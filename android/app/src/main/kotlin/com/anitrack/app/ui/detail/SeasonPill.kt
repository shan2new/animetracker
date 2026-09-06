package com.anitrack.app.ui.detail

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.anitrack.app.design.PreviouslyIcons
import com.anitrack.app.design.ThemeColor
import com.anitrack.app.design.ThemeMetrics
import com.anitrack.app.design.ThemeType
import com.anitrack.app.design.rememberSymbol
import com.anitrack.app.ui.control.PressStyle
import com.anitrack.app.ui.control.materialGlyphBox
import com.anitrack.app.ui.control.minimumTapTarget
import com.anitrack.model.FranchisePart
import com.anitrack.model.copy.Copy

/**
 * The season as a capsule menu — "Season 4 ⌄" — the ONE control that chooses a season, on the show
 * page's Episodes header and on the season screen. The bar's status-menu family, drawn on the canvas:
 * `surfaceFloating` ground, a hairline stroke, `metadataEmphasis`. It lists SEASONS
 * (`Franchise.seasonPartsInOrder`), never the catalogue. The season's name used to BE the section
 * title, with a stacked `unfold_more` glyph, and did not read as a control (4 Sep); every streaming app
 * draws the selector as a pill beside "Episodes".
 */
@Composable
internal fun SeasonPill(
    current: FranchisePart,
    seasons: List<FranchisePart>,
    onPick: (Int) -> Unit,
    modifier: Modifier = Modifier,
) {
    var open by remember { mutableStateOf(false) }
    val label = seasonLabel(current)

    // The visual is 34 dp; the target is the platform's 44.
    Box(modifier.heightIn(min = minimumTapTarget), contentAlignment = Alignment.CenterEnd) {
        Row(
            modifier = Modifier
                .clip(CircleShape)
                .background(ThemeColor.surfaceFloating, CircleShape)
                .border(ThemeMetrics.hairline, ThemeColor.stroke, CircleShape)
                .clickable(
                    interactionSource = null,
                    indication = PressStyle.control,
                    role = Role.Button,
                    onClick = { open = true },
                )
                .semantics(mergeDescendants = true) {
                    contentDescription = Copy.Detail.seasonPicker(label)
                }
                .heightIn(min = PILL_HEIGHT)
                .padding(horizontal = PILL_SIDE_PADDING),
            horizontalArrangement = Arrangement.spacedBy(DetailMetrics.glyphGap),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            BasicText(
                text = label,
                style = ThemeType.metadataEmphasis.copy(color = ThemeColor.textPrimary),
                maxLines = 1,
            )
            Image(
                imageVector = rememberSymbol(PreviouslyIcons.KeyboardArrowDown),
                contentDescription = null,
                modifier = Modifier.size(materialGlyphBox(DetailMetrics.statusCaretGlyph)),
                colorFilter = ColorFilter.tint(ThemeColor.textPrimary),
            )
        }
        DetailMenu(expanded = open, onDismiss = { open = false }) {
            seasons.forEach { season ->
                DetailMenuItem(
                    label = seasonLabel(season),
                    symbol = if (season.mediaId == current.mediaId) PreviouslyIcons.Check else null,
                ) {
                    open = false
                    onPick(season.mediaId)
                }
            }
        }
    }
}

private val PILL_HEIGHT = 34.dp
private val PILL_SIDE_PADDING = 14.dp
