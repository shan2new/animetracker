package com.anitrack.app.ui.hero

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.anitrack.app.design.ThemeColor
import com.anitrack.app.design.ThemeSpace

/**
 * The three gradients that protect content laid on artwork. **Nobody hand-rolls a black overlay.**
 *
 * All three are pure decoration: they take no pointer input and contribute no semantics, which is
 * what iOS spelled out as `allowsHitTesting(false)` + `accessibilityHidden(true)`. In Compose a
 * [Box] carrying only a background does both by construction, so there is nothing to declare — the
 * native answer to those two modifiers is to write neither.
 *
 * Each is a vertical gradient over its own band. The stop tables are the shipped ones, stop for stop
 * and opacity for opacity; they are the part of the design that is neither a rendering mechanic nor
 * a re-tunable number — a veil that can be *seen* is a smudge, and these are the values at which it
 * cannot.
 */

// -------------------------------------------------------------------------------------------------
// ArtScrim
// -------------------------------------------------------------------------------------------------

/**
 * The general full-bleed scrim: protection at the top for the status bar and any floating toolbar,
 * a handover to the canvas at the bottom, and **a transparent middle so the art is never uniformly
 * greyed**.
 *
 * [ArtScrim] has no intrinsic height — it takes the frame it is given, which inside [ArtHeader] is
 * the billboard's own. Pass `Modifier.matchParentSize()` from a [Box], or a sized modifier.
 *
 * A resting billboard passes `bottom = 0` and mounts [HeroCopyScrim] instead: a fractional scrim
 * does not know how tall the copy is, and 0.80-of-the-image is a different physical distance at
 * every type size.
 *
 * @param top scales the two black stops at the head of the gradient. 0 removes them entirely.
 * @param bottom scales the two canvas stops at its foot.
 */
@Composable
fun ArtScrim(
    modifier: Modifier = Modifier,
    top: Float = 1f,
    bottom: Float = 1f,
) {
    val brush = remember(top, bottom) {
        Brush.verticalGradient(
            0.00f to Color.Black.copy(alpha = 0.55f * top),
            0.22f to Color.Black.copy(alpha = 0.16f * top),
            0.46f to Color.Transparent,
            0.80f to ThemeColor.canvas.copy(alpha = 0.55f * bottom),
            1.00f to ThemeColor.canvas.copy(alpha = 1.00f * bottom),
        )
    }
    Box(modifier.background(brush))
}

// -------------------------------------------------------------------------------------------------
// HeroTopVeil
// -------------------------------------------------------------------------------------------------

/**
 * Protection over the status bar and the chrome band at the top of a billboard hero, ramping out
 * with no discernible knee.
 *
 * One gradient for Today's wordmark band and Detail's floating toolbar. A ramp that holds flat and
 * then falls reads, over bright key art, as a hard-edged plate laid on the picture right where the
 * brand mark (or the back button) is; a veil that can be *seen* is not protection, it is a smudge.
 * This holds only as far as the band's own bottom edge and then eases out over the rest, on enough
 * stops that no single step is visible.
 *
 * @param band the chrome band's bottom edge, status-bar inset included.
 * @param ramp how far below the band the veil takes to reach clear. The default matches Today's own
 *   `veilRamp`, so the hero's protection and the scroll-edge chrome's are one shape: at 46 the
 *   chrome's proportional gradient was already down to ~30 % by the bottom of the wordmark band, and
 *   a scrolling 34-dp title read through the brand mark at half strength.
 */
@Composable
fun HeroTopVeil(
    band: Dp,
    modifier: Modifier = Modifier,
    ramp: Dp = heroTopVeilRamp,
) {
    val total = band + ramp
    val mark = if (total > 0.dp) band / total else 0f
    val brush = remember(mark) {
        Brush.verticalGradient(
            0f to Color.Black.copy(alpha = 0.72f),
            mark * 0.72f to Color.Black.copy(alpha = 0.66f),
            mark to Color.Black.copy(alpha = 0.52f),
            mark + (1f - mark) * 0.30f to Color.Black.copy(alpha = 0.30f),
            mark + (1f - mark) * 0.62f to Color.Black.copy(alpha = 0.12f),
            1f to Color.Transparent,
        )
    }
    Box(
        modifier
            .fillMaxWidth()
            .height(total)
            .background(brush)
    )
}

/** Today's `veilRamp`, named once so the hero veil and the chrome veil cannot drift apart. */
val heroTopVeilRamp = 100.dp

// -------------------------------------------------------------------------------------------------
// HeroCopyScrim
// -------------------------------------------------------------------------------------------------

/**
 * Protection BEHIND a hero's copy, sized to the copy's **measured** height at every type size.
 *
 * The stops are placed in DP off the measured copy height, not as fractions of the image. A fixed
 * fraction is a different physical distance at every type size, which is how AX1 came to set a
 * three-line 44-pt title over a face at ~55 % luminance while the same stops were comfortable at
 * default size.
 *
 * [lead] is the run-in above the copy — long, because this is the only bottom protection on a
 * resting billboard (the fractional [ArtScrim] bottom is off there), and without pre-darkening, a
 * 24-dp rise to 0.72 read as a visible edge drawn across the picture. Apple TV's billboard gradient
 * has the same shape: it begins just above the lockup and eases in.
 *
 * The final stop is **full canvas at the frame's bottom edge**, and it is mandatory: the 3 % of
 * photograph left glowing through at the exact line where the hero meets the canvas rendered as a
 * faint band across the screen. The scrim must LAND, not hover.
 *
 * Measure the copy with [reportHeight] and hold the result in screen state, guarded — the copy's
 * height depends only on the available width, never on this scrim, so there is no layout cycle.
 */
@Composable
fun HeroCopyScrim(
    copyHeight: Dp,
    modifier: Modifier = Modifier,
    lead: Dp = heroCopyScrimLead,
) {
    val h = (copyHeight + lead + ThemeSpace.x2).coerceAtLeast(1.dp)
    val leadFraction = lead / h
    val bodyFraction = (lead + heroCopyScrimBodyReach) / h
    val brush = remember(leadFraction, bodyFraction) {
        Brush.verticalGradient(
            0f to Color.Transparent,
            minOf(0.99f, leadFraction * 0.4f) to ThemeColor.canvas.copy(alpha = 0.16f),
            minOf(0.99f, leadFraction * 0.7f) to ThemeColor.canvas.copy(alpha = 0.44f),
            minOf(0.99f, leadFraction) to ThemeColor.canvas.copy(alpha = 0.72f),
            minOf(0.995f, bodyFraction) to ThemeColor.canvas.copy(alpha = 0.90f),
            1f to ThemeColor.canvas,
        )
    }
    Box(
        modifier
            .fillMaxWidth()
            .height(h)
            .background(brush)
    )
}

/** The run-in above the copy. See [HeroCopyScrim]. */
val heroCopyScrimLead = 72.dp

/** How far past the copy's top edge the scrim is effectively opaque — the body of the text block. */
private val heroCopyScrimBodyReach = 56.dp

// -------------------------------------------------------------------------------------------------
// Measuring the copy
// -------------------------------------------------------------------------------------------------

/**
 * Report this element's height in dp whenever it changes — the companion to [HeroCopyScrim] and to
 * the billboard's grow-by-overflow rule.
 *
 * `onSizeChanged` already fires only on a real change, so the callback is the guarded write iOS had
 * to spell out. Store the value in screen state: unlike the scroll offset, the copy height changes
 * a handful of times in a screen's life (a type-size change, a card handover), and the layout that
 * consumes it genuinely has to re-run.
 */
@Composable
fun Modifier.reportHeight(onHeight: (Dp) -> Unit): Modifier {
    val density = LocalDensity.current
    return this.onSizeChanged { size -> onHeight(with(density) { size.height.toDp() }) }
}
