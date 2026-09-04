# Design tokens, typography, motion, haptics, palette

This is the foundation layer of **Previously.** — the single source of truth for every colour,
size, spacing step, radius, type role, animation curve, haptic and art-derived ground in the iOS
app. No screen in the app is permitted to declare a literal colour, size, font or animation; it
composes from the namespaces here (`ThemeColor` / `ThemeSpace` / `ThemeRadius` / `ThemeMetrics` /
`ThemeType` / `ThemeMotion` / `ShadowToken` / `PosterSize` / `FeedbackCoordinator`). The app is
**dark-only** (`UIUserInterfaceStyle: Dark` in Info.plist plus `.preferredColorScheme(.dark)` on
the root scene) and **portrait-only**, so there is no light palette to port and no landscape
variant of any metric. Two rules in this file are load-bearing product decisions rather than
styling conveniences and must survive the port verbatim: **amber (`ThemeColor.accent`) is never an
action colour** — it means a fact or a state, and every tappable bare word/glyph uses
`ThemeColor.interactive` (which is currently an alias of the primary ink) — and **every haptic
goes through `FeedbackCoordinator.fire(_:)`, at most one per transaction**, throttled per token.
Everything below is stated as exact numbers taken from the shipping source; where the source
carries a comment explaining *why* a number is what it is, that comment is quoted, because those
numbers were arrived at by measurement and reverting one of them re-introduces a named bug.

**Source files covered**

| File | Contents |
| --- | --- |
| `ios/Sources/DesignSystem/ThemeTokens.swift` | `Color(hex:)`, `ThemeColor`, `ShadowToken`, `ThemeSpace`, `ThemeRadius`, `ThemeMetrics`, `PosterSize`, `TypeToken`/`ThemeType`, `ThemeMotion`, `AnyTransition.handoff`/`.toast`, `FeedbackToken`, `FeedbackCoordinator` |
| `ios/Sources/DesignSystem/AppFont.swift` | Outfit weight → bundled cut mapping, SwiftUI + UIKit font factories |
| `ios/Sources/DesignSystem/ScaledFont.swift` | `@ScaledMetric`-driven Outfit modifier (**currently dead code** — no call sites) |
| `ios/Sources/DesignSystem/Palette.swift` | `PaletteCache` (OKLab dominant-colour extraction), `ArtAdaptiveGround`, `ArtBackdrop` |
| `ios/Sources/DesignSystem/Appearance.swift` | The one global UIKit appearance proxy installed at launch |
| `ios/Sources/DesignSystem/PreviouslyMark.swift` | The brand glyph (`PreviouslyMark`, `BookmarkShape`) |

---

## 1. Colour

### 1.1 The `Color(hex:alpha:)` constructor

```swift
init(hex: UInt32, alpha: Double = 1.0) {
    let r = Double((hex >> 16) & 0xFF) / 255.0
    let g = Double((hex >> 8) & 0xFF) / 255.0
    let b = Double(hex & 0xFF) / 255.0
    self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
}
```

All literals are **sRGB, non-premultiplied**. `.opacity(x)` on a token produces a source-over
composite against whatever is beneath it — this matters for the lift tokens (§1.4).

### 1.2 Every `ThemeColor`, exhaustively

Alpha column: `—` means fully opaque. "Uses" is the number of `ThemeColor.<name>` references in
`ios/Sources` at the time of writing; a zero means the token is declared but currently unused.

| Token | Hex | sRGB | Alpha | Uses | Meaning / rule |
| --- | --- | --- | --- | --- | --- |
| `canvas` | `#09090B` | 9, 9, 11 | — | 34 | The app ground. Everything else is a lift over this. |
| `canvasRaised` | `#0D0E11` | 13, 14, 17 | — | 3 | Ground for a *pushed* full-screen surface — sheet backgrounds (`presentationBackground`), Watch-history screens. |
| `surfaceFlat` | `#171719` | 23, 23, 25 | — | 6 | Opaque result of `plateLift` over `canvas`. `.plate` fill; base layer of `ArtAdaptiveGround`. |
| `surfaceRaised` | `#242428` | 36, 36, 40 | — | 19 | Opaque result of `raisedLift` over `canvas`. `.raised` fill; quiet avatar disc; unselected mark chip. |
| `surfaceFloating` | `#2A2D36` | 42, 45, 54 | — | 5 | `.floating` fill — toast, sync banner, secondary capsule button. Deliberately **opaque**. |
| `surfacePressed` | `#353842` | 53, 56, 66 | — | 7 | Pressed state of any neutral surface/row/capsule. |
| `textPrimary` | `#F4F1EC` | 244, 241, 236 | — | 72 | Warm off-white. Titles, facts, primary ink. 17.7:1 on `canvas`. |
| `textSecondary` | `#AAA6A0` | 170, 166, 160 | — | 57 | Row metadata, hero fact line, colophon. 8.2:1 on `canvas`. |
| `textTertiary` | `#85817C` | 133, 129, 124 | — | 60 | Section counts, footnotes, eyebrows, disabled ticker days. 5.1:1 on `canvas`. |
| `textDisabled` | `#807C77` | 128, 124, 119 | — | 7 | The quietest ink that is still *read*. See the quote below. |
| `accent` | `#F0A24E` | 240, 162, 78 | — | 65 | Brand amber. **Fact / state / ground only** — see §1.3. 9.5:1 on `canvas`. |
| `accentPressed` | `#D88D3B` | 216, 141, 59 | — | 3 | Pressed state of an amber ground (primary capsule, mark ring fill). |
| `accentSoft` | `#F0A24E` | 240, 162, 78 | **0.14** | 5 | Amber disc/chip ground. Ink on it is `onAccent`, never amber. Over `canvas` composites to ≈ rgb(41, 30, 20). |
| `ambientBackdropFallback` | `#432D21` | 67, 45, 33 | — | 3 | Pre-art ember for `ArtBackdrop`. Must be **visibly warmer than `canvas`** — see quote. |
| `onAccent` | `#0B0B0D` | 11, 11, 13 | — | 8 | Ink drawn *on* an amber ground. 9.3:1 on `accent`. |
| `interactive` | = `textPrimary` (`#F4F1EC`) | 244, 241, 236 | — | 19 | **The ink of every bare tappable word or glyph.** An alias, not a new hue — see §1.3. |
| `success` | `#30D158` | 48, 209, 88 | — | 1 | Sync "No problems" line only. (Apple's dark systemGreen.) |
| `warning` | `#FFD60A` | 255, 214, 10 | — | 4 | Unsynced-changes dot, sync-status glyph. (Apple's dark systemYellow.) |
| `destructive` | `#FF453A` | 255, 69, 58 | — | 8 | Delete verbs, destructive confirmation buttons. (Apple's dark systemRed.) |
| `information` | `#64D2FF` | 100, 210, 255 | — | **0** | Declared, unused. |
| `separator` | white | 255, 255, 255 | **0.08** | **0** | Declared, unused — `separatorQuiet` replaced it. |
| `stroke` | white | 255, 255, 255 | **0.12** | 4 | Generic outline. **Never** used to make a card visible (see §1.4). |
| `strokeStrong` | white | 255, 255, 255 | **0.20** | 5 | The `.floating` level's full ring. |
| `markRingIdle` | white | 255, 255, 255 | **0.34** | 1 | The unmarked `MarkRing` stroke. See quote. |
| `skeleton` | `#F4F1EC` | 244, 241, 236 | **0.11** | 1 | Skeleton fill. At 8 % it was "≈4 % above ground and effectively invisible". |
| `focusRing` | `#F0A24E` | 240, 162, 78 | **0.70** | **0** | Declared, unused. |
| `scrim` | black | 0, 0, 0 | **0.56** | 1 | Bottom-of-art scrim gradient terminal. |
| `scrimStrong` | black | 0, 0, 0 | **0.72** | 7 | Heavier art scrim / over-art legibility. |
| `hairline` | white | 255, 255, 255 | **0.055** | 6 | 1-px **top-edge** highlight of a raised surface, fading out by its vertical centre. The only "stroke" a content card gets. |
| `separatorQuiet` | white | 255, 255, 255 | **0.045** | 9 | Divider *inside* a plate. |
| `posterEdge` | white | 255, 255, 255 | **0.09** | 16 | The edge of artwork. Never `stroke`. |
| `plateLift` | white | 255, 255, 255 | **0.055** | 1 | `.plate` ground — a *relative* lift, not a fill. |
| `raisedLift` | white | 255, 255, 255 | **0.11** | 1 | `.raised` ground — a *relative* lift. |
| `backdropFade` | = `canvas` | 9, 9, 11 | — | **0** | Declared, unused. |
| `chromeVeil` | = `canvas` | 9, 9, 11 | — | 12 | The veil that hides scrolling content approaching the bars. Full canvas so "content does not slide *under a grey bar*, it dissolves into the app". |
| `controlSheen` | white | 255, 255, 255 | **0.22** | 3 | Light along the top edge of a *filled* control. "An orange rectangle is a swatch; an orange rectangle with a lit top edge is an object." |

**Contrast (recomputed for this spec with the WCAG 2.1 formula, on `canvas` `#09090B`)**

| Ink | Ratio |
| --- | --- |
| `textPrimary` | 17.66 : 1 |
| `accent` | 9.46 : 1 |
| `textSecondary` | 8.21 : 1 |
| `textTertiary` | 5.14 : 1 |
| `textDisabled` | 4.80 : 1 |
| `onAccent` on `accent` | 9.35 : 1 |

Source comment for `textDisabled` (verbatim):

> The quietest ink that is still *read*. #6C6965 measured 3.29:1 on the canvas — legal for a
> chevron (decoration, 3:1) and wrong for the section counts and index letters this token is
> also assigned to. #807C77 is ≈4.6:1 and nothing else in the ramp moves.

Source comment for `markRingIdle`:

> The unmarked `MarkRing`'s stroke. `strokeStrong` at 1.5 pt over a dark poster read as a
> disabled ghost — the app's core control was the least visible element on its row. The mark's
> idle state is an INVITATION and gets its own, clearly-drawn weight.

Source comment for `ambientBackdropFallback`:

> Immediate ground for an artwork wash before a remote image or its palette is available.
> It must be visibly warmer than `canvas`: a near-black fallback made a cold device launch
> look as though the gradient had not rendered, while a cache-warm simulator showed the art.

### 1.3 `accent` vs `interactive` — the load-bearing rule

This is the single most consequential doc comment in the file. Reproduced in full because a port
that gets it wrong is wrong even if it compiles:

> The ink of a bare interactive word or glyph — "See all", "Read more", "Clear", "Sync now",
> "Details", "Add", "Done", a tertiary button in an empty state.
>
> **Amber is not an action colour.** It is rationed to two readings and neither is "tappable":
>   · MEANING — a real next step ("Returns Oct 2", "Episode 19 next", a future air time);
>   · STATE   — today, owned, selected, an active filter, a committed mark.
> Amber may also be a GROUND (`PrimaryButtonStyle2`'s capsule, `MarkRing`'s fill, `accentSoft`
> discs) — there the amber is the object and the ink on it is `onAccent`, so no amber *word*
> is drawn and nothing competes.
>
> Before this token, twenty tappable words and glyphs wore `accent` and collided head-on with
> the first reading: Detail's toolbar said "+ Add" in amber directly above "Episode 14 next"
> in amber, and a Library section header put an amber "See all" over amber "Returns Oct 2"
> captions. One hue cannot mean "this is a fact about your future" and "this is a button".
> Search's add control had it right all along — the actionable `+` is neutral and only the
> owned `✓` is amber (`SearchComponents.swift`).
>
> A bare action carries its affordance the way iOS lists do: position (a toolbar slot, a
> section header's trailing edge), semibold weight, a 44-pt target, and a chevron where the
> row has one. An alias, not a new colour — if this ever needs its own hue, it changes here.
>
> One clarification the STATE reading needs, settled once (cohesion pass, 30 Aug): a
> selector's SELECTED value is legal amber (it is a state, like an active filter) — *except*
> inside a control where amber already carries another meaning. Schedule's ticker is that
> exception: amber is today's alone there, so its selection is a neutral raised plate.
> Library's root tabs keep the amber selection; the two controls are answering different
> constraints, not disagreeing.

**Tint plumbing (three levels, all three deliberate):**

1. Root scene: `.tint(ThemeColor.interactive)` — so back chevrons, alert buttons, the search
   field's Cancel button and its caret are **ink**, not amber.
2. `TabView`: re-tints to `.accent` — a *selected tab* is state.
3. Every tab's `NavigationStack`: re-tints to `.interactive` again.
4. Only toggles and pickers whose value means state carry an explicit `.tint(ThemeColor.accent)`.

**Android:** Compose has no cascading `tint`. Reproduce with a `CompositionLocalProvider` chain
carrying an `LocalControlInk` (default `interactive`), overridden to `accent` inside the bottom
navigation bar and back to `interactive` inside each tab's `NavHost`. Do **not** map `accent` to
`MaterialTheme.colorScheme.primary` — Material tints controls with `primary` by default, which is
exactly the collision the rule forbids. Set `primary` = `interactive`, and treat `accent` as a
separate, hand-applied extended colour.

### 1.4 Surfaces are *lifts*, not fills

Source comment:

> A surface is a RELATIVE lift, not an absolute fill. The shipped `.plate` painted opaque
> `surfaceFlat` wherever it landed, so on any screen carrying an `ArtBackdrop` the ambient wash
> lifted the canvas AROUND the plate and the plate itself inverted into a hole 13 levels darker
> than its own ground — measured on Library, where it is the first element on the screen.
> Painting white over whatever is beneath means a plate is always *above* its ground.

And the corresponding note on the opaque tokens:

> These are the RESULT of `plateLift` / `raisedLift` composited over `canvas`, so a screen that
> reaches for the token directly and a container that goes through `.surface(_:)` land on the
> same colour. The shipped values (#121318 / #181A20) were a 9-value 8-bit step off a #09090B
> canvas and 6 values apart from each other — Apple's dark grouped step is roughly twice that,
> which is why every container still needed an outline to exist.

Verification (do this in the port too): `plateLift` (white 5.5 %) over `canvas` composites to
rgb(22.5, 22.5, 24.4) ≈ `#171718`, matching `surfaceFlat` `#171719`. `raisedLift` (white 11 %)
over `canvas` composites to rgb(36.1, 36.1, 37.8) ≈ `#242426`, matching `surfaceRaised` `#242428`.

**`SurfaceLevel` — the four legal containers** (`Primitives.swift`; the enum itself is outside this
area but its *ground* is a token contract):

| Level | Ground painted | Edge | Shadow | Used for |
| --- | --- | --- | --- | --- |
| `.plate` | `plateLift` (white 5.5 %, translucent) | none at all | `.none` | grouped lists, section grounds, notices |
| `.raised` | `raisedLift` (white 11 %, translucent) | 1-pt `strokeBorder`, `LinearGradient(hairline → clear, .top → .center)` | `.card` | the card carrying the screen's action |
| `.floating` | `surfaceFloating` (**opaque**) | 1-pt `strokeBorder(strokeStrong)` all round | `.floating` | toast, sync banner, menu-like chrome |
| `.art(tint)` | `ArtAdaptiveGround(tint:)` | same top hairline as `.raised` | `.card` | Focus / Recap / hero identity cards |

Shape for all four: `RoundedRectangle(cornerRadius: radius, style: .continuous)`, default radius
`ThemeRadius.card` (22). Order of operations: `background(ground)` → `clipShape` → `overlay(edge)`
→ `shadow`.

> Nothing else is a legal container. If a surface needs an outline to be visible, it is the wrong
> level — move it up, do not draw a box around it.

`.floating` stays opaque on purpose: "a translucent toast with a shelf scrolling through it is
worse than a flat one."

**Android:** `.continuous` corners are Apple squircles, not circular arcs. At radius 22 the
difference is visible. Implement a custom `Shape` approximating the iOS superellipse (or use a
known squircle path implementation) rather than `RoundedCornerShape`. `strokeBorder` draws
**inside** the shape (inset by half the line width) — Compose's `Modifier.border` draws inside too,
so that maps directly, but `Modifier.border` must be applied *after* `clip`.

### 1.5 `ShadowToken`

> A shadow is one token, never three numbers at a call site. On a near-black canvas a shadow is
> not "depth" on its own — it is the soft contact edge under a card whose FILL already separates
> it. Never apply one to a surface that has no tone of its own.

| Token | Colour | Radius | Y offset | Applied to |
| --- | --- | --- | --- | --- |
| `.none` | `.clear` | 0 | 0 | — |
| `.card` | black 45 % | 18 | 10 | Content card on canvas or plate; `.raised` and `.art` surfaces |
| `.art` | black 55 % | 12 | 7 | Posters and stills — "physical objects, so their shadow is tighter and darker" |
| `.artHero` | black 60 % | 26 | 14 | A hero poster, the largest object on its screen |
| `.floating` | black 50 % | 26 | 14 | Toast, sync banner, anything floating over content |

Applied only through `View.shadow(_ token:)` → `shadow(color:radius:y:)` (X offset is always 0).

**Android:** Compose's `Modifier.shadow(elevation, shape, ambientColor, spotColor)` cannot express
an arbitrary radius + offset + alpha. Use `Modifier.drawBehind` with
`Paint().asFrameworkPaint().setShadowLayer(radius, 0f, dy, color)` on a hardware-accelerated layer,
or draw the shape into a `RenderNode` with a blur `RenderEffect`. **Calibrate visually** — the iOS
`radius` is a Gaussian blur parameter and `setShadowLayer`'s radius is not identically scaled.
Difficulty: moderate.

---

## 2. Spacing, radius and rhythm

### 2.1 `ThemeSpace` — the scale

| Token | pt |
| --- | --- |
| `x0_5` | 2 |
| `x1` | 4 |
| `x2` | 8 |
| `x3` | 12 |
| `x4` | 16 |
| `x5` | 20 |
| `x6` | 24 |
| `x8` | 32 |
| `x10` | 40 |
| `x12` | 48 |
| `x16` | 64 |

### 2.2 `ThemeRadius`

| Token | pt | Applied to |
| --- | --- | --- |
| `episodeStill` | 8 | 120 × 68 episode tile |
| `poster` | 10 | generic poster corner |
| `compactControl` | 12 | chips, small controls |
| `row` | 16 | grouped list / row container |
| `toast` | 18 | toast + sync banner capsuloid |
| `card` | 22 | default `surface(_:)` radius |
| `focusCard` | 24 | Today's Focus / handoff ground |

All corners are `style: .continuous` (squircle) wherever a `RoundedRectangle` is constructed in
the design system.

### 2.3 `ThemeMetrics` — rhythm

> Spacing is a scale (`ThemeSpace`); RHYTHM is which step a given relationship gets. Every screen
> used 16 for everything, which is why the shipped build reads as a settings table: a section
> break, a card gap and a title-to-metadata gap cannot all be the same distance and still say
> anything. These are the relationships, named once.

| Token | Value | Uses | Relationship |
| --- | --- | --- | --- |
| `gutter` | 16 | 99 | Screen side margin. Content, section labels and card edges all align to it. |
| `sectionGap` | 30 | 21 | Between two SECTIONS. "Big enough that the eye takes a breath and re-orients." |
| `labelGap` | 10 | 26 | Section label → the first thing under it. "The label belongs to what follows." |
| `cardGap` | 10 | 2 | Between two sibling cards inside one section. |
| `shelfGap` | 12 | 17 | Between shelf items. |
| `titleGap` | 3 | 13 | Title → its own metadata line. "Tight: they are one thought." |
| `artGap` | 14 | 14 | Art → the text it belongs to. |
| `heroClearance` | 26 | 4 | Below a hero, before the first content block. |
| `rowRuleInset` | `gutter + PosterSize.row.width + artGap` = **90** | 1 | Where a poster row's hairline starts — the title's leading edge. Schedule's day-header rule and All-titles' letter-header rule share it. |

### 2.4 Row heights

> A row's height is set by its ART, not by a hairline grid: 68 pt everywhere is what makes a media
> app look like a list of settings.

| Token | pt | Carries |
| --- | --- | --- |
| `rowCompact` | 56 | Text-only or 40-pt-art rows (menus, selection lists) |
| `rowStandard` | 88 | The standard media row: 48 × 72 poster |
| `rowMedia` | 100 | Heavier media row: 56 × 84 poster, two-line title allowed |
| `rowEpisode` | 82 | Episode row carrying a 96 × 54 still |

### 2.5 Chrome edges and bars

> Every root screen in the shipped build scrolls its content straight through the status bar:
> a poster and a show title sit on top of the clock and the battery with nothing between them.
> No shipping media app does this. The fix is systemic, not per-screen.

| Token | Value | Notes |
| --- | --- | --- |
| `topSafeInset` | measured, cached; **59** before a window exists | Read from the key window's `safeAreaInsets.top`, once, and cached — but **only if it is not 59**, so a pre-window default never becomes permanent. Off the main thread it returns 59 without caching. |
| `topChromeRamp` | 22 | "How far BELOW the status bar the veil takes to disappear. Short and hard on purpose: it must clear a large title that sits just underneath, so it may not be a lazy 120-pt wash." |
| `topChromeHeight` | `topSafeInset + 22` | Total top chrome height, safe area included. |
| `inlineBarHeight` | 44 | The system's inline navigation bar, below the status bar. |
| `inlineBarBottom` | `topSafeInset + 44` | The bar's full band. What a root's hardened veil holds through. |
| `barEdgeRamp` | 28 | "The ramp under a HARDENED top veil… Short, like a material bar's own edge." |
| `chromeBarOpacity` | **0.74** | The hardened bar's canvas opacity *over* its blur. Never 1.0 except under Reduce Transparency. |
| `searchDrawerHeight` | 52 | Height the system search drawer adds under an inline title. Added to the hold under a search drawer. |
| `bottomChromeHeight` | 64 | Height of the bottom scroll-edge ramp = the tab pill's own height. |
| `bottomUnderfill` | 180 | Solid canvas over-drawn *below* the ramp, behind the tab bar and across the home-indicator strip. |
| `tabBarClearance` | `bottomChromeHeight + ThemeSpace.x3` = **76** | Scroll bottom inset. The rule is "`bottomChromeHeight` + one gutter, and it is only ever that". |
| `tabBarVisualHeight` | 90 | The tab bar's VISUAL height (pill + home-indicator strip). **The divisor for optically centring a state block — and it is not `tabBarClearance`**: "subtracting a scroll inset when centring pushed every empty state ~81 pt above true centre on Today and Schedule." |
| `toastClearance` | 62 | How far above the safe area's bottom edge a floating toast sits: "the 52-pt pill plus a 10-pt gap". One value for all four tabs. |
| `windowHeight` | measured, cached; **852** before a window exists | Billboard heroes are sized as a fraction of the SCREEN (status bar included). Same not-852-only caching rule as `topSafeInset`. |
| `rootWashHeight` | 320 | THE ambient-wash height, app-wide. |
| `rootWashIntensity` | 0.4 | THE ambient-wash strength, app-wide. |

The `chromeBarOpacity` comment is the reason a straight `1.0` is a regression:

> The hardened bar's canvas over its material — a BAR, not a slab. What has scrolled under
> the title stays faintly alive through the blur, the way every material bar in iOS keeps
> the content behind it present. At 1.0 the top ~100 pt of every scrolled screen was a flat
> #09090B rectangle with a 28-pt edge ("the top area becomes pure black", user, 3 Sep) —
> and the `.ultraThinMaterial` painted under it was doing nothing at all. Reduce Transparency
> drops the material, so it gets the opaque bar back.

And the ambient-wash rule (`rootWashHeight` / `rootWashIntensity`):

> The three roots shipped with 300/0.3, 380–520/0.5–0.68 and 400/0.68, so the same atmosphere was
> a whisper on one tab and a stain on the next — and by the cohesion pass (30 Aug) the tree had
> re-diverged into seven configurations. The rule from here: EVERY ambient wash uses this pair —
> tab roots, pushed lists (Season episodes, Watch history), and Today's no-hero states alike. A
> screen may not carry a private wash spec; Today's full-bleed hero is the one composition that
> replaces the wash outright.

Confirmed call sites, all passing `intensity: ThemeMetrics.rootWashIntensity`: Today, Library
(root + All titles), Search/Discover, Schedule (with `height: max(chromeBottom, topChromeHeight)`),
Detail's non-hero wash, Watch history.

**The bottom-ramp height (64) is a measured value with two named failures behind it.** Quoted in
full because both wrong answers look reasonable:

> 116 started the ramp ~100 pt above the tab pill's top edge, so half of it did nothing but
> dim readable content, while the pill's own glass rim still had un-occluded body copy to
> refract (the mirrored/upside-down text on `finished.png`, `search.png`, `ax-schedule.png`,
> which reads as GPU corruption). It now starts where the pill does and finishes opaque.
>
> 140 said the same thing in a comment and did not do it: the material lift began ~137 pt
> above a pill whose top edge is at 873 pt, so at rest, with no scrolling, the ramp erased
> Today's `WATCHING` label (1.26:1), an interactive `See all` (1.42:1), four lines of Detail's
> synopsis (4.39 → 1.04:1) and Search's sixth `+` button (131 vs 241 for the identical enabled
> control one row higher). Apple's own scroll-edge effect fades ~30–54 pt directly behind an
> opaque bar and never erases 140 pt of visible text.

### 2.6 `scrollSample` — the scroll-offset clamp

```swift
static func scrollSample(_ y: CGFloat, floor: CGFloat = -320, ceiling: CGFloat = 240) -> CGFloat {
    (min(max(y, floor), ceiling) * 2).rounded() / 2
}
```

Clamp to `[-320, 240]`, then **round to the nearest half point** (Swift's `.rounded()` is
half-away-from-zero). Why:

> Every veil, mask and title handover in the app saturates within the first ~120 pt of
> scroll and the pull-down stretch within ~300 pt; past that the offset changes nothing on
> screen. Writing the raw offset to `@State` on every frame re-evaluated Today's whole body
> — the stack, the queue, the shelf, the upcoming rows, every row diff — at 60–120 Hz for
> the entire length of the scroll, which is the jank the user felt (2 Sep). Clamped and
> rounded to the half-point, the value stops changing once the chrome has settled, so the
> body stops re-running. Callers still guard `if v != scrollY`.

**Android:** the equivalent discipline is to keep the scroll offset out of any state read by a
composable that draws the screen. Hold it in a `MutableState<Float>` read only inside
`Modifier.drawBehind { }` / `graphicsLayer { }` lambdas (deferred read), and apply the same clamp
and half-point quantisation before writing. Difficulty: easy, but the *discipline* is the point.

### 2.7 The scroll-edge chrome bands (values consumed by these metrics)

Reproduced here because the metrics above are meaningless without the gradients they drive
(`ScrollEdgeChrome` in `Primitives.swift`). Each band is `ZStack { blurred material (masked); veil }`.
The material layer is `Rectangle().fill(.ultraThinMaterial).mask(blurMask)` and is **omitted
entirely under Reduce Transparency**.

`hold = clamp((holdHeight ?? topSafeInset) / max(height, 1), 0, 1)` — a fraction of the band.

| Band | Veil stops (colour @ opacity, location) | Blur mask stops |
| --- | --- | --- |
| top, `soft: true` | `chromeVeil` .55 @ 0 · .30 @ 0.5 · 0 @ 1 | black .6 @ 0 · .3 @ 0.5 · clear @ 1 |
| top, hardened | `bar` @ 0 · `bar` @ `hold` · `bar × 0.45` @ `hold + (1−hold)·0.45` · 0 @ 1, where `bar = reduceTransparency ? 1.0 : 0.74` | black @ 0 · black @ `hold` · black .42 @ `hold + (1−hold)·0.45` · clear @ 1 |
| bottom | 0 @ 0 · .25 @ 0.55 · .75 @ 0.85 · full canvas @ 1 | clear @ 0 · black .30 @ 0.55 · black .75 @ 0.85 · black @ 1 |

The bottom band is `bottomChromeHeight` (64) tall, followed by `bottomUnderfill` (180) of solid
`chromeVeil` drawn past the layout's bottom edge. Blur mask and veil are re-stopped **together** on
purpose: "A mask that terminates while the veil is still at a third leaves a visible seam straight
across the screen."

**Android:** `.ultraThinMaterial` is a live backdrop blur (UIVisualEffectView). On Android use
`RenderEffect.createBlurEffect(σ, σ, Shader.TileMode.CLAMP)` on the *content* node behind the bar
(API 31+), or the `haze` library. **Below API 31 there is no live backdrop blur** — fall back to
the Reduce-Transparency path (opaque `chromeVeil` at 1.0, no material) which the iOS app already
ships as a legal rendering. Difficulty: hard on API < 31 (accept the fallback), moderate at 31+.

---

## 3. Artwork slots — `PosterSize`

> Artwork slots, named by CONTEXT rather than by number, so no screen has to remember a size.
> Art is this product's only real material — every one of these is at or above the size the
> shipped build used, never below.
>
> **One row slot.** Library rows were 48×72, Search rows 60×90 and Schedule built its own 56×84
> by hand — three poster sizes for the one object the app renders most.

| Case | Size (pt) | Radius | Shadow | Context |
| --- | --- | --- | --- | --- |
| `.hero` | 112 × 168 | 12 | `.artHero` | Detail hero — largest identity object in the app |
| `.libraryHero` | 192 × 288 | 14 | `.artHero` | Library's cover-flow carousel card |
| `.focus` | 88 × 132 | 10 | `.art` | Today's Focus / Recap card |
| `.shelfLarge` | 124 × 186 | 12 | `.art` | Library "Returning" shelf, Search trending |
| `.shelfMedium` | 112 × 168 | 12 | `.art` | Today "Watching" shelf |
| `.todayShelf` | 100 × 150 | 11 | `.art` | Today's denser resting shelf |
| `.row` | **60 × 90** | 10 | `.none` | THE list row — Library, Search, Schedule |
| `.todayQueue` | 52 × 78 | 9 | `.none` | Today's actionable queue |
| `.queue` | 44 × 66 | 8 | `.none` | Today's compact queue rows under the hero |
| `.beat` | 34 × 51 | 6 | `.none` | A recap beat — the smallest slot that still reads as a show |

Radius rule: "Radius tracks size: a 10-pt radius on a 34-pt slot is a blob, on a 112-pt slot it is
sharp." Shadow rule: "Only art large enough to read as an object earns a contact shadow."

`.shelfLarge` at 124 (not 100) is deliberate:

> Widened so a shelf caption's first line carries a real WORD. At 100 pt "That Time I Got
> Reincarnated as a Slime" broke as "That Time I / Got Reincarn…" and "Re:ZERO / -Starting
> Life…" opened a line on a hyphen — the app truncating an identity title on one screen
> while Library's rows render the same title whole.

All slots are **2:3** (0.6667) and posters are **aspect-filled**, never fitted. Source posters are
~0.708, so a 4 % height crop is taken; fitting instead produced "a 5–6 pt bar of exact
`surfaceRaised` grey across [the] top and bottom" of every image.

---

## 4. Typography

### 4.1 The two-family rule

> Type tokens. Outfit SPEAKS — identity (wordmark, titles) and every word the app says in its
> own voice (buttons, row/body copy, facts, link actions). SF Pro ANNOTATES — dense small
> metadata, section labels, numerals/times (Outfit has no tabular figures; timers would jiggle),
> and the one long-form reading paragraph (`prose`). The old split ("Outfit carries identity,
> SF carries information") left Outfit such a thin slice that it read as the anomaly, not the
> voice (user, 30 Aug: "paired with some secondary font that isn't going well").
> Outfit scales with Dynamic Type through `relativeTo:`; SF tokens are system text styles.
> Tracking follows the size ramp of the identity tokens: tighter as the cut gets bigger and
> heavier, neutral by 13 pt.

**Bundled cuts** (registered via `UIAppFonts` in `Info.plist`, files in `ios/Resources/Fonts/`):
`Outfit-Light.ttf`, `Outfit-Regular.ttf`, `Outfit-Medium.ttf`, `Outfit-SemiBold.ttf`,
`Outfit-Bold.ttf`. Five static cuts, no variable font.

`AppFont.name(_ weight:)` snaps a `Font.Weight` to a bundled cut:

| Requested weight | Cut |
| --- | --- |
| `.ultraLight`, `.thin`, `.light` | `Outfit-Light` |
| `.medium` | `Outfit-Medium` |
| `.semibold` | `Outfit-SemiBold` |
| `.bold`, `.heavy`, `.black` | `Outfit-Bold` |
| anything else (incl. `.regular`) | `Outfit-Regular` |

`Font.Weight` is a struct, not an enum, so the mapping is written as `==` comparisons rather than
a `switch` — noted in the source.

### 4.2 `TypeToken`

```swift
struct TypeToken { let font: Font; let tracking: CGFloat }
```

Applied through `View.type(_:)` / `Text.type(_:)` → `.font(token.font).tracking(token.tracking)`.
**`tracking` is an absolute point value that does not scale with Dynamic Type.**

### 4.3 Every `ThemeType` role

"Style" = the SwiftUI `relativeTo:` text style for Outfit tokens, or the system text style for SF
tokens. "Default pt" is the iOS point size at the Large (default) content size.

**Palette tokens (`enum ThemeType`)**

| Token | Family & weight | Size | Style (`relativeTo`) | Tracking |
| --- | --- | --- | --- | --- |
| `brandWordmark` | Outfit SemiBold | 20 | `.headline` | −0.30 |
| `displayXL` | Outfit Bold | 34 | `.largeTitle` | −0.80 |
| `displayL` | Outfit Bold | 28 | `.title` | −0.60 |
| `showTitleL` | Outfit SemiBold | 22 | `.title2` | −0.35 |
| `showTitleM` | Outfit SemiBold | 17 | `.headline` | −0.20 |
| `sectionTitle` | Outfit SemiBold | 20 | `.title3` | −0.30 |
| `body` | Outfit Regular | 17 | `.body` | −0.10 |
| `bodyEmphasis` | Outfit SemiBold | 17 | `.body` | −0.20 |
| `button` | Outfit SemiBold | 16 | `.callout` | −0.15 |
| `callout` | Outfit Regular | 16 | `.callout` | −0.10 |
| `metadata` | **SF** regular | 13 (`.footnote`) | system style | 0 |
| `metadataEmphasis` | **SF** semibold | 13 (`.footnote`) | system style | 0 |
| `sectionLabel` | **SF** semibold | 11 (`.caption2`) | system style | **+1.0** |
| `caption` | **SF** regular | 11 (`.caption2`) | system style | 0 |
| `numberXL` | **SF** bold, **monospacedDigit** | 34 (`.largeTitle`) | system style | −0.50 |
| `time` | **SF** semibold, **monospacedDigit** | 15 (`.subheadline`) | system style | 0 |

**Contextual tokens (`extension ThemeType`)**

| Token | Family & weight | Size | Style | Tracking |
| --- | --- | --- | --- | --- |
| `heroTitle` | Outfit Bold | 28 | `.title` | −0.55 |
| `heroMeta` | Outfit Regular | 15 | `.subheadline` | −0.05 |
| `prose` | **SF** regular | 15 (`.subheadline`) | system style | 0 |
| `cardFact` | Outfit SemiBold | 15 | `.subheadline` | −0.10 |
| `rowTitle` | Outfit SemiBold | 17 | `.headline` | −0.20 |
| `rowMeta` | **SF** regular | 13 (`.footnote`) | system style | 0 |
| `rowMetaLead` | **SF** semibold | 13 (`.footnote`) | system style | 0 |
| `shelfTitle` | Outfit **Medium** | **14** | `.subheadline` | −0.10 |
| `shelfCaption` | **SF** medium | 12 (`.caption`) | system style | 0 |
| `listAction` | Outfit SemiBold | 13 | `.footnote` | 0 |

Retired: `showTitleS` and `screenTitle` (30 Aug — "no call sites").

`prose` is SF **on purpose**:

> Long-form reading text — Detail's synopsis, the one paragraph in the app. Subheadline, with
> the call site opening the leading (`lineSpacing(5)`). It was `body`: 17-pt default-leading
> grey — visually an unstyled SwiftUI `Text` — and TWO POINTS LARGER than the hero's own
> `heroMeta` line above it, so the type ladder inverted at exactly the step where it should
> step down (user device, 30 Aug: "the description font looks plain wrong").
> Deliberately still SF under the "Outfit speaks" rule: a synopsis is quoted CONTENT, not
> the app's voice, and SF reads better than a geometric sans over a full paragraph.

`sectionTitle` replaced small-caps as the shelf-header family:

> THE section header (2 Sep). Every shelf and list section in the app is headed by this —
> mixed case, the app's voice, with a trailing chevron when the header is the way into the
> section. It replaces the 11-pt small-caps `SectionLabel` as the header family: Apple TV,
> Netflix and Apple Music all head a shelf with a bold title the size of a row title plus a
> step, and the small-caps eyebrow read as a footnote above the shows it introduced. Small
> caps stay for EYEBROWS (`OverArtLabel`, a grouped list's header) — the two levels now
> split cleanly instead of one token doing both jobs.

`listAction` is deliberately small: "a 16-pt semibold word beside an 11-pt grey label wins a fight
it should lose. Rendered in `ThemeColor.interactive` — a link is an action, and actions are not
amber."

`cardFact` is primary ink, not grey: "a fact the whole card exists to deliver may not be rendered
in the same grey as its footnote."

### 4.4 Type by context — the ASSIGNMENT table

> The tokens above are a PALETTE. This extension is the ASSIGNMENT: which token a thing gets
> because of where it sits. The shipped build set every title to `showTitleM` and every second
> line to `metadata`, at every altitude, which is why nothing on any screen was allowed to be the
> hero and nothing was allowed to be quiet.

| Altitude | Slot | Token | Ink |
| --- | --- | --- | --- |
| **HERO** (one per screen) | title | `heroTitle` — Outfit Bold 28 | `textPrimary` |
| | eyebrow (**above** the title, never below) | `sectionLabel` — SF 11 semibold +1.0 | `textTertiary` |
| | meta | `heroMeta` — Outfit 15 | `textSecondary` |
| **CARD** (the one card carrying an action) | title | `showTitleL` — Outfit SemiBold 22 | `textPrimary` |
| | fact | `cardFact` — Outfit SemiBold 15 | `textPrimary` ← **the fact is NOT grey** |
| | support | `metadata` — SF 13 | `textTertiary` |
| **ROW** (repeating, scannable) | title | `rowTitle` — Outfit SemiBold 17, 1 line (2 at AX) | `textPrimary` |
| | meta | `rowMeta` — SF 13 | `textSecondary` |
| | forward-looking fact | `rowMetaLead` — SF 13 semibold | `accent` — *only a real next step earns amber* |
| **SHELF** (poster + caption) | title | `shelfTitle` — Outfit Medium (code: **14**; comment says 15), exactly 2 reserved lines | `textPrimary` |
| | caption | `shelfCaption` — SF 12 medium | `textSecondary` (`accent` when it is a next step) |
| **SECTION** | title | `sectionTitle` — Outfit SemiBold 20, chevron when it navigates | `textPrimary` |
| | count | `metadata` — SF 13, on the title's baseline | `textTertiary` |
| | eyebrow | `sectionLabel` — SF 11 semibold +1.0, over art (`OverArtLabel`) and grouped lists only | `textTertiary` |
| | inline action | `listAction` — Outfit SemiBold 13 | `interactive` ← an inline link ("Clear"); **never amber** |

### 4.5 Dynamic Type

- Scaling ceiling: the root scene applies `.dynamicTypeSize(...DynamicTypeSize.accessibility2)` —
  "Scale text for accessibility, but cap before the densest grids break." AX3–AX5 are clamped to
  AX2.
- Outfit tokens scale via `Font.custom(_:size:relativeTo:)`, which applies the named text style's
  Dynamic Type ramp to the custom size. At the default (Large) content size the rendered size is
  exactly the declared size.
- SF tokens are `Font.system(_ style:)` / `.footnote` / `.caption2` etc. and scale natively.
- Tracking never scales.
- Inherited default font on the whole scene: `.font(.custom("Outfit-Regular", size: 17, relativeTo: .body))`
  — "so any text not already using `.scaledFont` (and SwiftUI TextField input) still renders in the
  brand typeface, scaled."
- At accessibility sizes several components change shape rather than truncate. House rule from
  `Primitives+States.swift`: "nothing truncates at accessibility sizes — the container grows."
  Concrete examples in scope here: `SectionLabel` goes `lineLimit(1) → 2` when
  `typeSize.isAccessibilitySize`; Schedule's "Nothing scheduled" moves from the header's count slot
  into a row under the header only at accessibility sizes.

### 4.6 `ScaledFont` — currently dead

`ScaledFont.swift` declares `View.scaledFont(_ size:weight:monospacedDigit:relativeTo:)`, which
uses `@ScaledMetric(wrappedValue: size, relativeTo:)` and then `AppFont.font(size: scaledSize, ...)`.
**It has zero call sites in `ios/Sources`.** Everything goes through `ThemeType` + `.type(_:)`
instead. The file's own comment — "`@ScaledMetric` is exactly 1.0 at the default content size, so
every existing layout stays pixel-identical to before" — describes a migration that has since
completed by a different route. Do not port it; port `ThemeType`.

Note the two paths differ subtly and only one is live: `@ScaledMetric` scales the *number*, then
builds a fixed-size font; `Font.custom(relativeTo:)` builds a scaling font. Both are identity at
Large.

### 4.7 UIKit appearance proxies (`AppAppearance` + `AniTrackApp.applyBrandFont`)

Installed **once at launch**, never from `onAppear`:

> A proxy is global, so every other segmented control and search field in the app rendered one way
> before the user had visited that screen and another way after. Launch is the only place a global
> belongs.

| Proxy | Value | Why |
| --- | --- | --- |
| `UISearchTextField.appearance().font` | `UIFontMetrics(.body).scaledFont(for: .systemFont(ofSize: 17, weight: .regular))` | "input in a catalogue field is information, not identity, so it is SF at body size" |
| `UITabBarItem` normal title | `Outfit-Medium 10`, `UIFontMetrics(.caption2)`-scaled | Tab-bar item titles are drawn by UIKit; the SwiftUI default font never reaches them |
| `UITabBarItem` selected title | `Outfit-SemiBold 10`, `UIFontMetrics(.caption2)`-scaled | same |

Applied to `UITabBarItem.appearance()` and to all three `UITabBarItemAppearance` layouts
(`stacked`, `inline`, `compactInline`) of a `UITabBarAppearance` configured with
`configureWithDefaultBackground()`, set as both `standardAppearance` and `scrollEdgeAppearance`.

**Explicitly not installed:** a `UISegmentedControl` appearance proxy. It was there once and
"flattened the system SEARCH SCOPE BAR into a grey strip — on iOS 26+ that control is Liquid Glass
by default, and it stays that way everywhere."

### 4.8 Android notes for type

| Item | Android | Difficulty |
| --- | --- | --- |
| Outfit static cuts | Ship the same five `.ttf` files as a `FontFamily` with `FontWeight.Light/Normal/Medium/SemiBold/Bold`. Compose maps `SemiBold` (600) correctly to the SemiBold cut. | Easy |
| SF Pro tokens | **No SF Pro on Android.** Use Roboto (the platform UI face) at the same point sizes and weights. The two-family contrast survives — Outfit (geometric) vs Roboto (neo-grotesque) reads like Outfit vs SF. | Easy, but visually not identical |
| `relativeTo:` Dynamic Type ramp | Android has one global `fontScale` multiplier plus (API 34+) non-linear scaling. There is no per-text-style ramp. Declare sizes in `sp` and accept linear scaling; clamp `fontScale` to the AX2-equivalent (~1.6×) with a `CompositionLocalProvider(LocalDensity provides Density(density, fontScale.coerceAtMost(1.6f)))`. | Moderate |
| Tracking | Compose `TextStyle(letterSpacing = (-0.30).sp)` — but `sp` **scales**, and the iOS values do not. Use `letterSpacing = (value).dp.toSp()` computed at the current density, or set it in `TextUnit(px)` terms. | Moderate |
| `monospacedDigit()` | `TextStyle(fontFeatureSettings = "tnum")` on Roboto. | Easy |
| Small-caps eyebrows | iOS uses `.textCase(.uppercase)` on `sectionLabel`, not a small-caps feature. Uppercase the string in Compose. | Easy |

---

## 5. Motion

### 5.1 `ThemeMotion` — every curve

`response`/`dampingFraction` are SwiftUI spring parameters (unit mass): natural frequency
ω₀ = 2π / response, so Compose `stiffness = ω₀²` and `dampingRatio = dampingFraction`.

| Token | SwiftUI | Duration / spring | Compose equivalent | Uses | Assigned to |
| --- | --- | --- | --- | --- | --- |
| `uiPress` | `easeOut` | 0.09 s | `tween(90, easing = CubicBezierEasing(0f, 0f, 0.58f, 1f))` | 12 | **Touch compression only.** |
| `uiMicro` | `spring` | response 0.22, damping 0.88 | `spring(dampingRatio = 0.88f, stiffness = 815.7f)` | 18 | Checkmarks, icon replacement, chip selection, status change. |
| `uiSnappy` | `spring` | response 0.34, damping 0.84 | `spring(0.84f, 341.5f)` | 21 | Fast local layout changes and user-requested expansion. |
| `uiSettle` | `spring` | response 0.46, damping 0.90 | `spring(0.90f, 186.6f)` | 19 | Large but controlled card-to-card or source-to-destination motion. |
| `uiMilestone` | `spring` | response 0.38, damping 0.74 | `spring(0.74f, 273.4f)` | 2 | **One restrained overshoot for a meaningful milestone (series complete only).** |
| `uiGentle` | `easeInOut` | 0.22 s | `tween(220, easing = CubicBezierEasing(0.42f, 0f, 0.58f, 1f))` | 32 | State fades, stale strips, error notices, NOW movement. |
| `uiReveal` | `timingCurve(0.22, 1.00, 0.36, 1.00)` | 0.28 s | `tween(280, easing = CubicBezierEasing(0.22f, 1f, 0.36f, 1f))` | 5 | Initial content reveal. |
| `uiPoster` | `easeOut` | 0.18 s | `tween(180, CubicBezierEasing(0f, 0f, 0.58f, 1f))` | 5 | Poster tint → final image cross-dissolve. |
| `uiNumeric` | `easeOut` | 0.22 s | `tween(220, …easeOut)` | 1 | Numeric content transition. |
| `uiSweep` | `timingCurve(0.40, 0.00, 0.20, 1.00)` | 0.52 s | `tween(520, CubicBezierEasing(0.4f, 0f, 0.2f, 1f))` | 2 | Season-complete hairline, History rail. |
| `uiDismiss` | `easeIn` | 0.16 s | `tween(160, CubicBezierEasing(0.42f, 0f, 1f, 1f))` | 2 | **Toast dismissal only.** |
| `uiLiveBreath` | `easeInOut(1.80).repeatForever(autoreverses: true)` | 1.80 s, reversing | `infiniteRepeatable(tween(1800, easing = …easeInOut), RepeatMode.Reverse)` | **0** | Wordmark live indicator. Declared, **no call sites**. |
| `uiReduced` | `easeOut` | 0.12 s | `tween(120, …easeOut)` | 3 (direct) | **Universal Reduce Motion fallback.** |
| `uiCrossfade` (alias, declared in `Primitives+States.swift`) | = `uiReduced` | 0.12 s | same | 2 | Skeleton ⇄ content swap. "Board 09's '120-ms crossfade' and board 11's Reduce Motion fallback are the same curve, so this is a name for `uiReduced`, not a fourteenth token." |

**Reduce Motion:** every animation in the app is written
`ThemeMotion.pick(ThemeMotion.<token>, reduceMotion: reduceMotion)` (93 call sites), where

```swift
static func pick(_ token: Animation, reduceMotion: Bool) -> Animation {
    reduceMotion ? uiReduced : token
}
```

There is **one** substitute for everything: a 0.12 s ease-out. Nothing is disabled outright by
`pick`; things that must actually stop (drift, splash, skeleton breath) branch on `reduceMotion`
themselves — see §5.4.

**Compose easing warning:** SwiftUI's `.easeInOut`/`.easeOut`/`.easeIn` are the CSS cubic-beziers
(0.42, 0, 0.58, 1) / (0, 0, 0.58, 1) / (0.42, 0, 1, 1). Compose's `FastOutSlowInEasing` is
(0.4, 0, 0.2, 1) — **not the same shape**. Declare the beziers explicitly.

### 5.2 The handoff transition

> One card is replaced by the next one on four surfaces — Today's Focus card after a mark, Detail's
> Next-up card, a Schedule row settling, Search's results replacing the launchpad. The build shipped
> four different answers: Today's (correct) asymmetric construction, a symmetric 460 ms crossfade on
> Detail that renders two show titles and two CTA labels superimposed for a quarter of a second, a
> 40 % scale pop on Schedule, and SwiftUI's default crossfade of two whole view trees on Search.

```swift
static func handoff(reduceMotion: Bool) -> AnyTransition {
    guard !reduceMotion else { return .opacity.animation(ThemeMotion.uiReduced) }
    return .asymmetric(
        insertion: .opacity.animation(ThemeMotion.uiSettle.delay(0.08)),
        removal:   .opacity.animation(ThemeMotion.uiDismiss)
    )
}
```

- **Removal first**: fade out on `uiDismiss` (ease-in 160 ms).
- **Insertion delayed 80 ms**, then fade in on `uiSettle` (spring, response 0.46 / damping 0.90).
- Under Reduce Motion both halves collapse to `uiReduced` (120 ms) with **no delay** — "still a
  handover, no travel."
- The **ground must not belong to either card**. `View.handoffGround(tint:radius:)` puts an
  `ArtAdaptiveGround` clipped to `ThemeRadius.focusCard` (24) on the *container that survives*,
  "or the canvas flashes through the gap between them."

### 5.3 The toast transition

```swift
static func toast(reduceMotion: Bool) -> AnyTransition {
    guard !reduceMotion else { return .opacity.animation(ThemeMotion.uiReduced) }
    return .asymmetric(
        insertion: .opacity.combined(with: .offset(y: 4)).animation(ThemeMotion.uiSnappy),
        removal:   .opacity.animation(ThemeMotion.uiDismiss)
    )
}
```

A **4-pt rise** on `uiSnappy` in; `uiDismiss` out. "`uiDismiss` was minted for exactly this moment
and had one call site that was not this one — a toast leaving on the spring it arrived on reads as
a bounce, not a dismissal."

### 5.4 Motions that branch on Reduce Motion themselves

| Motion | Normal | Reduce Motion |
| --- | --- | --- |
| Billboard **drift** (`ArtHeader(drift: true)` — Today and Detail only) | After an 80 ms delay ("an animation started in the same transaction as the view's own appearance is folded into it and never repeats"), `withAnimation(.easeInOut(duration: 24).repeatForever(autoreverses: true))` scales the **sharp layer only** from 1.0 → **1.07**, anchored `.top` / `.bottom` / `.center` per the header's focus. One transform on one layer, so no body re-evaluates. | `drifting = false`; no animation started. |
| **Skeleton breath** (`SkeletonGate`) | `Animation.easeInOut(duration: 1.4).repeatForever(autoreverses: true)`, opacity **0.88 ⇄ 1.0**. | Static opacity **0.92**, animation `nil`. |
| **Splash** (`SplashView`) | Full ~2 s timeline driven by `TimelineView(.animation)` over real elapsed seconds; the ignition haptic fires at t = 0.92 s; hand-off at t = 1.68 s. | `tm` is pinned at **1.4** (a static late-timeline frame), **no haptic**, hand-off after 1.2 s. |

Skeleton breath amplitude is a corrected value:

> The amplitude is 0.88 ↔ 1.0, not 0.65 ↔ 1.0. A 35 % oscillation across the WHOLE screen, forever,
> is not a reassurance that something is working — it is a pulse the eye cannot ignore and cannot
> look away from, on the frame the user is already waiting through. 12 % still visibly breathes.

**Shimmer is refused by name** on skeletons: "a travelling highlight is decoration pretending to be
progress."

### 5.5 The loading gate timing (SkeletonGate — the 240 / 320 / 120 rule)

Lives in exactly one place and nowhere else:

- **240 ms**: nothing at all is drawn — not the skeleton, not the content. "a fast response should
  never flash a skeleton."
- Once shown, the skeleton stays a minimum of **320 ms** even if data lands at 250 ms.
- Swap to content is a **120 ms** ease-out crossfade (`uiCrossfade` = `uiReduced`).
- After **800 ms** of visible skeleton, `slow` flips (inside `uiGentle`) and a small
  `ProgressView` appears.
- The minimum-window clock is `ContinuousClock`, not wall clock: "a wall-clock stamp could be moved
  by the system mid-window and compute a negative or absurd remainder."
- The skeleton element is `accessibilityElement(children: .ignore)` with label
  `Copy.Accessibility.loading`.

### 5.6 Reduce Transparency

Only one behaviour, and it belongs to the chrome bands: the `.ultraThinMaterial` layer is not drawn
at all, and the hardened top veil goes from `chromeBarOpacity` (0.74) to **1.0**.

> Under Reduce Transparency there is no blur to carry the bar, so it is opaque there — a
> 74 % veil with nothing softening what is under it is the half-lit row under "Library"
> that the hardened bar was built to end.

**Android:** there is no OS "Reduce Transparency" setting. Map this to the *capability* instead:
API < 31 (no `RenderEffect` blur) takes the Reduce-Transparency path. Optionally expose it as an
in-app accessibility toggle. Difficulty: easy, once framed this way.

**Android Reduce Motion:** read
`Settings.Global.getFloat(resolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f`, or
`AccessibilityManager.isReducedMotionEnabled`-style helpers where available, and expose it as a
`LocalReduceMotion` CompositionLocal consumed by a `pickMotion(token)` helper mirroring
`ThemeMotion.pick`.

---

## 6. Haptics

### 6.1 The vocabulary — `FeedbackToken`

> Every haptic in the app goes through here. One-sentence justification per token (board 11).

| Token | iOS generator | Exact call | Meaning (verbatim comment) |
| --- | --- | --- | --- |
| `.selection` | `UISelectionFeedbackGenerator` | `selectionChanged()` then `prepare()` | *a discrete selected value changed* |
| `.commitLight` | `UIImpactFeedbackGenerator(style: .light)` | `impactOccurred(intensity: 0.65)` then `prepare()` | *one watch fact recorded on this device* |
| `.commitMedium` | `UIImpactFeedbackGenerator(style: .medium)` | `impactOccurred(intensity: 0.72)` then `prepare()` | *a larger contiguous progress change recorded* |
| `.success` | `UINotificationFeedbackGenerator` | `notificationOccurred(.success)` then `prepare()` | *season/series complete · title added · rewatch started* |
| `.destructive` | `UINotificationFeedbackGenerator` | `notificationOccurred(.warning)` then `prepare()` | *an irreversible deletion was accepted* |
| `.refreshArmed` | `UIImpactFeedbackGenerator(style: .light)` | `impactOccurred(intensity: 0.50)` then `prepare()` | *releasing now will refresh* |
| `.directError` | `UINotificationFeedbackGenerator` | `notificationOccurred(.error)` then `prepare()` | *an explicit action failed* |

Note `.destructive` deliberately uses the **warning** notification pattern, not `.error`.

Four generator instances are held as statics and re-`prepare()`d after each fire (keeps the Taptic
Engine warm for the next event in the same gesture).

### 6.2 The gate

```swift
static func fire(_ token: FeedbackToken) {
    guard enabled, UIApplication.shared.applicationState == .active else { return }
    let now = Date().timeIntervalSinceReferenceDate
    guard now - (lastFire[token] ?? 0) >= floor(for: token) else { return }
    lastFire[token] = now
    …
}
```

Three conditions, all required:

1. **`enabled`** — `UserDefaults` key `"previously.haptics"`, `Bool`, **default `true`**. Exposed
   as the Profile → Haptics toggle. Comment: "Haptics: On / Off (Accessibility). System settings
   remain authoritative."
2. **App must be `.active`** — never fires while backgrounded or inactive.
3. **Per-token throttle floor**, keyed by token, *not* one shared stamp:

| Token | Floor |
| --- | --- |
| `.selection` | **0.04 s (40 ms)** |
| every other token | **0.3 s (300 ms)** |

Both halves of that design are quoted decisions:

> Per token, as the floor is: one shared stamp meant adding two shows in quick succession
> buzzed once, an error inside 300 ms of the commit it belonged to was swallowed, and Undo
> tapped straight after a mark gave no selection tick at all.

> A blanket 300 ms floor is right for a commit — two marks 100 ms apart are one transaction
> and must buzz once. It is wrong for `.selection`, which is the token the A–Z index rail and
> the week strip use: UIKit's own `UITableViewIndex` fires per section, unthrottled, and at
> 300 ms an A→W drag yielded at most two taps out of twenty-odd. Selection is *tracking* a
> finger, not confirming a write.

### 6.3 "At most one per transaction" — where each token actually fires

House rule (`Primitives+States.swift` header): "every haptic through `FeedbackCoordinator.fire(_:)`,
at most one per transaction". The 300 ms floor is the *mechanism*; the discipline below is the
*intent*. Note the pattern used by Schedule's filter bindings: **the haptic fires from the mutation,
not from an observer** — "so one transaction is one haptic."

| Token | Trigger (file: what happened) |
| --- | --- |
| `.selection` | Splash: exactly at the ignition beat, `t = 0.92 s` (skipped under Reduce Motion). Root: `onChange(of: selectedTab)`. `AppModel.setStatus(haptic: true)`. `AppModel.performUndo()`. `AppModel+Writes.undoTapped` and `restoreRemoved`. Library: filter chip tap, Reset, A–Z rail `select(index:)`, arrange-sheet value change. Schedule: "Today" button, a ticker day tap, source filter binding, hide-watched binding, filter-chip clear, no-matches empty-state action, Earlier row expand. Discover/Search: `onChange(of: mediaFilter)`, scope chip tap. Rewatch: scope picker row. Profile: turning the Haptics toggle **on** (the toggle's own confirmation). |
| `.commitLight` | `AppModel.setProgress(haptic: true)` when the delta is **≤ 1 episode** (`abs(clamped - prev) > 1 ? .commitMedium : .commitLight`). `AppModel.removeFromLibrary(haptic: true)`. |
| `.commitMedium` | `AppModel.setProgress` when the delta is **> 1 episode**. `AppModel.markCaughtUp` when the target is *not* a series milestone. |
| `.success` | `AppModel.addToLibrary`. `AppModel.markCaughtUp` when `milestone` is true — `!part.isReleasing && part.totalEpisodes > 0 && part.airedEpisodes >= part.totalEpisodes`. Detail: start rewatch, restart rewatch, mark series complete. Rewatch: "Mark rewatch complete". Discover: notification permission **granted**. |
| `.destructive` | Profile: sign out, delete account. Detail: cancel a rewatch. Rewatch: delete session, delete all history, stop rewatch. `Primitives+States`: "discard changes" confirmation. |
| `.refreshArmed` | Pull-to-refresh: fires **once**, when `!armed && dragging && progress >= 1`. Guarded so it "may only fire while there is something to let go of." |
| `.directError` | `AppModel.showError(_:)`. `SyncCenter`: a retry the *user* explicitly asked for failed within `directErrorWindow`; inside `retryAll()` it is **one haptic for the whole batch**, gated by `batchErrorFired`. |

Explicitly **silent** (no haptic): a progress write failing in the background (it goes to the sync
banner instead — "a progress mark never rolls back"); `setStatus`/`setProgress` called with
`haptic: false` inside a compound transaction (e.g. a rewatch, where the outer action already fired
`.success`); `showNotice` receipts.

### 6.4 Android mapping

| iOS | Android | Difficulty |
| --- | --- | --- |
| `UISelectionFeedbackGenerator.selectionChanged()` | `view.performHapticFeedback(HapticFeedbackConstants.SEGMENT_TICK)` (API 34+), else `CLOCK_TICK`. In Compose: `LocalHapticFeedback.current.performHapticFeedback(HapticFeedbackType.SegmentTick)` where available. | Easy–moderate |
| `UIImpactFeedbackGenerator(.light).impactOccurred(intensity: 0.65)` | `VibrationEffect.startComposition().addPrimitive(PRIMITIVE_CLICK, 0.65f).compose()` (API 30+, requires `Vibrator.arePrimitivesSupported`), else `VibrationEffect.createOneShot(12, ~110)`. | Moderate |
| `.medium` at 0.72 | same composition with `PRIMITIVE_CLICK, 0.72f`, or `createOneShot(16, ~150)`. | Moderate |
| `.light` at 0.50 (`refreshArmed`) | `PRIMITIVE_TICK, 0.5f`, else `createOneShot(10, ~80)`. | Moderate |
| `notificationOccurred(.success)` | **No equivalent pattern.** Hand-author: `startComposition().addPrimitive(PRIMITIVE_CLICK, 0.6f).addPrimitive(PRIMITIVE_CLICK, 1.0f, delay = 90).compose()` (rising double-tap). | Moderate — needs tuning by feel |
| `notificationOccurred(.warning)` (`destructive`) | Hand-author a falling double-tap: `CLICK 1.0f`, then `CLICK 0.6f` after 90 ms. | Moderate |
| `notificationOccurred(.error)` | Hand-author a three-beat pattern: `createWaveform(longArrayOf(0, 20, 80, 20, 80, 40), intensities, -1)`. | Moderate |
| `prepare()` | No Android equivalent; nothing to do. | n/a |
| `applicationState == .active` guard | Gate on the activity being `RESUMED`. | Easy |
| Per-token throttle | Port verbatim: a `Map<FeedbackToken, Long>` of `SystemClock.elapsedRealtime()` stamps, floor 40 ms for selection / 300 ms otherwise. | Easy |
| `enabled` default `true` | DataStore key `previously.haptics`, default `true`. Also respect `Settings.System.HAPTIC_FEEDBACK_ENABLED`. | Easy |

---

## 7. Palette — the art-adaptive ground

### 7.1 What it is

Every identity surface in the app (Focus card, Recap card, Detail hero bloom, the episode tile
fallback, every screen's ambient wash) is grounded in **one colour derived from the show's own
artwork**. The derivation is deliberately lossy — the ground is "related to the show, never hostage
to its palette".

**Where it runs:** `PaletteCache` is `@MainActor`, holds `cache: [String: Color]` keyed by artwork
URL and an `inFlight: Set<String>`; the pixel work runs in `Task.detached(priority: .utility)`.
"Computed once per artwork URL, off the main thread, never during scroll."

**Fallback:** `PaletteCache.fallback = Color(hex: 0x1C1A17)` = rgb(28, 26, 23), "neutral warm
surface".

**Two entry points:**

- `resolve(url:maxPixel:) async -> Color` — always returns a colour, falling back to
  `PaletteCache.fallback`.
- `resolveIfAvailable(url:maxPixel:) async -> Color?` — returns `nil` when there is no URL, no
  decoded image, or a resolve is already in flight for that URL. "The optional form is for surfaces
  that own a meaningful branded fallback. Returning nil keeps that fallback on stage when a device
  is offline or the artwork decode is still busy, instead of replacing it with a neutral colour
  that is indistinguishable from the canvas."

Resolution order inside `resolveIfAvailable`: empty/nil URL → `nil`; cache hit → return it;
already in flight → return whatever is in the cache (usually `nil`); otherwise take the already
decoded image from `ImageCache.shared.image(for:atLeast: maxPixel)` if present, else
`ImageLoader.shared.image(for:maxPixel:)`; nil image → `nil`; then extract, cache, return.

Observed `maxPixel` values at call sites: 320 (`ArtBackdrop`), 360 (Today's hero/recap), 420
(Detail hero + Detail wash), 288 (episode still tint, Primitives), `max(width, height) * 3`
(`PosterSlot`).

### 7.2 `dominantTint(of:)` — the exact algorithm

Reimplement this literally. **Do not substitute `androidx.palette`** — it is a different algorithm
(median-cut on HSL with hard-coded "vibrant/muted" targets) and produces visibly different grounds.

**Step 1 — downsample.** Draw the `CGImage` into a **32 × 32** RGBA8 bitmap
(`CGColorSpaceCreateDeviceRGB`, `premultipliedLast`, `bytesPerRow = 32 * 4 = 128`,
`interpolationQuality = .medium`), filling the whole 32 × 32 rect. **The draw does not preserve
aspect ratio** — the image is squashed to a square. If the `CGImage` is missing, return `fallback`.

Android: `Bitmap.createScaledBitmap(source, 32, 32, /* filter = */ true)` then `getPixels`.

**Step 2 — per-pixel filtering and bucketing.** For each of the 1024 pixels:

| Test | Reject when |
| --- | --- |
| alpha | `a / 255 < 0.8` |
| OKLab lightness | `L < 0.08` or `L > 0.92` (near-black / near-white) |
| OKLab chroma | `sqrt(a² + b²) < 0.035` (neutral) |

Surviving pixels are bucketed into **12 hue bins × 4 lightness bins**:

```swift
let hue = atan2(b, a)                                   // (−π, π]
let key = Int((hue + .pi) / (2 * .pi) * 12) * 10 + Int(l * 4)
```

Accumulate per bucket: `sum(L)`, `sum(a)`, `sum(b)`, `count`. (Note the harmless edge case: a hue of
exactly +π yields bin index 12, i.e. a 13th bucket. Reproduce or clamp — it never matters in
practice, and the `key` encoding leaves room for it because bins are spaced by 10.)

**Step 3 — pick.** `buckets.values.max(by: { $0.n < $1.n })`, i.e. the **highest-population** bucket.
If there are no buckets, return `fallback`. (Tie-breaking is dictionary-order and therefore
unspecified — an Android port may break ties by lowest key without visible consequence.)

**Step 4 — mean.** `L = sumL/n`, `a = sumA/n`, `b = sumB/n`.

**Step 5 — clamp lightness.** `L = clamp(L, 0.30, 0.44)`.

**Step 6 — clamp chroma and lean toward brand amber.**

```swift
let c = sqrt(a*a + b*b)
let cc = min(max(c, 0.075), 0.145)
if c > 0 {
    var ua = a / c, ub = b / c                       // unit hue vector
    let (_, wa, wb) = oklab(r: 0xF0/255, g: 0xA2/255, b: 0x4E/255)   // brand amber #F0A24E
    let wn = sqrt(wa*wa + wb*wb)
    ua = 0.85 * ua + 0.15 * (wa / wn)
    ub = 0.85 * ub + 0.15 * (wb / wn)
    let un = sqrt(ua*ua + ub*ub)
    a = ua / un * cc; b = ub / un * cc
}
```

Precomputed constants so the port does not need to re-derive them: OKLab of `#F0A24E` is
**L ≈ 0.7737, a ≈ 0.05652, b ≈ 0.12299**; `wn ≈ 0.13536`; the **unit brand hue vector is
(0.4175, 0.9087)** (≈ 65.3°).

**Step 7 — back to sRGB** via the inverse OKLab transform, each channel gamma-encoded and clamped
to `[0, 1]`.

The clamp values in step 5/6 are a correction with measurements attached:

> The clamps the ambient wash regressed on. Measured against the baseline at (1200,300):
> Library new rgb(36,30,27) vs original rgb(45,32,22) — 20 % dimmer with R−B falling 23→9;
> Schedule new rgb(32,32,29) vs original rgb(71,64,59) — less than half the luminance,
> R−B 12→3. Chroma clamped to 0.035–0.075 and then blended 35 % toward brand amber makes
> "art-derived colour" arithmetically present and perceptually absent: neutral charcoal
> where the baseline had warm ember. The chroma ceiling doubles, the lightness floor rises,
> and the brand blend drops to a breath (0.15) that stops the app swinging olive or steel
> from tab to tab without erasing the show's own hue.

> ⚠️ **Stale header comment.** The file-level comment at the top of `Palette.swift` still says
> "clamp L 0.24…0.38, C 0.04…0.12 … black overlay 44 %". Those are the *superseded* values. The
> shipping code clamps **L 0.30…0.44, C 0.075…0.145** and the black overlay is **0.30** (see §7.4).
> Port the code, not the header.

### 7.3 OKLab ⇄ sRGB (Björn Ottosson) — verbatim coefficients

```
lin(v) = v ≤ 0.04045 ? v/12.92 : ((v + 0.055)/1.055)^2.4
gam(v) = v ≤ 0.0031308 ? 12.92*v : 1.055*v^(1/2.4) − 0.055
```

**sRGB → OKLab** (input channels 0…1, gamma-encoded):

```
rl = lin(r); gl = lin(g); bl = lin(b)
l_ = cbrt(0.4122214708*rl + 0.5363325363*gl + 0.0514459929*bl)
m_ = cbrt(0.2119034982*rl + 0.6806995451*gl + 0.1073969566*bl)
s_ = cbrt(0.0883024619*rl + 0.2817188376*gl + 0.6299787005*bl)
L =  0.2104542553*l_ + 0.7936177850*m_ − 0.0040720468*s_
A =  1.9779984951*l_ − 2.4285922050*m_ + 0.4505937099*s_
B =  0.0259040371*l_ + 0.7827717662*m_ − 0.8086757660*s_
```

**OKLab → sRGB:**

```
l_ = L + 0.3963377774*A + 0.2158037573*B
m_ = L − 0.1055613458*A − 0.0638541728*B
s_ = L − 0.0894841775*A − 1.2914855480*B
Lc = l_³; Mc = m_³; Sc = s_³
r  =  4.0767416621*Lc − 3.3077115913*Mc + 0.2309699292*Sc
g  = −1.2684380046*Lc + 2.6097574011*Mc − 0.3413193965*Sc
b  = −0.0041960863*Lc − 0.7034186147*Mc + 1.7076147010*Sc
→ each: clamp(gam(x), 0, 1)
```

These two functions are also used **outside** the palette extractor and must be public in the port:

- `FranchiseDetailView.lightness(_:)` — OKLab L of a resolved tint, used for
  `heroIsDark = lightness < 0.34`, which multiplies the Detail hero bloom by 1.8.
- `DetailTint.quiet(_:)` (`DetailSupport.swift`) — a second, quieter form of an art colour, applied
  to Detail's card/tile grounds: chroma clamped to **≤ 0.045**, lightness held in **0.40…0.46**,
  then mixed **20 % toward `surfaceRaised`**. The tile fill composites `quiet` over the card ground
  at **0.35** opacity (`DetailTint.tileOverGround`). Its own comment marks it as "a LOCAL
  workaround: the same transform belongs at the end of `PaletteCache.resolve`" — an Android port
  may legitimately fold it in, but must then apply it only to card/tile grounds, not to washes.

### 7.4 `ArtAdaptiveGround` — the card ground

`base = tint ?? PaletteCache.fallback`. Layers bottom → top inside a `ZStack`:

| # | Layer | Exact value |
| --- | --- | --- |
| 1 | Flat base | `ThemeColor.surfaceFlat` (`#171719`, opaque) |
| 2 | Diagonal gradient | `LinearGradient([base @ 0.52·intensity, base @ 0.18·intensity], startPoint: .topLeading, endPoint: .bottomTrailing)` |
| 3 | Light source | `RadialGradient([base @ 0.30·intensity, .clear], center: UnitPoint(x: 0.16, y: 0.02), startRadius: 0, endRadius: 320)` |
| 4 | Veil | `Color.black.opacity(0.30)` — **not** scaled by `intensity` |

`intensity` defaults to **1**; "Drop it for a large hero where the colour would otherwise dominate."
`.animation(ThemeMotion.uiPoster, value: tint == nil)` — a 180 ms ease-out when the tint appears or
disappears.

Layer 3's purpose: "A light source, not a flat wash: without it a large ground is one dead
rectangle of colour, which is what a gradient-filled div looks like."

**The 0.30 veil is a corrected value** and the reasoning is the whole design of the card:

> **The veil is 30 %, not 44 %.** The spec's 44 % is a FLOOR to be raised until primary text
> clears 4.5:1 — but the derived colour is already clamped to OKLab L ≤ 0.38, so the composite
> landed at rgb(22,18,18) against a rgb(9,9,11) canvas: a 4 % luminance step, which is why the
> shipped Focus card read as a hole with an outline round it rather than as a lit object. At 30 %
> the same card composites near rgb(34,28,25) — still a deep, cinema-dark ground, `textPrimary`
> (#F4F1EC) still clears 12:1 on it, and the card finally has a body.

**Android:** `endRadius: 320` is in **points, not a fraction** — pass `320.dp.toPx()` to
`Brush.radialGradient(radius = …)`, and `center = Offset(0.16f * width, 0.02f * height)`.

### 7.5 `ArtBackdrop` — the ambient identity wash

> The ambient identity wash behind the top of a screen: the artwork itself, blurred past
> recognition, bleeding under the status bar and dissolving into the canvas.
>
> This is the single biggest thing the shipped build dropped. The original Detail, Library,
> Schedule and Search screens all opened on a warm, art-derived atmosphere; the rebuilt ones open
> on #09090B. Nothing else recovers that much perceived quality for as little structure — and it
> costs one static, already-cached image, drawn once, never animated, never touched on scroll.

**Parameters:** `url: String? = nil`, `tint: Color? = nil`, `height: CGFloat = 380`,
`intensity: Double = 1`. Every real call site passes `height: ThemeMetrics.rootWashHeight` (320)
and `intensity: ThemeMetrics.rootWashIntensity` (0.4); the 380 default is not used in production.
Screens with no artwork pass `tint: ThemeColor.accent` explicitly (Library root, Schedule).

**State:** `@State resolvedTint: Color?`, filled by `.task(id: url)`:

```swift
resolvedTint = nil
let color = await PaletteCache.shared.resolveIfAvailable(url: url, maxPixel: 320)
guard !Task.isCancelled else { return }
resolvedTint = color
```

**Derived:**

```
base       = tint ?? resolvedTint ?? ThemeColor.ambientBackdropFallback   // #432D21
artSettled = (resolvedTint != nil)
baseTop    = artSettled ? 0.60 * intensity : max(0.60 * intensity, 0.55)
baseMid    = artSettled ? 0.10 * intensity : max(0.10 * intensity, 0.12)
```

At the production `intensity = 0.4`: **before** the palette lands, `baseTop = 0.55`,
`baseMid = 0.12`; **after**, `baseTop = 0.24`, `baseMid = 0.04`. That floor is the bug fix:

> `ambientBackdropFallback` was made "visibly warmer than canvas" for exactly this moment — but
> that fix was applied at Detail's intensity 1. At a list root's 0.4 the same ember composites to
> ~rgb(38,36,32) on device: the status band reads BLACK for the whole first load, then jumps to
> twice the luminance when the art decodes (user, 30 Aug — "black, then it becomes flush"). Until
> the art is actually contributing, the base gradient holds a floor independent of `intensity`, so
> the wash looks like the wash from frame one; the art then arrives as a hue shift, not a light
> switching on.

**Layers**, in a `ZStack(alignment: .top)`:

| # | Layer | Exact value |
| --- | --- | --- |
| 1 | Blurred art (only when `url` is non-nil and non-empty) | `RemoteImageView(url:, contentMode: .fill, maxPixel: 320, placeholderHidden: true)` → `.frame(maxWidth: .infinity)` → `.frame(height: height)` → `.clipped()` → `.blur(radius: 56, opaque: true)` → `.opacity(0.70 * intensity)` |
| 2 | Base wash | `LinearGradient([base @ baseTop, base @ baseMid, .clear], .top → .bottom)` (three evenly spaced stops: 0, 0.5, 1) |
| 3 | Brand breath | `LinearGradient([ThemeColor.accent @ (0.07 * intensity), .clear], .top → .bottom)` |
| 4 | Handover to canvas | `LinearGradient(stops: [.clear @ 0.0, ThemeColor.canvas @ 0.55 at location 0.55, ThemeColor.canvas @ 1.0 at location 1.0], .top → .bottom)` |

Container: `.frame(height: height)`, `.frame(maxWidth: .infinity)`, `.clipped()`,
`.animation(ThemeMotion.uiGentle, value: resolvedTint)`, `.allowsHitTesting(false)`,
`.accessibilityHidden(true)`.

Three notes the port must keep:

- **The art is centre-cropped BEFORE the blur** (`contentMode: .fill` + `clipped()` + a fixed
  frame). "Blurring a view whose art has not been made to fill its frame samples whatever corner
  the image happened to land in — which is why Profile drew no image at all — and it is why the
  wash lost its warmth even where an image was present."
- **No `.saturation()` pass.** "the tint clamp already holds chroma in a narrow band, so
  desaturating on top of it is subtracting the one thing the wash is for."
- Layer 4 "must reach FULL canvas well before the content that sits over it, or the first section
  looks like it is floating on a stain."
- The floor relaxation and the fallback → palette hue handover ride **one** `uiGentle` fade — "the
  snap between them was half of the 'black, then flush' jump."

**Android:** `blur(radius: 56, opaque: true)` — `opaque: true` means edge pixels are clamped rather
than sampled as transparent, i.e. `Shader.TileMode.CLAMP`. Use
`Modifier.graphicsLayer { renderEffect = BlurEffect(56f.dp.toPx(), 56f.dp.toPx(), TileMode.Clamp) }`
(API 31+). Below API 31, pre-blur on a downscaled bitmap (`RenderScript` is deprecated; use a
box-blur on a ⅛-scale bitmap, upscaled) or fall back to *no art layer at all* and let the base wash
carry it — the gradient alone is a legal rendering (it is exactly what the pre-art frame draws).
Difficulty: moderate at 31+, moderate-with-compromise below.

---

## 8. The brand glyph — `PreviouslyMark`

> The Previously. brand mark: a saved-place ribbon with a single progress point.
> Keep this geometry as the source of truth for every in-app use of the identity.

### 8.1 API

```swift
PreviouslyMark(width: CGFloat,
               detail: Detail = .progress,     // .progress | .none
               progress: CGFloat = 0,          // 0…1, clamped
               finish: Finish = .flat)         // .flat | .hero
```

> `.flat` is the mark at UI scale (wordmark, sign-in). `.hero` adds the material pass the
> splash needs at ~200pt — rim light, notch shading, a carved slot and an ember dot —
> where the flat fills read as plastic. Same geometry either way.

Call sites: `Wordmark` (width 13, `.progress`; colophon: width 11, `.none`), `SignInView`
(width 58, defaults), the identity avatar disc (`width: diameter * 0.34`, `.none`), `SplashView`
(width = `comp * 0.49`, animated `progress`, `.hero`). The whole view is
`.accessibilityHidden(true)`.

### 8.2 Geometry — all derived from `width` (`w`)

| Quantity | Formula | At w = 13 | At w = 58 |
| --- | --- | --- | --- |
| `height` | `w * 1.58` | 20.54 | 91.64 |
| `slotWidth` | `w * 0.56` | 7.28 | 32.48 |
| `slotHeight` | `w * 0.12` | 1.56 | 6.96 |
| dot diameter | `w * 0.10` | 1.30 | 5.80 |
| dot glow blur radius | `w * 0.035` | 0.455 | 2.03 |
| hero rim stroke width | `max(0.8, w * 0.004)` | 0.8 | 0.8 |
| hero slot stroke width | `slotHeight * 0.07` | 0.109 | 0.487 |
| hero dot gradient end radius | `w * 0.055` | 0.715 | 3.19 |
| hero rim-light radial end radius | `w * 0.95` | 12.35 | 55.1 |

Slot and dot both sit at **`offset(y: -height * 0.24)`** relative to the frame's centre — i.e. 24 %
of the mark's height above centre.

Dot horizontal position (this is the only animated value):

```
x = (-slotWidth * 0.32) + (slotWidth * 0.64 * clamp(progress, 0, 1))
```

so at `progress = 0` the dot is at `−0.32·slotWidth` (left end of its travel) and at `1` at
`+0.32·slotWidth` (right end). Travel span = `0.64 · slotWidth`.

**`BookmarkShape.path(in rect:)`** — the ribbon. Only the **top** two corners are rounded; the
bottom is a V-notch cut *upward* into the shape:

```
radius     = rect.width  * 0.17
notchApex  = rect.height * 0.76
edgeBottom = rect.height * 0.96

move  (radius, 0)
line  (maxX − radius, 0)
quad  → (maxX, radius),  control (maxX, 0)
line  (maxX, edgeBottom)
line  (midX, notchApex)          ← the saved-place notch apex, ABOVE the bottom edge
line  (0, edgeBottom)
line  (0, radius)
quad  → (radius, 0),     control (0, 0)
close
```

Note that the shape's bounding rect is the full `w × 1.58w` frame but the ribbon's drawn extent
stops at `0.96 · height`; the notch apex at `0.76 · height` produces a chevron 0.20·height deep.

### 8.3 Fills

**Body (both finishes):**
`LinearGradient([#FFD6A0, ThemeColor.accent (#F0A24E), #C9702E], startPoint: .topLeading, endPoint: .bottomTrailing)`.

**`.hero` adds three passes over the same shape** ("A single soft light from the upper left, and
depth falling into the notch"):

| Pass | Value |
| --- | --- |
| Rim light | `RadialGradient([white @ 0.16, .clear], center: UnitPoint(0.28, 0.10), startRadius: 0, endRadius: w * 0.95)` |
| Notch depth | `LinearGradient(stops: [.clear @ 0, .clear @ 0.62, #7A3E10 @ 0.30 at 1], .top → .bottom)` |
| Edge stroke | `stroke(LinearGradient([white @ 0.35, white @ 0.06, .clear], .top → .bottom), lineWidth: max(0.8, w * 0.004))` |

**Slot** (`detail == .progress` only), a `Capsule` of `slotWidth × slotHeight`:

| Finish | Fill | Overlay |
| --- | --- | --- |
| `.flat` | `ThemeColor.canvas` (`#09090B`) | none |
| `.hero` | `LinearGradient([#140E08, #2B2015], .top → .bottom)` | `Capsule().stroke(LinearGradient([black @ 0.35, white @ 0.14], .top → .bottom), lineWidth: slotHeight * 0.07)` — "Carved, not printed: dark upper lip, light catching the lower one." |

**Dot**, a `Circle` of `w * 0.10`:

| Finish | Fill | Shadow |
| --- | --- | --- |
| `.flat` | `#FFF0DA` | `.clear` (radius `w * 0.035`, no visible effect) |
| `.hero` | `RadialGradient([#FFF6E4, #F0AC5E], center: .center, startRadius: 0, endRadius: w * 0.055)` — "An ember, not a toggle knob — warm core falling to amber at the edge." | `#F6BD7D @ 0.55`, radius `w * 0.035` |

### 8.4 The lockup — `Wordmark`

| Property | Normal | `colophon: true` |
| --- | --- | --- |
| HStack spacing | `ThemeSpace.x2` (8) | 7 |
| Mark width | 13 | 11 |
| Mark detail | `.progress` | `.none` |
| Text | `"Previously."` | same |
| Text ink | `textPrimary` | `textSecondary` |
| Type | `ThemeType.brandWordmark` (Outfit SemiBold 20, tracking −0.30) | same |
| Shadow | `.art` | `.none` |

Accessibility: `.accessibilityElement(children: .ignore)` + `.accessibilityLabel("Previously")`
(no full stop in the spoken label).

> The full stop is TEXT ink, not accent, everywhere inside the app — the bookmark mark beside it
> already carries the brand's amber. The splash and sign-in keep their amber dot; there the
> wordmark IS the subject.

### 8.5 The splash derives its anchors from this geometry

`SplashView` computes the dot's position from `PreviouslyMark`'s formulas rather than measuring it,
and this is the *reason* the geometry above is the source of truth:

```swift
// mark width 0.49·comp centered at (0.5, 0.48); dot rest offset +slotWidth·0.32, slot lift −height·0.24
private static let dotX = 0.5 + 0.49 * 0.56 * 0.32     // ≈ 0.5878
private static let dotY = 0.48 - 0.49 * 1.58 * 0.24    // ≈ 0.2942
```

> The mock's hand-measured 0.424 was ~30pt left of where the dot actually lands.

If a port changes any factor in §8.2, these two constants change with it.

**Android:** the mark is a pure vector; implement `BookmarkShape` as a Compose `Shape` returning a
`Path` with the same commands (`quadraticBezierTo` for the two corners) and draw the gradients with
`Brush.linearGradient(start = Offset.Zero, end = Offset(w, h))` for `.topLeading → .bottomTrailing`.
Difficulty: easy. An SVG/`VectorDrawable` export is **not** sufficient because the dot's `x` is
animated and the hero finish is a separate layer stack.

---

## 9. Global app configuration that belongs to this layer

| Setting | Value | Where |
| --- | --- | --- |
| Colour scheme | Dark, forced | `UIUserInterfaceStyle: Dark` (Info.plist + `project.yml`) and `.preferredColorScheme(.dark)` |
| Orientation | Portrait only | `UISupportedInterfaceOrientations` |
| Display name | `Previously.` | `CFBundleDisplayName` |
| ProMotion | 120 Hz allowed | `CADisableMinimumFrameDurationOnPhone: true` — the splash's `TimelineView(.animation)` needs it |
| Launch background | asset colour `LaunchBackground` = **`#000000`** (true black, not `canvas`) | `UILaunchScreen.UIColorName`; the splash's base is true black "for OLED — pixels stay off, seamless with the launch frame" |
| `AccentColor` asset | sRGB (0.941, 0.635, 0.306) = **`#F0A24E`** | `Assets.xcassets/AccentColor.colorset` — identical to `ThemeColor.accent`; used by the system (widgets, share sheets), not by app code |
| Dynamic Type ceiling | `accessibility2` | root scene `.dynamicTypeSize(...)` |
| Root tint | `ThemeColor.interactive` | root scene `.tint(...)` |
| Default font | `Outfit-Regular 17 relativeTo .body` | root scene `.font(...)` |
| Bundled fonts | 5 Outfit `.ttf` | `UIAppFonts` |

---

## 10. Known dead / stale items (do not port; flagged so the port is not confused)

| Item | Status |
| --- | --- |
| `ThemeColor.information`, `.separator`, `.focusRing`, `.backdropFade` | Declared, **zero** call sites |
| `ThemeMotion.uiLiveBreath` | Declared, **zero** call sites ("Wordmark live indicator" — the indicator no longer exists) |
| `View.scaledFont(_:weight:monospacedDigit:relativeTo:)` (`ScaledFont.swift`) | **Zero** call sites; superseded by `ThemeType` + `.type(_:)` |
| `ThemeType` assignment comment: "shelfTitle Outfit Medium **15**" | Code declares **14**. The code wins |
| `Palette.swift` file-header comment: "clamp L 0.24…0.38, C 0.04…0.12 … black overlay 44 %" | Superseded. Code: **L 0.30…0.44, C 0.075…0.145, overlay 0.30** |
| `ThemeMetrics.topChromeRamp`, `.inlineBarHeight` | Never referenced directly; only via `topChromeHeight` / `inlineBarBottom` |
| `PosterSize.libraryHero` | Still declared; the Library cover-flow spotlight it sized "is gone" per CLAUDE.md's 3 Sep cohesion note. Verify before porting |
| `ZoomTransition.swift` / `zoomSource` registrations | `.zoom` navigation transition was tried (2 Sep) and retired (3 Sep). Registrations remain but nothing consumes them |

---

## 11. Android reproduction risk — consolidated

| Item | Risk | Notes |
| --- | --- | --- |
| `.ultraThinMaterial` chrome bands | **hard** below API 31 | No live backdrop blur. Take the app's own Reduce-Transparency path (opaque `chromeVeil`, no material) — it is already a shipping rendering, so this is a legal, not a degraded, result. API 31+: `RenderEffect.createBlurEffect(σ, σ, CLAMP)` on the content node, calibrated against reference screenshots. |
| iOS Liquid Glass (tab pill, toolbar capsules, search scope bar) | **blocker** | Everything iOS 26-specific is already routed through `GlassHelpers.swift` with an iOS 18 fallback. Port the **fallback** (`.ultraThinMaterial`/opaque), not the glass. |
| `.continuous` (squircle) corners | **moderate** | Compose `RoundedCornerShape` is a circular arc. Visible at radius 22 (`ThemeRadius.card`) and 24 (`focusCard`). Needs a custom superellipse `Shape`. |
| `ShadowToken` (colour + radius + Y, no elevation) | **moderate** | `Modifier.shadow` cannot express it. Use `setShadowLayer` in `drawBehind`; calibrate radius by eye. |
| `UINotificationFeedbackGenerator` success/warning/error | **moderate** | No Android equivalent pattern; must be hand-authored `VibrationEffect` compositions and tuned by feel. |
| `UIImpactFeedbackGenerator(intensity:)` | **moderate** | `VibrationEffect.Composition` primitives with a scale (API 30+), guarded by `arePrimitivesSupported`; older devices get `createOneShot` approximations. |
| Reduce Transparency | **moderate** | No such Android setting. Map to "no blur capability" and/or an in-app toggle. |
| Dynamic Type `relativeTo:` ramps | **moderate** | Android has a single `fontScale`, not per-style ramps. Sizes in `sp`, clamp scale to ~1.6× to mirror the `accessibility2` ceiling. |
| Non-scaling `tracking` | **moderate** | Compose `letterSpacing` in `sp` scales; convert dp→sp at the current density instead. |
| SF Pro | **moderate** | Substitute Roboto at identical sizes/weights. The two-family contrast is preserved; exact metrics are not. |
| SF Symbols (glyphs referenced by tokens: `photo` placeholder, `plus`, `arrow.up.right`, chevrons, the 44-pt tertiary state symbol) | **moderate** | Map to Material Symbols; a handful (e.g. `arrow.up.right`) need a custom vector. Optical sizing and baseline alignment differ — check every icon-beside-text pairing. |
| `.blur(radius: 56, opaque: true)` on the wash | **moderate** | `BlurEffect(56.dp, 56.dp, TileMode.Clamp)` at API 31+; below that, pre-blur a ⅛-scale bitmap or drop the art layer and keep the base gradient. |
| OKLab palette extraction | **easy** | Pure arithmetic; port verbatim. **Do not** substitute `androidx.palette`. |
| `PreviouslyMark` geometry | **easy** | Pure vector maths; port the `Path` commands. |
| Spring curves | **easy** | `stiffness = (2π/response)²`, `dampingRatio = dampingFraction`. Values pre-computed in §5.1. |
| Cubic-bezier easings | **easy** | Declare beziers explicitly; do **not** use `FastOutSlowInEasing` as a stand-in for `.easeInOut`. |
| Live Activities / Dynamic Island | **blocker** | Out of this area, but noted: no Android equivalent. Closest is an ongoing notification with `setOngoing` + a custom `RemoteViews` layout, or (API 34+) a foreground-service "Live Update"-style notification. |
| `topSafeInset` / `windowHeight` read from the key window | **easy** | `WindowInsets.statusBars` / `LocalConfiguration`. Note the iOS code caches only *real* measurements (never the 59/852 pre-window defaults) — reproduce that guard or read lazily inside composition. |
