import Fastify, { type FastifyReply, type FastifyRequest } from 'fastify'
import { beforeEach, describe, expect, it, vi } from 'vitest'

const mocks = vi.hoisted(() => ({
  getWatchAvailability: vi.fn(),
  getFranchise: vi.fn(),
  getSummaries: vi.fn(),
  enqueueFranchiseNewsRefresh: vi.fn(),
  searchFranchises: vi.fn(),
  refreshTvUpcomingFact: vi.fn(),
  enqueueFranchiseEnrichment: vi.fn(),
}))

vi.mock('../services/watchAvailability.js', () => ({
  getWatchAvailability: mocks.getWatchAvailability,
}))
vi.mock('../services/franchiseView.js', () => ({
  getFranchise: mocks.getFranchise,
  getSummaries: mocks.getSummaries,
  getTrendingFranchises: vi.fn(async () => []),
}))
vi.mock('../news/service.js', () => ({
  enqueueFranchiseNewsRefresh: mocks.enqueueFranchiseNewsRefresh,
}))
vi.mock('../tmdb/service.js', () => ({
  refreshTvUpcomingFact: mocks.refreshTvUpcomingFact,
}))
vi.mock('../services/search.js', () => ({
  searchFranchises: mocks.searchFranchises,
}))
vi.mock('../services/catalogEnrichment.js', () => ({
  enqueueFranchiseEnrichment: mocks.enqueueFranchiseEnrichment,
}))

const { franchiseRoutes } = await import('./franchises.js')
const ID = '11111111-1111-4111-8111-111111111111'

async function appWithUser() {
  const app = Fastify()
  app.decorate('authenticate', async (req: FastifyRequest, _reply: FastifyReply) => {
    req.user = { id: ID, clerkId: 'user_test' }
  })
  await app.register(franchiseRoutes)
  await app.ready()
  return app
}

beforeEach(() => {
  mocks.getWatchAvailability.mockReset()
  mocks.getFranchise.mockReset()
  mocks.getSummaries.mockReset().mockResolvedValue([])
  mocks.enqueueFranchiseNewsRefresh.mockReset()
  mocks.searchFranchises.mockReset().mockResolvedValue({ franchises: [] })
  mocks.refreshTvUpcomingFact.mockReset().mockResolvedValue(null)
  mocks.enqueueFranchiseEnrichment.mockReset()
  mocks.getWatchAvailability.mockResolvedValue({
    country: 'IN',
    status: 'not_available',
    providers: [],
    link: null,
    attribution: 'JustWatch',
  })
})

describe('GET /search', () => {
  it('ships announcement data on the search result and starts exact-title enrichment there', async () => {
    const upcoming = {
      status: 'upcoming_dated',
      next: 'Season 6',
      release: '2026-12-24',
      note: null,
      source: 'https://www.themoviedb.org/tv/82596',
      checked: '2026-09-02T12:00:00.000Z',
      releaseWindow: { date: '2026-12-24', precision: 'day', sortKey: 20261224 },
    }
    mocks.searchFranchises.mockResolvedValueOnce({
      franchises: [{ id: ID, title: 'Emily in Paris', upcoming }],
      sources: { anilist: 'ok', tmdb: 'ok' },
    })
    const app = await appWithUser()
    const res = await app.inject({ method: 'GET', url: '/search?q=Emily%20in%20Paris' })

    expect(res.statusCode, res.body).toBe(200)
    expect(res.json().franchises[0].upcoming).toEqual(upcoming)
    expect(mocks.enqueueFranchiseNewsRefresh).toHaveBeenCalledWith(ID, upcoming)
    expect(mocks.enqueueFranchiseEnrichment).toHaveBeenCalledWith(ID)
    await app.close()
  })

  it('does not launch research for every fuzzy result while the user is still typing', async () => {
    mocks.searchFranchises.mockResolvedValueOnce({
      franchises: [{ id: ID, title: 'Emily in Paris', upcoming: null }],
    })
    const app = await appWithUser()
    await app.inject({ method: 'GET', url: '/search?q=Emily' })

    expect(mocks.enqueueFranchiseNewsRefresh).not.toHaveBeenCalled()
    await app.close()
  })

  it('fills a missing exact TMDB announcement before returning the search response', async () => {
    mocks.searchFranchises.mockResolvedValueOnce({
      franchises: [{ id: ID, source: 'tmdb', title: 'Selling Sunset', upcoming: null }],
    })
    mocks.refreshTvUpcomingFact.mockResolvedValueOnce({
      status: 'announced_no_date',
      next: 'Season 10',
      release: 'TBA',
      note: 'TMDB currently lists the series as returning.',
      source: 'https://www.themoviedb.org/tv/87826',
      checked: '2026-09-02T12:00:00.000Z',
    })
    const app = await appWithUser()
    const res = await app.inject({ method: 'GET', url: '/search?q=Selling%20Sunset' })

    expect(res.statusCode, res.body).toBe(200)
    expect(mocks.refreshTvUpcomingFact).toHaveBeenCalledWith(ID, { maxRetries: 0, timeoutMs: 1_050 })
    expect(res.json().franchises[0].upcoming).toMatchObject({
      status: 'announced_no_date',
      next: 'Season 10',
      releaseWindow: { precision: 'unknown', sortKey: null },
    })
    expect(mocks.enqueueFranchiseNewsRefresh).toHaveBeenCalledWith(
      ID,
      expect.objectContaining({ next: 'Season 10' }),
    )
    await app.close()
  })

  it('returns a newly fetched TMDB trailer on the same exact-search response', async () => {
    mocks.searchFranchises.mockResolvedValueOnce({
      franchises: [{ id: ID, source: 'tmdb', title: 'Emily in Paris', upcoming: { next: 'Season 6' }, featuredVideo: null }],
    })
    mocks.refreshTvUpcomingFact.mockResolvedValueOnce({
      status: 'announced_no_date',
      next: 'Season 6',
      release: 'TBA',
      note: null,
      source: 'https://www.themoviedb.org/tv/82596',
      checked: '2026-09-02T12:00:00.000Z',
    })
    mocks.getSummaries.mockResolvedValueOnce([{
      id: ID,
      source: 'tmdb',
      title: 'Emily in Paris',
      featuredVideo: { id: 'ldfEtPf3CfQ', kind: 'announcement', site: 'youtube' },
    }])
    const app = await appWithUser()
    const res = await app.inject({ method: 'GET', url: '/search?q=Emily%20in%20Paris' })

    expect(res.statusCode, res.body).toBe(200)
    expect(mocks.getSummaries).toHaveBeenCalledWith([ID])
    expect(res.json().franchises[0].featuredVideo).toMatchObject({
      id: 'ldfEtPf3CfQ',
      kind: 'announcement',
    })
    await app.close()
  })
})

describe('GET /franchises/:id', () => {
  it('returns immediately and schedules stale-while-revalidate news research', async () => {
    const franchise = { id: ID, title: 'Selling Sunset', upcoming: null }
    mocks.getFranchise.mockResolvedValueOnce(franchise)
    const app = await appWithUser()
    const res = await app.inject({ method: 'GET', url: `/franchises/${ID}?country=in` })

    expect(res.statusCode, res.body).toBe(200)
    expect(res.json()).toEqual(franchise)
    expect(mocks.getFranchise).toHaveBeenCalledWith(ID, ID, 'IN')
    expect(mocks.enqueueFranchiseNewsRefresh).toHaveBeenCalledWith(ID, null)
    expect(mocks.enqueueFranchiseEnrichment).toHaveBeenCalledWith(ID)
    await app.close()
  })

  it('rejects a malformed optional rating country', async () => {
    const app = await appWithUser()
    const res = await app.inject({ method: 'GET', url: `/franchises/${ID}?country=India` })

    expect(res.statusCode, res.body).toBe(400)
    expect(mocks.getFranchise).not.toHaveBeenCalled()
    await app.close()
  })
})

describe('GET /franchises/:id/watch-providers', () => {
  it('normalizes the requested country before lookup', async () => {
    const app = await appWithUser()
    const res = await app.inject({ method: 'GET', url: `/franchises/${ID}/watch-providers?country=in` })

    expect(res.statusCode, res.body).toBe(200)
    expect(mocks.getWatchAvailability).toHaveBeenCalledWith(ID, 'IN')
    expect(res.json().country).toBe('IN')
    await app.close()
  })

  it('rejects a missing or non-ISO-alpha-2 country without touching the provider', async () => {
    const app = await appWithUser()
    const missing = await app.inject({ method: 'GET', url: `/franchises/${ID}/watch-providers` })
    const malformed = await app.inject({ method: 'GET', url: `/franchises/${ID}/watch-providers?country=India` })

    expect(missing.statusCode, missing.body).toBe(400)
    expect(malformed.statusCode, malformed.body).toBe(400)
    expect(mocks.getWatchAvailability).not.toHaveBeenCalled()
    await app.close()
  })

  it('returns 404 when the franchise does not exist', async () => {
    mocks.getWatchAvailability.mockResolvedValueOnce(null)
    const app = await appWithUser()
    const res = await app.inject({ method: 'GET', url: `/franchises/${ID}/watch-providers?country=IN` })

    expect(res.statusCode, res.body).toBe(404)
    expect(res.json()).toEqual({ error: 'franchise not found' })
    await app.close()
  })
})
