import { containsBlockedTerm } from '../social/contentFilter.js'
import type { FeedSource, StoryBeat } from '../types/api.js'
import type { ComposeEvidence, ComposeObservation } from './compose.js'
import { parseEvidenceDate, safeHttpsUrl, sanitizeEvidence, tierRank } from './evidence.js'

// The trail behind a post, for the thread page: one beat per day of reporting, and the full list of
// sources. Ports the spike's `storyline`/`slugHeadline` (FeedSpikeModel.swift:557-601) and the
// thread page's source list (FeedSpikeThread.swift:484-494). Pure; `nowMs` only bounds dates.

const MAX_BEATS = 6

const SMALL_WORDS = new Set(['a', 'an', 'the', 'of', 'in', 'on', 'at', 'for', 'to', 'and', 'with', 'from', 'by', 'as', 'vs'])
const ACRONYMS = new Set(['tv', 'pv', 'hbo', 'jst', 'mappa', 'ufotable', 'adn', 'sdcc'])

const compareText = (a: string, b: string): number => (a < b ? -1 : a > b ? 1 : 0)

/** yyyymmdd of an instant, in UTC (a date-only report sits at 12:00 UTC, so it keeps its day). */
function utcDayKey(ms: number): string {
  const d = new Date(ms)
  const pad = (n: number) => String(n).padStart(2, '0')
  return `${d.getUTCFullYear()}${pad(d.getUTCMonth() + 1)}${pad(d.getUTCDate())}`
}

/** The unique evidence of a thread by URL, https only, in the order the observations are given. */
function uniqueEvidence(observations: readonly ComposeObservation[]): ComposeEvidence[] {
  const byUrl = new Map<string, ComposeEvidence>()
  for (const o of observations) {
    for (const e of sanitizeEvidence(o.evidence)) if (!byUrl.has(e.url)) byUrl.set(e.url, e)
  }
  return [...byUrl.values()]
}

/**
 * "https://x.com/news/sakamoto-days-season-2-returns-january-2027" → "Sakamoto Days Season 2
 * Returns January 2027". Null when the address carries no sentence: an encyclopedia id, a status
 * URL, or a slug of fewer than four words — and when its words carry a blocked term.
 */
export function slugHeadline(url: string): string | null {
  let parsed: URL
  try {
    parsed = new URL(url)
  } catch {
    return null
  }
  const segments = parsed.pathname
    .split('/')
    .filter((segment) => segment !== '')
    .map((segment) => {
      try {
        return decodeURIComponent(segment)
      } catch {
        return segment
      }
    })

  // The FIRST segment with the most hyphens is the article's slug; it needs at least three.
  let slug: string | null = null
  let most = 0
  for (const segment of segments) {
    const hyphens = segment.split('-').length - 1
    if (hyphens > most) {
      most = hyphens
      slug = segment
    }
  }
  if (slug == null || most < 3) return null

  const dot = slug.indexOf('.')
  if (dot >= 0) slug = slug.slice(0, dot)
  const words = slug.split('-').filter((word) => word !== '')
  // A trailing article id ("-2026091512") is not part of the sentence; a year (four digits) is.
  while (words.length > 0 && /^\p{N}+$/u.test(words[words.length - 1]!) && [...words[words.length - 1]!].length > 4) {
    words.pop()
  }
  if (words.length < 4) return null

  // An id is not a sentence: "entity-f1c31566-ec05-4d30-…" mixes letters and digits in its words.
  const mixed = words.filter((w) => [...w].length >= 4 && /\p{N}/u.test(w) && /\p{L}/u.test(w))
  if (mixed.length >= 2 || words[0]!.toLowerCase() === 'entity') return null

  const headline = words
    .map((word, i) => {
      const lower = word.toLowerCase()
      if (i > 0 && SMALL_WORDS.has(lower)) return lower
      if (ACRONYMS.has(lower)) return lower.toUpperCase()
      const [first = '', ...rest] = [...lower]
      return first.toUpperCase() + rest.join('')
    })
    .join(' ')
  // The address is the agent's pick of page; its words are printed as a headline under the brand,
  // so a slug that carries a blocked term is no headline.
  return containsBlockedTerm(headline) ? null : headline
}

/**
 * Every dated report behind a post, one beat per UTC day, oldest first, the last six. A beat is
 * led by the day's strongest voice that has a readable headline in its URL. Catalogue entries and
 * undated reports are not reporting.
 *
 * `thread` is newest first (as composed); the evidence is collected oldest observation first.
 */
export function storyline(thread: readonly ComposeObservation[], nowMs: number): StoryBeat[] {
  const byDay = new Map<string, { e: ComposeEvidence; ms: number }[]>()
  for (const e of uniqueEvidence([...thread].reverse())) {
    if (e.tier === 'catalogue') continue
    const date = parseEvidenceDate(e.publishedAt, nowMs)
    if (!date) continue
    const key = utcDayKey(date.ms)
    const day = byDay.get(key) ?? []
    day.push({ e, ms: date.ms })
    byDay.set(key, day)
  }

  const beats: StoryBeat[] = []
  for (const [id, items] of byDay) {
    const sorted = [...items].sort(
      (a, b) =>
        (a.e.primary ? 0 : 1) - (b.e.primary ? 0 : 1) ||
        tierRank(a.e.tier) - tierRank(b.e.tier) ||
        compareText(a.e.url, b.e.url),
    )
    const lead = sorted.find((item) => slugHeadline(item.e.url) != null) ?? sorted[0]!
    const publishers: string[] = []
    const seen = new Set<string>()
    for (const item of sorted) {
      const name = item.e.publisher?.trim() ?? ''
      if (name === '' || seen.has(name.toLowerCase())) continue
      seen.add(name.toLowerCase())
      publishers.push(name)
    }
    beats.push({
      id,
      day: lead.ms,
      publishers,
      official: sorted.some((item) => item.e.tier === 'official'),
      primary: sorted.some((item) => item.e.primary),
      headline: slugHeadline(lead.e.url),
      url: safeHttpsUrl(lead.e.url),
    })
  }
  return beats.sort((a, b) => a.day - b.day || compareText(a.id, b.id)).slice(-MAX_BEATS)
}

/**
 * The thread page's "Sources": every https link across the thread once, named by its publisher
 * (else its host), primary announcements first, then newest, then URL.
 */
export function threadSources(thread: readonly ComposeObservation[], nowMs: number): FeedSource[] {
  const items = uniqueEvidence(thread).map((e): FeedSource => {
    const date = parseEvidenceDate(e.publishedAt, nowMs)
    let publisher = e.publisher?.trim() ?? ''
    if (publisher === '') {
      try {
        publisher = new URL(e.url).hostname
      } catch {
        publisher = e.url
      }
    }
    return {
      publisher,
      tier: e.tier,
      url: safeHttpsUrl(e.url),
      publishedAt: date?.ms ?? null,
      dateOnly: date?.dateOnly ?? false,
      primary: e.primary,
    }
  })
  return items.sort((a, b) => {
    const primary = (a.primary ? 0 : 1) - (b.primary ? 0 : 1)
    if (primary !== 0) return primary
    if (a.publishedAt !== b.publishedAt) {
      if (a.publishedAt == null) return 1
      if (b.publishedAt == null) return -1
      return b.publishedAt - a.publishedAt
    }
    return compareText(a.url ?? '', b.url ?? '')
  })
}
