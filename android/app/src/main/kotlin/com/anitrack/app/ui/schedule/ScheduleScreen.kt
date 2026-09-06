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
import androidx.compose.ui.graphics.drawscope.Stroke
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
import com.anitrack.app.data.ReceiptHost
import androidx.compose.foundation.border
import com.anitrack.app.design.shadowToken
import androidx.compose.ui.draw.clip
import com.anitrack.app.ui.chrome.chromeGlass

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
    val typeFilter: MediaFilter = MediaFilter.ALL,
    val hideWatched: Boolean = false,
    /** `--ez scheduleMonthOpen true` — open with the calendar already down, for a capture. */
    val monthOpen: Boolean = false,
    /**
     * `--ez scheduleDemoStates true` — the test account has no AIRED-AND-UNWATCHED airing (both
     * past slots are watched, and Mushoku is `planned`, so its four are correctly off the
     * calendar), so the state ladder cannot be photographed with all three rungs on real data.
     * This draws the most recent aired airing as though it were still waiting. It changes what is
     * DRAWN, never what is stored.
     */
    val demoStates: Boolean = false,
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
            typeFilter = when (intent.getStringExtra("scheduleFilter")) {
                "anime" -> MediaFilter.ANIME
                "tv" -> MediaFilter.TV
                else -> MediaFilter.ALL
            },
            hideWatched = flag("scheduleHideWatched"),
            monthOpen = flag("scheduleMonthOpen"),
            demoStates = flag("scheduleDemoStates"),
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

    /** Between two airings on one day. */
    val rowGap = ThemeSpace.x4

    /**
     * Between one day and the next. NOT [ThemeMetrics.sectionGap] (30): a schedule is sparse —
     * measured on the test library ten of the window's twenty-two days carry an episode and none
     * carries more than one — so at the section gap a feed of one-row days was half header by area,
     * and the eyebrow floated between two rows belonging to neither.
     */
    val dayGap = ThemeSpace.x6



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

private const val PREFIX_DAY = "day:"
private const val PREFIX_EMPTY_DAY = "empty:"
private const val PREFIX_ROW = "row:"

/** Whether this key is one of the agenda targets the ticker follows. */
private fun isAgendaKey(key: String): Boolean =
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

    data class DayHeader(val day: DayView, val previousIsEmpty: Boolean = false) : FeedItem {
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
    pinnedEmptyDay: Int?,
    todayNoon: Long,
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
        out.add(FeedItem.Whole(state = Copy.Empty.noScheduleMatches, action = WholeAction.CLEAR_FILTERS))
        return out
    }

    // The past, then today (always), then what is ahead — one agenda, no fold (4 Sep; the "Earlier"
    // row and its "3 to watch" were one of the three confusions named). Plus the one empty day the
    // reader picked on the strip, drawn as a section that says "Nothing scheduled" so the pick
    // lands somewhere.
    val days = ArrayList(derived.earlier + derived.ahead)
    if (pinnedEmptyDay != null && pinnedEmptyDay != 0 && days.none { it.id == pinnedEmptyDay }) {
        days.add(DayView(id = pinnedEmptyDay, noon = todayNoon + pinnedEmptyDay * Formatting.D, rows = emptyList()))
        days.sortBy { it.id }
    }
    days.forEachIndexed { i, day ->
        // An empty day is a header with no body: the next day closes up to x4 under it (i2), or
        // the two headers sat a whole section gap apart with nothing between them.
        out.add(FeedItem.DayHeader(day, previousIsEmpty = i > 0 && days[i - 1].isEmpty))
        if (day.isEmpty) {
            // At reading sizes the statement lives in the header's count slot, on its own baseline.
            // A ROW, at every size (6 Sep). Today is the day the reader is standing on, and as a
            // fragment in the header's trailing slot it was the thinnest, emptiest thing on the
            // screen — the one day with a header and no body. The rule that put it in the header
            // came from the card era, when a grey line cost a third of a screen; at row density it
            // costs 32 dp and buys today the same shape every other day has.
            out.add(FeedItem.EmptyDay(day))
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
    /**
     * A day the reader picked on the strip that has nothing on it: drawn as an empty section so the
     * pick lands somewhere — every strip day is a target now (4 Sep). [pendingPick] carries the
     * scroll until the feed has rebuilt with that section in it.
     */
    var pinnedEmptyDay by rememberSaveable { mutableStateOf<Int?>(null) }
    var pendingPick by remember { mutableStateOf<Int?>(null) }
    /** Row ids whose mark is animating. */
    var committed by remember { mutableStateOf(emptySet<String>()) }
    var prompt by remember { mutableStateOf<WritePrompt?>(null) }
    /** The day at the top of the feed — what the calendar highlights. Never a scroll offset. */
    var selectedDay by rememberSaveable { mutableStateOf(0) }
    /**
     * Whether the calendar is down. At rest it is NOT: the screen's whole point is that it has no
     * date chrome until the reader asks for one.
     */
    var calendarOpen by rememberSaveable { mutableStateOf(debug.monthOpen) }
    /** Any day inside the month the calendar is showing, as an offset from today. */
    var monthAnchor by rememberSaveable { mutableStateOf(0) }
    /** Once a finger has moved the feed, the landing stops correcting. */
    var userScrolled by remember { mutableStateOf(false) }

    val listState = rememberLazyListState()

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

    // The demo's target: the most recent aired row. A DRAWING override — nothing is written.
    val demoUnwatchedId = if (debug.demoStates) {
        derived.earlier.lastOrNull()?.rows?.lastOrNull()?.id
    } else {
        null
    }



    val staleSince = appModel.staleSince(SyncCenter.DataClass.EXACT_AIRING)
    val hasFreshness = phase == SchedulePhase.CONTENT && (appModel.sectionFailed || staleSince != null)
    val online = SyncCenter.isOnline

    val todayNoon = appModel.scheduleTodayNoon
    val feed = remember(derived, phase, online, hasFreshness, pinnedEmptyDay, todayNoon, isAX, filterActive) {
        buildFeed(derived, phase, online, hasFreshness, pinnedEmptyDay, todayNoon, isAX, filterActive)
    }

    // "The reader is somewhere other than today's section. Measured against TODAY (day 0), which is
    // always in the feed — never against 'the first day that carries something', which on a quiet
    // day is not today and made this read `false` while Wednesday filled the screen."
    val awayFromToday = selectedDay != 0

    // ---- Scrolling -------------------------------------------------------------------

    fun scrollTo(key: String, day: Int) {
        userScrolled = true
        selectedDay = day
        // The calendar follows an explicit move as well as a scroll, so pressing Today with the
        // grid open does not leave it on a month the feed has left.
        monthAnchor = day
        val index = feed.indexOfFirst { it.key == key }
        if (index >= 0) scope.launch { listState.animateScrollToItem(index) }
    }

    fun goToToday() {
        FeedbackCoordinator.fire(FeedbackToken.SELECTION)
        scrollTo("${PREFIX_DAY}0", day = 0)
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
                    // The calendar follows the feed across a month boundary, so opening it never
                    // shows a month the reader has scrolled away from.
                    monthAnchor = day
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

    // The landing: the feed opens on TODAY — no longer its first item, now that the past sits above
    // it — un-animated.
    LaunchedEffect(derived.feedKey, showsWholeScreenState, feed) {
        if (userScrolled || library.isEmpty() || showsWholeScreenState) return@LaunchedEffect
        val index = feed.indexOfFirst { it.key == "${PREFIX_DAY}0" }
        if (index >= 0) listState.scrollToItem(index)
        if (selectedDay != 0) selectedDay = 0
    }

    // A strip tap on an empty day: the section is pinned into the feed first; the scroll follows
    // once the feed has rebuilt with it.
    LaunchedEffect(feed, pendingPick) {
        val pick = pendingPick ?: return@LaunchedEffect
        val key = "$PREFIX_DAY$pick"
        if (feed.any { it.key == key }) {
            pendingPick = null
            scrollTo(key, day = pick)
        }
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
            // In place, under the card's caption.
            commit(row) { appModel.presentUndo(undo, host = ReceiptHost.schedule(part.mediaId, row.episode)) }
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
                if (undo != null) commit(row) { appModel.presentUndo(undo, host = ReceiptHost.schedule(part.mediaId, row.episode)) }
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
                    awayFromToday = awayFromToday,
                    typeFilter = typeFilter,
                    unwatchedOnly = unwatchedOnly,
                    filterActive = filterActive,
                    calendarOpen = calendarOpen,
                    onToday = { goToToday() },
                    onToggleCalendar = {
                        FeedbackCoordinator.fire(FeedbackToken.SELECTION)
                        calendarOpen = !calendarOpen
                    },
                    // The haptic fires from the MUTATION, not from an observer, so one transaction
                    // is one haptic.
                    onTypeFilter = { typeFilter = it },
                    onHideWatched = { unwatchedOnly = it },
                )

                Box(Modifier.weight(1f)) {
                PreviouslyPullToRefresh(
                    onRefresh = { appModel.reload() },
                    // Schedule draws no bar spinner — the day strip is what says the screen is
                    // alive — so there is nothing for the pull to stand down for.
                    onDrivingChange = {},
                    modifier = Modifier.fillMaxSize(),
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
                                    isAX = isAX,
                                    reduceMotion = reduceMotion,
                                    committed = committed,
                                    demoUnwatchedId = demoUnwatchedId,
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

                // The calendar OVERLAYS the feed (Google Calendar's month dropdown), it does not
                // push it: 500 dp of grid inserted above a lazy list threw the reader's place three
                // screens down and back again on every toggle. It lives INSIDE the feed's own box,
                // below the chrome band, so it hangs from the bar by construction rather than by an
                // arithmetic top inset — as a child of the screen's root it was drawn over the word
                // "Schedule". Mounted only while it is down, because a held-at-zero-alpha overlay
                // over a scrolling list is a composited layer per frame.
                CalendarOverlay(
                visible = calendarOpen,
                todayNoon = appModel.scheduleTodayNoon,
                counts = derived.counts,
                live = derived.live,
                selected = selectedDay,
                monthAnchor = monthAnchor,
                onMonthAnchor = { monthAnchor = it },
                onDismiss = {
                    FeedbackCoordinator.fire(FeedbackToken.SELECTION)
                    calendarOpen = false
                },
                onPick = { offset ->
                    FeedbackCoordinator.fire(FeedbackToken.SELECTION)
                    // A pick closes the calendar. Leaving it down over the day it just took you to
                    // means the answer is hidden behind the question.
                    calendarOpen = false
                    // Every cell is a target: a day with a section lands on it; an empty one gets
                    // a section pinned for it first.
                    val key = "$PREFIX_DAY$offset"
                    if (feed.any { it.key == key }) {
                        scrollTo(key, day = offset)
                    } else {
                        pinnedEmptyDay = offset
                        pendingPick = offset
                    }
                },
                )
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
    awayFromToday: Boolean,
    typeFilter: MediaFilter,
    unwatchedOnly: Boolean,
    filterActive: Boolean,
    calendarOpen: Boolean,
    onToday: () -> Unit,
    onToggleCalendar: () -> Unit,
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
                // Only the filter chips can give this band height, so only they earn its padding.
                .padding(bottom = if (filterActive) ThemeSpace.x2 else 0.dp),
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
                    // The calendar's switch. A TAP, not a pull — Fantastical pulls its DayTicker
                    // down into a month, but this screen already owns the pull gesture for refresh.
                    // ONE glyph in both states, tinted when the grid is down: a control that
                    // changes its symbol on press reads as a different control.
                    CalendarButton(open = calendarOpen, onToggle = onToggleCalendar)
                    FilterMenuButton(
                        typeFilter = typeFilter,
                        unwatchedOnly = unwatchedOnly,
                        filterActive = filterActive,
                        onTypeFilter = onTypeFilter,
                        onHideWatched = onHideWatched,
                    )
                },
            )

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

/** The bar control that brings the month grid down over the feed. */
@Composable
private fun CalendarButton(open: Boolean, onToggle: () -> Unit, modifier: Modifier = Modifier) {
    Box(
        modifier
            .size(minimumTapTarget)
            .clickable(
                interactionSource = null,
                indication = PressStyle.control,
                role = Role.Button,
                onClick = onToggle,
            )
            .semantics(mergeDescendants = true) {
                contentDescription = Copy.Schedule.calendar
                stateDescription =
                    if (open) Copy.Schedule.calendarShown else Copy.Schedule.calendarHidden
            },
        contentAlignment = Alignment.Center,
    ) {
        Box(
            Modifier
                .size(ScheduleMetrics.filterDisc)
                .background(
                    color = if (open) ThemeColor.accentSoft else Color.Transparent,
                    shape = CircleShape,
                ),
            contentAlignment = Alignment.Center,
        ) {
            Image(
                imageVector = rememberSymbol(PreviouslyIcons.CalendarMonth),
                contentDescription = null,
                modifier = Modifier.size(materialGlyphBox(ScheduleMetrics.filterGlyph)),
                colorFilter = ColorFilter.tint(
                    if (open) ThemeColor.accent else ThemeColor.textPrimary,
                ),
            )
        }
    }
}

/**
 * The calendar, its scrim, and the rules for getting out of it.
 *
 * Anywhere off the grid closes it, as a menu does. There is no dimming of the feed: the grid has
 * its own surface and a tap-to-dismiss, and a scrim over a schedule the reader is trying to read
 * against is theatre.
 */
@Composable
private fun CalendarOverlay(
    visible: Boolean,
    todayNoon: Long,
    counts: Map<Int, Int>,
    live: Set<Int>,
    selected: Int,
    monthAnchor: Int,
    onMonthAnchor: (Int) -> Unit,
    onDismiss: () -> Unit,
    onPick: (Int) -> Unit,
) {
    // The transition lives HERE rather than at the call site: nested inside the screen's `Column`,
    // Kotlin resolved `AnimatedVisibility` to the `ColumnScope` overload through the outer implicit
    // receiver and refused the call. In its own composable there is no such receiver.
    AnimatedVisibility(
        visible = visible,
        enter = fadeIn(ThemeMotion.uiSnappy()) + expandVertically(ThemeMotion.uiSnappy()),
        exit = fadeOut(ThemeMotion.uiSnappy()) + shrinkVertically(ThemeMotion.uiSnappy()),
    ) {
    BoxWithConstraints(
        Modifier
            .fillMaxSize()
            .clickable(
                interactionSource = null,
                indication = null,
                onClick = onDismiss,
            ),
    ) {
        val available = maxHeight - ThemeMetrics.tabBarClearance
        val shape = ContinuousCornerShape(ThemeRadius.card)
        Box(
            Modifier
                .align(Alignment.TopCenter)
                .padding(top = ThemeSpace.x1)
                .padding(horizontal = ThemeSpace.x3)
                // GLASS over the feed, not a flat grey slab — the panel is chrome that floats,
                // which is what every other floating surface in the app is made of. `chromeGlass`
                // is the app's one sanctioned entry to it (and its Reduce-Transparency branch is an
                // opaque `surfaceFloating`, which is exactly what a calendar wants when the device
                // cannot blur). The canvas veil UNDER it is what keeps the numerals legible over
                // busy art, the same pairing the bars use.
                .shadowToken(ShadowToken.Card, shape)
                .clip(shape)
                .background(ThemeColor.canvas.copy(alpha = 0.72f))
                .chromeGlass(shape)
                .border(1.dp, ThemeColor.stroke, shape)
                // The panel eats its own taps so a miss inside it does not dismiss.
                .clickable(interactionSource = null, indication = null, onClick = {}),
        ) {
            ScheduleMonthGrid(
                todayNoon = todayNoon,
                counts = counts,
                live = live,
                selected = selected,
                window = AppModel.SCHEDULE_BACK..AppModel.SCHEDULE_AHEAD,
                monthAnchor = monthAnchor,
                maxHeight = available,
                onMonthAnchor = onMonthAnchor,
                onPick = onPick,
            )
        }
    }
    }
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
    isAX: Boolean,
    reduceMotion: Boolean,
    committed: Set<String>,
    demoUnwatchedId: String?,
    modifier: Modifier,
    onOpen: (ScheduleRow) -> Unit,
    onMark: (ScheduleRow, Boolean) -> Unit,
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

        is FeedItem.DayHeader -> DayHeader(
            day = item.day,
            previousIsEmpty = item.previousIsEmpty,
            emptyText = emptyDayText(derived),
            isAX = isAX,
            modifier = modifier,
        )

        is FeedItem.EmptyDay -> BasicText(
            text = emptyDayText(derived),
            style = ThemeType.rowMeta,
            modifier = modifier
                .fillMaxWidth()
                .defaultMinSize(minHeight = 32.dp)
                .padding(horizontal = ThemeMetrics.gutter),
            color = ColorProducer { ThemeColor.textTertiary },
        )

        is FeedItem.Card -> CardRow(
            row = item.row,
            last = item.last,
            appModel = appModel,
            committed = committed,
            demoUnwatchedId = demoUnwatchedId,
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
    demoUnwatchedId: String?,
    reduceMotion: Boolean,
    onOpen: (ScheduleRow) -> Unit,
    onMark: (ScheduleRow, Boolean) -> Unit,
    modifier: Modifier = Modifier,
) {
    val isCommitted = committed.contains(row.id)
    // `scheduleDemoStates`: one aired row is drawn as though it were still waiting, so the ladder
    // can be photographed with all three rungs on one screen.
    val demoUnseen = demoUnwatchedId == row.id && !isCommitted
    val watched = (row.watched && !demoUnseen) || isCommitted
    val inLibrary = appModel.isInLibrary(row.franchise.id)
    val showsAction = row.aired && !watched && inLibrary
    // THE state, decided once and read by every part of the row that shows it — the ladder's
    // control, the clock's ink and the tile's exposure. It used to be three unrelated booleans
    // computed at three different depths, which is why the three states never lined up.
    val state = when {
        !row.aired -> AiringState.Upcoming
        watched -> AiringState.Watched
        else -> AiringState.ToWatch
    }
    // Marking this row would skip at least one episode, so it confirms with the exact count.
    val batch = row.aired && row.episode > row.part.progress + 1
    // `fmtTime` returns "" for a date-only anchor; the guard makes that explicit and passes null, so
    // a TMDB row can never invent a clock.
    val time = if (row.dateOnly) null else Formatting.fmtTime(row.at, row.franchise.timeAnchor)
    val hasReminder = !row.aired && ScheduleReminders.has(row.part.mediaId, row.episode)

    val card: @Composable (Modifier) -> Unit = { slot ->
        ScheduleAiringRow(
            franchise = row.franchise,
            meta = metaLine(row),
            time = time,
            state = state,
            hasReminder = hasReminder,
            onOpen = { onOpen(row) },
            modifier = slot,
            receiptHost = ReceiptHost.schedule(row.part.mediaId, row.episode),
        ) {
            AiringStateControl(
                state = state,
                episode = row.episode,
                committing = isCommitted,
                title = row.franchise.title,
                batch = batch,
                count = row.episode - row.part.progress,
                canMark = showsAction,
                onMark = { if (!isCommitted) onMark(row, batch) },
            )
        }
    }

    val frame = modifier
        .padding(horizontal = ThemeMetrics.gutter)
        .padding(bottom = if (last) 0.dp else ScheduleMetrics.rowGap)

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
    previousIsEmpty: Boolean = false,
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

    // The count, INLINE, on the same separator the date uses. Only when it says something:
    // "1 episode" over a single row restates the row. It hung at the TRAILING edge until 6 Sep —
    // the only right-aligned text on the screen — which on an empty today put "TODAY · SUN 6 SEP"
    // and "NOTHING SCHEDULED" at opposite ends of a bare line with 200 dp of nothing between them,
    // four small-caps fragments reading as a table header rather than a day ("Today row looks weird
    // visually", user). An empty day now states itself in a ROW beneath, like every other day.
    val countText = if (day.count > 1) Copy.episodes(day.count) else null
    // "'0 episodes' is a count, not a state. An empty today speaks the same words the line under it
    // prints, so VoiceOver and the screen agree."
    val spoken = "$text, ${if (day.isEmpty) emptyText else Copy.episodes(day.count)}"

    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = ThemeMetrics.gutter)
            .padding(
                top = if (previousIsEmpty) ThemeSpace.x4 else ScheduleMetrics.dayGap,
                bottom = ThemeMetrics.labelGap,
            )
            // Children ignored: the header is one element carrying one sentence, marked as a heading
            // so the heading rotor can skim the agenda a day at a time.
            .clearAndSetSemantics {
                contentDescription = spoken
                heading()
            },
        horizontalArrangement = Arrangement.Start,
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
            Spacer(Modifier.width(ScheduleMetrics.labelInnerGap))
            SectionLabel(
                text = "· $countText",
                modifier = Modifier.alignByBaseline(),
                tint = ThemeColor.textTertiary,
            )
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
