package com.anitrack.app

import androidx.compose.runtime.Immutable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.anitrack.app.data.AmbientSync
import com.anitrack.app.data.AniTrackApi
import com.anitrack.app.data.ApiErrorTaxonomy
import com.anitrack.app.data.LibraryCache
import com.anitrack.app.data.NoAmbientSync
import com.anitrack.app.data.ProgressLane
import com.anitrack.app.data.ProgressWrite
import com.anitrack.app.data.RecentsStore
import com.anitrack.app.data.RewatchStore
import com.anitrack.app.data.SessionResets
import com.anitrack.app.data.SyncCenter
import com.anitrack.app.data.UndoState
import com.anitrack.app.data.WriteIntent
import com.anitrack.app.data.withStatus
import com.anitrack.app.data.withUpdatedProgress
import com.anitrack.app.design.FeedbackCoordinator
import com.anitrack.app.design.FeedbackToken
import com.anitrack.app.notifications.NotificationPrimer
import com.anitrack.model.Formatting
import com.anitrack.model.Franchise
import com.anitrack.model.FranchiseListResponse
import com.anitrack.model.FranchisePart
import com.anitrack.model.FranchiseSummary
import com.anitrack.model.MediaSource
import com.anitrack.model.ReleaseSortKey
import com.anitrack.model.ShelfState
import com.anitrack.model.ShelfWindows
import com.anitrack.model.Time
import com.anitrack.model.WatchStatus
import com.anitrack.model.behind
import com.anitrack.model.continueBacklog
import com.anitrack.model.copy.Copy
import com.anitrack.model.copy.CopyFilter
import com.anitrack.model.copy.EmptyStateCopy
import com.anitrack.model.currentPart
import com.anitrack.model.dayDiff
import com.anitrack.model.dayKey
import com.anitrack.model.effectiveStatus
import com.anitrack.model.hasArrived
import com.anitrack.model.isFutureInstallment
import com.anitrack.model.lastAired
import com.anitrack.model.lastAiredSortKey
import com.anitrack.model.nextAiring
import com.anitrack.model.nextAiringSortKey
import com.anitrack.model.nextPremiere
import com.anitrack.model.progressCeiling
import com.anitrack.model.releaseSortKey
import com.anitrack.model.releasingPart
import com.anitrack.model.resumePart
import com.anitrack.model.scheduleAirings
import com.anitrack.model.shelfState
import com.anitrack.model.snapshotForUndo
import com.anitrack.model.timeAnchor
import com.anitrack.model.tracksAirings
import java.text.Collator
import kotlin.math.abs
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import com.anitrack.app.data.ReceiptPlacement
import com.anitrack.app.ui.state.LaneItem
import com.anitrack.model.isWatchedThrough

/*
 * # The brain
 *
 * The one object every screen reads from and writes through. It owns the signed-in account's
 * library, a 20-second wall clock, the search subsystem, every derived feed (Today's stacks, the
 * Schedule agenda, the Library shelves) and every mutation the app can perform.
 *
 * Four rules make this subsystem correct, and none of them is visible in the type signatures:
 *
 *  1. **A progress mark never rolls back; membership and status writes always do.** See
 *     `data/WritePolicy.kt`, which states the rule and the production bug behind its asymmetry.
 *  2. **One progress PUT is in flight per part, newest-wins, superseded targets are dropped**
 *     ([ProgressLane]).
 *  3. **Every "is it out / when is the next one" question is computed from the per-episode
 *     `airings` list, never from the catalogue's counters** — the derive layer's freshness ladder.
 *  4. **The library has an offline copy on disk**, so a launch with no network opens on the shows,
 *     not on an error.
 *
 * A port that gets the pixels right and these rules wrong is wrong.
 *
 * ## Observation
 *
 * Per-field Compose snapshot state, **not** one immutable `UiState`. This is the true analogue of
 * Swift `@Observable`'s per-property tracking, and it is load-bearing rather than stylistic: the
 * 20-second clock tick writes [now] three times a minute, and a single state object would invalidate
 * every screen on every tick. It is also why [nowMinute] exists as its own field (Schedule's facts
 * are all minute-grained) and why [libraryVersion] is a plain `var` — bumping the schedule cache's
 * key must not invalidate anything by itself.
 *
 * ## Threading
 *
 * Every stored property and every method is confined to the main thread, as the Swift type is
 * `@MainActor`. The session [scope] runs on `Dispatchers.Main.immediate`; only the two disk writes
 * (the offline copy, the session file) hop to IO, inside their own stores.
 */
@Stable
class AppModel(
    private val api: AniTrackApi,
    /**
     * Required, never defaulted: a taxonomy that answered `isUnauthorized` with `false` would
     * render "couldn't load your library" over a dead session forever. Wiring it is a decision.
     */
    private val errors: ApiErrorTaxonomy,
    private val cache: LibraryCache,
    private val recentsStore: RecentsStore,
    private val ambient: AmbientSync = NoAmbientSync,
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate),
) {

    companion object {
        /** Fallback "out now" window when `/me/opened` never answered. */
        const val NEW_LOOKBACK: Long = 3 * Time.DAY_MS

        /** Calendar feed span, in days either side of today. */
        const val SCHEDULE_BACK: Int = -7
        const val SCHEDULE_AHEAD: Int = 14

        /**
         * Wall-clock tick period. Countdowns are minute-grained, so 20 s guarantees at most 20 s of
         * lag on a minute boundary while costing three writes a minute rather than sixty.
         */
        const val CLOCK_TICK_MILLIS: Long = 20_000

        /** Cap for both recents lists. */
        const val MAX_RECENTS: Int = 10

        /**
         * Away-time past which returning to the foreground triggers a [reload].
         *
         * Separate from [NEW_VISIT_AFTER] on purpose: brief app switches must not wipe "Out now" by
         * re-stamping `/me/opened`.
         */
        const val STALE_RELOAD_AFTER: Long = 2 * Time.MINUTE_MS

        /** Away-time past which returning also re-stamps `/me/opened` — a genuinely new visit. */
        const val NEW_VISIT_AFTER: Long = 6 * Time.HOUR_MS

        /** Debounce before a keystroke becomes a request. */
        const val SEARCH_DEBOUNCE_MILLIS: Long = 300

        /** How long a just-caught-up row keeps its place while its celebration plays. */
        const val CELEBRATION_MILLIS: Long = 1_300

        /** A neutral receipt carries no action, so it is the shortest-lived message the app has. */
        const val NOTICE_MILLIS: Long = 2_500

        /** The margin past the undo window before an add may arm the notification primer. */
        const val PRIMER_ARM_DELAY_MILLIS: Long = 500

        /** Every caller of the chart asks for ten. */
        const val TRENDING_LIMIT: Int = 10

        /** Today is a glance, not the whole library. */
        const val KEEP_WATCHING_LIMIT: Int = 8
    }

    // =============================================================================================
    // MARK: - State: library and account
    // =============================================================================================

    private val libraryState = mutableStateOf<List<Franchise>>(emptyList())
    private val libraryIdsState = mutableStateOf<Set<String>>(emptySet())

    /**
     * The whole signed-in library. Writing it refreshes the id mirror and bumps [libraryVersion] —
     * the Kotlin spelling of the Swift `didSet`.
     */
    var library: List<Franchise>
        get() = libraryState.value
        private set(value) {
            libraryState.value = value
            libraryIdsState.value = value.mapTo(HashSet(value.size)) { it.id }
            // Wrapping increment, exactly as Swift's `&+=`: Kotlin's Int overflows silently and
            // only equality is ever asked of this number.
            libraryVersion += 1
        }

    /**
     * Bumped on every library write; the key the derived-feed cache ([scheduleDays]) hangs off.
     *
     * **Deliberately not snapshot state** (`@ObservationIgnored` on iOS): the library write that
     * bumps it has already invalidated everything that reads the library, and a second observable
     * write for the same event would only add churn.
     */
    private var libraryVersion = 0

    /**
     * O(1) membership. The Discover grid calls [isInLibrary] per card on every animating frame; a
     * linear scan there is the reason this mirror exists.
     */
    val libraryIds: Set<String> get() = libraryIdsState.value

    /** Optimistically added, not yet confirmed by a reload. */
    var pendingAdds: Set<String> by mutableStateOf(emptySet())
        private set

    /** From `POST /me/opened`; drives "since you were last here". */
    var prevOpenedAt: Long by mutableLongStateOf(0)
        private set

    /** A library request is in flight. */
    var loading: Boolean by mutableStateOf(true)
        private set

    /** Epoch-ms of the last payload that actually **arrived**. The app's single freshness stamp. */
    var lastLoadedAt: Long by mutableLongStateOf(0)
        private set

    /** Set by the root once the splash has left. Today's recap waits on it. */
    var surfaceReady: Boolean by mutableStateOf(false)

    /** The last library refresh failed — never a cancellation, never a 401. */
    var loadError: Boolean by mutableStateOf(false)
        private set

    /**
     * Invoked when the server rejects our credentials. The auth layer owns the response — a 401
     * means the session is gone, which is a sign-in problem, never a connectivity one.
     */
    var onSessionExpired: (() -> Unit)? = null

    /** A show a tapped episode alert (or the debug launch argument) asks to open. */
    var pendingOpen: String? by mutableStateOf(null)

    // =============================================================================================
    // MARK: - State: clock
    // =============================================================================================

    private val nowState = mutableLongStateOf(System.currentTimeMillis())

    /** Epoch-ms, refreshed every 20 s and on foreground. */
    var now: Long
        get() = nowState.longValue
        private set(value) {
            nowState.longValue = value
            val minute = (value / Time.MINUTE_MS) * Time.MINUTE_MS
            if (minute != nowMinute) nowMinute = minute
        }

    /**
     * [now] truncated to the minute, written **only when the minute changes**.
     *
     * A screen whose every fact is minute-grained (Schedule) observes this, so the 20-second tick
     * does not re-lay it out three times a minute for nothing.
     */
    var nowMinute: Long by mutableLongStateOf(
        (System.currentTimeMillis() / Time.MINUTE_MS) * Time.MINUTE_MS,
    )
        private set

    // =============================================================================================
    // MARK: - State: search and discover
    // =============================================================================================

    private val searchQueryState = mutableStateOf("")

    /** The live field text. Writing it clears the literal-search flag and re-schedules. */
    var searchQuery: String
        get() = searchQueryState.value
        set(value) {
            searchQueryState.value = value
            searchExactOnce = false
            scheduleSearch()
        }

    /** Unfiltered; the media chip is applied by [filteredSearchResults]. */
    var searchResults: List<FranchiseSummary> by mutableStateOf(emptyList())
        private set

    var searchBusy: Boolean by mutableStateOf(false)
        private set

    var searchError: Boolean by mutableStateOf(false)
        private set

    /**
     * The server's spell repair for the results currently on screen. Present **only when the
     * correction differs from the original**, case-insensitively — "showing results for X" that
     * echoes X back is noise.
     */
    var searchCorrection: SearchCorrection? by mutableStateOf(null)
        private set

    /**
     * Per-catalogue outcome (`anilist`/`tmdb` → `ok` | `failed` | `disabled`). A TMDB outage must
     * render as a notice, not as "no TV results".
     */
    var searchSources: Map<String, String>? by mutableStateOf(null)
        private set

    /**
     * Opts exactly one request out of the server's correction (`&exact=1`). Any keystroke clears it
     * — the flag belongs to the request the user asked for, not to the field.
     */
    private var searchExactOnce = false

    /** The trimmed text the last search was scheduled for. See [scheduleSearch]. */
    private var lastScheduledQuery = ""

    /** Most-recent-first, de-duplicated case-insensitively, capped at [MAX_RECENTS]. */
    var recentSearches: List<String> by mutableStateOf(emptyList())
        private set

    /**
     * Shows opened or added *from* a search. Apple Music's model: the things you found, not the
     * strings you typed.
     */
    var recentItems: List<FranchiseSummary> by mutableStateOf(emptyList())
        private set

    /** The chart for the search zero-state and Today's empty-account billboard. */
    var trending: List<FranchiseSummary> by mutableStateOf(emptyList())
        private set

    /**
     * Observable, unlike the other task handles, because [trendingLoading] is derived from it: Today
     * holds a skeleton on that rather than flashing "Nothing to watch yet" for the ~300 ms before
     * the billboard arrives.
     */
    private var trendingTask: Job? by mutableStateOf(null)

    val trendingLoading: Boolean get() = trending.isEmpty() && trendingTask != null

    /**
     * A CTA elsewhere ("Add a show", the empty Schedule) asked for the search **field**, not just
     * the tab. Search consumes it and clears it.
     */
    var searchFieldRequested: Boolean by mutableStateOf(false)

    /**
     * Anime/TV filter — **search only**. Today, Schedule and Library are your shows and always show
     * everything: a filter set once while browsing used to silently hide half of what aired.
     */
    var mediaFilter: MediaFilter by mutableStateOf(MediaFilter.ALL)

    // =============================================================================================
    // MARK: - State: transients
    // =============================================================================================

    /** Franchise ids currently celebrating; entries expire after [CELEBRATION_MILLIS]. */
    var justCaught: Set<String> by mutableStateOf(emptySet())
        private set

    /** The single live Undo toast. Only one can be on screen at a time. */
    var undo: UndoState? by mutableStateOf(null)
        private set

    /** A transient write-failure message. Never a *failed write* — that is the SyncBanner. */
    var errorToast: String? by mutableStateOf(null)
        private set

    /** A neutral receipt with no action ("Episode alerts on"). */
    var notice: String? by mutableStateOf(null)
        private set

    // =============================================================================================
    // MARK: - Internals
    // =============================================================================================

    private var clockTask: Job? = null
    private var searchTask: Job? = null
    private var undoTask: Job? = null
    private var errorTask: Job? = null
    private var noticeTask: Job? = null

    /** Celebration timers, keyed by franchise id. */
    private val ccTasks = HashMap<String, Job>()

    /** Set when the app enters the background; drives the staleness checks on return. */
    private var backgroundedAt: Long? = null

    /**
     * Monotonic tokens. Each fired request claims the next value; a response mutates state only if
     * its captured value is still current, so out-of-order completions cannot clobber fresh
     * results. [teardown] bumps **both**, which invalidates every in-flight response at once —
     * which is why plain counters are kept even though the coroutines are structured.
     */
    private var searchSeq = 0
    private var reloadSeq = 0

    /** One optimistic progress write, awaiting a server snapshot that confirms it. */
    private data class LocalWrite(
        val episodes: Int,
        /**
         * [reloadSeq] at the moment the PUT settled; `null` while it is still in flight. Any
         * snapshot fetched by a LATER reload was read after the server had its final say, so it is
         * authoritative — see [reconcileLocalProgress].
         */
        val settledAtSeq: Int?,
    )

    /**
     * Optimistic progress writes a server snapshot has not confirmed yet, keyed by `mediaId`
     * (globally unique).
     *
     * Two jobs it exists for: a franchise added seconds ago is not in [library] until the add's
     * reload lands, so the write has nowhere to go; and a reload already in flight when the write
     * happened carries a pre-write snapshot that would silently revert it.
     */
    private val localProgress = HashMap<Int, LocalWrite>()

    private val progressLane = ProgressLane(scope) { mediaId, write -> putProgress(write, mediaId) }

    /**
     * The port of `localizedCaseInsensitiveCompare`: locale-aware, case-blind, accent-aware.
     * `SECONDARY` strength is what drops case while keeping "Résumé" ≠ "Resume".
     *
     * A `Collator` is not thread-safe; every sort that uses it is main-confined, as the whole model
     * is.
     */
    private val titleOrder: Collator = Collator.getInstance().apply { strength = Collator.SECONDARY }

    private val franchiseTitleOrder: Comparator<Franchise> =
        Comparator<Franchise> { a, b -> titleOrder.compare(a.title, b.title) }

    init {
        // Synchronous, in the constructor: the search tab must be able to compose its recents on the
        // first frame. A decode failure leaves a list empty; it is never an error.
        recentSearches = recentsStore.loadTerms()
        recentItems = recentsStore.loadItems()
    }

    // =============================================================================================
    // MARK: - Lifecycle
    // =============================================================================================

    /**
     * Called on every transition into signed-in. **Order matters.**
     */
    fun start() {
        startClock()

        // A failed change restored from a previous launch retries by replaying its write here —
        // not by reloading a library that never had it.
        SyncCenter.replay = { intent -> replay(intent) }

        // The offline copy FIRST: the last library this device saw, stamped with its real age so
        // the stale strip and the inline notice tell the truth. Without it a bad connection at
        // launch was "Couldn't reach the server" over nothing, seconds after the library had been
        // on screen.
        if (library.isEmpty()) {
            cache.load()?.let { cached ->
                library = cached.response.franchises
                prevOpenedAt = maxOf(prevOpenedAt, cached.response.prevOpenedAt)
                lastLoadedAt = cached.savedAt
            }
        }

        // Two independent coroutines, deliberately not sequenced.
        scope.launch { stampOpened() }
        scope.launch { reload() }
    }

    private fun startClock() {
        clockTask?.cancel()
        clockTask = scope.launch {
            while (isActive) {
                delay(CLOCK_TICK_MILLIS)
                now = System.currentTimeMillis()
            }
        }
    }

    /**
     * Records the previous-open timestamp (which drives "since you were last here") and stamps now.
     *
     * `/me/opened` is explicitly **not** idempotent — it returns the *previous* value and then
     * stamps — so it is never retried and never replayed: a replay would return "now" and destroy
     * the recap's whole premise. A failure is swallowed and "out now" falls back to a three-day
     * lookback ([effectivePrev]).
     */
    private suspend fun stampOpened() {
        try {
            prevOpenedAt = api.markOpened().prevOpenedAt
        } catch (e: CancellationException) {
            throw e
        } catch (_: Throwable) {
            // Non-fatal, and deliberately invisible.
        }
    }

    suspend fun reload() {
        reloadSeq += 1
        val seq = reloadSeq
        loading = true
        try {
            val res = api.library()
            // A newer reload — or a sign-out teardown — superseded this request. Its snapshot is
            // stale by definition; applying it would resurrect state we just tore down.
            if (seq != reloadSeq) return
            library = reconcileLocalProgress(res.franchises, seq)
            settleCompletedSeries()
            // Keep the larger of the two prevOpenedAt values we may have seen.
            if (res.prevOpenedAt > 0) prevOpenedAt = maxOf(prevOpenedAt, res.prevOpenedAt)
            // The screens fade their "couldn't refresh" footnote in and out around this flag. On
            // iOS the fade is put into the transaction here (`withAnimation`); on Android the
            // transition belongs to the `AnimatedVisibility` that draws the notice, so the model
            // only states the fact.
            loadError = false
            loading = false
            lastLoadedAt = System.currentTimeMillis()
            cache.save(res, lastLoadedAt)
            syncAmbient()
        } catch (e: Throwable) {
            val cancelled = e is CancellationException
            if (seq == reloadSeq) {
                if (errors.isUnauthorized(e)) {
                    // NOT a load failure: retrying can never fix a dead session, and "the server
                    // couldn't be reached" would be a lie. Hand it to auth.
                    handleSessionExpired()
                } else {
                    loading = false
                    // A cancelled refresh (a pull whose screen left, a superseding reload) is not a
                    // failed one: it must not raise the footnote over good content.
                    if (!cancelled && !errors.isCancellation(e)) loadError = true
                }
            }
            if (cancelled) throw e
        }
    }

    /** The session is gone. Drop every trace of it, then let auth surface the honest reason. */
    private fun handleSessionExpired() {
        teardown()
        onSessionExpired?.invoke()
    }

    /**
     * Full account teardown, run on every sign-out — voluntary or forced by a 401.
     *
     * Anything that outlives the view tree has to be dismantled here: the in-memory library, the
     * live clock, in-flight requests, the failed-write list and the two ambient layers would
     * otherwise keep serving the previous account. It leaves the model in its launch state so the
     * next sign-in opens on a loader, never on someone else's shows.
     */
    fun teardown() {
        completedByMark.clear()
        completionSweepDone = false
        RewatchStore.reset()
        SessionResets.runAll()
        cache.clear()

        clockTask?.cancel(); clockTask = null
        searchTask?.cancel(); searchTask = null
        trendingTask?.cancel(); trendingTask = null
        undoTask?.cancel(); undoTask = null
        errorTask?.cancel(); errorTask = null
        noticeTask?.cancel(); noticeTask = null
        notice = null

        for (job in ccTasks.values) job.cancel()
        ccTasks.clear()
        progressLane.cancelAll()

        // The next account must not inherit this one's failed writes — a Retry there would send the
        // previous user's mark into the new user's library.
        SyncCenter.teardown()

        // Invalidate every in-flight response so a late completion cannot repopulate the model.
        searchSeq += 1
        reloadSeq += 1

        library = emptyList()
        pendingAdds = emptySet()
        localProgress.clear()
        prevOpenedAt = 0
        loadError = false
        loading = true            // the next sign-in mounts on the loader, not on an empty shelf
        backgroundedAt = null

        lastScheduledQuery = ""
        searchQuery = ""          // the setter clears the flag and re-schedules
        searchResults = emptyList()
        searchBusy = false
        searchError = false
        searchCorrection = null
        searchSources = null
        trending = emptyList()
        searchFieldRequested = false
        mediaFilter = MediaFilter.ALL

        justCaught = emptySet()
        undo = null
        errorToast = null

        ambient.cancelAll()
    }

    // ---------------------------------------------------------------------------------------------
    // MARK: - Process lifecycle
    // ---------------------------------------------------------------------------------------------

    fun sceneEnteredBackground() {
        backgroundedAt = System.currentTimeMillis()
    }

    /**
     * Snaps the countdown clock immediately (the tick coroutine was suspended), reloads when the
     * data is stale, and re-stamps `/me/opened` when the away-time reads as a **new visit**.
     *
     * Android may kill and recreate the process where iOS merely suspends it. On process death
     * [backgroundedAt] is lost, so the app takes the [start] path — a full reload and a fresh
     * stamp — instead of this one. That is correct, and it is why nothing here is persisted.
     */
    fun sceneBecameActive() {
        now = System.currentTimeMillis()
        val bg = backgroundedAt ?: return   // launch activation — start() covers it
        backgroundedAt = null
        val away = now - bg
        if (away < STALE_RELOAD_AFTER) return
        scope.launch {
            if (away >= NEW_VISIT_AFTER) stampOpened()
            reload()
        }
    }

    /**
     * Alerts were just allowed (the notification primer): arm them **now**, from the library already
     * on screen. They used to wait for the next reload — "Turn on" granted permission and scheduled
     * nothing, so the first alert could be a day away.
     */
    suspend fun alertsWereAllowed() {
        syncAmbient()
    }

    /**
     * Push the current library into the ambient layers after any confirmed server-side change.
     *
     * **It swallows everything the ambient layer throws, and that is the point.** `AmbientSync.sync`
     * is documented as "it must not throw", but nothing enforced it and on Android it genuinely can:
     * the canonical case is a `SecurityException` out of `AlarmManager` the moment
     * `SCHEDULE_EXACT_ALARM` is revoked at runtime. Every call site here sits inside the SUCCESS
     * branch of a write, so an escaping exception was caught as a *server* failure:
     *
     * * [reload] painted "Couldn't refresh" over a library that had arrived and was already
     *   committed to `library`, `lastLoadedAt` and the offline copy;
     * * [setStatus] ROLLED BACK a status the server had accepted, cleared its undo and filed a bogus
     *   failed change whose Retry re-issued a PATCH that had already succeeded;
     * * [removeFromLibrary] re-inserted a franchise the server had already deleted.
     *
     * On iOS this is impossible — `EpisodeNotifications.sync` and `AiringLiveActivityManager.sync`
     * are non-throwing Swift calls — so the enforcement belongs here, at the one point every caller
     * goes through. An alarm that could not be scheduled is the notification layer's problem to
     * report, not the library's.
     *
     * Cancellation still propagates: it is not a failure, and the callers already know that.
     */
    private suspend fun syncAmbient() {
        try {
            ambient.sync(library, System.currentTimeMillis())
        } catch (cancellation: CancellationException) {
            throw cancellation
        } catch (_: Throwable) {
            // Deliberately invisible. See above.
        }
    }

    // =============================================================================================
    // MARK: - Toasts, receipts and celebration
    // =============================================================================================

    /**
     * Present a receipt for a write that already happened (when a card's handoff settles). With
     * [host] it lands IN PLACE under that control; without, on the bottom chrome's lane.
     */
    fun presentUndo(state: UndoState, host: String? = null) {
        undo = if (host != null) state.placed(host) else state
        scheduleUndoDismissal()
    }

    /** What the lane shows: the newest of a failure, a lane-placed undo, or a notice. */
    val laneItem: LaneItem?
        get() {
            errorToast?.let { return LaneItem.Error(it) }
            undo?.let { if (it.placement == ReceiptPlacement.Lane) return LaneItem.Undo(it) }
            notice?.let { return LaneItem.Notice(it) }
            return null
        }

    /**
     * The lifetime comes from [SyncCenter], which is the only thing that knows whether a screen
     * reader is running. On iOS that knowledge existed and never reached the timer: the constant
     * was declared, documented and never called while the sleep beside it used a hard-coded 6, so
     * an Undo a VoiceOver user could not reach in time was still exactly six seconds long.
     */
    private fun scheduleUndoDismissal() {
        undoTask?.cancel()
        undoTask = scope.launch {
            delay(SyncCenter.toastMillis)
            undo = null
        }
    }

    /** A quiet receipt with no action ("Episode alerts on"). **No haptic.** */
    fun showNotice(message: String) {
        notice = message
        noticeTask?.cancel()
        noticeTask = scope.launch {
            delay(NOTICE_MILLIS)
            notice = null
        }
    }

    fun showError(message: String) {
        FeedbackCoordinator.fire(FeedbackToken.DIRECT_ERROR)
        errorToast = message
        errorTask?.cancel()
        errorTask = scope.launch {
            delay(SyncCenter.errorMillis)
            errorToast = null
        }
    }

    /**
     * Keeps a just-caught-up row on screen for its celebration. `behind` drops to 0 the instant
     * progress is written, which would otherwise yank the row — and the frame its result state
     * renders on — before it is ever seen.
     */
    private fun celebrate(franchiseId: String) {
        justCaught = justCaught + franchiseId
        ccTasks[franchiseId]?.cancel()
        ccTasks[franchiseId] = scope.launch {
            delay(CELEBRATION_MILLIS)
            justCaught = justCaught - franchiseId
            ccTasks.remove(franchiseId)
        }
    }

    // =============================================================================================
    // MARK: - Recents
    // =============================================================================================

    /** Records the current query as a recent term. Called when the field is submitted. */
    fun recordRecentSearch() {
        val q = searchQuery.trim()
        if (q.length < 2) return
        recentSearches = (listOf(q) + recentSearches.filterNot { it.equals(q, ignoreCase = true) })
            .take(MAX_RECENTS)
        recentsStore.saveTerms(recentSearches)
    }

    fun removeRecentSearch(term: String) {
        recentSearches = recentSearches.filterNot { it.equals(term, ignoreCase = true) }
        recentsStore.saveTerms(recentSearches)
    }

    fun clearRecentSearches() {
        recentSearches = emptyList()
        recentsStore.saveTerms(recentSearches)
    }

    /** A show acted on from a result set (opened or added) is worth remembering as itself. */
    fun recordRecentItem(item: FranchiseSummary) {
        recentItems = (listOf(item) + recentItems.filterNot { it.id == item.id }).take(MAX_RECENTS)
        recentsStore.saveItems(recentItems)
    }

    fun removeRecentItem(id: String) {
        recentItems = recentItems.filterNot { it.id == id }
        recentsStore.saveItems(recentItems)
    }

    /** Everything under "Recently searched": the shows and the leftover terms. */
    fun clearRecents() {
        recentItems = emptyList()
        recentsStore.saveItems(recentItems)
        clearRecentSearches()
    }

    // =============================================================================================
    // MARK: - Search
    // =============================================================================================

    private fun scheduleSearch() {
        val trimmed = searchQuery.trim()
        // A whitespace-only edit ("naruto" -> "naruto ") is not a new query. It used to cancel the
        // in-flight request and re-issue the identical one 300 ms later.
        if (trimmed == lastScheduledQuery && trimmed.isNotEmpty() && !searchExactOnce) return
        lastScheduledQuery = trimmed
        searchTask?.cancel()

        // A cleared box falls back to the recents empty state. It never shows an error.
        if (trimmed.isEmpty()) {
            searchBusy = false
            searchError = false
            searchResults = emptyList()
            searchCorrection = null
            searchSources = null
            searchTask = null
            return
        }

        searchBusy = true
        searchError = false
        searchTask = scope.launch {
            delay(SEARCH_DEBOUNCE_MILLIS)
            runSearch(trimmed)
        }
    }

    private suspend fun runSearch(query: String) {
        searchSeq += 1
        val seq = searchSeq
        val exact = searchExactOnce
        try {
            val response = api.search(query, exact)
            if (seq != searchSeq) return   // a newer keystroke superseded this request
            searchResults = response.franchises
            searchCorrection = SearchCorrection.from(response)
            searchSources = response.sources
            searchExactOnce = false
            searchError = false
            searchBusy = false
        } catch (e: Throwable) {
            val cancelled = e is CancellationException || errors.isCancellation(e)
            // Checked BEFORE the sequence guard, as on iOS: a search cancelled by the next
            // keystroke is not a failure and must not raise the error state on its way out.
            if (!cancelled && seq == searchSeq) {
                searchCorrection = null
                searchSources = null
                searchError = true
                searchBusy = false
            }
            if (e is CancellationException) throw e
        }
    }

    /**
     * "Search instead for …": re-run the words the user actually typed, with the server's spell
     * correction turned off for that one request.
     *
     * The order is load-bearing — assigning [searchQuery] clears the flag through its setter, so the
     * flag must be raised **after** it and before [retrySearch] reads it.
     */
    fun searchLiterally(term: String) {
        if (searchQuery != term) searchQuery = term
        searchExactOnce = true
        retrySearch()
    }

    /** Re-run the current query immediately, with no debounce — the Retry on a failed search. */
    fun retrySearch() {
        val trimmed = searchQuery.trim()
        if (trimmed.isEmpty()) return
        searchTask?.cancel()
        searchBusy = true
        searchError = false
        searchTask = scope.launch { runSearch(trimmed) }
    }

    /**
     * Fetch the zero-state chart, once per session, lazily. **Quiet on failure** — the launchpad
     * simply shows recents alone, and the next cold visit tries again.
     */
    fun loadTrendingIfNeeded() {
        if (trending.isNotEmpty() || trendingTask != null) return
        // LAZY, then assign, then start: see ProgressLane for why an eagerly-started coroutine on
        // `Main.immediate` cannot be trusted to have been stored before its body runs.
        val job = scope.launch(start = CoroutineStart.LAZY) {
            try {
                trending = api.trending(TRENDING_LIMIT)
            } catch (e: CancellationException) {
                throw e
            } catch (_: Throwable) {
                // Nothing to retry into; the shelf is simply absent.
            } finally {
                if (trendingTask === coroutineContext[Job]) trendingTask = null
            }
        }
        trendingTask = job
        job.start()
    }

    /** The pull on Search: refetch the chart, which also gives a failed first fetch its retry. */
    suspend fun refreshTrending() {
        trendingTask?.cancel()
        trendingTask = null
        val items = try {
            api.trending(TRENDING_LIMIT)
        } catch (e: CancellationException) {
            throw e
        } catch (_: Throwable) {
            null
        }
        // Only a non-empty result replaces the chart: a pull that comes back empty must not blank
        // a shelf that was already right.
        if (!items.isNullOrEmpty()) trending = items
    }

    // =============================================================================================
    // MARK: - Derived: trivial helpers
    // =============================================================================================

    fun isInLibrary(id: String): Boolean = libraryIds.contains(id) || pendingAdds.contains(id)

    /**
     * Search results with the anime/TV chip applied (the server interleaves both sources). **The
     * only surface [mediaFilter] touches.**
     */
    val filteredSearchResults: List<FranchiseSummary>
        get() = searchResults.filter { matchesMediaFilter(it.source) }

    fun franchise(id: String): Franchise? = library.firstOrNull { it.id == id }

    /**
     * Which catalogue a franchise came from, resolved from whatever is loaded. `null` when we
     * genuinely do not know — callers must treat that as "not AniList" rather than guess.
     */
    fun sourceOf(franchiseId: String): MediaSource? =
        franchise(franchiseId)?.source
            ?: searchResults.firstOrNull { it.id == franchiseId }?.source
            ?: trending.firstOrNull { it.id == franchiseId }?.source

    fun matchesMediaFilter(source: MediaSource): Boolean = when (mediaFilter) {
        MediaFilter.ALL -> true
        MediaFilter.ANIME -> source == MediaSource.ANILIST
        MediaFilter.TV -> source == MediaSource.TMDB
    }

    val libraryEmpty: Boolean get() = library.isEmpty()

    val effectivePrev: Long get() = if (prevOpenedAt > 0) prevOpenedAt else now - NEW_LOOKBACK

    /**
     * Every subscribed franchise that has a currently-releasing part **and** belongs on the calendar
     * (`tracksAirings` — a `planned` show does not).
     *
     * Never media-filtered: what aired today is a fact about your library, not about a chip you last
     * touched in search. The `planned` exclusion is load-bearing — without it a mid-broadcast show
     * you had only shelved arrived on Today as "20 episodes behind" with a "Mark 20 episodes as
     * watched" ring: an obligation invented out of a bookmark.
     */
    val airingFranchises: List<Franchise>
        get() = library.filter { it.releasingPart != null && it.tracksAirings }

    /**
     * Descending recency for the live shelves — the **airings-advanced** `lastAired`, so an episode
     * that struck a minute ago leads a drop from last night whose catalogue field still says last
     * week until the next sync.
     */
    private fun lastAiredKey(f: Franchise): Long = f.lastAired(now) ?: 0L

    // =============================================================================================
    // MARK: - Derived: Today's stacks
    // =============================================================================================

    /**
     * "Out now" — releasing parts with a recently aired **unwatched** episode, freshest first.
     *
     * Keyed on unwatched-ness and recency, **not** on [prevOpenedAt]: the old last-open comparison
     * made a new episode vanish from Today the second time you opened the app, watched or not.
     */
    val outNow: List<Franchise>
        get() = airingFranchises
            .filter { f ->
                val part = f.releasingPart ?: return@filter false
                val behind = part.behind(now, f.timeAnchor)
                if (behind <= 0 && !justCaught.contains(f.id)) return@filter false
                now - (part.lastAired(now, f.timeAnchor) ?: 0L) <= ShelfWindows.OUT_NOW
            }
            .sortedByDescending { lastAiredKey(it) }

    /** "Airing soon" — a genuine wait inside 48 h, soonest first. */
    val soon: List<Franchise>
        get() = airingFranchises
            .filter { f ->
                val next = f.nextAiring(now) ?: return@filter false
                val delta = next - now
                delta > 0 && delta <= ShelfWindows.SOON
            }
            .sortedBy { it.nextAiring(now) ?: Long.MAX_VALUE }

    /**
     * The soonest upcoming airing across every airing franchise — **not** limited to 48 h.
     *
     * This is the "waiting" hero and the all-caught-up line, so every slot it yields must still be a
     * genuine WAIT. A date-only TV drop legitimately stays "up next" for the whole of its day (its
     * clock is synthesized and the labels are day-granular); an AniList slot that has struck can
     * never appear, because `upcomingAiring` has already moved to the following slot — which is what
     * prevents "lands Today 9:00 AM" being rendered at 8 pm.
     */
    val nextUp: Franchise?
        get() = airingFranchises
            .mapNotNull { f -> f.nextAiring(now)?.let { f to it } }
            .minByOrNull { it.second }
            ?.first

    /**
     * Today's Now Bar fact — one global answer to "when".
     *
     * Deliberately mirrors the ambient layer's "one soonest episode" model so the lock screen and
     * Today tell the same story.
     */
    val nowBarItem: NowBarItem?
        get() {
            val f = outNow.firstOrNull()
            if (f != null) {
                val last = f.releasingPart?.lastAired(now, f.timeAnchor)
                if (last != null) {
                    val fresh = if (f.timeAnchor.isDateOnly) {
                        // A date-only drop has no real instant to measure hours against, so its own
                        // day is the whole of its freshness.
                        f.dayDiff(last, now) == 0
                    } else {
                        // Deliberately tighter than `OUT_NOW`: the bar answers "what is happening
                        // now", not "what is still unwatched".
                        now - last <= ShelfWindows.NOW_BAR_LIVE
                    }
                    if (fresh) return NowBarItem(f.id, NowBarItem.State.LIVE, last)
                }
            }
            val next = nextUp
            val at = next?.nextAiring(now)
            if (next != null && at != null) return NowBarItem(next.id, NowBarItem.State.NEXT, at)
            // The bar collapses to nothing: Today must not nag with an idle strip.
            return null
        }

    /**
     * "Keep watching" — mid-watch backlog not already surfaced in Out now (a binged TV season, or a
     * show you have fallen behind on off its airing schedule). Most backlog first.
     */
    val keepWatching: List<Franchise>
        get() {
            val outNowIds = outNow.mapTo(HashSet()) { it.id }
            return library
                .filter {
                    it.effectiveStatus == WatchStatus.WATCHING &&
                        !outNowIds.contains(it.id) &&
                        it.resumePart != null
                }
                .sortedWith(
                    compareByDescending<Franchise> { it.continueBacklog }.then(franchiseTitleOrder),
                )
                .take(KEEP_WATCHING_LIMIT)
        }

    // =============================================================================================
    // MARK: - Derived: the Watching shelf
    // =============================================================================================

    /** The state that admits `f` to the shelf, or `null` (dormant: caught up with nothing dated). */
    fun shelfState(f: Franchise): ShelfState? = f.shelfState(now)

    /** The soonest dated future premiere among a franchise's announced parts. */
    fun nextPremiere(f: Franchise): Long? = f.nextPremiere(now)

    /**
     * Every Watching-status show with a live claim on your attention: new episode > backlog >
     * caught-up-airing > imminent premiere. Ties break most-actionable first — freshest drop,
     * biggest backlog, soonest airing, soonest premiere.
     */
    val watchingShelf: List<Franchise>
        get() = library
            .filter { it.effectiveStatus == WatchStatus.WATCHING }
            .mapNotNull { f -> shelfState(f)?.let { f to it } }
            .sortedWith { a, b ->
                if (a.second != b.second) {
                    a.second.order.compareTo(b.second.order)
                } else {
                    when (a.second) {
                        // The CALM sort keys, on purpose: these are ties inside one state, where an
                        // hour of catalogue lag cannot change the answer.
                        ShelfState.NEW_EPISODE ->
                            b.first.lastAiredSortKey.compareTo(a.first.lastAiredSortKey)
                        ShelfState.BACKLOG ->
                            b.first.continueBacklog.compareTo(a.first.continueBacklog)
                        ShelfState.AIRING_WAIT ->
                            a.first.nextAiringSortKey.compareTo(b.first.nextAiringSortKey)
                        ShelfState.PREMIERE_SOON ->
                            (nextPremiere(a.first) ?: Long.MAX_VALUE)
                                .compareTo(nextPremiere(b.first) ?: Long.MAX_VALUE)
                    }
                }
            }
            .map { it.first }

    // =============================================================================================
    // MARK: - Derived: the Schedule agenda
    // =============================================================================================

    /**
     * Identity of the current feed. Equal keys ⇒ identical [scheduleDays], so a screen can key its
     * own derivations on this instead of walking the feed again.
     */
    val scheduleFeedKey: ScheduleFeedKey get() = ScheduleFeedKey(libraryVersion, nowMinute)

    /** Not snapshot state: a cache must never be the reason a screen redraws. */
    private var scheduleCache: Pair<ScheduleFeedKey, List<ScheduleDay>>? = null

    /**
     * A week back through two weeks ahead, chronological, **one entry per dated episode**.
     *
     * Memoised. It used to be a bare computed property that `ScheduleView` read through a dozen of
     * its own computed properties — about thirty full rebuilds per body evaluation. The feed only
     * changes when the library changes or the minute turns, so that is the cache key.
     */
    val scheduleDays: List<ScheduleDay>
        get() {
            // Read the library BEFORE consulting the cache. Compose re-establishes a scope's reads
            // from scratch on every recomposition, so a cache hit that never touched `library`
            // would silently unsubscribe the screen from the one thing the feed is built from.
            // (Swift's Observation has the same shape; there the rebuild path happened to cover it.)
            val snapshot = library
            val key = scheduleFeedKey
            scheduleCache?.let { if (it.first == key) return it.second }
            val days = buildScheduleDays(snapshot)
            scheduleCache = key to days
            return days
        }

    /** Local noon of today — the anchor every day offset is measured from. */
    val scheduleTodayNoon: Long
        get() {
            val minute = nowMinute
            val p = Formatting.localParts(minute)
            // Noon, so day arithmetic and labels can never land on a DST seam: a ±1 h shift cannot
            // move noon out of its own day.
            return minute - (p.hour * Time.HOUR_MS + p.minute * Time.MINUTE_MS) + 12 * Time.HOUR_MS
        }

    private fun buildScheduleDays(library: List<Franchise>): List<ScheduleDay> {
        val now = nowMinute
        val noon = scheduleTodayNoon
        val todayKey = Formatting.localDayKey(noon)
        val buckets = HashMap<Int, MutableList<ScheduleEntry>>()

        // Written as a `library` walk rather than `airingFranchises` (which is releasing-only): an
        // announced season premiering inside the window has no releasing part and still belongs
        // here. The SHOW's status is the filter — `tracksAirings` keeps `planned` off the calendar.
        for (f in library) {
            if (!f.tracksAirings) continue
            // EVERY part, not only the releasing one: a season that premieres inside the window is
            // announced rather than releasing, and a finale that aired three days ago belongs to a
            // finished part. The window is the filter, not the part's status.
            for (part in f.parts) {
                for (a in part.scheduleAirings) {
                    // Bucketed by the calendar day the episode lives in, read in ITS source's own
                    // calendar: a TMDB drop is a date-only fact, and reading its synthesized instant
                    // locally filed it a day late east of UTC+7.
                    val offset = ((f.dayKey(a.at) - todayKey) / Time.DAY_MS).toInt()
                    if (offset < SCHEDULE_BACK || offset > SCHEDULE_AHEAD) continue
                    // A different rule from `passedAirings` on purpose: a date-only drop is out at
                    // some point on its day and the calendar cannot know when, so the WHOLE day
                    // counts — the row can be marked from the morning on.
                    val aired = if (f.timeAnchor.isDateOnly) offset <= 0 else a.at <= now
                    buckets.getOrPut(offset) { ArrayList() }
                        .add(ScheduleEntry(f, part, a.episode, a.at, aired))
                }
            }
        }

        val out = ArrayList<ScheduleDay>()
        for (offset in SCHEDULE_BACK..SCHEDULE_AHEAD) {
            val entries = buckets[offset]?.sortedWith(SCHEDULE_ENTRY_ORDER).orEmpty()
            // TODAY IS ALWAYS PRESENT, empty or not, and "today" always means day 0. With the empty
            // section skipped the feed opened on a future day, the "Today" button hid itself
            // (`selectedDay == landing` — by its own test you were already there), and a row's bare
            // clock read as tonight.
            if (offset != 0 && entries.isEmpty()) continue
            out.add(ScheduleDay(id = offset, noon = noon + offset * Time.DAY_MS, entries = entries))
        }
        return out
    }

    // =============================================================================================
    // MARK: - Derived: the Library crate
    // =============================================================================================

    /** One show, one shelf. First match wins. */
    fun libShelf(f: Franchise): LibShelf {
        if (f.effectiveStatus == WatchStatus.PLANNED) return LibShelf.PLANNED
        // The status is the user's own word for the show — it outranks every derived signal, so a
        // finished series they have marked Watching sits on Watching instead of being filed under
        // Finished while the context menu shows a tick next to Watching.
        if (f.effectiveStatus == WatchStatus.WATCHING) return LibShelf.WATCHING
        // Nothing to watch right now, but a next installment is announced — dated or TBA alike. A
        // day-dated installment whose date has passed has arrived (or slipped) and is not
        // "returning" any more, whatever the stale curated note says: Mushoku Tensei sat on this
        // shelf reading "Returns today" two months into its third season.
        val announced = f.upcoming?.let { it.isFutureInstallment && !it.hasArrived(now) } ?: false
        if (announced || nextPremiere(f) != null) return LibShelf.COMING_BACK
        return LibShelf.FINISHED
    }

    /**
     * The crate, in shelf order; empty shelves are omitted.
     *
     * **No filters** — the Library root is one collection, and All titles owns search and Arrange.
     */
    val libraryShelves: List<LibShelfSection>
        get() = LibShelf.entries.mapNotNull { shelf ->
            val arr = sortedForShelf(library.filter { libShelf(it) == shelf }, shelf)
            if (arr.isEmpty()) null else LibShelfSection(shelf, arr)
        }

    private fun sortedForShelf(arr: List<Franchise>, shelf: LibShelf): List<Franchise> = when (shelf) {
        // Recently-active first — the show you are living with floats to the top. The CATALOGUE's
        // field, deliberately: these shelves are calm, and an hour of lag is nothing on them.
        LibShelf.WATCHING -> arr.sortedWith(
            compareByDescending<Franchise> { it.lastAiredSortKey }.then(franchiseTitleOrder),
        )
        // Soonest return first; TBA and undated last. Ties break by date PRECISION — descending, so
        // a concrete month leads a bare year — then by title.
        LibShelf.COMING_BACK -> arr.sortedWith(
            Comparator<Franchise> { a, b ->
                val ak = comingBackSortKey(a)
                val bk = comingBackSortKey(b)
                if (ak.value != bk.value) ak.value.compareTo(bk.value)
                else bk.precision.compareTo(ak.precision)
            }.then(franchiseTitleOrder),
        )
        LibShelf.PLANNED, LibShelf.FINISHED -> arr.sortedWith(franchiseTitleOrder)
    }

    /**
     * Chronological key for the Coming back shelf: a dated premiere beats the curated release
     * window, and a genuinely unknown date sorts to the very end (never as 0, never as January of a
     * year nobody stated).
     */
    private fun comingBackSortKey(f: Franchise): ReleaseSortKey {
        val premiere = nextPremiere(f)
        if (premiere != null) {
            // Read in the franchise's own calendar — a TMDB premiere is a date, not an instant.
            val p = Formatting.localParts(premiere, f.timeAnchor)
            return ReleaseSortKey(p.y * 10000 + p.mo * 100 + p.d, ReleaseSortKey.DAY)
        }
        return f.upcoming?.releaseSortKey ?: ReleaseSortKey.LAST
    }

    // =============================================================================================
    // MARK: - Derived: surface phases
    // =============================================================================================

    /**
     * The phase for a root that renders the whole library.
     *
     * **Order matters**: cached content always wins over a failed refresh (the network never blanks
     * the library), and an empty account is never shown while a first load is still running.
     */
    val surfacePhase: SurfacePhase
        get() {
            if (library.isEmpty()) {
                if (loading) return SurfacePhase.Loading
                if (loadError) return SurfacePhase.ErrorNoCache
                return SurfacePhase.EmptyAccount
            }
            return SurfacePhase.Content(
                refreshing = isRefreshing,
                staleSince = staleSince(SyncCenter.DataClass.EXACT_AIRING),
                sectionFailed = loadError,
            )
        }

    /** A refresh over content the user can already see. */
    val isRefreshing: Boolean get() = loading && library.isNotEmpty()

    /** Content is on screen but the last refresh failed — a section notice, never a blanked frame. */
    val sectionFailed: Boolean get() = loadError && library.isNotEmpty()

    /**
     * The empty state to render when there is nothing to show.
     *
     * **`isOnline` — not the error — decides** between "you're offline" and "we couldn't reach the
     * server", because only the reachability monitor knows which sentence is true.
     */
    val emptyStateCopy: EmptyStateCopy
        get() = when (surfacePhase) {
            is SurfacePhase.ErrorNoCache ->
                if (SyncCenter.isOnline) EmptyStateCopy.serverNoCache else EmptyStateCopy.offlineNoData
            else -> EmptyStateCopy.emptyAccount
        }

    fun isStale(dataClass: SyncCenter.DataClass): Boolean = SyncCenter.isStale(dataClass, now)

    fun staleSince(dataClass: SyncCenter.DataClass): Long? = SyncCenter.staleSince(dataClass, now)

    /** Writes are always permitted; this only decides whether the user is told they are queued. */
    val writesAreOffline: Boolean get() = !SyncCenter.isOnline

    // =============================================================================================
    // MARK: - Commands: progress
    // =============================================================================================

    /** Mark the releasing part of a franchise caught up. */
    fun markCaughtUp(franchiseId: String) {
        val f = franchise(franchiseId) ?: return
        val part = f.releasingPart ?: return
        // Reached only through `releasingPart`, so the first clause is false today; it is kept
        // exactly as the shipped rule reads, so the milestone test and `releasingPart`'s contract
        // stay legible against one another.
        val milestone = !part.isReleasing && part.totalEpisodes > 0 &&
            part.airedEpisodes >= part.totalEpisodes
        // One haptic for the whole transaction.
        FeedbackCoordinator.fire(if (milestone) FeedbackToken.SUCCESS else FeedbackToken.COMMIT_MEDIUM)
        val prev = part.progress
        // Through the same ceiling `setProgress` uses: asserting a number the server would clamp
        // shows "caught up" against a server that disagrees, and the next launch silently reverts.
        val aired = minOf(part.airedEpisodes, part.progressCeiling)
        applyLocalProgress(franchiseId, part.mediaId, aired)

        // Preserve the ORIGINAL prev if a non-add undo for this franchise is already pending, so
        // repeated catch-ups still restore the true start. `count` is derived from the same prev the
        // undo restores, so the sentence and the rollback can never disagree — it was left at its
        // default of 1 once, and catching up six episodes confirmed "Episode 12 marked as watched".
        val cur = undo
        undo = if (cur != null && !cur.added && cur.franchiseId == franchiseId) {
            UndoState(
                mediaId = part.mediaId, franchiseId = franchiseId, prevProgress = cur.prevProgress,
                title = f.title, episode = aired, count = maxOf(1, aired - cur.prevProgress),
            )
        } else {
            UndoState(
                mediaId = part.mediaId, franchiseId = franchiseId, prevProgress = prev,
                title = f.title, episode = aired, count = maxOf(1, aired - prev),
            )
        }

        celebrate(franchiseId)
        scheduleUndoDismissal()
        sendProgress(franchiseId, part.mediaId, aired)
    }

    /**
     * Mark the next episode of the releasing (or resume) part watched, and **return** the undo
     * without presenting it — the card shows the result and presents the toast when its handoff
     * settles. `null` when there is nothing to write: a completed part yields no write and
     * therefore no toast.
     */
    fun markNext(
        franchiseId: String,
        mediaId: Int? = null,
        haptic: FeedbackToken = FeedbackToken.COMMIT_LIGHT,
    ): UndoState? {
        val f = franchise(franchiseId) ?: return null
        val chosen = mediaId?.let { id -> f.parts.firstOrNull { it.mediaId == id } }
        val part = chosen ?: f.currentPart ?: f.releasingPart ?: f.resumePart ?: return null
        val target = minOf(part.progress + 1, part.progressCeiling)
        if (target <= part.progress) return null
        FeedbackCoordinator.fire(haptic)
        val prev = part.progress
        applyLocalProgress(franchiseId, part.mediaId, target)
        sendProgress(franchiseId, part.mediaId, target)
        return UndoState(
            mediaId = part.mediaId, franchiseId = franchiseId, prevProgress = prev,
            title = f.title, episode = target,
        )
    }

    /**
     * Set explicit progress for a part — **the single choke point where every write is bounded**.
     *
     * An unbounded "+1" control otherwise walks progress off the end of a season: a 10-episode
     * season sat at 59/10 because every tap incremented and the progress ring clamped its *visual*
     * at 100 %, so the overrun was invisible.
     *
     * Mints no [UndoState]; callers that need one use [markThrough].
     */
    fun setProgress(franchiseId: String, mediaId: Int, episodes: Int, haptic: Boolean = true) {
        val part = franchise(franchiseId)?.parts?.firstOrNull { it.mediaId == mediaId }
        val clamped = minOf(maxOf(0, episodes), part?.progressCeiling ?: Int.MAX_VALUE)
        val prev = part?.progress
        // One watch fact is a light commit; a contiguous range is a firmer one.
        if (haptic) {
            val delta = abs(clamped - (prev ?: clamped))
            FeedbackCoordinator.fire(
                if (delta > 1) FeedbackToken.COMMIT_MEDIUM else FeedbackToken.COMMIT_LIGHT,
            )
        }
        applyLocalProgress(franchiseId, mediaId, clamped)
        sendProgress(franchiseId, mediaId, clamped)
    }

    /**
     * Move a part's progress to `episode` and present ONE undo that reports the real count and
     * restores the exact prior value.
     *
     * Three defects had to be fixed together to make this exist: `setProgress` created no undo at
     * all, so "Mark through episode N" — a multi-episode write, reached from a menu, with no
     * confirmation — was **unreversible**; `markCaughtUp` left the count at 1, so a six-episode
     * batch confirmed one; and `UndoState.undoAction` had no call site, which is also what blocked
     * a series-level "mark as watched" from ever being offered.
     *
     * One transaction, one haptic (fired inside [setProgress]), one toast, one restoring action —
     * captured here from the value read **before** the write, so undo cannot be re-derived (wrongly)
     * from state the write has already changed. It works downward too, which is how a season reset
     * is expressed.
     */
    fun markThrough(
        franchiseId: String,
        mediaId: Int,
        episode: Int,
        present: Boolean = true,
    ): UndoState? {
        val f = franchise(franchiseId) ?: return null
        val part = f.parts.firstOrNull { it.mediaId == mediaId } ?: return null
        val prev = part.progress
        val target = minOf(maxOf(0, episode), part.progressCeiling)
        if (target == prev) return null

        setProgress(franchiseId, mediaId, target)

        val state = UndoState(
            mediaId = mediaId, franchiseId = franchiseId, prevProgress = prev,
            title = f.title, episode = target, count = maxOf(1, abs(target - prev)),
            undoAction = { setProgress(franchiseId, mediaId, prev, haptic = false) },
        )
        if (present) presentUndo(state)
        return state
    }

    // =============================================================================================
    // MARK: - Commands: membership and status
    // =============================================================================================

    /**
     * Subscribe to a franchise. Optimistic through [pendingAdds], so the card flips to "In library"
     * instantly instead of waiting a network round-trip.
     *
     * **An add never raises the system permission prompt.** It used to: this call set the undo state
     * and the next line asked for notification permission, so a modal system dialog appeared over
     * the results with "Added … — Undo" counting down underneath it. The undo was unreachable for
     * its whole six-second window, screen-reader focus was stolen, and the app's first-ever
     * permission ask arrived unprimed in the middle of an unrelated action — where the reflex answer
     * is Deny, after which episode alerts are dead for that account. The ask belongs to an explicit
     * primer (armed by an add that *stuck*, raised only after the undo window closed) and to
     * Profile → Notifications.
     *
     * **Arming that primer is this method's job, and it is why [source] is a parameter.** It used to
     * be the Search screen's, wired into one `add` lambda — so Today's trending billboard, Detail's
     * toolbar `+` and the replay below all added shows and armed nothing, and a user who never
     * visited Search was never asked, had every alarm stood down by the denied default on API 33+,
     * and got no episode alert ever. See [armAlertPrimer].
     *
     * @param source null when it genuinely is not known (a subscribe restored from a previous
     *   launch, written before the intent carried one). Unknown never arms the primer: the gate
     *   asks for a *fact*, and "probably anime" is not one.
     */
    fun addToLibrary(
        franchiseId: String,
        title: String,
        isReleasing: Boolean,
        source: MediaSource?,
    ) {
        if (isInLibrary(franchiseId)) return
        FeedbackCoordinator.fire(FeedbackToken.SUCCESS)
        pendingAdds = pendingAdds + franchiseId
        val status = if (isReleasing) WatchStatus.WATCHING else WatchStatus.PLANNED
        // The copy table, never a local spelling: this line used to say "Plan to watch", a string
        // the table explicitly bans, in the one toast every first-time user reads.
        undo = UndoState(
            franchiseId = franchiseId,
            title = title,
            added = true,
            statusLabel = Copy.statusLabel(status.wire),
        )
        scheduleUndoDismissal()

        scope.launch {
            try {
                // The status the toast promised is the status that is sent.
                api.subscribe(franchiseId, status)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                val cur = undo
                if (cur != null && cur.added && cur.franchiseId == franchiseId) undo = null
                // Membership rolls back, and the failure goes where every other membership failure
                // goes: the SyncBanner, with a Retry that re-issues exactly this add. It was the
                // only write in the app that ended in a transient toast with no way back.
                pendingAdds = pendingAdds - franchiseId
                SyncCenter.record(
                    command = Copy.Action.add,
                    title = title,
                    reason = errors.reason(e),
                    intent = WriteIntent.Subscribe(
                        franchiseId = franchiseId,
                        title = title,
                        status = status.wire,
                        source = source?.wire.orEmpty(),
                    ),
                ) { addToLibrary(franchiseId, title, isReleasing, source) }
                return@launch
            }
            reload()
            // After the reload, so the flag never flickers off before the real row arrives. A
            // reload that fails does not throw — it swallows its own error — so this still runs.
            pendingAdds = pendingAdds - franchiseId
        }

        armAlertPrimer(franchiseId, isReleasing, source)
    }

    /**
     * Arm the notification primer, if this add is the kind that has anything to offer.
     *
     * Gated exactly as the Search screen's copy of this was: a **currently airing AniList** show
     * (TMDB air times are synthesised at 17:00 UTC, so a TV-only add buys the user nothing and asks
     * for nothing), on an ask that has not already been answered, after the add has STUCK.
     *
     * The wait is the whole undo window plus half a second, and it is not politeness. The system
     * dialog is never raised by an add: it used to arrive unprimed, over the trending grid, with
     * "Added … — Undo" counting down UNDERNEATH a modal the user could not dismiss without
     * answering. Nothing here raises a dialog either — it only makes the primer ROW eligible, on a
     * flag that is persisted, so an add on Today surfaces the ask on the next visit to Search.
     */
    private fun armAlertPrimer(franchiseId: String, isReleasing: Boolean, source: MediaSource?) {
        if (!isReleasing || source != MediaSource.ANILIST) return
        if (!NotificationPrimer.armable) return
        scope.launch {
            delay(SyncCenter.toastMillis + PRIMER_ARM_DELAY_MILLIS)
            // An undone add arms nothing.
            if (!isInLibrary(franchiseId)) return@launch
            NotificationPrimer.arm()
        }
    }

    /**
     * Move a show to another shelf.
     *
     * `present` draws the "Moved to Watching" toast with an Undo that puts it back. It is `false`
     * inside a multi-write transaction (a rewatch start, an undo's restore) so a transaction still
     * shows exactly one toast.
     */
    fun setStatus(
        franchiseId: String,
        status: WatchStatus,
        haptic: Boolean = true,
        present: Boolean = true,
    ) {
        if (haptic) FeedbackCoordinator.fire(FeedbackToken.SELECTION)
        val intent = WriteIntent.Status(franchiseId, status.wire)
        val moved = Copy.Toast.movedTo(Copy.statusLabel(status.wire))

        val idx = library.indexOfFirst { it.id == franchiseId }
        if (idx < 0) {
            // Not in the loaded library yet (a pending add). Nothing to roll back, but the failure
            // is still a failure: this was fire-and-forget, the only silent write in the app.
            scope.launch {
                try {
                    api.setStatus(franchiseId, status)
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Throwable) {
                    SyncCenter.record(
                        command = moved, title = "", reason = errors.reason(e), intent = intent,
                    ) { setStatus(franchiseId, status, haptic = false, present = false) }
                }
            }
            return
        }

        val prevStatus = library[idx].effectiveStatus
        // An unchanged status is a no-op: no write, no toast.
        if (prevStatus == status) return
        replaceFranchise(idx, library[idx].withStatus(status))
        val title = library[idx].title
        if (present) {
            presentUndo(
                UndoState(
                    franchiseId = franchiseId,
                    title = title,
                    customMessage = moved,
                    undoAction = {
                        setStatus(franchiseId, prevStatus, haptic = false, present = false)
                    },
                ),
            )
        }

        scope.launch {
            try {
                api.setStatus(franchiseId, status)
                syncAmbient()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                val i = library.indexOfFirst { it.id == franchiseId }
                if (i >= 0) replaceFranchise(i, library[i].withStatus(prevStatus))
                val cur = undo
                if (cur != null && cur.franchiseId == franchiseId && cur.customMessage != null) {
                    undo = null
                }
                SyncCenter.record(
                    command = moved, title = title, reason = errors.reason(e), intent = intent,
                ) { setStatus(franchiseId, status, haptic = false, present = false) }
            }
        }
    }

    /** `haptic = false` on the undo path, which has already fired its own selection tick. */
    fun removeFromLibrary(franchiseId: String, haptic: Boolean = true) {
        if (haptic) FeedbackCoordinator.fire(FeedbackToken.COMMIT_LIGHT)
        pendingAdds = pendingAdds - franchiseId
        val idx = library.indexOfFirst { it.id == franchiseId }.takeIf { it >= 0 }
        val removed = idx?.let { library[it] }
        // Drop any unconfirmed progress for this show — re-adding it later must not replay a write
        // against the fresh subscription.
        removed?.parts?.forEach { forgetLocalProgress(it.mediaId) }
        if (idx != null) library = library.filterIndexed { i, _ -> i != idx }

        scope.launch {
            try {
                api.unsubscribe(franchiseId)
                syncAmbient()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                if (removed != null && library.none { it.id == franchiseId }) {
                    val at = minOf(idx ?: library.size, library.size)
                    library = library.toMutableList().also { it.add(at, removed) }
                }
                SyncCenter.record(
                    command = Copy.Action.removeFromLibrary,
                    title = removed?.title.orEmpty(),
                    reason = errors.reason(e),
                    intent = WriteIntent.Unsubscribe(franchiseId, removed?.title.orEmpty()),
                ) { removeFromLibrary(franchiseId, haptic = false) }
            }
        }
    }

    /**
     * Remove a show, with Undo.
     *
     * **No confirmation dialog**: remove is reversible for 6 s (10 s under a screen reader) and
     * never touches watch history — the server deletes only the subscription row, so every progress
     * row survives and Undo brings the ticks back exactly. One haptic for the whole transaction,
     * fired inside [removeFromLibrary]. The toast is presented immediately: unlike a mark, a removal
     * has no handoff to wait for.
     */
    fun removeWithUndo(f: Franchise) {
        // `Franchise` is an immutable value, so this is the whole show — parts, progress and status
        // — frozen at the instant of the removal. That is what lets Undo restore before any network
        // round-trip.
        val snapshot = f.snapshotForUndo
        val previousStatus = f.effectiveStatus
        removeFromLibrary(f.id, haptic = true)
        presentUndo(
            UndoState(
                franchiseId = f.id,
                title = f.title,
                removed = true,
                removedFranchise = snapshot,
                prevStatus = previousStatus,
            ),
        )
    }

    // =============================================================================================
    // MARK: - Commands: undo
    // =============================================================================================

    /**
     * The single entry point for the toast's Undo button.
     *
     * Takes the state **by value** so a toast that is still on screen stays actionable even if
     * [undo] has already moved on.
     */
    fun undoTapped(state: UndoState) {
        val action = state.undoAction
        if (action != null) {
            undo = null
            FeedbackCoordinator.fire(FeedbackToken.SELECTION)
            action()
            return
        }
        if (state.removed) {
            restoreRemoved(state)
            return
        }
        performUndo()
    }

    /**
     * Put a removed show back exactly as it was — instantly, from the snapshot, before any network
     * round-trip. The re-subscribe carries the **previous** status, so a Watched show returns to the
     * Watched shelf rather than silently becoming Planned.
     */
    private fun restoreRemoved(state: UndoState) {
        val f = state.removedFranchise ?: return
        FeedbackCoordinator.fire(FeedbackToken.SELECTION)
        undo = null
        if (library.none { it.id == f.id }) library = library + f

        scope.launch {
            try {
                api.subscribe(f.id, state.prevStatus)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                // Membership is a fact about the account, so it rolls back; the failure is surfaced
                // once, in the SyncBanner, with a Retry that re-issues exactly this call.
                library = library.filterNot { it.id == f.id }
                // Deliberately NO WriteIntent: the restore needs the snapshot, which cannot be
                // encoded, so this row cannot be replayed after a relaunch and Discard is its only
                // exit. It must never be cleared as though it had succeeded.
                SyncCenter.record(
                    command = Copy.Action.add,
                    title = f.title,
                    reason = errors.reason(e),
                    intent = null,
                ) { undoTapped(state) }
                return@launch
            }
            reload()
        }
    }

    fun performUndo() {
        val u = undo ?: return
        FeedbackCoordinator.fire(FeedbackToken.SELECTION)
        val fid = u.franchiseId
        val mediaId = u.mediaId
        if (u.added && fid != null) {
            removeFromLibrary(fid, haptic = false)
        } else if (fid != null && mediaId != null && isInLibrary(fid)) {
            applyLocalProgress(fid, mediaId, u.prevProgress)
            unsettleCompletion(fid)
            justCaught = justCaught - fid
            // An undo is a progress write like any other: it rides the part's lane BEHIND the mark
            // it reverses, so the server can never end on the mark after the user took it back, and
            // a failure keeps the user's last word on screen with a Retry.
            sendProgress(fid, mediaId, u.prevProgress, command = Copy.Action.undo)
        }
        undo = null
        undoTask?.cancel()
    }

    // =============================================================================================
    // MARK: - Progress writes: one lane per part
    // =============================================================================================

    /**
     * Send a part's progress, serialised per part.
     *
     * Failure **keeps the mark** — a mark is a fact about the user — and files it in the SyncBanner
     * with a Retry that re-issues exactly this write, from this launch or the next.
     */
    private fun sendProgress(
        franchiseId: String,
        mediaId: Int,
        episodes: Int,
        command: String = Copy.Action.markAsWatched,
    ) {
        val title = franchise(franchiseId)?.title.orEmpty()
        progressLane.send(mediaId, ProgressWrite(franchiseId, episodes, command, title))
    }

    private suspend fun putProgress(write: ProgressWrite, mediaId: Int) {
        try {
            api.setProgress(mediaId, write.episodes)
            settleLocalProgress(mediaId, write.episodes)
        } catch (e: CancellationException) {
            // Teardown cancelled the lane. Structured concurrency requires the rethrow; the write
            // is simply not reported, which is the same outcome as iOS's `Task.isCancelled` guard.
            throw e
        } catch (e: Throwable) {
            // The doubled guard: the lane is gone, or a newer target is queued behind this one and
            // will decide the outcome — either way this attempt has nothing to report.
            if (!currentCoroutineContext().isActive) return
            if (progressLane.isQueued(mediaId)) return
            if (errors.isCancellation(e)) return
            SyncCenter.record(
                command = write.command,
                title = write.title,
                reason = errors.reason(e),
                intent = WriteIntent.Progress(write.franchiseId, mediaId, write.episodes),
            ) { putProgress(write, mediaId) }
        }
    }

    /**
     * Re-issue a write restored from a previous launch (`SyncCenter.replay`).
     *
     * Progress replays **straight to the server** — the local value it defends is already on screen
     * if the library still carries it. Membership and status replays go through the live commands,
     * so their optimistic state, rollback and toasts stay the app's one grammar.
     */
    suspend fun replay(intent: WriteIntent) {
        when (intent) {
            is WriteIntent.Progress -> putProgress(
                ProgressWrite(
                    franchiseId = intent.franchiseId,
                    episodes = intent.episodes,
                    command = Copy.Action.markAsWatched,
                    title = franchise(intent.franchiseId)?.title.orEmpty(),
                ),
                intent.mediaId,
            )

            is WriteIntent.Status ->
                WatchStatus.entries.firstOrNull { it.wire == intent.status }
                    ?.let { setStatus(intent.franchiseId, it, haptic = false, present = false) }

            is WriteIntent.Subscribe -> {
                val status = WatchStatus.entries.firstOrNull { it.wire == intent.status }
                    ?: WatchStatus.PLANNED
                addToLibrary(
                    franchiseId = intent.franchiseId,
                    title = intent.title,
                    isReleasing = status == WatchStatus.WATCHING,
                    // Null for a row restored from a launch that predates the field — see
                    // `addToLibrary`: unknown never arms the primer.
                    source = MediaSource.entries.firstOrNull { it.wire == intent.source },
                )
            }

            is WriteIntent.Unsubscribe -> removeFromLibrary(intent.franchiseId, haptic = false)
        }
    }

    // =============================================================================================
    // MARK: - The optimistic progress overlay
    // =============================================================================================

    private fun replaceFranchise(index: Int, value: Franchise) {
        library = library.toMutableList().also { it[index] = value }
    }

    /**
     * Rewrite a part's progress in the in-memory library so the UI updates instantly, and record the
     * write so it survives the two cases the library alone cannot express.
     */
    private fun applyLocalProgress(franchiseId: String, mediaId: Int, episodes: Int) {
        localProgress[mediaId] = LocalWrite(episodes = episodes, settledAtSeq = null)
        val fi = library.indexOfFirst { it.id == franchiseId }
        if (fi < 0) return
        library = library.toMutableList().also {
            it[fi] = it[fi].withUpdatedProgress(mediaId, episodes)
        }
        settleCompletion(franchiseId)
    }

    /** The shows THIS session moved to Watched by marking their last episode — Undo takes the move back too. */
    private val completedByMark = HashSet<String>()
    private var completionSweepDone = false

    /**
     * A finished series whose last episode has just been marked is filed under Watched (i4:
     * Thrones read "Watching ⌄" in the bar over "COMPLETE · Watched once"), the way AniList, MAL
     * and Trakt file it. A status write like any other: it rolls back on failure.
     */
    private fun settleCompletion(franchiseId: String) {
        val f = franchise(franchiseId) ?: return
        if (f.effectiveStatus != WatchStatus.WATCHING || !f.isWatchedThrough) return
        completedByMark.add(franchiseId)
        setStatus(franchiseId, WatchStatus.COMPLETED, haptic = false, present = false)
    }

    private fun unsettleCompletion(franchiseId: String) {
        if (!completedByMark.remove(franchiseId)) return
        val f = franchise(franchiseId) ?: return
        if (f.effectiveStatus != WatchStatus.COMPLETED || f.isWatchedThrough) return
        setStatus(franchiseId, WatchStatus.WATCHING, haptic = false, present = false)
    }

    /** Rows the server still files under Watching though everything is watched: moved once per session, quietly. */
    private fun settleCompletedSeries() {
        if (completionSweepDone) return
        completionSweepDone = true
        for (f in library) {
            if (f.effectiveStatus == WatchStatus.WATCHING && f.isWatchedThrough) {
                setStatus(f.id, WatchStatus.COMPLETED, haptic = false, present = false)
            }
        }
    }

    /**
     * The PUT for this part returned **successfully**; the overlay stops being unconditional from
     * here. The next snapshot fetched after this moment decides, so a value the server will not
     * accept (a clamp, a rejected write) cannot stay pinned for the rest of the session.
     *
     * Called only on success, which is exactly the "a mark never rolls back" rule expressed in the
     * reconciler: a **failed** write leaves `settledAtSeq == null`, so its overlay stays
     * unconditional until a snapshot agrees with it.
     */
    private fun settleLocalProgress(mediaId: Int, episodes: Int) {
        val write = localProgress[mediaId] ?: return
        // Superseded by a newer write for the same part: not this write's story to end.
        if (write.episodes != episodes) return
        localProgress[mediaId] = write.copy(settledAtSeq = reloadSeq)
    }

    /**
     * Forget an optimistic write with no replacement value — every part of a removed franchise, so
     * re-adding it later cannot replay a write against the fresh subscription. The next snapshot
     * then wins outright.
     */
    private fun forgetLocalProgress(mediaId: Int) {
        localProgress.remove(mediaId)
    }

    /**
     * Replay unconfirmed local writes over a freshly fetched library (`seq` = the [reloadSeq] of the
     * reload that fetched it).
     *
     * An entry retires when the server reports the same number — the write has landed and the
     * overlay would only pin a stale value from then on — **and** when this snapshot was fetched
     * after the write settled and still disagrees: the server had its say and said something else.
     * Without that second rule a value the server will not accept is re-applied on every reload
     * forever. Entries for franchises still missing from the snapshot (an add mid-flight) are kept
     * for the next one.
     */
    private fun reconcileLocalProgress(fetched: List<Franchise>, seq: Int): List<Franchise> {
        if (localProgress.isEmpty()) return fetched
        var result = fetched
        for ((mediaId, write) in localProgress.entries.toList()) {
            val fi = result.indexOfFirst { f -> f.parts.any { it.mediaId == mediaId } }
            if (fi < 0) continue
            val serverProgress = result[fi].parts.firstOrNull { it.mediaId == mediaId }?.progress
            val settledBeforeFetch = write.settledAtSeq?.let { seq > it } ?: false
            if (serverProgress == write.episodes || settledBeforeFetch) {
                localProgress.remove(mediaId)
            } else {
                result = result.toMutableList().also {
                    it[fi] = it[fi].withUpdatedProgress(mediaId, write.episodes)
                }
            }
        }
        return result
    }
}

// =================================================================================================
// MARK: - The model's own value types
// =================================================================================================

/*
 * Every value type below is annotated for the Compose compiler, for the same reason
 * `compose_stability.conf` names `com.anitrack.model.**`: an inferred-UNSTABLE parameter makes the
 * composable that takes it non-skippable, and the 20-second clock tick would then recompose every
 * row on every tab three times a minute. A `List` field is inferred unstable by default, so the
 * types that carry one say what they actually are.
 */

/**
 * The anime/TV scope. **Search only** — see `AppModel.mediaFilter`.
 *
 * The wire values match iOS's raw values so a persisted or logged scope reads the same on both
 * platforms; the chip's word comes from the copy table, never from the enum.
 */
enum class MediaFilter(val wire: String) {
    ALL("all"),
    ANIME("anime"),
    TV("tv"),
    ;

    val chipLabel: String
        get() = when (this) {
            ALL -> CopyFilter.all
            ANIME -> CopyFilter.anime
            TV -> CopyFilter.tv
        }
}

/**
 * A query the server was able to repair, and the words the user actually typed.
 *
 * Present **only when the two differ** — "showing results for X" that echoes X back is noise.
 */
@Immutable
data class SearchCorrection(val original: String, val corrected: String) {
    companion object {
        fun from(response: FranchiseListResponse): SearchCorrection? {
            val corrected = response.correctedQuery ?: return null
            val original = response.originalQuery ?: return null
            if (corrected.equals(original, ignoreCase = true)) return null
            return SearchCorrection(original = original, corrected = corrected)
        }
    }
}

/** One episode on the calendar: which show, which part, which episode, when. */
@Immutable
data class ScheduleEntry(
    val franchise: Franchise,
    val part: FranchisePart,
    val episode: Int,
    val at: Long,
    /**
     * It has happened: an exact instant that has passed, or a date-only release whose day is today
     * or earlier.
     */
    val aired: Boolean,
) {
    val id: String get() = "${franchise.id}/${part.mediaId}/$episode"

    val dateOnly: Boolean get() = franchise.timeAnchor.isDateOnly

    val watched: Boolean get() = aired && part.progress >= episode
}

/** Ascending by instant, then title, then episode. */
private val SCHEDULE_ENTRY_ORDER: Comparator<ScheduleEntry> =
    compareBy<ScheduleEntry>({ it.at }, { it.franchise.title }, { it.episode })

@Immutable
data class ScheduleDay(
    /** Day offset from today; negative for past days. */
    val id: Int,
    /** **Local noon** of the day, so day arithmetic and labels never land on a DST seam. */
    val noon: Long,
    val entries: List<ScheduleEntry>,
) {
    val isToday: Boolean get() = id == 0
    val isPast: Boolean get() = id < 0
}

/** Equal keys ⇒ identical `scheduleDays`. */
data class ScheduleFeedKey(val library: Int, val minute: Long)

/** Today's Now Bar fact — one global answer to "when". */
@Immutable
data class NowBarItem(
    val franchiseId: String,
    val state: State,
    /** The instant the bar is about: the drop ([State.LIVE]) or the next airing ([State.NEXT]). */
    val at: Long,
) {
    enum class State { LIVE, NEXT }
}

/**
 * The Library crate's four shelves — grouped by the show's relationship to your FUTURE, not by app
 * state: you're in it / it's coming back / you haven't started / it's over.
 *
 * **Declaration order is shelf order on screen.** Planned leads (the library is where you browse
 * what to start next — Today already fronts what you're watching), then Coming back, Watching, and
 * the Finished archive.
 *
 * Deliberately carries **no label**: the on-screen name lives in the Library's own facts layer, so a
 * second vocabulary ("Coming back" for the shelf the screen calls "Returning") cannot drift into
 * existence here.
 */
enum class LibShelf { PLANNED, COMING_BACK, WATCHING, FINISHED }

@Immutable
data class LibShelfSection(val shelf: LibShelf, val franchises: List<Franchise>)

/**
 * The five conditions every root can be in. Anything not in this type is not a state the app has a
 * treatment for.
 */
sealed interface SurfacePhase {

    /** No cache and a request in flight. Structural skeleton, delayed. */
    data object Loading : SurfacePhase

    /** The request settled and the account has no titles. First-run content, immediately. */
    data object EmptyAccount : SurfacePhase

    /** The request failed and there is nothing cached to show instead. */
    data object ErrorNoCache : SurfacePhase

    /** There is content. It may be refreshing, stale, or missing one section's refresh. */
    data class Content(
        val refreshing: Boolean,
        val staleSince: Long?,
        val sectionFailed: Boolean,
    ) : SurfacePhase

    val isContent: Boolean get() = this is Content
}
