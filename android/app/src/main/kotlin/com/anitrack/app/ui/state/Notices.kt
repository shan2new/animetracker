package com.anitrack.app.ui.state

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.anitrack.app.design.LocalReduceMotion
import com.anitrack.app.design.MotionToken
import com.anitrack.app.design.PreviouslyIcons
import com.anitrack.app.design.ThemeColor
import com.anitrack.app.design.ThemeMotion
import com.anitrack.app.design.ThemeSpace
import com.anitrack.app.design.ThemeType
import com.anitrack.app.design.motion
import com.anitrack.app.design.rememberSymbol
import com.anitrack.app.ui.control.InlineLinkButton
import com.anitrack.app.ui.isAccessibilityTextSize
import com.anitrack.app.ui.negativePadding
import com.anitrack.model.copy.Copy
import com.anitrack.model.copy.CopyDates
import kotlinx.coroutines.delay

// =====================================================================================
// A BACKGROUND FAILURE IS A FOOTNOTE, NOT AN ALERT.
//
// `InlineNotice`, `StaleStrip`, `RefreshIndicator` and the composed `Freshness` pair —
// the port of the middle third of `ios/Sources/DesignSystem/Primitives+States.swift`.
//
// The three of them answer three different questions and must never be confused:
//
//   InlineNotice     — "this section's refresh FAILED". The content stays; the notice
//                      sits under the section header with a "Retry" link. Never a
//                      dialog, never a toast, never a full-screen error over content
//                      that loaded fine from the cache.
//   StaleStrip       — "what you're looking at is OLD". Passive by decision: pull-to-
//                      refresh is the refresh affordance, and a tappable strip would be
//                      a second, invisible one.
//   RefreshIndicator — "a refresh is running RIGHT NOW over content already on screen".
//                      Only after 400 ms, in the bar, and it yields to a native pull.
// =====================================================================================

/** A notice's tone. `Info` is a plain footnote fact; `Failure` is a repairable refresh failure. */
enum class InlineNoticeKind {
    Failure,
    Info,
}

/**
 * "This section's refresh failed" — the content stays, the notice sits under the section header.
 *
 * It was a plate with a 3-pt warning rule down its edge, a bold triangle and a 17-pt "Retry" — an
 * alert box, on screens whose content had loaded fine from the cache. **A background refresh that
 * failed is a footnote** (Mail's "Cannot connect" at the foot of the list), never a warning.
 *
 * Copy is noun-first — *the thing that failed, then what happened to it*: `Copy.Notice.today`
 * ("Airing dates couldn’t refresh"), `Copy.Notice.library` ("Your library couldn’t refresh"). The
 * brand is never the clause subject and neither is the screen.
 *
 * At an accessibility text size the layout swaps H → V so the link never squeezes the message.
 *
 * @param onRetry when non-null, draws the "Retry" link. Its handler re-runs the same request.
 */
@Composable
fun InlineNotice(
    message: String,
    modifier: Modifier = Modifier,
    kind: InlineNoticeKind = InlineNoticeKind.Failure,
    onRetry: (() -> Unit)? = null,
) {
    val isAX = isAccessibilityTextSize()

    // The glyph + the message are ONE screen-reader element labelled with the message; the glyph
    // itself is never spoken.
    val glyphAndMessage: @Composable (Modifier) -> Unit = { slot ->
        Row(
            verticalAlignment = Alignment.Top,
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            modifier = slot.semantics(mergeDescendants = true) {
                contentDescription = message
            },
        ) {
            val symbol = when (kind) {
                InlineNoticeKind.Failure -> rememberSymbol(PreviouslyIcons.WifiTetheringError)
                InlineNoticeKind.Info -> rememberSymbol(PreviouslyIcons.Pending.Info)
            }
            // iOS aligns the glyph to the message's FIRST TEXT BASELINE. Compose has no baseline
            // for a non-text node, so the glyph is centred inside a box exactly one metadata line
            // tall — which lands in the same place and, unlike `alignByBaseline`, does not sink
            // when the message wraps to two lines.
            val lineBox = with(LocalDensity.current) { ThemeType.metadata.lineHeight.toDp() }
            Box(Modifier.height(lineBox), contentAlignment = Alignment.Center) {
                Image(
                    imageVector = symbol,
                    contentDescription = null,
                    colorFilter = ColorFilter.tint(ThemeColor.textTertiary),
                    modifier = Modifier.size(12.dp),
                )
            }
            BasicText(
                text = message,
                style = ThemeType.metadata.copy(color = ThemeColor.textSecondary),
            )
        }
    }

    val retryLink: @Composable () -> Unit = {
        val retry = onRetry
        if (retry != null) {
            InlineLinkButton(
                label = Copy.Action.retry,
                onClick = retry,
                // The hint iOS attaches to the same control.
                onClickLabel = Copy.Accessibility.retryHint,
                // Optical: the style holds its own 44-dp target with 14-dp vertical + 12-dp
                // horizontal padding, and without pulling it back the link sits 12 dp off the
                // message's baseline and inflates this 28-dp footnote row to 44.
                modifier = Modifier.negativePadding(
                    top = 12.dp,
                    bottom = 12.dp,
                    start = if (isAX) 12.dp else 4.dp,
                ),
            )
        }
    }

    val container = modifier
        .fillMaxWidth()
        .heightIn(min = 28.dp)

    if (isAX) {
        Column(
            modifier = container,
            horizontalAlignment = Alignment.Start,
            verticalArrangement = Arrangement.spacedBy(ThemeSpace.x1),
        ) {
            glyphAndMessage(Modifier)
            retryLink()
        }
    } else {
        Row(
            modifier = container,
            verticalAlignment = Alignment.Top,
            horizontalArrangement = Arrangement.spacedBy(ThemeSpace.x2),
        ) {
            // `fill = false` so the message keeps its natural width and the link sits beside it —
            // it only yields when the sentence would otherwise push the link off the gutter.
            glyphAndMessage(Modifier.weight(1f, fill = false))
            retryLink()
        }
    }
}

/**
 * "Updated 8h ago".
 *
 * **Passive by decision**: pull-to-refresh is the refresh affordance, and a tappable strip would be
 * a second, invisible one. No ground, no stroke, no 44-dp rule — it is a static-text element, and
 * a screen reader hears the elapsed time spelled out ("Updated 8 hours ago", never "8h").
 *
 * It **wraps** rather than truncating: at the largest text sizes the metadata token is ~44 dp and
 * "Updated Aug 19, 2025" cannot fit one line. The strip is passive, so the 28-dp minimum simply
 * grows.
 *
 * @param since the last successful load, epoch ms. A page that has never loaded is not stale, it is
 *   loading — the model returns `null` there and the caller draws nothing.
 * @param dates the copy table's five date facts. `:model` is a pure Kotlin module and the 24-hour
 *   clock setting is only readable through a `Context`, so the seam is explicit rather than
 *   imported.
 */
@Composable
fun StaleStrip(
    since: Long,
    now: Long,
    dates: CopyDates,
    modifier: Modifier = Modifier,
) {
    val spoken = Copy.updatedSpokenLabel(at = since, now = now, dates = dates)
    Row(
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = 28.dp)
            // One element, labelled with the spelled-out form. `.isStaticText` is Compose's
            // default for a node with no click handler, so nothing has to say so.
            .clearAndSetSemantics { contentDescription = spoken },
        verticalAlignment = Alignment.Top,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        val lineBox = with(LocalDensity.current) { ThemeType.metadata.lineHeight.toDp() }
        Box(Modifier.height(lineBox), contentAlignment = Alignment.Center) {
            Image(
                imageVector = rememberSymbol(PreviouslyIcons.Sync),
                contentDescription = null,
                colorFilter = ColorFilter.tint(ThemeColor.textTertiary),
                modifier = Modifier.size(11.dp),
            )
        }
        BasicText(
            text = Copy.updated(at = since, now = now, dates = dates),
            style = ThemeType.metadata.copy(color = ThemeColor.textTertiary),
        )
    }
}

/**
 * The small spinner beside a screen title while a refresh runs **over content that is already on
 * screen**.
 *
 * Three rules, all of them load-bearing:
 *
 * 1. **Visible only after 400 ms in flight** — below that it is a flicker.
 * 2. **Suppressed entirely while a native pull is driving** — the system pull indicator owns that
 *    moment, and two indicators is worse than none.
 * 3. It lives in the **bar**, not in flow: "In flow above the content it reserved a 16-pt row at
 *    idle — the void between 'Library' and the All titles row." A caller mounts it only while
 *    [isRefreshing]; it is never held at opacity 0 as a layout placeholder.
 *
 * Drawn by hand rather than with M3's `CircularProgressIndicator`, which is banned outright
 * (PLAN §3.1) — it would arrive wearing `MaterialTheme.colorScheme.primary` and Material's own
 * stroke and diameter. This is the same indeterminate arc at the app's tint and 16 dp.
 */
@Composable
fun RefreshIndicator(
    isRefreshing: Boolean,
    modifier: Modifier = Modifier,
    suppressed: Boolean = false,
) {
    var visible by remember { mutableStateOf(false) }

    // Keyed on BOTH guards, exactly as iOS keys its task on `[isRefreshing, suppressed]`: any
    // change cancels the pending 400 ms wait, and `visible` drops immediately when either fails.
    LaunchedEffect(isRefreshing, suppressed) {
        if (!isRefreshing || suppressed) {
            visible = false
            return@LaunchedEffect
        }
        delay(REFRESH_INDICATOR_DELAY_MILLIS)
        visible = true
    }

    val alpha by animateFloatAsState(
        targetValue = if (visible) 1f else 0f,
        animationSpec = motion(MotionToken.UI_GENTLE),
        label = "refreshIndicatorAlpha",
    )

    Box(
        modifier = modifier
            .size(RefreshIndicatorDiameter)
            // Decorative: "a refresh is running" reaches a screen reader through the announcement
            // the settling state makes, not through a spinning arc.
            .clearAndSetSemantics { },
    ) {
        // Mounted only while it is visible: an infinite transition held at opacity 0 is a frame the
        // compositor pays for and nobody sees.
        if (alpha > 0f) {
            IndeterminateArc(
                tint = ThemeColor.textTertiary,
                diameter = RefreshIndicatorDiameter,
                stroke = RefreshIndicatorStroke,
                sweep = RefreshIndicatorSweep,
                modifier = Modifier.graphicsLayer { this.alpha = alpha },
            )
        }
    }
}

/** Below this a spinner is a flicker, not a signal. */
const val REFRESH_INDICATOR_DELAY_MILLIS = 400L

/** The bar-side indicator's own anatomy. */
private val RefreshIndicatorDiameter = 16.dp
private val RefreshIndicatorStroke = 1.5.dp
private const val RefreshIndicatorSweep = 280f

// =====================================================================================
// THE INDETERMINATE ARC
// =====================================================================================

/**
 * **The** indeterminate spinner: one arc, one turn, one Reduce Motion decision.
 *
 * Both spinners in the app are this — [RefreshIndicator] (a background refresh over content already
 * on screen) and `InlineSpinner` (a settings row's write in flight). What separates them is when
 * they appear, how big they are and what ink they wear; never how fast they go round and never
 * whether they answer to Reduce Motion. Two hand-rolled copies is how a preference comes to be
 * honoured on one screen and not the next: the copy in `ui/profile/Settings.kt` gated nothing.
 *
 * Drawn by hand rather than with M3's `CircularProgressIndicator`, which is banned outright
 * (PLAN §3.1) — it would arrive wearing `MaterialTheme.colorScheme.primary` and Material's own
 * stroke and diameter.
 *
 * **Under Reduce Motion the arc is HELD**, at [ThemeMotion.refreshSpinStatic], and no infinite
 * transition is started at all — the same shape `SkeletonGate` takes with its breath. See
 * [ThemeMotion.refreshSpin] for why that overruled the earlier "a spinner always turns" note.
 *
 * The angle is read inside the draw lambda, so a turning arc costs a draw pass and never a
 * recomposition of the row or bar it sits in.
 *
 * @param sweep how much of the circle the arc covers. The rest of the ring is the gap that makes
 *   the rotation legible.
 */
@Composable
fun IndeterminateArc(
    tint: Color,
    diameter: Dp,
    stroke: Dp,
    sweep: Float,
    modifier: Modifier = Modifier,
) {
    val reduceMotion = LocalReduceMotion.current
    val angle: () -> Float = if (reduceMotion) {
        { ThemeMotion.refreshSpinStatic }
    } else {
        val spin = rememberInfiniteTransition(label = "indeterminateArc")
        val animated = spin.animateFloat(
            initialValue = 0f,
            targetValue = 360f,
            animationSpec = ThemeMotion.refreshSpin(),
            label = "indeterminateArcAngle",
        )
        remember(animated) { { animated.value } }
    }

    Canvas(
        modifier = modifier
            .size(diameter)
            // Decorative: the row's own label, or the state the screen settles into, says what is
            // happening.
            .clearAndSetSemantics { },
    ) {
        val width = stroke.toPx()
        val inset = width / 2f
        drawArc(
            color = tint,
            startAngle = angle() - 90f,
            sweepAngle = sweep,
            useCenter = false,
            topLeft = Offset(inset, inset),
            size = Size(size.width - width, size.height - width),
            style = Stroke(width = width, cap = StrokeCap.Round),
        )
    }
}

/**
 * The freshness pair, composed once so that five screens do not hand-assemble it five ways: the
 * content, with the 28-dp [StaleStrip] directly beneath it whenever this data class is past its
 * threshold.
 *
 * **The spinner half is not in here.** On iOS `freshness` also plants a `RefreshIndicator` in the
 * navigation bar through `.toolbar { }`; Android's bar is an app-drawn `Box` inside `ChromeSurface`
 * (M3's `TopAppBar` is banned), so there is no toolbar slot a modifier can reach into. A screen
 * places [RefreshIndicator] in its own bar and passes the same `pullDriving` flag to `suppressed`.
 * The `if` around it matters there as much as it does here: **mount it only while refreshing**,
 * never hold it at opacity 0.
 *
 * The two animations are `uiGentle` and are deliberately **not** routed through `pickMotion` — this
 * is one of the three unconditional motions the design system names, because a strip that appears
 * without any transition shoves the content under it.
 *
 * @param staleSince the model's `staleSince(dataClass)`. `null` before the first successful load —
 *   "a page that has never loaded is not stale, it is loading" — and after a fresh one.
 */
@Composable
fun Freshness(
    staleSince: Long?,
    now: Long,
    dates: CopyDates,
    modifier: Modifier = Modifier,
    content: @Composable ColumnScope.() -> Unit,
) {
    // Held so the strip can animate OUT with the timestamp it was drawn with, rather than
    // re-composing to nothing the instant the model nils it. `AnimatedVisibility` keeps its
    // subtree composed through the exit, so without the hold the fade would run over an empty box.
    //
    // This is a FORWARD write — the value is written before anything in this composition reads it,
    // so it costs no extra recomposition; it is not the "backwards write" Compose warns about.
    var lastStale by remember { mutableStateOf(staleSince) }
    if (staleSince != null) lastStale = staleSince

    Column(modifier = modifier, verticalArrangement = Arrangement.Top) {
        content()
        AnimatedVisibility(
            visible = staleSince != null,
            enter = fadeIn(ThemeMotion.uiGentle()),
            exit = fadeOut(ThemeMotion.uiGentle()),
        ) {
            val since = lastStale
            if (since != null) {
                StaleStrip(
                    since = since,
                    now = now,
                    dates = dates,
                    modifier = Modifier.padding(vertical = ThemeSpace.x2),
                )
            } else {
                Spacer(Modifier.width(0.dp))
            }
        }
    }
}

/**
 * The pull-to-refresh arming rule, as data, because the part most likely to be dropped in a port is
 * the `dragging` test rather than the threshold.
 *
 * The pull itself is Compose's own `PullToRefreshBox` (the native answer, per the fidelity line);
 * what the design adds is one haptic:
 *
 * ```
 * val armed = remember { mutableStateOf(false) }
 * // inside a snapshotFlow over the pull state:
 * val progress = distance / PullRefresh.THRESHOLD
 * if (!armed.value && dragging && progress >= 1f) {
 *     armed.value = true
 *     FeedbackCoordinator.fire(FeedbackToken.REFRESH_ARMED)
 * } else if (armed.value && progress < PullRefresh.REARM_PROGRESS) {
 *     armed.value = false   // re-arm only well back, so a wobble at the threshold cannot buzz twice
 * }
 * ```
 *
 * **`dragging` is the whole point**: "a fast flick to the top overshoots well past the threshold
 * under momentum with no finger down, and the system `refreshable` does NOT fire for that.
 * `.refreshArmed` promises 'let go now and it refreshes', so it may only fire while there is
 * something to let go of."
 *
 * The custom bookmark-fill refresh graphic is **deliberately not drawn**: suppressing the system
 * indicator is not supported API, and two indicators is worse than none.
 */
object PullRefresh {
    /** The pull distance, in dp, at which releasing will refresh. */
    val THRESHOLD = 80.dp

    /** Re-arm only once the pull is well back, so a wobble at the threshold cannot buzz twice. */
    const val REARM_PROGRESS = 0.3f
}
