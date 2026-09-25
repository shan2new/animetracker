import { describe, expect, it, vi } from 'vitest'

// Never a real term in a test (social/blocklist.ts): the filter reads this fake list here.
vi.mock('../social/blocklist.js', () => ({ BLOCKED_TERMS: [{ term: 'zzbadword', match: 'word' }], NAME_ONLY_TERMS: [] }))

import type { ComposeEvidence, ComposeObservation } from './compose.js'
import { slugHeadline, storyline, threadSources } from './storyline.js'

const D = 86_400_000
const NOW = Date.UTC(2026, 8, 25, 12)
const A1 = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'

function e(overrides: Partial<ComposeEvidence> = {}): ComposeEvidence {
  return { url: 'https://x.example/a', publisher: 'X', publishedAt: null, tier: 'trade', primary: false, ...overrides }
}

let seq = 0
function obs(evidence: ComposeEvidence[], observedAt = NOW - D): ComposeObservation {
  seq += 1
  return {
    id: `00000000-0000-4000-8000-${String(seq).padStart(12, '0')}`,
    announcementId: A1,
    status: 'announced',
    next: 'Season 2',
    release: 'January 2027',
    note: null,
    observedAt,
    evidence,
  }
}

describe('slugHeadline', () => {
  it("titles the spike's own example", () => {
    expect(slugHeadline('https://www.animenewsnetwork.com/news/2026-09-15/sakamoto-days-season-2-returns-january-2027'))
      .toBe('Sakamoto Days Season 2 Returns January 2027')
  })

  it('strips an extension and a trailing article id', () => {
    expect(slugHeadline('https://a.example/news/show-gets-second-season.html')).toBe('Show Gets Second Season')
    expect(slugHeadline('https://a.example/show-gets-second-season-2026091512')).toBe('Show Gets Second Season')
  })

  it('needs at least four words and three hyphens', () => {
    expect(slugHeadline('https://a.example/news/show-season-two')).toBeNull()
    expect(slugHeadline('https://a.example/news/show-season-2-2026091512')).toBeNull()
    expect(slugHeadline('https://a.example/')).toBeNull()
    expect(slugHeadline('not a url')).toBeNull()
  })

  it('refuses ids that are not sentences', () => {
    expect(slugHeadline('https://a.example/entity-f1c31566-ec05-4d30-9b11-aa01')).toBeNull()
    expect(slugHeadline('https://a.example/news-ab12cd-ef34gh-announced-today')).toBeNull()
  })

  it('upper-cases the known acronyms and lower-cases small words after the first', () => {
    expect(slugHeadline('https://a.example/mappa-to-animate-the-new-tv-series-for-hbo'))
      .toBe('MAPPA to Animate the New TV Series for HBO')
    expect(slugHeadline('https://a.example/the-show-returns-in-spring')).toBe('The Show Returns in Spring')
  })

  it('reads percent-encoded segments', () => {
    expect(slugHeadline('https://a.example/news/pok%C3%A9mon-horizons-season-3-announced'))
      .toBe('Pokémon Horizons Season 3 Announced')
  })

  it('takes the first segment with the most hyphens', () => {
    expect(slugHeadline('https://a.example/one-two-three-four/five-six-seven-eight')).toBe('One Two Three Four')
  })

  it('prints no headline whose words carry a blocked term', () => {
    expect(slugHeadline('https://a.example/news/show-season-2-zzbadword-reveal')).toBeNull()
    // The beat still stands, led by the same report, without a headline.
    const [beat] = storyline([obs([e({ url: 'https://a.example/news/show-season-2-zzbadword-reveal', publishedAt: '2026-09-20' })])], NOW)
    expect(beat).toMatchObject({ headline: null, url: 'https://a.example/news/show-season-2-zzbadword-reveal' })
  })
})

describe('storyline', () => {
  it('makes one beat per UTC day, oldest first', () => {
    const beats = storyline([
      obs([
        e({ url: 'https://b.example/show-season-2-gets-a-date', publisher: 'B', publishedAt: '2026-09-10T23:30:00Z' }),
        e({ url: 'https://c.example/c', publisher: 'C', publishedAt: '2026-09-10' }),
      ]),
      // An official voice on a reviewed official host (feed/officialHosts.ts); anywhere else it reads as reputable.
      obs([e({ url: 'https://about.netflix.com/show-season-2-is-announced', publisher: 'A', publishedAt: '2026-06-01', tier: 'official', primary: true })], NOW - 100 * D),
    ], NOW)
    expect(beats.map((b) => b.id)).toEqual(['20260601', '20260910'])
    expect(beats[0]).toEqual({
      id: '20260601',
      day: Date.UTC(2026, 5, 1, 12),
      publishers: ['A'],
      official: true,
      primary: true,
      headline: 'Show Season 2 Is Announced',
      url: 'https://about.netflix.com/show-season-2-is-announced',
    })
    expect(beats[1]?.publishers.sort()).toEqual(['B', 'C'])
  })

  it('leads a day with the strongest report that has a readable headline', () => {
    const [beat] = storyline([obs([
      e({ url: 'https://www.crunchyroll.com/p?id=1', publisher: 'Studio', tier: 'official', publishedAt: '2026-09-10' }),
      e({ url: 'https://trade.example/show-season-2-gets-a-date', publisher: 'Trade', publishedAt: '2026-09-10' }),
    ])], NOW)
    expect(beat).toMatchObject({
      publishers: ['Studio', 'Trade'],
      official: true,
      headline: 'Show Season 2 Gets a Date',
      url: 'https://trade.example/show-season-2-gets-a-date',
    })
    const [plain] = storyline([obs([e({ url: 'https://www.crunchyroll.com/p?id=1', publisher: 'Studio', publishedAt: '2026-09-10' })])], NOW)
    expect(plain).toMatchObject({ headline: null, url: 'https://www.crunchyroll.com/p?id=1' })
  })

  it('keeps the last six beats', () => {
    const evidence = Array.from({ length: 8 }, (_, i) =>
      e({ url: `https://n.example/${i}`, publisher: `P${i}`, publishedAt: new Date(Date.UTC(2026, 0, 1 + i)).toISOString() }),
    )
    const beats = storyline([obs(evidence)], NOW)
    expect(beats).toHaveLength(6)
    expect(beats[0]?.id).toBe('20260103')
    expect(beats[5]?.id).toBe('20260108')
  })

  it('excludes catalogue entries, undated and future reports, and non-https links', () => {
    const beats = storyline([obs([
      e({ url: 'https://anilist.co/anime/1', tier: 'catalogue', publishedAt: '2026-09-01' }),
      e({ url: 'https://u.example/undated', publishedAt: null }),
      e({ url: 'https://f.example/future', publishedAt: new Date(NOW + 3 * D).toISOString() }),
      e({ url: 'javascript:alert(1)', publishedAt: '2026-09-02' }),
    ])], NOW)
    expect(beats).toEqual([])
  })

  it('counts a URL reported by several observations once', () => {
    const same = e({ url: 'https://d.example/dup', publisher: 'Dup', publishedAt: '2026-09-01' })
    const beats = storyline([obs([same]), obs([{ ...same, publisher: 'Dup Again' }], NOW - 10 * D)], NOW)
    expect(beats).toHaveLength(1)
    // The OLDEST observation's copy is the one kept.
    expect(beats[0]?.publishers).toEqual(['Dup Again'])
  })
})

describe('threadSources', () => {
  it('lists every https URL once, falling back to the host for a nameless publisher', () => {
    const sources = threadSources([
      obs([e({ url: 'https://news.example/a', publisher: null, publishedAt: '2026-09-01' })]),
      obs([e({ url: 'https://news.example/a', publisher: 'Later copy' }), e({ url: 'http://insecure.example/x' })], NOW - 5 * D),
    ], NOW)
    expect(sources).toEqual([{
      publisher: 'news.example',
      tier: 'trade',
      url: 'https://news.example/a',
      publishedAt: Date.UTC(2026, 8, 1, 12),
      dateOnly: true,
      primary: false,
    }])
  })

  it('sorts primary first, then newest, undated last, then URL', () => {
    const sources = threadSources([obs([
      e({ url: 'https://c.example/undated', publisher: 'Undated' }),
      e({ url: 'https://b.example/old', publisher: 'Old', publishedAt: '2026-01-01' }),
      e({ url: 'https://a.example/new', publisher: 'New', publishedAt: '2026-09-01' }),
      e({ url: 'https://d.example/primary', publisher: 'Primary', publishedAt: '2025-06-01', primary: true }),
      e({ url: 'https://0.example/undated', publisher: 'Undated first by URL' }),
    ])], NOW)
    expect(sources.map((s) => s.publisher)).toEqual(['Primary', 'New', 'Old', 'Undated first by URL', 'Undated'])
  })
})
