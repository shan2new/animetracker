import type { FastifyReply, FastifyRequest } from 'fastify'
import { upsertUser, type AppUser } from '../services/users.js'
import { authConfigFromEnv } from './authConfig.js'
import { resolveIdentity } from './identity.js'

declare module 'fastify' {
  interface FastifyRequest {
    user?: AppUser
  }
  interface FastifyInstance {
    authenticate: (req: FastifyRequest, reply: FastifyReply) => Promise<void>
  }
}

function bearer(req: FastifyRequest): string | null {
  const h = req.headers.authorization
  if (!h || !h.startsWith('Bearer ')) return null
  return h.slice('Bearer '.length).trim()
}

/**
 * Fastify preHandler that authenticates the request and attaches `req.user`.
 *
 * All issuer policy lives in `identity.ts` / `authConfig.ts` — this file is glue only, so
 * `DEV_AUTH_BYPASS` is never read at a decision site.
 */
export async function authenticate(req: FastifyRequest, reply: FastifyReply): Promise<void> {
  const token = bearer(req)
  if (!token) return reply.code(401).send({ error: 'missing bearer token' })
  const id = await resolveIdentity(token, authConfigFromEnv())
  if (!id) return reply.code(401).send({ error: 'invalid token' })
  req.user = await upsertUser(id.clerkId, id.email)
}
