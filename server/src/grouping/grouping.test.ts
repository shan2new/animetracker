import { describe, expect, it } from 'vitest'
import type { AniListMedia, MediaFormat, RelationType } from '../anilist/types.js'
import { deterministicGroup } from './deterministic.js'
import { expandComponent } from './graph.js'
import { groupingTier, type GroupingInput } from './llm.js'

// Build a minimal AniListMedia for fixtures.
function m(
  id: number,
  opts: { format?: MediaFormat; year?: number; rel?: [RelationType, number, MediaFormat?][] } = {},
): AniListMedia {
  return {
    id,
    title: { romaji: `Title ${id}`, english: `Title ${id}` },
    coverImage: { extraLarge: null, large: null },
    bannerImage: null,
    description: `Synopsis ${id}`,
    genres: ['Action'],
    episodes: 12,
    format: opts.format ?? 'TV',
    status: 'FINISHED',
    season: 'SPRING',
    seasonYear: opts.year ?? 2013,
    popularity: 1000 - id,
    trending: 0,
    nextAiringEpisode: null,
    relations: {
      edges: (opts.rel ?? []).map(([relationType, nodeId, fmt]) => ({
        relationType,
        node: { id: nodeId, type: 'ANIME', format: fmt ?? 'TV' },
      })),
    },
  }
}

describe('expandComponent', () => {
  it('follows sequel/prequel/side_story but not alternative/spin_off', async () => {
    // 1 (S1) -SEQUEL-> 2 (S2) -SEQUEL-> 3 (S3); 1 -SIDE_STORY-> 10 (movie);
    // 2 -ALTERNATIVE-> 99 (a reboot we must NOT merge); 3 -SPIN_OFF-> 88 (must NOT merge)
    const graph: Record<number, AniListMedia> = {
      1: m(1, { year: 2013, rel: [['SEQUEL', 2], ['SIDE_STORY', 10, 'MOVIE']] }),
      2: m(2, { year: 2017, rel: [['PREQUEL', 1], ['SEQUEL', 3], ['ALTERNATIVE', 99]] }),
      3: m(3, { year: 2019, rel: [['PREQUEL', 2], ['SPIN_OFF', 88]] }),
      10: m(10, { format: 'MOVIE', year: 2015, rel: [['PARENT', 1]] }),
      99: m(99, { year: 2020 }),
      88: m(88, { year: 2021 }),
    }
    const fetcher = async (ids: number[]) => ids.map((id) => graph[id]).filter((x): x is AniListMedia => !!x)
    const comp = await expandComponent(1, fetcher)
    expect([...comp.keys()].sort((a, b) => a - b)).toEqual([1, 2, 3, 10])
    expect(comp.has(99)).toBe(false)
    expect(comp.has(88)).toBe(false)
  })

  it('is bounded and handles missing nodes', async () => {
    const fetcher = async (ids: number[]) => ids.flatMap((id) => (id === 1 ? [m(1, { rel: [['SEQUEL', 2]] })] : []))
    const comp = await expandComponent(1, fetcher)
    expect([...comp.keys()]).toEqual([1])
  })
})

describe('groupingTier', () => {
  const cand = (id: number): GroupingInput['candidates'][number] => ({
    id,
    title: `T${id}`,
    format: 'TV',
    status: 'FINISHED',
    seasonYear: 2013,
    episodes: 12,
    synopsis: '',
  })

  it('skips the LLM for a single-member component', () => {
    expect(groupingTier({ candidates: [cand(1)], edges: [] })).toBe('deterministic')
  })

  it('skips the LLM for a pure sequel chain (no side-story to split)', () => {
    const input: GroupingInput = {
      candidates: [cand(1), cand(2), cand(3)],
      edges: [
        { from: 1, to: 2, type: 'SEQUEL' },
        { from: 2, to: 3, type: 'SEQUEL' },
      ],
    }
    expect(groupingTier(input)).toBe('deterministic')
  })

  it('uses the standard model for a single side-story', () => {
    const input: GroupingInput = {
      candidates: [cand(1), cand(2), cand(10)],
      edges: [
        { from: 1, to: 2, type: 'SEQUEL' },
        { from: 1, to: 10, type: 'SIDE_STORY' },
      ],
    }
    expect(groupingTier(input)).toBe('standard')
  })

  it('escalates when there are multiple distinct side-story targets', () => {
    const input: GroupingInput = {
      candidates: [cand(1), cand(10), cand(11)],
      edges: [
        { from: 1, to: 10, type: 'SIDE_STORY' },
        { from: 1, to: 11, type: 'SIDE_STORY' },
      ],
    }
    expect(groupingTier(input)).toBe('escalate')
  })
})

describe('deterministicGroup', () => {
  it('buckets by format and sequences chronologically within a kind', () => {
    const input: GroupingInput = {
      candidates: [
        { id: 3, title: 'AoT S3', format: 'TV', status: 'FINISHED', seasonYear: 2018, episodes: 22, synopsis: '' },
        { id: 1, title: 'AoT S1', format: 'TV', status: 'FINISHED', seasonYear: 2013, episodes: 25, synopsis: '' },
        { id: 2, title: 'AoT S2', format: 'TV', status: 'FINISHED', seasonYear: 2017, episodes: 12, synopsis: '' },
        { id: 10, title: 'AoT Movie', format: 'MOVIE', status: 'FINISHED', seasonYear: 2015, episodes: 1, synopsis: '' },
      ],
      edges: [],
    }
    const res = deterministicGroup(input)
    expect(res.franchises).toHaveLength(1)
    const f = res.franchises[0]!
    const seasons = f.parts.filter((p) => p.partKind === 'season').sort((a, b) => a.sequence - b.sequence)
    expect(seasons.map((s) => s.id)).toEqual([1, 2, 3]) // chronological
    expect(seasons.map((s) => s.sequence)).toEqual([1, 2, 3])
    const movies = f.parts.filter((p) => p.partKind === 'movie')
    expect(movies).toHaveLength(1)
    expect(movies[0]!.sequence).toBe(1)
    // canonical name = earliest season's title
    expect(f.canonicalName).toBe('AoT S1')
  })
})
