import type { GroupingInput, GroupingResult, GroupedPart } from './llm.js'
import type { PartKind } from './partKind.js'

const seasonRank: Record<string, number> = { WINTER: 0, SPRING: 1, SUMMER: 2, FALL: 3 }

/**
 * No-LLM grouping: everything in the component becomes one franchise. part_kind comes from
 * AniList format; sequence is chronological within each kind. Used as a fallback and as the
 * baseline the tests assert against.
 */
export function deterministicGroup(input: GroupingInput): GroupingResult {
  const byKind = new Map<PartKind, typeof input.candidates>()
  for (const c of input.candidates) {
    const kind = formatToKind(c.format)
    const arr = byKind.get(kind) ?? []
    arr.push(c)
    byKind.set(kind, arr)
  }

  const parts: GroupedPart[] = []
  for (const [kind, arr] of byKind) {
    arr.sort((a, b) => sortKey(a) - sortKey(b))
    arr.forEach((c, i) => {
      const label = kind === 'season' ? `Season ${i + 1}` : `${capitalize(kind)} ${i + 1}`
      parts.push({ id: c.id, partKind: kind, sequence: i + 1, label })
    })
  }

  // Canonical name: the earliest TV season's title, else the first candidate's title.
  const seasons = input.candidates
    .filter((c) => formatToKind(c.format) === 'season')
    .sort((a, b) => sortKey(a) - sortKey(b))
  const canonicalName = (seasons[0] ?? input.candidates[0])?.title ?? 'Untitled'

  return { franchises: [{ canonicalName, parts }], confidence: 0.5, model: null }
}

function formatToKind(format: string | null): PartKind {
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
    default:
      return 'season'
  }
}

function sortKey(c: { seasonYear: number | null; title: string }): number {
  return (c.seasonYear ?? 9999) * 10
}

function capitalize(s: string): string {
  return s.length ? s[0]!.toUpperCase() + s.slice(1) : s
}
