package com.anitrack.app.ui.detail

import androidx.compose.animation.core.Animatable
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
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
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDefaults
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.SelectableDates
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.ColorProducer
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.anitrack.app.AppModel
import com.anitrack.app.data.RewatchStore
import com.anitrack.app.data.WatchSession
import com.anitrack.app.design.ContinuousCornerShape
import com.anitrack.app.design.FeedbackCoordinator
import com.anitrack.app.design.FeedbackToken
import com.anitrack.app.design.LocalControlInk
import com.anitrack.app.design.LocalReduceMotion
import com.anitrack.app.design.MotionToken
import com.anitrack.app.design.PosterSize
import com.anitrack.app.design.PreviouslyIcons
import com.anitrack.app.design.PreviouslyMaterialBridge
import com.anitrack.app.design.ShadowToken
import com.anitrack.app.design.SurfaceLevel
import com.anitrack.app.design.ThemeColor
import com.anitrack.app.design.ThemeMetrics
import com.anitrack.app.design.ThemeRadius
import com.anitrack.app.design.ThemeSpace
import com.anitrack.app.design.ThemeType
import com.anitrack.app.design.pickMotion
import com.anitrack.app.design.surface
import com.anitrack.app.ui.art.ArtBackdrop
import com.anitrack.app.ui.art.PosterSlot
import com.anitrack.app.ui.control.PressStyle
import com.anitrack.app.ui.control.SymbolIcon
import com.anitrack.app.ui.control.TertiaryButton
import com.anitrack.app.ui.control.minimumTapTarget
import com.anitrack.app.ui.isAccessibilityTextSize
import com.anitrack.app.ui.list.GroupedList
import com.anitrack.app.ui.list.GroupedRow
import com.anitrack.app.ui.list.GroupedTrailing
import com.anitrack.app.ui.row.MediaRow
import com.anitrack.app.ui.section.SectionLabel
import com.anitrack.app.ui.state.EmptyState
import com.anitrack.app.ui.state.EmptyStateProminence
import com.anitrack.app.ui.state.centredState
import com.anitrack.model.Formatting
import com.anitrack.model.Franchise
import com.anitrack.model.TemporalCopy
import com.anitrack.model.canonicalPartLabel
import com.anitrack.model.copy.Copy
import com.anitrack.model.copy.EmptyStateCopy
import com.anitrack.model.currentPart
import com.anitrack.model.displayTitle
import com.anitrack.model.landscapeArt
import com.anitrack.model.portraitArt
import java.util.Calendar
import java.util.TimeZone

// =================================================================================================
// THE WATCH RECORD — the port of the two surfaces `ios/Sources/Features/FranchiseDetail/
// RewatchViews.swift` owns beyond the start sheet: **Watch history** (Surface D) and **one
// session** (Surface E). Spec: docs/android-port/spec/detail.md §14.5–14.6.
//
// Rewatching is first-class: every completed watch is a session, at most one is active per
// franchise, and progress lives on the server while the sessions explain it. `RewatchStore` is the
// device-local JSON that holds them.
//
// The three rules this file exists to keep:
//
//  1. **A rail needs two nodes to be a rail.** One session is a plain row under its own eyebrow —
//     *"one disconnected ring floating beside a single card was worse than no timeline at all."*
//  2. **Every row carries WHEN.** *"Five sessions across four years read as five ordinals and five
//     counts with nothing at all to tell them apart — on the one screen in the app whose entire
//     subject is when things happened."* One formatter stands behind every date on the screen.
//  3. **`episodes` is the SCOPE's length**, so it is what was watched on a finished session and is
//     not on a running one. "2 episodes watched" beside "Episode 1 next" is the same class of lie
//     the predication exists to stop, in the other direction.
//
// The start sheet, the rewatch transaction and `RewatchArrival` live in `DetailScreen.kt` /
// `EpisodeList.kt`, which own Detail's own surfaces; this file consumes `RewatchArrival` and never
// records into it.
//
// -------------------------------------------------------------------------------------
// WHAT CHANGED IN THE PORT, AND WHY
//
// 1. **The bar carries the subtitle.** iOS gates `chromeNavigationSubtitle` to iOS 26 and DROPS the
//    line below it, rather than faking one. Android's bar is drawn by the app, so the line the
//    design asked for is simply drawn — the constraint that removed it was Apple's, not the
//    design's.
//
// 2. **The overflow is a `DropdownMenu`** — iOS's blurred lift-and-platter has no Android
//    equivalent and reproducing one is the heavy engineering the fidelity line rules out.
//
// 3. **The session sheet is a `ModalBottomSheet` sized by its content**, which is what iOS's
//    measured `.presentationDetents([.height(contentHeight)])` was reaching for: *"the sheet is
//    exactly as tall as what is in it. At `.medium` it left 105–600 pt of dead plate below the last
//    group."* A bottom sheet wraps its content natively, so nothing has to be measured.
// =================================================================================================

// ─────────────────────────────────────────────────────────────────────────────
// Copy
// ─────────────────────────────────────────────────────────────────────────────
// The record's strings live in `Copy.Rewatch` (`:model`, `copy/CopyScreens.kt`), beside the start
// sheet's scope word: one vocabulary, one home.


// ─────────────────────────────────────────────────────────────────────────────
// Surface D — Watch history
// ─────────────────────────────────────────────────────────────────────────────

/**
 * The record of one show's watches.
 *
 * Three shapes, and which one is drawn is the whole design:
 *
 *  * **nothing** → the empty state, CENTRED. *"An empty state pinned under the navigation bar with
 *    1 400 pt of canvas under it reads as a screen that failed to load; centred in the content area
 *    it reads as the answer to the question the screen asks."*
 *  * **one session** → an eyebrow and a plain row, centred in the viewport at ordinary text sizes.
 *  * **two or more** → the rail, TOP-ALIGNED. *"Two cards started ~354 pt down the screen with
 *    ~230 pt of unexplained void above them … a rail starts at the top, where a list starts."*
 *
 * The bottom chrome is the pushed-screen scaffold's, applied by the shell around this screen; the
 * scroll's own bottom clearance is [DetailMetrics.bottomClearance].
 */
@Composable
fun WatchHistoryScreen(
    franchiseId: String,
    appModel: AppModel,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val now = appModel.now
    val franchise = appModel.franchise(franchiseId)
    val sessions = RewatchStore.sessions(franchiseId)
    val isAX = isAccessibilityTextSize()
    val reduceMotion = LocalReduceMotion.current

    var editing by remember { mutableStateOf<WatchSession?>(null) }
    var prompt by remember { mutableStateOf<WritePrompt?>(null) }

    val topInset = ThemeMetrics.topSafeInset()
    val subtitle = historySubtitle(sessions)
    val barBottom = topInset + historyBarHeight(subtitle.isNotEmpty())

    // The bar's one destructive command, or nothing at all when there is no record to destroy —
    // a menu whose only item cannot apply is a menu that should not open.
    val requestDeleteAll: (() -> Unit)? = if (sessions.isEmpty()) {
        null
    } else {
        {
            prompt = WritePrompt(
                title = Copy.Confirm.deleteHistoryTitle,
                message = Copy.Confirm.deleteHistory(
                    sessions = sessions.size,
                    episodes = sessions.sumOf { it.episodes },
                ),
                confirm = Copy.Confirm.deleteHistoryConfirm,
                destructive = true,
            ) {
                FeedbackCoordinator.fire(FeedbackToken.DESTRUCTIVE)
                RewatchStore.deleteAll(franchiseId)
            }
        }
    }

    Box(modifier.fillMaxSize().background(ThemeColor.canvas)) {
        // The ONE wash spec, app-wide (this screen carried a private 280/0.55 on iOS).
        if (franchise != null) {
            ArtBackdrop(
                url = franchise.landscapeArt ?: franchise.portraitArt,
                modifier = Modifier.align(Alignment.TopCenter),
            )
        }

        BoxWithConstraints(Modifier.fillMaxSize()) {
            val viewport = maxHeight - barBottom
            when {
                sessions.isEmpty() -> EmptyState(
                    copy = EmptyStateCopy.noSessions,
                    modifier = Modifier
                        .padding(horizontal = ThemeMetrics.gutter)
                        .padding(top = barBottom)
                        .centredState(viewport, DetailMetrics.bottomClearance()),
                    prominence = EmptyStateProminence.Major,
                )

                else -> Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .verticalScroll(rememberScrollState()),
                ) {
                    Spacer(Modifier.height(barBottom + ThemeMetrics.heroClearance))

                    val body: @Composable () -> Unit = {
                        if (sessions.size == 1) {
                            // A rail needs two nodes to be a rail.
                            Column(
                                verticalArrangement = Arrangement.spacedBy(ThemeMetrics.labelGap),
                            ) {
                                SectionLabel(Copy.Rewatch.SESSIONS)
                                SoloSessionRow(
                                    session = sessions.first(),
                                    franchise = franchise,
                                    now = now,
                                    onOpen = { editing = sessions.first() },
                                )
                            }
                        } else {
                            HistoryRail(
                                sessions = sessions,
                                franchise = franchise,
                                now = now,
                                reduceMotion = reduceMotion,
                                onOpen = { editing = it },
                            )
                        }
                    }

                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = ThemeMetrics.gutter)
                            // A two-session record is ~240 dp of content above 600 dp of black.
                            // That is what a short list looks like, and it is the honest shape —
                            // so only a genuinely SINGLE session is centred, and never at an
                            // accessibility size, where the content is taller than the container.
                            .then(
                                if (sessions.size == 1 && !isAX) {
                                    Modifier.centredState(
                                        viewport - ThemeMetrics.heroClearance,
                                        DetailMetrics.bottomClearance(),
                                    )
                                } else {
                                    Modifier
                                },
                            ),
                    ) {
                        Column { body() }
                    }

                    Spacer(Modifier.height(DetailMetrics.bottomClearance()))
                }
            }
        }

        HistoryBar(
            title = franchise?.displayTitle ?: Copy.Rewatch.WATCH_HISTORY,
            subtitle = subtitle,
            topInset = topInset,
            onBack = onBack,
            onDeleteAll = requestDeleteAll,
            modifier = Modifier.align(Alignment.TopCenter),
        )
    }

    WritePromptDialog(prompt = prompt, onDismiss = { prompt = null })

    editing?.let { session ->
        SessionDetailSheet(
            session = session,
            franchise = franchise,
            appModel = appModel,
            onDismiss = { editing = null },
        )
    }
}

/**
 * The bar's subtitle: the whole record in one line.
 *
 * **Only FINISHED sessions contribute to "watched".** A rewatch still running has a scope length,
 * not a tally — counting it here is how one noun phrase came to mean two different quantities
 * within one show.
 */
private fun historySubtitle(sessions: List<WatchSession>): String {
    if (sessions.isEmpty()) return ""
    val episodes = sessions.filter { it.isCompleted }.sumOf { it.episodes }
    val bits = mutableListOf(Copy.watchSessions(sessions.size))
    if (episodes > 0) bits += Copy.episodesWatched(episodes)
    return bits.joinToString(" · ")
}

/**
 * One session's line, with ONE date formatter behind it.
 *
 * Adjacent rows read "24 May – 29 Jul" and "10 Dec, 2024" — two formats, one of them missing its
 * year and the other punctuated in a way no locale writes. `TemporalCopy.dateRange` orders and
 * punctuates per locale and states both years whenever the span is not this year's.
 */
private fun sessionLine(session: WatchSession, franchise: Franchise?, now: Long): String {
    val started = session.startedAt
        ?.takeIf { it > 0 }
        ?.let { Copy.Rewatch.startedOn(TemporalCopy.dateWord(it, now, Formatting.TimeAnchor.LOCAL)) }

    if (session.isActive) {
        val progress = nextEpisode(session, franchise)
            ?.let { Copy.episodeNext(it) }
            ?: Copy.Rewatch.IN_PROGRESS
        return listOfNotNull(started, progress).joinToString(" · ")
    }
    session.cancelledAtEpisode?.let { at ->
        return listOfNotNull(started, Copy.Rewatch.cancelledAt(at)).joinToString(" · ")
    }

    // Predicated only where it is TRUE — see rule 3 in the file header.
    val count = when {
        session.episodes <= 0 -> null
        session.isCompleted -> Copy.episodesWatched(session.episodes)
        else -> Copy.episodes(session.episodes)
    }
    val whenText = sessionSpan(session, now) ?: started
    val bits = listOfNotNull(whenText, count)
    return if (bits.isEmpty()) Copy.Progress.datesUnknown else bits.joinToString(" · ")
}

/**
 * The span a finished session covers, or `null` while it is still running.
 *
 * `completedAt == 0` is the store's sentinel for "finished, date unknown", so every formatter here
 * tests `> 0` before printing — a 1970 date is worse than no date.
 */
private fun sessionSpan(session: WatchSession, now: Long): String? {
    val end = session.completedAt?.takeIf { it > 0 } ?: return null
    val start = session.startedAt
    return if (start != null && start > 0 && start < end) {
        TemporalCopy.dateRange(start, end, now)
    } else {
        TemporalCopy.dateWord(end, now, Formatting.TimeAnchor.LOCAL)
    }
}

/** The next episode of the part this session covers, or `null` when it is not running. */
private fun nextEpisode(session: WatchSession, franchise: Franchise?): Int? {
    if (!session.isActive) return null
    val f = franchise ?: return null
    return when (val scope = session.scope) {
        is WatchSession.Scope.Franchise -> f.currentPart?.let { it.progress + 1 }
        is WatchSession.Scope.Part -> f.parts.firstOrNull { it.mediaId == scope.mediaId }
            ?.let { it.progress + 1 }
    }
}

/**
 * The artwork for one session: **the scope's**, not the show's.
 *
 * *"A record of a show with a full art library was showing zero artwork — the only list in the app
 * that did. The earlier reasoning ('three identical covers read as duplicates') was right about the
 * franchise cover and wrong about the fix: a season-scoped rewatch is a different picture, so the
 * scope's poster distinguishes the sessions instead of repeating."*
 */
private fun sessionPoster(session: WatchSession, franchise: Franchise?): String? =
    when (val scope = session.scope) {
        is WatchSession.Scope.Franchise -> franchise?.portraitArt
        is WatchSession.Scope.Part ->
            franchise?.parts?.firstOrNull { it.mediaId == scope.mediaId }?.portraitArt
                ?: franchise?.portraitArt
    }

/** The scope, in the app's own vocabulary. */
private fun scopeLine(session: WatchSession, franchise: Franchise?): String? =
    when (val scope = session.scope) {
        is WatchSession.Scope.Franchise -> Copy.Rewatch.everything
        is WatchSession.Scope.Part ->
            franchise?.canonicalPartLabel(scope.mediaId)?.takeIf { it.isNotEmpty() }
    }

/**
 * The one session, as a record rather than as a media row: what it is called, when it ran, how many
 * episodes it covered, and the way in.
 *
 * An ACTIVE session's line is the `lead` — amber, because a running rewatch is a real next step.
 */
@Composable
private fun SoloSessionRow(
    session: WatchSession,
    franchise: Franchise?,
    now: Long,
    onOpen: () -> Unit,
) {
    val line = sessionLine(session, franchise, now)
    MediaRow(
        title = session.title,
        onClick = onOpen,
        meta = if (session.isActive) null else line,
        lead = if (session.isActive) line else null,
        poster = sessionPoster(session, franchise),
        slot = PosterSize.Queue,
        hint = Copy.Rewatch.OPENS_THIS_SESSION,
    )
}

// ─────────────────────────────────────────────────────────────────────────────
// The bar
// ─────────────────────────────────────────────────────────────────────────────

/** The bar's own band: one line of title, plus one of subtitle when there is one. */
private fun historyBarHeight(hasSubtitle: Boolean): Dp =
    if (hasSubtitle) ThemeMetrics.inlineBarHeight + HistorySubtitleBand else ThemeMetrics.inlineBarHeight

private val HistorySubtitleBand = 16.dp

/** iOS draws a bar's back chevron at 17 pt semibold, and its overflow at 15. */
private val BackGlyph = 17.dp
private val OverflowGlyph = 15.dp

/**
 * Whose history this is.
 *
 * *"The shipped screen was a hand-built row over hidden chrome, titled 'Watch history' and nothing
 * else, so the name of the show whose history it was never appeared anywhere on it."*
 */
@Composable
private fun HistoryBar(
    title: String,
    subtitle: String,
    topInset: Dp,
    onBack: () -> Unit,
    onDeleteAll: (() -> Unit)?,
    modifier: Modifier = Modifier,
) {
    Box(
        modifier = modifier
            .fillMaxWidth()
            .padding(top = topInset)
            .height(historyBarHeight(subtitle.isNotEmpty()))
            // A 44-dp target sits 12 dp from the edge, which puts its ink on the screen's gutter.
            .padding(horizontal = ThemeSpace.x3),
    ) {
        Box(
            modifier = Modifier
                .align(Alignment.CenterStart)
                .size(minimumTapTarget)
                .clickable(
                    interactionSource = null,
                    indication = PressStyle.textAction,
                    role = Role.Button,
                    onClick = onBack,
                )
                .semantics { contentDescription = Copy.Rewatch.BACK },
            contentAlignment = Alignment.Center,
        ) {
            // A known substitution: the icon vocabulary carries no `arrow_back`, which is the
            // Android reflex here. `chevron_right` mirrored is the same glyph pointing the way
            // back, and it is what the vocabulary can express today.
            SymbolIcon(
                symbol = PreviouslyIcons.ChevronRight,
                tint = ThemeColor.textPrimary,
                glyph = BackGlyph,
                modifier = Modifier.mirrored(),
            )
        }

        Column(
            modifier = Modifier
                .align(Alignment.Center)
                .padding(horizontal = minimumTapTarget)
                .semantics(mergeDescendants = true) { heading() },
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            BasicText(
                text = title,
                style = ThemeType.bodyEmphasis.copy(color = ThemeColor.textPrimary),
                maxLines = 1,
            )
            if (subtitle.isNotEmpty()) {
                BasicText(
                    text = subtitle,
                    style = ThemeType.caption.copy(color = ThemeColor.textSecondary),
                    maxLines = 1,
                )
            }
        }

        if (onDeleteAll != null) {
            HistoryOverflow(
                onDeleteAll = onDeleteAll,
                modifier = Modifier.align(Alignment.CenterEnd),
            )
        }
    }
}

/** Mirrors a directional glyph horizontally. */
private fun Modifier.mirrored(): Modifier = graphicsLayer { scaleX = -1f }

/**
 * The bar's one destructive command, behind the overflow — where a command that is not the screen's
 * purpose belongs.
 */
@Composable
private fun HistoryOverflow(onDeleteAll: () -> Unit, modifier: Modifier = Modifier) {
    var open by remember { mutableStateOf(false) }
    Box(modifier) {
        Box(
            modifier = Modifier
                .size(minimumTapTarget)
                .clickable(
                    interactionSource = null,
                    indication = PressStyle.textAction,
                    role = Role.Button,
                    onClick = { open = true },
                )
                .semantics { contentDescription = Copy.Detail.moreActions },
            contentAlignment = Alignment.Center,
        ) {
            SymbolIcon(PreviouslyIcons.MoreHoriz, ThemeColor.textPrimary, OverflowGlyph)
        }
        PreviouslyMaterialBridge {
            DropdownMenu(
                expanded = open,
                onDismissRequest = { open = false },
                // The `.floating` surface level, spelled out.
                shape = ContinuousCornerShape(ThemeRadius.compactControl),
                containerColor = ThemeColor.surfaceFloating,
                tonalElevation = 0.dp,
                shadowElevation = ShadowToken.Floating.elevation,
                border = BorderStroke(ThemeMetrics.hairline, ThemeColor.strokeStrong),
            ) {
                MenuCommand(
                    label = Copy.Action.deleteWatchHistory,
                    destructive = true,
                ) {
                    open = false
                    onDeleteAll()
                }
            }
        }
    }
}

/** One command in a menu. Ink, or destructive ink — never amber, which is not an action colour. */
@Composable
private fun MenuCommand(label: String, destructive: Boolean = false, onClick: () -> Unit) {
    val ink = if (destructive) ThemeColor.destructive else LocalControlInk.current
    Box(
        Modifier
            .fillMaxWidth()
            .clickable(
                interactionSource = null,
                indication = PressStyle.groupedRow,
                role = Role.Button,
                onClick = onClick,
            )
            .defaultMinSize(minHeight = minimumTapTarget)
            .padding(horizontal = ThemeMetrics.gutter, vertical = ThemeSpace.x2),
        contentAlignment = Alignment.CenterStart,
    ) {
        BasicText(text = label, style = ThemeType.body, color = ColorProducer { ink })
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// The rail
// ─────────────────────────────────────────────────────────────────────────────

/*
 * Geometry, from the spec: the 1-dp rail's x-centre sits 4 dp inside the container, the cards start
 * at 22, the node is 8 and the rows are 10 apart. With the screen's own 16-dp gutter the cards
 * therefore start at 38 — "exactly where Schedule's rows start."
 *
 * The rail is drawn as each row's own BACKGROUND rather than as a sibling: a full-height sibling
 * beside the cards would claim the whole proposed height and stretch every row.
 */

private val RailX = 4.dp
private val CardX = 22.dp
private val RailNode = 8.dp
private val RailRowGap = 10.dp
private val RailMinRowHeight = 68.dp
private val RailStroke = ThemeMetrics.hairline
private val RailNodeStroke = 1.5.dp

/** The halo behind an ACTIVE node: the node again, at double the diameter. */
private val RailNodeHalo = RailNode * 2f

/** The arrival's starting scale. */
private const val NodeArrivalScale = 0.6f

/** The active card's ring — the only thing separating it from its identical neighbours. */
private const val ActiveRingAlpha = 0.45f

private enum class RailPosition { Only, First, Middle, Last }

private fun railPosition(index: Int, count: Int): RailPosition = when {
    count == 1 -> RailPosition.Only
    index == 0 -> RailPosition.First
    index == count - 1 -> RailPosition.Last
    else -> RailPosition.Middle
}

@Composable
private fun HistoryRail(
    sessions: List<WatchSession>,
    franchise: Franchise?,
    now: Long,
    reduceMotion: Boolean,
    onOpen: (WatchSession) -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(RailRowGap)) {
        sessions.forEachIndexed { i, session ->
            HistorySessionRow(
                title = session.title,
                subtitle = sessionLine(session, franchise, now),
                poster = sessionPoster(session, franchise),
                active = session.isActive,
                position = railPosition(i, sessions.size),
                // Claimed ONCE, for the session that was just created — the rail's arrival
                // choreography was specified, built, and then called from nothing.
                isNew = remember(session.id) { RewatchArrival.claim(session.id) },
                reduceMotion = reduceMotion,
                onClick = { onOpen(session) },
            )
        }
    }
}

/**
 * One node on the rail, and the card beside it.
 *
 * The arrival is two beats that never overlap: the segment draws on `uiSweep`, and the node settles
 * on `uiMicro` **from that animation's completion**, not from a timer. Under Reduce Motion both
 * arrive at 1 immediately.
 *
 * Both animated values are read inside `drawBehind`, so a frame of the arrival invalidates a draw
 * and never a composition.
 */
@Composable
private fun HistorySessionRow(
    title: String,
    subtitle: String,
    poster: String?,
    active: Boolean,
    position: RailPosition,
    isNew: Boolean,
    reduceMotion: Boolean,
    onClick: () -> Unit,
) {
    val segment = remember(isNew) { Animatable(if (isNew) 0f else 1f) }
    val nodeScale = remember(isNew) { Animatable(if (isNew) NodeArrivalScale else 1f) }

    LaunchedEffect(isNew, reduceMotion) {
        if (!isNew) return@LaunchedEffect
        if (reduceMotion) {
            segment.snapTo(1f)
            nodeScale.snapTo(1f)
            return@LaunchedEffect
        }
        segment.animateTo(1f, pickMotion(MotionToken.UI_SWEEP, reduceMotion = false))
        nodeScale.animateTo(1f, pickMotion(MotionToken.UI_MICRO, reduceMotion = false))
    }

    val drawsUp = position != RailPosition.First && position != RailPosition.Only
    val drawsDown = position != RailPosition.Last && position != RailPosition.Only
    val nodeFill = if (active) ThemeColor.accent else ThemeColor.surfaceFlat

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .drawBehind {
                val x = RailX.toPx()
                val half = size.height / 2f
                val stroke = RailStroke.toPx()
                val grown = segment.value

                if (drawsUp) {
                    drawRect(
                        color = ThemeColor.strokeStrong,
                        topLeft = Offset(x - stroke / 2f, 0f),
                        size = Size(stroke, half),
                    )
                }
                if (drawsDown) {
                    // The `+ rowGap` overshoot is what keeps the line continuous between cards.
                    val length = (size.height - half + RailRowGap.toPx()) * grown
                    drawRect(
                        color = ThemeColor.strokeStrong,
                        topLeft = Offset(x - stroke / 2f, half),
                        size = Size(stroke, length),
                    )
                }

                val radius = RailNode.toPx() / 2f * nodeScale.value
                if (active) {
                    drawCircle(
                        color = ThemeColor.accentSoft,
                        radius = RailNodeHalo.toPx() / 2f * nodeScale.value,
                        center = Offset(x, half),
                    )
                }
                drawCircle(color = nodeFill, radius = radius, center = Offset(x, half))
                if (!active) {
                    drawCircle(
                        color = ThemeColor.textTertiary,
                        radius = radius,
                        center = Offset(x, half),
                        style = Stroke(RailNodeStroke.toPx()),
                    )
                }
            }
            .padding(start = CardX),
    ) {
        HistoryCard(
            title = title,
            subtitle = subtitle,
            poster = poster,
            active = active,
            onClick = onClick,
        )
    }
}

/** The card: artwork, what the session is called, its line, and the way in. */
@Composable
private fun HistoryCard(
    title: String,
    subtitle: String,
    poster: String?,
    active: Boolean,
    onClick: () -> Unit,
) {
    val spoken = "$title, $subtitle"
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = RailMinRowHeight)
            .clickable(
                interactionSource = null,
                indication = PressStyle.row(ThemeRadius.row),
                role = Role.Button,
                onClick = onClick,
            )
            .semantics(mergeDescendants = true) {
                contentDescription = spoken
                if (active) stateDescription = Copy.Rewatch.ACTIVE
            }
            .surface(SurfaceLevel.Raised, ThemeRadius.row)
            .then(
                // Here the colour IS the state, and the ring is the only thing separating this card
                // from its identical neighbours.
                if (active) {
                    Modifier.border(
                        width = ThemeMetrics.hairline,
                        color = ThemeColor.accent.copy(alpha = ActiveRingAlpha),
                        shape = ContinuousCornerShape(ThemeRadius.row),
                    )
                } else {
                    Modifier
                },
            )
            .padding(horizontal = HistoryCardInsetX, vertical = HistoryCardInsetY),
        horizontalArrangement = Arrangement.spacedBy(ThemeSpace.x3),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        PosterSlot(url = poster, slot = PosterSize.Queue)
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(ThemeSpace.x0_5),
        ) {
            BasicText(
                text = title,
                style = ThemeType.body.copy(color = ThemeColor.textPrimary),
                maxLines = 2,
            )
            BasicText(
                text = subtitle,
                style = ThemeType.metadata.copy(color = ThemeColor.textSecondary),
                maxLines = 2,
            )
        }
        Spacer(Modifier.width(ThemeSpace.x2))
        SymbolIcon(PreviouslyIcons.ChevronRight, ThemeColor.textTertiary, HistoryChevronGlyph)
    }
}

private val HistoryCardInsetX = 14.dp
private val HistoryCardInsetY = ThemeSpace.x3
private val HistoryChevronGlyph = 13.dp

// ─────────────────────────────────────────────────────────────────────────────
// Surface E — one session
// ─────────────────────────────────────────────────────────────────────────────

/**
 * One session, as a SUMMARY and not a form.
 *
 * *"The sheet used to open on four label/value rows with no artwork, no title and no indication of
 * which show it belonged to — and 'Status: Completed' sat directly above 'Completed: 29 Jul', so
 * the word was both a value and a field label in adjacent rows while proving nothing the completion
 * date did not already prove."*
 *
 * What is left is: the identity block (with the state as a FACT on it), the ONE genuinely editable
 * row, the two non-destructive verbs a running session needs, and the destructive one in its own
 * plate at the bottom.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SessionDetailSheet(
    session: WatchSession,
    franchise: Franchise?,
    appModel: AppModel,
    onDismiss: () -> Unit,
) {
    val now = appModel.now
    val sheetState = rememberModalBottomSheetState()
    var startDate by remember(session.id) {
        mutableStateOf(session.startedAt?.takeIf { it > 0 } ?: now)
    }
    var picking by remember { mutableStateOf(false) }
    var prompt by remember { mutableStateOf<WritePrompt?>(null) }

    val stoppedAt = stoppedAtEpisode(session, franchise)

    PreviouslyMaterialBridge {
        ModalBottomSheet(
            onDismissRequest = onDismiss,
            sheetState = sheetState,
            containerColor = ThemeColor.canvasRaised,
            scrimColor = ThemeColor.scrimStrong,
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = ThemeMetrics.gutter)
                    .padding(top = ThemeSpace.x2, bottom = ThemeSpace.x6),
                verticalArrangement = Arrangement.spacedBy(ThemeMetrics.sectionGap),
            ) {
                // The sheet's own bar. `Done` commits the one editable value and closes.
                Box(Modifier.fillMaxWidth()) {
                    BasicText(
                        text = session.title,
                        style = ThemeType.bodyEmphasis.copy(color = ThemeColor.textPrimary),
                        maxLines = 1,
                        modifier = Modifier
                            .align(Alignment.Center)
                            .semantics { heading() },
                    )
                    TertiaryButton(
                        label = Copy.Action.done,
                        onClick = {
                            if (startDate != session.startedAt) {
                                RewatchStore.setStartDate(session.id, to = startDate)
                            }
                            onDismiss()
                        },
                        modifier = Modifier.align(Alignment.CenterEnd),
                    )
                }

                SessionIdentity(
                    session = session,
                    franchise = franchise,
                    now = now,
                )

                GroupedList {
                    GroupedRow(
                        title = Copy.Rewatch.STARTED,
                        trailing = GroupedTrailing.Value(
                            TemporalCopy.dateWord(startDate, now, Formatting.TimeAnchor.LOCAL),
                        ),
                        separator = (session.completedAt ?: 0L) > 0L,
                        onClick = { picking = true },
                    )
                    // `Finished` keeps its row — a date is a fact with a value, which is what a
                    // form row is for. The "Status" row that used to sit here is gone: it stated
                    // what the identity block now states, and it was the fake-editable pill.
                    session.completedAt?.takeIf { it > 0 }?.let { completed ->
                        GroupedRow(
                            title = Copy.Rewatch.FINISHED,
                            trailing = GroupedTrailing.Value(
                                TemporalCopy.dateWord(completed, now, Formatting.TimeAnchor.LOCAL),
                            ),
                            separator = false,
                        )
                    }
                }

                // ENDING a session, which the sheet never offered: a user who abandoned a rewatch
                // at episode 26 could only DESTROY the record, leaving the "In progress" badge and
                // the rail's accent ring lit for ever. Two non-destructive verbs, above the
                // destructive plate, where the system puts them.
                if (session.isActive) {
                    GroupedList {
                        GroupedRow(
                            title = Copy.Action.markRewatchComplete,
                            separator = true,
                            onClick = {
                                FeedbackCoordinator.fire(FeedbackToken.SUCCESS)
                                RewatchStore.complete(session.id, at = now)
                                onDismiss()
                            },
                        )
                        GroupedRow(
                            title = Copy.Action.stopRewatch,
                            separator = false,
                            onClick = {
                                prompt = WritePrompt(
                                    title = Copy.Rewatch.STOP_TITLE,
                                    message = Copy.Rewatch.stopMessage(stoppedAt),
                                    confirm = Copy.Rewatch.STOP_CONFIRM,
                                    destructive = true,
                                ) {
                                    FeedbackCoordinator.fire(FeedbackToken.DESTRUCTIVE)
                                    RewatchStore.cancel(session.id, atEpisode = stoppedAt, at = now)
                                    onDismiss()
                                }
                            },
                        )
                    }
                }

                DestructiveRow(label = Copy.Action.deleteThisSession) {
                    prompt = WritePrompt(
                        title = Copy.Confirm.deleteSessionTitle,
                        message = Copy.Confirm.deleteSession(session.episodes),
                        confirm = Copy.Confirm.deleteSessionConfirm,
                        destructive = true,
                    ) {
                        FeedbackCoordinator.fire(FeedbackToken.DESTRUCTIVE)
                        RewatchStore.delete(session.id)
                        onDismiss()
                    }
                }
            }
        }
    }

    WritePromptDialog(prompt = prompt, onDismiss = { prompt = null })

    if (picking) {
        SessionDatePicker(
            initial = startDate,
            onDismiss = { picking = false },
            onPick = {
                picking = false
                startDate = it
            },
        )
    }
}

/**
 * The identity block: which show, what the session covered, when it ran, and — as a FACT rather
 * than a form row — what state it is in.
 */
@Composable
private fun SessionIdentity(
    session: WatchSession,
    franchise: Franchise?,
    now: Long,
) {
    val status = when {
        session.isActive -> Copy.Rewatch.IN_PROGRESS
        session.cancelledAtEpisode != null -> Copy.Rewatch.STOPPED
        else -> null
    }

    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(ThemeMetrics.artGap),
        verticalAlignment = Alignment.Top,
    ) {
        PosterSlot(url = franchise?.portraitArt, slot = PosterSize.Row)
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(ThemeMetrics.titleGap),
        ) {
            BasicText(
                text = franchise?.title ?: session.title,
                style = ThemeType.showTitleM.copy(color = ThemeColor.textPrimary),
                maxLines = 2,
            )
            // The SCOPE, not the session's own name: the sheet's title already says "Second watch".
            BasicText(
                text = scopeLine(session, franchise) ?: session.title,
                style = ThemeType.heroMeta.copy(color = ThemeColor.textSecondary),
                maxLines = 2,
            )
            BasicText(
                text = spanLine(session, now),
                style = ThemeType.metadata.copy(color = ThemeColor.textTertiary),
                maxLines = 2,
            )
            if (status != null) {
                BasicText(
                    text = status,
                    style = ThemeType.rowMetaLead.copy(
                        // Amber is legal here: a running session is a real next step.
                        color = if (session.isActive) ThemeColor.accent else ThemeColor.textSecondary,
                    ),
                    maxLines = 1,
                )
            }
        }
    }
}

/**
 * [sessionLine]'s tail **without the start date**: while the session is running the start date is
 * not stated here, *"because the row below is a date picker showing exactly that date, and 'Started
 * 22 Aug 2026' was printed twice, 100–150 pt apart, in one sheet."*
 */
private fun spanLine(session: WatchSession, now: Long): String {
    val count = when {
        session.episodes <= 0 -> null
        session.isCompleted -> Copy.episodesWatched(session.episodes)
        else -> Copy.episodes(session.episodes)
    }
    val bits = listOfNotNull(sessionSpan(session, now), count)
    return if (bits.isEmpty()) Copy.Progress.datesUnknown else bits.joinToString(" · ")
}

/** Where a stopped session stopped: the progress of the part it covers. */
private fun stoppedAtEpisode(session: WatchSession, franchise: Franchise?): Int =
    when (val scope = session.scope) {
        is WatchSession.Scope.Franchise -> franchise?.currentPart?.progress ?: 0
        is WatchSession.Scope.Part ->
            franchise?.parts?.firstOrNull { it.mediaId == scope.mediaId }?.progress ?: 0
    }

/**
 * A destructive verb is a ROW IN ITS OWN PLATE, not a red word floating centred under a void.
 *
 * Hand-drawn rather than a `GroupedRow`, which has no destructive ink — the same reason Profile's
 * rows are their own primitive.
 */
@Composable
private fun DestructiveRow(label: String, onClick: () -> Unit) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .surface(SurfaceLevel.Plate, ThemeRadius.row)
            .clickable(
                interactionSource = null,
                indication = PressStyle.groupedRow,
                role = Role.Button,
                onClick = onClick,
            )
            .heightIn(min = ThemeMetrics.rowCompact)
            .padding(horizontal = HistoryCardInsetX),
        contentAlignment = Alignment.CenterStart,
    ) {
        BasicText(
            text = label,
            style = ThemeType.body.copy(color = ThemeColor.destructive),
            maxLines = 1,
        )
    }
}

/**
 * The date picker, bounded to today or earlier — the port of iOS's `in: ...Date()`.
 *
 * Android's reflex is a dialog rather than an inline wheel. It duplicates the private
 * `RewatchDatePicker` in `DetailScreen.kt`; **when either file is next opened, hoist one of them**
 * — two date pickers in one area is exactly the "two grammars for one thing" defect the design
 * system exists to prevent.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SessionDatePicker(initial: Long, onDismiss: () -> Unit, onPick: (Long) -> Unit) {
    val today = remember { System.currentTimeMillis() }
    val pickerState = rememberDatePickerState(
        initialSelectedDateMillis = initial,
        selectableDates = remember(today) {
            object : SelectableDates {
                override fun isSelectableDate(utcTimeMillis: Long): Boolean = utcTimeMillis <= today
            }
        },
    )
    PreviouslyMaterialBridge {
        DatePickerDialog(
            onDismissRequest = onDismiss,
            colors = DatePickerDefaults.colors(containerColor = ThemeColor.canvasRaised),
            confirmButton = {
                TertiaryButton(
                    label = Copy.Action.done,
                    onClick = {
                        // The picker answers in UTC midnight; the session's day is a LOCAL fact, so
                        // the picked calendar day is re-read locally rather than stored as the
                        // instant the picker returned.
                        onPick(localMidnight(pickerState.selectedDateMillis ?: initial))
                    },
                )
            },
            dismissButton = {
                TertiaryButton(label = Copy.Action.cancel, onClick = onDismiss)
            },
        ) {
            DatePicker(state = pickerState)
        }
    }
}

/** The picked UTC day, as that same calendar day at local midnight. */
private fun localMidnight(utcMillis: Long): Long {
    val utc = Calendar.getInstance(TimeZone.getTimeZone("UTC")).apply {
        timeInMillis = utcMillis
    }
    return Calendar.getInstance().apply {
        clear()
        set(
            utc.get(Calendar.YEAR),
            utc.get(Calendar.MONTH),
            utc.get(Calendar.DAY_OF_MONTH),
        )
    }.timeInMillis
}
