package com.anitrack.app.data

import androidx.compose.runtime.Stable
import com.anitrack.model.Franchise
import com.anitrack.model.FranchiseListResponse
import com.anitrack.model.FranchiseSummary
import com.anitrack.model.LibraryResponse
import com.anitrack.model.OpenedResponse
import com.anitrack.model.Subscription
import com.anitrack.model.WatchStatus
import com.anitrack.model.copy.Copy
import com.anitrack.model.copy.CopyLibrary
import com.anitrack.model.withProgress
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.io.IOException
import java.util.UUID

/*
 * # The write policy
 *
 * The value types, the per-part write lane and the four seams every mutation runs through. The
 * commands themselves live on `AppModel`, because they mutate its state; what lives here is the
 * part of the policy that is *not* about any one screen, and can therefore be read — and tested —
 * on its own.
 *
 * ## The two rules, and why they are not symmetric
 *
 * > **A progress mark never rolls back.** A failed progress write keeps the local value and files
 * > the failure in [SyncCenter] with a Retry. *"A mark is a fact about the user."* There is no red
 * > "couldn't save" toast and no rollback on this path.
 * >
 * > **Membership and status writes always roll back.** Add, remove and status changes are facts
 * > about the *account*; on failure the optimistic change is reverted and the failure goes to the
 * > SyncBanner with a Retry that re-issues exactly that call.
 *
 * The asymmetry is written down because it was once absent: the progress path *used* to roll back
 * and flash a red toast, so the tick a user drew on an episode row survived a bad connection while
 * the batch they confirmed above it vanished — two answers to one failure, on one screen.
 *
 * ## One lane per part
 *
 * [ProgressLane] is the whole of "one PUT in flight per part, newest-wins, superseded-dropped".
 * Every mark used to spawn a bare coroutine, so marking 12 then 13 quickly raced two PUTs: when
 * 13's answer landed first and 12's landed last, the server ended on 12 and the next reload walked
 * the tick back.
 */

// ---------------------------------------------------------------------------------------------
// MARK: - Seams
// ---------------------------------------------------------------------------------------------

/**
 * The endpoints `AppModel` calls, and nothing else.
 *
 * A **narrow port interface**, not the transport: the networking layer owns the client, its retry
 * budget, its token refresh and its error taxonomy, and adapts to this. Declaring the seam here
 * rather than importing the client keeps the model testable with no OkHttp on the classpath, and
 * keeps this file honest about exactly how much of the API the brain actually touches — eight
 * calls out of twelve.
 *
 * Every method suspends and either returns or throws. **`markOpened` is the one call in the app
 * that is not idempotent** (`POST /me/opened` returns the *previous* `lastOpenedAt` and then stamps
 * now, so a replay would return "now" and destroy "since you were last here") — it is deliberately
 * never retried or replayed.
 */
interface AniTrackApi {

    /** `GET /me/library`. */
    suspend fun library(): LibraryResponse

    /** `POST /me/opened` — returns the value from *before* this call. Never retried. */
    suspend fun markOpened(): OpenedResponse

    /** `GET /search?q=…[&exact=1]`. */
    suspend fun search(query: String, exact: Boolean): FranchiseListResponse

    /** `GET /franchises/trending?limit={n}`. */
    suspend fun trending(limit: Int): List<FranchiseSummary>

    /** `PUT /me/progress` — an **absolute** episode count, never a delta, so a replay is a no-op. */
    suspend fun setProgress(mediaId: Int, episodes: Int)

    /**
     * `POST /me/subscriptions`. The status is always stated: letting the server re-derive it from
     * `null` meant the toast could name one shelf and the show land on another.
     */
    suspend fun subscribe(franchiseId: String, status: WatchStatus?)

    /** `PATCH /me/subscriptions/{franchiseId}`. */
    suspend fun setStatus(franchiseId: String, status: WatchStatus)

    /** `DELETE /me/subscriptions/{franchiseId}`. */
    suspend fun unsubscribe(franchiseId: String)
}

/**
 * The three questions the model asks about a thrown error. The networking layer owns the exception
 * taxonomy; this is the whole of what the brain needs from it, and it is a **required** constructor
 * argument on `AppModel` precisely so nobody can forget to wire the real one — a client whose 401
 * answered [isUnauthorized] with `false` would render "couldn't load your library" over a dead
 * session forever, and no amount of retrying could fix it.
 *
 * [DefaultApiErrorTaxonomy] is the no-client implementation: correct for transport failures,
 * deliberately blind to HTTP status. Use it in tests, never in the app.
 */
interface ApiErrorTaxonomy {

    /**
     * **A cancelled request is not a failure.** A superseded reload, a keystroke that cancelled the
     * search behind it, a pull-to-refresh whose screen left — none of them may raise a "couldn't
     * refresh" footnote over good content.
     *
     * Note the semantics differ from Swift's: there, cancellation is *swallowed* at the consumer;
     * in Kotlin, structured concurrency requires the [CancellationException] to be rethrown and it
     * is the UI side-effect that is suppressed. Both call sites here do exactly that.
     */
    fun isCancellation(error: Throwable): Boolean = DefaultApiErrorTaxonomy.isCancellation(error)

    /**
     * The session is gone. **Exactly one code path in the whole client ends a session**, and this
     * is what tells it apart from every other failure: a 403, an HTML body at any status, and an
     * inability to *mint* a token are all ordinary failures that keep the session.
     */
    fun isUnauthorized(error: Throwable): Boolean = false

    /**
     * The reason a write failed, in the user's words — a `Copy.Notice` string, never a status code
     * and never a raw exception message.
     */
    fun reason(error: Throwable): String = Copy.Notice.reason(error)
}

/** See [ApiErrorTaxonomy]. Transport-accurate, HTTP-blind; for tests. */
object DefaultApiErrorTaxonomy : ApiErrorTaxonomy {

    /**
     * Two shapes, and only two.
     *
     * A bare [CancellationException] anywhere down the cause chain is cancellation. OkHttp's own
     * cancel signal is an [IOException] whose message is exactly `"Canceled"` — matched by that
     * message rather than by type, because the type it arrives as
     * (`InterruptedIOException`/`SocketException`) is shared with genuine timeouts and resets,
     * which must keep reading "Took too long" / "No connection". A timeout is not a cancellation.
     */
    override fun isCancellation(error: Throwable): Boolean {
        var e: Throwable? = error
        var hops = 0
        while (e != null && hops < 16) {
            if (e is CancellationException) return true
            if (e is IOException && e.message == "Canceled") return true
            e = e.cause
            hops++
        }
        return false
    }
}

/**
 * The ambient surfaces a confirmed server-side change has to be pushed into: scheduled episode
 * notifications, and (where the platform has one) the airing live update.
 *
 * A seam because those layers land separately and the model must not import them. It is called
 * after a successful `reload()`, after a successful `setStatus`, after a successful
 * `removeFromLibrary`, and from `alertsWereAllowed()` — *"they used to wait for the next reload, so
 * 'Turn on' granted permission and scheduled nothing, and the first alert could be a day away."*
 */
interface AmbientSync {

    /**
     * Re-arm everything from the library as it now stands.
     *
     * **It must not throw.** It is awaited inside the successful branch of `reload()`, so an
     * exception escaping here would be caught as a *library* failure and paint "couldn't refresh"
     * over a library that had just arrived intact. An alarm that could not be scheduled is the
     * notification layer's problem to report, not the library's.
     */
    suspend fun sync(library: List<Franchise>, now: Long)

    /** Sign-out: nothing armed by this account may survive it. */
    fun cancelAll()
}

/** The do-nothing ambient layer — the shape of the app before notifications are wired. */
object NoAmbientSync : AmbientSync {
    override suspend fun sync(library: List<Franchise>, now: Long) = Unit
    override fun cancelAll() = Unit
}

/**
 * Process-lifetime state owned by *other* layers that nonetheless belongs to the signed-in account,
 * and must therefore be dropped on sign-out.
 *
 * There is exactly one such thing today — the design system's season-sweep ledger, which remembers
 * which milestone commits have already been drawn so a sweep never replays on a scroll back. *"The
 * next account's first season completion is its own, not a token this one already spent."* It lives
 * in the design layer, so `AppModel.teardown()` reaches it through this registry rather than
 * reaching up into a layer it must not depend on.
 *
 * Registration is idempotent by identity, and the registry is deliberately **not** cleared by
 * [runAll]: these are hooks, not session data.
 */
object SessionResets {

    private val hooks = ArrayList<() -> Unit>()

    /** Register a reset to run on every sign-out. Call once, when the owning layer initialises. */
    fun onSignOut(hook: () -> Unit) {
        if (hooks.none { it === hook }) hooks.add(hook)
    }

    /** Run every registered reset. Called from `AppModel.teardown()` and nowhere else. */
    fun runAll() {
        for (hook in hooks) hook()
    }
}

// ---------------------------------------------------------------------------------------------
// MARK: - The write itself, in a form that survives a relaunch
// ---------------------------------------------------------------------------------------------

/**
 * The write behind a failed change, encoded.
 *
 * This is **not** an outbox: there is no idempotency key and no sequence. What survives a relaunch
 * is the knowledge that a change failed *and*, for the four writes the app makes, the write itself
 * — so Retry after a relaunch re-issues the mark rather than reloading a library that never had it.
 *
 * All four server calls behind these are idempotent (progress is an absolute PUT; subscribe is an
 * upsert), which is what makes blind replay safe.
 */
@Serializable
sealed interface WriteIntent {

    @Serializable
    @SerialName("progress")
    data class Progress(val franchiseId: String, val mediaId: Int, val episodes: Int) : WriteIntent

    @Serializable
    @SerialName("status")
    data class Status(val franchiseId: String, val status: String) : WriteIntent

    /**
     * @param source the franchise's `MediaSource.wire`. **Defaulted, and the default is empty on
     *   purpose**: a row persisted before this field existed has to decode, and an *unknown* source
     *   must not be guessed at — `AppModel.addToLibrary` reads it back as null, and null never arms
     *   the notification primer. Guessing "anilist" would spend the app's one permission ask on a
     *   restored TV add.
     */
    @Serializable
    @SerialName("subscribe")
    data class Subscribe(
        val franchiseId: String,
        val title: String,
        val status: String,
        val source: String = "",
    ) : WriteIntent

    @Serializable
    @SerialName("unsubscribe")
    data class Unsubscribe(val franchiseId: String, val title: String) : WriteIntent
}

/** One queued progress PUT: the absolute target, plus what to call it if it fails. */
data class ProgressWrite(
    val franchiseId: String,
    val episodes: Int,
    /** A `Copy.Action` string — "Mark as watched", or "Undo" when the write is a revert. */
    val command: String,
    val title: String,
)

// ---------------------------------------------------------------------------------------------
// MARK: - The lane
// ---------------------------------------------------------------------------------------------

/**
 * One in-flight PUT per part, the newest target waiting behind it, everything it superseded
 * dropped — **the server always ends on the user's last word.**
 *
 * The mailbox holds exactly **one** pending write per part, so a rapid 12 → 13 → 14 sequence issues
 * the PUT for 12, then (once it settles) a single PUT for 14; the intermediate 13 is dropped
 * without ever being sent. The in-flight request is *never* cancelled mid-flight — a conflated
 * channel that cancelled its collector would leave the server's last word undecided.
 *
 * Deliberately a plain class with no Android and no model imports, so the semantics that are easy
 * to get subtly wrong are the ones that can be tested in isolation (`ProgressLaneTest`).
 *
 * @param scope the session scope. Main-confined in the app; a test scheduler in tests. The maps are
 *   unsynchronised because every entry point is confined to that one thread.
 * @param put issues the write. It must not throw for an ordinary failure — a failure is *reported*,
 *   not propagated, or one bad connection would tear down the lane and lose the queued target.
 */
class ProgressLane(
    private val scope: CoroutineScope,
    private val put: suspend (mediaId: Int, write: ProgressWrite) -> Unit,
) {

    /** One slot per part: a newer target overwrites the pending one rather than queueing behind it. */
    private val queued = HashMap<Int, ProgressWrite>()

    /** The draining coroutine per part, while one is running. */
    private val lanes = HashMap<Int, Job>()

    /** Post a target for this part. Starts a drainer only if one is not already running. */
    fun send(mediaId: Int, write: ProgressWrite) {
        queued[mediaId] = write
        if (lanes[mediaId] != null) return

        // LAZY, then assign, then start: on `Dispatchers.Main.immediate` a DEFAULT-started
        // coroutine begins executing *inline*, before `launch` returns — so a write that happened
        // to complete without suspending would remove a lane entry that had not been inserted yet,
        // and leak the next one. Starting explicitly makes the map the source of truth.
        val job = scope.launch(start = CoroutineStart.LAZY) {
            try {
                while (true) {
                    val next = queued.remove(mediaId) ?: break
                    put(mediaId, next)
                }
            } finally {
                // Identity-checked: a teardown that cancelled this lane and a later `send` that
                // started a fresh one must not have the old one's unwinding remove the new entry.
                if (lanes[mediaId] === coroutineContext[Job]) lanes.remove(mediaId)
            }
        }
        lanes[mediaId] = job
        job.start()
    }

    /**
     * A newer target is already waiting behind the write that just failed, and will decide the
     * outcome — so that attempt has nothing to report.
     */
    fun isQueued(mediaId: Int): Boolean = queued[mediaId] != null

    /** Sign-out. Cancels every drainer and drops every pending target. */
    fun cancelAll() {
        for (job in lanes.values) job.cancel()
        lanes.clear()
        queued.clear()
    }
}

// ---------------------------------------------------------------------------------------------
// MARK: - Undo
// ---------------------------------------------------------------------------------------------

/**
 * The single live Undo toast's state.
 *
 * **Identity is [id] alone**, which is why this is not a `data class`: a generated `equals` would
 * compare [undoAction], and two states that differ only in a lambda would read as different toasts
 * and replay the transition. The screen keys its transition and its live region on [id].
 */
/** Where a receipt is drawn. Set at the write site; [Lane] unless a host claims it. */
sealed class ReceiptPlacement {
    /** Under the control that was pressed. [host] names it ([ReceiptHost]). */
    data class InPlace(val host: String) : ReceiptPlacement()
    /** The bottom chrome's lane. */
    object Lane : ReceiptPlacement()
}

/** The in-place hosts' names — one spelling per surface, so the write and the view agree. */
object ReceiptHost {
    fun todayHero(franchiseId: String): String = "today.hero/$franchiseId"
    fun todayQueue(franchiseId: String): String = "today.queue/$franchiseId"
    fun detailHero(franchiseId: String): String = "detail.hero/$franchiseId"
    fun episodes(mediaId: Int): String = "episodes/$mediaId"
    fun schedule(mediaId: Int, episode: Int): String = "schedule/$mediaId/$episode"
}

@Stable
class UndoState(
    val mediaId: Int? = null,
    val franchiseId: String? = null,
    val prevProgress: Int = 0,
    val title: String = "",
    val episode: Int = 0,
    val added: Boolean = false,
    val statusLabel: String? = null,
    val removed: Boolean = false,
    val removedFranchise: Franchise? = null,
    val prevStatus: WatchStatus = WatchStatus.WATCHING,
    /**
     * The number of episodes this transaction actually recorded. It was left at its default of 1
     * once, *"so catching up six episodes confirmed 'Episode 12 marked as watched' — the app
     * under-reporting its own write by five, on the one control whose whole purpose is a batch."*
     * It is always derived from the SAME `prev` the undo restores, so the sentence and the rollback
     * can never disagree.
     */
    val count: Int = 1,
    val customMessage: String? = null,
    /**
     * A restoring action captured from the value read **before** the write, so undo cannot be
     * re-derived (wrongly) from state the write has already changed. Present for `markThrough` and
     * for a status move; absent for the plain progress path, which `performUndo` reverses.
     */
    val undoAction: (() -> Unit)? = null,
    /**
     * Where the receipt is drawn (`Receipts`, 5 Sep): in place under a host that stays on screen,
     * else the bottom chrome's lane. Default: the lane.
     */
    val placement: ReceiptPlacement = ReceiptPlacement.Lane,
) {
    val id: String = UUID.randomUUID().toString()

    /** The same state, placed under a host. */
    fun placed(host: String): UndoState = UndoState(
        mediaId = mediaId, franchiseId = franchiseId, prevProgress = prevProgress, title = title,
        episode = episode, added = added, statusLabel = statusLabel, removed = removed,
        removedFranchise = removedFranchise, prevStatus = prevStatus, count = count,
        customMessage = customMessage, undoAction = undoAction,
        placement = ReceiptPlacement.InPlace(host),
    )

    /** The fact alone — "Episode 19 watched" — for a receipt that sits where the show's name already is. */
    val receipt: String
        get() = when {
            customMessage != null -> customMessage
            removed -> Copy.Toast.removedShort
            added -> Copy.Toast.added(title, statusLabel ?: CopyLibrary.title)
            count > 1 -> "${Copy.episodes(count)} watched"
            else -> Copy.Progress.episodeWatched(episode)
        }

    /**
     * The toast's sentence, in fixed precedence. **Derived here and never assembled in a view**, so
     * one write cannot be described two ways on two screens.
     */
    val message: String
        get() = when {
            customMessage != null -> customMessage
            removed -> Copy.Toast.removed
            added -> Copy.Toast.added(title, statusLabel ?: CopyLibrary.title)
            count > 1 -> Copy.Toast.batchMarked(title, count)
            else -> Copy.Toast.marked(title, episode)
        }

    override fun equals(other: Any?): Boolean = other is UndoState && other.id == id

    override fun hashCode(): Int = id.hashCode()
}

// ---------------------------------------------------------------------------------------------
// MARK: - Optimistic mutation on the immutable model
// ---------------------------------------------------------------------------------------------

/**
 * A copy with one part's progress replaced — the optimistic UI update.
 *
 * It goes through `FranchisePart.withProgress`, which is `data class.copy()` and therefore carries
 * **every** field. The hand-built copy it replaced omitted `airings`, *"so one local mark silently
 * took the show off the calendar until the next library reload."* Never hand-build a part.
 */
fun Franchise.withUpdatedProgress(mediaId: Int, episodes: Int): Franchise {
    val idx = parts.indexOfFirst { it.mediaId == mediaId }
    // A part this franchise does not carry: nothing to rewrite, and no allocation to spend.
    if (idx < 0) return this
    val newParts = parts.toMutableList()
    newParts[idx] = newParts[idx].withProgress(episodes)
    return copy(parts = newParts)
}

/**
 * A copy with the watch status replaced — **both** the library field and the subscription mirror,
 * so `effectiveStatus` flips immediately.
 *
 * `addedAt` is preserved: it is a fact about the account, not about the status, and an optimistic
 * status flip must not erase when the user added the show.
 */
fun Franchise.withStatus(newStatus: WatchStatus): Franchise = copy(
    subscription = Subscription(status = newStatus, addedAt = subscription?.addedAt),
    status = newStatus,
)
