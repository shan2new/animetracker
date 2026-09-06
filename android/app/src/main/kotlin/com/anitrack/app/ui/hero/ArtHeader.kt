package com.anitrack.app.ui.hero

import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.BiasAlignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import coil3.transform.Transformation
import com.anitrack.app.design.ArtGround
import com.anitrack.app.design.LocalReduceMotion
import com.anitrack.app.design.ThemeMetrics
import com.anitrack.app.design.ThemeMotion
import com.anitrack.app.design.ThemeSpace
import com.anitrack.app.ui.image.ArtBlur
import com.anitrack.app.ui.image.ArtImage
import com.anitrack.app.ui.image.ArtMaxPixel
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.CompositingStrategy

/**
 * A cinematic, edge-to-edge art header with content laid over its lower third — **the one billboard
 * hero grammar**, used by Today and by Detail and by nothing else.
 *
 * This is the shape the original Today and Detail screens had and the rebuild replaced with a 78-dp
 * thumbnail beside a 20-dp title. Identity art is this product's only real material; when it is
 * 78 dp wide inside a stroked box there is nothing left for the design to be made of.
 *
 * The art fills and crops — a hero is a backdrop, not a poster; artwork that must stay whole belongs
 * in a poster slot. Everything the caller passes is bottom-aligned inside the gutter.
 *
 * ## Layers, bottom to top
 *
 * 1. the palette [tint] as a flat ground, **so the header never flashes black**;
 * 2. the artwork — one filling layer for a banner, or a composited pair for a portrait cover
 *    ([portraitSource]);
 * 3. [ArtScrim] at the given strengths;
 * 4. the caller's [overlay], in the gutter, 20 dp off the foot.
 *
 * @param height the FULL art height, status bar included. `CLAUDE.md` pins the shipped billboard at
 *   0.68–0.72 × screen — see [billboardHeight], which both screens size themselves through.
 * @param tint the extracted palette colour. Null falls back to [ArtGround.neutralWarm], the same
 *   neutral warm the art-adaptive ground stands in with.
 * @param focus where the crop anchors, and what the drift scales away from. `TopCenter` keeps faces
 *   in a tall band; a key-art lockup that lives in the lower third needs a bottom anchor, and a
 *   centred composition needs the centre. **Hard-coding the top is why one hero was a forehead and
 *   another was a logo.**
 * @param portraitSource the source is a PORTRAIT cover, not a landscape banner. A 2:3 cover filled
 *   into a 0.7-screen band is upscaled ~2.5× and cropped to a horizontal slice of itself — the app's
 *   largest piece of artwork rendered as its worst. When there is no banner the cover is composited
 *   instead: a blurred, opaque copy of itself as the ground, the whole cover fitted over it. Nothing
 *   is upscaled and nothing is lost.
 * @param drift the slow breath. See [driftScaleFor].
 */
@Composable
fun ArtHeader(
    url: String?,
    height: Dp,
    modifier: Modifier = Modifier,
    tint: Color? = null,
    scrimTop: Float = 1f,
    scrimBottom: Float = 1f,
    focus: Alignment = Alignment.TopCenter,
    portraitSource: Boolean = false,
    drift: Boolean = false,
    /**
     * Today only, and only while the name is set in TYPE (i3-1): the sharp cover starts under the
     * wordmark band instead of behind it, blended in over [INSET_BLEND]. With a logo the art keeps
     * the full bleed — a hard edge under the band cut every poster; a soft one is a picture
     * arriving under the chrome.
     */
    topInset: Dp = 0.dp,
    /** Fires once the sharp layer has decoded: the launch ident waits on the first billboard. */
    onLoaded: (() -> Unit)? = null,
    overlay: @Composable ColumnScope.() -> Unit = {},
) {
    // Null on every non-drifting hero — and the modifier below is then absent entirely rather than
    // present-and-inert. `Modifier.graphicsLayer { }` is not free when it does nothing: it promotes
    // the art to its own RenderNode and re-reads the block on every draw, and Today's calm hero,
    // Detail's, and every screen that reuses this frame pass `drift = false`.
    val driftScale = driftScaleFor(drift)
    val anchor = remember(focus) { driftAnchor(focus) }
    val driftLayer = driftScale?.let { read ->
        Modifier.graphicsLayer {
            // Read INSIDE the layer block: a deferred read, so a drift frame is a draw, never a
            // recomposition. This is the one transform on the one layer the whole drift is allowed
            // to be.
            val s = read()
            scaleX = s
            scaleY = s
            transformOrigin = anchor
        }
    } ?: Modifier

    Box(
        modifier
            .fillMaxWidth()
            .height(height)
            // The port of `.clipped()`: the sharp layer is scaled past the frame by the drift, and
            // a composited cover's ground is filled and cropped. Both must stop at this edge.
            .clipToBounds()
            .background(tint ?: ArtGround.neutralWarm)
    ) {
        if (!url.isNullOrEmpty()) {
            if (portraitSource) {
                // The ground: the cover's own colour and shape, blurred past recognition, so the
                // whole cover above it has something to sit on other than a flat plate.
                HeroArt(
                    url = url,
                    maxPixel = ArtMaxPixel.HERO_PORTRAIT_GROUND,
                    fill = true,
                    alignment = Alignment.Center,
                    modifier = Modifier.matchParentSize(),
                    transformations = ArtBlur.HERO_PORTRAIT_GROUND,
                )
                Box(Modifier.matchParentSize().background(portraitGroundVeil))
                // 2048, not the ground's 1024: the billboard draws this layer at ~1770 px tall, and
                // capping the decode below that softened the one sharp asset in the frame. The
                // blurred ground stays small — it is blurred.
                val inset = topInset > 0.dp
                HeroArt(
                    url = url,
                    maxPixel = ArtMaxPixel.HERO_PORTRAIT_SHARP,
                    // Under the band the frame is shorter than the cover's 2:3 and the cover fills
                    // it (its top under the blend); the full-bleed cover is fitted whole.
                    fill = inset,
                    alignment = focus,
                    onLoaded = onLoaded,
                    modifier = Modifier
                        .matchParentSize()
                        .padding(top = topInset)
                        .then(if (inset) Modifier.blendTop(INSET_BLEND) else Modifier)
                        .then(driftLayer),
                )
            } else {
                HeroArt(
                    url = url,
                    maxPixel = ArtMaxPixel.HERO_LANDSCAPE,
                    fill = true,
                    alignment = focus,
                    modifier = Modifier
                        .matchParentSize()
                        .then(driftLayer),
                )
            }
        }

        ArtScrim(Modifier.matchParentSize(), top = scrimTop, bottom = scrimBottom)

        Column(
            Modifier
                .align(Alignment.BottomStart)
                .fillMaxWidth()
                .padding(horizontal = ThemeMetrics.gutter)
                .padding(bottom = ThemeSpace.x5),
            content = overlay,
        )
    }
}

// -------------------------------------------------------------------------------------------------
// Height
// -------------------------------------------------------------------------------------------------

/**
 * The two billboard fractions, named here so the two screens that draw a billboard spend the same
 * token rather than each keeping a private number.
 */
object Billboard {

    /**
     * Today's resting focus stage, at billboard scale. Measured against Apple TV's Home: its hero
     * CTA bottoms out at ~70 % of the screen and the next shelf's header sits at ~83 %, so at 0.72
     * the copy block lands on the same line and the queue's first row peeks above the tab bar as the
     * scroll affordance.
     */
    const val today = 0.72f

    /**
     * Detail's — Today's 0.72 (5 Sep): the state block that used to sit under the art is inside the
     * lockup now, so nothing below the hero has to land on the first screen.
     */
    const val detail = 0.72f
}

/**
 * A billboard's height: the fraction of the SCREEN, grown by the copy's overflow.
 *
 * One fraction at every type size. The frame grows by the copy's OVERFLOW, not by a guessed
 * accessibility bump — at AX5 the block then gets exactly the room it needs instead of a fixed
 * fraction and a clipped title, and there is no layout cycle, because **the copy's height depends
 * only on the available width, never on this**.
 *
 * The fraction is of [ThemeMetrics.windowHeight], status bar included: a billboard is sized against
 * the screen, which no inner layout can report.
 *
 * @param artBand the least photograph that must survive above the copy.
 * @param copyHeight the copy block's measured height — see [reportHeight].
 */
@Composable
fun billboardHeight(fraction: Float, copyHeight: Dp, artBand: Dp): Dp =
    maxOf(ThemeMetrics.windowHeight() * fraction, copyHeight + artBand)

// -------------------------------------------------------------------------------------------------
// Drift
// -------------------------------------------------------------------------------------------------

/**
 * The billboard's slow breath, as a **deferred** scale reader.
 *
 * ~7 % over 24 s, eased, reversing: under the threshold where it reads as motion, over the one where
 * the frame reads as a still pinned to a wall. Today's and Detail's billboards only — *nothing else
 * in the app drifts*.
 *
 * Returns a lambda rather than a `Float` on purpose. Calling it inside a `graphicsLayer { }` block
 * keeps the animation's snapshot read at draw time, so a drift frame never recomposes anything; a
 * `Float` returned from here would be read in the caller's body and re-run it at 60–120 Hz for
 * twenty-four seconds at a time, which is the scroll-lag rule of 2 Sep from a second direction.
 *
 * **Null means "there is no drift", and the caller must then mount no layer at all** — not a layer
 * reading a constant 1. Every hero in the app except Today's and Detail's billboards takes that
 * branch, and a `graphicsLayer` that scales by 1 still costs a RenderNode and a draw-time block.
 *
 * Under Reduce Motion the drift is **not started at all** — it is not swapped for a shorter one
 * ([ThemeMotion.drift] documents that branch), and an already-running drift snaps back to 1.
 *
 * ### Lifetime, and why this is not an `Animatable`
 *
 * It was one: `remember { Animatable(1f) }` inside a `LaunchedEffect` that slept for the beat and
 * then called `animateTo(driftScale, ThemeMotion.drift())`. **An `animateTo` on an
 * `InfiniteRepeatableSpec` never returns**, so the effect's coroutine stayed open for the life of
 * the screen — and a coroutine launched from the composition that never completes is a composition
 * that is never idle. `ComposeTestRule.waitForIdle` and Espresso's own sync both hang on a
 * drifting billboard, which is Today and Detail, which is most of the app.
 *
 * `rememberInfiniteTransition` is the shape Compose's idling resource knows to ignore, and it is
 * what every other perpetual animation in this app already uses (`SkeletonGate`'s breath,
 * `IndeterminateArc`). The 80-ms beat moves onto the spec itself as a
 * `StartOffset(…, StartOffsetType.Delay)` — see [ThemeMotion.drift] — so nothing is lost.
 *
 * The transition is mounted only while `active`, and it leaves with the header or the moment
 * Reduce Motion is switched on: both ways the drift must stop are "this branch is no longer
 * composed", so there is no animation left running to snap back from.
 */
@Composable
private fun driftScaleFor(drift: Boolean): (() -> Float)? {
    val reduceMotion = LocalReduceMotion.current
    if (!drift || reduceMotion) return null

    val transition = rememberInfiniteTransition(label = "heroDrift")
    val scale = transition.animateFloat(
        initialValue = 1f,
        targetValue = ThemeMotion.driftScale,
        animationSpec = ThemeMotion.drift(),
        label = "heroDriftScale",
    )
    // Remembered so the `graphicsLayer` block it feeds keeps one identity across recompositions.
    return remember(scale) { { scale.value } }
}

/**
 * Where the drift scales away from, derived from the crop anchor so the two agree: a top-anchored
 * crop that grew from its centre would push the face it was anchored to off the top of the frame.
 *
 * Every stock [Alignment] is a [BiasAlignment], so the vertical bias covers all of them; anything
 * else falls to the centre, which is iOS's own `else` branch.
 */
private fun driftAnchor(focus: Alignment): TransformOrigin {
    val bias = (focus as? BiasAlignment)?.verticalBias ?: 0f
    return when {
        bias <= -1f -> TransformOrigin(0.5f, 0f)
        bias >= 1f -> TransformOrigin(0.5f, 1f)
        else -> TransformOrigin.Center
    }
}

// -------------------------------------------------------------------------------------------------
// The art layers
// -------------------------------------------------------------------------------------------------

/**
 * One layer of billboard artwork.
 *
 * **The single seam between this file and the image pipeline.** `ArtImage` (`ui/image`) owns the
 * decoded-image cache, the bucket ladder, the no-flash ladder probe, the load fade and the baked
 * blur, and nothing here may open a second decode path for the same URL — two entry points would
 * cache the same asset under two keys and decode a 2048-px billboard twice. Every image call in
 * this file funnels through this one function, so the pipeline is reached from exactly one place,
 * and every decode budget it spends is a named rung of [ArtMaxPixel] rather than a private number.
 *
 * `fitSnapAspect` is not passed: it exists so a ~0.708 cover snaps to a 2:3 poster slot, and a
 * billboard has no fixed aspect to snap to.
 *
 * @param fill iOS's `contentMode`: a hero is a backdrop, so it fills and crops; a composited cover
 *   is fitted, so it stays whole.
 * @param transformations baked into the decode — in practice only `ArtBlur.HERO_PORTRAIT_GROUND`.
 *   The blur, like every decode budget here, is the pipeline's and not this file's.
 */
@Composable
private fun HeroArt(
    url: String,
    maxPixel: Int,
    fill: Boolean,
    alignment: Alignment,
    modifier: Modifier,
    transformations: List<Transformation> = emptyList(),
    onLoaded: (() -> Unit)? = null,
) {
    ArtImage(
        url = url,
        maxPixel = maxPixel,
        modifier = modifier,
        onLoaded = onLoaded,
        contentScale = if (fill) ContentScale.Crop else ContentScale.Fit,
        alignment = alignment,
        // The header already drew the palette ground beneath this; a gradient placeholder on top of
        // it would be a second, colder ground flashing over the first.
        placeholder = false,
        transformations = transformations,
    )
}

/*
 * THE BLUR UNDER A COMPOSITED COVER — `ArtBlur.HERO_PORTRAIT_GROUND`, **baked into the decoded
 * bitmap, never drawn on the frame**.
 *
 * `Modifier.blur` was the obvious spelling and is the wrong one twice over. It is a *silent no-op
 * below API 31* — no throw, no warning, just a sharp poster where a blurred one was specified — so
 * it needs a capability branch, and the app already has exactly one capability boolean
 * (`LocalCanUseMaterial`, `ui/chrome/ChromeSurface.kt`) which is about *material*: chrome the user
 * reads content through. This is not material; it is one image composited as its own ground, and
 * giving it a second, private `SDK_INT >= S` was two capability tests for one class of surface.
 * And it costs a full-screen `RenderEffect` offscreen buffer on **every frame** of a 0.7-screen
 * hero, where the baked form costs nothing per frame and needs no branch at all.
 *
 * Baked, it runs once per (url, cacheKey, size) on Coil's decoder dispatcher, is cached under a key
 * that already includes the transformation, and is **identical on API 26 and API 37**. Edges clamp,
 * which is iOS's `.blur(opaque: true)` — no soft border where the frame cuts the ground.
 *
 * The radius and the 256-px working size are `ArtBlur.HERO_PORTRAIT_GROUND`'s and not this file's,
 * for the reason every other art number in here is a named rung of `ArtMaxPixel`: a size written at
 * a call site is one of three places the softness of this app can drift. That table also records
 * why the number is not iOS's 48 — iOS blurs in points *after* the upscale into the billboard,
 * this blurs in source pixels before it.
 */

/** The veil over the blurred ground, so the sharp cover reads as the subject and not as a duplicate. */
private val portraitGroundVeil = Color.Black.copy(alpha = 0.28f)


/** The inset cover's top edge, faded in from nothing over [INSET_BLEND] so it never cuts. */
private val INSET_BLEND = 56.dp

private fun Modifier.blendTop(depth: Dp): Modifier = this
    .graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }
    .drawWithContent {
        drawContent()
        drawRect(
            brush = Brush.verticalGradient(
                0f to Color.Transparent,
                1f to Color.Black,
                startY = 0f,
                endY = depth.toPx(),
            ),
            blendMode = BlendMode.DstIn,
        )
    }
