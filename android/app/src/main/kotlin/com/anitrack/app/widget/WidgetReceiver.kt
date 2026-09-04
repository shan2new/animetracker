package com.anitrack.app.widget

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/*
 * ============================================================================================
 * THE TWO RECEIVERS — the one the launcher talks to, and the one the clock talks to.
 * ============================================================================================
 *
 * Neither runs in its own process. There is deliberately no `android:process` on either manifest
 * entry, so both share the app's `filesDir`, its Coil disk cache and — when the app happens to be
 * alive — its object graph. `MultiProcessGlanceAppWidget` exists for apps that split them
 * deliberately; this one must not.
 */

/**
 * The provider the launcher binds to.
 *
 * `GlanceAppWidgetReceiver` is an `AppWidgetProvider`, so the widget lifecycle callbacks arrive
 * here: [onEnabled] when the FIRST instance is placed, [onDisabled] when the LAST one is removed.
 * That is the right place to own the refresh schedule — arming a periodic worker and an alarm for a
 * widget nobody has placed is a battery cost with no surface.
 *
 * Every override calls `super` first: the base class is what actually drives the Glance session, and
 * a swallowed callback is a widget that silently never draws.
 */
class UpNextWidgetReceiver : GlanceAppWidgetReceiver() {

    override val glanceAppWidget: GlanceAppWidget = PreviouslyWidget()

    /** First instance placed. Install the 30-minute net and arm the next episode boundary. */
    override fun onEnabled(context: Context) {
        super.onEnabled(context)
        WidgetRefresh.schedule(context)
        WidgetRefresh.refreshAsync(context)
    }

    /** Last instance removed. Nothing may keep waking the device for a surface that is gone. */
    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        WidgetRefresh.cancel(context)
    }
}

/**
 * The episode boundary.
 *
 * The widget's copy is derived — `airedByNow`, `behind`, `upcomingAiring` all read the part's own
 * `airings` against the clock — so "Airs in 3m" becomes "Out now" with no server call and no new
 * data. What it needs is a **re-render at the right instant**, and that instant is the only moment
 * the card's meaning changes while nobody is touching the phone.
 *
 * One INEXACT alarm, re-armed on every render for the new next boundary. Never exact: Play policy
 * restricts `USE_EXACT_ALARM` to apps whose core function is alarms, timers or calendars, and
 * `SCHEDULE_EXACT_ALARM` is denied by default on Android 14+ — while a five-minute window is
 * indistinguishable to somebody reading a card that says "in 3h 12m". A widget is not an alarm
 * clock and must never ask to be treated as one.
 *
 * The alarm is cleared by the platform on reboot and on package replace. Nothing here re-arms it,
 * on purpose: the 30-minute `PeriodicWorkRequest` survives both (WorkManager persists its schedule),
 * and its first run after boot re-arms the alarm as a side effect of rendering. One recovery path,
 * not two.
 */
class WidgetBoundaryReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_BOUNDARY) return
        val app = context.applicationContext
        // `goAsync` because the work is a file read and a `RemoteViews` build — short, but not
        // synchronous, and a receiver that returns before its coroutine lands is a receiver whose
        // process the system is free to kill mid-render.
        val pending = goAsync()
        CoroutineScope(SupervisorJob() + Dispatchers.Default).launch {
            try {
                // `refresh` re-arms the alarm for the NEXT boundary from what it just read, so the
                // chain continues without a repeating alarm and without a guess about cadence.
                WidgetRefresh.refresh(app)
            } finally {
                pending.finish()
            }
        }
    }

    companion object {
        /** Package-qualified: an action name is a global namespace. */
        const val ACTION_BOUNDARY = "com.anitrack.app.widget.BOUNDARY"
    }
}

/**
 * Is there a card on any home screen right now?
 *
 * Asked before tearing the schedule down in [PreviouslyWidget.onDelete], because `onDelete` fires
 * per instance while `onDisabled` fires only for the last one — removing the second of three cards
 * must not stop the other two updating.
 */
internal object WidgetPresence {

    suspend fun anyPlaced(context: Context): Boolean = runCatching {
        GlanceAppWidgetManager(context.applicationContext)
            .getGlanceIds(PreviouslyWidget::class.java)
            .isNotEmpty()
    }.getOrDefault(false)
}
