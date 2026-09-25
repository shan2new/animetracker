import { describe, expect, it, vi } from 'vitest'

vi.mock('../db/index.js', () => ({ db: {} }))

const { FranchiseProgressError, progressWritesForCommand } = await import('./library.js')

// Fixed "now": 2026-09-25T12:00Z, passed explicitly — the aired count reads no clock here.
const NOW = Date.UTC(2026, 8, 25, 12)
const sec = (ms: number) => Math.floor(ms / 1000)

const rows = [
  {
    mediaId: 1,
    source: 'anilist',
    status: 'FINISHED',
    episodes: 12,
    next: null,
    episodesList: [],
  },
  {
    // Releasing, 24 planned, episode 8 is next and still in the future: 7 aired.
    mediaId: 2,
    source: 'anilist',
    status: 'RELEASING',
    episodes: 24,
    next: { episode: 8, airingAt: sec(NOW + 3 * 86_400_000) },
    episodesList: [],
  },
  {
    mediaId: 3,
    source: 'anilist',
    status: 'NOT_YET_RELEASED',
    episodes: 10,
    next: { episode: 1, airingAt: sec(NOW + 30 * 86_400_000) },
    episodesList: [],
  },
  {
    // Releasing, and the hourly sync has not caught up: "episode 5 next" struck 20 minutes ago.
    mediaId: 4,
    source: 'anilist',
    status: 'RELEASING',
    episodes: 12,
    next: { episode: 5, airingAt: sec(NOW - 20 * 60_000) },
    episodesList: [],
  },
]

describe('progressWritesForCommand', () => {
  it('marks released episodes caught up without claiming an announced season was watched', () => {
    expect(progressWritesForCommand(rows, { mode: 'caught_up' }, NOW)).toEqual([
      { mediaId: 1, episodes: 12 },
      { mediaId: 2, episodes: 7 },
      { mediaId: 3, episodes: 0 },
      // The stale-but-passed slot counts: caught up means through episode 5, not 4.
      { mediaId: 4, episodes: 5 },
    ])
  })

  it('resets every part to 0', () => {
    expect(progressWritesForCommand(rows, { mode: 'reset' }, NOW).map((w) => w.episodes)).toEqual([0, 0, 0, 0])
  })

  it('clamps explicit updates to each part ceiling — a releasing part to what has aired, not its size', () => {
    expect(progressWritesForCommand(rows, { parts: [
      { mediaId: 1, episodes: 99 },
      { mediaId: 2, episodes: 9 },
      { mediaId: 4, episodes: 12 },
    ] }, NOW)).toEqual([
      { mediaId: 1, episodes: 12 },
      { mediaId: 2, episodes: 7 },
      { mediaId: 4, episodes: 5 },
    ])
  })

  it('never lets a season that has not premiered hold progress', () => {
    expect(progressWritesForCommand(rows, { parts: [{ mediaId: 3, episodes: 5 }] }, NOW)).toEqual([
      { mediaId: 3, episodes: 0 },
    ])
  })

  it('never pulls a stored mark down: caught up keeps a legacy over-mark, an explicit write can step below it', () => {
    // Part 2 has 7 aired; a mark of 12 was written before the aired ceiling existed.
    const held = rows.map((row) => (row.mediaId === 2 ? { ...row, watched: 12 } : row))
    expect(progressWritesForCommand(held, { mode: 'caught_up' }, NOW).find((w) => w.mediaId === 2)).toEqual({
      mediaId: 2,
      episodes: 12,
    })
    // Unmarking 12 → 11 writes 11, not 7; climbing past what it holds is still refused.
    expect(progressWritesForCommand(held, { parts: [{ mediaId: 2, episodes: 11 }] }, NOW)).toEqual([
      { mediaId: 2, episodes: 11 },
    ])
    expect(progressWritesForCommand(held, { parts: [{ mediaId: 2, episodes: 20 }] }, NOW)).toEqual([
      { mediaId: 2, episodes: 12 },
    ])
    // Only a reset walks it back.
    expect(progressWritesForCommand(held, { mode: 'reset' }, NOW).find((w) => w.mediaId === 2)?.episodes).toBe(0)
  })

  it('caught up on a releasing part in a schedule gap (no slot, no dates) marks its size, not 0', () => {
    const gap = [{ mediaId: 5, source: 'anilist', status: 'RELEASING', episodes: 12, next: null, episodesList: [] }]
    expect(progressWritesForCommand(gap, { mode: 'caught_up' }, NOW)).toEqual([{ mediaId: 5, episodes: 12 }])
  })

  it('rejects foreign and duplicate media ids before the transaction can partially write', () => {
    expect(() => progressWritesForCommand(rows, { parts: [{ mediaId: 99, episodes: 1 }] }, NOW))
      .toThrow(FranchiseProgressError)
    expect(() => progressWritesForCommand(rows, { parts: [
      { mediaId: 1, episodes: 1 }, { mediaId: 1, episodes: 2 },
    ] }, NOW)).toThrow(FranchiseProgressError)
  })
})
