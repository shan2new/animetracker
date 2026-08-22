import type { FastifyPluginAsync } from 'fastify'
import { z } from 'zod'
import { getFranchise, getTrendingFranchises } from '../services/franchiseView.js'
import { searchFranchises } from '../services/search.js'
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

  app.get('/search', async (req): Promise<FranchiseListResponse> => {
    const { q, limit, exact } = searchQuery.parse(req.query)
    return searchFranchises(q, limit, { exact: exact === '1' })
  })

  app.get('/franchises/:id', async (req, reply) => {
    const { id } = z.object({ id: z.string().uuid() }).parse(req.params)
    const f = await getFranchise(id, req.user!.id)
    if (!f) return reply.code(404).send({ error: 'franchise not found' })
    return f
  })
}
