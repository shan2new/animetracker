# Typography, icon parity, and dark-only theming

**Status:** research / decision note. Written **2026-09-04**. Every version, API signature and
numeric table below was checked against primary sources on that date (links + dates in §10). Two
tables were **measured on this machine** rather than quoted: the iOS Dynamic Type ladder (run on the
`Previously QA 14 Pro` simulator, iOS 27 SDK) and the AOSP non-linear font-scale curve (read out of
`FontScaleConverterFactory.java` on `androidx-main`). Those are the load-bearing numbers, so they
are first-hand.

Target stack, inherited from `research/compose-architecture.md` and
`research/minsdk-decision.md` (do not re-litigate here):
Kotlin 2.4.10 · AGP 9.4.0 / Gradle 9.6.1 · Compose BOM 2026.08.00 (ui 1.12.0, material3 1.4.0) ·
**minSdk 26** (product-owner decision 2026-09-04, superseding the 31 in `compose-architecture.md`) ·
compileSdk 37 · targetSdk 36.

**What the 26 floor costs this topic: almost nothing, but check every line.** Variable fonts land at
*exactly* API 26, so Outfit works everywhere with zero margin and zero gating. Compose ships its own
copy of Android 14's non-linear font-scale converter, so the type ramp behaves identically on an
API 26 device and an API 36 one (§4.1). What does need version-qualifying is a short, specific list
of system-bar theme attributes (§6.2, §7.2) — not the type or icon system.

---

## 1. Recommendation up front

| Question | Decision | One-line reason |
|---|---|---|
| **Outfit delivery** | **Bundle `Outfit[wght].ttf`** (the Google Fonts variable file) in `res/font/`, one file, and declare five `Font(…)` entries at wght 300/400/500/600/700 with **explicit `variationSettings`** | minSdk 26 **is** the variable-font floor — supported on every device the app runs on, no `Build.VERSION` gate, no static fallback family; one ~100 KB file replaces five statics; downloadable fonts **cannot** serve variable fonts and cost a first-frame reflow |
| **The `Font()` overload trap** | Always pass `variationSettings = FontVariation.Settings(FontVariation.weight(n))` | The 4-arg `Font(resId, weight, style, loadingStrategy)` overload hard-codes `FontVariation.Settings()` — **empty** — so the `wght` axis is never applied and Compose fake-bolds instead (§2.2) |
| **Second face ("SF Pro annotates")** | `FontFamily.Default` (Roboto in practice) | Roboto is a neo-grotesque like SF Pro, so the Outfit-speaks / grotesque-annotates pairing survives the port at zero bytes. Flagged as open question Q1 |
| **Typography strategy** | **Both**: a full 15-slot M3 `Typography` mapped to Outfit *and* a separate `PreviouslyType` CompositionLocal carrying the 24 real tokens | The M3 object stops any material3 component leaking Roboto; the CompositionLocal is what screens actually call. Screens never read `MaterialTheme.typography` |
| **Tracking** | `letterSpacing` in **`.em`**, converted from iOS points (`em = pt ÷ size`) | Identical at fontScale 1.0 and stays proportional as text scales; `.sp` over-tightens under the non-linear curve because letter-spacing values sit far below the curve's 8 sp floor |
| **Dynamic Type** | Put the **iOS point size straight into `sp`**. Ship **no font-scale cap** | At fontScale 1.0 sp == dp, so the default screen is pixel-identical to iOS. At Android's 2.0 maximum, every token lands **7–14 % smaller** than the same token at the iOS cap of `.accessibility2`, so the port is already more conservative than iOS. There is no clean cap API and Google's guidance is not to add one (§4) |
| **Icon set** | **Material Symbols Rounded**, as **static VectorDrawable XML copied from `google/material-design-icons`**, `wght 400` (500 for the small semibold glyphs), **`GRAD −25`**, `opsz 24`, FILL per the table | Rounded matches SF Symbols' rounded terminals; **−25 grade is Google's own prescription for a light icon on a dark ground**, which is every icon in this app; static XML = no dependency, no font, exact glyph, `Icon()` tinting still works |
| **Icon library** | **None.** Do not add `material-icons-extended` | The artifact is frozen at **1.7.8** and is not published in any BOM after Compose 1.8; it is also the wrong (old) icon set |
| **Dark-only** | `MaterialTheme(colorScheme = PreviouslyDarkScheme)` with **no `isSystemInDarkTheme()` and no `dynamic*ColorScheme`**; **no `values-night/`**; app theme `android:isLightTheme="false"` + `forceDarkAllowed=false`; `enableEdgeToEdge(SystemBarStyle.dark(TRANSPARENT), SystemBarStyle.dark(TRANSPARENT))` | Omitting `values-night/` is the whole trick — one `values/` folder is already unconditional. `isLightTheme="false"` additionally makes the **trailer WebView** report `prefers-color-scheme: dark` to YouTube, which is the Android answer to the iOS `VideoSheet` |
| **Edge-to-edge** | Mandatory. Call `enableEdgeToEdge()`, take insets manually with `Modifier.windowInsetsPadding(WindowInsets.safeDrawing)`, and set `android:windowSoftInputMode="adjustResize"` | Apps targeting API 36 cannot opt out — `windowOptOutEdgeToEdgeEnforcement` is deprecated and disabled on Android 16 devices. The iOS design is already full-bleed art under translucent chrome, so this is a match, not a migration |

**One thing to correct in the brief:** the app uses **24 SF Symbol string literals** (`systemName: "…"`)
— exactly the list handed to this task — but **44 distinct symbols in total**. The other 20 arrive
as stored properties and enum payloads, which is where all of the state-screen iconography lives
(`EmptyState`, `InlineNotice`, `SyncBanner`, Profile's settings rows). Verified:

```
grep -rhoE 'systemName: "[a-z0-9.]+"' ios/Sources ios/Widgets | sort -u | wc -l   →  24
```

§5.3 maps the 24 in full detail and §5.4 the remaining 20; do not ship having mapped only 24.

---

## 2. Bundling Outfit

### 2.1 What the iOS app actually ships

`ios/Resources/Fonts/` holds **five static TTFs** — `Outfit-{Light,Regular,Medium,SemiBold,Bold}.ttf`,
~48 KB each, ~240 KB total — registered through `UIAppFonts` and resolved by
`AppFont.name(_ weight:)` (`ios/Sources/DesignSystem/AppFont.swift`), which snaps ultraLight/thin →
Light, heavy/black → Bold. It is **not** the variable font, despite the brief's wording.

Upstream, Google Fonts ships Outfit as a **single variable file** — `ofl/outfit/Outfit[wght].ttf`,
one `wght` axis 100–900, nine named instances, **SIL OFL 1.1**, by Rodrigo Fuenzalida. There are no
static instances in the Google Fonts repo — the five files in `ios/Resources/Fonts/` were instanced
from it.

**Take the variable file.** One `res/font/outfit.ttf` covers the five cuts the design uses and the
four it does not, and Android has no `UIAppFonts`-style registration cost.

### 2.2 The overload trap — read this before writing the FontFamily

`androidx.compose.ui.text.font.Font` has **two live resource-id overloads** and they differ in the
one way that matters:

```kotlin
// androidx-main · compose/ui/ui-text/src/commonMain/.../font/Font.kt  (read 2026-09-04)

@Stable
public fun Font(
    resId: Int,
    weight: FontWeight = FontWeight.Normal,
    style: FontStyle = FontStyle.Normal,
    loadingStrategy: FontLoadingStrategy = FontLoadingStrategy.Blocking,
): Font = ResourceFont(resId, weight, style, FontVariation.Settings(), loadingStrategy)
//                                            ^^^^^^^^^^^^^^^^^^^^^^^^ EMPTY

public fun Font(
    resId: Int,
    weight: FontWeight = FontWeight.Normal,
    style: FontStyle = FontStyle.Normal,
    loadingStrategy: FontLoadingStrategy = FontLoadingStrategy.Blocking,
    variationSettings: FontVariation.Settings = FontVariation.Settings(weight, style),
): Font = ResourceFont(resId, weight, style, variationSettings, loadingStrategy)
```

Kotlin resolves `Font(R.font.outfit, FontWeight.Bold)` to the **first** one (fewer parameters wins
when both are applicable through defaults). With a variable font that means the `wght` axis is
never set: every weight loads the file's default instance, and `FontSynthesis` then *fake-bolds* it
— a smeared, subtly wrong Bold that looks "nearly right", which is the worst failure mode. Note the
asymmetry: the *asset*/*file*/*fileDescriptor* overloads in `AndroidFont.android.kt` **do** default
`variationSettings` to `FontVariation.Settings(weight, style)`. Only the resource-id 4-arg one does
not.

So: name the argument, every time.

### 2.3 The FontFamily

```kotlin
// ui/theme/Fonts.kt
package app.previously.ui.theme

import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontVariation
import androidx.compose.ui.text.font.FontWeight
import app.previously.R

/**
 * Outfit, the brand face. ONE variable file (`res/font/outfit.ttf` = Outfit[wght].ttf from
 * google/fonts, OFL 1.1). Five instances, matching the five cuts iOS bundles; AppFont.swift's
 * snapping rules (thin/light -> 300, heavy/black -> 700) fall out of FontFamily resolution for free.
 *
 * `variationSettings` is passed EXPLICITLY. The 4-arg Font(resId, weight, style, loadingStrategy)
 * overload hard-codes an EMPTY FontVariation.Settings, so omitting it silently disables the wght
 * axis and lets FontSynthesis fake-bold instead. See docs/android-port/research/typography-icons.md §2.2.
 */
private fun outfit(weight: Int, w: FontWeight) =
    Font(
        resId = R.font.outfit,
        weight = w,
        variationSettings = FontVariation.Settings(FontVariation.weight(weight)),
    )

val Outfit = FontFamily(
    outfit(300, FontWeight.Light),
    outfit(400, FontWeight.Normal),
    outfit(500, FontWeight.Medium),
    outfit(600, FontWeight.SemiBold),
    outfit(700, FontWeight.Bold),
)

/** "SF Pro annotates" -> the platform grotesque. See open question Q1. */
val Annotating = FontFamily.Default
```

**No `Build.VERSION` gate, and no static fallback family.** Google's own sample wraps the variable
`FontFamily` in `if (SDK_INT >= Build.VERSION_CODES.O)` with a static fallback, because variable
fonts crash with `IllegalStateException` below API 26. `Build.VERSION_CODES.O` **is** 26, which is
this app's floor, so the branch is dead code here. Compose's own
`PlatformFontVariationSettings.android.kt` is `@RequiresApi(26)`-guarded internally and simply
always applies. Delete the gate if you copy the sample — but note there is **zero margin**: if the
floor ever moves down, the variable font is the first thing that breaks.

Filename rules for `res/font/`: **all lowercase, no special characters**, `.ttf` or `.otf`. So
`Outfit[wght].ttf` must be renamed — `outfit.ttf` — before it lands in the tree. Keep the upstream
`OFL.txt` next to it in `app/src/main/assets/licenses/` and surface it from Profile's colophon, the
same as the iOS build does.

### 2.4 Why not downloadable fonts

`androidx.compose.ui:ui-text-google-fonts` can pull Outfit from the Google Play Services font
provider with no bytes in the APK. Rejected, for three independent reasons:

1. **It cannot serve variable fonts at all** — Google's own doc lists this under "Caveats" and links
   the open bug (issuetracker 223262013). You would be back to five static requests.
2. **The download is asynchronous.** The first frame renders in the fallback face and reflows when
   the download lands. This app's first frame is a splash into a billboard hero — a reflow there is
   the single most visible place it could happen.
3. **It needs Play Services** and a live network. The iOS app deliberately opens on
   `library-cache.json` with no network; a font that needs one contradicts that.

Bundling costs ~100 KB in an app that already ships splash PNGs at three densities.

---

## 3. The type scale

### 3.1 Rule zero: Material's defaults are not this app's defaults

M3's `Typography` is 15 slots (`display/headline/title/body/label` × `Large/Medium/Small`) of Roboto
at Material's own sizes. **None of them is a token in this app.** But material3 components read them
— `Button` uses `labelLarge`, `AlertDialog` uses `headlineSmall`, `ModalBottomSheet` content
inherits `bodyLarge` via `LocalTextStyle`. So the M3 object is not optional; it is the **backstop**
that keeps a stray component from rendering Roboto next to Outfit.

Two objects, two jobs:

```kotlin
// ui/theme/Type.kt

/** BACKSTOP. Not a design token. Exists so no material3 component ever draws in Roboto. */
val PreviouslyMaterialTypography = Typography().let { d ->
    Typography(
        displayLarge   = d.displayLarge.copy(fontFamily = Outfit),
        displayMedium  = d.displayMedium.copy(fontFamily = Outfit),
        displaySmall   = d.displaySmall.copy(fontFamily = Outfit),
        headlineLarge  = d.headlineLarge.copy(fontFamily = Outfit),
        headlineMedium = d.headlineMedium.copy(fontFamily = Outfit),
        headlineSmall  = d.headlineSmall.copy(fontFamily = Outfit),
        titleLarge     = d.titleLarge.copy(fontFamily = Outfit),
        titleMedium    = d.titleMedium.copy(fontFamily = Outfit),
        titleSmall     = d.titleSmall.copy(fontFamily = Outfit),
        bodyLarge      = d.bodyLarge.copy(fontFamily = Outfit),
        bodyMedium     = d.bodyMedium.copy(fontFamily = Outfit),
        bodySmall      = d.bodySmall.copy(fontFamily = Outfit),
        labelLarge     = d.labelLarge.copy(fontFamily = Outfit),
        labelMedium    = d.labelMedium.copy(fontFamily = Outfit),
        labelSmall     = d.labelSmall.copy(fontFamily = Outfit),
    )
}
```

> **Version note.** material3 **1.5.0-alpha16 (25 Mar 2026)** added a `Typography` constructor
> taking a **default `FontFamily`** applied to every style, refined in **1.5.0-alpha19 (6 May 2026)**
> to merge only where a style has not set one. That would collapse the block above to one line —
> but 1.5.0 is **alpha-only** as of 26 Aug 2026 (`1.5.0-alpha27`) and stable is **1.4.0**. Write the
> 15-line `.copy` chain now; delete it the day 1.5.0 goes stable.

### 3.2 The real tokens

`ThemeType` is a `TypeToken(font:tracking:)` struct with an extension of context-assigned tokens.
The Compose shape is a data class + a CompositionLocal — deliberately **not** M3's `Typography`,
because the token names carry the design decisions (`heroTitle`, `cardFact`, `rowMetaLead`,
`listAction`) and a screen that reaches for `MaterialTheme.typography.titleLarge` has lost them.

```kotlin
// ui/theme/Type.kt

@Immutable
data class PreviouslyTypography(
    // Outfit SPEAKS — identity and every word the app says in its own voice.
    val brandWordmark: TextStyle,
    val displayXL: TextStyle,
    val displayL: TextStyle,
    val heroTitle: TextStyle,
    val showTitleL: TextStyle,
    val showTitleM: TextStyle,
    val sectionTitle: TextStyle,
    val body: TextStyle,
    val bodyEmphasis: TextStyle,
    val button: TextStyle,
    val callout: TextStyle,
    val cardFact: TextStyle,
    val heroMeta: TextStyle,
    val rowTitle: TextStyle,
    val shelfTitle: TextStyle,
    val listAction: TextStyle,
    // The grotesque ANNOTATES — dense metadata, eyebrows, numerals, the one paragraph.
    val metadata: TextStyle,
    val metadataEmphasis: TextStyle,
    val rowMeta: TextStyle,
    val rowMetaLead: TextStyle,
    val sectionLabel: TextStyle,   // EYEBROW ONLY. Draw with text.uppercase().
    val caption: TextStyle,
    val shelfCaption: TextStyle,
    val prose: TextStyle,
    val numberXL: TextStyle,
    val time: TextStyle,
)

private val Tight = PlatformTextStyle(includeFontPadding = false)

private fun outfitStyle(size: Int, weight: FontWeight, em: Float) = TextStyle(
    fontFamily = Outfit, fontWeight = weight,
    fontSize = size.sp, letterSpacing = em.em,
    lineHeight = TextUnit.Unspecified,   // font metrics, as SwiftUI does by default
    platformStyle = Tight,
)

private fun annotStyle(size: Int, weight: FontWeight = FontWeight.Normal, em: Float = 0f) = TextStyle(
    fontFamily = Annotating, fontWeight = weight,
    fontSize = size.sp, letterSpacing = em.em,
    lineHeight = TextUnit.Unspecified,
    platformStyle = Tight,
)

val PreviouslyType = PreviouslyTypography(
    brandWordmark    = outfitStyle(20, FontWeight.SemiBold, -0.0150f),
    displayXL        = outfitStyle(34, FontWeight.Bold,     -0.0235f),
    displayL         = outfitStyle(28, FontWeight.Bold,     -0.0214f),
    heroTitle        = outfitStyle(28, FontWeight.Bold,     -0.0196f),
    showTitleL       = outfitStyle(22, FontWeight.SemiBold, -0.0159f),
    showTitleM       = outfitStyle(17, FontWeight.SemiBold, -0.0118f),
    sectionTitle     = outfitStyle(20, FontWeight.SemiBold, -0.0150f),
    body             = outfitStyle(17, FontWeight.Normal,   -0.0059f),
    bodyEmphasis     = outfitStyle(17, FontWeight.SemiBold, -0.0118f),
    button           = outfitStyle(16, FontWeight.SemiBold, -0.0094f),
    callout          = outfitStyle(16, FontWeight.Normal,   -0.0063f),
    cardFact         = outfitStyle(15, FontWeight.SemiBold, -0.0067f),
    heroMeta         = outfitStyle(15, FontWeight.Normal,   -0.0033f),
    rowTitle         = outfitStyle(17, FontWeight.SemiBold, -0.0118f),
    shelfTitle       = outfitStyle(14, FontWeight.Medium,   -0.0071f),
    listAction       = outfitStyle(13, FontWeight.SemiBold,  0f),

    metadata         = annotStyle(13),
    metadataEmphasis = annotStyle(13, FontWeight.SemiBold),
    rowMeta          = annotStyle(13),
    rowMetaLead      = annotStyle(13, FontWeight.SemiBold),
    sectionLabel     = annotStyle(11, FontWeight.SemiBold, em = 0.0909f),  // iOS tracking +1.0 pt
    caption          = annotStyle(11),
    shelfCaption     = annotStyle(12, FontWeight.Medium),
    prose            = annotStyle(15).copy(lineHeight = 25.sp),            // see §3.4
    numberXL         = annotStyle(34, FontWeight.Bold, -0.0147f)
                          .copy(fontFeatureSettings = "tnum"),
    time             = annotStyle(15, FontWeight.SemiBold)
                          .copy(fontFeatureSettings = "tnum"),
)

val LocalPreviouslyType = staticCompositionLocalOf { PreviouslyType }
```

Sizes come straight from `ThemeTokens.swift`; the SF-based tokens use iOS's text-style point sizes
at the default content size, measured on the simulator (§3.3): footnote 13, caption2 11, caption 12,
subheadline 15, largeTitle 34.

### 3.3 Tracking → `letterSpacing`, and why `.em`

SwiftUI's `.tracking(_:)` is an **absolute point value** that does not change with the text size.
Compose's `letterSpacing` is a `TextUnit` and accepts either `.sp` or `.em`.

- `.sp` is the literal translation and is **exactly right at fontScale 1.0**. It goes wrong above
  that: the non-linear curve's lookup table starts at 8 sp and extrapolates linearly below it, so
  `-0.30.sp` at fontScale 2.0 becomes roughly `-0.60` device-independent units, doubling the
  tightening on text that has only grown 1.7×. The 34 sp display then tracks tighter than it was
  designed to at exactly the size where it is most fragile.
- `.em` is proportional by construction, identical to `.sp` at 1.0, and preserves the *intent* the
  token comment states — "tracking follows the size ramp: tighter as the cut gets bigger, neutral
  by 13 pt".

Conversion is `em = tracking_pt ÷ size_pt`:

| Token | sp | iOS tracking (pt) | `letterSpacing` |
|---|---:|---:|---|
| `brandWordmark` | 20 | −0.30 | `(-0.0150f).em` |
| `displayXL` | 34 | −0.80 | `(-0.0235f).em` |
| `displayL` | 28 | −0.60 | `(-0.0214f).em` |
| `heroTitle` | 28 | −0.55 | `(-0.0196f).em` |
| `showTitleL` | 22 | −0.35 | `(-0.0159f).em` |
| `sectionTitle` | 20 | −0.30 | `(-0.0150f).em` |
| `showTitleM` / `bodyEmphasis` / `rowTitle` | 17 | −0.20 | `(-0.0118f).em` |
| `body` | 17 | −0.10 | `(-0.0059f).em` |
| `button` | 16 | −0.15 | `(-0.0094f).em` |
| `callout` | 16 | −0.10 | `(-0.0063f).em` |
| `cardFact` | 15 | −0.10 | `(-0.0067f).em` |
| `heroMeta` | 15 | −0.05 | `(-0.0033f).em` |
| `shelfTitle` | 14 | −0.10 | `(-0.0071f).em` |
| `listAction` | 13 | 0 | `0f.em` |
| `sectionLabel` | 11 | **+1.00** | `0.0909f.em` |

### 3.4 Line height, font padding, and the one paragraph

- **`includeFontPadding` has been `false` by default since Compose ui 1.6.0**, which is what you
  want — it is the setting that makes Compose text box the way iOS does. Set it explicitly anyway
  (`PlatformTextStyle(includeFontPadding = false)`), because it is one line and it makes the
  intent survive a future default flip.
- **Leave `lineHeight = TextUnit.Unspecified`** on every token except `prose`. Unspecified means
  "use the font's own ascent + descent + leading", which is exactly what SwiftUI does for a `Text`
  with no `.lineSpacing`. Setting M3's line heights instead would open every row in the app.
- **`prose` is the exception.** iOS draws it as `.system(.subheadline)` with `.lineSpacing(5)` at
  the call site. SwiftUI's `lineSpacing` is the gap *between* lines; Compose's `lineHeight` is the
  *total*. So `lineHeight = fontMetricLineHeight + 5.sp`. Roboto's default line height at 15 sp is
  ≈ 20 sp, hence `25.sp` above. **Measure this once on device and correct the constant** — it is
  the only number in §3.2 that is derived rather than transcribed.
- If a paragraph reads bottom-heavy after that, add
  `lineHeightStyle = LineHeightStyle(alignment = Alignment.Center, trim = Trim.None)`. `Trim`
  requires `includeFontPadding = false`, which is already true.

### 3.5 Tabular figures

iOS `numberXL` and `time` use `.monospacedDigit()`. The Compose equivalent is the OpenType feature,
not a different family:

```kotlin
TextStyle(fontFeatureSettings = "tnum")
```

Roboto ships `tnum`. Outfit does **not** — and the iOS comment says so explicitly ("Outfit has no
tabular figures; timers would jiggle"), which is precisely why those two tokens are in the
annotating face on both platforms. Do not "fix" this by moving the countdown to Outfit.

---

## 4. Dynamic Type equivalence

### 4.1 The two curves, measured

iOS, measured on the simulator (`UIFont.preferredFont(forTextStyle:compatibleWith:)`, iOS 27 SDK,
2026-09-04) — the ladder `.custom(size:relativeTo:)` and `@ScaledMetric` multiply against:

| Style | L | xL | xxL | xxxL | AX1 | AX2 | AX3 | AX4 | AX5 |
|---|--:|--:|--:|--:|--:|--:|--:|--:|--:|
| largeTitle | 34 | 36 | 38 | 40 | 44 | 48 | 52 | 56 | 60 |
| title | 28 | 30 | 32 | 34 | 38 | 43 | 48 | 53 | 58 |
| title2 | 22 | 24 | 26 | 28 | 34 | 39 | 44 | 50 | 56 |
| title3 | 20 | 22 | 24 | 26 | 31 | 37 | 43 | 49 | 55 |
| headline / body | 17 | 19 | 21 | 23 | 28 | 33 | 40 | 47 | 53 |
| callout | 16 | 18 | 20 | 22 | 26 | 32 | 38 | 44 | 51 |
| subheadline | 15 | 17 | 19 | 21 | 25 | 30 | 36 | 42 | 49 |
| footnote | 13 | 15 | 17 | 19 | 23 | 27 | 33 | 38 | 44 |
| caption | 12 | 14 | 16 | 18 | 22 | 26 | 32 | 37 | 43 |
| caption2 | 11 | 13 | 15 | 17 | 20 | 24 | 29 | 34 | 40 |

`AniTrackApp.swift` clamps the app at `.dynamicTypeSize(...DynamicTypeSize.accessibility2)` — the
**AX2** column.

Android — and here is the finding that the **minSdk 26** floor makes load-bearing:

> **Compose applies Android 14's non-linear curve on every API level, including API 26.**
> `androidx.compose.ui.unit.FontScaling.TextUnit.toDp()` does not call the platform's
> `TypedValue.deriveDimension`; it calls **Compose's own vendored copy** of the converter at
> `androidx.compose.ui.unit.fontscaling.FontScaleConverterFactory`, whose lookup table is
> byte-identical to AOSP's for the anchors below. Verified by reading both files on `androidx-main`,
> 2026-09-04.

So there is **no pre-14 / post-14 fork in this app's type ramp**. An API 26 device and an API 36
device at the same `fontScale` render the same sizes. (Views-based UI would fork; nothing here is
Views-based.) The one real difference is *reachability*: stock Settings on Android 13 and below tops
out around fontScale **1.30**, while the **2.00** column needs Android 14+ — or `adb`, which is how
QA will get there on the floor emulator.

Anchors, linearly interpolated between; below ≈1.03–1.05 scaling is plain linear:

| fontScale | 8 sp | 10 | 12 | 14 | 18 | 20 | 24 | 30 | 100 |
|---|--:|--:|--:|--:|--:|--:|--:|--:|--:|
| 1.15 | 9.2 | 11.5 | 13.8 | 16.4 | 19.8 | 21.8 | 25.2 | 30 | 100 |
| 1.30 | 10.4 | 13 | 15.6 | 18.8 | 21.6 | 23.6 | 26.4 | 30 | 100 |
| 1.50 | 12 | 15 | 18 | 22 | 24 | 26 | 28 | 30 | 100 |
| 1.80 | 14.4 | 18 | 21.6 | 24.4 | 27.6 | 30.8 | 32.8 | 34.8 | 100 |
| **2.00** | 16 | 20 | 24 | 26 | 30 | 34 | 36 | 38 | 100 |

These five are exactly the anchors Compose ships. (Recent AOSP has since added 1.05 / 1.1 / 1.2
tables that Compose's vendored copy does not carry; at those scales Compose interpolates instead.
Test at 1.15 / 1.3 / 1.5 / 1.8 / 2.0 — the anchors are the only scales where the curve is a
constant rather than an interpolation, so they are the stable screenshot baselines.)

**Both platforms compress large text at accessibility sizes**, which is the important structural
match — iOS does it per text style through the `relativeTo:` ladder, Android does it per sp value
through this curve. So the translation is not "map each `relativeTo:` to something"; it is **put the
point size in sp and let Android's curve do what iOS's ladder did**.

### 4.2 The comparison that decides the cap question

iOS at its shipped cap (AX2) vs Android at its maximum (fontScale 2.0), for this app's actual sizes:

| Token(s) | sp | iOS AX2 | ×    | Android @2.0 | ×    | Android vs iOS |
|---|--:|--:|--:|--:|--:|--:|
| `displayXL` | 34 | 48 | 1.41 | 41.5 | 1.22 | **−13.5 %** |
| `displayL` / `heroTitle` | 28 | 43 | 1.54 | 37.3 | 1.33 | −13.2 % |
| `showTitleL` | 22 | 39 | 1.77 | 35.0 | 1.59 | −10.3 % |
| `sectionTitle` | 20 | 37 | 1.85 | 34.0 | 1.70 | −8.1 % |
| `body` / `rowTitle` / `showTitleM` | 17 | 33 | 1.94 | 29.0 | 1.71 | −12.1 % |
| `button` | 16 | 32 | 2.00 | 28.0 | 1.75 | −12.5 % |
| `cardFact` / `heroMeta` | 15 | 30 | 2.00 | 27.0 | 1.80 | −10.0 % |
| `metadata` / `rowMeta` / `listAction` | 13 | 27 | 2.08 | 25.0 | 1.92 | −7.4 % |
| `shelfCaption` | 12 | 26 | 2.17 | 24.0 | 2.00 | −7.7 % |
| `sectionLabel` / `caption` | 11 | 24 | 2.18 | 22.0 | 2.00 | −8.3 % |

**Conclusion: ship no cap.** Android's own maximum is already 7–14 % more conservative than the
ceiling the iOS build chose to allow, so every layout that survives AX2 on iOS has slack on Android.
A cap would also be the wrong instrument: the only way to impose one is
`CompositionLocalProvider(LocalDensity provides Density(density, fontScale.coerceAtMost(x)))`, and
Google's own page shows that construction for **user-driven pinch-to-zoom**, not for taking scale
away from a user who asked for it. It further breaks non-linearity — the coerced scalar goes back
through the curve as if it were the user's setting.

### 4.3 The one place Android is *worse* than iOS, and it needs a decision

At **fontScale 1.30** — the largest step in the ordinary Settings → Display → Font size slider, i.e.
what a merely long-sighted user picks, not an accessibility user — the curve is brutal to headings:

| Token | sp | @1.30 | × |
|---|--:|--:|--:|
| `displayXL` | 34 | 34.0 | **1.00** |
| `displayL` / `heroTitle` | 28 | 28.8 | 1.03 |
| `showTitleL` | 22 | 25.0 | 1.14 |
| `sectionTitle` | 20 | 23.6 | 1.18 |
| `body` / `rowTitle` | 17 | 20.9 | 1.23 |
| `cardFact` / `heroMeta` | 15 | 19.5 | 1.30 |
| `metadata` | 13 | 17.2 | 1.32 |

**The hero headline does not grow at all**, while the metadata under it grows 32 %. On iOS at
xxxLarge the same headline goes 34 → 40. The ladder does not invert (the headline is still the
biggest thing) but the *gap* between the hero and its support line closes hard, and the hero is the
whole point of the Today screen. This is Q3 in §9.

### 4.4 The rest of `@ScaledMetric`

`ScaledFont.swift` and eleven `@ScaledMetric` sites scale **non-text** metrics — row heights,
skeleton line heights, Schedule's 5-pt dot, Profile's 14-pt indicator, `RankGutter.width`. Android
has no `@ScaledMetric`. The equivalent is to convert an sp value to dp inside a composable:

```kotlin
/** iOS `@ScaledMetric(wrappedValue: n, relativeTo: .body)`. Applies the non-linear curve. */
@Composable
fun scaledDp(value: Dp): Dp = with(LocalDensity.current) { value.value.sp.toDp() }
```

`TextUnit.toDp()` routes through `FontScaleConverterFactory.isNonLinearFontScalingActive(fontScale)`
and uses `convertSpToDp` when the curve applies, so this is the correct conversion and not a
`× fontScale` multiply. Do **not** hand-roll `dp * LocalDensity.current.fontScale`: since Android 14
`DisplayMetrics.scaledDensity` and a bare `fontScale` multiply are documented as inaccurate, and
`fontScale` is "for informational purposes only".

Note the sp arithmetic trap Google calls out: `4.sp + 20.sp` does **not** equal `24.sp` in dp under
the curve. Every composite metric (row height = art + 2 × padding) must be composed in dp and
scaled once, not scaled per-part.

### 4.5 QA

`adb shell settings put system font_scale 1.3` is already in `TOOLCHAIN.md`. Add all five anchors —
**1.15 / 1.3 / 1.5 / 1.8 / 2.0** — to the capture matrix, on **both** emulators
(`PreviouslyQA_API36` and `PreviouslyFloor_API26`). The floor device matters here specifically to
prove the claim in §4.1: the two devices at the same `font_scale` must produce **identical** text
metrics, because Compose vendors the converter. If a screenshot diff at 2.0 shows drift between
them, that assumption is wrong and this whole section needs revisiting.

Note the floor device cannot reach 2.0 through Settings (stock Android 8 tops out near 1.30); `adb`
sets it regardless, which is exactly what makes the comparison possible.

---

## 5. SF Symbols → Material Symbols

### 5.1 Set, style, and the axes

**Set: Material Symbols** — not Material Icons, and not the `material-icons-extended` Compose
artifact. That artifact is **frozen at 1.7.8** and is not published in Compose BOMs from 1.8.0
onward; it also carries the *previous* icon generation. Nothing new will ever appear in it.

**Optical family: Rounded.** SF Symbols' strokes have rounded terminals and joins; Material Symbols
**Outlined** has flat, squared terminals, and **Sharp** has hard corners. Rounded is the only one of
the three whose terminal treatment matches, and it also sits better beside Outfit, which is a
geometric sans with round bowls. (The earlier `spec/icon-mapping.md` reached the same conclusion; it
holds.)

**Axes:**

| Axis | Range | Google default | **This app** |
|---|---|---|---|
| `FILL` | 0 – 1 | 0 | per-glyph, from the table (SF's `.fill` suffix) |
| `wght` | 100 – 700 | 400 | **400**, or **500** where the iOS call site draws the glyph at `.semibold` |
| `GRAD` | −50 – 200 | 0 | **−25** everywhere |
| `opsz` | 20 – 48 | 48 | **24** (the design source size; use the `_24px` files) |

**`GRAD −25` is the single most consequential line in this section.** Google's guidance: the default
grade is 0 for a dark icon on a light background and **−25 for a light icon on a dark background**,
to keep the apparent size matched — light-on-dark halates and reads heavier than it is. *Previously.*
is dark-only; **every** icon in it is light on dark. Shipping `GRAD 0` gives a set that is uniformly
a touch too fat next to Outfit and next to SF Symbols' own rendering. It costs nothing: the −25
variants are pre-built in the repo as `…_gradN25_24px.xml`.

Weight: 13 of the app's ~57 icon draws are `.system(size: 13, weight: .semibold)` and 6 more are 15
semibold. SF Symbols' weight tracks the surrounding font weight; Material Symbols does not, so those
glyphs need `wght 500` explicitly (`…_wght500gradN25_24px.xml`). The 16/17/20/26-pt regular sites
stay at 400.

### 5.2 Delivery: static VectorDrawable, not the font, not a library

The chosen path — copy the exact XML files out of the source repo:

```
https://github.com/google/material-design-icons
  symbols/android/<icon_name>/materialsymbolsrounded/<icon_name>[_wght500][_gradN25][fill1]_24px.xml
```

Verified naming, from a live listing of `symbols/android/check/materialsymbolsrounded/` on
2026-09-04: variants concatenate without separators in the order **wght → grad → fill**, then the
pixel size — `check_24px.xml`, `check_gradN25_24px.xml`, `check_wght200gradN25fill1_24px.xml`,
sizes 20/24/40/48, weights 100–700 in hundreds, grades `gradN25` / (none = 0) / `grad200`.

**All 24 filenames below were fetched and confirmed to return HTTP 200 on 2026-09-04**, so this
script is complete, not illustrative:

```bash
#!/usr/bin/env bash
# Vendor the 24 icons. Run once, commit the XML, throw the checkout away.
set -euo pipefail
BASE=https://raw.githubusercontent.com/google/material-design-icons/master/symbols/android
DEST=app/src/main/res/drawable

get () {  # get <material_name> <variant_suffix>   ->  res/drawable/ic_<material_name>.xml
  curl -fsSL "$BASE/$1/materialsymbolsrounded/$1$2_24px.xml" -o "$DEST/ic_$1.xml"
}

# ── wght 500 (iOS draws these at .semibold), GRAD -25, FILL 0 ──────────────────
get north_west          _wght500gradN25
get arrow_outward       _wght500gradN25
get check               _wght500gradN25
get keyboard_arrow_down _wght500gradN25
get chevron_right       _wght500gradN25
get unfold_more         _wght500gradN25
get history             _wght500gradN25
get more_horiz          _wght500gradN25
get visibility          _wght500gradN25
get filter_list         _wght500gradN25
get search              _wght500gradN25
get add                 _wght500gradN25
get share               _wght500gradN25
get close               _wght500gradN25

# ── wght 400 (iOS draws these at .regular), GRAD -25, FILL 0 ──────────────────
get sync                 _gradN25
get notifications_active _gradN25
get sensors              _gradN25
get visibility_off       _gradN25
get image                _gradN25
get smart_display        _gradN25

# ── FILL 1 (SF's `.fill` suffix), GRAD -25 ────────────────────────────────────
get notifications _gradN25fill1
get warning       _gradN25fill1
get person        _gradN25fill1
get play_arrow    _gradN25fill1
```

Then, per file, two hand edits (both are one-liners, both matter):

1. **`android:tint` / hard-coded fill.** Google's XML paints `android:fillColor="#FF000000"` — black.
   `Icon()` tints the whole painter, so the literal colour is irrelevant *if* you use `Icon()`; if
   anything ever uses `Image()`, it will draw a black glyph on a black canvas. Normalise
   `fillColor` to `#FFFFFFFF` on import so a mistake is visible instead of invisible.
2. **`android:autoMirrored="true"`** on the five that must flip in RTL: **`chevron_right`**,
   **`north_west`**, **`arrow_outward`**, **`logout`**, **`filter_list`** (its lines are
   left-aligned and decreasing, so it reads backwards unmirrored). Everything else is symmetric or
   vertical — `unfold_more`, `keyboard_arrow_down`, `check`, `close`, `add` need nothing.
   VectorDrawable's `autoMirrored` is the free, correct mechanism and Compose honours it through
   `ImageVector.vectorResource`; it is API 19+, so it works on the floor device.

Call site:

```kotlin
Icon(
    imageVector = ImageVector.vectorResource(R.drawable.ic_chevron_right),
    contentDescription = null,          // decorative; the row carries the label
    tint = PreviouslyColors.textTertiary,
    modifier = Modifier.size(20.dp),
)
```

`Icon` defaults to **24.dp** and tints with `LocalContentColor`. The iOS sizes are point sizes on a
*glyph*, not box sizes, so they do not transfer 1:1 — see §5.5.

### 5.3 The 24 literal symbols

Weight column: **500** where the iOS call site draws the glyph at `.semibold`, else 400. Every row
is `materialsymbolsrounded`, `gradN25`, `opsz 24`.

| # | SF Symbol | Material Symbol | FILL | wght | Where / meaning that must survive |
|---|---|---|:--:|:--:|---|
| 1 | `arrow.triangle.2.circlepath` | **`sync`** | 0 | 400 | `StaleStrip` — "Updated 8h ago". It is a *freshness* mark, not a button; 11 pt regular. `refresh` (the circular arrow) is the alternative and is arguably closer to iOS's two-arrow loop — pick `sync` for the two-arrow form, `refresh` if QA says `sync` reads as "cloud" |
| 2 | `arrow.up.backward` | **`north_west`** | 0 | 500 | Discover's recent-term row: "put this query back in the field". Android's own search UIs use exactly this diagonal. **Must auto-mirror** |
| 3 | `arrow.up.right` | **`arrow_outward`** | 0 | 500 | Leaves the app (trailer provider, JustWatch). `open_in_new` is the Android-reflex alternative — see Q4 |
| 4 | `bell.badge` | **`notifications_active`** | 0 | 400 | The notification permission primer, 20 pt regular. Material's "active" bell has motion lines where SF has a dot — accepted; `edit_notifications` is worse |
| 5 | `bell.fill` | **`notifications`** | **1** | 400 | Schedule's reminder, committed. Amber STATE |
| 6 | `checkmark` | **`check`** | 0 | 500 | The bare tick. `MarkRing`'s settled watched state; six call sites. **Never `check_circle`** — the ring is drawn by the app, the glyph is only the tick |
| 7 | `chevron.down` | **`keyboard_arrow_down`** | 0 | 500 | Disclosure. `keyboard_arrow_*` is the metric-matched pair to `chevron_right`; `expand_more` is the same outline on a different grid and will not line up in a row of chevrons |
| 8 | `chevron.forward` | **`chevron_right`** | 0 | 500 | The row/section-header navigation chevron — the most-drawn glyph in the app. **Must auto-mirror** |
| 9 | `chevron.up.chevron.down` | **`unfold_more`** | 0 | 500 | The season picker and Library's sort. Near-exact match |
| 10 | `clock.arrow.circlepath` | **`history`** | 0 | 500 | Today's "Previously" recap line and watch history. `restore` is the same glyph under an older name — use `history` |
| 11 | `dot.radiowaves.left.and.right` | **`sensors`** | 0 | 400 | ⚠ Live/airing. `sensors` *is* a centre dot with arcs radiating both sides — a much closer match than the earlier spec allowed. **But**: on iOS this glyph lives only in the Live Activity / Dynamic Island, which Android has no counterpart for. On Android it becomes the **notification small icon**, which must be a white-on-transparent single-colour 24 dp drawable. See Q5 |
| 12 | `ellipsis` | **`more_horiz`** | 0 | 500 | Overflow. Exact |
| 13 | `exclamationmark.triangle.fill` | **`warning`** | **1** | 400 | `SyncBanner` / write failure. Filled triangle, exact |
| 14 | `eye` | **`visibility`** | 0 | 500 | *Reveal this spoiler* — the 44-pt button over a hidden episode still. Not a settings toggle |
| 15 | `eye.slash` | **`visibility_off`** | 0 | 400 | The censored episode still itself, 16 pt at 62 % ink. Exact |
| 16 | `line.3.horizontal.decrease` | **`filter_list`** | 0 | 500 | Library's Arrange toolbar item. Amber only when filters are active. `filter_alt` (the funnel) is the Android reflex but changes the mark from "sorted lines" to "funnel" — `filter_list` is the 1:1 |
| 17 | `magnifyingglass` | **`search`** | 0 | 500 | Exact |
| 18 | `person.fill` | **`person`** | **1** | 400 | Cast & crew avatar fallback (`PersonCard`, 72-pt disc). **Not `account_circle`** — that draws its own disc and the app already draws one |
| 19 | `photo` | **`image`** | 0 | 400 | Art placeholder inside `PosterSlot`. `broken_image` says "failed"; this state is "not yet" |
| 20 | `play.fill` | **`play_arrow`** | **1** | 400 | Trailer play triangle |
| 21 | `play.rectangle` | **`smart_display`** | 0 | 400 | `TrailerCard`'s affordance — a play triangle inside a rounded rectangle. `ondemand_video` is the near-identical alternative; `subscriptions` and `movie` are wrong |
| 22 | `plus` | **`add`** | 0 | 500 | Detail's toolbar Add. **Stays `interactive` ink, never amber** — this is the rule the iOS build broke and fixed |
| 23 | `square.and.arrow.up` | **`share`** | 0 | 500 | ⚠ `ios_share` exists in Material Symbols and is a literal copy of the iOS box-and-arrow. **Do not use it.** Use `share` and the Android system share sheet: this is the one place the fidelity rule yields to the platform reflex, and shipping the iOS glyph on Android reads as a port, not an app |
| 24 | `xmark` | **`close`** | 0 | 500 | Dismiss. Exact |

**No good match exists for exactly one of the 24: #11.** Not because the glyph is wrong — `sensors`
is fine — but because the *surface* is gone. Decide Q5 before drawing it.

Two more are "close, decide deliberately": #1 (`sync` vs `refresh`) and #3 (`arrow_outward` vs
`open_in_new`).

### 5.4 Appendix — the other 20

These are the ones passed as stored properties / enum payloads (`EmptyState`, `InlineNotice`,
`SyncBanner`, Profile's grouped settings). All names verified present in Material Symbols Rounded
against the 4,275-entry codepoints list on 2026-09-04.

| SF Symbol | Material Symbol | FILL | Note |
|---|---|:--:|---|
| `bell` | `notifications` | 0 | Reminder, unset |
| `bookmark` | `bookmark` | 0 | Planned / saved |
| `calendar` | `calendar_month` | 0 | Schedule empty state. `event` also fine |
| `checkmark.circle.fill` | `check_circle` | **1** | "Everything synced" |
| `circle.fill` | `circle` | **1** | The today dot / bullet. A 4–6 dp `Box` with a `CircleShape` background is cheaper and sharper — prefer that to a glyph |
| `curlybraces` | `data_object` | 0 | Debug/JSON row |
| `doc.text` | `description` | 0 | Legal / export doc |
| `envelope` | `mail` | 0 | Support contact |
| `exclamationmark.circle` | `error` | 0 | Recoverable failure. Keep FILL 0 |
| `hand.raised` | `front_hand` | 0 | Privacy policy row |
| `hand.tap` | `touch_app` | 0 | Haptics setting |
| `line.3.horizontal.decrease.circle.fill` | `filter_list` in a filled disc | 0 | Material has no circled-filter glyph. Draw `filter_list` on an `accentSoft` disc — the app already has that primitive |
| `rectangle.portrait.and.arrow.right` | `logout` | 0 | Sign out. **Must auto-mirror** |
| `rectangle.stack` | `layers` | 0 | Library / all titles. `video_library` is the alternative if `layers` reads as "design tool" |
| `slider.horizontal.3` | `tune` | 0 | "No titles match your filters" |
| `tablecells` | `table` | 0 | Export as table. `table_chart` / `grid_on` alternatives |
| `trash` | `delete` | 0 | Destructive |
| `tv` | `tv` | 0 | TV scope / source badge |
| `wifi.exclamationmark` | `wifi_tethering_error` | 0 | ⚠ Weak. `signal_wifi_bad` and `signal_wifi_statusbar_not_connected` both exist and both read closer to "connected but not working". Compare all three on device |
| `wifi.slash` | `wifi_off` | 0 | Offline. Exact |

### 5.5 Sizing: iOS point size → Compose dp

SF Symbols are **glyphs in a text run**: `.font(.system(size: 13))` sets a *font* size, and the
drawn mark is roughly the cap height plus overshoot — noticeably smaller than 13 pt of box.
Material Symbols' VectorDrawable is a **24 dp box with the ink inset**, roughly 20/24 of the box.

Empirically the two land on top of each other at **`dp ≈ iOS_pt × 1.35`**, rounded to the nearest
even dp, then verified. Starting table — **treat as a first draft to be screenshot-diffed, not as
truth**:

| iOS `.system(size:)` | Sites | `Modifier.size()` |
|---|---|---|
| 9 | 1 | 12.dp |
| 10 | 2 | 14.dp |
| 11 | 3 | 16.dp |
| 12 | 5 | 16.dp |
| 13 | 13 | 18.dp |
| 14 | 2 | 20.dp |
| 15 | 8 | 20.dp |
| 16 | 2 | 22.dp |
| 17 | 2 | 24.dp |
| 20 | 1 | 28.dp |
| 26 | 1 | 36.dp |

Two rules that come with it:

- **The touch target is separate from the glyph.** iOS wraps these in `.frame(width: 44, height: 44)`.
  Android's minimum is **48 dp**; Compose enforces it on `Modifier.clickable` inside
  `LocalMinimumInteractiveComponentSize`. Draw the glyph at the size above and let the target be
  48 dp — do not scale the glyph up to fill it.
- **Icons do not scale with font size**, on either platform, unless you make them. iOS's
  `@ScaledMetric` glyph sites (`Primitives+States.swift`'s `glyphUnit`) do; port those with
  `scaledDp()` from §4.4 and leave the rest fixed. Google's guidance for the font-scaling strategy
  is explicitly that "containers, padding, and icons remain a fixed size".

### 5.6 Non-glyph assets

Unchanged from `spec/icon-mapping.md` and still correct: the four tab-bar SVGs become `ImageVector`s
(remember the **+3,+3 path translation** — VectorDrawable has no negative viewport origin), the
splash PNGs map @2x→`xhdpi` / @3x→`xxhdpi` with **`xxxhdpi` re-rendered from vector, never upscaled**,
and the app icon needs an **adaptive icon plus a monochrome layer** for Android 13+ themed icons —
a layer that does not exist yet and has to be drawn.

Two floor-related notes: adaptive icons arrive at **exactly API 26**, so there is no legacy square
icon to maintain; the **monochrome** layer is API 33+ and is ignored below that, so it needs no
qualifier — just a `<monochrome>` element in `mipmap-anydpi-v26/ic_launcher.xml`.

---

## 6. Dark-only

### 6.1 The Compose half

```kotlin
// ui/theme/Theme.kt

private val PreviouslyDarkScheme = darkColorScheme(
    primary        = Amber,            // ThemeColor.accent  #F0A24E
    onPrimary      = OnAccent,         // #0B0B0D
    background     = Canvas,           // #09090B
    onBackground   = TextPrimary,      // #F4F1EC
    surface        = SurfaceFlat,      // #171719
    onSurface      = TextPrimary,
    surfaceVariant = SurfaceRaised,    // #242428
    outline        = Stroke,           // white 12 %
    error          = Destructive,      // #FF453A
    // …the rest of the 30-odd M3 roles. Fill them ALL: an unset role falls back to
    // Material's baseline purple, and it will surface in exactly one dialog, once, in beta.
)

@Composable
fun PreviouslyTheme(content: @Composable () -> Unit) {
    // NO `darkTheme: Boolean = isSystemInDarkTheme()` parameter.
    // NO dynamicDarkColorScheme(). Amber is the brand; the wallpaper does not get a vote.
    MaterialTheme(
        colorScheme = PreviouslyDarkScheme,
        typography  = PreviouslyMaterialTypography,
        shapes      = PreviouslyShapes,
    ) {
        CompositionLocalProvider(
            LocalPreviouslyType   provides PreviouslyType,
            LocalPreviouslyColors provides PreviouslyColors,
            LocalPreviouslySpace  provides PreviouslySpace,
            LocalContentColor     provides PreviouslyColors.textPrimary,
            content = content,
        )
    }
}
```

The positive act here is **not calling** two functions. `isSystemInDarkTheme()` reads
`Configuration.uiMode`; never calling it means the system setting has no path into the composition.
`dynamicDarkColorScheme(context)` (API 31+) is the one that would import wallpaper colour — never
call it, and therefore never write the `SDK_INT >= S` branch that every Compose theme template
starts with.

`LocalContentColor` matters more than it looks: `Icon()` and `IconButton()` tint from it, and M3's
default is derived from the colour scheme role of whatever surface they sit on. Providing it once at
the root is what makes an `Icon()` with no explicit `tint` come out in the app's ink.

### 6.2 The manifest / resources half

The system can still reach the app three ways that Compose does not cover: the **launch theme**
(what is on screen before the first frame), **Force Dark** (the platform's auto-darkening of
light-themed apps, which OEMs like Xiaomi apply aggressively), and the **WebView** in the trailer
sheet.

`res/values/themes.xml` — and **create no `res/values-night/`**. One `values/` folder is already
unconditional; adding a night variant is what would introduce a light/dark split.

```xml
<resources>
    <style name="Theme.Previously.Splash" parent="Theme.SplashScreen">
        <item name="windowSplashScreenBackground">@color/launch_black</item> <!-- #000000 -->
        <!-- ERRATUM (2026-09-04, PLAN §4.7/§9.2): this was @color/canvas (#09090B). The launch
             frame is TRUE BLACK for OLED continuity, matching ios LaunchBackground.colorset
             (r/g/b 0.000) and Info.plist:54. The system splash and SplashScreen.kt must sit on
             the SAME black or the hand-off shows a colour step. -->
        <item name="windowSplashScreenAnimatedIcon">@drawable/ic_splash</item>
        <item name="postSplashScreenTheme">@style/Theme.Previously</item>
    </style>

    <!-- Everything that is safe at API 26 lives on .Base; the v27/v29 overlays below
         extend it and add the attributes that arrive later. -->
    <style name="Theme.Previously.Base" parent="android:Theme.Material.NoActionBar">
        <!-- Tell the platform this is a dark theme. Three consequences:
             1. Force Dark is globally disabled for it (documented: a theme with
                isLightTheme="false" is never auto-darkened);
             2. WebView reports `prefers-color-scheme: dark` to page content, which is
                what makes the YouTube trailer embed come up dark — the Android answer
                to iOS's VideoSheet;
             3. system-supplied surfaces (autofill, text-selection handles) pick dark. -->
        <item name="android:isLightTheme">false</item>
        <item name="android:forceDarkAllowed">false</item>

        <item name="android:windowBackground">@color/canvas</item>
        <item name="android:statusBarColor">@android:color/transparent</item>
        <item name="android:navigationBarColor">@android:color/transparent</item>
        <item name="android:windowLightStatusBar">false</item>   <!-- API 23+, fine at the 26 floor -->
    </style>

    <!-- What the manifest points at. -->
    <style name="Theme.Previously" parent="Theme.Previously.Base" />
</resources>
```

Three attributes arrive **after** the API 26 floor and must be version-qualified, or lint's `NewApi`
check fires and the intent gets lost in a suppression:

```xml
<!-- res/values-v27/themes.xml -->
<style name="Theme.Previously" parent="Theme.Previously.Base">
    <item name="android:windowLightNavigationBar">false</item>   <!-- API 27 -->
</style>

<!-- res/values-v29/themes.xml -->
<style name="Theme.Previously" parent="Theme.Previously.Base">
    <item name="android:windowLightNavigationBar">false</item>
    <item name="android:enforceNavigationBarContrast">false</item>  <!-- API 29 -->
    <item name="android:enforceStatusBarContrast">false</item>      <!-- API 29 -->
</style>
```

Note that these are **not** `values-night/` folders — they are API-level qualifiers, not UI-mode
qualifiers, and the two are easy to conflate at review time. Introducing `values-night/` anywhere in
the tree is the one thing that would break the dark-only guarantee.

Below API 29 there is no navigation-bar contrast enforcement to switch off, so the app simply gets
the platform's own translucent nav band there — acceptable, and the reduce-transparency/no-blur
chrome path (`minsdk-decision.md`) is already the design that covers those devices.

```xml
<activity
    android:name=".MainActivity"
    android:theme="@style/Theme.Previously.Splash"
    android:windowSoftInputMode="adjustResize"
    android:configChanges="uiMode"
    android:exported="true" />
```

`android:configChanges="uiMode"` is a small but real win: without it, a user toggling system dark
mode **recreates the Activity** — a jarring re-entry into a screen whose appearance does not change
at all. Declaring it means `onConfigurationChanged()` fires and nothing else happens.

On the trailer WebView (the `VideoSheet` equivalent), leave algorithmic darkening **off** — but say
so explicitly, and guard the call, because the API is provider-gated rather than API-level-gated:

```kotlin
if (WebViewFeature.isFeatureSupported(WebViewFeature.ALGORITHMIC_DARKENING)) {
    // The page is ALREADY dark: android:isLightTheme="false" makes WebView report
    // `prefers-color-scheme: dark`, and YouTube's embed honours it. Algorithmic
    // darkening on top of that would invert the video chrome a second time.
    WebSettingsCompat.setAlgorithmicDarkeningAllowed(webView.settings, false)
}
```

`setAlgorithmicDarkeningAllowed` is the `androidx.webkit` method that applies for `targetSdk ≥ 33`
(this app is 36). Note the platform's own override: if the system is applying Force Dark to WebView,
the setting is ignored and behaves as `true` — which is a second reason `isLightTheme="false"`
matters, since it takes the app out of Force Dark's scope entirely.

### 6.3 What is *not* needed

- **`AppCompatDelegate.setDefaultNightMode(MODE_NIGHT_YES)`** — that is the AppCompat mechanism, and
  a pure-Compose `ComponentActivity` app does not use AppCompat. Adding AppCompat just for it would
  be backwards.
- **A light `ColorScheme` "for completeness"** — an unused light scheme is a trap. It will get
  wired up by accident in one dialog and produce the only white surface in the app.
- **`android:forceDarkAllowed="true"`** — the opposite of what is wanted.

---

## 7. Edge-to-edge and system bars

### 7.1 It is not optional

Apps targeting **API 36** cannot opt out. `R.attr#windowOptOutEdgeToEdgeEnforcement` is **deprecated
and disabled** on Android 16 devices (it still works if a targetSdk-36 app runs on Android 15, which
is not a reason to use it). Edge-to-edge has been enforced by default since **API 35**.

For this app that is a gift, not a migration: the iOS design is already full-bleed art running under
translucent chrome, with `HeroTopVeil`, `chromeBarOpacity` and the `scrollEdgeChromeBody` ramp doing
the work. The Android layout wants the same shape.

### 7.2 The Activity

```kotlin
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        val splash = installSplashScreen()
        super.onCreate(savedInstanceState)

        // Both bars transparent, both with LIGHT icons (SystemBarStyle.dark == dark bar,
        // light content). The `scrim` argument is what a device below API 29 gets, where
        // a transparent nav bar cannot guarantee icon contrast.
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.dark(Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.dark(Color.TRANSPARENT),
        )
        // `enableEdgeToEdge` puts a translucent scrim behind 3-button navigation. This app
        // paints its own material tab bar to the bottom edge, so the scrim would be a second,
        // differently-coloured band under the first. API 29+; below that there is no scrim
        // to switch off.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            window.isNavigationBarContrastEnforced = false
        }

        setContent { PreviouslyTheme { PreviouslyApp() } }
    }
}
```

`enableEdgeToEdge()` comes from `androidx.activity:activity-compose` (1.8+) and back-compats to
API 21, so it is safe at the 26 floor. Passing `SystemBarStyle.dark` for both bars pins the icons
light and makes them independent of the system theme — the `auto(...)` variants are the ones that
would follow light/dark, so do not use them in a dark-only app. The `scrim` argument (here
`Color.TRANSPARENT`) is what devices below API 29 fall back to, where a transparent nav bar cannot
guarantee icon contrast; on the API 26 floor emulator, check that the bottom of Today does not lose
its tab labels behind the 3-button bar.

### 7.3 Insets in Compose

`enableEdgeToEdge` only removes the bars' opaque background. Taking the insets is on you, and it is
the part where a fidelity port goes wrong quietly: content that is *technically* visible but sits
1 dp under a status-bar clock is exactly the failure the iOS build spent three passes fixing.

The mapping from the iOS vocabulary:

| iOS | Compose |
|---|---|
| `.ignoresSafeArea()` on hero art | draw with no inset modifier at all (the default) |
| safe-area top for the chrome band | `WindowInsets.statusBars` / `.safeDrawing.only(WindowInsetsSides.Top)` |
| `ThemeMetrics.tabBarClearance` bottom scroll inset | `WindowInsets.navigationBars` + the tab bar's own height, applied as `contentPadding` on the `LazyColumn`, **not** as a modifier on it |
| keyboard avoidance | `WindowInsets.ime` (needs `android:windowSoftInputMode="adjustResize"`) |
| `safeAreaInsets` for a toast | `WindowInsets.safeDrawing` |

```kotlin
Scaffold(
    // Scaffold consumes safeDrawing by default and hands it to the content lambda.
    // This app draws its own bars over full-bleed art, so take NOTHING here and
    // apply insets per-surface. Otherwise the hero stops at the status bar.
    contentWindowInsets = WindowInsets(0),
    bottomBar = { PreviouslyTabBar(Modifier.windowInsetsPadding(WindowInsets.navigationBars)) },
) { _ ->
    LazyColumn(
        contentPadding = WindowInsets.safeDrawing.asPaddingValues().let {
            PaddingValues(
                top = 0.dp,                                     // hero runs under the bar
                bottom = it.calculateBottomPadding() + TabBarHeight + Gutter,
            )
        },
    ) { /* … */ }
}
```

Two rules worth writing into the code review checklist:

- **`Modifier.windowInsetsPadding` on a scrolling container clips the scroll.** Use
  `contentPadding` for scroll containers and `windowInsetsPadding` for fixed chrome. This is the
  single most common edge-to-edge bug.
- **Insets are consumed as they are applied.** A `windowInsetsPadding(safeDrawing)` on an outer Box
  means the inner content sees zero insets. That is usually what you want exactly once, at the top.

### 7.4 Emulator note

`TOOLCHAIN.md` records the QA emulator at **427 × 952 dp** against the iPhone's 393 × 852 pt — 34 dp
wider and 100 dp taller. Combined with gesture navigation's ~24 dp bottom inset versus iOS's 34 pt
home indicator, the bottom chrome arithmetic (`tabBarClearance = bottomChromeHeight + x3`) does not
transfer as a constant. Recompute it from `WindowInsets.navigationBars` at runtime rather than
porting `152`/`90`/`62` as literals.

---

## 8. Rejected alternatives

| Rejected | Why |
|---|---|
| **`androidx.compose.material:material-icons-extended`** | Frozen at 1.7.8; not published in Compose BOMs from 1.8.0; ships the previous icon generation; and pulls ~2,000 `ImageVector` initialisers into the binary for 44 icons |
| **`dev.vicart:compose-material-symbols` (1.1.5)** | Works, exposes wght/grade/size, KMP-friendly. But it is one maintainer's library on the critical path of every screen's iconography, it bundles the **whole** symbol font (thousands of glyphs, MB-class) where 44 XML files cost ~20 KB, and it cannot express per-icon FILL as cleanly as picking the `fill1` file. Keep it in mind only if animating FILL becomes a requirement (§9 Q6) |
| **Material Symbols as a bundled variable font, rendered as text** | Tempting: `FontVariation.weight()`, `FontVariation.grade()` and `FontVariation.opticalSizing()` all exist in Compose, so all four axes are reachable, and FILL 0→1 could be animated. Rejected because (a) the font is megabytes unless subsetted, and subsetting becomes a build step nobody maintains; (b) variation settings are baked into the `Font` at load, so "animating" FILL means constructing a new `FontFamily` and `Typeface` per frame; (c) a glyph in a text run does not compose with `Modifier.size` the way `Icon` does, so every existing layout metric would need re-deriving |
| **Downloadable Google Fonts for Outfit** | Cannot serve variable fonts at all (open bug 223262013); asynchronous first paint causes reflow on the billboard hero; requires Play Services and a network on an app that deliberately opens offline |
| **Five static Outfit TTFs (a literal port of the iOS bundle)** | Works and is the lowest-risk option. Rejected on size (~240 KB vs ~100 KB) and on the fact that a variable file makes any future weight — a lighter caption, a heavier wordmark — a one-line change rather than a new asset |
| **`isSystemInDarkTheme()` with a light scheme that is never used** | Dead code that one dialog will eventually reach |
| **Capping `fontScale` via `LocalDensity`** | Android's own maximum is already more conservative than the iOS cap (§4.2); a cap takes away scale the user asked for, and re-feeding a coerced scalar through the non-linear curve is not what the curve is for |
| **`.sp` for `letterSpacing`** | Correct at fontScale 1.0, over-tightens above it because letter-spacing values sit far below the curve's 8 sp anchor |
| **M3 `Typography` as the app's design tokens** | Fifteen Material slot names cannot carry `heroTitle` / `cardFact` / `rowMetaLead` / `listAction`, and the whole point of `ThemeTokens.swift` is that the token name *is* the design decision |
| **`ios_share` glyph for Share** | It exists in Material Symbols. Using it would put the iOS box-and-arrow on Android, which reads as a port |
| **`AppCompatDelegate.setDefaultNightMode`** | Requires AppCompat in an app that does not otherwise need it |

---

## 9. Open questions — need a human decision

**Q1 · Is the annotating face `FontFamily.Default`, or a bundled Roboto?**
The iOS design pairs Outfit (speaks) with SF Pro (annotates) — a geometric sans against a
neo-grotesque. `FontFamily.Default` on Android resolves to Roboto, which is also a neo-grotesque,
so the pairing survives at zero bytes. Confirmed for Samsung: One UI's custom font applies only to
Samsung's own apps, and third-party apps get Roboto. **Unconfirmed for other OEMs** (Xiaomi HyperOS,
Oppo ColorOS) and for users who install a system font pack. Lean: `FontFamily.Default` for v1, with
a bundled `Roboto[wdth,wght].ttf` as the escape hatch if OEM QA shows drift. *Decide before the
first beta, because it changes every metadata line's width.*

**Q2 · Does `prose` stay in the grotesque?**
The iOS comment is deliberate — a synopsis is quoted *content*, not the app's voice, and SF reads
better than a geometric sans over a paragraph. That argument transfers to Roboto unchanged. But it
is the one place a reviewer will say "why isn't this the brand font", so it should be an explicit
decision rather than an inherited one.

**Q3 · The heading that does not grow at fontScale 1.30 (§4.3).**
34 sp → 34.0 dp: the hero headline is the *only* element on Today that does not respond to the
ordinary font-size slider, while the metadata under it grows 32 %. Three options: (a) accept it —
Android users expect this curve and the hierarchy does not invert; (b) special-case the two display
tokens through `scaledDp()` so they scale linearly like iOS; (c) drop `displayXL` from 34 to 30 sp,
which puts it below the curve's flat shelf. **(a) is the honest default and (b) is the fidelity
answer.** Needs a screenshot comparison at 1.0 / 1.3 / 2.0 before choosing.

**Q4 · `arrow_outward` or `open_in_new` for "leaves the app"?**
`arrow_outward` is the 1:1 for SF's `arrow.up.right`. `open_in_new` (arrow escaping a box) is the
Android reflex and tells the user a browser or another app is about to open — which is exactly what
the JustWatch and trailer-provider links do. Same class of decision as #23 Share, and probably
wants the same answer.

**Q5 · What replaces the Live Activity, and what icon does it wear?**
`dot.radiowaves.left.and.right` exists only in `AniTrackWidgets.swift` — Dynamic Island compact
leading, minimal, and lock-screen. Android's nearest equivalent in 2026 is a **Live Update /
`ProgressStyle` notification** (Android 16+), which needs a **notification small icon**: white on
transparent, single colour, 24 dp, no gradient. `sensors` at `wght 500` fill 0 would work, but this
is a product decision about a whole surface, not an icon swap. **Out of scope for this note; must
not be improvised by whoever ports the widget.**

**Q6 · Does the mark tick animate its FILL?**
`MarkRing`'s settled watched state is a bare check. If the design ever wants the Material
FILL 0→1 morph on commit, static VectorDrawables cannot do it and the decision in §5.2 has to be
revisited (an `AnimatedVectorDrawable` between the two files is the middle path). Today the answer
is no — flagging it because it is the one thing the static path forecloses.

**Q7 · Monochrome app-icon layer.**
Android 13+ themed icons need a monochrome layer that does not exist in the iOS asset set. Someone
has to draw it. It is a design task, not an engineering one.

**Q8 · Do the *icons* need a floor-device pass?**
The type ramp is proven identical across API 26 and 36 by §4.1. Icons should be too — VectorDrawable
is API 21+ and `Icon()` is pure Compose — but two things are worth one screenshot each on
`PreviouslyFloor_API26`: whether `android:autoMirrored` behaves identically on Android 8 (it is
API 19+, so it should), and whether the `gradN25` hairlines survive at 480 dpi on the older
rasteriser. Cheap to check, annoying to discover in beta.

---

## 10. Sources

All checked **2026-09-04** unless the source itself carries a later "last updated" date, which is
then given.

| Claim | Source | Date |
|---|---|---|
| Compose fonts: `res/font` rules, `FontFamily`, variable fonts + `FontVariation`, downloadable fonts, **variable fonts unsupported via downloadable fonts (bug 223262013)** | https://developer.android.com/develop/ui/compose/text/fonts | page updated 14 Aug 2026 |
| `Font(resId, …)` overloads and the empty-`FontVariation.Settings` default | `androidx-main` · `compose/ui/ui-text/src/commonMain/kotlin/androidx/compose/ui/text/font/Font.kt` (read directly) | 4 Sep 2026 |
| Asset/file `Font(...)` overloads DO default `variationSettings` to `Settings(weight, style)` | `androidx-main` · `.../font/AndroidFont.android.kt` | 4 Sep 2026 |
| `FontVariation.weight` → `wght`, `.grade` → `GRAD`, `.opticalSizing` → `opsz`, `Settings(weight, style, vararg)` | `androidx-main` · `.../font/FontVariation.kt` | 4 Sep 2026 |
| Outfit is a single variable file `Outfit[wght].ttf`, wght 100–900, OFL 1.1, Rodrigo Fuenzalida | https://github.com/google/fonts/tree/main/ofl/outfit · https://fonts.google.com/specimen/Outfit | 4 Sep 2026 |
| M3 typography = 15 slots; no `defaultFontFamily`; `MaterialTheme(typography = …)`; dynamic colour is API 31+ | https://developer.android.com/develop/ui/compose/designsystems/material3 | 4 Sep 2026 |
| material3 stable **1.4.0** (26 Aug 2026); **1.5.0-alpha27** latest alpha; `Typography` default-`FontFamily` constructor added 1.5.0-alpha16 (25 Mar 2026), refined 1.5.0-alpha19 (6 May 2026) | https://developer.android.com/jetpack/androidx/releases/compose-material3 | 26 Aug 2026 |
| `includeFontPadding = false` default since ui 1.6.0-alpha01; `LineHeightStyle.Trim` requires it | https://medium.com/androiddevelopers/fixing-font-padding-in-compose-text-768cd232425b · https://developer.android.com/develop/ui/compose/text/style-paragraph | — |
| Android 14: font scaling to **200 %**, non-linear curve, use `TypedValue.applyDimension`/`deriveDimension`, `scaledDensity` inaccurate, `fontScale` informational only, sp arithmetic is not additive | https://developer.android.com/about/versions/14/features | — |
| The exact non-linear lookup tables (AOSP carries 1.05 / 1.1 / 1.15 / 1.2 / 1.3 / 1.5 / 1.8 / 2.0; `sMinScaleBeforeCurvesApplied = 1.05f`) | AOSP `frameworks/base` · `core/java/android/content/res/FontScaleConverterFactory.java` (read directly) | 4 Sep 2026 |
| **Compose vendors its own converter — the curve applies on every API level, not just 14+**; `TextUnit.toDp()` / `Dp.toSp()` call `androidx.compose.ui.unit.fontscaling.FontScaleConverterFactory`, whose table carries 1.15 / 1.3 / 1.5 / 1.8 / 2.0 with values identical to AOSP's | `androidx-main` · `compose/ui/ui-unit/src/androidMain/.../unit/FontScaling.android.kt` and `.../unit/fontscaling/FontScaleConverterFactory.android.kt` (read directly) | 4 Sep 2026 |
| Font-scale strategy, min/max ≈ 0.75×/3.5×, `LocalDensity` + `Density(density, fontScale)` pattern, "containers, padding, and icons remain a fixed size" | https://developer.android.com/develop/ui/compose/accessibility/scalable-content | page updated 21 Jul 2026 |
| iOS Dynamic Type point ladder incl. AX1–AX5 | **Measured**: `UIFont.preferredFont(forTextStyle:compatibleWith:)` on simulator `C2AED006-…` (Previously QA 14 Pro), iPhoneSimulator27.0 SDK | 4 Sep 2026 |
| Material Symbols: 3 styles, axes FILL 0–1 / wght 100–700 / GRAD −50–200 / opsz 20–48, static assets available as Android Vector Drawable | https://developers.google.com/fonts/docs/material_symbols | 4 Sep 2026 |
| **GRAD default is 0 for dark-on-light and −25 for light-on-dark**; grade is finer than weight and barely changes size | Material Design 3 icon guidance, via https://m3.material.io/styles/icons/overview and the Material Symbols guide | 4 Sep 2026 |
| Repo layout `symbols/android/<name>/materialsymbols{outlined,rounded,sharp}/<name>[wght…][grad…][fill1]_{20,24,40,48}px.xml`; grades present are `gradN25`, none (=0), `grad200` | https://api.github.com/repos/google/material-design-icons/contents/symbols/android/check/materialsymbolsrounded (live listing) | 4 Sep 2026 |
| Material Symbols Rounded contains **4,275** named glyphs; every name in §5.3/§5.4 verified present | `variablefont/MaterialSymbolsRounded[FILL,GRAD,opsz,wght].codepoints` (downloaded and grepped) | 4 Sep 2026 |
| All 24 exact variant filenames in §5.2's script return HTTP 200 | `curl -o /dev/null -w %{http_code}` against `raw.githubusercontent.com/.../symbols/android/<name>/materialsymbolsrounded/<file>` | 4 Sep 2026 |
| `material-icons-core` / `-extended` frozen at **1.7.8**, package absent from 1.8.0-rc01 onward, "no longer being published" | Kotlinlang #compose thread + Maven Central version history; androidx release notes confirm only the AutoMirrored deprecations | Feb 2025 → 2026 |
| `Icon()` defaults to 24.dp and tints from `LocalContentColor`; `Icons.AutoMirrored.*` exists for RTL | https://developer.android.com/develop/ui/compose/graphics/images/material · compose-material release notes 1.6.0-alpha05 (6 Sep 2023) | — |
| Android 16 (API 36): edge-to-edge mandatory; `windowOptOutEdgeToEdgeEnforcement` deprecated **and disabled** | https://developer.android.com/about/versions/16/behavior-changes-16 | 4 Sep 2026 |
| `enableEdgeToEdge()`, `SystemBarStyle.dark/light/auto`, 3-button scrim, `window.isNavigationBarContrastEnforced = false`, `windowSoftInputMode="adjustResize"` | https://developer.android.com/develop/ui/compose/system/setup-e2e | page updated 2 Sep 2026 |
| `android:isLightTheme="false"` globally disables Force Dark; `forceDarkAllowed` opt-in/out; `configChanges="uiMode"` avoids recreation | https://developer.android.com/develop/ui/views/theming/darktheme | — |
| **WebView sets `prefers-color-scheme` from the app theme's `isLightTheme`**; `setAlgorithmicDarkeningAllowed` required for `targetSdk ≥ 33` | https://developer.android.com/develop/ui/views/layout/webapps/dark-theme | — |
| core-splashscreen: `windowSplashScreenBackground` / `windowSplashScreenAnimatedIcon` / `postSplashScreenTheme`; `values-night` is the *opt-in* to a dark variant | https://developer.android.com/develop/ui/views/launch/splash-screen | — |
| Samsung One UI: the OEM font applies to Samsung apps only; third-party apps render Roboto | XDA One UI font research thread; Samsung Community threads (One UI 6/7) | 2026 |
| `dev.vicart:compose-material-symbols` 1.1.5, variable-font based, KMP | https://github.com/ClementVicart/compose-material-symbols | 4 Sep 2026 |
| Roboto supports the `tnum` OpenType feature | https://otf.show/tnum and font-feature references | — |

**Where sources disagree, and how it was resolved:** several secondary posts state flatly that
"Material Icons is deprecated". The androidx **release notes** carry no library-wide deprecation —
only the per-icon `AutoMirrored` deprecations from 1.6.0-alpha05 (6 Sep 2023). What is verifiable is
narrower and sufficient: the artifacts stop at **1.7.8** and the package is gone from 1.8.0-rc01
onward. The recommendation in §5 does not depend on the stronger claim.
