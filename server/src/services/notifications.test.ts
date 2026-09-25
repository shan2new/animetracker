import { describe, expect, it, vi } from 'vitest'
import { decodeCursor } from '../util/cursor.js'

vi.mock('../db/index.js', () => ({ db: {}, sql: {} }))

const { toNotificationItem, toNotificationsPage, EXCERPT_CODE_POINTS } = await import('./notifications.js')
type Row = import('./notifications.js').NotificationRow

const MIRA = '22222222-2222-4222-8222-222222222222'
const FRANCHISE = '33333333-3333-4333-8333-333333333333'
const ANNOUNCEMENT = '44444444-4444-4444-8444-444444444444'
const COMMENT = '55555555-5555-4555-8555-555555555555'
const CREATED = new Date('2026-09-25T10:00:00.123Z')

function newsRow(over: Partial<Row> = {}): Row {
  return {
    id: '66666666-6666-4666-8666-666666666666',
    franchiseId: FRANCHISE,
    kind: 'news_announced',
    title: 'Sakamoto Days',
    body: 'Season 2 announced — release TBA',
    createdAt: CREATED,
    readAt: null,
    actorUserId: null,
    actorCount: 0,
    subject: null,
    postId: `news:${ANNOUNCEMENT}`,
    commentId: null,
    actorHandle: null,
    actorDisplayName: null,
    commentBody: null,
    commentDeletedAt: null,
    commentHiddenAt: null,
    cursorAt: '2026-09-25T10:00:00.123456Z',
    ...over,
  }
}

function replyRow(over: Partial<Row> = {}): Row {
  return newsRow({
    id: '77777777-7777-4777-8777-777777777777',
    kind: 'reply',
    body: '',
    actorUserId: MIRA,
    actorCount: 1,
    subject: `news:${ANNOUNCEMENT}`,
    postId: `news:${ANNOUNCEMENT}`,
    commentId: COMMENT,
    actorHandle: 'mira.k',
    actorDisplayName: 'Mira',
    commentBody: 'Finally!',
    ...over,
  })
}

describe('toNotificationItem', () => {
  it('sends a news row with no actor, a zero actor count and no excerpt', () => {
    const readAt = new Date('2026-09-25T11:00:00.000Z')
    expect(toNotificationItem(newsRow({ readAt }))).toEqual({
      id: '66666666-6666-4666-8666-666666666666',
      franchiseId: FRANCHISE,
      kind: 'news_announced',
      title: 'Sakamoto Days',
      body: 'Season 2 announced — release TBA',
      createdAt: CREATED.getTime(),
      readAt: readAt.getTime(),
      actor: null,
      actorCount: 0,
      subject: null,
      postId: `news:${ANNOUNCEMENT}`,
      commentId: null,
      excerpt: null,
      news: null, // no announcement joined: the client falls back to `body`
    })
  })

  it('carries a news row as structured facts, read live from its announcement', () => {
    const item = toNotificationItem(
      newsRow({
        kind: 'news_dated',
        body: 'Season 2 arrives 2026-11-20',
        newsStatus: 'upcoming_dated',
        newsNext: 'Season 2',
        newsRelease: '2026-11-20',
      }),
    )
    expect(item.news).toEqual({
      status: 'upcoming_dated',
      installment: 'Season 2',
      isMovie: false,
      release: '2026-11-20',
      releaseWindow: { date: '2026-11-20', precision: 'day', sortKey: 20261120 },
    })
  })

  it('names a movie like the feed does and resolves a prose window', () => {
    const item = toNotificationItem(
      newsRow({ newsStatus: 'announced', newsNext: 'Infinity Castle - Part 2 (movie)', newsRelease: 'Summer 2027' }),
    )
    expect(item.news).toEqual({
      status: 'announced',
      installment: 'Infinity Castle - Part 2',
      isMovie: true,
      release: 'Summer 2027',
      releaseWindow: { date: '2027-07', precision: 'quarter', sortKey: 20270701 },
    })
  })

  it("gives a rumour no window, whatever date it names (the feed's rule)", () => {
    const item = toNotificationItem(
      newsRow({ kind: 'news_rumored', newsStatus: 'rumored', newsNext: 'Season 3', newsRelease: '2027' }),
    )
    expect(item.news?.releaseWindow).toEqual({ date: null, precision: 'unknown', sortKey: null })
    expect(item.news?.release).toBe('2027')
  })

  it('has no news facts on a social row or a news row whose announcement is gone', () => {
    const joined = { newsStatus: 'announced', newsNext: 'Season 2', newsRelease: 'TBA' }
    expect(toNotificationItem(replyRow(joined)).news).toBeNull()
    expect(toNotificationItem(newsRow({ newsStatus: null, newsNext: null, newsRelease: null })).news).toBeNull()
    expect(toNotificationItem(newsRow({ ...joined, newsNext: '  ' })).news).toBeNull()
  })

  // Research reads arbitrary pages: its words reach Activity only on the feed composer's terms.
  it('prints no research text that carries a link — name, release or fallback body', () => {
    const dirtyName = toNotificationItem(
      newsRow({
        body: 'Season 2 at animefan.io/s2 announced — date TBA',
        newsStatus: 'announced_no_date',
        newsNext: 'Season 2 at animefan.io/s2',
        newsRelease: 'TBA',
      }),
    )
    expect(dirtyName.news).toBeNull()
    expect(dirtyName.body).toBe('')

    // A window that cannot be printed is no window (the composer words it as announced)…
    const dirtyWindow = toNotificationItem(
      newsRow({ newsStatus: 'announced', newsNext: 'Season 2', newsRelease: 'Fall 2026 via bit.ly/abc' }),
    )
    expect(dirtyWindow.news).toMatchObject({ installment: 'Season 2', release: '' })
    expect(dirtyWindow.news?.releaseWindow).toEqual({ date: null, precision: 'unknown', sortKey: null })

    // …but a day-precise date is a structured fact, and survives the prose it came in.
    const dirtyDay = toNotificationItem(
      newsRow({
        kind: 'news_dated',
        newsStatus: 'upcoming_dated',
        newsNext: 'Season 2',
        newsRelease: 'November 20, 2026 — tickets at animefan.io/s2',
      }),
    )
    expect(dirtyDay.news?.release).toBe('')
    expect(dirtyDay.news?.releaseWindow).toEqual({ date: '2026-11-20', precision: 'day', sortKey: 20261120 })
  })

  it('keeps a clean fallback body, and never touches a social row', () => {
    expect(toNotificationItem(newsRow()).body).toBe('Season 2 announced — release TBA')
    expect(toNotificationItem(replyRow()).body).toBe('')
  })

  it('sends a reply row with its actor, the thread, and the reply as the excerpt', () => {
    const item = toNotificationItem(replyRow())
    expect(item.actor).toEqual({ id: MIRA, handle: 'mira.k', displayName: 'Mira' })
    expect(item.actorCount).toBe(1)
    expect(item.subject).toBe(`news:${ANNOUNCEMENT}`)
    expect(item.commentId).toBe(COMMENT)
    expect(item.excerpt).toBe('Finally!')
    expect(item.readAt).toBeNull()
  })

  it('truncates the excerpt to 140 code points, never splitting an emoji', () => {
    expect(EXCERPT_CODE_POINTS).toBe(140)
    // 150 astral code points (300 UTF-16 units): a slice by .length would cut one in half.
    const body = '🔥'.repeat(150)
    const excerpt = toNotificationItem(replyRow({ commentBody: body })).excerpt!
    expect([...excerpt]).toHaveLength(140)
    expect(excerpt).toBe('🔥'.repeat(140))
    // Short bodies come through whole.
    expect(toNotificationItem(replyRow({ commentBody: 'a'.repeat(140) })).excerpt).toBe('a'.repeat(140))
  })

  it('sends a like row with the newest liker and the folded count, excerpting YOUR comment', () => {
    const item = toNotificationItem(
      replyRow({ kind: 'like_comment', actorCount: 42, commentBody: 'My take on episode 12' }),
    )
    expect(item.kind).toBe('like_comment')
    expect(item.actor).toEqual({ id: MIRA, handle: 'mira.k', displayName: 'Mira' })
    expect(item.actorCount).toBe(42)
    expect(item.excerpt).toBe('My take on episode 12')
  })

  it('sends a liker without a public profile as a null actor, keeping the count', () => {
    const item = toNotificationItem(
      replyRow({ kind: 'like_comment', actorCount: 3, actorHandle: null, actorDisplayName: null }),
    )
    expect(item.actor).toBeNull()
    expect(item.actorCount).toBe(3)
  })

  it('has no excerpt once the comment is deleted or hidden', () => {
    const deletedAt = new Date('2026-09-25T10:30:00.000Z')
    expect(toNotificationItem(replyRow({ commentBody: '', commentDeletedAt: deletedAt })).excerpt).toBeNull()
    expect(toNotificationItem(replyRow({ commentHiddenAt: deletedAt })).excerpt).toBeNull()
    // The comment row itself is gone (the left join found nothing).
    expect(toNotificationItem(replyRow({ commentBody: null })).excerpt).toBeNull()
  })

  it('passes an unknown kind through for the client to render leniently', () => {
    expect(toNotificationItem(newsRow({ kind: 'something_new' })).kind).toBe('something_new')
  })

  it('sends a moderation notice as a row that opens nothing, its category in `body`', () => {
    for (const [kind, body] of [
      ['comment_hidden', 'reports'],
      ['comment_hidden', 'operator'],
      ['report_resolved', 'hidden'],
      ['report_resolved', 'dismissed'],
    ] as const) {
      const item = toNotificationItem(newsRow({ kind, body, title: 'Frieren', postId: null }))
      expect(item).toMatchObject({
        kind,
        body,
        title: 'Frieren',
        actor: null,
        actorCount: 0,
        subject: null,
        postId: null,
        commentId: null,
        excerpt: null,
        news: null,
      })
    }
  })
})

describe('toNotificationsPage', () => {
  const rows = [0, 1, 2].map((i) =>
    newsRow({
      id: `8888888${i}-8888-4888-8888-888888888888`,
      cursorAt: `2026-09-25T10:00:0${i}.000001Z`,
    }),
  )

  it('shows `limit` rows and points the cursor at the last one shown when there is more', () => {
    const page = toNotificationsPage(rows, 2, 5)
    expect(page.items.map((i) => i.id)).toEqual([rows[0]!.id, rows[1]!.id])
    expect(page.unread).toBe(5)
    expect(decodeCursor(page.nextCursor!)).toEqual({ at: rows[1]!.cursorAt, id: rows[1]!.id })
  })

  it('has no cursor on the last page', () => {
    expect(toNotificationsPage(rows, 3, 0).nextCursor).toBeNull()
    expect(toNotificationsPage([], 50, 0)).toEqual({ items: [], unread: 0, nextCursor: null })
  })
})

// A reply in an episode room prints its text only while the room is open to the recipient NOW: a
// `reset` re-locks rooms, and Activity must not keep showing the spoiler (services/episodeGate.ts).
describe('excerpts from episode rooms follow the spoiler gate', async () => {
  const { episodeRoomMediaIds } = await import('./notifications.js')
  const room = replyRow({ subject: 'ep:154587:12', postId: null, commentBody: 'That ending!' })

  it('shows the excerpt only while the room is open', () => {
    expect(toNotificationItem(room, () => true).excerpt).toBe('That ending!')
    expect(toNotificationItem(room, () => false).excerpt).toBeNull()
  })

  it('fails closed without a gate, and asks the gate about the right room', () => {
    expect(toNotificationItem(room).excerpt).toBeNull()
    const asked: [number, number][] = []
    toNotificationItem(room, (mediaId, episode) => (asked.push([mediaId, episode]), true))
    expect(asked).toEqual([[154587, 12]])
  })

  it('leaves post threads alone, and gates every row of a page', () => {
    expect(toNotificationItem(replyRow(), () => false).excerpt).toBe('Finally!')
    const page = toNotificationsPage([room, replyRow()], 50, 0, () => false)
    expect(page.items.map((i) => i.excerpt)).toEqual([null, 'Finally!'])
  })

  it('collects each room media id once, for one batched gate query', () => {
    expect(
      episodeRoomMediaIds([
        room,
        replyRow({ subject: 'ep:154587:13' }),
        replyRow({ subject: 'ep:99:1' }),
        replyRow(),
        newsRow(),
        replyRow({ subject: 'ep:7:1', commentId: null }),
      ]),
    ).toEqual([154587, 99])
  })
})
