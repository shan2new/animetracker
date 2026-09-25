import Fastify from 'fastify'
import { describe, expect, it } from 'vitest'
import { envSchema } from '../env.js'
import {
  commentAction,
  decideRate,
  NEW_ACCOUNT_MS,
  rateKeyOf,
  RateLimiter,
  rateRulesFromEnv,
  sendRateLimited,
  type RateAction,
  type RateRule,
} from './rateLimit.js'

const T0 = 1_790_000_000_000
const MIN = 60_000
const HOUR = 60 * MIN
const U1 = '11111111-1111-4111-8111-111111111111'
const U2 = '22222222-2222-4222-8222-222222222222'

/** Feed `n` hits through decideRate at the given instants, returning the last decision and log. */
function run(rules: RateRule[], at: number[]) {
  let history: number[] = []
  let decision = decideRate(history, rules, at[0] ?? T0).decision
  for (const t of at) {
    const r = decideRate(history, rules, t)
    decision = r.decision
    history = r.history
  }
  return { decision, history }
}

function rulesWith(overrides: Partial<Record<RateAction, RateRule[]>>): Record<RateAction, RateRule[]> {
  return { ...rateRulesFromEnv(envSchema.parse({})), ...overrides }
}

describe('decideRate — a pure sliding-window log', () => {
  const perMinute3: RateRule[] = [{ limit: 3, windowMs: MIN }]

  it('allows up to the limit and denies the next', () => {
    const hits = [T0, T0 + 1000, T0 + 2000]
    expect(run(perMinute3, hits).decision).toEqual({ allowed: true })
    expect(run(perMinute3, [...hits, T0 + 3000]).decision).toEqual({ allowed: false, retryAfterSec: 57 })
  })

  it('computes retryAfterSec exactly, rounding up, never below 1', () => {
    const { history } = run(perMinute3, [T0, T0 + 1, T0 + 2])
    // The oldest hit leaves the window at T0 + 60 000; 59 999 ms before that is 60 s rounded up.
    expect(decideRate(history, perMinute3, T0 + 1).decision).toEqual({ allowed: false, retryAfterSec: 60 })
    // 1 ms before the oldest hit ages out: still denied, and still at least a second.
    expect(decideRate(history, perMinute3, T0 + MIN - 1).decision).toEqual({ allowed: false, retryAfterSec: 1 })
    // At exactly T0 + windowMs the oldest hit is out of the window.
    expect(decideRate(history, perMinute3, T0 + MIN).decision).toEqual({ allowed: true })
  })

  it('does not record a denied hit, so hammering cannot extend the lockout', () => {
    const { history } = run(perMinute3, [T0, T0 + 1, T0 + 2])
    const denied = decideRate(history, perMinute3, T0 + 30_000)
    expect(denied.decision.allowed).toBe(false)
    expect(denied.history).toEqual(history)
  })

  it('slides: old hits fall out and make room', () => {
    const { history } = run(perMinute3, [T0, T0 + 20_000, T0 + 40_000])
    expect(decideRate(history, perMinute3, T0 + 59_000).decision.allowed).toBe(false)
    const next = decideRate(history, perMinute3, T0 + 61_000)
    expect(next.decision).toEqual({ allowed: true })
    expect(next.history).toEqual([T0 + 20_000, T0 + 40_000, T0 + 61_000])
  })

  describe('several rules at once (comments: per minute AND per hour)', () => {
    const rules: RateRule[] = [
      { limit: 2, windowMs: MIN },
      { limit: 3, windowMs: HOUR },
    ]

    it('the minute rule denies while the hour rule still has room', () => {
      const { decision } = run(rules, [T0, T0 + 1000, T0 + 2000])
      expect(decision).toEqual({ allowed: false, retryAfterSec: 58 })
    })

    it('the hour rule denies while the minute rule has room', () => {
      const { decision } = run(rules, [T0, T0 + 2 * MIN, T0 + 4 * MIN, T0 + 6 * MIN])
      expect(decision).toEqual({ allowed: false, retryAfterSec: Math.ceil((HOUR - 6 * MIN) / 1000) })
    })

    it('answers with the LONGEST wait when both deny', () => {
      const { decision } = run(rules, [T0, T0 + 10 * MIN, T0 + 10 * MIN + 1000, T0 + 10 * MIN + 2000])
      // minute: 58 s; hour: the first hit leaves at T0 + 60 min → 50 min − 2 s.
      expect(decision).toEqual({ allowed: false, retryAfterSec: 50 * 60 - 2 })
    })

    it('trims the log to the largest limit', () => {
      const { history } = run(rules, [T0, T0 + 2 * MIN, T0 + 4 * MIN, T0 + 2 * HOUR])
      expect(history).toEqual([T0 + 2 * HOUR])
      const long = run([{ limit: 2, windowMs: HOUR }], [T0, T0 + 1, T0 + 2 * HOUR, T0 + 2 * HOUR + 1])
      expect(long.history).toHaveLength(2)
    })
  })

  it('no rules → always allowed, nothing kept', () => {
    expect(decideRate([T0], [], T0)).toEqual({ decision: { allowed: true }, history: [] })
  })
})

describe('RateLimiter', () => {
  it('keys on (action, user): users and actions are independent', () => {
    const limiter = new RateLimiter(rulesWith({ comment: [{ limit: 1, windowMs: MIN }], toggle: [{ limit: 1, windowMs: MIN }] }))
    expect(limiter.check('comment', U1, T0)).toEqual({ allowed: true })
    expect(limiter.check('comment', U1, T0 + 1).allowed).toBe(false)
    expect(limiter.check('comment', U2, T0 + 1)).toEqual({ allowed: true })
    expect(limiter.check('toggle', U1, T0 + 1)).toEqual({ allowed: true })
  })

  it('evicts the least recently checked key past maxKeys', () => {
    const limiter = new RateLimiter(rulesWith({ report: [{ limit: 1, windowMs: HOUR }] }), { maxKeys: 2 })
    limiter.check('report', 'a', T0)
    limiter.check('report', 'b', T0)
    expect(limiter.check('report', 'a', T0 + 1).allowed).toBe(false) // touches 'a' → 'b' is now oldest
    limiter.check('report', 'c', T0 + 2) // size 3 > 2 → 'b' goes
    expect(limiter.size).toBe(2)
    expect(limiter.check('report', 'b', T0 + 3)).toEqual({ allowed: true }) // forgotten, so allowed again
    expect(limiter.check('report', 'c', T0 + 4).allowed).toBe(false)
  })

  it('disabled always allows', () => {
    const limiter = new RateLimiter(rulesWith({ comment: [{ limit: 1, windowMs: MIN }] }), { disabled: true })
    for (let i = 0; i < 5; i++) expect(limiter.check('comment', U1, T0 + i)).toEqual({ allowed: true })
    expect(limiter.size).toBe(0)
  })
})

describe('rateRulesFromEnv', () => {
  it('maps the documented defaults, lookup sharing the toggle budget', () => {
    const rules = rateRulesFromEnv(envSchema.parse({}))
    expect(rules.comment).toEqual([
      { limit: 5, windowMs: MIN },
      { limit: 60, windowMs: HOUR },
    ])
    expect(rules.toggle).toEqual([{ limit: 120, windowMs: MIN }])
    expect(rules.lookup).toEqual(rules.toggle)
    expect(rules.report).toEqual([{ limit: 20, windowMs: HOUR }])
    expect(rules.block).toEqual([{ limit: 30, windowMs: HOUR }])
    expect(rules.profile).toEqual([{ limit: 10, windowMs: 24 * HOUR }])
    expect(rules.export).toEqual([{ limit: 3, windowMs: HOUR }])
    expect(rules.commentNew).toEqual([
      { limit: 5, windowMs: MIN },
      { limit: 60, windowMs: HOUR },
      { limit: 10, windowMs: HOUR },
    ])
    expect(rules.rejected).toEqual([{ limit: 20, windowMs: HOUR }])
    expect(rules.read).toEqual([{ limit: 120, windowMs: MIN }])
  })
})

describe('the key: the Clerk identity, never users.id', () => {
  it('keys on the Clerk id, so a deleted-and-recreated account keeps its history', () => {
    const limiter = new RateLimiter(rulesWith({ report: [{ limit: 1, windowMs: HOUR }] }))
    const before = { id: U1, clerkId: 'user_2abc' }
    const recreated = { id: U2, clerkId: 'user_2abc' } // DELETE /me, then signed straight back in
    expect(limiter.check('report', rateKeyOf(before), T0)).toEqual({ allowed: true })
    expect(limiter.check('report', rateKeyOf(recreated), T0 + 1).allowed).toBe(false)
  })
})

describe('new accounts: a smaller comment hour on the SAME log', () => {
  it('commentAction is commentNew for the first day only; an unknown age is established', () => {
    expect(commentAction({ createdAt: T0 }, T0)).toBe('commentNew')
    expect(commentAction({ createdAt: T0 }, T0 + NEW_ACCOUNT_MS - 1)).toBe('commentNew')
    expect(commentAction({ createdAt: T0 }, T0 + NEW_ACCOUNT_MS)).toBe('comment')
    expect(commentAction({}, T0)).toBe('comment')
  })

  it('caps a new account at the new-account hour, and the day it ages its hour still counts', () => {
    const limiter = new RateLimiter(rateRulesFromEnv(envSchema.parse({})))
    // Ten comments, a minute apart (the per-minute rule never bites).
    for (let i = 0; i < 10; i++) expect(limiter.check('commentNew', 'user_new', T0 + i * MIN).allowed).toBe(true)
    expect(limiter.check('commentNew', 'user_new', T0 + 10 * MIN)).toEqual({ allowed: false, retryAfterSec: 50 * 60 })
    // Established from here: the same ten hits are in the log, so 50 more fit in the hour, not 60.
    for (let i = 0; i < 50; i++) {
      expect(limiter.check('comment', 'user_new', T0 + 10 * MIN + i * 1000 * 13).allowed, `hit ${i}`).toBe(true)
    }
    expect(limiter.check('comment', 'user_new', T0 + 22 * MIN).allowed).toBe(false)
  })
})

describe('refusals and heavy reads have budgets of their own', () => {
  it('rejected: 20 an hour by default, then denied', () => {
    const limiter = new RateLimiter(rateRulesFromEnv(envSchema.parse({})))
    for (let i = 0; i < 20; i++) expect(limiter.check('rejected', 'user_x', T0 + i).allowed).toBe(true)
    expect(limiter.check('rejected', 'user_x', T0 + 20).allowed).toBe(false)
    // Independent of the comment budget.
    expect(limiter.check('comment', 'user_x', T0 + 21)).toEqual({ allowed: true })
  })

  it('read: 120 a minute by default, then denied until the window slides', () => {
    const limiter = new RateLimiter(rateRulesFromEnv(envSchema.parse({})))
    for (let i = 0; i < 120; i++) expect(limiter.check('read', 'user_x', T0 + i * 100).allowed).toBe(true)
    expect(limiter.check('read', 'user_x', T0 + 12_000).allowed).toBe(false)
    expect(limiter.check('read', 'user_x', T0 + MIN)).toEqual({ allowed: true })
  })
})

describe('sendRateLimited', () => {
  it('answers 429 with retryAfter and an integer Retry-After header ≥ 1', async () => {
    const app = Fastify()
    app.get('/a', async (_req, reply) => sendRateLimited(reply, 12))
    app.get('/b', async (_req, reply) => sendRateLimited(reply, 0.2))
    const a = await app.inject({ method: 'GET', url: '/a' })
    expect(a.statusCode).toBe(429)
    expect(a.headers['retry-after']).toBe('12')
    expect(a.json()).toEqual({ error: 'rate_limited', retryAfter: 12 })
    const b = await app.inject({ method: 'GET', url: '/b' })
    expect(b.headers['retry-after']).toBe('1')
    expect(b.json()).toEqual({ error: 'rate_limited', retryAfter: 1 })
    await app.close()
  })
})
