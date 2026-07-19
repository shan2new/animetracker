import type { PartKind } from '../grouping/partKind.js'

export type WatchStatus = 'watching' | 'completed' | 'planned'

/** Which catalogue a franchise (and all its parts) came from. A franchise never mixes sources. */
export type MediaSource = 'anilist' | 'tmdb'

/**
 * Web-sourced "what's next" news for a franchise (announced/airing seasons, films, etc.).
 * Populated out-of-band (research/cron), stored on franchise.upcoming. `release` is a
 * human-readable date or window ("2026-10", "January 2027", "TBA") because announced seasons
 * often have only a window, which AniList doesn't expose as a per-episode airing time.
 */
export interface FranchiseUpcoming {
  status: string // airing | upcoming_dated | announced | announced_no_date | recently_aired | rumored | concluded
  next: string // e.g. "Season 2", "Infinity Castle - Part 2 (movie)"
  release: string // human-readable date or window
  note: string | null
  source: string | null
  checked: string | null // ISO date the info was last verified
}

export interface FranchisePart {
  mediaId: number
  kind: PartKind
  sequence: number
  label: string
  title: string
  cover: string
  banner: string
  format: string | null
  status: string | null
  isReleasing: boolean
  totalEpisodes: number
  airedEpisodes: number
  nextEpisodeNumber: number | null
  nextAiringAt: number | null
  lastAiredAt: number | null
  synopsis: string
  genres: string[]
  progress: number
}

export interface Franchise {
  id: string
  source: MediaSource
  title: string
  cover: string
  banner: string
  synopsis: string
  genres: string[]
  isReleasing: boolean
  partCounts: Partial<Record<PartKind, number>>
  parts: FranchisePart[]
  subscription: { status: WatchStatus } | null
  upcoming: FranchiseUpcoming | null
}

export interface FranchiseSummary {
  id: string
  source: MediaSource
  title: string
  cover: string
  banner: string
  isReleasing: boolean
  partCount: number
  nextAiringAt: number | null
  upcoming: FranchiseUpcoming | null
  status?: WatchStatus
  behind?: number
  newParts?: number
}

export type LibraryFranchise = Franchise & { status: WatchStatus; behind: number; newParts: number }

/** A stored per-user notification (announcement news for a subscribed franchise). */
export interface NotificationItem {
  id: string
  franchiseId: string
  kind: string // news_rumored | news_announced | news_dated
  title: string // franchise title
  body: string // e.g. "Season 4 announced — release TBA"
  createdAt: number // ms epoch
  readAt: number | null // ms epoch, null while unread
}
