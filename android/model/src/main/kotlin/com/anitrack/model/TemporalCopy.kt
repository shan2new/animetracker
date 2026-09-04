package com.anitrack.model

// One temporal expression per item (spec board 03/09). Exact instants (AniList) get a clock;
// date-only releases (TMDB) get a day word; unknown says unknown. Evaluated in the user's current
// calendar; precedence for the past is top-down: relative → same calendar day → yesterday →
// weekday → date.
//
// Every function comes in two shapes: one taking a `MediaSource` (the shape the screens call, and
// the shape the iOS source has) and one taking the `TimeAnchor` directly. The anchor form is the
// real implementation — nothing here ever branches on the source itself, because
// `MediaSource.timeAnchor` is the ONLY thing about a source that formatting is allowed to see.
object TemporalCopy {

    /**
     * "Airs in 27 min" · "Today at 8:30 PM" · "Tomorrow at 8:30 PM" · "Friday at 8:30 PM" ·
     * "Aug 28 at 8:30 PM" · "Aug 28, 2027 at 8:30 PM" — or for date-only: "Today" · "Tomorrow" ·
     * "Friday" · "Aug 28" · "Aug 28, 2027".
     */
    fun airs(at: Long, now: Long, source: MediaSource): String =
        airs(at, now, source.timeAnchor)

    fun airs(at: Long, now: Long, anchor: TimeAnchor): String {
        val delta = at - now
        if (!anchor.isDateOnly) {
            if (delta < 60 * Formatting.MINUTE_MS && delta > 0) {
                // max(1, …) so a slot 40 seconds out never says "Airs in 0 min".
                return "Airs in ${maxOf(1L, delta / Formatting.MINUTE_MS)} min"
            }
            val time = Formatting.fmtTime(at, anchor)
            return when (Formatting.dayDiff(at, now, anchor)) {
                0 -> "Today at $time"
                1 -> "Tomorrow at $time"
                in 2..6 -> "${Formatting.fmtDayLong(at, now, anchor)} at $time"
                else -> "${dateWord(at, now, anchor)} at $time"
            }
        }
        return when (Formatting.dayDiff(at, now, anchor)) {
            0 -> "Today"
            1 -> "Tomorrow"
            in 2..6 -> Formatting.fmtDayLong(at, now, anchor)
            else -> dateWord(at, now, anchor)
        }
    }

    /**
     * Compact form for narrow captions: "Today" · "Tomorrow" · "Wednesday" · "Aug 28".
     *
     * **The compact form drops the CLOCK. It never drops the day word or a preposition.**
     *
     * It used to drop both: one frame of Detail showed "Tomorrow at 8:30 PM" ([airs]) directly
     * beside "Wed 6:30 PM" (this), and two rows of Search showed "Fri 9:30 PM" above
     * "29 Aug 2:00 PM" — three renderings of "when it airs" in one product, with no rule a reader
     * could infer, all so a caption could save six characters. Abbreviating the day to "Wed" is
     * what makes the two forms look like different grammars; the clock is the part a 100-dp
     * caption genuinely has no room for, and the part the schedule already states elsewhere.
     *
     * The day ladder is [airs]'s ladder verbatim, so the two can never drift again.
     */
    fun airsCompact(at: Long, now: Long, source: MediaSource): String =
        airsCompact(at, now, source.timeAnchor)

    fun airsCompact(at: Long, now: Long, anchor: TimeAnchor): String =
        when (Formatting.dayDiff(at, now, anchor)) {
            0 -> "Today"
            1 -> "Tomorrow"
            in 2..6 -> Formatting.fmtDayLong(at, now, anchor)
            else -> dateWord(at, now, anchor)
        }

    /**
     * "Aired just now" · "Aired 27 min ago" · "Aired 10h ago" · "Aired yesterday" ·
     * "Aired Aug 19". Date-only sources never get a clock: "Aired today" · "Aired yesterday" · …
     *
     * **The 2–6-days-ago band renders a month-day, not a weekday**, because `fmtDayLong` only
     * names weekdays in the FUTURE. iOS's doc comment promises "Aired Wednesday" and its code
     * emits "Aired Sep 2"; the code is what shipped, so the code is what is ported. Changing it is
     * a product decision that must be taken on both platforms at once.
     */
    fun aired(at: Long, now: Long, source: MediaSource): String =
        aired(at, now, source.timeAnchor)

    fun aired(at: Long, now: Long, anchor: TimeAnchor): String {
        val elapsed = now - at
        val days = -Formatting.dayDiff(at, now, anchor)
        if (!anchor.isDateOnly) {
            if (elapsed < 5 * Formatting.MINUTE_MS) return "Aired just now"
            if (elapsed < 60 * Formatting.MINUTE_MS) {
                return "Aired ${elapsed / Formatting.MINUTE_MS} min ago"
            }
            if (days == 0) return "Aired ${elapsed / Formatting.H}h ago"
        } else if (days == 0) {
            return "Aired today"
        }
        return when (days) {
            1 -> "Aired yesterday"
            in 2..6 -> "Aired ${Formatting.fmtDayLong(at, now, anchor)}"
            else -> "Aired ${dateWord(at, now, anchor)}"
        }
    }

    const val noDateAnnounced: String = "No date announced"

    /** "Premieres Oct 2" — an announced first air date, already formatted by the caller. */
    fun premieres(date: String): String = "Premieres $date"

    /**
     * "Returns tomorrow" · "Returns Friday" · "Returns Oct 2" · "No date announced".
     *
     * A date that has passed says so ("Returned Jul 5") — the catalogue's note can outlive the
     * premiere by weeks, and every past day used to read "Returns today" (Mushoku Tensei read
     * "Returns today" two months into its season).
     */
    fun returns(at: Long?, now: Long, source: MediaSource): String =
        returns(at, now, source.timeAnchor)

    fun returns(at: Long?, now: Long, anchor: TimeAnchor): String {
        if (at == null) return noDateAnnounced
        val diff = Formatting.dayDiff(at, now, anchor)
        return when {
            diff < 0 -> "Returned ${dateWord(at, now, anchor)}"
            diff == 0 -> "Returns today"
            diff == 1 -> "Returns tomorrow"
            diff in 2..6 -> "Returns ${Formatting.fmtDayLong(at, now, anchor)}"
            else -> "Returns ${dateWord(at, now, anchor)}"
        }
    }

    /**
     * "Since earlier today" · "Since yesterday" · "Since Aug 12". Always LOCAL — the recap window
     * is anchored to the device's own last visit, which is a real instant.
     *
     * Same divergence as [aired]: the doc comment on iOS promises "Since Tuesday", the code emits
     * "Since Aug 12" for the 2–6 band. Ported as written.
     */
    fun since(ts: Long, now: Long): String {
        val days = -Formatting.dayDiff(ts, now, TimeAnchor.LOCAL)
        return when (days) {
            0 -> "Since earlier today"
            1 -> "Since yesterday"
            in 2..6 -> "Since ${Formatting.fmtDayLong(ts, now, TimeAnchor.LOCAL)}"
            else -> "Since ${dateWord(ts, now, TimeAnchor.LOCAL)}"
        }
    }

    /**
     * "Aug 28" in the current year, "Aug 28, 2027" otherwise.
     *
     * The year is never string-joined on. `"$md, ${a.y}"` produced **"31 Mar, 2013"** on a
     * day-first device — a comma between a day-first date and its year, which no locale writes
     * (en-GB is "31 Mar 2013", en-US "Mar 31, 2013") — and it was on every row of every episode
     * list. `fmtFullDate` already carries the "MMMdyyyy" skeleton, which orders and punctuates
     * itself per locale; a hand-assembled date cannot.
     *
     * Note that `now` is read in the ANCHOR's calendar here, unlike `dayDiff`, which always reads
     * `now` locally. It only matters within a few hours of New Year.
     */
    fun dateWord(ts: Long, now: Long, anchor: TimeAnchor): String {
        val a = Formatting.localParts(ts, anchor)
        val b = Formatting.localParts(now, anchor)
        return if (a.y == b.y) Formatting.fmtMonthDay(ts, anchor)
        else Formatting.fmtFullDate(ts, anchor)
    }

    /**
     * A date range — "24 May – 29 Jul", "10 Dec 2024 – 3 Feb 2025". One formatter, so the two ends
     * agree with each other and with [dateWord], and the year is never implied away inside a form.
     *
     * Within two taps the shipped build showed "31 Mar, 2013", "24 May – 29 Jul" (no year at all),
     * "10 Dec, 2024" and "24 May 2026" — four formats, two of them in adjacent rows of one list.
     *
     * Separator is U+2013 with a space on each side.
     */
    fun dateRange(
        from: Long,
        to: Long,
        now: Long,
        anchor: TimeAnchor = TimeAnchor.LOCAL,
    ): String {
        val a = Formatting.localParts(from, anchor)
        val b = Formatting.localParts(to, anchor)
        val thisYear = Formatting.localParts(now, anchor).y
        // A span that crosses a year, or sits in a year that is not this one, states both years.
        if (a.y != b.y || a.y != thisYear) {
            return "${Formatting.fmtFullDate(from, anchor)} – ${Formatting.fmtFullDate(to, anchor)}"
        }
        return "${Formatting.fmtMonthDay(from, anchor)} – ${Formatting.fmtMonthDay(to, anchor)}"
    }
}
