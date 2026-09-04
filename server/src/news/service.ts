import { desc, eq, inArray } from 'drizzle-orm'
import { db } from '../db/index.js'
import {
  announcementEvidence,
  announcementObservations,
  announcements,
  franchise,
  franchiseMember,
  media,
  notifications,
  subscriptions,
} from '../db/schema.js'
import { env } from '../env.js'
import type { AnnouncementEvidence, AnnouncementObservationView, FranchiseUpcoming } from '../types/api.js'
import { BoundedTaskQueue } from '../util/taskQueue.js'
import { researchFranchiseNews, type NewsResult } from './agent.js'

// Only forward progress through this ladder produces a notification; the agent re-reporting
// the same news (or waffling back down to a rumor) just bumps lastSeenAt.
const STATUS_RANK: Record<string, number> = {
  rumored: 1,
  announced_no_date: 2,
  announced: 3,
  upcoming_dated: 4,
}

const isNoteworthy = (status: string): boolean => status in STATUS_RANK

// Detail reads may opportunistically warm missing/stale news, but web-research agents are slow and
// expensive work. One worker plus a hard queue cap keeps ordinary API traffic from multiplying it.
const onDemandNews = new BoundedTaskQueue(1, 8, (key, error) => {
  console.warn(`[news] on-demand refresh failed (${key}):`, error instanceof Error ? error.message : error)
})
const onDemandAttemptedAt = new Map<string, number>()

export function newsNeedsRefresh(
  current: Partial<Pick<FranchiseUpcoming, 'checked' | 'source'>> | null | undefined,
  nowMs = Date.now(),
  intervalHours = env.NEWS_CHECK_INTERVAL_HOURS,
): boolean {
  // AniList/TMDB catalogue pages prove the immediate fact, but they are intentionally only a
  // fallback. Enrich them once with an actual announcement/report even when the catalogue row was
  // fetched moments ago.
  if (
    current?.source?.startsWith('https://anilist.co/') ||
    current?.source?.startsWith('https://www.themoviedb.org/')
  ) {
    return true
  }
  if (!current?.checked) return true
  const checkedAt = Date.parse(current.checked)
  return !Number.isFinite(checkedAt) || checkedAt < nowMs - intervalHours * 3_600_000
}

/**
 * Schedule stale-while-revalidate news research without extending detail-request latency.
 * Repeated views single-flight while queued and remain throttled for one normal check interval even
 * if research fails, so a title with no discoverable news cannot spawn an agent on every request.
 */
export function enqueueFranchiseNewsRefresh(
  franchiseId: string,
  current: Partial<Pick<FranchiseUpcoming, 'checked' | 'source'>> | null | undefined,
): boolean {
  if (env.NEWS_AGENT_DISABLED || !newsNeedsRefresh(current)) return false
  const now = Date.now()
  const lastAttempt = onDemandAttemptedAt.get(franchiseId)
  if (lastAttempt != null && lastAttempt >= now - env.NEWS_CHECK_INTERVAL_HOURS * 3_600_000) return false

  const task = onDemandNews.enqueue(`franchise:${franchiseId}`, async () => {
    await refreshFranchiseNews(franchiseId)
  })
  if (!task.accepted) return false
  onDemandAttemptedAt.set(franchiseId, now)
  // This is a bounded process-local throttle (the catalogue is currently small); shed oldest keys
  // if it grows so a long-running server never accumulates an unbounded access history.
  if (onDemandAttemptedAt.size > 500) onDemandAttemptedAt.delete(onDemandAttemptedAt.keys().next().value!)
  return true
}

/** Stable per-installment key so "Season 4" / "season 4!" / "SEASON 4" collapse to one row. */
const dedupeKey = (next: string): string => next.toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim()

/**
 * Whether two normalized keys name the same installment. Exact match, or one key's tokens
 * fully contained in the other's — the agent rewording "Season 4" as "Season 4: The Culling
 * Game Part 2" across runs must not create a second announcement.
 */
function sameInstallment(a: string, b: string): boolean {
  if (a === b) return true
  const ta = new Set(a.split(' ').filter(Boolean))
  const tb = new Set(b.split(' ').filter(Boolean))
  const [small, big] = ta.size <= tb.size ? [ta, tb] : [tb, ta]
  if (small.size === 0) return false
  for (const t of small) if (!big.has(t)) return false
  return true
}

const isConcreteRelease = (release: string): boolean => {
  const r = release.trim().toLowerCase()
  return r !== '' && r !== 'tba' && r !== 'tbd' && r !== 'unknown'
}

type NewsEvent = 'new' | 'upgraded' | 'dated'

function notificationText(result: NewsResult, event: NewsEvent): { kind: string; body: string } {
  const withRelease = isConcreteRelease(result.release) ? ` — ${result.release}` : ''
  if (event === 'dated') return { kind: 'news_dated', body: `${result.next} — release set for ${result.release}` }
  switch (result.status) {
    case 'rumored':
      return { kind: 'news_rumored', body: `${result.next} rumored${withRelease}` }
    case 'announced_no_date':
      return { kind: 'news_announced', body: `${result.next} announced — date TBA` }
    case 'announced':
      return { kind: 'news_announced', body: `${result.next} announced${withRelease}` }
    default: // upcoming_dated
      return { kind: 'news_dated', body: `${result.next} arrives ${result.release}` }
  }
}

/** Insert one notification per subscriber of the franchise. Returns how many were created. */
async function fanOut(
  franchiseId: string,
  franchiseTitle: string,
  announcementId: string,
  kind: string,
  body: string,
): Promise<number> {
  const subs = await db
    .select({ userId: subscriptions.userId })
    .from(subscriptions)
    .where(eq(subscriptions.franchiseId, franchiseId))
  if (subs.length === 0) return 0
  await db.insert(notifications).values(
    subs.map((s) => ({
      userId: s.userId,
      franchiseId,
      announcementId,
      kind,
      title: franchiseTitle,
      body,
    })),
  )
  return subs.length
}

/**
 * Research one franchise, persist the result on franchise.upcoming, and — when the news is
 * genuinely new (first sighting, status upgrade, or a TBA release becoming a real date) —
 * record an announcement and notify every subscriber.
 */
export async function refreshFranchiseNews(franchiseId: string): Promise<{ checked: boolean; notified: number }> {
  const [f] = await db.select().from(franchise).where(eq(franchise.id, franchiseId)).limit(1)
  if (!f) return { checked: false, notified: 0 }

  const members = await db
    .select({
      label: franchiseMember.label,
      titleEnglish: media.titleEnglish,
      titleRomaji: media.titleRomaji,
      format: media.format,
      status: media.status,
      seasonYear: media.seasonYear,
    })
    .from(franchiseMember)
    .innerJoin(media, eq(franchiseMember.mediaId, media.id))
    .where(eq(franchiseMember.franchiseId, franchiseId))

  const knownParts = members.map((m) => {
    const name = m.label || m.titleEnglish || m.titleRomaji || 'Unknown'
    const bits = [m.format, m.status, m.seasonYear].filter(Boolean).join(', ')
    return bits ? `${name} (${bits})` : name
  })

  const priorRows = await db.select().from(announcements).where(eq(announcements.franchiseId, franchiseId))
  const knownAnnouncements = priorRows.map((a) => `${a.next} (${a.status})`)

  const result = await researchFranchiseNews({
    title: f.title,
    catalogueSource: f.source === 'tmdb' ? 'tmdb' : 'anilist',
    knownParts,
    current: f.upcoming ?? null,
    knownAnnouncements,
  })
  if (!result) return { checked: false, notified: 0 }

  const upcoming: FranchiseUpcoming = { ...result, checked: new Date().toISOString() }
  await db.update(franchise).set({ upcoming }).where(eq(franchise.id, franchiseId))

  const noteworthy = isNoteworthy(result.status) && !!result.next.trim()
  const key = noteworthy ? dedupeKey(result.next) : `__state__:${result.status}`
  const existing = noteworthy ? priorRows.find((a) => sameInstallment(a.dedupeKey, key)) : undefined
  let event: NewsEvent | null = null
  let announcementId: string | null = null
  if (noteworthy) {
    const newRank = STATUS_RANK[result.status] ?? 0
    const oldRank = existing ? (STATUS_RANK[existing.status] ?? 0) : 0
    if (!existing) event = 'new'
    else if (newRank > oldRank) event = 'upgraded'
    else if (newRank === oldRank && !isConcreteRelease(existing.release) && isConcreteRelease(result.release)) event = 'dated'

    if (!existing) {
      const [row] = await db
        .insert(announcements)
        .values({
          franchiseId,
          dedupeKey: key,
          status: result.status,
          next: result.next,
          release: result.release,
          note: result.note,
          source: result.source,
        })
        .returning({ id: announcements.id })
      announcementId = row!.id
    } else {
      // Never let a lower-confidence re-report downgrade a stored announcement.
      const advance = newRank >= oldRank
      await db
        .update(announcements)
        .set({
          lastSeenAt: new Date(),
          ...(advance
            ? { status: result.status, next: result.next, release: result.release, note: result.note, source: result.source }
            : {}),
        })
        .where(eq(announcements.id, existing.id))
      announcementId = existing.id
    }
  }

  const [observation] = await db
    .insert(announcementObservations)
    .values({
      franchiseId,
      announcementId,
      dedupeKey: key,
      status: result.status,
      next: result.next,
      release: result.release,
      note: result.note,
    })
    .returning({ id: announcementObservations.id })
  const evidence = normalizedEvidence(result)
  if (observation && evidence.length > 0) {
    await db.insert(announcementEvidence).values(evidence.map((item) => ({
      observationId: observation.id,
      ...item,
    }))).onConflictDoNothing()
  }

  if (!event || !announcementId) return { checked: true, notified: 0 }

  const { kind, body } = notificationText(result, event)
  const notified = await fanOut(franchiseId, f.title, announcementId, kind, body)
  console.log(`[news] "${f.title}": ${event} → notified ${notified} subscriber(s): ${body}`)
  return { checked: true, notified }
}

function normalizedEvidence(result: NewsResult): AnnouncementEvidence[] {
  const candidates: AnnouncementEvidence[] = result.evidence.length > 0
    ? result.evidence
    : result.source
      ? [{ url: result.source, publisher: null, publishedAt: null, tier: 'unknown', primary: false }]
      : []
  const byUrl = new Map<string, AnnouncementEvidence>()
  for (const item of candidates) if (!byUrl.has(item.url)) byUrl.set(item.url, item)
  return [...byUrl.values()].slice(0, 5)
}

/** Inspectable evidence history behind the latest one-line `upcoming` state. */
export async function listAnnouncementObservations(
  franchiseId: string,
  limit = 20,
): Promise<AnnouncementObservationView[]> {
  const rows = await db
    .select()
    .from(announcementObservations)
    .where(eq(announcementObservations.franchiseId, franchiseId))
    .orderBy(desc(announcementObservations.observedAt))
    .limit(limit)
  if (rows.length === 0) return []
  const evidence = await db
    .select()
    .from(announcementEvidence)
    .where(inArray(announcementEvidence.observationId, rows.map((row) => row.id)))
  const byObservation = new Map<string, AnnouncementEvidence[]>()
  for (const item of evidence) {
    const list = byObservation.get(item.observationId) ?? []
    list.push({
      url: item.url,
      publisher: item.publisher,
      publishedAt: item.publishedAt,
      tier: item.tier as AnnouncementEvidence['tier'],
      primary: item.primary,
    })
    byObservation.set(item.observationId, list)
  }
  return rows.map((row) => ({
    id: row.id,
    announcementId: row.announcementId,
    status: row.status,
    next: row.next,
    release: row.release,
    note: row.note,
    observedAt: row.observedAt.toISOString(),
    evidence: byObservation.get(row.id) ?? [],
  }))
}

/**
 * Daily pass over every franchise anyone is subscribed to. Franchises checked within the last
 * NEWS_CHECK_INTERVAL_HOURS are skipped; the rest are processed oldest-check-first, capped at
 * NEWS_MAX_FRANCHISES_PER_RUN, so a large backlog rotates through over successive runs.
 */
export async function refreshSubscribedNews(): Promise<{ checked: number; notified: number; skipped: number }> {
  const subbed = await db.selectDistinct({ franchiseId: subscriptions.franchiseId }).from(subscriptions)
  if (subbed.length === 0) return { checked: 0, notified: 0, skipped: 0 }

  const ids = subbed.map((s) => s.franchiseId)
  const rows = await db
    .select({ id: franchise.id, upcoming: franchise.upcoming })
    .from(franchise)
    .where(inArray(franchise.id, ids))

  const cutoff = Date.now() - env.NEWS_CHECK_INTERVAL_HOURS * 3_600_000
  const due = rows
    .map((r) => ({ id: r.id, checkedAt: r.upcoming?.checked ? Date.parse(r.upcoming.checked) || 0 : 0 }))
    .filter((r) => r.checkedAt < cutoff)
    .sort((a, b) => a.checkedAt - b.checkedAt)
    .slice(0, env.NEWS_MAX_FRANCHISES_PER_RUN)

  let checked = 0
  let notified = 0
  // Sequential on purpose: each check spawns an agent subprocess doing multi-turn web research.
  for (const { id } of due) {
    try {
      const r = await refreshFranchiseNews(id)
      if (r.checked) checked++
      notified += r.notified
    } catch (err) {
      console.warn(`[news] refresh failed for franchise ${id}:`, (err as Error).message)
    }
  }
  return { checked, notified, skipped: rows.length - due.length }
}
