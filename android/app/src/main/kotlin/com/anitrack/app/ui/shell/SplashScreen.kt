package com.anitrack.app.ui.shell

import android.graphics.RenderEffect as AndroidRenderEffect
import android.graphics.RuntimeShader
import android.os.Build
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlurEffect
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.Paint
import androidx.compose.ui.graphics.RenderEffect
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.asComposeRenderEffect
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.res.imageResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import com.anitrack.app.R
import com.anitrack.app.design.AppFont
import com.anitrack.app.design.FeedbackCoordinator
import com.anitrack.app.design.FeedbackToken
import com.anitrack.app.design.LocalReduceMotion
import com.anitrack.app.design.ThemeColor
import com.anitrack.app.ui.chrome.LocalCanUseMaterial
import com.anitrack.model.copy.Copy
import kotlin.math.PI
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlinx.coroutines.delay

/*
 * THE BRAND IDENT — the port of `ios/Sources/App/SplashView.swift`.
 *
 * A single-climax ~2 s ident. **All motion is pure math over elapsed real time**: there is not one
 * animation object in this file, no spring, no `animate*AsState`. Every value on screen is a
 * function of `tm`, the seconds since the first frame — which is exactly what makes it portable
 * without re-tuning, and exactly what keeps it off the recomposer: `tm` lives in a
 * `MutableFloatState` that only DRAW and LAYER lambdas read, so a frame of the ident invalidates a
 * draw and never a composition.
 *
 * Base is true black for OLED — the pixels stay off, seamless with the system launch frame, which
 * `Theme.Previously.Splash` pins to the same `#000000`.
 *
 * ### The two shaders (PLAN D19)
 *
 * `emberZoom` (a 10-tap radial smear with a chromatic fringe, so the dive reads as going THROUGH
 * the ember rather than past it) and `filmGrain` are Metal on iOS and AGSL here, and AGSL
 * `RuntimeShader` is API 33+. **Below 33 the dive is a plain scale and the grain is dropped** — the
 * grain is near-invisible by design, so its loss is a loss of nothing, and the dive keeps its shape
 * from the scale-around-the-dot that carries it.
 *
 * ### What the artwork is
 *
 * Three PNG layers — the back card peeking out, the front card, and the progress bar with its
 * ember. The iOS ident draws its mark as a vector path; this one composites the shipped icon
 * artwork, and the two anchor constants ([SplashGeometry.DOT_X] / [SplashGeometry.DOT_Y]) are
 * MEASURED from that artwork rather than carried across, because they name a point in a different
 * drawing. iOS records the same lesson from the other direction: *"the mock's hand-measured 0.424
 * was ~30 pt left of where the dot actually lands."*
 */

// ---------------------------------------------------------------------------------------------
// The timeline
// ---------------------------------------------------------------------------------------------

private object SplashTiming {

    /**
     * THE CLIMAX. Every climax event — the haptic, the wordmark punch, the light flood — is keyed
     * to it: it is the moment the sweep's leading edge crosses the dot.
     */
    const val IGNITE = 0.92f

    /**
     * Real time at which we hand off to the app — EARLY IN THE PUSH, so the root's crossfade
     * overlaps the zoom-through and the app emerges from inside the icon.
     */
    const val HANDOFF = 1.68f

    /** The stage keeps animating to here underneath the crossfade. Past it nothing changes. */
    const val STAGE_END = 2.10f

    /**
     * Under Reduce Motion `tm` is PINNED here — a still frame of the ident at its settled state.
     * Nothing runs; there is no timeline to shorten, so it is not shortened.
     */
    const val REDUCED_FRAME = 1.4f

    /** How long that still frame is held before the hand-off. */
    const val REDUCED_HOLD_MS = 1_200L
}

private object SplashGeometry {
    /** Icon comp width ÷ screen width. */
    const val COMP_FRACTION = 640f / 1080f

    /** Comp top as a fraction of screen height. */
    const val COMP_TOP = 560f / 1920f

    // Measured from `splash_layer_progress.png` (a 1024² box): the ember's centre is (572, 708),
    // its radius 30, and the bar's track starts at x = 220. The dive scales around the ember, so
    // being wrong here is being wrong about what the camera flies into.
    const val DOT_X = 572f / 1024f
    const val DOT_Y = 708f / 1024f
    const val DOT_R = 30f / 1024f
    const val BAR_LEFT = 220f / 1024f

    /**
     * The sweep value at which the ember reaches its saved place — chosen so `fl` crosses it at
     * `tm ≈ IGNITE`.
     */
    const val DOT_ARRIVE = 0.571f

    const val WORDMARK_TOP = 1150f / 1920f
    const val TAGLINE_TOP = 1330f / 1920f
}

private object SplashInk {
    /** Wordmark ink. Splash-local, and deliberately NOT `textPrimary`. */
    val ink = Color(0xFFF4EFE6)

    /**
     * The wordmark full stop's gradient end — the MARK's own shaded stop, so the ident's period and
     * the ribbon it flies out of are lit by one gradient rather than by two equal literals.
     */
    val accentDeep = ThemeColor.markShadow

    /** The ember's own light — the flash, the glow, the shockwave. */
    val ember = Color(0xFFF6BD7D)

    /** The ember's specular top, sampled from the artwork so the drawn dot matches the drawn one. */
    val dotHighlight = Color(0xFFFDD39A)

    /** The stage light. */
    val stage = Color(0xFF4A3B24)

    // The five-stop ground the icon lands on.
    val ground0 = Color(0xFF2A1F14)
    val ground1 = Color(0xFF1C1510)
    val ground2 = Color(0xFF12100C)
    val ground3 = Color(0xFF0C0B09)
}

// The name and the ident's line are `Copy.Brand`'s — this screen used to declare its own spelling
// of both, and the app's two brand lines could not be read side by side because they lived in two
// files that never mention each other.

// ---------------------------------------------------------------------------------------------
// Easing — clamped normalise plus the five curves, exactly as the Swift declares them
// ---------------------------------------------------------------------------------------------

private fun seg(p: Float, a: Float, b: Float): Float = ((p - a) / (b - a)).coerceIn(0f, 1f)

private fun outQuint(t: Float): Float {
    val u = 1f - t
    return 1f - u * u * u * u * u
}

private fun inOutQuint(t: Float): Float =
    if (t < 0.5f) {
        16f * t * t * t * t * t
    } else {
        val u = -2f * t + 2f
        1f - (u * u * u * u * u) / 2f
    }

private fun inOutCubic(t: Float): Float =
    if (t < 0.5f) {
        4f * t * t * t
    } else {
        val u = -2f * t + 2f
        1f - (u * u * u) / 2f
    }

private fun inCubic(t: Float): Float = t * t * t

private fun outCubic(t: Float): Float {
    val u = 1f - t
    return 1f - u * u * u
}

/**
 * Every driver value for one instant, in the order the Swift evaluates them.
 *
 * Cheap enough to build per draw lambda per frame (three of them, for ~2 s) and far clearer than
 * threading eleven floats.
 */
private class SplashFrame(val tm: Float) {

    /** The icon lands from depth: scale 1.16 → 1, the blur clears. */
    val ar = outQuint(seg(tm, 0f, 0.55f))

    /** The progress ember travels to its saved place. */
    val fl = inOutCubic(seg(tm, 0.50f, 1.30f))

    /** THE IGNITION GATE. 0 → 1 across `fl` ∈ [0.501, 0.601]. */
    val lit = seg(fl, SplashGeometry.DOT_ARRIVE - 0.07f, SplashGeometry.DOT_ARRIVE + 0.03f)

    /**
     * The stage light DIPS a breath before ignition, so the flood that follows reads bigger —
     * contrast bought just before it is spent.
     */
    val dip = seg(tm, 0.70f, 0.88f) * (1f - lit)

    /** The light jumps on the beat, then settles high. */
    val flood = lit * (1f - 0.45f * seg(tm, 1.15f, 1.60f))

    /** Wordmark punch-in, keyed to the ignite. */
    val w = outQuint(seg(tm, SplashTiming.IGNITE, 1.28f))

    /** Tagline, a breath later. */
    val tg = outQuint(seg(tm, 1.06f, 1.46f))

    /** Post-ignition breath in the ember. */
    val breathe = seg(tm, 1.30f, 1.60f) *
        (0.5f + 0.5f * sin(((tm - 1.30f) * PI.toFloat() / 1.1f)))

    val dotGlow = lit * (0.75f - 0.30f * seg(tm, 1.10f, 1.50f)) + breathe * 0.15f
    val glowScale = 1f + 0.45f * lit * (1f - 0.75f * seg(tm, 1.10f, 1.55f))

    /** One specular pass across the card. */
    val sheen = inOutQuint(seg(tm, 1.00f, 1.70f))

    /** THE CAMERA DIVE. */
    val push = inCubic(seg(tm, 1.60f, SplashTiming.STAGE_END))

    val tgOut = outQuint(seg(tm, 1.55f, 1.80f))
    val wOut = outQuint(seg(tm, 1.60f, 1.90f))
    val iFade = seg(tm, 1.80f, 2.08f)

    /** The ember's travel, 0 → 1. The bar is drawn behind it as it goes. */
    val progress = (fl / SplashGeometry.DOT_ARRIVE).coerceAtMost(1f)

    /** The icon's own scale: it lands, then the camera dives through it. */
    val iconScale = (1.16f - 0.16f * ar) * (1f + 1.15f * push)

    /** The ignition flash over everything. */
    val flash = 0.07f * lit * (1f - seg(tm, 0.97f, 1.35f))

    /** The shockwave ring, mounted only inside its own window. */
    val ring = outCubic(seg(tm, SplashTiming.IGNITE, 1.47f))
    val ringLive = tm > SplashTiming.IGNITE && tm < SplashTiming.IGNITE + 0.55f
}

// ---------------------------------------------------------------------------------------------
// The screen
// ---------------------------------------------------------------------------------------------

/**
 * The ident, and the half of the hand-off that belongs to it.
 *
 * @param onFinished called at [SplashTiming.HANDOFF] (or after [SplashTiming.REDUCED_HOLD_MS] under
 *   Reduce Motion). It is not the end of the animation — the stage keeps running to
 *   [SplashTiming.STAGE_END] underneath the root's crossfade, which is what makes the app emerge
 *   from inside the icon rather than after it.
 */
@Composable
fun SplashScreen(
    onFinished: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val reduceMotion = LocalReduceMotion.current
    val canUseEffects = LocalCanUseMaterial.current

    // The clock. Written every frame, read ONLY inside draw and graphicsLayer lambdas — so a frame
    // of the ident costs a draw, never a recomposition. This is the same discipline the scroll
    // offset is held to, for the same reason.
    val clock = remember { mutableFloatStateOf(if (reduceMotion) SplashTiming.REDUCED_FRAME else 0f) }

    LaunchedEffect(reduceMotion) {
        if (reduceMotion) {
            // A still frame of the ident at its settled state. Nothing runs.
            clock.floatValue = SplashTiming.REDUCED_FRAME
            return@LaunchedEffect
        }
        // `start` is taken on the FIRST FRAME, not at composition — so a slow cold launch does not
        // consume the timeline before anything has been drawn.
        var start = 0L
        var elapsed = 0f
        while (elapsed < SplashTiming.STAGE_END) {
            withFrameNanos { now ->
                if (start == 0L) start = now
                elapsed = (now - start) / 1_000_000_000f
                // Written INSIDE the frame callback, which runs before this frame's composition and
                // draw: written after it resumes, every value would be drawn one frame late.
                clock.floatValue = elapsed
            }
        }
    }

    LaunchedEffect(reduceMotion) {
        if (!reduceMotion) {
            delay((SplashTiming.IGNITE * 1000f).toLong())
            // ONE soft tap, exactly as the ember ignites. The app's only launch haptic.
            FeedbackCoordinator.fire(FeedbackToken.SELECTION)
            delay(((SplashTiming.HANDOFF - SplashTiming.IGNITE) * 1000f).toLong())
        } else {
            delay(SplashTiming.REDUCED_HOLD_MS)
        }
        onFinished()
    }

    val peek = ImageBitmap.imageResource(R.drawable.splash_layer_peek)
    val card = ImageBitmap.imageResource(R.drawable.splash_layer_card)
    val progress = ImageBitmap.imageResource(R.drawable.splash_layer_progress)
    val measurer = rememberTextMeasurer()

    // Film grain over the whole ident, quantised to 24 fps. Deliberately near-invisible; absent
    // below API 33, where there is no AGSL to express it and nothing anyone could point at is lost.
    val grainShader = remember(canUseEffects) { runtimeShader(FILM_GRAIN_AGSL, canUseEffects) }

    BoxWithConstraints(
        modifier = modifier
            .fillMaxSize()
            .graphicsLayer {
                renderEffect = grainShader?.let { shader ->
                    // Quantised to 1/24 s: grain that changes every frame at 120 Hz is a shimmer,
                    // not a film stock.
                    val quantised = (clock.floatValue * GRAIN_FPS).toInt() / GRAIN_FPS
                    shader.setFloatUniform("time", quantised)
                    shader.setFloatUniform("intensity", GRAIN_INTENSITY)
                    AndroidRenderEffect.createRuntimeShaderEffect(shader, "src").asComposeRenderEffect()
                }
            }
            // True black, not `canvas`: the pixels stay off, and the system launch frame under it
            // is the same black.
            .background(Color.Black)
            // The ident says nothing a screen reader needs; the app behind it is what is announced.
            .clearAndSetSemantics {},
    ) {
        val comp = maxWidth * SplashGeometry.COMP_FRACTION
        val iconLeft = (maxWidth - comp) / 2
        val iconTop = maxHeight * SplashGeometry.COMP_TOP

        // 1 — the ground, the stage light and the vignette.
        Canvas(Modifier.fillMaxSize()) { drawStage(SplashFrame(clock.floatValue)) }

        // 2 — the icon. Its own layer, because the dive is a transform ABOUT THE EMBER and the
        // landing blur is a render effect on the group.
        Box(
            Modifier
                .offset(x = iconLeft, y = iconTop)
                .size(comp)
                .graphicsLayer {
                    val f = SplashFrame(clock.floatValue)
                    scaleX = f.iconScale
                    scaleY = f.iconScale
                    // "Push scales around the dot itself — we zoom THROUGH the ember."
                    transformOrigin = TransformOrigin(SplashGeometry.DOT_X, SplashGeometry.DOT_Y)
                    alpha = f.ar * (1f - f.iFade)
                    renderEffect = iconEffect(f, size.width, size.height, canUseEffects, this.density)
                },
        ) {
            Canvas(Modifier.fillMaxSize()) {
                drawIcon(SplashFrame(clock.floatValue), peek, card, progress)
            }
        }

        // 3–7 — shockwave, ember bloom, wordmark, tagline, ignition flash.
        Canvas(Modifier.fillMaxSize()) {
            drawOverlay(
                f = SplashFrame(clock.floatValue),
                measurer = measurer,
                comp = comp.toPx(),
                iconTopPx = iconTop.toPx(),
                iconLeftPx = iconLeft.toPx(),
            )
        }
    }
}

// ---------------------------------------------------------------------------------------------
// 1 — the stage
// ---------------------------------------------------------------------------------------------

private fun DrawScope.drawStage(f: SplashFrame) {
    drawRect(Color.Black)

    drawRect(
        brush = Brush.verticalGradient(
            0.00f to SplashInk.ground0,
            0.22f to SplashInk.ground1,
            0.45f to SplashInk.ground2,
            0.70f to SplashInk.ground3,
            1.00f to Color.Black,
        ),
        alpha = f.ar * 0.9f,
    )

    // The stage light, centred where the icon sits. Its own alpha dips a breath before the ignite
    // and floods on it.
    val stageAlpha = 0.16f - 0.07f * f.dip + 0.34f * f.flood
    val stageRadius = (STAGE_RADIUS + STAGE_RADIUS_LIT * f.lit).dp.toPx()
    val stageCentre = Offset(size.width * 0.5f, size.height * 0.42f)
    drawCircle(
        brush = Brush.radialGradient(
            0f to SplashInk.stage.copy(alpha = stageAlpha),
            1f to Color.Transparent,
            center = stageCentre,
            radius = stageRadius,
        ),
        radius = stageRadius,
        center = stageCentre,
        alpha = f.ar,
    )

    val vignetteRadius = (VIGNETTE_RADIUS * f.ar).coerceAtLeast(1f).dp.toPx()
    drawRect(
        brush = Brush.radialGradient(
            0f to Color.Transparent,
            1f to Color.Black.copy(alpha = 0.4f),
            center = center,
            radius = vignetteRadius,
        ),
    )
}

// ---------------------------------------------------------------------------------------------
// 2 — the icon
// ---------------------------------------------------------------------------------------------

private fun DrawScope.drawIcon(
    f: SplashFrame,
    peek: ImageBitmap,
    card: ImageBitmap,
    progress: ImageBitmap,
) {
    val box = IntSize(size.width.roundToInt(), size.height.roundToInt())

    // The back card, peeking out above the front one.
    drawImage(image = peek, dstOffset = IntOffset.Zero, dstSize = box)

    // The front card, with one specular pass over it. The sheen is clipped to the card's own alpha
    // — a band of light that spilled past the card's edge would read as a bug, not as a highlight —
    // which is what the layer plus `SrcAtop` buys.
    if (f.sheen > 0f && f.sheen < 1f) {
        drawIntoCanvas { canvas ->
            canvas.saveLayer(Rect(0f, 0f, size.width, size.height), Paint())
            drawImage(image = card, dstOffset = IntOffset.Zero, dstSize = box)
            val bandWidth = size.width * SHEEN_WIDTH
            val travel = -0.9f + 1.8f * f.sheen
            rotate(degrees = SHEEN_ANGLE, pivot = center) {
                translate(left = size.width * travel, top = 0f) {
                    drawRect(
                        brush = SolidColor(Color.White.copy(alpha = 0.09f)),
                        topLeft = Offset(size.width / 2f - bandWidth / 2f, -size.height / 2f),
                        size = Size(bandWidth, size.height * 2f),
                        alpha = sin(f.sheen * PI.toFloat()),
                        blendMode = BlendMode.SrcAtop,
                    )
                }
            }
            canvas.restore()
        }
    } else {
        drawImage(image = card, dstOffset = IntOffset.Zero, dstSize = box)
    }

    // The progress bar, REVEALED to the ember's leading edge rather than drawn whole: the artwork
    // draws the ember at the end of a filled bar, so clipping to where the ember has reached is
    // what makes the bar grow behind it.
    val from = (SplashGeometry.BAR_LEFT + SplashGeometry.DOT_R) * size.width
    val to = SplashGeometry.DOT_X * size.width
    val leadX = from + (to - from) * f.progress
    val dotY = SplashGeometry.DOT_Y * size.height
    val dotR = SplashGeometry.DOT_R * size.width

    clipRect(left = 0f, top = 0f, right = leadX, bottom = size.height) {
        drawImage(image = progress, dstOffset = IntOffset.Zero, dstSize = box)
    }

    // The travelling ember. It rides the bar's leading edge and lands EXACTLY on the artwork's own
    // dot, which the clip reveals underneath it at the same instant — so the arrival is a landing,
    // never a pop.
    drawCircle(
        brush = Brush.radialGradient(
            0f to SplashInk.dotHighlight,
            1f to ThemeColor.accent,
            center = Offset(leadX - dotR * 0.3f, dotY - dotR * 0.3f),
            radius = dotR,
        ),
        radius = dotR,
        center = Offset(leadX, dotY),
    )

    // Its glow, which is what actually ignites.
    if (f.dotGlow > 0f) {
        val glowRadius = size.width * 0.11f * f.glowScale
        drawCircle(
            brush = Brush.radialGradient(
                0.0f to SplashInk.ember.copy(alpha = 0.85f),
                0.5f to ThemeColor.accent.copy(alpha = 0.2f),
                1.0f to Color.Transparent,
                center = Offset(leadX, dotY),
                radius = glowRadius,
            ),
            radius = glowRadius,
            center = Offset(leadX, dotY),
            alpha = f.dotGlow.coerceIn(0f, 1f),
        )
    }
}

/**
 * The icon group's render effect: the dive's smear while it is diving, the landing blur before it.
 *
 * Both are `RenderEffect`s rather than `Modifier.blur`, so the clock stays a deferred read — and
 * because `Modifier.blur` is a SILENT NO-OP below API 31, which would leave the floor device with a
 * different landing and no way to notice.
 */
private fun iconEffect(
    f: SplashFrame,
    width: Float,
    height: Float,
    canUseEffects: Boolean,
    density: Float,
): RenderEffect? = when {
    !canUseEffects -> null

    f.push > 0.001f -> emberZoom?.let { shader ->
        shader.setFloatUniform(
            "center",
            SplashGeometry.DOT_X * width,
            SplashGeometry.DOT_Y * height,
        )
        shader.setFloatUniform("strength", f.push)
        AndroidRenderEffect.createRuntimeShaderEffect(shader, "layer").asComposeRenderEffect()
    }

    f.ar < 0.99f -> {
        val radius = (1f - f.ar) * LANDING_BLUR * density
        if (radius > 0.1f) BlurEffect(radius, radius) else null
    }

    else -> null
}

// ---------------------------------------------------------------------------------------------
// 3–7 — the shockwave, the bloom, the lockup and the flash
// ---------------------------------------------------------------------------------------------

private fun DrawScope.drawOverlay(
    f: SplashFrame,
    measurer: TextMeasurer,
    comp: Float,
    iconLeftPx: Float,
    iconTopPx: Float,
) {
    val dot = Offset(
        iconLeftPx + comp * SplashGeometry.DOT_X,
        iconTopPx + comp * SplashGeometry.DOT_Y,
    )

    // 3 — the shockwave, mounted only inside its own window.
    if (f.ringLive) {
        val alpha = (1f - f.ring) * (1f - f.ring) * 0.30f
        drawCircle(
            color = SplashInk.ember.copy(alpha = alpha),
            radius = comp * 0.06f * (0.4f + 6.5f * f.ring),
            center = dot,
            style = Stroke(width = (1f + 3.5f * (1f - f.ring)).dp.toPx()),
        )
    }

    // 4 — the ember bloom the camera dives into.
    if (f.push > 0f) {
        val bloomRadius = comp * 0.75f * (0.25f + 2.6f * f.push)
        drawCircle(
            brush = Brush.radialGradient(
                0.0f to SplashInk.ember.copy(alpha = 0.55f),
                0.4f to ThemeColor.accent.copy(alpha = 0.18f),
                1.0f to Color.Transparent,
                center = dot,
                radius = bloomRadius,
            ),
            radius = bloomRadius,
            center = dot,
            alpha = sin((f.push * 1.25f).coerceAtMost(1f) * PI.toFloat()) * 0.6f,
        )
    }

    // 5 — the wordmark.
    if (f.w > 0f && f.wOut < 1f) {
        drawWordmark(f, measurer)
    }

    // 6 — the tagline.
    if (f.tg > 0f && f.tgOut < 1f) {
        drawTagline(f, measurer)
    }

    // 7 — the ignition flash.
    if (f.flash > 0f) {
        drawRect(color = SplashInk.ember.copy(alpha = f.flash))
    }
}

private fun DrawScope.drawWordmark(f: SplashFrame, measurer: TextMeasurer) {
    val fs = size.width * WORDMARK_SIZE
    // "Letters start airy and settle tight." The tracking is quantised to 24 steps so the punch-in
    // re-measures nine times rather than once per frame: a text layout is cached on its exact style,
    // and a tracking that changes every frame would miss the cache every frame.
    val settle = (f.w * TRACKING_STEPS).roundToInt() / TRACKING_STEPS
    val tracking = fs * (-0.03f * settle + 0.025f * (1f - settle))

    val text: AnnotatedString = buildAnnotatedString {
        append(Copy.Brand.word)
        // The full stop is the brand's one flourish: an amber gradient, always.
        withStyle(
            SpanStyle(
                brush = Brush.linearGradient(listOf(ThemeColor.accent, SplashInk.accentDeep)),
            ),
        ) {
            append(Copy.Brand.period)
        }
    }
    val style = TextStyle(
        fontFamily = AppFont.outfit,
        fontWeight = FontWeight.Bold,
        // Fixed art: the size is a fraction of the SCREEN, so it is converted through the density
        // rather than declared in `sp`, which would let the user's font scale resize a logo.
        fontSize = fs.toSp(),
        letterSpacing = tracking.toSp(),
        color = SplashInk.ink,
    )
    val layout = measurer.measure(text, style)

    val centreY = size.height * SplashGeometry.WORDMARK_TOP + fs / 2f
    val left = (size.width - layout.size.width) / 2f
    val top = centreY - layout.size.height / 2f

    val exit = 1f + 0.30f * outQuint(seg(f.tm, 1.60f, 2.00f))
    val scale = (1.06f - 0.06f * f.w) * exit

    scale(scale, scale, pivot = Offset(size.width / 2f, size.height * SplashGeometry.WORDMARK_TOP)) {
        translate(top = (1f - f.w) * WORDMARK_RISE.dp.toPx()) {
            drawText(
                textLayoutResult = layout,
                topLeft = Offset(left, top),
                alpha = (f.w * (1f - f.wOut)).coerceIn(0f, 1f),
            )
        }
    }
}

private fun DrawScope.drawTagline(f: SplashFrame, measurer: TextMeasurer) {
    val fs = size.width * TAGLINE_SIZE
    val style = TextStyle(
        // Deliberately the platform's monospace, and deliberately not Dynamic Type: a fixed-art
        // splash caption. It is the one string in the app that is not in the brand face.
        fontFamily = FontFamily.Monospace,
        fontWeight = FontWeight.Medium,
        fontSize = fs.toSp(),
        letterSpacing = (fs * 0.34f).toSp(),
        color = ThemeColor.accent,
    )
    val layout = measurer.measure(AnnotatedString(Copy.Brand.tagline), style)

    val centreY = size.height * SplashGeometry.TAGLINE_TOP + fs / 2f
    // The +0.17 em nudge centres the SET string: the trailing letter carries a tracking space the
    // eye does not see, so the optical centre sits right of the metric one.
    val left = size.width / 2f + fs * 0.17f - layout.size.width / 2f
    val top = centreY - layout.size.height / 2f

    val exit = 1f + 0.22f * outQuint(seg(f.tm, 1.55f, 1.95f))
    scale(exit, exit, pivot = Offset(size.width / 2f, size.height * SplashGeometry.TAGLINE_TOP)) {
        translate(top = (1f - f.tg) * TAGLINE_RISE.dp.toPx()) {
            drawText(
                textLayoutResult = layout,
                topLeft = Offset(left, top),
                alpha = (f.tg * 0.8f * (1f - f.tgOut)).coerceIn(0f, 1f),
            )
        }
    }
}

// ---------------------------------------------------------------------------------------------
// The shaders
// ---------------------------------------------------------------------------------------------

/** `null` below API 33, where AGSL does not exist. Both effects are then simply not drawn. */
private fun runtimeShader(source: String, allowed: Boolean): RuntimeShader? =
    if (allowed && Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        runCatching { RuntimeShader(source) }.getOrNull()
    } else {
        null
    }

/**
 * Ten taps along the ray from the ember through each pixel, with the red and blue channels
 * resampled a hair apart — a radial smear with a chromatic fringe, so the dive reads as going
 * through a light rather than past a picture.
 *
 * One instance for the process: the dive lasts half a second and compiling AGSL inside a frame
 * callback is not something to do twice.
 */
private val emberZoom: RuntimeShader? by lazy { runtimeShader(EMBER_ZOOM_AGSL, allowed = true) }

@Suppress("MaxLineLength")
private const val EMBER_ZOOM_AGSL = """
uniform shader layer;
uniform float2 center;
uniform float strength;

half4 main(float2 pos) {
    float2 dir = pos - center;
    float4 acc = float4(0.0);
    for (int i = 0; i < 10; i++) {
        float t = float(i) / 9.0;
        float s = 1.0 - strength * 0.18 * t;
        float4 c = float4(layer.eval(center + dir * s));
        float r = float(layer.eval(center + dir * (s - strength * 0.012)).r);
        float b = float(layer.eval(center + dir * (s + strength * 0.012)).b);
        acc += float4(r, c.g, b, c.a);
    }
    return half4(acc / 10.0);
}
"""

private const val FILM_GRAIN_AGSL = """
uniform shader src;
uniform float time;
uniform float intensity;

half4 main(float2 pos) {
    half4 c = src.eval(pos);
    float n = fract(sin(dot(pos * 1.37 + time * 61.7, float2(12.9898, 78.233))) * 43758.5453);
    float g = (n - 0.5) * intensity * float(c.a);
    return half4(half3(float3(c.rgb) + g), c.a);
}
"""

// ---------------------------------------------------------------------------------------------
// The numbers this file owns
// ---------------------------------------------------------------------------------------------

/** 24 fps. Film, not a frame counter. */
private const val GRAIN_FPS = 24f

/** Near-invisible by design. Anything you can point at is too much. */
private const val GRAIN_INTENSITY = 0.035f

/** The stage light's reach, in dp, and the extra it gains on the flood. */
private const val STAGE_RADIUS = 420f
private const val STAGE_RADIUS_LIT = 140f
private const val VIGNETTE_RADIUS = 700f

/** The icon's landing blur, in dp at `ar = 0`. */
private const val LANDING_BLUR = 6f

/** The specular band: 55 % of the comp's width, raked 24°. */
private const val SHEEN_WIDTH = 0.30f
private const val SHEEN_ANGLE = 24f

/** ≈ 42.9 dp on a 393-dp screen, which is where the wordmark was drawn. */
private const val WORDMARK_SIZE = 118f / 1080f
private const val TAGLINE_SIZE = 25f / 1080f

/** How far each line rises into place. */
private const val WORDMARK_RISE = 14f
private const val TAGLINE_RISE = 7f

/** Tracking is re-measured at most this many times across the punch-in. */
private const val TRACKING_STEPS = 24f
