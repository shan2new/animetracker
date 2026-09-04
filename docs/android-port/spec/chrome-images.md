# Chrome shims, scroll-edge behaviour, image pipeline, transitions

This document specifies the four cross-cutting subsystems that sit *underneath* every screen of
Previously.: (1) the **iOS-26 chrome shims** — a handful of one-line wrappers that let the app use
Liquid Glass, scroll-edge effects and tab-bar minimisation on iOS 26 while compiling and running
correctly against the iOS 18 deployment floor; (2) the **hand-rolled scroll-edge chrome**, which is
what actually draws the app's status-bar and tab-bar edges on every screen on every OS version — a
per-screen gradient veil plus a masked blur whose exact ramp is the single most-iterated detail in
the codebase; (3) the **image pipeline** — a bespoke `NSCache` + ImageIO decoder (there is *no*
Nuke, no SDWebImage, no third-party image library anywhere in the project; the brief that called it
"Nuke-based" is wrong) keyed on `(url, size-bucket)` with a strict serve-larger-never-smaller rule;
and (4) the **transition helpers** — the once-per-tab page-in entrance, the retired-but-still-wired
zoom source registry, and the asymmetric handoff/toast transitions. Nothing here draws a single
user-facing string: this whole subsystem is decoration, and every layer in it is explicitly hidden
from the accessibility tree. Its job is that content never scrolls through the clock, art never
flashes, and a recycled cell never re-decodes.

**Source files (all under `ios/`)**

| File | Lines | What it owns |
|---|---|---|
| `Sources/DesignSystem/GlassHelpers.swift` | 126 | The five iOS-26 availability shims + `ChromeEdge` |
| `Sources/DesignSystem/ImageLoader.swift` | 215 | `downsampleImage`, `ImageCache`, `ImageLoader`, `CachedAsyncImage` |
| `Sources/DesignSystem/RemoteImageView.swift` | 55 | `RemoteImageView`, `GradientPlaceholder`, `Thumb` |
| `Sources/DesignSystem/PageTransition.swift` | 52 | `PageInTransition` / `.pageInTransition(isActive:travel:)` |
| `Sources/DesignSystem/ZoomTransition.swift` | 30 | `zoomNamespace` environment entry, `.zoomSource(_:)` |

Three tightly-coupled pieces live in neighbouring files and are specified here because the five
files above are meaningless without them: `ScrollEdgeChrome` + `ScrollEdgeChromeModifier` +
`ScrollOffset` + `ChromeGlassBox` (`Sources/DesignSystem/Primitives.swift`), the `ThemeMetrics`
chrome tokens (`Sources/DesignSystem/ThemeTokens.swift`), and `PaletteCache` / `ArtBackdrop`
(`Sources/DesignSystem/Palette.swift`), which shares the image cache.

---

## 0. Ground rules this subsystem exists to enforce

Quoted from `Primitives.swift`, `ScrollEdgeChrome`:

> The single most damaging detail in the shipped build is invisible in a design tool and obvious on
> a device: **content scrolls straight through the status bar**. On Schedule a poster and a
> truncated show title sit on top of the clock; on Library a poster crosses the Dynamic Island. No
> shipping media app does this, and no amount of card polish survives it.

And from `CLAUDE.md` (2026-09-03):

> **Bars are MATERIAL to their bottom edge.** … "hardened" means `ThemeMetrics.chromeBarOpacity`
> (0.74) canvas over the full-strength blur, NEVER opaque canvas (only Reduce Transparency, which
> has no blur, gets the opaque bar): at 1.0 the top ~100 pt of every scrolled screen was a flat
> #09090B slab ("pure black", 3 Sep) with the material under it painted for nothing.

Three invariants follow, and an Android port that breaks any of them is wrong even if it compiles:

1. **A bar is opaque to its bottom edge and content is either under it or not.** The only soft part
   is a 28-pt edge below the bar. Never a 120–150 pt wash.
2. **A hardened bar is translucent (0.74) over a full-strength blur.** Only when the platform
   cannot blur does it become fully opaque.
3. **The scroll offset is never screen state.** It lives in a small observable object read by two
   or three tiny views, never by a screen body.

---

## 1. The iOS 26 chrome shims (`GlassHelpers.swift`)

### 1.1 Why the file exists

Deployment target is **iOS 18.0** (`project.yml` → `deploymentTarget: iOS: "18.0"`, Swift 6.0). Every
iOS 26 API is gated behind `if #available(iOS 26.0, *)`, **never removed**. Screens are forbidden
from calling an iOS 26 symbol directly; they call a shim here.

`ChromeEdge` is a local enum, not Apple's edge type, and the reason is a hard compiler constraint
worth understanding before porting:

> Ours rather than Apple's on purpose: the `for:` parameter of `scrollEdgeEffectHidden` and
> `scrollEdgeEffectStyle` takes an iOS 26 type, and a function signature that names one cannot
> compile against an iOS 18 deployment target — even if every call is inside an availability check.
> The mapping onto Apple's type happens in the bodies below, where the symbol is legal.

```swift
enum ChromeEdge { case all, top, bottom }
```

This constraint has **no Android analogue** — Kotlin has no equivalent of "a type that cannot appear
in a signature below API N". The enum should still be kept as a plain `enum class ChromeEdge` for
call-site parity, but the reason is documentation only.

### 1.2 The five shims

| Shim | iOS 26 behaviour | iOS 18 fallback | Call sites | Android |
|---|---|---|---|---|
| `View.glassChrome(in:interactive:)` | `.glassEffect(.regular, in: shape)`; `.regular.interactive()` when `interactive == true` | `.background(.ultraThinMaterial, in: shape)` | Only via `chromeGlass` (see 1.3) | **Hard** — see 1.4 |
| `View.chromeScrollEdgeHidden(_ edge:)` | `scrollEdgeEffectHidden(true, for: .all/.top/.bottom)` | `self` (exact no-op) | `scrollEdgeChrome()` (`.all`), `pushedScreenChrome()` (`.bottom`), Schedule/Discover/Library/LibraryAll (`.all`), Detail (`.top`) | **N/A** — Android draws no system scroll-edge effect, so this is a no-op there too |
| `View.chromeScrollEdgeHard(_ edge:)` | `scrollEdgeEffectStyle(.hard, for: …)` | `self` (no-op) | `ProfileView` only, `.top` | **N/A** — no system effect to harden |
| `View.chromeTabBarMinimizeOnScroll()` | `tabBarMinimizeBehavior(.onScrollDown)` | `self` (bar stays put) | `MainTabView`, once | **Moderate** — hand-rolled `NestedScrollConnection` |
| `ToolbarContent.chromeSharedBackgroundHidden()` | `.sharedBackgroundVisibility(.hidden)` | `self` | 7 sites (see below) | **N/A** — Compose toolbar actions have no glass capsule |
| `View.chromeNavigationSubtitle(_:)` | `navigationSubtitle(subtitle)` | drops the line entirely | `WatchHistoryView` only | **Easy** — two-line title slot in the **app-drawn** bar. **ERRATUM (2026-09-04, PLAN §3.1/§9.2): not an M3 `TopAppBar`**, which is banned — it stacks a second uncontrolled scroll-hardening layer (`containerColor → scrolledContainerColor`) on `ScrollEdgeChrome` and types its title from `MaterialTheme.typography`. |

`chromeSharedBackgroundHidden()` call sites, all of which are "a bare word or a bare glyph in a
toolbar": Library's *N titles* count action, Library's refresh spinner (`Primitives+States.swift`
:1070), Detail's `.principal` docked title, Profile's *Done*, Rewatch sheet's *Cancel*, Watch-history
sheet's *Done*. The comment names the exact defect it fixes: iOS 26 renders `rgb(26,27,29)` behind a
word on an `rgb(13,14,17)` sheet, and for an invisible spinner it draws "an empty disc beside the
title".

**One shim is deliberately not a shim.** `ToolbarSpacer` is gated *inline* in Detail's toolbar
because it is a `ToolbarContent` **value**, not a modifier, so it cannot be wrapped:

```swift
if #available(iOS 26.0, *) {
    ToolbarSpacer(.fixed, placement: .topBarTrailing)
}
```

Its purpose: split Detail's status pill and overflow `···` into **two glass capsules** rather than
one shared capsule containing two inner materials ("three materials in one cluster, with a visible
seam mid-capsule … reads as a rendering bug"). On Android this is simply two separate `IconButton`s
with a spacer between them — trivially reproducible, and the visual bug never arises.

### 1.3 `chromeGlass` — the one sanctioned entry to glass

`glassChrome` is **not** called from screens. The single sanctioned entry point is
`View.chromeGlass(in:interactive:)` (Primitives.swift:1350), which routes through `ChromeGlassBox`
so it can read the accessibility environment:

| `accessibilityReduceTransparency` | Rendering |
|---|---|
| `false` | `content.glassChrome(in: shape, interactive:)` → Liquid Glass (26) or `.ultraThinMaterial` (18) |
| `true` | `content.background(ThemeColor.surfaceFloating, in: shape)` **plus** `shape.stroke(ThemeColor.strokeStrong, lineWidth: 1)` — opaque `#2A2D36` with a 20 %-white 1-pt border, no refraction |

Three call sites, all chrome, never content: `ToastView` (`Capsule()`), `SyncBanner`
(`Capsule()`), and the Rewatch sheet's bottom action bar (`Rectangle()`, the one raw material in
`Features/`, converted specifically because it ignored Reduce Transparency).

The file's own scope rule, verbatim:

> Glass is applied ONLY to the navigation/functional chrome (tab bar, toolbars, sheet headers,
> floating action buttons, the "mark caught up" buttons, chips) — never stacked on poster/content
> cards. Adjacent glass elements should be wrapped in a `GlassEffectContainer` by the caller.

`GlassCircleButton`, `glassTinted`, `GlassGroup` and the `buttonStyleGlass` pair were **deleted** in
the 30-Aug cohesion pass (zero call sites each). Do not re-introduce equivalents on Android.

### 1.4 What the Android equivalent of each blur/material surface must achieve visually

There are exactly **three** distinct blurred surfaces in the app. Reproduce the *look*, not the API.

| Surface | iOS construction | Visual target on Android | Difficulty |
|---|---|---|---|
| **Chrome glass** (toast, sync banner, rewatch action bar) | Liquid Glass / `.ultraThinMaterial` behind a `Capsule`/`Rectangle` | A pill that reads as *frosted, lit, and above* the content: a ~20–24 dp Gaussian blur of what is behind it, lifted ~8 % toward white, with a 5.5 %-white top-edge hairline and `ShadowToken.floating` (black 50 %, radius 26, y 14). If a real backdrop blur is unobtainable, fall through to the Reduce-Transparency recipe (`#2A2D36` + 20 %-white 1-dp stroke) — that path is already designed and shipping. | **Hard** for true backdrop blur (`Modifier.blur` blurs the composable's own content, not what is behind it; you need a `GraphicsLayer` capture of the scroll content, or the `haze` library). The fallback is **easy**. |
| **Scroll-edge material band** (top/bottom veils) | `Rectangle().fill(.ultraThinMaterial).mask(blurMask)` under a `LinearGradient` veil | A band in which content dissolving into the bar goes soft *before* it goes dark — the blur must ramp out at *exactly* the same place the veil does, or there is "a visible seam straight across the screen — which is precisely what a hand-rolled scroll edge looks like". | **Hard** — needs a blurred snapshot of the scroll content, masked by a vertical alpha gradient (`drawWithContent { drawContent(); drawRect(mask, blendMode = DstIn) }`) |
| **Composited-cover ground** (`ArtHeader(portraitSource:)`, `LandscapeArt(portraitSource:)`) | `RemoteImageView(...).blur(radius: 48 or 28, opaque: true)` + `Color.black.opacity(0.28 / 0.32)` | A blurred, opaque copy of the poster filling the frame behind a whole, unscaled copy of the same poster. This one blurs **an image, not a backdrop**, so it is fully reproducible. Note the ground is fetched at a deliberately tiny `maxPixel` (1024 for the hero, **160** for a card) — most of the "blur" is already free upscaling. | **Easy** — `Modifier.blur` (API 31+) over a small-decoded bitmap; below 31, the 160-px decode upscaled is already close enough, add a `RenderScript`-replacement or accept it |

If Android cannot do a *backdrop* blur in a given surface, **use the Reduce-Transparency branch,
not a translucent scrim with no blur**. The comment on `chromeBarOpacity` is explicit that a 74 %
veil with nothing softening beneath it is the exact defect the hardened bar was built to end.

---

## 2. Chrome tokens (`ThemeMetrics`, `ThemeColor`)

Every number below is used by the scroll-edge system. No screen may invent its own.

| Token | Value | Meaning |
|---|---|---|
| `ThemeColor.canvas` | `#09090B` | App ground |
| `ThemeColor.chromeVeil` | `= canvas` (`#09090B`) | The veil colour, so "content does not slide *under a grey bar*, it dissolves into the app" |
| `ThemeColor.surfaceFloating` | `#2A2D36` | Reduce-Transparency glass replacement |
| `ThemeColor.strokeStrong` | white 20 % | Its border |
| `ThemeColor.scrim` / `scrimStrong` | black 56 % / 72 % | Over-art protection |
| `ThemeColor.hairline` | white 5.5 % | 1-px top-edge highlight |
| `ThemeColor.posterEdge` | white 9 % | The edge of artwork — never `stroke` (12 %) |
| `ThemeMetrics.topSafeInset` | measured; **59** fallback | See 2.1 |
| `ThemeMetrics.topChromeRamp` | **22** | How far below the status bar a default veil disappears |
| `ThemeMetrics.topChromeHeight` | `topSafeInset + 22` | Default top veil height |
| `ThemeMetrics.inlineBarHeight` | **44** | System inline navigation bar |
| `ThemeMetrics.inlineBarBottom` | `topSafeInset + 44` | The bar's full band |
| `ThemeMetrics.barEdgeRamp` | **28** | The ramp under a *hardened* top veil |
| `ThemeMetrics.chromeBarOpacity` | **0.74** | Hardened canvas over the material |
| `ThemeMetrics.searchDrawerHeight` | **52** | System search drawer under an inline title |
| `ThemeMetrics.bottomChromeHeight` | **64** | Bottom ramp — the tab pill's own height |
| `ThemeMetrics.bottomUnderfill` | **180** | Solid canvas drawn *past* the layout's bottom edge |
| `ThemeMetrics.tabBarClearance` | `64 + 12 = 76` | Bottom scroll-content margin |
| `ThemeMetrics.tabBarVisualHeight` | **90** | Pill + home-indicator strip; the divisor for optically centring an empty state (**not** `tabBarClearance` — using the latter pushed every empty state ~81 pt above true centre) |
| `ThemeMetrics.toastClearance` | **62** | Toast inset above the safe area |
| `ThemeMetrics.rootWashHeight` | **320** | The one ambient-wash height, app-wide |
| `ThemeMetrics.rootWashIntensity` | **0.4** | The one ambient-wash strength |
| `ThemeMetrics.gutter` | **16** | Screen side margin |

### 2.1 `topSafeInset` and `windowHeight` — read from the window, cached once

Both are `static var`s backed by `nonisolated(unsafe)` caches:

```swift
static var topSafeInset: CGFloat {
    if let cachedTopInset { return cachedTopInset }
    guard Thread.isMainThread else { return 59 }
    // foregroundActive window scene → key window → safeAreaInsets.top, else 0
    return inset > 0 ? inset : 59       // and only a real measurement is cached
}
```

Non-obvious and load-bearing: **a `GeometryReader` cannot supply this.** "The chrome is an OVERLAY
on a view that already sits inside the safe area, so its proxy reports an inset of zero. Reading the
window is the honest way to know how tall the band the clock lives in actually is." The 59 pre-window
fallback (the modern Dynamic Island default) is deliberately **not** cached, so it cannot become
permanent. `windowHeight` follows the identical pattern with an **852** fallback, and exists because
"billboard heroes are sized as a fraction of the SCREEN (status bar included), which no
`GeometryReader` inside a navigation stack can report".

**Android:** `WindowInsets.statusBars` via `WindowInsetsCompat` gives the same fact and *can* be read
from composition, so no window-scraping hack is needed. Do not hard-code 59: Android status bars run
~24–48 dp, and the derived band heights below must be computed from the real inset.

### 2.2 `ScrollOffset` — the scroll offset is never screen state

```swift
@Observable @MainActor
final class ScrollOffset {
    private(set) var y: CGFloat = 0
    func set(_ raw: CGFloat) { let v = ThemeMetrics.scrollSample(raw); if v != y { y = v } }
    var veilOpacity: Double { Double(min(1, max(0, (y - 16) / 64))) }   // 0 at ≤16 pt, 1 at ≥80 pt
    var stretch: CGFloat { max(0, -y) }                                  // pull-down, as extra art height
}

static func scrollSample(_ y: CGFloat, floor: CGFloat = -320, ceiling: CGFloat = 240) -> CGFloat {
    (min(max(y, floor), ceiling) * 2).rounded() / 2                      // clamp, then round to ½ pt
}
```

Why: "Every veil, mask and title handover in the app saturates within the first ~120 pt of scroll and
the pull-down stretch within ~300 pt; past that the offset changes nothing on screen. Writing the raw
offset to `@State` on every frame re-evaluated Today's whole body … at 60–120 Hz for the entire
length of the scroll, which is the jank the user felt (2 Sep)." Held in `@State` on Today and Detail;
read inside a `body` **only** by `TodayVeils`, `DetailVeils` and `StretchingHeroArt`.

**Android:** the same discipline is required and the mechanism is different. Hoist the offset into a
`MutableState<Float>` owned by the screen but read only inside the veil composables (or, better, a
`derivedStateOf`/lambda-based `Modifier.drawBehind` so the read happens at draw time, not
composition). Clamp to `[-320, 240]` and round to 0.5 dp exactly as above; the deduplication is what
stops recomposition, not the clamp alone. Boolean probes (`raisedTop`, `scrolledUnderBar`,
`heroCopyUnderBand`) are guarded with `if new != old` at every site.

---

## 3. `ScrollEdgeChrome` — the veil, exactly

`ScrollEdgeChrome(side:height:soft:holdHeight:)` is one view with three rendering modes. It is
**always** `allowsHitTesting(false)` + `accessibilityHidden(true)`, `.frame(maxWidth: .infinity)`,
and `.ignoresSafeArea(edges: side == .top ? .top : .bottom)`.

### 3.1 Parameters

| Parameter | Default | Meaning |
|---|---|---|
| `side` | — | `.top` or `.bottom` |
| `height` | `ThemeMetrics.topChromeHeight` | Top only: total height, safe area **included** |
| `soft` | `false` | Top only: no solid hold; a translucent gradient only (Apple Music Search's at-rest edge) |
| `holdHeight` | `nil` → `topSafeInset` | Top only: how far down full canvas holds before the ramp starts |

Derived:

```swift
private var hold: CGFloat { max(0, min(1, (holdHeight ?? ThemeMetrics.topSafeInset) / max(height, 1))) }
```

`hold` is a **fraction of `height`**, i.e. a gradient stop location, not a length.

### 3.2 Gradient stops — the canvas veil

All colours are `ThemeColor.chromeVeil` (`#09090B`) at the stated opacity. `startPoint: .top`,
`endPoint: .bottom`.

**Top, soft** (at rest, artwork visible to the screen's top edge):

| Stop | Opacity | Location |
|---|---|---|
| 0 | 0.55 | 0.0 |
| 1 | 0.30 | 0.5 |
| 2 | 0.00 | 1.0 |

**Top, hard** (`bar = reduceTransparency ? 1.0 : 0.74`):

| Stop | Opacity | Location |
|---|---|---|
| 0 | `bar` | 0.0 |
| 1 | `bar` | `hold` |
| 2 | `bar * 0.45` | `hold + (1 - hold) * 0.45` |
| 3 | 0.00 | 1.0 |

**Bottom** (fixed; `height` is ignored, the band is always `bottomChromeHeight`):

| Stop | Opacity | Location |
|---|---|---|
| 0 | 0.00 | 0.00 |
| 1 | 0.25 | 0.55 |
| 2 | 0.75 | 0.85 |
| 3 | 1.00 | 1.00 |

The bottom stops carry the most expensive history in the file, and the reasoning must survive the
port verbatim:

> Capping at 0.78 left the Liquid Glass rim with un-occluded body copy to refract, and the bar duly
> mirrored it back as legible upside-down text (a second amber "Read more" on Detail, a doubled show
> title on Search) — a frame that reads as GPU corruption. Glass needs opaque canvas underneath it,
> not a 78 % veil. Going the other way and reaching full canvas at 0.86 of *140 pt* solved the
> refraction by erasing the content: a `See all` link at 1.42:1 and a live `+` button at 131/241, at
> rest, with nothing scrolled. Both failures are the same mistake — the band's HEIGHT — so the stops
> stay hard and the band is now the pill's own height.
>
> Held flat to 0.44 (≈28 pt above the pill) so nothing in the last readable line is touched at all,
> then a fast run to opaque.

### 3.3 Gradient stops — the blur mask

The `.ultraThinMaterial` rectangle is masked by a **second** gradient that "runs out on exactly the
same ramp as the veil, and reaches zero at the same place. A mask that terminates while the veil is
still at a third leaves a visible seam straight across the screen."

**Top, soft:** black 0.6 @ 0 → black 0.3 @ 0.5 → clear @ 1.
**Top, hard:** black 1.0 @ 0 → black 1.0 @ `hold` → black 0.42 @ `hold + (1-hold)*0.45` → clear @ 1.
Full strength through the *whole* hold, because "the bar is translucent now, so the blur is what
keeps a row title under it from reading as a row title".
**Bottom:** clear @ 0 → black 0.30 @ 0.55 → black 0.75 @ 0.85 → black @ 1. Re-stopped *with* the
veil: "a blur that keeps lifting where the veil has already stopped is a second, invisible ramp — and
it was the half that was actually measured softening live body copy 137 pt above the bar."

### 3.4 Composition

```swift
private var band: some View {
    ZStack {
        if !reduceTransparency { Rectangle().fill(.ultraThinMaterial).mask(blurMask) }
        veil
    }
}
```

Blur under, canvas veil over. Under Reduce Transparency the material is dropped **and** the top-hard
veil's `bar` goes to 1.0, so the opaque bar does the whole job.

Top: `band.frame(height: height)`.

Bottom (the underfill trick, which is subtle and must be copied exactly):

```swift
VStack(spacing: 0) {
    band.frame(height: ThemeMetrics.bottomChromeHeight)   // 64
    ThemeColor.chromeVeil.frame(height: ThemeMetrics.bottomUnderfill)  // 180 solid canvas
}
.offset(y: ThemeMetrics.bottomUnderfill)                  // push the whole thing down 180
```

Mounted as `.overlay(alignment: .bottom)`. Net geometry: the 244-pt stack is bottom-aligned inside
the container, then offset +180, so the **64-pt ramp's bottom edge lands exactly on the container's
bottom edge** (= the tab bar's top edge, because a `TabView` insets its children's safe area by the
bar) and **180 pt of solid canvas continues below it**, behind the tab bar and across the
home-indicator strip. The rationale:

> A `TabView` insets its children's safe area by the bar, so a `.bottom`-aligned overlay's bottom
> edge is the bar's TOP edge, not the screen's — and `ignoresSafeArea` can only give that overlay
> back the window's own 34-pt inset, never the bar's height on top of it. That gap is exactly
> consequence (b): content rendering at full brightness underneath the bar (236/255 on Library
> against 59 one row above it) with live chevrons in the home-indicator strip. Over-drawing past the
> layout's edge is the only honest fix; the tab bar is drawn by the `TabView` above its children, so
> this passes underneath it and gives its glass an opaque ground to refract.

**Android:** a Compose `Scaffold` with a `NavigationBar` behaves the same way (content is inset by
the bar), so the identical over-draw is needed: put the veil in a `Box` that fills the content area,
align it bottom, and give it `Modifier.height(244.dp).offset(y = 180.dp)` — or simply draw it in the
Scaffold's root `Box` *below* the `NavigationBar` in z-order with no inset consumption. Verify with a
screenshot that no chevron is legible in the gesture-nav strip.

### 3.5 `ScrollEdgeChromeModifier` — the soft ⇄ hard cross-fade

```swift
content
  .overlay(alignment: .bottom) { if bottom { ScrollEdgeChrome(side: .bottom) } }
  .overlay(alignment: .top) {
      if top {
          if softTop {
              let hold = topHold ?? ThemeMetrics.topSafeInset
              ZStack(alignment: .top) {
                  ScrollEdgeChrome(side: .top, height: topHeight, soft: true)
                      .opacity(topRaised ? 0 : 1)
                  ScrollEdgeChrome(side: .top, height: hold + ThemeMetrics.barEdgeRamp,
                                   soft: false, holdHeight: hold)
                      .opacity(topRaised ? 1 : 0)
              }
              .animation(ThemeMotion.uiGentle, value: topRaised)
          } else {
              ScrollEdgeChrome(side: .top, height: topHeight)
          }
      }
  }
```

**Both layers stay mounted; only opacity trades, so the swap is a cross-fade rather than a re-created
material.** The animation is `uiGentle` (easeInOut 0.22 s) — note it is *not* routed through
`ThemeMotion.pick`, so it does not shorten under Reduce Motion here (a 220 ms opacity cross-fade with
no travel is already Reduce-Motion-safe).

Note the asymmetry: the **soft** layer's height is the caller's `topHeight`; the **hard** layer's
height is always `hold + 28`, computed independently. They are different heights on purpose.

### 3.6 The three public entry points

| Modifier | Composition | Used by |
|---|---|---|
| `scrollEdgeChrome(top:bottom:topHeight:)` | `scrollEdgeChromeBody(...)` + `.chromeScrollEdgeHidden(.all)` | (Generic; screens now use the `Body` form directly because they need `softTop`) |
| `scrollEdgeChromeBody(top:bottom:topHeight:softTop:topRaised:topHold:)` | the modifier above, no system-effect suppression | Library, Discover, Schedule, LibraryAll |
| `pushedScreenChrome()` | `scrollEdgeChromeBody(top: false, bottom: true)` + `.chromeScrollEdgeHidden(.bottom)` + `.contentMargins(.bottom, 76, for: .scrollContent)` | `RootView.detailDestinations` — **every** pushed screen inherits it |
| `tabBarContentMargin(extra:)` | `.contentMargins(.bottom, 76 + extra, for: .scrollContent)` | Every tab root's scroll view |

`pushedScreenChrome`'s rationale is architectural, not cosmetic: "That is not a per-screen oversight
to fix six times; it is the pushed-screen scaffold, so it lives on the navigation destination and
every future push inherits it." Its **top edge is deliberately untouched** — a pushed screen has a
real navigation bar and the system owns that edge.

`tabBarContentMargin` is a **scroll-content margin, never padding inside the stack**:

> `.padding(.bottom, tabBarClearance)` inside the scroll content does nothing at all when the stack
> is shorter than the viewport — the content is already above the fold, so padding under it changes
> no layout — which is exactly the case a short list is in when it comes to rest inside the ramp. A
> content margin is honoured either way, and it is also what makes the scroll indicator stop at the
> right place.

**Android:** `LazyColumn(contentPadding = PaddingValues(bottom = 76.dp))` is the correct equivalent —
it behaves like a content margin (extends the scrollable range and moves the scrollbar), unlike a
`Modifier.padding` on the last item.

### 3.7 Per-screen hardening: what drives `topRaised`, screen by screen

Every probe is `Color.clear.onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY }` placed
in a `.background` of the **scroll content**. The reason is a platform bug, stated in four places:

> Scroll probes are `Color.clear.onGeometryChange` on the scroll content, because
> `onScrollGeometryChange` never fires on the iOS 27 sim (Today, Detail, Library, Search all use the
> probe).

(`ProfileView` is the one exception and *does* use `onScrollGeometryChange`, because it is a sheet.)

| Screen | Soft layer height | `topHold` | Hardening predicate | Hard layer height |
|---|---|---|---|---|
| **Library** (`LibraryView`) | `topChromeHeight` = `inset+22` | `inlineBarBottom` = `inset+44` | `contentMinY < inlineBarBottom` | `inset+44+28` |
| **All titles** (`LibraryAllView`) | `inset + 52` | focus-dependent, see Search | same shape as Search | ditto |
| **Search** (`DiscoverView`) | `inset + 52` | `searchChromeBottom` | `contentMinY < searchChromeBottom` | `searchChromeBottom + 28` |
| **Schedule** | *(top: false)* | — | — | — |
| **Today** (`TodayVeils`) | `inset + 52 + 100` | `inset + 52` | `showsHero ? headerCarriesTitle : scroll.y > 8` | `inset+52+28` |
| **Detail** (`DetailVeils`) | `inset + 46 + 100` | `inset + 46` | `y > copyTop − (inset + 46)` | `inset+46+28` |
| **Profile** | — | — | system `.hard` scroll edge only | — |

`searchChromeBottom` (DiscoverView:72, and an identical copy in `LibraryAllView`):

```swift
fieldPresented ? topSafeInset + 52              // focused: the title collapses; only the field's band remains
              : inlineBarBottom + 52            // at rest: title + drawer
```

> The hardened veil and its probe follow it — sized to the resting chrome, the veil swallowed the
> grid's header the moment the field was tapped (captured 2 Sep).

**Today** and **Detail** do not use `ScrollEdgeChromeModifier` at all; they mount `ScrollEdgeChrome`
directly in a private two-layer view, because their soft layer is opacity-driven by the scroll offset
rather than a boolean:

```swift
// TodayVeils — headerBand = 52, veilRamp = 100
if !hardOn, scroll.y > 12 {
    ScrollEdgeChrome(side: .top, height: topInset + 52 + 100)
        .opacity(scroll.veilOpacity)            // (y-16)/64, clamped
        .transition(.opacity)
}
if hardOn {
    ScrollEdgeChrome(side: .top, height: topInset + 52 + 28, holdHeight: topInset + 52)
        .transition(.opacity)
}
// .animation(ThemeMotion.pick(.uiGentle, reduceMotion:), value: hardOn) · .allowsHitTesting(false)
```

`DetailVeils` is byte-for-byte the same shape with `band = topSafeInset + 46` and a soft height of
`band + 100`.

**Critical:** the soft layer is *mounted only while it is on*, never held at opacity 0 — "a material
at opacity 0 over moving art is still a backdrop blur the compositor pays for every frame". On
Android the same rule holds for any `Modifier.blur`/`haze` layer: remove it from the composition, do
not alpha it out.

Today additionally has **no mask on its scroll view any more** (that was an offscreen pass per
frame); the opaque bar covers what passes under the wordmark band.

### 3.8 Detail's hardening threshold — the measured handover

```swift
let copyTop = heroHeight - ThemeSpace.x4 - heroCopyHeight        // ThemeSpace.x4 = 16
let under   = y > copyTop - (ThemeMetrics.topSafeInset + 46)
if under != scrolledUnderBar {
    withAnimation(ThemeMotion.pick(.uiGentle, reduceMotion:)) { scrolledUnderBar = under }
}
```

`heroCopyHeight` is the *measured* height of the copy block laid on the hero (its own
`onGeometryChange`). The same flag both hardens the veil **and** fades in the `.principal` docked
title (`.opacity(scrolledUnderBar ? 1 : 0)`, `uiGentle`, `.accessibilityHidden(!scrolledUnderBar)`).

> The bar hardens — and docks the title — the moment the hero's COPY reaches the toolbar's bottom
> edge: Apple TV's handover, the title leaving the picture as it arrives in the bar. At a flat 130 pt
> the flip came ~80 pt later, so the title slid under the glass capsules half-lit and ghosted through
> them for the whole of that scroll (captured 3 Sep).

Today's equivalent (`headerCarriesTitle`) is also measured, not thresholded:

```swift
heroCopyUnderBand = minY < topInset + TodayView.headerBand + 8     // 8 pt of lead
private var headerCarriesTitle: Bool {
    guard showsHero, !recapOnStage, heroFranchise != nil else { return false }
    return heroCopyUnderBand
}
```

> Measured, not thresholded: `scrollY > 150` was calibrated against a tall library and never tripped
> on a compact one — a short Today parks at ~92 pt of scroll with the title already under the band,
> so the mask erased the show's name and the wordmark never took it over.

The wordmark ⇄ title cross-fade is a `ZStack(alignment: .leading)` with reciprocal opacities on
`uiGentle`, `.accessibilityHidden(!headerCarriesTitle)` on the title so VoiceOver never reads both.

### 3.9 Worked numbers (iPhone with a 59-pt top inset)

| Screen / state | Total height | `hold` fraction | Full-canvas holds to | 45 %-canvas at | Clear at |
|---|---|---|---|---|---|
| Library, at rest (soft) | 81 pt | — | — | 0.55·81 ≈ 45 pt @ 30 % | 81 pt |
| Library, hardened | 131 pt | 103/131 = 0.786 | 103 pt | 115.6 pt | 131 pt |
| Search, at rest (soft) | 111 pt | — | — | 55.5 pt @ 30 % | 111 pt |
| Search, hardened, unfocused | 183 pt | 155/183 = 0.847 | 155 pt | 167.6 pt | 183 pt |
| Search, hardened, focused | 139 pt | 111/139 = 0.799 | 111 pt | 123.6 pt | 139 pt |
| Today, hardened | 139 pt | 111/139 = 0.799 | 111 pt | 123.6 pt | 139 pt |
| Detail, hardened | 133 pt | 105/133 = 0.789 | 105 pt | 118.6 pt | 133 pt |
| Any screen, bottom | 64 pt + 180 underfill | — | (bottom edge) | 0.85 → 75 % at 54.4 pt | (top of band) |

Use these as regression targets: an Android build whose hardened Library bar goes fully clear at,
say, 190 dp is wrong even if it "looks fine".

### 3.10 The billboard veils that sit *inside* the hero

Two more gradients belong to the same family and are referenced by the chrome above.

**`HeroTopVeil(band:ramp:)`** — protection over the status bar + chrome band on a full-bleed hero.
One gradient for Today's wordmark band and Detail's floating toolbar. `ramp` defaults to **100**.
`total = band + ramp`, `mark = band / total`, black at:

| Opacity | Location |
|---|---|
| 0.72 | 0 |
| 0.66 | `mark * 0.72` |
| 0.52 | `mark` |
| 0.30 | `mark + (1-mark)*0.30` |
| 0.12 | `mark + (1-mark)*0.62` |
| 0.00 | 1 |

> A ramp that holds flat and then falls reads, over bright key art, as a hard-edged plate laid on the
> picture right where the brand mark (or the back button) is; a veil that can be *seen* is not
> protection, it is a smudge.

**`HeroCopyScrim(copyHeight:lead:)`** — `lead` = **72**, `h = max(1, copyHeight + lead + 8)`, stops
placed in **points off the measured copy height**, not as fractions of the image (a fixed fraction is
a different physical distance at every type size, "which is how AX1 came to set a three-line 44-pt
title over a face at ~55 % luminance"): clear @ 0, canvas 0.16 @ `lead*0.4/h`, canvas 0.44 @
`lead*0.7/h`, canvas 0.72 @ `lead/h`, canvas 0.90 @ `(lead+56)/h`, full canvas at 1.

**`ArtScrim(top:bottom:)`** — the general full-bleed scrim with a transparent middle "so the art is
never uniformly greyed": black `0.55·top` @ 0, black `0.16·top` @ 0.22, clear @ 0.46,
canvas `0.55·bottom` @ 0.80, canvas `1.00·bottom` @ 1.00.

---

## 4. The image pipeline

### 4.1 What it is, and what it is not

`ImageLoader.swift` opens with the problem statement:

> A seamless image pipeline for the poster grids. `AsyncImage` was the bottleneck: it keeps no
> decoded-image cache, so every `LazyVGrid` cell recycle re-fetched, re-decoded on the main actor,
> and flashed the placeholder back in — visible flicker and scroll hitches. This pipeline:
> • caches DECODED, downsampled images in memory (`NSCache`), so recycled cells render instantly;
> • de-duplicates concurrent loads of the same URL;
> • downsamples via ImageIO off the main thread (bounded memory, no main-thread decode);
> • serves synchronous cache hits at init, so a scrolled-away-and-back card never flashes.

There is **no third-party image library**. There is **no prefetching anywhere** (a repo-wide
case-insensitive grep for `prefetch` returns nothing) — the synchronous cache hit at `init` is what
removes the flash, not speculative loading. The disk layer is `URLCache` via
`URLRequest.cachePolicy = .returnCacheDataElseLoad`; nothing in the app configures `URLCache.shared`,
so it runs at the system default.

### 4.2 `downsampleImage(_:maxPixel:)`

```swift
let sourceOptions = [kCGImageSourceShouldCache: false]
CGImageSourceCreateWithData(data, sourceOptions)         // throws .badData on failure
let options: [CFString: Any] = [
    kCGImageSourceCreateThumbnailFromImageAlways: true,
    kCGImageSourceShouldCacheImmediately: true,           // force the decode up front
    kCGImageSourceCreateThumbnailWithTransform: true,     // honour EXIF orientation
    kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixel),
]
CGImageSourceCreateThumbnailAtIndex(source, 0, options)   // throws .badData on failure
return UIImage(cgImage: cgImage)                          // scale 1.0 — see 4.6
```

`maxPixel` bounds the **longest edge** in **pixels**. `kCGImageSourceShouldCacheImmediately` is the
"no main-thread decode" guarantee.

**Android:** Coil's `ImageRequest.size(Size(px, px))` with `Precision.INEXACT` and `Scale.FIT` is the
direct equivalent (Coil decodes to at most that box and honours EXIF). Raw equivalent:
`BitmapFactory` two-pass with `inJustDecodeBounds` → `inSampleSize` → decode, plus
`ExifInterface` rotation. Note `inSampleSize` only quantises to powers of two, so Coil (or
`ImageDecoder.setTargetSize`) is preferred for exact bucket sizes.

### 4.3 `ImageCache` — keyed on `(url, size bucket)`, serve-larger-never-smaller

```swift
final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()
    private let cache = NSCache<NSString, UIImage>()
    private init() { cache.totalCostLimit = 96 * 1024 * 1024 }          // ~96 MB of decoded posters
    static let buckets: [CGFloat] = [128, 192, 256, 384, 512, 768, 1024, 1536, 2048]
    static func bucket(for maxPixel: CGFloat) -> CGFloat {
        buckets.first { $0 >= maxPixel } ?? maxPixel.rounded(.up)
    }
    private static func key(_ url: URL, _ bucket: CGFloat) -> NSString {
        "\(Int(bucket))|\(url.absoluteString)" as NSString
    }
}
```

The **bug this exists to prevent**, quoted:

> Keyed on (url, SIZE BUCKET), not on url alone. Keying on the URL made the FIRST decode win for the
> whole session: a Library thumb asks for ~207px, so the detail hero that wants 700px got the 207px
> decode handed back and rendered a blurry upscale until the app restarted.

The **rule**, quoted:

> The rule is one-directional. A request is served by any cached decode at least as detailed as it
> asked for (downscaling at draw time is free and lossless-looking); it is never served a smaller
> one. Sizes are rounded UP to a fixed ladder and the decode is done at the bucket, not at the
> caller's exact request — otherwise a 207px decode filed under the 256 bucket would shortchange the
> next caller who genuinely wants 256. The ladder plus the serve-larger rule keeps entries per URL to
> a small handful (in practice one or two), and NSCache's byte-cost limit bounds the rest.

Lookup:

```swift
func image(for url: URL, atLeast maxPixel: CGFloat) -> UIImage? {
    let want = ImageCache.bucket(for: maxPixel)
    for b in ImageCache.buckets where b >= want {                 // ascending scan from `want`
        if let hit = cache.object(forKey: ImageCache.key(url, b)) { return hit }
    }
    // Above the ladder there is no larger bucket to fall back on: only an exact match serves.
    return want > (ImageCache.buckets.last ?? 0) ? cache.object(forKey: ImageCache.key(url, want)) : nil
}
```

Store cost: `image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0`. Buckets are spaced ~1.4× "so
rounding never wastes much memory, and wide enough at the top to cover full-bleed banners on a 3x
device".

**Android:** Coil's memory cache is keyed on `MemoryCache.Key(url, extras)` and does **not** do
serve-larger. Reproduce with `MemoryCache.Key(url, mapOf("b" to bucket.toString()))` plus a custom
`Interceptor` that, before the fetch, probes every bucket ≥ `want` in the shared
`MemoryCache` and short-circuits on a hit. Set `MemoryCache.Builder().maxSizeBytes(96L * 1024 * 1024)`
— note Coil's default is a percentage of app heap and will be much smaller than 96 MB on most
devices, so measure. **Difficulty: moderate**; skipping it produces exactly the blurry-hero bug the
comment describes.

### 4.4 `ImageLoader` — the in-flight de-duplicator

```swift
actor ImageLoader {
    static let shared = ImageLoader()
    private var inFlight: [String: Task<UIImage, Error>] = [:]

    func image(for url: URL, maxPixel: CGFloat) async throws -> UIImage {
        if let cached = ImageCache.shared.image(for: url, atLeast: maxPixel) { return cached }
        let bucket = ImageCache.bucket(for: maxPixel)
        let key = "\(Int(bucket))|\(url.absoluteString)"
        if let existing = inFlight[key] { return try await existing.value }
        let task = Task.detached(priority: .userInitiated) {
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad          // URLCache handles the on-disk layer
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw ImageLoadError.badData
            }
            return try downsampleImage(data, maxPixel: bucket)      // decode AT THE BUCKET
        }
        inFlight[key] = task
        do { let image = try await task.value
             ImageCache.shared.store(image, for: url, bucket: bucket)
             inFlight[key] = nil; return image }
        catch { inFlight[key] = nil; throw error }
    }
}
```

De-dup is keyed on `(url, bucket)` for the same reason the cache is: "two surfaces wanting the same
poster at different sizes are not the same request, and collapsing them handed the loser a decode too
small to render sharply." Any non-2xx is a `badData` throw. Note the decode is at **`bucket`**, not
at the caller's `maxPixel`.

**Android:** a `Mutex`-guarded `MutableMap<String, Deferred<Bitmap>>` on an object with
`Dispatchers.IO`, or rely on OkHttp's own request coalescing plus the bucket key. Coil de-dupes
identical `ImageRequest`s but *not* across different sizes, which is the same trap.

### 4.5 `CachedAsyncImage` — the view

```swift
struct CachedAsyncImage: View {
    let url: URL?
    var maxPixel: CGFloat                  // default 700 (→ bucket 768)
    var contentMode: ContentMode           // default .fill
    var alignment: Alignment               // default .center — where a .fill image anchors
    var placeholderHidden: Bool            // default false — hosts with their own ground hide it
    var fitSnapAspect: CGFloat?            // default nil
    private static let fitSnapTolerance: CGFloat = 0.08
    @State private var image: UIImage?
    @State private var loadedURL: URL?
    @State private var didFail = false
}
```

**The synchronous cache hit at `init`** — this is what removes the recycle flash:

```swift
_image = State(initialValue: url.flatMap { ImageCache.shared.image(for: $0, atLeast: maxPixel) })
```

> Synchronous cache hit → first frame already shows the poster, so recycled cells don't flash.
> `atLeast:` so a hero never inherits a thumbnail-sized decode as its first frame.

**Body — the `Color.clear` sizing box.** This is the single most load-bearing line in the file and
the comment explains a real, reproduced layout failure:

```swift
Color.clear
    .overlay(alignment: alignment) {
        if let image {
            Image(uiImage: image).resizable()
                .aspectRatio(contentMode: resolvedContentMode(for: image))
                .transition(.opacity)
        } else if !placeholderHidden {
            GradientPlaceholder()
        }
    }
    .clipped()
    .task(id: url) { await load() }
```

> An `Image` reports its pixel dimensions as its ideal size (our decoded `UIImage`s are scale 1.0, so
> a 1100px banner claims 1100pt), and `.frame(maxWidth:.infinity)` only clamps that ideal when the
> parent proposes a concrete width — during an HStack/ZStack's sizing pass the proposal is nil, so
> the ideal leaks out and inflates the whole enclosing layout. (That's what threw Schedule's rail
> off-screen: one hero banner widened the ScrollView's content past the screen and the feed rendered
> horizontally centred/clipped.) `Color.clear` has no intrinsic size and an overlay never contributes
> to its parent's size, so this view now measures exactly what its container proposes — never more.

**`fitSnapAspect` — the anti-sliver rule.**

```swift
private func resolvedContentMode(for image: UIImage) -> ContentMode {
    guard contentMode == .fit, let target = fitSnapAspect, target > 0, image.size.height > 0
    else { return contentMode }
    let aspect = image.size.width / image.size.height
    return abs(aspect / target - 1) <= 0.08 ? .fill : .fit
}
```

> 0.08, not 0.05: AniList's standard cover is 460×654 (0.703) against the 2:3 slot (0.667) — a 5.4 %
> miss, i.e. exactly the sliver this exists to remove. At 8 % the fill crops ≤4 % per edge, still
> imperceptible on a poster; genuine lockups and stills miss by far more.

Set by `PosterSlot` as `width / height`. Posters aspect-**fit** by rule (they must stay whole), but a
cover that misses by ≤8 % fills instead of leaving a 2-pt tinted mat that "read on every shelf as a
rendering artifact, not as the deliberate letterbox mat the rule is for".

**`load()` — every branch:**

```swift
private func load() async {
    if image != nil && loadedURL == url { return }            // 1. already showing this exact URL
    guard let url else { image = nil; loadedURL = nil; return }  // 2. URL went nil → clear
    if let cached = ImageCache.shared.image(for: url, atLeast: maxPixel) {
        image = cached; loadedURL = url; return               // 3. cache hit → NO animation, instant
    }
    image = nil                                               // 4. uncached new URL → clear stale art
    didFail = false
    do {
        let loaded = try await ImageLoader.shared.image(for: url, maxPixel: maxPixel)
        withAnimation(ThemeMotion.uiGentle) { image = loaded } // 5. fresh load → 0.22 s easeInOut fade
        loadedURL = url
    } catch {
        if !Task.isCancelled { didFail = true }                // 6. failure
    }
}
```

Behaviours an Android port must match exactly:

- **A cache hit never animates.** Only a network/disk load cross-fades, and only on `uiGentle`
  (easeInOut 0.22 s). A recycled cell must appear already-loaded on frame one.
- **A URL change to an uncached URL clears the old art first** (branch 4). No stale poster under a
  new title.
- **A failure has no UI.** `didFail` is written and never read in the body — so on failure the view
  keeps `image == nil` and falls back to `GradientPlaceholder` (or, when `placeholderHidden`, to
  whatever ground the host drew). There is **no error glyph, no retry button, no spinner**. A retry
  happens only when `url` changes or the view is re-created (`.task(id: url)`).
- **Cancellation is not a failure** — the app-wide rule (`Error.isCancellation`) shows up here as
  `if !Task.isCancelled`.

### 4.6 `RemoteImageView`, `GradientPlaceholder`, `Thumb`

`RemoteImageView` is a pure pass-through with the same defaults (`maxPixel: 700`, `.fill`,
`.center`, `placeholderHidden: false`, `fitSnapAspect: nil`) that parses `String?` → `URL?` and
returns `nil` for empty strings.

`GradientPlaceholder`: `LinearGradient(colors: [#27272F, #141418], startPoint: .topLeading, endPoint:
.bottomTrailing)`. Opaque; that is why hosts with their own ground pass `placeholderHidden: true`.

`Thumb(cover:width:height:radius:)` — the legacy fixed-size rounded thumbnail: `radius` default
**10**, `maxPixel = max(width, height) * 3` ("3x = max device scale — a 160 pt thumb needs ~480 px,
not 700"), `.clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))`,
`.background(ThemeColor.surfaceRaised)`.

**Note on `style: .continuous`:** every rounded rectangle in this app is a squircle (iOS continuous
corner curve), not a circular-arc round-rect. Compose's `RoundedCornerShape` is circular-arc; the
visual difference at radius 22 on a card is noticeable. Use a squircle shape
(`GenericShape` with a superellipse path, or the `smooth-corner-rect` approach) for `ThemeRadius.card`
(22) and `focusCard` (24); below ~12 dp it does not matter. **Difficulty: easy but easy to forget.**

### 4.7 `maxPixel` across the app — the complete table

Derived sizes use `max(width, height) * 3`. "Bucket" is what is actually decoded and cached.

| Consumer | `maxPixel` | Bucket | Notes |
|---|---|---|---|
| `CachedAsyncImage` / `RemoteImageView` default | 700 | 768 | |
| `Thumb` | `max(w,h)*3` | varies | |
| `PosterSlot` (`.row` 60×90) | 270 | 384 | THE list row, Library/Search/Schedule |
| `PosterSlot` (`.queue` 44×66) | 198 | 256 | |
| `PosterSlot` (`.todayQueue` 52×78) | 234 | 256 | |
| `PosterSlot` (`.beat` 34×51) | 153 | 192 | |
| `PosterSlot` (`.focus` 88×132) | 396 | 512 | |
| `PosterSlot` (`.todayShelf` 100×150) | 450 | 512 | |
| `PosterSlot` (`.hero` / `.shelfMedium` 112×168) | 504 | 512 | |
| `PosterSlot` (`.shelfLarge` 124×186) | 558 | 768 | |
| `PosterSlot` (`.libraryHero` 192×288) | 864 | 1024 | |
| `ArtHeader`, portrait blurred ground | **1024** | 1024 | stays small "it is blurred" |
| `ArtHeader`, portrait sharp layer | **2048** | 2048 | "Today's billboard hero draws this layer at ~1770 px tall, and capping the decode below that softened the one sharp asset in the frame" |
| `ArtHeader`, landscape | **1536** | 1536 | |
| `LandscapeArt` blurred ground | **160** | 192 | deliberately tiny |
| `LandscapeArt` sharp / `BannerCard` | 560 | 768 | |
| `ProgressBanner` | 900 | 1024 | |
| Schedule `AiringCard` | 1100 | 1536 | gutter-to-gutter 16:9 |
| `ArtBackdrop` (ambient wash) | 320 | 384 | blurred 56 |
| `EpisodeArtwork` still | 288 | 384 | |
| `EpisodeStill` (all three ladder rungs) | `(width ?? 400) * 3` → 360 | 384 | slot is 120×68 |
| `TrailerCard` thumbnail | 640 | 768 | |
| `VideoSheet` poster | 900 | 1024 | |
| `PersonCard` (72-pt disc) | 216 | 256 | |
| Watch-provider logo | 156 | 192 | |
| Palette resolves | 288 / 320 / 360 / 420 / `max(w,h)*3` | — | see 4.9 |

### 4.8 The four image *compositions* built on the pipeline

**(a) `PosterSlot`** — artwork that must stay whole. Z-order: `surfaceRaised` round-rect →
palette tint at **0.60** opacity ("at 0.22 over `surfaceRaised` it was still grey") →
`RemoteImageView(contentMode: .fit, maxPixel: max(w,h)*3, placeholderHidden: true, fitSnapAspect:
w/h)` with `.transition(.opacity.animation(ThemeMotion.uiPoster))` (easeOut 0.18) → **or**, if the
URL is empty, `Image(systemName: "photo")` at `min(w,h) * 0.28`, weight `.regular`, in
`textTertiary`. Then `.clipShape(RoundedRectangle(radius, .continuous))`,
`.overlay(strokeBorder(ThemeColor.posterEdge, lineWidth: 1))`, `.shadow(slot.shadow)`,
`.accessibilityHidden(true)`.

Deliberately **removed**: a blurred second copy behind the poster. "It cost a second full decode plus
a blur pass on every slot ≥ 72 pt, i.e. 60 of each on a 30-title grid." And `.fill` is forbidden
here: it "side-cropped every asset that is not 2:3: Wistoria's announcement lockup rendered as
'son 3 制作'".

**(b) `LandscapeArt(url:portraitSource:maxPixel:alignment:)`** — artwork in a landscape frame.

- `portraitSource == false`: one `RemoteImageView(.fill, maxPixel:, alignment:, placeholderHidden:
  true)`. `alignment` defaults to `.top`.
- `portraitSource == true`: a `ZStack` of
  1. `RemoteImageView(.fill, maxPixel: 160, .center, placeholderHidden: true)`
     `.blur(radius: 28, opaque: true)` `.overlay(Color.black.opacity(0.32))`
  2. `RemoteImageView(.fit, maxPixel: maxPixel, .center, placeholderHidden: true)`
     `.padding(.vertical, ThemeSpace.x2)` (8) `.shadow(color: .black.opacity(0.45), radius: 8, y: 4)`

  The contact shadow is not decoration: "without it the two read as one badly-decoded image".

Why it exists: "`.fill`ed into a 1.6–2.1:1 frame, a 2:3 poster shows the middle third of itself — a
forehead, a white slab, a fragment of a lockup — which is what the Library's Announced shelf and
Search's trending wall did for every show the catalogue has no banner for (about a third of them)."

**(c) `ArtHeader(url:height:tint:scrimTop:scrimBottom:focus:portraitSource:drift:overlay:)`** — the
billboard. `ZStack(alignment: .bottom)`:

1. `(tint ?? PaletteCache.fallback)` — the palette ground, "so the header never flashes black"
2. art: portrait path = blur-48 ground at 1024 + black 0.28 overlay, then `.fit` at 2048 anchored to
   `focus`; landscape path = single `.fill` at 1536 anchored to `focus`
3. `ArtScrim(top: scrimTop, bottom: scrimBottom)`
4. `overlay()` with `.padding(.horizontal, 16)`, `.padding(.bottom, ThemeSpace.x5 = 20)`,
   `.frame(maxWidth: .infinity, alignment: .leading)`

then `.frame(height:)`, `.frame(maxWidth: .infinity)`, `.clipped()`.

`focus` is an `Alignment` (`.top` default) — "hard-coding `.top` is why one hero was a forehead and
another was a logo".

**The drift** (Today's and Detail's billboards only; nothing else in the app drifts):

```swift
private var driftScale: CGFloat { drifting ? 1.07 : 1 }
private var driftAnchor: UnitPoint { focus == .top ? .top : (focus == .bottom ? .bottom : .center) }
.task(id: drift && !reduceMotion) {
    guard drift, !reduceMotion else { drifting = false; return }
    try? await Task.sleep(for: .milliseconds(80))     // a beat after insertion
    guard !Task.isCancelled else { return }
    withAnimation(.easeInOut(duration: 24).repeatForever(autoreverses: true)) { drifting = true }
}
```

**1.07× over 24 s, eased, auto-reversing, off under Reduce Motion, one transform on one layer** (the
sharp layer only — the blurred ground does not move). The 80 ms delay is required: "an animation
started in the same transaction as the view's own appearance is folded into it and never repeats."

**(d) `EpisodeStill(url:landscape:poster:tint:width:number:)`** (DetailSupport) — the episode tile,
120×68, 16:9 by ratio, `ThemeRadius.episodeStill` = 8. Ground = `stillTint ?? tint ??
surfaceRaised`. Ladder, in order:

| Rung | Art | Extra |
|---|---|---|
| still (`url`) | `.fill`, `(width ?? 400)*3` | no number drawn |
| landscape | `.fill`, `.center` | black 0.20→0.46 vertical gradient + the episode number |
| poster | `.fill`, `.top` ("a 2:3 cover carries the face in its upper half and the logotype band in its lower one") | black 0.25→0.50 + the number |
| nothing | — | black 0.10→0.34 only, no glyph ("a play glyph here would claim a picture failed to load") |

The number, drawn **only when there is no real still**: `Text("\(number)")`, system 17 bold
monospaced-digit, `textPrimary`, shadow black 0.55 r3 y1, `.bottomLeading`, padding 7. Rationale: "a
season the catalogue did not illustrate gets its own cover behind the numeral that is the episode's
whole identity, so a column of tiles reads 11, 12, 13 instead of one poster eighteen times".

`EpisodeArtwork` (Primitives+States) is the *other* episode tile — the spoiler-aware one. Slot is
`CGSize(120, 68)` (it was 96×54; "a postage stamp beside 17-pt type; Netflix's episode thumbnails run
~130 pt wide"). When `spoilerSafe && url != nil` it stacks tint → `Image(systemName: "photo")` at
16 pt in `textTertiary` → `RemoteImageView(.fill, maxPixel: 288)`; the glyph sits *under* the image so
a fetch that never resolves leaves tint + a centred photo glyph rather than a bare rectangle.
Otherwise `EpisodeGlyphTile`: show tint, black 0.10→0.34 gradient, `play.rectangle` at 17 pt. **A
spoiler-protected still is replaced, never blurred** — "a blur is a tease with no VoiceOver
equivalent."

### 4.9 `PaletteCache` — the art-adaptive ground, sharing the same decode

`PaletteCache` is `@MainActor`, memoised by URL string, with an `inFlight: Set<String>` guard. It
**reads the image cache first** and only falls through to `ImageLoader`:

```swift
if let cached = ImageCache.shared.image(for: u, atLeast: maxPixel) { image = cached }
else { image = try? await ImageLoader.shared.image(for: u, maxPixel: maxPixel) }
let color = await Task.detached(priority: .utility) { PaletteCache.dominantTint(of: image) }.value
```

This is why palette `maxPixel`s are *smaller* than display ones (288/320/360/420): the serve-larger
rule means the already-decoded display image satisfies them, so the palette costs **zero extra
decodes** on every surface that draws the art at ≥ its palette request. `PosterSlot` passes the same
`max(w,h)*3` to both, so one decode serves both. Detail asks for 420 while its hero decodes at 2048 —
the cache hands back the 2048.

`resolve` returns `PaletteCache.fallback` (`#1C1A17`, "neutral warm surface") on failure;
`resolveIfAvailable` returns `nil` so callers with a *branded* fallback keep it on stage.

**Extraction** (`dominantTint(of:)`, `nonisolated`, runs off-main, pure arithmetic — fully portable):

1. Draw into a **32×32** `CGContext`, `premultipliedLast`, `interpolationQuality = .medium`.
2. Per pixel: skip `alpha < 0.8`; convert sRGB → **OKLab** (Björn Ottosson's matrices, in the file);
   skip `L < 0.08` or `L > 0.92`; skip `chroma < 0.035`.
3. Bucket by **12 hue bins × 4 lightness bins**: `key = Int((hue + π)/(2π) * 12) * 10 + Int(L * 4)`,
   accumulating summed L/a/b and a count.
4. Take the highest-population bucket; average it. If none, return `fallback`.
5. **Clamp** `L` to **0.30…0.44**; clamp chroma to **0.075…0.145**; blend the hue **15 %** toward
   brand amber (`#F0A24E` in OKLab, unit vector) and renormalise to the clamped chroma.
6. Convert back to sRGB, clamped to 0…1.

The clamp values carry a regression note worth preserving: at `L 0.24…0.38` / `C 0.035…0.075` /
35 % brand blend, "Library new rgb(36,30,27) vs original rgb(45,32,22) — 20 % dimmer with R−B falling
23→9; Schedule new rgb(32,32,29) vs original rgb(71,64,59) — less than half the luminance". The
current numbers are the fix.

**Android:** do **not** use `androidx.palette` — it quantises in HSL and produces different, greyer
colours. Port the OKLab code directly (it is ~30 lines of `Double` arithmetic) onto
`Bitmap.createScaledBitmap(bmp, 32, 32, true)` + `getPixels`. **Difficulty: easy.**

**`ArtAdaptiveGround(tint:intensity:)`** — the card ground: `surfaceFlat` → linear gradient
`base·0.52·intensity` (topLeading) → `base·0.18·intensity` (bottomTrailing) → radial
`base·0.30·intensity` → clear, centre (0.16, 0.02), radius 0…320 → `Color.black.opacity(0.30)`.
`.animation(uiPoster, value: tint == nil)`. The veil is **0.30, not the spec's 0.44**: at 0.44 "the
composite landed at rgb(22,18,18) against a rgb(9,9,11) canvas: a 4 % luminance step, which is why
the shipped Focus card read as a hole with an outline round it".

**`ArtBackdrop(url:tint:height:intensity:)`** — the ambient wash, one spec app-wide
(`rootWashHeight` 320, `rootWashIntensity` 0.4). Layers, top-aligned:

1. `RemoteImageView(.fill, maxPixel: 320, placeholderHidden: true)` sized to `height`, `.clipped()`,
   `.blur(radius: 56, opaque: true)`, `.opacity(0.70 * intensity)`.
   **Centre-cropped BEFORE the blur** — "blurring a view whose art has not been made to fill its
   frame samples whatever corner the image happened to land in — which is why Profile drew no image
   at all". No `.saturation()`: the tint clamp already narrows chroma.
2. `LinearGradient([base·baseTop, base·baseMid, .clear])` where
   `baseTop = artSettled ? 0.60·intensity : max(0.60·intensity, 0.55)` and
   `baseMid = artSettled ? 0.10·intensity : max(0.10·intensity, 0.12)`.
   `artSettled = (resolvedTint != nil)`. The floor is **independent of `intensity`** until the art
   lands, because at a list root's 0.4 the ember composited to ~rgb(38,36,32): "the status band reads
   BLACK for the whole first load, then jumps to twice the luminance when the art decodes (user,
   30 Aug — 'black, then it becomes flush')".
3. `LinearGradient([accent·0.07·intensity, .clear])` — "a constant breath of the brand's warmth under
   every wash, so Schedule, Search and Profile share one atmosphere".
4. Handover: clear @ 0 → `canvas·0.55` @ 0.55 → `canvas` @ 1.

`base = tint ?? resolvedTint ?? ThemeColor.ambientBackdropFallback` (`#432D21`).
`.animation(uiGentle, value: resolvedTint)`, `.allowsHitTesting(false)`, `.accessibilityHidden(true)`,
`.task(id: url) { resolvedTint = nil; … resolveIfAvailable(maxPixel: 320) }`.

### 4.10 Accessibility of the whole image layer

Every art-drawing view in this subsystem is `.accessibilityHidden(true)`: `PosterSlot`,
`EpisodeArtwork`, `EpisodeGlyphTile`, `EpisodeStill`, `ArtBackdrop`, `ArtScrim`, `HeroTopVeil`,
`HeroCopyScrim`, `ScrollEdgeChrome`. Meaning is carried by the row's text, never by the picture. A
Compose port should mark these `Modifier.clearAndSetSemantics {}` / `contentDescription = null`
uniformly — an auto-generated "image" node on every poster in a grid is a TalkBack regression.

Dynamic Type: the image layer has **no** type-size branches of its own; sizes are fixed points. The
type-size responses live in the hosts (hero heights grow with *measured* copy overflow, not with a
guessed accessibility bump). Reduce Motion: only the `drift` and the cross-fades respond.

---

## 5. Transitions

### 5.1 `PageInTransition` — the once-per-tab entrance

```swift
private struct PageInTransition: ViewModifier {
    let isActive: Bool
    var travel: CGFloat = 6
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var entrance: Animation { ThemeMotion.pick(ThemeMotion.uiReveal, reduceMotion: reduceMotion) }

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : travel)     // Reduce Motion → pure crossfade
            .onChange(of: isActive) { _, active in
                if active, !shown { withAnimation(entrance) { shown = true } }
            }
            .onAppear { if isActive, !shown { withAnimation(entrance) { shown = true } } }
    }
}
```

| Property | Value |
|---|---|
| Travel | **6 pt** upward (content starts 6 pt low and settles) |
| Opacity | 0 → 1 |
| Curve | `uiReveal` = `timingCurve(0.22, 1.00, 0.36, 1.00)`, **0.28 s** |
| Reduce Motion | `uiReduced` = easeOut 0.12 s, **and no travel at all** |
| Repeats | **never** — `shown` is never reset |
| Applied to | the four tab roots only, inside `MainTabView` |

Two decisions with reasons:

> It runs ONCE per tab: replaying it on every switch turned ordinary tab changes into a 0.42 s
> loading beat, so after the first landing a switch is the instant cut native tabs promise (user
> call, 2026-08-08).

> Driven by the *selection* (`isActive`), not by `onAppear`/`onDisappear` alone. TabView keeps every
> tab alive and fires those lifecycle callbacks inconsistently, which made an earlier onAppear-based
> version replay unevenly (or not at all) on Today/Schedule.

Travel is 6 and not 10: "at 10 the first landing reads as content sliding into place, which is a
loading beat; at 6 it reads as the screen coming into focus."

**Android:** `AnimatedVisibility` is the wrong tool (it would re-run on every tab switch if the tabs
are swapped out). Keep all four tab screens composed (a `Pager` or a `Box` with saveable state),
hold a `remember { mutableStateOf(false) }` per tab that is only ever set true, and drive
`Modifier.graphicsLayer { alpha = …; translationY = … }` from an `animateFloatAsState` with
`tween(280, easing = CubicBezierEasing(0.22f, 1f, 0.36f, 1f))`. **Difficulty: easy.**

### 5.2 `ZoomTransition` — registered everywhere, consumed nowhere

```swift
extension EnvironmentValues { @Entry var zoomNamespace: Namespace.ID? = nil }

func zoomSource(_ id: String) -> some View { modifier(ZoomSourceModifier(id: id)) }

private struct ZoomSourceModifier: ViewModifier {
    @Environment(\.zoomNamespace) private var namespace
    let id: String
    func body(content: Content) -> some View {
        if let namespace { content.matchedTransitionSource(id: id, in: namespace) } else { content }
    }
}
```

`OptionalZoomSource` (Primitives.swift) is the same thing for an `id: String?` — "so a card can be
composed once whether or not its screen registers it as a transition source". The namespace is
injected once in `MainTabView` (`@Namespace private var zoom` → `.environment(\.zoomNamespace, zoom)`).

**Ids are surface-scoped, and that is the whole point** — "the same franchise can be on screen in
several tabs at once, and duplicate source ids within one namespace are undefined". Observed
prefixes: `lib/`, `lib-hero/`, `all/`, `focus/` (`focus/recap` when the recap is on stage),
`queue/`, `next/`, `shelf/`, `shelfrow/`, `trending/`, `trend/`, `recent/`, `sched/<id>/<episode>`,
`detail/`, `alert/`. `DetailRoute` carries the `zoomID` (`Sources/App/Routing.swift`).

**Nothing consumes any of it.** Detail is a plain push. The retirement is documented in
`RootView.detailDestinations` and must not be reversed by an Android engineer who thinks a shared
element would be a nice touch:

> It was `.zoom` from the tapped artwork (2 Sep) and the frames say why that is wrong here: the zoom
> scales the WHOLE destination into the source's frame, so for its first 150 ms the show page was a
> miniature of itself — billboard, pill, title and amber capsule squeezed into a 60×90 poster —
> inflating ("the details opening motion is just trash", user, 3 Sep). The HIG reserves zoom for a
> destination that IS the source, larger (a photo, a card's own art); a page with a landscape
> billboard cropped from a different picture is not that. The `zoomSource` registrations stay: they
> cost nothing and are the hook if a transition that fits ever arrives.

**Android:** Detail opens with the platform's default forward push/slide. Do **not** wire a
`SharedTransitionLayout`. If the registry is ported at all it should be a no-op `Modifier` +
id-generation convention kept for future use, exactly as here.

### 5.3 Navigation transition facts this subsystem depends on

- Detail is a **plain push** on the active tab's `NavigationPath`.
- **Re-selecting the active tab pops it to root** (`selection` binding replaces the path with an
  empty `NavigationPath`); Library additionally bumps `libraryPops` because its All-titles route is
  an *item* destination, not a path entry, "so clearing the path alone left it standing and the tap
  did nothing".
- Tab change fires exactly one haptic: `FeedbackCoordinator.fire(.selection)`. **Navigation is
  silent otherwise** — "board 11: no haptic on open" (`openDetail` has no feedback call).
- An episode-alert tap replaces Today's path wholesale:
  `paths[.today] = NavigationPath([DetailRoute(id: id, zoomID: "alert/\(id)")])`.
- The tab bar minimises on scroll-down (iOS 26 only) and the toast host sits at
  `.padding(.horizontal, 22)` / `.padding(.bottom, 62)` above the window's bottom.

### 5.4 The two shared content transitions

Not in the five assigned files, but they are the transitions every screen in this subsystem hands
off with, and they are specified in `ThemeTokens.swift`.

**`AnyTransition.handoff(reduceMotion:)`** — one card replaced by the next (Today's focus card after
a mark, Detail's next-up card, a Schedule row settling, Search's launchpad ⇄ results):

```swift
.asymmetric(insertion: .opacity.animation(ThemeMotion.uiSettle.delay(0.08)),
            removal:   .opacity.animation(ThemeMotion.uiDismiss))
// Reduce Motion: .opacity.animation(uiReduced), no delay
```

> Asymmetry is the whole point — a symmetric crossfade superimposes two different sentences, which is
> what a smear is.

The build it replaced had four different answers, including "a symmetric 460 ms crossfade on Detail
that renders two show titles and two CTA labels superimposed for a quarter of a second".

**`AnyTransition.toast(reduceMotion:)`**:

```swift
.asymmetric(insertion: .opacity.combined(with: .offset(y: 4)).animation(ThemeMotion.uiSnappy),
            removal:   .opacity.animation(ThemeMotion.uiDismiss))
```

A 4-pt rise in, a plain fade out. "A toast leaving on the spring it arrived on reads as a bounce, not
a dismissal."

### 5.5 Motion token reference (with Android conversions)

`ThemeMotion.pick(token, reduceMotion:)` returns `uiReduced` whenever Reduce Motion is on. Every
animation in this subsystem goes through it **except** the `ScrollEdgeChromeModifier` cross-fade and
`ArtAdaptiveGround`/`ArtBackdrop`'s `uiGentle` fades (all pure opacity, already safe).

| Token | SwiftUI | Compose equivalent |
|---|---|---|
| `uiPress` | `easeOut(0.09)` | `tween(90, easing = FastOutLinearInEasing)` ≈ `CubicBezierEasing(0f,0f,0.58f,1f)` |
| `uiMicro` | `spring(response: 0.22, damping: 0.88)` | `spring(dampingRatio = 0.88f, stiffness = 816f)` |
| `uiSnappy` | `spring(0.34, 0.84)` | `spring(0.84f, 342f)` |
| `uiSettle` | `spring(0.46, 0.90)` | `spring(0.90f, 187f)` |
| `uiMilestone` | `spring(0.38, 0.74)` | `spring(0.74f, 273f)` |
| `uiGentle` | `easeInOut(0.22)` | `tween(220, easing = FastOutSlowInEasing)` |
| `uiReveal` | `timingCurve(0.22, 1.00, 0.36, 1.00, 0.28)` | `tween(280, easing = CubicBezierEasing(0.22f,1f,0.36f,1f))` |
| `uiPoster` | `easeOut(0.18)` | `tween(180, LinearOutSlowInEasing)` |
| `uiNumeric` | `easeOut(0.22)` | `tween(220, LinearOutSlowInEasing)` |
| `uiSweep` | `timingCurve(0.40, 0.00, 0.20, 1.00, 0.52)` | `tween(520, CubicBezierEasing(0.4f,0f,0.2f,1f))` |
| `uiDismiss` | `easeIn(0.16)` | `tween(160, FastOutLinearInEasing)` |
| `uiLiveBreath` | `easeInOut(1.80).repeatForever(autoreverses: true)` | `infiniteRepeatable(tween(1800, easing = FastOutSlowInEasing), RepeatMode.Reverse)` |
| `uiReduced` | `easeOut(0.12)` | `tween(120, LinearOutSlowInEasing)` |
| art drift | `easeInOut(24).repeatForever(autoreverses: true)` | `infiniteRepeatable(tween(24_000, easing = FastOutSlowInEasing), RepeatMode.Reverse)` |

Spring conversion used: SwiftUI's `response` is the undamped period, so
`stiffness = (2π / response)²` at unit mass, `dampingRatio = dampingFraction`. Verify by eye —
Compose's spring integrator is not identical.

---

## 6. Accessibility behaviour, consolidated

| Setting | Behaviour in this subsystem |
|---|---|
| **Reduce Transparency** | `ChromeGlassBox` swaps glass for `surfaceFloating` + 20 %-white 1-pt stroke. `ScrollEdgeChrome` drops the `.ultraThinMaterial` layer entirely **and** raises the hardened top veil from 0.74 to **1.0** — the only case in which the bar is opaque. |
| **Reduce Motion** | `PageInTransition` loses its 6-pt travel and runs `uiReduced` (0.12 s). `ArtHeader.drift` does not start (`drifting` forced false). `handoff`/`toast` collapse to `uiReduced` opacity with no delay/offset. Every screen veil cross-fade goes through `ThemeMotion.pick`. Press feedback presses in **opacity (0.72), never scale**. |
| **VoiceOver** | Every veil, scrim, backdrop, poster, still and glyph tile is `accessibilityHidden(true)`. Detail's docked bar title is `accessibilityHidden(!scrolledUnderBar)`; Today's hero title is `accessibilityHidden(!headerCarriesTitle)` — exactly one of wordmark/title is ever exposed. |
| **Dynamic Type** | No image or veil size varies with type size. Hero heights grow with *measured copy overflow* (`heroCopyHeight`), which changes the veil's `hold` indirectly. `HeroCopyScrim` places its stops in points off the measured copy, not as fractions, precisely so AX sizes stay protected. |
| **Haptics** | This subsystem fires exactly one: `.selection` on tab change, via `FeedbackCoordinator` (throttle floor 0.04 s for `.selection`, 0.3 s for everything else; suppressed unless `UIApplication.shared.applicationState == .active` and the in-app Haptics toggle is on). |

---

## 7. Android reproduction risks

| # | Item | Risk |
|---|---|---|
| 1 | **Backdrop blur for the scroll-edge bands and chrome glass** | The whole "material to its bottom edge" rule depends on real backdrop blur. `Modifier.blur` blurs the composable's own content. Needs a `GraphicsLayer` capture of the scroll content (Compose 1.7 `rememberGraphicsLayer` + `toImageBitmap`, per-frame, expensive) or the `haze` library. If unobtainable, ship the Reduce-Transparency recipe everywhere and accept a flatter bar — **do not** ship a 0.74 scrim with no blur. |
| 2 | Liquid Glass (`glassEffect`) | No analogue and none needed: the app already ships a correct non-glass path for iOS 18. Target the `.ultraThinMaterial` look, not the iOS 26 one. |
| 3 | `tabBarMinimizeBehavior(.onScrollDown)` | **ERRATUM (2026-09-04, PLAN §9.2): DROPPED — a static `NavigationBar` (PLAN D10).** It is already a no-op on the iOS 18 floor the port targets, and a hand-rolled `NestedScrollConnection` version is a different component with different physics. |
| 4 | `scrollEdgeEffectHidden` / `scrollEdgeEffectStyle(.hard)` | No-ops; Android has no system scroll-edge effect to suppress or harden. Profile loses its `.hard` edge and must draw its own veil or accept the plain material bar. |
| 5 | `sharedBackgroundVisibility(.hidden)` | No-op; Compose toolbar actions carry no capsule. |
| 6 | `navigationSubtitle` | Easy — two-line title slot in the **app-drawn** bar. **ERRATUM (2026-09-04, PLAN §3.1/§9.2): M3 `TopAppBar` is banned** (see row above). |
| 7 | Continuous (squircle) corners | `RoundedCornerShape` is circular-arc; at radius 22–24 on cards the difference reads. Needs a superellipse shape. |
| 8 | `matchedTransitionSource` / `.zoom` | Dead in the iOS app by design. `SharedTransitionLayout` must **not** be wired to Detail — the transition was tried and retired for a documented reason. |
| 9 | Serve-larger image cache | Coil keys per exact size and will hand back the wrong decode. Needs a bucket-keyed `MemoryCache.Key` plus an interceptor that probes buckets ≥ want. Skipping it reproduces the blurry-hero bug verbatim. |
| 10 | 96 MB decoded-image budget | Coil's default memory cache is a % of app heap and will be far smaller on mid-range devices; setting 96 MB may push against the heap limit. Measure and tune; the *rule* (bounded by real byte cost, `bytesPerRow × height`) matters more than the number. |
| 11 | Synchronous cache hit on first frame | Compose's `AsyncImage` renders a placeholder for at least one frame unless the memory cache is probed during composition. Needs a `remember` that reads the `MemoryCache` before the request. Moderate, and it is the difference between "no flash" and the `AsyncImage` behaviour this pipeline was built to replace. |
| 12 | `Color.clear` sizing box | Compose has no "ideal size leaks out" bug in the same form, but `Image` with `wrapContentSize` will still inflate a `Row`. Always size the box and let the painter fill it (`Modifier.fillMaxSize()` + `ContentScale`). |
| 13 | **Reduce Transparency** | Android has **no** public equivalent setting. The app has a real branch that depends on it. Recommendation: an in-app Settings toggle (the app already owns a Haptics toggle in the same list), defaulted off, plus honouring `AccessibilityManager` high-contrast where readable. Flag to product. |
| 14 | Reduce Motion | No first-class API. Use `Settings.Global.ANIMATOR_DURATION_SCALE == 0f` (and `TRANSITION_ANIMATION_SCALE`) as the signal; wire it into a single `LocalReduceMotion` composition local so `ThemeMotion.pick` has one input, as on iOS. |
| 15 | `topSafeInset` = 59 assumption | All band heights are `inset + N`. Android status bars are much shorter and gesture-nav insets differ. Compute from `WindowInsets`, never port the 59. |
| 16 | `bottomUnderfill` over-draw | **KEPT (PLAN D21).** Compose `Scaffold` insets content by the bottom bar the same way, so the same 180-dp over-draw is needed. Verify no content is legible in the gesture strip. Note `spec/discover.md` §14 once said it could be dropped; that line is errata-patched. |
| 17 | SF Symbols | Three appear here: `photo` (poster/still fallback), `play.rectangle` (glyph tile), `exclamationmark.triangle.fill` (failure toast). Map to Material Symbols `image` / `smart_display` / `warning` and re-check optical weight at the stated point sizes. Easy. |
| 18 | ImageIO EXIF-aware thumbnailing | `kCGImageSourceCreateThumbnailWithTransform` handles orientation for free. Coil does too; a hand-rolled `BitmapFactory` path does not. |
| 19 | Live Activities / Dynamic Island | Not touched by these files. The only Dynamic-Island dependency here is that `topSafeInset` is tall on those devices, which is handled by measuring. |
