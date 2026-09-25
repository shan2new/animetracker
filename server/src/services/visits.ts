import { eq } from 'drizzle-orm'
import { db } from '../db/index.js'
import { users } from '../db/schema.js'

// "Since your last visit" anchors. `POST /me/opened` shifts `last_opened_at → prev_opened_at` and
// stamps now in one statement (services/library.ts `markOpened`), so a read in the same session
// compares against the REAL previous visit instead of the stamp that session just wrote (the
// pre-0010 echo bug: the pill and "Out now" compared against a moment ago).

/**
 * Pure. `prev` 0 = never shifted since migration 0010 (the column arrived as 0 for every existing
 * account), so the last stamp is the best anchor there is until the next `POST /me/opened`.
 */
export function effectivePrevOpenedAt(prev: number, last: number): number {
  return prev > 0 ? prev : last
}

/**
 * Pure. The client's own anchor (`GET /me/feed?since=`) when it is a real past instant
 * (0 < since ≤ now), else null — the caller then reads the stored one. The client passes the
 * `prevOpenedAt` its `POST /me/opened` answered this session, which the stored value stops being
 * the moment that stamp failed (it is never retried) or ANOTHER device stamped a visit, so the
 * server's fresh block and the client's "since …" marker always name the same boundary.
 */
export function clientAnchor(since: number | null | undefined, nowMs: number): number | null {
  return since != null && Number.isSafeInteger(since) && since > 0 && since <= nowMs ? since : null
}

/**
 * The caller's visit anchors. `prevOpenedAt` is already EFFECTIVE (see above) — it is the value
 * `GET /me/library` and `GET /me/feed` return and order "new" against. Both are 0 for an unknown id.
 */
export async function readVisitAnchors(userId: string): Promise<{ prevOpenedAt: number; lastOpenedAt: number }> {
  const [row] = await db
    .select({ prev: users.prevOpenedAt, last: users.lastOpenedAt })
    .from(users)
    .where(eq(users.id, userId))
    .limit(1)
  const last = row?.last ?? 0
  return { prevOpenedAt: effectivePrevOpenedAt(row?.prev ?? 0, last), lastOpenedAt: last }
}
