// User-chosen status buckets, mirroring the AniTrack design (Watching / Completed / Plan).
export type WatchStatus = 'watching' | 'completed' | 'planned'

// One entry the user keeps in their library. Only user-owned data is persisted;
// everything else (covers, airing schedule, episode counts) comes live from AniList.
export interface LibraryEntry {
  id: number // AniList media id
  status: WatchStatus
  progress: number // episodes watched
  addedAt: number // ms epoch
}

// Raw shape returned by the AniList GraphQL API for a Media node.
export interface AniListMedia {
  id: number
  title: { romaji: string | null; english: string | null }
  coverImage: { extraLarge: string | null; large: string | null }
  bannerImage: string | null
  description: string | null
  genres: string[]
  episodes: number | null
  status: 'FINISHED' | 'RELEASING' | 'NOT_YET_RELEASED' | 'CANCELLED' | 'HIATUS' | null
  nextAiringEpisode: { episode: number; airingAt: number } | null
}

// A library entry merged with its live AniList metadata, plus derived fields the UI reads.
export interface Show {
  id: number
  status: WatchStatus
  progress: number

  title: string
  cover: string
  banner: string
  synopsis: string
  genres: string[]
  totalEpisodes: number

  isReleasing: boolean
  airedEpisodes: number // latest episode that has aired
  nextEpisodeNumber: number | null
  nextAiringAt: number | null // ms epoch
  lastAiredAt: number | null // ms epoch (exact from airingSchedules; weekly fallback while loading)
}
