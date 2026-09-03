// Idempotent TMDB trailer backfill for AniList-owned anime. Passing a franchise UUID targets one
// title; without one, every followed anime (up to the library sweep cap) is refreshed.

import { sql } from '../db/index.js'
import {
  refreshAnimeVideoFallback,
  refreshSubscribedAnimeVideoFallback,
} from '../services/animeVideoFallback.js'

const franchiseId = process.argv[2]?.trim()

try {
  if (franchiseId) {
    const result = await refreshAnimeVideoFallback(franchiseId, {
      force: true,
      request: { maxRetries: 1, timeoutMs: 8_000 },
    })
    console.log(`[anime-videos] ${franchiseId}:`, result)
  } else {
    const result = await refreshSubscribedAnimeVideoFallback(100, { force: true })
    console.log('[anime-videos] subscribed:', result)
  }
} finally {
  await sql.end()
}
