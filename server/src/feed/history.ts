import { asc, desc, eq, inArray } from 'drizzle-orm'
import { db } from '../db/index.js'
import { announcementEvidence, announcementObservations, announcements, franchise } from '../db/schema.js'
import { dedupeKey, sameInstallment } from '../news/installment.js'
import type { AnnouncementEvidence, AnnouncementEvidenceTier, FranchiseUpcoming } from '../types/api.js'
import type { ComposeAnnouncement, ComposeEvidence, ComposeObservation } from './compose.js'
import { sanitizeEvidence, TIER_RANK } from './evidence.js'

// The research history the composer reads: every observation (FULL history — dating a post from a
// capped page let its date drift as rows aged out), each observation's evidence (https only), and
// the announcement rows. Three queries for any number of franchises; no N+1. A fourth runs only
// when a franchise has announcements but no observations (research from before migration 0008 —
// see `legacyObservation`).

const tierOf = (tier: string): AnnouncementEvidenceTier =>
  Object.hasOwn(TIER_RANK, tier) ? (tier as AnnouncementEvidenceTier) : 'unknown'

/** The research statuses that are news (the composer's KIND map, feed/compose.ts). */
const NEWS_STATUSES: ReadonlySet<string> = new Set(['upcoming_dated', 'announced', 'announced_no_date', 'rumored'])

/**
 * The one observation a franchise researched before observations existed (migration 0008, 3 Sep,
 * no backfill) stands on: its stored `upcoming` — when that is news and an announcement row names
 * the same installment. Dated at the announcement's first sighting, so the post keeps the id
 * (`news:<announcement id>`) and the date it will have once research observes it for real.
 * Null when there is nothing to stand on.
 */
export function legacyObservation(
  upcoming: FranchiseUpcoming | null | undefined,
  rows: readonly ComposeAnnouncement[],
): ComposeObservation | null {
  if (!upcoming || !NEWS_STATUSES.has(upcoming.status)) return null
  const next = typeof upcoming.next === 'string' ? upcoming.next : ''
  if (next.trim() === '') return null
  const key = dedupeKey(next)
  const match = rows.find((a) => sameInstallment(a.dedupeKey, key))
  if (!match) return null
  // The stored evidence list, else the bare `source` (as the write path does for an agent that
  // returned no list); https only, the official claim verified, like every other row.
  const stored: AnnouncementEvidence[] = Array.isArray(upcoming.evidence) && upcoming.evidence.length > 0
    ? upcoming.evidence
    : typeof upcoming.source === 'string'
      ? [{ url: upcoming.source, publisher: null, publishedAt: null, tier: 'unknown', primary: false }]
      : []
  const evidence: ComposeEvidence[] = sanitizeEvidence(
    stored
      .filter((e) => e && typeof e.url === 'string')
      .map((e) => ({
        url: e.url,
        publisher: typeof e.publisher === 'string' ? e.publisher : null,
        publishedAt: typeof e.publishedAt === 'string' ? e.publishedAt : null,
        tier: tierOf(String(e.tier)),
        primary: e.primary === true,
      })),
  )
  return {
    id: `legacy:${match.id}`,
    announcementId: match.id,
    status: upcoming.status,
    next,
    release: typeof upcoming.release === 'string' ? upcoming.release : '',
    note: typeof upcoming.note === 'string' ? upcoming.note : null,
    observedAt: match.firstSeenAt,
    evidence,
  }
}

export async function loadResearchHistory(franchiseIds: string[]): Promise<{
  observations: Map<string, ComposeObservation[]>
  announcements: Map<string, ComposeAnnouncement[]>
}> {
  const observations = new Map<string, ComposeObservation[]>()
  const byAnnouncement = new Map<string, ComposeAnnouncement[]>()
  const ids = [...new Set(franchiseIds)]
  if (ids.length === 0) return { observations, announcements: byAnnouncement }

  const [observationRows, evidenceRows, announcementRows] = await Promise.all([
    // Newest first per franchise (announcement_observations_franchise_idx).
    db
      .select({
        id: announcementObservations.id,
        franchiseId: announcementObservations.franchiseId,
        announcementId: announcementObservations.announcementId,
        status: announcementObservations.status,
        next: announcementObservations.next,
        release: announcementObservations.release,
        note: announcementObservations.note,
        observedAt: announcementObservations.observedAt,
      })
      .from(announcementObservations)
      .where(inArray(announcementObservations.franchiseId, ids))
      .orderBy(
        asc(announcementObservations.franchiseId),
        desc(announcementObservations.observedAt),
        desc(announcementObservations.id),
      ),
    // A join rather than a giant IN list of observation ids.
    db
      .select({
        observationId: announcementEvidence.observationId,
        url: announcementEvidence.url,
        publisher: announcementEvidence.publisher,
        publishedAt: announcementEvidence.publishedAt,
        tier: announcementEvidence.tier,
        primary: announcementEvidence.primary,
      })
      .from(announcementEvidence)
      .innerJoin(announcementObservations, eq(announcementObservations.id, announcementEvidence.observationId))
      .where(inArray(announcementObservations.franchiseId, ids))
      .orderBy(asc(announcementEvidence.observationId), asc(announcementEvidence.url)),
    db
      .select({
        id: announcements.id,
        franchiseId: announcements.franchiseId,
        dedupeKey: announcements.dedupeKey,
        status: announcements.status,
        next: announcements.next,
        firstSeenAt: announcements.firstSeenAt,
      })
      .from(announcements)
      .where(inArray(announcements.franchiseId, ids))
      .orderBy(asc(announcements.franchiseId), asc(announcements.firstSeenAt), asc(announcements.id)),
  ])

  const evidenceByObservation = new Map<string, ComposeEvidence[]>()
  for (const row of evidenceRows) {
    const list = evidenceByObservation.get(row.observationId) ?? []
    list.push({
      url: row.url,
      publisher: row.publisher,
      publishedAt: row.publishedAt,
      tier: tierOf(row.tier),
      primary: row.primary,
    })
    evidenceByObservation.set(row.observationId, list)
  }

  for (const row of observationRows) {
    const list = observations.get(row.franchiseId) ?? []
    list.push({
      id: row.id,
      announcementId: row.announcementId,
      status: row.status,
      next: row.next,
      release: row.release,
      note: row.note,
      observedAt: row.observedAt.getTime(),
      evidence: sanitizeEvidence(evidenceByObservation.get(row.id) ?? []),
    })
    observations.set(row.franchiseId, list)
  }

  for (const row of announcementRows) {
    const list = byAnnouncement.get(row.franchiseId) ?? []
    list.push({
      id: row.id,
      dedupeKey: row.dedupeKey,
      status: row.status,
      next: row.next,
      firstSeenAt: row.firstSeenAt.getTime(),
    })
    byAnnouncement.set(row.franchiseId, list)
  }

  // Researched before observations existed: stand the post on the stored `upcoming`.
  const legacy = ids.filter((id) => !observations.has(id) && byAnnouncement.has(id))
  if (legacy.length > 0) {
    const rows = await db
      .select({ id: franchise.id, upcoming: franchise.upcoming })
      .from(franchise)
      .where(inArray(franchise.id, legacy))
    for (const row of rows) {
      const synthetic = legacyObservation(row.upcoming, byAnnouncement.get(row.id) ?? [])
      if (synthetic) observations.set(row.id, [synthetic])
    }
  }

  return { observations, announcements: byAnnouncement }
}
