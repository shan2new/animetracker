import { and, desc, eq, inArray } from 'drizzle-orm'
import { db } from '../db/index.js'
import { catalogLinks, franchise, franchiseMember, recommendationEdges, subscriptions } from '../db/schema.js'
import type { DiscoveryItem, MediaSource, RelatedTitle, WatchStatus } from '../types/api.js'

/** Replace one franchise's source-native recommendation snapshot atomically. */
export async function syncRecommendationEdges(franchiseId: string, related: RelatedTitle[]): Promise<void> {
  const deduped = [...new Map(related.map((item) => [`${item.source}:${item.externalId}`, item])).values()]
  const resolved = await resolveTargets(deduped)
  await db.transaction(async (tx) => {
    await tx.delete(recommendationEdges).where(eq(recommendationEdges.franchiseId, franchiseId))
    if (resolved.length === 0) return
    await tx.insert(recommendationEdges).values(resolved.map((item) => ({
      franchiseId,
      source: item.source,
      externalId: item.externalId,
      targetFranchiseId: item.franchiseId,
      score: item.score ?? null,
      title: item.title,
      year: item.year,
      images: item.images,
      checkedAt: new Date(),
    })))
  })
}

async function resolveTargets(items: RelatedTitle[]): Promise<RelatedTitle[]> {
  if (items.length === 0) return []
  const animeIds = items.filter((item) => item.source === 'anilist').map((item) => item.externalId)
  const tmdbIds = items.filter((item) => item.source === 'tmdb').map((item) => item.externalId)
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
  for (const row of tv) if (row.externalId != null) local.set(`tmdb:${row.externalId}`, row.id)
  for (const row of linkedTv) if (row.externalId != null) local.set(`tmdb:${row.externalId}`, row.id)
  return items.map((item) => ({
    ...item,
    franchiseId: item.franchiseId ?? local.get(`${item.source}:${item.externalId}`) ?? null,
  }))
}

interface Candidate {
  item: DiscoveryItem
  sourceStatus: WatchStatus
  targetKey: string
}

/** Explainable recommendations derived only from catalogue votes and the user's own library. */
export async function getDiscover(userId: string, limit = 20): Promise<DiscoveryItem[]> {
  const mine = await db
    .select({ franchiseId: subscriptions.franchiseId, status: subscriptions.status, title: franchise.title })
    .from(subscriptions)
    .innerJoin(franchise, eq(franchise.id, subscriptions.franchiseId))
    .where(eq(subscriptions.userId, userId))
  if (mine.length === 0) return []

  const mineIds = mine.map((item) => item.franchiseId)
  const statusById = new Map(mine.map((item) => [item.franchiseId, item.status as WatchStatus]))
  const titleById = new Map(mine.map((item) => [item.franchiseId, item.title]))
  const rows = await db
    .select()
    .from(recommendationEdges)
    .where(inArray(recommendationEdges.franchiseId, mineIds))
    .orderBy(desc(recommendationEdges.score))
    .limit(Math.max(100, limit * 10))

  const subscribed = new Set(mineIds)
  const best = new Map<string, Candidate>()
  for (const row of rows) {
    if (row.targetFranchiseId && subscribed.has(row.targetFranchiseId)) continue
    const sourceStatus = statusById.get(row.franchiseId) ?? 'planned'
    if (sourceStatus === 'dropped') continue
    const statusBoost = sourceStatus === 'completed' ? 25 : sourceStatus === 'watching' ? 18 : 6
    const raw = row.score ?? 0
    const score = Math.round((raw + statusBoost) * 100) / 100
    const targetKey = row.targetFranchiseId ?? `${row.source}:${row.externalId}`
    const becauseTitle = titleById.get(row.franchiseId) ?? 'a title in your library'
    const candidate: Candidate = {
      targetKey,
      sourceStatus,
      item: {
        title: {
          source: row.source as MediaSource,
          externalId: row.externalId,
          franchiseId: row.targetFranchiseId,
          title: row.title,
          year: row.year,
          images: row.images,
          score: row.score,
        },
        because: { franchiseId: row.franchiseId, title: becauseTitle },
        reason: `Because you ${sourceStatus === 'completed' ? 'completed' : 'watched'} ${becauseTitle}`,
        score,
      },
    }
    const previous = best.get(targetKey)
    if (!previous || candidate.item.score > previous.item.score) best.set(targetKey, candidate)
  }

  // A single source title may contribute many near-identical recommendations. Cap it to three so
  // the feed stays exploratory while retaining deterministic ranking.
  const byBecause = new Map<string, number>()
  const out: DiscoveryItem[] = []
  for (const candidate of [...best.values()].sort((a, b) => b.item.score - a.item.score || a.item.title.title.localeCompare(b.item.title.title))) {
    const sourceId = candidate.item.because.franchiseId
    const count = byBecause.get(sourceId) ?? 0
    if (count >= 3) continue
    byBecause.set(sourceId, count + 1)
    out.push(candidate.item)
    if (out.length >= limit) break
  }
  return out
}
