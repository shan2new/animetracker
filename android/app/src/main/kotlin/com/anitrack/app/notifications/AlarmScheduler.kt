package com.anitrack.app.notifications

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.util.Log
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.anitrack.model.Time
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import java.util.concurrent.TimeUnit

/*
 * # The bucketed alarm scheduler — the `AiringAlarms` seam
 *
 * `EpisodeNotifications.kt` turns a library into an [AiringPlan]; `AiringReceiver` turns a fired
 * bucket into notifications; this arms the alarms in between. It is a REDESIGN of iOS's scheduler,
 * not a translation, and the redesign is forced by three independent platform facts:
 *
 * 1. **Doze rate-limits an app to one `set*AndAllowWhileIdle` firing per nine minutes.** Anime
 *    simulcasts CLUSTER — a dozen shows share one JST slot. Twelve alarms on one instant would be
 *    serialised across ~108 minutes in Doze. One alarm posting twelve notifications is untouched.
 * 2. **Android 16's notification cooldown collapses a burst anyway.** The bundle is going to
 *    happen; `AiringReceiver` builds it deliberately instead of losing the design to the system's
 *    version of it.
 * 3. **The platform throws past 500 concurrent alarms per UID.** Eight is nowhere near it; "one
 *    alarm per episode per show" for a large library walks towards it.
 *
 * So: **one alarm per distinct air-time minute** ([airingBucket]), the soonest [MAX_BUCKETS] inside
 * [ARM_HORIZON_MS]. The round-robin intent survives untouched — the horizon is time-based, so every
 * show inside it is armed and no show's third episode can displace another show's first.
 *
 * ## Eight fixed slots, and why that is the whole cancellation story
 *
 * There is no API that reads an app's armed alarms back, so a scheduler whose request codes come
 * from the air instant can never cancel an alarm whose instant has left the plan — it would need a
 * second persisted list of what it armed, and that list is one crash away from lying to the user
 * about a bell.
 *
 * This one owns exactly [MAX_BUCKETS] `PendingIntent`s at fixed request codes, told apart by a
 * per-slot `data` URI (`Intent.filterEquals` ignores extras, so the URI is what actually
 * distinguishes them — and it makes `adb shell dumpsys alarm` legible). Slot *i* always holds the
 * *i*-th soonest bucket; every re-arm rewrites the slots it needs and **cancels the rest**. The
 * armed set is therefore a pure function of the plan and the clock, and [cancelAll] is total
 * without reading anything at all.
 *
 * ## The trigger time is not the bucket key
 *
 * [airingBucket] rounds **down**, and `AiringReceiver` matches on that key — so the key is what the
 * alarm must CARRY. It is not what the alarm must FIRE AT: a floor-rounded key can be up to 59
 * seconds before the episode, and "Episode 12 is out now" said before it is out is the one failure
 * this feature cannot afford. Each bucket therefore fires at the LATEST air instant inside it and
 * carries the bucket key as [AiringReceiver.EXTRA_AT]. In practice AniList publishes minute-aligned
 * broadcast instants and the two are the same number; this is what keeps them honest when it does
 * not.
 *
 * ## Both exactness branches ship, and the inexact one is the DEFAULT
 *
 * `SCHEDULE_EXACT_ALARM` is declared; **`USE_EXACT_ALARM` never is** — Play policy reserves it for
 * alarm, timer and calendar apps, and declaring it is a review rejection. On Android 14+ at
 * targetSdk 33+ the grant is denied by default, so `setAndAllowWhileIdle` is the normal path, not a
 * degraded one: it still pierces Doze, just not to the minute. The grant is asked for contextually
 * and late — when alerts are turned on for an airing show — once, with a Settings row
 * ([exactAlarmSettingsIntent]) as the way back (`research/product-decisions.md` §4).
 *
 * [canScheduleExact] is checked before every arm **and** `SecurityException` is caught regardless:
 * the grant is revocable at runtime, between the check and the call. Nothing here may throw —
 * `AmbientSync.sync` runs inside the success branch of `reload()`, `setStatus` and
 * `removeFromLibrary`, where an escaping exception rolls back a change the server already accepted.
 *
 * [lastArm] records which branch actually armed, so a Settings row can tell the truth about the
 * precision instead of drawing a bell that claims one the device has not granted.
 *
 * ## Live Updates are NOT scheduled here
 *
 * `research/product-decisions.md` §8 defers them: the T-0 episode notification is the feature and
 * the promoted-ongoing countdown is API 36+ only. There is deliberately no second alarm action.
 *
 * ## Manifest
 *
 * ```xml
 * <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" />
 * <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
 *
 * <!-- Explicit component: no intent-filter, no export. -->
 * <receiver android:name=".notifications.AiringReceiver" android:exported="false" />
 *
 * <!-- Alarms survive neither a reboot, an app update, nor a clock change. -->
 * <receiver android:name=".notifications.AlarmRearmReceiver" android:exported="true">
 *     <intent-filter>
 *         <action android:name="android.intent.action.BOOT_COMPLETED" />
 *         <action android:name="android.intent.action.MY_PACKAGE_REPLACED" />
 *         <action android:name="android.intent.action.TIME_SET" />
 *         <action android:name="android.intent.action.TIMEZONE_CHANGED" />
 *     </intent-filter>
 *     <intent-filter>
 *         <action android:name="android.app.action.SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED" />
 *     </intent-filter>
 * </receiver>
 * ```
 *
 * ## The ceiling, stated rather than mitigated
 *
 * Samsung ships "Put unused apps to sleep" on by default and Xiaomi denies Autostart by default; a
 * **force-stopped app receives no broadcasts at all**, so not even [AlarmRearmReceiver] runs and the
 * alerts stay dead until the user next opens the app. There is no in-app fix. Exact-time local
 * alerts on Android are best-effort, and the app's own screens — derived from `airings`, correct
 * whenever it is open — are the source of truth the user actually relies on.
 */

// ---------------------------------------------------------------------------------------------
// MARK: - The arming policy, as a pure function
// ---------------------------------------------------------------------------------------------

/** One armed alarm: the key it carries, and the instant it fires at. See the file header. */
internal data class ArmTarget(
    /** [airingBucket] of the airings it announces — what `AiringReceiver` matches on. */
    val bucketAt: Long,
    /** The latest air instant inside the bucket, so the alarm can never precede an episode. */
    val triggerAt: Long,
)

/**
 * Which alarms a plan wants armed right now. Pure, so the policy is testable without a device.
 *
 * @param firedBucketAt the bucket an alarm has just fired for, when this runs at the end of a
 *   firing. Its airings are already posted, and excluding them closes the one race `> now` cannot:
 *   an alarm that arrives a millisecond early would otherwise re-arm the bucket it just posted and
 *   announce every one of those episodes twice.
 * @param horizonMs how far ahead to arm. Past it, a re-arm from a freshly derived plan is the right
 *   answer rather than a two-day-old row.
 *
 * The horizon is a budget, **not a cut-off**: when it would leave nothing armed while the plan
 * still holds a future episode, the soonest one is armed anyway. Without that, a device left
 * untouched for three days would have no alarm, and no alarm means no re-arm — the chain that keeps
 * the feature alive between library reloads would end silently.
 */
internal fun AiringPlan.armTargets(
    now: Long,
    firedBucketAt: Long? = null,
    horizonMs: Long = AlarmScheduler.ARM_HORIZON_MS,
    maxBuckets: Int = AlarmScheduler.MAX_BUCKETS,
): List<ArmTarget> {
    val posted = firedBucketAt ?: Long.MIN_VALUE
    val ahead = airings.filter { it.atMillis > now && airingBucket(it.atMillis) > posted }
    if (ahead.isEmpty()) return emptyList()

    val byBucket = ahead.groupBy { airingBucket(it.atMillis) }
    val keys = byBucket.keys.sorted()
    val withinHorizon = keys.filter { it <= now + horizonMs }
    val chosen = (if (withinHorizon.isEmpty()) keys.take(1) else withinHorizon).take(maxBuckets)

    return chosen.map { key ->
        ArmTarget(bucketAt = key, triggerAt = byBucket.getValue(key).maxOf { it.atMillis })
    }
}

// ---------------------------------------------------------------------------------------------
// MARK: - What an arm actually managed to do
// ---------------------------------------------------------------------------------------------

/** The outcome of one [AlarmScheduler.arm]. */
data class ArmResult(
    /** How many alarms are now armed, 0 … [AlarmScheduler.MAX_BUCKETS]. */
    val armed: Int,
    /**
     * Whether **every** armed alarm was armed exactly. False the moment one falls back to
     * `setAndAllowWhileIdle` — which is the default state on Android 14+ — so nothing downstream
     * can claim a precision the device has not granted.
     */
    val exact: Boolean,
    /** How many alerts the plan carries in total, armed or waiting behind the bucket budget. */
    val plannedAlerts: Int,
    /** The soonest armed firing instant, or null when nothing is armed. */
    val nextAt: Long?,
)

// ---------------------------------------------------------------------------------------------
// MARK: - The scheduler
// ---------------------------------------------------------------------------------------------

/**
 * The [AiringAlarms] implementation. Stateless beyond the system services it looks up, so building
 * one per use is fine.
 *
 * @param plans the persisted plan. The scheduler always arms **what the receiver will actually
 *   read** — never an in-memory plan that failed to reach disk.
 */
class AlarmScheduler(
    context: Context,
    private val plans: AiringPlans,
) : AiringAlarms {

    private val app: Context = context.applicationContext
    private val alarms: AlarmManager? = app.getSystemService(AlarmManager::class.java)

    /**
     * The last arm's outcome, for a Settings row that has to say whether reminders are approximate.
     * Process-scoped and best-effort — it is a diagnostic, never the source of truth for what is
     * armed (that is the plan plus the clock).
     */
    @Volatile
    var lastArm: ArmResult? = null
        private set

    // -----------------------------------------------------------------------------------------
    // MARK: - AiringAlarms
    // -----------------------------------------------------------------------------------------

    override suspend fun rearm(now: Long) {
        arm(now = now)
    }

    /**
     * The re-arm at the end of a firing, with the bucket that was just ANNOUNCED excluded.
     *
     * The interface's default falls through to [rearm], which drops [firedBucketAt] on the floor —
     * so without this override the exclusion `AiringReceiver` computes was discarded before it
     * reached [armTargets], and the guard it documents was in force nowhere in production. Only the
     * test exercised the parameter, which is to say the test passed over dead code.
     */
    override suspend fun rearmAfterFiring(now: Long, firedBucketAt: Long) {
        arm(now = now, firedBucketAt = firedBucketAt)
    }

    /** Drop every alarm this app owns. Total and stateless — there are only [MAX_BUCKETS] of them. */
    override fun cancelAll() {
        for (slot in 0 until MAX_BUCKETS) cancelSlot(slot)
        lastArm = ArmResult(armed = 0, exact = canScheduleExact(), plannedAlerts = 0, nextAt = null)
    }

    /**
     * [rearm], reporting what it did.
     *
     * @param firedBucketAt see [armTargets] — pass the bucket key when re-arming at the end of a
     *   firing.
     */
    suspend fun arm(
        now: Long = System.currentTimeMillis(),
        firedBucketAt: Long? = null,
    ): ArmResult {
        val plan = plans.read()
        return applyTargets(plan, now, firedBucketAt)
    }

    private fun applyTargets(plan: AiringPlan?, now: Long, firedBucketAt: Long?): ArmResult {
        val targets = plan?.armTargets(now = now, firedBucketAt = firedBucketAt).orEmpty()
        if (targets.isEmpty()) {
            cancelAll()
            val result = ArmResult(
                armed = 0,
                exact = canScheduleExact(),
                plannedAlerts = plan?.airings?.size ?: 0,
                nextAt = null,
            )
            lastArm = result
            return result
        }

        warnIfReceiverMissing()
        val exactAllowed = canScheduleExact()

        var armed = 0
        var exact = true
        for (slot in 0 until MAX_BUCKETS) {
            val target = targets.getOrNull(slot)
            if (target == null) {
                cancelSlot(slot)
                continue
            }
            when (armSlot(slot, target, exactAllowed)) {
                Armed.EXACT -> armed += 1
                Armed.INEXACT -> {
                    armed += 1
                    exact = false
                }
                Armed.FAILED -> exact = false
            }
        }

        val result = ArmResult(
            armed = armed,
            exact = exact,
            plannedAlerts = plan?.airings?.size ?: 0,
            nextAt = targets.firstOrNull()?.triggerAt,
        )
        lastArm = result
        Log.i(ALERTS_LOG_TAG, "armed $result")
        return result
    }

    // -----------------------------------------------------------------------------------------
    // MARK: - The exact-alarm grant
    // -----------------------------------------------------------------------------------------

    /**
     * Whether `setExactAndAllowWhileIdle` is permitted **right now**.
     *
     * Below API 31 there is no permission to hold. From 31 the user owns the answer and can change
     * it at any moment, which is why every arm catches `SecurityException` as well as asking.
     */
    fun canScheduleExact(): Boolean {
        // The early return is what keeps an API-31 call off a minSdk-26 device. Deliberately not
        // inside a lambda: a version guard the API checker cannot follow is a guard that has to be
        // argued about in review.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        val am = alarms ?: return false
        return try {
            am.canScheduleExactAlarms()
        } catch (e: Exception) {
            Log.w(ALERTS_LOG_TAG, "canScheduleExactAlarms threw; assuming denied", e)
            false
        }
    }

    /**
     * The system page that grants "Alarms & reminders", or null below API 31 where there is nothing
     * to grant. There is no in-app dialog for this permission — a deep link to Settings is the only
     * route the platform offers.
     */
    fun exactAlarmSettingsIntent(): Intent? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return null
        return Intent(ACTION_REQUEST_SCHEDULE_EXACT_ALARM)
            .setData(Uri.fromParts("package", app.packageName, null))
    }

    // -----------------------------------------------------------------------------------------
    // MARK: - Slots
    // -----------------------------------------------------------------------------------------

    private enum class Armed { EXACT, INEXACT, FAILED }

    private fun armSlot(slot: Int, target: ArmTarget, exactAllowed: Boolean): Armed {
        val am = alarms ?: return Armed.FAILED
        val pending = pendingIntent(slot, target.bucketAt, PendingIntent.FLAG_UPDATE_CURRENT)
            ?: return Armed.FAILED

        // RTC_WAKEUP, not ELAPSED_REALTIME: an air time is a wall-clock instant from the server, and
        // the alarm has to move with the clock — which is also why TIME_SET and TIMEZONE_CHANGED
        // re-arm.
        if (exactAllowed) {
            try {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, target.triggerAt, pending)
                return Armed.EXACT
            } catch (e: SecurityException) {
                // Revoked between the check and the call. Not an error the user needs to see: the
                // inexact branch below is a correct product, just a less precise one.
                Log.i(ALERTS_LOG_TAG, "exact alarm denied at arm time; falling back", e)
            }
        }

        return try {
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, target.triggerAt, pending)
            Armed.INEXACT
        } catch (e: Exception) {
            // The platform throws IllegalStateException past 500 concurrent alarms per UID. Eight
            // slots can never reach it; this exists so nothing out of AlarmManager can escape into
            // AmbientSync and be misread as a library failure.
            Log.w(ALERTS_LOG_TAG, "couldn’t arm slot $slot for ${target.triggerAt}", e)
            Armed.FAILED
        }
    }

    private fun cancelSlot(slot: Int) {
        val am = alarms ?: return
        // FLAG_NO_CREATE: null means nothing is armed in this slot, which is the common case.
        val pending = pendingIntent(slot, bucketAt = 0L, flags = PendingIntent.FLAG_NO_CREATE)
            ?: return
        runCatching {
            am.cancel(pending)
            pending.cancel()
        }
    }

    /**
     * `FLAG_IMMUTABLE` is mandatory from API 31 and correct everywhere: nothing outside this app has
     * any business rewriting an alarm intent.
     *
     * The per-slot `data` URI is what actually distinguishes the eight `PendingIntent`s —
     * `Intent.filterEquals` ignores extras, so two slots sharing an action and a component would
     * otherwise differ only by request code.
     */
    private fun pendingIntent(slot: Int, bucketAt: Long, flags: Int): PendingIntent? {
        val intent = Intent(app, AiringReceiver::class.java)
            .setAction(AiringReceiver.ACTION_FIRE)
            .setData(Uri.parse("$SLOT_SCHEME://bucket/$slot"))
            .putExtra(AiringReceiver.EXTRA_AT, bucketAt)
        return PendingIntent.getBroadcast(
            app,
            REQUEST_BUCKET_BASE + slot,
            intent,
            flags or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    /**
     * One loud log if the alarm receiver is not declared in the manifest.
     *
     * An explicit-component `PendingIntent` at an undeclared receiver arms happily and fires into
     * nothing — a silent, permanent loss of the whole feature, and the manifest is the one part of
     * this that the compiler does not check.
     */
    private fun warnIfReceiverMissing() {
        if (receiverChecked) return
        receiverChecked = true
        val component = ComponentName(app, AiringReceiver::class.java)
        val present = runCatching { app.packageManager.getReceiverInfo(component, 0) }.isSuccess
        if (!present) {
            Log.e(
                ALERTS_LOG_TAG,
                "AiringReceiver is not declared in the manifest — every episode alarm will fire " +
                    "into nothing. See the manifest block in AlarmScheduler.kt.",
            )
        }
    }

    @Volatile
    private var receiverChecked = false

    companion object {

        /**
         * The alarm budget. Eight buckets is far below the platform's 500-alarm-per-UID ceiling, and
         * far above "one alarm at a time", where a single dropped re-arm ends the feature forever.
         */
        const val MAX_BUCKETS: Int = 8

        /**
         * How far ahead alarms are armed. A budget rather than a cut-off — see [armTargets].
         *
         * 48 hours is the research note's window and it is generous: every re-arm trigger (a
         * library change, app foreground, boot, package replace, a grant change, and the firing of
         * any armed alarm) refreshes the set long before it runs out.
         */
        const val ARM_HORIZON_MS: Long = 48L * Time.HOUR_MS

        /** Distinguishes the eight `PendingIntent`s. Matches no intent-filter anywhere, by design. */
        private const val SLOT_SCHEME: String = "previously-alarm"

        /**
         * Broadcast `PendingIntent` request codes, `REQUEST_BUCKET_BASE + slot`. `PendingIntent`
         * identity includes the target type, so these cannot collide with the `getActivity` codes
         * the notification tap route derives from `episode-<mediaId>-<episode>`.
         */
        private const val REQUEST_BUCKET_BASE: Int = 0x5000

        /**
         * `Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM` (API 31), written out so nothing in this
         * file names an API-gated symbol at minSdk 26.
         */
        const val ACTION_REQUEST_SCHEDULE_EXACT_ALARM: String =
            "android.settings.REQUEST_SCHEDULE_EXACT_ALARM"

        /**
         * `AlarmManager.ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED` (API 31), same reason.
         * It fires when the user grants **or** revokes "Alarms & reminders"; both re-arm, which is
         * how the armed set is upgraded to exact — or honestly downgraded — without the app being
         * opened.
         */
        const val ACTION_EXACT_ALARM_STATE_CHANGED: String =
            "android.app.action.SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED"

        /** The scheduler a cold process builds for itself: no graph, no session, no network. */
        fun from(context: Context): AlarmScheduler =
            AlarmScheduler(context, AiringPlanStore.from(context))
    }
}

// ---------------------------------------------------------------------------------------------
// MARK: - The layer a receiver reaches for
// ---------------------------------------------------------------------------------------------

/**
 * [EpisodeNotifications.current], or a stand-in built from the same two seams.
 *
 * The branch is unreachable while `PreviouslyApp.onCreate` runs before any component — which it
 * always does — but the two receivers used to DISAGREE about what to do if it ever were: this one
 * fell back to `AlarmScheduler.from(app).arm()`, which bypasses the notification-permission gate
 * entirely and arms wake-ups for a user who has alerts switched off, while [AiringReceiver] logged
 * and returned *without* re-arming, ending the alarm chain permanently. One failure mode, and it is
 * this one: rebuild the layer, so the permission still decides whether anything is armed and the
 * chain still continues. `install` is idempotent — it also makes sure the channel exists, which a
 * cold process wants anyway.
 */
internal fun alertsLayer(context: Context): EpisodeNotifications {
    val app = context.applicationContext
    return EpisodeNotifications.current ?: EpisodeNotifications.install(
        context = app,
        plans = AiringPlanStore.from(app),
        alarms = AlarmScheduler.from(app),
    )
}

// ---------------------------------------------------------------------------------------------
// MARK: - Re-arming from outside the app
// ---------------------------------------------------------------------------------------------

// ---------------------------------------------------------------------------------------------
// MARK: - The safety nets
// ---------------------------------------------------------------------------------------------

/**
 * The two re-arms that are not events: a **daily** unique periodic job, and the app's own
 * **foreground**.
 *
 * `research/§1.5` and `§3.9` specify both, and neither existed — the armed set was recovered only by
 * an alarm actually firing, by a library reload, or by one of [AlarmRearmReceiver]'s five
 * broadcasts. Which is enough right up until an OEM silently drops the alarms: Samsung's "Put
 * unused apps to sleep" and Xiaomi's power manager do exactly that, and the eight-slot budget is no
 * redundancy at all against it — the slots are cancelled and re-armed together, so they are lost
 * together. Without a net the feature stayed dead until the app was next opened, and it re-armed
 * then only if a library reload happened to succeed.
 *
 * **`sceneBecameActive` is not that net.** `AppModel` reloads on foreground only after
 * `STALE_RELOAD_AFTER` (two minutes) away, and a trip to the system notification screen and back is
 * shorter than that — which is precisely the moment a user has just switched alerts ON.
 *
 * The job re-arms from the persisted plan alone: no network, no session, no `AppModel`. It cannot
 * refresh a stale plan and does not try; the app's next foreground does that.
 *
 * A **force-stopped** app receives no broadcasts and runs no work, so this does not lift the
 * ceiling `AlarmScheduler`'s header states — it covers the far more common case where the app is
 * merely asleep.
 */
object AiringRearm {

    /** Namespaced, so no blanket sweep can take it — or Glance's own sessions — with it. */
    private const val PERIODIC_WORK = "previously.alerts.rearm-airing-alarms"

    private const val PERIOD_HOURS = 24L

    /**
     * Install the periodic net. Idempotent: `KEEP` leaves an already-enqueued schedule alone, so
     * this is safe to call on every app start.
     *
     * **No constraints.** A re-arm reads one small file and talks to `AlarmManager`; requiring
     * connectivity or a charger would strand it on exactly the device that lost its alarms.
     */
    fun schedule(context: Context) {
        val app = context.applicationContext
        runCatching {
            WorkManager.getInstance(app).enqueueUniquePeriodicWork(
                PERIODIC_WORK,
                ExistingPeriodicWorkPolicy.KEEP,
                PeriodicWorkRequestBuilder<AiringRearmWorker>(PERIOD_HOURS, TimeUnit.HOURS).build(),
            )
        }.onFailure { Log.w(ALERTS_LOG_TAG, "couldn’t schedule the daily re-arm", it) }
    }

    /**
     * The app came to the foreground. Cheap and idempotent — it re-arms what the plan on disk
     * implies, and stands the alarms down if the notification permission has gone away since.
     */
    fun onForeground(context: Context) {
        val app = context.applicationContext
        scope.launch {
            runCatching { alertsLayer(app).rearmNow() }
                .onFailure { Log.w(ALERTS_LOG_TAG, "couldn’t re-arm on foreground", it) }
        }
    }

    /** Process-scoped: nothing here belongs to a composition or an Activity. */
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
}

/** The daily net's worker. It re-arms from the plan and reports success either way. */
class AiringRearmWorker(
    appContext: Context,
    params: WorkerParameters,
) : CoroutineWorker(appContext, params) {

    override suspend fun doWork(): Result {
        runCatching { alertsLayer(applicationContext).rearmNow() }
            .onFailure { Log.w(ALERTS_LOG_TAG, "the daily re-arm failed", it) }
        // Never `retry()`: the next run is a day away and a failed arm is not a transient fetch.
        return Result.success()
    }
}

/**
 * The five broadcasts that invalidate the armed set, and the only thing standing between episode
 * alerts and a reboot.
 *
 * * `BOOT_COMPLETED` — the platform clears every alarm on reboot.
 * * `MY_PACKAGE_REPLACED` — and on an app update.
 * * `TIME_SET` / `TIMEZONE_CHANGED` — the alarms are `RTC_WAKEUP` wall-clock instants, which is
 *   right (an air time *is* a wall-clock fact from the server), so a clock or zone change moves
 *   what "19:30" means.
 * * `SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED` — the grant flipped; re-arming upgrades the set
 *   to exact, or downgrades it honestly.
 *
 * It re-arms **from the persisted plan alone** — no network, no auth, no `AppModel`. Nothing here
 * rebuilds the plan: a device that has been off for three days holds a stale one, and the app's next
 * foreground is what refreshes it.
 *
 * It goes through [EpisodeNotifications] — [alertsLayer], so the notification permission decides
 * whether anything is armed at all even on the impossible path where `Application.onCreate` has not
 * run.
 *
 * `BOOT_COMPLETED` arrives after the user unlocks (this receiver is not direct-boot aware), so
 * `filesDir` is readable by the time it runs.
 *
 * **Divergence:** `docs/android-port/PLAN.md` calls this `notify/RearmReceiver.kt`. It lives here
 * because re-arming needs the plan and the scheduler and nothing from the posting layer.
 */
class AlarmRearmReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        if (action !in REARM_ACTIONS) return

        val app = context.applicationContext
        // A `BroadcastReceiver` instance is discarded the moment `onReceive` returns, so `goAsync`
        // is what buys the disk read and the arm the time they need. `finish()` runs on every path,
        // including a throw: an unfinished result is an ANR waiting for the next low-memory moment.
        val pending = goAsync()
        receiverScope.launch {
            try {
                alertsLayer(app).rearmNow()
                Log.i(ALERTS_LOG_TAG, "re-armed on $action")
            } catch (e: Throwable) {
                // A receiver that throws kills the process. Nothing here is worth that.
                Log.w(ALERTS_LOG_TAG, "couldn’t re-arm on $action", e)
            } finally {
                pending.finish()
            }
        }
    }

    private companion object {

        val REARM_ACTIONS: Set<String> = setOf(
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED,
            AlarmScheduler.ACTION_EXACT_ALARM_STATE_CHANGED,
        )

        /** Process-scoped: a scope tied to the receiver would cancel the work it just started. */
        val receiverScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    }
}
