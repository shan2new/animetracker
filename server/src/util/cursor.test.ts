import { PgDialect } from 'drizzle-orm/pg-core'
import { sql } from 'drizzle-orm'
import { describe, expect, it } from 'vitest'
import { comments } from '../db/schema.js'
import { cursorAt, decodeCursor, encodeCursor, type KeysetCursor } from './cursor.js'

const ID = '11111111-1111-4111-8111-111111111111'
const AT = '2026-09-25T10:00:00.123456Z'
const enc = (v: unknown) => Buffer.from(JSON.stringify(v), 'utf8').toString('base64url')

describe('encodeCursor / decodeCursor', () => {
  it('round-trips with and without a rank', () => {
    const plain: KeysetCursor = { at: AT, id: ID }
    const ranked: KeysetCursor = { at: AT, id: ID, rank: 41 }
    expect(decodeCursor(encodeCursor(plain))).toEqual(plain)
    expect(decodeCursor(encodeCursor(ranked))).toEqual(ranked)
    expect(decodeCursor(encodeCursor({ at: AT, id: ID, rank: 0 }))).toEqual({ at: AT, id: ID, rank: 0 })
  })

  it('is url-safe and opaque', () => {
    expect(encodeCursor({ at: AT, id: ID, rank: 3 })).toMatch(/^[A-Za-z0-9_-]+$/)
  })

  it.each([
    ['bad base64', '!!!not-base64!!!'],
    ['base64 with padding / foreign characters', `${enc({ at: AT, id: ID })}==`],
    ['bad JSON', Buffer.from('{"at":', 'utf8').toString('base64url')],
    ['a JSON array', enc([AT, ID])],
    ['missing microseconds', enc({ at: '2026-09-25T10:00:00.123Z', id: ID })],
    ['no fraction at all', enc({ at: '2026-09-25T10:00:00Z', id: ID })],
    ['a non-UTC offset', enc({ at: '2026-09-25T10:00:00.123456+05:30', id: ID })],
    ['an impossible date', enc({ at: '2026-02-30T10:00:00.123456Z', id: ID })],
    ['an impossible hour', enc({ at: '2026-09-25T25:00:00.123456Z', id: ID })],
    ['a non-uuid id', enc({ at: AT, id: 'abc' })],
    ['a negative rank', enc({ at: AT, id: ID, rank: -1 })],
    ['a fractional rank', enc({ at: AT, id: ID, rank: 1.5 })],
    ['an extra field', enc({ at: AT, id: ID, o: 3 })],
    ['the empty string', ''],
    ['an over-long string', 'A'.repeat(401)],
  ])('rejects %s', (_label, raw) => {
    expect(decodeCursor(raw)).toBeNull()
  })
})

describe('cursorAt', () => {
  it('selects the column as UTC ISO with microseconds', () => {
    const q = new PgDialect().sqlToQuery(sql`select ${cursorAt(comments.createdAt)}`)
    expect(q.sql).toBe(`select to_char("comments"."created_at" at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')`)
  })
})
