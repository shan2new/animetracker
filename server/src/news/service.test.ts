import { describe, expect, it } from 'vitest'
import { newsNeedsRefresh } from './service.js'

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
