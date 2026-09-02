import type { PartKind } from '../grouping/partKind.js'
import type { FranchiseUpcoming, MediaSource } from '../types/api.js'

/** Minimal catalogue fields needed to turn a known future part into an `upcoming` fact. */
export interface CatalogUpcomingPart {
  mediaId: number
  kind: PartKind
  sequence: number
  label: string
  status: string | null
  nextAiringAt: number | null
  fetchedAt: Date | null
}

const KIND_ORDER: PartKind[] = ['season', 'movie', 'ona', 'ova', 'special', 'music']

function providerUrl(source: MediaSource, franchiseExternalId: number | null, mediaId: number): string | null {
  if (source === 'tmdb') {
    return franchiseExternalId == null ? null : `https://www.themoviedb.org/tv/${franchiseExternalId}`
  }
  return `https://anilist.co/anime/${mediaId}`
}

/**
 * Build a confirmed fallback from catalogue data already held by the backend.
 *
 * The web-news result remains authoritative when present because it carries richer context and a
 * primary announcement URL. This fallback closes the gap where AniList/TMDB already lists a future
 * season but the slower news researcher has never examined the franchise.
 */
export function deriveCatalogUpcoming(input: {
  source: MediaSource
  franchiseExternalId: number | null
  parts: CatalogUpcomingPart[]
  nowMs?: number
}): FranchiseUpcoming | null {
  const nowMs = input.nowMs ?? Date.now()
  const candidates = input.parts.filter((part) => {
    if (part.status !== 'NOT_YET_RELEASED') return false
    // A past premiere on a NOT_YET_RELEASED row is stale catalogue data, not an undated
    // announcement. The normal sync will advance it; until then, do not publish a false return.
    return part.nextAiringAt == null || part.nextAiringAt > nowMs
  })
  if (candidates.length === 0) return null

  candidates.sort((a, b) => {
    if (a.nextAiringAt != null && b.nextAiringAt != null) return a.nextAiringAt - b.nextAiringAt
    if (a.nextAiringAt != null) return -1
    if (b.nextAiringAt != null) return 1
    const kind = KIND_ORDER.indexOf(a.kind) - KIND_ORDER.indexOf(b.kind)
    return kind !== 0 ? kind : a.sequence - b.sequence
  })

  const next = candidates[0]!
  const release = next.nextAiringAt == null ? 'TBA' : new Date(next.nextAiringAt).toISOString().slice(0, 10)
  return {
    status: next.nextAiringAt == null ? 'announced_no_date' : 'upcoming_dated',
    next: next.label,
    release,
    note: null,
    source: providerUrl(input.source, input.franchiseExternalId, next.mediaId),
    checked: next.fetchedAt?.toISOString() ?? null,
  }
}

/**
 * A confirmed future catalogue part disproves a stored rumor/conclusion. Richer official web-news
 * remains preferred in every other case.
 */
export function resolveUpcomingWithCatalog(
  stored: FranchiseUpcoming | null | undefined,
  catalog: FranchiseUpcoming | null,
): FranchiseUpcoming | null {
  if (!stored) return catalog
  if (!catalog) return stored
  return ['rumored', 'recently_aired', 'concluded'].includes(stored.status) ? catalog : stored
}
