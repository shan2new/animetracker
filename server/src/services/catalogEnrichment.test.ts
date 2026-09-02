import { describe, expect, it } from 'vitest'
import type { AniListMediaEnrichment } from '../anilist/types.js'
import { aniListFranchiseEnrichment, basicAniListEnrichment } from './catalogEnrichment.js'

const person = (id: number, full: string) => ({ id, name: { full }, image: { large: `https://img/${id}.jpg` } })

function enriched(overrides: Partial<AniListMediaEnrichment> = {}): AniListMediaEnrichment {
  return {
    id: 1,
    isAdult: false,
    tags: [],
    staff: { edges: [] },
    characters: { edges: [] },
    recommendations: { nodes: [] },
    ...overrides,
  }
}

describe('aniListFranchiseEnrichment', () => {
  it('keeps only explicitly non-spoiler, non-adult themes in rank order', () => {
    const result = aniListFranchiseEnrichment([
      enriched({
        tags: [
          { name: 'Friendship', rank: 80, isGeneralSpoiler: false, isMediaSpoiler: false, isAdult: false },
          { name: 'Hidden identity', rank: 99, isGeneralSpoiler: false, isMediaSpoiler: true, isAdult: false },
          { name: 'Nudity', rank: 95, isGeneralSpoiler: false, isMediaSpoiler: false, isAdult: true },
          { name: 'Found Family', rank: 90, isGeneralSpoiler: false, isMediaSpoiler: false, isAdult: false },
        ],
      }),
    ], ['Drama'], new Set(), 0)

    expect(result.themes).toEqual(['Found Family', 'Friendship', 'Drama'])
    expect(result.isAdult).toBe(false)
    expect(result.checkedAt).toBe('1970-01-01T00:00:00.000Z')
  })

  it('maps creators, directors, voice cast, and deduplicated external recommendations', () => {
    const result = aniListFranchiseEnrichment([
      enriched({
        staff: { edges: [
          { role: 'Original Creator', node: person(1, 'Author') },
          { role: 'Director', node: person(2, 'Director') },
        ] },
        characters: { edges: [
          { role: 'MAIN', node: person(10, 'Hero'), voiceActors: [person(3, 'Voice Actor')] },
        ] },
        recommendations: { nodes: [
          {
            rating: 100,
            mediaRecommendation: {
              id: 99,
              type: 'ANIME',
              title: { english: 'Related', romaji: null },
              coverImage: { extraLarge: 'https://img/portrait.jpg', large: null },
              bannerImage: 'https://img/landscape.jpg',
              seasonYear: 2025,
            },
          },
          {
            rating: 90,
            mediaRecommendation: {
              id: 1,
              type: 'ANIME',
              title: { english: 'Same franchise', romaji: null },
              coverImage: { extraLarge: null, large: null },
              bannerImage: null,
              seasonYear: 2020,
            },
          },
        ] },
      }),
    ], [], new Set([1]), 0)

    expect(result.people.creators[0]).toMatchObject({ name: 'Author', role: 'Original Creator' })
    expect(result.people.directors[0]).toMatchObject({ name: 'Director', role: 'Director' })
    expect(result.people.cast[0]).toMatchObject({ name: 'Voice Actor', role: 'Hero' })
    expect(result.related).toEqual([{
      source: 'anilist',
      externalId: 99,
      franchiseId: null,
      title: 'Related',
      year: 2025,
      images: { portrait: 'https://img/portrait.jpg', landscape: 'https://img/landscape.jpg' },
    }])
  })

  it('does not expose manga recommendations as playable anime titles', () => {
    const result = aniListFranchiseEnrichment([
      enriched({
        recommendations: { nodes: [{
          rating: 100,
          mediaRecommendation: {
            id: 77,
            type: 'MANGA',
            title: { english: 'Source Manga', romaji: null },
            coverImage: { extraLarge: null, large: null },
            bannerImage: null,
            seasonYear: 2020,
          },
        }] },
      }),
    ], [], new Set(), 0)

    expect(result.related).toEqual([])
  })
})

describe('basicAniListEnrichment', () => {
  it('ships genres and audience state immediately while marking graph metadata basic', () => {
    const result = basicAniListEnrichment({ isAdult: true } as never, ['Action', 'Action'], 0)
    expect(result).toMatchObject({ level: 'basic', themes: ['Action'], isAdult: true })
    expect(result.people).toEqual({ creators: [], directors: [], cast: [] })
  })
})
