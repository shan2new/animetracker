package com.anitrack.app.ui.row

import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import com.anitrack.app.design.PosterSize
import com.anitrack.app.design.PreviouslyIcons
import com.anitrack.app.design.ThemeColor
import com.anitrack.app.design.ThemeMetrics
import com.anitrack.app.design.ThemeRadius
import com.anitrack.app.design.ThemeSpace
import com.anitrack.app.design.ThemeType
import com.anitrack.app.ui.art.PosterSlot
import com.anitrack.app.ui.control.PressStyle
import com.anitrack.app.ui.control.ProgressBar
import com.anitrack.app.ui.control.SymbolIcon
import com.anitrack.app.ui.isAccessibilityTextSize
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.withStyle

/**
 * Width a list reserves along its trailing edge for chrome that floats over it — today that is
 * Library's A–Z index rail, which lives in the same 16-dp gutter every row ends in.
 *
 * Set it once on the list; every [MediaRow] inside stops short of the reserved strip. Without it a
 * fixed trailing chevron and a rail letter can land on the same 4 dp of screen, which is what an
 * indexed list looks like when nobody reserved the gutter (Contacts reserves it).
 */
val LocalListTrailingInset = compositionLocalOf { 0.dp }

/** Past / already-handled rows recede as a GROUP. See the note on [MediaRow]'s `dimmed`. */
private const val DIMMED_ROW_ALPHA = 0.72f

/**
 * The disclosure column: fixed, so every chevron in a list shares one x.
 *
 * iOS reserves 11 pt for a 13-pt SF glyph whose ink is about 7 pt wide. The column IS the glyph's
 * box, and that box is [materialGlyphBox]'s — the ink lands about 2 dp further from the trailing
 * edge than on iOS, which is invisible, and every row still shares one right edge, which is the
 * whole point. **The ratio is not re-spelled here**: an 18-dp literal made a `MediaRow`'s chevron
 * a size larger than the identical chevron in a `GroupedRow` two screens away.
 *
 * Stated as the iOS POINT size; `SymbolIcon` draws the box.
 */
private val chevronGlyph = 13.dp

/** The separator is a hairline, not a rule: one device-independent point. */
private val separatorHeight = ThemeMetrics.hairline

/**
 * Two lines of identity title, unbounded at accessibility sizes — nothing truncates there, the
 * container grows.
 */
private const val ROW_TITLE_LINES = 2

/**
 * The canonical repeating row: artwork, an identity title, one fact, one optional forward-looking
 * fact in accent, and a trailing control. Library, Schedule, Search and Detail all render this
 * shape; the shipped iOS build hand-rolled it four times at four sizes with four different poster
 * slots, which is most of why the app read as four apps.
 *
 * **It sits on the CANVAS with a hairline under it — not inside a stroked box. A list of shows is
 * not a form.** And its height comes from its ART: `rowMedia` (100 dp) for a catalogue slot,
 * `rowStandard` (88 dp) for the purpose-built compact ones. A uniform hairline grid is what makes a
 * media app look like a list of settings.
 *
 * @param meta the one fact, in `textSecondary`.
 * @param lead the forward-looking fact — "Returns Oct 2", "Episode 19 next". Amber, because a real
 *   next step is exactly what amber is for. **Never use it for a status that has already
 *   happened.** It is drawn ABOVE [meta], directly under the title.
 * @param chevron the disclosure indicator, in a fixed trailing column. Pass `false` where the
 *   trailing slot holds a control instead.
 * @param dimmed one opacity on the whole row group, never per element — one opacity keeps the
 *   artwork's colour relationship intact. 0.72, not 0.45: at 0.45 `textSecondary` over the canvas
 *   composites to ≈#515151 (2.64:1) and it was applied to exactly the rows being scanned for a date
 *   (Schedule's past week, Detail's unaired episodes). 0.72 lands at ≈5.4:1 and still reads as a
 *   group that has stepped back.
 * @param hint what tapping this row does, for TalkBack. Schedule's and Detail's rows carry one;
 *   Today's did not, so the same control was self-describing on two screens and mute on a third.
 * @param progress where you are, 0…1, drawn as a 3-dp bar under the text column — the wordless form
 *   of "11 of 24 watched". A row that carries one says in words only what is COMING.
 * @param progressSpoken the bar's count, for TalkBack ("11 of 24 watched"); the bar itself is
 *   silent, and this is folded into the row's own label rather than announced separately.
 * @param trailing the caller's control, between the text and the chevron. **It must declare
 *   `Modifier.semantics(mergeDescendants = true)` on itself**, otherwise this row's merge absorbs
 *   it and TalkBack can no longer reach the control (`MarkRing` and Discover's add badge both do).
 */
@Composable
fun MediaRow(
    title: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    meta: String? = null,
    /** A forward fact appended to [meta] in accent, on the same line (i1-F10). */
    metaLead: String? = null,
    lead: String? = null,
    poster: String? = null,
    slot: PosterSize = PosterSize.Row,
    chevron: Boolean = true,
    dimmed: Boolean = false,
    separator: Boolean = true,
    hint: String? = null,
    progress: Float? = null,
    progressSpoken: String? = null,
    trailing: (@Composable RowScope.() -> Unit)? = null,
) {
    val isAX = isAccessibilityTextSize()
    val trailingInset = LocalListTrailingInset.current

    // Spelled out rather than left to the merge, so the trailing chevron is never spoken.
    val spoken = remember(title, lead, meta, progress, progressSpoken) {
        listOfNotNull(title, lead, meta, if (progress == null) null else progressSpoken)
            .joinToString(separator = ", ")
    }
    val separatorInset = if (poster == null) 0.dp else slot.width + ThemeMetrics.artGap

    Row(
        modifier = modifier
            .fillMaxWidth()
            // The press wash covers the row INCLUDING its hairline; the dimming does not — on iOS
            // the separator is an overlay added after `.opacity(...)`, so a receded row keeps a
            // full-strength hairline. It is `separatorQuiet` (white 4.5 %), so this is a
            // difference of a few values either way; the order is preserved because it is what
            // the shipped code does: the indication node sits above the separator's draw.
            .clickable(
                interactionSource = null,
                indication = PressStyle.row(ThemeRadius.row),
                onClickLabel = hint,
                role = Role.Button,
                onClick = onClick,
            )
            .semantics(mergeDescendants = true) { contentDescription = spoken }
            .drawWithContent {
                drawContent()
                if (separator) {
                    val inset = separatorInset.toPx()
                    val thickness = separatorHeight.toPx()
                    val left = if (layoutDirection == LayoutDirection.Ltr) inset else 0f
                    drawRect(
                        color = ThemeColor.separatorQuiet,
                        topLeft = Offset(left, size.height - thickness),
                        size = Size(size.width - inset, thickness),
                    )
                }
            }
            // Past / already-handled rows recede as one group, never element by element.
            .then(if (dimmed) Modifier.alpha(DIMMED_ROW_ALPHA) else Modifier)
            .padding(end = trailingInset)
            .heightIn(min = minimumRowHeight(slot))
            .padding(vertical = ThemeSpace.x2),
        horizontalArrangement = Arrangement.spacedBy(ThemeMetrics.artGap),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (poster != null) {
            PosterSlot(url = poster, slot = slot)
        }

        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(ThemeMetrics.titleGap),
        ) {
            BasicText(
                text = title,
                style = ThemeType.rowTitle.copy(color = ThemeColor.textPrimary),
                maxLines = if (isAX) Int.MAX_VALUE else ROW_TITLE_LINES,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.wrapContentHeight(align = Alignment.Top, unbounded = true),
            )
            // Order is load-bearing: the amber fact sits directly under the title, above the meta.
            if (lead != null) {
                BasicText(
                    text = lead,
                    style = ThemeType.rowMetaLead.copy(color = ThemeColor.accent),
                    modifier = Modifier.wrapContentHeight(align = Alignment.Top, unbounded = true),
                )
            }
            if (meta != null) {
                BasicText(
                    text = if (metaLead == null) AnnotatedString(meta) else buildAnnotatedString {
                        append(meta); append(" · ")
                        withStyle(SpanStyle(color = ThemeColor.accent)) { append(metaLead) }
                    },
                    style = ThemeType.rowMeta.copy(color = ThemeColor.textSecondary),
                    modifier = Modifier.wrapContentHeight(align = Alignment.Top, unbounded = true),
                )
            }
            if (progress != null) {
                ProgressBar(
                    value = progress,
                    modifier = Modifier
                        .padding(top = ThemeSpace.x1, end = ThemeSpace.x6)
                        .fillMaxWidth(),
                )
            }
        }

        Spacer(Modifier.width(ThemeSpace.x3))

        if (trailing != null) trailing()

        if (chevron) {
            SymbolIcon(
                symbol = PreviouslyIcons.ChevronRight,
                tint = ThemeColor.textDisabled,
                glyph = chevronGlyph,
            )
        }
    }
}

/**
 * Catalogue rows keep the heavier height. The purpose-built compact slots preserve the same 44-dp
 * controls inside a denser reading rhythm.
 */
private fun minimumRowHeight(slot: PosterSize): Dp = when (slot) {
    PosterSize.Queue, PosterSize.TodayQueue -> ThemeMetrics.rowStandard
    else -> ThemeMetrics.rowMedia
}
