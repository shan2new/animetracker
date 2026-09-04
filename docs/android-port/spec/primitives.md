# Core primitives — cards, rows, buttons, lists, progress, rings

This is the behavioural specification for `ios/Sources/DesignSystem/Primitives.swift` — the component
library every screen in *Previously.* is assembled from — plus the four primitives that live one file
away but are part of the same contract (`SectionHeaderRow`, `SectionHeaderPressStyle`,
`CompactActionButtonStyle`, `EpisodeArtwork`/`EpisodeGlyphTile` in `Primitives+States.swift`,
`EpisodeStill` in `FranchiseDetail/DetailSupport.swift`, `StretchingHeroArt` in `TodayView.swift`).
Every number here is literal and load-bearing: the file's own header says *"Each has exact geometry,
named states, and no local colour or radius values."* A screen may never re-declare a size, a colour,
a radius or a shadow — it composes these. Two rules from `CLAUDE.md` govern almost every decision
below and must survive the port: **amber (`accent`) is never an action colour** — it is rationed to
MEANING (a real next step) and STATE (today, owned, selected, committed) plus grounds and brand, while
every tappable word or glyph uses `interactive`; and **tone separates, light describes, strokes are
for things that float** — a container that needs an outline to be visible is at the wrong surface
level. Read §0 first: every component quotes those tokens by name and this spec never repeats their
values inline.

---

## 0. Token dependencies

These live in `DesignSystem/ThemeTokens.swift`. They are reproduced here because the components below
are unbuildable without them; the ThemeTokens spec is authoritative if the two ever disagree.

### 0.1 Colour (`ThemeColor`)

All colours are opaque sRGB hex or white/black with alpha. The app is **dark-only**; there is no light
palette.

| Token | Value | Role |
|---|---|---|
| `canvas` | `#09090B` | screen ground |
| `canvasRaised` | `#0D0E11` | — |
| `surfaceFlat` | `#171719` | result of `plateLift` over canvas |
| `surfaceRaised` | `#242428` | poster/art ground before decode, unselected chip |
| `surfaceFloating` | `#2A2D36` | floating containers, secondary button |
| `surfacePressed` | `#353842` | pressed ground for rows/chips/secondary |
| `textPrimary` | `#F4F1EC` | |
| `textSecondary` | `#AAA6A0` | |
| `textTertiary` | `#85817C` | 5.14:1 on canvas — the AA floor for text at any size |
| `textDisabled` | `#807C77` | ≈4.6:1; **glyphs only** (row chevrons) |
| `accent` | `#F0A24E` | amber |
| `accentPressed` | `#D88D3B` | |
| `accentSoft` | `#F0A24E` @ 0.14 | |
| `onAccent` | `#0B0B0D` | ink on amber grounds |
| `interactive` | **alias of `textPrimary`** | the ink of every bare tappable word/glyph |
| `ambientBackdropFallback` | `#432D21` | warm pre-art wash |
| `success` / `warning` / `destructive` / `information` | `#30D158` / `#FFD60A` / `#FF453A` / `#64D2FF` | |
| `separator` | white 0.08 | |
| `separatorQuiet` | white 0.045 | divider **inside** a plate (8 of `separator` down one list reads as a spreadsheet) |
| `stroke` | white 0.12 | control perimeter |
| `strokeStrong` | white 0.20 | floating container edge, `ProgressBar` track |
| `markRingIdle` | white 0.34 | the unmarked `MarkRing` stroke — an invitation, deliberately louder than `strokeStrong` |
| `hairline` | white 0.055 | 1-px top-edge highlight on a raised surface |
| `posterEdge` | white 0.09 | the edge of artwork — never `stroke` |
| `skeleton` | `#F4F1EC` @ 0.11 | |
| `focusRing` | `#F0A24E` @ 0.70 | |
| `scrim` | black 0.56 | |
| `scrimStrong` | black 0.72 | `OverArtLabel`'s capsule |
| `plateLift` | white 0.055 | `.plate` ground (a *lift*, not a fill) |
| `raisedLift` | white 0.11 | `.raised` ground |
| `chromeVeil` | = `canvas` | scroll-edge veil |
| `backdropFade` | = `canvas` | |
| `controlSheen` | white 0.22 | the lit top edge of a filled control |

> **Why `plateLift`/`raisedLift` are alphas, not fills:** *"The shipped `.plate` painted opaque
> `surfaceFlat` wherever it landed, so on any screen carrying an `ArtBackdrop` the ambient wash lifted
> the canvas AROUND the plate and the plate itself inverted into a hole 13 levels darker than its own
> ground."* Painting white over whatever is beneath means a plate is always *above* its ground.

### 0.2 Space, radius, metrics

`ThemeSpace`: `x0_5`=2, `x1`=4, `x2`=8, `x3`=12, `x4`=16, `x5`=20, `x6`=24, `x8`=32, `x10`=40,
`x12`=48, `x16`=64.

`ThemeRadius`: `episodeStill`=8, `poster`=10, `compactControl`=12, `row`=16, `toast`=18, `card`=22,
`focusCard`=24. **All rounded rectangles use `style: .continuous`** (Apple's squircle), never a
circular-arc corner.

`ThemeMetrics` (the ones this file consumes):

| Token | Value | Meaning |
|---|---|---|
| `gutter` | 16 | screen side margin |
| `sectionGap` | 30 | between two sections |
| `labelGap` | 10 | section label → first thing under it |
| `cardGap` | 10 | between sibling cards |
| `shelfGap` | 12 | between shelf items |
| `titleGap` | 3 | title → its own metadata line |
| `artGap` | 14 | art → the text it belongs to |
| `heroClearance` | 26 | below a hero |
| `rowCompact` | 56 | `GroupedRow` min height |
| `rowStandard` | 88 | `MediaRow` min height for `.queue` / `.todayQueue` |
| `rowMedia` | 100 | `MediaRow` min height for every other slot |
| `rowEpisode` | 82 | |
| `rowRuleInset` | `gutter + PosterSize.row.width + artGap` = **90** | where a poster row's hairline starts |
| `topSafeInset` | device status-bar inset, read once from the key window, cached; **59** before a window exists | |
| `topChromeRamp` | 22 | |
| `topChromeHeight` | `topSafeInset + 22` | |
| `inlineBarHeight` | 44 | |
| `inlineBarBottom` | `topSafeInset + 44` | |
| `barEdgeRamp` | 28 | ramp under a hardened top veil |
| `chromeBarOpacity` | 0.74 | hardened bar canvas over its blur — **never 1.0** except under Reduce Transparency |
| `searchDrawerHeight` | 52 | |
| `bottomChromeHeight` | 64 | the tab pill's own height |
| `bottomUnderfill` | 180 | solid canvas over-drawn past the layout's bottom edge |
| `tabBarClearance` | `64 + 12` = 76 | |
| `tabBarVisualHeight` | 90 | |
| `toastClearance` | 62 | |
| `rootWashHeight` / `rootWashIntensity` | 320 / 0.4 | the one ambient-wash spec app-wide |
| `scrollSample(y, floor: -320, ceiling: 240)` | `(clamp(y, -320, 240) * 2).rounded() / 2` | clamp + round to the half point |
| `windowHeight` | key-window height, cached; **852** fallback | |

### 0.3 Shadow (`ShadowToken` = colour + radius + y-offset; x is always 0)

| Token | Colour | Radius | Y |
|---|---|---|---|
| `.none` | clear | 0 | 0 |
| `.card` | black 0.45 | 18 | 10 |
| `.art` | black 0.55 | 12 | 7 |
| `.artHero` | black 0.60 | 26 | 14 |
| `.floating` | black 0.50 | 26 | 14 |

`.shadow(token)` is the only sanctioned way to cast one. *"Never apply one to a surface that has no
tone of its own."*

### 0.4 Type (`ThemeType` → `TypeToken { font, tracking }`, applied by `.type(_:)`)

Two families: **Outfit SPEAKS** (identity, buttons, row/body copy, facts, link actions);
**SF Pro ANNOTATES** (dense small metadata, section eyebrows, numerals/times — Outfit has no tabular
figures — and the one long-form paragraph). `tracking` is in **points**, not em.

| Token | Font | Tracking | Dynamic-Type anchor |
|---|---|---|---|
| `brandWordmark` | Outfit-SemiBold 20 | −0.30 | `.headline` |
| `displayXL` | Outfit-Bold 34 | −0.80 | `.largeTitle` |
| `displayL` | Outfit-Bold 28 | −0.60 | `.title` |
| `heroTitle` | Outfit-Bold 28 | −0.55 | `.title` |
| `showTitleL` | Outfit-SemiBold 22 | −0.35 | `.title2` |
| `sectionTitle` | Outfit-SemiBold 20 | −0.30 | `.title3` |
| `showTitleM` | Outfit-SemiBold 17 | −0.20 | `.headline` |
| `rowTitle` | Outfit-SemiBold 17 | −0.20 | `.headline` |
| `body` | Outfit-Regular 17 | −0.10 | `.body` |
| `bodyEmphasis` | Outfit-SemiBold 17 | −0.20 | `.body` |
| `button` | Outfit-SemiBold 16 | −0.15 | `.callout` |
| `callout` | Outfit-Regular 16 | −0.10 | `.callout` |
| `heroMeta` | Outfit-Regular 15 | −0.05 | `.subheadline` |
| `cardFact` | Outfit-SemiBold 15 | −0.10 | `.subheadline` |
| `shelfTitle` | Outfit-Medium 14 | −0.10 | `.subheadline` |
| `listAction` | Outfit-SemiBold 13 | 0 | `.footnote` |
| `metadata` / `rowMeta` | SF `.footnote` (13) | 0 | — |
| `metadataEmphasis` | SF `.footnote` semibold | 0 | — |
| `rowMetaLead` | SF `.footnote` semibold | 0 | — (drawn in `accent`) |
| `sectionLabel` | SF `.caption2` semibold (11) | **+1.0** | — |
| `shelfCaption` | SF `.caption` medium (12) | 0 | — |
| `caption` | SF `.caption2` | 0 | — |
| `prose` | SF `.subheadline` | 0 | — |
| `numberXL` | SF `.largeTitle` bold, monospaced digits | −0.50 | — |
| `time` | SF `.subheadline` semibold, monospaced digits | 0 | — |

### 0.5 Motion (`ThemeMotion`)

| Token | Curve |
|---|---|
| `uiPress` | easeOut 0.09 s |
| `uiMicro` | spring(response 0.22, damping 0.88) |
| `uiSnappy` | spring(0.34, 0.84) |
| `uiSettle` | spring(0.46, 0.90) |
| `uiMilestone` | spring(0.38, 0.74) — series complete only |
| `uiGentle` | easeInOut 0.22 s |
| `uiReveal` | cubic-bezier(0.22, 1.00, 0.36, 1.00) 0.28 s |
| `uiPoster` | easeOut 0.18 s |
| `uiNumeric` | easeOut 0.22 s |
| `uiSweep` | cubic-bezier(0.40, 0.00, 0.20, 1.00) 0.52 s |
| `uiDismiss` | easeIn 0.16 s — toast dismissal only |
| `uiLiveBreath` | easeInOut 1.80 s, repeat forever, autoreverse |
| `uiReduced` | easeOut 0.12 s — the universal Reduce Motion fallback |

`ThemeMotion.pick(token, reduceMotion:)` returns `uiReduced` when Reduce Motion is on. **Every**
animation in this file goes through `pick`, except `ArtHeader`'s drift and `ArtAdaptiveGround`'s tint
fade, which are gated by branching instead.

Transitions:
- `AnyTransition.handoff(reduceMotion:)` — asymmetric: insertion `.opacity` on `uiSettle` **delayed
  0.08 s**, removal `.opacity` on `uiDismiss`. Reduce Motion → plain `.opacity` on `uiReduced`.
  *"the outgoing card leaves first … a symmetric crossfade superimposes two different sentences,
  which is what a smear is."*
- `AnyTransition.toast(reduceMotion:)` — insertion `.opacity` + `.offset(y: 4)` on `uiSnappy`,
  removal `.opacity` on `uiDismiss`. Reduce Motion → `.opacity` on `uiReduced`.

### 0.6 `PosterSize` — the artwork slot table

Named by CONTEXT, never by number, so no screen has to remember a size. **One row slot** (`.row`) for
Library, Search and Schedule.

| Slot | Size (w × h) | Radius | Shadow | Used by |
|---|---|---|---|---|
| `.hero` | 112 × 168 | 12 | `.artHero` | Detail hero |
| `.libraryHero` | 192 × 288 | 14 | `.artHero` | Library carousel |
| `.focus` | 88 × 132 | 10 | `.art` | Today Focus/Recap |
| `.shelfLarge` | 124 × 186 | 12 | `.art` | Library "Returning", Search trending |
| `.shelfMedium` | 112 × 168 | 12 | `.art` | Today "Watching" shelf |
| `.todayShelf` | 100 × 150 | 11 | `.art` | Today's denser resting shelf |
| `.row` | 60 × 90 | 10 | `.none` | **the** list row |
| `.todayQueue` | 52 × 78 | 9 | `.none` | Today's actionable queue |
| `.queue` | 44 × 66 | 8 | `.none` | Today's compact queue |
| `.beat` | 34 × 51 | 6 | `.none` | recap beat |

All are 2:3 (0.667) exactly. `.shelfLarge` was widened from 100 pt *"so a shelf caption's first line
carries a real WORD."*

### 0.7 Haptics (`FeedbackCoordinator`)

Every haptic in the app goes through `FeedbackCoordinator.fire(_:)`; **at most one per transaction**.
Gated by a user setting (`previously.haptics`, default true) and by
`UIApplication.applicationState == .active`. Per-token rate floor: `.selection` = 0.04 s, everything
else = 0.3 s.

| Token | Effect | Fires when |
|---|---|---|
| `.selection` | selection tick | a discrete selected value changed (index rail, week strip) |
| `.commitLight` | light impact, intensity 0.65 | one watch fact recorded |
| `.commitMedium` | medium impact, intensity 0.72 | a larger contiguous progress change |
| `.success` | notification success | season/series complete, title added, rewatch started |
| `.destructive` | notification warning | irreversible deletion accepted |
| `.refreshArmed` | light impact, intensity 0.50 | releasing now will refresh |
| `.directError` | notification error | an explicit action failed |

**No component in `Primitives.swift` fires a haptic itself.** Every primitive that carries an action
(`MarkRing`, `MarkSplitButton`, `MediaRow`, `GroupedRow`, chips) takes a closure; the *screen* decides
whether that closure fires feedback. Do not put haptics inside the Compose components.

---

## 1. Surfaces — `SurfaceLevel`, `.surface(_:radius:)`, `handoffGround`

The surface hierarchy, *"as one decision instead of forty."* The rule:
**tone separates, light describes, strokes are for things that float.**

| Level | Ground | Edge | Shadow | Used by |
|---|---|---|---|---|
| `.plate` | `plateLift` (white 0.055) | **none** | `.none` | grouped lists, section grounds, notices |
| `.raised` | `raisedLift` (white 0.11) | top hairline gradient | `.card` | a card that carries an action |
| `.floating` | `surfaceFloating` (**opaque** `#2A2D36`) | `strokeStrong` all round, 1 pt | `.floating` | toast, sync banner, menu-like chrome |
| `.art(Color?)` | `ArtAdaptiveGround(tint:)` | top hairline gradient | `.card` | Focus / Recap / hero identity cards |

Construction order in `SurfaceModifier`: `background(ground)` → `clipShape(RoundedRectangle(radius,
.continuous))` → `overlay(edge)` → `shadow(level.shadow)`. Default `radius` = `ThemeRadius.card` (22).

**The top hairline** (`.raised`, `.art`): `shape.strokeBorder(LinearGradient(colors: [hairline,
.clear], startPoint: .top, endPoint: .center), lineWidth: 1)`, `allowsHitTesting(false)`. A raised
surface is lit from above, so its highlight lives on the TOP edge and **dies by the vertical centre**.
*"A ring of uniform grey is the thing this replaces."*

**`.floating` stays opaque on purpose:** *"it is the one level that covers content it must never be
mistaken for, and a translucent toast with a shelf scrolling through it is worse than a flat one."*

`ArtAdaptiveGround(tint:intensity:)` (Palette.swift), the ground for `.art`, is a 4-layer ZStack:
1. `surfaceFlat`
2. `LinearGradient([base@0.52·i, base@0.18·i], topLeading → bottomTrailing)`
3. `RadialGradient([base@0.30·i, clear], center (0.16, 0.02), r 0 → 320)` — *"a light source, not a
   flat wash"*
4. `Color.black.opacity(0.30)` — **30 %, not the spec's 44 %**; at 44 the composite landed 4 % above
   canvas and the card read as a hole.

`base` = `tint ?? PaletteCache.fallback (#1C1A17)`. Animated with `uiPoster` on `tint == nil`.

**`handoffGround(tint:radius:)`** (default radius `focusCard` = 24): puts `ArtAdaptiveGround` clipped
to the rounded rect **behind** a container that survives a card swap. Required whenever
`.handoff` transitions two cards in the same slot: *"if the ground belongs to the cards themselves,
the canvas flashes through the gap between them."*

> **Android:** `strokeBorder` insets the stroke fully inside the shape — Compose's `Modifier.border`
> also draws inward, so this maps. The continuous-corner squircle does **not** exist in Compose;
> `RoundedCornerShape` is circular-arc and visibly different at r ≥ 16 on a 100-pt card. Ship a custom
> `Shape` that emits a squircle path (superellipse, n≈5) or accept a visible delta. **Moderate.**
> Shadows are the harder half: iOS shadows are a blurred alpha copy of the shape in an arbitrary
> colour; Compose `Modifier.shadow` is elevation-driven and only honours a custom colour on API 28+
> (`spotShadowColor`/`ambientShadowColor`) with no radius/offset control. Reproduce with a manual
> `drawBehind` + `Paint.asFrameworkPaint().setShadowLayer(radius, 0, y, color)` on a software layer.
> **Moderate-hard.**

---

## 2. Artwork

### 2.0 The image pipeline this file assumes

`RemoteImageView(url:contentMode:maxPixel:alignment:placeholderHidden:fitSnapAspect:)` wraps
`CachedAsyncImage`, which:
- takes a **synchronous** cache hit in `init` so a recycled cell never flashes a placeholder;
- draws the image as an **overlay on a `Color.clear` sizing box**, so the view measures exactly what
  its container proposes. *"an `Image` reports its pixel dimensions as its ideal size … during an
  HStack/ZStack's sizing pass the proposal is nil, so the ideal leaks out and inflates the whole
  enclosing layout."* — this is what threw Schedule's rail off screen;
- fades a freshly-loaded image in with `withAnimation(uiGentle)`; a cache hit has no fade;
- shows `GradientPlaceholder` (linear `#27272F` → `#141418`, topLeading → bottomTrailing) unless
  `placeholderHidden` (every host in this file that draws its own ground passes `true`);
- **fit-snap:** when `contentMode == .fit` and `fitSnapAspect = target` is given, the image switches to
  `.fill` if `abs(imageAspect / target − 1) ≤ 0.08`. Tolerance is 0.08 *"not 0.05: AniList's standard
  cover is 460×654 (0.703) against the 2:3 slot (0.667) — a 5.4 % miss."*
- `maxPixel` bounds the decode on the long edge.

`PaletteCache.shared.resolve(url:maxPixel:)` returns a derived tint (never the raw dominant colour):
downsample to 32×32 → drop alpha < 0.8 and OKLab L < 0.08 or > 0.92 → highest-population non-neutral
(chroma ≥ 0.035) → **clamp L to 0.24…0.38 and C to 0.04…0.12** → fall back to `#1C1A17` when the art is
all-neutral. Memoised per URL; extraction runs on a detached utility task.

### 2.1 `PosterSlot`

Identity artwork filling its slot. Two initialisers:

```
PosterSlot(url:width:height:radius: = .poster, shadow: ShadowToken? = nil)
PosterSlot(url:_ slot: PosterSize)     // size, radius and shadow all from the slot table
```

Default `shadow` in the explicit form: `max(width, height) >= 88 ? .art : .none` — *"art at or above
88 pt on its long edge reads as a physical object and gets one; a 44-pt thumb does not."* The context
form **overrides that heuristic with the slot table**, which is why `.row` (60×90, long edge 90) has
`.none` while the heuristic would say `.art`. The slot table wins.

Layer order (ZStack, then a `frame(width:height:)`):

1. `RoundedRectangle(radius, .continuous).fill(surfaceRaised)`
2. if a palette tint has resolved: same rect filled with `tint.opacity(0.60)`. *"At 0.22 over
   `surfaceRaised` it was still grey."*
3. if `url` non-nil and non-empty: `RemoteImageView(contentMode: .fit, maxPixel: max(w,h) * 3,
   placeholderHidden: true, fitSnapAspect: h > 0 ? w/h : nil)` with
   `.transition(.opacity.animation(uiPoster))`
4. else: SF `photo`, `font(.system(size: min(w, h) * 0.28, weight: .regular))`, `textTertiary`

Then: `clipShape(rounded rect)` → `overlay(rounded rect.strokeBorder(posterEdge, 1))` →
`shadow(shadow)` → `task(id: url) { tint = await PaletteCache.resolve(url:, maxPixel: max(w,h)*3) }` →
**`accessibilityHidden(true)`** (a poster is always described by the row/card around it).

**Why `.fit` and not `.fill`** — the two comments that settle it:
> *"The shipped build aspect-**fitted** every poster into a fixed 2:3 frame. AniList and TMDB covers
> are ~0.708, so every single piece of artwork in the app carried a 5–6 pt bar of exact
> `surfaceRaised` grey across its top and bottom."*
> *"`.fill` was the answer while the ground was grey; with the ground being the artwork's own palette
> colour it is the wrong one. **Posters aspect-fit and stay whole; backdrops fill and crop** … `.fill`
> here side-cropped every asset that is not 2:3: Wistoria's announcement lockup rendered as
> 'son 3 制作'."*

There is deliberately **no blurred backfill** behind a poster: *"it cost a second full decode plus a
blur pass on every slot ≥ 72 pt, i.e. 60 of each on a 30-title grid."*

The edge is `posterEdge` (white 9 %), **never** `separator` (8 %) or `stroke`: *"the job is to stop a
dark poster dissolving into a black canvas, NOT to draw a frame around every piece of artwork."*

> **Android:** straightforward with Coil (`AsyncImage`, `ContentScale.Fit`, `size(maxPixel)`), except
> (a) the fit-snap rule must be implemented manually — read the decoded intrinsic size, compare to the
> slot aspect, swap `ContentScale`; (b) the palette clamp is a Kotlin port of the OKLab maths (no
> androidx.palette equivalent — androidx returns vibrant/muted swatches, not an L/C-clamped derived
> tint). **Easy-moderate.**

### 2.2 `LandscapeArt`

Artwork in a LANDSCAPE frame. `LandscapeArt(url:portraitSource: = false, maxPixel: = 560,
alignment: Alignment = .top)`.

- **`portraitSource == false` (a real banner):** one `RemoteImageView(contentMode: .fill,
  maxPixel:, alignment:, placeholderHidden: true)`. Fills and crops.
- **`portraitSource == true` (a 2:3 cover, no banner):** composited, two layers in a ZStack —
  1. ground: `RemoteImageView(.fill, maxPixel: **160**, alignment: .center)` `.blur(radius: 28,
     opaque: true)` `.overlay(Color.black.opacity(0.32))`
  2. subject: `RemoteImageView(.fit, maxPixel: maxPixel, alignment: .center)`
     `.padding(.vertical, ThemeSpace.x2 = 8)`
     `.shadow(color: .black.opacity(0.45), radius: 8, y: 4)` — *"A contact shadow separates the sharp
     cover from its own blurred ground — without it the two read as one badly-decoded image."*

> *"A portrait cover … `.fill`ed into a 1.6–2.1:1 frame, a 2:3 poster shows the middle third of itself
> — a forehead, a white slab, a fragment of a lockup — which is what the Library's Announced shelf and
> Search's trending wall did for every show the catalogue has no banner for (about a third of them)."*

**Contract:** a landscape frame must NEVER `.fill` a portrait cover. Callers pass `portraitSource:`
from the model's `wideArt` (`WideArt = url + portraitSource`).

> **Android:** `Modifier.blur` requires **API 31+**; below that it is a silent no-op. Options: bump
> `minSdk` to 31, or render the ground through a downsample-and-upscale Coil transformation (decode at
> ~32 px and let the scaler smear it), or RenderScript-free `Toolkit.blur`. `blur(opaque: true)` means
> edges are clamped rather than fading to transparent — Compose's blur has
> `BlurredEdgeTreatment.Rectangle` for the same effect. **Moderate.**

### 2.3 `BannerCard`

*"A wide art card that sells a show: banner art on top, the title and one caption beneath."*
This object existed three times before the 30 Aug cohesion pass (104 pt/r13, 176 pt/r18, r22) — **one
geometry now**.

```
BannerCard(title:lead: = nil, meta: = nil, art: = nil,
           portraitSource: = false, zoomID: = nil, action:)
static let height: CGFloat = 104
private static let maxPixel: CGFloat = 560
private var caption: String? { lead ?? meta }
```

Layout — a `Button` whose label is `VStack(alignment: .leading, spacing: ThemeSpace.x2 = 8)`:

1. **banner** — `ZStack { RoundedRectangle(ThemeRadius.card = 22, .continuous).fill(surfaceRaised);
   LandscapeArt(url: art, portraitSource:, maxPixel: 560) }`,
   `.frame(maxWidth: .infinity).frame(height: 104)`, `clipShape(shape)`,
   `overlay(shape.strokeBorder(posterEdge, 1))`, `shadow(.art)`,
   `modifier(OptionalZoomSource(id: zoomID))`.
2. **copy** — `VStack(alignment: .leading, spacing: ThemeSpace.x0_5 = 2)`:
   - `Text(title.shelfShortened)` · `shelfTitle` · `textPrimary` · `lineLimit(1...2)` ·
     `minimumScaleFactor(0.82)` · `allowsTightening(true)` · leading alignment.
     **Never truncated** (DIRECTION §3) — *"the compact card shipped `lineLimit(1)` and amputated the
     identity titles the rule exists for."*
   - if `caption != nil`: `Text(caption)` · `shelfCaption` ·
     **`lead != nil ? accent : textSecondary`** · `lineLimit(2)` · `truncationMode(.tail)`.

`contentShape(Rectangle())`, `buttonStyle(OverArtPressStyle())`.

**The caption rule is enforced here so a screen cannot opt out of it again:** a forward-looking fact
("Returns today") is accent; a plain fact is grey. *"Library hard-coded grey and rendered the identical
class of fact Today draws amber — the app's central colour rule answered two ways one tab apart."*

**Accessibility:** `accessibilityElement(children: .combine)`;
label = `[title, caption]` joined with `", "` — **the whole title, never the shortened one**;
hint = `Copy.Accessibility.opensTheShowHint` = `"Opens the show"`.

### 2.4 `ProgressBanner`

*"One wide piece of art with where-you-are drawn ON it … Apple TV's Up Next card."* The ONE 16:9
art-with-progress card. Library's *Continue watching* cards and the season screen's header are this
same view.

```
ProgressBanner(url:portraitSource: = false, progress: Double? = nil,
               maxPixel: = 900, zoomID: = nil)
static let inset: CGFloat = ThemeSpace.x3   // 12
```

ZStack, `alignment: .bottom`:
1. `RoundedRectangle(ThemeRadius.card = 22, .continuous).fill(surfaceRaised)`
2. `LandscapeArt(url:, portraitSource:, maxPixel: 900)`
3. `LinearGradient([.clear, ThemeColor.scrim], .top → .bottom).frame(height: 56)`,
   `allowsHitTesting(false)` — *"The bar reads on any art: a short scrim under it, never a plate."*
   (Bottom-aligned by the ZStack, so it is the bottom 56 pt.)
4. if `progress != nil`: `ProgressBar(value:)` `.padding(.horizontal, 12).padding(.bottom, 12)`

Then `.aspectRatio(16.0/9.0, contentMode: .fit)` → `clipShape(shape)` →
`overlay(shape.strokeBorder(posterEdge, 1))` → `shadow(.art)` → optional zoom source.

**16:9 BY RATIO, never a fixed height.** From `CLAUDE.md`: *"a fixed height plus a gutter applied twice
had drawn every card 16 pt inside its own day header — two left edges on one screen."*

The card carries no text. A numeral, where a screen wants one, sits on the title's baseline **beneath**
it, never in the picture.

### 2.5 `ArtHeader`

*"A cinematic, edge-to-edge art header with content laid over its lower third."* The one billboard
hero grammar, used by Today AND Detail.

```
ArtHeader(url:height:tint: = nil, scrimTop: Double = 1, scrimBottom: Double = 1,
          focus: Alignment = .top, portraitSource: Bool = false, drift: Bool = false,
          overlay: () -> Overlay)
```

`height` is the **full** art height, safe area included; 0.44–0.52 × screen is called the cinematic
band in the doc comment, and `CLAUDE.md` pins the shipped billboard at **0.68–0.72 × screen**.

ZStack, `alignment: .bottom`:
1. `(tint ?? PaletteCache.fallback)` — a flat colour, so the header never flashes black
2. artwork, if `url` non-empty:
   - **`portraitSource == true`:**
     ground `RemoteImageView(.fill, maxPixel: 1024, alignment: .center, placeholderHidden: true)`
     `.blur(radius: 48, opaque: true).overlay(Color.black.opacity(0.28))`;
     subject `RemoteImageView(.fit, maxPixel: **2048**, alignment: focus, placeholderHidden: true)`
     `.scaleEffect(driftScale, anchor: driftAnchor).transition(.opacity)`.
     *"2048, not the ground's 1024: Today's billboard hero draws this layer at ~1770 px tall, and
     capping the decode below that softened the one sharp asset in the frame."*
   - **`portraitSource == false`:** one `RemoteImageView(.fill, maxPixel: 1536, alignment: focus,
     placeholderHidden: true)` `.scaleEffect(driftScale, anchor: driftAnchor).transition(.opacity)`
3. `ArtScrim(top: scrimTop, bottom: scrimBottom)`
4. `overlay()` — `padding(.horizontal, ThemeMetrics.gutter = 16)`,
   `padding(.bottom, ThemeSpace.x5 = 20)`, `frame(maxWidth: .infinity, alignment: .leading)`

Then `.frame(height: height).frame(maxWidth: .infinity).clipped()`.

**`focus` is an `Alignment`, not a `UnitPoint`,** because it is handed straight to
`RemoteImageView(alignment:)`. *"Hard-coding `.top` is why one hero was a forehead and another was a
logo."*

**Drift** (`drift: true`, Today's and Detail's billboards only — *nothing else in the app drifts*):
`driftScale = drifting ? 1.07 : 1`;
`driftAnchor = focus == .top ? .top : (focus == .bottom ? .bottom : .center)`;
in `.task(id: drift && !reduceMotion)`: bail (and reset `drifting = false`) unless `drift &&
!reduceMotion`, **sleep 80 ms**, bail if cancelled, then
`withAnimation(.easeInOut(duration: 24).repeatForever(autoreverses: true)) { drifting = true }`.
> *"A beat after insertion: an animation started in the same transaction as the view's own appearance
> is folded into it and never repeats."*
> *"~7 % over 24 s, eased, reversing: under the threshold where it reads as motion, over the one where
> the frame reads as a still pinned to a wall … It is one transform animation on one layer, so no body
> re-evaluates for it (the scroll-lag rule of 2 Sep still holds)."*

### 2.6 The scrims — `ArtScrim`, `HeroTopVeil`, `HeroCopyScrim`

All three are `allowsHitTesting(false)` + `accessibilityHidden(true)`, full-width, top→bottom linear
gradients. **Nobody hand-rolls a black overlay.**

**`ArtScrim(top: Double = 1, bottom: Double = 1)`** — one gradient with a *transparent middle*, so the
art is never uniformly greyed:

| Location | Colour |
|---|---|
| 0.00 | black @ `0.55 × top` |
| 0.22 | black @ `0.16 × top` |
| 0.46 | clear |
| 0.80 | `canvas` @ `0.55 × bottom` |
| 1.00 | `canvas` @ `1.00 × bottom` |

**`HeroTopVeil(band: CGFloat, ramp: CGFloat = 100)`** — protection over the status bar and the chrome
band at the top of a billboard. `total = band + ramp`; `mark = band / total`. Height = `total`.

| Location | Colour |
|---|---|
| 0 | black @ 0.72 |
| `mark × 0.72` | black @ 0.66 |
| `mark` | black @ 0.52 |
| `mark + (1 − mark) × 0.30` | black @ 0.30 |
| `mark + (1 − mark) × 0.62` | black @ 0.12 |
| 1 | clear |

> *"A ramp that holds flat and then falls reads, over bright key art, as a hard-edged plate laid on the
> picture right where the brand mark (or the back button) is; a veil that can be *seen* is not
> protection, it is a smudge."* Six stops exist so no single step is visible.

**`HeroCopyScrim(copyHeight: CGFloat, lead: CGFloat = 72)`** — protection BEHIND a hero's copy, sized
to the copy's **measured** height at every type size. `h = max(1, copyHeight + lead + 8)`;
height = `h`.

| Location | Colour |
|---|---|
| 0 | clear |
| `min(0.99, lead × 0.4 / h)` | `canvas` @ 0.16 |
| `min(0.99, lead × 0.7 / h)` | `canvas` @ 0.44 |
| `min(0.99, lead / h)` | `canvas` @ 0.72 |
| `min(0.995, (lead + 56) / h)` | `canvas` @ 0.90 |
| 1 | `canvas` @ 1.00 |

> *"The stops are placed in POINTS off the measured copy height, not as fractions of the image. A fixed
> fraction is a different physical distance at every type size, which is how AX1 came to set a
> three-line 44-pt title over a face at ~55 % luminance while the same stops were comfortable at
> default size."*
> Full canvas at location 1 is mandatory: *"the 3 % of photograph left glowing through at the exact
> line where the hero meets the canvas rendered as a faint band across the screen — the scrim must
> LAND, not hover."*

A resting billboard uses `HeroCopyScrim` **instead of** a fractional `ArtScrim` bottom (Today and
Detail pass `scrimBottom` accordingly); `lead` is long *"because this is the only bottom protection on
a resting billboard."*

### 2.7 `StretchingHeroArt` (TodayView.swift, private)

The hero's art grown by the pull-down. **The frame the layout sees never changes** — everything below
travels with the pull, once; only the art is taller and bottom-aligned, so it fills the rubber band.

```
ArtHeader(url:, height: height + scroll.stretch, tint:,
          scrimTop: 0, scrimBottom: scrimBottom,
          focus: .top, portraitSource: portrait, drift: true) { EmptyView() }
```

`focus: .top` because *"Faces live in the upper third of a key visual and in the upper half of a cover;
a centred crop of either is a chin."* This is one of only two views in the app allowed to read
`ScrollOffset.y` in its body (see §11).

### 2.8 Episode artwork — `EpisodeArtwork`, `EpisodeGlyphTile`, `EpisodeStill`

Three related slots; **`EpisodeStill` is the shipped one** (Detail + Season list, per `CLAUDE.md`:
*"EVERY episode row carries a 120×68 tile"*). `EpisodeArtwork` is the older tile and is still the
owner of the canonical slot size.

`EpisodeArtwork.slot = CGSize(width: 120, height: 68)` (16:9). Radius everywhere is
`ThemeRadius.episodeStill = 8`; edge everywhere is `posterEdge` 1 pt.

**`EpisodeArtwork(url:spoilerSafe: Bool = true, showTint: Color? = nil)`**
`hasStill = spoilerSafe && !(url ?? "").isEmpty`.
- has a still → ZStack: rounded rect filled `tint ?? surfaceRaised`; SF `photo` at 16 pt regular in
  `textTertiary` **under** the image (so a fetch that never resolves leaves tint + glyph, not a bare
  rectangle); `RemoteImageView(.fill, maxPixel: 288)`. `.animation(pick(uiPoster, reduceMotion),
  value: tint)`. Palette resolved in `.task(id: url)` at `maxPixel: 288`.
- otherwise → `EpisodeGlyphTile(showTint:)`: rounded rect filled `showTint ?? surfaceRaised`, overlaid
  with `LinearGradient([black 0.10, black 0.34], top → bottom)` and SF `play.rectangle` at 17 pt
  regular in `textPrimary.opacity(0.34)`.
- whole thing `accessibilityHidden(true)`.

> *"a spoiler-protected still is **replaced, never blurred** — a blur is a tease with no VoiceOver
> equivalent."* *"The episode number is drawn exactly once, in the row's text."*
> *"one rectangle for every episode row, still or not"* — the shipped build changed shape halfway down
> a season list.

**`EpisodeStill(url:landscape: = nil, poster:, tint: = nil, width: CGFloat? = EpisodeArtwork.slot.width
(120), number: Int? = nil)`** — the fallback CHAIN, in order:

| # | Condition | Draws |
|---|---|---|
| 1 | `url` non-empty | `RemoteImageView(.fill, maxPixel: (width ?? 400) × 3)` — no gradient, **no numeral** |
| 2 | `landscape` non-empty | `.fill` at `(width ?? 400) × 3`, alignment `.center`, + `LinearGradient([black 0.20, black 0.46])` |
| 3 | `poster` non-empty | `.fill` at `(width ?? 400) × 3`, alignment **`.top`**, + `LinearGradient([black 0.25, black 0.50])` |
| 4 | nothing | `LinearGradient([black 0.10, black 0.34])` over the tint — **no glyph** |

Ground beneath all four: `RoundedRectangle(8, .continuous).fill(stillTint ?? tint ?? surfaceRaised)`.
`stillTint` = `DetailTint.quiet(await PaletteCache.resolve(url: url ?? landscape ?? poster,
maxPixel: 288))` in `.task(id: url ?? landscape ?? poster)`.

**Numeral:** drawn **only when `number != nil` && there is no still** —
`Text("\(number)")`, `.system(size: 17, weight: .bold).monospacedDigit()`, `textPrimary`,
`shadow(color: black 0.55, radius: 3, y: 1)`, `frame(maxWidth/.maxHeight: .infinity, alignment:
.bottomLeading)`, `padding(7)`.

Frame: `.aspectRatio(16/9, .fit)`, `.frame(width: width)`, `.frame(maxWidth: width == nil ? .infinity :
nil)` — `nil` width fills the row it is offered (the accessibility-size card). `accessibilityHidden(true)`.

> *"**A glyph is only honest where there is no art at all, and there is always art — the season has a
> poster.**"* Poster crop anchors `.top` *"because a 2:3 cover carries the face in its upper half and
> the logotype band in its lower one."* A real still is never labelled: *"the row's text is 8 pt away."*
> The guard against a wall of one repeated poster lives **upstream** in
> `SeasonEpisodesView.artPolicy`, which drops the art column entirely for a barely-illustrated season.

---

## 3. Rows and cards

### 3.1 `MediaRow`

*"The canonical repeating row: artwork, an identity title, one fact, one optional forward-looking fact
in accent, and a trailing control. Library, Schedule, Search and Detail all render this shape; the
shipped build hand-rolled it four times at four sizes with four different poster slots, which is most
of why the app read as four apps."*

**It sits on the CANVAS with a hairline under it — not inside a stroked box. A list of shows is not a
form.**

```
MediaRow<Trailing: View>(
  title: String,
  meta: String? = nil,          // one fact, textSecondary
  lead: String? = nil,          // the forward-looking fact, ACCENT
  poster: String? = nil,
  slot: PosterSize = .row,
  chevron: Bool = true,
  dimmed: Bool = false,
  separator: Bool = true,
  hint: String? = nil,          // VoiceOver action hint
  zoomID: String? = nil,
  progress: Double? = nil,
  progressSpoken: String? = nil,
  trailing: () -> Trailing,
  action: () -> Void)
```
A convenience `init` with `Trailing == EmptyView` omits the `trailing:` closure (note: it does **not**
forward `progressSpoken`, which therefore defaults to nil on that path).

**Geometry** — a `Button` whose label is `HStack(spacing: ThemeMetrics.artGap = 14)`:

| Element | Rule |
|---|---|
| poster | drawn only when `poster != nil`; `PosterSlot(url: poster, slot)`, wrapped in `.zoomSource(zoomID)` when given |
| text column | `VStack(alignment: .leading, spacing: ThemeMetrics.titleGap = 3)` |
| — title | `rowTitle` · `textPrimary` · `lineLimit(isAX ? nil : 2)` · `fixedSize(h: false, v: true)` |
| — lead | `rowMetaLead` · **`accent`** · `fixedSize(h: false, v: true)` |
| — meta | `rowMeta` · `textSecondary` · `fixedSize(h: false, v: true)` |
| — progress | `ProgressBar(value:)` · `.padding(.top, ThemeSpace.x1 = 4)` · `.padding(.trailing, ThemeSpace.x6 = 24)` |
| spacer | `Spacer(minLength: ThemeSpace.x3 = 12)` |
| trailing | the caller's view |
| chevron | SF `chevron.forward`, `.system(size: 13, weight: .semibold)`, **`textDisabled`**, `frame(width: 11, alignment: .trailing)`, `accessibilityHidden(true)` |

Row-level: `padding(.trailing, listTrailingInset)` → `padding(.vertical, ThemeSpace.x2 = 8)` →
`frame(minHeight: minimumRowHeight, alignment: .leading)` → `contentShape(Rectangle())` →
`opacity(dimmed ? 0.72 : 1)` → bottom-aligned separator overlay.

`minimumRowHeight` = `ThemeMetrics.rowStandard (88)` for `.queue` and `.todayQueue`;
`ThemeMetrics.rowMedia (100)` for every other slot. *"Catalogue rows keep the heavier height."*

**Separator:** `Rectangle().fill(separatorQuiet).frame(height: 1)` with
`padding(.leading, poster == nil ? 0 : slot.size.width + artGap)` — i.e. 74 pt for `.row`. Drawn as a
bottom-aligned overlay **inside the button label**, so it dims with `dimmed` and highlights with the
press.

**Order note:** `lead` is drawn **above** `meta`. The forward-looking amber fact sits directly under the
title.

**`dimmed` is 0.72, not 0.45.** *"0.45 was not 'recessed', it was unreadable: `textSecondary` at 0.45
over the canvas composites to ≈#515151, i.e. 2.64:1, and it was applied to exactly the rows being
scanned for a date (Schedule's past week, Detail's unaired episodes). 0.72 lands at ≈5.4:1 and still
reads as a group that has stepped back."* It is **one opacity on the whole row group**, never per
element — *"one opacity keeps the artwork's colour relationship intact."*

**The chevron is a FIXED 11-pt column.** *"It was concatenated into the title … the glyph's x became a
function of title length, and it was measured at 370 / 418 / 520 / 600 / 712 down a single list — five
different right edges in one column of a list whose whole job is to be scanned."*

**`@Entry var listTrailingInset: CGFloat = 0`** (an `EnvironmentValues` entry declared in this file):
*"Width a list reserves along its trailing edge for chrome that floats over it — today that is
Library's A–Z index rail."* Set once on the list (`LibraryView` sets it to `LibraryAllView.railLane`
= 28 when the rail is on); every `MediaRow` inside stops short of the strip. *"Without it a fixed
trailing chevron and a rail letter can land on the same 4 pt of screen."*

**Press:** `buttonStyle(RowPressStyle())` (radius `ThemeRadius.row` = 16 — see §7).

**Accessibility:** `accessibilityElement(children: .combine)`;
label = `[title, lead, meta, progress == nil ? nil : progressSpoken]` compacted and joined with
`", "` — **spelled out rather than left to `.combine`, so the trailing chevron is never spoken**;
hint = `hint ?? ""`. At an accessibility text size the title's line limit becomes unbounded.

### 3.2 `ShelfCard`

One poster on a horizontal shelf.

```
ShelfCard(title:caption: = nil, captionIsLead: Bool = false, poster: = nil,
          slot: PosterSize = .shelfLarge, zoomID: = nil, action:)
```

`VStack(alignment: .leading, spacing: ThemeSpace.x2 = 8)`:
1. `PosterSlot(url: poster, slot)` (wrapped in `zoomSource` when `zoomID` is given)
2. `VStack(alignment: .leading, spacing: 2)`:
   - title: `Text(title.shelfShortened)` · `shelfTitle` · `textPrimary` ·
     `lineLimit(isAX ? 1...6 : 1...2)` · `minimumScaleFactor(0.82)` · `allowsTightening(true)` ·
     `multilineTextAlignment(.leading)` · **`fixedSize(horizontal: false, vertical: true)`**
   - caption (if any): `shelfCaption` · `captionIsLead ? accent : textSecondary` · `lineLimit(2)` ·
     `truncationMode(.tail)`
   - the copy VStack is `frame(width: isAX ? nil : slot.size.width, alignment: .leading)` then
     `frame(maxWidth: isAX ? .infinity : nil, alignment: .leading)`

`contentShape(Rectangle())`, `buttonStyle(RowPressStyle(radius: slot.radius))`.

**Two corrections encoded here:**
> *"NOTHING reserved: the caption sits directly under the title, one line or two. Reserving a second
> line put an empty band between every one-line name and its date (user, 24 Aug)."*
> *"The title takes its WRAPPED height, whatever the shelf proposes. On Today's Watching shelf a
> two-line name was photographed scaled down and cut to one line with an ellipsis ('The Beginning
> After…', 2 Sep) — the horizontal scroller had handed the card a one-line height budget and the range
> limit obeyed it. The rule is the identity title never ellipsizes; a fixed vertical size is what makes
> the range mean 'up to two' rather than 'whatever fits'."*

The caption's ellipsis IS allowed: *"Two lines and a tail ellipsis, so the last visible caption ends
inside its own card instead of at the screen bezel."*

**Accessibility:** `.combine`; label = `[title, caption]` joined `", "` — **the whole title, never the
shortened one**.

### 3.3 `String.shelfShortened`

Identity titles as a shelf caption can carry them. Deterministic, pure:

```swift
var s = trimmingCharacters(in: .whitespacesAndNewlines)
if s.hasSuffix("-"), let open = s.range(of: " -") { s = String(s[s.startIndex..<open.lowerBound]) }
s = s.trimmingCharacters(in: CharacterSet(charactersIn: " -–—:"))
if s.count > 40 {
    for sep in [": ", " – ", " — ", " - ", " ("] {
        if let r = s.range(of: sep), s.distance(from: s.startIndex, to: r.lowerBound) >= 12 {
            return String(s[s.startIndex..<r.lowerBound])
        }
    }
}
return s
```

Step 1 strips a trailing `-…-` subtitle wrapper (finds the **first** `" -"`).
Step 2 trims spaces, hyphen, en dash (U+2013), em dash (U+2014) and colon from **both** ends.
Step 3, only for a result longer than 40 characters, cuts at the first of `": "`, `" – "`, `" — "`,
`" - "`, `" ("` that starts at index ≥ 12.

> *"Source titles arrive wrapped in subtitle punctuation — 'Re:ZERO -Starting Life in Another World-' —
> and a line that opens on a hyphen reads as a hyphenation bug, not as a title."*

Note the `"Re:ZERO"` case: the `": "` separator requires a **space** after the colon, so `Re:ZERO`
survives intact.

### 3.4 `View.shelfScroller(trailingMargin: CGFloat = 40, masked: Bool = true)`

The horizontal-shelf scroller: **art may run off the trailing edge, TYPE may not.**

- `contentMargins(.trailing, trailingMargin, for: .scrollContent)`
- a `.mask` that is a horizontal `LinearGradient(leading → trailing)` when
  `masked && !typeSize.isAccessibilitySize`, otherwise a plain `Rectangle()`:

| Location | Colour |
|---|---|
| 0 | black |
| 0.86 | black |
| 0.95 | black @ 0.45 |
| 1 | black @ 0 |

- the mask is `.padding(.vertical, -24)` — **vertically oversized on purpose**: *"A mask is clipped to
  its own bounds, so a mask exactly the scroller's height would undo `.scrollClipDisabled()` and shear
  the posters' `.art` shadow into a hard line along each card's edge — trading one clipping artefact
  for another."*

> *"`trailingMargin` 40, not 28: at 28 the peeking card's caption still reached the bezel and sheared
> mid-word ('Avatar:', 'Caught u', 'So', 'Re') because the fade only covered the last 7 % (~30 pt) of
> the viewport."* At accessibility sizes the shelf is already a vertical list, so the mask is skipped.

---

## 4. Section furniture

**One section-header family: `SectionHeaderRow`.** Small-caps `SectionLabel` is an EYEBROW only —
never a shelf header.

### 4.1 `SectionHeaderRow` (Primitives+States.swift)

```
SectionHeaderRow(_ text: String, count: Int? = nil, dot: Bool = false,
                 actionLabel: String? = nil, inlineAction: Bool = false,
                 action: (() -> Void)? = nil)
```

`HStack(alignment: .firstTextBaseline, spacing: ThemeSpace.x2 = 8)`. Three shapes:

**A — navigating header** (`action != nil && !inlineAction`): the whole `title + count + chevron` group
IS the button.
`HStack(alignment: .firstTextBaseline, spacing: 6) { title; countLabel; Image("chevron.forward")
.font(.system(size: 14, weight: .semibold)).foregroundStyle(textTertiary).accessibilityHidden(true) }`,
`buttonStyle(SectionHeaderPressStyle())`, **`.padding(.vertical, -10)`**,
`accessibilityLabel("\(text), \(actionLabel ?? Copy.Action.seeAll)")` (default trailing word
`"See all"`), `accessibilityAddTraits(.isHeader)`.

**B — plain header** (no action, or `inlineAction`): `title.accessibilityAddTraits(.isHeader)` then
`countLabel`.

**C — inline command** (`inlineAction && actionLabel != nil && action != nil`): after
`Spacer(minLength: 8)`, `Button(actionLabel, action:)` with `buttonStyle(InlineLinkButtonStyle())` and
**`.padding(.vertical, -12)`**.

`title` = `HStack(alignment: .center, spacing: 6) { if dot { Circle().fill(accent).frame(5×5) };
Text(text).type(sectionTitle).foregroundStyle(textPrimary).lineLimit(1).minimumScaleFactor(0.85) }`.

`countLabel` = `Text("\(count)")` · `metadata` · **`textTertiary`** · `monospacedDigit()`, on the
title's baseline. *"`textDisabled` is reserved for glyphs."*

Whole row: `.zIndex(1)` and `accessibilityElement(children: .contain)`.

> **The negative padding + zIndex pair is load-bearing.** `SectionHeaderPressStyle` pads the target out
> to 44 pt; the negative padding pulls the header's *layout* back to the title's own height, so a stack
> is not shoved 20 pt taller. *"The negative padding leaves the button DRAWING and HIT-TESTING above
> and below the row's layout rect. Siblings laid out after the header would otherwise win the taps in
> the lower overlap band whenever the stack's spacing is under 10 pt, quietly eating the bottom quarter
> of a 44-pt target. The header paints (and tests) above them."*

> **The design rule:** *"Every shelf in Apple TV, Netflix and Apple Music is headed by a bold mixed-case
> title ('Continue Watching ›'), tappable as a unit; this app headed its shelves with an 11-pt
> small-caps footnote and hung a 13-pt 'See all' off the far edge, so the section's name was the
> quietest thing in the section and its action was a word to hunt for. The chevron carries the
> affordance now."* **There is no "See all" word in the header** — the title IS the button.

`SectionHeaderPressStyle`: `padding(.vertical, 10)` → `frame(minHeight: 44)` →
`contentShape(Rectangle())` → `opacity(isPressed ? 0.55 : 1)` → `animation(pick(uiPress,
reduceMotion), value: isPressed)`.

### 4.2 `SectionLabel`

Eyebrow only. `SectionLabel(text:dot: Bool = false, tint: Color = textSecondary)`.

`HStack(alignment: .firstTextBaseline, spacing: 6)`:
- if `dot`: `Circle().fill(accent).frame(width: 4, height: 4)` — **the 4-pt leading dot means "newly
  changed" only**
- `Text(text).type(sectionLabel).textCase(.uppercase).fixedSize(horizontal: false, vertical: true)`

`foregroundStyle(tint)`, `lineLimit(typeSize.isAccessibilitySize ? 2 : 1)`.

> Tint is `textSecondary`, *"one step up from the `textTertiary` it shipped at: the label is the
> section's IDENTITY, and at tertiary it was outweighed by its own trailing 'See all' — the utility
> link read as the header and the header read as a footnote."*

Legal uses now: `OverArtLabel` over art, grouped-list headers, sheet labels, Schedule's day headers
("TODAY · THU 3 SEP") and its Earlier row.

### 4.3 `OverArtLabel`

An eyebrow that sits ON artwork — "CONTINUE", "NEW EPISODE", "AIRED 10H AGO".

`OverArtLabel(text:dot: Bool = false, tint: Color = textPrimary)`:
`HStack(spacing: 6) { if dot { Circle().fill(accent).frame(5×5) };
Text(text).type(sectionLabel).textCase(.uppercase) }`
→ `foregroundStyle(tint)` → `padding(.horizontal, 10)` → `frame(height: 24)` →
`background(ThemeColor.scrimStrong, in: Capsule())` →
`overlay(Capsule().strokeBorder(ThemeColor.hairline, lineWidth: 1))`.

> *"Over a photograph, plain tertiary-grey caps are unreadable half the time and washed out the rest. A
> dark capsule makes it legible over anything and reads as a label rather than as text that happens to
> be floating."*

Note the dot here is **5 pt** (`SectionLabel`'s is 4 pt); the height is a hard 24 pt and does **not**
grow with Dynamic Type.

---

## 5. Grouped list

Inset grouped list in the system grammar.

### 5.1 `GroupedList(header: String? = nil, content:)`

`VStack(alignment: .leading, spacing: ThemeMetrics.labelGap = 10)`:
1. if `header != nil`: `SectionLabel(text: header).padding(.leading, ThemeSpace.x4 = 16)` +
   `accessibilityAddTraits(.isHeader)` — *"VoiceOver's heading rotor is how a grouped screen is
   skimmed; without the trait a five-section settings page had one stop."*
2. `VStack(spacing: 0) { content() }.surface(.plate, radius: ThemeRadius.row = 16)`

> *"A plate, not a stroked box: this is the iOS grouped-table grammar, and a grouped table has never had
> an outline. The fill IS the group."*

### 5.2 `GroupedTrailing`

```swift
enum GroupedTrailing { case chevron(String?), value(String), toggle(Binding<Bool>), check(Bool), none }
```

### 5.3 `GroupedRow`

```
GroupedRow(symbol: String? = nil, symbolTint: Color = Color(hex: 0x3A3D45),
           title: String, subtitle: String? = nil, warning: Bool = false,
           trailing: GroupedTrailing = .none, separator: Bool = true,
           action: (() -> Void)? = nil)
```

**Two structural branches, and the branch matters for accessibility:**

- **`.toggle(binding)`** → a real `Toggle(isOn:) { labelStack }` with `toggleStyle(.switch)` and
  **`tint(ThemeColor.accent)`** (a switch means STATE, so amber is legal).
  *"A `Toggle` inside a `Button`'s label does not survive as an independent element: VoiceOver announced
  'Unwatched only, button' with no switch trait and no On/Off value, and the outer button's hit-test
  priority made the switch itself unreliable to hit. The toggle case therefore renders a real `Toggle`
  whose LABEL is the row — one element, with the switch trait, a spoken value, and the whole row as its
  target."*
- **everything else** → `Button { action?() } label: { HStack(spacing: 12) { labelStack;
  Spacer(minLength: 8); trailingView } }`, `buttonStyle(GroupedRowPressStyle())`,
  `.disabled(action == nil)`.

Both branches share: `padding(.leading, 14)`, `padding(.trailing, 16)`,
`frame(minHeight: ThemeMetrics.rowCompact = 56)`, bottom-aligned `separatorLine` overlay. The button
branch additionally sets `contentShape(Rectangle())`.

**`labelStack`** = `HStack(spacing: 12)`:
- optional symbol tile: `Image(systemName: symbol)` · `.system(size: 15, weight: .medium)` ·
  `textPrimary` · `frame(28 × 28)` · `background(symbolTint, in: RoundedRectangle(cornerRadius: 7,
  style: .continuous))`
- `VStack(alignment: .leading, spacing: 1)`:
  - `HStack(spacing: 8) { Text(title).type(body).foregroundStyle(textPrimary);
    if warning { Circle().fill(ThemeColor.warning).frame(8 × 8) } }`
  - optional `Text(subtitle).type(metadata).foregroundStyle(textSecondary)
    .fixedSize(horizontal: false, vertical: true)`
- `.frame(maxWidth: .infinity, alignment: .leading)`

**`separatorLine`** (when `separator`): `Rectangle().fill(separatorQuiet).frame(height: 1)`
`.padding(.leading, symbol == nil ? 14 : 54)`. *"`separatorQuiet`: eight of these down one plate at 8 %
white is a grid."*

**`trailingView`:**

| Case | Drawing |
|---|---|
| `.chevron(value)` | `HStack(spacing: 6)`: optional `Text(value).type(body).foregroundStyle(textTertiary)`, then SF `chevron.forward` `.system(size: 13, weight: .semibold)` in `textTertiary` |
| `.value(v)` | `Text(v).type(body).foregroundStyle(textTertiary)` |
| `.toggle` | `EmptyView()` — *"a switch is never drawn inside a Button"* |
| `.check(on)` | SF `checkmark` `.system(size: 15, weight: .semibold)`, **`accent`**, `opacity(on ? 1 : 0)`, `frame(width: 22)` — the reserved width keeps the column stable |
| `.none` | `EmptyView()` |

**`GroupedRowPressStyle`:** `background(isPressed ? surfacePressed : .clear)` +
`animation(pick(isPressed ? uiPress : uiMicro, reduceMotion), value: isPressed)`. *"The shipped style
had NO animation at all: the pressed ground snapped on and off in one frame, in both directions, on
the densest grouped-row screens in the app."* Note the **asymmetric animation choice** — press-in on
`uiPress` (easeOut 0.09), release on `uiMicro` (spring). The same pair appears in `RowPressStyle`.

Note there is no clipping on the row itself; the pressed ground is clipped by the `.plate` surface
around the whole `GroupedList`, which is why the first and last rows get rounded press highlights for
free.

---

## 6. Progress and the mark

### 6.1 `ProgressBar`

*"The one progress bar."* `ProgressBar(value: Double, spoken: String? = nil)`.

```
GeometryReader { proxy in
  let ratio = min(1, max(0, value))
  ZStack(alignment: .leading) {
    Capsule().fill(ThemeColor.strokeStrong)
    Capsule().fill(ThemeColor.accent).frame(width: max(3, proxy.size.width * ratio))
  }
}
.frame(height: 3)
```

- height **3 pt**, track `strokeStrong` (white 0.20), fill `accent`, both capsules
- **3-pt minimum fill** *"so a started season is never a zero-width fill"*
- `value` is clamped to 0…1
- **wordless on purpose** — it replaces "11 of 24 watched" wherever a row or header can show it instead
  of saying it
- `accessibilityHidden(spoken == nil)` + `accessibilityLabel(spoken ?? "")`.
  *"Without it the bar is decoration and hidden; a label set on a hidden element from outside was
  silently dropped, which is how Today's hero came to say its count to nobody."*

### 6.2 `DrawnCheck`

**The check DRAWS.** `DrawnCheck(on: Bool, size: CGFloat = 14, tint: Color = onAccent)`.

`Image(systemName: "checkmark").font(.system(size: size, weight: .bold)).foregroundStyle(tint)`
masked, **leading-aligned**, by `GeometryReader { geo in Rectangle().frame(width: geo.size.width *
progress) }`.

`onChange(of: on, initial: true)`: when `on == false` → `progress = 0` immediately; when `on == true` →
`progress = 1` immediately if Reduce Motion, else `withAnimation(ThemeMotion.uiMicro) { progress = 1 }`.
`accessibilityHidden(true)`.

> *"Nowhere in the shipped build did it: every tick was an opacity crossfade or a scale pop, so the one
> moment the product exists to deliver had no signature motion. The mark is masked left-to-right as it
> lands, which is what a hand-drawn tick does — and under Reduce Motion it is simply there, at full
> width, with no animation to suppress."*

**Hard rule, stated twice in the file:** `DrawnCheck` must be **mounted unconditionally**. A
conditional insert hands SwiftUI an implicit opacity transition *on top of* the mask and the signature
motion renders as a smear. Collapse it to zero width instead (`MarkSplitButton` does exactly that).
**Nothing else may touch this glyph's opacity.**

### 6.3 `MarkRing`

The round mark control. **One verb, one control grammar** — the shipped build had four dialects, *"two
of which used the same glyph to mean opposite things."*

```
MarkRing(marked: Bool, style: Style = .filled, lead: Bool = false,
         episode: Int? = nil, label: String = Copy.Action.markAsWatched,
         markedLabel: String? = nil, action: () -> Void)
enum Style { case filled, quiet, settled }
```

Geometry is identical in all three styles — **only the ink changes** — a 44 × 44 target holding a
22 × 22 ring drawn at `lineWidth: 1.5`.

| | `fill` | `ring` | `ink` (check + numeral base) |
|---|---|---|---|
| unmarked, `lead == false` | clear | `markRingIdle` (white 0.34) | — |
| unmarked, `lead == true` | clear | `accent` | — |
| marked · `.filled` | `accent` | clear | `onAccent` |
| marked · `.quiet` | clear | `accent` | `accent` |
| marked · `.settled` | clear | clear | `textTertiary` |

ZStack contents, in order:
1. `Circle().fill(fill).frame(22 × 22)`
2. `Circle().strokeBorder(ring, lineWidth: 1.5).frame(22 × 22)`
3. if `episode != nil && !marked && episode < 1000`: `Text("\(episode)")`,
   `.system(size: episode < 100 ? 9 : 7, weight: .semibold)`, `.monospacedDigit()`,
   `foregroundStyle(lead ? accent : textSecondary)`, `.transition(.opacity)`
4. `DrawnCheck(on: marked, size: 12, tint: ink)` — **unconditional**

Then `frame(44 × 44)`, `contentShape(Circle())`, `animation(pick(uiMicro, reduceMotion), value:
marked)`, `buttonStyle(MarkPressStyle())`.

**Accessibility:** `accessibilityLabel(marked ? (markedLabel ?? Copy.Accessibility.complete
/* "Complete" */) : label /* default "Mark as watched" */)`;
traits `marked ? [.isButton, .isSelected] : .isButton`.

Real call sites for reference:
- Detail's episode list — `style: .settled`, `lead: isNext`, `episode: isNext ? n : nil`,
  `label: Copy.episode(n)` ("Episode 12"), `markedLabel: Copy.episode(n)`; the caller adds
  `.accessibilityValue("Watched"/"Not watched")` and
  `.accessibilityHint("Marks as unwatched"/"Marks as watched")`, and `.disabled(!interactive)`.
- Schedule's airing card — `style: .quiet`, label
  `"Mark \(Copy.episode(n)) of \(title) as watched"` (or `"Mark \(Copy.episodes(k)) of \(title) as
  watched"` for a batch), `markedLabel: Copy.Progress.episodeWatched(n)`, wrapped in
  `.transition(.handoff(reduceMotion:))`.
- `.filled` currently has no live call site — *"the capsule CTAs carry the filled weight now."*

**Why `.settled` exists:** `.quiet` still put eleven amber rings down one column. *"History is quiet,
and amber goes to the ONE ring that is a next step (`lead`)."*
**Why the numeral exists:** *"The unmarked control used to be a bare hairline circle — the app's core
action, with no visible object and barely any ink. With a numeral inside, the ring says exactly what
committing it means."*

### 6.4 `MarkSplitButton`

*"'Mark as watched' with the batch options behind a real split."* One capsule containing **two 44-pt
targets separated by a hairline**.

```
MarkSplitButton(episode: Int, committed: Bool, behind: Int, title: String,
                onMark: () -> Void, onMarkThrough: (Int) -> Void, onMarkAll: () -> Void)
private var showsMenu: Bool { behind > 1 }
```

`HStack(spacing: 0)`:

**Left half — the mark.** `Button(action: onMark)` whose label is `HStack(spacing: 0)`:
- `DrawnCheck(on: committed, tint: ThemeColor.accent)` (default size 14)
  `.padding(.trailing, ThemeSpace.x2 = 8)`
  `.frame(width: committed ? nil : 0, alignment: .leading)` `.clipped()`
  — **collapsed to zero width, never conditionally inserted** (see §6.2)
- `Text(committed ? Copy.Progress.episodeWatched(episode) : Copy.Action.markAsWatched)` ·
  `type(button)` · `lineLimit(1)` · `minimumScaleFactor(0.78)` · `allowsTightening(true)` ·
  **`contentTransition(.opacity)`**

Half-level: `foregroundStyle(committed ? accent : onAccent)`,
`padding(.horizontal, ThemeSpace.x5 = 20)`, `frame(maxWidth: .infinity, minHeight: 48)`,
`contentShape(Rectangle())`, `buttonStyle(SplitHalfStyle())`, `allowsHitTesting(!committed)`,
`accessibilityRemoveTraits(committed ? .isButton : [])`, and
`accessibilityLabel(committed ? Copy.Progress.episodeWatched(episode)
: "\(Copy.Action.markEpisodeWatched(episode)), \(title)")`.

> *"'Mark as watched' (2 Sep): the hero and Detail's block now state exactly ONE episode directly above
> this capsule, so the number the label used to repeat is no longer disambiguating anything. VoiceOver
> still hears the episode … The committed form keeps its number: 'Episode 12 watched' is a receipt."*
> *"`.interpolate` tried to morph two unrelated strings and printed 'Mark as watched' and 'Episode 19
> watched' superimposed as an unreadable smear, twice per mark. Two different sentences crossfade;
> they do not interpolate."*
> *"One line, scaled before wrapped … A capsule's label compresses a step; it does not stack."*

**Divider (only when `showsMenu`):** `Rectangle().fill(onAccent.opacity(0.18)).frame(width: 1,
height: 24)`.

**Right half — the batch menu (only when `behind > 1`):** a `Menu` whose label is SF `chevron.down`,
`.system(size: 12, weight: .semibold)`, `onAccent`, `frame(width: 46, height: 48)`,
`contentShape(Rectangle())`; `buttonStyle(SplitHalfStyle())`, `allowsHitTesting(!committed)`,
`opacity(committed ? 0.45 : 1)`, `accessibilityLabel("More ways to mark")`,
`accessibilityHidden(committed)`.

Menu content — a `Section(title)` (*"A Section header is the one Menu element that names without
acting"*) containing:
```swift
let through = min(episode + 4, episode + behind - 1)
if through > episode { Button(Copy.Action.markThrough(from: episode, to: through)) { onMarkThrough(through) } }
Button(Copy.Action.markAll(behind)) { onMarkAll() }
```

**Container:** `background(committed ? ThemeColor.accent.opacity(0.18) : ThemeColor.accent)` →
`clipShape(Capsule())` → `overlay(Capsule().strokeBorder(LinearGradient([controlSheen, .clear], .top →
.center), lineWidth: 1))` → `animation(pick(uiMicro, reduceMotion), value: committed)`.

> *"A past-tense fact does not get the app's one primary colour: the committed capsule keeps its shape
> and drops to a soft tint with accent ink."*

**Exact strings** (from `Copy.swift`; `\u{00A0}` = NBSP, `\u{2060}` = word joiner, `\u{2013}` = en dash):

| Function | Output |
|---|---|
| `Copy.Action.markAsWatched` | `Mark as watched` |
| `Copy.Progress.episodeWatched(12)` | `Episode 12 watched` |
| `Copy.Action.markEpisodeWatched(12)` | `Mark episode 12 watched` |
| `Copy.Action.markThrough(from: 1, to: 5)` | `Mark episodes 1⁠–⁠5 watched` (word joiners around the en dash) |
| `Copy.Action.markThrough(from: 5, to: 5)` (from ≥ to) | `Mark episode 5 watched` |
| `Copy.Action.markAll(18)` | `Mark all 18 episodes as watched` (NBSP between count and noun) |
| `Copy.Accessibility.complete` | `Complete` |
| `Copy.Action.seeAll` | `See all` |
| `Copy.Accessibility.opensTheShowHint` | `Opens the show` |

Word joiners exist because *"a narrow menu line broke it as 'episodes 1–' / '5', which reads as a typo,
not a range."*

### 6.5 `PassiveTick` (Primitives+States.swift)

A completed thing. **Never a button, never accent** — "complete" is a fact, not an action.
`PassiveTick(boxed: Bool = false)`: SF `checkmark`, `.system(size: 14, weight: .semibold)`,
`textTertiary`, `frame(width: boxed ? 44 : nil, height: boxed ? 44 : nil)`,
`accessibilityElement()` + `accessibilityValue(Copy.Accessibility.complete)` +
`accessibilityAddTraits(.isStaticText)`.

> *"A bare check, not a filled disc. `checkmark.circle.fill` at tertiary grey renders as a 18-pt grey
> blob — read as a disabled control rather than as a settled fact."*

---

## 7. Buttons, press styles and chips

**Press feedback is one pattern, written once** (`View.pressFeedback(_:reduceMotion:scale:)`, private):
```swift
.opacity(reduceMotion && isPressed ? 0.72 : 1)
.scaleEffect(reduceMotion ? 1 : (isPressed ? scale : 1))
.animation(ThemeMotion.pick(ThemeMotion.uiPress, reduceMotion: reduceMotion), value: isPressed)
```
Default `scale` = 0.985. **Board 11: Reduce Motion presses in OPACITY, never in scale.**

| Style | Type | Ink | Height | Padding | Ground | Edge | Press | Disabled |
|---|---|---|---|---|---|---|---|---|
| `PrimaryButtonStyle2` | `button` | `onAccent` | `maxWidth: .infinity`, minHeight **48** | h 18 | Capsule `accent` / pressed `accentPressed` | Capsule `strokeBorder(LinearGradient([controlSheen, clear], top→center), 1)` | `pressFeedback` (0.985) | opacity 0.38 |
| `SecondaryButtonStyle2` | `button` | `textPrimary` | `maxWidth: .infinity`, minHeight **44** | h 18 | Capsule `surfaceFloating` / pressed `surfacePressed` | Capsule `strokeBorder(stroke, 1)` | `pressFeedback` (0.985) | — |
| `TertiaryButtonStyle2(destructive:)` | `button` | `destructive ? destructive : interactive` | `minWidth 44, minHeight 44` | — | none | none | opacity 0.6, **no animation** | — |
| `RowPressStyle(radius: = ThemeRadius.row 16)` | — | — | — | — | overlay `RoundedRectangle(radius, .continuous).fill(surfacePressed.opacity(isPressed ? 0.6 : 0))` | — | scale 0.992 (1 under Reduce Motion); animation `pick(isPressed ? uiPress : uiMicro)` | — |
| `MarkPressStyle` | — | — | — | — | none | none | `pressFeedback` (0.985) — **compression only, no rounded-rect wash behind a circle** | — |
| `OverArtPressStyle` | — | — | — | — | none | none | opacity `isPressed ? (reduceMotion ? 0.72 : 0.88) : 1`, scale 0.99, `pick(uiPress)` | — |
| `SplitHalfStyle` | — | — | — | — | `background(isPressed ? accentPressed : .clear)` | — | `pick(uiPress)` on `isPressed` | — |
| `InlineLinkButtonStyle(destructive:)` | `listAction` | `destructive ? destructive : interactive` | `minHeight 44` | v **14**, h **12**, then `contentShape(Rectangle())` | none | none | opacity 0.55, `pick(uiPress)` | — |
| `GroupedRowPressStyle` | — | — | — | — | `isPressed ? surfacePressed : .clear` | — | `pick(isPressed ? uiPress : uiMicro)` | — |
| `SectionHeaderPressStyle` | — | — | `minHeight 44` | v 10 | none | none | opacity 0.55, `pick(uiPress)` | — |
| `ToastActionStyle` (private) | `metadataEmphasis` | `textPrimary` | `minHeight 44` | h 16 | none, `contentShape(Capsule())` | — | opacity 0.55, `pick(uiPress)` | — |
| `CompactActionButtonStyle` | `metadataEmphasis` | `textPrimary` | `minHeight 44` | h 14 | `RoundedRectangle(compactControl 12, .continuous)` `surfaceFloating` / pressed `surfacePressed` | `strokeBorder(stroke, 1)` | opacity 0.72 when Reduce Motion + pressed; scale 0.985 otherwise | opacity 0.38 |

Notes that must survive the port:

- **`RowPressStyle.radius` must match the surface being pressed.** *"Left at the default, a pressed
  24-pt Focus card paints a 16-pt highlight inside its own corners — a 4-pt sliver of un-highlighted
  card at each corner, visible on every single tap of the app's most important control."* `ShelfCard`
  passes `slot.radius` for exactly this reason.
- **`OverArtPressStyle` is for a target that IS a photograph** — the Today hero, the avatar, the recap
  card, `BannerCard`. *"a `surfacePressed` wash over artwork is a grey film over someone's
  illustration. Art dips in brightness and compresses a hair instead."*
- **`strokeBorder`, not `stroke`**: *"a centred 1-pt line straddles the capsule's edge and renders as a
  soft 2-px smear on the outside of the shape. A CONTROL is allowed a full-perimeter edge (a container
  is not) — but it has to be a crisp one."*
- **The lit top edge on every filled control:** *"Flat #F0A24E across 48×376 pt is a swatch of orange;
  one 22 %-white hairline along the top, dead by the vertical centre, is what makes it read as a
  physical, pressable object."*
- **`InlineLinkButtonStyle`'s padding is symmetric and comes BEFORE `contentShape`:** *"A footnote
  cap-height is ~13 pt, so 12 pt of vertical padding gives a ~37–40 pt target, and leading-only padding
  ends the hit area at the last glyph — the user has to hit the WORD."* Affects `See all`,
  `Read more`, `Clear`, `Sync now` and Detail's `Details`, at every type size.
- **`TertiaryButtonStyle2` has no animation on its press.** Preserve that (it is the only style with a
  hard opacity switch).

### Chips

**`FilterChipStyle`** — an ACTIVE, removable filter chip. `metadataEmphasis` in **`accent` ink**;
`padding(.horizontal, ThemeSpace.x3 = 12)`; `frame(minHeight: 32)`; background
`Capsule().fill(isPressed ? surfacePressed : accentSoft)`; `contentShape(Capsule())`; then
`frame(minHeight: 44)`; `pressFeedback`.

**`FilterChipLabel(text:)`** — its label: `HStack(spacing: 5) { Text(text);
Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }`.

**`ChipButtonStyle(selected: Bool = false)`** — a primary choice (a search scope).
`metadataEmphasis`; ink `selected ? onAccent : textSecondary`; `padding(.horizontal, 14)`;
`frame(minHeight: 34)`; background capsule = selected ? (pressed ? `accentPressed` : `accent`)
: (pressed ? `surfacePressed` : `surfaceRaised`); **overlay only when selected**: the `controlSheen`
top-edge gradient; `contentShape(Capsule())`; then `frame(minHeight: 44)`; `pressFeedback`.

> *"Unselected chips carry NO stroke. The shipped Search screen draws a grey-outlined pill for every
> scope and every recent query, so eight outlined objects compete with the three posters underneath
> them. Tone alone separates an unselected chip from the canvas; the selected one is the only chip
> allowed to use colour."*
> The two styles are deliberately different: *"four solid amber capsules above a list is louder than
> anything on the screen they are filtering."*

Both chips use the **32/34-then-44** pattern: the visible capsule is 32 or 34 pt tall, the *hit target*
is 44. Reproduce this exactly — do not inflate the capsule.

---

## 8. Chrome, toast, brand, account

### 8.1 `ScrollEdgeChrome` and the modifiers around it

> *"The single most damaging detail in the shipped build is invisible in a design tool and obvious on a
> device: **content scrolls straight through the status bar**. On Schedule a poster and a truncated
> show title sit on top of the clock; on Library a poster crosses the Dynamic Island. No shipping media
> app does this, and no amount of card polish survives it."*

`ScrollEdgeChrome(side: .top | .bottom, height: = topChromeHeight, soft: Bool = false,
holdHeight: CGFloat? = nil)`.

`hold` (a fraction) = `clamp((holdHeight ?? topSafeInset) / max(height, 1), 0, 1)`.
`bar` = `reduceTransparency ? 1 : ThemeMetrics.chromeBarOpacity (0.74)`.

**Veil gradients** (colour = `ThemeColor.chromeVeil`, i.e. the canvas):

*top, `soft: true`* (the at-rest edge — art runs to the screen's top under a gradient that only softens):

| Loc | Alpha |
|---|---|
| 0 | 0.55 |
| 0.5 | 0.30 |
| 1 | 0 |

*top, `soft: false`* (the hardened bar):

| Loc | Alpha |
|---|---|
| 0 | `bar` |
| `hold` | `bar` |
| `hold + (1 − hold) × 0.45` | `bar × 0.45` |
| 1 | 0 |

*bottom* (the tab-bar ramp):

| Loc | Alpha |
|---|---|
| 0 | 0 |
| 0.55 | 0.25 |
| 0.85 | 0.75 |
| 1 | 1.00 |

**Blur masks** — the `.ultraThinMaterial` rides the *same* ramp and reaches zero at the same place.
*"A mask that terminates while the veil is still at a third leaves a visible seam straight across the
screen — which is precisely what a hand-rolled scroll edge looks like."*

| Side | Stops (black alpha) |
|---|---|
| top soft | 0 → 0.6 · 0.5 → 0.3 · 1 → clear |
| top hard | 0 → 1.0 · `hold` → 1.0 · `hold + (1 − hold) × 0.45` → 0.42 · 1 → clear |
| bottom | 0 → clear · 0.55 → 0.30 · 0.85 → 0.75 · 1 → 1.0 |

`band` = `ZStack { if !reduceTransparency { Rectangle().fill(.ultraThinMaterial).mask(blurMask) }; veil }`.

Body: top → `band.frame(height: height)`. Bottom → `VStack(spacing: 0) { band.frame(height:
bottomChromeHeight = 64); ThemeColor.chromeVeil.frame(height: bottomUnderfill = 180) }.offset(y: 180)`.
Then `frame(maxWidth: .infinity)`, `ignoresSafeArea(edges: top ? .top : .bottom)`,
`allowsHitTesting(false)`, `accessibilityHidden(true)`.

**The 0.74 rule, quoted because it has been re-litigated three times:**
> *"Under Reduce Transparency there is no blur to carry the bar, so it is opaque there — a 74 % veil
> with nothing softening what is under it is the half-lit row under 'Library' that the hardened bar was
> built to end."* And at 1.0 with the blur present, *"the top ~100 pt of every scrolled screen was a
> flat #09090B rectangle with a 28-pt edge … and the `.ultraThinMaterial` painted under it was doing
> nothing at all."*

**The bottom band's height is the pill's own height (64), not 116 or 140.** Both earlier values are
recorded failures: 116 left un-occluded body copy for the Liquid Glass rim to refract (*"the bar duly
mirrored it back as legible upside-down text … a frame that reads as GPU corruption"*), and 140 erased
live content at rest (*"a `See all` link at 1.42:1 and a live `+` button at 131/241, at rest, with
nothing scrolled"*). **`bottomUnderfill` over-draws 180 pt past the layout's bottom edge** because a
`TabView` insets its children's safe area by the bar, so a `.bottom`-aligned overlay's bottom edge is
the *bar's* top edge, not the screen's.

**`ScrollEdgeChromeModifier`** — how a screen mounts it:
- bottom overlay: `ScrollEdgeChrome(side: .bottom)` when `bottom`
- top overlay when `top`:
  - `softTop == false` → `ScrollEdgeChrome(side: .top, height: topHeight)`
  - `softTop == true` → **both layers mounted, opacity traded**, so the swap is a cross-fade rather
    than a re-created material:
    ```
    hold = topHold ?? topSafeInset
    ZStack(alignment: .top) {
      ScrollEdgeChrome(.top, height: topHeight, soft: true).opacity(topRaised ? 0 : 1)
      ScrollEdgeChrome(.top, height: hold + barEdgeRamp(28), soft: false, holdHeight: hold)
        .opacity(topRaised ? 1 : 0)
    }.animation(ThemeMotion.uiGentle, value: topRaised)
    ```

Public entry points:
- `scrollEdgeChrome(top: = true, bottom: = true, topHeight: = topChromeHeight)` — the plain form, plus
  `chromeScrollEdgeHidden(.all)`. *"Our edge chrome replaces the system scroll-edge effect; both
  together dim the last ~190 pt of every scroll view (a primary CTA at the bottom read as disabled)."*
- `scrollEdgeChromeBody(top:bottom:topHeight:softTop:topRaised:topHold:)` — the soft/hard form. `topHold`
  is normally `ThemeMetrics.inlineBarBottom`, plus `searchDrawerHeight` under a search drawer.
- `tabBarContentMargin(extra:)` = `contentMargins(.bottom, tabBarClearance + extra, for:
  .scrollContent)`. **Applied to the scroll view, never inside the stack** — *"`.padding(.bottom,
  tabBarClearance)` inside the scroll content does nothing at all when the stack is shorter than the
  viewport."*
- `pushedScreenChrome()` = `scrollEdgeChromeBody(top: false, bottom: true)` +
  `chromeScrollEdgeHidden(.bottom)` + `contentMargins(.bottom, tabBarClearance, for: .scrollContent)`.
  It lives on the navigation destination so every future push inherits it. **The top edge is
  deliberately untouched: a pushed screen has a real navigation bar and the system owns that edge.**

**`ChromeGlassBox` / `View.chromeGlass(in:interactive:)`** — the ONE sanctioned entry to glass:
- Reduce Transparency ON → `background(surfaceFloating, in: shape)` +
  `overlay(shape.stroke(strokeStrong, lineWidth: 1))`
- otherwise → `glassChrome(in:interactive:)`, which is `glassEffect(.regular[.interactive()], in:)` on
  iOS 26+ and `background(.ultraThinMaterial, in: shape)` below.

*"`glassChrome` alone keeps refracting when the user has asked it not to."*

> **Android:** this whole section is the hardest part of the port.
> - `.ultraThinMaterial` / Liquid Glass have no Android equivalent. The closest is a `RenderEffect`
>   blur of the content behind (API 31+) via a shared graphics layer, or the Haze library. Below 31,
>   fall back to the Reduce-Transparency branch (`surfaceFloating` + `strokeStrong`) — which the design
>   already specifies, so it degrades honestly. **Hard.**
> - Reduce Transparency **does not exist on Android.** Add an in-app setting, defaulted from
>   `Settings.Global.ANIMATOR_DURATION_SCALE == 0` is *not* a valid proxy — ship an explicit toggle.
>   **Blocker without a product decision.**
> - The `.mask(gradient)` on a material: Compose needs
>   `graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }` +
>   `drawWithContent { drawContent(); drawRect(brush, blendMode = BlendMode.DstIn) }`. **Moderate.**
> - `bottomUnderfill` exists to fight a `TabView` quirk; Android's `NavigationBar` sits in the same
>   composable tree, so the over-draw is unnecessary — but the 64-pt ramp above it still is. Simplify
>   deliberately, and record it.

### 8.2 `ToastView`

*"The canonical toast: a content-width glass **capsule**, centred over the tab bar's own margin."*

`ToastView(message: String, actionLabel: String? = nil, failure: Bool = false,
action: (() -> Void)? = nil)`.

`HStack(spacing: ThemeSpace.x3 = 12)`:
- if `failure`: SF `exclamationmark.triangle.fill`, `.system(size: 13, weight: .semibold)`,
  `ThemeColor.warning`
- `Text(message)` · `metadataEmphasis` · `textPrimary` · `lineLimit(2)` ·
  `multilineTextAlignment(.leading)`
- if `actionLabel != nil && action != nil`: `Button(actionLabel, action:)` with `ToastActionStyle()`

Then `padding(.leading, ThemeSpace.x4 = 16)`,
`padding(.trailing, actionLabel == nil ? ThemeSpace.x4 (16) : ThemeSpace.x1 (4))`,
`frame(minHeight: 48)`, `fixedSize(horizontal: false, vertical: true)`, `frame(maxWidth: 420)`,
`chromeGlass(in: Capsule())`, `shadow(.floating)`, `transition(.toast(reduceMotion:))`.

> *"The shipped shape — a full-width rounded rectangle with a 1-px perimeter stroke and a trailing
> amber 'Undo' — is an Android Material snackbar in shape, position and construction, and it put a
> second amber object beside the amber CTA it had just been used to confirm."*
> The action label is `textPrimary`, **not accent**: *"Weight carries the action."*
> *"The toast owns its own timing. Its host used to declare three `uiSnappy` animations and the toast a
> bare `.opacity`, so it arrived and LEFT on the same spring — a bounce out, not a dismissal."*

Positioning is the host's job: `ThemeMetrics.toastClearance = 62` above the safe area's bottom edge.

> **Android note, worth stating plainly:** do **not** reach for Material3 `Snackbar`. The whole point of
> this component is that it is *not* a snackbar. Build the capsule.

### 8.3 `Wordmark` and `PreviouslyMark`

**One brand lockup.** `Wordmark(colophon: Bool = false)`:
`HStack(spacing: colophon ? 7 : ThemeSpace.x2 (8)) {
PreviouslyMark(width: colophon ? 11 : 13, detail: colophon ? .none : .progress);
Text("Previously.").foregroundStyle(colophon ? textSecondary : textPrimary).type(brandWordmark) }`
→ `shadow(colophon ? .none : .art)` → `accessibilityElement(children: .ignore)` →
`accessibilityLabel("Previously")` (**no full stop in the spoken label**).

> *"Profile's colophon had drifted into a second drawing with an accent period, so the logo had two
> versions inside one app. The full stop is TEXT ink, not accent, everywhere inside the app — the
> bookmark mark beside it already carries the brand's amber. The splash and sign-in keep their amber
> dot; there the wordmark IS the subject."*

`PreviouslyMark(width:detail: .progress|.none, progress: CGFloat = 0, finish: .flat|.hero)` — a
saved-place ribbon with one progress point. Derived geometry: `height = width × 1.58`,
`slotWidth = width × 0.56`, `slotHeight = width × 0.12`.

- `BookmarkShape` filled `LinearGradient([#FFD6A0, accent, #C9702E], topLeading → bottomTrailing)`.
  Path: rounded top corners at `r = width × 0.17` (quad curves), straight sides down to
  `y = height × 0.96`, then a V notch to `(midX, height × 0.76)` and back out.
- `.progress` adds a `Capsule()` slot (`canvas` fill when `.flat`), `slotWidth × slotHeight`, offset
  `y: −height × 0.24`; and a `Circle()` dot of `width × 0.10` in `#FFF0DA` (flat), offset
  `x: −slotWidth × 0.32 + slotWidth × 0.64 × clamp(progress, 0, 1)`, `y: −height × 0.24`.
- `.hero` (splash only, ~200 pt) adds a rim light, notch shading, a carved slot stroke and an ember dot
  — see the source; not needed for any in-app surface.
- `accessibilityHidden(true)`.

### 8.4 `AccountDisc`

`AccountDisc(identity: AuthManager.AccountIdentity, diameter: CGFloat = 56, quiet: Bool = false)`:

ZStack, `frame(diameter × diameter)`, `accessibilityHidden(true)`:
1. `Circle().fill(quiet ? surfaceRaised : accentSoft)`
2. `Circle().strokeBorder(posterEdge, lineWidth: 1)`
3. if `identity.monogram != nil`: `Text(monogram)` · `.system(size: diameter × 0.42, weight:
   .semibold)` · `quiet ? textSecondary : accent` · `minimumScaleFactor(0.6)` · `lineLimit(1)`
   else: `PreviouslyMark(width: diameter × 0.34, detail: .none)`

`monogram` = the real account initial, else the first **letter** of the display label ("Your account" →
"Y"), else nil. A leading digit, punctuation or emoji is not an initial.

> *"**It never draws `person.fill`.** Both call sites were rendering the system's generic account glyph
> inside a brand-coloured ring — the app spending its one accent on a placeholder, on the element whose
> entire job is to be *this person*."* The chain: real initial → first letter of the label → the
> Previously. mark. *"Only the first two are letters, so a wrong initial is still never invented; the
> third is the app's own identity, which is never wrong."*
> `quiet` exists for Today's header: *"the amber budget above the fold belongs to the hero's fact and
> its one action."* Profile — where the disc IS the subject — keeps the accent form.

---

## 9. Colour is never the only carrier

Two views that draw **nothing** unless the system's *Differentiate Without Color* setting is on.

**`DifferentiateMark(symbol: String = "circle.fill", size: CGFloat = 6, tint: Color = textPrimary)`** —
when `accessibilityDifferentiateWithoutColor`, renders `Image(systemName: symbol)` at
`.system(size: size, weight: .bold)` in `tint`, `accessibilityHidden(true)`. Otherwise nothing.

**`View.differentiatingUnderline(_ active: Bool, tint: Color = textPrimary)`** — when `active &&
differentiate`, overlays at `.bottom` a `Capsule().fill(tint).frame(height: 2)
.padding(.horizontal, 4).offset(y: 3)`, `accessibilityHidden(true)`.

> *"`accessibilityDifferentiateWithoutColor` had **zero** references in the whole of `Sources/`, so
> every colour-only encoding in the app — Schedule's 'today', an accent caption that means 'this is
> your next step' — was invisible to a user who has asked the system for shapes instead of hues. … It
> is not an accessibility fallback bolted beside the design; it is the second carrier the design should
> have had."*

> **Android:** there is no Differentiate Without Color setting. Ship an in-app preference (Settings →
> Accessibility) that drives the same two views, and default it off. Until it exists, every amber-only
> state (today, selected, next step) fails the same way iOS did. **Blocker without a product decision.**

---

## 10. `SkeletonBlock`

Structural skeleton: **static, no shimmer** (spec: shimmer is refused).

`SkeletonBlock(width: CGFloat? = nil, height: CGFloat? = 12, radius: CGFloat = 6)` →
`RoundedRectangle(cornerRadius: radius, style: .continuous).fill(ThemeColor.skeleton)
.frame(width: width, height: height)`. `height: nil` takes the height it is proposed (e.g. a 16:9 card
via `aspectRatio`).

`skeleton` is `#F4F1EC` @ 0.11: *"At 8 % over the old #09090B canvas the structure was ~4 % above ground
and effectively invisible; it has to read as the shape of what is coming."*

---

## 11. `ScrollOffset`

**The scroll offset is never screen state.**

```swift
@Observable @MainActor
final class ScrollOffset {
    private(set) var y: CGFloat = 0
    func set(_ raw: CGFloat) { let v = ThemeMetrics.scrollSample(raw); if v != y { y = v } }
    var veilOpacity: Double { Double(min(1, max(0, (y - 16) / 64))) }   // 0 until 16 pt, 1 by 80 pt
    var stretch: CGFloat { max(0, -y) }                                  // the pull-down, as extra art height
}
```

`scrollSample` clamps to −320…240 and rounds to the half point, so the value **stops changing once the
chrome has settled**.

The contract around it (from `CLAUDE.md` and the doc comment):
- Today and Detail hold one in `@State`.
- **Only the small views that draw the veils (`TodayVeils`, `DetailVeils`) and stretch the hero
  (`StretchingHeroArt`) may read `.y` inside a body**, so a scroll frame invalidates those views alone.
- Boolean probes derived from it (`raisedTop`, `scrolledUnderBar`) are written back to screen state
  **guarded with `if new != old`**.
- Scroll probes are `Color.clear.onGeometryChange` on the *scroll content*, because
  `onScrollGeometryChange` never fires on the iOS 27 simulator.
- Veils are mounted only while on, **never held at opacity 0**; Today has no mask on its scroll view.

> *"As `@State` on the screen it re-ran the screen's whole body — Today's stack, queue, shelf and every
> row — on every frame of the first swipe (user, 2 Sep, twice)."*

> **Android:** the same discipline, different mechanism. Hold the sampled offset in a
> `MutableFloatState` inside a stable holder; read it **inside** `graphicsLayer { }` / `drawBehind { }`
> lambdas or via `derivedStateOf`, never in the composable body of a screen — a body read defers the
> whole screen to the recomposition phase, which is precisely the bug this class exists to prevent.
> **Easy to state, easy to get wrong.**

---

## 12. Android port risk register

Ordered by severity. Items rated *blocker* need a product decision before the component can be
considered ported.

| # | Item | Where it bites | Severity | Note |
|---|---|---|---|---|
| 1 | **Reduce Transparency** has no Android equivalent | `ChromeGlassBox`, `ScrollEdgeChrome.veil`/`blurMask`, `ToastView` | blocker | The design branches on it in three places. Ship an explicit in-app toggle; the "on" branch (`surfaceFloating` + `strokeStrong`, opaque bar at alpha 1.0) is already fully specified and is also the correct fallback for API < 31. |
| 2 | **Differentiate Without Color** has no Android equivalent | `DifferentiateMark`, `differentiatingUnderline` | blocker | Same fix: an in-app preference. Without it every amber-only state (today, selected, "next step") is colour-only. |
| 3 | `.ultraThinMaterial` / Liquid Glass | `ScrollEdgeChrome` band, `chromeGlass`, `ToastView`, `SyncBanner` | hard | `RenderEffect.createBlurEffect` is API 31+ and blurs a *layer*, not "what is behind me" — a live backdrop blur needs the content re-rendered into a shared graphics layer (Haze-style). Degrade to the Reduce-Transparency branch below 31. |
| 4 | Arbitrary-colour, arbitrary-radius, offset shadows | `ShadowToken` everywhere: `.card`, `.art`, `.artHero`, `.floating` | hard | Compose `Modifier.shadow` is elevation-based; custom colour needs API 28+ and still gives no radius/offset control. Implement via `drawBehind` + `setShadowLayer` on a software-rendered paint, or pre-composited nine-patch. The 5 tokens are reused ~40 times, so build it once. |
| 5 | `.continuous` corner style (squircle) | every rounded rect ≥ r16: cards, plates, rows, chips, tiles | moderate | Compose `RoundedCornerShape` is circular-arc and reads visibly "rounder" at r22 on a 104-pt card. Write a `SquircleShape(radius)` emitting a superellipse path. |
| 6 | SF Symbols | `chevron.forward`, `chevron.down`, `checkmark`, `xmark`, `photo`, `play.rectangle`, `exclamationmark.triangle.fill`, `circle.fill`, `person.fill` | moderate | Nine glyphs total in this file. Material Symbols cover all nine but with different optical weights and metrics; the specified pixel sizes (13/14/15/17 pt at semibold/bold) will need re-tuning per glyph, and `chevron.forward` must mirror in RTL. |
| 7 | `minimumScaleFactor` | `ShelfCard` (0.82), `BannerCard` (0.82), `MarkSplitButton` (0.78), `SectionHeaderRow` (0.85), `AccountDisc` (0.6) | moderate | No Compose equivalent. Implement an `AutoSizeText` using `TextMeasurer` + a bisection over `fontSize` with the given floor. Five call sites, all with different floors. |
| 8 | Negative padding that keeps a 44-pt target without growing layout | `SectionHeaderRow` (−10 / −12) + `.zIndex(1)` | moderate | Compose has no negative padding. Use a custom `Modifier.layout` that measures with extra height but reports the smaller one, plus `Modifier.zIndex(1f)` for the hit-test priority the comment describes. |
| 9 | `Modifier.blur` is API 31+ | `LandscapeArt` (28), `ArtHeader` (48), both `opaque: true` | moderate | Below 31, approximate by decoding the ground image at ~32–64 px and letting the scaler smear it; visually close at these radii. `opaque: true` ⇒ `BlurredEdgeTreatment.Rectangle`. |
| 10 | Dynamic Type accessibility-size boundary | `MediaRow`, `ShelfCard`, `SectionLabel`, `ShelfScroller`, `EpisodeStill` all branch on `typeSize.isAccessibilitySize` | moderate | Android has a continuous `fontScale` with no named AX threshold. Define `isAccessibilitySize = LocalDensity.current.fontScale >= 1.35` once and use it everywhere; do not re-derive per component. |
| 11 | Reduce Motion | `pressFeedback`, `RowPressStyle`, `OverArtPressStyle`, `DrawnCheck`, `MarkRing`, `ArtHeader.drift`, both transitions | moderate | Read `Settings.Global.TRANSITION_ANIMATION_SCALE == 0f` (and `ANIMATOR_DURATION_SCALE`), expose as a `CompositionLocal`, and route every animation through the `pick()` equivalent. Note the rule is *not* "no animation" — it is `uiReduced` (easeOut 120 ms) and **press in opacity, never scale**. |
| 12 | Haptic intensities | `FeedbackCoordinator` (light @0.65, medium @0.72, light @0.50) | moderate | `VibrationEffect.createOneShot(ms, amplitude)` / `createPredefined` give coarse control; `HapticFeedbackConstants.CONFIRM`/`REJECT` (API 30+) are the nearest named equivalents. The per-token 0.04 s / 0.3 s rate floors and the "app must be foreground" gate port directly. |
| 13 | `accessibilityHint` | `MediaRow.hint`, `BannerCard` ("Opens the show"), `MarkRing` call sites | moderate | Compose has no hint. Nearest: `Modifier.semantics { onClick(label = hint) { … } }`, which TalkBack reads as "double tap to <label>". Rephrase hints imperatively where needed; keep the *label* strings verbatim. |
| 14 | Tracking in **points** | every `TypeToken` | easy-moderate | SwiftUI `tracking` is absolute points; Compose `letterSpacing` in `sp` scales with font scale, in `em` scales with size. Use `em = tracking / fontSize` to preserve the ratio, or `sp` to preserve the absolute value — pick one and record it. The values are small (−0.80…+1.0) but `sectionLabel`'s +1.0 on 11 pt is very visible. |
| 15 | Outfit variable/static fonts + `relativeTo:` | all Outfit tokens | easy-moderate | Ship Outfit Regular/Medium/SemiBold/Bold as resources. `relativeTo:` clamps growth against a system text style; Compose `sp` scales linearly and unbounded — cap the effective scale per token if AX5 breaks a layout. |
| 16 | `.matchedTransitionSource` / `zoomSource` | `MediaRow`, `ShelfCard`, `BannerCard`, `ProgressBanner`, `OptionalZoomSource` | easy | **Dead weight.** Per `CLAUDE.md` the `.zoom` transition was retired 3 Sep and "the `zoomSource` registrations stay but nothing consumes them". Detail is a plain push. Drop the parameter entirely in Compose. |
| 17 | `Toggle` with the row as its label | `GroupedRow` | easy | `Row(Modifier.toggleable(value, role = Role.Switch, onValueChange))` with a `Switch` inside and `mergeDescendants` — reproduces the exact one-element/switch-trait/whole-row-target behaviour the comment demands. |
| 18 | Gradient masks | `ShelfScroller`, `DrawnCheck`, `ScrollEdgeChrome.blurMask` | easy | `CompositingStrategy.Offscreen` + `BlendMode.DstIn`. `DrawnCheck`'s mask is a plain animated-width clip and is trivially a `Modifier.clipToBounds()` on a width-animated Box. |
| 19 | `contentMargins(for: .scrollContent)` | `shelfScroller`, `tabBarContentMargin`, `pushedScreenChrome` | easy | `LazyRow`/`LazyColumn` `contentPadding`. Note the iOS rationale (a margin is honoured even when content is shorter than the viewport, unlike padding) holds identically for `contentPadding`. |
| 20 | `.monospacedDigit()` | `MarkRing` numeral, `SectionHeaderRow` count, `EpisodeStill` numeral, `numberXL`, `time` | easy | `TextStyle(fontFeatureSettings = "tnum")`. |
| 21 | `contentTransition(.opacity)` | `MarkSplitButton` label | easy | `AnimatedContent` with `fadeIn() togetherWith fadeOut()`. **Do not** use a shared-element/interpolating transition — the comment records exactly that failure. |
| 22 | Status-bar / window measurement | `ThemeMetrics.topSafeInset`, `windowHeight` | easy | `WindowInsets.statusBars` and the composable's own constraints. The iOS caching hack exists only because an overlay's `GeometryReader` reports zero inside the safe area; Compose has no such problem. |
| 23 | OKLab palette extraction | `PosterSlot`, `EpisodeArtwork`, `EpisodeStill`, `ArtAdaptiveGround` | easy | Pure maths — port `oklab`/`srgb` and the 32×32 histogram directly. Do **not** substitute androidx `Palette`: it returns vibrant/muted swatches, not an L 0.24–0.38 / C 0.04–0.12 clamped derived tint, and the clamp is what stops a card fighting its own artwork. |
