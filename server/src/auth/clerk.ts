import { verifyToken } from '@clerk/backend'
import type { FastifyReply, FastifyRequest } from 'fastify'
import { env } from '../env.js'
import { upsertUser, type AppUser } from '../services/users.js'

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
 * Resolve a request's Clerk identity:
 *  - DEV_AUTH_BYPASS: accepts `Bearer dev:<clerkId>` for local testing.
 *  - Otherwise verifies the Clerk session JWT (networkless via CLERK_JWT_KEY if set,
 *    else JWKS using CLERK_SECRET_KEY).
 */
async function resolveClerkId(token: string): Promise<{ clerkId: string; email?: string | null } | null> {
  if (env.DEV_AUTH_BYPASS && token.startsWith('dev:')) {
    const clerkId = token.slice('dev:'.length)
    return clerkId ? { clerkId } : null
  }
  try {
    const claims = await verifyToken(token, {
      jwtKey: env.CLERK_JWT_KEY,
      secretKey: env.CLERK_SECRET_KEY,
    })
    if (!claims.sub) return null
    const email = (claims as Record<string, unknown>).email as string | undefined
    return { clerkId: claims.sub, email }
  } catch {
    return null
  }
}

/** Fastify preHandler that authenticates the request and attaches `req.user`. */
export async function authenticate(req: FastifyRequest, reply: FastifyReply): Promise<void> {
  const token = bearer(req)
  if (!token) return reply.code(401).send({ error: 'missing bearer token' })
  const id = await resolveClerkId(token)
  if (!id) return reply.code(401).send({ error: 'invalid token' })
  req.user = await upsertUser(id.clerkId, id.email)
}
