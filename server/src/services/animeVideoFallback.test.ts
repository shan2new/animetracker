import { beforeEach, describe, expect, it, vi } from 'vitest'
import type { FranchiseEnrichment } from '../types/api.js'

const h = vi.hoisted(() => ({
  selectRows: [] as unknown[][],
  writes: [] as unknown[],
  getShow: vi.fn(),
  getMovie: vi.fn(),
  getSeason: vi.fn(),
  resolveTarget: vi.fn(),
}))

vi.mock('../db/index.js', () => {
  const query = (rows: unknown[]) => {
    const chain: Record<string, unknown> = {}
    for (const key of ['from', 'where', 'limit', 'innerJoin']) chain[key] = () => chain
    chain.then = (resolve: (value: unknown[]) => unknown) => Promise.resolve(rows).then(resolve)
    return chain
  }
  return {
    db: {
      select: () => query(h.selectRows.shift() ?? []),
      update: () => ({
        set: (value: unknown) => {
          h.writes.push(value)
          return { where: () => Promise.resolve() }
        },
      }),
    },
  }
})

vi.mock('../tmdb/client.js', () => ({
  tmdbEnabled: () => true,
  getShow: h.getShow,
  getMovie: h.getMovie,
  getSeason: h.getSeason,
}))

vi.mock('./animeTmdbMatch.js', () => ({
  resolveAnimeTmdbTarget: h.resolveTarget,
}))
vi.mock('./catalogLinks.js', () => ({
  getCatalogLink: vi.fn(async () => null),
  upsertCatalogLink: vi.fn(async () => true),
}))
vi.mock('./recommendations.js', () => ({ syncRecommendationEdges: vi.fn(async () => {}) }))

const {
  animeTrailerSeasonNumbers,
  matchAnimePartsToTmdbSeasons,
  mergeAnimeVideoFallback,
  overlayAnimeEpisodes,
  refreshAnimeVideoFallback,
} = await import('./animeVideoFallback.js')

const deep: FranchiseEnrichment = {
  level: 'full',
  themes: ['Found Family'],
  isAdult: false,
  contentRatings: [],
  people: { creators: [], directors: [], cast: [] },
  related: [],
  videos: [],
  checkedAt: '2026-09-01T00:00:00.000Z',
}

const show = {
  id: 30984,
  name: 'Bleach',
  status: 'Returning Series',
  number_of_seasons: 2,
  seasons: [
    { id: 1, season_number: 1, episode_count: 366, air_date: '2004-10-05', poster_path: null, name: 'Season 1', overview: null },
    { id: 2, season_number: 2, episode_count: 52, air_date: '2022-10-11', poster_path: null, name: 'Thousand-Year Blood War', overview: null },
  ],
  next_episode_to_air: null,
  last_episode_to_air: { season_number: 2, episode_number: 40, air_date: '2024-12-28' },
  genres: [{ id: 16, name: 'Animation' }],
  overview: null,
  backdrop_path: null,
  poster_path: null,
  popularity: 100,
  origin_country: ['JP'],
  videos: { results: [] },
} as const

beforeEach(() => {
  h.selectRows.length = 0
  h.writes.length = 0
  h.getShow.mockReset().mockResolvedValue(show)
  h.getMovie.mockReset().mockResolvedValue(null)
  h.getSeason.mockReset().mockImplementation(async (_showId: number, seasonNumber: number) => ({
    id: seasonNumber,
    season_number: seasonNumber,
    episodes: [],
    videos: { results: [] },
  }))
  h.resolveTarget.mockReset().mockResolvedValue({ mediaType: 'tv', externalId: 30984 })
})

describe('animeTrailerSeasonNumbers', () => {
  it('targets current/latest seasons without downloading every season of a long-running anime', () => {
    expect(animeTrailerSeasonNumbers(show as never, [2004, 2022, 2026])).toEqual([2, 1])
  })
})

describe('anime episode metadata matching', () => {
  it('requires corroborating year and episode count before overlaying a TMDB season', () => {
    expect(matchAnimePartsToTmdbSeasons([{
      id: 1, format: 'TV', year: 2022, sequence: 2, totalEpisodes: 13,
    }], [{
      id: 22, season_number: 2, episode_count: 13, air_date: '2022-10-11',
      poster_path: null, name: 'Season 2', overview: null,
    }])).toEqual([{ mediaId: 1, seasonNumber: 2, confidence: 0.99 }])
  })

  it('rejects an ambiguous season match instead of assigning the wrong episode stills', () => {
    expect(matchAnimePartsToTmdbSeasons([{
      id: 1, format: 'TV', year: 2022, sequence: 1, totalEpisodes: 12,
    }], [1, 2].map((seasonNumber) => ({
      id: seasonNumber, season_number: seasonNumber, episode_count: 12,
      air_date: '2022-01-01', poster_path: null, name: `Part ${seasonNumber}`, overview: null,
    })))).toEqual([])
  })

  it('preserves AniList airing precision while filling descriptive episode fields', () => {
    const exact = Date.UTC(2026, 8, 3, 12, 30)
    expect(overlayAnimeEpisodes([{
      number: 1, title: null, airDate: exact, overview: null, still: null, runtime: null,
    }], [{
      number: 1, title: 'The Blade', airDate: Date.UTC(2026, 8, 3, 17),
      overview: 'A return.', still: 'https://image/still.jpg', runtime: 24,
    }])).toEqual([{
      number: 1, title: 'The Blade', airDate: exact,
      overview: 'A return.', still: 'https://image/still.jpg', runtime: 24,
    }])
  })
})

describe('mergeAnimeVideoFallback', () => {
  it('preserves AniList catalogue facts while recording metadata-only TMDB provenance', () => {
    const result = mergeAnimeVideoFallback(
      deep,
      ['Action'],
      [{
        id: 'trailer', site: 'youtube', kind: 'trailer', title: 'Trailer', url: null,
        thumbnail: null, official: true, language: 'en', country: 'US', publishedAt: null,
      }],
      { mediaType: 'tv', externalId: 30984 },
      '2026-09-03T00:00:00.000Z',
    )

    expect(result).toMatchObject({
      level: 'full',
      themes: ['Found Family'],
      checkedAt: '2026-09-03T00:00:00.000Z',
      videoFallback: {
        source: 'tmdb',
        mediaType: 'tv',
        externalId: 30984,
        status: 'matched',
        checkedAt: '2026-09-03T00:00:00.000Z',
      },
    })
    expect(result.videos).toHaveLength(1)
  })
})

describe('refreshAnimeVideoFallback', () => {
  it('stores show and latest-season trailers on the existing AniList franchise', async () => {
    h.selectRows.push(
      [{ source: 'anilist', title: 'Bleach', primaryMediaId: 1, genres: ['Action'], enrichment: deep }],
      [{
        id: 1,
        titleEnglish: 'Bleach',
        titleRomaji: 'BLEACH',
        format: 'TV',
        year: 2004,
        sequence: 1,
        videos: [],
      }],
    )
    h.getSeason.mockResolvedValueOnce({
      id: 2,
      season_number: 2,
      episodes: [],
      videos: { results: [{
        id: 'tmdb-video', key: 'Px1xodGZAT0', site: 'YouTube', type: 'Trailer',
        name: 'BLEACH: The Calamity Official Trailer', official: true,
        iso_639_1: 'en', iso_3166_1: 'US', published_at: '2026-07-04T00:00:00.000Z',
      }] },
    })

    await expect(refreshAnimeVideoFallback('franchise-id', { force: true })).resolves.toMatchObject({
      checked: true,
      matched: true,
      updated: true,
      videos: 1,
    })
    expect(h.resolveTarget).toHaveBeenCalledWith(
      expect.objectContaining({ title: 'Bleach', year: 2004, mediaType: 'tv' }),
      undefined,
    )
    expect(h.getShow).toHaveBeenCalledWith(30984, { enrichment: true })
    expect(h.getSeason).toHaveBeenCalledWith(30984, 2, undefined)
    expect(h.writes).toHaveLength(2)
    expect(h.writes[0]).toMatchObject({ episodesList: [] })
    expect(h.writes[1]).toMatchObject({ updatedAt: expect.any(Date) })
  })

  it('does no provider work while a successful fallback cache is fresh', async () => {
    const fresh: FranchiseEnrichment = {
      ...deep,
      videos: [{
        id: 'fallback', site: 'youtube', kind: 'trailer', title: null, url: null,
        thumbnail: null, official: true, language: null, country: null, publishedAt: null,
      }],
      videoFallback: {
        source: 'tmdb',
        mediaType: 'tv',
        externalId: 30984,
        status: 'matched',
        checkedAt: new Date().toISOString(),
      },
    }
    h.selectRows.push(
      [{ source: 'anilist', title: 'Bleach', primaryMediaId: 1, genres: [], enrichment: fresh }],
    )

    await expect(refreshAnimeVideoFallback('franchise-id')).resolves.toEqual({
      checked: false,
      matched: true,
      updated: false,
      videos: 1,
    })
    expect(h.resolveTarget).not.toHaveBeenCalled()
    expect(h.getShow).not.toHaveBeenCalled()
    expect(h.writes).toEqual([])
  })
})
