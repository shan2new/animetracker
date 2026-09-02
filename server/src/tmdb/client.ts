import { env } from '../env.js'
import { abortReason, abortableSleep, isAbortError, withTimeout } from '../util/abort.js'
import type { TmdbSeasonDetail, TmdbSearchResult, TmdbShow } from './types.js'

const BASE = 'https://api.themoviedb.org/3'

/** TV support is opt-in: without a token the whole TMDB path is disabled (anime-only mode). */
export function tmdbEnabled(): boolean {
  return !!env.TMDB_ACCESS_TOKEN
}

const DEFAULT_MAX_RETRIES = 4
const DEFAULT_TIMEOUT_MS = 10_000

export interface TmdbRequestOptions {
  signal?: AbortSignal
  maxRetries?: number
  timeoutMs?: number
}

/**
 * GET a TMDB v3 path with bounded retry — same contract as the AniList `gql()` client:
 * honor `Retry-After` on 429/5xx (else exponential backoff), retry network errors, throw
 * after retries are spent. TMDB allows ~40 req/s per IP, so retries here are rare.
 */
async function tmdbGet<T>(
  path: string,
  params: Record<string, string> = {},
  options: TmdbRequestOptions = {},
  attempt = 0,
): Promise<T> {
  const maxRetries = options.maxRetries ?? DEFAULT_MAX_RETRIES
  const url = new URL(`${BASE}${path}`)
  for (const [k, v] of Object.entries(params)) url.searchParams.set(k, v)
  try {
    const res = await fetch(url, {
      headers: { Authorization: `Bearer ${env.TMDB_ACCESS_TOKEN}`, Accept: 'application/json' },
      signal: withTimeout(options.signal, options.timeoutMs ?? DEFAULT_TIMEOUT_MS),
    })
    if (res.status === 429 || res.status >= 500) {
      if (attempt >= maxRetries) throw new Error(`TMDB ${res.status}`)
      const retryAfter = Number(res.headers.get('Retry-After'))
      const waitMs = Number.isFinite(retryAfter) && retryAfter > 0 ? retryAfter * 1000 : 2 ** attempt * 1000
      await abortableSleep(waitMs, options.signal)
      return tmdbGet<T>(path, params, options, attempt + 1)
    }
    if (!res.ok) throw new Error(`TMDB ${res.status}`)
    return (await res.json()) as T
  } catch (err) {
    if (options.signal?.aborted) throw abortReason(options.signal)
    if (attempt < maxRetries && (err instanceof TypeError || isAbortError(err))) {
      await abortableSleep(2 ** attempt * 1000, options.signal)
      return tmdbGet<T>(path, params, options, attempt + 1)
    }
    throw err
  }
}

/** Search TV shows by name (TMDB does its own fuzzy matching). */
export async function searchTv(
  query: string,
  options: TmdbRequestOptions & { limit?: number } = {},
): Promise<TmdbSearchResult[]> {
  const json = await tmdbGet<{ results?: TmdbSearchResult[] }>('/search/tv', {
    query,
    include_adult: 'false',
    page: '1',
  }, options)
  return (json.results ?? []).slice(0, Math.max(1, Math.min(options.limit ?? 20, 20)))
}

/** Full show detail (status, seasons, next/last episode). Null on 404 (deleted/merged show). */
export async function getShow(showId: number, options: TmdbRequestOptions = {}): Promise<TmdbShow | null> {
  try {
    return await tmdbGet<TmdbShow>(`/tv/${showId}`, {}, options)
  } catch (err) {
    if ((err as Error).message === 'TMDB 404') return null
    throw err
  }
}

/** Season detail with the full per-episode list. Null on 404 (season absent/unpublished). */
export async function getSeason(
  showId: number,
  seasonNumber: number,
  options: TmdbRequestOptions = {},
): Promise<TmdbSeasonDetail | null> {
  try {
    return await tmdbGet<TmdbSeasonDetail>(`/tv/${showId}/season/${seasonNumber}`, {}, options)
  } catch (err) {
    if ((err as Error).message === 'TMDB 404') return null
    throw err
  }
}

/** Daily-trending TV, paged (20/page) up to `limit`. */
export async function getTrendingTv(limit: number, options: TmdbRequestOptions = {}): Promise<TmdbSearchResult[]> {
  const out: TmdbSearchResult[] = []
  const pages = Math.max(1, Math.ceil(limit / 20))
  for (let page = 1; page <= pages && out.length < limit; page++) {
    const json = await tmdbGet<{ results?: TmdbSearchResult[] }>(
      '/trending/tv/day',
      { page: String(page) },
      options,
    )
    const results = json.results ?? []
    out.push(...results)
    if (results.length === 0) break
  }
  return out.slice(0, limit)
}
