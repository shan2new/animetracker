package com.anitrack.model.copy

// Strings the screens staged locally during the polish rounds, now in the copy table where every
// user-facing string lives. Ported from `ios/Sources/DesignSystem/Copy+Screens.swift`.
//
// The Swift file also adds members to `Copy.Action`, `Copy.Accessibility` and `Copy.Progress`.
// A Kotlin object cannot be reopened in a second file, so those live in `Copy.kt` under a
// `// Copy+Screens.swift` marker — the namespaces are identical, only the file boundary moved.
// What remains here is what the Swift file *introduces*: Recap, Rewatch, Account, Filter,
// Schedule, Video, People and Watch, each reached as `Copy.<Name>.*` through a getter on `Copy`.

object CopyRecap {
    const val whileYouWereAway = "While you were away"

    /**
     * "Episode 19 aired" / "3 episodes aired" / "Season 4 · Episode 19 aired".
     *
     * The verb was typed inline at four separate sites in `RecapDigest.kt`; the subject varies, the
     * verb never does.
     */
    fun aired(subject: String): String = "$subject aired"

    /** The strip's whole line: what happened, and the window it happened in. */
    fun airedSince(count: Int, since: String): String = "${aired(Copy.episodes(count))} $since"

    /** The same line when nothing aired and the beats are returns and announcements. */
    fun updatesSince(count: Int, since: String): String = "${Copy.updates(count)} $since"

    /**
     * "Since Aug 12" → "since Aug 12".
     *
     * Only the leading WORD is re-cased: lower-casing the whole phrase produced "since 23 **jul**",
     * and a month abbreviation is a proper noun that does not follow the sentence.
     */
    fun sinceFragment(phrase: String): String {
        val lead = phrase.substringBefore(' ')
        return "since " + phrase.removePrefix("$lead ")
    }

    /** What the beats card does when it is tapped — a click label, never a drawn word. */
    const val continuesToWhatIsNext = "Continues to what is next"

    /** What the strip does when it is tapped. */
    const val opensWhatYouMissed = "Opens what you missed"

    /** The beats that did not fit, counted rather than listed. */
    fun andMore(n: Int): String = "and $n more"

    /**
     * "Since your last visit, 23 Jul" — the window always names its anchor.
     *
     * The leading "Since " is stripped from the temporal phrase rather than the phrase being
     * lower-cased whole: "since 23 **jul**" is wrong, because a month abbreviation is a proper
     * noun.
     */
    fun sinceYourLastVisit(phrase: String): String {
        val tail = if (phrase.startsWith("Since ")) phrase.substring(6) else phrase
        return "Since your last visit, $tail"
    }
}

/**
 * The rewatch vocabulary: the start sheet's scope word, and the whole watch-history record.
 *
 * The record's half was staged in `ui/detail/RewatchViews.kt` as a "gap marker" object; it is here
 * now, beside the one string that was already in the table, because a rewatch has one vocabulary
 * and it may not live in two files.
 */
object CopyRewatch {
    /** The scope that covers the whole work (not "All seasons" over a list of OVAs). */
    const val everything = "Everything"


    /** The solo session's eyebrow. A rail needs two nodes, so one session is a labelled row. */
    const val SESSIONS = "Sessions"

    /** The bar's title when the show itself is not in the library any more. */
    const val WATCH_HISTORY = "Watch history"

    /** The session sheet's date row. NOT "Start date" — that label belongs to the start sheet. */
    const val STARTED = "Started"

    /** A completed session's date row: a fact with a value, which is what a form row is for. */
    const val FINISHED = "Finished"

    /** The active session's state, as a FACT on the identity block. */
    const val IN_PROGRESS = "In progress"

    /** A stopped session's state. */
    const val STOPPED = "Stopped"

    /** "Started 24 May" — every row states when it began. */
    fun startedOn(date: String): String = "Started $date"

    /** "Cancelled at episode 4". */
    fun cancelledAt(episode: Int): String = "Cancelled at ${Copy.episodeInSentence(episode)}"

    // -- Stopping (not a deletion, so it does not borrow the destructive verb's copy) -------------

    const val STOP_TITLE = "Stop this rewatch?"

    /** A confirmation BUTTON never ends in an ellipsis. */
    const val STOP_CONFIRM = "Stop rewatch"

    fun stopMessage(episode: Int): String =
        "The session stays in your history, stopped at ${Copy.episodeInSentence(episode)}. " +
            "Your progress is not changed."

    // -- Accessibility ----------------------------------------------------------------------------

    const val OPENS_THIS_SESSION = "Opens this session"

    /** The date row's hint: a row whose value is editable has to say so. */
    const val CHANGES_START_DATE = "Changes the date this watch began"

    /** A session that is still running. The rail states it in colour; a screen reader hears it. */
    const val ACTIVE = "Active"

    /** The bar's back control, which is a glyph and says nothing aloud on its own. */
    const val BACK = "Back"
}

object CopyAccount {
    const val signOutTitle = "Sign out?"
    const val deleteSubtitle = "Erases your library, progress and history"
    const val deleteTitle = "Delete your account?"
    const val deleteConfirm = "Delete account"
    const val deleteFailedTitle = "Couldn’t delete your account"

    /*
     * Why the deletion did not happen, in the words the alert prints — **never a status code**: the
     * user is being told whether their account still exists, and "500" does not answer that.
     *
     * These are the strongest-consequence strings in the app and they used to sit in an enum's
     * constructor arguments in `ui/profile/Settings.kt`, outside even that file's own staging
     * table, so nothing enumerated or gated them.
     */

    /** There is no credential to send. The account was not touched. */
    const val deleteFailedNotSignedIn = "You’re signed out. Sign in again to delete your account."

    /** The server answered, and the answer was not "deleted". */
    const val deleteFailedRefused = "Your account couldn’t be deleted. Nothing was changed."

    /** The request never got an answer. The account may or may not still exist. */
    const val deleteFailedUnreachable = "Couldn’t reach the server. Your account wasn’t deleted."

    /**
     * The three-word rule: "Up to date" / "Checked just now" / "Sync" — three slots, three words,
     * one fact stated once. "Everything synced / Just now / Sync now" said "sync" three times.
     */
    const val upToDate = "Up to date"

    /**
     * Substituted at render for a failed change whose reason is `Copy.Notice.serverError`: the
     * account row says what could not be reached, not what went wrong in the abstract.
     */
    const val couldNotReachServer = "Couldn’t connect"

    const val offlineSupporting = "Changes sync when you reconnect"
    const val showingSavedCopy = "Showing what was saved on this device"
    const val signedInWithClerk = "Signed in"
    const val signOutFailedTitle = "Couldn’t sign out"
    const val signOutFailedMessage = "Check your connection and try again."

    fun discardChangesTitle(n: Int): String = "Discard ${Copy.changes(n)}?"

    const val discardChangesMessage =
        "They were never saved to your account. Your library here stays as it is."

    fun discardChangesConfirm(n: Int): String = "Discard ${Copy.changes(n)}"
}

/**
 * Filter vocabulary shared by Schedule's menu, its chips and Library's Arrange sheet. One phrasing
 * per filter: the same toggle used to read "Hide watched episodes" in the menu, "Watched hidden"
 * on the chip and "watched episodes hidden" to a screen reader.
 */
object CopyFilter {
    const val filter = "Filter"
    const val off = "Off"
    const val source = "Source"
    const val all = "All"
    const val anime = "Anime"
    const val tv = "TV"
    const val hideWatched = "Hide watched"
}

object CopySchedule {
    const val title = "Schedule"

    /**
     * The bar's return control. It lands on today's section, which is in the feed whether or not
     * anything airs — on a quiet day the section prints [nothingScheduled] instead of being
     * skipped, so "Today" always means today.
     */
    const val today = "Today"

    const val tomorrow = "Tomorrow"
    const val scrollToToday = "Scroll to today"
    const val scrollToTodayHint = "Scrolls to today’s episodes"

    /** The day strip's own name, for a screen reader. */
    const val ticker = "Days"

    const val selected = "Selected"
    const val noEpisodes = "No episodes"

    /**
     * The bar control that brings the month grid down over the feed. ONE label in both states —
     * the state is its `stateDescription`, so TalkBack announces a toggle rather than two
     * different buttons.
     */
    const val calendar = "Calendar"

    const val calendarShown = "Shown"
    const val calendarHidden = "Hidden"
    const val previousMonth = "Previous month"
    const val nextMonth = "Next month"

    /**
     * A day in the grid past the end of the feed's window. NOT "no episodes" — the app does not
     * know yet, and saying it does is a different claim.
     */
    const val beyondHorizon = "Not scheduled yet"

    /**
     * The collapsed block of aired days above today — "the last seven days" without saying so
     * twice: its value line counts them.
     */
    const val earlier = "Earlier"

    const val showEarlier = "Show earlier episodes"
    const val hideEarlier = "Hide earlier episodes"

    /** A day in the feed with nothing on it — in practice only today, which is always drawn. */
    const val nothingScheduled = "Nothing scheduled"

    /** Lower case: it is appended inside a spoken label, never drawn on its own. */
    const val reminderSet = "reminder set"

    /** The feed's tail. Falls back to `EmptyStateCopy.nothingScheduled.title` when there is no horizon. */
    fun everythingThrough(date: String): String = "That’s everything through $date"

    /**
     * "3 to watch" — the unwatched count in the Earlier block's value line.
     *
     * Deliberately a bare interpolation: **no NBSP, no `Copy.plural`.** It is a value beside its
     * own label in a two-column row, never a fact inside a sentence that could wrap.
     */
    fun toWatch(n: Int): String = "$n to watch"
}

/**
 * The trailer shelf's vocabulary: what kind of video a card is.
 *
 * Keyed on the wire value rather than the model enum so the catalogue compiles and audits with
 * nothing else on the classpath — the same reason `Copy.statusLabel` takes a raw string. Callers
 * pass `video.kind`'s wire value; an unrecognised one reads "Video", which is also the decode
 * default (`FranchiseVideo.Kind.other`).
 */
object CopyVideo {
    fun kind(kind: String): String = when (kind) {
        "trailer" -> "Trailer"
        "teaser" -> "Teaser"
        "announcement" -> "Announcement"
        "featurette" -> "Featurette"
        "clip" -> "Clip"
        else -> "Video"
    }
}

/** Role words for the people the catalogue lists without one. */
object CopyPeople {
    const val creator = "Creator"
    const val director = "Director"
}

/**
 * The streaming row's words. The providers' marks carry the names; these are for a screen reader
 * and for the attribution the provider data requires.
 */
object CopyWatch {
    /**
     * Keyed on the wire value, as [CopyVideo.kind] is. An unrecognised access level reads
     * "Subscription" — the decode default for `WatchProvider.Access`, and the safest thing to
     * claim about a service we cannot classify.
     */
    fun access(access: String): String = when (access) {
        "free" -> "Free"
        "ads" -> "Free with ads"
        else -> "Subscription"
    }

    /** "Streaming availability by JustWatch" — the attribution the provider data requires. */
    fun attribution(provider: String): String = "Streaming availability by $provider"
}
