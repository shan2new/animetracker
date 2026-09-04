package com.anitrack.model.copy

/*
 * THE ALERT NAMESPACE — every string the episode-alert feature says, from the notification the
 * system draws to the two Settings rows that govern it.
 *
 * Reached as `Copy.Alert.*` through the getter on `Copy` (the nested `Copy.Alert` object this file
 * absorbed held only [episodeOut], and one feature may not have two namespaces). Three groups, and
 * the boundary between them is the platform's, not the app's:
 *
 *   * the ALERT itself — [episodeOut], [episodesOut], [line]: what a user reads in the shade;
 *   * the CHANNEL — [channelEpisodes], [channelEpisodesDescription]: what a user reads in system
 *     Settings, which exists only because Android has channels and has no iOS twin at all;
 *   * the EXACT-ALARM ask and the settings rows — [exactTiming] and below.
 *
 * A top-level object in `com.anitrack.model.copy`, for the reason `CopyLibrary` / `CopySearch` /
 * `CopyAccount` are: Kotlin objects cannot be reopened the way Swift extends `Copy`, so each
 * namespace is a top-level object here and `Copy` wires it back in with a getter. Nothing here is a
 * second spelling of an existing entry — "Turn on", "Not now", "On" and "Off" already exist
 * (`Copy.Search.primerTurnOn`, `Copy.Search.primerNotNow`, `Copy.State.on`, `Copy.State.off`) and
 * are reused verbatim at the call sites.
 *
 * ## Why these strings exist at all, and what they may never say
 *
 * **They have no iOS twin.** iOS schedules a `UNTimeIntervalNotificationTrigger` and the system
 * keeps the promise; Android's `SCHEDULE_EXACT_ALARM` is *denied by default* on Android 14+ for an
 * app targeting API 33+ (`docs/android-port/research/product-decisions.md` §4, PLAN D7a/D31), and
 * `USE_EXACT_ALARM` — the auto-granted tier — is reserved by Play policy for alarm, timer and
 * calendar apps. So this app ships **correct without the permission**: an alert armed with
 * `setAndAllowWhileIdle` still arrives, just not to the minute.
 *
 * Three laws govern the wording, and all three are the same law from different angles:
 *
 *  1. **State the benefit, not the mechanism.** Not one of these strings says "alarm",
 *     "permission", "exact alarm", "Doze" or "battery optimisation". This is a fact about the
 *     user's episodes.
 *  2. **Never claim a precision the app does not have.** While the grant is absent the copy says
 *     an alert *can arrive a few minutes late* — which is true — and never promises a time.
 *     "A few minutes" is the honest reading of Doze's documented ~9-minute floor on
 *     `setAndAllowWhileIdle`; a number in the sentence would be precision the app cannot promise
 *     either.
 *  3. **One name for one thing.** The Settings row, the contextual ask and the receipt all say
 *     "Exact timing". A control the user meets twice under two names is two controls.
 *
 * Voice, as everywhere: sentence case, one supporting sentence, no exclamation marks, curly
 * apostrophes (U+2019). A settings subtitle carries no full stop (as "Erases your library,
 * progress and history" does not); a primer's supporting sentence does (as
 * `Copy.Search.primerBody` does). **A pushed alert carries no full stop either** — *"Apple's own
 * alerts carry none"*, and one voice across two platforms is worth more than the punctuation. The
 * brand is never a clause subject in any of them: the system draws the app name beside every
 * notification, so a line beginning "Previously…" would read as the adverb and say the opposite of
 * what it means.
 */
object CopyAlerts {

    // ---------------------------------------------------------------------------------------------
    // The alert itself
    // ---------------------------------------------------------------------------------------------

    /**
     * The one sentence the app ever pushes — the notification's BODY; its title is the show.
     *
     * Null when the catalogue has not numbered the slot, which is why the fallback exists at all.
     */
    fun episodeOut(n: Int?): String =
        n?.let { "${Copy.episode(it)} is out now" } ?: "A new episode is out now"

    /**
     * The bundle summary's title: "3 episodes are out now".
     *
     * The count goes through `Copy.episodes`, so the pluraliser and the non-breaking space that
     * binds the numeral to its noun are the catalogue's rather than a second spelling of them.
     */
    fun episodesOut(n: Int): String = "${Copy.episodes(n)} are out now"

    /**
     * One line of that summary: "Re:ZERO · Episode 12".
     *
     * The separator is the app's fact separator (U+00B7). The line deliberately does NOT repeat
     * "is out now": five identical predicates stacked inside one bundle is exactly the prose the
     * design law rations, and the bundle's own title has already said it.
     */
    fun line(title: String, episode: Int?): String =
        if (episode == null) title else "$title · ${Copy.episode(episode)}"

    // ---------------------------------------------------------------------------------------------
    // The channel — Android only
    // ---------------------------------------------------------------------------------------------

    /**
     * The channel's name, as the user reads it in system Settings. A NOUN for the thing that
     * arrives, not a description of the app's machinery.
     */
    const val channelEpisodes = "New episodes"

    /** One line, about the user's episodes rather than about scheduling. */
    const val channelEpisodesDescription = "When an episode of a show you’re watching is out"

    // ---------------------------------------------------------------------------------------------
    // The exact-alarm ask, and the Settings rows
    // ---------------------------------------------------------------------------------------------

    /**
     * The name of the thing, in the Settings row, in the contextual ask, and in the receipt.
     *
     * It is deliberately the vocabulary of the system screen the row opens ("Alarms & reminders",
     * whose switch reads "Allow setting alarms and reminders"), because the user has to find that
     * switch once they arrive — but stated as the outcome rather than the machinery.
     */
    const val exactTiming = "Exact timing"

    /**
     * The degraded state, in the Settings row's subtitle, drawn **only while the grant is absent**
     * (PLAN spec debt D-1: "the one string that tells a user their reminders are approximate").
     *
     * The row would otherwise say "Off" against a title that sounds like a luxury, and a user whose
     * alerts arrive late would have nothing on this screen that admits it.
     */
    const val approximate = "Episode alerts can arrive a few minutes late"

    /**
     * The contextual ask's supporting line. "It" is the title directly above it.
     *
     * Names *episode* alerts, not alerts in general: the ask is raised on the Search screen, one
     * row above a catalogue, and "an alert" alone there could be read as anything.
     */
    const val askBody = "Without it, an episode alert can arrive a few minutes late."

    /**
     * The neutral receipt when the grant lands — `showNotice`, not an Undo toast, and no haptic of
     * its own beyond the one the grant already fired.
     *
     * Built like `Copy.Toast.alertsOn` ("Episode alerts on"): the setting, stated. **Not** a
     * promise about delivery — the OEM ceiling (Samsung's "Put unused apps to sleep", Xiaomi's
     * Autostart) survives the grant, and a receipt reading "Alerts will arrive on time" would be
     * the app claiming something no permission can buy it.
     */
    const val exactTimingOn = "Exact timing on"
}
