import { and, eq, inArray, sql } from 'drizzle-orm'
import { db } from '../db/index.js'
import { catalogLinks, franchise, franchiseMember, recommendationEdges, recommendationTargets } from '../db/schema.js'
import type { RecommendationEdgeFacts, RecommendationTargetFacts } from './recommendationRank.js'

/** A target as the refreshers hand it over; `rootCheckedAt` is kept when the root was reused. */
export type RecommendationTargetWrite = RecommendationTargetFacts & { rootCheckedAt?: Date }

const targetKey = (item: { source: string; externalId: number }) => `${item.source}:${item.externalId}`

/**
 * Write-time resolution of each edge's local franchise. Only for the legacy `target_franchise_id`
 * column and its index: the ranker never trusts it and resolves ownership live on every read.
 */
async function resolveTargetFranchises(edges: RecommendationEdgeFacts[]): Promise<Map<string, string>> {
  const animeIds = edges.filter((item) => item.source === 'anilist').map((item) => item.externalId)
  const tmdbIds = edges.filter((item) => item.source === 'tmdb').map((item) => item.externalId)
  const [anime, tv, linkedTv] = await Promise.all([
    animeIds.length
      ? db.select({ externalId: franchiseMember.mediaId, id: franchiseMember.franchiseId })
          .from(franchiseMember).where(inArray(franchiseMember.mediaId, animeIds))
      : Promise.resolve([]),
    tmdbIds.length
      ? db.select({ externalId: franchise.externalId, id: franchise.id }).from(franchise)
          .where(and(eq(franchise.source, 'tmdb'), inArray(franchise.externalId, tmdbIds)))
      : Promise.resolve([]),
    tmdbIds.length
      ? db.select({ externalId: catalogLinks.externalId, id: catalogLinks.franchiseId }).from(catalogLinks)
          .where(and(
            eq(catalogLinks.provider, 'tmdb'),
            eq(catalogLinks.status, 'matched'),
            inArray(catalogLinks.externalId, tmdbIds),
          ))
      : Promise.resolve([]),
  ])
  const local = new Map<string, string>()
  for (const row of anime) local.set(`anilist:${row.externalId}`, row.id)
  for (const row of linkedTv) if (row.externalId != null) local.set(`tmdb:${row.externalId}`, row.id)
  for (const row of tv) if (row.externalId != null) local.set(`tmdb:${row.externalId}`, row.id)
  return local
}

/**
 * Replace one franchise's recommendation list atomically, and upsert the facts about every title
 * on it into the shared `recommendation_targets`. Edges without a target row are never written:
 * the ranker cannot vet a title it knows nothing about.
 */
export async function syncRecommendationEdges(
  franchiseId: string,
  edges: RecommendationEdgeFacts[],
  targets: RecommendationTargetWrite[],
): Promise<void> {
  const byKey = new Map<string, RecommendationTargetWrite>()
  for (const target of targets) if (!byKey.has(targetKey(target))) byKey.set(targetKey(target), target)
  const seen = new Set<string>()
  const list = edges.filter((edge) => {
    const key = targetKey(edge)
    if (seen.has(key) || !byKey.has(key)) return false
    seen.add(key)
    return true
  })
  const resolved = await resolveTargetFranchises(list)
  const now = new Date()
  const rows = [...byKey.values()].map((target) => ({ ...target, rootCheckedAt: target.rootCheckedAt ?? now, checkedAt: now }))

  await db.transaction(async (tx) => {
    if (rows.length > 0) {
      await tx
        .insert(recommendationTargets)
        .values(rows)
        .onConflictDoUpdate({
          target: [recommendationTargets.source, recommendationTargets.externalId],
          set: Object.fromEntries(
            [
              'title', 'year', 'images', 'format', 'status', 'episodes', 'average_score', 'vote_count', 'popularity',
              'genres', 'is_adult', 'country_of_origin', 'airing', 'announced', 'release_date', 'root_id', 'root_title',
              'root_year', 'root_format', 'root_episodes', 'root_images', 'member_ids', 'world_ids', 'root_checked_at',
              'checked_at',
            ].map((column) => [camel(column), sql.raw(`excluded.${column}`)]),
          ),
        })
    }
    await tx.delete(recommendationEdges).where(eq(recommendationEdges.franchiseId, franchiseId))
    if (list.length === 0) return
    await tx.insert(recommendationEdges).values(list.map((edge) => {
      const target = byKey.get(targetKey(edge))!
      return {
        franchiseId,
        source: edge.source,
        externalId: edge.externalId,
        targetFranchiseId: resolved.get(targetKey(edge)) ?? null,
        score: edge.votes,
        title: target.title,
        year: target.year,
        images: target.images,
        rank: edge.rank,
        votes: edge.votes,
        checkedAt: now,
      }
    }))
  })
}

function camel(column: string): string {
  return column.replace(/_([a-z])/g, (_, c: string) => c.toUpperCase())
}

/** Stored series identity for AniList targets whose root is still fresh (reused, not re-walked). */
export async function storedRoots(ids: number[], freshAfter: Date): Promise<Map<number, RecommendationTargetWrite>> {
  const unique = [...new Set(ids)]
  if (unique.length === 0) return new Map()
  const rows = await db
    .select()
    .from(recommendationTargets)
    .where(and(eq(recommendationTargets.source, 'anilist'), inArray(recommendationTargets.externalId, unique)))
  const out = new Map<number, RecommendationTargetWrite>()
  for (const row of rows) {
    if (row.rootCheckedAt < freshAfter) continue
    out.set(row.externalId, {
      source: 'anilist',
      externalId: row.externalId,
      title: row.title,
      year: row.year,
      images: row.images,
      format: row.format,
      status: row.status,
      episodes: row.episodes,
      averageScore: row.averageScore,
      voteCount: row.voteCount,
      popularity: row.popularity,
      genres: row.genres,
      isAdult: row.isAdult,
      countryOfOrigin: row.countryOfOrigin,
      airing: row.airing,
      announced: row.announced,
      releaseDate: row.releaseDate,
      rootId: row.rootId,
      rootTitle: row.rootTitle,
      rootYear: row.rootYear,
      rootFormat: row.rootFormat,
      rootEpisodes: row.rootEpisodes,
      rootImages: row.rootImages,
      memberIds: row.memberIds,
      worldIds: row.worldIds,
      rootCheckedAt: row.rootCheckedAt,
    })
  }
  return out
}
