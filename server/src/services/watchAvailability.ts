import { eq } from 'drizzle-orm'
import { db } from '../db/index.js'
import { franchise, franchiseMember, media } from '../db/schema.js'
import {
  getMovieWatchProviders,
  getTvWatchProviders,
  searchMovies,
  searchTv,
  tmdbEnabled,
  type TmdbRequestOptions,
} from '../tmdb/client.js'
import type {
  TmdbMovieSearchResult,
  TmdbSearchResult,
  TmdbWatchProvider,
  TmdbWatchProviderMarket,
} from '../tmdb/types.js'
import type {
  WatchAccess,
  WatchAvailability,
  WatchAvailabilityStatus,
  WatchProvider,
} from '../types/api.js'

const CACHE_TTL_MS = 12 * 60 * 60 * 1000
const MISS_TTL_MS = 60 * 60 * 1000
const MAX_CACHE_ENTRIES = 500
const INTERACTIVE_OPTIONS: TmdbRequestOptions = { maxRetries: 0, timeoutMs: 4_000 }
const ANIMATION_GENRE_ID = 16

type TargetKind = 'tv' | 'movie'

export interface WatchTargetCandidate {
  id: number
  title: string
  originalTitle: string | null
  year: number | null
  popularity: number
  genreIds: number[]
  originCountries: string[]
  originalLanguage?: string | null
}

interface WatchTarget {
  kind: TargetKind
  id: number
}

interface CacheEntry {
  expiresAt: number
  value: WatchAvailability
}

const cache = new Map<string, CacheEntry>()
const inFlight = new Map<string, Promise<WatchAvailability | null>>()

function emptyAvailability(country: string, status: WatchAvailabilityStatus): WatchAvailability {
  return { country, status, providers: [], link: null, attribution: 'JustWatch' }
}

function normalizedTitle(value: string): string {
  return value
    .normalize('NFKD')
    .toLocaleLowerCase('en')
    .replace(/[^a-z0-9]+/g, ' ')
    .trim()
}

function titleTokens(value: string): Set<string> {
  return new Set(normalizedTitle(value).split(' ').filter((token) => token.length > 1))
}

function similarity(a: string, b: string): number {
  const left = titleTokens(a)
  const right = titleTokens(b)
  if (left.size === 0 || right.size === 0) return 0
  let overlap = 0
  for (const token of left) if (right.has(token)) overlap++
  return overlap / Math.max(left.size, right.size)
}

function yearFromDate(value: string | null | undefined): number | null {
  const match = /^(\d{4})-/.exec(value ?? '')
  return match ? Number(match[1]) : null
}

function animeCandidate(candidate: WatchTargetCandidate): boolean {
  return (
    candidate.genreIds.includes(ANIMATION_GENRE_ID) &&
    (candidate.originCountries.includes('JP') || candidate.originalLanguage === 'ja')
  )
}

/**
 * Pick a conservative TMDB match for an AniList-owned title. An exact normalized title wins;
 * otherwise most title tokens must agree. The anime gate prevents a same-name live-action result
 * from becoming the source of a confident-looking provider list.
 */
export function pickAnimeWatchTarget(
  candidates: WatchTargetCandidate[],
  aliases: string[],
  year: number | null,
): WatchTargetCandidate | null {
  const names = [...new Set(aliases.map(normalizedTitle).filter(Boolean))]
  if (names.length === 0) return null

  const scored = candidates.flatMap((candidate) => {
    if (!animeCandidate(candidate)) return []
    const candidateNames = [candidate.title, candidate.originalTitle ?? ''].map(normalizedTitle).filter(Boolean)
    const exact = candidateNames.some((name) => names.includes(name))
    const bestSimilarity = Math.max(
      0,
      ...candidateNames.flatMap((candidateName) => names.map((name) => similarity(candidateName, name))),
    )
    // A fuzzy match must share most of the meaningful words. Search rank alone is not identity.
    if (!exact && bestSimilarity < 0.72) return []

    // A known catalogue year must be corroborated. An undated same-name result is not enough to
    // distinguish a remake or an announced reboot.
    if (year != null && candidate.year == null) return []
    const yearDistance = year != null && candidate.year != null ? Math.abs(year - candidate.year) : null
    // Same-title remakes exist. Once both sides state a year, a result more than two years away is
    // not safe enough to label as this work.
    if (yearDistance != null && yearDistance > 2) return []
    const yearScore = yearDistance == null ? 0 : yearDistance === 0 ? 20 : yearDistance === 1 ? 10 : 4
    const titleScore = exact ? 100 : Math.round(bestSimilarity * 70)
    return [{ candidate, score: titleScore + yearScore + Math.log10(Math.max(1, candidate.popularity)) }]
  })

  scored.sort((a, b) => b.score - a.score || a.candidate.id - b.candidate.id)
  return scored[0]?.candidate ?? null
}

function providerLogo(path: string | null): string | null {
  return path ? `https://image.tmdb.org/t/p/w92${path}` : null
}

/** Convert TMDB's access buckets into a deduplicated API list. */
export function normalizeWatchProviders(market: TmdbWatchProviderMarket | undefined): WatchProvider[] {
  if (!market) return []
  const byId = new Map<number, WatchProvider & { priority: number; rank: number }>()
  const buckets: { access: WatchAccess; rank: number; providers: TmdbWatchProvider[] | undefined }[] = [
    { access: 'subscription', rank: 0, providers: market.flatrate },
    { access: 'free', rank: 1, providers: market.free },
    { access: 'ads', rank: 2, providers: market.ads },
  ]

  for (const bucket of buckets) {
    for (const provider of bucket.providers ?? []) {
      // If the same service appears in more than one bucket, prefer its primary subscription
      // classification ahead of ancillary free/ad listings. Provider ids are stable; names are not.
      if (byId.has(provider.provider_id)) continue
      byId.set(provider.provider_id, {
        id: provider.provider_id,
        name: provider.provider_name,
        logo: providerLogo(provider.logo_path),
        access: bucket.access,
        priority: provider.display_priority,
        rank: bucket.rank,
      })
    }
  }

  return [...byId.values()]
    .sort((a, b) => a.rank - b.rank || a.priority - b.priority || a.name.localeCompare(b.name))
    .map(({ priority: _priority, rank: _rank, ...provider }) => provider)
}

function tvCandidate(hit: TmdbSearchResult): WatchTargetCandidate {
  return {
    id: hit.id,
    title: hit.name,
    originalTitle: hit.original_name ?? null,
    year: yearFromDate(hit.first_air_date),
    popularity: hit.popularity ?? 0,
    genreIds: hit.genre_ids ?? [],
    originCountries: hit.origin_country ?? [],
  }
}

function movieCandidate(hit: TmdbMovieSearchResult): WatchTargetCandidate {
  return {
    id: hit.id,
    title: hit.title,
    originalTitle: hit.original_title ?? null,
    year: yearFromDate(hit.release_date),
    popularity: hit.popularity ?? 0,
    genreIds: hit.genre_ids ?? [],
    originCountries: hit.origin_country ?? [],
    originalLanguage: hit.original_language,
  }
}

async function resolveAnimeTarget(
  title: string,
  aliases: string[],
  year: number | null,
  kind: TargetKind,
): Promise<WatchTarget | null> {
  const queries = [...new Set([title, ...aliases].map((value) => value.trim()).filter(Boolean))].slice(0, 2)
  for (const query of queries) {
    const candidates =
      kind === 'movie'
        ? (await searchMovies(query, { ...INTERACTIVE_OPTIONS, limit: 10 })).map(movieCandidate)
        : (await searchTv(query, { ...INTERACTIVE_OPTIONS, limit: 10 })).map(tvCandidate)
    const picked = pickAnimeWatchTarget(candidates, [title, ...aliases], year)
    if (picked) return { kind, id: picked.id }
  }
  return null
}

async function lookup(franchiseId: string, country: string): Promise<WatchAvailability | null> {
  const [row] = await db
    .select({
      id: franchise.id,
      source: franchise.source,
      externalId: franchise.externalId,
      title: franchise.title,
      primaryMediaId: franchise.primaryMediaId,
    })
    .from(franchise)
    .where(eq(franchise.id, franchiseId))
    .limit(1)
  if (!row) return null

  // TMDB owns general-TV franchises directly. AniList-owned anime needs a conservative title/year
  // bridge because AniList exposes streaming links but no regional catalogue or TMDB id.
  let target: WatchTarget | null = null
  if (row.source === 'tmdb' && row.externalId != null) {
    target = { kind: 'tv', id: row.externalId }
  } else {
    const parts = await db
      .select({
        id: media.id,
        titleEnglish: media.titleEnglish,
        titleRomaji: media.titleRomaji,
        format: media.format,
        year: media.seasonYear,
        sequence: franchiseMember.sequence,
      })
      .from(franchiseMember)
      .innerJoin(media, eq(media.id, franchiseMember.mediaId))
      .where(eq(franchiseMember.franchiseId, franchiseId))
    const declaredPrimary = parts.find((part) => part.id === row.primaryMediaId)
    const primary = (
      declaredPrimary && ['TV', 'TV_SHORT', 'ONA'].includes(declaredPrimary.format ?? '')
        ? declaredPrimary
        : undefined
    )
      ?? parts.find((part) => ['TV', 'TV_SHORT', 'ONA'].includes(part.format ?? ''))
      ?? (declaredPrimary?.format === 'MOVIE' ? declaredPrimary : undefined)
      ?? parts.find((part) => part.format === 'MOVIE')
      ?? parts.sort((a, b) => a.sequence - b.sequence)[0]
    if (primary) {
      const aliases = [primary.titleEnglish ?? '', primary.titleRomaji ?? ''].filter(Boolean)
      target = await resolveAnimeTarget(
        row.title,
        aliases,
        primary.year,
        primary.format === 'MOVIE' ? 'movie' : 'tv',
      )
    }
  }

  if (!target) return emptyAvailability(country, 'unmatched')
  const response = target.kind === 'movie'
    ? await getMovieWatchProviders(target.id, INTERACTIVE_OPTIONS)
    : await getTvWatchProviders(target.id, INTERACTIVE_OPTIONS)
  const market = response.results?.[country]
  const providers = normalizeWatchProviders(market)
  return {
    country,
    status: providers.length > 0 ? 'available' : 'not_available',
    providers,
    link: market?.link ?? null,
    attribution: 'JustWatch',
  }
}

function remember(key: string, value: WatchAvailability): void {
  if (cache.size >= MAX_CACHE_ENTRIES) {
    const oldest = cache.keys().next().value as string | undefined
    if (oldest) cache.delete(oldest)
  }
  cache.set(key, {
    value,
    expiresAt: Date.now() + (value.status === 'available' ? CACHE_TTL_MS : MISS_TTL_MS),
  })
}

/**
 * Country-specific subscription/free/ad-supported availability. Cached in-process because this is
 * display metadata, while the separate route keeps a cold TMDB lookup off the detail critical path.
 */
export async function getWatchAvailability(franchiseId: string, country: string): Promise<WatchAvailability | null> {
  if (!tmdbEnabled()) {
    const [exists] = await db.select({ id: franchise.id }).from(franchise).where(eq(franchise.id, franchiseId)).limit(1)
    return exists ? emptyAvailability(country, 'disabled') : null
  }
  const key = `${franchiseId}:${country}`
  const hit = cache.get(key)
  if (hit && hit.expiresAt > Date.now()) return hit.value
  if (hit) cache.delete(key)

  const active = inFlight.get(key)
  if (active) return active
  const task = lookup(franchiseId, country)
    .then((value) => {
      if (value) remember(key, value)
      return value
    })
    .finally(() => inFlight.delete(key))
  inFlight.set(key, task)
  return task
}
