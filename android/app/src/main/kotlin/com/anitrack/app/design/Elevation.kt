package com.anitrack.app.design

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Immutable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.RectangleShape
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * A shadow is one token, never three numbers at a call site.
 *
 * On a near-black canvas a shadow is not "depth" on its own — it is the soft contact edge under a
 * card whose FILL already separates it. **Never apply one to a surface that has no tone of its
 * own**, and only art large enough to read as an object earns one (see [PosterSize]).
 *
 * ### Why these are dp elevations and not iOS's triples
 *
 * The shipped app declares each shadow as `(colour, blur radius, y offset)` and draws it directly.
 * Reproducing those numbers on Android means a hand-rolled `setShadowLayer` pass on a hardware
 * layer, calibrated against iPhone captures, because Skia's blur radius is not on the same scale —
 * which is exactly the "match an iOS pixel by building machinery Android does not want" that the
 * fidelity line calls a defect rather than fidelity. So the **semantic names survive and the
 * numbers do not**: each token gets a dp elevation chosen to read right on Android, rendered by
 * the platform's own elevation model.
 *
 * The iOS values, recorded as history rather than as targets:
 *
 * | token      | colour     | blur | y  |
 * |------------|------------|------|----|
 * | `none`     | clear      |  0   |  0 |
 * | `card`     | black 45 % | 18   | 10 |
 * | `art`      | black 55 % | 12   |  7 |
 * | `artHero`  | black 60 % | 26   | 14 |
 * | `floating` | black 50 % | 26   | 14 |
 *
 * The ordering they encode is what ported: `art` is *tighter* than `card` (a poster sits close to
 * what it rests on), `artHero` is the biggest and softest (the largest object on its screen), and
 * `floating` reads clearly above everything without being an object of the page.
 *
 * ### One Android caveat, deliberately accepted
 *
 * Custom ambient/spot shadow colours only reach the platform from API 28. On 26–27 the shadow is
 * the system's own black at this elevation, which on a #09090B canvas is a difference nobody can
 * name. No branch is worth it.
 */
enum class ShadowToken(val elevation: Dp) {

    /** No shadow. The default for anything without a tone of its own. */
    None(0.dp),

    /**
     * Artwork: posters and stills read as physical objects, so their contact shadow is tight and
     * sits close.
     */
    Art(4.dp),

    /** Content card sitting on the canvas or on a plate; the `.raised` and `.art` surfaces. */
    Card(8.dp),

    /** Toast, sync banner, anything that floats over content it must not be mistaken for. */
    Floating(14.dp),

    /** A hero poster, which is the largest object on its screen. */
    ArtHero(18.dp),
}

/**
 * `Modifier.shadowToken(ShadowToken.Card, shape)` — the only sanctioned way to cast a shadow.
 *
 * [ShadowToken.None] is a no-op, so a caller may pass a slot's [PosterSize.shadow] straight
 * through without branching.
 *
 * @param shape the silhouette to cast. Prefer a `RoundedCornerShape` even where the content is
 *   clipped to a [ContinuousCornerShape]: a generic-path outline casts no native shadow below API
 *   29, and under a blurred shadow the two silhouettes are indistinguishable.
 * @param clip whether the shadow layer also clips the content. Left `false` by default because
 *   callers clip explicitly, in order, right after this.
 */
fun Modifier.shadowToken(
    token: ShadowToken,
    shape: Shape = RectangleShape,
    clip: Boolean = false,
): Modifier = if (token == ShadowToken.None) this else shadow(token.elevation, shape, clip)

/**
 * The four legal containers. **Nothing else is one.** If a surface needs an outline to be visible,
 * it is the wrong level — move it up, do not draw a box around it.
 *
 * | level      | ground                            | edge                              | shadow     |
 * |------------|-----------------------------------|-----------------------------------|------------|
 * | [Plate]    | `plateLift` (white 5.5 %, translucent) | none at all                  | none       |
 * | [Raised]   | `raisedLift` (white 11 %, translucent) | top hairline → clear by centre | card    |
 * | [Floating] | `surfaceFloating` (**opaque**)    | 1-dp `strokeStrong` all round     | floating   |
 * | [Art]      | the art-adaptive ground           | same top hairline as [Raised]     | card       |
 *
 * ### A surface is a RELATIVE lift, not an absolute fill
 *
 * [Plate] and [Raised] paint **translucent white over whatever is beneath**, never the opaque
 * `surfaceFlat` / `surfaceRaised` twins. The shipped `.plate` painted opaque `surfaceFlat`
 * wherever it landed, so on any screen carrying an art backdrop the ambient wash lifted the canvas
 * AROUND the plate and the plate itself inverted into a hole 13 levels darker than its own ground
 * — measured on Library, where it is the first element on the screen. Painting white over what is
 * beneath means a plate is always *above* its ground, whatever that ground turned out to be.
 *
 * The opaque tokens still exist and are still correct, because they are the *result* of these
 * lifts over `canvas`; a screen that reaches for `ThemeColor.surfaceFlat` directly and a container
 * that goes through [Modifier.surface] land on the same colour over a plain canvas.
 *
 * [Floating] stays opaque on purpose: a translucent toast with a shelf scrolling through it is
 * worse than a flat one.
 */
@Immutable
sealed interface SurfaceLevel {

    val shadow: ShadowToken

    /** Grouped lists, section grounds, notices. */
    @Immutable
    data object Plate : SurfaceLevel {
        override val shadow = ShadowToken.None
    }

    /** The card carrying the screen's action. */
    @Immutable
    data object Raised : SurfaceLevel {
        override val shadow = ShadowToken.Card
    }

    /** Toast, sync banner, menu-like chrome. */
    @Immutable
    data object Floating : SurfaceLevel {
        override val shadow = ShadowToken.Floating
    }

    /**
     * Focus / Recap / hero identity cards — grounded in a colour derived from the show's own
     * artwork.
     *
     * @param tint the extracted palette colour; `null` until it resolves, and then the neutral
     *   warm [ArtGround.neutralWarm] stands in rather than the canvas, so the card has a body from
     *   the first frame.
     * @param intensity scales the three tinted layers (not the veil). Drop it for a large hero
     *   where the colour would otherwise dominate.
     */
    @Immutable
    data class Art(val tint: Color? = null, val intensity: Float = 1f) : SurfaceLevel {
        override val shadow: ShadowToken get() = ShadowToken.Card
    }
}

/** Constants of the art-adaptive ground, kept here so [SurfaceLevel.Art] is self-sufficient. */
object ArtGround {

    /**
     * "Neutral warm surface" — the stand-in while a show's palette has not resolved. Mirrors the
     * palette layer's own fallback; the two must not drift.
     */
    val neutralWarm = Color(0xFF1C1A17)

    /**
     * The veil over the tinted layers, and **not** scaled by intensity.
     *
     * 30 %, not the spec's 44 %. That 44 was a FLOOR to be raised until primary text cleared
     * 4.5:1 — but the derived colour is already clamped in lightness, so the composite landed at
     * rgb(22, 18, 18) against a rgb(9, 9, 11) canvas: a 4 % luminance step, which is why the
     * shipped Focus card read as a hole with an outline round it rather than as a lit object. At
     * 30 % the same card composites near rgb(34, 28, 25) — still a deep, cinema-dark ground,
     * `textPrimary` still clears 12:1 on it, and the card finally has a body.
     */
    val veil = Color.Black.copy(alpha = 0.30f)

    /**
     * The light source's reach. A **distance**, not a fraction of the card: without this layer a
     * large ground is one dead rectangle of colour, which is what a gradient-filled div looks like.
     */
    val lightSourceRadius = 320.dp
}

/**
 * Paint a [SurfaceLevel] — ground, edge and shadow — on a continuous-cornered rounded rectangle.
 *
 * Order of operations is the shipped one and matters: shadow (outside the clip) → clip → ground →
 * edge. The border is applied **after** the clip so it strokes the same silhouette the content is
 * cut to, which is where Compose puts an inset stroke.
 *
 * @param radius defaults to [ThemeRadius.card] (22), the design system's default container corner.
 */
fun Modifier.surface(level: SurfaceLevel, radius: Dp = ThemeRadius.card): Modifier {
    val shape = ContinuousCornerShape(radius)
    val grounded = this
        // A generic path casts no platform shadow below API 29; the round-rect silhouette is
        // indistinguishable once blurred. See ShadowToken.shadowToken.
        .shadowToken(level.shadow, RoundedCornerShape(radius))
        .clip(shape)
        .let { m ->
            when (level) {
                SurfaceLevel.Plate -> m.background(ThemeColor.plateLift)
                SurfaceLevel.Raised -> m.background(ThemeColor.raisedLift)
                SurfaceLevel.Floating -> m.background(ThemeColor.surfaceFloating)
                is SurfaceLevel.Art -> m.artAdaptiveGround(
                    tint = level.tint ?: ArtGround.neutralWarm,
                    intensity = level.intensity,
                )
            }
        }

    return when (level) {
        SurfaceLevel.Plate -> grounded
        SurfaceLevel.Raised, is SurfaceLevel.Art ->
            grounded.border(surfaceEdgeWidth, topHairlineBrush, shape)
        SurfaceLevel.Floating ->
            grounded.border(surfaceEdgeWidth, ThemeColor.strokeStrong, shape)
    }
}

/** 1 dp, the shipped `strokeBorder` width. Compose insets a border the same way, so this maps. */
private val surfaceEdgeWidth = ThemeMetrics.hairline

/**
 * The only "stroke" a content card is allowed: a 1-dp highlight along the TOP edge, gone by the
 * card's vertical centre — a physical object catching light, not a wireframe box.
 */
private val topHairlineBrush = Brush.verticalGradient(
    0.0f to ThemeColor.hairline,
    0.5f to Color.Transparent,
    1.0f to Color.Transparent,
)

/**
 * The art-adaptive ground: flat base, a diagonal wash of the show's own colour, a light source in
 * the upper left, and a veil that puts the whole thing back in the dark.
 *
 * [SurfaceLevel] is complete on its own through [Modifier.surface]; this is also the ground
 * `Modifier.handoffGround` paints behind a container that survives a card swap, which is why it is
 * not private. The palette layer owns *deriving* the tint; this owns *painting* with it.
 */
fun Modifier.artAdaptiveGround(tint: Color, intensity: Float): Modifier = drawBehind {
    // 1 — flat base, so the ground is opaque even before any tint contributes.
    drawRect(ThemeColor.surfaceFlat)

    // 2 — the diagonal wash, top-leading to bottom-trailing.
    drawRect(
        Brush.linearGradient(
            colors = listOf(
                tint.copy(alpha = 0.52f * intensity),
                tint.copy(alpha = 0.18f * intensity),
            ),
            start = Offset.Zero,
            end = Offset(size.width, size.height),
        )
    )

    // 3 — a light source, not a flat wash.
    drawRect(
        Brush.radialGradient(
            colors = listOf(tint.copy(alpha = 0.30f * intensity), Color.Transparent),
            center = Offset(size.width * 0.16f, size.height * 0.02f),
            radius = ArtGround.lightSourceRadius.toPx(),
        )
    )

    // 4 — the veil. Deliberately NOT scaled by intensity: see ArtGround.veil.
    drawRect(ArtGround.veil)
}
