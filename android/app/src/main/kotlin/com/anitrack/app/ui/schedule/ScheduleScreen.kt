package com.anitrack.app.ui.schedule

import android.app.Activity
import android.content.ContentResolver
import android.content.Context
import android.content.ContextWrapper
import android.database.ContentObserver
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.VisibilityThreshold
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.DragInteraction
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.ColorProducer
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import com.anitrack.app.AppModel
import com.anitrack.app.BuildConfig
import com.anitrack.app.MediaFilter
import com.anitrack.app.ScheduleDay
import com.anitrack.app.ScheduleEntry
import com.anitrack.app.data.SyncCenter
import com.anitrack.app.design.ContinuousCornerShape
import com.anitrack.app.design.FeedbackCoordinator
import com.anitrack.app.design.FeedbackToken
import com.anitrack.app.design.LocalReduceMotion
import com.anitrack.app.design.MotionToken
import com.anitrack.app.design.PreviouslyIcons
import com.anitrack.app.design.PreviouslyMaterialBridge
import com.anitrack.app.design.ShadowToken
import com.anitrack.app.design.ThemeColor
import com.anitrack.app.design.ThemeMetrics
import com.anitrack.app.design.ThemeMotion
import com.anitrack.app.design.ThemeRadius
import com.anitrack.app.design.ThemeSpace
import com.anitrack.app.design.ThemeType
import com.anitrack.app.design.motion
import com.anitrack.app.design.rememberSymbol
import com.anitrack.app.ui.AutoSizeText
import com.anitrack.app.ui.art.ArtBackdrop
import com.anitrack.app.ui.chrome.ChromeEdge
import com.anitrack.app.ui.chrome.ScrollEdgeChromeBox
import com.anitrack.app.ui.chrome.chromeHazeSource
import com.anitrack.app.ui.chrome.tabBarContentPadding
import com.anitrack.app.ui.control.FilterChip
import com.anitrack.app.ui.control.MarkRing
import com.anitrack.app.ui.control.MarkRingStyle
import com.anitrack.app.ui.control.PressStyle
import com.anitrack.app.ui.control.TertiaryButton
import com.anitrack.app.ui.control.materialGlyphBox
import com.anitrack.app.ui.control.minimumTapTarget
import com.anitrack.app.ui.isAccessibilityTextSize
import com.anitrack.app.ui.library.FranchiseQuickActions
import com.anitrack.app.ui.library.InlineChromeBar
import com.anitrack.app.ui.library.PreviouslyPullToRefresh
import com.anitrack.app.ui.section.SectionLabel
import com.anitrack.app.ui.state.EmptyState
import com.anitrack.app.ui.state.InlineNotice
import com.anitrack.app.ui.state.SkeletonBlock
import com.anitrack.app.ui.state.SkeletonGate
import com.anitrack.app.ui.state.SkeletonLine
import com.anitrack.app.ui.state.StaleStrip
import com.anitrack.app.ui.state.centredState
import com.anitrack.model.Formatting
import com.anitrack.model.Franchise
import com.anitrack.model.FranchisePart
import com.anitrack.model.MediaSource
import com.anitrack.model.canonicalLabel
import com.anitrack.model.copy.Copy
import com.anitrack.model.copy.CopyDates
import com.anitrack.model.copy.EmptyStateCopy
import com.anitrack.model.portraitArt
import com.anitrack.model.timeAnchor
import com.anitrack.model.watchContext
import java.time.Month
import java.util.Locale
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.launch

// =====================================================================================
// SCHEDULE — the agenda.
//
// The port of `ios/Sources/Features/Schedule/ScheduleView.swift` (spec/schedule.md).
//
// One vertical list, one section per day, a ticker across the top spanning exactly the window the
// feed holds (a week back, two weeks ahead), and rows that are 16:9 art cards rather than poster
// rows. THREE rules in this file are load-bearing product decisions, each arrived at by fixing a
// shipped bug, and a port that "simplifies" any of them re-introduces the bug by name:
//
//  1. **Today's section is always drawn, empty or not.** An agenda that skips an empty today opens
//     on a future day, and its top row's bare clock reads as tonight's. The empty today states so
//     in its header's COUNT SLOT — not as a 44-dp row under the header: "the agenda used to open on
//     the ticker, the Earlier row, a 'Today' header, one grey line and a 'Tomorrow' header before
//     its first card". The row exists only at accessibility sizes, where a sentence cannot fit
//     beside the date.
//
//  2. **"Today" always means DAY 0**, never "the first day that carries something". There is
//     deliberately no "landing day": the one this used to compute was the first NON-EMPTY day >= 0,
//     and `awayFromToday` then treated that as a synonym for today — so on a quiet day the agenda
//     opened on a future day and the "Today" button hid itself (`selectedDay == landing`, so by its
//     own test you were already there).
//
//  3. **Amber means TODAY here, not selection.** This screen is the app's one deliberate exception
//     to "amber selection is legal STATE": amber is already spent on the current day in this
//     control, so the selected cell gets a neutral `surfaceRaised` disc. Calendar's own grammar —
//     today is the filled disc, the selected day a quiet one.
//
// Two further rules the port must not undo:
//
//  * **No pinned header, no ground under a day header, no rule.** "A pinned header has to occlude
//    the rows passing under it, which means an opaque full-bleed plate — and that plate's top edge
//    cut the wash in a hard horizontal step across the screen, the exact seam the shared chrome
//    exists to remove."
//  * **A day with nothing on it is not a target and does not look like one.** "Every cell used to
//    wear the same white, and a tap on '5' that did nothing read as a broken control rather than as
//    an empty Saturday."
//
// -------------------------------------------------------------------------------------
// WHAT IS ANDROID'S AND NOT iOS'S
//
//  * iOS's `DerivedBox` — a reference cache held in `@State` so filling it during a `body` read
//    does not invalidate the view — **disappears**. `remember(feedKey, typeFilter, unwatchedOnly)`
//    is the same memo with none of the hazard.
//  * `onScrollTargetVisibilityChange(idType:threshold:)` has no Compose equivalent. It is rebuilt
//    from `LazyListState.layoutInfo.visibleItemsInfo` behind a `snapshotFlow`, with the same 20 %
//    visibility predicate and the same "earliest visible day wins" rule.
//  * The chrome band is REAL LAYOUT — a `Column { band; feed }` rather than a safe-area inset — so
//    the feed sits under it by construction. Only the BOTTOM scroll edge is drawn; the top edge
//    belongs to the band, whose ground *is* the wash.
//  * The programmatic feed scrolls animate on `LazyListState.animateScrollToItem`'s own curve rather
//    than `uiReveal`: Compose's lazy scroll animation takes no `AnimationSpec`, and hand-rolling one
//    over `scrollBy` would be exactly the machinery the fidelity line forbids.
// =====================================================================================

// -------------------------------------------------------------------------------------
// Reminders — the read-only mirror behind the card's bell
// -------------------------------------------------------------------------------------

/**
 * Which episodes have a pending local reminder. **Read-only: the bell is passive, never a control.**
 *
 * iOS asks `UNUserNotificationCenter.pendingNotificationRequests()` directly. Android has no
 * equivalent read of pending `AlarmManager` / `WorkManager` alerts, so the scheduler persists the
 * armed set when it arms it and installs a reader here. The identifier shape is kept **identical**
 * to iOS's — `episode-<mediaId>-<episode>` — so one alert scheduler can be checked against both.
 *
 * With no [source] installed the set is empty and no bells are drawn, which is exactly the shipped
 * behaviour when notification permission has never been granted.
 *
 * The scheduler arms three alerts per *watching* AniList show, so the bell can only ever appear on
 * an anime row, on one of that show's next three unaired episodes.
 */
object ScheduleReminders {

    /**
     * Installed by `AppGraph.create` from `EpisodeNotifications.armedAlertTags` — the alerts this
     * account is owed **and** this device will actually post. Null only in a unit test, where the
     * set is empty and no bell is drawn.
     */
    @Volatile
    var source: (suspend () -> Set<String>)? = null

    var pending: Set<String> by mutableStateOf(emptySet())
        private set

    fun identifier(mediaId: Int, episode: Int): String = "episode-$mediaId-$episode"

    fun has(mediaId: Int, episode: Int): Boolean = pending.contains(identifier(mediaId, episode))

    /** Refreshed once per appearance of the screen. There is no other call site in the app. */
    suspend fun refresh() {
        pending = source?.invoke().orEmpty()
    }
}

// -------------------------------------------------------------------------------------
// Debug launch state
// -------------------------------------------------------------------------------------

/**
 * The three iOS launch arguments this screen answers to, as intent extras, so one capture script
 * drives both platforms.
 *
 * | iOS | here |
 * | --- | --- |
 * | `-scheduleEarlier 1` | `--ez scheduleEarlier true` — the Earlier block opens already unfolded |
 * | `-scheduleFilter anime\|tv` | `--es scheduleFilter anime` — anything else is `ALL` |
 * | `-scheduleHideWatched 1` | `--ez scheduleHideWatched true` |
 *
 * Read once, at first composition, exactly as iOS reads its `#if DEBUG` static initialisers. In a
 * release build [BuildConfig.DEBUG] is a compile-time `false`, so R8 removes the branch and the
 * screen starts on the plain defaults.
 */
@Immutable
data class ScheduleDebugState(
    val earlierExpanded: Boolean = false,
    val typeFilter: MediaFilter = MediaFilter.ALL,
    val hideWatched: Boolean = false,
)

/** `--ez` gives a real boolean; `--es` is accepted too so one capture script can use either. */
private val TRUTHY_EXTRA_VALUES = setOf("1", "true")

@Composable
private fun rememberScheduleDebugState(): ScheduleDebugState {
    val context = LocalContext.current
    return remember(context) {
        if (!BuildConfig.DEBUG) return@remember ScheduleDebugState()
        val intent = context.findActivity()?.intent ?: return@remember ScheduleDebugState()
        fun flag(name: String): Boolean =
            intent.getBooleanExtra(name, false) ||
                TRUTHY_EXTRA_VALUES.contains(intent.getStringExtra(name).orEmpty())
        ScheduleDebugState(
            earlierExpanded = flag("scheduleEarlier"),
            typeFilter = when (intent.getStringExtra("scheduleFilter")) {
                "anime" -> MediaFilter.ANIME
                "tv" -> MediaFilter.TV
                else -> MediaFilter.ALL
            },
            hideWatched = flag("scheduleHideWatched"),
        )
    }
}

/** The hosting activity, for the debug intent extras. `null` in a preview or a test harness. */
private fun Context.findActivity(): Activity? {
    var ctx: Context? = this
    while (ctx is ContextWrapper) {
        if (ctx is Activity) return ctx
        ctx = ctx.baseContext
    }
    return ctx as? Activity
}

// -------------------------------------------------------------------------------------
// Screen-local geometry
// -------------------------------------------------------------------------------------

/** Nothing here is a token candidate: every value belongs to this screen and to nothing else. */
private object ScheduleMetrics {

    /**
     * "Seven and a bit fit the width, which is what says 'this scrolls'." — which is the app's
     * minimum target, not a coincidence: [minimumTapTarget], never a second spelling of 44.
     */
    val cellWidth = minimumTapTarget

    val cellGap = 6.dp

    /** The ticker numeral's minimum box — and its disc's diameter. */
    val numeralMin = 34.dp

    /** Between two cards on one day. */
    val cardGap = ThemeSpace.x5

    /** Inside a ticker cell, between the weekday letter, the numeral and the dot. */
    val cellStack = 3.dp

    /**
     * The "something airs here" dot's base size. Scaled by `fontScale` at the call site, which is
     * the Android reading of iOS's `@ScaledMetric(relativeTo: .caption)`.
     */
    val dot = 5.dp

    /**
     * How many cells the ticker shows. A constant, not a measurement: 44 + 6 per cell over a 393-dp
     * screen with 16-dp gutters gives 7.2 cells, "which is what says 'this scrolls'".
     */
    const val TICKER_VISIBLE = 7

    /** The past recedes as a group — never the selected cell. */
    const val PAST_DIM = 0.55f

    /** A target counts as visible once this much of it is on screen. iOS: `threshold: 0.2`. */
    const val VISIBILITY_THRESHOLD = 0.2f

    /**
     * The Earlier row's chevron, at its iOS point size. "12 semibold — a step lighter than the
     * section header's 14, beside an 11-pt label rather than a 20-pt title."
     */
    val earlierChevron = 12.dp

    /** The bar's filter glyph, at its iOS point size. */
    val filterGlyph = 17.dp

    /**
     * The active filter glyph's `accentSoft` disc. Material has no circled-filter glyph to answer
     * SF's `line.3.horizontal.decrease.circle.fill`, and the app already owns the disc primitive.
     */
    val filterDisc = 30.dp

    /** The inner gap between the day word and its date, and between the Earlier label and its meta. */
    val labelInnerGap = 5.dp


    /** iOS `.minimumScaleFactor(0.7)` on the ticker numeral. */
    const val NUMERAL_MIN_SCALE = 0.7f

    /** With Hide watched on, the departure is held long enough to be legible, not instantaneous. */
    const val HIDE_WATCHED_HOLD_MILLIS = 650L
}

// -------------------------------------------------------------------------------------
// Screen-local derivation
// -------------------------------------------------------------------------------------

/**
 * One line on the calendar.
 *
 * A **date-only** part that drops several episodes on one day collapses into ONE row spanning
 * `min…max` of the episode numbers ("Season 2 · 8 episodes"), not eight identical ones.
 */
@Immutable
private data class ScheduleRow(
    val franchise: Franchise,
    val part: FranchisePart,
    val episodes: IntRange,
    val at: Long,
    val aired: Boolean,
    val dateOnly: Boolean,
) {
    val episode: Int get() = episodes.last
    val id: String get() = "${franchise.id}/${part.mediaId}/$episode"
    val watched: Boolean get() = aired && part.progress >= episode
}

/** The screen's own view of a feed day. */
@Immutable
private data class DayView(val id: Int, val noon: Long, val rows: List<ScheduleRow>) {
    val isToday: Boolean get() = id == 0
    val isEmpty: Boolean get() = rows.isEmpty()
    val count: Int get() = rows.size
}

/** Everything computed once per (feed, filter). */
@Immutable
private data class Derived(
    val earlier: List<DayView> = emptyList(),
    val ahead: List<DayView> = emptyList(),
    /** Today is empty **after** filtering but was not before it. */
    val todayFiltered: Boolean = false,
    val counts: Map<Int, Int> = emptyMap(),
    /** Day ids where at least one shown row is unwatched. */
    val live: Set<Int> = emptySet(),
    val earlierCount: Int = 0,
    val earlierUnwatched: Int = 0,
    /**
     * The **last day in the raw feed** — the furthest offset that actually carries something, or 0.
     * NOT a flat +14: on a library whose furthest dated episode is nine days out, the tail line
     * names the ninth day.
     */
    val horizonId: Int? = null,
    val allEmpty: Boolean = true,
    val shownEmpty: Boolean = true,
    /** The animation and landing trigger. */
    val feedKey: List<Int> = emptyList(),
    val washCover: String? = null,
)

/**
 * A day's entries as rows.
 *
 * The merge map is populated **only for a date-only entry**, which is what confines the collapse to
 * a same-day season drop; every timed entry is one row each. The merged row keeps the FIRST entry's
 * instant, aired flag, franchise and part.
 */
private fun rowsFor(day: ScheduleDay): List<ScheduleRow> {
    val out = ArrayList<ScheduleRow>(day.entries.size)
    val merged = HashMap<Int, Int>()
    for (e: ScheduleEntry in day.entries) {
        val at = merged[e.part.mediaId]
        if (at != null) {
            val cur = out[at]
            out[at] = cur.copy(
                episodes = minOf(cur.episodes.first, e.episode)..maxOf(cur.episodes.last, e.episode),
            )
            continue
        }
        out.add(
            ScheduleRow(
                franchise = e.franchise,
                part = e.part,
                episodes = e.episode..e.episode,
                at = e.at,
                aired = e.aired,
                dateOnly = e.dateOnly,
            ),
        )
        if (e.dateOnly) merged[e.part.mediaId] = out.size - 1
    }
    return out
}

private fun computeDerived(
    days: List<ScheduleDay>,
    library: List<Franchise>,
    typeFilter: MediaFilter,
    unwatchedOnly: Boolean,
): Derived {
    val all = days.map { DayView(id = it.id, noon = it.noon, rows = rowsFor(it)) }

    fun passes(r: ScheduleRow): Boolean {
        when (typeFilter) {
            MediaFilter.ALL -> Unit
            MediaFilter.ANIME -> if (r.franchise.source != MediaSource.ANILIST) return false
            MediaFilter.TV -> if (r.franchise.source != MediaSource.TMDB) return false
        }
        if (unwatchedOnly && r.watched) return false
        return true
    }

    val shown = all.map { it.copy(rows = it.rows.filter(::passes)) }
    val earlier = shown.filter { it.id < 0 && !it.isEmpty }
    // `|| it.id == 0`: today survives its own emptiness. `AppModel.buildScheduleDays` keeps an empty
    // today in the feed on purpose, as the anchor; dropping it here threw that away.
    val ahead = shown.filter { it.id >= 0 && (!it.isEmpty || it.id == 0) }

    val todayShown = shown.firstOrNull { it.isToday }
    val todayAll = all.firstOrNull { it.isToday }
    val todayFiltered = todayShown != null && todayShown.isEmpty && todayAll?.isEmpty == false

    // "`first(where:)`, not `first`: today leads `ahead` even when it is empty, and an empty day
    // would otherwise hand the wash to the LAST thing that aired instead of the next."
    val washCover = ahead.firstOrNull { !it.isEmpty }?.rows?.firstOrNull()?.franchise?.portraitArt
        ?: earlier.lastOrNull()?.rows?.lastOrNull()?.franchise?.portraitArt
        ?: library.firstOrNull()?.portraitArt

    return Derived(
        earlier = earlier,
        ahead = ahead,
        todayFiltered = todayFiltered,
        counts = shown.associate { it.id to it.count },
        live = shown.filter { d -> d.rows.any { !it.watched } }.mapTo(HashSet()) { it.id },
        earlierCount = earlier.sumOf { it.count },
        earlierUnwatched = earlier.sumOf { d -> d.rows.count { !it.watched } },
        horizonId = days.lastOrNull()?.id,
        allEmpty = all.all { it.isEmpty },
        shownEmpty = shown.all { it.isEmpty },
        feedKey = (earlier + ahead).map { it.id * 1000 + it.count },
        washCover = washCover,
    )
}

// -------------------------------------------------------------------------------------
// Scroll identity
// -------------------------------------------------------------------------------------
//
// iOS models this as a `Hashable` enum (`AgendaID`). A `LazyColumn` key must survive
// `rememberSaveable`'s default saver, so the same identity is carried as a prefixed string and
// mapped back with `dayOf`. `.earlier` deliberately reports NO day: "Only the Earlier row on screen
// means today is next under it."

private const val KEY_EARLIER = "earlier"
private const val PREFIX_DAY = "day:"
private const val PREFIX_EMPTY_DAY = "empty:"
private const val PREFIX_ROW = "row:"

/** Whether this key is one of the agenda targets the ticker follows. */
private fun isAgendaKey(key: String): Boolean =
    key == KEY_EARLIER ||
        key.startsWith(PREFIX_DAY) ||
        key.startsWith(PREFIX_EMPTY_DAY) ||
        key.startsWith(PREFIX_ROW)

/** The day an agenda key belongs to; `null` for the Earlier row and for anything that is not one. */
private fun dayOf(key: String): Int? = when {
    key.startsWith(PREFIX_DAY) -> key.removePrefix(PREFIX_DAY).toIntOrNull()
    key.startsWith(PREFIX_EMPTY_DAY) -> key.removePrefix(PREFIX_EMPTY_DAY).toIntOrNull()
    // "row:<day>:<rowId>", and a row id contains slashes but never a colon.
    key.startsWith(PREFIX_ROW) -> key.removePrefix(PREFIX_ROW).substringBefore(':').toIntOrNull()
    else -> null
}

// -------------------------------------------------------------------------------------
// The feed, as one flat list
// -------------------------------------------------------------------------------------
//
// One list, one renderer: every scroll target's index is then an `indexOf` rather than an arithmetic
// guess that has to be kept in step with the branches above it.

/** What a whole-screen state's single button does. Kept out of the item so the list stays equatable. */
private enum class WholeAction { NONE, RETRY, ADD_SHOW, CLEAR_FILTERS }

private sealed interface FeedItem {
    val key: String

    data object Skeleton : FeedItem {
        override val key: String = "skeleton"
    }

    /**
     * A whole-screen state. The words are `state`, never `copy`: a data-class component called
     * `copy` shadows the one every reader expects `.copy(...)` to be.
     */
    data class Whole(val state: EmptyStateCopy, val action: WholeAction) : FeedItem {
        override val key: String = "state"
    }

    /** At most one freshness line: the section failure, else the stale strip. */
    data object Freshness : FeedItem {
        override val key: String = "freshness"
    }

    data object EarlierRow : FeedItem {
        override val key: String = KEY_EARLIER
    }

    data class DayHeader(val day: DayView) : FeedItem {
        override val key: String = "$PREFIX_DAY${day.id}"
    }

    /** Only today can be empty, and only at accessibility sizes does it get a row of its own. */
    data class EmptyDay(val day: DayView) : FeedItem {
        override val key: String = "$PREFIX_EMPTY_DAY${day.id}"
    }

    data class Card(val dayId: Int, val row: ScheduleRow, val last: Boolean) : FeedItem {
        override val key: String = "$PREFIX_ROW$dayId:${row.id}"
    }

    data object Tail : FeedItem {
        override val key: String = "tail"
    }
}

/** The four conditions the whole surface can be in. Mirrors `AppModel.surfacePhase`'s shape. */
private enum class SchedulePhase { LOADING, ERROR_NO_CACHE, EMPTY_ACCOUNT, CONTENT }

private fun buildFeed(
    derived: Derived,
    phase: SchedulePhase,
    online: Boolean,
    hasFreshness: Boolean,
    earlierExpanded: Boolean,
    isAX: Boolean,
    filterActive: Boolean,
): List<FeedItem> {
    when (phase) {
        SchedulePhase.LOADING -> return listOf(FeedItem.Skeleton)
        // The choice between "server" and "offline" is made by the network monitor, never guessed
        // from the error.
        SchedulePhase.ERROR_NO_CACHE -> return listOf(
            FeedItem.Whole(
                state = if (online) Copy.Empty.serverNoCache else Copy.Empty.offlineNoData,
                action = WholeAction.RETRY,
            ),
        )
        SchedulePhase.EMPTY_ACCOUNT -> return listOf(
            FeedItem.Whole(state = EmptyStateCopy.emptySchedule, action = WholeAction.ADD_SHOW),
        )
        SchedulePhase.CONTENT -> Unit
    }

    val out = ArrayList<FeedItem>(32)
    if (hasFreshness) out.add(FeedItem.Freshness)

    if (derived.allEmpty) {
        // Not an error and not an empty account: a stocked library with no dated episodes. No button.
        out.add(FeedItem.Whole(state = Copy.Empty.nothingScheduled, action = WholeAction.NONE))
        return out
    }
    if (derived.shownEmpty && filterActive) {
        out.add(FeedItem.Whole(state = Copy.Empty.noFilterMatches, action = WholeAction.CLEAR_FILTERS))
        return out
    }

    if (derived.earlier.isNotEmpty()) {
        out.add(FeedItem.EarlierRow)
        if (earlierExpanded) {
            for (day in derived.earlier) {
                out.add(FeedItem.DayHeader(day))
                day.rows.forEachIndexed { i, r ->
                    out.add(FeedItem.Card(day.id, r, last = i == day.rows.lastIndex))
                }
            }
        }
    }

    for (day in derived.ahead) {
        out.add(FeedItem.DayHeader(day))
        if (day.isEmpty) {
            // At reading sizes the statement lives in the header's count slot, on its own baseline.
            if (isAX) out.add(FeedItem.EmptyDay(day))
        } else {
            day.rows.forEachIndexed { i, r ->
                out.add(FeedItem.Card(day.id, r, last = i == day.rows.lastIndex))
            }
        }
    }
    out.add(FeedItem.Tail)
    return out
}

// -------------------------------------------------------------------------------------
// The batch-mark confirmation
// -------------------------------------------------------------------------------------

/** The one confirmation this screen raises. Every field is copy; nothing is assembled at render. */
@Immutable
private data class WritePrompt(
    val title: String,
    val message: String,
    val confirm: String,
    val perform: () -> Unit,
)

// -------------------------------------------------------------------------------------
// The screen
// -------------------------------------------------------------------------------------

/**
 * The Schedule tab's root.
 *
 * @param dates the copy table's five date facts. `:model` is pure Kotlin and the 24-hour clock
 *   setting is only readable through a `Context`, so the seam is passed in rather than imported —
 *   the same shape `LibraryScreen` takes.
 * @param onOpenDetail pushes the show onto the Schedule tab's own back stack, focused on the episode
 *   the row names — the Compose reading of iOS's `EpisodeFocus(mediaId:episode:)`. Detail is a plain
 *   push; the `.zoom` transition was tried and retired.
 * @param onAddShow reached only from the empty-account state's "Add a show" button: it requests the
 *   search field and switches to the Discover tab.
 */
@Composable
fun ScheduleScreen(
    appModel: AppModel,
    dates: CopyDates,
    onOpenDetail: (franchiseId: String, mediaId: Int, episode: Int) -> Unit,
    onAddShow: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val debug = rememberScheduleDebugState()
    val scope = rememberCoroutineScope()
    val reduceMotion = LocalReduceMotion.current
    val isAX = isAccessibilityTextSize()

    var typeFilter by rememberSaveable { mutableStateOf(debug.typeFilter) }
    var unwatchedOnly by rememberSaveable { mutableStateOf(debug.hideWatched) }
    var earlierExpanded by rememberSaveable { mutableStateOf(debug.earlierExpanded) }
    /** Row ids whose mark is animating. */
    var committed by remember { mutableStateOf(emptySet<String>()) }
    var prompt by remember { mutableStateOf<WritePrompt?>(null) }
    /** The day at the top of the feed — what the ticker highlights. Never a scroll offset. */
    var selectedDay by rememberSaveable { mutableStateOf(0) }
    /** Once a finger has moved the feed, the landing stops correcting. */
    var userScrolled by remember { mutableStateOf(false) }

    val listState = rememberLazyListState()
    // Hoisted above the ticker on purpose: the ticker COLLAPSES out of the tree with the rest of the
    // chrome when a whole-screen state settles, and iOS's rule — "collapse by height, never by a
    // conditional: taking a scroll view out of the tree and putting it back re-creates it, and a
    // re-created `.scrollPosition(id:)` does not re-apply" — is answered here rather than by keeping
    // an invisible scroll container mounted and measuring.
    val tickerState = rememberLazyListState()

    val filterActive = typeFilter != MediaFilter.ALL || unwatchedOnly
    val now = appModel.nowMinute

    // The whole of iOS's `DerivedBox` hazard, gone: the feed only changes when the library changes
    // or the minute turns, and both are in `scheduleFeedKey`.
    val feedKey = appModel.scheduleFeedKey
    val days = appModel.scheduleDays
    val library = appModel.library
    val derived = remember(feedKey, typeFilter, unwatchedOnly) {
        computeDerived(days, library, typeFilter, unwatchedOnly)
    }

    val phase = when {
        appModel.loading && library.isEmpty() -> SchedulePhase.LOADING
        appModel.loadError && appModel.libraryEmpty -> SchedulePhase.ERROR_NO_CACHE
        appModel.libraryEmpty -> SchedulePhase.EMPTY_ACCOUNT
        else -> SchedulePhase.CONTENT
    }

    val showsWholeScreenState = phase != SchedulePhase.CONTENT ||
        derived.allEmpty ||
        (derived.shownEmpty && filterActive)

    // "The day strip stays up while the first library loads — its days come from the clock, not the
    // data — so the feed lands under it instead of shoving everything down 60 dp the instant the
    // response arrives. Only a settled whole-screen state folds it away, animated."
    val tickerCollapsed = showsWholeScreenState && phase != SchedulePhase.LOADING

    val staleSince = appModel.staleSince(SyncCenter.DataClass.EXACT_AIRING)
    val hasFreshness = phase == SchedulePhase.CONTENT && (appModel.sectionFailed || staleSince != null)
    val online = SyncCenter.isOnline

    val feed = remember(derived, phase, online, hasFreshness, earlierExpanded, isAX, filterActive) {
        buildFeed(derived, phase, online, hasFreshness, earlierExpanded, isAX, filterActive)
    }

    // "The reader is somewhere other than today's section. Measured against TODAY (day 0), which is
    // always in the feed — never against 'the first day that carries something', which on a quiet
    // day is not today and made this read `false` while Wednesday filled the screen."
    val awayFromToday = selectedDay != 0 || (earlierExpanded && selectedDay < 0)

    // ---- Scrolling -------------------------------------------------------------------

    fun keepTickerVisible(day: Int) {
        val first = tickerState.firstVisibleItemIndex + AppModel.SCHEDULE_BACK
        val target = when {
            day < first -> day
            day > first + ScheduleMetrics.TICKER_VISIBLE - 1 ->
                day - ScheduleMetrics.TICKER_VISIBLE + 1
            // "It moves only when the selected day would fall outside them, and then by the least
            // it can."
            else -> return
        }
        val clamped = target.coerceIn(AppModel.SCHEDULE_BACK, AppModel.SCHEDULE_AHEAD)
        scope.launch { tickerState.animateScrollToItem(clamped - AppModel.SCHEDULE_BACK) }
    }

    fun scrollTo(key: String, day: Int) {
        userScrolled = true
        selectedDay = day
        keepTickerVisible(day)
        val index = feed.indexOfFirst { it.key == key }
        if (index >= 0) scope.launch { listState.animateScrollToItem(index) }
    }

    fun goToToday() {
        FeedbackCoordinator.fire(FeedbackToken.SELECTION)
        // "Back to the top of what is ahead: the Earlier row while it is folded (today sits right
        // under it), today's own section once the past has been opened."
        val key = if (earlierExpanded || derived.earlier.isEmpty()) "${PREFIX_DAY}0" else KEY_EARLIER
        scrollTo(key, day = 0)
    }

    // The system reports which targets are on screen; the earliest day among them is the section at
    // the top, and the ticker follows it. No coordinate spaces, no pin-line arithmetic — the one
    // thing the previous screen got wrong in every capture.
    LaunchedEffect(listState) {
        snapshotFlow { topAgendaDay(listState) }
            .distinctUntilChanged()
            .collect { reported ->
                // `NO_AGENDA_VISIBLE` keeps the current selection; `null` means only the Earlier row
                // is on screen, which means today is next under it.
                if (reported == NO_AGENDA_VISIBLE) return@collect
                val day = reported ?: 0
                if (day != selectedDay) {
                    selectedDay = day
                    keepTickerVisible(day)
                }
            }
    }

    // "The moment a finger touches the feed it belongs to the reader" — after that the landing never
    // corrects again.
    LaunchedEffect(listState) {
        listState.interactionSource.interactions.collect { interaction ->
            if (interaction is DragInteraction.Start) userScrolled = true
        }
    }

    // The landing. The FEED never scrolls: the Earlier row (or today's section) is already its first
    // item, so nothing moves — only the ticker is repositioned, un-animated, so today is its first
    // visible cell and the past sits off the leading edge.
    LaunchedEffect(derived.feedKey, showsWholeScreenState) {
        if (userScrolled || library.isEmpty() || showsWholeScreenState) return@LaunchedEffect
        tickerState.scrollToItem(-AppModel.SCHEDULE_BACK)
        if (selectedDay != 0) selectedDay = 0
    }

    LaunchedEffect(Unit) { ScheduleReminders.refresh() }

    // ---- The write -------------------------------------------------------------------

    // "The control fills and the check draws in place; the row settles into its dimmed state and
    // stays (a calendar keeps its history) — unless watched rows are hidden, in which case it leaves
    // after a short hold." The Undo toast is presented when that settles, never before.
    fun commit(row: ScheduleRow, present: () -> Unit) {
        committed = committed + row.id
        if (!unwatchedOnly) {
            present()
            return
        }
        scope.launch {
            delay(ScheduleMetrics.HIDE_WATCHED_HOLD_MILLIS)
            committed = committed - row.id
            present()
        }
    }

    fun mark(row: ScheduleRow, batch: Boolean) {
        val f = row.franchise
        val part = row.part
        if (!batch) {
            val undo = appModel.markNext(franchiseId = f.id, mediaId = part.mediaId) ?: return
            commit(row) { appModel.presentUndo(undo) }
            return
        }
        // Marking this row would skip at least one episode, so it confirms with the exact count.
        val count = row.episode - part.progress
        prompt = WritePrompt(
            title = Copy.Confirm.batchMarkTitle(count),
            message = Copy.Confirm.batchMarkMessage(from = part.progress, to = row.episode),
            confirm = Copy.Confirm.batchMarkConfirm(count),
            perform = {
                // `present = false`: the toast waits for the card's handoff to settle. `markThrough`
                // clamps to the part's ceiling, fires ONE haptic (medium, because the delta is > 1)
                // and mints an undo carrying the real count.
                val undo = appModel.markThrough(
                    franchiseId = f.id,
                    mediaId = part.mediaId,
                    episode = row.episode,
                    present = false,
                )
                if (undo != null) commit(row) { appModel.presentUndo(undo) }
            },
        )
    }

    // ---- Chrome + feed ---------------------------------------------------------------

    Box(modifier.fillMaxSize().background(ThemeColor.canvas)) {
        // Only the BOTTOM scroll edge is drawn. The top edge belongs to the chrome band below, whose
        // ground IS the wash: "measured on this screen a poster and two lines of row text were
        // plainly legible through the ticker's date numerals and beside the title."
        ScrollEdgeChromeBox(modifier = Modifier.fillMaxSize(), edges = ChromeEdge.Bottom) {
            Column(Modifier.fillMaxSize()) {
                ChromeBand(
                    washCover = derived.washCover,
                    tickerState = tickerState,
                    tickerCollapsed = tickerCollapsed,
                    awayFromToday = awayFromToday,
                    typeFilter = typeFilter,
                    unwatchedOnly = unwatchedOnly,
                    filterActive = filterActive,
                    selectedDay = selectedDay,
                    counts = derived.counts,
                    live = derived.live,
                    todayNoon = appModel.scheduleTodayNoon,
                    onToday = { goToToday() },
                    onPickDay = { offset ->
                        FeedbackCoordinator.fire(FeedbackToken.SELECTION)
                        // "Every enabled cell now has a section to land on: a day carries rows, or
                        // it is today, which renders empty rather than being skipped."
                        if (offset < 0) earlierExpanded = true
                        scrollTo("$PREFIX_DAY$offset", day = offset)
                    },
                    // The haptic fires from the MUTATION, not from an observer, so one transaction
                    // is one haptic.
                    onTypeFilter = {
                        typeFilter = it
                        FeedbackCoordinator.fire(FeedbackToken.SELECTION)
                    },
                    onHideWatched = {
                        unwatchedOnly = it
                        FeedbackCoordinator.fire(FeedbackToken.SELECTION)
                    },
                )

                PreviouslyPullToRefresh(
                    onRefresh = { appModel.reload() },
                    // Schedule draws no bar spinner — the day strip is what says the screen is
                    // alive — so there is nothing for the pull to stand down for.
                    onDrivingChange = {},
                    modifier = Modifier.weight(1f),
                ) {
                    BoxWithConstraints(Modifier.fillMaxSize()) {
                        val viewportHeight = maxHeight
                        LazyColumn(
                            state = listState,
                            modifier = Modifier.fillMaxSize().chromeHazeSource(),
                            // A scroll-content inset, never padding on the last item: padding inside
                            // a stack shorter than the viewport changes no layout at all, which is
                            // exactly the case a short feed is in when it comes to rest inside the
                            // bottom ramp.
                            contentPadding = tabBarContentPadding(),
                        ) {
                            items(
                                items = feed,
                                key = { it.key },
                                contentType = { it::class },
                            ) { item ->
                                FeedRow(
                                    item = item,
                                    appModel = appModel,
                                    derived = derived,
                                    now = now,
                                    dates = dates,
                                    staleSince = staleSince,
                                    viewportHeight = viewportHeight,
                                    earlierExpanded = earlierExpanded,
                                    isAX = isAX,
                                    reduceMotion = reduceMotion,
                                    committed = committed,
                                    // One spec set for every row: `uiSnappy` placement is the feed's
                                    // own re-layout animation, and `uiGentle` is the fade the stale
                                    // strip needs so it does not snap in and shove the rows down.
                                    modifier = Modifier.animateItem(
                                        fadeInSpec = ThemeMotion.uiGentle(),
                                        placementSpec = ThemeMotion.uiSnappy(
                                            IntOffset.VisibilityThreshold,
                                        ),
                                        fadeOutSpec = ThemeMotion.uiGentle(),
                                    ),
                                    onOpen = { r ->
                                        onOpenDetail(r.franchise.id, r.part.mediaId, r.episode)
                                    },
                                    onMark = { r, batch -> mark(r, batch) },
                                    onToggleEarlier = {
                                        FeedbackCoordinator.fire(FeedbackToken.SELECTION)
                                        earlierExpanded = !earlierExpanded
                                    },
                                    onRetry = { scope.launch { appModel.reload() } },
                                    onAddShow = onAddShow,
                                    onClearFilters = {
                                        FeedbackCoordinator.fire(FeedbackToken.SELECTION)
                                        typeFilter = MediaFilter.ALL
                                        unwatchedOnly = false
                                    },
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    prompt?.let { p ->
        BatchMarkDialog(
            prompt = p,
            onDismiss = { prompt = null },
            onConfirm = {
                prompt = null
                p.perform()
            },
        )
    }
}

/** `topAgendaDay` reports this when no agenda target is on screen at all: keep the selection. */
private const val NO_AGENDA_VISIBLE = Int.MIN_VALUE

/**
 * The port of `onScrollTargetVisibilityChange(idType:threshold: 0.2)`.
 *
 * Returns the earliest day among the visible agenda targets; `null` when targets are visible but
 * none of them names a day (only the Earlier row), and [NO_AGENDA_VISIBLE] when there is nothing to
 * report at all. **Read inside a `snapshotFlow`, never in a composable body** — this is layout
 * information that changes on every frame of a scroll.
 */
private fun topAgendaDay(state: LazyListState): Int? {
    val info = state.layoutInfo
    val start = info.viewportStartOffset
    val end = info.viewportEndOffset
    var any = false
    var min: Int? = null
    for (item in info.visibleItemsInfo) {
        val key = item.key as? String ?: continue
        if (!isAgendaKey(key)) continue
        val size = item.size
        if (size <= 0) continue
        val visible = minOf(item.offset + size, end) - maxOf(item.offset, start)
        if (visible.toFloat() / size < ScheduleMetrics.VISIBILITY_THRESHOLD) continue
        any = true
        val day = dayOf(key) ?: continue
        val current = min
        if (current == null || day < current) min = day
    }
    return if (!any) NO_AGENDA_VISIBLE else min
}

// -------------------------------------------------------------------------------------
// The chrome band
// -------------------------------------------------------------------------------------

/**
 * Bar, ticker and filter chips over the ambient wash.
 *
 * **The band's ground is THE WASH**, sized to end exactly at the band's own bottom edge — which is
 * what removes the seam. `ArtBackdrop`'s final stop IS `ThemeColor.canvas`, so at the band's bottom
 * the ground is already the canvas the feed scrolls on: warm behind the title and the ticker, plain
 * canvas the pixel below, no step anywhere. A flat canvas strip (what this screen shipped) put a
 * hard horizontal edge across the wash; a translucent veil (what Library uses over its rows) let
 * posters through the date numerals. This is both: opaque, and continuous with the content.
 *
 * The height is **measured, not composed**: "the band's height answers to Dynamic Type and to
 * whether chips are showing". The measurement is taken from the CONTENT column rather than from the
 * box that also holds the wash, or the two would chase each other upward.
 */
@Composable
private fun ChromeBand(
    washCover: String?,
    tickerState: LazyListState,
    tickerCollapsed: Boolean,
    awayFromToday: Boolean,
    typeFilter: MediaFilter,
    unwatchedOnly: Boolean,
    filterActive: Boolean,
    selectedDay: Int,
    counts: Map<Int, Int>,
    live: Set<Int>,
    todayNoon: Long,
    onToday: () -> Unit,
    onPickDay: (Int) -> Unit,
    onTypeFilter: (MediaFilter) -> Unit,
    onHideWatched: (Boolean) -> Unit,
) {
    val density = LocalDensity.current
    val floor = ThemeMetrics.topChromeHeight()
    var measured by remember(floor) { mutableStateOf(floor) }

    Box(Modifier.fillMaxWidth()) {
        ArtBackdrop(
            modifier = Modifier.align(Alignment.TopCenter),
            url = washCover,
            // No artwork anywhere: first run gets the app's own colour rather than a grey band.
            tint = if (washCover == null) ThemeColor.accent else null,
            height = maxOf(measured, floor),
        )

        Column(
            Modifier
                .fillMaxWidth()
                .onSizeChanged { size ->
                    val h = with(density) { size.height.toDp() }
                    if (h != measured) measured = h
                }
                .padding(bottom = if (tickerCollapsed) 0.dp else ThemeSpace.x2),
        ) {
            // Inline, never a large title: "a large title collapses on the first scroll and moves
            // the top safe area ~50 pt mid-flight, under a ticker that has to hold still."
            InlineChromeBar(
                title = Copy.Schedule.title,
                leading = {
                    AnimatedVisibility(
                        visible = awayFromToday,
                        enter = fadeIn(ThemeMotion.uiGentle()),
                        exit = fadeOut(ThemeMotion.uiGentle()),
                    ) {
                        TodayButton(onToday)
                    }
                },
                trailing = {
                    FilterMenuButton(
                        typeFilter = typeFilter,
                        unwatchedOnly = unwatchedOnly,
                        filterActive = filterActive,
                        onTypeFilter = onTypeFilter,
                        onHideWatched = onHideWatched,
                    )
                },
            )

            // Collapse by HEIGHT, animated — never a bare `if`. The ticker's scroll position lives
            // above this composable for the same reason.
            AnimatedVisibility(
                visible = !tickerCollapsed,
                enter = fadeIn(ThemeMotion.uiGentle()) + expandVertically(ThemeMotion.uiGentle()),
                exit = fadeOut(ThemeMotion.uiGentle()) + shrinkVertically(ThemeMotion.uiGentle()),
            ) {
                Ticker(
                    state = tickerState,
                    selectedDay = selectedDay,
                    counts = counts,
                    live = live,
                    todayNoon = todayNoon,
                    onPickDay = onPickDay,
                )
            }

            // Drawn in the CHROME, not in the feed — "so a reader who filters, leaves and comes back
            // is never shown a schedule that merely looks thin."
            AnimatedVisibility(
                visible = filterActive,
                enter = fadeIn(ThemeMotion.uiGentle()),
                exit = fadeOut(ThemeMotion.uiGentle()),
            ) {
                FilterChips(
                    typeFilter = typeFilter,
                    unwatchedOnly = unwatchedOnly,
                    onTypeFilter = onTypeFilter,
                    onHideWatched = onHideWatched,
                )
            }
        }
    }
}

/**
 * The bar's LEADING control.
 *
 * Two decisions, both quoted:
 *
 * > LEADING, not trailing. Two items plus a spacer on the trailing side pushed the inline title off
 * > centre — "Schedule" sat hard against the leading bezel while every other root centres its title.
 * > It also reads better: the leading slot is where navigation lives, the trailing slot is where the
 * > view's controls do.
 *
 * > Explicitly `interactive`: unstyled, this inherited the app-wide accent tint and rendered as an
 * > amber tappable word — the exact collision the `interactive` token exists to forbid, worst on the
 * > one screen where amber means "today".
 *
 * [TertiaryButton] draws in `LocalControlInk`, which the tab's navigation host provides as
 * `interactive`; there is no cascading tint on Android and none is wanted.
 */
@Composable
private fun TodayButton(onToday: () -> Unit) {
    TertiaryButton(
        label = Copy.Schedule.today,
        onClick = onToday,
        modifier = Modifier.semantics(mergeDescendants = true) {
            contentDescription = Copy.Schedule.scrollToToday
            onClick(label = Copy.Schedule.scrollToTodayHint) { onToday(); true }
        },
    )
}

/**
 * The filter control.
 *
 * An **active** filter is STATE, so its glyph is amber — drawn on an `accentSoft` disc, because
 * Material has no circled-filter glyph to answer SF's `line.3.horizontal.decrease.circle.fill` and
 * the app already owns that disc.
 *
 * iOS opens a `Menu` containing an inline `Picker` and a `Toggle`. Here it is a `DropdownMenu` (the
 * sanctioned anchored popup) with a radio group and a checked row: a switch inside a dropdown is not
 * an Android shape, and a checkable menu item is.
 */
@Composable
private fun FilterMenuButton(
    typeFilter: MediaFilter,
    unwatchedOnly: Boolean,
    filterActive: Boolean,
    onTypeFilter: (MediaFilter) -> Unit,
    onHideWatched: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
) {
    var open by remember { mutableStateOf(false) }
    val spokenValue = listOfNotNull(
        typeFilter.chipLabel.takeIf { typeFilter != MediaFilter.ALL },
        Copy.Filter.hideWatched.takeIf { unwatchedOnly },
    ).joinToString(", ").ifEmpty { Copy.Filter.off }

    Box(modifier) {
        Box(
            Modifier
                .size(minimumTapTarget)
                .clickable(
                    interactionSource = null,
                    indication = PressStyle.control,
                    role = Role.Button,
                    onClick = { open = true },
                )
                .semantics(mergeDescendants = true) {
                    contentDescription = Copy.Filter.filter
                    stateDescription = spokenValue
                },
            contentAlignment = Alignment.Center,
        ) {
            Box(
                Modifier
                    .size(ScheduleMetrics.filterDisc)
                    .background(
                        color = if (filterActive) ThemeColor.accentSoft else Color.Transparent,
                        shape = CircleShape,
                    ),
                contentAlignment = Alignment.Center,
            ) {
                Image(
                    imageVector = rememberSymbol(PreviouslyIcons.FilterList),
                    contentDescription = null,
                    modifier = Modifier.size(materialGlyphBox(ScheduleMetrics.filterGlyph)),
                    colorFilter = ColorFilter.tint(
                        if (filterActive) ThemeColor.accent else ThemeColor.textPrimary,
                    ),
                )
            }
        }

        PreviouslyMaterialBridge {
            DropdownMenu(
                expanded = open,
                onDismissRequest = { open = false },
                // The `.floating` surface level, spelled out: an opaque ground, a full
                // `strokeStrong` ring and the floating shadow.
                shape = ContinuousCornerShape(ThemeRadius.compactControl),
                containerColor = ThemeColor.surfaceFloating,
                tonalElevation = 0.dp,
                shadowElevation = ShadowToken.Floating.elevation,
                border = BorderStroke(ThemeMetrics.hairline, ThemeColor.strokeStrong),
            ) {
                MenuSectionLabel(Copy.Filter.source)
                for (option in MediaFilter.entries) {
                    MenuRow(
                        label = option.chipLabel,
                        checked = option == typeFilter,
                        role = Role.RadioButton,
                    ) {
                        open = false
                        onTypeFilter(option)
                    }
                }
                Spacer(
                    Modifier
                        .fillMaxWidth()
                        .height(1.dp)
                        .background(ThemeColor.separatorQuiet),
                )
                MenuRow(
                    label = Copy.Filter.hideWatched,
                    checked = unwatchedOnly,
                    role = Role.Checkbox,
                ) {
                    open = false
                    onHideWatched(!unwatchedOnly)
                }
            }
        }
    }
}

/** The menu's one element that names without acting. An eyebrow, so it uppercases. */
@Composable
private fun MenuSectionLabel(text: String) {
    SectionLabel(
        text = text,
        modifier = Modifier.padding(horizontal = ThemeMetrics.gutter, vertical = ThemeSpace.x2),
        tint = ThemeColor.textTertiary,
    )
}

/**
 * One command in the filter menu. `interactive` ink — a menu item is an action, and actions are ink;
 * the tick beside it is amber, because a chosen value is STATE.
 */
@Composable
private fun MenuRow(
    label: String,
    checked: Boolean,
    role: Role,
    onSelect: () -> Unit,
) {
    val isSelected = checked
    Row(
        Modifier
            .fillMaxWidth()
            .clickable(
                interactionSource = null,
                indication = PressStyle.groupedRow,
                role = role,
                onClick = onSelect,
            )
            // iOS states the selection in colour alone here. TalkBack cannot see amber, so the state
            // is spoken as well — the second carrier the design should always have had.
            .semantics(mergeDescendants = true) { selected = isSelected }
            .defaultMinSize(minHeight = minimumTapTarget)
            .padding(horizontal = ThemeMetrics.gutter, vertical = ThemeSpace.x2),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(ThemeSpace.x3),
    ) {
        BasicText(
            text = label,
            style = ThemeType.body,
            maxLines = 1,
            modifier = Modifier.weight(1f),
            color = ColorProducer { ThemeColor.textPrimary },
        )
        if (checked) {
            Image(
                imageVector = rememberSymbol(PreviouslyIcons.Check),
                contentDescription = null,
                modifier = Modifier.size(materialGlyphBox(menuCheckGlyph)),
                colorFilter = ColorFilter.tint(ThemeColor.accent),
            )
        }
    }
}

/** The menu's tick, at its iOS point size. */
private val menuCheckGlyph = 14.dp

/**
 * The active criteria, as removable chips.
 *
 * The amber here is STATE — this filter is on — and it is a GROUND at 14 %, with the criterion in
 * amber ink on it. Tapping removes the filter, which is why the whole chip is the target.
 */
@Composable
private fun FilterChips(
    typeFilter: MediaFilter,
    unwatchedOnly: Boolean,
    onTypeFilter: (MediaFilter) -> Unit,
    onHideWatched: (Boolean) -> Unit,
) {
    Row(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = ThemeMetrics.gutter)
            .padding(top = ThemeSpace.x2),
        horizontalArrangement = Arrangement.spacedBy(ThemeSpace.x2),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (typeFilter != MediaFilter.ALL) {
            FilterChip(text = typeFilter.chipLabel, onRemove = { onTypeFilter(MediaFilter.ALL) })
        }
        if (unwatchedOnly) {
            FilterChip(text = Copy.Filter.hideWatched, onRemove = { onHideWatched(false) })
        }
    }
}

// -------------------------------------------------------------------------------------
// The ticker
// -------------------------------------------------------------------------------------

/**
 * Twenty-two cells, always all of them, whether or not the feed carries that day.
 *
 * iOS needs two nested-scroll defences here — a horizontal scroll view inside a `safeAreaInset` is
 * greedy on its cross axis, and it inherits the feed's tab-bar content margins through the
 * environment. Neither exists in Compose: a `LazyRow` in a `Column` wraps its own height and
 * inherits no padding from a sibling, so both are dropped rather than translated.
 */
@Composable
private fun Ticker(
    state: LazyListState,
    selectedDay: Int,
    counts: Map<Int, Int>,
    live: Set<Int>,
    todayNoon: Long,
    onPickDay: (Int) -> Unit,
) {
    val offsets = remember { (AppModel.SCHEDULE_BACK..AppModel.SCHEDULE_AHEAD).toList() }
    LazyRow(
        state = state,
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = ThemeSpace.x1)
            .semantics { contentDescription = Copy.Schedule.ticker },
        contentPadding = PaddingValues(horizontal = ThemeMetrics.gutter),
        horizontalArrangement = Arrangement.spacedBy(ScheduleMetrics.cellGap),
    ) {
        items(items = offsets, key = { it }) { offset ->
            TickerCell(
                offset = offset,
                todayNoon = todayNoon,
                count = counts[offset] ?: 0,
                live = live.contains(offset),
                selected = offset == selectedDay,
                onPick = { onPickDay(offset) },
            )
        }
    }
}

/**
 * One day in the strip.
 *
 * Three decisions here, each quoted from the source:
 *
 *  * **The disc.** "Calendar's own grammar: today is the filled disc, the selected day a quiet one.
 *    A stroked rounded square read as a form control." Amber is today's alone in this control, so
 *    the selected cell gets a neutral `surfaceRaised` disc — the app's one exception to "amber
 *    selection is legal STATE".
 *  * **The ink.** "A day with nothing on it is not a target and looks like one: primary ink only for
 *    the days the feed can land on. Every cell used to wear the same white, and a tap on '5' that
 *    did nothing read as a broken control rather than as an empty Saturday."
 *  * **The top line.** "The first of a month names the month where its weekday letter would go — the
 *    numerals alone cannot say that '2' comes after '31'."
 */
@Composable
private fun TickerCell(
    offset: Int,
    todayNoon: Long,
    count: Int,
    live: Boolean,
    selected: Boolean,
    onPick: () -> Unit,
) {
    val ts = todayNoon + offset * Formatting.D
    val parts = remember(ts) { Formatting.localParts(ts) }
    val isToday = offset == 0
    val past = offset < 0
    val enabled = count > 0 || isToday

    val top = remember(ts) {
        if (parts.d == 1) {
            monthWord(ts)
        } else {
            Formatting.weekdayLetterMonFirst(Formatting.localMondayCol(ts))
        }
    }

    val fade = animateFloatAsState(
        targetValue = if (past && !selected) ScheduleMetrics.PAST_DIM else 1f,
        animationSpec = motion(MotionToken.UI_MICRO),
        label = "tickerCellFade",
    )
    val disc = animateColorAsState(
        targetValue = when {
            isToday -> ThemeColor.accent
            selected -> ThemeColor.surfaceRaised
            else -> Color.Transparent
        },
        animationSpec = motion(MotionToken.UI_MICRO),
        label = "tickerCellDisc",
    )

    // "Thursday 3 September" — the locale's own full weekday + month + day skeleton, never a
    // hand-assembled date.
    val spokenLabel = remember(ts) { Formatting.fmtTodayDate(ts) }
    val spokenValue = listOfNotNull(
        Copy.Schedule.selected.takeIf { selected },
        Copy.Schedule.today.takeIf { isToday },
        if (count > 0) Copy.episodes(count) else Copy.Schedule.noEpisodes,
    ).joinToString(", ")

    val dotSize = ScheduleMetrics.dot * LocalDensity.current.fontScale
    val highContrast = rememberHighTextContrast()

    Column(
        modifier = Modifier
            .width(ScheduleMetrics.cellWidth)
            .defaultMinSize(minHeight = minimumTapTarget)
            .graphicsLayer { alpha = fade.value }
            .clickable(
                interactionSource = null,
                // The app's one press language for a control with a ground of its own. iOS's
                // `TickerCellPressStyle` also dims to 0.7; the compression is the half that carries
                // the feedback, and a second press feel for one control is what this token prevents.
                indication = PressStyle.control,
                enabled = enabled,
                role = Role.Button,
                onClick = onPick,
            )
            .semantics(mergeDescendants = true) {
                contentDescription = spokenLabel
                stateDescription = spokenValue
            },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(ScheduleMetrics.cellStack),
    ) {
        BasicText(
            text = top,
            style = ThemeType.caption,
            maxLines = 1,
            color = ColorProducer { if (isToday) ThemeColor.accent else ThemeColor.textTertiary },
        )

        Box(
            Modifier
                .size(ScheduleMetrics.numeralMin)
                // Read in the DRAW phase: a selection change costs one node's draw, not the strip's
                // recomposition.
                .drawBehind { drawCircle(disc.value) },
            contentAlignment = Alignment.Center,
        ) {
            AutoSizeText(
                text = parts.d.toString(),
                style = ThemeType.time.copy(
                    color = when {
                        isToday -> ThemeColor.onAccent
                        enabled -> ThemeColor.textPrimary
                        else -> ThemeColor.textSecondary
                    },
                ),
                minScale = ScheduleMetrics.NUMERAL_MIN_SCALE,
                maxLines = 1,
            )
        }

        // Hidden from the accessibility tree: the cell's value already says how many episodes there
        // are, and a dot spoken as well would be a second sentence for one fact.
        Spacer(
            Modifier
                .size(dotSize)
                .background(
                    color = when {
                        count <= 0 -> Color.Transparent
                        live -> ThemeColor.accent
                        else -> ThemeColor.textTertiary
                    },
                    shape = CircleShape,
                )
                .clearAndSetSemantics {},
        )

        // Android has no Differentiate Without Colour flag; high-contrast text is the closest signal
        // the platform exposes, and `spec/schedule.md` §19 names it as the second choice. Under it
        // today's cell gains a 2-dp accent capsule, so "today" is not carried by a hue alone. Absent
        // otherwise — exactly as on iOS.
        if (isToday && highContrast) {
            Spacer(
                Modifier
                    .padding(horizontal = ThemeSpace.x1)
                    .fillMaxWidth()
                    .height(differentiatingUnderlineHeight)
                    .background(ThemeColor.accent, CircleShape),
            )
        }
    }
}

/** iOS `differentiatingUnderline`: a 2-pt accent capsule under the cell. */
private val differentiatingUnderlineHeight = 2.dp

/**
 * The month word for the first of a month, in the locale's own short standalone form.
 *
 * iOS extracts it from the locale-ordered "MMMd" string by taking the first space-separated
 * component that is not an integer, so both `Sep 1` and `1 Sep` yield `SEP`. Android can ask for the
 * month alone, which is the honest version of the same rule; only the rule ports.
 */
private fun monthWord(ts: Long): String {
    val locale = Locale.getDefault()
    return Month.of(Formatting.localParts(ts).mo)
        .getDisplayName(java.time.format.TextStyle.SHORT_STANDALONE, locale)
        .uppercase(locale)
}

// -------------------------------------------------------------------------------------
// The feed's rows
// -------------------------------------------------------------------------------------

@Composable
private fun FeedRow(
    item: FeedItem,
    appModel: AppModel,
    derived: Derived,
    now: Long,
    dates: CopyDates,
    staleSince: Long?,
    viewportHeight: Dp,
    earlierExpanded: Boolean,
    isAX: Boolean,
    reduceMotion: Boolean,
    committed: Set<String>,
    modifier: Modifier,
    onOpen: (ScheduleRow) -> Unit,
    onMark: (ScheduleRow, Boolean) -> Unit,
    onToggleEarlier: () -> Unit,
    onRetry: () -> Unit,
    onAddShow: () -> Unit,
    onClearFilters: () -> Unit,
) {
    when (item) {
        FeedItem.Skeleton -> Box(modifier) {
            // The gate owns the timing and no screen re-implements it: nothing for the first 240 ms,
            // at least 320 ms once shown, a 120 ms crossfade out.
            SkeletonGate(isLoading = true, skeleton = { FeedSkeleton() }, content = {})
        }

        is FeedItem.Whole -> Box(modifier) {
            EmptyState(
                copy = item.state,
                modifier = Modifier
                    .padding(horizontal = ThemeMetrics.gutter)
                    // The divisor is the bar's VISUAL height, not the scroll clearance: subtracting
                    // a scroll inset when centring pushed every empty state ~81 dp above true centre.
                    .centredState(contentHeight = viewportHeight),
                onPrimary = when (item.action) {
                    WholeAction.NONE -> null
                    WholeAction.RETRY -> onRetry
                    WholeAction.ADD_SHOW -> onAddShow
                    WholeAction.CLEAR_FILTERS -> onClearFilters
                },
            )
        }

        FeedItem.Freshness -> Box(
            modifier
                .padding(horizontal = ThemeMetrics.gutter)
                .padding(top = ThemeMetrics.labelGap),
        ) {
            // At most one line, and the failure outranks the clock.
            if (appModel.sectionFailed) {
                InlineNotice(message = Copy.Notice.schedule, onRetry = onRetry)
            } else if (staleSince != null) {
                StaleStrip(since = staleSince, now = now, dates = dates)
            }
        }

        FeedItem.EarlierRow -> EarlierRow(
            count = derived.earlierCount,
            unwatched = derived.earlierUnwatched,
            expanded = earlierExpanded,
            isAX = isAX,
            onToggle = onToggleEarlier,
            modifier = modifier,
        )

        is FeedItem.DayHeader -> DayHeader(
            day = item.day,
            emptyText = emptyDayText(derived),
            isAX = isAX,
            modifier = modifier,
        )

        is FeedItem.EmptyDay -> BasicText(
            text = emptyDayText(derived),
            style = ThemeType.rowMeta,
            modifier = modifier
                .fillMaxWidth()
                .defaultMinSize(minHeight = minimumTapTarget)
                .padding(horizontal = ThemeMetrics.gutter),
            color = ColorProducer { ThemeColor.textTertiary },
        )

        is FeedItem.Card -> CardRow(
            row = item.row,
            last = item.last,
            appModel = appModel,
            committed = committed,
            reduceMotion = reduceMotion,
            onOpen = onOpen,
            onMark = onMark,
            modifier = modifier,
        )

        FeedItem.Tail -> FeedTail(
            horizonId = derived.horizonId,
            todayNoon = appModel.scheduleTodayNoon,
            modifier = modifier,
        )
    }
}

/** "'No episodes' when the filter is what emptied it" — there *are* some; you filtered them. */
private fun emptyDayText(derived: Derived): String =
    if (derived.todayFiltered) Copy.Schedule.noEpisodes else Copy.Schedule.nothingScheduled

/**
 * One airing, with everything the row computes before drawing.
 *
 * `showsAction` reads the DATA's `watched`, never `isCommitted`: "The control stays put through the
 * commit so the check can DRAW in place; only a row that was already watched when the screen loaded
 * starts as a settled one."
 *
 * The long-press menu is the shared [FranchiseQuickActions] — "a row here is the same show" — and it
 * is offered only for a show that is actually in the library, exactly as iOS passes `nil` otherwise.
 */
@Composable
private fun CardRow(
    row: ScheduleRow,
    last: Boolean,
    appModel: AppModel,
    committed: Set<String>,
    reduceMotion: Boolean,
    onOpen: (ScheduleRow) -> Unit,
    onMark: (ScheduleRow, Boolean) -> Unit,
    modifier: Modifier = Modifier,
) {
    val isCommitted = committed.contains(row.id)
    val watched = row.watched || isCommitted
    val inLibrary = appModel.isInLibrary(row.franchise.id)
    val showsAction = row.aired && !row.watched && inLibrary
    // Marking this row would skip at least one episode, so it confirms with the exact count.
    val batch = row.aired && row.episode > row.part.progress + 1
    // `fmtTime` returns "" for a date-only anchor; the guard makes that explicit and passes null, so
    // a TMDB row can never invent a clock.
    val time = if (row.dateOnly) null else Formatting.fmtTime(row.at, row.franchise.timeAnchor)
    val hasReminder = !row.aired && ScheduleReminders.has(row.part.mediaId, row.episode)

    val card: @Composable (Modifier) -> Unit = { slot ->
        AiringCard(
            franchise = row.franchise,
            meta = metaLine(row),
            time = time,
            aired = row.aired,
            watched = watched,
            dateOnly = row.dateOnly,
            hasReminder = hasReminder,
            onOpen = { onOpen(row) },
            modifier = slot,
        ) {
            // The optimistic write lands in the same update as the commit, so the observed behaviour
            // on a mark is the REMOVAL branch: the ring fades out over 160 ms while the tick badge
            // appears on the art and the card dims.
            AnimatedVisibility(
                visible = showsAction,
                enter = ThemeMotion.handoffEnter(reduceMotion),
                exit = ThemeMotion.handoffExit(reduceMotion),
            ) {
                MarkRing(
                    marked = watched,
                    onMark = { if (!watched) onMark(row, batch) },
                    // Quiet, never filled: twenty filled amber discs down one column turn a rhythm
                    // into a scoreboard.
                    style = MarkRingStyle.Quiet,
                    // The table owns this label, and `MarkRing` reads the same entry for the
                    // identical control on every other screen: one control, one name. It used to be
                    // assembled from typed English here, so the ring was "Mark Episode 21 of
                    // Mushoku Tensei as watched" on Schedule and "Mark episode 21 watched, Mushoku
                    // Tensei" everywhere else.
                    label = if (batch) {
                        Copy.Action.markThrough(
                            from = row.part.progress + 1,
                            to = row.episode,
                            title = row.franchise.title,
                        )
                    } else {
                        Copy.Action.markEpisodeWatched(row.episode, row.franchise.title)
                    },
                    markedLabel = Copy.Progress.episodeWatched(row.episode),
                )
            }
        }
    }

    val frame = modifier
        .padding(horizontal = ThemeMetrics.gutter)
        .padding(bottom = if (last) 0.dp else ScheduleMetrics.cardGap)

    if (inLibrary) {
        FranchiseQuickActions(
            franchise = row.franchise,
            appModel = appModel,
            modifier = frame,
        ) {
            card(Modifier)
        }
    } else {
        card(frame)
    }
}

/**
 * The episode line.
 *
 * A same-day date-only drop states its count ("Season 2 · 8 episodes", or a bare "8 episodes" when
 * the part has no label or the show has one part); everything else takes the shared watch-context
 * rule. Notation is fixed by the copy table: **"Episode 21", never "E21" or "Ep 21".**
 */
private fun metaLine(row: ScheduleRow): String {
    val n = row.episodes.last - row.episodes.first + 1
    if (n > 1) {
        val label = row.part.canonicalLabel
        val drop = Copy.episodes(n)
        return if (label.isEmpty() || row.franchise.parts.size == 1) drop else "$label · $drop"
    }
    return row.franchise.watchContext(row.part, row.episode)
}

/**
 * The day header — an EYEBROW, no rule and no ground.
 *
 * "Not the section-title family any more: the card under this label names its show at `rowTitle`,
 * Outfit SemiBold 17, ten points down — a day set in Outfit SemiBold 20 was the same shape in the
 * same ink, and 'Tomorrow' and 'Mushoku Tensei' read as two rows of one list. A label above a title
 * is the hierarchy every other grouped list in the app draws."
 *
 * "No ground of its own: the wash is the screen's ground and a plate here would carve a step out of
 * it."
 *
 * The weekday is repeated in the detail only for today and tomorrow, where the word alone does not
 * name a day: **"TODAY · THU 3 SEP"**, **"TOMORROW · FRI 4 SEP"**, **"FRIDAY · 11 SEP"**.
 */
@Composable
private fun DayHeader(
    day: DayView,
    emptyText: String,
    isAX: Boolean,
    modifier: Modifier = Modifier,
) {
    val word = when (day.id) {
        0 -> Copy.Schedule.today
        1 -> Copy.Schedule.tomorrow
        else -> Formatting.weekdayNameMonFirst(Formatting.localMondayCol(day.noon))
    }
    val date = Formatting.fmtMonthDay(day.noon)
    val detail = if (day.id == 0 || day.id == 1) {
        "${Formatting.weekdayShortMonFirst(Formatting.localMondayCol(day.noon))} $date"
    } else {
        date
    }
    val text = "$word · $detail"

    // The count slot, in order: an empty day says so HERE, on its own baseline; a day with more than
    // one card states the count; a single card says nothing, because "1 episode" over one card
    // restates the card.
    val countText = when {
        day.isEmpty && !isAX -> emptyText
        day.count > 1 -> Copy.episodes(day.count)
        else -> null
    }
    // "'0 episodes' is a count, not a state. An empty today speaks the same words the line under it
    // prints, so VoiceOver and the screen agree."
    val spoken = "$text, ${if (day.isEmpty) emptyText else Copy.episodes(day.count)}"

    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = ThemeMetrics.gutter)
            .padding(top = ThemeMetrics.sectionGap, bottom = ThemeMetrics.labelGap)
            // Children ignored: the header is one element carrying one sentence, marked as a heading
            // so the heading rotor can skim the agenda a day at a time.
            .clearAndSetSemantics {
                contentDescription = spoken
                heading()
            },
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.Top,
    ) {
        Row(
            // `fill = false` caps the group so a long weekday cannot push the count off the trailing
            // edge, and leaves the slack between the two rather than after both.
            //
            // `alignByBaseline` on the GROUP, not only inside it: Compose propagates a child's
            // alignment lines up through the layouts that contain it, so the count sits on the day
            // word's own baseline — iOS's `HStack(alignment: .firstTextBaseline)`, in two nested
            // rows.
            modifier = Modifier.weight(1f, fill = false).alignByBaseline(),
            horizontalArrangement = Arrangement.spacedBy(ScheduleMetrics.labelInnerGap),
            verticalAlignment = Alignment.Top,
        ) {
            SectionLabel(
                text = word,
                modifier = Modifier.alignByBaseline(),
                tint = if (day.isToday) ThemeColor.accent else ThemeColor.textSecondary,
            )
            SectionLabel(
                text = "· $detail",
                modifier = Modifier.alignByBaseline(),
                tint = ThemeColor.textTertiary,
            )
        }
        if (countText != null) {
            Spacer(Modifier.width(ThemeSpace.x2))
            SectionLabel(
                text = countText,
                modifier = Modifier.alignByBaseline(),
                tint = ThemeColor.textTertiary,
            )
        }
    }
}

/**
 * The Earlier fold — aired days collapsed behind one 44-dp row above today, "so the screen opens on
 * what is ahead and still lets the reader check what they missed".
 *
 * The type family is the DAY-LABEL family, not the section-title family: "it was the section-title
 * family while the day headers were, and followed them out of it, so the show's title is the only
 * title here."
 *
 * At accessibility sizes the label and its count reflow onto two lines rather than truncating the
 * count away — "'EARLIER 3 episodes · 1 to…' hid the only number on the row that says whether
 * opening it is worth it."
 */
@Composable
private fun EarlierRow(
    count: Int,
    unwatched: Int,
    expanded: Boolean,
    isAX: Boolean,
    onToggle: () -> Unit,
    modifier: Modifier = Modifier,
) {
    // "'3 to watch' while every earlier episode is still unwatched, '3 episodes' once none is, and
    // both only when they differ — '3 episodes · 3 to watch' said one number twice."
    val meta = when {
        unwatched == 0 -> Copy.episodes(count)
        unwatched == count -> Copy.Schedule.toWatch(unwatched)
        else -> "${Copy.episodes(count)} · ${Copy.Schedule.toWatch(unwatched)}"
    }
    val rotation = animateFloatAsState(
        targetValue = if (expanded) 90f else 0f,
        animationSpec = motion(MotionToken.UI_MICRO),
        label = "earlierChevron",
    )
    val spoken = "${Copy.Schedule.earlier}, $meta"
    val hint = if (expanded) Copy.Schedule.hideEarlier else Copy.Schedule.showEarlier

    Box(
        modifier = modifier
            .fillMaxWidth()
            .clickable(
                interactionSource = null,
                indication = PressStyle.row(ThemeRadius.row),
                role = Role.Button,
                onClick = onToggle,
            )
            .semantics(mergeDescendants = true) {
                contentDescription = spoken
                onClick(label = hint) { onToggle(); true }
            }
            .defaultMinSize(minHeight = minimumTapTarget)
            .padding(horizontal = ThemeMetrics.gutter)
            .padding(vertical = if (isAX) ThemeSpace.x2 else 0.dp),
        contentAlignment = Alignment.CenterStart,
    ) {
        if (isAX) {
            Column(verticalArrangement = Arrangement.spacedBy(ThemeSpace.x1)) {
                SectionLabel(text = Copy.Schedule.earlier, tint = ThemeColor.textSecondary)
                SectionLabel(
                    text = "· $meta",
                    tint = if (unwatched > 0) ThemeColor.textSecondary else ThemeColor.textTertiary,
                )
            }
        } else {
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Row(
                    modifier = Modifier.weight(1f, fill = false),
                    horizontalArrangement = Arrangement.spacedBy(ScheduleMetrics.labelInnerGap),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    SectionLabel(text = Copy.Schedule.earlier, tint = ThemeColor.textSecondary)
                    SectionLabel(
                        text = "· $meta",
                        tint = if (unwatched > 0) {
                            ThemeColor.textSecondary
                        } else {
                            ThemeColor.textTertiary
                        },
                    )
                }
                Spacer(Modifier.width(ThemeSpace.x2))
                Image(
                    imageVector = rememberSymbol(PreviouslyIcons.ChevronRight),
                    contentDescription = null,
                    modifier = Modifier
                        .size(materialGlyphBox(ScheduleMetrics.earlierChevron))
                        .graphicsLayer { rotationZ = rotation.value },
                    colorFilter = ColorFilter.tint(ThemeColor.textTertiary),
                )
            }
        }
    }
}

/**
 * The end of the horizon — and it NAMES the horizon, which is now true, because the feed holds every
 * dated episode up to it.
 */
@Composable
private fun FeedTail(horizonId: Int?, todayNoon: Long, modifier: Modifier = Modifier) {
    val text = horizonId
        ?.let { Copy.Schedule.everythingThrough(Formatting.fmtMonthDay(todayNoon + it * Formatting.D)) }
        ?: Copy.Empty.nothingScheduled.title
    BasicText(
        text = text,
        style = ThemeType.rowMeta,
        modifier = modifier
            .fillMaxWidth()
            .defaultMinSize(minHeight = minimumTapTarget)
            .padding(horizontal = ThemeMetrics.gutter)
            .padding(top = ThemeSpace.x3),
        color = ColorProducer { ThemeColor.textTertiary },
    )
}

/**
 * Three repeats of the airing card's own anatomy, "so the swap lands in place. It drew poster rows
 * until 3 Sep, the row the calendar stopped using."
 */
@Composable
private fun FeedSkeleton() {
    Column(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = ThemeMetrics.gutter)
            .clearAndSetSemantics { contentDescription = Copy.Accessibility.loading },
    ) {
        repeat(3) {
            SkeletonLine(
                modifier = Modifier.padding(
                    top = skeletonDayGap,
                    bottom = ThemeMetrics.labelGap,
                ),
                width = skeletonDayWidth,
                height = skeletonDayHeight,
            )
            SkeletonBlock(
                modifier = Modifier.fillMaxWidth().aspectRatio(ThemeMetrics.wideAspect),
                height = null,
                radius = ThemeRadius.card,
            )
            SkeletonLine(
                modifier = Modifier.padding(top = ThemeSpace.x2),
                width = skeletonTitleWidth,
                height = skeletonTitleHeight,
            )
            SkeletonLine(
                modifier = Modifier.padding(top = ThemeSpace.x1),
                width = skeletonMetaWidth,
                height = skeletonMetaHeight,
            )
        }
    }
}

// The skeleton's own geometry: it mirrors the card it stands in for, so the swap changes content
// and not shape. Skeleton blocks do NOT scale with the text size — they are structure, not text.
private val skeletonDayGap = 30.dp
private val skeletonDayWidth = 116.dp
private val skeletonDayHeight = 11.dp
private val skeletonTitleWidth = 212.dp
private val skeletonTitleHeight = 13.dp
private val skeletonMetaWidth = 96.dp
private val skeletonMetaHeight = 10.dp

/**
 * The batch-mark confirmation. Every confirmation states its exact blast radius, and a confirmation
 * BUTTON never ends in an ellipsis.
 *
 * M3's own `Button` / `TextButton` are banned outright; these are the app's bare words in a 44-dp
 * box, drawn in `LocalControlInk`.
 */
@Composable
private fun BatchMarkDialog(prompt: WritePrompt, onDismiss: () -> Unit, onConfirm: () -> Unit) {
    PreviouslyMaterialBridge {
        AlertDialog(
            onDismissRequest = onDismiss,
            title = {
                BasicText(
                    text = prompt.title,
                    style = ThemeType.showTitleM,
                    color = ColorProducer { ThemeColor.textPrimary },
                )
            },
            text = {
                BasicText(
                    text = prompt.message,
                    style = ThemeType.callout,
                    color = ColorProducer { ThemeColor.textSecondary },
                )
            },
            confirmButton = { TertiaryButton(label = prompt.confirm, onClick = onConfirm) },
            dismissButton = { TertiaryButton(label = Copy.Confirm.cancel, onClick = onDismiss) },
            containerColor = ThemeColor.surfaceFloating,
            shape = ContinuousCornerShape(ThemeRadius.card),
        )
    }
}

// -------------------------------------------------------------------------------------
// Platform signals
// -------------------------------------------------------------------------------------

/**
 * Android's nearest thing to iOS's **Differentiate Without Colour**: the high-contrast-text
 * accessibility setting.
 *
 * There is no direct equivalent — the platform exposes no "differentiate without colour" flag — so
 * this is the documented second choice from `spec/schedule.md` §19. It reads back as 0 on a device
 * where it was never written, which is "default", not "on"; only an explicit 1 turns the underline
 * on. Observed live, because a user who changes the setting while the app is open expects the app to
 * obey without a relaunch — the same shape as `rememberReduceMotion`.
 */
@Composable
private fun rememberHighTextContrast(): Boolean {
    val resolver = LocalContext.current.contentResolver
    var high by remember(resolver) { mutableStateOf(highTextContrastEnabled(resolver)) }
    DisposableEffect(resolver) {
        val observer = object : ContentObserver(Handler(Looper.getMainLooper())) {
            override fun onChange(selfChange: Boolean) {
                high = highTextContrastEnabled(resolver)
            }
        }
        resolver.registerContentObserver(
            Settings.Secure.getUriFor(HIGH_TEXT_CONTRAST),
            false,
            observer,
        )
        onDispose { resolver.unregisterContentObserver(observer) }
    }
    return high
}

private const val HIGH_TEXT_CONTRAST = "high_text_contrast_enabled"

private fun highTextContrastEnabled(resolver: ContentResolver): Boolean =
    Settings.Secure.getInt(resolver, HIGH_TEXT_CONTRAST, 0) == 1
