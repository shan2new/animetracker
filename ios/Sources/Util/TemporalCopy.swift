import Foundation

// One temporal expression per item (spec board 03/09). Exact instants (AniList) get a clock;
// date-only releases (TMDB) get a day word; unknown says unknown. Evaluated in the user's current
// calendar; precedence for the past is top-down: relative → same calendar day → yesterday → weekday → date.
enum TemporalCopy {
    /// "Airs in 27 min" · "Today at 8:30 PM" · "Tomorrow at 8:30 PM" · "Friday at 8:30 PM" ·
    /// "Aug 28 at 8:30 PM" · "Aug 28, 2027 at 8:30 PM" — or for date-only: "Today" · "Tomorrow" ·
    /// "Friday" · "Aug 28" · "Aug 28, 2027".
    static func airs(at ts: Int64, now: Int64, source: MediaSource) -> String {
        let anchor = source.timeAnchor
        let delta = ts - now
        if source == .anilist {
            if delta < 60 * Formatting.minuteMs && delta > 0 {
                return "Airs in \(max(1, Int(delta / Formatting.minuteMs))) min"
            }
            let time = Formatting.fmtTime(ts, anchor: anchor)
            switch Formatting.dayDiff(ts: ts, now: now, anchor: anchor) {
            case 0: return "Today at \(time)"
            case 1: return "Tomorrow at \(time)"
            case 2...6: return "\(Formatting.fmtDayLong(ts: ts, now: now, anchor: anchor)) at \(time)"
            default: return "\(dateWord(ts, now: now, anchor: anchor)) at \(time)"
            }
        }
        switch Formatting.dayDiff(ts: ts, now: now, anchor: anchor) {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case 2...6: return Formatting.fmtDayLong(ts: ts, now: now, anchor: anchor)
        default: return dateWord(ts, now: now, anchor: anchor)
        }
    }

    /// Compact form for narrow captions: "Today" · "Tomorrow" · "Wednesday" · "Aug 28".
    ///
    /// **The compact form drops the CLOCK. It never drops the day word or a preposition.**
    ///
    /// It used to drop both: one frame of Detail showed "Tomorrow at 8:30 PM" (`airs`) directly
    /// beside "Wed 6:30 PM" (this), and two rows of Search showed "Fri 9:30 PM" above
    /// "29 Aug 2:00 PM" — three renderings of "when it airs" in one product, with no rule a reader
    /// could infer, all so a caption could save six characters. Abbreviating the day to "Wed" is
    /// what makes the two forms look like different grammars; the clock is the part a 100-pt
    /// caption genuinely has no room for, and the part the schedule already states elsewhere.
    ///
    /// The day ladder is `airs`'s ladder verbatim, so the two can never drift again.
    static func airsCompact(at ts: Int64, now: Int64, source: MediaSource) -> String {
        let anchor = source.timeAnchor
        switch Formatting.dayDiff(ts: ts, now: now, anchor: anchor) {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case 2...6: return Formatting.fmtDayLong(ts: ts, now: now, anchor: anchor)
        default: return dateWord(ts, now: now, anchor: anchor)
        }
    }

    /// "Aired just now" · "Aired 27 min ago" · "Aired 10h ago" · "Aired yesterday" · "Aired Wednesday" ·
    /// "Aired Aug 19". Date-only sources never get a clock: "Aired today" · "Aired yesterday" · …
    static func aired(at ts: Int64, now: Int64, source: MediaSource) -> String {
        let anchor = source.timeAnchor
        let elapsed = now - ts
        let days = -Formatting.dayDiff(ts: ts, now: now, anchor: anchor)
        if source == .anilist {
            if elapsed < 5 * Formatting.minuteMs { return "Aired just now" }
            if elapsed < 60 * Formatting.minuteMs { return "Aired \(Int(elapsed / Formatting.minuteMs)) min ago" }
            if days == 0 { return "Aired \(Int(elapsed / Formatting.H))h ago" }
        } else if days == 0 {
            return "Aired today"
        }
        switch days {
        case 1: return "Aired yesterday"
        case 2...6: return "Aired \(Formatting.fmtDayLong(ts: ts, now: now, anchor: anchor))"
        default: return "Aired \(dateWord(ts, now: now, anchor: anchor))"
        }
    }

    static let noDateAnnounced = "No date announced"
    /// "Premieres Oct 2" — an announced first air date.
    static func premieres(_ date: String) -> String { "Premieres \(date)" }

    /// "Returns tomorrow" · "Returns Friday" · "Returns Oct 2" · "Returns in 2027" · "No date announced".
    /// A date that has passed says so ("Returned Jul 5") — the catalogue's note can outlive the
    /// premiere by weeks, and every past day used to read "Returns today".
    static func returns(at ts: Int64?, now: Int64, source: MediaSource) -> String {
        guard let ts else { return noDateAnnounced }
        let anchor = source.timeAnchor
        switch Formatting.dayDiff(ts: ts, now: now, anchor: anchor) {
        case ..<0: return "Returned \(dateWord(ts, now: now, anchor: anchor))"
        case 0: return "Returns today"
        case 1: return "Returns tomorrow"
        case 2...6: return "Returns \(Formatting.fmtDayLong(ts: ts, now: now, anchor: anchor))"
        default: return "Returns \(dateWord(ts, now: now, anchor: anchor))"
        }
    }

    /// "Since Tuesday" · "Since Aug 12".
    static func since(_ ts: Int64, now: Int64) -> String {
        let days = -Formatting.dayDiff(ts: ts, now: now)
        switch days {
        case 0: return "Since earlier today"
        case 1: return "Since yesterday"
        case 2...6: return "Since \(Formatting.fmtDayLong(ts: ts, now: now))"
        default: return "Since \(dateWord(ts, now: now, anchor: .local))"
        }
    }

    /// "Aug 28" in the current year, "Aug 28, 2027" otherwise.
    ///
    /// The year is never string-joined on. `"\(md), \(a.y)"` produced **"31 Mar, 2013"** on a
    /// day-first device — a comma between a day-first date and its year, which no locale writes
    /// (en-GB is "31 Mar 2013", en-US "Mar 31, 2013") — and it was on every row of every episode
    /// list. `fmtFullDate` already carries the "MMMdyyyy" skeleton, which orders and punctuates
    /// itself per locale; a hand-assembled date cannot.
    static func dateWord(_ ts: Int64, now: Int64, anchor: Formatting.TimeAnchor) -> String {
        let a = Formatting.localParts(ts, anchor: anchor), b = Formatting.localParts(now, anchor: anchor)
        return a.y == b.y
            ? Formatting.fmtMonthDay(ts, anchor: anchor)
            : Formatting.fmtFullDate(ts, anchor: anchor)
    }

    /// A date range — "24 May – 29 Jul", "10 Dec 2024 – 3 Feb 2025". One formatter, so the two ends
    /// agree with each other and with `dateWord`, and the year is never implied away inside a form.
    ///
    /// Within two taps the shipped build showed "31 Mar, 2013", "24 May – 29 Jul" (no year at all),
    /// "10 Dec, 2024" and "24 May 2026" — four formats, two of them in adjacent rows of one list.
    static func dateRange(_ from: Int64, _ to: Int64, now: Int64,
                          anchor: Formatting.TimeAnchor = .local) -> String {
        let a = Formatting.localParts(from, anchor: anchor)
        let b = Formatting.localParts(to, anchor: anchor)
        let thisYear = Formatting.localParts(now, anchor: anchor).y
        // A span that crosses a year, or sits in a year that is not this one, states both years.
        guard a.y == b.y, a.y == thisYear else {
            return "\(Formatting.fmtFullDate(from, anchor: anchor)) \u{2013} \(Formatting.fmtFullDate(to, anchor: anchor))"
        }
        return "\(Formatting.fmtMonthDay(from, anchor: anchor)) \u{2013} \(Formatting.fmtMonthDay(to, anchor: anchor))"
    }
}
