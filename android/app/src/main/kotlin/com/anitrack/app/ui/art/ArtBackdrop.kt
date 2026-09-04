package com.anitrack.app.ui.art

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.unit.Dp
import com.anitrack.app.design.MotionToken
import com.anitrack.app.design.ThemeColor
import com.anitrack.app.design.ThemeMetrics
import com.anitrack.app.design.motion
import com.anitrack.app.ui.image.ArtBlur
import com.anitrack.app.ui.image.ArtImage
import com.anitrack.app.ui.image.ArtMaxPixel
import com.anitrack.app.ui.image.rememberArtTint
import kotlin.math.max

/*
 * THE AMBIENT IDENTITY WASH — the port of `ArtBackdrop` from `ios/Sources/DesignSystem/Palette.swift`
 * (spec/design-tokens.md §7.5, spec/chrome-images.md §4.9).
 *
 * > "The ambient identity wash behind the top of a screen: the artwork itself, blurred past
 * > recognition, bleeding under the status bar and dissolving into the canvas. This is the single
 * > biggest thing the shipped build dropped … it costs one static, already-cached image, drawn once,
 * > never animated, never touched on scroll."
 *
 * **There is ONE wash spec app-wide** — `ThemeMetrics.rootWashHeight` (320) and
 * `ThemeMetrics.rootWashIntensity` (0.4), for tab roots and pushed lists alike. A screen may not
 * carry a private height/intensity pair: the three roots once shipped 300/0.3, 380–520/0.5–0.68 and
 * 400/0.68, so the same atmosphere was a whisper on one tab and a stain on the next, and by the
 * cohesion pass the tree had re-diverged into seven configurations. Those are the defaults here so a
 * caller never types either number.
 */

/**
 * The wash's decode budget. Tiny on purpose: the image is about to be blurred past recognition and
 * then scaled across the whole band, so anything larger is detail destroyed on the next line.
 *
 * The palette does **not** take a budget from a call site: `ArtPaletteCache` owns its own 64-px
 * sample (`ArtMaxPixel.PALETTE_SAMPLE`), served from the disk cache or coalesced with the display
 * fetch, because Coil hands out hardware bitmaps whose pixels `getPixels` cannot read.
 */
private const val WASH_MAX_PIXEL = ArtMaxPixel.AMBIENT_BACKDROP

/**
 * The blurred-art layer's opacity multiplier — iOS's `.opacity(0.70 * intensity)`.
 */
private const val WASH_ART_OPACITY = 0.70f

/*
 * The wash's blur is `ArtBlur.AMBIENT_WASH`, and it is **baked into the decoded bitmap** rather
 * than drawn on the frame — the same decision `LandscapeArt`'s portrait ground and the billboard
 * hero's take, and for the same reason: `Modifier.blur` is a *silent no-op below API 31* and this
 * app's floor is 26, so a drawn blur would leave every pre-31 device showing a sharp, recognisable
 * poster smeared across the status band with no error and nothing in a log. Baking works on every
 * supported API with no branch, and Coil caches the transformed bitmap.
 *
 * The radius itself lives in `ArtBlur` with the other two and not here: it is a size, and a size at
 * a call site is how the three blurred surfaces in this app drift apart. See that table for why the
 * number is not iOS's 56.
 */

/**
 * The ambient wash: the artwork blurred past recognition, a base gradient in the show's own colour,
 * a constant breath of brand warmth, and the handover to the canvas.
 *
 * Mount it as the FIRST child of a screen's chrome box, top-aligned and drawing into the status bar
 * (the box must not consume the status-bar inset). It draws and does nothing else: no pointer input,
 * and `clearAndSetSemantics` keeps the whole decoration out of the accessibility tree.
 *
 * ### The pre-art floor, which is a bug fix and not a nicety
 *
 * `baseTop` / `baseMid` hold a floor that is **independent of [intensity]** until the palette
 * resolves. `ambientBackdropFallback` was made "visibly warmer than canvas" for exactly this moment
 * — but at a list root's 0.4 the same ember composites to ≈rgb(38,36,32) on device: *"the status
 * band reads BLACK for the whole first load, then jumps to twice the luminance when the art decodes
 * (user, 30 Aug — 'black, then it becomes flush')"*. With the floor the wash looks like the wash
 * from frame one and the art arrives as a hue shift, not as a light switching on.
 *
 * @param url the artwork to light the room with. A screen with no artwork passes `null` and an
 *   explicit [tint] instead — *"with no artwork in the library there is nothing for it to be ABOUT,
 *   so first run gets the app's own colour."*
 * @param tint an explicit base colour, outranking the palette. It does **not** count as the art
 *   having settled, so the floor above still applies.
 */
@Composable
fun ArtBackdrop(
    modifier: Modifier = Modifier,
    url: String? = null,
    tint: Color? = null,
    height: Dp = ThemeMetrics.rootWashHeight,
    intensity: Float = ThemeMetrics.rootWashIntensity,
) {
    // Keyed on the URL, so a screen whose wash source changes drops the previous show's colour
    // rather than grounding the new art in the last one's palette. `rememberArtTint` seeds itself
    // from the palette cache's synchronous read, so a screen re-entered with warm caches paints
    // its ground on frame one instead of opening on the fallback and stepping to the real colour.
    val resolved = rememberArtTint(url)

    val artSettled = resolved != null
    val base = tint ?: resolved ?: ThemeColor.ambientBackdropFallback
    val baseTop = if (artSettled) 0.60f * intensity else max(0.60f * intensity, 0.55f)
    val baseMid = if (artSettled) 0.10f * intensity else max(0.10f * intensity, 0.12f)

    // `uiGentle` on the palette landing, deliberately NOT routed through `pickMotion`: it is a pure
    // opacity/colour crossfade with no travel, which is already Reduce-Motion-safe.
    val baseColor = animateColorAsState(base, motion(MotionToken.UI_GENTLE), label = "washBase")
    val topAlpha = animateFloatAsState(baseTop, motion(MotionToken.UI_GENTLE), label = "washTop")
    val midAlpha = animateFloatAsState(baseMid, motion(MotionToken.UI_GENTLE), label = "washMid")

    // Layers 3 and 4 never change, so they are built once rather than per frame.
    val breath = remember(intensity) {
        Brush.verticalGradient(
            0f to ThemeColor.accent.copy(alpha = 0.07f * intensity),
            1f to Color.Transparent,
        )
    }
    val handover = remember {
        Brush.verticalGradient(
            0f to Color.Transparent,
            0.55f to ThemeColor.canvas.copy(alpha = 0.55f),
            1f to ThemeColor.canvas,
        )
    }

    Box(
        modifier
            .fillMaxWidth()
            .height(height)
            .clipToBounds()
            .clearAndSetSemantics {},
    ) {
        if (!url.isNullOrEmpty()) {
            // Centre-cropped BEFORE the blur — `ContentScale.Crop` inside a frame of the band's own
            // size. "Blurring a view whose art has not been made to fill its frame samples whatever
            // corner the image happened to land in, which is why Profile drew no image at all."
            ArtImage(
                url = url,
                maxPixel = WASH_MAX_PIXEL,
                modifier = Modifier
                    .matchParentSize()
                    .graphicsLayer { alpha = WASH_ART_OPACITY * intensity },
                contentScale = ContentScale.Crop,
                placeholder = false,
                transformations = ArtBlur.AMBIENT_WASH,
            )
        }

        Box(
            Modifier
                .matchParentSize()
                // The animated values are read inside the draw lambda, never in a body: the palette
                // landing costs a draw pass, not a recomposition of the screen it sits behind.
                .drawBehind {
                    val colour = baseColor.value
                    drawRect(
                        Brush.verticalGradient(
                            0f to colour.copy(alpha = topAlpha.value),
                            0.5f to colour.copy(alpha = midAlpha.value),
                            1f to Color.Transparent,
                        ),
                    )
                    drawRect(breath)
                    drawRect(handover)
                },
        )
    }
}
