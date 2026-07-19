import { env } from '../env.js'
import type { TmdbSeasonDetail, TmdbSearchResult, TmdbShow } from './types.js'

const BASE = 'https://api.themoviedb.org/3'

/** TV support is opt-in: without a token the whole TMDB path is disabled (anime-only mode). */
export function tmdbEnabled(): boolean {
  return !!env.TMDB_ACCESS_TOKEN
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms))

/**
 * GET a TMDB v3 path with bounded retry — same contract as the AniList `gql()` client:
 * honor `Retry-After` on 429/5xx (else exponential backoff), retry network errors, throw
 * after retries are spent. TMDB allows ~40 req/s per IP, so retries here are rare.
 */
async function tmdbGet<T>(path: string, params: Record<string, string> = {}, attempt = 0): Promise<T> {
  const MAX_RETRIES = 4
  const url = new URL(`${BASE}${path}`)
  for (const [k, v] of Object.entries(params)) url.searchParams.set(k, v)
  try {
    const res = await fetch(url, {
      headers: { Authorization: `Bearer ${env.TMDB_ACCESS_TOKEN}`, Accept: 'application/json' },
    })
    if (res.status === 429 || res.status >= 500) {
      if (attempt >= MAX_RETRIES) throw new Error(`TMDB ${res.status}`)
      const retryAfter = Number(res.headers.get('Retry-After'))
      const waitMs = Number.isFinite(retryAfter) && retryAfter > 0 ? retryAfter * 1000 : 2 ** attempt * 1000
      await sleep(waitMs)
      return tmdbGet<T>(path, params, attempt + 1)
    }
    if (!res.ok) throw new Error(`TMDB ${res.status}`)
    return (await res.json()) as T
  } catch (err) {
    if (attempt < MAX_RETRIES && err instanceof TypeError) {
      await sleep(2 ** attempt * 1000)
      return tmdbGet<T>(path, params, attempt + 1)
    }
    throw err
  }
}

/** Search TV shows by name (TMDB does its own fuzzy matching). */
export async function searchTv(query: string): Promise<TmdbSearchResult[]> {
  const json = await tmdbGet<{ results?: TmdbSearchResult[] }>('/search/tv', {
    query,
    include_adult: 'false',
    page: '1',
  })
  return (json.results ?? []).slice(0, 20)
}

/** Full show detail (status, seasons, next/last episode). Null on 404 (deleted/merged show). */
export async function getShow(showId: number): Promise<TmdbShow | null> {
  try {
    return await tmdbGet<TmdbShow>(`/tv/${showId}`)
  } catch (err) {
    if ((err as Error).message === 'TMDB 404') return null
    throw err
  }
}

/** Season detail with the full per-episode list. Null on 404 (season absent/unpublished). */
export async function getSeason(showId: number, seasonNumber: number): Promise<TmdbSeasonDetail | null> {
  try {
    return await tmdbGet<TmdbSeasonDetail>(`/tv/${showId}/season/${seasonNumber}`)
  } catch (err) {
    if ((err as Error).message === 'TMDB 404') return null
    throw err
  }
}

/** Daily-trending TV, paged (20/page) up to `limit`. */
export async function getTrendingTv(limit: number): Promise<TmdbSearchResult[]> {
  const out: TmdbSearchResult[] = []
  const pages = Math.max(1, Math.ceil(limit / 20))
  for (let page = 1; page <= pages && out.length < limit; page++) {
    const json = await tmdbGet<{ results?: TmdbSearchResult[] }>('/trending/tv/day', { page: String(page) })
    const results = json.results ?? []
    out.push(...results)
    if (results.length === 0) break
  }
  return out.slice(0, limit)
}
