import { beforeEach, describe, expect, it, vi } from 'vitest'

// services/erasure.ts: the post-erasure hold `authenticate` reads, and the Clerk identity's erasure
// (Clerk's API injected — no network, no database).

const mocks = vi.hoisted(() => ({
  isSuspended: vi.fn(),
  /** What each successive `db.select(...)…limit()` answers, in order. */
  selects: [] as unknown[][],
}))
vi.mock('../db/index.js', () => {
  const chain = {
    from: () => chain,
    where: () => chain,
    limit: async () => mocks.selects.shift() ?? [],
  }
  return { db: { select: () => chain }, sql: {} }
})
vi.mock('./moderation.js', () => ({
  isSuspended: mocks.isSuspended,
  ModerationError: class ModerationError extends Error {},
}))

const {
  ERASURE_HOLD_MS,
  MAX_HELD_ERASURES,
  clerkErasureAction,
  eraseClerkIdentity,
  recordErasure,
  resetErasures,
  retryClerkErasure,
  wasErased,
} = await import('./erasure.js')

const T0 = Date.UTC(2026, 8, 25, 12)

beforeEach(() => {
  resetErasures()
  mocks.isSuspended.mockReset().mockResolvedValue(false)
  mocks.selects.length = 0
})

describe('the post-erasure hold', () => {
  it('refuses the identity for 15 minutes, then forgets it', () => {
    recordErasure('user_a', T0)
    expect(wasErased('user_a', T0)).toBe(true)
    expect(wasErased('user_a', T0 + ERASURE_HOLD_MS - 1)).toBe(true)
    expect(wasErased('user_a', T0 + ERASURE_HOLD_MS)).toBe(false)
    expect(wasErased('user_b', T0)).toBe(false)
  })

  it('a second erasure of the same identity restarts its hold', () => {
    recordErasure('user_a', T0)
    recordErasure('user_a', T0 + 10 * 60_000)
    expect(wasErased('user_a', T0 + ERASURE_HOLD_MS + 60_000)).toBe(true)
  })

  it('is bounded: past the cap the oldest hold goes first', () => {
    for (let i = 0; i <= MAX_HELD_ERASURES; i++) recordErasure(`user_${i}`, T0)
    expect(wasErased('user_0', T0)).toBe(false)
    expect(wasErased('user_1', T0)).toBe(true)
    expect(wasErased(`user_${MAX_HELD_ERASURES}`, T0)).toBe(true)
  })
})

describe('eraseClerkIdentity', () => {
  function fakeUsers() {
    return { deleteUser: vi.fn(async () => ({})), banUser: vi.fn(async () => ({})) }
  }

  it('deletes an ordinary identity', async () => {
    const users = fakeUsers()
    expect(await eraseClerkIdentity('user_a', { users })).toEqual({ outcome: 'deleted' })
    expect(users.deleteUser).toHaveBeenCalledWith('user_a')
    expect(users.banUser).not.toHaveBeenCalled()
    expect(mocks.isSuspended).toHaveBeenCalledWith('user_a')
  })

  it('BANS a suspended identity in Clerk instead, so its email cannot sign up again', async () => {
    const users = fakeUsers()
    mocks.isSuspended.mockResolvedValue(true)
    expect(await eraseClerkIdentity('user_a', { users })).toEqual({ outcome: 'banned' })
    expect(users.banUser).toHaveBeenCalledWith('user_a')
    expect(users.deleteUser).not.toHaveBeenCalled()
    expect(clerkErasureAction(true)).toBe('ban')
    expect(clerkErasureAction(false)).toBe('delete')
  })

  it('an identity Clerk no longer has is the outcome asked for', async () => {
    const users = fakeUsers()
    users.deleteUser.mockRejectedValue(Object.assign(new Error('Not Found'), { status: 404 }))
    expect(await eraseClerkIdentity('user_a', { users })).toEqual({ outcome: 'deleted' })
  })

  it('reports a failure or a timeout instead of throwing', async () => {
    const users = fakeUsers()
    users.deleteUser.mockRejectedValue(Object.assign(new Error('Internal'), { status: 500 }))
    expect(await eraseClerkIdentity('user_a', { users })).toEqual({ outcome: 'failed', error: 'Internal' })

    users.deleteUser.mockImplementation(() => new Promise(() => {}))
    expect(await eraseClerkIdentity('user_a', { users, timeoutMs: 5 })).toEqual({ outcome: 'failed', error: 'timed out' })
  })

  it('skips when the server has no Clerk secret key', async () => {
    expect(await eraseClerkIdentity('user_a', { users: null })).toEqual({ outcome: 'skipped' })
  })
})

describe('retryClerkErasure (npm run moderation -- clerk-delete)', () => {
  it('refuses an identity that still has an account here', async () => {
    mocks.selects.push([{ id: 'u1' }])
    await expect(retryClerkErasure('user_live')).rejects.toThrow(/still has an account on this server/)
  })

  it('finishes an erased identity: skipped without a Clerk secret key, never throwing', async () => {
    // No users row, no active ban. This server has no CLERK_SECRET_KEY in the test env.
    mocks.selects.push([], [])
    const result = await retryClerkErasure('user_gone')
    expect(['skipped', 'deleted', 'failed']).toContain(result.outcome)
    expect(mocks.isSuspended).not.toHaveBeenCalled()
  })
})
