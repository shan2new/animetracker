import { sql, type AnyColumn, type SQL } from 'drizzle-orm'
import type { db } from '../db/index.js'
import { blocks } from '../db/schema.js'

// Blocks hide people from each other in BOTH directions (docs/api-contract.md, "Social"): a
// viewer sees nothing written by someone they blocked, and nothing written by someone who blocked
// them. Counts stay global (D14); only lists, reply parents, notifications and the comment-like
// target check are filtered.
//
// `blocks.user_id` blocked `blocks.blocked_user_id`.

/** The pool handle or a transaction handle (grouping/service.ts's idiom). */
export type Executor = typeof db | Parameters<Parameters<typeof db.transaction>[0]>[0]

/** The key `blockedEitherWay` reads: "<blocker>:<blocked>". */
export function blockPairKey(blockerId: string, blockedId: string): string {
  return `${blockerId}:${blockedId}`
}

/**
 * True when either user has blocked the other. `pairs` holds "<blocker>:<blocked>" keys
 * (`blockPairKey`). The in-memory rule behind notification decisions.
 */
export function blockedEitherWay(a: string, b: string, pairs: ReadonlySet<string>): boolean {
  return pairs.has(blockPairKey(a, b)) || pairs.has(blockPairKey(b, a))
}

/**
 * The fragment every list query ANDs in: the author is not someone the viewer blocked, and the
 * viewer is not someone the author blocked. `authorCol` is a column, or a raw alias such as
 * sql`c.user_id` inside a hand-written query.
 */
export function notBlockedEitherWaySql(viewerId: string, authorCol: AnyColumn | SQL): SQL {
  return sql`(${authorCol} not in (select ${blocks.blockedUserId} from ${blocks} where ${blocks.userId} = ${viewerId}) and ${authorCol} not in (select ${blocks.userId} from ${blocks} where ${blocks.blockedUserId} = ${viewerId}))`
}

/** One `exists` over both directions (a reply's parent, a like's notification). */
export async function isBlockedEitherWay(exec: Executor, a: string, b: string): Promise<boolean> {
  if (a === b) return false
  const rows = await exec
    .select({ one: sql<number>`1` })
    .from(blocks)
    .where(
      sql`(${blocks.userId} = ${a} and ${blocks.blockedUserId} = ${b}) or (${blocks.userId} = ${b} and ${blocks.blockedUserId} = ${a})`,
    )
    .limit(1)
  return rows.length > 0
}
