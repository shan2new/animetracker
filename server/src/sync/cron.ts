import cron from 'node-cron'
import { env } from '../env.js'
import { refreshSubscribedNews } from '../news/service.js'
import {
  refreshSubscribedAniListEnrichment,
  refreshSubscribedTmdbRecommendations,
} from '../services/catalogEnrichment.js'
import { materialiseTopRecommendations } from '../services/recommendations.js'
import { refreshAnimeMetadataFallback } from '../services/animeVideoFallback.js'
import { refreshPreferredAvailability } from '../services/watchAvailability.js'
import { clampUnairedProgress } from '../services/library.js'
import { purgeCommentTombstones } from '../services/commentRetention.js'
import { alertStaleReports } from '../services/moderationAlert.js'
import { tmdbEnabled } from '../tmdb/client.js'
import {
  attachNewSeasons,
  refreshAiring,
  refreshAiringTv,
  seedTrending,
  seedTrendingTv,
  sweepAniListTrailers,
} from './sync.js'

let started = false

/** Register the scheduled sync jobs (idempotent; safe to call once at boot). */
export function startCron(): void {
  if (started) return
  started = true

  // The unaired-season progress repair (`clampUnairedProgress`): once at boot, then hourly — a
  // no-op once the rows are clean.
  const repairUnaired = async () => {
    try {
      const n = await clampUnairedProgress()
      if (n > 0) console.log(`[cron] clampUnairedProgress: ${n} rows`)
    } catch (err) {
      console.error('[cron] clampUnairedProgress failed:', (err as Error).message)
    }
  }
  void repairUnaired()

  // Hourly: keep airing schedules + "out now" fresh (both sources).
  cron.schedule('0 * * * *', async () => {
    await repairUnaired()
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
    try {
      const result = await sweepAniListTrailers()
      if (result.providerReachable === false) {
        console.warn('[cron] AniList catalogue metadata sweep deferred: provider unavailable')
      } else if (result.scanned > 0) {
        console.log(
          `[cron] AniList catalogue metadata sweep: scanned ${result.scanned}, upserted ${result.upserted}, complete=${result.complete}`,
        )
      }
    } catch (err) {
      console.error('[cron] AniList trailer sweep failed:', (err as Error).message)
    }
  })

  // Hourly at :20: while any report has waited more than 12 hours, log it and nudge the operator's
  // webhook (services/moderationAlert.ts) — App Review expects reports acted on within 24 hours, and
  // there is one operator. Its own schedule and catch, so the catalogue jobs cannot delay it.
  cron.schedule('20 * * * *', async () => {
    try {
      await alertStaleReports()
    } catch (err) {
      console.error('[cron] stale report alert failed:', (err as Error).message)
    }
  })

  // Daily 03:10: remove comments their authors deleted more than 30 days ago (social/retention.ts).
  // The tombstone only has to outlive a client's replay of the same POST; past that it is who
  // commented on what, kept after they deleted it. Likes, reports and notifications cascade.
  cron.schedule('10 3 * * *', async () => {
    try {
      const n = await purgeCommentTombstones()
      if (n > 0) console.log(`[cron] purgeCommentTombstones: ${n} comments`)
    } catch (err) {
      console.error('[cron] purgeCommentTombstones failed:', (err as Error).message)
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
  // because AniList outages must not suppress the 05:00 announcement researcher. It also rewrites
  // each refreshed show's ranked recommendation list (and its series-root walk).
  cron.schedule('15 4 * * *', async () => {
    try {
      const { checked, refreshed } = await refreshSubscribedAniListEnrichment()
      console.log(`[cron] anime enrichment: checked ${checked}, refreshed ${refreshed}`)
    } catch (err) {
      console.error('[cron] anime enrichment failed:', (err as Error).message)
    }
  })

  // Daily 04:20: re-read followed TV shows' TMDB recommendation lists (one request per show). The
  // hourly TV refresh keeps their seasons fresh but never rewrites their recommendation edges.
  if (tmdbEnabled()) {
    cron.schedule('20 4 * * *', async () => {
      try {
        const { checked, refreshed } = await refreshSubscribedTmdbRecommendations()
        console.log(`[cron] TV recommendations: checked ${checked}, refreshed ${refreshed}`)
      } catch (err) {
        console.error('[cron] TV recommendations failed:', (err as Error).message)
      }
    })
  }

  // Daily 04:40, after both refreshes: build show pages for every user's top 12 recommendations
  // (today's and tomorrow's lists, capped at 40 titles) so a tap opens a real page instantly.
  cron.schedule('40 4 * * *', async () => {
    try {
      const { users, due, materialised, failed } = await materialiseTopRecommendations({ perUser: 12, cap: 40 })
      console.log(`[cron] recommendation pages: ${users} users, ${due} due, ${materialised} built, ${failed} failed`)
    } catch (err) {
      console.error('[cron] recommendation pages failed:', (err as Error).message)
    }
  })

  // Daily 04:30: repair sparse anime metadata from TMDB independently of AniList. Followed titles
  // are first, then the rest of the materialized catalogue; this never changes AniList identity.
  if (tmdbEnabled()) {
    cron.schedule('30 4 * * *', async () => {
      try {
        const { checked, matched, videos } = await refreshAnimeMetadataFallback()
        console.log(`[cron] anime metadata fallback: checked ${checked}, matched ${matched}, videos ${videos}`)
      } catch (err) {
        console.error('[cron] anime metadata fallback failed:', (err as Error).message)
      }
    })

    // Daily 04:45: keep list-card availability warm only for explicitly saved user countries.
    // This changes no subscriptions and emits no provider-change notifications.
    cron.schedule('45 4 * * *', async () => {
      try {
        const { checked, available } = await refreshPreferredAvailability()
        console.log(`[cron] regional availability: checked ${checked}, available ${available}`)
      } catch (err) {
        console.error('[cron] regional availability failed:', (err as Error).message)
      }
    })
  }

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
