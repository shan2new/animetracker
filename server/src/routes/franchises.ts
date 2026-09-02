import type { FastifyPluginAsync } from 'fastify'
import { z } from 'zod'
import { getFranchise, getTrendingFranchises } from '../services/franchiseView.js'
import { searchFranchises, type SearchProfile } from '../services/search.js'
import type { FranchiseListResponse } from '../types/api.js'

const trendingQuery = z.object({ limit: z.coerce.number().min(1).max(100).default(30) })
// `exact=1` opts out of the LLM spell-correction: the caller wants the literal query searched.
const searchQuery = z.object({
  q: z.string().default(''),
  limit: z.coerce.number().min(1).max(100).default(30),
  exact: z.string().optional(),
})

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
      req.log.info({ event: 'search.profile', search: profile, sources: response.sources }, 'search profile')
      return response
    } finally {
      req.raw.removeListener('aborted', abort)
      reply.raw.removeListener('close', abortIfUnsent)
    }
  })

  app.get('/franchises/:id', async (req, reply) => {
    const { id } = z.object({ id: z.string().uuid() }).parse(req.params)
    const f = await getFranchise(id, req.user!.id)
    if (!f) return reply.code(404).send({ error: 'franchise not found' })
    return f
  })
}
