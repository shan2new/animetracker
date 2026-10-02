// Read-only catalogue snapshot for the native visual preview. Run with tsx from server/.
// No account, authentication secret, production user state or upstream provider call is used.
import { writeFile } from 'node:fs/promises'

const { env } = await import('../../server/src/env.js')
const connection = new URL(env.DATABASE_URL)
connection.searchParams.set('options', '-c default_transaction_read_only=on')
env.DATABASE_URL = connection.toString()
const { sql } = await import('../../server/src/db/index.js')
try {
  const [guard] = await sql`show default_transaction_read_only`
  if (guard.default_transaction_read_only !== 'on') throw new Error('Read-only connection required')
  const { getDiscoverGenres, getDiscoverGenrePage } = await import('../../server/src/services/discover.js')
  const { genreByKey } = await import('../../server/src/discover/genres.js')
  const { getTrendingFranchises } = await import('../../server/src/services/franchiseView.js')
  const result: Record<string, unknown> = {
    '/franchises/trending': {franchises: await getTrendingFranchises(10)},
  }
  for (const source of [null, 'anilist', 'tmdb'] as const) {
    const query = source ? `?source=${source}` : ''
    result[`/discover/genres${query}`] = await getDiscoverGenres(source)
    for (const key of ['adventure', 'drama']) {
      result[`/discover/genres/${key}${query}`] = await getDiscoverGenrePage(
        '00000000-0000-0000-0000-000000000000', genreByKey(key)!, {source, limit: 24, offset: 0},
      )
    }
  }
  await writeFile(new URL('./catalog-snapshot.json', import.meta.url), JSON.stringify(result, null, 2) + '\n')
  console.log('Read-only real catalogue snapshot saved for All, Anime and TV.')
} finally {
  await sql.end()
}
