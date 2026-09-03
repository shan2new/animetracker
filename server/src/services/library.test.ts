import { describe, expect, it, vi } from 'vitest'

vi.mock('../db/index.js', () => ({ db: {} }))

const { FranchiseProgressError, progressWritesForCommand } = await import('./library.js')

const rows = [
  {
    mediaId: 1,
    status: 'FINISHED',
    episodes: 12,
    next: null,
    episodesList: [],
  },
  {
    mediaId: 2,
    status: 'RELEASING',
    episodes: 24,
    next: { episode: 8, airingAt: 2_000_000_000 },
    episodesList: [],
  },
  {
    mediaId: 3,
    status: 'NOT_YET_RELEASED',
    episodes: 10,
    next: { episode: 1, airingAt: 2_100_000_000 },
    episodesList: [],
  },
]

describe('progressWritesForCommand', () => {
  it('marks released episodes caught up without claiming an announced season was watched', () => {
    expect(progressWritesForCommand(rows, { mode: 'caught_up' })).toEqual([
      { mediaId: 1, episodes: 12 },
      { mediaId: 2, episodes: 7 },
      { mediaId: 3, episodes: 0 },
    ])
  })

  it('clamps explicit updates to each part ceiling', () => {
    expect(progressWritesForCommand(rows, { parts: [
      { mediaId: 1, episodes: 99 },
      { mediaId: 2, episodes: 9 },
    ] })).toEqual([
      { mediaId: 1, episodes: 12 },
      { mediaId: 2, episodes: 9 },
    ])
  })

  it('rejects foreign and duplicate media ids before the transaction can partially write', () => {
    expect(() => progressWritesForCommand(rows, { parts: [{ mediaId: 99, episodes: 1 }] }))
      .toThrow(FranchiseProgressError)
    expect(() => progressWritesForCommand(rows, { parts: [
      { mediaId: 1, episodes: 1 }, { mediaId: 1, episodes: 2 },
    ] })).toThrow(FranchiseProgressError)
  })
})
