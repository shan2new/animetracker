import { sql } from 'drizzle-orm'
import { PgDialect } from 'drizzle-orm/pg-core'
import { describe, expect, it } from 'vitest'
import { comments } from '../db/schema.js'
import { blockedEitherWay, blockPairKey, notBlockedEitherWaySql } from './blocks.js'

const A = '11111111-1111-4111-8111-111111111111'
const B = '22222222-2222-4222-8222-222222222222'
const C = '33333333-3333-4333-8333-333333333333'

describe('blockedEitherWay', () => {
  it('is true when a blocked b', () => {
    const pairs = new Set([blockPairKey(A, B)])
    expect(blockedEitherWay(A, B, pairs)).toBe(true)
  })

  it('is true when b blocked a (the other direction)', () => {
    const pairs = new Set([blockPairKey(B, A)])
    expect(blockedEitherWay(A, B, pairs)).toBe(true)
    expect(blockedEitherWay(B, A, pairs)).toBe(true)
  })

  it('is false for strangers and for blocks between other people', () => {
    expect(blockedEitherWay(A, B, new Set())).toBe(false)
    expect(blockedEitherWay(A, B, new Set([blockPairKey(A, C), blockPairKey(C, B)]))).toBe(false)
  })

  it('keys are "<blocker>:<blocked>"', () => {
    expect(blockPairKey(A, B)).toBe(`${A}:${B}`)
  })
})

describe('notBlockedEitherWaySql', () => {
  const dialect = new PgDialect()

  it('excludes authors the viewer blocked AND authors who blocked the viewer', () => {
    const q = dialect.sqlToQuery(notBlockedEitherWaySql(A, comments.userId))
    expect(q.sql).toBe(
      '("comments"."user_id" not in (select "blocks"."blocked_user_id" from "blocks" where "blocks"."user_id" = $1)' +
        ' and "comments"."user_id" not in (select "blocks"."user_id" from "blocks" where "blocks"."blocked_user_id" = $2))',
    )
    expect(q.params).toEqual([A, A])
  })

  it('accepts a raw alias inside a hand-written query', () => {
    const q = dialect.sqlToQuery(notBlockedEitherWaySql(B, sql`c.user_id`))
    expect(q.sql.startsWith('(c.user_id not in (select')).toBe(true)
    expect(q.sql).toContain('and c.user_id not in (select "blocks"."user_id"')
    expect(q.params).toEqual([B, B])
  })
})
