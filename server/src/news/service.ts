import { and, eq, inArray } from 'drizzle-orm'
import { db } from '../db/index.js'
import { announcements, franchise, franchiseMember, media, notifications, subscriptions } from '../db/schema.js'
import { env } from '../env.js'
import type { FranchiseUpcoming } from '../types/api.js'
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

  const result = await researchFranchiseNews({ title: f.title, knownParts, current: f.upcoming ?? null, knownAnnouncements })
  if (!result) return { checked: false, notified: 0 }

  const upcoming: FranchiseUpcoming = { ...result, checked: new Date().toISOString() }
  await db.update(franchise).set({ upcoming }).where(eq(franchise.id, franchiseId))

  if (!isNoteworthy(result.status) || !result.next.trim()) return { checked: true, notified: 0 }

  const key = dedupeKey(result.next)
  const existing = priorRows.find((a) => sameInstallment(a.dedupeKey, key))

  const newRank = STATUS_RANK[result.status] ?? 0
  const oldRank = existing ? (STATUS_RANK[existing.status] ?? 0) : 0

  let event: NewsEvent | null = null
  if (!existing) event = 'new'
  else if (newRank > oldRank) event = 'upgraded'
  else if (newRank === oldRank && !isConcreteRelease(existing.release) && isConcreteRelease(result.release)) event = 'dated'

  let announcementId: string
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

  if (!event) return { checked: true, notified: 0 }

  const { kind, body } = notificationText(result, event)
  const notified = await fanOut(franchiseId, f.title, announcementId, kind, body)
  console.log(`[news] "${f.title}": ${event} → notified ${notified} subscriber(s): ${body}`)
  return { checked: true, notified }
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
