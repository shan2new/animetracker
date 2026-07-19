// One-off backfill for the `studios` + `episodes_list` columns added in migration 0004. Media rows
// materialized before those columns existed carry the empty `[]` defaults; this re-fetches each
// catalogue from its source and re-upserts, populating studios + per-episode metadata.
//
//   AniList: re-fetch media by id in batches (fetchByIds now requests studios + streamingEpisodes).
//   TMDB:    re-materialize each show (refreshTvShow fetches /tv/{id}/season/{n} per season).
//
// Idempotent and resilient — per-chunk/per-show failures are logged and skipped, not fatal, so a
// re-run picks up whatever was missed. Usage: npx tsx src/scripts/backfill-episodes.ts

import { fetchByIds } from '../anilist/client.js'
import { sql } from '../db/index.js'
import { toMediaRow, upsertMediaRows } from '../services/mediaStore.js'
import { TMDB_ID_OFFSET } from '../tmdb/mapping.js'
import { refreshTvShow } from '../tmdb/service.js'

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms))

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
  for (const chunk of chunked(ids, 100)) {
    try {
      const medias = await fetchByIds(chunk)
      await upsertMediaRows(medias.map(toMediaRow))
      done += medias.length
    } catch (err) {
      failed += chunk.length
      console.warn(`[anilist] chunk failed:`, (err as Error).message)
    }
    console.log(`[anilist] upserted ${done}/${ids.length} (failed ${failed})`)
    await sleep(500) // be gentle with AniList; gql() already backs off on 429
  }
}

async function backfillTmdb(): Promise<void> {
  const fr = await sql<{ id: string; external_id: number }[]>`
    SELECT id, external_id FROM franchise
    WHERE source = 'tmdb' AND external_id IS NOT NULL
    ORDER BY external_id`
  console.log(`[tmdb] ${fr.length} shows to re-materialize`)
  let done = 0
  let failed = 0
  for (const f of fr) {
    try {
      const res = await refreshTvShow(f.id, f.external_id)
      done++
      console.log(`[tmdb] show ${f.external_id}: refreshed=${res.refreshed} attached=${res.attached} (${done}/${fr.length})`)
    } catch (err) {
      failed++
      console.warn(`[tmdb] show ${f.external_id} failed:`, (err as Error).message)
    }
  }
  console.log(`[tmdb] done ${done}/${fr.length} (failed ${failed})`)
}

await backfillAniList()
await backfillTmdb()

const stats = await sql<{ empty_eps: number; empty_studios: number }[]>`
  SELECT count(*) FILTER (WHERE episodes_list = '[]'::jsonb) AS empty_eps,
         count(*) FILTER (WHERE studios = '[]'::jsonb) AS empty_studios
  FROM media`
console.log(`[done] media still empty — episodes_list: ${stats[0]?.empty_eps}, studios: ${stats[0]?.empty_studios}`)

await sql.end()
