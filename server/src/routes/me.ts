import type { FastifyPluginAsync } from 'fastify'
import { z } from 'zod'
import { getLibrary } from '../services/franchiseView.js'
import {
  franchiseExists,
  markOpened,
  setProgress,
  setSubscriptionStatus,
  subscribe,
  unsubscribe,
} from '../services/library.js'
import { db } from '../db/index.js'
import { users } from '../db/schema.js'
import { eq } from 'drizzle-orm'

const statusEnum = z.enum(['watching', 'completed', 'planned'])

export const meRoutes: FastifyPluginAsync = async (app) => {
  app.addHook('preHandler', app.authenticate)

  app.get('/me/library', async (req) => {
    const userId = req.user!.id
    const [u] = await db.select({ prev: users.lastOpenedAt }).from(users).where(eq(users.id, userId)).limit(1)
    const franchises = await getLibrary(userId, u?.prev ?? 0)
    return { franchises, prevOpenedAt: u?.prev ?? 0 }
  })

  app.post('/me/subscriptions', async (req, reply) => {
    const body = z.object({ franchiseId: z.string().uuid(), status: statusEnum.optional() }).parse(req.body)
    if (!(await franchiseExists(body.franchiseId))) return reply.code(404).send({ error: 'franchise not found' })
    await subscribe(req.user!.id, body.franchiseId, body.status)
    return { ok: true }
  })

  app.patch('/me/subscriptions/:franchiseId', async (req) => {
    const { franchiseId } = z.object({ franchiseId: z.string().uuid() }).parse(req.params)
    const { status } = z.object({ status: statusEnum }).parse(req.body)
    await setSubscriptionStatus(req.user!.id, franchiseId, status)
    return { ok: true }
  })

  app.delete('/me/subscriptions/:franchiseId', async (req) => {
    const { franchiseId } = z.object({ franchiseId: z.string().uuid() }).parse(req.params)
    await unsubscribe(req.user!.id, franchiseId)
    return { ok: true }
  })

  app.put('/me/progress', async (req) => {
    const body = z.object({ mediaId: z.number().int(), episodes: z.number().int().min(0) }).parse(req.body)
    await setProgress(req.user!.id, body.mediaId, body.episodes)
    return { ok: true }
  })

  app.post('/me/opened', async (req) => {
    const prevOpenedAt = await markOpened(req.user!.id)
    return { prevOpenedAt }
  })
}
