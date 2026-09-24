import { describe, expect, it } from 'vitest'
import type { AniListMediaEnrichment, AniListRecommendation, AniListRecommendedMedia } from '../anilist/types.js'
import { aniListFranchiseEnrichment, aniListRecommendationTargets, basicAniListEnrichment } from './catalogEnrichment.js'

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
      score: 100,
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

describe('aniListRecommendationTargets', () => {
  function media(id: number, extra: Partial<AniListRecommendedMedia> = {}): AniListRecommendedMedia {
    return {
      id,
      type: 'ANIME',
      title: { english: `Show ${id}`, romaji: `Shou ${id}` },
      coverImage: { extraLarge: `https://img/${id}.jpg`, large: null },
      bannerImage: null,
      seasonYear: 2020,
      format: 'TV',
      status: 'FINISHED',
      episodes: 12,
      averageScore: 80,
      meanScore: 81,
      popularity: 50_000,
      genres: ['Action'],
      isAdult: false,
      countryOfOrigin: 'JP',
      season: 'SPRING',
      startDate: { year: 2020, month: 4, day: 3 },
      relations: { edges: [] },
      ...extra,
    }
  }
  const node = (rating: number | null, m: AniListRecommendedMedia): AniListRecommendation => ({ rating, mediaRecommendation: m })

  const later = media(40, {
    title: { english: null, romaji: 'Sequel Season 2' },
    relations: { edges: [
      { relationType: 'PREQUEL', node: { id: 39, type: 'ANIME', format: 'TV', status: 'FINISHED' } },
      { relationType: 'SEQUEL', node: { id: 41, type: 'ANIME', format: 'TV', status: 'NOT_YET_RELEASED' } },
      { relationType: 'SIDE_STORY', node: { id: 42, type: 'ANIME', format: 'OVA', status: 'RELEASING' } },
      { relationType: 'SPIN_OFF', node: { id: 43, type: 'ANIME', format: 'ONA' } },
      { relationType: 'CHARACTER', node: { id: 44, type: 'ANIME', format: 'TV' } },
      { relationType: 'ADAPTATION', node: { id: 45, type: 'MANGA', format: null } },
      { relationType: 'PARENT', node: { id: 46, type: 'ANIME', format: 'MUSIC' } },
    ] },
  })
  const items = [enriched({ recommendations: { nodes: [
    node(40, media(20, { averageScore: null, meanScore: 70, startDate: { year: 2020, month: 4, day: null } })),
    node(900, later),
    node(null, media(30, { format: 'MOVIE' })),
    node(999, media(1)), // one of the franchise's own parts
    node(800, { ...media(50), type: 'MANGA' }),
    ...Array.from({ length: 25 }, (_, i) => node(10 - i, media(100 + i))),
  ] } })]

  it('keeps twenty ranked edges with their votes, strongest first — the show page still gets ten', () => {
    const { edges } = aniListRecommendationTargets(items, new Set([1]))
    expect(edges).toHaveLength(20)
    expect(edges.slice(0, 3)).toEqual([
      { source: 'anilist', externalId: 40, rank: 0, votes: 900 },
      { source: 'anilist', externalId: 20, rank: 1, votes: 40 },
      { source: 'anilist', externalId: 100, rank: 2, votes: 10 },
    ])
    // No rating counts as zero votes: after every positive pair, ahead of the downvoted ones.
    const unrated = edges.find((edge) => edge.externalId === 30)!
    expect(unrated.votes).toBe(0)
    expect(edges.slice(0, unrated.rank).every((edge) => (edge.votes ?? 0) > 0)).toBe(true)
    expect(edges.slice(unrated.rank + 1).every((edge) => (edge.votes ?? 0) <= 0)).toBe(true)
    expect(aniListFranchiseEnrichment(items, [], new Set([1]), 0).related.map((r) => r.externalId))
      .toEqual(edges.slice(0, 10).map((e) => e.externalId))
  })

  it("records each title's facts, its series relatives and the walk start for its root", () => {
    const { targets, starts } = aniListRecommendationTargets(items, new Set([1]))
    const sequel = targets.find((t) => t.externalId === 40)!
    expect(sequel).toMatchObject({
      title: 'Sequel Season 2',
      format: 'TV',
      status: 'FINISHED',
      averageScore: 80,
      popularity: 50_000,
      airing: true, // its side story is releasing
      announced: true, // its sequel is announced
      releaseDate: '2020-04-03',
      rootId: 40, // until the walk runs
      memberIds: [40, 39, 41, 42],
      worldIds: [43, 44],
    })
    expect(starts.find((s) => s.target === sequel)).toMatchObject({ ups: [39], season: 'SPRING' })
    // meanScore stands in for a missing averageScore; a partial start date is no date.
    expect(targets.find((t) => t.externalId === 20)).toMatchObject({ averageScore: 70, releaseDate: null, memberIds: [20] })
  })
})
