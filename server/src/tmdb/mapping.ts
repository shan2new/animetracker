import type { MediaStatus } from '../anilist/types.js'
import type { media } from '../db/schema.js'
import type { GroupingResult } from '../grouping/llm.js'
import type {
  ArtworkGallery,
  ArtworkImage,
  CatalogPerson,
  CatalogVideo,
  EpisodeMeta,
  FranchiseEnrichment,
  FranchisePeople,
  FranchiseUpcoming,
  RelatedTitle,
  VideoKind,
} from '../types/api.js'
import type { TmdbEpisode, TmdbImage, TmdbMovie, TmdbSearchResult, TmdbSeason, TmdbShow, TmdbVideo } from './types.js'

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

export function imageUrl(path: string | null | undefined, size: 'w342' | 'w780' | 'w1280'): string | null {
  return path ? `https://image.tmdb.org/t/p/${size}${path}` : null
}

function rankedArtwork(
  items: TmdbImage[] | null | undefined,
  orientation: 'portrait' | 'landscape' | 'logo',
): ArtworkImage[] {
  const size = orientation === 'portrait' ? 'w780' : 'w1280'
  const seen = new Set<string>()
  return (items ?? [])
    .slice()
    .sort((a, b) => (b.vote_average ?? 0) - (a.vote_average ?? 0) || (b.vote_count ?? 0) - (a.vote_count ?? 0))
    .flatMap((item) => {
      const url = imageUrl(item.file_path, size)
      if (!url || seen.has(url)) return []
      seen.add(url)
      return [{
        url,
        source: 'tmdb' as const,
        width: item.width ?? null,
        height: item.height ?? null,
        language: item.iso_639_1 ?? null,
        score: item.vote_average ?? null,
      }]
    })
    .slice(0, 6)
}

function prependArtwork(items: ArtworkImage[], url: string | null, orientation: 'portrait' | 'landscape'): ArtworkImage[] {
  if (!url || items.some((item) => item.url === url)) return items
  return [{ url, source: 'tmdb' as const, width: null, height: null, language: null, score: null }, ...items].slice(0, 6)
}

export function tmdbArtwork(show: TmdbShow, season?: TmdbSeason): ArtworkGallery {
  const primaryPortrait = imageUrl(season?.poster_path ?? show.poster_path, 'w780')
  const primaryLandscape = imageUrl(show.backdrop_path, 'w1280')
  return {
    portraits: prependArtwork(rankedArtwork(show.images?.posters, 'portrait'), primaryPortrait, 'portrait'),
    landscapes: prependArtwork(rankedArtwork(show.images?.backdrops, 'landscape'), primaryLandscape, 'landscape'),
    logos: rankedArtwork(show.images?.logos, 'logo'),
  }
}

export function tmdbMovieArtwork(movie: TmdbMovie): ArtworkGallery {
  return {
    portraits: prependArtwork(
      rankedArtwork(movie.images?.posters, 'portrait'),
      imageUrl(movie.poster_path, 'w780'),
      'portrait',
    ),
    landscapes: prependArtwork(
      rankedArtwork(movie.images?.backdrops, 'landscape'),
      imageUrl(movie.backdrop_path, 'w1280'),
      'landscape',
    ),
    logos: rankedArtwork(movie.images?.logos, 'logo'),
  }
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

const ANIMATION_GENRE_ID = 16

/** Search-boundary rule: Japanese animation belongs to AniList, so its TMDB twin is suppressed. */
export function isJapaneseAnimation(r: TmdbSearchResult): boolean {
  return (r.genre_ids ?? []).includes(ANIMATION_GENRE_ID) && (r.origin_country ?? []).includes('JP')
}

/**
 * The same boundary rule against a FULL show payload (`genres` objects, not `genre_ids`).
 *
 * `ensureTvFranchise` enforces this so the rule holds for EVERY caller. Keeping it only in the
 * callers left it one new call site away from being bypassed — and `npm run tv -- <showId>` was
 * exactly that gap, which is how a TMDB twin of an AniList-owned anime got materialized.
 */
export function isJapaneseAnimationShow(show: TmdbShow): boolean {
  return (
    (show.genres ?? []).some((g) => g.id === ANIMATION_GENRE_ID) && (show.origin_country ?? []).includes('JP')
  )
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

/** Map a TMDB season's full episode list to the source-neutral EpisodeMeta shape (dates → 17:00 UTC ms). */
export function tmdbEpisodes(episodes: TmdbEpisode[] | null | undefined): EpisodeMeta[] {
  return (episodes ?? []).map((e) => ({
    number: e.episode_number,
    title: e.name || null,
    airDate: airDateToMs(e.air_date),
    overview: e.overview || null,
    still: imageUrl(e.still_path, 'w780'),
    runtime: e.runtime ?? null,
  }))
}

/** Network names for the detail meta line (the TV analogue of AniList studios). */
export function tmdbNetworks(show: TmdbShow): string[] {
  return (show.networks ?? []).map((n) => n.name).slice(0, 3)
}

const VIDEO_KIND_ORDER: Record<VideoKind, number> = {
  trailer: 0,
  teaser: 1,
  announcement: 2,
  featurette: 3,
  clip: 4,
  other: 5,
}

function tmdbVideoKind(video: TmdbVideo): VideoKind {
  const type = video.type.toLowerCase()
  if (type === 'trailer') return 'trailer'
  if (type === 'teaser') return 'teaser'
  if (type === 'clip') return 'clip'
  if (type === 'featurette') {
    return /announc|coming back|returning|renew|in production/i.test(video.name ?? '') ? 'announcement' : 'featurette'
  }
  return 'other'
}

/** Map TMDB's external-video records into provider-neutral links; video bytes stay on the host. */
export function tmdbVideos(input: TmdbVideo[] | null | undefined): CatalogVideo[] {
  const byProviderId = new Map<string, CatalogVideo>()
  for (const video of input ?? []) {
    const id = video.key?.trim()
    const site = video.site?.trim().toLowerCase()
    if (!id || !site) continue
    const kind = tmdbVideoKind(video)
    // Bloopers/recaps/opening credits are useful editorially but not a trailer surface.
    if (kind === 'other') continue
    const url =
      site === 'youtube'
        ? `https://www.youtube.com/watch?v=${encodeURIComponent(id)}`
        : site === 'vimeo'
          ? `https://vimeo.com/${encodeURIComponent(id)}`
          : null
    const thumbnail = site === 'youtube' ? `https://i.ytimg.com/vi/${encodeURIComponent(id)}/hqdefault.jpg` : null
    const mapped: CatalogVideo = {
      id,
      site,
      kind,
      title: video.name?.trim() || null,
      url,
      thumbnail,
      official: video.official,
      language: video.iso_639_1 || null,
      country: video.iso_3166_1 || null,
      publishedAt: video.published_at || null,
    }
    const key = `${site}:${id}`
    const previous = byProviderId.get(key)
    if (!previous || (!previous.official && mapped.official)) byProviderId.set(key, mapped)
  }
  return [...byProviderId.values()]
    .sort((a, b) =>
      Number(b.official) - Number(a.official) ||
      VIDEO_KIND_ORDER[a.kind] - VIDEO_KIND_ORDER[b.kind] ||
      (b.publishedAt ?? '').localeCompare(a.publishedAt ?? ''),
    )
    .slice(0, 12)
}

function tmdbPerson(
  id: number,
  name: string,
  profilePath: string | null,
  role: string | null,
): CatalogPerson {
  return { source: 'tmdb', externalId: id, name, role, image: imageUrl(profilePath, 'w342') }
}

function uniquePeople(people: CatalogPerson[], limit: number): CatalogPerson[] {
  const seen = new Set<number>()
  const out: CatalogPerson[] = []
  for (const person of people) {
    if (seen.has(person.externalId)) continue
    seen.add(person.externalId)
    out.push(person)
    if (out.length >= limit) break
  }
  return out
}

function tmdbPeople(show: TmdbShow): FranchisePeople {
  const creators = uniquePeople(
    (show.created_by ?? []).map((person) => tmdbPerson(person.id, person.name, person.profile_path, 'Creator')),
    4,
  )
  const directors = uniquePeople(
    (show.aggregate_credits?.crew ?? [])
      .flatMap((person) => {
        const jobs = (person.jobs ?? []).filter((job) => /director/i.test(job.job))
        const episodes = jobs.reduce((sum, job) => sum + (job.episode_count ?? 0), 0)
        return jobs.length
          ? [{ person: tmdbPerson(person.id, person.name, person.profile_path, jobs[0]?.job ?? 'Director'), episodes }]
          : []
      })
      .sort((a, b) => b.episodes - a.episodes)
      .map((entry) => entry.person),
    4,
  )
  const cast = uniquePeople(
    (show.aggregate_credits?.cast ?? [])
      .slice()
      .sort((a, b) => (a.order ?? 9999) - (b.order ?? 9999) || (b.total_episode_count ?? 0) - (a.total_episode_count ?? 0))
      .map((person) => {
        const role = (person.roles ?? []).slice().sort((a, b) => (b.episode_count ?? 0) - (a.episode_count ?? 0))[0]
        return tmdbPerson(person.id, person.name, person.profile_path, role?.character ?? null)
      }),
    10,
  )
  return { creators, directors, cast }
}

// TMDB keywords have no spoiler flag. Only broad concepts/locations pass this conservative gate;
// everything plot-shaped stays out rather than being labelled safe without evidence.
const SAFE_THEME = /^(friendship|family|romance|romcom|workplace|coming of age|female protagonist|male protagonist|high school|middle school|college|magic|superhero|space|time travel|sports|music|cooking|fashion|marketing|reality tv|competition|travel|medical|legal|police|detective|historical|period drama|sitcom|based on novel or book|based on comic|based on manga)$/i

function titleCase(value: string): string {
  return value.replace(/\b\p{L}/gu, (char) => char.toLocaleUpperCase('en-US'))
}

function tmdbThemes(show: TmdbShow): string[] {
  const themes = [
    ...(show.genres ?? []).map((genre) => genre.name),
    ...(show.keywords?.results ?? []).map((keyword) => keyword.name).filter((name) => SAFE_THEME.test(name)).map(titleCase),
  ]
  return [...new Set(themes)].slice(0, 10)
}

/** Franchise-level catalogue metadata. Missing appended fields intentionally yield a basic row. */
export function tmdbFranchiseEnrichment(show: TmdbShow, nowMs = Date.now()): FranchiseEnrichment {
  const hasDeepPayload =
    show.content_ratings != null || show.aggregate_credits != null || show.keywords != null || show.recommendations != null
  const contentRatings = (show.content_ratings?.results ?? [])
    .filter((item) => !!item.iso_3166_1 && !!item.rating)
    .map((item) => ({ country: item.iso_3166_1.toUpperCase(), rating: item.rating }))
    .filter((item, index, all) => all.findIndex((other) => other.country === item.country) === index)
    .sort((a, b) => a.country.localeCompare(b.country))
  const related: RelatedTitle[] = (show.recommendations?.results ?? [])
    .filter((item) => item.media_type !== 'movie' && item.adult !== true && !!item.name)
    .slice(0, 10)
    .map((item, index) => ({
      source: 'tmdb',
      externalId: item.id,
      franchiseId: null,
      title: item.name,
      year: item.first_air_date ? Number(item.first_air_date.slice(0, 4)) || null : null,
      images: {
        portrait: imageUrl(item.poster_path, 'w780'),
        landscape: imageUrl(item.backdrop_path, 'w1280'),
      },
      score: 10 - index,
    }))
  return {
    level: hasDeepPayload ? 'full' : 'basic',
    themes: tmdbThemes(show),
    isAdult: show.adult ?? null,
    contentRatings,
    people: tmdbPeople(show),
    related,
    videos: tmdbVideos(show.videos?.results),
    checkedAt: new Date(nowMs).toISOString(),
  }
}

/**
 * Immediate "what's next" fact available from the same TMDB payload that materializes a search
 * result. This deliberately requires no web-research round trip, so Search can ship the field on
 * its first response; the news agent later replaces it with a primary announcement and context.
 */
export function tmdbShowUpcoming(show: TmdbShow, nowMs = Date.now()): FranchiseUpcoming | null {
  const numbered = includedSeasons(show).filter((season) => season.season_number > 0)
  if (numbered.length === 0) return null
  const lastAiredSeason = Math.max(
    show.last_episode_to_air?.season_number ?? 0,
    ...numbered
      .filter((season) => {
        const premiere = airDateToMs(season.air_date)
        return premiere != null && premiere <= nowMs
      })
      .map((season) => season.season_number),
  )
  const future = numbered
    .filter((season) => {
      const premiere = airDateToMs(season.air_date)
      if (premiere != null) return premiere > nowMs
      // Old seasons sometimes have a missing air_date. Only a number beyond the last aired season
      // is evidence of an undated announcement.
      return season.season_number > lastAiredSeason
    })
    .sort((a, b) => {
      const aa = airDateToMs(a.air_date)
      const bb = airDateToMs(b.air_date)
      if (aa != null && bb != null) return aa - bb
      if (aa != null) return -1
      if (bb != null) return 1
      return a.season_number - b.season_number
    })

  const checked = new Date(nowMs).toISOString()
  const source = `https://www.themoviedb.org/tv/${show.id}`
  const evidence = [{
    url: source,
    publisher: 'TMDB',
    publishedAt: null,
    tier: 'catalogue' as const,
    primary: false,
  }]
  const known = future[0]
  if (known) {
    return {
      status: known.air_date ? 'upcoming_dated' : 'announced_no_date',
      next: `Season ${known.season_number}`,
      release: known.air_date ?? 'TBA',
      note: null,
      source,
      checked,
      evidence,
    }
  }

  // Do not infer another season while the latest one is actively releasing. Search already carries
  // that state via isReleasing/nextAiringAt, and "Returning Series" may describe that same run.
  const releasing = show.next_episode_to_air != null
  if (releasing || !['Returning Series', 'In Production', 'Planned'].includes(show.status)) return null

  const nextNumber = Math.max(...numbered.map((season) => season.season_number)) + 1
  return {
    status: 'announced_no_date',
    next: `Season ${nextNumber}`,
    release: 'TBA',
    note: 'TMDB currently lists the series as returning; no premiere date is available in its catalogue.',
    source,
    checked,
    evidence,
  }
}

export function tmdbSeasonToMediaRow(
  show: TmdbShow,
  season: TmdbSeason,
  nowMs: number,
  episodes: EpisodeMeta[] = [],
  videos: CatalogVideo[] = [],
): MediaRow {
  const status = deriveSeasonStatus(show, season, nowMs)
  const next = show.next_episode_to_air
  const nextAirMs = status === 'RELEASING' ? airDateToMs(next?.air_date) : null
  // A dated-but-unaired season carries its premiere as the next slot (episode 1) — the same shape
  // AniList gives an announced season. `next_episode_to_air` only ever points at the RELEASING
  // season, so without this an upcoming season had no airing instant at all: clients read it as
  // "release date TBA" and it never reached the premiere shelf. deriveSeasonStatus returns
  // NOT_YET_RELEASED precisely because season.air_date is in the future, so this slot is never past.
  const premiereMs = status === 'NOT_YET_RELEASED' ? airDateToMs(season.air_date) : null
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
    titleNative: show.original_name ?? null,
    synonyms: (show.alternative_titles?.results ?? []).map((item) => item.title).filter(Boolean).slice(0, 30),
    format: 'TV',
    status,
    episodes: season.episode_count || null,
    cover: imageUrl(season.poster_path ?? show.poster_path, 'w780'),
    banner: imageUrl(show.backdrop_path, 'w1280'),
    artwork: tmdbArtwork(show, season),
    description: season.overview || show.overview || null,
    genres: (show.genres ?? []).map((g) => g.name),
    studios: tmdbNetworks(show),
    episodesList: episodes,
    videos,
    nextAiringEpisode:
      next && nextAirMs != null
        ? { episode: next.episode_number, airingAt: Math.floor(nextAirMs / 1000) }
        : premiereMs != null
          ? { episode: 1, airingAt: Math.floor(premiereMs / 1000) }
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
          // PostgreSQL `integer` tops out at ~2.1b. Keep specials after any plausible numbered
          // season without sending JavaScript's MAX_SAFE_INTEGER into an integer column.
          watchOrder: s.season_number === 0 ? 10_000 : s.season_number,
          relationship: s.season_number === 0 ? 'SPECIAL' : s.season_number === 1 ? null : 'SEQUEL',
          optional: s.season_number === 0,
          label: s.season_number === 0 ? 'Specials' : `Season ${s.season_number}`,
        })),
      },
    ],
    confidence: 1,
    model: null,
  }
}
