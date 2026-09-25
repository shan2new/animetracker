import { and, eq, sql } from 'drizzle-orm'
import { notifications } from '../db/schema.js'
import { isBlockedEitherWay, type Executor } from './blocks.js'
import { isPostSubject } from './subjects.js'

// Social notifications (docs/api-contract.md, "NotificationItem"): "replied to you" and "liked
// your comment". Poll-only — there is no push in this build. The decisions are pure and tested;
// the writes run on the caller's executor, so a reply's notification commits with the reply.
//
// Social rows carry `body = ''`: the excerpt is read live at list time (services/notifications.ts),
// so an edited-away (deleted or hidden) comment never lingers in someone's inbox as text.

/**
 * Who a reply notifies: the parent's author — unless the parent is gone or hidden, the replier is
 * replying to themself, or either has blocked the other. Null means no notification.
 */
export function replyRecipient(input: {
  parentAuthorId: string | null
  replierId: string
  parentVisible: boolean
  blocked: boolean
}): string | null {
  const { parentAuthorId, replierId, parentVisible, blocked } = input
  if (parentAuthorId == null) return null
  if (parentAuthorId === replierId) return null
  if (!parentVisible || blocked) return null
  return parentAuthorId
}

export type LikeNotificationAction = 'aggregate' | 'insert' | 'skip'

/**
 * What a like on someone's comment does to their inbox:
 * - `skip` for a self-like or when either has blocked the other;
 * - `aggregate` into the one UNREAD like row for that comment when there is one (the actor becomes
 *   the newest liker and the count grows — "Mira and 41 others liked your reply");
 * - `skip` while the last like row for that comment (now read) is younger than the cooldown, so a
 *   popular comment does not ring the bell every time its author opens Activity;
 * - otherwise `insert` a fresh row.
 */
export function likeNotificationAction(input: {
  likerId: string
  authorId: string
  blocked: boolean
  unreadExists: boolean
  lastCreatedAt: number | null
  nowMs: number
  cooldownMs: number
}): LikeNotificationAction {
  const { likerId, authorId, blocked, unreadExists, lastCreatedAt, nowMs, cooldownMs } = input
  if (likerId === authorId || blocked) return 'skip'
  if (unreadExists) return 'aggregate'
  if (lastCreatedAt != null && nowMs - lastCreatedAt < cooldownMs) return 'skip'
  return 'insert'
}

/** The feed post a social row opens: the subject itself when it is a post, never an episode room. */
function postIdFor(subject: string): string | null {
  return isPostSubject(subject) ? subject : null
}

/** "Replied to you". Called only when `replyRecipient` answered someone, inside the reply's transaction. */
export async function notifyReply(
  exec: Executor,
  input: {
    recipientId: string
    actorId: string
    franchiseId: string
    franchiseTitle: string
    subject: string
    /** The reply itself. */
    commentId: string
  },
): Promise<void> {
  await exec.insert(notifications).values({
    userId: input.recipientId,
    franchiseId: input.franchiseId,
    kind: 'reply',
    title: input.franchiseTitle,
    body: '',
    actorUserId: input.actorId,
    actorCount: 1,
    subject: input.subject,
    postId: postIdFor(input.subject),
    commentId: input.commentId,
  })
}

/**
 * "Liked your comment", throttled and aggregated (see `likeNotificationAction`). Both `aggregate`
 * and `insert` run the same statement: an upsert on the partial unique index
 * `notifications_like_unread_uq` (one UNREAD like row per recipient and comment), so two likes
 * landing at once can never produce two unread rows. Unliking never decrements.
 */
export async function notifyCommentLike(
  exec: Executor,
  input: {
    authorId: string
    likerId: string
    /** The liked comment (the author's). */
    commentId: string
    subject: string
    franchiseId: string
    franchiseTitle: string
    nowMs: number
    cooldownMs: number
  },
): Promise<LikeNotificationAction> {
  if (input.likerId === input.authorId) return 'skip'

  const [state] = await exec
    .select({
      unread: sql<boolean>`coalesce(bool_or(${notifications.readAt} is null), false)`,
      lastMs: sql<number | null>`floor(extract(epoch from max(${notifications.createdAt})) * 1000)::float8`,
    })
    .from(notifications)
    .where(
      and(
        eq(notifications.userId, input.authorId),
        eq(notifications.commentId, input.commentId),
        eq(notifications.kind, 'like_comment'),
      ),
    )
  const blocked = await isBlockedEitherWay(exec, input.authorId, input.likerId)

  const action = likeNotificationAction({
    likerId: input.likerId,
    authorId: input.authorId,
    blocked,
    unreadExists: state?.unread === true,
    lastCreatedAt: state?.lastMs == null ? null : Number(state.lastMs),
    nowMs: input.nowMs,
    cooldownMs: input.cooldownMs,
  })
  if (action === 'skip') return action

  await exec
    .insert(notifications)
    .values({
      userId: input.authorId,
      franchiseId: input.franchiseId,
      kind: 'like_comment',
      title: input.franchiseTitle,
      body: '',
      actorUserId: input.likerId,
      actorCount: 1,
      subject: input.subject,
      postId: postIdFor(input.subject),
      commentId: input.commentId,
      createdAt: sql`now()`,
    })
    .onConflictDoUpdate({
      target: [notifications.userId, notifications.commentId],
      // The partial index's predicate, unqualified, so Postgres can infer the arbiter index.
      targetWhere: sql`kind = 'like_comment' and read_at is null`,
      set: {
        actorUserId: sql`excluded.actor_user_id`,
        actorCount: sql`${notifications.actorCount} + 1`,
        createdAt: sql`now()`,
      },
    })
  return action
}
