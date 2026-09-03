import Fastify, { type FastifyReply, type FastifyRequest } from 'fastify'
import { getTableConfig } from 'drizzle-orm/pg-core'
import { getTableColumns, getTableName, is } from 'drizzle-orm'
import { PgTable } from 'drizzle-orm/pg-core'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import * as schema from '../db/schema.js'

// `DELETE /me` — App Store guideline 5.1.1(v). Two independent things are asserted here, because
// each of them can be true while the other is false:
//
//   1. the ROUTE erases every user-owned table and the user row, in one transaction, scoped to the
//      caller — no DB needed, the transaction is recorded through a fake;
//   2. the SCHEMA still cascades from `users`, and the route's list still covers every table that
//      stores rows for one user — so adding a user-owned table later fails this test instead of
//      quietly surviving a "delete my account".
//
// The `db` module is mocked before `./me.js` is imported, which keeps `src/env.ts` (and therefore a
// DATABASE_URL) out of the test entirely, matching the no-DB, no-network rule the suite follows.

const recorded = vi.hoisted(() => ({
  deletes: [] as { table: string; where: unknown }[],
  transactions: 0,
})) as { deletes: { table: string; where: unknown }[]; transactions: number }

vi.mock('../db/index.js', () => {
  const tx = {
    delete(table: unknown) {
      const row = { table: getTableName(table as never), where: undefined as unknown }
      recorded.deletes.push(row)
      return {
        where(condition: unknown) {
          row.where = condition
          return Promise.resolve([])
        },
      }
    },
  }
  return {
    db: {
      ...tx,
      async transaction<T>(fn: (t: typeof tx) => Promise<T>): Promise<T> {
        recorded.transactions += 1
        return fn(tx)
      },
      // `GET /me/library` is registered in the same plugin; it is never called here, but the
      // module has to expose enough shape for the import to succeed.
      select: () => ({ from: () => ({ where: () => ({ limit: async () => [] }) }) }),
    },
    sql: {},
    schema,
  }
})

vi.mock('../services/animeVideoFallback.js', () => ({ enqueueAnimeVideoFallback: vi.fn() }))

const { meRoutes, accountOwnedTableNames } = await import('./me.js')

const CALLER = '11111111-1111-1111-1111-111111111111'

/** The plugin under test, with `authenticate` stubbed to attach one known user. */
async function appWithUser(userId: string | null = CALLER) {
  const app = Fastify()
  app.decorate('authenticate', async (req: FastifyRequest, reply: FastifyReply) => {
    if (!userId) return reply.code(401).send({ error: 'unauthorized' })
    req.user = { id: userId, clerkId: 'user_test' }
  })
  await app.register(meRoutes)
  await app.ready()
  return app
}

beforeEach(() => {
  recorded.deletes.length = 0
  recorded.transactions = 0
})

describe('DELETE /me — the account is erased, not deactivated', () => {
  it('deletes every user-owned table and the user row, inside one transaction', async () => {
    const app = await appWithUser()
    const res = await app.inject({ method: 'DELETE', url: '/me' })

    expect(res.statusCode).toBe(200)
    expect(res.json()).toEqual({ deleted: true })
    expect(recorded.transactions).toBe(1)
    expect(recorded.deletes.map((d) => d.table)).toEqual([...accountOwnedTableNames, 'users'])
    // Every delete is scoped — a missing `where` would erase the table for every account.
    expect(recorded.deletes.every((d) => d.where !== undefined)).toBe(true)
    await app.close()
  })

  it('deletes the user row LAST, so it never depends on a cascade to succeed', async () => {
    const app = await appWithUser()
    await app.inject({ method: 'DELETE', url: '/me' })
    expect(recorded.deletes.at(-1)?.table).toBe('users')
    await app.close()
  })

  it('refuses an unauthenticated caller and touches nothing', async () => {
    const app = await appWithUser(null)
    const res = await app.inject({ method: 'DELETE', url: '/me' })
    expect(res.statusCode).toBe(401)
    expect(recorded.deletes).toEqual([])
    await app.close()
  })

  it('rejects a body it does not understand rather than deleting anyway', async () => {
    const app = await appWithUser()
    const res = await app.inject({ method: 'DELETE', url: '/me', payload: { userId: 'someone-else' } })
    expect(res.statusCode).toBe(400)
    expect(recorded.deletes).toEqual([])
    await app.close()
  })
})

describe('the schema keeps the deletion complete', () => {
  /** Every declared table that stores rows belonging to one user. */
  // `Object.values` over the schema module yields tables AND `relations()` helpers; the `unknown[]`
  // step is what lets the `is(v, PgTable)` guard narrow that heterogeneous union.
  const userOwned = (Object.values(schema) as unknown[])
    .filter((v): v is PgTable => is(v, PgTable))
    .filter((t) => 'userId' in getTableColumns(t))

  it('lists every user-owned table in the route, so a new one cannot be forgotten', () => {
    expect(new Set(userOwned.map((t) => getTableName(t)))).toEqual(new Set(accountOwnedTableNames))
  })

  it('cascades from users on every user-owned table, so no row can outlive the account', () => {
    for (const table of userOwned) {
      const fk = getTableConfig(table)
        .foreignKeys.map((f) => f.reference())
        .find((r) => getTableName(r.foreignTable) === 'users')
      expect(fk, `${getTableName(table)} has no foreign key to users`).toBeDefined()
      expect(getTableConfig(table).foreignKeys.some((f) => f.onDelete === 'cascade')).toBe(true)
    }
  })
})
