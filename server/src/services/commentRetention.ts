import { and, isNotNull, lt } from 'drizzle-orm'
import { db } from '../db/index.js'
import { comments } from '../db/schema.js'
import { tombstoneCutoff } from '../social/retention.js'

/**
 * Remove comments their authors deleted more than `COMMENT_TOMBSTONE_DAYS` ago (social/retention.ts
 * says why the window exists). `comment_likes`, `reports` and `notifications` rows that point at a
 * purged comment go with it (ON DELETE CASCADE); a reply keeps standing with `parent_id` set to null
 * (ON DELETE SET NULL) — its parent was already invisible, so the thread reads the same. Only an
 * author's soft delete sets `deleted_at`; hidden comments are moderation state and are kept.
 * Returns how many rows were removed.
 */
export async function purgeCommentTombstones(nowMs: number = Date.now()): Promise<number> {
  const removed = await db
    .delete(comments)
    .where(and(isNotNull(comments.deletedAt), lt(comments.deletedAt, tombstoneCutoff(nowMs))))
    .returning({ id: comments.id })
  return removed.length
}
