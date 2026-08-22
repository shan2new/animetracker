# AniTrack API contract (v1)

The Node backend (`server/`) and the iOS app (`ios/`) both build against this. Base URL is
configurable; default dev `http://localhost:8787`. All times are **ms since epoch** (Int64).
All endpoints except `GET /health` require `Authorization: Bearer <Clerk session JWT>`.

## Sources

Franchises come from one of two catalogues, tagged by `source` on `Franchise`/`FranchiseSummary`
(a franchise never mixes sources; the field defaults to `"anilist"` when absent, so old clients
keep decoding):

- `"anilist"` — anime. Parts are AniList Media entries; grouping via the relation graph (+LLM).
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

### EpisodeMeta
Per-episode metadata. Richness is **source-dependent**: TMDB gives title/overview/still/runtime/date
from the season endpoint; AniList gives best-effort titles/thumbnails from `streamingEpisodes`
(numbered by position, often sparse) and **no** per-episode `airDate`/`overview`. Any field may be null.
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
  "label": "Season 1",       // human label the LLM/grouping assigned
  "title": "Attack on Titan",
  "cover": "https://…",
  "banner": "https://…",
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
  "episodes": [ EpisodeMeta, … ] // FULL list on GET /franchises/:id ONLY; [] on list/library payloads
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
  "synopsis": "…",
  "genres": ["Action","Drama"],
  "isReleasing": true,             // any part currently releasing
  "partCounts": { "season": 4, "movie": 2, "ova": 3, "special": 1 },
  "parts": [ FranchisePart, … ],   // ordered by kind then sequence; each part carries its `episodes`
  "subscription": { "status": "watching", "addedAt": 1700000000000 } | null,  // addedAt = ms epoch the user subscribed
  "year": 2013,                    // premiere year (earliest dated part), or null
  "studios": ["Wit Studio"]        // primary installment's studios (anime) / networks (TV)
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
  "isReleasing": true,
  "partCount": 10,
  "nextAiringAt": 1700000000000,   // soonest upcoming across parts, or null
  "year": 2013,                    // premiere year (for "Anime · 2023" / "TV · 2024"), or null
  // present only in /me/library:
  "status": "watching",            // watching | completed | planned | paused | dropped
  "behind": 2,                      // unwatched aired eps across releasing parts
  "newParts": 1                     // parts added since user last opened (badge)
}
```

## Endpoints

| Method | Path | Body | Returns |
|--------|------|------|---------|
| GET | `/health` | — | `{ ok: true }` |
| GET | `/franchises/trending?limit=30` | — | `FranchiseListResponse` |
| GET | `/search?q=&exact=1` | — | `FranchiseListResponse` — empty `q` = trending; fans out to AniList + TMDB `/search/tv` in parallel, lazily groups/materializes ungrouped matches, suppresses TMDB results that are Japanese animation (AniList owns those), and interleaves the two relevance-ordered lists. `exact=1` opts out of the spell-correction below |
| GET | `/franchises/:id` | — | `Franchise` |
| GET | `/me/library` | — | `{ franchises: LibraryFranchise[], prevOpenedAt: Int }` where `LibraryFranchise` = full `Franchise` + `status` + `behind` + `newParts` |
| POST | `/me/subscriptions` | `{ franchiseId, status? }` | `{ ok: true }` (status defaults: `watching` if releasing else `planned`) |
| PATCH | `/me/subscriptions/:franchiseId` | `{ status }` | `{ ok: true }` |
| DELETE | `/me/subscriptions/:franchiseId` | — | `{ ok: true }` |
| PUT | `/me/progress` | `{ mediaId, episodes }` | `{ ok: true }` |
| POST | `/me/opened` | — | `{ prevOpenedAt: Int }` (returns the value *before* this call, then stamps now) |
| GET | `/me/notifications?limit=50` | — | `{ items: NotificationItem[], unread: Int }` newest-first |
| POST | `/me/notifications/read` | `{ ids?: [uuid] }` | `{ marked: Int }` — omit `ids` to mark all unread as read |

### FranchiseListResponse
The envelope every franchise-list route returns. Two fields exist so the client can be honest
rather than silently plausible:
```jsonc
{
  "franchises": [ FranchiseSummary, … ],
  "correctedQuery": "Mushoku Tensei",  // present only when the query was spell-corrected AND the
                                       // rewrite actually found something
  "originalQuery": "Mushuko Tensei",   // echoed alongside correctedQuery
  "sources": {                          // per-catalogue outcome: a catalogue that FAILED is not a
    "anilist": "ok",                    // catalogue with no matches. ok | failed | disabled
    "tmdb": "disabled"                  // "disabled" = TMDB_ACCESS_TOKEN unset (anime-only mode)
  }
}
```

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
- **Mark caught up** = `PUT /me/progress {mediaId, episodes: airedEpisodes}` for the releasing part.

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
