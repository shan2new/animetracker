import { describe, expect, it, vi } from 'vitest'

// Never a real term in a test (social/blocklist.ts): the filter reads this fake list here.
vi.mock('../social/blocklist.js', () => ({ BLOCKED_TERMS: [{ term: 'zzbadword', match: 'word' }], NAME_ONLY_TERMS: [] }))

import {
  AGENT_TEXT_LIMITS,
  parseEvidenceDate,
  rankSources,
  safeHttpsUrl,
  sanitizeAgentText,
  sanitizeEvidence,
  TIER_RANK,
  tierRank,
  verifiedTier,
  type RankableEvidence,
} from './evidence.js'
import { isOfficialHost, OFFICIAL_HOSTS } from './officialHosts.js'

const NOW = Date.UTC(2026, 8, 25, 12)

function ev(overrides: Partial<RankableEvidence> = {}): RankableEvidence {
  return {
    url: 'https://example.com/a',
    publisher: 'Example',
    publishedAt: null,
    tier: 'trade',
    primary: false,
    observedAt: NOW,
    ...overrides,
  }
}

describe('safeHttpsUrl', () => {
  it('passes a plain https URL through unchanged', () => {
    expect(safeHttpsUrl('https://www.crunchyroll.com/news/a-b-c')).toBe('https://www.crunchyroll.com/news/a-b-c')
    expect(safeHttpsUrl('https://x.y/?q=1#frag')).toBe('https://x.y/?q=1#frag')
  })

  it('rejects every other scheme', () => {
    for (const url of ['javascript:alert(1)', 'http://example.com', 'myapp://open', 'ftp://example.com/x', 'data:text/html,hi']) {
      expect(safeHttpsUrl(url)).toBeNull()
    }
  })

  it('rejects credentials, missing hosts, whitespace, junk and over-length URLs', () => {
    expect(safeHttpsUrl('https://user:pass@example.com/')).toBeNull()
    expect(safeHttpsUrl('https://user@example.com/')).toBeNull()
    expect(safeHttpsUrl('https://')).toBeNull()
    expect(safeHttpsUrl(' https://example.com')).toBeNull()
    expect(safeHttpsUrl('https://example.com/a b')).toBeNull()
    expect(safeHttpsUrl('not a url')).toBeNull()
    expect(safeHttpsUrl('')).toBeNull()
    expect(safeHttpsUrl(null)).toBeNull()
    expect(safeHttpsUrl(undefined)).toBeNull()
    const long = `https://example.com/${'a'.repeat(2048)}`
    expect(safeHttpsUrl(long)).toBeNull()
    expect(safeHttpsUrl(`https://example.com/${'a'.repeat(2048 - 20)}`)).not.toBeNull()
  })
})

describe('sanitizeEvidence', () => {
  it('drops every entry whose URL is not safe https and keeps the rest in order', () => {
    const list = [
      { url: 'https://a.com/1', n: 1 },
      { url: 'javascript:alert(1)', n: 2 },
      { url: 'http://b.com', n: 3 },
      { url: 'https://c.com/3', n: 4 },
    ]
    expect(sanitizeEvidence(list).map((e) => e.n)).toEqual([1, 4])
  })

  it("downgrades an unverified official claim to reputable and keeps every other tier as claimed", () => {
    const list = sanitizeEvidence([
      { url: 'https://about.netflix.com/en/news/a', tier: 'official', publisher: 'Netflix' },
      { url: 'https://netflix-tudum.example/a', tier: 'official', publisher: 'Netflix' },
      { url: 'https://trade.example/a', tier: 'trade', publisher: 'Trade' },
    ])
    expect(list.map((e) => e.tier)).toEqual(['official', 'reputable', 'trade'])
    // Idempotent: a second pass changes nothing.
    expect(sanitizeEvidence(list)).toEqual(list)
  })

  it("names a source by its host when the agent's publisher carries a link or a blocked term", () => {
    const [linked, blocked, blank, clean] = sanitizeEvidence([
      { url: 'https://news.example/a', publisher: 'Visit discord.gg/x' },
      { url: 'https://other.example/a', publisher: 'The zzbadword Times' },
      { url: 'https://third.example/a', publisher: '   ' },
      { url: 'https://fourth.example/a', publisher: '  Anime​  News ' },
    ])
    expect(linked?.publisher).toBe('news.example')
    expect(blocked?.publisher).toBe('other.example')
    expect(blank?.publisher).toBeNull()
    expect(clean?.publisher).toBe('Anime News')
  })
})

describe('verifiedTier / isOfficialHost', () => {
  it('holds an official claim only on a listed host or its subdomain', () => {
    expect(verifiedTier('https://about.netflix.com/en/news/x', 'official')).toBe('official')
    expect(verifiedTier('https://www.crunchyroll.com/news/x', 'official')).toBe('official')
    expect(verifiedTier('https://NETFLIX.COM./x', 'official')).toBe('official')
    for (const url of ['https://netflix-news.example/x', 'https://notnetflix.com/x', 'https://netflix.com.evil.example/x', 'not a url']) {
      expect(verifiedTier(url, 'official')).toBe('reputable')
    }
  })

  it('never raises a lower claim', () => {
    for (const tier of ['trade', 'reputable', 'unknown', 'catalogue'] as const) {
      expect(verifiedTier('https://about.netflix.com/x', tier)).toBe(tier)
    }
  })

  it('lists no user-content platform and no duplicate', () => {
    for (const host of ['youtube.com', 'x.com', 'twitter.com', 'instagram.com', 'reddit.com', 'tiktok.com']) {
      expect(isOfficialHost(`https://${host}/a`)).toBe(false)
    }
    expect(new Set(OFFICIAL_HOSTS).size).toBe(OFFICIAL_HOSTS.length)
    for (const host of OFFICIAL_HOSTS) expect(host).toBe(host.toLowerCase())
  })
})

describe('sanitizeAgentText', () => {
  it('folds agent text to one clean line and caps it on a word boundary', () => {
    expect(sanitizeAgentText('  Season\n\t2​ ', AGENT_TEXT_LIMITS.installment)).toBe('Season 2')
    const long = sanitizeAgentText('word '.repeat(40), AGENT_TEXT_LIMITS.installment)!
    expect([...long].length).toBeLessThanOrEqual(AGENT_TEXT_LIMITS.installment)
    expect(long.endsWith('word…')).toBe(true)
  })

  it('refuses text carrying a link or a blocked term, and empty text', () => {
    expect(sanitizeAgentText('Details at discord.gg/x', AGENT_TEXT_LIMITS.note)).toBeNull()
    expect(sanitizeAgentText('see https://a.example/b', AGENT_TEXT_LIMITS.note)).toBeNull()
    expect(sanitizeAgentText('Season 2 zzbadword', AGENT_TEXT_LIMITS.installment)).toBeNull()
    expect(sanitizeAgentText('  ​ ', AGENT_TEXT_LIMITS.installment)).toBeNull()
    expect(sanitizeAgentText(null, AGENT_TEXT_LIMITS.installment)).toBeNull()
  })
})

describe('parseEvidenceDate', () => {
  it('reads an ISO instant with and without fractional seconds, Z or an offset', () => {
    expect(parseEvidenceDate('2026-09-15T10:30:00Z', NOW)).toEqual({ ms: Date.UTC(2026, 8, 15, 10, 30), dateOnly: false })
    expect(parseEvidenceDate('2026-09-15T10:30:00.250Z', NOW)).toEqual({ ms: Date.UTC(2026, 8, 15, 10, 30, 0, 250), dateOnly: false })
    expect(parseEvidenceDate('2026-09-15T10:30:00.123456+09:00', NOW)).toEqual({
      ms: Date.UTC(2026, 8, 15, 1, 30, 0, 123),
      dateOnly: false,
    })
    expect(parseEvidenceDate('2026-09-15T10:30:00-0500', NOW)).toEqual({ ms: Date.UTC(2026, 8, 15, 15, 30), dateOnly: false })
  })

  it('reads a YYYY-MM-DD prefix as 12:00 UTC of that day', () => {
    expect(parseEvidenceDate('2026-09-15', NOW)).toEqual({ ms: Date.UTC(2026, 8, 15, 12), dateOnly: true })
    expect(parseEvidenceDate('2026-9-5', NOW)).toEqual({ ms: Date.UTC(2026, 8, 5, 12), dateOnly: true })
    // A timestamp without a zone is not an instant; its day still stands.
    expect(parseEvidenceDate('2026-09-15T10:30:00', NOW)).toEqual({ ms: Date.UTC(2026, 8, 15, 12), dateOnly: true })
  })

  it('rejects a date that does not exist, a year out of range, and non-dates', () => {
    expect(parseEvidenceDate('2026-02-30', NOW)).toBeNull()
    expect(parseEvidenceDate('2026-13-01', NOW)).toBeNull()
    expect(parseEvidenceDate('1800-01-01', NOW)).toBeNull()
    expect(parseEvidenceDate('1800-01-01T00:00:00Z', NOW)).toBeNull()
    expect(parseEvidenceDate('September 2026', NOW)).toBeNull()
    expect(parseEvidenceDate('', NOW)).toBeNull()
    expect(parseEvidenceDate(null, NOW)).toBeNull()
  })

  it('rejects a date more than 24 hours in the future', () => {
    expect(parseEvidenceDate(new Date(NOW + 86_400_000).toISOString(), NOW)).not.toBeNull()
    expect(parseEvidenceDate(new Date(NOW + 86_400_001).toISOString(), NOW)).toBeNull()
    expect(parseEvidenceDate('2026-09-27', NOW)).toBeNull()
  })
})

describe('TIER_RANK', () => {
  it('orders voice from official to catalogue, unknown tiers last', () => {
    expect(TIER_RANK).toEqual({ official: 0, trade: 1, reputable: 2, unknown: 3, catalogue: 4 })
    expect(tierRank('press-release')).toBe(5)
  })
})

describe('rankSources', () => {
  it('leads with a primary announcement, then by tier', () => {
    const sources = rankSources([
      ev({ url: 'https://a.com', publisher: 'Reputable', tier: 'reputable' }),
      ev({ url: 'https://b.com', publisher: 'Official', tier: 'official' }),
      ev({ url: 'https://c.com', publisher: 'Primary Trade', tier: 'trade', primary: true }),
    ], NOW)
    expect(sources.map((s) => s.publisher)).toEqual(['Primary Trade', 'Official', 'Reputable'])
  })

  it('names a publisher once, case-insensitively, keeping the best-ranked entry', () => {
    const sources = rankSources([
      ev({ url: 'https://a.com/1', publisher: 'crunchyroll', tier: 'trade' }),
      ev({ url: 'https://a.com/2', publisher: ' Crunchyroll ', tier: 'official' }),
    ], NOW)
    expect(sources).toHaveLength(1)
    expect(sources[0]).toMatchObject({ publisher: 'Crunchyroll', tier: 'official', url: 'https://a.com/2' })
  })

  it('drops entries without a publisher', () => {
    const sources = rankSources([ev({ publisher: null }), ev({ publisher: '   ' }), ev({ url: 'https://b.com', publisher: 'B' })], NOW)
    expect(sources.map((s) => s.publisher)).toEqual(['B'])
  })

  it('removes catalogue entries unless nothing editorial remains', () => {
    const mixed = rankSources([
      ev({ url: 'https://anilist.co/anime/1', publisher: 'AniList', tier: 'catalogue' }),
      ev({ url: 'https://b.com', publisher: 'B', tier: 'unknown' }),
    ], NOW)
    expect(mixed.map((s) => s.publisher)).toEqual(['B'])
    const alone = rankSources([ev({ url: 'https://anilist.co/anime/1', publisher: 'AniList', tier: 'catalogue' })], NOW)
    expect(alone.map((s) => s.publisher)).toEqual(['AniList'])
  })

  it('caps at eight', () => {
    const many = Array.from({ length: 12 }, (_, i) => ev({ url: `https://s${i}.com`, publisher: `S${i}` }))
    expect(rankSources(many, NOW)).toHaveLength(8)
  })

  it('breaks ties by newest observation, then URL, whatever the input order', () => {
    const a = ev({ url: 'https://z.com', publisher: 'Old', observedAt: NOW - 1000 })
    const b = ev({ url: 'https://y.com', publisher: 'NewY', observedAt: NOW })
    const c = ev({ url: 'https://x.com', publisher: 'NewX', observedAt: NOW })
    const expected = ['NewX', 'NewY', 'Old']
    expect(rankSources([a, b, c], NOW).map((s) => s.publisher)).toEqual(expected)
    expect(rankSources([c, a, b], NOW).map((s) => s.publisher)).toEqual(expected)
  })

  it('carries the parsed publish date', () => {
    const [source] = rankSources([ev({ publishedAt: '2026-09-01' })], NOW)
    expect(source).toEqual({
      publisher: 'Example',
      tier: 'trade',
      url: 'https://example.com/a',
      publishedAt: Date.UTC(2026, 8, 1, 12),
      dateOnly: true,
      primary: false,
    })
  })
})
