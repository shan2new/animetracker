import type { AniListMedia, RelationType } from '../anilist/types.js'

// Edge types that keep us inside the SAME canonical franchise. We deliberately exclude
// ALTERNATIVE / SPIN_OFF / ADAPTATION / CHARACTER / OTHER — they over-merge distinct works
// (shared universes, manga sources, cameo crossovers). The LLM refine step can still split
// further; this just bounds the candidate component.
const FOLLOW: ReadonlySet<RelationType> = new Set<RelationType>(['SEQUEL', 'PREQUEL', 'PARENT', 'SIDE_STORY'])

const MAX_COMPONENT = 60 // safety cap against pathological graphs

/**
 * Fetches a whole BFS frontier at once. Implementations batch the network call (and may
 * read from / write to the local media cache). Returns only the media that resolved;
 * missing/non-anime ids are simply omitted.
 */
export type MediaFetcher = (ids: number[]) => Promise<AniListMedia[]>

/**
 * BFS the AniList relation graph from `seedId`, following only intra-franchise edges,
 * and return the connected component of ANIME media (id → media). Bounded by MAX_COMPONENT.
 * Each BFS level is fetched in a single batched call, so a component of N nodes costs
 * O(depth) round-trips rather than N.
 */
export async function expandComponent(seedId: number, fetchMany: MediaFetcher): Promise<Map<number, AniListMedia>> {
  const visited = new Map<number, AniListMedia>()
  let frontier: number[] = [seedId]
  const enqueued = new Set<number>([seedId])

  while (frontier.length > 0 && visited.size < MAX_COMPONENT) {
    const batch = frontier.filter((id) => !visited.has(id))
    frontier = []
    if (batch.length === 0) break

    const fetched = await fetchMany(batch)
    for (const m of fetched) {
      if (visited.has(m.id)) continue
      if (visited.size >= MAX_COMPONENT) break
      visited.set(m.id, m)

      for (const edge of m.relations?.edges ?? []) {
        if (edge.node.type !== 'ANIME') continue
        if (!FOLLOW.has(edge.relationType)) continue
        // Skip pure-music tie-ins; they're rarely part of the watch experience.
        if (edge.node.format === 'MUSIC') continue
        if (!enqueued.has(edge.node.id)) {
          enqueued.add(edge.node.id)
          frontier.push(edge.node.id)
        }
      }
    }
  }

  return visited
}
