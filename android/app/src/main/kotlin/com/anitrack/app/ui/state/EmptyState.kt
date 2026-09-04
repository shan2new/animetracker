package com.anitrack.app.ui.state

import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.anitrack.app.design.PreviouslyIcons
import com.anitrack.app.design.ThemeColor
import com.anitrack.app.design.ThemeMetrics
import com.anitrack.app.design.ThemeSpace
import com.anitrack.app.design.ThemeType
import com.anitrack.app.design.rememberSymbol
import com.anitrack.app.ui.control.PrimaryButton
import com.anitrack.app.ui.control.SecondaryButton
import com.anitrack.app.ui.control.TertiaryButton
import com.anitrack.app.ui.isAccessibilityTextSize
import com.anitrack.app.ui.scaledDp
import com.anitrack.model.copy.EmptyStateCopy

// =====================================================================================
// STATES ARE CONSUMER, NOT SaaS.
//
// The port of `EmptyState` + `centredState` from
// `ios/Sources/DesignSystem/Primitives+States.swift`.
//
// It draws NO controls of its own. The buttons are `PrimaryButton` / `SecondaryButton` /
// `TertiaryButton` in `ui/control/Buttons.kt` and the shared layout rules are `scaledDp` /
// `isAccessibilityTextSize` / `negativePadding` in `ui/UiPrimitives.kt`. A second copy of that
// button set used to live here, re-spelling every dp of its geometry as a literal.
//
// The whole area obeys two rules from CLAUDE.md, and a port that breaks either is wrong
// even if it compiles:
//
//   1. An empty state is `ContentUnavailableView`'s anatomy on the canvas — a 44-dp
//      tertiary symbol, a title, ONE sentence, ONE hugging button. No plate, no glyph
//      tile, no ambient bloom, no 236-dp floor, no full-width accent banner. That card
//      "was an 'empty state card' from a dashboard template, and the thing that made
//      every failure in the app look like a SaaS product had crashed."
//
//   2. **Amber is not an action colour.** A recovery ("Try again", "Retry") is the quiet
//      capsule; only a real next step ("Add a show", "Clear", "Show all") earns the amber
//      one, and there the amber is a GROUND with `onAccent` ink on it — no amber *word*
//      is ever drawn.
// =====================================================================================

// -------------------------------------------------------------------------------------
// The state symbol
// -------------------------------------------------------------------------------------

/**
 * `EmptyStateCopy.symbol` carries a **Material Symbols name**, not an SF one — the copy table was
 * ported against `spec/icon-mapping.md`. This resolves that name to the vocabulary in
 * [PreviouslyIcons]; the mapping is a `when` rather than a lookup by string so that a name the
 * icon table does not carry is visible here rather than at run time.
 *
 * `signal_wifi_statusbar_not_connected` is the copy table's own preferred pick for SF's
 * `wifi.exclamationmark` (icon-mapping row 40 records `wifi_tethering_error` as the first choice
 * and prefers this one on meaning). Both names resolve to the same vocabulary entry so the two
 * tables cannot drift into two different glyphs for one state.
 *
 * An unrecognised name draws **no glyph** rather than crashing: `symbol` is nullable by design
 * (`calmToday` has none), so the layout already handles absence, and a copy/icon-table gap is not
 * worth taking a whole screen down for. It is still a defect — the `when` is the checklist.
 */
@Composable
private fun stateSymbol(name: String): ImageVector? = when (name) {
    "layers" -> rememberSymbol(PreviouslyIcons.Layers)
    "tv" -> rememberSymbol(PreviouslyIcons.Tv)
    "calendar_month" -> rememberSymbol(PreviouslyIcons.CalendarMonth)
    "bookmark" -> rememberSymbol(PreviouslyIcons.Bookmark)
    "wifi_off" -> rememberSymbol(PreviouslyIcons.WifiOff)
    "search" -> rememberSymbol(PreviouslyIcons.Search)
    "history" -> rememberSymbol(PreviouslyIcons.History)
    "error" -> rememberSymbol(PreviouslyIcons.Error)
    "tune" -> rememberSymbol(PreviouslyIcons.Tune)
    "filter_list" -> rememberSymbol(PreviouslyIcons.FilterList)
    "check_circle" -> rememberSymbol(PreviouslyIcons.CheckCircleFilled)
    "wifi_tethering_error", "signal_wifi_statusbar_not_connected" ->
        rememberSymbol(PreviouslyIcons.WifiTetheringError)
    else -> null
}

// -------------------------------------------------------------------------------------
// The state
// -------------------------------------------------------------------------------------

/** Whether the whole surface, or one section of a populated surface, has nothing to show. */
enum class EmptyStateProminence {
    /** The whole surface has nothing to show. */
    Major,

    /** One section of a populated surface has nothing to show. */
    Section,
}

/**
 * The ONE empty state. Centred, never left-aligned.
 *
 * The system's own grammar for "nothing here" (`ContentUnavailableView`, and every state in Apple
 * TV, Music and Netflix): a symbol, a title, a sentence, one action — set on the canvas, centred.
 * The shipped iOS card was a left-aligned marketing plate with the symbol floating unattached at
 * the top-left, a fixed 22-pt title that ignored Dynamic Type entirely, and a full-width accent
 * capsule that read as a banner CTA.
 *
 * ### Which button, and when it is amber
 *
 * [EmptyStateCopy.isRecovery] (`primaryLabel` is "Try again" or "Retry") decides the TREATMENT,
 * not the position: a recovery gets the quiet [SecondaryButton], a next step ("Add a show",
 * "Clear", "Show all", "Browse your library") gets the amber [PrimaryButton]. Hugging,
 * never a banner — until an accessibility text size, where the button is allowed the full 300-dp
 * column and may wrap.
 *
 * ### A label without a handler is a dead control, not a disabled one
 *
 * The button exists only when the caller supplied something for it to do, which is why `hasAction`
 * tests the label AND the handler.
 *
 * ### Why [prominence] is the LAST parameter
 *
 * On iOS `EmptyState(.serverNoCache) { retry }` bound the trailing closure to `secondary` by
 * Swift's forward-scan rule, and **Schedule's and Detail's whole-screen server errors shipped with
 * no "Try again" at all**. Kotlin's trailing lambda binds to the last parameter, so the identical
 * bug is available here — unless the last parameter is not a function type. It is not: a trailing
 * lambda on this function is a **compile error**, which is the same guarantee the iOS reordering
 * bought, enforced by the compiler instead of by a convention.
 *
 * @param copy the state's words, its glyph and its labels. Data, not a view.
 * @param onPrimary the primary action's handler. Must precede [onSecondary].
 * @param onSecondary the secondary action's handler, drawn as a bare word.
 */
@Composable
fun EmptyState(
    copy: EmptyStateCopy,
    modifier: Modifier = Modifier,
    onPrimary: (() -> Unit)? = null,
    onSecondary: (() -> Unit)? = null,
    prominence: EmptyStateProminence = EmptyStateProminence.Major,
) {
    // A state whose copy promises an action, wired to nothing, is the bug this catches. Kotlin's
    // `assert` is the closest analogue to Swift's DEBUG-only `assert`: it compiles to a check of
    // `desiredAssertionStatus()`, which ART answers `false` unless the build enables assertions
    // (`-ea` on the JVM, `adb shell setprop debug.assert 1` on device). It is therefore free in
    // release and available in a debug run, which is exactly the iOS contract.
    assert(copy.primaryLabel == null || onPrimary != null || onSecondary != null) {
        "EmptyState “${copy.title}” declares “${copy.primaryLabel ?: ""}” " +
            "but was given no handler"
    }
    assert(copy.secondaryLabel != null || onSecondary == null) {
        "EmptyState “${copy.title}” was given a secondary handler but declares no " +
            "secondary label — did a handler bind to onSecondary by mistake?"
    }

    val isAX = isAccessibilityTextSize()
    val major = prominence == EmptyStateProminence.Major
    val titleStyle = if (major) ThemeType.showTitleL else ThemeType.showTitleM
    val supportStyle = if (major) ThemeType.callout else ThemeType.metadata
    // The symbol answers to Dynamic Type like the type beside it.
    val glyph = scaledDp(if (major) 44.dp else 30.dp)

    val hasPrimary = copy.primaryLabel != null && onPrimary != null
    val hasSecondary = copy.secondaryLabel != null && onSecondary != null

    Box(
        // The copy column is capped at 300 dp; the whole block is centred in whatever it is given.
        modifier = modifier.fillMaxWidth(),
        contentAlignment = Alignment.Center,
    ) {
        Column(
            modifier = Modifier.widthIn(max = 300.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Top,
        ) {
            val symbol = copy.symbol?.let { stateSymbol(it) }
            if (symbol != null) {
                Image(
                    imageVector = symbol,
                    // Decorative: the state below is the labelled element.
                    contentDescription = null,
                    colorFilter = ColorFilter.tint(ThemeColor.textTertiary),
                    modifier = Modifier.size(glyph),
                )
                Spacer(Modifier.height(if (major) ThemeSpace.x4 else ThemeSpace.x3))
            }

            // Title + supporting are ONE screen-reader element carrying `spokenLabel`; the button
            // stays its own node, so a screen reader can still reach the action.
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                modifier = Modifier.semantics(mergeDescendants = true) {
                    contentDescription = copy.spokenLabel
                },
            ) {
                BasicText(
                    text = copy.title,
                    style = titleStyle.copy(
                        color = ThemeColor.textPrimary,
                        textAlign = TextAlign.Center,
                    ),
                    // Nothing truncates at accessibility sizes — the container grows.
                    maxLines = if (isAX) Int.MAX_VALUE else if (major) 3 else 2,
                    overflow = TextOverflow.Ellipsis,
                )
                val supporting = copy.supporting
                if (supporting != null) {
                    Spacer(Modifier.height(ThemeSpace.x2))
                    BasicText(
                        text = supporting,
                        style = supportStyle.copy(
                            color = ThemeColor.textSecondary,
                            textAlign = TextAlign.Center,
                        ),
                    )
                }
            }

            if (hasPrimary || hasSecondary) {
                Spacer(Modifier.height(ThemeSpace.x5))
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(ThemeSpace.x1),
                ) {
                    if (hasPrimary) {
                        // Hugging, never a banner — until an accessibility size, where the button
                        // may take the full column and wrap.
                        if (copy.isRecovery) {
                            SecondaryButton(
                                label = copy.primaryLabel!!,
                                onClick = onPrimary!!,
                                hugging = !isAX,
                            )
                        } else {
                            PrimaryButton(
                                label = copy.primaryLabel!!,
                                onClick = onPrimary!!,
                                hugging = !isAX,
                            )
                        }
                    }
                    if (hasSecondary) {
                        TertiaryButton(
                            label = copy.secondaryLabel!!,
                            onClick = onSecondary!!,
                        )
                    }
                }
            }
        }
    }
}

/**
 * The shared placement for a state that owns its whole surface: vertically centred in the content
 * area, never top-pinned above 950–1100 dp of void (Library) or floated in the upper third
 * (Search).
 *
 * The default clearance is the bottom bar's **VISUAL** height ([ThemeMetrics.tabBarVisualHeight],
 * 90) and **not** [ThemeMetrics.tabBarClearance] (76). "They are different numbers for different
 * jobs: a scroll inset has to clear the ramp as well as the bar, and subtracting that inset when
 * *centring* pushed every empty state ~81 pt above true optical centre on Today and Schedule. Half
 * of whatever is subtracted is the error."
 *
 * A **minimum** height, never a fixed one, so the largest text sizes grow the block rather than
 * clipping it outside the scrollable region.
 *
 * @param contentHeight the scroll viewport's own height.
 */
fun Modifier.centredState(
    contentHeight: Dp,
    clearance: Dp = ThemeMetrics.tabBarVisualHeight,
): Modifier = this
    .fillMaxWidth()
    .defaultMinSize(minHeight = (contentHeight - clearance).coerceAtLeast(0.dp))
    .wrapContentSize(Alignment.Center)
