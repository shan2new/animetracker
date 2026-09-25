import { containsBlockedTerm, containsLink, normalizeUserText } from '../social/contentFilter.js'
import type { AnnouncementEvidenceTier, FeedSource } from '../types/api.js'
import { isOfficialHost } from './officialHosts.js'

// Evidence hygiene for the Today feed. Research output is untrusted (the agent can return any
// string as a URL or a date), so every rule that reads evidence reads it through here: only https
// links survive, an "official" claim holds only on a reviewed official host, a publisher name that
// carries a link or a blocked term is replaced by the page's host, and a "published" date more
// than a day in the future is not a date. Agent-written words the feed prints (the installment,
// the release, the note) go through `sanitizeAgentText`.

const DAY_MS = 86_400_000
/** Evidence dated further ahead than this is ignored (D6): nobody reports tomorrow's news today. */
export const FUTURE_TOLERANCE_MS = DAY_MS
const MAX_URL_LENGTH = 2048
const MAX_SOURCES = 8

/** Voice first: the show's own studio/network/streamer, then trade press, then the rest. */
export const TIER_RANK: Readonly<Record<AnnouncementEvidenceTier, number>> = {
  official: 0,
  trade: 1,
  reputable: 2,
  unknown: 3,
  catalogue: 4,
}

/** `TIER_RANK`, with a tier the table does not know ranking after every known one. */
export function tierRank(tier: string): number {
  return (TIER_RANK as Readonly<Record<string, number>>)[tier] ?? 5
}

/**
 * `u` itself when it is a well-formed https URL with a host, no credentials, no whitespace or
 * control characters, and at most 2048 chars; otherwise null. `javascript:`, `http:`, custom
 * schemes and `https://user:pass@…` never reach a client.
 */
export function safeHttpsUrl(u: string | null | undefined): string | null {
  if (typeof u !== 'string' || u.length === 0 || u.length > MAX_URL_LENGTH) return null
  // `new URL` quietly trims and percent-encodes; a URL that needed that is not one a client can
  // open as given, so it is refused rather than repaired.
  if (/[\u0000- \u007f-\u009f]/.test(u)) return null
  let parsed: URL
  try {
    parsed = new URL(u)
  } catch {
    return null
  }
  if (parsed.protocol !== 'https:') return null
  if (parsed.hostname === '' || parsed.username !== '' || parsed.password !== '') return null
  return u
}

// ---------- Agent-written text ----------

/** The longest agent-written strings the feed prints, in code points. */
export const AGENT_TEXT_LIMITS = { installment: 60, publisher: 60, release: 60, note: 600 } as const

/** C0/C1 controls that are not whitespace (whitespace is folded to one space instead). */
const NON_SPACE_CONTROLS = /[\u0000-\u0008\u000e-\u001f\u007f-\u009f]/g

/** True when agent text may be printed under the brand: it carries no link and no blocked term. */
export function isCleanAgentText(s: string): boolean {
  return !containsLink(s) && !containsBlockedTerm(s)
}

/** At most `max` code points; a longer text is cut on a word boundary with an ellipsis. */
function capCodePoints(s: string, max: number): string {
  const points = [...s]
  if (points.length <= max) return s
  let cut = points.slice(0, Math.max(1, max - 1)).join('')
  const boundary = cut.lastIndexOf(' ')
  if (boundary > 0) cut = cut.slice(0, boundary)
  return `${cut.trimEnd()}…`
}

type AgentText = { ok: true; text: string } | { ok: false; reason: 'empty' | 'rejected' }

function readAgentText(s: string | null | undefined, max: number): AgentText {
  if (typeof s !== 'string') return { ok: false, reason: 'empty' }
  const text = normalizeUserText(s.replace(NON_SPACE_CONTROLS, ''), { multiline: false })
  if (text === '') return { ok: false, reason: 'empty' }
  if (!isCleanAgentText(text)) return { ok: false, reason: 'rejected' }
  return { ok: true, text: capCodePoints(text, max) }
}

/**
 * One line of research-agent text as the feed may print it: normalised to a single line (NFC,
 * invisible and control characters removed, whitespace folded), capped at `maxCodePoints`. Null
 * when nothing is left, or when it carries a link or a blocked term — the agent reads arbitrary
 * pages, and nothing it copied from one is printed under the brand unfiltered.
 */
export function sanitizeAgentText(s: string | null | undefined, maxCodePoints: number): string | null {
  const read = readAgentText(s, maxCodePoints)
  return read.ok ? read.text : null
}

/** The host a publisher-less (or refused) source is named by. Null for a host that is itself refused. */
function hostName(url: string): string | null {
  try {
    const host = new URL(url).hostname
    return host === '' || containsBlockedTerm(host) ? null : host
  } catch {
    return null
  }
}

/**
 * The publisher name the feed prints: the agent's own, cleaned; the page's host when that name
 * carried a link or a blocked term; null when there was no name (so `rankSources` still drops a
 * nameless entry and `threadSources` still names it by its host).
 */
function sanitizePublisher(publisher: string | null, url: string): string | null {
  const read = readAgentText(publisher, AGENT_TEXT_LIMITS.publisher)
  if (read.ok) return read.text
  return read.reason === 'rejected' ? hostName(url) : null
}

/**
 * The tier the feed trusts. An `official` claim holds only when the URL is on a reviewed official
 * host (feed/officialHosts.ts); anywhere else it reads as `reputable`, so a page that calls itself
 * "Netflix" cannot put the gold check on a post. Every other tier is kept as claimed (a claim below
 * official never gains the check).
 */
export function verifiedTier(url: string, claimed: AnnouncementEvidenceTier): AnnouncementEvidenceTier {
  if (claimed !== 'official') return claimed
  return isOfficialHost(url) ? 'official' : 'reputable'
}

/**
 * Drops every entry whose URL is not a safe https link (D6), verifies an `official` tier against
 * its host, and cleans the publisher name. Runs before any other rule reads evidence; idempotent.
 */
export function sanitizeEvidence<E extends { url: string; tier?: string; publisher?: string | null }>(
  list: readonly E[],
): E[] {
  const out: E[] = []
  for (const entry of list) {
    if (safeHttpsUrl(entry.url) == null) continue
    let next = entry
    if (entry.tier === 'official' && verifiedTier(entry.url, 'official') !== 'official') {
      next = { ...next, tier: 'reputable' } as E
    }
    if (typeof entry.publisher === 'string') {
      const publisher = sanitizePublisher(entry.publisher, entry.url)
      if (publisher !== entry.publisher) next = { ...next, publisher } as E
    }
    out.push(next)
  }
  return out
}

export interface EvidenceDate {
  ms: number
  /** True when only a calendar day was given; `ms` is then 12:00 UTC of that day. */
  dateOnly: boolean
}

const ISO_INSTANT =
  /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,9}))?(Z|[+-]\d{2}:?\d{2})$/
const DATE_PREFIX = /^(\d{4})-(\d{1,2})-(\d{1,2})/

const validYear = (y: number): boolean => y >= 1900 && y <= 2100

/** The instant for a calendar date, or null when the date does not exist (Feb 30, month 13). */
function utcIfReal(y: number, m: number, d: number, h: number, mi: number, s: number, ms: number): number | null {
  if (!validYear(y) || m < 1 || m > 12 || d < 1 || d > 31) return null
  if (h > 23 || mi > 59 || s > 59) return null
  const at = Date.UTC(y, m - 1, d, h, mi, s, ms)
  const back = new Date(at)
  if (back.getUTCFullYear() !== y || back.getUTCMonth() !== m - 1 || back.getUTCDate() !== d) return null
  return at
}

function parseInstant(s: string): number | null {
  const hit = ISO_INSTANT.exec(s)
  if (!hit) return null
  const [y, mo, d, h, mi, sec] = [1, 2, 3, 4, 5, 6].map((i) => Number(hit[i]))
  const fraction = hit[7] ? Number(hit[7].slice(0, 3).padEnd(3, '0')) : 0
  const local = utcIfReal(y!, mo!, d!, h!, mi!, sec!, fraction)
  if (local == null) return null
  const zone = hit[8]!
  if (zone === 'Z') return local
  const sign = zone.startsWith('-') ? -1 : 1
  const digits = zone.slice(1).replace(':', '')
  const oh = Number(digits.slice(0, 2))
  const om = Number(digits.slice(2, 4))
  if (oh > 23 || om > 59) return null
  return local - sign * (oh * 60 + om) * 60_000
}

/**
 * A research date, the port of the spike's `FeedTime.parse` (FeedSpikeModel.swift:98-108):
 * an ISO-8601 instant (fractional seconds optional, `Z` or an offset), else a `YYYY-MM-DD` prefix
 * read at 12:00 UTC so no time zone moves its day. The year must be 1900–2100 and the date must
 * exist (Feb 30 is refused, where Swift would roll it over). Null for anything else, and — added
 * over the spike (D6) — for a date more than 24 h after `nowMs`.
 */
export function parseEvidenceDate(s: string | null | undefined, nowMs: number): EvidenceDate | null {
  if (typeof s !== 'string') return null
  const text = s.trim()
  if (text === '') return null
  let parsed: EvidenceDate | null = null
  const instant = parseInstant(text)
  if (instant != null) {
    parsed = { ms: instant, dateOnly: false }
  } else {
    const hit = DATE_PREFIX.exec(text.slice(0, 10))
    if (hit) {
      const at = utcIfReal(Number(hit[1]), Number(hit[2]), Number(hit[3]), 12, 0, 0, 0)
      if (at != null) parsed = { ms: at, dateOnly: true }
    }
  }
  if (!parsed) return null
  if (parsed.ms > nowMs + FUTURE_TOLERANCE_MS) return null
  return parsed
}

/** One piece of evidence as `rankSources` reads it: the stored row plus when research saw it. */
export interface RankableEvidence {
  url: string
  publisher: string | null
  publishedAt: string | null
  tier: AnnouncementEvidenceTier
  primary: boolean
  observedAt: number
}

/**
 * The post's sources, lead first (the spike's `sources()`, FeedSpikeModel.swift:704-716):
 * primary announcements first, then by tier, then newest observation, then URL (the last two are
 * the deterministic tie-break the spike lacked). Publisher-less entries are dropped and a
 * publisher appears once. Catalogue entries (AniList/TMDB) survive only when nothing editorial
 * does. At most eight.
 */
export function rankSources(evidence: readonly RankableEvidence[], nowMs: number): FeedSource[] {
  const sorted = [...evidence].sort(
    (a, b) =>
      (a.primary ? 0 : 1) - (b.primary ? 0 : 1) ||
      tierRank(a.tier) - tierRank(b.tier) ||
      b.observedAt - a.observedAt ||
      (a.url < b.url ? -1 : a.url > b.url ? 1 : 0),
  )
  const seen = new Set<string>()
  const items: FeedSource[] = []
  for (const entry of sorted) {
    const publisher = entry.publisher?.trim() ?? ''
    if (publisher === '') continue
    const key = publisher.toLowerCase()
    if (seen.has(key)) continue
    seen.add(key)
    const date = parseEvidenceDate(entry.publishedAt, nowMs)
    items.push({
      publisher,
      tier: entry.tier,
      url: safeHttpsUrl(entry.url),
      publishedAt: date?.ms ?? null,
      dateOnly: date?.dateOnly ?? false,
      primary: entry.primary,
    })
  }
  const editorial = items.filter((item) => item.tier !== 'catalogue')
  return (editorial.length > 0 ? editorial : items).slice(0, MAX_SOURCES)
}
