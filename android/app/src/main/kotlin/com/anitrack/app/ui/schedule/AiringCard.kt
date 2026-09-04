package com.anitrack.app.ui.schedule

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.ColorProducer
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.anitrack.app.design.ContinuousCornerShape
import com.anitrack.app.design.MotionToken
import com.anitrack.app.design.PreviouslyIcons
import com.anitrack.app.design.ShadowToken
import com.anitrack.app.design.ThemeColor
import com.anitrack.app.design.ThemeMetrics
import com.anitrack.app.design.ThemeRadius
import com.anitrack.app.design.ThemeSpace
import com.anitrack.app.design.ThemeType
import com.anitrack.app.design.motion
import com.anitrack.app.design.rememberSymbol
import com.anitrack.app.design.shadowToken
import com.anitrack.app.ui.art.LandscapeArt
import com.anitrack.app.ui.control.PressStyle
import com.anitrack.app.ui.control.materialGlyphBox
import com.anitrack.app.ui.image.ArtMaxPixel
import com.anitrack.app.ui.section.OverArtLabel
import com.anitrack.model.Franchise
import com.anitrack.model.copy.Copy
import com.anitrack.model.displayTitle
import com.anitrack.model.wideArt

// =====================================================================================
// THE AIRING CARD — Schedule's row, and the only row anatomy the calendar has.
//
// Ported from `ios/Sources/Features/Schedule/ScheduleView.swift` (spec/schedule.md §12).
//
//   "One airing as television: the show's art wide, the moment as a pill on it, the episode named
//    beneath, the mark ring beside that while there is something to mark. A 60-pt poster row with
//    a clock in a column said 'list'; the calendar now reads like Apple TV's Coming Soon and
//    Netflix's New & Hot, which is what a calendar of television should look like."
//
// Two rules in this file are fixed bugs wearing a different shape, and a port that "simplifies"
// either re-introduces the bug by name:
//
//  1. **16:9 BY RATIO, gutter to gutter — never a fixed height.** "The card is gutter to gutter; a
//     height picked for one width crops the banner to a different letterbox at every other one, and
//     this one had also been drawn 16 pt in from each side of its own day header (the gutter was
//     applied twice), so the feed had two left edges." The card therefore applies NO horizontal
//     padding of its own; the feed's gutter is applied once, by the feed.
//
//  2. **Amber while the episode is still ahead — the app's one colour rule for a time — ink once it
//     has aired.** The pill is the only place on this card where amber can appear, and it is
//     MEANING (a future air time), never an action.
//
// ONE trailing column, and one rule for what is in it: the action while there is something to do,
// and nothing once there is not. The air time is ON the art now and is deliberately not repeated in
// the meta line — appended there it wrapped ("Season 5 · Episode 9 ·" / "8:30 PM", a line ending on
// a separator); inlined into a fixed column beside the ring it truncated ("…Episode 9 · 8:3…"),
// which is what the shipped row did. VoiceOver still speaks it, through this card's own value.
//
// The long-press quick actions are NOT here. They are the shared `FranchiseQuickActions`, which
// wraps the card from outside and detects the press on the Initial pointer pass precisely so the
// card's own taps are left alone — see `ScheduleScreen.CardRow`.
// =====================================================================================

/** A watched airing keeps its place on the calendar and recedes. */
private const val WATCHED_DIM = 0.72f

/** The pill, the bell and the tick are all inset this far from the art's own edges. */
private val overArtInset = ThemeSpace.x3

/** Between the pill and the reminder bell beside it. */
private val overArtGap = ThemeSpace.x2

/** The bell's glyph at its iOS point size; [materialGlyphBox] does the SF → Material conversion. */
private val bellGlyph = 11.dp

/** The bell's disc padding around that glyph. */
private val bellDiscPadding = 7.dp

/** The tick badge's disc. */
private val tickBadgeDiameter = 26.dp

/** The tick's glyph at its iOS point size. */
private val tickGlyph = 12.dp

/** The edge of artwork: `posterEdge` (white 9 %), never `stroke`. */
private val artEdgeWidth = ThemeMetrics.hairline


/**
 * One airing on the calendar.
 *
 * The card carries **two** press regions with the same action, as the shipped card does: the art
 * dips in brightness ([PressStyle.overArt] — a grey wash over someone's illustration is a film on
 * it), and the text block takes the row wash ([PressStyle.row]). The [trailing] control sits outside
 * both, so it is never swallowed by the row's target.
 *
 * @param meta the episode line — "Season 4 · Episode 21", or "Season 2 · 8 episodes" for a
 *   same-day date-only drop. Built by the feed, because only the feed knows whether several
 *   episodes collapsed into this row.
 * @param time the clock, or `null` for a date-only source. `Formatting.fmtTime` returns "" for a
 *   date-only anchor, so a TMDB row can never invent one; the caller passes `null` explicitly.
 * @param aired the moment has passed. **This is the pill's colour rule** — amber ahead, ink behind.
 * @param watched dims the whole card and puts a tick on the art. A finished thing is a tick, not
 *   the word "Watched".
 * @param dateOnly the source publishes a date and no clock. With no [time] the pill says what the
 *   drop is ("New episode") instead of inventing a clock.
 * @param hasReminder a local episode alert is armed for this exact episode. **Passive, never a
 *   control** — there is no tap target on the bell; it is spoken through the card's own value.
 * @param trailing the mark ring, while there is something to mark. Empty otherwise.
 */
@Composable
fun AiringCard(
    franchise: Franchise,
    meta: String,
    time: String?,
    aired: Boolean,
    watched: Boolean,
    dateOnly: Boolean,
    hasReminder: Boolean,
    onOpen: () -> Unit,
    modifier: Modifier = Modifier,
    trailing: @Composable () -> Unit = {},
) {
    // "'7:30 PM' for a timed slot; a date-only drop says what it is instead of inventing a clock."
    val pill = time ?: if (dateOnly) Copy.Label.newEpisode else null

    // Animated in a layer, never in the body: the mark's commit dims the card, and a dim that
    // recomposed the row would recompose it once per animation frame for a value only the
    // compositor needs.
    val dim = animateFloatAsState(
        targetValue = if (watched) WATCHED_DIM else 1f,
        animationSpec = motion(MotionToken.UI_MICRO),
        label = "airingCardDim",
    )

    // VoiceOver hears the FULL title, never the shortened one.
    val spokenLabel = listOfNotNull(franchise.title, meta, pill).joinToString(", ")
    val spokenValue = when {
        watched -> Copy.Accessibility.complete
        time != null && hasReminder -> "$time, ${Copy.Schedule.reminderSet}"
        time != null -> time
        else -> ""
    }

    Column(
        modifier = modifier
            .fillMaxWidth()
            .graphicsLayer { alpha = dim.value }
            // One spoken element for the card, exactly as iOS's `children: .contain`: the two press
            // regions merge into it, while `trailing`'s mark ring sets `mergeDescendants` itself and
            // therefore stays its own node. The action must not be swallowed by the row's label.
            .semantics(mergeDescendants = true) {
                contentDescription = spokenLabel
                if (spokenValue.isNotEmpty()) stateDescription = spokenValue
                role = Role.Button
                onClick { onOpen(); true }
            },
        verticalArrangement = Arrangement.spacedBy(ThemeSpace.x2),
    ) {
        CardArt(
            franchise = franchise,
            pill = pill,
            aired = aired,
            watched = watched,
            hasReminder = hasReminder,
            onOpen = onOpen,
        )

        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(ThemeSpace.x3),
        ) {
            Column(
                modifier = Modifier
                    .weight(1f)
                    .clickable(
                        interactionSource = null,
                        indication = PressStyle.row(ThemeRadius.row),
                        role = Role.Button,
                        onClick = onOpen,
                    ),
                verticalArrangement = Arrangement.spacedBy(ThemeSpace.x0_5),
            ) {
                // `displayTitle`, as every row and shelf in the app draws it — the raw `title` is
                // kept for the spoken label above, which always speaks the whole thing.
                BasicText(
                    text = franchise.displayTitle,
                    style = ThemeType.rowTitle,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                    color = ColorProducer { ThemeColor.textPrimary },
                )
                BasicText(
                    text = meta,
                    style = ThemeType.rowMeta,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    color = ColorProducer { ThemeColor.textSecondary },
                )
            }
            trailing()
        }
    }
}

/**
 * The art layer: the show's banner gutter to gutter, the moment as a pill on it, a tick once the
 * episode is watched.
 *
 * The ground is `surfaceRaised` under the picture, the edge is `posterEdge` all the way round (the
 * one full ring a photograph is allowed), and the shadow is `ShadowToken.Art` — a poster sits close
 * to what it rests on. The shadow's silhouette is a plain `RoundedCornerShape` while the content is
 * clipped to the squircle: a generic path casts no platform shadow below API 29 and the difference
 * is invisible once blurred.
 */
@Composable
private fun CardArt(
    franchise: Franchise,
    pill: String?,
    aired: Boolean,
    watched: Boolean,
    hasReminder: Boolean,
    onOpen: () -> Unit,
) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            // BY RATIO. A fixed height crops the banner to a different letterbox at every width.
            .aspectRatio(ThemeMetrics.wideAspect)
            .clickable(
                interactionSource = null,
                // A target that IS a photograph dips in brightness; it never takes a grey wash.
                indication = PressStyle.overArt,
                role = Role.Button,
                onClick = onOpen,
            )
            .shadowToken(ShadowToken.Art, RoundedCornerShape(ThemeRadius.card))
            .clip(ContinuousCornerShape(ThemeRadius.card))
            .background(ThemeColor.surfaceRaised),
    ) {
        // `wideArt`, never `banner ?: cover`: a landscape frame never fills a portrait cover, and
        // the model has already decided which of the two this is.
        LandscapeArt(
            art = franchise.wideArt,
            maxPixel = ArtMaxPixel.AIRING_CARD,
            modifier = Modifier.fillMaxSize(),
        )

        if (pill != null) {
            Row(
                modifier = Modifier
                    .align(Alignment.BottomStart)
                    .padding(overArtInset),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(overArtGap),
            ) {
                // THE colour rule: amber while the episode is still ahead, ink once it has aired.
                OverArtLabel(
                    text = pill,
                    tint = if (aired) ThemeColor.textPrimary else ThemeColor.accent,
                )
                if (hasReminder) ReminderBell()
            }
        }

        if (watched) {
            TickBadge(
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(overArtInset),
            )
        }

        // Drawn last so it strokes the picture rather than sitting under it — the Compose reading of
        // iOS's `.overlay(shape.strokeBorder(...))`. `border` insets its stroke, as `strokeBorder`
        // does; a centred line on a 22-dp squircle renders as a soft smear outside the shape.
        Box(
            Modifier
                .matchParentSize()
                .border(artEdgeWidth, ThemeColor.posterEdge, ContinuousCornerShape(ThemeRadius.card)),
        )
    }
}

/**
 * "A reminder is armed for this exact episode."
 *
 * **Passive, never a control.** It reports that a local notification exists and has no tap target;
 * the fact reaches a screen reader through the card's own value (", reminder set"), which is why the
 * glyph is cleared out of the semantics tree entirely.
 *
 * The ink is `textPrimary`, not amber. `spec/icon-mapping.md` row 6 editorialises the filled bell as
 * "amber = STATE"; the shipped card draws `.foregroundStyle(ThemeColor.textPrimary)` and the code
 * wins. Amber on this card is spent on the pill, and one card may not say "this is ahead" twice.
 */
@Composable
private fun ReminderBell() {
    Image(
        imageVector = rememberSymbol(PreviouslyIcons.NotificationsFilled),
        contentDescription = null,
        modifier = Modifier
            .clip(CircleShape)
            .background(ThemeColor.scrimStrong)
            .padding(bellDiscPadding)
            .size(materialGlyphBox(bellGlyph))
            .clearAndSetSemantics {},
        colorFilter = ColorFilter.tint(ThemeColor.textPrimary),
    )
}

/** "A watched episode wears its tick on the art, as Detail's films do." */
@Composable
private fun TickBadge(modifier: Modifier = Modifier) {
    Box(
        modifier = modifier
            .size(tickBadgeDiameter)
            .clip(CircleShape)
            .background(ThemeColor.scrimStrong)
            .border(artEdgeWidth, ThemeColor.hairline, CircleShape)
            // The card's own label already says "Complete"; a tick spoken twice is noise.
            .clearAndSetSemantics {},
        contentAlignment = Alignment.Center,
    ) {
        Image(
            imageVector = rememberSymbol(PreviouslyIcons.Check),
            contentDescription = null,
            modifier = Modifier.size(materialGlyphBox(tickGlyph)),
            colorFilter = ColorFilter.tint(ThemeColor.textPrimary),
        )
    }
}
