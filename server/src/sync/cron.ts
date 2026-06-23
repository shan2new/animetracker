import cron from 'node-cron'
import { attachNewSeasons, refreshAiring, seedTrending } from './sync.js'

let started = false

/** Register the scheduled sync jobs (idempotent; safe to call once at boot). */
export function startCron(): void {
  if (started) return
  started = true

  // Hourly: keep airing schedules + "out now" fresh.
  cron.schedule('0 * * * *', async () => {
    try {
      const n = await refreshAiring()
      console.log(`[cron] refreshAiring: ${n} releasing media`)
    } catch (err) {
      console.error('[cron] refreshAiring failed:', (err as Error).message)
    }
  })

  // Daily 03:30: re-seed trending franchises + attach newly-aired seasons to followed franchises.
  cron.schedule('30 3 * * *', async () => {
    try {
      const { fetched, grouped } = await seedTrending()
      const attached = await attachNewSeasons()
      console.log(`[cron] daily: fetched ${fetched} trending, grouped ${grouped} new, attached ${attached} parts`)
    } catch (err) {
      console.error('[cron] daily sync failed:', (err as Error).message)
    }
  })
}
