import { describe, expect, it, vi } from 'vitest'

// `legacyObservation` is pure; the module's loader is not exercised here.
vi.mock('../db/index.js', () => ({ db: {}, sql: {} }))

import type { FranchiseUpcoming } from '../types/api.js'
import type { ComposeAnnouncement } from './compose.js'
import { legacyObservation } from './history.js'

// A franchise researched before migration 0008 (3 Sep) has its `upcoming` and an announcement row,
// but no observations: the feed stands its news post on one synthesized observation.

const A1 = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
const A2 = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
const FIRST_SEEN = Date.UTC(2026, 7, 20, 9)

function announcement(overrides: Partial<ComposeAnnouncement> = {}): ComposeAnnouncement {
  return { id: A1, dedupeKey: 'season 2', status: 'announced', next: 'Season 2', firstSeenAt: FIRST_SEEN, ...overrides }
}

function upcoming(overrides: Partial<FranchiseUpcoming> = {}): FranchiseUpcoming {
  return {
    status: 'announced',
    next: 'Season 2',
    release: 'January 2027',
    note: 'Announced at the finale.',
    source: 'https://a.example/news',
    checked: '2026-08-20T09:00:00.000Z',
    ...overrides,
  }
}

describe('legacyObservation', () => {
  it("synthesizes one observation keyed on the matching announcement, dated at its first sighting", () => {
    const o = legacyObservation(upcoming({
      next: 'Season 2: The Return',
      evidence: [
        { url: 'https://about.netflix.com/a', publisher: 'Netflix', publishedAt: '2026-08-19', tier: 'official', primary: true },
        { url: 'https://spoof.example/a', publisher: 'Netflix', publishedAt: null, tier: 'official', primary: false },
        { url: 'http://insecure.example/a', publisher: 'X', publishedAt: null, tier: 'trade', primary: false },
      ],
    }), [announcement({ id: A2, dedupeKey: 'season 3', next: 'Season 3' }), announcement()])
    expect(o).toEqual({
      id: `legacy:${A1}`,
      announcementId: A1,
      status: 'announced',
      next: 'Season 2: The Return',
      release: 'January 2027',
      note: 'Announced at the finale.',
      observedAt: FIRST_SEEN,
      evidence: [
        { url: 'https://about.netflix.com/a', publisher: 'Netflix', publishedAt: '2026-08-19', tier: 'official', primary: true },
        // https only, and an official claim holds only on a reviewed host.
        { url: 'https://spoof.example/a', publisher: 'Netflix', publishedAt: null, tier: 'reputable', primary: false },
      ],
    })
  })

  it('falls back to the bare source when the stored state has no evidence list', () => {
    expect(legacyObservation(upcoming(), [announcement()])?.evidence).toEqual([
      { url: 'https://a.example/news', publisher: null, publishedAt: null, tier: 'unknown', primary: false },
    ])
    expect(legacyObservation(upcoming({ source: 'javascript:alert(1)' }), [announcement()])?.evidence).toEqual([])
  })

  it('stands on nothing that is not news, has no installment, or matches no announcement', () => {
    for (const status of ['airing', 'recently_aired', 'concluded']) {
      expect(legacyObservation(upcoming({ status }), [announcement()])).toBeNull()
    }
    expect(legacyObservation(upcoming({ next: '  ' }), [announcement()])).toBeNull()
    expect(legacyObservation(upcoming({ next: 'Movie' }), [announcement()])).toBeNull()
    expect(legacyObservation(upcoming(), [])).toBeNull()
    expect(legacyObservation(null, [announcement()])).toBeNull()
  })
})
