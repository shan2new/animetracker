import { and, eq, inArray, sql } from 'drizzle-orm'
import { fetchEnrichmentByIds, type AniListRequestOptions } from '../anilist/client.js'
import type {
  AniListCharacterEdge,
  AniListMedia,
  AniListMediaEnrichment,
  AniListPerson,
  AniListStaffEdge,
} from '../anilist/types.js'
import { db } from '../db/index.js'
import { franchise, franchiseMember, media, subscriptions } from '../db/schema.js'
import { getShow, type TmdbRequestOptions } from '../tmdb/client.js'
import { tmdbFranchiseEnrichment } from '../tmdb/mapping.js'
import type { CatalogPerson, FranchiseEnrichment, FranchisePeople, RelatedTitle } from '../types/api.js'
import { BoundedTaskQueue } from '../util/taskQueue.js'
import { syncRecommendationEdges } from './recommendations.js'

const D = 86_400_000
const REFRESH_AFTER_MS = 7 * D
const ANILIST_BACKGROUND_INTERVAL_MS = 2_100
const EMPTY_PEOPLE: FranchisePeople = { creators: [], directors: [], cast: [] }

const queue = new BoundedTaskQueue(2, 48, (key, error) => {
  console.warn(`catalog enrichment failed (${key}):`, error instanceof Error ? error.message : error)
})

function aniListPerson(person: AniListPerson, role: string | null): CatalogPerson | null {
  const name = person.name.full?.trim()
  if (!name) return null
  return {
    source: 'anilist',
    externalId: person.id,
    name,
    role: role?.trim() || null,
    image: person.image.large ?? null,
  }
}

function dedupePeople(people: (CatalogPerson | null)[], limit: number): CatalogPerson[] {
  const seen = new Set<number>()
  const out: CatalogPerson[] = []
  for (const person of people) {
    if (!person || seen.has(person.externalId)) continue
    seen.add(person.externalId)
    out.push(person)
    if (out.length >= limit) break
  }
  return out
}

function aniListPeople(items: AniListMediaEnrichment[]): FranchisePeople {
  const staff = items.flatMap((item) => item.staff?.edges ?? [])
  const creators = dedupePeople(
    staff
      .filter((edge: AniListStaffEdge) => /original (creator|story)|creator|mangaka/i.test(edge.role ?? ''))
      .map((edge) => aniListPerson(edge.node, edge.role)),
    4,
  )
  const directors = dedupePeople(
    staff
      .filter((edge: AniListStaffEdge) => /director/i.test(edge.role ?? ''))
      .map((edge) => aniListPerson(edge.node, edge.role)),
    4,
  )
  const cast = dedupePeople(
    items.flatMap((item) =>
      (item.characters?.edges ?? []).flatMap((edge: AniListCharacterEdge) => {
        const character = edge.node.name.full?.trim() || edge.role?.trim() || null
        return (edge.voiceActors ?? []).map((actor) => aniListPerson(actor, character))
      }),
    ),
    10,
  )
  return { creators, directors, cast }
}

/** A cheap row available from the normal AniList media payload; deep graphs arrive later. */
export function basicAniListEnrichment(
  primary: AniListMedia | undefined,
  genres: string[],
  nowMs = Date.now(),
): FranchiseEnrichment {
  return {
    level: 'basic',
    themes: [...new Set(genres)].slice(0, 10),
    isAdult: primary?.isAdult ?? null,
    contentRatings: [],
    people: EMPTY_PEOPLE,
    related: [],
    videos: [],
    checkedAt: new Date(nowMs).toISOString(),
  }
}

/** Map AniList's explicit spoiler flags into a conservative source-neutral franchise payload. */
export function aniListFranchiseEnrichment(
  items: AniListMediaEnrichment[],
  genres: string[],
  memberIds: Set<number>,
  nowMs = Date.now(),
): FranchiseEnrichment {
  const safeTags = items
    .flatMap((item) => item.tags ?? [])
    .filter((tag) => !tag.isGeneralSpoiler && !tag.isMediaSpoiler && !tag.isAdult)
    .sort((a, b) => b.rank - a.rank)
    .map((tag) => tag.name.trim())
    .filter(Boolean)
  const themes = [...new Set([...safeTags, ...genres])].slice(0, 10)
  const adultValues = items.map((item) => item.isAdult).filter((value): value is boolean => value != null)

  const relatedCandidates = items
    .flatMap((item) => item.recommendations?.nodes ?? [])
    .filter(
      (node) =>
        node.mediaRecommendation?.type === 'ANIME' && !memberIds.has(node.mediaRecommendation.id),
    )
    .sort((a, b) => (b.rating ?? 0) - (a.rating ?? 0))
  const seenRelated = new Set<number>()
  const related: RelatedTitle[] = []
  for (const node of relatedCandidates) {
    const candidate = node.mediaRecommendation
    if (!candidate || seenRelated.has(candidate.id)) continue
    const title = candidate.title.english || candidate.title.romaji
    if (!title) continue
    seenRelated.add(candidate.id)
    related.push({
      source: 'anilist',
      externalId: candidate.id,
      franchiseId: null,
      title,
      year: candidate.seasonYear ?? null,
      images: {
        portrait: candidate.coverImage.extraLarge ?? candidate.coverImage.large ?? null,
        landscape: candidate.bannerImage ?? null,
      },
      score: node.rating ?? null,
    })
    if (related.length >= 10) break
  }

  return {
    level: 'full',
    themes,
    isAdult: adultValues.length ? adultValues.some(Boolean) : null,
    contentRatings: [],
    people: aniListPeople(items),
    related,
    videos: [],
    checkedAt: new Date(nowMs).toISOString(),
  }
}

function stillFresh(value: FranchiseEnrichment | null | undefined): boolean {
  if (value?.level !== 'full') return false
  const checked = Date.parse(value.checkedAt)
  return Number.isFinite(checked) && checked > Date.now() - REFRESH_AFTER_MS
}

/** Refresh one franchise's expensive catalogue metadata. Safe to call repeatedly. */
export async function refreshFranchiseEnrichment(
  franchiseId: string,
  options: {
    force?: boolean
    anilistRequest?: AniListRequestOptions
    tmdbRequest?: TmdbRequestOptions
  } = {},
): Promise<boolean> {
  const [row] = await db.select().from(franchise).where(eq(franchise.id, franchiseId)).limit(1)
  if (!row || (!options.force && stillFresh(row.enrichment))) return false

  if (row.source === 'tmdb') {
    if (row.externalId == null) return false
    const show = await getShow(row.externalId, { ...options.tmdbRequest, enrichment: true })
    if (!show) return false
    const value = tmdbFranchiseEnrichment(show)
    await db
      .update(franchise)
      .set({ enrichment: value, updatedAt: new Date() })
      .where(eq(franchise.id, franchiseId))
    await syncRecommendationEdges(franchiseId, value.related)
    return true
  }

  const members = await db
    .select({
      mediaId: franchiseMember.mediaId,
      sequence: franchiseMember.sequence,
      status: media.status,
    })
    .from(franchiseMember)
    .innerJoin(media, eq(media.id, franchiseMember.mediaId))
    .where(eq(franchiseMember.franchiseId, franchiseId))
  if (members.length === 0) return false

  // Primary + current/future/latest parts capture canonical staff, current voice cast and useful
  // recommendations in one small GraphQL request without traversing every OVA/special.
  const ranked = members.slice().sort((a, b) => {
    const priority = (status: string | null) => status === 'NOT_YET_RELEASED' ? 2 : status === 'RELEASING' ? 1 : 0
    return priority(b.status) - priority(a.status) || b.sequence - a.sequence
  })
  const representativeIds = [row.primaryMediaId, ...ranked.map((item) => item.mediaId)]
    .filter((id): id is number => id != null)
    .filter((id, index, all) => all.indexOf(id) === index)
    .slice(0, 3)
  const enriched = await fetchEnrichmentByIds(representativeIds, options.anilistRequest)
  if (enriched.length === 0) return false

  const value = aniListFranchiseEnrichment(
    enriched,
    row.genres ?? [],
    new Set(members.map((item) => item.mediaId)),
  )
  // TMDB is metadata-only for anime. Merge fallback fields from the row AT UPDATE TIME rather than
  // the snapshot read above: Search queues both enrichers together, and a read/modify/write here
  // could otherwise erase a trailer that arrived while the AniList request was in flight.
  await db.update(franchise).set({
    enrichment: sql`jsonb_strip_nulls(
      ${JSON.stringify(value)}::jsonb || jsonb_build_object(
        'videos', coalesce(${franchise.enrichment}->'videos', '[]'::jsonb),
        'videoFallback', ${franchise.enrichment}->'videoFallback'
      )
    )`,
    updatedAt: new Date(),
  }).where(eq(franchise.id, franchiseId))
  await syncRecommendationEdges(franchiseId, value.related)
  return true
}

/** Stale-while-revalidate entry point for Search and Detail. Never blocks either response. */
export function enqueueFranchiseEnrichment(franchiseId: string): void {
  queue.enqueue(`franchise:${franchiseId}`, async () => {
    await refreshFranchiseEnrichment(franchiseId)
  })
}

/**
 * Slowly repair/refresh followed anime without depending on a Detail visit. AniList may enforce a
 * 30 requests/minute degraded limit, so this is intentionally sequential, capped, and stops after
 * three provider misses. Fresh rows short-circuit before any network request.
 */
export async function refreshSubscribedAniListEnrichment(limit = 25): Promise<{
  checked: number
  refreshed: number
}> {
  const candidates = await db
    .selectDistinct({ id: franchise.id, enrichment: franchise.enrichment })
    .from(subscriptions)
    .innerJoin(franchise, eq(franchise.id, subscriptions.franchiseId))
    .where(eq(franchise.source, 'anilist'))
    .limit(100)
  const stale = candidates.filter((row) => !stillFresh(row.enrichment)).slice(0, limit)
  let checked = 0
  let refreshed = 0
  let consecutiveMisses = 0
  for (const row of stale) {
    checked++
    const didRefresh = await refreshFranchiseEnrichment(row.id, {
      anilistRequest: { maxRetries: 1, timeoutMs: 10_000 },
    })
    if (didRefresh) {
      refreshed++
      consecutiveMisses = 0
    } else {
      consecutiveMisses++
      if (consecutiveMisses >= 3) break
    }
    await new Promise((resolve) => setTimeout(resolve, ANILIST_BACKGROUND_INTERVAL_MS))
  }
  return { checked, refreshed }
}

/** Resolve related provider ids to local franchise ids in two batched reads. */
export async function resolveRelatedFranchiseIds(items: RelatedTitle[]): Promise<RelatedTitle[]> {
  if (items.length === 0) return items
  const aniIds = [...new Set(items.filter((item) => item.source === 'anilist').map((item) => item.externalId))]
  const tmdbIds = [...new Set(items.filter((item) => item.source === 'tmdb').map((item) => item.externalId))]
  const [aniRows, tmdbRows] = await Promise.all([
    aniIds.length
      ? db
          .select({ externalId: franchiseMember.mediaId, franchiseId: franchiseMember.franchiseId })
          .from(franchiseMember)
          .where(inArray(franchiseMember.mediaId, aniIds))
      : Promise.resolve([]),
    tmdbIds.length
      ? db
          .select({ externalId: franchise.externalId, franchiseId: franchise.id })
          .from(franchise)
          .where(and(eq(franchise.source, 'tmdb'), inArray(franchise.externalId, tmdbIds)))
      : Promise.resolve([]),
  ])
  const local = new Map<string, string>()
  for (const row of aniRows) local.set(`anilist:${row.externalId}`, row.franchiseId)
  for (const row of tmdbRows) if (row.externalId != null) local.set(`tmdb:${row.externalId}`, row.franchiseId)
  return items.map((item) => ({
    ...item,
    franchiseId: local.get(`${item.source}:${item.externalId}`) ?? null,
  }))
}
