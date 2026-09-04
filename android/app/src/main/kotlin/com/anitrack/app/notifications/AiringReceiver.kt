package com.anitrack.app.notifications

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.service.notification.StatusBarNotification
import android.util.Log
import androidx.compose.ui.graphics.toArgb
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.anitrack.app.R
import com.anitrack.app.design.ThemeColor
import com.anitrack.model.copy.Copy
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/*
 * THE ALARM RECEIVER — where an armed bucket becomes notifications.
 *
 * `AlarmScheduler` arms one alarm per air-time MINUTE (not one per episode) and this is what those
 * alarms point at. It reads the persisted [AiringPlan], posts everything that has become due, and
 * re-arms. It needs no network, no auth session and no `AppModel`: the process it runs in was very
 * often started for this alone.
 *
 * ## Why it posts a RANGE, not the one bucket it was armed for
 *
 * Without the exact-alarm grant — which is the DEFAULT on Android 14+, not the degraded case —
 * `setAndAllowWhileIdle` fires at the system's convenience, and Doze rate-limits an app to roughly
 * one firing every nine minutes. Two buckets a few minutes apart therefore collapse into a single
 * wake-up. Posting only the armed bucket would drop the other one on the floor, silently, for
 * exactly the users whose device is most aggressive about sleeping. So the window is
 * `(armed − one minute, max(armed, the minute that has just passed)]`, and the re-arm afterwards
 * passes that upper bound as `firedBucketAt` so nothing inside it can be armed and announced twice.
 *
 * ## Why the bundle is built here rather than left to the system
 *
 * Anime simulcasts cluster — a dozen shows share one JST slot — so the natural output of a bucket is
 * a burst. Since Android 16 the platform collapses a burst by itself: the first notification at full
 * volume, each subsequent one quieter and visually minimised for up to a minute, all under one
 * banner. The app does not get to choose whether its alerts are bundled; it only gets to choose
 * whether the bundle was designed. This posts an explicit group with an explicit summary — one line
 * per show, one sound, one banner, and a count in the app's own words — instead of nine alerts,
 * eight of them muted, under a header the app never wrote.
 *
 * ## What the summary counts
 *
 * Not this firing. **Everything still live in the group**, read back from the shade and unioned with
 * what is about to be posted. A summary rebuilt from one firing alone would say "2 episodes are out
 * now" over a bundle holding five, an hour after the first three arrived and were left unread.
 *
 * ## Manifest
 *
 * The scheduler addresses it by explicit component, so it needs no intent-filter and must not be
 * exported:
 *
 * ```xml
 * <receiver android:name=".notifications.AiringReceiver" android:exported="false" />
 * ```
 */
class AiringReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_FIRE) return

        val app = context.applicationContext
        val armedAt = intent.getLongExtra(EXTRA_AT, 0L)

        // The `Application` is always constructed before any component of its process, so a cold
        // start for this broadcast has already run `PreviouslyApp.onCreate` and the layer is here.
        // If it somehow is not, `alertsLayer` rebuilds it from the same two seams rather than
        // returning: this receiver used to log and give up, which ends the alarm chain permanently,
        // while `AlarmRearmReceiver` armed directly and skipped the permission gate. One failure
        // mode, and it is the one that keeps the chain alive with the gate intact.
        val alerts = alertsLayer(app)

        // A broadcast's main-thread window is measured in milliseconds; `goAsync` buys the ~10 s a
        // file read, a handful of `notify` calls and a re-arm actually need. `finish()` runs on every
        // path, including a throw — an unfinished result is an ANR waiting for the next low-memory
        // moment, and an exception out of `onReceive` kills the process outright.
        val pending = goAsync()
        receiverScope.launch {
            try {
                // A notification posted to a channel that does not exist is dropped by the platform
                // with nothing but a logcat line, and this process may be seconds old.
                Channels.ensure(app)

                val now = System.currentTimeMillis()
                val window = FiringWindow.of(armedAt, now)

                val plan = alerts.currentPlan()
                val posted = if (plan != null) {
                    postDueAirings(app, plan, window)
                } else {
                    Log.i(ALERTS_LOG_TAG, "alarm fired with no plan on disk")
                    emptyList()
                }

                // What the re-arm must not arm again is what was ANNOUNCED, and **nothing else**.
                //
                // Not `window.through`: that is the minute the alarm arrived in, and a bucket
                // inside it whose episode is still 40 seconds away was deliberately held back —
                // excluding it would mean it was never armed and never announced at all. And not
                // `window.armed` either, which is the same mistake one step earlier: an alarm that
                // arrives a hair before its trigger posts nothing (`FiringWindow.due` requires
                // `atMillis <= now`) yet would have excluded its own bucket from every subsequent
                // re-arm, permanently. `armTargets`' own `it.atMillis > now` filter already covers
                // everything that WAS posted, so this is the narrow belt over it: the latest bucket
                // this firing actually announced, or null when it announced nothing.
                val fired = posted.maxOfOrNull { airingBucket(it.atMillis) }

                // ALWAYS, even when nothing was posted. The alarm that just fired is spent, and the
                // next bucket exists only because something re-arms it — a dropped re-arm here ends
                // the feature until the app is next opened.
                alerts.rearmNow(now = now, firedBucketAt = fired)
            } catch (t: Throwable) {
                Log.w(ALERTS_LOG_TAG, "couldn’t post the airing bucket", t)
            } finally {
                pending.finish()
            }
        }
    }

    companion object {

        /**
         * The alarm the scheduler arms, and the shape it must arm it in:
         *
         * ```kotlin
         * Intent(AiringReceiver.ACTION_FIRE)
         *     .setComponent(ComponentName(packageName, AiringReceiver::class.java.name))
         *     .putExtra(AiringReceiver.EXTRA_AT, bucket)          // airingBucket(at), always
         * PendingIntent.getBroadcast(…, FLAG_UPDATE_CURRENT or FLAG_IMMUTABLE)
         * ```
         *
         * `FLAG_IMMUTABLE` is mandatory from API 31 and correct everywhere: nothing outside this app
         * has any business rewriting an alarm intent.
         */
        const val ACTION_FIRE: String = "com.anitrack.app.alerts.FIRE"

        /**
         * `Long` extra: the bucket instant this alarm was armed for, rounded with [airingBucket].
         *
         * It is the INTENDED instant, never the firing time, and that is what makes a late alarm
         * harmless — matching on the key posts exactly the set that was armed, however late the
         * wake-up came.
         */
        const val EXTRA_AT: String = "com.anitrack.app.alerts.extra.AT"

        /**
         * The group summary's notification id.
         *
         * Reserved: [PlannedAiring.notificationId] never returns it, so the bundle header can never
         * be evicted by an alert nor an alert by the header.
         */
        const val SUMMARY_ID: Int = 1

        /**
         * Process-scoped, not receiver-scoped: a `BroadcastReceiver` instance is discarded the
         * moment `onReceive` returns, so a scope tied to one would cancel the work it just started.
         * `SupervisorJob` so a failure in one firing cannot poison the next.
         */
        private val receiverScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    }
}

// =================================================================================================
// MARK: - The window one firing covers
// =================================================================================================

/**
 * The half-open range of buckets a single firing is responsible for: `(after, through]`, measured at
 * [now].
 *
 * @property armed the bucket key the alarm carried. Always inside the range.
 * @property through the armed bucket, or the last minute that has actually arrived when the alarm
 *   came late — whichever is further on.
 * @property now the firing instant, and the second half of [due]'s test.
 */
internal data class FiringWindow(val armed: Long, val through: Long, val now: Long) {

    /** One minute below [armed], so the armed bucket itself is inside `(after, through]`. */
    val after: Long get() = armed - AIRING_BUCKET_MS

    /**
     * Everything [plan] has made due, soonest episode first.
     *
     * **Two conditions, and the second one is not redundant.** `airingBucket` FLOORS, so a bucket
     * key can be up to 59 seconds before the episodes it names; the scheduler compensates by firing
     * each bucket at the latest air instant inside it, which is exactly why the armed bucket always
     * satisfies `atMillis <= now`. A bucket swept in by a LATE alarm has no such guarantee — the
     * minute that has just arrived may hold an episode 40 seconds from now — and announcing "Episode
     * 12 is out now" before it is out is the one failure this feature cannot afford. An episode held
     * back here is not lost: its own bucket is still armed, and it announces itself on time.
     */
    fun due(plan: AiringPlan): List<PlannedAiring> = plan.airings
        .filter { it.atMillis <= now }
        .filter { airingBucket(it.atMillis) > after && airingBucket(it.atMillis) <= through }
        .sortedBy { it.atMillis }

    companion object {

        /**
         * @param armedAt the bucket the alarm was armed for, or 0 when the extra is missing.
         * @param now the firing instant.
         */
        fun of(armedAt: Long, now: Long): FiringWindow {
            val arrived = airingBucket(now)
            val armed = if (armedAt > 0L) armedAt else arrived
            return FiringWindow(armed = armed, through = maxOf(armed, arrived), now = now)
        }
    }
}

// =================================================================================================
// MARK: - Posting
// =================================================================================================

/** How many lines the summary spells out before the count has to carry the rest. */
private const val SUMMARY_LINES = 6

/**
 * Post everything [window] has made due, as one deliberate bundle.
 *
 * `MissingPermission` is suppressed because [canPostAlerts] is the check lint is asking for — it
 * tests `POST_NOTIFICATIONS` on API 33+ *and* `areNotificationsEnabled()`, which lint does not know
 * about and which is the half that matters below 33.
 *
 * @return what was actually announced, so the caller's re-arm can exclude exactly that and no more.
 */
@SuppressLint("MissingPermission")
internal fun postDueAirings(
    context: Context,
    plan: AiringPlan,
    window: FiringWindow,
): List<PlannedAiring> {
    if (!canPostAlerts(context)) return emptyList()

    val due = window.due(plan).distinctBy { it.notificationId }
    if (due.isEmpty()) return emptyList()

    val manager = NotificationManagerCompat.from(context)
    val byId = plan.airings.associateBy { it.notificationId }

    // What is already in the shade, so the summary counts the BUNDLE rather than this firing.
    val dueIds = due.mapTo(HashSet()) { it.notificationId }
    val live = liveChildren(context).filter { it.id !in dueIds }
    val total = live.size + due.size

    // The lines lead with what just arrived — that is the reason the bundle alerted — and the
    // still-unread earlier drops follow. A live child the plan no longer knows about (the library
    // moved on while it sat unread) falls back to the title it was posted with, so it is never
    // missing from a count that includes it.
    val lines = ArrayList<String>(total)
    due.forEach { lines.add(Copy.Alert.line(it.title, it.episode)) }
    live.forEach { sbn ->
        val planned = byId[sbn.id]
        if (planned != null) {
            lines.add(Copy.Alert.line(planned.title, planned.episode))
        } else {
            val posted = sbn.notification.extras
                .getCharSequence(Notification.EXTRA_TITLE)?.toString()?.trim()
            if (!posted.isNullOrEmpty()) lines.add(posted)
        }
    }

    val summarised = total > 1

    // The summary goes up FIRST, so no child is ever briefly on screen unbundled — and it is the one
    // that makes the sound: `GROUP_ALERT_SUMMARY` on the children means twelve simulcast alerts
    // announce themselves once, in the app's own voice, instead of once per show at descending
    // volume as the platform's cooldown chews through them.
    if (summarised) {
        manager.notify(AiringReceiver.SUMMARY_ID, summaryNotification(context, total, lines))
    } else {
        // Down to one: a bundle header over a single alert is worse than no bundle at all.
        manager.cancel(AiringReceiver.SUMMARY_ID)
    }

    due.forEach { airing ->
        manager.notify(airing.notificationId, childNotification(context, airing, silent = summarised))
    }

    Log.i(
        ALERTS_LOG_TAG,
        "posted ${due.size} alert(s) in (${window.after}, ${window.through}], bundle of $total",
    )
    return due
}

/**
 * One show, one episode.
 *
 * The title is the show — `displayTitle`, the same "Re:ZERO" every row and shelf draws — and the
 * body is the catalogue's one alert sentence. Neither is reworded here.
 */
private fun childNotification(
    context: Context,
    airing: PlannedAiring,
    silent: Boolean,
): Notification = baseBuilder(context)
    .setContentTitle(airing.title)
    .setContentText(Copy.Alert.episodeOut(airing.episode))
    // The stamp is the AIR INSTANT, not the posting time. Without the exact-alarm grant an alert can
    // land minutes late, and a shade that timestamps it "now" would quietly misreport when the
    // episode actually dropped — from the one app whose whole job is saying when things drop.
    .setWhen(airing.atMillis)
    .setShowWhen(true)
    .setContentIntent(openShowIntent(context, airing.franchiseId))
    .setCategory(NotificationCompat.CATEGORY_EVENT)
    .setGroup(Channels.GROUP_EPISODES)
    .setGroupAlertBehavior(
        if (silent) NotificationCompat.GROUP_ALERT_SUMMARY else NotificationCompat.GROUP_ALERT_ALL,
    )
    .build()

/** The bundle header: the count in the app's words, then a line per show. */
private fun summaryNotification(
    context: Context,
    total: Int,
    lines: List<String>,
): Notification {
    val style = NotificationCompat.InboxStyle()
    lines.take(SUMMARY_LINES).forEach { style.addLine(it) }

    return baseBuilder(context)
        .setContentTitle(Copy.Alert.episodesOut(total))
        .setStyle(style)
        .setGroup(Channels.GROUP_EPISODES)
        .setGroupSummary(true)
        // A bundle over four shows must not silently pick one of them; it opens the app.
        .setContentIntent(openAppIntent(context))
        .setCategory(NotificationCompat.CATEGORY_EVENT)
        .build()
}

/**
 * Everything both builders share.
 *
 * The small icon is the brand silhouette — the monochrome layer the themed launcher icon already
 * draws — because a status-bar icon uses only the alpha channel, and that layer is exactly a white
 * mark on transparent. `setColor` is the accent, which the shade uses to tint that icon and the app
 * name: amber as BRAND, one of the three things `CLAUDE.md` still spends it on. No amber *word* is
 * drawn anywhere in the notification, so "amber is not an action colour" is untouched.
 *
 * Visibility is deliberately left at the platform default (`VISIBILITY_PRIVATE`): the title is a
 * show name, and a user who asked the system to hide sensitive content on the lock screen meant this
 * too.
 */
private fun baseBuilder(context: Context): NotificationCompat.Builder =
    NotificationCompat.Builder(context, Channels.EPISODES)
        .setSmallIcon(R.mipmap.ic_launcher_monochrome)
        .setColor(ThemeColor.accent.toArgb())
        .setAutoCancel(true)

/**
 * The episode alerts this app currently has in the shade, summary excluded.
 *
 * There is no equivalent worth porting from iOS — `getDeliveredNotifications` exists there and
 * nothing reads it — and here it is load-bearing: it is the only way to know how big the bundle
 * actually is. Wrapped, because reading the active set is a binder call some OEM builds have been
 * known to refuse, and a bundle header is not worth a crash inside a `BroadcastReceiver`.
 */
private fun liveChildren(context: Context): List<StatusBarNotification> {
    val manager = context.getSystemService(NotificationManager::class.java) ?: return emptyList()
    val active = runCatching { manager.activeNotifications }.getOrNull() ?: return emptyList()
    return active.filter { sbn ->
        sbn.packageName == context.packageName &&
            sbn.id != AiringReceiver.SUMMARY_ID &&
            sbn.notification.group == Channels.GROUP_EPISODES
    }
}
