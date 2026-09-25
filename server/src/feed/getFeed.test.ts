import { beforeEach, describe, expect, it, vi } from 'vitest'
import type { FeedTime, Franchise, FranchiseSummary } from '../types/api.js'
import type { ComposedPost } from './compose.js'

// `getFeed` per request (docs/api-contract.md, "Today feed"): anchors → hides → the composed posts
// minus owned, muted and hidden ones → order → cap → the viewer's social state → author rows. The
// composer is stubbed (feed/compose.test.ts covers it); `orderPosts` and `toFeedFranchise` are real.

const mocks = vi.hoisted(() => ({
  subRows: [] as { franchiseId: string }[],
  composePosts: vi.fn(),
  getFeedFranchises: vi.fn(),
  getSummaries: vi.fn(),
  trendingFranchiseIds: vi.fn(),
  readVisitAnchors: vi.fn(),
  loadResearchHistory: vi.fn(),
  loadHides: vi.fn(),
  loadPostSocial: vi.fn(),
  firstActivityAt: vi.fn(),
}))

vi.mock('../db/index.js', () => {
  const chain = {
    from: () => chain,
    where: () => chain,
    orderBy: () => Promise.resolve(mocks.subRows),
  }
  return { db: { select: () => chain }, sql: {} }
})
vi.mock('../env.js', () => ({ env: { SOCIAL_COMMENTS_ENABLED: true } }))
vi.mock('../services/franchiseView.js', () => ({
  getFeedFranchises: mocks.getFeedFranchises,
  getSummaries: mocks.getSummaries,
  trendingFranchiseIds: mocks.trendingFranchiseIds,
}))
vi.mock('../services/visits.js', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../services/visits.js')>()),
  readVisitAnchors: mocks.readVisitAnchors,
}))
vi.mock('./history.js', () => ({ loadResearchHistory: mocks.loadResearchHistory }))
vi.mock('./viewerState.js', async (importOriginal) => ({
  ...(await importOriginal<typeof import('./viewerState.js')>()),
  loadHides: mocks.loadHides,
  loadPostSocial: mocks.loadPostSocial,
  firstActivityAt: mocks.firstActivityAt,
}))
vi.mock('./compose.js', async (importOriginal) => ({
  ...(await importOriginal<typeof import('./compose.js')>()),
  composePosts: mocks.composePosts,
}))

import { FEED_LIMITS, getFeed, getPostDetail } from './service.js'

const D = 86_400_000
const H = 3_600_000
const USER = 'user-1'
const [OWNED, MUTED, F3, F4] = [
  '11111111-1111-4111-8111-111111111111',
  '22222222-2222-4222-8222-222222222222',
  '33333333-3333-4333-8333-333333333333',
  '44444444-4444-4444-8444-444444444444',
]

// For you is cached per process for 10 minutes: every test composes at its own hour.
let clock = Date.UTC(2026, 8, 25, 12)
const nextNow = () => (clock += H)

function franchise(id: string): Franchise {
  return {
    id,
    source: 'anilist',
    title: `Show ${id.slice(0, 1)}`,
    cover: '',
    banner: '',
    images: { portrait: null, landscape: null },
    artwork: { portraits: [], landscapes: [], logos: [] },
    year: 2026,
    isReleasing: false,
    upcoming: null,
    parts: [],
    videos: [],
  } as unknown as Franchise
}

function post(id: string, franchiseId: string, at: number, discoveredAt = 0): ComposedPost {
  const time: FeedTime = { at, dateOnly: false, basis: 'observed' }
  return {
    id,
    kind: 'announced',
    origin: 'research',
    franchiseId,
    installment: 'Season 2',
    isMovie: false,
    part: null,
    time,
    discoveredAt,
    premiere: null,
    window: null,
    note: null,
    video: null,
    sources: [],
    isOfficial: false,
    thread: [],
  }
}

function loaded(ids: string[], status: Record<string, string> = {}) {
  return {
    franchises: ids.map(franchise),
    memberAddedAt: new Map(),
    externalIdById: new Map(),
    statusById: new Map(Object.entries(status)),
  }
}

beforeEach(() => {
  mocks.subRows = [{ franchiseId: OWNED }, { franchiseId: MUTED }]
  mocks.composePosts.mockReset()
  mocks.getFeedFranchises.mockReset().mockImplementation(async (ids: string[]) => loaded(ids, { [OWNED]: 'watching' }))
  mocks.getSummaries.mockReset().mockImplementation(async (ids: string[]) => ids.map((id) => ({ id }) as FranchiseSummary))
  mocks.trendingFranchiseIds.mockReset().mockResolvedValue([OWNED, MUTED, F3, F4])
  mocks.loadResearchHistory.mockReset().mockResolvedValue({ observations: new Map(), announcements: new Map() })
  mocks.loadHides.mockReset().mockResolvedValue({ posts: new Set(['news:hidden']), shows: new Set([MUTED]) })
  mocks.loadPostSocial.mockReset().mockImplementation(async (_user: string, ids: string[]) =>
    new Map(ids.map((id) => [id, { viewer: { liked: id === 'news:f4', saved: false, reminded: false }, counts: { likes: 2, comments: 1 } }])))
})

describe('getFeed: For you', () => {
  it('drops owned, muted and hidden posts, orders by time alone with nothing fresh, and attaches social state', async () => {
    const now = nextNow()
    const prev = now - D
    mocks.readVisitAnchors.mockResolvedValue({ prevOpenedAt: prev, lastOpenedAt: now - H })
    mocks.composePosts.mockReturnValue([
      post('news:owned', OWNED, now - H, now - H),
      post('news:muted', MUTED, now - H, now - H),
      // Learned since the previous visit, but For you has no fresh block: it sorts by its time.
      post('news:f3', F3, now - 3 * D, now - H),
      post('news:hidden', F3, now - 2 * H, now - H),
      post('news:f4', F4, now - D, 0),
    ])

    const res = await getFeed(USER, 'foryou', now)

    expect(res.tab).toBe('foryou')
    expect(res.prevOpenedAt).toBe(prev)
    expect(res.posts.map((p) => [p.id, p.fresh])).toEqual([['news:f4', false], ['news:f3', false]])
    expect(mocks.loadPostSocial).toHaveBeenCalledWith(USER, ['news:f4', 'news:f3'])
    expect(res.posts[0]).toMatchObject({ viewer: { liked: true }, counts: { likes: 2, comments: 1 } })
    expect(res.posts[0]).not.toHaveProperty('thread')
    // Author rows for exactly the referenced shows, none of them in the viewer's library.
    expect(res.franchises.map((f) => [f.id, f.status])).toEqual([[F4, null], [F3, null]])
    expect(res.trending.map((s) => s.id)).toEqual([F3, F4])
    // The composition is the viewer-independent one: trending shows, no user id.
    expect(mocks.getFeedFranchises).toHaveBeenCalledWith([OWNED, MUTED, F3, F4], null)
  })

  it('caps at 50 posts, newest first', async () => {
    const now = nextNow()
    mocks.readVisitAnchors.mockResolvedValue({ prevOpenedAt: 0, lastOpenedAt: 0 })
    mocks.composePosts.mockReturnValue(
      Array.from({ length: 60 }, (_, i) => post(`news:n${String(i).padStart(2, '0')}`, F3, now - i * H)),
    )

    const res = await getFeed(USER, 'foryou', now)

    expect(res.posts).toHaveLength(FEED_LIMITS.forYou)
    expect(res.posts[0]?.id).toBe('news:n00')
    expect(res.posts.at(-1)?.id).toBe('news:n49')
  })
})

describe('getFeed: Following', () => {
  it('composes the library minus muted shows, puts the fresh block first, and drops hidden posts', async () => {
    const now = nextNow()
    const prev = now - D
    mocks.readVisitAnchors.mockResolvedValue({ prevOpenedAt: prev, lastOpenedAt: now - H })
    mocks.composePosts.mockReturnValue([
      post('news:old-fresh', OWNED, now - 5 * D, now - H),
      post('news:newer', OWNED, now - 2 * H, prev - H),
      post('news:hidden', OWNED, now - H, now - H),
    ])

    const res = await getFeed(USER, 'following', now)

    expect(mocks.getFeedFranchises).toHaveBeenCalledWith([OWNED], USER)
    expect(mocks.loadResearchHistory).toHaveBeenCalledWith([OWNED])
    expect(res.posts.map((p) => [p.id, p.fresh])).toEqual([['news:old-fresh', true], ['news:newer', false]])
    expect(res.franchises.map((f) => [f.id, f.status])).toEqual([[OWNED, 'watching']])
    expect(res.trending).toEqual([])
  })
})

describe('getPostDetail: a delisted trailer', () => {
  const id = `trailer:${F3}:youtube:gone0000001`

  it('stays reachable, bare and not live, while someone holds a row on it', async () => {
    const now = nextNow()
    mocks.readVisitAnchors.mockResolvedValue({ prevOpenedAt: now - D, lastOpenedAt: now - H })
    mocks.firstActivityAt.mockReset().mockResolvedValue(new Map([[id, now - 3 * D]]))

    const res = await getPostDetail(USER, id, now)

    expect(mocks.firstActivityAt).toHaveBeenCalledWith([id])
    expect(res).toMatchObject({
      live: false,
      post: { id, kind: 'trailer', video: null, installment: '', sources: [], fresh: false, time: { at: now - 3 * D } },
      franchise: { id: F3, status: null },
      storyline: [],
    })
  })

  it('is gone once nobody holds a row on it', async () => {
    const now = nextNow()
    mocks.readVisitAnchors.mockResolvedValue({ prevOpenedAt: 0, lastOpenedAt: 0 })
    mocks.firstActivityAt.mockReset().mockResolvedValue(new Map())

    expect(await getPostDetail(USER, id, now)).toBeNull()
  })
})
