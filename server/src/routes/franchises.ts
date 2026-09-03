import type { FastifyPluginAsync } from 'fastify'
import { z } from 'zod'
import { enqueueFranchiseNewsRefresh } from '../news/service.js'
import { getFranchise, getSummaries, getTrendingFranchises } from '../services/franchiseView.js'
import { withReleaseWindow } from '../services/releaseWindow.js'
import { searchFranchises, type SearchProfile } from '../services/search.js'
import { getWatchAvailability } from '../services/watchAvailability.js'
import { enqueueFranchiseEnrichment } from '../services/catalogEnrichment.js'
import { enqueueAnimeVideoFallback, refreshAnimeVideoFallback } from '../services/animeVideoFallback.js'
import { refreshTvUpcomingFact } from '../tmdb/service.js'
import type { FranchiseListResponse } from '../types/api.js'
import { withTimeout } from '../util/abort.js'

const trendingQuery = z.object({ limit: z.coerce.number().min(1).max(100).default(30) })
// `exact=1` opts out of the LLM spell-correction: the caller wants the literal query searched.
const searchQuery = z.object({
  q: z.string().default(''),
  limit: z.coerce.number().min(1).max(100).default(30),
  exact: z.string().optional(),
})
const watchProviderQuery = z.object({
  country: z.string().regex(/^[a-z]{2}$/i).transform((value) => value.toUpperCase()),
})
const detailQuery = z.object({
  country: z.string().regex(/^[a-z]{2}$/i).transform((value) => value.toUpperCase()).optional(),
})

const normalizedTitle = (value: string): string =>
  value.normalize('NFKC').toLocaleLowerCase('en-US').replace(/[^\p{L}\p{N}]+/gu, ' ').trim()

export const franchiseRoutes: FastifyPluginAsync = async (app) => {
  // All franchise routes require a valid user (so detail can include subscription/progress).
  app.addHook('preHandler', app.authenticate)

  app.get('/franchises/trending', async (req): Promise<FranchiseListResponse> => {
    const { limit } = trendingQuery.parse(req.query)
    return { franchises: await getTrendingFranchises(limit) }
  })

  app.get('/search', async (req, reply): Promise<FranchiseListResponse> => {
    const { q, limit, exact } = searchQuery.parse(req.query)
    const controller = new AbortController()
    const abort = () => controller.abort()
    const abortIfUnsent = () => {
      if (!reply.raw.writableEnded) controller.abort()
    }
    req.raw.once('aborted', abort)
    reply.raw.once('close', abortIfUnsent)

    let profile: SearchProfile | undefined
    try {
      const response = await searchFranchises(q, limit, {
        exact: exact === '1',
        signal: controller.signal,
        onProfile: (value) => {
          profile = value
        },
      })
      // Search is a product surface, not merely a path to Detail. An exact result must begin
      // enriching its catalogue fallback here; the request still returns immediately.
      const intendedTitle = normalizedTitle(response.correctedQuery ?? q)
      const exactFranchise = intendedTitle
        ? response.franchises.find((item) => normalizedTitle(item.title) === intendedTitle)
        : undefined
      if (exactFranchise?.source === 'tmdb' && (!exactFranchise.upcoming || !exactFranchise.featuredVideo)) {
        try {
          const immediate = await refreshTvUpcomingFact(exactFranchise.id, { maxRetries: 0, timeoutMs: 1_050 })
          // refreshTvUpcomingFact also persists the show-level video from the same TMDB response.
          // Rebuild this one summary so a first exact Search can return that trailer immediately.
          const [refreshed] = await getSummaries([exactFranchise.id])
          if (refreshed) Object.assign(exactFranchise, refreshed)
          exactFranchise.upcoming = withReleaseWindow(immediate)
        } catch (error) {
          // Provider news is enrichment: a short TMDB failure must not turn a useful search result
          // into an error. The background researcher below can still fill it later.
          req.log.warn(
            { event: 'search.upcoming_refresh_failed', franchiseId: exactFranchise.id, error },
            'exact-search upcoming refresh failed',
          )
        }
      } else if (exactFranchise?.source === 'anilist' && !exactFranchise.featuredVideo) {
        try {
          const result = await refreshAnimeVideoFallback(exactFranchise.id, {
            request: {
              signal: withTimeout(controller.signal, 3_200),
              maxRetries: 0,
              timeoutMs: 1_050,
            },
          })
          if (result.updated) {
            const [refreshed] = await getSummaries([exactFranchise.id])
            if (refreshed) Object.assign(exactFranchise, refreshed)
          }
        } catch (error) {
          // A failed metadata fallback must not hide the AniList search result. The queued pass
          // below gets a longer budget and the daily subscriber sweep repairs it independently.
          req.log.warn(
            { event: 'search.anime_video_fallback_failed', franchiseId: exactFranchise.id, error },
            'exact-search anime video fallback failed',
          )
        }
      }
      if (exactFranchise) {
        enqueueFranchiseNewsRefresh(exactFranchise.id, exactFranchise.upcoming)
        enqueueFranchiseEnrichment(exactFranchise.id)
        enqueueAnimeVideoFallback(exactFranchise.id)
      }
      req.log.info({ event: 'search.profile', search: profile, sources: response.sources }, 'search profile')
      return response
    } finally {
      req.raw.removeListener('aborted', abort)
      reply.raw.removeListener('close', abortIfUnsent)
    }
  })

  app.get('/franchises/:id/watch-providers', async (req, reply) => {
    const params = z.object({ id: z.string().uuid() }).safeParse(req.params)
    const query = watchProviderQuery.safeParse(req.query)
    if (!params.success || !query.success) return reply.code(400).send({ error: 'invalid request' })
    const { id } = params.data
    const { country } = query.data
    const availability = await getWatchAvailability(id, country)
    if (!availability) return reply.code(404).send({ error: 'franchise not found' })
    return availability
  })

  app.get('/franchises/:id', async (req, reply) => {
    const params = z.object({ id: z.string().uuid() }).safeParse(req.params)
    const query = detailQuery.safeParse(req.query)
    if (!params.success || !query.success) return reply.code(400).send({ error: 'invalid request' })
    const { id } = params.data
    let f = await getFranchise(id, req.user!.id, query.data.country)
    if (!f) return reply.code(404).send({ error: 'franchise not found' })
    if (f.source === 'anilist' && !f.featuredVideo) {
      try {
        const result = await refreshAnimeVideoFallback(id, {
          request: { signal: withTimeout(undefined, 3_200), maxRetries: 0, timeoutMs: 1_050 },
        })
        if (result.updated) f = await getFranchise(id, req.user!.id, query.data.country) ?? f
      } catch (error) {
        req.log.warn(
          { event: 'detail.anime_video_fallback_failed', franchiseId: id, error },
          'anime detail video fallback failed',
        )
      }
    }
    enqueueFranchiseNewsRefresh(id, f.upcoming)
    enqueueFranchiseEnrichment(id)
    enqueueAnimeVideoFallback(id)
    return f
  })
}
