import type { CommentView, PublicUser } from '../types/api.js'

// Wire views for the social layer. Pure: the comment queries (services/comments.ts) select a
// flat row, `commentRowFromDb` coerces what the driver hands back (ints can arrive as strings,
// booleans as 't'), and `toCommentView` shapes it for one viewer.

/** One comment as the thread query selects it, already coerced. */
export interface CommentRow {
  id: string
  subject: string
  body: string
  /** ms epoch. */
  createdAt: number
  parentId: string | null
  authorId: string
  authorHandle: string | null
  authorDisplayName: string | null
  /** The parent's author (null when there is no parent or the parent row is gone). */
  parentAuthorId: string | null
  parentAuthorHandle: string | null
  parentAuthorDisplayName: string | null
  /** The parent exists and is neither deleted, hidden nor written by someone blocked either way. */
  parentVisible: boolean
  likeCount: number
  liked: boolean
  replyCount: number
}

/**
 * A public face from profile columns: the handle is required (no handle, no public identity); a
 * missing display name falls back to the handle rather than to anything private.
 */
export function toPublicUser(id: string | null, handle: string | null, displayName: string | null): PublicUser | null {
  if (id == null || handle == null || handle === '') return null
  const name = displayName != null && displayName.trim() !== '' ? displayName : handle
  return { id, handle, displayName: name }
}

/**
 * The view of one comment for viewer `me`. `replyTo` names the parent's author only while the
 * parent is still visible to this viewer — a deleted, hidden or blocked parent leaves the reply
 * standing without saying whom it answered. `parentId` stays, so a client can still thread it.
 */
export function toCommentView(row: CommentRow, me: string): CommentView {
  const author = toPublicUser(row.authorId, row.authorHandle, row.authorDisplayName) ?? {
    // A comment is only ever written by someone with a handle, and the thread query inner-joins
    // the profile, so this is unreachable in practice; never leak an id-free author either way.
    id: row.authorId,
    handle: '',
    displayName: '',
  }
  const replyTo =
    row.parentId != null && row.parentVisible
      ? toPublicUser(row.parentAuthorId, row.parentAuthorHandle, row.parentAuthorDisplayName)
      : null
  return {
    id: row.id,
    subject: row.subject,
    author,
    body: row.body,
    createdAt: row.createdAt,
    parentId: row.parentId,
    replyTo,
    likeCount: row.likeCount,
    liked: row.liked,
    replyCount: row.replyCount,
    mine: row.authorId === me,
  }
}

function str(v: unknown): string | null {
  if (v == null) return null
  return typeof v === 'string' ? v : String(v)
}

function num(v: unknown): number {
  const n = typeof v === 'number' ? v : typeof v === 'string' ? Number(v) : typeof v === 'bigint' ? Number(v) : NaN
  return Number.isFinite(n) ? n : 0
}

function bool(v: unknown): boolean {
  return v === true || v === 't' || v === 'true' || v === 1
}

/** A timestamptz as ms epoch: a Date, an epoch number, or a Postgres/ISO timestamp string. */
function epochMs(v: unknown): number {
  if (v instanceof Date) return v.getTime()
  if (typeof v === 'number') return Math.floor(v)
  if (typeof v === 'string') {
    if (/^-?\d+(\.\d+)?$/.test(v)) return Math.floor(Number(v))
    // Postgres text form "2026-09-25 10:00:00.123456+00" → ISO.
    const iso = v.includes('T') ? v : v.replace(' ', 'T')
    const withZone = /[zZ]|[+-]\d{2}(:?\d{2})?$/.test(iso) ? iso.replace(/([+-]\d{2})$/, '$1:00') : `${iso}Z`
    const ms = Date.parse(withZone)
    return Number.isFinite(ms) ? ms : 0
  }
  return 0
}

/**
 * A raw row of the thread query (snake_case, as `db.execute` returns it) → `CommentRow`.
 * `created_ms` is preferred; `created_at` is read when only the timestamp was selected.
 */
export function commentRowFromDb(raw: Record<string, unknown>): CommentRow {
  return {
    id: str(raw.id) ?? '',
    subject: str(raw.subject) ?? '',
    body: str(raw.body) ?? '',
    createdAt: raw.created_ms != null ? epochMs(raw.created_ms) : epochMs(raw.created_at),
    parentId: str(raw.parent_id),
    authorId: str(raw.author_id) ?? '',
    authorHandle: str(raw.author_handle),
    authorDisplayName: str(raw.author_display_name),
    parentAuthorId: str(raw.parent_author_id),
    parentAuthorHandle: str(raw.parent_author_handle),
    parentAuthorDisplayName: str(raw.parent_author_display_name),
    parentVisible: bool(raw.parent_visible),
    likeCount: num(raw.like_count),
    liked: bool(raw.liked),
    replyCount: num(raw.reply_count),
  }
}
