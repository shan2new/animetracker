package com.anitrack.app.ui.card

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.anitrack.app.design.ContinuousCornerShape
import com.anitrack.app.design.ShadowToken
import com.anitrack.app.design.ThemeColor
import com.anitrack.app.design.ThemeMetrics
import com.anitrack.app.design.ThemeRadius
import com.anitrack.app.design.ThemeSpace
import com.anitrack.app.design.ThemeType
import com.anitrack.app.design.shadowToken
import com.anitrack.app.ui.AutoSizeText
import com.anitrack.app.ui.art.LandscapeArt
import com.anitrack.app.ui.control.PressStyle
import com.anitrack.model.copy.Copy
import com.anitrack.model.shelfShortened

/**
 * The wide art card's one height. A `feature` variant (176 dp) existed for the status tabs' lead
 * card and died with them (30 Aug); Library's skeletons measure against this.
 */
val BannerCardHeight: Dp = 104.dp

/** Banner decode budget at the width the card actually renders. */
private const val BANNER_MAX_PIXEL = 560

/** Same floor as [ShelfCard]: the identity title shrinks before it does anything else. */
private const val BANNER_TITLE_MIN_SCALE = 0.82f
private const val BANNER_TITLE_LINES = 2
private const val BANNER_CAPTION_LINES = 2

/** The card's edge. `posterEdge` (white 9 %), never `stroke` — this is the edge of ARTWORK. */
private val bannerEdgeWidth = ThemeMetrics.hairline

/**
 * A wide art card that sells a show: banner art on top, the title and one caption beneath.
 *
 * **One geometry, app-wide.** This object existed three times before the 30 Aug cohesion pass —
 * Library's shelf card (104 pt, radius 13), Library's status feature card (176 pt, radius 18) and
 * Search's browse tile (radius 22) — three geometries and three title treatments for one job, two
 * of the radii in no token table. The radius is [ThemeRadius.card].
 *
 * @param lead the forward-looking fact, in accent — the same contract as `MediaRow`'s lead.
 * @param meta a plain fact, in grey.
 * @param portraitSource `art` is a portrait COVER (the catalogue has no banner), so it is
 *   composited whole on its own blurred ground rather than cropped to a horizontal slice of itself.
 *   **A landscape frame never fills a portrait cover** — see `LandscapeArt`.
 *
 * The caption is `lead ?: meta`, and **the amber decision is made here so a screen cannot opt out
 * of it again**: a forward-looking fact ("Returns today") is accent, a plain fact is grey. Library
 * hard-coded grey and rendered the identical class of fact Today draws amber — the app's central
 * colour rule answered two ways one tab apart.
 */
@Composable
fun BannerCard(
    title: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    lead: String? = null,
    meta: String? = null,
    art: String? = null,
    portraitSource: Boolean = false,
) {
    val caption = lead ?: meta
    // The spoken title is the WHOLE title, never the shortened one.
    val spoken = remember(title, caption) {
        listOfNotNull(title, caption).joinToString(separator = ", ")
    }

    Column(
        modifier = modifier
            // The target IS a photograph: `overArt` dips it in brightness and compresses a hair.
            // A `surfacePressed` wash here would be a grey film over someone's illustration.
            .clickable(
                interactionSource = null,
                indication = PressStyle.overArt,
                onClickLabel = Copy.Accessibility.opensTheShowHint,
                role = Role.Button,
                onClick = onClick,
            )
            .semantics(mergeDescendants = true) { contentDescription = spoken },
        verticalArrangement = Arrangement.spacedBy(ThemeSpace.x2),
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(BannerCardHeight)
                // The shadow is cast from a circular-arc silhouette and the content clipped with
                // the squircle: a generic path casts no native elevation shadow below API 29, and
                // under a blurred shadow the two outlines are indistinguishable.
                .shadowToken(ShadowToken.Art, RoundedCornerShape(ThemeRadius.card))
                .clip(ContinuousCornerShape(ThemeRadius.card))
                .background(ThemeColor.surfaceRaised),
        ) {
            LandscapeArt(
                url = art,
                portraitSource = portraitSource,
                maxPixel = BANNER_MAX_PIXEL,
                modifier = Modifier.fillMaxSize(),
            )
            // Drawn last so the edge sits on top of the art, not under it.
            Box(
                Modifier
                    .matchParentSize()
                    .border(
                        width = bannerEdgeWidth,
                        color = ThemeColor.posterEdge,
                        shape = ContinuousCornerShape(ThemeRadius.card),
                    ),
            )
        }

        Column(verticalArrangement = Arrangement.spacedBy(ThemeSpace.x0_5)) {
            AutoSizeText(
                text = title.shelfShortened,
                style = ThemeType.shelfTitle.copy(color = ThemeColor.textPrimary),
                minScale = BANNER_TITLE_MIN_SCALE,
                maxLines = BANNER_TITLE_LINES,
                modifier = Modifier.fillMaxWidth(),
            )
            if (caption != null) {
                BasicText(
                    text = caption,
                    style = ThemeType.shelfCaption.copy(
                        color = if (lead != null) ThemeColor.accent else ThemeColor.textSecondary,
                    ),
                    maxLines = BANNER_CAPTION_LINES,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}
