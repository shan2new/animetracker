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

    /// Compact form for narrow captions: "Today 8:30 PM" · "Tomorrow" · "Wed 8:30 PM" · "Aug 28".
    static func airsCompact(at ts: Int64, now: Int64, source: MediaSource) -> String {
        let anchor = source.timeAnchor
        let day: String
        switch Formatting.dayDiff(ts: ts, now: now, anchor: anchor) {
        case 0: day = "Today"
        case 1: day = "Tomorrow"
        case 2...6: day = Formatting.fmtDay(ts: ts, now: now, anchor: anchor)
        default: day = Formatting.fmtMonthDay(ts, anchor: anchor)
        }
        return source == .anilist ? "\(day) \(Formatting.fmtTime(ts, anchor: anchor))" : day
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

    /// "Returns tomorrow" · "Returns Friday" · "Returns Oct 2" · "Returns in 2027" · "No date announced".
    static func returns(at ts: Int64?, now: Int64, source: MediaSource) -> String {
        guard let ts else { return "No date announced" }
        let anchor = source.timeAnchor
        switch Formatting.dayDiff(ts: ts, now: now, anchor: anchor) {
        case ..<1: return "Returns today"
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
    static func dateWord(_ ts: Int64, now: Int64, anchor: Formatting.TimeAnchor) -> String {
        let a = Formatting.localParts(ts, anchor: anchor), b = Formatting.localParts(now, anchor: anchor)
        let md = Formatting.fmtMonthDay(ts, anchor: anchor)
        return a.y == b.y ? md : "\(md), \(a.y)"
    }
}
