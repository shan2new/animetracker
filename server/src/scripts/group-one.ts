import { sql } from '../db/index.js'
import { getFranchise } from '../services/franchiseView.js'
import { groupFromSeed } from '../grouping/service.js'

const seed = Number(process.argv[2])
if (!Number.isFinite(seed)) {
  console.error('usage: npm run group -- <anilistMediaId>')
  process.exit(1)
}

const outcome = await groupFromSeed(seed)
const f = await getFranchise(outcome.franchiseId)
console.log(JSON.stringify({ outcome, franchise: f }, null, 2))
await sql.end()
