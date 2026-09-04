# Library — screen, shelves, All titles, and the Library fact vocabulary

The Library is the app's **calm** root. Per the product's *urgency pact*, Today carries every
obligation ("4 episodes behind", amber mark rings, countdowns) and the Library carries **none** —
it is a zero-control browsing surface: one lead shelf of art you are in the middle of, then four
quiet horizontal shelves grouped by a show's relationship to your *future* (Returning / Watching /
Planned / Announced / Watched), and one door — a trailing bar button reading "30 titles" — into
**All titles**, the single screen in the Library that has controls on it (search, sort, direction,
status filter, an unwatched-episodes axis, a poster/list view toggle and an A–Z index rail). Two
source files own all of it: `LibraryView.swift` (both screens plus the Sort & filter sheet) and
`LibraryFacts.swift` (the vocabulary: which bucket a show is in, how "when does it come back" is
phrased, and the two lines drawn under every Library row). This document specifies both to the
pixel, the string and the branch.

---

## 0. Files, and what depends on what

| Swift file | Contents |
|---|---|
| `ios/Sources/Features/Library/LibraryView.swift` | `LibraryView` (root), `LibraryRootMetrics`, `LibraryContinueShelf`, `LibraryContinueCard`, `LibraryLandscapeItem`, `LibraryLandscapeShelf`, `ReturnScope`, `LibraryAllView`, `ArrangeGeometry`, `ArrangeMetrics`, `ArrangeDetent`, `ArrangeSheet` |
| `ios/Sources/Features/Library/LibraryFacts.swift` | `LibrarySection`, `LibraryShelving`, `ReturnFact`, `LibraryDates`, `LibraryRowFacts` |

Everything else the screens use is shared: `AppModel` (data + shelving), `Models*.swift`
(derivations), `DesignSystem/*` (tokens, primitives, copy). Only `ReturnFact` leaks out of the
feature — `FranchiseDetailView` calls `ReturnFact.of(_:appModel:).text` so the show page cannot
contradict the Library shelf.

---

## 1. Design tokens used by this area

Reproduce these as Compose constants. **No screen may inline a colour or a size**; that rule is
load-bearing in the iOS codebase and should carry over.

### 1.1 Colour (all sRGB, dark-only app — there is no light theme)

| Token | Hex / value | Where the Library uses it |
|---|---|---|
| `canvas` | `#09090B` | screen ground, pinned section-header ground, chrome veil |
| `canvasRaised` | `#0D0E11` | Sort & filter sheet background |
| `surfaceFlat` | `#171719` | (`.plate` fill reference) |
| `surfaceRaised` | `#242428` | poster/banner ground before art decodes; index-rail capsule under the finger |
| `surfacePressed` | `#353842` | row press wash, chip press ground |
| `textPrimary` | `#F4F1EC` | titles, section titles, sheet row labels |
| `textSecondary` | `#AAA6A0` | `meta` line, shelf captions, filter-button idle in All titles is `textPrimary` |
| `textTertiary` | `#85817C` | counts, index-rail letters at rest, section letter headers, footer count, chevron on section headers |
| `textDisabled` | `#807C77` | `MediaRow` chevron, sheet pop-up glyph |
| `accent` | `#F0A24E` | **facts and state only** — near return dates, progress-bar fill, filter chips, active filter glyph, selected toggle |
| `accentSoft` | `#F0A24E` @ 14 % | filter-chip ground |
| `onAccent` | `#0B0B0D` | ink on an amber ground |
| `interactive` | = `textPrimary` (`#F4F1EC`) | every bare tappable word ("Reset", "Done", "Retry") |
| `separatorQuiet` | white @ 4.5 % | row hairlines, pinned-header rule, grouped-row dividers |
| `posterEdge` | white @ 9 % | 1-px border on all artwork |
| `skeleton` | `#F4F1EC` @ 11 % | skeleton blocks |
| `plateLift` | white @ 5.5 % | `.plate` ground (grouped lists) — a **lift over whatever is behind**, not an opaque fill |
| `raisedLift` | white @ 11 % | `.raised` ground |
| `hairline` | white @ 5.5 % | top-edge highlight on raised surfaces (gradient top→center) |
| `strokeStrong` | white @ 20 % | progress-bar track |
| `scrim` | black @ 56 % | bottom of the `ProgressBanner` gradient |
| `ambientBackdropFallback` | `#432D21` | ambient wash base before artwork palette resolves |

> **Rule to port verbatim: amber is not an action colour.** `accent` means MEANING (a real next
> step — "Returns Oct 2") or STATE (selected, active filter, committed mark) or a GROUND (the
> progress bar, a chip's soft disc). Every tappable *word* is `interactive` ink. The Library was
> the screen that broke this twice — an amber "See all" sat directly over amber "Returns Oct 2"
> captions — which is why the shelf headers today draw **no "See all" word at all** (§5.5).

### 1.2 Spacing / radius / metrics

| Token | Value |
|---|---|
| `ThemeSpace.x0_5 … x16` | 2, 4, 8, 12, 16, 20, 24, 32, 40, 48, 64 (x0_5, x1, x2, x3, x4, x5, x6, x8, x10, x12, x16) |
| `ThemeRadius.poster` | 10 |
| `ThemeRadius.compactControl` | 12 |
| `ThemeRadius.row` | 16 |
| `ThemeRadius.card` | 22 |
| `ThemeMetrics.gutter` | 16 |
| `ThemeMetrics.sectionGap` | 30 |
| `ThemeMetrics.labelGap` | 10 |
| `ThemeMetrics.shelfGap` | 12 |
| `ThemeMetrics.titleGap` | 3 |
| `ThemeMetrics.artGap` | 14 |
| `ThemeMetrics.rowCompact` | 56 |
| `ThemeMetrics.rowStandard` | 88 |
| `ThemeMetrics.rowMedia` | 100 |
| `ThemeMetrics.rowRuleInset` | `gutter + PosterSize.row.width + artGap` = 16 + 60 + 14 = **90** |
| `ThemeMetrics.tabBarClearance` | `bottomChromeHeight + 12` = 64 + 12 = **76** |
| `ThemeMetrics.tabBarVisualHeight` | 90 (used for optical centring of full-surface states) |
| `ThemeMetrics.bottomChromeHeight` | 64 |
| `ThemeMetrics.bottomUnderfill` | 180 |
| `ThemeMetrics.topSafeInset` | read from the window; 59 fallback |
| `ThemeMetrics.inlineBarHeight` | 44 |
| `ThemeMetrics.inlineBarBottom` | `topSafeInset + 44` |
| `ThemeMetrics.topChromeRamp` | 22 |
| `ThemeMetrics.topChromeHeight` | `topSafeInset + 22` |
| `ThemeMetrics.barEdgeRamp` | 28 |
| `ThemeMetrics.chromeBarOpacity` | 0.74 |
| `ThemeMetrics.searchDrawerHeight` | 52 |
| `ThemeMetrics.rootWashHeight` | 320 |
| `ThemeMetrics.rootWashIntensity` | 0.4 |
| `PosterSize.row` | 60 × 90, radius 10, **no shadow** |
| `PosterSize.shelfMedium` | 112 × 168, radius 12, shadow `.art` |
| `BannerCard.height` | 104 |
| `ShadowToken.art` | black 55 %, radius 12, y 7 |

### 1.3 Type

Two families: **Outfit** *speaks* (identity, titles, body, buttons, link actions), **SF/system**
*annotates* (dense metadata, small-caps labels, numerals). Outfit sizes scale with Dynamic Type
via `relativeTo:`; SF tokens are system text styles.

| Token | Font | Size | Tracking | Dynamic-Type anchor |
|---|---|---|---|---|
| `sectionTitle` | Outfit SemiBold | 20 | −0.30 | `.title3` |
| `showTitleM` | Outfit SemiBold | 17 | −0.20 | `.headline` |
| `showTitleL` | Outfit SemiBold | 22 | −0.35 | `.title2` |
| `rowTitle` | Outfit SemiBold | 17 | −0.20 | `.headline` |
| `body` | Outfit Regular | 17 | −0.10 | `.body` |
| `callout` | Outfit Regular | 16 | −0.10 | `.callout` |
| `listAction` | Outfit SemiBold | 13 | 0 | `.footnote` |
| `shelfTitle` | Outfit Medium | 14 | −0.10 | `.subheadline` |
| `rowMeta` | SF footnote (13) | — | 0 | `.footnote` |
| `rowMetaLead` | SF footnote **semibold** | — | 0 | `.footnote` |
| `metadata` | SF footnote | — | 0 | `.footnote` |
| `metadataEmphasis` | SF footnote semibold | — | 0 | `.footnote` |
| `sectionLabel` | SF caption2 semibold | ~11 | **+1.0** | `.caption2`, rendered `.uppercase` |
| `shelfCaption` | SF caption **medium** | ~12 | 0 | `.caption` |

### 1.4 Motion

| Token | Curve |
|---|---|
| `uiPress` | easeOut 0.09 s |
| `uiMicro` | spring(response 0.22, damping 0.88) |
| `uiSnappy` | spring(response 0.34, damping 0.84) |
| `uiSettle` | spring(response 0.46, damping 0.90) |
| `uiGentle` | easeInOut 0.22 s |
| `uiPoster` | easeOut 0.18 s |
| `uiNumeric` | easeOut 0.22 s |
| `uiReduced` | easeOut 0.12 s — **the universal Reduce-Motion substitute** |
| `uiCrossfade` | = `uiReduced` |

`ThemeMotion.pick(token, reduceMotion:)` returns `uiReduced` when Reduce Motion is on. Every
animation in the Library goes through it except `uiGentle` on the freshness/veil crossfades, which
are already 220 ms opacity-only.

### 1.5 Haptics

One coordinator, one event per token per floor. `.selection` floor is **40 ms** (deliberately, so
an A→W drag on the index rail fires ~20 taps rather than 2); every other token's floor is **300 ms**.
Haptics are suppressed entirely when the app is not `active` or the user's "Haptics" preference is
off (`UserDefaults previously.haptics`, default true).

| Token | iOS generator | Library trigger |
|---|---|---|
| `.selection` | `UISelectionFeedbackGenerator` | index-rail letter change; any chip clear; Reset; every picker/toggle change in the Sort & filter sheet |
| `.refreshArmed` | light impact @ 0.50 | pull-to-refresh crosses 80 pt **while the finger is down** |

No other haptic fires from the Library. The context-menu writes (`markCaughtUp`, `setStatus`,
`removeWithUndo`) fire their own inside `AppModel`.

---

## 2. Upstream data the Library reads

All of it is **derived, never stored**. Port the derivations, not a snapshot.

### 2.1 `Franchise` accessors

| Accessor | Definition |
|---|---|
| `displayTitle` | `title.shelfShortened` — see §2.3. Used by **every** shelf card and row. The raw `title` is used only for accessibility labels and Search. |
| `effectiveStatus` | `status ?? subscription?.status ?? .planned` |
| `kindWord` | `source == .tmdb ? "TV" : "Anime"` |
| `year` | premiere year of the earliest dated part (`Int?`) |
| `timeAnchor` | `.utcDate` for TMDB (date-only), `.local` for AniList |
| `portraitArt` | `images.portrait ?? nonEmpty(cover)` |
| `landscapeArt` | `images.landscape ?? legacyBanner(banner, cover:)` where `legacyBanner` returns nil if `banner == cover` (older writers copied the poster into `banner`) |
| `wideArt` | `WideArt(landscape:portrait:)` → `{url: landscape ?? portrait, portraitSource: landscape == nil}` |
| `releasingPart` | the part currently broadcasting: among `parts.filter(isReleasing)`, the one with the soonest `nextAiringAt`; else the most recently aired |
| `resumePart` | in episodic (season/ONA/OVA) sequence order: first part with `0 < progress < available`; else the first unstarted part *after* the highest completed sequence; else the earliest part with anything left. `available(p) = p.isUpcoming ? 0 : (airedEpisodes > 0 ? airedEpisodes : totalEpisodes)` |
| `currentPart` | `releasingPart ?? resumePart ?? first episodic part that is not complete` |
| `continueBacklog` | `max(0, available(resumePart) − resumePart.progress)`; 0 when `resumePart == nil` |
| `lastAiredSortKey` | `releasingPart?.lastAiredAt ?? 0` — **the catalogue's raw field.** Deliberately used by the Library (calm shelves; an hour of drift is invisible) and forbidden anywhere live. |
| `nextAiringSortKey` | `releasingPart?.nextAiringAt ?? .max` |
| `tracksAirings` | `effectiveStatus != .planned` (gates Schedule/Today, not the Library) |
| `watchContext(part:episode:)` | movie → `part.canonicalLabel`; multi-part franchise → `"<label> · Episode <n>"`; single-part → `"Episode <n>"` |

### 2.2 `FranchisePart` accessors used here

| Accessor | Definition |
|---|---|
| `isUpcoming` | `status == "NOT_YET_RELEASED"` |
| `isReleasing` | catalogue flag |
| `episodesBehind` | `isReleasing ? max(0, airedEpisodes − progress) : 0` |
| `provenAiredCount(now:)` | not releasing → `airedEpisodes`; else `max(airedEpisodes, highest episode whose airDate is strictly before today, highest airings slot with at <= now)` |
| `renderableEpisodeCount(now:)` | `totalEpisodes` when known; else `max(provenAired, progress, provenAired+1 if releasing && nextAiringAt != nil)` |
| `markTarget(now:)` | `isReleasing ? provenAiredCount(now:) : renderableEpisodeCount(now:)` |
| `wideArt(within: f)` | `WideArt(landscape: part.landscapeArt ?? f.landscapeArt, portrait: part.portraitArt ?? f.portraitArt)` |
| `premiereAt` | `isUpcoming ? nextAiringAt : nil` |

### 2.3 `String.shelfShortened`

```
1. trim whitespace
2. if it ends with "-" and contains " -", cut at the first " "  →  drops a "-Subtitle-" wrapper
3. trim the character set  " -–—:"  from both ends
4. if the result is longer than 40 characters, for each separator in [": ", " – ", " — ", " - ", " ("]
   in that order: if it occurs at index >= 12, return everything before it
5. otherwise return the string
```
("Re:ZERO -Starting Life in Another World-" → "Re:ZERO".)

### 2.4 `AppModel` shelving

**`libShelf(of:) -> {planned, comingBack, watching, finished}`** — one show, one shelf:

```
if effectiveStatus == .planned  -> .planned
if effectiveStatus == .watching -> .watching        // the user's own word outranks every derived signal
announced = upcoming.isFutureInstallment && !upcoming.hasArrived(now)   // false when upcoming == nil
if announced || nextPremiere(of: f) != nil -> .comingBack
else -> .finished
```

* `isFutureInstallment` is true for server statuses `upcoming_dated`, `announced`,
  `announced_no_date`, `rumored`.
* **`hasArrived(now:)`** — only meaningful for a DAY-precision window: rebuild `yyyymmdd` from
  `releaseSortKey.value`, interpret it in **UTC**, and return true when its UTC day is strictly
  before today. *Why it exists (quote the source): "the catalogue's curated note can outlive the
  premiere by weeks … Mushoku Tensei sat there reading 'Returns today' two months into its third
  season."* A show whose dated return has passed drops out of `comingBack` into `finished`.
* `nextPremiere(of:)` = `min` of `parts.compactMap(premiereAt).filter { $0 > now }`.

**`libraryShelves`** — `[.planned, .comingBack, .watching, .finished]` in that enum order, empty
shelves omitted, each sorted by `sortedForShelf`:

| Shelf | Order |
|---|---|
| `.watching` | `lastAiredSortKey` **descending**, ties by `title` case-insensitive ascending |
| `.comingBack` | `comingBackSortKey` ascending; ties: higher `precision` first; then title. Key = dated premiere → `(y*10000+m*100+d, 3)` read in the franchise's own calendar; else `upcoming.releaseSortKey`; else `(Int.max, 0)` |
| `.planned`, `.finished` | title case-insensitive ascending |

**`watchingShelf`** (shared with Today) — every `.watching` show that has a `shelfState`, ordered
by state then by an intra-state key:

| `ShelfState` (rawValue) | Admission test | Tie-break |
|---|---|---|
| `.newEpisode` (0) | `releasingPart.behind(now, anchor) > 0` **and** `now − lastAired(now, anchor) <= outNowWindow` | `lastAiredSortKey` desc |
| `.backlog` (1) | `resumePart != nil` | `continueBacklog` desc |
| `.airingWait` (2) | `releasingPart.isCaughtUp` and `nextAiring(now) != nil` | `nextAiringSortKey` asc |
| `.premiereSoon` (3) | `nextPremiere(of:) − now <= 45 days` | `nextPremiere` asc |

**`outNow`** — used only as the `unwatchedOnly` predicate in All titles:
franchises where `tracksAirings` and `releasingPart != nil`, with `behind(now, anchor) > 0` (or in
the `justCaught` grace set) and `now − lastAired(now, anchor) <= outNowWindow`, sorted by
`lastAired(now:)` descending.

**Freshness / phase** (`AppModel+States`):

| Property | Definition |
|---|---|
| `isRefreshing` | `loading && !library.isEmpty` |
| `sectionFailed` | `loadError && !library.isEmpty` |
| `staleSince(.catalogue)` | timestamp of the last load if older than **24 h**, else nil |
| `emptyStateCopy` | library empty & `loadError` → `isOnline ? serverNoCache : offlineNoData`; otherwise `emptyAccount` |

---

## 3. `LibraryFacts.swift` — the vocabulary

### 3.1 `LibrarySection`

Five buckets. Four map 1:1 onto `LibShelf`; the fifth exists because *"coming back" is two
different facts wearing one word*.

| Case | `label` | `rank` (screen order) |
|---|---|---|
| `.returning` | `"Returning"` | 0 |
| `.watching` | `"Watching"` (= `Copy.Status(.watching)`) | 1 |
| `.planned` | `"Planned"` | 2 |
| `.announced` | `"Announced"` | 3 |
| `.finished` | `"Watched"` (= `Copy.Status(.completed)`) | 4 |

*Why `.announced` sits at rank 3 and not next to `.returning`*: "It is the weakest signal on the
screen (a sequel exists, nobody has said when), so it must not sit between the dated returns and
the shows you are actually living with: seven 'No date announced' rows pushed WATCHING a full
screen down."

**`LibraryShelving.section(of:appModel:)`** — the ONE classifier both Library surfaces route
through: map `libShelf` directly, except `.comingBack` → `ReturnFact.of(...).dated ? .returning :
.announced`.

### 3.2 `ReturnFact` — "when does it come back"

```swift
struct ReturnFact { let text: String; let dated: Bool; let soon: Bool }
static let soonHorizon: Int64 = 60 * 86_400 * 1000        // 60 days, in MILLISECONDS
```

* `dated == false` only for **"No date announced"** and for a **rumour**. It is what keeps a show
  out of a section headed RETURNING.
* `soon` is **the one flag that decides whether this fact is amber**, on the shelf and in the
  catalogue alike: `soon = (at − now) <= soonHorizon` when an instant is known, `false` otherwise.
  A window with no instant behind it is never `soon` ("the colour rule has nothing to measure").
  It replaced an older `accentAllowed` scheme that rationed amber **by row index** at accessibility
  sizes — "the fourth returning row printed the identical fact in a different colour from the
  third, with nothing in the content to explain it."

**Algorithm — `ReturnFact.of(f, appModel)`**, evaluated against `appModel.nowMinute` (the clock
truncated to the minute, so captions do not re-derive on the 20-second tick):

```
1. at = appModel.nextPremiere(of: f)
   if at != nil:  text = TemporalCopy.returns(at: at, now: now, source: f.source)
                  dated = true, soon = (at - now <= 60d)
2. if f.upcoming?.isRumored (server status == "rumored"):
                  text = Copy.Library.rumored(next: upcoming.next)
                  dated = false, soon = false
3. guard upcoming?.releaseWindow with precision != .unknown and parsable parts,
   else -> text = TemporalCopy.returns(at: nil, ...) == "No date announced", dated = false, soon = false
4. precision == .day AND parts.year == current UTC year:
        build the UTC midnight of (y, m, d), at = its epoch ms
        text = TemporalCopy.returns(at: at, now: now, source: .tmdb)   // friendly day form
        dated = true, soon by horizon
5. precision == .day or .month:
        at = UTC midnight of (y, m, 1)
        text = "Returns " + monthYear(at, anchor: .utcDate)            // "Returns Oct 2026"
        dated = true, soon by horizon
6. otherwise (quarter / year) — a WINDOW, printed from the server's own prose:
        prose = upcoming.displayRelease.trimmed
        if prose is exactly 4 characters and parses as an Int:  text = "Returns 2027"
        else if 1 <= prose.count <= 20:  text = "Returns " + lowercaseFirstCharacter(prose)
        else: text = "Returns " + String(parts.year)
        dated = true, soon = false
```

Notes that must survive the port:

* Step 4 uses `source: .tmdb` **deliberately** — a curated window is a calendar date and must be
  read date-only, whatever the franchise's own source is. Step 4/5 build the date in **UTC**
  (`utcDay`) because "a device in UTC+9 reads 'October 2026' as September".
* Step 6 lower-cases only the first character (`"Summer 2027"` → `"Returns summer 2027"`), never
  the server's capital dropped mid-sentence.
* Step 6's quarter month is an **ordering device only** — "Summer 2027" sorts as July and must
  never be printed as a month.
* **The rule the whole type exists for:** one grammar, at the shortest honest precision. Four
  phrasings of one fact ("Returns Oct 2026" / "Returns in 2027" / "Returns Jan 2027" /
  "Returns Late 2027") once appeared within six rows. Board 09's rule: *drop a fact, never
  truncate one.*

**`TemporalCopy.returns(at:now:source:)`** (day ladder, evaluated in the source's anchor calendar):

| `dayDiff(ts, now)` | Output |
|---|---|
| `nil` timestamp | `"No date announced"` |
| `< 0` | `"Returned <dateWord>"` |
| `0` | `"Returns today"` |
| `1` | `"Returns tomorrow"` |
| `2…6` | `"Returns <weekday long>"` |
| else | `"Returns <dateWord>"` |

`dateWord` = `"Aug 28"` in the current year, `"Aug 28, 2027"` otherwise — always through a
locale-ordered `MMMd` / `MMMdyyyy` skeleton, **never string-joined** (a hand-joined form produced
`"31 Mar, 2013"` on day-first locales).

**`Copy.Library.rumored(next:)`** = `next` non-empty ? `"<next> rumored"` : `"Rumored"` →
e.g. `"Season 3 rumored"`. Never a date, never amber.

### 3.3 `LibraryDates.monthYear(ts, anchor)`

`Formatting.fmtMonthYear` → the `"MMMyyyy"` skeleton, locale-ordered → `"Oct 2026"`. Read in the
supplied anchor's calendar so a TMDB date-only instant and an AniList instant each land in the
month they belong to.

### 3.4 `LibraryRowFacts` — the two lines under a row title

```swift
struct LibraryRowFacts { var lead: String?; var meta: String? }
```

* `lead` renders **amber** (`rowMetaLead` / `shelfCaption` in `accent`) and is only ever a real
  NEXT STEP.
* `meta` renders **grey** (`rowMeta` / `shelfCaption` in `textSecondary`).
* A fact never appears in both. A section's own heading is never repeated in the row under it.

#### `root(f, section:, appModel:)` — the Library ROOT (a shelf, not a catalogue)

```
.returning:  fact = ReturnFact.of(f)
             fact.soon ? (lead: fact.text)   : (meta: fact.text)
.announced:  (meta: ReturnFact.of(f).text)               // never amber — the ABSENCE of a next
                                                          // step is not a next step
.watching:   1. if rewatch(f) != nil          -> (lead: rewatch)      // a step the user chose
             2. if nextStep(f, now) != nil    -> (meta: nextStep)     // the step rides the GREY line
             3. if (currentPart?.isUpcoming ?? true):
                    fact = ReturnFact.of(f)
                    if fact.dated -> fact.soon ? (lead: fact.text) : (meta: fact.text)
             4. (meta: standing(f) ?? "Caught up")
.planned, .finished:
             1. if rewatch(f) != nil -> (lead: rewatch)
             2. (meta: settled(f, now) ?? identity(f))
```

Two comments to preserve as behaviour:

* Step 2 of `.watching` deliberately puts the step on the **grey** line: *"Behind-counts and amber
  belong to Today — the urgency pact — so the Library says where you stand and never how far behind
  you are."*
* `identity()` is **unreachable** from `.watching`. Before that, "three consecutive rows answered
  'what do I owe' with the year the show came out — 'Attack on Titan · Anime · 2013' — because
  `standing()` refused to speak without a current part."

#### `catalogue(f, appModel:, stateIsGiven: Bool = false, compact: Bool = false)` — ALL TITLES

A catalogue mixes every status, so **the list state is itself a fact and is always stated** —
unless `stateIsGiven` (a status filter is active, so the chip above already says it).

```
state   = stateIsGiven ? nil : Copy.Status(f.effectiveStatus)
joined(x)  = state == nil ? x : (compact ? state : "\(state) · \(x)")
lead(full) = compact ? (shortStep(f, now) ?? full) : full

1. if progress(f, now) != nil     -> (lead: lead(progress), meta: compact ? nil : state)
2. if rewatch(f) != nil           -> (lead: lead(rewatch),  meta: compact ? nil : state)
3. fact = ReturnFact.of(f)
   if fact.dated AND LibraryShelving.section(of: f) == .returning:
        fact.soon -> (lead: fact.text, meta: compact ? nil : state)
        else      -> (meta: joined(fact.text))          // "Watched · Returns Oct 2026"
4. if settled(f, now) != nil      -> (meta: joined(settled))
5. if standing(f) != nil          -> (meta: joined(standing))
6. (meta: state ?? identity(f))
```

Branch 3's `section == .returning` guard exists because *"'Returns' is the wrong verb for a Planned
show you never started ('Planned · Returns 9 Oct') and for one you are mid-way through
('Watching · Returns today')."*

`compact: true` is the **poster grid** asking the same question in a ~136-pt cell. It is not a
second implementation and **must not reach a different conclusion**: same branches, shortest honest
form of each fact, joined second fact dropped. (The bug this fixed: "the wall said 'Episode 1 next'
in amber where the list said 'Watched' in grey for the same show one segment apart, and neither
mentioned the rewatch that was actually in progress. A user reads that as the app losing their
data.")

#### Helper functions

| Function | Definition | Output examples |
|---|---|---|
| `standing(f)` | `effectiveStatus == .watching ? "Caught up" : nil` — *no* `currentPart` guard | `"Caught up"` |
| `listState(f)` | `Copy.Status(f.effectiveStatus)` | `"Watching"`, `"Planned"`, `"Watched"`, `"Paused"`, `"Dropped"` |
| `rewatch(f)` | requires `RewatchStore.shared.activeSession(for: f.id)` **and** `f.currentPart`; returns `"<session.title> · <Copy.Progress.episodeNext(p.progress+1)>"` | `"Second watch · Episode 7 next"` |
| `progress(f, now)` | nil unless `.watching` and `currentPart` exists and `!isUpcoming`. Then: rewatch wins; else if `isReleasing` → `episodesBehind > 0 ? "3 episodes behind" : nil`; else `nextStep` | `"3 episodes behind"` |
| `nextStep(f, now)` | nil unless `currentPart` exists, `!isUpcoming`, `markTarget(now) > progress`; then `"<watchContext> next"` | `"Season 7 · Episode 5 next"` |
| `shortStep(f, now)` | same guards minus markTarget; `isReleasing` → behind-or-nil; else `markTarget > progress ? "Episode 5 next" : nil` | `"Episode 5 next"` |
| `settled(f, now)` | `.completed` and `RewatchStore.summary(f.id).completedCount >= 2` → `Copy.Progress.watchedTimes(n)`; else nil | `"Watched twice"`, `"Watched 4 times"` |
| `identity(f)` | `year == nil ? kindWord : "<kindWord> · <year>"` | `"Anime · 2021"`, `"TV"` |

`Copy.Status` mapping: `watching→"Watching"`, `planned→"Planned"`, `completed→"Watched"`,
`paused→"Paused"`, `dropped→"Dropped"`. **"Finished" and "Completed" are not in this app's
vocabulary.**

`Copy.Progress` strings used here (all verbatim, note the non-breaking spaces `U+00A0`):

| Function | Result |
|---|---|
| `episodeNext(n)` | `"Episode <n> next"` |
| `next(context:)` | `"<context> next"` |
| `behind(n)` | `"<n>\u{00A0}episode(s)\u{00A0}behind"` — the numeral is bound to its noun with an NBSP; **wraps happen between facts, never inside one** |
| `caughtUp` | `"Caught up"` |
| `watchedOf(w, t)` | `"<w> of <t> watched"` |
| `watchedTimes(n)` | `n<1 "Not watched yet"`, `1 "Watched once"`, `2 "Watched twice"`, else `"Watched <n> times"` |
| `ordinalWatch(n)` | `"First watch"…"Tenth watch"`, else `"<n>th watch"` with correct ordinal suffix |

`Copy.plural(n, one, many)` = `"<n>\u{00A0}<noun>"`; `Copy.titles(n)` → `"1 title"` / `"30 titles"`
(with NBSP).

---

## 4. Screen chrome shared by both Library screens

### 4.1 The ambient wash

An `ArtBackdrop` pinned to the top, ignoring the top safe area, drawn **behind** the scroll view.

```
height    = 320   (ThemeMetrics.rootWashHeight)
intensity = 0.4   (ThemeMetrics.rootWashIntensity)
```

Composition, top-aligned, all clipped to `height`:
1. the artwork, `contentMode = fill`, centred, decoded at `maxPixel 320`, **blurred 56 pt with
   `opaque: true`**, at `opacity 0.70 * intensity` (= 0.28). Cropped to fill **before** blurring.
2. `LinearGradient(base@baseTop → base@baseMid → clear)` top→bottom, where
   `base = explicitTint ?? paletteTint ?? #432D21`,
   `baseTop = artSettled ? 0.60*intensity : max(0.60*intensity, 0.55)`,
   `baseMid = artSettled ? 0.10*intensity : max(0.10*intensity, 0.12)`.
   *Why the floor:* at a list root's 0.4 the ember composited to ≈rgb(38,36,32) and "the status band
   reads BLACK for the whole first load, then jumps to twice the luminance when the art decodes".
3. `LinearGradient(accent@0.07*intensity → clear)` — a constant breath of brand warmth so every
   root shares one atmosphere.
4. handover: `clear → canvas@0.55 at 0.55 → canvas at 1.0`.

Transitions on `resolvedTint` use `uiGentle`. The whole thing is `allowsHitTesting(false)` and
`accessibilityHidden(true)`.

**Root wash source (`washArtwork`)** — "the room is lit by the thing you are looking at":
```
franchise = heroItems.first ?? sections.first?.items.first ?? library.first
return first non-empty of [ franchise.resumePart?.landscapeArt,
                            franchise.landscapeArt,
                            franchise.resumePart?.portraitArt,
                            franchise.portraitArt ]
```
When the result is `nil` the root passes `tint: ThemeColor.accent` — *"With no artwork in the
library there is nothing for it to be ABOUT, so first run gets the app's own colour."*

**All titles** receives the root's already-computed `washArt` through the push and falls back to
`results.first?.portraitArt ?? library.first?.portraitArt`. Without the hand-off the pushed screen
"lit itself from its first alphabetical row … and the push visibly changed the room's light."

### 4.2 The scroll-edge chrome (top veil)

Both screens use `scrollEdgeChromeBody(top: true, bottom: true, softTop: true, topRaised:,
topHold:)` plus a hidden system toolbar background.

| | Root | All titles |
|---|---|---|
| `topHeight` | `topSafeInset + 22` | `topSafeInset + 52` |
| `topHold` | `inlineBarBottom` = `topSafeInset + 44` | `searchChromeBottom` (below) |
| probe threshold | `contentMinY < inlineBarBottom` | `contentMinY < searchChromeBottom` |

`searchChromeBottom = searchPresented ? topSafeInset + 52 : inlineBarBottom + 52` — when the search
field takes focus the inline title collapses, so the hardened hold shrinks with it.

Two veil layers are **both mounted** and cross-fade on `topRaised` with `uiGentle`:

* **soft (at rest)** — `canvas` at 0.55 → 0.30 at 50 % → 0 at 100 %, over an `ultraThinMaterial`
  masked by black 0.6 → 0.3 → clear.
* **hardened (scrolled)** — height `topHold + 28`. Canvas gradient at
  `barOpacity` (0.74) held from 0 to `hold = topHold/height`, then `barOpacity*0.45` at
  `hold + (1−hold)*0.45`, then 0 at 1.0; the blur mask holds full black through the whole hold.
  **Under Reduce Transparency the bar opacity becomes 1.0** and the material layer is dropped
  entirely — there is no blur to keep a row title from reading as a row title.

*Why 0.74 and not 1.0 (quote):* "at 1.0 the top ~100 pt of every scrolled screen was a flat #09090B
rectangle with a 28-pt edge ('the top area becomes pure black', user, 3 Sep) — and the
`.ultraThinMaterial` painted under it was doing nothing at all."

**Bottom chrome** (both screens): a 64-pt band `clear → canvas@0.25 @0.55 → canvas@0.75 @0.85 →
canvas @1.0`, blur mask restopped identically, followed by 180 pt of solid canvas offset downwards
so the floating tab bar has an opaque ground to refract. `contentMargins(.bottom, 76)`.

**The probe itself** is a geometry read, not `onScrollGeometryChange`: a `Color.clear` background
on the scroll content reporting `frame(in: .global).minY`, with `if raised != raisedTop` guarding
the write. *"`onScrollGeometryChange` never fires on the iOS 27 simulator."* On Android use a
`NestedScrollConnection` or `LazyListState.firstVisibleItemScrollOffset` — but keep the boolean
guard so a scroll frame does not invalidate the screen.

### 4.3 Freshness (both screens)

At the very top of the scroll content, a zero-height `Color.clear` carrying the `.freshness(.catalogue)`
modifier, horizontally padded by the gutter. It renders:

* a **`StaleStrip`** below it when `staleSince(.catalogue) != nil` (i.e. last load > 24 h ago):
  a 28-pt-min row, `arrow.triangle.2.circlepath` at 11 pt regular in `textTertiary`, then
  `"Updated <elapsed>"` in `metadata`/`textTertiary`, wrapping at AX sizes. Vertical padding 8.
  VoiceOver reads the spelled-out form: `"Updated 8 hours ago"`, never `"8h"`.
* a **`RefreshIndicator`** in the top-trailing toolbar slot while `isRefreshing && !pullDriving`
  (appears only after 400 ms in flight), with the iOS-26 glass capsule suppressed.
* `uiGentle` animations on both `isRefreshing` and `staleSince`.

Elapsed ladder (`Copy.elapsedWord`): `< 1 min` → `"just now"`; `< 60 min` → `"<n> min ago"`; same
day → `"<n>h ago"`; `−1 day` → `"yesterday"`; `−2…−6` → weekday name; else `dateWord`.

### 4.4 Pull to refresh

`previouslyRefreshable(threshold: 80) { await appModel.reload() }` on both screens: the platform
refresh control, **plus** one `.refreshArmed` haptic fired the first time the pull distance reaches
80 pt *while the finger is down* (re-armed only after the pull falls back below 24 pt). A momentum
overshoot with no finger down must **not** buzz.

The root also tracks `pullDriving` from the scroll phase (`tracking || interacting`) so the custom
spinner yields to the system one during a pull.

---

## 5. The Library root (`LibraryView`)

### 5.1 Inputs

```swift
LibraryView(onOpenDetail: (franchiseId, zoomID) -> Void,
            onAddShow: () -> Void,
            requestedAll: Binding<AllTitlesRoute?>,
            popSignal: Int)
```

`AllTitlesRoute` is `Hashable, Identifiable`:

```swift
struct AllTitlesRoute { var status: WatchStatus?; var returning: ReturnScope?; var unwatchedOnly = false
                        var id = "\(status?.rawValue ?? "-")/\(returning?.rawValue ?? "-")/\(unwatchedOnly)" }
```

Two independent axes on purpose: *"the root's buckets are not all statuses: `Returning` and
`Announced` are facts about a show's future, not list states."*

### 5.2 Per-render resolution (performance contract)

`body` resolves, **once**, in this order, and passes the results down. Do not recompute in
children.

```swift
let sections      = rootSections()
let heroItems     = appModel.watchingShelf.filter { $0.resumePart != nil }
let ambientArtwork = washArtwork(sections, heroItems: heroItems)
```

*Why:* "`sections` used to be recomputed by the wash and by the section loop, and each pass ran
`ReturnFact.of` twice per title."

`heroItems` is `watchingShelf` **filtered to titles with a real `resumePart`** — "the hero is an
instruction to continue, so only a title with a real resume part may enter it."

### 5.3 `rootSections()`

`AppModel.libraryShelves` stays the source of truth for membership and order; the only work done
here is **splitting `comingBack` in two** (because "a heading that says RETURNING may not contain a
show whose own detail screen says 'Finished' and 'No date announced'"):

```
for shelf in appModel.libraryShelves:
    .comingBack -> partition its franchises, IN ORDER, by ReturnFact.of(f).dated
                   emit RootSection(.returning, dated)   if non-empty
                   emit RootSection(.announced, undated) if non-empty
    .watching   -> RootSection(.watching,  shelf.franchises)
    .planned    -> RootSection(.planned,   shelf.franchises)
    .finished   -> RootSection(.finished,  shelf.franchises)
finally: sort by LibrarySection.rank    // Returning, Watching, Planned, Announced, Watched
```

The partition **preserves** `comingBack`'s soonest-first order inside each half, and calls
`ReturnFact.of` exactly once per title.

### 5.4 Root layout

```
ZStack(topAligned):
  canvas (ignoresSafeArea)
  ArtBackdrop(...)  .ignoresSafeArea(edges: .top)
  ScrollView (indicators hidden, tabBarContentMargin, previouslyRefreshable):
    VStack(alignment: .leading, spacing: 0):
       [freshness anchor, horizontal gutter]
       if sectionFailed: InlineNotice(...)      padding: horizontal gutter, top 12
       SkeletonGate(isLoading: loading && library.isEmpty):
           skeleton   |   library.isEmpty ? EmptyState (centred) : root(sections, heroItems)
```

* Navigation title: `"Library"`, **inline** display mode, toolbar visible, toolbar background
  hidden. *"A large title collapses on the first scroll and moves the top safe area ~50 pt
  mid-flight; an inline one holds still over the wash."*
* **Trailing bar button**: text `Copy.titles(library.count)` → `"30 titles"`, `.plain` button
  style, `listAction` type (Outfit SemiBold 13), `textSecondary` ink, `minWidth/minHeight 44`.
  Tap → `all = AllTitlesRoute()` (no filters).
  a11y label `"All titles, 30 titles"`, hint `"Opens your whole library, with search, sorting and filters"`.
  On iOS 26 the toolbar item's shared glass capsule is suppressed.

### 5.5 The root content stack

```
VStack(alignment: .leading, spacing: 30)          // ThemeMetrics.sectionGap
    if !heroItems.isEmpty:  LibraryContinueShelf(items: heroItems, ...)
    ForEach(shelves) { LibraryLandscapeShelf(title: section.key.label, items: supportingItems(section)) }
.padding(.top, 20)                                // LibraryRootMetrics.contentTopPadding
```

where `shelves = sections.filter { $0.key != .watching || heroItems.isEmpty }`.

> **The Watching bucket belongs to the Continue shelf.** Its own quiet shelf renders *only* when
> the Continue shelf cannot — i.e. a Watching list where nothing has a `resumePart`.

`supportingItems(section)` takes **`prefix(6)`** (`supportingPreviewCount`) and maps each franchise
to `LibraryLandscapeItem(franchise:, lead:, meta:)` from `LibraryRowFacts.root(f, section:)`.
`lead` and `meta` are carried **separately, never merged** — "the old merged `caption` is how this
screen came to render 'Returns today' in grey while Today drew the identical class of fact in
accent."

### 5.6 `LibraryContinueShelf` — Up Next

The lead surface. Apple TV's *Up Next* / Netflix's *Continue Watching* grammar: a horizontal shelf
of landscape cards, each with progress drawn on the art and the next episode named beneath. It
replaced a cover-flow spotlight — *"a carousel from another era … it spent the root's first 300 pt
on ONE show while hiding the rest behind a swipe."*

```
VStack(alignment: .leading, spacing: 10)                     // ThemeMetrics.labelGap
  SectionHeaderRow("Continue watching", action: onViewAll)   // padded horizontally by 16
  ScrollView(.horizontal)
    LazyHStack(alignment: .top, spacing: 12)                 // ThemeMetrics.shelfGap
      ForEach(items) where f.resumePart != nil:
        LibraryContinueCard(franchise: f, part: resumePart)
          .containerRelativeFrame(.horizontal, count: 5, span: 4, spacing: 12)
          .franchiseQuickActions(f)
    .scrollTargetLayout()
  .contentMargins(.horizontal, 16, for: .scrollContent)
  .scrollTargetBehavior(.viewAligned)
  .scrollIndicators(.hidden)
  .scrollClipDisabled()
  .fixedSize(horizontal: false, vertical: true)
```

**Card width.** The container is the scroll content region, i.e. `screenWidth − 2×16`. With
`count = 5, span = 4, spacing = 12`:

```
unit  = (containerWidth − spacing*(count−1)) / count
width = unit*span + spacing*(span−1)
```
On a 393-pt-wide device: container 361 → unit 62.6 → **width ≈ 286.4**, height `286.4 × 9/16 ≈ 161`.
(These are exactly the skeleton's `continueSkeletonWidth 286` / `continueSkeletonHeight 161`, which
is how to verify a port.) The next card therefore *peeks* — that peek is the point.

**Accessibility text sizes** (`typeSize.isAccessibilitySize`, i.e. AX1–AX5): `count: 1, span: 1`
— one full-width card per screen.

**`SectionHeaderRow` anatomy** (shared, `Primitives+States.swift`) — when an `action` is supplied
and `inlineAction == false`, **the title itself is the button**:

```
HStack(firstTextBaseline, spacing 8):
  Button:
    HStack(center, spacing 6):
      [optional 5-pt accent dot]           // dot == "newly changed"; Library never sets it
      Text(title)  sectionTitle / textPrimary, lineLimit 1, minimumScaleFactor 0.85
      [optional count]  metadata / textTertiary, monospacedDigit
      Image("chevron.forward") 14 pt semibold, textTertiary, a11y-hidden
    style: pad vertical 10, minHeight 44, contentShape rect, opacity 0.55 when pressed (uiPress)
  .padding(.vertical, -10)                 // target grows, layout height does not
  Spacer(minLength: 8)
.zIndex(1)                                 // header paints AND hit-tests above later siblings
```

**There is no "See all" word.** `actionLabel` only feeds the accessibility label:
`"<title>, <actionLabel ?? "See all">"` — so the Continue header speaks
`"Continue watching, See all"` and the Watching shelf speaks `"Watching, See all"`, while on
screen both show only a title and a chevron. This is the Apple TV / Netflix shelf grammar and it is
also what keeps amber off the header.

Tapping the Continue header → `all = route(for: .watching)` = `AllTitlesRoute(status: .watching)`.

### 5.7 `LibraryContinueCard`

```
Button(OverArtPressStyle):
  VStack(alignment: .leading, spacing: 8):
    ProgressBanner(url: wide.url, portraitSource: wide.portraitSource,
                   progress: total > 0 ? ratio : nil,
                   zoomID: "lib-hero/<franchiseId>")
    VStack(alignment: .leading, spacing: 2):
      Text(franchise.displayTitle)  rowTitle / textPrimary, lineLimit 1...2,
                                    minimumScaleFactor 0.85, leading aligned
      Text(next)                    rowMeta  / textSecondary, lineLimit 1
  .contentShape(Rectangle())
```

Derivations:

```
wide  = part.wideArt(within: franchise)
total = max(part.totalEpisodes, part.airedEpisodes, part.progress)
ratio = total > 0 ? Double(part.progress)/Double(total) : 0
next  = franchise.watchContext(part: part, episode: part.progress + 1)
        // upgraded to "<context> · <episodeTitle>" ONLY when the server's own pointer agrees:
        if let cw = franchise.continueWatching,
           cw.mediaId == part.mediaId,
           cw.episode.number == part.progress + 1,
           let title = EpisodeCopy.title(cw.episode.title, franchise: franchise.title)
        -> "\(context) · \(title)"
```

`continueWatching` is *user-specific and never unaired*, so this is spoiler-safe by the row model's
own rule (the NEXT episode's title is always shown).

`EpisodeCopy.title(raw, franchise:)` sanitiser — returns `nil` (no title) when the catalogue's
string is not really a title:
1. collapse every whitespace run to one space;
2. strip a leading `^[Ee]pisode\s*\d*\s*[-–—:·]?\s*`;
3. trim `" -–—:·"` from both ends; empty → nil;
4. nil if the lower-cased result **starts with** the franchise title (AniList's episode-1 slots
   embed the show name);
5. nil if it still starts with `"episode"`;
6. nil if it ends with `"trailer"`, `"teaser"`, `"promo"`, `" pv"` or `"preview"`.

**`ProgressBanner`** (shared — the ONE 16:9 art-with-progress card; the season screen's header is
the same view):

```
ZStack(bottom):
  RoundedRect(radius 22, continuous).fill(surfaceRaised)
  LandscapeArt(url:, portraitSource:, maxPixel 900)
  LinearGradient(clear -> scrim) height 56, hit-testing off
  if progress != nil: ProgressBar(value:).padding(horizontal 12).padding(bottom 12)
.aspectRatio(16/9, .fit)
.clipShape(radius 22)
.overlay(strokeBorder(posterEdge, 1))
.shadow(.art)                      // black 55 %, radius 12, y 7
```

**`LandscapeArt`** — the rule "landscape frames never `.fill` a portrait cover":

* `portraitSource == false`: one image, `contentMode = fill`, aligned `.top`, `maxPixel 560/900`.
* `portraitSource == true`: a **composite** — the same image `fill`ed at `maxPixel 160`, blurred
  28 pt `opaque`, overlaid with `black @ 0.32`; then the sharp image `fit`ted at the real
  `maxPixel`, centred, padded vertically 8, with a contact shadow `black 45 %, radius 8, y 4`.
  *"Without it the two read as one badly-decoded image."*

**`ProgressBar`** — 3-pt-tall capsule track in `strokeStrong`, fill in `accent`, fill width
`max(3, trackWidth × clamp(value, 0, 1))` so a started season is never zero-width. It is
**wordless by design** — it replaces "11 of 24 watched" everywhere a bar can be drawn. It is
accessibility-hidden unless the caller supplies a `spoken` string (here it does not; the card's
combined label carries the count).

Accessibility for the whole card: one combined element,
label = `[franchise.title, next, total > 0 ? "\(progress) of \(total) watched" : nil]` joined with
`", "`, hint = `"Opens the show"`. **Note the spoken title is the full `title`, not
`displayTitle`.**

Press feedback (`OverArtPressStyle`): opacity 0.88 and scale 0.99 on `uiPress`; under Reduce
Motion, opacity 0.72 and **no scale**.

Tap → `onOpenDetail(f.id, "lib-hero/\(f.id)")`.

Long-press → the shared franchise context menu (§5.9).

### 5.8 `LibraryLandscapeShelf` — the four quiet shelves

Identical scroller mechanics to the Continue shelf, with `count: 2, span: 1` (→ `unit = (361−12)/2
= 174.5`, matching `landscapeSkeletonWidth 174`), and `count: 1` at accessibility sizes.

Each item is a **`BannerCard`**:

```
BannerCard(title: franchise.displayTitle,
           lead: item.lead, meta: item.meta,
           art: franchise.wideArt.url,
           portraitSource: franchise.wideArt.portraitSource,
           zoomID: "lib/<id>") { onOpen(franchise) }
```

`BannerCard` anatomy (one geometry, app-wide):

```
Button(OverArtPressStyle):
  VStack(alignment: .leading, spacing: 8):
    banner:  ZStack { RoundedRect(22).fill(surfaceRaised); LandscapeArt(art, portraitSource, maxPixel 560) }
             .frame(maxWidth: .infinity).frame(height: 104)
             .clipShape(22).overlay(strokeBorder(posterEdge, 1)).shadow(.art)
    VStack(alignment: .leading, spacing: 2):
      Text(title.shelfShortened)   shelfTitle / textPrimary
                                   lineLimit 1...2, minimumScaleFactor 0.82, allowsTightening
      if caption != nil:
        Text(caption)              shelfCaption
                                   foreground: lead != nil ? accent : textSecondary
                                   lineLimit 2, truncationMode .tail
```

`caption = lead ?? meta`. **This is the one place the amber decision is made for a shelf card**, and
it is made from which of the two fields is populated — which is why `LibraryRowFacts` must never
merge them.

a11y: combined element, label = `[title, caption]` joined `", "` (again the **full** title),
hint `"Opens the show"`.

Tap → `onOpenDetail(f.id, "lib/\(f.id)")`. Shelf header tap → `route(for: section.key)`:

| Section | Route |
|---|---|
| `.returning` | `AllTitlesRoute(returning: .dated)` |
| `.announced` | `AllTitlesRoute(returning: .undated)` |
| `.watching` | `AllTitlesRoute(status: .watching)` |
| `.planned` | `AllTitlesRoute(status: .planned)` |
| `.finished` | `AllTitlesRoute(status: .completed)` |

### 5.9 Long-press quick actions (every card and row in the Library)

`franchiseQuickActions(f, appModel:)` attaches a context menu:

1. **Only if** `f.releasingPart != nil && releasingPart.episodesBehind > 0`:
   `"Mark all <n> episodes as watched"` with symbol `text.append` → `appModel.markCaughtUp(f.id)`.
2. Five status rows in `menuOrder` = watching, planned, completed, paused, dropped; label
   `Copy.Status(option)`, symbol = `checkmark` when it is the current `effectiveStatus`, else
   `play.circle` / `clock` / `checkmark.circle` / `pause.circle` / `xmark.circle`
   → `appModel.setStatus(franchiseId:status:)`.
3. Divider.
4. Destructive `"Remove from Library"`, symbol `trash` → `appModel.removeWithUndo(f, reduceMotion:)`.

**No haptic is fired by the menu itself** — each `AppModel` command fires its own, at most one per
transaction.

### 5.10 Root states

| Condition | Render |
|---|---|
| `loading && library.isEmpty` | the skeleton (§5.11), behind `SkeletonGate` |
| `library.isEmpty` and settled | `EmptyState(appModel.emptyStateCopy, prominence: .major, primary: emptyStateAction)`, gutter-padded, `centredState(contentH:)` |
| `sectionFailed` (content on screen, last refresh failed) | `InlineNotice("Your library couldn’t refresh") { reload() }` above the content |
| otherwise | the shelves |

`emptyStateAction = appModel.loadError ? { reload() } : onAddShow` — *"the empty state's one action,
and it is always a live one."*

`centredState(contentH:)` = `frame(maxWidth: .infinity, minHeight: max(0, contentH − 90),
alignment: .center)` where `contentH` is the scroll view's own height and 90 is
`tabBarVisualHeight` (**not** `tabBarClearance`; "half of whatever is subtracted is the error").

**`EmptyState` anatomy** (`ContentUnavailableView`'s grammar on the bare canvas — *no plate, no
glyph tile, no bloom*):

```
VStack(spacing 0), frame(maxWidth: 300), then frame(maxWidth: .infinity)
  Image(systemName: copy.symbol) size 44*scaledMetric(.title3), regular, textTertiary
      .padding(.bottom, 16)   [12 for .section prominence]  a11y hidden
  Text(copy.title)       showTitleL (major) / showTitleM (section), textPrimary,
                         centred, lineLimit 3 (2 for section; unlimited at AX)
  Text(copy.supporting)  callout (major) / metadata, textSecondary, centred, padding(.top, 8)
  if a handler was supplied for a declared label:
      VStack(spacing 4).padding(.top, 20):
        primary: isRecovery ? SecondaryButtonStyle2 : PrimaryButtonStyle2, hugging (fixedSize
                 horizontally unless AX)
        secondary: TertiaryButtonStyle2
.transition(.opacity)          // "an empty state that scales in reads as a celebration of having nothing"
a11y: container, label = "<title>. <supporting>"
```

`isRecovery` is true when the primary label is `"Try again"` or `"Retry"` → quiet capsule; anything
else (e.g. `"Add a show"`) → the amber capsule.

The three copies the root can show:

| Copy | Symbol | Title | Supporting | Primary |
|---|---|---|---|---|
| `emptyAccount` | `rectangle.stack` | `Your library is empty` | `Everything you add shows up here.` | `Add a show` |
| `serverNoCache` | `exclamationmark.circle` | `Couldn’t load your library` | `Something went wrong. Try again in a moment.` | `Try again` |
| `offlineNoData` | `wifi.slash` | `You’re offline` | `Connect to the internet to load your library.` | `Try again` |

Which of the last two is chosen is decided by `SyncCenter.isOnline` (a live path monitor),
**never** by inspecting the error.

**`InlineNotice`** is a footnote line, never an alert box:
`wifi.exclamationmark` 12 pt semibold `textTertiary` + the message in `metadata`/`textSecondary` +
a `"Retry"` `InlineLinkButtonStyle` link pulled back `-12 pt` vertically and `-4 pt` leading;
`minHeight 28`, `.transition(.opacity)`. At accessibility sizes it becomes a leading-aligned VStack
(spacing 4) and the link's leading pull-back becomes `-12`.

Note the **curly apostrophe** in `"Your library couldn’t refresh"` (U+2019). Every apostrophe in
this app's copy is U+2019.

### 5.11 Root skeleton

Mirrors the composition it stands in for, so the hand-off changes content, not shape.

```
VStack(alignment: .leading, spacing: 30).padding(.top, 20)

  // block 1 — the Continue shelf
  VStack(alignment: .leading, spacing: 12)
    SkeletonLine(width 108, height 19)            .padding(.horizontal, 16)
    HStack(alignment: .top, spacing: 12) × 2:
       VStack(alignment: .leading, spacing: 8)
         SkeletonPoster(286 × 161, radius 22)
         SkeletonLine(154, 18)
         SkeletonLine(196 * 0.6 = 117.6, 12)
    .padding(.horizontal, 16).clipped()

  // block 2 — one landscape shelf
  VStack(alignment: .leading, spacing: 12)
    HStack: SkeletonLine(92, 19) … Spacer … SkeletonLine(54, 12)   .padding(.horizontal, 16)
    HStack(spacing 12) × 2:
       VStack(alignment: .leading, spacing: 8)
         SkeletonPoster(174 × 104, radius 22)
         SkeletonLine(174*0.72 = 125.3, 14)
         SkeletonLine(174*0.55 = 95.7, 12)
    .padding(.horizontal, 16)
```

Blocks are `skeleton` fill (`#F4F1EC` @ 11 %), radius 6 for lines, the given radius for posters.

**`SkeletonGate` timing — the 240/320/120 rule, implemented once:**
* nothing at all for the first **240 ms** (a fast response must never flash structure);
* once shown, the skeleton stays at least **320 ms**;
* swap to content is a **120 ms crossfade** (`uiCrossfade` = `uiReduced` = easeOut 0.12);
* the frame never blanks between them;
* while visible the skeleton **breathes**: opacity 0.88 ↔ 1.0 on `easeInOut 1.4 s` repeating and
  auto-reversing. Under Reduce Motion it is a **static 0.92** with no animation. Shimmer is refused
  by name. (Amplitude is 12 %, not 35 %: "a pulse the eye cannot ignore … on the frame the user is
  already waiting through".)
* after **800 ms** still loading, a `slow` flag flips on `uiGentle` (currently only used to allow a
  small progress view).
* a11y: the skeleton is one element labelled `"Loading"` with children ignored.

The minimum-visible window must be measured on a **monotonic** clock, not wall time.

### 5.12 Routing in and out

| Trigger | Effect |
|---|---|
| trailing bar button | `all = AllTitlesRoute()` |
| any section header | `all = route(for: key)` |
| `requestedAll` binding changes (incl. `initial: true`) | `all = route; requestedAll = nil` — a one-shot route pushed from another tab |
| `popSignal` changes | `all = nil` — **re-selecting the Library tab pops All titles**. This exists because All titles is an *item* destination, not a path entry, so clearing the `NavigationPath` alone left it standing and the tab tap did nothing. |
| DEBUG `-openAllTitles 1` | on first `onAppear` only (`debugOpenedAll` latch), `all = AllTitlesRoute()`. The latch is required: `onAppear` fires again when All titles pops and the flag re-pushed it on the spot. |

The push hands All titles the **root's already-computed wash art**:
`washArt: washArtwork(rootSections(), heroItems: appModel.watchingShelf.filter { $0.resumePart != nil })`.

Cross-tab entries (from `MainTabView`):
* Today "See all watching" → `AllTitlesRoute(status: .watching)`
* Today "View all N updates" → `AllTitlesRoute(status: nil, unwatchedOnly: true)` — **no status**,
  because Today's count is `outNow`, which spans every status; "pinning Watching here made the
  count and the list disagree the moment a Paused show aired."
* Profile / other "open library at status" → `AllTitlesRoute(status: s)`

---

## 6. All titles (`LibraryAllView`) — the instrument

The one Library screen with controls. Rows sit on the canvas at `rowMedia` height with 60×90 art,
under **pinned letter headers with an A–Z index rail** once the list is long enough.

### 6.1 Construction — filters are seeded at INIT

```swift
init(initialStatus: WatchStatus? = nil, initialReturning: ReturnScope? = nil,
     initialSort: Sort = .title, initialUnwatchedOnly: Bool = false,
     washArt: String? = nil, onOpenDetail:, onAddShow:)
```

`status`, `unwatchedOnly`, `returning`, `sort` are all written into state **in the initialiser**,
never applied in an `onAppear`. *"Applied late, the screen builds once unfiltered and once
filtered — the user sees the whole library flash past on the way to the six rows they asked for,
and the rows that survive both passes can keep the first pass's copy (rows under a `Watching` chip
still reading 'Watching')."*

`initialUnwatchedOnly` **composes with** `initialStatus` rather than replacing it.

### 6.2 State

| State | Default | Notes |
|---|---|---|
| `query` | `""` | bound to the search field |
| `sort` | `.title` | `title / added / recent / progress` |
| `sortAscending` | `false` | "reverse order" flag; the base direction differs per sort |
| `status` | `.any` | `StatusFilter = .any \| .status(WatchStatus)` |
| `unwatchedOnly` | `false` | its own axis |
| `returning` | `nil` | `ReturnScope = .dated \| .undated` |
| `display` | `.list` | `.posters \| .list` — **a preference, not a filter** |
| `showArrange` | `false` | sheet presentation |
| `contentWidth`, `contentHeight` | 0 | geometry probes |
| `raisedTop` | `false` | chrome probe |
| `searchPresented` | `false` | field focus |
| `railIndex`, `railScroll`, `railTouching` | nil/nil/false | index rail |

`ReturnScope`: `.dated` labels `"Returning"`, `.undated` labels `"Announced"`; `.section` maps to
`LibrarySection.returning` / `.announced`.

`StatusFilter`: `label` = `"Any"` or `Copy.Status(s)`; `chip` = `nil` for `.any` ("a chip states
the criterion, and 'Any' is not one"); `givesState` = true for `.status(_)`;
`watchStatus` unwraps.

### 6.3 `filtered()` — one pass, resolved once per render

```swift
let q = query.trimmingCharacters(in: .whitespaces).lowercased()
let outNow: Set<String> = unwatchedOnly ? Set(appModel.outNow.map(\.id)) : []

var arr = appModel.library.filter { f in
    (status == .any || f.effectiveStatus == status.watchStatus!)
 && (!unwatchedOnly || outNow.contains(f.id))
 && (returning == nil || LibraryShelving.section(of: f, appModel: appModel) == returning!.section)
 && (q.isEmpty || f.title.lowercased().contains(q))
}
```

* The search matches the **raw `title`**, case-insensitively, as a substring — not `displayTitle`.
* **"Has unwatched episodes" is exactly the set Today counts** (`AppModel.outNow`), resolved once
  per pass, "so 'View all 12 updates' lands on twelve rows. The shipped predicate was its own
  (`markTarget > progress`), which counted unaired seasons as unwatched and could not agree with
  the number that opened the screen."

Sorting:

| `sort` | Comparator | Base direction |
|---|---|---|
| `.title` | `a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending` | A→Z |
| `.added` | descending by `subscription?.addedAt ?? Int64.min` | newest first; **unknown dates sort LAST**, never as 1970 |
| `.recent` | descending by `lastAiredSortKey` | most recently aired first |
| `.progress` | descending by `continueBacklog` | most left to watch first |

All three descending sorts share one generic helper: *largest key first, `titleAscending` between
equals*. **There is exactly ONE tie-break and one title order** — three sorts once broke ties three
different ways (`lowercased()`, raw `title`, a locale-aware compare) "so 'Ōoku' moved between them."

Finally: `return sortAscending ? arr.reversed() : arr` — the whole array is reversed, tie-break
included.

`filtered()` is a **function, not a computed property**: "it was read from eight sites per render
(the list, the grid, the rail, the rotor, `showsRail`, `isSectioned`, the footer, the rail's
VoiceOver value), each one re-filtering and re-sorting the library." `body` resolves, once, in
order:

```swift
let results   = filtered()
let sections  = titleSections(results)
let sectioned = isSectioned(results)
let rail      = showsRail(results)
```

### 6.4 `hasFilters`

```swift
status != .any || unwatchedOnly || returning != nil || sort != .title || sortAscending
```

**`display` is deliberately excluded.** *"A filter is a thing the user chose that hides rows. The
view mode is not one — which is why the shipped 'Posters … Clear' row offered a destructive-sounding
action against a state that was nowhere on screen."* `query` is also excluded (it names itself).

### 6.5 Layout

```
ScrollViewReader { proxy in
ScrollView (indicators hidden):
  VStack(alignment: .leading, spacing: 0):
    [freshness anchor, gutter-padded]
    if sectionFailed: InlineNotice("Your library couldn’t refresh") { reload() }   gutter, top 12
    if !activeChips.isEmpty: chipRow
    SkeletonGate(isLoading: loading && library.isEmpty):
       skeleton
       |
       VStack(alignment: .leading, spacing: 0):      // ONE view — SkeletonGate lays its content
                                                     // out in a ZStack, so two siblings drew on
                                                     // top of each other ("30 titles" across the
                                                     // first row)
         library.isEmpty  -> EmptyState(emptyStateCopy, .major, primary: emptyLibraryAction).centred
         results.isEmpty  -> EmptyState(emptyResultsCopy, .major,
                                        primary: hasFilters ? resetFilters : nil).centred
         display == .posters -> grid(...).padding(.top, 8)
         else                -> list(...)            // NO top lead-in: the search drawer carries
                                                     // its own margin
         if !results.isEmpty:
            Text(Copy.titles(results.count))  metadata / textTertiary
              .numericFact(results.count)     // digit roll on uiNumeric; opacity crossfade under
                                              // Reduce Motion
              .frame(maxWidth: .infinity).padding(.top, 24)
  .onGeometryChange -> contentWidth
  .background { geometry probe -> raisedTop }
.onGeometryChange -> contentHeight
.onChange(of: railScroll) { proxy.scrollTo("sec-\(key)", anchor: .top) }
```

Screen chrome:
* wash: `ZStack(top) { canvas; ArtBackdrop(washArt ?? results.first?.portraitArt ?? library.first?.portraitArt, height 320, intensity 0.4) }.ignoresSafeArea()`
* `scrollEdgeChromeBody(top: true, bottom: true, topHeight: topSafeInset + 52, softTop: true, topRaised:, topHold: searchChromeBottom)`
* `contentMargins(.bottom, 76, for: .scrollContent)`
* `navigationTitle("All titles")`, inline display mode
* `searchable(text: $query, isPresented: $searchPresented, placement: .navigationBarDrawer(.always), prompt: "Search your library")`
* `.textInputAutocapitalization(.never)`, `.autocorrectionDisabled()`,
  `.scrollDismissesKeyboard(.interactively)` — "titles are names, not sentences, and the keyboard
  follows the finger down"
* `previouslyRefreshable { reload() }`
* `environment(\.listTrailingInset, rail ? 28 : 0)` — the rail **owns a lane**, and every
  `MediaRow` inside stops short of it
* `.overlay(alignment: .trailing) { if rail { indexRail(sections) } }`
* trailing toolbar item: `Image(systemName: "line.3.horizontal.decrease")`, tinted
  `hasFilters ? accent : textPrimary`, a11y label `"Sort & filter"`, tap → `showArrange = true`.
  *"Accent is selection here, and only here: an idle filter control is not the screen's primary
  action and has no business being the loudest thing on it."*

### 6.6 Empty / error states

| Condition | Copy | Primary |
|---|---|---|
| `library.isEmpty` | `appModel.emptyStateCopy` (§5.10) | `loadError ? reload : onAddShow` |
| `results.isEmpty`, `query.isEmpty` | `EmptyStateCopy.noFilterMatches` — symbol `slider.horizontal.3`, title `"No titles match"`, supporting `"Clear the filters to see everything in your library."`, primary label `"Clear"` | `resetFilters` (guaranteed present, because only a filter can empty a query-less list) |
| `results.isEmpty`, query non-empty, `!hasFilters` | symbol `magnifyingglass`, title `"No results for “<query>”"` (curly double quotes U+201C/U+201D), supporting `"Check the spelling or try another title."`, **no primary label** | none |
| `results.isEmpty`, query non-empty, `hasFilters` | same as above **plus** primary label `"Clear"` | `resetFilters` |

The last row exists because "without it a query under a 'Watched' chip dead-ended on a card with no
way out but the chip row."

There is a `DEBUG` assertion in `EmptyState.init` that fires when a copy declares a
`primaryLabel` and no handler was supplied — the guard against re-introducing a dead control.

### 6.7 Chip row

Rendered only when `activeChips` is non-empty, directly under the freshness/notice block.

```
ScrollView(.horizontal, indicators hidden, scrollClipDisabled)
  HStack(spacing 8) { chips…, [Reset] }.padding(.horizontal, 16)
.padding(.bottom, 8)
```

Chip order and content:

| id | Shown when | Text | Clear action |
|---|---|---|---|
| `status` | `status != .any` | `Copy.Status(s)` | `status = .any` |
| `unwatched` | `unwatchedOnly` | `"Has unwatched episodes"` | `unwatchedOnly = false` |
| `returning` | `returning != nil` | `"Returning"` / `"Announced"` | `returning = nil` |
| `sort` | `sort != .title \|\| sortAscending` | `sortAscending ? "<label>, reversed" : label` | `sort = .title; sortAscending = false` |

**Reset** appears only when `activeChips.count > 1`, label `"Reset"`, `ChipButtonStyle` (unselected:
`surfaceRaised` capsule, `textSecondary` `metadataEmphasis` ink, no stroke). *"Neutral, not amber:
returning to the default is the smallest thing on the row, and the screen's one accent is not spent
on a utility."*

Chip visual (`FilterChipStyle` + `FilterChipLabel`): text + `xmark` glyph at 10 pt bold, spacing 5;
`metadataEmphasis` type in `accent`; horizontal padding 12; `minHeight 32` inside a `Capsule` of
`accentSoft` (or `surfacePressed` while pressed); hit shape the capsule; outer `minHeight 44`.
Press: scale 0.985 (opacity 0.72, no scale under Reduce Motion) on `uiPress`.

Every chip tap and the Reset tap: `FeedbackCoordinator.fire(.selection)` then the mutation inside
`withAnimation(pick(uiSnappy, reduceMotion:))`.

a11y label per chip: `"<text>. Remove filter"`.

`resetFilters()` sets `sort = .title; sortAscending = false; status = .any; unwatchedOnly = false;
returning = nil`. **It does not touch `display` or `query`.**

The sort chip must name its direction: *"a 'Recently added' chip that silently means oldest first
is a lie the reader cannot see."*

### 6.8 Sections and the index

```swift
static let sectionFloor = 48
isSectioned(results) = sort != .progress && results.count > 48
showsRail(results)   = sort == .title   && results.count > 48 && !isAccessibilitySize
```

*Why 48:* "about five screens; below that a flick is faster than an alphabet, and a thirty-title
library dressed in letter headers and a rail read as a phone book for one street. At the stated 300
titles the rail is the difference between finding 'Vinland Saga' and hunting for it."
The rail and the headers share the threshold so the two controls "never disagree about whether this
list has sections."

`titleSections(results)`:

```
if !isSectioned: return [ TitleSection(key: "", items: results) ]     // ONE bucket
switch sort:
  .title:   bucket by indexKey(f.title)
            keys sorted so that "#" is LAST, everything else ascending by string
  .recent, .added:
            key = sort == .added ? monthKey(subscription?.addedAt ?? 0, anchor: .local)
                                 : monthKey(lastAiredSortKey,          anchor: f.timeAnchor)
            buckets emitted in FIRST-SEEN order (the sort already ordered them)
  .progress: [ TitleSection(key: "", items: results) ]
```

*Why one bucket when not sectioned:* "A `Section` inside a `LazyVGrid` starts a new ROW even when
its header is an `EmptyView`, so leaving the per-letter buckets in place and merely hiding the
headers laid a ten-title poster wall out two-then-one down the page with holes where the letters
changed."

```swift
static func indexKey(_ title: String) -> String {
    let folded = title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    guard let first = folded.first(where: { $0.isLetter || $0.isNumber }) else { return "#" }
    return first.isLetter ? String(first).uppercased() : "#"
}

private static func monthKey(_ at: Int64, anchor:) -> String {
    at > 0 ? LibraryDates.monthYear(at, anchor: anchor) : "No date"
}
```

**`at` is milliseconds** — "it was read as seconds here, which put the 'Recently updated' month
headers roughly fifty-five thousand years out."

`monthKey`'s two anchors differ on purpose: `addedAt` is the user's own instant (local); an airing
is read in the franchise's calendar so a TMDB date-only row lands in the month it names.

#### Pinned section header

```
HStack(spacing 0) { Text(key) sectionLabel / textTertiary ; Spacer(minLength: 0) }
.padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 4)
.frame(maxWidth: .infinity, alignment: .leading)
.background { canvas.padding(.horizontal, -16) }          // OPAQUE and FULL-BLEED
.overlay(alignment: .bottom) {
    Rectangle().fill(separatorQuiet).frame(height: 1)
      .padding(.leading, inset)
      .padding(.trailing, rail ? 28 : 0)
}
.accessibilityAddTraits(.isHeader)
```

* `inset` is **`rowRuleInset` = 90** in the list (so the header's rule shares the row separators'
  left edge) and **`gutter` = 16** in the grid (there is no poster column to align to). In the grid
  the header is additionally `padding(.horizontal, -16)` so it reaches the bezels.
* The header is opaque because content scrolls **under** it; but it must be full-bleed — "inset to
  the gutter it painted a visible canvas rectangle against the ambient wash behind the list — a
  plate, which is exactly what a pinned header must not look like."
* Each header carries `.id("sec-<key>")` (the programmatic scroll target) and
  `.accessibilityRotorEntry(id: key, in: rotorSpace)`.

#### The A–Z index rail

Constants: `railLane = 28` (the reserved drawing lane, matching Contacts), `railHit = 44` (the
gesture host — reaches 16 pt into the rows' trailing padding), `railMinStep = 22` (minimum band
height).

```
GeometryReader { geo in
  step = max(22, geo.size.height / max(keys.count, 1))
  VStack(spacing 0) { ForEach(keys) { Text(key) sectionLabel, railTint(i), maxWidth .infinity, height step } }
    .frame(width: 28)
    .frame(width: 44, height: geo.size.height, alignment: .topTrailing)
    .contentShape(Rectangle())
    .gesture(DragGesture(minimumDistance: 0)
       .onChanged { select(index: clamp(Int(location.y / step), 0, keys.count-1)) ; railTouching = true }
       .onEnded   { railTouching = false; railIndex = nil; railScroll = nil })
}
.frame(width: 44)
.padding(.top, 12).padding(.bottom, 76)     // between the search drawer and the tab bar
.background(alignment: .trailing) {
    Capsule().fill(surfaceRaised.opacity(railTouching ? 1 : 0))
      .frame(width: 28).padding(.vertical, 8)
}
.animation(pick(uiMicro, reduceMotion:), value: railTouching)
```

`railTint(i)`: not touching → `textTertiary`; touching → `accent` for the active index,
`textSecondary` for the rest. *"the rail says which letter it is on instead of all of them."*

`select(index:)`: no-op if out of range **or already the current index**; then
`railIndex = index; FeedbackCoordinator.fire(.selection); railScroll = keys[index]`, and the
`onChange(of: railScroll)` performs `proxy.scrollTo("sec-\(key)", anchor: .top)`.

Everything the rail's rebuild fixed, recorded so a port does not regress it:

| Axis | Was | Is |
|---|---|---|
| Type | hard-coded `.system(size: 11, weight: .semibold)` — stayed 11 pt at AX5 | `sectionLabel`, which scales; the rail is suppressed entirely at accessibility sizes |
| Contrast | `textDisabled` (3.6:1) on **text** | `textTertiary` (5.14:1), lifting to `textSecondary`/`accent` under the finger |
| Extent | 15 letters × 15 pt = a 225-pt column floating in the vertical middle, attached to nothing | spans the list top to bottom; every band ≥ 22 pt |
| Target | 22×15 bands in a 22-pt column, letters sitting **on** the third poster column | letters right-aligned in a 28-pt reserved lane; a 44-pt gesture host |
| VoiceOver | `accessibilityHidden(true)` with no substitute | one adjustable element + a "Sections" rotor on the list |
| Feel | a 300 ms blanket haptic floor made an A→W drag produce two taps | `.selection` has its own 40 ms floor |

Rail accessibility: one element, label `"Section index"`, value = the current key (or the first),
hint `"Jumps the list to a section"`, `accessibilityAdjustableAction` moving ±1 through
`select(index:)`.

Both the list and the grid additionally carry
`.accessibilityRotor("Sections", entries: sections, entryID: \.key, entryLabel: \.key)` — the
rail's VoiceOver counterpart, working even while the lazy stack has not built the rows between two
letters.

### 6.9 The list

```
LazyVStack(spacing: 0, pinnedViews: sectioned ? [.sectionHeaders] : []):
   ForEach(sections) { Section(header: listHeader) { ForEach(items) { row(f, last: i == count-1) } } }
.padding(.horizontal, 16)
.accessibilityRotor("Sections", …)
```

**Lazy and sectioned is a hard requirement**: "At the stated 300-title library an eager `VStack`
instantiates 300 `MediaRow`s and 300 `RemoteImageView`s on push."

Each row:

```swift
let facts = LibraryRowFacts.catalogue(f, appModel:, stateIsGiven: status.givesState)
MediaRow(title: f.displayTitle, meta: facts.meta, lead: facts.lead,
         poster: f.portraitArt, slot: .row, separator: !last,
         hint: "Opens the show", zoomID: "all/\(f.id)") { onOpenDetail(f.id, "all/\(f.id)") }
  .franchiseQuickActions(f, appModel:)
```

**`MediaRow` anatomy** (the one repeating row; `slot = .row` → 60×90 poster, radius 10, no shadow):

```
Button(RowPressStyle):
  HStack(spacing 14):                                 // ThemeMetrics.artGap
    PosterSlot(url: poster, .row)                     // zoomSource("all/<id>")
    VStack(alignment: .leading, spacing: 3):          // ThemeMetrics.titleGap
      Text(title)   rowTitle / textPrimary,  lineLimit 2 (nil at AX)
      if lead:  Text(lead)  rowMetaLead / accent
      if meta:  Text(meta)  rowMeta / textSecondary
      [if progress: ProgressBar, padding top 4, trailing 24]   // unused by Library
    Spacer(minLength: 12)
    if chevron: Image("chevron.forward") 13 pt semibold, textDisabled,
                frame(width: 11, alignment: .trailing)         // a FIXED column
  .padding(.trailing, listTrailingInset)              // 28 while the rail is up
  .padding(.vertical, 8)
  .frame(minHeight: 100, alignment: .leading)         // ThemeMetrics.rowMedia
  .contentShape(Rectangle())
  .opacity(dimmed ? 0.72 : 1)
  .overlay(alignment: .bottom) { if separator:
      Rectangle().fill(separatorQuiet).frame(height: 1).padding(.leading, 60 + 14 = 74) }
a11y: one combined element, label = [title, lead, meta] joined ", ", hint = "Opens the show"
```

The chevron sits in a fixed 11-pt column because it was once concatenated into the title, making
its x a function of title length — "measured at 370 / 418 / 520 / 600 / 712 down a single list."

**`PosterSlot`** decoding rules (they matter for fidelity):
* ground = `RoundedRect(radius).fill(surfaceRaised)`, then the artwork's own **palette tint at
  0.60 opacity** once resolved — "never grey";
* the image is `contentMode = .fit` at `maxPixel = max(w,h) * 3`, with a `fitSnapAspect` allowance:
  a cover that misses the slot's ratio by **≤ 5 %** fills instead of leaving a tinted sliver;
* **no blurred backfill** behind a poster — that cost a second full decode plus a blur pass on
  every slot ≥ 72 pt;
* 1-px `posterEdge` (white 9 %) border, then the slot's shadow;
* transition to the decoded image is `.opacity` on `uiPoster` (easeOut 0.18);
* the slot is `accessibilityHidden(true)`;
* no artwork at all → `Image(systemName: "photo")` at `min(w,h)*0.28`, `textTertiary`.

`RowPressStyle`: `surfacePressed @ 0.6` rounded-rect wash (radius 16) + scale 0.992 on `uiPress`
in, `uiMicro` out; no scale under Reduce Motion.

### 6.10 The poster wall

```
columns   = 3
lane      = rail ? 28 : 0
available = max(0, contentWidth − 32 − lane)
cellWidth = available > 0 ? (available − 12*(3−1)) / 3 : 112       // PosterSize.shelfMedium.width
LazyVGrid(columns: 3 × GridItem(.fixed(cellWidth), spacing: 12, alignment: .top),
          alignment: .leading, spacing: 24, pinnedViews: sectioned ? [.sectionHeaders] : [])
.padding(.horizontal, 16)
```

Fixed columns, not adaptive: an adaptive grid "leaves a ragged 30 pt down the trailing edge."

Each cell:

```
Button(RowPressStyle(radius: 12)):                  // PosterSize.shelfMedium.radius
  VStack(alignment: .leading, spacing: 8):
    PosterSlot(url: f.portraitArt, width: cellWidth, height: (cellWidth*3/2).rounded(),
               radius: 12, shadow: .art).zoomSource("all/<id>")
    VStack(alignment: .leading, spacing: 2):
      Text(f.displayTitle)  shelfTitle / textPrimary
            lineLimit isAX ? 1...6 : 1...2, minimumScaleFactor 0.82, allowsTightening, leading
      if caption: Text(caption.text)  shelfCaption
            foreground: caption.lead ? accent : textSecondary
            lineLimit 2, truncationMode .tail
    .frame(width: cellWidth, alignment: .leading)
  .contentShape(Rectangle())
.franchiseQuickActions(f)
a11y: combined, label = [f.title, caption?.text] joined ", ", hint "Opens the show"
```

`gridCaption(f)`:

```swift
let facts = LibraryRowFacts.catalogue(f, appModel:, stateIsGiven: status.givesState, compact: true)
if let lead = facts.lead { return (lead, true) }     // amber
if let meta = facts.meta { return (meta, false) }    // grey
return nil
```

Resolved **once** per cell — "calling the accessor twice to pick a colour is how a caption and its
colour drift apart."

The `alignCaptions` parameter is computed as `section.items.count > 1` and passed, but the current
cell body does not reserve title lines; the reason it exists is recorded: "A section holding a
single title has nothing to align with, and reserving there left a hole between a one-line title
and its caption."

`zoomSource("all/<id>")` is registered on **both** the list poster and the grid poster — "the list
variant zoomed into Detail and the wall slid, so the transition changed with a VIEW-MODE TOGGLE."
(Nothing currently consumes the registrations; Detail is a plain push.)

### 6.11 All-titles skeleton

```
VStack(spacing: 0) { 8 × SkeletonRow(poster: 60×90, lines: [196, 108], posterRadius: 10, spacing: 14) }
.padding(.horizontal, 16).padding(.top, 4)
```

`SkeletonRow` = poster + a `VStack(spacing 8)` of lines whose **first line is 13 pt tall and the
rest 10 pt**, in a row whose `minHeight` is `rowStandard (88)` **scaled with Dynamic Type**
(`@ScaledMetric(relativeTo: .body)`) so the swap to real content does not jump at accessibility
sizes.

### 6.12 The Sort & filter sheet

Presented on `showArrange`, with:
* `presentationDetents([.custom(ArrangeDetent.self), .large])`
* `presentationDragIndicator(.visible)`
* `presentationBackground(ThemeColor.canvasRaised)` — set at the call site, not painted on the
  sheet's scroll view: "painting it on this scroll view left the plate 34 pt short and the undimmed
  list showed through the gap — it read as a rendering failure."

**The detent is computed before presentation**, never measured:

```
ArrangeGeometry.rowCount = 5
ArrangeGeometry.chrome   = 52 + 12 + 20 + 30 + 24 + 34 − 42 = 130
height = min(5 × 56 × typeFactor(dynamicTypeSize) + 130, maxDetentValue × 0.92)
```

`typeFactor`: xSmall 0.92, small 0.95, medium 0.98, **large 1.00**, xLarge 1.08, xxLarge 1.16,
xxxLarge 1.26, AX1 1.52, AX2 1.74, AX3 2.05, AX4 2.35, AX5 2.60.

At the default text size that is **410 pt**. *"A detent that measures itself cannot be right on the
first frame: the sheet grew 68 pt under the user's eye and only looked correct the second time it
opened."*

**Header** (hand-built, not a navigation toolbar — "on this OS a toolbar button renders as a filled
glass capsule, which made `Done` the single heaviest object in a sheet whose whole job is to be
quiet"):

```
HStack:
  if hasFilters: Button("Reset")  InlineLinkButtonStyle
  Spacer(minLength: 0)
  Button("Done")  InlineLinkButtonStyle -> dismiss()
.overlay { Text("Sort & filter") showTitleM / textPrimary, lineLimit 1, minimumScaleFactor 0.85 }
.padding(.horizontal, 16).frame(height: 52).padding(.top, 12)
```

The title is an **overlay**, not a stack member: "with `Reset` present on one side only, a
three-item HStack puts the title wherever the two buttons' widths happen to leave it."

`InlineLinkButtonStyle`: `listAction` type, `interactive` ink, `padding(.vertical, 14)`,
`padding(.horizontal, 12)`, `minHeight 44`, `contentShape(Rectangle())`, opacity 0.55 pressed on
`uiPress`.

`hasFilters` **inside the sheet** is `sort != .title || ascending || status != .any ||
unwatchedOnly` (it omits `returning`, which the sheet does not expose).

**Groups** — `VStack(alignment: .leading, spacing: 30)`, horizontally padded 16, top 20, bottom 24:

Group 1 (**no header** — "the sheet's own title names it, and repeating 'SORT & FILTER' 30 pt under
'Sort & filter' is an echo"; iOS Settings grammar: the first group is implicit, later groups are
named):

| Row | Control | Values |
|---|---|---|
| `Sort by` | menu row → inline `Picker` | `Title` / `Recently added` / `Recently updated` / `Most left to watch` |
| `Reverse order` | native `Toggle`, tint `accent`; subtitle appears **only while on** | subtitle = `Z to A` / `Oldest first` / `Least recent first` / `Least left to watch first` |
| `Status` | menu row → inline `Picker` | `Any`, then `Watching`, `Planned`, `Watched`, `Paused`, `Dropped` (`WatchStatus.menuOrder`) |
| `Has unwatched episodes` | native `Toggle`, no separator below | — |

Group 2, header `View` (small-caps `SectionLabel`, leading padding 16):

| Row | Control |
|---|---|
| `View as` | segmented `Picker`: `Posters` / `List`, fixed width **168** |

At accessibility sizes the `View as` row becomes a `VStack(alignment: .leading, spacing: 8)` —
label above, full-width segmented control below, vertical padding 12 — "rather than squeezing to
60 pt."

**`valueRow`** (a `GroupedRow`'s geometry with a `Menu` where the `Button` is):

```
Menu { picker } label: {
  HStack(spacing 12):
    Text(title)  body / textPrimary
    Spacer(minLength: 12)
    Text(value)  body / textTertiary, lineLimit 1
    Image("chevron.up.chevron.down") 12 pt semibold, textDisabled
  .padding(.leading, 14).padding(.trailing, 16)
  .frame(minHeight: 56)
  .contentShape(Rectangle())
  .overlay(alignment: .bottom) { if separator: 1-pt separatorQuiet, padding(.leading, 14) }
}
a11y: label = title, value = value
```

The pop-up glyph is `chevron.up.chevron.down`, **not** `chevron.forward` — "this row opens a menu
in place, it does not push a screen, and iOS has one symbol for each."

**`GroupedList` / `GroupedRow`** (shared): the list is a `VStack(alignment: .leading, spacing: 10)`
with an optional small-caps header, and the rows sit inside a `VStack(spacing: 0)` given
`.surface(.plate, radius: 16)` — i.e. a **white 5.5 % lift over whatever is behind it**, clipped,
**no stroke**, no shadow. *"A plate, not a stroked box: this is the iOS grouped-table grammar, and
a grouped table has never had an outline. The fill IS the group."* The lift (rather than an opaque
fill) is required because these screens carry an ambient wash — an opaque near-black plate over a
lit canvas "inverted into a hole."

A toggle row renders a **real `Toggle` whose label is the row** — never a `Toggle` inside a
`Button`: "VoiceOver announced 'Unwatched only, button' with no switch trait and no On/Off value,
and the outer button's hit-test priority made the switch itself unreliable to hit."

**Bindings and feedback.** A `Picker` writes straight through its binding, so the haptic and the
settle animation live in the binding:

```swift
func select<V: Equatable>(_ current: V, _ new: V, _ apply: () -> Void) {
    guard new != current else { return }
    FeedbackCoordinator.fire(.selection)
    withAnimation(ThemeMotion.pick(.uiMicro, reduceMotion:), apply)
}
```
applied to `sort`, `status`, `display`, `ascending` and `unwatchedOnly`. The header's `Reset` fires
`.selection` and animates `onReset()` on `uiSnappy`.

---

## 7. Accessibility summary

| Element | Behaviour |
|---|---|
| Root bar button | label `"All titles, 30 titles"`, hint `"Opens your whole library, with search, sorting and filters"` |
| Section headers | `.isHeader` trait; navigating headers speak `"<title>, See all"` and the chevron is hidden |
| Continue card | one element: `"<full title>, <next episode line>, <n> of <m> watched"`, hint `"Opens the show"` |
| Banner card / grid cell | one element: `"<full title>, <caption>"`, hint `"Opens the show"` — **always the raw `title`, never `displayTitle`** |
| `MediaRow` | one element: `[title, lead, meta]`; the chevron is never spoken; hint `"Opens the show"` |
| Progress bars | hidden unless a `spoken` string is supplied; the count rides the parent's label |
| Posters | `accessibilityHidden(true)` everywhere |
| Index rail | one adjustable element; label `"Section index"`, value = current letter, hint `"Jumps the list to a section"` |
| Sections rotor | `"Sections"` on both list and grid, entry id and label = the section key |
| Filter chips | `"<criterion>. Remove filter"` |
| Filter toolbar button | label `"Sort & filter"` |
| Footer count | spoken as text, digit-rolls on change |
| Stale strip | children ignored; label is the spelled-out form `"Updated 8 hours ago"`; `.isStaticText` |
| Empty states | container element; label `"<title>. <supporting>"` |
| Skeleton | children ignored; label `"Loading"` |

**Dynamic Type responses**

| Size class | Change |
|---|---|
| any | all Outfit tokens scale via `relativeTo:`; SF tokens are text styles; skeleton blocks do **not** scale (they are structure), but `SkeletonRow`'s minimum height does |
| accessibility (AX1–AX5) | Continue shelf → 1 card per screen; landscape shelves → 1 card per screen; index rail suppressed entirely; grid cell title `1...6` lines instead of `1...2`; `MediaRow` title unlimited lines; `InlineNotice` becomes a vertical stack; `View as` row becomes label-over-control; `EmptyState` title unlimited lines and its buttons stop hugging; sheet detent grows by `typeFactor` up to 2.60× |

**Reduce Motion**: every `ThemeMotion.pick` call collapses to `uiReduced` (easeOut 0.12); all press
styles switch from scale to opacity (0.72); the skeleton breath becomes a static 0.92; the numeric
footer count crossfades instead of rolling.

**Reduce Transparency**: the top chrome veil drops its `ultraThinMaterial` and becomes **fully
opaque canvas** (bar opacity 1.0 instead of 0.74).

---

## 8. Verbatim strings inventory

Every user-facing string in this area, exactly as it must appear. `’` is U+2019, `·` is U+00B7,
`“ ”` are U+201C/U+201D, and `\u{00A0}` marks a non-breaking space.

| Key | String |
|---|---|
| screen title | `Library` |
| pushed screen title | `All titles` |
| root bar button | `<n>\u{00A0}title` / `<n>\u{00A0}titles` |
| root bar a11y | `All titles, <n>\u{00A0}titles` |
| root bar hint | `Opens your whole library, with search, sorting and filters` |
| lead shelf header | `Continue watching` |
| shelf headers | `Returning`, `Watching`, `Planned`, `Announced`, `Watched` |
| header a11y suffix | `See all` |
| refresh notice | `Your library couldn’t refresh` |
| notice retry | `Retry` (hint `Tries the request again`) |
| search prompt | `Search your library` |
| sheet title / a11y | `Sort & filter` |
| sheet rows | `Sort by`, `Reverse order`, `Status`, `Has unwatched episodes`, `View`, `View as` |
| sort labels | `Title`, `Recently added`, `Recently updated`, `Most left to watch` |
| reversed hints | `Z to A`, `Oldest first`, `Least recent first`, `Least left to watch first` |
| status filter "no filter" | `Any` |
| view modes | `Posters`, `List` |
| sort chip when reversed | `<label>, reversed` |
| sheet/chip actions | `Reset`, `Done`, `Clear` |
| month header for no date | `No date` |
| index rail | `Section index` / hint `Jumps the list to a section` / rotor `Sections` |
| return phrasings | `Returns today`, `Returns tomorrow`, `Returns <Weekday>`, `Returns <Mon d>`, `Returns <Mon d, yyyy>`, `Returned <date>`, `Returns <Mon yyyy>`, `Returns <yyyy>`, `Returns <window in lower case>`, `No date announced` |
| rumour | `<Season 3> rumored` / bare `Rumored` |
| progress | `Caught up`, `Episode <n> next`, `<context> next`, `<n>\u{00A0}episodes\u{00A0}behind`, `<w> of <t> watched`, `Watched once` / `Watched twice` / `Watched <n> times`, `First watch`…`Tenth watch`, `<n>th watch` |
| identity line | `Anime · <year>`, `TV · <year>`, or just `Anime` / `TV` |
| catalogue joined meta | `<State> · <fact>` |
| statuses | `Watching`, `Planned`, `Watched`, `Paused`, `Dropped` |
| context menu | `Mark all <n>\u{00A0}episodes as watched`, `Remove from Library` |
| empty: account | `Your library is empty` / `Everything you add shows up here.` / `Add a show` |
| empty: server | `Couldn’t load your library` / `Something went wrong. Try again in a moment.` / `Try again` |
| empty: offline | `You’re offline` / `Connect to the internet to load your library.` / `Try again` |
| empty: filters | `No titles match` / `Clear the filters to see everything in your library.` / `Clear` |
| empty: search | `No results for “<query>”` / `Check the spelling or try another title.` |
| stale strip | `Updated just now` / `Updated <n> min ago` / `Updated <n>h ago` / `Updated yesterday` / `Updated <Weekday>` / `Updated <date>` |
| stale strip (spoken) | `Updated <n> minutes ago` / `Updated <n> hours ago` |

Two strings exist in `Copy.Library` with **no call site** and should not be ported unless a use
appears: `allTitlesCount(_:)` → `"All <n>"`, `focusTitleHint` → `"Shows this title in the centre"`,
`partProgress(_:watched:total:)`.

---

## 9. Behavioural invariants a reviewer should check on the Android build

1. **The Library never shows a behind-count, a mark control or a countdown.** The one number it
   draws is the progress bar's fill on a Continue card, and the one amber caption is a
   `ReturnFact` inside the 60-day horizon (plus the amber `lead` line, which on the root's
   Watching shelf can only ever be a rewatch).
2. **One show, one caption, in both view modes.** The list and the poster wall must call the same
   `catalogue(...)` function, with `compact` changing layout only.
3. **RETURNING contains only dated shows.** A show with `"No date announced"` or a rumour appears
   under ANNOUNCED.
4. **A dated return whose day has passed leaves the Returning shelf** (`hasArrived`).
5. **"Has unwatched episodes" returns exactly `AppModel.outNow`**, so a "View all 12 updates" entry
   lands on 12 rows.
6. **Re-selecting the Library tab pops All titles** (`popSignal`).
7. **The pushed screen is lit by the root's wash art**, not by its own first row.
8. **Section headers and the index rail appear together or not at all** (> 48 rows, `.title` sort,
   non-AX for the rail).
9. **`results`/`sections`/`sectioned`/`rail` are computed once per frame**, not per consumer.
10. **The footer count is inside the same view as the list**, not a sibling of it.

---

## 10. Android portability risks

| # | Item | Why it is hard on Android | Severity |
|---|---|---|---|
| 1 | **SF Symbols** — `rectangle.stack`, `slider.horizontal.3`, `wifi.slash`, `wifi.exclamationmark`, `exclamationmark.circle`, `magnifyingglass`, `chevron.forward`, `chevron.up.chevron.down`, `line.3.horizontal.decrease`, `arrow.triangle.2.circlepath`, `photo`, `xmark`, `text.append`, `trash`, `play.circle`, `clock`, `checkmark.circle`, `pause.circle`, `xmark.circle` | No equivalent set. Material Symbols cover the semantics but not the weight/optical-size ramp or the Dynamic-Type-scaled `.font(.system(size:weight:))` sizing. Every glyph must be re-picked and re-weighted, and the two chevrons (`forward` vs `up.chevron.down`) carry a *meaning distinction* the port must preserve. | moderate |
| 2 | **`.ultraThinMaterial` chrome veils** (the top bar's blur under a 0.74 canvas, and the bottom ramp) | Compose has no first-class backdrop blur before Android 12's `RenderEffect`, and `RenderEffect.createBlurEffect` cannot sample "what is behind this composable" without a render-node capture. Practical fallback: a `Modifier.graphicsLayer` blur on a duplicated content layer, or drop the blur and go straight to the Reduce-Transparency path (opaque canvas at 1.0 with the same 28-pt edge ramp). | hard |
| 3 | **Liquid Glass tab bar / `chromeScrollEdgeHidden` / `chromeSharedBackgroundHidden` / iOS 26 toolbar capsules** | Purely iOS 26 chrome. On Android the whole family collapses to "no system scroll-edge effect exists", which is exactly what these shims already no-op to below iOS 26 — so the port simply omits them. | easy |
| 4 | **`containerRelativeFrame(count:span:spacing:)`** on both shelves | No Compose equivalent. Compute the width by hand from the container width using the formula in §5.6 and apply it with `Modifier.width()`; drive it off `BoxWithConstraints` or the `LazyRow`'s constraints. | easy |
| 5 | **`.scrollTargetBehavior(.viewAligned)` + `scrollTargetLayout()`** (card-aligned paging on both shelves) | `LazyRow` + `rememberSnapFlingBehavior(lazyListState)` gets close but snaps to item *start* with different physics; the peeking-card rhythm and the deceleration will not match exactly. | moderate |
| 6 | **`pinnedViews: [.sectionHeaders]`** with content scrolling *under* an opaque full-bleed header | `LazyColumn`'s `stickyHeader` exists, but `LazyVerticalGrid` has **no** sticky-header API. The poster wall's pinned letter headers must be hand-rolled (a header row spanning `maxLineSpan` plus a manual overlay driven by `LazyGridState`). | hard |
| 7 | **`ScrollViewReader.scrollTo(id, anchor: .top)`** from the index rail | `LazyListState.animateScrollToItem` / `scrollToItem` needs an *index*, not an id, so the port must maintain a key→flattened-index map (and a second one for the grid). Mechanical but easy to get wrong when sections change. | moderate |
| 8 | **`accessibilityRotor`** ("Sections") | TalkBack has no rotor-entry API. The nearest equivalents are heading traversal (`Modifier.semantics { heading() }`, already implied by the pinned headers) plus custom accessibility actions on the rail. The rail's `accessibilityAdjustableAction` maps to `SemanticsProperties.ProgressBarRangeInfo` + `setProgress`, or to two custom actions. | moderate |
| 9 | **`.searchable(placement: .navigationBarDrawer(displayMode: .always))`** | No platform search drawer. Must be built: a `TextField` in a 52-pt band under the title, with focus driving `searchChromeBottom` (§4.2) and the collapse of the inline title. The whole `searchPresented` → veil-hold shrink behaviour is bespoke either way. | moderate |
| 10 | **`presentationDetents([.custom, .large])` with a pre-computed custom detent** | `ModalBottomSheet` supports `SheetValue` states but not an arbitrary computed height as a *detent*; approximate with a fixed-height sheet content plus `skipPartiallyExpanded = false`. The computed height itself (§6.12) ports directly. | moderate |
| 11 | **`@ScaledMetric` / `relativeTo:` Dynamic Type** | Compose's `sp` scales with font scale but there is no per-token "relative to `.title3`" ramp and no non-linear accessibility ramp. Recreate `typeFactor` (§6.12) and derive glyph/skeleton sizes from `LocalDensity.fontScale`. Android's font scale tops out lower than AX5, so the AX-only layout switches need their own thresholds (`fontScale >= 1.3`). **ERRATUM (2026-09-04, PLAN D6a/§9.2):** wherever this document or `spec/detail.md` says iOS AX1 is "≈1.35×", that is wrong — iOS `.body` goes 17 pt → 28 pt, i.e. **1.647×**. The 1.3 threshold is a **deliberate divergence** (PLAN D6a) that fires the AX layouts a full band early on Android's ordinary *Largest* setting; it is not a conversion, and `fontScale` is not clamped at 2.0 by the platform (PLAN D6b). | moderate |
| 12 | **`zoomSource(_:)` registrations** (`"lib/<id>"`, `"lib-hero/<id>"`, `"all/<id>"`) | They are dead weight in iOS today — Detail is a plain push, and the `.zoom` transition was explicitly retired ("it scales the whole page into the tapped poster, so the show page opened as a miniature of itself inflating"). **Do not port them,** and do not implement a shared-element transition into Detail. | easy |
| 13 | **Haptics** — `UISelectionFeedbackGenerator`, light impact at intensity 0.50 | Android has `HapticFeedbackConstants.SEGMENT_TICK` / `VibrationEffect.createPredefined(EFFECT_TICK)`. Intensity is not addressable pre-API 31 amplitude control. The **40 ms selection floor vs 300 ms everything-else floor** is the part that must survive — it is what makes the index rail feel alive. | moderate |
| 14 | **Palette-derived poster tint** (`PaletteCache.resolve`) driving both `PosterSlot`'s mat and `ArtBackdrop`'s base | Straightforward with AndroidX Palette, but must share one decode with the image loader (Coil) or every slot pays a second decode — the iOS code is explicit that a second decode per slot was a measured cost. | easy |
| 15 | **`fitSnapAspect`** (a cover within 5 % of the slot's ratio fills instead of fitting) | No Coil/`ContentScale` equivalent; needs a custom `ContentScale` or a post-decode measurement branch. | easy |
| 16 | **`blur(radius: 56, opaque: true)`** for the ambient wash | `Modifier.blur` requires API 31+ and has different edge semantics (`BlurredEdgeTreatment`). Below 31 fall back to a downsampled + upscaled bitmap, or to the gradient layers alone (layers 2–4 already carry most of the effect). | moderate |
| 17 | **`.surface(.plate)` as a white 5.5 % LIFT rather than an opaque fill** | Trivial to express (`Color.White.copy(alpha = .055)`), but the *reason* is easy to lose: an opaque plate over the ambient wash reads as a hole. Reviewers must not "simplify" it to `surfaceFlat`. | easy |
| 18 | **`onGeometryChange` scroll probes** instead of scroll-offset state | Compose's `LazyListState` recomposition semantics are different, but the invariant still applies: **derive booleans, guard the write, and never hoist the raw offset into screen-level state** (`derivedStateOf` is the idiomatic equivalent). Getting this wrong reproduces the iOS "Today lags" bug on the Library. | moderate |
| 19 | **Non-breaking spaces inside counts** (`"3\u{00A0}episodes\u{00A0}behind"`) | Works in Compose text, but Android string resources with plurals must carry the NBSP explicitly, and the pluralisation itself moves into `plurals.xml` — which changes the shape of `Copy.plural`. Watch that the NBSP is not stripped by a translation pipeline. | easy |
| 20 | **`localizedCaseInsensitiveCompare`** as the one title order | `java.text.Collator.getInstance()` with `Collator.SECONDARY` is the closest match, but it will not be byte-identical for titles like "Ōoku". Pick one collator, use it for **every** sort and tie-break, and never mix in `String.compareTo`. | moderate |
| 21 | **`String.folding(options: [.diacriticInsensitive, .caseInsensitive])`** for `indexKey` | `java.text.Normalizer.normalize(s, NFD)` + strip `\p{Mn}` + `uppercase()`. Equivalent, but the Swift version also folds width/compatibility forms differently for CJK titles — verify against a real library before shipping the rail. | moderate |
| 22 | **Context menus on long-press** with a destructive role | Compose has no `contextMenu`; use a `DropdownMenu` anchored to the card via `combinedClickable(onLongClick =)`. The destructive item's red styling and the "no haptic from the menu itself" rule must be re-established by hand. | easy |
