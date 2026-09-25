import type { FastifyReply } from 'fastify'
import { env, type Env } from '../env.js'
import type { AppUser } from '../services/users.js'

// Per-user, in-process rate limits for the social layer (App Review 1.2's "prevent abuse").
//
// Keys are `${bucket}:${clerkId}` — the IDENTITY, never `req.ip` (behind the Cloudflare tunnel with
// `trustProxy` off every request arrives from the proxy's address) and never `users.id`: deleting
// the account and signing straight back in mints a new users row for the same Clerk id, and must
// not hand back a fresh allowance. One process serves the app, so an in-memory sliding-window log
// is exact; a restart forgets the logs, which only ever errs toward allowing.

export type RateAction =
  | 'comment'
  | 'commentNew'
  | 'toggle'
  | 'report'
  | 'block'
  | 'profile'
  | 'lookup'
  | 'export'
  | 'rejected'
  | 'read'

export interface RateRule {
  limit: number
  windowMs: number
}

export type RateDecision = { allowed: true } | { allowed: false; retryAfterSec: number }

const MINUTE = 60_000
const HOUR = 60 * MINUTE
const DAY = 24 * HOUR

/** How long an account counts as new for the comment budget (`commentAction`). */
export const NEW_ACCOUNT_MS = DAY

/**
 * Actions that spend another action's log under their own rules. A new account's comments go in the
 * SAME log as everyone's, so the day it stops being new its last hour is still counted.
 */
const BUCKET: Partial<Record<RateAction, RateAction>> = { commentNew: 'comment' }

/** The limiter key for a signed-in caller: the Clerk id (see the header). */
export function rateKeyOf(user: Pick<AppUser, 'clerkId'>): string {
  return user.clerkId
}

/**
 * Which comment budget a caller spends: `commentNew` while the account is younger than
 * `NEW_ACCOUNT_MS`, else `comment`. An unknown creation time reads as established.
 */
export function commentAction(user: Pick<AppUser, 'createdAt'>, nowMs: number = Date.now()): 'comment' | 'commentNew' {
  return user.createdAt != null && nowMs - user.createdAt < NEW_ACCOUNT_MS ? 'commentNew' : 'comment'
}

/**
 * Pure sliding-window log. `history` = ascending ms of ALLOWED hits for one (action, user).
 *
 * A hit counts inside a rule's window while it is strictly newer than `now - windowMs`. When any
 * rule is full, the answer is the LONGEST wait among the full rules and the hit is not recorded
 * (a client hammering a denied route cannot extend its own lockout). Otherwise `now` is appended
 * and the log is trimmed to the largest limit, which is all any rule can ever need.
 */
export function decideRate(
  history: readonly number[],
  rules: readonly RateRule[],
  nowMs: number,
): { decision: RateDecision; history: number[] } {
  if (rules.length === 0) return { decision: { allowed: true }, history: [] }

  const maxWindow = Math.max(...rules.map((r) => r.windowMs))
  const pruned = history.filter((t) => t > nowMs - maxWindow)

  let retryAfterSec = 0
  for (const rule of rules) {
    const inWindow = pruned.filter((t) => t > nowMs - rule.windowMs)
    if (inWindow.length < rule.limit) continue
    // The hit that must age out before this rule has room again. With the log only ever holding
    // allowed hits, `inWindow.length === limit` and this is the oldest hit in the window.
    const gate = inWindow[inWindow.length - rule.limit]!
    const wait = Math.max(1, Math.ceil((gate + rule.windowMs - nowMs) / 1000))
    retryAfterSec = Math.max(retryAfterSec, wait)
  }

  if (retryAfterSec > 0) return { decision: { allowed: false, retryAfterSec }, history: pruned }

  const maxLimit = Math.max(...rules.map((r) => r.limit))
  const next = [...pruned, nowMs].sort((a, b) => a - b)
  return { decision: { allowed: true }, history: next.slice(Math.max(0, next.length - maxLimit)) }
}

/** The rule table of docs/api-contract.md ("Rate limits"), from the SOCIAL_RATE_* env keys. */
export function rateRulesFromEnv(e: Env): Record<RateAction, RateRule[]> {
  return {
    comment: [
      { limit: e.SOCIAL_RATE_COMMENTS_PER_MINUTE, windowMs: MINUTE },
      { limit: e.SOCIAL_RATE_COMMENTS_PER_HOUR, windowMs: HOUR },
    ],
    // The comment rules plus the new-account hour. The full hour rule stays in the list so the
    // shared log is kept at its size.
    commentNew: [
      { limit: e.SOCIAL_RATE_COMMENTS_PER_MINUTE, windowMs: MINUTE },
      { limit: e.SOCIAL_RATE_COMMENTS_PER_HOUR, windowMs: HOUR },
      { limit: e.SOCIAL_RATE_NEW_COMMENTS_PER_HOUR, windowMs: HOUR },
    ],
    toggle: [{ limit: e.SOCIAL_RATE_TOGGLES_PER_MINUTE, windowMs: MINUTE }],
    report: [{ limit: e.SOCIAL_RATE_REPORTS_PER_HOUR, windowMs: HOUR }],
    block: [{ limit: e.SOCIAL_RATE_BLOCKS_PER_HOUR, windowMs: HOUR }],
    profile: [{ limit: e.SOCIAL_RATE_PROFILE_PER_DAY, windowMs: DAY }],
    lookup: [{ limit: e.SOCIAL_RATE_TOGGLES_PER_MINUTE, windowMs: MINUTE }],
    export: [{ limit: e.SOCIAL_RATE_EXPORTS_PER_HOUR, windowMs: HOUR }],
    rejected: [{ limit: e.SOCIAL_RATE_REJECTED_PER_HOUR, windowMs: HOUR }],
    read: [{ limit: e.SOCIAL_RATE_READS_PER_MINUTE, windowMs: MINUTE }],
  }
}

export class RateLimiter {
  private readonly store = new Map<string, number[]>()
  private readonly maxKeys: number
  private readonly disabled: boolean

  constructor(
    private readonly rules: Record<RateAction, RateRule[]>,
    opts?: { maxKeys?: number; disabled?: boolean },
  ) {
    this.maxKeys = opts?.maxKeys ?? 10_000
    this.disabled = opts?.disabled ?? false
  }

  /** Decide, and record the hit when it is allowed. `rateKey` is `rateKeyOf(req.user!)`. */
  check(action: RateAction, rateKey: string, nowMs: number = Date.now()): RateDecision {
    if (this.disabled) return { allowed: true }
    const key = `${BUCKET[action] ?? action}:${rateKey}`
    const { decision, history } = decideRate(this.store.get(key) ?? [], this.rules[action], nowMs)
    // Delete-then-set moves the key to the end of the Map's insertion order, so the key shed below
    // is the one that has gone longest without a check (news/service.ts's bounded-map idiom).
    this.store.delete(key)
    if (history.length > 0) this.store.set(key, history)
    if (this.store.size > this.maxKeys) this.store.delete(this.store.keys().next().value!)
    return decision
  }

  /** How many (action, user) logs are held. */
  get size(): number {
    return this.store.size
  }
}

/** The process's limiter, built from env. `SOCIAL_RATE_LIMIT_DISABLED=1` turns every check into an allow. */
export const rateLimiter = new RateLimiter(rateRulesFromEnv(env), { disabled: env.SOCIAL_RATE_LIMIT_DISABLED })

/** `429 { error: 'rate_limited', retryAfter }` with a matching integer `Retry-After` header (≥ 1). */
export function sendRateLimited(reply: FastifyReply, retryAfterSec: number): FastifyReply {
  const seconds = Math.max(1, Math.ceil(Number.isFinite(retryAfterSec) ? retryAfterSec : 1))
  return reply.code(429).header('Retry-After', String(seconds)).send({ error: 'rate_limited', retryAfter: seconds })
}
