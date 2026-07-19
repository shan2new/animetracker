import { describe, expect, it } from 'vitest'
import {
  MAX_TMDB_SEASON_ID,
  TMDB_ID_OFFSET,
  airDateToMs,
  deriveSeasonStatus,
  includedSeasons,
  isJapaneseAnimation,
  tmdbEpisodes,
  tmdbNetworks,
  tmdbSeasonMediaId,
  tmdbSeasonToMediaRow,
  tmdbShowToGroupingResult,
} from './mapping.js'
import type { TmdbEpisode, TmdbSearchResult, TmdbSeason, TmdbShow } from './types.js'

// Fixed "now": 2026-07-01T00:00Z.
const NOW = Date.UTC(2026, 6, 1)

function season(n: number, opts: Partial<TmdbSeason> = {}): TmdbSeason {
  return {
    id: 1000 + n,
    season_number: n,
    episode_count: 10,
    air_date: `202${Math.min(n, 5)}-01-15`,
    poster_path: `/s${n}.jpg`,
    name: n === 0 ? 'Specials' : `Season ${n}`,
    overview: '',
    ...opts,
  }
}

function show(opts: Partial<TmdbShow> = {}): TmdbShow {
  return {
    id: 42,
    name: 'Test Show',
    status: 'Returning Series',
    number_of_seasons: 2,
    seasons: [season(1), season(2)],
    next_episode_to_air: null,
    last_episode_to_air: null,
    genres: [{ id: 18, name: 'Drama' }],
    overview: 'A show.',
    backdrop_path: '/back.jpg',
    poster_path: '/poster.jpg',
    popularity: 12.7,
    origin_country: ['US'],
    ...opts,
  }
}

function result(opts: Partial<TmdbSearchResult> = {}): TmdbSearchResult {
  return {
    id: 42,
    name: 'Test Show',
    genre_ids: [18],
    origin_country: ['US'],
    poster_path: null,
    first_air_date: '2020-01-01',
    popularity: 1,
    overview: null,
    ...opts,
  }
}

function episode(n: number, opts: Partial<TmdbEpisode> = {}): TmdbEpisode {
  return {
    episode_number: n,
    name: `Episode ${n}`,
    overview: `Overview ${n}`,
    air_date: '2025-05-04',
    still_path: `/e${n}.jpg`,
    runtime: 42,
    ...opts,
  }
}

describe('tmdbSeasonMediaId', () => {
  it('offsets into the reserved id range', () => {
    expect(tmdbSeasonMediaId(123)).toBe(TMDB_ID_OFFSET + 123)
  })

  it('rejects ids outside the int4-safe range', () => {
    expect(() => tmdbSeasonMediaId(0)).toThrow()
    expect(() => tmdbSeasonMediaId(-5)).toThrow()
    expect(() => tmdbSeasonMediaId(MAX_TMDB_SEASON_ID + 1)).toThrow()
    expect(() => tmdbSeasonMediaId(1.5)).toThrow()
    expect(tmdbSeasonMediaId(MAX_TMDB_SEASON_ID)).toBe(2_147_483_647)
  })
})

describe('airDateToMs', () => {
  it('lands on the fixed 17:00 UTC synthesis hour', () => {
    expect(airDateToMs('2026-07-19')).toBe(Date.UTC(2026, 6, 19, 17))
  })

  it('is null for missing or malformed dates', () => {
    expect(airDateToMs(null)).toBeNull()
    expect(airDateToMs('')).toBeNull()
    expect(airDateToMs('soon')).toBeNull()
  })
})

describe('isJapaneseAnimation', () => {
  it('suppresses JP animation (AniList owns it)', () => {
    expect(isJapaneseAnimation(result({ genre_ids: [16], origin_country: ['JP'] }))).toBe(true)
  })

  it('keeps western animation and JP live-action', () => {
    expect(isJapaneseAnimation(result({ genre_ids: [16], origin_country: ['US'] }))).toBe(false)
    expect(isJapaneseAnimation(result({ genre_ids: [18], origin_country: ['JP'] }))).toBe(false)
  })
})

describe('includedSeasons', () => {
  it('keeps numbered seasons even with zero episodes (announced), drops empty Specials', () => {
    const s = show({
      seasons: [season(0, { episode_count: 0 }), season(1), season(2, { episode_count: 0, air_date: null })],
    })
    expect(includedSeasons(s).map((x) => x.season_number)).toEqual([1, 2])
  })

  it('keeps Specials that actually have episodes', () => {
    const s = show({ seasons: [season(0, { episode_count: 3 }), season(1)] })
    expect(includedSeasons(s).map((x) => x.season_number)).toEqual([0, 1])
  })
})

describe('deriveSeasonStatus', () => {
  it('marks undated and future seasons NOT_YET_RELEASED', () => {
    const s = show()
    expect(deriveSeasonStatus(s, season(3, { air_date: null }), NOW)).toBe('NOT_YET_RELEASED')
    expect(deriveSeasonStatus(s, season(3, { air_date: '2026-09-01' }), NOW)).toBe('NOT_YET_RELEASED')
  })

  it('marks only the next-episode season RELEASING', () => {
    const s = show({
      next_episode_to_air: { air_date: '2026-07-10', episode_number: 5, season_number: 2 },
    })
    expect(deriveSeasonStatus(s, season(2), NOW)).toBe('RELEASING')
    expect(deriveSeasonStatus(s, season(1), NOW)).toBe('FINISHED')
  })

  it('marks a cancelled show´s last-aired season CANCELLED, earlier seasons FINISHED', () => {
    const s = show({
      status: 'Canceled',
      last_episode_to_air: { air_date: '2025-03-01', episode_number: 8, season_number: 2 },
    })
    expect(deriveSeasonStatus(s, season(2), NOW)).toBe('CANCELLED')
    expect(deriveSeasonStatus(s, season(1), NOW)).toBe('FINISHED')
  })

  it('marks aired seasons of a returning show FINISHED', () => {
    expect(deriveSeasonStatus(show(), season(1), NOW)).toBe('FINISHED')
  })
})

describe('tmdbSeasonToMediaRow', () => {
  it('maps ids, source, and titles (per-season title only when multi-season)', () => {
    const s = show({
      next_episode_to_air: { air_date: '2026-07-10', episode_number: 5, season_number: 2 },
    })
    const row = tmdbSeasonToMediaRow(s, season(2), NOW)
    expect(row.id).toBe(TMDB_ID_OFFSET + 1002)
    expect(row.source).toBe('tmdb')
    expect(row.externalId).toBe(1002)
    expect(row.titleEnglish).toBe('Test Show: Season 2')
    expect(row.format).toBe('TV')

    const solo = show({ seasons: [season(1)] })
    expect(tmdbSeasonToMediaRow(solo, season(1), NOW).titleEnglish).toBe('Test Show')
  })

  it('snapshots nextAiringEpisode in SECONDS on the releasing season only', () => {
    const s = show({
      next_episode_to_air: { air_date: '2026-07-10', episode_number: 5, season_number: 2 },
    })
    const releasing = tmdbSeasonToMediaRow(s, season(2), NOW)
    expect(releasing.nextAiringEpisode).toEqual({
      episode: 5,
      airingAt: Math.floor(Date.UTC(2026, 6, 10, 17) / 1000),
    })
    expect(tmdbSeasonToMediaRow(s, season(1), NOW).nextAiringEpisode).toBeNull()
  })

  it('takes lastAiredAt from last_episode_to_air for its season, else the season premiere', () => {
    const s = show({
      next_episode_to_air: { air_date: '2026-07-10', episode_number: 5, season_number: 2 },
      last_episode_to_air: { air_date: '2026-07-03', episode_number: 4, season_number: 2 },
    })
    expect(tmdbSeasonToMediaRow(s, season(2), NOW).lastAiredAt).toBe(Date.UTC(2026, 6, 3, 17))
    expect(tmdbSeasonToMediaRow(s, season(1), NOW).lastAiredAt).toBe(airDateToMs(season(1).air_date))
  })

  it('falls back to the show poster when a season has none', () => {
    const row = tmdbSeasonToMediaRow(show(), season(1, { poster_path: null }), NOW)
    expect(row.cover).toBe('https://image.tmdb.org/t/p/w780/poster.jpg')
    expect(row.banner).toBe('https://image.tmdb.org/t/p/w1280/back.jpg')
  })

  it('carries the passed episode list and the show networks as studios', () => {
    const s = show({ networks: [{ id: 1, name: 'HBO' }] })
    const eps = tmdbEpisodes([episode(1)])
    const row = tmdbSeasonToMediaRow(s, season(1), NOW, eps)
    expect(row.studios).toEqual(['HBO'])
    expect(row.episodesList).toEqual(eps)
  })

  it('defaults to no episodes and no studios when omitted', () => {
    const row = tmdbSeasonToMediaRow(show(), season(1), NOW)
    expect(row.episodesList).toEqual([])
    expect(row.studios).toEqual([])
  })
})

describe('tmdbEpisodes', () => {
  it('maps to EpisodeMeta with 17:00 UTC dates, still urls, and runtime', () => {
    const eps = tmdbEpisodes([episode(1), episode(2, { name: '', still_path: null, runtime: null })])
    expect(eps).toEqual([
      {
        number: 1,
        title: 'Episode 1',
        airDate: Date.UTC(2025, 4, 4, 17),
        overview: 'Overview 1',
        still: 'https://image.tmdb.org/t/p/w780/e1.jpg',
        runtime: 42,
      },
      {
        number: 2,
        title: null, // empty name → null
        airDate: Date.UTC(2025, 4, 4, 17),
        overview: 'Overview 2',
        still: null,
        runtime: null,
      },
    ])
  })

  it('is empty for null/undefined episode lists', () => {
    expect(tmdbEpisodes(null)).toEqual([])
    expect(tmdbEpisodes(undefined)).toEqual([])
  })
})

describe('tmdbNetworks', () => {
  it('takes up to three network names', () => {
    const s = show({
      networks: [
        { id: 1, name: 'HBO' },
        { id: 2, name: 'Max' },
        { id: 3, name: 'Sky' },
        { id: 4, name: 'Crave' },
      ],
    })
    expect(tmdbNetworks(s)).toEqual(['HBO', 'Max', 'Sky'])
  })

  it('is empty when the show has no networks', () => {
    expect(tmdbNetworks(show())).toEqual([])
  })
})

describe('tmdbShowToGroupingResult', () => {
  it('builds one deterministic franchise with season_number sequences', () => {
    const s = show({ seasons: [season(0, { episode_count: 3 }), season(1), season(2)] })
    const r = tmdbShowToGroupingResult(s)
    expect(r.model).toBeNull()
    expect(r.confidence).toBe(1)
    expect(r.franchises).toHaveLength(1)
    expect(r.franchises[0]!.canonicalName).toBe('Test Show')
    expect(r.franchises[0]!.parts).toEqual([
      { id: TMDB_ID_OFFSET + 1000, partKind: 'special', sequence: 0, label: 'Specials' },
      { id: TMDB_ID_OFFSET + 1001, partKind: 'season', sequence: 1, label: 'Season 1' },
      { id: TMDB_ID_OFFSET + 1002, partKind: 'season', sequence: 2, label: 'Season 2' },
    ])
  })
})
