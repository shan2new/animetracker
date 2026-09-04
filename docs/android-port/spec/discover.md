# Discover / Search — the one browse anatomy

This is the behavioural specification for the Search tab: `ios/Sources/Features/Discover/DiscoverView.swift`
(the screen) and `ios/Sources/Features/Discover/SearchComponents.swift` (`AddControl`, `FactLine`,
`RankGutter`). The screen is one slot with two mutually exclusive view trees in it — **the launchpad**
(trimmed query is empty) and **the results** (trimmed query is non-empty) — swapped with the app's
asymmetric `handoff` transition. Its single most important rule, from `CLAUDE.md`, is *"Search has one
browse anatomy: a 3-column `ShelfCard` poster grid at rest AND focused (recents rows above it once
focused), scopes appear `.onTextEntry`, results are `MediaRow`s only (no top-match card, no headers,
`.row` slot everywhere); the hardened bar hold follows focus (`searchChromeBottom` — the title collapses
when the field has focus, so the hold shrinks to the drawer)."* Everything below serves that sentence.
Two further app-wide rules govern almost every decision here: **amber (`accent`) is never an action
colour** — it is rationed to a real forward-looking fact (`when(item)`, the owned tick) while every
tappable word or glyph uses `interactive` (an alias of `textPrimary`); and **the payoff frame is never
emptier than the question** — the trending grid stays mounted underneath every empty, scoped-out and
error state, because the screen already decoded that artwork.

Read §1 (tokens) first. Every number after it is literal and load-bearing.

---

## 0. Where this screen sits

| Fact | Value |
|---|---|
| Tab | 4th of 4 (`AppTab.discover`), label **"Search"**, SF Symbol `magnifyingglass` |
| Tab role | an **ordinary** tab, deliberately *not* `Tab(role: .search)` — the search-role tab-bar morph does not allow the field to live under the screen's own title (Apple Music's Search is the reference, user, 24 Aug) |
| Container | `NavigationStack` with its own `NavigationPath`; `.tint(ThemeColor.interactive)` (the `TabView` itself is `.tint(ThemeColor.accent)` because a selected tab is *state*) |
| Entry animation | `pageInTransition(isActive:)` — once per tab, ever: opacity 0→1 with a 6-pt upward settle on `ThemeMotion.uiReveal`; under Reduce Motion a pure crossfade with no travel. Never replayed on a later tab switch. |
| Re-selecting the tab | pops the stack to root (`paths[tab] = NavigationPath()`) |
| Callback out | `onOpenDetail: (franchiseId: String, zoomID: String) -> Void` → pushes `DetailRoute(id:zoomID:)` onto the active tab's path. **A plain push, not a zoom** — the `.zoom` transition was tried on 2 Sep and retired on 3 Sep. `zoomID` strings are still registered (`zoomSource`) but nothing consumes them. |
| Callback in | `AppModel.searchFieldRequested` — an "Add a show" CTA on Today / Schedule / Library sets it and switches to this tab; this screen consumes it by presenting the field. |
| Tab-bar behaviour | `tabBarMinimizeBehavior(.onScrollDown)` — the bar minimises on downward scroll, returns on the first upward scroll |
| Haptic on tab change | `.selection` (fired by `MainTabView`, not by this screen) |

---

## 1. Token dependencies

Authoritative source is `DesignSystem/ThemeTokens.swift`; reproduced because the screen is unbuildable
without them. The app is **dark-only** — there is no light palette.

### 1.1 Colour

| Token | Value | Where this screen uses it |
|---|---|---|
| `canvas` | `#09090B` | screen ground (`ThemeColor.canvas.ignoresSafeArea()`), and `chromeVeil` |
| `surfaceFlat` | `#171719` | the circular tile behind a bare recent term's magnifier glyph |
| `surfaceRaised` | `#242428` | the primer's dismiss disc; `PosterSlot`'s pre-decode ground |
| `surfacePressed` | `#353842` | `RowPressStyle` wash, pressed `CompactSquareStyle` fill, pressed `FilterChipStyle` |
| `textPrimary` | `#F4F1EC` | row/card titles, the unowned `plus` glyph |
| `textSecondary` | `#AAA6A0` | all grey facts, the recent-term magnifier glyph, the correction line |
| `textTertiary` | `#85817C` | the primer bell, `EmptyState` symbols, the term row's `arrow.up.backward`, the primer's dismiss × |
| `textDisabled` | `#807C77` | `RankGutter` numerals (unused, see §9.3) |
| `accent` | `#F0A24E` | the `when(item)` lead fact; the owned `checkmark`; the owned control's ring; `FilterChipStyle` label |
| `accentSoft` | `#F0A24E` @ 0.14 | the owned add control's fill (both placements); `FilterChipStyle` capsule ground |
| `interactive` | **alias of `textPrimary`** | "Turn on", "Clear", "Search instead for …", "Retry" |
| `posterEdge` | white 0.09 | the 1-pt edge on every `PosterSlot`; the unowned over-art disc's ring |
| `stroke` | white 0.12 | the unowned row add control's rounded-square border |
| `separatorQuiet` | white 0.045 | the primer's bottom rule; every row separator |
| `scrimStrong` | black 0.72 | the over-art add disc's fill — in **both** states, so the reading never depends on the poster behind it |
| `skeleton` | `#F4F1EC` @ 0.11 | `SkeletonRow` blocks |
| `ambientBackdropFallback` | `#432D21` | `ArtBackdrop`'s warm pre-art wash |
| `chromeBarOpacity` | **0.74** (a Double, not a colour) | the hardened top veil's canvas over its blur — never 1.0 except under Reduce Transparency |

### 1.2 Space, radius, rhythm

| Token | Value | | Token | Value |
|---|---|---|---|---|
| `ThemeSpace.x0_5` | 2 | | `ThemeMetrics.gutter` | **16** |
| `x1` | 4 | | `sectionGap` | **30** |
| `x2` | 8 | | `labelGap` | **10** |
| `x3` | 12 | | `shelfGap` | **12** |
| `x4` | 16 | | `titleGap` | **3** |
| `x5` | 20 | | `artGap` | **14** |
| `x6` | 24 | | `rowCompact` | 56 |
| `x8` | 32 | | `rowStandard` | 88 |
| `ThemeRadius.poster` | 10 | | `rowMedia` | **100** |
| `ThemeRadius.compactControl` | **12** | | `tabBarClearance` | **76** (= `bottomChromeHeight` 64 + `x3` 12) |
| `ThemeRadius.row` | 16 | | `tabBarVisualHeight` | **90** (centring divisor — *not* `tabBarClearance`) |
| `ThemeRadius.card` | 22 | | `searchDrawerHeight` | **52** |
| | | | `inlineBarHeight` | **44** |
| | | | `inlineBarBottom` | `topSafeInset + 44` |
| | | | `barEdgeRamp` | **28** |
| | | | `rootWashHeight` / `rootWashIntensity` | **320 / 0.4** |
| | | | `bottomChromeHeight` / `bottomUnderfill` | 64 / 180 |
| | | | `topSafeInset` | read once from the key window; **59** before a window exists (only a real measurement is cached) |

`ShadowToken.art` = black 0.55, blur radius 12, y +7, x 0. `.none` = clear.

### 1.3 Artwork slots used here

| Slot | Size | Radius | Shadow | Used by |
|---|---|---|---|---|
| `.shelfMedium` | **112 × 168** | 12 | `.art` | every trending grid card |
| `.row` | **60 × 90** | 10 | `.none` | every result row, recents row, AX-size trending row, skeleton row |

`PosterSlot` renders art `.fit` (never `.fill`) over a ground of the poster's own extracted palette
colour at 0.60 opacity over `surfaceRaised`, clipped to a continuous rounded rectangle, with a 1-pt
`posterEdge` border and the slot's shadow. A cover whose aspect ratio misses the slot's by ≤5 % snaps
to fill; a real mismatch keeps the honest fit plus the palette mat. Decode budget is
`max(width, height) × 3` px. No artwork → SF Symbol `photo` at `min(w,h) × 0.28`, `textTertiary`.
The slot is `.accessibilityHidden(true)`.

### 1.4 Type

| Token | Font | Tracking | Used for |
|---|---|---|---|
| `sectionTitle` | Outfit SemiBold 20 (`relativeTo: .title3`) | −0.30 | "Trending now", "Recently searched" |
| `rowTitle` | Outfit SemiBold 17 (`.headline`) | −0.20 | result / recents / term row titles, primer title |
| `rowMeta` | SF footnote (13) | 0 | all grey facts, primer body |
| `rowMetaLead` | SF footnote **semibold** | 0 | the amber `when` lead |
| `shelfTitle` | Outfit Medium 14 (`.subheadline`) | −0.10 | grid card titles |
| `shelfCaption` | SF caption (12) medium | 0 | grid card captions |
| `metadata` | SF footnote | 0 | the correction line, `InlineNotice` text, `SectionHeaderRow` counts |
| `metadataEmphasis` | SF footnote semibold | 0 | **the scope-bar segment labels**, `FilterChipLabel` |
| `listAction` | Outfit SemiBold 13 (`.footnote`) | 0 | "Clear", "Turn on", "Search instead for …", "Retry" |
| `showTitleL` | Outfit SemiBold 22 (`.title2`) | −0.35 | `EmptyState` title at `.major` prominence |
| `callout` | Outfit Regular 16 | −0.10 | `EmptyState` supporting line at `.major` |
| `button` | Outfit SemiBold 16 (`.callout`) | −0.15 | `EmptyState` capsule buttons |
| `sectionLabel` | SF caption2 semibold | **+1.0** | `RankGutter` (unused) |

Outfit scales with Dynamic Type through `relativeTo:`; SF tokens are system text styles. **Android note:**
Outfit is a variable Google font — ship Outfit-Regular/Medium/SemiBold/Bold as resources and map
`relativeTo:` onto Compose's `TextStyle` + `fontScale`. SF footnote/caption/caption2 map to Roboto at
13/12/11 sp with the same `fontScale` multiplier. Tracking is in points → `letterSpacing` in sp
(negative values are legal in Compose).

### 1.5 Motion

| Token | Curve | Used for |
|---|---|---|
| `uiPress` | `easeOut(0.09)` | every press style |
| `uiMicro` | `spring(response: 0.22, damping: 0.88)` | the `plus`⇄`checkmark` symbol replacement |
| `uiSnappy` | `spring(0.34, 0.84)` | clearing the scope; removing a recent; a new result-set arrival; `clearRecents` |
| `uiSettle` | `spring(0.46, 0.90)` | primer show/hide; the incoming half of `handoff` |
| `uiGentle` | `easeInOut(0.22)` | launchpad↔results value animation; `fieldPresented` layout; the busy dim; the hardened-veil crossfade |
| `uiReveal` | `timingCurve(0.22, 1.00, 0.36, 1.00, 0.28)` | page-in |
| `uiDismiss` | `easeIn(0.16)` | the outgoing half of `handoff` |
| `uiReduced` | `easeOut(0.12)` | **the universal Reduce Motion fallback** |
| `uiCrossfade` | = `uiReduced` | `SkeletonGate`'s 120-ms swap |

`ThemeMotion.pick(token, reduceMotion:)` returns `uiReduced` when Reduce Motion is on. **Every**
animation on this screen goes through `pick` except `SkeletonGate`'s own crossfade and the veil
crossfade (both already reduced-length).

**`AnyTransition.handoff(reduceMotion:)`** — the app's one card-replacement transition, and the reason
this screen does not use a default crossfade:

> *"The launchpad and the results are two entirely different view trees in one slot, so SwiftUI's
> default crossfade dissolved three 124×186 posters and a numbered chart THROUGH a list of rows for
> 220 ms — the double-exposure class of artefact, on this screen's one structural change."*

- Normal: **asymmetric** — insertion `.opacity` on `uiSettle` **delayed 0.08 s**; removal `.opacity` on
  `uiDismiss` (160 ms). The outgoing tree leaves first; the incoming settles into the space it left.
- Reduce Motion: `.opacity` on `uiReduced`, no delay, both directions.

### 1.6 Haptics (`FeedbackCoordinator`)

Every haptic goes through the coordinator; **at most one per transaction**. It is suppressed entirely
when the app is not `.active`, or when the user's "Haptics" preference (`UserDefaults` key
`previously.haptics`, default `true`) is off. Per-token rate floor: `.selection` **0.04 s**, everything
else **0.3 s**.

| Token | UIKit generator | Fired on this screen by |
|---|---|---|
| `.selection` | `UISelectionFeedbackGenerator` | scope changed (`onChange(of: mediaFilter)`); scope chip removed; `setStatus` from the owned menu |
| `.success` | `UINotificationFeedbackGenerator(.success)` | **an add** (inside `AppModel.addToLibrary`); notification permission **granted** |
| `.commitLight` | `UIImpactFeedbackGenerator(.light)` @ intensity 0.65 | `removeFromLibrary` (from the owned menu's Remove) |
| `.refreshArmed` | `.light` @ intensity 0.50 | pull-to-refresh crosses its threshold **while a finger is down** |
| `.directError` | `.error` notification | a write failure toast (`showError`) |

**No haptic on navigation** — opening a show is silent, by design (board 11).

---

## 2. The screen's state

### 2.1 Local view state

| Property | Type | Initial | Meaning |
|---|---|---|---|
| `contentH` | `CGFloat` | 0 | the ScrollView's own height, measured with `onGeometryChange { $0.size.height }`. Sole consumer: `centredState(contentH:)`. |
| `raisedTop` | `Bool` | false | content has scrolled under the bar → the soft top veil hardens. Set from a geometry probe (§4.3). Guarded: only written when the value actually changes. |
| `fieldPresented` | `Bool` | false | binds `.searchable(isPresented:)`. Drives `searchChromeBottom`, whether recents are drawn, and the launchpad's fallback empty state. |
| `primerPending` | `@AppStorage("previously.notifPrimerPending")` `Bool` | false | an add stuck and armed the notification primer. **Persisted**, because the ask is deferred past the undo window and the user may leave the tab. |
| `primerAnswered` | `@AppStorage("previously.notifPrimerAnswered")` `Bool` | false | the user answered the primer once. One-shot forever — iOS only shows its own alert once per install. |
| `canAskForNotifications` | `Bool` | false | resolved from `UNUserNotificationCenter`: only `.notDetermined` can still be asked. |
| `primerVisible` | `Bool` | false | the primer row is mounted. |

Environment read: `AppModel`, `accessibilityReduceMotion`, `dynamicTypeSize`.
`isAX` ≡ `typeSize.isAccessibilitySize` (AX1–AX5).

### 2.2 Shared model state (`AppModel`, `@Observable`, `@MainActor`)

| Property | Type | Notes |
|---|---|---|
| `searchQuery` | `String` | **two-way bound to the field.** Its `didSet` clears `searchExactOnce` and calls `scheduleSearch()`. |
| `searchResults` | `[FranchiseSummary]` | raw, unfiltered, server order |
| `filteredSearchResults` | `[FranchiseSummary]` | `searchResults.filter { matchesMediaFilter($0.source) }` — the **only** surface `mediaFilter` touches |
| `searchBusy` | `Bool` | a request is scheduled or in flight |
| `searchError` | `Bool` | the last non-cancelled request failed |
| `searchCorrection` | `SearchCorrection?` | `{ original, corrected }`, non-nil only when the two differ case-insensitively |
| `searchSources` | `[String: String]?` | `"anilist"`/`"tmdb"` → `"ok"` \| `"failed"` \| `"disabled"` |
| `recentSearches` | `[String]` | bare terms, newest first, cap 10, persisted at `UserDefaults["recentSearches"]` |
| `recentItems` | `[FranchiseSummary]` | shows acted on from a search, newest first, cap 10, JSON at `UserDefaults["recentSearchItems"]` |
| `trending` | `[FranchiseSummary]` | the chart, fetched once per session (limit **10**) |
| `trendingLoading` | `Bool` | `trending.isEmpty && trendingTask != nil` (Today reads it; this screen does not) |
| `searchFieldRequested` | `Bool` | an off-tab CTA asked for the field |
| `mediaFilter` | `MediaFilter` | `.all` \| `.anime` \| `.tv`. Search-only — Today, Schedule and Library always show everything. |
| `nowMinute` | `Int64` | `now` truncated to the minute, written only when the minute changes. This screen observes **this**, never `now`: *"Minute precision is all a 'New episode tomorrow' needs; observing the 20-second tick would re-lay out every row on the screen three times a minute for nothing."* |
| `library`, `libraryIds`, `pendingAdds` | | `isInLibrary(id)` = `libraryIds.contains(id) \|\| pendingAdds.contains(id)` |

`query` (the screen's derived value) ≡ `appModel.searchQuery.trimmingCharacters(in: .whitespaces)`.
Note this trims **spaces only**; the model's own scheduler trims `.whitespacesAndNewlines`.

Sign-out (`teardown()`) resets: `searchQuery = ""`, `searchResults = []`, `searchBusy/Error = false`,
`searchCorrection = nil`, `searchSources = nil`, `trending = []`, `searchFieldRequested = false`,
`mediaFilter = .all`. Recents are **not** cleared (they are device-local browsing history).

**Android:** all of the above is one `ViewModel` + `StateFlow`/`MutableState`, collected with
`collectAsStateWithLifecycle`. `nowMinute` is a `flow { while(true) { emit(minuteTruncated()); delay(20_000) } }
.distinctUntilChanged()`.

---

## 3. Structure

```
ZStack(alignment: .top)
├── ThemeColor.canvas.ignoresSafeArea()
├── ArtBackdrop(url: washURL, height: 320, intensity: 0.4).ignoresSafeArea(edges: .top)
└── ScrollView                                   ← .scrollIndicators(.hidden)
    │                                              .scrollDismissesKeyboard(.interactively)
    │                                              .previouslyRefreshable { refreshTrending() }
    │                                              .tabBarContentMargin()        (bottom 76, scrollContent)
    │                                              .onGeometryChange → contentH
    └── VStack(alignment: .leading, spacing: 0)
        ├── notificationPrimer                    (only while primerVisible)
        └── Group { launchpad | searchBody }      .id(query.isEmpty)
                                                  .transition(.handoff(reduceMotion:))
        …VStack .frame(maxWidth: .infinity, alignment: .leading)
                .animation(pick(uiGentle), value: query.isEmpty)
                .background { Color.clear.onGeometryChange(minY) → raisedTop }
```

Modifiers on the whole `ZStack`, in source order:

```
.scrollEdgeChromeBody(top: true, bottom: true,
                      topHeight: topSafeInset + searchDrawerHeight,   // 52
                      softTop: true, topRaised: raisedTop,
                      topHold: searchChromeBottom)
.toolbarBackground(.hidden, for: .navigationBar)
.chromeScrollEdgeHidden(.all)                     // iOS 26 only; no-op below
.navigationTitle("Search")
.navigationBarTitleDisplayMode(.inline)
.toolbar(.visible, for: .navigationBar)
.searchable(text: $model.searchQuery, isPresented: $fieldPresented,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: Copy.Search.prompt(for: appModel.mediaFilter))
.textInputAutocapitalization(.never)
.autocorrectionDisabled()
.searchScopes($model.mediaFilter, activation: .onTextEntry) { … }
.onSubmit(of: .search) { appModel.recordRecentSearch() }
```

`washURL` = `appModel.trending.first?.portraitArt` — the **unfiltered** chart's leader:

> *"The ambient wash is keyed to the chart's leader: a poster this screen is already loading, so the
> atmosphere costs one decode and never changes under the user mid-session — not even when the scope
> hides it from the chart."*

Two values are computed **once per body** and handed down, never re-read:

```swift
let results  = ResultSet(appModel.filteredSearchResults)
let trending = appModel.trending.filter { appModel.matchesMediaFilter($0.source) }
```

The body used to read `filteredSearchResults` eight times, and `ResultSet`'s duplicate-title scan ran
once per **row** on top of that. The trending filter exists because *"With TV selected the results were
TV-only and the chart underneath them still led with an anime, so the scope bar appeared to govern half
the screen."*

---

## 4. Chrome

### 4.1 The field

The field is the **system's**, under an **inline** title, always — never a hand-rolled `TextField`.
The rewrite note is explicit about what hand-rolling cost: *"throwing away the iOS 26 search morph,
Cancel, the scope bar, the keyboard's return semantics and the localised prompt, and gaining nothing."*

| Property | Value |
|---|---|
| Title | **"Search"** (`Copy.Search.title`), inline display mode, toolbar background hidden |
| Placement | `.navigationBarDrawer(displayMode: .always)` — the field sits **under** the title at rest, and pins to the top with a Cancel button when focused (Apple Music's Search) |
| Prompt | follows the scope: `.all` → **"Search anime and TV"**, `.anime` → **"Search anime"**, `.tv` → **"Search TV"** |
| Capitalisation | **off** (`.never`) |
| Autocorrect | **off** — *"the system field capitalises the first letter and autocorrects romaji titles into English words ('Sousou' → 'Season')"* |
| Return key | `.search`; `onSubmit(of: .search)` calls `recordRecentSearch()`. Before this, *"the field always carried a `.search` return key and then threw the submission away, so RECENT could only ever hold terms left over from an older build."* |
| Keyboard dismissal | `.scrollDismissesKeyboard(.interactively)` — dragging the list drags the keyboard away |

**Android:** **ERRATUM (2026-09-04, PLAN §3.1/§9.2): NOT an M3 `TopAppBar`** — it is banned outright, because it interpolates `containerColor → scrolledContainerColor` (a `surfaceContainer` tonal overlay) as its scroll behaviour progresses, stacking a second uncontrolled hardening layer on `ScrollEdgeChrome`'s 0.74-over-blur, and draws its title at `MaterialTheme.typography.titleLarge` rather than a `ThemeType` token. The bar is an **app-drawn `Box`** inside `ChromeSurface`'s band: title in a `ThemeType` token, actions as ripple-free `clickable` glyphs, inset from `WindowInsets.statusBars` — with a persistent docked `TextField` row beneath it. Compose M3's `SearchBar` expands to full screen when active, which is *not* this behaviour — use a
docked `TextField` inside the app-bar column and drive `fieldPresented` from `FocusRequester` /
`interactionSource.collectIsFocusedAsState()`. Show a "Cancel" text button in the trailing slot only
while focused (it clears focus, and — matching iOS — clears the query). `keyboardOptions =
KeyboardOptions(capitalization = None, autoCorrectEnabled = false, imeAction = Search)`,
`keyboardActions = KeyboardActions(onSearch = { recordRecentSearch() })`. Interactive keyboard dismissal
on scroll needs a `NestedScrollConnection` that calls `softwareKeyboardController.hide()` on the first
downward drag — Compose has no `scrollDismissesKeyboard(.interactively)` equivalent, so the *interactive*
(finger-tracked) part is not reproducible; a plain hide-on-drag is the honest substitute. **Moderate.**

### 4.2 The scope bar

```swift
.searchScopes($model.mediaFilter, activation: .onTextEntry) {
    ForEach(MediaFilter.allCases, id: \.self) { filter in
        Text(Copy.Search.scopeWord(filter)).type(ThemeType.metadataEmphasis).tag(filter)
    }
}
```

- Segments, in order: **"All"**, **"Anime"**, **"TV"** (`Copy.Filter.all/anime/tv`).
- `activation: .onTextEntry` — **the bar appears with the first keystroke, not on focus.** Rationale:
  *"the scope bar is a RESULTS control … On the focused-but-empty page it was a full-width pill pushing
  the recents down for a choice that had nothing to filter yet; the active scope shows there as the
  launchpad's removable token instead."*
- The **labels** are ours (`metadataEmphasis`, a *text style*, so they scale with Dynamic Type); the bar
  chrome around them is the system's. At AX1 they had been measured at exactly the default cap height —
  *"the only controls on the screen still at default size, so the whole bar read as a strip borrowed
  from another app."*
- Changing the scope fires `.selection` and, when a query is present and not busy, re-announces the
  outcome to VoiceOver (§10).

**Android:** **ERRATUM (2026-09-04, PLAN §3.4/§9.2): NOT `SingleChoiceSegmentedButtonRow`.** The scope bar is **the app's own chip row (`FilterChipStyle`)** — a 32/34-dp visible capsule inside a 44-dp target, no stroke when unselected, **amber for the selected scope** because an active filter is STATE — rendered **conditionally on `query.isNotEmpty()`**, directly under the field, animated in/out with `AnimatedVisibility` (fade + expandVertically). Label style = footnote-semibold. Two chip anatomies in one app is the defect this avoids.

### 4.3 The hardened top veil — `searchChromeBottom`

```swift
private var searchChromeBottom: CGFloat {
    fieldPresented
        ? ThemeMetrics.topSafeInset + ThemeMetrics.searchDrawerHeight       // 52
        : ThemeMetrics.inlineBarBottom + ThemeMetrics.searchDrawerHeight    // 44 + 52 = 96
}
```

> *"Where the bar's chrome ends: title + drawer at rest; once the field has focus the title collapses
> and only the field's band remains. The hardened veil and its probe follow it — sized to the resting
> chrome, the veil swallowed the grid's header the moment the field was tapped (captured 2 Sep)."*

The probe, on the scroll content's background:

```swift
Color.clear.onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY }
           action: { minY in
               let raised = minY < searchChromeBottom
               if raised != raisedTop { raisedTop = raised }
           }
```

`onGeometryChange` on the content, **not** `onScrollGeometryChange` — the latter never fires on the
iOS 27 simulator (the same probe Today, Detail and Library use).

The veil itself (`ScrollEdgeChromeModifier` with `softTop: true`): **both** layers stay mounted and only
their opacities trade, crossfading on `uiGentle` — so the swap is a cross-fade, never a re-created
material.

| Layer | Height | Gradient stops (canvas opacity, top→bottom) | Blur mask (`.ultraThinMaterial`) |
|---|---|---|---|
| **Soft** (`raisedTop == false`, opacity 1) | `topSafeInset + 52` | 0.55 @ 0 · 0.30 @ 0.5 · 0 @ 1 | 0.6 @ 0 · 0.3 @ 0.5 · clear @ 1 |
| **Hardened** (`raisedTop == true`, opacity 1) | `searchChromeBottom + 28` | **b** @ 0 · **b** @ `h` · **b × 0.45** @ `h + (1−h)×0.45` · 0 @ 1 | black @ 0 · black @ `h` · 0.42 @ `h + (1−h)×0.45` · clear @ 1 |

where `h = searchChromeBottom / (searchChromeBottom + 28)` and `b = 0.74`
(**`b = 1.0` under Reduce Transparency**, where there is no blur to carry the bar).

The 0.74 is load-bearing: *"at 1.0 the top ~100 pt of every scrolled screen was a flat #09090B slab
('pure black', 3 Sep) with the material under it painted for nothing."*

Bottom edge (always on, never keyed to scroll): a 64-pt band with stops 0 @ 0 · 0.25 @ 0.55 · 0.75 @ 0.85
· full canvas @ 1, blur mask re-stopped identically, followed by **180 pt of solid canvas offset +180 pt
downward** so it passes under the floating tab bar and across the home-indicator strip. Reaching full
canvas is required, not cosmetic: at 0.78 the Liquid Glass rim had un-occluded body copy to refract and
*"the bar duly mirrored it back as legible upside-down text (… a doubled show title on Search) — a frame
that reads as GPU corruption."* Both edges are `allowsHitTesting(false)` and `accessibilityHidden(true)`.

The bottom edge is ours **in both states**: the shipped build passed `bottom: false` on the assumption
that the keyboard owned the bottom, *"which is how a saturated poster came to refract a doubled,
mirrored show title through the tab bar's glass and put an amber rim on the *Today* pill while Search
was the active tab."*

**Android:** two stacked `Box`es with `Brush.verticalGradient(colorStops)` over the content, opacity-
crossfaded by `animateFloatAsState(if (raisedTop) 1f else 0f, tween(220))`. `.ultraThinMaterial` has no
Compose equivalent — use `Modifier.blur` on a captured backdrop, or `RenderEffect.createBlurEffect` on a
`GraphicsLayer` (API 31+). On API < 31 skip the blur and use the Reduce-Transparency branch (opaque bar).
`raisedTop` comes from `LazyListState.firstVisibleItemIndex > 0 || firstVisibleItemScrollOffset > 0`
compared against the chrome height in px. **Moderate** (the material blur is the hard half).

### 4.4 The ambient wash

`ArtBackdrop(url: washURL, height: 320, intensity: 0.4)`, `.ignoresSafeArea(edges: .top)`, drawn from
the very top of the screen — status bar included. Layers, back to front:

1. `RemoteImageView(url, contentMode: .fill, maxPixel: 320)`, clipped to 320 pt, `blur(radius: 56,
   opaque: true)`, `.opacity(0.70 × 0.4 = 0.28)`. Centre-cropped **before** the blur.
2. `LinearGradient([base × baseTop, base × baseMid, .clear], top→bottom)` where `base` = extracted
   palette tint, else `ambientBackdropFallback` `#432D21`; `baseTop = art settled ? 0.60×0.4 : max(0.24, 0.55)`,
   `baseMid = art settled ? 0.10×0.4 : max(0.04, 0.12)`. The floor exists so the band does not read
   **black** on the first load and then jump to twice the luminance when the art decodes.
3. `LinearGradient([accent × 0.07×0.4, .clear])` — a constant breath of brand warmth so Schedule, Search
   and Profile share one atmosphere.
4. Handover: `.clear @ 0.0 · canvas × 0.55 @ 0.55 · canvas @ 1.0`.

No opaque band anywhere (user, 24 Aug). One wash per screen — which is why **every `EmptyState` on this
screen is drawn with `ambient: false`** semantics (the primitive no longer takes the parameter; the rule
survives as "never add a second wash here").

### 4.5 Pull to refresh

`.previouslyRefreshable(threshold: 80) { await appModel.refreshTrending() }` — *"The one root without a
pull: the chart is a network list like any other."* The system `refreshable` does the work; the modifier
adds exactly one thing: `.refreshArmed` fires **once** when pull ÷ 80 ≥ 1 **while a finger is down**
(`onScrollPhaseChange` → `.tracking`/`.interacting`), and re-arms only after the pull falls back below
0.3 so a wobble at the threshold cannot buzz twice. `phase == .idle` disarms.

**Note the asymmetry:** the pull refreshes **trending**, never the query. A failed search is retried
through `InlineNotice`'s "Retry" or the empty state's "Try again", not by pulling.

### 4.6 Bottom margin

`.tabBarContentMargin()` → `contentMargins(.bottom, 76, for: .scrollContent)` — applied to the
**ScrollView**, never inside the stack:

> *"A content MARGIN, not `.padding` inside the stack: padding under a stack that is shorter than the
> viewport changes no layout at all, which is exactly the case the launchpad is in — and it is why the
> sixth chart row came to rest inside the bottom ramp with its enabled `+` at 131/255 against 241 for
> the identical control four rows higher."*

**Android:** `contentPadding = PaddingValues(bottom = 76.dp)` on the `LazyColumn`. Same effect, and the
scrollbar stops with it. **Easy.**

---

## 5. The launchpad (`query.isEmpty`)

```
VStack(alignment: .leading, spacing: 0) {
    if mediaFilter != .all      → scopeChipRow
    if fieldPresented && !recentsEmpty → recentsList.padding(.top, 8)
    if !trending.isEmpty        → trendingGrid.padding(.top, fieldPresented && !recentsEmpty ? 30 : 8)
    else if !SyncCenter.isOnline                     → EmptyState(.searchOffline)  .centredState
    else if mediaFilter != .all && !trending.isEmpty(unfiltered) → EmptyState(.noScopeTrending) .centredState
    else if !fieldPresented || recentsEmpty          → EmptyState(.searchLaunchpad) .centredState
}
.animation(pick(uiGentle), value: fieldPresented)
```

`recentsEmpty` ≡ `recentItems.isEmpty && recentSearches.isEmpty`.

**One page in the slot, at rest and focused.** *"The grid used to become a different list — the same
shows as compact rows — the moment the field was tapped, so the tab's content changed anatomy under the
finger for no reason a reader could name. Apple TV keeps its grid under the keyboard; so does this."*

### 5.1 The scope chip row

Drawn **only when `mediaFilter != .all`** and only on the launchpad — where the scope bar does not exist.

> *"An active scope is VISIBLE whenever the scope bar is not (the bar exists only while there is text):
> a sticky TV/anime scope would otherwise filter the whole grid with nothing on screen saying so and
> nothing to clear it with. Schedule's rule: whatever is filtering the feed sits in the chrome as a
> removable token."*

- `FilterChipLabel(text: mediaFilter.chipLabel)` — the word ("Anime" / "TV") + `xmark` SF Symbol at
  size 10, weight bold, 5-pt gap.
- `FilterChipStyle`: `metadataEmphasis` in **`accent`**, horizontal padding 12, `minHeight 32` inside a
  Capsule filled `accentSoft` (`surfacePressed` while pressed), `contentShape(Capsule())`, then
  `minHeight 44` for the target. Press: scale 0.985 on `uiPress` (opacity 0.72 under Reduce Motion).
  Amber here is legal — an **active filter is state**.
- Tap: `.selection` haptic, then `withAnimation(pick(uiSnappy)) { mediaFilter = .all }`.
- Layout: `HStack(spacing: 8)` + `Spacer(minLength: 0)`, `.padding(.horizontal, 16)`,
  `.padding(.top, 8)`, `.transition(.opacity)`.
- VoiceOver label: **"Anime. Remove filter"** (`Copy.Accessibility.removeFilter`).

### 5.2 Recently searched

Drawn only when **`fieldPresented && !recentsEmpty`**. Section:

```
VStack(alignment: .leading, spacing: 10 /* labelGap */) {
    SectionHeaderRow("Recently searched", actionLabel: "Clear", inlineAction: true) { … }
        .padding(.horizontal, 16)
    VStack(spacing: 0) { [item rows] + [term rows] }.padding(.horizontal, 16)
}
```

- **Header**: `sectionTitle` (Outfit SemiBold 20, mixed case), `.isHeader` trait, `lineLimit(1)`,
  `minimumScaleFactor(0.85)`, plus a trailing **"Clear"** link in `listAction` /
  `interactive` (`InlineLinkButtonStyle`: vertical padding 14, horizontal 12, `minHeight 44`,
  `contentShape(Rectangle())`, pressed opacity 0.55; the header pulls it back by `-12` vertically so the
  header's *layout* height stays the title's own). The header row carries `zIndex(1)` so the padded
  target paints and hit-tests **above** the rows laid out after it. Tapping Clear runs
  `withAnimation(pick(uiSnappy)) { appModel.clearRecents() }` → wipes both `recentItems` and
  `recentSearches` and re-persists.
- **Item rows** (`recentItems`, in order): `MediaRow`
  - `title: item.title` (the **whole** title — no disambiguation, no shortening)
  - `meta: shelfFacts(item).joined(" · ")` — §8.4
  - `poster: item.portraitArt`, `slot: .row` (60×90)
  - `separator: i < items.count - 1 || !terms.isEmpty`
  - `hint: "Opens the show"`, `zoomID: "recent/\(item.id)"`
  - action: `open(item, zoom:)`
  - `.contextMenu { Button(role: .destructive) { withAnimation(pick(uiSnappy)) { removeRecentItem(item.id) } } label: { Label("Remove", systemImage: "trash") } }`
  - **`chevron` defaults to `true` here** — recents rows keep the disclosure indicator; result rows do not.

  The comment names `.queue` (44×66) as Apple Music's recents density and *"the same 44-pt left edge the
  bare-term rows' glyph tile sits on"* — but the shipped call passes **`.row`** (60×90), per the
  cohesion rule "`.row` — the one list slot Library, Search and Schedule share". Build `.row`.
- **Term rows** (`recentSearches`, in order, after the item rows): §5.3.

### 5.3 The bare-term row (`termRow`)

Three decisions, each recorded against what the row was:

> *"the tile is a CIRCLE in the field's own colours … it is a search, not a poster, and a grey square
> beside art tiles read as a poster that failed; a second line, `Copy.Search.termKind`, so the row has
> the same two-line anatomy as the media rows around it instead of one bold word floating in a 60-pt
> band; the trailing glyph is the fill-the-field arrow, not a chevron. A chevron promises a push; this
> row puts the words back in the field (Safari's and YouTube's convention)."*

| Element | Spec |
|---|---|
| Container | `Button` → `RowPressStyle()` (radius 16). `HStack(spacing: 14 /* artGap */)`, `.padding(.vertical, 8)`, `.frame(minHeight: 60)`, `.contentShape(Rectangle())` |
| Tile | `Circle` filled **`surfaceFlat`**, **60 × 60** (`PosterSize.row.size.width`), containing SF Symbol `magnifyingglass` at `.body` weight **semibold**, `textSecondary`. Neutral, **not** amber: *"a recent QUERY is neither a next step nor a state — the amber disc made a search term the warmest object in a list of real shows."* |
| Text | `VStack(alignment: .leading, spacing: 3)`: the term in `rowTitle`/`textPrimary`, `lineLimit(1)`; below it **"Search"** (`Copy.Search.termKind`) in `rowMeta`/`textSecondary` |
| Spacer | `Spacer(minLength: 12)` |
| Trailing glyph | SF Symbol **`arrow.up.backward`**, `.system(size: 13, weight: .semibold)`, `textTertiary`, in a fixed `frame(width: 11, alignment: .trailing)` — verbatim `MediaRow`'s chevron geometry so the term rows share the media rows' x. `accessibilityHidden(true)` |
| Separator | when `separator`: 1-pt `separatorQuiet` rectangle at the bottom, `.padding(.leading, 60 + 14 = 74)` |
| Tap | `appModel.searchQuery = term` — fills the field, which re-schedules the search through the `didSet` |
| Long press | context menu with one destructive item **"Remove"** (`trash`) → `withAnimation(pick(uiSnappy)) { removeRecentSearch(term) }` |
| VoiceOver | `children: .ignore`; label **"\(term), Search"**; hint **"Searches for it again"** (`Copy.Search.termHint`) |

### 5.4 The trending grid

```
VStack(alignment: .leading, spacing: 10 /* labelGap */) {
    SectionHeaderRow("Trending now").padding(.horizontal, 16)
    if isAX  → VStack(spacing: 0) { mediaRow(item, zoom: "trend/\(id)", ambiguous: [], separator: i < n-1) }
                  .padding(.horizontal, 16)
    else     → LazyVGrid(columns: 3 × GridItem(.flexible(), spacing: 12, alignment: .top),
                         alignment: .leading, spacing: 12) { gridCard(item) }
                  .padding(.horizontal, 16)
}
```

- Header carries **no** count, **no** chevron, **no** action — it is a plain `sectionTitle` label.
- **3 columns**, `.flexible()`, column spacing 12, row spacing 12, gutter 16 each side. On a 393-pt
  screen each column measures `(393 − 32 − 24) / 3 = 112.33` pt — i.e. exactly the `.shelfMedium`
  poster width. The cards therefore fill their columns with no slack.
- Items are `alignment: .top`, so a two-line title in one card does not push its neighbours down.

**At accessibility sizes the grid becomes rows, not a one-column grid:**

> *"At accessibility sizes a poster grid has no honest shape — one card per row stretched a caption
> across the screen with its add disc floating at the far edge. The results' own row (poster, name,
> facts, the square add control) is the anatomy that reflows."*

So at AX1–AX5 the chart renders the **exact same `mediaRow`** the results use (§9.1), with
`ambiguous: []`.

#### `gridCard(item)`

| Element | Spec |
|---|---|
| Card | `ShelfCard(title: item.title, caption:, poster: item.portraitArt, slot: .shelfMedium, zoomID: "trend/\(id)") { open(item, zoom:) }` |
| Caption | `[item.source.kindWord, item.year.map(String.init)].compactMap{}.joined(" · ")` → **"Anime · 1999"** / **"TV · 2023"**. **Exactly two facts**: *"a 112-pt caption cannot hold a third, and the owned disc in the art's corner already says the show is in the library ('Watched · Anime / · 2021' wrapped with a middot opening the second line)."* Note this is **not** `shelfFacts` — no status word, no season count. |
| Card title | `title.shelfShortened` (§8.6) in `shelfTitle`, `lineLimit(1...2)` (`1...6` at AX), `minimumScaleFactor(0.82)`, `allowsTightening(true)`, `fixedSize(vertical: true)`. **Never truncated.** |
| Caption style | `shelfCaption` / `textSecondary` (this screen never passes `captionIsLead`), `lineLimit(2)`, `.truncationMode(.tail)` |
| Caption block width | pinned to the poster width (112) at default sizes; `maxWidth: .infinity` at AX |
| Gap poster→text | `ThemeSpace.x2` = 8; title→caption gap = 2 |
| Press | `RowPressStyle(radius: 12)` — a `surfacePressed × 0.6` overlay at the poster's radius, scale 0.992 |
| Add badge | `.overlay(alignment: .topTrailing) { addControl(item, placement: .overArt).padding(-1) }` |
| Quick actions | `.franchiseQuickActions(appModel.franchise(id: item.id), appModel:)` — a long-press menu **only when the show is in the loaded library**; `nil` → no menu at all |
| Frame | `.frame(maxWidth: .infinity, alignment: .leading)` |
| A11y | `.accessibilityLabel(spoken(item, ambiguous: []))`, `.accessibilityHint("Opens the show")`, then `.accessibilityElement(children: .contain)` on the whole card — so the **add control stays a separately focusable element** |

The badge sits **outside** the card's own button on purpose: *"a Button nested inside another Button's
label is a coin-toss for which one gets the tap."* The `-1` inset (`Metrics.overArtControlInset`) puts
the visible 26-pt disc **8 pt inside** the artwork's corner rather than straddling its edge (the 44-pt
target is centred on the 26-pt disc → 9 pt of slack per side; −1 of padding lands the disc at 8).

### 5.5 The launchpad's three empty states

All three are `EmptyState` centred with `.centredState(contentH: contentH)` — `frame(maxWidth: .infinity,
minHeight: max(0, contentH − 90), alignment: .center)` — and `.padding(.horizontal, 16)`.
**The clearance divisor is `tabBarVisualHeight` (90), not `tabBarClearance` (76)**: *"subtracting a
scroll inset when centring pushed every empty state ~81 pt above true centre."*

| Branch (in order) | Copy | Symbol | Button |
|---|---|---|---|
| `trending.isEmpty && !SyncCenter.isOnline` | **"You're offline"** / "Search needs a connection. Trending shows appear when you reconnect." | `wifi.slash` | **"Try again"** → `loadTrendingIfNeeded()`. `isRecovery == true` → the **quiet** `SecondaryButtonStyle2` capsule |
| `trending.isEmpty && mediaFilter != .all && !appModel.trending.isEmpty` (unfiltered) | **"Nothing trending in Anime"** / "Switch the scope to All to see what everyone is watching." | `line.3.horizontal.decrease` | **"Show all"** → `withAnimation(pick(uiSnappy)) { mediaFilter = .all }`. Not a recovery → the **amber** `PrimaryButtonStyle2` capsule |
| `trending.isEmpty && (!fieldPresented \|\| recentsEmpty)` | **"Find your next show"** / "Search anime and TV by title." | `magnifyingglass` | **none** (no `primaryLabel`) |

The offline branch's rationale: *"'Find your next show' over a grid that will never load is a promise,
and the path monitor knows it is an empty one."* The scope branch's: *"The SCOPE emptied the chart, not
the server: name the filter and offer the same one-tap way out `noScopeMatches` gives the results page."*

Note the **fourth** implicit case: `fieldPresented && !recentsEmpty && trending.isEmpty` draws **nothing
below the recents** — no empty state at all, because the recents themselves are content.

`EmptyState` anatomy (`.major` prominence — the only one used here):
symbol at **44 pt** × `@ScaledMetric(relativeTo: .title3)`, `textTertiary`, `accessibilityHidden`,
padding-bottom 16 → title in `showTitleL`/`textPrimary`, centred, `lineLimit(3)` (unbounded at AX),
`fixedSize(vertical:)` → supporting in `callout`/`textSecondary`, centred, padding-top 8 → button block,
padding-top 20, `VStack(spacing: 4)`. Whole block `frame(maxWidth: 300)` then `maxWidth: .infinity`.
`.transition(.opacity)` — *"an empty state that scales in reads as a celebration of having nothing."*
`accessibilityElement(children: .contain)` + `accessibilityLabel(copy.spokenLabel)`.
**A label without a handler draws no button at all** (a dead control is worse than none).

`isRecovery` ≡ `primaryLabel == "Try again" || primaryLabel == "Retry"` → quiet capsule
(`SecondaryButtonStyle2`: `button` type, `textPrimary`, `minHeight 44`, horizontal padding 18,
`surfaceFloating` capsule + 1-pt `stroke` `strokeBorder`). Otherwise the amber capsule
(`PrimaryButtonStyle2`: `onAccent` ink, `minHeight 48`, `accent` capsule + a top-lit 1-pt
`controlSheen`→clear gradient border, disabled opacity 0.38). Both are `fixedSize(horizontal: !isAX)`
— **hugging, never a full-width banner** — but expand to full width at AX sizes.

---

## 6. The results (`!query.isEmpty`)

```
searchBody(results, trending:) =
  SkeletonGate(isLoading: searchBusy && results.isEmpty && !scopedOut(results) && !searchError) {
      searchSkeleton
  } content: {
      resultsContent(results, trending:)
  }
  .frame(maxWidth: .infinity, alignment: .leading)
```

### 6.1 The skeleton and its gate

`SkeletonGate` owns the whole loading rule and no screen re-implements it:

- **Nothing for the first 240 ms** — a fast response never flashes structure. The gate renders
  `Color.clear.frame(height: 0)` during this window.
- Once shown, the skeleton stays a **minimum of 320 ms** even if data lands at 250 ms.
- After **800 ms** of continuous loading an internal `slow` flag flips (fades on `uiGentle`) —
  currently unused by this screen's skeleton, but the timing is part of the gate's contract.
- The swap to content is a **120 ms** crossfade (`uiCrossfade` = `uiReduced` = `easeOut(0.12)`).
- The frame never blanks between them.
- Breath: the skeleton oscillates opacity **0.88 ↔ 1.0** on `easeInOut(1.4s).repeatForever(autoreverses)`;
  under Reduce Motion it is a **static 0.92**. *"A 35 % oscillation across the WHOLE screen, forever, is
  not a reassurance that something is working — it is a pulse the eye cannot ignore."* **Shimmer is
  refused by name** (board 12) — a travelling highlight is decoration pretending to be progress.
- Timing uses `ContinuousClock`, not wall-clock: a system clock adjustment mid-window could compute a
  negative remainder.
- The skeleton is `accessibilityElement(children: .ignore)` + label **"Loading"**.

`searchSkeleton`: **5** `SkeletonRow`s in a `VStack(spacing: 0)`, `.padding(.horizontal, 16)`,
`.padding(.top, 12)`. Each row: a 60×90 block at radius **10** (`PosterSize.row.radius`, not the
default 6), `spacing: 14` (`artGap`), `height: 100` (`rowMedia`, `@ScaledMetric relativeTo: .body`), and
two lines of widths **188** and **126** at heights 13 and 10, stacked with spacing 8.
*"The shape the results are about to take: rows at exactly the `.row` geometry the content uses, so
nothing reflows when the data lands."* All blocks are `skeleton` (`#F4F1EC` @ 0.11).

**The gate's condition excludes three cases** that must not show a skeleton: a scoped-out set (the data
is already here), an error (there is a state for that), and a non-empty result set being refined (that
is the group-dim, §6.5).

### 6.2 `resultsContent` — the three-way branch

```
if scopedOut(results)      → stateWithTrending { EmptyState(scopedOutCopy, primary: showAll) }
else if results.isEmpty    → stateWithTrending { VStack(spacing: 16) { notices(inset: false); EmptyState(…) } }
else                       → the list
```

`scopedOut(results)` ≡ `mediaFilter != .all && results.isEmpty && !searchResults.isEmpty`
— *"The scope, not the query, emptied the list."*

`stateWithTrending(trending) { state }`:

```
VStack(alignment: .leading, spacing: 0) {
    state().padding(.horizontal, 16).padding(.top, 30 /* sectionGap */)
    if !trending.isEmpty { trendingGrid(trending).padding(.top, 30) }
    else                 { Spacer(minLength: 0) }
}
.frame(maxWidth: .infinity, alignment: .leading)
```

> *"A whole-surface state, followed by the artwork this screen already has. The app used to throw away a
> decoded shelf in order to say one sentence, leaving a plate over 900 pt of black — on the screen a
> reviewer walks first."*

Note that inside `stateWithTrending` the `EmptyState` is **top-anchored at `sectionGap`**, not
`centredState`-centred: it has the grid under it, so there is nothing to centre in.

### 6.3 Empty / error copy

| Condition | Copy struct | Title | Supporting | Symbol | Button |
|---|---|---|---|---|---|
| `scopedOut` | `noScopeMatches(scope:query:)` | **"Nothing in Anime for “one piece”"** (curly quotes U+201C/U+201D) | "Switch the scope to All to see every result." | `magnifyingglass` | **"Show all"** → `withAnimation(pick(uiSnappy)) { mediaFilter = .all }` (amber) |
| `results.isEmpty && searchError && isOnline` | `searchUnavailable` | **"Couldn’t search right now"** | "Something went wrong. Try again in a moment." | `exclamationmark.circle` | **"Try again"** → `retrySearch()` (quiet) |
| `results.isEmpty && searchError && !isOnline` | `searchFailed` | **"Couldn’t search right now"** | "Check your connection and try again." | `wifi.exclamationmark` | **"Try again"** → `retrySearch()` (quiet) |
| `results.isEmpty && !searchError` | `noSearchResults(query:)` | **"No results for “one pece”"** | "Check the spelling or try another title." | `magnifyingglass` | **none** |

> *"`searchFailed` carries the wifi glyph and 'check your connection', so it is the OFFLINE copy;
> online, the catalogue itself failed. Both name SEARCH — the online branch used the library's own
> error, on a screen that has nothing to do with the library."*

Both error titles are deliberately the **same words**: one failure has one name. The reachability source
is `SyncCenter.shared.isOnline` (an `NWPathMonitor` on `path.status == .satisfied`), never inferred
from the error. Apostrophes are **U+2019**, quotes **U+201C/U+201D**, throughout.

State copy says **"Couldn't load your library" / "You're offline" / "Something went wrong"**, never
"server".

### 6.4 The catalogue notices

```swift
private static let failedMarker = "failed"   // a WIRE marker, not copy

private var catalogueNotices: [String] {
    guard let sources = appModel.searchSources else { return [] }
    var out: [String] = []
    if sources["anilist"] == "failed", appModel.matchesMediaFilter(.anilist) { out.append(Copy.Notice.searchAnime) }
    if sources["tmdb"]    == "failed", appModel.matchesMediaFilter(.tmdb)    { out.append(Copy.Notice.searchTV) }
    return out
}
```

- `Copy.Notice.searchAnime` = **"Anime results couldn’t refresh"**
- `Copy.Notice.searchTV` = **"TV results couldn’t refresh"**
- `Copy.Search.couldNotRefresh` = **"Results couldn’t refresh"** (the whole-request failure over a stale
  result set — *"the 'both sources, one request' case `Copy.Notice`'s per-catalogue lines do not name"*)

> *"`/search` names the outcome per source (`ok` / `failed` / `disabled`); a catalogue that failed is not
> a catalogue with no matches, so the rows that did arrive get a notice above them rather than standing
> in for the whole answer. Filtered by scope: an anime notice over a TV-only list names a failure the
> user cannot see."*

An absent `sources` is **"nothing to report"**, never a failure. `"disabled"` (TMDB token unset,
anime-only mode) produces **no** notice.

`notices(refreshFailed:inset:)`:

```
messages = (refreshFailed ? ["Results couldn’t refresh"] : []) + catalogueNotices
if !messages.isEmpty {
    VStack(spacing: 8) { ForEach(messages) { InlineNotice($0) { retrySearch() } } }
        .padding(.horizontal, inset ? 16 : 0)
        .padding(.top,        inset ? 16 : 0)
}
```

`inset: true` over a populated list (the list already has its own gutter applied separately);
`inset: false` inside `stateWithTrending`, which already padded horizontally.

`InlineNotice` anatomy — **a footnote line, never an alert box**:
`HStack(firstTextBaseline, spacing: 6)`: SF Symbol `wifi.exclamationmark` at `.system(size: 12,
weight: .semibold)` in `textTertiary`, then the message in `metadata`/`textSecondary` with
`fixedSize(vertical:)`; then, spaced 8 pt, a **"Retry"** `InlineLinkButtonStyle` button pulled back
`-12` vertically and `-4` leading so it sits on the line's baseline. `frame(maxWidth: .infinity,
minHeight: 28, alignment: .leading)`, `.transition(.opacity)`. The glyph+text pair is one combined
a11y element labelled with the message; Retry carries hint **"Tries the request again"**.
At AX sizes the `HStack` becomes a `VStack(alignment: .leading, spacing: 4)` and the Retry link's
leading pull-back becomes `-12`.

### 6.5 The populated list

```
VStack(alignment: .leading, spacing: 0) {
    notices(refreshFailed: searchError, inset: true)
    if let correction = searchCorrection { correctionLine(correction) }
    VStack(spacing: 0) {
        ForEach(results.items) { i, item in
            mediaRow(item, zoom: "result/\(item.id)",
                     ambiguous: results.ambiguous, separator: i < results.count - 1)
        }
    }
    .padding(.horizontal, 16)
    .padding(.top, 12 /* x3 */)
}
.opacity(searchBusy ? 0.72 : 1)
.animation(pick(uiGentle), value: searchBusy)
.animation(pick(uiSnappy), value: results.items.map(\.id))
```

**Rows only — no headers, no top-match card, `.row` slot everywhere:**

> *"Rows, all of them, no headers and no card: Apple TV's answer to a query is the list of what matched.
> 'Top match' (a plate, then an art tile) over 'More results 3' was two anatomies and a count for one
> list."*

**The group dim, 0.72:** *"Refining a query that already has results: the old set steps back as a group
while the new one is in flight, so a list that is about to change never looks settled."*
0.72 is the app-wide group-dim value — `textSecondary` at 0.72 composites to ≈5.4:1 and still reads as
content that has stepped back (0.45 measured ≈2.64:1 and was unreadable).

The second `.animation` keyed on `results.items.map(\.id)` animates **every new result set**, not just
the first — *"this is the modifier the container-level one was standing in for."*

**No trending grid under a populated list** — the chart appears only in the empty / scoped-out branches.

### 6.6 The correction line

```
VStack(alignment: .leading, spacing: 0) {
    Text("Showing results for “\(corrected)”").type(metadata).foregroundStyle(textSecondary)
        .fixedSize(horizontal: false, vertical: true)
    Button("Search instead for “\(original)”") { appModel.searchLiterally(original) }
        .buttonStyle(InlineLinkButtonStyle())
        .padding(.leading, -12 /* Metrics.inlineLinkInset */)
}
.padding(.horizontal, 16)
.padding(.top, 30 /* sectionGap */)
.accessibilityElement(children: .contain)
```

- Quotes are curly (U+201C / U+201D).
- The link's `-12` leading pull-back exists because `InlineLinkButtonStyle` pads 12 pt leading to hold
  its 44-pt target; the pull-back puts the **word** on the gutter.
- It is drawn **only over a populated list** — a zero-result correction never reaches the screen,
  because the server only returns `correctedQuery` when the rewrite actually found something.

> *"The standard 'we searched for something else' disclosure, with the literal search one tap away.
> `correctedQuery` has been on the wire and decoded since the endpoint shipped"* — and was read by
> nothing until this pass. A search for "one pieceszz" showed a flat "No results" while the backend had
> already worked out what was meant.

`SearchCorrection` is `nil` unless **both** `correctedQuery` and `originalQuery` are present **and**
they differ under `caseInsensitiveCompare` — *"'showing results for X' that echoes X back is noise."*

---

## 7. The notification primer

**The system permission alert is never raised by an add.** This is the single most heavily documented
decision in the file, and the port must reproduce it exactly:

> *"`addToLibrary` used to set the undo state and then immediately raise the notification prompt, so the
> app's first-ever permission ask arrived unprimed, in the middle of an unrelated action, over the
> trending grid — with 'Added … — Undo' counting down *underneath* a modal the user could not dismiss
> without answering. The Undo was unreachable for its whole six seconds and had expired by the time they
> got back to it, VoiceOver focus was stolen, and the reflex answer to an unexplained ask is Don't Allow
> — after which iOS never asks again and episode alerts are dead for that account permanently."*

### 7.1 The arming sequence

```swift
private func armNotificationPrimer(_ item: FranchiseSummary) {
    guard item.isReleasing, item.source == .anilist, !primerAnswered else { return }
    Task {
        try? await Task.sleep(for: SyncCenter.shared.toastSeconds + 0.5)   // 6.5 s, or 10.5 s under VoiceOver
        guard appModel.isInLibrary(item.id) else { return }                // the add must have STUCK
        primerPending = true
        await refreshNotificationEligibility()
    }
}
```

- Gated to a **currently-airing AniList show**: *"TMDB air times are synthesised, so a TV-only add buys
  the user nothing and asks for nothing."*
- Gated on `!primerAnswered` — one shot per install, ever.
- The delay is the full undo window **plus 0.5 s**, and the add must still be in the library when it
  elapses (an undone add arms nothing).

### 7.2 Eligibility

```swift
private func refreshNotificationEligibility() async {
    guard primerPending, !primerAnswered else { if primerVisible { primerVisible = false }; return }
    let settings = await UNUserNotificationCenter.current().notificationSettings()
    canAskForNotifications = settings.authorizationStatus == .notDetermined
    guard canAskForNotifications != primerVisible else { return }
    withAnimation(pick(uiSettle)) { primerVisible = canAskForNotifications }
}
```

Only `.notDetermined` can still be asked — *"anything else and the primer would be a card that promises
a system alert iOS will never show."* The notification-centre round trip happens **only while there is a
primer to show**: *"It used to run on every library change for every user, forever — including the ones
who answered the primer on day one."*

Called from three places: `.task { }` (once on appear), `.task(id: appModel.library.count)` (on any
library-size change), and after `answerPrimer`.

### 7.3 The primer row

Mounted as the **first child of the scroll content**, above the launchpad/results slot.
*"A row on the canvas, in the app's own row grammar: a glyph, a title, one line, and the answer as a
link. It was a plate with a bell in a tile, a paragraph and a full-width amber capsule — a promo card
from a marketing site, on a search screen."*

```
layout {                                   // HStack(center, spacing: 14) — VStack(leading, spacing: 8) at AX
    HStack(center, spacing: 14) {
        Image(systemName: "bell.badge").font(.system(size: 20, weight: .regular))
            .foregroundStyle(textTertiary).frame(width: 28)
        VStack(alignment: .leading, spacing: 3) {
            Text("Episode alerts").type(rowTitle).foregroundStyle(textPrimary).fixedSize(vertical:)
            Text("Know the moment a new episode airs.").type(rowMeta).foregroundStyle(textSecondary).fixedSize(vertical:)
        }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    HStack(spacing: 8) {
        Button("Turn on") { answerPrimer(turnOn: true) }
            .buttonStyle(InlineLinkButtonStyle())
            .padding(.vertical, -12).padding(.leading, isAX ? -12 : 0)
        primerDismiss
    }
}
.padding(.vertical, 8)
.frame(minHeight: 56 /* rowCompact */)
.overlay(alignment: .bottom) { Rectangle().fill(separatorQuiet).frame(height: 1) }
.padding(.horizontal, 16)
.padding(.top, 8)
.accessibilityElement(children: .contain)
```

- **At AX sizes the layout flips to a `VStack`** so the words take the full width and the answers drop
  to their own line: *"beside two controls the sentence was wrapping one word per line."*
- `primerDismiss`: SF Symbol `xmark` at `.caption2` weight **bold**, `textTertiary`, in a **28-pt**
  circle (`Metrics.dismissDisc`) filled `surfaceRaised` with a 1-pt `posterEdge` `strokeBorder`,
  centred inside a **44-pt** target with `contentShape(Circle())`, then `.padding(4)`.
  VoiceOver label: **"Not now"** — *"'Not now', not 'No thanks': iOS raises its own alert once ever, so
  the honest offer is a deferral."*
- `Metrics.primerGlyphTile = 36` is declared and **unused** (a vestige of the earlier tile treatment).

### 7.4 Answering

```swift
private func answerPrimer(turnOn: Bool) {
    primerAnswered = true
    primerPending  = false
    withAnimation(pick(uiSettle)) { primerVisible = false }
    guard turnOn else { return }
    Task {
        let granted = await EpisodeNotifications.shared.requestPermissionIfNeeded()   // options: [.alert, .sound]
        if granted {
            FeedbackCoordinator.fire(.success)
            appModel.showNotice("Episode alerts on")      // a neutral receipt, 2.5 s, no action
            await appModel.alertsWereAllowed()            // arms alerts + the Live Activity from the loaded library
        }
        await refreshNotificationEligibility()
    }
}
```

> *"The card used to vanish whether the user allowed or declined, with no receipt either way. Allowed is
> a success (one haptic, one line); declined is the system's own answer and needs no second one."*

Both answers set `primerAnswered = true` permanently; **Profile → Notifications is the only route back.**

**Android:** the substance ports directly and is *more* necessary, since `POST_NOTIFICATIONS` (API 33+)
is also one-shot-ish (two denials permanently block the dialog). `primerPending`/`primerAnswered` →
`DataStore<Preferences>` booleans. `notificationSettings().authorizationStatus == .notDetermined` →
`ContextCompat.checkSelfPermission(...) != GRANTED && !shouldShowRequestPermissionRationale(...)` on a
first run; track "asked once" yourself in DataStore because Android gives no `notDetermined` state
directly. **Moderate** — the state machine differs, the UX rule does not.

---

## 8. Copy derivations

Every user-facing string lives in `Copy` (`Copy+Search.swift`); `DiscoverView` and `SearchComponents`
carry **no literals**. The one exception is `failedMarker = "failed"`, which is a **wire** value.

### 8.1 `when(item)` — the amber forward-looking fact

```swift
private func when(_ item: FranchiseSummary) -> String? {
    guard item.isReleasing else { return nil }
    guard let at = item.nextAiringAt, at > now else { return "Airing now" }
    let word  = TemporalCopy.airsCompact(at: at, now: now, source: item.source)
    let cased = (word == "Today" || word == "Tomorrow") ? word.lowercased() : word
    return "New episode \(cased)"
}
```

- `now` here is `appModel.nowMinute`.
- **"Airing now"** when the show is releasing but there is no future air instant.
- Otherwise **"New episode today"**, **"New episode tomorrow"**, **"New episode Friday"**,
  **"New episode Aug 28"**, **"New episode Aug 28, 2027"**.
- Casing: *"'today' and 'tomorrow' are common nouns mid-sentence; a weekday and a month are not."*

`TemporalCopy.airsCompact` **drops the clock and never the day word**, using the exact same day ladder
as the long `airs` form so the two grammars cannot drift:

| `dayDiff` | Result |
|---|---|
| 0 | "Today" |
| 1 | "Tomorrow" |
| 2…6 | full weekday name ("Friday") |
| else | `dateWord` — "Aug 28" in the current year, otherwise the locale-ordered full date ("Aug 28, 2027" / "28 Aug 2027") |

`dayDiff` is computed against the item's **time anchor**: `.local` for AniList (true instants),
**`.utcDate` for TMDB** (date-only facts the server carries as a synthesised 17:00 UTC instant — reading
them locally put every timezone east of UTC+7 a day ahead). The year is never string-joined: a
hand-assembled `"\(md), \(y)"` produced **"31 Mar, 2013"** on day-first devices.

The rationale for the whole treatment:

> *"The shipped row printed a bare '29 Aug 2:00 PM' as its fourth fact, in the same grey as the year and
> the season count — a date-time with nothing saying whether it was a premiere, the next episode or the
> finale, set as though it were trivia. It is the one forward-looking fact on the screen, so it is
> named, it leads the line, and it is the one thing on it in amber."*

### 8.2 `size(item)` — the season count, only where it is true

```swift
private func size(_ item: FranchiseSummary) -> String? {
    guard item.partCount > 0, item.source == .tmdb else { return nil }
    return Copy.Search.seasons(item.partCount)      // "1 season" / "23 seasons", NBSP-bound
}
```

**AniList prints no count at all.** The reasoning is worth quoting in full because it is a data-honesty
rule, not a layout one:

> *"'Part' is `FranchisePart`, an internal model word nobody outside this repository can interpret. But
> its replacement asserted something the app disproves two taps later: Search said One Piece had '45
> seasons', and One Piece's own screen prints 'SEASONS & MOVIES 23' … Renaming the number does not fix
> it — 41 is not 23 under any label. This is the figure a user checks before adding a 45-'season' show,
> and a tracker that gets it wrong on the add screen is not one you trust with your progress."*

TMDB keeps its count because there one member genuinely is one season. **Server follow-up recorded in
the source:** once `partCounts` reaches `FranchiseListItem`, this becomes "5 seasons · 6 extras".

`Copy.plural(n, one, many)` = `"\(n)\u{00A0}\(n == 1 ? one : many)"` — the number is bound to its noun
with a **non-breaking space**, so a numeral never ends a line its unit does not start.

### 8.3 `rowFacts(item, ambiguous:)` — the grey facts, in priority order

```swift
var facts: [String] = []
if let f = appModel.franchise(id: item.id) { facts.append(Copy.Status(f.effectiveStatus)) }
facts.append(item.source.kindWord)
if let y = item.year, when(item) == nil, !titleCarriesYear(item, ambiguous:) { facts.append(String(y)) }
if let s = size(item) { facts.append(s) }
```

Three documented rules:

1. **An owned show leads with its shelf.** *"The tick alone said 'in your library' and never which of
   five lists it was on; the status word is the fact that answers that, in the same vocabulary Library's
   own rows use."* → "Watching" / "Planned" / "Watched" / "Paused" / "Dropped" (`Copy.statusLabel`;
   "Completed" and "Plan to watch" never appear).
2. **Kind next.** `kindWord` = `"TV"` for TMDB, `"Anime"` for AniList. *"A search for 'one piece'
   returns the 1999 anime, the 2023 live-action and the 2027 anime, separated by capitalisation and a
   year … Adding the wrong one puts the wrong show in the library, and there is no other moment where
   the kind matters more."*
3. **The year goes when a next-episode date is present** (and when the title already carries it).
   *"They are the same class of fact and the line only holds so much: for a show airing tomorrow, '1999'
   is the least useful thing on it, and keeping both is what pushed the row to four facts and a wrap."*

Joined with `FactLine.separator` = `" · "` (U+00B7 with a plain space either side) — the **one**
separator every joined fact line on this screen uses, so a row and a card never punctuate differently.

### 8.4 `shelfFacts(item)` — the recents-row caption

Identical schema **minus** the two `when`-dependent suppressions: status (if owned), kind, year (always),
size. *"The shelf caption carries the SAME schema as a row — shelf, then kind. It carries no lead, so it
keeps the year."*

Used by the **recents rows** (`meta:`). Note it is **not** used by the trending grid cards, which use
the two-fact kind + year caption (§5.4).

### 8.5 Disambiguation — `ResultSet`, `titleCarriesYear`, `disambiguated`

```swift
private struct ResultSet {
    let items: [FranchiseSummary]
    let ambiguous: Set<String>          // normalised titles that more than one item shares

    static func normalised(_ title: String) -> String {
        title.lowercased()
             .replacingOccurrences(of: "^the\\s+", with: "", options: .regularExpression)
             .components(separatedBy: CharacterSet.alphanumerics.inverted)
             .joined()
    }
}
```

Built **once per body** — *"The scan is a regex over every title; at eight reads of `results` and one
scan per row it was running dozens of times per keystroke."*

- `titleCarriesYear(item, ambiguous:)` ≡ `item.year != nil && ambiguous.contains(normalised(item.title))`
- `disambiguated(item, ambiguous:)` → `"\(title) (\(year))"` when it does, else the source title verbatim

> *"A search for 'one piece' returns five results whose titles differ only in capitalisation and a
> definite article, separated by a 13-pt grey line — so 'One Piece (Anime · 1999)' and 'ONE PIECE
> (TV · 2023)' read as the same show, and one of them is the wrong one to put in the library. Where the
> ambiguity is real the disambiguator is promoted into the identity line; where it is not, the source
> title is left exactly as the catalogue spells it, because in search the user is matching against what
> they typed."*

The grid cards and recents rows pass `ambiguous: []` (a chart and a history list are not a
disambiguation context) — only result rows disambiguate.

### 8.6 `String.shelfShortened` (grid card titles only)

1. Trim whitespace.
2. If the string ends in `-` and contains `" -"`, drop from that `" -"` onward (a trailing `-…-`
   subtitle wrapper: "Re:ZERO -Starting Life in Another World-" → "Re:ZERO").
3. Trim any leading/trailing characters in `" -–—:"`.
4. If still longer than **40** characters, cut at the first of `": "`, `" – "`, `" — "`, `" - "`, `" ("`
   that appears at index ≥ **12**, and keep the head.

*"A line that opens on a hyphen reads as a hyphenation bug, not as a title."* `MediaRow` never applies
this — **rows print the title whole.** VoiceOver on a `ShelfCard` speaks the **whole** title, never the
shortened one.

### 8.7 `spoken(item, rank:, ambiguous:)`

`[rank.map { "\($0). \(title)" } ?? title] + [when(item)] + rowFacts(...)`, joined with `", "`.
*"The spoken form of a result: rank (when it has one), the WHOLE title, the lead, the facts."*
`rank` is never passed by any live call site.

### 8.8 The full string table

| Constant | Verbatim value |
|---|---|
| `Copy.Search.title` | `Search` |
| `promptAll` / `promptAnime` / `promptTV` | `Search anime and TV` / `Search anime` / `Search TV` |
| `Copy.Filter.all/anime/tv` | `All` / `Anime` / `TV` |
| `recentlySearched` | `Recently searched` |
| `termKind` | `Search` |
| `termHint` | `Searches for it again` |
| `trendingNow` | `Trending now` |
| `removeRecent` | `Remove` |
| `Copy.Action.clear` | `Clear` |
| `results(n)` | `1 result` / `12 results` (NBSP after the numeral) |
| `seasons(n)` | `1 season` / `23 seasons` (NBSP) |
| `showingResultsFor(x)` | `Showing results for “x”` |
| `searchInsteadFor(x)` | `Search instead for “x”` |
| `couldNotRefresh` | `Results couldn’t refresh` |
| `Copy.Notice.searchAnime` / `searchTV` | `Anime results couldn’t refresh` / `TV results couldn’t refresh` |
| `airingNow` | `Airing now` |
| `newEpisode(day:)` | `New episode {day}` |
| `inLibrary` / `notInLibrary` | `In library` / `Not in library` |
| `addHint` | `Adds it to your library` |
| `ownedHint` | `Change its status or remove it` |
| `addToLibrary` | `Add to Library` |
| `showAll` | `Show all` |
| `primerTitle` / `primerBody` | `Episode alerts` / `Know the moment a new episode airs.` |
| `primerTurnOn` / `primerNotNow` | `Turn on` / `Not now` |
| `Copy.Toast.alertsOn` | `Episode alerts on` |
| `Copy.Toast.removed` | `Removed from Library. Watch history kept.` |
| `Copy.Toast.added(title:status:)` | `Added {title} to {status}` |
| `Copy.Action.removeFromLibrary` | `Remove from Library` |
| `Copy.Accessibility.opensTheShowHint` | `Opens the show` |
| `Copy.Accessibility.removeFilter(x)` | `{x}. Remove filter` |
| `Copy.Accessibility.retryHint` | `Tries the request again` |
| `Copy.Accessibility.loading` | `Loading` |
| `Copy.Action.retry` / `tryAgain` | `Retry` / `Try again` |

Declared and **never rendered** on the current screen: `Copy.Search.recent` (`Recent`),
`moreTrending` (`More trending`), `topMatch` (`Top match`), `moreResults` (`More results`),
`rank(n)` (`%02d`).

---

## 9. Components

### 9.1 `mediaRow(item, zoom:, ambiguous:, separator:)` — the ONE row anatomy

Used by both lists on this screen (results, and the trending chart at AX sizes).

```swift
MediaRow(title: disambiguated(item, ambiguous:),
         meta:  rowFacts(item, ambiguous:).joined(separator: " · "),
         lead:  when(item),
         poster: item.portraitArt,
         slot:  .row,
         chevron: false,          // ← the trailing column holds a control
         separator: separator,
         hint:  "Opens the show",
         zoomID: zoom,
         trailing: { addControl(item) })       { open(item, zoom: zoom) }
.franchiseQuickActions(appModel.franchise(id: item.id), appModel: appModel)
```

`MediaRow` geometry:

| Element | Spec |
|---|---|
| Container | `Button` → `RowPressStyle()` (radius 16: `surfacePressed × 0.6` overlay, scale 0.992, `uiPress` in / `uiMicro` out) |
| Row | `HStack(spacing: 14)`, `.padding(.vertical, 8)`, `.frame(minHeight: 100, alignment: .leading)`, `.contentShape(Rectangle())` |
| Poster | `PosterSlot(url:, .row)` = 60×90, radius 10, no shadow, `zoomSource(zoomID)` |
| Text column | `VStack(alignment: .leading, spacing: 3)`: title (`rowTitle`/`textPrimary`, `lineLimit(2)` — **unbounded at AX**, `fixedSize(vertical:)`), then `lead` in `rowMetaLead`/**`accent`**, then `meta` in `rowMeta`/`textSecondary`. **Lead above meta**, always. |
| Spacer | `Spacer(minLength: 12)` |
| Trailing | the `AddControl` (44×44) |
| Chevron | **absent** here (`chevron: false`) |
| Separator | when true: 1-pt `separatorQuiet`, `.padding(.leading, 60 + 14 = 74)` |
| Dim | `.opacity(dimmed ? 0.72 : 1)` — never set on this screen |

**Accessibility:** `.accessibilityElement(children: .combine)` with an explicit
`.accessibilityLabel([title, lead, meta].compactMap{}.joined(", "))` — spelled out *"so the trailing
chevron is never spoken"* — plus `.accessibilityHint(hint)`. **Consequence to reproduce or consciously
diverge from:** because `MediaRow` combines its children, a result row and its add control are **one**
VoiceOver element; the `AddControl`'s own label/value/hint (declared in `SearchComponents`) are subsumed.
The grid card does *not* have this property (`children: .contain`). If the Android port wants the add
control separately reachable in the list, use a custom accessibility action or a container semantics
node — but note that the iOS build ships the combined behaviour.

> *"The one row anatomy for both lists on this screen: the app's `MediaRow`, no chevron (the trailing
> column holds a control), the amber `when` as its lead so VoiceOver hears it inside the row's combined
> label, and the add control in the trailing slot."*

### 9.2 `AddControl` — the primary action of the whole screen

The component's own header states the defect it replaced:

> *"It measured ~25 pt over artwork (below the 44-pt minimum), 55×43 as a bordered `Add` in a row (1 pt
> under it), and **vanished entirely** in the added state, replaced by a bare grey checkmark with no
> chrome, no target and no way to undo — so the trailing column's edge was ragged down the list and the
> most important control on the screen was its quietest object. One component, two states, one 44-pt
> frame, one visual width, in both states, on every surface."*

**The placement rule, written down:** a control that sits **ON artwork** is a 26-pt disc inset into the
poster's corner; a control that sits in a **row or card's trailing column** is a 44-pt rounded square.
*"Those are the only two, they are chosen by what is underneath the control, and neither one ever
appears in the other's context — including at accessibility sizes, where the shipped build grew the
card's square into a full-width capsule and so drew one verb three ways."*

#### The control is one `Menu` in both states

```swift
private var control: Menu<AddGlyph, AddMenuContent<OwnedMenu>> {
    owned ? Menu(content:label:)                    // tap OPENS the menu
          : Menu(content:label:primaryAction: add)  // tap ADDS; long-press shows the menu
}
```

*"ONE `Menu` in both states — a ternary over one concrete type, not a `ViewBuilder` branch, so the
control keeps its identity when `owned` flips and the glyph's symbol replacement animates instead of the
whole button being torn down and rebuilt around a new one."*

`.menuStyle(.button)`.

**Owned does not remove on tap:** *"A tick that unsubscribed on contact was the only destructive one-tap
in the app, 44 pt from the add it replaced — and it never said which shelf the show was on."*

Menu contents:
- **Unowned**: one item, `Label("Add to Library", systemImage: "plus")` → `add()` — *"the long-press
  shows the one verb it performs, so the two states are one control with one gesture grammar."*
- **Owned, franchise loaded** (`appModel.franchise(id:) != nil`): `FranchiseContextMenu` —
  - "Mark all N episodes as watched" (`text.append`) when the releasing part has `episodesBehind > 0`
  - the five statuses in `menuOrder` — **Watching** (`play.circle`), **Planned** (`clock`), **Watched**
    (`checkmark.circle`), **Paused** (`pause.circle`), **Dropped** (`xmark.circle`); the current one
    shows `checkmark` instead of its own glyph. Each → `appModel.setStatus(franchiseId:status:)`
    (fires `.selection`, presents "Moved to {status} · Undo").
  - `Divider()`
  - destructive **"Remove from Library"** (`trash`) → `removeWithUndo`
- **Owned, franchise NOT loaded** (a pending add): one destructive item **"Remove from Library"** which
  hand-builds the receipt:
  ```swift
  appModel.removeFromLibrary(franchiseId: item.id)
  appModel.presentUndo(UndoState(mediaId: nil, franchiseId: item.id, prevProgress: 0,
                                 title: item.title, episode: 0,
                                 customMessage: "Removed from Library. Watch history kept.") {
      appModel.addToLibrary(franchiseId: item.id, title: item.title, isReleasing: item.isReleasing)
  })
  ```
  > *"The one remove in the app with no way back: a show added seconds ago and not yet in the loaded
  > library has no `Franchise` for `removeWithUndo`, so the receipt is built here — same toast, same six
  > seconds, same Undo."*

#### `AddGlyph`

`Image(systemName: owned ? "checkmark" : "plus")`, at **`.caption` (12) over art** and **`.subheadline`
(15) in a row**, weight **bold** — text styles, not point sizes, *"so the glyph tracks Dynamic Type with
the row it sits in."* Foreground: `accent` when owned, `textPrimary` when not.
`.contentTransition(.symbolEffect(.replace.downUp))` animated on `pick(uiMicro)` keyed to `owned`.

> *"Added is drawn in `accent`; unadded in `textPrimary`. The two states were previously separated by the
> glyph's *colour alone* inside identical grey chrome, so 'in your library' and 'not in your library'
> both read as live grey buttons."*

#### `AddControlShape`

| Placement | Geometry |
|---|---|
| `.overArt` | glyph → `frame(26 × 26)` → `.background(scrimStrong, in: Circle())` → `.background(owned ? accentSoft : .clear, in: Circle())` → `.overlay(Circle().strokeBorder(owned ? accent.opacity(0.45) : posterEdge, lineWidth: 1))` → `frame(44 × 44)` → `contentShape(Circle())`. Button style: **`MarkPressStyle`** (compression only — no rounded-rect wash behind a circle). |
| `.row` | glyph → `frame(44 × 44)` → `contentShape(Rectangle())`. Button style: **`CompactSquareStyle(owned:)`** — background `owned ? accentSoft : .clear` (`surfacePressed` while pressed) in a `RoundedRectangle(cornerRadius: 12, style: .continuous)`, `strokeBorder(owned ? accent.opacity(0.35) : stroke, lineWidth: 1)`, opacity 0.72 when pressed **under Reduce Motion**, `scaleEffect(0.985)` when pressed otherwise, on `pick(uiPress)`. |

The disc is **scrim-filled in both states** *"so the reading never depends on what the poster happens to
be doing behind it — measured 7.0:1 / 16.6:1 / 14.8:1 against the brightest posters in the chart. The
added state warms the fill so the two states differ in more than the glyph's colour."* The ring alphas
differ by placement (0.45 over art vs 0.35 on a surface) because *"on a surface the `accentSoft` fill
already carries the state."*

**Unadded is a stroke, not a fill:** *"Four identical filled grey tiles running down the right edge of
the one screen whose job is showing artwork made the trailing column the heaviest thing in every row.
The fill is now what *ownership* looks like."* Square, not a text capsule, because *"'Add' and '✓' are
different widths, and a trailing column that changes width between rows is why the list's right edge
was ragged."*

**Accessibility (on the `AddControl` itself):**
`label = item.title`, `value = owned ? "In library" : "Not in library"`,
`hint = owned ? "Change its status or remove it" : "Adds it to your library"`.
*"Not `.isSelected`: the amber tick is ownership, not a selection state."*

**Android:** the disc/square split is straightforward. The `Menu` with `primaryAction` (tap = act,
long-press = menu) maps to a `Box` with `combinedClickable(onClick = add, onLongClick = { expanded = true })`
hosting a `DropdownMenu`; the owned state uses `onClick = { expanded = true }` and no long-press.
`.symbolEffect(.replace.downUp)` has no equivalent — use `AnimatedContent` with
`slideInVertically { it } + fadeIn() togetherWith slideOutVertically { -it } + fadeOut()`,
`animationSpec = spring(dampingRatio = 0.88f, stiffness = ...)` matching `uiMicro`. **Easy/Moderate.**

### 9.3 `FactLine` and `RankGutter` — present in the file, **not rendered**

Both live in `SearchComponents.swift` and neither reaches the screen in the shipped build:

- **`FactLine`** (the view) is constructed only inside `DiscoverView.cardMeta`, which has **no call
  sites**. Only its static `FactLine.separator` (`" · "`) is used, by five call sites.
- **`RankGutter`** has no call sites at all — *"the over-art numeral is gone"* and the ranks moved to the
  caption, and then off it.

Do **not** port them as components. They are specified here only so the port can recognise the dead
code and so the `ViewThatFits` idea is on record if a fact line is ever revived:

`FactLine` renders **one** joined line at every size, dropping whole facts to fit rather than printing a
fragment — *"drop a fact rather than print a fragment … `.truncationMode(.tail)` on a joined metadata
string is how '2026 ·' and '2018 · 11 parts · Friday…' reached the screen."* It ladders through
candidates `line(n) … line(3), line(2), line(1), line(0)`, each `fixedSize(horizontal: true)` so
`ViewThatFits` can reject it on ideal width, and a **final flexible floor** `line(0, fixed: false)
.minimumScaleFactor(0.75).truncationMode(.tail)` — because `ViewThatFits` renders its last candidate
whether or not it fits. `lead` is the one amber fact, printed first and never dropped.

`RankGutter` is a `%02d` numeral in `sectionLabel`/`textDisabled`, `monospacedDigit()`,
`minimumScaleFactor(0.7)`, in a `@ScaledMetric(relativeTo: .caption2)` lane of **24 pt**
(*"Held at 24 pt, the numeral rendered as a bare '…' at AX1"*), `accessibilityHidden(true)`.

### 9.4 Dead members of `DiscoverView`

`cardMeta(_:ambiguous:)` and `fittedTitle(_:budget:ambiguous:)` are both unreferenced (they belonged to
the retired "top match" card). `fittedTitle`'s rule is worth preserving as **doctrine** even though the
function is dead: *"an identity title never ends in an ellipsis and never breaks mid-word … the fallback
is the one the direction names: break at the colon and drop the subtitle."*
`Metrics.primerGlyphTile` (36) is likewise unused.

---

## 10. Accessibility

### 10.1 The spoken outcome (WCAG 4.1.3)

> *"A VoiceOver user typed a query and results arrived, or didn't, or failed, and nothing was spoken."*

```swift
.onChange(of: appModel.searchBusy) { _, busy in
    guard !busy, !query.isEmpty else { return }
    announceOutcome()
}
.onChange(of: appModel.mediaFilter) { _, _ in
    FeedbackCoordinator.fire(.selection)
    guard !query.isEmpty, !appModel.searchBusy else { return }
    announceOutcome()
}
```

`announceOutcome()` → `Announce.status(outcomeTitle(ResultSet(filteredSearchResults)))`, which posts an
`AccessibilityNotification.Announcement` **only while VoiceOver is running** and only for a non-empty
message (a *polite* announcement — it waits for VoiceOver to finish whatever it is saying).

```swift
private func outcomeTitle(_ results: ResultSet) -> String {
    if scopedOut(results) { return scopedOutCopy.title }          // "Nothing in Anime for “x”"
    if results.isEmpty {
        return searchError ? errorCopy.title                       // "Couldn’t search right now"
                           : noSearchResults(query:).title         // "No results for “x”"
    }
    var parts = [Copy.Search.results(results.count)]               // "12 results"
    if searchError { parts.append(Copy.Search.couldNotRefresh) }   // "Results couldn’t refresh"
    parts += catalogueNotices                                      // "TV results couldn’t refresh"
    return parts.joined(separator: ". ")
}
```

> *"Speaks the SAME title the visible state shows. It used to announce the anime catalogue's notice for
> a server error and the no-results title for a scoped-out set."*

### 10.2 Dynamic Type

| Surface | Response |
|---|---|
| Trending grid | **becomes `mediaRow`s** at any accessibility size (§5.4) |
| `MediaRow` title | `lineLimit(2)` normally; **unbounded** at AX |
| `ShelfCard` title | `lineLimit(1...2)` normally; `1...6` at AX; caption block goes `maxWidth: .infinity` |
| Primer | `HStack` → `VStack(leading, spacing: 8)`; "Turn on" gains a `-12` leading pull-back |
| `InlineNotice` | `HStack(firstTextBaseline)` → `VStack(leading, spacing: 4)`; Retry pull-back `-12` |
| `EmptyState` | title/supporting line limits unbounded; buttons expand to full width (`fixedSize(horizontal: !isAX)`) |
| Scope segments | `metadataEmphasis` is a **text style**, so the bar scales with everything else |
| Skeleton rows | height is `@ScaledMetric(relativeTo: .body)` so the swap does not jump at AX |
| `RankGutter` lane | `@ScaledMetric(relativeTo: .caption2)` (dead code) |

### 10.3 Reduce Motion

Every `withAnimation` and `.animation` on this screen goes through `ThemeMotion.pick(_:reduceMotion:)` →
`easeOut(0.12)`. `handoff` collapses to a symmetric opacity fade with no delay. Press styles switch from
`scaleEffect` to **opacity 0.72** (board 11: *"Reduce Motion presses in OPACITY, never in scale"*).
The skeleton breath becomes a static 0.92. `pageInTransition` drops its 6-pt travel.

### 10.4 Reduce Transparency

Only one consumer here: `ScrollEdgeChrome` drops the `.ultraThinMaterial` layer entirely and raises the
hardened bar's canvas from **0.74 to 1.0** — *"a 74 % veil with nothing softening what is under it is the
half-lit row under 'Library' that the hardened bar was built to end."*

### 10.5 Element-level labels

| Element | Label / value / hint |
|---|---|
| Grid card | label = `spoken(item, ambiguous: [])`; hint = "Opens the show"; container `children: .contain` so the add control stays reachable |
| Result row | label = `[title, lead, meta].joined(", ")`; hint = "Opens the show"; `children: .combine` |
| Add control | label = title; value = "In library" / "Not in library"; hint = "Change its status or remove it" / "Adds it to your library" |
| Term row | `children: .ignore`; label = "\(term), Search"; hint = "Searches for it again" |
| Scope chip | label = "Anime. Remove filter" |
| Primer | container `children: .contain`; dismiss button label "Not now" |
| Primer / correction line | `accessibilityElement(children: .contain)` |
| Section header | `.isHeader` trait on the title |
| Skeleton | `children: .ignore`, label "Loading" |
| Posters, chevrons, arrows, chrome veils | `accessibilityHidden(true)` |

---

## 11. The query pipeline

### 11.1 Client side — debounce, sequence, cancellation

`searchQuery.didSet` → `searchExactOnce = false` → `scheduleSearch()`:

```swift
let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
if trimmed == lastScheduledQuery, !trimmed.isEmpty, !searchExactOnce { return }   // ①
lastScheduledQuery = trimmed
searchTask?.cancel()

if trimmed.isEmpty {                                                              // ②
    searchBusy = false; searchError = false; searchResults = []
    searchCorrection = nil; searchSources = nil; searchTask = nil
    return
}

searchBusy = true; searchError = false                                            // ③
searchTask = Task {
    try? await Task.sleep(for: .milliseconds(300))                                // ④
    if Task.isCancelled { return }
    await runSearch(query: trimmed)
}
```

① **A whitespace-only edit is not a new query.** *"'naruto' → 'naruto ' … used to cancel the in-flight
request and re-issue the identical one 300 ms later."*
② **Cleared box** cancels everything and falls straight back to the launchpad — no busy, no error.
③ `searchBusy` flips **before** the debounce, so the skeleton gate begins counting from the keystroke.
④ **Debounce: 300 ms.**

`runSearch`:

```swift
let seq = nextSeq()                       // monotonic ticket
let exact = searchExactOnce
do {
    let response: SearchResponse = try await api.search(query: query, exact: exact)
    guard seq == searchSeq else { return }              // a newer keystroke superseded this request
    searchResults = response.franchises
    searchCorrection = SearchCorrection(response)
    searchSources = response.sources
    searchExactOnce = false; searchError = false; searchBusy = false
} catch {
    guard !isCancellation(error) else { return }        // cancelled by a newer keystroke — NOT a failure
    guard seq == searchSeq else { return }
    searchCorrection = nil; searchSources = nil
    searchError = true; searchBusy = false
}
```

- **The sequence token is the out-of-order guard**: a response only mutates state if it is still the
  latest. Note the token is claimed at *send* time and the guard compares it to the *current* counter —
  so a slow first response cannot clobber a fast second one.
- **A cancelled request is not a failure.** `isCancellation` matches `CancellationError`,
  `URLError.cancelled`, and `APIError.transport(URLError.cancelled)`.
- `teardown()` bumps `searchSeq`, invalidating every in-flight response.

`retrySearch()` — no debounce: cancels, sets busy, calls `runSearch` immediately. Guarded on a non-empty
trimmed query.

`searchLiterally(term)`:
```swift
if searchQuery != term { searchQuery = term }   // didSet CLEARS searchExactOnce and re-schedules
searchExactOnce = true                          // set AFTER, so the request below reads it
retrySearch()
```
The ordering comment is load-bearing — setting the flag first would have it wiped by the `didSet`.
`exact` adds `&exact=1`, which opts that one request out of the server's spell correction.

**URL encoding:** the query value is percent-encoded with a **strict** set —
`.urlQueryAllowed` minus `&=+?#`. *".urlQueryAllowed leaves `&`, `+`, and `=` unescaped, which corrupts
the q parameter (searching 'X & Y' truncated at the ampersand)."*

**Trending:** `loadTrendingIfNeeded()` runs at most once per session (`guard trending.isEmpty,
trendingTask == nil`), `GET /franchises/trending?limit=10`, **quiet on failure** — the task handle is
released either way, so the next cold visit retries. `refreshTrending()` (the pull) cancels the pending
task and replaces `trending` **only if the fetch succeeds and is non-empty** — a failed pull never
blanks a good chart.

### 11.2 Server side — local-first and bounded

The client's contract with `GET /search?q=&exact=1` (see `server/src/services/search.ts`; the whole
request is budgeted at **2 400 ms**). The client does not implement this, but the port must understand
what latencies and outcomes to expect:

| Budget | Value |
|---|---|
| `SEARCH_BUDGET_MS` | 2 400 |
| `SOURCE_TIMEOUT_MS` (per provider) | 1 050, `maxRetries: 0` |
| `CORRECTION_TIMEOUT_MS` (LLM) | 650 |
| `COLD_ENRICH_WAIT_MS` | 600 |
| `MIN_REMOTE_QUERY_LENGTH` | **3** |

1. **Empty `q`** → the trending list (the client never sends this; it short-circuits locally).
2. **Local first.** A Postgres GIN-indexed prefix `tsquery` over canonical franchise titles **and** every
   member's `titleEnglish`/`titleRomaji`, scored (exact 100/90, prefix 50/45, else `ts_rank_cd × 10`),
   tie-broken on popularity. *"One- and two-character typeahead never triggers network, LLM, or
   catalogue writes."* Any local hit returns immediately (`mode: 'local'`).
3. **Remote fan-out** only on a genuine local miss with `q.length >= 3`: AniList + TMDB `/search/tv` in
   parallel, one attempt each, 1 050 ms. A provider that throws sets `sources[x] = "failed"` and returns
   `[]` — **the request still succeeds**. TMDB hits that are Japanese animation are suppressed (AniList
   owns those).
4. **Correction** runs only when *both* providers positively returned nothing, at least one responded,
   `!exact`, and `q.length >= 4`. The corrected string is re-checked against Postgres first
   (`mode: 'corrected-local'`) before a second provider fan-out.
5. **Enrichment** for unknown hits is enqueued on a `BoundedTaskQueue(width 2, depth 24)` — at most 3
   AniList seeds and 2 TMDB seeds per request, using the **deterministic** relation grouper (no LLM on
   the interactive path). A completely cold query waits at most 600 ms for its first materialised
   franchise, then returns whatever landed; the rest warms in the background.
6. Anime and TV ids are **interleaved** in the response.

**Practical consequences for the UI:** a two-character query returns fast and possibly empty — and that
empty is legitimate, not an error; the same query typed a third character later can suddenly return
results; a repeat of a cold query a few seconds later often returns *more* results than the first
attempt (the queue warmed them). The screen is honest about all three because it never caches results
locally and re-renders whatever the latest sequence delivered.

---

## 12. Actions

### 12.1 `open(item, zoom:)`

```swift
if !query.isEmpty { appModel.recordRecentItem(item) }
onOpenDetail(item.id, zoom)
```

> *"The SHOW the user acted on is what 'Recently searched' remembers — the term only when it came from
> the field."*

Note the guard: opening a card from the **launchpad's** trending grid (empty query) does **not** record
a recent item. Only a show reached through a query does.

`recordRecentItem`: remove any existing entry with the same id, insert at 0, truncate to **10**, persist
as JSON at `UserDefaults["recentSearchItems"]`.

`recordRecentSearch` (from the keyboard's Search key only): trims, **requires ≥ 2 characters**, removes
any case-insensitive duplicate, inserts at 0, truncates to **10**, persists at
`UserDefaults["recentSearches"]`.

Zoom-id namespaces (registered, currently unconsumed): `"trend/{id}"`, `"recent/{id}"`, `"result/{id}"`.

### 12.2 `add(item)` — the optimistic path

```swift
private func add(_ item: FranchiseSummary) {
    appModel.addToLibrary(franchiseId: item.id, title: item.title, isReleasing: item.isReleasing)
    if !query.isEmpty { appModel.recordRecentItem(item) }
    armNotificationPrimer(item)          // NOT a permission prompt — see §7
}
```

`AppModel.addToLibrary`:

1. `guard !isInLibrary(franchiseId)` — a second tap is a no-op.
2. `FeedbackCoordinator.fire(.success)`.
3. `pendingAdds.insert(id)` — **the control flips to owned on the very next frame** (`isInLibrary`
   reads `libraryIds ∪ pendingAdds`), with the `plus`→`checkmark` symbol replacement on `uiMicro`.
4. `status = isReleasing ? .watching : .planned`.
5. `undo = UndoState(added: true, title:, statusLabel: Copy.Status(status))` → the toast reads
   **"Added {title} to Watching"** with an **Undo**, dismissed after `toastSeconds`
   (**6 s**, **10 s while VoiceOver runs** — *"an Undo the user cannot reach in time is not an Undo"*).
   *"`Copy.Status`, never a local spelling: this line used to say 'Plan to watch', a string the copy
   table explicitly bans, in the one toast every first-time user reads."*
6. `POST` the subscription **with the status the toast promised** — *"Letting the server re-derive it
   from `nil` meant the toast could name one shelf and the show land on another whenever the two
   `isReleasing` readings disagreed."* Then `await reload()`.
7. **On failure**: clear the undo if it is still this add's; `pendingAdds.remove(id)` (**membership rolls
   back** — the control returns to `plus`); record the failure on `SyncCenter` with command "Add", the
   title, a plain-language reason and a `WriteIntent.subscribe(...)` so a **relaunch can retry it**. It
   surfaces as the persistent `SyncBanner`, never a transient toast: *"It was the only write in the app
   that ended in a transient toast with no way back."*
8. On success, `pendingAdds.remove(id)` once the reload has landed.

**Membership and status writes roll back; a progress mark never does** — the app-wide write rule.
The toast host floats above the tab bar at `ThemeMetrics.toastClearance` (62) from the window's bottom
safe area, horizontally inset **22 pt** (the tab bar's own margin).

`removeFromLibrary` (from the owned menu when the franchise is not yet loaded): `.commitLight` haptic,
drop the id from `pendingAdds`, remove the row if present, forget any unconfirmed progress, `DELETE`,
and on failure re-insert the row at its old index and record it on `SyncCenter` with a retry.

---

## 13. The full state matrix

`Q` = trimmed query non-empty · `F` = `fieldPresented` · `S` = `mediaFilter != .all` ·
`T` = filtered trending non-empty · `R` = recents non-empty · `On` = `SyncCenter.isOnline`

| # | Condition | What is drawn, top to bottom |
|---|---|---|
| 1 | `!Q`, `!F`, `!S`, `T` | trending grid (`padding(.top, 8)`) |
| 2 | `!Q`, `!F`, `S`, `T` | scope chip · trending grid |
| 3 | `!Q`, `F`, `R`, `T` | [scope chip] · "Recently searched" + Clear + rows (`top 8`) · trending grid (`top 30`) |
| 4 | `!Q`, `F`, `!R`, `T` | [scope chip] · trending grid (`top 8`) |
| 5 | `!Q`, `!T`, `!On` | [scope chip] · [recents] · `EmptyState(.searchOffline)` centred, **"Try again"** |
| 6 | `!Q`, `!T`, `On`, `S`, chart non-empty unfiltered | [scope chip] · [recents] · `EmptyState(.noScopeTrending)` centred, **"Show all"** |
| 7 | `!Q`, `!T`, `On`, `!F` or `!R` | [scope chip] · `EmptyState(.searchLaunchpad)` centred, no button |
| 8 | `!Q`, `!T`, `On`, `F`, `R` | recents rows only — **no empty state at all** |
| 9 | `Q`, busy, no results, not scoped-out, no error | 5 skeleton rows (after 240 ms; min 320 ms) |
| 10 | `Q`, scoped out | `EmptyState(.noScopeMatches)` at `top 30` · trending grid at `top 30` |
| 11 | `Q`, empty, `searchError`, online | [notices] · `EmptyState(.searchUnavailable)`, **"Try again"** · trending grid |
| 12 | `Q`, empty, `searchError`, offline | [notices] · `EmptyState(.searchFailed)`, **"Try again"** · trending grid |
| 13 | `Q`, empty, no error | [notices] · `EmptyState(.noSearchResults)`, no button · trending grid |
| 14 | `Q`, results | [notices] · [correction line] · rows |
| 15 | `Q`, results, `searchError` (stale set) | "Results couldn’t refresh" + Retry above the rows |
| 16 | `Q`, results, `searchBusy` (refining) | the whole block at **opacity 0.72** |
| 17 | any of the above + `primerVisible` | the primer row above everything, with its bottom rule |

The primer is orthogonal — it can appear over any of rows 1–16.

---

## 14. Android reproduction risks

| Item | Difficulty | Notes |
|---|---|---|
| SF Symbols — `magnifyingglass`, `arrow.up.backward`, `bell.badge`, `xmark`, `plus`, `checkmark`, `wifi.slash`, `wifi.exclamationmark`, `exclamationmark.circle`, `line.3.horizontal.decrease`, `trash`, `photo`, `chevron.forward`, `text.append`, `play.circle`, `clock`, `checkmark.circle`, `pause.circle`, `xmark.circle` | **easy** | **ERRATUM (2026-09-04, PLAN §9.2): this glyph list is NOT normative.** `docs/android-port/spec/icon-mapping.md` is the only icon authority — including the family (**Rounded**), the axes (**opsz 24 / GRAD −25 / wght 500 or 400 / FILL**) and the vendoring form (**committed static `VectorDrawable` XML, never `material-icons-extended`, never an icon font, never the variable font at runtime**). The CamelCase names above are the bundled `androidx.compose.material.icons` Filled/Outlined set: wrong optical family, GRAD 0, no auto-mirroring unless spelled `AutoMirrored.*`, and several exist only in the banned `material-icons-extended`. Use `icon-mapping.md`. |
| `.searchable` + `.navigationBarDrawer(displayMode: .always)` | **moderate** | Compose has no drawer-placement search field. Build the field as a row inside the app-bar column; Compose M3's `SearchBar` expands full-screen and must **not** be used. |
| `.searchScopes(activation: .onTextEntry)` | **easy** | `AnimatedVisibility(visible = query.isNotEmpty())` around **the app's own chip row (`FilterChipStyle`), amber for the selected scope — NOT a `SingleChoiceSegmentedButtonRow`** (ERRATUM 2026-09-04, PLAN §3.4/§9.2: the M3 segmented row brings an outlined container, a `secondaryContainer` selected fill and a sliding leading check, i.e. a second chip anatomy on a screen that already has the app's own). |
| `.scrollDismissesKeyboard(.interactively)` | **hard** | Only the *finger-tracked* part is unreproducible. A `NestedScrollConnection` that hides the IME on the first downward drag is the honest substitute; the keyboard will snap rather than track. |
| `.ultraThinMaterial` in the scroll-edge veils | **hard** | No first-party equivalent. `RenderEffect.createBlurEffect` on a `GraphicsLayer` (API 31+) is close; below 31 fall back to the Reduce-Transparency branch (opaque bar at 1.0), which the design already specifies. |
| Liquid Glass tab bar + `tabBarMinimizeBehavior(.onScrollDown)` | **hard** | Owned by the shell, not this screen, but it decides `tabBarClearance` (76) and `bottomUnderfill` (180). **ERRATUM (2026-09-04, PLAN §9.2): both halves of this are superseded.** The port ships a **static `NavigationBar`** (PLAN D10 — the minimise behaviour is already a no-op on the iOS 18 floor, and a hand-rolled version is a different component), and **`bottomUnderfill` is KEPT** (PLAN D21): Compose's `Scaffold` insets content by the bottom bar identically, and dropping the 180-pt underfill puts live chevrons in the gesture-nav strip — the exact defect `chrome-images.md` §3.4 documents. |
| `.zoom` navigation transition / `zoomSource` | **n/a** | Already retired on iOS — Detail is a plain push. Do **not** build shared-element transitions into Detail; ship the platform's default forward transition. The `zoomID` strings can be dropped entirely. |
| `Menu(primaryAction:)` — tap acts, long-press opens | **easy** | `combinedClickable(onClick =, onLongClick =)` + `DropdownMenu`. |
| `.contentTransition(.symbolEffect(.replace.downUp))` | **easy** | `AnimatedContent` with vertical slide + fade; tune to `spring(dampingRatio = 0.88f)`. |
| `ViewThatFits` (the `FactLine` ladder) | **moderate** | No equivalent; needs `SubcomposeLayout` or a `TextMeasurer` loop. **Not required** — `FactLine` the view is dead code (§9.3). |
| `@ScaledMetric` | **easy** | `LocalDensity.current.fontScale` multiplied into the dp value. |
| `AccessibilityNotification.Announcement` (polite) | **easy** | `View.announceForAccessibility` / `LiveRegionMode.Polite` semantics on a hidden text node. Compose's `liveRegion` is the closer match to "polite". |
| Palette extraction for `PosterSlot`'s ground and `ArtBackdrop`'s tint | **easy** | **ERRATUM (2026-09-04, PLAN §9.2): never `androidx.palette`.** Port `dominantTint` verbatim per PLAN §3.6 — median-cut on HSL has no OKLab L ∈ [0.30, 0.44] / C ∈ [0.075, 0.145] clamp and no 15 % lean toward brand amber (unit hue 0.4175, 0.9087); adopting it changes the hue of every `ArtAdaptiveGround`, `PosterSlot` tint and `ArtBackdrop` in the app. Cache by URL exactly as `PaletteCache` does. |
| Haptic vocabulary | **moderate** | `HapticFeedbackConstants.CONTEXT_CLICK` ≈ `.selection`; `CONFIRM` ≈ `.success`; `VirtualEffect`/`VibrationEffect.createPredefined(EFFECT_TICK / EFFECT_CLICK)` for the impacts. Reproduce the **per-token rate floor** (0.04 s selection, 0.3 s everything else) and the "suppressed while not active" rule in the wrapper, not at call sites. |
| Pull-to-refresh with an armed haptic at 80 dp while dragging | **moderate** | M3 `PullToRefreshBox` exposes `state.distanceFraction`; combine with the drag phase to fire the tick once. **ERRATUM (2026-09-04, PLAN §3.4/§9.2): use `PullToRefreshBox` for the gesture and `distanceFraction` ONLY, passing `indicator = {}`.** Its default indicator is a Material tonal circle drawing its arc in `primary`; the visible refresh affordance stays the app's 400 ms in-bar spinner. |
| `UNUserNotificationCenter.authorizationStatus == .notDetermined` | **moderate** | Android has no `notDetermined`; track "we have asked" in DataStore and combine with `checkSelfPermission` + `shouldShowRequestPermissionRationale`. Below API 33 notifications need no runtime permission — the primer should then simply never appear. |
| `@AppStorage` | **easy** | `DataStore<Preferences>` (`preferencesDataStore`), read as a `Flow` in the ViewModel. |
| `UserDefaults` JSON for `recentItems` | **easy** | DataStore + `kotlinx.serialization`, or Room if the list ever grows past 10. |
| Curly quotes / NBSP / word-joiners in copy | **easy** | **ERRATUM (2026-09-04, PLAN §9.2): never `strings.xml`.** The catalogue is a Kotlin `object` in `:model` (PLAN F4 / R31 / §4.1) precisely so a `strings.xml` round-trip cannot eat U+00A0, U+2060, U+2019 or U+00B7 — and so `&` in five headings needs no escaping; `CopyAuditTest` asserts the code points. ~~Keep them literal in `strings.xml`; escape the NBSP as ` `. **Do not** let a translation pipeline normalise them. |
| Outfit variable font + SF text styles | **easy** | Bundle Outfit; map SF footnote/caption/caption2 to Roboto 13/12/11 sp. |
| The `handoff` asymmetric transition | **easy** | `AnimatedContent` with `fadeIn(spring(0.90, ...), delayMillis = 80) togetherWith fadeOut(tween(160, easing = EaseIn))`. |

---

## 15. Invariants a reviewer should check the port against

1. The trending grid is **the same object** at rest and focused, and **the same rows** the results use at
   accessibility sizes. It never becomes a different list under the finger.
2. The scope bar appears on the **first keystroke**, not on focus; while it is absent and a scope is
   active, the removable chip is on screen instead.
3. The hardened top veil's hold is **96 + safe area** at rest and **52 + safe area** when focused, and it
   is 0.74 canvas over a blur — never opaque, except under Reduce Transparency.
4. Results are `MediaRow`s only. No headers, no top-match card, no rank column, no "More results".
5. Exactly one thing on a row is amber: `when(item)`. Every tappable word — Clear, Turn on, Retry,
   Search instead for — is `interactive` ink.
6. The trending grid stays mounted under every empty, scoped-out and error state.
7. An add **never** raises the OS permission dialog. The primer appears ≥ 6.5 s later, only if the add
   stuck, only for an airing AniList show, only once per install.
8. A cancelled request is not a failure, and a superseded response never mutates state.
9. `size()` prints a season count for TMDB only, never for AniList.
10. The Undo window is 6 s, or 10 s while a screen reader is running.
