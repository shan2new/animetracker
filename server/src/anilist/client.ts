import type { AniListMedia } from './types.js'

const ENDPOINT = 'https://graphql.anilist.co'

// Fields fetched for every Media node. `relations` is included so we can walk the
// franchise graph; only id/type/format are needed per related node (we re-fetch the
// full node when we expand into it).
const MEDIA_FIELDS = `
  id
  title { romaji english }
  coverImage { extraLarge large }
  bannerImage
  description(asHtml: false)
  genres
  episodes
  format
  status
  season
  seasonYear
  popularity
  trending
  nextAiringEpisode { episode airingAt }
  relations { edges { relationType node { id type format } } }
`

function chunked<T>(arr: T[], size: number): T[][] {
  const out: T[][] = []
  for (let i = 0; i < arr.length; i += size) out.push(arr.slice(i, i + size))
  return out
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms))

/**
 * POST a GraphQL query with bounded retry: honors AniList's 429 `Retry-After`, and backs
 * off on transient 5xx / network errors. Throws after retries are spent. Ported from the
 * legacy web client (legacy-web/src/anilist.ts).
 */
export async function gql<T>(query: string, variables: Record<string, unknown>, attempt = 0): Promise<T> {
  const MAX_RETRIES = 4
  try {
    const res = await fetch(ENDPOINT, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
      body: JSON.stringify({ query, variables }),
    })
    if (res.status === 429 || res.status >= 500) {
      if (attempt >= MAX_RETRIES) throw new Error(`AniList ${res.status}`)
      const retryAfter = Number(res.headers.get('Retry-After'))
      const waitMs = Number.isFinite(retryAfter) && retryAfter > 0 ? retryAfter * 1000 : 2 ** attempt * 1000
      await sleep(waitMs)
      return gql<T>(query, variables, attempt + 1)
    }
    if (!res.ok) throw new Error(`AniList ${res.status}`)
    const json = (await res.json()) as { data?: T; errors?: { message: string }[] }
    if (json.errors) throw new Error(json.errors.map((e) => e.message).join('; '))
    return json.data as T
  } catch (err) {
    if (attempt < MAX_RETRIES && err instanceof TypeError) {
      await sleep(2 ** attempt * 1000)
      return gql<T>(query, variables, attempt + 1)
    }
    throw err
  }
}

async function settle<T>(promises: Promise<T>[]): Promise<T[]> {
  const settled = await Promise.allSettled(promises)
  return settled.flatMap((r) => (r.status === 'fulfilled' ? [r.value] : []))
}

/** Fetch full live metadata (incl. relations) for a set of AniList ids. */
export async function fetchByIds(ids: number[]): Promise<AniListMedia[]> {
  if (ids.length === 0) return []
  const batches = await settle(
    chunked(ids, 50).map((chunk) =>
      gql<{ Page: { media: AniListMedia[] } }>(
        `query ($ids: [Int]) { Page(perPage: 50) { media(id_in: $ids, type: ANIME) { ${MEDIA_FIELDS} } } }`,
        { ids: chunk },
      ),
    ),
  )
  return batches.flatMap((d) => d.Page.media)
}

/** Fetch a single media with relations (used while expanding the franchise graph). */
export async function fetchOne(id: number): Promise<AniListMedia | null> {
  try {
    const data = await gql<{ Media: AniListMedia | null }>(
      `query ($id: Int) { Media(id: $id, type: ANIME) { ${MEDIA_FIELDS} } }`,
      { id },
    )
    return data.Media
  } catch (err) {
    // AniList returns 404 for a non-existent / non-anime id. During graph expansion a dead
    // edge shouldn't crash the whole grouping — treat it as "not found".
    if (err instanceof Error && /\b404\b/.test(err.message)) return null
    throw err
  }
}

/**
 * Exact most-recent aired episode time for each id, from airingSchedules (TIME_DESC).
 * Returns a map of mediaId → airingAt (ms epoch). Ported from the legacy client.
 */
export async function fetchLastAired(ids: number[]): Promise<Record<number, number>> {
  const out: Record<number, number> = {}
  if (ids.length === 0) return out
  const batches = await settle(
    chunked(ids, 20).map((chunk) => {
      const aliases = chunk
        .map(
          (id, j) =>
            `a${j}: Page(perPage: 1) { airingSchedules(mediaId: ${id}, notYetAired: false, sort: TIME_DESC) { episode airingAt mediaId } }`,
        )
        .join('\n')
      return gql<Record<string, { airingSchedules: { airingAt: number; mediaId: number }[] }>>(
        `query { ${aliases} }`,
        {},
      )
    }),
  )
  for (const data of batches) {
    for (const key of Object.keys(data)) {
      const node = data[key]?.airingSchedules?.[0]
      if (node) out[node.mediaId] = node.airingAt * 1000
    }
  }
  return out
}

/** Search AniList. Empty query returns what's trending now. */
export async function searchMedia(query: string): Promise<AniListMedia[]> {
  const trimmed = query.trim()
  const data = await gql<{ Page: { media: AniListMedia[] } }>(
    `query ($search: String, $sort: [MediaSort]) {
      Page(perPage: 30) { media(search: $search, type: ANIME, sort: $sort, isAdult: false) { ${MEDIA_FIELDS} } }
    }`,
    trimmed
      ? { search: trimmed, sort: ['SEARCH_MATCH', 'POPULARITY_DESC'] }
      : { search: null, sort: ['TRENDING_DESC', 'POPULARITY_DESC'] },
  )
  return data.Page.media
}

/** Top trending anime for eager-grouping seed. Paginates; uses hasNextPage (reliable). */
export async function fetchTrending(limit: number): Promise<AniListMedia[]> {
  const perPage = 50
  const pages = Math.ceil(limit / perPage)
  const out: AniListMedia[] = []
  for (let page = 1; page <= pages; page++) {
    const data = await gql<{ Page: { pageInfo: { hasNextPage: boolean }; media: AniListMedia[] } }>(
      `query ($page: Int, $perPage: Int) {
        Page(page: $page, perPage: $perPage) {
          pageInfo { hasNextPage }
          media(type: ANIME, sort: [TRENDING_DESC, POPULARITY_DESC], isAdult: false) { ${MEDIA_FIELDS} }
        }
      }`,
      { page, perPage },
    )
    out.push(...data.Page.media)
    if (!data.Page.pageInfo.hasNextPage) break
  }
  return out.slice(0, limit)
}
