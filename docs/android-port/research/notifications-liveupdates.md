# Scheduled episode alerts & the Live Activity equivalent — Android

**Researched 2026-09-04.** Targets the port's settled toolchain (`docs/android-port/research/compose-architecture.md`):
**minSdk 31 · targetSdk 36 · compileSdk 37**, Compose BOM 2026.08.00, Navigation 3 1.1.7, Hilt 2.60.1,
WorkManager available. Android 17 (API 37) shipped **16 Jun 2026**; Android 16 (API 36) shipped
**10 Jun 2025**.

The iOS behaviour being reproduced (`ios/Sources/Notifications/`):

| iOS | What it does |
|---|---|
| `EpisodeNotifications.sync(library:now:)` | Rebuilds the whole pending set: up to **3 alerts per watching AniList show** from `part.airings`, **round-robin** (every show gets its soonest before any gets its second), capped at 48 (iOS's 64-pending limit). Full clear + re-add = idempotent. |
| `ForegroundPresenter` | Presents the alert even when the app is frontmost; a tap reads `threadIdentifier` (the franchise id) → `AppModel.pendingOpen` → Today tab + push Detail. |
| `requestPermissionIfNeeded()` | Asks **late**, when an airing show is added — not at first launch. |
| `AiringLiveActivityManager` | ONE Live Activity for the soonest watching-show episode inside a **60-min lead window**, lingering **15 min** past air time. The countdown ticks natively in the widget (`Text(timerInterval:)`) — no updates needed while backgrounded. |
| `cancelAll()` / `endAll()` | Sign-out wipes everything; the schedule belongs to one account's library. |

---

## 1. Recommendation (up front)

### 1.1 Scheduling — `AlarmManager.setExactAndAllowWhileIdle`, one alarm per *air-time bucket*

**Do not port "N pending notifications" one-for-one.** Schedule **one exact alarm per distinct air
instant** (rounded to the minute), covering the next **8 buckets inside a 48-hour horizon**, and let
the receiver post *all* the notifications due in that bucket. Three independent facts force this:

1. **Doze rate limit.** Official wording: *"Neither `setAndAllowWhileIdle()` nor
   `setExactAndAllowWhileIdle()` can fire alarms more than once per nine minutes, per app."*
   ([Doze and App Standby](https://developer.android.com/training/monitoring-device-state/doze-standby))
   Anime simulcasts **cluster** — a dozen shows share one JST slot. Twelve separate alarms at the
   same instant would be serialised across ~108 minutes in Doze. One alarm, twelve notifications, is
   not affected at all.
2. **Android 16 notification cooldown**, on by default since Android 16 stable (10 Jun 2025): a burst
   from one app gets the first notification at full volume/banner and each subsequent one
   progressively quieter and visually minimised for up to a minute, bundled under a single banner.
   A burst is *already* going to be collapsed by the system — so build the bundle deliberately
   (`setGroup` + a group summary) instead of losing the design to the system's version of it.
3. **Alarm quota.** The platform throws `IllegalStateException("Maximum limit of concurrent alarms
   500 reached for uid …")` past 500 alarms per UID. 8 buckets is not near it, but "one alarm per
   episode per show" for a 200-show library is.

Bucketing also preserves the round-robin *intent* — the horizon is time-based, so every show inside
48 hours is armed, and no show's third episode displaces another show's first.

**Permission: declare `SCHEDULE_EXACT_ALARM`, never `USE_EXACT_ALARM`.** Google Play policy limits
`USE_EXACT_ALARM` (auto-granted, non-revocable) to apps *"whose core, user-facing functionality
requires precisely-timed actions, such as dedicated alarm, timer, or calendar applications."* An
episode-drop notifier is not that; declaring it is a review rejection.
([Play Console: Permissions and APIs that Access Sensitive Information](https://support.google.com/googleplay/android-developer/answer/16558241))

Consequence, and it is the single biggest behavioural difference from iOS: **on Android 14+ devices
`SCHEDULE_EXACT_ALARM` is denied by default** for apps targeting API 33+
([Android 14 change](https://developer.android.com/about/versions/14/changes/schedule-exact-alarms)).
So the app must be **correct without it**: fall back to `setAndAllowWhileIdle()` (still fires in
Doze, just not to the minute), and surface exactly one quiet Settings row that opens
`Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM`. Never gate the feature behind a nag.

### 1.2 `POST_NOTIFICATIONS` — ask late, at the same moment iOS does

Runtime permission since Android 13 (API 33). minSdk is 31, so it is `SDK_INT >= 33` gated. Ask when
an airing show is added — the iOS trigger — not at launch. Because targetSdk ≥ 33, the app controls
when the dialog appears. ([Notification runtime permission](https://developer.android.com/develop/ui/views/notifications/notification-permission))

### 1.3 Deep link — intent extra, not a URI

Navigation 3 has no `navDeepLink`; the back stack is yours. So: `PendingIntent.getActivity` →
`MainActivity` (`launchMode="singleTop"`) carrying `EXTRA_FRANCHISE_ID`, read in `onCreate` (cold
start) **and** through `addOnNewIntentListener` (warm start), pushed into `AppModel.pendingOpen`,
which the `LaunchedEffect(model.pendingOpen)` already sketched in `compose-architecture.md` §9.3
turns into `switchTo(TodayKey)` + `push(DetailKey(id))`. Zero new navigation machinery.

### 1.4 Live Activity equivalent — a **Live Update** notification, no foreground service

The closest thing is Android 16's **Live Updates**: an ongoing notification the system *promotes*
to the top of the shade, the lock screen, and a **status-bar chip**.
([Live Update guide](https://developer.android.com/develop/ui/views/notifications/live-update) ·
[Compose guide](https://developer.android.com/develop/ui/compose/notifications/live-update))

The important find: **`setWhen(airsAtMillis) + setUsesChronometer(true) + setChronometerCountDown(true)`
makes the system tick the countdown with the app process dead** — the exact analogue of SwiftUI's
`Text(timerInterval:)` in the Live Activity widget. So the whole thing is:

- a **T-60min alarm** posts the promoted ongoing notification (matching `leadWindow`),
- `setTimeoutAfter(75 min)` auto-cancels it (matching `linger` — 60 + 15),
- **no foreground service, no periodic updates, no process kept alive.**

That matters: Android 14+ requires every foreground service to declare a *type*, and none of the
declared types fits "counting down to a TV episode". Avoiding the FGS is not just cheaper — it is
the only compliant route.

Gate on `SDK_INT >= 36` **and** `NotificationManager.canPostPromotedNotifications()`. Below that,
post nothing extra. Do **not** ship a plain ongoing notification as a "fallback Live Activity" — an
un-promoted ongoing notification is a permanent line in the shade with none of the payoff, and since
Android 14 the user can swipe it away anyway.

Reach is real: **Samsung One UI 8 ingests the standard Live Updates API into the Now Bar**, so one
implementation lights up Pixel status-bar chips and Galaxy lock screens
([Android Authority, One UI 8 Live Updates](https://www.androidauthority.com/one-ui-8-live-updates-support-3573794/) ·
[Android Police, 13 Aug 2026](https://www.androidpolice.com/nobody-is-using-live-updates/)).

### 1.5 The one-line version

> Persist an **airing plan** whenever the library reloads. Arm **one exact alarm per air-time
> bucket** (≤ 8, ≤ 48 h out) plus **one Live-Update alarm at T-60 min**. The receiver reads only the
> plan, posts a **grouped** set of notifications, and re-arms. Re-arm again on boot, package replace,
> time/timezone change, exact-alarm-permission change, app foreground, and from a **daily WorkManager
> safety net**. Degrade to inexact alarms when the exact-alarm permission is absent. Live Updates are
> API 36+ only and self-ticking.

---

## 2. Evidence

| Claim | Source | Date |
|---|---|---|
| `setExactAndAllowWhileIdle` / `setAndAllowWhileIdle` fire at most **once per 9 minutes per app** in Doze; standard alarms defer to the maintenance window; `setAlarmClock()` alarms fire normally and the system exits Doze shortly before them | [Optimize for Doze and App Standby](https://developer.android.com/training/monitoring-device-state/doze-standby) | fetched 2026-09-04 |
| Doze also suspends network, ignores wake locks, and blocks `JobScheduler` **including WorkManager** | ibid. | " |
| `SCHEDULE_EXACT_ALARM` vs `USE_EXACT_ALARM`; `canScheduleExactAlarms()`; `ACTION_REQUEST_SCHEDULE_EXACT_ALARM`; `ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED`; alarms do not survive reboot | [Schedule alarms](https://developer.android.com/develop/background-work/services/alarms/schedule) | " |
| On **Android 14+**, `SCHEDULE_EXACT_ALARM` is **denied by default** for apps targeting API 33+ that are not calendar/alarm-clock apps; exemptions are platform-signed, privileged, power-allowlisted, or `SYSTEM_WELLBEING` role holders | [Schedule exact alarms are denied by default](https://developer.android.com/about/versions/14/changes/schedule-exact-alarms) | " |
| `USE_EXACT_ALARM` is restricted by Play policy to *"dedicated alarm, timer, or calendar applications"*; Play Console declaration required; non-qualifying apps are rejected | [Play Console: sensitive permissions](https://support.google.com/googleplay/android-developer/answer/16558241) | " |
| `SecurityException` if `setExact()`, `setExactAndAllowWhileIdle()` **or `setAlarmClock()`** is called without the exact-alarm permission on API 31+ | [Esper: Android 13 exact alarm restrictions](https://www.esper.io/blog/android-13-exact-alarm-api-restrictions) · AlarmManager reference | 2022 / current |
| 500 concurrent alarms per UID ⇒ `IllegalStateException` | [paho.mqtt.android#468](https://github.com/eclipse-paho/paho.mqtt.android/issues/468) (platform-thrown message) | ongoing |
| `POST_NOTIFICATIONS` runtime permission, API 33+; app controls dialog timing at targetSdk 33+; `areNotificationsEnabled()`; exemptions (media sessions, `MANAGE_OWN_CALLS`) | [Notification runtime permission](https://developer.android.com/develop/ui/views/notifications/notification-permission) | fetched 2026-09-04 |
| Live Update requirements: Standard / `BigTextStyle` / `CallStyle` / `ProgressStyle` / `MetricStyle`; `POST_PROMOTED_NOTIFICATIONS`; `setRequestPromotedOngoing(true)`; `FLAG_ONGOING_EVENT`; `contentTitle` set; **no** `RemoteViews`; not a group summary; not colorized; channel not `IMPORTANCE_MIN`. Surfaces: top of the shade, lock screen, **status-bar chip**. `canPostPromotedNotifications()`, `hasPromotableCharacteristics()`, `FLAG_PROMOTED_ONGOING`, `Settings.ACTION_MANAGE_APP_PROMOTED_NOTIFICATIONS`. **OEMs may enforce additional eligibility criteria.** | [Create a Live Update notification](https://developer.android.com/develop/ui/views/notifications/live-update) | " |
| Status-chip APIs: `setShortCriticalText()`, `setWhen()`, `setUsesChronometer()`, `setChronometerCountDown()`, `setShowWhen(false)`, `setDeleteIntent()` | ibid. | " |
| `Notification.ProgressStyle` with `Segment`/`Point`, `setProgressTrackerIcon`, `setStyledByProgress` — aimed at rideshare / delivery / navigation | [Progress-centric notifications](https://developer.android.com/about/versions/16/features/progress-centric-notifications) | " |
| `NotificationCompat.ProgressStyle` + `NotificationCompat.Builder.setRequestPromotedOngoing()` added in **androidx.core 1.17.0-alpha01 (18 Jun 2025)**; `MetricStyle` + semantic styles added in **1.18.0-alpha01 (14 Jan 2026)**; latest stable **1.19.0 (3 Jun 2026)** | [androidx.core release notes](https://developer.android.com/jetpack/androidx/releases/core) | " |
| Android 17 adds `Notification.MetricStyle` (up to 3 metrics: label/value/unit; AOD + lock screen + status bar) and **semantic colouring** (`SEMANTIC_STYLE_INFO/SAFE/CAUTION/DANGER`, `Notification.createSemanticStyleAnnotation`) | [Android 17 features](https://developer.android.com/about/versions/17/features) · [Android Authority](https://www.androidauthority.com/android-17-live-updates-metric-style-template-3669117/) | 2026 |
| Android 17 adds an `OnAlarmListener`+`Executor` overload of `setExactAndAllowWhileIdle` (no `PendingIntent`, fewer wake locks) | [Android 17 features](https://developer.android.com/about/versions/17/features) | 2026 |
| Android 17 all-apps behaviour changes contain **no** notification/alarm regressions relevant here (memory limits, SMS OTP, keystore, cross-profile loopback, background *audio* hardening) | [Behavior changes: all apps (Android 17)](https://developer.android.com/about/versions/17/behavior-changes-all) | fetched 2026-09-04 |
| Android 16 **notification cooldown** is on by default: bursts get progressively lowered volume and visual minimisation for up to a minute, bundled under one banner | [PushEngage analysis](https://www.pushengage.com/android-notification-cooldown/) · Android 16 behaviour changes | 2025–26 |
| **Android 14 made `FLAG_ONGOING_EVENT` notifications user-dismissible** | [Behavior changes: all apps (Android 14)](https://developer.android.com/about/versions/14/behavior-changes-all) | 2023 |
| One UI 8 opens the **Now Bar** to any app via the standard Live Updates API (was Samsung-first-party-only) | [Android Authority](https://www.androidauthority.com/one-ui-8-live-updates-support-3573794/) · [Android Police](https://www.androidpolice.com/nobody-is-using-live-updates/) | 2025–2026-08-13 |
| WorkManager: **15-minute minimum** periodic interval, `setInitialDelay` is a *minimum*, expedited work is quota-limited, and **exact execution time is not guaranteed** | [Define work](https://developer.android.com/develop/background-work/background-tasks/persistent/getting-started/define-work) | fetched 2026-09-04 |
| Alarms are cleared on reboot; a **force-stopped** app receives no broadcasts (including `BOOT_COMPLETED`) until the user launches it again | [Schedule alarms](https://developer.android.com/develop/background-work/services/alarms/schedule) · long-standing platform behaviour | " |
| Field report: `setAlarmClock()` + boot receiver + WorkManager recovery + OEM education eliminated user reports of missed notifications; Xiaomi needs autostart, Samsung needs app-sleep exclusions | [nek12.dev, *How to make Android notifications 100% reliable*, 6 Nov 2025](https://nek12.dev/blog/en/how-to-make-android-notifications-100-reliable/) | 2025-11-06 |
| `PendingIntent` must be `FLAG_IMMUTABLE` (or `FLAG_MUTABLE`) on API 31+; `TaskStackBuilder` for regular activities | [Start an Activity from a notification](https://developer.android.com/develop/ui/views/notifications/navigation) | fetched 2026-09-04 |

**Where sources disagree:** the Compose Live Update page says *"use androidx.core 1.10.0 or higher"*
while the core release notes place `setRequestPromotedOngoing` in **1.17.0-alpha01**. The release
notes win — **require `androidx.core ≥ 1.17.0`; use 1.19.0.** Also, `setShortCriticalText` is
documented on the guide pages but does **not** appear in the androidx.core release notes I read;
treat its presence in `NotificationCompat.Builder` as **unverified** and check against 1.19.0
sources before relying on it (fall back to the platform `Notification.Builder` behind an
`SDK_INT >= 36` gate if it is platform-only).

---

## 3. Config an engineer can paste

### 3.1 `AndroidManifest.xml`

```xml
<!-- Alerts (API 33+ runtime permission; harmless on 31/32) -->
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />

<!-- Exact alarms. SCHEDULE_EXACT_ALARM, *not* USE_EXACT_ALARM: Play policy limits
     USE_EXACT_ALARM to alarm/timer/calendar apps and would reject this app. -->
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" />

<!-- Live Updates (Android 16+). Normal permission, no runtime prompt. -->
<uses-permission android:name="android.permission.POST_PROMOTED_NOTIFICATIONS" />

<!-- Re-arm alarms after a reboot; the platform clears them. -->
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />

<application …>
    <activity
        android:name=".MainActivity"
        android:launchMode="singleTop"          <!-- notification taps reuse the task -->
        android:exported="true">
        <intent-filter>
            <action android:name="android.intent.action.MAIN" />
            <category android:name="android.intent.category.LAUNCHER" />
        </intent-filter>
    </activity>

    <receiver android:name=".alerts.AiringAlarmReceiver" android:exported="false" />

    <receiver android:name=".alerts.RearmReceiver" android:exported="true">
        <intent-filter>
            <action android:name="android.intent.action.BOOT_COMPLETED" />
            <action android:name="android.intent.action.MY_PACKAGE_REPLACED" />
            <action android:name="android.intent.action.TIME_SET" />
            <action android:name="android.intent.action.TIMEZONE_CHANGED" />
        </intent-filter>
        <intent-filter>
            <!-- API 31+: fires when the user grants/revokes "Alarms & reminders" -->
            <action android:name="android.app.action.SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED" />
        </intent-filter>
    </receiver>
</application>
```

`libs.versions.toml`:

```toml
androidxCore = "1.19.0"   # >= 1.17.0 for NotificationCompat.ProgressStyle + setRequestPromotedOngoing
workManager  = "2.10.5"   # VERIFY current stable at implementation time
```

### 3.2 Channels — created once, at `Application.onCreate()`

```kotlin
object Channels {
    const val EPISODES  = "episodes"   // "Episode is out" alerts
    const val COUNTDOWN = "countdown"  // the Live Update

    fun ensure(context: Context) {
        val nm = NotificationManagerCompat.from(context)
        nm.createNotificationChannel(
            NotificationChannelCompat.Builder(EPISODES, NotificationManagerCompat.IMPORTANCE_HIGH)
                .setName(context.getString(R.string.channel_episodes))          // "New episodes"
                .setDescription(context.getString(R.string.channel_episodes_desc))
                .build()
        )
        // IMPORTANCE_LOW: silent, but NOT IMPORTANCE_MIN — MIN disqualifies a Live Update.
        nm.createNotificationChannel(
            NotificationChannelCompat.Builder(COUNTDOWN, NotificationManagerCompat.IMPORTANCE_LOW)
                .setName(context.getString(R.string.channel_countdown))          // "Airing countdown"
                .build()
        )
    }
}
```

### 3.3 The airing plan — what the receiver reads

The receiver must not need the network, auth, or the full `AppModel`. Persist a flat plan whenever
the library reloads (this is the Android counterpart of `EpisodeNotifications.sync`):

```kotlin
@Serializable
data class PlannedAiring(
    val atMillis: Long,
    val franchiseId: String,
    val title: String,        // Franchise.displayTitle
    val mediaId: Int,
    val episode: Int?,
)

@Serializable
data class AiringPlan(val builtAt: Long, val airings: List<PlannedAiring>)

/** Mirrors EpisodeNotifications.sync's selection, minus the 48-slot iOS cap. */
fun buildPlan(library: List<Franchise>, now: Long, horizonMs: Long = 48 * 3_600_000L): AiringPlan {
    val perShow = library
        .filter { it.effectiveStatus == Status.Watching && it.source == Source.AniList }  // TMDB is date-only
        .mapNotNull { f ->
            val part = f.releasingPart ?: return@mapNotNull null
            part.airings
                .filter { it.at > now && it.at <= now + horizonMs }
                .sortedBy { it.at }
                .take(3)                                   // EpisodeNotifications.perShow
                .map { PlannedAiring(it.at, f.id, f.displayTitle, part.mediaId, it.episode) }
                .ifEmpty {
                    part.nextAiringAt?.takeIf { it > now && it <= now + horizonMs }
                        ?.let { listOf(PlannedAiring(it, f.id, f.displayTitle, part.mediaId, part.nextEpisodeNumber)) }
                        ?: emptyList()
                }
        }
        .filter { it.isNotEmpty() }

    // Round-robin, exactly as iOS: every show's soonest before any show's second.
    val ordered = (0 until 3).flatMap { rank ->
        perShow.mapNotNull { it.getOrNull(rank) }.sortedBy { it.atMillis }
    }
    return AiringPlan(builtAt = now, airings = ordered)
}
```

Store it with `DataStore<AiringPlan>` (or a small JSON file beside the library cache). The plan is
account-scoped: **clear it on sign-out**, like `EpisodeNotifications.cancelAll()`.

### 3.4 The scheduler

```kotlin
private const val BUCKET_MS = 60_000L          // round to the minute
private const val MAX_BUCKETS = 8              // « the 500-alarm platform cap
private const val LIVE_UPDATE_LEAD_MS = 60 * 60_000L   // AiringLiveActivityManager.leadWindow
private const val LIVE_UPDATE_LINGER_MS = 15 * 60_000L // .linger

class AiringAlarmScheduler @Inject constructor(
    @ApplicationContext private val context: Context,
    private val plans: AiringPlanStore,
) {
    private val am = context.getSystemService(AlarmManager::class.java)

    fun canBeExact(): Boolean =
        Build.VERSION.SDK_INT < 31 || am.canScheduleExactAlarms()

    /** Idempotent: cancel everything we own, then re-arm from the current plan. */
    suspend fun rearm(now: Long = System.currentTimeMillis()) {
        val plan = plans.read() ?: return
        cancelAll()

        val buckets = plan.airings
            .filter { it.atMillis > now }
            .groupBy { it.atMillis / BUCKET_MS * BUCKET_MS }
            .toSortedMap()
            .keys.take(MAX_BUCKETS)

        buckets.forEach { at -> arm(AiringAlarmReceiver.ACTION_FIRE, at, requestCode = at.bucketCode()) }

        // One Live Update alarm: T-60min before the soonest airing (the iOS lead window).
        buckets.firstOrNull()?.let { soonest ->
            val at = (soonest - LIVE_UPDATE_LEAD_MS).coerceAtLeast(now + 1_000)
            arm(AiringAlarmReceiver.ACTION_LIVE, at, requestCode = LIVE_REQUEST_CODE)
        }
    }

    private fun arm(action: String, atMillis: Long, requestCode: Int) {
        val pi = PendingIntent.getBroadcast(
            context, requestCode,
            Intent(context, AiringAlarmReceiver::class.java).setAction(action)
                .putExtra(AiringAlarmReceiver.EXTRA_AT, atMillis),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,   // IMMUTABLE required API 31+
        )
        // Exact when the user has granted "Alarms & reminders"; otherwise still Doze-piercing,
        // just not to the minute. Never throw: the grant can be revoked between check and call.
        try {
            if (canBeExact()) am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMillis, pi)
            else am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMillis, pi)
        } catch (e: SecurityException) {
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMillis, pi)
        }
    }
}
```

`RTC_WAKEUP` (not `ELAPSED_REALTIME`) is right here: air times are wall-clock instants from the
server, and the alarm must survive a clock/timezone change — which is also why `TIME_SET` /
`TIMEZONE_CHANGED` re-arm.

### 3.5 The receiver — post grouped, then re-arm

```kotlin
@AndroidEntryPoint
class AiringAlarmReceiver : BroadcastReceiver() {
    @Inject lateinit var plans: AiringPlanStore
    @Inject lateinit var scheduler: AiringAlarmScheduler

    companion object {
        const val ACTION_FIRE = "app.previously.alerts.FIRE"
        const val ACTION_LIVE = "app.previously.alerts.LIVE"
        const val EXTRA_AT = "at"
        const val GROUP_EPISODES = "episodes"
        const val SUMMARY_ID = 1
    }

    override fun onReceive(context: Context, intent: Intent) {
        val at = intent.getLongExtra(EXTRA_AT, 0L)
        val pending = goAsync()
        CoroutineScope(Dispatchers.Default).launch {
            try {
                val plan = plans.read() ?: return@launch
                when (intent.action) {
                    ACTION_FIRE -> postDue(context, plan, at)
                    ACTION_LIVE -> LiveUpdate.post(context, plan, System.currentTimeMillis())
                }
                scheduler.rearm()                 // always re-arm from inside the receiver
            } finally { pending.finish() }
        }
    }

    private fun postDue(context: Context, plan: AiringPlan, at: Long) {
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS)
            != PackageManager.PERMISSION_GRANTED && Build.VERSION.SDK_INT >= 33) return

        val due = plan.airings.filter { it.atMillis / BUCKET_MS * BUCKET_MS == at }
        if (due.isEmpty()) return
        val nm = NotificationManagerCompat.from(context)

        due.forEach { a ->
            nm.notify(
                a.notificationId(),
                NotificationCompat.Builder(context, Channels.EPISODES)
                    .setSmallIcon(R.drawable.ic_stat_previously)
                    .setContentTitle(a.title)                            // Franchise.displayTitle
                    .setContentText(Copy.Alert.episodeOut(a.episode))    // "Episode 12 is out now"
                    .setContentIntent(openDetail(context, a.franchiseId))
                    .setAutoCancel(true)
                    .setCategory(NotificationCompat.CATEGORY_EVENT)
                    .setGroup(GROUP_EPISODES)                            // see note below
                    .build()
            )
        }
        // A summary keeps a simulcast cluster as ONE banner rather than N that Android 16's
        // notification cooldown would silently mute one by one.
        if (due.size > 1) {
            nm.notify(
                SUMMARY_ID,
                NotificationCompat.Builder(context, Channels.EPISODES)
                    .setSmallIcon(R.drawable.ic_stat_previously)
                    .setContentTitle(Copy.Alert.episodesOut(due.size))   // "3 new episodes"
                    .setStyle(NotificationCompat.InboxStyle().also { s ->
                        due.forEach { s.addLine("${it.title} · ${Copy.Alert.episodeShort(it.episode)}") }
                    })
                    .setGroup(GROUP_EPISODES)
                    .setGroupSummary(true)
                    .setContentIntent(openTab(context, Tab.TODAY))
                    .setAutoCancel(true)
                    .build()
            )
        }
    }
}

private fun PlannedAiring.notificationId(): Int =
    (mediaId * 1000 + (episode ?: 0)) and 0x7fffffff   // stable, like "episode-<mediaId>-<ep>"
```

**Grouping note.** iOS uses `threadIdentifier = franchiseId` to file *repeat alerts of one show*
together. `setGroup(franchiseId)` is the literal translation, but on Android a group of one buys
nothing, and the real problem is the *simulcast cluster*. Prefer a single `GROUP_EPISODES` with a
summary. If you want the iOS grammar as well, keep `setGroup(franchiseId)` and add a per-franchise
summary — but only when that franchise has ≥ 2 live alerts.

### 3.6 Deep link — `PendingIntent` → `MainActivity` → `AppModel.pendingOpen`

```kotlin
const val EXTRA_FRANCHISE_ID = "app.previously.extra.FRANCHISE_ID"

fun openDetail(context: Context, franchiseId: String): PendingIntent {
    val intent = Intent(context, MainActivity::class.java)
        .setAction(Intent.ACTION_VIEW)                       // distinct action ⇒ distinct PendingIntent
        .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        .putExtra(EXTRA_FRANCHISE_ID, franchiseId)
    return PendingIntent.getActivity(
        context,
        franchiseId.hashCode(),                              // unique requestCode per show, or all
                                                             // shows share one PendingIntent
        intent,
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )
}
```

```kotlin
@AndroidEntryPoint
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        installSplashScreen()
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        setContent {
            val session: SessionViewModel = hiltViewModel()
            val model = session.model

            // Cold start: the intent that launched us.
            LaunchedEffect(Unit) {
                intent?.getStringExtra(EXTRA_FRANCHISE_ID)?.let(model::openFranchise)
            }
            // Warm start: singleTop delivers through onNewIntent, which never re-runs onCreate.
            val activity = LocalActivity.current as ComponentActivity
            DisposableEffect(activity) {
                val listener = Consumer<Intent> { i ->
                    i.getStringExtra(EXTRA_FRANCHISE_ID)?.let(model::openFranchise)
                }
                activity.addOnNewIntentListener(listener)
                onDispose { activity.removeOnNewIntentListener(listener) }
            }

            CompositionLocalProvider(LocalAppModel provides model) {
                PreviouslyTheme { RootView() }
            }
        }
    }
}
```

`model.openFranchise(id)` sets `pendingOpen`; `MainTabs`'s existing
`LaunchedEffect(model.pendingOpen)` does `switchTo(TodayKey)` + `push(DetailKey(id))` +
`consumePendingOpen()` — identical to the iOS route, and it already handles the
"consume once" rule that stopped Schedule's focus re-pushing on every pop.

> **Do not** use `TaskStackBuilder` here. It is for a *separate* result Activity that needs a
> synthetic parent stack. This app is single-Activity; `singleTop` + `CLEAR_TOP` + `onNewIntent` is
> the correct shape and preserves the user's existing back stack under the pushed Detail.

### 3.7 `POST_NOTIFICATIONS` — asked at the iOS moment

```kotlin
@Composable
fun rememberNotificationPermission(): NotificationPermission {
    val context = LocalContext.current
    var granted by remember {
        mutableStateOf(NotificationManagerCompat.from(context).areNotificationsEnabled())
    }
    val launcher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { ok ->
        granted = ok
        // iOS re-syncs the pending set the moment the primer's Allow lands (alertsWereAllowed).
        if (ok) AlertsBridge.rearmNow(context)
    }
    return remember(granted) {
        NotificationPermission(
            granted = granted,
            request = {
                if (Build.VERSION.SDK_INT >= 33) launcher.launch(Manifest.permission.POST_NOTIFICATIONS)
                else granted = NotificationManagerCompat.from(context).areNotificationsEnabled()
            },
        )
    }
}
```

Call `request()` from the same place iOS calls `requestPermissionIfNeeded()` — when an **airing show
is added** — not at launch. On API 31/32 there is no runtime permission, so
`areNotificationsEnabled()` is the whole answer.

### 3.8 The Live Update

```kotlin
object LiveUpdate {
    private const val ID = 2

    fun post(context: Context, plan: AiringPlan, now: Long) {
        if (Build.VERSION.SDK_INT < 36) return
        val nm = context.getSystemService(NotificationManager::class.java)
        if (!nm.canPostPromotedNotifications()) return       // user turned Live Updates off

        val next = plan.airings
            .filter { it.atMillis - now in 0..LIVE_UPDATE_LEAD_MS || now - it.atMillis in 0..LIVE_UPDATE_LINGER_MS }
            .minByOrNull { it.atMillis } ?: run { nm.cancel(ID); return }

        val n = NotificationCompat.Builder(context, Channels.COUNTDOWN)
            .setSmallIcon(R.drawable.ic_stat_previously)
            .setContentTitle(next.title)                                 // required for promotion
            .setContentText(Copy.Alert.airingSoon(next.episode))         // "Episode 12 airs soon"
            .setOngoing(true)                                            // FLAG_ONGOING_EVENT: required
            .setRequestPromotedOngoing(true)                             // the promotion request
            .setWhen(next.atMillis)
            .setUsesChronometer(true)
            .setChronometerCountDown(true)                               // ticks with the app dead
            .setTimeoutAfter(next.atMillis + LIVE_UPDATE_LINGER_MS - now) // the iOS `linger`
            .setContentIntent(openDetail(context, next.franchiseId))
            .setDeleteIntent(dismissed(context))                         // learn when the user swipes it
            // NO setColorized(true), NO custom RemoteViews, NO setGroupSummary — each disqualifies it.
            .build()

        NotificationManagerCompat.from(context).notify(ID, n)
    }

    fun cancel(context: Context) = NotificationManagerCompat.from(context).cancel(ID)
}
```

Verify promotion actually happened (OEMs may add criteria):

```kotlin
val posted = nm.activeNotifications.firstOrNull { it.id == LiveUpdate.ID }?.notification
val promoted = posted != null && (posted.flags and Notification.FLAG_PROMOTED_ONGOING) != 0
// Diagnostics only. Also available before posting: notification.hasPromotableCharacteristics()
```

A Settings row for the user, mirroring the iOS "Notifications" row:

```kotlin
context.startActivity(Intent(Settings.ACTION_MANAGE_APP_PROMOTED_NOTIFICATIONS)
    .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName))
```

### 3.9 The safety nets

```kotlin
// Daily: rebuild the plan from the cached library and re-arm. Covers a dropped alarm, an OEM
// that silently cancelled it, and the case where the exact-alarm grant changed while we slept.
WorkManager.getInstance(context).enqueueUniquePeriodicWork(
    "rearm-airing-alarms",
    ExistingPeriodicWorkPolicy.KEEP,
    PeriodicWorkRequestBuilder<RearmWorker>(1, TimeUnit.DAYS, 6, TimeUnit.HOURS)
        .setConstraints(Constraints.Builder().setRequiresBatteryNotLow(false).build())
        .build(),
)
```

Also re-arm on: `BOOT_COMPLETED`, `MY_PACKAGE_REPLACED`, `TIME_SET`, `TIMEZONE_CHANGED`,
`SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED` (all in `RearmReceiver`), on every successful
`AppModel.reload()`, and on app foreground. Sign-out (`teardown()`) must call
`scheduler.cancelAll()`, `NotificationManagerCompat.cancelAll()`, `LiveUpdate.cancel()`,
`WorkManager.cancelUniqueWork("rearm-airing-alarms")` and clear the plan — the Android counterpart of
`cancelAll()` + `endAll()`.

---

## 4. What actually survives Doze and OEM battery killers

| Threat | Effect | Mitigation in this design |
|---|---|---|
| **Doze** | Standard alarms deferred to the maintenance window; network suspended; WorkManager/JobScheduler blocked | `setExactAndAllowWhileIdle` / `setAndAllowWhileIdle` pierce Doze. The receiver **needs no network** — it reads the persisted plan. |
| **Doze 9-min rate limit** | Simultaneous alarms serialise | One alarm per air-time *bucket* |
| **App Standby buckets** | Rare/restricted buckets throttle alarms and jobs harder | The user opens this app most days, so it lands in *active/working set*. Do not rely on WorkManager for the alert itself. |
| **Exact-alarm permission denied (Android 14+ default)** | `setExactAndAllowWhileIdle` throws `SecurityException` | Try/catch → `setAndAllowWhileIdle`. Alerts still arrive, minutes late. One opt-in Settings row. |
| **Samsung "Sleeping apps" / "Deep sleeping apps"** | App put to sleep; alarms suppressed | Cannot be fixed in code. Samsung *excludes* apps the user opens regularly; document the toggle in an in-app help row. |
| **Xiaomi/HyperOS Autostart + MIUI battery saver** | No broadcasts (including `BOOT_COMPLETED`), alarms killed | Cannot be fixed in code. Autostart must be granted by the user. |
| **Force stop** | All alarms cancelled; **no broadcasts at all** until the user launches the app again | Unfixable by design. Re-arm on every app foreground. |
| **Reboot** | Alarms cleared by the platform | `BOOT_COMPLETED` receiver, unless force-stopped |
| **App update** | Alarms cleared | `MY_PACKAGE_REPLACED` receiver |

The honest summary: **exact-time local alerts on Android are best-effort, not guaranteed.** iOS's
`UNTimeIntervalNotificationTrigger` is a promise the system keeps; Android's alarm is a request the
system, the OEM and the user can each veto. Design the product around "usually within a minute,
sometimes later, occasionally not at all", and make Today's own state — which is derived from
`airings` and correct whenever the app is open — the source of truth the user actually relies on.

**Consider offering the OEM-settings escape hatch, but do not beg.** A single row in Settings
("Episode alerts arriving late?") that deep-links to
`Settings.ACTION_APPLICATION_DETAILS_SETTINGS` (and to
`ACTION_REQUEST_SCHEDULE_EXACT_ALARM` when the exact grant is missing) is the right dose. Do **not**
ship `ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` — Play policy restricts it and this app does not
qualify.

---

## 5. What is NOT achievable

1. **No Dynamic Island.** There is no third-party API for any equivalent. The closest surfaces are
   the **Android 16 status-bar chip** (Pixel and, via One UI 8, Samsung) and the **One UI Now Bar** —
   both reached only through the standard Live Updates API, both rendered from **Google's templates**,
   neither addressable directly.
2. **No custom Live Update layout.** `RemoteViews` / `customContentView` **disqualifies** a
   notification from promotion. You get Standard, `BigTextStyle`, `CallStyle`, `ProgressStyle`, or
   (API 37) `MetricStyle`. The iOS Live Activity's bespoke SwiftUI layout has no counterpart — plan
   for "title + text + countdown chip", not for a designed card.
3. **No Live Updates below Android 16 (API 36).** With minSdk 31 that is a large slice of the
   install base with **no countdown surface at all**. There is no `ActivityKit` back-compat shim.
4. **No `.staleDate`.** `setTimeoutAfter` is the nearest thing (auto-cancel after a duration); there
   is no "render it dimmed once stale" state.
5. **No guaranteed exact delivery** without a permission the user must grant in Settings and can
   revoke, plus OEM cooperation you cannot obtain in code (§4).
6. **Ongoing ≠ undismissible.** Since Android 14 the user can swipe away a `FLAG_ONGOING_EVENT`
   notification. Handle `setDeleteIntent` and do not re-post it.
7. **No provisional/quiet authorization.** iOS's `.provisional` (deliver quietly without a prompt)
   has no Android equivalent; `POST_NOTIFICATIONS` is a hard yes/no dialog.
8. **No foreground-presentation delegate needed — and none available.** Android posts notifications
   regardless of whether the app is frontmost; whether it *interrupts* is decided by channel
   importance, which the user owns. `ForegroundPresenter` has no port, and its bug class (a weak
   delegate silently dropping the alert) does not exist here.
9. **No 64-notification cap, but a 500-alarm cap** and a 9-minute Doze cadence instead. Different
   budget, different shape — which is why §1.1 is a redesign rather than a translation.
10. **`USE_EXACT_ALARM` is off the table** by Play policy, so the "always granted, never revocable"
    tier iOS effectively has is unavailable to this app.

---

## 6. Alternatives rejected

| Option | Why not |
|---|---|
| **WorkManager for the alerts themselves** | Cannot run at an exact time; 15-minute minimum periodic interval; `setInitialDelay` is a floor, not a schedule; **blocked outright by Doze**. Official guidance is explicit that exact timing is not guaranteed. Kept only as the daily re-arm safety net. |
| **`setAlarmClock()`** | The most reliable API (the system exits Doze before it and OEMs respect it) — and wrong here. It plants a **system alarm icon in the status bar** and a "next alarm" entry in the lock screen and Quick Settings, i.e. this app would masquerade as the user's wake-up alarm to announce an anime episode. It also needs the same `SCHEDULE_EXACT_ALARM` grant, so it buys reliability at the cost of lying to the user. Revisit only if field telemetry shows unacceptable miss rates *and* the alarm-icon cost is explicitly accepted. |
| **`USE_EXACT_ALARM`** | Play policy restricts it to alarm/timer/calendar apps; declaring it invites rejection. |
| **One alarm per episode (the literal iOS port)** | Serialised by the 9-minute Doze rate limit exactly when it matters most (simulcast clusters); walks toward the 500-alarm cap; and produces the notification burst Android 16's cooldown mutes. |
| **A single "next alarm only" chain** | Minimal, but one dropped re-arm silently ends the feature forever. Eight buckets is cheap insurance. |
| **FCM push from the server at air time** | Genuinely more reliable (high-priority FCM pierces Doze and does not need the exact-alarm permission) and worth considering **later** — but it needs server-side per-device scheduling, token lifecycle, and a privacy story for shipping the watch list to a push service. The iOS app deliberately has no push infrastructure; matching it locally is the smaller change. Flag as a **Phase 2** upgrade if miss rates are bad. |
| **Foreground service for the countdown** | Android 14+ requires a declared FGS *type*, and none fits; it drains battery, shows a persistent notification anyway, and is unnecessary because `setChronometerCountDown` ticks without a process. |
| **`ProgressStyle` for the countdown** | Built for rideshare/delivery/navigation — segments and points along a route. A countdown to an air time is a *clock*, not a journey with milestones; the chronometer chip says it better. Reconsider if a "3 of 12 episodes watched this season" progress reading is wanted on the lock screen. |
| **`MetricStyle` (API 37)** | Genuinely attractive later (three metrics: episodes behind / next airing / season progress), but API 37 only and `androidx.core` support only landed in 1.18.0-alpha01. Not for v1. |
| **`ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`** | Play-restricted; this app does not qualify; a hostile prompt regardless. |
| **A URI deep link (`previously://franchise/{id}`) with `navDeepLink`** | Navigation 3 has no `navDeepLink` — the back stack is hand-owned. An intent extra is simpler, type-safe, and reuses the `pendingOpen` route already specified. |

---

## 7. Open questions for a human

1. **Do we accept "best effort" alerts, or is this a push feature?** If a missed episode alert is a
   product failure rather than a nuisance, the answer is server-side FCM, and that decision should
   be taken **before** the alarm code is written, not after. It also changes the backend
   (`sync/cron.ts` would need to fan out to device tokens).
2. **Where does the exact-alarm ask live in the UI, if anywhere?** Options: (a) never ask, accept
   minutes of slop; (b) one Settings row; (c) an inline `InlineNotice` on Today when an alert was
   demonstrably late. iOS has no analogue to copy from, so this is a fresh design decision — and per
   the project's own rule, it is a UX question that wants research and a decision, not a default.
3. **Ship the Live Update at all in v1?** It is API 36+ only, invisible to a large minority of
   minSdk-31 users, and the Android Police piece (13 Aug 2026) says adoption is sparse — meaning the
   surface is unfamiliar and lightly QA'd by OEMs. A defensible v1 answer is "no Live Update; the
   T-0 notification is the whole feature", with Live Updates as a fast follow once there is a device
   to test on.
4. **Is `NotificationCompat.Builder.setShortCriticalText` real in androidx.core 1.19.0?** The guide
   pages use it; the release notes do not list it. If it is platform-only, the chip text falls back
   to the chronometer and the `SDK_INT >= 36` branch has to use `Notification.Builder` directly.
   **Verify against the actual artifact before writing the Live Update.**
5. **What is the notification-tap target when a cluster fires?** iOS opens the one show. The summary
   here opens Today. Confirm that is the wanted grammar (Today is the app's urgency screen, so it
   probably is — but Schedule is the other candidate).
6. **TMDB shows stay excluded, as on iOS?** The date-only 17:00-UTC synthesis makes a timed alert
   dishonest. Confirm the port keeps the `source == anilist` gate, and that the Android copy says so
   somewhere the user can find it.
7. **How do we test any of this?** The emulator (`PreviouslyQA_API36`, per `TOOLCHAIN.md`) can be
   forced through Doze with `adb shell dumpsys deviceidle force-idle` and alarms inspected with
   `adb shell dumpsys alarm | grep <package>`, but **OEM battery killers cannot be reproduced on an
   emulator**. A physical Samsung and a physical Xiaomi are the only way to know. Is there budget for
   that, or is the answer "ship and watch the crash-free/engagement funnel"?

---

## 8. Version summary (as of 2026-09-04)

| Thing | Version / API level | Date |
|---|---|---|
| Android 16 | API 36 | stable 10 Jun 2025 |
| Android 17 | API 37 | stable 16 Jun 2026 |
| Live Updates (`setRequestPromotedOngoing`, `POST_PROMOTED_NOTIFICATIONS`, status-bar chip) | API 36+ | Android 16 |
| `Notification.MetricStyle`, semantic colours | API 37+ | Android 17 |
| `setExactAndAllowWhileIdle(…, OnAlarmListener, Executor)` | API 37+ | Android 17 |
| `androidx.core` (needed for `NotificationCompat.ProgressStyle` / `setRequestPromotedOngoing`) | **1.19.0** stable (floor 1.17.0) | 1.19.0 on 3 Jun 2026 |
| `POST_NOTIFICATIONS` runtime permission | API 33+ | Android 13 |
| `SCHEDULE_EXACT_ALARM` denied by default | Android 14+ devices, apps targeting API 33+ | Android 14 |
| Play targetSdk floor | API 36 | since 31 Aug 2026 |
| One UI 8 Now Bar open to third parties via Live Updates | — | 2025–2026 |
