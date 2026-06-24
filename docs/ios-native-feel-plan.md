# AniTrack iOS — Native-Feel Pass

**Goal:** Make the app *feel* like a premium native iOS 26 app without redesigning the
screens. Keep the current layouts and the franchise/airing-first product. Replace the
hand-rolled, web-derived UX scaffolding with the real system primitives so the app gets
native motion, gestures, accessibility, and haptics "for free."

**Constraints (agreed):**
- Lean into iOS 26 / Liquid Glass as the foundation (use native components, not hand-built ones).
- Keep existing screen layouts (Today / Schedule / Library / Add / Detail).
- Dark-only stays for this pass; light mode is out of scope (revisit later).
- Keep the iOS 17–25 fallbacks that already exist in `GlassHelpers.swift`.

The order below is by leverage: the things that change "feel" most per line of code come first.

---

## Workstream 1 — Native navigation (highest leverage)

**Problem.** `MainTabView` (RootView.swift:68–88) is a `ZStack` of four always-mounted views
toggled by `.opacity` + `.allowsHitTesting`, under a custom `FloatingTabBar`. Detail is a
`.sheet` (RootView.swift:100). This forfeits everything good about iOS navigation and is the
single biggest reason it "feels webby."

**Change.**
1. Replace the ZStack + `FloatingTabBar` with a native `TabView` using the `Tab` API.
   - On iOS 26 this gives the native floating, morphing glass tab bar + scroll-edge effects
     automatically — i.e. the thing `FloatingTabBar` was hand-approximating, but correct.
   - Free wins: tap-tab-to-scroll-to-top, reselect-to-pop, keyboard avoidance, accessibility,
     correct safe-area insets.
2. Give each tab its own `NavigationStack`.
3. Convert franchise **detail from a sheet to a push**: `.navigationDestination(for:)` driven
   by a per-tab path instead of the global `appModel.detailRoute` sheet.
4. Remove the manual bottom-padding hacks (`.padding(.bottom, 120)` in Today/Schedule/Library,
   RootView toast `.padding(.bottom, 96)`) — native TabView manages content insets, and content
   correctly scrolls *under* the glass bar.

**Files:** `RootView.swift` (rewrite `MainTabView`, delete `FloatingTabBar`/`TabBarItem`),
`AppModel.swift` (replace `detailRoute` with navigation paths or a routing enum),
all four feature views (the `onOpenDetail` closure now appends to a path),
`FranchiseDetailView.swift` (drop the custom dismiss; use native back — see WS2).

**Risk:** Medium. Touches routing app-wide. The `AppTab` enum, icons, and labels carry over
1:1, so the surface change is contained to how content is hosted.

---

## Workstream 2 — Push detail + zoom transition (the "premium" moment)

**Problem.** Tapping a poster pops a modal sheet. On iOS, drilling into content should *push*,
and the thing you tapped should visually *become* the next screen.

**Change.**
1. With detail now a push (WS1), add the zoom/shared-element transition:
   - `.matchedTransitionSource(id:in:)` on `PosterCard` / rows (the tapped art).
   - `.navigationTransition(.zoom(sourceID:in:))` on `FranchiseDetailView`.
   - The tapped poster expands into the detail hero. This is ~4 lines and is the highest
     visual-payoff change in the app.
2. Replace the custom `GlassCircleButton(chevron.left)` back button
   (FranchiseDetailView.swift hero) with the native back button / swipe-back-to-dismiss.
   Keep the parallax banner hero art; just let the system own the back affordance.
3. Because detail is now in a stack, detail→related→detail navigation becomes possible later
   (not built now, but unblocked).

**Files:** `PosterCard.swift`, `BriefingHeroCards.swift`, row builders in
`TodayView`/`ScheduleView`/`LibraryView`/`DiscoverView`, `FranchiseDetailView.swift`.

**Risk:** Low–Medium. Depends on WS1. `.zoom` transition is iOS 18+; pre-18 falls back to a
normal push automatically (acceptable).

---

## Workstream 3 — Haptics everywhere (highest ROI, lowest risk)

**Problem.** Zero haptics in the codebase. This is ~half of "feels tactile and premium."

**Change.** Use SwiftUI's native `.sensoryFeedback(_:trigger:)` (iOS 17+), wired to existing
state changes:
- Tab change → `.selection`
- Mark caught up → `.success` (pairs with the existing `CaughtUpOverlay` celebration)
- Episode stepper +/- → `.increase` / `.decrease` (or `.impact(weight:.light)`)
- Add to library → `.success`
- Status segmented control change → `.selection`
- Undo fired → `.impact`
- Pull-to-refresh completion → `.success`

**Files:** A small `Haptics`/sensory-feedback helper, then attach at each interaction site
(`PosterCard`, `BriefingHeroCards`, `FranchiseDetailView` steppers/status, tab bar, `UndoToast`).

**Risk:** Very low. Additive.

---

## Workstream 4 — Monospaced *digits* instead of monospaced *font*

**Problem.** `Theme.mono` (SF Mono) is used for all countdowns, counts, times, dates. It reads
as a developer tool / web dashboard, not a warm consumer app.

**Change.** Switch those call sites to SF Pro with `.monospacedDigit()` so only the ticking
digits are fixed-width (no jitter) while the type stays native. Keep `Theme.mono` available but
stop using it for body/countdown text. Affects countdowns, "Ep N", air times, progress counts,
the Today date header (TodayView.swift:65), Schedule rows, detail airing callout.

**Files:** `Theme.swift` (add a `numeric` font token), then replace `Theme.mono(...)` usages.

**Risk:** Low. Visual-only, no layout change of note.

---

## Workstream 5 — Dynamic Type & semantic typography (phased)

**Problem.** Every font is a fixed point size (`.font(.system(size: 14.5))`) with manual
`.tracking(...)`. This is CSS thinking: no Dynamic Type (accessibility fails) and it fights the
system. This is the most pervasive "non-native" tell after navigation.

**Change (phased so layouts don't break):**
1. Add a typography layer to `Theme` mapping the current sizes to Dynamic Type via
   `.font(.system(size:weight:relativeTo:))` so text scales with the user's setting while
   preserving the current default look.
2. Constrain with `.dynamicTypeSize(...DynamicTypeSize.accessibility1)` where dense layouts
   would otherwise break.
3. Migrate file-by-file (Today → Detail → Schedule → Library → Discover), verifying each at the
   default size matches today's design before moving on.

**Files:** `Theme.swift` + incremental across all views.

**Risk:** Medium (breadth). Mitigated by phasing and by anchoring on "looks identical at default
size." Could be split into its own PR after WS1–4 land.

---

## Workstream 6 — Native gestures: context menus + pull-to-refresh

**Problem.** Everything is tap-a-custom-button. No long-press quick actions, no pull-to-refresh.

**Change.**
1. `.refreshable { await appModel.reload() }` on the Today / Library / Schedule scroll views.
2. `.contextMenu` on poster cards and rows: quick "Mark caught up", "Watching / Completed /
   Plan to watch", "Remove from library" — the same actions as detail, one long-press away.
3. *(Optional / larger)* Swipe actions (swipe-to-mark-caught-up on the Airing-soon and Library
   rows) require those sections to become `List` rows rather than custom `Button`s in a
   `LazyVGrid`/`VStack`. Flagged as a follow-up because it's a structural change to those
   sections, not a drop-in.

**Files:** `TodayView.swift`, `LibraryView.swift`, `ScheduleView.swift`, `PosterCard.swift`.

**Risk:** Low for refresh + context menus; Medium for swipe actions (deferred).

---

## Workstream 7 — Commit to one Today layout (product call — recommended)

**Problem.** The Briefing/Spotlight/Grid toggle (TodayView.swift:100–125) is indecision shipped
as a feature, and it puts a settings-y control at the top of the app's emotional hero moment
("what dropped for me since you were last here").

**Change.** Pick one layout and delete the toggle. Recommendation: keep **Briefing** as the
single home layout (it's the default and the most feed-like). This is technically a layout edit,
so it's flagged separately from the "keep layouts" constraint — include only if you agree.

**Files:** `TodayView.swift` (remove `HomeLayout`, `layoutToggle`, the `switch`),
possibly retire `HeroCard` from `BriefingHeroCards.swift` if unused.

**Risk:** Low. Pure removal. Product decision, not a technical one.

---

## Suggested sequencing (PRs)

1. **PR 1 — Navigation rebuild:** WS1 + WS2 together (native TabView, push detail, zoom
   transition). Biggest single feel improvement; everything else sits on top.
2. **PR 2 — Tactility:** WS3 (haptics) + WS4 (monospaced digits) + WS6 refresh/context menus.
   Small, high-delight, low-risk.
3. **PR 3 — Accessibility:** WS5 (Dynamic Type / semantic typography), phased and verified.
4. **Optional:** WS7 (single Today layout) folded into PR 1 or PR 2; swipe-actions follow-up.

## Progress

- **PR 1 — Navigation rebuild — DONE** (compiles clean on the iOS 26 SDK). Native `TabView`,
  per-tab `NavigationStack`, franchise detail as a push with the zoom transition, custom tab bar
  + sheet routing removed, Today layout toggle deleted.
- **PR 2 — Tactility — DONE** (compiles clean). Haptics via a central `Haptics` helper wired into
  mark-caught-up / stepper / add / status / undo, plus `.sensoryFeedback(.selection)` on tab
  change; `Theme.numeric` (SF Pro + `monospacedDigit`) replacing SF Mono everywhere; pull-to-
  refresh on Today/Schedule/Library/Discover; long-press context menus (status / mark caught up /
  remove, or add-to-library in Discover).
- **PR 3 — Accessibility (Dynamic Type) — DONE** (compiles clean). New `scaledFont` modifier
  (`@ScaledMetric`-backed: pixel-identical at the default text size, grows at accessibility
  sizes); every literal `.font(.system(size:))` / `Theme.numeric` call site migrated to it
  (SF Symbol glyph sizes left fixed); app-root ceiling of `.accessibility2` so dense grids
  degrade gracefully.
- **Follow-up — swipe actions** (needs row sections moved to `List`) — TODO.

All three PRs verified with `xcodebuild build` (BUILD SUCCEEDED); not yet run in a simulator for a
visual/tactile check. Dynamic Type is identical-by-construction at the default size, so the only
thing needing eyes there is how the densest layouts (poster grids, schedule rows) hold up at the
larger accessibility steps.

## Explicitly out of scope for this pass
- Art-forward visual redesign / new card designs (that's the "beauty pass").
- Surfacing unused data (scores, season/year, "N behind", popularity).
- Light mode.
- Server / data-model changes.
