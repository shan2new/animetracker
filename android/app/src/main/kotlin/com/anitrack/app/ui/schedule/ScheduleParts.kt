package com.anitrack.app.ui.schedule

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorProducer
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.anitrack.app.design.ContinuousCornerShape
import com.anitrack.app.design.ThemeColor
import com.anitrack.app.design.ThemeRadius
import com.anitrack.app.design.ThemeSpace
import com.anitrack.app.design.ThemeType
import com.anitrack.app.ui.art.LandscapeArt
import com.anitrack.app.ui.control.MarkRing
import com.anitrack.app.ui.control.MarkRingStyle
import com.anitrack.app.ui.control.PressStyle
import com.anitrack.app.ui.state.ReceiptLine
import com.anitrack.app.ui.state.receiptIsLive
import com.anitrack.model.Formatting
import com.anitrack.model.Franchise
import com.anitrack.model.copy.Copy
import com.anitrack.model.displayTitle
import com.anitrack.model.wideArt
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone

// =====================================================================================
// Schedule's row and its calendar — the Android mirror of `ios/.../Schedule/ScheduleParts.swift`
// (6 Sep, the second rebuild of this screen in a day).
//
// Two complaints settled it ("Lots of problem in the Schedule page", user):
//   1. "The calendar part is utterly confusing and poorly executed."
//   2. "There is no instant visual distinction between an episode that has been marked as
//      completed, not seen, and upcoming. Everything feels of the same weight."
//
// Four headers x three densities were built behind launch arguments on iOS and photographed side
// by side on the real account; the user picked the MONTH GRID behind a bar button, on COMPACT
// rows. What the photographs showed, in order of how much it mattered:
//
//   * The day rail (which Android never shipped — it still had the eight-day ticker the rail
//     itself replaced) was pointing at days the reader was not looking at: the feed sat on
//     Wednesday 2 Sep and Friday 4 Sep and NEITHER day was on the rail, both scrolled off its left
//     edge while the selected capsule said "TODAY". NN/g's eye-tracking puts ~1 % of attention past
//     the edge of a horizontal strip, and a jump list whose targets are off-screen is not a jump
//     list. It also named every day twice — in the strip, and again in the feed's own day header.
//   * A list of only the non-empty days cannot show a month's SHAPE — which weeks are busy, which
//     are spent, which are empty — by construction. The grid can, and at rest it costs nothing.
//   * At a gutter-to-gutter 16:9 card an airing plus its day header is ~305 dp, so exactly two fit
//     on a screen. A state ladder you can only see two rungs of is not a ladder.
//
// The reference apps: animeschedule.net prints day headers and pages by WEEK with no day picker;
// Fantastical's DayTicker pulls down into a month; Google Calendar's Schedule view puts the jump
// behind a month dropdown that OVERLAYS the agenda. Trakt v3 dropped its date picker entirely.
// =====================================================================================

// -------------------------------------------------------------------------------------
// The state ladder
// -------------------------------------------------------------------------------------

/**
 * The three states an airing can be in, and the ONE place they are told apart.
 *
 * What shipped put the three signals in three corners of a 249-dp card: the clock's colour at the
 * leading edge, the ring's presence at the trailing edge, a 26-dp tick on the art's top-right — and
 * "watched" was a whole-card alpha of 0.72 over a photograph on black, which is not a state, it is
 * a haze. Jellyfin's issue #706 is the same bug with better contrast: readers cannot parse states
 * that differ only in glyph at the same weight.
 *
 * The fix is a LADDER at one x-position — the trailing slot, which every airing reserves whether or
 * not it has a control, so the eye runs down one column and reads:
 *
 *  * [Upcoming] — an empty slot, and the time in accent. Nothing to do; the fact is the clock.
 *  * [ToWatch]  — the accent RING with its episode numeral. The only lit thing in the column.
 *  * [Watched]  — a settled DISC with a check, and the art dimmed a step below the ink.
 *
 * The urgency also stops being inverted: the ring, not the clock, is what the accent buys on an
 * aired row, and a watched row gives up its picture's brightness rather than a tenth of its alpha.
 */
enum class AiringState {
    Upcoming,
    ToWatch,
    Watched,
    ;

    val isWatched: Boolean get() = this == Watched
}

/** The ladder's column width — the mark ring's own 44-dp target, reserved in every state. */
private val ladderWidth = 44.dp

/**
 * The trailing column, at one width for all three states so the column exists even where it is
 * empty. An upcoming row RESERVES it rather than closing the gap, which is what let "watched" and
 * "upcoming" look identical here before.
 *
 * @param canMark the show is in the library, so there is progress to write. A catalogue row that
 *   merely airs keeps the column's width and draws nothing in it.
 */
@Composable
fun AiringStateControl(
    state: AiringState,
    episode: Int,
    committing: Boolean,
    title: String,
    batch: Boolean,
    count: Int,
    canMark: Boolean,
    onMark: () -> Unit,
) {
    Box(Modifier.width(ladderWidth), contentAlignment = Alignment.Center) {
        when {
            state == AiringState.ToWatch && canMark ->
                // `lead = true` is what makes the ring ACCENT rather than `markRingIdle`. On a
                // schedule every unwatched aired row is a next step, so every one of them leads;
                // the episode list's "one accent ring in the column" rule is about a column of
                // episodes of ONE show, which this is not.
                MarkRing(
                    marked = committing,
                    onMark = onMark,
                    style = MarkRingStyle.Quiet,
                    lead = true,
                    episode = episode,
                    label = if (batch) {
                        "Mark ${Copy.episodes(count)} of $title as watched"
                    } else {
                        "Mark ${Copy.episode(episode)} of $title as watched"
                    },
                    markedLabel = Copy.Progress.episodeWatched(episode),
                )

            state == AiringState.Watched ->
                // The receipt, kept: a disc with the check, the form the episode list settles into.
                // Not a control here — a schedule is a record, and the row's own long-press menu
                // already carries the corrections.
                MarkRing(
                    marked = true,
                    onMark = {},
                    style = MarkRingStyle.Settled,
                    episode = null,
                    enabled = false,
                    modifier = Modifier.clearForDecoration(),
                )

            else -> Spacer(Modifier.size(ladderWidth))
        }
    }
}

/** A decoration, not a control: TalkBack skips it and the row's own label carries the state. */
private fun Modifier.clearForDecoration(): Modifier =
    this.semantics(mergeDescendants = true) { }

// -------------------------------------------------------------------------------------
// The row
// -------------------------------------------------------------------------------------

private val tileWidth = 104.dp
private val tileHeight = 59.dp

/**
 * One airing: a 104x59 tile, the show, the clock and its facts, and the ladder's slot.
 *
 * The card this replaces was 16:9 gutter to gutter — two per screen, so nothing could be compared
 * with anything. This runs six deep on the same feed. The clock moves INTO the caption rather than
 * holding a column of its own: a leading time column is Apple Calendar's answer to a day with many
 * events, and measured on the test library no day in the window carries more than one. It keeps its
 * colour, which is the part that was load-bearing.
 */
@Composable
fun ScheduleAiringRow(
    franchise: Franchise,
    meta: String,
    time: String?,
    state: AiringState,
    hasReminder: Boolean,
    onOpen: () -> Unit,
    modifier: Modifier = Modifier,
    receiptHost: String? = null,
    trailing: @Composable () -> Unit = {},
) {
    // TalkBack hears the FULL title, never the shortened one.
    val spokenLabel = listOfNotNull(franchise.title, meta, time).joinToString(", ")
    val spokenValue = when {
        state.isWatched -> Copy.Accessibility.complete
        time != null && hasReminder -> "$time, ${Copy.Schedule.reminderSet}"
        time != null -> time
        else -> ""
    }

    Row(
        modifier = modifier
            .fillMaxWidth()
            // The tile is the row's floor, so a one-line row and a two-line row still read as one
            // rhythm down the column.
            .heightIn(min = tileHeight)
            .semantics(mergeDescendants = true) {
                contentDescription = spokenLabel
                if (spokenValue.isNotEmpty()) stateDescription = spokenValue
                role = Role.Button
                onClick { onOpen(); true }
            },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(ThemeSpace.x3),
    ) {
        RowTile(franchise = franchise, watched = state.isWatched, onOpen = onOpen)

        Column(
            modifier = Modifier
                .weight(1f)
                .clickable(
                    interactionSource = null,
                    indication = PressStyle.control,
                    onClick = onOpen,
                ),
            verticalArrangement = Arrangement.spacedBy(ThemeSpace.x0_5),
        ) {
            BasicText(
                text = franchise.displayTitle,
                style = ThemeType.rowTitle,
                color = ColorProducer {
                    if (state.isWatched) ThemeColor.textSecondary else ThemeColor.textPrimary
                },
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            if (receiptHost != null && receiptIsLive(receiptHost)) {
                ReceiptLine(host = receiptHost, compact = true)
            } else {
                CaptionLine(time = time, meta = meta, state = state, hasReminder = hasReminder)
            }
        }

        trailing()
    }
}

/**
 * "6:30 PM · Season 4 · Episode 16" — the clock keeps the colour it had in its own column and the
 * rest of the line is the row's meta.
 *
 * ONE annotated string, not a Row of two texts. As a row the clock held the space and the meta
 * carried `maxLines = 1`, so at the largest font scales the clock took the whole line and
 * "Season 4 · Episode 15" was squeezed out of existence — the row printed a bare time and never
 * said which episode, which is the one fact it exists to give. As one string the run wraps like
 * prose and every part survives.
 */
@Composable
private fun CaptionLine(
    time: String?,
    meta: String,
    state: AiringState,
    hasReminder: Boolean,
) {
    val clockInk = when (state) {
        AiringState.Upcoming -> ThemeColor.accent
        AiringState.ToWatch -> ThemeColor.textPrimary
        AiringState.Watched -> ThemeColor.textTertiary
    }
    val metaInk = if (state.isWatched) ThemeColor.textTertiary else ThemeColor.textSecondary
    val text: AnnotatedString = remember(time, meta, clockInk, metaInk, hasReminder) {
        buildAnnotatedString {
            if (time != null) {
                withStyle(SpanStyle(color = clockInk)) { append(time) }
                // A reminder is armed for this exact episode — passive, never a control; the row's
                // spoken value says it. A bell glyph inline would need an inline-content slot, and
                // the fact is already spoken, so the marker is a hairline bullet.
                if (hasReminder) {
                    withStyle(SpanStyle(color = ThemeColor.textTertiary)) { append(" •") }
                }
                withStyle(SpanStyle(color = ThemeColor.textTertiary)) { append(" · ") }
            }
            withStyle(SpanStyle(color = metaInk)) { append(meta) }
        }
    }
    BasicText(
        text = text,
        style = ThemeType.rowMeta,
        maxLines = 2,
        overflow = TextOverflow.Ellipsis,
    )
}

@Composable
private fun RowTile(franchise: Franchise, watched: Boolean, onOpen: () -> Unit) {
    val shape = ContinuousCornerShape(ThemeRadius.episodeStill)
    val wide = franchise.wideArt
    Box(
        Modifier
            .size(width = tileWidth, height = tileHeight)
            .clip(shape)
            .background(ThemeColor.surfaceRaised)
            .clickable(
                interactionSource = null,
                indication = PressStyle.overArt,
                onClick = onOpen,
            ),
    ) {
        LandscapeArt(
            url = wide.url,
            portraitSource = wide.portraitSource,
            maxPixel = if (wide.ultraWide) 1900 else 420,
            modifier = Modifier.fillMaxSize(),
        )
        // A watched airing gives up its PICTURE. A flat veil inside the clipped shape — never a
        // saturation or blur filter, which are per-frame passes on a scrolling list.
        if (watched) {
            Box(Modifier.fillMaxSize().background(ThemeColor.canvas.copy(alpha = 0.55f)))
        }
        Box(Modifier.fillMaxSize().border(1.dp, ThemeColor.posterEdge, shape))
    }
}

// -------------------------------------------------------------------------------------
// The calendar
// -------------------------------------------------------------------------------------

/**
 * The month grid, behind the bar's calendar button.
 *
 * At rest the screen has NO date chrome — the feed's day headers are the calendar, which is what
 * animeschedule.net and Trakt v3 do. The grid is what the reader asks for, which is where
 * Fantastical (pull the DayTicker down) and Google Calendar (the month dropdown) both put it; it is
 * a TAP here rather than a pull because this screen already owns the pull gesture for refresh.
 *
 * It OVERLAYS the feed rather than pushing it: 500 dp of grid inserted above a lazy list threw the
 * reader's place three screens down and back again on every toggle.
 *
 * **The grid only answers for days the feed actually holds.** [window] is a 22-day range; a month
 * has thirty-odd. A cell outside it used to be an ordinary target that landed on "Nothing
 * scheduled" — which is a lie, since the truth is that nothing is KNOWN about 25 September. Those
 * days are drawn quiet and are inert, and the month arrows stop at the window's own months.
 *
 * Its anatomy is Apple Calendar's, because that is the one every reader already knows: the month
 * NAMED, one numeral weight and size with TONE carrying the hierarchy, the selected day a filled
 * disc, the day's content a dot beneath it — and a hairline rule above every week row but the
 * first, because five rows of loose numerals in one field have nothing telling the eye where a week
 * ends ("a visual cue for week separation is also necessary to avoid confusion", user, 6 Sep).
 */
@Composable
fun ScheduleMonthGrid(
    todayNoon: Long,
    counts: Map<Int, Int>,
    live: Set<Int>,
    selected: Int,
    window: IntRange,
    monthAnchor: Int,
    maxHeight: Dp,
    onMonthAnchor: (Int) -> Unit,
    onPick: (Int) -> Unit,
    modifier: Modifier = Modifier,
) {
    val slots = remember(todayNoon, monthAnchor) { monthSlots(todayNoon, monthAnchor) }
    val weekRows = (slots.size + 6) / 7
    val naturalWeeks = weeksHeight(weekRows)
    // Everything above the weeks: the month row and the weekday letters, plus the panel's padding.
    val chrome = 34.dp + ThemeSpace.x2 + 18.dp + ThemeSpace.x1 + ThemeSpace.x3 * 2
    val weeksBudget = maxOf(120.dp, maxHeight - chrome)

    Column(
        modifier
            .fillMaxWidth()
            .padding(horizontal = ThemeSpace.x2, vertical = ThemeSpace.x3),
    ) {
        MonthHeader(
            todayNoon = todayNoon,
            monthAnchor = monthAnchor,
            window = window,
            onMonthAnchor = onMonthAnchor,
        )
        Spacer(Modifier.height(ThemeSpace.x2))
        Row(Modifier.fillMaxWidth()) {
            // Sunday-first: column 0 is Sunday whatever the device's locale says. Stated by the
            // app (the user's rule, 6 Sep: "the mental model for anyone in general") rather than
            // read from the calendar's `firstDayOfWeek`, which resolves to Monday in much of the
            // world. `weekdayLetterMonFirst` takes a MONDAY-first column, so Sunday is column 6.
            for (col in 0 until 7) {
                BasicText(
                    text = Formatting.weekdayLetterMonFirst((col + 6) % 7).uppercase(Locale.getDefault()),
                    style = ThemeType.caption,
                    color = ColorProducer { ThemeColor.textTertiary },
                    modifier = Modifier.weight(1f),
                )
            }
        }
        Spacer(Modifier.height(ThemeSpace.x1))
        // The weeks scroll only when they have to. A month's cells scale with the font scale, and
        // six rows at the largest scales are taller than the screen has to give — uncapped, the
        // last week and the navigation bar occupied the same points. At reading sizes the natural
        // height wins and this is an ordinary column.
        Column(
            Modifier
                .height(minOf(naturalWeeks, weeksBudget))
                .verticalScroll(rememberScrollState()),
        ) {
            for (row in 0 until weekRows) {
                if (row > 0) {
                    // THE WEEK SEPARATOR. A hairline rule above each row but the first is what
                    // every month grid on the platform draws, and it is the lightest mark that can
                    // do it — `hairline` is white at 0.055.
                    Box(
                        Modifier
                            .fillMaxWidth()
                            .padding(horizontal = ThemeSpace.x1)
                            .height(1.dp)
                            .background(ThemeColor.hairline),
                    )
                }
                Row(
                    Modifier.fillMaxWidth().padding(vertical = ThemeSpace.x1),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    for (col in 0 until 7) {
                        val i = row * 7 + col
                        val offset = slots.getOrNull(i)
                        if (offset == null) {
                            Spacer(Modifier.weight(1f).height(cellHeight))
                        } else {
                            DayCell(
                                offset = offset,
                                todayNoon = todayNoon,
                                count = counts[offset] ?: 0,
                                live = live.contains(offset),
                                selected = offset == selected,
                                known = offset in window,
                                onPick = { onPick(offset) },
                                modifier = Modifier.weight(1f),
                            )
                        }
                    }
                }
            }
        }
    }
}

/**
 * The numeral's disc. It scales with the font scale up to the column it has to live in: seven
 * columns share ~353 dp, so a cell is ~50 wide, and uncapped the disc reached ~78 at the largest
 * scales and seven of them forced the panel 180 dp wider than the screen — the arrows and both
 * weekend columns off the edges. **A grid's cell cannot be wider than a seventh of its grid,
 * whatever the text size says.**
 */
private val discSize = 34.dp
private val dotSize = 6.dp
private val cellHeight = discSize + 3.dp + dotSize

private fun weeksHeight(rows: Int): Dp =
    cellHeight * rows + ThemeSpace.x1 * 2 * rows + 1.dp * maxOf(0, rows - 1)

/** "September 2026" — the month NAMED, not an 11-sp grey eyebrow. */
@Composable
private fun MonthHeader(
    todayNoon: Long,
    monthAnchor: Int,
    window: IntRange,
    onMonthAnchor: (Int) -> Unit,
) {
    Row(
        Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        MonthArrow(
            back = true,
            target = monthOffset(todayNoon, monthAnchor, -1),
            window = window,
            todayNoon = todayNoon,
            label = Copy.Schedule.previousMonth,
            onMonthAnchor = onMonthAnchor,
        )
        BasicText(
            text = Formatting.fmtMonthNameYear(todayNoon + monthAnchor * Formatting.D),
            style = ThemeType.bodyEmphasis,
            color = ColorProducer { ThemeColor.textPrimary },
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f),
        )
        MonthArrow(
            back = false,
            target = monthOffset(todayNoon, monthAnchor, 1),
            window = window,
            todayNoon = todayNoon,
            label = Copy.Schedule.nextMonth,
            onMonthAnchor = onMonthAnchor,
        )
    }
}

/**
 * A month arrow, live only while the window reaches into the month it would show. Past the horizon
 * there is nothing to page to, and an arrow that pages to a blank month is an invitation to keep
 * pressing it.
 */
@Composable
private fun MonthArrow(
    back: Boolean,
    target: Int,
    window: IntRange,
    todayNoon: Long,
    label: String,
    onMonthAnchor: (Int) -> Unit,
) {
    val reachable = monthIntersectsWindow(todayNoon, target, window)
    Box(
        Modifier
            .size(width = 44.dp, height = 34.dp)
            .alpha(if (reachable) 1f else 0.25f)
            .clickable(
                interactionSource = null,
                indication = PressStyle.control,
                enabled = reachable,
                role = Role.Button,
                onClick = { onMonthAnchor(target) },
            )
            .semantics { contentDescription = label },
        contentAlignment = Alignment.Center,
    ) {
        BasicText(
            text = if (back) "‹" else "›",
            style = ThemeType.bodyEmphasis,
            color = ColorProducer { ThemeColor.interactive },
        )
    }
}

/**
 * One day. Apple Calendar's anatomy: the numeral in a disc that fills when the day is SELECTED,
 * today's numeral in the accent, and the day's content as a dot beneath. Every numeral is the same
 * weight and size — TONE carries the hierarchy, as it does everywhere else in the app — because a
 * grid of mixed weights reads as a grid of mistakes.
 */
@Composable
private fun DayCell(
    offset: Int,
    todayNoon: Long,
    count: Int,
    live: Boolean,
    selected: Boolean,
    known: Boolean,
    onPick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val ts = todayNoon + offset * Formatting.D
    val parts = remember(ts) { Formatting.localParts(ts) }
    val isToday = offset == 0
    val spoken = remember(ts) { Formatting.fmtFullDate(ts) }
    val value = when {
        !known -> Copy.Schedule.beyondHorizon
        count > 0 -> Copy.episodes(count)
        else -> Copy.Schedule.noEpisodes
    }
    val ink = when {
        isToday -> ThemeColor.accent
        count > 0 -> ThemeColor.textPrimary
        else -> ThemeColor.textSecondary
    }

    Column(
        modifier
            .height(cellHeight)
            .alpha(if (known) 1f else 0.4f)
            .clickable(
                interactionSource = null,
                indication = PressStyle.control,
                // Outside the feed's window there is no answer to give: the day is drawn as
                // context and does not take a tap. "Nothing scheduled" would claim knowledge the
                // app does not have.
                enabled = known,
                role = Role.Button,
                onClick = onPick,
            )
            .semantics(mergeDescendants = true) {
                contentDescription = spoken
                stateDescription = value
            },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Box(
            Modifier
                .size(discSize)
                .then(
                    if (selected) {
                        Modifier.background(ThemeColor.surfaceFloating, CircleShape)
                    } else {
                        Modifier
                    },
                ),
            contentAlignment = Alignment.Center,
        ) {
            BasicText(
                text = parts.d.toString(),
                style = ThemeType.time,
                color = ColorProducer { ink },
                maxLines = 1,
            )
        }
        Spacer(Modifier.height(3.dp))
        // The day's content: amber while something on it is still to come or still to watch, quiet
        // once it is spent, nothing at all where there is none.
        Box(
            Modifier
                .size(dotSize)
                .then(
                    if (count == 0) {
                        Modifier
                    } else {
                        Modifier.background(
                            if (live) ThemeColor.accent else ThemeColor.textTertiary,
                            CircleShape,
                        )
                    },
                ),
        )
    }
}

// -------------------------------------------------------------------------------------
// Month arithmetic
// -------------------------------------------------------------------------------------

private fun calendarAt(todayNoon: Long, offset: Int): Calendar =
    Calendar.getInstance(TimeZone.getDefault()).apply {
        timeInMillis = todayNoon + offset * Formatting.D
    }

/**
 * Offsets of the days drawn in the grid: the anchor month's days, preceded by blanks for the
 * weekdays before the 1st. Sunday-first, stated by the app.
 */
private fun monthSlots(todayNoon: Long, monthAnchor: Int): List<Int?> {
    val cal = calendarAt(todayNoon, monthAnchor)
    val days = cal.getActualMaximum(Calendar.DAY_OF_MONTH)
    val first = (cal.clone() as Calendar).apply { set(Calendar.DAY_OF_MONTH, 1) }
    // `DAY_OF_WEEK` is 1 = Sunday … 7 = Saturday, so the lead-in is that minus one.
    val lead = first.get(Calendar.DAY_OF_WEEK) - 1
    val firstOffset = monthAnchor - (cal.get(Calendar.DAY_OF_MONTH) - 1)
    return List(lead) { null } + (0 until days).map { firstOffset + it }
}

/** The offset of the same day-of-month one month away, for the header's arrows. */
private fun monthOffset(todayNoon: Long, monthAnchor: Int, step: Int): Int {
    val cal = calendarAt(todayNoon, monthAnchor)
    cal.add(Calendar.MONTH, step)
    val millis = cal.timeInMillis - todayNoon
    return Math.round(millis.toDouble() / Formatting.D.toDouble()).toInt()
}

/** Does the month containing [offset] hold any day the feed can answer for? */
private fun monthIntersectsWindow(todayNoon: Long, offset: Int, window: IntRange): Boolean {
    val cal = calendarAt(todayNoon, offset)
    val days = cal.getActualMaximum(Calendar.DAY_OF_MONTH)
    val firstOffset = offset - (cal.get(Calendar.DAY_OF_MONTH) - 1)
    return firstOffset <= window.last && firstOffset + days - 1 >= window.first
}
