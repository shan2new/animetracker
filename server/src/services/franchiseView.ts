import { partKindForFormat } from '../grouping/partKind.js'
import type { MediaFormat } from '../anilist/types.js'
import { and, eq, inArray, sql } from 'drizzle-orm'
import { db } from '../db/index.js'
import { franchise, franchiseMember, media, progress, subscriptions } from '../db/schema.js'
import type { PartKind } from '../grouping/partKind.js'
import type {
  Airing,
  EpisodeMeta,
  Franchise,
  FranchisePart,
  FranchiseSummary,
  LibraryFranchise,
  MediaSource,
  ReleasePrecision,
  WatchStatus,
} from '../types/api.js'
import { stripHtml } from '../util/text.js'

const D = 86_400_000
const KIND_ORDER: PartKind[] = ['season', 'movie', 'ova', 'ona', 'special', 'music']

/** Latest aired episode number from a dated episode list, or null when the list carries no dates
 *  at all (AniList `streamingEpisodes` have titles/thumbnails but never air dates). */
function latestAiredFromEpisodes(episodes: EpisodeMeta[], nowMs: number): number | null {
  let dated = false
  let latest = 0
  for (const e of episodes) {
    if (e.airDate == null) continue
    dated = true
    if (e.airDate <= nowMs && e.number > latest) latest = e.number
  }
  return dated ? latest : null
}

/**
 * How many episodes of a part are actually out. Pure so it can be unit-tested (see
 * `franchiseView.test.ts`); everything it needs comes from the media row, never from the user.
 *
 * The tricky case is RELEASING with **no** next slot — reachable on both sources: TMDB nulls
 * `next_episode_to_air.air_date` while the season still derives as RELEASING, and AniList leaves a
 * window between a finale airing and `status` flipping to FINISHED. The old fallback there was the
 * user's own `watched` count, which is not evidence of anything: a fresh subscriber saw every
 * episode as un-aired ("upcoming", progress 0), and a partway viewer got a season header claiming
 * they were caught up. Derive it from the episode list when it is dated, else from the catalogue's
 * total — never from progress.
 */
export function deriveAiredEpisodes(m: {
  status: string | null
  totalEpisodes: number
  next: { episode: number } | null
  episodes: EpisodeMeta[]
  nowMs: number
}): number {
  // An announced part has aired NOTHING, whatever episode count the catalogue advertises for it.
  // TMDB publishes `episode_count` for announced seasons, so a One Piece season that hadn't aired
  // an episode surfaced as a backlog ("S3 · 1 left") and lost its premiere-date treatment.
  if (m.status === 'NOT_YET_RELEASED') return 0
  if (m.next) return Math.max(0, m.next.episode - 1)
  if (m.status === 'RELEASING') return latestAiredFromEpisodes(m.episodes, m.nowMs) ?? m.totalEpisodes
  return m.totalEpisodes
}

/** Schedule's window, in days either side of now. A day wider than the client's own −7…+14 so a
 *  device at UTC±14 never sees an edge day arrive undated; the client windows precisely. */
export const SCHEDULE_WINDOW = { backDays: 8, aheadDays: 15 } as const

/**
 * Every dated episode of a part inside Schedule's window, oldest first — the per-episode facts a
 * calendar needs, without shipping the whole list on the library payload.
 *
 * Three sources of a date, merged and de-duplicated by episode number: the dated episode list
 * (TMDB always; AniList once `backfill-episodes` has run), the catalogue's own next slot (AniList
 * always has one while releasing, even with no per-episode dates), and `lastAiredAt` for the
 * latest aired episode (so an un-backfilled AniList part still puts its most recent episode on
 * the calendar). The list wins on a conflict: it is the only one of the three that is per-episode.
 * Pure so it can be unit-tested (see `franchiseView.test.ts`).
 */
export function airingsWindow(m: {
  episodes: EpisodeMeta[]
  next: { episode: number; airingAt: number } | null
  airedEpisodes: number
  lastAiredAt: number | null
  nowMs: number
}): Airing[] {
  const lo = m.nowMs - SCHEDULE_WINDOW.backDays * D
  const hi = m.nowMs + SCHEDULE_WINDOW.aheadDays * D
  const byEpisode = new Map<number, number>()
  const consider = (episode: number, at: number | null | undefined) => {
    if (at == null || at <= 0 || episode <= 0) return
    if (at < lo || at > hi) return
    if (!byEpisode.has(episode)) byEpisode.set(episode, at)
  }
  for (const e of m.episodes) consider(e.number, e.airDate)
  if (m.next) consider(m.next.episode, m.next.airingAt * 1000)
  if (m.airedEpisodes > 0) consider(m.airedEpisodes, m.lastAiredAt)
  return [...byEpisode.entries()]
    .map(([episode, at]) => ({ episode, at }))
    .sort((a, b) => a.at - b.at || a.episode - b.episode)
}

type MediaRow = typeof media.$inferSelect
type MemberRow = typeof franchiseMember.$inferSelect
type FranchiseRow = typeof franchise.$inferSelect

/**
 * State the precision of a next-release instant instead of leaving the client to infer it from
 * `source`. AniList publishes a real broadcast instant; TMDB publishes a calendar date that the TV
 * sync synthesizes to 17:00 UTC, so its clock half is not a fact and must never be rendered.
 */
function releasePrecision(nextAiringAt: number | null, source: MediaSource): ReleasePrecision {
  if (nextAiringAt == null) return { precision: 'unknown', at: null, date: null }
  if (source === 'tmdb') {
    return { precision: 'date_only', at: nextAiringAt, date: new Date(nextAiringAt).toISOString().slice(0, 10) }
  }
  return { precision: 'exact', at: nextAiringAt, date: null }
}

/** Derive a FranchisePart's airing fields from a media row + the user's progress. Mirrors legacy `toShow`.
 *  `opts.episodes` includes the full per-episode list (detail only; omitted from lean list payloads). */
function toPart(
  m: MediaRow,
  member: MemberRow,
  watched: number,
  source: MediaSource,
  opts?: { episodes?: boolean },
): FranchisePart {
  const title = m.titleEnglish || m.titleRomaji || `Anime #${m.id}`
  const isReleasing = m.status === 'RELEASING'
  const total = m.episodes ?? 0
  const next = m.nextAiringEpisode && m.nextAiringEpisode.airingAt > 0 ? m.nextAiringEpisode : null
  const eps = m.episodesList ?? []
  const airedEpisodes = deriveAiredEpisodes({
    status: m.status,
    totalEpisodes: total,
    next,
    episodes: eps,
    nowMs: Date.now(),
  })
  const nextAiringAt = next ? next.airingAt * 1000 : null
  const release = releasePrecision(nextAiringAt, source)
  const lastAiredAt =
    m.lastAiredAt != null && m.lastAiredAt > 0
      ? m.lastAiredAt
      : next && next.episode > 1
        ? next.airingAt * 1000 - 7 * D
        : null

  // Episodes sharing the exact next airing instant ⇒ a same-day multi-episode / full-season drop.
  const nextAiringCount = nextAiringAt != null ? eps.filter((e) => e.airDate === nextAiringAt).length : 0
  const airings = airingsWindow({ episodes: eps, next, airedEpisodes, lastAiredAt, nowMs: Date.now() })

  return {
    mediaId: m.id,
    kind: member.partKind as PartKind,
    sequence: member.sequence,
    label: member.label ?? title,
    title,
    cover: m.cover ?? '',
    // Keep artwork semantics honest. A portrait cover is not a landscape banner; clients need
    // the distinction to choose a composition that does not crop the subject into a wide slot.
    banner: m.banner ?? '',
    format: m.format,
    status: m.status,
    isReleasing,
    totalEpisodes: total,
    airedEpisodes,
    nextEpisodeNumber: next?.episode ?? null,
    nextAiringAt,
    release,
    lastAiredAt,
    synopsis: stripHtml(m.description),
    genres: (m.genres ?? []).slice(0, 4),
    progress: watched,
    year: m.seasonYear ?? null,
    studios: m.studios ?? [],
    nextAiringCount,
    episodes: opts?.episodes ? eps : [],
    airings,
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
  sub: { status: WatchStatus; addedAt: number } | null,
  opts?: { episodes?: boolean },
): Franchise {
  const source: MediaSource = (f.source as MediaSource) ?? 'anilist'
  const parts = sortParts(
    mems
      .map((mem) => {
        const m = mediaById.get(mem.mediaId)
        return m ? toPart(m, mem, watchedById.get(mem.mediaId) ?? 0, source, opts) : null
      })
      .filter((p): p is FranchisePart => p !== null),
  )

  const partCounts: Partial<Record<PartKind, number>> = {}
  for (const p of parts) partCounts[p.kind] = (partCounts[p.kind] ?? 0) + 1

  // Franchise-level meta for the detail header: premiere year (earliest dated part) + the primary
  // installment's studios/networks (fall back to the first part that has any).
  const primary = f.primaryMediaId != null ? mediaById.get(f.primaryMediaId) : undefined
  // Premiere year = the earliest dated SEASON or MOVIE; an OVA or music video dated before the
  // first season must not become the work's year.
  const episodic = parts.filter((p) => p.kind === 'season' || p.kind === 'movie')
  const years = (episodic.length ? episodic : parts).map((p) => p.year).filter((y): y is number => y != null)
  const year = years.length ? Math.min(...years) : (primary?.seasonYear ?? null)
  const studios = (primary?.studios?.length ? primary.studios : parts.find((p) => p.studios.length > 0)?.studios) ?? []

  return {
    id: f.id,
    source,
    title: f.title,
    cover: f.cover ?? '',
    banner: f.banner ?? '',
    synopsis: f.description ?? '',
    genres: f.genres ?? [],
    isReleasing: parts.some((p) => p.isReleasing),
    partCounts,
    parts,
    subscription: sub,
    upcoming: f.upcoming ?? null,
    year,
    studios,
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

  let sub: { status: WatchStatus; addedAt: number } | null = null
  if (userId) {
    const [s] = await db
      .select()
      .from(subscriptions)
      .where(and(eq(subscriptions.userId, userId), eq(subscriptions.franchiseId, franchiseId)))
      .limit(1)
    if (s) sub = { status: s.status as WatchStatus, addedAt: s.createdAt.getTime() }
  }

  // Detail is the only response that ships the full per-episode list.
  return buildFranchise(f, members, mediaById, watchedById, sub, { episodes: true })
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
      let minYear: number | null = null
      for (const mem of mems) {
        const m = mediaById.get(mem.mediaId)
        if (!m) continue
        if (m.status === 'RELEASING') releasing = true
        const next = m.nextAiringEpisode && m.nextAiringEpisode.airingAt > 0 ? m.nextAiringEpisode.airingAt * 1000 : null
        if (next && (nextAiringAt == null || next < nextAiringAt)) nextAiringAt = next
        if (m.seasonYear != null && (minYear == null || m.seasonYear < minYear)) minYear = m.seasonYear
      }
      const primary = f.primaryMediaId != null ? mediaById.get(f.primaryMediaId) : undefined
      return {
        id: f.id,
        source: (f.source as MediaSource) ?? 'anilist',
        title: f.title,
        cover: f.cover ?? '',
        banner: f.banner ?? '',
        isReleasing: releasing,
        // The count Detail prints under "Seasons & movies": episodic members only, never OVAs,
        // specials or music videos — Search and Detail must agree.
        partCount: mems.filter((mem) => {
          const m = mediaById.get(mem.mediaId)
          if (!m) return false
          const kind = partKindForFormat((m.format as MediaFormat | null) ?? null)
          return kind === 'season' || kind === 'movie'
        }).length,
        nextAiringAt,
        upcoming: f.upcoming ?? null,
        year: primary?.seasonYear ?? minYear,
      }
    })
    .sort((a, b) => (order.get(a.id) ?? 0) - (order.get(b.id) ?? 0))
}

/**
 * Trending franchises ranked by the catalogue's actual trend signal.
 *
 * `franchise.updatedAt` is a grouping/cache timestamp, not audience interest. Search lazily
 * groups catalogue misses, so ordering by it let the most recent query overwrite the zero-state
 * shelf (for example an "f" search became the next user's "Trending now"). AniList's persisted
 * `media.trending` score is the correct product fact; popularity is only a deterministic tie-break.
 */
export async function getTrendingFranchises(limit: number): Promise<FranchiseSummary[]> {
  const rows = await db
    .select({ id: franchise.id })
    .from(franchise)
    .innerJoin(franchiseMember, eq(franchiseMember.franchiseId, franchise.id))
    .innerJoin(media, eq(media.id, franchiseMember.mediaId))
    .groupBy(franchise.id)
    .orderBy(
      sql`max(${media.trending}) desc nulls last`,
      sql`max(${media.popularity}) desc nulls last`,
      sql`max(${franchise.updatedAt}) desc`,
    )
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
    const fr = buildFranchise(f, mems, mediaById, watchedById, { status, addedAt: s.createdAt.getTime() })
    const behind = fr.parts.reduce((acc, p) => acc + episodesBehind(p), 0)
    // newParts: members added since the user last opened the app.
    const newParts = mems.filter((m) => m.addedAt.getTime() > lastOpenedAt).length
    out.push({ ...fr, status, behind, newParts })
  }
  return out
}
