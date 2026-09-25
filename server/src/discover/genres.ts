import type { DiscoverGenre, MediaSource } from '../types/api.js'

// Discover's canonical genre vocabulary (brief §17, server spec §10.1). Pure: no IO, no clock.
//
// One key per genre across both catalogues. The names are catalogue data exactly as
// `franchise.genres` stores them: AniList's genre names for anime (grouping/service.ts) and TMDB's
// TV genre names for general TV (tmdb/mapping.ts). TMDB folds some genres together ("Action &
// Adventure", "Sci-Fi & Fantasy"), so one TMDB name can feed two keys; a key with no counterpart in
// a catalogue has an empty list there and is simply absent from that scope.
//
// Membership is SOURCE-AWARE: an anime franchise joins a key through its AniList names only and a TV
// franchise through its TMDB names only, so a TV show can never land under "Romance" (a key with no
// TMDB name) by carrying a stray name from the other catalogue's vocabulary.

export interface GenreDef {
  /** Stable, URL-safe: the path segment of GET /discover/genres/:key. */
  key: string
  /** English display name (catalogue data; localising it is a client concern). */
  name: string
  /** AniList genre names that place an anime franchise under this key. */
  anilist: string[]
  /** TMDB TV genre names that place a TV franchise under this key. */
  tmdb: string[]
}

/**
 * Catalogue genres that are never a Discover genre, in any scope. Ecchi and Hentai are adult-adjacent
 * (adult titles are filtered out separately, by `enrichment.isAdult`); News, Soap and Talk are TMDB
 * programming types, not something anyone browses a tracker for.
 */
export const EXCLUDED_SOURCE_GENRES: ReadonlySet<string> = new Set(['Ecchi', 'Hentai', 'News', 'Soap', 'Talk'])

export const GENRES: readonly GenreDef[] = Object.freeze([
  { key: 'action', name: 'Action', anilist: ['Action'], tmdb: ['Action & Adventure'] },
  { key: 'adventure', name: 'Adventure', anilist: ['Adventure'], tmdb: ['Action & Adventure'] },
  { key: 'comedy', name: 'Comedy', anilist: ['Comedy'], tmdb: ['Comedy'] },
  { key: 'drama', name: 'Drama', anilist: ['Drama'], tmdb: ['Drama'] },
  { key: 'fantasy', name: 'Fantasy', anilist: ['Fantasy'], tmdb: ['Sci-Fi & Fantasy'] },
  { key: 'sci-fi', name: 'Sci-Fi', anilist: ['Sci-Fi'], tmdb: ['Sci-Fi & Fantasy'] },
  { key: 'mystery', name: 'Mystery', anilist: ['Mystery'], tmdb: ['Mystery'] },
  { key: 'romance', name: 'Romance', anilist: ['Romance'], tmdb: [] },
  { key: 'horror', name: 'Horror', anilist: ['Horror'], tmdb: [] },
  { key: 'thriller', name: 'Thriller', anilist: ['Thriller'], tmdb: [] },
  { key: 'psychological', name: 'Psychological', anilist: ['Psychological'], tmdb: [] },
  { key: 'supernatural', name: 'Supernatural', anilist: ['Supernatural'], tmdb: [] },
  { key: 'slice-of-life', name: 'Slice of Life', anilist: ['Slice of Life'], tmdb: [] },
  { key: 'sports', name: 'Sports', anilist: ['Sports'], tmdb: [] },
  { key: 'mecha', name: 'Mecha', anilist: ['Mecha'], tmdb: [] },
  { key: 'music', name: 'Music', anilist: ['Music'], tmdb: [] },
  { key: 'mahou-shoujo', name: 'Mahou Shoujo', anilist: ['Mahou Shoujo'], tmdb: [] },
  { key: 'crime', name: 'Crime', anilist: [], tmdb: ['Crime'] },
  { key: 'documentary', name: 'Documentary', anilist: [], tmdb: ['Documentary'] },
  { key: 'family', name: 'Family', anilist: [], tmdb: ['Family', 'Kids'] },
  { key: 'reality', name: 'Reality', anilist: [], tmdb: ['Reality'] },
  { key: 'war-politics', name: 'War & Politics', anilist: [], tmdb: ['War & Politics'] },
  { key: 'western', name: 'Western', anilist: [], tmdb: ['Western'] },
  { key: 'animation', name: 'Animation', anilist: [], tmdb: ['Animation'] },
].map((def) => Object.freeze({ ...def, anilist: Object.freeze(def.anilist), tmdb: Object.freeze(def.tmdb) }) as GenreDef))

// A Map, not an object lookup: `genreByKey('constructor')` must be null, not Object's prototype.
const BY_KEY: ReadonlyMap<string, GenreDef> = new Map(GENRES.map((def) => [def.key, def]))

/** The genre for a path key (exact, lowercase), or null for anything that is not one of ours. */
export function genreByKey(key: string): GenreDef | null {
  return BY_KEY.get(key) ?? null
}

/** The sources a scope covers: one catalogue, or both for All (null). */
export function scopeSources(source: MediaSource | null): MediaSource[] {
  return source ? [source] : ['anilist', 'tmdb']
}

/**
 * The catalogue genre names that place a franchise of `source` under `def`; for All (null), the union
 * of both catalogues' names (AniList's first, deduped). Never returns an excluded name.
 */
export function sourceGenreNames(def: GenreDef, source: MediaSource | null): string[] {
  const names = scopeSources(source).flatMap((s) => (s === 'anilist' ? def.anilist : def.tmdb))
  return [...new Set(names)].filter((name) => !EXCLUDED_SOURCE_GENRES.has(name))
}

/** The genres that can hold anything at all in a scope (at least one catalogue name there). */
export function genresInScope(source: MediaSource | null): GenreDef[] {
  return GENRES.filter((def) => sourceGenreNames(def, source).length > 0)
}

// ---------- The genre list (GET /discover/genres) ----------

/** A genre needs this many qualifying franchises to be offered as a tile. */
export const MIN_GENRE_COUNT = 3
/** Portrait URLs on a tile's collage. */
export const POSTERS_PER_GENRE = 4

/**
 * Every genre in scope as a tile, before the `MIN_GENRE_COUNT` cut (the genre page uses the uncut
 * list for its header, so a small genre reached by key still reports its real count).
 *
 * @param totals     qualifying franchises per key (a key with none may be absent)
 * @param rankedIds  per key, franchise ids in trending order (more than four is fine: a franchise
 *                   without a portrait is skipped so the collage still fills)
 * @param portraitOf `images.portrait` per franchise id (null/absent = no poster)
 */
export function buildGenreTiles(
  source: MediaSource | null,
  totals: ReadonlyMap<string, number>,
  rankedIds: ReadonlyMap<string, readonly string[]>,
  portraitOf: ReadonlyMap<string, string | null>,
): DiscoverGenre[] {
  return genresInScope(source).map((def) => {
    const posters: string[] = []
    for (const id of rankedIds.get(def.key) ?? []) {
      if (posters.length >= POSTERS_PER_GENRE) break
      const url = portraitOf.get(id)
      if (url && !posters.includes(url)) posters.push(url)
    }
    return { key: def.key, name: def.name, count: Math.max(0, totals.get(def.key) ?? 0), posters }
  })
}

/** The tiles a client is offered: `count >= MIN_GENRE_COUNT`, most titles first, then by key. */
export function rankGenreTiles(tiles: readonly DiscoverGenre[]): DiscoverGenre[] {
  return tiles
    .filter((tile) => tile.count >= MIN_GENRE_COUNT)
    .sort((a, b) => b.count - a.count || (a.key < b.key ? -1 : a.key > b.key ? 1 : 0))
}

// ---------- The genre page cursor ----------
//
// Opaque to clients: base64url of `{ "o": offset }`. Offset paging is deliberate for a browse list
// whose ranking moves hourly (spec §10.2); clients dedupe by id across pages.

/** Deep enough for any real catalogue; a larger offset is not a cursor this server wrote. */
export const MAX_GENRE_OFFSET = 10_000
const MAX_CURSOR_LENGTH = 64

export function encodeGenreCursor(offset: number): string {
  return Buffer.from(JSON.stringify({ o: offset }), 'utf8').toString('base64url')
}

/** The offset a cursor carries, or null for anything malformed (the route answers 400). */
export function decodeGenreCursor(cursor: string): number | null {
  if (typeof cursor !== 'string' || cursor.length === 0 || cursor.length > MAX_CURSOR_LENGTH) return null
  // Node's base64url decoder silently skips characters outside the alphabet; refuse them instead.
  if (!/^[A-Za-z0-9_-]+$/.test(cursor)) return null
  let value: unknown
  try {
    value = JSON.parse(Buffer.from(cursor, 'base64url').toString('utf8'))
  } catch {
    return null
  }
  if (typeof value !== 'object' || value === null || Array.isArray(value)) return null
  const keys = Object.keys(value)
  if (keys.length !== 1 || keys[0] !== 'o') return null
  const offset = (value as { o: unknown }).o
  if (typeof offset !== 'number' || !Number.isInteger(offset) || offset < 0 || offset > MAX_GENRE_OFFSET) return null
  return offset
}
