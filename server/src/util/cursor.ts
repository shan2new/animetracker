import { sql, type AnyColumn, type SQL } from 'drizzle-orm'
import { z } from 'zod'

// Keyset cursors for `(created_at, id)` pages (comment threads, notifications), optionally ranked
// (`top` comments: `(like_count, created_at, id)`). Opaque to clients: base64url of a small JSON.
//
// `at` is the row's `created_at` exactly as Postgres holds it — microseconds, UTC — selected with
// `cursorAt(col)`. A JS Date only keeps milliseconds, so a cursor built from one would sit up to
// 999 µs before the row it came from and the next page would repeat or skip rows written in the
// same millisecond (every `defaultNow()` insert in a transaction shares one).

export interface KeysetCursor {
  /** ISO-8601 UTC with exactly six fractional digits, e.g. "2026-09-25T10:00:00.123456Z". */
  at: string
  /** The row's uuid (the tiebreak). */
  id: string
  /** The ranked sort key for `top` pages (a like count). */
  rank?: number
}

const AT_RE = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z$/
/** Generous for `{ at, id, rank }` (~110 chars encoded); anything longer is not ours. */
const MAX_ENCODED_LENGTH = 400

const cursorSchema = z
  .object({
    at: z
      .string()
      .regex(AT_RE)
      // The regex admits 2026-02-30 and 25:00; Postgres would throw on the cast (a 500), so a
      // cursor must name a real instant: the millisecond prefix has to survive a Date round-trip.
      .refine((at) => {
        const ms = Date.parse(`${at.slice(0, 23)}Z`)
        return Number.isFinite(ms) && new Date(ms).toISOString().slice(0, 23) === at.slice(0, 23)
      }),
    id: z.string().uuid(),
    rank: z.number().int().min(0).optional(),
  })
  .strict()

export function encodeCursor(c: KeysetCursor): string {
  const body: KeysetCursor = { at: c.at, id: c.id }
  if (c.rank !== undefined) body.rank = c.rank
  return Buffer.from(JSON.stringify(body), 'utf8').toString('base64url')
}

/** Null for anything that is not a cursor this server wrote (the route answers 400). */
export function decodeCursor(s: string): KeysetCursor | null {
  if (typeof s !== 'string' || s.length === 0 || s.length > MAX_ENCODED_LENGTH) return null
  // Node's base64url decoder skips characters it does not know; refuse them instead.
  if (!/^[A-Za-z0-9_-]+$/.test(s)) return null
  let json: unknown
  try {
    json = JSON.parse(Buffer.from(s, 'base64url').toString('utf8'))
  } catch {
    return null
  }
  const parsed = cursorSchema.safeParse(json)
  if (!parsed.success) return null
  const out: KeysetCursor = { at: parsed.data.at, id: parsed.data.id }
  if (parsed.data.rank !== undefined) out.rank = parsed.data.rank
  return out
}

/**
 * A timestamptz column (or expression) as the cursor's `at` string: UTC, exact to the microsecond.
 * Compare it back with `(created_at, id) < (${at}::timestamptz, ${id}::uuid)`.
 */
export function cursorAt(col: AnyColumn | SQL): SQL<string> {
  return sql<string>`to_char(${col} at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')`
}
