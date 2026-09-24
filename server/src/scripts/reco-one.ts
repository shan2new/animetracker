// Print one user's "Recommended for you" list with the full score breakdown — the tool for
// checking the ranking against a real library (run it on production before an iOS release).
//
//   npm run reco -- <clerkId>                 today's served list (12, rotated)
//   npm run reco -- <clerkId> --limit=20
//   npm run reco -- <clerkId> --reference     MMR order, no daily rotation (the spike's view)
//
// Read-only: nothing is materialised or written.

import { eq } from 'drizzle-orm'
import { db, sql } from '../db/index.js'
import { users } from '../db/schema.js'
import { loadRankInput } from '../services/recommendations.js'
import { rankRecommendations, type RankedRecommendation } from '../services/recommendationRank.js'

const clerkId = process.argv[2]?.trim()
const limitArg = process.argv.find((arg) => arg.startsWith('--limit='))
const limit = Math.max(1, Math.min(30, Number(limitArg?.slice('--limit='.length)) || 12))
const reference = process.argv.includes('--reference')

function sentence(item: RankedRecommendation): string {
  const [a, b] = item.reason.seeds.map((seed) => seed.title)
  switch (item.reason.kind) {
    case 'consensus':
      return item.reason.count >= 3 ? `Like ${a} and ${item.reason.count - 1} more of yours` : `Like ${a} and ${b}`
    case 'finished':
      return `Because you finished ${a}`
    case 'watching':
      return `Because you're watching ${a}`
    case 'watched':
      return `Because you watched ${a}`
    case 'planned':
      return `Like ${a}, on your list`
    case 'world':
      return `From the world of ${a}`
  }
}

const f = (value: number | null, digits = 2) => (value == null ? '–' : value.toFixed(digits))

try {
  if (!clerkId) {
    console.error('usage: npm run reco -- <clerkId> [--limit=N] [--reference]')
    process.exitCode = 1
  } else {
    const [user] = await db.select({ id: users.id }).from(users).where(eq(users.clerkId, clerkId)).limit(1)
    if (!user) {
      console.error(`no user with clerk id ${clerkId}`)
      process.exitCode = 1
    } else {
      const now = Date.now()
      const started = performance.now()
      const { input } = await loadRankInput(user.id, now)
      const loadedMs = performance.now() - started
      const result = rankRecommendations(input, { userId: user.id, limit, rotation: !reference })
      const rankedMs = performance.now() - started - loadedMs
      const bySource = (source: string) => input.seeds.filter((seed) => seed.source === source).length
      console.log(
        `library ${input.seeds.length} (${bySource('anilist')} anime, ${bySource('tmdb')} TV) · ` +
          `edges ${input.edges.length} · targets ${input.targets.length} · feedback ${input.feedback.length} · ` +
          `load ${loadedMs.toFixed(0)} ms, rank ${rankedMs.toFixed(0)} ms · ${new Date(now).toISOString().slice(0, 10)} UTC` +
          (reference ? ' · REFERENCE (no rotation)' : ''),
      )
      console.log(
        `candidates ${result.stats.candidates} · TV share ${result.stats.tvShare} → quota ${result.stats.tvQuota} · ` +
          `excluded edges ${JSON.stringify(result.stats.excludedEdges)} · ` +
          `excluded candidates ${JSON.stringify(result.stats.excludedCandidates)}` +
          (result.stats.penalisedSeeds.length ? ` · penalised ${result.stats.penalisedSeeds.join(', ')}` : ''),
      )
      console.log('')
      for (const [index, item] of result.items.entries()) {
        const b = item.breakdown
        const quality = b.averageScore != null ? `q ${f(b.quality)} (avg ${b.averageScore}, pop ${b.popularity != null ? Math.round(b.popularity / 1000) + 'k' : '–'})` : `q ${f(b.quality)} (unmeasured)`
        console.log(
          `${String(index + 1).padStart(2)}. ${item.title.slice(0, 38).padEnd(38)} ${item.source.padEnd(7)} ` +
            `${item.franchiseId ? 'page ' : 'new  '} score ${f(item.score, 3)} | cf ${f(b.cf, 3)} n ${b.nSeeds} ` +
            `x${f(b.consensus)} ${quality} fit ${f(b.fit)} fresh ${b.fresh} pop ${f(b.popDamp)}` +
            `${b.era !== 1 ? ` era ${b.era}` : ''}${b.sameWorld ? ' sameWorld' : ''} jitter ${f(b.jitter, 3)}`,
        )
        console.log(
          `    ${sentence(item)}  [${b.contributions.slice(0, 4).map((c) => `${c.title} ${f(c.value, 3)}`).join(', ')}]  ${item.key}`,
        )
      }
    }
  }
} finally {
  await sql.end()
}
