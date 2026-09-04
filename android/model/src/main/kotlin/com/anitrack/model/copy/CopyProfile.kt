package com.anitrack.model.copy

/*
 * PROFILE — the account sheet's own strings.
 *
 * The port of the `AccountCopy` enum in `ProfileView.swift`, which exists for the reason this does:
 * one screen introduces a block of vocabulary and nothing else in the app says any of it. It was
 * staged in `ui/profile/Settings.kt` for a while, on the argument that a Kotlin object cannot be
 * reopened from another module — but that argument only ever ruled out *adding to `Copy`*, never
 * living in the catalogue package, which is what `CopyLibrary`, `CopySearch` and `CopyScreens`
 * already do. It is a sibling object here now, reached as `Copy.Profile.*`, so the whole of the
 * app's copy is enumerable — and therefore auditable — from one place.
 *
 * Two of these strings are App Review-sensitive and are not to be reworded: [ATTRIBUTION] (TMDB
 * requires the sentence verbatim) and [deleteMessage] (the strongest consequence in the app, stated
 * in the user's own numbers).
 *
 * Voice, as everywhere: sentence case, curly apostrophes (U+2019), no exclamation marks. Two
 * Android-only divergences from the Swift are recorded at their members: a hint may not name an app
 * the device does not have, so "Opens in Safari" is [HINT_OPENS_BROWSER] and "Opens Mail" is
 * [HINT_OPENS_MAIL].
 */
object CopyProfile {


    /** The sheet's own title. */
    const val PROFILE = "Profile"

    // Grouped-list headers. Eyebrows, so `SectionLabel` uppercases them at render.
    const val SETTINGS = "Settings"
    const val SYNC = "Sync"
    const val ACCOUNT = "Account"

    const val NOTIFICATIONS = "Notifications"
    const val HAPTICS = "Haptics"

    const val EXPORT = "Export library"

    /**
     * **Not "for re-import".** There is no import path in this build, and the export screen is the
     * one place a user reads when they are worried about their data — a false claim there is worse
     * than a missing feature. What the file IS, never what it could one day be fed back into.
     */
    const val EXPORT_JSON = "JSON"
    const val EXPORT_JSON_SUB = "Every field, machine-readable"
    const val EXPORT_CSV = "CSV"
    const val EXPORT_CSV_SUB = "One row per title, for spreadsheets"

    const val EXPORT_FOOTNOTE =
        "A copy is created on this device and handed to whatever you share it with. " +
            "Nothing leaves your account until you choose a destination."

    /** The file the picker is opened with. Same names as iOS writes. */
    const val EXPORT_FILE_JSON = "previously-library.json"
    const val EXPORT_FILE_CSV = "previously-library.csv"

    fun exportAs(format: String): String = "Export as $format"

    // -- Identity -------------------------------------------------------------------------------

    fun signedInAs(name: String): String = "Signed in as $name"

    // -- Sync ladder ----------------------------------------------------------------------------

    /**
     * "Checked just now" — the stamp word lower-cased at its FIRST CHARACTER only, so it can
     * follow a verb without shouting ("Just now" → "just now"). Never `lowercase()`, which would
     * also un-capitalise the month in "Aug 19".
     */
    fun checked(stamp: String): String = "Checked ${stamp.lowercasedFirstCharacter()}"

    private fun String.lowercasedFirstCharacter(): String =
        if (isEmpty()) this else this[0].lowercaseChar() + substring(1)

    const val JUST_NOW = "Just now"

    fun minutesAgo(n: Int): String = "$n min ago"

    // -- Destructive confirmations --------------------------------------------------------------

    /**
     * One outcome, one supporting sentence. The pending-changes case earns its second clause
     * because it carries a second fact.
     *
     * "3 changes hasn't" — the one verb in the app that has to agree with its count.
     */
    fun signOutMessage(pending: Int): String {
        if (pending <= 0) {
            return "Your library stays in your account — sign back in any time."
        }
        val verb = if (pending == 1) "hasn’t" else "haven’t"
        val pronoun = if (pending == 1) "it stays" else "they stay"
        return "Your library stays in your account. ${Copy.changes(pending)} $verb synced yet — " +
            "$pronoun on this device and upload the next time you sign in."
    }

    /** The blast radius, in the user's own numbers. The strongest copy in the app; not shortened. */
    fun deleteMessage(titles: Int): String =
        "This permanently deletes your account and everything in it" +
            (if (titles > 0) " — ${Copy.titles(titles)}, all progress and watch history" else "") +
            ". It can’t be undone."

    /**
     * The confirmation names the change it is about to destroy — "Discard" alone beside a show name
     * is genuinely ambiguous about its object.
     */
    fun discardMessage(title: String, command: String): String =
        "“$title · $command”. ${Copy.Confirm.discardChangeMessage}"

    // -- Colophon -------------------------------------------------------------------------------

    /**
     * **App Review-sensitive and not to be reworded.** Only the MEASURE is a design decision (see
     * the colophon's own width note); the STRING is untouched.
     */
    const val ATTRIBUTION =
        "Data from AniList and TMDB. This product uses the TMDB API but is not endorsed " +
            "or certified by TMDB."

    // -- Accessibility --------------------------------------------------------------------------

    /** Android has a Settings app, so this one is verbatim. */
    const val HINT_OPENS_SETTINGS = "Opens Settings"

    /** iOS: "Opens in Safari". A hint may not name an app the device does not have. */
    const val HINT_OPENS_BROWSER = "Opens in your browser"

    /** iOS: "Opens Mail". */
    const val HINT_OPENS_MAIL = "Opens your email app"

    const val HINT_SIGN_OUT = "Your library stays in your account"
    const val HINT_DELETE = "Permanently deletes your account and library"
    const val HINT_DISCARD = "Throws this change away. It can’t be undone."
}
