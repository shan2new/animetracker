import { and, eq, gt, inArray, sql } from 'drizzle-orm'
import { db } from '../db/index.js'
import { franchise, franchiseMember, media, progress, subscriptions, users } from '../db/schema.js'
import type { EpisodeMeta, FranchiseProgressCommandResponse, WatchStatus } from '../types/api.js'
import { airedCount, caughtUpValue, clampProgressValue, type AiredInput } from './aired.js'

/** Subscribe to a franchise. Defaults status to `watching` if any part is releasing, else `planned`. */
export async function subscribe(userId: string, franchiseId: string, status?: WatchStatus): Promise<void> {
  let resolved = status
  if (!resolved) {
    const members = await db
      .select({ mediaId: franchiseMember.mediaId })
      .from(franchiseMember)
      .where(eq(franchiseMember.franchiseId, franchiseId))
    const ids = members.map((m) => m.mediaId)
    const releasing = ids.length
      ? await db.select({ id: media.id }).from(media).where(and(inArray(media.id, ids), eq(media.status, 'RELEASING')))
      : []
    resolved = releasing.length > 0 ? 'watching' : 'planned'
  }
  await db
    .insert(subscriptions)
    .values({ userId, franchiseId, status: resolved })
    .onConflictDoUpdate({ target: [subscriptions.userId, subscriptions.franchiseId], set: { status: resolved } })
}

export async function setSubscriptionStatus(userId: string, franchiseId: string, status: WatchStatus): Promise<void> {
  await db
    .update(subscriptions)
    .set({ status })
    .where(and(eq(subscriptions.userId, userId), eq(subscriptions.franchiseId, franchiseId)))
}

export async function unsubscribe(userId: string, franchiseId: string): Promise<void> {
  await db
    .delete(subscriptions)
    .where(and(eq(subscriptions.userId, userId), eq(subscriptions.franchiseId, franchiseId)))
}

export type SetProgressResult = { ok: true; episodes: number } | { ok: false; reason: 'media_not_found' }

/**
 * Store one part's watched count, clamped by `clampProgressValue` (services/aired.ts):
 *
 * - a NOT_YET_RELEASED part takes 0 — a season that has not premiered cannot have been watched;
 * - a RELEASING part takes at most what has AIRED by now (a slot that struck counts before the
 *   hourly sync advances `next`). The old ceiling was the season's size, `max(episodes, aired)`,
 *   which let a 12-episode season with 5 aired be marked to 12 — and that mark then opened
 *   episode rooms for episodes nobody could have seen;
 * - anything else takes at most its size, `max(episodes, aired)`. Unsized stays unbounded.
 *
 * The ceiling bounds only an INCREASE: the stored count stays reachable, so a mark written before
 * the aired ceiling existed (12 of a season with 5 aired) is never pulled down by the next write —
 * unmarking 12 → 11 stores 11, not 5 ("a progress mark never rolls back").
 *
 * Belt-and-braces against any client with an unbounded "+1" control: one such control walked a
 * 10-episode season up to 59 watched, and a bad value written once stays wrong until something
 * overwrites it. The client must bound itself to a number no higher (`FranchisePart.progressCeiling`
 * = its aired-by-now count for a releasing part, which never exceeds the server's), or the server
 * cuts a mark the client showed.
 *
 * An unknown `mediaId` writes NOTHING and says so (the route answers 404 `media not found`, which is
 * final): it used to be written unclamped, a row no read would ever surface.
 */
export async function setProgress(userId: string, mediaId: number, episodes: number): Promise<SetProgressResult> {
  const [row] = await db
    .select({
      source: media.source,
      status: media.status,
      episodes: media.episodes,
      next: media.nextAiringEpisode,
      episodesList: media.episodesList,
      watched: progress.episodesWatched,
    })
    .from(media)
    .leftJoin(progress, and(eq(progress.mediaId, media.id), eq(progress.userId, userId)))
    .where(eq(media.id, mediaId))
    .limit(1)
  if (!row) return { ok: false, reason: 'media_not_found' }
  const clamped = clampProgressValue(toAiredInput(row), episodes, Date.now(), row.watched ?? 0)
  const now = new Date()
  await db
    .insert(progress)
    .values({ userId, mediaId, episodesWatched: clamped, updatedAt: now })
    .onConflictDoUpdate({
      target: [progress.userId, progress.mediaId],
      set: { episodesWatched: clamped, updatedAt: now },
    })
  return { ok: true, episodes: clamped }
}

export interface ProgressMediaRow {
  mediaId: number
  /** media.source ('anilist' | 'tmdb'): a TMDB slot is date-only, which moves when it counts as aired. */
  source: string
  status: string | null
  episodes: number | null
  next: { episode: number; airingAt: number } | null
  episodesList: EpisodeMeta[] | null
  /** The caller's stored count for the part (null / absent = none): a write never pulls it down. */
  watched?: number | null
}

/** A media select's nullable jsonb columns as the aired rule's input. */
function toAiredInput(row: Omit<ProgressMediaRow, 'mediaId'>): AiredInput {
  return {
    source: row.source,
    status: row.status,
    episodes: row.episodes,
    next: row.next ?? null,
    episodesList: row.episodesList ?? null,
  }
}

function airedForProgress(row: Omit<ProgressMediaRow, 'mediaId'>, nowMs: number = Date.now()): number {
  return airedCount(toAiredInput(row), nowMs).aired
}

/**
 * One-off, idempotent repair (review i4): progress stored on a season that has not premiered —
 * written before the write clamp existed — comes back the day the season does. Every read guard
 * stops at the premiere: Avatar: Seven Havens, 13 of 13 marked a fortnight before its 9 Oct
 * premiere, would open that day at "Season 1 · Episode 14" with thirteen watched discs over
 * unaired episodes, never behind and never on Today. Each unaired season is set to what has aired
 * (nothing, until it does). Run at boot and hourly; a no-op once the rows are clean.
 */
export async function clampUnairedProgress(): Promise<number> {
  const rows = await db
    .select({
      userId: progress.userId,
      mediaId: progress.mediaId,
      watched: progress.episodesWatched,
      source: media.source,
      status: media.status,
      episodes: media.episodes,
      next: media.nextAiringEpisode,
      episodesList: media.episodesList,
    })
    .from(progress)
    .innerJoin(media, eq(media.id, progress.mediaId))
    .where(and(eq(media.status, 'NOT_YET_RELEASED'), gt(progress.episodesWatched, 0)))
  let fixed = 0
  for (const row of rows) {
    const aired = airedForProgress(row)
    if (row.watched <= aired) continue
    await db
      .update(progress)
      .set({ episodesWatched: aired, updatedAt: new Date() })
      .where(and(eq(progress.userId, row.userId), eq(progress.mediaId, row.mediaId)))
    fixed++
  }
  return fixed
}

export type FranchiseProgressCommand =
  | { mode: 'caught_up' | 'completed' | 'reset'; status?: WatchStatus }
  | { parts: { mediaId: number; episodes: number }[]; status?: WatchStatus }

export class FranchiseProgressError extends Error {
  constructor(
    public readonly reason: 'not_found' | 'invalid_part',
    message: string,
  ) {
    super(message)
  }
}

/**
 * The writes a franchise-level command makes. `caught_up` / `completed` mark each part to what has
 * aired by `nowMs` (a slot that struck counts before the hourly sync notices), never below what the
 * part already holds (`caughtUpValue`); explicit parts are clamped exactly as `PUT /me/progress`
 * clamps (`clampProgressValue`, the stored count kept reachable). Only `reset` walks progress back.
 */
export function progressWritesForCommand(
  rows: ProgressMediaRow[],
  command: FranchiseProgressCommand,
  nowMs: number = Date.now(),
): { mediaId: number; episodes: number }[] {
  if ('mode' in command) {
    return rows.map((row) => ({
      mediaId: row.mediaId,
      episodes: command.mode === 'reset' ? 0 : caughtUpValue(toAiredInput(row), nowMs, row.watched ?? 0),
    }))
  }
  const byId = new Map(rows.map((row) => [row.mediaId, row]))
  const seen = new Set<number>()
  return command.parts.map((part) => {
    const row = byId.get(part.mediaId)
    if (!row || seen.has(part.mediaId)) {
      throw new FranchiseProgressError('invalid_part', `media ${part.mediaId} is not a unique member of this franchise`)
    }
    seen.add(part.mediaId)
    return {
      mediaId: part.mediaId,
      episodes: clampProgressValue(toAiredInput(row), part.episodes, nowMs, row.watched ?? 0),
    }
  })
}

/**
 * Apply a franchise-level progress action in one transaction. This is intentionally separate from
 * the legacy single-part endpoint: clients can migrate without losing the simple primitive, while
 * catch-up/reset/completion can no longer leave half a franchise updated after an interrupted run.
 */
export async function setFranchiseProgress(
  userId: string,
  franchiseId: string,
  command: FranchiseProgressCommand,
): Promise<FranchiseProgressCommandResponse> {
  return db.transaction(async (tx) => {
    const [exists] = await tx.select({ id: franchise.id }).from(franchise).where(eq(franchise.id, franchiseId)).limit(1)
    if (!exists) throw new FranchiseProgressError('not_found', 'franchise not found')

    const rows: ProgressMediaRow[] = await tx
      .select({
        mediaId: media.id,
        source: media.source,
        status: media.status,
        episodes: media.episodes,
        next: media.nextAiringEpisode,
        episodesList: media.episodesList,
        watched: progress.episodesWatched,
      })
      .from(franchiseMember)
      .innerJoin(media, eq(media.id, franchiseMember.mediaId))
      .leftJoin(progress, and(eq(progress.mediaId, media.id), eq(progress.userId, userId)))
      .where(eq(franchiseMember.franchiseId, franchiseId))

    const writes = progressWritesForCommand(rows, command)

    const now = new Date()
    for (const write of writes) {
      await tx
        .insert(progress)
        .values({ userId, mediaId: write.mediaId, episodesWatched: write.episodes, updatedAt: now })
        .onConflictDoUpdate({
          target: [progress.userId, progress.mediaId],
          set: { episodesWatched: write.episodes, updatedAt: now },
        })
    }

    const requestedStatus = command.status ?? ('mode' in command && command.mode === 'completed' ? 'completed' : undefined)
    if (requestedStatus) {
      await tx
        .insert(subscriptions)
        .values({ userId, franchiseId, status: requestedStatus })
        .onConflictDoUpdate({
          target: [subscriptions.userId, subscriptions.franchiseId],
          set: { status: requestedStatus },
        })
    }

    const [subscription] = await tx
      .select({ status: subscriptions.status })
      .from(subscriptions)
      .where(and(eq(subscriptions.userId, userId), eq(subscriptions.franchiseId, franchiseId)))
      .limit(1)
    const saved = rows.length
      ? await tx
          .select({ mediaId: progress.mediaId, episodes: progress.episodesWatched })
          .from(progress)
          .where(and(eq(progress.userId, userId), inArray(progress.mediaId, rows.map((row) => row.mediaId))))
      : []
    const savedById = new Map(saved.map((row) => [row.mediaId, row.episodes]))
    return {
      ok: true,
      franchiseId,
      status: (subscription?.status as WatchStatus | undefined) ?? null,
      progress: rows.map((row) => ({ mediaId: row.mediaId, episodes: savedById.get(row.mediaId) ?? 0 })),
    }
  })
}

/**
 * A new visit: move the last visit into `prev_opened_at` and stamp now, in ONE statement; return the
 * previous visit (for "since you were last here").
 *
 * Postgres evaluates every SET right-hand side against the OLD row, so `prev_opened_at =
 * last_opened_at` reads the stamp this statement replaces — atomic, with no read-then-write window
 * for a second foreground to slip through. Every later read in the session (`GET /me/library`,
 * `GET /me/feed`) answers `prev_opened_at`, never the stamp just written (the pre-0010 echo bug:
 * the pill and "new" compared against a moment ago). 0 for an unknown id.
 */
export async function markOpened(userId: string): Promise<number> {
  const [row] = await db
    .update(users)
    .set({ prevOpenedAt: sql`${users.lastOpenedAt}`, lastOpenedAt: Date.now() })
    .where(eq(users.id, userId))
    .returning({ prev: users.prevOpenedAt })
  return row?.prev ?? 0
}

/** Whether a franchise exists (for 404s on subscribe). */
export async function franchiseExists(franchiseId: string): Promise<boolean> {
  const [f] = await db.select({ id: franchise.id }).from(franchise).where(eq(franchise.id, franchiseId)).limit(1)
  return !!f
}
