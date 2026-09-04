package com.anitrack.app.notifications

import android.content.Context
import android.content.SharedPreferences
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

/*
 * THE NOTIFICATION PRIMER'S STATE — armed by an add, answered on the Search tab.
 *
 * ## Why this is not a private class on the Search screen any more
 *
 * It was, and the ask reached exactly one of the app's four add paths.
 *
 * `POST_NOTIFICATIONS` defaults to DENIED on API 33+, so `canPostAlerts` answers false and
 * `EpisodeNotifications.armOrStandDown` responds by standing every alarm down. The ask is the only
 * thing that changes that answer — and it was armed from `DiscoverScreen`'s `add` lambda alone.
 * Today's trending billboard (the *designed first add* for an empty account), Detail's toolbar `+`
 * and `SyncCenter`'s Subscribe replay all added shows without ever arming it, so a user who built
 * their library from Today and Detail — or who signed in with a library already populated on iOS —
 * was never asked, had every alarm stood down, and received no episode alert ever, with nothing to
 * say why but a Profile row reading "Off".
 *
 * So the arming moved to the one place every add goes through, `AppModel.addToLibrary`, and the
 * state it writes had to move somewhere both the model and the screen can see. This is that place.
 *
 * ## The two flags, and what the screen still owns
 *
 * [pending] and [answered] are the user's state and are persisted under the **same keys iOS uses**,
 * so the two ports name the same thing. What the *screen* owns is unchanged and stays there: whether
 * the device can still be asked at all (API level, the manifest declaration, whether the permission
 * is already granted), and the round trip through `rememberLauncherForActivityResult`.
 *
 * They are per install, not per account — the OS asks its own permission question once per install
 * too, and re-raising the ask at every sign-in is the nag the product decision rules out. Sign-out
 * clears the plan and the alarms; it does not un-ask a question the device has already answered.
 *
 * `SharedPreferences` rather than DataStore, deliberately: the read has to be SYNCHRONOUS so the
 * primer's visibility is decided on the frame the screen first composes rather than one collection
 * later. The mirrored snapshot state on top of it is what lets an arm that happens on Today reach a
 * Search screen that is already composed.
 */

/**
 * The primer's persisted answer, as one process-wide object.
 *
 * [install] is called from `AppGraph.create`, before the first composition and before anything can
 * add a show. Un-installed (a unit test, a process that has somehow not run `Application.onCreate`)
 * every write is a no-op and [pending] stays false — the ask simply never appears, which is the
 * right failure for a permission prompt.
 */
@Stable
object NotificationPrimer {

    @Volatile
    private var store: PrimerStore? = null

    /**
     * An add of a currently-airing AniList show has STUCK and its undo window has closed.
     *
     * Snapshot state, not just a preference read, because the two moments are frames apart and on
     * different screens: the add that arms it may have happened on Today while the Search tab was
     * already composed.
     */
    var pending by mutableStateOf(false)
        private set

    /** Answered once, whichever way. One-shot forever; Profile → Notifications is the way back. */
    var answered by mutableStateOf(false)
        private set

    /** Whether an add is still worth arming — cheap, so the caller can ask before it waits. */
    val armable: Boolean get() = store != null && !answered

    fun install(context: Context) {
        val prefs = context.applicationContext
            .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val restored = PrimerStore(prefs)
        store = restored
        pending = restored.pending
        answered = restored.answered
    }

    /** Arm the ask. Idempotent, and a no-op once it has been answered. */
    fun arm() {
        val store = store ?: return
        if (answered) return
        store.pending = true
        pending = true
    }

    /** Both answers spend it permanently — asking twice is the nag the product decision forbids. */
    fun settle() {
        val store = store ?: return
        store.answered = true
        store.pending = false
        answered = true
        pending = false
    }

    /** iOS `@AppStorage` keys, kept identical. */
    private const val PENDING_KEY = "previously.notifPrimerPending"
    private const val ANSWERED_KEY = "previously.notifPrimerAnswered"

    /** Shared with `ExactTimingAskStore`: two answers to one question, one file. */
    private const val PREFS_NAME = "previously.notifications"

    private class PrimerStore(private val prefs: SharedPreferences) {

        var pending: Boolean
            get() = prefs.getBoolean(PENDING_KEY, false)
            set(value) = prefs.edit().putBoolean(PENDING_KEY, value).apply()

        var answered: Boolean
            get() = prefs.getBoolean(ANSWERED_KEY, false)
            set(value) = prefs.edit().putBoolean(ANSWERED_KEY, value).apply()
    }
}
