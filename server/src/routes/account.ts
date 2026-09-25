import type { FastifyPluginAsync, FastifyReply, FastifyRequest } from 'fastify'
import { z } from 'zod'
import { env } from '../env.js'
import { buildAccountExport, exportFilename } from '../services/export.js'
import {
  acceptTerms,
  findHandleOwner,
  getProfile,
  handleAvailability,
  isHandleTakenError,
  saveProfile,
} from '../services/profile.js'
import { checkDisplayName, checkHandle } from '../social/identity.js'
import type { HandleAvailability, ProfileResponse, SocialError } from '../types/api.js'
import { rateKeyOf, rateLimiter, sendRateLimited } from '../util/rateLimit.js'

// Public identity, community rules and the data export: /me/profile, /me/profile/handle,
// /me/terms, /me/export (docs/api-contract.md, "Identity" and "Account export").
//
// Order on every write: validate (400/422), then the preconditions that need no write (409), then
// the rate limit (429), then the write — so a refused request never spends the user's allowance.
// The one exception: a 422 from the identity rules spends the `rejected` budget and answers 429 once
// it is spent, so the name filter cannot be probed at full speed. Limits key on the Clerk id.
//
// A public identity is only collected from someone who has accepted the CURRENT community rules
// (PUT /me/profile and GET /me/profile/handle answer 409 `terms_required` otherwise), and only
// while comments are on: with SOCIAL_COMMENTS_ENABLED=0 the identity writes, the handle lookup and
// POST /me/terms answer 404 `comments disabled`, because nothing would ever show a name. Reading
// your profile and the export always work.

// Raw-length guards only: the real limits (3–20 for a handle, 40 code points for a name) are the
// identity rules', which answer 422 with a reason the client can show. These just keep an absurd
// payload from reaching them.
const RAW_HANDLE_MAX = 200
const RAW_NAME_MAX = 400

const profileBody = z
  .object({
    handle: z.string().max(RAW_HANDLE_MAX),
    displayName: z.string().max(RAW_NAME_MAX),
  })
  .strict()

const handleQuery = z.object({ handle: z.string().max(RAW_HANDLE_MAX) })

const termsBody = z.object({ version: z.string().min(1).max(100) }).strict()

const invalidRequest = { error: 'invalid request' } as const
const commentsDisabled = { error: 'comments disabled' } satisfies SocialError

/** 409 `terms_required` (+ the version to accept) unless the caller accepted the current rules. */
function termsRequired(termsVersion: string | null): SocialError | null {
  const currentVersion = env.SOCIAL_TERMS_VERSION
  return termsVersion === currentVersion ? null : { error: 'terms_required', currentVersion }
}

/** A 422 refusal spends one `rejected` hit; once the hour's refusals are spent it is a 429 instead. */
function refuse(req: FastifyRequest, reply: FastifyReply, body: SocialError): FastifyReply {
  const rate = rateLimiter.check('rejected', rateKeyOf(req.user!))
  return rate.allowed ? reply.code(422).send(body) : sendRateLimited(reply, rate.retryAfterSec)
}

export const accountRoutes: FastifyPluginAsync = async (app) => {
  app.addHook('preHandler', app.authenticate)

  app.get('/me/profile', async (req): Promise<ProfileResponse> => getProfile(req.user!.id))

  app.put('/me/profile', async (req, reply) => {
    if (!env.SOCIAL_COMMENTS_ENABLED) return reply.code(404).send(commentsDisabled)
    const userId = req.user!.id
    const parsed = profileBody.safeParse(req.body)
    if (!parsed.success) return reply.code(400).send(invalidRequest)

    const handle = checkHandle(parsed.data.handle)
    if (!handle.ok) return refuse(req, reply, { error: 'invalid_handle', reason: handle.reason })
    const name = checkDisplayName(parsed.data.displayName)
    if (!name.ok) return refuse(req, reply, { error: 'invalid_display_name', reason: name.reason })

    // A replay of what is already stored (an idempotent retry, or Save tapped twice) answers the
    // profile without writing or charging the day's allowance.
    const current = await getProfile(userId)
    const terms = termsRequired(current.termsVersion)
    if (terms) return reply.code(409).send(terms)
    if (current.handle === handle.handle && current.displayName === name.displayName) return current

    // Taken by someone else: refused before the limiter, so trying names costs nothing. The unique
    // index below still decides a race between two people claiming the same handle.
    const owner = await findHandleOwner(handle.handle)
    if (owner != null && owner !== userId) {
      return reply.code(409).send({ error: 'handle_taken' } satisfies SocialError)
    }

    const rate = rateLimiter.check('profile', rateKeyOf(req.user!))
    if (!rate.allowed) return sendRateLimited(reply, rate.retryAfterSec)

    try {
      return await saveProfile(userId, { handle: handle.handle, displayName: name.displayName })
    } catch (err) {
      if (isHandleTakenError(err)) return reply.code(409).send({ error: 'handle_taken' } satisfies SocialError)
      throw err
    }
  })

  app.get('/me/profile/handle', async (req, reply): Promise<HandleAvailability | undefined> => {
    if (!env.SOCIAL_COMMENTS_ENABLED) return reply.code(404).send(commentsDisabled)
    const userId = req.user!.id
    const parsed = handleQuery.safeParse(req.query)
    if (!parsed.success) return reply.code(400).send(invalidRequest)
    const terms = termsRequired((await getProfile(userId)).termsVersion)
    if (terms) return reply.code(409).send(terms)
    const rate = rateLimiter.check('lookup', rateKeyOf(req.user!))
    if (!rate.allowed) return sendRateLimited(reply, rate.retryAfterSec)
    return handleAvailability(userId, parsed.data.handle)
  })

  app.post('/me/terms', async (req, reply) => {
    if (!env.SOCIAL_COMMENTS_ENABLED) return reply.code(404).send(commentsDisabled)
    const userId = req.user!.id
    const parsed = termsBody.safeParse(req.body)
    if (!parsed.success) return reply.code(400).send(invalidRequest)
    const currentVersion = env.SOCIAL_TERMS_VERSION
    if (parsed.data.version !== currentVersion) {
      return reply.code(409).send({ error: 'terms_version_mismatch', currentVersion } satisfies SocialError)
    }
    const rate = rateLimiter.check('profile', rateKeyOf(req.user!))
    if (!rate.allowed) return sendRateLimited(reply, rate.retryAfterSec)
    return acceptTerms(userId, currentVersion)
  })

  // Answers a suspended account too (auth/clerk.ts `suspendedMayCall`).
  app.get('/me/export', async (req, reply) => {
    const userId = req.user!.id
    const rate = rateLimiter.check('export', rateKeyOf(req.user!))
    if (!rate.allowed) return sendRateLimited(reply, rate.retryAfterSec)
    const now = Date.now()
    const body = await buildAccountExport(userId, now)
    if (!body) return reply.code(404).send({ error: 'account not found' })
    return reply
      .header('Content-Type', 'application/json; charset=utf-8')
      .header('Content-Disposition', `attachment; filename="${exportFilename(now)}"`)
      .header('Cache-Control', 'no-store')
      .send(JSON.stringify(body, null, 2))
  })
}
