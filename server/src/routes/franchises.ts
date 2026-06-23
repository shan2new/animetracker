import type { FastifyPluginAsync } from 'fastify'
import { z } from 'zod'
import { getFranchise, getTrendingFranchises } from '../services/franchiseView.js'
import { searchFranchises } from '../services/search.js'

const trendingQuery = z.object({ limit: z.coerce.number().min(1).max(100).default(30) })
const searchQuery = z.object({ q: z.string().default(''), limit: z.coerce.number().min(1).max(100).default(30) })

export const franchiseRoutes: FastifyPluginAsync = async (app) => {
  // All franchise routes require a valid user (so detail can include subscription/progress).
  app.addHook('preHandler', app.authenticate)

  app.get('/franchises/trending', async (req) => {
    const { limit } = trendingQuery.parse(req.query)
    return { franchises: await getTrendingFranchises(limit) }
  })

  app.get('/search', async (req) => {
    const { q, limit } = searchQuery.parse(req.query)
    return { franchises: await searchFranchises(q, limit) }
  })

  app.get('/franchises/:id', async (req, reply) => {
    const { id } = z.object({ id: z.string().uuid() }).parse(req.params)
    const f = await getFranchise(id, req.user!.id)
    if (!f) return reply.code(404).send({ error: 'franchise not found' })
    return f
  })
}
