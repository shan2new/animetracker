import type { DisplayNameRejection, HandleRejection } from '../types/api.js'
import { BLOCKED_TERMS, NAME_ONLY_TERMS, type BlockedTerm } from './blocklist.js'
import {
  checkNameText,
  codePointLength,
  compactReadings,
  containsBlockedTerm,
  containsBlockedTermCompact,
} from './contentFilter.js'

// The public face of an account (docs/api-contract.md, "Identity"): a handle the user picks at their
// first reply, and a first name they confirm. Pure — the IO is services/profile.ts.
//
// Neither is ever derived from the email or Clerk's display name: the client proposes, the user
// confirms, and these rules decide.

export const HANDLE_MIN_LENGTH = 3
export const HANDLE_MAX_LENGTH = 20
export const DISPLAY_NAME_MAX_CODE_POINTS = 40

/** Names that would read as the app, its staff, or a system state if a user wore them. */
export const RESERVED_HANDLES: ReadonlySet<string> = new Set([
  'admin',
  'administrator',
  'root',
  'system',
  'support',
  'help',
  'staff',
  'team',
  'mod',
  'moderator',
  'moderation',
  'official',
  'previously',
  'anitrack',
  'app',
  'api',
  'www',
  'null',
  'undefined',
  'me',
  'you',
  'everyone',
  'here',
  'anonymous',
  'deleted',
  'unknown',
  'notifications',
  'settings',
  'profile',
  'feed',
  'today',
  'discover',
  'apple',
  'clerk',
  'security',
  'abuse',
  'legal',
  'privacy',
  'terms',
  'rules',
])

/**
 * Prefixes no handle may start with. `mod` itself is only reserved with a separator after it
 * ("mod.x", "mod_x"), so "modern" and "modest" stay available.
 */
export const RESERVED_HANDLE_PREFIXES: readonly string[] = [
  'previously',
  'anitrack',
  'official',
  'admin',
  'support',
  'mod.',
  'mod_',
]

/** Names refuse the name-only profanity list as well as the slurs every text refuses. */
const NAME_TERMS: readonly BlockedTerm[] = [...BLOCKED_TERMS, ...NAME_ONLY_TERMS]

/**
 * A handle is one token, so a blocked term of this many folded characters or more is refused
 * ANYWHERE in it (`containsBlockedTermCompact`), not only as a whole word. Shorter terms stay
 * whole-word: three letters occur inside too many ordinary words.
 */
export const HANDLE_COMPACT_TERM_MIN_LENGTH = 4

/**
 * Ordinary words that happen to contain a blocked term of four letters or more, cut out of a handle
 * before the anywhere-match so they stay available ("grape_soda", "peacock", "analog_kid"). Each is
 * an everyday word in its own right; a handle that sets the term apart with a separator (one letter,
 * `_`, then the term) is still refused by the whole-word check, which reads `.`/`_` as breaks.
 * Reviewed 25 Sep 2026; widen it with a human, never shrink the blocklist to make room instead.
 */
export const HANDLE_INNOCENT_WORDS: readonly string[] = [
  'analog',
  'analogue',
  'analysis',
  'analyst',
  'analytic',
  'banal',
  'canal',
  'cockatiel',
  'cockatoo',
  'cockpit',
  'cockroach',
  'custard',
  'dickens',
  'dickinson',
  'drape',
  'grape',
  'hancock',
  'hitchcock',
  'hospice',
  'leotard',
  'mustard',
  'pakistan',
  'parapet',
  'peacock',
  'pedometer',
  'penistone',
  'prickle',
  'prickly',
  'scrape',
  'scunthorpe',
  'shitsuji', // Kuroshitsuji (Black Butler)
  'shuttlecock',
  'spice',
  'spicy',
  'stardust',
  'swank',
  'tardis',
  'therapist',
  'thorny',
  'torpedo',
  'trapeze',
]

/**
 * Words a DISPLAY NAME may not contain as a token (a plural too, leet-folded), nor spell out with
 * separators ("A.d.m.i.n"): the app, its staff and a system voice, and the brands whose news or data
 * the feed carries. A name sits beside every reply, so "Previously Support" or "Crunchyroll" would
 * read as the official voice. Brands reviewed 25 Sep 2026: the catalogue and data providers the app
 * names, and the streamers and publishers the feed's news most often comes from.
 */
export const RESERVED_NAME_WORDS: readonly string[] = [
  'previously',
  'anitrack',
  'admin',
  'administrator',
  'moderator',
  'mod',
  'official',
  'support',
  'staff',
  'team',
  'system',
  'security',
  // Brands.
  'anilist',
  'tmdb',
  'justwatch',
  'myanimelist',
  'crunchyroll',
  'funimation',
  'hidive',
  'netflix',
  'aniplex',
]

const RESERVED_NAME_TERMS: readonly BlockedTerm[] = RESERVED_NAME_WORDS.map((term) => ({ term, match: 'word' }))

/** A reserved word as a token of the name, or the whole name spelling one out with separators. */
function isReservedName(name: string): boolean {
  if (containsBlockedTerm(name, RESERVED_NAME_TERMS)) return true
  return compactReadings(name).some((reading) => RESERVED_NAME_WORDS.includes(reading))
}

/** Trim, drop ONE leading `@`, lowercase. What the user typed, in the form handles are stored in. */
export function normalizeHandle(raw: string): string {
  const trimmed = raw.trim()
  return (trimmed.startsWith('@') ? trimmed.slice(1) : trimmed).toLowerCase()
}

function isReserved(h: string): boolean {
  if (RESERVED_HANDLES.has(h)) return true
  return RESERVED_HANDLE_PREFIXES.some((prefix) => h.startsWith(prefix))
}

/**
 * A handle, checked in order and stopping at the first failure: `length` (3–20), `characters`
 * (`[a-z0-9_.]` only), `dots` (no leading, trailing or doubled `.`), `no_letter`, `reserved`,
 * `blocked_term`. On success the NORMALISED handle is what gets stored and compared.
 *
 * Reserved words are also matched with the separators removed, so `a.dmin` and `_admin_` cannot
 * stand in for `admin`. The blocked-term check reads the handle with `.`/`_` as word breaks
 * ("zz_badword") and as written, so both a spaced and a run-together term are caught; and a term of
 * `HANDLE_COMPACT_TERM_MIN_LENGTH`+ folded letters is refused anywhere in the handle with the
 * separators removed ("xzzbadwordx"), once the `innocent` words are cut out.
 */
export function checkHandle(
  raw: string,
  terms: readonly BlockedTerm[] = NAME_TERMS,
  innocent: readonly string[] = HANDLE_INNOCENT_WORDS,
): { ok: true; handle: string } | { ok: false; reason: HandleRejection } {
  const h = normalizeHandle(raw)
  const length = codePointLength(h)
  if (length < HANDLE_MIN_LENGTH || length > HANDLE_MAX_LENGTH) return { ok: false, reason: 'length' }
  if (!/^[a-z0-9_.]+$/.test(h)) return { ok: false, reason: 'characters' }
  if (h.startsWith('.') || h.endsWith('.') || h.includes('..')) return { ok: false, reason: 'dots' }
  if (!/[a-z]/.test(h)) return { ok: false, reason: 'no_letter' }
  if (isReserved(h) || isReserved(h.replace(/[._]/g, ''))) return { ok: false, reason: 'reserved' }
  if (
    containsBlockedTerm(h.replace(/[._]/g, ' '), terms) ||
    containsBlockedTerm(h, terms) ||
    containsBlockedTermCompact(h, terms, { minLength: HANDLE_COMPACT_TERM_MIN_LENGTH, innocent })
  ) {
    return { ok: false, reason: 'blocked_term' }
  }
  return { ok: true, handle: h }
}

/**
 * A display name (the first name shown beside the handle), normalised to one line, then refused as
 * `empty`, `too_long` (> 40 code points), `invalid_characters`, `at_sign` (keeps emails out),
 * `link`, `no_letter`, `blocked_term` or `reserved` (`RESERVED_NAME_WORDS`: the app, its staff, a
 * brand) — first failure wins. On success the NORMALISED name is what gets stored.
 */
export function checkDisplayName(
  raw: string,
  terms: readonly BlockedTerm[] = NAME_TERMS,
): { ok: true; displayName: string } | { ok: false; reason: DisplayNameRejection } {
  const result = checkNameText(raw, DISPLAY_NAME_MAX_CODE_POINTS, terms)
  if (!result.ok) return result
  if (isReservedName(result.text)) return { ok: false, reason: 'reserved' }
  return { ok: true, displayName: result.text }
}
