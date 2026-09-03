import type { PartKind } from '../grouping/partKind.js'

/**
 * The user's own verdict on a franchise. Stored in `subscriptions.status`, which is a `text()`
 * column — adding a value needs no migration.
 */
export type WatchStatus = 'watching' | 'completed' | 'planned' | 'paused' | 'dropped'

/** Which catalogue a franchise (and all its parts) came from. A franchise never mixes sources. */
export type MediaSource = 'anilist' | 'tmdb'

/** How a title can be streamed in the requested country. Purchase/rental stores are excluded. */
export type WatchAccess = 'subscription' | 'free' | 'ads'
export type WatchAvailabilityStatus = 'available' | 'not_available' | 'unmatched' | 'disabled'

export interface WatchProvider {
  id: number
  name: string
  logo: string | null
  access: WatchAccess
}

/** Country-specific streaming availability returned by GET /franchises/:id/watch-providers. */
export interface WatchAvailability {
  /** ISO 3166-1 alpha-2 country code echoed from the request. */
  country: string
  /** Why providers is populated or empty; consumers must not infer this from array length. */
  status: WatchAvailabilityStatus
  /** Subscription first, then free/ad-supported; TMDB display priority within each group. */
  providers: WatchProvider[]
  /** TMDB's regional watch page. Provider entries do not include reliable deep links. */
  link: string | null
  /** Required attribution for TMDB watch-provider data. */
  attribution: 'JustWatch'
}

/** Explicit artwork orientation. Legacy `cover`/`banner` remain for older clients. */
export interface ArtworkSet {
  portrait: string | null
  landscape: string | null
}

export type VideoKind = 'trailer' | 'teaser' | 'announcement' | 'featurette' | 'clip' | 'other'

/** A catalogue-curated video. AniTrack stores provider ids/links; it never hosts the video. */
export interface CatalogVideo {
  id: string
  site: string
  kind: VideoKind
  title: string | null
  url: string | null
  thumbnail: string | null
  official: boolean | null
  language: string | null
  country: string | null
  publishedAt: string | null
}

export type VideoScope =
  | { type: 'franchise' }
  | { type: 'part'; mediaId: number; label: string }

/** A video returned to clients, annotated with the franchise/part it belongs to. */
export type FranchiseVideo = CatalogVideo & { scope: VideoScope }

export interface ContentRating {
  country: string
  rating: string
}

export interface AudienceInfo {
  isAdult: boolean | null
  /** Rating for the caller-supplied country, or null when that market has no rating. */
  contentRating: ContentRating | null
  /** Every country rating in the catalogue, so clients can change region without re-fetching. */
  availableRatings: ContentRating[]
}

export interface CatalogPerson {
  source: MediaSource
  externalId: number
  name: string
  role: string | null
  image: string | null
}

export interface FranchisePeople {
  creators: CatalogPerson[]
  directors: CatalogPerson[]
  cast: CatalogPerson[]
}

/** Source-native recommendation; franchiseId is filled when that title is already materialized. */
export interface RelatedTitle {
  source: MediaSource
  externalId: number
  franchiseId: string | null
  title: string
  year: number | null
  images: ArtworkSet
}

/** Deep catalogue metadata persisted separately from the latency-sensitive search index. */
export interface FranchiseEnrichment {
  level: 'basic' | 'full'
  themes: string[]
  isAdult: boolean | null
  contentRatings: ContentRating[]
  people: FranchisePeople
  related: RelatedTitle[]
  /** Show/franchise-level videos; part-specific videos live on `media.videos`. */
  videos: CatalogVideo[]
  /**
   * Internal provenance/cache state for AniList-owned anime enriched from TMDB. This never changes
   * franchise identity: `source` remains AniList and the matched TMDB title is metadata-only.
   */
  videoFallback?: {
    source: 'tmdb'
    mediaType: 'tv' | 'movie'
    externalId: number | null
    status: 'matched' | 'unmatched'
    checkedAt: string
  }
  checkedAt: string
}

/**
 * "What's next" for a franchise (announced/airing seasons, films, etc.). Usually populated by
 * web research and stored on franchise.upcoming; the read path can also derive the same shape from
 * a future part already confirmed by AniList/TMDB. `release` is a human-readable date or window
 * ("2026-10", "January 2027", "TBA") because announcements often provide only a window.
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
 * `FranchiseUpcoming.release` resolved into something orderable. Derived on read (never stored),
 * so a row written before this existed still ships one — see `services/releaseWindow.ts`.
 *
 * `release` remains the only thing a client PRINTS; `sortKey` is the only thing it SORTS BY.
 * Clients must not parse `release` themselves: an ISO-only reading of a corpus full of "October
 * 2026" and "Summer 2027" silently orders a franchise's return by January of its year.
 */
export interface ReleaseWindow {
  /** "YYYY-MM-DD" | "YYYY-MM" | "YYYY" — the window at the precision actually known, or null. */
  date: string | null
  /**
   * day/month = `date` is exactly what was announced · quarter = a broadcast season or Qn, whose
   * `date` is that quarter's FIRST month (safe to order by, never to print as a month) · year =
   * only the year may be printed · unknown = TBA, rumored, or prose with no date in it.
   */
  precision: 'day' | 'month' | 'quarter' | 'year' | 'unknown'
  /**
   * `yyyymmdd` of the EARLIEST instant the window can mean, so ascending = soonest first.
   * `null` (unknown) sorts last — never as 0, and never as January of a year nobody stated.
   */
  sortKey: number | null
}

/** What the API actually ships for `upcoming`: the stored news plus its resolved window. */
export type FranchiseUpcomingView = FranchiseUpcoming & { releaseWindow: ReleaseWindow }

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

/** The first already-aired episode the authenticated user has not watched. */
export interface ContinueWatching {
  mediaId: number
  partLabel: string
  episode: EpisodeMeta
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
  images: ArtworkSet
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
  /**
   * Dated episodes inside Schedule's window (`SCHEDULE_WINDOW`: 8 days back … 15 days ahead of
   * now), oldest first. Present on EVERY payload — list, library and detail — because it is the
   * one per-episode fact Schedule needs and it is tiny; `episodes` stays detail-only. A weekly
   * show therefore appears on every one of its air dates in the window, not once on its next.
   * Empty when nothing in the window is dated.
   */
  airings: Airing[]
  /** Part-specific trailers/teasers. Populated on detail/library; safe to ignore when empty. */
  videos: FranchiseVideo[]
}

/** One dated episode: its number and its air instant (ms epoch; TMDB's is date-only at 17:00 UTC). */
export interface Airing {
  episode: number
  at: number
}

export interface Franchise {
  id: string
  source: MediaSource
  title: string
  cover: string
  banner: string
  images: ArtworkSet
  synopsis: string
  genres: string[]
  isReleasing: boolean
  partCounts: Partial<Record<PartKind, number>>
  parts: FranchisePart[]
  subscription: { status: WatchStatus; addedAt: number } | null
  upcoming: FranchiseUpcomingView | null
  /** Premiere year of the franchise (earliest dated part). */
  year: number | null
  /** Studios (anime) or networks (TV) for the primary installment — the detail meta line. */
  studios: string[]
  /** Conservative, spoiler-screened themes. AniList spoiler-tag flags are honoured. */
  themes: string[]
  featuredVideo: FranchiseVideo | null
  videos: FranchiseVideo[]
  audience: AudienceInfo
  people: FranchisePeople
  related: RelatedTitle[]
  continueWatching: ContinueWatching | null
}

export interface FranchiseSummary {
  id: string
  source: MediaSource
  title: string
  cover: string
  banner: string
  images: ArtworkSet
  isReleasing: boolean
  partCount: number
  nextAiringAt: number | null
  upcoming: FranchiseUpcomingView | null
  /** Premiere year (for "Anime · 2023" / "TV · 2024" on discover cards). */
  year: number | null
  themes: string[]
  featuredVideo: FranchiseVideo | null
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
