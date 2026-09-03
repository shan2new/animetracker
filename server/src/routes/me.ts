import type { FastifyPluginAsync } from 'fastify'
import { z } from 'zod'
import { getLibrary } from '../services/franchiseView.js'
import { listNotifications, markNotificationsRead } from '../services/notifications.js'
import {
  franchiseExists,
  markOpened,
  setProgress,
  setSubscriptionStatus,
  subscribe,
  unsubscribe,
} from '../services/library.js'
import { db } from '../db/index.js'
import { notifications, progress, subscriptions, users } from '../db/schema.js'
import { eq } from 'drizzle-orm'
import type { AccountDeletedResponse } from '../types/api.js'
import { enqueueAnimeVideoFallback } from '../services/animeVideoFallback.js'

// Board 09's status vocabulary. `subscriptions.status` is a text() column, so the two added
// values need no migration.
const statusEnum = z.enum(['watching', 'completed', 'planned', 'paused', 'dropped'])

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
    enqueueAnimeVideoFallback(body.franchiseId)
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

  app.get('/me/notifications', async (req) => {
    const { limit } = z.object({ limit: z.coerce.number().int().min(1).max(200).default(50) }).parse(req.query)
    return listNotifications(req.user!.id, limit)
  })

  app.post('/me/notifications/read', async (req) => {
    // ids omitted → mark everything unread as read.
    const { ids } = z.object({ ids: z.array(z.string().uuid()).optional() }).parse(req.body ?? {})
    const marked = await markNotificationsRead(req.user!.id, ids)
    return { marked }
  })

  // In-app account deletion — App Store guideline 5.1.1(v). The client confirms; this is the
  // point of no return, so it must actually erase, not deactivate.
  //
  // Every user-owned table is deleted EXPLICITLY rather than left to the `onDelete: 'cascade'`
  // declared on each foreign key. The cascade is real and is asserted by `me.account.test.ts`,
  // but a database restored from a dump, or a table added later without one, would turn "delete
  // my account" into "orphan my rows" — and a deletion route that silently leaves a user's
  // progress behind is the failure the guideline exists to prevent. The whole erasure runs in one
  // transaction: a half-deleted account is worse than either outcome.
  app.delete('/me', async (req, reply) => {
    // Nothing to read, and validated anyway: an irreversible route rejects a request it does not
    // fully understand instead of ignoring the part it did not expect. `safeParse` rather than the
    // `parse` the other routes use, because a thrown ZodError surfaces as a 500 — and "the server
    // broke" is the wrong answer to "you sent me a field I do not know" on the one route that
    // cannot be undone.
    if (!z.object({}).strict().safeParse(req.body ?? {}).success) {
      return reply.code(400).send({ error: 'unexpected body' })
    }
    const userId = req.user!.id
    await db.transaction(async (tx) => {
      await tx.delete(notifications).where(eq(notifications.userId, userId))
      await tx.delete(subscriptions).where(eq(subscriptions.userId, userId))
      await tx.delete(progress).where(eq(progress.userId, userId))
      // Last: everything that references it is gone, so this succeeds with or without the cascade.
      await tx.delete(users).where(eq(users.id, userId))
    })
    const body: AccountDeletedResponse = { deleted: true }
    return reply.code(200).send(body)
  })
}

/**
 * The tables `DELETE /me` erases before the `users` row itself — every table that stores rows
 * belonging to one user.
 *
 * Exported so the test can hold it against the schema: if a future table gains a `userId` column
 * and is not listed here, `me.account.test.ts` fails rather than the deletion quietly leaving that
 * table's rows behind.
 */
export const accountOwnedTableNames = ['notifications', 'subscriptions', 'progress'] as const
