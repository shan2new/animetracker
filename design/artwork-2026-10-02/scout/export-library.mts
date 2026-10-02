// Read-only visual scouting snapshot. No identity credentials or account metadata is exported.
import { writeFile } from 'node:fs/promises'
const { env } = await import('../../../server/src/env.js')
const connection = new URL(env.DATABASE_URL)
connection.searchParams.set('options', '-c default_transaction_read_only=on')
env.DATABASE_URL = connection.toString()
const { sql } = await import('../../../server/src/db/index.js')
try {
  const [guard] = await sql`show default_transaction_read_only`
  if (guard.default_transaction_read_only !== 'on') throw new Error('Read-only connection required')
  const [account] = await sql`
    select user_id, count(*)::int as count from subscriptions group by user_id order by count(*) desc limit 1
  `
  if (!account) throw new Error('No real library to inspect')
  const { getLibrary, getFranchise } = await import('../../../server/src/services/franchiseView.js')
  const library = await getLibrary(account.user_id, 0)
  const snapshot: Record<string, unknown> = {'/me/library': {franchises: library, prevOpenedAt: 0}}
  const { getFeed } = await import('../../../server/src/feed/service.js')
  snapshot['/me/feed?tab=following'] = await getFeed(account.user_id, 'following')
  snapshot['/me/feed?tab=foryou'] = await getFeed(account.user_id, 'foryou')
  for (const f of library.slice(0, 4)) {
    snapshot[`/franchises/${f.id}`] = await getFranchise(f.id, account.user_id)
  }
  await writeFile(new URL('./library-snapshot.local.json', import.meta.url), JSON.stringify(snapshot, null, 2) + '\n')
  console.log(JSON.stringify({libraryCount: library.length, detailExamples: library.slice(0, 4).map(f => ({id:f.id, title:f.title}))}))
} finally { await sql.end() }
