package com.anitrack.app.ui.art

import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.min
import androidx.compose.ui.unit.sp
import com.anitrack.app.design.MotionToken
import com.anitrack.app.design.PosterSize
import com.anitrack.app.design.PreviouslyIcons
import com.anitrack.app.design.ShadowToken
import com.anitrack.app.design.ThemeColor
import com.anitrack.app.design.ThemeMetrics
import com.anitrack.app.design.ThemeRadius
import com.anitrack.app.design.ThemeSpace
import com.anitrack.app.design.ThemeType
import com.anitrack.app.design.artFrame
import com.anitrack.app.design.motion
import com.anitrack.app.design.shadowToken
import com.anitrack.app.ui.control.SymbolIcon
import com.anitrack.app.ui.image.ArtBlur
import com.anitrack.app.ui.image.ArtImage
import com.anitrack.app.ui.image.ArtMaxPixel
import com.anitrack.app.ui.image.rememberArtTint
import com.anitrack.model.WideArt
import kotlin.math.max
import kotlin.math.roundToInt

/*
 * ARTWORK — the slots, the frames, and the one compositing rule that matters.
 *
 * Art is this product's only real material, and this file owns every decision about how a piece of
 * it meets its frame. Two rules run through all of it:
 *
 *   1. **Posters aspect-fit and stay whole; backdrops fill and crop.** A poster is an object the
 *      catalogue drew; a backdrop is a texture. `.fill` on a poster side-crops every asset that is
 *      not 2:3 — Wistoria's announcement lockup rendered as "son 3 制作".
 *
 *   2. **A landscape frame NEVER fills a portrait cover.** About a third of the catalogue has no
 *      landscape asset, and `.fill`ed into a 1.6–2.1:1 frame a 2:3 poster shows the middle third of
 *      itself: a forehead, a white slab, a fragment of a lockup. That is what Library's Announced
 *      shelf and Search's trending wall drew. When there is no banner the cover is composited WHOLE
 *      on its own blurred ground — see [LandscapeArt].
 *
 * Everything here is `accessibilityHidden` on iOS and `clearAndSetSemantics { }` here: a picture is
 * always described by the row or card around it, never by itself.
 */

// ─────────────────────────────────────────────────────────────────────────────
// 1. What this file does NOT own
// ─────────────────────────────────────────────────────────────────────────────
//
// **There is one image pipeline and one palette, and neither is here.** `ui/image/` owns the
// decode: the bucket ladder, the no-flash ladder probe, the bucketed memory-cache keys, the art
// `OkHttpClient`, the load fade and the baked `BlurTransformation`. `ui/image/ImageLoader.kt` owns
// the art-adaptive palette (`ArtPaletteCache`, published through `LocalArtPalette`) and its quiet
// tile form.
//
// This file draws SLOTS. It reaches the pipeline through four names and **declares no decode path,
// no transformation, no blur radius and no palette of its own**:
//
//   * `ArtImage` — the one composable that fetches and draws;
//   * `rememberArtTint` — the one way to a show's colour;
//   * `ArtMaxPixel` — the decode budget for a surface, asked for by name;
//   * `ArtBlur` — the softness for a surface, likewise.
//
// The last two matter as much as the first two. A second entry point would cache the same asset
// under two keys, decode a 2048-px billboard twice and lose the frame-one guarantee on the surfaces
// that recycle hardest; a decode budget or a blur radius written as a number *here* is the same
// drift arriving one literal at a time.

// ─────────────────────────────────────────────────────────────────────────────
// 2. PosterSlot — identity artwork, whole, in its slot
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Identity artwork filling its slot, grounded in the show's own colour.
 *
 * The context form: size, radius and shadow all come from the slot table, so a screen never has to
 * remember three numbers. **The table overrides the size heuristic** — [PosterSize.Row] (60 × 90,
 * long edge 90) carries no shadow where the heuristic in the explicit form would give it one.
 *
 * ```
 * PosterSlot(url = show.portraitArt, slot = PosterSize.Row)
 * ```
 */
@Composable
fun PosterSlot(url: String?, slot: PosterSize, modifier: Modifier = Modifier) {
    PosterSlot(
        url = url,
        width = slot.width,
        height = slot.height,
        radius = slot.radius,
        shadow = slot.shadow,
        modifier = modifier,
    )
}

/**
 * The explicit form, for the handful of places that size their own art.
 *
 * Layer order, bottom to top: `surfaceRaised` → the palette tint at 60 % → the poster, aspect-FIT
 * with fit-snap → or, with no URL, a centred `photo` glyph.
 *
 * **Why fit and not fill, and why there is no blurred backfill.** The shipped build aspect-*fitted*
 * every poster into a fixed 2:3 frame while the ground was grey, so every piece of artwork carried
 * a 5–6 dp bar of exact `surfaceRaised` across its top and bottom, with the art's square corners
 * inside a rounded frame showing dark wedges at all four. `.fill` was the answer *while the ground
 * was grey*; with the ground being the artwork's own palette colour it is the wrong one — it
 * side-cropped every asset that is not 2:3. And the blurred second copy that used to hide the mat
 * cost a second full decode plus a blur pass on every slot ≥ 72 dp — sixty of each on a 30-title
 * grid. A 0.708 cover loses 4 % of its height to the slot, which lands as a 2-dp tinted band, not a
 * grey bar.
 *
 * @param shadow `null` takes the size-appropriate token: art at or above 88 dp on its long edge
 *   reads as a physical object and earns a contact shadow; a 44-dp thumb does not.
 */
@Composable
fun PosterSlot(
    url: String?,
    width: Dp,
    height: Dp,
    radius: Dp = ThemeRadius.poster,
    shadow: ShadowToken? = null,
    modifier: Modifier = Modifier,
) {
    val density = LocalDensity.current
    // iOS asks for points × 3 because 3× is the largest iPhone scale, so one cache entry serves
    // every device. Android knows its own density, so the honest port asks for the pixels this
    // device will actually draw — smaller on an hdpi phone, identical at 3×.
    val maxPixel = remember(width, height, density) {
        with(density) { max(width.toPx(), height.toPx()) }.roundToInt().coerceAtLeast(1)
    }
    val token = shadow ?: if (max(width.value, height.value) >= 88f) ShadowToken.Art else ShadowToken.None
    val tint = rememberArtTint(url)

    Box(
        modifier
            .size(width, height)
            .artFrame(radius, token)
            .background(ThemeColor.surfaceRaised)
            // Strong enough that the band an aspect-fit leaves reads as the SHOW's colour rather
            // than as a grey mat. At 0.22 over `surfaceRaised` it was still grey.
            .then(tint?.let { Modifier.background(it.copy(alpha = 0.60f)) } ?: Modifier)
            .clearAndSetSemantics { },
        contentAlignment = Alignment.Center,
    ) {
        if (!url.isNullOrEmpty()) {
            ArtImage(
                url = url,
                maxPixel = maxPixel,
                modifier = Modifier.matchParentSize(),
                contentScale = ContentScale.Fit,
                placeholder = false,
                // A cover that misses the slot's ratio by ≤ 8 % fills instead of leaving a 2-dp
                // tinted sliver along one edge; a real mismatch keeps the honest fit.
                fitSnapAspect = if (height > 0.dp) width / height else null,
            )
        } else {
            SymbolIcon(
                symbol = PreviouslyIcons.Image,
                tint = ThemeColor.textTertiary,
                glyph = min(width, height) * 0.28f,
            )
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// 3. LandscapeArt — the compositing rule
// ─────────────────────────────────────────────────────────────────────────────

/** Defaults for [LandscapeArt], named so a caller never types a decode budget. */
object LandscapeArtDefaults {

    /** The sharp layer's decode. `BannerCard` and every 104-dp wide card draw at this. */
    const val maxPixel: Int = ArtMaxPixel.LANDSCAPE_SHARP

    /**
     * The blurred ground's decode. Deliberately tiny — it is about to be blurred to mush and then
     * scaled up over the whole frame, so anything larger is a decode spent on detail that is
     * destroyed on the next line.
     */
    const val groundMaxPixel: Int = ArtMaxPixel.LANDSCAPE_GROUND
}

/**
 * The veil over the blurred ground. Not a scrim token: it is not protecting copy, it is pushing the
 * ground back so the sharp cover in front of it is unmistakably the subject.
 */
private val PortraitGroundVeil = Color.Black.copy(alpha = 0.32f)

/**
 * Artwork in a LANDSCAPE frame — and the rule that a landscape frame **never fills a portrait
 * cover**.
 *
 * - **A real banner** ([portraitSource] false): one image, filled and cropped, anchored to
 *   [alignment]. A backdrop is a texture; cropping it is what it is for.
 * - **A cover with no banner** ([portraitSource] true): the cover composited WHOLE over its own
 *   blurred, veiled copy, with a contact shadow between them. *"Without it the two read as one
 *   badly-decoded image."*
 *
 * Callers never make this choice themselves — they pass the model's `wideArt`, which already
 * decided (see the [WideArt] overload). A screen that reads `banner ?: cover` and passes the result
 * as a banner is the bug this whole path exists to end.
 *
 * The frame is always sized by its host (a 104-dp card, a 16:9 ratio box), so this fills whatever
 * it is given.
 */
@Composable
fun LandscapeArt(
    url: String?,
    portraitSource: Boolean = false,
    maxPixel: Int = LandscapeArtDefaults.maxPixel,
    alignment: Alignment = Alignment.TopCenter,
    modifier: Modifier = Modifier,
) {
    if (!portraitSource) {
        ArtImage(
            url = url,
            maxPixel = maxPixel,
            modifier = modifier.fillMaxSize(),
            contentScale = ContentScale.Crop,
            alignment = alignment,
            // The host draws the ground (a card's `surfaceRaised`, a hero's palette colour), so a
            // second opaque placeholder underneath would only cover it.
            placeholder = false,
        )
    } else {
        Box(modifier.fillMaxSize().clipToBounds()) {
            // 1 — the ground: a 160-px decode, blurred once and cached, cropped to FILL the frame.
            //     `Crop`, never `Fit`: a fitted ground samples whatever corner the poster landed in.
            //     Cropping happens at draw time here where iOS crops before blurring; with clamped
            //     edges the two are identical, and blur-then-crop is the better order at the seams.
            ArtImage(
                url = url,
                maxPixel = LandscapeArtDefaults.groundMaxPixel,
                modifier = Modifier.matchParentSize(),
                contentScale = ContentScale.Crop,
                placeholder = false,
                transformations = ArtBlur.LANDSCAPE_GROUND,
            )
            Box(Modifier.matchParentSize().background(PortraitGroundVeil))

            // 2 — the cover, whole, with its contact shadow.
            //
            //     The shadow is cast by a 2:3 box rather than by the drawn pixels, because Compose
            //     casts an elevation shadow from a node's SHAPE and a fitted image does not fill
            //     its node. A 0.708 cover fitted in a 2:3 box leaves ~3 % of the height unfilled
            //     top and bottom, so the shadow's edge sits ~2 dp outside the art — invisible under
            //     the blur of a contact shadow, and the cover still ends up on screen whole, which
            //     is the promise.
            Box(
                Modifier
                    .align(Alignment.Center)
                    .fillMaxHeight()
                    .padding(vertical = ThemeSpace.x2)
                    .aspectRatio(PosterSize.posterAspectRatio, matchHeightConstraintsFirst = true)
                    .shadowToken(ShadowToken.Art),
            ) {
                ArtImage(
                    url = url,
                    maxPixel = maxPixel,
                    modifier = Modifier.matchParentSize(),
                    contentScale = ContentScale.Fit,
                    placeholder = false,
                )
            }
        }
    }
}

/**
 * [LandscapeArt] from the model's own decision — `franchise.wideArt`, `part.wideArt`,
 * `part.wideArt(within:)`. **This is the form screens use.**
 */
@Composable
fun LandscapeArt(
    art: WideArt,
    maxPixel: Int = LandscapeArtDefaults.maxPixel,
    alignment: Alignment = Alignment.TopCenter,
    modifier: Modifier = Modifier,
) {
    LandscapeArt(
        url = art.url,
        portraitSource = art.portraitSource,
        maxPixel = maxPixel,
        alignment = alignment,
        modifier = modifier,
    )
}

// ─────────────────────────────────────────────────────────────────────────────
// 4. Episode artwork
// ─────────────────────────────────────────────────────────────────────────────

/** The episode tile's geometry, named once so nothing re-derives it. */
object EpisodeArtworkDefaults {

    /**
     * 120 × 68 (16:9).
     *
     * It was 96 × 54 — a postage stamp beside 17-sp type, where Netflix's episode thumbnails run
     * ~130 dp wide. And it is **one rectangle for every episode row, still or not**: the shipped
     * build put a 96 × 54 photograph on rows that had art and a 48 × 48 square on rows that did
     * not, so a season list changed shape halfway down and the row rhythm broke with it.
     */
    val slot: DpSize = DpSize(120.dp, 68.dp)

    /** The still's decode. The pipeline's table is the one that states it. */
    const val stillMaxPixel: Int = ArtMaxPixel.EPISODE_STILL

    /** [EpisodeStill]'s decode when it fills the width it is offered (the accessibility card). */
    const val fullWidthMaxPixel: Int = 1200
}

/**
 * The darkening over a fallback tile, so it never competes with a row beside it that has real art.
 * Three depths, because the brighter the fallback art the harder the numeral has to work: a bare
 * tint needs the least, a season poster the most.
 */
private val TileShadeNone = listOf(Color.Black.copy(alpha = 0.10f), Color.Black.copy(alpha = 0.34f))
private val TileShadeLandscape =
    listOf(Color.Black.copy(alpha = 0.20f), Color.Black.copy(alpha = 0.46f))
private val TileShadePoster =
    listOf(Color.Black.copy(alpha = 0.25f), Color.Black.copy(alpha = 0.50f))

/**
 * The episode number, drawn on a fallback tile.
 *
 * iOS draws this ad hoc (`.system(size: 17, weight: .bold).monospacedDigit()`) rather than from the
 * type palette, and the palette has no 17/bold tabular cut to name — so it is derived from the one
 * token that already carries the annotating face with tabular figures rather than inventing a face
 * at the call site. Tabular matters: a column of tiles reading 9, 10, 11 must not shuffle sideways.
 *
 * The shadow is an ink shadow, not an elevation — legibility over an arbitrary photograph.
 */
private val EpisodeNumberStyle = ThemeType.time.copy(
    fontSize = 17.sp,
    fontWeight = FontWeight.Bold,
    lineHeight = 22.sp,
    color = ThemeColor.textPrimary,
    shadow = Shadow(
        color = Color.Black.copy(alpha = 0.55f),
        offset = Offset(0f, 1f),
        blurRadius = 3f,
    ),
)

/**
 * The episode tile with its full fallback CHAIN: **still → the season's landscape art → the season's
 * cover under the episode number → the show's colour**.
 *
 * *"A glyph is only honest where there is no art at all, and there is always art — the season has a
 * poster."* The shipped build drew a play glyph on every row without a still, so an anime season
 * (which rarely has per-episode stills) was a wall of identical grey rectangles; and a bare text row
 * was worse. The chain means a season the catalogue never illustrated still reads 11, 12, 13 down
 * the column instead of one poster eighteen times.
 *
 * The number is drawn **only when there is no real still**: a still is never labelled, because the
 * row's own text is 8 dp away. The poster rung crops to `.top`, because a 2:3 cover carries the face
 * in its upper half and the logotype band in its lower one.
 *
 * The guard against a whole season of one repeated poster lives upstream, in the season screen's art
 * policy, which drops the art column entirely for a barely-illustrated season.
 *
 * @param url the episode's own still.
 * @param landscape the season's (or show's) landscape art — the first fallback, because it fills a
 *   16:9 tile the way a still does. Anime rarely has one; TV usually does.
 * @param poster the season's (or show's) cover — the fallback ART, never a glyph.
 * @param tint the show's palette colour, so the slot is never grey.
 * @param width `null` fills the width it is offered (the accessibility-size card); a number pins
 *   the slot.
 */
@Composable
fun EpisodeStill(
    url: String?,
    poster: String?,
    landscape: String? = null,
    tint: Color? = null,
    width: Dp? = EpisodeArtworkDefaults.slot.width,
    number: Int? = null,
    modifier: Modifier = Modifier,
) {
    val density = LocalDensity.current
    val maxPixel = remember(width, density) {
        width?.let { with(density) { it.toPx() }.roundToInt().coerceAtLeast(1) }
            ?: EpisodeArtworkDefaults.fullWidthMaxPixel
    }

    val hasStill = !url.isNullOrEmpty()
    val hasLandscape = !landscape.isNullOrEmpty()
    val hasPoster = !poster.isNullOrEmpty()
    val paletteSource = url ?: landscape ?: poster
    val stillTint = rememberArtTint(paletteSource, quiet = true)

    Box(
        modifier
            .then(if (width != null) Modifier.width(width) else Modifier.fillMaxWidth())
            // 16:9 BY RATIO, never a fixed height — a fixed height plus a gutter applied twice had
            // drawn every card 16 dp inside its own header. The ratio is the app's one landscape
            // ratio, never a literal.
            .aspectRatio(ThemeMetrics.wideAspect)
            .artFrame(ThemeRadius.episodeStill)
            .background(stillTint ?: tint ?: ThemeColor.surfaceRaised)
            .clearAndSetSemantics { },
    ) {
        when {
            hasStill -> ArtImage(
                url = url,
                maxPixel = maxPixel,
                modifier = Modifier.matchParentSize(),
                contentScale = ContentScale.Crop,
                placeholder = false,
            )

            hasLandscape -> {
                // A banner fills the tile the way a still does; the numeral still says which
                // episode, because one banner eighteen times is not eighteen episodes.
                ArtImage(
                    url = landscape,
                    maxPixel = maxPixel,
                    modifier = Modifier.matchParentSize(),
                    contentScale = ContentScale.Crop,
                    placeholder = false,
                )
                Box(Modifier.matchParentSize().background(Brush.verticalGradient(TileShadeLandscape)))
            }

            hasPoster -> {
                ArtImage(
                    url = poster,
                    maxPixel = maxPixel,
                    modifier = Modifier.matchParentSize(),
                    contentScale = ContentScale.Crop,
                    alignment = Alignment.TopCenter,
                    placeholder = false,
                )
                Box(Modifier.matchParentSize().background(Brush.verticalGradient(TileShadePoster)))
            }

            // Genuinely no artwork anywhere for this show: the show's colour and nothing else. A
            // play glyph here would claim a picture failed to load.
            else -> Box(Modifier.matchParentSize().background(Brush.verticalGradient(TileShadeNone)))
        }

        if (number != null && !hasStill) {
            BasicText(
                text = number.toString(),
                style = EpisodeNumberStyle,
                modifier = Modifier
                    .align(Alignment.BottomStart)
                    // iOS insets this by 7; the scale's neighbouring step is 8 and one dp on a
                    // numeral's inset is not a difference anyone can see.
                    .padding(ThemeSpace.x2),
            )
        }
    }
}

/**
 * The SPOILER-AWARE episode tile.
 *
 * A spoiler-protected still is **replaced, never blurred** — a blur is a tease, and it has no
 * VoiceOver equivalent. The episode number is drawn exactly once, in the row's text, so this tile
 * never carries one.
 *
 * @param showTint the FRANCHISE's palette colour. A show whose stills are missing still has a
 *   colour, and a list where two rows carry a photograph and eight carry an identical grey
 *   play-glyph reads as a broken list. Passing this makes the glyph rows read as *this show, no
 *   still yet*.
 */
@Composable
fun EpisodeArtwork(
    url: String?,
    spoilerSafe: Boolean = true,
    showTint: Color? = null,
    modifier: Modifier = Modifier,
) {
    val hasStill = spoilerSafe && !url.isNullOrEmpty()
    if (!hasStill) {
        EpisodeGlyphTile(showTint = showTint, modifier = modifier)
    } else {
        val tint = rememberArtTint(url)
        // The tint-to-image fade is the loader's own; this is the ground arriving under it.
        val ground by animateColorAsState(
            targetValue = tint ?: ThemeColor.surfaceRaised,
            animationSpec = motion<Color>(MotionToken.UI_POSTER),
            label = "episodeArtworkTint",
        )

        Box(
            modifier
                .size(EpisodeArtworkDefaults.slot.width, EpisodeArtworkDefaults.slot.height)
                .artFrame(ThemeRadius.episodeStill)
                .background(ground)
                .clearAndSetSemantics { },
            contentAlignment = Alignment.Center,
        ) {
            // The failed state, mirroring PosterSlot: the symbol sits UNDER the image, so a fetch
            // that never resolves leaves the tint plus a centred photo glyph instead of a bare
            // rectangle. The image covers it the moment it lands.
            SymbolIcon(
                symbol = PreviouslyIcons.Image,
                tint = ThemeColor.textTertiary,
                glyph = 16.dp,
            )
            ArtImage(
                url = url,
                maxPixel = EpisodeArtworkDefaults.stillMaxPixel,
                modifier = Modifier.matchParentSize(),
                contentScale = ContentScale.Crop,
                placeholder = false,
            )
        }
    }
}

/**
 * The episode tile with no still to show — the show's colour, darkened, under a play glyph.
 *
 * Used only by [EpisodeArtwork], where a hidden still is a deliberate act rather than missing art.
 * [EpisodeStill] never falls back to this: there the show has a poster, and art beats a glyph.
 */
@Composable
fun EpisodeGlyphTile(showTint: Color? = null, modifier: Modifier = Modifier) {
    Box(
        modifier
            .size(EpisodeArtworkDefaults.slot.width, EpisodeArtworkDefaults.slot.height)
            .artFrame(ThemeRadius.episodeStill)
            .background(showTint ?: ThemeColor.surfaceRaised)
            .background(Brush.verticalGradient(TileShadeNone))
            .clearAndSetSemantics { },
        contentAlignment = Alignment.Center,
    ) {
        SymbolIcon(
            symbol = PreviouslyIcons.SmartDisplay,
            tint = ThemeColor.textPrimary.copy(alpha = 0.34f),
            glyph = 17.dp,
        )
    }
}
