import { and, desc, eq, inArray } from 'drizzle-orm'
import { db } from '../db/index.js'
import { franchise, franchiseMember, media, progress, subscriptions } from '../db/schema.js'
import type { PartKind } from '../grouping/partKind.js'
import type { Franchise, FranchisePart, FranchiseSummary, LibraryFranchise, WatchStatus } from '../types/api.js'
import { stripHtml } from '../util/text.js'

const D = 86_400_000
const KIND_ORDER: PartKind[] = ['season', 'movie', 'ova', 'ona', 'special', 'music']

type MediaRow = typeof media.$inferSelect
type MemberRow = typeof franchiseMember.$inferSelect
type FranchiseRow = typeof franchise.$inferSelect

/** Derive a FranchisePart's airing fields from a media row + the user's progress. Mirrors legacy `toShow`. */
function toPart(m: MediaRow, member: MemberRow, watched: number): FranchisePart {
  const title = m.titleEnglish || m.titleRomaji || `Anime #${m.id}`
  const isReleasing = m.status === 'RELEASING'
  const total = m.episodes ?? 0
  const next = m.nextAiringEpisode && m.nextAiringEpisode.airingAt > 0 ? m.nextAiringEpisode : null
  const airedEpisodes = next ? Math.max(0, next.episode - 1) : isReleasing ? watched : total
  const nextAiringAt = next ? next.airingAt * 1000 : null
  const lastAiredAt =
    m.lastAiredAt != null && m.lastAiredAt > 0
      ? m.lastAiredAt
      : next && next.episode > 1
        ? next.airingAt * 1000 - 7 * D
        : null

  return {
    mediaId: m.id,
    kind: member.partKind as PartKind,
    sequence: member.sequence,
    label: member.label ?? title,
    title,
    cover: m.cover ?? '',
    banner: m.banner || m.cover || '',
    format: m.format,
    status: m.status,
    isReleasing,
    totalEpisodes: total,
    airedEpisodes,
    nextEpisodeNumber: next?.episode ?? null,
    nextAiringAt,
    lastAiredAt,
    synopsis: stripHtml(m.description),
    genres: (m.genres ?? []).slice(0, 4),
    progress: watched,
  }
}

function sortParts(parts: FranchisePart[]): FranchisePart[] {
  return parts.sort((a, b) => {
    const k = KIND_ORDER.indexOf(a.kind) - KIND_ORDER.indexOf(b.kind)
    return k !== 0 ? k : a.sequence - b.sequence
  })
}

/** Unwatched aired episodes for a part (0 unless releasing). */
function episodesBehind(p: FranchisePart): number {
  return p.isReleasing ? Math.max(0, p.airedEpisodes - p.progress) : 0
}

async function loadProgressMap(userId: string | undefined, mediaIds: number[]): Promise<Map<number, number>> {
  const map = new Map<number, number>()
  if (!userId || mediaIds.length === 0) return map
  const rows = await db
    .select()
    .from(progress)
    .where(and(eq(progress.userId, userId), inArray(progress.mediaId, mediaIds)))
  for (const r of rows) map.set(r.mediaId, r.episodesWatched)
  return map
}

/** Assemble a Franchise from already-loaded rows (no DB access). Shared by detail + library. */
function buildFranchise(
  f: FranchiseRow,
  mems: MemberRow[],
  mediaById: Map<number, MediaRow>,
  watchedById: Map<number, number>,
  sub: { status: WatchStatus } | null,
): Franchise {
  const parts = sortParts(
    mems
      .map((mem) => {
        const m = mediaById.get(mem.mediaId)
        return m ? toPart(m, mem, watchedById.get(mem.mediaId) ?? 0) : null
      })
      .filter((p): p is FranchisePart => p !== null),
  )

  const partCounts: Partial<Record<PartKind, number>> = {}
  for (const p of parts) partCounts[p.kind] = (partCounts[p.kind] ?? 0) + 1

  return {
    id: f.id,
    title: f.title,
    cover: f.cover ?? '',
    banner: f.banner || f.cover || '',
    synopsis: f.description ?? '',
    genres: f.genres ?? [],
    isReleasing: parts.some((p) => p.isReleasing),
    partCounts,
    parts,
    subscription: sub,
  }
}

/** Full franchise detail with parts + (optional) the user's progress and subscription. */
export async function getFranchise(franchiseId: string, userId?: string): Promise<Franchise | null> {
  const [f] = await db.select().from(franchise).where(eq(franchise.id, franchiseId)).limit(1)
  if (!f) return null

  const members = await db.select().from(franchiseMember).where(eq(franchiseMember.franchiseId, franchiseId))
  const mediaIds = members.map((m) => m.mediaId)
  const mediaRows = mediaIds.length ? await db.select().from(media).where(inArray(media.id, mediaIds)) : []
  const mediaById = new Map(mediaRows.map((m) => [m.id, m]))
  const watchedById = await loadProgressMap(userId, mediaIds)

  let sub: { status: WatchStatus } | null = null
  if (userId) {
    const [s] = await db
      .select()
      .from(subscriptions)
      .where(and(eq(subscriptions.userId, userId), eq(subscriptions.franchiseId, franchiseId)))
      .limit(1)
    if (s) sub = { status: s.status as WatchStatus }
  }

  return buildFranchise(f, members, mediaById, watchedById, sub)
}

/** Build a list of FranchiseSummary for the given franchise ids (trending/search). */
export async function getSummaries(franchiseIds: string[]): Promise<FranchiseSummary[]> {
  if (franchiseIds.length === 0) return []
  const fr = await db.select().from(franchise).where(inArray(franchise.id, franchiseIds))
  const members = await db.select().from(franchiseMember).where(inArray(franchiseMember.franchiseId, franchiseIds))
  const mediaIds = members.map((m) => m.mediaId)
  const mediaRows = mediaIds.length ? await db.select().from(media).where(inArray(media.id, mediaIds)) : []
  const mediaById = new Map(mediaRows.map((m) => [m.id, m]))

  const byFranchise = new Map<string, MemberRow[]>()
  for (const m of members) {
    const arr = byFranchise.get(m.franchiseId) ?? []
    arr.push(m)
    byFranchise.set(m.franchiseId, arr)
  }

  const order = new Map(franchiseIds.map((id, i) => [id, i]))
  return fr
    .map((f): FranchiseSummary => {
      const mems = byFranchise.get(f.id) ?? []
      let nextAiringAt: number | null = null
      let releasing = false
      for (const mem of mems) {
        const m = mediaById.get(mem.mediaId)
        if (!m) continue
        if (m.status === 'RELEASING') releasing = true
        const next = m.nextAiringEpisode && m.nextAiringEpisode.airingAt > 0 ? m.nextAiringEpisode.airingAt * 1000 : null
        if (next && (nextAiringAt == null || next < nextAiringAt)) nextAiringAt = next
      }
      return {
        id: f.id,
        title: f.title,
        cover: f.cover ?? '',
        banner: f.banner || f.cover || '',
        isReleasing: releasing,
        partCount: mems.length,
        nextAiringAt,
      }
    })
    .sort((a, b) => (order.get(a.id) ?? 0) - (order.get(b.id) ?? 0))
}

/** Trending franchises, most-recently-grouped first (proxy for hotness for now). */
export async function getTrendingFranchises(limit: number): Promise<FranchiseSummary[]> {
  const rows = await db
    .select({ id: franchise.id })
    .from(franchise)
    .orderBy(desc(franchise.updatedAt))
    .limit(limit)
  return getSummaries(rows.map((r) => r.id))
}

/** The authenticated user's library: full franchises + status + behind + newParts. */
export async function getLibrary(userId: string, lastOpenedAt: number): Promise<LibraryFranchise[]> {
  const subs = await db.select().from(subscriptions).where(eq(subscriptions.userId, userId))
  if (subs.length === 0) return []

  const franchiseIds = subs.map((s) => s.franchiseId)
  const statusById = new Map(subs.map((s) => [s.franchiseId, s.status as WatchStatus]))

  // Batch every dependency in a fixed number of queries — no per-subscription round-trips.
  const frRows = await db.select().from(franchise).where(inArray(franchise.id, franchiseIds))
  const members = await db.select().from(franchiseMember).where(inArray(franchiseMember.franchiseId, franchiseIds))
  const mediaIds = members.map((m) => m.mediaId)
  const mediaRows = mediaIds.length ? await db.select().from(media).where(inArray(media.id, mediaIds)) : []
  const watchedById = await loadProgressMap(userId, mediaIds)

  const frById = new Map(frRows.map((f) => [f.id, f]))
  const mediaById = new Map(mediaRows.map((m) => [m.id, m]))
  const membersByFranchise = new Map<string, MemberRow[]>()
  for (const mem of members) {
    const arr = membersByFranchise.get(mem.franchiseId) ?? []
    arr.push(mem)
    membersByFranchise.set(mem.franchiseId, arr)
  }

  // Iterate subs to preserve the user's subscription ordering.
  const out: LibraryFranchise[] = []
  for (const s of subs) {
    const f = frById.get(s.franchiseId)
    if (!f) continue
    const mems = membersByFranchise.get(s.franchiseId) ?? []
    const status = statusById.get(s.franchiseId) ?? 'planned'
    const fr = buildFranchise(f, mems, mediaById, watchedById, { status })
    const behind = fr.parts.reduce((acc, p) => acc + episodesBehind(p), 0)
    // newParts: members added since the user last opened the app.
    const newParts = mems.filter((m) => m.addedAt.getTime() > lastOpenedAt).length
    out.push({ ...fr, status, behind, newParts })
  }
  return out
}
