import { eq, sql } from 'drizzle-orm'
import { db } from '../db/index.js'
import { franchise, franchiseMember, media, subscriptions } from '../db/schema.js'
import {
  getMovie,
  getSeasonVideos,
  getShow,
  tmdbEnabled,
  type TmdbRequestOptions,
} from '../tmdb/client.js'
import { tmdbVideos } from '../tmdb/mapping.js'
import type { TmdbShow, TmdbVideo } from '../tmdb/types.js'
import type { CatalogVideo, FranchiseEnrichment } from '../types/api.js'
import { BoundedTaskQueue } from '../util/taskQueue.js'
import {
  resolveAnimeTmdbTarget,
  type AnimeTmdbMediaType,
  type AnimeTmdbTarget,
} from './animeTmdbMatch.js'

const D = 86_400_000
const VIDEO_TTL_MS = 7 * D
const EMPTY_TTL_MS = D
const BACKGROUND_INTERVAL_MS = 150
const TV_FORMATS = new Set(['TV', 'TV_SHORT', 'ONA'])

const queue = new BoundedTaskQueue(2, 48, (key, error) => {
  console.warn(`anime video fallback failed (${key}):`, error instanceof Error ? error.message : error)
})

interface AnimeIdentityPart {
  id: number
  titleEnglish: string | null
  titleRomaji: string | null
  format: string | null
  year: number | null
  sequence: number
  videos: CatalogVideo[] | null
}

export interface AnimeVideoFallbackResult {
  checked: boolean
  matched: boolean
  updated: boolean
  videos: number
}

function fallbackFresh(value: FranchiseEnrichment | null | undefined, nowMs = Date.now()): boolean {
  const state = value?.videoFallback
  if (!state) return false
  const checked = Date.parse(state.checkedAt)
  const ttl = (value?.videos?.length ?? 0) > 0 ? VIDEO_TTL_MS : EMPTY_TTL_MS
  return Number.isFinite(checked) && checked > nowMs - ttl
}

function pickIdentityPart(parts: AnimeIdentityPart[], primaryMediaId: number | null): AnimeIdentityPart | undefined {
  const declared = parts.find((part) => part.id === primaryMediaId)
  return (
    (declared && TV_FORMATS.has(declared.format ?? '') ? declared : undefined)
    ?? parts.find((part) => TV_FORMATS.has(part.format ?? ''))
    ?? (declared?.format === 'MOVIE' ? declared : undefined)
    ?? parts.find((part) => part.format === 'MOVIE')
    ?? parts.slice().sort((a, b) => a.sequence - b.sequence)[0]
  )
}

/**
 * Fetch only the season video endpoints most likely to carry the current campaign. Show-level
 * videos are always included separately; this list is capped so long-running anime stay cheap.
 */
export function animeTrailerSeasonNumbers(show: TmdbShow, animeYears: number[], limit = 3): number[] {
  const seasons = (show.seasons ?? []).filter((season) => season.season_number > 0)
  const available = new Set(seasons.map((season) => season.season_number))
  const out: number[] = []
  const add = (value: number | null | undefined) => {
    if (value != null && available.has(value) && !out.includes(value) && out.length < limit) out.push(value)
  }

  add(show.next_episode_to_air?.season_number)
  add(Math.max(0, ...seasons.map((season) => season.season_number)))
  add(show.last_episode_to_air?.season_number)

  // If current/last/latest all collapse to one season, use dated seasons nearest the newest
  // AniList installments before falling back to simple reverse season order.
  const newestAnimeYear = Math.max(0, ...animeYears)
  for (const season of seasons
    .filter((item) => !!item.air_date)
    .sort((a, b) => {
      const ay = Number(a.air_date?.slice(0, 4)) || 0
      const by = Number(b.air_date?.slice(0, 4)) || 0
      return Math.abs(ay - newestAnimeYear) - Math.abs(by - newestAnimeYear) || b.season_number - a.season_number
    })) add(season.season_number)
  for (const season of seasons.slice().sort((a, b) => b.season_number - a.season_number)) add(season.season_number)
  return out
}

/** Preserve AniList's deep metadata while replacing only the metadata-only trailer cache. */
export function mergeAnimeVideoFallback(
  current: FranchiseEnrichment | null | undefined,
  genres: string[],
  videos: CatalogVideo[],
  target: AnimeTmdbTarget | null,
  checkedAt: string,
  attemptedMediaType?: AnimeTmdbMediaType,
): FranchiseEnrichment {
  const base: FranchiseEnrichment = current ?? {
    level: 'basic',
    themes: [...new Set(genres)].slice(0, 10),
    isAdult: null,
    contentRatings: [],
    people: { creators: [], directors: [], cast: [] },
    related: [],
    videos: [],
    checkedAt,
  }
  const mediaType: AnimeTmdbMediaType =
    target?.mediaType ?? attemptedMediaType ?? current?.videoFallback?.mediaType ?? 'tv'
  return {
    ...base,
    videos,
    videoFallback: {
      source: 'tmdb',
      mediaType,
      externalId: target?.externalId ?? null,
      status: target ? 'matched' : 'unmatched',
      checkedAt,
    },
  }
}

/**
 * Enrich one AniList franchise with TMDB trailers without materializing a TMDB franchise or
 * changing any AniList part. Failures throw and therefore never become durable "unmatched" facts.
 */
export async function refreshAnimeVideoFallback(
  franchiseId: string,
  options: { force?: boolean; request?: TmdbRequestOptions } = {},
): Promise<AnimeVideoFallbackResult> {
  if (!tmdbEnabled()) return { checked: false, matched: false, updated: false, videos: 0 }
  const [row] = await db
    .select({
      source: franchise.source,
      title: franchise.title,
      primaryMediaId: franchise.primaryMediaId,
      genres: franchise.genres,
      enrichment: franchise.enrichment,
    })
    .from(franchise)
    .where(eq(franchise.id, franchiseId))
    .limit(1)
  if (!row || row.source !== 'anilist') return { checked: false, matched: false, updated: false, videos: 0 }
  if (!options.force && fallbackFresh(row.enrichment)) {
    return {
      checked: false,
      matched: row.enrichment?.videoFallback?.status === 'matched',
      updated: false,
      videos: row.enrichment?.videos?.length ?? 0,
    }
  }

  const parts = await db
    .select({
      id: media.id,
      titleEnglish: media.titleEnglish,
      titleRomaji: media.titleRomaji,
      format: media.format,
      year: media.seasonYear,
      sequence: franchiseMember.sequence,
      videos: media.videos,
    })
    .from(franchiseMember)
    .innerJoin(media, eq(media.id, franchiseMember.mediaId))
    .where(eq(franchiseMember.franchiseId, franchiseId))
  const primary = pickIdentityPart(parts, row.primaryMediaId)
  if (!primary) return { checked: false, matched: false, updated: false, videos: 0 }
  const mediaType: AnimeTmdbMediaType = primary.format === 'MOVIE' ? 'movie' : 'tv'
  const aliases = [
    primary.titleEnglish,
    primary.titleRomaji,
    ...parts.flatMap((part) => [part.titleEnglish, part.titleRomaji]),
  ].filter((value): value is string => !!value)
  const previous = row.enrichment?.videoFallback
  let target: AnimeTmdbTarget | null =
    previous?.status === 'matched' && previous.externalId != null && previous.mediaType === mediaType
      ? { mediaType, externalId: previous.externalId }
      : await resolveAnimeTmdbTarget({ title: row.title, aliases, year: primary.year, mediaType }, options.request)

  let rawVideos: TmdbVideo[] = []
  if (target?.mediaType === 'movie') {
    const movie = await getMovie(target.externalId, options.request)
    if (movie) rawVideos = movie.videos?.results ?? []
    else target = null
  } else if (target) {
    const show = await getShow(target.externalId, options.request)
    if (show) {
      const seasonNumbers = animeTrailerSeasonNumbers(
        show,
        parts.map((part) => part.year).filter((year): year is number => year != null),
      )
      const seasons = await Promise.all(
        seasonNumbers.map((season) => getSeasonVideos(target!.externalId, season, options.request)),
      )
      rawVideos = [
        ...(show.videos?.results ?? []),
        ...seasons.flatMap((season) => season?.results ?? []),
      ]
    } else {
      target = null
    }
  }

  const videos = target ? tmdbVideos(rawVideos) : []
  const checkedAt = new Date().toISOString()
  const enrichment = mergeAnimeVideoFallback(
    row.enrichment,
    row.genres ?? [],
    videos,
    target,
    checkedAt,
    mediaType,
  )
  const patch = { videos: enrichment.videos, videoFallback: enrichment.videoFallback }
  // Merge only the fallback fields into the value present AT UPDATE TIME. The AniList deep
  // enricher can run concurrently from Search, and neither writer may clobber the other's facts.
  await db.update(franchise).set({
    enrichment: sql`coalesce(${franchise.enrichment}, ${JSON.stringify(enrichment)}::jsonb) || ${JSON.stringify(patch)}::jsonb`,
    updatedAt: new Date(),
  }).where(eq(franchise.id, franchiseId))
  return { checked: true, matched: target != null, updated: true, videos: videos.length }
}

/** Single-flight stale-while-revalidate hook for Search, Detail, and Subscribe. */
export function enqueueAnimeVideoFallback(franchiseId: string): void {
  queue.enqueue(`franchise:${franchiseId}`, async () => {
    await refreshAnimeVideoFallback(franchiseId, { request: { maxRetries: 1, timeoutMs: 4_000 } })
  })
}

/** Refresh followed anime even when no user visits Search or Detail. */
export async function refreshSubscribedAnimeVideoFallback(
  limit = 25,
  options: { force?: boolean } = {},
): Promise<{ checked: number; matched: number; videos: number }> {
  if (!tmdbEnabled()) return { checked: 0, matched: 0, videos: 0 }
  const candidates = await db
    .selectDistinct({ id: franchise.id, enrichment: franchise.enrichment })
    .from(subscriptions)
    .innerJoin(franchise, eq(franchise.id, subscriptions.franchiseId))
    .where(eq(franchise.source, 'anilist'))
    .limit(100)
  const stale = candidates
    .filter((row) => options.force || !fallbackFresh(row.enrichment))
    .slice(0, limit)
  let checked = 0
  let matched = 0
  let videos = 0
  let consecutiveFailures = 0
  for (const row of stale) {
    try {
      const result = await refreshAnimeVideoFallback(row.id, {
        force: options.force,
        request: { maxRetries: 1, timeoutMs: 8_000 },
      })
      if (result.checked) checked++
      if (result.matched) matched++
      videos += result.videos
      consecutiveFailures = 0
    } catch (error) {
      consecutiveFailures++
      console.warn(`anime video fallback failed (${row.id}):`, error instanceof Error ? error.message : error)
      if (consecutiveFailures >= 3) break
    }
    await new Promise((resolve) => setTimeout(resolve, BACKGROUND_INTERVAL_MS))
  }
  return { checked, matched, videos }
}
