import { describe, expect, it } from 'vitest'
import { commentRowFromDb, toCommentView, toPublicUser, type CommentRow } from './views.js'

const ME = '11111111-1111-4111-8111-111111111111'
const MIRA = '22222222-2222-4222-8222-222222222222'
const COMMENT = '33333333-3333-4333-8333-333333333333'
const PARENT = '44444444-4444-4444-8444-444444444444'
const SUBJECT = 'news:55555555-5555-4555-8555-555555555555'

function row(overrides: Partial<CommentRow> = {}): CommentRow {
  return {
    id: COMMENT,
    subject: SUBJECT,
    body: 'That PV looked incredible',
    createdAt: 1790330400000,
    parentId: null,
    authorId: MIRA,
    authorHandle: 'mira.k',
    authorDisplayName: 'Mira',
    parentAuthorId: null,
    parentAuthorHandle: null,
    parentAuthorDisplayName: null,
    parentVisible: false,
    likeCount: 4,
    liked: true,
    replyCount: 2,
    ...overrides,
  }
}

describe('toCommentView', () => {
  it('shapes a top-level comment for another viewer', () => {
    expect(toCommentView(row(), ME)).toEqual({
      id: COMMENT,
      subject: SUBJECT,
      author: { id: MIRA, handle: 'mira.k', displayName: 'Mira' },
      body: 'That PV looked incredible',
      createdAt: 1790330400000,
      parentId: null,
      replyTo: null,
      likeCount: 4,
      liked: true,
      replyCount: 2,
      mine: false,
    })
  })

  it('`mine` is the viewer being the author', () => {
    expect(toCommentView(row(), MIRA).mine).toBe(true)
    expect(toCommentView(row({ authorId: ME, authorHandle: 'dex', authorDisplayName: 'Dex' }), ME).mine).toBe(true)
  })

  it('names the parent author while the parent is visible', () => {
    const reply = row({
      parentId: PARENT,
      parentAuthorId: ME,
      parentAuthorHandle: 'dex',
      parentAuthorDisplayName: 'Dex',
      parentVisible: true,
    })
    expect(toCommentView(reply, ME).replyTo).toEqual({ id: ME, handle: 'dex', displayName: 'Dex' })
  })

  it('drops replyTo (and keeps parentId) when the parent is deleted, hidden or blocked', () => {
    const reply = row({
      parentId: PARENT,
      parentAuthorId: ME,
      parentAuthorHandle: 'dex',
      parentAuthorDisplayName: 'Dex',
      parentVisible: false,
    })
    const view = toCommentView(reply, ME)
    expect(view.replyTo).toBeNull()
    expect(view.parentId).toBe(PARENT)
  })

  it('drops replyTo when the parent row is gone (account erased → parent_id SET NULL)', () => {
    expect(toCommentView(row({ parentId: null, parentVisible: true }), ME).replyTo).toBeNull()
  })
})

describe('toPublicUser', () => {
  it('needs a handle; a missing display name falls back to it', () => {
    expect(toPublicUser(ME, null, 'Dex')).toBeNull()
    expect(toPublicUser(ME, '', 'Dex')).toBeNull()
    expect(toPublicUser(null, 'dex', 'Dex')).toBeNull()
    expect(toPublicUser(ME, 'dex', null)).toEqual({ id: ME, handle: 'dex', displayName: 'dex' })
    expect(toPublicUser(ME, 'dex', '  ')).toEqual({ id: ME, handle: 'dex', displayName: 'dex' })
  })
})

describe('commentRowFromDb', () => {
  it('coerces what the driver hands back', () => {
    const r = commentRowFromDb({
      id: COMMENT,
      subject: SUBJECT,
      body: 'hi',
      created_ms: 1790330400123.0,
      parent_id: PARENT,
      author_id: MIRA,
      author_handle: 'mira.k',
      author_display_name: 'Mira',
      parent_author_id: ME,
      parent_author_handle: 'dex',
      parent_author_display_name: 'Dex',
      parent_visible: 't',
      like_count: '12',
      liked: false,
      reply_count: 3,
    })
    expect(r).toEqual({
      id: COMMENT,
      subject: SUBJECT,
      body: 'hi',
      createdAt: 1790330400123,
      parentId: PARENT,
      authorId: MIRA,
      authorHandle: 'mira.k',
      authorDisplayName: 'Mira',
      parentAuthorId: ME,
      parentAuthorHandle: 'dex',
      parentAuthorDisplayName: 'Dex',
      parentVisible: true,
      likeCount: 12,
      liked: false,
      replyCount: 3,
    })
  })

  it('reads a timestamp when no epoch column was selected, and defaults the rest', () => {
    const r = commentRowFromDb({
      id: COMMENT,
      subject: SUBJECT,
      body: '',
      created_at: '2026-09-25 10:00:00.123456+00',
      author_id: MIRA,
    })
    expect(r.createdAt).toBe(Date.parse('2026-09-25T10:00:00.123Z'))
    expect(r.parentId).toBeNull()
    expect(r.parentVisible).toBe(false)
    expect(r.likeCount).toBe(0)
    expect(r.liked).toBe(false)
    expect(r.replyCount).toBe(0)
  })

  it('accepts a Date', () => {
    expect(commentRowFromDb({ created_at: new Date('2026-09-25T10:00:00Z') }).createdAt).toBe(
      Date.parse('2026-09-25T10:00:00Z'),
    )
  })
})
