package com.anitrack.app.notifications

import android.content.Context
import com.anitrack.model.AniTrackJson
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.util.UUID

/*
 * # Where the airing plan lives between processes
 *
 * `EpisodeNotifications.kt` owns the plan's *shape* ([AiringPlan], [PlannedAiring]) and its
 * *selection* (`EpisodeNotifications.buildPlan` — the port of iOS's
 * `EpisodeNotifications.sync(library:now:)`: `watching` AND AniList, three per show, round-robin,
 * capped at 48). It deliberately leaves two seams unimplemented, because neither belongs to a file
 * about notifications: [AiringPlans] — persistence — and [AiringAlarms] — `AlarmManager`.
 *
 * This file is the first of those. [AlarmScheduler] is the second.
 *
 * ## Why a flat file and not DataStore
 *
 * The only reader that matters is [AiringReceiver], on a process very often started for that
 * broadcast alone, with about ten seconds to live, no session and no network. A file it reads and
 * is done with is the honest shape of that; a `Flow` would be ceremony around a single `readText`.
 * It is the same discipline `data/LibraryCache.kt` uses for the same reason, and the same atomic
 * write:
 *
 * * write to a **uniquely named** scratch file, then `rename(2)` it into place — so a reader can
 *   never see a half-written plan, and a failed write leaves the previous plan standing;
 * * never delete the target first — that opens a window where a boot finds no plan at all, and
 *   loses the good copy outright whenever the rename then fails;
 * * swallow every failure. `AiringPlans` requires it (*"a plan that cannot be read is an empty
 *   plan, never a crash inside a `BroadcastReceiver`"*), and so does `AmbientSync`: this runs inside
 *   the SUCCESS branch of `reload()`, where an escaping exception is read as a *library* failure.
 *
 * It sits in `filesDir`, beside the library cache. Not `cacheDir`: a schedule the system may evict
 * overnight is not a schedule.
 *
 * ## Divergence from `docs/android-port/PLAN.md`
 *
 * PLAN §4 files the store under `data/disk/AiringPlanStore.kt`. It lives here, beside the scheduler
 * that is its only other caller, in the `notifications/` package this port settled on.
 */

// ---------------------------------------------------------------------------------------------
// MARK: - Reading a plan as alarms
// ---------------------------------------------------------------------------------------------
//
// There used to be a `bucketsAfter(afterExclusive)` here — "every distinct bucket still ahead,
// soonest first" — documented as the sanctioned way to read `AiringPlan.airings` and as having the
// scheduler for its only caller. It had NO production caller: the real arming policy is
// `AlarmScheduler.armTargets`, which differs in every way that matters (it carries the trigger
// instant as well as the key, the eight-bucket budget and the horizon's fallback), and the only
// thing left calling `bucketsAfter` was the test that covered it. Two subtly different bucket
// selectors, one unused and both documented as authoritative, is a trap in the one file whose whole
// contract is "both halves must round with `airingBucket`", so it is gone and `armTargets` is the
// only answer to "which alarms does this plan want".

// ---------------------------------------------------------------------------------------------
// MARK: - The store
// ---------------------------------------------------------------------------------------------

/**
 * `airing-plan.json`, the [AiringPlans] implementation.
 *
 * Every method is safe from any dispatcher and none of them throws (except cancellation, which is
 * not a failure and must propagate).
 *
 * @param dir the app's own `filesDir`.
 */
class AiringPlanStore(private val dir: File) : AiringPlans {

    private val file: File get() = File(dir, FILE_NAME)

    // ---- AiringPlans ------------------------------------------------------------------------

    override suspend fun read(): AiringPlan? = withContext(Dispatchers.IO) { load() }

    override suspend fun write(plan: AiringPlan) {
        withContext(Dispatchers.IO) { save(plan) }
    }

    override suspend fun clear() {
        withContext(Dispatchers.IO) { delete() }
    }

    /**
     * The blocking half, for sign-out. See [AiringPlans.clearNow]: the plan has to be gone before
     * `cancelAll` returns, or a boot between the two steps re-arms the departing account's shows.
     */
    override fun clearNow() {
        delete()
    }

    // ---- The blocking primitives --------------------------------------------------------------
    //
    // Public because a BroadcastReceiver's `goAsync` block is already off the main thread and has
    // no reason to hop a dispatcher to read one small file.

    /** The persisted plan, or `null` for "nothing armed" — including every failure mode. */
    fun load(): AiringPlan? = runCatching {
        val f = file
        if (!f.exists()) return null
        AniTrackJson.decodeFromString(AiringPlan.serializer(), f.readText())
    }.getOrNull()

    /**
     * Replace the stored plan. Blocking file I/O — never call it on the main thread.
     *
     * @return whether the plan on disk is now [plan].
     */
    @Synchronized
    fun save(plan: AiringPlan): Boolean {
        val tmp = File(dir, "$FILE_NAME.${UUID.randomUUID()}.tmp")
        val written = runCatching {
            dir.mkdirs()
            // Any OTHER scratch file here belongs to a process that died mid-write: this method is
            // synchronized and nothing alive owns one. Unique names would otherwise accumulate a
            // copy of the plan per unlucky kill, in `filesDir`, which the system never reclaims.
            dir.listFiles()?.forEach { stale ->
                val scratch = stale.name.startsWith("$FILE_NAME.") && stale.name.endsWith(".tmp")
                if (stale != tmp && scratch) stale.delete()
            }
            tmp.writeText(AniTrackJson.encodeToString(AiringPlan.serializer(), plan))
            // `rename(2)` REPLACES atomically, so the previous plan stands until the instant the new
            // one takes its place.
            var renamed = tmp.renameTo(file)
            if (!renamed) {
                file.delete()
                renamed = tmp.renameTo(file)
            }
            renamed
        }.getOrDefault(false)
        // The scratch file never outlives the attempt, whichever way it ended.
        if (tmp.exists()) runCatching { tmp.delete() }
        return written
    }

    /**
     * Sign-out. The plan is built from one account's library, so leaving it on disk would announce
     * the previous user's episodes to whoever signs in next.
     */
    @Synchronized
    fun delete() {
        runCatching { file.delete() }
    }

    companion object {

        private const val FILE_NAME = "airing-plan.json"

        /** The store a cold process builds for itself: no graph, no session, no network. */
        fun from(context: Context): AiringPlanStore =
            AiringPlanStore(context.applicationContext.filesDir)
    }
}
