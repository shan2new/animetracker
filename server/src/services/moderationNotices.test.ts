import { describe, expect, it } from 'vitest'
import {
  COMMENT_HIDDEN_KIND,
  REPORT_RESOLVED_KIND,
  commentHiddenNotices,
  reportResolvedNotices,
} from './moderationNotices.js'

// Both sides of a moderation decision are told (DSA Art. 16(5) and 17): the rows these pure
// builders produce are what services/comments.ts (auto-hide) and services/moderation.ts (hide,
// restore, dismiss, ban --hide-comments) insert. They point at no comment, subject or post — a
// hidden comment is nobody's to open — and `body` is a machine category the client words.

const FRANCHISE = '33333333-3333-4333-8333-333333333333'
const AUTHOR = '22222222-2222-4222-8222-222222222222'
const REPORTER = '11111111-1111-4111-8111-111111111111'

describe('commentHiddenNotices — the author learns their comment was hidden, and why', () => {
  it('one row per hidden comment, to its author, with the reason category as the body', () => {
    for (const reason of ['reports', 'operator'] as const) {
      const rows = commentHiddenNotices([{ authorId: AUTHOR, franchiseId: FRANCHISE, franchiseTitle: 'Frieren' }], reason)
      expect(rows).toEqual([
        { userId: AUTHOR, franchiseId: FRANCHISE, kind: COMMENT_HIDDEN_KIND, title: 'Frieren', body: reason },
      ])
    }
    expect(COMMENT_HIDDEN_KIND).toBe('comment_hidden')
  })

  it('carries no comment, subject, post or actor (nothing to open, nobody named)', () => {
    const [row] = commentHiddenNotices([{ authorId: AUTHOR, franchiseId: FRANCHISE, franchiseTitle: 'Frieren' }], 'reports')
    expect(row).not.toHaveProperty('commentId')
    expect(row).not.toHaveProperty('subject')
    expect(row).not.toHaveProperty('postId')
    expect(row).not.toHaveProperty('actorUserId')
  })

  it('nothing hidden, nothing sent', () => {
    expect(commentHiddenNotices([], 'operator')).toEqual([])
  })
})

describe('reportResolvedNotices — each reporter learns the decision', () => {
  it('one row per decided report, to its reporter, with the resolution as the body', () => {
    for (const resolution of ['hidden', 'dismissed'] as const) {
      const rows = reportResolvedNotices(
        [
          { reporterId: REPORTER, franchiseId: FRANCHISE, franchiseTitle: 'Frieren' },
          { reporterId: AUTHOR, franchiseId: FRANCHISE, franchiseTitle: 'Frieren' },
        ],
        resolution,
      )
      expect(rows.map((r) => [r.userId, r.kind, r.body])).toEqual([
        [REPORTER, REPORT_RESOLVED_KIND, resolution],
        [AUTHOR, REPORT_RESOLVED_KIND, resolution],
      ])
    }
    expect(REPORT_RESOLVED_KIND).toBe('report_resolved')
  })
})
