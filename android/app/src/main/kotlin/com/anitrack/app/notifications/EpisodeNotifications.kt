package com.anitrack.app.notifications

import android.Manifest
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.anitrack.app.MainActivity
import com.anitrack.app.data.AmbientSync
import com.anitrack.app.ui.shell.ShellIntents
import com.anitrack.model.Franchise
import com.anitrack.model.MediaSource
import com.anitrack.model.WatchStatus
import com.anitrack.model.copy.Copy
import com.anitrack.model.displayTitle
import com.anitrack.model.effectiveStatus
import com.anitrack.model.releasingPart
import com.anitrack.model.scheduleAirings
import kotlinx.coroutines.CancellationException
import kotlinx.serialization.Serializable

/*
 * EPISODE ALERTS — the port of `ios/Sources/Notifications/EpisodeNotifications.swift`
 * (spec `spec/profile-shell.md` §7).
 *
 * The SELECTION below is iOS's, to the letter: up to three alerts per watching AniList show, taken
 * from the part's own dated slots, flattened ROUND-ROBIN so every show keeps its soonest before any
 * show gets its second, capped at 48. The DELIVERY is not, and could not be — see
 * `docs/android-port/research/notifications-liveupdates.md`, which re-architected it:
 *
 *   iOS      one pending `UNTimeIntervalNotificationTrigger` per alert; the system keeps the promise
 *            and presents it, and a 64-request cap is the only budget.
 *   here     one persisted PLAN, and one alarm per distinct air-time MINUTE — because Doze
 *            rate-limits `set*AndAllowWhileIdle` to one firing per nine minutes per app and anime
 *            simulcasts cluster on a single slot. Twelve alarms on one instant would serialise
 *            across ~108 minutes; one alarm posting twelve notifications is not rate-limited at all.
 *
 * That split is why this file builds and persists a plan and hands the arming to a seam, instead of
 * "scheduling notifications". Nothing here talks to `AlarmManager`; nothing here reads the network,
 * the auth session or `AppModel`. The receiver that fires in a cold process reads only the plan.
 *
 * The four files, split the way the platform splits:
 *
 *   this file          SELECTION, the plan's shape, the `AmbientSync` seam, the permission gate and
 *                      the tap route.
 *   AiringPlan.kt      the [AiringPlans] implementation — `airing-plan.json` in `filesDir`.
 *   AlarmScheduler.kt  the [AiringAlarms] implementation — buckets, slots, both exactness branches,
 *                      and the re-arm receiver for boot / update / clock / grant.
 *   Channels.kt        the channel and the group key.
 *   AiringReceiver.kt  POSTING and GROUPING — the notification a user actually sees.
 *
 * ## The three gates, and the one that is deliberately NOT iOS's
 *
 * 1. `effectiveStatus == watching` — the hardest tier of the app's airings ladder (all statuses ⊃
 *    `tracksAirings` ⊃ `watching`). An alert interrupts you; a bookmark may not.
 * 2. `source == anilist` — TMDB air times are date-only, synthesised by the server at 17:00 UTC, so
 *    a minute-precise "Episode 12 is out now" fired off that instant would be fiction.
 * 3. The notification permission gates POSTING, not PLANNING. iOS returns from `sync` without
 *    touching its pending set when authorization is missing, because there scheduling *is* posting.
 *    Here they are two different things, so: the PLAN is written whatever the permission says — it
 *    is one file, it costs nothing, and it is what makes an instant re-arm possible the moment the
 *    answer changes — while the ALARMS are stood down, because an armed alarm for a user who
 *    declined notifications is a device wake-up spent drawing something the platform then drops.
 *
 * [EpisodeNotifications.rearmNow] is the other half of gate 3: it arms from the plan already on
 * disk, with no library in hand. Its callers, all of them moments when the PERMISSION or the ARMED
 * SET changed rather than the library — the primer's Allow (iOS's `alertsWereAllowed`, which exists
 * because *"'Turn on' granted permission and scheduled nothing, so the first alert could be a day
 * away"*), the Profile → Notifications row when the user comes back from system Settings having
 * switched the app back on, [AiringReceiver] immediately after it posts a bucket,
 * [AlarmRearmReceiver]'s five broadcasts, and `AiringRearm`'s two safety nets (the app's foreground
 * and a daily job).
 */

// =================================================================================================
// MARK: - The plan
// =================================================================================================

/**
 * One alert, flattened to everything the receiver needs and nothing else.
 *
 * It is deliberately NOT a `Franchise` reference: [AiringReceiver] runs in a process that may have
 * been started for the sole purpose of posting, with no library in memory, no session and no
 * network. Everything the notification says is carried here.
 */
@Serializable
data class PlannedAiring(
    /** ms epoch — the episode's own air instant, not the bucket it is armed in. */
    val atMillis: Long,
    /** `Franchise.id` — the tap route's payload, and the analogue of iOS's `threadIdentifier`. */
    val franchiseId: String,
    /** `Franchise.displayTitle` — "Re:ZERO", the same name every row and shelf in the app uses. */
    val title: String,
    /** `FranchisePart.mediaId` — half of the alert's stable identity. */
    val mediaId: Int,
    /** Null when the catalogue has not numbered the slot; the copy says "A new episode is out now". */
    val episode: Int? = null,
) {

    /**
     * `episode-<mediaId>-<episode>` — the SAME identifier shape iOS gives its pending request.
     *
     * Both ports therefore name one alert alike, which is what makes an armed-set dump from one
     * readable against the other.
     */
    val tag: String get() = "episode-$mediaId-${episode ?: 0}"

    /**
     * The `NotificationManager` id, so a re-post of the same episode REPLACES its own notification
     * instead of stacking a second copy of it.
     *
     * Derived from [tag] rather than from arithmetic on [mediaId]: a TMDB media id is
     * `1_000_000_000 + season id`, and `mediaId * 1000` would silently overflow `Int`. TMDB cannot
     * reach this file today (gate 2), and this is what keeps that harmless if it ever does.
     *
     * Never 0 and never [AiringReceiver.SUMMARY_ID], so an alert can neither evict the bundle header
     * nor be evicted by it.
     */
    val notificationId: Int
        get() {
            val hashed = tag.hashCode() and 0x7fffffff
            return if (hashed <= AiringReceiver.SUMMARY_ID) hashed + 2 else hashed
        }
}

/**
 * Every alert this account is owed, in the order iOS would have queued them.
 *
 * [builtAt] is not decoration: a plan is only as true as the library it was derived from, and the
 * re-arm safety nets want to know how old it is before they trust it.
 *
 * [airings] is in **round-robin order, not time order** — read it through the scheduler's
 * `armTargets` and [AiringReceiver]'s window, never by position. Nothing should depend on the
 * list's own order except the truncation that produced it.
 */
@Serializable
data class AiringPlan(
    val builtAt: Long,
    val airings: List<PlannedAiring> = emptyList(),
) {
    val isEmpty: Boolean get() = airings.isEmpty()

    /** Whether [other] arms the identical set. Ignores [builtAt], which changes on every rebuild. */
    fun sameAlerts(other: AiringPlan?): Boolean = other != null && other.airings == airings
}

/**
 * One alarm per distinct air-time minute — the bucket.
 *
 * The scheduler arms a bucket, the alarm carries the bucket key back as [AiringReceiver.EXTRA_AT],
 * and the receiver posts every airing whose instant rounds into it. So a LATE alarm — which is the
 * normal case without the exact-alarm grant — still posts exactly the set that was armed, because
 * the key is the intended instant rather than the firing time.
 *
 * **Both halves must round with [airingBucket].** A bucket armed at second precision and matched at
 * minute precision posts nothing at all, silently.
 */
const val AIRING_BUCKET_MS: Long = 60_000L

/**
 * The minute [atMillis] falls in — floored. Epoch milliseconds are positive, so truncating division
 * is a floor.
 *
 * **This is a KEY, not a firing time**, and the distinction is the whole reason a floor is safe. A
 * floored key can be up to 59 seconds before the episode it names, and "Episode 12 is out now" said
 * before it is out is the one failure this feature cannot afford — so the scheduler fires each
 * bucket at the LATEST air instant inside it and merely *carries* this key as
 * [AiringReceiver.EXTRA_AT]. The receiver then matches on the key, and refuses to announce any
 * episode whose own instant has not yet passed.
 */
fun airingBucket(atMillis: Long): Long = atMillis / AIRING_BUCKET_MS * AIRING_BUCKET_MS

// Which buckets a plan wants armed is `AlarmScheduler.armTargets`'s answer, and its only one: it
// carries the trigger instant beside the key, the bucket budget and the horizon's fallback. See the
// note in `AiringPlan.kt` about the second selector that used to sit there unused.

// =================================================================================================
// MARK: - The two seams this file does not implement
// =================================================================================================

/**
 * Where the plan lives between processes. Implemented by `AiringPlanStore` (`AiringPlan.kt`).
 *
 * An interface rather than a concrete store because the receiver's process is frequently cold and
 * the store's shape is a persistence decision. All three methods must be safe from any dispatcher
 * and **must not throw** — a plan that cannot be read is an empty plan, never a crash inside a
 * `BroadcastReceiver`.
 */
interface AiringPlans {

    /** The last plan written, or null when there is none (a fresh install, or after sign-out). */
    suspend fun read(): AiringPlan?

    /** Replace the stored plan. */
    suspend fun write(plan: AiringPlan)

    /** Sign-out. The schedule belongs to one account's library. */
    suspend fun clear()

    /**
     * [clear], **blocking**, for the one caller that cannot suspend: `AmbientSync.cancelAll` is
     * non-suspending because `AppModel.teardown()` is a main-thread transaction.
     *
     * It is one `unlink` on one small file, and the alternative is a plan that outlives its account
     * — see [EpisodeNotifications.cancelAll] for why nothing asynchronous will do. Must not throw.
     */
    fun clearNow()
}

/**
 * The alarm seam — `AlarmManager`, bucketed. Implemented by `AlarmScheduler` (`AlarmScheduler.kt`).
 *
 * The implementation owns the whole exactness question: `canScheduleExactAlarms()`,
 * `setExactAndAllowWhileIdle` versus `setAndAllowWhileIdle`, and the `SecurityException` that can be
 * thrown between the check and the call because the grant is revocable at runtime. Nothing in this
 * file assumes a precision the device has not granted, and nothing it throws may reach `AmbientSync`.
 */
interface AiringAlarms {

    /** Idempotent: cancel everything we own, then arm the soonest buckets the stored plan implies. */
    suspend fun rearm(now: Long = System.currentTimeMillis())

    /**
     * The re-arm at the end of a firing.
     *
     * [firedBucketAt] has just been announced, so buckets at or before it must not be armed again —
     * which closes the one race a "still ahead" filter cannot: an alarm that arrives a millisecond
     * early would otherwise re-arm the bucket it has just posted and announce every one of those
     * episodes twice.
     *
     * The default is [rearm], because that filter already covers the ordinary case; an
     * implementation that can express the exclusion should override this and do so.
     */
    suspend fun rearmAfterFiring(now: Long, firedBucketAt: Long) {
        rearm(now)
    }

    /** Drop every armed alarm. Must be safe to call when nothing is armed. */
    fun cancelAll()
}

// =================================================================================================
// MARK: - EpisodeNotifications
// =================================================================================================

/**
 * The app-facing half of the alert feature: it turns a library into a plan, keeps the alarms in step
 * with it, and tears the whole thing down at sign-out.
 *
 * It is the app's [AmbientSync], so `AppModel` pushes into it after every confirmed library change —
 * a successful `reload()`, a confirmed `setStatus`, a confirmed `removeFromLibrary` — and from
 * `alertsWereAllowed()`, and never has to know that alarms, plans or channels exist.
 */
class EpisodeNotifications internal constructor(
    private val context: Context,
    private val plans: AiringPlans,
    private val alarms: AiringAlarms,
) : AmbientSync {

    // ---------------------------------------------------------------------------------------------
    // MARK: - AmbientSync
    // ---------------------------------------------------------------------------------------------

    /**
     * Rebuild the plan from the library as it now stands, and arm what it implies.
     *
     * **It must not throw**, and the `try` here is the enforcement rather than a precaution: this
     * runs inside the SUCCESS branch of `reload()`, `setStatus` and `removeFromLibrary`, so anything
     * escaping would be read by the caller as a *library* failure — it would paint "couldn't
     * refresh" over a library that had already arrived and been committed, roll back a status the
     * server had accepted, or re-insert a franchise the server had already deleted. The canonical
     * case is a `SecurityException` out of `AlarmManager` the moment the user revokes "Alarms &
     * reminders" mid-session. `AppModel.syncAmbient` carries the same belt; this is the braces, at
     * the layer that knows the failure is not the library's.
     */
    override suspend fun sync(library: List<Franchise>, now: Long) {
        try {
            val plan = buildPlan(library, now)
            // Rewriting an identical plan buys nothing and costs a file rename on every reload.
            if (!plan.sameAlerts(plans.read())) plans.write(plan)
            armOrStandDown(now)
        } catch (cancellation: CancellationException) {
            throw cancellation
        } catch (t: Throwable) {
            Log.w(ALERTS_LOG_TAG, "couldn’t sync episode alerts", t)
        }
    }

    /**
     * Sign-out. *"The schedule is built from one account's library, so leaving it armed would
     * announce the previous user's episodes to whoever signs in next (or to nobody at all)."*
     *
     * Three things go, and **the plan goes first**. It used to go last, and asynchronously, on the
     * argument that with the alarms already cancelled nothing could reach it — which holds in only
     * one direction. A surviving `airing-plan.json` is read and re-armed by the very next
     * `BOOT_COMPLETED` or `MY_PACKAGE_REPLACED`, because [AlarmRearmReceiver] arms from the
     * persisted plan with no account check at all. The window was small and its consequence was the
     * previous account's shows posting alerts to whoever signed in next: the precise leak this
     * method exists to prevent.
     *
     * With the plan deleted first the remainder really is inert whichever step the process dies
     * on — an armed alarm over no plan posts nothing and re-arms nothing. That is why the deletion
     * is [AiringPlans.clearNow] rather than a launched `clear()`: one `unlink`, synchronously, is
     * the whole cost of closing it.
     */
    override fun cancelAll() {
        runCatching { plans.clearNow() }
            .onFailure { Log.w(ALERTS_LOG_TAG, "couldn’t delete the airing plan", it) }

        runCatching { alarms.cancelAll() }
            .onFailure { Log.w(ALERTS_LOG_TAG, "couldn’t cancel airing alarms", it) }

        // Every notification this app has ever posted belongs to this feature, so the blanket cancel
        // is exact — the Android counterpart of iOS clearing BOTH its pending and its delivered
        // sets. An alert already on the lock screen is as much the departing account's as one that
        // has not fired yet.
        runCatching { NotificationManagerCompat.from(context).cancelAll() }
            .onFailure { Log.w(ALERTS_LOG_TAG, "couldn’t clear posted alerts", it) }
    }

    // ---------------------------------------------------------------------------------------------
    // MARK: - Re-arming from the plan alone
    // ---------------------------------------------------------------------------------------------

    /**
     * Arm — or stand down — from the plan already on disk, with no library in hand. Never throws.
     *
     * @param firedBucketAt the bucket a firing has just posted, so it cannot be announced twice.
     *   Null everywhere except [AiringReceiver].
     */
    suspend fun rearmNow(
        now: Long = System.currentTimeMillis(),
        firedBucketAt: Long? = null,
    ) {
        try {
            armOrStandDown(now, firedBucketAt)
        } catch (cancellation: CancellationException) {
            throw cancellation
        } catch (t: Throwable) {
            Log.w(ALERTS_LOG_TAG, "couldn’t re-arm episode alerts", t)
        }
    }

    /** The plan [AiringReceiver] posts from. Null when there is none. */
    suspend fun currentPlan(): AiringPlan? = plans.read()

    /**
     * The alerts this account is owed and this device will actually post, as [PlannedAiring.tag]s.
     *
     * **This is what a bell in the UI is allowed to claim.** Schedule's reminder bell is the one
     * surface that tells a user an alert is armed for a specific episode, and it is drawn from this
     * — through `ScheduleReminders.source`, which `AppGraph` installs. It went unwired for a while,
     * so `refresh()` always resolved to the empty set and the bell never drew at all: the exact
     * failure `AppGraph`'s own comment warns about ("every bell in the UI still says armed"),
     * inverted.
     *
     * Two things are deliberately NOT the answer here. Not the eight armed BUCKETS — those are an
     * alarm budget that re-fills itself as each one fires, and a user does not have a mental model
     * of a bucket; the promise is the plan. And not the plan alone either: with notifications
     * switched off nothing is armed and nothing will post, so the bell must not claim otherwise.
     */
    suspend fun armedAlertTags(now: Long = System.currentTimeMillis()): Set<String> {
        if (!canPostAlerts(context)) return emptySet()
        val plan = try {
            plans.read()
        } catch (cancellation: CancellationException) {
            throw cancellation
        } catch (t: Throwable) {
            Log.w(ALERTS_LOG_TAG, "couldn’t read the airing plan", t)
            null
        } ?: return emptySet()
        return plan.airings.asSequence().filter { it.atMillis > now }.map { it.tag }.toSet()
    }

    /**
     * The one place the notification permission decides anything. See gate 3 in the file header.
     */
    private suspend fun armOrStandDown(now: Long, firedBucketAt: Long? = null) {
        if (!canPostAlerts(context)) {
            alarms.cancelAll()
            return
        }
        if (firedBucketAt != null) alarms.rearmAfterFiring(now, firedBucketAt) else alarms.rearm(now)
    }

    // ---------------------------------------------------------------------------------------------
    // MARK: - Companion: the process singleton, and the selection
    // ---------------------------------------------------------------------------------------------

    companion object {

        /**
         * Alerts per show. *"One used to be all there was, so a viewer who got the alert for episode
         * 5 and did not open the app for three weeks heard nothing about 6, 7 or 8 — the feature
         * went quiet for exactly the person it exists to bring back."*
         */
        const val PER_SHOW: Int = 3

        /**
         * The total cap. **Android has no 64-request limit — this is kept anyway**, deliberately, so
         * both platforms fire the same alerts. A cap the two ports do not share is a bug report
         * nobody can reproduce.
         */
        const val MAX_PENDING: Int = 48

        @Volatile
        private var installed: EpisodeNotifications? = null

        /**
         * The instance [AiringReceiver] reads, which is the whole reason it exists.
         *
         * A `BroadcastReceiver` may be the reason the process was started, and Android always
         * constructs the `Application` before any component — so a singleton written in
         * `PreviouslyApp.onCreate` is visible to a receiver on a cold process, while anything held
         * in composition or on an `Activity` is not.
         */
        val current: EpisodeNotifications? get() = installed

        /**
         * Build the layer, publish it to the process, and make sure the channel exists.
         *
         * Called once from `PreviouslyApp.onCreate`, before `AppGraph.create` needs it as the
         * model's [AmbientSync]:
         *
         * ```kotlin
         * val alerts = EpisodeNotifications.install(
         *     context = app,
         *     plans = AiringPlanStore.from(app),
         *     alarms = AlarmScheduler.from(app),
         * )
         * // … AppModel(…, ambient = alerts, …)
         * ```
         */
        fun install(context: Context, plans: AiringPlans, alarms: AiringAlarms): EpisodeNotifications {
            val app = context.applicationContext
            Channels.ensure(app)
            return EpisodeNotifications(app, plans, alarms).also { installed = it }
        }

        /**
         * The whole selection algorithm, and it is `EpisodeNotifications.sync`'s, step for step.
         *
         * 1. Eligible shows: `watching` **and** `anilist` — gates 1 and 2 in the file header.
         * 2. The releasing part, or the show contributes nothing.
         * 3. Its dated slots, future-only, soonest first, one per episode number, at most
         *    [PER_SHOW]. Read through `scheduleAirings`, which **is** the ported fallback: against a
         *    server that predates per-episode airings it synthesises the slot from `nextAiringAt` /
         *    `nextEpisodeNumber`, so a weekly show still gets its one alert instead of none. The raw
         *    fields are never read here — freshness is derived from `airings`, never from the
         *    catalogue's hourly counts.
         * 4. Shows with no slots drop out.
         * 5. **Round-robin flattening.** Rank 0 for every show, sorted by instant; then rank 1; then
         *    rank 2 — *not* one global time sort. That is the whole point: a large library must
         *    never starve one show of its next episode to make room for another show's third.
         * 6. [MAX_PENDING].
         *
         * Note what is deliberately absent: a time HORIZON. The research note bounded the plan to 48
         * hours, but the horizon is an *arming* policy — the scheduler picks the buckets it can
         * afford — and a plan clipped to it would leave a device that had been offline for three
         * days with nothing to re-arm from. The server's own `airings` window (8 days back … 15
         * ahead) is the only bound this list needs.
         */
        fun buildPlan(library: List<Franchise>, now: Long): AiringPlan {
            val perShow: List<List<PlannedAiring>> = library.mapNotNull inner@{ franchise ->
                if (franchise.source != MediaSource.ANILIST) return@inner null
                if (franchise.effectiveStatus != WatchStatus.WATCHING) return@inner null

                val part = franchise.releasingPart ?: return@inner null
                val title = franchise.displayTitle

                val slots = part.scheduleAirings
                    .asSequence()
                    .filter { it.at > now }
                    .sortedBy { it.at }
                    .distinctBy { it.episode }
                    .take(PER_SHOW)
                    .map { slot ->
                        PlannedAiring(
                            atMillis = slot.at,
                            franchiseId = franchise.id,
                            title = title,
                            mediaId = part.mediaId,
                            episode = slot.episode,
                        )
                    }
                    .toList()

                if (slots.isEmpty()) null else slots
            }

            val ordered = ArrayList<PlannedAiring>(minOf(MAX_PENDING, perShow.sumOf { it.size }))
            ranks@ for (rank in 0 until PER_SHOW) {
                for (airing in perShow.mapNotNull { it.getOrNull(rank) }.sortedBy { it.atMillis }) {
                    if (ordered.size >= MAX_PENDING) break@ranks
                    ordered.add(airing)
                }
            }

            return AiringPlan(builtAt = now, airings = ordered.toList())
        }
    }
}

// =================================================================================================
// MARK: - Permission
// =================================================================================================

/**
 * May this app post an episode alert **right now**?
 *
 * Two questions, and both have to be asked. The runtime permission exists only from API 33, so below
 * that it is always held and `areNotificationsEnabled()` is the whole answer; from 33 the permission
 * can be granted while the user has still switched the app off in Settings, and a notification
 * posted in that state is dropped by the platform without an exception.
 *
 * **The ASK is not here.** It lives exactly where iOS's does — the Search tab's primer, raised only
 * after an add of a currently-airing AniList show has STUCK and its Undo window has closed
 * (`ui/discover/DiscoverScreen.kt`). An add never raises the OS dialog itself: it used to arrive
 * unprimed, in the middle of an unrelated action, over the trending grid, with "Added — Undo"
 * counting down underneath a modal the user could not dismiss without answering. The Undo was
 * unreachable for its whole six seconds, screen-reader focus was stolen, and the reflex answer to an
 * unexplained ask is Deny — after which episode alerts are dead for that account.
 */
internal fun canPostAlerts(context: Context): Boolean {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
        ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) !=
        PackageManager.PERMISSION_GRANTED
    ) {
        return false
    }
    return NotificationManagerCompat.from(context).areNotificationsEnabled()
}

// =================================================================================================
// MARK: - The deep link
// =================================================================================================

/*
 * THE TAP ROUTE, and it is the app's ONE open-a-show route.
 *
 * Navigation 3 has no `navDeepLink` — the back stack is this app's own — so there is no URI to
 * register and nothing to parse. The `PendingIntent` carries `ShellIntents.EXTRA_OPEN_DETAIL`,
 * `MainActivity` reads it in `onCreate` (cold start) and through `addOnNewIntentListener` (warm
 * start, which is most taps), and sets `AppModel.pendingOpen` — the same field the capture script's
 * `-e openDetail <id>` sets, so what a QA screenshot photographs is exactly what a user's tap
 * produces and the route cannot rot unnoticed. The shell then selects Today and REPLACES its stack,
 * as iOS's `MainTabView.onChange` does.
 *
 * Three mechanics, none of them optional:
 *
 *   * `MainActivity` must stay `launchMode="singleTop"`. With the default mode a tap on a WARM app
 *     builds a second Activity, `onNewIntent` never fires and nothing happens — while a cold-start
 *     test still passes, because a cold start reads `onCreate`'s intent.
 *   * `FLAG_IMMUTABLE` — mandatory from API 31, and the right default everywhere else: whoever holds
 *     the `PendingIntent` must not be able to fill in the franchise id.
 *   * a DISTINCT request code per show — a `PendingIntent`'s identity ignores extras, so a shared
 *     request code would hand every alert whichever id was written last. `FLAG_UPDATE_CURRENT` then
 *     keeps a re-posted alert for the same show pointing at the same place.
 */

/** Open one show. The tap target of every episode alert. */
internal fun openShowIntent(context: Context, franchiseId: String): PendingIntent {
    val intent = Intent(context, MainActivity::class.java)
        .setAction(Intent.ACTION_VIEW)
        .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        .putExtra(ShellIntents.EXTRA_OPEN_DETAIL, franchiseId)
    return PendingIntent.getActivity(
        context,
        requestCode("open:$franchiseId"),
        intent,
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )
}

/**
 * Open the app, and nothing more specific than that. The tap target of the group summary.
 *
 * A bundle covering four shows must not silently pick one of them, and there is no release-safe
 * "open this tab" route to aim at — `ShellIntents.EXTRA_OPEN_TAB` is parsed only in debug builds, by
 * design, so R8 can delete the whole capture surface from the shipped APK. A plain launch lands on
 * whichever tab the user left the app on, which is the honest answer to "show me all of these".
 */
internal fun openAppIntent(context: Context): PendingIntent {
    val intent = Intent(context, MainActivity::class.java)
        .setAction(Intent.ACTION_MAIN)
        .addCategory(Intent.CATEGORY_LAUNCHER)
        .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
    return PendingIntent.getActivity(
        context,
        requestCode("open:summary"),
        intent,
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )
}

/**
 * A stable, non-negative request code for one `getActivity` slot.
 *
 * These can never collide with the alarm scheduler's `getBroadcast` codes: a `PendingIntent`'s
 * identity includes the target type.
 */
private fun requestCode(key: String): Int = key.hashCode() and 0x7fffffff

// =================================================================================================
// MARK: - Copy
// =================================================================================================

// Every string this feature says lives in `Copy.Alert` (`:model`, `copy/CopyAlerts.kt`): the alert
// itself, the bundle summary, the Android channel's name and description, and the exact-timing ask.
// It was staged here as `AlertCopy` on the argument that a Kotlin object cannot be reopened from
// another module — which never ruled out a sibling object in the catalogue package, and left the
// channel name and description (strings the user reads in system Settings) outside the corpus the
// copy gate walks.


/** Logcat tag for the alert layer. iOS logs the same events under category "alerts". */
internal const val ALERTS_LOG_TAG: String = "Alerts"
