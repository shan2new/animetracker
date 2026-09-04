package com.anitrack.app.ui.image

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.ScaleFactor
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.unit.Dp
import coil3.compose.AsyncImage
import coil3.compose.LocalPlatformContext
import coil3.request.ImageRequest
import coil3.request.allowHardware
import coil3.request.crossfade
import coil3.request.transformations
import coil3.size.Precision
import coil3.size.Scale
import coil3.transform.Transformation
import com.anitrack.app.design.ContinuousCornerShape
import com.anitrack.app.design.ThemeColor
import com.anitrack.app.design.ThemeRadius
import kotlin.math.abs

/**
 * # The art view
 *
 * The port of `CachedAsyncImage` / `RemoteImageView` / `Thumb`
 * (`ios/Sources/DesignSystem/{ImageLoader,RemoteImageView}.swift`). One composable draws every
 * pixel of artwork in the app; the compositions built on it — `PosterSlot`, `LandscapeArt`,
 * `ArtHeader`, `EpisodeStill`, `ArtBackdrop` — live in the design system and all of them come
 * through here.
 *
 * The behaviours it must keep, each with a shipped bug behind it:
 *
 * * **No intrinsic size.** It measures exactly what its container proposes, never more. See
 *   [ArtImage].
 * * **No flash on a recycled cell.** The ladder probe in [ImageBuckets.ladderHit] paints frame one
 *   from whatever decode is already in memory, and the cross-fade is skipped when it does.
 * * **A cache hit never animates**; only a network or disk load cross-fades.
 * * **A URL change to an uncached URL clears the old art first.** No stale poster under a new title.
 * * **A failure has no UI.** No error glyph, no retry button, no spinner — the ground stays and a
 *   retry happens only when the URL changes.
 * * **Invisible to TalkBack.** Every art node is `clearAndSetSemantics {}`: meaning is carried by
 *   the row's text, never by the picture. An auto-generated "image" node on every poster in a grid
 *   is a regression, and the semantics tree is walked on scroll.
 */

/**
 * The placeholder ground — the port of `GradientPlaceholder`.
 *
 * Opaque, top-leading to bottom-trailing. That opacity is why hosts that draw their own ground (a
 * palette tint, an art backdrop, a composited blur) pass `placeholder = false` instead of stacking
 * this on top of it.
 */
private val GradientPlaceholderBrush = Brush.linearGradient(
    colors = listOf(Color(0xFF27272F), Color(0xFF141418)),
    start = Offset.Zero,
    end = Offset.Infinite,
)

/**
 * The anti-sliver rule — the port of `CachedAsyncImage.resolvedContentMode`.
 *
 * Artwork that must stay whole aspect-**fits**, which leaves a mat wherever the source and the slot
 * disagree. AniList's standard cover is 460 × 654 (0.703) against a 2:3 slot (0.667) — a 5.4 % miss,
 * i.e. a 2-dp tinted bar across the top and bottom of every poster on every shelf, which reads as a
 * rendering artifact rather than as the deliberate letterbox the fit rule exists for. Inside
 * [tolerance] the image fills instead: at 8 % the crop is ≤ 4 % per edge, imperceptible on a poster,
 * while a genuine lockup or still misses by far more and still fits.
 *
 * **0.08, not 0.05** — 0.05 is below the exact miss this exists to remove.
 *
 * On iOS this is a decision taken at draw time from the decoded image's aspect. In Compose it is a
 * pure function of (source size, destination size), which is precisely `ContentScale`'s contract —
 * so it needs no state, no recomposition and no load-state observation.
 *
 * @param targetAspect the FRAME's aspect (width / height), which the caller knows; the source's
 *   aspect arrives as `srcSize`.
 */
@Immutable
data class SnapFitContentScale(
    val targetAspect: Float,
    val tolerance: Float = FIT_SNAP_TOLERANCE,
) : ContentScale {

    override fun computeScaleFactor(srcSize: Size, dstSize: Size): ScaleFactor {
        if (srcSize.height <= 0f || targetAspect <= 0f) {
            return ContentScale.Fit.computeScaleFactor(srcSize, dstSize)
        }
        val aspect = srcSize.width / srcSize.height
        return if (abs(aspect / targetAspect - 1f) <= tolerance) {
            ContentScale.Crop.computeScaleFactor(srcSize, dstSize)
        } else {
            ContentScale.Fit.computeScaleFactor(srcSize, dstSize)
        }
    }

    companion object {
        /** `CachedAsyncImage.fitSnapTolerance`. */
        const val FIT_SNAP_TOLERANCE = 0.08f
    }
}

/**
 * Remote artwork, decoded at a bucketed size and drawn to fill whatever box the caller gives it.
 *
 * ### It has NO intrinsic size — the caller must size it
 *
 * `Modifier.size(...)`, `fillMaxWidth().aspectRatio(...)` or `matchParentSize()`: this measures what
 * its container proposes and contributes nothing back. That is deliberate and it is the single
 * most load-bearing line in the iOS original, whose comment records the failure:
 *
 * > An `Image` reports its pixel dimensions as its ideal size … during an HStack/ZStack's sizing
 * > pass the proposal is nil, so the ideal leaks out and inflates the whole enclosing layout.
 * > That's what threw Schedule's rail off-screen: one hero banner widened the ScrollView's content
 * > past the screen and the feed rendered horizontally centred/clipped.
 *
 * Compose has the same failure in a different shape — an `AsyncImage` in a `Row` with no width and
 * no weight reports the painter's intrinsic size. `Modifier.matchParentSize()` inside a sized `Box`
 * is the guarantee: it measures from the parent and never contributes to it.
 *
 * @param maxPixel the longest edge, in pixels, this surface needs. Take it from [ArtMaxPixel], or
 *   from [artPixels] for a slot-derived size. It is rounded up to [ImageBuckets.LADDER] and the
 *   decode happens at the bucket, not at this number.
 * @param placeholder whether to draw the [GradientPlaceholderBrush] ground while loading and on
 *   failure. Hosts with their own ground pass `false`.
 * @param fitSnapAspect the frame's width / height, when [contentScale] is `Fit` and a near-match
 *   should fill rather than leave a sliver of mat. See [SnapFitContentScale].
 * @param transformations Coil transformations to bake into the decode — in practice only
 *   [BlurTransformation]. **Do not** hand-key a transformed request: its memory-cache key must
 *   include the transformation, and this branches for exactly that reason.
 */
@Composable
fun ArtImage(
    url: String?,
    maxPixel: Int,
    modifier: Modifier = Modifier,
    contentScale: ContentScale = ContentScale.Crop,
    alignment: Alignment = Alignment.Center,
    placeholder: Boolean = true,
    fitSnapAspect: Float? = null,
    transformations: List<Transformation> = emptyList(),
) {
    val context = LocalPlatformContext.current
    val loader = LocalArtImageLoader.current
    val source = url?.takeIf(String::isNotEmpty)
    val bucket = remember(maxPixel) { ImageBuckets.bucket(maxPixel) }

    // Frame one: the best decode already in memory at >= this bucket. A transformed request is
    // excluded — its bytes are not this URL's bytes, and a sharp decode handed to a blurred ground
    // as a placeholder would flash the poster before softening it.
    val ladderKey = remember(source, bucket, transformations) {
        if (source == null || transformations.isNotEmpty()) null
        else ImageBuckets.ladderHit(loader.memoryCache, source, bucket)
    }

    val scale = remember(contentScale, fitSnapAspect) {
        if (fitSnapAspect != null && contentScale == ContentScale.Fit) {
            SnapFitContentScale(fitSnapAspect)
        } else {
            contentScale
        }
    }

    Box(
        modifier
            .clipToBounds() // iOS `.clipped()`
            // Drawn behind, not passed as a placeholder Painter: `AsyncImage`'s painter parameters
            // OVERRIDE the memory-cache placeholder, which would undo the whole no-flash probe.
            // Behind an aspect-filled image it is invisible once loaded, exactly as on iOS; every
            // surface that aspect-FITS its art draws its own ground and passes `placeholder = false`.
            .then(if (placeholder) Modifier.background(GradientPlaceholderBrush) else Modifier)
            .clearAndSetSemantics { }
    ) {
        if (source != null) {
            AsyncImage(
                model = remember(source, bucket, ladderKey, transformations) {
                    ImageRequest.Builder(context)
                        .data(source)
                        // A square box with FIT bounds the LONGEST edge, which is what iOS's
                        // `maxPixel` means. Set explicitly so Coil does not derive scale from
                        // `contentScale`: FILL against a square box would decode a wide banner
                        // far past its bucket.
                        .size(bucket, bucket)
                        .scale(Scale.FIT)
                        .precision(Precision.INEXACT)
                        .apply {
                            if (transformations.isEmpty()) {
                                memoryCacheKey(ImageBuckets.key(source, bucket))
                                placeholderMemoryCacheKey(ladderKey)
                            } else {
                                // Let Coil build the key: it folds in the transformation's own
                                // cacheKey and the size. Forcing "$url|$bucket" here would file the
                                // BLURRED bitmap under the sharp layer's key and serve it back to
                                // the sharp view.
                                transformations(transformations)
                                allowHardware(false) // a transform needs CPU-readable pixels
                            }
                        }
                        // Don't re-fade a picture the user is already looking at. (Coil also skips
                        // the transition for a memory-cache result, which covers the rest of it.)
                        .crossfade(if (ladderKey != null) 0 else ART_CROSSFADE_MILLIS)
                        .build()
                },
                contentDescription = null,
                imageLoader = loader,
                modifier = Modifier.matchParentSize(),
                alignment = alignment,
                contentScale = scale,
            )
        }
    }
}

/**
 * [ArtImage] under the name every iOS call site uses, with `RemoteImageView`'s defaults: the
 * pipeline's default decode size, aspect-fill, centred, placeholder shown, no snap.
 *
 * An empty string is no URL — the iOS pass-through returns `nil` for one, and so does this.
 */
@Composable
fun RemoteImage(
    url: String?,
    modifier: Modifier = Modifier,
    maxPixel: Int = ArtMaxPixel.DEFAULT,
    contentScale: ContentScale = ContentScale.Crop,
    alignment: Alignment = Alignment.Center,
    placeholder: Boolean = true,
    fitSnapAspect: Float? = null,
) {
    ArtImage(
        url = url,
        maxPixel = maxPixel,
        modifier = modifier,
        contentScale = contentScale,
        alignment = alignment,
        placeholder = placeholder,
        fitSnapAspect = fitSnapAspect,
    )
}

/**
 * The legacy fixed-size rounded thumbnail — the port of `Thumb`.
 *
 * Kept because it is a genuinely different object from `PosterSlot`: a thumbnail whose size the
 * caller states, rather than a named slot from the artwork table. Prefer `PosterSlot` for anything
 * that is a poster in a list.
 *
 * The decode is sized from the real frame ([artPixels]) rather than iOS's fixed 3× — "a 160-pt
 * thumb needs ~480 px, not 700" is the same rule, expressed against a density that varies here.
 */
@Composable
fun Thumb(
    cover: String?,
    width: Dp,
    height: Dp,
    modifier: Modifier = Modifier,
    radius: Dp = ThemeRadius.poster,
) {
    val longestEdge = if (width >= height) width else height
    Box(
        modifier
            .size(width, height)
            .clip(ContinuousCornerShape(radius))
            .background(ThemeColor.surfaceRaised)
    ) {
        ArtImage(
            url = cover,
            maxPixel = artPixels(longestEdge),
            modifier = Modifier.matchParentSize(),
            contentScale = ContentScale.Crop,
        )
    }
}
