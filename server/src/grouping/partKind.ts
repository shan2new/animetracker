import type { AniListMedia, MediaFormat } from '../anilist/types.js'

export type PartKind = 'season' | 'movie' | 'ova' | 'ona' | 'special' | 'music'

/** Deterministic AniList format → franchise part bucket. */
export function partKindForFormat(format: MediaFormat | null): PartKind {
  switch (format) {
    case 'MOVIE':
      return 'movie'
    case 'OVA':
      return 'ova'
    case 'ONA':
      return 'ona'
    case 'SPECIAL':
      return 'special'
    case 'MUSIC':
      return 'music'
    case 'TV':
    case 'TV_SHORT':
    default:
      return 'season'
  }
}

/** Chronological-ish sort key for ordering parts within a kind. */
export function airSortKey(m: AniListMedia): number {
  const year = m.seasonYear ?? 9999
  const seasonRank: Record<string, number> = { WINTER: 0, SPRING: 1, SUMMER: 2, FALL: 3 }
  const s = m.season ? (seasonRank[m.season] ?? 0) : 0
  return year * 10 + s
}
