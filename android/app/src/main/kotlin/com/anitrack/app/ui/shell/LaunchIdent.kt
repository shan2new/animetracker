package com.anitrack.app.ui.shell

import android.util.Log
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.layout
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.imageResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import com.anitrack.app.BuildConfig
import com.anitrack.app.R
import com.anitrack.app.design.LocalReduceMotion
import com.anitrack.app.design.ThemeColor
import com.anitrack.app.design.brand.LaunchHandoff
import com.anitrack.app.design.brand.MarkGeometry
import com.anitrack.app.design.brand.RibbonShape
import com.anitrack.app.design.brand.drawPeriodBead
import com.anitrack.app.design.brand.drawRibbon
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.math.sqrt

/*
 * THE LAUNCH — the port of `ios/Sources/App/LaunchIdent.swift`. The app icon's ribbon, at
 * cinematic scale, lit — then the app comes through it.
 *
 * Android starts every launch on the platform's own splash: the adaptive icon in a disc on the
 * canvas (`Theme.Previously.Splash`). The ident's first frame IS that picture — the same launcher
 * layers, clipped to the same disc, at the frame the exit listener reports — so the hand-off from
 * the system to the app is a picture into itself, never two splashes. Then the disc's tile
 * dissolves and the ribbon is released from it: the drawing takes over from the bitmap and grows
 * from the icon's size to a third of the screen, a travelling light crossing it as it does, the
 * icon's material forming — the ramp, the rim, the pool of warm light it casts on the canvas —
 * and the coral full stop pulses once as it settles. The composition holds, still. Once auth has
 * answered, the ident pushes through: the composition grows a hair and fades as the app emerges
 * beneath it, settling from a hair small. One gesture, one object, the brand's own material; no
 * tagline, no flash, no haptic; nothing flies into a corner.
 *
 * EVERY value here is a pure function of live time — seconds of frames actually presented, read
 * off `withFrameNanos`, with any real stall between two frames cut out of the clock. There is not
 * one animation object in this file: a `delay` counts wall time while the main thread is still
 * busy, and an animation started in the same frame as the view's appearance is folded into it.
 * The clock is a `MutableFloatState` read only inside layout, draw and layer lambdas, so a frame
 * of the ident invalidates a draw, never a composition. The ribbon is ONE fixed-size layer moved
 * by transforms — its outline (the cast shadow's) never changes and nothing is re-measured per
 * frame; a per-frame re-measure held the emulator's UI thread at 300 ms a frame.
 *
 * Under Reduce Motion (animator scale 0) nothing grows or pushes: the disc gives way to the
 * composition at rest, which holds, then crossfades to the app.
 */

// ---------------------------------------------------------------------------------------------
// The beats, in seconds of live time
// ---------------------------------------------------------------------------------------------

private object Beats {
    /** The disc's tile dissolves and the bitmap gives way to the drawing. */
    const val RELEASE = 0.25f

    /** The ribbon grows from the icon's size to the ident's — a spring with one soft settle. */
    const val GROW_AT = 0.12f
    const val GROW_RESPONSE = 0.72f
    const val GROW_DAMPING = 0.86f

    /** The light crosses the ribbon head to foot as it grows. */
    const val SWEEP_AT = 0.20f
    const val SWEEP_FOR = 0.60f

    /** The pool of light beneath arrives as the ribbon settles. */
    const val CAST_AT = 0.50f
    const val CAST_FOR = 0.40f

    /** The full stop's one pulse of light, as the light passes the tails. */
    const val PULSE_AT = 0.52f
    const val PULSE_FOR = 0.45f

    /** The composition holds before it may leave. */
    // Stated in the stop's own clock (i2-2): SWEEP_AT + PULSE_AT + 0.22, so the brand's period
    // lands on every launch, fast network or slow.
    const val HOLD_UNTIL = SWEEP_AT + PULSE_AT + 0.22f

    /**
     * The push through: the composition grows and is gone before the ground has finished lifting,
     * so it never lingers as a ghost over the screen arriving beneath it.
     */
    const val EXIT_FOR = 0.28f
    const val EXIT_SCALE = 1.12f
    const val COMPOSITION_EXIT_FRACTION = 0.65f

    /** Under Reduce Motion: the hold before the crossfade, and the crossfade. */
    const val REDUCED_HOLD = 0.6f
    const val REDUCED_FADE = 0.22f

    /** Auth's own wait is capped at 3 s; the ident does not outlast it by much. */
    const val PATIENCE = 4.0f

    /** How long the ident waits for the billboard's art after auth has answered (i2). */
    const val ART_PATIENCE = 1.6f

    /** A WALL ceiling from the first frame (i4): live seconds cut stalls out, so a starved device had none. */
    const val WALL_CEILING = 2.4f
}

private object Geometry {
    /** The ribbon's width at rest: a third of the screen, where a title card sits. */
    val RIBBON_WIDTH = 120.dp

    /** The ribbon's centre as a fraction of the screen — a hair high, a hair left, the full stop balancing it. */
    const val REST_X = 0.5f
    const val REST_Y = 0.44f
    val REST_OFFSET_X = (-14).dp

    /**
     * The system splash: the adaptive icon drawn at [ICON_BOX] with its inner two-thirds visible —
     * a [ICON_DISC] disc — centred in the window. The iOS tile (1024) maps onto that disc. Measured
     * against the exit listener's frame when it fires; predicted from the window otherwise.
     */
    val ICON_BOX = 240.dp
    val ICON_DISC = 160.dp
    const val TILE = 1024f

    /** The ribbon in the icon (design/app-icon-v2/glass3.py `geometry`): x0 = 281.6, width 376, tails at 800. */
    const val ICON_RIBBON_LEFT = 281.6f
    const val ICON_RIBBON_WIDTH = 376f
}

// ---------------------------------------------------------------------------------------------
// Easing — the unit-step response of a damped spring at rest, and two ramps
// ---------------------------------------------------------------------------------------------

/** What Compose's `spring(dampingRatio, stiffness)` traces, as a function of time. */
private fun spring(t: Float, response: Float, damping: Float): Float {
    if (t <= 0f) return 0f
    val omega = 2f * PI.toFloat() / response
    if (damping < 1f) {
        val damped = omega * sqrt(1f - damping * damping)
        return 1f - exp(-damping * omega * t) * (cos(damped * t) + (damping * omega / damped) * sin(damped * t))
    }
    return 1f - exp(-omega * t) * (1f + omega * t)
}

/** A smooth 0 → 1 over [over] seconds. */
private fun ease(t: Float, over: Float): Float {
    val x = (t / over).coerceIn(0f, 1f)
    return x * x * (3f - 2f * x)
}

/** Gathering pace (quadratic in): the exit's own curve. */
private fun easeIn(t: Float, over: Float): Float {
    val x = (t / over).coerceIn(0f, 1f)
    return x * x
}

private fun lerp(a: Float, b: Float, p: Float) = a + (b - a) * p

private fun lerp(a: Rect, b: Rect, p: Float) =
    Rect(lerp(a.left, b.left, p), lerp(a.top, b.top, p), lerp(a.right, b.right, p), lerp(a.bottom, b.bottom, p))

// ---------------------------------------------------------------------------------------------
// The frame: every value on screen at live time t, in one place
// ---------------------------------------------------------------------------------------------

private enum class Stage { Holding, Leaving, Done }

private class IdentFrame(t: Float, leaveAt: Float?, reduceMotion: Boolean) {
    val stage: Stage

    /** The bitmap disc (the system splash's picture) over the drawing, 1 → 0. */
    val disc: Float

    /** The drawing's own presence, 0 → 1, as the bitmap gives way. */
    val drawn: Float

    /** The growth from the icon's ribbon to the ident's, 0 → 1 (a hair over, then back). */
    val grow: Float

    /** The light crossing the ribbon, 0 → 1 head to foot, or `null` while there is none. */
    val sweep: Float?

    /** The pool of light beneath. */
    val cast: Float

    /** The full stop's pulse, 0 → 1 → 0. */
    val pulse: Float

    /** The push through: the composition's scale and opacity, and the ground's opacity. */
    val scale: Float
    val opacity: Float
    val ground: Float

    init {
        if (reduceMotion) {
            // The disc gives way to the composition at rest; a hold; a crossfade out. Nothing travels.
            val fadeIn = ease(t, Beats.RELEASE)
            val out = leaveAt?.let { ease(t - it, Beats.REDUCED_FADE) } ?: 0f
            disc = 1f - fadeIn
            drawn = fadeIn
            grow = 1f
            sweep = null
            cast = 1f
            pulse = 0f
            scale = 1f
            opacity = 1f - out
            ground = 1f - out
            stage = leaveAt?.let { if (t >= it + 0.3f) Stage.Done else Stage.Leaving } ?: Stage.Holding
        } else {
            val release = ease(t, Beats.RELEASE)
            disc = 1f - release
            drawn = release
            grow = spring(t - Beats.GROW_AT, Beats.GROW_RESPONSE, Beats.GROW_DAMPING)
            val pass = ease(t - Beats.SWEEP_AT, Beats.SWEEP_FOR)
            sweep = if (pass > 0f && pass < 1f) pass else null
            cast = ease(t - Beats.CAST_AT, Beats.CAST_FOR)
            val beat = ((t - Beats.PULSE_AT) / Beats.PULSE_FOR).coerceIn(0f, 1f)
            pulse = if (beat > 0f && beat < 1f) sin(beat * PI.toFloat()) else 0f
            if (leaveAt != null) {
                val since = t - leaveAt
                val out = easeIn(since, Beats.EXIT_FOR * Beats.COMPOSITION_EXIT_FRACTION)
                scale = 1f + (Beats.EXIT_SCALE - 1f) * out
                opacity = 1f - out
                ground = 1f - easeIn(since, Beats.EXIT_FOR)
                stage = if (since >= Beats.EXIT_FOR) Stage.Done else Stage.Leaving
            } else {
                scale = 1f
                opacity = 1f
                ground = 1f
                stage = Stage.Holding
            }
        }
    }
}

/**
 * Live time for the ident: seconds of frames actually presented, not wall time. A stall between
 * two frames longer than [STALL] — the main thread was busy, nothing was presented — is cut out.
 */
private class IdentClock {
    private var start = 0L
    private var last = 0L
    private var firstNanos = 0L
    private var frames = 0
    var leaveAt: Float? = null
        private set

    fun tick(nanos: Long, authReady: Boolean, artReady: Boolean, reduceMotion: Boolean): Float {
        if (start == 0L) {
            start = nanos
            last = nanos
            firstNanos = nanos
            return 0f
        }
        val gap = (nanos - last) / 1_000_000_000f
        if (gap > STALL) start += nanos - last - 16_666_667L
        last = nanos
        val t = (nanos - start) / 1_000_000_000f
        if (BuildConfig.DEBUG && ++frames % 30 == 0) Log.d("Launch", "ident t=%.2f gap=%.0fms".format(t, gap * 1000f))
        if (leaveAt == null) {
            val held = t >= if (reduceMotion) Beats.REDUCED_HOLD else Beats.HOLD_UNTIL
            val ready = authReady && (artReady || t >= Beats.ART_PATIENCE)
            val overdue = (nanos - firstNanos) / 1_000_000_000f >= Beats.WALL_CEILING
            if (held && (ready || t >= Beats.PATIENCE)) leaveAt = t else if (overdue) leaveAt = t
        }
        return t
    }

    private companion object {
        /**
         * The largest gap between two frames that still counts as continuous. A merely slow frame
         * (an emulator at 8 fps) must NOT be cut: cutting it plays the motion in stepped slow
         * motion, which reads as dropped frames on top of the drop itself.
         */
        const val STALL = 0.25f
    }
}

// ---------------------------------------------------------------------------------------------
// The screen
// ---------------------------------------------------------------------------------------------

/**
 * The ident, and its half of the hand-off.
 *
 * @param handoff the launch's shared state: auth's answer and the system icon's frame; the ident
 *   writes its phase back into it.
 * @param onLeaving the ident has started to push through: the app should begin emerging.
 * @param onFinished the ident is gone; the caller removes it.
 */
@Composable
fun LaunchIdent(
    handoff: LaunchHandoff,
    onLeaving: () -> Unit,
    onFinished: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val reduceMotion = LocalReduceMotion.current
    val clock = remember { IdentClock() }
    val time = remember { mutableFloatStateOf(0f) }
    var done by remember { mutableStateOf(false) }

    val background = ImageBitmap.imageResource(R.mipmap.ic_launcher_background)
    val foreground = ImageBitmap.imageResource(R.mipmap.ic_launcher_foreground)

    // The clock. Written inside the frame callback — which runs before this frame's layout and
    // draw — and read only by the layout, draw and layer lambdas below.
    LaunchedEffect(reduceMotion) {
        while (!done) {
            withFrameNanos { nanos ->
                time.floatValue = clock.tick(nanos, authReady = handoff.authReady, artReady = handoff.artReady, reduceMotion = reduceMotion)
            }
        }
    }

    // The hand-off, off the draw path: the phase is state the shell reads.
    LaunchedEffect(reduceMotion) {
        snapshotFlow { IdentFrame(time.floatValue, clock.leaveAt, reduceMotion).stage }.collect { stage ->
            when (stage) {
                Stage.Holding -> Unit
                Stage.Leaving -> {
                    handoff.phase = LaunchHandoff.Phase.Leaving
                    onLeaving()
                }
                Stage.Done -> {
                    done = true
                    onFinished()
                }
            }
        }
    }

    BoxWithConstraints(
        modifier = modifier
            .fillMaxSize()
            .clearAndSetSemantics {},
    ) {
        val widthPx = constraints.maxWidth.toFloat()
        val heightPx = constraints.maxHeight.toFloat()

        // --- geometry, in px, resolved once per size
        val density = LocalDensity.current
        val iconBoxPx = with(density) { Geometry.ICON_BOX.toPx() }
        val iconDiscPx = with(density) { Geometry.ICON_DISC.toPx() }
        val restWidthPx = with(density) { Geometry.RIBBON_WIDTH.toPx() }
        val restOffsetPx = with(density) { Geometry.REST_OFFSET_X.toPx() }

        fun iconBox(): Rect {
            val reported = handoff.systemIcon
            if (reported != null && reported.width > 0f) return reported
            val cx = widthPx / 2f
            val cy = heightPx / 2f
            return Rect(cx - iconBoxPx / 2f, cy - iconBoxPx / 2f, cx + iconBoxPx / 2f, cy + iconBoxPx / 2f)
        }

        /** The ribbon as the icon draws it, in px: the tile mapped onto the disc. */
        fun iconRibbon(box: Rect): Rect {
            val s = iconDiscPx / Geometry.TILE
            val tileOrigin = Offset(box.center.x - iconDiscPx / 2f, box.center.y - iconDiscPx / 2f)
            val w = Geometry.ICON_RIBBON_WIDTH * s
            val left = tileOrigin.x + Geometry.ICON_RIBBON_LEFT * s
            val top = tileOrigin.y
            return Rect(left, top, left + w, top + w * MarkGeometry.ASPECT)
        }

        val rest = run {
            val w = restWidthPx
            val h = w * MarkGeometry.ASPECT
            val cx = widthPx * Geometry.REST_X + restOffsetPx
            val cy = heightPx * Geometry.REST_Y
            Rect(cx - w / 2f, cy - h / 2f, cx + w / 2f, cy + h / 2f)
        }
        // The composition's own frame — the lockup plus room for the light it casts — so the push
        // through fades a small layer, never a full-screen one.
        val pad = rest.width * 0.5f
        val lockup = Rect(
            rest.left - pad, rest.top - pad,
            rest.left + rest.width * MarkGeometry.LOCKUP_WIDTH + pad, rest.bottom + pad,
        )

        /** Where the ribbon is at this frame: grown from the icon's to its resting size. */
        fun ribbonRect(f: IdentFrame): Rect = lerp(iconRibbon(iconBox()), rest, f.grow)

        // 1 — the ground and the system splash's disc.
        Canvas(Modifier.fillMaxSize()) {
            val f = IdentFrame(time.floatValue, clock.leaveAt, reduceMotion)
            drawRect(ThemeColor.canvas, alpha = f.ground)
            if (f.disc > 0f) {
                val box = iconBox()
                val disc = Path().apply {
                    addOval(Rect(box.center.x - iconDiscPx / 2f, box.center.y - iconDiscPx / 2f, box.center.x + iconDiscPx / 2f, box.center.y + iconDiscPx / 2f))
                }
                val offset = IntOffset(box.left.roundToInt(), box.top.roundToInt())
                val boxSize = IntSize(box.width.roundToInt(), box.height.roundToInt())
                clipPath(disc) {
                    drawImage(background, dstOffset = offset, dstSize = boxSize, alpha = f.disc)
                    drawImage(foreground, dstOffset = offset, dstSize = boxSize, alpha = f.disc)
                }
            }
        }

        // 2 — the composition: one layer sized to the lockup, which the push through scales and
        // fades. Inside it, the ribbon is its own fixed-size layer moved by transforms (its
        // outline never changes), and the full stop with its pulse is drawn beside it.
        Box(
            Modifier
                .layout { measurable, constraints ->
                    val placeable = measurable.measure(
                        Constraints.fixed(lockup.width.roundToInt().coerceAtLeast(1), lockup.height.roundToInt().coerceAtLeast(1)),
                    )
                    layout(constraints.maxWidth, constraints.maxHeight) {
                        placeable.place(lockup.left.roundToInt(), lockup.top.roundToInt())
                    }
                }
                .graphicsLayer {
                    val f = IdentFrame(time.floatValue, clock.leaveAt, reduceMotion)
                    scaleX = f.scale
                    scaleY = f.scale
                    alpha = f.opacity
                },
        ) {
            Box(
                Modifier
                    .layout { measurable, constraints ->
                        val placeable = measurable.measure(
                            Constraints.fixed(rest.width.roundToInt().coerceAtLeast(1), rest.height.roundToInt().coerceAtLeast(1)),
                        )
                        layout(constraints.maxWidth, constraints.maxHeight) {
                            placeable.place((rest.left - lockup.left).roundToInt(), (rest.top - lockup.top).roundToInt())
                        }
                    }
                    .graphicsLayer {
                        val f = IdentFrame(time.floatValue, clock.leaveAt, reduceMotion)
                        val r = ribbonRect(f)
                        val scale = r.width / rest.width
                        transformOrigin = TransformOrigin(0.5f, 0f)
                        scaleX = scale
                        scaleY = scale
                        translationX = r.center.x - rest.center.x
                        translationY = r.top - rest.top
                        alpha = f.drawn
                        shape = RibbonShape
                        shadowElevation = if (f.cast > 0.02f) rest.width * 0.14f * f.cast else 0f
                        spotShadowColor = ThemeColor.markCastShadow
                        ambientShadowColor = ThemeColor.markCastShadow
                    },
            ) {
                Canvas(Modifier.fillMaxSize()) {
                    val f = IdentFrame(time.floatValue, clock.leaveAt, reduceMotion)
                    drawRibbon(Rect(Offset.Zero, size), material = 1f, sweep = f.sweep)
                }
            }

            Canvas(Modifier.fillMaxSize()) {
                val f = IdentFrame(time.floatValue, clock.leaveAt, reduceMotion)
                if (f.drawn <= 0f) return@Canvas
                val r = ribbonRect(f)
                val bead = MarkGeometry.periodRect(Rect(r.left - lockup.left, r.top - lockup.top, r.right - lockup.left, r.bottom - lockup.top))
                if (f.pulse > 0f) {
                    val reach = bead.width * (0.7f + 1.3f * f.pulse)
                    drawCircle(
                        brush = Brush.radialGradient(
                            0f to ThemeColor.brandPeriod.copy(alpha = 0.42f), 1f to Color.Transparent,
                            center = bead.center, radius = reach,
                        ),
                        radius = reach,
                        center = bead.center,
                        alpha = f.pulse * f.drawn,
                    )
                }
                drawPeriodBead(bead.center, bead.width, lit = true)
            }
        }
    }
}
