import { seedTrending } from '../sync/sync.js'
import { sql } from '../db/index.js'

const count = Number(process.argv[2]) || undefined
const res = await seedTrending(count)
console.log(`seeded: fetched ${res.fetched} trending, grouped ${res.grouped} new franchises`)
await sql.end()
