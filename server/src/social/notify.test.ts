import { PgDialect } from 'drizzle-orm/pg-core'
import type { SQL } from 'drizzle-orm'
import { describe, expect, it } from 'vitest'
import { blocks, notifications } from '../db/schema.js'
import type { Executor } from './blocks.js'
import { likeNotificationAction, notifyCommentLike, notifyReply, replyRecipient } from './notify.js'

const ME = '11111111-1111-4111-8111-111111111111'
const MIRA = '22222222-2222-4222-8222-222222222222'
const FRANCHISE = '33333333-3333-4333-8333-333333333333'
const COMMENT = '44444444-4444-4444-8444-444444444444'
const NEWS = 'news:55555555-5555-4555-8555-555555555555'
const NOW = Date.parse('2026-09-25T12:00:00Z')
const HOUR = 3_600_000

describe('replyRecipient', () => {
  const base = { parentAuthorId: MIRA, replierId: ME, parentVisible: true, blocked: false }

  it('notifies the parent author', () => {
    expect(replyRecipient(base)).toBe(MIRA)
  })

  it('never notifies yourself', () => {
    expect(replyRecipient({ ...base, parentAuthorId: ME })).toBeNull()
  })

  it('stays quiet when either side blocked the other', () => {
    expect(replyRecipient({ ...base, blocked: true })).toBeNull()
  })

  it('stays quiet when the parent is gone or no longer visible', () => {
    expect(replyRecipient({ ...base, parentAuthorId: null })).toBeNull()
    expect(replyRecipient({ ...base, parentVisible: false })).toBeNull()
  })
})

describe('likeNotificationAction', () => {
  const base = {
    likerId: ME,
    authorId: MIRA,
    blocked: false,
    unreadExists: false,
    lastCreatedAt: null,
    nowMs: NOW,
    cooldownMs: HOUR,
  }

  it('skips a self-like', () => {
    expect(likeNotificationAction({ ...base, likerId: MIRA })).toBe('skip')
    expect(likeNotificationAction({ ...base, likerId: MIRA, unreadExists: true })).toBe('skip')
  })

  it('skips when blocked, even with an unread row to fold into', () => {
    expect(likeNotificationAction({ ...base, blocked: true })).toBe('skip')
    expect(likeNotificationAction({ ...base, blocked: true, unreadExists: true })).toBe('skip')
  })

  it('aggregates into the unread row, whatever the cooldown says', () => {
    expect(likeNotificationAction({ ...base, unreadExists: true, lastCreatedAt: NOW - 1000 })).toBe('aggregate')
  })

  it('skips inside the cooldown once the last row was read', () => {
    expect(likeNotificationAction({ ...base, lastCreatedAt: NOW - HOUR + 1 })).toBe('skip')
  })

  it('inserts once the cooldown has passed, or when there never was a row', () => {
    expect(likeNotificationAction({ ...base, lastCreatedAt: NOW - HOUR })).toBe('insert')
    expect(likeNotificationAction({ ...base, lastCreatedAt: NOW - 5 * HOUR })).toBe('insert')
    expect(likeNotificationAction(base)).toBe('insert')
  })

  it('a zero cooldown never skips a read row', () => {
    expect(likeNotificationAction({ ...base, cooldownMs: 0, lastCreatedAt: NOW })).toBe('insert')
  })
})

// A recording stand-in for the executor: selects answer from `state`, inserts are captured.
function fakeExec(state: { unread: boolean; lastMs: number | null; blocked: boolean }) {
  const inserts: { table: unknown; values: Record<string, unknown>; conflict: Record<string, unknown> | null }[] = []
  let reads = 0
  const exec = {
    select: () => ({
      from: (table: unknown) => ({
        where: () => {
          reads++
          const rows = table === blocks ? (state.blocked ? [{ one: 1 }] : []) : [{ unread: state.unread, lastMs: state.lastMs }]
          return Object.assign(Promise.resolve(rows), { limit: () => Promise.resolve(rows) })
        },
      }),
    }),
    insert: (table: unknown) => ({
      values: (values: Record<string, unknown>) => {
        const record = { table, values, conflict: null as Record<string, unknown> | null }
        inserts.push(record)
        return Object.assign(Promise.resolve(), {
          onConflictDoUpdate: (config: Record<string, unknown>) => {
            record.conflict = config
            return Promise.resolve()
          },
        })
      },
    }),
  }
  return { exec: exec as unknown as Executor, inserts, reads: () => reads }
}

describe('notifyReply', () => {
  it('writes one reply row: the actor, one actor, the thread, the post and the reply', async () => {
    const f = fakeExec({ unread: false, lastMs: null, blocked: false })
    await notifyReply(f.exec, {
      recipientId: MIRA,
      actorId: ME,
      franchiseId: FRANCHISE,
      franchiseTitle: 'Sakamoto Days',
      subject: NEWS,
      commentId: COMMENT,
    })
    expect(f.inserts).toHaveLength(1)
    expect(f.inserts[0]!.table).toBe(notifications)
    expect(f.inserts[0]!.values).toEqual({
      userId: MIRA,
      franchiseId: FRANCHISE,
      kind: 'reply',
      title: 'Sakamoto Days',
      body: '',
      actorUserId: ME,
      actorCount: 1,
      subject: NEWS,
      postId: NEWS,
      commentId: COMMENT,
    })
  })

  it('an episode room is a thread but not a post', async () => {
    const f = fakeExec({ unread: false, lastMs: null, blocked: false })
    await notifyReply(f.exec, {
      recipientId: MIRA,
      actorId: ME,
      franchiseId: FRANCHISE,
      franchiseTitle: 'Frieren',
      subject: 'ep:154587:12',
      commentId: COMMENT,
    })
    expect(f.inserts[0]!.values.subject).toBe('ep:154587:12')
    expect(f.inserts[0]!.values.postId).toBeNull()
  })
})

describe('notifyCommentLike', () => {
  const input = {
    authorId: MIRA,
    likerId: ME,
    commentId: COMMENT,
    subject: NEWS,
    franchiseId: FRANCHISE,
    franchiseTitle: 'Sakamoto Days',
    nowMs: NOW,
    cooldownMs: HOUR,
  }

  it('inserts through the upsert on the one-unread-row index', async () => {
    const f = fakeExec({ unread: false, lastMs: null, blocked: false })
    expect(await notifyCommentLike(f.exec, input)).toBe('insert')
    expect(f.inserts).toHaveLength(1)
    const { values, conflict } = f.inserts[0]!
    expect(values).toMatchObject({
      userId: MIRA,
      franchiseId: FRANCHISE,
      kind: 'like_comment',
      title: 'Sakamoto Days',
      body: '',
      actorUserId: ME,
      actorCount: 1,
      subject: NEWS,
      postId: NEWS,
      commentId: COMMENT,
    })
    expect(conflict!.target).toEqual([notifications.userId, notifications.commentId])
    const dialect = new PgDialect()
    expect(dialect.sqlToQuery(conflict!.targetWhere as SQL).sql).toBe("kind = 'like_comment' and read_at is null")
    const set = conflict!.set as Record<string, SQL>
    expect(dialect.sqlToQuery(set.actorCount!).sql).toBe('"notifications"."actor_count" + 1')
    expect(dialect.sqlToQuery(set.actorUserId!).sql).toBe('excluded.actor_user_id')
  })

  it('aggregates with the same statement when an unread row exists', async () => {
    const f = fakeExec({ unread: true, lastMs: NOW - 60_000, blocked: false })
    expect(await notifyCommentLike(f.exec, input)).toBe('aggregate')
    expect(f.inserts).toHaveLength(1)
    expect(f.inserts[0]!.conflict).not.toBeNull()
  })

  it('writes nothing inside the cooldown', async () => {
    const f = fakeExec({ unread: false, lastMs: NOW - 10 * 60_000, blocked: false })
    expect(await notifyCommentLike(f.exec, input)).toBe('skip')
    expect(f.inserts).toHaveLength(0)
  })

  it('writes nothing when either side blocked the other', async () => {
    const f = fakeExec({ unread: true, lastMs: null, blocked: true })
    expect(await notifyCommentLike(f.exec, input)).toBe('skip')
    expect(f.inserts).toHaveLength(0)
  })

  it('a self-like reads nothing and writes nothing', async () => {
    const f = fakeExec({ unread: false, lastMs: null, blocked: false })
    expect(await notifyCommentLike(f.exec, { ...input, likerId: MIRA })).toBe('skip')
    expect(f.reads()).toBe(0)
    expect(f.inserts).toHaveLength(0)
  })
})
