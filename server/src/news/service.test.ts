import { PgDialect } from 'drizzle-orm/pg-core'
import { describe, expect, it } from 'vitest'
import { newsNeedsRefresh, normalizedEvidence, reminderHoldersWhere, storableEvidence } from './service.js'

const NOW = Date.parse('2026-09-02T12:00:00.000Z')

describe('newsNeedsRefresh', () => {
  it('refreshes a franchise that has never been researched', () => {
    expect(newsNeedsRefresh(null, NOW, 20)).toBe(true)
  })

  it('keeps a recently checked result without regard to its classification', () => {
    expect(newsNeedsRefresh({ checked: '2026-09-02T00:00:00.000Z' }, NOW, 20)).toBe(false)
  })

  it('refreshes stale or malformed checked timestamps', () => {
    expect(newsNeedsRefresh({ checked: '2026-09-01T00:00:00.000Z' }, NOW, 20)).toBe(true)
    expect(newsNeedsRefresh({ checked: 'not-a-date' }, NOW, 20)).toBe(true)
  })

  it('enriches a fresh catalogue fallback with an authoritative announcement source', () => {
    expect(
      newsNeedsRefresh(
        { checked: '2026-09-02T11:59:00.000Z', source: 'https://www.themoviedb.org/tv/82596' },
        NOW,
        20,
      ),
    ).toBe(true)
  })
})

describe('reminderHoldersWhere (who hears an announcement besides subscribers)', () => {
  const FRANCHISE = '33333333-3333-4333-8333-333333333333'
  const NEWS = 'news:44444444-4444-4444-8444-444444444444'

  // The app says "News about it will show in Activity" for every undated reminder, including one on
  // a trailer post (never re-keyed) and one on a catalogue post adoption could not match.
  it("reaches the news post's holders and every non-news reminder on the show", () => {
    const q = new PgDialect().sqlToQuery(reminderHoldersWhere(FRANCHISE, NEWS))
    expect(q.sql).toBe(
      '("reminders"."post_id" = $1 or ("reminders"."franchise_id" = $2 and "reminders"."post_id" not like $3))',
    )
    expect(q.params).toEqual([NEWS, FRANCHISE, 'news:%'])
  })
})

describe('stored evidence (write-side hygiene)', () => {
  const item = (url: string, tier: 'official' | 'trade' | 'reputable' | 'catalogue' | 'unknown' = 'official') =>
    ({ url, publisher: 'Netflix', publishedAt: null, tier, primary: true })

  // The agent reads arbitrary pages, so its "official" is a claim: a page calling itself Netflix on
  // an unlisted host is stored as reputable, exactly as the feed reads it.
  it('keeps an official tier only on a reviewed official host', () => {
    expect(storableEvidence([
      item('https://about.netflix.com/en/news/season-2'),
      item('https://netflix-news.example/season-2'),
      item('https://netflix.com.evil.example/season-2'),
      item('https://trade.example/a', 'trade'),
    ]).map((e) => e.tier)).toEqual(['official', 'reputable', 'reputable', 'trade'])
  })

  it('stores https links only, once per URL, at most five', () => {
    const stored = storableEvidence([
      item('javascript:alert(1)'),
      item('http://about.netflix.com/a'),
      ...Array.from({ length: 7 }, (_, i) => item(`https://s${i}.example/a`, 'trade')),
      item('https://s0.example/a', 'unknown'),
    ])
    expect(stored.map((e) => e.url)).toEqual([0, 1, 2, 3, 4].map((i) => `https://s${i}.example/a`))
    expect(stored[0]?.tier).toBe('trade')
  })

  it('stands the bare source in for an empty list, at tier unknown', () => {
    expect(normalizedEvidence({ evidence: [], source: 'https://a.example/x' })).toEqual([
      { url: 'https://a.example/x', publisher: null, publishedAt: null, tier: 'unknown', primary: false },
    ])
    expect(normalizedEvidence({ evidence: [], source: 'http://a.example/x' })).toEqual([])
    expect(normalizedEvidence({ evidence: [], source: null })).toEqual([])
  })
})
