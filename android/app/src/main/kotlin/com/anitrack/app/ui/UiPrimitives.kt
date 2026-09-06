package com.anitrack.app.ui

import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.AlignmentLine
import androidx.compose.ui.layout.FirstBaseline
import androidx.compose.ui.layout.layout
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.isSpecified
import androidx.compose.ui.unit.sp

/*
 * The layout rules the cards, rows and states need that the token layer does not own.
 *
 * They live here — one file, `internal`, at the root of `ui/` — rather than in private copies
 * across `ui/card/`, `ui/row/`, `ui/section/` and `ui/state/`, because each is a rule rather than a
 * value: **one** accessibility-size threshold, **one** scaled metric, **one** negative padding,
 * **one** answer to "the identity title never ellipsizes". A second threshold is two shapes of the
 * same screen; a second negative padding is two answers to one measurement.
 *
 * The press language is NOT here. It is `PressStyle` in `ui/control/Buttons.kt`, as an
 * `Indication` handed to `Modifier.clickable` — the framework's own mechanism, and the only
 * sanctioned way to make something tappable in this app. Two hand-rolled press modifiers used to
 * live here and gave the app three press feels for one finger.
 */

// ---------------------------------------------------------------------------------------------
// Accessibility text size
// ---------------------------------------------------------------------------------------------

/**
 * Where the AX layouts switch: **1.3, and that is a deliberate divergence, not a conversion.**
 *
 * iOS switches at `.accessibility1`, which is `.body` 17 pt → 28 pt, a ratio of 1.647×. Android's
 * ordinary "Largest" slider is 1.3 and its ladder has no rung between there and the accessibility
 * range, so every user on the largest *non*-accessibility setting gets the AX layout an equivalent
 * iOS user never sees. That is accepted: Compose's non-linear curve already lands most tokens
 * 7–14 % below iOS at the same nominal scale, and switching **early** degrades gracefully (looser,
 * taller, single-column) where switching **late** clips.
 *
 * Defined once. Nothing re-derives it — a second threshold means two shapes of the same screen.
 */
internal const val AX_FONT_SCALE = 1.3f

/** The port of iOS's `dynamicTypeSize.isAccessibilitySize`. See [AX_FONT_SCALE]. */
@Composable
internal fun isAccessibilityTextSize(): Boolean = LocalDensity.current.fontScale >= AX_FONT_SCALE

// ---------------------------------------------------------------------------------------------
// Scaled metrics
// ---------------------------------------------------------------------------------------------

/**
 * iOS `@ScaledMetric(wrappedValue:relativeTo:)` — a dp value that answers to the text scale.
 *
 * Routed through `TextUnit.toDp()`, which goes via `FontScaleConverterFactory` and applies
 * Android 14's **non-linear** curve. Do **not** hand-roll `value * LocalDensity.current.fontScale`:
 * since Android 14 a bare `fontScale` multiply is documented as inaccurate and the field is "for
 * informational purposes only".
 *
 * Google's own sp-arithmetic trap applies: `4.sp + 20.sp` is not `24.sp` in dp under the curve, so
 * a composite metric (row height = art + 2 × padding) is composed in dp and scaled **once**.
 */
@Composable
internal fun scaledDp(value: Dp): Dp = with(LocalDensity.current) { value.value.sp.toDp() }

// ---------------------------------------------------------------------------------------------
// Negative padding
// ---------------------------------------------------------------------------------------------

/**
 * The port of SwiftUI's `.padding(.vertical, -inset)`, which Compose has no direct spelling for.
 *
 * Three call sites need one: `InlineNotice`'s Retry link, `SectionHeaderRow`'s inline action and
 * header press target, and the episode row's reveal glyph. Each hosts a control that holds its own
 * 44-dp target with real padding; without pulling that back the link sits 12 dp off the message's
 * baseline and a 28-dp footnote row inflates to 44.
 *
 * Measure the child as it wants to be, report a box that much smaller, and place the child
 * straddling it. It works because **Compose does not clip hit-testing to a parent's bounds**: a
 * child placed outside its parent still receives touches as long as no ancestor sets `clip = true`.
 * Any host that clips this subtree gets a smaller target and must re-verify it.
 *
 * The child's first baseline is forwarded through the shift, so a collapsed inline link can still
 * be baseline-aligned against the title beside it.
 */
internal fun Modifier.negativePadding(
    start: Dp = 0.dp,
    top: Dp = 0.dp,
    end: Dp = 0.dp,
    bottom: Dp = 0.dp,
): Modifier = this.layout { measurable, constraints ->
    val dx = start.roundToPx()
    val dy = top.roundToPx()
    val shrinkWidth = dx + end.roundToPx()
    val shrinkHeight = dy + bottom.roundToPx()
    val placeable = measurable.measure(constraints)
    val width = (placeable.width - shrinkWidth).coerceAtLeast(0)
    val height = (placeable.height - shrinkHeight).coerceAtLeast(0)
    val baseline = placeable[FirstBaseline]
    val lines: Map<AlignmentLine, Int> =
        if (baseline == AlignmentLine.Unspecified) emptyMap()
        else mapOf(FirstBaseline to baseline - dy)
    layout(width, height, lines) { placeable.place(-dx, -dy) }
}

// ---------------------------------------------------------------------------------------------
// Auto-sizing text
// ---------------------------------------------------------------------------------------------

/**
 * The port of SwiftUI's `minimumScaleFactor`: shrink the type, down to a floor, rather than
 * truncate it.
 *
 * **Never substitute an ellipsis.** The identity title is the one string a card exists to show, and
 * the shipped compact card's `lineLimit(1)` amputated exactly the titles the rule was written for.
 * A title that still does not fit at the floor is drawn at the floor and allowed to clip its last
 * line — which, at two lines of a shortened title, does not happen in practice.
 *
 * Compose has no equivalent, so this bisects the font size with a [TextMeasurer]: at most six
 * probes between [minScale] and 1, each a cached measure. The line height scales with the type so
 * the block stays optically the same shape; the letter spacing does not, because the tracking
 * tokens are absolute and shrinking them at 82 % would close up an already tight face.
 *
 * The text takes its **wrapped** height whatever its parent proposes — the horizontal scroller on
 * Today's Watching shelf handed a card a one-line budget and a range limit obeyed it, scaling a
 * two-line name down and cutting it with an ellipsis ("The Beginning After…").
 */
@Composable
internal fun AutoSizeText(
    text: String,
    style: TextStyle,
    minScale: Float,
    modifier: Modifier = Modifier,
    maxLines: Int = Int.MAX_VALUE,
) {
    val measurer = rememberTextMeasurer()
    val density = LocalDensity.current
    BoxWithConstraints(modifier) {
        val widthPx = constraints.maxWidth
        val fitted = remember(text, style, maxLines, minScale, widthPx, density) {
            fittedStyle(measurer, text, style, maxLines, minScale, widthPx)
        }
        BasicText(
            text = text,
            style = fitted,
            maxLines = maxLines,
            overflow = TextOverflow.Clip,
            modifier = Modifier.wrapContentHeight(align = Alignment.Top, unbounded = true),
        )
    }
}

/** Probes per bisection. Six lands within ~0.3 % of the largest fitting scale over a 0.18 range. */
private const val AUTO_SIZE_PROBES = 6

private fun fittedStyle(
    measurer: TextMeasurer,
    text: String,
    style: TextStyle,
    maxLines: Int,
    minScale: Float,
    widthPx: Int,
): TextStyle {
    if (widthPx <= 0 || widthPx == Constraints.Infinity || !style.fontSize.isSpecified) return style

    fun fits(scale: Float): Boolean = !measurer.measure(
        text = text,
        style = style.scaledBy(scale),
        maxLines = maxLines,
        softWrap = true,
        overflow = TextOverflow.Ellipsis,
        constraints = Constraints(maxWidth = widthPx),
    ).hasVisualOverflow

    if (fits(1f)) return style
    // The floor is a floor: below it the type stops shrinking and the block is allowed to clip.
    if (!fits(minScale)) return style.scaledBy(minScale)

    var low = minScale
    var high = 1f
    repeat(AUTO_SIZE_PROBES) {
        val mid = (low + high) / 2f
        if (fits(mid)) low = mid else high = mid
    }
    return style.scaledBy(low)
}

/** Font size and line height together; tracking is absolute and stays put. */
private fun TextStyle.scaledBy(scale: Float): TextStyle {
    if (scale >= 1f) return this
    return copy(
        fontSize = if (fontSize.isSpecified) fontSize * scale else fontSize,
        lineHeight = if (lineHeight.isSpecified) lineHeight * scale else lineHeight,
    )
}
