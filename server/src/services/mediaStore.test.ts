import { beforeEach, describe, expect, it, vi } from 'vitest'
import type { MediaRow } from './mediaStore.js'

// Postgres rejects an ON CONFLICT DO UPDATE that would touch the same row twice in one statement
// ("cannot affect row a second time"), which took down three daily syncs. The batch handed to the
// insert must therefore hold each id exactly once. `db` is mocked so this needs no database,
// matching the no-DB, no-network rule the suite follows.

const recorded = vi.hoisted(() => ({ batches: [] as MediaRow[][] })) as { batches: MediaRow[][] }

vi.mock('../db/index.js', () => ({
  db: {
    insert() {
      return {
        values(rows: MediaRow[]) {
          recorded.batches.push(rows)
          return {
            onConflictDoUpdate: () => Promise.resolve([]),
            onConflictDoNothing: () => Promise.resolve([]),
          }
        },
      }
    },
  },
}))

const { aniListVideos, upsertMediaRows } = await import('./mediaStore.js')

const row = (id: number, titleRomaji: string): MediaRow => ({ id, source: 'anilist', titleRomaji })

beforeEach(() => {
  recorded.batches.length = 0
})

describe('upsertMediaRows', () => {
  it('collapses duplicate ids so the insert can never touch a row twice', async () => {
    // fetchTrending paginates; AniList's TRENDING_DESC order can shift between page requests, so
    // the same media legitimately arrives on two pages.
    await upsertMediaRows([row(1, 'a'), row(2, 'b'), row(1, 'a again'), row(3, 'c')])

    const [batch] = recorded.batches
    expect(batch?.map((r) => r.id)).toEqual([1, 2, 3])
    expect(new Set(batch?.map((r) => r.id)).size).toBe(batch?.length)
  })

  it('keeps the LAST occurrence, which carries the fresher payload', async () => {
    await upsertMediaRows([row(7, 'stale'), row(7, 'fresh')])
    expect(recorded.batches[0]).toEqual([{ id: 7, source: 'anilist', titleRomaji: 'fresh' }])
  })

  it('preserves first-seen order for the ids it keeps', async () => {
    await upsertMediaRows([row(9, 'i'), row(4, 'ii'), row(9, 'iii')])
    expect(recorded.batches[0]?.map((r) => r.id)).toEqual([9, 4])
  })

  it('issues no statement at all for an empty batch', async () => {
    await upsertMediaRows([])
    expect(recorded.batches).toHaveLength(0)
  })

  it('passes an already-unique batch through untouched', async () => {
    await upsertMediaRows([row(1, 'a'), row(2, 'b')])
    expect(recorded.batches[0]).toHaveLength(2)
  })
})

describe('aniListVideos', () => {
  it('maps the catalogue trailer without inventing unavailable metadata', () => {
    expect(aniListVideos({
      trailer: { id: 'abc_123', site: 'youtube', thumbnail: 'https://img.example/trailer.jpg' },
    } as never)).toEqual([{
      id: 'abc_123',
      site: 'youtube',
      kind: 'trailer',
      title: null,
      url: 'https://www.youtube.com/watch?v=abc_123',
      thumbnail: 'https://img.example/trailer.jpg',
      official: null,
      language: null,
      country: null,
      publishedAt: null,
    }])
  })

  it('returns no video when AniList has no usable provider id', () => {
    expect(aniListVideos({ trailer: null } as never)).toEqual([])
    expect(aniListVideos({ trailer: { id: '', site: 'youtube', thumbnail: null } } as never)).toEqual([])
  })
})
