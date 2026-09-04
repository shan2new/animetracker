package com.anitrack.app.ui.state

import android.os.SystemClock
import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import com.anitrack.app.design.ContinuousCornerShape
import com.anitrack.app.design.LocalReduceMotion
import com.anitrack.app.design.PosterSize
import com.anitrack.app.design.SurfaceLevel
import com.anitrack.app.design.ThemeColor
import com.anitrack.app.design.ThemeMetrics
import com.anitrack.app.design.ThemeMotion
import com.anitrack.app.design.ThemeRadius
import com.anitrack.app.design.ThemeSpace
import com.anitrack.app.design.surface
import com.anitrack.app.ui.scaledDp
import com.anitrack.model.copy.Copy
import kotlinx.coroutines.delay

// =====================================================================================
// A SKELETON IS THE SHAPE OF THE CONTENT THAT IS COMING.
//
// The port of `ios/Sources/DesignSystem/Skeletons+States.swift` plus `SkeletonBlock`
// (Primitives.swift).
//
// **Shimmer is refused by name**: "a travelling highlight is decoration pretending to be
// progress." What replaces it is a breath — 0.88 ↔ 1.0 over 1.4 s, and the amplitude is
// deliberate: "A 35 % oscillation across the WHOLE screen, forever, is not a reassurance
// that something is working — it is a pulse the eye cannot ignore and cannot look away
// from, on the frame the user is already waiting through. 12 % still visibly breathes."
//
// The 240 / 320 / 120 rule lives in `SkeletonGate` and NOWHERE else. A screen composes its
// skeleton from the atoms below and hands it to the gate; it never re-implements the
// timing. The six per-screen default compositions the design system used to ship were
// deleted (30 Aug) — every screen composes its own stand-in, and the atoms plus the gate
// are the whole contract.
//
// The other half of the contract is geometrical: **the skeleton's geometry must be the
// geometry that arrives.** "The skeleton put 'WATCHING' at 493 pt and the real content at
// 537 pt … so everything below moved 44 pt at the swap, and because `SkeletonGate`
// crossfades you saw both misaligned lists superimposed for 120 ms."
// =====================================================================================

/**
 * "The wait has passed 800 ms."
 *
 * `SkeletonGate` sets this exactly as iOS does — and, exactly as iOS does, **nothing renders it**.
 * The file header of the Swift source promises "a small `ProgressView` once the wait passes 800 ms"
 * and the body never draws one, so a port that adds a spinner here is adding a behaviour the app
 * does not have. The flag is published rather than kept private so the timing is real and
 * observable, and so the first screen that genuinely wants it does not re-invent the clock.
 */
val LocalSkeletonSlow = compositionLocalOf { false }

/** Nothing at all for this long: a fast response must never flash a skeleton. */
const val SKELETON_DELAY_MILLIS = 240L

/** Once shown, the skeleton stays at least this long even if the data lands at 250 ms. */
const val SKELETON_MINIMUM_MILLIS = 320L

/** After this long the wait is "slow" — see [LocalSkeletonSlow]. */
const val SKELETON_SLOW_MILLIS = 800L

private enum class GatePhase { Skeleton, Blank, Content }

/**
 * Owns the whole loading rule:
 *
 * * nothing at all for the first **240 ms** — a fast response must never flash a skeleton;
 * * once shown, the skeleton stays at least **320 ms** even if data lands at 250 ms;
 * * it swaps to content with a **120-ms crossfade** (`uiCrossfade`, which is a name for
 *   `uiReduced`, not a fourteenth token);
 * * the frame never blanks between them.
 *
 * The two waits are timed holds, not springs gated by a sleep: the swap itself is an ease-out
 * crossfade, so nothing is animated on a timer.
 *
 * ### Two things a caller must know
 *
 * 1. **[content] is laid out in one box.** Two sibling composables handed to it are drawn on top of
 *    each other — this shipped on iOS as "30 titles" printed across the first row of All titles.
 *    Wrap the content in one layout.
 * 2. **[isLoading] means "there is nothing to show yet".** A refresh over content the user can
 *    already see is NOT this — that is [RefreshIndicator] plus the content itself.
 *
 * The minimum-visible window is measured with `SystemClock.elapsedRealtime()`, which is monotonic
 * since boot. **Never `System.currentTimeMillis()`:** a wall-clock stamp can be moved by the system
 * mid-window and compute a negative or absurd remainder.
 */
@Composable
fun SkeletonGate(
    isLoading: Boolean,
    modifier: Modifier = Modifier,
    skeleton: @Composable () -> Unit,
    content: @Composable () -> Unit,
) {
    val reduceMotion = LocalReduceMotion.current
    var visible by remember { mutableStateOf(false) }
    var shownAt by remember { mutableStateOf<Long?>(null) }
    var slow by remember { mutableStateOf(false) }

    // `LaunchedEffect(isLoading)` cancels and restarts on every change, identically to SwiftUI's
    // `.task(id:)` — which is what makes every wait below cancellable rather than a stale timer.
    LaunchedEffect(isLoading) {
        if (isLoading) {
            if (visible) return@LaunchedEffect
            delay(SKELETON_DELAY_MILLIS)
            shownAt = SystemClock.elapsedRealtime()
            visible = true
            delay(SKELETON_SLOW_MILLIS)
            slow = true
        } else {
            slow = false
            if (!visible) return@LaunchedEffect
            val shown = shownAt
            if (shown != null) {
                val remaining = SKELETON_MINIMUM_MILLIS - (SystemClock.elapsedRealtime() - shown)
                if (remaining > 0) delay(remaining)
            }
            visible = false
            shownAt = null
        }
    }

    val phase = when {
        visible -> GatePhase.Skeleton
        isLoading -> GatePhase.Blank
        else -> GatePhase.Content
    }

    Crossfade(
        targetState = phase,
        modifier = modifier,
        animationSpec = ThemeMotion.uiCrossfade(),
        label = "skeletonGate",
    ) { current ->
        when (current) {
            GatePhase.Skeleton -> {
                // The breath is mounted only while the skeleton is: an infinite transition held at
                // opacity 0 is a frame the compositor pays for and nobody sees.
                //
                // It is handed on as a LAMBDA, never as a `Float`. `val animated by transition
                // .animateFloat(...)` unwraps the `State` HERE, in the content lambda's own body:
                // the breath then invalidated this recomposition scope at 60–120 Hz for the whole
                // of every load — re-running the `when`, allocating a fresh `graphicsLayer` block
                // and a fresh `clearAndSetSemantics` block each frame and re-applying the modifier
                // chain — on the first frames of every cold launch, which is the tightest frame
                // budget the app has. The comment below claimed a deferred read that the code did
                // not make. Reading `.value` inside the layer block is the read that is actually
                // deferred, and it is the shape `IndeterminateArc` uses.
                val breath: () -> Float = if (reduceMotion) {
                    remember { { ThemeMotion.skeletonBreathStatic } }
                } else {
                    val transition = rememberInfiniteTransition(label = "skeletonBreath")
                    val animated = transition.animateFloat(
                        initialValue = ThemeMotion.skeletonBreathLow,
                        targetValue = ThemeMotion.skeletonBreathHigh,
                        animationSpec = ThemeMotion.skeletonBreath(),
                        label = "skeletonBreathAlpha",
                    )
                    remember(animated) { { animated.value } }
                }
                // Remembered so the semantics node is configured once rather than re-applied on
                // every recomposition of this branch — TalkBack may be walking it.
                val loadingSemantics = remember {
                    Modifier.clearAndSetSemantics { contentDescription = Copy.Accessibility.loading }
                }
                CompositionLocalProvider(LocalSkeletonSlow provides slow) {
                    Box(
                        // A deferred read: the breath does not invalidate the screen that is
                        // waiting, only this layer's draw.
                        modifier = Modifier
                            .graphicsLayer { alpha = breath() }
                            .then(loadingSemantics),
                    ) {
                        skeleton()
                    }
                }
            }

            // The first 240 ms: no skeleton and no content. Deliberately empty, so a fast response
            // lands straight on content instead of flashing structure at the user.
            GatePhase.Blank -> Spacer(Modifier.height(0.dp))

            GatePhase.Content -> content()
        }
    }
}

// -------------------------------------------------------------------------------------
// The atoms
//
// Skeletons do NOT scale with the text size — they are structure, not text — EXCEPT
// `SkeletonRow`'s height and `SkeletonShelf`'s line heights, which do, so the swap to real
// content does not jump at accessibility sizes.
//
// The geometry below is named ONCE here for the same reason every other dimension in this app is
// named once: the corner and the line height are each spelled at three call sites, and three
// literals are three chances for a skeleton line to stop matching the line it stands in for.
// -------------------------------------------------------------------------------------

/** A metadata line that has not arrived: one step of the spacing scale, which is its cap height. */
private val skeletonLineHeight: Dp = ThemeSpace.x3

/**
 * A skeleton's own corner — a pill on a line, a soft crop on a poster placeholder.
 *
 * **Derived, and declared after what it derives from**: a top-level `val` initialises in file
 * order, so writing this above [skeletonLineHeight] would silently make every skeleton corner
 * `0.dp`.
 *
 * Half a line height, so a default line is a full stadium: a bar with a smaller radius than its own
 * half-height reads as a disabled table cell rather than as text that has not arrived. It is
 * deliberately NOT [ThemeRadius.poster] — that is the corner of the real poster, and a placeholder
 * cut to the finished art's radius makes the swap land as a shape change on everything else in the
 * row.
 */
private val skeletonCorner: Dp = skeletonLineHeight / 2

/** A TITLE line. Heavier than [skeletonLineHeight] — see [SkeletonRow]. */
private val skeletonTitleLine: Dp = 13.dp

/** A row's later lines. Lighter than the title above them, so the stack is not a table. */
private val skeletonSupportLine: Dp = 10.dp

/** A shelf card's caption line, matching what the real caption occupies. */
private val skeletonCaptionLine: Dp = 11.dp

/**
 * The base block: a rounded rectangle filled with [ThemeColor.skeleton].
 *
 * A `null` dimension takes the size it is offered, which is how a 16:9 card is built —
 * `SkeletonBlock(height = null, radius = ThemeRadius.card, modifier =
 * Modifier.fillMaxWidth().aspectRatio(ThemeMetrics.wideAspect))`.
 */
@Composable
fun SkeletonBlock(
    modifier: Modifier = Modifier,
    width: Dp? = null,
    height: Dp? = skeletonLineHeight,
    radius: Dp = skeletonCorner,
) {
    Box(
        modifier = modifier
            .then(if (width != null) Modifier.width(width) else Modifier.fillMaxWidth())
            .then(if (height != null) Modifier.height(height) else Modifier.fillMaxHeight())
            .background(ThemeColor.skeleton, ContinuousCornerShape(radius)),
    )
}

/** A poster-shaped block. */
@Composable
fun SkeletonPoster(
    width: Dp,
    height: Dp,
    modifier: Modifier = Modifier,
    radius: Dp = ThemeRadius.poster,
) {
    SkeletonBlock(modifier = modifier, width = width, height = height, radius = radius)
}

/** A line of text that has not arrived. */
@Composable
fun SkeletonLine(
    modifier: Modifier = Modifier,
    width: Dp? = null,
    height: Dp = skeletonLineHeight,
) {
    SkeletonBlock(modifier = modifier, width = width, height = height, radius = skeletonCorner)
}

/**
 * A list row: poster plus stacked lines.
 *
 * The first line is 13 dp tall and every later line 10 dp — a title reads heavier than its
 * metadata, and a stack of identical bars reads as a table. The row height scales with the text
 * size so the swap to real content does not jump at accessibility sizes.
 *
 * A `poster` of zero width omits the art entirely (a text-only row).
 */
@Composable
fun SkeletonRow(
    poster: DpSize,
    lines: List<Dp>,
    modifier: Modifier = Modifier,
    posterRadius: Dp = skeletonCorner,
    spacing: Dp = ThemeSpace.x3,
    height: Dp = ThemeMetrics.rowStandard,
) {
    Row(
        modifier = modifier.heightIn(min = scaledDp(height)),
        horizontalArrangement = Arrangement.spacedBy(spacing),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (poster.width > 0.dp) {
            SkeletonPoster(width = poster.width, height = poster.height, radius = posterRadius)
        }
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(ThemeSpace.x2),
            horizontalAlignment = Alignment.Start,
        ) {
            lines.forEachIndexed { index, lineWidth ->
                SkeletonLine(
                    width = lineWidth,
                    height = if (index == 0) skeletonTitleLine else skeletonSupportLine,
                )
            }
        }
    }
}

/**
 * A card-shaped block — the shape a Focus, Recap or Next-up card will fill.
 *
 * Drawn at the card's own surface level: "a skeleton that sits at a different elevation than the
 * content it stands in for makes the swap land as a lighting change."
 */
@Composable
fun SkeletonCard(
    modifier: Modifier = Modifier,
    height: Dp = 168.dp,
    radius: Dp = ThemeRadius.card,
    content: @Composable ColumnScope.() -> Unit = {},
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = height)
            .surface(SurfaceLevel.Plate, radius)
            .padding(ThemeSpace.x4),
        verticalArrangement = Arrangement.spacedBy(ThemeSpace.x4),
        horizontalAlignment = Alignment.Start,
        content = content,
    )
}

/**
 * A horizontal poster shelf.
 *
 * Two hard-won defaults:
 *
 * * **[titleLines] must match what the destination `ShelfCard` RESERVES**, or the swap jumps. A
 *   `ShelfCard` reserves two *title* lines **plus** a caption; a skeleton that emits two lines
 *   total moved everything below it 44 pt at the swap, superimposed for the whole crossfade.
 * * **[count] defaults to 5, not 3**: "the real shelf runs off the trailing edge, and a skeleton
 *   that stops short of it promises a shorter shelf than the one that arrives."
 *
 * The last title line is 62 % of the poster's width and the caption 45 %, so the block reads as
 * wrapped text rather than as a stack of identical bars. Both line heights scale with the text
 * size, matching what the real caption occupies at every setting.
 *
 * The caller owns the scroller: a shelf wider than the screen inside a plain column sets the ideal
 * width of everything above it — "the WHOLE screen (wordmark and avatar included) gets centred
 * 14 pt to the left with the avatar hanging off the edge."
 */
@Composable
fun SkeletonShelf(
    modifier: Modifier = Modifier,
    count: Int = 5,
    size: DpSize = PosterSize.ShelfLarge.size,
    caption: Boolean = false,
    titleLines: Int = 2,
) {
    val titleLine = scaledDp(skeletonTitleLine)
    val captionLine = scaledDp(skeletonCaptionLine)
    Row(
        modifier = modifier,
        horizontalArrangement = Arrangement.spacedBy(ThemeMetrics.shelfGap),
        verticalAlignment = Alignment.Top,
    ) {
        repeat(count) {
            Column(
                verticalArrangement = Arrangement.spacedBy(ThemeSpace.x2),
                horizontalAlignment = Alignment.Start,
            ) {
                SkeletonPoster(width = size.width, height = size.height)
                Column(
                    modifier = Modifier.width(size.width),
                    verticalArrangement = Arrangement.spacedBy(ThemeSpace.x1),
                    horizontalAlignment = Alignment.Start,
                ) {
                    repeat(titleLines.coerceAtLeast(0)) { line ->
                        SkeletonLine(
                            width = if (line == titleLines - 1) size.width * 0.62f else size.width,
                            height = titleLine,
                        )
                    }
                    if (caption) {
                        SkeletonLine(width = size.width * 0.45f, height = captionLine)
                    }
                }
            }
        }
    }
}
