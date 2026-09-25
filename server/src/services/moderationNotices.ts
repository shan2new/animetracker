import { inArray, eq } from 'drizzle-orm'
import type { db } from '../db/index.js'
import { comments, franchise, notifications, reports } from '../db/schema.js'

// Telling both sides of a moderation decision (docs/api-contract.md, "Moderation notices"): the
// AUTHOR of a comment that was hidden gets a `comment_hidden` row (a statement of reasons: DSA
// Art. 17), and each REPORTER whose report the operator decided gets a `report_resolved` row (the
// notifier learns the decision: DSA Art. 16(5)).
//
// The rows carry no comment, subject or post — a hidden comment is nobody's to open, and the
// Activity sheet renders them as plain rows that open nothing. `body` is a machine CATEGORY the
// client words (with the support contact), never server English:
//
//   comment_hidden    body 'reports' (auto-hidden after reports) | 'operator' (hidden by a moderator)
//   report_resolved   body 'hidden' (the comment was removed)    | 'dismissed' (it stays up)

export const COMMENT_HIDDEN_KIND = 'comment_hidden'
export const REPORT_RESOLVED_KIND = 'report_resolved'

export type HiddenReason = 'reports' | 'operator'
export type ReportResolution = 'hidden' | 'dismissed'

type Tx = Parameters<Parameters<typeof db.transaction>[0]>[0]

type NewNotification = typeof notifications.$inferInsert

/** Pure: the author notices for hidden comments (one per comment). */
export function commentHiddenNotices(
  rows: readonly { authorId: string; franchiseId: string; franchiseTitle: string }[],
  reason: HiddenReason,
): NewNotification[] {
  return rows.map((r) => ({
    userId: r.authorId,
    franchiseId: r.franchiseId,
    kind: COMMENT_HIDDEN_KIND,
    title: r.franchiseTitle,
    body: reason,
  }))
}

/** Pure: the reporter notices for decided reports (one per report: reports are unique per reporter and comment). */
export function reportResolvedNotices(
  rows: readonly { reporterId: string; franchiseId: string; franchiseTitle: string }[],
  resolution: ReportResolution,
): NewNotification[] {
  return rows.map((r) => ({
    userId: r.reporterId,
    franchiseId: r.franchiseId,
    kind: REPORT_RESOLVED_KIND,
    title: r.franchiseTitle,
    body: resolution,
  }))
}

/** Insert `comment_hidden` for each comment in `commentIds` (inside the hiding transaction). */
export async function noticeCommentsHidden(tx: Tx, commentIds: readonly string[], reason: HiddenReason): Promise<number> {
  if (commentIds.length === 0) return 0
  const rows = await tx
    .select({ authorId: comments.userId, franchiseId: comments.franchiseId, franchiseTitle: franchise.title })
    .from(comments)
    .innerJoin(franchise, eq(franchise.id, comments.franchiseId))
    .where(inArray(comments.id, [...commentIds]))
  const values = commentHiddenNotices(rows, reason)
  if (values.length > 0) await tx.insert(notifications).values(values)
  return values.length
}

/** Insert `report_resolved` for each report in `reportIds` (inside the resolving transaction). */
export async function noticeReportsResolved(
  tx: Tx,
  reportIds: readonly string[],
  resolution: ReportResolution,
): Promise<number> {
  if (reportIds.length === 0) return 0
  const rows = await tx
    .select({ reporterId: reports.userId, franchiseId: comments.franchiseId, franchiseTitle: franchise.title })
    .from(reports)
    .innerJoin(comments, eq(comments.id, reports.commentId))
    .innerJoin(franchise, eq(franchise.id, comments.franchiseId))
    .where(inArray(reports.id, [...reportIds]))
  const values = reportResolvedNotices(rows, resolution)
  if (values.length > 0) await tx.insert(notifications).values(values)
  return values.length
}
