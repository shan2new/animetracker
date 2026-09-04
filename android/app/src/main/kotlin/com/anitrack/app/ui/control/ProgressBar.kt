package com.anitrack.app.ui.control

import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.anitrack.app.design.ThemeColor
import kotlin.math.max

/**
 * **The one progress bar.** A 3-dp track in `strokeStrong`, the watched share in `accent`, and a
 * 3-dp minimum fill so a started season is never a zero-width fill.
 *
 * It is **wordless on purpose**: where-you-are is a bar, never "11 of 24 watched" in words. Every
 * surface that can draw one draws one instead of saying it — the hero's fact line, a `MediaRow`,
 * the season header, the Up Next banner. `Copy.Progress.watchedOf` exists only for the grouped
 * rows and confirmations that have no room for a bar.
 *
 * ### Accessibility
 *
 * Without [spoken] the bar is decoration and is **hidden**, exactly as on iOS — and a label set on
 * a hidden element from the outside is silently dropped, which is how Today's hero came to say its
 * count to nobody. So the count is passed *in*, and the bar speaks it itself.
 *
 * `clearAndSetSemantics {}` is the Compose spelling of `accessibilityHidden(true)`: it removes this
 * node and everything under it from the tree rather than merely leaving it unlabelled.
 *
 * @param value the watched share, 0…1. Clamped here so no caller has to.
 * @param spoken what TalkBack reads for the bar ("4 episodes behind"). `null` hides the bar.
 */
@Composable
fun ProgressBar(
    value: Float,
    modifier: Modifier = Modifier,
    spoken: String? = null,
) {
    Spacer(
        modifier
            .fillMaxWidth()
            .height(progressBarHeight)
            .then(
                if (spoken == null) {
                    Modifier.clearAndSetSemantics {}
                } else {
                    Modifier.semantics { contentDescription = spoken }
                }
            )
            // The whole bar is one draw call pair on one node: nothing here recomposes, and the
            // fill width is resolved in the draw phase from the value the caller passed.
            .drawBehind {
                // A capsule is a rounded rect whose radius is half its height. Drawing it as one
                // round rect rather than as two clipped `Capsule()`s keeps the fill's LEADING cap
                // round and its trailing cap round too — which is what the two stacked capsules
                // produced on iOS.
                val cap = CornerRadius(size.height / 2f)
                drawRoundRect(color = ThemeColor.strokeStrong, cornerRadius = cap)
                val filled = max(
                    progressBarMinimumFill.toPx(),
                    size.width * value.coerceIn(0f, 1f),
                )
                drawRoundRect(
                    color = ThemeColor.accent,
                    size = Size(filled, size.height),
                    cornerRadius = cap,
                )
            }
    )
}

/**
 * 3 dp. Thin enough to be a measurement rather than a component — it sits under a fact line, on a
 * banner's art and inside a row, and at any more it becomes the loudest thing in all three.
 */
private val progressBarHeight = 3.dp

/**
 * The floor on the fill's width, so a started season is never a zero-width fill: one episode of
 * twenty-four is 4 % of a 200-dp bar, which rounds to nothing on a low-density screen and reads as
 * "not started".
 */
private val progressBarMinimumFill = 3.dp
