import { eq } from 'drizzle-orm'
import { db } from '../db/index.js'
import { franchise, franchiseMember, media } from '../db/schema.js'
import {
  getMovieWatchProviders,
  getTvWatchProviders,
  tmdbEnabled,
  type TmdbRequestOptions,
} from '../tmdb/client.js'
import type {
  TmdbWatchProvider,
  TmdbWatchProviderMarket,
} from '../tmdb/types.js'
import type {
  WatchAccess,
  WatchAvailability,
  WatchAvailabilityStatus,
  WatchProvider,
} from '../types/api.js'
import { resolveAnimeTmdbTarget } from './animeTmdbMatch.js'
export { pickAnimeTmdbCandidate as pickAnimeWatchTarget } from './animeTmdbMatch.js'
export type { AnimeTmdbCandidate as WatchTargetCandidate } from './animeTmdbMatch.js'

const CACHE_TTL_MS = 12 * 60 * 60 * 1000
const MISS_TTL_MS = 60 * 60 * 1000
const MAX_CACHE_ENTRIES = 500
const INTERACTIVE_OPTIONS: TmdbRequestOptions = { maxRetries: 0, timeoutMs: 4_000 }
type TargetKind = 'tv' | 'movie'

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

async function lookup(franchiseId: string, country: string): Promise<WatchAvailability | null> {
  const [row] = await db
    .select({
      id: franchise.id,
      source: franchise.source,
      externalId: franchise.externalId,
      title: franchise.title,
      primaryMediaId: franchise.primaryMediaId,
      enrichment: franchise.enrichment,
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
  } else if (
    row.enrichment?.videoFallback?.status === 'matched' &&
    row.enrichment.videoFallback.externalId != null
  ) {
    // Trailer enrichment already established the same conservative title/year match. Reuse it so
    // regional availability cannot select a different TMDB work and avoids another search call.
    target = {
      kind: row.enrichment.videoFallback.mediaType,
      id: row.enrichment.videoFallback.externalId,
    }
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
      const resolved = await resolveAnimeTmdbTarget({
        title: row.title,
        aliases,
        year: primary.year,
        mediaType: primary.format === 'MOVIE' ? 'movie' : 'tv',
      }, INTERACTIVE_OPTIONS)
      target = resolved ? { kind: resolved.mediaType, id: resolved.externalId } : null
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
