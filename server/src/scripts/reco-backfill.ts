// Backfill the ranked recommendation lists: re-enrich every followed show, which rewrites its
// recommendation edges (20, ranked, with votes), the facts about every title on them
// (recommendation_targets) and each title's series root. Idempotent; run it once after migration
// 0009 and whenever the lists need a full refresh.
//
//   npm run reco:backfill                       every followed show
//   npm run reco:backfill -- --user=<clerkId>   one account's shows
//   npm run reco:backfill -- <franchiseId>       one show
//
// Serial, and every AniList request (the enrichment fetch and each series-root walk level) is
// spaced ~2.1 s apart — AniList drops to 30 requests/minute when degraded. TV shows need
// TMDB_ACCESS_TOKEN; without it they are skipped (anime-only mode).

import { asc, eq } from 'drizzle-orm'
import { db, sql } from '../db/index.js'
import { franchise, recommendationEdges, subscriptions, users } from '../db/schema.js'
import { refreshFranchiseEnrichment } from '../services/catalogEnrichment.js'
import { tmdbEnabled } from '../tmdb/client.js'
import { createPacer } from '../util/pacer.js'

const args = process.argv.slice(2).map((arg) => arg.trim())
const userArg = args.find((arg) => arg.startsWith('--user='))?.slice('--user='.length)
const only = args.find((arg) => !arg.startsWith('--'))
const pace = createPacer(2_100)

try {
  const followed = await db
    .selectDistinct({ id: franchise.id, title: franchise.title, source: franchise.source })
    .from(subscriptions)
    .innerJoin(franchise, eq(franchise.id, subscriptions.franchiseId))
    .innerJoin(users, eq(users.id, subscriptions.userId))
    .where(userArg ? eq(users.clerkId, userArg) : undefined)
    .orderBy(asc(franchise.source), asc(franchise.title))
  const rows = only ? followed.filter((row) => row.id === only) : followed
  if (rows.length === 0) console.log('[reco:backfill] no followed show matches')

  let refreshed = 0
  let skipped = 0
  let failed = 0
  const started = Date.now()
  for (const [index, row] of rows.entries()) {
    const label = `[${index + 1}/${rows.length}] ${row.source} ${row.title}`
    if (row.source === 'tmdb' && !tmdbEnabled()) {
      skipped++
      console.log(`${label}: skipped (TMDB_ACCESS_TOKEN unset)`)
      continue
    }
    try {
      const ok = await refreshFranchiseEnrichment(row.id, {
        force: true,
        pace,
        anilistRequest: { maxRetries: 4, timeoutMs: 20_000 },
        tmdbRequest: { maxRetries: 3, timeoutMs: 15_000 },
      })
      const edges = await db
        .select({ rank: recommendationEdges.rank })
        .from(recommendationEdges)
        .where(eq(recommendationEdges.franchiseId, row.id))
      if (ok) refreshed++
      else failed++
      console.log(`${label}: ${ok ? 'ok' : 'no data'} · ${edges.filter((edge) => edge.rank != null).length} ranked edges`)
    } catch (error) {
      failed++
      console.log(`${label}: FAILED ${error instanceof Error ? error.message : String(error)}`)
    }
  }
  console.log(
    `[reco:backfill] ${refreshed} refreshed, ${skipped} skipped, ${failed} failed in ${Math.round((Date.now() - started) / 1000)} s`,
  )
} finally {
  await sql.end()
}
