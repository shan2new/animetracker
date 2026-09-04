import { and, eq } from 'drizzle-orm'
import { db } from '../db/index.js'
import { franchise, franchiseMember, media, progress, subscriptions, users } from '../db/schema.js'
import type { FranchiseProgressCommandResponse, WatchStatus } from '../types/api.js'
import { inArray } from 'drizzle-orm'
import { deriveAiredEpisodes } from './franchiseView.js'

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

export async function setProgress(userId: string, mediaId: number, episodes: number): Promise<void> {
  let clamped = Number.isFinite(episodes) ? Math.max(0, Math.floor(episodes)) : 0
  // Ceiling: a part can't be watched past its own SIZE. Belt-and-braces against any client with
  // an unbounded "+1" control — one such control walked a 10-episode season up to 59 watched, and
  // a bad value written once stays wrong until something overwrites it.
  //
  // Size is `max(episodes, airedEpisodes)`, exactly what the client bounds itself to
  // (`FranchisePart.progressCeiling`). The two ceilings MUST agree: a RELEASING part whose
  // catalogue total lags its aired count (a stale `episode_count`, an `episodes: null` season
  // that derives its aired number from the next slot) let the client legitimately mark caught up
  // at N while a `media.episodes`-only ceiling silently stored less — the user saw "caught up"
  // against a server that disagreed and a fresh launch reverted them.
  // Unsized and un-aired (ongoing AniList shows carry `episodes: null`) stays unbounded.
  const [row] = await db
    .select({
      status: media.status,
      episodes: media.episodes,
      next: media.nextAiringEpisode,
      episodesList: media.episodesList,
    })
    .from(media)
    .where(eq(media.id, mediaId))
    .limit(1)
  if (row) clamped = clampProgress(row, clamped)
  await db
    .insert(progress)
    .values({ userId, mediaId, episodesWatched: clamped, updatedAt: new Date() })
    .onConflictDoUpdate({
      target: [progress.userId, progress.mediaId],
      set: { episodesWatched: clamped, updatedAt: new Date() },
    })
}

export interface ProgressMediaRow {
  mediaId: number
  status: string | null
  episodes: number | null
  next: { episode: number; airingAt: number } | null
  episodesList: import('../types/api.js').EpisodeMeta[] | null
}

function airedForProgress(row: ProgressMediaRow): number {
  return deriveAiredEpisodes({
    status: row.status,
    totalEpisodes: row.episodes ?? 0,
    next: row.next && row.next.airingAt > 0 ? row.next : null,
    episodes: row.episodesList ?? [],
    nowMs: Date.now(),
  })
}

function clampProgress(row: Omit<ProgressMediaRow, 'mediaId'>, episodes: number): number {
  const value = Number.isFinite(episodes) ? Math.max(0, Math.floor(episodes)) : 0
  const ceiling = Math.max(row.episodes ?? 0, airedForProgress({ ...row, mediaId: 0 }))
  return ceiling > 0 ? Math.min(value, ceiling) : value
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

export function progressWritesForCommand(
  rows: ProgressMediaRow[],
  command: FranchiseProgressCommand,
): { mediaId: number; episodes: number }[] {
  if ('mode' in command) {
    return rows.map((row) => ({
      mediaId: row.mediaId,
      episodes: command.mode === 'reset' ? 0 : airedForProgress(row),
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
    return { mediaId: part.mediaId, episodes: clampProgress(row, part.episodes) }
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
        status: media.status,
        episodes: media.episodes,
        next: media.nextAiringEpisode,
        episodesList: media.episodesList,
      })
      .from(franchiseMember)
      .innerJoin(media, eq(media.id, franchiseMember.mediaId))
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

/** Stamp the user's last-opened time to now; return the PREVIOUS value (for "since you were last here"). */
export async function markOpened(userId: string): Promise<number> {
  const [u] = await db.select({ prev: users.lastOpenedAt }).from(users).where(eq(users.id, userId)).limit(1)
  const prev = u?.prev ?? 0
  await db.update(users).set({ lastOpenedAt: Date.now() }).where(eq(users.id, userId))
  return prev
}

/** Whether a franchise exists (for 404s on subscribe). */
export async function franchiseExists(franchiseId: string): Promise<boolean> {
  const [f] = await db.select({ id: franchise.id }).from(franchise).where(eq(franchise.id, franchiseId)).limit(1)
  return !!f
}
