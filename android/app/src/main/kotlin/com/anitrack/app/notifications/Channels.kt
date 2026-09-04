package com.anitrack.app.notifications

import android.content.Context
import androidx.core.app.NotificationChannelCompat
import androidx.core.app.NotificationManagerCompat
import com.anitrack.model.copy.Copy

/*
 * THE CHANNELS — the one thing iOS has no counterpart for at all.
 *
 * On iOS the app decides how an alert behaves (`.alert, .sound`) and the user's only lever is the
 * whole app. On Android the CHANNEL owns the behaviour — importance, sound, vibration, badge, lock
 * screen — and once it is created the app can never change any of that again: `createNotificationChannel`
 * on an existing id updates the NAME and the DESCRIPTION and silently ignores everything else,
 * because the user's own edits in Settings are the authority. So the values below are effectively
 * permanent for every install that has already run this code once, and the only way to change one
 * is to ship a new channel id and orphan the old one (which leaves a dead row in the user's
 * Settings). Treat them as a shipped decision, not a default.
 *
 * Channels are MANDATORY from API 26 and the app's floor is exactly 26, so there is no `SDK_INT`
 * branch here and there must never be one: a notification posted to a channel that does not exist
 * is dropped by the platform with nothing but a logcat line, which is the quietest possible way for
 * the whole alert feature to die.
 */

/**
 * Every notification channel **Previously.** owns. There is one.
 *
 * `ensure` is idempotent and cheap; it runs from `PreviouslyApp.onCreate` (so the channel exists
 * before anything can post to it — including a cold process started by [AiringReceiver], where the
 * `Application` is always constructed first) and again from
 * [EpisodeNotifications.install].
 */
object Channels {

    /**
     * "An episode of a show you're watching is out."
     *
     * The id is a wire value in the user's own Settings and in every posted notification, so it is
     * frozen: renaming it creates a second channel and abandons whatever the user had customised on
     * the first one.
     */
    const val EPISODES: String = "episodes"

    /**
     * The group key every episode alert carries, and the reason a simulcast cluster reads as one
     * event instead of nine.
     *
     * **One group for the whole feature, not one per franchise.** iOS files repeat alerts of a
     * single show under `threadIdentifier = franchiseId`, and the literal translation of that is
     * `setGroup(franchiseId)` — but on Android a group of one buys nothing, and the problem the
     * grouping actually has to solve is the opposite one: a dozen shows share one JST broadcast
     * slot, so the alerts arrive as a burst. Since Android 16 the platform collapses a burst by
     * itself — first notification at full volume, each subsequent one quieter and visually
     * minimised, bundled under a single banner — so the choice is not "bundle or don't", it is
     * "bundle deliberately, or let the system improvise a bundle out of nine alerts the app
     * designed to stand alone".
     */
    const val GROUP_EPISODES: String = "app.previously.episodes"

    /**
     * Create (or update the wording of) every channel this app posts to.
     *
     * Safe to call on any thread and any number of times.
     */
    fun ensure(context: Context) {
        NotificationManagerCompat.from(context.applicationContext).createNotificationChannel(
            NotificationChannelCompat.Builder(EPISODES, NotificationManagerCompat.IMPORTANCE_DEFAULT)
                .setName(Copy.Alert.channelEpisodes)
                .setDescription(Copy.Alert.channelEpisodesDescription)
                // A launcher dot is the quietest possible "there is something here", and it is the
                // one part of this feature that costs the user nothing.
                .setShowBadge(true)
                .build(),
        )
    }
}

/*
 * IMPORTANCE — why DEFAULT and not HIGH, and why never MIN.
 *
 * `IMPORTANCE_DEFAULT` makes a sound and files the alert in the shade; `IMPORTANCE_HIGH` adds the
 * heads-up banner that peels over whatever the user is doing. iOS's `.banner` presentation looks
 * like an argument for HIGH, and the platform research note proposed it — but the two are not the
 * same promise. An iOS banner is a transient card at the top of the screen; an Android heads-up is
 * a full interruption with its own sound, and Android 16's cooldown will mute the second and
 * subsequent members of a simulcast burst anyway, so HIGH would buy an interruption for exactly one
 * show and a muted, half-drawn bundle for the rest.
 *
 * An episode dropping is NEWS, not an alarm. It goes in the shade with a sound; the user who wants
 * it louder raises it in Settings, and — unlike the app — the user's edit sticks.
 *
 * `IMPORTANCE_MIN` is forbidden outright: it is silent, statusless and collapsed, i.e. the feature
 * would ship switched off for everyone who never opens the shade, and it also disqualifies a
 * notification from ever being promoted if the deferred Live Update is picked up later.
 */
