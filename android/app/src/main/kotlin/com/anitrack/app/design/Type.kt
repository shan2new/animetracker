package com.anitrack.app.design

import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.LineHeightStyle
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.sp
import com.anitrack.app.R

// =====================================================================================
// TYPOGRAPHY — the port of `ThemeType` / `TypeToken` / `AppFont` from
// ios/Sources/DesignSystem/ThemeTokens.swift + AppFont.swift.
//
// THE LOAD-BEARING RULE (ported verbatim from the source's doc comment):
//
//   Type tokens. Outfit SPEAKS — identity (wordmark, titles) and every word the app says in its
//   own voice (buttons, row/body copy, facts, link actions). SF Pro ANNOTATES — dense small
//   metadata, section labels, numerals/times (Outfit has no tabular figures; timers would jiggle),
//   and the one long-form reading paragraph (`prose`). The old split ("Outfit carries identity,
//   SF carries information") left Outfit such a thin slice that it read as the anomaly, not the
//   voice (user, 30 Aug: "paired with some secondary font that isn't going well").
//   Tracking follows the size ramp of the identity tokens: tighter as the cut gets bigger and
//   heavier, neutral by 13 pt.
//
// On Android the ANNOTATING face is **Roboto** (`FontFamily.Default`). Roboto is the platform UI
// face and has tabular figures, so both halves of the rule survive intact: the geometric-vs-
// neo-grotesque contrast reads like Outfit-vs-SF, and numerals still stop jiggling. Outfit is
// bundled identically to iOS (five static cuts) and still SPEAKS.
//
// NOT Material typography. `MaterialTheme.typography` is never the source of a style in this app;
// no screen may see an M3 type. These `TextStyle`s are the whole vocabulary.
//
// -------------------------------------------------------------------------------------
// WHAT CHANGED IN THE PORT, AND WHY (fidelity line: port the meaning, render with native
// means, re-tune the numbers)
//
// 1. `TypeToken` is gone; the token IS a `TextStyle`.
//    SwiftUI splits a type role across two modifiers (`.font(...)` + `.tracking(...)`), which is
//    why iOS needed a `TypeToken` struct and a `.type(_:)` modifier to carry them together.
//    Compose's `TextStyle` already carries family + weight + size + letterSpacing + line height +
//    font features in one value. Reproducing `TypeToken` here would be building machinery Android
//    does not want. iOS `.type(ThemeType.rowTitle)` becomes `style = ThemeType.rowTitle`.
//
// 2. Sizes are `sp`, not `dp`.
//    iOS scales Outfit through `Font.custom(_:size:relativeTo:)`, which applies a named text
//    style's Dynamic Type ramp to a custom size. Android has no per-style ramp — it has one global
//    `fontScale` plus (API 34+) a NON-LINEAR curve that already compresses large text. Declaring in
//    `sp` is the native answer and the product-owner ruling ("`sp` text scaling + Android 14+
//    non-linear font scaling", NOT "a fixed reimplementation of Dynamic Type"). Do not fight the
//    non-linear curve. At the default font scale every size below is EXACTLY the iOS point value.
//
// 3. Tracking is expressed in `sp`, so it scales with the text. iOS tracking is absolute points
//    and does not scale.
//    At the default font scale the two are identical (1 sp == 1 dp == 1 iOS pt). They diverge only
//    at non-default font scales, where the Android value stays proportional to the type — which is
//    what Compose's model wants and what actually reads correctly on a 34 sp display title blown up
//    to accessibility size. The alternative (`value.dp.toSp()` at the current density) would force
//    every token through a `Density` and make the whole palette composable-only, for a difference
//    nobody can see at scale 1.0. Deliberate divergence, recorded.
//
// 4. `.monospacedDigit()` becomes `fontFeatureSettings = "tnum"`, applied only to the annotating
//    face — which is the entire reason numerals live there.
//
// 5. SF Pro **semibold** has no Roboto cut, and asking for one is a trap below API 28.
//    `FontWeight.SemiBold` (W600) has no real Roboto master: on API 28+ the system font matcher is
//    equidistant between Medium (500) and Bold (700), and below API 28 `Typeface.create` cannot
//    express a numeric weight at all, so W600 rounds to Bold or is synthesised. `FontWeight.Medium`
//    resolves to the real `sans-serif-medium` family on EVERY supported API level and is the
//    closest visual analogue to SF semibold at 11–15 sp. Every annotating "semibold" role below is
//    therefore Medium; `numberXL` stays Bold because SF's bold does have a Roboto master. If a
//    design review finds these light, this file is the one place they change.
//    (Outfit is unaffected — we ship its SemiBold cut, so `FontWeight.SemiBold` matches exactly.)
//
// 6. Line heights are declared, where iOS let the text style's leading do it.
//    iOS gets its leading free from the SF text style / the custom font's metrics; Outfit's own
//    vertical metrics on Android are looser than SF's leading, and the rhythm tokens depend on tight
//    baselines (`titleGap` is THREE points — "tight: they are one thought"). Each token's line
//    height is the iOS leading for its size (34→40, 28→34, 22→28, 20→25, 17→22, 16→21, 15→20,
//    14→18, 13→18, 12→16, 11→14). `Trim.Both` means a SINGLE-line label still measures exactly its
//    own ascent+descent — so declaring a line height buys leading between wrapped lines without
//    padding every one-line row, which is precisely SwiftUI's `lineSpacing` semantics.
// =====================================================================================

/**
 * The app's two faces, in one place — the port of iOS `AppFont`.
 *
 * iOS snaps a requested `Font.Weight` to the nearest bundled Outfit cut by hand
 * (ultraLight/thin/light → Light, medium → Medium, semibold → SemiBold, bold/heavy/black → Bold,
 * everything else → Regular) because `Font.Weight` is a struct and cannot be switched over.
 * Compose's font matcher does that job itself from the `FontFamily` below, so the snap table is
 * declarative here rather than a chain of `==` comparisons.
 */
object AppFont {

    /** Outfit SPEAKS. Five static cuts, bundled — identical set to iOS, no variable font. */
    val outfit: FontFamily = FontFamily(
        Font(R.font.outfit_light, FontWeight.Light),
        Font(R.font.outfit_regular, FontWeight.Normal),
        Font(R.font.outfit_medium, FontWeight.Medium),
        Font(R.font.outfit_semibold, FontWeight.SemiBold),
        Font(R.font.outfit_bold, FontWeight.Bold),
    )

    /**
     * Roboto ANNOTATES — the Android stand-in for SF Pro. `FontFamily.Default` is the platform UI
     * face, so it inherits whatever the OEM ships as the system sans and stays native by
     * definition. It has tabular figures, which is the one property this half of the rule exists
     * for.
     */
    val annotation: FontFamily = FontFamily.Default
}

/**
 * The Dynamic Type ceiling.
 *
 * iOS caps the whole scene at `DynamicTypeSize.accessibility2` — "Scale text for accessibility,
 * but cap before the densest grids break." AX2 is ≈1.94× the default body size.
 *
 * Android's own maximum font scale is **2.0×**, and from API 34 the platform applies a non-linear
 * curve that already compresses large sizes far more than it compresses small ones — which is
 * Android's answer to exactly the problem iOS solved with a ceiling. So on a stock device this
 * guard never fires, and that is the intended state: accepting the platform contract is the ruling
 * (`fidelity-line.md` Q17 in spirit — the platform's accessibility contract wins).
 *
 * The clamp exists only for OEM sliders that go beyond stock. Note it must not be applied
 * unconditionally: replacing `LocalDensity` with a plain [Density] discards Android 14's non-linear
 * converter and silently reverts to linear scaling, so [ceiling] returns the density UNTOUCHED
 * whenever it is already within range.
 */
object AppTypeScale {

    /** iOS's accessibility2 ceiling (≈1.94×), rounded to Android's own stock maximum. */
    const val MAX_FONT_SCALE: Float = 2.0f

    /**
     * The density to install at the theme root. Identity — and therefore non-linear-scaling
     * preserving — unless an OEM has pushed `fontScale` past anything the platform curve covers.
     */
    fun ceiling(density: Density): Density =
        if (density.fontScale <= MAX_FONT_SCALE) density
        else Density(density.density, MAX_FONT_SCALE)
}

// -------------------------------------------------------------------------------------
// Builders. Nothing below this line writes a family, a feature string or a line-height
// style by hand — the same discipline the call sites are held to.
// -------------------------------------------------------------------------------------

/**
 * Leading is added BETWEEN lines, never above the first or below the last.
 *
 * `Trim.Both` makes a single-line `Text` measure its own ascent+descent, so a declared line height
 * costs a one-line row nothing — matching SwiftUI, where `lineSpacing` only ever opens the gap
 * between wrapped lines. `Alignment.Center` distributes the extra space evenly, so a wrapped title
 * stays optically centred in its own box.
 */
private val TrimmedLeading = LineHeightStyle(
    alignment = LineHeightStyle.Alignment.Center,
    trim = LineHeightStyle.Trim.Both,
)

/** Outfit SPEAKS. */
private fun speak(
    size: Float,
    weight: FontWeight,
    tracking: Float,
    lineHeight: Float,
): TextStyle = TextStyle(
    fontFamily = AppFont.outfit,
    fontWeight = weight,
    fontSize = size.sp,
    letterSpacing = tracking.sp,
    lineHeight = lineHeight.sp,
    lineHeightStyle = TrimmedLeading,
)

/** Roboto ANNOTATES. `tabular` is the port of iOS `.monospacedDigit()`. */
private fun annotate(
    size: Float,
    weight: FontWeight,
    tracking: Float = 0f,
    lineHeight: Float,
    tabular: Boolean = false,
): TextStyle = TextStyle(
    fontFamily = AppFont.annotation,
    fontWeight = weight,
    fontSize = size.sp,
    letterSpacing = tracking.sp,
    lineHeight = lineHeight.sp,
    lineHeightStyle = TrimmedLeading,
    fontFeatureSettings = if (tabular) "tnum" else null,
)

/**
 * The type palette and the type assignments.
 *
 * PALETTE first (iOS `enum ThemeType`), then the CONTEXTUAL tokens (iOS
 * `extension ThemeType` — "Type by context"). Both live in one object here because Kotlin has no
 * reason to split them; the section comments preserve which is which.
 */
object ThemeType {

    // ---------------------------------------------------------------------------------
    // PALETTE
    // ---------------------------------------------------------------------------------

    /** The wordmark. The biggest cut in the app belongs to the brand. */
    val brandWordmark: TextStyle = speak(20f, FontWeight.SemiBold, -0.30f, 25f)

    val displayXL: TextStyle = speak(34f, FontWeight.Bold, -0.80f, 40f)
    val displayL: TextStyle = speak(28f, FontWeight.Bold, -0.60f, 34f)
    val showTitleL: TextStyle = speak(22f, FontWeight.SemiBold, -0.35f, 28f)
    val showTitleM: TextStyle = speak(17f, FontWeight.SemiBold, -0.20f, 22f)

    /**
     * THE section header (2 Sep). Every shelf and list section in the app is headed by this —
     * mixed case, the app's voice, with a trailing chevron when the header is the way into the
     * section. It replaces the 11-pt small-caps `sectionLabel` as the header family: Apple TV,
     * Netflix and Apple Music all head a shelf with a bold title the size of a row title plus a
     * step, and the small-caps eyebrow read as a footnote above the shows it introduced. Small
     * caps stay for EYEBROWS (`OverArtLabel`, a grouped list's header) — the two levels now split
     * cleanly instead of one token doing both jobs.
     *
     * (`showTitleS` and `screenTitle` are gone, 30 Aug: no call sites. Not ported.)
     */
    val sectionTitle: TextStyle = speak(20f, FontWeight.SemiBold, -0.30f, 25f)

    val body: TextStyle = speak(17f, FontWeight.Normal, -0.10f, 22f)
    val bodyEmphasis: TextStyle = speak(17f, FontWeight.SemiBold, -0.20f, 22f)
    val button: TextStyle = speak(16f, FontWeight.SemiBold, -0.15f, 21f)
    val callout: TextStyle = speak(16f, FontWeight.Normal, -0.10f, 21f)

    /** SF footnote → Roboto 13. The app's densest ordinary metadata line. */
    val metadata: TextStyle = annotate(13f, FontWeight.Normal, lineHeight = 18f)

    /** SF footnote semibold → Roboto Medium 13 (see note 5 in the header). */
    val metadataEmphasis: TextStyle = annotate(13f, FontWeight.Medium, lineHeight = 18f)

    /**
     * The EYEBROW, and only the eyebrow: over art (`OverArtLabel`), a grouped list's header, a
     * sheet label, Schedule's day headers. Never a shelf header — that is `sectionTitle`.
     *
     * iOS reaches uppercase with `.textCase(.uppercase)` at the call site, not with a small-caps
     * font feature; the Android component uppercases the string. The +1.0 tracking is what makes
     * 11 sp uppercase readable and is not optional.
     *
     * At accessibility sizes this token's component goes `maxLines = 1 → 2` rather than truncating
     * ("nothing truncates at accessibility sizes — the container grows"), which is why it carries a
     * real line height.
     */
    val sectionLabel: TextStyle = annotate(11f, FontWeight.Medium, tracking = 1.0f, lineHeight = 14f)

    /**
     * The BILLBOARD's badge — "NEW EPISODE", "4 EPISODES BEHIND", "TRENDING" — the streaming apps'
     * filled tag, 11-sp bold caps on an amber ground (`HeroBadge`, 4 Sep). A ground, so no amber
     * word is drawn. iOS: `heroBadge` = SF caption2 bold, tracking +0.6.
     */
    val heroBadge: TextStyle = annotate(11f, FontWeight.Bold, tracking = 0.6f, lineHeight = 14f)

    val caption: TextStyle = annotate(11f, FontWeight.Normal, lineHeight = 14f)

    /** Tabular. A counter that re-flows while it counts is a bug you can see. */
    val numberXL: TextStyle =
        annotate(34f, FontWeight.Bold, tracking = -0.50f, lineHeight = 40f, tabular = true)

    /** Tabular. Clocks and countdowns — the reason numerals live on the annotating face at all. */
    val time: TextStyle =
        annotate(15f, FontWeight.Medium, lineHeight = 20f, tabular = true)

    // ---------------------------------------------------------------------------------
    // TYPE BY CONTEXT — the ASSIGNMENT
    //
    // The tokens above are a PALETTE. What follows is the ASSIGNMENT: which token a thing gets
    // because of where it sits. The shipped build set every title to `showTitleM` and every second
    // line to `metadata`, at every altitude, which is why nothing on any screen was allowed to be
    // the hero and nothing was allowed to be quiet.
    //
    //   HERO   (one per screen, the thing the screen is about)
    //     title      heroTitle     Outfit Bold 28 / textPrimary
    //     eyebrow    sectionLabel  11 semibold +1.0 / textTertiary — above the title, never below
    //     meta       heroMeta      Outfit 15 / textSecondary
    //
    //   CARD   (the one card that carries an action)
    //     title      showTitleL    Outfit SemiBold 22 / textPrimary
    //     fact       cardFact      Outfit SemiBold 15 / textPrimary  ← the fact is NOT grey
    //     support    metadata      13 / textTertiary
    //
    //   ROW    (repeating, scannable)
    //     title      rowTitle      Outfit SemiBold 17 / textPrimary, 1 line (2 at AX)
    //     meta       rowMeta       13 / textSecondary
    //     forward    rowMetaLead   13 semibold / accent — only a real next step earns amber
    //
    //   SHELF  (poster + caption)
    //     title      shelfTitle    Outfit Medium 14 / textPrimary, exactly 2 reserved lines
    //     caption    shelfCaption  12 medium / textSecondary (accent when it is a next step)
    //
    //   SECTION
    //     title      sectionTitle  Outfit SemiBold 20 / textPrimary, chevron when it navigates
    //     count      metadata      13 / textTertiary, on the title's baseline
    //     eyebrow    sectionLabel  11 semibold +1.0 — over art and grouped lists only
    //     action     listAction    Outfit SemiBold 13 / interactive  ← an inline link ("Clear");
    //                                                                  NEVER amber
    // ---------------------------------------------------------------------------------

    /** Detail / Today hero. Identity gets the biggest cut in the app after the wordmark. */
    val heroTitle: TextStyle = speak(28f, FontWeight.Bold, -0.55f, 34f)

    /** The genre/network/year line under a hero title ("Anime · 2018 · Action · Adventure"). */
    val heroMeta: TextStyle = speak(15f, FontWeight.Normal, -0.05f, 20f)

    /**
     * Long-form reading text — Detail's synopsis, the one paragraph in the app. Subheadline size,
     * with the leading opened: iOS gets 20 pt of natural leading plus a `lineSpacing(5)` at the
     * call site, so the ported line height is 25. Opening it HERE rather than at the call site is
     * the point — a call site may not declare a size.
     *
     * It was `body`: 17-pt default-leading grey — visually an unstyled `Text` — and TWO POINTS
     * LARGER than the hero's own `heroMeta` line above it, so the type ladder inverted at exactly
     * the step where it should step down (user device, 30 Aug: "the description font looks plain
     * wrong").
     *
     * Deliberately still the ANNOTATING face under the "Outfit speaks" rule: a synopsis is quoted
     * CONTENT, not the app's voice, and a neo-grotesque reads better than a geometric sans over a
     * full paragraph.
     */
    val prose: TextStyle = annotate(15f, FontWeight.Normal, lineHeight = 25f)

    /**
     * The single load-bearing fact on a card ("Season 7 · Episode 2"). Primary ink, not secondary:
     * a fact the whole card exists to deliver may not be rendered in the same grey as its footnote.
     */
    val cardFact: TextStyle = speak(15f, FontWeight.SemiBold, -0.10f, 20f)

    /** Repeating media row title. One line; two at accessibility sizes. */
    val rowTitle: TextStyle = speak(17f, FontWeight.SemiBold, -0.20f, 22f)

    /** Repeating media row metadata. */
    val rowMeta: TextStyle = annotate(13f, FontWeight.Normal, lineHeight = 18f)

    /**
     * A row's forward-looking fact — "Returns Oct 2", "Episode 19 next". THE one place a row is
     * allowed amber, because amber means a real next step. Never used for a tappable word.
     */
    val rowMetaLead: TextStyle = annotate(13f, FontWeight.Medium, lineHeight = 18f)

    /**
     * Shelf caption title under a poster. Exactly two reserved lines at the call site, so the
     * declared line height is what makes two shelves the same height whether their titles wrap or
     * not.
     */
    val shelfTitle: TextStyle = speak(14f, FontWeight.Medium, -0.10f, 18f)

    val shelfCaption: TextStyle = annotate(12f, FontWeight.Medium, lineHeight = 16f)

    /**
     * An inline text action in a section header ("Clear"). Deliberately smaller than [button]: a
     * 16-pt semibold word beside an 11-pt grey label wins a fight it should lose.
     *
     * Rendered in `interactive`, never `accent` — a link is an action, and actions are not amber.
     */
    val listAction: TextStyle = speak(13f, FontWeight.SemiBold, 0f, 18f)

    // ---------------------------------------------------------------------------------
    // CHROME — the port of iOS's UIKit appearance proxies (`AppAppearance`).
    //
    // On iOS a tab-bar item title and a search field's input are drawn by UIKit, so they had to be
    // reached through global appearance proxies installed once at launch ("a proxy is global, so
    // every other segmented control and search field in the app rendered one way before the user
    // had visited that screen and another way after"). On Android both are ordinary composables
    // with a `style`, so the proxy machinery disappears and only the ASSIGNMENT survives — which is
    // this, and which belongs in the type palette like everything else.
    // ---------------------------------------------------------------------------------

    /**
     * Bottom-navigation item label, unselected.
     *
     * iOS uses Outfit Medium **10** because 10 pt is the iOS tab-bar size. Android's navigation
     * labels sit at 12 sp, and at the same physical size Outfit at 10 sp on Android reads as a
     * shrunken iOS tab bar rather than a native one. Re-tuned to 12 so it READS the same, per the
     * fidelity line. Weight and role are unchanged.
     */
    val tabLabel: TextStyle = speak(12f, FontWeight.Medium, 0f, 16f)

    /** Bottom-navigation item label, selected — the weight steps up, exactly as on iOS. */
    val tabLabelSelected: TextStyle = speak(12f, FontWeight.SemiBold, 0f, 16f)

    /**
     * Text-field input (the search field).
     *
     * The annotating face at body size, on purpose: "input in a catalogue field is information, not
     * identity, so it is SF at body size." What the user types is not the app speaking.
     */
    val fieldInput: TextStyle = annotate(17f, FontWeight.Normal, lineHeight = 22f)

    /**
     * The scene-wide inherited style, installed once at the theme root as `LocalTextStyle`.
     *
     * iOS sets `.font(.custom("Outfit-Regular", size: 17, relativeTo: .body))` on the root scene
     * "so any text not already using `.scaledFont` (and SwiftUI TextField input) still renders in
     * the brand typeface, scaled." Same intent: nothing in this app may ever fall back to a
     * platform default face.
     *
     * Colour is deliberately absent — ink is the colour layer's contract, exactly as iOS's
     * `TypeToken` carries no colour. The theme provides both.
     *
     * [body] at zero tracking, not [body] itself: the iOS root font is a bare
     * `.font(.custom(...))` with no `.tracking(...)` beside it, and a token's tracking is a
     * decision taken for the role it was cut for — inheriting one into every unstyled string in
     * the app would be spending it where nobody chose to.
     */
    val appDefault: TextStyle = body.copy(letterSpacing = 0f.sp)
}
