package com.anitrack.app.ui.detail

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.ScrollState
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.toggleable
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
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.RectangleShape
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import com.anitrack.app.AppModel
import com.anitrack.app.data.RewatchStore
import com.anitrack.app.data.SyncCenter
import com.anitrack.app.data.UndoState
import com.anitrack.app.data.WatchSession
import com.anitrack.app.data.api.ApiClient
import com.anitrack.app.design.ArtGround
import com.anitrack.app.design.ContinuousCornerShape
import com.anitrack.app.design.FeedbackCoordinator
import com.anitrack.app.design.FeedbackToken
import com.anitrack.app.design.LocalReduceMotion
import com.anitrack.app.design.MaterialSymbol
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
import com.anitrack.app.ui.art.PosterSlot
import com.anitrack.app.ui.chrome.PushedScreenChrome
import com.anitrack.app.ui.chrome.TopScrollEdgeChrome
import com.anitrack.app.ui.chrome.chromeGlass
import com.anitrack.app.ui.chrome.chromeHazeSource
import com.anitrack.app.ui.control.InlineLink
import com.anitrack.app.ui.control.InlineLinkButton
import com.anitrack.app.ui.control.MarkSplitButton
import com.anitrack.app.ui.control.PressStyle
import com.anitrack.app.ui.control.PrimaryButton
import com.anitrack.app.ui.control.ProgressBar
import com.anitrack.app.ui.control.TertiaryButton
import com.anitrack.app.ui.control.materialGlyphBox
import com.anitrack.app.ui.control.minimumTapTarget
import com.anitrack.app.ui.hero.ArtHeader
import com.anitrack.app.ui.hero.Billboard
import com.anitrack.app.ui.hero.HeroCopyScrim
import com.anitrack.app.ui.hero.HeroTopVeil
import com.anitrack.app.ui.hero.billboardHeight
import com.anitrack.app.ui.hero.reportHeight
import com.anitrack.app.ui.image.rememberArtTint
import com.anitrack.app.ui.isAccessibilityTextSize
import com.anitrack.app.ui.list.GroupedList
import com.anitrack.app.ui.list.GroupedRow
import com.anitrack.app.ui.list.GroupedTrailing
import com.anitrack.app.ui.negativePadding
import com.anitrack.app.ui.row.MediaRow
import com.anitrack.app.ui.scroll.ScrollOffset
import com.anitrack.app.ui.scroll.past
import com.anitrack.app.ui.scroll.rememberScrollOffset
import com.anitrack.app.ui.scroll.track
import com.anitrack.app.ui.section.HeroBadge
import com.anitrack.app.ui.section.SectionLabel
import com.anitrack.app.ui.state.EmptyState
import com.anitrack.app.ui.state.InlineNotice
import com.anitrack.app.ui.state.SkeletonCard
import com.anitrack.app.ui.state.SkeletonGate
import com.anitrack.app.ui.state.SkeletonLine
import com.anitrack.app.ui.state.SkeletonRow
import com.anitrack.model.AppRegion
import com.anitrack.model.Formatting
import com.anitrack.model.Franchise
import com.anitrack.model.FranchisePart
import com.anitrack.model.FranchiseSummary
import com.anitrack.model.FranchiseVideo
import com.anitrack.model.PartKind
import com.anitrack.model.RelatedTitle
import com.anitrack.model.TemporalCopy
import com.anitrack.model.TimeAnchor
import com.anitrack.model.WatchAvailability
import com.anitrack.model.WatchStatus
import com.anitrack.model.allVideos
import com.anitrack.model.announcedDateLabel
import com.anitrack.model.canonicalLabel
import com.anitrack.model.contentRatingLabel
import com.anitrack.model.copy.Copy
import com.anitrack.model.copy.EmptyStateCopy
import com.anitrack.model.currentPart
import com.anitrack.model.displayRelease
import com.anitrack.model.displayTitle
import com.anitrack.model.effectiveStatus
import com.anitrack.model.episodicPartsInOrder
import com.anitrack.model.seasonPartsInOrder
import com.anitrack.model.grafting
import com.anitrack.model.hasArrived
import com.anitrack.model.isComplete
import com.anitrack.model.isFutureInstallment
import com.anitrack.model.isRumored
import com.anitrack.model.isSeriesComplete
import com.anitrack.model.isUpcoming
import com.anitrack.model.kindWord
import com.anitrack.model.landscapeArt
import com.anitrack.model.lastAired
import com.anitrack.model.ShelfWindows
import com.anitrack.model.airedByNow
import com.anitrack.model.availableEpisodes
import com.anitrack.model.billboardResolution
import com.anitrack.model.looksUnenriched
import com.anitrack.model.markTarget
import com.anitrack.model.nextAiring
import com.anitrack.model.nextPremiere
import com.anitrack.model.billboardName
import com.anitrack.model.textlessPortrait
import com.anitrack.app.ui.hero.HeroTitle
import com.anitrack.app.ui.hero.HeroLockup
import com.anitrack.app.ui.hero.HeroLockupDefaults
import com.anitrack.model.portraitArt
import com.anitrack.model.themesBeyondGenres
import com.anitrack.model.timeAnchor
import com.anitrack.model.tracksAirings
import com.anitrack.model.watchContext
import java.util.Locale
import java.util.UUID
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import com.anitrack.app.data.ReceiptHost
import com.anitrack.app.ui.state.ReceiptLine
import com.anitrack.model.shelfShortened
import androidx.compose.foundation.border
import androidx.compose.foundation.shape.RoundedCornerShape

/*
 * THE SHOW PAGE — the port of `ios/Sources/Features/FranchiseDetail/FranchiseDetailView.swift`.
 *
 * It opens on a full-bleed billboard (the cover shown WHOLE at 68 % of the screen with the title and
 * one identity line laid over its foot), hands that title into the bar the moment the hero's COPY
 * reaches the toolbar's bottom edge, and then runs a single ungrouped column on the canvas: a state
 * block carrying the screen's one action, the synopsis, a season picker heading a six-row window of
 * episodes, a "Movies & extras" art shelf, and four catalogue shelves in Apple TV's order.
 *
 * ## The four rules that shape it
 *
 * * **The scroll offset is never screen state.** [ScrollOffset] quantises and de-duplicates, and the
 *   only things that READ it are the veil's `graphicsLayer` lambda and a `derivedStateOf`. The raw
 *   offset held as state re-ran Today's whole body at 60–120 Hz for the length of every swipe (user,
 *   2 Sep, twice), and this screen is bigger than Today.
 * * **The docked-title threshold is `copyTop − band`, NOT a flat 130.** The flip happens exactly when
 *   the TOP OF THE HERO'S TITLE reaches the BOTTOM EDGE OF THE TOOLBAR — Apple TV's handover. At a
 *   flat 130 the flip came ~80 dp later and the title slid under the bar half-lit for the whole of
 *   that scroll (captured 3 Sep). Because the copy's height is MEASURED, the threshold moves with the
 *   text size for free: bigger type means a taller copy block, a smaller `copyTop`, and an earlier
 *   hand-over — which is correct.
 * * **Amber is never an action colour.** The toolbar's Add is a bare `plus` glyph in `interactive`,
 *   because it sits directly above the episode list's amber "Next up".
 * * **Every section emits nothing when it has no content**, so the 30-dp section gap never doubles.
 *
 * The content column is **full-bleed** and each block pads itself by the gutter, because the shelves
 * run edge to edge — see the note in `DetailShelves.kt`.
 */

// =================================================================================================
// MARK: - Ports
// =================================================================================================

/**
 * The three calls the show page makes that `AniTrackApi` — the model's own eight-call port — does not
 * carry: the country-qualified franchise read, the separate providers read, and the exact-title
 * search that materialises a related title.
 *
 * Declared here rather than widened onto `AniTrackApi` because they belong to THIS screen: the model
 * layer never asks for a market, and the search here is a materialisation rather than a query the
 * user typed.
 */
interface DetailApi {

    /**
     * `GET /franchises/{id}?country=XX`. The market selects `audience.contentRating`; the server
     * never substitutes another country's rating, so a miss is absent rather than "US".
     */
    suspend fun franchise(id: String, country: String): Franchise

    /**
     * `GET /franchises/{id}/watch-providers?country=XX`. Read apart from the franchise so a cold
     * provider lookup never delays the show page — **and a failure here is a missing section, never
     * an error state: the page is about the show, not about where to stream it.**
     */
    suspend fun watchProviders(id: String, country: String): WatchAvailability

    /** `GET /search?q=…&exact=1`, for a related title the catalogue has not materialised yet. */
    suspend fun searchExact(query: String): List<FranchiseSummary>
}

/** [DetailApi] over the real transport. Wire this once, beside `ApiClientPort`. */
class ApiClientDetailApi(private val client: ApiClient) : DetailApi {

    override suspend fun franchise(id: String, country: String): Franchise =
        client.franchise(id = id, country = country)

    override suspend fun watchProviders(id: String, country: String): WatchAvailability =
        client.watchProviders(id = id, country = country)

    override suspend fun searchExact(query: String): List<FranchiseSummary> =
        client.search(query = query, exact = true).franchises
}

/**
 * The three routes the show page pushes on the OWNING tab's back stack. **Detail is a plain push** —
 * never a sheet, and never a zoom transition: the `.zoom` push was tried (2 Sep) and retired (3 Sep)
 * because it scales the whole page into the tapped poster, so the show page opened as a miniature of
 * itself inflating.
 */
@Immutable
sealed interface DetailPush {

    /** The full season list. */
    data class Episodes(
        val franchiseId: String,
        val mediaId: Int,
        val focusEpisode: Int? = null,
    ) : DetailPush

    /** Watch history. */
    data class History(val franchiseId: String) : DetailPush

    /** Another show page, one deeper. */
    data class Detail(val franchiseId: String) : DetailPush
}

/** A Schedule deep link straight to one episode. */
@Immutable
data class EpisodeFocus(val mediaId: Int, val episode: Int)

/**
 * The debug capture driver's arguments — the Android reading of the iOS launch arguments.
 *
 * They exist so the show page can be PHOTOGRAPHED when the device cannot be touched. Read them from
 * the launch `Intent`'s extras at the router and hand them down; nothing here reads a global, and a
 * release router passes `null`.
 */
@Immutable
data class DetailDebugArgs(
    /** `trailers` | `people` | `related` | `watch`. */
    val anchor: String? = null,
    /** Open the first trailer's sheet. */
    val trailer: Boolean = false,
    /** Open the Nth related title. */
    val openRelated: Int? = null,
)

/** How long after appearance the capture driver acts, so the push transition has settled. */
private const val DEBUG_DRIVE_DELAY_MILLIS = 2_500L

/** The back glyph's ink size, matched across Detail, the season screen and Watch history. */
internal val DetailBackGlyph = 17.dp

// =================================================================================================
// MARK: - Screen state
// =================================================================================================

/**
 * Everything the show page holds that is not the library.
 *
 * Per-field snapshot state rather than one immutable value, for the same reason `AppModel` is: a mark
 * writes four of these fields inside 650 ms, and a single state object would invalidate the whole
 * screen on each of them.
 */
@Stable
class DetailScreenState {

    /** The detail read. `null` until it lands; never cleared by a failure. */
    var fetched: Franchise? by mutableStateOf(null)

    /** The providers read. Runs once per screen; a throw is swallowed. */
    var providers: WatchAvailability? by mutableStateOf(null)

    var loading: Boolean by mutableStateOf(false)

    /** The last read failed — **never** a cancellation. */
    var loadError: Boolean by mutableStateOf(false)

    /** The measured height of the hero's copy block. Drives the scrim AND the docked-title flip. */
    var heroCopyHeight: Dp by mutableStateOf(0.dp)

    /** The pre-mark snapshot, frozen for the result window so the block keeps the episode it wrote. */
    var pinned: Franchise? by mutableStateOf(null)

    var committedEpisode: Int? by mutableStateOf(null)

    /** Held back until the handoff settles, so the toast and the card do not talk over each other. */
    var pendingUndo: UndoState? by mutableStateOf(null)

    var sweepToken: String? by mutableStateOf(null)

    var milestoneToken: String? by mutableStateOf(null)

    var selectedSeasonId: Int? by mutableStateOf(null)

    var synopsisExpanded: Boolean by mutableStateOf(false)

    /** Episodes whose title the reader has chosen to see, on the state block. */
    var revealed: Set<Int> by mutableStateOf(emptySet())

    var video: FranchiseVideo? by mutableStateOf(null)

    var prompt: WritePrompt? by mutableStateOf(null)

    var startRewatchOpen: Boolean by mutableStateOf(false)

    /** The related title whose exact-title search is in flight. A second tap waits for the first. */
    var resolvingRelated: String? by mutableStateOf(null)

    /** The Schedule deep link is consumed exactly ONCE. */
    var focusConsumed: Boolean = false

    /** The 6-second enrichment re-read fires at most once per screen. */
    var enrichmentRetryStarted: Boolean = false

    /**
     * The scroll content's root y, and each catalogue shelf's y inside it.
     *
     * Written from layout callbacks and read from one — never from a composition — so the plain
     * `var` is deliberate; only the capture driver consumes them.
     */
    var contentTop: Float = 0f
    val anchors: MutableMap<String, Int> = HashMap()
}

@Composable
fun rememberDetailScreenState(franchiseId: String): DetailScreenState =
    remember(franchiseId) { DetailScreenState() }

// =================================================================================================
// MARK: - The screen
// =================================================================================================

/**
 * @param focus a Schedule deep link straight to one episode. Consumed exactly once — the appearance
 *   effect fires again when the episode list pops back to here, and the push re-fired with it, so
 *   **every Schedule-routed Detail was a screen you could not return to.**
 */
@Composable
fun DetailScreen(
    franchiseId: String,
    appModel: AppModel,
    api: DetailApi,
    push: (DetailPush) -> Unit,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
    focus: EpisodeFocus? = null,
    debug: DetailDebugArgs? = null,
) {
    val state = rememberDetailScreenState(franchiseId)
    val scope = rememberCoroutineScope()
    val country = remember { AppRegion.current }

    // ---- The two reads --------------------------------------------------------------------------

    // The appearance effect passes nothing, so popping back from the season list no longer refetches
    // the whole franchise under the user.
    suspend fun load(force: Boolean = false) {
        if (!force && state.fetched?.id == franchiseId) return
        state.loading = true
        try {
            state.fetched = api.franchise(franchiseId, country)
            state.loadError = false
        } catch (e: CancellationException) {
            // A pop mid-fetch cancels this. That is NOT a failed load, and it must not leave the
            // "couldn't refresh" footnote standing when the user returns.
            throw e
        } catch (e: Throwable) {
            state.loadError = true
        } finally {
            state.loading = false
        }
    }

    LaunchedEffect(franchiseId) {
        load()
        val availability = try {
            api.watchProviders(franchiseId, country)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            // A failure here is a MISSING SECTION, never an error state.
            null
        }
        if (availability != null) state.providers = availability
    }

    // The catalogue's deep metadata arrives stale-while-revalidate: the first read of a show can
    // return before its people, related titles and trailers exist, and the server fills them in the
    // background. ONE quiet re-read a few seconds later catches that, so the shelves fade in on this
    // visit instead of the next. At most once per screen; a second read that is ALSO unenriched is
    // discarded rather than re-rendered.
    LaunchedEffect(state.fetched?.id, state.fetched?.looksUnenriched) {
        val current = state.fetched ?: return@LaunchedEffect
        if (!current.looksUnenriched || state.enrichmentRetryStarted) return@LaunchedEffect
        state.enrichmentRetryStarted = true
        delay(ENRICHMENT_RETRY_MILLIS)
        val again = try {
            api.franchise(franchiseId, country)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            null
        }
        if (again != null && !again.looksUnenriched) state.fetched = again
    }

    // ---- Which franchise the screen draws --------------------------------------------------------
    //
    // Precedence: the PINNED snapshot (frozen during a mark's result window) → the live LIBRARY row
    // grafted with the detail read → the detail read alone (a show not in the library).
    //
    // The graft matters because the library payload was read at LAUNCH, before the server's
    // stale-while-revalidate pass may have run: the live copy keeps progress and status, the detail
    // read fills the enrichment, field by field.
    val live = appModel.franchise(franchiseId)
    val fetched = state.fetched
    val franchise: Franchise? = state.pinned
        ?: (live ?: fetched)?.let { base -> if (fetched != null) base.grafting(fetched) else base }

    // ---- The two palettes ------------------------------------------------------------------------
    //
    // They differ only when the show has no cover and the hero falls back to the banner:
    // *"the hero's photograph is the banner, so the colour that continues it below the fold has to
    // come from the banner too — derived from the cover it landed a warm brown under a
    // magenta-and-cyan neon header, i.e. two light sources in one hero."*
    val art = remember(franchise?.portraitArt, franchise?.landscapeArt) { heroArt(franchise) }
    val coverTint = rememberArtTint(franchise?.portraitArt)
    val heroTint = rememberArtTint(art.url)

    // ---- The deep link, once ---------------------------------------------------------------------
    LaunchedEffect(franchiseId, focus) {
        val target = focus ?: return@LaunchedEffect
        if (state.focusConsumed) return@LaunchedEffect
        state.focusConsumed = true
        push(DetailPush.Episodes(franchiseId, target.mediaId, target.episode))
    }

    val inLibrary = appModel.isInLibrary(franchiseId)

    Box(modifier.fillMaxSize().background(ThemeColor.canvas)) {
        SkeletonGate(
            isLoading = franchise == null && state.loading && !state.loadError,
            skeleton = { DetailSkeleton(coverTint) },
            content = {
                val f = franchise
                when {
                    f != null -> DetailContent(
                        franchise = f,
                        state = state,
                        appModel = appModel,
                        api = api,
                        push = push,
                        onBack = onBack,
                        inLibrary = inLibrary,
                        tint = coverTint,
                        heroTint = heroTint,
                        debug = debug,
                        onRetry = { scope.launch { load(force = true) } },
                    )

                    state.loadError -> EmptyState(
                        // `isOnline` decides, NEVER the error: only the reachability monitor knows
                        // which of the two sentences is true.
                        copy = if (SyncCenter.isOnline) {
                            EmptyStateCopy.serverNoCache
                        } else {
                            EmptyStateCopy.offlineNoData
                        },
                        onPrimary = { scope.launch { load(force = true) } },
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(horizontal = ThemeMetrics.gutter),
                    )
                }
            },
        )
    }

    WritePromptDialog(prompt = state.prompt) { state.prompt = null }

    val playing = state.video
    if (playing != null && franchise != null) {
        // A NEW video is a NEW sheet, so the player is built once and nothing reloads.
        VideoSheet(
            video = playing,
            showTitle = franchise.displayTitle,
            onDismiss = { state.video = null },
            ambientArt = franchise.landscapeArt ?: franchise.portraitArt,
        )
    }
}

/** One quiet re-read, a few seconds later, for a row the server's background pass has not reached. */
private const val ENRICHMENT_RETRY_MILLIS = 6_000L

// =================================================================================================
// MARK: - The content column
// =================================================================================================

@Composable
private fun DetailContent(
    franchise: Franchise,
    state: DetailScreenState,
    appModel: AppModel,
    api: DetailApi,
    push: (DetailPush) -> Unit,
    onBack: () -> Unit,
    inLibrary: Boolean,
    tint: Color?,
    heroTint: Color?,
    debug: DetailDebugArgs?,
    onRetry: () -> Unit,
) {
    val scope = rememberCoroutineScope()
    val uriHandler = LocalUriHandler.current
    val scrollState = rememberScrollState()
    val scroll = rememberScrollOffset()
    scroll.track(scrollState)

    val band = ThemeMetrics.topSafeInset() + DetailMetrics.toolbarClearance
    val heroHeight = billboardHeight(
        fraction = Billboard.detail,
        copyHeight = state.heroCopyHeight,
        artBand = heroArtBand,
    )

    // THE threshold: the top of the hero's COPY reaching the toolbar's bottom edge. A MEASURED
    // number — never the flat 130 that let the title slide half-lit under the glass for ~80 dp —
    // so it moves with the type size for free.
    //
    // Through `ScrollOffset.past`, which is the app's one boolean probe: it compares against the
    // UNCLAMPED channel (`ScrollOffset` keeps the 240-dp sampling ceiling for the veils' drawn
    // reads only, and on a billboard this tall the hand-over sits 300–500 dp down, above it), and
    // its `derivedStateOf` is the native form of iOS's `if (under != scrolledUnderBar)` guard —
    // the screen recomposes on the crossing rather than on the scroll. Reading `scrollState.value`
    // here instead was a second scroll-position source on a screen that already feeds one, and it
    // published a raw pixel on every frame where the offset publishes nothing once it has settled.
    // The copy's top is the badge; the NAME sits a badge and a gap beneath it (5 Sep, the lockup),
    // and it is the name's arrival in the bar that the dock answers.
    val scrolledUnderBar by scroll.past(
        heroHeight - ThemeSpace.x4 - state.heroCopyHeight + HeroLockupDefaults.badgeToName - band,
    )

    val now = appModel.now
    val staleAfterFailure = state.loadError && state.fetched != null
    val nextUp = remember(franchise, now) { nextUpState(franchise, now) }
    val quietTint = remember(tint) { DetailTint.quiet(tint) }

    PushedScreenChrome(Modifier.fillMaxSize()) {
        Column(
            Modifier
                .fillMaxSize()
                .verticalScroll(scrollState)
                .chromeHazeSource()
                .onGloballyPositioned { state.contentTop = it.positionInRoot().y },
        ) {
            DetailHero(
                franchise = franchise,
                state = state,
                appModel = appModel,
                now = now,
                inLibrary = inLibrary,
                nextUp = nextUp,
                tint = tint,
                heroTint = heroTint,
                height = heroHeight,
                band = band,
            )

            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    // The first thing under the billboard is the identity line heading the
                    // synopsis (5 Sep). x4 (i1-F2): the in-place receipt lives in this band.
                    .padding(top = ThemeSpace.x4),
                verticalArrangement = Arrangement.spacedBy(ThemeMetrics.sectionGap),
            ) {
                if (staleAfterFailure) {
                    // A background refresh that failed is a FOOTNOTE (Mail's "Cannot connect" at the
                    // foot of the list), never a warning.
                    InlineNotice(
                        message = Copy.Notice.detailEpisodes,
                        onRetry = onRetry,
                        modifier = Modifier.padding(horizontal = detailGutter),
                    )
                }

                // The state block lives in the billboard's lockup now (5 Sep); the way into watch
                // history follows the synopsis.
                AboutSection(
                    franchise = franchise,
                    expanded = state.synopsisExpanded,
                    onToggle = { state.synopsisExpanded = !state.synopsisExpanded },
                    modifier = Modifier.padding(horizontal = detailGutter),
                )
                if (inLibrary && RewatchStore.sessions(franchise.id).isNotEmpty()) {
                    Box(Modifier.padding(horizontal = detailGutter)) {
                        HistoryRow(franchise = franchise, push = push)
                    }
                }

                EpisodesSection(
                    franchise = franchise,
                    state = state,
                    appModel = appModel,
                    now = now,
                    inLibrary = inLibrary,
                    tint = quietTint,
                    push = push,
                    modifier = Modifier.padding(horizontal = detailGutter),
                )

                val extras = remember(franchise) {
                    // Everything that is not a SEASON: films, OVAs, ONAs, spin-offs, specials.
                    val spine = franchise.seasonPartsInOrder.map { it.mediaId }.toSet()
                    franchise.parts.filterNot { spine.contains(it.mediaId) }.sortedBy { it.sequence }
                }
                MoviesAndExtrasShelf(
                    franchise = franchise,
                    parts = extras,
                    now = now,
                    inLibrary = inLibrary,
                    onToggle = { part -> toggleUnit(appModel, franchise, part) },
                    onOpen = { part -> push(DetailPush.Episodes(franchise.id, part.mediaId, null)) },
                )

                val videos = remember(franchise) { franchise.allVideos }
                if (videos.isNotEmpty()) {
                    DetailShelf(
                        title = Copy.Heading.trailers,
                        modifier = Modifier.anchor(state, ANCHOR_TRAILERS, scrollState),
                    ) {
                        items(videos, key = { "${it.site}/${it.id}" }) { video ->
                            TrailerCard(video = video, onPlay = { state.video = video }, showTitle = franchise.title)
                        }
                    }
                }

                val people = remember(franchise) {
                    franchise.people?.orderedPeople()?.take(PEOPLE_LIMIT).orEmpty()
                }
                if (people.isNotEmpty()) {
                    DetailShelf(
                        title = Copy.Heading.castAndCrew,
                        modifier = Modifier.anchor(state, ANCHOR_PEOPLE, scrollState),
                    ) {
                        items(people, key = { it.id }) { person -> PersonCard(person) }
                    }
                }

                val related = remember(franchise) { franchise.related.take(RELATED_LIMIT) }
                if (related.isNotEmpty()) {
                    DetailShelf(
                        title = Copy.Heading.moreLikeThis,
                        modifier = Modifier.anchor(state, ANCHOR_RELATED, scrollState),
                    ) {
                        items(related, key = { it.id }) { title ->
                            RelatedCard(
                                related = title,
                                resolving = state.resolvingRelated == title.id,
                                onOpen = { openRelated(scope, state, api, appModel, push, title) },
                            )
                        }
                    }
                }

                val availability = state.providers
                // Branch on the STATUS, never on `providers.isEmpty()` — and a section that says
                // "not here" is not a section.
                if (availability != null &&
                    availability.status == WatchAvailability.Status.AVAILABLE &&
                    availability.providers.isNotEmpty()
                ) {
                    WatchProvidersRow(
                        availability = availability,
                        onOpenLink = { uriHandler.openUri(it) },
                        modifier = Modifier.anchor(state, ANCHOR_WATCH, scrollState),
                    )
                }
            }

            // The scroll's bottom clearance. It extends the scrollable range, which is the property
            // that matters — the last row must be able to leave the bottom ramp.
            Spacer(Modifier.height(DetailMetrics.bottomClearance()))
        }

        DetailVeils(
            scroll = scroll,
            band = band,
            hardOn = scrolledUnderBar,
            ink = DetailTint.chrome(heroTint ?: tint),
        )

        DetailBar(
            franchise = franchise,
            state = state,
            appModel = appModel,
            now = now,
            inLibrary = inLibrary,
            docked = scrolledUnderBar,
            push = push,
            onBack = onBack,
            modifier = Modifier.align(Alignment.TopCenter),
        )
    }

    if (state.startRewatchOpen) {
        StartRewatchSheet(
            franchise = franchise,
            onDismiss = { state.startRewatchOpen = false },
            onStart = { chosen, startedAt -> startRewatch(appModel, franchise, chosen, startedAt) },
        )
    }

    DebugCaptureDriver(state = state, franchise = franchise, scrollState = scrollState, debug = debug) {
        franchise.related.getOrNull(it)?.let { title ->
            openRelated(scope, state, api, appModel, push, title)
        }
    }
}

private const val ANCHOR_TRAILERS = "trailers"
private const val ANCHOR_PEOPLE = "people"
private const val ANCHOR_RELATED = "related"
private const val ANCHOR_WATCH = "watch"

/**
 * Records a shelf's y inside the SCROLL CONTENT — the shelf's root position minus the container's,
 * plus how far the container has already scrolled. Consumed only by the capture driver.
 */
private fun Modifier.anchor(
    state: DetailScreenState,
    name: String,
    scrollState: ScrollState,
): Modifier = onGloballyPositioned { coords ->
    val y = coords.positionInRoot().y - state.contentTop + scrollState.value
    state.anchors[name] = y.roundToInt()
}

// =================================================================================================
// MARK: - The billboard
// =================================================================================================

/** The least photograph that must survive above the copy. */
private val heroArtBand = 132.dp

/** The bloom's own height, and how far INSIDE the photograph it starts. */
private val heroBloomHeight = 220.dp
private val heroBloomOverlap = 56.dp

/** Cover first; the banner only when there is no cover at all. */
private data class HeroArt(val url: String?, val portrait: Boolean)

private fun heroArt(f: Franchise?): HeroArt {
    // The TEXTLESS poster where the gallery has one: the billboard draws the name itself — and
    // `billboardResolution`: the billboard asks TMDB for the original, not the card's `w780`.
    val cover = billboardResolution(f?.textlessPortrait ?: f?.portraitArt)
    if (cover != null) return HeroArt(cover, portrait = true)
    val banner = billboardResolution(f?.landscapeArt)
    if (banner != null) return HeroArt(banner, portrait = false)
    return HeroArt(null, portrait = true)
}

/**
 * The billboard.
 *
 * The layer stack, bottom to top: a persistent palette ground (so the frame never flashes canvas
 * while the image decodes) · the art · [HeroCopyScrim] sized to the MEASURED copy · the copy ·
 * [HeroTopVeil] over the chrome band · the bloom.
 *
 * `ArtScrim` is passed at zero on both ends and therefore draws nothing, deliberately: *"Both
 * protections are drawn in POINTS — `HeroTopVeil` over the chrome band, `HeroCopyScrim` sized to the
 * measured copy. A fractional scrim on a 580-pt frame blankets the middle of the picture."*
 *
 * Why a billboard at all, quoted because it is the rationale a port must not undo:
 *
 * > The previous hero was a 320-pt landscape band with the 112-pt poster floating over its lower edge
 * > … on this catalogue's art it was the app's worst crop — a 4.75:1 AniList banner filled into a
 * > 1.2:1 band shows a quarter of itself, which put a forehead under the back button on the flagship
 * > title. Apple TV and Netflix open a show on its key art edge to edge with the lockup over it; the
 * > cover is within 4 % of this frame's aspect, so the composite path shows it whole and sharp.
 *
 * **The hero is not a control.** Unlike Today's it has no tap target of its own; its accessibility
 * surface is the two strings.
 */
@Composable
private fun DetailHero(
    franchise: Franchise,
    state: DetailScreenState,
    appModel: AppModel,
    now: Long,
    inLibrary: Boolean,
    nextUp: NextUp?,
    tint: Color?,
    heroTint: Color?,
    height: Dp,
    band: Dp,
) {
    val art = remember(franchise.portraitArt, franchise.landscapeArt) { heroArt(franchise) }
    val ground = heroTint ?: tint ?: ArtGround.neutralWarm
    val isAX = isAccessibilityTextSize()

    Box(Modifier.fillMaxWidth().height(height)) {
        ArtHeader(
            url = art.url,
            height = height,
            tint = ground,
            // Every stop multiplies by zero, so this draws NOTHING. See the doc above.
            scrimTop = 0f,
            scrimBottom = 0f,
            focus = Alignment.TopCenter,
            portraitSource = art.portrait,
            // The billboard BREATHES: ~7 % over 24 s, one transform on one layer, off under Reduce
            // Motion. Today's hero and this one; nothing else in the app drifts.
            drift = true,
        )

        HeroCopyScrim(
            copyHeight = state.heroCopyHeight,
            modifier = Modifier.align(Alignment.BottomCenter),
        )

        // ONE billboard lockup, Today's (`HeroLockup`, 5 Sep): the state badge, the name, the
        // moment and the episode, the season bar and the one action, all over the art's foot. The
        // page used to end its hero on a logo and a grey identity line and start a second block on
        // canvas with the badge, the fact and the capsule — a poster with a caption, then a widget
        // ("poorly built and rushed", user). The identity line heads the synopsis now; a show that
        // is not in the library draws its name alone.
        DetailHeroCopy(
            franchise = franchise,
            state = state,
            nextUp = nextUp,
            inLibrary = inLibrary,
            appModel = appModel,
            now = now,
            modifier = Modifier
                .align(Alignment.BottomStart)
                .fillMaxWidth()
                .padding(horizontal = ThemeMetrics.gutter)
                .padding(bottom = if (isAX) ThemeSpace.x5 else ThemeSpace.x4)
                .reportHeight { state.heroCopyHeight = it },
        )

        HeroTopVeil(band = band, modifier = Modifier.align(Alignment.TopCenter))

        HeroBloom(
            tint = heroTint ?: tint,
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
                .height(heroBloomHeight + heroBloomOverlap)
                .offset(y = heroBloomHeight),
        )
    }
}

private const val HERO_TITLE_MIN_SCALE = 0.85f
private const val HERO_IDENTITY_MIN_SCALE = 0.9f

/**
 * The bloom: the show's colour continuing past the photograph's bottom edge.
 *
 * It starts **inside** the picture and is an OVERLAY rather than a background, and both halves are
 * load-bearing: *"Ending it where the image ends put the whole colour ramp below the seam — a visible
 * full-width line across the widest part of the hero. And as a `.background` it was occluded by the
 * copy scrim (opaque canvas at the frame's bottom, by design) right up to the seam, then added its
 * light from the first row below it: the same line, measured again on the billboard."*
 *
 * A DARK show gets more of it — *"with the photograph sitting at canvas luminance the bloom is the
 * only thing separating identity from background"* (Game of Thrones' Iron Throne is the named case).
 *
 * Drawn with `BlendMode.Plus` straight into the parent's canvas. **No offscreen layer**: one would
 * blend the two gradients with each other and then paste the result opaquely, which is not what
 * `plusLighter` over the picture does. At the overlap's opacities (0 → 0.13) it is invisible on white
 * type.
 */
@Composable
private fun HeroBloom(tint: Color?, modifier: Modifier = Modifier) {
    val base = tint ?: ArtGround.neutralWarm
    // A null palette is treated as mid-lightness, exactly as iOS's `?? 0.5` does.
    val heroIsDark = (tint?.let { oklabLightness(it) } ?: 0.5) < HERO_DARK_LIGHTNESS
    val lift = if (heroIsDark) 1.8f else 1.0f
    Box(
        modifier
            .drawBehind {
                drawRect(
                    brush = Brush.verticalGradient(
                        0.00f to base.copy(alpha = 0f),
                        0.30f to base.copy(alpha = (0.20f * lift).coerceAtMost(1f)),
                        0.70f to base.copy(alpha = (0.07f * lift).coerceAtMost(1f)),
                        1.00f to base.copy(alpha = 0f),
                    ),
                    blendMode = BlendMode.Plus,
                )
                drawRect(
                    brush = Brush.radialGradient(
                        colors = listOf(
                            base.copy(alpha = (0.16f * lift).coerceAtMost(1f)),
                            Color.Transparent,
                        ),
                        // Inside its overlay (i2-4): at 0.12 / 300 dp the pool was still at 26 % at
                        // the overlay's top edge and printed a straight step above the frame's foot.
                        // Centred under the lockup (i3): the pool sat off to the left of a centred name.
                        center = Offset(size.width * 0.5f, size.height * 0.26f),
                        radius = HERO_BLOOM_RADIUS.toPx(),
                    ),
                    blendMode = BlendMode.Plus,
                )
            }
            .clearAndSetSemantics { },
    )
}

private const val HERO_DARK_LIGHTNESS = 0.34
private val HERO_BLOOM_RADIUS = 88.dp

/**
 * "Anime · 2016 · U/A 16+ · Action · Adventure".
 *
 * The budget is a CHARACTER COUNT rather than a measurement, on purpose: *"`minimumScaleFactor`
 * absorbs the last few points, and a `TextRenderer` pass on every identity change is not worth one
 * line of type."*
 *
 * The **studio is not on the hero** — *"a studio is a credit, not identity"* — and "8-Bit" /
 * "WIT Studio" read as genres with a missing separator when they closed the run.
 */
internal fun identityLine(f: Franchise, isAX: Boolean, withRating: Boolean = true): String {
    val genres = LinkedHashSet<String>()
    f.parts.forEach { part -> part.genres.forEach { genres.add(it.capitalisedWords()) } }
    val head = ArrayList<String>(3)
    head.add(f.kindWord)
    premiereYear(f)?.let { head.add(it.toString()) }
    if (withRating) f.contentRatingLabel?.let { head.add(it) }
    val budget = if (isAX) Int.MAX_VALUE else IDENTITY_BUDGET
    val tail = ArrayList(genres.take(3))
    while (true) {
        val line = (head + tail).joinToString(" · ")
        if (line.length <= budget || tail.isEmpty()) return line
        tail.removeAt(tail.size - 1)
    }
}

private const val IDENTITY_BUDGET = 46

/**
 * The year the WORK premiered, specials excluded.
 *
 * TMDB's season 0 carries the air date of the earliest featurette, which on Game of Thrones is
 * 2010-12-05: a pre-launch promo, five months before the show existed. Taking a plain minimum across
 * every part therefore printed "TV · 2010" on the flagship title. (The server computes this field
 * the same wrong way; this is the client half, so the screen is right either way.)
 */
internal fun premiereYear(f: Franchise): Int? {
    val real = f.parts.filter { it.kind != PartKind.SPECIAL }.mapNotNull { it.year }
    return (if (real.isEmpty()) f.parts.mapNotNull { it.year } else real).minOrNull()
}

/** The port of `.localizedCapitalized`, per word, in the device's own locale. */
private fun String.capitalisedWords(): String =
    split(' ').joinToString(" ") { word ->
        if (word.isEmpty()) word
        else word.substring(0, 1).uppercase(Locale.getDefault()) + word.substring(1)
    }

// =================================================================================================
// MARK: - The chrome
// =================================================================================================

/**
 * The two veils, of which **exactly one is mounted at a time** — *"a material at opacity 0 is still a
 * backdrop blur."*
 *
 * | condition | layer |
 * |---|---|
 * | `!hardOn && scroll.y > 12` | the SOFT veil, while ARTWORK is behind the toolbar |
 * | `hardOn` | the BAR, once CONTENT is behind the toolbar |
 *
 * The soft layer's opacity is the scroll's own, read INSIDE a `graphicsLayer` lambda so a scroll
 * frame invalidates a layer and nothing else.
 */
@Composable
private fun DetailVeils(scroll: ScrollOffset, band: Dp, hardOn: Boolean, ink: Color? = null) {
    val softVisible by remember(scroll) { derivedStateOf { scroll.y > SOFT_VEIL_ONSET } }

    AnimatedVisibility(
        visible = !hardOn && softVisible,
        enter = fadeIn(ThemeMotion.uiGentle()),
        exit = fadeOut(ThemeMotion.uiGentle()),
    ) {
        TopScrollEdgeChrome(
            modifier = Modifier.graphicsLayer { alpha = scroll.veilOpacity },
            height = band + SOFT_VEIL_RAMP,
            soft = true,
        )
    }
    AnimatedVisibility(
        visible = hardOn,
        enter = fadeIn(ThemeMotion.uiGentle()),
        exit = fadeOut(ThemeMotion.uiGentle()),
    ) {
        // "Hardened" means `chromeBarOpacity` canvas over a FULL-STRENGTH blur, never opaque canvas:
        // at 1.0 the top ~100 dp of every scrolled screen was a flat #09090B slab with the material
        // under it painted for nothing. `TopScrollEdgeChrome` owns that rule.
        TopScrollEdgeChrome(
            height = band + ThemeMetrics.barEdgeRamp,
            soft = false,
            holdHeight = band,
            // The show's colour as bar ink (`DetailTint.chrome`): the show's glass, not canvas.
            ink = ink,
        )
    }
}

private const val SOFT_VEIL_ONSET = 12f
private val SOFT_VEIL_RAMP = 100.dp

/**
 * Detail's floating bar: a back control, the docked title, and either the status pair or the Add
 * glyph.
 *
 * It draws no material of its own — [DetailVeils] is the material — because the hero has to bleed
 * under it. And there is exactly one back affordance: *"Three hand-built circles in one navigation
 * stack … is three answers to 'how do I go back'."*
 */
@Composable
private fun DetailBar(
    franchise: Franchise,
    state: DetailScreenState,
    appModel: AppModel,
    now: Long,
    inLibrary: Boolean,
    docked: Boolean,
    push: (DetailPush) -> Unit,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val titleAlpha by animateFloatAsState(
        targetValue = if (docked) 1f else 0f,
        animationSpec = motion(MotionToken.UI_GENTLE),
        label = "detailBarTitle",
    )
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(top = ThemeMetrics.topSafeInset())
            .height(DetailMetrics.toolbarClearance)
            .padding(horizontal = ThemeSpace.x1),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        DetailBackButton(onClick = onBack)
        Box(Modifier.weight(1f), contentAlignment = Alignment.Center) {
            BasicText(
                // Fit, shortened, or NOTHING (i2-8): a bar that says "That Time I Got R…" says
                // less than a bar with no noun.
                text = dockedName(franchise) ?: "",
                style = ThemeType.bodyEmphasis.copy(color = ThemeColor.textPrimary),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier
                    .graphicsLayer { alpha = titleAlpha }
                    // So the screen does not announce its name twice.
                    .then(if (docked) Modifier else Modifier.clearAndSetSemantics { }),
            )
        }
        if (inLibrary) {
            StatusMenu(franchise = franchise, state = state, appModel = appModel)
            Spacer(Modifier.width(ThemeSpace.x1))
            OverflowMenu(
                franchise = franchise,
                state = state,
                appModel = appModel,
                now = now,
                push = push,
            )
        } else {
            BarGlyphButton(
                symbol = PreviouslyIcons.Add,
                label = Copy.Detail.addToLibrary(franchise.title),
                glyph = DetailBackGlyph,
                onClick = {
                    appModel.addToLibrary(
                        franchiseId = franchise.id,
                        title = franchise.title,
                        isReleasing = franchise.isReleasing,
                        source = franchise.source,
                    )
                },
            )
        }
    }
}

/** Not in the copy catalogue: the platform's own word for the back affordance. */
internal const val backLabel = "Back"

/**
 * A bare glyph in the bar.
 *
 * **`interactive`, never `accent`.** The Add glyph sits directly above the episode list's amber
 * "Next up", so one hue must not mean both "press this" and "this is what's coming". And it is a
 * GLYPH, not a word: *"'+ Add' was the last piece of prose in the bar (and this SDK broke it
 * 'Ad / d')."*
 */
@Composable
internal fun BarGlyphButton(
    symbol: MaterialSymbol,
    label: String,
    glyph: Dp,
    onClick: () -> Unit,
    mirrored: Boolean = false,
) {
    Box(
        Modifier
            .size(minimumTapTarget)
            .clickable(
                interactionSource = null,
                indication = PressStyle.tertiary,
                role = Role.Button,
                onClick = onClick,
            )
            .semantics(mergeDescendants = true) { contentDescription = label },
        contentAlignment = Alignment.Center,
    ) {
        Image(
            imageVector = rememberSymbol(symbol),
            contentDescription = null,
            modifier = Modifier
                .size(materialGlyphBox(glyph))
                .then(if (mirrored) Modifier.graphicsLayer { scaleX = -1f } else Modifier),
            colorFilter = ColorFilter.tint(ThemeColor.interactive),
        )
    }
}

/**
 * The ONE back control across a franchise's three screens.
 *
 * A known substitution: the icon vocabulary carries no `arrow_back`, which is the Android reflex
 * here, so `chevron_right` MIRRORED is the same glyph pointing the way back — and it is what the
 * vocabulary can express today. Watch history draws the identical thing; when `arrow_back` is
 * vendored, all three change here. *"Three hand-built circles in one navigation stack … is three
 * answers to 'how do I go back'."*
 */
@Composable
internal fun DetailBackButton(onClick: () -> Unit) {
    BarGlyphButton(
        symbol = PreviouslyIcons.ChevronRight,
        label = backLabel,
        glyph = DetailBackGlyph,
        onClick = onClick,
        mirrored = true,
    )
}

/** The five statuses, in the order the menu lists them. */
private val statusMenuOrder = listOf(
    WatchStatus.WATCHING,
    WatchStatus.PLANNED,
    WatchStatus.COMPLETED,
    WatchStatus.PAUSED,
    WatchStatus.DROPPED,
)

/**
 * The unselected glyph for each status.
 *
 * `planned` maps to `bookmark` rather than a clock: the icon inventory has no `schedule`, and
 * bookmark's own recorded meaning is "planned / saved for later", which is exactly this row.
 */
private fun statusGlyph(status: WatchStatus): MaterialSymbol = when (status) {
    WatchStatus.WATCHING -> PreviouslyIcons.Pending.PlayCircle
    WatchStatus.PLANNED -> PreviouslyIcons.Bookmark
    WatchStatus.COMPLETED -> PreviouslyIcons.Pending.CheckCircle
    WatchStatus.PAUSED -> PreviouslyIcons.Pending.PauseCircle
    WatchStatus.DROPPED -> PreviouslyIcons.Pending.Cancel
}

/**
 * The status pill. **No local background** — *"a second capsule inside it is the inner pill that reads
 * as a refraction bug over bright artwork."*
 *
 * It carries the series-complete milestone: one restrained scale bounce, claimed once through
 * [SeasonSweepLedger] so a re-created bar cannot replay a milestone the user already saw.
 */
@Composable
private fun StatusMenu(
    franchise: Franchise,
    state: DetailScreenState,
    appModel: AppModel,
) {
    var open by remember { mutableStateOf(false) }
    val reduceMotion = LocalReduceMotion.current
    val current = franchise.effectiveStatus
    val name = Copy.statusLabel(current.wire)
    val scale = remember { Animatable(1f) }

    LaunchedEffect(state.milestoneToken, reduceMotion) {
        val token = state.milestoneToken ?: return@LaunchedEffect
        if (!SeasonSweepLedger.claim(token)) return@LaunchedEffect
        // Reduce Motion gets no scale bounce at all — it is not swapped for a shorter one.
        if (reduceMotion) return@LaunchedEffect
        scale.snapTo(MILESTONE_COMPRESSION)
        scale.animateTo(1f, ThemeMotion.uiMilestone())
    }

    Box {
        Row(
            modifier = Modifier
                .height(minimumTapTarget)
                .clickable(
                    interactionSource = null,
                    indication = PressStyle.tertiary,
                    role = Role.Button,
                    onClick = { open = true },
                )
                .semantics(mergeDescendants = true) {
                    contentDescription = "${Copy.Accessibility.changeStatus}, $name"
                }
                .padding(horizontal = ThemeSpace.x2)
                .graphicsLayer {
                    val s = scale.value
                    scaleX = s
                    scaleY = s
                },
            horizontalArrangement = Arrangement.spacedBy(DetailMetrics.glyphGap),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            BasicText(
                text = name,
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
            statusMenuOrder.forEach { status ->
                DetailMenuItem(
                    label = Copy.statusLabel(status.wire),
                    symbol = if (status == current) PreviouslyIcons.Check else statusGlyph(status),
                ) {
                    open = false
                    // `setStatus` fires `.selection`, writes optimistically and presents
                    // "Moved to Watching · Undo"; a failure ROLLS BACK and records on the banner.
                    appModel.setStatus(franchise.id, status)
                }
            }
        }
    }
}

private const val MILESTONE_COMPRESSION = 0.94f

/** Every item is gated; the glyph itself only appears for a show that is in the library. */
@Composable
private fun OverflowMenu(
    franchise: Franchise,
    state: DetailScreenState,
    appModel: AppModel,
    now: Long,
    push: (DetailPush) -> Unit,
) {
    var open by remember { mutableStateOf(false) }
    val part = franchise.currentPart
    val behind = part?.let { max(0, it.markTarget(now) - it.progress) } ?: 0
    val seriesBehind = remember(franchise, now) {
        franchise.episodicPartsInOrder.sumOf { max(0, it.markTarget(now) - it.progress) }
    }
    val session = RewatchStore.activeSession(franchise.id)
    val hasHistory = RewatchStore.sessions(franchise.id).isNotEmpty()

    Box {
        BarGlyphButton(
            symbol = PreviouslyIcons.MoreHoriz,
            label = Copy.Detail.moreActions,
            glyph = DetailMetrics.barGlyph,
            onClick = { open = true },
        )
        DetailMenu(expanded = open, onDismiss = { open = false }) {
            if (part != null && !part.isUpcoming) {
                val markTarget = part.markTarget(now)
                val through = min(part.progress + 5, markTarget)
                if (behind > 1 && through > part.progress + 1) {
                    DetailMenuItem(
                        label = Copy.Action.markThrough(from = part.progress + 1, to = through),
                    ) {
                        open = false
                        promptBatchMark(state, appModel, franchise, part, through)
                    }
                }
                if (behind > 0) {
                    DetailMenuItem(label = Copy.Action.markAllEpisodes) {
                        open = false
                        promptBatchMark(state, appModel, franchise, part, markTarget)
                    }
                }
                if (part.progress > 0) {
                    val total = max(part.headerTotal(), part.progress)
                    val label = part.canonicalLabel.ifEmpty { part.title }
                    DetailMenuItem(label = Copy.Action.markAllUnwatched(total)) {
                        open = false
                        state.prompt = WritePrompt(
                            title = Copy.Confirm.resetSeasonTitle(total),
                            message = Copy.Confirm.resetSeason(label = label, total = total),
                            confirm = Copy.Confirm.resetSeasonConfirm(total),
                        ) {
                            val prev = part.progress
                            appModel.setProgress(franchise.id, part.mediaId, 0)
                            appModel.presentUndo(
                                UndoState(
                                    mediaId = part.mediaId,
                                    franchiseId = franchise.id,
                                    prevProgress = prev,
                                    title = franchise.title,
                                    customMessage = Copy.Detail.labelMarkedUnwatched(label),
                                    undoAction = {
                                        appModel.setProgress(
                                            franchise.id,
                                            part.mediaId,
                                            prev,
                                            haptic = false,
                                        )
                                    },
                                ),
                            )
                        }
                    }
                }
                DetailMenuItem(label = Copy.Action.viewEpisodes) {
                    open = false
                    push(DetailPush.Episodes(franchise.id, part.mediaId, null))
                }
            }

            if (seriesBehind > 0) {
                DetailMenuItem(label = Copy.Action.markSeriesWatched) {
                    open = false
                    val seasons = franchise.episodicPartsInOrder.size
                    state.prompt = WritePrompt(
                        title = Copy.Confirm.batchMarkTitle(seriesBehind),
                        message = Copy.Detail.markSeriesMessage(franchise.title, seasons),
                        confirm = Copy.Confirm.batchMarkConfirm(seriesBehind),
                    ) {
                        // A multi-write command passes `haptic = false` to every write and fires ONE
                        // `.success` itself.
                        FeedbackCoordinator.fire(FeedbackToken.SUCCESS)
                        franchise.episodicPartsInOrder.forEach { p ->
                            val target = p.markTarget(now)
                            if (target > p.progress) {
                                appModel.setProgress(franchise.id, p.mediaId, target, haptic = false)
                            }
                        }
                        appModel.presentUndo(
                            UndoState(
                                franchiseId = franchise.id,
                                title = franchise.title,
                                count = seriesBehind,
                                customMessage = Copy.Toast.batchMarked(
                                    franchise.title,
                                    seriesBehind,
                                ),
                            ),
                        )
                    }
                }
            }

            if (session != null) {
                DetailMenuDivider()
                DetailMenuItem(label = Copy.Action.restartRewatch) {
                    open = false
                    restartRewatch(state, appModel, franchise)
                }
                DetailMenuItem(label = Copy.Detail.cancelRewatchAction) {
                    open = false
                    val at = franchise.currentPart?.progress ?: 0
                    state.prompt = WritePrompt(
                        title = Copy.Detail.cancelRewatchTitle,
                        message = Copy.Detail.cancelRewatchMessage(at),
                        confirm = Copy.Detail.cancelRewatchConfirm,
                        destructive = true,
                    ) {
                        FeedbackCoordinator.fire(FeedbackToken.DESTRUCTIVE)
                        // NO progress is touched, and there is no Undo: the session is kept in the
                        // history as cancelled.
                        RewatchStore.cancel(session.id, atEpisode = at, at = appModel.now)
                    }
                }
            }

            // `RewatchStore` records the first watch implicitly, at the moment a REWATCH starts — so
            // a finished show with no rewatch has no session, and this door led to "No watch history
            // yet" on a screen whose card, 40 dp above, said "Watched once". Two answers to the same
            // question.
            if (hasHistory) {
                DetailMenuItem(label = Copy.Action.viewWatchHistory) {
                    open = false
                    push(DetailPush.History(franchise.id))
                }
            }

            DetailMenuDivider()
            DetailMenuItem(
                label = Copy.Action.removeFromLibrary,
                symbol = PreviouslyIcons.Delete,
                destructive = true,
            ) {
                open = false
                // No confirmation: remove is reversible for the toast's whole window and never
                // touches watch history — the server deletes only the subscription row.
                appModel.removeWithUndo(franchise)
            }
        }
    }
}

/**
 * The app's menu chassis.
 *
 * `DropdownMenu` is the native answer — iOS's blurred lift-and-platter has no Android equivalent and
 * reproducing one is exactly the heavy engineering the fidelity line rules out. Its rows are plain
 * `clickable` `Row`s rather than `DropdownMenuItem`s, which build their own ripple with no way to
 * turn it off.
 */
@Composable
internal fun DetailMenu(
    expanded: Boolean,
    onDismiss: () -> Unit,
    content: @Composable ColumnScope.() -> Unit,
) {
    PreviouslyMaterialBridge {
        DropdownMenu(
            expanded = expanded,
            onDismissRequest = onDismiss,
            // The `.floating` surface level, spelled out: an opaque ground, a full `strokeStrong`
            // ring, and the floating shadow.
            shape = ContinuousCornerShape(ThemeRadius.compactControl),
            containerColor = ThemeColor.surfaceFloating,
            tonalElevation = 0.dp,
            shadowElevation = ShadowToken.Floating.elevation,
            border = BorderStroke(ThemeMetrics.hairline, ThemeColor.strokeStrong),
            content = content,
        )
    }
}

/** One command. `interactive` ink — a menu item is an action, and actions are ink, never amber. */
@Composable
internal fun DetailMenuItem(
    label: String,
    symbol: MaterialSymbol? = null,
    destructive: Boolean = false,
    onClick: () -> Unit,
) {
    val ink = if (destructive) ThemeColor.destructive else ThemeColor.interactive
    Row(
        Modifier
            .fillMaxWidth()
            .clickable(
                interactionSource = null,
                indication = PressStyle.groupedRow,
                role = Role.Button,
                onClick = onClick,
            )
            .height(minimumTapTarget)
            .padding(horizontal = ThemeMetrics.gutter),
        horizontalArrangement = Arrangement.spacedBy(ThemeSpace.x3),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (symbol != null) {
            Image(
                imageVector = rememberSymbol(symbol),
                contentDescription = null,
                modifier = Modifier.size(materialGlyphBox(DetailMetrics.barGlyph)),
                colorFilter = ColorFilter.tint(ink),
            )
        }
        BasicText(text = label, style = ThemeType.body.copy(color = ink), maxLines = 2)
    }
}

@Composable
internal fun DetailMenuDivider() {
    Spacer(
        Modifier
            .fillMaxWidth()
            .height(1.dp)
            .background(ThemeColor.separatorQuiet),
    )
}

// =================================================================================================
// MARK: - The state block
// =================================================================================================

/**
 * The billboard's copy (5 Sep): [HeroLockup] — Today's composable — for a show in the library, fed
 * from [NextUp]; the name alone otherwise.
 *
 * The state on the badge (an active rewatch prefixes its ordinal name: "Second watch · 3 episodes
 * behind"), the FULL title at `heroTitle` with a scale floor, the moment leading the line, the
 * reveal glyph on the line's trailing edge, the season bar, the airing cadence as the support line,
 * and beneath it the capsule (or "Start rewatch"). It replaced the boxed-then-deboxed "Next up"
 * block that sat on the canvas under the art: the hero and the block were one thing said in two
 * places.
 */
@Composable
private fun DetailHeroCopy(
    franchise: Franchise,
    state: DetailScreenState,
    nextUp: NextUp?,
    inLibrary: Boolean,
    appModel: AppModel,
    now: Long,
    modifier: Modifier = Modifier,
) {
    val isAX = isAccessibilityTextSize()
    val style = (if (isAX) ThemeType.displayXL else ThemeType.heroTitle).copy(color = ThemeColor.textPrimary)
    if (!inLibrary || nextUp == null) {
        // The FULL title — as the show's logo where the gallery has one, else in type with a scale
        // floor at EVERY size: the hero may never ellipsize the one name the screen exists to show.
        HeroTitle(
            text = franchise.title,
            name = franchise.billboardName,
            style = style,
            minScale = HERO_TITLE_MIN_SCALE,
            maxLines = if (isAX) Int.MAX_VALUE else 3,
            isAX = isAX,
            modifier = modifier.fillMaxWidth(),
        )
        return
    }

    val scope = rememberCoroutineScope()
    val reduceMotion = LocalReduceMotion.current
    val session = RewatchStore.activeSession(franchise.id)
    val eyebrow = session?.let { "${it.title} · ${nextUp.eyebrow}" } ?: nextUp.eyebrow
    val part = nextUp.part
    val episode = nextUp.episode
    val committed = state.committedEpisode != null && state.pinned != null
    val revealTarget: Int? = if (part != null && episode != null && canRevealEpisode(franchise, part, episode)) episode else null
    val bar = heroBar(franchise, nextUp, committed, state.committedEpisode, now)
    val accessory: (@Composable () -> Unit)? = if (!isAX && revealTarget != null) {
        {
            RevealGlyph(
                revealed = state.revealed.contains(revealTarget),
                onChange = { on ->
                    state.revealed = if (on) state.revealed + revealTarget else state.revealed - revealTarget
                },
            )
        }
    } else {
        null
    }

    HeroLockup(
        badge = eyebrow,
        title = franchise.title,
        name = franchise.billboardName,
        moment = if (committed) null else nextUp.moment,
        fact = nextUp.line1,
        support = secondLine(franchise, nextUp, state.revealed),
        progress = bar?.first,
        progressSpoken = bar?.second,
        modifier = modifier.seasonCompleteSweep(
            token = if (nextUp.kind == NextUp.Kind.SEASON_COMPLETE) state.sweepToken else null,
            reduceMotion = reduceMotion,
        ),
        third = nextUp.line3,
        style = style,
        minScale = HERO_TITLE_MIN_SCALE,
        maxLines = if (isAX) Int.MAX_VALUE else 3,
        accessory = accessory,
        receiptHost = ReceiptHost.detailHero(franchise.id),
    ) {
        if (part != null && episode != null &&
            (nextUp.kind == NextUp.Kind.ACTIONABLE || nextUp.kind == NextUp.Kind.BACKLOG)
        ) {
            MarkSplitButton(
                episode = if (committed) (state.committedEpisode ?: episode) else episode,
                committed = committed,
                behind = nextUp.behind,
                title = franchise.title,
                onMark = { mark(scope, state, appModel, franchise, part, now) },
                onMarkThrough = { through ->
                    promptBatchMark(state, appModel, franchise, part, through)
                },
                onMarkAll = {
                    promptBatchMark(state, appModel, franchise, part, part.markTarget(now))
                },
                modifier = Modifier
                    .padding(top = HeroLockupDefaults.actionGap(isAX))
                    .fillMaxWidth(),
            )
        }

        if (nextUp.kind == NextUp.Kind.SERIES_COMPLETE && session == null) {
            // Full width, as the mark capsule and iOS's are: a hugging capsule sat left in a
            // centred lockup.
            PrimaryButton(
                label = Copy.Action.startRewatch,
                onClick = { state.startRewatchOpen = true },
                hugging = false,
                modifier = Modifier
                    .padding(top = HeroLockupDefaults.actionGap(isAX))
                    .fillMaxWidth(),
            )
        }

        // At accessibility sizes the labelled reveal FOLLOWS the action rather than sharing a line
        // that is now a column.
        if (isAX && revealTarget != null) {
            RevealToggle(
                revealed = state.revealed.contains(revealTarget),
                onChange = { on ->
                    state.revealed = if (on) state.revealed + revealTarget else state.revealed - revealTarget
                },
            )
        }
    }
}

/**
 * Today's season bar, on the show page: watched over what there is to watch — aired-by-now for a
 * releasing season, the available run otherwise — advancing in the same frame as a mark. Null when
 * there is nothing to show: nothing watched yet, or everything.
 */
private fun heroBar(
    f: Franchise,
    state: NextUp,
    committed: Boolean,
    committedEpisode: Int?,
    now: Long,
): Pair<Float, String>? {
    if (state.kind != NextUp.Kind.ACTIONABLE && state.kind != NextUp.Kind.BACKLOG) return null
    val part = state.part ?: return null
    val done = if (committed) (committedEpisode ?: part.progress) else part.progress
    val total = if (part.isReleasing) part.airedByNow(now, f.timeAnchor) else part.availableEpisodes()
    if (total <= 0 || done <= 0 || done >= total) return null
    val left = max(0, total - done)
    val spoken = if (part.isReleasing) Copy.Progress.behind(left) else Copy.Progress.left(left)
    return (done.toFloat() / total.toFloat()) to spoken
}

/**
 * The reveal as a GLYPH on the line's trailing edge (5 Sep). The labelled toggle shared the fact's
 * row and took half of it, so "Season 3 · Episode 8" wrapped mid-phrase with a dangling middot
 * (Thrones). An eye in a 44-dp target, `textSecondary`, with the switch role and the labelled
 * control's words spoken; [RevealToggle] survives at accessibility sizes, under the action.
 */
@Composable
private fun RevealGlyph(revealed: Boolean, onChange: (Boolean) -> Unit) {
    Box(
        Modifier
            .size(HeroLockupDefaults.accessoryTarget)
            .toggleable(
                value = revealed,
                interactionSource = null,
                indication = PressStyle.tertiary,
                role = Role.Switch,
                onValueChange = onChange,
            )
            .semantics {
                contentDescription = if (revealed) Copy.Action.hideEpisodeTitle else Copy.Action.revealEpisodeTitle
            },
        contentAlignment = Alignment.Center,
    ) {
        Image(
            imageVector = rememberSymbol(
                if (revealed) PreviouslyIcons.VisibilityOff else PreviouslyIcons.Visibility,
            ),
            contentDescription = null,
            modifier = Modifier.size(materialGlyphBox(REVEAL_GLYPH)),
            colorFilter = ColorFilter.tint(ThemeColor.textSecondary),
        )
    }
}

private val REVEAL_GLYPH = 15.dp

/**
 * For `.actionable` only, the revealed episode title is appended to the support line.
 *
 * There is deliberately no "Title hidden to avoid spoilers" caption: *"the control and the sentence
 * saying the same thing 100 pt apart, and the sentence advertising that there is a spoiler to be had.
 * The control is the statement."*
 */
private fun secondLine(franchise: Franchise, state: NextUp, revealed: Set<Int>): String? {
    if (state.kind != NextUp.Kind.ACTIONABLE) return state.line2
    val part = state.part ?: return state.line2
    val episode = state.episode ?: return state.line2
    if (!revealed.contains(episode)) return state.line2
    val raw = part.episodes.firstOrNull { it.number == episode }?.title
    val title = EpisodeCopy.title(raw, franchise.title)
    return listOfNotNull(state.line2, title).joinToString(" · ")
}

/**
 * Only a REAL title can be revealed.
 *
 * *"The control used to appear whenever the catalogue held any string at all, including 'Episode 19'
 * — so tapping it replaced the fact line with the same words the fact line already carried."*
 */
private fun canRevealEpisode(franchise: Franchise, part: FranchisePart, episode: Int): Boolean {
    val raw = part.episodes.firstOrNull { it.number == episode }?.title ?: return false
    return EpisodeCopy.title(raw, franchise.title) != null
}

/**
 * A real switch, with the switch role and a spoken on/off value.
 *
 * `textTertiary` — *"a utility, quieter than the eyebrow it shares a row with"* — and the word is
 * "episode title", not "title": *"the word 'title' alone parses as the SHOW's title in a TV app."*
 */
@Composable
private fun RevealToggle(revealed: Boolean, onChange: (Boolean) -> Unit) {
    Row(
        Modifier
            .toggleable(
                value = revealed,
                interactionSource = null,
                indication = PressStyle.tertiary,
                role = Role.Switch,
                onValueChange = onChange,
            )
            .padding(vertical = ThemeSpace.x2, horizontal = ThemeSpace.x3),
        horizontalArrangement = Arrangement.spacedBy(ThemeSpace.x1),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Image(
            imageVector = rememberSymbol(
                if (revealed) PreviouslyIcons.VisibilityOff else PreviouslyIcons.Visibility,
            ),
            contentDescription = null,
            modifier = Modifier.size(materialGlyphBox(DetailMetrics.revealGlyph)),
            colorFilter = ColorFilter.tint(ThemeColor.textTertiary),
        )
        BasicText(
            text = if (revealed) Copy.Action.hideEpisodeTitle else Copy.Action.revealEpisodeTitle,
            style = ThemeType.listAction.copy(color = ThemeColor.textTertiary),
            maxLines = 1,
        )
    }
}

/**
 * The season-complete hairline: a 1-dp amber gradient sweeping out under the block.
 *
 * **No haptic of its own** — the transaction's single `.success` is the confirmation. Claimed through
 * [SeasonSweepLedger] so a re-created block cannot replay a milestone the user already saw.
 */
@Composable
private fun Modifier.seasonCompleteSweep(token: String?, reduceMotion: Boolean): Modifier {
    val progress = remember { Animatable(0f) }
    LaunchedEffect(token, reduceMotion) {
        if (token == null) return@LaunchedEffect
        if (!SeasonSweepLedger.claim(token) || reduceMotion) {
            progress.snapTo(1f)
            return@LaunchedEffect
        }
        progress.snapTo(0f)
        progress.animateTo(1f, ThemeMotion.uiSweep())
    }
    return drawWithContent {
        drawContent()
        val p = progress.value
        if (p <= 0f) return@drawWithContent
        val width = size.width * SWEEP_WIDTH_FRACTION * p
        if (width <= 0f) return@drawWithContent
        drawRect(
            brush = Brush.horizontalGradient(
                listOf(ThemeColor.accent, ThemeColor.accent.copy(alpha = 0f)),
                startX = 0f,
                endX = width,
            ),
            topLeft = Offset(0f, size.height + 3.dp.toPx()),
            size = Size(width, ThemeMetrics.hairline.toPx()),
        )
    }
}

private const val SWEEP_WIDTH_FRACTION = 0.64f

/**
 * The history row.
 *
 * The subtitle is PREDICATED on purpose: *"'95 episodes' (the work) and '50 episodes' (what the user
 * watched) sat two taps apart in the same noun phrase, so within one show the same words meant two
 * different quantities."*
 */
@Composable
private fun HistoryRow(franchise: Franchise, push: (DetailPush) -> Unit) {
    val sessions = RewatchStore.sessions(franchise.id)
    if (sessions.isEmpty()) return
    val watched = sessions.sumOf { it.episodes }
    GroupedList {
        GroupedRow(
            title = Copy.Action.viewWatchHistory,
            symbol = PreviouslyIcons.History,
            // The glyph sits directly on the plate. A filled 28-dp tile inside a plate is a second
            // container around a symbol, and tiles are for rows that carry ART.
            symbolTint = Color.Transparent,
            subtitle = Copy.episodesWatched(watched),
            trailing = GroupedTrailing.Chevron(),
            separator = false,
            onClick = { push(DetailPush.History(franchise.id)) },
        )
    }
}

// =================================================================================================
// MARK: - About
// =================================================================================================

/**
 * The synopsis, and the themes the genres do not already say.
 *
 * There is **no "ABOUT" label**: *"Three stacked blocks at three weights were saying one thing; a
 * synopsis under a hero does not need to be announced."*
 *
 * The source is the FIRST PART with a non-empty synopsis, not the franchise's own field. Three lines
 * and a "Read more", not four — *"Apple TV shows two and a MORE."* The type is `prose`, the ANNOTATING
 * face: *"a synopsis is quoted CONTENT, not the app's voice, and SF reads better than a geometric
 * sans over a full paragraph."*
 */
@Composable
private fun AboutSection(
    franchise: Franchise,
    expanded: Boolean,
    onToggle: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val synopsis = remember(franchise) {
        Formatting.stripHtml(franchise.parts.firstOrNull { !it.synopsis.isNullOrEmpty() }?.synopsis)
    }
    val isAX = isAccessibilityTextSize()
    // The certificate is a TAG beside the line (i3), the way a rating is printed everywhere
    // else: inline it read as one more genre.
    val identity = remember(franchise, isAX) { identityLine(franchise, isAX, withRating = false) }
    val rating = franchise.contentRatingLabel
    // The catalogue's themes for an anime often ARE its genres, and a fact printed twice on one
    // screen is a defect.
    val themes = remember(franchise) { franchise.themesBeyondGenres.take(4).joinToString(" · ") }
    if (synopsis.isEmpty() && identity.isEmpty()) return
    Column(modifier.fillMaxWidth()) {
        // ONE metadata line — class, year, rating, genres — heading the synopsis, where Apple TV
        // keeps a show's metadata (5 Sep). It used to close the hero's lockup under the name; with
        // the state block folded into the billboard the grey identity line was the last thing on
        // the art and the first thing under it an amber badge.
        // `metadata`, not `heroMeta`: off the art it is a footnote over the paragraph (Apple TV's
        // small grey "TV-MA · 2011 · Drama"); at the prose's own size the two read as one block.
        if (identity.isNotEmpty()) {
            // Kind · year, the tag, then the genres — air on both sides of the tag, no middot
            // against it (i4, Apple TV's grammar).
            val facts = identity.split(" · ")
            val headCount = facts.indexOfFirst { !(it == franchise.kindWord || it.all(Char::isDigit)) }
                .let { if (it < 0) facts.size else it }
            val head = facts.take(headCount).joinToString(" · ")
            val tail = facts.drop(headCount).joinToString(" · ")
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(bottom = if (synopsis.isEmpty()) 0.dp else ThemeSpace.x2),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(ThemeSpace.x2),
            ) {
                if (head.isNotEmpty()) {
                    BasicText(
                        text = head,
                        style = ThemeType.metadata.copy(color = ThemeColor.textSecondary),
                        maxLines = 1,
                    )
                }
                if (rating != null) CertificateTag(rating)
                if (tail.isNotEmpty()) {
                    AutoSizeText(
                        text = tail,
                        style = ThemeType.metadata.copy(color = ThemeColor.textSecondary),
                        minScale = HERO_IDENTITY_MIN_SCALE,
                        maxLines = if (isAX) 3 else 1,
                        modifier = Modifier.weight(1f, fill = false),
                    )
                }
            }
        }
        if (synopsis.isNotEmpty()) {
            // The link is drawn only when there is more (i4): a link that does nothing teaches
            // that links here do nothing.
            var overflows by remember(synopsis) { mutableStateOf(false) }
            BasicText(
                text = synopsis,
                style = ThemeType.prose.copy(color = ThemeColor.textSecondary),
                maxLines = if (expanded) Int.MAX_VALUE else 3,
                overflow = TextOverflow.Ellipsis,
                onTextLayout = { if (!expanded) overflows = it.hasVisualOverflow },
            )
            if (expanded || overflows) {
                InlineLinkButton(
                    label = if (expanded) Copy.Detail.readLess else Copy.Detail.readMore,
                    onClick = onToggle,
                    // Cancels the link style's own padding so the word starts on the gutter while
                    // the 44-dp target survives.
                    modifier = Modifier.negativePadding(
                        start = InlineLink.sideOverhang,
                        top = InlineLink.readingLift,
                        bottom = InlineLink.readingLift,
                    ),
                )
            }
            if (themes.isNotEmpty()) {
                BasicText(
                    text = themes,
                    style = ThemeType.metadata.copy(color = ThemeColor.textTertiary),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.padding(top = ThemeSpace.x2),
                )
            }
        }
    }
}

// =================================================================================================
// MARK: - Episodes
// =================================================================================================

/**
 * **Episodes are ON the show page** (Apple TV, Netflix).
 *
 * The show page used to list all eleven parts as database rows and push a second screen for the
 * episodes, so the thing a viewer opens a show for — which episode is next — was never on the page.
 * **There is no seasons row list any more**, and the section title IS the picker.
 */
@Composable
private fun EpisodesSection(
    franchise: Franchise,
    state: DetailScreenState,
    appModel: AppModel,
    now: Long,
    inLibrary: Boolean,
    tint: Color?,
    push: (DetailPush) -> Unit,
    modifier: Modifier = Modifier,
) {
    val seasons = franchise.seasonPartsInOrder
    val part = focusSeason(franchise, state.selectedSeasonId) ?: return
    val total = episodeListCount(part, now)
    // Re-keyed on the picker's choice, so a picker change lands on a FRESH list rather than rows
    // morphing their numbers in place.
    val controller = rememberEpisodeListController(part.mediaId, appModel)

    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(ThemeMetrics.labelGap),
    ) {
        EpisodesHeader(
            part = part,
            seasons = seasons,
            onSelect = { state.selectedSeasonId = it },
        )
        // The list owns its own range and grows IN PLACE. The six-row window with an
        // "All 24 episodes ›" door to a second screen was "a complete tangent… a broken
        // experience" (user, 6 Sep): a list that began at Episode 19 with the season's first
        // eighteen on another page was the tangent, not the season. The door is gone.
        EpisodeListColumn(
            franchise = franchise,
            part = part,
            total = total,
            now = now,
            inLibrary = inLibrary,
            controller = controller,
            tint = tint,
        )
    }
    WritePromptDialog(prompt = controller.prompt) { controller.prompt = null }
}

/**
 * The picker's choice → the part the screen is about (airing, resuming, or the earliest unfinished)
 * when that is a season → the earliest unfinished season → the last.
 */
internal fun focusSeason(f: Franchise, selectedId: Int?): FranchisePart? {
    val seasons = f.seasonPartsInOrder
    if (selectedId != null) {
        seasons.firstOrNull { it.mediaId == selectedId }?.let { return it }
    }
    val current = f.currentPart
    if (current != null) {
        seasons.firstOrNull { it.mediaId == current.mediaId }?.let { return it }
    }
    return seasons.firstOrNull { !it.isComplete } ?: seasons.lastOrNull()
}

/**
 * "Episodes" and, trailing, the season as a capsule menu ([SeasonPill]) — the streaming apps'
 * grammar: a section labelled Episodes, one "Season 4 ⌄" pill that lists seasons only. Where-you-are
 * is the bar under it, never "18 of 24" in numerals: beside a window that opened on Episode 18 the
 * pair read as "showing 18 of 24" (4 Sep). The season's name used to BE the section title, with a
 * stacked chevron, and did not read as a control.
 *
 * ⚠ **Port faithfully:** the header's total (`max(totalEpisodes, airedEpisodes)`) and the list's total
 * ([episodeListCount]) are computed differently and CAN disagree — the bar can be full while the list
 * draws 25 rows (a user marked past the catalogue's count). This is the shipped behaviour.
 */
@Composable
private fun EpisodesHeader(
    part: FranchisePart,
    seasons: List<FranchisePart>,
    onSelect: (Int) -> Unit,
) {
    val total = part.headerTotal()
    val watched = min(part.progress, total)

    Column(
        modifier = Modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(ThemeSpace.x2),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(ThemeSpace.x2),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            BasicText(
                text = Copy.Heading.episodes,
                style = ThemeType.sectionTitle.copy(color = ThemeColor.textPrimary),
                maxLines = 1,
                modifier = Modifier
                    .weight(1f, fill = false)
                    .semantics { heading() },
            )
            Spacer(Modifier.weight(1f))
            if (seasons.size > 1) {
                SeasonPill(current = part, seasons = seasons, onPick = onSelect)
            } else if (part.canonicalLabel.isNotEmpty()) {
                // One season with a name: the name, as a fact, not a control.
                BasicText(
                    text = part.canonicalLabel,
                    style = ThemeType.metadataEmphasis.copy(color = ThemeColor.textSecondary),
                    maxLines = 1,
                )
            }
        }
        if (total > 0) {
            ProgressBar(
                value = watched.toFloat() / total.toFloat(),
                spoken = Copy.Progress.watchedOf(watched, total),
            )
        }
    }
}

private const val SEASON_LABEL_MIN_SCALE = 0.85f

/**
 * The source's own label, else the part's title, else "Episodes".
 *
 * **Never derived from `sequence`** — a fabricated "Season 1" is worse than nothing.
 */
internal fun seasonLabel(part: FranchisePart): String =
    part.canonicalLabel.ifEmpty { part.title.ifEmpty { Copy.Heading.episodes } }

// =================================================================================================
// MARK: - Writes
// =================================================================================================

/**
 * The mark timeline.
 *
 * 1. re-entrancy guard; 2. ONE haptic — `.success` if this completes the season, else the light
 * commit; 3. the optimistic write (**a progress write never rolls back**; a failure goes to the
 * SyncBanner with a Retry); 4. `pinned` freezes the pre-mark franchise so the block keeps showing the
 * episode it just wrote for the result window; 5. the capsule flips to "Episode N watched" with the
 * check drawing in; 6. after 650 ms the pin clears and the handoff runs; 7. **once the handoff has
 * settled** the Undo toast is presented.
 */
private fun mark(
    scope: CoroutineScope,
    state: DetailScreenState,
    appModel: AppModel,
    franchise: Franchise,
    part: FranchisePart,
    now: Long,
) {
    if (state.committedEpisode != null) return
    val completes = part.progress + 1 >= part.markTarget(now) &&
        !part.isReleasing &&
        part.totalEpisodes > 0
    val snapshot = franchise
    val undo = appModel.markNext(
        franchiseId = franchise.id,
        mediaId = part.mediaId,
        haptic = if (completes) FeedbackToken.SUCCESS else FeedbackToken.COMMIT_LIGHT,
    ) ?: return

    if (completes) {
        state.sweepToken = UUID.randomUUID().toString()
        val others = franchise.episodicPartsInOrder.filter { it.mediaId != part.mediaId }
        val seriesDone = others.all { it.isComplete } &&
            franchise.parts.none { it.isReleasing || it.isUpcoming }
        if (seriesDone) {
            state.milestoneToken = UUID.randomUUID().toString()
            RewatchStore.activeSession(franchise.id)?.let {
                RewatchStore.complete(it.id, at = appModel.now)
            }
            appModel.setStatus(
                franchiseId = franchise.id,
                status = WatchStatus.COMPLETED,
                haptic = false,
                present = false,
            )
        }
    }

    state.pinned = snapshot
    // The receipt lands IN PLACE, under this capsule (`ReceiptLine` in the lockup).
    state.pendingUndo = undo.placed(ReceiptHost.detailHero(franchise.id))
    state.committedEpisode = undo.episode
    scope.launch {
        delay(MARK_RESULT_WINDOW_MILLIS)
        state.pinned = null
        state.committedEpisode = null
        // Presented once the card's handoff has settled, so the toast and the swap do not talk over
        // each other.
        delay(ThemeMotion.handoffSettleMillis.toLong())
        state.pendingUndo?.let { appModel.presentUndo(it) }
        state.pendingUndo = null
    }
}

/** How long the committed capsule holds its receipt before the block hands over. */
private const val MARK_RESULT_WINDOW_MILLIS = 650L

/** A forward batch. Every one of them states its exact blast radius first. */
internal fun promptBatchMark(
    state: DetailScreenState,
    appModel: AppModel,
    franchise: Franchise,
    part: FranchisePart,
    through: Int,
) {
    val count = max(1, through - part.progress)
    state.prompt = WritePrompt(
        title = Copy.Confirm.batchMarkTitle(count),
        message = Copy.Confirm.batchMarkMessage(from = part.progress + 1, to = through),
        confirm = Copy.Confirm.batchMarkConfirm(count),
    ) {
        appModel.markThrough(franchise.id, part.mediaId, through, present = false)
            ?.let { appModel.presentUndo(it, host = ReceiptHost.detailHero(franchise.id)) }
    }
}

/** No confirmation — the write is one unit and Undo is immediate. */
private fun toggleUnit(appModel: AppModel, franchise: Franchise, part: FranchisePart) {
    val full = max(part.totalEpisodes, 1)
    val watched = part.progress >= full
    val label = part.canonicalLabel.ifEmpty { part.title }
    val prev = part.progress
    appModel.setProgress(franchise.id, part.mediaId, if (watched) 0 else full)
    appModel.presentUndo(
        UndoState(
            mediaId = part.mediaId,
            franchiseId = franchise.id,
            prevProgress = prev,
            title = franchise.title,
            customMessage = if (watched) {
                Copy.Detail.labelMarkedUnwatched(label)
            } else {
                Copy.Detail.labelMarkedWatched(label)
            },
            undoAction = {
                appModel.setProgress(franchise.id, part.mediaId, prev, haptic = false)
            },
        ),
    )
}

/**
 * Three outcomes: already materialised → push; not yet → **an exact-title search asks the server to
 * materialise it and the first same-source hit is the show**; nothing → a neutral receipt with no
 * action (`ToastView(message:)`, no Undo, no failure styling).
 */
private fun openRelated(
    scope: CoroutineScope,
    state: DetailScreenState,
    api: DetailApi,
    appModel: AppModel,
    push: (DetailPush) -> Unit,
    related: RelatedTitle,
) {
    val id = related.franchiseId
    if (id != null) {
        push(DetailPush.Detail(id))
        return
    }
    // A second tap waits for the first.
    if (state.resolvingRelated != null) return
    state.resolvingRelated = related.id
    scope.launch {
        try {
            val hits = api.searchExact(related.title).filter { it.source == related.source }
            val hit = hits.firstOrNull { it.title.equals(related.title, ignoreCase = true) }
                ?: hits.firstOrNull()
            if (hit != null) {
                push(DetailPush.Detail(hit.id))
            } else {
                appModel.showNotice(Copy.Notice.notInCatalogue)
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            appModel.showNotice(Copy.Notice.notInCatalogue)
        } finally {
            state.resolvingRelated = null
        }
    }
}

// =================================================================================================
// MARK: - Rewatch
// =================================================================================================

/**
 * The rewatch transaction: ONE haptic, every part zeroed, the status moved, and one Undo that
 * restores the exact snapshot — **every part's progress including the zeroes, the previous status,
 * and the session deleted.**
 */
private fun startRewatch(
    appModel: AppModel,
    franchise: Franchise,
    scope: WatchSession.Scope,
    startedAt: Long,
) {
    val parts = when (scope) {
        is WatchSession.Scope.Franchise -> franchise.episodicPartsInOrder
        is WatchSession.Scope.Part -> franchise.parts.filter { it.mediaId == scope.mediaId }
    }
    val snapshot = parts.map { it.mediaId to it.progress }
    val previousStatus = franchise.effectiveStatus
    val episodes = parts.sumOf { max(it.totalEpisodes, it.progress) }
    val session = RewatchStore.startRewatch(
        franchiseId = franchise.id,
        scope = scope,
        startedAt = startedAt,
        episodes = episodes,
    )
    RewatchArrival.record(session.id)
    FeedbackCoordinator.fire(FeedbackToken.SUCCESS)
    snapshot.forEach { (mediaId, progress) ->
        if (progress > 0) appModel.setProgress(franchise.id, mediaId, 0, haptic = false)
    }
    appModel.setStatus(franchise.id, WatchStatus.WATCHING, haptic = false, present = false)
    appModel.presentUndo(
        UndoState(
            franchiseId = franchise.id,
            title = franchise.title,
            customMessage = Copy.Toast.rewatchStarted,
            undoAction = {
                RewatchStore.delete(session.id)
                snapshot.forEach { (mediaId, progress) ->
                    appModel.setProgress(franchise.id, mediaId, progress, haptic = false)
                }
                appModel.setStatus(franchise.id, previousStatus, haptic = false, present = false)
            },
        ),
    )
}

/**
 * Restart.
 *
 * *"The same receipt a season reset gets: a toast that names what moved and an Undo that restores the
 * exact snapshot. It wiped every tick with neither."*
 */
private fun restartRewatch(state: DetailScreenState, appModel: AppModel, franchise: Franchise) {
    val watched = franchise.episodicPartsInOrder.sumOf { it.progress }
    state.prompt = WritePrompt(
        title = Copy.Confirm.restartRewatchTitle,
        message = Copy.Confirm.restartRewatch(watched),
        confirm = Copy.Confirm.restartRewatchConfirm,
        destructive = true,
    ) {
        FeedbackCoordinator.fire(FeedbackToken.SUCCESS)
        val snapshot = franchise.episodicPartsInOrder.map { it.mediaId to it.progress }
        snapshot.forEach { (mediaId, progress) ->
            if (progress > 0) appModel.setProgress(franchise.id, mediaId, 0, haptic = false)
        }
        appModel.presentUndo(
            UndoState(
                franchiseId = franchise.id,
                title = franchise.title,
                customMessage = Copy.Toast.rewatchRestarted,
                undoAction = {
                    snapshot.forEach { (mediaId, progress) ->
                        appModel.setProgress(franchise.id, mediaId, progress, haptic = false)
                    }
                },
            ),
        )
    }
}

/**
 * The Start-rewatch sheet.
 *
 * Full height only: *"At `.medium` the scope list ran past the bottom of the sheet and the commit
 * button — now pinned as a bottom inset — had a list a screen and a half tall above it."*
 *
 * The scope rows are `MediaRow`s — *"the same season list is a push away, rendered as 88-pt poster
 * rows on the canvas; here it was text-only 56-pt rows inside a plate with a trailing count — two
 * grammars for one list, one tap apart."*
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun StartRewatchSheet(
    franchise: Franchise,
    onDismiss: () -> Unit,
    onStart: (WatchSession.Scope, Long) -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val seasons = franchise.episodicPartsInOrder
    var chosen by remember { mutableStateOf<WatchSession.Scope>(WatchSession.Scope.Franchise) }
    var startDate by remember { mutableStateOf(System.currentTimeMillis()) }
    var pickerOpen by remember { mutableStateOf(false) }
    val everythingCount = remember(seasons) { seasons.sumOf { max(it.totalEpisodes, it.progress) } }

    PreviouslyMaterialBridge {
        ModalBottomSheet(
            onDismissRequest = onDismiss,
            sheetState = sheetState,
            containerColor = ThemeColor.canvasRaised,
            scrimColor = ThemeColor.scrimStrong,
        ) {
            Column(Modifier.fillMaxWidth()) {
                Row(
                    Modifier
                        .fillMaxWidth()
                        .padding(horizontal = ThemeMetrics.gutter),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    // Neutral, not amber: amber on the dismissive action made the loudest coloured
                    // object on the sheet the one that throws the work away — and the selection tick
                    // is amber too, so there would be two ambers and neither the primary action.
                    InlineLinkButton(label = Copy.Action.cancel, onClick = onDismiss)
                    Spacer(Modifier.weight(1f))
                    BasicText(
                        text = Copy.Action.startRewatch,
                        style = ThemeType.bodyEmphasis.copy(color = ThemeColor.textPrimary),
                        maxLines = 1,
                    )
                    Spacer(Modifier.weight(1f))
                    Spacer(Modifier.width(minimumTapTarget))
                }

                Column(
                    Modifier
                        .weight(1f, fill = false)
                        .verticalScroll(rememberScrollState())
                        .padding(horizontal = ThemeMetrics.gutter)
                        .padding(top = ThemeMetrics.gutter),
                    verticalArrangement = Arrangement.spacedBy(ThemeMetrics.sectionGap),
                ) {
                    // A modal that opens on a grey sentence and a list of radio rows could be about
                    // anything, so the sheet leads with the show.
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(ThemeMetrics.artGap),
                        verticalAlignment = Alignment.Top,
                    ) {
                        PosterSlot(url = franchise.portraitArt, slot = PosterSize.Queue)
                        Column(verticalArrangement = Arrangement.spacedBy(ThemeMetrics.titleGap)) {
                            BasicText(
                                text = franchise.title,
                                style = ThemeType.showTitleM.copy(color = ThemeColor.textPrimary),
                                maxLines = 2,
                                overflow = TextOverflow.Ellipsis,
                            )
                            BasicText(
                                text = Copy.Detail.historyStaysUnchanged,
                                style = ThemeType.metadata.copy(color = ThemeColor.textSecondary),
                            )
                        }
                    }

                    Column(verticalArrangement = Arrangement.spacedBy(ThemeMetrics.labelGap)) {
                        SectionLabel(text = Copy.Detail.scope)
                        ScopeRow(
                            // "Everything", not "All seasons": it is printed directly over a list
                            // containing "OVA 1", "OVA 2: No Regrets" and "OVA 3: Lost Girls", none
                            // of which is a season.
                            title = Copy.Rewatch.everything,
                            count = if (everythingCount > 0) Copy.episodes(everythingCount) else null,
                            poster = franchise.portraitArt,
                            selected = chosen is WatchSession.Scope.Franchise,
                            separator = seasons.isNotEmpty(),
                            onSelect = { chosen = WatchSession.Scope.Franchise },
                        )
                        seasons.forEachIndexed { index, part ->
                            ScopeRow(
                                title = part.canonicalLabel.ifEmpty { part.title },
                                count = if (part.totalEpisodes > 0) {
                                    Copy.episodes(part.totalEpisodes)
                                } else {
                                    null
                                },
                                poster = part.portraitArt ?: franchise.portraitArt,
                                selected =
                                    (chosen as? WatchSession.Scope.Part)?.mediaId == part.mediaId,
                                separator = index < seasons.lastIndex,
                                onSelect = { chosen = WatchSession.Scope.Part(part.mediaId) },
                            )
                        }
                    }

                    // No "START DATE" header: the header and the row were the same three words,
                    // 10 dp apart.
                    GroupedList {
                        GroupedRow(
                            title = Copy.Detail.startDate,
                            trailing = GroupedTrailing.Value(Formatting.fmtFullDate(startDate)),
                            separator = false,
                            onClick = { pickerOpen = true },
                        )
                    }
                }

                // The commit, pinned — the port of `safeAreaInset(edge: .bottom)`.
                Box(
                    Modifier
                        .fillMaxWidth()
                        .chromeGlass(RectangleShape)
                        .padding(horizontal = ThemeMetrics.gutter)
                        .padding(top = ThemeSpace.x3, bottom = ThemeSpace.x2)
                        .padding(
                            bottom = with(LocalDensity.current) {
                                WindowInsets.navigationBars.getBottom(this).toDp()
                            },
                        ),
                ) {
                    PrimaryButton(
                        label = Copy.Action.startRewatch,
                        onClick = {
                            onStart(chosen, startDate)
                            onDismiss()
                        },
                    )
                }
            }
        }
    }

    if (pickerOpen) {
        RewatchDatePicker(
            initial = startDate,
            onDismiss = { pickerOpen = false },
            onPick = {
                startDate = it
                pickerOpen = false
            },
        )
    }
}

/**
 * One scope choice.
 *
 * The tick's column is **reserved whether or not the row is selected**, so a tick landing never
 * reflows the row it lands on.
 */
@Composable
private fun ScopeRow(
    title: String,
    count: String?,
    poster: String?,
    selected: Boolean,
    separator: Boolean,
    onSelect: () -> Unit,
) {
    MediaRow(
        title = title,
        meta = count,
        poster = poster,
        slot = PosterSize.Queue,
        chevron = false,
        separator = separator,
        onClick = {
            FeedbackCoordinator.fire(FeedbackToken.SELECTION)
            onSelect()
        },
    ) {
        Box(Modifier.width(SCOPE_TICK_COLUMN), contentAlignment = Alignment.Center) {
            Image(
                imageVector = rememberSymbol(PreviouslyIcons.Check),
                contentDescription = null,
                modifier = Modifier
                    .size(materialGlyphBox(DetailMetrics.barGlyph))
                    .graphicsLayer { alpha = if (selected) 1f else 0f },
                // A chosen value is STATE, which is one of amber's two legal readings.
                colorFilter = ColorFilter.tint(ThemeColor.accent),
            )
        }
    }
}

private val SCOPE_TICK_COLUMN = 18.dp

/** The date picker, bounded to today or earlier. Android's reflex is a dialog, not an inline wheel. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun RewatchDatePicker(initial: Long, onDismiss: () -> Unit, onPick: (Long) -> Unit) {
    val today = remember { System.currentTimeMillis() }
    val pickerState = rememberDatePickerState(
        initialSelectedDateMillis = initial,
        selectableDates = remember(today) {
            object : SelectableDates {
                override fun isSelectableDate(utcTimeMillis: Long): Boolean = utcTimeMillis <= today
            }
        },
    )
    // ONE colour set, given to BOTH the dialog and the picker inside it. Passing it only to the
    // dialog left the panel on `DatePickerDefaults`' own `containerColor`
    // (`MaterialTheme.colorScheme.surface` = `ThemeColor.canvas`), so a #09090B panel painted inside
    // a #0D0E11 dialog — and the chosen day wore `primary`, near-white, where every other chosen
    // value in the app wears an amber tick. A chosen value is STATE, which is one of amber's two
    // legal readings, and the ink on the amber disc is `onAccent`, so no amber word is drawn.
    val pickerColours = DatePickerDefaults.colors(
        containerColor = ThemeColor.surfaceFloating,
        titleContentColor = ThemeColor.textSecondary,
        headlineContentColor = ThemeColor.textPrimary,
        weekdayContentColor = ThemeColor.textTertiary,
        subheadContentColor = ThemeColor.textSecondary,
        navigationContentColor = ThemeColor.interactive,
        yearContentColor = ThemeColor.textPrimary,
        currentYearContentColor = ThemeColor.accent,
        selectedYearContentColor = ThemeColor.onAccent,
        selectedYearContainerColor = ThemeColor.accent,
        dayContentColor = ThemeColor.textPrimary,
        disabledDayContentColor = ThemeColor.textDisabled,
        selectedDayContentColor = ThemeColor.onAccent,
        selectedDayContainerColor = ThemeColor.accent,
        todayContentColor = ThemeColor.accent,
        todayDateBorderColor = ThemeColor.accent,
        dividerColor = ThemeColor.separatorQuiet,
    )
    PreviouslyMaterialBridge {
        DatePickerDialog(
            onDismissRequest = onDismiss,
            shape = ContinuousCornerShape(ThemeRadius.card),
            colors = pickerColours,
            tonalElevation = 0.dp,
            confirmButton = {
                TertiaryButton(
                    label = Copy.Action.done,
                    onClick = { onPick(pickerState.selectedDateMillis ?: initial) },
                )
            },
            dismissButton = {
                TertiaryButton(label = Copy.Action.cancel, onClick = onDismiss)
            },
        ) {
            DatePicker(
                state = pickerState,
                colors = pickerColours,
                // Material's own "Select date" resource, replaced with this app's word.
                title = {
                    BasicText(
                        text = Copy.Detail.startDateTitle,
                        style = ThemeType.sectionLabel.copy(color = ThemeColor.textSecondary),
                        modifier = Modifier.padding(
                            start = DatePickerTitleInset,
                            end = DatePickerTitleInset,
                            top = ThemeSpace.x4,
                        ),
                    )
                },
            )
        }
    }
}

/** Material's own headline inset, so the replaced title lands where the picker's headline does. */
private val DatePickerTitleInset = 24.dp

// =================================================================================================
// MARK: - The state block's decision tree
// =================================================================================================

/** The state block's whole content, as one value. */
@Immutable
class NextUp(
    val kind: Kind,
    val part: FranchisePart?,
    /** The STATE, staged in the capsule. */
    val eyebrow: String,
    /** The amber dot — a fresh, actionable episode only. */
    val dot: Boolean = false,
    /**
     * The WHEN, leading the lockup's one line ahead of the fact (Today's grammar, 5 Sep): today's
     * drop ("Aired 2h ago"), a caught-up show's next airing ("Friday at 7:30 PM").
     */
    val moment: String? = null,
    /** The FACT. */
    val line1: String,
    val line2: String?,
    val line3: String? = null,
    val episode: Int? = null,
    val behind: Int = 0,
) {
    enum class Kind { ACTIONABLE, BACKLOG, CAUGHT_UP, SEASON_COMPLETE, SERIES_COMPLETE, WAITING }

    /** Drives the handoff. */
    val identity: String get() = "$kind/${part?.mediaId ?: 0}/${episode ?: 0}"

    // Equality also compares `line2` deliberately, so a changed support line re-renders without a
    // full handoff.
    override fun equals(other: Any?): Boolean =
        other is NextUp && other.identity == identity && other.line2 == line2

    override fun hashCode(): Int = identity.hashCode() * 31 + (line2?.hashCode() ?: 0)
}

/**
 * The full decision tree.
 *
 * > The STATE goes to the eyebrow and the EPISODE is the fact (user, 30 Aug): a show airing tonight
 * > led with a 22-pt "Caught up" while "Today at 8:30 PM" — the thing the person opened the show for
 * > — hid in the support line.
 */
internal fun nextUpState(f: Franchise, now: Long): NextUp? {
    if (f.isSeriesComplete) return completeState(f, now)

    val current = f.currentPart
    if (current == null) {
        val upcoming = f.parts.firstOrNull { it.isUpcoming }
        if (upcoming != null) return waitingState(f, upcoming)
        val episodic = f.episodicPartsInOrder
        if (episodic.isNotEmpty() && episodic.all { it.isComplete }) return completeState(f, now)
        // No block at all.
        return null
    }

    if (current.isUpcoming) return waitingState(f, current)

    val behind = max(0, current.markTarget(now) - current.progress)
    if (behind == 0) {
        if (current.isComplete && !current.isReleasing) {
            val label = current.canonicalLabel
            val total = max(current.totalEpisodes, current.progress)
            val ahead = f.episodicPartsInOrder
                .firstOrNull { it.isUpcoming && it.mediaId != current.mediaId }
            val returns = ahead?.let { part ->
                val at = part.nextAiringAt ?: return@let null
                val name = part.canonicalLabel.ifEmpty { part.title }
                "$name ${TemporalCopy.returns(at, now, f.source).lowercasedFirstChar()}"
            }
            return NextUp(
                kind = NextUp.Kind.SEASON_COMPLETE,
                part = current,
                eyebrow = Copy.Label.complete,
                line1 = Copy.Progress.complete(label),
                line2 = Copy.Library.partProgress(label, min(current.progress, total), total),
                line3 = returns,
            )
        }
        val episode = current.nextEpisodeNumber ?: (current.progress + 1)
        // The next airing is the MOMENT, leading the line ("Friday at 7:30 PM · Season 5 · Episode
        // 10"); only its absence is a support line.
        val next = f.nextAiring(now)?.let { TemporalCopy.airs(at = it, now = now, source = f.source) }
        return NextUp(
            kind = NextUp.Kind.CAUGHT_UP,
            part = current,
            eyebrow = Copy.Progress.caughtUp,
            moment = next,
            line1 = f.watchContext(current, episode),
            line2 = if (next == null) TemporalCopy.noDateAnnounced else null,
        )
    }

    val episode = current.progress + 1
    val context = f.watchContext(current, episode)
    if (behind > 1) {
        return NextUp(
            kind = NextUp.Kind.BACKLOG,
            part = current,
            eyebrow = if (current.isReleasing) {
                Copy.Progress.behind(behind)
            } else {
                Copy.Progress.left(behind)
            },
            line1 = context,
            // The drop while it is fresh (i3): "Episode 21 aired yesterday" under "4 EPISODES
            // BEHIND" says which one struck; the next air date takes over once it has settled.
            line2 = dropAiredLine(f, current, now) ?: newEpisodeLine(f, now),
            episode = episode,
            behind = behind,
        )
    }
    // Today's fresh-hero grammar, verbatim (5 Sep): a drop that struck today is "NEW EPISODE" on the
    // badge with its recency leading the line ("Aired 2h ago · Season 4 · Episode 19"); an older
    // single drop wears its day on the badge and has no moment.
    val last = current.lastAired(now, f.timeAnchor)
    val recency = last?.let { TemporalCopy.aired(at = it, now = now, source = f.source) }
    val struck = last != null && now - last <= ShelfWindows.NOW_BAR_LIVE
    return NextUp(
        kind = NextUp.Kind.ACTIONABLE,
        part = current,
        eyebrow = if (struck) Copy.Label.newEpisode else (recency ?: Copy.Label.newEpisode),
        // The amber dot belongs to a fresh, actionable episode and nothing else.
        dot = true,
        moment = if (struck) recency else null,
        line1 = context,
        // No third line: "Caught up after this episode" restated what the badge and the
        // one-episode CTA already say — the capsule is the sentence.
        line2 = newEpisodeLine(f, now),
        episode = episode,
        behind = 1,
    )
}

private fun waitingState(f: Franchise, part: FranchisePart): NextUp {
    val label = part.canonicalLabel.ifEmpty { part.title }
    val date = part.announcedDateLabel(f.source)
    return NextUp(
        kind = NextUp.Kind.WAITING,
        part = part,
        eyebrow = Copy.Label.upcoming,
        line1 = label,
        line2 = date?.let { TemporalCopy.premieres(it) } ?: TemporalCopy.noDateAnnounced,
    )
}

/**
 * The complete state.
 *
 * The headline is the STATE, not the name: *"the show's name twice at near-hero weight in one
 * viewport, while the two facts the card exists to deliver — how many times, and when — sat under it
 * in tertiary grey. A card headlines its STATE; the identity is the hero's job and the hero already
 * did it."*
 *
 * `ahead` exists so *"this page cannot say COMPLETE while the Library's shelf says 'Returns Oct 2026'
 * about the same show — and a rumour is called one."*
 */
/** The name the bar can hold: `displayTitle` within the budget, else the shelf-shortened form, else null. */
internal fun dockedName(f: Franchise, budget: Int = 19): String? {
    if (f.displayTitle.length <= budget) return f.displayTitle
    val short = f.title.shelfShortened
    return if (short.length <= budget) short else null
}

private fun completeState(f: Franchise, now: Long): NextUp {
    val summary = RewatchStore.summary(f.id)
    val last = summary.lastCompletedAt
        ?.takeIf { it > 0 }
        ?.let { Copy.Detail.lastFinished(TemporalCopy.dateWord(it, now, TimeAnchor.LOCAL)) }
    // A show finished before the app ever saw it has no recorded date. The card still states what was
    // watched rather than leaving the fact column empty.
    val scale = f.episodicPartsInOrder
        .sumOf { max(it.totalEpisodes, it.progress) }
        .takeIf { it > 0 }
        ?.let { Copy.episodes(it) }
    val ahead = f.upcoming
        ?.takeIf { it.isFutureInstallment && !it.hasArrived(now) }
        ?.let { up ->
            when {
                // A rumour is labelled one everywhere the curated fact appears — never a date, never
                // amber.
                up.isRumored -> Copy.Library.rumored(up.next)
                up.next.isNullOrEmpty() -> returnFact(f, now)
                else -> "${up.next} · ${returnFact(f, now)}"
            }
        }
    // The fact and its scale on ONE line, then the ONE more thing (i1-F8).
    val fact = listOfNotNull(Copy.Progress.watchedTimes(max(1, summary.completedCount)), scale).joinToString(" · ")
    return NextUp(
        kind = NextUp.Kind.SERIES_COMPLETE,
        part = null,
        eyebrow = Copy.Label.complete,
        line1 = fact,
        line2 = ahead ?: last,
        line3 = null,
    )
}

/**
 * The curated "what's next", said once.
 *
 * On iOS this is `ReturnFact.of(_:appModel:)`, which lives in the LIBRARY area so the shelf caption
 * and this line cannot disagree. That file is not ported yet; when it lands, **delete this and call
 * it** — the whole point of the type is that there is one of it.
 */
private fun returnFact(f: Franchise, now: Long): String {
    val premiere = f.nextPremiere(now)
    if (premiere != null) return TemporalCopy.returns(at = premiere, now = now, source = f.source)
    val release = f.upcoming?.displayRelease.orEmpty()
    if (release.isNotEmpty()) return Copy.Detail.returnsWindow(release)
    return TemporalCopy.noDateAnnounced
}

/**
 * The airing cadence, said the way Netflix says it: "New episode Friday at 7:30 PM".
 *
 * "New", not "next": *"on a show nine episodes behind, 'next episode' is the one YOU watch next and
 * the reader would take the day for its air date."* A `planned` show gets no cadence line — it is in
 * your library but not in your week.
 */
/** "Episode 21 aired yesterday" while the latest drop is inside the live window, else null. */
private fun dropAiredLine(f: Franchise, part: FranchisePart, now: Long): String? {
    val last = f.lastAired(now) ?: return null
    if (now - last > ShelfWindows.NOW_BAR_LIVE) return null
    val whenText = TemporalCopy.aired(at = last, now = now, source = f.source).removePrefix("Aired ")
    return Copy.Progress.dropAired(part.airedByNow(now, f.timeAnchor), whenText)
}

private fun newEpisodeLine(f: Franchise, now: Long): String? {
    if (!f.tracksAirings) return null
    val at = f.nextAiring(now) ?: return null
    return Copy.Progress.newEpisode(TemporalCopy.airs(at = at, now = now, source = f.source))
}

/** "Returns tomorrow" → "returns tomorrow" — only the FIRST character; a month is a proper noun. */
private fun String.lowercasedFirstChar(): String =
    if (isEmpty()) this else this[0].lowercase() + substring(1)

// =================================================================================================
// MARK: - The skeleton
// =================================================================================================

/**
 * The shape that arrives.
 *
 * The billboard's ground is the palette rather than black — *"the loading frame is the first thing a
 * returning user sees, and it has no artwork yet by definition, so it was a black rectangle."*
 */
@Composable
private fun DetailSkeleton(tint: Color?) {
    val heroHeight = billboardHeight(
        fraction = Billboard.detail,
        copyHeight = 0.dp,
        artBand = heroArtBand,
    )
    Column(
        modifier = Modifier.fillMaxSize(),
        verticalArrangement = Arrangement.spacedBy(ThemeMetrics.sectionGap),
    ) {
        Box(
            Modifier
                .fillMaxWidth()
                .height(heroHeight)
                .background(tint ?: ThemeColor.ambientBackdropFallback),
        ) {
            Column(
                Modifier
                    .align(Alignment.BottomStart)
                    .padding(horizontal = ThemeMetrics.gutter)
                    .padding(bottom = ThemeMetrics.gutter),
                verticalArrangement = Arrangement.spacedBy(ThemeSpace.x2),
            ) {
                SkeletonLine(width = SkeletonHeroTitleWidth, height = SkeletonHeroTitleHeight)
                SkeletonLine(width = SkeletonHeroMetaWidth, height = SkeletonHeroMetaHeight)
            }
        }
        Column(
            Modifier.padding(horizontal = ThemeMetrics.gutter),
            verticalArrangement = Arrangement.spacedBy(ThemeMetrics.sectionGap),
        ) {
            SkeletonCard(height = SkeletonStateBlockHeight)
            Column(verticalArrangement = Arrangement.spacedBy(ThemeSpace.x2)) {
                SkeletonLine(height = SkeletonProseHeight)
                SkeletonLine(height = SkeletonProseHeight)
                SkeletonLine(width = SkeletonProseTailWidth, height = SkeletonProseHeight)
            }
            Column {
                repeat(3) {
                    SkeletonRow(
                        poster = PosterSize.Row.size,
                        lines = listOf(SkeletonRowTitleWidth, SkeletonRowMetaWidth),
                        posterRadius = ThemeRadius.poster,
                        spacing = ThemeMetrics.artGap,
                    )
                }
            }
        }
    }
}

// The show page's skeleton geometry: it mirrors the page it stands in for, so the swap changes
// content and not shape. Skeleton blocks do NOT scale with the text size — they are structure.
private val SkeletonHeroTitleWidth = 250.dp
private val SkeletonHeroTitleHeight = 26.dp
private val SkeletonHeroMetaWidth = 176.dp
private val SkeletonHeroMetaHeight = 13.dp

/** The state block's card. */
private val SkeletonStateBlockHeight = 190.dp

/** Three lines of synopsis, the last one short. */
private val SkeletonProseHeight = 12.dp
private val SkeletonProseTailWidth = 210.dp

/** An episode row's two lines. */
private val SkeletonRowTitleWidth = 150.dp
private val SkeletonRowMetaWidth = 104.dp

// =================================================================================================
// MARK: - The capture driver
// =================================================================================================

/**
 * The way to photograph the show page when the device cannot be touched — *"on 3 Sep System Events
 * saw no Simulator window and `screencapture` was refused, so cliclick had nothing to hit."*
 *
 * The router passes `null` unless the launch intent carried the extras, so there is no build-type
 * branch inside a composable here.
 */
@Composable
private fun DebugCaptureDriver(
    state: DetailScreenState,
    franchise: Franchise,
    scrollState: ScrollState,
    debug: DetailDebugArgs?,
    onOpenRelated: (Int) -> Unit,
) {
    if (debug == null) return
    LaunchedEffect(debug, franchise.id) {
        delay(DEBUG_DRIVE_DELAY_MILLIS)
        debug.anchor?.let { name -> state.anchors[name]?.let { scrollState.animateScrollTo(it) } }
        if (debug.trailer) state.video = franchise.allVideos.firstOrNull()
        debug.openRelated?.let { index ->
            if (index in franchise.related.indices) onOpenRelated(index)
        }
    }
}

/** The market's certificate as an outlined tag — "U/A 16+", "TV-MA" — beside the identity line. */
@Composable
private fun CertificateTag(text: String) {
    BasicText(
        text = text,
        style = ThemeType.metadataEmphasis.copy(color = ThemeColor.textSecondary),
        maxLines = 1,
        modifier = Modifier
            .border(1.dp, ThemeColor.textSecondary.copy(alpha = 0.45f), RoundedCornerShape(4.dp))
            .padding(horizontal = 5.dp, vertical = 1.dp),
    )
}
