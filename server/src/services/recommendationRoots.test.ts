import { describe, expect, it, vi } from 'vitest'
import type { AniListRootNode } from '../anilist/types.js'
import type { RecommendationTargetFacts } from './recommendationRank.js'
import {
  resolveSeriesRoots,
  rootOrder,
  type FranchiseSeries,
  type RootWalkIo,
  type WalkNode,
} from './recommendationRoots.js'

// The series-root walk gives a recommended "Season 4" its series (the first season): local
// franchise first, then the cached media graph, then AniList — one batched request per level.

function target(id: number, t: Partial<RecommendationTargetFacts> = {}): RecommendationTargetFacts {
  return {
    source: 'anilist',
    externalId: id,
    title: `Show ${id}`,
    year: 2020,
    images: { portrait: `cover-${id}`, landscape: null },
    format: 'TV',
    status: 'FINISHED',
    episodes: 12,
    averageScore: 75,
    voteCount: null,
    popularity: 1000,
    genres: [],
    isAdult: false,
    countryOfOrigin: 'JP',
    airing: false,
    announced: false,
    releaseDate: null,
    rootId: id,
    rootTitle: `Show ${id}`,
    rootYear: 2020,
    rootFormat: 'TV',
    rootEpisodes: 12,
    rootImages: { portrait: `cover-${id}`, landscape: null },
    memberIds: [id],
    worldIds: [],
    ...t,
  }
}

function remote(id: number, facts: Partial<AniListRootNode> & { ups?: number[] } = {}): AniListRootNode {
  const { ups = [], ...rest } = facts
  return {
    id,
    format: 'TV',
    status: 'FINISHED',
    episodes: 12,
    season: 'SPRING',
    seasonYear: 2015,
    title: { english: `Series ${id}`, romaji: null },
    coverImage: { extraLarge: `cover-${id}`, large: null },
    bannerImage: `banner-${id}`,
    relations: { edges: ups.map((up) => ({ relationType: 'PREQUEL', node: { id: up, type: 'ANIME', format: 'TV' } })) },
    ...rest,
  }
}

function io(parts: {
  owners?: Record<number, string>
  local?: WalkNode[]
  remote?: AniListRootNode[]
  series?: FranchiseSeries[]
  fail?: boolean
}): RootWalkIo & { requested: number[][] } {
  const requested: number[][] = []
  return {
    requested,
    franchisesOfMedia: vi.fn(async (ids: number[]) =>
      new Map(ids.filter((id) => parts.owners?.[id]).map((id) => [id, parts.owners![id]!]))),
    localNodes: vi.fn(async (ids: number[]) =>
      new Map((parts.local ?? []).filter((node) => ids.includes(node.id)).map((node) => [node.id, node]))),
    fetchRootNodes: vi.fn(async (ids: number[]) => {
      requested.push(ids)
      if (parts.fail) throw new Error('AniList 429')
      return (parts.remote ?? []).filter((node) => ids.includes(node.id))
    }),
    loadFranchiseSeries: vi.fn(async (ids: string[]) =>
      new Map((parts.series ?? []).filter((s) => ids.includes(s.franchiseId)).map((s) => [s.franchiseId, s]))),
  }
}

describe('rootOrder', () => {
  it('puts the earliest series entry first, ahead of any film or OVA before it', () => {
    const nodes = [
      { id: 5, format: 'TV', season: 'FALL', seasonYear: 2018 },
      { id: 4, format: 'MOVIE', season: 'SPRING', seasonYear: 2010 },
      { id: 3, format: 'TV', season: 'SPRING', seasonYear: 2018 },
      { id: 2, format: 'ONA', season: null, seasonYear: 2019 },
    ]
    expect(nodes.sort(rootOrder).map((n) => n.id)).toEqual([3, 5, 2, 4])
  })
})

describe('resolveSeriesRoots', () => {
  it('leaves a first season as its own root without asking anyone', async () => {
    const t = target(1)
    const fakes = io({})
    await expect(resolveSeriesRoots([{ target: t, ups: [] }], {}, fakes)).resolves.toEqual({ providerRequests: 0 })
    expect(t.rootId).toBe(1)
    expect(fakes.requested).toEqual([])
  })

  it('climbs a later season to its first: cached graph first, AniList for the rest, one request per level', async () => {
    const s4 = target(40, { title: 'Hero Academy Season 4', year: 2019 })
    const fakes = io({
      // Season 3 is in the local media cache; seasons 2 and 1 are not.
      local: [{ id: 30, format: 'TV', status: 'FINISHED', season: 'SPRING', seasonYear: 2018, episodes: 25, title: 'Hero Academy 3', images: { portrait: 'c30', landscape: null }, ups: [20] }],
      remote: [
        remote(20, { seasonYear: 2017, ups: [10] }),
        remote(10, { seasonYear: 2016, title: { english: 'Hero Academy', romaji: 'Boku no Hero' }, relations: { edges: [
          // A film before it never wins the root.
          { relationType: 'PREQUEL', node: { id: 5, type: 'ANIME', format: 'MOVIE' } },
        ] } }),
        remote(5, { format: 'MOVIE', seasonYear: 2015 }),
      ],
    })
    const result = await resolveSeriesRoots([{ target: s4, ups: [30] }], {}, fakes)
    expect(s4).toMatchObject({
      rootId: 10,
      rootTitle: 'Hero Academy',
      rootYear: 2016,
      rootFormat: 'TV',
      rootImages: { portrait: 'cover-10', landscape: 'banner-10' },
    })
    expect(s4.memberIds).toEqual(expect.arrayContaining([40, 30, 20, 10, 5]))
    expect(fakes.requested).toEqual([[20], [10], [5]])
    expect(result.providerRequests).toBe(3)
  })

  it('takes the franchise root when the climb reaches a show page, and walks two targets in one batch', async () => {
    const a = target(41, { title: 'Show Part 2' })
    const b = target(51, { title: 'Other S2' })
    const pace = vi.fn(async () => {})
    const fakes = io({
      owners: { 31: 'fr-show' },
      remote: [remote(50, { seasonYear: 2012 })],
      series: [{
        franchiseId: 'fr-show', source: 'anilist', externalId: null, title: 'Show', genres: ['Drama'], rootId: 11,
        rootYear: 2010, rootFormat: 'TV', rootEpisodes: 24, images: { portrait: 'show.jpg', landscape: 'show-wide.jpg' },
        memberIds: [11, 21, 31], episodes: 72, airing: true, announced: true,
      }],
    })
    await resolveSeriesRoots([{ target: a, ups: [31] }, { target: b, ups: [50] }], { pace }, fakes)
    expect(a).toMatchObject({ rootId: 11, rootTitle: 'Show', rootYear: 2010, airing: true, announced: true })
    expect(a.memberIds).toEqual(expect.arrayContaining([41, 11, 21, 31]))
    expect(b).toMatchObject({ rootId: 50, rootTitle: 'Series 50' })
    // The frontier of both walks went to AniList in ONE paced request.
    expect(fakes.requested).toEqual([[50]])
    expect(pace).toHaveBeenCalledTimes(1)
  })

  it('uses the franchise directly when the title itself is materialised', async () => {
    const t = target(21)
    const fakes = io({
      owners: { 21: 'fr-show' },
      series: [{
        franchiseId: 'fr-show', source: 'anilist', externalId: null, title: 'Show', genres: [], rootId: 11,
        rootYear: 2010, rootFormat: 'TV', rootEpisodes: 24, images: { portrait: null, landscape: null },
        memberIds: [11, 21], episodes: 48, airing: false, announced: false,
      }],
    })
    await resolveSeriesRoots([{ target: t, ups: [11] }], {}, fakes)
    expect(t.rootId).toBe(11)
    expect(fakes.requested).toEqual([])
  })

  it('degrades to the title as its own root when AniList fails', async () => {
    const t = target(40)
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => {})
    await expect(resolveSeriesRoots([{ target: t, ups: [30] }], {}, io({ fail: true }))).resolves.toEqual({ providerRequests: 1 })
    expect(t.rootId).toBe(40)
    warn.mockRestore()
  })
})
