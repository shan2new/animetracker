# Copy & Temporal Expression — Android Port Specification

This document specifies the app's entire user-facing string catalogue and its two date/time engines.
In the iOS build **every** visible sentence resolves to a symbol in `Copy` (`Sources/DesignSystem/Copy.swift`
plus the `Copy+Library`, `Copy+Screens`, `Copy+Search` extensions); a screen either renders a `Copy`
symbol or renders interpolated data (a title, a numeral, a formatted date). Nothing is inlined, and the
table carries a self-audit (`Copy.auditProblems`) that fails on a straight apostrophe, an exclamation
mark, banned episode notation, or an ellipsis that promises a confirmation it does not open. `TemporalCopy`
(`Sources/Util/TemporalCopy.swift`) is the single owner of "when does this happen" phrasing — one temporal
expression per item, never two grammars for one fact — and `Formatting` (`Sources/Util/Formatting.swift`)
is the single owner of calendars, clocks and locale-correct date skeletons, built around a two-calendar
`TimeAnchor` that keeps date-only (TMDB) facts from ever growing a clock or sliding a day east of UTC+7.
An Android port that gets any of this subtly wrong will not read as the same product: the strings are
not decoration here, they are the state model rendered in words. Port the *implementation*, not the
doc comments — several doc comments in the Swift describe an intent the code does not quite reach, and
those divergences are flagged individually below.

---

## 0. Source-of-truth files

| Swift file | Contents |
|---|---|
| `ios/Sources/DesignSystem/Copy.swift` | Notation, status, labels, headings, actions, toasts, alerts, notices, progress, confirmations, session state, freshness ladder, accessibility strings, `EmptyStateCopy`, the audit, `Franchise.displayTitle` |
| `ios/Sources/DesignSystem/Copy+Library.swift` | `Copy.Library` — Library root, All titles, sort/filter vocabulary |
| `ios/Sources/DesignSystem/Copy+Screens.swift` | Extra `Copy.Action` verbs, `Copy.Recap`, `Copy.Rewatch`, `Copy.Account`, `Copy.Filter`, `Copy.Schedule`, `Copy.Video`, `Copy.People`, `Copy.Watch`, `Copy.Progress.next(context:)`, extra accessibility strings |
| `ios/Sources/DesignSystem/Copy+Search.swift` | `Copy.Search` + four search-specific `EmptyStateCopy` values |
| `ios/Sources/Util/TemporalCopy.swift` | `airs` / `airsCompact` / `aired` / `returns` / `premieres` / `since` / `dateWord` / `dateRange` |
| `ios/Sources/Util/Formatting.swift` | `TimeAnchor`, calendar + formatter caches, day maths, countdowns, clocks, date skeletons, greeting, HTML stripping |

Supporting definitions this spec depends on (specified elsewhere, quoted here for completeness):

| Symbol | File | Value |
|---|---|---|
| `MediaSource.timeAnchor` | `Models.swift:30` | `self == .tmdb ? .utcDate : .local` |
| `MediaSource.kindWord` | `Models+Shared.swift:177` | `.tmdb → "TV"`, `.anilist → "Anime"` |
| `Episode.airDateAnchor` | `Models.swift:99` | always `.utcDate` (episode air dates are date-only whatever the source) |
| `FranchisePart.canonicalLabel` | `Models+Shared.swift:21` | the source's own `label`, trimmed; **never derived from `sequence`**; `""` when unknown |
| `Franchise.displayTitle` | `Copy.swift:876` | `title.shelfShortened` (§19) |

---

## 1. Voice and typography — the non-negotiable rules

These are enforced (partly by the audit, partly by review) and are what make the product feel like one
voice. Encode them as lint/unit tests on the Android side too.

| # | Rule | Consequence if broken |
|---|---|---|
| V1 | **Sentence case for every heading, control label and sentence.** Title Case is reserved for the names of works. | "Sort & Filter" beside "Seasons & movies" was two conventions one screen apart. |
| V2 | **No exclamation marks anywhere.** Audited. | — |
| V3 | **Curly apostrophe U+2019 only.** A straight `'` fails the audit. | — |
| V4 | **One supporting sentence maximum** in a state; a state that needs two is two states. | — |
| V5 | **"Previously." always carries its full stop** and is **never a clause subject.** "Previously couldn't reach the server" parses as the adverb — it says the opposite. A failure states the bare fact: "Couldn't reach the server". | Two names for one failure. |
| V6 | **No screen substitutes its own subject** for a failure ("Search couldn't reach the server"). | One failure got two names one tab apart. |
| V7 | **No state promises a benefit on a different tab.** Each surface owns its own empty sentence, about itself. | "Add your first show and Today builds itself." ran verbatim on Library *and* Schedule. |
| V8 | **Episode notation is `Season 4 · Episode 19`.** Never `E19`, `Ep 19`, `Ep.19`, `S5 E19`. Audited by `hasBannedNotation` (§22). | — |
| V9 | **`Episode N` capitalised as a label/identifier; `episode N` lower-case inside a sentence-case command.** Exactly two builders: `episode(_:)` and `episodeInSentence(_:)`. Nothing else builds the string. | — |
| V10 | **"&" only between two nouns in a label that must hold one line.** The word "and" in any sentence the user reads. | — |
| V11 | **"Finished" is not in the vocabulary.** "Complete" belongs to the *series* (`Copy.Label.complete`, `Copy.Progress.complete`); "Watched" belongs to the *user* (`Copy.Status(.completed)`). | The app filed a show as finished on one screen and promised its return on the next; one state was spelled four ways within two taps. |
| V12 | **A command that opens a confirmation may end in `…`; a confirmation *button* never does.** Recorded as data, not inferred from the character (§6.6). | — |
| V13 | **Never say in words what a numeral beside them already says**, and never make the reason someone opened the app the smallest text on screen. | — |
| V14 | **One temporal expression per item** (§20.1). | Three renderings of "when it airs" shipped in one product. |
| V15 | **Statuses are the USER's list state, never the series' production state.** | — |

### 1.1 Unicode inventory (exact code points — copy these, do not "normalise")

| Code point | Char | Where it is used |
|---|---|---|
| U+2019 | `’` | Every apostrophe: "Couldn’t", "You’re", "That’s", "today’s" |
| U+00B7 | `·` | The fact separator: "Season 4 · Episode 19", "In progress · Episode 7 next", "Dates unknown · 26 episodes", Schedule's day header `"\(word) · \(detail)"` |
| U+00A0 | NBSP | Binds a numeral to its noun in `plural(_:_:_:)`, and again in `Progress.behind` / `Progress.left` |
| U+2060 | word joiner | Welds the batch range in `markThrough`: `1⁠–⁠5` |
| U+2013 | `–` | En dash in the batch range and every date range |
| U+2014 | `—` | Em dash only as an HTML-entity decode target and in `shelfShortened`'s separator list |
| U+2026 | `…` | Every ellipsis is the single character, never three dots |
| U+201C / U+201D | `“ ”` | Quoted query strings: `No results for “one pece”` |
| U+2018 / U+2019 | `‘ ’` | HTML-entity decode targets only |

> **Android note.** If these move into `strings.xml`: `&` must be escaped `&amp;` (affects `Sort & filter`,
> `Seasons & movies`, `Movies & extras`, `Cast & crew`, `Anime & TV`); `%` would need `%%` (no string
> currently contains one). Curly apostrophes need **no** escaping — which is precisely why the audit bans
> straight ones. `@` and `?` never lead a string here. Prefer a Kotlin `object Copy` mirroring the Swift
> structure over `strings.xml`, because ~40 % of the catalogue is parameterised by functions whose logic
> (pluralisation, the ellipsis table, the ladders) is behaviour, not a resource.

---

## 2. Notation primitives (`Copy`, top level)

| Swift | Signature | Output | Notes |
|---|---|---|---|
| `Copy.episode(_:)` | `(Int) -> String` | `"Episode 19"` | The **label** form. |
| `Copy.episodeInSentence(_:)` | `(Int) -> String` | `"episode 19"` | The form inside a sentence-case command/message. |
| `Copy.watchContext(part:episode:)` | `(String, Int) -> String` | `"Season 4 · Episode 19"`; `"Episode 19"` when the compacted label is empty | `compact = compactPartLabel(label)`; `compact.isEmpty ? episode(n) : "\(compact) · \(episode(n))"` |
| `Copy.compactPartLabel(_:)` | `(String) -> String` | `"Season 5: Hashira Training Arc"` → `"Season 5"`; anything else unchanged | Regex `^Season \d+(?=:)`. **Only a `Season N:` prefix compacts** — `"OVA 2: No Regrets"` keeps its subtitle because the subtitle *is* the identity there. Reason: a numbered season's arc subtitle wrapped every row it appeared on and stranded the `·` at the line end; the arc name is Detail's fact, not a row's. |
| `Copy.plural(_:_:_:)` | `(Int, String, String) -> String` | `"1\u{00A0}episode"`, `"3\u{00A0}episodes"` | English-only pluraliser; a `.stringsdict` is deliberately out of scope. **The NBSP is load-bearing**: a numeral must never end a line its unit doesn't start (measured on Today's queue rows: `… · 11 /` `episodes left`). Wraps happen between facts, never inside one. |
| `Copy.episodes(_:)` | `(Int) -> String` | `"24\u{00A0}episodes"` | |
| `Copy.episodesWatched(_:)` | `(Int) -> String` | `"26\u{00A0}episodes watched"` | Predicated so it cannot be read as the work's *length*. "Watched once · 95 episodes" (the show) and "2 watch sessions · 50 episodes" (the user) sat two taps apart. Catalogue counts stay bare; progress counts come through here. |
| `Copy.changes(_:)` | `(Int) -> String` | `"1\u{00A0}change"` / `"3\u{00A0}changes"` | |
| `Copy.watchSessions(_:)` | `(Int) -> String` | `"2\u{00A0}watch sessions"` | |
| `Copy.updates(_:)` | `(Int) -> String` | `"5\u{00A0}updates"` | |
| `Copy.titles(_:)` | `(Int) -> String` | `"40\u{00A0}titles"` | |
| `Copy.episodeNext(_:)` | `(Int) -> String` | `"Episode 19 next"` | Top-level alias for `Copy.Progress.episodeNext`. |

**Franchise-level watch context** (`Models+Shared.swift:155`) — the rule screens actually call:

```swift
func watchContext(part: FranchisePart, episode n: Int) -> String {
    if part.kind == .movie { return part.canonicalLabel }          // a movie has no episode to name
    return parts.count > 1 ? Copy.watchContext(part: part.canonicalLabel, episode: n)
                           : Copy.episode(n)                        // single-part show: no season prefix
}
```

`FranchisePart.watchContext(episode:)` (`Models+Shared.swift:31`) is the part-local sibling: movie → label;
empty label → `Episode N`; else `"\(label) · Episode N"`.

**Android:** implement `plural` by hand, exactly as written. Do **not** replace it with
`resources.getQuantityString` — the NBSP binding and the two-argument call shape are what guarantee
byte-identical output at every call site, and `getQuantityString` would silently drop the NBSP.

---

## 3. Statuses (`Copy.Status` / `Copy.statusLabel`)

`WatchStatus` wire values are `watching | completed | planned | paused | dropped`. `Copy.statusLabel`
switches on the **raw string**, not the case set, so a status the enum gains later still renders.

| Raw | Displayed |
|---|---|
| `watching` | `Watching` |
| `planned` | `Planned` |
| `completed` | `Watched` |
| `paused` | `Paused` |
| `dropped` | `Dropped` |
| anything else | first character upper-cased + remainder (`raw.prefix(1).uppercased() + raw.dropFirst()`) |

`Copy.statusesInOrder = ["Watching", "Planned", "Watched", "Paused", "Dropped"]` — the **display order of a
status menu**, independent of the enum's declaration order. Port it as an ordered list, not as
`WatchStatus.values()`.

"Completed" and "Plan to watch" never appear. `WatchStatus.displayName` (`Models+Shared.swift:172`) is the
only other entry point and forwards to `Copy.Status(_:)`.

---

## 4. Section eyebrows — the "next" vocabulary (`Copy.Label`)

Five "next" forms meaning three things once shipped simultaneously ("UP NEXT" / "COMING NEXT" 60 pt apart,
"NEXT UP", "Next up Sun 23 Aug", "Episode 5 next"). The rule, and the only permitted forms:

- `nextUp` — the specific episode watchable **right now**. At most one per screen.
- `upcoming` — episodes that exist but have not aired. Never a second "next" on a screen.
- `Progress.episodeNext(n)` — the only **postfix** form.

Nothing else may be worded with "next".

| Swift | String | Where |
|---|---|---|
| `Copy.Label.nextUp` | `Next up` | Today's queue section header |
| `Copy.Label.newEpisode` | `New episode` | Waiting hero's eyebrow; Today's shelf caption for `.newEpisode` state; the pill for a date-only (TMDB) waiting hero, which has no clock to make a headline of |
| `Copy.Label.trending` | `Trending` | The empty account's billboard pill (chart #1) |
| `Copy.Label.upcoming` | `Upcoming` | Today's "Upcoming" section header |
| `Copy.Label.airingSoon` | `Airing soon` | *No live call site in this build* |
| `Copy.Label.watching` | `Watching` | Today's Watching shelf header; Profile's Watching shelf header |
| `Copy.Label.complete` | `Complete` | Detail's series-complete / season-complete eyebrow. The **series'** production state — never the user's list state |
| `Copy.Label.adultRating` | `18+` | The identity line's word for a title the catalogue flags adult with no market rating |

---

## 5. Headings (`Copy.Heading`)

Stored in the case they are **written** in; `SectionLabel` uppercases at render time, which is what lets one
string serve a header and a menu item.

| Swift | String | Notes |
|---|---|---|
| `sortAndFilter` | `Sort & filter` | |
| `seasonsAndMovies` | `Seasons & movies` | |
| `moviesAndExtras` | `Movies & extras` | The shelf of a franchise's non-season parts under the episode list |
| `episodes` | `Episodes` | The Episodes section title when the work has one season and no name for it (`part.title.isEmpty ? Copy.Heading.episodes : part.title`) |
| `searchPrompt` | `Anime & TV` | *No live call site in this build* |
| `watchHistory` | `Watch history` | |
| `allTitles` | `All titles` | |
| `trailers` | `Trailers` | Detail catalogue shelf 1 |
| `castAndCrew` | `Cast & crew` | Detail catalogue shelf 2 |
| `moreLikeThis` | `More like this` | Detail catalogue shelf 3 |
| `whereToWatch` | `Where to watch` | Detail catalogue shelf 4; drawn only when `WatchAvailability.status == .available` — a section that says "not here" is not a section |

`PartKind.sectionTitle` (`Models.swift`) is a parallel, small heading set used by Detail's grouping:
`season → "Seasons"`, `movie → "Movies"`, `ova`/`ona` → `"OVAs"`, `special → "Specials"`, `music → "Music"`.

---

## 6. Actions (`Copy.Action`)

One form per intent. **A command that exists here must not be reworded at a call site, shortened to fit a
control, or given a second form for a narrow layout.**

### 6.1 Marking

| Swift | String / template |
|---|---|
| `markAsWatched` | `Mark as watched` |
| `markAsUnwatched` | `Mark as unwatched` (*no live call site*) |
| `markEpisodeWatched(n)` | `Mark episode 19 watched` — the CTA form that **names its object**. Bare `markAsWatched` stays for surfaces with no single episode to name; a control that KNOWS which episode it writes says so, because "Mark as watched" beside a hero showing a behind-count and a latest-aired date left the reader to work out which of three numbers the button touched. |
| `markThrough(from:to:)` | `from >= to` → `Mark episode 5 watched`; else `Mark episodes 1⁠–⁠5 watched` with **U+2060 word joiners either side of the U+2013**. A narrow menu line had broken it as `episodes 1–` / `5`, which reads as a typo. A batch command **states its range**: "Mark through episode 5" named only its endpoint, so under a hero saying "Episode 1 next · 9 behind" the 5 read as an unexplained third number. |
| `markAll(n)` | `Mark all 18 episodes as watched` (the count goes through `Copy.episodes`, so it carries the NBSP) |
| `allEpisodes(n)` | `All 24 episodes` — the link from Detail's six-row episode window to the whole season |
| `markAllEpisodes` | `Mark all episodes as watched` |
| `markAllUnwatched(n)` | `Mark all 24 episodes as unwatched…` |
| `markCaughtUp` | `Mark caught up` |

### 6.2 Rewatch

| Swift | String |
|---|---|
| `startRewatch` | `Start rewatch` |
| `continueRewatch` | `Continue rewatch` |
| `restartRewatch` | `Restart rewatch…` |
| `fromAnEpisode` | `From an episode…` (*no live call site*) |
| `markRewatchComplete` | `Mark this rewatch complete` |
| `stopRewatch` | `Stop this rewatch…` |
| `markSeriesWatched` | `Mark series as watched` |

### 6.3 Library / destructive

| Swift | String |
|---|---|
| `add` | `Add` |
| `addAShow` | `Add a show` |
| `removeFromLibrary` | `Remove from Library` |
| `deleteWatchHistory` | `Delete watch history…` |
| `deleteThisSession` | `Delete this session…` |
| `editSessions` | `Edit sessions` (*no live call site*) |

### 6.4 Navigation / disclosure

| Swift | String |
|---|---|
| `viewEpisodes` | `View episodes` |
| `viewWatchHistory` | `View watch history` |
| `viewAllUpdates(n)` | `View all 5 updates` — a **different destination** from a shelf's "See all": this one lands on the Library filtered to *Most left to watch* + *unwatched only*; "See all" stays on the unfiltered root |
| `browseYourLibrary` | `Browse your library` (only as `EmptyStateCopy.noWatching.primaryLabel`) |
| `seeAll` | `See all` — **only as an accessibility label / default action word.** Shelf headers draw no "See all" word: the title *is* the button, with a trailing chevron (Apple TV / Netflix grammar) |
| `details` | `Details` |
| `continueLabel` | `Continue` |

### 6.5 Chrome / small verbs

| Swift | String |
|---|---|
| `showTitle` | `Show title` |
| `hideTitle` | `Hide title` (*no live call site*) |
| `revealEpisodeTitle` | `Reveal episode title` |
| `hideEpisodeTitle` | `Hide episode title` |
| `revealEpisodeTitlesAndStills` | `Reveal episode titles and stills` |
| `dismissRecap` | `Dismiss what you missed` |
| `tryAgain` | `Try again` |
| `retry` | `Retry` |
| `retryAll` | `Retry all` |
| `clear` | `Clear` |
| `cancel` | `Cancel` |
| `done` | `Done` |
| `dismiss` | `Dismiss` |
| `undo` | `Undo` |
| `arrange` | `Arrange` |
| `reset` | `Reset` |
| `discard` | `Discard…` |
| `syncNow` | `Sync` (the word is "Sync", not "Sync now" — the row already says "Up to date / Checked just now"; "Everything synced / Just now / Sync now" said "sync" three times) |
| `openOnYouTube` | `Open on YouTube` — the trailer sheet's way out, drawn as a glyph; **this is what VoiceOver says** |
| `openInBrowser` | `Open in browser` |
| `signOut` | `Sign out` |
| `deleteAccount` | `Delete account` |
| `privacyPolicy` | `Privacy Policy` (Title Case — it is the name of a document) |
| `termsOfUse` | `Terms of Use` (same) |
| `contactSupport` | `Contact support` |

### 6.6 The ellipsis rule, as data

Board 09 states "commands that open a confirmation end in …", but its own action table omits the ellipsis
from the forward batch marks — which *do* confirm. **The table's concrete strings win**, so
`opensConfirmation` is recorded independently of the trailing character and the two are never inferred from
one another.

```swift
struct Command: Hashable, Sendable {
    let label: String
    let opensConfirmation: Bool
    var endsInEllipsis: Bool { label.hasSuffix("\u{2026}") }
}
```

| Command (representative argument) | `opensConfirmation` | ends in `…` |
|---|---|---|
| `Mark as watched` | false | no |
| `Mark as unwatched` | false | no |
| `Mark episode 19 watched` | false | no |
| `Mark episodes 6⁠–⁠10 watched` | **true** | no |
| `Mark all 18 episodes as watched` | **true** | no |
| `Mark all episodes as watched` | **true** | no |
| `Mark all 24 episodes as unwatched…` | **true** | **yes** |
| `Mark caught up` | false | no |
| `Start rewatch` | false | no |
| `Continue rewatch` | false | no |
| `Restart rewatch…` | **true** | **yes** |
| `From an episode…` | **true** | **yes** |
| `Add` | false | no |
| `Remove from Library` | false | no (removal is immediate with Undo) |
| `Delete watch history…` | **true** | **yes** |
| `Delete this session…` | **true** | **yes** |
| `View episodes` | false | no |
| `View watch history` | false | no |
| `Show title` | false | no |
| `Hide title` | false | no |
| `Try again` | false | no |
| `Retry` | false | no |
| `Clear` | false | no |
| `Discard…` | **true** | **yes** |

- `Action.opensConfirmation(label)` — exact-label lookup; **unknown labels answer `false`** ("an unknown
  label is a copy defect, not a silent confirmation").
- `Action.ellipsisViolations` — commands that end in `…` but open no confirmation. Must be empty.
- `Action.confirmationButtonViolations` — `Confirm.buttons` entries ending in `…`. Must be empty.

---

## 7. Toasts (`Copy.Toast`)

Presented by `UndoState.message` (`UndoToast.swift:24`) in this precedence:
`customMessage` → `removed` → `added` → `count > 1` → single mark.

| Swift | Output |
|---|---|
| `marked(episode: 19)` | `Episode 19 marked as watched` |
| `batchMarked(3)` | `3\u{00A0}episodes marked as watched` |
| `marked(title:episode:)` | `title.isEmpty` → `marked(episode:)`; else `Re:ZERO · Episode 19 watched` |
| `batchMarked(title:_:)` | `title.isEmpty` → `batchMarked(n)`; else `Re:ZERO · 3\u{00A0}episodes watched` |
| `removed` | `Removed from Library. Watch history kept.` |
| `added(title:status:)` | `Added One Piece to Watching` (status defaults to `"Library"` when the caller has none) |
| `movedTo(_:)` | `Moved to Watched` — shown **only where the row leaves the screen** as a result (Library) |
| `rewatchStarted` | `Rewatch started` |
| `rewatchRestarted` | `Rewatch restarted` |
| `alertsOn` | `Episode alerts on` (a neutral receipt with no action — `showNotice`, not an Undo toast) |
| `offlinePending` | `Saved on this device. Waiting to sync.` |
| `syncFailed(n)` | `1\u{00A0}change couldn’t sync` / `3\u{00A0}changes couldn’t sync` — **the SyncBanner's line. A failure is never a transient toast.** |

**Why the subject-carrying forms exist:** the identical toast fires from a Schedule row and a Library
context menu, where the user has just acted on one of several shows and "Episode 2 marked as watched"
cannot say which. **The title is the part allowed to truncate; the fact never is.**

---

## 8. System notifications (`Copy.Alert`)

The one sentence the app ever pushes. **No full stop — Apple's own alerts carry none.**

```swift
static func episodeOut(_ n: Int?) -> String {
    n.map { "\(Copy.episode($0)) is out now" } ?? "A new episode is out now"
}
```

- `Episode 19 is out now` / `A new episode is out now`.
- The notification **title** is the show's title (`airing.title`), the **body** is this string
  (`EpisodeNotifications.swift:108`).
- `threadIdentifier` = franchise id, so repeat alerts group per show.
- Alerts are only scheduled for `source == .anilist` shows with status `watching` — TMDB air dates are
  date-only 17:00-UTC synthetics and would fire at the wrong minute.

---

## 9. Inline notices and error reasons (`Copy.Notice`)

**Noun-first: the thing that failed, then what happened to it.** Rendered by `InlineNotice` — a footnote
line (glyph + metadata text + a "Retry" link), never an alert box.

### 9.1 Per-surface refresh failures

| Swift | String | Surface |
|---|---|---|
| `today` | `Airing dates couldn’t refresh` | Today (`TodayView:935`) |
| `schedule` | `The schedule couldn’t refresh` | Schedule (`ScheduleView:665`) |
| `library` | `Your library couldn’t refresh` | Library root and All titles (`LibraryView:99`, `:770`) |
| `detailEpisodes` | `Episodes couldn’t refresh` | Detail (`FranchiseDetailView:257`) |
| `searchAnime` | `Anime results couldn’t refresh` | Search, when `/search` reports `sources["anilist"] == "failed"` **and** the current scope can show anime |
| `searchTV` | `TV results couldn’t refresh` | same, for TMDB |
| `Copy.Search.couldNotRefresh` | `Results couldn’t refresh` | Search, the "both sources, one request" case the per-catalogue lines do not name |

### 9.2 Reason vocabulary

| Swift | String |
|---|---|
| `noConnection` | `No connection` |
| `serverError` | `Something went wrong` |
| `signedOut` | `Signed out` |
| `timedOut` | `Took too long` |
| `rateLimited` | `Try again in a minute` |
| `notInCatalogue` | `Not in the catalogue yet` — a related title the catalogue has not materialised and a search could not find |

### 9.3 `Copy.Notice.reason(_ error:) -> String`

The reason a **write** failed, in the user's words. Never a status code, never a raw
`localizedDescription`. Sync status shows this beside each failed command.

```
if error is APIError:
    .unauthorized       -> signedOut
    .http(code, _)      -> code == 429 ? rateLimited : serverError
    .transport(under)   -> transportReason(under)
    default             -> serverError          // .invalidURL, .infrastructure, .rateLimited, .decoding
else                    -> transportReason(error)
```

`transportReason(error)`:

```
if (error as NSError).domain != NSURLErrorDomain -> serverError
switch code:
  NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost,
  NSURLErrorDataNotAllowed, NSURLErrorCannotConnectToHost,
  NSURLErrorCannotFindHost, NSURLErrorInternationalRoamingOff  -> noConnection
  NSURLErrorTimedOut                                            -> timedOut
  default                                                        -> serverError
```

> **Note the deliberate asymmetry:** `APIError.rateLimited` (a 429 that outlived the retry budget) maps to
> `serverError` via the `default` branch, while `APIError.http(429, _)` maps to `rateLimited`. That is what
> the code does; reproduce it rather than "fixing" it, or the Sync list changes wording for the same
> user-visible failure.

**Android mapping for `transportReason`** (OkHttp / `java.net`):

| iOS condition | Android equivalent |
|---|---|
| `NSURLErrorNotConnectedToInternet`, `NetworkConnectionLost`, `DataNotAllowed`, `CannotConnectToHost`, `CannotFindHost`, `InternationalRoamingOff` | `UnknownHostException`, `ConnectException`, `NoRouteToHostException`, `SSLException` caused by a dead network, or `ConnectivityManager` reporting no validated network |
| `NSURLErrorTimedOut` | `SocketTimeoutException`, `InterruptedIOException` with a timeout cause |
| everything else | `serverError` |

### 9.4 `APIError.failureReason` (parallel, shorter ladder used by the Sync-status row)

| Case | String |
|---|---|
| `.unauthorized` | `Signed out` |
| `.rateLimited` | `Rate limited` |
| `.transport` where `URLError.code == .timedOut` | `Timed out` |
| `.transport` otherwise | `No connection` |
| `.infrastructure`, `.http`, `.decoding`, `.invalidURL` | `Server error` |

`APIError.errorDescription` (`localizedDescription`): `.unauthorized` → `You’re signed out. Sign in again to
continue.`; every other case → `failureReason`. **No status code or MIME type may ever reach this string** —
the technical detail lives in `diagnostic`, which only the logger reads.

Profile substitutes once at render: a change whose `reason == Copy.Notice.serverError` displays
`Copy.Account.couldNotReachServer` (`Couldn’t connect`) instead (`ProfileView:589`).

---

## 10. Progress text (`Copy.Progress`) — passive, never an action

| Swift | Output | When |
|---|---|---|
| `watchedOf(w, t)` | `18 of 24 watched` | Grouped list rows and the reset confirmation. **Never on a hero or a media row** — where-you-are there is a `ProgressBar`, not words |
| `episodeNext(n)` | `Episode 19 next` | The single most reused progress line |
| `next(context:)` | `Season 4 · Episode 5 next` | The postfix "next" over a full watch context. The only sibling `episodeNext` is allowed |
| `episodeWatched(n)` | `Episode 19 watched` | The committed state of the mark control (`MarkSplitButton`, four surfaces) |
| `episodeAiring(n)` | `Episode 19 airing` | |
| `behind(n)` | `3\u{00A0}episodes\u{00A0}behind` (double NBSP — the whole phrase is unbreakable) | |
| `left(n)` | `6\u{00A0}episodes\u{00A0}left` | |
| `caughtUp` | `Caught up` | |
| `newEpisodeToday` | `New episode today` | The calm open's headline when the next episode lands **today** — "the day is not nothing", and "Caught up" printed over an Upcoming row saying "Today at 8:30 PM" was the state shouting over the day's real fact |
| `newEpisode(when:)` | see below | Detail's state block; the airing cadence |
| `caughtUpAfterThisEpisode` | `Caught up after this episode` | |
| `noNewDates` | `No new dates have been announced.` | Variant B of the calm day. Shared with `EmptyStateCopy.calmToday` so the sentence exists once |
| `lastEpisodeOfTheSeason` | `Last episode of the season` | |
| `complete(label)` | `label.isEmpty ? "Complete" : "Season 4 complete"` | |
| `datesUnknown` | `Dates unknown` | |
| `watchedTimes(n)` | `n < 1` → `Not watched yet`; `1` → `Watched once`; `2` → `Watched twice`; else `Watched 4 times` | |
| `ordinalWatch(n)` | `1…10` → `First watch` … `Tenth watch`; else `11th watch` etc. | Words table: `["", "First","Second","Third","Fourth","Fifth","Sixth","Seventh","Eighth","Ninth","Tenth"]` |
| `inProgress(nextEpisode:)` | `In progress · Episode 7 next` | The active session's subtitle |
| `sessionSpan(...)` | see below | A completed session's subtitle |

### 10.1 `newEpisode(when:)` — the airing cadence

```swift
static func newEpisode(when: String) -> String {
    let lowered = ["Today", "Tomorrow", "Airs", "In "].contains { when.hasPrefix($0) }
    return "New episode \(lowered ? when.lowercasedFirst() : when)"
}
```

Produces `New episode Friday at 7:30 PM` · `New episode today at 6:30 PM` · `New episode airs in 27 min`.
Only the four listed prefixes are re-cased (they are ordinary adverbs/verbs); `Friday`, `Sep 12`, `Aug 28,
2027` are proper nouns and keep their capital. `lowercasedFirst()` lower-cases **only the first character**.

> **"New", not "next":** on a show nine episodes behind, "next episode" is the one *you* watch next, and the
> reader would take the day for its air date. Said the way Netflix says it ("New episode coming on Saturday").

### 10.2 `ordinalSuffix(_ n: Int)`

`tens = n % 100`; if `11...13` → `th`; else by `n % 10`: `1 → st`, `2 → nd`, `3 → rd`, default `th`.

### 10.3 `sessionSpan(started:completed:episodes:now:)`

```
count = Copy.episodes(episodes)
if completed == nil                       -> "Dates unknown · {count}"
end = TemporalCopy.dateWord(completed, now, .local)
if started == nil || started >= completed -> "{end} · {count}"
sameYear = localParts(started).y == localParts(completed).y
start = sameYear ? Formatting.fmtMonthDay(started)
                 : TemporalCopy.dateWord(started, now, .local)
                                          -> "{start} – {end} · {count}"     // U+2013, spaces both sides
```

Example: `Jul 4 – Jul 19 · 26\u{00A0}episodes`. The separator before the count is U+00B7 with spaces.

---

## 11. Confirmations (`Copy.Confirm`) — every one states its exact blast radius

| Slot | String |
|---|---|
| `cancel` | `Cancel` |
| **Batch mark** title | `Mark 18\u{00A0}episodes as watched?` |
| message | `Your progress will move from episode 1122 to episode 1140.` (lower-case `episode`, `episodeInSentence`) |
| confirm button | `Mark 18\u{00A0}episodes as watched` |
| **Reset a season** title | `Mark 24\u{00A0}episodes as unwatched?` |
| message | `This sets Season 4 back to 0 of 24 watched. Your watch history is kept.` |
| confirm button | `Mark 24\u{00A0}episodes as unwatched` |
| **Restart rewatch** title | `Restart rewatch?` |
| message | `Restarting discards 6\u{00A0}episodes of progress in this run. Earlier watches are kept.` |
| confirm button | `Restart rewatch` |
| **Delete one session** title | `Delete this session?` |
| message | `This permanently removes 26\u{00A0}episodes from your history. Your other sessions are unchanged.` |
| confirm button | `Delete this session` |
| **Delete history** title | `Delete watch history?` |
| message | `This permanently removes 2\u{00A0}watch sessions covering 59\u{00A0}episodes.` |
| confirm button | `Delete watch history` |
| **Discard a failed change** title | `Discard this change?` |
| message | `It stays on this device and is never saved to your account.` |
| confirm button | `Discard change` |

`Confirm.buttons` = `[batchMarkConfirm(18), resetSeasonConfirm(24), restartRewatchConfirm, deleteSessionConfirm, deleteHistoryConfirm, discardChangeConfirm, cancel]` — the audited set; **none may end in an ellipsis**.

Plural forms of the discard confirmation live in `Copy.Account` (§14.3).

---

## 12. Session / account state (`Copy.State`)

| Swift | String |
|---|---|
| `signedOut` | `You’re signed out. Sign in again to continue.` |
| `checkingForChanges` | `Checking for changes` |
| `couldNotCheck` | `Couldn’t check for changes` |
| `everythingSynced` | `Everything synced` |
| `on` | `On` |
| `off` | `Off` |
| `neverSynced` | `Not synced yet` |

### 12.1 `SyncCenter.syncedLine(now:)` — precedence

```
failedChanges non-empty -> Copy.Toast.syncFailed(count)
checking                -> Copy.State.checkingForChanges
lastSyncedAt == nil     -> isOnline ? Copy.State.neverSynced : Copy.State.couldNotCheck
else                    -> Copy.synced(at: lastSyncedAt, now:)
```

### 12.2 Profile's account row — a **different**, three-slot precedence (`ProfileView.syncTitle`)

**Offline is tested first.** The shipped order tested `checking` first, so a device whose network monitor
had already reported no path still watched "Checking for changes" spin until the request timed out, and
nothing on screen ever said the user was offline.

| Order | Condition | Title | Stamp line (`syncStamp`) | Glyph |
|---|---|---|---|---|
| 1 | `failedChanges` non-empty | `Copy.Toast.syncFailed(n)` | `nil` (a stamp of the last successful check under "1 change couldn't sync" is a contradiction) | `exclamationmark.triangle.fill` |
| 2 | `!isOnline` | `You’re offline` (`EmptyStateCopy.offlineCached.title`) | `Changes sync when you reconnect` | `wifi.slash` |
| 3 | `checking` | `Checking for changes` | `nil` | *none — a spinner* |
| 4 | `lastSyncedAt == nil` and snapshot empty | `Not synced yet` | `nil` | `arrow.triangle.2.circlepath` |
| 5 | `lastSyncedAt == nil` and snapshot non-empty | `Couldn’t check for changes` | `Showing the copy saved on this device` | `wifi.exclamationmark` |
| 6 | otherwise | `Up to date` (`Copy.Account.upToDate`) | `Checked {stampWord.lowercasedFirstWord()}` | `checkmark` |

`stampWord(ts)` — the same ladder as `Copy.synced` **without the verb the title already carries**:

| Condition | Output |
|---|---|
| `minutes < 1` | `Just now` |
| `minutes < 60` | `12 min ago` |
| `dayDiff(ts, now) == 0` | `Formatting.fmtTime(ts)` → `9:41 AM` / `21:41` |
| otherwise | `TemporalCopy.dateWord(ts, now, .local)` → `Aug 19` / `Aug 19, 2025` |

so slot 6 reads `Checked just now` / `Checked 12 min ago` / `Checked 9:41 AM` / `Checked Aug 19`.
`lowercasedFirstWord()` lower-cases only the first character.

> **The three-word rule:** `Up to date` / `Checked just now` / `Sync` — three slots, three words, one fact
> stated once. "Everything synced / Just now / Sync now" said "sync" three times.

---

## 13. Freshness ladder (`Copy.updated`, `Copy.synced`, `Copy.updatedSpokenLabel`)

**One elapsed ladder rendered under two verbs.** `elapsedWord` is private; the two public functions prefix
it. Elapsed time only, so a date-only source can never produce a clock here.

```swift
private static func elapsedWord(at ts: Int64, now: Int64) -> String {
    let elapsed = max(0, now - ts)
    let minutes = Int(elapsed / Formatting.minuteMs)
    if minutes < 1 { return "just now" }
    if minutes < 60 { return "\(minutes) min ago" }
    switch Formatting.dayDiff(ts: ts, now: now) {
    case 0:        return "\(Int(elapsed / Formatting.H))h ago"
    case -1:       return "yesterday"
    case -6 ... -2: return Formatting.weekdayNameMonFirst(Formatting.localMondayCol(ts))
    default:       return TemporalCopy.dateWord(ts, now: now, anchor: .local)
    }
}
```

| Elapsed | `Copy.updated` | `Copy.synced` |
|---|---|---|
| `< 1 min` | `Updated just now` | `Synced just now` |
| `1–59 min` | `Updated 8 min ago` | `Synced 2 min ago` |
| same calendar day, `≥ 60 min` | `Updated 8h ago` | `Synced 8h ago` |
| yesterday | `Updated yesterday` | `Synced yesterday` |
| 2–6 days ago | `Updated Wednesday` (**full weekday name**) | `Synced Wednesday` |
| older | `Updated Aug 19` / `Updated Aug 19, 2025` | same |

> **Why the weekday is fetched directly here:** `Formatting.fmtDayLong` only names weekdays in the
> **future**; the past falls through to a month-day. This ladder needs the name, so it calls
> `weekdayNameMonFirst(localMondayCol(ts))` itself. Quoted from the source: *"`fmtDayLong` only names
> weekdays in the FUTURE; the past needs the name directly."*

### 13.1 VoiceOver variant — `updatedSpokenLabel(at:now:)`

The elapsed time is **spelled out**: "Updated 8 hours ago", never "8h".

| Condition | Output |
|---|---|
| `minutes < 1` | `Updated just now` |
| `minutes < 60` | `Updated 8\u{00A0}minutes ago` (via `plural`, so it carries the NBSP; `1\u{00A0}minute`) |
| `dayDiff == 0` | `Updated 8\u{00A0}hours ago` (`plural(Int(elapsed / H), "hour", "hours")`) |
| otherwise | `Copy.updated(at:now:)` verbatim |

`StaleStrip` renders `Copy.updated` visually and sets `accessibilityLabel = Copy.updatedSpokenLabel`.
It is **passive by decision** — pull-to-refresh is the refresh affordance, so no tap target, no ground,
no stroke, 28 pt minimum height, wraps at accessibility sizes rather than truncating.

Staleness thresholds that decide whether the strip appears at all (`SyncCenter.DataClass.threshold`):
**30 min** for exact airings, **6 h** for date-only, **24 h** for catalogue data.

---

## 14. Screen-scoped copy

### 14.1 `Copy.Recap`

| Swift | Output |
|---|---|
| `whileYouWereAway` | `While you were away` |
| `sinceYourLastVisit(phrase)` | Strips a leading `"Since "` from the phrase, then `Since your last visit, {tail}` → `Since your last visit, 23 Jul`. The window always names its anchor |

The recap **strip** (the collapsed one-line form) is built in `TodayView.recapStripText`:
- `aired > 0` → `"{Copy.episodes(aired)} aired {sinceFragment}"` → `3\u{00A0}episodes aired since 23 Jul`
- else → `"{Copy.updates(beats + hidden)} {sinceFragment}"` → `5\u{00A0}updates since 23 Jul`

`sinceFragment(ts)` = `"since " + everything after the first space of TemporalCopy.since(ts, now)`; if the
phrase has no space, the whole thing is lower-cased. **Only the leading word is re-cased** — lower-casing
the whole phrase produced "1 episode aired since 23 **jul**", and a month abbreviation is a proper noun.

### 14.2 `Copy.Rewatch`

`everything` = `Everything` — the scope covering the whole work (not "All seasons" over a list of OVAs).

### 14.3 `Copy.Account`

| Swift | String |
|---|---|
| `signOutTitle` | `Sign out?` |
| `deleteSubtitle` | `Erases your library, progress and history` |
| `deleteTitle` | `Delete your account?` |
| `deleteConfirm` | `Delete account` |
| `deleteFailedTitle` | `Couldn’t delete your account` |
| `upToDate` | `Up to date` |
| `couldNotReachServer` | `Couldn’t connect` |
| `offlineSupporting` | `Changes sync when you reconnect` |
| `showingSavedCopy` | `Showing the copy saved on this device` |
| `signedInWithClerk` | `Signed in` |
| `signOutFailedTitle` | `Couldn’t sign out` |
| `signOutFailedMessage` | `Check your connection and try again.` |
| `discardChangesTitle(n)` | `Discard 3\u{00A0}changes?` |
| `discardChangesMessage` | `They were never saved to your account. Your library here stays as it is.` |
| `discardChangesConfirm(n)` | `Discard 3\u{00A0}changes` |

Export sheet strings live locally in `ProfileView.AccountCopy` (they are the one block not yet hoisted):
`Export library` / `Every title with progress and status` / `JSON` / `Every field, machine-readable` /
`CSV` / `One row per title, for spreadsheets` / footnote `A copy is created on this device and handed to
whatever you share it with. Nothing leaves your account until you choose a destination.`
> **Not "for re-import".** There is no import path in this build, and the export screen is the one place a
> worried user reads — a false claim there is worse than a missing feature.

### 14.4 `Copy.Filter` — shared by Schedule's menu, its chips and Library's Arrange sheet

One phrasing per filter: the same toggle used to read "Hide watched episodes" in the menu, "Watched hidden"
on the chip and "watched episodes hidden" to VoiceOver.

| Swift | String |
|---|---|
| `filter` | `Filter` |
| `off` | `Off` |
| `source` | `Source` |
| `all` | `All` |
| `anime` | `Anime` |
| `tv` | `TV` |
| `hideWatched` | `Hide watched` |

### 14.5 `Copy.Schedule`

| Swift | String / template | Notes |
|---|---|---|
| `title` | `Schedule` | |
| `today` | `Today` | The bar's return control. **Today's section is always in the feed**, empty or not, so "Today" always means day 0 |
| `tomorrow` | `Tomorrow` | |
| `scrollToToday` | `Scroll to today` | |
| `scrollToTodayHint` | `Scrolls to today’s episodes` | |
| `ticker` | `Days` | Accessibility label of the day strip |
| `selected` | `Selected` | |
| `noEpisodes` | `No episodes` | |
| `earlier` | `Earlier` | The collapsed block of aired days above today |
| `showEarlier` | `Show earlier episodes` | |
| `hideEarlier` | `Hide earlier episodes` | |
| `nothingScheduled` | `Nothing scheduled` | A day in the feed with nothing on it — in practice only today |
| `reminderSet` | `reminder set` | Lower case: it is appended inside a spoken label |
| `everythingThrough(date)` | `That’s everything through Sep 25` | Feed tail; falls back to `EmptyStateCopy.nothingScheduled.title` when there is no horizon |
| `toWatch(n)` | `3 to watch` | The unwatched count in the Earlier block's value line. **Note: no NBSP, no plural function** — it is a bare `"\(n) to watch"` |

**Day header format** (`ScheduleView.dayHeader`), rendered as an eyebrow (small caps, uppercased at draw time):

```
word   = day 0 -> "Today"; day 1 -> "Tomorrow"; else weekdayNameMonFirst(localMondayCol(noon))
date   = Formatting.fmtMonthDay(day.noon)                   // "3 Sep" / "Sep 3", locale-ordered
detail = (day 0 or day 1) ? "{weekdayShortMonFirst} {date}" : date
text   = "{word} · {detail}"
```

→ `TODAY · THU 3 SEP`, `TOMORROW · FRI 4 SEP`, `FRIDAY · 11 SEP`. Today's word is amber (today is STATE);
the date beside it is one step quieter. **No ground behind the header** — an opaque plate cuts a hard step
across the root wash.

Header count slot: `day.isEmpty && !accessibilitySize` → `Nothing scheduled`; `day.count > 1` →
`Copy.episodes(count)`; otherwise nothing ("1 episode" over a single card restates the card).
Spoken label: `"{text}, {day.isEmpty ? "Nothing scheduled" : Copy.episodes(count)}"` — **"0 episodes" is a
count, not a state**, so VoiceOver and the screen say the same words.

Ticker cell top line: on the **1st of a month** it names the month (the non-numeric component of
`fmtMonthDay`, upper-cased) because numerals alone cannot say that "2" comes after "31"; otherwise the
locale's one-letter standalone weekday (`weekdayLetterMonFirst`).

### 14.6 `Copy.Video.kind(_:)`

| `FranchiseVideo.Kind` | String |
|---|---|
| `trailer` | `Trailer` |
| `teaser` | `Teaser` |
| `announcement` | `Announcement` |
| `featurette` | `Featurette` |
| `clip` | `Clip` |
| `other` | `Video` |

### 14.7 `Copy.People`

`creator` = `Creator`, `director` = `Director` — role words for people the catalogue lists without one.

### 14.8 `Copy.Watch`

| Swift | String |
|---|---|
| `access(.subscription)` | `Subscription` |
| `access(.free)` | `Free` |
| `access(.ads)` | `Free with ads` |
| `attribution(provider)` | `Streaming availability by JustWatch` |

The providers' marks carry the names; these strings are for VoiceOver and for the attribution the
provider data requires.

---

## 15. Library copy (`Copy.Library`)

| Swift | String / template | Notes |
|---|---|---|
| `title` | `Library` | |
| `continueWatching` | `Continue watching` | The Up Next shelf's header |
| `returning` | `Returning` | The anticipation shelf |
| `announced` | `Announced` | A sequel exists and nobody has said when. The absence of a date is the content |
| `rumored(next:)` | `next` empty/nil → `Rumored`; else `Season 3 rumored` | **Never a date, never amber.** An unconfirmed report said as one |
| `allTitlesHint` | `Opens your whole library, with search, sorting and filters` | |
| `allTitlesCount(n)` | `All 40` (bare integer, **no** `plural`) | |
| `allTitlesAccessibility(n)` | `All titles, 40\u{00A0}titles` | |
| `searchPrompt` | `Search your library` | |
| `focusTitleHint` | `Shows this title in the centre` | |
| `partProgress(label:watched:total:)` | `label.isEmpty ? "18 of 24 watched" : "Season 4 · 18 of 24 watched"` | |
| `sortBy` | `Sort by` | |
| `reverseOrder` | `Reverse order` | |
| `status` | `Status` | |
| `anyStatus` | `Any` | The Status picker's "no filter" value. **A chip never states it** — "Any" is not a criterion |
| `hasUnwatched` | `Has unwatched episodes` | Says unwatched *what* — the identical word on Schedule's menu means episodes |
| `view` | `View` |  |
| `viewAs` | `View as` | |
| `reversed(label)` | `Recently added, reversed` | The chip names the direction, or it is lying |
| `sortTitle` | `Title` | |
| `sortAdded` | `Recently added` | |
| `sortRecent` | `Recently updated` | |
| `sortProgress` | `Most left to watch` | |
| `reversedTitle` | `Z to A` | The direction in the reader's terms, never "ascending" |
| `reversedAdded` | `Oldest first` | |
| `reversedRecent` | `Least recent first` | |
| `reversedProgress` | `Least left to watch first` | |
| `posters` | `Posters` | |
| `list` | `List` | |
| `noDate` | `No date` | Month header for titles with no date behind the active sort |
| `sectionIndex` | `Section index` | |
| `sectionIndexHint` | `Jumps the list to a section` | |
| `sectionsRotor` | `Sections` | VoiceOver rotor name |
| `noSearchResults(query:filtered:)` | `EmptyStateCopy.noSearchResults(query:)`, plus `primaryLabel = Clear` when filters are also narrowing the list | Without the action, a query under a "Watched" chip dead-ended with no way out but the chip row |

"View all" is gone: section actions say `See all` everywhere — one verb for one gesture.

### 15.1 The Returning caption (`ReturnFact`, `LibraryFacts.swift`) — one grammar

The Library's forward-looking caption has exactly one grammar: **`TemporalCopy.returns`'s verb followed by
the date word at its own precision.** ("Returns in 2027" beside "Returns Jan 2027" was two forms of one
fact six rows apart, and the preposition was the only visible difference.) Resolution order:

1. A dated premiere among the parts (`appModel.nextPremiere`) → `TemporalCopy.returns(at:now:source:)`, `dated = true`.
2. `upcoming.isRumored` → `Copy.Library.rumored(next:)`, `dated = false`, `soon = false`.
3. No usable release window → `TemporalCopy.returns(at: nil, …)` = `No date announced`, `dated = false`.
4. Day precision **inside the current year** → the friendly form (`Returns tomorrow` / `Returns Saturday` /
   `Returns Oct 2`), which is also always the shortest.
5. Any other day-or-month precision → month-and-year: `Returns Oct 2026`. ("Oct 2, 2027" does not fit a
   124-pt caption, and a day nine months out is not a fact anybody acts on.)
6. A quarter/year window → the **server's own prose**, first character lower-cased:
   `Returns summer 2027`, `Returns late 2026`, `Returns 2027` (a bare 4-digit year passes through
   un-lowered). Prose longer than 20 characters degrades to `Returns {year}`. **A window is never `soon`** —
   with no instant behind it there is nothing for the colour rule to measure.

`soon` (the one flag that decides amber, on both the shelf and the catalogue panel) =
`premiereInstant - now <= 60 * 86_400 * 1000` (**60 days in milliseconds**). `dated == false` is the one
caption that must never be amber, and it also keeps a show out of a section headed RETURNING.

Rule quoted from the source: **"Board 09's rule is to drop a fact, never to truncate one."**

---

## 16. Search copy (`Copy.Search`)

| Swift | String / template | Notes |
|---|---|---|
| `title` | `Search` | |
| `promptAll` | `Search anime and TV` | The prompt names the **verb**, not the domain, and it follows the scope |
| `promptAnime` | `Search anime` | |
| `promptTV` | `Search TV` | |
| `prompt(for:)` | `.anime → promptAnime`, `.tv → promptTV`, `.all → promptAll` | |
| `scopeWord(for:)` | `.anime → "Anime"`, `.tv → "TV"`, `.all → "All"` (via `Copy.Filter`) | |
| `recent` | `Recent` | |
| `recentlySearched` | `Recently searched` | |
| `termKind` | `Search` | The type line under a bare recent term — what the row IS, the way a media row says "Anime · 2021" |
| `termHint` | `Searches for it again` | |
| `trendingNow` | `Trending now` | Also Today's empty-account chart shelf header |
| `moreTrending` | `More trending` | |
| `topMatch` | `Top match` | *No live call site* — results are `MediaRow`s only, no top-match card |
| `moreResults` | `More results` | *No live call site* |
| `results(n)` | `1\u{00A0}result` / `12\u{00A0}results` | |
| `seasons(n)` | `1\u{00A0}season` / `4\u{00A0}seasons` | |
| `rank(n)` | `String(format: "%02d", n)` → `01`, `07`, `12` | A chart position, two digits, as the shelf caption leads with it |
| `showingResultsFor(corrected)` | `Showing results for “one piece”` | U+201C / U+201D |
| `searchInsteadFor(original)` | `Search instead for “one pece”` | |
| `couldNotRefresh` | `Results couldn’t refresh` | |
| `airingNow` | `Airing now` | |
| `newEpisode(day:)` | `New episode Friday` | Search owns its own two forward-looking forms; recorded in the source as a duplicate to fold with Today's private literals |
| `inLibrary` | `In library` | |
| `notInLibrary` | `Not in library` | |
| `addHint` | `Adds it to your library` | |
| `ownedHint` | `Change its status or remove it` | |
| `addToLibrary` | `Add to Library` | The long-press item behind an unowned control — the same verb the tap performs. Also the empty-account billboard's capsule on Today |
| `removeRecent` | `Remove` | |
| `showAll` | `Show all` | |
| `primerTitle` | `Episode alerts` | |
| `primerBody` | `Know the moment a new episode airs.` | |
| `primerTurnOn` | `Turn on` | |
| `primerNotNow` | `Not now` | **Not "No thanks"**: iOS raises its own alert once ever, so the honest offer is a deferral — and Profile → Notifications keeps it available for good |

**Results-summary accessibility string** (`DiscoverView:378`): scoped-out → `scopedOutCopy.title`; empty →
error title or `noSearchResults(query:).title`; otherwise
`[Copy.Search.results(n)] + [couldNotRefresh if searchError] + catalogueNotices`, joined with `". "`.

---

## 17. Empty states (`EmptyStateCopy`)

Copy as **data**, not a view, so the same values drive the card, the VoiceOver label and the audit.

```swift
struct EmptyStateCopy: Equatable, Sendable {
    let symbol: String?          // SF Symbol name; nil where the state has no glyph
    let title: String
    let supporting: String?
    let primaryLabel: String?
    let secondaryLabel: String?
    var isRecovery: Bool { primaryLabel == Copy.Action.tryAgain || primaryLabel == Copy.Action.retry }
    var spokenLabel: String { supporting.map { "\(title). \($0)" } ?? title }
}
```

`isRecovery` decides the button's *treatment*, not its position: a recovery ("Try again" / "Retry") is the
**quiet capsule**; a next step ("Add a show", "Clear", "Show all", "Browse your library") is the **amber**
one. `EmptyState` renders `ContentUnavailableView`'s anatomy on the plain canvas — a 44-pt tertiary symbol,
a title, one sentence, **one hugging button** — no plate, no glyph tile, no bloom.

### 17.1 The full table

| Value | `symbol` (SF) | `title` | `supporting` | `primaryLabel` |
|---|---|---|---|---|
| `emptyAccount` | `rectangle.stack` | `Your library is empty` | `Everything you add shows up here.` | `Add a show` |
| `emptyToday` | `tv` | `Nothing to watch yet` | `Add a show and this screen fills in with what is next.` | `Add a show` |
| `emptySchedule` | `calendar` | `Nothing scheduled` | `Add a show and its air dates appear here.` | `Add a show` |
| `noWatching` | `bookmark` | `Nothing in Watching` | `Move a show to Watching to build Today.` | `Browse your library` |
| `offlineCached` | `wifi.slash` | `You’re offline` | `Showing saved data. Changes will sync when you reconnect.` | — |
| `offlineNoData` | `wifi.slash` | `You’re offline` | `Connect to the internet to load your library.` | `Try again` |
| `serverNoCache` | `exclamationmark.circle` | `Couldn’t load your library` | `Something went wrong. Try again in a moment.` | `Try again` |
| `searchLaunchpad` | `magnifyingglass` | `Find your next show` | `Search anime and TV by title.` | — |
| `searchFailed` | `wifi.exclamationmark` | `Couldn’t search right now` | `Check your connection and try again.` | `Try again` |
| `searchUnavailable` | `exclamationmark.circle` | `Couldn’t search right now` | `Something went wrong. Try again in a moment.` | `Try again` |
| `searchOffline` | `wifi.slash` | `You’re offline` | `Search needs a connection. Trending shows appear when you reconnect.` | `Try again` |
| `noSessions` | `clock.arrow.circlepath` | `No watch history yet` | `Your first watch is recorded when you finish the show. Rewatches appear here as sessions.` | — |
| `noFilterMatches` | `slider.horizontal.3` | `No titles match` | `Clear the filters to see everything in your library.` | `Clear` |
| `nothingScheduled` | `calendar` | `Nothing scheduled` | `None of the shows you follow have an upcoming date.` | — |
| `everythingSynced` | `checkmark.circle.fill` | `Everything synced` | `No changes are waiting to sync.` | — |
| `noSearchResults(query:)` | `magnifyingglass` | `No results for “one pece”` | `Check the spelling or try another title.` | — |
| `noScopeMatches(scope:query:)` | `magnifyingglass` | `Nothing in TV for “frieren”` | `Switch the scope to All to see every result.` | `Show all` |
| `noScopeTrending(scope:)` | `line.3.horizontal.decrease` | `Nothing trending in TV` | `Switch the scope to All to see what everyone is watching.` | `Show all` |
| `calmToday(title:when:)` | **nil** | `Nothing changed since you were last here` | both given → `Frieren returns tomorrow.`; else `No new dates have been announced.` | — |
| `caughtUp(title:when:)` | `checkmark.circle.fill` | `You’re caught up` | both given → `Frieren returns tomorrow.`; else **nil** | — |

`calmToday` / `caughtUp` build their supporting line as `"\(title) \(when.lowercasedFirst())."` — the
`TemporalCopy` phrase follows the title inside one sentence, so its first character is lower-cased and a
full stop is appended. `calmToday` has **no symbol**: the calm day is a sentence about the user's shows,
not an icon.

> `calmToday` is **not** rendered as a plate on Today any more — the calm open is a quiet caught-up line
> (`TodayView.calmBlock`). "Nothing changed since you were last here" led every calm morning with an
> absence, at display size, above an Upcoming row restating its own supporting sentence. The value is kept
> for previews and the audit.

### 17.2 Which state is chosen, where

| Surface | Selection rule |
|---|---|
| Library (`AppModel.emptyStateCopy`) | `surfacePhase == .errorNoCache` → `isOnline ? serverNoCache : offlineNoData`; otherwise `emptyAccount` |
| Library search results | `Copy.Library.noSearchResults(query:filtered:)` |
| Library filter chips active | `noFilterMatches` |
| Today | `emptyToday` — **only** the offline / no-chart fallback. When the trending chart has loaded, an empty account instead opens on the chart's #1 show as a billboard (`Copy.Label.trending` pill, `Add to Library` capsule) |
| Schedule, no cache | `isOnline ? serverNoCache : offlineNoData` |
| Schedule, empty account | `emptySchedule` |
| Schedule, stocked library, no dated episodes | `nothingScheduled` |
| Schedule, filters active | `noFilterMatches` |
| Search launchpad, offline | `searchOffline` |
| Search launchpad, chart loaded but scope empties it | `noScopeTrending(scope:)` |
| Search launchpad, otherwise | `searchLaunchpad` |
| Search results, scope excludes every hit | `noScopeMatches(scope:query:)` |
| Search results, empty + error | `isOnline ? searchUnavailable : searchFailed` |
| Search results, empty, no error | `noSearchResults(query:)` |
| Detail, no cache | `isOnline ? serverNoCache : offlineNoData` |
| Watch history | `noSessions` |
| Sync status | `everythingSynced` |
| Profile account row (title only) | `offlineCached.title` |

> `searchFailed` and `serverNoCache` deliberately **share a title with their sibling**: one failure has one
> name. `searchFailed` carries the wifi glyph and "check your connection", so it is the *offline* copy;
> online, the catalogue itself failed and `searchUnavailable` says so — both name SEARCH, because the
> online branch used to render the Library's "Couldn't load your library" on a screen with nothing to do
> with the library.

**Android risk:** every `symbol` is an SF Symbol name. There is no automatic mapping. Use Material Symbols
and hand-map: `rectangle.stack → video_library`, `tv → tv`, `calendar → calendar_month`,
`bookmark → bookmark`, `wifi.slash → wifi_off`, `wifi.exclamationmark → signal_wifi_statusbar_not_connected`,
`exclamationmark.circle → error_outline`, `magnifyingglass → search`,
`clock.arrow.circlepath → history`, `slider.horizontal.3 → tune`, `checkmark.circle.fill → check_circle`,
`line.3.horizontal.decrease → filter_list`, `arrow.triangle.2.circlepath → sync`,
`exclamationmark.triangle.fill → warning`, `checkmark → check`. Keep the field name `symbol` so the data
shape stays identical.

---

## 18. Accessibility strings (`Copy.Accessibility`)

| Swift | String |
|---|---|
| `loading` | `Loading` |
| `refreshing` | `Refreshing` |
| `complete` | `Complete` |
| `active` | `Active` |
| `retryHint` | `Tries the request again` |
| `changeStatus` | `Change status` |
| `playsTrailerHint` | `Plays the video` |
| `opensStreamingOptionsHint` | `Opens the streaming options` |
| `opensTheShowHint` | `Opens the show` |
| `sectionHeader` | `Section` |
| `person(name:role:)` | `role` given → `Ken Watanabe, Director`; else the bare name |
| `removeFilter(text)` | `Watching. Remove filter` |
| `wordmarkLive(n)` | `n == 1` → `One followed episode is airing now`; else `3 followed episodes are airing now` |

**The wordmark's full stop is the only live indicator in the app** — `wordmarkLive` is what it says aloud.

Two accessibility rules the copy layer enforces rather than the views:

1. **Spoken titles are the WHOLE title**, never `shelfShortened` (`ShelfCard` and `BannerCard` set
   `accessibilityLabel` from the raw `title` + caption). §19 covers what the *visible* title does.
2. **VoiceOver still hears the episode number** even where the visible label has stopped repeating it
   (Today's hero capsule reads "Mark as watched" visually because the hero already states the episode
   directly above it; the accessibility label names the episode).

---

## 19. `String.shelfShortened` and `Franchise.displayTitle`

`displayTitle` is the title wherever identity is being **recognised** — Today, Library, Schedule, Detail,
every row and shelf. The raw `title` is kept for exactly two jobs: **Search results** (the user is matching
what they typed and every character is evidence) and **accessibility labels** (which always speak the
whole title).

```swift
var shelfShortened: String {
    var s = trimmingCharacters(in: .whitespacesAndNewlines)
    if s.hasSuffix("-"), let open = s.range(of: " -") {          // a trailing "-…-" subtitle wrapper
        s = String(s[s.startIndex..<open.lowerBound])
    }
    s = s.trimmingCharacters(in: CharacterSet(charactersIn: " -\u{2013}\u{2014}:"))
    if s.count > 40 {                                            // long "Title: Subtitle" keeps its identity half
        for sep in [": ", " – ", " — ", " - ", " ("] {
            if let r = s.range(of: sep), s.distance(from: s.startIndex, to: r.lowerBound) >= 12 {
                return String(s[s.startIndex..<r.lowerBound])
            }
        }
    }
    return s
}
```

Behaviour:
1. Trim whitespace.
2. If the string **ends with `-`** and contains `" -"` anywhere, cut everything from the **first** `" -"`.
   `"Re:ZERO -Starting Life in Another World-"` → `"Re:ZERO"`.
3. Trim any of ` `, `-`, `–` (U+2013), `—` (U+2014), `:` from **both** ends.
4. Only if the result is **longer than 40 characters**: scan the separators in the fixed order
   `": "`, `" – "`, `" — "`, `" - "`, `" ("`; take the first whose match starts at index **≥ 12** and
   return the prefix before it. Otherwise return the whole string.

> Rationale, quoted: *"a line that opens on a hyphen reads as a hyphenation bug, not as a title. Stripping
> the dashes is lossless; what follows the em/en dash or the colon is a subtitle the shelf never had room
> for anyway."* The 40-character gate and the ≥12 offset stop a short title being amputated and stop a
> title whose first colon is at index 2 (`"Re:ZERO"`) from collapsing to `"Re"`.

**Android:** `s.count` is a **Character (grapheme-cluster) count** in Swift, and `distance(from:to:)` counts
graphemes too. Kotlin's `String.length` is UTF-16 code units — for CJK titles with surrogate pairs or
emoji this diverges. Use `codePointCount` or a grapheme iterator (`BreakIterator.getCharacterInstance`) to
match exactly.

---

## 20. `TemporalCopy` — the temporal grammar

### 20.1 The rules

- **One temporal expression per item.** Exact instants (AniList) get a clock; date-only releases (TMDB) get
  a day word; unknown says unknown.
- **Precedence for the past is top-down:** relative → same calendar day → yesterday → weekday → date.
- **Everything is evaluated in the user's current calendar**, with the timestamp read through its
  `TimeAnchor` (§21.1).
- **The compact form drops the CLOCK. It never drops the day word or a preposition.** It used to drop both:
  one frame of Detail showed "Tomorrow at 8:30 PM" beside "Wed 6:30 PM", and two rows of Search showed
  "Fri 9:30 PM" above "29 Aug 2:00 PM" — three renderings of "when it airs" in one product, all so a
  caption could save six characters. Abbreviating the day to "Wed" is what makes the two forms look like
  different grammars; the clock is the part a 100-pt caption genuinely has no room for. **`airsCompact`'s
  day ladder is `airs`'s ladder verbatim**, so the two can never drift again.

### 20.2 `airs(at:now:source:)`

`anchor = source.timeAnchor`, `delta = ts - now`.

**AniList (`.anilist`, `.local` anchor):**

| Condition | Output |
|---|---|
| `0 < delta < 60 min` | `Airs in 27 min` — `max(1, delta / 60_000)`, so it never says "Airs in 0 min" |
| `dayDiff == 0` | `Today at 8:30 PM` |
| `dayDiff == 1` | `Tomorrow at 8:30 PM` |
| `dayDiff ∈ 2…6` | `Friday at 8:30 PM` (`fmtDayLong` → full weekday) |
| otherwise (incl. all past days) | `Aug 28 at 8:30 PM` / `Aug 28, 2027 at 8:30 PM` |

**TMDB (`.tmdb`, `.utcDate` anchor) — no clock, ever:**

| Condition | Output |
|---|---|
| `dayDiff == 0` | `Today` |
| `dayDiff == 1` | `Tomorrow` |
| `dayDiff ∈ 2…6` | `Friday` |
| otherwise | `Aug 28` / `Aug 28, 2027` |

### 20.3 `airsCompact(at:now:source:)`

Identical day ladder for **both** sources, with no clock and no preposition:
`Today` · `Tomorrow` · `Wednesday` · `Aug 28` · `Aug 28, 2027`.

### 20.4 `aired(at:now:source:)`

`elapsed = now - ts`, `days = -dayDiff(ts, now, anchor)`.

| Source | Condition | Output |
|---|---|---|
| AniList | `elapsed < 5 min` | `Aired just now` |
| AniList | `elapsed < 60 min` | `Aired 27 min ago` (integer division, no `max(1,…)`) |
| AniList | `days == 0` | `Aired 10h ago` |
| TMDB | `days == 0` | `Aired today` |
| both | `days == 1` | `Aired yesterday` |
| both | `days ∈ 2…6` | `Aired {fmtDayLong}` |
| both | otherwise | `Aired {dateWord}` → `Aired Aug 19` / `Aired Aug 19, 2025` |

> **⚠ Implementation truth vs doc comment.** The doc comment promises `"Aired Wednesday"` for the 2–6-days-ago
> band, but `fmtDayLong` only names weekdays for a **future** diff (§21.6); for `dayDiff ∈ −2…−6` it falls
> through to `fmtMonthDay`. So the real output for 2–6 days ago is **`Aired Sep 2`**, not `Aired Wednesday`.
> Port the code, not the comment; if the Android build should say the weekday, that is a *product* change and
> must be made on both platforms at once.
>
> Also note: for a **future** timestamp (`days < 0`) this function falls to the default branch and produces
> `Aired {dateWord}` — nonsense, but unreachable in practice because callers gate on `lastAired`.

### 20.5 `returns(at:now:source:)`

| Condition | Output |
|---|---|
| `ts == nil` | `No date announced` (`TemporalCopy.noDateAnnounced`) |
| `dayDiff < 0` | `Returned Jul 5` (`dateWord`) |
| `dayDiff == 0` | `Returns today` |
| `dayDiff == 1` | `Returns tomorrow` |
| `dayDiff ∈ 2…6` | `Returns Friday` |
| otherwise | `Returns Oct 2` / `Returns Oct 2, 2027` |

> **Why the past branch exists:** the curated catalogue note can outlive the premiere by weeks, and every
> past day used to read "Returns today" — Mushoku Tensei read "Returns today" two months into its season.

`premieres(_ date: String)` → `Premieres Oct 2` — takes an already-formatted date string (from
`FranchisePart.announcedDateLabel`, which is `fmtFullDate` at the `.utcDate` anchor).

### 20.6 `since(_ ts:now:)` — always `.local`

| Condition (`days = -dayDiff`) | Output |
|---|---|
| `days == 0` | `Since earlier today` |
| `days == 1` | `Since yesterday` |
| `days ∈ 2…6` | `Since {fmtDayLong}` |
| otherwise | `Since {dateWord}` |

> **⚠ Same divergence as `aired`.** The doc comment promises `"Since Tuesday"`; the 2–6 band actually
> renders `Since Aug 12` because `fmtDayLong` does not name past weekdays. Ported as written.

### 20.7 `dateWord(_ ts:now:anchor:)`

```swift
let a = Formatting.localParts(ts,  anchor: anchor)
let b = Formatting.localParts(now, anchor: anchor)
return a.y == b.y ? Formatting.fmtMonthDay(ts,  anchor: anchor)
                  : Formatting.fmtFullDate(ts,  anchor: anchor)
```

Same year → `Aug 28`; different year → `Aug 28, 2027`.

> **The year is never string-joined on.** `"\(md), \(a.y)"` produced **"31 Mar, 2013"** on a day-first
> device — a comma between a day-first date and its year, which no locale writes (en-GB is "31 Mar 2013",
> en-US "Mar 31, 2013") — and it was on every row of every episode list. `fmtFullDate` carries the
> `MMMdyyyy` skeleton, which orders and punctuates itself per locale; a hand-assembled date cannot.

Note that `now` is read in the **anchor's** calendar here (unlike `dayDiff`, which always reads `now`
locally). This only matters within a few hours of New Year.

### 20.8 `dateRange(_:_:now:anchor:)` — default anchor `.local`

```
a = localParts(from, anchor); b = localParts(to, anchor); thisYear = localParts(now, anchor).y
if !(a.y == b.y && a.y == thisYear) -> "{fmtFullDate(from)} – {fmtFullDate(to)}"
else                                -> "{fmtMonthDay(from)} – {fmtMonthDay(to)}"
```

Separator is `" \u{2013} "` (space, en dash, space). `24 May – 29 Jul`, `10 Dec 2024 – 3 Feb 2025`.

> **A span that crosses a year, or sits in a year that is not this one, states both years.** Within two taps
> the shipped build showed "31 Mar, 2013", "24 May – 29 Jul" (no year at all), "10 Dec, 2024" and
> "24 May 2026" — four formats, two of them in adjacent rows of one list.

### 20.9 Sentence-internal re-casing (three call sites, one rule)

A `TemporalCopy` phrase set inside a sentence rather than at the head of one is re-cased **only when its
first word is an ordinary adverb**. Proper nouns keep their capital.

| Helper | Location | Rule |
|---|---|---|
| `String.lowercasedFirst()` | `Copy.swift` (private) | Lower-case the first character. Used by `Progress.newEpisode` and the `calmToday` / `caughtUp` supporting lines |
| `TodayView.midSentence(_:)` | `TodayView.swift` (private static) | Lower-case the first word **only if** it is `Today`, `Tomorrow` or `Yesterday`; otherwise return the phrase untouched. `"friday"`, `"aug 28"`, `"sun"` are proper nouns and a sentence does not get to lower-case them |
| `ReturnFact.lowerFirst(_:)` | `LibraryFacts.swift` | Same as `lowercasedFirst` (flagged in-source as a duplicate to fold) |
| `String.lowercasedFirstWord()` | `ProfileView.swift` (private) | Same again, for `Checked {stamp}` |

`Progress.newEpisode` lowers on the prefixes `["Today", "Tomorrow", "Airs", "In "]`.
`TodayView.sinceFragment` rebuilds `"since " + tail` rather than lower-casing, so `Jul` survives.

---

## 21. `Formatting` — calendars, clocks, skeletons

Timestamps are **milliseconds since epoch, `Int64`**, matching the API contract; the conversion to/from a
date object happens at the networking layer. `Int64.nowMs` = `Int64((Date().timeIntervalSince1970 * 1000).rounded())`.

| Constant | Value |
|---|---|
| `D` | `86_400_000` |
| `H` | `3_600_000` |
| `minuteMs` | `60_000` |

### 21.1 `TimeAnchor` — two calendars, not one

| Case | Meaning | Time zone |
|---|---|---|
| `.local` | A **real instant**. AniList dates episodes to the minute, so its timestamps carry a genuine broadcast moment | `TimeZone.current` |
| `.utcDate` | A **date-only fact**. TMDB ships air dates with no clock and the server synthesizes them at **17:00 UTC**, so the only true part of the timestamp is its UTC calendar day | `TimeZone(secondsFromGMT: 0)` |

`isDateOnly == (self == .utcDate)`.

**Two consequences the anchor enforces rather than documents:**
> (a) day labels, day diffs and day bucketing use the timestamp's **own** calendar day;
> (b) a `.utcDate` timestamp **never** yields a clock time or an hour-precision countdown — `fmtTime`
> returns `""` and `fmtCountdown` degrades to day precision.

**Why:** breaking a synthesized 17:00-UTC instant down locally pushes every timezone east of UTC+7 one day
forward — a Sunday drop read "Monday" in JST.

**Never branch on `source` at a formatting call site — pass `source.timeAnchor`.** Episode air dates use
`Episode.airDateAnchor`, which is `.utcDate` **whatever the source is**.

### 21.2 Caches (performance-load-bearing)

**Calendars** — built once per (time zone, locale), keyed `"{TimeZone.current.identifier}|{Locale.current.identifier}"`,
both cached calendars dropped when the key changes so a travelling user never keeps yesterday's calendar.
Reason quoted: *"`localParts` used to construct a `Calendar` on every call — 2.2 µs each on a Mac, and the
Schedule feed called it 22 days × 2 passes × every airing show × ~30 times per render. A cached calendar is
0.65 µs."* Both calendars are `Calendar(identifier: .gregorian)` with `locale = Locale.current` and the
anchor's time zone.

**Formatters** — cached per `"{skeleton}|{timeZone.identifier}"`, with the whole cache dropped whenever
`"{locale.identifier}|{locale.hourCycle}|{TimeZone.current.identifier}"` changes. **The `hourCycle` term is
essential**: a cached formatter would otherwise keep printing "9:00 PM" after the user flips the 24-Hour
Time switch.

> **Android:** `java.time` formatters are immutable and thread-safe, so cache them the same way, but the
> invalidation trigger differs. Register a `BroadcastReceiver` for `Intent.ACTION_TIME_CHANGED`,
> `ACTION_TIMEZONE_CHANGED` and `ACTION_LOCALE_CHANGED`, and read the 24-hour setting from
> `android.text.format.DateFormat.is24HourFormat(context)` — **`DateTimeFormatter.ofLocalizedTime(SHORT)`
> ignores the user's 24-hour toggle**, which would break the single most visible rule in this file
> ("a device set to 24-Hour Time must read 21:00, not 9:00 PM"). Use
> `android.text.format.DateFormat.getTimeFormat(context)` for the clock and
> `DateFormat.getBestDateTimePattern(locale, skeleton)` for every other skeleton.

### 21.3 `LocalParts` and day keys

```swift
struct LocalParts { var y: Int; var mo: Int /*1-12*/; var d: Int; var hour: Int /*0-23*/; var minute: Int; var wd: Int /*0=Sun..6=Sat*/ }
```

- `localParts(ts, anchor:)` — decomposes in the anchor's calendar. `hour`/`minute` are **only meaningful
  for `.local`**; a `.utcDate` timestamp always reports the synthesized 17:00 and must never be shown or
  thresholded on.
- `wd` is `Calendar.weekday - 1` (Calendar is 1=Sunday).
- `localDayKey(ts, anchor:)` — a **UTC midnight** ms-epoch for the calendar day containing `ts` as read in
  `anchor`. Normalising into one shared space is what makes day keys comparable across anchors: the key of
  a TMDB date-only timestamp (its UTC day) subtracts cleanly from the key of "now" (local day).
- `localMondayCol(ts, anchor:)` = `(wd + 6) % 7` → 0=Mon … 6=Sun.

### 21.4 `dayDiff(ts:now:anchor:)` — the single definition everything is built on

```swift
let a = localDayKey(ts,  anchor: anchor)
let b = localDayKey(now, anchor: .local)      // `now` is ALWAYS read locally — it IS a real instant
return Int((Double(a - b) / Double(D)).rounded())
```

`0` = same day, `+1` = tomorrow, `−1` = yesterday. The `.rounded()` on a double is what makes it survive
DST transitions (a 23- or 25-hour local day still keys to a clean UTC midnight, so the quotient is exact —
the rounding is belt-and-braces).

### 21.5 Weekday and month names

Names depend on the **locale only, never the time zone**, so they always come off the `.local` formatter
regardless of which anchor the day was computed in.

| Function | Source array | Output |
|---|---|---|
| `weekdayShort(wd)` | `shortStandaloneWeekdaySymbols` | `Wed` |
| `weekdayShortMonFirst(col)` | same, `(col + 1) % 7` | `Wed` for a Monday-first column |
| `weekdayLetterMonFirst(col)` | `veryShortStandaloneWeekdaySymbols` | `W` — **the locale's own one-letter form**, not the first character of a name that has no reason to be Latin |
| `weekdayFull(wd)` (private) | `standaloneWeekdaySymbols` | `Wednesday` |
| `weekdayNameMonFirst(col)` | `weekdayFull((col + 1) % 7)` | `Wednesday` |

Out-of-range indices return `""`.

> **Android:** `DayOfWeek.getDisplayName(TextStyle.SHORT_STANDALONE / NARROW_STANDALONE / FULL_STANDALONE, locale)`.
> Note Android's `DayOfWeek` is 1=Monday…7=Sunday, the opposite convention to `LocalParts.wd`; convert once
> at the boundary and keep `wd` 0=Sun internally so the `(col + 1) % 7` arithmetic ports verbatim.

### 21.6 Day words

| Function | Ladder |
|---|---|
| `fmtDay(ts:now:anchor:)` | `0 → "Today"`, `1 → "Tomorrow"`, `−1 → "Yesterday"`, **anything else → `weekdayShort(wd)`**. ⚠ A date 30 days out reads `Thu`; this function never produces a month-day |
| `fmtDayLong(ts:now:anchor:)` | `0 → "Today"`, `1 → "Tomorrow"`, `−1 → "Yesterday"`, `1 < diff < 7 → weekdayFull(wd)`, **everything else (including all past days ≤ −2) → `fmtMonthDay`**. The long-weekday sibling of `fmtDay`, and **the only day label a date-only (TV) release should ever use** |
| `fmtWhen(ts:now:anchor:)` | `.utcDate` → `fmtDayLong`; else `"{fmtDay} {fmtTime}"` → `Tomorrow 9:00 PM`. Wrapped by `Franchise.whenLabel`; **no live call site in this build** |

The asymmetry in `fmtDayLong` (future weekdays named, past weekdays not) is the direct cause of the two
divergences flagged in §20.4 and §20.6, and the reason `Copy.elapsedWord` fetches the past weekday itself.

### 21.7 Countdowns and clocks

**`fmtCountdown(target:now:anchor:)`** — minute-precise wait. A `.utcDate` timestamp has no clock to count
down to, so it degrades to the day-precision span instead of inventing hours.

```
if anchor.isDateOnly -> fmtRelSpanShort(ts: target, now: now, anchor: anchor)
s = max(0, target - now)
if s < 60_000 -> "now"
d = s / D;  s -= d*D;  h = s / H;  s -= h*H;  m = s / 60_000
if d > 0 -> "2d 4h"
if h > 0 -> "3h 12m"
else     -> "31m"
```

**`fmtTime(ts:anchor:)`** — locale-correct clock (`9:00 PM`, or `21:00` on a 24-hour device). **Returns `""`
for a `.utcDate` timestamp**: its clock is synthesized, so there is no time to print. Implemented with the
empty skeleton, which means `dateStyle = .none, timeStyle = .short` — the style that honours the 24-Hour
Time setting.

**`fmtAgo(ts:now:anchor:)`** — *no live call site in this build*, but part of the public surface:

| Anchor | Condition | Output |
|---|---|---|
| `.utcDate` | `-dayDiff <= 0` | `today` |
| `.utcDate` | otherwise | `3d ago` |
| `.local` | `m < 1` | `just now` |
| `.local` | `m < 60` | `42m ago` |
| `.local` | `h < 24` | `9h ago` |
| `.local` | otherwise | `4d ago` (`h / 24`) |

### 21.8 Day-precision spans (the TV analogue of the countdown)

**`fmtRelSpanShort(ts:now:anchor:)`** — bare span, no preposition:

| `d = dayDiff` | Output |
|---|---|
| `< 0` | `""` |
| `0` | `today` |
| `1…6` | `3d` |
| `7…29` | `(d + 3) / 7` + `wk` → `2wk` |
| `≥ 30` | `max(1, (d + 15) / 30)` + `mo` → `2mo` |

> **A date in the PAST returns `""` rather than "today".** These spans describe a wait, and a timestamp we
> have already passed describes none — a stale `nextAiringAt` the source has not advanced used to render as
> a permanent "today" (a week-old Saturday slot read "Sat · today" every day since). **Callers treat `""`
> as "nothing to say".**

Note the integer division rounds **to nearest** by adding half the divisor: `(d+3)/7` and `(d+15)/30`.
Kotlin's `Int` division truncates the same way, so this ports verbatim.

**`fmtRelSpan`** — `short.isEmpty || short == "today"` → `short`; else `"in {short}"` → `in 3d`, `in 2wk`.

**`fmtDayBadge(ts:now:anchor:)`** — a compact two-line date badge, `(top, bottom)`. *No live call site.*

| Condition | `top` | `bottom` |
|---|---|---|
| `diff < 0` | `Aired` | `fmtMonthDay` |
| `diff == 0` | `Today` | `today` |
| `diff == 1` | `Tomorrow` | `in 1d` |
| `1 < diff < 7` | `weekdayShort(wd)` → `Sun` | `in 4d` |
| otherwise | `fmtMonthDay` → `May 4` | `in 2wk` |

### 21.9 Date skeletons

Every one goes through `setLocalizedDateFormatFromTemplate`, so ordering and punctuation are the locale's.

| Function | Skeleton | en-US | en-GB |
|---|---|---|---|
| `fmtMonthDay(ts:anchor:)` | `MMMd` | `May 4` | `4 May` |
| `fmtFullDate(ts:anchor:)` | `MMMdyyyy` | `Jun 24, 2026` | `24 Jun 2026` |
| `fmtMonthYear(ts:anchor:)` | `MMMyyyy` | `Oct 2026` | `Oct 2026` |
| `fmtTodayDate(now)` | `EEEEMMMMd` | `Sunday, July 19` | `Sunday 19 July` |
| `fmtTodayDateShort(now)` | `EEEEMMMd` | `Sunday, Jul 19` | `Sunday 19 Jul` |
| `fmtTime(ts:anchor:)` | *(empty → short time style)* | `9:00 PM` | `21:00` |

`fmtTodayDate` / `fmtTodayDateShort` are always `.local` — it is the **device's own today**. Neither has a
live call site in this build.

### 21.10 `prettyReleaseString(_ raw: String)`

Prettifies a curated release string from `FranchiseUpcoming`. **Parsed as a bare calendar date, so it is
formatted in UTC and never shifts a day.**

```
s = raw.trimmed
parts = s.split("-")
require parts.count >= 2, y = Int(parts[0]) in 1000...9999, m = Int(parts[1]) in 1...12   else return s
if parts.count >= 3, d = Int(parts[2]) in 1...31  -> fmtFullDate(utcTimestamp(y,m,d), .utcDate)
if parts.count == 2                               -> "MMMyyyy" of utcTimestamp(y,m,1), .utcDate
else                                              -> return s
```

`"2026-07-05"` → `Jul 5, 2026`; `"2026-10"` → `Oct 2026`; `"October 2026"`, `"2027"`, `"TBA"` pass through
unchanged. A three-part string with an invalid day (e.g. `"2026-10-99"`) falls through and returns `s`.

### 21.11 Greeting and day-part

| Function | Rule |
|---|---|
| `isEvening(hour:)` | `hour >= 18` — **the app's single definition of when "tonight"/"evening" starts**, shared by the greeting, Library's day-part label and Schedule's hero eyebrow |
| `greetingFor(now)` | `h < 5` → `Late night`; `h < 12` → `Good morning`; `!isEvening(h)` → `Good afternoon`; else `Good evening`. Hour read at the `.local` anchor |

*No live call site for `greetingFor` in this build*; keep it, the strings are part of the vocabulary.

### 21.12 HTML text cleaning

**`stripHtml(_ s: String?) -> String`** — returns the **full** cleaned text; visual clamping
(`lineLimit` + "Read more") is the view's job, never a data-layer truncation.

1. `nil` or empty → `""`.
2. Remove tags: regex `<[^>]+>` → `""`.
3. `decodeHtmlEntities`.
4. Collapse whitespace: regex `\s+` → `" "`.
5. Trim.

**`decodeHtmlEntities(_ s: String) -> String`** — early-outs if the string contains no `&`.

1. Numeric references first, regex `&#(x[0-9A-Fa-f]+|[0-9]+);`; `x`-prefixed parsed base 16, else base 10;
   invalid scalars are dropped (the reference disappears).
2. Then the named list **in this exact order**:

| Entity | Char |
|---|---|
| `&lt;` | `<` |
| `&gt;` | `>` |
| `&quot;` | `"` |
| `&apos;` | `'` |
| `&nbsp;` | ` ` (a plain space, **not** U+00A0) |
| `&mdash;` | `—` U+2014 |
| `&ndash;` | `–` U+2013 |
| `&hellip;` | `…` U+2026 |
| `&lsquo;` | `‘` U+2018 |
| `&rsquo;` | `’` U+2019 |
| `&ldquo;` | `“` U+201C |
| `&rdquo;` | `”` U+201D |
| `&amp;` | `&` |

> **`&amp;` must stay last** so `&amp;lt;` yields `&lt;`, not `<`.

**Android:** do **not** substitute `Html.fromHtml` / `HtmlCompat.fromHtml`. It decodes a different entity
set, emits a `Spanned` with paragraph breaks, and would not collapse whitespace the same way. Port the four
steps literally.

---

## 22. The audit (`Copy.auditProblems`) — port it as a unit test

The table checks its own invariants without a test target (the prototype has none); the "Copy rules"
preview renders `auditProblems` and **it must be empty**. On Android this becomes a plain JVM unit test.

`allSampleStrings` = every command label + every confirmation button + a fixed list of representative
toasts / notices / progress lines / confirmations / states / accessibility strings + `statusesInOrder` +
the `title` / `supporting` / `primaryLabel` / `secondaryLabel` of sixteen `EmptyStateCopy` values
(`emptyAccount`, `emptyToday`, `emptySchedule`, `noWatching`, `offlineCached`, `offlineNoData`,
`searchFailed`, `searchLaunchpad`, `noSessions`, `serverNoCache`, `noFilterMatches`, `nothingScheduled`,
`everythingSynced`, `calmToday(title:"Frieren", when:"Returns tomorrow")`,
`caughtUp(title:"Frieren", when:"Returns tomorrow")`, `noSearchResults(query:"one pece")`).

| Check | Message template |
|---|---|
| `Action.ellipsisViolations` | `“{label}” ends in an ellipsis but opens no confirmation` |
| `Action.confirmationButtonViolations` | `confirmation button “{label}” ends in an ellipsis` |
| `hasBannedNotation` | `“{s}” uses banned episode notation` |
| contains `!` | `“{s}” uses an exclamation mark` |
| contains `'` (straight apostrophe) | `“{s}” uses a straight apostrophe` |

`hasBannedNotation(_ s:)`:

```swift
if s.contains("Ep ") || s.contains("Ep.") { return true }
for i in chars.indices where chars[i] == "E" {
    if i + 1 < chars.count, chars[i + 1].isNumber { return true }   // "E19"
}
return false
```

(Note it is a capital-`E`-followed-by-digit scan, so a title containing "E4" would trip it — the audit only
runs over the copy table's own strings, never over interpolated data.)

---

## 23. Android reproduction — summary of the porting decisions

| Concern | Decision |
|---|---|
| Where strings live | A Kotlin `object Copy` mirroring the Swift nesting (`Copy.Action`, `Copy.Progress`, …), **not** `strings.xml`. ~40 % of the table is behaviour (pluralisation, ladders, the ellipsis table, the audit) that a resource file cannot hold, and splitting the catalogue would recreate exactly the "one string, two homes" defect the table exists to prevent. |
| Pluralisation | Keep `plural(n, one, many)` hand-rolled with its NBSP. **Do not** use `getQuantityString`. |
| Timestamps | `Long` milliseconds throughout, as on iOS. Convert to `Instant`/`ZonedDateTime` only inside `Formatting`. |
| Calendars | `ZoneId.systemDefault()` vs `ZoneOffset.UTC`, chosen by `TimeAnchor`. Cache the two `ZoneId`s and re-key on locale/zone change exactly as `CalendarStore` does. |
| Clock format | `android.text.format.DateFormat.getTimeFormat(context)` — the only API that honours the 24-hour system toggle. |
| Other date formats | `DateFormat.getBestDateTimePattern(locale, skeleton)` with the skeletons in §21.9, fed to `SimpleDateFormat`/`DateTimeFormatter`. |
| Weekday/month names | `DayOfWeek.getDisplayName(TextStyle.*_STANDALONE, locale)`; convert 1=Mon to the internal 0=Sun `wd`. |
| Grapheme counting | `shelfShortened`'s `count > 40` and `distance >= 12` must count graphemes (`BreakIterator`), not UTF-16 units. |
| Symbols | Hand-mapped Material Symbols (§17.2); keep the `symbol` field name and the nullable type. |
| Audit | Straight port as a JVM unit test asserting `auditProblems.isEmpty()`. |

---

## 24. Android risk register

| Item | Risk | Severity | Why |
|---|---|---|---|
| `EmptyStateCopy.symbol` — 15 distinct **SF Symbol** names | Needs a hand-built Material Symbols mapping; some (`wifi.exclamationmark`, `clock.arrow.circlepath`, `line.3.horizontal.decrease`) have no exact twin, and weight/optical-size behaviour differs | moderate | SF Symbols are Apple-licensed and not redistributable |
| **24-hour clock honouring** | `DateTimeFormatter.ofLocalizedTime(SHORT)` ignores the user's 24-hour toggle; only `android.text.format.DateFormat.getTimeFormat(context)` respects it, and it needs a `Context` — which forces `Formatting` to be injected rather than a pure object | moderate | The single most visible formatting rule in this file |
| **`hourCycle` cache invalidation** | iOS re-keys on `Locale.hourCycle`; Android must observe `ACTION_TIME_CHANGED` / `Settings.System.TIME_12_24` broadcasts to drop the formatter cache | moderate | A stale formatter prints "9:00 PM" after the user flips the switch |
| `setLocalizedDateFormatFromTemplate` skeletons | `DateFormat.getBestDateTimePattern` is a direct equivalent but ICU versions differ between the two platforms and between Android API levels — `MMMd` in some locales resolves with different separators | easy | Verify en-US / en-GB / ja-JP / de-DE against the iOS output |
| `NSURLErrorDomain` code mapping in `Notice.reason` | Six distinct URLError codes collapse to `No connection`; OkHttp raises a different exception taxonomy and a captive portal behaves differently again | moderate | Get it wrong and a write failure reads "Something went wrong" where iOS says "No connection" |
| `APIError.rateLimited` → `serverError` asymmetry | Looks like a bug and will be "fixed" by any porting engineer who does not read §9.3 | easy | Behavioural parity requires copying it |
| `fmtDayLong` past-weekday fall-through (§20.4, §20.6) | Doc comments promise `Aired Wednesday` / `Since Tuesday`; the code emits `Aired Sep 2` / `Since Aug 12` | easy | Port the code; changing it is a product decision for both platforms |
| NBSP (U+00A0) and word joiner (U+2060) in strings | Compose `Text` honours both, but a naive `strings.xml` round-trip or a trim/normalise step will eat them; so will most translation tooling | easy | The line-break behaviour they buy is the whole reason they exist |
| `&` in five headings if moved to `strings.xml` | Must be `&amp;` | easy | Compile error, caught immediately |
| Grapheme-vs-UTF-16 counting in `shelfShortened` | CJK/emoji titles diverge from iOS at the 40-char gate | easy | `BreakIterator` fixes it |
| **Live Activity / Dynamic Island** copy | None of this catalogue feeds one today (the app gates Live Activities to AniList sources and the strings live outside these files), but any future "airing now" surface has no Android twin | blocker (if attempted) | No OS equivalent; the nearest analogue is an ongoing notification with a custom layout |
| System notification body (`Copy.Alert`) | Direct port; Android's `NotificationCompat` `setContentTitle`/`setContentText` map cleanly, `threadIdentifier` → `setGroup(franchiseId)` | easy | Keep the **no full stop** rule — it is an Apple convention the copy adopted, and changing it on Android would split the voice |
| `LocalizedError` / `errorDescription` | No Kotlin equivalent of "the exception's own user-facing string"; must be an explicit `APIError.userMessage` property | easy | Keep `diagnostic` separate so a status code can never leak into a surface |
| The `Copy.auditProblems` preview harness | SwiftUI `#Preview` has no Compose equivalent that fails a build; move it to a JVM unit test in CI | easy | The invariant matters more than the preview |
