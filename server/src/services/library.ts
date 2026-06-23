import { and, eq } from 'drizzle-orm'
import { db } from '../db/index.js'
import { franchise, franchiseMember, media, progress, subscriptions, users } from '../db/schema.js'
import type { WatchStatus } from '../types/api.js'
import { inArray } from 'drizzle-orm'

/** Subscribe to a franchise. Defaults status to `watching` if any part is releasing, else `planned`. */
export async function subscribe(userId: string, franchiseId: string, status?: WatchStatus): Promise<void> {
  let resolved = status
  if (!resolved) {
    const members = await db
      .select({ mediaId: franchiseMember.mediaId })
      .from(franchiseMember)
      .where(eq(franchiseMember.franchiseId, franchiseId))
    const ids = members.map((m) => m.mediaId)
    const releasing = ids.length
      ? await db.select({ id: media.id }).from(media).where(and(inArray(media.id, ids), eq(media.status, 'RELEASING')))
      : []
    resolved = releasing.length > 0 ? 'watching' : 'planned'
  }
  await db
    .insert(subscriptions)
    .values({ userId, franchiseId, status: resolved })
    .onConflictDoUpdate({ target: [subscriptions.userId, subscriptions.franchiseId], set: { status: resolved } })
}

export async function setSubscriptionStatus(userId: string, franchiseId: string, status: WatchStatus): Promise<void> {
  await db
    .update(subscriptions)
    .set({ status })
    .where(and(eq(subscriptions.userId, userId), eq(subscriptions.franchiseId, franchiseId)))
}

export async function unsubscribe(userId: string, franchiseId: string): Promise<void> {
  await db
    .delete(subscriptions)
    .where(and(eq(subscriptions.userId, userId), eq(subscriptions.franchiseId, franchiseId)))
}

export async function setProgress(userId: string, mediaId: number, episodes: number): Promise<void> {
  const clamped = Number.isFinite(episodes) ? Math.max(0, Math.floor(episodes)) : 0
  await db
    .insert(progress)
    .values({ userId, mediaId, episodesWatched: clamped, updatedAt: new Date() })
    .onConflictDoUpdate({
      target: [progress.userId, progress.mediaId],
      set: { episodesWatched: clamped, updatedAt: new Date() },
    })
}

/** Stamp the user's last-opened time to now; return the PREVIOUS value (for "since you were last here"). */
export async function markOpened(userId: string): Promise<number> {
  const [u] = await db.select({ prev: users.lastOpenedAt }).from(users).where(eq(users.id, userId)).limit(1)
  const prev = u?.prev ?? 0
  await db.update(users).set({ lastOpenedAt: Date.now() }).where(eq(users.id, userId))
  return prev
}

/** Whether a franchise exists (for 404s on subscribe). */
export async function franchiseExists(franchiseId: string): Promise<boolean> {
  const [f] = await db.select({ id: franchise.id }).from(franchise).where(eq(franchise.id, franchiseId)).limit(1)
  return !!f
}
