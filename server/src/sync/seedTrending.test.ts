import { beforeEach, describe, expect, it, vi } from 'vitest'

// AniList intermittently answers a valid trending query with HTTP 200 and an empty `media` array.
// That is a degraded response, not a real state — the catalogue is never empty — but seedTrending
// used to accept it, upsert nothing, and log "fetched 0 trending" as a success. This pins the
// guard that turns that silence into a visible failure.
//
// Every module seedTrending touches is mocked, so this needs neither env, DB, nor network.

const h = vi.hoisted(() => ({ trending: [] as { id: number }[], upserted: [] as unknown[][] })) as {
  trending: { id: number }[]
  upserted: unknown[][]
}

vi.mock('../env.js', () => ({ env: { TRENDING_SEED_COUNT: 60, OPENROUTER_MODEL_BULK: 'm' } }))
vi.mock('../anilist/client.js', () => ({
  fetchTrending: async (limit: number) => h.trending.slice(0, limit),
  fetchByIds: async () => [],
  fetchLastAired: async () => ({}),
}))
vi.mock('../services/mediaStore.js', () => ({
  upsertMedia: async (items: unknown[]) => {
    h.upserted.push(items)
  },
}))
vi.mock('../grouping/service.js', () => ({ groupFromSeed: async () => ({ franchiseId: 'f', attached: 0 }) }))
vi.mock('../tmdb/client.js', () => ({ getTrendingTv: async () => [], tmdbEnabled: () => false }))
vi.mock('../tmdb/mapping.js', () => ({ isJapaneseAnimation: () => false }))
vi.mock('../tmdb/service.js', () => ({ ensureTvFranchise: async () => null, refreshTvShow: async () => ({ refreshed: true }) }))
vi.mock('../util/concurrency.js', () => ({ mapWithConcurrency: async () => [] }))
vi.mock('../db/index.js', () => {
  // Every read seedTrending performs returns "nothing already grouped".
  const chain: Record<string, unknown> = {}
  for (const k of ['select', 'selectDistinct', 'from', 'where', 'innerJoin', 'leftJoin', 'limit', 'update', 'set']) {
    chain[k] = () => chain
  }
  chain.then = (resolve: (v: unknown[]) => unknown) => resolve([])
  return { db: chain }
})

const { seedTrending } = await import('./sync.js')

beforeEach(() => {
  h.trending = []
  h.upserted.length = 0
})

describe('seedTrending', () => {
  it('throws instead of silently succeeding when AniList returns an empty page', async () => {
    h.trending = []
    await expect(seedTrending(60)).rejects.toThrow(/no trending media/i)
    expect(h.upserted, 'must not write an empty batch').toHaveLength(0)
  })

  it('accepts a non-empty page', async () => {
    h.trending = [{ id: 1 }, { id: 2 }]
    const out = await seedTrending(60)
    expect(out.fetched).toBe(2)
    expect(h.upserted[0]).toHaveLength(2)
  })

  it('does not treat an explicit request for zero as a failure', async () => {
    // count === 0 legitimately yields nothing; only a non-empty request can be "degraded".
    await expect(seedTrending(0)).resolves.toEqual({ fetched: 0, grouped: 0 })
  })
})
