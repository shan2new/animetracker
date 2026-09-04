package com.anitrack.model.copy

/*
 * THE SHOW PAGE — Detail, its season screen and its shelves.
 *
 * Every one of these is in `spec/detail.md` §9 / §9.2 and in the shipped iOS `Copy.swift`; the
 * Kotlin port of the table simply had not reached them, so they were staged in
 * `ui/detail/EpisodeList.kt` as a "gap marker" object and in `ui/detail/DetailShelves.kt` as a
 * block of file-private constants. Both are here now, as a sibling object in the catalogue package
 * reached through `Copy.Detail.*` — the same move `CopyProfile` records, for the same reason: a
 * string outside the catalogue is a string the copy gate cannot see.
 *
 * Voice, as everywhere: sentence case, curly apostrophes (U+2019), no exclamation marks. A command
 * that opens a confirmation ends in an ellipsis; a confirmation BUTTON never does.
 */
object CopyDetail {


    // --- Confirmations -------------------------------------------------------------------------

    /** "This marks every episode of Attack on Titan as watched, across 4 seasons." */
    fun markSeriesMessage(title: String, seasons: Int): String =
        "This marks every episode of $title as watched, " +
            "across ${Copy.plural(seasons, "season", "seasons")}."

    /** Detail's overflow command. The ellipsis promises the confirmation below. */
    const val cancelRewatchAction = "Cancel rewatch…"

    const val cancelRewatchTitle = "Cancel this rewatch?"

    fun cancelRewatchMessage(episode: Int): String =
        "The session is kept in your history as cancelled at ${Copy.episodeInSentence(episode)}."

    /** A confirmation BUTTON never ends in an ellipsis. */
    const val cancelRewatchConfirm = "Cancel rewatch"

    // --- Toasts --------------------------------------------------------------------------------

    fun markedUnwatched(episode: Int): String = "${Copy.episode(episode)} marked as unwatched"

    fun batchMarkedUnwatched(count: Int): String = "${Copy.episodes(count)} marked as unwatched"

    fun labelMarkedWatched(label: String): String = "$label marked as watched"

    fun labelMarkedUnwatched(label: String): String = "$label marked as unwatched"

    // --- The state block ------------------------------------------------------------------------

    /** The synopsis clamp. Three lines and a MORE, the way Apple TV shows two and a MORE. */
    const val readMore = "Read more"

    const val readLess = "Read less"

    /** The complete card's second fact: when the last watch finished. */
    fun lastFinished(date: String): String = "Last finished $date"

    /**
     * "Returns Oct 2026".
     *
     * The curated window is a MONTH or a quarter and carries no instant, so `TemporalCopy.returns`
     * — which formats from one — cannot form it. Same verb, so the show page and the Library shelf
     * cannot say the same fact two ways.
     */
    fun returnsWindow(release: String): String = "Returns $release"

    // --- Start-rewatch sheet -------------------------------------------------------------------

    /**
     * The context row's line. *"A modal that opens on a grey sentence and a list of radio rows could
     * be about anything"* — so the sheet leads with the show, and this is the reassurance beside it.
     */
    const val historyStaysUnchanged = "Your previous watch history stays unchanged."

    /** The scope list's eyebrow. */
    const val scope = "Scope"

    /**
     * The date row's label. There is no header above it — the header and the row were the same three
     * words, 10 dp apart.
     */
    const val startDate = "Start date"

    /**
     * The date picker's own headline. Material draws "Select date" from its OWN string resources —
     * the one place in the app where Material's prose reached the user — so the dialog is given a
     * title from this table instead, in the app's voice and the app's type.
     */
    const val startDateTitle = "Start date"

    // --- Accessibility -------------------------------------------------------------------------

    fun addToLibrary(title: String): String = "Add $title to Library"

    /** Detail's overflow. */
    const val moreActions = "More actions"

    /** The season screen's overflow. One overflow GLYPH across the two screens, two labels. */
    const val episodeActions = "Episode actions"

    fun seasonPicker(label: String): String = "Season, $label"

    const val choosesAnotherSeason = "Chooses another season"

    const val marksAsWatched = "Marks as watched"

    const val marksAsUnwatched = "Marks as unwatched"

    const val watched = "Watched"

    const val notWatched = "Not watched"

    // --- Movies & extras ------------------------------------------------------------------------
    //
    // The shelf's own vocabulary. iOS builds these at its call sites; here they were a block of
    // file-private constants under a comment naming the violation ("Fold them into `Copy`"), with
    // the part-kind words additionally inlined in a `when` beside them. "Season" in particular is a
    // word the season picker, the show page's header and Schedule's meta line all draw, so it was
    // spelled in several places at once.

    /** The shelf that holds everything the seasons do not: films, OVAs, specials. */
    const val extras = "Extras"

    /** Why a catalogue extra is dimmed. A fact about the row, never a warning. */
    const val notCountedTowardsProgress = "not counted towards progress"

    /** The films toggle's spoken action. */
    const val togglesWatched = "Toggles watched"

    /**
     * The SINGULAR word for a part's kind — what this one thing IS.
     *
     * `PartKind.sectionTitle` is the plural section heading ("OVAs") and would read as a category
     * instead. Keyed on the wire value rather than the enum, as `CopyVideo.kind` and
     * `CopyWatch.access` are, so the catalogue compiles and audits with nothing else on the
     * classpath; an unrecognised kind reads "Season", which is the decode default.
     */
    fun partKind(kind: String): String = when (kind) {
        "movie" -> film
        "ova" -> "OVA"
        "ona" -> "ONA"
        "special" -> "Special"
        "music" -> "Music"
        else -> season
    }

    /** The word on its own, for the call site that names one without a kind in hand. */
    const val film = "Film"

    /** Drawn by the season picker, the show page's header and Schedule's meta line. */
    const val season = "Season"
}
