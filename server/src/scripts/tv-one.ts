import { sql } from '../db/index.js'
import { getFranchise } from '../services/franchiseView.js'
import { ensureTvFranchise } from '../tmdb/service.js'

const showId = Number(process.argv[2])
if (!Number.isFinite(showId)) {
  console.error('usage: npm run tv -- <tmdbShowId>')
  process.exit(1)
}

const outcome = await ensureTvFranchise(showId)
const f = outcome ? await getFranchise(outcome.franchiseId) : null
console.log(JSON.stringify({ outcome, franchise: f }, null, 2))
await sql.end()
