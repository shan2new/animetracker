import { beforeEach, describe, expect, it, vi } from 'vitest'
import type { ArtworkGallery, ArtworkImage, FranchiseEnrichment } from '../types/api.js'

const h = vi.hoisted(() => ({
  selectRows: [] as unknown[][],
  writes: [] as Record<string, unknown>[],
  getShow: vi.fn(),
  syncRecommendationEdges: vi.fn(async () => {}),
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
        set: (value: Record<string, unknown>) => {
          h.writes.push(value)
          return { where: () => Promise.resolve() }
        },
      }),
    },
  }
})

vi.mock('../anilist/client.js', () => ({ fetchEnrichmentByIds: vi.fn() }))
vi.mock('../tmdb/client.js', () => ({ getShow: h.getShow }))
vi.mock('./recommendations.js', () => ({
  syncRecommendationEdges: h.syncRecommendationEdges,
}))

const { refreshFranchiseEnrichment } = await import('./catalogEnrichment.js')

const image = (
  url: string,
  width: number | null = null,
  height: number | null = null,
  language: string | null = null,
  score: number | null = null,
): ArtworkImage => ({ url, source: 'tmdb', width, height, language, score })

const fullEnrichment = (): FranchiseEnrichment => ({
  level: 'full',
  themes: [],
  isAdult: false,
  contentRatings: [],
  people: { creators: [], directors: [], cast: [] },
  related: [],
  videos: [],
  checkedAt: new Date().toISOString(),
})

const emptyArtwork = (): ArtworkGallery => ({ portraits: [], landscapes: [], logos: [] })

const franchiseRow = (overrides: Record<string, unknown> = {}) => ({
  id: 'franchise-id',
  source: 'tmdb',
  externalId: 123,
  cover: 'https://stored/cover.jpg',
  banner: 'https://stored/banner.jpg',
  artwork: emptyArtwork(),
  enrichment: null,
  ...overrides,
})

const show = (overrides: Record<string, unknown> = {}) => ({
  id: 123,
  name: 'Example Show',
  status: 'Ended',
  number_of_seasons: 1,
  seasons: [],
  next_episode_to_air: null,
  last_episode_to_air: null,
  genres: [],
  overview: null,
  poster_path: '/poster.jpg',
  backdrop_path: '/backdrop.jpg',
  popularity: 1,
  origin_country: ['US'],
  adult: false,
  created_by: [],
  content_ratings: { results: [] },
  aggregate_credits: { cast: [], crew: [] },
  keywords: { results: [] },
  recommendations: { results: [] },
  videos: { results: [] },
  images: { posters: [], backdrops: [], logos: [] },
  ...overrides,
})

beforeEach(() => {
  h.selectRows.length = 0
  h.writes.length = 0
  h.getShow.mockReset()
  h.syncRecommendationEdges.mockClear()
})

describe('refreshFranchiseEnrichment TMDB artwork', () => {
  it('persists every artwork orientation without changing identity or selected legacy artwork', async () => {
    h.selectRows.push([franchiseRow()])
    h.getShow.mockResolvedValue(show({
      images: {
        posters: [{ file_path: '/poster.jpg', width: 2000, height: 3000, iso_639_1: 'en', vote_average: 8.2 }],
        backdrops: [{ file_path: '/backdrop.jpg', width: 3840, height: 2160, iso_639_1: null, vote_average: 7.4 }],
        logos: [{ file_path: '/logo.png', width: 1200, height: 480, iso_639_1: 'en', vote_average: 9.1 }],
      },
    }))

    await expect(refreshFranchiseEnrichment('franchise-id')).resolves.toBe(true)

    expect(h.writes).toHaveLength(1)
    expect(h.writes[0]).toMatchObject({
      artwork: {
        portraits: [expect.objectContaining({ width: 2000, height: 3000, language: 'en' })],
        landscapes: [expect.objectContaining({ width: 3840, height: 2160 })],
        logos: [expect.objectContaining({
          url: 'https://image.tmdb.org/t/p/w1280/logo.png',
          width: 1200,
          height: 480,
          language: 'en',
          source: 'tmdb',
        })],
      },
      updatedAt: expect.any(Date),
    })
    for (const key of ['cover', 'banner', 'source', 'externalId']) {
      expect(h.writes[0]).not.toHaveProperty(key)
    }
    expect(h.syncRecommendationEdges).toHaveBeenCalledTimes(1)
  })

  it('preserves stored alternatives and logos when TMDB omits the images payload', async () => {
    const stored: ArtworkGallery = {
      portraits: [image('https://stored/portrait.jpg', 1000, 1500)],
      landscapes: [image('https://stored/landscape.jpg', 1920, 1080)],
      logos: [image('https://stored/logo.png', 900, 300, 'en')],
    }
    h.selectRows.push([franchiseRow({ artwork: stored })])
    h.getShow.mockResolvedValue(show({ images: undefined, poster_path: null, backdrop_path: null }))

    await expect(refreshFranchiseEnrichment('franchise-id')).resolves.toBe(true)

    expect(h.writes[0]?.artwork).toEqual(stored)
  })

  it('keeps alternatives, upgrades duplicate metadata, deduplicates URLs, and ranks by quality', async () => {
    const repeated = 'https://image.tmdb.org/t/p/w780/repeated.jpg'
    h.selectRows.push([franchiseRow({
      artwork: {
        portraits: [
          image(repeated),
          image('https://stored/alternative.jpg', 1000, 1500, null, 9),
        ],
        landscapes: [image('https://stored/landscape.jpg', 1920, 1080)],
        logos: [image('https://stored/logo.png', 900, 300, 'en')],
      },
    })])
    h.getShow.mockResolvedValue(show({
      poster_path: '/repeated.jpg',
      backdrop_path: null,
      images: {
        posters: [
          { file_path: '/repeated.jpg', width: 2000, height: 3000, iso_639_1: 'en', vote_average: 4 },
          { file_path: '/new.jpg', width: 1200, height: 1800, iso_639_1: null, vote_average: 8 },
        ],
        backdrops: [],
        logos: [],
      },
    }))

    await expect(refreshFranchiseEnrichment('franchise-id')).resolves.toBe(true)

    const gallery = h.writes[0]?.artwork as ArtworkGallery
    expect(gallery.portraits.map((item) => item.url)).toEqual([
      repeated,
      'https://image.tmdb.org/t/p/w780/new.jpg',
      'https://stored/alternative.jpg',
    ])
    expect(gallery.portraits.filter((item) => item.url === repeated)).toEqual([
      expect.objectContaining({ width: 2000, height: 3000, language: 'en' }),
    ])
    expect(gallery.landscapes).toHaveLength(1)
    expect(gallery.logos).toHaveLength(1)
  })

  it('skips fresh metadata normally but force-refreshes and repairs its gallery', async () => {
    const fresh = franchiseRow({ enrichment: fullEnrichment() })
    h.selectRows.push([fresh], [fresh])
    h.getShow.mockResolvedValue(show({
      images: {
        posters: [],
        backdrops: [],
        logos: [{ file_path: '/logo.png', width: 1000, height: 400, iso_639_1: 'en', vote_average: 7 }],
      },
    }))

    await expect(refreshFranchiseEnrichment('franchise-id')).resolves.toBe(false)
    expect(h.getShow).not.toHaveBeenCalled()
    expect(h.writes).toEqual([])

    await expect(refreshFranchiseEnrichment('franchise-id', { force: true })).resolves.toBe(true)
    expect(h.getShow).toHaveBeenCalledTimes(1)
    expect((h.writes[0]?.artwork as ArtworkGallery).logos).toHaveLength(1)
  })

  it('does not write or update recommendations when TMDB returns null', async () => {
    h.selectRows.push([franchiseRow()])
    h.getShow.mockResolvedValue(null)

    await expect(refreshFranchiseEnrichment('franchise-id', { force: true })).resolves.toBe(false)

    expect(h.writes).toEqual([])
    expect(h.syncRecommendationEdges).not.toHaveBeenCalled()
  })
})
