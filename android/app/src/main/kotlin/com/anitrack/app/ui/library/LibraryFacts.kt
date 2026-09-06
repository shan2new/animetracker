package com.anitrack.app.ui.library

import androidx.compose.runtime.Immutable
import com.anitrack.app.AppModel
import com.anitrack.app.LibShelf
import com.anitrack.app.data.RewatchStore
import com.anitrack.model.Franchise
import com.anitrack.model.Formatting
import com.anitrack.model.MediaSource
import com.anitrack.model.ReleaseWindow
import com.anitrack.model.TemporalCopy
import com.anitrack.model.TimeAnchor
import com.anitrack.model.WatchStatus
import com.anitrack.model.copy.Copy
import com.anitrack.model.copy.CopyLibrary
import com.anitrack.model.currentPart
import com.anitrack.model.displayRelease
import com.anitrack.model.effectiveStatus
import com.anitrack.model.episodesBehind
import com.anitrack.model.isRumored
import com.anitrack.model.isUpcoming
import com.anitrack.model.kindWord
import com.anitrack.model.markTarget
import com.anitrack.model.nextPremiere
import com.anitrack.model.watchContext
import java.time.DateTimeException
import java.time.LocalDate
import java.time.ZoneOffset

/*
 * THE LIBRARY'S VOCABULARY — the port of `ios/Sources/Features/Library/LibraryFacts.swift`.
 *
 * Which bucket a show is in, how "when does it come back" is phrased, and the two lines drawn under
 * every Library row. Nothing here draws; it is the one place the Library decides what a show's fact
 * IS, so the shelf, the list and the poster wall cannot reach different conclusions about the same
 * title.
 *
 * Only [ReturnFact] leaks out of the feature — the show page calls it so Detail's COMPLETE block
 * cannot contradict the Library shelf.
 *
 * ## The two rules that run through all of it
 *
 * 1. **The Library is CALM.** Today carries every obligation — behind-counts, mark rings,
 *    countdowns — and the Library carries none. The one number this file can produce is a
 *    behind-count inside `catalogue`'s *lead* on a catalogue row; the ROOT's shelves put the step on
 *    the grey line on purpose.
 * 2. **`lead` and `meta` are never merged.** `lead` renders amber and is only ever a real NEXT
 *    STEP; `meta` renders grey. A card decides its colour from *which field is populated*, so a
 *    merged caption is how this screen came to render "Returns today" in grey while Today drew the
 *    identical class of fact in accent.
 */

// =================================================================================================
// MARK: - LibrarySection
// =================================================================================================

/**
 * The five buckets the Library root draws. Four map 1:1 onto [LibShelf]; the fifth exists because
 * *"coming back" is two different facts wearing one word* — a dated return and an announcement with
 * no date behind it.
 *
 * [rank] is screen order, and **[ANNOUNCED] sits at 3 rather than beside [RETURNING] on purpose**:
 * *"It is the weakest signal on the screen (a sequel exists, nobody has said when), so it must not
 * sit between the dated returns and the shows you are actually living with: seven 'No date
 * announced' rows pushed WATCHING a full screen down."*
 */
enum class LibrarySection(val label: String, val rank: Int) {
    RETURNING(CopyLibrary.returning, 0),

    // The three status words come from the copy table, never from a local spelling: "Finished" and
    // "Completed" are not in this app's vocabulary, and `completed` reads "Watched".
    WATCHING(Copy.statusLabel(WatchStatus.WATCHING.wire), 1),
    PLANNED(Copy.statusLabel(WatchStatus.PLANNED.wire), 2),
    ANNOUNCED(CopyLibrary.announced, 3),
    FINISHED(Copy.statusLabel(WatchStatus.COMPLETED.wire), 4),
}

/** The ONE classifier both Library surfaces route through. */
object LibraryShelving {

    /**
     * Map the model's shelf onto the screen's section, splitting `comingBack` by whether its return
     * is DATED.
     *
     * *"A heading that says RETURNING may not contain a show whose own detail screen says 'Finished'
     * and 'No date announced'."*
     */
    fun section(f: Franchise, appModel: AppModel): LibrarySection =
        when (appModel.libShelf(f)) {
            LibShelf.PLANNED -> LibrarySection.PLANNED
            LibShelf.WATCHING -> LibrarySection.WATCHING
            LibShelf.FINISHED -> LibrarySection.FINISHED
            LibShelf.COMING_BACK ->
                if (ReturnFact.of(f, appModel.nowMinute).dated) {
                    LibrarySection.RETURNING
                } else {
                    LibrarySection.ANNOUNCED
                }
        }
}

// =================================================================================================
// MARK: - ReturnFact
// =================================================================================================

/**
 * "When does it come back", said **once, in one grammar, at the shortest honest precision**.
 *
 * Four phrasings of one fact ("Returns Oct 2026" / "Returns in 2027" / "Returns Jan 2027" /
 * "Returns Late 2027") once appeared within six rows. Board 09's rule: *drop a fact, never truncate
 * one.*
 *
 * @property dated `false` only for **"No date announced"** and for a **rumour**. It is what keeps a
 *   show out of a section headed RETURNING.
 * @property soon **the one flag that decides whether this fact is amber**, on the shelf and in the
 *   catalogue alike. A window with no instant behind it is never `soon` — the colour rule has
 *   nothing to measure. It replaced an older scheme that rationed amber *by row index* at
 *   accessibility sizes: "the fourth returning row printed the identical fact in a different colour
 *   from the third, with nothing in the content to explain it."
 */
@Immutable
data class ReturnFact(val text: String, val dated: Boolean, val soon: Boolean) {

    companion object {

        /** 60 days, in **milliseconds**. Inside it, a dated return is a real next step. */
        const val SOON_HORIZON: Long = 60L * 86_400L * 1000L

        /**
         * The Library's own composition of the temporal grammar for a month/window-precision
         * return. `TemporalCopy` owns every DAY-precision phrasing; only these two coarser forms are
         * assembled here, and this is the one place the prefix is written.
         */
        private const val RETURNS_PREFIX = "Returns "

        /**
         * Beyond this a curated window is prose we do not trust to be a release window at all, so
         * the year is printed instead.
         */
        private const val MAX_WINDOW_PROSE = 20

        /**
         * Evaluate against `appModel.nowMinute` — the clock truncated to the minute, so captions do
         * not re-derive on the 20-second tick.
         */
        fun of(f: Franchise, now: Long): ReturnFact {
            // 1 — a real dated premiere among the franchise's own announced parts always wins.
            val premiere = f.nextPremiere(now)
            if (premiere != null) {
                return ReturnFact(
                    text = TemporalCopy.returns(premiere, now, f.source),
                    dated = true,
                    soon = premiere - now <= SOON_HORIZON,
                )
            }

            val upcoming = f.upcoming

            // 2 — a rumour is labelled one everywhere. Never a date, never amber.
            if (upcoming?.isRumored == true) {
                return ReturnFact(
                    text = CopyLibrary.rumored(upcoming.next),
                    dated = false,
                    soon = false,
                )
            }

            // 3 — no window, or a window with nothing in it: the ABSENCE of a date is the content.
            val window = upcoming?.releaseWindow
            val parts = window?.parts
            if (window == null || parts == null || window.precision == ReleaseWindow.Precision.UNKNOWN) {
                return ReturnFact(
                    text = TemporalCopy.returns(null, now, f.source),
                    dated = false,
                    soon = false,
                )
            }

            // 4 — a day-precision window inside the current year reads as a friendly day.
            //
            //     `MediaSource.TMDB` is passed DELIBERATELY: a curated window is a calendar date and
            //     must be read date-only, whatever the franchise's own source is. The instant is
            //     built at UTC midnight because "a device in UTC+9 reads 'October 2026' as
            //     September".
            if (window.precision == ReleaseWindow.Precision.DAY &&
                parts.year == Formatting.localParts(now, TimeAnchor.UTC_DATE).y
            ) {
                val at = utcMidnight(parts.year, parts.month, parts.day)
                if (at != null) {
                    return ReturnFact(
                        text = TemporalCopy.returns(at, now, MediaSource.TMDB),
                        dated = true,
                        soon = at - now <= SOON_HORIZON,
                    )
                }
            }

            // 5 — day or month precision otherwise: the month it lands in. "Returns Oct 2026".
            if (window.precision == ReleaseWindow.Precision.DAY ||
                window.precision == ReleaseWindow.Precision.MONTH
            ) {
                val at = utcMidnight(parts.year, parts.month, 1)
                if (at != null) {
                    return ReturnFact(
                        text = RETURNS_PREFIX + LibraryDates.monthYear(at, TimeAnchor.UTC_DATE),
                        dated = true,
                        soon = at - now <= SOON_HORIZON,
                    )
                }
            }

            // 6 — a quarter or a bare year is a WINDOW, printed from the server's own prose.
            //
            //     A quarter's month is an ORDERING DEVICE ONLY: "Summer 2027" sorts as July and must
            //     never be printed as a month.
            val prose = upcoming.displayRelease.trim()
            val text = when {
                prose.length == 4 && prose.toIntOrNull() != null -> RETURNS_PREFIX + prose
                prose.length in 1..MAX_WINDOW_PROSE -> RETURNS_PREFIX + prose.lowercasedFirst()
                else -> RETURNS_PREFIX + parts.year.toString()
            }
            return ReturnFact(text = text, dated = true, soon = false)
        }

        /** A bare UTC calendar date as an instant. `null` for a key that is not a real date. */
        private fun utcMidnight(year: Int, month: Int, day: Int): Long? = try {
            LocalDate.of(year, month, day).atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli()
        } catch (_: DateTimeException) {
            null
        }
    }
}

/**
 * "Returns tomorrow" → "returns tomorrow". **Only the first character** — lower-casing the whole
 * phrase produced "returns late 2027" with a month abbreviation mangled elsewhere, and a month
 * abbreviation is a proper noun. (`:model` has the same helper, `internal` to its own module.)
 */
private fun String.lowercasedFirst(): String =
    if (isEmpty()) this else this[0].lowercase() + substring(1)

// =================================================================================================
// MARK: - LibraryDates
// =================================================================================================

/** The one month-precision date the Library prints — captions and month headers alike. */
object LibraryDates {

    /**
     * "Oct 2026", locale-ordered through the `MMMyyyy` skeleton. Read in the supplied anchor's
     * calendar, so a TMDB date-only instant and an AniList instant each land in the month they
     * belong to.
     */
    fun monthYear(ts: Long, anchor: TimeAnchor = TimeAnchor.LOCAL): String =
        Formatting.fmtMonthYear(ts, anchor)
}

// =================================================================================================
// MARK: - LibraryRowFacts
// =================================================================================================

/**
 * The two lines under a Library row title.
 *
 * @property lead renders **amber** and is only ever a real NEXT STEP.
 * @property meta renders **grey**.
 *
 * A fact never appears in both, and a section's own heading is never repeated in the row under it.
 */
@Immutable
data class LibraryRowFacts(val lead: String? = null, val meta: String? = null, val metaLead: String? = null) {

    companion object {

        // -------------------------------------------------------------------------------------
        // The Library ROOT — a shelf, not a catalogue
        // -------------------------------------------------------------------------------------

        /**
         * The caption for a card on one of the root's shelves. The section is already stated by the
         * heading above it, so it is never repeated here.
         */
        fun root(f: Franchise, section: LibrarySection, appModel: AppModel): LibraryRowFacts {
            val now = appModel.nowMinute
            return when (section) {
                LibrarySection.RETURNING -> {
                    val fact = ReturnFact.of(f, now)
                    if (fact.soon) LibraryRowFacts(lead = fact.text)
                    else LibraryRowFacts(meta = fact.text)
                }

                // Never amber — the ABSENCE of a next step is not a next step.
                LibrarySection.ANNOUNCED -> LibraryRowFacts(meta = ReturnFact.of(f, now).text)

                LibrarySection.WATCHING -> {
                    // 1 — a step the user chose.
                    rewatch(f)?.let { return LibraryRowFacts(lead = it) }
                    // 2 — the step rides the GREY line. Behind-counts and amber belong to Today —
                    //     the urgency pact — so the Library says where you stand and never how far
                    //     behind you are.
                    nextStep(f, now)?.let { return LibraryRowFacts(meta = it) }
                    // 3 — nothing to watch in the current part: say when it comes back, if it does.
                    if (f.currentPart?.isUpcoming ?: true) {
                        val fact = ReturnFact.of(f, now)
                        if (fact.dated) {
                            return if (fact.soon) LibraryRowFacts(lead = fact.text)
                            else LibraryRowFacts(meta = fact.text)
                        }
                    }
                    // 4 — `identity()` is UNREACHABLE from here, and that is the fix: before it,
                    //     three consecutive rows answered "what do I owe" with the year the show
                    //     came out — "Attack on Titan · Anime · 2013" — because `standing()` refused
                    //     to speak without a current part.
                    LibraryRowFacts(meta = standing(f) ?: Copy.Progress.caughtUp)
                }

                LibrarySection.PLANNED, LibrarySection.FINISHED -> {
                    rewatch(f)?.let { return LibraryRowFacts(lead = it) }
                    LibraryRowFacts(meta = settled(f) ?: identity(f))
                }
            }
        }

        // -------------------------------------------------------------------------------------
        // ALL TITLES — a catalogue
        // -------------------------------------------------------------------------------------

        /**
         * The caption for a row (or a poster-wall cell) in All titles.
         *
         * A catalogue mixes every status, so **the list state is itself a fact and is always
         * stated** — unless [stateIsGiven], where a status chip above the list already says it.
         *
         * @param compact the poster grid asking the same question in a ~136-dp cell. It is **not a
         *   second implementation and must not reach a different conclusion**: same branches,
         *   shortest honest form of each fact, joined second fact dropped. (The bug this fixed: "the
         *   wall said 'Episode 1 next' in amber where the list said 'Watched' in grey for the same
         *   show one segment apart, and neither mentioned the rewatch that was actually in progress.
         *   A user reads that as the app losing their data.")
         */
        fun catalogue(
            f: Franchise,
            appModel: AppModel,
            stateIsGiven: Boolean = false,
            compact: Boolean = false,
        ): LibraryRowFacts {
            val now = appModel.nowMinute
            val state = if (stateIsGiven) null else listState(f)

            fun joined(x: String): String = when {
                state == null -> x
                compact -> state
                else -> "$state · $x"
            }

            fun lead(full: String): String = if (compact) shortStep(f, now) ?: full else full
            fun stateMeta(): String? = if (compact) null else state

            // 1 — where you stand in what you are watching.
            progress(f, now)?.let {
                return LibraryRowFacts(lead = lead(it), meta = stateMeta())
            }
            // 2 — a rewatch the user started.
            rewatch(f)?.let {
                return LibraryRowFacts(lead = lead(it), meta = stateMeta())
            }
            // 3 — when it comes back. The section guard exists because "'Returns' is the wrong verb
            //     for a Planned show you never started ('Planned · Returns 9 Oct') and for one you
            //     are mid-way through ('Watching · Returns today')."
            val fact = ReturnFact.of(f, now)
            if (fact.dated && LibraryShelving.section(f, appModel) == LibrarySection.RETURNING) {
                return if (fact.soon) {
                    // The state and the date on ONE line, the date in accent (i1-F10).
                    if (compact || stateMeta() == null) LibraryRowFacts(lead = fact.text)
                    else LibraryRowFacts(meta = stateMeta(), metaLead = fact.text)
                } else {
                    LibraryRowFacts(meta = joined(fact.text))
                }
            }
            // 4 — a settled fact about a finished show.
            settled(f)?.let { return LibraryRowFacts(meta = joined(it)) }
            // 5 — where you stand when there is nothing to do about it.
            standing(f)?.let { return LibraryRowFacts(meta = joined(it)) }
            // 6 — the state, or failing that the show's own identity.
            return LibraryRowFacts(meta = state ?: identity(f))
        }

        // -------------------------------------------------------------------------------------
        // The helpers
        // -------------------------------------------------------------------------------------

        /**
         * "Caught up" — **no `currentPart` guard**. The guard is what made three consecutive
         * Watching rows print the year the show came out instead of where the user stands.
         */
        fun standing(f: Franchise): String? =
            if (f.effectiveStatus == WatchStatus.WATCHING) Copy.Progress.caughtUp else null

        /** "Watching" / "Planned" / "Watched" / "Paused" / "Dropped". */
        fun listState(f: Franchise): String = Copy.statusLabel(f.effectiveStatus.wire)

        /** "Second watch · Episode 7 next" — a step the user chose, so it earns the amber line. */
        fun rewatch(f: Franchise): String? {
            val session = RewatchStore.activeSession(f.id) ?: return null
            val part = f.currentPart ?: return null
            return "${session.title} · ${Copy.Progress.episodeNext(part.progress + 1)}"
        }

        /** "3 episodes behind" · "Season 7 · Episode 5 next" — only for a show you are watching. */
        fun progress(f: Franchise, now: Long): String? {
            if (f.effectiveStatus != WatchStatus.WATCHING) return null
            val part = f.currentPart ?: return null
            if (part.isUpcoming) return null
            rewatch(f)?.let { return it }
            if (part.isReleasing) {
                val behind = part.episodesBehind
                return if (behind > 0) Copy.Progress.behind(behind) else null
            }
            return nextStep(f, now)
        }

        /** "Season 7 · Episode 5 next" — the full watch context, wherever there is room for it. */
        fun nextStep(f: Franchise, now: Long): String? {
            val part = f.currentPart ?: return null
            if (part.isUpcoming) return null
            if (part.markTarget(now) <= part.progress) return null
            return Copy.Progress.next(f.watchContext(part, part.progress + 1))
        }

        /** "Episode 5 next" — the same fact in a poster cell's width. */
        fun shortStep(f: Franchise, now: Long): String? {
            val part = f.currentPart ?: return null
            if (part.isUpcoming) return null
            if (part.isReleasing) {
                val behind = part.episodesBehind
                return if (behind > 0) Copy.Progress.behind(behind) else null
            }
            return if (part.markTarget(now) > part.progress) {
                Copy.Progress.episodeNext(part.progress + 1)
            } else {
                null
            }
        }

        /** "Watched twice" — only once there is more than one completed watch to report. */
        fun settled(f: Franchise): String? {
            if (f.effectiveStatus != WatchStatus.COMPLETED) return null
            val count = RewatchStore.summary(f.id).completedCount
            return if (count >= 2) Copy.Progress.watchedTimes(count) else null
        }

        /** "Anime · 2021" / "TV". The last thing a row can say about itself. */
        fun identity(f: Franchise): String {
            val year = f.year ?: return f.kindWord
            return "${f.kindWord} · $year"
        }
    }
}
