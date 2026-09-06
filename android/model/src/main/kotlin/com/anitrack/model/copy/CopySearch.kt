package com.anitrack.model.copy

import java.util.Locale

// Search's strings, in the copy table where every user-facing string lives. Ported from
// `ios/Sources/DesignSystem/Copy+Search.swift`. The search screen and its components reference
// these and carry no literals of their own.
//
// Reached as `Copy.Search.*` through a getter on `Copy`.
//
// The four search-specific `EmptyStateCopy` values the Swift file declares — `searchUnavailable`,
// `searchOffline`, `noScopeMatches`, `noScopeTrending` — live on `EmptyStateCopy`'s companion in
// `Copy.kt`, because a Kotlin companion cannot be reopened in a second file and
// `EmptyStateCopy.searchOffline` must stay resolvable without a per-symbol import at every call
// site. They are grouped and commented there under the same heading.

object CopySearch {
    const val title = "Search"

    // MARK: The field's prompt — one sentence per scope

    /**
     * The prompt names the VERB, not the domain, and it follows the scope. The launchpad's own
     * supporting line is "Search anime and TV by title." — the same sentence with the same
     * conjunction, minus the full stop.
     */
    const val promptAll = "Search anime and TV"
    const val promptAnime = "Search anime"
    const val promptTV = "Search TV"

    /**
     * Keyed on the media filter's wire value (`"all"` / `"anime"` / `"tv"`) rather than the enum,
     * so the catalogue compiles and audits with nothing else on the classpath — the same reason
     * `Copy.statusLabel` takes a raw string. An unrecognised scope falls to the widest prompt,
     * which can never be wrong about what the field will search.
     */
    fun prompt(scope: String): String = when (scope) {
        "anime" -> promptAnime
        "tv" -> promptTV
        else -> promptAll
    }

    /** The scope's own word, for a state that names it ("Nothing in Anime for …"). */
    fun scopeWord(scope: String): String = when (scope) {
        "anime" -> CopyFilter.anime
        "tv" -> CopyFilter.tv
        else -> CopyFilter.all
    }

    // MARK: Section headers

    const val recent = "Recent"
    const val recentlySearched = "Recently searched"

    /**
     * The type line under a bare recent term — what the row IS, the way a media row says
     * "Anime · 2021".
     */
    const val termKind = "Search"

    const val termHint = "Searches for it again"

    /** Also Today's empty-account chart shelf header. */
    const val trendingNow = "Trending now"

    const val moreTrending = "More trending"

    /** No live call site: results are media rows only, no top-match card. */
    const val topMatch = "Top match"

    /** No live call site. */
    const val moreResults = "More results"

    // MARK: Counts

    fun results(n: Int): String = Copy.plural(n, "result", "results")

    fun seasons(n: Int): String = Copy.plural(n, "season", "seasons")

    /**
     * A chart position, two digits, as the shelf caption leads with it.
     *
     * `Locale.ROOT` is load-bearing: the default locale would render Arabic-Indic digits on a
     * device set to one of the locales that uses them, and a chart position is a numeral, not a
     * word. Swift's `String(format:)` is locale-independent by default; this is how you say the
     * same thing in Kotlin.
     */
    fun rank(n: Int): String = String.format(Locale.ROOT, "%02d", n)

    // MARK: The correction line

    fun showingResultsFor(corrected: String): String = "Showing results for “$corrected”"

    fun searchInsteadFor(original: String): String = "Search instead for “$original”"

    // MARK: Notices

    /**
     * A stale result set with a failed refresh over it — the "both sources, one request" case
     * `Copy.Notice`'s per-catalogue lines do not name.
     */
    const val couldNotRefresh = "Results couldn’t refresh"

    // MARK: The forward-looking fact
    //
    // Today spells "New episode" as a private literal in three places and the upcoming tag spells
    // "Airing now"; neither is shared copy on iOS, so Search owns its own two forms here.
    // Recorded in the source as a duplicate to fold.

    const val airingNow = "Airing now"

    fun newEpisode(day: String): String = "New episode $day"

    // MARK: The add control

    const val inLibrary = "In Library"
    const val notInLibrary = "Not in library"
    const val addHint = "Adds it to your library"
    const val ownedHint = "Change its status or remove it"

    /**
     * The long-press item behind an unowned control — the same verb the tap performs. Also the
     * empty-account billboard's capsule on Today.
     */
    const val addToLibrary = "Add to Library"

    // MARK: Recents

    const val removeRecent = "Remove"

    // MARK: Scoped-out state

    const val showAll = "Show all"

    // MARK: The notification primer

    const val primerTitle = "Episode alerts"

    /**
     * **Not "Know the moment a new episode airs."** That claimed a precision the app does not have
     * and the ask itself cannot buy: without `SCHEDULE_EXACT_ALARM` — denied by default on Android
     * 14+ — an alert is armed with `setAndAllowWhileIdle` and can land minutes late, which is what
     * `Copy.Alert.approximate` admits in the app's own words two rows further down. The exact-timing
     * ask does correct it, but only *afterwards*: it is gated on notifications already being
     * allowed, so the user read the stronger claim first and the honest one second, once per
     * install.
     *
     * So: the benefit, without the timing adverb — the same promise the channel description makes
     * ("When an episode of a show you’re watching is out").
     */
    const val primerBody = "Know when a new episode is out."
    const val primerTurnOn = "Turn on"

    /**
     * "Not now", not "No thanks": the OS raises its own permission prompt once, so the honest
     * offer is a deferral — and Profile → Notifications keeps it available for good.
     */
    const val primerNotNow = "Not now"
}
