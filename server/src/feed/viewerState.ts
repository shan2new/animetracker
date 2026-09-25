import { and, eq, inArray, isNull, sql, type AnyColumn } from 'drizzle-orm'
import { db } from '../db/index.js'
import { comments, feedHides, likes, reminders, saves } from '../db/schema.js'
import type { FeedCounts, FeedViewerState } from '../types/api.js'

// Per-viewer state over composed posts: what the viewer hid, and each post's likes/saves/reminders
// and counts. Counts are GLOBAL (D14) — blocks filter lists, never counts.

/** "Not interested" post ids and muted show (franchise) ids. */
export async function loadHides(userId: string): Promise<{ posts: Set<string>; shows: Set<string> }> {
  const rows = await db
    .select({ kind: feedHides.kind, target: feedHides.target })
    .from(feedHides)
    .where(eq(feedHides.userId, userId))
  const posts = new Set<string>()
  const shows = new Set<string>()
  for (const row of rows) {
    if (row.kind === 'post') posts.add(row.target)
    else if (row.kind === 'show') shows.add(row.target)
  }
  return { posts, shows }
}

export interface PostSocial {
  viewer: FeedViewerState
  counts: FeedCounts
}

/** Zeros and falses: a post nobody has touched. */
export function emptyPostSocial(): PostSocial {
  return { viewer: { liked: false, saved: false, reminded: false }, counts: { likes: 0, comments: 0 } }
}

/**
 * The viewer's state and the global counts for each post, in exactly four queries. Every id asked
 * for is in the result; one nobody has touched reads as zeros and falses.
 */
export async function loadPostSocial(userId: string, postIds: string[]): Promise<Map<string, PostSocial>> {
  const ids = [...new Set(postIds)]
  const out = new Map<string, PostSocial>(ids.map((id) => [id, emptyPostSocial()]))
  if (ids.length === 0) return out

  const [likeRows, saveRows, reminderRows, commentRows] = await Promise.all([
    db
      .select({
        subject: likes.subject,
        count: sql<number>`count(*)::int`,
        mine: sql<boolean>`bool_or(${likes.userId} = ${userId})`,
      })
      .from(likes)
      .where(inArray(likes.subject, ids))
      .groupBy(likes.subject),
    db
      .select({ postId: saves.postId })
      .from(saves)
      .where(and(eq(saves.userId, userId), inArray(saves.postId, ids))),
    db
      .select({ postId: reminders.postId })
      .from(reminders)
      .where(and(eq(reminders.userId, userId), inArray(reminders.postId, ids))),
    db
      .select({ subject: comments.subject, count: sql<number>`count(*)::int` })
      .from(comments)
      .where(and(inArray(comments.subject, ids), isNull(comments.deletedAt), isNull(comments.hiddenAt)))
      .groupBy(comments.subject),
  ])

  for (const row of likeRows) {
    const entry = out.get(row.subject)
    if (!entry) continue
    entry.counts.likes = Number(row.count) || 0
    entry.viewer.liked = row.mine === true
  }
  for (const row of saveRows) {
    const entry = out.get(row.postId)
    if (entry) entry.viewer.saved = true
  }
  for (const row of reminderRows) {
    const entry = out.get(row.postId)
    if (entry) entry.viewer.reminded = true
  }
  for (const row of commentRows) {
    const entry = out.get(row.subject)
    if (entry) entry.counts.comments = Number(row.count) || 0
  }
  return out
}

/** `min(col)` as epoch ms (a number, not the driver's timestamp text). */
const earliestMs = (col: AnyColumn) => sql<number>`floor(extract(epoch from min(${col})) * 1000)::float8`.mapWith(Number)

/**
 * For each post id that anyone holds a social row on — a like, a live comment, a save or a
 * reminder — the instant of the earliest such row (ms). An id nobody touched is absent. Used only
 * for a trailer whose video was delisted, to decide whether its thread is still worth composing
 * (feed/compose.ts `orphanTrailerPost`) and to date it; four small queries over those ids.
 */
export async function firstActivityAt(postIds: string[]): Promise<Map<string, number>> {
  const ids = [...new Set(postIds)]
  const out = new Map<string, number>()
  if (ids.length === 0) return out

  const [likeRows, commentRows, saveRows, reminderRows] = await Promise.all([
    db
      .select({ subject: likes.subject, first: earliestMs(likes.createdAt) })
      .from(likes)
      .where(inArray(likes.subject, ids))
      .groupBy(likes.subject),
    db
      .select({ subject: comments.subject, first: earliestMs(comments.createdAt) })
      .from(comments)
      .where(and(inArray(comments.subject, ids), isNull(comments.deletedAt), isNull(comments.hiddenAt)))
      .groupBy(comments.subject),
    db
      .select({ subject: saves.postId, first: earliestMs(saves.createdAt) })
      .from(saves)
      .where(inArray(saves.postId, ids))
      .groupBy(saves.postId),
    db
      .select({ subject: reminders.postId, first: earliestMs(reminders.createdAt) })
      .from(reminders)
      .where(inArray(reminders.postId, ids))
      .groupBy(reminders.postId),
  ])

  for (const row of [...likeRows, ...commentRows, ...saveRows, ...reminderRows]) {
    const ms = Number(row.first)
    if (!Number.isFinite(ms)) continue
    const known = out.get(row.subject)
    if (known == null || ms < known) out.set(row.subject, ms)
  }
  return out
}
