import { eq, inArray, isNull, sql } from 'drizzle-orm'
import { fetchByIds, fetchLastAired, fetchTrending } from '../anilist/client.js'
import { db } from '../db/index.js'
import { franchiseMember, media, subscriptions } from '../db/schema.js'
import { env } from '../env.js'
import { groupFromSeed } from '../grouping/service.js'
import { upsertMedia } from '../services/mediaStore.js'

/**
 * Refresh airing data for currently-releasing media (next episode + exact last-aired time).
 * Keeps countdowns and "out now" detection accurate.
 */
export async function refreshAiring(): Promise<number> {
  const rows = await db.select({ id: media.id }).from(media).where(eq(media.status, 'RELEASING'))
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
 * Detect new parts that have joined franchises a user follows (e.g. a new season aired and
 * the relation graph now links it). Re-expands from each subscribed franchise's members.
 */
export async function attachNewSeasons(): Promise<number> {
  const subbedFranchises = await db
    .selectDistinct({ franchiseId: subscriptions.franchiseId })
    .from(subscriptions)
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

// Touch helpers so unused imports for future use don't trip noUnusedLocals if enabled.
void isNull
void sql
