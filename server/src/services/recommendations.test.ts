import { beforeEach, describe, expect, it, vi } from 'vitest'

const h = vi.hoisted(() => ({ rows: [] as unknown[][] }))

function query(rows: unknown[]): Record<string, unknown> {
  const chain: Record<string, unknown> = {}
  for (const method of ['from', 'innerJoin', 'where', 'orderBy', 'limit']) chain[method] = () => chain
  chain.then = (resolve: (value: unknown[]) => unknown) => Promise.resolve(rows).then(resolve)
  return chain
}

vi.mock('../db/index.js', () => ({
  db: {
    select: () => query(h.rows.shift() ?? []),
  },
}))

const { getDiscover } = await import('./recommendations.js')

beforeEach(() => {
  h.rows.length = 0
})

describe('getDiscover', () => {
  it('is explainable, ignores dropped/subscribed targets, and caps one source title at three', async () => {
    h.rows.push(
      [
        { franchiseId: 'bleach', status: 'completed', title: 'Bleach' },
        { franchiseId: 'dropped', status: 'dropped', title: 'Dropped Show' },
      ],
      [
        ...[1, 2, 3, 4].map((externalId) => ({
          franchiseId: 'bleach', targetFranchiseId: null, source: 'anilist', externalId,
          score: 100 - externalId, title: `Recommendation ${externalId}`, year: 2026,
          images: { portrait: null, landscape: null },
        })),
        {
          franchiseId: 'dropped', targetFranchiseId: null, source: 'anilist', externalId: 9,
          score: 999, title: 'Ignored dropped source', year: null,
          images: { portrait: null, landscape: null },
        },
        {
          franchiseId: 'bleach', targetFranchiseId: 'bleach', source: 'anilist', externalId: 10,
          score: 999, title: 'Already subscribed', year: null,
          images: { portrait: null, landscape: null },
        },
      ],
    )

    const items = await getDiscover('user', 20)

    expect(items).toHaveLength(3)
    expect(items[0]).toMatchObject({
      because: { franchiseId: 'bleach', title: 'Bleach' },
      reason: 'Because you completed Bleach',
      score: 124,
      title: { externalId: 1, franchiseId: null },
    })
    expect(items.map((item) => item.title.title)).not.toContain('Ignored dropped source')
    expect(items.map((item) => item.title.title)).not.toContain('Already subscribed')
  })
})
