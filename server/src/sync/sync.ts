import { and, eq, inArray, isNotNull, or } from 'drizzle-orm'
import { fetchByIds, fetchLastAired, fetchTrending } from '../anilist/client.js'
import { db } from '../db/index.js'
import { franchise, franchiseMember, media, subscriptions } from '../db/schema.js'
import { env } from '../env.js'
import { groupFromSeed } from '../grouping/service.js'
import { upsertMedia } from '../services/mediaStore.js'
import { getTrendingTv, tmdbEnabled } from '../tmdb/client.js'
import { isJapaneseAnimation } from '../tmdb/mapping.js'
import { ensureTvFranchise, refreshTvShow } from '../tmdb/service.js'
import { mapWithConcurrency } from '../util/concurrency.js'

/**
 * Refresh airing data for currently-releasing AniList media (next episode + exact last-aired
 * time). Keeps countdowns and "out now" detection accurate. Source-filtered: TMDB rows live in
 * the same table but must never be sent to AniList (their ids are offset TMDB season ids).
 */
export async function refreshAiring(): Promise<number> {
  const rows = await db
    .select({ id: media.id })
    .from(media)
    .where(and(eq(media.status, 'RELEASING'), eq(media.source, 'anilist')))
  const ids = rows.map((r) => r.id)
  if (ids.length === 0) return 0

  const fresh = await fetchByIds(ids)
  await upsertMedia(fresh)

  const lastAired = await fetchLastAired(ids)
  for (const [id, ts] of Object.entries(lastAired)) {
    await db.update(media).set({ lastAiredAt: ts }).where(eq(media.id, Number(id)))
  }
  return ids.length
}

/**
 * TV sibling of refreshAiring: re-fetch every TMDB show that is releasing or subscribed.
 * The show payload carries seasons[], so this also attaches newly-announced seasons — TV
 * needs no separate attachNewSeasons pass.
 */
export async function refreshAiringTv(): Promise<number> {
  if (!tmdbEnabled()) return 0
  const rows = await db
    .selectDistinct({ id: franchise.id, externalId: franchise.externalId })
    .from(franchise)
    .leftJoin(franchiseMember, eq(franchiseMember.franchiseId, franchise.id))
    .leftJoin(media, eq(media.id, franchiseMember.mediaId))
    .leftJoin(subscriptions, eq(subscriptions.franchiseId, franchise.id))
    .where(
      and(eq(franchise.source, 'tmdb'), or(eq(media.status, 'RELEASING'), isNotNull(subscriptions.userId))),
    )
    .limit(100)

  const results = await mapWithConcurrency(rows, 5, async ({ id, externalId }) => {
    if (externalId == null) return false
    try {
      return (await refreshTvShow(id, externalId)).refreshed
    } catch (err) {
      console.warn(`refreshAiringTv: failed for franchise ${id}:`, (err as Error).message)
      return false
    }
  })
  return results.filter(Boolean).length
}

/**
 * Seed/refresh trending franchises: fetch top trending anime, cache them, and group any that
 * aren't grouped yet. Grouping is idempotent and component-deduped, so the number of actual
 * grouping calls is far smaller than the seed count.
 */
export async function seedTrending(count = env.TRENDING_SEED_COUNT): Promise<{ fetched: number; grouped: number }> {
  const trending = await fetchTrending(count)
  await upsertMedia(trending)

  const ids = trending.map((m) => m.id)
  const alreadyGrouped = new Set(
    (await db.select({ mediaId: franchiseMember.mediaId }).from(franchiseMember).where(inArray(franchiseMember.mediaId, ids))).map(
      (r) => r.mediaId,
    ),
  )

  let grouped = 0
  for (const m of trending) {
    if (alreadyGrouped.has(m.id)) continue
    try {
      // Pass the bulk model (not a pre-built grouper) so the per-component gate still applies:
      // most trending shows are simple sequel chains and never reach the LLM at all.
      const outcome = await groupFromSeed(m.id, { model: env.OPENROUTER_MODEL_BULK })
      grouped++
      // Mark every member of the resulting component as grouped so we skip them this run.
      const members = await db
        .select({ mediaId: franchiseMember.mediaId })
        .from(franchiseMember)
        .where(eq(franchiseMember.franchiseId, outcome.franchiseId))
      for (const mem of members) alreadyGrouped.add(mem.mediaId)
    } catch (err) {
      console.warn(`seedTrending: failed to group media ${m.id}:`, (err as Error).message)
    }
  }
  return { fetched: trending.length, grouped }
}

/**
 * Seed trending TV (capped low so getTrendingFranchises' updatedAt-DESC feed isn't swamped by
 * TV on day one). Known shows short-circuit on the franchise external-id fast path.
 */
export async function seedTrendingTv(count = 40): Promise<{ fetched: number; created: number }> {
  if (!tmdbEnabled()) return { fetched: 0, created: 0 }
  const trending = await getTrendingTv(count)
  const keep = trending.filter((r) => !isJapaneseAnimation(r))

  let created = 0
  for (const r of keep) {
    try {
      const outcome = await ensureTvFranchise(r.id)
      if (outcome?.created) created++
    } catch (err) {
      console.warn(`seedTrendingTv: failed for show ${r.id}:`, (err as Error).message)
    }
  }
  return { fetched: keep.length, created }
}

/**
 * Detect new parts that have joined AniList franchises a user follows (e.g. a new season aired
 * and the relation graph now links it). Re-expands from each subscribed franchise's members.
 * TMDB franchises are excluded — their new seasons attach via refreshAiringTv.
 */
export async function attachNewSeasons(): Promise<number> {
  const subbedFranchises = await db
    .selectDistinct({ franchiseId: subscriptions.franchiseId })
    .from(subscriptions)
    .innerJoin(franchise, eq(franchise.id, subscriptions.franchiseId))
    .where(eq(franchise.source, 'anilist'))
  let attached = 0
  for (const { franchiseId } of subbedFranchises) {
    const members = await db
      .select({ mediaId: franchiseMember.mediaId })
      .from(franchiseMember)
      .where(eq(franchiseMember.franchiseId, franchiseId))
    if (members[0]) {
      try {
        const outcome = await groupFromSeed(members[0].mediaId)
        attached += outcome.attached
      } catch (err) {
        console.warn(`attachNewSeasons: failed to regroup franchise ${franchiseId}:`, (err as Error).message)
      }
    }
  }
  return attached
}
