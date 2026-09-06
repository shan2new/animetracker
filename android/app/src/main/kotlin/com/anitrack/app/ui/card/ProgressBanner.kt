package com.anitrack.app.ui.card

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.anitrack.app.design.ContinuousCornerShape
import com.anitrack.app.design.ShadowToken
import com.anitrack.app.design.ThemeColor
import com.anitrack.app.design.ThemeMetrics
import com.anitrack.app.design.ThemeRadius
import com.anitrack.app.design.ThemeSpace
import com.anitrack.app.design.shadowToken
import com.anitrack.app.ui.art.LandscapeArt
import com.anitrack.app.ui.control.ProgressBar
import com.anitrack.app.ui.section.OverArtLabel


/** The bar's inset from the art's edges, on three sides. */
private val progressBannerInset: Dp = ThemeSpace.x3

/**
 * The scrim under the bar. A short gradient, **never a plate** — the bar has to read on any art,
 * and a plate would announce itself on art that never needed one.
 */
private val progressBannerScrimHeight = 56.dp

/** Wide art at the width a Continue card and a season header actually render. */
private const val PROGRESS_BANNER_MAX_PIXEL = 900

/** The bar's height, which the episode pill clears when both are drawn. */
private val progressBarThickness = 3.dp


/** The edge of artwork: `posterEdge` (white 9 %), never `stroke`. */
private val progressBannerEdgeWidth = ThemeMetrics.hairline

/**
 * One wide piece of art with where-you-are drawn ON it: a 16:9 card with the progress bar inset
 * over a short scrim at its foot — Apple TV's Up Next card.
 *
 * Library's *Continue watching* cards and the season screen's header are this one view.
 *
 * **16:9 BY RATIO, never a fixed height.** A fixed height plus a gutter applied twice had drawn
 * every Schedule card 16 dp inside its own day header — two left edges on one screen.
 *
 * The card carries no text. A numeral, where a screen wants one, sits on the title's baseline
 * beneath it, never in the picture.
 *
 * @param portraitSource `url` is a portrait cover: composited whole on its own blurred ground
 *   rather than cropped. See `LandscapeArt`.
 * @param progress 0…1; `null` while there is nothing to measure. The bar is wordless and silent —
 *   the screen around it carries the count.
 */
@Composable
fun ProgressBanner(
    url: String?,
    modifier: Modifier = Modifier,
    portraitSource: Boolean = false,
    progress: Float? = null,
    maxPixel: Int = PROGRESS_BANNER_MAX_PIXEL,
    /**
     * The EPISODE on the art — "EPISODE 21" as a pill in the BOTTOM-start corner, above the bar
     * when there is one ("the episode number can be fitted right into the image itself … otherwise
     * it's tough to read", then "move the episode pill to the bottom-left so it stops covering
     * faces", user, 4 Sep). The ONE pill a card wears; what it says beneath is the moment or the
     * season.
     */
    episode: String? = null,
    /** See [LandscapeArt]'s `ultraWide`. */
    ultraWide: Boolean = false,
) {
    Box(
        modifier = modifier
            .fillMaxWidth()
            .aspectRatio(ThemeMetrics.wideAspect)
            // Circular-arc silhouette for the shadow, squircle for the clip — see BannerCard.
            .shadowToken(ShadowToken.Art, RoundedCornerShape(ThemeRadius.card))
            .clip(ContinuousCornerShape(ThemeRadius.card))
            .background(ThemeColor.surfaceRaised),
    ) {
        LandscapeArt(
            url = url,
            portraitSource = portraitSource,
            maxPixel = maxPixel,
            modifier = Modifier.fillMaxSize(),
            ultraWide = ultraWide,
        )

        Box(
            Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
                .height(progressBannerScrimHeight)
                .background(Brush.verticalGradient(listOf(Color.Transparent, ThemeColor.scrim))),
        )

        if (progress != null) {
            ProgressBar(
                value = progress,
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .padding(
                        start = progressBannerInset,
                        end = progressBannerInset,
                        bottom = progressBannerInset,
                    )
                    .fillMaxWidth(),
            )
        }

        if (episode != null) {
            OverArtLabel(
                text = episode,
                modifier = Modifier
                    .align(Alignment.BottomStart)
                    .padding(
                        start = progressBannerInset,
                        // Above the bar (3 dp) by a step when the card carries one.
                        bottom = if (progress == null) progressBannerInset
                                 else progressBannerInset + progressBarThickness + ThemeSpace.x2,
                    ),
            )
        }

        Box(
            Modifier
                .matchParentSize()
                .border(
                    width = progressBannerEdgeWidth,
                    color = ThemeColor.posterEdge,
                    shape = ContinuousCornerShape(ThemeRadius.card),
                ),
        )
    }
}
