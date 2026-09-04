# State surfaces — empty, error, offline, stale, sync banner, toasts, skeletons

This is the behavioural specification for every surface that tells the user *the content is not
here yet, could not be fetched, is old, was written, or failed to be written*. Four files own it in
the iOS app: `Sources/DesignSystem/Primitives+States.swift` (empty state, inline notice, stale
strip, refresh indicator, sync banner, VoiceOver announcements, plus the passive primitives and
history rail that live in the same file), `Sources/DesignSystem/Skeletons+States.swift`
(`SkeletonGate` and the skeleton atoms), `Sources/DesignSystem/UndoToast.swift` (the toast layer and
the undo state model) and `Sources/DesignSystem/FranchiseContextMenu.swift` (the long-press quick
actions). Two rules from `CLAUDE.md` govern all of it and a port that breaks either is wrong even
if it compiles: **states are consumer, not SaaS** — an empty state is `ContentUnavailableView`'s
anatomy on the canvas (44-pt tertiary symbol, title, one sentence, ONE hugging button), an inline
notice is a footnote line and never an alert box, and a failed write wears the toast's glass capsule
— and **amber is not an action colour**: `accent` is spent on MEANING (a real next step) and STATE
(committed, selected, today), so a recovery button ("Try again") is a quiet capsule and only a
genuine next step ("Add a show") gets the amber one. Everything below is exact: no value in this
document is a range unless the source says it is.

---

## 0. Tokens this subsystem consumes

All values are literal from `Sources/DesignSystem/ThemeTokens.swift`. The port must define these
once, not per component.

### 0.1 Colour

| Token | Value | Used here for |
|---|---|---|
| `canvas` | `#09090B` | screen ground behind every state |
| `surfaceFlat` | `#171719` | `.plate` fill (skeleton card) |
| `surfaceRaised` | `#242428` | episode-still ground, unselected chip |
| `surfaceFloating` | `#2A2D36` | secondary button ground, Reduce-Transparency toast/banner ground |
| `surfacePressed` | `#353842` | pressed grounds |
| `textPrimary` | `#F4F1EC` | state title, toast message, banner text |
| `textSecondary` | `#AAA6A0` | supporting sentence, notice message |
| `textTertiary` | `#85817C` | state symbol, notice glyph, stale strip (both glyph and text), refresh spinner tint |
| `textDisabled` | `#807C77` | row chevrons (not used by states) |
| `accent` | `#F0A24E` | primary ("next step") button ground, query progress bar |
| `accentPressed` | `#D88D3B` | primary button pressed ground |
| `onAccent` | `#0B0B0D` | ink on the amber capsule |
| `interactive` | alias of `textPrimary` (`#F4F1EC`) | every bare tappable word: "Retry", "Dismiss", "Clear", "Try again" when tertiary |
| `warning` | `#FFD60A` | error-toast triangle, Profile sync glyph |
| `destructive` | `#FF453A` | destructive inline link ("Discard change") |
| `stroke` | white 12 % | secondary-button capsule edge |
| `strokeStrong` | white 20 % | floating-surface edge (Reduce Transparency), progress-bar track, history rail |
| `separatorQuiet` | white 4.5 % | in-plate dividers |
| `posterEdge` | white 9 % | artwork edge (episode still) |
| `hairline` | white 5.5 % | top-edge highlight on a raised surface |
| `plateLift` | white 5.5 % | `.plate` ground (a *lift over* whatever is behind, not an opaque fill) |
| `raisedLift` | white 11 % | `.raised` ground |
| `controlSheen` | white 22 % | lit top edge of a filled control |
| `skeleton` | `#F4F1EC` @ 11 % | every skeleton block |
| `scrim` / `scrimStrong` | black 56 % / 72 % | over-art label ground |
| `ambientBackdropFallback` | `#432D21` | the warm ground a skeleton hero opens on when no palette is remembered |

### 0.2 Spacing, radii, metrics

| Token | Value | | Token | Value |
|---|---|---|---|---|
| `ThemeSpace.x0_5` | 2 | | `ThemeRadius.episodeStill` | 8 |
| `x1` | 4 | | `poster` | 10 |
| `x2` | 8 | | `compactControl` | 12 |
| `x3` | 12 | | `row` | 16 |
| `x4` | 16 | | `toast` | 18 (legacy; the toast is a capsule now) |
| `x5` | 20 | | `card` | 22 |
| `x6` | 24 | | `focusCard` | 24 |
| `x8` | 32 | | | |
| `x10` | 40 | | `ThemeMetrics.gutter` | 16 |
| `x12` | 48 | | `sectionGap` | 30 |
| `x16` | 64 | | `labelGap` | 10 |
| | | | `cardGap` | 10 |
| | | | `shelfGap` | 12 |
| | | | `artGap` | 14 |
| | | | `rowCompact` | 56 |
| | | | `rowStandard` | 88 |
| | | | `rowMedia` | 100 |
| | | | `rowEpisode` | 82 |
| | | | `tabBarVisualHeight` | 90 |
| | | | `tabBarClearance` | 76 (`bottomChromeHeight` 64 + `x3`) |
| | | | `toastClearance` | 62 |

### 0.3 Type

| Token | Font | Tracking |
|---|---|---|
| `showTitleL` | Outfit-SemiBold 22, scales with `.title2` | −0.35 |
| `showTitleM` | Outfit-SemiBold 17, scales with `.headline` | −0.20 |
| `sectionTitle` | Outfit-SemiBold 20, scales with `.title3` | −0.30 |
| `callout` | Outfit-Regular 16, scales with `.callout` | −0.10 |
| `button` | Outfit-SemiBold 16, scales with `.callout` | −0.15 |
| `body` | Outfit-Regular 17 | −0.10 |
| `metadata` | **system** footnote (SF, 13 at default) | 0 |
| `metadataEmphasis` | system footnote semibold | 0 |
| `sectionLabel` | system caption2 semibold, rendered uppercase | +1.0 |
| `caption` | system caption2 | 0 |
| `listAction` | Outfit-SemiBold 13, scales with `.footnote` | 0 |
| `rowTitle` | Outfit-SemiBold 17 | −0.20 |
| `rowMeta` | system footnote | 0 |

Outfit is bundled (`ios/Resources/Fonts/Outfit-{Light,Regular,Medium,SemiBold,Bold}.ttf`) and ports
as-is. SF Pro must be replaced by the platform system font (Roboto) — those tokens exist precisely
because Outfit has no tabular figures.

### 0.4 Motion

| Token | Curve |
|---|---|
| `uiPress` | easeOut 0.09 s |
| `uiMicro` | spring(response 0.22, damping 0.88) |
| `uiSnappy` | spring(response 0.34, damping 0.84) |
| `uiSettle` | spring(response 0.46, damping 0.90) |
| `uiMilestone` | spring(response 0.38, damping 0.74) |
| `uiGentle` | easeInOut 0.22 s |
| `uiReveal` | cubic-bezier(0.22, 1.00, 0.36, 1.00) 0.28 s |
| `uiPoster` | easeOut 0.18 s |
| `uiNumeric` | easeOut 0.22 s |
| `uiSweep` | cubic-bezier(0.40, 0.00, 0.20, 1.00) 0.52 s |
| `uiDismiss` | easeIn 0.16 s |
| `uiReduced` | easeOut 0.12 s |
| `uiCrossfade` | **an alias of `uiReduced`** — "board 09's 120-ms crossfade and board 11's Reduce Motion fallback are the same curve, so this is a name for `uiReduced`, not a fourteenth token" |

`ThemeMotion.pick(token, reduceMotion:)` returns `uiReduced` when Reduce Motion is on. **Every**
animation in this subsystem goes through `pick` except the ones explicitly documented as unconditional
(`SkeletonGate`'s crossfade, `Freshness`'s two `uiGentle`s, `ScrollEdgeChromeModifier`'s veil fade).

Two named transitions:

```swift
// AnyTransition.toast(reduceMotion:)
insertion: .opacity + .offset(y: 4)  animated with uiSnappy
removal:   .opacity                  animated with uiDismiss
// Reduce Motion: .opacity animated with uiReduced, both directions
```

```swift
// AnyTransition.handoff(reduceMotion:)  — one card replaced by the next
insertion: .opacity  animated with uiSettle.delay(0.08)
removal:   .opacity  animated with uiDismiss
// Reduce Motion: .opacity with uiReduced, no delay
```
The asymmetry is load-bearing: "a symmetric crossfade superimposes two different sentences, which is
what a smear is."

### 0.5 Shadows

| Token | Colour | Radius | Y |
|---|---|---|---|
| `.none` | clear | 0 | 0 |
| `.card` | black 45 % | 18 | 10 |
| `.art` | black 55 % | 12 | 7 |
| `.artHero` | black 60 % | 26 | 14 |
| `.floating` | black 50 % | 26 | 14 |

Toast and sync banner both use `.floating`.

### 0.6 Haptics

Every haptic goes through `FeedbackCoordinator.fire(_:)`, **at most one per transaction**, and it is
suppressed entirely when the app is not `active` or when the user's `previously.haptics` preference
(UserDefaults, default `true`) is off. Per-token throttle floor: `.selection` 40 ms, everything else
300 ms (per token, not shared — "two shows added in quick succession buzzed once" was the bug).

| Token | iOS generator | Fired by, in this subsystem |
|---|---|---|
| `.selection` | `UISelectionFeedbackGenerator` | Undo tapped (all three branches); clearing a filter from an empty state |
| `.commitLight` | impact light, intensity 0.65 | `removeFromLibrary` (so `removeWithUndo`) |
| `.commitMedium` | impact medium, intensity 0.72 | `markCaughtUp` when it is not a milestone |
| `.success` | notification success | `markCaughtUp` when it completes a finished part; `addToLibrary` |
| `.destructive` | notification **warning** | confirming "Discard N changes" in the sync banner |
| `.refreshArmed` | impact light, intensity 0.50 | pull-to-refresh crossing the threshold, once per pull |
| `.directError` | notification error | a write the user explicitly retried failing again (fired by `SyncCenter`, never by the banner) |

The banner is **silent on appearance**: "a background failure earns no haptic".

---

## 1. `Announce` — VoiceOver status announcements

```swift
@MainActor enum Announce {
    static func status(_ message: String)           // polite; queued behind current speech
    static func screenChanged(_ message: String?)   // the stage changed under the user
}
```
Both no-op unless VoiceOver is running; `status` also no-ops on an empty string.

Why it exists, verbatim from the source: *"The shipped build had 45 labels, 10 hints, 6 values, 10
added traits and **zero** announcements and zero custom actions. A VoiceOver user typed a query and
results arrived, or didn't, or failed — and nothing was spoken; marks committed silently; the undo
toast appeared and expired unheard. Every state that SETTLES without the user having navigated to it
announces here."*

Call sites relevant to this area:

| Trigger | Announcement |
|---|---|
| `appModel.undo` changes to non-nil (`ToastHost`) | `"{undo.message}. Undo available."` |
| `appModel.errorToast` becomes non-nil | the error message verbatim |
| `appModel.notice` becomes non-nil | the notice verbatim |
| a queue row mark commits (Today) | `Copy.Progress.episodeWatched(n)` → `"Episode 12 watched"` |
| a hero mark commits (Today) | same |
| a batch confirmed | `Copy.Confirm.batchMarkConfirm(n)` → `"Mark 6 episodes as watched"` |
| search results settle (Discover) | `outcomeTitle` — `"7 results"`, or `"7 results. Results couldn’t refresh"`, or the empty-state title |

**Android**: `status` maps to `View.announceForAccessibility` / Compose
`LiveRegionMode.Polite` on a text node; `screenChanged` has no exact TalkBack equivalent — use
`announceForAccessibility` plus moving accessibility focus to the new content root. Moderate.

---

## 2. `EmptyState`

The one whole-surface (or whole-section) "there is nothing here" component. Centred, not
left-aligned.

**Why**, verbatim: *"The shipped card was a left-aligned marketing plate with the symbol floating
unattached at the top-left (its ink landing 2 pt right of the headline's x), a fixed
`.system(size: 22)` that ignored Dynamic Type entirely, and a full-width accent capsule that read as
a banner CTA. Centred with the symbol in its own tile is the shape every system
`ContentUnavailableView` has, and it is the shape a user recognises as 'there is nothing here'
rather than as an advertisement."* And: *"It was a plate with a glyph in a tile, an ambient bloom, a
236-pt floor and a 280-pt amber capsule: an 'empty state card' from a dashboard template, and the
thing that made every failure in the app look like a SaaS product had crashed."*

### 2.1 API

```swift
EmptyState(_ copy: EmptyStateCopy,
           prominence: Prominence = .major,
           primary: (() -> Void)? = nil,
           secondary: (() -> Void)? = nil)
enum Prominence { case major; case section }
```

**`primary` MUST precede `secondary` in the parameter list.** It used to be last, so
`EmptyState(.serverNoCache) { retry }` bound the trailing closure to `secondary` by Swift's
forward-scan rule — `serverNoCache` has no secondary label, so **Schedule's and Detail's whole-screen
server errors shipped with no "Try again" at all** while the identical card on Today and Library
(which passed `primary:` explicitly) was recoverable. A DEBUG assertion backs the ordering:

```swift
assert(copy.primaryLabel == nil || primary != nil || secondary != nil,
       "EmptyState “\(copy.title)” declares “\(copy.primaryLabel ?? "")” but was given no handler")
```
A port should keep this as a debug-build check: a state whose copy promises an action, wired to
nothing, is the class of bug this catches.

### 2.2 Layout — top to bottom, `VStack(spacing: 0)`

| Element | Condition | Spec |
|---|---|---|
| Symbol | `copy.symbol != nil` | SF Symbol, `system(size: glyph, weight: .regular)`, `textTertiary`, bottom padding **16** (`major`) / **12** (`section`), `accessibilityHidden(true)` |
| Title | always | `showTitleL` (major) / `showTitleM` (section), `textPrimary`, centred, `lineLimit` **3** (major) / **2** (section) — **nil (unlimited) at accessibility text sizes**, `fixedSize(vertical)` |
| Supporting | `copy.supporting != nil` | `callout` (major) / `metadata` (section), `textSecondary`, centred, `fixedSize(vertical)`, top padding **8** |
| Action stack | `hasAction` | `VStack(spacing: 4)`, top padding **20** |
| — primary | `copy.primaryLabel != nil && primary != nil` | see 2.3 |
| — secondary | `copy.secondaryLabel != nil && secondary != nil` | `TertiaryButtonStyle2` (bare `interactive` word, 44×44 min target, pressed opacity 0.6) |

Glyph size: `(prominence == .major ? 44 : 30) * glyphUnit`, where `glyphUnit` is a
`@ScaledMetric(relativeTo: .title3)` seeded at 1 — **the symbol answers to Dynamic Type like the
type beside it**. On Android: multiply the base size by `fontScale` clamped the way `.title3` scales.

Container: `.frame(maxWidth: 300)` then `.frame(maxWidth: .infinity)` — the copy column is capped at
300 pt and the whole block is centred in whatever it is given.
Accessibility: one element (`children: .contain`) labelled `copy.spokenLabel`.
Transition: `.opacity` only — *"an empty state that scales in reads as a celebration of having
nothing."*

`hasAction` is computed as `(primaryLabel != nil && primary != nil) || (secondaryLabel != nil &&
secondary != nil)`. *"A label without a handler is a dead control, not a disabled one: the button
exists only when the caller supplied something for it to do."*

### 2.3 The ONE hugging button, and when it is amber

```swift
if copy.isRecovery { Button(label).buttonStyle(SecondaryButtonStyle2()) }
else               { Button(label).buttonStyle(PrimaryButtonStyle2())   }
```
with `.fixedSize(horizontal: !isAX, vertical: false)` in both branches.

`EmptyStateCopy.isRecovery` is `primaryLabel == "Try again" || primaryLabel == "Retry"`. So:

| Kind of action | Example labels | Style |
|---|---|---|
| Recovery (retries a fetch) | "Try again", "Retry" | **quiet** — `SecondaryButtonStyle2` |
| Next step | "Add a show", "Browse your library", "Clear", "Show all" | **amber** — `PrimaryButtonStyle2` |

*"Hugging, never a banner. A recovery ('Try again') is a quiet capsule — amber is for a real next
step ('Add a show'), not for retrying a fetch."*

`.fixedSize(horizontal: true)` is what makes the capsule hug its label despite the styles declaring
`frame(maxWidth: .infinity)`. At accessibility text sizes the horizontal fixed size is dropped so the
button may take the full 300-pt column and wrap.

Button style geometry:

| Style | Height | H-padding | Ground | Ink | Edge | Press |
|---|---|---|---|---|---|---|
| `PrimaryButtonStyle2` | min 48 | 18 | `accent` → `accentPressed` when pressed, Capsule | `onAccent` | Capsule `strokeBorder` linear-gradient `controlSheen`→clear, top→center, 1 pt | scale 0.985; disabled opacity 0.38 |
| `SecondaryButtonStyle2` | min 44 | 18 | `surfaceFloating` → `surfacePressed`, Capsule | `textPrimary` | Capsule `strokeBorder` `stroke`, 1 pt | scale 0.985 |
| `TertiaryButtonStyle2` | min 44 × min 44 | — | none | `interactive` (or `destructive`) | none | opacity 0.6 |

**Reduce Motion presses in opacity, never in scale**: `pressFeedback` sets `opacity 0.72` while
pressed and keeps `scaleEffect` at 1.

The lit top edge is not decoration: *"Flat #F0A24E across 48×376 pt is a swatch of orange; one 22 %-
white hairline along the top, dead by the vertical centre, is what makes it read as a physical,
pressable object."*

### 2.4 `centredState` — where a whole-surface state sits

```swift
func centredState(contentH: CGFloat, clearance: CGFloat = ThemeMetrics.tabBarVisualHeight) -> some View {
    frame(maxWidth: .infinity, minHeight: max(0, contentH - clearance), alignment: .center)
}
```
`contentH` is the scroll view's own height. The default clearance is **90** (`tabBarVisualHeight` —
pill plus home-indicator strip), **not** `tabBarClearance` (76). *"They are different numbers for
different jobs: a scroll inset has to clear the ramp as well as the bar, and subtracting that inset
when centring pushed every empty state ~81 pt above true optical centre on Today and Schedule. Half
of whatever is subtracted is the error."*

`minHeight`, never `height`, so AX3–AX5 grows the block rather than clipping it outside the
scrollable region.

Today additionally subtracts its header band before centring and re-adds it as top padding:
`.centredState(contentH: contentH - TodayView.headerBand).padding(.top, TodayView.headerBand)`.

### 2.5 The complete `EmptyStateCopy` catalogue (verbatim)

`EmptyStateCopy` is **data, not a view**: `(symbol, title, supporting, primaryLabel, secondaryLabel)`,
`Equatable`, `Sendable`. `spokenLabel` = `"{title}. {supporting}"`, or just the title when there is
no supporting line.

| Name | Symbol | Title | Supporting | Primary | Recovery? |
|---|---|---|---|---|---|
| `emptyAccount` | `rectangle.stack` | Your library is empty | Everything you add shows up here. | Add a show | no |
| `emptyToday` | `tv` | Nothing to watch yet | Add a show and this screen fills in with what is next. | Add a show | no |
| `emptySchedule` | `calendar` | Nothing scheduled | Add a show and its air dates appear here. | Add a show | no |
| `noWatching` | `bookmark` | Nothing in Watching | Move a show to Watching to build Today. | Browse your library | no |
| `offlineCached` | `wifi.slash` | You’re offline | Showing saved data. Changes will sync when you reconnect. | — | — |
| `offlineNoData` | `wifi.slash` | You’re offline | Connect to the internet to load your library. | Try again | **yes** |
| `serverNoCache` | `exclamationmark.circle` | Couldn’t load your library | Something went wrong. Try again in a moment. | Try again | **yes** |
| `searchLaunchpad` | `magnifyingglass` | Find your next show | Search anime and TV by title. | — | — |
| `searchFailed` | `wifi.exclamationmark` | Couldn’t search right now | Check your connection and try again. | Try again | **yes** |
| `searchUnavailable` | `exclamationmark.circle` | Couldn’t search right now | Something went wrong. Try again in a moment. | Try again | **yes** |
| `searchOffline` | `wifi.slash` | You’re offline | Search needs a connection. Trending shows appear when you reconnect. | Try again | **yes** |
| `noSessions` | `clock.arrow.circlepath` | No watch history yet | Your first watch is recorded when you finish the show. Rewatches appear here as sessions. | — | — |
| `nothingScheduled` | `calendar` | Nothing scheduled | None of the shows you follow have an upcoming date. | — | — |
| `noFilterMatches` | `slider.horizontal.3` | No titles match | Clear the filters to see everything in your library. | Clear | no |
| `everythingSynced` | `checkmark.circle.fill` | Everything synced | No changes are waiting to sync. | — | — |

Parameterised:

| Name | Symbol | Title | Supporting | Primary |
|---|---|---|---|---|
| `noSearchResults(query:)` | `magnifyingglass` | No results for “{query}” | Check the spelling or try another title. | — |
| `Copy.Library.noSearchResults(query:filtered:)` | as above | as above | as above | **Clear** when `filtered`, else none |
| `noScopeMatches(scope:query:)` | `magnifyingglass` | Nothing in {scope} for “{query}” | Switch the scope to All to see every result. | Show all |
| `noScopeTrending(scope:)` | `line.3.horizontal.decrease` | Nothing trending in {scope} | Switch the scope to All to see what everyone is watching. | Show all |
| `calmToday(title:when:)` | **nil** | Nothing changed since you were last here | `"{title} {when, first letter lowercased}."` or `"No new dates have been announced."` | — |
| `caughtUp(title:when:)` | `checkmark.circle.fill` | You’re caught up | `"{title} {when, lowercased first}."`, else none | — |

Notes that must survive the port:

* The quotation marks in `No results for “one pece”` are **curly** (U+201C / U+201D). Every
  apostrophe in the table is U+2019. The copy audit (`Copy.auditProblems`) fails the build's preview
  on a straight `'`, an `!`, or banned episode notation (`E19`, `Ep 19`).
* `calmToday` is **no longer rendered by any screen** — Today's calm open is a quiet headline
  (`TodayView.calmBlock`), not a plate. It is kept for previews and the copy audit. Do not port it as
  a live state; port the rule: *"'Nothing changed since you were last here' led every calm morning
  with an absence, at display size, above an Upcoming row restating its own supporting sentence."*
* `searchFailed` and `searchUnavailable` share a title on purpose: **one failure has one name**. The
  offline/online split decides which supporting sentence and which glyph, never a different title.
* A state never promises a benefit on another tab. `emptyAccount`, `emptyToday` and `emptySchedule`
  are three different sentences for the same condition because each surface owns its own.
* The brand is never a clause subject: "Couldn’t reach the server", never "Previously couldn’t reach
  the server", never "Search couldn’t reach the server".

### 2.6 Which state, on which screen — the full decision matrix

Model-side derivation (`AppModel+States.swift`):

```swift
var surfacePhase: SurfacePhase {
    if library.isEmpty {
        if loading   { return .loading }        // no cache + request in flight
        if loadError { return .errorNoCache }
        return .emptyAccount
    }
    return .content(refreshing: isRefreshing, staleSince: staleSince(.exactAiring), sectionFailed: loadError)
}
var isRefreshing: Bool { loading && !library.isEmpty }
var sectionFailed: Bool { loadError && !library.isEmpty }
var emptyStateCopy: EmptyStateCopy {   // errorNoCache → online?/offline?
    case .errorNoCache: SyncCenter.shared.isOnline ? .serverNoCache : .offlineNoData
    default:            .emptyAccount
}
```
**Order matters**: cached content always beats a failed refresh (the network never blanks the
library), and an empty account is never shown while a first load is still running.

**Offline vs. server-unreachable is decided by `SyncCenter.isOnline` (an `NWPathMonitor` path
status), never guessed from the error.** A captive portal that reports "satisfied" while every
request fails is accepted: *"claiming the user is offline when they are not is the worse lie."*

| Screen | Condition | Rendered |
|---|---|---|
| Library root | `loading && library.isEmpty` | `SkeletonGate` → root skeleton |
| Library root | `library.isEmpty` after settle | `EmptyState(appModel.emptyStateCopy, .major, primary: emptyStateAction)`, gutter-padded, `centredState(contentHeight)` — action is *reload* when `loadError`, else *Add a show* → Search |
| Library root | content + `sectionFailed` | `InlineNotice(Copy.Notice.library)` with reload, above the content |
| Library All-titles | same three, plus `results.isEmpty` | `emptyResultsCopy` = `noFilterMatches` when the query is empty, else `Copy.Library.noSearchResults(query:filtered:)`; primary = `resetFilters` only when `hasFilters` |
| Schedule | `loading && library.isEmpty` | `SkeletonGate(isLoading: true) { feedSkeleton } content: { EmptyView() }` |
| Schedule | `loadError && libraryEmpty` | centred `serverNoCache` / `offlineNoData`, primary = `reload()` |
| Schedule | `libraryEmpty` | centred `emptySchedule`, primary = Add a show |
| Schedule | content, `sectionFailed` | `InlineNotice(Copy.Notice.schedule)` |
| Schedule | content, `staleSince(.exactAiring)` (and **not** sectionFailed) | `StaleStrip` |
| Schedule | all days empty | centred `nothingScheduled` (no action) |
| Schedule | days empty *because of* the filter | centred `noFilterMatches`, primary clears `typeFilter = .all; unwatchedOnly = false` inside `uiSnappy` and fires `.selection` |
| Today | `loading && libraryEmpty` | `SkeletonGate` → Today skeleton |
| Today | empty account / failure | `stateBlock(copy)` — `EmptyState` + gutter + `centredState(contentH − headerBand)` + `.padding(.top, headerBand)`; behind `emptyToday` **only**, a 3-poster fan at opacity 0.35 |
| Today | content, `sectionFailed` | `InlineNotice(Copy.Notice.today)` with reload |
| Detail | `franchise == nil && loading && !loadError` | `SkeletonGate` → detail skeleton |
| Detail | `loadError` and no franchise | `EmptyState(serverNoCache/offlineNoData, .major) { load() }`, gutter-padded |
| Detail | content, `staleAfterFailure` | `InlineNotice(Copy.Notice.detailEpisodes)` with `load(force: true)` |
| Search launchpad | trending empty + offline | `searchOffline` centred, primary reloads trending |
| Search launchpad | trending empty because scope ≠ All while `trending` non-empty | `noScopeTrending(scope:)`, primary sets `mediaFilter = .all` inside `uiSnappy` |
| Search launchpad | otherwise nothing to show | `searchLaunchpad` centred |
| Search results | scope emptied a non-empty result set | `noScopeMatches(scope:query:)`, primary widens scope — then the trending grid **still follows below it** |
| Search results | genuinely empty | notices, then `searchError ? errorCopy : noSearchResults(query:)`; `errorCopy` = `isOnline ? searchUnavailable : searchFailed` |
| Watch history | no sessions | `EmptyState(.noSessions, .major)` |
| Profile | no failed changes | the calm footnote line, **not** an `EmptyState` plate (see §5.6) |

The "state, then the artwork we already have" rule on Search
(`stateWithTrending`) is deliberate: *"The app used to throw away a decoded shelf in order to say one
sentence, leaving a plate over 900 pt of black — on the screen a reviewer walks first."*

**Android**: everything here is portable. The only awkward piece is the SF Symbol names — see §11.

---

## 3. `InlineNotice`

"This section's refresh failed" — the content stays, the notice sits under the section header.
Never a full-screen error, never a toast: *"a background failure is silent and repairable."*

**Why it looks like this**: *"It was a plate with a 3-pt warning rule down its edge, a bold triangle
and a 17-pt 'Retry' — an alert box, on screens whose content had loaded fine from the cache. A
background refresh that failed is a footnote (Mail's 'Cannot connect' at the foot of the list), never
a warning."*

```swift
InlineNotice(_ message: String, kind: Kind = .failure, retry: (() -> Void)? = nil)
enum Kind { case failure; case info }
```

Layout (`AnyLayout` swap on accessibility text size):

* **Default**: `HStack(alignment: .firstTextBaseline, spacing: 8)`
* **Accessibility sizes**: `VStack(alignment: .leading, spacing: 4)`

Inner group — `HStack(alignment: .firstTextBaseline, spacing: 6)`:

| Element | Spec |
|---|---|
| Glyph | `wifi.exclamationmark` (failure) / `info.circle` (info), `system(size: 12, weight: .semibold)`, `textTertiary` |
| Message | `metadata` (SF footnote), `textSecondary`, `fixedSize(vertical)` |

The glyph + message are combined into one accessibility element labelled with the message (the glyph
is never spoken).

Retry link (only when `retry != nil`): `Button("Retry")` with `InlineLinkButtonStyle`, then
`.padding(.vertical, -12)` and `.padding(.leading, isAX ? -12 : -4)`. The negative padding is
optical: the style holds its own 44-pt target with 14-pt vertical + 12-pt horizontal padding, and
without pulling it back the link sits 12 pt off the message's baseline. Accessibility hint:
`"Tries the request again"`.

Container: `frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)`, transition `.opacity`.

`InlineLinkButtonStyle` (shared with section headers): `listAction` type (Outfit SemiBold 13),
`interactive` ink (or `destructive`), `padding(.vertical, 14).padding(.horizontal, 12)`,
`frame(minHeight: 44)`, `contentShape(Rectangle())`, pressed opacity 0.55 on `uiPress`. *"Leading-only
padding ends the hit area at the last glyph — the user has to hit the WORD."*

### 3.1 Every notice string (verbatim)

| Symbol | String |
|---|---|
| `Copy.Notice.today` | Airing dates couldn’t refresh |
| `Copy.Notice.schedule` | The schedule couldn’t refresh |
| `Copy.Notice.library` | Your library couldn’t refresh |
| `Copy.Notice.detailEpisodes` | Episodes couldn’t refresh |
| `Copy.Notice.searchAnime` | Anime results couldn’t refresh |
| `Copy.Notice.searchTV` | TV results couldn’t refresh |
| `Copy.Search.couldNotRefresh` | Results couldn’t refresh |
| `Copy.Notice.notInCatalogue` | Not in the catalogue yet |
| `Copy.Toast.offlinePending` (as `kind: .info`) | Saved on this device. Waiting to sync. |

Noun-first is the rule: *the thing that failed, then what happened to it.*

### 3.2 Failure-reason vocabulary — `Copy.Notice.reason(_:)`

The user-facing reason for a failed write. **Never a status code, never `localizedDescription`.**

| Condition | String |
|---|---|
| `APIError.unauthorized` | Signed out |
| HTTP 429 | Try again in a minute |
| any other HTTP status | Something went wrong |
| `NSURLErrorNotConnectedToInternet`, `NetworkConnectionLost`, `DataNotAllowed`, `CannotConnectToHost`, `CannotFindHost`, `InternationalRoamingOff` | No connection |
| `NSURLErrorTimedOut` | Took too long |
| anything else | Something went wrong |

Profile softens one of these on the way to the screen: `Something went wrong` → `Couldn’t connect`
(`Copy.Account.couldNotReachServer`), passing everything else through.

Search stacks notices: the whole-request failure line first, then the per-catalogue lines, each in
its own `InlineNotice` inside a `VStack(spacing: 8)`, all carrying the same `retrySearch` handler.

---

## 4. `StaleStrip`, `RefreshIndicator` and the `freshness` pair

### 4.1 `StaleStrip`

"Updated 8h ago". **Passive by decision**: pull-to-refresh is the refresh affordance, and a tappable
strip would be a second, invisible one. No ground, no stroke, no 44-pt rule.

```swift
StaleStrip(since: Int64 /* epoch ms */, now: Int64)
```

| Element | Spec |
|---|---|
| Glyph | `arrow.triangle.2.circlepath`, `system(size: 11, weight: .regular)`, `textTertiary` |
| Text | `Copy.updated(at:now:)`, `metadata`, `textTertiary`, `fixedSize(vertical)` — it **wraps** at AX5 where the footnote token is ~44 pt and "Updated Aug 19, 2025" cannot fit a line |
| Layout | `HStack(spacing: 6)` + trailing `Spacer(minLength: 0)`, `frame(minHeight: 28, alignment: .leading)` |
| Accessibility | one element (`children: .ignore`), label `Copy.updatedSpokenLabel(at:now:)`, trait `.isStaticText` |
| Transition | `.opacity` |

Elapsed ladder (`Copy.updated` = `"Updated " + elapsedWord`; `Copy.synced` = `"Synced " + elapsedWord`
— one function, two verbs):

| Elapsed | Word |
|---|---|
| < 1 min | just now |
| < 60 min | `{n} min ago` |
| same calendar day | `{n}h ago` |
| yesterday | yesterday |
| 2–6 days ago | the weekday name ("Wednesday") |
| older | `TemporalCopy.dateWord` → "Aug 19" / "Aug 19, 2025" |

Spoken form spells it out — `"Updated just now"`, `"Updated 8 minutes ago"`, `"Updated 8 hours ago"`,
falling through to the written form for anything a day or older. Never "8h" to VoiceOver.

### 4.2 Staleness thresholds

`SyncCenter.DataClass` — a class is stale when `now − stamp >= threshold`:

| Class | Threshold | Rationale (source) |
|---|---|---|
| `exactAiring` | 30 min | "AniList airing instants. Wrong within half an hour is wrong." |
| `dateOnlySchedule` | 6 h | "TMDB date-only schedule. A day's worth of drift is invisible; six hours is the limit." |
| `catalogue` | 24 h | "Titles, artwork, season structure. Changes on the order of days." |

There is exactly **one** freshness stamp and `SyncCenter` does not own it: `AppModel.lastLoadedAt`
is read through an installed closure (`SyncCenter.signals`). Per-class `stamp(_:at:)` is optional
refinement; an unstamped class falls back to the library-wide stamp. **`staleSince` returns nil
before the first successful load** — *"a page that has never loaded is not stale, it is loading"* —
and artwork failures never reach here, so a failed poster can never mark a page stale.

### 4.3 `RefreshIndicator`

The small spinner beside a screen title while a refresh runs **over content that is already on
screen**.

* `ProgressView().controlSize(.small)`, tint `textTertiary`, `frame(16 × 16)`.
* Visible only after **400 ms** in flight ("below that it is a flicker"); `visible` animates on
  `pick(uiGentle)`.
* Suppressed entirely while a native pull is driving — the system pull indicator owns that moment.
* `accessibilityHidden(true)`.
* The show/hide task is keyed on `[isRefreshing, suppressed]`: any change cancels the pending 400-ms
  sleep, and `visible` is set to `false` immediately when either guard fails.

### 4.4 `.freshness(_:appModel:pullDriving:)`

The composed pair, applied to a screen's title view so five screens do not hand-assemble it five
ways:

```swift
VStack(alignment: .leading, spacing: 0) {
    content
    if let since = appModel.staleSince(dataClass) {
        StaleStrip(since: since, now: appModel.now).padding(.vertical, 8)
    }
}
.toolbar {                                  // the spinner lives in the NAVIGATION BAR
    if appModel.isRefreshing, !pullDriving {
        ToolbarItem(placement: .topBarTrailing) { RefreshIndicator(...) }
            .chromeSharedBackgroundHidden()  // iOS 26 wraps toolbar items in glass; an invisible
                                             // spinner would be an empty disc beside the title
    }
}
.animation(uiGentle, value: appModel.isRefreshing)
.animation(uiGentle, value: appModel.staleSince(dataClass))
```
*"In flow above the content it reserved a 16-pt row at idle — the void between 'Library' and the All
titles row."* The `if` around the `ToolbarItem` matters: the item is **mounted only while
refreshing**, not held at opacity 0.

Call sites: Library root (`.catalogue`, `pullDriving:` bound to the pull state) and Library
All-titles (`.catalogue`). Schedule renders `StaleStrip` directly for `.exactAiring`.

### 4.5 `.previouslyRefreshable(threshold: 80)`

Native pull-to-refresh plus the one thing the motion board asks of a pull: `.refreshArmed`, once.

```swift
.refreshable { await action() }
.onScrollPhaseChange { _, phase, _ in
    dragging = (phase == .tracking || phase == .interacting)
    if phase == .idle { armed = false }
}
.onScrollGeometryChange(for: CGFloat.self) { -(geo.contentOffset.y + geo.contentInsets.top) }
action: { _, pull in
    let progress = pull / threshold                        // threshold defaults to 80 pt
    if !armed, dragging, progress >= 1 { armed = true; FeedbackCoordinator.fire(.refreshArmed) }
    else if armed, progress < 0.3 { armed = false }        // re-arm only well back, so a wobble
}                                                          // at the threshold cannot buzz twice
```
`dragging` is the whole point: *"a fast flick to the top overshoots well past the threshold under
momentum with no finger down, and the system `refreshable` does NOT fire for that. `.refreshArmed`
promises 'let go now and it refreshes', so it may only fire while there is something to let go of."*

The custom bookmark-fill refresh graphic is **deliberately not drawn**: suppressing the system
indicator is not supported API and two indicators is worse than none.

---

## 5. `SyncBanner` — the persistent write-failure surface

Sits above the tab bar, inside `ToastHost`. **A failed write is never a transient toast: it stays
until it is retried or discarded.**

### 5.1 Anatomy

```swift
SyncBanner(count: Int, retry: (() -> Void)? = nil)
```

* Layout: `HStack(spacing: 12)`; at accessibility sizes `VStack(alignment: .leading, spacing: 12)`.
* Message: `Copy.Toast.syncFailed(count)` in `metadataEmphasis`, `textPrimary`, `lineLimit(2)`,
  `fixedSize(vertical)`.
  * `syncFailed(n)` = `"{n} changes couldn’t sync"` where the count is pluralised through
    `Copy.plural` → `"1 change"` / `"3 changes"` with a **non-breaking space (U+00A0)** between the
    numeral and the noun. A numeral must never end a line its unit does not start.
* Trailing control, one of two:
  * `retry != nil` → `Button("Retry")`, `TertiaryButtonStyle2` (AX: `SecondaryButtonStyle2`),
    `.disabled(retryInFlight)`, hint `"Tries the request again"`.
  * `retry == nil` → `Button("Dismiss")` with the same style pair, opening the discard confirmation.
    *"Nothing can be retried from here (the change came from a previous launch): the banner still
    needs a way out, and discarding a write is confirmed first."*
* Padding: leading **16**; trailing **16** at AX, else **4**; vertical **12** at AX, else **0**.
* `frame(minHeight: 48)`, `fixedSize(vertical)`.
* Ground: `chromeGlass(in: Capsule())` + `.shadow(.floating)` — **the toast's own capsule**.
  *"A failed write is the same class of message as a committed one, and it wears the same object;
  only its persistence differs."* It was a full-width floating plate at 17 pt — a system alert bar
  laid across the app.
* Accessibility: `children: .contain` + `.isSummaryElement`.
* Transition: `.opacity` — "persistent chrome fades; it never springs in".
* Width in the host: `.frame(maxWidth: 420)`.

### 5.2 Retry is optimistic, and double-tap-proof

There is **no spinner**: *"a local-first write returns before the network does — a spinner here
could only be a lie about waiting."* Instead:

```swift
private static let retryLockout: Duration = .milliseconds(800)
func issueRetry(_ retry: @escaping () -> Void) {
    guard !retryInFlight else { return }
    retryInFlight = true
    retry()
}
// .task(id: retryInFlight): sleep 800 ms, then retryInFlight = false
```
*"A timed hold, not a gate on a spring: the sync closure returns immediately, so there is no
completion to wait on. Long enough to swallow a double-tap, short enough that a banner which comes
straight back is pressable again."*

The banner leaves as soon as the retry is issued (the failed rows are removed by `SyncCenter`) and
returns if the write fails again.

### 5.3 Discard confirmation

`confirmationDialog(titleVisibility: .visible)`:

| Slot | String |
|---|---|
| Title | `"Discard {n} changes?"` (`Copy.Account.discardChangesTitle`) |
| Message | They were never saved to your account. Your library here stays as it is. |
| Destructive button | `"Discard {n} changes"` → fires `.destructive` haptic, then `SyncCenter.shared.discardAll()` |
| Cancel | Cancel |

### 5.4 `SyncCenter` — the model behind the banner

`@MainActor @Observable` singleton. State the banner reads:

| Member | Meaning |
|---|---|
| `failedChanges: [FailedChange]` | one row per `(command, title)` pair — *"a repeatedly failing write is one problem, not a list"* |
| `canRetryAny: Bool` | at least one row has something Retry can actually run |
| `profileIsOpen: Bool` | Profile lists every failure with Retry and Discard, so the banner is suppressed there |
| `isOnline: Bool` | `NWPathMonitor` path satisfied |
| `toastSeconds` | 6, or **10 while VoiceOver runs** |
| `errorSeconds` | 4, or **8 while VoiceOver runs** |

`FailedChange`: `id`, `command` (a `Copy.Action` / `Copy.Toast` string), `title` (the show),
`reason` (a `Copy.Notice.reason` string), `at` (epoch ms), `attemptCount`, an optional `WriteIntent`,
and an optional in-memory `retry` closure. `key = "{command}\u{1F}{title}"`.

`record(command:title:reason:intent:retry:)` — called by every mutation's `catch`:
1. increments `attempts[key]`;
2. updates the existing row (reason, timestamp, attempt count, intent) or appends a new one;
3. fires **exactly one** `.directError` haptic *only* if the user explicitly retried this key within
   the last **30 000 ms**, and inside a `retryAll()` batch only for the first failure in the batch;
4. persists to `UserDefaults` under `previously.sync.failedChanges`.

`retry(id)` removes the row immediately (the write is optimistic again), stamps `userRetriedAt[key]`,
runs the effective retry, then drops the stamp. `retryAll()` does the same for every runnable row
under a single batch token so *"one Retry press is one transaction: the whole batch earns at most one
`.directError`, however many of its writes fail again."*

A row whose retry cannot be run (restored from a previous launch, with no `replay` installed) is
**never cleared as if it had succeeded**: *"Clearing it would delete the record, persist an empty
list and let `syncedLine()` report 'Everything synced' for a write that was never sent."*

`WriteIntent` — the four writes the app makes, encodable so a restored row can retry itself:
`progress(franchiseId, mediaId, episodes)`, `status(franchiseId, status)`,
`subscribe(franchiseId, title, status)`, `unsubscribe(franchiseId, title)`.

`teardown()` (sign-out) clears failures, stamps, attempt counters, the batch token, stops path
monitoring, drops `replay`, resets `SeasonSweepLedger` and persists the empty list. `signals` is
deliberately kept — it is wiring, and it captures the model weakly.

### 5.5 The write policy the banner exists to serve

From `CLAUDE.md`, and it is the reason there is no red "couldn't save" toast for progress:

* **A progress mark never rolls back.** A failure goes to `SyncCenter.record` and the banner.
* **Membership and status writes do roll back**, then record.
* Every progress write goes through `AppModel.sendProgress`: one PUT in flight per part, the newest
  target queues behind it, superseded targets are dropped — *"the server always ends on the user's
  last word."*

### 5.6 Profile's variant (the same data, a different anatomy)

* `profileIsOpen` suppresses the global banner while Profile is on screen.
* Calm state = a **footnote line**, not a plate: `"Up to date · Checked just now"` in `caption` /
  `textTertiary`, with a 10-pt semibold glyph or a mini `ProgressView` while checking.
* Failing state = a `GroupedList(header: "Sync")` whose first row is a heading carrying "Retry all"
  (only when `canRetryAny && failedChanges.count > 1`), then one row per failure in four slots:
  **WHAT** (show title `rowTitle` ≤ 2 lines, + `Formatting.fmtTime(change.at)` in its own trailing
  slot, monospaced digits, `layoutPriority(1)`), **WHICH CHANGE** (`change.command`, `rowMeta`,
  `textSecondary`), **WHY** (`failureReason`, `metadata`, `textTertiary`), then the action row.
* Action row: `Retry` as a `CompactActionButtonStyle` bordered control and `Discard change` as a
  **destructive inline link** — *"Shape, not only colour, tells these two apart… Two identically-shaped
  capsules differing only in ink is the pattern that makes a destructive action a mis-tap."* Spaced
  20 pt apart; at AX they stack (`VStack(alignment: .trailing, spacing: 8)`).
* Discard alert message names the change: `"“{title} · {command}”. It stays on this device and is
  never saved to your account."`
* `syncTitle` precedence — **offline is tested before checking**: failures → `"{n} changes couldn’t
  sync"`; `!isOnline` → "You’re offline"; `checking` → "Checking for changes"; else the synced stamp.
  *"The shipped order tested `checking` first, so a device whose NWPathMonitor had already reported
  no path still watched 'Checking for changes' spin until the request timed out."*

---

## 6. The toast layer — `ToastHost`, `ToastView`, `UndoToast`, `ErrorToast`

### 6.1 `ToastHost` — the stack

```swift
VStack(spacing: 9) {
    if !sync.failedChanges.isEmpty, !sync.profileIsOpen {
        SyncBanner(count: sync.failedChanges.count,
                   retry: sync.canRetryAny ? { sync.retryAll() } : nil).frame(maxWidth: 420)
    }
    if let message = appModel.errorToast { ErrorToast(message: message) }        // maxWidth 420
    if let notice  = appModel.notice     { ToastView(message: notice).frame(maxWidth: 420) }
    if let undo    = appModel.undo       { UndoToast(state: undo) { appModel.undoTapped(undo) } }
}
```
Order is fixed: sync banner (top), error toast, neutral notice, undo toast (bottom, nearest the
thumb). All four can be on screen simultaneously.

Animations, each `pick`ed against Reduce Motion, all `uiSnappy`, keyed on
`sync.failedChanges.count`, `appModel.undo?.id`, `appModel.errorToast`, `appModel.notice`.
*"`pick`, so a toast does not still spring in with a 4-pt rise under Reduce Motion — the three
shipped calls were raw `uiSnappy`."*

**The host is always mounted with `if let` children**, never conditionally mounted itself: *"Keeping
the host always mounted also means the insert/remove transitions actually animate — the animation
lives on this container, not the transient child."*

It is mounted **twice** — in `MainTabView` and in the detail sheet — because a sheet presents above
the tab view's ZStack; whichever is frontmost shows the same state, and a toast survives the sheet
dismissing.

Placement in `RootView`'s root ZStack:
```swift
ToastHost().padding(.horizontal, 22).padding(.bottom, ThemeMetrics.toastClearance /* 62 */)
```
22 pt is the tab bar's own horizontal margin (the shipped 17 disagreed with it by 5 pt). The bottom
inset is measured from the **window**, not the bar: at 12 pt the toast landed at 858–935 against a
tab pill at 873–935 and covered the tab bar outright — on Search it covered the field with the user's
own query in it. Measured after the fix: 815–856 pt against a pill whose top edge is 875, on all four
tabs.

VoiceOver: `onChange` of each of the three model values posts an `Announce.status` (see §1).
*"A VoiceOver user was never told the toast existed, let alone that Undo was available for the next
six (or ten) seconds."*

### 6.2 `ToastView` — the capsule

**Why a capsule**: *"The shipped shape — a full-width rounded rectangle with a 1-px perimeter stroke
and a trailing amber 'Undo' — is an Android Material snackbar in shape, position and construction,
and it put a second amber object beside the amber CTA it had just been used to confirm. A capsule
that hugs its own text is the iOS grammar (the AirPods / silent-switch HUDs, the Photos 'Copied'
pill)."* **A port must not regress to a Material Snackbar.**

| Element | Spec |
|---|---|
| Layout | `HStack(spacing: 12)` |
| Failure glyph | only when `failure`: `exclamationmark.triangle.fill`, `system(size: 13, weight: .semibold)`, `warning` (#FFD60A) |
| Message | `metadataEmphasis`, `textPrimary`, `lineLimit(2)`, leading alignment |
| Action | `Button(actionLabel)` with `ToastActionStyle`: `metadataEmphasis`, **`textPrimary` — never accent**, horizontal padding 16, `minHeight 44`, `contentShape(Capsule())`, pressed opacity 0.55 on `uiPress` |
| Padding | leading 16; trailing 16 with no action, **4** with one |
| Frame | `minHeight 48`, `fixedSize(vertical)`, `maxWidth 420` |
| Ground | `chromeGlass(in: Capsule())` + `.shadow(.floating)` |
| Transition | `.toast(reduceMotion:)` — in: opacity + 4-pt rise on `uiSnappy`; out: opacity on `uiDismiss` |

*"Not accent: the mark this toast is confirming was committed by an amber control, and a second amber
word 6 pt away competes with it. Weight carries the action."*

`chromeGlass(in:)` = native Liquid Glass on iOS 26+, `.ultraThinMaterial` below; under **Reduce
Transparency** it is `surfaceFloating` fill + a 1-pt `strokeStrong` stroke, with no refraction.

`ErrorToast(message:)` = `ToastView(message:, failure: true)`.
`UndoToast(state:onUndo:)` = `ToastView(message: state.message, actionLabel: "Undo", action: onUndo)`.

### 6.3 `UndoState` and its message derivation

```swift
struct UndoState: Identifiable {          // Equatable by `id` only
    let id = UUID()
    let mediaId: Int?; let franchiseId: String?
    let prevProgress: Int                 // what Undo restores
    let title: String; let episode: Int
    var added = false;  var statusLabel: String? = nil
    var removed = false; var removedFranchise: Franchise? = nil
    var prevStatus: WatchStatus = .watching
    var count: Int = 1                    // episodes covered by a batch mark
    var customMessage: String? = nil
    var undoAction: (() -> Void)? = nil   // runs instead of performUndo
}
```

`message` is derived in this exact precedence:

| # | Condition | String |
|---|---|---|
| 1 | `customMessage != nil` | that string |
| 2 | `removed` | **Removed from Library. Watch history kept.** |
| 3 | `added` | **Added {title} to {statusLabel ?? "Library"}** |
| 4 | `count > 1` | `Copy.Toast.batchMarked(title:_:)` → `"{title} · {n}\u{00A0}episodes watched"`; empty title → `"{n}\u{00A0}episodes marked as watched"` |
| 5 | otherwise | `Copy.Toast.marked(title:episode:)` → `"{title} · Episode {n} watched"`; empty title → `"Episode {n} marked as watched"` |

The middot is U+00B7 with spaces around it. The subject-carrying forms exist because *"the same
toast fires from Today, a Schedule row and a Library context menu, and 'Episode 2 marked as watched'
cannot say which show it means."* The title is the part allowed to truncate (`lineLimit(2)` on the
whole message); the fact never is.

Other `customMessage` strings in use: `Copy.Toast.movedTo(status)` → `"Moved to Watching"`;
`Copy.Toast.removed` for the pending-add remove on Search.

### 6.4 Lifetimes and queueing

| Toast | Lifetime | Owner |
|---|---|---|
| Undo | **6 s**, **10 s while VoiceOver runs** | `AppModel.scheduleUndoDismissal()` → `undoTask` |
| Error | **4 s**, **8 s while VoiceOver runs** | `AppModel.showError` → `errorTask` |
| Neutral notice | **2.5 s**, fixed | `AppModel.showNotice` → `noticeTask` |
| Sync banner | **no lifetime** — persists until retried or discarded | `SyncCenter` |

There is **no queue**. Each channel holds at most one value and a new one replaces the old: the
timer task is cancelled and restarted, and because `UndoState` is `Equatable` by `id` the host's
`onChange(of: undo?.id)` re-announces. *"An Undo the user cannot reach in time is not an Undo"* is
the whole reason for the VoiceOver extensions.

`teardown()` (sign-out) cancels `undoTask` and `noticeTask` and nils `undo`, `errorToast`, `notice`.

Special coalescing rule in `markCaughtUp`: if an undo for the *same franchise* is already pending and
it is not an "added" one, the new `UndoState` **keeps the original `prevProgress`** and recomputes
`count = max(1, aired − originalPrev)`. *"`count` … was left at its default of 1, so catching up six
episodes confirmed 'Episode 12 marked as watched' — the app under-reporting its own write by five, on
the one control whose whole purpose is a batch."*

`addToLibrary`'s failure path removes its own toast if it is still up
(`if let cur = undo, cur.added, cur.franchiseId == franchiseId { undo = nil }`), and `setStatus`'s
failure path does the same for its `customMessage` toast.

### 6.5 "Present when the handoff settles"

A **single mark on a card that hands over to its successor** does not present its toast immediately;
it presents it when the outgoing card has left. Today's hero is the reference implementation:

```
tap Mark
 ├─ AppModel.markNext(...)                       // optimistic write + one .commitLight
 ├─ withAnimation(pick(uiMicro)) { committedEpisode = undo.episode }   // capsule flips to "Episode N watched"
 ├─ Announce.status("Episode N watched")
 ├─ clearRecapStrip()
 └─ Task: sleep 650 ms
      └─ withAnimation(pick(uiSettle)) { pinned = nil; committedEpisode = nil }
           completion:
             ├─ presentUndo(pendingUndo)          // ← the toast lands HERE
             └─ Task: sleep 300 ms (0 under Reduce Motion) → handoffInFlight = false
```
The incoming card's insertion is delayed by `AnyTransition.handoff` (0.08 s) and then runs
`uiSettle`; it is **not tappable until it has actually arrived** (`handoffInFlight`).

Surfaces **without** a handoff present immediately: Today's queue rows (*"Unlike the hero there is no
card handing over here, so the toast is presented immediately rather than deferred"*), Schedule's
airing cards, Detail's episode rows, Library's context menu, and `removeWithUndo` (*"unlike a mark, a
removal has no handoff to wait for"*).

Queue-row marks also carry a 650-ms `committedQueue` membership so the row draws its committed state
for the same beat, then reverts.

### 6.6 What Undo actually does

`AppModel.undoTapped(_ state:)` — **takes the state by value** so a toast still on screen stays
actionable even if `self.undo` has already moved on:

| Branch | Behaviour |
|---|---|
| `state.undoAction != nil` | `undo = nil`, fire `.selection`, run the closure (status revert, season-reset restore, batch revert…) |
| `state.removed` | `restoreRemoved` — fire `.selection`, `undo = nil`, re-insert the snapshot into `library` inside `pick(uiSnappy)`, then `subscribe(status: prevStatus)`; on failure roll the row back out on `pick(uiGentle)` and record the failure with a retry that re-runs `undoTapped(state)` |
| otherwise | `performUndo()` — fire `.selection`; an `added` state calls `removeFromLibrary(haptic: false)`; a progress state re-applies `prevProgress` locally, drops the franchise from `justCaught`, and re-issues the write through `sendProgress(command: "Undo")` so it rides the same per-part lane; then `undo = nil` and `undoTask.cancel()` |

*"An undo is a progress write like any other: it rides the part's lane behind the mark it reverses, so
the server can never end on the mark after the user took it back."*

`removeWithUndo(_:reduceMotion:)` is the canonical remove: no confirmation dialog — *"remove is
reversible for 6 s (10 s under VoiceOver) and never touches watch history — the server deletes only
the subscription row, so every progress row survives and Undo brings the ticks back exactly."* One
haptic for the whole transaction (`.commitLight`, fired inside `removeFromLibrary`), the row leaves
inside `pick(uiSettle)`.

---

## 7. Skeletons

### 7.1 The philosophy, and what is refused

*"A skeleton is the shape of the content that is coming."* **Shimmer is refused by name** — *"a
travelling highlight is decoration pretending to be progress."* What replaces it is a breath:

```swift
private let skeletonBreath = Animation.easeInOut(duration: 1.4).repeatForever(autoreverses: true)
// opacity 0.88 ↔ 1.0, or a static 0.92 under Reduce Motion
```
The amplitude is deliberate: *"0.88 ↔ 1.0, not 0.65 ↔ 1.0. A 35 % oscillation across the WHOLE
screen, forever, is not a reassurance that something is working — it is a pulse the eye cannot ignore
and cannot look away from, on the frame the user is already waiting through. 12 % still visibly
breathes."*

### 7.2 `SkeletonGate` — the whole loading rule, in one place

```swift
SkeletonGate(isLoading: Bool) { skeleton } content: { content }
```

Rules, and they live **only** here:

* nothing at all for the first **240 ms** — a fast response must never flash a skeleton;
* once shown, the skeleton stays at least **320 ms** even if data lands at 250 ms;
* it swaps to content with a **120-ms crossfade** (`uiCrossfade` = `uiReduced` = easeOut 0.12);
* the frame never blanks between them.

State machine (`.task(id: isLoading)`):

```
isLoading becomes true:
    if already visible → return
    sleep 240 ms;  if cancelled or no longer loading → return
    shownAt = ContinuousClock.now;  visible = true
    sleep 800 ms;  if cancelled or no longer loading → return
    withAnimation(pick(uiGentle)) { slow = true }

isLoading becomes false:
    slow = false
    if !visible → return
    remaining = 320 ms − (now − shownAt)
    if remaining > 0 → sleep remaining
    if cancelled → return
    visible = false;  shownAt = nil
```
`shownAt` is a **monotonic** `ContinuousClock.Instant`, never a wall clock: *"a wall-clock stamp
could be moved by the system mid-window and compute a negative or absurd remainder."* Android: use
`SystemClock.elapsedRealtime()` / `TimeSource.Monotonic`, never `System.currentTimeMillis()`.

Body:
```swift
ZStack(alignment: .top) {
    if visible      { skeleton().opacity(reduceMotion ? 0.92 : (breathing ? 1.0 : 0.88))
                                .animation(reduceMotion ? nil : skeletonBreath, value: breathing)
                                .onAppear { breathing = true }
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel("Loading") }
    else if isLoading { Color.clear.frame(height: 0) }   // the first 240 ms: deliberately empty
    else            { content() }
}
.animation(uiCrossfade, value: visible)
.animation(uiCrossfade, value: isLoading)
```

Two things a porter must know:

1. **The content is laid out in a `ZStack`.** Two sibling views handed to `content:` are drawn on top
   of each other — this actually shipped as "30 titles" printed across the first row of All titles.
   Wrap the content in one view.
2. **`slow` is set after 800 ms but nothing renders it.** The file's header comment promises "a small
   `ProgressView` once the wait passes 800 ms"; the body never draws one. Port the timing hook if you
   want the behaviour, but do not assume the iOS build shows a spinner there — it does not.

`isLoading` means *"there is nothing to show yet"*. A refresh over content the user can already see is
**not** this — that is `RefreshIndicator` plus the content itself.

### 7.3 The atoms

| Atom | Parameters (defaults) | Renders |
|---|---|---|
| `SkeletonBlock` | `width: CGFloat? = nil`, `height: CGFloat? = 12`, `radius = 6` | rounded rect (`.continuous`) filled `ThemeColor.skeleton`. `height: nil` takes the proposed height (used with `.aspectRatio(16/9)`) |
| `SkeletonPoster` | `width`, `height`, `radius = ThemeRadius.poster (10)` | a `SkeletonBlock` |
| `SkeletonLine` | `width: CGFloat? = nil`, `height = 12`, radius 6 | a `SkeletonBlock` |
| `SkeletonRow` | `poster: CGSize`, `lines: [CGFloat]`, `posterRadius = 6`, `spacing = 12`, `height = ThemeMetrics.rowStandard (88)` | `HStack(spacing:)` of poster (omitted when `poster.width == 0`) + `VStack(alignment: .leading, spacing: 8)` of lines — **first line 13 pt tall, every later line 10 pt** — + `Spacer(minLength: 0)`; `frame(minHeight: height)` where height is a `@ScaledMetric(relativeTo: .body)` so the row grows with Dynamic Type |
| `SkeletonCard` | `height = 168`, `radius = ThemeRadius.card (22)`, content builder | `VStack(alignment: .leading, spacing: 16)` of content, padding 16, `frame(maxWidth: .infinity, minHeight: height, alignment: .topLeading)`, `.surface(.plate, radius:)` |
| `SkeletonShelf` | `count = 5`, `size = PosterSize.shelfLarge (124×186)`, `caption = false`, `titleLines = 2` | `HStack(alignment: .top, spacing: 12)` of `count` columns; each is a poster then `VStack(spacing: 4)` of title lines (last line `0.62 × width`, the rest full width, height = `@ScaledMetric(relativeTo: .subheadline) 13`) and, when `caption`, one line at `0.45 × width`, height `@ScaledMetric(relativeTo: .caption) 11`; the caption block is `frame(width: size.width, alignment: .leading)`; outer column spacing 8 |

Two hard-won defaults:

* **Skeletons do not scale with Dynamic Type** — they are structure, not text — *except*
  `SkeletonRow`'s height and `SkeletonShelf`'s line heights, which do, so the swap to real content
  does not jump at accessibility sizes.
* `SkeletonShelf.titleLines` **must match what the destination `ShelfCard` reserves**, and `count`
  defaults to 5 rather than 3: *"the skeleton put 'WATCHING' at 493 pt and the real content at
  537 pt … so everything below moved 44 pt at the swap, and because `SkeletonGate` crossfades in a
  `ZStack` you saw both misaligned lists superimposed for 120 ms"*; *"the real shelf runs off the
  trailing edge, and a skeleton that stops short of it promises a shorter shelf than the one that
  arrives."*

The six per-screen default compositions that used to live in the design system were **deleted**: every
screen composes its own stand-in from the atoms, and the atoms + `SkeletonGate` are the contract.

### 7.4 Every per-screen skeleton, exactly

**Today** (`TodayView.skeleton(screenH:topInset:)`) — the shape the billboard hero will fill:

1. Hero band, `frame(height: heroHeight(screenH), alignment: .bottom)`, content bottom-aligned:
   `Spacer(minLength: 0)`, then `SkeletonLine(96 × 12)`, `SkeletonLine(250 × 28)` at top 14,
   `SkeletonLine(160 × 14)` at top 12, `SkeletonBlock(height: 48, radius: 24)` at top 18 (the mark
   capsule). Horizontal gutter 16; bottom padding 20 at AX, else 16.
   * Ground: `TodayView.rememberedTint ?? ThemeColor.ambientBackdropFallback (#432D21)`, over which a
     `LinearGradient(white 5 % → clear, top → center)` gives it the tone of a photograph under a
     scrim. **Not** a grey plate: *"the status area read as BLACK for the whole first load and then
     'became flush' when the art landed."*
   * Bottom hand-over mask (long, like `ArtScrim`): black 0 → black 0.52 → 0.72 @ 0.74 → 0.26 @ 0.90
     → 0 @ 1.0. *"The old mask held solid to 0.86 and then dropped inside 14 %, which at 440 pt is a
     60-pt cliff — measured as a hard seam."*
   * `.padding(.top, -topInset)` so it bleeds under the status bar.
2. Queue block: `VStack(spacing: labelGap 10)` — `SkeletonLine(62 × 10)` then 2 ×
   `SkeletonRow(poster: (.todayQueue 52×78, or .row 60×90 at AX), lines: [180, 110],
   posterRadius: slot.radius)`. Gutter 16; top padding `heroClearance 26` at AX, else 20.
3. Shelf block: `SkeletonLine(84 × 10)` then a **horizontal, scroll-disabled** `ScrollView`
   containing `SkeletonShelf(count: 4, size: .todayShelf 100×150, caption: true)`.
   The scroller is mandatory: *"Four 100-pt cards plus gaps are 468 pt wide — wider than the screen.
   In a plain stack that oversized child sets the ideal width of everything above it, and the WHOLE
   screen (wordmark and avatar included) gets centred 14 pt to the left with the avatar hanging off
   the edge."* Top padding `sectionGap 30`.
4. Whole thing labelled `"Loading"`.

**Library root**: `VStack(spacing: sectionGap 30)`, top padding 20.
* Block 1 (`spacing 12`): `SkeletonLine(108 × 19)` gutter-padded; then `HStack(alignment: .top,
  spacing: shelfGap 12)` of 2 columns — `SkeletonPoster(286 × 161, radius: card 22)`,
  `SkeletonLine(154 × 18)`, `SkeletonLine(196 × 0.6 = 117.6, height 12)`; gutter-padded, `.clipped()`.
* Block 2 (`spacing 12`): `HStack { SkeletonLine(92 × 19); Spacer; SkeletonLine(54 × 12) }`, then
  `HStack(spacing 12)` of 2 columns — `SkeletonPoster(174 × BannerCard.height 104, radius 22)`,
  `SkeletonLine(174 × 0.72 = 125.3, height 14)`, `SkeletonLine(174 × 0.55 = 95.7, height 12)`.

**Library All-titles**: 8 × `SkeletonRow(poster: .row 60×90, lines: [196, 108], posterRadius: 10,
spacing: artGap 14)` in a `VStack(spacing: 0)`, gutter 16, top padding 4.

**Schedule feed**: 3 repetitions of — `SkeletonLine(116 × 11)` (top `sectionGap 30`, bottom
`labelGap 10`), `SkeletonBlock(height: nil, radius: card 22).aspectRatio(16/9, .fit)`,
`SkeletonLine(212 × 13)` (top 8), `SkeletonLine(96 × 10)` (top 4). Gutter 16, `accessibilityHidden`.
It drew poster rows until 3 Sep — *"the row the calendar stopped using"* — and now mirrors the airing
card's anatomy so the swap lands in place.

**Detail**: `VStack(spacing: sectionGap 30)`, gutter 16, `ignoresSafeArea(.top)`.
* Hero: `ZStack(alignment: .bottomLeading)` filled with `tint ?? TodayView.rememberedTint ??
  ambientBackdropFallback`, carrying `VStack(spacing: 8)` of `SkeletonLine(250 × 26)` and
  `SkeletonLine(176 × 13)` at gutter 16 / bottom 16; `frame(height: heroHeight)`, negative gutter
  padding so it bleeds full width.
* `SkeletonCard(height: 190) {}` — the next-up card's shape.
* `VStack(spacing: 8)`: `SkeletonLine(height: 12)` ×2 full width + `SkeletonLine(210 × 12)` — the
  synopsis.
* 3 × `SkeletonRow(poster: .row, lines: [150, 104], posterRadius: 10, spacing: 14)`.

**Season episodes**: `SkeletonBlock(height: nil, radius: 22).aspectRatio(16/9)` at top 12, then
`SkeletonLine(120 × 20)` (top 12 / bottom 12), then 8 × `SkeletonRow(poster: EpisodeArtwork.slot
120×68, lines: [190, 120], posterRadius: episodeStill 8, spacing: 14, height: rowEpisode 82)`.
Gutter 16, top padding 8.

**Search results**: 5 × `SkeletonRow(poster: .row 60×90, lines: [188, 126], posterRadius: 10,
spacing: 14, height: rowMedia 100)`, gutter 16, top padding 12. The gate condition is
`searchBusy && results.isEmpty && !scopedOut(results) && !searchError`.

A refining query (results already on screen, a new request in flight) does **not** show a skeleton:
the existing list dims as a group to `Metrics.groupDim` on `pick(uiGentle)` — *"a list that is about
to change never looks settled."*

---

## 8. `FranchiseContextMenu` — long-press quick actions

*"The same actions as the detail screen, one press away. Every item here also exists in Detail, so
long-press is a shortcut, never the only route."*

```swift
extension View {
    @ViewBuilder
    func franchiseQuickActions(_ f: Franchise?, appModel: AppModel) -> some View {
        if let f { contextMenu { FranchiseContextMenu(f: f, appModel: appModel) } } else { self }
    }
}
```
**Passing `nil` gives the surface no menu at all** — an unowned search result has nothing to act on.

Menu contents, in order:

| # | Condition | Label | Symbol | Action |
|---|---|---|---|---|
| 1 | `f.releasingPart != nil && part.episodesBehind > 0` | `Copy.Action.markAll(n)` → **"Mark all {n} episodes as watched"** | `text.append` | `appModel.markCaughtUp(f.id)` |
| 2–6 | always, in `WatchStatus.menuOrder` | the status's `displayName` | `checkmark` when it is the current `effectiveStatus`, else the status glyph | `appModel.setStatus(franchiseId:status:)` |
| — | | `Divider()` | | |
| 7 | always | **"Remove from Library"** (`role: .destructive`) | `trash` | `appModel.removeWithUndo(f, reduceMotion:)` |

`WatchStatus.menuOrder` = `[.watching, .planned, .completed, .paused, .dropped]` — *"board 09's
order — the order a viewer moves through them"* — which is **not** the enum's declaration order.

| Status | Label (`Copy.Status`) | Unselected glyph |
|---|---|---|
| `watching` | Watching | `play.circle` |
| `planned` | Planned | `clock` |
| `completed` | **Watched** | `checkmark.circle` |
| `paused` | Paused | `pause.circle` |
| `dropped` | Dropped | `xmark.circle` |

The selected row's glyph is **always `checkmark`** — the status word plus a tick, never a second
colour. "Completed" and "Plan to watch" never appear; "Finished" is not in the vocabulary at all
(*"it was carrying both meanings at once, which is how the app came to file a show as finished on
one screen and promise it returns in six weeks on the next"*).

`episodesBehind` = `isReleasing ? max(0, airedEpisodes − progress) : 0`.
`effectiveStatus` = `status ?? subscription?.status ?? .planned`.
`releasingPart` = the releasing part with the soonest `nextAiringAt`, else the most recently aired.

**Haptics: none are fired by the menu itself.** *"markCaughtUp, setStatus and removeWithUndo each fire
their own"* — `.success`/`.commitMedium`, `.selection`, `.commitLight` respectively. This is the
"one haptic per transaction" rule enforced structurally.

`RemoveFromLibraryButton` is extracted as its own view *"so every host adds remove in one line and no
host can reintroduce a confirmation dialog or a second haptic."* Detail's overflow menu mounts it
directly.

Hosts of `franchiseQuickActions`: Today (queue rows, shelf cards, upcoming rows, the hero block),
Schedule airing cards, Library rows and cards (root + All titles), Search rows and tiles (only when
`appModel.franchise(id:)` resolves — i.e. the show is in the loaded library).

Search's add control has one extra branch: an item that is **owned but still pending** (added
seconds ago, not yet in `library`, so there is no `Franchise` for `removeWithUndo`) gets a single
destructive "Remove from Library" that calls `removeFromLibrary` and hand-builds the receipt —
*"same toast, same six seconds, same Undo"* — with `customMessage: Copy.Toast.removed` and an
`undoAction` that re-adds.

**Android**: Compose has no first-class long-press context menu with the iOS preview-and-menu
presentation. `combinedClickable(onLongClick =)` + a `DropdownMenu` anchored to the row is the
straightforward port; the iOS platter's blurred backdrop and the row lifting out of the list are
**not** reproducible without a custom overlay. Moderate.

---

## 9. The rest of `Primitives+States.swift` (same file, adjacent responsibilities)

These are not "state surfaces" but they ship in the same file and no other spec owns them.

### 9.1 `EpisodeArtwork` / `EpisodeGlyphTile`

* Slot: **120 × 68** (16:9), radius `episodeStill` 8, 1-pt `posterEdge` border, `accessibilityHidden`.
  It was 96×54 — *"a postage stamp beside 17-pt type; Netflix's episode thumbnails run ~130 pt wide."*
* With a still (`spoilerSafe && url non-empty`): rounded rect filled with the resolved palette tint
  (else `surfaceRaised`), a centred `photo` symbol (16 pt, `textTertiary`) **under** the image so a
  fetch that never resolves is not a bare rectangle, then `RemoteImageView(contentMode: .fill,
  maxPixel: 288)`. Tint change animates on `pick(uiPoster)`.
* Without one: `EpisodeGlyphTile` — the **same rectangle**, filled with the show's palette colour
  (`showTint`), a `LinearGradient(black 10 % → black 34 %, top → bottom)` so it never competes with a
  neighbour that has real art, and a `play.rectangle` glyph at 17 pt in `textPrimary` @ 34 %.
* **A spoiler-protected still is replaced, never blurred** — *"a blur is a tease with no VoiceOver
  equivalent."* The episode number is drawn exactly once, in the row's text.

### 9.2 `PassiveTick`

A completed thing. `checkmark`, `system(size: 14, weight: .semibold)`, `textTertiary`; `boxed: true`
puts it in a 44 × 44 frame so a row's trailing edge lines up with a real control. Its accessibility
value is `"Complete"` with `.isStaticText`. **Never a button, never accent.** A bare check, not
`checkmark.circle.fill`: *"a 18-pt grey blob — read as a disabled control rather than as a settled
fact."*

### 9.3 `ProgressText`

`Text` with `metadataEmphasis` (when `emphasis`) or `metadata`, tint defaulting to `textSecondary`,
`fixedSize(vertical)`, `.isStaticText`. Passive: it reports, it never invites a tap.

### 9.4 `QueryProgressBar`

The 1-pt bar under the search field while a query is in flight — **the one sanctioned repeating
animation outside `ThemeMotion`**, and it runs only while a real request is running.

* Track: `frame(height: 1)`, background `accent` @ 14 % while active, animated on `pick(uiGentle)`.
* Segment: `Rectangle().fill(accent)`, width `0.28 × track`, offset from `−0.28 w` to `1.0 w` on
  `Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: false)`. `.clipped()` is required —
  *"without this it paints over the 16-pt gutters and whatever sits beside the field."*
* **Reduce Motion**: a static `accent` @ 30 % fill, no travel.
* Accessibility: the bar is `accessibilityHidden`, but a 1×1 clear leading overlay carries the label
  `"Loading"` with `.updatesFrequently` — *"a 1-pt bar is meaningless to VoiceOver, while 'a request
  is running' is exactly what a VoiceOver user needs and had no way to observe."*

### 9.5 `SectionHeaderRow` + `SectionHeaderPressStyle`

THE section header — one family, app-wide.

* `HStack(alignment: .firstTextBaseline, spacing: 8)`.
* Title: optional 5-pt `accent` dot (means "newly changed" **only**), then the text in `sectionTitle`
  (Outfit SemiBold 20, mixed case), `textPrimary`, `lineLimit(1)`, `minimumScaleFactor(0.85)`.
* Count: `metadata`, `textTertiary`, `monospacedDigit()`, on the title's baseline.
* Navigating header (`action != nil && !inlineAction`): the **whole title is the button**, with a
  trailing `chevron.forward` at `system(size: 14, weight: .semibold)` in `textTertiary`. There is no
  "See all" word — the Apple TV / Netflix shelf grammar. Accessibility label
  `"{text}, {actionLabel ?? "See all"}"`, trait `.isHeader`.
* `inlineAction: true` keeps a trailing text link for a command on the section ("Clear"), rendered
  with `InlineLinkButtonStyle` and `.padding(.vertical, -12)`.
* `SectionHeaderPressStyle`: `padding(.vertical, 10)`, `frame(minHeight: 44)`,
  `contentShape(Rectangle())`, pressed opacity 0.55 on `pick(uiPress)`. The row then pulls the button
  back with `.padding(.vertical, -10)` so the header's **layout** height stays the title's own.
* `.zIndex(1)` on the row is load-bearing: *"the negative padding leaves the button DRAWING and
  HIT-TESTING above and below the row's layout rect. Siblings laid out after the header would
  otherwise win the taps in the lower overlap band whenever the stack's spacing is under 10 pt,
  quietly eating the bottom quarter of a 44-pt target."*

### 9.6 `CompactActionButtonStyle`

The canonical subordinate row control: `metadataEmphasis`, `textPrimary`, horizontal padding 14,
`minHeight 44`, ground `surfaceFloating` (`surfacePressed` when pressed) at radius
`compactControl` 12, 1-pt `stroke` border, disabled opacity 0.38, press 0.985 / opacity 0.72 under
Reduce Motion.

### 9.7 Watch-history rail

`HistoryRail` is a `VStack(alignment: .leading, spacing: HistoryRailMetrics.rowGap)`.

| Metric | Value |
|---|---|
| `railX` (x-centre of the 1-pt rail from the container's leading edge) | 4 |
| `cardX` (card's leading edge) | 22 |
| `node` (diameter) | 8 |
| `rowGap` | 10 |
| `minRowHeight` | 68 |

`HistorySessionRow(title:subtitle:poster:active:position:isNew:action:)`, `position ∈ {only, first,
middle, last}`, rows ordered **newest first**.

* The rail is drawn as a **background** of the card, not a ZStack sibling — *"a GeometryReader beside
  the card would claim the whole proposed height and stretch every row."* Upward segment (skipped for
  `.first`/`.only`): 1 × `h/2` at `railX − 0.5`. Downward segment (skipped for `.last`/`.only`):
  1 × `(h − h/2 + rowGap) × segment` offset to `y = h/2` — it overshoots by the row gap so the line
  stays continuous between cards. Both `strokeStrong`. `allowsHitTesting(false)`,
  `accessibilityHidden`.
* Node: 8-pt circle, `accent` when active (with a 16-pt `accentSoft` halo behind it) else
  `surfaceFlat` with a 1.5-pt `textTertiary` stroke; scaled by `nodeScale`.
* Card: `Button` with `RowPressStyle`, `HStack(spacing: 12)` — optional `PosterSlot(.queue 44×66)`,
  `VStack(spacing: 2)` of title (`body`, `textPrimary`) and subtitle (`metadata`, `textSecondary`),
  `Spacer(minLength: 8)`, `chevron.forward` 13 semibold `textTertiary`; padding vertical 12 /
  horizontal 14, `minHeight 68`, `.surface(.raised, radius: row 16)`; when active, an extra
  `accent @ 45 %` 1-pt border — *"here the colour IS the state, and the ring is the only thing
  separating this card from its identical neighbours."*
  Accessibility: one element, label `"{title}, {subtitle}"`, value `"Active"` when active,
  `.isButton`.
* **New-session choreography** (`isNew`, and only when Reduce Motion is off): `segment` 0 → 1 on
  `uiSweep` (520 ms), and **in that animation's completion** `nodeScale` 0.6 → 1 on `uiMicro`
  (220 ms). *"The two never overlap — the second starts from the first's completion, not a timer."*
  Under Reduce Motion both snap to 1.

Subtitle strings: `Copy.Progress.ordinalWatch(n)` → "First watch" … "Tenth watch", then "11th watch";
`Copy.Progress.inProgress(nextEpisode:)` → `"In progress · Episode 7 next"`;
`Copy.Progress.sessionSpan(...)` → `"Jul 4 – Jul 19 · 26 episodes"`, `"Dates unknown · 26 episodes"`,
or a single end date when there is no start.

### 9.8 Milestones — `seasonCompleteSweep`, `milestone`, `SeasonSweepLedger`

* `seasonCompleteSweep(token:reduceMotion:)`: a 1-pt amber hairline under a card's title, **64 % of
  the title's own width**, offset `y = height + 3`, drawn as a
  `LinearGradient(accent → accent @ 0, leading → trailing)`, over `uiSweep` (520 ms). No scrim, no
  disc, no confetti. It fires **no haptic of its own** — the transaction's single `.success` is the
  confirmation.
* `milestone(token:reduceMotion:)`: one restrained overshoot — `scale` 0.94 → 1 on `uiMilestone` —
  applied to whatever carries the new status. `ThemeMotion.uiMilestone` had **zero call sites** before
  this, so finishing a series flipped the status chip with an instant text swap.
* Both are keyed on a `UUID` identifying the **COMMIT**, not the state, and claimed through
  `SeasonSweepLedger.claim(token)` — a process-wide ledger of the last **32** drawn tokens.
  `@State` could not do this job: *"`@State` dies with the view, and the case this exists for is
  precisely the view being re-created while the milestone is still true"* — a card scrolled off and
  back, a tab switch or a recycled row would replay the whole 520-ms draw for a milestone the user
  already saw. A second claim snaps straight to the finished value.
  `SeasonSweepLedger.reset()` is called from `SyncCenter.teardown()`: *"the next account's first
  season completion is its own."*

### 9.9 `numericFact(_:)`

`contentTransition(.numericText())` animated with `uiNumeric`, allowed on exactly four numbers: the
backlog count after a mark, the library count, a confirmation summary, and the foreground countdown.
*"Nowhere else — constant movement turns state into spectacle."*
**SwiftUI does not disable `.numericText()` under Reduce Motion**, so the check lives in this one
modifier: with Reduce Motion on the digits crossfade (`.opacity`) instead of rolling.

---

## 10. Cross-cutting accessibility contract

| Setting | Behaviour required |
|---|---|
| **Dynamic Type** | `EmptyState` drops its line limits at accessibility sizes and its buttons stop hugging; `InlineNotice` and `SyncBanner` swap H→V layout; `StaleStrip` wraps and its 28-pt minimum grows; `SkeletonRow`/`SkeletonShelf` scale their heights; nothing in this subsystem truncates — the container grows. Every interactive element is ≥ 44 pt at every size. |
| **Reduce Motion** | Every animation goes through `pick` → `uiReduced` (easeOut 0.12). Skeleton breath becomes a static 0.92. Toast in/out collapse to a plain opacity fade. History-rail choreography and both milestone effects are skipped, snapping to the finished value. Presses feed back in **opacity (0.72)**, never scale. `numericFact` crossfades instead of rolling. `QueryProgressBar` becomes a static 30 % fill. Today's hero handoff drops its 300-ms tail. |
| **Reduce Transparency** | `chromeGlass` → `surfaceFloating` fill + 1-pt `strokeStrong` stroke (toast and sync banner). `ScrollEdgeChrome` drops the `.ultraThinMaterial` layer entirely and the top bar veil goes **opaque** (1.0) instead of `chromeBarOpacity` 0.74 — *"a 74 % veil with nothing softening what is under it is the half-lit row under 'Library' that the hardened bar was built to end."* |
| **Differentiate Without Color** | `DifferentiateMark` (a 6-pt `circle.fill`) and `differentiatingUnderline` (a 2-pt capsule) draw **only** when the setting is on, adding a shape carrier to any state encoded in hue alone. *"It is not an accessibility fallback bolted beside the design; it is the second carrier the design should have had."* |
| **VoiceOver** | Undo 6 s → 10 s, error toast 4 s → 8 s. Every settling state announces (§1). Symbols inside states are hidden; the state is one element with the `"{title}. {supporting}"` label. `StaleStrip` speaks the elapsed time spelled out. The banner is `.isSummaryElement`. |

---

## 11. Android portability

| Item | Risk | Note |
|---|---|---|
| SF Symbols (`rectangle.stack`, `tv`, `calendar`, `bookmark`, `wifi.slash`, `wifi.exclamationmark`, `exclamationmark.circle`, `exclamationmark.triangle.fill`, `magnifyingglass`, `clock.arrow.circlepath`, `slider.horizontal.3`, `line.3.horizontal.decrease`, `checkmark.circle.fill`, `arrow.triangle.2.circlepath`, `info.circle`, `text.append`, `play.circle`, `pause.circle`, `xmark.circle`, `checkmark`, `trash`, `photo`, `play.rectangle`, `chevron.forward`) | **moderate** | No equivalent set. Map each to a Material Symbol (rounded, weight 400) hand-checked at 44 pt and 30 pt; several (`text.append`, `rectangle.stack`, `line.3.horizontal.decrease`) need a custom vector. Optical weight must match — these are drawn at `textTertiary` and read as *quiet*. |
| Liquid Glass / `.ultraThinMaterial` on the toast and banner capsule | **hard** | Compose has no live backdrop blur below API 31 and no `RenderEffect`-based capsule blur that matches. Use a `RenderEffect` blur of the captured backdrop on API 31+, and the Reduce-Transparency fallback (`surfaceFloating` + `strokeStrong` stroke) below it. The fallback is already specified, so the degraded path is correct by construction. |
| Toast must not become a Material Snackbar | **moderate** | Material3's `Snackbar` is a full-width rectangle with a coloured action — precisely the shape this design rejected. Build a custom hugging capsule: `wrapContentWidth`, `widthIn(max = 420.dp)`, `heightIn(min = 48.dp)`, `CircleShape`, elevation matching `.floating`. |
| iOS `contextMenu` (long-press platter with the row lifted and blurred backdrop) | **moderate** | `combinedClickable(onLongClick)` + `DropdownMenu` reproduces the actions but not the presentation. |
| `confirmationDialog` (action sheet) for the discard flow | **easy** | `AlertDialog` with a destructive-tinted confirm button; the sheet-vs-dialog difference is idiomatic on each platform. |
| `AccessibilityNotification.Announcement` / `.ScreenChanged` | **moderate** | `announceForAccessibility` (or a `Polite` live region) covers `status`; `screenChanged` needs an announcement plus an explicit focus move. |
| `UIImpactFeedbackGenerator` intensities (0.65 / 0.72 / 0.50) and `UINotificationFeedbackGenerator` success/warning/error | **moderate** | Android has `HapticFeedbackConstants` / `VibrationEffect.Composition` (API 30+: `PRIMITIVE_CLICK` with scale, `PRIMITIVE_THUD`). The *distinctions* matter more than the exact waveform: commit-light ≠ commit-medium ≠ error. Keep the per-token 300 ms / 40 ms throttle and the "one per transaction" rule. |
| `@ScaledMetric(relativeTo:)` for the empty-state glyph and skeleton row heights | **easy** | Multiply by `LocalDensity.current.fontScale`, clamped the way the referenced text style clamps. |
| `ContinuousClock` for the skeleton's minimum-visible window | **easy** | `SystemClock.elapsedRealtime()` / `TimeSource.Monotonic`. **Not** `currentTimeMillis`. |
| `.task(id:)` cancellation semantics driving every timing rule (240/320/400/800 ms, 6 s, 800 ms lockout) | **easy** | `LaunchedEffect(key)` cancels and restarts identically. |
| SwiftUI implicit `.transition` + container-level `.animation(value:)` (the "host is always mounted" trick) | **moderate** | `AnimatedVisibility` with explicit `enter`/`exit` per child; keep the parent stable so exits actually run. |
| Asymmetric transitions (`toast`, `handoff`: different curve in vs out) | **easy** | `AnimatedVisibility(enter = fadeIn(snappySpec) + slideInVertically(4.dp), exit = fadeOut(easeIn160))`. |
| `AnyLayout` H↔V swap at accessibility text sizes | **easy** | Branch on `fontScale` and emit `Row`/`Column`. |
| `Spring(response:dampingFraction:)` tokens | **easy** | Convert: `stiffness ≈ (2π/response)²`, `dampingRatio = dampingFraction`. |
| Negative padding to keep a 44-pt target off a baseline (`InlineNotice` retry, `SectionHeaderRow`) | **moderate** | Compose has no negative padding; use a custom `Layout` or `offset` + `Modifier.touchTarget`, and re-verify the hit rect. |
| `.zIndex(1)` for hit-testing above later siblings (`SectionHeaderRow`) | **moderate** | Compose hit-tests in reverse draw order per node; verify explicitly that the header still wins taps in the overlap band. |
| `NWPathMonitor` (`isOnline` decides offline-vs-server copy) | **easy** | `ConnectivityManager.NetworkCallback` on `NET_CAPABILITY_VALIDATED`. Keep the "never guess from the error" rule. |
| Curly punctuation (U+2019, U+201C/D), non-breaking space U+00A0, word joiner U+2060, middot U+00B7 | **easy** | Preserve exactly; the copy audit rejects straight quotes. |
| Outfit variable/static fonts | **portable** | Ship the five TTFs; `letterSpacing` in `sp`, negated tracking values divided by the font size to get `em`. |
| SF Pro tokens (`metadata`, `metadataEmphasis`, `sectionLabel`, `caption`) | **easy** | Roboto at the same optical sizes; keep `monospacedDigit` → `FontFeature "tnum"`. |
| `.refreshable` + scroll-geometry threshold haptic | **moderate** | Compose `PullToRefreshBox` exposes progress; fire the arm haptic when progress ≥ 1 **while dragging**, re-arm below 0.3. The dragging test is the part most likely to be dropped in a port. |
| Live Activities / Dynamic Island | n/a | Not touched by this subsystem (episode alerts only). |

---

## 12. Porting checklist (the invariants, condensed)

1. One empty-state component; centred; ≤ 300 pt copy column; **one hugging button**; a recovery is
   quiet, a next step is amber.
2. A state whose copy declares a label but has no handler is a build-time failure.
3. Offline vs. server-unreachable is decided by the reachability monitor, never by the error.
4. Cached content always beats a failed refresh; an empty account is never shown while loading.
5. A background refresh failure is an inline footnote with a "Retry" link. Never a dialog, never a
   toast, never a full-screen error over content that loaded.
6. Staleness is 30 min / 6 h / 24 h by data class, and nothing is stale before its first success.
7. The refresh spinner appears only after 400 ms, lives in the bar, and yields to a native pull.
8. A failed write is persistent chrome (the sync banner), not a transient toast; it survives a
   relaunch; it is never cleared as though it succeeded; Retry is optimistic with an 800-ms lockout.
9. Progress marks never roll back; membership and status writes do.
10. Toasts: 6 s undo (10 s VoiceOver), 4 s error (8 s VoiceOver), 2.5 s notice, one per channel, no
    queue, capsule not snackbar, action word in text ink.
11. A mark on a card that hands over presents its Undo **when the handoff settles** (650 ms + the
    settle animation's completion), everywhere else immediately.
12. Skeletons: 240 ms delay, 320 ms floor, 120 ms crossfade, 0.88↔1.0 breath at 1.4 s, **no shimmer**,
    and the skeleton's geometry must be the geometry that arrives.
13. Long-press quick actions duplicate Detail; they never fire a haptic of their own; a title not in
    the library gets no menu.
14. Amber is never the colour of a tappable word.
