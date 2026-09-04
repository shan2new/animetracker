# AniTrack API contract (v1)

The Node backend (`server/`) and the iOS app (`ios/`) both build against this. Base URL is
configurable; default dev `http://localhost:8787`. All times are **ms since epoch** (Int64).
All endpoints except `GET /health` require `Authorization: Bearer <Clerk session JWT>`.

## Sources

Franchises come from one of two catalogues, tagged by `source` on `Franchise`/`FranchiseSummary`
(a franchise never mixes sources; the field defaults to `"anilist"` when absent, so old clients
keep decoding):

- `"anilist"` — anime. Parts are AniList Media entries; grouping via the relation graph (+LLM).
  A conservatively matched TMDB title may enrich artwork, videos, episode context, ratings, people,
  recommendations and regional availability, but it never changes this identity or creates a
  second TMDB franchise for the same anime. The highest-resolution available portrait and landscape
  become the response's best `cover`/`banner` and `images.portrait`/`images.landscape` pair; when
  both orientations exist, both are returned. AniList art remains in `artwork` as an alternative.
- `"tmdb"` — general TV. One TMDB **show** = one franchise; each TMDB **season** is a part
  (`kind: "season"`, `sequence` = TMDB season_number; season 0 → `kind: "special"`, label
  "Specials"). `mediaId` = `1_000_000_000 + TMDB season id`. Grouping is deterministic (no LLM).
  **Date precision caveat**: TMDB publishes air *dates* only, so `nextAiringAt`/`lastAiredAt`
  for tmdb parts are synthesized at **17:00 UTC** of the air date. Clients must not show
  minute-level countdowns or schedule time-of-day notifications for `source: "tmdb"`.
  **Announced seasons**: a season with a known future air date ships that premiere as its next
  slot (`nextEpisodeNumber: 1`, `nextAiringAt` = premiere at 17:00 UTC), matching how AniList
  announces a season — so clients read the premiere date off `nextAiringAt` for either source.
  A season with no air date yet has `nextAiringAt: null` and is genuinely undated.
  **Attribution**: any client surface using this data must show the TMDB logo and the line
  "This product uses the TMDB API but is not endorsed or certified by TMDB."

## Core JSON shapes

### ArtworkSet

Artwork orientation is explicit everywhere it is useful: franchise, summary, part and related
title. A missing landscape asset is `null`; the backend never puts a portrait poster into the
landscape slot. The legacy `cover`/`banner` strings remain for older clients.

```jsonc
{
  "portrait": "https://…" | null,
  "landscape": "https://…" | null
}
```

### ArtworkGallery

`artwork` sits beside the best-pair `images` field on franchises, summaries and parts. It exposes
ranked alternatives so iOS can choose portrait artwork for lists/share sheets and landscape art for
hero, episode and horizontal-share layouts without URL guessing. Arrays are de-duplicated and
capped at six; `logos` is populated when the linked catalogue has one.

```jsonc
{
  "portraits": [{
    "url": "https://…", "source": "tmdb", "width": 2000, "height": 3000,
    "language": "en", "score": 5.31
  }],
  "landscapes": [{
    "url": "https://…", "source": "tmdb", "width": 3840, "height": 2160,
    "language": null, "score": 5.02
  }],
  "logos": []
}
```

### FranchiseVideo

Catalogue-curated external video metadata. AniTrack does not proxy or host video bytes. `url` may
be opened directly when the provider is supported; `site` + `id` are the durable fallback. A video
can belong to the whole franchise or one exact season/movie. `featuredVideo` is selected by the
backend, preferring an upcoming/current part before video type, then official status and recency.

```jsonc
{
  "id": "ldfEtPf3CfQ",
  "site": "youtube",
  "kind": "announcement", // trailer | teaser | announcement | featurette | clip | other
  "title": "Season 6 Announcement" | null,
  "url": "https://www.youtube.com/watch?v=ldfEtPf3CfQ" | null,
  "thumbnail": "https://…" | null,
  "official": true | false | null,
  "language": "en" | null,
  "country": "US" | null,
  "publishedAt": "2026-01-05T00:00:00.000Z" | null,
  "scope": { "type": "franchise" }
           | { "type": "part", "mediaId": 1000123456, "label": "Season 6" }
}
```

AniList currently supplies at most one trailer id/thumbnail and does not state its official flag
or publish date. TMDB supplies show- and season-level trailers, teasers, clips and featurettes; an
official renewal/return announcement is normalized to `kind: "announcement"`. Empty means the
catalogue has no usable external video, not that playback failed.

For an AniList franchise, source-native videos remain part-scoped. The backend also uses the same
title/year/Japanese-animation match as WatchAvailability to add TMDB videos with franchise scope.
That fallback is refreshed on exact Search, Detail, Subscribe, and a daily catalogue-wide sweep
that prioritizes followed anime.
The public shape is unchanged: clients consume `featuredVideo` and `videos` without branching on
which catalogue supplied the record. An upcoming/current part-scoped video wins featured selection;
a franchise campaign wins over trailers tied only to finished parts, so old Season 1 art does not
hide a newly published fallback trailer.

### EpisodeMeta
Per-episode metadata. TMDB gives title/overview/still/runtime/date from the season endpoint. AniList
gives exact airing instants plus best-effort streaming titles/thumbnails; when a conservative
title/year/episode-count match identifies a TMDB season, the backend fills missing descriptive
fields and horizontal stills while preserving AniList's exact airing instant. Any field may be null.
```jsonc
{
  "number": 1,
  "title": "The North Remembers" | null,
  "airDate": 1333472400000 | null,   // ms epoch (TMDB 17:00 UTC); null for AniList
  "overview": "…" | null,            // null for AniList
  "still": "https://…" | null,       // thumbnail
  "runtime": 51 | null               // minutes
}
```

### FranchisePart
A single installment (one season/movie/OVA/etc.) inside a franchise, merged with the
authenticated user's progress.
```jsonc
{
  "mediaId": 16498,
  "kind": "season",          // season | movie | ova | ona | special | music
  "sequence": 1,              // order within its kind
  "watchOrder": 1,            // one global chronology across seasons, movies and specials
  "relationship": "SEQUEL", // source relation when known; otherwise null
  "optional": false,          // true only for source-identified side/optional material
  "label": "Season 1",       // human label the LLM/grouping assigned
  "title": "Attack on Titan",
  "cover": "https://…",
  "banner": "https://…",
  "images": { "portrait": "https://…", "landscape": "https://…" },
  "artwork": ArtworkGallery,
  "format": "TV",            // raw AniList format
  "status": "FINISHED",      // raw AniList status
  "isReleasing": false,
  "totalEpisodes": 25,
  "airedEpisodes": 25,        // latest aired ep number; always 0 while status is NOT_YET_RELEASED
                              // (an announced part has aired nothing, whatever `totalEpisodes` says)
                              // Derived from catalogue airing data ONLY — never from `progress`:
                              // `nextEpisodeNumber - 1` when a next slot exists; for a RELEASING
                              // part with no next slot (the window between a finale airing and the
                              // source flipping status) the latest episode in `episodes` whose
                              // `airDate` has passed, or `totalEpisodes` when the list is undated.
  "nextEpisodeNumber": null,  // 1 on a dated NOT_YET_RELEASED part — the premiere is the next slot
  "nextAiringAt": null,       // ms epoch or null. DERIVED compatibility field: always == release.at
  "release": {                // how precisely the next release is known — state it, never infer it
    "precision": "exact",     // exact | date_only | unknown
    "at": 1700000000000,      // ms epoch; authoritative only when precision is "exact"
    "date": null              // "YYYY-MM-DD" (UTC); authoritative only when precision is "date_only"
  },
  "lastAiredAt": 1372000000000, // ms epoch or null
  "synopsis": "…",
  "genres": ["Action","Drama"],
  "progress": 25,             // user's watched count for THIS part (0 if not subscribed/unwatched)
  "year": 2013,               // premiere/season year, or null
  "studios": ["Wit Studio"],  // studios (anime) or networks (TV) — names only
  "nextAiringCount": 1,       // episodes sharing the next airing date; >1 ⇒ a full-season "drop"
  "episodes": [ EpisodeMeta, … ], // FULL list on GET /franchises/:id ONLY; [] on list/library payloads
  "airings": [ Airing, … ],    // dated episodes inside Schedule's window, oldest first — on EVERY payload
  "videos": [ FranchiseVideo, … ] // trailers/teasers scoped to this exact part
}
```

### Airing
One dated episode of a part, for the Schedule calendar. `airings` covers the window **8 days back
… 15 days ahead** of the request (`SCHEDULE_WINDOW` in `franchiseView.ts` — a day wider than the
client's own −7…+14 so no timezone sees an edge day undated; clients window precisely). Merged from
the dated episode list (TMDB always; AniList after `backfill-episodes`), the catalogue's next slot
and `lastAiredAt`, de-duplicated by episode number — the list wins. Present on list, library **and**
detail payloads; a weekly show therefore appears on every air date in the window, not once on its
next. Empty when nothing in the window is dated.
```jsonc
{
  "episode": 14,
  "at": 1756226400000    // ms epoch; TMDB's is date-only (17:00 UTC) — read it in the source's calendar
}
```

### Franchise (full detail — `GET /franchises/:id`)
```jsonc
{
  "id": "uuid",
  "source": "anilist",             // anilist | tmdb (default anilist)
  "title": "Attack on Titan",
  "cover": "https://…",
  "banner": "https://…",
  "images": { "portrait": "https://…", "landscape": "https://…" },
  "artwork": ArtworkGallery,
  "synopsis": "…",
  "genres": ["Action","Drama"],
  "isReleasing": true,             // any part currently releasing
  "partCounts": { "season": 4, "movie": 2, "ova": 3, "special": 1 },
  "parts": [ FranchisePart, … ],   // ordered by global watchOrder; each part carries its `episodes`
  "subscription": { "status": "watching", "addedAt": 1700000000000 } | null,  // addedAt = ms epoch the user subscribed
  "upcoming": FranchiseUpcoming | null,  // confirmed/rumored "what's next" — see below
  "year": 2013,                    // premiere year (earliest dated part), or null
  "studios": ["Wit Studio"],       // primary installment's studios (anime) / networks (TV)
  "themes": ["Survival", "Military"], // spoiler-screened; see Catalogue enrichment below
  "featuredVideo": FranchiseVideo | null,
  "videos": [ FranchiseVideo, … ],
  "audience": {
    "isAdult": false | null,
    "contentRating": { "country": "IN", "rating": "U/A 16+" } | null,
    "availableRatings": [{ "country": "US", "rating": "TV-MA" }, …]
  },
  "people": {
    "creators": [ CatalogPerson, … ],
    "directors": [ CatalogPerson, … ],
    "cast": [ CatalogPerson, … ]
  },
  "related": [ RelatedTitle, … ],
  "continueWatching": {
    "mediaId": 16498,
    "partLabel": "Season 1",
    "episode": EpisodeMeta
  } | null,
  "availability": WatchAvailability, // optional; present when country was requested/saved
  "metadata": {
    "completeness": {
      "artwork": true, "episodes": true, "people": true,
      "ratings": true, "related": true, "videos": true
    },
    "sources": [{
      "provider": "tmdb", "mediaType": "tv", "externalId": 82596,
      "matchMethod": "catalogue_owner", "confidence": 1,
      "checkedAt": "2026-09-03T…"
    }]
  }
}
```

### FranchiseSummary (lists: trending, search, library)
```jsonc
{
  "id": "uuid",
  "source": "anilist",             // anilist | tmdb (default anilist)
  "title": "Attack on Titan",
  "cover": "https://…",
  "banner": "https://…",
  "images": { "portrait": "https://…", "landscape": "https://…" },
  "artwork": ArtworkGallery,
  "isReleasing": true,
  "partCount": 10,
  "nextAiringAt": 1700000000000,   // soonest upcoming across parts, or null
  "upcoming": FranchiseUpcoming | null,  // confirmed/rumored "what's next" — see below
  "year": 2013,                    // premiere year (for "Anime · 2023" / "TV · 2024"), or null
  "themes": ["Survival", "Military"],
  "featuredVideo": FranchiseVideo | null,
  "availability": WatchAvailability, // optional; cached preview when country was requested/saved
  // present only in /me/library:
  "status": "watching",            // watching | completed | planned | paused | dropped
  "behind": 2,                      // unwatched aired eps across releasing parts
  "newParts": 1                     // parts added since user last opened (badge)
}
```

### Catalogue enrichment

The detail/library payload includes spoiler-safe themes, audience metadata, people, related titles,
videos and the next already-aired episode the authenticated user has not watched. Search/trending
stay compact but include the fields needed for rich cards: both image orientations, themes and the
single backend-selected `featuredVideo`. Detail/Search use stale-while-revalidate; a slow daily
pass repairs deep AniList metadata, while a separate TMDB pass refreshes anime trailers even when
AniList cannot be reached.

```jsonc
// CatalogPerson
{
  "source": "anilist" | "tmdb",
  "externalId": 123,
  "name": "Lily Collins",
  "role": "Emily Cooper" | "Creator" | "Director" | null,
  "image": "https://…" | null
}

// RelatedTitle
{
  "source": "anilist" | "tmdb",
  "externalId": 456,
  "franchiseId": "uuid" | null, // filled only when already materialized locally
  "title": "The Bold Type",
  "year": 2017 | null,
  "images": { "portrait": "https://…" | null, "landscape": "https://…" | null },
  "score": 100 | null              // source-native recommendation strength when available
}
```

`GET /me/discover` wraps a related title with an auditable reason instead of a black-box label:

```jsonc
{
  "title": RelatedTitle,
  "because": { "franchiseId": "uuid", "title": "Bleach" },
  "reason": "Because you completed Bleach",
  "score": 125
}
```

Dropped sources and already-subscribed targets are excluded. Results are capped at three per source
franchise so one completed title cannot consume the whole feed. If `title.franchiseId` is null,
send its `source` and `externalId` to `/franchises/resolve` only after the user selects it.

- AniList tags marked as general spoilers, media spoilers, or adult are excluded. TMDB has no
  spoiler bit, so only genres and a conservative allow-list of broad keywords become themes.
- `audience.contentRating` is the exact match for the optional `country` query on Detail. No market
  match is `null`; the backend does not substitute a US rating. TMDB provides regional ratings;
  AniList currently provides `isAdult` only.
- Anime cast entries are Japanese voice actors with the character name in `role`. General-TV cast
  entries are top-billed aggregate cast; creators and directors are separate.
- `continueWatching` prefers a part the user already started, then the first unfinished part. It
  never points to an unaired episode. Missing episode metadata produces an honest Episode-N shell
  with nullable context rather than suppressing the next episode.

### FranchiseUpcoming
"What's next" for a franchise (announced/airing seasons, films). A future part already present in
AniList/TMDB is returned immediately as a confirmed fallback; web research adds richer context,
the primary announcement URL, and credible rumors. Detail reads enqueue missing or stale research
without delaying the response, while the daily job proactively refreshes subscribed franchises.
`release` is prose because that is what gets announced — a window as often as a date.

Search is a first-class consumer of this field. A newly materialized TMDB title persists the
immediate catalogue fact in the same write as the franchise, while AniList future parts derive the
same field on read. An exact search hit whose TMDB fact or catalogue-video record is still missing
gets one bounded show-summary refresh before the response returns. The summary is rebuilt after
that write, so an available trailer appears in that same Search response. The same guarantee now
applies to an exact AniList result with no trailer: a bounded metadata-only TMDB match runs and the
summary is rebuilt before return. Richer web research is then queued from Search itself; opening
Detail is not required to start it.
```jsonc
{
  "status": "announced",       // airing | upcoming_dated | announced | announced_no_date | rumored | recently_aired | concluded
  "next": "Season 2",          // shortest stable name for the installment
  "release": "October 2026",   // human-readable date OR window ("2026-11-20", "Summer 2027", "TBA")
  "note": "Announced at AnimeJapan.",
  "source": "https://…",       // primary announcement or provider-catalogue URL, or null
  "checked": "2026-08-24T…",   // ISO date the info was last verified
  "evidence": [{
    "url": "https://…",
    "publisher": "Netflix Tudum" | null,
    "publishedAt": "2026-08-20" | null,
    "tier": "official",        // official | trade | reputable | catalogue | unknown
    "primary": true             // original announcement, not merely coverage
  }],
  "releaseWindow": {           // `release` resolved into something orderable — DERIVED on read
    "date": "2026-10",         // "YYYY-MM-DD" | "YYYY-MM" | "YYYY", at the precision actually known, or null
    "precision": "month",      // day | month | quarter | year | unknown
    "sortKey": 20261001        // yyyymmdd of the EARLIEST instant the window can mean, or null
  }
}
```

`status` is the classification, not a confidence guess: `rumored` is never presented as
`announced`. `evidence` makes the reason inspectable on the critical Search/Detail surface.
Catalogue-derived facts carry a `catalogue` evidence row immediately; agent research can add the
official primary announcement and independent trade/reputable reporting. The immutable history is
available at `GET /franchises/:id/announcements`.

**`release` is the only field a client prints; `sortKey` is the only field it sorts by.** Clients
must not parse `release` themselves — an ISO-only reading of a corpus full of `October 2026` and
`Summer 2027` silently files every one of them under January of its year, which is how a "returning
soonest first" list ended up putting October 2026 ahead of an August 2026 date.

- `precision: "quarter"` means a broadcast season or `Qn`, and `date` is that quarter's **first**
  month — safe to order by, never to print as a month (`Summer 2027` is not "July 2027").
- `precision: "year"` may print only the year: `Late 2026` keeps `date: "2026"` while `sortKey`
  places it in September, so it lands after spring and before the next January.
- `sortKey: null` (TBA, prose with no date, **and every rumor** — an unconfirmed report is not a
  schedule) sorts **last**. Never treat it as 0.

### WatchAvailability
Country-specific **streaming** availability for a franchise. The caller can supply an ISO 3166-1
alpha-2 region or save it once in `/me/preferences`; purchase and rental stores are intentionally excluded. Subscription
services come first, followed by free and ad-supported services.

For TMDB-owned TV franchises the lookup uses the stored TMDB show id. AniList does not expose a
regional catalogue or TMDB id, so anime is conservatively matched to a Japanese-animation TMDB
title by normalized title and premiere year. No safe match is represented by an empty list, never
by a guessed provider.

Consumers must branch on `status`, not on `providers.isEmpty`: `not_available` means a title was
matched but has no subscription/free/ad-supported option in that country; `unmatched` means the
AniList→TMDB bridge could not establish identity safely; and `disabled` means this deployment has
no TMDB token. An upstream failure is an HTTP error rather than any of those catalogue states.

This data comes from TMDB's JustWatch partnership. TMDB returns a regional watch-page link rather
than reliable provider deep links, so the client opens `link` for the actual options and must show
the supplied JustWatch attribution. Search, trending, Library and Detail embed `availability` when
a region resolves. List responses use persisted stale-while-revalidate snapshots; exact Search and
Detail do a current bounded lookup. Use the batch endpoint to warm a visible shelf in one request.
```jsonc
{
  "country": "IN",
  "status": "available",  // available | not_available | unmatched | disabled
  "providers": [
    {
      "id": 8,
      "name": "Netflix",
      "logo": "https://image.tmdb.org/t/p/w92/…" | null,
      "access": "subscription", // subscription | free | ads
      "preferred": true          // optional; saved services sort first
    }
  ],
  "link": "https://www.themoviedb.org/tv/30984-bleach/watch?locale=IN" | null,
  "attribution": "JustWatch",
  "checkedAt": "2026-09-03T12:00:00.000Z"
}
```

## Endpoints

| Method | Path | Body | Returns |
|--------|------|------|---------|
| GET | `/health` | — | `{ ok: true }` |
| GET | `/franchises/trending?limit=30&country=IN` | — | `FranchiseListResponse`; supports the same `source`, `year`, `status`, `theme`, `providerId` filters as Search |
| GET | `/search?q=&exact=1&source=anilist&year=2026&status=RELEASING&theme=Drama&providerId=8&country=IN` | — | `FranchiseListResponse` — empty `q` = trending. Indexed aliases include English, Romaji, native titles and synonyms. One- or two-character typeahead is local-only. A genuine miss gets one short AniList + TMDB fan-out and bounded materialization. Exact-title hits synchronously refresh immediate `upcoming`, trailer and regional facts, then queue richer research. `exact=1` disables spell correction. All filters are optional; `providerId` requires a query/saved country |
| POST | `/franchises/resolve` | `{ source: "anilist" \| "tmdb", externalId }` | Materializes a `RelatedTitle` selected by the user and returns its `FranchiseSummary`; `422` when identity/source policy rejects it |
| GET | `/franchises/:id?country=IN` | — | `Franchise`; `country` is optional/case-insensitive, falls back to saved preference, selects `audience.contentRating`, and attaches current `availability` |
| GET | `/franchises/:id/announcements?limit=20` | — | `{ observations: AnnouncementObservation[] }` newest-first, with immutable evidence snapshots |
| GET | `/franchises/:id/watch-providers?country=IN` | — | `WatchAvailability`; `country` is case-insensitive and may be omitted after saving a preference |
| POST | `/franchises/watch-providers/batch` | `{ franchiseIds: [uuid], country? }` | `{ country, availability: [{ franchiseId, ...WatchAvailability }] }`; max 100, four bounded workers |
| GET | `/me/preferences` | — | `{ country, language, providerIds, updatedAt }` |
| PUT | `/me/preferences` | `{ country?: "IN" \| null, language?, providerIds? }` | Saved preference object; omitted fields are preserved |
| GET | `/me/library?country=IN` | — | `{ franchises: LibraryFranchise[], prevOpenedAt: Int }`; country falls back to preferences and adds cached availability |
| GET | `/me/discover?limit=20` | — | `{ items: DiscoveryItem[] }`; source-native recommendations with score plus `because`, `reason`, and optional materialized `franchiseId` |
| POST | `/me/subscriptions` | `{ franchiseId, status? }` | `{ ok: true }` (status defaults: `watching` if releasing else `planned`) |
| PATCH | `/me/subscriptions/:franchiseId` | `{ status }` | `{ ok: true }` |
| DELETE | `/me/subscriptions/:franchiseId` | — | `{ ok: true }` |
| PUT | `/me/progress` | `{ mediaId, episodes }` | `{ ok: true }` |
| PUT | `/me/franchises/:franchiseId/progress` | `{ mode: "caught_up" \| "completed" \| "reset", status? }` **or** `{ parts: [{ mediaId, episodes }], status? }` | Atomic canonical `{ ok, franchiseId, status, progress[] }`; rejects foreign/duplicate media IDs before writing; `completed` also upserts completed subscription status |
| POST | `/me/opened` | — | `{ prevOpenedAt: Int }` (returns the value *before* this call, then stamps now) |
| GET | `/me/notifications?limit=50` | — | `{ items: NotificationItem[], unread: Int }` newest-first |
| POST | `/me/notifications/read` | `{ ids?: [uuid] }` | `{ marked: Int }` — omit `ids` to mark all unread as read |
| DELETE | `/me` | — (an unknown field is a `400`) | `{ deleted: true }` — see **Account deletion** |

### Account deletion

`DELETE /me` erases the account. It is required by App Store guideline 5.1.1(v) and it is the one
route in this API that cannot be undone, so its semantics are exact:

- **Erased, not deactivated.** In one transaction: the caller's `notifications`, `subscriptions`,
  `progress`, and `user_preferences` rows, then the `users` row itself. Every user-owned table is deleted explicitly
  rather than left to the `ON DELETE CASCADE` each foreign key declares — the cascade is real and
  `me.account.test.ts` asserts it, but a database restored from a dump, or a table added later
  without one, must not be able to turn "delete my account" into "orphan my rows".
- **Scoped to the bearer.** The user id comes from the token; there is no path or body parameter
  that could name a different account. A body is accepted only if it is empty — an unrecognised
  field is a `400`, never an ignored one.
- **Nothing else is touched.** The catalogue (`media`, `franchise`, `announcements`) is shared and
  survives; only the rows that belong to this user are removed.
- The client signs out immediately afterwards; the next sign-in with the same Clerk identity
  creates a brand-new, empty account.


### FranchiseListResponse
The envelope every franchise-list route returns. `franchises` is the only guaranteed field; the
other three are **optional — present only on `/search`**, the one route that may fall back across
catalogues. `/franchises/trending` returns `{ franchises }` alone. They exist so the client can be
honest rather than silently plausible:
```jsonc
{
  "franchises": [ FranchiseSummary, … ],
  "correctedQuery": "Mushoku Tensei",  // optional — /search only; present only when the query was
                                       // spell-corrected AND the rewrite actually found something
  "originalQuery": "Mushuko Tensei",   // optional — /search only; echoed alongside correctedQuery
  "sources": {                          // optional — /search only. Per-catalogue outcome: a
    "anilist": "ok",                    // catalogue that FAILED is not a catalogue with no
    "tmdb": "disabled"                  // matches. ok | failed | disabled; "disabled" =
  }                                     // TMDB_ACCESS_TOKEN unset (anime-only mode)
}
```
A client must treat an absent `sources` as "nothing to report", never as a failure.

### NotificationItem

```
{
  id: uuid,
  franchiseId: uuid,
  kind: "news_rumored" | "news_announced" | "news_dated",
  title: String,       // franchise title, e.g. "Jujutsu Kaisen"
  body: String,        // e.g. "Season 4 announced — release TBA"
  createdAt: Int,      // ms epoch
  readAt: Int | null   // ms epoch, null while unread
}
```

Notifications are produced by a daily backend job (Claude Agent SDK web research over each
subscribed franchise). A notification is created only when news is genuinely new: first
sighting of an upcoming installment (including credible rumors), a status upgrade
(rumored → announced → dated), or a TBA release gaining a concrete date. The same job keeps
`franchise.upcoming` fresh, so the existing upcoming badges/callouts update automatically.

## Client-side derivation (ported from the legacy React app's `format.ts`/`App.tsx`)

`/me/library` returns every subscribed franchise with **all** its parts (airing + progress).
The client computes views exactly like the old app, but per **releasing part**:

- **episodesBehind(part)** = `isReleasing ? max(0, airedEpisodes - progress) : 0`.
- **availableEpisodes(part)** = `0` when `status == "NOT_YET_RELEASED"`, else `airedEpisodes || totalEpisodes`.
  Announced parts must never contribute to a "keep watching" backlog.
- **premiereAt(part)** = `nextAiringAt` while `status == "NOT_YET_RELEASED"` — both sources put a
  dated announced part's premiere in that slot. `null` there means the date is genuinely unknown
  (release TBA), never just "the source didn't say".
- **`nextAiringAt` in the past is stale, not a schedule.** Sources don't advance the slot the
  instant an episode airs, so clients treat a `nextAiringAt` whose *local day* is already behind
  today as absent (same-day is kept) rather than rendering it as an upcoming airing.
- **Today / "Out now"** = releasing parts whose `lastAiredAt > prevOpenedAt`.
- **Airing soon** = releasing parts with `nextAiringAt` within 48h.
- **Schedule** = releasing parts bucketed into the IST Mon–Sun week by `nextAiringAt`.
- **Library buckets** = Behind / Caught up (releasing, behind 0) / Finished / Plan, computed
  from the franchise's releasing part + subscription status.
- Render franchise chronology by `watchOrder`; use `relationship`/`optional` for honest side-story
  labels. Never reconstruct one order by separately sorting season/movie arrays.
- **Mark caught up** = `PUT /me/franchises/:id/progress {"mode":"caught_up"}`. This updates every
  member atomically and leaves a `NOT_YET_RELEASED` part at zero. The legacy per-part endpoint
  remains valid for a single +/- control.

All time math is **IST (Asia/Kolkata)** — port `istParts`, `istDayKey`, `istMondayCol`,
`fmtCountdown`, `fmtAgo`, `fmtDay`, `fmtTime`, `greetingFor` to Swift.

## Auth

iOS uses the Clerk iOS SDK; attaches the session JWT as `Authorization: Bearer …`.
Backend verifies via `@clerk/backend` `verifyToken` (JWKS / networkless `CLERK_JWT_KEY`),
maps `sub` (Clerk user id) → `users` row (upsert on first request), exposes `req.user`.

### Two issuers, and only one of them is a JWT

`dev:<clerkId>` is a **distinct, non-production issuer**, not a relaxed mode of the real one. It is
not a JWT and never will be, so:

- The server accepts it only when `APP_ENV` is not `production` **and** `DEV_AUTH_BYPASS` is set.
- **A production process rejects `dev:` tokens with `401 {"error":"invalid token"}` regardless of
  `DEV_AUTH_BYPASS`**, and never forwards a dev id to Clerk.
- A production process **refuses to start** if it sets `DEV_AUTH_BYPASS`, or if it has neither
  `CLERK_JWT_KEY` nor `CLERK_SECRET_KEY` (nothing could verify a real token). Fail closed, loudly,
  at deploy time.

The policy lives in `src/auth/authConfig.ts` (`devBypassAllowed`, `assertAuthConfig`) and
`src/auth/identity.ts` (`resolveIdentity`); `DEV_AUTH_BYPASS` is read nowhere else.

Deploy test — `npm run auth:smoke -- https://<host>` asserts `GET /health` → 200 and
`GET /me/library` with a `dev:` bearer → **401**, exiting non-zero otherwise.

### Client failure semantics

`401` means the session is gone (the client refreshes its token once, retries, and only then signs
out). `403` — including a Cloudflare/WAF HTML challenge — is an **infrastructure** failure: the
session is kept and the surface shows a stale/error frame. Any response whose body is HTML is
treated the same way at any status, including 2xx (captive portals).

Two things that look like `401` but are not. A client that cannot **mint** a token (an expired
session JWT with no network to renew it) never reaches the server and reports a *transport*
failure — being offline must not sign anyone out. A forced refresh that could not reach the token
issuer is likewise transport, not a dead session. Only an issuer that answers — with the same token,
or with none — turns a `401` into a sign-out.

Every request is bounded by one wall-clock budget (~16.6 s: a 15 s attempt plus at most ~1.6 s of
backoff), shared across retries, so a black-holed upstream can never hold a skeleton on screen.
`429` and `5xx` are retried twice while that budget lasts (`Retry-After` honoured, capped at 8 s);
an exhausted `5xx` whose body is HTML lands as infrastructure.
