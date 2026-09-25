import type { ContentRejection, DisplayNameRejection } from '../types/api.js'
import { BLOCKED_TERMS, NAME_ONLY_TERMS, type BlockedTerm } from './blocklist.js'

// The server-side content filter for user text (App Review 1.2). Pure: comments go through
// `checkCommentBody`, public names through `checkNameText` (social/identity.ts builds on it).
//
// Length is counted in Unicode CODE POINTS on both sides (iOS: `unicodeScalars.count`), after the
// normalisation below, which only removes or collapses characters — a client that counts the
// trimmed draft is not refused for length because of anything the server strips.

export const COMMENT_MAX_CODE_POINTS = 280

/** Unicode code points, not UTF-16 units: an emoji with a skin tone is 2, a flag is 2. */
export function codePointLength(s: string): number {
  return [...s].length
}

/** Zero-width and bidi controls, word joiners, the BOM and the soft hyphen. */
const INVISIBLE_RE = /[​-‏‪-‮⁠-⁩﻿­]/g
/** C0/C1 controls other than tab, LF and CR (CR is already folded into LF by normalisation). */
const CONTROL_RE = /[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F-\u009F]/

/**
 * NFC → CRLF/CR to LF → invisible and bidi controls removed → whitespace tidied (single-line:
 * every run to one space; multiline: trailing spaces before a newline dropped, 3+ newlines to 2)
 * → trimmed.
 */
export function normalizeUserText(raw: string, opts: { multiline: boolean }): string {
  let s = raw.normalize('NFC').replace(/\r\n?/g, '\n').replace(INVISIBLE_RE, '')
  if (opts.multiline) {
    s = s.replace(/[ \t]+\n/g, '\n').replace(/\n{3,}/g, '\n\n')
  } else {
    s = s.replace(/\s+/g, ' ')
  }
  return s.trim()
}

/** The common TLDs a bare domain is recognised by. */
const BARE_DOMAIN_TLDS = [
  'com', 'net', 'org', 'io', 'gg', 'tv', 'me', 'co', 'app', 'dev', 'xyz', 'ly', 'to', 'link', 'site', 'online',
  'info', 'biz', 'ru', 'cn', 'jp', 'uk', 'us', 'ai',
] as const
/**
 * A bare domain: a label in ANY case, then a TLD written all lowercase or all uppercase. The label's
 * case never mattered (iOS capitalises a sentence's first word: "Discord.gg"); only the TLD's does,
 * because a mixed-case "To"/"So" after a dot is a sentence with a missing space ("how.To").
 */
const BARE_DOMAIN_RE = new RegExp(
  `\\b[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\\.(?:${[
    ...BARE_DOMAIN_TLDS,
    ...BARE_DOMAIN_TLDS.map((tld) => tld.toUpperCase()),
  ].join('|')})\\b`,
)

/**
 * True when the text carries a link. v1 comments carry none (spam and phishing are most of what a
 * report queue would otherwise hold). The text is folded first (NFKC turns a fullwidth "．" into
 * ".", and the ideographic full stops are mapped too), then:
 * - a scheme (`https://`, `ftp://`), a `www.`, or `name.tld/path` anywhere, any case;
 * - a bare domain with a common TLD written all lowercase or all uppercase, the label in any case —
 *   "example.com", "Discord.gg" and "EXAMPLE.COM" are links, while "episode.So good" and "how.To"
 *   (a missing space before a capital) are sentences.
 */
export function containsLink(s: string): boolean {
  const folded = s.normalize('NFKC').replace(/[。｡]/g, '.')
  if (/\b(?:https?|ftp):\/\//i.test(folded)) return true
  if (/\bwww\./i.test(folded)) return true
  if (/[a-z0-9-]+\.[a-z0-9-]+\/\S/i.test(folded)) return true
  return BARE_DOMAIN_RE.test(folded)
}

const LEET: Readonly<Record<string, string>> = {
  '0': 'o',
  '1': 'i',
  '3': 'e',
  '4': 'a',
  '5': 's',
  '7': 't',
  '@': 'a',
  $: 's',
  '!': 'i',
}
const LEET_RE = /[013457@$!]/g
const SEPARATORS_RE = /[^\p{L}\p{N}]+/gu

/** NFKC → lowercase → diacritics stripped (NFD, \p{M} removed) → [leet mapped] → 3+ letter runs to 2. */
function fold(x: string, leet: boolean): string {
  let s = x.normalize('NFKC').toLowerCase().normalize('NFD').replace(/\p{M}/gu, '')
  if (leet) s = s.replace(LEET_RE, (c) => LEET[c] ?? c)
  return s.replace(/(\p{L})\1{2,}/gu, '$1$1')
}

function tokensOf(folded: string): string[] {
  return folded.split(SEPARATORS_RE).filter((t) => t.length > 0)
}

function hasRun(tokens: readonly string[], run: readonly string[]): boolean {
  if (run.length === 0 || run.length > tokens.length) return false
  outer: for (let i = 0; i + run.length <= tokens.length; i++) {
    for (let j = 0; j < run.length; j++) if (tokens[i + j] !== run[j]) continue outer
    return true
  }
  return false
}

/**
 * True when the text contains a blocked term (see social/blocklist.ts for the two match modes).
 *
 * The text is read twice: once leet-folded ("z2b4dw0rd" → "zzbadword") and once without the leet
 * map, because the map turns punctuation into letters — "zzbadword!" folds to "zzbadwordi", which
 * no whole-word check would ever match. Reading both only adds hits the spec'd fold would miss.
 */
export function containsBlockedTerm(s: string, terms: readonly BlockedTerm[] = BLOCKED_TERMS): boolean {
  if (terms.length === 0 || s.length === 0) return false
  const readings = [true, false].map((leet) => {
    const folded = fold(s, leet)
    return { leet, tokens: tokensOf(folded), compact: folded.replace(SEPARATORS_RE, '') }
  })
  for (const { term, match } of terms) {
    for (const reading of readings) {
      const t = fold(term, reading.leet)
      if (match === 'substring') {
        const needle = t.replace(SEPARATORS_RE, '')
        if (needle.length > 0 && reading.compact.includes(needle)) return true
        continue
      }
      const run = tokensOf(t)
      if (run.length === 1) {
        const w = run[0]!
        if (reading.tokens.includes(w) || reading.tokens.includes(`${w}s`)) return true
      } else if (hasRun(reading.tokens, run)) {
        return true
      }
    }
  }
  return false
}

/**
 * The text folded as `containsBlockedTerm` folds it, with every separator removed — once with the
 * leet map and once without (deduplicated). "A.d-m1n" reads as ["admin", "adm1n"].
 */
export function compactReadings(s: string): string[] {
  return [...new Set([true, false].map((leet) => fold(s, leet).replace(SEPARATORS_RE, '')))]
}

/**
 * True when a blocked term of at least `minLength` folded characters occurs ANYWHERE in `s` with the
 * separators removed, whatever the term's own match mode. This is the reading for a handle: a handle
 * is one token, so a slur run into anything else ("xslurx", "slur123") escapes every whole-word
 * check. Shorter terms are left to the whole-word checks, where they cannot hit ordinary words.
 *
 * `innocent` words — ordinary words that merely contain a term — are cut out of each reading first,
 * each cut leaving a break, so a cut can never join its two sides into a new hit.
 */
export function containsBlockedTermCompact(
  s: string,
  terms: readonly BlockedTerm[],
  opts: { minLength: number; innocent?: readonly string[] },
): boolean {
  if (terms.length === 0 || s.length === 0) return false
  for (const leet of [true, false]) {
    let segments = [fold(s, leet).replace(SEPARATORS_RE, '')]
    for (const word of opts.innocent ?? []) {
      const cut = fold(word, leet).replace(SEPARATORS_RE, '')
      if (cut.length > 0) segments = segments.flatMap((segment) => segment.split(cut))
    }
    for (const { term } of terms) {
      const needle = fold(term, leet).replace(SEPARATORS_RE, '')
      if (needle.length >= opts.minLength && segments.some((segment) => segment.includes(needle))) return true
    }
  }
  return false
}

/**
 * A comment body: normalised (multiline), then refused as `empty`, `invalid_characters`,
 * `too_long` (> 280 code points), `link`, or `blocked_term` — first failure wins. On success the
 * NORMALISED text is what gets stored.
 */
export function checkCommentBody(
  raw: string,
  terms: readonly BlockedTerm[] = BLOCKED_TERMS,
): { ok: true; text: string } | { ok: false; reason: ContentRejection } {
  const text = normalizeUserText(raw, { multiline: true })
  if (text.length === 0) return { ok: false, reason: 'empty' }
  if (CONTROL_RE.test(text)) return { ok: false, reason: 'invalid_characters' }
  if (codePointLength(text) > COMMENT_MAX_CODE_POINTS) return { ok: false, reason: 'too_long' }
  if (containsLink(text)) return { ok: false, reason: 'link' }
  if (containsBlockedTerm(text, terms)) return { ok: false, reason: 'blocked_term' }
  return { ok: true, text }
}

/**
 * A public name (a display name): normalised single-line, then refused as `empty`, `too_long`
 * (> `max` code points), `invalid_characters`, `at_sign` (keeps emails out), `link`, `no_letter`,
 * or `blocked_term` (slurs AND the name-only profanity list) — first failure wins.
 */
export function checkNameText(
  raw: string,
  max: number,
  terms: readonly BlockedTerm[] = [...BLOCKED_TERMS, ...NAME_ONLY_TERMS],
): { ok: true; text: string } | { ok: false; reason: DisplayNameRejection } {
  const text = normalizeUserText(raw, { multiline: false })
  if (text.length === 0) return { ok: false, reason: 'empty' }
  if (codePointLength(text) > max) return { ok: false, reason: 'too_long' }
  if (CONTROL_RE.test(text)) return { ok: false, reason: 'invalid_characters' }
  if (text.includes('@') || text.includes('＠')) return { ok: false, reason: 'at_sign' }
  if (containsLink(text)) return { ok: false, reason: 'link' }
  if (!/\p{L}/u.test(text)) return { ok: false, reason: 'no_letter' }
  if (containsBlockedTerm(text, terms)) return { ok: false, reason: 'blocked_term' }
  return { ok: true, text }
}
