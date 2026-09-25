import { beforeEach, describe, expect, it, vi } from 'vitest'

// services/export.ts (GET /me/export): the categories an access request must see — the visit
// stamps, the profile's own times, why a comment was hidden, the stored notification text, and the
// one record kept after an erasure (the caller's ban row, read by their Clerk id). The database is
// a fake transaction that answers each query in the order buildAccountExport issues them.

const fake = vi.hoisted(() => {
  /** One answer per query, in order. */
  const answers: unknown[][] = []
  /** A query builder that is awaitable at any step and answers the next queued rows. */
  const chain = () => {
    const c: Record<string, unknown> = {}
    for (const m of ['from', 'innerJoin', 'leftJoin', 'where', 'orderBy', 'limit']) c[m] = () => c
    c.then = (resolve: (v: unknown) => unknown, reject: (e: unknown) => unknown) =>
      Promise.resolve(answers.shift() ?? []).then(resolve, reject)
    return c
  }
  const tx = { select: () => chain() }
  return { answers, tx }
})

vi.mock('../db/index.js', () => ({
  db: { transaction: async (fn: (tx: unknown) => unknown) => fn(fake.tx) },
  sql: {},
}))

const { buildAccountExport, moderationRecord, openedAtOrNull } = await import('./export.js')

const USER = '11111111-1111-4111-8111-111111111111'
const FRANCHISE = '33333333-3333-4333-8333-333333333333'
const COMMENT = '55555555-5555-4555-8555-555555555555'
const T = (iso: string) => new Date(iso)

beforeEach(() => {
  fake.answers.length = 0
})

describe('openedAtOrNull / moderationRecord', () => {
  it('reads a 0 visit stamp as never', () => {
    expect(openedAtOrNull(0)).toBeNull()
    expect(openedAtOrNull(null)).toBeNull()
    expect(openedAtOrNull(Number.NaN)).toBeNull()
    expect(openedAtOrNull(1790330400000)).toBe(1790330400000)
  })

  it('an identity never suspended has no record; an active and a lifted ban both show', () => {
    expect(moderationRecord(undefined)).toBeNull()
    expect(moderationRecord({ reason: 'harassment', createdAt: T('2026-09-20T00:00:00Z'), liftedAt: null })).toEqual({
      suspended: true,
      reason: 'harassment',
      since: Date.parse('2026-09-20T00:00:00Z'),
      liftedAt: null,
    })
    expect(
      moderationRecord({ reason: null, createdAt: T('2026-09-20T00:00:00Z'), liftedAt: T('2026-09-22T00:00:00Z') }),
    ).toEqual({ suspended: false, reason: null, since: Date.parse('2026-09-20T00:00:00Z'), liftedAt: Date.parse('2026-09-22T00:00:00Z') })
  })
})

describe('buildAccountExport', () => {
  it('includes the visit stamps, profile times, the ban record, hidden reasons and notification text', async () => {
    fake.answers.push(
      // account
      [
        {
          id: USER,
          clerkId: 'user_x',
          createdAt: T('2026-09-01T00:00:00Z'),
          email: 'x@example.com',
          lastOpenedAt: 1790330400000,
          prevOpenedAt: 0,
        },
      ],
      // profile
      [
        {
          handle: 'dex',
          displayName: 'Dex',
          termsAcceptedAt: T('2026-09-02T00:00:00Z'),
          termsVersion: '2026-09-25',
          createdAt: T('2026-09-02T00:00:00Z'),
          updatedAt: T('2026-09-03T00:00:00Z'),
        },
      ],
      // moderation ban (by Clerk id)
      [{ reason: 'spam', createdAt: T('2026-09-20T00:00:00Z'), liftedAt: null }],
      [], // subscriptions
      [], // progress
      [], // preferences
      [], // recommendation feedback
      // comments
      [
        {
          id: COMMENT,
          subject: 'ep:154587:12',
          parentId: null,
          body: 'So good',
          createdAt: T('2026-09-10T00:00:00Z'),
          deletedAt: null,
          hiddenAt: T('2026-09-11T00:00:00Z'),
          hiddenReason: 'reports',
        },
      ],
      [], // likes
      [], // comment likes
      [], // saves
      [], // reminders
      [], // hides
      [], // ratings
      [], // blocks
      [], // reports
      // notifications
      [
        {
          id: '77777777-7777-4777-8777-777777777777',
          kind: 'comment_hidden',
          franchiseId: FRANCHISE,
          title: 'Frieren',
          body: 'reports',
          subject: null,
          postId: null,
          commentId: null,
          createdAt: T('2026-09-11T00:00:00Z'),
          readAt: null,
        },
      ],
    )

    const doc = await buildAccountExport(USER, 42)
    expect(fake.answers).toHaveLength(0) // every query was answered, in order
    expect(doc?.exportedAt).toBe(42)
    expect(doc?.account).toEqual({
      id: USER,
      createdAt: Date.parse('2026-09-01T00:00:00Z'),
      email: 'x@example.com',
      lastOpenedAt: 1790330400000,
      prevOpenedAt: null,
    })
    expect(doc?.account).not.toHaveProperty('clerkId')
    expect(doc?.profile).toMatchObject({
      createdAt: Date.parse('2026-09-02T00:00:00Z'),
      updatedAt: Date.parse('2026-09-03T00:00:00Z'),
    })
    expect(doc?.moderation).toEqual({
      suspended: true,
      reason: 'spam',
      since: Date.parse('2026-09-20T00:00:00Z'),
      liftedAt: null,
    })
    expect(doc?.social.comments[0]).toMatchObject({ hiddenReason: 'reports', hiddenAt: Date.parse('2026-09-11T00:00:00Z') })
    expect(doc?.social.notifications[0]).toMatchObject({ kind: 'comment_hidden', title: 'Frieren', body: 'reports' })
  })

  it('an identity that was never suspended exports moderation: null', async () => {
    fake.answers.push([{ id: USER, clerkId: 'user_x', createdAt: T('2026-09-01T00:00:00Z'), email: null, lastOpenedAt: 0, prevOpenedAt: 0 }])
    const doc = await buildAccountExport(USER, 1)
    expect(doc?.moderation).toBeNull()
    expect(doc?.profile).toBeNull()
    expect(doc?.account.lastOpenedAt).toBeNull()
  })

  it('no account row → null', async () => {
    expect(await buildAccountExport(USER, 1)).toBeNull()
  })
})
