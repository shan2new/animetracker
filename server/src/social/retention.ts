// How long a comment its author deleted is kept as a tombstone. Pure.
//
// DELETE /social/comments/:id empties the body but keeps the row (D10) for one reason: a replayed
// POST with the same client uuid must answer 410 rather than bring the comment back, and clients
// replay within their session — days, not months. Keeping "who commented on what, and when" (and
// the reports on it, reporters' notes included) forever after the author deleted it is retention
// the privacy policy does not describe, so a daily job removes tombstones past this window; the
// comment's likes, reports and notifications go with it through their FK cascades. A replay after
// the window creates a new comment, which is acceptable for the same reason the window is safe.

export const COMMENT_TOMBSTONE_DAYS = 30

const DAY_MS = 24 * 60 * 60 * 1000

/** Tombstones deleted strictly before this instant are purged. */
export function tombstoneCutoff(nowMs: number): Date {
  return new Date(nowMs - COMMENT_TOMBSTONE_DAYS * DAY_MS)
}

/** Whether a comment is a tombstone old enough to purge (a live comment never is). */
export function isPurgeableTombstone(deletedAt: Date | null, nowMs: number): boolean {
  return deletedAt != null && deletedAt.getTime() < tombstoneCutoff(nowMs).getTime()
}
