import { beforeEach, describe, expect, it, vi } from 'vitest'

const h = vi.hoisted(() => ({
  selectRows: [] as unknown[][],
  fetchRows: [] as { id: number }[][],
  requested: [] as number[][],
  upserted: [] as number[][],
  stateWrites: [] as { cursor: number; complete: boolean }[],
}))

vi.mock('../env.js', () => ({
  env: { TRENDING_SEED_COUNT: 60, OPENROUTER_MODEL_BULK: 'm' },
}))

vi.mock('../anilist/client.js', () => ({
  fetchByIds: async (ids: number[]) => {
    h.requested.push(ids)
    return h.fetchRows.length ? h.fetchRows.shift()! : ids.map((id) => ({ id }))
  },
  fetchLastAired: async () => ({}),
  fetchTrending: async () => [],
}))

vi.mock('../services/mediaStore.js', () => ({
  upsertMedia: async (items: { id: number }[]) => {
    h.upserted.push(items.map((item) => item.id))
  },
}))

vi.mock('../grouping/service.js', () => ({ groupFromSeed: async () => ({ franchiseId: 'f', attached: 0 }) }))
vi.mock('../tmdb/client.js', () => ({ getTrendingTv: async () => [], tmdbEnabled: () => false }))
vi.mock('../tmdb/mapping.js', () => ({ isJapaneseAnimation: () => false }))
vi.mock('../tmdb/service.js', () => ({
  ensureTvFranchise: async () => null,
  refreshTvShow: async () => ({ refreshed: true }),
}))
vi.mock('../util/concurrency.js', () => ({ mapWithConcurrency: async () => [] }))

vi.mock('../db/index.js', () => {
  const query = (rows: unknown[]) => {
    const chain: Record<string, unknown> = {}
    for (const key of ['from', 'where', 'orderBy', 'limit']) chain[key] = () => chain
    chain.then = (resolve: (value: unknown[]) => unknown) => Promise.resolve(rows).then(resolve)
    return chain
  }
  const db = {
    select: () => query(h.selectRows.shift() ?? []),
    insert: () => {
      const chain: Record<string, unknown> = {}
      chain.values = (value: { value: { cursor: number; complete: boolean } }) => {
        h.stateWrites.push(value.value)
        return chain
      }
      chain.onConflictDoUpdate = () => Promise.resolve()
      return chain
    },
  }
  return { db }
})

const { sweepAniListTrailers } = await import('./sync.js')

beforeEach(() => {
  h.selectRows.length = 0
  h.fetchRows.length = 0
  h.requested.length = 0
  h.upserted.length = 0
  h.stateWrites.length = 0
})

describe('sweepAniListTrailers', () => {
  it('does no provider or catalogue work after the durable sweep is complete', async () => {
    h.selectRows.push([{ value: { cursor: 2065, complete: true } }])

    await expect(sweepAniListTrailers({ requestIntervalMs: 0 })).resolves.toEqual({
      scanned: 0,
      upserted: 0,
      complete: true,
      providerReachable: null,
    })
    expect(h.requested).toEqual([])
    expect(h.stateWrites).toEqual([])
  })

  it('rate-batches rows, upserts source payloads, and records a completed cursor', async () => {
    const ids = Array.from({ length: 60 }, (_, index) => index + 1)
    h.selectRows.push([], ids.map((id) => ({ id })))

    await expect(sweepAniListTrailers({ limit: 60, requestIntervalMs: 0 })).resolves.toEqual({
      scanned: 60,
      upserted: 60,
      complete: true,
      providerReachable: true,
    })
    expect(h.requested.map((chunk) => chunk.length)).toEqual([50, 10])
    expect(h.upserted.map((chunk) => chunk.length)).toEqual([50, 10])
    expect(h.stateWrites).toEqual([
      { cursor: 50, complete: false },
      { cursor: 60, complete: true },
    ])
  })

  it('keeps the last successful cursor when the provider fails partway through', async () => {
    const ids = Array.from({ length: 60 }, (_, index) => index + 1)
    h.selectRows.push([], ids.map((id) => ({ id })))
    h.fetchRows.push(ids.slice(0, 50).map((id) => ({ id })), [])

    await expect(sweepAniListTrailers({ limit: 60, requestIntervalMs: 0 })).resolves.toEqual({
      scanned: 50,
      upserted: 50,
      complete: false,
      providerReachable: false,
    })
    expect(h.stateWrites).toEqual([{ cursor: 50, complete: false }])
  })
})
