import type { PartKind } from '../grouping/partKind.js'

/**
 * The user's own verdict on a franchise. Stored in `subscriptions.status`, which is a `text()`
 * column — adding a value needs no migration.
 */
export type WatchStatus = 'watching' | 'completed' | 'planned' | 'paused' | 'dropped'

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

/**
 * Per-episode metadata. Richness is source-dependent: TMDB gives title/overview/still/runtime/date;
 * AniList gives per-episode air dates (from airingSchedule) and best-effort titles/stills (from
 * streamingEpisodes), but no per-episode overview. Any field may be null/absent.
 */
export interface EpisodeMeta {
  number: number
  title: string | null
  airDate: number | null // ms epoch
  overview: string | null
  still: string | null // thumbnail/still image url
  runtime: number | null // minutes
}

/**
 * How precisely the next release instant is known. Sources differ in kind, not just in quality:
 * AniList publishes a real broadcast instant, TMDB publishes a calendar date that the sync
 * synthesizes to 17:00 UTC. Stating it here is what stops a client from inferring precision from
 * `source` — and from ever rendering a clock time that nobody published.
 */
export interface ReleasePrecision {
  /** exact = `at` is a real instant · date_only = `date` is the fact, `at` is synthesized · unknown = nothing scheduled. */
  precision: 'exact' | 'date_only' | 'unknown'
  /** ms epoch. Authoritative only when `precision` is "exact"; synthesized when "date_only". */
  at: number | null
  /** "YYYY-MM-DD" (UTC). Authoritative only when `precision` is "date_only". */
  date: string | null
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
  /** Derived compatibility field: always `release.at`. Prefer `release` for anything user-facing. */
  nextAiringAt: number | null
  /** The honest shape of the next release date. See ReleasePrecision. */
  release: ReleasePrecision
  lastAiredAt: number | null
  synopsis: string
  genres: string[]
  progress: number
  /** Premiere/season year (AniList seasonYear or TMDB season air-date year). */
  year: number | null
  /** Studios (AniList) or networks (TMDB) — names only, for the detail meta line. */
  studios: string[]
  /**
   * Episodes sharing the next airing date. `> 1` marks a same-day multi-episode / full-season
   * "drop" (TMDB), so Schedule can label it "Season drop" without shipping the whole episode list.
   * Computed from `episodes` server-side; `0` when nothing is upcoming or episode data is absent.
   */
  nextAiringCount: number
  /**
   * Full per-episode list. Populated ONLY on the franchise-detail response (`GET /franchises/:id`);
   * empty on the library/summary payloads to keep those lean.
   */
  episodes: EpisodeMeta[]
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
  subscription: { status: WatchStatus; addedAt: number } | null
  upcoming: FranchiseUpcoming | null
  /** Premiere year of the franchise (earliest dated part). */
  year: number | null
  /** Studios (anime) or networks (TV) for the primary installment — the detail meta line. */
  studios: string[]
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
  /** Premiere year (for "Anime · 2023" / "TV · 2024" on discover cards). */
  year: number | null
  status?: WatchStatus
  behind?: number
  newParts?: number
}

export type LibraryFranchise = Franchise & { status: WatchStatus; behind: number; newParts: number }

/** Per-catalogue outcome for a fan-out search, so the client can say which half failed. */
export type SourceOutcome = 'ok' | 'failed' | 'disabled'

/** The envelope every franchise list route returns (`/franchises/trending`, `/search`). */
export interface FranchiseListResponse {
  franchises: FranchiseSummary[]
  /** Set when the query was spell-corrected/completed before searching (see queryCorrect.ts). */
  correctedQuery?: string
  /** The query the caller sent, echoed when `correctedQuery` is present. */
  originalQuery?: string
  /** Per-catalogue outcome. Absent on routes that do not fan out. */
  sources?: { anilist: SourceOutcome; tmdb: SourceOutcome }
}

/**
 * `DELETE /me`. The account and everything it owned are gone, so there is nothing left to
 * describe: the response carries only the fact that the erasure completed.
 *
 * `deleted` is a literal `true` rather than the codebase's usual `{ ok: true }` so a client can
 * never read "the request was accepted" as "the account no longer exists".
 */
export interface AccountDeletedResponse {
  deleted: true
}

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
