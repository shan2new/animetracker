package com.anitrack.app.ui.library

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.material3.pulltorefresh.rememberPullToRefreshState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.ColorProducer
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.PointerEventTimeoutCancellationException
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.anitrack.app.AppModel
import com.anitrack.app.LibShelf
import com.anitrack.app.data.SyncCenter
import com.anitrack.app.design.ContinuousCornerShape
import com.anitrack.app.design.FeedbackCoordinator
import com.anitrack.app.design.FeedbackToken
import com.anitrack.app.design.LocalControlInk
import com.anitrack.app.design.MaterialSymbol
import com.anitrack.app.design.PreviouslyIcons
import com.anitrack.app.design.PreviouslyMaterialBridge
import com.anitrack.app.design.ShadowToken
import com.anitrack.app.design.ThemeColor
import com.anitrack.app.design.ThemeMetrics
import com.anitrack.app.design.ThemeMotion
import com.anitrack.app.design.ThemeRadius
import com.anitrack.app.design.ThemeSpace
import com.anitrack.app.design.ThemeType
import com.anitrack.app.design.rememberSymbol
import com.anitrack.app.ui.art.ArtBackdrop
import com.anitrack.app.ui.chrome.ScrollEdgeChromeBox
import com.anitrack.app.ui.chrome.chromeHazeSource
import com.anitrack.app.ui.chrome.tabBarContentBottom
import com.anitrack.app.ui.control.PressStyle
import com.anitrack.app.ui.control.materialGlyphBox
import com.anitrack.app.ui.control.minimumTapTarget
import com.anitrack.app.ui.state.EmptyState
import com.anitrack.app.ui.state.Freshness
import com.anitrack.app.ui.state.InlineNotice
import com.anitrack.app.ui.state.PullRefresh
import com.anitrack.app.ui.state.RefreshIndicator
import com.anitrack.app.ui.state.SkeletonGate
import com.anitrack.app.ui.state.SkeletonLine
import com.anitrack.app.ui.state.SkeletonPoster
import com.anitrack.app.ui.state.centredState
import com.anitrack.model.Franchise
import com.anitrack.model.WatchStatus
import com.anitrack.model.copy.Copy
import com.anitrack.model.copy.CopyDates
import com.anitrack.model.copy.CopyLibrary
import com.anitrack.model.effectiveStatus
import com.anitrack.model.episodesBehind
import com.anitrack.model.landscapeArt
import com.anitrack.model.portraitArt
import com.anitrack.model.releasingPart
import com.anitrack.model.resumePart
import kotlinx.coroutines.launch

/*
 * THE LIBRARY ROOT — the port of `LibraryView` from
 * `ios/Sources/Features/Library/LibraryView.swift`.
 *
 * **The Library is the app's CALM root.** Per the urgency pact, Today carries every obligation —
 * "4 episodes behind", amber mark rings, countdowns — and the Library carries NONE. It is a
 * zero-control browsing surface: one lead shelf of art you are in the middle of, four quiet
 * horizontal shelves grouped by a show's relationship to its FUTURE, and one door — a trailing bar
 * button reading "30 titles" — into All titles, the single Library screen that has controls on it.
 *
 * The one number this screen draws is a Continue card's progress bar, and the one amber caption is a
 * `ReturnFact` inside the 60-day horizon (plus the amber `lead`, which on the Watching shelf can
 * only ever be a rewatch).
 */

// =================================================================================================
// MARK: - Routing
// =================================================================================================

/**
 * The two axes All titles can be seeded on, kept **independent on purpose**: *"the root's buckets are
 * not all statuses — `Returning` and `Announced` are facts about a show's future, not list states."*
 *
 * [unwatchedOnly] **composes with** [status] rather than replacing it.
 */
@Immutable
data class AllTitlesRoute(
    val status: WatchStatus? = null,
    val returning: ReturnScope? = null,
    val unwatchedOnly: Boolean = false,
) {
    /** Identity, so a second push of the same filters re-uses the composition and a different one does not. */
    val id: String
        get() = "${status?.wire ?: "-"}/${returning?.wire ?: "-"}/$unwatchedOnly"
}

/** "Is its return DATED?" — the axis the root's two anticipation shelves split on. */
enum class ReturnScope(val wire: String, val label: String, val section: LibrarySection) {
    DATED("dated", CopyLibrary.returning, LibrarySection.RETURNING),
    UNDATED("undated", CopyLibrary.announced, LibrarySection.ANNOUNCED),
}

/** The route a section header walks to. */
private fun routeFor(section: LibrarySection): AllTitlesRoute = when (section) {
    LibrarySection.RETURNING -> AllTitlesRoute(returning = ReturnScope.DATED)
    LibrarySection.ANNOUNCED -> AllTitlesRoute(returning = ReturnScope.UNDATED)
    LibrarySection.WATCHING -> AllTitlesRoute(status = WatchStatus.WATCHING)
    LibrarySection.PLANNED -> AllTitlesRoute(status = WatchStatus.PLANNED)
    LibrarySection.FINISHED -> AllTitlesRoute(status = WatchStatus.COMPLETED)
}

// =================================================================================================
// MARK: - Metrics
// =================================================================================================

/** Geometry that belongs to this screen alone. Nothing here is a scale token. */
private object LibraryRootMetrics {

    /** Above the first shelf, under the bar. */
    val contentTopPadding = 20.dp

    /** How many titles a quiet shelf previews before its header becomes the way to the rest. */
    const val supportingPreviewCount = 6

    /** The Continue skeleton's card, at the reference device's computed width. */
    val continueSkeletonWidth = 286.dp
    val continueSkeletonHeight = 161.dp

    /** The landscape skeleton's card. `BannerCard`'s own height is 104. */
    val landscapeSkeletonWidth = 174.dp
    val landscapeSkeletonHeight = 104.dp
}

// =================================================================================================
// MARK: - Sections
// =================================================================================================

/** One shelf on the root, resolved once per frame and passed down. */
@Immutable
data class RootSection(val key: LibrarySection, val items: List<Franchise>)

/**
 * `AppModel.libraryShelves` stays the source of truth for membership and order; the only work here
 * is **splitting `comingBack` in two**, because *"a heading that says RETURNING may not contain a
 * show whose own detail screen says 'Finished' and 'No date announced'."*
 *
 * The partition **preserves** `comingBack`'s soonest-first order inside each half and calls
 * `ReturnFact.of` exactly once per title.
 */
fun rootSections(appModel: AppModel): List<RootSection> {
    val now = appModel.nowMinute
    val out = ArrayList<RootSection>(5)
    for (shelf in appModel.libraryShelves) {
        when (shelf.shelf) {
            LibShelf.COMING_BACK -> {
                val dated = ArrayList<Franchise>(shelf.franchises.size)
                val undated = ArrayList<Franchise>()
                for (f in shelf.franchises) {
                    if (ReturnFact.of(f, now).dated) dated.add(f) else undated.add(f)
                }
                if (dated.isNotEmpty()) out.add(RootSection(LibrarySection.RETURNING, dated))
                if (undated.isNotEmpty()) out.add(RootSection(LibrarySection.ANNOUNCED, undated))
            }

            LibShelf.WATCHING -> out.add(RootSection(LibrarySection.WATCHING, shelf.franchises))
            LibShelf.PLANNED -> out.add(RootSection(LibrarySection.PLANNED, shelf.franchises))
            LibShelf.FINISHED -> out.add(RootSection(LibrarySection.FINISHED, shelf.franchises))
        }
    }
    // Returning · Watching · Planned · Announced · Watched.
    return out.sortedBy { it.key.rank }
}

/**
 * "The room is lit by the thing you are looking at": the wash's source is the lead show's own art.
 *
 * `null` when the library has no artwork at all, in which case the root passes the brand colour
 * instead — *"with no artwork in the library there is nothing for it to be ABOUT, so first run gets
 * the app's own colour."*
 */
fun washArtwork(
    sections: List<RootSection>,
    heroItems: List<Franchise>,
    library: List<Franchise>,
): String? {
    val franchise = heroItems.firstOrNull()
        ?: sections.firstOrNull()?.items?.firstOrNull()
        ?: library.firstOrNull()
        ?: return null
    val resume = franchise.resumePart
    return listOfNotNull(
        resume?.landscapeArt,
        franchise.landscapeArt,
        resume?.portraitArt,
        franchise.portraitArt,
    ).firstOrNull { it.isNotEmpty() }
}

// =================================================================================================
// MARK: - The screen
// =================================================================================================

/**
 * The Library tab.
 *
 * All titles is an **item destination**, not a path entry — exactly as on iOS — which is why this
 * composable owns it and why [popSignal] can clear it. Clearing a navigation path alone left it
 * standing and re-selecting the tab did nothing.
 *
 * @param requestedAll a one-shot route pushed from another tab (Today's "See all watching", Today's
 *   "View all N updates", Profile's status rows). Consumed immediately.
 * @param popSignal bumped when the Library tab is re-selected. Its **first** value is ignored, so a
 *   route supplied at launch is not cancelled by the initial signal.
 * @param openAllTitlesOnLaunch the DEBUG `openAllTitles` launch extra. Latched, because a bare flag
 *   re-pushed the screen the instant it popped.
 */
@Composable
fun LibraryScreen(
    appModel: AppModel,
    dates: CopyDates,
    onOpenDetail: (String) -> Unit,
    onAddShow: () -> Unit,
    modifier: Modifier = Modifier,
    requestedAll: AllTitlesRoute? = null,
    onRequestedAllHandled: () -> Unit = {},
    popSignal: Int = 0,
    openAllTitlesOnLaunch: Boolean = false,
) {
    var all by remember { mutableStateOf<AllTitlesRoute?>(null) }
    var debugOpened by remember { mutableStateOf(false) }
    val seenPop = remember { mutableIntStateOf(popSignal) }

    // ---- The performance contract: resolve ONCE, pass the results down. ----
    //
    // `sections` used to be recomputed by the wash and by the section loop, and each pass ran
    // `ReturnFact.of` twice per title. The memo keys are the two things either derivation reads:
    // the library itself, and the clock at MINUTE granularity (a `ReturnFact` cannot change inside
    // a minute, and the model publishes `nowMinute` precisely so a 20-second tick does not re-derive
    // captions).
    val library = appModel.library
    val sections = remember(library, appModel.nowMinute) { rootSections(appModel) }
    // The hero is an instruction to continue, so only a title with a real resume part may enter it.
    val heroItems = remember(library, appModel.nowMinute) {
        appModel.watchingShelf.filter { it.resumePart != null }
    }
    val washArt = remember(sections, heroItems, library) {
        washArtwork(sections, heroItems, library)
    }

    LaunchedEffect(requestedAll) {
        val route = requestedAll ?: return@LaunchedEffect
        all = route
        onRequestedAllHandled()
    }

    // Re-selecting the Library tab pops All titles.
    LaunchedEffect(popSignal) {
        if (popSignal != seenPop.intValue) {
            seenPop.intValue = popSignal
            all = null
        }
    }

    LaunchedEffect(openAllTitlesOnLaunch) {
        if (openAllTitlesOnLaunch && !debugOpened) {
            debugOpened = true
            all = AllTitlesRoute()
        }
    }

    BackHandler(enabled = all != null) { all = null }

    val route = all
    if (route == null) {
        LibraryRoot(
            appModel = appModel,
            dates = dates,
            sections = sections,
            heroItems = heroItems,
            washArt = washArt,
            onOpenDetail = onOpenDetail,
            onAddShow = onAddShow,
            onOpenAll = { all = it },
            modifier = modifier,
        )
    } else {
        // Keyed on the route's identity: the filters are seeded in the initialiser, never applied in
        // an `onAppear`, so a *different* route must build a fresh composition rather than mutate a
        // live one. "Applied late, the screen builds once unfiltered and once filtered — the user
        // sees the whole library flash past on the way to the six rows they asked for."
        key(route.id) {
            AllTitlesScreen(
                appModel = appModel,
                dates = dates,
                initialStatus = route.status,
                initialReturning = route.returning,
                initialUnwatchedOnly = route.unwatchedOnly,
                washArt = washArt,
                onOpenDetail = onOpenDetail,
                onAddShow = onAddShow,
                onBack = { all = null },
                modifier = modifier,
            )
        }
    }
}

@Composable
private fun LibraryRoot(
    appModel: AppModel,
    dates: CopyDates,
    sections: List<RootSection>,
    heroItems: List<Franchise>,
    washArt: String?,
    onOpenDetail: (String) -> Unit,
    onAddShow: () -> Unit,
    onOpenAll: (AllTitlesRoute) -> Unit,
    modifier: Modifier = Modifier,
) {
    val scope = rememberCoroutineScope()
    val scrollState = rememberScrollState()
    var pullDriving by remember { mutableStateOf(false) }

    // Named, and named WITH ITS TYPE. `scope.launch` answers with a `Job`, so an anonymous
    // `{ scope.launch { … } }` types as `() -> Job`; passed straight to a parameter it coerces to
    // `Unit`, but inside an `if` it does not — the branches widen to their common supertype
    // `() -> Any` and the call stops compiling. One handler, declared once, ends that.
    val retry: () -> Unit = { scope.launch { appModel.reload() } }

    // The boolean is DERIVED and only notifies on the flip, which is the Compose spelling of iOS's
    // `if raised != raisedTop` guard around a geometry probe. The raw offset is never screen state.
    val raisedTop by remember(scrollState) { derivedStateOf { scrollState.value > 0 } }

    val library = appModel.library
    val loading = appModel.loading

    Box(modifier.fillMaxSize().background(ThemeColor.canvas)) {
        ScrollEdgeChromeBox(
            modifier = Modifier.fillMaxSize(),
            softTop = true,
            topRaised = raisedTop,
            topHold = ThemeMetrics.inlineBarBottom(),
        ) {
            ArtBackdrop(
                modifier = Modifier.align(Alignment.TopCenter),
                url = washArt,
                // No artwork anywhere: first run gets the app's own colour rather than a grey band.
                tint = if (washArt == null) ThemeColor.accent else null,
            )

            PreviouslyPullToRefresh(
                modifier = Modifier.fillMaxSize(),
                onRefresh = { appModel.reload() },
                onDrivingChange = { if (it != pullDriving) pullDriving = it },
            ) {
                BoxWithConstraints(Modifier.fillMaxSize()) {
                    val contentHeight = maxHeight
                    Column(
                        modifier = Modifier
                            .fillMaxSize()
                            .verticalScroll(scrollState)
                            .chromeHazeSource()
                            .padding(
                                top = ThemeMetrics.inlineBarBottom(),
                                bottom = tabBarContentBottom(),
                            ),
                    ) {
                        // The freshness anchor: a zero-height element that plants the stale strip
                        // beneath it once the last successful load is over 24 h old.
                        Freshness(
                            staleSince = appModel.staleSince(SyncCenter.DataClass.CATALOGUE),
                            now = appModel.now,
                            dates = dates,
                            modifier = Modifier.padding(horizontal = ThemeMetrics.gutter),
                        ) {}

                        AnimatedVisibility(
                            visible = appModel.sectionFailed,
                            enter = fadeIn(ThemeMotion.uiGentle()),
                            exit = fadeOut(ThemeMotion.uiGentle()),
                        ) {
                            InlineNotice(
                                message = Copy.Notice.library,
                                modifier = Modifier.padding(
                                    horizontal = ThemeMetrics.gutter,
                                    vertical = ThemeSpace.x3,
                                ),
                                onRetry = retry,
                            )
                        }

                        SkeletonGate(
                            isLoading = loading && library.isEmpty(),
                            skeleton = { LibraryRootSkeleton() },
                        ) {
                            // ONE view: `SkeletonGate` lays its content out in a box, so two
                            // siblings handed to it draw on top of each other.
                            if (library.isEmpty()) {
                                val copy = appModel.emptyStateCopy
                                EmptyState(
                                    copy = copy,
                                    modifier = Modifier
                                        .padding(horizontal = ThemeMetrics.gutter)
                                        .centredState(contentHeight),
                                    // The empty state's one action, and it is always a live one.
                                    onPrimary = if (appModel.loadError) retry else onAddShow,
                                )
                            } else {
                                RootShelves(
                                    appModel = appModel,
                                    sections = sections,
                                    heroItems = heroItems,
                                    onOpenDetail = onOpenDetail,
                                    onOpenAll = onOpenAll,
                                )
                            }
                        }
                    }
                }
            }
        }

        // The bar draws ABOVE the veil, so it is a sibling of the chrome box rather than a child.
        InlineChromeBar(
            title = CopyLibrary.title,
            modifier = Modifier.align(Alignment.TopCenter),
        ) {
            // Mounted only while a refresh is running, never held at opacity 0 as a layout
            // placeholder: "in flow above the content it reserved a 16-pt row at idle — the void
            // between 'Library' and the All titles row." It stands down entirely while a pull is
            // driving, because the system pull indicator owns that moment.
            if (appModel.isRefreshing) {
                RefreshIndicator(
                    isRefreshing = true,
                    modifier = Modifier.padding(end = ThemeSpace.x2),
                    suppressed = pullDriving,
                )
            }
            AllTitlesBarButton(count = library.size) { onOpenAll(AllTitlesRoute()) }
        }
    }
}

/**
 * The root's content stack.
 *
 * **The Watching bucket belongs to the Continue shelf.** Its own quiet shelf renders *only* when the
 * Continue shelf cannot — a Watching list where nothing has a resume part.
 */
@Composable
private fun RootShelves(
    appModel: AppModel,
    sections: List<RootSection>,
    heroItems: List<Franchise>,
    onOpenDetail: (String) -> Unit,
    onOpenAll: (AllTitlesRoute) -> Unit,
) {
    val shelves = remember(sections, heroItems.isEmpty()) {
        sections.filter { it.key != LibrarySection.WATCHING || heroItems.isEmpty() }
    }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = LibraryRootMetrics.contentTopPadding),
        verticalArrangement = Arrangement.spacedBy(ThemeMetrics.sectionGap),
    ) {
        if (heroItems.isNotEmpty()) {
            LibraryContinueShelf(
                items = heroItems,
                appModel = appModel,
                onOpenDetail = onOpenDetail,
                onViewAll = { onOpenAll(routeFor(LibrarySection.WATCHING)) },
            )
        }
        for (section in shelves) {
            val items = remember(section, appModel.nowMinute) {
                section.items
                    .take(LibraryRootMetrics.supportingPreviewCount)
                    .map { franchise ->
                        val facts = LibraryRowFacts.root(franchise, section.key, appModel)
                        LibraryLandscapeItem(franchise, facts.lead, facts.meta)
                    }
            }
            LibraryLandscapeShelf(
                title = section.key.label,
                items = items,
                appModel = appModel,
                onOpenDetail = onOpenDetail,
                onViewAll = { onOpenAll(routeFor(section.key)) },
            )
        }
    }
}

/**
 * The door into All titles: `"30 titles"`, a bare word in the bar.
 *
 * `listAction` in `textSecondary` — never amber. Amber on this screen is spent on a return date, and
 * a control that opens a list is not a fact about the user's future.
 */
@Composable
private fun AllTitlesBarButton(count: Int, onClick: () -> Unit) {
    val label = Copy.titles(count)
    val spoken = CopyLibrary.allTitlesAccessibility(count)
    Box(
        Modifier
            .clickable(
                interactionSource = null,
                indication = PressStyle.textAction,
                onClickLabel = CopyLibrary.allTitlesHint,
                role = Role.Button,
                onClick = onClick,
            )
            .semantics(mergeDescendants = true) { contentDescription = spoken }
            .defaultMinSize(minWidth = minimumTapTarget, minHeight = minimumTapTarget)
            .padding(horizontal = ThemeSpace.x3),
        contentAlignment = Alignment.Center,
    ) {
        BasicText(
            text = label,
            style = ThemeType.listAction,
            maxLines = 1,
            color = ColorProducer { ThemeColor.textSecondary },
        )
    }
}

// =================================================================================================
// MARK: - Shared chrome
// =================================================================================================

/**
 * An inline navigation bar: the title centred in the 44-dp band under the status bar, with optional
 * leading and trailing controls.
 *
 * **Inline, never a large title.** *"A large title collapses on the first scroll and moves the top
 * safe area ~50 pt mid-flight; an inline one holds still over the wash."* The bar paints no ground
 * of its own — `ScrollEdgeChromeBox`'s hardened veil is the bar's material, and it holds through
 * exactly this band.
 *
 * The title is an OVERLAY rather than a stack member, so a leading control on one side only cannot
 * shift it: "with `Reset` present on one side only, a three-item row puts the title wherever the two
 * buttons' widths happen to leave it."
 */
@Composable
internal fun InlineChromeBar(
    title: String,
    modifier: Modifier = Modifier,
    leading: @Composable (RowScope.() -> Unit)? = null,
    trailing: @Composable (RowScope.() -> Unit)? = null,
) {
    Box(
        modifier
            .fillMaxWidth()
            .padding(top = ThemeMetrics.topSafeInset())
            .height(ThemeMetrics.inlineBarHeight),
        contentAlignment = Alignment.Center,
    ) {
        BasicText(
            text = title,
            style = ThemeType.showTitleM,
            maxLines = 1,
            color = ColorProducer { ThemeColor.textPrimary },
        )
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = ThemeSpace.x1),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (leading != null) leading()
            Spacer(Modifier.weight(1f))
            if (trailing != null) trailing()
        }
    }
}

/**
 * Pull to refresh, with the app's one added haptic.
 *
 * Compose's own `PullToRefreshBox` is the pull — the native answer, per the fidelity line — and the
 * custom bookmark-fill graphic is deliberately not drawn: suppressing the system indicator is not
 * supported API, and two indicators is worse than none.
 *
 * `.refreshArmed` fires the first time the pull crosses its threshold, and re-arms only once the
 * pull is well back so a wobble at the threshold cannot buzz twice. The iOS rule adds "**while the
 * finger is down**" — *"a fast flick to the top overshoots well past the threshold under momentum
 * with no finger down, and the system `refreshable` does NOT fire for that"*. On Android that test
 * is structural rather than a flag to read: `PullToRefreshState` only accumulates distance from a
 * user drag, so a fling never advances `distanceFraction` at all.
 *
 * [onDrivingChange] reports "the system indicator owns this moment" — a live drag, or the refresh it
 * started — so the caller's own bar spinner can stand down. The refreshing flag is owned HERE rather
 * than read from the model, so a background refresh does not raise the pull indicator as well.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun PreviouslyPullToRefresh(
    onRefresh: suspend () -> Unit,
    onDrivingChange: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
    content: @Composable BoxScope.() -> Unit,
) {
    val scope = rememberCoroutineScope()
    val state = rememberPullToRefreshState()
    var refreshing by remember { mutableStateOf(false) }
    var armed by remember { mutableStateOf(false) }

    LaunchedEffect(state) {
        snapshotFlow { state.distanceFraction }.collect { fraction ->
            if (!armed && fraction >= 1f) {
                armed = true
                FeedbackCoordinator.fire(FeedbackToken.REFRESH_ARMED)
            } else if (armed && fraction < PullRefresh.REARM_PROGRESS) {
                armed = false
            }
            onDrivingChange(fraction > 0f)
        }
    }
    LaunchedEffect(refreshing) { if (refreshing) onDrivingChange(true) }

    PreviouslyMaterialBridge {
        PullToRefreshBox(
            isRefreshing = refreshing,
            onRefresh = {
                refreshing = true
                scope.launch {
                    try {
                        onRefresh()
                    } finally {
                        refreshing = false
                        onDrivingChange(false)
                    }
                }
            },
            state = state,
            modifier = modifier,
            content = content,
        )
    }
}

// =================================================================================================
// MARK: - Long-press quick actions
// =================================================================================================

/** The status rows, in menu order — independent of the enum's declaration order. */
private val statusMenuOrder = listOf(
    WatchStatus.WATCHING,
    WatchStatus.PLANNED,
    WatchStatus.COMPLETED,
    WatchStatus.PAUSED,
    WatchStatus.DROPPED,
)

/**
 * The symbol for a status that is NOT the current one. (The current one wears a tick.)
 *
 * `PLANNED` is the one gap in the icon inventory: iOS draws SF `clock`, and the 42-row Material
 * table has no clock. `bookmark` is the app's own mark for a shelved-but-unstarted show — it is the
 * glyph the "Nothing in Watching" state already uses — so it stands in here rather than a
 * `history` glyph, which means "watched before" and would be actively wrong.
 */
private fun statusSymbol(status: WatchStatus): MaterialSymbol = when (status) {
    WatchStatus.WATCHING -> PreviouslyIcons.Pending.PlayCircle
    WatchStatus.PLANNED -> PreviouslyIcons.Bookmark
    WatchStatus.COMPLETED -> PreviouslyIcons.Pending.CheckCircle
    WatchStatus.PAUSED -> PreviouslyIcons.Pending.PauseCircle
    WatchStatus.DROPPED -> PreviouslyIcons.Pending.Cancel
}

/**
 * The shared franchise context menu, on every card and row in the Library.
 *
 * `DropdownMenu` is the native answer — iOS's blurred lift-and-platter has no Android equivalent and
 * reproducing one is exactly the heavy engineering the fidelity line rules out.
 *
 * **No haptic is fired by the menu itself.** Each `AppModel` command fires its own, at most one per
 * transaction.
 */
@Composable
internal fun FranchiseQuickActions(
    franchise: Franchise,
    appModel: AppModel,
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }
    Box(modifier.longPressAction { expanded = true }) {
        content()
        QuickActionsMenu(
            franchise = franchise,
            appModel = appModel,
            expanded = expanded,
            onDismiss = { expanded = false },
        )
    }
}

@Composable
private fun QuickActionsMenu(
    franchise: Franchise,
    appModel: AppModel,
    expanded: Boolean,
    onDismiss: () -> Unit,
) {
    val releasing = franchise.releasingPart
    val behind = releasing?.episodesBehind ?: 0
    val current = franchise.effectiveStatus

    PreviouslyMaterialBridge {
        DropdownMenu(
            expanded = expanded,
            onDismissRequest = onDismiss,
            // The `.floating` surface level, spelled out: an opaque ground, a full `strokeStrong`
            // ring and the floating shadow.
            shape = ContinuousCornerShape(ThemeRadius.compactControl),
            containerColor = ThemeColor.surfaceFloating,
            tonalElevation = 0.dp,
            shadowElevation = ShadowToken.Floating.elevation,
            border = BorderStroke(ThemeMetrics.hairline, ThemeColor.strokeStrong),
        ) {
            if (releasing != null && behind > 0) {
                QuickAction(
                    label = Copy.Action.markAll(behind),
                    symbol = PreviouslyIcons.Pending.PlaylistAdd,
                ) {
                    onDismiss()
                    appModel.markCaughtUp(franchise.id)
                }
            }
            for (status in statusMenuOrder) {
                QuickAction(
                    label = Copy.statusLabel(status.wire),
                    symbol = if (status == current) PreviouslyIcons.Check else statusSymbol(status),
                ) {
                    onDismiss()
                    appModel.setStatus(franchise.id, status)
                }
            }
            Spacer(
                Modifier
                    .fillMaxWidth()
                    .padding(vertical = ThemeSpace.x1)
                    .height(1.dp)
                    .background(ThemeColor.separatorQuiet),
            )
            QuickAction(
                label = Copy.Action.removeFromLibrary,
                symbol = PreviouslyIcons.Delete,
                destructive = true,
            ) {
                onDismiss()
                appModel.removeWithUndo(franchise)
            }
        }
    }
}

/** The menu glyph, at its iOS point size. `materialGlyphBox` owns the SF→Material conversion. */
private val quickActionGlyph = 15.dp

/**
 * One command. `interactive` ink — a menu item is an action, and actions are ink — except the
 * destructive one, which is the only row in the app that may wear `destructive`.
 *
 * Plain `clickable` rows rather than `DropdownMenuItem`s, which build their own ripple with no way
 * to turn it off.
 */
@Composable
private fun QuickAction(
    label: String,
    symbol: MaterialSymbol,
    destructive: Boolean = false,
    onClick: () -> Unit,
) {
    val ink = if (destructive) ThemeColor.destructive else LocalControlInk.current
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(
                interactionSource = null,
                indication = PressStyle.groupedRow,
                role = Role.Button,
                onClick = onClick,
            )
            .defaultMinSize(minHeight = minimumTapTarget)
            .padding(horizontal = ThemeMetrics.gutter, vertical = ThemeSpace.x2),
        horizontalArrangement = Arrangement.spacedBy(ThemeSpace.x3),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        BasicText(
            text = label,
            style = ThemeType.body,
            modifier = Modifier.weight(1f),
            maxLines = 2,
            color = ColorProducer { ink },
        )
        Image(
            imageVector = rememberSymbol(symbol),
            // Decorative: the row's own label is what a screen reader reads.
            contentDescription = null,
            modifier = Modifier.size(materialGlyphBox(quickActionGlyph)),
            colorFilter = ColorFilter.tint(ink),
        )
    }
}

/**
 * Long-press detection that does **not** disturb the card's own tap.
 *
 * The shared cards own their `clickable`, and a plain `combinedClickable` on a wrapper loses every
 * gesture to them: hit-testing reaches the innermost node first and the card consumes the press in
 * the Main pass. So this watches the **Initial** pass, which runs parent-first, times the press
 * itself, and on a long press consumes the remainder of the gesture — which the card's `clickable`
 * reads as a cancellation, so exactly one of the two fires.
 *
 * Movement past the touch slop abandons the attempt, leaving the scroll gesture untouched.
 */
private fun Modifier.longPressAction(onLongPress: () -> Unit): Modifier =
    pointerInput(onLongPress) {
        awaitEachGesture {
            val down = awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Initial)
            val slop = viewConfiguration.touchSlop
            var longPressed = false
            try {
                withTimeout(viewConfiguration.longPressTimeoutMillis) {
                    while (true) {
                        val event = awaitPointerEvent(PointerEventPass.Initial)
                        val change = event.changes.firstOrNull { it.id == down.id }
                            ?: return@withTimeout
                        if (!change.pressed) return@withTimeout
                        if ((change.position - down.position).getDistance() > slop) {
                            return@withTimeout
                        }
                    }
                }
            } catch (_: PointerEventTimeoutCancellationException) {
                longPressed = true
            }
            if (!longPressed) return@awaitEachGesture

            onLongPress()
            while (true) {
                val event = awaitPointerEvent(PointerEventPass.Initial)
                val change = event.changes.firstOrNull { it.id == down.id } ?: break
                change.consume()
                if (!change.pressed) break
            }
        }
    }

// =================================================================================================
// MARK: - The root skeleton
// =================================================================================================

/**
 * Mirrors the composition it stands in for, so the hand-off changes content and not shape: the
 * Continue shelf, then one landscape shelf.
 *
 * Skeleton blocks do **not** scale with the text size — they are structure, not text.
 */
@Composable
private fun LibraryRootSkeleton(modifier: Modifier = Modifier) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(top = LibraryRootMetrics.contentTopPadding),
        verticalArrangement = Arrangement.spacedBy(ThemeMetrics.sectionGap),
    ) {
        // Block 1 — the Continue shelf.
        Column(verticalArrangement = Arrangement.spacedBy(ThemeMetrics.shelfGap)) {
            SkeletonLine(
                modifier = Modifier.padding(horizontal = ThemeMetrics.gutter),
                width = SkeletonHeaderWidth,
                height = SkeletonHeaderHeight,
            )
            Row(
                modifier = Modifier
                    .padding(horizontal = ThemeMetrics.gutter)
                    // The real shelf runs off the trailing edge; the skeleton says so and is clipped
                    // rather than allowed to widen the screen.
                    .clipToBounds(),
                horizontalArrangement = Arrangement.spacedBy(ThemeMetrics.shelfGap),
                verticalAlignment = Alignment.Top,
            ) {
                repeat(2) {
                    SkeletonShelfCard(
                        width = LibraryRootMetrics.continueSkeletonWidth,
                        height = LibraryRootMetrics.continueSkeletonHeight,
                        titleWidth = SkeletonContinueTitleWidth,
                        titleHeight = SkeletonContinueTitleHeight,
                        captionWidth = SkeletonContinueCaptionWidth,
                    )
                }
            }
        }

        // Block 2 — one landscape shelf.
        Column(verticalArrangement = Arrangement.spacedBy(ThemeMetrics.shelfGap)) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = ThemeMetrics.gutter),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                SkeletonLine(width = SkeletonShelfHeaderWidth, height = SkeletonHeaderHeight)
                Spacer(Modifier.weight(1f))
                SkeletonLine(width = SkeletonHeaderActionWidth, height = SkeletonCaptionHeight)
            }
            Row(
                modifier = Modifier
                    .padding(horizontal = ThemeMetrics.gutter)
                    .clipToBounds(),
                horizontalArrangement = Arrangement.spacedBy(ThemeMetrics.shelfGap),
                verticalAlignment = Alignment.Top,
            ) {
                repeat(2) {
                    SkeletonShelfCard(
                        width = LibraryRootMetrics.landscapeSkeletonWidth,
                        height = LibraryRootMetrics.landscapeSkeletonHeight,
                        titleWidth = LibraryRootMetrics.landscapeSkeletonWidth * 0.72f,
                        titleHeight = SkeletonShelfTitleHeight,
                        captionWidth = LibraryRootMetrics.landscapeSkeletonWidth * 0.55f,
                    )
                }
            }
        }
    }
}

// The root skeleton's own geometry: it mirrors the shelves it stands in for, so the swap changes
// content and not shape. Skeleton blocks do NOT scale with the text size — they are structure, not
// text.
private val SkeletonHeaderWidth = 108.dp
private val SkeletonHeaderHeight = 19.dp
private val SkeletonShelfHeaderWidth = 92.dp
private val SkeletonHeaderActionWidth = 54.dp
private val SkeletonContinueTitleWidth = 154.dp
private val SkeletonContinueTitleHeight = 18.dp
private val SkeletonContinueCaptionWidth = 196.dp * 0.6f
private val SkeletonShelfTitleHeight = 14.dp
private val SkeletonCaptionHeight = 12.dp

@Composable
private fun SkeletonShelfCard(
    width: Dp,
    height: Dp,
    titleWidth: Dp,
    titleHeight: Dp,
    captionWidth: Dp,
) {
    Column(verticalArrangement = Arrangement.spacedBy(ThemeSpace.x2)) {
        SkeletonPoster(width = width, height = height, radius = ThemeRadius.card)
        SkeletonLine(width = titleWidth, height = titleHeight)
        SkeletonLine(width = captionWidth, height = SkeletonCaptionHeight)
    }
}
