import { inArray } from 'drizzle-orm'
import type { AniListMedia } from '../anilist/types.js'
import { searchMedia } from '../anilist/client.js'
import { db } from '../db/index.js'
import { franchiseMember } from '../db/schema.js'
import { expandComponent } from '../grouping/graph.js'
import { groupKnownComponent } from '../grouping/service.js'
import type { FranchiseSummary } from '../types/api.js'
import { mapWithConcurrency } from '../util/concurrency.js'
import { getSummaries, getTrendingFranchises } from './franchiseView.js'
import { makeAniListFetcher, upsertMedia } from './mediaStore.js'

// Cap how many cache-miss components we group synchronously per search, to bound LLM cost/latency.
const LAZY_GROUP_CAP = 8
// How many components to expand / group in parallel. Bounded to respect AniList rate limits,
// the OpenRouter budget, and the DB connection pool.
const EXPAND_CONCURRENCY = 6
const GROUP_CONCURRENCY = 4

/**
 * Search franchises. Empty query → trending. For each AniList hit, resolve its franchise,
 * lazily grouping (and caching) up to LAZY_GROUP_CAP ungrouped hits. Returns distinct
 * franchises in search-relevance order.
 */
export async function searchFranchises(query: string, limit = 30): Promise<FranchiseSummary[]> {
  if (!query.trim()) return getTrendingFranchises(limit)

  const hits = await searchMedia(query)
  await upsertMedia(hits)

  const hitIds = hits.map((h) => h.id)
  const existing = hitIds.length
    ? await db.select().from(franchiseMember).where(inArray(franchiseMember.mediaId, hitIds))
    : []
  const alreadyGrouped = new Set(existing.map((m) => m.mediaId))

  // Seeds that still need grouping, in relevance order, capped to bound cost.
  const seeds = hits.map((h) => h.id).filter((id) => !alreadyGrouped.has(id)).slice(0, LAZY_GROUP_CAP)

  if (seeds.length > 0) {
    // Phase 1: expand each seed's relation component (network-only, no LLM). A single
    // memoised fetcher is shared across all seeds, so overlapping franchises (e.g. a query
    // that returns many seasons of one show) never re-fetch the same node.
    const fetcher = makeAniListFetcher()
    const expanded = await mapWithConcurrency(seeds, EXPAND_CONCURRENCY, async (seedId) => {
      try {
        const component = await expandComponent(seedId, fetcher)
        return component.size > 0 ? { seedId, component } : null
      } catch {
        return null // a seed that fails to expand just doesn't contribute; the rest still return
      }
    })

    // Dedupe overlapping components so each franchise is grouped (and LLM-classified) once.
    const unique = dedupeComponents(expanded.filter((e): e is ExpandedComponent => e !== null))

    // Phase 2: group the distinct components concurrently.
    await mapWithConcurrency(unique, GROUP_CONCURRENCY, async ({ seedId, component }) => {
      try {
        await groupKnownComponent(component, seedId)
      } catch {
        // skip a component that fails to group; the rest of the page still returns
      }
    })
  }

  // Re-resolve every hit to its (now-persisted) franchise and return them in relevance order.
  const members = hitIds.length
    ? await db.select().from(franchiseMember).where(inArray(franchiseMember.mediaId, hitIds))
    : []
  const franchiseByMedia = new Map(members.map((m) => [m.mediaId, m.franchiseId]))

  const orderedFranchiseIds: string[] = []
  const seen = new Set<string>()
  for (const hit of hits) {
    const fid = franchiseByMedia.get(hit.id)
    if (fid && !seen.has(fid)) {
      seen.add(fid)
      orderedFranchiseIds.push(fid)
    }
  }

  return getSummaries(orderedFranchiseIds.slice(0, limit))
}

interface ExpandedComponent {
  seedId: number
  component: Map<number, AniListMedia>
}

/**
 * Merge components that share any member into one. The relation BFS yields the same set from
 * any seed in a component, so overlapping expansions are effectively duplicates; collapsing
 * them avoids grouping the same franchise twice (and the duplicate LLM call / write race).
 */
function dedupeComponents(items: ExpandedComponent[]): ExpandedComponent[] {
  const merged: ExpandedComponent[] = []
  for (const item of items) {
    const ids = [...item.component.keys()]
    // Find every existing bucket this item touches — there can be more than one when the item
    // bridges two previously-disjoint buckets (transitive merge). Fold them all together.
    const overlapping = merged.filter((m) => ids.some((id) => m.component.has(id)))
    if (overlapping.length === 0) {
      merged.push({ seedId: item.seedId, component: new Map(item.component) })
      continue
    }
    const target = overlapping[0]!
    for (const [id, media] of item.component) target.component.set(id, media)
    for (let i = 1; i < overlapping.length; i++) {
      for (const [id, media] of overlapping[i]!.component) target.component.set(id, media)
    }
    if (overlapping.length > 1) {
      const drop = new Set(overlapping.slice(1))
      for (let i = merged.length - 1; i >= 0; i--) if (drop.has(merged[i]!)) merged.splice(i, 1)
    }
  }
  return merged
}
