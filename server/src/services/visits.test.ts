import { beforeEach, describe, expect, it, vi } from 'vitest'

// No DB: the one query is answered by a fake `db` (the me.account.test.ts pattern).
const rows = vi.hoisted(() => ({ value: [] as { prev: number; last: number }[] }))

vi.mock('../db/index.js', () => ({
  db: {
    select: () => ({ from: () => ({ where: () => ({ limit: async () => rows.value }) }) }),
  },
  sql: {},
}))

const { clientAnchor, effectivePrevOpenedAt, readVisitAnchors } = await import('./visits.js')

const U = '11111111-1111-4111-8111-111111111111'

beforeEach(() => {
  rows.value = []
})

describe('effectivePrevOpenedAt', () => {
  it('uses the shifted previous visit when there is one', () => {
    expect(effectivePrevOpenedAt(1_790_000_000_000, 1_790_300_000_000)).toBe(1_790_000_000_000)
  })

  it('falls back to the last stamp for an account not yet shifted since 0010', () => {
    expect(effectivePrevOpenedAt(0, 1_790_300_000_000)).toBe(1_790_300_000_000)
    expect(effectivePrevOpenedAt(0, 0)).toBe(0)
  })
})

describe('clientAnchor', () => {
  const NOW = 1_790_400_000_000

  it("takes the client's anchor when it is a real past instant, up to and including now", () => {
    expect(clientAnchor(1_790_000_000_000, NOW)).toBe(1_790_000_000_000)
    expect(clientAnchor(NOW, NOW)).toBe(NOW)
    expect(clientAnchor(1, NOW)).toBe(1)
  })

  it('declines a missing, zero, future or unsafe anchor, so the stored one is read', () => {
    expect(clientAnchor(undefined, NOW)).toBeNull()
    expect(clientAnchor(null, NOW)).toBeNull()
    expect(clientAnchor(0, NOW)).toBeNull()
    expect(clientAnchor(NOW + 1, NOW)).toBeNull()
    expect(clientAnchor(Number.MAX_SAFE_INTEGER + 2, Number.MAX_VALUE)).toBeNull()
    expect(clientAnchor(1.5, NOW)).toBeNull()
  })
})

describe('readVisitAnchors', () => {
  it('returns the effective previous visit and the last stamp', async () => {
    rows.value = [{ prev: 0, last: 42 }]
    expect(await readVisitAnchors(U)).toEqual({ prevOpenedAt: 42, lastOpenedAt: 42 })
    rows.value = [{ prev: 7, last: 42 }]
    expect(await readVisitAnchors(U)).toEqual({ prevOpenedAt: 7, lastOpenedAt: 42 })
  })

  it('is zero for an unknown user', async () => {
    expect(await readVisitAnchors(U)).toEqual({ prevOpenedAt: 0, lastOpenedAt: 0 })
  })
})
