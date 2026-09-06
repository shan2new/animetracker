# Today screen and the Previously Recap

> **Revision, 2026-09-04 (ported the same day; the sections below describe the 2–3 Sep tree).**
> The hero is no longer the four-line slate of §6 (pill → headline → show → fact). It is a
> three-row LOCKUP, direction B of three photographed on the simulator: a filled amber
> `HeroBadge` saying the STATE ("NEW EPISODE", "4 EPISODES BEHIND"), the title at `displayXL`
> (scale floor 0.82), then ONE line `moment · fact` ("Today at 7:30 PM · Season 4 · Episode 21"),
> the bar, the capsule. No headline clock, no eyebrow dot, no countdown. `HeroSlate` lost
> `headline`/`eyebrowDot` and gained `moment: String?`; the widget mirrors it (`widget_badge.xml`).
> `HeroCopyScrim` is lighter and longer (lead 132, monotonic stops, full canvas 40 dp above the
> frame's bottom). Under the hero, §11's `Next up` rows and `Upcoming` rows are ONE horizontal
> shelf of 16:9 cards (`UpNextShelf.kt`, the Continue-card geometry) except at accessibility
> sizes; each card wears one "EPISODE N" pill on the art and an amber time / grey count caption.
> Schedule's `AiringCard` keeps its 3 Sep anatomy (time pill, "Season 4 · Episode 21" caption).
> `WideArt.ultraWide` is decided by the URL and makes `LandscapeArt` decode an AniList banner at
> its native 1900 px; the crop itself stays. Source of truth: `ios/Sources/Features/Today/
> TodayView.swift` (`HeroFocus`, `upNextShelf`, `upNextCard`, `upNextCaption`), `Primitives.swift`
> (`HeroBadge`, `HeroCopyScrim`, `ProgressBanner`, `LandscapeArt`) and CLAUDE.md's cohesion bullet.

`Today` is the flagship surface of *Previously.* — the tab the app opens on, and the only screen in
the product whose job is urgency ("here is the thing to watch right now"). Its top ~72 % is a
full-bleed **billboard hero** (`ArtHeader` over the show's own artwork) carrying a four-line
**slate** read in a TV-listing's order — pill → headline → show → fact — plus at most one action;
under it sits a **focus stack** (a two-row `Next up` queue), an `Upcoming` block of not-yet-aired
episodes, and a `Watching` poster shelf. On arrival after an absence the hero frame is instead
occupied by the **Previously Recap** — a full-height digest of what changed while you were away —
which then *shrinks* into the hero in a single move and leaves a one-line strip behind. Four
top-level states share the same frame: the hero, the trending billboard (empty account), a calm
caught-up headline, and a whole-screen failure card. Everything on this screen is *derived* from
`AppModel` feeds and `Franchise`/`FranchisePart` model computations; the view owns only timing
state, and — critically — **never** the scroll offset.

Source of truth: `ios/Sources/Features/Today/TodayView.swift` (2223 lines) and
`ios/Sources/Features/Today/RecapDigest.swift` (142 lines). All design tokens quoted below resolve
in `ios/Sources/DesignSystem/ThemeTokens.swift`; all user-facing strings in
`ios/Sources/DesignSystem/Copy*.swift`.

---

## 0. Reading this document

Numbers are exact and **not** to be rounded. Where a value is a token, both the token name and its
resolved value are given, because the Android port should mint the same token and then use it.
Every "why" quoted in blockquotes is a paraphrase or verbatim quote of the source comment that
records the defect the rule exists to prevent — these are load-bearing and must survive the port.

---

## 1. Token reference (only what this screen touches)

### 1.1 Colour

| Token | Value | Where used on Today |
|---|---|---|
| `ThemeColor.canvas` | `#09090B` | screen background, veil colour (`chromeVeil`), `HeroCopyScrim` terminus |
| `ThemeColor.surfaceRaised` | `#242428` | `AccountDisc` quiet ground, poster placeholder ground |
| `ThemeColor.surfacePressed` | `#353842` | `RowPressStyle` press wash (at 0.6 alpha) |
| `ThemeColor.textPrimary` | `#F4F1EC` | hero title, headline of recap, row titles, wordmark |
| `ThemeColor.textSecondary` | `#AAA6A0` | hero fact (`heroMeta`), row meta, shelf captions, support line |
| `ThemeColor.textTertiary` | `#85817C` | "and N more", `EmptyState` symbol, section-header chevron |
| `ThemeColor.textDisabled` | `#807C77` | row chevrons, recap beat chevron |
| `ThemeColor.accent` (amber) | `#F0A24E` | hero **headline** (clock), `ProgressBar` fill, `MarkSplitButton` capsule ground, `OverArtLabel` dot, `MediaRow.lead`, shelf lead captions, `MarkRing` accents |
| `ThemeColor.accentPressed` | `#D88D3B` | pressed half of the split button / primary capsule |
| `ThemeColor.onAccent` | `#0B0B0D` | ink on amber grounds |
| `ThemeColor.interactive` | **alias of `textPrimary`** `#F4F1EC` | every bare tappable word ("View all N updates", "See all") |
| `ThemeColor.ambientBackdropFallback` | `#432D21` | skeleton hero ground when no remembered tint |
| `ThemeColor.scrimStrong` | `black @ 0.72` | `OverArtLabel` capsule ground, recap ✕ disc |
| `ThemeColor.posterEdge` | `white @ 0.09` | 1-pt edge on all artwork and on the ✕ disc / account disc |
| `ThemeColor.hairline` | `white @ 0.055` | `OverArtLabel` capsule border; top-edge light on `.art`/`.raised` surfaces |
| `ThemeColor.separatorQuiet` | `white @ 0.045` | row separators |
| `ThemeColor.strokeStrong` | `white @ 0.20` | `ProgressBar` track |
| `ThemeColor.controlSheen` | `white @ 0.22` | lit top edge of every filled capsule |
| `ThemeColor.markRingIdle` | `white @ 0.34` | unmarked `MarkRing` stroke |
| `ThemeColor.skeleton` | `#F4F1EC @ 0.11` | skeleton blocks |
| `PaletteCache.fallback` | `#1C1A17` | hero persistent ground before palette resolves |

**The amber rule (non-negotiable).** `accent` is rationed to **meaning** (a real next step — a
future air time, "Returns Oct 2") and **state** (today, owned, selected, a committed mark), plus
brand and *grounds* (a filled capsule, where the ink on top is `onAccent`, so no amber *word* is
drawn). Every bare tappable word or glyph uses `interactive` (which is plain text ink) and carries
its affordance by position, semibold weight, a 44-pt target and a chevron. On Today this means:
the hero's clock headline is amber (a fact), the "View all N updates" link is **not**.

### 1.2 Spacing / rhythm

| Token | Value |
|---|---|
| `ThemeSpace.x0_5 / x1 / x2 / x3 / x4 / x5 / x6 / x8 / x10 / x12 / x16` | 2 / 4 / 8 / 12 / 16 / 20 / 24 / 32 / 40 / 48 / 64 |
| `ThemeMetrics.gutter` | 16 |
| `ThemeMetrics.sectionGap` | 30 |
| `ThemeMetrics.labelGap` | 10 |
| `ThemeMetrics.cardGap` | 10 |
| `ThemeMetrics.shelfGap` | 12 |
| `ThemeMetrics.titleGap` | 3 |
| `ThemeMetrics.artGap` | 14 |
| `ThemeMetrics.heroClearance` | 26 |
| `ThemeMetrics.bottomChromeHeight` | 64 |
| `ThemeMetrics.tabBarClearance` | `64 + 12 = 76` |
| `ThemeMetrics.tabBarVisualHeight` | 90 |
| `ThemeMetrics.barEdgeRamp` | 28 |
| `ThemeMetrics.chromeBarOpacity` | 0.74 |
| `ThemeMetrics.rootWashHeight` / `rootWashIntensity` | 320 / 0.4 |
| `ThemeMetrics.rowStandard` / `rowMedia` | 88 / 100 |

### 1.3 Type

Two families. **Outfit speaks** (identity, titles, buttons, facts). **SF annotates** (dense small
metadata, section eyebrows, numerals/times — Outfit has no tabular figures). Outfit tokens scale
with Dynamic Type via `relativeTo:`; SF tokens are system text styles.

| Token | Font | Size | Tracking | Scales relative to |
|---|---|---|---|---|
| `brandWordmark` | Outfit SemiBold | 20 | −0.30 | headline |
| `displayXL` | Outfit Bold | 34 | −0.80 | largeTitle |
| `displayL` | Outfit Bold | 28 | −0.60 | title |
| `heroTitle` | Outfit Bold | 28 | −0.55 | title |
| `showTitleL` | Outfit SemiBold | 22 | −0.35 | title2 |
| `showTitleM` | Outfit SemiBold | 17 | −0.20 | headline |
| `sectionTitle` | Outfit SemiBold | 20 | −0.30 | title3 |
| `heroMeta` | Outfit Regular | 15 | −0.05 | subheadline |
| `rowTitle` | Outfit SemiBold | 17 | −0.20 | headline |
| `shelfTitle` | Outfit Medium | 14 | −0.10 | subheadline |
| `button` | Outfit SemiBold | 16 | −0.15 | callout |
| `listAction` | Outfit SemiBold | 13 | 0 | footnote |
| `rowMeta` / `metadata` | SF footnote | — | 0 | — |
| `metadataEmphasis` | SF footnote semibold | — | 0 | — |
| `rowMetaLead` | SF footnote semibold | — | 0 | — |
| `sectionLabel` | SF caption2 semibold | — | **+1.0** | — |
| `shelfCaption` | SF caption medium | — | 0 | — |

### 1.4 Motion

| Token | Curve |
|---|---|
| `uiPress` | easeOut 0.09 s |
| `uiMicro` | spring(response 0.22, damping 0.88) |
| `uiSnappy` | spring(0.34, 0.84) |
| `uiSettle` | spring(0.46, 0.90) |
| `uiGentle` | easeInOut 0.22 s |
| `uiReveal` | cubic-bezier(0.22, 1.00, 0.36, 1.00) 0.28 s |
| `uiDismiss` | easeIn 0.16 s |
| `uiNumeric` | easeOut 0.22 s |
| `uiPoster` | easeOut 0.18 s |
| `uiReduced` | easeOut 0.12 s — **the universal Reduce Motion substitute** |
| `uiCrossfade` | `= uiReduced` |

`ThemeMotion.pick(token, reduceMotion:)` returns `uiReduced` whenever Reduce Motion is on. Every
animation on this screen goes through `pick`.

**`AnyTransition.handoff(reduceMotion:)`** — the one card-replacement transition, used by the hero,
the recap and the queue rows. Asymmetric on purpose:

- insertion: `.opacity`, animated with `uiSettle` **delayed 0.08 s**
- removal: `.opacity`, animated with `uiDismiss` (0.16 s)
- under Reduce Motion: plain `.opacity` on `uiReduced`, no delay.

> The removal finishes before the insertion starts. A symmetric crossfade renders two different
> show titles at 50 % on top of each other — "which is what a smear is".

### 1.5 Haptics

All haptics go through `FeedbackCoordinator.fire(_:)`, which (a) respects a user toggle stored at
`UserDefaults["previously.haptics"]` (default true), (b) no-ops when the app is not `.active`, and
(c) throttles **per token** — 0.04 s floor for `.selection`, 0.3 s for everything else.

| Token | iOS generator | Fired on Today by |
|---|---|---|
| `.commitLight` | UIImpactFeedback `.light` @ intensity 0.65 | every `markNext` (hero mark, queue-row mark) |
| `.commitMedium` | `.medium` @ 0.72 | `setProgress` when the delta > 1 episode (i.e. the batch mark) |
| `.success` | UINotificationFeedback `.success` | `addToLibrary` (trending billboard "Add to Library") |
| `.selection` | UISelectionFeedback | Undo tapped |
| `.refreshArmed` | `.light` @ 0.50 | pull-to-refresh crosses its 80-pt threshold **while a finger is down** |

**One haptic per transaction** is the rule; the view never fires one directly — it is fired inside
the write (`markNext`, `setProgress`, `addToLibrary`).

---

## 2. Data inputs

`TodayView` reads `AppModel` (an `@Observable` main-actor object) and `AuthManager`. Nothing on
this screen fetches; the parent owns loading.

### 2.1 Time

`appModel.now` is milliseconds since epoch, re-published on a **20-second tick** (`clockTick`).
Every countdown, "aired N min ago" and day-word on this screen is a pure function of `now`.
`appModel.nowMinute` (a minute-truncated mirror) exists for Schedule and is not used here.

### 2.2 Flags

| Property | Meaning |
|---|---|
| `loading` | no library payload has arrived yet |
| `libraryEmpty` | `library.isEmpty` |
| `loadError` | the last library fetch failed (cancellations are **not** failures) |
| `isRefreshing` | a pull-to-refresh is in flight |
| `surfaceReady` | the cold-launch splash has left and Today is actually visible |
| `prevOpenedAt` | server-supplied epoch-ms of the previous visit; the recap window's anchor |
| `trending` / `trendingLoading` | the chart, and `trending.isEmpty && a fetch is in flight` |
| `justCaught: Set<String>` | franchise ids currently celebrating a just-committed catch-up |

### 2.3 Feeds (all derived, all recomputed from `library` + `now`)

| Feed | Definition |
|---|---|
| `airingFranchises` | `library` where `releasingPart != nil` **and** `tracksAirings` (i.e. `effectiveStatus != .planned`) |
| `outNow` | `airingFranchises` where `part.behind(now:anchor:) > 0` (or the id is in `justCaught`) **and** `now − part.lastAired(now:anchor:) ≤ 7 days` (`outNowWindow`), sorted by `lastAired(now:)` descending |
| `keepWatching` | `library` where status is `watching`, not in `outNow`, and `resumePart != nil`; sorted by `continueBacklog` desc then title asc; **capped at 8** |
| `nextUp` | the `airingFranchises` entry with the minimum `nextAiring(now:)` |
| `watchingShelf` | `watching` shows admitted by `shelfState(of:)`, ordered `newEpisode(0) < backlog(1) < airingWait(2) < premiereSoon(3)`, ties broken most-actionable-first |
| `soon` | 48-h lookahead — **no consumer on Today** (see §14) |
| `nowBarItem` | one global "live / next" fact — **no consumer on Today** (see §14) |

`shelfState(of:)`:
1. `.newEpisode` — `releasingPart.behind > 0` and `now − lastAired ≤ 7 d`
2. `.backlog` — `resumePart != nil`
3. `.airingWait` — releasing part is caught up and `nextAiring(now:) != nil`
4. `.premiereSoon` — `nextPremiere(of:)` within 45 days (`premiereShelfWindow`)
5. otherwise `nil` (dormant → not on the shelf)

### 2.4 Model derivations the screen depends on

**Freshness is derived from `airings`, never from the catalogue's counts.** `airedEpisodes`,
`lastAiredAt`, `nextAiringAt` are hourly-cron fields; `FranchisePart.airings` is the per-episode
calendar in the same payload, and a slot in it that has struck **is** an aired episode.

```swift
// A slot has "passed" — the anchor decides:
//   .local   (AniList, a true instant):  a.at <= now
//   .utcDate (TMDB, date-only):          dayDiff(a.at, now, .utcDate) < 0   (the day AFTER)
func airedByNow(now:anchor:) -> Int   // max(airedEpisodes, latest passed slot's episode)
func behind(now:anchor:)    -> Int    // isReleasing ? max(0, airedByNow − progress) : 0
func lastAired(now:anchor:) -> Int64? // max(lastAiredAt, latest passed slot's `at`)
func upcomingAiring(now:anchor:) -> Int64?
      // strictly-future slot for a timed source; today-or-later for a date-only one;
      // falls back to `scheduledAiring` (nextAiringAt if dayDiff >= 0)
```

> Reading the raw fields made the one show that had just aired (6:30 PM) the one show Today could
> not see for an hour: not fresh (count unchanged), not waiting (slot passed) — gone.

Other required derivations:

| Member | Rule |
|---|---|
| `Franchise.timeAnchor` | `.utcDate` for TMDB, `.local` for AniList |
| `Franchise.nextAiring(now:)` | `releasingPart?.upcomingAiring(now:anchor: timeAnchor)` |
| `Franchise.lastAired(now:)` | `releasingPart?.lastAired(now:anchor: timeAnchor)` |
| `Franchise.releasingPart` | releasing part with the soonest `nextAiringAt`, else the most recently aired |
| `Franchise.resumePart` | mid-watch part (progress in `1..<available`), else the first unstarted part *after* the highest completed one, else the earliest with anything left |
| `Franchise.continueBacklog` | `available(resumePart) − resumePart.progress`, floored at 0 |
| `Franchise.effectiveStatus` | `status ?? subscription?.status ?? .planned` |
| `Franchise.tracksAirings` | `effectiveStatus != .planned` |
| `Franchise.displayTitle` | `title.shelfShortened` (see §12.4) |
| `Franchise.watchContext(part:episode:)` | `"Season 4 · Episode 19"` when `parts.count > 1`, else `"Episode 19"`; a movie yields the part's `canonicalLabel` alone |
| `FranchisePart.availableEpisodes()` | 0 if upcoming; else `airedEpisodes > 0 ? airedEpisodes : totalEpisodes` |
| `FranchisePart.progressCeiling` | 0 if upcoming; `max(totalEpisodes, airedEpisodes)`; **`Int.max` when unknown** |
| `FranchisePart.markTarget(now:)` | releasing → `provenAiredCount(now:)`; else `renderableEpisodeCount(now:)` |

**Art access.** Views read `portraitArt` / `landscapeArt`, never `cover` / `banner`:
`portraitArt = images?.portrait ?? nonEmpty(cover)`;
`landscapeArt = images?.landscape ?? legacyBanner(banner, cover:)` — the legacy `banner` is trusted
only when it differs from the cover (older writers copied the poster into it).

---

## 3. Screen scaffold

```
GeometryReader { geo in
  topInset = geo.safeAreaInsets.top
  screenH  = geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom

  ZStack(alignment: .top) {
    [A]  if !showsHero  →  ArtBackdrop(url: ambientArt, height: 320, intensity: 0.4)
                              .ignoresSafeArea(edges: .top)
    [B]  ScrollView { VStack(alignment: .leading, spacing: 0) {
              SkeletonGate(isLoading: loading && libraryEmpty) { skeleton } content: {
                 VStack(spacing: 0) {
                    topBlock(screenH:topInset:contentH:)
                    belowTheFold.opacity(recapOnStage ? 0 : 1)
                 }.animation(pick(uiSettle), value: recapOnStage)
              }
           } }
           .background { Color.clear.onGeometryChange(minY) { scroll.set(topInset − minY) } }
           .tabBarContentMargin()            // contentMargins(.bottom, 76, for: .scrollContent)
           .scrollIndicators(.hidden)
           .onScrollGeometryChange { g in g.contentOffset.y + g.contentInsets.top }
                                  action: { _, y in scroll.set(y) }
           .previouslyRefreshable { await appModel.reload() }
    [C]  TodayVeils(scroll:topInset:showsHero:headerCarriesTitle:)
    [D]  header                                       // wordmark + account disc, 52 pt tall
  }.frame(width: geo.size.width, height: geo.size.height)
}
.background(ThemeColor.canvas.ignoresSafeArea())
.overlay(alignment: .bottom) { ScrollEdgeChrome(side: .bottom) }
```

### 3.1 `screenH`

The hero fraction is of the **whole screen, status bar included**, because the art bleeds into it.
Adding the inset again would silently shrink the resting geometry.

### 3.2 The scroll offset — the performance architecture (read this before porting)

`ScrollOffset` is a small observable object held in `@State`, **not** a plain `CGFloat`:

```swift
@Observable @MainActor final class ScrollOffset {
    private(set) var y: CGFloat = 0
    func set(_ raw: CGFloat) {
        let v = ThemeMetrics.scrollSample(raw)   // clamp(-320…240), round to the half point
        if v != y { y = v }                      // de-duplicate
    }
    var veilOpacity: Double { clamp((y − 16) / 64, 0, 1) }
    var stretch: CGFloat { max(0, −y) }
}
```

Only two tiny views read `.y` inside a body: `TodayVeils` and `StretchingHeroArt`. Therefore a
frame of scrolling invalidates **those two views and nothing else**.

> The raw offset as `@State` on the screen re-ran Today's entire body — the stack, the queue, the
> shelf, every row — at 60–120 Hz on the first swipe ("Today lags", reported twice).

Two probes write the same value, deliberately:

1. `onScrollGeometryChange` on the `ScrollView` (`contentOffset.y + contentInsets.top`);
2. **belt-and-braces:** a `Color.clear.onGeometryChange` on the scroll *content*'s global `minY`,
   writing `topInset − minY`.

> On the iOS 27 simulator `onScrollGeometryChange` never fired, so the veil stayed off and the
> hero's title parked *inside* the wordmark at full ink ("Previously.Tensei"). A layout frame
> cannot fail to report a move; when both fire they write the same value, so nothing oscillates.

**Android translation.** Compose's `LazyColumn`/`ScrollState` already exposes a value; the rule to
carry over is that the offset must live in a `MutableState` read **only** inside the two small
composables that draw the veil and stretch the art (or better, read via a lambda / `derivedStateOf`
so the parent never recomposes). Clamp to `[-320, 240]` dp and round to 0.5 dp before publishing —
this is what makes the value *stop changing* once the chrome has settled.

**There is no mask on the scroll view.** An earlier build masked the content to fade it under the
wordmark; it cost a full-screen offscreen pass every frame and it erased the show's name. The
opaque bar covers what passes under the band instead.

### 3.3 `TodayVeils` — the wordmark-band hardening

```swift
hardOn = showsHero ? headerCarriesTitle : (scroll.y > 8)
```

Two mutually exclusive layers inside a `ZStack(alignment: .top)`, cross-faded on
`pick(uiGentle)` keyed on `hardOn`, the whole thing `allowsHitTesting(false)`:

| Condition | Layer |
|---|---|
| `!hardOn && scroll.y > 12` | `ScrollEdgeChrome(side: .top, height: topInset + 52 + 100)` at `opacity = scroll.veilOpacity`, `.transition(.opacity)` |
| `hardOn` | `ScrollEdgeChrome(side: .top, height: topInset + 52 + 28, holdHeight: topInset + 52)`, `.transition(.opacity)` |

> The soft layer is **mounted only in that phase** — "a material at opacity 0 over moving art is
> still a backdrop blur the compositor pays for every frame."

`ScrollEdgeChrome(side: .top)` composition, with `hold = holdHeight / height` clamped to 0…1:

- an `.ultraThinMaterial` rectangle masked by a gradient: `black@1.0` at 0 → `black@1.0` at `hold`
  → `black@0.42` at `hold + (1−hold)·0.45` → `clear` at 1. **Dropped entirely under Reduce
  Transparency.**
- over it, a canvas gradient with `bar = reduceTransparency ? 1.0 : 0.74` (`chromeBarOpacity`):
  `canvas@bar` at 0 → `canvas@bar` at `hold` → `canvas@(bar·0.45)` at `hold + (1−hold)·0.45` →
  `canvas@0` at 1.

> "Hardened" means **0.74 canvas over a full-strength blur, never opaque canvas.** At 1.0 the top
> ~100 pt of every scrolled screen was a flat `#09090B` slab with the material under it painted for
> nothing. Only Reduce Transparency — which has no blur — gets the opaque bar.

`ScrollEdgeChrome(side: .bottom)` (mounted once on the screen root, outside the scroll view): a
64-pt band whose canvas gradient runs `0` at 0 → `0.25` at 0.55 → `0.75` at 0.85 → full canvas at
1, with the blur mask stopped identically, followed by **180 pt of solid canvas offset downward
(`bottomUnderfill`)** so the floating glass tab bar has an opaque ground to refract.

### 3.4 Header (wordmark ⇄ title hand-over)

`HStack(alignment: .center)`, `padding(.leading, 16)`, `padding(.trailing, 8)`, `frame(height: 52)`.

Leading: a `ZStack(alignment: .leading)` cross-fading two things on `pick(uiGentle)` keyed on
`headerCarriesTitle`:

- `Wordmark()` at `opacity(headerCarriesTitle ? 0 : 1)` — the `PreviouslyMark` bookmark glyph (13 pt
  wide, aspect 1 : 1.58, amber gradient `#FFD6A0 → #F0A24E → #C9702E`, with the `.progress` slot)
  then `Text("Previously.")` in `brandWordmark`/`textPrimary`; `HStack(spacing: 8)`; `shadow(.art)`;
  VoiceOver label "Previously".
- `Text(heroFranchise.displayTitle)` in `showTitleM`/`textPrimary`, `lineLimit(1)`,
  `minimumScaleFactor(0.85)`, `shadow(.art)`, at `opacity(headerCarriesTitle ? 1 : 0)` and
  `accessibilityHidden(!headerCarriesTitle)`.

> The identity is HANDED OVER, not dropped. Scrolling used to dissolve the show's name while the
> wordmark sat still, so the screen lost the one fact it was about and gained nothing.

Trailing: `AccountDisc(identity:, diameter: 34, quiet: true)` — a 34-pt circle filled
`surfaceRaised`, stroked `posterEdge` 1 pt, with the monogram at `size = diameter × 0.42` semibold
in `textSecondary` (or the `PreviouslyMark` at `diameter × 0.34` when there is no monogram) —
`shadow(.art)`, in a `44 × 44` frame with `contentShape(Circle())`, `OverArtPressStyle`,
`accessibilityLabel("Profile")`. Tapping presents the Profile sheet.

> No glass behind it — `AccountDisc` already carries its own ground and ring; a second disc drawn
> over a finished one rendered as a flat grey plate on the artwork. And `quiet:` because six amber
> objects sat in the first viewport and the one that must win — the CTA — had no contrast left.

### 3.5 `headerCarriesTitle`

```swift
guard showsHero, !recapOnStage, heroFranchise != nil else { return false }
return heroCopyUnderBand
```

`heroCopyUnderBand` is **measured, not thresholded** — it is set where the hero copy block is
measured: `minY < topInset + 52 + 8`.

> `scrollY > 150` was calibrated against a tall library and never tripped on a compact one — a
> short Today parks at ~92 pt of scroll with the title already under the band, so the mask erased
> the show's name and the wordmark never took it over.

### 3.6 Lifecycle hooks

| Trigger | Effect |
|---|---|
| `.onAppear` | (DEBUG) `-openProfile 1` → present Profile; `evaluateRecap()`; if `libraryEmpty` → `loadTrendingIfNeeded()` |
| `.onChange(of: loading)` when it goes false | `evaluateRecap()` |
| `.onChange(of: surfaceReady)` | `startRecapClock()` |
| `.onChange(of: libraryEmpty)` when it becomes true | `loadTrendingIfNeeded()` |
| `.onChange(of: isRefreshing)` when it becomes true | `Announce.status("Refreshing")` — "a pull-to-refresh is a state change with no visible focus move, so VoiceOver was told nothing at all while it ran" |
| `.onDisappear` | `clearRecapStrip()` |
| `.onChange(of: scenePhase) == .background` | `clearRecapStrip()` |

Pull-to-refresh (`previouslyRefreshable(threshold: 80)`) calls `appModel.reload()` and fires
`.refreshArmed` once, only while a finger is on the glass (`scrollPhase == .tracking || .interacting`),
re-arming only after the pull falls back below 0.3 × threshold.

---

## 4. Top-block state machine

```swift
isFailed      = loadError && libraryEmpty
isEmptyAccount = !loading && libraryEmpty && !loadError
showsHero     = !libraryEmpty && !isFailed && (heroFranchise != nil || (recapOnStage && recap != nil))
```

`topBlock(screenH:topInset:contentH:)` resolves in this exact order:

1. **`isFailed`** → `stateBlock(SyncCenter.shared.isOnline ? .serverNoCache : .offlineNoData)` with
   `Try again` → `appModel.reload()`.
2. **`isEmptyAccount`**
   - `trending.first != nil` → **trending billboard** (§6) + trending shelf
   - else `trendingLoading` → the **skeleton** (§8)
   - else → `stateBlock(.emptyToday)` with `Add a show` → `onAddShow`
     > `emptyToday`, not `emptyAccount`: the latter is LIBRARY's string, "and a state may not title
     > itself after a tab the user is not looking at."
3. **`showsHero`** → `hero(heroFranchise, …)` (§5)
4. else → `calmBlock` (§7)

`ambientArt` (the wash behind any no-hero state) =
`nextUp?.portraitArt ?? watchingShelf.first?.portraitArt ?? library.first?.portraitArt`.

### 4.1 `stateBlock`

```
EmptyState(copy, primary: action)
  .padding(.horizontal, 16)
  .centredState(contentH: contentH − 52)      // frame(minHeight: max(0, h − 90), alignment: .center)
  .padding(.top, 52)
  .background(alignment: .center) { if copy == .emptyToday { emptyFan } }
```

`centredState` subtracts `tabBarVisualHeight` (**90**), *not* `tabBarClearance` (76): "half of
whatever is subtracted is the error", and subtracting the scroll inset pushed every empty state
~81 pt above true optical centre. `minHeight`, never `height`, so AX3–AX5 grows the block rather
than pushing the button outside the scrollable region.

**`EmptyState` anatomy** (`ContentUnavailableView`'s shape on the canvas — no plate, no glyph tile,
no bloom): a centred SF Symbol at `44 pt × @ScaledMetric(relativeTo: .title3)` in `textTertiary`,
16 pt below it the title in `showTitleL`/`textPrimary` (≤3 lines, unlimited at AX), 8 pt below that
the supporting sentence in `callout`/`textSecondary`, then 20 pt and **one hugging button**
(`fixedSize(horizontal: !isAX)`): a *recovery* ("Try again"/"Retry") uses `SecondaryButtonStyle2`
(44-pt `surfaceFloating` capsule, `stroke` border), a *next step* ("Add a show") uses
`PrimaryButtonStyle2` (48-pt amber capsule, `onAccent` ink, `controlSheen` top edge). Whole block
`frame(maxWidth: 300)`, `.transition(.opacity)` ("an empty state that scales in reads as a
celebration of having nothing"), one combined VoiceOver label `"{title}. {supporting}"`.

### 4.2 `emptyFan` — behind `.emptyToday` only

Three `PosterSlot(url:, .shelfMedium)` (112 × 168, radius 12) from `trending.prefix(3)` — drawn
**only when exactly three covers exist** — in an `HStack(spacing: −112 × 0.42 = −47.04)`, each
rotated `(i − 1) × 9°` and offset `y: |i − 1| × 10`, the middle card `zIndex(1)`. Whole fan
`opacity(0.35)`, `blur(radius: 1.5)`, `offset(y: −60)`, non-interactive, accessibility-hidden.

> ONLY behind the empty account — behind "Couldn't load your library" the same fan read as the very
> shows the message says it cannot show.

---

## 5. The hero

### 5.1 Height

```swift
func heroHeight(_ screenH: CGFloat) -> CGFloat {
    if recapOnStage { return screenH − recapFloor }          // recapFloor = 76 + 8 = 84
    let artBand = isAX ? 210 : 132
    return max(screenH × 0.72, heroCopyHeight + artBand)
}
```

- **0.72** is measured against Apple TV Home: its hero CTA bottoms out at ~70 % of the screen and
  the next shelf header sits at ~83 %, so at 0.72 the copy block lands on the same line and the
  queue's first row peeks above the tab bar as the scroll affordance.
- The frame grows by the copy's **overflow**, not by a guessed accessibility bump. The copy height
  depends only on the width, never on this, so there is no layout cycle.
- `recapFloor` must clear the bottom chrome's *whole ramp*, not just the tab bar: at 96 pt the
  card's `Continue` control came to rest inside the veil and rendered at a quarter of its ink.

### 5.2 Art selection

```swift
heroArt(f)          = f?.portraitArt ?? f?.landscapeArt ?? recap?.beats.first?.cover
heroArtIsPortrait(f) = f?.portraitArt != nil ? true : (f?.landscapeArt != nil ? false : true)
```

**Cover first, banner as the fallback** — the inverse of Detail's order.

> This frame is 72 % of the screen at ~0.64 w/h, and a ~1900×400 banner `.fill`ed into it is
> upscaled ~4.6× to a sliver of itself ("why does it appear so zoomed in?"). The 2:3 cover is within
> 4 % of the frame's own aspect, so the composite path shows it whole and sharp over its own blurred
> edges — the Netflix mobile-billboard anatomy.

### 5.3 Layer stack

`ZStack(alignment: .bottom)`, frame `height: h`, `maxWidth: .infinity`:

1. **Persistent ground** — `(heroTint ?? PaletteCache.fallback)` filling `h`, non-interactive,
   accessibility-hidden. It sits **outside** the `.id`/`.transition` so it survives both cards.
   > The handoff finishes the removal before it starts the insertion — which means for ~80 ms there
   > is a gap with nothing in it, and a 46 %-of-screen frame rendered bare `#09090B` in the middle
   > of the app's signature moment.
2. **`StretchingHeroArt`** — `ArtHeader(url: art, height: h + scroll.stretch, tint: heroTint,
   scrimTop: 0, scrimBottom: recapOnStage ? 1.9 : 0, focus: .top, portraitSource:
   heroArtIsPortrait(f), drift: true)`, `frame(height: h, alignment: .bottom)`,
   `.id(art ?? f?.id ?? recap?.digestID ?? "hero")`, `.transition(handoff)`.
   **Keyed on the photograph, not the franchise id** — the image only has reason to dissolve when
   the image changes; two shows sharing a hero asset hand over without a flicker.
3. **`HeroCopyScrim(copyHeight: heroCopyHeight)`** (§5.5).
4. **The overlay group** — `RecapArrival` when `recapOnStage`, else `heroOverlay(f)` — each with
   `.transition(handoff)`, wrapped in `padding(.horizontal, 16)` and
   `padding(.bottom, isAX ? 20 : 16)`, plus two geometry readers:
   - `onGeometryChange { $0.size.height } → heroCopyHeight`
   - `onGeometryChange { $0.frame(in: .global).minY } → heroCopyUnderBand = minY < topInset + 52 + 8`

Then, on the ZStack, in this exact order:

```swift
.mask(alignment: .bottom) { Rectangle().padding(.top, -2000) }   // clip the BOTTOM only
.overlay(alignment: .top) { HeroTopVeil(band: topInset + 52, ramp: 100) }
.padding(.top, -topInset)
.zoomSource(f.map { "focus/\($0.id)" } ?? "focus/recap")
.franchiseQuickActions(f, appModel: appModel)
.animation(pick(uiSettle), value: recapOnStage)
.animation(pick(uiSettle), value: key)
.task(id: art) { heroTint = await PaletteCache.shared.resolve(url: art, maxPixel: 360)
                 TodayView.rememberTint(heroTint) }
```

Three ordering constraints that are bugs if broken:

- The **mask** extends 2000 pt upward and stops at the bottom edge, cutting one side only. A
  removing view keeps the frame it had when it left the layout, so during the recap → focus shrink
  the outgoing recap card (last laid out at ~880 pt) hung in the vacated space and drew over
  `UPCOMING` and the first shelf row for ~130 ms. `.clipped()` cannot be used — the pull-stretched
  art has to keep drawing *above* this frame.
- The **top veil overlay must be attached BEFORE `padding(.top, -topInset)`**; attached after, it
  starts below the status bar and leaves the clock on bare art with a hard seam under it.
- `padding(.top, -topInset)` is what lets the art bleed into the status bar.

### 5.4 `ArtHeader` internals (shared with Detail)

- ground = `tint ?? PaletteCache.fallback`;
- if `portraitSource`: a blurred fill copy (`maxPixel 1024`, `blur(radius: 48, opaque: true)`,
  `overlay(black @ 0.28)`), then the **sharp** copy `contentMode: .fit`, `maxPixel: 2048`,
  `alignment: focus`;
  else a single `.fill` copy at `maxPixel: 1536`, `alignment: focus`.
  > 2048, not 1024, on the sharp layer: Today's billboard draws it ~1770 px tall, and capping the
  > decode below that softened the one sharp asset in the frame.
- `focus: .top` — "faces live in the upper third of a key visual and in the upper half of a cover;
  a centred crop of either is a chin."
- then `ArtScrim(top: scrimTop, bottom: scrimBottom)`; on Today `scrimTop = 0` always and
  `scrimBottom = 0` except while the recap is on stage (1.9). `ArtScrim`'s stops:
  `black@(0.55·top)` at 0.00, `black@(0.16·top)` at 0.22, `clear` at 0.46,
  `canvas@(0.55·bottom)` at 0.80, `canvas@(1.00·bottom)` at 1.00.
- `.clipped()`.

**The drift ("the billboard art BREATHES").** `drift: true` only on Today's and Detail's hero:

```swift
driftScale  = drifting ? 1.07 : 1
driftAnchor = focus == .top ? .top : (focus == .bottom ? .bottom : .center)
.task(id: drift && !reduceMotion) {
    guard drift, !reduceMotion else { drifting = false; return }
    try? await Task.sleep(for: .milliseconds(80))   // a beat after insertion, or the animation
    guard !Task.isCancelled else { return }         // is folded into the appearance and never repeats
    withAnimation(.easeInOut(duration: 24).repeatForever(autoreverses: true)) { drifting = true }
}
```

Applied as `scaleEffect` on the **sharp layer only** (not the blurred ground): ~7 % over 24 s,
eased, reversing, anchored at the top, off under Reduce Motion. It is one transform animation on
one layer, so **no body re-evaluates for it** — the scroll-lag rule still holds.

### 5.5 The two protections, both in POINTS

`HeroTopVeil(band: topInset + 52, ramp: 100)`, total `= band + ramp`, `mark = band / total`:

| Stop | Location | Colour |
|---|---|---|
| 0 | 0 | `black @ 0.72` |
| 1 | `mark × 0.72` | `black @ 0.66` |
| 2 | `mark` | `black @ 0.52` |
| 3 | `mark + (1−mark) × 0.30` | `black @ 0.30` |
| 4 | `mark + (1−mark) × 0.62` | `black @ 0.12` |
| 5 | 1 | `clear` |

> `veilRamp = 100`, not 46: the chrome's ramp is proportional to its own height, so a veil that
> ends at the band ramps out in ~25 pt — and against bright hero artwork that reads as a straight
> black line drawn across the screen.

`HeroCopyScrim(copyHeight:)`, `lead = 72`, `h = max(1, copyHeight + lead + 8)`:

| Stop | Location | Colour |
|---|---|---|
| 0 | 0 | `clear` |
| 1 | `min(0.99, lead × 0.4 / h)` | `canvas @ 0.16` |
| 2 | `min(0.99, lead × 0.7 / h)` | `canvas @ 0.44` |
| 3 | `min(0.99, lead / h)` | `canvas @ 0.72` |
| 4 | `min(0.995, (lead + 56) / h)` | `canvas @ 0.90` |
| 5 | 1 | `canvas` (fully opaque) |

> Stops that are fractions of the image simply do not know how tall the text is, which is why AX1
> put "Reincarnated as a / Slime" in white on pale sky at ~1.6:1. And the scrim must **land**, not
> hover: 3 % of photograph glowing through at the line where the hero meets the canvas rendered as
> a faint band across the screen.

### 5.6 Remembered hero tint (cross-launch)

`UserDefaults["today.heroTint"]` stores `[r, g, b]` as `Double`s from `UIColor(color).cgColor.components`
after every successful palette resolve; `TodayView.rememberedTint` reads them back as an sRGB
`Color`. It is used **only** by the skeleton's hero band.

> The loading frame is the first thing a returning user sees and it has no artwork yet by
> definition — so it was a black rectangle. The hero rarely changes between two opens.

---

## 6. The hero SLATE — grammar and copy

> **The hero is a SLATE, read in a TV listing's order: pill → headline → show → fact.**
> Never let the reason someone opened the app be the smallest text on it, and never say in words
> what a numeral beside them already says.

### 6.1 `FocusKind` — the classifier

```swift
enum FocusKind { case fresh(behind: Int), backlog(left: Int), caughtUp, waiting(at: Int64) }

func kind(of f: Franchise) -> (FocusKind, FranchisePart)? {
    if let part = f.releasingPart {
        let behind = part.behind(now: now, anchor: f.timeAnchor)
        if now − (part.lastAired(now: now, anchor: f.timeAnchor) ?? 0) <= 7.days,      // outNowWindow
           behind > 0 || appModel.justCaught.contains(f.id) {
            return behind > 0 ? (.fresh(behind), part) : (.caughtUp, part)
        }
    }
    if let part = f.resumePart      { return (.backlog(left: f.continueBacklog), part) }
    if let part = f.releasingPart, let at = f.nextAiring(now: now) { return (.waiting(at: at), part) }
    return nil
}
```

Evaluated **on the object, not on the live feed**, so a pinned snapshot keeps its wording while the
hero shows its result.

**`calmKind(of:)`** — used *only* for the calm hero, never `kind(of:)`:

```swift
if let part = f.releasingPart, let at = f.nextAiring(now: now) { return (.waiting(at: at), part) }
guard let part = f.resumePart ?? f.releasingPart ?? f.episodicPartsInOrder.last ?? f.parts.first else { return nil }
return (.caughtUp, part)
```

> The calm hero exists because the stack is empty, so there is nothing to mark on it; and under
> `-calmDemo 1` the stack is emptied by force on a library that *is* behind, where `kind(of:)`
> would hand the calm hero a CTA.

### 6.2 The four slate lines

Let `nextEpisode = part.progress + 1`, `LIVE = 24 h` (`AppModel.nowBarLiveWindow`).

#### Pill / eyebrow (`OverArtLabel`, uppercase)

| Kind | Text |
|---|---|
| `.fresh(behind)` | if `lastAired` exists **and** `now − lastAired ≤ 24 h` → `TemporalCopy.aired(at:)` ("AIRED 29 MIN AGO"); else if `behind > 1` → `Copy.Progress.behind(behind)` ("9 EPISODES BEHIND"); else if `lastAired` exists → `TemporalCopy.aired(at:)`; else `"New episode"` |
| `.backlog(left)` | `left > 1` → `Copy.Progress.left(left)` ("13 EPISODES LEFT"); else `"Last episode of the season"` |
| `.caughtUp` | `"Caught up"` |
| `.waiting(at)` | AniList → `TemporalCopy.airsCompact(at:)` — just the DAY: `"Today"` / `"Tomorrow"` / `"Friday"` / `"Sep 12"`. TMDB (date-only) → `"New episode"` |

> An episode that struck TODAY leads with its recency **whatever the count** — "it has literally
> aired just now" is the news the person opened the app for; the count moves to the support line.
> And for a waiting hero, "NEW EPISODE TODAY" said in three words what the pill's day and the
> headline's clock already say between them.

#### Pill dot (`eyebrowDot`)

`true` only for: `.fresh` where `f.lastAired(now:)` exists and `now − lastAired ≤ 24 h`; or
`.waiting(at)` where `f.dayDiff(of: at, now:) == 0`. `false` in every other case, and always
`false` in the committed frame. "A days-old drop with a backlog is a count, not a pulse."

#### Headline (`displayXL`, accent, monospaced digits) — only a moment earns it

```swift
guard case .waiting(let at) = kind else { return nil }
return f.source == .anilist ? Formatting.fmtTime(at, anchor: .local)         // "6:30 PM" / "21:00"
                            : TemporalCopy.airsCompact(at: at, now:, source:) // "Friday"
```

An aired episode has **no headline** — there the show and the action are the news. `fmtTime` uses
the locale's short time style, so a 24-hour device reads "21:00".

#### Show

`franchise.displayTitle` (the shortened form, "Re:ZERO", as every row and shelf in the app).
Type: `headline == nil ? (isAX ? displayXL : heroTitle) : showTitleL` — i.e. the show steps **down**
a size when a headline is above it, "because the art is already saying its name".
`lineLimit(isAX ? 3 : 2)`, `minimumScaleFactor(0.85)`, `allowsTightening(true)`.
> The hero may never ellipsize the one name the screen exists to show.

#### Fact (`heroMeta`, `textSecondary`)

```swift
// caught-up whose season is finished → the SEASON, not a nonexistent episode
if case .caughtUp = kind, part.isComplete || (part.progress >= max(part.totalEpisodes, 1) && !part.isReleasing) {
    return part.canonicalLabel.isEmpty ? part.title : part.canonicalLabel
}
if case .waiting(let at) = kind {
    let episode = f.watchContext(part: part, episode: part.nextEpisodeNumber ?? part.airedEpisodes + 1)
    guard f.source == .anilist, at > now, at − now < 24 h else { return episode }
    return "in \(Formatting.fmtCountdown(target: at, now: now, anchor: .local)) · \(episode)"
}
return f.watchContext(part: part, episode: part.progress + 1)
```

So a waiting hero reads `"in 3h 12m · Season 4 · Episode 15"` — **the countdown rides along only
inside the day**: "in 3h 12m" is the thing to be excited about, "in 4d 2h" is arithmetic.

The fact line is `textSecondary` on purpose, "so the title and 'Season 4 · Episode 12' never read
as one line."

#### Support (`metadata`, `textSecondary`) — at most one more thing

| Kind | Support |
|---|---|
| `.fresh(behind)` | `Copy.Progress.behind(behind)` **only when** `part.progress == 0 && behind > 1 && now − lastAired ≤ 24 h` (i.e. nothing watched yet **and** the pill spent itself on the recency). Otherwise `nil`. |
| `.backlog` | `nil` |
| `.caughtUp` | `part.nextAiringAt > now` → `TemporalCopy.airs(at:)`; else `appModel.nextPremiere(of: f)` → `TemporalCopy.returns(at:)`; else `nil` |
| `.waiting` | `nil` |

> "Latest aired 28 Aug" under "9 EPISODES BEHIND" and "11 of 24 watched" under "13 EPISODES LEFT"
> were second sentences about the same fact.

#### Progress bar — where-you-are, wordless

```swift
let done  = committed ? (committedEpisode ?? part.progress) : part.progress
switch kind {
case .fresh:   total = part.airedByNow(now:anchor:); spoken = Copy.Progress.behind(max(0, total − done))
case .backlog: total = part.availableEpisodes();     spoken = Copy.Progress.left(max(0, total − done))
default: return nil
}
guard total > 0, done > 0, done < total else { return nil }   // nothing watched, or everything
ratio = Double(done) / Double(total)
```

Rendered as `ProgressBar(value:spoken:)`: a 3-pt-tall capsule track in `strokeStrong` with the
watched share in `accent`, **minimum fill width 3 pt** so a started season is never zero-width.
`frame(maxWidth: isAX ? .infinity : 200, alignment: .leading)`, `padding(.top, 8)`. The bar itself
is accessibility-hidden unless `spoken` is supplied, in which case that string is its label.

### 6.3 The committed frame — `advanced(_:f:part:from:behind:)`

While a mark is committing (`committedEpisode != nil && pinned?.first?.id == f.id`), the whole meta
block advances **in the same frame as the button's label**:

```swift
let left = max(0, behind − 1)
if left == 0 {
    // The button already says "Episode 19 watched"; the footnote says what comes NEXT.
    let next = part.nextAiringAt.flatMap { at in
        guard at > now else { return nil }
        return "\(Copy.episode(episode + 1)) airs \(midSentence(TemporalCopy.airs(at: at, now:, source:)))"
    }
    return (eyebrow: "Caught up", fact: f.watchContext(part: part, episode: episode), support: next)
}
let count = (kind is .backlog) ? Copy.Progress.left(left) : Copy.Progress.behind(left)
return (count, f.watchContext(part: part, episode: episode + 1),
        left == 1 ? "Caught up after this episode" : nil)
```

`midSentence(_:)` lower-cases **only** "Today", "Tomorrow", "Yesterday" — the ordinary adverbs.
"Friday", "Aug 28", "Sun" are proper nouns and a sentence does not get to lower-case them.

> A bare "Friday at 7:30 PM" printed directly under "Season 4 · Episode 19" is the identical grammar
> this screen uses for a future airing, so the line read as "Episode 19 airs Friday" — about an
> episode the user has just told the app they already watched. The clock is a fact about episode 20.

In the committed frame the headline is suppressed (`nil`) and `eyebrowDot` is forced `false`.

### 6.4 `HeroFocus` layout

`VStack(alignment: .leading, spacing: 0)`:

```
Button(onOpen) {                         // the WHOLE copy block opens the show
  HStack(alignment: .bottom, spacing: 16) {
    VStack(alignment: .leading, spacing: 0) {
      OverArtLabel(text: eyebrow, dot: eyebrowDot)
      [headline]   displayXL / accent / monospacedDigit / 1 line / minScale 0.7
                   .numericFact(headline)  .padding(.top, 12)
      [title]      see §6.2                 .padding(.top, headline == nil ? 12 : 8)
      [fact]       heroMeta / textSecondary / .numericFact(fact) .padding(.top, 3)
      [bar]        ProgressBar             .padding(.top, 8)
      [support]    metadata / textSecondary .padding(.top, 2)
    }
  }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
}
.buttonStyle(OverArtPressStyle())
.shadow(.art)                             // type on a photograph needs a contact shadow
.accessibilityElement(children: .combine)
.accessibilityHint("Opens the show")

if ctaEpisode != nil { actions.padding(.top, isAX ? 20 : 16) }
```

whole view `.allowsHitTesting(interactive)`.

`OverArtLabel`: `HStack(spacing: 6)` — a 5-pt `accent` circle when `dot`, then the text in
`sectionLabel` **uppercased at render time**, `foregroundStyle(textPrimary)`,
`padding(.horizontal, 10)`, `frame(height: 24)`, ground `scrimStrong` in a `Capsule()`, overlaid
with `Capsule().strokeBorder(hairline, 1)`.

`OverArtPressStyle` (used by the hero block, the account disc, the recap card and its ✕):
`opacity(isPressed ? (reduceMotion ? 0.72 : 0.88) : 1)`, `scaleEffect(reduceMotion ? 1 : (isPressed ? 0.99 : 1))`,
animated `pick(uiPress)`.
> A `surfacePressed` wash over a photograph is a grey film over someone's illustration; the art dips
> in brightness and compresses a hair instead.

`numericFact(_:)` = `contentTransition(reduceMotion ? .opacity : .numericText())` +
`animation(pick(uiNumeric), value:)`. **SwiftUI does not disable `.numericText()` under Reduce
Motion**, so the check lives in the modifier, once.

### 6.5 The one action — `MarkSplitButton`

Rendered only when `ctaEpisode != nil`, i.e. only when `behind > 0` (or the card is committed).
`ctaEpisode = committed ? committedEpisode : (behind > 0 ? nextEpisode : nil)`.

> ONE action. "Details" beside it duplicated the card's own tap; Apple TV's and Netflix's second
> button is a different verb (save / My List), never "open what you are already looking at".
> A calm hero therefore carries **no action row at all** — the art, the state and the moment, tap
> to open.

Anatomy: an `HStack(spacing: 0)` inside a `Capsule()`:

- **Left half** (`Button(onMark)`, `SplitHalfStyle`): a `DrawnCheck(on: committed, tint: accent)`
  mounted *unconditionally* and collapsed to `width: 0` when not committed, with 8 pt trailing
  padding; then `Text(committed ? "Episode N watched" : "Mark as watched")` in `button` type,
  `lineLimit(1)`, `minimumScaleFactor(0.78)`, `allowsTightening`, `contentTransition(.opacity)`.
  Ink = `committed ? accent : onAccent`. `padding(.horizontal, 20)`,
  `frame(maxWidth: .infinity, minHeight: 48)`. `allowsHitTesting(!committed)`.
- **Divider** (only when `showsMenu`): `Rectangle().fill(onAccent @ 0.18)`, `1 × 24`.
- **Right half** (only when `showsMenu = behind > 1`): a `Menu` labelled `chevron.down` at 12 pt
  semibold in `onAccent`, `frame(width: 46, height: 48)`. Menu contents, inside a `Section(title)`:
  - `Copy.Action.markThrough(from: episode, to: through)` where `through = min(episode + 4, episode + behind − 1)`,
    shown only when `through > episode` → `"Mark episodes 6⁠–⁠10 watched"` (U+2060 word joiners
    around the en dash so a narrow menu cannot break the range);
  - `Copy.Action.markAll(behind)` → `"Mark all 18 episodes as watched"`.
  Dimmed to `opacity 0.45` and accessibility-hidden while committed.
- Capsule ground: `committed ? accent @ 0.18 : accent`; overlaid with
  `Capsule().strokeBorder(LinearGradient([controlSheen, .clear], .top → .center), 1)`.
- `animation(pick(uiMicro), value: committed)`.

`DrawnCheck` is the app's signature motion: an SF `checkmark` at the given size/weight `.bold`,
masked by a leading-anchored rectangle whose width is `geo.width × progress`; `progress` animates
0 → 1 on `uiMicro` when `on` becomes true, and is **set instantly to 1 under Reduce Motion**.
> Mounted unconditionally on purpose: a conditional insert hands SwiftUI an implicit opacity
> transition *on top of* the mask and the stroke renders as a smear. The mask IS the animation.

VoiceOver labels: uncommitted `"Mark episode 19 watched, {full title}"`; committed
`"Episode 19 watched"` with the button trait removed. The chevron half is `"More ways to mark"`.

---

## 7. Trending billboard (first contact / empty account)

> **An empty account opens on television.** Apple TV's and Netflix's first screen is never a
> sentence on a black canvas; it is television with a way in.

`trendingBlock(item:screenH:topInset:)` with `item = appModel.trending.first`:

```swift
let h = heroHeight(screenH)
let cover = item.portraitArt ?? ""
let art   = !cover.isEmpty ? cover : item.landscapeArt
```

Same layer stack as the hero (ground → `StretchingHeroArt(scrimBottom: 0, portrait: !cover.isEmpty)`
→ `heroTextScrim` → copy), the same bottom-only mask, the same `HeroTopVeil`, the same
`padding(.top, -topInset)`, `zoomSource("trending/{id}")`, and the same palette `task`. It has **no**
`.transition`/`.id` (there is no card to hand over to) and **no** quick-action menu.

`TrendingFocus` copy ladder:

| Line | Value | Type |
|---|---|---|
| pill | `Copy.Label.trending` = `"Trending"`, no dot | `OverArtLabel` |
| title | `item.title.shelfShortened` | `isAX ? displayXL : heroTitle`, `lineLimit(isAX ? 3 : 2)`, minScale 0.85, `.padding(.top, 12)` |
| identity | `[source.kindWord, year].joined(" · ")` → `"Anime · 1999"` / `"TV · 2016"` | `heroMeta` / `textSecondary`, `.padding(.top, 3)` |
| action | `owned ? "In library" : "Add to Library"` | `PrimaryButtonStyle2`, `frame(maxWidth: .infinity)`, `.disabled(owned)`, `.padding(.top, isAX ? 20 : 16)` |

The copy block above the button is itself a `Button(onOpen)` with `OverArtPressStyle`,
`shadow(.art)`, combined accessibility and hint "Opens the show".

`onAdd` calls `appModel.addToLibrary(franchiseId:title:isReleasing:)` — the optimistic path: it
fires `.success`, inserts into `pendingAdds` so the capsule flips to "In library" on the tap, sets
the Undo toast (`"Added {title} to Watching"` / `"… to Planned"` — status is `.watching` when
`isReleasing`, else `.planned`), then POSTs and reloads. On failure the membership rolls back and
the failure goes to the `SyncBanner` with a Retry that re-issues exactly this add.
**An add never raises the system notification permission alert.**

### 7.1 Trending shelf

Rendered under the billboard when `trending.dropFirst().prefix(9)` is non-empty.

```
VStack(alignment: .leading, spacing: 10) {          // labelGap
  SectionHeaderRow("Trending now", action: onAddShow).padding(.horizontal, 16)
  ScrollView(.horizontal) {
    HStack(alignment: .top, spacing: 12) {          // shelfGap
      ShelfCard(title:, caption: "{kindWord} · {year}", poster: item.portraitArt,
                slot: .todayShelf, zoomID: "trending/{id}") { onOpenDetail(...) }
        .accessibilityHint("Opens the show")
    }.padding(.leading, 16).padding(.vertical, 4)
  }.scrollIndicators(.hidden).scrollClipDisabled()
}.padding(.top, 20)
```

The header walks to Search (`onAddShow`), "where the whole chart is the browse grid".

---

## 8. Calm block (caught up, nothing to mark)

Reached only when `showsHero == false` and the account is neither empty nor failed — i.e. when
`heroFranchise == nil`, which in practice means `actionable.isEmpty && calmHero == nil` (an empty
`nextUp` **and** an empty watching shelf).

```
VStack(alignment: .leading, spacing: 8) {
   Text(calmHeadline).type(heroTitle).foregroundStyle(textPrimary)
   if comingNext == nil {
      Text("No new dates have been announced.")
         .type(metadata).foregroundStyle(textSecondary).fixedSize(h: false, v: true)
   }
}
.padding(.horizontal, 16)
.padding(.top, 52 + 32)                 // headerBand + ThemeSpace.x8
.accessibilityElement(children: .combine)
```

```swift
calmHeadline = (comingNext has a nextAiring today, by its own source anchor)
             ? "New episode today"     // Copy.Progress.newEpisodeToday
             : "Caught up"             // Copy.Progress.caughtUp
```

The "today" test is `Formatting.dayDiff(ts: at, now: now, anchor: f.source.timeAnchor) == 0` — the
exact test the Upcoming row's "Today" word comes from, "so the two can never disagree."

Three deliberate absences, each recording a defect:

- **No plate.** It used to render `EmptyState(.calmToday)`: a boxed card opening the app with
  "Nothing changed since you were last here" at display size — an absence, in empty-state clothing,
  on a populated screen, restating the event the Upcoming row 60 pt below already carries with
  artwork and an amber time.
- **No glyph.** An amber check disc in the wordmark's own column read as a second lockup —
  `[amber bookmark] Previously.` mirrored 40 pt above `[amber check] Caught up`.
- **`heroTitle` (28), not `showTitleL` (22)** — a full step above the 20-pt section headers under
  it, so this reads as the page's title and those read as its sections.

> Note the composition rule from CLAUDE.md: **Today is never without a billboard.** On a calm day
> where the library still has *something*, the hero is `nextUp` (else the first Watching show) in
> the *waiting* grammar (§5, via `calmKind`) — this headline-only block is the residual case where
> even that is unavailable.

---

## 9. Skeleton

Gated by `SkeletonGate(isLoading: appModel.loading && appModel.libraryEmpty)`, which owns the whole
loading rule and must be ported as-is:

- **nothing for the first 240 ms** (a fast response never flashes structure);
- once shown, the skeleton stays **at least 320 ms** even if data lands at 250 ms;
- swap is a **120-ms crossfade** (`uiCrossfade = uiReduced`), the frame never blanks between them;
- the skeleton **breathes**: `opacity 0.88 ↔ 1.0` on `easeInOut(1.4 s).repeatForever(autoreverses)`,
  a static **0.92** under Reduce Motion. **Shimmer is refused by name.**
- a `slow` flag flips 800 ms after the skeleton appears (no visual consumer on Today).
- accessibility label `"Loading"`, children ignored.

The Today skeleton is *the shape the hero will fill*, not a generic card:

```
VStack(alignment: .leading, spacing: 0) {

  // 1. Hero band
  VStack(alignment: .leading, spacing: 0) {
     Spacer(minLength: 0)
     SkeletonLine(width:  96, height: 12)
     SkeletonLine(width: 250, height: 28).padding(.top, 14)
     SkeletonLine(width: 160, height: 14).padding(.top, 12)
     SkeletonBlock(height: 48, radius: 24).padding(.top, 18)
  }
  .padding(.horizontal, 16)
  .padding(.bottom, isAX ? 20 : 16)
  .frame(maxWidth: .infinity, alignment: .leading)
  .frame(height: heroHeight(screenH), alignment: .bottom)
  .background { ZStack {
      TodayView.rememberedTint ?? ThemeColor.ambientBackdropFallback   // #432D21
      LinearGradient([white @ 0.05, .clear], .top → .center)
  } }
  .mask(LinearGradient(stops: [ (black, 0), (black, 0.52), (black@0.72, 0.74),
                                (black@0.26, 0.90), (black@0, 1) ], .top → .bottom))
  .padding(.top, -topInset)

  // 2. Queue stand-in
  VStack(alignment: .leading, spacing: 10) {
     SkeletonLine(width: 62, height: 10)
     VStack(spacing: 0) { ForEach(0..<2) {
        SkeletonRow(poster: (isAX ? .row : .todayQueue).size, lines: [180, 110],
                    posterRadius: slot.radius)
     } }
  }.padding(.horizontal, 16).padding(.top, isAX ? 26 : 20)

  // 3. Shelf stand-in
  VStack(alignment: .leading, spacing: 10) {
     SkeletonLine(width: 84, height: 10).padding(.horizontal, 16)
     ScrollView(.horizontal) {
        SkeletonShelf(count: 4, size: PosterSize.todayShelf.size, caption: true)
           .padding(.horizontal, 16)
     }.scrollDisabled(true).scrollIndicators(.hidden)
  }.padding(.top, 30)
}
```

Three notes that are bugs if dropped:

- The hero band **must** carry the remembered tint (not `surfacePlate`, not `PaletteCache.fallback`):
  the cold fallback is the branded ember `#432D21`, because a card-ground neutral composited to
  rgb(38,36,32) and "the status area read as BLACK for the whole first load and then became flush
  when the art landed".
- The mask is **long** (the hand-over starts at 0.52). The old mask held solid to 0.86 and dropped
  inside 14 %, which at 440 pt is a 60-pt cliff — a measured hard seam.
- The shelf stand-in is wrapped in a (disabled) horizontal `ScrollView`. Four 100-pt cards plus gaps
  are 468 pt wide; in a plain stack that oversized child sets the ideal width of everything above
  it, and the **whole screen — wordmark and avatar included — got centred 14 pt to the left**.

`SkeletonRow` uses `@ScaledMetric(relativeTo: .body)` on its 88-pt minimum height, and the
`SkeletonShelf` caption/title line heights are `@ScaledMetric` mirrors of `ShelfCard`'s own type,
so the handoff lands flush at every Dynamic Type size.

---

## 10. The focus stack (ordering)

```swift
liveItems  = outNow.sorted { a, b in
                 let aw = a.effectiveStatus == .watching, bw = b.effectiveStatus == .watching
                 if aw != bw { return aw }                                   // Watching outranks
                 return (a.lastAired(now:) ?? 0) > (b.lastAired(now:) ?? 0)  // then recency
             } + keepWatching
items      = pinned ?? liveItems
actionable = items.filter { kind(of: $0) != nil }
heroFranchise = actionable.first ?? calmHero
queue      = Array(actionable.dropFirst().prefix(2))                         // queueCount = 2
stackIds   = Set(actionable.prefix(3).map(\.id))  ∪  {calmHero?.id}
```

- `calmHero` (only when `actionable.isEmpty && !libraryEmpty`) = `nextUp ?? watchingShelf.first`.
- The recency key is `lastAired(now:)` — the **airings-advanced** value — never `lastAiredSortKey`
  (the raw catalogue field), "which put a days-old Slime drop over the Re:ZERO episode that had
  struck 27 minutes earlier."
- Watching-first exists because `outNow` orders purely by recency, which handed the hero to a show
  the user had marked *completed* while five in-progress shows compressed into thumbnails below it.
- `updateCount = appModel.outNow.count`; `showsViewAll = updateCount > 3`.
- `comingNext` = `nextUp` when it is not already in `stackIds`, else `nil`.

### 10.1 `upcomingRows`

```swift
let limit = actionable.isEmpty ? 3 : 1     // one under a busy screen; three under a calm one
library.compactMap { f in
    guard f.tracksAirings, !stackIds.contains(f.id), let at = f.nextAiring(now: now) else { return nil }
    guard f.timeAnchor.isDateOnly || at > now else { return nil }
    return (f, at)
}
.sorted { $0.1 < $1.1 }.prefix(limit).map(\.0)
```

> A passed AniList slot is kept alive for the day elsewhere; here it would be announced as future.
> Date-only TV has no instant to test.

### 10.2 `shelf`

```swift
let claimed = watchingShelf.filter { !stackIds.contains($0.id) }
if claimed.count >= 3 { return Array(claimed.prefix(10)) }
// fall back to EVERY watching show not in the stack, de-duplicated, prefix 10
```

`shelfIsList = isAX || shelf.count < 3`.

> `watchingShelf` is already narrowed by a "live claim" predicate, and this narrows it again — on a
> 9-show library that left ONE card in 340 pt of dead black under a "See all", while the loading
> skeleton four seconds earlier had promised four cards running off the right edge. A horizontal
> shelf that does not reach its trailing edge gives no reason to swipe and reads as artwork that
> failed to load.

---

## 11. Below the fold

```swift
let strip    = !recapOnStage && recapMode == .strip && recap != nil
let notice   = appModel.loadError && !appModel.libraryEmpty
let hasQueue = showsHero && (!queue.isEmpty || showsViewAll)
let first       = showsHero ? (isAX ? 26 : 20) : 30      // heroClearance / x5 / sectionGap
let gap         = 30
let gapAfterRow = 30 − 8 = 22                            // a section ending in a MediaRow already
                                                         // spent `rowOwnInset` below its last row
```

| Block | Condition | `padding(.top, …)` |
|---|---|---|
| `RecapLine` | `strip` | `showsHero ? 12 : first` |
| `InlineNotice` | `notice` | `strip ? 10 : first` |
| `queueSection` | `hasQueue` | `(strip \|\| notice) ? 30 : first` |
| `upcomingSection` | `!upcoming.isEmpty` | `hasQueue ? 22 : ((strip \|\| notice) ? 30 : first)` |
| `watchingShelf` | `!shelf.isEmpty` | `(hasQueue \|\| !upcoming.isEmpty) ? 22 : ((strip \|\| notice) ? 30 : first)` |

The whole stack carries `.animation(pick(uiGentle), value: recapMode)`, and — one level up — is
faded to `opacity(0)` while `recapOnStage`, animated `pick(uiSettle)`.

> It is **not removed** while the recap is on stage. The recap is the hero's contents, not a
> takeover: hiding the rest left ~110 pt of bare canvas above the tab bar and then re-inserted
> everything on a second curve when the recap handed off — the layout shove the handoff exists to
> avoid. It is *faded* rather than left visible because the rows glowed through the gap between the
> recap's floor and the tab bar, reading as a translucent layering glitch.

**The `rowOwnInset = 8` correction.** `MediaRow` carries 8 pt of vertical padding *inside* its own
minimum height, so a container that then adds a full `labelGap`/`sectionGap` produces 8 pt more than
the token names — measured at 31 pt under a label whose token says 10, and 51–57 pt between sections
whose token says 30. **The container pays the token minus what the row already spends.**

### 11.1 `queueSection` — "Next up"

```
VStack(alignment: .leading, spacing: 0) {
   SectionHeaderRow("Next up").padding(.horizontal, 16)     // Copy.Label.nextUp
   queueRows.padding(.top, 10 − 8 = 2)                      // labelGap − rowOwnInset
}
```

`SectionHeaderRow` with no action: the title in `sectionTitle` (Outfit SemiBold 20)/`textPrimary`,
`lineLimit(1)`, `minimumScaleFactor(0.85)`, with `.isHeader` trait; no chevron, no count.

Each queue row is a `MediaRow`:

| Property | Value |
|---|---|
| `title` | `f.title` (the **full** title, not `displayTitle`) |
| `meta` | `queueMeta(f)` |
| `lead` | `queueLead(f)` |
| `poster` | `f.portraitArt` |
| `slot` | `isAX ? .row (60×90, r10) : .todayQueue (52×78, r9)` |
| `chevron` | `false` — "a disclosure indicator and a mark ring in the same column is two trailing affordances on one row" |
| `separator` | `index < queue.count − 1 \|\| showsViewAll` |
| `hint` | `"Opens the show"` |
| `zoomID` | `"queue/{id}"` |
| `trailing` | `queueMark(f)` |

plus `.franchiseQuickActions(f, appModel:)`, `.padding(.horizontal, 16)`, `.transition(handoff)`.
The row container carries `.animation(pick(uiSettle), value: queue.map(\.id))`.

**`MediaRow` anatomy** (shared): `HStack(spacing: 14)` — poster, then a
`VStack(alignment: .leading, spacing: 3)` with title (`rowTitle`, `lineLimit(isAX ? nil : 2)`),
optional `lead` (`rowMetaLead`, **accent**), optional `meta` (`rowMeta`, `textSecondary`), optional
`ProgressBar`; then `Spacer(minLength: 12)`, the trailing view, and (when `chevron`) a
`chevron.forward` at 13 pt semibold `textDisabled` in a fixed **11-pt** column.
`padding(.vertical, 8)`, `frame(minHeight: 88 for .queue/.todayQueue else 100)`, `RowPressStyle`
(radius 16; press = `surfacePressed @ 0.6` overlay + `scaleEffect 0.992`, `uiPress` in / `uiMicro`
out, no scale under Reduce Motion). Separator: 1-pt `separatorQuiet` at the bottom, inset by
`slot.width + 14`. A `dimmed` row goes to `opacity 0.72` (never 0.45 — that measured 2.64:1).
VoiceOver: label = `[title, lead, meta, progressSpoken].joined(", ")` — spelled out so the chevron
is never spoken — plus the hint.

#### The two-colour row grammar (obeyed by every row on this screen)

| Colour | Slot | Meaning |
|---|---|---|
| **amber** `rowMetaLead` | `lead` | the forward-looking TIME — "Aired yesterday", "Tomorrow at 8:30 PM" |
| **grey** `rowMeta` | `meta` | the EPISODE IDENTITY and its counts — "Season 7 · Episode 5" |

> The shipped rows swapped those two meanings between adjacent blocks, so the reader had to
> re-learn the code halfway down the screen.

`queueLead(f)`:

| Kind | Lead |
|---|---|
| `.fresh` | `TemporalCopy.aired(at: lastAired)` **only if** `now − lastAired ≤ 24 h`; otherwise `nil` |
| `.backlog`, `.caughtUp` | `nil` |
| `.waiting(at)` | `TemporalCopy.airs(at:)` |

> Amber is for what is live: today's drop. An older one is a plain row — its ring already names the
> episode, and "Aired 28 Aug" in accent spent the colour on a fact that is neither next nor now.

`queueMeta(f)`, with `ep = f.watchContext(part:, episode: part.progress + 1)` and
`roomForCount = !isAX && ep.count <= 13`:

| Kind | Meta |
|---|---|
| `.fresh(behind)` | `behind > 1 && roomForCount ? "\(ep) · \(behind(behind))" : ep` |
| `.backlog(left)` | `left > 1 && roomForCount ? "\(ep) · \(left(left))" : ep` |
| `.caughtUp` | `"Caught up"` |
| `.waiting` | `f.watchContext(part:, episode: part.nextEpisodeNumber ?? part.airedEpisodes + 1)` |

> The row DROPS a fact rather than wrapping one. **13, not 22**: at 22 a two-season identity
> ("Season 2 · Episode 2", 20 chars) still took the count and the assembled line overran the row's
> ~240 pt, wrapping "… · 11 / episodes left" mid-phrase. 13 admits the single-part form
> ("Episode 2") and nothing longer.

`queueMark(f)` — drawn only when `kind` is `.fresh` or `.backlog`:

```swift
MarkRing(marked: committedQueue.contains(f.id),
         style: .quiet,
         episode: part.progress + 1,
         label: "Mark as watched, {watchContext} of {f.title}") { markQueueRow(f) }
```

`MarkRing` geometry: a 44 × 44 target holding a 22-pt circle. `.quiet` style — no fill; ring colour
`markRingIdle` (white 34 %) when unmarked, `accent` when marked; ink `accent`; stroke 1.5 pt. The
episode numeral is drawn inside the idle ring at 9 pt semibold monospaced (7 pt when ≥ 100, omitted
at ≥ 1000) in `textSecondary`. A `DrawnCheck(on: marked, size: 12, tint: ink)` is mounted
unconditionally. `MarkPressStyle` (compression only). `animation(pick(uiMicro), value: marked)`.
Accessibility: label as given when unmarked, `"Complete"` when marked, with `.isSelected` added.

**"View all N updates"** (when `showsViewAll`): a `Button` whose label is
`HStack(spacing: 6) { Text("View all 40 updates"); Image("chevron.forward").font(.system(size: 13, weight: .semibold)) }`,
styled `InlineLinkButtonStyle` (13-pt Outfit SemiBold in `interactive`, 14 pt vertical + 12 pt
horizontal padding, `minHeight 44`, press `opacity 0.55`), pulled back with
`padding(.leading, 16 − 12 = 4)` so the word starts on the gutter.
It routes to `onViewAllUpdates` (Library filtered to *unwatched only, any status*) — **a different
destination from the shelf's "See all"** (Library filtered to Watching).

> Both used to switch to the Library root shelf, so a link that names a set ("all 40 updates")
> landed on a list that does not show it.

### 11.2 `upcomingSection` — "Upcoming"

Header `SectionHeaderRow("Upcoming")` (`Copy.Label.upcoming`), rows padded `.top, 2`.

Each row: `MediaRow(title: f.title, meta: f.releasingPart.map { watchContext(part:, episode:
$0.nextEpisodeNumber ?? $0.airedEpisodes + 1) }, lead: TemporalCopy.airs(at: f.nextAiring(now:)),
poster: f.portraitArt, slot: .queue (44×66, r8), chevron: false, separator: index < rows.count − 1,
hint: "Opens the show", zoomID: "next/{id}")` + quick actions + 16-pt horizontal padding.

> The quieter block keeps the smaller slot: nothing here is actionable, and a 56×84 poster under a
> 56×84 poster with no control beside it would give an un-actionable row the same weight as the
> queue above it.
>
> `Copy.Label.upcoming`, not "Coming next": **never a second "next" on one screen.**

### 11.3 Watching shelf

```
VStack(alignment: .leading, spacing: 10) {
   SectionHeaderRow("Watching",
                    actionLabel: shelfIsList ? nil : "See all",
                    action:      shelfIsList ? nil : onSeeAllWatching)
     .padding(.horizontal, 16)
   shelfIsList ? axWatchingList : shelfScroller
}
```

When the header has a navigating action, the **title itself is the button**: title + optional count
+ a `chevron.forward` at **14 pt semibold** in `textTertiary`, inside `SectionHeaderPressStyle`
(10 pt vertical padding, `minHeight 44`, `opacity 0.55` pressed, `pick(uiPress)`), with the row
pulled back `padding(.vertical, -10)` and given `zIndex(1)` so the overhanging target still wins
taps. VoiceOver label `"Watching, See all"`, `.isHeader`.

> Apple TV / Netflix shelf grammar: the title IS the button; there is no "See all" word for a
> navigating header. (`actionLabel` here only feeds the VoiceOver label.)

**`shelfScroller`** — `ScrollView(.horizontal)` containing `HStack(alignment: .top, spacing: 12)` of
`ShelfCard`s, `padding(.leading, 16)`, `scrollIndicators(.hidden)`, `scrollClipDisabled()`, and
`.shelfScroller()`: `contentMargins(.trailing, 40, for: .scrollContent)` plus a horizontal mask
(`black` 0 → `black` 0.86 → `black@0.45` 0.95 → `clear` 1.0) padded `-24` vertically so the mask
does not shear the cards' shadows.
> Art may run off the trailing edge; **TYPE may not.** Every shelf's last card had its title sliced
> mid-glyph by the hard screen edge ("Solo L", "Return…").

**`ShelfCard`** (slot `.todayShelf`, 100 × 150, radius 11, `.art` shadow): a `VStack(alignment:
.leading, spacing: 8)` of poster then a `VStack(spacing: 2)` of title (`shelfTitle`,
`lineLimit(1...2)` — `1...6` at AX — `minimumScaleFactor(0.82)`, `allowsTightening`, and
**`fixedSize(vertical: true)`** so a horizontal scroller cannot force it to one line) and caption
(`shelfCaption`, `lineLimit(2)`, `.tail` truncation, `accent` when `captionIsLead` else
`textSecondary`). Title is drawn as `title.shelfShortened`; the **VoiceOver label uses the whole
title**. `RowPressStyle(radius: slot.radius)`.

**`shelfCaption(f)`** — text plus whether it is a forward-looking fact (amber):

| `shelfState(of: f)` | caption | lead? |
|---|---|---|
| `.newEpisode` | `"New episode"` | **yes** |
| `.backlog` | `"Episode {resumePart.progress + 1} next"`; `nil` when there is no resume part | no |
| `.airingWait` | `TemporalCopy.airsCompact(at: nextAiring)` ("Today"/"Tomorrow"/"Friday"/"Sep 12"); `"Caught up"` if none | yes / no |
| `.premiereSoon` | `TemporalCopy.returns(at: nextPremiere(of: f))` | **yes** |
| `nil` | `"Caught up"` | no |

> Every card gets one. A dormant show reached the shelf only because the honest-count fallback
> widened it, and three captionless cards beside one that has a caption is worse than saying the
> true, quiet thing.

**`axWatchingList`** (AX sizes, or fewer than 3 cards): full-width `MediaRow`s, `slot: .queue`,
`chevron: false`, `separator: index < shelf.count − 1`, `zoomID: "shelfrow/{id}"` — deliberately a
**different id namespace from `"shelf/{id}"`**, because the same franchise must never register two
zoom sources in one namespace even when only one layout is mounted. The caption is routed into
`lead:` or `meta:` by its `lead` flag. The header drops its "See all" in this mode, "because there
is nothing more to see".

### 11.4 Inline notice

`InlineNotice(Copy.Notice.today) { Task { await appModel.reload() } }` — a **footnote line, never an
alert box**: `HStack(firstTextBaseline, spacing: 8)` of a `wifi.exclamationmark` at 12 pt semibold
in `textTertiary`, the message in `metadata`/`textSecondary`, and a `Retry` link in
`InlineLinkButtonStyle` pulled back `padding(.vertical, -12)`/`padding(.leading, -4)`.
`frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)`, `.transition(.opacity)`. At
accessibility sizes the layout switches to a `VStack(spacing: 4)` and the link's leading pull
becomes `-12`.

Message: **"Airing dates couldn't refresh"** (U+2019 apostrophe). State copy never says "server".

---

## 12. The mark timeline

### 12.1 Hero mark

```swift
func mark(_ f: Franchise) {
    guard committedEpisode == nil, !handoffInFlight else { return }
    let snapshot = items
    guard let undo = appModel.markNext(franchiseId: f.id) else { return }   // fires .commitLight
    settleHero(snapshot: snapshot, undo: undo)
}

func settleHero(snapshot:undo:) {
    pinned = snapshot
    pendingUndo = undo
    handoffInFlight = true
    withAnimation(pick(uiMicro)) { committedEpisode = undo.episode }
    Announce.status("Episode \(undo.episode) watched")
    clearRecapStrip()
    Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(650))
        withAnimation(pick(uiSettle)) { pinned = nil; committedEpisode = nil }
        completion: {
            if let undo = pendingUndo { appModel.presentUndo(undo); pendingUndo = nil }
            Task { @MainActor in
                if !reduceMotion { try? await Task.sleep(for: .milliseconds(300)) }
                handoffInFlight = false
            }
        }
    }
}
```

Timeline, in order:
1. **t=0** — local progress written optimistically, `.commitLight` haptic, `committedEpisode` set on
   `uiMicro`. The capsule shows the drawn check and reads "Episode 19 watched"; the eyebrow, fact,
   support and progress bar all advance **in the same frame** (see §6.3).
2. **t=650 ms** — `pinned`/`committedEpisode` cleared on `uiSettle`; the hero hands over to the next
   show via `handoff` (outgoing fades on `uiDismiss` 160 ms, incoming on `uiSettle` delayed 80 ms).
3. **on completion** — the Undo toast is presented (6 s; **10 s under VoiceOver**), then
   `handoffInFlight` clears 300 ms later (immediately under Reduce Motion).

`handoffInFlight` covers the window `committedEpisode` cannot:
> Without it the hero is a trap: `committedEpisode` clears at 650 ms and the next show's card fades
> in over 460 ms with its Mark button already live and hit-testable at partial opacity, so a user
> clearing three episodes has tap 2 swallowed and tap 3 land on a half-faded button belonging to a
> *different franchise* — the write goes to the wrong show and the single Undo toast only covers the
> most recent one.

`pinned` is a **snapshot of `items`** held for the 650 ms so the card keeps describing the show it
just wrote to, even though the live feed has already moved on.

### 12.2 Queue-row mark

```swift
guard !committedQueue.contains(f.id) else { return }
guard let undo = appModel.markNext(franchiseId: f.id) else { return }
withAnimation(pick(uiMicro)) { committedQueue.insert(f.id) }
appModel.presentUndo(undo)                       // immediate — no card is handing over here
Announce.status("Episode \(undo.episode) watched")
Task { try? await Task.sleep(for: .milliseconds(650)); committedQueue.remove(f.id) }
```

### 12.3 Batch mark (`promptBatch`)

Reached from the split button's menu. `count = through − part.progress`; nothing happens when
`count <= 0`. A `confirmationDialog` with `titleVisibility: .visible`:

| Slot | String |
|---|---|
| title | `"Mark 6 episodes as watched?"` |
| message | `"{f.title} · {part.label}. Your progress will move from episode 14 to episode 19."` |
| confirm | `"Mark 6 episodes as watched"` |
| cancel | `"Cancel"` (role `.cancel`) |

Confirming re-checks `committedEpisode == nil && !handoffInFlight`, snapshots `items`, calls
`appModel.markThrough(franchiseId:mediaId:episode:present: false)` (which fires `.commitMedium`
because the delta > 1, writes once, and mints one `UndoState` carrying the **true count** and a
restoring closure), then runs `settleHero` and announces the confirm string.

> Both branches now go through `markThrough`. "Mark through episode N" used to call `setProgress`,
> which mints no `UndoState` at all — so the app's most-used multi-episode control had no toast and
> no undo. "Mark all N" used to call `markCaughtUp`, which left `UndoState.count` at 1, so a
> six-episode batch reported "Episode 19 marked as watched".

`onMarkAll` passes `part.markTarget(now:)`, **not** `progressCeiling`:
> The ceiling is `Int.max` for an ongoing AniList season with no published episode count, and for
> every other releasing season it is the season's SIZE — so "Mark all 6" would have written every
> unaired episode too.

### 12.4 Write policy (inherited, must be ported)

- **A progress mark never rolls back.** A failed PUT goes to `SyncCenter.record` and the SyncBanner,
  carrying a `WriteIntent` so it can be replayed on a later launch. No red "couldn't save" toast.
- Every progress write funnels through `AppModel.sendProgress`: **one PUT in flight per part**, the
  newest target waits behind it, superseded targets are dropped — so the server always ends on the
  user's last word.
- Membership/status writes **do** roll back.
- Optimistic local copies go through `FranchisePart.withProgress`, which preserves `airings`
  (a hand-built copy once dropped them and a local mark took the show off the calendar).

### 12.5 Undo toast

Presented by `AppModel`, rendered by the shared `ToastHost` (not by this screen): a glass **capsule**
hugging its text, `ThemeRadius.toast = 18`, seated `toastClearance = 62` pt above the safe-area
bottom, `frame(maxWidth: 420)`. Message forms: `"{title} · Episode 19 watched"` (single),
`"{title} · 6 episodes watched"` (batch), `"Added {title} to Watching"` (add). Action label
`"Undo"`. In/out transition: `opacity + offset(y: 4)` on `uiSnappy` in, `opacity` on `uiDismiss`
out (pure opacity on `uiReduced` under Reduce Motion). VoiceOver hears
`"{message}. Undo available."` on presentation.

---

## 13. The Previously Recap

### 13.1 Model — `RecapBeat`

```swift
enum Kind: Equatable {
    case episodesAired(count: Int, latest: Int?)   // `latest` = highest episode that aired in-window
    case returning(at: Int64?)
    case returnDateAnnounced(at: Int64?)
}
struct RecapBeat { franchiseId, title, cover: String?, source: MediaSource, kind: Kind, score: Int }
var id: String { franchiseId + "/" + label(now: 0) }
```

`label(now:)`:

| Kind | Text |
|---|---|
| `.episodesAired(1, latest)` | `"Episode {latest} aired"` |
| `.episodesAired(n, _)` | `"{n} episodes aired"` |
| `.returning(at)` / `.returnDateAnnounced(at)` | `TemporalCopy.returns(at:now:source:)` |

> **Only genuine CHANGES inside the window belong on the recap.** `nextUp` — "where you stopped" —
> was a standing state that had not happened since anything, printed directly above the hero that
> says the same thing: the recap's job is what you missed, the hero's is what to do about it.

⚠️ **Port hazard:** `id` calls `label(now: 0)`, so a `.returning`/`.returnDateAnnounced` beat's id
embeds a **locale-formatted absolute date** ("Returns Oct 2, 2026"). The id is persisted as part of
`digestID` for acknowledgement, so on iOS changing the device locale can un-acknowledge a digest.
Reproduce the behaviour if you want byte-identical semantics, but prefer a locale-independent id on
Android and note the divergence.

### 13.2 `RecapDigest`

```swift
struct RecapDigest { let since: Int64; let beats: [RecapBeat]  /* ≤3 */; let hiddenBeatCount: Int; let score: Int }
var digestID: String { "\(since)|" + beats.map(\.id).joined(separator: ",") }
enum Presentation { case full, strip, none }

static let fullAbsence   : Int64 = 72 * H     // 3 days
static let stripAbsence  : Int64 =  8 * H
static let fullCooldown  : Int64 =  7 * D
static let returningGap  : Int64 = 30 * D
static let returningWindow: Int64 = 48 * H
static let announcedWindow: Int64 = 30 * D
```

**`build(library:since:now:)`** — returns `nil` when nothing changed:

```
guard since > 0 && since < now                                      else return nil

for f in library where f.effectiveStatus == .watching:
    guard let part = f.releasingPart else continue
    if let last = part.lastAiredAt, last > since, part.episodesBehind > 0 {
        count = min(part.episodesBehind, max(1, part.airedEpisodes − part.progress))
        newEpisodeTitles += 1
        beat .episodesAired(count: count, latest: part.airedEpisodes)
             score = (count == 1 ? 5 : 3)
        continue                                       // ← at most one beat per franchise
    }
    if let next = f.nextAiring(now:), next − now <= 48h,
       let last = part.lastAiredAt,  now − last >= 30d {
        beat .returning(at: next), score 4
    }

for f in library where f.effectiveStatus == .completed:
    if let premiere = min of f.parts.compactMap(premiereAt).filter { $0 > now },
       premiere − now <= 30d {
        beat .returnDateAnnounced(at: premiere), score 3
    }

guard !beats.isEmpty else return nil
ordered = beats.sorted { $0.score > $1.score }
score   = ordered.map(\.score).reduce(+)
if newEpisodeTitles >= 2 { score += 4 }
return RecapDigest(since:, beats: Array(ordered.prefix(3)),
                   hiddenBeatCount: max(0, ordered.count − 3), score:)
```

Note `episodesBehind` / `lastAiredAt` / `airedEpisodes` here are the **raw catalogue fields**, not
the airings-derived ones — the digest describes what changed since a past visit, not what is live
right now.

**`presentation(absence:lastFullRecapAt:acknowledgedID:now:enteredByDeepLink:)`**

```
guard !enteredByDeepLink, acknowledgedID != digestID, beats.count >= 2 else { return .none }
cooldownOK = lastFullRecapAt.map { now − $0 >= 7 days } ?? true
if absence >= 72h, score >= 4, cooldownOK { return .full }
if absence >=  8h, score >= 3             { return .strip }
return .none
```

**`demoDigest(library:since:now:)`** — DEBUG only, used by `-recapDemo 1`. Returns the real digest
when one exists; otherwise builds up to 2 beats from `watching` shows
(`.episodesAired(count: 1, latest: resumePart.progress + 1 ?? 1)`, scores 5 and 4), with
`hiddenBeatCount = max(0, candidates.count − beats.count)` and a fixed `score` of 9.

> The launch argument is documented as *forcing* the full recap so the arrival can be reviewed and
> captured, and it silently did nothing whenever the signed-in library happened to have no unwatched
> new episodes — which is most of the time on a well-kept account.

**Persistence** (`RecapState`, `UserDefaults`):

| Key | Type |
|---|---|
| `recap.acknowledgedDigestID` | `String?` |
| `recap.lastFullRecapAt` | `Int64` (0 read back as `nil`) |

### 13.3 The recap state machine on Today

View state: `recap: RecapDigest?`, `recapMode: .none/.strip/.full`, `recapOnStage: Bool`,
`recapRevealed: Bool`, `recapEvaluated: Bool`, `recapClockStarted: Bool`.

**`evaluateRecap()`** — runs on `.onAppear` and whenever `loading` flips false:

```swift
guard !appModel.loading, !recapEvaluated, !appModel.library.isEmpty else { return }
recapEvaluated = true
let demo  = RecapState.demo                              // UserDefaults["recapDemo"]
let since = demo ? now − 400 × Formatting.D : appModel.prevOpenedAt
let built = demo ? RecapDigest.demoDigest(...) : RecapDigest.build(...)
guard let digest = built else { recap = nil; recapMode = .none; return }
let mode = demo ? .full : digest.presentation(absence: now − since,
                                              lastFullRecapAt: RecapState.lastFullRecapAt,
                                              acknowledgedID: RecapState.acknowledgedID,
                                              now: now, enteredByDeepLink: false)
recap = digest; recapMode = mode
if mode == .full {
    var t = Transaction(); t.disablesAnimations = true
    withTransaction(t) { recapOnStage = true; recapRevealed = false }   // NO animation: it must be
    startRecapClock()                                                   // the first thing on screen
}
```

The **400-day** demo window is deliberate: 30 days was not wide enough to guarantee a digest on a
library whose latest change is older than that, and the flag is DEBUG-only.

**`startRecapClock()`** — the reveal/hold clock only starts once the surface is actually visible:

```swift
guard recapOnStage, appModel.surfaceReady, !recapClockStarted else { return }
recapClockStarted = true
Task { @MainActor in
    try? await Task.sleep(for: .milliseconds(60))
    withAnimation(pick(uiReveal)) { recapRevealed = true }
    Announce.screenChanged(recapSpokenSummary(recap))
    guard !voiceOver else { return }              // ← VoiceOver NEVER auto-dismisses
    try? await Task.sleep(for: .milliseconds(holdMilliseconds))
    handoffRecap()
}
```

```swift
var holdMilliseconds: Int {
    let beats  = max(1, recap?.beats.count ?? 1)
    let reveal = reduceMotion ? 0 : Int(120 × Double(beats + 1))
    return reveal + min(4500, 1400 + 300 × beats) + (reduceMotion ? 600 : 0)
}
```

Worked values (Reduce Motion off): 2 beats → 360 + 2000 = **2360 ms**; 3 beats → 480 + 2300 =
**2780 ms**. With Reduce Motion: 2 beats → 0 + 2000 + 600 = **2600 ms**.

> Two accessibility rules the shipped clock had backwards. **VoiceOver never auto-dismisses** — a
> user got roughly one element spoken before the card was removed from the tree. **Reduce Motion
> holds LONGER**, not shorter (it used to cut the hold from 2,000 ms to 1,600): *less movement is
> not less reading time*, and the two settings that most need time were both given less.
> The hold is measured **from the last beat's reveal** and scales with what there is to read.

**`stageRecap()`** (the strip was tapped): resets `recapRevealed`/`recapClockStarted`, sets
`recapOnStage = true` inside `withAnimation(pick(uiSettle))`, and starts the clock.

**`handoffRecap()`** — recap → focus, in **ONE** move:

```swift
guard recapOnStage else { return }
let next: Presentation = (recapMode == .full) ? .strip : .none
withAnimation(pick(uiSettle)) { recapOnStage = false; recapMode = next }
completion: { persistRecapAcknowledgement() }
```

> It used to be two: the hero shrank and settled (460 ms), and only in that animation's completion
> did `acknowledgeRecap()` set `recapMode = .strip` inside a *second* `withAnimation`, inserting a
> 44-pt strip that shoved everything under it down ~60 pt on another 220 ms curve. The screen
> appeared to finish and then jumped. Only the persistence — which animates nothing — is left for
> afterwards.

**`dismissRecap()`** (the ✕): identical, but `recapMode = .none`.
> Dismiss means gone: no strip, nothing to come back to on this visit. The ✕ used to call
> `onContinue()`, so it demoted the card to the strip and it reappeared 460 ms later.

**`persistRecapAcknowledgement()`**: sets `acknowledgedID = digest.digestID` and
`lastFullRecapAt = now` — skipped entirely under `-recapDemo`.

**`clearRecapStrip()`**: if `recapMode == .strip`, persist the acknowledgement and set `.none`.
Called on `.onDisappear`, on `scenePhase == .background`, and inside `settleHero`.

### 13.4 `RecapArrival` (the full card, in the hero frame)

Occupies `screenH − 84`. Layer stack is the hero's, with `scrimBottom: 1.9` on the art — "its copy
fills the frame and the whole image is meant to step back."

`VStack(alignment: .leading, spacing: 0)`:

1. **Header row** — `HStack(alignment: .top)`:
   - `OverArtLabel("While you were away")` (uppercased at render).
   - `Spacer(minLength: 12)`
   - **✕**: `ZStack { Circle().fill(scrimStrong); Circle().strokeBorder(posterEdge, 1);
     Image("xmark").font(.system(size: 13, weight: .semibold)).foregroundStyle(textPrimary) }`
     at `30 × 30` inside a `44 × 44` frame, `contentShape(Circle())`, `OverArtPressStyle`,
     `accessibilityLabel("Dismiss what you missed")`, `padding(.trailing, -10)`, `padding(.top, -8)`.
     > 22 pt of low-contrast glyph was the only way out of a full-screen takeover — and it called
     > `onContinue`.
2. **Headline** — `displayL` (Outfit Bold 28) / `textPrimary`, `lineLimit(2)`,
   `minimumScaleFactor(0.85)`, `.padding(.top, 12)`:
   ```swift
   let aired = Σ over beats of episodesAired.count
   let total = beats.count + hiddenBeatCount
   aired > 0 ? "\(Copy.episodes(aired)) aired"      // "5 episodes aired"
             : "\(Copy.updates(total)) waiting"     // "3 updates waiting"
   ```
3. **Window line** — `Copy.Recap.sinceYourLastVisit(TemporalCopy.since(digest.since, now:))`:
   `"Since your last visit, 23 Jul"` (the helper strips a leading `"Since "` from the phrase before
   interpolating). `metadata` / `textSecondary`, `.padding(.top, 2)`.
   > "Since 23 Jul" named a date with no anchor — since what?
4. **The beats card** — the **whole card is the `Continue` button** (`Button(onContinue)`,
   `OverArtPressStyle`, `.padding(.top, 20)`):
   ```
   VStack(alignment: .leading, spacing: 12) {
     ForEach(beats.enumerated()) { i, beat in
        HStack(spacing: 12) {
           if showsPoster { PosterSlot(url: beat.cover, .beat) }      // 34 × 51, radius 6
           VStack(alignment: .leading, spacing: 3) {
              HStack(alignment: .firstTextBaseline, spacing: 8) {
                 Text(beat.title).type(rowTitle).foregroundStyle(textPrimary).lineLimit(2)
                 Spacer(minLength: 8)
                 if i == 0 { Image("chevron.forward").font(.system(size: 13, weight: .semibold))
                                 .foregroundStyle(textDisabled) }
              }
              Text(beatLabel(beat)).type(rowMeta).foregroundStyle(textSecondary).lineLimit(1)
           }
        }
        .opacity(revealed ? 1 : 0)
        .offset(y: revealed || reduceMotion ? 0 : 6)
        .animation(pick(uiReveal).delay(reduceMotion ? 0 : 0.12 × Double(i + 1)), value: revealed)
     }
     if hiddenBeatCount > 0 {
        Text("and \(hiddenBeatCount) more").type(metadata).foregroundStyle(textTertiary)
           .opacity(revealed ? 1 : 0)
           .animation(pick(uiReveal).delay(reduceMotion ? 0 : 0.12 × Double(beats.count + 1)), value: revealed)
     }
   }
   .padding(16)
   .frame(maxWidth: .infinity, alignment: .topLeading)
   .surface(.art(tint), radius: ThemeRadius.focusCard /* 24 */)
   ```
   `.surface(.art(tint))` = an art-adaptive ground (the palette of `beats.first?.cover`, resolved at
   `maxPixel: 360`) with a **top-edge-only** hairline highlight (`LinearGradient([hairline, .clear],
   .top → .center)`, 1 pt) and a `.card` shadow — **never a full-perimeter stroke**; the recap was
   the one surface in the app overriding that rule.
   Whole card: `accessibilityElement(children: .combine)`,
   `accessibilityLabel(beats.map { "\($0.title), \(beatLabel($0))" }.joined(separator: ". "))`,
   `accessibilityHint("Continues to what is next")`.
5. Whole `VStack` carries `.shadow(.art)`.

**Both beat titles are `textPrimary`** — the second used to be `textSecondary` and read as disabled;
the aired-vs-upcoming distinction lives in the meta line.

**`showsPoster`**:
```swift
guard beats.count == 1, hiddenBeatCount == 0 else { return true }
guard let cover = beats.first?.cover, let heroArt else { return true }
return cover != heroArt
```
> A single-title recap laid on that title's own key visual at 440 pt printed the SAME image again at
> 34 × 51 about 200 pt below it — a postage stamp of the picture above it.

In practice this only fires under `-recapDemo` on a one-show library, because `presentation`
requires `beats.count >= 2`.

**`beatLabel(_:)`** (supplied by `TodayView`, resolved against the live library):
```swift
guard case .episodesAired(let n, let latest) = beat.kind, n == 1, let latest,
      let f = library.first(where: { $0.id == beat.franchiseId }),
      let part = f.releasingPart ?? f.resumePart
else { return beat.label(now: now) }
return "\(f.watchContext(part: part, episode: latest)) aired"     // "Season 4 · Episode 19 aired"
```
> `RecapBeat.label` prints "Episode 19 aired" with no season, while the hero for that exact episode
> said "Season 4 · Episode 19" 200 pt above it — one screen, two ways of naming one thing.

### 13.5 `RecapLine` (the strip)

On the **canvas**, not in a box:

```
Button(stageRecap) {
  HStack(alignment: .firstTextBaseline, spacing: 8) {
     Image("clock.arrow.circlepath").font(.system(size: 13, weight: .semibold))
        .foregroundStyle(textSecondary)
     Text(text).type(metadataEmphasis).foregroundStyle(textPrimary).lineLimit(2)
     Image("chevron.forward").font(.system(size: 13, weight: .semibold))
        .foregroundStyle(textDisabled)
     Spacer(minLength: 0)
  }
  .frame(minHeight: 44, alignment: .center).frame(maxWidth: .infinity, alignment: .leading)
  .contentShape(Rectangle())
}
.buttonStyle(RowPressStyle())
.accessibilityLabel(text).accessibilityHint("Opens what you missed")
```

Mounted with `.transition(.opacity)` and tucked at `padding(.top, 12)` under a hero
> (x3, not the section gap): the line is the hero's residue, and at full section distance it floated
> in the dead zone between hero and queue reading as a stray debug print.

**`recapStripText(_:)`**:
```swift
let aired = Σ episodesAired.count
let since = sinceFragment(recap.since)              // "since 23 Jul" / "since yesterday" / …
aired > 0 ? "\(Copy.episodes(aired)) aired \(since)"                       // "5 episodes aired since 23 Jul"
          : "\(Copy.updates(beats.count + hiddenBeatCount)) \(since)"      // "3 updates since 23 Jul"
```

`sinceFragment(ts)` takes `TemporalCopy.since` ("Since Tuesday" / "Since Aug 12" / "Since earlier
today" / "Since yesterday") and replaces only the leading word: `"since " + remainder`.
> Lower-casing the whole phrase produced "1 episode aired since 23 **jul**": a month abbreviation is
> a proper noun and does not follow the sentence.

`recapSpokenSummary` = `"While you were away. {strip text}."` — announced via
`Announce.screenChanged` when the arrival reveals.

---

## 14. Feeds with no consumer on Today (do not port UI for them)

- **`AppModel.nowBarItem` ("the Now Bar")** — a `{franchiseId, state: .live/.next, at}` triple that
  mirrors the Live Activity's "one soonest episode" model. `.live` = the freshest unwatched drop
  within `nowBarLiveWindow` (24 h; same-day for date-only TV), else `.next` = the soonest scheduled
  airing, else `nil`. **Nothing on Today renders it** in the current build — the hero absorbed its
  job (the pill's recency, the amber clock headline, the dot). Keep the derivation if the Android
  port ports Live Activities/ongoing notifications; do not add a strip.
  > "Today must not nag with an idle strip."
- **`AppModel.soon` ("Airing soon", 48 h)** — no consumer. The `Upcoming` section (§11.2) is built
  from `upcomingRows`, which walks the whole library, not from `soon`.
- **"Out now"** survives only as the `outNow` feed: it seeds `liveItems` (hero + queue) and supplies
  `updateCount` for "View all N updates". There is no section with that title.

---

## 15. Navigation and callbacks

| Callback | Wired in `RootView` to |
|---|---|
| `onOpenDetail(franchiseId, zoomID)` | push `DetailRoute` on the **Today** tab's `NavigationPath` |
| `onSeeAllWatching()` | Library, filtered to `status: .watching` |
| `onViewAllUpdates()` | Library, filtered `status: nil, unwatchedOnly: true` — deliberately **not** pinned to Watching, because `updateCount` counts `outNow` (any status) |
| `onOpenLibrary(status)` | Library, filtered to that status (used by the Profile sheet) |
| `onAddShow()` | `appModel.searchFieldRequested = true`; select the Discover tab |

Zoom-source ids registered by this screen (all currently **inert** — `.zoom` transitions were tried
2 Sep and retired 3 Sep; `matchedTransitionSource` registrations remain but nothing consumes them):
`focus/{id}`, `focus/recap`, `queue/{id}`, `next/{id}`, `shelf/{id}`, `shelfrow/{id}`,
`trending/{id}`, `profile/{id}`. Detail is a **plain push**.

The screen is wrapped in `pageInTransition(isActive:)`: a once-per-tab entrance —
`opacity 0 → 1` with a **6-pt** rise on `uiReveal`; under Reduce Motion a pure crossfade, nothing
travels. It never replays on a later tab switch.

Long-press anywhere on the hero, a queue row, an upcoming row or a shelf card opens
`franchiseQuickActions` (a context menu): `Mark all N episodes as watched` (only when
`releasingPart.episodesBehind > 0`), the five statuses with a `checkmark` on the current one
(`Watching / Planned / Watched / Paused / Dropped`, glyphs `play.circle / clock /
checkmark.circle / pause.circle / xmark.circle`), a divider, then a destructive
`Remove from Library`.

---

## 16. Debug launch arguments

Read as `UserDefaults.standard.bool(forKey:)` (iOS maps `-flag 1` launch arguments into
`NSUserDefaults`), all `#if DEBUG`:

| Argument | Effect |
|---|---|
| `-recapDemo 1` | `RecapState.demo == true`: the recap window becomes `now − 400 days`, `demoDigest` is used when the real build yields nothing, `presentation` is bypassed (mode forced to `.full`), and the acknowledgement is **never persisted** — so it fires on every launch. |
| `-calmDemo 1` | `liveItems` returns `[]`, so the focus stack is empty and the **calm open renders on a library that still has backlog**. |
| `-openProfile 1` | Presents the Profile sheet on appear. |

Other arguments the app honours that land on this screen: `-openTab today`, `-openDetail <id>`
(the alert-tap route).

---

## 17. Accessibility summary

| Area | Behaviour |
|---|---|
| **VoiceOver, hero** | The whole copy block is one element (`children: .combine`) with hint "Opens the show". The mark capsule is a separate element: `"Mark episode 19 watched, {full title}"` → `"Episode 19 watched"` (button trait removed) once committed. The menu half is "More ways to mark", hidden while committed. |
| **VoiceOver, bar** | `ProgressBar` is hidden unless a `spoken` string is supplied; the hero passes `"4 episodes behind"` / `"3 episodes left"`. |
| **VoiceOver, rows** | `MediaRow` spells its label as `title, lead, meta` so the chevron is never spoken; the hint is "Opens the show". `MarkRing` reads its unmarked label (`"Mark as watched, Season 4 · Episode 12 of {title}"`) or `"Complete"` with `.isSelected`. |
| **VoiceOver, announcements** | `"Refreshing"` when a pull starts; `"Episode N watched"` on every mark; `"{toast message}. Undo available."` when the toast lands; `ScreenChanged("While you were away. 5 episodes aired since 23 Jul.")` when the recap reveals; `"Mark 6 episodes as watched"` after a batch confirm. Skeleton reads `"Loading"`. |
| **VoiceOver, recap** | **The recap never auto-dismisses under VoiceOver** — the clock returns before the hold; the card waits for `Continue`. |
| **Dynamic Type** | Outfit tokens scale via `relativeTo:`; SF tokens are system styles. At accessibility sizes (`typeSize.isAccessibilitySize`): the hero title becomes `displayXL` with 3 lines; the art band minimum grows 132 → **210**; hero bottom padding 16 → 20; the action row's top padding 16 → 20; the progress bar goes full width; the queue's poster slot grows `.todayQueue` → `.row`; the first below-fold gap becomes `heroClearance` (26); the Watching shelf becomes a vertical list and loses "See all"; queue meta drops its count unconditionally (`roomForCount` is false); `InlineNotice` stacks vertically; `ShelfCard` titles allow up to 6 lines and take the full row width; `EmptyState` buttons stop hugging. **`heroHeight` grows by the copy's measured overflow, so there is one fraction at every type size.** |
| **Reduce Motion** | Every animation resolves to `uiReduced` (easeOut 0.12) through `pick`. The `handoff` becomes a plain opacity crossfade with no delay. The **drift is off**. `DrawnCheck` is instantly at full width. `numericFact` crossfades instead of rolling digits. Press styles use opacity, never scale. Recap beats do not offset (no 6-pt rise) and their stagger delay is 0. The recap **hold is 600 ms longer**, and its reveal component is 0. `handoffInFlight` clears with no 300 ms wait. The page-in entrance does not travel. Skeleton breath is a static 0.92. |
| **Reduce Transparency** | `ScrollEdgeChrome` drops the `.ultraThinMaterial` entirely and paints an **opaque** canvas bar (bar factor 1.0 instead of 0.74). |
| **Differentiate Without Color** | Provided app-wide by `DifferentiateMark` (a shape carrier drawn only when the setting is on). Today's amber-only encodings — the pill dot, an amber `lead` caption — currently rely on the hero's own words; carry `DifferentiateMark` over if you add colour-only state. |
| **Haptics toggle** | `UserDefaults["previously.haptics"]`, default on; system settings remain authoritative. |
| **Targets** | Every control is ≥ 44 pt: the account disc (34-pt art in a 44-pt frame), `MarkRing` (22-pt ring in a 44-pt frame), the recap ✕ (30-pt disc in a 44-pt frame), inline links (padded to `minHeight 44`), section headers (padded then pulled back with `zIndex(1)` so the overhang still wins taps). |

---

## 18. String inventory (verbatim, with interpolation shape)

Curly apostrophes are U+2019. `\u{00A0}` is a non-breaking space; `\u{2060}` a word joiner;
`\u{b7}` the middle dot `·`.

| Symbol | String |
|---|---|
| `Copy.episode(n)` | `"Episode {n}"` |
| `Copy.episodes(n)` | `"{n}\u{00A0}episode"` / `"{n}\u{00A0}episodes"` |
| `Copy.updates(n)` | `"{n}\u{00A0}update"` / `"{n}\u{00A0}updates"` |
| `Copy.watchContext(part:episode:)` | `"Season 4 · Episode 19"` (a `Season N:` prefix is compacted to `Season N`; other labels keep their subtitle) |
| `Copy.Label.nextUp` | `"Next up"` |
| `Copy.Label.upcoming` | `"Upcoming"` |
| `Copy.Label.watching` | `"Watching"` |
| `Copy.Label.newEpisode` | `"New episode"` |
| `Copy.Label.trending` | `"Trending"` |
| `Copy.Search.trendingNow` | `"Trending now"` |
| `Copy.Search.addToLibrary` / `.inLibrary` | `"Add to Library"` / `"In library"` |
| `Copy.Action.seeAll` | `"See all"` |
| `Copy.Action.viewAllUpdates(n)` | `"View all {n} updates"` |
| `Copy.Action.markAsWatched` | `"Mark as watched"` |
| `Copy.Action.markEpisodeWatched(n)` | `"Mark episode {n} watched"` |
| `Copy.Action.markThrough(from:to:)` | `"Mark episodes {a}\u{2060}–\u{2060}{b} watched"`, or `"Mark episode {b} watched"` when `from >= to` |
| `Copy.Action.markAll(n)` | `"Mark all {n} episodes as watched"` |
| `Copy.Action.undo` / `.retry` / `.cancel` | `"Undo"` / `"Retry"` / `"Cancel"` |
| `Copy.Progress.behind(n)` | `"{n}\u{00A0}episodes\u{00A0}behind"` |
| `Copy.Progress.left(n)` | `"{n}\u{00A0}episodes\u{00A0}left"` |
| `Copy.Progress.caughtUp` | `"Caught up"` |
| `Copy.Progress.caughtUpAfterThisEpisode` | `"Caught up after this episode"` |
| `Copy.Progress.lastEpisodeOfTheSeason` | `"Last episode of the season"` |
| `Copy.Progress.newEpisodeToday` | `"New episode today"` |
| `Copy.Progress.noNewDates` | `"No new dates have been announced."` |
| `Copy.Progress.episodeNext(n)` | `"Episode {n} next"` |
| `Copy.Progress.episodeWatched(n)` | `"Episode {n} watched"` |
| `Copy.Confirm.batchMarkTitle(n)` | `"Mark {n} episodes as watched?"` |
| `Copy.Confirm.batchMarkMessage(from:to:)` | `"Your progress will move from episode {a} to episode {b}."` |
| `Copy.Confirm.batchMarkConfirm(n)` | `"Mark {n} episodes as watched"` |
| `Copy.Notice.today` | `"Airing dates couldn’t refresh"` |
| `Copy.Recap.whileYouWereAway` | `"While you were away"` |
| `Copy.Recap.sinceYourLastVisit(p)` | `"Since your last visit, {p minus a leading \"Since \"}"` |
| `Copy.Action.dismissRecap` | `"Dismiss what you missed"` |
| `Copy.Action.continueLabel` | `"Continue"` (referenced by `TodayCopy`; the card is the button, so the word is not currently drawn) |
| `Copy.Accessibility.opensTheShowHint` | `"Opens the show"` |
| `Copy.Accessibility.loading` / `.refreshing` / `.complete` | `"Loading"` / `"Refreshing"` / `"Complete"` |
| recap in-line | `"and {n} more"`, `"Continues to what is next"`, `"Opens what you missed"` |
| header | `"Profile"`, `"Previously"` (wordmark VoiceOver), `"Previously."` (drawn) |
| `EmptyStateCopy.emptyToday` | symbol `tv` · `"Nothing to watch yet"` · `"Add a show and this screen fills in with what is next."` · `"Add a show"` |
| `EmptyStateCopy.serverNoCache` | symbol `exclamationmark.circle` · `"Couldn’t load your library"` · `"Something went wrong. Try again in a moment."` · `"Try again"` |
| `EmptyStateCopy.offlineNoData` | symbol `wifi.slash` · `"You’re offline"` · `"Connect to the internet to load your library."` · `"Try again"` |

### 18.1 Temporal phrase ladders

`TemporalCopy.airs(at:now:source:)` — AniList (timed):
`"Airs in {m} min"` (0 < Δ < 60 min) · `"Today at 8:30 PM"` · `"Tomorrow at 8:30 PM"` ·
`"{Weekday} at 8:30 PM"` (dayDiff 2…6) · `"Aug 28 at 8:30 PM"` / `"Aug 28, 2027 at 8:30 PM"`.
TMDB (date-only): `"Today"` · `"Tomorrow"` · `"{Weekday}"` · `"Aug 28"` / `"Aug 28, 2027"`.

`TemporalCopy.airsCompact` — **drops the clock, never the day word**: `"Today"` · `"Tomorrow"` ·
`"{Weekday}"` · `"Aug 28"`.

`TemporalCopy.aired(at:now:source:)` — AniList: `"Aired just now"` (< 5 min) ·
`"Aired {m} min ago"` (< 60 min) · `"Aired {h}h ago"` (same day) · `"Aired yesterday"` ·
`"Aired {Weekday}"` (2…6 days) · `"Aired Aug 19"`. TMDB: `"Aired today"` then the same day ladder.

`TemporalCopy.returns(at:now:source:)` — `"No date announced"` (nil) · `"Returned Jul 5"` (past) ·
`"Returns today"` · `"Returns tomorrow"` · `"Returns {Weekday}"` · `"Returns Oct 2"`.

`TemporalCopy.since(ts:now:)` — `"Since earlier today"` · `"Since yesterday"` ·
`"Since {Weekday}"` · `"Since Aug 12"`.

`Formatting.fmtCountdown` — `"now"` (< 1 min) · `"{m}m"` · `"{h}h {m}m"` · `"{d}d {h}h"`.

`Formatting.fmtTime` — the locale's **short time style**, so a 24-hour device reads `"21:00"`; it
returns `""` for a date-only anchor.

**Two calendars.** Every day word, day diff and clock is read in the source's own `TimeAnchor`:
`.local` for AniList (a real instant), `.utcDate` for TMDB (a date-only fact the server carries as a
synthesized 17:00 UTC instant). Breaking a TMDB timestamp down locally pushes every timezone east of
UTC+7 one day forward — a Sunday drop reads "Monday" in JST. `dayDiff` compares
`localDayKey(ts, anchor:)` against `localDayKey(now, .local)`, both normalised to midnight-UTC keys.

---

## 19. Android reproduction risks

Ordered roughly by how much work each represents.

| Item | Why it is hard on Android | Severity |
|---|---|---|
| **SF Symbols** (`chevron.forward`, `xmark`, `clock.arrow.circlepath`, `tv`, `wifi.slash`, `wifi.exclamationmark`, `exclamationmark.circle`, `checkmark`, `photo`, `play.circle`, `clock`, `checkmark.circle`, `pause.circle`, `xmark.circle`, `trash`, `text.append`) | No equivalent family. Material Symbols differ in optical weight and metrics; the 13-pt semibold chevron and the 44-pt tertiary empty-state glyph are tuned to SF's proportions. Substitute per-glyph and re-tune sizes against a screenshot. | moderate |
| **`.ultraThinMaterial` backdrop blur in the scroll-edge chrome** | Compose has no first-class live backdrop blur below API 31; `RenderEffect`/`HazeChild` works on 31+ at real cost, and older devices need the Reduce-Transparency path (opaque canvas at 1.0) as the default. The **0.74-over-blur** rule is the whole point of the bar and cannot be approximated by a flat 74 % scrim without losing the "content stays faintly alive" reading. | hard |
| **`.matchedTransitionSource` / `.zoom` navigation** | Currently inert on this screen (retired 3 Sep). Do **not** port; Detail is a plain push. The `zoomID` strings can be dropped or kept as analytics keys. | easy |
| **Live Activities / Dynamic Island** | Not applicable to Today itself (`nowBarItem` has no consumer here). If ported at all, it becomes an ongoing notification and the "one soonest episode" model still holds. | blocker (feature parity), but out of scope for this screen |
| **`onGeometryChange` belt-and-braces scroll probes** | Compose gives one source of truth (`LazyListState`/`ScrollState`), so the double probe is unnecessary — but the *reason* it exists (the offset must not invalidate the screen) must be honoured with `derivedStateOf` or a lambda-read `graphicsLayer`. Getting this wrong reproduces the exact 60–120 Hz recomposition storm the iOS code was rewritten to kill. | moderate |
| **Measured-copy-driven scrim + hero height** (`heroCopyHeight`, `heroCopyUnderBand`) | Requires a measure-then-draw pass (`SubcomposeLayout` or an `onGloballyPositioned` + state write). A naive `onGloballyPositioned` write inside the same composition causes a second frame; keep the value in a `MutableState` read only by the scrim and the height calculation, exactly as iOS does. Note the comment: "the copy's height depends only on the width, never on this, so there is no layout cycle" — preserve that invariant. | moderate |
| **`confirmationDialog`** (batch mark) | Maps to a Material `AlertDialog`; iOS's action-sheet ordering (destructive-ish confirm first, then Cancel) inverts on Android. Keep the strings; adopt Android button placement. | easy |
| **Context menu on long-press** | `contextMenu` has no direct Compose analogue with the same preview-lift affordance. A `DropdownMenu` anchored at the touch point is the closest; the *lifted card preview* is not reproducible without custom work. | moderate |
| **`Outfit` variable font + `tracking` + `minimumScaleFactor`** | Outfit ships as a Google font, so the family is fine. `tracking` maps to `letterSpacing` (note: iOS tracking is in points, Compose is in `sp`/`em` — convert as `pt / fontSize` em). **`minimumScaleFactor` has no Compose equivalent**: you need `AutoSizeText`/`TextAutoSize` (Compose 1.8+) or a manual measure loop. Six places on this screen depend on it (0.7, 0.78, 0.82, 0.85 twice, 0.85). | moderate |
| **`allowsTightening`** | No equivalent; drop it and rely on auto-sizing. | easy |
| **`contentTransition(.numericText())`** (the rolling digits on the hero headline and fact) | No built-in. Reproduce with `AnimatedContent` + per-character `slideInVertically`/`slideOutVertically` keyed on the digit, or accept a crossfade (which is what Reduce Motion already does — so the fallback is already specified). | moderate |
| **`DrawnCheck`'s left-to-right mask** | Easy in Compose (`drawWithContent` + `clipRect` on an animated width), **but** carry over the warning: the check must be mounted unconditionally and animated only by the mask; an enter/exit transition on top of it renders as a smear. | easy |
| **`Menu` inside a capsule (`MarkSplitButton`)** | The split control (a 48-pt capsule containing two independent 44-pt targets with a 1 × 24 divider and per-half press states) needs a custom composable; `SplitHalfStyle`'s "only the half under the finger darkens" is the detail that makes the divider honest. | moderate |
| **`@ScaledMetric`** (empty-state glyph, skeleton row height, skeleton shelf line heights) | Compose has no direct analogue; derive from `LocalDensity.fontScale`. Required, or the skeleton→content swap jumps at large font sizes. | easy |
| **`UIAccessibility.isVoiceOverRunning` / `AccessibilityNotification`** | TalkBack: use `AccessibilityManager.isTouchExplorationEnabled` and `View.announceForAccessibility` / `LiveRegionMode`. The **VoiceOver-never-auto-dismisses** rule for the recap must be gated on touch exploration. | easy |
| **`accessibilityReduceMotion` / `ReduceTransparency`** | Android exposes `Settings.Global.TRANSITION_ANIMATION_SCALE == 0` (and `ANIMATOR_DURATION_SCALE`) for reduced motion; there is **no** Reduce Transparency setting — decide once whether to bind the opaque-bar path to a high-contrast setting or to an in-app toggle. | moderate |
| **Haptics** | `UIImpactFeedbackGenerator(style:intensity:)` maps imperfectly. Closest: `HapticFeedbackConstants.CONFIRM` / `REJECT` / `SEGMENT_TICK`, or `VibrationEffect.createPredefined(EFFECT_CLICK/EFFECT_HEAVY_CLICK)` with amplitude. The **per-token throttle (0.04 s for selection, 0.3 s otherwise) and the "never while inactive" rule must be ported verbatim** — they are what keeps a batch mark to one buzz. | moderate |
| **`refreshable` + arm-at-threshold haptic** | `PullToRefreshBox` gives the gesture; the "fire once at 80 pt **while a finger is down**, re-arm below 0.3×" rule needs the raw pull offset plus a drag-in-progress flag, because a momentum overshoot must not buzz. | moderate |
| **Palette extraction (`PaletteCache`)** | `androidx.palette` is the analogue; it will not produce identical colours. The important behaviours are: resolve at `maxPixel 360`, use the result as the hero's persistent ground, and **persist the last hero tint across launches** for the skeleton. | easy |
| **Cross-launch `UserDefaults`** | `DataStore`/`SharedPreferences`. Keys: `today.heroTint` (`[Double]`), `recap.acknowledgedDigestID` (`String`), `recap.lastFullRecapAt` (`Long`), `previously.haptics` (`Bool`). | easy |
| **Locale-formatted date inside `RecapBeat.id`** | See §13.1 — reproduce or deliberately diverge, but decide consciously. | easy |
| **Two calendars (`TimeAnchor`)** | `java.time` with a fixed `ZoneOffset.UTC` for `.utcDate` and the device zone for `.local`. The day-key normalisation (midnight-UTC epoch-ms of the day read in the anchor's zone) must be ported exactly or TMDB rows drift a day. | moderate |
| **Non-breaking spaces and word joiners in copy** | Preserve ` ` and `⁠` in the Android string resources; Compose respects them. Dropping them reintroduces "… · 11 / episodes left" wrapping. | easy |
| **`contentMargins(.bottom, …, for: .scrollContent)`** | Compose: `contentPadding` on the `LazyColumn`. The iOS note — that `padding` inside the stack does nothing when the content is shorter than the viewport — does not apply, so `contentPadding` is simply correct. | easy |
| **`scrollClipDisabled()` + oversized shelf mask** | Compose clips by default; to let shelf card shadows escape you need `clip = false` on the container plus a horizontal fade via `graphicsLayer { compositingStrategy = Offscreen }` + `drawWithContent` blend. The vertical `-24` mask padding exists precisely to stop the fade shearing the shadows. | moderate |

---

## 20. Invariants an Android reviewer should check

1. The scroll offset never recomposes the screen — only the veil and the hero art.
2. The hero is present in every non-empty, non-failed state; there is no headline-only screen while
   a billboard is available.
3. Exactly one amber *word* above the fold, and it is a fact (the clock), never an action.
4. The hero states exactly one episode; the capsule says "Mark as watched" without repeating it.
5. The mark's committed frame advances the eyebrow, fact, support and bar **in the same frame** as
   the button label.
6. No tap can land on a card that is still arriving (`handoffInFlight`).
7. The recap demotes to a strip on `Continue` and disappears entirely on ✕; leaving the screen
   clears the strip and persists the acknowledgement.
8. The recap never auto-dismisses under TalkBack.
9. Reduce Motion **lengthens** the recap hold.
10. Section rhythm uses the token minus 8 pt after any block that ends in a media row.
