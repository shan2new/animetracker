package com.anitrack.app.design.brand

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorProducer
import androidx.compose.ui.graphics.Outline
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import com.anitrack.app.design.ShadowToken
import com.anitrack.app.design.ThemeColor
import com.anitrack.app.design.ThemeMetrics
import com.anitrack.app.design.ThemeType
import com.anitrack.app.design.shadowToken
import com.anitrack.app.ui.AutoSizeText
import com.anitrack.model.copy.Copy
import kotlin.math.PI
import kotlin.math.acos
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.tan

/*
 * THE IDENTITY — the port of `ios/Sources/DesignSystem/PreviouslyMark.swift`, drawn from the app
 * icon's own geometry (design/app-icon-v2/glass/x9-final.icon): a ribbon hanging by its top edge,
 * gold at the top-left falling to coral at the tails, and — where the composition calls for it —
 * the coral full stop beside the tails. Every drawing of the mark in the app goes through this
 * file: the launch ident, the wordmark, the sign-in gate and the account disc all draw THIS
 * ribbon, so the tile in the launcher, the object that arrives at launch and the mark beside the
 * name are one thing. **The identity may not exist twice.**
 *
 * The rules the icon settled (4 Sep) hold: flat, stroke-built, one hue-shifting ramp, no sphere,
 * no glow. Where the mark is the subject (the launch, the gate) it is `lit` — the icon's material
 * at scale: a hairline rim where light catches the edge, the volume of the ramp, and the coloured
 * shadow the ribbon casts on the canvas. Beside a name it is flat.
 *
 * The colours are `ThemeColor.markHighlight` / `markMid` / `markShadow` / `brandPeriod` /
 * `markCastShadow`, because a colour lives in the palette and nowhere else. This is the only file
 * that spends the ramp. `LaunchHandoff` lives beside it because the launch is the identity's own
 * moment, not the shell's.
 */

// ─────────────────────────────────────────────────────────────────────────────
// Geometry: the mark's anatomy in fractions of the ribbon's width, so one number sizes every use.
// ─────────────────────────────────────────────────────────────────────────────

object MarkGeometry {
    /** Height ÷ width. The icon shows 800 px of its 376-px-wide ribbon above the tile's foot. */
    const val ASPECT = 800f / 376f

    /** The notch, up from the tails. */
    const val NOTCH_DEPTH = 0.40f
    const val TIP_RADIUS = 0.045f
    const val APEX_RADIUS = 0.035f

    /**
     * The icon's ribbon runs off the tile's top edge. Standing alone it needs a finished top: the
     * same small radius as its tips, so it reads as a cut length of ribbon, never a plaque.
     */
    const val TOP_RADIUS = 0.06f

    /** The full stop: a 90-px bead in the icon, its foot flush with the tails, 38 px clear of the edge. */
    const val PERIOD_DIAMETER = 180f / 376f
    const val PERIOD_GAP = 38f / 376f

    /** The bead's centre from the ribbon's leading edge, in widths (the icon: x0 + 376 + 38 + 90). */
    const val PERIOD_CENTER_X = 1f + PERIOD_GAP + PERIOD_DIAMETER / 2f

    /** The bead's centre from the ribbon's top, in widths. */
    const val PERIOD_CENTER_Y = ASPECT - PERIOD_DIAMETER / 2f

    /** The composition's width (ribbon + gap + bead), in widths. */
    const val LOCKUP_WIDTH = 1f + PERIOD_GAP + PERIOD_DIAMETER

    /** Where the bead sits beside a ribbon occupying [ribbon]. */
    fun periodRect(ribbon: Rect): Rect {
        val d = ribbon.width * PERIOD_DIAMETER
        val cx = ribbon.left + ribbon.width * PERIOD_CENTER_X
        val cy = ribbon.top + ribbon.width * PERIOD_CENTER_Y
        return Rect(cx - d / 2f, cy - d / 2f, cx + d / 2f, cy + d / 2f)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// The outline: the icon's polygon (design/app-icon-v2/ribbon.py `ribbon_pts` + `rounded`), every
// corner a tangent arc.
// ─────────────────────────────────────────────────────────────────────────────

/** The ribbon's outline inside [rect]. */
fun ribbonPath(rect: Rect): Path {
    val w = rect.width
    val tl = Offset(rect.left, rect.top)
    val tr = Offset(rect.right, rect.top)
    val br = Offset(rect.right, rect.bottom)
    val apex = Offset(rect.center.x, rect.bottom - MarkGeometry.NOTCH_DEPTH * w)
    val bl = Offset(rect.left, rect.bottom)
    val vertices = listOf(tr, br, apex, bl, tl)
    val radii = listOf(
        MarkGeometry.TOP_RADIUS * w, MarkGeometry.TIP_RADIUS * w, MarkGeometry.APEX_RADIUS * w,
        MarkGeometry.TIP_RADIUS * w, MarkGeometry.TOP_RADIUS * w,
    )
    val path = Path()
    path.moveTo(rect.center.x, rect.top)
    var previous = Offset(rect.center.x, rect.top)
    for (i in vertices.indices) {
        val v = vertices[i]
        val next = vertices[(i + 1) % vertices.size]
        arcThrough(path, previous, v, next, radii[i])
        previous = v
    }
    path.close()
    return path
}

/** A line to the tangent point before [vertex], then the arc of [radius] round it towards [next]. */
private fun arcThrough(path: Path, from: Offset, vertex: Offset, next: Offset, radius: Float) {
    val u = from - vertex
    val v = next - vertex
    val lu = hypot(u.x, u.y)
    val lv = hypot(v.x, v.y)
    val ux = u.x / lu
    val uy = u.y / lu
    val vx = v.x / lv
    val vy = v.y / lv
    val theta = acos((ux * vx + uy * vy).coerceIn(-1f, 1f))
    if (radius <= 0f || theta > PI.toFloat() - 1e-3f) {
        path.lineTo(vertex.x, vertex.y)
        return
    }
    var tangent = radius / tan(theta / 2f)
    var r = radius
    val tmax = 0.5f * min(lu, lv)
    if (tangent > tmax) {
        tangent = tmax
        r = tangent * tan(theta / 2f)
    }
    val t1 = Offset(vertex.x + ux * tangent, vertex.y + uy * tangent)
    val t2 = Offset(vertex.x + vx * tangent, vertex.y + vy * tangent)
    val bx = ux + vx
    val by = uy + vy
    val lb = hypot(bx, by)
    val reach = r / sin(theta / 2f)
    val c = Offset(vertex.x + bx / lb * reach, vertex.y + by / lb * reach)
    val a1 = atan2(t1.y - c.y, t1.x - c.x)
    val a2 = atan2(t2.y - c.y, t2.x - c.x)
    var sweep = a2 - a1
    while (sweep > PI) sweep -= (2 * PI).toFloat()
    while (sweep < -PI) sweep += (2 * PI).toFloat()
    path.lineTo(t1.x, t1.y)
    path.arcTo(
        rect = Rect(c.x - r, c.y - r, c.x + r, c.y + r),
        startAngleDegrees = a1 * 180f / PI.toFloat(),
        sweepAngleDegrees = sweep * 180f / PI.toFloat(),
        forceMoveTo = false,
    )
}

/** The ribbon as a [Shape] — for a shadow's outline or a clip. */
object RibbonShape : Shape {
    override fun createOutline(size: Size, layoutDirection: LayoutDirection, density: Density): Outline =
        Outline.Generic(ribbonPath(Rect(Offset.Zero, size)))
}

// ─────────────────────────────────────────────────────────────────────────────
// The drawing
// ─────────────────────────────────────────────────────────────────────────────

/**
 * The shaded ribbon in [rect]. The ramp runs the icon's diagonal; two quiet overlays give it the
 * icon's volume (lit at the head, shaded at the foot) and its curl (a cylinder's light across the
 * width). [material] (0…1) adds the hairline rim where light catches the top-left edges — the
 * icon's material at scale — and [sweep] (0 → 1 across the ribbon, or `null`) one pass of light.
 * The coloured shadow on the ground is a layer's, not a drawing's: see [ribbonCastShadow].
 */
fun DrawScope.drawRibbon(rect: Rect, material: Float = 0f, sweep: Float? = null) {
    val path = ribbonPath(rect)
    val tl = Offset(rect.left, rect.top)
    val br = Offset(rect.right, rect.bottom)
    drawPath(
        path = path,
        brush = Brush.linearGradient(
            0f to ThemeColor.markHighlight, 0.5f to ThemeColor.markMid, 1f to ThemeColor.markShadow,
            start = tl, end = br,
        ),
    )
    drawPath(
        path = path,
        brush = Brush.verticalGradient(
            0f to Color.White.copy(alpha = 0.09f), 0.35f to Color.Transparent, 1f to Color.Black.copy(alpha = 0.22f),
            startY = rect.top, endY = rect.bottom,
        ),
    )
    drawPath(
        path = path,
        brush = Brush.horizontalGradient(
            0f to Color.Black.copy(alpha = 0.08f), 0.35f to Color.White.copy(alpha = 0.09f), 1f to Color.Black.copy(alpha = 0.18f),
            startX = rect.left, endX = rect.right,
        ),
    )
    if (sweep != null && sweep > 0f && sweep < 1f) {
        clipPath(path) {
            val bandW = rect.width * 0.6f
            val bandH = rect.height * 2.4f
            val cx = rect.left + rect.width * (-0.7f + 2.4f * sweep)
            val cy = rect.top + rect.height * (0.15f + 0.7f * sweep)
            rotate(degrees = -24f, pivot = Offset(cx, cy)) {
                drawRect(
                    brush = Brush.horizontalGradient(
                        0f to Color.Transparent, 0.5f to Color.White.copy(alpha = 0.16f), 1f to Color.Transparent,
                        startX = cx - bandW / 2f, endX = cx + bandW / 2f,
                    ),
                    topLeft = Offset(cx - bandW / 2f, cy - bandH / 2f),
                    size = Size(bandW, bandH),
                    alpha = sin(sweep * PI.toFloat()) * material.coerceIn(0f, 1f),
                )
            }
        }
    }
    if (material > 0f) {
        // The edge: light catching the near side, the far side falling into shade. Inner strokes:
        // clipped to the outline, drawn at twice the width.
        val rim = max(0.8f * density, rect.width * 0.012f)
        clipPath(path) {
            drawPath(
                path = path,
                brush = Brush.linearGradient(
                    0f to Color.White.copy(alpha = 0.34f), 0.5f to Color.White.copy(alpha = 0.06f), 1f to Color.Transparent,
                    start = tl, end = Offset(rect.center.x, rect.bottom),
                ),
                style = Stroke(width = rim * 2f),
                alpha = material.coerceIn(0f, 1f),
            )
            drawPath(
                path = path,
                brush = Brush.linearGradient(
                    0f to Color.Transparent, 1f to Color.Black.copy(alpha = 0.22f),
                    start = Offset(rect.center.x, rect.top), end = br,
                ),
                style = Stroke(width = rim * 1.6f),
                alpha = material.coerceIn(0f, 1f),
            )
        }
    }
}

/** The full stop: the icon's coral bead, catching the same light from the upper left. */
fun DrawScope.drawPeriodBead(center: Offset, diameter: Float, lit: Boolean = false) {
    val r = diameter / 2f
    drawCircle(color = ThemeColor.brandPeriod, radius = r, center = center)
    drawCircle(
        brush = Brush.radialGradient(
            0f to Color.White.copy(alpha = 0.18f), 1f to Color.Transparent,
            center = Offset(center.x - 0.14f * diameter, center.y - 0.18f * diameter),
            radius = diameter * 0.62f,
        ),
        radius = r,
        center = center,
    )
    if (lit) {
        val rim = max(0.8f * density, diameter * 0.025f)
        drawCircle(
            brush = Brush.linearGradient(
                0f to Color.White.copy(alpha = 0.26f), 1f to Color.Transparent,
                start = Offset(center.x - r, center.y - r), end = Offset(center.x, center.y + r),
            ),
            radius = r - rim / 2f,
            center = center,
            style = Stroke(width = rim),
        )
    }
}

/**
 * The icon's coloured shadow under a lit ribbon: the platform's own elevation shadow, tinted warm
 * where the platform can tint it (API 28+). Below API 29 a non-convex outline (the notch) casts
 * no elevation shadow at all, so the floor devices show the lit ribbon without its halo — a
 * softening nobody misses, not a shape change. Native means, re-tuned numbers — iOS draws a
 * 0.10-width blur at 0.36 of the same colour, as a static layer beneath the fill.
 */
fun Modifier.ribbonCastShadow(width: Dp, amount: Float = 1f): Modifier =
    if (amount <= 0f) {
        this
    } else {
        shadow(
            elevation = width * 0.12f * amount,
            shape = RibbonShape,
            clip = false,
            ambientColor = ThemeColor.markCastShadow,
            spotColor = ThemeColor.markCastShadow,
        )
    }

// ─────────────────────────────────────────────────────────────────────────────
// The mark
// ─────────────────────────────────────────────────────────────────────────────

/**
 * The identity: the ribbon, and with [period] the icon's composition of ribbon and full stop.
 *
 * [lit] is the icon's material at scale (rim, coloured shadow) — for the launch and the sign-in
 * gate, where the mark is the subject; beside a name the ribbon is flat.
 *
 * The whole mark is hidden from accessibility everywhere it is drawn: the wordmark beside it, or
 * the control around it, says the name.
 *
 * @param width the only size a caller gives. The height and every internal measure are fractions
 *   of it, so the mark cannot be drawn out of proportion.
 * @param bloom the sign-in gate's one light source: a three-stop radial gradient centred on the
 *   mark, drawn behind it. It carries no blur, on any API level (`Modifier.blur` is a silent
 *   no-op below 31); Compose does not clip a draw to its node's bounds, so the reach spills past
 *   the mark exactly as the iOS background frame does.
 */
@Composable
fun PreviouslyMark(
    width: Dp,
    modifier: Modifier = Modifier,
    period: Boolean = false,
    lit: Boolean = false,
    bloom: Boolean = false,
) {
    val accent = ThemeColor.accent
    val height = width * MarkGeometry.ASPECT
    val lockup = if (period) width * MarkGeometry.LOCKUP_WIDTH else width
    Box(
        modifier = modifier
            .size(width = lockup, height = height)
            .then(if (bloom) Modifier.drawBehind { drawBloom(accent) } else Modifier)
            .clearAndSetSemantics {},
    ) {
        Canvas(
            Modifier
                .size(width = width, height = height)
                .then(if (lit) Modifier.ribbonCastShadow(width) else Modifier),
        ) {
            drawRibbon(Rect(Offset.Zero, size), material = if (lit) 1f else 0f)
        }
        if (period) {
            Canvas(Modifier.size(width = lockup, height = height)) {
                val ribbon = Rect(Offset.Zero, Size(width.toPx(), height.toPx()))
                val bead = MarkGeometry.periodRect(ribbon)
                drawPeriodBead(bead.center, bead.width, lit = lit)
            }
        }
    }
}

/** The bloom's reach — iOS `RadialGradient(endRadius: 260)` in a 520 × 520 frame. */
private val BloomRadius = 260.dp

private fun DrawScope.drawBloom(accent: Color) {
    val reach = BloomRadius.toPx()
    drawCircle(
        brush = Brush.radialGradient(
            0.0f to accent.copy(alpha = 0.20f),
            0.5f to accent.copy(alpha = 0.05f),
            1.0f to Color.Transparent,
            center = center,
            radius = reach,
        ),
        radius = reach,
        center = center,
    )
}

// ─────────────────────────────────────────────────────────────────────────────
// The name
// ─────────────────────────────────────────────────────────────────────────────

/**
 * "Previously." set in two inks: the word in [ink], the full stop in `brandPeriod` — the icon's
 * bead at text size (Outfit's period is a circle). The port of iOS `BrandWord`.
 */
@Composable
fun BrandWord(
    style: TextStyle,
    modifier: Modifier = Modifier,
    ink: Color = ThemeColor.textPrimary,
) {
    Row(
        modifier = modifier.semantics(mergeDescendants = true) { contentDescription = Copy.Brand.spoken },
    ) {
        BasicText(
            text = Copy.Brand.word,
            style = style,
            color = ColorProducer { ink },
            modifier = Modifier.alignByBaseline().clearAndSetSemantics {},
        )
        BasicText(
            text = Copy.Brand.period,
            style = style,
            color = ColorProducer { ThemeColor.brandPeriod },
            modifier = Modifier.alignByBaseline().clearAndSetSemantics {},
        )
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// The account disc
// ─────────────────────────────────────────────────────────────────────────────

/** The monogram is 0.42 × the disc — the disc's own anatomy, like a ring's numeral. */
private const val MONOGRAM_FRACTION = 0.42f

/** The mark stands in for a monogram at 0.28 × the disc (its aspect makes that 0.6 of the height). */
private const val MARK_FRACTION = 0.28f

/** iOS `minimumScaleFactor(0.6)` on the monogram. */
private const val MONOGRAM_MIN_SCALE = 0.6f

/** The ring of canvas around the subject disc: drawn OUTSIDE it, so it separates without cutting. */
private val DiscHaloInset = 5.dp

/**
 * The account disc, drawn once for every surface that shows one.
 *
 * **It never draws a person glyph.** The chain is: the real initial → the first letter of the
 * label the account is shown under ("Your account" → "Y") → the [PreviouslyMark]. Only the first
 * two are letters, so a wrong initial is still never invented; the third is the app's own
 * identity, which is never wrong.
 *
 * The disc is hidden from accessibility: the control around it is what is named.
 *
 * @param monogram the resolved initial, or `null` for the mark. Callers pass
 *   `AuthManager.AccountIdentity.monogram` — never a letter of their own derivation.
 * @param quiet neutral ground and ink instead of the accent pair, **and no halo**. Today's header
 *   wears this: the amber budget above the fold belongs to the hero's fact and its one action.
 *   Profile — where the disc IS the subject — keeps the accent form and the ring of canvas.
 */
@Composable
fun AccountDisc(
    monogram: String?,
    diameter: Dp,
    modifier: Modifier = Modifier,
    quiet: Boolean = false,
) {
    val density = LocalDensity.current
    val monogramStyle = with(density) {
        ThemeType.showTitleM.copy(
            fontSize = (diameter * MONOGRAM_FRACTION).toSp(),
            lineHeight = (diameter * MONOGRAM_FRACTION * 1.28f).toSp(),
            color = if (quiet) ThemeColor.textSecondary else ThemeColor.accent,
        )
    }

    Box(
        modifier = modifier
            .size(diameter)
            .shadowToken(ShadowToken.Art, CircleShape)
            .background(
                if (quiet) ThemeColor.surfaceRaised else ThemeColor.accentSoft,
                CircleShape,
            )
            .border(ThemeMetrics.hairline, ThemeColor.posterEdge, CircleShape)
            .then(
                if (quiet) {
                    Modifier
                } else {
                    Modifier.drawBehind {
                        drawCircle(
                            color = ThemeColor.hairline,
                            radius = size.minDimension / 2f + DiscHaloInset.toPx(),
                            style = Stroke(ThemeMetrics.hairline.toPx()),
                        )
                    }
                },
            )
            .clearAndSetSemantics {},
        contentAlignment = Alignment.Center,
    ) {
        if (monogram != null) {
            AutoSizeText(
                text = monogram,
                style = monogramStyle,
                minScale = MONOGRAM_MIN_SCALE,
                maxLines = 1,
            )
        } else {
            PreviouslyMark(width = diameter * MARK_FRACTION)
        }
    }
}
