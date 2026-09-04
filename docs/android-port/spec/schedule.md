# Schedule — the agenda screen

Schedule is the app's calendar of television, and it is an **agenda**, not a grid: one vertical
list, one section per day, a day ticker across the top spanning exactly the window the feed holds
(a week back, two weeks ahead), and rows that are 16:9 art cards rather than poster rows. Three
rules in this file are load-bearing product decisions that were each arrived at by fixing a
shipped bug, and a port that "simplifies" any of them re-introduces the bug by name: **today's
section is always drawn, empty or not** (an agenda that skips an empty today opens on a future day
and its top row's bare clock reads as tonight's); **"today" always means day 0**, never "the first
day that carries something" (the `Today` button hid itself by its own test); and **amber means
today, not selection** — the ticker's selected cell is a neutral raised disc, because in this one
control amber is already spent on the current day. The screen carries exactly one write ("Mark as
watched" on a row that has aired), one long-press menu (the shared franchise quick actions), and
two programmatic scrolls (a ticker tap and the `Today` button); everything else is reading.
Everything below is stated as exact numbers taken from the shipping source, and where the source
carries a comment explaining *why* a number or a branch is what it is, that comment is quoted.

**Source files covered**

| File | Contents |
| --- | --- |
| `ios/Sources/Features/Schedule/ScheduleView.swift` | The whole screen: state, derivation, chrome band, ticker, filters, content state matrix, Earlier fold, day sections, `AiringCard`, the mark flow, `TickerCellPressStyle` |
| `ios/Sources/Features/Schedule/ScheduleReminders.swift` | `ScheduleReminders` — the read-only pending-notification mirror behind the card's bell |

**Depended-on specs** (do not re-derive these; read them): `design-tokens.md` (every
`ThemeColor` / `ThemeSpace` / `ThemeRadius` / `ThemeMetrics` / `ThemeType` / `ThemeMotion` /
`FeedbackToken` value), `primitives.md` (`OverArtLabel`, `LandscapeArt`, `MarkRing`,
`RowPressStyle`, `OverArtPressStyle`, `FilterChipStyle`/`FilterChipLabel`, `ScrollEdgeChrome`,
`differentiatingUnderline`), `primitives-states.md` (`EmptyState`, `InlineNotice`, `StaleStrip`,
`SkeletonGate`, `centredState`, `previouslyRefreshable`), `copy.md` (every string), `models.md`
(`Franchise`, `FranchisePart`, `Airing`, `TimeAnchor`), `appmodel.md` (`scheduleDays`,
`scheduleFeedKey`, `markNext`, `setProgress`, `presentUndo`), `chrome-images.md` (`ArtBackdrop`,
`RemoteImageView`).

---

## 1. Where the screen sits

`ScheduleView` is the root of the **Schedule** tab (`RootView.swift`, `AppTab.schedule`, tab icon
asset `TabSchedule`, tab title "Schedule"). It is constructed as:

```swift
ScheduleView(onOpenDetail: openEpisode,
             onAddShow: { appModel.searchFieldRequested = true; selectedTab = .discover })
    .detailDestinations(push: { push(.schedule, $0) })
```

* `onOpenDetail: (franchiseId: String, zoomID: String, focus: EpisodeFocus?) -> Void` pushes
  `DetailRoute(id:zoomID:focus:)` onto the **Schedule tab's own** `NavigationPath`. Detail is a
  plain push (the `.zoom` transition was tried and retired); `EpisodeFocus(mediaId:episode:)`
  makes Detail open the season's episode list once, on that episode.
* `onAddShow` is only reached from the empty-account state's "Add a show" button: it requests the
  search field and switches to the Discover tab.
* Re-selecting the already-active Schedule tab pops its stack to root.

The tab bar minimises on scroll (`tabBarMinimizeBehavior(.onScrollDown)`, applied on the
`TabView`, iOS 26 only).

---

## 2. The feed: what `AppModel` hands the screen

The screen never walks the library itself. It reads three things off `AppModel`:

| Member | Type | Meaning |
| --- | --- | --- |
| `scheduleDays` | `[ScheduleDay]` | The feed — cached, rebuilt only when the key below changes |
| `scheduleFeedKey` | `ScheduleFeedKey(library: Int, minute: Int64)` | Feed identity. Equal keys ⇒ identical `scheduleDays` |
| `scheduleTodayNoon` | `Int64` | Local **noon** of today, ms epoch — the anchor every day offset is measured from |
| `nowMinute` | `Int64` | `now` truncated to the minute; written only when the minute changes |

Window constants (`AppModel`):

| Constant | Value | Meaning |
| --- | --- | --- |
| `scheduleBack` | `-7` | Seven local days back |
| `scheduleAhead` | `14` | Fourteen local days ahead |
| `Formatting.D` | `86_400_000` | ms/day |
| `Formatting.H` | `3_600_000` | ms/hour |
| `Formatting.minuteMs` | `60_000` | ms/minute |

So the ticker and the feed both span **22 days**, offsets `-7 … +14` inclusive.

### 2.1 `ScheduleEntry` and `ScheduleDay`

```swift
struct ScheduleEntry: Identifiable {
    let franchise: Franchise
    let part: FranchisePart
    let episode: Int
    let at: Int64
    let aired: Bool
    var id: String { "\(franchise.id)/\(part.mediaId)/\(episode)" }
    var dateOnly: Bool { franchise.timeAnchor.isDateOnly }
    var watched: Bool { aired && part.progress >= episode }
}

struct ScheduleDay: Identifiable {
    let id: Int          // day offset from today, negative for the past
    let noon: Int64      // local noon of the day — day arithmetic never lands on a DST seam
    let entries: [ScheduleEntry]   // ascending by instant, then title, then episode
}
```

### 2.2 How the feed is built (`AppModel.buildScheduleDays`)

1. `noon = scheduleTodayNoon`; `todayKey = Formatting.localDayKey(noon)`.
2. For every franchise `f` in the library **where `f.tracksAirings`** (i.e. `effectiveStatus !=
   .planned`), for every `part` in `f.parts`, for every `a` in `part.scheduleAirings`:
   * `offset = Int((f.dayKey(of: a.at) - todayKey) / D)` — the day the episode lives in, read in
     **its own source's calendar**. "a TMDB drop is a date-only fact, and reading its synthesized
     instant locally filed it a day late east of UTC+7."
   * Skip unless `(-7...14).contains(offset)`.
   * `aired = f.timeAnchor.isDateOnly ? offset <= 0 : a.at <= now` — "a TMDB drop is out at some
     point on its day, and the calendar cannot know when, so the whole day counts (the row can be
     marked from the morning on)."
3. For each offset in `-7...14`, sort its entries by `at`, then `franchise.title`, then `episode`.
   Emit a `ScheduleDay` **only when `offset == 0 || !entries.isEmpty`** — empty days are dropped,
   **today survives its own emptiness as the feed's anchor**.

Every part is walked, not just the releasing one: "a season that premieres inside the window is
announced, not releasing, and a finale that aired three days ago belongs to a finished part. The
window is the filter, not the part's status."

`FranchisePart.scheduleAirings` is `airings` when the server sent them, otherwise a synthesised
two-slot list (`lastAiredAt`/`airedEpisodes` and `nextAiringAt`/`nextEpisodeNumber`) so a weekly
show against an older server still lands on its next and last date instead of vanishing.

**Android:** this is pure Kotlin — a `data class` feed built in the shared view-model, memoised on
`(libraryVersion, nowMinute)`. Use `java.time.LocalDate`/`ZoneId` for the two calendars
(`ZoneId.systemDefault()` for AniList, `ZoneOffset.UTC` for TMDB). No risk.

---

## 3. Screen-local derivation

### 3.1 `Row` — one line on the calendar

```swift
struct Row: Identifiable {
    let franchise: Franchise
    let part: FranchisePart
    let episodes: ClosedRange<Int>   // first…last episode the row covers; equal for one episode
    let at: Int64
    let aired: Bool
    let dateOnly: Bool
    var episode: Int { episodes.upperBound }
    var id: String { "\(franchise.id)/\(part.mediaId)/\(episode)" }
    var watched: Bool { aired && part.progress >= episode }
}
```

**Grouping rule (`rows(for:)`):** a **date-only** part that drops several episodes on one day
collapses into **one** row spanning `min…max` of the episode numbers ("Season 2 · 8 episodes"),
not eight identical ones. Every other entry is one row each. Implementation keeps a
`[mediaId: indexInOut]` map, and only registers a part in it when `e.dateOnly` is true; the merged
row keeps the **first** entry's `at`, `aired` and `franchise`/`part`.

### 3.2 `Day` — the screen's own view of a feed day

```swift
struct Day: Identifiable {
    let id: Int
    let noon: Int64
    let rows: [Row]
    var isToday: Bool { id == 0 }
    var isEmpty: Bool { rows.isEmpty }
    var count: Int { rows.count }
}
```

### 3.3 `Derived` — everything computed once per (feed, filter)

| Field | Type | Definition |
| --- | --- | --- |
| `all` | `[Day]` | Every feed day with its rows, **unfiltered** |
| `earlier` | `[Day]` | `shown.filter { $0.id < 0 && !$0.isEmpty }` |
| `ahead` | `[Day]` | `shown.filter { $0.id >= 0 && (!$0.isEmpty \|\| $0.id == 0) }` |
| `todayFiltered` | `Bool` | today is empty **after** filtering but non-empty before it |
| `counts` | `[Int: Int]` | day id → post-filter row count (from `shown`) |
| `live` | `Set<Int>` | day ids where at least one shown row is `!watched` |
| `earlierCount` | `Int` | Σ of `earlier` day counts |
| `earlierUnwatched` | `Int` | Σ of unwatched rows across `earlier` |
| `horizonId` | `Int?` | `raw.last?.id` — the **last day in the raw feed**, i.e. the furthest offset that actually carries something (or `0`) |
| `allEmpty` | `Bool` | every unfiltered day is empty |
| `shownEmpty` | `Bool` | every filtered day is empty |
| `feedKey` | `[Int]` | `(earlier + ahead).map { $0.id * 1000 + $0.count }` — the animation/landing trigger |

where `shown = all.map { Day(id:noon:rows: $0.rows.filter(passes)) }`.

The `|| $0.id == 0` in `ahead` is the anchor rule, quoted verbatim from the source:

> `|| $0.id == 0`: today survives its own emptiness. `AppModel.buildScheduleDays` keeps an empty
> today in the feed on purpose, as the anchor; dropping it here threw that away.

And on the deliberate absence of a "landing day":

> There is deliberately no "landing day" to go with it: the one this used to compute was the first
> NON-EMPTY day ≥ 0, and `awayFromToday` / `goToToday` then treated that as a synonym for today. On
> a day with nothing scheduled the agenda opened on a future day, hid the "Today" button
> (`selectedDay == landing`, so by its own test you were already there) and sent that button to the
> wrong day when it did show. The top row's bare clock — a Wednesday 6:30 PM episode — read as
> tonight's, and its missing mark control read as a bug rather than as "this has not aired".

### 3.4 The derivation cache

```swift
private struct DerivedKey: Equatable {
    let feed: AppModel.ScheduleFeedKey
    let type: MediaFilter
    let unwatched: Bool
}
@MainActor private final class DerivedBox { var key: DerivedKey?; var value = Derived() }
@State private var box = DerivedBox()

private var derived: Derived {
    let key = DerivedKey(feed: appModel.scheduleFeedKey, type: typeFilter, unwatched: unwatchedOnly)
    if box.key == key { return box.value }
    let value = computeDerived()
    box.key = key; box.value = value
    return value
}
```

The box is a **reference type held in `@State`** precisely so filling the cache during a `body`
read does not invalidate the view. In Compose this is `remember(feedKey, typeFilter, unwatchedOnly)
{ computeDerived() }` — trivially cleaner, and the whole hazard disappears.

### 3.5 The filter predicate

```swift
private func passes(_ r: Row) -> Bool {
    switch typeFilter {
    case .all: break
    case .anime: if r.franchise.source != .anilist { return false }
    case .tv:    if r.franchise.source != .tmdb    { return false }
    }
    if unwatchedOnly && r.watched { return false }
    return true
}
private var filterActive: Bool { typeFilter != .all || unwatchedOnly }
```

---

## 4. Screen state

| `@State` | Type | Initial | Notes |
| --- | --- | --- | --- |
| `typeFilter` | `MediaFilter` | `debugTypeFilter` (`.all` in release) | Anime / TV / All |
| `unwatchedOnly` | `Bool` | `debugUnwatchedOnly` (`false` in release) | "Hide watched" |
| `earlierExpanded` | `Bool` | `debugEarlierExpanded` (`false` in release) | The Earlier fold |
| `committed` | `Set<String>` | `[]` | Row ids whose mark is animating |
| `prompt` | `WritePrompt?` | `nil` | The batch-mark confirmation |
| `selectedDay` | `Int` | `0` | The day at the top of the feed — what the ticker highlights |
| `tickerPosition` | `ScrollPosition(idType: Int.self)` | — | The ticker's own scroll position |
| `userScrolled` | `Bool` | `false` | Once a finger has moved the feed, the landing stops correcting |
| `viewportH` | `CGFloat` | `720` | Scroll view height, for centring whole-screen states |
| `chromeBottom` | `CGFloat` | `ThemeMetrics.topChromeHeight` | Global `maxY` of the chrome band, for the wash height |
| `box` | `DerivedBox` | — | The derivation cache (§3.4) |

Environment: `AppModel`, `\.accessibilityReduceMotion`, `\.dynamicTypeSize`.
`private var isAX: Bool { typeSize.isAccessibilitySize }` (AX1–AX5) gates four separate layout
branches; `private var now: Int64 { appModel.nowMinute }`.

Screen-local geometry (`private enum Metrics`):

| Name | Value | Use |
| --- | --- | --- |
| `cellWidth` | `44` | A ticker cell's width. "Seven and a bit fit the width, which is what says 'this scrolls'." |
| `cellGap` | `6` | Between ticker cells |
| `numeralMin` | `34` | The ticker numeral's min width/height (and its disc's diameter) |
| `cardGap` | `ThemeSpace.x5` = `20` | Between two cards on one day |

Plus `@ScaledMetric(relativeTo: .caption) private var dot: CGFloat = 5` — the ticker's
"something airs here" dot, scaling with the caption above it.

### 4.1 The wash source

```swift
private var washCover: String? {
    let d = derived
    if let next = d.ahead.first(where: { !$0.isEmpty })?.rows.first?.franchise.portraitArt { return next }
    if let last = d.earlier.last?.rows.last?.franchise.portraitArt { return last }
    return appModel.library.first?.portraitArt
}
```

"`first(where:)`, not `first`: today leads `ahead` even when it is empty, and an empty day would
otherwise hand the wash to the LAST thing that aired instead of the next." Fallback order: the
next thing to air → the most recent thing that did → whatever the library leads with.

### 4.2 Whole-surface state gates

```swift
private var showsWholeScreenState: Bool {
    if appModel.loading && appModel.library.isEmpty { return true }
    if appModel.libraryEmpty { return true }
    let d = derived
    return d.allEmpty || (d.shownEmpty && filterActive)
}

private var tickerCollapsed: Bool {
    showsWholeScreenState && !(appModel.loading && appModel.library.isEmpty)
}
```

"The day strip stays up while the first library loads — its days come from the clock, not the data
— so the feed lands under it instead of shoving everything down 60 pt the instant the response
arrives. Only a settled whole-screen state folds it away, animated."

---

## 5. Scroll identity: `AgendaID`

```swift
enum AgendaID: Hashable {
    case earlier
    case day(Int)
    case row(Int, String)      // day offset, Row.id

    var day: Int? {
        switch self {
        case .earlier: return nil
        case .day(let d), .row(let d, _): return d
        }
    }
}
```

Every scroll target in the feed maps back to a day, so whatever the system reports as visible names
the day the ticker should show. `.earlier` deliberately reports `nil`: "Only the Earlier row on
screen means today is next under it."

---

## 6. Composition tree

```
ScrollViewReader { proxy in
  ZStack(alignment: .top) {
    ThemeColor.canvas.ignoresSafeArea()
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 0) { content() }
        .scrollTargetLayout()
        .animation(uiSnappy, value: derived.feedKey)
        .animation(uiSnappy, value: earlierExpanded)
        .animation(uiGentle, value: appModel.staleSince(.exactAiring) != nil)
    }
    .safeAreaInset(edge: .top, spacing: 0) { chrome(proxy) }
    .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { viewportH = $0 }
    .tabBarContentMargin()
    .scrollIndicators(.hidden)
    .onScrollPhaseChange { _, phase in if phase == .interacting { userScrolled = true } }
    .onScrollTargetVisibilityChange(idType: AgendaID.self, threshold: 0.2) { … }
  }
}
.scrollEdgeChromeBody(top: false, bottom: true)
.toolbarBackground(.hidden, for: .navigationBar)
.chromeScrollEdgeHidden(.all)
.previouslyRefreshable { await appModel.reload() }
.task { await ScheduleReminders.shared.refresh() }
.onChange(of: derived.feedKey, initial: true) { _, _ in land() }
.navigationTitle(Copy.Schedule.title)                 // "Schedule"
.navigationBarTitleDisplayMode(.inline)
.toolbar { … }                                        // leading: Today · trailing: filter menu
.confirmationDialog(…)                                // batch mark
```

Decisions encoded here, each with its source comment:

* **The stack is NOT pinned.** "A pinned header has to occlude the rows passing under it, which
  means an opaque full-bleed plate — and that plate's top edge cut the wash in a hard horizontal
  step across the screen, the exact seam the shared chrome exists to remove. A day section here is
  one to three rows, so its date is on screen beside its rows the whole time it matters; pinning
  bought nothing and cost the one thing the screen's ground is for."
* **The scroll view is NOT bound to a `ScrollPosition`.** "An id-bound position is sticky: the
  anchored view is re-pinned to the top on every layout change, so a row's own press-scale moved
  the feed 28 pt under the finger and the tap arrived as a cancelled scroll. The feed opens where
  it should by construction — the Earlier row or today's section is its FIRST item — and the two
  programmatic scrolls (a ticker tap, 'Today') are one-shot."
* **Bottom clearance is a scroll-content MARGIN**, `tabBarContentMargin()` =
  `contentMargins(.bottom, ThemeMetrics.tabBarClearance /* 64 + 12 = 76 */, for: .scrollContent)`.
  "Nothing may come to rest inside the bottom ramp. A scroll-content MARGIN, not padding: padding
  inside a stack shorter than the viewport changes no layout at all."
* **Only the bottom scroll edge is drawn** (`scrollEdgeChromeBody(top: false, bottom: true)`); the
  top edge belongs to the chrome band, whose ground *is* the wash. "measured on this screen a
  poster and two lines of row text were plainly legible through the ticker's date numerals and
  beside the title."
* **Inline navigation title**, never large: "a large title collapses on the first scroll and moves
  the top safe area ~50 pt mid-flight, under a ticker that has to hold still."

The bottom chrome is `ScrollEdgeChrome(side: .bottom)`: a 64-pt band (`bottomChromeHeight`) of
`.ultraThinMaterial` masked by a gradient, under a canvas veil with stops
`0 → 0`, `0.55 → 0.25`, `0.85 → 0.75`, `1.0 → 1.0`, followed by 180 pt of solid canvas
(`bottomUnderfill`) offset down past the layout's edge. Under Reduce Transparency the material
layer is omitted.

---

## 7. The chrome band

`chrome(_ proxy:)` is applied as `.safeAreaInset(edge: .top, spacing: 0)`, so it is real layout
that the scroll view insets under, not an overlay.

```
VStack(alignment: .leading, spacing: 0) {
    ticker(proxy)
        .frame(height: tickerCollapsed ? 0 : nil)
        .opacity(tickerCollapsed ? 0 : 1)
        .clipped()
        .accessibilityHidden(tickerCollapsed)
    filterChips
}
.padding(.bottom, tickerCollapsed ? 0 : ThemeSpace.x2 /* 8 */)
.animation(uiGentle, value: tickerCollapsed)
.background { ZStack(alignment: .top) { ThemeColor.canvas; ArtBackdrop(…) }
                .ignoresSafeArea(edges: .top).allowsHitTesting(false).accessibilityHidden(true) }
.onGeometryChange(for: CGFloat.self, of: { $0.frame(in: .global).maxY }) { chromeBottom = $0 }
```

**Collapse by height, never by a conditional:** "taking a scroll view out of the tree and putting
it back re-creates it, and a re-created `.scrollPosition(id:)` does not re-apply."

**The band's ground is the wash:**

```swift
ArtBackdrop(url: washCover,
            tint: washCover == nil ? ThemeColor.accent : nil,
            height: max(chromeBottom, ThemeMetrics.topChromeHeight),
            intensity: ThemeMetrics.rootWashIntensity)   // 0.4
```

> The band's ground is THE WASH … sized to end exactly at the band's own bottom edge. That last
> part is what removes the seam. `ArtBackdrop`'s final stop IS `ThemeColor.canvas`, so at the
> band's bottom the ground is already the canvas the feed scrolls on: warm behind the title and the
> ticker, plain canvas the pixel below, no step anywhere. A flat canvas strip (what this screen
> shipped) put a hard horizontal edge across the wash; a translucent veil (what Library uses over
> its rows) let posters through the date numerals. This is both: opaque, and continuous with the
> content.

`chromeBottom` is **measured, not composed** — "the band's height answers to Dynamic Type and to
whether chips are showing, and the veil is an overlay — it does not feed back into the band's own
layout."

### 7.1 The ticker

```swift
ScrollView(.horizontal) {
    LazyHStack(spacing: 6) {
        ForEach(Array(-7...14), id: \.self) { offset in
            tickerCell(offset, count: d.counts[offset] ?? 0, live: d.live.contains(offset), proxy: proxy)
                .id(offset)
        }
    }
    .scrollTargetLayout()
    .padding(.horizontal, ThemeMetrics.gutter)   // 16
}
.scrollPosition($tickerPosition, anchor: .leading)
.scrollIndicators(.hidden)
.contentMargins(.all, 0, for: .scrollContent)
.fixedSize(horizontal: false, vertical: true)
.padding(.top, ThemeSpace.x1)                     // 4
.accessibilityLabel(Copy.Schedule.ticker)         // "Days"
```

Twenty-two cells, always all of them, whether or not the feed carries that day. Two nested-scroll
defences, both load-bearing:

* `contentMargins(.all, 0, for: .scrollContent)` — "A nested scroll view has to state its own
  margins: the feed's tab-bar clearance is inherited through the environment and would otherwise
  apply here too."
* `fixedSize(horizontal: false, vertical: true)` — "A horizontal scroll view inside a
  `safeAreaInset` is greedy on its cross axis and will take the whole screen; it states what it
  needs."

### 7.2 A ticker cell

Inputs per cell: `offset`, `count` (post-filter), `live` (any unwatched row that day).

```swift
let ts       = appModel.scheduleTodayNoon + Int64(offset) * Formatting.D
let parts    = Formatting.localParts(ts)
let isToday  = offset == 0
let selected = offset == selectedDay
let past     = offset < 0
let enabled  = count > 0 || isToday
```

**Top line (`top`)** — the weekday letter, except on the first of a month:

```swift
let top = parts.d == 1
    ? Formatting.fmtMonthDay(ts).components(separatedBy: " ").first(where: { Int($0) == nil })?.uppercased() ?? ""
    : Formatting.weekdayLetterMonFirst(Formatting.localMondayCol(ts))
```

"The first of a month names the month where its weekday letter would go — the numerals alone cannot
say that '2' comes after '31'." The month word is extracted from the *locale-ordered* "MMMd" string
by taking the first space-separated component that is not an integer, so both `Sep 1` (en_US) and
`1 Sep` (en_GB) yield `SEP`. `weekdayLetterMonFirst` uses the locale's
`veryShortStandaloneWeekdaySymbols` — "not the first character of a name that has no reason to be
Latin".

**Layout** — `VStack(spacing: 3)`, three elements:

| Element | Type token | Ink | Geometry |
| --- | --- | --- | --- |
| Weekday letter / month | `ThemeType.caption` (SF caption2) | `accent` if today, else `textTertiary` | `lineLimit(1)` |
| Day numeral | `ThemeType.time` (SF subheadline semibold, monospaced digits) | today → `onAccent` `#0B0B0D`; else enabled → `textPrimary`; else → `textSecondary` | `lineLimit(1)`, `minimumScaleFactor(0.7)`, `frame(minWidth: 34, minHeight: 34)` |
| Dot | — | `count > 0 ? (live ? accent : textTertiary) : .clear` | `dot × dot`, base 5, `@ScaledMetric(relativeTo: .caption)`; `accessibilityHidden(true)` |

The numeral's background:

```swift
if isToday      { Circle().fill(ThemeColor.accent) }
else if selected { Circle().fill(ThemeColor.surfaceRaised) }
```

> Calendar's own grammar: today is the filled disc, the selected day a quiet one. A stroked rounded
> square read as a form control.

This is the app's one deliberate exception to "amber selection is legal STATE": amber already means
*today* in this control, so the selected cell gets a neutral `surfaceRaised` (`#242428`) disc.

Ink for a day with nothing on it:

> A day with nothing on it is not a target (`.disabled` below) and looks like one: primary ink only
> for the days the feed can land on. Every cell used to wear the same white, and a tap on "5" that
> did nothing read as a broken control rather than an empty Saturday.

`.differentiatingUnderline(isToday, tint: ThemeColor.accent)` — with **Differentiate Without
Colour** on, today's cell gains a 2-pt accent capsule at its bottom, inset 4 pt horizontally,
offset `y: 3`. Absent otherwise.

**Cell frame and press:** `.frame(width: 44).frame(minHeight: 44).contentShape(Rectangle())`,
`.opacity(past && !selected ? 0.55 : 1)` ("The past recedes as a group — never the selected cell"),
`.animation(uiMicro, value: selected)`, `.buttonStyle(TickerCellPressStyle())`,
`.disabled(!enabled)`.

```swift
private struct TickerCellPressStyle: ButtonStyle {
    // scale 0.985 pressed (1 under Reduce Motion), opacity 0.7 pressed, ThemeMotion.uiPress
}
```

**Tap action:**

```swift
FeedbackCoordinator.fire(.selection)
if offset < 0 { earlierExpanded = true }
scroll(to: .day(offset), day: offset, proxy: proxy)
```

"Every enabled cell now has a section to land on: a day carries rows, or it is today, which renders
empty rather than being skipped."

**Accessibility:** label = `Date(...).formatted(.dateTime.weekday(.wide).day().month(.wide))`
(e.g. "Thursday 3 September"); value = the non-nil members of
`[selected ? "Selected" : nil, isToday ? "Today" : nil, count > 0 ? Copy.episodes(count) : "No episodes"]`
joined with `", "`.

### 7.3 Filter chips

Drawn in the **chrome**, not in the feed — "so a reader who filters, leaves and comes back is never
shown a schedule that merely looks thin."

```swift
if filterActive {
    HStack(spacing: ThemeSpace.x2 /* 8 */) {
        if typeFilter != .all { filterChip(typeFilter.chipLabel) { typeFilter = .all } }
        if unwatchedOnly      { filterChip(Copy.Filter.hideWatched) { unwatchedOnly = false } }
        Spacer(minLength: 0)
    }
    .padding(.horizontal, 16)
    .padding(.top, 8)
    .transition(.opacity)
}
```

A chip is `FilterChipLabel(text:)` (the word + a 10-pt bold `xmark`, 5-pt spacing) in
`FilterChipStyle`: SF footnote semibold, `accent` ink, 12-pt horizontal padding, `minHeight 32`
inside a `minHeight 44` target, capsule filled `accentSoft` (`#F0A24E` @ 0.14) or `surfacePressed`
while pressed. Tapping fires `.selection` and clears that criterion inside
`withAnimation(uiSnappy)`. `accessibilityLabel = "\(text). Remove filter"`.

`MediaFilter.chipLabel`: `.all → "All"`, `.anime → "Anime"`, `.tv → "TV"`.

---

## 8. Toolbar

### 8.1 Leading — the `Today` button

```swift
ToolbarItem(placement: .topBarLeading) {
    Group {
        if awayFromToday {
            Button(Copy.Schedule.today /* "Today" */) { goToToday(proxy) }
                .tint(ThemeColor.interactive)
                .accessibilityLabel(Copy.Schedule.scrollToToday)        // "Scroll to today"
                .accessibilityHint(Copy.Schedule.scrollToTodayHint)     // "Scrolls to today’s episodes"
                .transition(.opacity)
        }
    }
    .animation(uiGentle, value: awayFromToday)
}
```

Two decisions, both quoted:

> LEADING, not trailing. Two items plus a spacer on the trailing side pushed the inline title off
> centre — "Schedule" sat hard against the leading bezel while every other root centres its title.
> It also reads better: the leading slot is where navigation lives, the trailing slot is where the
> view's controls do.

> Explicitly `interactive`: unstyled, this inherited the app-wide accent tint and rendered as an
> amber tappable word — the exact collision the `interactive` token exists to forbid, worst on the
> one screen where amber means "today".

```swift
private var awayFromToday: Bool { selectedDay != 0 || (earlierExpanded && selectedDay < 0) }
```

> The reader is somewhere other than today's section. Measured against TODAY (day 0), which is
> always in the feed — never against "the first day that carries something", which on a quiet day
> is not today and made this read `false` while Wednesday filled the screen.

(The second clause is redundant with the first as written, but is preserved as the explicit
statement that an expanded past also counts as "away".)

### 8.2 Trailing — the filter menu

```swift
Menu {
    Section(Copy.Filter.source /* "Source" */) {
        Picker(Copy.Filter.source, selection: sourceBinding) {
            Text("All").tag(MediaFilter.all)
            Text("Anime").tag(MediaFilter.anime)
            Text("TV").tag(MediaFilter.tv)
        }.pickerStyle(.inline)
    }
    Toggle(Copy.Filter.hideWatched /* "Hide watched" */, isOn: hideWatchedBinding)
} label: {
    Image(systemName: filterActive ? "line.3.horizontal.decrease.circle.fill"
                                   : "line.3.horizontal.decrease")
}
.tint(filterActive ? ThemeColor.accent : ThemeColor.textPrimary)
.accessibilityLabel(Copy.Filter.filter)   // "Filter"
.accessibilityValue(filterValue)
```

`filterValue` = `[typeFilter.chipLabel if != .all, "Hide watched" if on]` joined with `", "`, or
`"Off"` when both are clear. An **active** filter is state, so its glyph is amber and filled.

Both bindings fire the haptic **from the mutation**:

```swift
Binding(get: { typeFilter },     set: { typeFilter = $0;     FeedbackCoordinator.fire(.selection) })
Binding(get: { unwatchedOnly },  set: { unwatchedOnly = $0;  FeedbackCoordinator.fire(.selection) })
```

"The haptic fires from the MUTATION, not from an observer, so one transaction is one haptic."

### 8.3 The batch-mark confirmation

```swift
.confirmationDialog(prompt?.title ?? "",
                    isPresented: Binding(get: { prompt != nil }, set: { if !$0 { prompt = nil } }),
                    titleVisibility: .visible, presenting: prompt) { p in
    Button(p.confirm) { p.perform() }
    Button(Copy.Confirm.cancel /* "Cancel" */, role: .cancel) {}
} message: { p in Text(p.message) }
```

`WritePrompt` is `FranchiseDetailView.WritePrompt` — `{ id: UUID, title, message, confirm,
destructive = false, perform: () -> Void }`.

---

## 9. Content — the state matrix

`content()` is evaluated inside the `LazyVStack`. The branches, **in order**:

| # | Condition | Rendered |
| --- | --- | --- |
| 1 | `appModel.loading && library.isEmpty` | `SkeletonGate(isLoading: true) { feedSkeleton } content: { EmptyView() }` |
| 2 | `appModel.loadError && appModel.libraryEmpty` | `centred { EmptyState(SyncCenter.shared.isOnline ? .serverNoCache : .offlineNoData, prominence: .major, primary: { Task { await appModel.reload() } }) }` |
| 3 | `appModel.libraryEmpty` | `centred { EmptyState(.emptySchedule, prominence: .major, primary: onAddShow) }` |
| 4 | otherwise | strip (below) + feed |

Within branch 4, first a **freshness strip**, at most one:

| Condition | Rendered |
| --- | --- |
| `appModel.sectionFailed` (`loadError && !library.isEmpty`) | `InlineNotice(Copy.Notice.schedule) { Task { await appModel.reload() } }` |
| else `appModel.staleSince(.exactAiring)` non-nil | `StaleStrip(since:now:)` |

both with `.padding(.horizontal, 16).padding(.top, ThemeMetrics.labelGap /* 10 */)`. The
`.exactAiring` staleness threshold is **30 minutes** past `AppModel.lastLoadedAt`. Its appearance
is animated `uiGentle` on the stack: "The stale strip arrives on the 30-minute clock while the feed
is being read; it used to snap in and push every row down unannounced."

Then the feed, three further branches:

| Condition | Rendered |
| --- | --- |
| `derived.allEmpty` | `centred { EmptyState(.nothingScheduled, prominence: .major) }` — no button |
| `derived.shownEmpty && filterActive` | `centred { EmptyState(.noFilterMatches, prominence: .major, primary: { fire(.selection); withAnimation(uiSnappy) { typeFilter = .all; unwatchedOnly = false } }) }` |
| otherwise | Earlier row (if any) → expanded earlier days → `ahead` day sections → `feedTail` |

`centred` = `.padding(.horizontal, 16).centredState(contentH: viewportH)`, i.e.
`frame(maxWidth: .infinity, minHeight: max(0, viewportH - 90), alignment: .center)` — 90 is
`tabBarVisualHeight`, **not** the 76-pt scroll clearance: "subtracting a scroll inset when centring
pushed every empty state ~81 pt above true centre."

### 9.1 Exact empty-state copy

| State | Symbol (SF) | Title | Supporting | Button |
| --- | --- | --- | --- | --- |
| `.serverNoCache` | `exclamationmark.circle` | "Couldn’t load your library" | "Something went wrong. Try again in a moment." | "Try again" (quiet capsule — it is a recovery) |
| `.offlineNoData` | `wifi.slash` | "You’re offline" | "Connect to the internet to load your library." | "Try again" (quiet capsule) |
| `.emptySchedule` | `calendar` | "Nothing scheduled" | "Add a show and its air dates appear here." | "Add a show" (amber capsule — a next step) |
| `.nothingScheduled` | `calendar` | "Nothing scheduled" | "None of the shows you follow have an upcoming date." | *none* |
| `.noFilterMatches` | `slider.horizontal.3` | "No titles match" | "Clear the filters to see everything in your library." | "Clear" (amber capsule) |

`EmptyState(.major)` anatomy: 44-pt `textTertiary` symbol (scaled `relativeTo: .title3`), 16-pt gap,
title in `showTitleL` (Outfit SemiBold 22) centred, 8-pt gap, supporting in `callout`
(Outfit Regular 16) `textSecondary` centred, 20-pt gap, one hugging button; whole block
`frame(maxWidth: 300)`, `transition(.opacity)`, VoiceOver label = `"\(title). \(supporting)"`.

Note the choice between `.serverNoCache` and `.offlineNoData` is made by `SyncCenter.isOnline`
(an `NWPathMonitor` reading), **never guessed from the error**.

### 9.2 The feed skeleton

Three repeats of the airing card's own anatomy — "so the swap lands in place. It drew poster rows
until 3 Sep, the row the calendar stopped using."

```swift
ForEach(0..<3) { _ in
    SkeletonLine(width: 116, height: 11).padding(.top, 30).padding(.bottom, 10)   // the day header
    SkeletonBlock(height: nil, radius: 22).aspectRatio(16.0/9.0, contentMode: .fit)
    SkeletonLine(width: 212, height: 13).padding(.top, 8)                          // the title
    SkeletonLine(width: 96,  height: 10).padding(.top, 4)                          // the meta line
}
.padding(.horizontal, 16)
.accessibilityHidden(true)
```

Fill `ThemeColor.skeleton` (`#F4F1EC` @ 0.11); line radius 6.

`SkeletonGate` owns the timing and no screen re-implements it: **nothing for the first 240 ms**;
once shown, the skeleton stays **at least 320 ms**; the swap is a **120 ms crossfade**
(`uiCrossfade` = `uiReduced` = `easeOut 0.12`); a 1.4-s opacity breath 0.88 ↔ 1.0 while visible
(static 0.92 under Reduce Motion); a small `ProgressView` after 800 ms. The gate wraps only the
skeleton here ("the feed stays a lazy stack, so the gate holds the skeleton alone and the swap
rides the stack's own `feedKey` animation").

---

## 10. The Earlier fold

`earlier` days are collapsed behind one 44-pt row above today. "so the screen opens on what is
ahead and still lets the reader check what they missed."

**Meta line** (`earlierMeta(count:unwatched:)`):

```swift
if unwatched == 0        { return Copy.episodes(count) }          // "3 episodes"
if unwatched == count    { return Copy.Schedule.toWatch(unwatched) } // "3 to watch"
return "\(Copy.episodes(count)) · \(Copy.Schedule.toWatch(unwatched))"
```

"'3 to watch' while every earlier episode is still unwatched, '3 episodes' once none is, and both
only when they differ — '3 episodes · 3 to watch' said one number twice."
`Copy.episodes(n)` binds the numeral to its noun with a **non-breaking space** (`3\u{00A0}episodes`)
so a numeral never ends a line its unit does not start.

**Layout** — a `Button` whose label switches layout at accessibility sizes:

```swift
let layout = isAX ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                  : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 5))
```

"The label and its count reflow onto two lines at accessibility sizes rather than truncating the
count away — 'EARLIER 3 episodes · 1 to…' hid the only number on the row that says whether opening
it is worth it."

| Element | Type | Ink | Notes |
| --- | --- | --- | --- |
| "Earlier" | `sectionLabel` (SF caption2 semibold, tracking 1.0), `.textCase(.uppercase)` | `textSecondary` | `fixedSize(horizontal: false, vertical: true)` |
| "· \<meta\>" | same | `unwatched > 0 ? textSecondary : textTertiary` | `lineLimit(isAX ? nil : 1)` |
| `Spacer(minLength: 8)` | — | — | non-AX only |
| `chevron.forward` | `.system(size: 12, weight: .semibold)` | `textTertiary` | non-AX only; `rotationEffect(.degrees(earlierExpanded ? 90 : 0))`, `animation(uiMicro, value: earlierExpanded)`, `accessibilityHidden(true)` |

"12 semibold — a step lighter than the section header's 14, beside an 11-pt label rather than a
20-pt title."

The type family is the **day-label** family, not the section-title family: "it was the
section-title family while the day headers were, and followed them out of it (3 Sep) so the show's
title is the only title here."

Frame: `.padding(.horizontal, 16)`, `.padding(.vertical, isAX ? 8 : 0)`,
`.frame(minWidth: 0, maxWidth: .infinity, minHeight: 44, alignment: .leading)`,
`.contentShape(Rectangle())`, `.buttonStyle(RowPressStyle())` (16-pt-radius `surfacePressed` @ 0.6
overlay, scale 0.992), `.id(AgendaID.earlier)`.

**Tap:** `FeedbackCoordinator.fire(.selection); earlierExpanded.toggle()` — the expansion rides the
stack's `.animation(uiSnappy, value: earlierExpanded)`.

**Accessibility:** label `"Earlier, \(earlierMeta(...))"`, hint
`earlierExpanded ? "Hide earlier episodes" : "Show earlier episodes"`, `.isButton` trait added.

---

## 11. A day section

```swift
Section {
    if day.isEmpty {
        if isAX { emptyDayRow }        // at reading sizes the statement lives in the header
    } else {
        ForEach(Array(day.rows.enumerated()), id: \.element.id) { i, r in
            row(r, day: day.id, last: i == day.rows.count - 1)
        }
    }
} header: {
    dayHeader(day)
}
```

### 11.1 The day header — an eyebrow, no rule, no ground

```swift
let word     = dayWord(day)                                   // "Today" / "Tomorrow" / "Friday"
let date     = Formatting.fmtMonthDay(day.noon)               // "3 Sep" / "Sep 3", locale-ordered
let shortDay = Formatting.weekdayShortMonFirst(Formatting.localMondayCol(day.noon))   // "Thu"
let detail   = (day.id == 0 || day.id == 1) ? "\(shortDay) \(date)" : date
let text     = "\(word) · \(detail)"
```

So: **"TODAY · THU 3 SEP"**, **"TOMORROW · FRI 4 SEP"**, **"FRIDAY · 11 SEP"** — the weekday is
repeated in the detail only for today and tomorrow, where the word alone does not name a day.

```swift
private func dayWord(_ day: Day) -> String {
    switch day.id {
    case 0: return Copy.Schedule.today        // "Today"
    case 1: return Copy.Schedule.tomorrow     // "Tomorrow"
    default: return Formatting.weekdayNameMonFirst(Formatting.localMondayCol(day.noon))  // "Friday"
    }
}
```

Layout: `HStack(alignment: .firstTextBaseline, spacing: 8)` containing an inner
`HStack(alignment: .firstTextBaseline, spacing: 5)` of the word and `"· \(detail)"`, then a
`Spacer(minLength: 8)`, then the count slot.

| Element | Type | Ink |
| --- | --- | --- |
| Day word | `sectionLabel`, `.textCase(.uppercase)`, `lineLimit(1)` | `day.isToday ? accent : textSecondary` |
| "· \<detail\>" | same | `textTertiary` |
| Count slot | same | `textTertiary` |

Padding: `.padding(.horizontal, 16)`, `.padding(.top, ThemeMetrics.sectionGap /* 30 */)`,
`.padding(.bottom, ThemeMetrics.labelGap /* 10 */)`, `frame(maxWidth: .infinity, alignment:
.leading)`, `.id(AgendaID.day(day.id))`.

**No ground and no rule.** "A new day is a section break; the label belongs to the card under it."
And: "No ground of its own: the wash is the screen's ground and a plate here would carve a step out
of it."

The whole demotion from section-title to eyebrow is quoted in full because it is the rule the port
must not undo:

> Not the section-title family any more (3 Sep): the card under this label names its show at
> `rowTitle`, Outfit SemiBold 17, ten points down — a day set in Outfit SemiBold 20 was the same
> shape in the same ink, and "Tomorrow" and "Mushoku Tensei" read as two rows of one list. A label
> above a title is the hierarchy every other grouped list in the app draws.

**The count slot** — three cases, in order:

```swift
if day.isEmpty && !isAX      { Text(emptyDayText) }      // "Nothing scheduled" / "No episodes"
else if day.count > 1        { Text(Copy.episodes(day.count)) }   // "3 episodes"
// day.count == 1 → nothing
```

"Only when it says something: '1 episode' over a single card restates the card. An empty today says
so HERE, on its own baseline, not as a 44-pt row under the header: the agenda used to open on the
ticker, the Earlier row, a 'Today' header, one grey line and a 'Tomorrow' header before its first
card (3 Sep)."

**Accessibility:** `.accessibilityElement(children: .ignore)`,
label `"\(text), \(day.isEmpty ? emptyDayText : Copy.episodes(day.count))"`, trait `.isHeader`.
"'0 episodes' is a count, not a state. An empty today speaks the same words the line under it
prints, so VoiceOver and the screen agree."

### 11.2 The empty day

```swift
private var emptyDayText: String {
    derived.todayFiltered ? Copy.Schedule.noEpisodes         // "No episodes"
                          : Copy.Schedule.nothingScheduled   // "Nothing scheduled"
}
```

"'No episodes' when the filter is what emptied it" — there *are* some; you filtered them.

At accessibility sizes only, where the header's count slot cannot hold a sentence, the statement
moves to a row:

```swift
Text(emptyDayText)
    .type(ThemeType.rowMeta)                      // SF footnote
    .foregroundStyle(ThemeColor.textTertiary)
    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    .padding(.horizontal, 16)
```

Only today can be empty — every other empty day is dropped by `buildScheduleDays` — and "it has to
be SAID rather than skipped: an agenda whose first section is a future day tells the reader the
first card is tonight's."

### 11.3 The feed tail

```swift
let text = derived.horizonId.map {
    Copy.Schedule.everythingThrough(
        Formatting.fmtMonthDay(appModel.scheduleTodayNoon + Int64($0) * Formatting.D))
} ?? Copy.Empty.nothingScheduled.title
```

→ **"That’s everything through Sep 17"** (curly apostrophe), or "Nothing scheduled" when the feed
has no horizon. Rendered `rowMeta` / `textTertiary`, `fixedSize(horizontal: false, vertical: true)`,
`frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)`, `.padding(.horizontal, 16)`,
`.padding(.top, ThemeSpace.x3 /* 12 */)`.

"The end of the horizon, and it NAMES the horizon — and it is now true, because the feed holds
every dated episode up to it." Note `horizonId` is the **last day that carries something**, not a
flat +14: on a library whose furthest dated episode is nine days out, the line says the ninth day.

---

## 12. `AiringCard` — the row

> One airing as television: the show's art wide, the moment as a pill on it, the episode named
> beneath, the mark ring beside that while there is something to mark. A 60-pt poster row with a
> clock in a column said "list"; the calendar now reads like Apple TV's Coming Soon and Netflix's
> New & Hot, which is what a calendar of television should look like.

### 12.1 What the row computes before drawing

```swift
let f           = r.franchise
let isCommitted = committed.contains(r.id)
let watched     = r.watched || isCommitted
let showsAction = r.aired && !r.watched && appModel.isInLibrary(f.id)
let batch       = r.aired && r.episode > r.part.progress + 1
let time        = r.dateOnly ? nil : Formatting.fmtTime(r.at, anchor: f.timeAnchor)
let hasReminder = !r.aired && ScheduleReminders.shared.has(mediaId: r.part.mediaId, episode: r.episode)
let zoom        = "sched/\(f.id)/\(r.episode)"
```

`showsAction` reads `r.watched` (the data), never `isCommitted`: "The control stays put through the
commit so the check can DRAW in place; only a row that was already watched when the screen loaded
starts as a settled one."

`Formatting.fmtTime` returns `""` for a `.utcDate` anchor, so a TMDB row never invents a clock; the
`r.dateOnly` guard makes that explicit and passes `nil`.

The row is then:

```swift
AiringCard(franchise: f, meta: metaLine(r), time: time, aired: r.aired, watched: watched,
           dateOnly: r.dateOnly, hasReminder: hasReminder, zoomID: zoom,
           trailing: { trailing(r, showsAction:marked:batch:time:hasReminder:) }) {
    onOpenDetail(f.id, zoom, EpisodeFocus(mediaId: r.part.mediaId, episode: r.episode))
}
.padding(.horizontal, ThemeMetrics.gutter)          // 16
.padding(.bottom, last ? 0 : Metrics.cardGap)       // 20
.franchiseQuickActions(appModel.isInLibrary(f.id) ? f : nil, appModel: appModel)
.accessibilityValue(watched ? Copy.Accessibility.complete
                            : (time.map { "\($0)\(hasReminder ? ", \(Copy.Schedule.reminderSet)" : "")" } ?? ""))
.animation(uiMicro, value: isCommitted)
.id(AgendaID.row(day, r.id))
```

The long-press menu is the shared `FranchiseContextMenu`: "Mark N episodes as watched" (only when
the releasing part is behind), the five `WatchStatus` options in menu order
(Watching · Planned · Watched · Paused · Dropped, the current one glyphed `checkmark`), a divider,
and a destructive "Remove from Library". "a row here is the same show."

### 12.2 The meta line

```swift
private func metaLine(_ r: Row) -> String {
    let n = r.episodes.count
    if n > 1 {
        let label = r.part.canonicalLabel
        let drop  = Copy.episodes(n)
        return label.isEmpty || r.franchise.parts.count == 1 ? drop : "\(label) · \(drop)"
    }
    return r.franchise.watchContext(part: r.part, episode: r.episode)
}
```

* Single episode → the shared watch-context rule: `"Season 4 · Episode 21"` on a multi-part show,
  `"Episode 21"` on a single-part one, the bare part label for a movie. A `Season N: Subtitle`
  label compacts to `Season N` (`Copy.compactPartLabel`).
* A same-day date-only drop → `"Season 2 · 8 episodes"`, or bare `"8 episodes"` when the part has
  no label or the show has one part.
* Notation is fixed by the copy table: **"Episode 21", never "E21" or "Ep 21".**

### 12.3 The card's structure

```swift
VStack(alignment: .leading, spacing: ThemeSpace.x2 /* 8 */) {
    Button(action: action) { art.contentShape(Rectangle()) }
        .buttonStyle(OverArtPressStyle())
    HStack(alignment: .center, spacing: ThemeSpace.x3 /* 12 */) {
        Button(action: action) {
            VStack(alignment: .leading, spacing: ThemeSpace.x0_5 /* 2 */) {
                Text(franchise.displayTitle).type(rowTitle).foregroundStyle(textPrimary)
                    .lineLimit(2).multilineTextAlignment(.leading)
                Text(meta).type(rowMeta).foregroundStyle(textSecondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        trailing()
    }
}
.opacity(watched ? 0.72 : 1)
.accessibilityElement(children: .contain)
.accessibilityLabel([franchise.title, meta, pill].compactMap { $0 }.joined(separator: ", "))
```

Two separate buttons (art and text block) with the same action and different press styles; the
`trailing()` control sits outside both so it is never swallowed by the row's target.

| Element | Value |
| --- | --- |
| Title type | `ThemeType.rowTitle` — Outfit SemiBold 17, tracking −0.20, `relativeTo: .headline` |
| Title source | `franchise.displayTitle` = `title.shelfShortened` (subtitle wrappers stripped; a >40-char `Title: Subtitle` keeps its identity half) |
| Title lines | 2 |
| Meta type | `ThemeType.rowMeta` — SF footnote, `textSecondary`, 1 line |
| Watched dim | whole card `opacity 0.72` |
| Art press | `OverArtPressStyle`: opacity 0.88 pressed (0.72 under Reduce Motion), scale 0.99, `uiPress` |
| Text press | `RowPressStyle`: `surfacePressed` @ 0.6 in a 16-pt rounded rect, scale 0.992 |

VoiceOver hears the **full** `franchise.title`, never the shortened one.

### 12.4 The pill

```swift
private var pill: String? {
    if let time { return time }        // "7:30 PM" / "21:00" on a 24-hour device
    return dateOnly ? Copy.Label.newEpisode : nil     // "New episode"
}
```

"'7:30 PM' for a timed slot; a date-only drop says what it is instead of inventing a clock."
Clock strings come from `DateFormatter` with `timeStyle = .short`, so the device's 24-Hour Time
switch is honoured, and the formatter cache re-keys on `locale.identifier | locale.hourCycle |
TimeZone.current.identifier`.

### 12.5 The art layer

```swift
let shape = RoundedRectangle(cornerRadius: ThemeRadius.card /* 22 */, style: .continuous)
let wide  = franchise.wideArt
ZStack(alignment: .bottomLeading) {
    shape.fill(ThemeColor.surfaceRaised)
    LandscapeArt(url: wide.url, portraitSource: wide.portraitSource, maxPixel: 1100)
    if let pill {
        HStack(spacing: ThemeSpace.x2 /* 8 */) {
            OverArtLabel(text: pill, tint: aired ? ThemeColor.textPrimary : ThemeColor.accent)
            if hasReminder { bell }
        }
        .padding(ThemeSpace.x3)   // 12
    }
}
.frame(maxWidth: .infinity)
.aspectRatio(16.0/9.0, contentMode: .fit)
.clipShape(shape)
.overlay(shape.strokeBorder(ThemeColor.posterEdge, lineWidth: 1))
.overlay(alignment: .topTrailing) { if watched { tick } }
.shadow(.art)
.zoomSource(zoomID)
```

**16:9 by RATIO, never a fixed height**, and gutter to gutter:

> The card is gutter to gutter; a height picked for one width crops the banner to a different
> letterbox at every other one, and this one had also been drawn 16 pt in from each side of its own
> day header (the gutter was applied twice), so the feed had two left edges.

**`franchise.wideArt`** is `WideArt(landscape:portrait:)`: the landscape asset when the catalogue
has one (`images.landscape`, else the legacy `banner` **only when it differs from `cover`** — older
writers copied the poster into it), otherwise the portrait cover with `portraitSource = true`.
`LandscapeArt` then either fills the frame with the banner, or — for a portrait source — composites
the whole cover on its own blurred ground: a `maxPixel: 160` copy blurred 28 pt (`opaque: true`)
under a `Color.black.opacity(0.32)` overlay, with the sharp `.fit` copy over it, 8-pt vertical
padding and a contact shadow (`black 0.45`, radius 8, y 4). **A landscape frame never `.fill`s a
portrait cover.**

| Overlay | Spec |
| --- | --- |
| Ground | `surfaceRaised` `#242428` behind the art |
| Edge | `posterEdge` (white @ 0.09), `strokeBorder` 1 pt, on the 22-pt continuous shape |
| Shadow | `ShadowToken.art` — black @ 0.55, radius 12, y 7 |
| Pill + bell | bottom-leading, 12-pt inset from the art's edges, 8-pt gap between them |
| Tick badge | top-trailing, 12-pt inset |

**`OverArtLabel`**: `HStack(spacing: 6)` (optional 5-pt accent dot — **not used here**), text in
`sectionLabel` uppercased, tinted, `padding(.horizontal, 10)`, `frame(height: 24)`, ground
`scrimStrong` (black @ 0.72) in a `Capsule`, `strokeBorder(hairline /* white @ 0.055 */, 1)`.

**The colour rule for the pill** — the one sentence that must survive the port:

> Amber while the episode is still ahead — the app's one colour rule for a time — ink once it has
> aired.

i.e. `tint = aired ? ThemeColor.textPrimary : ThemeColor.accent`.

**The bell** (a reminder is pending for this exact episode):

```swift
Image(systemName: "bell.fill")
    .font(.system(size: 11, weight: .semibold))
    .foregroundStyle(ThemeColor.textPrimary)
    .padding(7)
    .background(ThemeColor.scrimStrong, in: Circle())
    .accessibilityHidden(true)
```

It is **passive, never a control** — the bell reports that a local notification exists, and there is
no tap target on it. It is spoken through the row's `accessibilityValue` instead
(`", reminder set"`).

**The tick badge** (watched):

```swift
Image(systemName: "checkmark")
    .font(.system(size: 12, weight: .bold))
    .foregroundStyle(ThemeColor.textPrimary)
    .frame(width: 26, height: 26)
    .background(ThemeColor.scrimStrong, in: Circle())
    .overlay(Circle().strokeBorder(ThemeColor.hairline, lineWidth: 1))
    .padding(ThemeSpace.x3)      // 12
    .accessibilityHidden(true)
```

"A watched episode wears its tick on the art, as Detail's films do."

`.zoomSource(zoomID)` registers the art as a matched-transition source under `"sched/<id>/<ep>"`.
**Nothing consumes it** — Detail is a plain push, and the `.zoom` transition was retired on 3 Sep —
so the port can drop this entirely.

### 12.6 The trailing control

```swift
@ViewBuilder
private func trailing(_ r: Row, showsAction: Bool, marked: Bool, batch: Bool,
                      time: String?, hasReminder: Bool) -> some View {
    if showsAction {
        MarkRing(marked: marked,
                 style: .quiet,
                 label: batch ? "Mark \(Copy.episodes(r.episode - r.part.progress)) of \(r.franchise.title) as watched"
                              : "Mark \(Copy.episode(r.episode)) of \(r.franchise.title) as watched",
                 markedLabel: Copy.Progress.episodeWatched(r.episode))   // "Episode 21 watched"
        { guard !marked else { return }; mark(r, batch: batch) }
        .transition(.handoff(reduceMotion: reduceMotion))
    }
}
```

**ONE trailing column, one rule for what is in it.** The air time is on the art now, so a card with
nothing to mark carries nothing here. The full reasoning, quoted, because it names two shipped
regressions:

> ONE trailing column, and one rule for what is in it: the action while there is something to do,
> the clock once there is not. The clock is not ALSO appended to the meta line — appended, it
> wrapped ("Season 5 · Episode 9 ·" / "8:30 PM", a line ending on a separator); inlined into a fixed
> column beside the ring, it truncated ("…Episode 9 · 8:3…"), which is what the shipped row did. An
> aired episode's exact minute is the least load-bearing fact on a row that already names its day
> and offers its action; VoiceOver still speaks it.
>
> At ACCESSIBILITY sizes the clock has no column at all: "7:30 PM" set in accessibility type is
> ~180 pt wide, and holding that beside the title squeezed the title into a ~150-pt lane where it
> broke inside a word ("Reincarn / ated").

**`MarkRing(style: .quiet)`** geometry: a 44×44 target holding a 22-pt circle,
`strokeBorder(lineWidth: 1.5)` in `markRingIdle` (white @ 0.34) when unmarked and `accent` when
marked, no fill, ink `accent`, a `DrawnCheck(on:size: 12, tint:)` mask-animated in
(`uiMicro`, spring response 0.22 / damping 0.88). `MarkPressStyle`: scale 0.985, `uiPress`.
Traits: `.isButton`, plus `.isSelected` when marked.

`.transition(.handoff(reduceMotion:))` — insertion `.opacity` on `uiSettle` delayed 80 ms, removal
`.opacity` on `uiDismiss` (easeIn 160 ms); under Reduce Motion both collapse to `uiReduced` with no
delay. In practice the optimistic write lands in the same update as the commit, so the ring's
observed behaviour on a mark is the **removal** branch: it fades out over 160 ms while the tick
badge appears on the art and the card dims to 0.72.

---

## 13. The write — "Mark as watched"

The **only** write on this screen.

```swift
private func mark(_ r: Row, batch: Bool) {
    let f = r.franchise, part = r.part
    if batch {
        let count = r.episode - part.progress
        prompt = .init(title:   Copy.Confirm.batchMarkTitle(count),
                       message: Copy.Confirm.batchMarkMessage(from: part.progress, to: r.episode),
                       confirm: Copy.Confirm.batchMarkConfirm(count)) {
            let prev = part.progress
            appModel.setProgress(franchiseId: f.id, mediaId: part.mediaId, episodes: r.episode)
            commit(r) {
                appModel.presentUndo(UndoState(mediaId: part.mediaId, franchiseId: f.id,
                                               prevProgress: prev, title: f.title,
                                               episode: r.episode, count: count))
            }
        }
        return
    }
    guard let undo = appModel.markNext(franchiseId: f.id, mediaId: part.mediaId) else { return }
    commit(r) { appModel.presentUndo(undo) }
}
```

`batch = r.aired && r.episode > r.part.progress + 1` — i.e. marking this row would skip at least one
episode, so it confirms with the exact count.

**Confirmation copy** (`count` = `r.episode − part.progress`):

| Slot | String |
| --- | --- |
| Title | `"Mark 4 episodes as watched?"` |
| Message | `"Your progress will move from episode 17 to episode 21."` (lower-case "episode" inside a sentence) |
| Confirm | `"Mark 4 episodes as watched"` (no ellipsis — confirmation buttons never end in one) |
| Cancel | `"Cancel"`, `role: .cancel` |

**Single mark** goes through `AppModel.markNext(franchiseId:mediaId:)`, which targets
`min(part.progress + 1, part.progressCeiling)`, fires `.commitLight`, applies the local progress
optimistically and serialises the PUT through `sendProgress`. **A progress mark never rolls back**:
a failure goes to `SyncCenter.record` and the SyncBanner, never a red toast.

**Batch** goes through `setProgress`, which clamps to the part's ceiling and fires `.commitMedium`
(the delta is > 1). Same failure policy.

**The Undo toast** is presented only after the card's handoff settles (`commit`'s completion), and
its message carries the subject: `"<full title> · Episode 21 watched"` for a single mark,
`"<full title> · 4 episodes watched"` for a batch.

### 13.1 `commit` — the settle

```swift
private func commit(_ r: Row, then present: @escaping () -> Void) {
    _ = withAnimation(uiMicro) { committed.insert(r.id) } completion: {
        if unwatchedOnly {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(650))
                _ = withAnimation(uiSettle) { committed.remove(r.id) } completion: { present() }
            }
        } else {
            present()
        }
    }
}
```

> The control fills and the check draws in place; the row settles into its dimmed state and stays
> (a calendar keeps its history) — unless watched rows are hidden, in which case it leaves after a
> short hold.

With **Hide watched** on, the row is already excluded by `passes` once the local write lands, so it
leaves the feed on the stack's `uiSnappy` `feedKey` animation; the 650 ms hold is what makes that
departure legible rather than instantaneous, and the Undo toast is presented after it.

---

## 14. Scrolling

### 14.1 Day tracking — the system reports, the screen never measures

```swift
.onScrollTargetVisibilityChange(idType: AgendaID.self, threshold: 0.2) { ids in
    let days = ids.compactMap(\.day)
    let day = days.min() ?? (ids.isEmpty ? selectedDay : 0)
    guard day != selectedDay else { return }
    selectedDay = day
    keepTickerVisible(day)
}
```

> The system says which targets are on screen; the earliest day among them is the section at the
> top, and the ticker follows it. No coordinate spaces, no pin-line arithmetic — the one thing the
> previous screen got wrong in every capture.

`threshold: 0.2` = a target counts as visible once 20 % of it is on screen. The `?? 0` fallback
covers "only the Earlier row is visible", which means today is next under it; an entirely empty
report keeps the current selection.

### 14.2 The landing

```swift
.onChange(of: derived.feedKey, initial: true) { _, _ in land() }

private func land() {
    guard !userScrolled, !appModel.library.isEmpty, !showsWholeScreenState else { return }
    var t = Transaction(); t.disablesAnimations = true
    withTransaction(t) { tickerPosition.scrollTo(id: 0, anchor: .leading) }
    if selectedDay != 0 { selectedDay = 0 }
}
```

> The feed opens on the Earlier row when there is one — a 44-pt line with today's section directly
> under it, so the reader sees that a past exists without being shown it — and on today's section
> otherwise. Both are the feed's first item, so nothing scrolls; the ticker opens with today as its
> first cell. True on a day with nothing on it too, now that an empty today still renders: the
> agenda always opens where the reader is standing.

**The feed itself never scrolls on landing** — it is already at the top and the top *is* today (or
the Earlier fold immediately above it). Only the **ticker** is repositioned, so today is the first
visible cell and the past sits off the leading edge. The reposition is inside a transaction with
animations disabled.

`userScrolled` flips `true` on the first `.interacting` scroll phase: "The moment a finger touches
the feed it belongs to the reader" — after that the landing never corrects again.

### 14.3 Keeping the ticker in view

```swift
private func keepTickerVisible(_ day: Int) {
    let first = tickerPosition.viewID(type: Int.self) ?? 0
    let visible = 7
    let target: Int
    if day < first                    { target = day }
    else if day > first + visible - 1 { target = day - visible + 1 }
    else { return }
    withAnimation(uiGentle) {
        tickerPosition.scrollTo(id: max(-7, min(target, 14)), anchor: .leading)
    }
}
```

"The ticker shows seven cells; it moves only when the selected day would fall outside them, and then
by the least it can." Seven is a constant, not measured: `44 + 6` per cell over a 393-pt screen with
16-pt gutters gives 7.2 cells, "which is what says 'this scrolls'".

### 14.4 The two programmatic feed scrolls

```swift
private func scroll(to id: AgendaID, day: Int, proxy: ScrollViewProxy) {
    userScrolled = true
    selectedDay = day
    keepTickerVisible(day)
    withAnimation(uiReveal) { proxy.scrollTo(id, anchor: .top) }
}

private func goToToday(_ proxy: ScrollViewProxy) {
    FeedbackCoordinator.fire(.selection)
    let d = derived
    scroll(to: earlierExpanded || d.earlier.isEmpty ? .day(0) : .earlier, day: 0, proxy: proxy)
}
```

1. **A ticker tap** → `scroll(to: .day(offset), day: offset)`, preceded by
   `earlierExpanded = true` when the offset is negative (there would otherwise be nothing to land
   on).
2. **The `Today` button** → "Back to the top of what is ahead: the Earlier row while it is folded
   (today sits right under it), today's own section once the past has been opened."

Both animate on `uiReveal` (`timingCurve(0.22, 1.00, 0.36, 1.00)`, 280 ms) and both set
`userScrolled = true`, permanently retiring the landing.

---

## 15. Animations, transitions and haptics

### 15.1 Animation table

| Trigger | Animation | Token value |
| --- | --- | --- |
| Feed re-layout (`derived.feedKey`) | `uiSnappy` | spring, response 0.34, damping 0.84 |
| Earlier fold (`earlierExpanded`) | `uiSnappy` | ″ |
| Stale strip appears/disappears | `uiGentle` | easeInOut 220 ms |
| Ticker collapse (`tickerCollapsed`) | `uiGentle` | ″ |
| `Today` button appears/disappears | `uiGentle` | ″ |
| Ticker keeps a day visible | `uiGentle` | ″ |
| Ticker cell selection | `uiMicro` | spring, response 0.22, damping 0.88 |
| Earlier chevron rotation | `uiMicro` | ″ |
| Row `isCommitted` | `uiMicro` | ″ |
| Mark-ring check draw | `uiMicro` | ″ |
| Committed → uncommitted (hide-watched hold) | `uiSettle` | spring, response 0.46, damping 0.90 |
| Programmatic feed scroll | `uiReveal` | timingCurve(0.22, 1, 0.36, 1), 280 ms |
| Any press | `uiPress` | easeOut 90 ms |
| Skeleton ↔ content | `uiCrossfade` = `uiReduced` | easeOut 120 ms |

Every one of these goes through `ThemeMotion.pick(_:reduceMotion:)`, which substitutes
`uiReduced` (easeOut 120 ms) when **Reduce Motion** is on. The `land()` reposition is explicitly
un-animated (`Transaction.disablesAnimations = true`).

### 15.2 Transitions

| Element | Transition |
| --- | --- |
| Filter chips row | `.opacity` |
| `Today` toolbar button | `.opacity` |
| `MarkRing` | `.handoff(reduceMotion:)` — in: opacity on `uiSettle` + 80 ms delay; out: opacity on `uiDismiss` (easeIn 160 ms) |
| `EmptyState` | `.opacity` ("an empty state that scales in reads as a celebration of having nothing") |
| `InlineNotice`, `StaleStrip` | `.opacity` |

### 15.3 Haptics — every one, and nothing else

| Action | Token | Physical |
| --- | --- | --- |
| Ticker cell tap | `.selection` | `UISelectionFeedbackGenerator` |
| `Today` button | `.selection` | ″ |
| Earlier fold toggle | `.selection` | ″ |
| Source picker change | `.selection` | ″ |
| Hide-watched toggle | `.selection` | ″ |
| Filter-chip clear | `.selection` | ″ |
| "Clear the filters" from the empty state | `.selection` | ″ |
| Single mark (inside `markNext`) | `.commitLight` | light impact, intensity 0.65 |
| Batch mark (inside `setProgress`, delta > 1) | `.commitMedium` | medium impact, intensity 0.72 |
| Pull-to-refresh crosses 80 pt while a finger is down | `.refreshArmed` | light impact, intensity 0.50 |

Opening Detail fires **nothing** — "Navigation is silent (board 11): no haptic on open."
`FeedbackCoordinator` throttles per token: 40 ms for `.selection`, 300 ms for everything else, and
suppresses everything while the app is not active or when the user has turned haptics off
(`UserDefaults` key `previously.haptics`).

---

## 16. Accessibility

| Element | Behaviour |
| --- | --- |
| Ticker container | label "Days" |
| Ticker cell | label = full date ("Thursday 3 September"); value = "Selected" / "Today" / "3 episodes" \| "No episodes", comma-joined; disabled when the day has nothing and is not today; dot is hidden |
| Ticker (collapsed) | `accessibilityHidden(true)` while the whole-screen state is showing |
| Chrome wash | `accessibilityHidden(true)`, `allowsHitTesting(false)` |
| Filter menu | label "Filter"; value = active criteria joined, or "Off" |
| Filter chip | label "\<criterion\>. Remove filter" |
| `Today` button | label "Scroll to today"; hint "Scrolls to today’s episodes" |
| Earlier row | label "Earlier, 3 episodes · 1 to watch"; hint "Show earlier episodes" / "Hide earlier episodes"; `.isButton` |
| Day header | children ignored; label "TODAY · THU 3 SEP, 3 episodes" (an empty today speaks its own empty line); `.isHeader` |
| Airing card | `children: .contain`; label = **full** `franchise.title`, then the meta line, then the pill, comma-joined |
| Airing card value | "Complete" when watched, else "7:30 PM" plus ", reminder set" when a reminder is armed, else "" |
| Mark ring | unmarked label "Mark Episode 21 of \<full title\> as watched" (batch: "Mark 4 episodes of \<full title\> as watched"); marked label "Episode 21 watched"; traits `.isButton` (+ `.isSelected` when marked) |
| Tick badge, bell, dot, skeleton, chevron | hidden — each is spoken by its row's label or value |
| Skeleton | children ignored, label "Loading" |
| Stale strip | children ignored, label "Updated 8 hours ago" (spelled out, never "8h"), `.isStaticText` |

**Dynamic Type.** Every type token is registered `relativeTo:` a text style and scales. Four
explicit accessibility-size branches (`typeSize.isAccessibilitySize`, AX1–AX5):

1. **Earlier row** — horizontal → vertical layout, chevron and spacer dropped, 8-pt vertical
   padding added, the meta line un-clamped.
2. **Empty today** — the "Nothing scheduled" statement moves out of the day header's count slot
   into its own 44-pt row.
3. **Day header count slot** — the empty-day text is suppressed there (it is the row instead).
4. **`InlineNotice`** — horizontal → vertical, with the Retry link's leading offset changing from
   −4 to −12.

The ticker numeral additionally carries `minimumScaleFactor(0.7)` inside a 34-pt box, and the
"something airs here" dot is `@ScaledMetric(relativeTo: .caption)`.

**Reduce Motion** — every animation collapses to `uiReduced`; press styles stop scaling and dim
instead (`OverArtPressStyle` goes to 0.72 opacity, `TickerCellPressStyle` to scale 1); the
skeleton's breath becomes a static 0.92; `.handoff` becomes a plain opacity fade.

**Reduce Transparency** — `ScrollEdgeChrome` drops its `.ultraThinMaterial` layer and its veil goes
fully opaque (`chromeBarOpacity` 0.74 → 1.0). Nothing else on this screen uses material.

**Differentiate Without Colour** — today's ticker cell gains the 2-pt accent underline
(§7.2). Nothing else on this screen encodes meaning in colour alone: the pill's amber/ink
distinction is backed by the presence or absence of the mark ring, and `live` vs. non-live dots are
backed by the day's own count.

---

## 17. `ScheduleReminders`

```swift
@MainActor @Observable
final class ScheduleReminders {
    static let shared = ScheduleReminders()
    private(set) var pending: Set<String> = []

    func has(mediaId: Int, episode: Int) -> Bool { pending.contains("episode-\(mediaId)-\(episode)") }

    func refresh() async {
        let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
        pending = Set(requests.map(\.identifier).filter { $0.hasPrefix("episode-") })
    }
}
```

"Which episodes have a pending local reminder … **Read-only: the bell is passive, never a
control.**"

* Refreshed **once**, from `ScheduleView`'s `.task { await ScheduleReminders.shared.refresh() }`,
  i.e. every time the screen appears. There is no other call site in the app.
* The identifiers are written by `EpisodeNotifications.sync(library:now:)` as
  `"episode-<mediaId>-<episode>"`. That scheduler arms **three alerts per watching AniList show**
  (`perShow = 3`), round-robin so every show keeps its soonest before any gets its second, capped at
  `maxPending = 48`, from `part.airings` filtered to `at > now`. **TMDB shows are excluded** — their
  air times are synthesized 17:00 UTC, so a time-of-day alert would fire at a meaningless instant.
  Consequence for the port: **the bell can only ever appear on an anime row, on one of that show's
  next three unaired episodes**, and only after notification permission has been granted.
* A missing permission means `sync` returns early and `pending` is empty, so no bells are drawn.

---

## 18. Debug launch arguments

All `#if DEBUG` only; each reads `UserDefaults.standard` (iOS maps `-key value` launch arguments
into the standard defaults), so a scripted simulator run can capture a state without driving the UI.

| Argument | Effect |
| --- | --- |
| `-scheduleEarlier 1` | `earlierExpanded` starts `true` — the Earlier block opens already unfolded |
| `-scheduleFilter anime` \| `tv` | `typeFilter` starts `.anime` / `.tv`; anything else → `.all` |
| `-scheduleHideWatched 1` | `unwatchedOnly` starts `true` |
| `-openTab schedule` | Lands the app on this tab (owned by `RootView`) |

In release builds all three static initialisers return the plain defaults (`false`, `.all`,
`false`).

---

## 19. What Android cannot reproduce directly

| Item | Difficulty | Why, and what to do |
| --- | --- | --- |
| `onScrollTargetVisibilityChange(idType:threshold:)` | **moderate** | No Compose equivalent. Rebuild from `LazyListState.layoutInfo.visibleItemsInfo`: map each visible item's key back to an `AgendaID`, take the minimum `day`, apply a ≥20 %-visible predicate (`item.offset + item.size − viewportStart ≥ 0.2 × item.size`), and drive it from a `snapshotFlow { … }.distinctUntilChanged()`. Behaviourally equivalent and arguably more direct. |
| `ScrollPosition(idType:)` + `viewID(type:)` on the ticker | **moderate** | `LazyListState.firstVisibleItemIndex` gives `first` (offset by the `-7` base). `keepTickerVisible` becomes `animateScrollToItem(index)`. The `.leading` anchor maps to the default `scrollToItem` behaviour. |
| `safeAreaInset(edge: .top)` for the chrome band | **easy** | A `Column { chromeBand(); LazyColumn(…) }` — the band is real layout, so no inset API is needed. Take care that the LazyColumn keeps its own bottom `contentPadding` (76 dp). |
| SF Symbols — `chevron.forward`, `bell.fill`, `checkmark`, `line.3.horizontal.decrease(.circle.fill)`, `calendar`, `slider.horizontal.3`, `wifi.slash`, `exclamationmark.circle`, `arrow.triangle.2.circlepath` | **easy** | **ERRATUM (2026-09-04, PLAN §3.3/§9.2): `docs/android-port/spec/icon-mapping.md` is the ONLY icon authority**, including the family (Rounded), the axes (opsz 24 / GRAD −25 / wght 500 or 400 / FILL) and the vendoring form (committed static `VectorDrawable` XML, never `material-icons-extended`, never an icon font). The names here are indicative; where they disagree with that file, that file wins. Size in dp 1:1. |
| Outfit at `relativeTo:` text styles | **easy** | Outfit is on Google Fonts. Dynamic Type maps to `fontScale`; declare sizes in `sp` and the scaling is automatic. There is no direct analogue of `relativeTo:` clamping — accept linear scaling. |
| `@ScaledMetric(relativeTo: .caption)` for the 5-pt dot | **easy** | `(5 * LocalDensity.current.fontScale).dp`. |
| `minimumScaleFactor(0.7)` on the ticker numeral | **easy** | `BasicText(autoSize = TextAutoSize.StepBased(minFontSize = 0.7 × base))`, or measure-and-shrink. |
| `ThemeMotion` springs (`response`/`dampingFraction`) | **easy** | Convert: `stiffness ≈ (2π/response)²`, `dampingRatio = dampingFraction`. `uiSnappy` (0.34/0.84) ≈ `spring(dampingRatio = 0.84f, stiffness = 341f)`; `uiMicro` (0.22/0.88) ≈ `spring(0.88f, 816f)`; `uiSettle` (0.46/0.90) ≈ `spring(0.90f, 186f)`. |
| `AnyTransition.handoff` asymmetry | **easy** | `AnimatedVisibility(enter = fadeIn(tween(460, delayMillis = 80)), exit = fadeOut(tween(160, easing = EaseIn)))`. |
| `.ultraThinMaterial` in the bottom scroll edge | **moderate** | No system material. Use `Modifier.blur` on a captured backdrop, or — cheaper and visually acceptable at this size — the veil gradient alone over an opaque canvas. The band is 64 dp and terminates opaque, so the loss is small. |
| Liquid Glass tab bar / `tabBarMinimizeBehavior(.onScrollDown)` | **easy to drop** | Android's bottom navigation has its own idiom; a `Scaffold` bottom bar that hides on scroll-down is the closest equivalent and is not load-bearing here. |
| `.zoomSource(zoomID)` | **drop it** | Registered but unconsumed (Detail is a plain push). Do not port. |
| `confirmationDialog` | **easy** | `AlertDialog` with a confirm and a dismiss button. Note the copy rule: confirmation buttons never end in an ellipsis. |
| `Menu` + inline `Picker` + `Toggle` (the filter menu) | **easy** | `DropdownMenu` with a radio group and a switch row. The "Source" section header maps to a `DropdownMenuItem` used as a label, or a small caption row. |
| `contextMenu` (long-press quick actions) | **easy** | `combinedClickable(onLongClick = …)` opening a `DropdownMenu` anchored to the card. |
| `UNUserNotificationCenter.pendingNotificationRequests()` | **moderate** | There is no equivalent read of pending `AlarmManager`/`WorkManager` alerts. Persist the armed set yourself (DataStore or Room) when scheduling, and read that back for `ScheduleReminders.pending`. Keep the same identifier shape `episode-<mediaId>-<episode>`. |
| `DateFormatter` short time honouring 24-Hour Time | **easy** | `DateFormat.getTimeFormat(context)` respects the system 24-hour setting; use `java.time` + `DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT)` with the locale, and re-create the formatter when `ACTION_TIME_CHANGED` / locale changes (the iOS cache re-keys on `locale.hourCycle`). |
| `veryShortStandaloneWeekdaySymbols` | **easy** | `DayOfWeek.getDisplayName(TextStyle.NARROW_STANDALONE, locale)`. |
| Locale-ordered `MMMd` + the "first non-numeric component" month extraction | **moderate** | Prefer the honest version on Android: format the month alone with `TextStyle.SHORT_STANDALONE` rather than parsing a formatted string apart. Keep the *rule* (day 1 shows the month word in the weekday-letter slot). |
| `Transaction.disablesAnimations` around the landing reposition | **easy** | `scrollToItem` (non-animated) instead of `animateScrollToItem`. |
| `DerivedBox` (a reference cache read from `body`) | **easy — and it disappears** | `remember(feedKey, typeFilter, unwatchedOnly) { computeDerived() }`. The whole hazard the box exists to dodge does not exist in Compose. |
| Reduce Motion / Reduce Transparency / Differentiate Without Colour | **moderate** | Android exposes `Settings.Global.ANIMATOR_DURATION_SCALE` (0 ⇒ reduce motion) and `Settings.Secure.ACCESSIBILITY_DISPLAY_INVERSION`/high-contrast text; there is **no** direct Differentiate-Without-Colour flag. Ship today's underline unconditionally, or gate it on high-contrast text. Reduce Transparency has no Android analogue — keep the opaque fallback as the only path if blur is unavailable. |

Two things that are **not** hard but must not be "improved" during the port, because each one is a
fixed bug wearing a different shape: the always-drawn empty today with its statement in the
header's count slot, and the ticker's neutral (not amber) selected disc.
