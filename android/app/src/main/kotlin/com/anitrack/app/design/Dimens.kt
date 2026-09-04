package com.anitrack.app.design

import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Outline
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalWindowInfo
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin

/**
 * The spacing SCALE. Which step a given relationship gets is [ThemeMetrics], not this.
 *
 * iOS points and Android dp are the same density-independent unit at 1:1, so these port as-is.
 */
@Immutable
object ThemeSpace {
    val x0_5 = 2.dp
    val x1 = 4.dp
    val x2 = 8.dp
    val x3 = 12.dp
    val x4 = 16.dp
    val x5 = 20.dp
    val x6 = 24.dp
    val x8 = 32.dp
    val x10 = 40.dp
    val x12 = 48.dp
    val x16 = 64.dp
}

/**
 * Corner radii. Every one of these is drawn with a **continuous** (squircle) corner in the design
 * system — see [ContinuousCornerShape] — because that is what the shipped app draws, and a
 * circular arc reads visibly rounder at 22 dp on the app's most-repeated object.
 */
@Immutable
object ThemeRadius {
    /** The 120 × 68 episode tile. */
    val episodeStill = 8.dp

    /** Generic poster corner. */
    val poster = 10.dp

    /** Chips and small controls. */
    val compactControl = 12.dp

    /** Grouped list / row container. */
    val row = 16.dp

    /** Toast + sync-banner capsuloid. */
    val toast = 18.dp

    /** Default `Modifier.surface(...)` radius. */
    val card = 22.dp

    /** Today's Focus / handoff ground. */
    val focusCard = 24.dp
}

/**
 * RHYTHM — which step of [ThemeSpace] a given relationship gets, plus the chrome bands.
 *
 * Spacing is a scale; rhythm is the assignment. Every screen used 16 for everything, which is why
 * the shipped build read as a settings table: a section break, a card gap and a title-to-metadata
 * gap cannot all be the same distance and still say anything. These are the relationships, named
 * once.
 */
@Immutable
object ThemeMetrics {

    // MARK: - Rhythm

    /** Screen side margin. Content, section labels and card edges all align to it. */
    val gutter = 16.dp

    /** Between two SECTIONS. Big enough that the eye takes a breath and re-orients. */
    val sectionGap = 30.dp

    /** Section label → the first thing under it. The label belongs to what follows. */
    val labelGap = 10.dp

    /** Between two sibling cards inside one section. */
    val cardGap = 10.dp

    /** Between shelf items. */
    val shelfGap = 12.dp

    /** Title → its own metadata line. Tight: they are one thought. */
    val titleGap = 3.dp

    /** Art → the text it belongs to. */
    val artGap = 14.dp

    /** Below a hero, before the first content block. */
    val heroClearance = 26.dp

    /**
     * **The** hairline: one device-independent pixel, the same physical thickness as the shipped
     * 1 pt.
     *
     * Every rule, separator and inset stroke in the app is this — a grouped row's separator and a
     * media row's, the edge of a piece of artwork, a capsule's lit top edge, the mark ring's, a
     * field's border, the chrome bar's Reduce-Transparency fallback. It was spelled `1.dp` at
     * thirty call sites in fifteen files, which is thirty chances for "a hairline" to become 1.5
     * somewhere and for the app to draw two thicknesses of the same line.
     *
     * Its colour is [com.anitrack.app.design.ThemeColor.hairline] — the two are the same rule seen
     * from two sides, and each object owns its half.
     *
     * A 1-dp value that is NOT a stroke is not this: a 1-dp copy gap, a 1-dp scroll threshold and
     * the 1-dp node a live region is anchored to keep their own names.
     */
    val hairline = 1.dp

    /**
     * **The** landscape ratio, 16:9. Every wide surface in the app is this and nothing else: the
     * Continue card and the season header (`ProgressBanner`), Schedule's `AiringCard` AND the
     * skeleton that stands in for it, an episode still, a trailer.
     *
     * It lived in four places, and one of those pairs was a card and the skeleton that is supposed
     * to mirror it reading two different constants — which is exactly how the swap from skeleton to
     * card comes to change shape. `PosterSize.posterAspectRatio` is its portrait twin.
     *
     * A `Float` for `Modifier.aspectRatio`, which takes width ÷ height.
     */
    const val wideAspect = 16f / 9f

    // MARK: - Row heights
    //
    // A row's height is set by its ART, not by a hairline grid: 68 dp everywhere is what makes a
    // media app look like a list of settings.

    /** Text-only or 40-dp-art rows (menus, selection lists). */
    val rowCompact = 56.dp

    /** The standard media row: 48 × 72 poster. */
    val rowStandard = 88.dp

    /** The heavier media row: 56 × 84 poster, two-line title allowed. */
    val rowMedia = 100.dp

    /** Episode row carrying a 96 × 54 still. */
    val rowEpisode = 82.dp

    /**
     * Where a poster row's hairline starts — the title's leading edge. Schedule's day-header rule
     * and All titles' letter-header rule share it, and each had computed it privately.
     *
     * [gutter] (16) + the row poster's width (60) + [artGap] (14) = 90.
     */
    val rowRuleInset: Dp = gutter + PosterSize.Row.size.width + artGap

    // MARK: - Chrome edges
    //
    // Every root screen in the shipped build scrolled its content straight through the status bar:
    // a poster and a show title on top of the clock with nothing between them. No shipping media
    // app does this. The fix is systemic, not per-screen — one chrome surface owns all of it.

    /**
     * How far BELOW the status bar the veil takes to disappear. Short and hard on purpose: it must
     * clear a large title that sits just underneath, so it may not be a lazy 120-dp wash.
     */
    val topChromeRamp = 22.dp

    /** The inline navigation bar's own height, below the status bar. */
    val inlineBarHeight = 44.dp

    /**
     * The ramp under a HARDENED top veil — the band in which content scrolling out from under an
     * opaque bar goes from hidden to fully lit. Short, like a material bar's own edge.
     *
     * The veils used to hold opaque canvas through the status bar only and then ramp out over
     * 22–150 pt — straight through the title bar, so a row title sat half-lit UNDER "Library" and
     * a hero's support line ghosted under Today's handed-over title. A bar is opaque to its bottom
     * edge and content is either under it or not; the only soft part is this edge.
     */
    val barEdgeRamp = 28.dp

    /**
     * The hardened bar's canvas over its blur — a BAR, not a slab. What has scrolled under the
     * title stays faintly alive through the blur, the way a material bar keeps the content behind
     * it present. At 1.0 the top ~100 pt of every scrolled screen was a flat #09090B rectangle
     * with a 28-pt edge ("the top area becomes pure black", user, 3 Sep) and the material painted
     * under it was doing nothing at all.
     *
     * **Android:** the no-blur state is not an accessibility preference here, it is a capability —
     * `Modifier.blur` is a *silent no-op* below API 31, so a naive call yields a transparent bar,
     * the one outcome the design forbids. "Device cannot blur" and "user asked for reduced
     * transparency" are ONE boolean, resolved once, and that state gets [chromeBarOpacityOpaque].
     */
    val chromeBarOpacity = 0.74f

    /**
     * The hardened bar with no blur beneath it. There is nothing softening what is under the veil,
     * so it is opaque — a 74 % veil over bare content is the half-lit row under "Library" that the
     * hardened bar was built to end.
     */
    val chromeBarOpacityOpaque = 1.0f

    /**
     * The height a search drawer adds under an inline title. Search and All titles both size their
     * top veil past it; each carried a private 52 before the token existed.
     */
    val searchDrawerHeight = 52.dp

    /**
     * The ramp that carries content out of sight before it reaches the bottom bar. 64 is the
     * bar's own height, and both larger values were measured failures:
     *
     * 116 started the ramp ~100 pt above the bar's top edge, so half of it did nothing but dim
     * readable content, while the bar's own glass rim still had un-occluded body copy to refract
     * (the mirrored text that reads as GPU corruption).
     *
     * 140 said the same thing in a comment and did not do it: at rest, with no scrolling, the ramp
     * erased Today's `WATCHING` label (1.26:1), an interactive `See all` (1.42:1), four lines of
     * Detail's synopsis (4.39 → 1.04:1) and Search's sixth `+` button. Apple's own scroll-edge
     * effect fades ~30–54 pt directly behind an opaque bar and never erases 140 pt of visible text.
     *
     * **Android:** this is the ramp above the app's bottom bar CHASSIS. The system navigation-bar
     * inset is separate and is added by the bar itself — never folded in here, or the ramp grows
     * on a 3-button device and shrinks on a gesture one for no reason a reader could name.
     */
    val bottomChromeHeight = 64.dp

    /**
     * Solid canvas over-drawn BELOW the ramp, behind the bar and across the gesture strip.
     *
     * On iOS a `TabView` insets its children's safe area by the bar, so a bottom-aligned overlay's
     * bottom edge is the bar's TOP edge, and content rendered at full brightness underneath it
     * with live chevrons in the home-indicator strip. Over-drawing past the layout's edge was the
     * only honest fix.
     *
     * **Android:** an edge-to-edge window hands the app the whole screen, so this is simply the
     * height of opaque canvas painted behind the bottom bar and the navigation-bar inset together.
     * 180 is generous by construction — it is over-draw, not layout, and nothing measures it.
     */
    val bottomUnderfill = 180.dp

    /**
     * Scroll bottom inset. The rule is [bottomChromeHeight] + one gutter, and it is only ever that.
     *
     * At 152 against a 140-dp ramp the clearance was itself the bug it was defending against: it
     * cost every screen 152 dp of vertical space *and* still let the ramp erase live content,
     * because the ramp was the thing that was too tall.
     */
    val tabBarClearance: Dp = bottomChromeHeight + ThemeSpace.x3

    /**
     * The bottom bar's VISUAL height — the bar plus the gesture strip under it.
     *
     * This is the divisor for optically centring a state block, and it is **not**
     * [tabBarClearance]: subtracting a scroll inset when centring pushed every empty state ~81 dp
     * above true centre on Today and Schedule.
     */
    val tabBarVisualHeight = 90.dp

    /**
     * How far above the safe area's bottom edge a floating toast sits, so it clears the bar
     * instead of landing on it: the 52-dp bar plus a 10-dp gap.
     *
     * One value for all four tabs. The search island was assumed to be taller than the bar and
     * measured is not, so a second, larger constant for that tab would have moved the toast 24 dp
     * for no reason and made one tab's chrome sit differently from the other three.
     */
    val toastClearance = 62.dp

    // MARK: - The ambient wash
    //
    // The three roots shipped with 300/0.3, 380–520/0.5–0.68 and 400/0.68, so the same atmosphere
    // was a whisper on one tab and a stain on the next — and by the cohesion pass the tree had
    // re-diverged into seven configurations. The rule from here: EVERY ambient wash uses this pair
    // — tab roots, pushed lists (Season episodes, Watch history), and Today's no-hero states
    // alike. A screen may not carry a private wash spec; Today's full-bleed hero is the one
    // composition that replaces the wash outright.

    /** THE ambient-wash height, app-wide. */
    val rootWashHeight = 320.dp

    /** THE ambient-wash strength, app-wide. */
    val rootWashIntensity = 0.4f

    // MARK: - Window-derived metrics
    //
    // iOS read these once from the key window and cached them, guarding against caching a
    // pre-window default (59 / 852) forever. Compose has no pre-window read — an inset and a
    // container size are always available inside composition, and they update themselves on a
    // rotation, a fold or a multi-window resize — so the cache and its guard are not ported.
    // Reading lazily inside composition IS the native answer.

    /**
     * The status-bar inset — the height of the band the clock lives in.
     *
     * A layout measurement cannot supply this: the chrome is drawn OVER content that already sits
     * inside the inset, so a local measurement reports zero. Reading the window inset is the
     * honest way to know how tall that band actually is.
     *
     * Requires an edge-to-edge window (`enableEdgeToEdge()` in `MainActivity`); with the status
     * bar genuinely hidden this is 0 and the top chrome collapses to [topChromeRamp], which is
     * correct.
     */
    // NOT @ReadOnlyComposable: `WindowInsets.statusBars` is a plain @Composable getter
    // (it resolves through WindowInsetsHolder), so a read-only frame cannot call it.
    @Composable
    fun topSafeInset(): Dp {
        val insets = WindowInsets.statusBars
        val density = LocalDensity.current
        return with(density) { insets.getTop(density).toDp() }
    }

    /** Total height of the top chrome, status-bar inset included. */
    // NOT @ReadOnlyComposable: `WindowInsets.statusBars` is a plain @Composable getter
    // (it resolves through WindowInsetsHolder), so a read-only frame cannot call it.
    @Composable
    fun topChromeHeight(): Dp = topSafeInset() + topChromeRamp

    /** The bar's full band: status bar + inline bar. What a root's hardened veil holds through. */
    // NOT @ReadOnlyComposable: `WindowInsets.statusBars` is a plain @Composable getter
    // (it resolves through WindowInsetsHolder), so a read-only frame cannot call it.
    @Composable
    fun inlineBarBottom(): Dp = topSafeInset() + inlineBarHeight

    /**
     * The window's height, insets included. Billboard heroes are sized as a fraction of the SCREEN
     * (status bar included), which no inner layout can report.
     *
     * `LocalWindowInfo.containerSize` is the container the app is actually drawing into, so it is
     * correct in split-screen and on a fold where a screen-metrics constant would not be.
     */
    @Composable
    @ReadOnlyComposable
    fun windowHeight(): Dp {
        val info = LocalWindowInfo.current
        val density = LocalDensity.current
        return with(density) { info.containerSize.height.toDp() }
    }

    /**
     * The scroll offset a screen's chrome actually NEEDS, for writing back to state.
     *
     * Every veil, mask and title handover saturates within the first ~120 dp of scroll and the
     * pull-down stretch within ~300 dp; past that the offset changes nothing on screen. Writing
     * the raw offset on every frame re-evaluated Today's whole body — the stack, the queue, the
     * shelf, the upcoming rows, every row diff — at 60–120 Hz for the entire length of the scroll,
     * which is the jank the user felt (2 Sep, twice). Clamped and rounded to the half-point, the
     * value stops changing once the chrome has settled, so the body stops re-running.
     *
     * **The Android discipline is the same and then some:** hold the offset in a `MutableState`
     * that only a deferred read (`Modifier.graphicsLayer { }` / `Modifier.drawBehind { }`)
     * touches, never a value read in a composable that draws the screen — and still quantise
     * before writing, so a settled chrome writes nothing at all. Callers guard `if (v != scrollY)`.
     *
     * @param y offset in **dp** — convert from px at the call site, because quantising raw pixels
     *   would quantise to a different real distance on every density.
     */
    fun scrollSample(y: Float, lowerBound: Float = -320f, upperBound: Float = 240f): Float {
        val doubled = y.coerceIn(lowerBound, upperBound) * 2f
        // Swift's `.rounded()` is half-AWAY-from-zero; Kotlin's `roundToInt` is half-up, and the
        // two differ for negative halves — which is the whole pull-down range.
        val rounded =
            if (doubled < 0f) -kotlin.math.floor(-doubled + 0.5f) else kotlin.math.floor(doubled + 0.5f)
        return rounded / 2f
    }
}

/**
 * Artwork slots, named by CONTEXT rather than by number, so no screen has to remember a size.
 *
 * Art is this product's only real material — every one of these is at or above the size the
 * shipped build used, never below.
 *
 * **One row slot.** Library rows were 48 × 72, Search rows 60 × 90 and Schedule built its own
 * 56 × 84 by hand — three poster sizes for the one object the app renders most. [Row] is now the
 * single list-row slot for Library, Search and Schedule; [Queue] stays for Today's compact queue,
 * which is a different, denser object under the hero.
 *
 * Every slot is 2:3 ([posterAspectRatio]) and posters are **aspect-filled, never fitted**. Source
 * posters are ~0.708, so a ~4 % height crop is taken; fitting instead produced a 5–6 dp bar of
 * exact `surfaceRaised` grey across the top and bottom of every image.
 *
 * @property size the slot's drawn size.
 * @property radius radius tracks size: a 10-dp radius on a 34-dp slot is a blob, on a 112-dp slot
 *   it is sharp.
 * @property shadow only art large enough to read as an object earns a contact shadow.
 */
enum class PosterSize(val size: DpSize, val radius: Dp, val shadow: ShadowToken) {

    /** Detail hero. The largest identity object in the app. */
    Hero(DpSize(112.dp, 168.dp), 12.dp, ShadowToken.ArtHero),

    /**
     * Library's cover-flow carousel card. Kept in the slot table so its geometry never lives in a
     * per-screen metrics object again (it shipped there at r18, a radius no token names).
     *
     * The cover-flow spotlight this sized was retired in the 3 Sep cohesion pass — Library's lead
     * surface is a landscape Up Next shelf now. The slot stays declared and unused rather than
     * being re-derived by hand the next time something wants a 192-wide card.
     */
    LibraryHero(DpSize(192.dp, 288.dp), 14.dp, ShadowToken.ArtHero),

    /** Today's Focus / Recap card. */
    Focus(DpSize(88.dp, 132.dp), 10.dp, ShadowToken.Art),

    /**
     * Library "Returning" shelf, Search trending.
     *
     * 124, not 100, is deliberate: widened so a shelf caption's first line carries a real WORD. At
     * 100 dp "That Time I Got Reincarnated as a Slime" broke as "That Time I / Got Reincarn…" and
     * "Re:ZERO / -Starting Life…" opened a line on a hyphen — the app truncating an identity title
     * on one screen while Library's rows render the same title whole.
     */
    ShelfLarge(DpSize(124.dp, 186.dp), 12.dp, ShadowToken.Art),

    /** Today "Watching" shelf. */
    ShelfMedium(DpSize(112.dp, 168.dp), 12.dp, ShadowToken.Art),

    /**
     * Today's denser resting shelf. The hero already owns the first visual beat, so this shelf
     * must read as supporting context rather than a second wall of key art.
     */
    TodayShelf(DpSize(100.dp, 150.dp), 11.dp, ShadowToken.Art),

    /** THE list row — Library, Search and Schedule. */
    Row(DpSize(60.dp, 90.dp), 10.dp, ShadowToken.None),

    /**
     * Today's actionable queue: recognisable at a glance without inheriting a catalogue row's full
     * 100-dp height.
     */
    TodayQueue(DpSize(52.dp, 78.dp), 9.dp, ShadowToken.None),

    /** Today's compact queue rows under the hero. */
    Queue(DpSize(44.dp, 66.dp), 8.dp, ShadowToken.None),

    /** A recap beat — the smallest slot that still reads as a show. */
    Beat(DpSize(34.dp, 51.dp), 6.dp, ShadowToken.None);

    val width: Dp get() = size.width
    val height: Dp get() = size.height

    companion object {
        /** 2:3. Every slot in the table satisfies this exactly. */
        val posterAspectRatio = 2f / 3f
    }
}

/**
 * A **continuous** (squircle) corner — the shape every rounded rectangle in the design system is
 * drawn with, because that is what the shipped app draws.
 *
 * Compose's `RoundedCornerShape` is a circular arc. At [ThemeRadius.card] (22 dp), on the app's
 * most-repeated object, the difference is visible: the arc reads noticeably rounder and softer,
 * and a wall of them reads like a different product. This emits a superellipse quadrant
 * (exponent ≈ 5) per corner instead.
 *
 * Below [minVisibleCornerRadius] the two are indistinguishable, so a plain `RoundedCornerShape` is
 * returned and no path is built.
 *
 * ### Shadows
 *
 * A generic-path outline only casts a native elevation shadow from API 29; below that the platform
 * silently draws nothing, and this app's floor is 26. Cast the shadow from a `RoundedCornerShape`
 * of the same radius and clip the content with this — the silhouette difference under a blurred
 * shadow is invisible, and the shadow then exists on every supported device. [Modifier.surface]
 * already does exactly that.
 */
@Suppress("FunctionName")
fun ContinuousCornerShape(radius: Dp): Shape =
    if (radius < minVisibleCornerRadius) RoundedCornerShape(radius) else ContinuousRoundedShape(radius)

/** Under this a squircle and a circular arc are the same shape to the eye. */
val minVisibleCornerRadius = 12.dp

/** Exponent of the superellipse |x/r|ⁿ + |y/r|ⁿ = 1. n = 2 is a circle; n ≈ 5 reads as Apple's. */
private const val SUPERELLIPSE_EXPONENT = 5.0

/** Segments per corner. 12 is past the point where another one changes a rendered pixel. */
private const val CORNER_SEGMENTS = 12

@Immutable
private data class ContinuousRoundedShape(val radius: Dp) : Shape {

    override fun createOutline(size: Size, layoutDirection: LayoutDirection, density: Density): Outline {
        val r = with(density) { radius.toPx() }.coerceAtMost(min(size.width, size.height) / 2f)
        if (r <= 0f) return Outline.Rectangle(Rect(0f, 0f, size.width, size.height))
        return Outline.Generic(superellipsePath(size.width, size.height, r))
    }
}

/**
 * The rounded rectangle, corner by corner, walked clockwise from the top-left corner's start on
 * the left edge. Each corner is the superellipse quadrant inscribed in its own r × r box.
 *
 * The path is convex, which also keeps it cheap to clip.
 */
private fun superellipsePath(w: Float, h: Float, r: Float): Path {
    val e = 2.0 / SUPERELLIPSE_EXPONENT
    // (u, v) walks one quadrant: (u/r)ⁿ + (v/r)ⁿ = 1, u from r → 0 while v goes 0 → r.
    val u = FloatArray(CORNER_SEGMENTS + 1)
    val v = FloatArray(CORNER_SEGMENTS + 1)
    for (i in 0..CORNER_SEGMENTS) {
        val theta = (PI / 2.0) * i / CORNER_SEGMENTS
        u[i] = (r * abs(cos(theta)).pow(e)).toFloat()
        v[i] = (r * abs(sin(theta)).pow(e)).toFloat()
    }

    return Path().apply {
        // Top-left: left edge (0, r) → top edge (r, 0). Corner centre (r, r).
        moveTo(0f, r)
        for (i in 1..CORNER_SEGMENTS) lineTo(r - u[i], r - v[i])

        lineTo(w - r, 0f)
        // Top-right: top edge (w−r, 0) → right edge (w, r). Corner centre (w−r, r).
        for (i in 1..CORNER_SEGMENTS) lineTo(w - r + v[i], r - u[i])

        lineTo(w, h - r)
        // Bottom-right: right edge (w, h−r) → bottom edge (w−r, h). Corner centre (w−r, h−r).
        for (i in 1..CORNER_SEGMENTS) lineTo(w - r + u[i], h - r + v[i])

        lineTo(r, h)
        // Bottom-left: bottom edge (r, h) → left edge (0, h−r). Corner centre (r, h−r).
        for (i in 1..CORNER_SEGMENTS) lineTo(r - v[i], h - r + u[i])

        close()
    }
}
