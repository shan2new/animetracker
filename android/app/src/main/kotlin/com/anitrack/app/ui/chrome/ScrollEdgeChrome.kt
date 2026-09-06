/*
 * The scroll edge — the veil, exactly.
 *
 * The single most damaging detail in the shipped build was invisible in a design tool and obvious
 * on a device: CONTENT SCROLLS STRAIGHT THROUGH THE STATUS BAR. On Schedule a poster and a
 * truncated show title sat on top of the clock; on Library a poster crossed the Dynamic Island. No
 * shipping media app does this, and no amount of card polish survives it.
 *
 * The fix is one veil per screen: full canvas through the bar's band, gone a short ramp below it.
 * Content does not slide under a grey bar — it dissolves into the app, because the veil's colour IS
 * the canvas. A blurred copy of the backdrop rides along, masked to the same band, so what is
 * dissolving also softens; where the platform cannot blur (or the user has asked it not to) the
 * material is dropped and the canvas veil does the whole job on its own.
 *
 * ## Three invariants. A build that breaks any of them is wrong even if it compiles.
 *
 * 1. A BAR IS OPAQUE TO ITS BOTTOM EDGE and content is either under it or not. The only soft part
 *    is a `barEdgeRamp` (28 dp) below the bar. Never a 120–150 dp wash.
 * 2. A HARDENED BAR IS TRANSLUCENT (`chromeBarOpacity`, 0.74) OVER A FULL-STRENGTH BLUR. At 1.0
 *    with a blur underneath, the top ~100 dp of every scrolled screen is a flat #09090B slab ("the
 *    top area becomes pure black", user, 3 Sep) and the material painted under it is doing nothing
 *    at all. Only the no-material path — Reduce transparency, or API < 31 — gets the opaque bar.
 * 3. THE SCROLL OFFSET IS NEVER SCREEN STATE. It is quantised through `ThemeMetrics.scrollSample`
 *    and read at DRAW time (`drawBehind` / `graphicsLayer`) or inside a `derivedStateOf`, never in
 *    the body of the composable that draws the screen. The raw offset in screen state re-ran
 *    Today's whole body at 60–120 Hz for the length of every swipe (user, 2 Sep, twice).
 *
 * ## And one rule about mounting
 *
 * NEVER HOLD A MATERIAL LAYER AT ALPHA 0. A `hazeEffect` at zero alpha still captures and still
 * blurs, every frame, for nothing. The soft⇄hard swap below is a cross-fade whose layers are
 * mounted only while they are visible or animating; `Today`'s and `Detail`'s own veils follow the
 * same rule with a conditional mount.
 */
package com.anitrack.app.ui.chrome

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.offset
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.anitrack.app.design.ThemeColor
import com.anitrack.app.design.ThemeMetrics
import com.anitrack.app.design.ThemeMotion

// ---------------------------------------------------------------------------------------------
// The top band
// ---------------------------------------------------------------------------------------------

/**
 * The status-bar edge: a canvas veil over a masked blur of whatever is scrolling underneath.
 *
 * Two shapes, chosen by [soft]:
 *
 * * **soft** — the AT-REST edge of an art-backed screen. The wash runs to the very top of the
 *   screen under a translucent gradient that only softens it (Apple Music's Search is the
 *   reference). Nothing is held opaque.
 * * **hard** (the default) — the bar. Full bar canvas through the whole of [holdHeight], then out
 *   over the rest of [height]. This is what a row title passing under "Library" needs.
 *
 * **Geometry.** [height] is the band's TOTAL height, status-bar inset included, and this composable
 * expects to be aligned to the top of a container that has *not* consumed the status-bar inset —
 * the Compose reading of iOS's `.ignoresSafeArea(edges: .top)`. [ScrollEdgeChromeBox] arranges
 * that; a screen mounting this by hand must.
 *
 * **Touch and TalkBack.** It draws and does nothing else: no pointer-input node, so taps pass
 * straight through to the content beneath, and `clearAndSetSemantics` keeps the whole decoration
 * out of the accessibility tree. Meaning is carried by the content, never by the veil.
 *
 * `Today` and `Detail` mount this directly rather than through [ScrollEdgeChromeBox], because their
 * soft layer's opacity is driven by the scroll offset rather than by a boolean:
 * `TopScrollEdgeChrome(Modifier.align(Alignment.TopCenter).graphicsLayer { alpha = veilOpacity })`.
 * Reading the offset inside `graphicsLayer`'s lambda is what keeps the read at draw time.
 *
 * @param height total band height, status-bar inset included.
 * @param soft no solid hold — a translucent gradient only.
 * @param holdHeight how far down full bar canvas holds before the ramp starts; `null` means the
 *   status bar. `Detail`'s floating toolbar passes the toolbar's own bottom edge. Ignored when
 *   [soft] is true.
 */
@Composable
fun TopScrollEdgeChrome(
    modifier: Modifier = Modifier,
    height: Dp = ThemeMetrics.topChromeHeight(),
    soft: Boolean = false,
    holdHeight: Dp? = null,
    /**
     * The bar's ink when it is not the canvas — a show page passes its art colour
     * (`DetailTint.chrome`) so the hardened bar is the show's own glass, not a black slab over the
     * picture ("too blackish anyway, should be glassish", user, 4 Sep). Ignored where there is no
     * material for a colour to be glass over.
     */
    ink: Color? = null,
) {
    val topSafeInset = ThemeMetrics.topSafeInset()
    val canUseMaterial = LocalCanUseMaterial.current
    val veilInk = (if (canUseMaterial) ink else null) ?: ThemeColor.chromeVeil

    // `hold` is a gradient STOP — a fraction of `height` — not a length.
    val hold = ((holdHeight ?: topSafeInset) / height.coerceAtLeast(1.dp)).coerceIn(0f, 1f)

    // The bar is 0.74 canvas over a full-strength blur. With no blur beneath it there is nothing
    // softening what is under the veil, so it goes opaque: a 74 % veil over bare content is the
    // half-lit row under "Library" that the hardened bar was built to end.
    val bar =
        if (canUseMaterial) ThemeMetrics.chromeBarOpacity
        else ThemeMetrics.chromeBarOpacityOpaque

    val blurMask = remember(soft, hold) { topBlurMask(soft, hold) }
    val veil = remember(soft, hold, bar, veilInk) { topVeil(soft, hold, bar, veilInk) }

    Box(
        modifier
            .fillMaxWidth()
            .height(height)
            // Blur under, canvas veil over: an outer draw modifier paints first and then calls
            // through to the inner one.
            .chromeBandMaterial(blurMask)
            .drawBehind { drawRect(veil) }
            .clearAndSetSemantics {}
    )
}

/**
 * Canvas opacity from the screen's top edge inward.
 *
 * All stops are [ThemeColor.chromeVeil] — the canvas itself — so the handover is invisible.
 */
private fun topVeil(soft: Boolean, hold: Float, bar: Float, ink: Color = ThemeColor.chromeVeil): Brush = if (soft) {
    Brush.verticalGradient(
        0f to ThemeColor.chromeVeil.copy(alpha = 0.55f),
        0.5f to ThemeColor.chromeVeil.copy(alpha = 0.30f),
        1f to ThemeColor.chromeVeil.copy(alpha = 0f),
    )
} else {
    Brush.verticalGradient(
        0f to ink.copy(alpha = bar),
        hold to ink.copy(alpha = bar),
        (hold + (1f - hold) * 0.45f) to ink.copy(alpha = bar * 0.45f),
        1f to ink.copy(alpha = 0f),
    )
}

/**
 * The blur mask.
 *
 * It runs out on EXACTLY the same ramp as the veil and reaches zero at the same place. A mask that
 * terminates while the veil is still at a third leaves a visible seam straight across the screen —
 * which is precisely what a hand-rolled scroll edge looks like.
 *
 * The hard variant is at full strength through the WHOLE hold: the bar is translucent now, so the
 * blur is what keeps a row title under it from reading as a row title.
 */
private fun topBlurMask(soft: Boolean, hold: Float): Brush = if (soft) {
    Brush.verticalGradient(
        0f to Color.Black.copy(alpha = 0.6f),
        0.5f to Color.Black.copy(alpha = 0.3f),
        1f to Color.Transparent,
    )
} else {
    Brush.verticalGradient(
        0f to Color.Black,
        hold to Color.Black,
        (hold + (1f - hold) * 0.45f) to Color.Black.copy(alpha = 0.42f),
        1f to Color.Transparent,
    )
}

// ---------------------------------------------------------------------------------------------
// The bottom band
// ---------------------------------------------------------------------------------------------

/**
 * The bottom-bar edge: a 64-dp ramp that carries content out of sight, plus 180 dp of solid canvas
 * over-drawn past the layout's bottom edge.
 *
 * **Align it to the bottom of the content area** (`Modifier.align(Alignment.BottomCenter)`); the
 * over-draw is baked in.
 *
 * ### The over-draw, and why it is not optional
 *
 * A Compose `Scaffold` insets its content by the bottom bar exactly as a SwiftUI `TabView` does, so
 * a bottom-aligned overlay's bottom edge is the BAR'S TOP EDGE, not the screen's. On iOS that gap
 * was measured: content rendering at full brightness underneath the bar (236/255 on Library against
 * 59 one row above it) with live chevrons in the home-indicator strip. Over-drawing past the
 * layout's edge is the only honest fix, and the bar — drawn above its children — passes over it and
 * gets an opaque ground beneath itself in the bargain. PLAN D21 keeps this on Android.
 *
 * The 244-dp stack is therefore offset DOWN by `bottomUnderfill`, so the 64-dp ramp's bottom edge
 * lands exactly on the container's bottom edge and 180 dp of solid canvas continues below it,
 * behind the bar and across the gesture strip. **The host must not clip its bounds** — a plain
 * `Box` does not, which is what [ScrollEdgeChromeBox] uses.
 *
 * ### Why the band is the bar's own height
 *
 * Both larger values were measured failures. Capping the ramp's canvas at 0.78 left the bar's rim
 * with un-occluded body copy to refract and it duly mirrored legible upside-down text back (a
 * second amber "Read more" on Detail, a doubled show title on Search) — a frame that reads as GPU
 * corruption; glass needs opaque canvas underneath it, not a 78 % veil. Going the other way and
 * reaching full canvas at 0.86 of *140 pt* solved the refraction by erasing the content: a "See
 * all" link at 1.42:1 and a live "+" button at 131/241, at rest, with nothing scrolled. Both
 * failures are the same mistake — the band's HEIGHT — so the stops stay hard and the band is the
 * bar's own 64.
 *
 * The system navigation-bar inset is deliberately NOT folded into the ramp: the bar chassis adds
 * it. Folding it in would grow the ramp on a 3-button device and shrink it on a gesture one for no
 * reason a reader could name.
 */
@Composable
fun BottomScrollEdgeChrome(modifier: Modifier = Modifier) {
    val blurMask = remember { bottomBlurMask() }
    val veil = remember { bottomVeil() }

    // The bar chassis: its 64-dp row of tabs, plus the system navigation-bar inset it pads itself
    // with. See the offset below — this is the height the stack has to clear, and it is read rather
    // than assumed because it is 0 on a gesture device and ~48 dp on a 3-button one.
    val barChassis = ThemeMetrics.bottomChromeHeight +
        WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding()

    Column(
        modifier
            .fillMaxWidth()
            // The stack is bottom-aligned, so without an offset its 244 dp end AT the container's
            // bottom edge — which on iOS is the bar's top edge (a `TabView` insets its children's
            // safe area) but on an EDGE-TO-EDGE Android window is the bottom of the screen. Offset
            // by the underfill alone, the whole 64-dp ramp landed behind the navigation strip and
            // the tab row had raw content behind it: on Today a queue row's title crossed
            // "Schedule", "Library" and "Search" at full brightness, and on Schedule an airing
            // card's episode line did the same.
            //
            // Lifting by the chassis puts the ramp's opaque bottom edge on the BAR'S TOP EDGE,
            // which is what the iOS geometry means, and leaves the 180 dp of solid canvas to cover
            // the tab row and the gesture strip together — the "already opaque canvas" the
            // transparent bar in `TabBar.kt` is documented as sitting on.
            .offset(y = ThemeMetrics.bottomUnderfill - barChassis)
            .clearAndSetSemantics {}
    ) {
        Box(
            Modifier
                .fillMaxWidth()
                .height(ThemeMetrics.bottomChromeHeight)
                .chromeBandMaterial(blurMask)
                .drawBehind { drawRect(veil) }
        )
        Box(
            Modifier
                .fillMaxWidth()
                .height(ThemeMetrics.bottomUnderfill)
                .background(ThemeColor.chromeVeil)
        )
    }
}

/**
 * Held flat to 0.44 (≈28 dp above the bar) so nothing in the last readable line is touched at all,
 * then a fast run to opaque. It reaches FULL canvas, and reaches it before the bar's top edge — but
 * only in the last ~10 dp of a 64-dp band, not across 140 dp of readable screen.
 */
private fun bottomVeil(): Brush = Brush.verticalGradient(
    0f to ThemeColor.chromeVeil.copy(alpha = 0f),
    0.55f to ThemeColor.chromeVeil.copy(alpha = 0.25f),
    0.85f to ThemeColor.chromeVeil.copy(alpha = 0.75f),
    1f to ThemeColor.chromeVeil,
)

/**
 * Re-stopped WITH the veil, not independently: a blur that keeps lifting where the veil has already
 * stopped is a second, invisible ramp — and it was the half that was actually measured softening
 * live body copy 137 pt above the bar.
 */
private fun bottomBlurMask(): Brush = Brush.verticalGradient(
    0f to Color.Transparent,
    0.55f to Color.Black.copy(alpha = 0.30f),
    0.85f to Color.Black.copy(alpha = 0.75f),
    1f to Color.Black,
)

// ---------------------------------------------------------------------------------------------
// The screen scaffold
// ---------------------------------------------------------------------------------------------

/**
 * Give a scrolling screen its status-bar and bottom-bar edges. The port of `scrollEdgeChromeBody`.
 *
 * ```
 * ScrollEdgeChromeBox(softTop = true, topRaised = raised, topHold = ThemeMetrics.inlineBarBottom()) {
 *     ArtBackdrop(...)
 *     LazyColumn(
 *         Modifier.chromeHazeSource(),
 *         contentPadding = tabBarContentPadding(),
 *     ) { … }
 * }
 * ```
 *
 * The box must **not** consume the status-bar inset and must not clip (a plain `Box` does neither),
 * because the top band draws into the status bar and the bottom band draws past the box's bottom
 * edge on purpose.
 *
 * ### The ambient wash is not drawn here
 *
 * This box draws chrome and nothing else. The art-adaptive wash is `ArtBackdrop`, mounted by the
 * screen as its first child, and there is exactly ONE spec for it app-wide —
 * `ThemeMetrics.rootWashHeight` (320) and `ThemeMetrics.rootWashIntensity` (0.4), for tab roots and
 * pushed lists alike. A screen may not carry a private height/intensity pair: the three roots once
 * shipped 300/0.3, 380–520/0.5–0.68 and 400/0.68, so the same atmosphere was a whisper on one tab
 * and a stain on the next, and by the cohesion pass the tree had re-diverged into seven
 * configurations. Today's full-bleed hero is the one composition that replaces the wash outright.
 *
 * ### The soft ⇄ hard swap
 *
 * A soft top is the at-rest edge. The moment content scrolls under the BAR — not under the clock —
 * the veil hardens: bar canvas through the whole of [topHold] (status bar + inline title, plus the
 * search drawer where there is one), then out over `barEdgeRamp`. It used to hold through the
 * status bar only and ramp across the title, which is exactly where a row's progress line was
 * photographed ghosting under "Library" (2 Sep).
 *
 * Note the asymmetry: the soft layer's height is the caller's [topHeight]; the hard layer's is
 * always `topHold + barEdgeRamp`, computed independently. They are different heights on purpose.
 *
 * The swap is a 220 ms opacity cross-fade on `uiGentle`, and it is deliberately NOT routed through
 * `pickMotion`: an opacity cross-fade with no travel is already Reduce-Motion-safe, and Compose
 * additionally collapses every app-driven animation to its first frame when the system animator
 * scale is 0. Each layer is mounted only while it is visible or animating — never held at alpha 0,
 * where a material still costs a capture and a blur every frame.
 *
 * @param edges which edges to draw. `Bottom` is a screen whose top is owned by something else
 *   (Schedule's ticker, a real navigation bar).
 * @param topHeight the SOFT layer's total height, status-bar inset included.
 * @param softTop draw the at-rest soft edge and cross-fade to the bar; otherwise the bar is always
 *   drawn.
 * @param topRaised has content passed under the bar? Screens drive it from a scroll probe, and
 *   guard the write with `if (new != old)`.
 * @param topHold the bar's full band that the hardened veil holds bar canvas through. `null` means
 *   the status bar, for a screen whose title sits in its own chrome band.
 */
@Composable
fun ScrollEdgeChromeBox(
    modifier: Modifier = Modifier,
    edges: ChromeEdge = ChromeEdge.All,
    topHeight: Dp = ThemeMetrics.topChromeHeight(),
    softTop: Boolean = false,
    topRaised: Boolean = false,
    topHold: Dp? = null,
    content: @Composable BoxScope.() -> Unit,
) {
    val drawsTop = edges != ChromeEdge.Bottom
    val drawsBottom = edges != ChromeEdge.Top

    Box(modifier) {
        content()

        if (drawsBottom) {
            BottomScrollEdgeChrome(Modifier.align(Alignment.BottomCenter))
        }

        if (drawsTop) {
            if (softTop) {
                val hold = topHold ?: ThemeMetrics.topSafeInset()
                AnimatedVisibility(
                    visible = !topRaised,
                    modifier = Modifier.align(Alignment.TopCenter),
                    enter = fadeIn(ThemeMotion.uiGentle()),
                    exit = fadeOut(ThemeMotion.uiGentle()),
                    label = "scrollEdgeSoftTop",
                ) {
                    TopScrollEdgeChrome(height = topHeight, soft = true)
                }
                AnimatedVisibility(
                    visible = topRaised,
                    modifier = Modifier.align(Alignment.TopCenter),
                    enter = fadeIn(ThemeMotion.uiGentle()),
                    exit = fadeOut(ThemeMotion.uiGentle()),
                    label = "scrollEdgeHardTop",
                ) {
                    TopScrollEdgeChrome(
                        height = hold + ThemeMetrics.barEdgeRamp,
                        soft = false,
                        holdHeight = hold,
                    )
                }
            } else {
                // `topHold` is forwarded here where iOS drops it. No shipped caller passes a hold
                // without `softTop`, so every existing screen renders identically; forwarding it
                // just removes a silent footgun for the next one that wants a hard bar over a
                // title band.
                TopScrollEdgeChrome(
                    modifier = Modifier.align(Alignment.TopCenter),
                    height = topHeight,
                    holdHeight = topHold,
                )
            }
        }
    }
}

/**
 * The bottom half of the chrome, for a screen that was PUSHED rather than selected.
 *
 * The tab roots got their edges and the pushed screens did not, so Detail, its episode list and
 * Watch history rendered whole rows at full opacity under and beside the bottom bar, with no
 * underfill for it to sit on. That is not a per-screen oversight to fix six times; it is the
 * pushed-screen scaffold, so it lives on the navigation destination and every future push inherits
 * it.
 *
 * **The top edge is deliberately untouched:** a pushed screen has a real navigation bar and that
 * bar owns its edge.
 *
 * The other half of the scaffold is the scroll inset — the content inside must use
 * [tabBarContentPadding], for the reason that function documents.
 */
@Composable
fun PushedScreenChrome(
    modifier: Modifier = Modifier,
    content: @Composable BoxScope.() -> Unit,
) {
    ScrollEdgeChromeBox(modifier = modifier, edges = ChromeEdge.Bottom, content = content)
}

// ---------------------------------------------------------------------------------------------
// The scroll inset
// ---------------------------------------------------------------------------------------------

/**
 * Bottom clearance for a scrolling screen, as the scroll container's CONTENT PADDING — never as
 * padding on the last item.
 *
 * Padding inside the content does nothing at all when the stack is shorter than the viewport: the
 * content is already above the fold, so padding under it changes no layout — which is exactly the
 * case a short list is in when it comes to rest inside the ramp. `LazyColumn`'s `contentPadding`
 * extends the scrollable range either way, and it is also what makes the scroll indicator stop in
 * the right place.
 *
 * @param extra a screen that needs more room under its last row (never less).
 */
fun tabBarContentBottom(extra: Dp = 0.dp): Dp = ThemeMetrics.tabBarClearance + extra

/**
 * [tabBarContentBottom] as `PaddingValues`, for a `LazyColumn`/`LazyVerticalGrid` that also wants
 * its gutters set in one place.
 */
fun tabBarContentPadding(
    extra: Dp = 0.dp,
    horizontal: Dp = 0.dp,
    top: Dp = 0.dp,
): PaddingValues = PaddingValues(
    start = horizontal,
    top = top,
    end = horizontal,
    bottom = tabBarContentBottom(extra),
)
