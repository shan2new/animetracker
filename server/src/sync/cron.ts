import cron from 'node-cron'
import { env } from '../env.js'
import { refreshSubscribedNews } from '../news/service.js'
import { refreshSubscribedAniListEnrichment } from '../services/catalogEnrichment.js'
import { tmdbEnabled } from '../tmdb/client.js'
import { attachNewSeasons, refreshAiring, refreshAiringTv, seedTrending, seedTrendingTv } from './sync.js'

let started = false

/** Register the scheduled sync jobs (idempotent; safe to call once at boot). */
export function startCron(): void {
  if (started) return
  started = true

  // Hourly: keep airing schedules + "out now" fresh (both sources).
  cron.schedule('0 * * * *', async () => {
    try {
      const n = await refreshAiring()
      console.log(`[cron] refreshAiring: ${n} releasing media`)
    } catch (err) {
      console.error('[cron] refreshAiring failed:', (err as Error).message)
    }
    if (tmdbEnabled()) {
      try {
        const n = await refreshAiringTv()
        console.log(`[cron] refreshAiringTv: ${n} shows refreshed`)
      } catch (err) {
        console.error('[cron] refreshAiringTv failed:', (err as Error).message)
      }
    }
  })

  // Daily 03:30: re-seed trending franchises + attach newly-aired seasons to followed franchises.
  // The two steps get their own try/catch on purpose: they share only the schedule, and under one
  // catch a transient AniList failure in seedTrending (which calls out first) also skipped
  // attachNewSeasons for the whole day, so followed shows missed new parts for an unrelated reason.
  cron.schedule('30 3 * * *', async () => {
    try {
      const { fetched, grouped } = await seedTrending()
      console.log(`[cron] daily seed: fetched ${fetched} trending, grouped ${grouped} new`)
    } catch (err) {
      console.error('[cron] seedTrending failed:', (err as Error).message)
    }
    try {
      const attached = await attachNewSeasons()
      console.log(`[cron] daily attach: ${attached} parts`)
    } catch (err) {
      console.error('[cron] attachNewSeasons failed:', (err as Error).message)
    }
    if (tmdbEnabled()) {
      try {
        const { fetched, created } = await seedTrendingTv()
        console.log(`[cron] daily TV: fetched ${fetched} trending, created ${created} franchises`)
      } catch (err) {
        console.error('[cron] daily TV sync failed:', (err as Error).message)
      }
    }
  })

  // Daily 04:15: fill graph-heavy anime metadata for followed titles. This is separately caught
  // because AniList outages must not suppress the 05:00 announcement researcher.
  cron.schedule('15 4 * * *', async () => {
    try {
      const { checked, refreshed } = await refreshSubscribedAniListEnrichment()
      console.log(`[cron] anime enrichment: checked ${checked}, refreshed ${refreshed}`)
    } catch (err) {
      console.error('[cron] anime enrichment failed:', (err as Error).message)
    }
  })

  // Daily 05:00: agent-based announcement research over subscribed franchises → notifications.
  if (!env.NEWS_AGENT_DISABLED) {
    cron.schedule('0 5 * * *', async () => {
      try {
        const { checked, notified, skipped } = await refreshSubscribedNews()
        console.log(`[cron] news: checked ${checked} franchises, ${notified} notifications, ${skipped} fresh-enough`)
      } catch (err) {
        console.error('[cron] news refresh failed:', (err as Error).message)
      }
    })
  }
}
