import { and, desc, eq, isNotNull, sql } from 'drizzle-orm'
import { db } from '../db/index.js'
import { blocks, episodeRatings, feedHides, franchise, likes, reminders, saves, userProfiles } from '../db/schema.js'
import { toPublicUser } from '../social/views.js'
import type { BlockedUsersResponse, HidesResponse } from '../types/api.js'

// The social layer's set-state toggles (docs/api-contract.md, "Social"): likes on a post or an
// episode room, saves, reminders, "Not interested" / "Mute <show>", episode ratings and blocks.
//
// Every write is idempotent — PUT sets the state, DELETE clears it, a repeat changes nothing — so
// clients mark them `idempotent: true` and replay them from a newest-word-wins queue. Validation,
// subject resolution, the spoiler gate and the rate limit happen in routes/social.ts BEFORE these
// run; this file only reads and writes rows scoped to the caller.

export type HideKind = 'post' | 'show'

// ---------- Likes (posts and episode rooms) ----------

export async function putLike(userId: string, subject: string): Promise<void> {
  await db.insert(likes).values({ userId, subject }).onConflictDoNothing({ target: [likes.userId, likes.subject] })
}

export async function deleteLike(userId: string, subject: string): Promise<void> {
  await db.delete(likes).where(and(eq(likes.userId, userId), eq(likes.subject, subject)))
}

// ---------- Saves ----------

/** The first save's time is kept: re-saving is a no-op, so the Saved list keeps its order. */
export async function putSave(userId: string, postId: string, franchiseId: string): Promise<void> {
  await db.insert(saves).values({ userId, postId, franchiseId }).onConflictDoNothing({ target: [saves.userId, saves.postId] })
}

export async function deleteSave(userId: string, postId: string): Promise<void> {
  await db.delete(saves).where(and(eq(saves.userId, userId), eq(saves.postId, postId)))
}

// ---------- Reminders ----------

export async function putReminder(userId: string, postId: string, franchiseId: string): Promise<void> {
  await db
    .insert(reminders)
    .values({ userId, postId, franchiseId })
    .onConflictDoNothing({ target: [reminders.userId, reminders.postId] })
}

export async function deleteReminder(userId: string, postId: string): Promise<void> {
  await db.delete(reminders).where(and(eq(reminders.userId, userId), eq(reminders.postId, postId)))
}

// ---------- Hides ("Not interested" / "Mute <show>") ----------

export async function putHide(userId: string, kind: HideKind, target: string): Promise<void> {
  await db
    .insert(feedHides)
    .values({ userId, kind, target })
    .onConflictDoNothing({ target: [feedHides.userId, feedHides.kind, feedHides.target] })
}

export async function deleteHide(userId: string, kind: HideKind, target: string): Promise<void> {
  await db
    .delete(feedHides)
    .where(and(eq(feedHides.userId, userId), eq(feedHides.kind, kind), eq(feedHides.target, target)))
}

/** Newest first. A muted show carries its franchise (id + title) so Settings can name it. */
export async function listHides(userId: string): Promise<HidesResponse> {
  const rows = await db
    .select({
      kind: feedHides.kind,
      target: feedHides.target,
      createdAt: feedHides.createdAt,
      franchiseId: franchise.id,
      franchiseTitle: franchise.title,
    })
    .from(feedHides)
    .leftJoin(franchise, and(eq(feedHides.kind, 'show'), sql`${franchise.id}::text = ${feedHides.target}`))
    .where(eq(feedHides.userId, userId))
    .orderBy(desc(feedHides.createdAt), feedHides.kind, feedHides.target)
  const items: HidesResponse['items'] = []
  for (const r of rows) {
    if (r.kind !== 'post' && r.kind !== 'show') continue
    items.push({
      kind: r.kind,
      target: r.target,
      createdAt: r.createdAt.getTime(),
      franchise: r.kind === 'show' && r.franchiseId && r.franchiseTitle != null ? { id: r.franchiseId, title: r.franchiseTitle } : null,
    })
  }
  return { items }
}

// ---------- Episode ratings (the emoji slider) ----------

export async function putRating(userId: string, mediaId: number, episode: number, score: number): Promise<void> {
  const now = new Date()
  await db
    .insert(episodeRatings)
    .values({ userId, mediaId, episode, score, createdAt: now, updatedAt: now })
    .onConflictDoUpdate({
      target: [episodeRatings.userId, episodeRatings.mediaId, episodeRatings.episode],
      set: { score, updatedAt: now },
    })
}

export async function deleteRating(userId: string, mediaId: number, episode: number): Promise<void> {
  await db
    .delete(episodeRatings)
    .where(and(eq(episodeRatings.userId, userId), eq(episodeRatings.mediaId, mediaId), eq(episodeRatings.episode, episode)))
}

// ---------- Blocks ----------

/** A blockable account: one with a public identity (a profile that has a handle). */
export async function blockTargetExists(userId: string): Promise<boolean> {
  const rows = await db
    .select({ userId: userProfiles.userId })
    .from(userProfiles)
    .where(and(eq(userProfiles.userId, userId), isNotNull(userProfiles.handle)))
    .limit(1)
  return rows.length > 0
}

export async function putBlock(userId: string, blockedUserId: string): Promise<void> {
  await db
    .insert(blocks)
    .values({ userId, blockedUserId })
    .onConflictDoNothing({ target: [blocks.userId, blocks.blockedUserId] })
}

export async function deleteBlock(userId: string, blockedUserId: string): Promise<void> {
  await db.delete(blocks).where(and(eq(blocks.userId, userId), eq(blocks.blockedUserId, blockedUserId)))
}

/** Whom the caller blocked, newest first, as public faces only. */
export async function listBlocks(userId: string): Promise<BlockedUsersResponse> {
  const rows = await db
    .select({
      blockedUserId: blocks.blockedUserId,
      createdAt: blocks.createdAt,
      handle: userProfiles.handle,
      displayName: userProfiles.displayName,
    })
    .from(blocks)
    .innerJoin(userProfiles, eq(userProfiles.userId, blocks.blockedUserId))
    .where(eq(blocks.userId, userId))
    .orderBy(desc(blocks.createdAt), blocks.blockedUserId)
  const items: BlockedUsersResponse['items'] = []
  for (const r of rows) {
    const user = toPublicUser(r.blockedUserId, r.handle, r.displayName)
    if (user) items.push({ user, blockedAt: r.createdAt.getTime() })
  }
  return { items }
}
