import { describe, expect, it } from 'vitest'
import type { ArtworkImage } from '../types/api.js'
import { isTextlessArtwork, limitArtwork, rankArtwork, rankLogos } from './artwork.js'

const titled = (id: number): ArtworkImage => ({
  url: `titled-${id}.jpg`, source: 'tmdb', width: 2000, height: 3000, language: 'en', score: 10 - id,
})
const clean: ArtworkImage = {
  url: 'clean.jpg', source: 'tmdb', width: 1000, height: 1500, language: null, score: 1,
}
const legacy: ArtworkImage = {
  url: 'legacy.jpg', source: 'tmdb', width: null, height: null, language: null, score: null,
}
const crowd = Array.from({ length: 8 }, (_, index) => titled(index))

describe('artwork identity retention', () => {
  it('keeps the top-ranked poster and the clean candidate within six slots', () => {
    const result = rankArtwork([...crowd, clean], 6, true)
    expect(result).toEqual([...crowd.slice(0, 5), clean])
  })
  it('preserves clean art through another ranking and a response merge', () => {
    const ranked = rankArtwork([...crowd, clean], 6, true)
    expect(rankArtwork([...ranked, legacy], 6, true)).toContainEqual(clean)
    expect(limitArtwork([...crowd, legacy, ...ranked], 6, true)).toContainEqual(clean)
  })
  it('does not mistake a missing-language legacy poster for textless art', () => {
    expect(isTextlessArtwork(legacy)).toBe(false)
    expect(isTextlessArtwork({ ...clean, source: 'anilist' })).toBe(false)
    expect(isTextlessArtwork({ ...clean, height: 0 })).toBe(false)
    expect(isTextlessArtwork(titled(0))).toBe(false)
    expect(rankArtwork([...crowd, legacy], 6, true)).toEqual(crowd.slice(0, 6))
  })
  it('recognizes clean-only galleries, without requiring a titled sibling', () => {
    expect(isTextlessArtwork(clean)).toBe(true)
    expect(rankArtwork([clean], 6, true)).toEqual([clean])
  })
  it('deduplicates and keeps the original ranking if clean art already fits', () => {
    expect(rankArtwork([titled(0), clean, clean], 6, true)).toEqual([titled(0), clean])
  })
  it('upgrades a duplicate URL-only entry before classifying its artwork', () => {
    const unknown = { ...legacy, url: clean.url }
    expect(limitArtwork([unknown, ...crowd, clean], 6, true)[0]).toEqual(clean)
    expect(limitArtwork([unknown, ...crowd, { ...clean, language: 'en' }], 6, true)
      .some(isTextlessArtwork)).toBe(false)
  })
  it('leaves logo ranking untouched and honors small or empty limits', () => {
    expect(rankArtwork([...crowd, clean])).toEqual(crowd.slice(0, 6))
    expect(rankArtwork([...crowd, clean], 1, true)).toEqual([crowd[0]])
    expect(rankArtwork([...crowd, clean], 0, true)).toEqual([])
    expect(rankArtwork([], 6, true)).toEqual([])
  })
})

describe('logo ranking', () => {
  const logo = (url: string, width: number, height: number, score: number | null, language: string | null = 'en'): ArtworkImage => ({
    url, source: 'tmdb', width, height, language, score,
  })
  it("prefers the catalogue's voted logo over a larger unvoted, season-stamped one", () => {
    // Re:ZERO, production data, 24 Sep: the 1200×478 "SEASON 3" mark (score 0) led three plain
    // 796×249 marks scored 3.334 under the size-first ranking.
    const stamped = logo('season3.png', 1200, 478, 0)
    const plain = [logo('a.png', 796, 249, 3.334), logo('b.png', 796, 249, 3.334), logo('c.png', 796, 249, 3.334)]
    expect(rankArtwork([stamped, ...plain])[0]).toEqual(stamped)
    expect(rankLogos([stamped, ...plain])[0]).toEqual(plain[0])
    expect(rankLogos([stamped, ...plain])).toHaveLength(4)
  })
  it('puts English marks first, then size among equal scores', () => {
    const ja = logo('ja.png', 1600, 600, 9, 'ja')
    const small = logo('small.png', 400, 150, 5)
    const large = logo('large.png', 1200, 450, 5)
    expect(rankLogos([ja, small, large]).map((l) => l.url)).toEqual(['large.png', 'small.png', 'ja.png'])
  })
  it('deduplicates and honours the limit', () => {
    const a = logo('a.png', 796, 249, 3)
    expect(rankLogos([a, a, a])).toEqual([a])
    expect(rankLogos([a, logo('b.png', 10, 10, 1)], 1)).toEqual([a])
  })
})
