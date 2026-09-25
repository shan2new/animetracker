import { and, eq, isNull, sql, type SQL } from 'drizzle-orm'
import { db } from '../db/index.js'
import { commentLikes, comments, episodeRatings, franchise, likes, notifications, reports, userProfiles, users } from '../db/schema.js'
import { alertModeration, reportAlert } from './moderationAlert.js'
import { noticeCommentsHidden } from './moderationNotices.js'
import { isBlockedEitherWay, notBlockedEitherWaySql } from '../social/blocks.js'
import { shouldAutoHide } from '../social/moderationRules.js'
import { notifyCommentLike, notifyReply, replyRecipient } from '../social/notify.js'
import { commentRowFromDb, toCommentView } from '../social/views.js'
import type { CommentSort, CommentView, ReportReason } from '../types/api.js'
import { cursorAt, encodeCursor, type KeysetCursor } from '../util/cursor.js'

// Comment threads (docs/api-contract.md, "Social" → "Comments"). One flat thread per subject;
// `parent_id` is only the "replied to you" reference.
//
// The route (routes/social.ts) owns the ORDER of the checks — replay first, then profile, subject,
// gate, content, parent, rate limit, write — and this file supplies each step's read or write, so
// every step is visible in one place and the route contract can be tested with these mocked.
//
// The VISIBLE set for a viewer: same subject, not deleted, not hidden, the author has a public
// identity, neither side has blocked the other, and the viewer has not reported it. Counts shown
// OUTSIDE a thread (the locked room's "join N comments", the episode room, feed counts) are global:
// deleted and hidden excluded, blocks not applied (D14).

// ---------- Queries ----------

/** Postgres timestamptz → ms epoch as a float8 (the driver returns timestamps as text here). */
const createdMs = sql`floor(extract(epoch from c.created_at) * 1000)::float8`

/** The comments `me` has reported (hidden from them, whatever everyone else sees). */
function notReportedBy(me: string, idCol: SQL): SQL {
  return sql`${idCol} not in (select rp.comment_id from reports rp where rp.user_id = ${me})`
}

/**
 * One row per comment `c`, with everything its view needs for viewer `me`: author and parent
 * author profiles, like count, `liked`, visible reply count, parent visibility, and the cursor's
 * exact `at`. `where` filters `c`.
 */
function threadRowsSql(me: string, where: SQL): SQL {
  return sql`
    select
      c.id, c.subject, c.body, c.parent_id, c.user_id as author_id, c.created_at,
      ${createdMs} as created_ms,
      ${cursorAt(sql`c.created_at`)} as at,
      (select count(*) from comment_likes cl where cl.comment_id = c.id)::int as like_count,
      exists (select 1 from comment_likes cl where cl.comment_id = c.id and cl.user_id = ${me}) as liked,
      (select count(*) from comments r
        where r.parent_id = c.id
          and r.subject = c.subject
          and r.deleted_at is null
          and r.hidden_at is null
          and exists (select 1 from user_profiles rap where rap.user_id = r.user_id and rap.handle is not null)
          and ${notBlockedEitherWaySql(me, sql`r.user_id`)}
          and ${notReportedBy(me, sql`r.id`)})::int as reply_count,
      ap.handle as author_handle,
      ap.display_name as author_display_name,
      p.user_id as parent_author_id,
      pp.handle as parent_author_handle,
      pp.display_name as parent_author_display_name,
      coalesce(p.id is not null and p.deleted_at is null and p.hidden_at is null
        and ${notBlockedEitherWaySql(me, sql`p.user_id`)}, false) as parent_visible
    from comments c
    left join user_profiles ap on ap.user_id = c.user_id
    left join comments p on p.id = c.parent_id
    left join user_profiles pp on pp.user_id = p.user_id
    where ${where}`
}

/** The visible set of `subject` for `me` (see the header). */
function visibleWhere(me: string, subject: string): SQL {
  return sql`c.subject = ${subject}
    and c.deleted_at is null
    and c.hidden_at is null
    and ap.handle is not null
    and ${notBlockedEitherWaySql(me, sql`c.user_id`)}
    and ${notReportedBy(me, sql`c.id`)}`
}

/** One comment's view for `me`, whatever its visibility (the author's replay, a fresh insert). */
export async function loadCommentView(id: string, me: string): Promise<CommentView | null> {
  const rows = await db.execute(threadRowsSql(me, sql`c.id = ${id}`))
  const raw = rows[0]
  return raw ? toCommentView(commentRowFromDb(raw), me) : null
}

// ---------- POST /social/comments ----------

export type ReplayOutcome =
  | { kind: 'none' }
  | { kind: 'replay'; comment: CommentView }
  | { kind: 'deleted' }
  | { kind: 'id_conflict' }

/**
 * Step 1, the replay check (it runs before everything else, and a replay costs no rate limit):
 * an unknown id is new; someone else's id is a conflict; my deleted comment is gone (410, so a
 * retried POST can never resurrect it); my live comment is answered as it stands.
 */
export async function findReplay(id: string, me: string): Promise<ReplayOutcome> {
  const [c] = await db
    .select({ userId: comments.userId, deletedAt: comments.deletedAt })
    .from(comments)
    .where(eq(comments.id, id))
    .limit(1)
  if (!c) return { kind: 'none' }
  if (c.userId !== me) return { kind: 'id_conflict' }
  if (c.deletedAt != null) return { kind: 'deleted' }
  const comment = await loadCommentView(id, me)
  // Deleted between the two reads (a concurrent DELETE): the tombstone answer is the true one.
  return comment ? { kind: 'replay', comment } : { kind: 'deleted' }
}

export interface CommenterProfile {
  handle: string | null
  displayName: string | null
  termsVersion: string | null
}

/** Step 2's read: the caller's public identity and accepted rules version, or null (no profile yet). */
export async function loadCommenterProfile(me: string): Promise<CommenterProfile | null> {
  const [row] = await db
    .select({ handle: userProfiles.handle, displayName: userProfiles.displayName, termsVersion: userProfiles.termsVersion })
    .from(userProfiles)
    .where(eq(userProfiles.userId, me))
    .limit(1)
  return row ?? null
}

export interface ReplyParent {
  id: string
  authorId: string
  authorHandle: string | null
  authorDisplayName: string | null
}

/**
 * Step 6: a reply's parent must be in the SAME thread, neither deleted nor hidden, and written by
 * someone neither side has blocked. Anything else is "parent not found".
 */
export async function findReplyParent(parentId: string, subject: string, me: string): Promise<ReplyParent | null> {
  const [row] = await db
    .select({
      id: comments.id,
      authorId: comments.userId,
      subject: comments.subject,
      deletedAt: comments.deletedAt,
      hiddenAt: comments.hiddenAt,
      authorHandle: userProfiles.handle,
      authorDisplayName: userProfiles.displayName,
    })
    .from(comments)
    .leftJoin(userProfiles, eq(userProfiles.userId, comments.userId))
    .where(eq(comments.id, parentId))
    .limit(1)
  if (!row || row.subject !== subject || row.deletedAt != null || row.hiddenAt != null) return null
  if (await isBlockedEitherWay(db, me, row.authorId)) return null
  return { id: row.id, authorId: row.authorId, authorHandle: row.authorHandle, authorDisplayName: row.authorDisplayName }
}

export interface CommentDraft {
  /** The client's uuid (lowercase). */
  id: string
  userId: string
  subject: string
  franchiseId: string
  franchiseTitle: string
  /** The normalised body (`checkCommentBody`'s text). */
  body: string
  author: { handle: string; displayName: string }
  parent: ReplyParent | null
}

export type CreateOutcome = { kind: 'created'; comment: CommentView } | Exclude<ReplayOutcome, { kind: 'none' }>

/**
 * Step 8: insert on the client's uuid and, in the same transaction, notify the parent's author.
 * `on conflict (id) do nothing` makes a concurrent replay safe: when nothing was inserted, the
 * replay check runs again and its answer is returned instead.
 */
export async function insertComment(draft: CommentDraft): Promise<CreateOutcome> {
  for (let attempt = 0; attempt < 2; attempt++) {
    const createdAt = new Date()
    const inserted = await db.transaction(async (tx) => {
      const rows = await tx
        .insert(comments)
        .values({
          id: draft.id,
          userId: draft.userId,
          subject: draft.subject,
          franchiseId: draft.franchiseId,
          parentId: draft.parent?.id ?? null,
          body: draft.body,
          createdAt,
        })
        .onConflictDoNothing({ target: comments.id })
        .returning({ id: comments.id })
      if (rows.length === 0) return false
      if (draft.parent) {
        const recipient = replyRecipient({
          parentAuthorId: draft.parent.authorId,
          replierId: draft.userId,
          parentVisible: true,
          blocked: await isBlockedEitherWay(tx, draft.parent.authorId, draft.userId),
        })
        if (recipient) {
          await notifyReply(tx, {
            recipientId: recipient,
            actorId: draft.userId,
            franchiseId: draft.franchiseId,
            franchiseTitle: draft.franchiseTitle,
            subject: draft.subject,
            commentId: draft.id,
          })
        }
      }
      return true
    })

    if (inserted) {
      return {
        kind: 'created',
        comment: toCommentView(
          {
            id: draft.id,
            subject: draft.subject,
            body: draft.body,
            createdAt: createdAt.getTime(),
            parentId: draft.parent?.id ?? null,
            authorId: draft.userId,
            authorHandle: draft.author.handle,
            authorDisplayName: draft.author.displayName,
            parentAuthorId: draft.parent?.authorId ?? null,
            parentAuthorHandle: draft.parent?.authorHandle ?? null,
            parentAuthorDisplayName: draft.parent?.authorDisplayName ?? null,
            parentVisible: draft.parent != null,
            likeCount: 0,
            liked: false,
            replyCount: 0,
          },
          draft.userId,
        ),
      }
    }
    const replay = await findReplay(draft.id, draft.userId)
    if (replay.kind !== 'none') return replay
    // The conflicting row vanished between the insert and the read (an account erasure): try once more.
  }
  throw new Error(`comments: insert of ${draft.id} kept conflicting`)
}

// ---------- GET /social/comments ----------

export interface ListCommentsInput {
  subject: string
  sort: CommentSort
  /** Already decoded, and carrying `rank` exactly when `sort` is `top` (the route checks). */
  cursor: KeysetCursor | null
  /** 1..50. */
  limit: number
}

export interface CommentsSlice {
  /** The visible set's size for this viewer. */
  total: number
  items: CommentView[]
  nextCursor: string | null
}

/**
 * A page of the visible set. `latest` orders by (created_at, id) desc; `top` by (like count,
 * created_at, id) desc, the like count computed in a derived table so the keyset predicate can
 * reference it. `top` pages can repeat or skip a comment whose likes change between pages — the
 * client dedupes by id (documented in the contract).
 */
export async function listComments(me: string, input: ListCommentsInput): Promise<CommentsSlice> {
  const inner = threadRowsSql(me, visibleWhere(me, input.subject))
  const top = input.sort === 'top'
  const c = input.cursor
  const after = c
    ? top
      ? sql`(t.like_count, t.created_at, t.id) < (${c.rank ?? 0}::int, ${c.at}::timestamptz, ${c.id}::uuid)`
      : sql`(t.created_at, t.id) < (${c.at}::timestamptz, ${c.id}::uuid)`
    : sql`true`
  const order = top ? sql`t.like_count desc, t.created_at desc, t.id desc` : sql`t.created_at desc, t.id desc`

  const [rows, totals] = await Promise.all([
    db.execute(sql`select * from (${inner}) t where ${after} order by ${order} limit ${input.limit + 1}`),
    db.execute(sql`select count(*)::int as n
      from comments c
      left join user_profiles ap on ap.user_id = c.user_id
      where ${visibleWhere(me, input.subject)}`),
  ])

  const page = [...rows].slice(0, input.limit)
  const items = page.map((raw) => toCommentView(commentRowFromDb(raw), me))
  let nextCursor: string | null = null
  const last = page[page.length - 1]
  if (rows.length > input.limit && last) {
    const row = commentRowFromDb(last)
    nextCursor = encodeCursor({ at: String(last.at), id: row.id, ...(top ? { rank: row.likeCount } : {}) })
  }
  return { total: Number(totals[0]?.n ?? 0), items, nextCursor }
}

/** Every live comment on a subject, not viewer-filtered (the locked room's "join N comments"). */
export async function countVisibleComments(subject: string): Promise<number> {
  const [row] = await db
    .select({ n: sql<number>`count(*)::int` })
    .from(comments)
    .where(and(eq(comments.subject, subject), isNull(comments.deletedAt), isNull(comments.hiddenAt)))
  return Number(row?.n ?? 0)
}

// ---------- DELETE /social/comments/:id (D10: a soft delete) ----------

export type DeleteOutcome = 'deleted' | 'already_deleted' | 'not_found'

/**
 * The author's delete: the body is erased and the row stays as a tombstone (so a replayed POST
 * with the same uuid answers 410, never re-creates it); its likes and every notification that
 * hangs off it go in the same transaction. Reports stay, for moderation history — until the
 * tombstone itself is purged `COMMENT_TOMBSTONE_DAYS` (30) later with them (social/retention.ts,
 * services/commentRetention.ts, the daily 03:10 job in sync/cron.ts).
 */
export async function deleteOwnComment(id: string, me: string): Promise<DeleteOutcome> {
  return db.transaction(async (tx) => {
    const updated = await tx
      .update(comments)
      .set({ deletedAt: new Date(), body: '' })
      .where(and(eq(comments.id, id), eq(comments.userId, me), isNull(comments.deletedAt)))
      .returning({ id: comments.id })
    if (updated.length === 0) {
      const [c] = await tx
        .select({ userId: comments.userId })
        .from(comments)
        .where(eq(comments.id, id))
        .limit(1)
      return !c || c.userId !== me ? 'not_found' : 'already_deleted'
    }
    await tx.delete(commentLikes).where(eq(commentLikes.commentId, id))
    await tx.delete(notifications).where(eq(notifications.commentId, id))
    return 'deleted'
  })
}

// ---------- PUT / DELETE /social/comments/:id/like ----------

export interface VisibleComment {
  id: string
  authorId: string
  subject: string
  franchiseId: string
  franchiseTitle: string
}

/** The comment when `me` can see it — the thread's rule (deleted, hidden, blocked or reported → null). */
export async function findVisibleComment(id: string, me: string): Promise<VisibleComment | null> {
  const [row] = await db
    .select({
      id: comments.id,
      authorId: comments.userId,
      subject: comments.subject,
      franchiseId: comments.franchiseId,
      franchiseTitle: franchise.title,
    })
    .from(comments)
    .innerJoin(franchise, eq(franchise.id, comments.franchiseId))
    .where(
      and(
        eq(comments.id, id),
        isNull(comments.deletedAt),
        isNull(comments.hiddenAt),
        notBlockedEitherWaySql(me, comments.userId),
        sql`${comments.id} not in (select ${reports.commentId} from ${reports} where ${reports.userId} = ${me})`,
      ),
    )
    .limit(1)
  return row ?? null
}

/** Insert the like; a NEW like on someone else's comment notifies them (throttled, aggregated). */
export async function likeComment(
  me: string,
  target: VisibleComment,
  opts: { nowMs: number; cooldownMs: number },
): Promise<void> {
  await db.transaction(async (tx) => {
    const rows = await tx
      .insert(commentLikes)
      .values({ userId: me, commentId: target.id })
      .onConflictDoNothing({ target: [commentLikes.userId, commentLikes.commentId] })
      .returning({ commentId: commentLikes.commentId })
    if (rows.length === 0 || target.authorId === me) return
    await notifyCommentLike(tx, {
      authorId: target.authorId,
      likerId: me,
      commentId: target.id,
      subject: target.subject,
      franchiseId: target.franchiseId,
      franchiseTitle: target.franchiseTitle,
      nowMs: opts.nowMs,
      cooldownMs: opts.cooldownMs,
    })
  })
}

/** Always succeeds, even when the comment is gone. Never touches notifications. */
export async function unlikeComment(me: string, commentId: string): Promise<void> {
  await db.delete(commentLikes).where(and(eq(commentLikes.userId, me), eq(commentLikes.commentId, commentId)))
}

// ---------- POST /social/comments/:id/report ----------

export interface ReportTarget {
  authorId: string
  /**
   * The author's Clerk id, for the operator's server log only (never a response, never the alert
   * webhook): erasing the author's account deletes the reports about their comments, and the log
   * line is then what keeps a ban possible.
   */
  authorClerkId: string
  /** The thread: the route applies an `ep:` room's spoiler gate. */
  subject: string
}

/**
 * A reportable comment for `me` — the thread's visibility rule (`findVisibleComment`) less two
 * clauses: a HIDDEN comment can still be reported, and one `me` already reported is found (the
 * repeat is a no-op, not a 404). So: it exists, it is not deleted, and neither side has blocked the
 * other — a person the author blocked cannot keep reporting comment ids they saw before the block.
 * An `ep:` room's gate is the route's, as for a like (a room not open to `me` is a 404).
 */
export async function findReportTarget(id: string, me: string): Promise<ReportTarget | null> {
  const [row] = await db
    .select({ authorId: comments.userId, authorClerkId: users.clerkId, subject: comments.subject })
    .from(comments)
    .innerJoin(users, eq(users.id, comments.userId))
    .where(and(eq(comments.id, id), isNull(comments.deletedAt), notBlockedEitherWaySql(me, comments.userId)))
    .limit(1)
  return row ?? null
}

export interface ReportResult {
  /** False for a repeat report by the same person (nothing changed). */
  inserted: boolean
  /**
   * The comment's COUNTED reports after this one (open, from accounts at least
   * `reporterMinAgeHours` old — social/moderationRules.ts); null when nothing was inserted.
   */
  reportCount: number | null
  /** This is the comment's only open report: the operator hears about it (services/moderationAlert.ts). */
  firstOpenReport: boolean
  /** This report crossed the threshold and hid the comment. */
  autoHidden: boolean
}

/**
 * One transaction: the report (unique per reporter and comment, so a repeat is a no-op), the
 * RECOMPUTED count, and the auto-hide once `threshold` counted reports stand. The count is never
 * incremented: it is the open reports whose reporter's account is at least `reporterMinAgeHours`
 * old (`autoHideCount` in social/moderationRules.ts is the same rule, pure), so an erased
 * reporter's report stops counting and "report, delete the account, sign back in, report again"
 * cannot hide a comment single-handed. An auto-hide tells the author (`comment_hidden`,
 * services/moderationNotices.ts) in the same transaction.
 *
 * Once it has COMMITTED, the operator is alerted (fire-and-forget) on the comment's first open
 * report and on every auto-hide.
 */
export async function fileReport(
  me: string,
  commentId: string,
  input: { reason: ReportReason; note: string | null; threshold: number; reporterMinAgeHours: number },
): Promise<ReportResult> {
  const minAgeHours = Math.max(0, Math.floor(input.reporterMinAgeHours))
  const filed = await db.transaction(async (tx) => {
    const inserted = await tx
      .insert(reports)
      .values({ userId: me, commentId, reason: input.reason, note: input.note })
      .onConflictDoNothing({ target: [reports.userId, reports.commentId] })
      .returning({ id: reports.id })
    if (inserted.length === 0) {
      return { inserted: false, reportCount: null, firstOpenReport: false, autoHidden: false, subject: null }
    }

    const [counted] = await tx
      .update(comments)
      .set({
        reportCount: sql`(select count(*)::int from reports r join users u on u.id = r.user_id
          where r.comment_id = ${commentId}
            and r.resolved_at is null
            and u.created_at <= now() - make_interval(hours => ${minAgeHours}::int))`,
      })
      .where(eq(comments.id, commentId))
      .returning({ reportCount: comments.reportCount, hiddenAt: comments.hiddenAt, subject: comments.subject })
    const [open] = await tx
      .select({ n: sql<number>`count(*)::int` })
      .from(reports)
      .where(and(eq(reports.commentId, commentId), isNull(reports.resolvedAt)))
    const reportCount = counted?.reportCount ?? 0
    let autoHidden = false
    if (counted && shouldAutoHide({ reportCount, threshold: input.threshold, hiddenAt: counted.hiddenAt })) {
      const hidden = await tx
        .update(comments)
        .set({ hiddenAt: new Date(), hiddenReason: 'reports' })
        .where(and(eq(comments.id, commentId), isNull(comments.hiddenAt)))
        .returning({ id: comments.id })
      if (hidden.length > 0) {
        await noticeCommentsHidden(tx, [commentId], 'reports')
        autoHidden = true
      }
    }
    return {
      inserted: true,
      reportCount,
      firstOpenReport: Number(open?.n ?? 0) === 1,
      autoHidden,
      subject: counted?.subject ?? null,
    }
  })
  const { subject, ...result } = filed
  const alert = subject == null ? null : reportAlert({ commentId, subject, reason: input.reason, ...result })
  if (alert) void alertModeration(alert)
  return result
}

// ---------- GET /social/episodes/:mediaId/:episode ----------

export interface EpisodeRoomStats {
  commentCount: number
  likeCount: number
  liked: boolean
  rating: { count: number; average: number | null; yours: number | null }
}

/**
 * The room's global counts, the caller's like and rating. The average is the real mean over the
 * raters (0–100, one decimal); the route withholds it while the room is locked.
 */
export async function episodeRoomStats(me: string, mediaId: number, episode: number, subject: string): Promise<EpisodeRoomStats> {
  const [commentCount, likeRows, ratingRows] = await Promise.all([
    countVisibleComments(subject),
    db
      .select({
        n: sql<number>`count(*)::int`,
        liked: sql<boolean>`coalesce(bool_or(${likes.userId} = ${me}), false)`,
      })
      .from(likes)
      .where(eq(likes.subject, subject)),
    db
      .select({
        n: sql<number>`count(*)::int`,
        average: sql<number | null>`round(avg(${episodeRatings.score})::numeric, 1)::float8`,
        yours: sql<number | null>`max(case when ${episodeRatings.userId} = ${me} then ${episodeRatings.score} end)`,
      })
      .from(episodeRatings)
      .where(and(eq(episodeRatings.mediaId, mediaId), eq(episodeRatings.episode, episode))),
  ])
  const l = likeRows[0]
  const r = ratingRows[0]
  const count = Number(r?.n ?? 0)
  return {
    commentCount,
    likeCount: Number(l?.n ?? 0),
    liked: l?.liked === true,
    rating: {
      count,
      average: count > 0 && r?.average != null ? Number(r.average) : null,
      yours: r?.yours != null ? Number(r.yours) : null,
    },
  }
}
