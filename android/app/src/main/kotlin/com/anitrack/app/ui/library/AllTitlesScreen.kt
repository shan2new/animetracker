package com.anitrack.app.ui.library

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.drag
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyGridState
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.BottomSheetDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.ColorProducer
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.layout
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.setProgress
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import com.anitrack.app.AppModel
import com.anitrack.app.data.SyncCenter
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
import com.anitrack.app.ui.art.PosterSlot
import com.anitrack.app.ui.chrome.ScrollEdgeChromeBox
import com.anitrack.app.ui.chrome.chromeHazeSource
import com.anitrack.app.ui.chrome.tabBarContentBottom
import com.anitrack.app.ui.card.ShelfCard
import com.anitrack.app.ui.control.ChipButton
import com.anitrack.app.ui.control.FilterChip
import com.anitrack.app.ui.control.InlineLinkButton
import com.anitrack.app.ui.control.PressStyle
import com.anitrack.app.ui.control.materialGlyphBox
import com.anitrack.app.ui.control.minimumTapTarget
import com.anitrack.app.ui.isAccessibilityTextSize
import com.anitrack.app.ui.list.GroupedList
import com.anitrack.app.ui.list.GroupedRow
import com.anitrack.app.ui.list.GroupedTrailing
import com.anitrack.app.ui.row.LocalListTrailingInset
import com.anitrack.app.ui.row.MediaRow
import com.anitrack.app.ui.section.SectionLabel
import com.anitrack.app.ui.state.EmptyState
import com.anitrack.app.ui.state.Freshness
import com.anitrack.app.ui.state.InlineNotice
import com.anitrack.app.ui.state.SkeletonGate
import com.anitrack.app.ui.state.SkeletonRow
import com.anitrack.app.ui.state.centredState
import com.anitrack.model.Franchise
import com.anitrack.model.TimeAnchor
import com.anitrack.model.WatchStatus
import com.anitrack.model.continueBacklog
import com.anitrack.model.copy.Copy
import com.anitrack.model.copy.CopyDates
import com.anitrack.model.copy.CopyLibrary
import com.anitrack.model.copy.EmptyStateCopy
import com.anitrack.model.displayTitle
import com.anitrack.model.effectiveStatus
import com.anitrack.model.lastAiredSortKey
import com.anitrack.model.portraitArt
import com.anitrack.model.timeAnchor
import java.text.Collator
import java.text.Normalizer
import java.util.Locale
import kotlin.math.roundToInt
import kotlinx.coroutines.launch

/*
 * ALL TITLES — the port of `LibraryAllView` and its Sort & filter sheet from
 * `ios/Sources/Features/Library/LibraryView.swift`.
 *
 * **The one Library screen with controls on it.** Search, sort, direction, a status filter, an
 * unwatched-episodes axis, a poster/list view toggle and an A–Z index rail — everything the calm
 * root deliberately does not have.
 *
 * Invariants a reviewer should check on the Android build:
 *
 *  * **One show, one caption, in both view modes.** The list and the poster wall call the same
 *    `LibraryRowFacts.catalogue(...)`, with `compact` changing layout only. "The wall said 'Episode 1
 *    next' in amber where the list said 'Watched' in grey for the same show one segment apart. A
 *    user reads that as the app losing their data."
 *  * **"Has unwatched episodes" is exactly `AppModel.outNow`**, so a "View all 12 updates" entry
 *    lands on twelve rows. The shipped predicate was its own and counted unaired seasons.
 *  * **Section headers and the index rail appear together or not at all.** They share one threshold
 *    so "the two controls never disagree about whether this list has sections."
 *  * **`results` / `sections` / `sectioned` / `rail` are computed once per frame**, not per consumer.
 *  * **The footer count is inside the same view as the list**, not a sibling of it.
 */

// =================================================================================================
// MARK: - The instrument's vocabulary
// =================================================================================================

/** The four orders. Each names its own reversal, or a chip that says "reversed" would be lying. */
enum class LibrarySort(val label: String, val reversedLabel: String) {
    TITLE(CopyLibrary.sortTitle, CopyLibrary.reversedTitle),
    ADDED(CopyLibrary.sortAdded, CopyLibrary.reversedAdded),
    RECENT(CopyLibrary.sortRecent, CopyLibrary.reversedRecent),
    PROGRESS(CopyLibrary.sortProgress, CopyLibrary.reversedProgress),
}

/** Posters or rows. **A preference, not a filter** — see `AllTitlesFilters.hasFilters`. */
enum class DisplayMode(val label: String) {
    POSTERS(CopyLibrary.posters),
    LIST(CopyLibrary.list),
}

/** The status axis. */
@Immutable
sealed interface StatusFilter {

    /** No filter. *"A chip states the criterion, and 'Any' is not one."* */
    data object AnyStatus : StatusFilter

    @Immutable
    data class Of(val status: WatchStatus) : StatusFilter

    val label: String
        get() = when (this) {
            AnyStatus -> CopyLibrary.anyStatus
            is Of -> Copy.statusLabel(status.wire)
        }

    /** `null` for [AnyStatus] — there is no chip for the absence of a criterion. */
    val chip: String? get() = if (this is Of) label else null

    /** True when a chip above the list already states every row's list state. */
    val givesState: Boolean get() = this is Of

    val watchStatus: WatchStatus? get() = (this as? Of)?.status
}

/** One bucket of the list, with the key its header prints. */
@Immutable
data class TitleSection(val key: String, val items: List<Franchise>)

// =================================================================================================
// MARK: - Metrics
// =================================================================================================

private object AllTitlesMetrics {

    /**
     * Below this a flick is faster than an alphabet: *"a thirty-title library dressed in letter
     * headers and a rail read as a phone book for one street. At the stated 300 titles the rail is
     * the difference between finding 'Vinland Saga' and hunting for it."*
     */
    const val sectionFloor = 48

    /** The rail's reserved drawing lane, matching Contacts. Every row stops short of it. */
    val railLane = 28.dp

    /**
     * The gesture host, reaching 16 dp into the rows' trailing padding — the app's minimum target,
     * spelled [minimumTapTarget] rather than 44 a second time.
     */
    val railHit = minimumTapTarget

    /** Minimum band height, so a 15-letter rail cannot become a 15-dp-per-letter ribbon. */
    val railMinStep = 22.dp

    /** The poster wall's columns. Fixed, never adaptive — adaptive "leaves a ragged 30 dp". */
    const val gridColumns = 3

    /** The all-titles skeleton: eight rows of the shape that is coming. */
    const val skeletonRows = 8

    /** The search field's own capsule inside the 52-dp drawer. */
    val searchFieldHeight = 36.dp

    /** The `View as` segmented control. */
    val segmentedWidth = 168.dp
    val segmentedHeight = 32.dp

    /** The sheet header's band. */
    val sheetHeaderHeight = 52.dp

    /** A grouped row's leading inset, matching `GroupedRow`'s own. */
    val groupedLeadingInset = 14.dp

    /** Glyphs, at their iOS point sizes. `materialGlyphBox` owns the SF→Material conversion. */
    val barGlyph = 17.dp
    val fieldGlyph = 13.dp
    val clearGlyph = 12.dp
    val popupGlyph = 12.dp
    val checkGlyph = 15.dp

    /** The skeleton row's two lines. */
    val skeletonTitleWidth = 196.dp
    val skeletonMetaWidth = 108.dp
}

// =================================================================================================
// MARK: - The screen
// =================================================================================================

/**
 * All titles.
 *
 * **Every filter is seeded in the initialiser**, never applied after the first frame: *"Applied
 * late, the screen builds once unfiltered and once filtered — the user sees the whole library flash
 * past on the way to the six rows they asked for, and the rows that survive both passes can keep the
 * first pass's copy (rows under a `Watching` chip still reading 'Watching')."* The caller keys this
 * composable on the route's identity so a *different* route builds a fresh one.
 *
 * @param washArt the ROOT's already-computed wash art, handed through the push. Without it "the
 *   pushed screen lit itself from its first alphabetical row … and the push visibly changed the
 *   room's light."
 * @param initialUnwatchedOnly **composes with** [initialStatus] rather than replacing it.
 */
@Composable
fun AllTitlesScreen(
    appModel: AppModel,
    dates: CopyDates,
    onOpenDetail: (String) -> Unit,
    onAddShow: () -> Unit,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
    initialStatus: WatchStatus? = null,
    initialReturning: ReturnScope? = null,
    initialSort: LibrarySort = LibrarySort.TITLE,
    initialUnwatchedOnly: Boolean = false,
    washArt: String? = null,
) {
    val scope = rememberCoroutineScope()
    val isAX = isAccessibilityTextSize()

    var query by remember { mutableStateOf("") }
    var sort by remember { mutableStateOf(initialSort) }
    var sortAscending by remember { mutableStateOf(false) }
    var status by remember {
        mutableStateOf<StatusFilter>(
            initialStatus?.let { StatusFilter.Of(it) } ?: StatusFilter.AnyStatus,
        )
    }
    var unwatchedOnly by remember { mutableStateOf(initialUnwatchedOnly) }
    var returning by remember { mutableStateOf(initialReturning) }
    var display by remember { mutableStateOf(DisplayMode.LIST) }
    var showArrange by remember { mutableStateOf(false) }
    var searchPresented by remember { mutableStateOf(false) }
    var pullDriving by remember { mutableStateOf(false) }

    // The port of `localizedCaseInsensitiveCompare`, and **there is exactly ONE of it**. Three sorts
    // once broke ties three different ways — `lowercased()`, the raw title, a locale-aware compare —
    // "so 'Ōoku' moved between them." `SECONDARY` strength drops case while keeping accents.
    val collator = remember { Collator.getInstance().apply { strength = Collator.SECONDARY } }

    val library = appModel.library

    // `filtered()` is a FUNCTION, not a computed property: on iOS it was read from eight sites per
    // render (the list, the grid, the rail, the rotor, `showsRail`, `isSectioned`, the footer and
    // the rail's spoken value), each one re-filtering and re-sorting the library. It resolves once
    // here, in order, and the results are passed down.
    val results = remember(
        library, appModel.nowMinute, query, sort, sortAscending, status, unwatchedOnly, returning,
    ) {
        filtered(
            library = library,
            appModel = appModel,
            query = query,
            status = status,
            unwatchedOnly = unwatchedOnly,
            returning = returning,
            sort = sort,
            ascending = sortAscending,
            collator = collator,
        )
    }
    val sectioned = remember(results, sort) { isSectioned(results, sort) }
    val rail = remember(results, sort, isAX) { showsRail(results, sort, isAX) }
    val sections = remember(results, sort, sectioned) { titleSections(results, sort, sectioned) }
    val headerIndices = remember(sections, sectioned) { headerIndexMap(sections, sectioned) }

    val filters = AllTitlesFilters(sort, sortAscending, status, unwatchedOnly, returning)
    val resetFilters: () -> Unit = {
        FeedbackCoordinator.fire(FeedbackToken.SELECTION)
        sort = LibrarySort.TITLE
        sortAscending = false
        status = StatusFilter.AnyStatus
        unwatchedOnly = false
        returning = null
        // Deliberately does NOT touch `display` or `query`.
    }

    // Named the same way, and for a reason beyond tidiness: `scope.launch` answers with a `Job`, so
    // an anonymous `{ scope.launch { … } }` types as `() -> Job`. Handed straight to a parameter it
    // coerces to `Unit`; inside an `if` it does not — the branches widen to `() -> Any` and the call
    // stops compiling. Declared once, with its type, it is simply a handler.
    val retry: () -> Unit = { scope.launch { appModel.reload() } }

    // The hardened bar holds through the title AND the drawer; when the field takes focus the title
    // collapses, so the hold shrinks with it.
    val searchChromeBottom =
        if (searchPresented) {
            ThemeMetrics.topSafeInset() + ThemeMetrics.searchDrawerHeight
        } else {
            ThemeMetrics.inlineBarBottom() + ThemeMetrics.searchDrawerHeight
        }

    val listState = rememberLazyListState()
    val gridState = rememberLazyGridState()
    val posters = display == DisplayMode.POSTERS

    // Derived and guarded: the boolean notifies its readers on the CROSSING, never on the scroll.
    // The raw offset is never screen state — that is the exact jank the iOS app fixed twice.
    val raisedTop by remember(listState, gridState, posters) {
        derivedStateOf {
            if (posters) {
                gridState.firstVisibleItemIndex > 0 || gridState.firstVisibleItemScrollOffset > 0
            } else {
                listState.firstVisibleItemIndex > 0 || listState.firstVisibleItemScrollOffset > 0
            }
        }
    }

    val wash = washArt
        ?: results.firstOrNull()?.portraitArt
        ?: library.firstOrNull()?.portraitArt

    Box(modifier.fillMaxSize().background(ThemeColor.canvas)) {
        ScrollEdgeChromeBox(
            modifier = Modifier.fillMaxSize(),
            softTop = true,
            topRaised = raisedTop,
            topHeight = ThemeMetrics.topSafeInset() + ThemeMetrics.searchDrawerHeight,
            topHold = searchChromeBottom,
        ) {
            ArtBackdrop(
                modifier = Modifier.align(Alignment.TopCenter),
                url = wash,
                tint = if (wash == null) ThemeColor.accent else null,
            )

            PreviouslyPullToRefresh(
                modifier = Modifier.fillMaxSize(),
                onRefresh = { appModel.reload() },
                onDrivingChange = { if (it != pullDriving) pullDriving = it },
            ) {
                BoxWithConstraints(Modifier.fillMaxSize()) {
                    val contentHeight = maxHeight
                    val contentWidth = maxWidth
                    val lane = if (rail) AllTitlesMetrics.railLane else 0.dp

                    val lead: @Composable () -> Unit = {
                        LeadBlock(
                            appModel = appModel,
                            dates = dates,
                            filters = filters,
                            onClearStatus = {
                                FeedbackCoordinator.fire(FeedbackToken.SELECTION)
                                status = StatusFilter.AnyStatus
                            },
                            onClearUnwatched = {
                                FeedbackCoordinator.fire(FeedbackToken.SELECTION)
                                unwatchedOnly = false
                            },
                            onClearReturning = {
                                FeedbackCoordinator.fire(FeedbackToken.SELECTION)
                                returning = null
                            },
                            onClearSort = {
                                FeedbackCoordinator.fire(FeedbackToken.SELECTION)
                                sort = LibrarySort.TITLE
                                sortAscending = false
                            },
                            onReset = resetFilters,
                            onRetry = retry,
                        )
                    }

                    val emptyState: (@Composable () -> Unit)? = when {
                        library.isEmpty() -> {
                            {
                                EmptyState(
                                    copy = appModel.emptyStateCopy,
                                    modifier = Modifier
                                        .padding(horizontal = ThemeMetrics.gutter)
                                        .centredState(contentHeight),
                                    // The empty state's one action, and it is always a live one.
                                    onPrimary = if (appModel.loadError) retry else onAddShow,
                                )
                            }
                        }

                        results.isEmpty() -> {
                            {
                                val copy = emptyResultsCopy(query, filters.hasFilters)
                                EmptyState(
                                    copy = copy,
                                    modifier = Modifier
                                        .padding(horizontal = ThemeMetrics.gutter)
                                        .centredState(contentHeight),
                                    onPrimary = if (copy.primaryLabel == null) {
                                        null
                                    } else {
                                        resetFilters
                                    },
                                )
                            }
                        }

                        else -> null
                    }

                    // The rail OWNS a lane, and every `MediaRow` inside stops short of it.
                    CompositionLocalProvider(LocalListTrailingInset provides lane) {
                        SkeletonGate(
                            isLoading = appModel.loading && library.isEmpty(),
                            modifier = Modifier.fillMaxSize(),
                            skeleton = { AllTitlesSkeleton(topInset = searchChromeBottom) },
                        ) {
                            // ONE view: `SkeletonGate` lays its content out in a box, and two
                            // siblings handed to it printed "30 titles" across the first row. The
                            // footer count therefore lives INSIDE the list, not beside it.
                            if (posters) {
                                PosterWall(
                                    appModel = appModel,
                                    sections = sections,
                                    sectioned = sectioned,
                                    headerIndices = headerIndices,
                                    state = gridState,
                                    contentWidth = contentWidth,
                                    lane = lane,
                                    topInset = searchChromeBottom,
                                    stateIsGiven = status.givesState,
                                    count = results.size,
                                    lead = lead,
                                    emptyState = emptyState,
                                    onOpenDetail = onOpenDetail,
                                )
                            } else {
                                TitleList(
                                    appModel = appModel,
                                    sections = sections,
                                    sectioned = sectioned,
                                    state = listState,
                                    lane = lane,
                                    topInset = searchChromeBottom,
                                    stateIsGiven = status.givesState,
                                    count = results.size,
                                    lead = lead,
                                    emptyState = emptyState,
                                    onOpenDetail = onOpenDetail,
                                )
                            }
                        }
                    }
                }
            }

            if (rail) {
                IndexRail(
                    keys = sections.map { it.key },
                    topInset = searchChromeBottom,
                    modifier = Modifier.align(Alignment.CenterEnd),
                    onSelect = { key ->
                        val index = headerIndices[key]
                        if (index != null) {
                            scope.launch {
                                if (posters) {
                                    gridState.scrollToItem(index)
                                } else {
                                    listState.scrollToItem(index)
                                }
                            }
                        }
                    },
                )
            }
        }

        // The bar and the drawer draw ABOVE the veil, so they are siblings of the chrome box.
        Column(Modifier.align(Alignment.TopCenter)) {
            AnimatedVisibility(
                visible = !searchPresented,
                enter = fadeIn(ThemeMotion.uiGentle()),
                exit = fadeOut(ThemeMotion.uiGentle()),
            ) {
                InlineChromeBar(
                    title = Copy.Heading.allTitles,
                    leading = { BackButton(onBack) },
                    trailing = { ArrangeButton(filters.hasFilters) { showArrange = true } },
                )
            }
            SearchDrawer(
                query = query,
                onQueryChange = { query = it },
                focused = searchPresented,
                onFocusChanged = { searchPresented = it },
                scrolling = if (posters) {
                    gridState.isScrollInProgress
                } else {
                    listState.isScrollInProgress
                },
            )
        }

        if (showArrange) {
            ArrangeSheet(
                sort = sort,
                onSort = { value -> select(sort, value) { sort = value } },
                ascending = sortAscending,
                onAscending = { value -> select(sortAscending, value) { sortAscending = value } },
                status = status,
                onStatus = { value -> select(status, value) { status = value } },
                unwatchedOnly = unwatchedOnly,
                onUnwatchedOnly = { value ->
                    select(unwatchedOnly, value) { unwatchedOnly = value }
                },
                display = display,
                onDisplay = { value -> select(display, value) { display = value } },
                onReset = resetFilters,
                onDismiss = { showArrange = false },
            )
        }
    }
}

/** The active axes, resolved once so the chip row, the sheet and the toolbar glyph agree. */
@Immutable
private data class AllTitlesFilters(
    val sort: LibrarySort,
    val ascending: Boolean,
    val status: StatusFilter,
    val unwatchedOnly: Boolean,
    val returning: ReturnScope?,
) {
    /**
     * **`display` is deliberately excluded.** *"A filter is a thing the user chose that hides rows.
     * The view mode is not one — which is why the shipped 'Posters … Clear' row offered a
     * destructive-sounding action against a state that was nowhere on screen."* `query` is excluded
     * too: it names itself.
     */
    val hasFilters: Boolean
        get() = status != StatusFilter.AnyStatus ||
            unwatchedOnly ||
            returning != null ||
            sort != LibrarySort.TITLE ||
            ascending
}

/**
 * A picker writes straight through its binding, so the haptic lives in the binding.
 *
 * iOS additionally wraps the mutation in `withAnimation(uiMicro)`; on Android the transition belongs
 * to the views that animate (the chip row's `AnimatedVisibility`, the footer count's
 * `AnimatedContent`), so the binding states the fact and fires the tick.
 */
private inline fun <V> select(current: V, new: V, apply: () -> Unit) {
    if (new == current) return
    FeedbackCoordinator.fire(FeedbackToken.SELECTION)
    apply()
}

// =================================================================================================
// MARK: - Filtering, sorting, sectioning
// =================================================================================================

private fun filtered(
    library: List<Franchise>,
    appModel: AppModel,
    query: String,
    status: StatusFilter,
    unwatchedOnly: Boolean,
    returning: ReturnScope?,
    sort: LibrarySort,
    ascending: Boolean,
    collator: Collator,
): List<Franchise> {
    val q = query.trim().lowercase()
    // **Exactly the set Today counts**, resolved once per pass, "so 'View all 12 updates' lands on
    // twelve rows. The shipped predicate was its own (`markTarget > progress`), which counted
    // unaired seasons as unwatched and could not agree with the number that opened the screen."
    val outNow: Set<String> =
        if (unwatchedOnly) appModel.outNow.mapTo(HashSet()) { it.id } else emptySet()
    val wanted = status.watchStatus

    val matched = library.filter { f ->
        (wanted == null || f.effectiveStatus == wanted) &&
            (!unwatchedOnly || outNow.contains(f.id)) &&
            (returning == null || LibraryShelving.section(f, appModel) == returning.section) &&
            // The RAW title, case-insensitively, as a substring — never `displayTitle`. In search a
            // user is matching what they typed against a catalogue, and every character is evidence.
            (q.isEmpty() || f.title.lowercase().contains(q))
    }

    val titleAscending = Comparator<Franchise> { a, b -> collator.compare(a.title, b.title) }
    val sorted = when (sort) {
        LibrarySort.TITLE -> matched.sortedWith(titleAscending)
        // Newest first; an unknown date sorts LAST, never as 1970.
        LibrarySort.ADDED -> matched.sortedWith(
            largestFirst({ it.subscription?.addedAt ?: Long.MIN_VALUE }, titleAscending),
        )
        LibrarySort.RECENT -> matched.sortedWith(
            largestFirst({ it.lastAiredSortKey }, titleAscending),
        )
        LibrarySort.PROGRESS -> matched.sortedWith(
            largestFirst({ it.continueBacklog.toLong() }, titleAscending),
        )
    }
    // The WHOLE array reverses, tie-break included.
    return if (ascending) sorted.reversed() else sorted
}

/**
 * The one descending comparator all three descending sorts share: largest key first, `titleAscending`
 * between equals.
 *
 * **There is exactly ONE tie-break and one title order.**
 */
private fun largestFirst(
    key: (Franchise) -> Long,
    tie: Comparator<Franchise>,
): Comparator<Franchise> = Comparator { a, b ->
    val ka = key(a)
    val kb = key(b)
    if (ka != kb) kb.compareTo(ka) else tie.compare(a, b)
}

/** Headers and the rail share this threshold so the two controls can never disagree. */
private fun isSectioned(results: List<Franchise>, sort: LibrarySort): Boolean =
    sort != LibrarySort.PROGRESS && results.size > AllTitlesMetrics.sectionFloor

private fun showsRail(results: List<Franchise>, sort: LibrarySort, isAX: Boolean): Boolean =
    sort == LibrarySort.TITLE && results.size > AllTitlesMetrics.sectionFloor && !isAX

/**
 * The buckets.
 *
 * **One bucket when the list is not sectioned**, rather than per-letter buckets with hidden headers:
 * *"A `Section` inside a grid starts a new ROW even when its header is empty, so leaving the
 * per-letter buckets in place and merely hiding the headers laid a ten-title poster wall out
 * two-then-one down the page with holes where the letters changed."*
 */
private fun titleSections(
    results: List<Franchise>,
    sort: LibrarySort,
    sectioned: Boolean,
): List<TitleSection> {
    if (!sectioned) return listOf(TitleSection("", results))
    return when (sort) {
        LibrarySort.TITLE -> {
            val buckets = LinkedHashMap<String, MutableList<Franchise>>()
            for (f in results) buckets.getOrPut(indexKey(f.title)) { ArrayList() }.add(f)
            buckets.entries
                // "#" is LAST; everything else ascending by string.
                .sortedWith(compareBy({ if (it.key == HASH_KEY) 1 else 0 }, { it.key }))
                .map { TitleSection(it.key, it.value) }
        }

        LibrarySort.ADDED, LibrarySort.RECENT -> {
            val buckets = LinkedHashMap<String, MutableList<Franchise>>()
            for (f in results) {
                // The two anchors differ on purpose: `addedAt` is the user's own instant (local); an
                // airing is read in the franchise's calendar so a TMDB date-only row lands in the
                // month it names.
                val key = if (sort == LibrarySort.ADDED) {
                    monthKey(f.subscription?.addedAt ?: 0L, TimeAnchor.LOCAL)
                } else {
                    monthKey(f.lastAiredSortKey, f.timeAnchor)
                }
                buckets.getOrPut(key) { ArrayList() }.add(f)
            }
            // FIRST-SEEN order: the sort already ordered them.
            buckets.map { TitleSection(it.key, it.value) }
        }

        LibrarySort.PROGRESS -> listOf(TitleSection("", results))
    }
}

private const val HASH_KEY = "#"
private val COMBINING_MARKS = Regex("\\p{Mn}+")

/**
 * The port of `String.folding(options: [.diacriticInsensitive, .caseInsensitive])` plus the
 * first-letter scan: NFD-normalise, strip combining marks, take the first letter or digit.
 *
 * A digit or a symbol files under "#", which sorts last.
 */
fun indexKey(title: String): String {
    val folded = COMBINING_MARKS.replace(Normalizer.normalize(title, Normalizer.Form.NFD), "")
    val first = folded.firstOrNull { it.isLetter() || it.isDigit() } ?: return HASH_KEY
    return if (first.isLetter()) first.toString().uppercase(Locale.getDefault()) else HASH_KEY
}

/**
 * The month a dated bucket names.
 *
 * **`at` is MILLISECONDS.** It was read as seconds here once, which put the "Recently updated" month
 * headers roughly fifty-five thousand years out.
 */
private fun monthKey(at: Long, anchor: TimeAnchor): String =
    if (at > 0) LibraryDates.monthYear(at, anchor) else CopyLibrary.noDate

/**
 * key → flattened item index, for the rail's programmatic scroll.
 *
 * `LazyListState.scrollToItem` needs an INDEX, not an id, so the map is maintained beside the
 * sections. Both view modes emit the same item sequence — one lead block, then a header plus its
 * items per section — so one map serves both.
 */
private fun headerIndexMap(sections: List<TitleSection>, sectioned: Boolean): Map<String, Int> {
    if (!sectioned) return emptyMap()
    val out = LinkedHashMap<String, Int>(sections.size)
    var index = 1 // the lead block
    for (section in sections) {
        out[section.key] = index
        index += 1 + section.items.size
    }
    return out
}

private fun emptyResultsCopy(query: String, hasFilters: Boolean): EmptyStateCopy =
    if (query.isEmpty()) {
        // Only a filter can empty a query-less list, so the recovery is guaranteed to be present.
        EmptyStateCopy.noFilterMatches
    } else {
        // With filters ALSO narrowing the list the card offers to clear them. Without it "a query
        // under a 'Watched' chip dead-ended on a card with no way out but the chip row."
        CopyLibrary.noSearchResults(query, hasFilters)
    }

// =================================================================================================
// MARK: - The lead block: freshness, notice, chips
// =================================================================================================

@Composable
private fun LeadBlock(
    appModel: AppModel,
    dates: CopyDates,
    filters: AllTitlesFilters,
    onClearStatus: () -> Unit,
    onClearUnwatched: () -> Unit,
    onClearReturning: () -> Unit,
    onClearSort: () -> Unit,
    onReset: () -> Unit,
    onRetry: () -> Unit,
) {
    Column(Modifier.fillMaxWidth()) {
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
                onRetry = onRetry,
            )
        }

        ChipRow(
            filters = filters,
            onClearStatus = onClearStatus,
            onClearUnwatched = onClearUnwatched,
            onClearReturning = onClearReturning,
            onClearSort = onClearSort,
            onReset = onReset,
        )
    }
}

/**
 * The active criteria, each with its own ×.
 *
 * **Reset appears only when there is more than one chip**, and it is a NEUTRAL chip: *"returning to
 * the default is the smallest thing on the row, and the screen's one accent is not spent on a
 * utility."* The sort chip must name its direction — *"a 'Recently added' chip that silently means
 * oldest first is a lie the reader cannot see."*
 */
@Composable
private fun ChipRow(
    filters: AllTitlesFilters,
    onClearStatus: () -> Unit,
    onClearUnwatched: () -> Unit,
    onClearReturning: () -> Unit,
    onClearSort: () -> Unit,
    onReset: () -> Unit,
) {
    val chips: List<Pair<String, () -> Unit>> = buildList {
        filters.status.chip?.let { add(it to onClearStatus) }
        if (filters.unwatchedOnly) add(CopyLibrary.hasUnwatched to onClearUnwatched)
        filters.returning?.let { add(it.label to onClearReturning) }
        if (filters.sort != LibrarySort.TITLE || filters.ascending) {
            val label = if (filters.ascending) {
                CopyLibrary.reversed(filters.sort.label)
            } else {
                filters.sort.label
            }
            add(label to onClearSort)
        }
    }
    val scrollState = rememberScrollState()

    AnimatedVisibility(
        visible = chips.isNotEmpty(),
        enter = fadeIn(ThemeMotion.uiGentle()),
        exit = fadeOut(ThemeMotion.uiGentle()),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                // A criterion never becomes a second line of chrome: the row scrolls.
                .horizontalScroll(scrollState)
                .padding(horizontal = ThemeMetrics.gutter)
                .padding(bottom = ThemeSpace.x2),
            horizontalArrangement = Arrangement.spacedBy(ThemeSpace.x2),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            for ((text, clear) in chips) {
                FilterChip(text = text, onRemove = clear)
            }
            if (chips.size > 1) {
                ChipButton(text = Copy.Action.reset, onClick = onReset)
            }
        }
    }
}

// =================================================================================================
// MARK: - The list
// =================================================================================================

/**
 * The rows.
 *
 * **Lazy and sectioned is a hard requirement**: at the stated 300-title library an eager column
 * instantiates 300 rows and 300 image requests on push.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun TitleList(
    appModel: AppModel,
    sections: List<TitleSection>,
    sectioned: Boolean,
    state: LazyListState,
    lane: Dp,
    topInset: Dp,
    stateIsGiven: Boolean,
    count: Int,
    lead: @Composable () -> Unit,
    emptyState: (@Composable () -> Unit)?,
    onOpenDetail: (String) -> Unit,
) {
    LazyColumn(
        state = state,
        modifier = Modifier.fillMaxSize().chromeHazeSource(),
        // NO top lead-in: the search drawer carries its own margin.
        contentPadding = PaddingValues(top = topInset, bottom = tabBarContentBottom()),
    ) {
        item(key = "lead") { lead() }

        if (emptyState != null) {
            item(key = "empty") { emptyState() }
            return@LazyColumn
        }

        for (section in sections) {
            if (sectioned) {
                stickyHeader(key = "sec-${section.key}") {
                    LetterHeader(
                        key = section.key,
                        // The header's rule shares the row separators' left edge.
                        ruleInset = ThemeMetrics.rowRuleInset,
                        trailingInset = lane,
                    )
                }
            }
            itemsIndexed(items = section.items, key = { _, f -> f.id }) { index, franchise ->
                val facts = LibraryRowFacts.catalogue(franchise, appModel, stateIsGiven)
                FranchiseQuickActions(franchise = franchise, appModel = appModel) {
                    MediaRow(
                        title = franchise.displayTitle,
                        onClick = { onOpenDetail(franchise.id) },
                        modifier = Modifier.padding(horizontal = ThemeMetrics.gutter),
                        meta = facts.meta,
                        lead = facts.lead,
                        poster = franchise.portraitArt,
                        slot = PosterSize.Row,
                        separator = index < section.items.lastIndex,
                        hint = Copy.Accessibility.opensTheShowHint,
                    )
                }
            }
        }

        item(key = "footer") { FooterCount(count) }
    }
}

// =================================================================================================
// MARK: - The poster wall
// =================================================================================================

/**
 * The wall.
 *
 * `LazyVerticalGrid` has **no** sticky-header API, so the pinned letter header is hand-rolled: the
 * header is a full-span item in flow, and an opaque full-bleed copy is overlaid at the top of the
 * viewport while its own section is the one being read.
 */
@Composable
private fun PosterWall(
    appModel: AppModel,
    sections: List<TitleSection>,
    sectioned: Boolean,
    headerIndices: Map<String, Int>,
    state: LazyGridState,
    contentWidth: Dp,
    lane: Dp,
    topInset: Dp,
    stateIsGiven: Boolean,
    count: Int,
    lead: @Composable () -> Unit,
    emptyState: (@Composable () -> Unit)?,
    onOpenDetail: (String) -> Unit,
) {
    val columns = AllTitlesMetrics.gridColumns
    // Fixed columns, computed exactly as the shipped grid computes them.
    val available = (contentWidth - ThemeMetrics.gutter * 2 - lane).coerceAtLeast(0.dp)
    val cellWidth = if (available > 0.dp) {
        (available - ThemeMetrics.shelfGap * (columns - 1)) / columns
    } else {
        PosterSize.ShelfMedium.width
    }

    val pinned by remember(sections, headerIndices, state) {
        derivedStateOf {
            if (headerIndices.isEmpty()) {
                null
            } else {
                val first = state.firstVisibleItemIndex
                sections.lastOrNull { (headerIndices[it.key] ?: Int.MAX_VALUE) <= first }?.key
            }
        }
    }

    Box(Modifier.fillMaxSize()) {
        LazyVerticalGrid(
            columns = GridCells.Fixed(columns),
            state = state,
            modifier = Modifier
                .fillMaxSize()
                .padding(end = lane)
                .chromeHazeSource(),
            contentPadding = PaddingValues(
                start = ThemeMetrics.gutter,
                end = ThemeMetrics.gutter,
                top = topInset + ThemeSpace.x2,
                bottom = tabBarContentBottom(),
            ),
            horizontalArrangement = Arrangement.spacedBy(ThemeMetrics.shelfGap),
            verticalArrangement = Arrangement.spacedBy(ThemeSpace.x6),
        ) {
            item(key = "lead", span = { GridItemSpan(maxLineSpan) }) { lead() }

            if (emptyState != null) {
                item(key = "empty", span = { GridItemSpan(maxLineSpan) }) { emptyState() }
                return@LazyVerticalGrid
            }

            for (section in sections) {
                if (sectioned) {
                    item(key = "sec-${section.key}", span = { GridItemSpan(maxLineSpan) }) {
                        LetterHeader(
                            key = section.key,
                            // No poster column to align to in the wall, so the rule starts at the
                            // gutter — and the header reaches the bezels back out of the grid's own
                            // content padding.
                            ruleInset = ThemeMetrics.gutter,
                            trailingInset = 0.dp,
                            bleed = ThemeMetrics.gutter,
                        )
                    }
                }
                items(items = section.items, key = { it.id }) { franchise ->
                    PosterWallCell(
                        franchise = franchise,
                        appModel = appModel,
                        stateIsGiven = stateIsGiven,
                        cellWidth = cellWidth,
                        onOpen = { onOpenDetail(franchise.id) },
                    )
                }
            }

            item(key = "footer", span = { GridItemSpan(maxLineSpan) }) { FooterCount(count) }
        }

        val pinnedKey = pinned
        if (pinnedKey != null) {
            LetterHeader(
                key = pinnedKey,
                ruleInset = ThemeMetrics.gutter,
                trailingInset = lane,
                modifier = Modifier
                    .align(Alignment.TopCenter)
                    .padding(top = topInset),
            )
        }
    }
}

/**
 * One cell of the poster wall: the shared [ShelfCard], at the grid's measured column width, inside
 * this screen's long-press quick actions.
 *
 * It used to be a second poster-cell anatomy — `ShelfCard` re-implemented line for line, with the
 * same press radius and the same verbatim comment, over a private constant set
 * (`GRID_TITLE_MIN_SCALE` etc.) that matched `ShelfCard`'s by coincidence and would have drifted on
 * the next tune — while Search's poster grid IS a `ShelfCard` grid. Two poster grids in one product
 * were two components.
 */
@Composable
private fun PosterWallCell(
    franchise: Franchise,
    appModel: AppModel,
    stateIsGiven: Boolean,
    cellWidth: Dp,
    onOpen: () -> Unit,
) {
    // Resolved ONCE per cell: "calling the accessor twice to pick a colour is how a caption and its
    // colour drift apart."
    val facts = LibraryRowFacts.catalogue(franchise, appModel, stateIsGiven, compact = true)

    FranchiseQuickActions(franchise = franchise, appModel = appModel) {
        ShelfCard(
            // The WHOLE title: the card shortens it for display and speaks it in full.
            title = franchise.title,
            onClick = onOpen,
            caption = facts.lead ?: facts.meta,
            captionIsLead = facts.lead != null,
            poster = franchise.portraitArt,
            slot = PosterSize.ShelfMedium,
            hint = Copy.Accessibility.opensTheShowHint,
            width = cellWidth,
        )
    }
}

// =================================================================================================
// MARK: - Section furniture
// =================================================================================================

/**
 * The pinned letter (or month) header.
 *
 * It is **opaque** because content scrolls under it — but it must be **full-bleed**: *"inset to the
 * gutter it painted a visible canvas rectangle against the ambient wash behind the list — a plate,
 * which is exactly what a pinned header must not look like."*
 *
 * @param bleed how far the header must reach back out of a container's own horizontal padding (the
 *   grid's content padding). The list's items carry their gutters themselves, so it is 0 there.
 */
@Composable
private fun LetterHeader(
    key: String,
    ruleInset: Dp,
    trailingInset: Dp,
    modifier: Modifier = Modifier,
    bleed: Dp = 0.dp,
) {
    Box(
        modifier
            .fillMaxWidth()
            .then(if (bleed > 0.dp) Modifier.bleedHorizontal(bleed) else Modifier)
            .background(ThemeColor.canvas),
    ) {
        SectionLabel(
            text = key,
            tint = ThemeColor.textTertiary,
            modifier = Modifier
                .padding(
                    start = ThemeMetrics.gutter,
                    top = ThemeSpace.x3,
                    bottom = ThemeSpace.x1,
                )
                .semantics { heading() },
        )
        Spacer(
            Modifier
                .align(Alignment.BottomStart)
                .fillMaxWidth()
                .padding(start = ruleInset, end = trailingInset)
                .height(1.dp)
                .background(ThemeColor.separatorQuiet),
        )
    }
}

/**
 * The port of SwiftUI's `.padding(.horizontal, -inset)` — measure wider than the parent proposed and
 * place the surplus outside it, so a header inside a padded container still reaches the bezels.
 */
private fun Modifier.bleedHorizontal(inset: Dp): Modifier = layout { measurable, constraints ->
    val extra = inset.roundToPx() * 2
    val widened = if (constraints.hasBoundedWidth) {
        constraints.copy(
            minWidth = constraints.minWidth + extra,
            maxWidth = constraints.maxWidth + extra,
        )
    } else {
        constraints.copy(minWidth = constraints.minWidth + extra, maxWidth = Constraints.Infinity)
    }
    val placeable = measurable.measure(widened)
    layout((placeable.width - extra).coerceAtLeast(0), placeable.height) {
        placeable.place(-inset.roundToPx(), 0)
    }
}

/**
 * "30 titles" under the last row.
 *
 * It is INSIDE the same view as the list, never a sibling of it: `SkeletonGate` lays its content out
 * in a box, and two siblings handed to it printed "30 titles" across the first row.
 */
@Composable
private fun FooterCount(count: Int) {
    val reduceMotion = LocalReduceMotion.current
    AnimatedContent(
        targetState = count,
        transitionSpec = {
            if (reduceMotion) {
                fadeIn(ThemeMotion.uiCrossfade()) togetherWith fadeOut(ThemeMotion.uiCrossfade())
            } else {
                // The digit roll.
                (
                    slideInVertically(ThemeMotion.uiNumeric<IntOffset>()) { it } +
                        fadeIn(ThemeMotion.uiNumeric())
                    ) togetherWith (
                    slideOutVertically(ThemeMotion.uiNumeric<IntOffset>()) { -it } +
                        fadeOut(ThemeMotion.uiNumeric())
                    )
            }
        },
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = ThemeSpace.x6),
        label = "titleCount",
    ) { value ->
        BasicText(
            text = Copy.titles(value),
            style = ThemeType.metadata.copy(textAlign = TextAlign.Center),
            modifier = Modifier.fillMaxWidth(),
            color = ColorProducer { ThemeColor.textTertiary },
        )
    }
}

// =================================================================================================
// MARK: - The A–Z index rail
// =================================================================================================

/**
 * The rail.
 *
 * Everything its rebuild fixed, recorded so a port does not regress it: the type is `sectionLabel`
 * (which scales) rather than a hard-coded 11 pt, and the rail is suppressed entirely at accessibility
 * sizes; the ink is `textTertiary` (5.14:1) lifting to `textSecondary` / `accent` under the finger,
 * not `textDisabled` (3.6:1); it spans the list top to bottom with every band ≥ 22 dp rather than
 * floating as a 225-dp column attached to nothing; the letters sit in a reserved 28-dp lane inside a
 * 44-dp gesture host rather than on the third poster column; and `.selection` has its own **40 ms**
 * floor, because a 300 ms blanket floor made an A→W drag produce two taps out of twenty-odd.
 *
 * *"The rail says which letter it is on instead of all of them."*
 */
@Composable
private fun IndexRail(
    keys: List<String>,
    topInset: Dp,
    onSelect: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    if (keys.isEmpty()) return
    val density = LocalDensity.current
    var touching by remember { mutableStateOf(false) }
    var activeIndex by remember { mutableStateOf<Int?>(null) }

    val capsuleAlpha = animateFloatAsState(
        targetValue = if (touching) 1f else 0f,
        animationSpec = motion(MotionToken.UI_MICRO),
        label = "railCapsule",
    )

    BoxWithConstraints(
        modifier = modifier
            .width(AllTitlesMetrics.railHit)
            .fillMaxHeight()
            // Between the search drawer and the tab bar.
            .padding(top = topInset + ThemeSpace.x3, bottom = tabBarContentBottom()),
    ) {
        val step = maxOf(AllTitlesMetrics.railMinStep, maxHeight / keys.size)
        val stepPx = with(density) { step.toPx() }

        fun select(index: Int) {
            if (index !in keys.indices || index == activeIndex) return
            activeIndex = index
            FeedbackCoordinator.fire(FeedbackToken.SELECTION)
            onSelect(keys[index])
        }

        // The capsule under the finger. Its alpha is read inside the layer lambda, so a drag
        // invalidates a layer and not the screen.
        Box(
            Modifier
                .align(Alignment.TopEnd)
                .width(AllTitlesMetrics.railLane)
                .fillMaxHeight()
                .padding(vertical = ThemeSpace.x2)
                .graphicsLayer { alpha = capsuleAlpha.value }
                .background(ThemeColor.surfaceRaised, CircleShape),
        )

        Column(
            modifier = Modifier
                .fillMaxHeight()
                .width(AllTitlesMetrics.railHit)
                .pointerInput(keys, stepPx) {
                    awaitEachGesture {
                        val down = awaitFirstDown(requireUnconsumed = false)
                        down.consume()
                        touching = true
                        select((down.position.y / stepPx).toInt().coerceIn(0, keys.lastIndex))
                        drag(down.id) { change ->
                            change.consume()
                            select((change.position.y / stepPx).toInt().coerceIn(0, keys.lastIndex))
                        }
                        touching = false
                        activeIndex = null
                    }
                }
                // ONE adjustable element, so a screen reader gets the rail's job rather than fifteen
                // unlabelled letters. TalkBack's up/down swipes drive `setProgress`.
                .semantics(mergeDescendants = true) {
                    contentDescription = CopyLibrary.sectionIndex
                    stateDescription = keys[activeIndex ?: 0]
                    progressBarRangeInfo = ProgressBarRangeInfo(
                        current = (activeIndex ?: 0).toFloat(),
                        range = 0f..keys.lastIndex.coerceAtLeast(0).toFloat(),
                        steps = (keys.size - 2).coerceAtLeast(0),
                    )
                    setProgress { target ->
                        select(target.roundToInt().coerceIn(0, keys.lastIndex))
                        true
                    }
                },
            horizontalAlignment = Alignment.End,
        ) {
            keys.forEachIndexed { index, key ->
                Box(
                    modifier = Modifier
                        .width(AllTitlesMetrics.railLane)
                        .height(step),
                    contentAlignment = Alignment.Center,
                ) {
                    BasicText(
                        text = key.uppercase(Locale.getDefault()),
                        style = ThemeType.sectionLabel,
                        maxLines = 1,
                        color = ColorProducer {
                            when {
                                !touching -> ThemeColor.textTertiary
                                index == activeIndex -> ThemeColor.accent
                                else -> ThemeColor.textSecondary
                            }
                        },
                    )
                }
            }
        }
    }
}

// =================================================================================================
// MARK: - Bar controls and the search drawer
// =================================================================================================

/**
 * Back.
 *
 * The icon inventory has no back arrow — the app's own chevron, rotated, IS the back mark, and it
 * stays `interactive` ink like every other bare glyph.
 */
@Composable
private fun BackButton(onBack: () -> Unit) {
    val ink = LocalControlInk.current
    Box(
        Modifier
            .clickable(
                interactionSource = null,
                indication = PressStyle.textAction,
                role = Role.Button,
                onClick = onBack,
            )
            .semantics { contentDescription = CopyLibrary.title }
            .size(minimumTapTarget),
        contentAlignment = Alignment.Center,
    ) {
        Image(
            imageVector = rememberSymbol(PreviouslyIcons.ChevronRight),
            contentDescription = null,
            modifier = Modifier
                .size(materialGlyphBox(AllTitlesMetrics.barGlyph))
                .graphicsLayer { rotationZ = 180f },
            colorFilter = ColorFilter.tint(ink),
        )
    }
}

/**
 * The Sort & filter control.
 *
 * *"Accent is selection here, and only here: an idle filter control is not the screen's primary
 * action and has no business being the loudest thing on it."*
 */
@Composable
private fun ArrangeButton(active: Boolean, onClick: () -> Unit) {
    Box(
        Modifier
            .clickable(
                interactionSource = null,
                indication = PressStyle.textAction,
                role = Role.Button,
                onClick = onClick,
            )
            .semantics { contentDescription = Copy.Heading.sortAndFilter }
            .size(minimumTapTarget),
        contentAlignment = Alignment.Center,
    ) {
        Image(
            imageVector = rememberSymbol(PreviouslyIcons.FilterList),
            contentDescription = null,
            modifier = Modifier.size(materialGlyphBox(AllTitlesMetrics.barGlyph)),
            colorFilter = ColorFilter.tint(
                if (active) ThemeColor.accent else ThemeColor.textPrimary,
            ),
        )
    }
}

/**
 * The search drawer — the 52-dp band under the title.
 *
 * Android has no platform search drawer, so it is built: a field in its own band, whose focus drives
 * the hardened veil's hold and the collapse of the inline title above it.
 *
 * *"Titles are names, not sentences, and the keyboard follows the finger down"* — no
 * autocapitalisation, no autocorrect, and the keyboard hides as soon as the list moves. Focus is
 * **kept** while it hides, so the drawer does not jump back under a title mid-scroll.
 */
@Composable
private fun SearchDrawer(
    query: String,
    onQueryChange: (String) -> Unit,
    focused: Boolean,
    onFocusChanged: (Boolean) -> Unit,
    scrolling: Boolean,
) {
    val keyboard = LocalSoftwareKeyboardController.current
    val ink = LocalControlInk.current

    LaunchedEffect(scrolling) { if (scrolling) keyboard?.hide() }

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(ThemeMetrics.searchDrawerHeight)
            .padding(horizontal = ThemeMetrics.gutter),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(ThemeSpace.x2),
    ) {
        Row(
            modifier = Modifier
                .weight(1f)
                .height(AllTitlesMetrics.searchFieldHeight)
                .background(
                    ThemeColor.surfaceRaised,
                    ContinuousCornerShape(ThemeRadius.compactControl),
                )
                .padding(horizontal = ThemeSpace.x2),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(ThemeSpace.x2),
        ) {
            Image(
                imageVector = rememberSymbol(PreviouslyIcons.Search),
                contentDescription = null,
                modifier = Modifier.size(materialGlyphBox(AllTitlesMetrics.fieldGlyph)),
                colorFilter = ColorFilter.tint(ThemeColor.textTertiary),
            )
            Box(Modifier.weight(1f), contentAlignment = Alignment.CenterStart) {
                if (query.isEmpty()) {
                    BasicText(
                        text = CopyLibrary.searchPrompt,
                        style = ThemeType.fieldInput,
                        maxLines = 1,
                        color = ColorProducer { ThemeColor.textTertiary },
                    )
                }
                BasicTextField(
                    value = query,
                    onValueChange = onQueryChange,
                    modifier = Modifier
                        .fillMaxWidth()
                        .onFocusChanged { onFocusChanged(it.isFocused) },
                    textStyle = ThemeType.fieldInput.copy(color = ThemeColor.textPrimary),
                    singleLine = true,
                    // The caret is INK, never amber: a cursor is not a fact about the user's future.
                    cursorBrush = SolidColor(ink),
                    keyboardOptions = KeyboardOptions(
                        capitalization = KeyboardCapitalization.None,
                        autoCorrectEnabled = false,
                        imeAction = ImeAction.Search,
                    ),
                )
            }
            if (query.isNotEmpty()) {
                Box(
                    Modifier
                        .clickable(
                            interactionSource = null,
                            indication = PressStyle.textAction,
                            role = Role.Button,
                            onClick = { onQueryChange("") },
                        )
                        .semantics { contentDescription = Copy.Action.clear }
                        .size(materialGlyphBox(ThemeSpace.x5)),
                    contentAlignment = Alignment.Center,
                ) {
                    Image(
                        imageVector = rememberSymbol(PreviouslyIcons.Close),
                        contentDescription = null,
                        modifier = Modifier.size(materialGlyphBox(AllTitlesMetrics.clearGlyph)),
                        colorFilter = ColorFilter.tint(ThemeColor.textTertiary),
                    )
                }
            }
        }
        if (focused) {
            InlineLinkButton(label = Copy.Action.cancel, onClick = { keyboard?.hide() })
        }
    }
}

// =================================================================================================
// MARK: - The Sort & filter sheet
// =================================================================================================

/**
 * The sheet's height, **computed before presentation and never measured**.
 *
 * *"A detent that measures itself cannot be right on the first frame: the sheet grew 68 pt under the
 * user's eye and only looked correct the second time it opened."*
 *
 * `chrome` = 52 (header) + 12 (top) + 20 (group top) + 30 (group gap) + 24 (bottom) + 34 (grabber)
 * − 42 = **130**.
 */
private object ArrangeGeometry {
    const val rowCount = 5
    val chrome = 130.dp
    const val maxFraction = 0.92f

    /**
     * iOS's `typeFactor` ladder, re-anchored on Android's own `fontScale`.
     *
     * The iOS table is keyed on `DynamicTypeSize` cases; Android has one continuous scale, so these
     * bands reproduce the same growth curve against the sliders a user can actually set. Re-tuned so
     * the sheet READS the same, not so it measures the same.
     */
    fun typeFactor(fontScale: Float): Float = when {
        fontScale <= 0.86f -> 0.92f
        fontScale <= 0.92f -> 0.95f
        fontScale <= 0.97f -> 0.98f
        fontScale <= 1.02f -> 1.00f
        fontScale <= 1.12f -> 1.08f
        fontScale <= 1.22f -> 1.16f
        fontScale <= 1.32f -> 1.26f
        fontScale <= 1.52f -> 1.52f
        fontScale <= 1.72f -> 1.74f
        fontScale <= 1.86f -> 2.05f
        fontScale <= 1.96f -> 2.35f
        else -> 2.60f
    }
}

/** One value a [ValueRow]'s menu can be set to. */
@Immutable
private class ValueOption(val label: String, val onSelect: () -> Unit)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ArrangeSheet(
    sort: LibrarySort,
    onSort: (LibrarySort) -> Unit,
    ascending: Boolean,
    onAscending: (Boolean) -> Unit,
    status: StatusFilter,
    onStatus: (StatusFilter) -> Unit,
    unwatchedOnly: Boolean,
    onUnwatchedOnly: (Boolean) -> Unit,
    display: DisplayMode,
    onDisplay: (DisplayMode) -> Unit,
    onReset: () -> Unit,
    onDismiss: () -> Unit,
) {
    val isAX = isAccessibilityTextSize()
    val fontScale = LocalDensity.current.fontScale
    val windowHeight = ThemeMetrics.windowHeight()
    val detent = minOf(
        ThemeMetrics.rowCompact * ArrangeGeometry.rowCount *
            ArrangeGeometry.typeFactor(fontScale) + ArrangeGeometry.chrome,
        windowHeight * ArrangeGeometry.maxFraction,
    )

    // `hasFilters` INSIDE the sheet omits `returning`, which the sheet does not expose.
    val hasFilters = sort != LibrarySort.TITLE ||
        ascending ||
        status != StatusFilter.AnyStatus ||
        unwatchedOnly

    PreviouslyMaterialBridge {
        ModalBottomSheet(
            onDismissRequest = onDismiss,
            sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
            // Set at the call site, never painted on the sheet's own scroll view: "painting it on
            // this scroll view left the plate 34 pt short and the undimmed list showed through the
            // gap — it read as a rendering failure."
            containerColor = ThemeColor.canvasRaised,
            contentColor = ThemeColor.textPrimary,
            dragHandle = { BottomSheetDefaults.DragHandle() },
        ) {
            Column(
                Modifier
                    .height(detent)
                    .verticalScroll(rememberScrollState()),
            ) {
                ArrangeHeader(hasFilters = hasFilters, onReset = onReset, onDone = onDismiss)

                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(
                            start = ThemeMetrics.gutter,
                            end = ThemeMetrics.gutter,
                            top = ThemeSpace.x5,
                            bottom = ThemeSpace.x6,
                        ),
                    verticalArrangement = Arrangement.spacedBy(ThemeMetrics.sectionGap),
                ) {
                    // Group 1 has NO header: the sheet's own title names it, and repeating "SORT &
                    // FILTER" 30 dp under "Sort & filter" is an echo. (Settings grammar: the first
                    // group is implicit, later groups are named.)
                    GroupedList {
                        ValueRow(
                            title = CopyLibrary.sortBy,
                            value = sort.label,
                            options = LibrarySort.entries.map { option ->
                                ValueOption(option.label) { onSort(option) }
                            },
                        )
                        GroupedRow(
                            title = CopyLibrary.reverseOrder,
                            // The subtitle appears ONLY while the switch is on — a direction that is
                            // not in force is not a fact about this list.
                            subtitle = if (ascending) sort.reversedLabel else null,
                            trailing = GroupedTrailing.Toggle(ascending, onAscending),
                        )
                        ValueRow(
                            title = CopyLibrary.status,
                            value = status.label,
                            options = statusFilterOptions().map { option ->
                                ValueOption(option.label) { onStatus(option) }
                            },
                        )
                        GroupedRow(
                            title = CopyLibrary.hasUnwatched,
                            trailing = GroupedTrailing.Toggle(unwatchedOnly, onUnwatchedOnly),
                            separator = false,
                        )
                    }

                    GroupedList(header = CopyLibrary.view) {
                        ViewAsRow(display = display, onDisplay = onDisplay, isAX = isAX)
                    }
                }
            }
        }
    }
}

/**
 * The sheet's header, hand-built rather than a navigation toolbar: *"on this OS a toolbar button
 * renders as a filled glass capsule, which made `Done` the single heaviest object in a sheet whose
 * whole job is to be quiet."*
 *
 * The title is an **overlay**, not a stack member: "with `Reset` present on one side only, a
 * three-item row puts the title wherever the two buttons' widths happen to leave it."
 */
@Composable
private fun ArrangeHeader(hasFilters: Boolean, onReset: () -> Unit, onDone: () -> Unit) {
    Box(
        Modifier
            .fillMaxWidth()
            .padding(top = ThemeSpace.x3, start = ThemeMetrics.gutter, end = ThemeMetrics.gutter)
            .height(AllTitlesMetrics.sheetHeaderHeight),
        contentAlignment = Alignment.Center,
    ) {
        AutoSizeText(
            text = Copy.Heading.sortAndFilter,
            style = ThemeType.showTitleM.copy(color = ThemeColor.textPrimary),
            minScale = SHEET_TITLE_MIN_SCALE,
            maxLines = 1,
        )
        Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            if (hasFilters) InlineLinkButton(label = Copy.Action.reset, onClick = onReset)
            Spacer(Modifier.weight(1f))
            InlineLinkButton(label = Copy.Action.done, onClick = onDone)
        }
    }
}

private const val SHEET_TITLE_MIN_SCALE = 0.85f

/** `Any`, then the five statuses in menu order. */
private fun statusFilterOptions(): List<StatusFilter> = listOf(
    StatusFilter.AnyStatus,
    StatusFilter.Of(WatchStatus.WATCHING),
    StatusFilter.Of(WatchStatus.PLANNED),
    StatusFilter.Of(WatchStatus.COMPLETED),
    StatusFilter.Of(WatchStatus.PAUSED),
    StatusFilter.Of(WatchStatus.DROPPED),
)

/** A `GroupedRow`'s geometry with a menu where the button is. */
@Composable
private fun ValueRow(
    title: String,
    value: String,
    options: List<ValueOption>,
    separator: Boolean = true,
) {
    var expanded by remember { mutableStateOf(false) }
    Box {
        Box(
            Modifier
                .fillMaxWidth()
                .clickable(
                    interactionSource = null,
                    indication = PressStyle.groupedRow,
                    role = Role.Button,
                    onClick = { expanded = true },
                )
                .semantics {
                    contentDescription = title
                    stateDescription = value
                }
                .defaultMinSize(minHeight = ThemeMetrics.rowCompact),
            contentAlignment = Alignment.CenterStart,
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(
                        start = AllTitlesMetrics.groupedLeadingInset,
                        end = ThemeMetrics.gutter,
                    ),
                horizontalArrangement = Arrangement.spacedBy(ThemeSpace.x3),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                BasicText(
                    text = title,
                    style = ThemeType.body,
                    color = ColorProducer { ThemeColor.textPrimary },
                )
                Spacer(Modifier.weight(1f))
                BasicText(
                    text = value,
                    style = ThemeType.body,
                    maxLines = 1,
                    color = ColorProducer { ThemeColor.textTertiary },
                )
                Image(
                    // NOT a forward chevron: "this row opens a menu in place, it does not push a
                    // screen, and there is one symbol for each."
                    imageVector = rememberSymbol(PreviouslyIcons.UnfoldMore),
                    contentDescription = null,
                    modifier = Modifier.size(materialGlyphBox(AllTitlesMetrics.popupGlyph)),
                    colorFilter = ColorFilter.tint(ThemeColor.textDisabled),
                )
            }
            if (separator) {
                Spacer(
                    Modifier
                        .align(Alignment.BottomStart)
                        .fillMaxWidth()
                        .padding(start = AllTitlesMetrics.groupedLeadingInset)
                        .height(1.dp)
                        .background(ThemeColor.separatorQuiet),
                )
            }
        }

        PreviouslyMaterialBridge {
            DropdownMenu(
                expanded = expanded,
                onDismissRequest = { expanded = false },
                shape = ContinuousCornerShape(ThemeRadius.compactControl),
                containerColor = ThemeColor.surfaceFloating,
                tonalElevation = 0.dp,
                shadowElevation = ShadowToken.Floating.elevation,
                border = BorderStroke(ThemeMetrics.hairline, ThemeColor.strokeStrong),
            ) {
                for (option in options) {
                    MenuValue(label = option.label, selected = option.label == value) {
                        expanded = false
                        option.onSelect()
                    }
                }
            }
        }
    }
}

@Composable
private fun MenuValue(label: String, selected: Boolean, onClick: () -> Unit) {
    val ink = LocalControlInk.current
    val isSelected = selected
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(
                interactionSource = null,
                indication = PressStyle.groupedRow,
                role = Role.Button,
                onClick = onClick,
            )
            .semantics { this.selected = isSelected }
            .defaultMinSize(minHeight = minimumTapTarget)
            .padding(horizontal = ThemeMetrics.gutter, vertical = ThemeSpace.x2),
        horizontalArrangement = Arrangement.spacedBy(ThemeSpace.x3),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        BasicText(
            text = label,
            style = ThemeType.body,
            modifier = Modifier.weight(1f),
            maxLines = 1,
            color = ColorProducer { ink },
        )
        if (isSelected) {
            Image(
                imageVector = rememberSymbol(PreviouslyIcons.Check),
                contentDescription = null,
                modifier = Modifier.size(materialGlyphBox(AllTitlesMetrics.checkGlyph)),
                // A chosen value is STATE, and STATE is legal amber.
                colorFilter = ColorFilter.tint(ThemeColor.accent),
            )
        }
    }
}

/**
 * `View as`, a two-segment control.
 *
 * At an accessibility text size the row becomes label-over-control *"rather than squeezing to
 * 60 pt."*
 */
@Composable
private fun ViewAsRow(display: DisplayMode, onDisplay: (DisplayMode) -> Unit, isAX: Boolean) {
    if (isAX) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(
                    horizontal = AllTitlesMetrics.groupedLeadingInset,
                    vertical = ThemeSpace.x3,
                ),
            verticalArrangement = Arrangement.spacedBy(ThemeSpace.x2),
        ) {
            BasicText(
                text = CopyLibrary.viewAs,
                style = ThemeType.body,
                color = ColorProducer { ThemeColor.textPrimary },
            )
            Segmented(display = display, onDisplay = onDisplay, modifier = Modifier.fillMaxWidth())
        }
    } else {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .defaultMinSize(minHeight = ThemeMetrics.rowCompact)
                .padding(
                    start = AllTitlesMetrics.groupedLeadingInset,
                    end = ThemeMetrics.gutter,
                ),
            horizontalArrangement = Arrangement.spacedBy(ThemeSpace.x3),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            BasicText(
                text = CopyLibrary.viewAs,
                style = ThemeType.body,
                color = ColorProducer { ThemeColor.textPrimary },
            )
            Spacer(Modifier.weight(1f))
            Segmented(
                display = display,
                onDisplay = onDisplay,
                modifier = Modifier.width(AllTitlesMetrics.segmentedWidth),
            )
        }
    }
}

/**
 * Two halves of one capsule. The selected half is amber with `onAccent` ink — a selected value is
 * STATE, and there the amber is a GROUND, so no amber *word* is drawn.
 */
@Composable
private fun Segmented(
    display: DisplayMode,
    onDisplay: (DisplayMode) -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier
            .height(AllTitlesMetrics.segmentedHeight)
            .background(ThemeColor.surfaceRaised, CircleShape),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        for (mode in DisplayMode.entries) {
            val isSelected = mode == display
            Box(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxHeight()
                    .clickable(
                        interactionSource = null,
                        indication = PressStyle.control,
                        role = Role.Button,
                        onClick = { onDisplay(mode) },
                    )
                    .semantics { selected = isSelected }
                    .background(
                        if (isSelected) ThemeColor.accent else Color.Transparent,
                        CircleShape,
                    ),
                contentAlignment = Alignment.Center,
            ) {
                BasicText(
                    text = mode.label,
                    style = ThemeType.metadataEmphasis,
                    maxLines = 1,
                    color = ColorProducer {
                        if (isSelected) ThemeColor.onAccent else ThemeColor.textSecondary
                    },
                )
            }
        }
    }
}

// =================================================================================================
// MARK: - The skeleton
// =================================================================================================

/** Eight rows of the shape that is coming, so the hand-off changes content and not structure. */
@Composable
private fun AllTitlesSkeleton(topInset: Dp, modifier: Modifier = Modifier) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(
                start = ThemeMetrics.gutter,
                end = ThemeMetrics.gutter,
                top = topInset + ThemeSpace.x1,
            ),
    ) {
        repeat(AllTitlesMetrics.skeletonRows) {
            SkeletonRow(
                poster = PosterSize.Row.size,
                lines = listOf(
                    AllTitlesMetrics.skeletonTitleWidth,
                    AllTitlesMetrics.skeletonMetaWidth,
                ),
                posterRadius = PosterSize.Row.radius,
                spacing = ThemeMetrics.artGap,
            )
        }
    }
}
