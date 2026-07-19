import { and, eq, inArray } from 'drizzle-orm'
import { db } from '../db/index.js'
import { franchise, franchiseMember } from '../db/schema.js'
import type { GroupedPart } from '../grouping/llm.js'
import { persistFranchises, type GroupOutcome } from '../grouping/service.js'
import { upsertMediaRows } from '../services/mediaStore.js'
import { getShow } from './client.js'
import { imageUrl, includedSeasons, tmdbSeasonToMediaRow, tmdbShowToGroupingResult } from './mapping.js'

/**
 * Idempotently materialize a TMDB show as a franchise (seasons as members). Deterministic —
 * no relation graph, no LLM. Returns null when the show doesn't exist or has no usable
 * seasons (we never create empty franchises). Safe to call concurrently: the partial unique
 * index on franchise (source, external_id) plus deterministic member ids make a lost create
 * race resolve to the winner inside persistFranchises.
 */
export async function ensureTvFranchise(showId: number): Promise<GroupOutcome | null> {
  const [existing] = await db
    .select({ id: franchise.id })
    .from(franchise)
    .where(and(eq(franchise.source, 'tmdb'), eq(franchise.externalId, showId)))
    .limit(1)
  if (existing) return { franchiseId: existing.id, created: false, attached: 0 }

  const show = await getShow(showId)
  if (!show || includedSeasons(show).length === 0) return null

  const now = Date.now()
  let rows
  try {
    rows = includedSeasons(show).map((s) => tmdbSeasonToMediaRow(show, s, now))
  } catch (err) {
    // Season id outside the offset-safe range — skip the show rather than corrupt the keyspace.
    console.warn(`ensureTvFranchise: skipping show ${showId}:`, (err as Error).message)
    return null
  }
  await upsertMediaRows(rows, { setLastAired: true })

  const result = tmdbShowToGroupingResult(show)
  const parts = result.franchises[0]!.parts
  const seasonOne = parts.find((p) => p.sequence === 1 && p.partKind === 'season')
  return persistFranchises({
    result,
    seedId: parts[0]!.id,
    allIds: parts.map((p) => p.id),
    metaFor: () => ({
      title: show.name,
      primaryMediaId: seasonOne?.id ?? parts[0]!.id,
      cover: imageUrl(show.poster_path, 'w780'),
      banner: imageUrl(show.backdrop_path, 'w1280') ?? imageUrl(show.poster_path, 'w780'),
      description: show.overview || null,
      genres: (show.genres ?? []).map((g) => g.name).slice(0, 6),
      groupingSource: 'tmdb',
      groupingModel: null,
      confidence: 1,
      source: 'tmdb',
      externalId: show.id,
    }),
    // One show = one franchise, so every raced member points at the same winner.
    onRaced: async (raced) => ({ franchiseId: raced[0]!.franchiseId, created: false, attached: 0 }),
  })
}

/**
 * Refresh a TV franchise from its show payload: season statuses, episode counts, next/last
 * airing. New seasons in the payload become new members, so this doubles as TV's
 * attachNewSeasons — no separate daily job.
 */
export async function refreshTvShow(
  franchiseId: string,
  showId: number,
): Promise<{ refreshed: boolean; attached: number }> {
  const show = await getShow(showId)
  if (!show || includedSeasons(show).length === 0) return { refreshed: false, attached: 0 }

  const now = Date.now()
  let rows
  try {
    rows = includedSeasons(show).map((s) => tmdbSeasonToMediaRow(show, s, now))
  } catch (err) {
    console.warn(`refreshTvShow: skipping show ${showId}:`, (err as Error).message)
    return { refreshed: false, attached: 0 }
  }
  await upsertMediaRows(rows, { setLastAired: true })

  const attached = await attachTvMembers(franchiseId, tmdbShowToGroupingResult(show).franchises[0]!.parts)
  return { refreshed: true, attached }
}

/**
 * TV sibling of grouping's attachNewMembers: sequences come straight from TMDB season numbers
 * (never route TV through attachNewMembers — its per-kind next-sequence counter would drift
 * when seasons arrive out of order).
 */
async function attachTvMembers(franchiseId: string, parts: GroupedPart[]): Promise<number> {
  const existing = await db
    .select({ mediaId: franchiseMember.mediaId })
    .from(franchiseMember)
    .where(eq(franchiseMember.franchiseId, franchiseId))
  const already = new Set(existing.map((r) => r.mediaId))
  const fresh = parts.filter((p) => !already.has(p.id))
  if (fresh.length === 0) return 0

  await db
    .insert(franchiseMember)
    .values(fresh.map((p) => ({ mediaId: p.id, franchiseId, partKind: p.partKind, sequence: p.sequence, label: p.label })))
    .onConflictDoNothing()
  await db.update(franchise).set({ updatedAt: new Date() }).where(inArray(franchise.id, [franchiseId]))
  return fresh.length
}
