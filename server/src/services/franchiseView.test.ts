import { describe, expect, it } from 'vitest'
import type { EpisodeMeta } from '../types/api.js'
import { deriveAiredEpisodes } from './franchiseView.js'

// Fixed "now": 2026-07-01T00:00Z.
const NOW = Date.UTC(2026, 6, 1)
const D = 86_400_000

function eps(count: number, firstAirDate: number | null): EpisodeMeta[] {
  return Array.from({ length: count }, (_, i) => ({
    number: i + 1,
    title: `Episode ${i + 1}`,
    airDate: firstAirDate == null ? null : firstAirDate + i * 7 * D,
    overview: null,
    still: null,
    runtime: null,
  }))
}

describe('deriveAiredEpisodes', () => {
  it('reads the next slot as "everything before it has aired"', () => {
    expect(
      deriveAiredEpisodes({ status: 'RELEASING', totalEpisodes: 12, next: { episode: 5 }, episodes: [], nowMs: NOW }),
    ).toBe(4)
    // A next slot of episode 1 (an announced premiere) means nothing has aired.
    expect(
      deriveAiredEpisodes({ status: 'RELEASING', totalEpisodes: 12, next: { episode: 1 }, episodes: [], nowMs: NOW }),
    ).toBe(0)
  })

  it('is 0 for an announced part whatever the catalogue advertises', () => {
    expect(
      deriveAiredEpisodes({
        status: 'NOT_YET_RELEASED',
        totalEpisodes: 10,
        next: { episode: 1 },
        episodes: eps(10, NOW + 30 * D),
        nowMs: NOW,
      }),
    ).toBe(0)
  })

  it('counts the dated episode list when a releasing part has no next slot', () => {
    // TMDB nulls next_episode_to_air.air_date while the season still derives as RELEASING; AniList
    // has the same window between a finale airing and status flipping to FINISHED.
    const episodes = eps(10, NOW - 4 * 7 * D) // 5 aired (weeks -4..0), 5 still to come
    expect(deriveAiredEpisodes({ status: 'RELEASING', totalEpisodes: 10, next: null, episodes, nowMs: NOW })).toBe(5)
  })

  it('never reports the user´s own progress for a releasing part with no next slot', () => {
    // The regression this guards: the count must not move with `watched`, and an undated list
    // (AniList streamingEpisodes carry no airDate) falls back to the catalogue total.
    const episodes = eps(12, null)
    expect(deriveAiredEpisodes({ status: 'RELEASING', totalEpisodes: 12, next: null, episodes, nowMs: NOW })).toBe(12)
    expect(deriveAiredEpisodes({ status: 'RELEASING', totalEpisodes: 12, next: null, episodes: [], nowMs: NOW })).toBe(12)
  })

  it('takes the latest aired number, not the count, from a sparse dated list', () => {
    const episodes: EpisodeMeta[] = [
      { number: 1, title: null, airDate: NOW - 14 * D, overview: null, still: null, runtime: null },
      { number: 4, title: null, airDate: NOW - 1 * D, overview: null, still: null, runtime: null },
      { number: 5, title: null, airDate: NOW + 6 * D, overview: null, still: null, runtime: null },
    ]
    expect(deriveAiredEpisodes({ status: 'RELEASING', totalEpisodes: 8, next: null, episodes, nowMs: NOW })).toBe(4)
  })

  it('reports the full run for finished/cancelled parts', () => {
    expect(deriveAiredEpisodes({ status: 'FINISHED', totalEpisodes: 25, next: null, episodes: [], nowMs: NOW })).toBe(25)
    expect(deriveAiredEpisodes({ status: 'CANCELLED', totalEpisodes: 8, next: null, episodes: [], nowMs: NOW })).toBe(8)
    expect(deriveAiredEpisodes({ status: null, totalEpisodes: 0, next: null, episodes: [], nowMs: NOW })).toBe(0)
  })
})
