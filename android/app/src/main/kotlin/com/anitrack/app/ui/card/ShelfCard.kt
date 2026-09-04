package com.anitrack.app.ui.card

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import com.anitrack.app.design.PosterSize
import com.anitrack.app.design.ThemeColor
import com.anitrack.app.design.ThemeSpace
import com.anitrack.app.design.ThemeType
import com.anitrack.app.ui.AutoSizeText
import com.anitrack.app.ui.art.PosterSlot
import com.anitrack.app.ui.control.PressStyle
import com.anitrack.app.ui.isAccessibilityTextSize
import com.anitrack.model.shelfShortened

/** The identity title shrinks to 82 % before it does anything else. It never ellipsizes. */
private const val SHELF_TITLE_MIN_SCALE = 0.82f

/** Two lines of title at ordinary sizes; at AX the card is a full-width row and may run to six. */
private const val SHELF_TITLE_LINES = 2
private const val SHELF_TITLE_LINES_AX = 6

/** Two lines and a tail ellipsis — the caption is a fact, and a fact may be cut. */
private const val SHELF_CAPTION_LINES = 2

/**
 * One poster on a horizontal shelf: the artwork, the identity title, and one caption.
 *
 * ### Nothing is reserved under the title
 *
 * The caption sits directly under the title, one line or two. Reserving a second line put an empty
 * band between every one-line name and its date (user, 24 Aug); a two-line name simply carries its
 * caption one line lower. (The iOS type's own doc comment still claims two reserved lines — the
 * code, and the inline comment recording the complaint, say otherwise, and the code is the spec.)
 *
 * ### The title takes its WRAPPED height, whatever the shelf proposes
 *
 * On Today's Watching shelf a two-line name was photographed scaled down and cut to one line with
 * an ellipsis ("The Beginning After…", 2 Sep): the horizontal scroller had handed the card a
 * one-line height budget and the range limit obeyed it. `wrapContentHeight(unbounded = true)` —
 * inside [AutoSizeText] — is what makes the limit mean "up to two" rather than "whatever fits".
 *
 * @param caption one fact under the title.
 * @param captionIsLead the caption is a forward-looking fact ("Returns Oct 2") and is therefore
 *   drawn in accent. A plain fact is grey. **This is the one amber decision a shelf card makes**,
 *   and it is made from which of the two fields the model populated — which is why a row's facts
 *   and its lead must never be merged upstream.
 * @param hint what tapping the card does, for TalkBack ("Opens the show"). The spoken title is the
 *   WHOLE title, never the shortened one.
 * @param width overrides [slot]'s width, for a GRID whose column width is measured rather than
 *   chosen — All titles' poster wall. The height follows from [PosterSize.posterAspectRatio], so a
 *   measured cell is still a 2:3 poster, and the radius and shadow are still the slot's. This is
 *   what stopped the poster wall being a second poster-cell anatomy: it re-implemented this file
 *   line for line, down to a duplicate copy of the min-scale and line-count constants that matched
 *   by coincidence and would have drifted on the next tune.
 */
@Composable
fun ShelfCard(
    title: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    caption: String? = null,
    captionIsLead: Boolean = false,
    poster: String? = null,
    slot: PosterSize = PosterSize.ShelfLarge,
    hint: String? = null,
    width: Dp? = null,
) {
    val isAX = isAccessibilityTextSize()
    val cellWidth = width ?: slot.width
    val spoken = remember(title, caption) {
        listOfNotNull(title, caption).joinToString(separator = ", ")
    }

    Column(
        modifier = modifier
            // The press radius is the SLOT's, not the row default: a 16-dp highlight inside a
            // 12-dp card leaves a sliver of un-highlighted card at each corner.
            .clickable(
                interactionSource = null,
                indication = PressStyle.row(slot.radius),
                onClickLabel = hint,
                role = Role.Button,
                onClick = onClick,
            )
            .semantics(mergeDescendants = true) { contentDescription = spoken },
        verticalArrangement = Arrangement.spacedBy(ThemeSpace.x2),
    ) {
        PosterSlot(
            url = poster,
            width = cellWidth,
            height = cellWidth / PosterSize.posterAspectRatio,
            radius = slot.radius,
            shadow = slot.shadow,
        )

        Column(
            // The poster's width — except at accessibility sizes, where a one-column grid hands the
            // card the whole row and the caption should not wrap "Anime / · 1999" inside a 112-dp
            // column beside it.
            modifier = if (isAX) Modifier.fillMaxWidth() else Modifier.width(cellWidth),
            verticalArrangement = Arrangement.spacedBy(ThemeSpace.x0_5),
            horizontalAlignment = Alignment.Start,
        ) {
            AutoSizeText(
                text = title.shelfShortened,
                style = ThemeType.shelfTitle.copy(color = ThemeColor.textPrimary),
                minScale = SHELF_TITLE_MIN_SCALE,
                maxLines = if (isAX) SHELF_TITLE_LINES_AX else SHELF_TITLE_LINES,
                modifier = Modifier.fillMaxWidth(),
            )
            if (caption != null) {
                BasicText(
                    text = caption,
                    style = ThemeType.shelfCaption.copy(
                        color = if (captionIsLead) ThemeColor.accent else ThemeColor.textSecondary,
                    ),
                    maxLines = SHELF_CAPTION_LINES,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}
