package com.anitrack.app.data

import android.content.Context
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.anitrack.model.AniTrackJson
import com.anitrack.model.copy.Copy
import com.anitrack.model.copy.CopyDates
import java.io.File
import java.util.UUID
import java.util.concurrent.atomic.AtomicLong
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer

/*
 * # Watch sessions
 *
 * Rewatching is first-class: every completed watch is a session, and **at most one session is
 * active per franchise**. Device-local this version — atomic JSON with one backup generation — so a
 * reinstall loses history but never corrupts it. Progress itself stays on the server; sessions
 * explain it.
 */

/**
 * One watch of a show, or of one part of it.
 *
 * The sentinel to know about: an **implicit first watch** carries `completedAt == 0`. It is written
 * when a rewatch is started for a franchise that has no sessions yet — the first watch happened,
 * its dates are simply unknown — and [subtitle] maps that 0 back to `null` so it renders "Dates
 * unknown · 26 episodes" rather than a 1970 date.
 */
@Immutable
@Serializable
data class WatchSession(
    val id: String,
    val franchiseId: String,
    val scope: Scope,
    /** 1 = first watch, 2 = second watch, … */
    val ordinal: Int,
    val startedAt: Long? = null,
    val completedAt: Long? = null,
    val cancelledAt: Long? = null,
    val cancelledAtEpisode: Int? = null,
    /** Episodes the session covers (for history copy); 0 when unknown. */
    val episodes: Int = 0,
) {

    /** What the session covers: the whole show, or one installment of it. */
    @Immutable
    @Serializable
    sealed interface Scope {
        @Serializable
        data object Franchise : Scope

        @Serializable
        data class Part(val mediaId: Int) : Scope
    }

    val isActive: Boolean get() = completedAt == null && cancelledAt == null

    val isCompleted: Boolean get() = completedAt != null

    /** "First watch" / "Second watch" / "7th watch". */
    val title: String get() = Copy.Progress.ordinalWatch(ordinal)

    /**
     * "In progress · Episode 7 next" · "Cancelled at episode 4" · "Jul 4 – Jul 19 · 26 episodes" ·
     * "Dates unknown · 26 episodes".
     */
    fun subtitle(nextEpisode: Int?, now: Long, dates: CopyDates): String {
        if (isActive) {
            return if (nextEpisode != null) Copy.Progress.inProgress(nextEpisode) else "In progress"
        }
        cancelledAtEpisode?.let { return "Cancelled at ${Copy.episodeInSentence(it)}" }
        return Copy.Progress.sessionSpan(
            started = startedAt,
            // The implicit-first-watch sentinel. See the type's own doc comment.
            completed = if (completedAt == 0L) null else completedAt,
            episodes = episodes,
            now = now,
            dates = dates,
        )
    }
}

/**
 * The device-local session store.
 *
 * A singleton, matching iOS, and **loaded synchronously** at [install] — Detail reads it during
 * composition, so an asynchronous hydrate would draw the history section empty and then pop it in.
 * Install from the application root, before the first composition.
 */
object RewatchStore {

    var sessions: List<WatchSession> by mutableStateOf(emptyList())
        private set

    /** What Detail's history header needs, in one read. */
    @Immutable
    data class Summary(
        val completedCount: Int,
        val active: WatchSession?,
        val lastCompletedAt: Long?,
    )

    private var dir: File? = null

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    /** Idempotent; loads synchronously. */
    fun install(context: Context) {
        if (dir != null) return
        dir = File(context.applicationContext.filesDir, DIR_NAME)
        load()
    }

    /** Test seam: install against an arbitrary directory. */
    fun install(directory: File) {
        if (dir != null) return
        dir = directory
        load()
    }

    // -----------------------------------------------------------------------------------------
    // MARK: - Queries
    // -----------------------------------------------------------------------------------------

    /** That franchise's sessions, **most recent watch first**. */
    fun sessions(franchiseId: String): List<WatchSession> =
        sessions.filter { it.franchiseId == franchiseId }.sortedByDescending { it.ordinal }

    fun activeSession(franchiseId: String): WatchSession? =
        sessions.firstOrNull { it.franchiseId == franchiseId && it.isActive }

    fun summary(franchiseId: String): Summary {
        val mine = sessions.filter { it.franchiseId == franchiseId }
        return Summary(
            completedCount = mine.count { it.isCompleted },
            active = mine.firstOrNull { it.isActive },
            lastCompletedAt = mine.mapNotNull { it.completedAt }.maxOrNull(),
        )
    }

    // -----------------------------------------------------------------------------------------
    // MARK: - Commands
    // -----------------------------------------------------------------------------------------

    /**
     * Starts a rewatch and returns the new active session.
     *
     * **The first watch is recorded implicitly** (dates unknown, `completedAt = 0`) when no session
     * exists yet, so the one being started is the *second* watch — which is what the user means by
     * "rewatch", and what makes the ordinal copy true.
     */
    fun startRewatch(
        franchiseId: String,
        scope: WatchSession.Scope,
        startedAt: Long,
        episodes: Int,
    ): WatchSession {
        val existing = sessions.filter { it.franchiseId == franchiseId }
        val additions = ArrayList<WatchSession>(2)
        val priorOrdinals: List<Int>
        if (existing.isEmpty()) {
            val first = WatchSession(
                id = UUID.randomUUID().toString(),
                franchiseId = franchiseId,
                scope = WatchSession.Scope.Franchise,
                ordinal = 1,
                startedAt = null,
                completedAt = 0L,
                episodes = episodes,
            )
            additions.add(first)
            priorOrdinals = listOf(first.ordinal)
        } else {
            priorOrdinals = existing.map { it.ordinal }
        }
        val session = WatchSession(
            id = UUID.randomUUID().toString(),
            franchiseId = franchiseId,
            scope = scope,
            ordinal = (priorOrdinals.maxOrNull() ?: 0) + 1,
            startedAt = startedAt,
            completedAt = null,
            episodes = episodes,
        )
        additions.add(session)
        sessions = sessions + additions
        persist()
        return session
    }

    fun complete(id: String, at: Long) = mutate(id) { it.copy(completedAt = at) }

    fun cancel(id: String, atEpisode: Int, at: Long) =
        mutate(id) { it.copy(cancelledAt = at, cancelledAtEpisode = atEpisode) }

    fun setStartDate(id: String, to: Long) = mutate(id) { it.copy(startedAt = to) }

    fun delete(id: String) {
        sessions = sessions.filterNot { it.id == id }
        persist()
    }

    fun deleteAll(franchiseId: String) {
        sessions = sessions.filterNot { it.franchiseId == franchiseId }
        persist()
    }

    /** Sign-out: sessions belong to the account that made them. */
    fun reset() {
        sessions = emptyList()
        persist()
    }

    private inline fun mutate(id: String, transform: (WatchSession) -> WatchSession) {
        if (sessions.none { it.id == id }) return
        sessions = sessions.map { if (it.id == id) transform(it) else it }
        persist()
    }

    // -----------------------------------------------------------------------------------------
    // MARK: - Persistence (atomic, one backup generation)
    // -----------------------------------------------------------------------------------------

    private fun load() {
        val base = dir ?: return
        for (candidate in listOf(File(base, FILE_NAME), File(base, BACKUP_NAME))) {
            val decoded = runCatching {
                if (!candidate.exists()) return@runCatching null
                AniTrackJson.decodeFromString(SESSION_LIST, candidate.readText())
            }.getOrNull()
            if (decoded != null) {
                sessions = decoded
                return
            }
        }
        sessions = emptyList()
    }

    /**
     * Snapshot now, write off the main thread: copy the live file to the backup, then write the new
     * one through a temp file and a rename.
     *
     * A throw is swallowed — *"a failed write keeps the previous file (atomic) and the backup; the
     * in-memory state stays authoritative for this session."*
     */
    private fun persist() {
        val base = dir ?: return
        val snapshot = sessions
        val seq = persistSeq.incrementAndGet()
        scope.launch {
            // `withLock` suspends, so it sits OUTSIDE the `runCatching`: a `runCatching` around a
            // suspension point also swallows the `CancellationException` thrown while it is parked.
            writeLock.withLock {
                // Serialised AND ordered. One transaction writes twice — a watch completed, then
                // the rewatch that follows it — and the lock alone does not say which of the two
                // coroutines reaches it first; an older snapshot landing last would resurrect the
                // session the user just closed. Only the newest is worth the write.
                if (seq != persistSeq.get()) return@withLock
                val target = File(base, FILE_NAME)
                val backup = File(base, BACKUP_NAME)
                // Per-write scratch name: two persists used to share `sessions.json.tmp` and
                // interleave into one file, which was then renamed over the live history. (The
                // counter restarts each process, so an orphan left by a kill is reused, never
                // accumulated.)
                val tmp = File(base, "$FILE_NAME.$seq.tmp")
                runCatching {
                    base.mkdirs()
                    if (target.exists()) {
                        backup.delete()
                        target.copyTo(backup, overwrite = true)
                    }
                    tmp.writeText(AniTrackJson.encodeToString(SESSION_LIST, snapshot))
                    // `rename(2)` REPLACES the destination atomically, so the live file stands
                    // until the instant the new one takes its place — the promise this function's
                    // doc makes. Deleting the target first threw both the live file and the write
                    // away together whenever the rename then failed.
                    if (!tmp.renameTo(target)) {
                        target.delete()
                        tmp.renameTo(target)
                    }
                }
                // The scratch file never outlives the attempt, whichever way it ended. (Also what
                // keeps this block Unit-typed, next to the early `return@withLock` above.)
                if (tmp.exists()) runCatching { tmp.delete() }
            }
        }
    }

    /** One history write at a time. See [persist]. */
    private val writeLock = Mutex()

    /** Stamped per [persist] call, so a write that lost the race to the lock can stand down. */
    private val persistSeq = AtomicLong(0)

    private val SESSION_LIST = ListSerializer(WatchSession.serializer())

    private const val DIR_NAME = "Previously"
    private const val FILE_NAME = "sessions.json"
    private const val BACKUP_NAME = "sessions.backup.json"
}
