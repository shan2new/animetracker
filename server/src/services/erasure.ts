import { createClerkClient } from '@clerk/backend'
import { and, eq, isNull } from 'drizzle-orm'
import { db } from '../db/index.js'
import { moderationBans, users } from '../db/schema.js'
import { env } from '../env.js'
import { isSuspended, ModerationError } from './moderation.js'

// The two loose ends of `DELETE /me` (routes/me.ts; docs/api-contract.md, "Account deletion"),
// both run only AFTER the erasure transaction has committed:
//
// 1. A recently erased identity is refused. A Clerk session JWT is verified OFFLINE, so it stays
//    valid for up to a minute after the account is gone, and `authenticate` upserts a users row for
//    any valid token — so the app's in-flight and retried writes (likes, ratings, progress, a queued
//    comment) would quietly re-create the account the user just erased. `recordErasure` remembers
//    the Clerk id in this process for `ERASURE_HOLD_MS` (longer than any session JWT lives) and
//    `authenticate` answers `401 { error: 'account deleted' }` to it, before the upsert.
// 2. The Clerk identity itself is erased (`eraseClerkIdentity`): deleted through Clerk's backend
//    API — or, for a SUSPENDED identity, banned there instead, so the same email cannot sign up
//    again for a fresh clerk id and walk around the ban (the ban row is the disclosed retention).
//    A failure is logged (`account.clerk_delete_failed`) and retried by hand with
//    `npm run moderation -- clerk-delete <clerkId>`.

/** How long an erased identity is refused. Clerk session JWTs live about a minute. */
export const ERASURE_HOLD_MS = 15 * 60_000
/** The most identities held at once; the oldest goes first. */
export const MAX_HELD_ERASURES = 10_000

// clerkId → the ms epoch its hold ends. Every hold is the same length, so insertion order IS
// expiry order and pruning stops at the first live entry.
const held = new Map<string, number>()

function prune(nowMs: number): void {
  for (const [clerkId, until] of held) {
    if (until > nowMs) break
    held.delete(clerkId)
  }
}

/** Remember that `clerkId` was just erased (call it once the erasure has COMMITTED). */
export function recordErasure(clerkId: string, nowMs: number = Date.now()): void {
  prune(nowMs)
  held.delete(clerkId) // re-inserted at the end, keeping the map in expiry order
  held.set(clerkId, nowMs + ERASURE_HOLD_MS)
  while (held.size > MAX_HELD_ERASURES) {
    const oldest = held.keys().next().value
    if (oldest === undefined) break
    held.delete(oldest)
  }
}

/** True while `clerkId` is inside its post-erasure hold. */
export function wasErased(clerkId: string, nowMs: number = Date.now()): boolean {
  const until = held.get(clerkId)
  if (until === undefined) return false
  if (until > nowMs) return true
  held.delete(clerkId)
  return false
}

/** Test hook: forget every hold. */
export function resetErasures(): void {
  held.clear()
}

/** The slice of Clerk's backend user API the erasure uses (injectable for tests). */
export interface ClerkUsersApi {
  deleteUser(userId: string): Promise<unknown>
  banUser(userId: string): Promise<unknown>
}

export type ClerkErasureOutcome =
  /** The Clerk user is gone (or already was: Clerk answered 404). */
  | { outcome: 'deleted' }
  /** A suspended identity: banned in Clerk, kept so its email cannot sign up again. */
  | { outcome: 'banned' }
  /** No `CLERK_SECRET_KEY` on this server: nothing could be called. */
  | { outcome: 'skipped' }
  | { outcome: 'failed'; error: string }

/** A suspended identity is banned in Clerk; any other is deleted. Pure. */
export function clerkErasureAction(suspended: boolean): 'ban' | 'delete' {
  return suspended ? 'ban' : 'delete'
}

const CLERK_TIMEOUT_MS = 10_000

function defaultClerkUsers(): ClerkUsersApi | null {
  const secretKey = env.CLERK_SECRET_KEY?.trim()
  return secretKey ? createClerkClient({ secretKey }).users : null
}

function statusOf(error: unknown): number | null {
  const status = (error as { status?: unknown } | null)?.status
  return typeof status === 'number' ? status : null
}

/**
 * Erase (or, when suspended, ban) the Clerk identity. Never throws: the account's own data is
 * already gone when this runs, so a Clerk failure is reported, not raised.
 */
export async function eraseClerkIdentity(
  clerkId: string,
  opts: { suspended?: boolean; users?: ClerkUsersApi | null; timeoutMs?: number } = {},
): Promise<ClerkErasureOutcome> {
  const clerkUsers = opts.users === undefined ? defaultClerkUsers() : opts.users
  if (!clerkUsers) return { outcome: 'skipped' }
  try {
    const suspended = opts.suspended ?? (await isSuspended(clerkId))
    const action = clerkErasureAction(suspended)
    let timer: NodeJS.Timeout | undefined
    const timeout = new Promise<never>((_, reject) => {
      timer = setTimeout(() => reject(new Error('timed out')), opts.timeoutMs ?? CLERK_TIMEOUT_MS)
    })
    try {
      await Promise.race([action === 'ban' ? clerkUsers.banUser(clerkId) : clerkUsers.deleteUser(clerkId), timeout])
    } finally {
      clearTimeout(timer)
    }
    return { outcome: action === 'ban' ? 'banned' : 'deleted' }
  } catch (error) {
    // A Clerk user that no longer exists is the outcome asked for.
    if (statusOf(error) === 404) return { outcome: 'deleted' }
    return { outcome: 'failed', error: error instanceof Error ? error.message : String(error) }
  }
}

/**
 * The operator's retry (`npm run moderation -- clerk-delete <clerkId>`) after
 * `account.clerk_delete_failed`. It only FINISHES an erasure: an identity that still has an
 * account on this server is refused (deleting its Clerk login would lock a live user out, and the
 * user erases their own account in the app). An active ban on this server bans in Clerk instead.
 */
export async function retryClerkErasure(clerkId: string): Promise<ClerkErasureOutcome> {
  const [account] = await db.select({ id: users.id }).from(users).where(eq(users.clerkId, clerkId)).limit(1)
  if (account) {
    throw new ModerationError(`${clerkId} still has an account on this server; clerk-delete only finishes an erasure`)
  }
  const [ban] = await db
    .select({ clerkId: moderationBans.clerkId })
    .from(moderationBans)
    .where(and(eq(moderationBans.clerkId, clerkId), isNull(moderationBans.liftedAt)))
    .limit(1)
  return eraseClerkIdentity(clerkId, { suspended: ban != null })
}
