# Domain models and derived presentation logic

This is the data spine of the app: the wire types decoded from the AniTrack REST API
(`docs/api-contract.md`) and — far more importantly — the ~50 **derived** properties computed on top
of them. The house rule that governs this whole subsystem is stated in `CLAUDE.md`: *"Presentation is
**derived, not stored**"*. The server sends raw catalogue facts (counts, timestamps, statuses); the
model layer turns them into every display string, sort key, threshold and boolean the screens read.
No screen may re-derive any of this, and no screen may store it. A second rule runs through
everything below: **freshness is derived from `airings`, never from the catalogue's counts** — the
server's `airedEpisodes` / `lastAiredAt` / `nextAiringAt` are advanced by an hourly cron and trail
reality by up to an hour, while the per-episode `airings` list in the same payload is precise. A
third rule is the **two-calendar system**: AniList timestamps are real instants read in the device's
zone, TMDB timestamps are date-only facts synthesised at 17:00 UTC whose only true part is their UTC
calendar day. Every one of the three has a documented production bug behind it, quoted in place
below. Source files: `ios/Sources/Models/Models.swift`, `Models+Shared.swift`,
`Models+Enrichment.swift`, `ios/Shared/AiringActivityAttributes.swift`, with the required time
substrate in `ios/Sources/Util/Formatting.swift`.

---

## 0. Ground rules

| Rule | Detail |
|---|---|
| Time unit | **Milliseconds since Unix epoch, `Int64`.** Never `Date`/`Instant` on the wire. Conversion happens at the networking layer only. Kotlin: `Long`. |
| Value semantics | Every type is a Swift `struct` (value type). Mutation is by whole-object copy. Kotlin: `data class` + `copy()`. This is what makes `snapshotForUndo` free. |
| Concurrency | Every type is `Sendable` (immutable, `let`-only). Kotlin: immutable `data class`, safe to hand across dispatchers. |
| Decoding | **Lenient by field.** Almost every field is decoded through `try?` and falls back to a default. See §2 for the exact contract and the places it is deliberately strict. |
| Identity | `Franchise.id: String` (uuid), `FranchisePart.id == mediaId: Int`, `Episode.id == number: Int`. |
| "now" | Callers pass `now: Int64` explicitly so a screen can pin a clock. `Int64.nowMs` = `Int64((Date().timeIntervalSince1970 * 1000).rounded())`. Only `FranchisePart.isComplete` reads the wall clock itself. |

### 0.1 The time anchor — required substrate

Not in the assigned files, but **no derivation below is portable without it**
(`Formatting.swift`). Port it first.

```
enum TimeAnchor { local, utcDate }
  isDateOnly  = (self == .utcDate)
  timeZone    = local ? TimeZone.current : UTC
```

| Constant | Value |
|---|---|
| `Formatting.D` (one day) | `86_400_000` |
| `Formatting.H` (one hour) | `3_600_000` |
| `Formatting.minuteMs` | `60_000` |

```swift
static func localDayKey(_ ts: Int64, anchor: TimeAnchor) -> Int64
// = midnight-UTC ms of the (y, mo, d) triple obtained by reading `ts` in `anchor`'s calendar.
// Normalised into ONE shared space so a UTC-anchored day key subtracts cleanly from a
// local-anchored one.

static func dayDiff(ts: Int64, now: Int64, anchor: TimeAnchor) -> Int {
    let a = localDayKey(ts, anchor: anchor)
    let b = localDayKey(now, anchor: .local)      // `now` is ALWAYS local — it IS a real instant
    return Int((Double(a - b) / Double(D)).rounded())
}
```

`dayDiff` returns `0` = same day, `+1` = tomorrow, `−1` = yesterday. The `Double` division + `.rounded()`
is load-bearing: integer division would be wrong across a DST seam. **Reproduce it exactly**, including
the asymmetry that `ts` uses `anchor` but `now` is always `.local`.

The comment at the head of `Formatting.swift` states the two consequences the anchor enforces:

> (a) day labels, day diffs and day bucketing use the timestamp's OWN calendar day;
> (b) a `.utcDate` timestamp NEVER yields a clock time or an hour-precision countdown.

**Android:** `java.time`. `localDayKey` = `Instant.ofEpochMilli(ts).atZone(zone).toLocalDate().atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli()`.
Cache the two `ZoneId`s and re-key the cache when `TimeZone.getDefault()` or `Locale.getDefault()`
changes (iOS re-keys on a `"<tzIdentifier>|<localeIdentifier>"` stamp; Android should use the same
composite-stamp trick — a cached formatter otherwise keeps printing `9:00 PM` after the user flips
the 24-hour switch).

---

## 1. Enumerations

### 1.1 `WatchStatus` — `String`-backed, `CaseIterable`

| Case | Wire value | User-facing word (`Copy.statusLabel`) |
|---|---|---|
| `watching` | `"watching"` | `Watching` |
| `completed` | `"completed"` | **`Watched`** |
| `planned` | `"planned"` | `Planned` |
| `paused` | `"paused"` | `Paused` |
| `dropped` | `"dropped"` | `Dropped` |

Fallback for an unrecognised raw value: `raw.prefix(1).uppercased() + raw.dropFirst()`.
Menu order is **not** the enum order — it is the fixed list
`["Watching", "Planned", "Watched", "Paused", "Dropped"]` (`Copy.statusesInOrder`).

`WatchStatus.displayName` (`Models+Shared.swift`) is the *only* place a status becomes text; it
delegates to `Copy.Status(_:)`. Source comment:

> **"Finished" is not in this vocabulary.** It was carrying both meanings at once, which is how the
> app came to file a show as finished on one screen and promise it returns in six weeks on the next
> […] "Complete" is now reserved for the *series*, "Watched" for the *user*.

Never emit `"Completed"` or `"Plan to watch"`.

### 1.2 `MediaSource` — `String`-backed

| Case | Wire | `timeAnchor` | `kindWord` |
|---|---|---|---|
| `anilist` | `"anilist"` | `.local` | `"Anime"` |
| `tmdb` | `"tmdb"` | `.utcDate` | `"TV"` |

Decoding default (and unknown-value fallback) is **`.anilist`**.

`timeAnchor` doc comment — the rule that must never be violated:

> TMDB air dates are DATE-ONLY facts the server carries as a synthesized 17:00 UTC instant, so only
> their UTC calendar day is real; reading them locally put every timezone east of UTC+7 a day ahead.
> AniList ships true instants. **Never branch on `source` at a formatting call site — pass this.**

`kindWord` lives on `MediaSource` (not on `Franchise`) specifically so `FranchiseSummary` (Search)
and `Franchise` (Library/Detail) cannot spell it differently. The app never says "AniList" or "TMDB"
to a viewer.

### 1.3 `PartKind` — `String`-backed

| Case | `sectionTitle` | `sortRank` |
|---|---|---|
| `season` | `"Seasons"` | 0 |
| `movie` | `"Movies"` | 1 |
| `ova` | `"OVAs"` | 2 |
| `ona` | `"OVAs"` | 3 |
| `special` | `"Specials"` | 4 |
| `music` | `"Music"` | 5 |

Decoding default / unknown fallback: **`.season`**.

> ⚠️ **Latent defect to carry or fix knowingly:** `ova` and `ona` share a `sectionTitle` but have
> *different* `sortRank`s, so `Franchise.sections` on a franchise carrying both renders **two
> sections both titled "OVAs"**. (Detail no longer draws the seasons section list, so this is
> currently unreachable; the two enum cases are still distinct everywhere else.)

### 1.4 Small closed enums

| Type | Cases (wire value where it differs) | Decode default |
|---|---|---|
| `ReleasePrecision.Precision` | `exact`, `dateOnly` = `"date_only"`, `unknown` | `.unknown` |
| `ReleaseWindow.Precision` | `day`, `month`, `quarter`, `year`, `unknown` | `.unknown` |
| `FranchiseVideo.Kind` | `trailer`, `teaser`, `announcement`, `featurette`, `clip`, `other` | `.other` |
| `WatchAvailability.Status` | `available`, `notAvailable` = `"not_available"`, `unmatched`, `disabled` | `.unmatched` |
| `WatchProvider.Access` | `subscription`, `free`, `ads` | `.subscription` |

`FranchiseVideo.Scope` is **not** `String`-backed — it is a sum type, `Equatable`, hand-coded on both
sides of Codable:

```
Scope = .franchise | .part(mediaId: Int, label: String)
```

---

## 2. The decoding contract

Every custom `init(from:)` in this subsystem follows one shape:

```swift
field = (try? c.decode(T.self,          forKey: .field)) ?? <default>   // non-optional field
field =  try? c.decodeIfPresent(T.self, forKey: .field)                 // optional field
```

`Models+Enrichment.swift` states the reason at the top of the file:

> Every field here decodes LENIENTLY. A server older than the field, or a row the server's
> stale-while-revalidate pass has not reached yet, must read as EMPTY — never as a decode failure
> that drops the whole franchise. The screens hide a section that is empty and draw it when it
> arrives; **nothing here may throw past the franchise.**

### 2.1 Where it is deliberately STRICT (these throw)

| Field | Consequence of a throw | Why |
|---|---|---|
| `Franchise.id` | The whole franchise fails → with `LibraryResponse` using synthesised Codable, **the whole library read fails** | An unidentifiable show is not a show |
| `FranchiseSummary.id` | Same, one row poisons the whole list | ″ |
| `FranchisePart.mediaId` | The `[FranchisePart]` decode throws → caught by the outer `try?` → **`parts = []`** | ″ |
| `FranchiseListResponse.franchises` | The whole response fails | Source comment: *"a body without it is a broken response, not an empty result, and swallowing that would render 'no results' for a server fault"* |
| `FranchiseVideo.id` | The `[FranchiseVideo]` decode throws → **all videos become `[]`** | id is also the `Identifiable` id and the YouTube id |
| `WatchProvider.id` | All providers become `[]` | ″ |
| `ContinueWatching.mediaId`, `.episode` | `continueWatching` becomes `nil` | A pointer with no target is useless |
| `Airing.episode`, `.at` (synthesised Codable) | All airings become `[]` | ″ |
| `Subscription.status` (synthesised) | `subscription` becomes `nil` | ″ |
| `ContentRating.country`, `.rating` (synthesised) | that rating becomes `nil` / drops the whole `availableRatings` array | ″ |
| `LibraryResponse`, `OpenedResponse`, `OKResponse` (synthesised) | whole response fails | Envelope shapes are contractual |

**Android:** kotlinx.serialization's default is the opposite (throw on type mismatch, allow defaults
for missing keys). To reproduce: enable `ignoreUnknownKeys = true`, `coerceInputValues = true`,
`explicitNulls = false`, and wrap the *type-mismatch* leniency in a reusable delegating serializer
(`SafeSerializer<T>(default)`) applied per field, plus a `SafeListSerializer` that drops
individually-malformed elements only where iOS drops the whole array (see the table above — iOS
drops the **whole array**, so a faithful port must too, not element-wise).

### 2.2 Post-decode filters (must be reproduced)

| Type | Filter |
|---|---|
| `FranchisePart.episodes` | `.filter { $0.number > 0 }` — *"`Episode.id` is its number, so a malformed/duplicate 0 would collide inside a ForEach"* |
| `FranchisePart.airings` | `.filter { $0.episode > 0 && $0.at > 0 }` |
| `Franchise.related` | `.filter { !$0.title.isEmpty }` |
| `FranchisePeople.creators/directors/cast` | each `.filter { !$0.name.isEmpty }` |
| `ArtworkSet.portrait/landscape` | through `ArtworkSet.nonEmpty` (below) — applied in **both** the decoding and the memberwise init |
| `FranchiseVideo.site` | `.lowercased()` in both inits |
| `FranchiseVideo.title/url/thumbnail`, `CatalogPerson.role/image`, `RelatedTitle.franchiseId`, `WatchAvailability.link`, `WatchProvider.logo` | through `ArtworkSet.nonEmpty` |

```swift
static func nonEmpty(_ s: String?) -> String? {
    guard let s, !s.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
    return s     // NOTE: returns the ORIGINAL, untrimmed string
}
```
Trims `.whitespaces` only — **not** newlines. Returns the untrimmed original when non-empty.

---

## 3. Wire types, field by field

### 3.1 `Episode` — `Codable, Identifiable, Sendable`

JSON key == property name for every field. `id == number`.

| Field | Type | Default on miss/malformed |
|---|---|---|
| `number` | `Int` | `0` (then filtered out by the parent) |
| `title` | `String?` | `nil` |
| `airDate` | `Int64?` ms epoch | `nil` |
| `overview` | `String?` | `nil` |
| `still` | `String?` (thumbnail url) | `nil` |
| `runtime` | `Int?` (minutes) | `nil` |

Because every field uses `try?`, **`Episode` can never throw** — decoding a `{}` yields
`Episode(number: 0, …)`.

Contract note (verbatim from `api-contract.md`): richness is source-dependent — TMDB gives
title/overview/still/runtime/date; AniList gives best-effort titles/thumbnails from
`streamingEpisodes` and **no** per-episode `airDate`/`overview`.

**Derived:**

```swift
static let airDateAnchor: Formatting.TimeAnchor = .utcDate
```
> `airDate` only ever comes from TMDB — AniList exposes none — so it is always a date-only fact and
> must be read in its own UTC day, never the device's.

| Property | Formula | Output |
|---|---|---|
| `airDateLabel` | `airDate.map { fmtFullDate($0, anchor: .utcDate) }` | `"Jun 24, 2026"` (locale-ordered), `nil` when undated |
| `airDayLabel(now:)` | `airDate.map { fmtDayLong(ts: $0, now: now, anchor: .utcDate) }` | `"Today"` / `"Thursday"` / `"May 4"` |

*Use these, never `Formatting.fmtFullDate(episode.airDate)` — the bare call reads a day late east of
UTC+7.* Both currently have **zero consumers outside the model layer** (see §8).

### 3.2 `Airing` — `Codable, Hashable, Sendable` (synthesised Codable)

| Field | Type |
|---|---|
| `episode` | `Int` |
| `at` | `Int64` ms epoch |

One dated episode of a part inside Schedule's window. Contract: the server ships the window **8 days
back … 15 days ahead** on **every** payload (list, library and detail), merged from the dated episode
list + the next slot + `lastAiredAt`, de-duplicated by episode number with the episode list winning.
`[]` means nothing in the window is dated *or* the server predates the field.

### 3.3 `ReleasePrecision`

| Field | Type | Default | Authoritative when |
|---|---|---|---|
| `precision` | `Precision` | `.unknown` | always |
| `at` | `Int64?` ms | `nil` | `precision == .exact` |
| `date` | `String?` `"YYYY-MM-DD"` UTC | `nil` | `precision == .dateOnly` |

> How precisely the next release instant is known — **stated by the server, never inferred from
> `source`**. AniList publishes a real broadcast instant; TMDB publishes a calendar date the sync
> synthesizes to 17:00 UTC, so its clock half is not a fact and must never be rendered.

⚠️ **`FranchisePart.release` has zero consumers in the app today** (§8). The `.utcDate`/`.local`
decision is taken from `MediaSource.timeAnchor` instead. Port the type for wire fidelity; do not
build UI on it without deciding which of the two mechanisms wins.

### 3.4 `FranchisePart` — `Codable, Identifiable, Sendable`. `id == mediaId`

| Field | Type | Default | Notes |
|---|---|---|---|
| `mediaId` | `Int` | **throws** | TMDB ids are `1_000_000_000 + tmdb season id` |
| `kind` | `PartKind` | `.season` | |
| `sequence` | `Int` | `0` | **ordering key; NEVER displayed** (see box below) |
| `label` | `String` | `""` | the source's own words: `"Season 4"`, `"Final Season"`, `"Part 2"` |
| `title` | `String` | `"Untitled"` | |
| `cover` | `String?` | `nil` | legacy; read `portraitArt` instead |
| `banner` | `String?` | `nil` | legacy; read `landscapeArt` instead |
| `format` | `String?` | `nil` | raw AniList format, e.g. `"TV"` |
| `status` | `String?` | `nil` | raw catalogue status, e.g. `"FINISHED"`, `"NOT_YET_RELEASED"` |
| `isReleasing` | `Bool` | `false` | |
| `totalEpisodes` | `Int` | `0` | `0` = unknown (common for ongoing AniList shows) |
| `airedEpisodes` | `Int` | `0` | catalogue fact, hourly cron; always `0` while `NOT_YET_RELEASED` |
| `nextEpisodeNumber` | `Int?` | `nil` | `1` on a dated `NOT_YET_RELEASED` part |
| `nextAiringAt` | `Int64?` | `nil` | contract: always `== release.at` |
| `lastAiredAt` | `Int64?` | `nil` | |
| `synopsis` | `String?` | `nil` | HTML; strip with `Formatting.stripHtml` |
| `genres` | `[String]` | `[]` | |
| `progress` | `Int` | `0` | the user's watched count **for this part** |
| `year` | `Int?` | `nil` | premiere/season year |
| `studios` | `[String]` | `[]` | studios (anime) / networks (TV) |
| `nextAiringCount` | `Int` | `0` | `> 1` ⇒ a full-season drop. **Zero consumers** (§8) |
| `episodes` | `[Episode]` | `[]` | **detail response only**; filtered `number > 0` |
| `release` | `ReleasePrecision?` | `nil` | |
| `airings` | `[Airing]` | `[]` | on **every** payload; filtered `episode > 0 && at > 0` |
| `images` | `ArtworkSet?` | `nil` | |
| `videos` | `[FranchiseVideo]` | `[]` | scoped to this exact part |

> **House rule (`Models+Shared.swift` header):** *"`sequence` is the ordering key and **never
> displays**. It counts a franchise's members, which is not the number the world uses for a season —
> rendering 'S5' beside a label that reads 'Season 4' is spec board 13's P0 #3, observed live on
> 2026-08-22."*

### 3.5 `PartCounts` — synthesised `Codable`

`season, movie, ova, ona, special, music` — all `var Int = 0`.

> 🚩 **CONFIRMED CONTRACT DRIFT.** Swift's synthesised `init(from:)` does **not** use property
> default values for missing keys; it calls `decode` and throws. The server emits a *partial* record
> (`franchiseView.ts:331` — `const partCounts: Partial<Record<PartKind, number>> = {}`, populated
> only for kinds that exist), so any franchise lacking one of the six kinds makes `PartCounts` throw,
> which `try? c.decodeIfPresent(...)` swallows to `nil`. **`Franchise.partCounts` is therefore `nil`
> in practice for essentially every row.** It has zero consumers, so nothing breaks today. On
> Android, model it as a `Map<PartKind, Int>` with `getOrDefault(0)`, which is what the wire actually
> carries.

### 3.6 `Subscription` — synthesised `Codable`

| Field | Type | Notes |
|---|---|---|
| `status` | `WatchStatus` | required |
| `addedAt` | `Int64?` | ms epoch. *"Absent in older server responses, so Library's 'recently added' ordering must treat `nil` as **unknown** rather than as the epoch."* |

### 3.7 `ReleaseWindow`

| Field | Type | Default |
|---|---|---|
| `date` | `String?` — `"YYYY-MM-DD"` \| `"YYYY-MM"` \| `"YYYY"` | `nil` |
| `precision` | `Precision` | `.unknown` |
| `sortKey` | `Int?` — `yyyymmdd` of the **earliest** instant the window can mean | `nil` |

The type's whole reason for existing, verbatim:

> `FranchiseUpcoming.release` resolved into something orderable — **stated by the server**, because
> `release` is prose: the catalogue announces "October 2026" and "Summer 2027" far more often than it
> announces a date. The app's own ISO-only reading of that prose filed every window under January of
> its year, so a shelf sorted "soonest first" put October 2026 ahead of an August 2026 premiere while
> its own caption read "Returns Oct 2026". **Nothing here re-parses `release`**; `sortKey` is the one
> order and `date` is the one date.

Semantics per precision (contract + doc comments):
- `day` / `month` — `date` is exactly what was announced; safe to print.
- `quarter` — a broadcast season or `Qn`. `date` is that quarter's **first month**: order by it,
  **never print it as a month** ("Summer 2027" is not "July 2027").
- `year` — only the year may be printed. `sortKey` may still place it inside that year ("Late 2026"
  sorts in September); that placement is an order, not a fact to render.
- `unknown` — TBA, prose with no date, **and every rumor**. `sortKey: nil` sorts **last**, never as 0.

**Derived — `parts`:**
```swift
var parts: (year: Int, month: Int, day: Int)? {
    guard let date else { return nil }
    let segs = date.split(separator: "-").compactMap { Int($0) }
    guard let y = segs.first else { return nil }
    return (y, segs.count > 1 ? segs[1] : 1, segs.count > 2 ? segs[2] : 1)
}
```
Month and day default to **1** when the window doesn't state them — *"a caller must check `precision`
before printing either."* Note `compactMap { Int($0) }` silently drops non-numeric segments, so
`"2026-XX-05"` yields `(2026, 5, 1)`; reproduce the same (mis)behaviour or explicitly fix it.

### 3.8 `FranchiseUpcoming`

Web-sourced/curated "what's next" news.

| Field | Type | Default |
|---|---|---|
| `status` | `String?` | `nil` |
| `next` | `String?` — shortest stable name, `"Season 2"` | `nil` |
| `release` | `String?` — prose: `"October 2026"`, `"2026-11-20"`, `"Summer 2027"`, `"TBA"` | `nil` |
| `note` | `String?` | `nil` |
| `source` | `String?` — announcement URL | `nil` |
| `checked` | `String?` — ISO date last verified | `nil` |
| `releaseWindow` | `ReleaseWindow?` | `nil` |

`status` values in the wild: `airing`, `upcoming_dated`, `announced`, `announced_no_date`, `rumored`,
`recently_aired`, `concluded`. Kept as a raw `String?` (not an enum) — **keep it a string on Android
too**, so an unseen status degrades to the `default` branches below rather than to a decode failure.

### 3.9 `Franchise` — `Codable, Identifiable, Sendable`

| Field | Type | Default | Present on |
|---|---|---|---|
| `id` | `String` | **throws** | all |
| `source` | `MediaSource` | `.anilist` | all |
| `title` | `String` | `"Untitled"` | all |
| `cover` | `String?` | `nil` | all (legacy) |
| `banner` | `String?` | `nil` | all (legacy) |
| `synopsis` | `String?` | `nil` | all |
| `genres` | `[String]` | `[]` | all |
| `isReleasing` | `Bool` | `false` | all — *any* part releasing |
| `partCounts` | `PartCounts?` | `nil` | see §3.5 |
| `parts` | `[FranchisePart]` | `[]` | all |
| `subscription` | `Subscription?` | `nil` | all |
| `upcoming` | `FranchiseUpcoming?` | `nil` | all |
| `year` | `Int?` | `nil` | premiere year (earliest dated part) |
| `studios` | `[String]` | `[]` | primary installment's |
| `images` | `ArtworkSet?` | `nil` | enrichment |
| `themes` | `[String]` | `[]` | enrichment, spoiler-screened |
| `featuredVideo` | `FranchiseVideo?` | `nil` | enrichment, server's pick |
| `videos` | `[FranchiseVideo]` | `[]` | enrichment |
| `audience` | `AudienceInfo?` | `nil` | enrichment |
| `people` | `FranchisePeople?` | `nil` | enrichment |
| `related` | `[RelatedTitle]` | `[]` | enrichment, filtered non-empty title |
| `continueWatching` | `ContinueWatching?` | `nil` | enrichment, user-specific |
| `status` | `WatchStatus?` | `nil` | **`/me/library` only** |
| `behind` | `Int?` | `nil` | **`/me/library` only** — server's count |
| `newParts` | `Int?` | `nil` | **`/me/library` only** — badge |

**Two initialisers matter for the port:**

1. `init(copying other: Franchise, parts:, subscription: WatchStatus?? = nil, status: ...)` — the
   optimistic-write copy. The enrichment and account fields are **double optionals** (`T??`):

   > The double optionals are what let "leave it" and "set it to nil" be different arguments.

   Resolution is `field ?? other.field` — i.e. `nil` (outer) means "leave it", `.some(nil)` means "set
   to nil". **Android has no double optional.** Model it as a sentinel wrapper, e.g.
   `sealed interface Patch<out T> { object Keep; data class Set<T>(val v: T?) }` with `Keep` as the
   default argument. Do not collapse it to a plain nullable — `Franchise.grafting` and the status
   writes both depend on the distinction.

2. `init(from decoder:)` — §2.

### 3.10 `FranchiseSummary` — lists (trending / search / library index)

| Field | Type | Default |
|---|---|---|
| `id` | `String` | **throws** |
| `source` | `MediaSource` | `.anilist` |
| `title` | `String` | `"Untitled"` |
| `cover`, `banner` | `String?` | `nil` |
| `isReleasing` | `Bool` | `false` |
| `partCount` | `Int` | `0` |
| `nextAiringAt` | `Int64?` | `nil` — soonest across parts |
| `upcoming` | `FranchiseUpcoming?` | `nil` |
| `year` | `Int?` | `nil` |
| `images` | `ArtworkSet?` | `nil` |
| `themes` | `[String]` | `[]` |
| `featuredVideo` | `FranchiseVideo?` | `nil` |
| `status`, `behind`, `newParts` | `WatchStatus?`, `Int?`, `Int?` | `nil` — `/me/library` only |

Derived: `timeAnchor == source.timeAnchor`.

### 3.11 Envelopes and request bodies

| Type | Fields |
|---|---|
| `FranchiseListResponse` | `franchises: [FranchiseSummary]` (**strict**), `correctedQuery: String?`, `originalQuery: String?`, `sources: [String: String]?` |
| `LibraryResponse` | `franchises: [Franchise]`, `prevOpenedAt: Int64` — synthesised, strict |
| `OpenedResponse` | `prevOpenedAt: Int64` |
| `OKResponse` | `ok: Bool` |
| `SubscribeBody` (Encodable) | `franchiseId: String`, `status: WatchStatus?` |
| `StatusBody` (Encodable) | `status: WatchStatus` |
| `ProgressBody` (Encodable) | `mediaId: Int`, `episodes: Int` |

`sources` is per-catalogue outcome (`"ok"` / `"failed"` / `"disabled"`). Doc comment:
> Absent means "nothing to report", never "everything failed": a catalogue that FAILED is not a
> catalogue with no matches.

### 3.12 `AiringActivityAttributes` (`ios/Shared/`)

```swift
struct AiringActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable { var airsAt: Date }
    var franchiseTitle: String
    var episodeNumber: Int?
}
```
File header: *"This file is a member of BOTH targets — ActivityKit matches app and widget by the
attributes type name, so it must be identical."* The widget renders a **self-ticking countdown**
(`Text(timerInterval:)`) to `airsAt`, so no live updates are needed while the app is closed.

Gating rule from `CLAUDE.md`: Live Activities and episode notifications are restricted to
`source == .anilist` (TMDB has no real clock) **and** `effectiveStatus == .watching` (they interrupt
you — a harder gate than `tracksAirings`).

**Android:** see the risk table — there is no ActivityKit. The nearest analogue is an ongoing
notification with `setUsesChronometer(true)` + `setWhen(airsAtMillis)` + `setChronometerCountDown(true)`
(API 24+), or Android 16's `Notification.ProgressStyle` "Live Update". Neither gives the Dynamic
Island presentation.

---

## 4. Enrichment types (`Models+Enrichment.swift`)

### 4.1 `ArtworkSet` — `Codable, Hashable, Sendable`

`portrait: String?`, `landscape: String?`, both normalised through `nonEmpty`.

> A missing landscape asset is `nil`: the server never puts a portrait poster in the landscape slot,
> so `nil` here is the signal to composite the cover whole rather than crop it to a forehead.

### 4.2 `WideArt` — `Hashable, Sendable` (**not** Codable, computed only)

```swift
init(landscape: String?, portrait: String?) {
    if let landscape { url = landscape; portraitSource = false }
    else             { url = portrait;  portraitSource = true  }
}
```
Note the edge case: when **both** are nil, `url == nil` **and `portraitSource == true`**.

> The one decision a wide frame makes: a landscape asset fills it; a portrait one is composited whole
> on its own blurred ground. Callers pass both halves straight to `LandscapeArt`, `ProgressBanner`,
> `BannerCard` or `ArtHeader` and **never re-derive the choice.**

### 4.3 `legacyBanner` (file-private free function)

```swift
private func legacyBanner(_ banner: String?, cover: String?) -> String? {
    guard let b = ArtworkSet.nonEmpty(banner), b != cover else { return nil }
    return b
}
```
> Writers older than the explicit artwork set copied a portrait cover into `banner` when the catalogue
> had no landscape asset; **exact URL equality is that copy**, and it is a poster, not a banner.

Note the comparison is against the raw `cover`, not `nonEmpty(cover)`.

### 4.4 The art accessors — the ONLY way a view reads art

Defined identically on `Franchise`, `FranchisePart` and `FranchiseSummary`:

| Property | Formula |
|---|---|
| `portraitArt` | `images?.portrait ?? ArtworkSet.nonEmpty(cover)` |
| `landscapeArt` | `images?.landscape ?? legacyBanner(banner, cover: cover)` |
| `wideArt` | `WideArt(landscape: landscapeArt, portrait: portraitArt)` |

Plus, on `FranchisePart` only:
```swift
func wideArt(within f: Franchise) -> WideArt {
    WideArt(landscape: landscapeArt ?? f.landscapeArt, portrait: portraitArt ?? f.portraitArt)
}
```
> The part's art with the show's behind it, for a card that is about the show as much as the season
> (Library's Continue watching).

`RelatedTitle.portraitArt` is `images?.portrait` **only** — no legacy fallback, because a related
title has no `cover` field.

⚠️ Note the `??` chain: `images?.portrait ?? nonEmpty(cover)` falls through when `images` exists but
its `portrait` is nil — i.e. an explicit `{"portrait": null}` still allows the legacy `cover`. That is
intended.

`CLAUDE.md`: *"Art is read through `portraitArt` / `landscapeArt` / `wideArt`, **never `cover`/`banner`
in a view**."*

### 4.5 `FranchiseVideo` — `Codable, Identifiable, Equatable, Sendable`

| Field | Type | Default |
|---|---|---|
| `id` | `String` | **throws** — provider id, e.g. `"ldfEtPf3CfQ"`; also the `Identifiable` id |
| `site` | `String` | `""`, always `.lowercased()` |
| `kind` | `Kind` | `.other` |
| `title` | `String?` | `nil` (nonEmpty) |
| `url` | `String?` | `nil` (nonEmpty) |
| `thumbnail` | `String?` | `nil` (nonEmpty) |
| `official` | `Bool?` | `nil` |
| `language` | `String?` | `nil` |
| `country` | `String?` | `nil` |
| `publishedAt` | `String?` — ISO 8601 | `nil` |
| `scope` | `Scope` | `.franchise` |

`scope` decoding: read the nested object; it is `.part(mediaId:label:)` **only when**
`scope.type == "part"` **and** `scope.mediaId` decodes as `Int`; `label` defaults to `""`. Anything
else → `.franchise`.

A hand-written `encode(to:)` mirrors the contract shape exactly —
> Written in the contract's own shape, so the library's offline copy reads back exactly.

(The offline `library-cache.json` in Application Support round-trips through this encoder.)

**Derived:**

| Property | Formula / output |
|---|---|
| `youtubeID` | `site == "youtube" ? id : nil` |
| `watchURL` | `URL(url) ?? URL("https://www.youtube.com/watch?v=<youtubeID>")` |
| `embedURL` | `https://www.youtube.com/embed/<youtubeID>?playsinline=1&autoplay=1&rel=0&modestbranding=1` — YouTube only |
| `thumbnailURL` | `thumbnail ?? "https://i.ytimg.com/vi/<youtubeID>/mqdefault.jpg"` |
| `displayTitle` | `title ?? Copy.Video.kind(kind)` → `"Trailer"`/`"Teaser"`/`"Announcement"`/`"Featurette"`/`"Clip"`/`"Video"` |
| `partLabel` | `"Season 6"` when `scope == .part` with a non-empty label, else `nil` |

`CLAUDE.md` gotcha for the embed: it must be loaded inside a WKWebView `<iframe>` on a page with a
**neutral base URL** — *"a bare embed URL gets 'Video player configuration error', a youtube.com base
URL gets 'unavailable · 152-4'."* Android WebView has the same class of restriction; port the
neutral-base-URL wrapper, not just the URL.

### 4.6 `ContentRating` / `AudienceInfo`

`ContentRating`: `country: String`, `rating: String` — both required (synthesised Codable).

`AudienceInfo`: `isAdult: Bool?`, `contentRating: ContentRating?`, `availableRatings: [ContentRating]` (`[]`).

> `contentRating` is the exact match for the market the app asked for; the server does not substitute
> another country's rating, so a miss is `nil`, never "US".

`availableRatings` has **zero consumers** (§8).

### 4.7 `CatalogPerson` — `Codable, Identifiable, Hashable, Sendable`

| Field | Type | Default |
|---|---|---|
| `source` | `MediaSource` | `.anilist` |
| `externalId` | `Int` | `0` |
| `name` | `String` | `""` (then filtered out by `FranchisePeople`) |
| `role` | `String?` | `nil` (nonEmpty) |
| `image` | `String?` | `nil` (nonEmpty) |

```swift
var id: String { "\(source.rawValue):\(externalId):\(role ?? "")" }
```
> One person can appear once per role (a director who also acts).

Contract: anime cast are Japanese voice actors with the **character name** in `role`; general-TV cast
are top-billed with their character; creators and directors are separate.

### 4.8 `FranchisePeople`

`creators`, `directors`, `cast` — three `[CatalogPerson]`, each `[]` on miss and filtered
`!name.isEmpty`.

| Derived | Formula |
|---|---|
| `isEmpty` | `creators.isEmpty && directors.isEmpty && cast.isEmpty` |
| `ordered` | `named(creators, "Creator") + named(directors, "Director") + cast`, then de-duplicated by `id` keeping the **first** occurrence |

`named(people, role)` replaces a `nil` role with the given word — *"each with a role word where the
catalogue gave none, so a face is never unexplained."* The order is fixed: **the people who made it,
then the people in it.** Role words come from `Copy.People.creator` = `"Creator"` and
`Copy.People.director` = `"Director"`.

### 4.9 `RelatedTitle` — `Codable, Identifiable, Hashable, Sendable`

| Field | Type | Default |
|---|---|---|
| `source` | `MediaSource` | `.anilist` |
| `externalId` | `Int` | `0` |
| `franchiseId` | `String?` | `nil` (nonEmpty) — filled **only** once the title exists locally |
| `title` | `String` | `""` (then filtered out by `Franchise`) |
| `year` | `Int?` | `nil` |
| `images` | `ArtworkSet?` | `nil` |

`id = "\(source.rawValue):\(externalId)"` (no role component, unlike `CatalogPerson`).

```swift
var identityLine: String {
    guard let year else { return source.kindWord }
    return "\(source.kindWord) \u{00B7} \(year)"          // "Anime · 2017"
}
```
Separator is **U+00B7 MIDDLE DOT with plain ASCII spaces either side**. This is the app's universal
fact separator; use it everywhere on Android too.

Navigation contract from `CLAUDE.md`: `franchiseId` present → push Detail; absent → an exact-title
search materialises it, or the notice `Copy.Notice.notInCatalogue`.

### 4.10 `ContinueWatching`

| Field | Type | Default |
|---|---|---|
| `mediaId` | `Int` | **throws** |
| `partLabel` | `String` | `""` |
| `episode` | `Episode` | **throws** if the key is absent (`Episode` itself never throws) |

> The server's own answer to "what do I watch next": the first already-aired episode the user has not
> watched, with whatever the catalogue knows about it. User-specific, **never unaired**.

Contract: it prefers a part the user already started, then the first unfinished part; missing episode
metadata produces *"an honest Episode-N shell with nullable context rather than suppressing the next
episode."* Rendered as `"Season 4 · Episode 12 · The Lion and the Sea"`.

### 4.11 `WatchAvailability` / `WatchProvider`

`WatchAvailability`: `country: String` (`""`), `status: Status` (`.unmatched`), `providers:
[WatchProvider]` (`[]`), `link: String?` (nonEmpty), `attribution: String` (**default `"JustWatch"`**).
Derived: `linkURL = URL(link)`.

> Consumers branch on `status`, **never on `providers.isEmpty`**: `notAvailable` is a matched title
> with no streaming option in that country, `unmatched` means the anime→TMDB bridge could not
> establish identity safely, and `disabled` means this deployment has no TMDB token.

`WatchProvider`: `id: Int` (**throws**), `name: String` (`""`), `logo: String?` (nonEmpty),
`access: Access` (`.subscription`). Order is contractual — subscription services first, then free and
ad-supported.

UI rule from `CLAUDE.md`: the Where-to-watch section is **drawn only for `status == .available`** —
*"a section that says 'not here' is not a section."* The header opens `link` (TMDB gives a regional
watch page, not reliable deep links) and the JustWatch attribution is required.

### 4.12 `AppRegion`

```swift
static var current: String {
    let code = (Locale.current.region?.identifier ?? "").uppercased()
    return code.count == 2 && code.allSatisfy(\.isLetter) ? code : "US"
}
```
> A device that states no region falls back to "US": an unset region is not "no market".

Sent as `?country=` on `GET /franchises/:id` and `GET /franchises/:id/watch-providers`.
**Android:** `Locale.getDefault().country` (already ISO-3166-1 alpha-2 upper-case), with the same
two-letter/all-letters validation and `"US"` fallback.

---

## 5. Derived logic — `FranchisePart`

This is the heart of the subsystem. Each entry gives the exact formula and the reason it exists.

### 5.1 Simple state

| Property | Formula | Notes |
|---|---|---|
| `isMovie` | `kind == .movie` | *"Movies are a single binary unit (watched / not watched) — no episode count."* |
| `isUpcoming` | `status == "NOT_YET_RELEASED"` | **Keyed on status ALONE.** See box |
| `premiereAt` | `isUpcoming ? nextAiringAt : nil` | |
| `episodesBehind` | `isReleasing ? max(0, airedEpisodes - progress) : 0` | *"Ported verbatim from `format.ts` `episodesBehind`."* Catalogue-count version |
| `isBehind` | `episodesBehind > 0` | zero consumers |
| `isCaughtUp` | `isReleasing && episodesBehind == 0` | |
| `isFinished` | `isMovie ? progress > 0 : (!isReleasing && totalEpisodes > 0 && progress >= totalEpisodes)` | zero consumers |

> **`isUpcoming` — why status alone:** *"a catalogue that publishes an announced season's planned
> episode count (TMDB does) would otherwise fail the old `airedEpisodes == 0` test and the season
> would masquerade as released — losing its premiere date and inventing a backlog."*

### 5.2 `availableEpisodes()` and `progressCeiling`

```swift
func availableEpisodes() -> Int {
    if isUpcoming { return 0 }
    return airedEpisodes > 0 ? airedEpisodes : totalEpisodes
}
```
> Zero for an announced part: a season that hasn't started has nothing to watch, whatever episode
> count the catalogue advertises for it.

```swift
var progressCeiling: Int {
    if isUpcoming { return 0 }
    let size = max(totalEpisodes, airedEpisodes)
    return size > 0 ? size : Int.max
}
```
> Highest episode number that may be recorded as watched — the season's **SIZE**. A "+1" logging
> control with no ceiling will happily run progress past the end of a season (a 10-episode season sat
> at **59/10** because every tap incremented and the progress ring clamped its *visual* at 100 %, so
> the overrun was invisible).
>
> Deliberately the season size rather than `availableEpisodes()`: aired counts trail the catalogue by
> up to an hour, and blocking a legitimate write on stale sync data is worse than allowing a keen
> viewer to run a few episodes ahead. Unknown size (ongoing AniList shows carry `episodes: null`)
> leaves it **unbounded** rather than guessing.

`Int.max` → Kotlin `Int.MAX_VALUE`. Six call sites bound every write with it.

### 5.3 `scheduleAirings` — the calendar-facts fallback

```swift
var scheduleAirings: [Airing] {
    if !airings.isEmpty { return airings }
    var out: [Airing] = []
    if let last = lastAiredAt, last > 0, airedEpisodes > 0 {
        out.append(Airing(episode: airedEpisodes, at: last))
    }
    if let next = nextAiringAt, next > 0 {
        let ep = nextEpisodeNumber ?? airedEpisodes + 1
        if !out.contains(where: { $0.episode == ep }) { out.append(Airing(episode: ep, at: next)) }
    }
    return out.sorted { $0.at < $1.at }
}
```
> `airings` when the server sent them; otherwise the two slots every server has always published —
> the next episode and the latest aired one — so a weekly show still lands on its next date and its
> last one. Ascending by instant.

Against a modern server this is never reached; it exists so an old deployment shows each weekly show
once rather than not at all.

### 5.4 Airings-derived freshness — the four functions everything live reads

Preamble comment, verbatim, because it is the single most consequential paragraph in the file:

> `airedEpisodes`, `lastAiredAt` and `nextAiringAt` are the **CATALOGUE'S** facts, advanced by an
> hourly sync. `airings` is the per-episode calendar the same payload carries, and a slot in it that
> has struck IS an aired episode — the count merely hasn't caught up yet. Reading only the counts made
> the one show that had just aired (**Re:ZERO, 6:30 PM**) the one show Today could not see for up to
> an hour: not fresh (count unchanged), not waiting (slot passed) — **gone**. Every "is it out yet /
> when is the next one" question goes through these four. The raw fields stay for sort keys and the
> Library's calm captions, where an hour is nothing.

**`passedAirings(now:anchor:)`** (private) — the anchor-aware "has this slot struck" predicate:
```swift
airings.filter { a in
    anchor.isDateOnly ? Formatting.dayDiff(ts: a.at, now: now, anchor: anchor) < 0
                      : a.at <= now
}
```
> A real instant once its clock has struck; a date-only slot **the day AFTER** its date (its clock is
> synthesized, and on the day itself it still reads "today").

| Function | Formula |
|---|---|
| `airedByNow(now:anchor:)` | `guard isReleasing else { return airedEpisodes }` → `max(airedEpisodes, passedAirings(...).map(\.episode).max() ?? 0)` |
| `behind(now:anchor:)` | `isReleasing ? max(0, airedByNow(now:anchor:) - progress) : 0` |
| `lastAired(now:anchor:)` | `[lastAiredAt, passedAirings(...).map(\.at).max()].compactMap{$0}.max()` → `Int64?` |
| `upcomingAiring(now:anchor:)` | see below |

```swift
func upcomingAiring(now: Int64, anchor: TimeAnchor = .local) -> Int64? {
    let ahead = airings
        .filter { a in anchor.isDateOnly ? dayDiff(ts: a.at, now: now, anchor: anchor) >= 0
                                         : a.at > now }
        .map(\.at).min()
    if let ahead { return ahead }
    guard let slot = scheduledAiring(now: now, anchor: anchor) else { return nil }
    return (anchor.isDateOnly || slot > now) ? slot : nil
}
```
> The next slot still AHEAD — **strictly future** for a timed source (a slot that has struck is an
> episode, not a wait), **today-or-later** for date-only — from the airings first, then the
> catalogue's single slot. What every "Airs Friday" / countdown reads.

**`scheduledAiring(now:anchor:)`** — the stale-slot guard:
```swift
guard let next = nextAiringAt,
      Formatting.dayDiff(ts: next, now: now, anchor: anchor) >= 0 else { return nil }
return next
```
> A `nextAiringAt` in the past is **STALE DATA, not a schedule**: the catalogue simply hasn't advanced
> the slot yet (an announced premiere whose date has come and gone, a season that ended between
> syncs). Reading it as a live schedule is what made a week-old timestamp render as "today" every
> day. **Same-day is kept** — an episode that aired a few hours ago still legitimately reads as
> "today". […] a TMDB slot must be judged against its own UTC date or a JST morning keeps yesterday's
> drop alive as "today". Prefer `Franchise.nextAiring(now:)`, which can't forget to pass it.

Default arguments are `.local` on all five — **always pass the franchise's `timeAnchor`**. This is
exactly the trap `Franchise.nextAiring(now:)` and `Franchise.lastAired(now:)` exist to close; port the
franchise-level wrappers, not just the part-level primitives.

### 5.5 The aired / renderable / mark-target ladder (`Models+Shared.swift`)

Header comment:
> Three different questions that were repeatedly confused for one another:
> `provenAiredCount` — how many episodes we can PROVE have aired;
> `renderableEpisodeCount` — how many rows to draw (plumbing; **NEVER shown as a season length**);
> `markTarget` — what "mark this season watched" writes.

```swift
func provenAiredCount(now: Int64) -> Int {
    guard isReleasing else { return airedEpisodes }
    let dated = episodes.reduce(0) { acc, ep in
        guard let d = ep.airDate,
              Formatting.dayDiff(ts: d, now: now, anchor: Episode.airDateAnchor) < 0 else { return acc }
        return max(acc, ep.number)
    }
    let struck = airings.filter { $0.at <= now }.map(\.episode).max() ?? 0
    return max(airedEpisodes, dated, struck)
}
```
Two reasons, both quoted:
> `airedEpisodes` is the server's derivation from catalogue airing data, but a part caught mid-sync
> can report 0 while its own episode list already carries dates in the past. Trusting that blindly
> dims every row and collapses `markTarget` onto the user's progress, so a season header renders
> "watched" purely because there is nothing left to compare against. An episode whose air date has
> passed HAS aired, so take the higher count.
>
> Strictly **BEFORE today**, not "today or earlier": today's slot is the one the catalogue is still
> counting down to, and swallowing it here would cost the next-to-air row its date badge on every
> healthy season the moment its drop day arrives.
>
> A per-episode slot that has struck is an aired episode too: without it the mark target trailed the
> catalogue's count by a sync, so the episode Today had just called "out now" could not be marked. For
> a date-only source this admits the drop day once its synthesized 17:00 UTC instant has passed —
> TMDB's own date has arrived by then.

> ⚠️ **Deliberate asymmetry — do not "unify" it.** The `struck` term uses the raw `$0.at <= now`, with
> **no anchor**, while `airedByNow`'s `passedAirings` requires `dayDiff < 0` for a date-only source.
> `provenAiredCount` is therefore *more permissive* for TMDB (it admits the drop day at 17:00 UTC).
> `dated` uses `dayDiff < 0` with `Episode.airDateAnchor` (always `.utcDate`). Three different
> passed-ness tests inside one function, each justified above.

```swift
func renderableEpisodeCount(now: Int64) -> Int {
    if totalEpisodes > 0 { return totalEpisodes }
    let aired = provenAiredCount(now: now)
    let nextToAir = (isReleasing && nextAiringAt != nil) ? aired + 1 : 0
    return max(aired, progress, nextToAir)
}
```
> With a known total, never exceed it. With an unknown total (0) extend one past what has aired so the
> next-to-air row can carry its date badge. **Row plumbing ONLY: it is a guess, and a guess must never
> be shown as a season length.**

```swift
func markTarget(now: Int64) -> Int { isReleasing ? provenAiredCount(now: now) : renderableEpisodeCount(now: now) }

var isComplete: Bool {                       // reads the wall clock — see below
    let target = markTarget(now: .nowMs)
    return target > 0 && progress >= target
}
```
> `isComplete` uses `.nowMs` because "complete" is a property of the part at the moment it is asked,
> and callers that need a pinned clock use `markTarget(now:)` directly.

`markTarget` is bounded **again** by `progressCeiling` at the write site.

### 5.6 Labels

| Property | Formula | Output |
|---|---|---|
| `canonicalLabel` | `label.trimmingCharacters(in: .whitespacesAndNewlines)` | `"Season 4"`, `"Final Season"`, `""` |
| `episodeLabel(_ n:)` | `Copy.episode(n)` | `"Episode 19"` — never `"E19"`, never `"Ep 19"` |
| `watchContext(episode:)` | movie → `canonicalLabel`; empty label → `episodeLabel(n)`; else `"\(label) · \(episodeLabel(n))"` | `"Season 4 · Episode 19"` |
| `premiereDateLabel(source:)` | `premiereAt.map { fmtFullDate($0, anchor: source.timeAnchor) }` | `"Jun 24, 2026"` |
| `announcedDateLabel(source:)` | `premiereDateLabel(source:)` **else** `fmtFullDate(episodes.compactMap(\.airDate).min()!, anchor: .utcDate)` **else** `nil` | ″ |

> `canonicalLabel` is *"the source's OWN label […] **Never derived from `sequence`.** Empty string when
> the source gave no label — unknown says unknown; a fabricated 'Season 1' is worse than nothing."*
>
> `announcedDateLabel`: *"`premiereDateLabel` reads the catalogue's own premiere slot, which TMDB
> frequently leaves null while still dating the season through its first episode. Falling back to the
> earliest episode air date is the difference between a real date and a bare 'TBA'."*

> 🚩 **Inconsistency to resolve during the port.** `FranchisePart.watchContext(episode:)` concatenates
> `canonicalLabel` **raw**, while `Franchise.watchContext(part:episode:)` (§6.7) routes through
> `Copy.watchContext`, which **compacts** `"Season 5: Hashira Training Arc"` → `"Season 5"` via the
> regex `^Season \d+(?=:)`. Two spellings of one fact. Pick the compacting one for both on Android.

### 5.7 Copy-with helpers (optimistic writes)

| Method | Replaces | Everything else |
|---|---|---|
| `withEpisodes(_ eps:)` | `episodes` | carried verbatim |
| `withProgress(_ episodes: Int)` | `progress = max(0, episodes)` | carried verbatim |
| `with(episodes:images:videos:)` | those three | carried verbatim |

> **Every optimistic write goes through `withProgress`** so a local mark never drops a field the server
> sent — *"`airings` used to fall off here, and a marked show left the calendar until the next
> reload."*

On Android this is `copy(progress = maxOf(0, episodes))` — the failure mode the comment describes
(a hand-built constructor call that silently omits a newer field) is exactly what `data class.copy()`
prevents. **Never hand-build a `FranchisePart` on Android; always `copy()`.**

---

## 6. Derived logic — `Franchise`

### 6.1 Calendar wrappers

| Property / method | Formula |
|---|---|
| `timeAnchor` | `source.timeAnchor` |
| `dayKey(of ts:)` | `Formatting.localDayKey(ts, anchor: timeAnchor)` |
| `dayDiff(of ts:, now:)` | `Formatting.dayDiff(ts:now:anchor: timeAnchor)` |
| `whenLabel(ts:now:)` | `Formatting.fmtWhen(ts:now:anchor: timeAnchor)` → anime `"Tomorrow 9:00 PM"`, TV `"Tomorrow"` / `"Thursday"` / `"May 4"` |
| `nextAiring(now:)` | `releasingPart?.upcomingAiring(now: now, anchor: timeAnchor)` |
| `lastAired(now:)` | `releasingPart?.lastAired(now: now, anchor: timeAnchor)` |

These exist purely so a call site *cannot forget the anchor*. Port them and make the part-level
functions internal.

### 6.2 `releasingPart` — the part every live surface operates on

```swift
var releasingPart: FranchisePart? {
    let releasing = parts.filter { $0.isReleasing }
    if releasing.isEmpty { return nil }
    let upcoming = releasing
        .filter { $0.nextAiringAt != nil }
        .sorted { ($0.nextAiringAt ?? .max) < ($1.nextAiringAt ?? .max) }
    if let first = upcoming.first { return first }
    return releasing.sorted { ($0.lastAiredAt ?? 0) > ($1.lastAiredAt ?? 0) }.first
}
```
> Mirrors the api-contract "Client-side derivation": pick the releasing part, preferring the one with
> the soonest next airing, else the most recently aired.

Note it reads the **raw** `nextAiringAt`/`lastAiredAt`, not the airings-derived values — the airings
logic is applied *after* the part is chosen.

⚠️ Swift's `sorted` is **not stable**; Kotlin's `sortedBy` **is**. For equal keys the two platforms
may pick different parts. This is benign (both are "a releasing part with the same date") but note it
if a golden-file test ever compares.

### 6.3 Sort keys — the centralised sentinels

| Property | Formula | Sentinel meaning |
|---|---|---|
| `nextAiringSortKey` | `releasingPart?.nextAiringAt ?? Int64.max` | no known next airing sorts **last** (ascending) |
| `lastAiredSortKey` | `releasingPart?.lastAiredAt ?? 0` | no aired part sorts **last** (descending) |

`CLAUDE.md`: *"reuse the existing sort-key accessors instead of re-inlining `?? .max` / `?? 0`
sentinels."*

> `lastAiredSortKey` doc comment: *"The **CATALOGUE'S** field: fine for the Library's calm shelves,
> wrong for anything live — sort Today's stack on `lastAired(now:)`, or tonight's episode loses the
> hero to a days-old drop."*

### 6.4 `episodicParts` / `episodicPartsInOrder`

```
parts.filter { kind ∈ {.season, .ona, .ova} }.sorted { $0.sequence < $1.sequence }
```
> A movie is a binary unit and is handled separately; specials and music videos are not part of the
> spine.

⚠️ **This is implemented twice** — `private var episodicParts` in `Models.swift` and
`var episodicPartsInOrder` in `Models+Shared.swift`, byte-for-byte identical bodies. Port **one**.

### 6.5 `resumePart` and `continueBacklog`

```swift
var resumePart: FranchisePart? {
    let eps = episodicParts
    func available(_ p: FranchisePart) -> Int { p.availableEpisodes() }

    // 1. mid-watch
    if let mid = eps.first(where: { $0.progress > 0 && $0.progress < available($0) }) { return mid }
    // 2. the first unstarted part AFTER the highest-sequence completed one
    if let doneSeq = eps.last(where: { available($0) > 0 && $0.progress >= available($0) })?.sequence,
       let next = eps.first(where: { $0.sequence > doneSeq && available($0) - $0.progress > 0 }) {
        return next
    }
    // 3. the earliest part with anything left
    return eps.first(where: { available($0) - $0.progress > 0 })
}
```
> The part the user would actually resume, in watch order: the one they're mid-way through, else the
> first unstarted part *after* everything they finished, else the earliest part with anything left.
> Nil when there's no backlog anywhere.
>
> **Picking by sequence (not by largest backlog) is the point:** a `max()` would resume S3 at 3/10 into
> an untouched S5 just because S5 is longer. With non-sequential progress (S2 untouched, S3
> half-watched) the mid-watch part still wins — resuming what you're actively watching beats sending
> you back to a season you skipped.

Note step 2's `if let … , let …`: if a completed part exists but nothing later qualifies, control
**falls through to step 3** (it does not return nil). `last(where:)` over an ascending list = the
highest-sequence completed part.

```swift
var continueBacklog: Int {
    guard let p = resumePart else { return 0 }
    return max(0, p.availableEpisodes() - p.progress)
}
```
The "Keep watching" count; `0` when nothing is left.

### 6.6 `effectiveStatus` and `tracksAirings`

```swift
var effectiveStatus: WatchStatus { status ?? subscription?.status ?? .planned }
var tracksAirings:   Bool        { effectiveStatus != .planned }
```

`tracksAirings` doc comment (this is a product law, not an implementation detail):
> A `planned` show is in your library but not in your week. You are not behind on it and you are not
> waiting on its next episode; it is something you might start. Without this test a mid-broadcast show
> you had only shelved arrived on Today as "20 episodes behind" and on Schedule with a mark ring whose
> action was "Mark 20 episodes as watched" — **an obligation invented out of a bookmark**, which is
> exactly what the urgency pact forbids.
>
> Every other status keeps its airings, deliberately: a `completed` show that starts a new season is
> news, and a `paused` one still has a calendar. `EpisodeNotifications` and
> `AiringLiveActivityManager` gate **harder still (`watching` only)** — they interrupt you.

Gating ladder, three tiers: **all statuses** (Library shelves) ⊃ **`tracksAirings`** (Schedule, Today's
Out now / Airing soon / Now Bar) ⊃ **`.watching`** (episode notifications, Live Activity).

### 6.7 Current part, completion, labels, snapshot

| Property | Formula |
|---|---|
| `currentPart` | `releasingPart ?? resumePart ?? episodicPartsInOrder.first { !$0.isComplete }` |
| `isSeriesComplete` | `!episodic.isEmpty && episodic.allSatisfy(\.isComplete) && !parts.contains { $0.isReleasing \|\| $0.isUpcoming } && upcoming?.isFutureInstallment != true` |
| `canonicalPartLabel(for mediaId:)` | `parts.first { $0.mediaId == mediaId }?.canonicalLabel ?? ""` |
| `kindWord` | `source.kindWord` |
| `snapshotForUndo` | `self` |
| `displayTitle` | `title.shelfShortened` (§7.1) |

> `isSeriesComplete`: *"The whole work is finished: every episodic member complete, nothing releasing,
> and no future installment announced. This is the question `Copy.Progress.complete(_:)` and the
> series-complete milestone both ask — it lives here so no screen re-derives it."*
>
> `snapshotForUndo`: *"`Franchise` is a value type, so this is the whole show — parts, progress and
> status — frozen at the instant of the removal. That is what lets Undo restore instantly, before any
> network round-trip."* **On Android this only works if every model in the graph is an immutable
> `data class` with no shared mutable collections.**

```swift
func watchContext(part: FranchisePart, episode n: Int) -> String {
    if part.kind == .movie { return part.canonicalLabel }
    return parts.count > 1 ? Copy.watchContext(part: part.canonicalLabel, episode: n) : Copy.episode(n)
}
```
> THE watch-context rule: `"Season 7 · Episode 5"` on a multi-part franchise, `"Episode 5"` on a single
> one. Today owned this rule privately while Library and Schedule always printed the season and
> Detail's Next up card never did — **one fact, three grammars. Every screen calls this now.**

### 6.8 `sections`

```swift
var sections: [(kind: PartKind, parts: [FranchisePart])] {
    Dictionary(grouping: parts, by: \.kind)
        .map { (key, value) in
            let ordered = value.sorted { $0.sequence < $1.sequence }
            return (key, key == .season ? ordered.reversed() : ordered)
        }
        .sorted { $0.kind.sortRank < $1.kind.sortRank }
}
```
> Seasons are listed **newest-first** (reverse sequence) so the latest season is at the top; other
> kinds stay chronological.

Dictionary iteration order is non-deterministic in Swift but the final `sorted` on the unique
`sortRank` makes the result deterministic.

### 6.9 Enrichment derivations on `Franchise`

| Property | Formula | Why |
|---|---|---|
| `allVideos` | `([featuredVideo].compactMap{$0} + videos + parts.flatMap(\.videos))`, de-duplicated by `"\(site)/\(id)"`, **first wins** | *"featured first, then the show's own, then each part's"* |
| `contentRatingLabel` | non-empty `audience?.contentRating?.rating`, else `audience?.isAdult == true ? "18+" : nil` | The market's own word, else the adult flag. Nothing when the catalogue says nothing |
| `themesBeyondGenres` | `themes.filter { !Set((genres + parts.flatMap(\.genres)).map(\.lowercased)).contains($0.lowercased()) }` | *"the catalogue's themes for an anime often ARE its genres, and a fact printed twice on one screen is a defect"* |
| `looksUnenriched` | `(people?.isEmpty ?? true) && related.isEmpty && videos.isEmpty && featuredVideo == nil` | *"True while the server's background enrichment has not reached this row yet […] Detail re-reads once on seeing this"* — after **6 s** (`CLAUDE.md`) |

Note `looksUnenriched` ignores `themes` and `parts[].videos` on purpose — those are cheap and arrive
earlier.

### 6.10 `grafting(_:)` — detail read onto the live library copy

```swift
func grafting(_ fetched: Franchise) -> Franchise {
    guard fetched.id == id else { return self }
    let byMedia = Dictionary(fetched.parts.map { ($0.mediaId, $0) }, uniquingKeysWith: { a, _ in a })
    let mergedParts = parts.map { p -> FranchisePart in
        guard let d = byMedia[p.mediaId] else { return p }
        let eps  = p.episodes.isEmpty ? d.episodes : p.episodes
        let vids = p.videos.isEmpty   ? d.videos   : p.videos
        let imgs = p.images ?? d.images
        if eps.count == p.episodes.count, vids.count == p.videos.count, imgs == p.images { return p }
        return p.with(episodes: eps, images: imgs, videos: vids)
    }
    return Franchise(copying: self, parts: mergedParts,
                     images:          images    ?? fetched.images,
                     themes:          themes.isEmpty        ? fetched.themes   : themes,
                     featuredVideo:   featuredVideo         ?? fetched.featuredVideo,
                     videos:          videos.isEmpty        ? fetched.videos   : videos,
                     audience:        fetched.audience      ?? audience,          // detail WINS
                     people:          (people?.isEmpty ?? true) ? fetched.people : people,
                     related:         related.isEmpty       ? fetched.related  : related,
                     continueWatching: fetched.continueWatching ?? continueWatching)  // detail WINS
}
```
> The live **LIBRARY** copy (fresh progress and status) with the **DETAIL** fetch's per-episode data
> and catalogue enrichment grafted on. The library payload carries the enrichment too, but it was read
> at launch — before the server's stale-while-revalidate pass may have run — so a detail read that came
> back richer wins, **field by field**; the market-matched `audience` and the fresher
> `continueWatching` **always** come from the detail read.

Receiver = library copy. Rules to reproduce exactly:
- **id mismatch → no-op.** Return `self`.
- Duplicate `mediaId` in the fetched parts: **first wins**.
- Parts are mapped over **`self.parts` only** — a part the detail read knows about but the library
  copy does not is **dropped**.
- The `if eps.count == … , vids.count == … , imgs == p.images { return p }` short-circuit is an
  identity optimisation (avoid allocating an unchanged copy); it compares **counts**, not contents.
- `progress`, `status`, `subscription`, `behind`, `newParts`, `upcoming`, `title`, `synopsis`,
  `genres`, `year`, `studios` all come from the **library** copy, untouched.

---

## 7. Title normalisation and the Copy vocabulary

### 7.1 `String.shelfShortened` (`Primitives.swift`) → `Franchise.displayTitle`

```swift
var shelfShortened: String {
    var s = trimmingCharacters(in: .whitespacesAndNewlines)
    // 1. a trailing "-…-" subtitle wrapper
    if s.hasSuffix("-"), let open = s.range(of: " -") {
        s = String(s[s.startIndex..<open.lowerBound])          // first " -" wins
    }
    // 2. strip leading/trailing subtitle punctuation
    s = s.trimmingCharacters(in: CharacterSet(charactersIn: " -\u{2013}\u{2014}:"))
    // 3. a long "Title: Subtitle" keeps its identity half
    if s.count > 40 {
        for sep in [": ", " – ", " — ", " - ", " ("] {
            if let r = s.range(of: sep), s.distance(from: s.startIndex, to: r.lowerBound) >= 12 {
                return String(s[s.startIndex..<r.lowerBound])
            }
        }
    }
    return s
}
```

| Step | Exact behaviour |
|---|---|
| 1 | Only when the string **ends** with `-`. Cuts at the **first** occurrence of `" -"` (space + hyphen). `"Re:ZERO -Starting Life in Another World-"` → `"Re:ZERO"` |
| 2 | Trims any of `space`, `-`, U+2013 en dash, U+2014 em dash, `:` from **both** ends |
| 3 | Only when length > **40 characters**. Separators tried **in order**: `": "`, `" – "` (en), `" — "` (em), `" - "`, `" ("`. The first separator that is both **found** and located at index **≥ 12** wins and returns immediately. A separator found at index < 12 does **not** return — the loop continues to the next separator |

> Source titles arrive wrapped in subtitle punctuation […] and a line that opens on a hyphen reads as a
> hyphenation bug, not as a title. Stripping the dashes is lossless; what follows the em/en dash or the
> colon is a subtitle the shelf never had room for anyway. […] A long "Title: Subtitle" keeps its
> identity half rather than an ellipsis mid-word.

`Franchise.displayTitle` doc comment states where the raw title survives:
> The title wherever identity is being **recognised** — Today, Library, Schedule, Detail. […] The raw
> `title` is kept for exactly two jobs: **Search results**, where the user is matching what they typed
> against a catalogue and every character of the source string is evidence, and **accessibility
> labels**, which always speak the whole title.

> ⚠️ **Android:** `s.count` in Swift counts **grapheme clusters**, `String.length` in Kotlin counts
> **UTF-16 code units**. A CJK title with combining marks or emoji will cross the 40 threshold at a
> different point. Use `java.text.BreakIterator.getCharacterInstance()` (or
> `androidx.emoji2`-aware counting) to count clusters, and use code-point-safe substring indices.
> Likewise `s.distance(from:to:)` is a grapheme distance, not a UTF-16 offset.

### 7.2 `Copy` strings this subsystem depends on

`Copy.swift` is *"the only place a user-facing string lives"*. The ones reachable from the model layer:

| Function | Output | Notes |
|---|---|---|
| `Copy.episode(n)` | `"Episode 19"` | the **label** form; never `"E19"` / `"Ep 19"` |
| `Copy.episodeInSentence(n)` | `"episode 19"` | inside a sentence-case command |
| `Copy.compactPartLabel(label)` | `"Season 5: Hashira Training Arc"` → `"Season 5"` | regex `^Season \d+(?=:)`; **only** `Season N:` prefixes compact — *"a label like 'OVA 2: No Regrets' keeps its subtitle because the subtitle IS the identity there"* |
| `Copy.watchContext(part:episode:)` | `"Season 4 · Episode 19"` (U+00B7) | compacts first; empty compacted label → `Copy.episode(n)` alone |
| `Copy.plural(n, one, many)` | `"1\u{00A0}episode"` / `"3\u{00A0}episodes"` | **NBSP U+00A0** binds numeral to noun: *"a numeral must never end a line its unit doesn't start"* |
| `Copy.episodes(n)` | `plural(n, "episode", "episodes")` | |
| `Copy.episodesWatched(n)` | `"3 episodes watched"` | predicated so it cannot be read as the work's length |
| `Copy.Status(_:)` / `statusLabel(_:)` | §1.1 | |
| `Copy.Video.kind(_:)` | `Trailer`/`Teaser`/`Announcement`/`Featurette`/`Clip`/`Video` | |
| `Copy.People.creator` / `.director` | `"Creator"` / `"Director"` | |
| `Copy.Label.adultRating` | `"18+"` | |

English-only pluralisation is a deliberate scope decision (*"A `.stringsdict` is out of scope for this
prototype (confirmed)"*). On Android use plain string templates for parity, or move to
`plurals.xml` — but if you do, keep the NBSP.

---

## 8. Derived properties with ZERO consumers outside the model layer

Verified by grep across `Sources/` + `Widgets/`, excluding `Sources/Models/`. Port these only if you
are building the surface that would use them:

`FranchisePart.release` (the whole `ReleasePrecision` type) · `FranchisePart.nextAiringCount` ·
`AudienceInfo.availableRatings` · `FranchisePart.isMovie` (used internally by `isFinished`) ·
`FranchisePart.isBehind` · `FranchisePart.isFinished` · `Episode.airDateLabel` ·
`Episode.airDayLabel(now:)` · `FranchisePart.premiereDateLabel` (used internally by
`announcedDateLabel`) · `FranchiseUpcoming.cardBadge` · `FranchiseUpcoming.tag` ·
`FranchiseUpcoming.isConcluded` · `Franchise.partCounts`.

Actively used, for contrast: `sections` (28 refs), `progressCeiling` (6), `episodesBehind` (6),
`continueBacklog` (4), `announcedDateLabel` (3), `identityLine` (3), `scheduleAirings` (2),
`allVideos` (2), `partLabel` (2).

---

## 9. `FranchiseUpcoming` derivations

| Property | Formula | Output |
|---|---|---|
| `tag` | switch on `status`: `airing`→`"Airing now"`, `upcoming_dated`→`"Upcoming"`, `announced`/`announced_no_date`→`"Announced"`, `recently_aired`→`"Recently aired"`, `rumored`→`"Rumored"`, `concluded`→`"Complete"`, default→`"Upcoming"` | badge word |
| `isConcluded` | `status == "concluded"` | softens card styling |
| `isRumored` | `status == "rumored"` | *(defined in `Models+Enrichment.swift`)* |
| `displayRelease` | `""` when `release` is nil/whitespace, else `Formatting.prettyReleaseString(release!)` | `"Jul 5, 2026"` / `"Oct 2026"` / `"Summer 2027"` |
| `isFutureInstallment` | `status ∈ {upcoming_dated, announced, announced_no_date, rumored}` | |
| `releaseSortKey` | see below | `(value: Int, precision: Int)?` |
| `hasArrived(now:)` | see below | `Bool` |
| `cardBadge` | `""` unless `isFutureInstallment`; else `what = next?.nonEmpty ?? "New season"`, `when = displayRelease`; result `when.isEmpty ? what : "\(what) · \(when)"` | `"Season 3 · Jul 5, 2026"` |

**`prettyReleaseString(raw)`** (`Formatting.swift`): trim; split on `-`. If ≥2 numeric segments with
`year ∈ 1000…9999` and `month ∈ 1…12`:
- ≥3 segments with `day ∈ 1…31` → `fmtFullDate(utcMidnight(y,m,d), anchor: .utcDate)` → `"Jul 5, 2026"`
- exactly 2 segments → `"MMMyyyy"` skeleton at UTC → `"Oct 2026"`

Anything else passes through unchanged (`"October 2026"`, `"2027"`, `"TBA"`).
*"Parsed as a bare calendar date, so it is formatted in UTC and never shifts a day."*

**`releaseSortKey`:**
```swift
guard let window = releaseWindow, let value = window.sortKey else { return nil }
switch window.precision {
case .day:              return (value, 3)
case .month, .quarter:  return (value, 2)
case .year:             return (value, 1)
case .unknown:          return nil
}
```
> **the server's**, not a reading of `release`. `value` is `yyyymmdd`; `precision` (3=day, 2=month or
> quarter, 1=year) breaks ties so a concrete month sorts ahead of a bare year. Nil when the window is
> genuinely unknown — TBA, prose with no date, *and every rumor*, all of which the server already
> resolves to `unknown` — so those sort to the end.
>
> This used to parse `release` here, and only its ISO forms, which filed "October 2026" and "Summer
> 2027" under January of their year. The prose lives in one grammar on the server now.

`nil` must sort **last**. `AppModel` does this with `f.upcoming?.releaseSortKey ?? (Int.max, 0)`.

**`hasArrived(now:)`:**
```swift
guard isFutureInstallment, let key = releaseSortKey, key.precision == 3 else { return false }
var comps = DateComponents()
comps.year  =  key.value / 10000
comps.month = (key.value / 100) % 100
comps.day   =  key.value % 100
var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
guard let date = cal.date(from: comps) else { return false }
let ts = Int64((date.timeIntervalSince1970 * 1000).rounded())
return Formatting.dayDiff(ts: ts, now: now, anchor: .utcDate) < 0
```
> True once a **DAY-dated** release is behind us: the installment is out, or slipped without the
> catalogue's curated note noticing (its `checked` date is weeks old). Either way "Returns Jul 5" is no
> longer a fact, and the Library must not file the show under Returning on it — **Mushoku Tensei sat
> there reading "Returns today" two months into its third season.**

Month/quarter/year windows are **never** "arrived" (`precision == 3` guard) — a month-precision window
has no day to have passed.

---

## 10. Cross-model derivations that live outside these files

Two are named in the brief but live in `AppModel.swift` / `LibraryFacts.swift`. Summarised here so the
Android port keeps them in the same layer relationship.

### 10.1 `AppModel.shelfState(of:)` → `ShelfState`

```swift
enum ShelfState: Int { case newEpisode = 0, backlog, airingWait, premiereSoon }
```
The `rawValue` **is** the shelf sort order. Windows:

| Constant | Value |
|---|---|
| `soonWindow` ("Airing soon" lookahead) | `48 * H` = 172 800 000 ms |
| `outNowWindow` (how recent an unwatched drop stays "out now") | `7 * D` = 604 800 000 ms |
| `nowBarLiveWindow` | `24 * H` |
| `premiereShelfWindow` | `45 * D` |

```swift
func shelfState(of f: Franchise) -> ShelfState? {
    if let part = f.releasingPart, part.behind(now: now, anchor: f.timeAnchor) > 0,
       now - (part.lastAired(now: now, anchor: f.timeAnchor) ?? 0) <= outNowWindow { return .newEpisode }
    if f.resumePart != nil { return .backlog }
    if let part = f.releasingPart, part.isCaughtUp, f.nextAiring(now: now) != nil { return .airingWait }
    if let premiere = nextPremiere(of: f), premiere - now <= premiereShelfWindow { return .premiereSoon }
    return nil                                    // dormant: caught up with nothing dated
}
```
`nextPremiere(of:) = f.parts.compactMap(\.premiereAt).filter { $0 > now }.min()`.

Tie-break inside each state (`watchingShelf`): `.newEpisode` → `lastAiredSortKey` desc; `.backlog` →
`continueBacklog` desc; `.airingWait` → `nextAiringSortKey` asc; `.premiereSoon` → `nextPremiere` asc
with `?? .max`.

### 10.2 `ReturnFact.of(_:appModel:)` — the Library's "Returns …" caption ladder

The one consumer that reads `releaseWindow.precision` end to end. Order:
1. `appModel.nextPremiere(of: f)` exists → `TemporalCopy.returns(at:now:source:)`.
2. `upcoming.isRumored` → `Copy.Library.rumored(next:)` → e.g. `"Season 3 rumored"`, `dated: false`,
   `soon: false`. *"An unconfirmed report is not a schedule […] filing a rumour under 'No date
   announced' reads as a confirmed sequel."*
3. No `releaseWindow`, or `precision == .unknown`, or no `parts` → `TemporalCopy.returns(at: nil, …)`.
4. `precision == .day` **and** `parts.year == current UTC year` → friendly form
   (`"Returns tomorrow"` / `"Returns Saturday"` / `"Returns Oct 2"`), computed as UTC midnight of
   `(y, m, d)`, source forced to `.tmdb` (i.e. `.utcDate`).
5. `precision ∈ {day, month}` otherwise → `"Returns Oct 2026"` from UTC midnight of `(y, m, 1)`.
   *"a day nine months out is not a fact anybody acts on."*
6. `quarter` / `year` → the server's **prose** (`displayRelease`), lower-cased first letter:
   `"Returns summer 2027"` / `"Returns late 2026"` / `"Returns 2027"`. A bare 4-digit year passes
   through un-lowercased. Prose longer than 20 characters falls back to `"Returns <year>"`.
   **A window is never `soon`** — with no instant behind it the colour rule has nothing to measure.

Rule from `CLAUDE.md`: *"a rumour is labelled one everywhere the curated fact appears […] never a
date, never amber."*

---

## 11. Contract cross-check (`docs/api-contract.md`)

| # | Finding | Severity |
|---|---|---|
| 1 | **`PartCounts` cannot decode the shape the server sends.** The contract's own example is `{"season":4,"movie":2,"ova":3,"special":1}` and `franchiseView.ts:331` builds a `Partial<Record<PartKind, number>>`; the Swift struct's synthesised `Codable` requires **all six** keys, so `Franchise.partCounts` is `nil` in production. Zero consumers, so invisible. **Android: model as `Map<PartKind, Int>`.** | Confirmed drift, latent |
| 2 | **The contract's "Client-side derivation" section is badly stale.** It states *"All time math is **IST (Asia/Kolkata)** — port `istParts`, `istDayKey`, `istMondayCol`"*. The app has used device-local + per-source UTC anchoring (`Formatting.TimeAnchor`) for months; there is no IST anywhere in `ios/`. It also states *"Today / 'Out now' = releasing parts whose `lastAiredAt > prevOpenedAt`"*, *"Airing soon = `nextAiringAt` within 48h"*, and *"Schedule = releasing parts bucketed into the IST Mon–Sun week by `nextAiringAt`"* — all three superseded by the airings-derived freshness rules (§5.4) and the 2026-08-24 agenda rework. **Do not port from that section.** | Major doc drift |
| 3 | The contract documents `episodesBehind(part) = isReleasing ? max(0, airedEpisodes - progress) : 0` and nothing else. The app's live surfaces use `behind(now:anchor:)` (airings-derived) instead; `episodesBehind` survives only for calm captions. The contract never mentions the airings-derived ladder at all. | Doc gap |
| 4 | The contract says AniList supplies **no** per-episode `airDate`, but the `Airing` section says the airings list is merged from *"the dated episode list (TMDB always; **AniList after `backfill-episodes`**)"*. If AniList episode rows ever carry a real broadcast instant, `Episode.airDateAnchor = .utcDate` (hard-coded, source-independent) would read them in UTC and shift the day east of UTC+7. Currently unreachable; becomes a bug the day backfill writes `airDate`. | Latent risk |
| 5 | `WatchAvailability.attribution` is required in the contract; the client defaults it to `"JustWatch"` on absence. Harmless, but the client will silently show attribution the server never sent. | Minor |
| 6 | `Franchise.status` / `behind` / `newParts` are documented as `/me/library`-only on `FranchiseSummary`; the client decodes them optionally on the full `Franchise` too (correct — `LibraryFranchise` extends `Franchise`). No drift, noting for the Android type design: **one type with three nullable library-only fields**, not two types. | OK |
| 7 | `FranchisePart.release` is fully specified in the contract and fully decoded by the client, but nothing reads it — the app derives date-only-ness from `MediaSource.timeAnchor` instead. Two mechanisms for one fact. | Redundancy |
| 8 | `FranchiseUpcoming.status` is an open string on both sides (7 known values). Correct — an unseen status degrades through the `default:` branches rather than failing to decode. | OK |

---

## 12. Android portability risk register

| Item | Difficulty | Notes |
|---|---|---|
| Live Activity (`AiringActivityAttributes`, ActivityKit) + Dynamic Island | **Blocker** | No equivalent. Closest: an ongoing notification with `setUsesChronometer(true)` + `setChronometerCountDown(true)` + `setWhen(airsAt)`, or Android 16's `Notification.ProgressStyle` Live Update. There is no Dynamic Island surface at all — the compact/minimal/expanded presentations have no target. Redesign the feature, don't port it. |
| `Text(timerInterval:)` self-ticking countdown with the app closed | **Hard** | The iOS widget re-renders itself from the timeline. Android needs `Chronometer` inside `RemoteViews` (works in notifications), or a Glance widget driven by `WorkManager` — which costs battery budget iOS does not. |
| Swift **double optional** `T??` in `Franchise.init(copying:)` and `grafting` | **Moderate** | Kotlin has no `T??`. Replace with a `Patch<T>` sentinel (`Keep` / `Set(value)`) defaulted to `Keep`. Collapsing to a plain nullable **silently breaks** "set this field to nil". |
| Per-field `try?` leniency vs. kotlinx.serialization's throw-on-mismatch | **Moderate** | Needs a `SafeSerializer<T>(default)` delegating serializer applied per property, plus faithful **whole-array** drops where iOS drops the whole array (§2.1). `coerceInputValues` alone is not equivalent. |
| Synthesised-Codable strictness (`PartCounts`, `Airing`, `Subscription`, `ContentRating`, the envelopes) | **Easy** | Kotlin's defaults make these lenient by default — which is *different*. Mark them `@Serializable` **without** property defaults where iOS is strict, so behaviour matches. |
| `String.count` / `String.range(of:)` / `distance(from:to:)` as **grapheme clusters** in `shelfShortened` | **Moderate** | Kotlin `String.length` is UTF-16. Use `BreakIterator.getCharacterInstance()` for the `> 40` and `>= 12` thresholds, and code-point-safe substring. A CJK/emoji title otherwise shortens at a different point. |
| `DateFormatter.setLocalizedDateFormatFromTemplate("MMMd")` (skeleton → locale pattern) | **Easy** | `android.text.format.DateFormat.getBestDateTimePattern(locale, "MMMd")` is the same ICU call. |
| Locale short-time style honouring the 24-Hour Time switch | **Easy** | `DateFormat.getTimeFormat(context)` respects `Settings.System.TIME_12_24`. Watch for the same cache-invalidation trap — key the formatter cache on `locale + is24Hour + timeZoneId`. |
| `Calendar` cache re-keyed on `"<tz>|<locale>"` stamp | **Easy** | Same pattern with `ZoneId.systemDefault()` + `Locale.getDefault()`; register an `ACTION_TIMEZONE_CHANGED` / `ACTION_LOCALE_CHANGED` receiver, or just re-check the stamp on every call as iOS does. |
| `dayDiff`'s `Double` division + `.rounded()` | **Easy** | `Math.round((a - b).toDouble() / D)`. Do **not** use integer division — it is wrong across DST. |
| `Locale.current.region?.identifier` → `AppRegion.current` | **Easy** | `Locale.getDefault().country`, same validation and `"US"` fallback. |
| `Int.max` / `Int64.max` sentinels (`progressCeiling`, `nextAiringSortKey`, `releaseSortKey` nil-last) | **Easy** | `Int.MAX_VALUE` / `Long.MAX_VALUE`. |
| Swift's **unstable** `sorted` vs Kotlin's **stable** `sortedBy` (`releasingPart`, `sections`, `watchingShelf`) | **Easy** | Behaviour differs only for equal keys, and Kotlin's is the better one. Note it if golden-file tests are shared. |
| `Dictionary(grouping:)` non-determinism (`sections`) | **Easy** | Kotlin's `groupBy` preserves encounter order; the subsequent `sortedBy(sortRank)` makes both deterministic anyway. |
| Value-type `snapshotForUndo` (whole-graph freeze by assignment) | **Easy** | Works iff every model is an immutable `data class` holding immutable `List`s. Use `kotlinx.collections.immutable` or defensive `toList()` at construction. |
| YouTube `embedURL` inside a neutral-base-URL WebView page | **Moderate** | Android `WebView.loadDataWithBaseURL(neutralBase, html, …)`. The same two failure modes apply (`"Video player configuration error"` for a bare embed URL, `"unavailable · 152-4"` for a youtube.com base). |
| `U+00B7` / `U+00A0` / en & em dash literals in copy | **Easy** | Preserve the exact code points in `strings.xml` (`·`, ` `). The NBSP in `Copy.plural` is a line-breaking rule, not decoration. |
| SF Symbol names leaking into model-adjacent copy (`"checkmark.circle.fill"` in `EmptyStateCopy`) | **Easy** | Not in these files' core types, but the copy layer carries symbol names. Map to Material Symbols at the presentation boundary; do not store SF names in shared models. |
| English-only `Copy.plural` | **Easy** | Deliberate scope decision. `plurals.xml` if you localise — keep the NBSP. |
