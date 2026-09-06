import cors from '@fastify/cors'
import Fastify, { type FastifyInstance } from 'fastify'
import { authenticate } from './auth/clerk.js'
import { env } from './env.js'
import { franchiseRoutes } from './routes/franchises.js'
import { legalRoutes } from './routes/legal.js'
import { meRoutes } from './routes/me.js'

export async function buildServer(): Promise<FastifyInstance> {
  const app = Fastify({ logger: true })

  await app.register(cors, {
    origin: env.CORS_ORIGIN === '*' ? true : env.CORS_ORIGIN.split(',').map((s) => s.trim()),
  })

  // Decorate the ROOT instance so the preHandler is visible to all route plugins.
  app.decorate('authenticate', authenticate)

  app.get('/health', async () => ({ ok: true }))

  // Public, unauthenticated: Privacy Policy + Terms (App Store guideline 5.1.1).
  await app.register(legalRoutes)

  await app.register(franchiseRoutes)
  await app.register(meRoutes)

  return app
}
