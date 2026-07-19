// Manual news-agent run: `npm run news -- <franchise-id | title fragment>`.
// With no argument, runs the same pass the daily cron does (subscribed franchises).
import { ilike } from 'drizzle-orm'
import { db, sql } from '../db/index.js'
import { franchise } from '../db/schema.js'
import { refreshFranchiseNews, refreshSubscribedNews } from '../news/service.js'

const arg = process.argv[2]

async function main() {
  if (!arg) {
    const summary = await refreshSubscribedNews()
    console.log('refreshSubscribedNews:', summary)
    return
  }

  const isUuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(arg)
  let id = arg
  if (!isUuid) {
    const matches = await db
      .select({ id: franchise.id, title: franchise.title })
      .from(franchise)
      .where(ilike(franchise.title, `%${arg}%`))
      .limit(5)
    const first = matches[0]
    if (!first) throw new Error(`no franchise matching "${arg}"`)
    if (matches.length > 1) console.log('multiple matches, using first:', matches.map((m) => m.title).join(' | '))
    id = first.id
    console.log(`franchise: ${first.title} (${id})`)
  }

  const result = await refreshFranchiseNews(id)
  console.log('refreshFranchiseNews:', result)
}

main()
  .catch((err) => {
    console.error(err)
    process.exitCode = 1
  })
  .finally(() => sql.end())
