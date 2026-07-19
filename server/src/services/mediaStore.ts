import { eq, inArray } from 'drizzle-orm'
import { fetchByIds } from '../anilist/client.js'
import type { AniListMedia } from '../anilist/types.js'
import { db } from '../db/index.js'
import { media, mediaRelations } from '../db/schema.js'
import type { EpisodeMeta } from '../types/api.js'

export type MediaRow = typeof media.$inferInsert

/** Strip AniList's "Episode 12 - " prefix from a streaming-episode title. */
function cleanEpisodeTitle(raw: string): string {
  const m = raw.match(/^\s*Episode\s+\d+\s*[-–:]\s*(.+)$/i)
  return (m?.[1] ?? raw).trim()
}

/**
 * Best-effort per-episode metadata for an AniList media, from `streamingEpisodes`. AniList exposes
 * no per-episode air date or overview; titles/thumbnails come as an ordered (but un-numbered) list,
 * so episodes are numbered by position. Sparse or empty for many titles — the client then falls
 * back to "Episode N", and the next-episode date badge uses the season-level `nextAiringAt`.
 */
function aniListEpisodes(m: AniListMedia): EpisodeMeta[] {
  const se = m.streamingEpisodes ?? []
  return se.map((e, i) => ({
    number: i + 1,
    title: e.title ? cleanEpisodeTitle(e.title) : null,
    airDate: null,
    overview: null,
    still: e.thumbnail ?? null,
    runtime: m.duration ?? null,
  }))
}

/** Studio names for an AniList media, preferring animation studios. */
function aniListStudios(m: AniListMedia): string[] {
  const nodes = m.studios?.nodes ?? []
  const anim = nodes.filter((n) => n.isAnimationStudio).map((n) => n.name)
  const names = anim.length ? anim : nodes.map((n) => n.name)
  return names.slice(0, 3)
}

export function toMediaRow(m: AniListMedia): MediaRow {
  return {
    id: m.id,
    source: 'anilist',
    externalId: null,
    titleRomaji: m.title.romaji,
    titleEnglish: m.title.english,
    format: m.format,
    status: m.status,
    episodes: m.episodes,
    cover: m.coverImage.extraLarge ?? m.coverImage.large ?? null,
    banner: m.bannerImage ?? m.coverImage.extraLarge ?? null,
    description: m.description,
    genres: m.genres ?? [],
    studios: aniListStudios(m),
    episodesList: aniListEpisodes(m),
    nextAiringEpisode: m.nextAiringEpisode,
    seasonYear: m.seasonYear,
    season: m.season,
    popularity: m.popularity,
    trending: m.trending,
    fetchedAt: new Date(),
  }
}

/**
 * Upsert prepared media rows (any source). `setLastAired` lets the TMDB path own lastAiredAt
 * via the upsert; the AniList path must NOT set it — there lastAiredAt belongs to
 * fetchLastAired (airingSchedules), which runs after the upsert.
 */
export async function upsertMediaRows(rows: MediaRow[], opts: { setLastAired?: boolean } = {}): Promise<void> {
  if (rows.length === 0) return
  await db
    .insert(media)
    .values(rows)
    .onConflictDoUpdate({
      target: media.id,
      set: {
        source: sqlExcluded('source'),
        externalId: sqlExcluded('external_id'),
        titleRomaji: sqlExcluded('title_romaji'),
        titleEnglish: sqlExcluded('title_english'),
        format: sqlExcluded('format'),
        status: sqlExcluded('status'),
        episodes: sqlExcluded('episodes'),
        cover: sqlExcluded('cover'),
        banner: sqlExcluded('banner'),
        description: sqlExcluded('description'),
        genres: sqlExcluded('genres'),
        studios: sqlExcluded('studios'),
        episodesList: sqlExcluded('episodes_list'),
        nextAiringEpisode: sqlExcluded('next_airing_episode'),
        seasonYear: sqlExcluded('season_year'),
        season: sqlExcluded('season'),
        popularity: sqlExcluded('popularity'),
        trending: sqlExcluded('trending'),
        ...(opts.setLastAired ? { lastAiredAt: sqlExcluded('last_aired_at') } : {}),
        fetchedAt: sqlExcluded('fetched_at'),
      },
    })
}

/** Upsert AniList media + their relation edges. */
export async function upsertMedia(items: AniListMedia[]): Promise<void> {
  if (items.length === 0) return
  await upsertMediaRows(items.map(toMediaRow))

  const edges = items.flatMap((m) =>
    (m.relations?.edges ?? [])
      .filter((e) => e.node.type === 'ANIME')
      .map((e) => ({ mediaId: m.id, relatedId: e.node.id, relationType: e.relationType })),
  )
  if (edges.length > 0) {
    await db.insert(mediaRelations).values(edges).onConflictDoNothing()
  }
}

export async function getMediaRows(ids: number[]): Promise<MediaRow[]> {
  if (ids.length === 0) return []
  return db.select().from(media).where(inArray(media.id, ids))
}

export async function getMediaRow(id: number): Promise<MediaRow | undefined> {
  const [row] = await db.select().from(media).where(eq(media.id, id)).limit(1)
  return row
}

/**
 * A batched MediaFetcher for graph expansion: fetches a whole BFS frontier from AniList in
 * one batched request (chunked internally), upserts the results in a single write, and
 * memoises across the expansion so overlapping components never re-fetch the same node.
 *
 * The memo stores per-id *promises*, registered synchronously before the network await, so
 * concurrent expansions (the parallel search path) that request the same id share one fetch
 * instead of racing to fetch it twice. Ids AniList omits resolve to `undefined` and are
 * cached as such, so a dead id is never re-requested either.
 */
export function makeAniListFetcher() {
  const memo = new Map<number, Promise<AniListMedia | undefined>>()
  return async (ids: number[]): Promise<AniListMedia[]> => {
    const need = ids.filter((id) => !memo.has(id))
    if (need.length > 0) {
      const batch = fetchByIds(need).then(async (fetched) => {
        if (fetched.length > 0) await upsertMedia(fetched) // one batched write per frontier
        return fetched
      })
      // Register a promise for every requested id up front so concurrent callers dedupe.
      for (const id of need) {
        const p = batch.then((fetched) => fetched.find((m) => m.id === id))
        // Evict on failure so a transient AniList error doesn't permanently poison this id (or
        // overlapping expansions sharing this fetcher); the .catch also keeps the rejection handled.
        p.catch(() => memo.delete(id))
        memo.set(id, p)
      }
    }
    const resolved = await Promise.all(ids.map((id) => memo.get(id)!))
    return resolved.filter((m): m is AniListMedia => m !== undefined)
  }
}

// drizzle helper: reference the conflicting INSERT row's column (Postgres `excluded`).
import { sql } from 'drizzle-orm'
function sqlExcluded(col: string) {
  return sql.raw(`excluded.${col}`)
}
