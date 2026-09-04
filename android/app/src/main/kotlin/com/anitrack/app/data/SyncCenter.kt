package com.anitrack.app.data

import android.content.Context
import android.content.SharedPreferences
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.view.accessibility.AccessibilityManager
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.anitrack.app.design.FeedbackCoordinator
import com.anitrack.app.design.FeedbackToken
import com.anitrack.model.AniTrackJson
import com.anitrack.model.Time
import com.anitrack.model.copy.Copy
import com.anitrack.model.copy.CopyDates
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer

/*
 * # The trust layer
 *
 * How fresh the data is, whether the device can reach anything, and which of the user's writes the
 * server never accepted.
 *
 * Two rules it exists to enforce:
 *
 *  • a failure is **never invisible and never auto-dismisses** — it persists in [failedChanges]
 *    until it is retried or discarded, and survives a relaunch;
 *  • **"offline" and "the server is unreachable" are different sentences**, and which one the user
 *    reads is decided by [isOnline], never guessed from an error.
 *
 * A singleton, as on iOS: it is *stored* state that outlives any one screen and any one navigation
 * stack, and the whole point of it is that a failure recorded on Detail is still standing when the
 * user reaches Profile. `AppModel` owns the session; this owns the session's trust.
 */
object SyncCenter {

    // -----------------------------------------------------------------------------------------
    // MARK: - Data classes and their staleness thresholds
    // -----------------------------------------------------------------------------------------

    /** What kind of fact a stamp is about. Each ages at its own rate. */
    enum class DataClass(val threshold: Long) {
        /** AniList airing instants. Wrong within half an hour is wrong. */
        EXACT_AIRING(30 * Time.MINUTE_MS),

        /** TMDB date-only schedule. A day's worth of drift is invisible; six hours is the limit. */
        DATE_ONLY_SCHEDULE(6 * Time.HOUR_MS),

        /** Titles, artwork, season structure. Changes on the order of days. */
        CATALOGUE(24 * Time.HOUR_MS),
    }

    // -----------------------------------------------------------------------------------------
    // MARK: - Freshness
    // -----------------------------------------------------------------------------------------
    //
    // There is exactly ONE freshness stamp in this app and SyncCenter does not own it:
    // `AppModel.lastLoadedAt` does, and this reads it through an installed closure. A stored copy
    // is exactly what lets Profile's "Synced 2 min ago" and a screen's stale strip disagree, so
    // both properties below are deliberately computed.

    /** What the live model currently knows about freshness. Read through [signals], never stored. */
    @Immutable
    data class Signals(
        /** Epoch-ms of the last library payload that actually arrived. `0` = never. */
        val lastLoadedAt: Long = 0,
        /** A library request is in flight. */
        val loading: Boolean = false,
    )

    /**
     * Installed once, at the app root:
     * ```
     * SyncCenter.signals = { SyncCenter.Signals(appModel.lastLoadedAt, appModel.loading) }
     * ```
     * Until it is installed, nothing can be stale and Profile reads **"Not synced yet"** — the
     * honest reading of "this build has no freshness source wired", not a silent claim of freshness.
     *
     * Because the closure reads the model's own snapshot state, every composable that renders
     * [lastSyncedAt] / [checking] re-reads when the model's stamp moves.
     */
    var signals: (() -> Signals)? = null

    private val current: Signals get() = signals?.invoke() ?: Signals()

    /** When the last library payload actually arrived. `null` until the first successful load. */
    val lastSyncedAt: Long? get() = current.lastLoadedAt.takeIf { it > 0 }

    /** A refresh is in flight. Drives Profile's "Checking for changes" line. */
    val checking: Boolean get() = current.loading

    private var stamps: Map<DataClass, Long> by mutableStateOf(emptyMap())

    /**
     * Optional per-class refinement: a surface that refreshes ONE class of data on its own stamps
     * it here and that class stops inheriting the library-wide stamp. Nothing is required to call
     * this — every class falls back to [lastSyncedAt], so the stale strip works on a screen that
     * never stamps anything.
     */
    fun stamp(dataClass: DataClass, at: Long = System.currentTimeMillis()) {
        stamps = stamps + (dataClass to at)
    }

    /** Elapsed ms since this class of data last arrived, or `null` when it never has. */
    fun age(dataClass: DataClass, now: Long = System.currentTimeMillis()): Long? {
        val at = stamps[dataClass] ?: lastSyncedAt ?: return null
        return maxOf(0L, now - at)
    }

    /**
     * Past the class threshold. **Never true before the first successful load**: a page that has
     * never loaded is not stale, it is loading. Artwork failures never reach here, so a failed
     * poster can never mark a page stale.
     */
    fun isStale(dataClass: DataClass, now: Long = System.currentTimeMillis()): Boolean {
        val age = age(dataClass, now) ?: return false
        return age >= dataClass.threshold
    }

    /** The timestamp the stale strip renders, or `null` when nothing is stale. */
    fun staleSince(dataClass: DataClass, now: Long = System.currentTimeMillis()): Long? {
        if (!isStale(dataClass, now)) return null
        return stamps[dataClass] ?: lastSyncedAt
    }

    /**
     * Profile's account line, in precedence order: a real failure outranks a stale stamp, and a
     * check in flight outranks a calm one.
     *
     * [dates] is the copy table's five-fact seam onto the time layer. It is a parameter rather than
     * a field because `Formatting` has to be injected on Android (only a `Context` can answer the
     * system 24-hour toggle), and the trust layer has no business holding one.
     */
    fun syncedLine(now: Long = System.currentTimeMillis(), dates: CopyDates): String {
        if (failedChanges.isNotEmpty()) return Copy.Toast.syncFailed(failedChanges.size)
        if (checking) return Copy.State.checkingForChanges
        val at = lastSyncedAt
            ?: return if (isOnline) Copy.State.neverSynced else Copy.State.couldNotCheck
        return Copy.synced(at, now, dates)
    }

    // -----------------------------------------------------------------------------------------
    // MARK: - Reachability and the screen reader
    // -----------------------------------------------------------------------------------------

    /**
     * The device believes it has a path to the network.
     *
     * Optimistic by default, and it stays optimistic in one more place than the research note
     * proposed: **a default network that never reports `NET_CAPABILITY_VALIDATED` still reads as
     * online.** That is the port of `NWPathMonitor`'s `.satisfied`, which asks whether a usable
     * route exists and not whether the internet answered, and it follows the ruling this property
     * carries on iOS: *"a captive portal can report `true` while every request fails — accepted:
     * claiming the user is offline when they are not is the worse lie, and the server-side copy is
     * the honest fallback."* Requiring validation would invert exactly that trade.
     */
    var isOnline: Boolean by mutableStateOf(true)
        private set

    /**
     * TalkBack (or any touch-exploration service) is running. The Android reading of
     * `UIAccessibility.isVoiceOverRunning`, and the only thing [toastSeconds] depends on.
     */
    var screenReaderActive: Boolean by mutableStateOf(false)
        private set

    private var monitoring = false
    private var connectivity: ConnectivityManager? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private var accessibility: AccessibilityManager? = null
    private var touchExplorationListener: AccessibilityManager.TouchExplorationStateChangeListener? = null

    /**
     * The networks the framework currently says are up. [isOnline] is derived from whether this is
     * EMPTY — **never from a bare `onLost`.**
     *
     * On a Wi-Fi → cellular handoff the default-network callback reports `onAvailable(cellular)`
     * and only *then* `onLost(wifi)`, so flipping the flag off on any loss dropped the app offline
     * for the length of every handoff: long enough to paint "You're offline" over a library that
     * was seconds from arriving, and to file the write in flight as a failure the user has to
     * retry by hand. The set cannot be fooled by the order the two events arrive in.
     *
     * Only ever touched on the main dispatcher — every callback arrives on a binder thread and
     * goes through [post], and the seeding read runs on the main thread before registration — so a
     * plain `HashSet` is enough.
     */
    private val availableNetworks = HashSet<Network>()

    /**
     * Started once, from the app's root, and stopped in [teardown]. Cheap, but not free — it is not
     * started when the object is first touched.
     *
     * Idempotent. Registers both live signals the trust layer needs, because both are "what the
     * device is doing to us" and both must be released together on sign-out.
     */
    fun startMonitoring(context: Context) {
        if (monitoring) return
        monitoring = true
        val app = context.applicationContext

        val cm = app.getSystemService(ConnectivityManager::class.java)
        connectivity = cm
        if (cm != null) {
            val cb = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) = post {
                    availableNetworks += network
                    isOnline = true
                }

                override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) {
                    // Only ever an upgrade. See [isOnline] for why validation is not required.
                    if (caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) {
                        post {
                            availableNetworks += network
                            isOnline = true
                        }
                    }
                }

                override fun onLost(network: Network) = post {
                    // This network, not the connection: see [availableNetworks] for the handoff
                    // this asymmetry exists to survive.
                    availableNetworks -= network
                    isOnline = availableNetworks.isNotEmpty()
                }

                override fun onUnavailable() = post {
                    // "The network that was asked for never materialised" — which says nothing
                    // about the ones already up, so it can only ever confirm an empty set.
                    isOnline = availableNetworks.isNotEmpty()
                }
            }
            networkCallback = cb
            // Both reads need ACCESS_NETWORK_STATE (declared in the app manifest) and both are
            // guarded together: `getActiveNetwork` is `@RequiresPermission` exactly as the
            // registration is, and guarding only the registration left the *seeding* read as the
            // one line that could take the app root down.
            //
            // Seeded synchronously, because `registerDefaultNetworkCallback` delivers nothing at
            // all when there is no default network — the optimistic default would then claim a
            // plane is online for the whole session.
            runCatching {
                cm.activeNetwork?.let { availableNetworks += it }
                isOnline = availableNetworks.isNotEmpty()
                cm.registerDefaultNetworkCallback(cb)
            }
        }

        val am = app.getSystemService(AccessibilityManager::class.java)
        accessibility = am
        if (am != null) {
            screenReaderActive = am.isTouchExplorationEnabled
            val listener = AccessibilityManager.TouchExplorationStateChangeListener { enabled ->
                post { screenReaderActive = enabled }
            }
            touchExplorationListener = listener
            am.addTouchExplorationStateChangeListener(listener)
        }
    }

    /** Idempotent. */
    fun stopMonitoring() {
        if (!monitoring) return
        monitoring = false
        networkCallback?.let { cb -> runCatching { connectivity?.unregisterNetworkCallback(cb) } }
        networkCallback = null
        connectivity = null
        // Nothing is watching these any more, so a stale membership must not decide [isOnline] the
        // next time monitoring starts — the seeding read does.
        availableNetworks.clear()
        touchExplorationListener?.let { accessibility?.removeTouchExplorationStateChangeListener(it) }
        touchExplorationListener = null
        accessibility = null
    }

    // -----------------------------------------------------------------------------------------
    // MARK: - Toast lifetimes
    // -----------------------------------------------------------------------------------------

    /**
     * 6 s, or 10 s while a screen reader runs — **an Undo the user cannot reach in time is not an
     * Undo.**
     *
     * This lives here because this is the only object that knows whether a screen reader is
     * running, and it is read by the live timer rather than merely declared: on iOS the constant
     * existed, was documented, and was never called, while the sleep beside it used a hard-coded 6.
     */
    val toastMillis: Long get() = if (screenReaderActive) 10_000L else 6_000L

    /** The error toast carries no action, so it is shorter — but still readable aloud in time. */
    val errorMillis: Long get() = if (screenReaderActive) 8_000L else 4_000L

    // -----------------------------------------------------------------------------------------
    // MARK: - Failed writes
    // -----------------------------------------------------------------------------------------

    var failedChanges: List<FailedChange> by mutableStateOf(emptyList())
        private set

    /**
     * At least one failed change has something Retry can actually run. A banner or a Profile row
     * whose Retry would be a no-op must not draw the button at all.
     */
    val canRetryAny: Boolean get() = failedChanges.any { it.canRetry() }

    /**
     * Replays a restored change's [WriteIntent] — the write itself, re-issued, not a reload that
     * would only confirm the server never got it. Installed by the model in `start()`, dropped in
     * [teardown] so nothing restored can replay into the account that follows this one.
     */
    var replay: (suspend (WriteIntent) -> Unit)? = null

    /**
     * Profile lists every failed change with its reason, Retry and Discard, so the global banner
     * would be a duplicate of the screen the user is already reading.
     */
    var profileIsOpen: Boolean by mutableStateOf(false)

    /**
     * Keys the user has explicitly retried, and when. A re-record inside [DIRECT_ERROR_WINDOW_MS]
     * is a *directly* failed action and earns one error haptic; an automatic failure is silent.
     */
    private val userRetriedAt = HashMap<String, Long>()
    private const val DIRECT_ERROR_WINDOW_MS = 30_000L

    /** Attempts per key, kept across the optimistic removal a retry performs. */
    private val attempts = HashMap<String, Int>()

    /** Set while a [retryAll] batch is in flight, so the batch fires one error haptic, not N. */
    private var batchRetryToken: String? = null
    private var batchErrorFired = false

    /**
     * Records a write the server never accepted. Called by every mutation's `catch`.
     *
     * The local value is **not** rolled back for progress writes — the mark is a fact about the
     * user. See `WritePolicy.kt` for the rule and its asymmetry.
     */
    fun record(
        command: String,
        title: String,
        reason: String,
        intent: WriteIntent? = null,
        retry: (suspend () -> Unit)?,
    ) {
        val key = FailedChange.key(command, title)
        val now = System.currentTimeMillis()
        val attempt = (attempts[key] ?: 0) + 1
        attempts[key] = attempt

        // One row per (command, title): a repeatedly failing write is one problem, not a list.
        val existing = failedChanges.firstOrNull { it.key == key }
        failedChanges = if (existing != null) {
            failedChanges.map { row ->
                if (row.key != key) row
                else row.updated(
                    reason = reason,
                    at = now,
                    attemptCount = attempt,
                    // `?: existing` so a replay-only row restored from a previous launch keeps the
                    // intent that is its only way back.
                    intent = intent ?: row.intent,
                )
            }
        } else {
            failedChanges + FailedChange(
                id = UUID.randomUUID().toString(),
                command = command,
                title = title,
                reason = reason,
                at = now,
                attemptCount = attempt,
                intent = intent,
                retry = retry,
            )
        }

        // Exactly one error haptic, and only when the user asked for this attempt themselves.
        // Inside a `retryAll()` batch that is one haptic for the whole batch, not one per row.
        val asked = userRetriedAt[key]
        if (asked != null && now - asked <= DIRECT_ERROR_WINDOW_MS) {
            userRetriedAt.remove(key)
            if (batchRetryToken == null) {
                FeedbackCoordinator.fire(FeedbackToken.DIRECT_ERROR)
            } else if (!batchErrorFired) {
                batchErrorFired = true
                FeedbackCoordinator.fire(FeedbackToken.DIRECT_ERROR)
            }
        }
        persist()
    }

    fun discard(id: String) {
        failedChanges.firstOrNull { it.id == id }?.let { change ->
            attempts.remove(change.key)
            userRetriedAt.remove(change.key)
        }
        failedChanges = failedChanges.filterNot { it.id == id }
        persist()
    }

    fun discardAll() {
        failedChanges = emptyList()
        attempts.clear()
        userRetriedAt.clear()
        persist()
    }

    /**
     * Retries one change. The row leaves immediately — the write is optimistic again — and the
     * command re-records itself if it fails, which is what fires the single error haptic.
     *
     * **A row is never cleared when there is nothing to run.** A restored change has no encoded
     * closure, and with no `replay` installed the only honest behaviour is to leave the failure
     * standing: clearing it would delete the record, persist an empty list and let [syncedLine]
     * report "Everything synced" for a write that was never sent.
     */
    fun retry(id: String) {
        val change = failedChanges.firstOrNull { it.id == id } ?: return
        val run = change.effectiveRetry() ?: return
        val key = change.key
        userRetriedAt[key] = System.currentTimeMillis()
        failedChanges = failedChanges.filterNot { it.id == id }
        persist()
        scope.launch { runRetry(change, run) }
    }

    /**
     * One Retry press is one transaction: the whole batch earns at most one error haptic, however
     * many of its writes fail again and however far apart they land. Only rows with a runnable
     * retry leave the banner.
     */
    fun retryAll() {
        val runnable = failedChanges.mapNotNull { change ->
            change.effectiveRetry()?.let { change to it }
        }
        if (runnable.isEmpty()) return

        val now = System.currentTimeMillis()
        for ((change, _) in runnable) userRetriedAt[change.key] = now
        val ids = runnable.mapTo(HashSet()) { it.first.id }
        failedChanges = failedChanges.filterNot { it.id in ids }
        persist()

        val token = UUID.randomUUID().toString()
        batchRetryToken = token
        batchErrorFired = false
        scope.launch {
            try {
                // One throwing row must not carry off the rest of the batch: every other row has
                // already left [failedChanges], so an abort here would erase writes the server
                // never accepted and nothing would ever put them back.
                for ((change, run) in runnable) runRetry(change, run)
            } finally {
                // In a `finally` because this token is what decides whether the NEXT failure fires
                // its haptic. Left standing, every later single retry took the batch path, found
                // `batchErrorFired` already true, and the app stopped answering a failed retry at
                // all for the life of the process.
                if (batchRetryToken == token) batchRetryToken = null
            }
        }
    }

    /**
     * Runs one retry and settles its bookkeeping **whatever the closure does** — the point of the
     * `finally`.
     *
     * Without it a throwing closure left [userRetriedAt] stamped, so the next unrelated background
     * failure on that key inside the 30-second window was read as something the user had just
     * asked for and buzzed at them, and [attempts] kept counting up across a failure that was no
     * longer standing ("4th attempt" on a first try).
     *
     * A throw that reaches here escaped the command's own `catch`, which means the command did NOT
     * re-record itself — so the row goes back. **A failure the user cannot see is a failure the
     * user cannot recover**, and this row has already been persisted away.
     */
    private suspend fun runRetry(change: FailedChange, run: suspend () -> Unit) {
        try {
            run()
        } catch (cancellation: CancellationException) {
            // Not a failure, and never re-filed: on the way out of a torn-down session, re-adding
            // a row is how the *next* account inherits this one's writes. It leaves by the normal
            // route, untouched.
            throw cancellation
        } catch (_: Throwable) {
            reinstate(change)
        } finally {
            settleRetry(change.key)
        }
    }

    /** Puts a row back after a retry that could not report its own failure. Never duplicates. */
    private fun reinstate(change: FailedChange) {
        if (failedChanges.any { it.key == change.key }) return
        failedChanges = failedChanges + change
        persist()
    }

    /**
     * A retried write finished. If it failed it already re-recorded itself — [record] runs
     * synchronously inside the command's `catch`, consuming the stamp and firing the single error
     * haptic — *so by the time this runs the stamp means "the retry SUCCEEDED".*
     *
     * The 30-second window is a safety net for a write that fails a moment after the tap, never a
     * licence to treat the next unrelated background failure on the same key as something the user
     * asked for.
     */
    private fun settleRetry(key: String) {
        userRetriedAt.remove(key)
        // The attempt counter belongs to a standing failure. With no row left, a later unrelated
        // failure must read "1st attempt", not inherit this key's history for the whole session.
        if (failedChanges.none { it.key == key }) attempts.remove(key)
    }

    // -----------------------------------------------------------------------------------------
    // MARK: - Persistence
    // -----------------------------------------------------------------------------------------
    //
    // `SharedPreferences`, not DataStore, and deliberately: `restore()` has to be SYNCHRONOUS. It
    // runs before the first frame, and a failure the user is still owed must be on screen when the
    // banner first composes rather than arriving one collection later. `SharedPreferences` is the
    // exact analogue of iOS's `UserDefaults` here — a synchronous read, an asynchronous commit.

    private const val STORE_KEY = "previously.sync.failedChanges"
    private const val PREFS_NAME = "previously.sync"

    private var prefs: SharedPreferences? = null

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    /**
     * Rehydrate the standing failures. Call once, from the app root, before the first composition.
     * Until it is called nothing persists and nothing is restored — which is correct for a preview
     * or a unit test, and wrong for the app, so the root must not forget it.
     */
    fun install(context: Context) {
        if (prefs != null) return
        prefs = context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        restore()
    }

    @Serializable
    private data class StoredChange(
        val id: String,
        val command: String,
        val title: String,
        val reason: String,
        val at: Long,
        val attemptCount: Int,
        val intent: WriteIntent? = null,
    )

    private fun persist() {
        val store = prefs ?: return
        val rows = failedChanges.map {
            StoredChange(it.id, it.command, it.title, it.reason, it.at, it.attemptCount, it.intent)
        }
        val json = runCatching {
            AniTrackJson.encodeToString(ListSerializer(StoredChange.serializer()), rows)
        }.getOrNull() ?: return
        store.edit().putString(STORE_KEY, json).apply()
    }

    private fun restore() {
        val json = prefs?.getString(STORE_KEY, null) ?: return
        val rows = runCatching {
            AniTrackJson.decodeFromString(ListSerializer(StoredChange.serializer()), json)
        }.getOrNull() ?: return
        // `retry = null`: the closure could not be encoded, so a restored row depends entirely on
        // its `intent` and on `replay` being installed.
        failedChanges = rows.map {
            FailedChange(
                id = it.id,
                command = it.command,
                title = it.title,
                reason = it.reason,
                at = it.at,
                attemptCount = it.attemptCount,
                intent = it.intent,
                retry = null,
            )
        }
    }

    /**
     * Sign-out: the next account must not inherit this one's failures — a Retry there would send
     * the previous user's mark into the new user's library.
     *
     * [signals] is deliberately **kept**: it is the wiring, not session data, and the root
     * re-installs it on the next sign-in either way. `lastSyncedAt` and `checking` are not cleared
     * because they are not stored here.
     */
    fun teardown() {
        failedChanges = emptyList()
        stamps = emptyMap()
        attempts.clear()
        userRetriedAt.clear()
        batchRetryToken = null
        batchErrorFired = false
        stopMonitoring()
        replay = null
        profileIsOpen = false
        persist()
    }

    private inline fun post(crossinline block: () -> Unit) {
        scope.launch { block() }
    }
}

/**
 * One write the server never accepted.
 *
 * [command] is a `Copy.Action` string and [reason] a `Copy.Notice` string — **never a status code**.
 *
 * Not a `data class`: [retry] is a lambda, and a generated `equals` comparing it would make every
 * row unequal to itself and re-run the banner's transition on any unrelated state change. Equality
 * is over the fields a reader can actually see change.
 */
@Stable
class FailedChange(
    val id: String,
    val command: String,
    val title: String,
    val reason: String,
    val at: Long,
    val attemptCount: Int,
    /** The write itself, when it can be expressed — what a restored row retries with. */
    val intent: WriteIntent?,
    /** `null` for a change restored from a previous launch: the closure could not be encoded. */
    val retry: (suspend () -> Unit)?,
) {

    /** Identity for de-duplication: the same command on the same title is one problem. */
    val key: String get() = key(command, title)

    internal fun updated(reason: String, at: Long, attemptCount: Int, intent: WriteIntent?) =
        FailedChange(id, command, title, reason, at, attemptCount, intent, retry)

    /**
     * The retry to actually run — the recorded closure, or the model replaying the stored intent
     * for a restored row.
     *
     * `null` when there is nothing to run: **a missing retry must never be mistaken for a
     * successful one**, so there is deliberately no empty-lambda fallback here.
     */
    fun effectiveRetry(): (suspend () -> Unit)? {
        retry?.let { return it }
        val intent = intent ?: return null
        val replay = SyncCenter.replay ?: return null
        return { replay(intent) }
    }

    /**
     * Whether Retry can do anything for this row. A row with no runnable retry keeps its place in
     * the banner; Profile shows Discard as the only way out until `replay` is installed.
     */
    fun canRetry(): Boolean = effectiveRetry() != null

    override fun equals(other: Any?): Boolean =
        other is FailedChange && other.id == id && other.reason == reason &&
            other.at == at && other.attemptCount == attemptCount && other.intent == intent

    override fun hashCode(): Int {
        var h = id.hashCode()
        h = 31 * h + reason.hashCode()
        h = 31 * h + at.hashCode()
        h = 31 * h + attemptCount
        h = 31 * h + (intent?.hashCode() ?: 0)
        return h
    }

    companion object {
        /** U+001F UNIT SEPARATOR: a character no command or title can contain. */
        fun key(command: String, title: String): String = "$command\u001F$title"
    }
}
