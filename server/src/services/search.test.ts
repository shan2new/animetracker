import { beforeEach, describe, expect, it, vi } from 'vitest'

const h = vi.hoisted(() => ({
  searchMedia: vi.fn(),
  searchTv: vi.fn(),
  correct: vi.fn(),
}))

vi.mock('../anilist/client.js', () => ({ searchMedia: h.searchMedia }))
vi.mock('../tmdb/client.js', () => ({ searchTv: h.searchTv, tmdbEnabled: () => true }))
vi.mock('../tmdb/mapping.js', () => ({ isJapaneseAnimation: () => false }))
vi.mock('../tmdb/service.js', () => ({ ensureTvFranchise: async () => null }))
vi.mock('../grouping/graph.js', () => ({ expandComponent: async () => new Map() }))
vi.mock('../grouping/service.js', () => ({ groupKnownComponent: async () => undefined }))
vi.mock('./mediaStore.js', () => ({
  makeAniListFetcher: () => async () => [],
  upsertMedia: async () => undefined,
}))
vi.mock('./queryCorrect.js', () => ({ correctSearchQuery: h.correct }))
vi.mock('./franchiseView.js', () => ({
  getSummaries: async () => [],
  getTrendingFranchises: async () => [],
}))
vi.mock('../db/index.js', () => ({
  db: {
    select: () => emptyQuery(),
  },
}))

function emptyQuery(): Record<string, unknown> {
  const query: Record<string, unknown> = {}
  for (const method of ['from', 'where', 'orderBy', 'limit', 'innerJoin', 'groupBy']) {
    query[method] = () => query
  }
  query.then = (resolve: (rows: unknown[]) => unknown) => resolve([])
  return query
}

const { searchFranchises } = await import('./search.js')

beforeEach(() => {
  h.searchMedia.mockReset().mockResolvedValue([])
  h.searchTv.mockReset().mockResolvedValue([])
  h.correct.mockReset().mockResolvedValue(null)
})

describe('interactive search orchestration', () => {
  it('keeps one- and two-character queries local-only', async () => {
    const response = await searchFranchises('ab')
    expect(response.franchises).toEqual([])
    expect(h.searchMedia).not.toHaveBeenCalled()
    expect(h.searchTv).not.toHaveBeenCalled()
  })

  it('gives live catalogue lookups one short attempt with no retries', async () => {
    await searchFranchises('abc', 30, { exact: true })

    expect(h.searchMedia).toHaveBeenCalledWith(
      'abc',
      expect.objectContaining({ maxRetries: 0, timeoutMs: 1_050, limit: 20 }),
    )
    expect(h.searchTv).toHaveBeenCalledWith(
      'abc',
      expect.objectContaining({ maxRetries: 0, timeoutMs: 1_050, limit: 20 }),
    )
  })

  it('returns an honest partial envelope instead of turning provider outages into a 500', async () => {
    h.searchMedia.mockRejectedValue(new Error('AniList unavailable'))
    h.searchTv.mockRejectedValue(new Error('TMDB unavailable'))

    await expect(searchFranchises('abc')).resolves.toEqual({
      franchises: [],
      sources: { anilist: 'failed', tmdb: 'failed' },
    })
    expect(h.correct).not.toHaveBeenCalled()
  })
})
