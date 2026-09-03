// Idempotent catalogue backfill for fields added after the first materialization of a title:
// studios, episode metadata, videos and deep franchise enrichment.
//
//   AniList: re-fetch media by id for episodes/trailers, then fetch graph-heavy tags/people/
//            recommendations for up to three representative parts per franchise.
//   TMDB:    re-materialize each show and season for videos, ratings, people and recommendations.
//
// Subscribed/recent franchises go first. Per-chunk/per-show failures are logged and skipped, so a
// re-run safely picks up anything missed. Usage: npx tsx src/scripts/backfill-episodes.ts

import { eq } from 'drizzle-orm'
import { fetchByIds, fetchEnrichmentByIds } from '../anilist/client.js'
import type { AniListMediaEnrichment } from '../anilist/types.js'
import { db, sql } from '../db/index.js'
import { franchise } from '../db/schema.js'
import { aniListFranchiseEnrichment } from '../services/catalogEnrichment.js'
import { toMediaRow, upsertMediaRows } from '../services/mediaStore.js'
import { TMDB_ID_OFFSET } from '../tmdb/mapping.js'
import { refreshTvShow } from '../tmdb/service.js'

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms))
const ANILIST_INTERVAL_MS = 2_100 // safely below AniList's degraded 30 requests/minute ceiling
const MAX_CONSECUTIVE_EMPTY_BATCHES = 3

function chunked<T>(arr: T[], n: number): T[][] {
  const out: T[][] = []
  for (let i = 0; i < arr.length; i += n) out.push(arr.slice(i, i + n))
  return out
}

async function backfillAniList(): Promise<void> {
  const rows = await sql<{ id: number }[]>`SELECT id FROM media WHERE id < ${TMDB_ID_OFFSET} ORDER BY id`
  const ids = rows.map((r) => r.id)
  console.log(`[anilist] ${ids.length} media to backfill`)
  let done = 0
  let failed = 0
  let consecutiveEmpty = 0
  for (const chunk of chunked(ids, 50)) {
    try {
      const medias = await fetchByIds(chunk, { maxRetries: 1 })
      if (medias.length === 0) throw new Error('provider returned no rows')
      await upsertMediaRows(medias.map(toMediaRow))
      done += medias.length
      failed += chunk.length - medias.length
      consecutiveEmpty = 0
    } catch (err) {
      failed += chunk.length
      consecutiveEmpty++
      console.warn(`[anilist] chunk failed:`, (err as Error).message)
    }
    console.log(`[anilist] upserted ${done}/${ids.length} (failed ${failed})`)
    if (consecutiveEmpty >= MAX_CONSECUTIVE_EMPTY_BATCHES) {
      console.warn('[anilist] stopping base pass after three empty batches; re-run when the provider recovers')
      break
    }
    await sleep(ANILIST_INTERVAL_MS)
  }
}

interface AniListFranchiseRow {
  id: string
  primary_media_id: number | null
  genres: string[] | null
  enrichment: import('../types/api.js').FranchiseEnrichment | null
}

interface AniListMemberRow {
  franchise_id: string
  media_id: number
  sequence: number
  status: string | null
}

function representativeIds(
  row: AniListFranchiseRow,
  members: AniListMemberRow[],
): number[] {
  const priority = (status: string | null) => status === 'NOT_YET_RELEASED' ? 2 : status === 'RELEASING' ? 1 : 0
  const ranked = members.slice().sort((a, b) =>
    priority(b.status) - priority(a.status) || b.sequence - a.sequence,
  )
  return [row.primary_media_id, ...ranked.map((item) => item.media_id)]
    .filter((id): id is number => id != null)
    .filter((id, index, all) => all.indexOf(id) === index)
    .slice(0, 3)
}

async function backfillAniListEnrichment(): Promise<void> {
  const rows = await sql<AniListFranchiseRow[]>`
    SELECT f.id, f.primary_media_id, f.genres, f.enrichment
    FROM franchise f
    LEFT JOIN subscriptions s ON s.franchise_id = f.id
    WHERE f.source = 'anilist'
    GROUP BY f.id
    ORDER BY count(s.user_id) DESC, f.updated_at DESC`
  const members = await sql<AniListMemberRow[]>`
    SELECT fm.franchise_id, fm.media_id, fm.sequence, m.status
    FROM franchise_member fm
    JOIN franchise f ON f.id = fm.franchise_id
    JOIN media m ON m.id = fm.media_id
    WHERE f.source = 'anilist'`
  const byFranchise = new Map<string, AniListMemberRow[]>()
  for (const member of members) {
    const values = byFranchise.get(member.franchise_id) ?? []
    values.push(member)
    byFranchise.set(member.franchise_id, values)
  }
  const selected = new Map(
    rows.map((row) => [row.id, representativeIds(row, byFranchise.get(row.id) ?? [])] as const),
  )
  const ids = [...new Set([...selected.values()].flat())]
  const enrichedById = new Map<number, AniListMediaEnrichment>()
  console.log(`[anilist] ${rows.length} franchises / ${ids.length} representative media to enrich`)

  let requested = 0
  let consecutiveEmpty = 0
  for (const chunk of chunked(ids, 20)) {
    const enriched = await fetchEnrichmentByIds(chunk, { maxRetries: 1 })
    requested += chunk.length
    for (const item of enriched) enrichedById.set(item.id, item)
    consecutiveEmpty = enriched.length === 0 ? consecutiveEmpty + 1 : 0
    console.log(`[anilist] deep media ${requested}/${ids.length}; received ${enrichedById.size}`)
    if (consecutiveEmpty >= MAX_CONSECUTIVE_EMPTY_BATCHES) {
      console.warn('[anilist] stopping deep pass after three empty batches; re-run when the provider recovers')
      break
    }
    await sleep(ANILIST_INTERVAL_MS)
  }

  let done = 0
  let skipped = 0
  for (const row of rows) {
    const memberRows = byFranchise.get(row.id) ?? []
    const items = (selected.get(row.id) ?? []).flatMap((id) => {
      const item = enrichedById.get(id)
      return item ? [item] : []
    })
    if (items.length === 0) {
      skipped++
      continue
    }
    const enrichment = aniListFranchiseEnrichment(
      items,
      row.genres ?? [],
      new Set(memberRows.map((item) => item.media_id)),
    )
    enrichment.videos = row.enrichment?.videos ?? []
    enrichment.videoFallback = row.enrichment?.videoFallback
    await db.update(franchise).set({ enrichment, updatedAt: new Date() }).where(eq(franchise.id, row.id))
    done++
  }
  console.log(`[anilist] deep-enriched ${done}/${rows.length} franchises (skipped ${skipped})`)
}

async function backfillTmdb(): Promise<void> {
  const fr = await sql<{ id: string; external_id: number }[]>`
    SELECT f.id, f.external_id
    FROM franchise f
    LEFT JOIN subscriptions s ON s.franchise_id = f.id
    WHERE f.source = 'tmdb' AND f.external_id IS NOT NULL
    GROUP BY f.id
    ORDER BY count(s.user_id) DESC, f.updated_at DESC`
  console.log(`[tmdb] ${fr.length} shows to re-materialize`)
  let processed = 0
  let done = 0
  let failed = 0
  for (const f of fr) {
    try {
      const res = await refreshTvShow(f.id, f.external_id)
      if (res.refreshed) done++
      else failed++
      processed++
      console.log(`[tmdb] show ${f.external_id}: refreshed=${res.refreshed} attached=${res.attached} (${processed}/${fr.length})`)
    } catch (err) {
      failed++
      processed++
      console.warn(`[tmdb] show ${f.external_id} failed:`, (err as Error).message)
    }
  }
  console.log(`[tmdb] refreshed ${done}/${fr.length} (unavailable/failed ${failed})`)
}

await backfillAniList()
await backfillAniListEnrichment()
await backfillTmdb()

const stats = await sql<{
  empty_eps: number
  empty_studios: number
  media_with_videos: number
  full_enrichment: number
}[]>`
  SELECT count(*) FILTER (WHERE episodes_list = '[]'::jsonb) AS empty_eps,
         count(*) FILTER (WHERE studios = '[]'::jsonb) AS empty_studios,
         count(*) FILTER (WHERE videos <> '[]'::jsonb) AS media_with_videos,
         (SELECT count(*) FROM franchise WHERE enrichment->>'level' = 'full') AS full_enrichment
  FROM media`
console.log(
  `[done] empty episode lists: ${stats[0]?.empty_eps}; empty studios: ${stats[0]?.empty_studios}; ` +
  `media with videos: ${stats[0]?.media_with_videos}; fully enriched franchises: ${stats[0]?.full_enrichment}`,
)

await sql.end()
