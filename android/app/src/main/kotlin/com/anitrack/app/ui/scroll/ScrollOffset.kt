package com.anitrack.app.ui.scroll

import androidx.compose.foundation.ScrollState
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.MutableFloatState
import androidx.compose.runtime.State
import androidx.compose.runtime.Stable
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.anitrack.app.design.ThemeMetrics

/**
 * A screen's scroll offset, as an object rather than as screen state.
 *
 * ## The rule, which is the whole reason this class exists
 *
 * **The scroll offset is never screen state.** Held as `@State` on the screen, the raw offset
 * re-ran Today's entire body — the stack, the queue, the shelf, the upcoming rows, every row diff —
 * on every frame of the first swipe. The user reported it twice on 2 Sep ("Today lags"), and the
 * shipped fix is the three halves below, all of which port:
 *
 * 1. **[set] quantises before it publishes.** Every veil, mask and title handover in the app
 *    saturates within the first ~120 dp of scroll and the pull-down within ~300; past that the
 *    offset changes nothing on screen. [ThemeMetrics.scrollSample] clamps to −320…240 and rounds to
 *    the half-point, and [set] then drops a write that would not change the value — so a settled
 *    chrome publishes **nothing at all**.
 * 2. **[y] is read only by deferred readers.** On iOS that meant "only the small views that draw
 *    the veils and stretch the hero may read it in a `body`". The Compose equivalent is stricter and
 *    easier to get wrong: read [y] inside a `Modifier.graphicsLayer { }` / `Modifier.drawBehind { }`
 *    lambda, or inside a [derivedStateOf], and **never in the body of a composable that draws the
 *    screen**. A body read defers that whole composable to the recomposition phase on every sampled
 *    frame, which is precisely the bug this class exists to prevent.
 * 3. **Boolean probes only emit on the flip.** [past] wraps the comparison in a [derivedStateOf], so
 *    a screen that hardens its bar at 12 dp recomposes twice for an entire scroll instead of sixty
 *    times. Use it rather than writing `if (scroll.y > x)` in a body.
 *
 * ## Units
 *
 * [y] is in **dp**, positive as content scrolls up and out of the viewport. Quantising raw pixels
 * would quantise to a different real distance on every density, so the conversion happens at the
 * feed — see [track].
 */
@Stable
class ScrollOffset {

    /**
     * Backed by [MutableFloatState] rather than `MutableState<Float>`: the value is written on
     * every sampled scroll frame and read from draw lambdas, and the primitive-specialised state
     * boxes nothing on either side.
     */
    private val sampled: MutableFloatState = mutableFloatStateOf(0f)

    /**
     * The same offset **without the ceiling** — the channel the boolean probes compare against.
     *
     * [ThemeMetrics.scrollSample]'s 240-dp ceiling is right for the veils: every one of them
     * saturates inside the first ~120 dp, so past that the number is worth nothing. It is wrong for
     * [past], whose thresholds are MEASURED: on a billboard screen `copyTop − band` lands 300–500 dp
     * down, above the ceiling, so a clamped comparison could never become true and Detail would
     * never harden its bar or dock its title — content scrolling through the clock, which is the one
     * defect this whole subsystem exists to prevent.
     *
     * Quantised to the half-point exactly as [sampled] is, and read only through a `derivedStateOf`,
     * so a screen still recomposes on the crossing rather than on the scroll.
     */
    private val sampledRaw: MutableFloatState = mutableFloatStateOf(0f)

    /**
     * The sampled offset in dp.
     *
     * Reading this is a snapshot-state read. Read it from a `graphicsLayer` / `drawBehind` lambda or
     * from a [derivedStateOf] — see the class doc. A read in a composable body is a defect, not a
     * style preference.
     */
    val y: Float get() = sampled.floatValue

    /**
     * Publish a new raw offset, in **dp**.
     *
     * Clamped and rounded by [ThemeMetrics.scrollSample], then de-duplicated. The de-duplication is
     * what stops recomposition; the clamp alone would not, because the raw value keeps arriving.
     */
    fun set(rawDp: Float) {
        val v = ThemeMetrics.scrollSample(rawDp)
        if (v != sampled.floatValue) sampled.floatValue = v
        // The unclamped channel takes the same quantisation and the same de-duplication, and only
        // the ceiling is dropped. See [sampledRaw].
        val raw = ThemeMetrics.scrollSample(rawDp, lowerBound = -UNCLAMPED_BOUND, upperBound = UNCLAMPED_BOUND)
        if (raw != sampledRaw.floatValue) sampledRaw.floatValue = raw
    }

    /**
     * The offset in dp with no ceiling applied. **For [past] only** — every drawn consumer wants
     * [y], which is quantised and clamped to the range anything on screen can actually use.
     */
    internal val unclampedY: Float get() = sampledRaw.floatValue

    /** 0 while a hero owns the status bar, 1 once anything is close enough to touch the clock. */
    val veilOpacity: Float
        get() = ((y - veilOnset) / veilRun).coerceIn(0f, 1f)

    /**
     * The pull-down, as extra art height.
     *
     * **On Android this is always 0, and that is the correct answer** (`fidelity-line.md` Q6). iOS
     * grows the hero's art by the rubber band because SwiftUI hands the app the negative offset and
     * nothing else fills the gap. Android answers overscroll natively — the platform stretches the
     * whole scroll container, hero included — so the ruling is to use it and *not* to intercept
     * `onPreScroll` and rebuild iOS's curve. A scroll position on Android never goes negative, so a
     * ported `height + scroll.stretch` is a no-op that still compiles and still reads correctly.
     * The billboard keeps its identity through its size, art and copy hierarchy, which is what makes
     * it a billboard — not through a particular rubber-band curve.
     */
    val stretch: Float get() = (-y).coerceAtLeast(0f)
}

/** 0 until 16 dp of scroll. */
private const val veilOnset = 16f

/** …and fully on by 80. */
private const val veilRun = 64f

/**
 * Beyond the first item there is no meaningful distance left to report.
 *
 * Every consumer saturates within ~120 dp, and this is [ThemeMetrics.scrollSample]'s own ceiling, so
 * feeding it is identical to feeding a much larger number and cheaper than computing one.
 */
private const val saturatedOffsetDp = 240f

/**
 * The ceiling the unclamped channel keeps.
 *
 * A bound rather than none at all, so a runaway value can never reach a `Float` at which the
 * half-point quantisation stops being exact. It is far above any threshold a screen can measure —
 * a billboard's copy top is 300–500 dp — so nothing real is clamped by it.
 */
private const val UNCLAMPED_BOUND = 100_000f

/**
 * What a [LazyListState] feed reports once the hero has left the viewport entirely.
 *
 * Every screen that owns a [ScrollOffset] has the hero as item 0, and every measured threshold a
 * screen passes to [past] is a position INSIDE that hero. So once item 0 is gone, every one of them
 * is passed, and the honest answer is "further than any of them" — not [saturatedOffsetDp], which
 * is the veils' end stop and would leave the boolean probes reading false forever.
 */
private const val pastFirstItemDp = UNCLAMPED_BOUND

/** One [ScrollOffset] per screen, for the lifetime of that screen's composition. */
@Composable
fun rememberScrollOffset(): ScrollOffset = remember { ScrollOffset() }

/**
 * Is the offset past [threshold]?
 *
 * The port of iOS's guarded boolean probes (`raisedTop`, `scrolledUnderBar`), which were written
 * back to screen state with `if (new != old)` around every assignment. [derivedStateOf] is the
 * native form of that guard: the returned [State] notifies its readers only when the boolean
 * actually flips, so the screen recomposes on the crossing rather than on the scroll.
 *
 * ```
 * val raisedTop by scroll.past(ThemeMetrics.topChromeRamp)
 * val scrolledUnderBar by scroll.past(copyTop - band)   // measured, never a flat 130
 * ```
 *
 * Detail's threshold is a *measured* one — `heroHeight − x4 − heroCopyHeight`, minus the bar's band
 * — and Today's is measured too. A flat 130 dp let the title slide half-lit under the bar for ~80 dp
 * before the chrome caught it (captured 3 Sep), and `scrollY > 150` never tripped at all on a
 * compact library. Pass a computed [Dp]; do not invent a constant here.
 *
 * It compares against the **unclamped** offset, not [ScrollOffset.y]: those measured thresholds sit
 * at 300–500 dp on a billboard screen, well above the veils' 240-dp sampling ceiling, so a clamped
 * comparison would be permanently false and the bar would never harden.
 */
@Composable
fun ScrollOffset.past(threshold: Dp): State<Boolean> =
    remember(this, threshold) { derivedStateOf { unclampedY >= threshold.value } }

/**
 * Feed this offset from a `Modifier.verticalScroll` container.
 *
 * `snapshotFlow` conflates and only emits on change, so the pipeline is: scroll frame → conflated
 * emission → [ScrollOffset.set] → quantise → drop if unchanged. Nothing downstream sees a frame that
 * would not move a pixel.
 *
 * This replaces iOS's `Color.clear.onGeometryChange` probe on the scroll content, which existed
 * because `onScrollGeometryChange` never fired on the iOS 27 simulator. A Compose scroll state is
 * the position itself rather than a callback about it, so there is nothing to be belt-and-braces
 * about and no layout probe to keep in sync.
 */
@Composable
fun ScrollOffset.track(state: ScrollState) {
    val density = LocalDensity.current
    LaunchedEffect(this, state, density) {
        snapshotFlow { with(density) { state.value.toDp().value } }
            .collect { set(it) }
    }
}

/**
 * Feed this offset from a `LazyColumn`.
 *
 * `firstVisibleItemScrollOffset` is the distance travelled *within the first item*, which is exactly
 * the screen's scroll distance while that item is on screen — and on every screen that owns a
 * [ScrollOffset] the first item is the hero, which is 0.68–0.72 × the screen tall. Once it has left,
 * the offset is reported as [pastFirstItemDp]: past that point every veil, mask and title handover
 * is already at its end stop, so the exact distance is not information any consumer can use — but
 * it must still read as *past* every measured threshold, which is why it is not the veils' own
 * ceiling. `set` clamps it back to [saturatedOffsetDp] for the drawn channel.
 */
@Composable
fun ScrollOffset.track(state: LazyListState) {
    val density = LocalDensity.current
    LaunchedEffect(this, state, density) {
        snapshotFlow {
            if (state.firstVisibleItemIndex > 0) {
                pastFirstItemDp
            } else {
                with(density) { state.firstVisibleItemScrollOffset.toDp().value }
            }
        }.collect { set(it) }
    }
}

/**
 * The offset as a [Dp], for the rare consumer that lays out against it.
 *
 * Kept as an explicit conversion rather than a second stored value so there is one source of truth
 * and one quantisation. It is still a snapshot-state read: the same deferred-read rule applies.
 */
val ScrollOffset.yDp: Dp get() = y.dp
