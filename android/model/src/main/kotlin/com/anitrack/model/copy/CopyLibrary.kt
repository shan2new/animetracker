package com.anitrack.model.copy

// The Library's strings — the root shelf and All titles. Ported from
// `ios/Sources/DesignSystem/Copy+Library.swift`.
//
// A Library screen renders nothing that is not here or in `Copy` proper: the status shelves are
// `Copy.statusLabel`, the "All titles" heading is `Copy.Heading.allTitles`, progress lines are
// `Copy.Progress`.
//
// Reached as `Copy.Library.*` — the Swift declares this inside an `extension Copy`, and a Kotlin
// object cannot be reopened, so `Copy` exposes it through a getter of the same name.

object CopyLibrary {
    const val title = "Library"

    /** The Up Next shelf's header. */
    const val continueWatching = "Continue watching"

    // The root's tab-strip strings went with the tabs (30 Aug): every bucket is a shelf, and
    // an empty bucket simply has no shelf — no per-status empty state to name.

    /** The anticipation shelf. Board 05's word, and the word its captions use ("Returns Oct 2026"). */
    const val returning = "Returning"

    /** A sequel exists and nobody has said when. The absence of a date is the content. */
    const val announced = "Announced"

    /**
     * An unconfirmed report, said as one: "Season 3 rumored". **Never a date, never amber** — with
     * no instant behind it there is nothing for the colour rule to measure, and a rumour dressed as
     * a fact is the one thing a tracker cannot be caught doing.
     */
    fun rumored(next: String?): String =
        if (next.isNullOrEmpty()) "Rumored" else "$next rumored"

    const val allTitlesHint = "Opens your whole library, with search, sorting and filters"

    /** "All 40" — a bare integer. Deliberately **not** through `Copy.plural`: it is a count on a control, not a fact in a sentence. */
    fun allTitlesCount(count: Int): String = "All $count"

    fun allTitlesAccessibility(count: Int): String = "All titles, ${Copy.titles(count)}"

    const val searchPrompt = "Search your library"

    // "View all" is gone (30 Aug): section actions say "See all" everywhere
    // (`Copy.Action.seeAll`) — one verb for one gesture, Today's and Library's alike.
    const val focusTitleHint = "Shows this title in the centre"

    fun partProgress(label: String, watched: Int, total: Int): String {
        val progress = Copy.Progress.watchedOf(watched, total)
        return if (label.isEmpty()) progress else "$label · $progress"
    }

    // MARK: Sort & filter

    const val sortBy = "Sort by"
    const val reverseOrder = "Reverse order"
    const val status = "Status"

    /** The Status picker's "no filter" value. A chip never states it: "Any" is not a criterion. */
    const val anyStatus = "Any"

    /** Says unwatched *what* — the identical word on Schedule's menu means episodes. */
    const val hasUnwatched = "Has unwatched episodes"

    const val view = "View"
    const val viewAs = "View as"

    /** "Recently added, reversed" — the chip names the direction, or it is lying. */
    fun reversed(label: String): String = "$label, reversed"

    const val sortTitle = "Title"
    const val sortAdded = "Recently added"
    const val sortRecent = "Recently updated"
    const val sortProgress = "Most left to watch"

    /** The direction, said in the reader's terms rather than as "ascending". */
    const val reversedTitle = "Z to A"
    const val reversedAdded = "Oldest first"
    const val reversedRecent = "Least recent first"
    const val reversedProgress = "Least left to watch first"

    const val posters = "Posters"
    const val list = "List"

    // MARK: Sections and the index

    /** The month header for titles with no date behind the active sort. */
    const val noDate = "No date"

    const val sectionIndex = "Section index"
    const val sectionIndexHint = "Jumps the list to a section"

    /** The name of the sections rotor a screen reader offers. */
    const val sectionsRotor = "Sections"

    /**
     * Search found nothing while filters are ALSO narrowing the list: the card offers to clear
     * them, the same action `noFilterMatches` carries. Without it a query under a "Watched" chip
     * dead-ended on a card with no way out but the chip row.
     */
    fun noSearchResults(query: String, filtered: Boolean): EmptyStateCopy {
        val base = EmptyStateCopy.noSearchResults(query)
        if (!filtered) return base
        return base.copy(primaryLabel = Copy.Action.clear)
    }
}
