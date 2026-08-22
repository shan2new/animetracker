import { inArray } from 'drizzle-orm'
import type { AniListMedia } from '../anilist/types.js'
import { searchMedia } from '../anilist/client.js'
import { db } from '../db/index.js'
import { franchiseMember } from '../db/schema.js'
import { expandComponent } from '../grouping/graph.js'
import { groupKnownComponent } from '../grouping/service.js'
import { searchTv, tmdbEnabled } from '../tmdb/client.js'
import { isJapaneseAnimation } from '../tmdb/mapping.js'
import { ensureTvFranchise } from '../tmdb/service.js'
import type { FranchiseListResponse, SourceOutcome } from '../types/api.js'
import { mapWithConcurrency } from '../util/concurrency.js'
import { getSummaries, getTrendingFranchises } from './franchiseView.js'
import { makeAniListFetcher, upsertMedia } from './mediaStore.js'
import { correctSearchQuery } from './queryCorrect.js'

// Cap how many cache-miss components we group synchronously per search, to bound LLM cost/latency.
const LAZY_GROUP_CAP = 8
// How many components to expand / group in parallel. Bounded to respect AniList rate limits,
// the OpenRouter budget, and the DB connection pool.
const EXPAND_CONCURRENCY = 6
const GROUP_CONCURRENCY = 4
// Cap how many not-yet-known TMDB shows we materialize per search (each costs one /tv/{id}
// call; known shows short-circuit on a DB lookup, so steady-state is ~1 TMDB call per search).
const LAZY_TV_CAP = 5
const TV_CONCURRENCY = 4

/**
 * Search franchises across both sources. Empty query → trending. AniList hits resolve to
 * franchises via lazy relation-graph grouping; TMDB TV hits (minus Japanese animation, which
 * AniList owns) are materialized deterministically via ensureTvFranchise. Results interleave
 * anime and TV in each source's relevance order.
 *
 * The response is honest about two things the caller cannot see otherwise: whether the query it
 * sent was silently spell-corrected (`correctedQuery`), and whether a catalogue failed or is
 * switched off rather than simply having no matches (`sources`). `opts.exact` opts out of the
 * correction, so a caller can insist on the literal query.
 */
export async function searchFranchises(
  query: string,
  limit = 30,
  opts: { exact?: boolean } = {},
): Promise<FranchiseListResponse> {
  // A catalogue that threw is not a catalogue with no results — record which is which. TMDB's
  // outcome is known before any request: with no TMDB_ACCESS_TOKEN the whole catalogue is off, and
  // the empty-query (trending) branch below returns this object without touching either source.
  const sources: { anilist: SourceOutcome; tmdb: SourceOutcome } = {
    anilist: 'ok',
    tmdb: tmdbEnabled() ? 'ok' : 'disabled',
  }
  if (!query.trim()) return { franchises: await getTrendingFranchises(limit), sources }

  // The outcome is written per CALL, success included, so the LAST attempt wins. Latching only
  // the failure would let a first call that threw mark the catalogue `failed` for good — and the
  // spell-corrected retry below would then return live AniList hits under "AniList couldn't be
  // reached", which is exactly the dishonesty `sources` exists to prevent.
  const searchAniListSafe = (q: string) =>
    searchMedia(q).then(
      (r) => {
        sources.anilist = 'ok'
        return r
      },
      () => {
        sources.anilist = 'failed'
        return []
      },
    )
  const searchTvSafe = (q: string) => {
    if (!tmdbEnabled()) return Promise.resolve([])
    return searchTv(q).then(
      (r) => {
        sources.tmdb = 'ok'
        return r
      },
      () => {
        sources.tmdb = 'failed'
        return []
      },
    )
  }

  let [hits, tvHitsRaw] = await Promise.all([searchAniListSafe(query), searchTvSafe(query)])
  // AniList ANDs the query's whitespace tokens with no typo tolerance, so one misspelled word
  // ("Mushuko" for "Mushoku") returns nothing at all. When both sources whiff, spell-correct the
  // query via Cerebras and search once more with the fixed query before giving up.
  let correctedQuery: string | undefined
  if (hits.length === 0 && tvHitsRaw.length === 0 && !opts.exact) {
    const corrected = await correctSearchQuery(query)
    if (corrected) {
      ;[hits, tvHitsRaw] = await Promise.all([searchAniListSafe(corrected), searchTvSafe(corrected)])
      // Only claim a correction that actually changed the outcome — otherwise the client would
      // apologise for a rewrite that found nothing either.
      if (hits.length > 0 || tvHitsRaw.length > 0) correctedQuery = corrected
    }
  }

  // Materialize TV franchises concurrently with the anime grouping below. Japanese animation is
  // suppressed — the AniList result is authoritative for that class (see docs/api-contract.md).
  const tvOutcomesPromise = mapWithConcurrency(
    tvHitsRaw.filter((r) => !isJapaneseAnimation(r)).slice(0, LAZY_TV_CAP),
    TV_CONCURRENCY,
    async (r) => {
      try {
        return await ensureTvFranchise(r.id)
      } catch {
        return null // a show that fails to materialize just doesn't contribute
      }
    },
  )

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

  const animeIds: string[] = []
  const seen = new Set<string>()
  for (const hit of hits) {
    const fid = franchiseByMedia.get(hit.id)
    if (fid && !seen.has(fid)) {
      seen.add(fid)
      animeIds.push(fid)
    }
  }

  const tvIds = (await tvOutcomesPromise)
    .filter((o): o is NonNullable<typeof o> => o != null)
    .map((o) => o.franchiseId)
    .filter((fid) => !seen.has(fid))

  // Interleave the two relevance-ordered lists (anime first) — deterministic, and keeps both
  // sources visible on mixed-name queries without inventing a cross-source score.
  const merged: string[] = []
  for (let i = 0; i < Math.max(animeIds.length, tvIds.length); i++) {
    if (animeIds[i]) merged.push(animeIds[i]!)
    if (tvIds[i]) merged.push(tvIds[i]!)
  }

  return {
    franchises: await getSummaries(merged.slice(0, limit)),
    ...(correctedQuery ? { correctedQuery, originalQuery: query } : {}),
    sources,
  }
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
