package com.anitrack.app.ui.today

import android.content.Context
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorProducer
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInWindow
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.zIndex
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.findViewTreeLifecycleOwner
import com.anitrack.app.AppModel
import com.anitrack.app.data.SyncCenter
import com.anitrack.app.data.UndoState
import com.anitrack.app.data.auth.AccountIdentity
import com.anitrack.app.design.ContinuousCornerShape
import com.anitrack.app.design.LocalReduceMotion
import com.anitrack.app.design.brand.AccountDisc
import com.anitrack.app.design.brand.PreviouslyMark
import com.anitrack.app.design.PosterSize
import com.anitrack.app.design.PreviouslyMaterialBridge
import com.anitrack.app.design.ShadowToken
import com.anitrack.app.design.ThemeColor
import com.anitrack.app.design.ThemeMetrics
import com.anitrack.app.design.ThemeMotion
import com.anitrack.app.design.ThemeRadius
import com.anitrack.app.design.ThemeSpace
import com.anitrack.app.design.ThemeType
import com.anitrack.app.design.shadowToken
import com.anitrack.app.ui.AutoSizeText
import com.anitrack.app.ui.art.ArtBackdrop
import com.anitrack.app.ui.art.PosterSlot
import com.anitrack.app.ui.card.ShelfCard
import com.anitrack.app.ui.chrome.BottomScrollEdgeChrome
import com.anitrack.app.ui.chrome.TopScrollEdgeChrome
import com.anitrack.app.ui.chrome.LocalCanUseMaterial
import com.anitrack.app.ui.chrome.chromeHazeSource
import com.anitrack.app.ui.chrome.tabBarContentBottom
import com.anitrack.app.ui.control.InlineLink
import com.anitrack.app.ui.control.InlineLinkButton
import com.anitrack.app.ui.control.MarkRing
import com.anitrack.app.ui.control.MarkRingStyle
import com.anitrack.app.ui.control.PressStyle
import com.anitrack.app.ui.control.minimumTapTarget
import com.anitrack.app.ui.control.TertiaryButton
import com.anitrack.app.ui.hero.reportHeight
import com.anitrack.app.ui.isAccessibilityTextSize
import com.anitrack.app.ui.library.PreviouslyPullToRefresh
import com.anitrack.app.ui.row.MediaRow
import com.anitrack.app.ui.scroll.ScrollOffset
import com.anitrack.app.ui.scroll.past
import com.anitrack.app.ui.scroll.rememberScrollOffset
import com.anitrack.app.ui.scroll.track
import com.anitrack.app.ui.section.SectionHeaderRow
import com.anitrack.app.ui.shell.LocalDebugLaunch
import com.anitrack.app.ui.state.EmptyState
import com.anitrack.app.ui.state.HandoffUndo
import com.anitrack.app.ui.state.InlineNotice
import com.anitrack.app.ui.state.SkeletonBlock
import com.anitrack.app.ui.state.SkeletonGate
import com.anitrack.app.ui.state.SkeletonLine
import com.anitrack.app.ui.state.SkeletonRow
import com.anitrack.app.ui.state.SkeletonShelf
import com.anitrack.app.ui.state.centredState
import com.anitrack.app.ui.state.rememberScreenReaderEnabled
import com.anitrack.model.Franchise
import com.anitrack.model.FranchisePart
import com.anitrack.model.FranchiseSummary
import com.anitrack.model.ShelfState
import com.anitrack.model.ShelfWindows
import com.anitrack.model.TemporalCopy
import com.anitrack.model.WatchStatus
import com.anitrack.model.canonicalLabel
import com.anitrack.model.copy.Copy
import com.anitrack.model.copy.EmptyStateCopy
import com.anitrack.model.dayDiff
import com.anitrack.model.displayTitle
import com.anitrack.model.effectiveStatus
import com.anitrack.model.lastAired
import com.anitrack.model.markTarget
import com.anitrack.model.nextAiring
import com.anitrack.model.portraitArt
import com.anitrack.model.releasingPart
import com.anitrack.model.resumePart
import com.anitrack.model.timeAnchor
import com.anitrack.model.tracksAirings
import com.anitrack.model.watchContext
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.abs

// =====================================================================================
// TODAY — the flagship surface, and the only screen in the product whose job is URGENCY
// ("here is the thing to watch right now").
//
// The port of `ios/Sources/Features/Today/TodayView.swift` (spec/today.md).
//
//   [billboard hero]   72 % of the screen: the slate, and at most one action
//   [Next up]          a two-row queue of what else is waiting
//   [Upcoming]         not-yet-aired episodes — one row under a busy screen, three under a calm one
//   [Watching]         a poster shelf
//
// Four top-level states share the frame: the hero, the trending billboard (an empty
// account), a calm caught-up headline, and a whole-screen failure card. Everything here is
// DERIVED from `AppModel` feeds and model computations; this file owns timing state and —
// critically — **never the scroll offset**.
//
// ## The performance architecture (read before changing anything)
//
// The raw offset held as screen state re-ran Today's entire body — the stack, the queue,
// the shelf, every row — at 60–120 Hz on the first swipe ("Today lags", reported twice).
// So: `ScrollOffset` quantises and de-duplicates, and **only `TodayVeils` reads `.y`**,
// inside a `graphicsLayer` lambda or a `derivedStateOf`. Two more values are written from
// layout — the hero copy's height, and whether it has passed under the bar — and both are
// guarded so they publish only on a real change.
//
// **There is no mask on the scroll content.** An earlier build masked it to fade under the
// wordmark; it cost a full-screen offscreen pass every frame and it erased the show's name.
// The opaque bar covers what passes under the band instead.
// =====================================================================================

/**
 * @param identity the account's display identity — the header's disc, and nothing else.
 * @param onOpenDetail push the show page on **this tab's** stack.
 * @param onSeeAllWatching Library, filtered to Watching.
 * @param onViewAllUpdates Library, filtered `status: null, unwatchedOnly: true` — deliberately a
 *   DIFFERENT destination from the shelf's "See all", because the count it names is `outNow` (any
 *   status). Both used to switch to the Library root, so a link that names a set ("all 40 updates")
 *   landed on a list that does not show it.
 * @param onAddShow the Discover tab, with the search field requested.
 */
@Composable
fun TodayScreen(
    appModel: AppModel,
    identity: AccountIdentity,
    onOpenDetail: (String) -> Unit,
    onSeeAllWatching: () -> Unit,
    onViewAllUpdates: () -> Unit,
    onAddShow: () -> Unit,
    onOpenProfile: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val view = LocalView.current
    val scope = rememberCoroutineScope()
    val reduceMotion = LocalReduceMotion.current
    val isAX = isAccessibilityTextSize()
    val announce = rememberAnnouncer()
    val topInset = ThemeMetrics.topSafeInset()
    val band = topInset + HeaderBandHeight

    // Debug launch arguments — iOS's `-recapDemo 1` / `-calmDemo 1` / `-openProfile 1`, which the
    // platform folds into `NSUserDefaults`. On Android they are intent extras, resolved once by the
    // shell and published to the tree; each flag is read by the screen that owns the state it poses.
    // `DebugLaunch.from` is gated on `BuildConfig.DEBUG`, a compile-time constant, so a release
    // build parses nothing and R8 deletes everything only this reaches.
    val debug = LocalDebugLaunch.current
    val recapDemo = debug.recapDemo
    val calmDemo = debug.calmDemo
    val openProfileOnAppear = debug.openProfile

    val scroll = rememberScrollOffset()
    val scrollState = rememberScrollState()
    scroll.track(scrollState)

    val recap = rememberRecapController(demo = recapDemo)
    val marks = remember { MarkTimeline() }

    // Measured geometry. Both are written from layout and both are guarded: the height only moves
    // when the copy really changes shape, and the boolean only on the crossing.
    var heroCopyHeight by remember { mutableStateOf(0.dp) }
    var heroCopyUnderBand by remember { mutableStateOf(false) }

    // ---------------------------------------------------------------------------------
    // Feeds. All derived; nothing here fetches.
    // ---------------------------------------------------------------------------------

    val now = appModel.now
    val library = appModel.library
    val justCaught = appModel.justCaught

    // `-calmDemo 1` empties the stack by force, so the calm open renders on a library that still
    // has backlog.
    val feed = if (calmDemo) emptyList() else liveItems(appModel)
    // A snapshot of the feed, pinned for the 650 ms a mark holds, so the card keeps describing the
    // show it just wrote to even though the live feed has already moved on.
    val items = marks.pinned ?: feed
    val actionable = items.mapNotNull { f -> focusKind(f, now, justCaught)?.let { f to it } }

    val calmHero = if (actionable.isEmpty() && !appModel.libraryEmpty) {
        appModel.nextUp ?: appModel.watchingShelf.firstOrNull()
    } else {
        null
    }
    val heroFranchise = actionable.firstOrNull()?.first ?: calmHero
    val heroKind = actionable.firstOrNull()?.second ?: calmHero?.let { calmFocusKind(it, now) }

    val queue = actionable.drop(1).take(QUEUE_COUNT)
    val stackIds = actionable.take(3).map { it.first.id }.toSet() + setOfNotNull(calmHero?.id)
    val updateCount = appModel.outNow.size
    val showsViewAll = updateCount > VIEW_ALL_THRESHOLD

    val upcoming = upcomingRows(library, stackIds, now, limit = if (actionable.isEmpty()) 3 else 1)
    val shelf = watchingShelf(appModel, stackIds)
    val shelfIsList = isAX || shelf.size < SHELF_MINIMUM_CARDS
    val comingNext = appModel.nextUp?.takeIf { !stackIds.contains(it.id) }

    // ---------------------------------------------------------------------------------
    // The top-block state machine
    // ---------------------------------------------------------------------------------

    val isFailed = appModel.loadError && appModel.libraryEmpty
    val isEmptyAccount = !appModel.loading && appModel.libraryEmpty && !appModel.loadError
    val showsHero = !appModel.libraryEmpty && !isFailed &&
        (heroFranchise != null || (recap.onStage && recap.digest != null))
    // Measured, never thresholded. `scrollY > 150` was calibrated against a tall library and never
    // tripped on a compact one — a short Today parks at ~92 dp of scroll with the title already
    // under the band, so the show's name was erased and the wordmark never took it over.
    val headerCarriesTitle = showsHero && !recap.onStage && heroFranchise != null && heroCopyUnderBand

    val trendingLead = appModel.trending.firstOrNull()
    val art = heroArt(heroFranchise, recap.digest?.beats?.firstOrNull()?.cover)
    val heroTint = rememberHeroTint(art.url) { TodayHeroTint.save(context, it) }

    // ---------------------------------------------------------------------------------
    // Lifecycle
    // ---------------------------------------------------------------------------------

    LaunchedEffect(Unit) {
        if (openProfileOnAppear) onOpenProfile()
    }

    // `evaluate` guards itself to once per visit; keying on `loading` is iOS's `.onAppear` plus its
    // `.onChange(of: loading)` in one place.
    LaunchedEffect(appModel.loading, library.size) {
        recap.evaluate(library, appModel.prevOpenedAt, appModel.now, appModel.loading)
    }

    // The reveal/hold clock only starts once the surface is actually visible — a recap that plays
    // behind the splash is a recap nobody saw.
    val screenReaderOn = rememberScreenReaderEnabled()
    LaunchedEffect(recap.onStage, appModel.surfaceReady) {
        if (!recap.shouldStartClock(appModel.surfaceReady)) return@LaunchedEffect
        recap.noteClockStarted()
        delay(RecapTiming.REVEAL_DELAY_MILLIS)
        recap.reveal()
        recap.digest?.let { announce(recapSpokenSummary(it, appModel.now)) }
        // **A screen reader NEVER auto-dismisses**: a user got roughly one element spoken before the
        // card was removed from the tree. The card waits for Continue.
        if (screenReaderOn) return@LaunchedEffect
        delay(RecapTiming.holdMillis(recap.digest?.beats?.size ?: 1, reduceMotion))
        recap.handoff()
    }

    LaunchedEffect(appModel.libraryEmpty) {
        if (appModel.libraryEmpty) appModel.loadTrendingIfNeeded()
    }

    // A pull-to-refresh is a state change with no visible focus move, so a screen reader was told
    // nothing at all while it ran.
    LaunchedEffect(appModel.isRefreshing) {
        if (appModel.isRefreshing) announce(Copy.Accessibility.refreshing)
    }

    // Leaving the screen — or backgrounding the app — retires the strip and banks its
    // acknowledgement, so it does not reappear on the next open as though it were new.
    DisposableEffect(view, recap) {
        val lifecycle = view.findViewTreeLifecycleOwner()?.lifecycle
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_STOP) recap.clearStrip()
        }
        lifecycle?.addObserver(observer)
        onDispose {
            lifecycle?.removeObserver(observer)
            recap.clearStrip()
        }
    }

    // ---------------------------------------------------------------------------------
    // Writes
    // ---------------------------------------------------------------------------------

    var batchPrompt by remember { mutableStateOf<BatchPrompt?>(null) }

    /** The hero's mark: the card keeps the show it wrote to, then hands over. */
    fun markHero(f: Franchise) {
        // No tap can land on a card that is still arriving. Without this guard the hero is a trap:
        // the committed state clears at 650 ms and the next show's card fades in over ~460 ms with
        // its button already hit-testable at partial opacity, so a user clearing three episodes has
        // tap 2 swallowed and tap 3 land on a button belonging to a *different franchise* — the
        // write goes to the wrong show, and the single Undo toast only covers the most recent one.
        if (marks.committedEpisode != null || marks.handoffInFlight) return
        val snapshot = items
        // The haptic is fired inside the write. One per transaction, and the view never fires one.
        val undo = appModel.markNext(f.id) ?: return
        marks.settle(scope, appModel, snapshot, undo, reduceMotion, announce) { recap.clearStrip() }
    }

    fun markQueueRow(f: Franchise) {
        if (marks.committedQueue.contains(f.id)) return
        val undo = appModel.markNext(f.id) ?: return
        marks.committedQueue = marks.committedQueue + f.id
        // Immediate: unlike the hero there is no card handing over here.
        appModel.presentUndo(undo)
        announce(Copy.Progress.episodeWatched(undo.episode))
        scope.launch {
            delay(HandoffUndo.HOLD_MILLIS)
            marks.committedQueue = marks.committedQueue - f.id
        }
    }

    fun confirmBatch(prompt: BatchPrompt) {
        if (marks.committedEpisode != null || marks.handoffInFlight) return
        val snapshot = items
        // `markThrough`, not `setProgress`: it mints ONE undo carrying the true count and a
        // restoring closure. "Mark through episode N" used to call `setProgress`, which mints no
        // undo at all — so the app's most-used multi-episode control had no toast and no undo.
        val undo = appModel.markThrough(
            franchiseId = prompt.franchiseId,
            mediaId = prompt.mediaId,
            episode = prompt.through,
            present = false,
        ) ?: return
        marks.settle(scope, appModel, snapshot, undo, reduceMotion, announce) { recap.clearStrip() }
        announce(Copy.Confirm.batchMarkConfirm(prompt.count))
    }

    // ---------------------------------------------------------------------------------
    // The scaffold
    // ---------------------------------------------------------------------------------

    Box(modifier.fillMaxSize().background(ThemeColor.canvas)) {
        BoxWithConstraints(Modifier.fillMaxSize()) {
            val contentHeight = maxHeight

            // The platform's own pull, through the app's one wrapper: it owns the arm-at-threshold
            // haptic, the re-arm floor and the Material bridge, so four tab roots and this one
            // cannot drift into four pulls. Today draws no `RefreshIndicator` of its own — its bar
            // is the wordmark and has no spinner slot — so nothing consumes the driving flag.
            PreviouslyPullToRefresh(
                onRefresh = { appModel.reload() },
                onDrivingChange = {},
                modifier = Modifier.fillMaxSize(),
            ) {
                // The ambient wash belongs to the states that have no billboard; a hero replaces it
                // outright. One spec app-wide — never a private height/intensity pair.
                if (!showsHero) {
                    val washArt = appModel.nextUp?.portraitArt
                        ?: appModel.watchingShelf.firstOrNull()?.portraitArt
                        ?: library.firstOrNull()?.portraitArt
                    ArtBackdrop(
                        modifier = Modifier.align(Alignment.TopCenter),
                        url = washArt,
                        // No artwork anywhere: first run gets the app's own colour rather than a
                        // grey band.
                        tint = if (washArt == null) ThemeColor.accent else null,
                    )
                }

                Column(
                    Modifier
                        .fillMaxSize()
                        .verticalScroll(scrollState)
                        // The backdrop the chrome bands blur. One source per screen, on the scroll
                        // container, never per item.
                        .chromeHazeSource(),
                ) {
                    SkeletonGate(
                        isLoading = appModel.loading && appModel.libraryEmpty,
                        skeleton = { TodaySkeleton(isAX = isAX) },
                    ) {
                        Column(Modifier.fillMaxWidth()) {
                            // ---- the top block, in this exact order ----
                            when {
                                isFailed -> StateBlock(
                                    // `isOnline`, not the error, decides which sentence is true.
                                    copy = if (SyncCenter.isOnline) {
                                        EmptyStateCopy.serverNoCache
                                    } else {
                                        EmptyStateCopy.offlineNoData
                                    },
                                    contentHeight = contentHeight,
                                    band = band,
                                    onPrimary = { scope.launch { appModel.reload() } },
                                )

                                isEmptyAccount && trendingLead != null -> TrendingBillboard(
                                    item = trendingLead,
                                    owned = appModel.isInLibrary(trendingLead.id),
                                    heroCopyHeight = heroCopyHeight,
                                    band = band,
                                    reduceMotion = reduceMotion,
                                    onCopyHeight = { if (it != heroCopyHeight) heroCopyHeight = it },
                                    onOpen = { onOpenDetail(trendingLead.id) },
                                    onAdd = {
                                        appModel.addToLibrary(
                                            franchiseId = trendingLead.id,
                                            title = trendingLead.title,
                                            isReleasing = trendingLead.isReleasing,
                                            source = trendingLead.source,
                                        )
                                    },
                                )

                                // The skeleton holds while the chart loads, rather than flashing
                                // "Nothing to watch yet" for the ~300 ms before the billboard lands.
                                isEmptyAccount && appModel.trendingLoading -> TodaySkeleton(isAX = isAX)

                                isEmptyAccount -> StateBlock(
                                    // `emptyToday`, not `emptyAccount`: the latter is LIBRARY's
                                    // string, and a state may not title itself after a tab the user
                                    // is not looking at.
                                    copy = EmptyStateCopy.emptyToday,
                                    contentHeight = contentHeight,
                                    band = band,
                                    onPrimary = onAddShow,
                                    behind = { EmptyFan(appModel.trending) },
                                )

                                showsHero -> Hero(
                                    franchise = heroFranchise,
                                    kind = heroKind,
                                    recap = recap,
                                    library = library,
                                    appModel = appModel,
                                    marks = marks,
                                    art = art,
                                    tint = heroTint,
                                    heroCopyHeight = heroCopyHeight,
                                    band = band,
                                    contentHeight = contentHeight,
                                    reduceMotion = reduceMotion,
                                    onCopyHeight = { if (it != heroCopyHeight) heroCopyHeight = it },
                                    onCopyUnderBand = {
                                        if (it != heroCopyUnderBand) heroCopyUnderBand = it
                                    },
                                    onOpenDetail = onOpenDetail,
                                    onMark = ::markHero,
                                    onPromptBatch = { batchPrompt = it },
                                )

                                else -> CalmBlock(comingNext = comingNext, now = now, band = band)
                            }

                            // ---- below the fold ----
                            // NOT removed while the recap is on stage: the recap is the hero's
                            // contents, not a takeover. Hiding the rest left ~110 dp of bare canvas
                            // above the tab bar and then re-inserted everything on a second curve
                            // when the recap handed off — the layout shove the handoff exists to
                            // avoid. It is FADED rather than left visible because the rows glowed
                            // through the gap between the recap's floor and the tab bar, reading as
                            // a translucent layering glitch.
                            val fold = animateFloatAsState(
                                targetValue = if (recap.onStage) 0f else 1f,
                                animationSpec = ThemeMotion.uiSettle(),
                                label = "belowTheFold",
                            )
                            Column(
                                Modifier
                                    .fillMaxWidth()
                                    .graphicsLayer { alpha = fold.value },
                            ) {
                                BelowTheFold(
                                    appModel = appModel,
                                    recap = recap,
                                    marks = marks,
                                    showsHero = showsHero,
                                    queue = queue,
                                    showsViewAll = showsViewAll,
                                    updateCount = updateCount,
                                    upcoming = upcoming,
                                    shelf = shelf,
                                    shelfIsList = shelfIsList,
                                    isEmptyAccount = isEmptyAccount,
                                    now = now,
                                    isAX = isAX,
                                    onOpenDetail = onOpenDetail,
                                    onSeeAllWatching = onSeeAllWatching,
                                    onViewAllUpdates = onViewAllUpdates,
                                    onAddShow = onAddShow,
                                    onRetry = { scope.launch { appModel.reload() } },
                                    onMarkQueueRow = ::markQueueRow,
                                )
                            }
                        }
                    }

                    // The scroll inset, as the last thing in the stack: a `verticalScroll` column
                    // has no `contentPadding`, and the clearance is `bottomChromeHeight` plus one
                    // gutter and only ever that.
                    Spacer(Modifier.height(tabBarContentBottom()))
                }
            }
        }

        TodayVeils(
            scroll = scroll,
            showsHero = showsHero,
            headerCarriesTitle = headerCarriesTitle,
            band = band,
        )

        TodayHeader(
            title = heroFranchise?.displayTitle.orEmpty(),
            carriesTitle = headerCarriesTitle,
            identity = identity,
            topInset = topInset,
            onOpenProfile = onOpenProfile,
        )

        BottomScrollEdgeChrome(Modifier.align(Alignment.BottomCenter))
    }

    batchPrompt?.let { prompt ->
        BatchMarkDialog(
            prompt = prompt,
            onDismiss = { batchPrompt = null },
            onConfirm = {
                batchPrompt = null
                confirmBatch(prompt)
            },
        )
    }
}

// -------------------------------------------------------------------------------------
// Feeds
// -------------------------------------------------------------------------------------

/**
 * The focus stack's order: **Watching outranks everything, then recency.**
 *
 * `outNow` orders purely by recency, which handed the hero to a show the user had marked
 * *completed* while five in-progress shows compressed into thumbnails below it. The recency key is
 * the **airings-advanced** `lastAired`, never the raw catalogue field, which put a days-old Slime
 * drop over the Re:ZERO episode that had struck 27 minutes earlier.
 */
private fun liveItems(appModel: AppModel): List<Franchise> {
    val now = appModel.now
    val live = appModel.outNow.sortedWith(
        compareByDescending<Franchise> { it.effectiveStatus == WatchStatus.WATCHING }
            .thenByDescending { it.lastAired(now) ?: 0L },
    )
    return live + appModel.keepWatching
}

/**
 * `Upcoming` — one row under a busy screen, three under a calm one.
 *
 * A passed AniList slot is kept alive for the day elsewhere; here it would be announced as future.
 * Date-only TV has no instant to test, so its whole day qualifies.
 */
private fun upcomingRows(
    library: List<Franchise>,
    stackIds: Set<String>,
    now: Long,
    limit: Int,
): List<Franchise> = library
    .mapNotNull { f ->
        if (!f.tracksAirings || stackIds.contains(f.id)) return@mapNotNull null
        val at = f.nextAiring(now) ?: return@mapNotNull null
        if (!f.timeAnchor.isDateOnly && at <= now) return@mapNotNull null
        f to at
    }
    .sortedBy { it.second }
    .take(limit)
    .map { it.first }

/**
 * The Watching shelf, with the honest-count fallback.
 *
 * `watchingShelf` is already narrowed by a live-claim predicate, and removing the stack narrows it
 * again — on a 9-show library that left ONE card in 340 dp of dead black under a "See all", while
 * the loading skeleton four seconds earlier had promised four cards running off the right edge. A
 * horizontal shelf that does not reach its trailing edge gives no reason to swipe and reads as
 * artwork that failed to load.
 */
private fun watchingShelf(appModel: AppModel, stackIds: Set<String>): List<Franchise> {
    val claimed = appModel.watchingShelf.filter { !stackIds.contains(it.id) }
    if (claimed.size >= SHELF_MINIMUM_CARDS) return claimed.take(SHELF_LIMIT)
    val everything = appModel.library.filter {
        it.effectiveStatus == WatchStatus.WATCHING && !stackIds.contains(it.id)
    }
    return (claimed + everything).distinctBy { it.id }.take(SHELF_LIMIT)
}

// -------------------------------------------------------------------------------------
// The hero
// -------------------------------------------------------------------------------------

@Composable
private fun Hero(
    franchise: Franchise?,
    kind: Pair<FocusKind, FranchisePart>?,
    recap: TodayRecapController,
    library: List<Franchise>,
    appModel: AppModel,
    marks: MarkTimeline,
    art: HeroArt,
    tint: Color?,
    heroCopyHeight: Dp,
    band: Dp,
    contentHeight: Dp,
    reduceMotion: Boolean,
    onCopyHeight: (Dp) -> Unit,
    onCopyUnderBand: (Boolean) -> Unit,
    onOpenDetail: (String) -> Unit,
    onMark: (Franchise) -> Unit,
    onPromptBatch: (BatchPrompt) -> Unit,
) {
    val now = appModel.now
    val digest = recap.digest
    val onStage = recap.onStage && digest != null
    // The recap occupies the frame minus a floor that clears the bottom chrome's WHOLE ramp, not
    // just the bar: at 96 dp the card's Continue control came to rest inside the veil and rendered
    // at a quarter of its ink.
    val height = if (onStage) {
        (contentHeight - RECAP_FLOOR).coerceAtLeast(0.dp)
    } else {
        heroHeight(heroCopyHeight)
    }
    // Resolved once, outside the layout callback that consumes it.
    val bandLimit = with(LocalDensity.current) { (band + BAND_TOLERANCE).toPx() }

    LaunchedEffect(recap.arrivesWithoutAnimation) {
        if (recap.arrivesWithoutAnimation) recap.animationsResume()
    }

    HeroFrame(
        height = height,
        art = art,
        tint = tint,
        // Only while the recap is on stage: its copy fills the frame and the whole image is meant
        // to step back.
        scrimBottom = if (onStage) RECAP_ART_SCRIM else 0f,
        copyHeight = heroCopyHeight,
        band = band,
        reduceMotion = reduceMotion,
        animateHeight = !recap.arrivesWithoutAnimation,
    ) {
        // Recap ⇄ focus, on the ONE card-replacement transition in the app: the outgoing card
        // leaves first (160 ms) and the incoming one settles into the space it left, delayed past
        // the removal. A symmetric crossfade renders two different show titles at 50 % on top of
        // each other, which is what a smear is.
        AnimatedContent(
            targetState = if (onStage) RECAP_CARD_KEY else franchise?.id.orEmpty(),
            transitionSpec = { ThemeMotion.handoff(reduceMotion) },
            modifier = Modifier.align(Alignment.BottomStart),
            label = "heroOverlay",
        ) { key ->
            if (key == RECAP_CARD_KEY && digest != null) {
                RecapArrival(
                    digest = digest,
                    library = library,
                    now = now,
                    revealed = recap.revealed,
                    reduceMotion = reduceMotion,
                    heroArtUrl = art.url,
                    tint = tint,
                    onContinue = { recap.handoff() },
                    onDismiss = { recap.dismiss() },
                )
            } else if (franchise != null && kind != null) {
                val part = kind.second
                val committed = marks.committedEpisode
                    ?.takeIf { marks.pinned?.firstOrNull()?.id == franchise.id }
                val slate = heroSlate(
                    f = franchise,
                    kind = kind.first,
                    part = part,
                    now = now,
                    committedEpisode = committed,
                    nextPremiere = appModel.nextPremiere(franchise),
                )
                HeroFocus(
                    slate = slate,
                    fullTitle = franchise.title,
                    committed = committed != null,
                    interactive = !marks.handoffInFlight,
                    onOpen = { onOpenDetail(franchise.id) },
                    onMark = { onMark(franchise) },
                    onMarkThrough = { through ->
                        onPromptBatch(batchPrompt(franchise, part, through))
                    },
                    // `markTarget`, **not** `progressCeiling`: the ceiling is `Int.MAX_VALUE` for an
                    // ongoing season with no published episode count, and for every other releasing
                    // season it is the season's SIZE — so "Mark all 6" would have written every
                    // unaired episode too.
                    onMarkAll = {
                        onPromptBatch(batchPrompt(franchise, part, part.markTarget(now)))
                    },
                    // Measured on the FOCUS card alone. During the recap's exit both cards are
                    // composed and the transition container is as tall as the taller of them, so
                    // measuring the container would hand the scrim — and the hero's own height
                    // formula — the recap's ~700 dp for the length of the shrink.
                    modifier = Modifier
                        .reportHeight(onCopyHeight)
                        .onGloballyPositioned { coordinates ->
                            onCopyUnderBand(coordinates.positionInWindow().y < bandLimit)
                        },
                )
            }
        }
    }
}

/** The trending billboard: same frame, same slate order, one capsule. */
@Composable
private fun TrendingBillboard(
    item: FranchiseSummary,
    owned: Boolean,
    heroCopyHeight: Dp,
    band: Dp,
    reduceMotion: Boolean,
    onCopyHeight: (Dp) -> Unit,
    onOpen: () -> Unit,
    onAdd: () -> Unit,
) {
    val art = heroArt(item)
    val tint = rememberHeroTint(art.url)
    HeroFrame(
        height = heroHeight(heroCopyHeight),
        art = art,
        tint = tint,
        scrimBottom = 0f,
        copyHeight = heroCopyHeight,
        band = band,
        reduceMotion = reduceMotion,
    ) {
        TrendingFocus(
            item = item,
            owned = owned,
            onOpen = onOpen,
            onAdd = onAdd,
            modifier = Modifier
                .align(Alignment.BottomStart)
                .reportHeight(onCopyHeight),
        )
    }
}

/**
 * The calm block — the residual case, reached only when even a waiting billboard is unavailable
 * (an empty `nextUp` **and** an empty Watching shelf).
 *
 * Three deliberate absences, each recording a defect: **no plate** (it used to be a boxed empty
 * state opening the app with "Nothing changed since you were last here" — an absence in empty-state
 * clothing on a populated screen), **no glyph** (an amber check disc in the wordmark's own column
 * read as a second lockup), and **`heroTitle`, not `showTitleL`** — a full step above the 20-sp
 * section headers under it, so this reads as the page's title and those read as its sections.
 */
@Composable
private fun CalmBlock(comingNext: Franchise?, now: Long, band: Dp) {
    val at = comingNext?.nextAiring(now)
    // The exact test the Upcoming row's "Today" word comes from, so the two can never disagree.
    val today = comingNext != null && at != null && comingNext.dayDiff(at, now) == 0
    Column(
        Modifier
            .fillMaxWidth()
            .padding(top = band + ThemeSpace.x8)
            .padding(horizontal = ThemeMetrics.gutter)
            .semantics(mergeDescendants = true) {},
        verticalArrangement = Arrangement.spacedBy(ThemeSpace.x2),
    ) {
        BasicText(
            text = if (today) Copy.Progress.newEpisodeToday else Copy.Progress.caughtUp,
            style = ThemeType.heroTitle,
            color = ColorProducer { ThemeColor.textPrimary },
        )
        if (comingNext == null) {
            BasicText(
                text = Copy.Progress.noNewDates,
                style = ThemeType.metadata,
                color = ColorProducer { ThemeColor.textSecondary },
            )
        }
    }
}

// -------------------------------------------------------------------------------------
// Below the fold
// -------------------------------------------------------------------------------------

/**
 * The section rhythm, and the one correction it depends on.
 *
 * **`rowOwnInset`**: `MediaRow` carries 8 dp of vertical padding *inside* its own minimum height,
 * so a container that then adds a full `labelGap` / `sectionGap` produces 8 dp more than the token
 * names — measured at 31 dp under a label whose token says 10, and 51–57 dp between sections whose
 * token says 30. **The container pays the token minus what the row already spends.**
 */
@Composable
private fun BelowTheFold(
    appModel: AppModel,
    recap: TodayRecapController,
    marks: MarkTimeline,
    showsHero: Boolean,
    queue: List<Pair<Franchise, Pair<FocusKind, FranchisePart>>>,
    showsViewAll: Boolean,
    updateCount: Int,
    upcoming: List<Franchise>,
    shelf: List<Franchise>,
    shelfIsList: Boolean,
    isEmptyAccount: Boolean,
    now: Long,
    isAX: Boolean,
    onOpenDetail: (String) -> Unit,
    onSeeAllWatching: () -> Unit,
    onViewAllUpdates: () -> Unit,
    onAddShow: () -> Unit,
    onRetry: () -> Unit,
    onMarkQueueRow: (Franchise) -> Unit,
) {
    val digest = recap.digest
    val strip = recap.showsStrip && digest != null
    val notice = appModel.loadError && !appModel.libraryEmpty
    val hasQueue = showsHero && (queue.isNotEmpty() || showsViewAll)

    val first = if (showsHero) {
        if (isAX) ThemeMetrics.heroClearance else ThemeSpace.x5
    } else {
        ThemeMetrics.sectionGap
    }
    val gap = ThemeMetrics.sectionGap
    val gapAfterRow = ThemeMetrics.sectionGap - ROW_OWN_INSET

    if (strip && digest != null) {
        RecapLine(
            text = recapStripText(digest, now),
            onOpen = { recap.stage() },
            modifier = Modifier
                // x3, not the section gap: the line is the hero's residue, and at full section
                // distance it floated in the dead zone between hero and queue, reading as a stray
                // debug print.
                .padding(top = if (showsHero) ThemeSpace.x3 else first)
                .padding(horizontal = ThemeMetrics.gutter),
        )
    }

    if (notice) {
        // A footnote line, never an alert box — the content loaded fine from the cache.
        InlineNotice(
            message = Copy.Notice.today,
            onRetry = onRetry,
            modifier = Modifier
                .padding(top = if (strip) ThemeMetrics.labelGap else first)
                .padding(horizontal = ThemeMetrics.gutter),
        )
    }

    if (hasQueue) {
        QueueSection(
            queue = queue,
            marks = marks,
            showsViewAll = showsViewAll,
            updateCount = updateCount,
            now = now,
            isAX = isAX,
            onOpenDetail = onOpenDetail,
            onViewAllUpdates = onViewAllUpdates,
            onMarkQueueRow = onMarkQueueRow,
            modifier = Modifier.padding(top = if (strip || notice) gap else first),
        )
    }

    if (upcoming.isNotEmpty()) {
        UpcomingSection(
            rows = upcoming,
            now = now,
            onOpenDetail = onOpenDetail,
            modifier = Modifier.padding(
                top = when {
                    hasQueue -> gapAfterRow
                    strip || notice -> gap
                    else -> first
                },
            ),
        )
    }

    if (shelf.isNotEmpty()) {
        WatchingShelf(
            appModel = appModel,
            shelf = shelf,
            asList = shelfIsList,
            now = now,
            onOpenDetail = onOpenDetail,
            onSeeAll = onSeeAllWatching,
            modifier = Modifier.padding(
                top = when {
                    hasQueue || upcoming.isNotEmpty() -> gapAfterRow
                    strip || notice -> gap
                    else -> first
                },
            ),
        )
    }

    // The rest of the chart, under the trending billboard.
    val chart = appModel.trending.drop(1).take(TRENDING_SHELF_LIMIT)
    if (isEmptyAccount && chart.isNotEmpty()) {
        TrendingShelf(
            items = chart,
            onOpenDetail = onOpenDetail,
            onAddShow = onAddShow,
            modifier = Modifier.padding(top = ThemeSpace.x5),
        )
    }
}

/** "Next up" — the two rows the hero did not take. */
@Composable
private fun QueueSection(
    queue: List<Pair<Franchise, Pair<FocusKind, FranchisePart>>>,
    marks: MarkTimeline,
    showsViewAll: Boolean,
    updateCount: Int,
    now: Long,
    isAX: Boolean,
    onOpenDetail: (String) -> Unit,
    onViewAllUpdates: () -> Unit,
    onMarkQueueRow: (Franchise) -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(modifier.fillMaxWidth()) {
        SectionHeaderRow(
            text = Copy.Label.nextUp,
            modifier = Modifier.padding(horizontal = ThemeMetrics.gutter),
        )
        Column(Modifier.padding(top = ThemeMetrics.labelGap - ROW_OWN_INSET)) {
            queue.forEachIndexed { index, entry ->
                val f = entry.first
                val kind = entry.second.first
                val part = entry.second.second
                val marked = marks.committedQueue.contains(f.id)
                // Drawn only where there is something to mark: a waiting or caught-up row carries
                // no control, because there is no episode for it to write.
                val markable = kind is FocusKind.Fresh || kind is FocusKind.Backlog
                val ring: (@Composable RowScope.() -> Unit)? = if (markable) {
                    {
                        MarkRing(
                            marked = marked,
                            onMark = { onMarkQueueRow(f) },
                            // A dense repeating list: twenty filled amber discs down one column
                            // would turn a rhythm into a scoreboard.
                            style = MarkRingStyle.Quiet,
                            episode = part.progress + 1,
                            label = "${Copy.Action.markAsWatched}, " +
                                "${f.watchContext(part, part.progress + 1)} of ${f.title}",
                        )
                    }
                } else {
                    null
                }
                MediaRow(
                    // The FULL title here, not `displayTitle`: a row is a list of things you own.
                    title = f.title,
                    onClick = { onOpenDetail(f.id) },
                    meta = queueMeta(f, kind, part, isAX),
                    lead = queueLead(f, kind, now),
                    poster = f.portraitArt,
                    slot = if (isAX) PosterSize.Row else PosterSize.TodayQueue,
                    // A disclosure indicator and a mark ring in the same column is two trailing
                    // affordances on one row.
                    chevron = false,
                    separator = index < queue.size - 1 || showsViewAll,
                    hint = Copy.Accessibility.opensTheShowHint,
                    trailing = ring,
                    modifier = Modifier.padding(horizontal = ThemeMetrics.gutter),
                )
            }

            if (showsViewAll) {
                InlineLinkButton(
                    label = Copy.Action.viewAllUpdates(updateCount),
                    onClick = onViewAllUpdates,
                    // The link holds its own 12-dp horizontal padding, so pull it back to start the
                    // word on the gutter.
                    modifier = Modifier.padding(start = ThemeMetrics.gutter - INLINE_LINK_INSET),
                )
            }
        }
    }
}

/**
 * The row's forward-looking TIME, in amber — and **only for today's drop**.
 *
 * An older one is a plain row: its ring already names the episode, and "Aired 28 Aug" in accent
 * spent the colour on a fact that is neither next nor now.
 */
private fun queueLead(f: Franchise, kind: FocusKind, now: Long): String? = when (kind) {
    is FocusKind.Fresh -> f.lastAired(now)
        ?.takeIf { now - it <= ShelfWindows.NOW_BAR_LIVE }
        ?.let { TemporalCopy.aired(it, now, f.source) }
    is FocusKind.Waiting -> TemporalCopy.airs(kind.at, now, f.source)
    else -> null
}

/**
 * The row's EPISODE IDENTITY and its counts, in grey.
 *
 * The row DROPS a fact rather than wrapping one. **13, not 22**: at 22 a two-season identity
 * ("Season 2 · Episode 2", 20 chars) still took the count and the assembled line overran the row's
 * ~240 dp, wrapping "… · 11 / episodes left" mid-phrase. 13 admits the single-part form
 * ("Episode 2") and nothing longer.
 */
private fun queueMeta(f: Franchise, kind: FocusKind, part: FranchisePart, isAX: Boolean): String {
    val episode = f.watchContext(part, part.progress + 1)
    val roomForCount = !isAX && episode.length <= QUEUE_META_COUNT_BUDGET
    return when (kind) {
        is FocusKind.Fresh ->
            if (kind.behind > 1 && roomForCount) {
                "$episode · ${Copy.Progress.behind(kind.behind)}"
            } else {
                episode
            }
        is FocusKind.Backlog ->
            if (kind.left > 1 && roomForCount) {
                "$episode · ${Copy.Progress.left(kind.left)}"
            } else {
                episode
            }
        FocusKind.CaughtUp -> Copy.Progress.caughtUp
        is FocusKind.Waiting ->
            f.watchContext(part, part.nextEpisodeNumber ?: part.airedEpisodes + 1)
    }
}

/**
 * "Upcoming" — never "Coming next": **never a second "next" on one screen.**
 *
 * The quieter block keeps the smaller slot. Nothing here is actionable, and a 56×84 poster under a
 * 56×84 poster with no control beside it would give an un-actionable row the same weight as the
 * queue above it.
 */
@Composable
private fun UpcomingSection(
    rows: List<Franchise>,
    now: Long,
    onOpenDetail: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(modifier.fillMaxWidth()) {
        SectionHeaderRow(
            text = Copy.Label.upcoming,
            modifier = Modifier.padding(horizontal = ThemeMetrics.gutter),
        )
        Column(Modifier.padding(top = ThemeMetrics.labelGap - ROW_OWN_INSET)) {
            rows.forEachIndexed { index, f ->
                val part = f.releasingPart
                MediaRow(
                    title = f.title,
                    onClick = { onOpenDetail(f.id) },
                    meta = part?.let {
                        f.watchContext(it, it.nextEpisodeNumber ?: it.airedEpisodes + 1)
                    },
                    lead = f.nextAiring(now)?.let { TemporalCopy.airs(it, now, f.source) },
                    poster = f.portraitArt,
                    slot = PosterSize.Queue,
                    chevron = false,
                    separator = index < rows.size - 1,
                    hint = Copy.Accessibility.opensTheShowHint,
                    modifier = Modifier.padding(horizontal = ThemeMetrics.gutter),
                )
            }
        }
    }
}

/** The resting shelf. At accessibility sizes — or under three cards — it is a list instead. */
@Composable
private fun WatchingShelf(
    appModel: AppModel,
    shelf: List<Franchise>,
    asList: Boolean,
    now: Long,
    onOpenDetail: (String) -> Unit,
    onSeeAll: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(modifier.fillMaxWidth()) {
        SectionHeaderRow(
            text = Copy.Label.watching,
            // The title IS the button — there is no "See all" word in a navigating header; the
            // label only feeds the spoken one. In list mode the header drops it, because there is
            // nothing more to see.
            actionLabel = if (asList) null else Copy.Action.seeAll,
            onAction = if (asList) null else onSeeAll,
            modifier = Modifier.padding(horizontal = ThemeMetrics.gutter),
        )
        if (asList) {
            Column(Modifier.padding(top = ThemeMetrics.labelGap - ROW_OWN_INSET)) {
                shelf.forEachIndexed { index, f ->
                    val caption = shelfCaption(appModel, f, now)
                    MediaRow(
                        title = f.title,
                        onClick = { onOpenDetail(f.id) },
                        meta = caption?.takeIf { !it.second }?.first,
                        lead = caption?.takeIf { it.second }?.first,
                        poster = f.portraitArt,
                        slot = PosterSize.Queue,
                        chevron = false,
                        separator = index < shelf.size - 1,
                        hint = Copy.Accessibility.opensTheShowHint,
                        modifier = Modifier.padding(horizontal = ThemeMetrics.gutter),
                    )
                }
            }
        } else {
            ShelfScroller(modifier = Modifier.padding(top = ThemeMetrics.labelGap)) {
                items(shelf, key = { it.id }) { f ->
                    val caption = shelfCaption(appModel, f, now)
                    ShelfCard(
                        title = f.title,
                        onClick = { onOpenDetail(f.id) },
                        caption = caption?.first,
                        captionIsLead = caption?.second == true,
                        poster = f.portraitArt,
                        slot = PosterSize.TodayShelf,
                        hint = Copy.Accessibility.opensTheShowHint,
                    )
                }
            }
        }
    }
}

/** The chart under the trending billboard. Its header walks to Search, where the chart IS the grid. */
@Composable
private fun TrendingShelf(
    items: List<FranchiseSummary>,
    onOpenDetail: (String) -> Unit,
    onAddShow: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(modifier.fillMaxWidth()) {
        SectionHeaderRow(
            text = Copy.Search.trendingNow,
            onAction = onAddShow,
            modifier = Modifier.padding(horizontal = ThemeMetrics.gutter),
        )
        ShelfScroller(modifier = Modifier.padding(top = ThemeMetrics.labelGap)) {
            items(items, key = { it.id }) { item ->
                ShelfCard(
                    title = item.title,
                    onClick = { onOpenDetail(item.id) },
                    caption = listOfNotNull(item.source.kindWord, item.year?.toString())
                        .joinToString(" · "),
                    poster = item.portraitArt,
                    slot = PosterSize.TodayShelf,
                    hint = Copy.Accessibility.opensTheShowHint,
                )
            }
        }
    }
}

/**
 * One fact per card, always.
 *
 * A dormant show reaches the shelf only because the honest-count fallback widened it, and three
 * captionless cards beside one that has a caption is worse than saying the true, quiet thing.
 *
 * @return the caption and whether it is a forward-looking fact — which is the one amber decision a
 *   shelf card makes.
 */
private fun shelfCaption(appModel: AppModel, f: Franchise, now: Long): Pair<String, Boolean>? =
    when (appModel.shelfState(f)) {
        ShelfState.NEW_EPISODE -> Copy.Label.newEpisode to true
        ShelfState.BACKLOG ->
            f.resumePart?.let { Copy.Progress.episodeNext(it.progress + 1) to false }
        ShelfState.AIRING_WAIT ->
            f.nextAiring(now)?.let { TemporalCopy.airsCompact(it, now, f.source) to true }
                ?: (Copy.Progress.caughtUp to false)
        ShelfState.PREMIERE_SOON ->
            TemporalCopy.returns(appModel.nextPremiere(f), now, f.source) to true
        null -> Copy.Progress.caughtUp to false
    }

/**
 * A horizontal shelf.
 *
 * **Art may run off the trailing edge; TYPE may not.** Every shelf's last card had its title sliced
 * mid-glyph by the hard screen edge ("Solo L", "Return…"), which is what the trailing content
 * margin fixes — the last card comes to rest 40 dp inside the screen.
 *
 * iOS also lays a fade over that edge. It is deliberately not ported: reproducing it needs an
 * offscreen compositing layer over the whole row, and that layer would shear the cards' own contact
 * shadows — the very thing iOS pads its mask by −24 pt to avoid. The margin carries the rule.
 */
@Composable
private fun ShelfScroller(
    modifier: Modifier = Modifier,
    content: LazyListScope.() -> Unit,
) {
    LazyRow(
        modifier = modifier.fillMaxWidth(),
        contentPadding = PaddingValues(
            start = ThemeMetrics.gutter,
            end = SHELF_TRAILING_MARGIN,
            // Breathing room for the cards' contact shadows, which a clipped row would cut.
            top = ThemeSpace.x1,
            bottom = ThemeSpace.x1,
        ),
        horizontalArrangement = Arrangement.spacedBy(ThemeMetrics.shelfGap),
        verticalAlignment = Alignment.Top,
        content = content,
    )
}

// -------------------------------------------------------------------------------------
// Chrome
// -------------------------------------------------------------------------------------

/**
 * The wordmark band's hardening.
 *
 * Two mutually exclusive layers, cross-faded. **The soft layer is mounted only in its own phase** —
 * a material at opacity 0 over moving art is still a backdrop blur the compositor pays for every
 * frame.
 *
 * This is the ONLY composable on the screen that reads the scroll offset, and it reads it in a
 * `graphicsLayer` lambda (a draw-phase read) and through `past` (a `derivedStateOf` that emits only
 * on the crossing).
 */
@Composable
private fun BoxScope.TodayVeils(
    scroll: ScrollOffset,
    showsHero: Boolean,
    headerCarriesTitle: Boolean,
    band: Dp,
) {
    val pastVeilOnset by scroll.past(VEIL_ONSET)
    val pastBarOnset by scroll.past(BAR_ONSET)
    val hard = if (showsHero) headerCarriesTitle else pastBarOnset

    Box(Modifier.align(Alignment.TopCenter).fillMaxWidth()) {
        AnimatedVisibility(
            visible = !hard && pastVeilOnset,
            enter = fadeIn(ThemeMotion.uiGentle()),
            exit = fadeOut(ThemeMotion.uiGentle()),
            label = "todaySoftVeil",
        ) {
            TopScrollEdgeChrome(
                height = band + SOFT_VEIL_RAMP,
                modifier = Modifier.graphicsLayer { alpha = scroll.veilOpacity },
            )
        }
        AnimatedVisibility(
            visible = hard,
            enter = fadeIn(ThemeMotion.uiGentle()),
            exit = fadeOut(ThemeMotion.uiGentle()),
            label = "todayHardVeil",
        ) {
            // "Hardened" means 0.74 canvas over a full-strength blur, never opaque canvas — at 1.0
            // the top ~100 dp of every scrolled screen was a flat #09090B slab with the material
            // under it painted for nothing. `TopScrollEdgeChrome` owns that rule.
            TopScrollEdgeChrome(
                height = band + ThemeMetrics.barEdgeRamp,
                holdHeight = band,
            )
        }
    }
}

/**
 * The wordmark ⇄ title hand-over.
 *
 * **The identity is HANDED OVER, not dropped.** Scrolling used to dissolve the show's name while
 * the wordmark sat still, so the screen lost the one fact it was about and gained nothing.
 */
@Composable
private fun BoxScope.TodayHeader(
    title: String,
    carriesTitle: Boolean,
    identity: AccountIdentity,
    topInset: Dp,
    onOpenProfile: () -> Unit,
) {
    val wordmarkAlpha = animateFloatAsState(
        targetValue = if (carriesTitle) 0f else 1f,
        animationSpec = ThemeMotion.uiGentle(),
        label = "wordmarkAlpha",
    )
    val titleAlpha = animateFloatAsState(
        targetValue = if (carriesTitle) 1f else 0f,
        animationSpec = ThemeMotion.uiGentle(),
        label = "heroTitleAlpha",
    )

    Row(
        Modifier
            .align(Alignment.TopStart)
            .fillMaxWidth()
            .padding(top = topInset)
            .height(HeaderBandHeight)
            .padding(start = ThemeMetrics.gutter, end = ThemeSpace.x2),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.weight(1f), contentAlignment = Alignment.CenterStart) {
            Row(
                Modifier
                    .graphicsLayer { alpha = wordmarkAlpha.value }
                    .then(
                        if (carriesTitle) {
                            Modifier.clearAndSetSemantics {}
                        } else {
                            Modifier.semantics(mergeDescendants = true) {
                                contentDescription = Copy.Brand.spoken
                            }
                        },
                    ),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(ThemeSpace.x2),
            ) {
                PreviouslyMark(width = MARK_WIDTH)
                BasicText(
                    text = Copy.Brand.wordmark,
                    style = ThemeType.brandWordmark,
                    color = ColorProducer { ThemeColor.textPrimary },
                )
            }
            if (title.isNotEmpty()) {
                AutoSizeText(
                    text = title,
                    style = ThemeType.showTitleM.copy(color = ThemeColor.textPrimary),
                    minScale = HEADER_TITLE_MIN_SCALE,
                    maxLines = 1,
                    modifier = Modifier
                        .graphicsLayer { alpha = titleAlpha.value }
                        .then(if (carriesTitle) Modifier else Modifier.clearAndSetSemantics {}),
                )
            }
        }
        AccountControl(identity = identity, onClick = onOpenProfile)
    }
}

/**
 * The header's account control: the shared 34-dp disc in a 44-dp target.
 *
 * The disc itself is `design/brand/AccountDisc`, in its **quiet** form — six amber objects sat in
 * the first viewport and the one that must win, the CTA, had no contrast left. This screen and
 * Profile drew two hand-built copies of the same disc for as long as the brand package did not
 * exist; the flag is the only thing that separates them now.
 *
 * **No glass behind it** — the disc already carries its own ground and ring, and a second disc drawn
 * over a finished one rendered as a flat grey plate on the artwork.
 */
@Composable
private fun AccountControl(identity: AccountIdentity, onClick: () -> Unit) {
    Box(
        Modifier
            .size(minimumTapTarget)
            .clickable(
                interactionSource = null,
                indication = PressStyle.overArt,
                role = Role.Button,
                onClick = onClick,
            )
            .semantics { contentDescription = Copy.Profile.PROFILE },
        contentAlignment = Alignment.Center,
    ) {
        AccountDisc(monogram = identity.monogram, diameter = ACCOUNT_DISC, quiet = true)
    }
}

// -------------------------------------------------------------------------------------
// States
// -------------------------------------------------------------------------------------

/**
 * A whole-screen state, optically centred.
 *
 * `centredState` subtracts `tabBarVisualHeight` (90), **not** `tabBarClearance` (76): they are
 * different numbers for different jobs, and subtracting the scroll inset when centring pushed every
 * empty state ~81 dp above true optical centre. Half of whatever is subtracted is the error.
 *
 * Modifier order is the reverse of SwiftUI's — in Compose the FIRST modifier is the outermost — so
 * the top padding comes first here and the gutter last.
 */
@Composable
private fun StateBlock(
    copy: EmptyStateCopy,
    contentHeight: Dp,
    band: Dp,
    onPrimary: () -> Unit,
    behind: (@Composable () -> Unit)? = null,
) {
    Box(
        Modifier
            .fillMaxWidth()
            .padding(top = band)
            .centredState(contentHeight = contentHeight - band)
            .padding(horizontal = ThemeMetrics.gutter),
        contentAlignment = Alignment.Center,
    ) {
        if (behind != null) behind()
        EmptyState(copy = copy, onPrimary = onPrimary)
    }
}

/**
 * Three covers behind the empty account — and **only** behind it: behind "Couldn't load your
 * library" the same fan read as the very shows the message says it cannot show.
 *
 * Drawn only when exactly three covers exist, so the fan is never lopsided.
 */
@Composable
private fun EmptyFan(trending: List<FranchiseSummary>) {
    val covers = remember(trending) { trending.take(3).mapNotNull { it.portraitArt } }
    if (covers.size < 3) return
    val slot = PosterSize.ShelfMedium
    // `Modifier.blur` is a SILENT no-op below API 31, so the branch is explicit rather than left to
    // degrade — but it is the app's ONE capability boolean that makes it, not a private `SDK_INT`
    // beside this fan. "Device cannot blur" and "the user asked for less transparency" are one
    // state (`ui/chrome/ChromeSurface.kt`); two spellings of it drift apart. At 1.5 dp behind a
    // 35 %-opacity fan the difference is imperceptible either way, which is why the other branch
    // simply does without it.
    val blurAvailable = LocalCanUseMaterial.current
    Row(
        Modifier
            .offset(y = FAN_RISE)
            .graphicsLayer { alpha = FAN_ALPHA }
            .then(if (blurAvailable) Modifier.blur(FAN_BLUR) else Modifier)
            .clearAndSetSemantics {},
        horizontalArrangement = Arrangement.spacedBy(-(slot.width * FAN_OVERLAP)),
    ) {
        covers.forEachIndexed { index, cover ->
            val step = index - 1
            Box(
                Modifier
                    .zIndex(if (step == 0) 1f else 0f)
                    .offset(y = FAN_STEP * abs(step))
                    .graphicsLayer {
                        rotationZ = step * FAN_ANGLE
                        transformOrigin = TransformOrigin.Center
                    },
            ) {
                PosterSlot(url = cover, slot = slot)
            }
        }
    }
}

/**
 * The shape the hero will fill — not a generic card.
 *
 * Three notes that are bugs if dropped: the band **must** carry the remembered tint (the cold
 * fallback is the branded ember `#432D21`, because a card-ground neutral composited to rgb(38,36,32)
 * and the status area read as BLACK for the whole first load and then became flush when the art
 * landed); the ground's fade is **long** (the hand-over starts at 0.52 — the old mask held solid to
 * 0.86 and dropped inside 14 %, which at 440 dp is a 60-dp cliff, a measured hard seam); and the
 * shelf stand-in is a real horizontal scroller, because four 100-dp cards plus gaps are 468 dp wide
 * and in a plain stack that oversized child sets the ideal width of everything above it — the whole
 * screen, wordmark and avatar included, got centred 14 dp to the left.
 */
@Composable
private fun TodaySkeleton(isAX: Boolean) {
    val context = LocalContext.current
    val tint = remember(context) { TodayHeroTint.load(context) } ?: ThemeColor.ambientBackdropFallback
    val height = heroHeight(0.dp)
    val queueSlot = if (isAX) PosterSize.Row else PosterSize.TodayQueue

    Column(Modifier.fillMaxWidth()) {
        Column(
            Modifier
                .fillMaxWidth()
                .height(height)
                .background(
                    // The mask and the ground are one gradient: the layer beneath is the canvas, so
                    // fading the ground's own alpha and masking it are the same picture — and this
                    // one costs no offscreen pass.
                    Brush.verticalGradient(
                        0.00f to tint,
                        0.52f to tint,
                        0.74f to tint.copy(alpha = 0.72f),
                        0.90f to tint.copy(alpha = 0.26f),
                        1.00f to tint.copy(alpha = 0f),
                    ),
                )
                .padding(horizontal = ThemeMetrics.gutter)
                .padding(bottom = if (isAX) ThemeSpace.x5 else ThemeSpace.x4),
            verticalArrangement = Arrangement.Bottom,
        ) {
            SkeletonLine(width = SkeletonPillWidth, height = SkeletonPillHeight)
            SkeletonLine(
                width = SkeletonHeadlineWidth,
                height = SkeletonHeadlineHeight,
                modifier = Modifier.padding(top = SKELETON_TITLE_GAP),
            )
            SkeletonLine(
                width = SkeletonFactWidth,
                height = SkeletonFactHeight,
                modifier = Modifier.padding(top = ThemeSpace.x3),
            )
            SkeletonBlock(
                height = SkeletonCapsuleHeight,
                radius = SkeletonCapsuleHeight / 2,
                modifier = Modifier.padding(top = SKELETON_ACTION_GAP),
            )
        }

        Column(
            Modifier
                .padding(top = if (isAX) ThemeMetrics.heroClearance else ThemeSpace.x5)
                .padding(horizontal = ThemeMetrics.gutter),
            verticalArrangement = Arrangement.spacedBy(ThemeMetrics.labelGap),
        ) {
            SkeletonLine(width = SkeletonEyebrowWidth, height = SkeletonEyebrowHeight)
            repeat(QUEUE_COUNT) {
                SkeletonRow(
                    poster = queueSlot.size,
                    lines = listOf(SkeletonRowTitleWidth, SkeletonRowMetaWidth),
                    posterRadius = queueSlot.radius,
                )
            }
        }

        Column(
            Modifier.padding(top = ThemeMetrics.sectionGap),
            verticalArrangement = Arrangement.spacedBy(ThemeMetrics.labelGap),
        ) {
            SkeletonLine(
                width = SkeletonShelfEyebrowWidth,
                height = SkeletonEyebrowHeight,
                modifier = Modifier.padding(horizontal = ThemeMetrics.gutter),
            )
            LazyRow(
                userScrollEnabled = false,
                contentPadding = PaddingValues(horizontal = ThemeMetrics.gutter),
            ) {
                item {
                    SkeletonShelf(count = 4, size = PosterSize.TodayShelf.size, caption = true)
                }
            }
        }
    }
}

// -------------------------------------------------------------------------------------
// The mark timeline
// -------------------------------------------------------------------------------------

/**
 * The 650-ms beat a committed mark holds, and the tail that follows it.
 *
 * ```
 * tap Mark
 *  ├─ appModel.markNext(...)          // optimistic write + ONE commit haptic
 *  ├─ committedEpisode = undo.episode // the capsule flips; the eyebrow, fact, support and bar
 *  │                                  // advance IN THE SAME FRAME
 *  └─ 650 ms
 *       ├─ pinned = null; committedEpisode = null   → the hero hands over
 *       ├─ presentUndo(...)                          → the toast lands here, not at the tap
 *       └─ 300 ms → handoffInFlight = false
 * ```
 */
@Stable
private class MarkTimeline {

    /** A snapshot of the feed, so the card keeps describing the show it wrote to. */
    var pinned by mutableStateOf<List<Franchise>?>(null)

    var committedEpisode by mutableStateOf<Int?>(null)

    /**
     * Covers the window `committedEpisode` cannot: the incoming card is on screen, fading in, and
     * must refuse a tap until it has actually arrived.
     */
    var handoffInFlight by mutableStateOf(false)

    var committedQueue by mutableStateOf(emptySet<String>())

    private var pendingUndo: UndoState? = null

    fun settle(
        scope: CoroutineScope,
        appModel: AppModel,
        snapshot: List<Franchise>,
        undo: UndoState,
        reduceMotion: Boolean,
        announce: (String) -> Unit,
        clearRecapStrip: () -> Unit,
    ) {
        pinned = snapshot
        pendingUndo = undo
        handoffInFlight = true
        committedEpisode = undo.episode
        announce(Copy.Progress.episodeWatched(undo.episode))
        clearRecapStrip()
        scope.launch {
            delay(HandoffUndo.HOLD_MILLIS)
            pinned = null
            committedEpisode = null
            pendingUndo?.let { appModel.presentUndo(it) }
            pendingUndo = null
            delay(HandoffUndo.tailMillis(reduceMotion))
            handoffInFlight = false
        }
    }
}

/** What a batch confirmation is about. */
private data class BatchPrompt(
    val franchiseId: String,
    val mediaId: Int,
    val title: String,
    val partLabel: String,
    val from: Int,
    val through: Int,
) {
    val count: Int get() = through - from
}

private fun batchPrompt(f: Franchise, part: FranchisePart, through: Int) = BatchPrompt(
    franchiseId = f.id,
    mediaId = part.mediaId,
    title = f.title,
    partLabel = part.canonicalLabel,
    from = part.progress,
    through = through,
)

/**
 * Every confirmation states its exact blast radius: the show, the season, and the two episode
 * numbers the write moves between.
 *
 * A Material dialog with **Android's button placement** — the confirm on the trailing edge — where
 * iOS's action sheet puts it first. The strings are the copy table's, unchanged.
 */
@Composable
private fun BatchMarkDialog(
    prompt: BatchPrompt,
    onDismiss: () -> Unit,
    onConfirm: () -> Unit,
) {
    if (prompt.count <= 0) return
    PreviouslyMaterialBridge {
        AlertDialog(
            onDismissRequest = onDismiss,
            title = {
                BasicText(
                    text = Copy.Confirm.batchMarkTitle(prompt.count),
                    style = ThemeType.showTitleM,
                    color = ColorProducer { ThemeColor.textPrimary },
                )
            },
            text = {
                val scope = listOfNotNull(
                    prompt.title,
                    prompt.partLabel.takeIf { it.isNotEmpty() },
                ).joinToString(" · ")
                BasicText(
                    text = "$scope. ${Copy.Confirm.batchMarkMessage(prompt.from, prompt.through)}",
                    style = ThemeType.metadata,
                    color = ColorProducer { ThemeColor.textSecondary },
                )
            },
            confirmButton = {
                TertiaryButton(
                    label = Copy.Confirm.batchMarkConfirm(prompt.count),
                    onClick = onConfirm,
                )
            },
            dismissButton = {
                TertiaryButton(label = Copy.Action.cancel, onClick = onDismiss)
            },
            containerColor = ThemeColor.surfaceFloating,
            shape = ContinuousCornerShape(ThemeRadius.card),
        )
    }
}

// -------------------------------------------------------------------------------------
// Small helpers
// -------------------------------------------------------------------------------------

/** `View.announceForAccessibility` — the Android reading of iOS's `Announce.status`. */
@Composable
private fun rememberAnnouncer(): (String) -> Unit {
    val view = LocalView.current
    return remember(view) { { text: String -> view.announceForAccessibility(text) } }
}

/**
 * The last hero tint, kept across launches for the skeleton's hero band.
 *
 * The loading frame is the first thing a returning user sees and it has no artwork yet by
 * definition — so it was a black rectangle. The hero rarely changes between two opens.
 *
 * iOS stores three doubles under `today.heroTint`; this stores one packed sRGB int under the same
 * key, which is the same colour to every eye and one read instead of three.
 */
private object TodayHeroTint {
    private const val FILE = "previously.today"
    private const val KEY = "today.heroTint"

    fun load(context: Context): Color? {
        val argb = context.applicationContext
            .getSharedPreferences(FILE, Context.MODE_PRIVATE)
            .getInt(KEY, 0)
        return if (argb == 0) null else Color(argb)
    }

    fun save(context: Context, color: Color) {
        context.applicationContext
            .getSharedPreferences(FILE, Context.MODE_PRIVATE)
            .edit()
            .putInt(KEY, color.toArgb())
            .apply()
    }
}

// -------------------------------------------------------------------------------------
// Geometry and constants
//
// A screen spends no literal; a component is where its own anatomy lives. These belong to Today.
// -------------------------------------------------------------------------------------

/** The wordmark row's height. Today's chrome band is this plus the status-bar inset. */
private val HeaderBandHeight = 52.dp

/** The queue is two rows: the hero takes the first actionable show, this takes the next two. */
private const val QUEUE_COUNT = 2

/** Above this the queue offers "View all N updates" instead of pretending to be the whole list. */
private const val VIEW_ALL_THRESHOLD = 3

/** Under three cards a shelf does not reach its trailing edge, so it becomes a list. */
private const val SHELF_MINIMUM_CARDS = 3

private const val SHELF_LIMIT = 10
private const val TRENDING_SHELF_LIMIT = 9

/** How far inside the screen a shelf's last card comes to rest. See [ShelfScroller]. */
private val SHELF_TRAILING_MARGIN = 40.dp

/** The assembled queue meta line drops its count rather than wrapping. See [queueMeta]. */
private const val QUEUE_META_COUNT_BUDGET = 13

/** `MediaRow`'s own vertical padding, which a container must not pay twice. */
private val ROW_OWN_INSET = ThemeSpace.x2

/** `InlineLinkButton`'s own horizontal padding, pulled back so the word starts on the gutter. */
private val INLINE_LINK_INSET = InlineLink.sideOverhang

/** The recap's floor must clear the bottom chrome's whole ramp, not just the bar. */
private val RECAP_FLOOR = ThemeMetrics.tabBarClearance + ThemeSpace.x2

/** While the recap is on stage the whole image steps back. */
private const val RECAP_ART_SCRIM = 1.9f

private const val RECAP_CARD_KEY = "recap"

/** The soft veil's ramp. 100, not 46: a veil that ends at the band reads as a line drawn on the art. */
private val SOFT_VEIL_RAMP = 100.dp

/** The soft veil appears at all only past here… */
private val VEIL_ONSET = 12.dp

/** …and a screen with no hero hardens its bar at 8. */
private val BAR_ONSET = 8.dp

/** The copy has passed under the bar once its top edge is within this of the band's bottom. */
private val BAND_TOLERANCE = ThemeSpace.x2

// The skeleton's own rhythm — the shape the hero will fill, measured against the real one. Every
// block is named, as Schedule's set is: the skeleton MIRRORS the card it stands in for, and a
// literal typed into the stand-in is a shape that drifts away from the shape that arrives.
private val SKELETON_TITLE_GAP = 14.dp
private val SKELETON_ACTION_GAP = 18.dp

/** The hero's pill. */
private val SkeletonPillWidth = 96.dp
private val SkeletonPillHeight = 12.dp

/** Its headline — the clock, or the show. */
private val SkeletonHeadlineWidth = 250.dp
private val SkeletonHeadlineHeight = 28.dp

/** The one fact line under it. */
private val SkeletonFactWidth = 160.dp
private val SkeletonFactHeight = 14.dp

/** The one action capsule. A stadium, so its radius is half its height. */
private val SkeletonCapsuleHeight = 48.dp

/** A section eyebrow, and the wider one a shelf header carries. */
private val SkeletonEyebrowWidth = 62.dp
private val SkeletonEyebrowHeight = 10.dp
private val SkeletonShelfEyebrowWidth = 84.dp

/** A queue row's two lines. */
private val SkeletonRowTitleWidth = 180.dp
private val SkeletonRowMetaWidth = 110.dp

private val ACCOUNT_DISC = 34.dp

private const val HEADER_TITLE_MIN_SCALE = 0.85f

/** The wordmark's mark, at the width the lockup sets. Its aspect and palette are the mark's own. */
private val MARK_WIDTH = 13.dp

private val FAN_RISE = (-60).dp
private val FAN_STEP = 10.dp
private const val FAN_ANGLE = 9f
private const val FAN_ALPHA = 0.35f
private const val FAN_OVERLAP = 0.42f
private val FAN_BLUR = 1.5.dp

// The wordmark, what a screen reader hears in its place, and the avatar's name: `Copy.Brand` and
// `Copy.Profile` own all three. This file used to declare its own "Previously." while the splash
// declared "Previously" and drew the period separately — two spellings that already disagreed about
// whether the period is part of the name.

