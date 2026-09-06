package com.anitrack.model.copy

import com.anitrack.model.Time

import java.io.InterruptedIOException
import java.net.SocketException
import java.net.SocketTimeoutException
import java.net.UnknownHostException

// The copy table (spec board 09), as a Kotlin source of truth. Ported from
// `ios/Sources/DesignSystem/Copy.swift` — see `docs/android-port/spec/copy.md`.
//
// Every visible state, action, status, toast, notice, progress line and confirmation string in
// the app resolves to a symbol in here. No screen inlines a sentence again: a string that appears
// on screen either comes from `Copy` or is interpolated data (a title, a date, a count).
//
// This is deliberately NOT `strings.xml`. Roughly 40 % of the table is behaviour — pluralisation,
// the ellipsis table, the freshness ladder, the audit — that a resource file cannot hold, and
// splitting the catalogue across two homes would recreate exactly the "one string, two places"
// defect the table exists to prevent. The app is English-only today; when it stops being, the
// resource move is a whole-table decision, not a per-string one.
//
// Voice: sentence case, no exclamation marks, one supporting sentence, curly apostrophes (U+2019),
// "Previously." always with its full stop. Notation is "Season 4 · Episode 19" — never E19, Ep 19
// or S5 E19.
//
// The brand is NEVER a clause subject. "Previously couldn’t reach the server" — stripped of the
// full stop the name requires — reverts to its ordinary meaning and the line parses as the adverb:
// *previously*, it couldn’t reach the server, i.e. it can now. Nor may a screen substitute its own
// subject ("Search couldn’t reach the server"), which gave one failure two names one tab apart.
// A failure states the fact and nothing else: "Couldn’t reach the server".
//
// Nor does a state promise a benefit on a different tab. "Add your first show and Today builds
// itself." ran verbatim on Library AND Schedule, under a title naming neither. Each surface owns
// its own empty sentence, about itself.
//
// Capitalisation rule (resolves the board 09 / board 03 apparent conflict):
//   • `Episode 19` is capitalised when it is a LABEL or identifier
//     ("Season 4 · Episode 19", "Episode 19 next", "Episode 19 marked as watched");
//   • it is lower-case inside a sentence-case COMMAND ("Mark through episode 1128").
// `episode()` and `episodeInSentence()` are the two forms; nothing else builds the string.
//
// EXACT CODE POINTS. Copy these; do not "normalise" them.
//   U+2019 ’  every apostrophe ("Couldn’t", "You’re", "today’s")
//   U+00B7 ·  the fact separator ("Season 4 · Episode 19")
//   U+2026 …  every ellipsis, the single character — never three dots
//   U+201C “  U+201D ”  quoted query strings
//   U+00A0    non-breaking space — binds a numeral to its noun
//   U+2060    word joiner — welds the batch range, 1⁠–⁠5
//   U+2013 –  en dash — the batch range and every date range
//
// The three at the bottom of that list are INVISIBLE or trivially mistaken for a hyphen, and a
// trim, a reformat or a translation round-trip eats them without a diff anyone reads. Inside a
// string literal they are therefore written as `\uXXXX` escapes; the visible ones stay as glyphs,
// where they are self-documenting and the audit catches the one substitution that matters (a
// straight apostrophe). The line-break behaviour the escapes buy is the whole reason they exist.
object Copy {

    // The time substrate's own constants, not a second spelling of them. These were briefly
    // duplicated here as bare arithmetic to keep the copy table free of a cross-module dependency —
    // but the table now lives in `:model` alongside `Time`, so there is no module boundary left to
    // avoid and a private copy would only be a way for the two to drift apart.
    private const val MINUTE_MS = Time.MINUTE_MS
    private const val HOUR_MS = Time.HOUR_MS

    // MARK: - Namespaces that live in the sibling files
    //
    // Swift reopens `Copy` with extensions; Kotlin objects cannot be reopened, so each extension's
    // namespace is a top-level object wired back in here through a getter. Call sites are
    // unchanged: `Copy.Library.title`, `Copy.Schedule.today`, `Copy.Search.promptAll`.

    /** `CopyLibrary.kt` — the Library root, All titles, the sort/filter vocabulary. */
    val Library get() = CopyLibrary

    /** `CopySearch.kt` — Search's prompts, sections, counts, correction line and primer. */
    val Search get() = CopySearch

    /** `CopyScreens.kt` — Today's recap strip. */
    val Recap get() = CopyRecap

    /** `CopyScreens.kt` — the rewatch scope word. */
    val Rewatch get() = CopyRewatch

    /** `CopyScreens.kt` — Profile's account sheet. */
    val Account get() = CopyAccount

    /** `CopyScreens.kt` — the filter vocabulary shared by Schedule and Library. */
    val Filter get() = CopyFilter

    /** `CopyScreens.kt` — the Schedule agenda. */
    val Schedule get() = CopySchedule

    /** `CopyScreens.kt` — the trailer shelf's kind words. */
    val Video get() = CopyVideo

    /** `CopyScreens.kt` — role words for people the catalogue lists without one. */
    val People get() = CopyPeople

    /** `CopyScreens.kt` — the streaming row. */
    val Watch get() = CopyWatch

    /**
     * `CopyAlerts.kt` — everything the episode-alert feature says: the pushed alert and its bundle,
     * the Android channel, and the exact-timing ask. It absorbed the nested `Copy.Alert` object
     * that used to hold [Alert.episodeOut] alone — one feature, one namespace.
     */
    val Alert get() = CopyAlerts

    /** `CopyBrand.kt` — the wordmark and the two brand lines. The one home for the name. */
    val Brand get() = CopyBrand

    /** `CopyProfile.kt` — the account sheet, its settings rows, its exports and its confirmations. */
    val Profile get() = CopyProfile

    /** `CopyDetail.kt` — the show page, its season screen and its shelves. */
    val Detail get() = CopyDetail

    /** `CopyAuth.kt` — the sign-in gate and the dev-bypass surface. */
    val Auth get() = CopyAuth

    // MARK: - Notation

    /** "Episode 19" — the label form. */
    fun episode(n: Int): String = "Episode $n"

    /** "episode 19" — the form used inside a sentence-case command or message. */
    fun episodeInSentence(n: Int): String = "episode $n"

    /**
     * "Season 4 · Episode 19". `part` is the source's own part label, never derived from order.
     *
     * A numbered season sheds its arc subtitle here: "Season 5: Hashira Training Arc · Episode 1"
     * wrapped every row it appeared on with a separator stranded at the line end, and the arc name
     * is Detail's fact, not a row's. Only `Season N:` prefixes compact — a label like
     * "OVA 2: No Regrets" keeps its subtitle because the subtitle IS the identity there.
     */
    fun watchContext(part: String, episode: Int): String {
        val compact = compactPartLabel(part)
        return if (compact.isEmpty()) Copy.episode(episode) else "$compact · ${Copy.episode(episode)}"
    }

    private val seasonPrefix = Regex("^Season \\d+(?=:)")

    /** "Season 5: Hashira Training Arc" → "Season 5"; anything else unchanged. */
    fun compactPartLabel(label: String): String = seasonPrefix.find(label)?.value ?: label

    /**
     * English-only pluraliser. A per-locale plural rule set is out of scope for this build; every
     * count that reaches the user goes through here so the singular is never "1 episodes".
     *
     * The number is bound to its noun with a non-breaking space: a numeral must never end a line
     * its unit doesn't start ("… · 11 / episodes left" — measured on Today's queue rows). Wraps
     * happen between facts, never inside one.
     *
     * **Not `getQuantityString`.** A plurals resource would drop the NBSP, split the catalogue
     * across two homes and change the call shape at every site.
     */
    fun plural(n: Int, one: String, many: String): String = "$n\u00A0${if (n == 1) one else many}"

    fun episodes(n: Int): String = plural(n, "episode", "episodes")

    /** A runtime, in an episode row's opened details: "55 min". */
    fun minutes(n: Int): String = "$n min"

    /**
     * A count of episodes the USER has watched, predicated so it cannot be read as the work's
     * length. "Watched once - 95 episodes" (the show) and "2 watch sessions - 50 episodes" (the
     * user) sat two taps apart, so within one show the same noun phrase meant 95 and 50.
     * Catalogue counts stay bare; progress counts come through here.
     */
    fun episodesWatched(n: Int): String = "${episodes(n)} watched"

    fun changes(n: Int): String = plural(n, "change", "changes")

    fun watchSessions(n: Int): String = plural(n, "watch session", "watch sessions")

    fun updates(n: Int): String = plural(n, "update", "updates")

    fun titles(n: Int): String = plural(n, "title", "titles")

    // MARK: - Status

    /**
     * The five user-facing statuses — the USER's list state, never the series' production state.
     * Internal `completed` reads "Watched" and `planned` reads "Planned"; "Completed" and
     * "Plan to watch" never appear.
     *
     * **"Finished" is not in this vocabulary.** It was carrying both meanings at once, which is how
     * the app came to file a show as finished on one screen and promise it returns in six weeks on
     * the next — and how one state came to be spelled four ways within two taps: "Finished" in the
     * detail picker, "FINISHED" on the Profile tile, "COMPLETE" on a card eyebrow and "Watched
     * once" in the same card's title. A tracker that cannot name its own states is not trustworthy.
     * "Complete" is now reserved for the *series* (`Progress.complete`), "Watched" for the *user*.
     *
     * Keyed on the **wire string** rather than the enum, exactly as the Swift is, so a status the
     * model gains later still renders. `WatchStatus.displayName` in the model layer is the only
     * other entry point and forwards here.
     */
    fun statusLabel(raw: String): String = when (raw) {
        "watching" -> "Watching"
        "planned" -> "Planned"
        "completed" -> "Watched"
        "paused" -> "Paused"
        "dropped" -> "Dropped"
        // `uppercase()` with no argument is root-locale in Kotlin — never the device's, which
        // would lower-case a Turkish "i" into a dotless one.
        else -> raw.take(1).uppercase() + raw.drop(1)
    }

    /** Display order for a status menu, independent of the enum's declaration order. */
    val statusesInOrder = listOf("Watching", "Planned", "Watched", "Paused", "Dropped")

    // MARK: - Section eyebrows - the "next" vocabulary

    /**
     * Five "next" forms meaning three different things shipped at once: "UP NEXT" (watchable now)
     * and "COMING NEXT" (not yet aired) differed by one word in the same token 60 pt apart;
     * Detail's card eyebrow said "NEXT UP"; Schedule printed "Next up Sun 23 Aug"; a season row
     * printed "Episode 5 next". No rule a reader could infer. The rule, and the only forms:
     *
     *   `nextUp`     - the specific episode you can watch RIGHT NOW. One per screen, at most.
     *   `upcoming`   - episodes that exist but have not aired. Never a second "next" on a screen.
     *   `Progress.episodeNext(n)` - the only POSTFIX form: "Episode 5 next".
     *
     * Nothing else may be worded with "next".
     */
    object Label {
        const val nextUp = "Next up"

        /**
         * The newest AIRED episode you have not watched, on the show page's episode list — the
         * streaming apps' NEW on a tile. Amber is STATE here, never an action; it rides the row's
         * eyebrow beside the episode number.
         */
        const val newTag = "NEW"

        /**
         * The waiting hero's eyebrow. The MOMENT is the fact line under the title, big and in
         * accent, so the eyebrow says only what kind of moment it is.
         */
        const val newEpisode = "New episode"

        /** The empty account's billboard pill: the chart's top show, on the hero's own slate. */
        const val trending = "Trending"

        const val upcoming = "Upcoming"


        const val watching = "Watching"

        /**
         * Today's shelf, since 6 Sep. **"Continue watching", not "Watching"**: the shelf is shows
         * you are part-way through with nothing airing — a caught-up show has nothing to continue,
         * which is what made the old shelf four posters saying the same two words.
         */
        const val continueWatching = "Continue watching"

        /** The SERIES' production state - never the user's list state, which is "Watched". */
        const val complete = "Complete"

        /** The identity line's word for a title the catalogue flags adult with no market rating. */
        const val adultRating = "18+"
    }

    // MARK: - Headings - case and conjunction, settled once

    /**
     * **Sentence case for every heading and control label in this app.** Title Case is for the
     * names of works. "Sort & Filter" and "Seasons & movies" were one screen apart, so the app was
     * visibly using two conventions at once and neither carried meaning.
     *
     * **"&" only between two nouns in a label that must hold one line** ("Sort & filter"); the
     * word "and" in any sentence the user reads. `SectionLabel` uppercases at the point of
     * rendering, so these are stored in the case they are WRITTEN in, not the case they are drawn
     * in - which is what lets one string serve a header and a menu item.
     */
    object Heading {
        const val sortAndFilter = "Sort & filter"
        const val seasonsAndMovies = "Seasons & movies"

        /**
         * The shelf of a franchise's non-season parts under the episode list — films, OVAs that
         * are units, the catalogue's specials.
         */
        const val moviesAndExtras = "Movies & extras"

        /** The Episodes section's title when the work has one season and no name for it. */
        const val episodes = "Episodes"

        /** No live call site in this build. */
        const val searchPrompt = "Anime & TV"

        const val watchHistory = "Watch history"
        const val allTitles = "All titles"

        /** The show page's catalogue shelves, in Apple TV's order: trailers, the people, related. */
        const val trailers = "Trailers"
        const val castAndCrew = "Cast & crew"
        const val moreLikeThis = "More like this"

        /** The streaming row. The providers' marks say who; the header is the way to the options. */
        const val whereToWatch = "Where to watch"
    }

    // MARK: - Actions

    /**
     * One form per intent (board 09). A command that exists here must not be reworded at a call
     * site, shortened to fit a control, or given a second form for a narrow layout.
     *
     * The block marked `Copy+Screens.swift` is what the Swift adds in a second extension; Kotlin
     * objects cannot be reopened across files, so it is folded in here. The namespace is identical.
     */
    object Action {
        const val markAsWatched = "Mark as watched"

        /** No live call site in this build. */
        const val markAsUnwatched = "Mark as unwatched"

        /**
         * "Mark episode 19 watched" — the CTA form that names its object. The bare
         * `markAsWatched` above stays for surfaces that have no single episode to name; a control
         * that KNOWS which episode it writes says so, because "Mark as watched" beside a hero that
         * also shows a behind-count and a latest-aired date left the reader to work out which of
         * three numbers the button would touch.
         */
        fun markEpisodeWatched(n: Int): String = "Mark ${Copy.episodeInSentence(n)} watched"

        /**
         * The same command **spoken with its subject** — "Mark episode 21 watched, Mushoku Tensei".
         *
         * One control may not have two spellings of its own name. Schedule's ring used to build
         * "Mark Episode 21 of Mushoku Tensei as watched" at the call site while `MarkRing`'s own
         * default said "Mark episode 21 watched, Mushoku Tensei" for the identical control one
         * screen away.
         */
        fun markEpisodeWatched(n: Int, title: String): String = "${markEpisodeWatched(n)}, $title"

        /**
         * "Mark episodes 2–5 watched" — a batch command STATES ITS RANGE. "Mark through episode 5"
         * named only its endpoint, so under a hero saying "Episode 1 next · 9 behind" the 5 read
         * as an unexplained third number rather than as first-unwatched + 4.
         */
        fun markThrough(from: Int, to: Int): String =
            // Word-joiners weld the range into one token — a narrow menu line broke it as
            // "episodes 1–" / "5", which reads as a typo, not a range.
            if (from >= to) "Mark ${Copy.episodeInSentence(to)} watched"
            else "Mark episodes $from\u2060\u2013\u2060$to watched"

        /** [markThrough] with its subject, for the same reason [markEpisodeWatched] has one. */
        fun markThrough(from: Int, to: Int, title: String): String =
            "${markThrough(from, to)}, $title"

        fun markAll(n: Int): String = "Mark all ${Copy.episodes(n)} as watched"

        /** The link from the show page's episode window to the whole season: "All 24 episodes". */
        fun allEpisodes(n: Int): String = "All ${Copy.episodes(n)}"

        /** The episode list's in-place doors — Mail's "Load Earlier Messages", both directions. */
        const val showEarlierEpisodes = "Show earlier episodes"
        const val showMoreEpisodes = "Show more episodes"

        const val markAllEpisodes = "Mark all episodes as watched"

        fun markAllUnwatched(n: Int): String = "Mark all ${Copy.episodes(n)} as unwatched…"

        const val markCaughtUp = "Mark as caught up"

        const val startRewatch = "Start rewatch"
        const val continueRewatch = "Continue rewatch"
        const val restartRewatch = "Restart rewatch…"

        /** No live call site in this build. */
        const val fromAnEpisode = "From an episode…"

        const val add = "Add"
        const val addAShow = "Add a show"
        const val removeFromLibrary = "Remove from Library"
        const val deleteWatchHistory = "Delete watch history…"
        const val deleteThisSession = "Delete this session…"

        /** No live call site in this build. */
        const val editSessions = "Edit sessions"

        const val viewEpisodes = "View episodes"
        const val viewWatchHistory = "View watch history"

        /**
         * A **different destination** from a shelf's "See all": this one lands on the Library
         * filtered to *Most left to watch* + unwatched only; "See all" stays on the unfiltered root.
         */
        fun viewAllUpdates(n: Int): String = "View all ${Copy.updates(n)}"

        const val browseYourLibrary = "Browse your library"

        /**
         * **Only as an accessibility label / default action word.** Shelf headers draw no "See all"
         * word: the title IS the button, with a trailing chevron (the Apple TV / Netflix grammar).
         */
        const val seeAll = "See all"

        const val showTitle = "Show title"

        /** No live call site in this build. */
        const val hideTitle = "Hide title"

        const val tryAgain = "Try again"
        const val retry = "Retry"
        const val clear = "Clear"
        const val cancel = "Cancel"
        const val done = "Done"

        /** The trailer sheet's way out to the provider, drawn as a glyph; this is what a screen reader says. */
        const val openOnYouTube = "Open on YouTube"

        const val openInBrowser = "Open in browser"
        const val arrange = "Arrange"
        const val reset = "Reset"
        const val discard = "Discard…"
        const val undo = "Undo"

        // Copy+Screens.swift — strings the screens staged locally during the polish rounds.

        const val details = "Details"
        const val continueLabel = "Continue"
        const val dismissRecap = "Dismiss what you missed"
        const val revealEpisodeTitle = "Reveal episode title"
        const val hideEpisodeTitle = "Hide episode title"
        const val revealEpisodeTitlesAndStills = "Reveal episode titles and stills"
        const val markSeriesWatched = "Mark series as watched"
        const val markRewatchComplete = "Mark this rewatch complete"
        const val stopRewatch = "Stop this rewatch…"
        const val signOut = "Sign out"
        const val deleteAccount = "Delete account"

        /** Title Case — it is the name of a document, not a heading. */
        const val privacyPolicy = "Privacy Policy"

        /** Title Case, same reason. */
        const val termsOfUse = "Terms of Use"

        const val contactSupport = "Contact support"

        /**
         * The word is "Sync", not "Sync now": the row already says "Up to date / Checked just now".
         * "Everything synced / Just now / Sync now" said "sync" three times in three slots.
         */
        const val syncNow = "Sync"

        const val retryAll = "Retry all"
        const val dismiss = "Dismiss"

        /**
         * The mark control's long-press affordance, spoken. It has one call site and no drawn
         * word — the press IS the control — so this string is its name to a screen reader.
         */
        const val moreWaysToMark = "More ways to mark"

        // MARK: The ellipsis rule, as data

        /**
         * Board 09 states the rule as "commands that open a confirmation end in …", but its own
         * action table omits the ellipsis from the forward batch marks — which do confirm. The
         * table's concrete strings win, so `opensConfirmation` is recorded **independently** of
         * the trailing character and the two are never inferred from one another.
         */
        data class Command(val label: String, val opensConfirmation: Boolean) {
            val endsInEllipsis: Boolean get() = label.endsWith("…")
        }

        /** Every command in the table, with a representative argument for the parameterised ones. */
        val commands: List<Command> = listOf(
            Command(markAsWatched, opensConfirmation = false),
            Command(markAsUnwatched, opensConfirmation = false),
            Command(markEpisodeWatched(19), opensConfirmation = false),
            Command(markThrough(from = 6, to = 10), opensConfirmation = true),
            Command(markAll(18), opensConfirmation = true),
            Command(markAllEpisodes, opensConfirmation = true),
            Command(markAllUnwatched(24), opensConfirmation = true),
            Command(markCaughtUp, opensConfirmation = false),
            Command(startRewatch, opensConfirmation = false),
            Command(continueRewatch, opensConfirmation = false),
            Command(restartRewatch, opensConfirmation = true),
            Command(fromAnEpisode, opensConfirmation = true),
            Command(add, opensConfirmation = false),
            Command(removeFromLibrary, opensConfirmation = false),
            Command(deleteWatchHistory, opensConfirmation = true),
            Command(deleteThisSession, opensConfirmation = true),
            Command(viewEpisodes, opensConfirmation = false),
            Command(viewWatchHistory, opensConfirmation = false),
            Command(showTitle, opensConfirmation = false),
            Command(hideTitle, opensConfirmation = false),
            Command(tryAgain, opensConfirmation = false),
            Command(retry, opensConfirmation = false),
            Command(clear, opensConfirmation = false),
            Command(discard, opensConfirmation = true),
        )

        /**
         * True when the command with this exact label opens a confirmation. Unknown labels are
         * answered `false` — an unknown label is a copy defect, not a silent confirmation.
         */
        fun opensConfirmation(label: String): Boolean =
            commands.firstOrNull { it.label == label }?.opensConfirmation ?: false

        /**
         * The invariant the rule really carries: an ellipsis promises a confirmation. (The
         * converse is deliberately not required — see [Command].) Empty means the table is sound.
         */
        val ellipsisViolations: List<String>
            get() = commands.filter { it.endsInEllipsis && !it.opensConfirmation }.map { it.label }

        /** A confirmation BUTTON never ends in an ellipsis. Empty means the table is sound. */
        val confirmationButtonViolations: List<String>
            get() = Copy.Confirm.buttons.filter { it.endsWith("…") }
    }

    // MARK: - Toasts

    object Toast {
        fun marked(episode: Int): String = "${Copy.episode(episode)} marked as watched"

        fun batchMarked(n: Int): String = "${Copy.episodes(n)} marked as watched"

        /**
         * The same fact, carrying its SUBJECT. The bare form names neither show nor season, yet
         * the identical toast fires from a Schedule row and a Library context menu, where the
         * user has just acted on one of several shows and "Episode 2 marked as watched" cannot
         * say which. The title is the part allowed to truncate; the fact never is.
         */
        fun marked(title: String, episode: Int): String =
            if (title.isEmpty()) marked(episode = episode)
            else "$title · ${Copy.episode(episode)} watched"

        fun batchMarked(title: String, n: Int): String =
            if (title.isEmpty()) batchMarked(n) else "$title · ${Copy.episodes(n)} watched"

        /** Remove never touches history, and the toast says so in words. */
        const val removed = "Removed from Library · Watch history kept"
        /** The lane's line — the history clause is spoken, not drawn, beside the show's name. */
        const val removedShort = "Removed from Library"

        /**
         * The status defaults to the Library's own name for the case where the caller has none —
         * on iOS that fallback is a literal at the `UndoState.message` call site, which is one
         * more place a user-facing string can drift. It lives here instead.
         */
        fun added(title: String, status: String = CopyLibrary.title): String = "Added $title to $status"

        /** Shown only where the row leaves the screen as a result of the change (Library). */
        fun movedTo(status: String): String = "Moved to $status"

        const val rewatchStarted = "Rewatch started"

        /** A neutral receipt with no action — `showNotice`, not an Undo toast. */
        const val alertsOn = "Episode alerts on"

        const val rewatchRestarted = "Rewatch restarted"
        const val offlinePending = "Saved on this device. Waiting to sync."

        /** The SyncBanner's line. A failure is never a transient toast. */
        fun syncFailed(n: Int): String = "${Copy.changes(n)} couldn’t sync"
    }

    // MARK: - Inline notices

    /**
     * Noun-first: the thing that failed, then what happened to it. Rendered by `InlineNotice` — a
     * footnote line (glyph + metadata + a "Retry" link), never an alert box.
     */
    object Notice {
        const val today = "Airing dates couldn’t refresh"
        const val schedule = "Your schedule couldn’t refresh"
        const val library = "Your library couldn’t refresh"
        const val detailEpisodes = "Episodes couldn’t refresh"
        const val searchAnime = "Anime results couldn’t refresh"
        const val searchTV = "TV results couldn’t refresh"

        const val noConnection = "No connection"
        const val serverError = "Something went wrong"
        const val signedOut = "Signed out"
        const val timedOut = "Took too long"
        const val rateLimited = "Try again in a minute"

        /** A related title the catalogue has not materialised yet, and a search could not find. */
        const val notInCatalogue = "Not in the catalogue yet"

        /**
         * How a failed write is classified before it is worded. The networking layer owns the
         * exception taxonomy; the copy table owns the ladder, so the mapping lives in exactly one
         * place on each side of the boundary.
         *
         * The API error cases map on as follows — **note the deliberate asymmetry**: a 429 that
         * arrived as an HTTP status reads "Try again in a minute", while a 429 that outlived the
         * retry budget and became the dedicated `rateLimited` error falls to [OTHER] and reads
         * "Something went wrong". That is what the shipped iOS code does. Reproduce it rather than
         * "fixing" it, or the Sync list changes wording for the same user-visible failure.
         *
         *   unauthorized                       -> [UNAUTHORIZED]
         *   http(code, _)                      -> [HTTP] with `httpStatus = code`
         *   transport(underlying)              -> [TRANSPORT] with `cause = underlying`
         *   invalidURL, infrastructure,
         *   rateLimited, decoding              -> [OTHER]
         */
        enum class Failure { UNAUTHORIZED, HTTP, TRANSPORT, OTHER }

        /**
         * The reason a write failed, in the user's words. Never a status code, never a raw
         * exception message — Sync status shows this beside each failed command.
         */
        fun reason(failure: Failure, httpStatus: Int? = null, cause: Throwable? = null): String =
            when (failure) {
                Failure.UNAUTHORIZED -> signedOut
                Failure.HTTP -> if (httpStatus == 429) rateLimited else serverError
                Failure.TRANSPORT -> transportReason(cause)
                Failure.OTHER -> serverError
            }

        /** A throwable that never passed through the API error type at all. */
        fun reason(error: Throwable?): String = transportReason(error)

        /**
         * The Android translation of iOS's `NSURLErrorDomain` ladder (spec §9.3). Six URLError
         * codes collapse to "No connection" there; the equivalent here is the socket-level
         * exception family, walked down the **cause chain** — which is also how an `SSLException`
         * raised over a dead network resolves to "No connection" while a genuine TLS failure keeps
         * falling through to "Something went wrong", exactly as `NSURLErrorSecureConnectionFailed`
         * does on iOS.
         */
        fun transportReason(error: Throwable?): String {
            var e: Throwable? = error
            var hops = 0
            while (e != null && hops < 16) {
                when (e) {
                    // Ordered before InterruptedIOException, which it extends.
                    is SocketTimeoutException -> return timedOut
                    // UnknownHostException extends IOException, not SocketException.
                    is UnknownHostException -> return noConnection
                    // ConnectException / NoRouteToHostException / PortUnreachableException, plus
                    // the reset-and-abort family that answers NSURLErrorNetworkConnectionLost.
                    is SocketException -> return noConnection
                    // OkHttp raises this bare for a call/read timeout it cancelled itself.
                    is InterruptedIOException -> return timedOut
                }
                e = e.cause
                hops++
            }
            return serverError
        }
    }

    // MARK: - Progress text (passive — never an action)

    object Progress {
        /**
         * "18 of 24 watched" — grouped list rows and the reset confirmation only. **Never on a
         * hero or a media row**: where-you-are there is a progress bar, not words.
         */
        fun watchedOf(watched: Int, total: Int): String = "$watched of $total watched"

        /**
         * "18 of 24" — the numeral pair a season header PRINTS, where [watchedOf] is what a screen
         * reader HEARS in its place. Two files drew this by typing the English word "of" beside
         * their own interpolation, so the visible half of one fact lived outside the table that
         * owns it while the spoken half was read from it two lines below.
         */
        fun watchedOfCount(watched: Int, total: Int): String = "$watched of $total"

        fun episodeNext(n: Int): String = "${Copy.episode(n)} next"

        /**
         * "Season 4 · Episode 5 next" — the postfix "next" form over a full watch context. Library
         * used to concatenate this by hand; it is the only sibling `episodeNext` is allowed.
         */
        fun next(context: String): String = "$context next"

        /**
         * The committed state of the mark control. Lives here rather than in a screen's private
         * copy because the split mark button renders it on four surfaces.
         */
        fun episodeWatched(n: Int): String = "${Copy.episode(n)} watched"

        fun episodeAiring(n: Int): String = "${Copy.episode(n)} airing"

        /** Double NBSP: the whole phrase is one unbreakable fact. */
        fun behind(n: Int): String = "${Copy.episodes(n)}\u00A0behind"

        fun left(n: Int): String = "${Copy.episodes(n)}\u00A0left"

        const val caughtUp = "Caught up"

        /**
         * The calm open's headline when the next episode lands TODAY: the day is not "nothing",
         * and "Caught up" printed over an Upcoming row saying "Today at 8:30 PM" was the state
         * shouting over the day's real fact (the same inversion Detail's block fixed). The
         * specifics — which show, what time — stay with the row; the headline only frames the day.
         */
        const val newEpisodeToday = "New episode today"

        /**
         * The airing cadence, said the way Netflix says it ("New episode coming on Saturday"):
         * "New episode Friday at 7:30 PM" · "New episode today at 6:30 PM" · "New episode airs
         * in 27 min". "New", not "next": on a show nine episodes behind, "next episode" is the
         * one YOU watch next and the reader would take the day for its air date.
         *
         * Only the four listed prefixes are re-cased — they are ordinary adverbs and verbs.
         * "Friday", "Sep 12" and "Aug 28, 2027" are proper nouns and keep their capital.
         *
         * (`when` is a Kotlin keyword, so the parameter reads `whenPhrase`; it is the Swift's
         * `when:` label and nothing else.)
         */
        /**
         * The drop that just struck, as a fact under a count: "Episode 21 aired yesterday" (i2).
         * The count is the badge's; this line says WHICH episode and when.
         */
        fun dropAired(episode: Int, whenPhrase: String): String {
            val lowered = listOf("Today", "Tomorrow", "Yesterday").any { whenPhrase.startsWith(it) }
            return "${Copy.episode(episode)} aired ${if (lowered) whenPhrase.lowercasedFirst() else whenPhrase}"
        }

        fun newEpisode(whenPhrase: String): String {
            val lowered = listOf("Today", "Tomorrow", "Airs", "In ").any { whenPhrase.startsWith(it) }
            return "New episode ${if (lowered) whenPhrase.lowercasedFirst() else whenPhrase}"
        }

        const val caughtUpAfterThisEpisode = "Caught up after this episode"

        /**
         * Variant B of the calm day: nothing changed AND nothing is dated. Shared with
         * `EmptyStateCopy.calmToday` so the sentence exists once.
         */
        const val noNewDates = "No new dates have been announced."

        const val lastEpisodeOfTheSeason = "Last episode of the season"

        fun complete(label: String): String = if (label.isEmpty()) "Complete" else "$label complete"

        /** "Watched once" · "Watched twice" · "Watched 4 times". */
        fun watchedTimes(n: Int): String = when {
            n < 1 -> "Not watched yet"
            n == 1 -> "Watched once"
            n == 2 -> "Watched twice"
            else -> "Watched $n times"
        }

        private val ordinalWords = listOf(
            "", "First", "Second", "Third", "Fourth", "Fifth", "Sixth", "Seventh",
            "Eighth", "Ninth", "Tenth",
        )

        /** "First watch" · "Second watch" · "Third watch" · "7th watch". */
        fun ordinalWatch(n: Int): String {
            if (n >= 1 && n < ordinalWords.size) return "${ordinalWords[n]} watch"
            return "$n${ordinalSuffix(n)} watch"
        }

        private fun ordinalSuffix(n: Int): String {
            val tens = n % 100
            if (tens in 11..13) return "th"
            return when (n % 10) {
                1 -> "st"
                2 -> "nd"
                3 -> "rd"
                else -> "th"
            }
        }

        /** The active session's subtitle: "In progress · Episode 7 next". */
        fun inProgress(nextEpisode: Int): String = "In progress · ${Copy.episodeNext(nextEpisode)}"

        const val datesUnknown = "Dates unknown"

        /**
         * A completed session's subtitle: "Jul 4 – Jul 19 · 26 episodes", year-qualified when the
         * session did not finish this year. Absent dates read "Dates unknown" rather than inventing.
         *
         * The separator before the count is U+00B7 with spaces; the range separator is U+2013 with
         * spaces. The year is never string-joined on — [CopyDates.dateWord] carries the locale's
         * own full-date skeleton (see its doc comment).
         */
        fun sessionSpan(
            started: Long?,
            completed: Long?,
            episodes: Int,
            now: Long,
            dates: CopyDates,
        ): String {
            val count = Copy.episodes(episodes)
            if (completed == null) return "$datesUnknown · $count"
            val end = dates.dateWord(completed, now)
            if (started == null || started >= completed) return "$end · $count"
            val sameYear = dates.year(started) == dates.year(completed)
            val start = if (sameYear) dates.monthDay(started) else dates.dateWord(started, now)
            return "$start \u2013 $end · $count"
        }
    }

    /** "Episode 19 next" at the top level too — the single most reused progress line. */
    fun episodeNext(n: Int): String = Progress.episodeNext(n)

    // MARK: - Confirmations (every one states its exact blast radius)

    object Confirm {
        const val cancel = "Cancel"

        // Contiguous / whole-backlog batch mark.
        fun batchMarkTitle(n: Int): String = "Mark ${Copy.episodes(n)} as watched?"

        fun batchMarkMessage(from: Int, to: Int): String =
            "Your progress will move from ${Copy.episodeInSentence(from)} to ${Copy.episodeInSentence(to)}."

        fun batchMarkConfirm(n: Int): String = "Mark ${Copy.episodes(n)} as watched"

        // Reset a season's progress. Nothing is deleted — only progress moves.
        fun resetSeasonTitle(total: Int): String = "Mark ${Copy.episodes(total)} as unwatched?"

        fun resetSeason(label: String, total: Int): String =
            "This sets $label back to ${Copy.Progress.watchedOf(0, total)}. Your watch history is kept."

        fun resetSeasonConfirm(total: Int): String = "Mark ${Copy.episodes(total)} as unwatched"

        // Restart the active rewatch.
        const val restartRewatchTitle = "Restart rewatch?"

        fun restartRewatch(count: Int): String =
            "Restarting discards ${Copy.episodes(count)} of progress in this run. Earlier watches are kept."

        const val restartRewatchConfirm = "Restart rewatch"

        // Delete one session.
        const val deleteSessionTitle = "Delete this session?"

        fun deleteSession(count: Int): String =
            "This permanently removes ${Copy.episodes(count)} from your history. Your other sessions are unchanged."

        const val deleteSessionConfirm = "Delete this session"

        // Delete the whole history.
        const val deleteHistoryTitle = "Delete watch history?"

        fun deleteHistory(sessions: Int, episodes: Int): String =
            "This permanently removes ${Copy.watchSessions(sessions)} covering ${Copy.episodes(episodes)}."

        const val deleteHistoryConfirm = "Delete watch history"

        // Discard a failed change from Sync status.
        const val discardChangeTitle = "Discard this change?"
        const val discardChangeMessage = "It stays on this device and is never saved to your account."
        const val discardChangeConfirm = "Discard change"

        /** Every confirmation BUTTON label. None may end in an ellipsis (board 09). */
        val buttons: List<String>
            get() = listOf(
                batchMarkConfirm(18), resetSeasonConfirm(24), restartRewatchConfirm,
                deleteSessionConfirm, deleteHistoryConfirm, discardChangeConfirm, cancel,
            )
    }

    // MARK: - Session / account state

    object State {
        const val signedOut = "You’re signed out. Sign in again to continue."
        const val checkingForChanges = "Checking for changes"
        const val couldNotCheck = "Couldn’t check for changes"
        const val everythingSynced = "Everything synced"
        const val on = "On"
        const val off = "Off"
        const val neverSynced = "Not synced yet"
    }

    // MARK: - Freshness

    /**
     * "Updated 8 min ago" · "Updated 8h ago" · "Updated yesterday" · "Updated Wednesday" ·
     * "Updated Aug 19" · "Updated Aug 19, 2025". Elapsed time only, so a date-only source can
     * never produce a clock here.
     */
    fun updated(at: Long, now: Long, dates: CopyDates): String = "Updated ${elapsedWord(at, now, dates)}"

    /** "Synced 2 min ago" — Profile's account line, same ladder, different verb. */
    fun synced(at: Long, now: Long, dates: CopyDates): String = "Synced ${elapsedWord(at, now, dates)}"

    /** A screen reader reads the elapsed time spelled out: "Updated 8 hours ago", never "8h". */
    fun updatedSpokenLabel(at: Long, now: Long, dates: CopyDates): String {
        val elapsed = maxOf(0L, now - at)
        val minutes = (elapsed / MINUTE_MS).toInt()
        if (minutes < 1) return "Updated just now"
        if (minutes < 60) return "Updated ${plural(minutes, "minute", "minutes")} ago"
        if (dates.dayDiff(at, now) == 0) {
            return "Updated ${plural((elapsed / HOUR_MS).toInt(), "hour", "hours")} ago"
        }
        return updated(at, now, dates)
    }

    /**
     * One elapsed ladder, so board 09's "Updated 8h ago" and board 08's "Synced 2 min ago" are
     * the same function rendered under two verbs.
     */
    private fun elapsedWord(at: Long, now: Long, dates: CopyDates): String {
        val elapsed = maxOf(0L, now - at)
        val minutes = (elapsed / MINUTE_MS).toInt()
        if (minutes < 1) return "just now"
        if (minutes < 60) return "$minutes min ago"
        return when (dates.dayDiff(at, now)) {
            0 -> "${(elapsed / HOUR_MS).toInt()}h ago"
            -1 -> "yesterday"
            // The day-word formatter only names weekdays in the FUTURE; the past needs the name
            // directly, which is why this ladder asks for it rather than reusing `dateWord`.
            in -6..-2 -> dates.weekdayName(at)
            else -> dates.dateWord(at, now)
        }
    }

    // MARK: - Accessibility values

    object Accessibility {
        const val loading = "Loading"
        const val refreshing = "Refreshing"
        const val complete = "Complete"
        const val active = "Active"
        const val retryHint = "Tries the request again"
        const val changeStatus = "Change status"
        const val playsTrailerHint = "Plays the video"
        const val opensStreamingOptionsHint = "Opens the streaming options"

        // Copy+Screens.swift.
        const val opensTheShowHint = "Opens the show"
        const val sectionHeader = "Section"

        fun removeFilter(text: String): String = "$text. Remove filter"

        fun person(name: String, role: String?): String = role?.let { "$name, $it" } ?: name

        /** The wordmark's full stop is the only live indicator in the app. */
        fun wordmarkLive(n: Int): String =
            if (n == 1) "One followed episode is airing now"
            else "$n followed episodes are airing now"
    }

    // MARK: - Empty states

    /**
     * Board 09's canonical empty copy, plus four states the board's table does not name. Each
     * added one is recorded with the reason it exists on [EmptyStateCopy].
     */
    object Empty {
        val account get() = EmptyStateCopy.emptyAccount
        val noWatching get() = EmptyStateCopy.noWatching
        val offlineCached get() = EmptyStateCopy.offlineCached
        val offlineNoData get() = EmptyStateCopy.offlineNoData
        val serverNoCache get() = EmptyStateCopy.serverNoCache
        val nothingScheduled get() = EmptyStateCopy.nothingScheduled
        val noFilterMatches get() = EmptyStateCopy.noFilterMatches
        val noScheduleMatches get() = EmptyStateCopy.noScheduleMatches
        val everythingSynced get() = EmptyStateCopy.everythingSynced

        fun calmToday(title: String?, whenPhrase: String?): EmptyStateCopy =
            EmptyStateCopy.calmToday(title, whenPhrase)

        fun caughtUp(title: String?, whenPhrase: String?): EmptyStateCopy =
            EmptyStateCopy.caughtUp(title, whenPhrase)

        fun noSearchResults(query: String): EmptyStateCopy = EmptyStateCopy.noSearchResults(query)
    }

    // MARK: - Audit
    //
    // The table's own invariants. On iOS these render in a SwiftUI preview that must come up empty;
    // here they are a plain JVM assertion — `Copy.auditProblems` must be empty, and the invariant
    // matters more than the harness.

    /**
     * Every table string, with a representative argument for the parameterised ones.
     *
     * **It walks every namespace, not only `Copy`'s own.** It used to stop at Action / Confirm /
     * Toast / Notice / Progress / State / the statuses plus `EmptyStateCopy` — which is a corpus
     * comfortably over the `size > 50` floor `CopyAuditTest` guards against a vacuous audit with,
     * so the gate looked healthy while `Copy.Library`, `Copy.Search`, `Copy.Alert` and everything
     * in `CopyScreens.kt` shipped ungated, and the five satellite objects staged in `:app` were not
     * even reachable from here.
     *
     * The **parameterised** entries are what have to be listed by hand: a function cannot be read
     * off a class. Plain `val`s and `const val`s are swept reflectively by `CopyAuditTest` on top
     * of this list, so a new constant in any namespace is audited the moment it is declared.
     */
    val allSampleStrings: List<String>
        get() {
            val out = mutableListOf<String>()
            out += Action.commands.map { it.label }
            out += Confirm.buttons
            out += listOf(
                Toast.marked(episode = 19), Toast.batchMarked(3), Toast.removed,
                Toast.added(title = "One Piece", status = "Watching"), Toast.movedTo("Watched"),
                Toast.offlinePending, Toast.syncFailed(1),
                Notice.today, Notice.schedule, Notice.library, Notice.detailEpisodes,
                Notice.searchAnime, Notice.searchTV,
                Notice.noConnection, Notice.serverError, Notice.signedOut, Notice.timedOut,
                Notice.rateLimited,
                Progress.watchedOf(18, 24), Progress.episodeNext(19), Progress.behind(3),
                Progress.left(1), Progress.caughtUp, Progress.caughtUpAfterThisEpisode,
                Progress.lastEpisodeOfTheSeason, Progress.complete("Season 4"),
                Progress.watchedTimes(2), Progress.ordinalWatch(3),
                Progress.inProgress(nextEpisode = 7), Progress.datesUnknown,
                Confirm.batchMarkTitle(18), Confirm.batchMarkMessage(from = 1122, to = 1140),
                Confirm.resetSeasonTitle(24), Confirm.resetSeason(label = "Season 4", total = 24),
                Confirm.restartRewatchTitle, Confirm.restartRewatch(count = 6),
                Confirm.deleteSessionTitle, Confirm.deleteSession(count = 26),
                Confirm.deleteHistoryTitle, Confirm.deleteHistory(sessions = 2, episodes = 59),
                Confirm.discardChangeTitle, Confirm.discardChangeMessage,
                State.signedOut, State.checkingForChanges, State.couldNotCheck,
                State.everythingSynced, State.neverSynced,
                Accessibility.wordmarkLive(1), Accessibility.wordmarkLive(3),
            )
            out += statusesInOrder
            val states = listOf(
                EmptyStateCopy.emptyAccount, EmptyStateCopy.emptyToday, EmptyStateCopy.emptySchedule,
                EmptyStateCopy.noWatching, EmptyStateCopy.offlineCached, EmptyStateCopy.offlineNoData,
                EmptyStateCopy.searchFailed, EmptyStateCopy.searchLaunchpad, EmptyStateCopy.noSessions,
                EmptyStateCopy.serverNoCache, EmptyStateCopy.noFilterMatches, EmptyStateCopy.noScheduleMatches,
                EmptyStateCopy.nothingScheduled, EmptyStateCopy.everythingSynced,
                EmptyStateCopy.calmToday(title = "Frieren", whenPhrase = "Returns tomorrow"),
                EmptyStateCopy.caughtUp(title = "Frieren", whenPhrase = "Returns tomorrow"),
                EmptyStateCopy.noSearchResults(query = "one pece"),
            )
            for (copy in states) {
                out.add(copy.title)
                copy.supporting?.let { out.add(it) }
                copy.primaryLabel?.let { out.add(it) }
                copy.secondaryLabel?.let { out.add(it) }
            }
            out += parameterisedSamples
            return out
        }

    /**
     * The parameterised strings of every SIBLING namespace, one representative argument each.
     *
     * Their constants are swept reflectively; these are the ones that only exist once something is
     * passed to them.
     */
    private val parameterisedSamples: List<String>
        get() = listOf(
            // CopyAlerts — the alert, its bundle, the channel, the exact-timing ask.
            Alert.episodeOut(12), Alert.episodeOut(null), Alert.episodesOut(3),
            Alert.line(title = "Re:ZERO", episode = 12), Alert.line(title = "Re:ZERO", episode = null),
            // CopyLibrary.
            Library.rumored("Season 3"), Library.rumored(null),
            Library.allTitlesCount(13), Library.allTitlesAccessibility(13),
            Library.partProgress(label = "Season 4", watched = 11, total = 24),
            Library.reversed(Library.sortTitle),
            Library.noSearchResults(query = "one pece", filtered = true).title,
            Library.noSearchResults(query = "one pece", filtered = false).title,
            // CopySearch.
            Search.prompt("anime"), Search.scopeWord("tv"), Search.results(7), Search.seasons(4),
            Search.rank(3), Search.showingResultsFor("one piece"),
            Search.searchInsteadFor("one pece"), Search.newEpisode("Friday"),
            // CopyScreens — Recap, Account, Schedule, Video, Watch.
            Recap.sinceYourLastVisit("Since 23 Jul"), Recap.aired(Copy.episode(19)),
            Recap.airedSince(3, Recap.sinceFragment("Since 23 Jul")),
            Recap.updatesSince(2, Recap.sinceFragment("Since 23 Jul")), Recap.andMore(2),
            Account.discardChangesTitle(3), Account.discardChangesConfirm(3),
            Schedule.everythingThrough("19 Sep"), Schedule.toWatch(3),
            Video.kind("trailer"), Video.kind("nonsense"),
            Watch.access("ads"), Watch.attribution("JustWatch"),
            // CopyProfile.
            Profile.exportAs(Profile.EXPORT_JSON), Profile.signedInAs("Shantanu"),
            Profile.checked(Profile.JUST_NOW), Profile.minutesAgo(4),
            Profile.signOutMessage(0), Profile.signOutMessage(1), Profile.signOutMessage(3),
            Profile.deleteMessage(0), Profile.deleteMessage(13),
            Profile.discardMessage(title = "Re:ZERO", command = Action.markAsWatched),
            // CopyDetail.
            Detail.markSeriesMessage(title = "Attack on Titan", seasons = 4),
            Detail.cancelRewatchMessage(4), Detail.markedUnwatched(19),
            Detail.batchMarkedUnwatched(3), Detail.labelMarkedWatched("Season 4"),
            Detail.labelMarkedUnwatched("Season 4"), Detail.lastFinished("24 May"),
            Detail.returnsWindow("Oct 2026"), Detail.addToLibrary("Re:ZERO"),
            Detail.seasonPicker("Season 4"), Detail.partKind("movie"), Detail.partKind("season"),
            // CopyRewatch.
            Rewatch.startedOn("24 May"), Rewatch.cancelledAt(4), Rewatch.stopMessage(4),
        )

    /** Empty when the table is sound. */
    val auditProblems: List<String>
        get() {
            val problems = mutableListOf<String>()
            problems += Action.ellipsisViolations.map {
                "“$it” ends in an ellipsis but opens no confirmation"
            }
            problems += Action.confirmationButtonViolations.map {
                "confirmation button “$it” ends in an ellipsis"
            }
            problems += audit(allSampleStrings)
            return problems
        }

    /**
     * The three VOICE laws, over any corpus — so the gate can be pointed at strings this file
     * cannot enumerate (every namespace's constants, swept reflectively by `CopyAuditTest`) rather
     * than only at [allSampleStrings].
     */
    fun audit(strings: List<String>): List<String> {
        val problems = mutableListOf<String>()
        problems += strings.filter { hasBannedNotation(it) }.map {
            "“$it” uses banned episode notation"
        }
        problems += strings.filter { it.contains("!") }.map {
            "“$it” uses an exclamation mark"
        }
        problems += strings.filter { it.contains("'") }.map {
            "“$it” uses a straight apostrophe"
        }
        return problems
    }

    /**
     * "E19", "Ep 19", "S5 E19" — never written anywhere in the app (voice law V8).
     *
     * It is a capital-E-followed-by-a-digit scan, so a *title* containing "E4" would trip it. That
     * is fine: the audit only ever runs over the copy table's own strings, never over interpolated
     * data.
     */
    fun hasBannedNotation(s: String): Boolean {
        if (s.contains("Ep ") || s.contains("Ep.")) return true
        for (i in s.indices) {
            if (s[i] == 'E' && i + 1 < s.length && s[i + 1].isDigit()) return true
        }
        return false
    }
}

// MARK: - The date facts the table needs from the time layer

/**
 * The five date facts the copy table needs, and the whole of its dependency on the time layer.
 *
 * All five are evaluated at the **local** anchor — the copy table only ever describes real
 * instants (a sync stamp, a watch session), never a date-only TMDB fact, so no anchor argument
 * crosses this seam. `Formatting` / `TemporalCopy` (ported separately) implement it; on Android
 * `Formatting` has to be injected rather than being a pure object, because the 24-hour clock
 * setting is only readable through a `Context` — which is precisely why the catalogue declares the
 * seam instead of importing the implementation.
 *
 * Naming each method after its origin keeps the two ports auditable against one another.
 */
interface CopyDates {
    /** `Formatting.dayDiff(ts, now, anchor = local)` — 0 today, +1 tomorrow, −1 yesterday. */
    fun dayDiff(ts: Long, now: Long): Int

    /**
     * `Formatting.weekdayNameMonFirst(Formatting.localMondayCol(ts))` — the full standalone
     * weekday name ("Wednesday"), fetched directly because the day-word formatter only names
     * weekdays in the future.
     */
    fun weekdayName(ts: Long): String

    /**
     * `TemporalCopy.dateWord(ts, now, anchor = local)` — "Aug 28" in the current year, "Aug 28,
     * 2027" otherwise.
     *
     * The year is never string-joined on: `"$monthDay, $year"` produced "31 Mar, 2013" on a
     * day-first device, a punctuation no locale writes, and it was on every row of every episode
     * list. The full-date skeleton orders and punctuates itself per locale; a hand-assembled date
     * cannot.
     */
    fun dateWord(ts: Long, now: Long): String

    /** `Formatting.fmtMonthDay(ts, anchor = local)` — "May 4" / "4 May", locale-ordered. */
    fun monthDay(ts: Long): String

    /** `Formatting.localParts(ts, anchor = local).y` — the calendar year the instant falls in. */
    fun year(ts: Long): Int
}

// MARK: - Empty-state copy as data

/**
 * One empty state's copy. It is data, not a view, so the same values drive the card, the
 * screen-reader label and the audit.
 *
 * [symbol] is the **Material Symbols** name, `null` where the state has no glyph (the calm day is
 * a sentence about the user's shows, not an icon). SF Symbols are Apple-licensed and have no
 * automatic mapping, so the names here come from the hand-built table in
 * `docs/android-port/spec/icon-mapping.md`, which is the authoritative inventory; each value below
 * records the SF symbol it replaces so the two tables stay checkable against one another. Use the
 * **Rounded** optical family, weight 400, grade 0 — Outlined's squarer terminals read cold against
 * Outfit.
 */
data class EmptyStateCopy(
    val symbol: String?,
    val title: String,
    val supporting: String?,
    val primaryLabel: String? = null,
    val secondaryLabel: String? = null,
) {
    /**
     * The primary action retries a fetch rather than taking a next step: it is drawn as a quiet
     * capsule, not the accent one. This decides the button's TREATMENT, not its position.
     */
    val isRecovery: Boolean
        get() = primaryLabel == Copy.Action.tryAgain || primaryLabel == Copy.Action.retry

    /** "{Title}. {Supporting}" — the card's single screen-reader label. */
    val spokenLabel: String
        get() = supporting?.let { "$title. $it" } ?: title

    companion object {

        // Board 09's table, verbatim.

        /**
         * LIBRARY's empty account. Every root has its own — see the voice note at the top of
         * `Copy`: a state may not promise a benefit on a tab the user is not looking at.
         *
         * SF `rectangle.stack`.
         */
        val emptyAccount = EmptyStateCopy(
            symbol = "layers",
            title = "Your library is empty",
            supporting = "Everything you add shows up here.",
            primaryLabel = Copy.Action.addAShow,
        )

        /** TODAY's empty account. SF `tv`. */
        val emptyToday = EmptyStateCopy(
            symbol = "tv",
            title = "Nothing to watch yet",
            supporting = "Add a show and this screen fills in with what’s next.",
            primaryLabel = Copy.Action.addAShow,
        )

        /**
         * SCHEDULE's empty account. Distinct from [nothingScheduled], which is a stocked library
         * with no dated episodes in it. SF `calendar`.
         */
        val emptySchedule = EmptyStateCopy(
            symbol = "calendar_month",
            title = "Nothing scheduled",
            supporting = "Add a show and its air dates appear here.",
            primaryLabel = Copy.Action.addAShow,
        )

        /** SF `bookmark`. */
        val noWatching = EmptyStateCopy(
            symbol = "bookmark",
            title = "Nothing in Watching",
            supporting = "Move a show to Watching to build Today.",
            primaryLabel = Copy.Action.browseYourLibrary,
        )

        /** SF `wifi.slash`. */
        val offlineCached = EmptyStateCopy(
            symbol = "wifi_off",
            title = "You’re offline",
            supporting = "Showing what was saved on this device. Changes sync when you reconnect.",
        )

        /** SF `magnifyingglass`. */
        val searchLaunchpad = EmptyStateCopy(
            symbol = "search",
            title = "Find your next show",
            supporting = "Search anime and TV by title.",
        )

        /** SF `clock.arrow.circlepath`. */
        val noSessions = EmptyStateCopy(
            symbol = "history",
            title = "No watch history yet",
            supporting = "Your first watch is recorded when you finish the show. Rewatches appear here as sessions.",
        )

        /**
         * Search's transport failure. The SAME title as [serverNoCache] on purpose — one failure
         * has one name — with a supporting line that names what could not be done.
         *
         * SF `wifi.exclamationmark`. The icon inventory's first pick is `wifi_tethering_error` and
         * its own note prefers `signal_wifi_statusbar_not_connected` on meaning; the copy spec
         * names the latter, so that is what this carries.
         */
        val searchFailed = EmptyStateCopy(
            symbol = "signal_wifi_statusbar_not_connected",
            title = "Couldn’t search right now",
            supporting = "Check your connection and try again.",
            primaryLabel = Copy.Action.tryAgain,
        )

        /** SF `wifi.slash`. */
        val offlineNoData = EmptyStateCopy(
            symbol = "wifi_off",
            title = "You’re offline",
            supporting = "Connect to the internet to load your library.",
            primaryLabel = Copy.Action.tryAgain,
        )

        /**
         * Calm day. Variant A names the next known event; variant B admits there is none. Never
         * both.
         *
         * NOTE: Today no longer renders this as a plate — the calm open is a quiet caught-up line.
         * "Nothing changed since you were last here" led every calm morning with an absence, at
         * display size, above an Upcoming row restating its own supporting sentence. Kept for
         * previews and the audit until another surface needs it.
         *
         * No symbol: the calm day is a sentence about the user's shows, not an icon.
         */
        fun calmToday(title: String?, whenPhrase: String?): EmptyStateCopy {
            val supporting =
                if (title != null && whenPhrase != null) "$title ${whenPhrase.lowercasedFirst()}."
                else Copy.Progress.noNewDates
            return EmptyStateCopy(
                symbol = null,
                title = "Nothing changed since you were last here",
                supporting = supporting,
            )
        }

        /**
         * Caught up. Carries the next event when one is known — never a second "caught up"
         * sentence. SF `checkmark.circle.fill` (Material FILL 1).
         */
        fun caughtUp(title: String?, whenPhrase: String?): EmptyStateCopy {
            val supporting =
                if (title != null && whenPhrase != null) "$title ${whenPhrase.lowercasedFirst()}."
                else null
            return EmptyStateCopy(
                symbol = "check_circle",
                title = "You’re caught up",
                supporting = supporting,
            )
        }

        // Four states board 09's table does not name. Recorded here as the source of truth.

        /**
         * The network is fine and we are not. Chosen over [offlineNoData] by the connectivity
         * monitor, never guessed from the error. SF `exclamationmark.circle`.
         */
        val serverNoCache = EmptyStateCopy(
            symbol = "error",
            title = "Couldn’t load your library",
            // Not "your saved library will appear": in the no-cache state there IS no saved copy,
            // which is the whole reason this state exists rather than `offlineCached`.
            supporting = "Something went wrong. Try again in a moment.",
            primaryLabel = Copy.Action.tryAgain,
        )

        /** Search returned nothing. SF `magnifyingglass`. */
        fun noSearchResults(query: String): EmptyStateCopy = EmptyStateCopy(
            symbol = "search",
            title = "No results for “$query”",
            supporting = "Check the spelling or try another title.",
        )

        /**
         * A filter, not the account, is why the list is empty — so the action clears the filter.
         * SF `slider.horizontal.3`.
         */
        val noFilterMatches = EmptyStateCopy(
            symbol = "tune",
            title = "No titles match",
            supporting = "Clear the filters to see everything in your library.",
            primaryLabel = Copy.Action.clear,
        )

        /** Schedule with a filter that leaves no episode — about episodes and a schedule (i4). */
        val noScheduleMatches = EmptyStateCopy(
            symbol = "filter_list",
            title = "No episodes match",
            supporting = "Clear the filter to see the whole schedule.",
            primaryLabel = Copy.Action.clear,
        )

        /**
         * Schedule with a library that has no dated episodes. Not an error and not empty-account.
         * SF `calendar`.
         */
        val nothingScheduled = EmptyStateCopy(
            symbol = "calendar_month",
            title = "Nothing scheduled",
            supporting = "None of the shows in your library has an upcoming date.",
        )

        /**
         * Sync status's calm frame. It claims only what the sync centre's failed-change list can
         * prove. SF `checkmark.circle.fill` (Material FILL 1).
         */
        val everythingSynced = EmptyStateCopy(
            symbol = "check_circle",
            title = Copy.State.everythingSynced,
            supporting = "No changes are waiting to sync.",
        )

        // Search's four, from Copy+Search.swift. They live on the companion rather than in
        // `CopySearch.kt` because a Kotlin companion cannot be reopened in a second file, and
        // `EmptyStateCopy.searchOffline` must stay resolvable without a per-symbol import.

        /**
         * The catalogue answered with a failure while the device is online. Named after SEARCH —
         * the screen used the library's "Couldn’t load your library" here (captured 2 Sep).
         * SF `exclamationmark.circle`.
         */
        val searchUnavailable = EmptyStateCopy(
            symbol = "error",
            title = "Couldn’t search right now",
            supporting = "Something went wrong. Try again in a moment.",
            primaryLabel = Copy.Action.tryAgain,
        )

        /**
         * The launchpad with no connection and no chart. The SAME title as [offlineCached] — one
         * state has one name — with a supporting line that says what this screen cannot do about
         * it. "Find your next show" over a chart that will never load is a promise, not a state.
         * SF `wifi.slash`.
         */
        val searchOffline = EmptyStateCopy(
            symbol = "wifi_off",
            title = "You’re offline",
            supporting = "Search needs a connection. Trending shows appear when you reconnect.",
            primaryLabel = Copy.Action.tryAgain,
        )

        /**
         * The scope, not the query, is why the list is empty — so the action widens the scope.
         * [noFilterMatches] is Library's ("Clear the filters to see everything in your library")
         * and was shown here verbatim, on a screen that has nothing to do with the library.
         * SF `magnifyingglass`.
         */
        fun noScopeMatches(scope: String, query: String): EmptyStateCopy = EmptyStateCopy(
            symbol = "search",
            title = "Nothing in $scope for “$query”",
            supporting = "Switch the scope to ${CopyFilter.all} to see every result.",
            primaryLabel = CopySearch.showAll,
        )

        /**
         * The launchpad when the SCOPE, not the world, emptied the chart: trending loaded, but
         * none of it is in the selected scope. Shown where the scope bar is NOT on screen (the
         * field is unfocused), so it names the filter and carries the same one-tap way out
         * [noScopeMatches] has — without it the launchpad fell through to "Find your next show",
         * copy that flatly contradicts an active TV-only scope and offers nothing to do about it.
         * SF `line.3.horizontal.decrease`.
         */
        fun noScopeTrending(scope: String): EmptyStateCopy = EmptyStateCopy(
            symbol = "filter_list",
            title = "Nothing trending in $scope",
            supporting = "Switch the scope to ${CopyFilter.all} to see what everyone is watching.",
            primaryLabel = CopySearch.showAll,
        )
    }
}

/**
 * "Returns tomorrow" → "returns tomorrow", so a temporal phrase can follow a title inside one
 * sentence without a second capital. **Only the first character** — lower-casing the whole phrase
 * produced "1 episode aired since 23 jul", and a month abbreviation is a proper noun.
 */
internal fun String.lowercasedFirst(): String =
    if (isEmpty()) this else this[0].lowercase() + substring(1)
