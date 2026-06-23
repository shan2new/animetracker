import type { AniListMedia } from './types'

const ENDPOINT = 'https://graphql.anilist.co'

const MEDIA_FIELDS = `
  id
  title { romaji english }
  coverImage { extraLarge large }
  bannerImage
  description(asHtml: false)
  genres
  episodes
  status
  nextAiringEpisode { episode airingAt }
`

/** Split an array into fixed-size chunks. */
function chunked<T>(arr: T[], size: number): T[][] {
  const out: T[][] = []
  for (let i = 0; i < arr.length; i += size) out.push(arr.slice(i, i + size))
  return out
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms))

/**
 * POST a GraphQL query with bounded retry: honors AniList's 429 `Retry-After`,
 * and backs off on transient 5xx / network errors. Throws after retries are spent.
 */
async function gql<T>(query: string, variables: Record<string, unknown>, attempt = 0): Promise<T> {
  const MAX_RETRIES = 3
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
    const json = await res.json()
    if (json.errors) throw new Error(json.errors.map((e: { message: string }) => e.message).join('; '))
    return json.data as T
  } catch (err) {
    // Network-level failure (fetch rejects with TypeError): retry with backoff, then give up.
    if (attempt < MAX_RETRIES && err instanceof TypeError) {
      await sleep(2 ** attempt * 1000)
      return gql<T>(query, variables, attempt + 1)
    }
    throw err
  }
}

/** Resolve all chunk queries, keeping data from the ones that succeed (partial > nothing). */
async function settleChunks<T>(promises: Promise<T>[]): Promise<{ values: T[]; ok: boolean }> {
  const settled = await Promise.allSettled(promises)
  return {
    values: settled.flatMap((r) => (r.status === 'fulfilled' ? [r.value] : [])),
    ok: settled.every((r) => r.status === 'fulfilled'),
  }
}

/** Fetch full live metadata for a set of AniList ids (the user's library). */
export async function fetchByIds(ids: number[]): Promise<AniListMedia[]> {
  if (ids.length === 0) return []
  // AniList caps a page at 50; run the chunks concurrently and keep partial results.
  const { values, ok } = await settleChunks(
    chunked(ids, 50).map((chunk) =>
      gql<{ Page: { media: AniListMedia[] } }>(
        `query ($ids: [Int]) {
          Page(perPage: 50) {
            media(id_in: $ids, type: ANIME) { ${MEDIA_FIELDS} }
          }
        }`,
        { ids: chunk },
      ),
    ),
  )
  const media = values.flatMap((d) => d.Page.media)
  // Only fail loudly if we got nothing at all; otherwise partial data is better than none.
  if (!ok && media.length === 0) throw new Error('Could not reach AniList')
  return media
}

/**
 * Fetch the exact most-recent aired episode time for each id, from AniList's
 * airingSchedules (TIME_DESC). Returns a map of mediaId → airingAt (ms epoch).
 * Used for precise "last aired" / "out now" timing instead of a weekly guess.
 */
export async function fetchLastAired(ids: number[]): Promise<Record<number, number>> {
  const out: Record<number, number> = {}
  if (ids.length === 0) return out
  // Batch via aliased Page queries (chunked under AniList's complexity cap), run concurrently.
  // Best-effort: failures fall back to the weekly heuristic in toShow, so keep partial results.
  const { values: batches } = await settleChunks(
    chunked(ids, 20).map((chunk) => {
      const aliases = chunk
        .map(
          (id, j) =>
            `a${j}: Page(perPage: 1) { airingSchedules(mediaId: ${id}, notYetAired: false, sort: TIME_DESC) { episode airingAt mediaId } }`,
        )
        .join('\n')
      return gql<Record<string, { airingSchedules: { airingAt: number; mediaId: number }[] }>>(`query { ${aliases} }`, {})
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

/** Search AniList. Empty query returns what's trending now (the "Add" tab default). */
export async function searchMedia(query: string): Promise<AniListMedia[]> {
  const trimmed = query.trim()
  const data = await gql<{ Page: { media: AniListMedia[] } }>(
    `query ($search: String, $sort: [MediaSort]) {
      Page(perPage: 30) {
        media(search: $search, type: ANIME, sort: $sort, isAdult: false) { ${MEDIA_FIELDS} }
      }
    }`,
    trimmed
      ? { search: trimmed, sort: ['SEARCH_MATCH', 'POPULARITY_DESC'] }
      : { search: null, sort: ['TRENDING_DESC', 'POPULARITY_DESC'] },
  )
  return data.Page.media
}
