import type { MediaStatus } from '../anilist/types.js'
import type { media } from '../db/schema.js'
import type { GroupingResult } from '../grouping/llm.js'
import type { TmdbSearchResult, TmdbSeason, TmdbShow } from './types.js'

// Pure TMDB → local-model mapping. No I/O here — everything is unit-testable.

type MediaRow = typeof media.$inferInsert

/**
 * TMDB media rows share the integer `media.id` keyspace with AniList rows, namespaced by a
 * fixed offset: id = OFFSET + tmdb season id. AniList ids are ~1e5-1e6 and TMDB season ids are
 * ~1e6 (int4 caps the scheme at season id 1,147,483,647) — the ranges can never collide, and
 * the deterministic id keeps upserts race-free without a lookup.
 */
export const TMDB_ID_OFFSET = 1_000_000_000
export const MAX_TMDB_SEASON_ID = 2_147_483_647 - TMDB_ID_OFFSET

export function tmdbSeasonMediaId(seasonId: number): number {
  if (!Number.isInteger(seasonId) || seasonId <= 0 || seasonId > MAX_TMDB_SEASON_ID) {
    throw new Error(`tmdb season id ${seasonId} outside the offset-safe range`)
  }
  return TMDB_ID_OFFSET + seasonId
}

export function imageUrl(path: string | null | undefined, size: 'w780' | 'w1280'): string | null {
  return path ? `https://image.tmdb.org/t/p/${size}${path}` : null
}

/**
 * TMDB air dates are date-only (no airtime). We synthesize a fixed 17:00 UTC instant so
 * countdown/"out now" ordering works; clients must not present minute-level countdowns or
 * schedule notifications for tmdb-sourced media (see docs/api-contract.md).
 */
export const TMDB_AIR_HOUR_UTC = 17

export function airDateToMs(date: string | null | undefined): number | null {
  if (!date) return null
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(date)
  if (!m) return null
  return Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3]), TMDB_AIR_HOUR_UTC)
}

/** Search-boundary rule: Japanese animation belongs to AniList, so its TMDB twin is suppressed. */
export function isJapaneseAnimation(r: TmdbSearchResult): boolean {
  const ANIMATION_GENRE_ID = 16
  return (r.genre_ids ?? []).includes(ANIMATION_GENRE_ID) && (r.origin_country ?? []).includes('JP')
}

/**
 * Seasons that become franchise parts. Numbered seasons always count (an announced 0-episode
 * season becomes a NOT_YET_RELEASED part, matching anime's announced-season behavior);
 * "Specials" (season 0) only when it actually has episodes.
 */
export function includedSeasons(show: TmdbShow): TmdbSeason[] {
  return (show.seasons ?? []).filter((s) => (s.season_number > 0 ? true : s.episode_count > 0))
}

/**
 * Per-season status in AniList vocabulary so franchiseView.toPart works unchanged:
 * only the season carrying next_episode_to_air is RELEASING; a cancelled show's last-aired
 * season is CANCELLED; unaired/undated seasons are NOT_YET_RELEASED; the rest are FINISHED.
 */
export function deriveSeasonStatus(show: TmdbShow, season: TmdbSeason, nowMs: number): MediaStatus {
  const premiere = airDateToMs(season.air_date)
  if (premiere == null || premiere > nowMs) return 'NOT_YET_RELEASED'
  if (show.next_episode_to_air?.season_number === season.season_number) return 'RELEASING'
  if (show.status === 'Canceled' && show.last_episode_to_air?.season_number === season.season_number) {
    return 'CANCELLED'
  }
  return 'FINISHED'
}

export function tmdbSeasonToMediaRow(show: TmdbShow, season: TmdbSeason, nowMs: number): MediaRow {
  const status = deriveSeasonStatus(show, season, nowMs)
  const next = show.next_episode_to_air
  const nextAirMs = status === 'RELEASING' ? airDateToMs(next?.air_date) : null
  const single = includedSeasons(show).length === 1
  const lastEp = show.last_episode_to_air
  const lastAiredAt =
    lastEp?.season_number === season.season_number
      ? airDateToMs(lastEp.air_date)
      : status === 'FINISHED' || status === 'CANCELLED'
        ? airDateToMs(season.air_date)
        : null
  return {
    id: tmdbSeasonMediaId(season.id),
    source: 'tmdb',
    externalId: season.id,
    titleRomaji: null,
    titleEnglish: single ? show.name : `${show.name}: ${season.name}`,
    format: 'TV',
    status,
    episodes: season.episode_count || null,
    cover: imageUrl(season.poster_path ?? show.poster_path, 'w780'),
    banner: imageUrl(show.backdrop_path, 'w1280') ?? imageUrl(show.poster_path, 'w780'),
    description: season.overview || show.overview || null,
    genres: (show.genres ?? []).map((g) => g.name),
    nextAiringEpisode:
      next && nextAirMs != null
        ? { episode: next.episode_number, airingAt: Math.floor(nextAirMs / 1000) }
        : null,
    seasonYear: season.air_date ? Number(season.air_date.slice(0, 4)) : null,
    season: null,
    popularity: Math.round(show.popularity ?? 0),
    trending: null,
    lastAiredAt,
    fetchedAt: new Date(),
  }
}

/**
 * Deterministic TV grouping: one show = one franchise, seasons as parts with
 * sequence = TMDB season_number (season 0 → 'special'). Zero LLM involvement.
 */
export function tmdbShowToGroupingResult(show: TmdbShow): GroupingResult {
  return {
    franchises: [
      {
        canonicalName: show.name,
        parts: includedSeasons(show).map((s) => ({
          id: tmdbSeasonMediaId(s.id),
          partKind: s.season_number === 0 ? 'special' : 'season',
          sequence: s.season_number,
          label: s.season_number === 0 ? 'Specials' : `Season ${s.season_number}`,
        })),
      },
    ],
    confidence: 1,
    model: null,
  }
}
