import Foundation

// Time/date formatting — a faithful Swift port of the legacy web app's `format.ts`.
// ALL time math is in the device-local timezone (TimeZone.current). Timestamps are
// milliseconds since epoch (Int64), matching the API contract; the conversion to/from
// `Date` happens at the networking layer.

enum Formatting {
    // Millisecond constants mirroring format.ts (D = 86400e3, H = 3600e3).
    static let D: Int64 = 86_400_000
    static let H: Int64 = 3_600_000
    static let minuteMs: Int64 = 60_000

    static var tz: TimeZone { TimeZone.current }

    private static let monShort = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    private static let monFull = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
    private static let wdFull = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    private static let wdShort = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    // A Gregorian calendar fixed to the device-local timezone — the Swift analogue of the
    // `Intl.DateTimeFormat` in format.ts. Computed so it always tracks TimeZone.current.
    private static var localCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        return cal
    }

    struct LocalParts {
        var y: Int
        var mo: Int // 1-12
        var d: Int
        var hour: Int // 0-23
        var minute: Int
        var wd: Int // 0=Sun .. 6=Sat
    }

    /// Break a ms-epoch timestamp into its local calendar/clock parts.
    static func localParts(_ ts: Int64) -> LocalParts {
        let date = Date(timeIntervalSince1970: Double(ts) / 1000.0)
        let c = localCalendar.dateComponents([.year, .month, .day, .hour, .minute, .weekday], from: date)
        // Calendar.weekday is 1=Sunday..7=Saturday; format.ts uses 0=Sun..6=Sat.
        let wd = ((c.weekday ?? 1) - 1)
        return LocalParts(
            y: c.year ?? 0,
            mo: c.month ?? 1,
            d: c.day ?? 1,
            hour: c.hour ?? 0,
            minute: c.minute ?? 0,
            wd: wd
        )
    }

    /// A UTC instant marking midnight of the local calendar day containing ts (ms epoch).
    /// Mirrors `Date.UTC(p.y, p.mo - 1, p.d)` so day-diff / same-day math matches the web app.
    static func localDayKey(_ ts: Int64) -> Int64 {
        let p = localParts(ts)
        var c = DateComponents()
        c.year = p.y
        c.month = p.mo
        c.day = p.d
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let date = utc.date(from: c) ?? Date(timeIntervalSince1970: 0)
        return Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    /// Monday-first weekday index (0=Mon .. 6=Sun) in local time.
    static func localMondayCol(_ ts: Int64) -> Int {
        (localParts(ts).wd + 6) % 7
    }

    static func fmtCountdown(target: Int64, now: Int64) -> String {
        var s = max(0, target - now)
        if s < minuteMs { return "now" }
        let d = s / D
        s -= d * D
        let h = s / H
        s -= h * H
        let m = s / minuteMs
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    static func fmtTime(_ ts: Int64) -> String {
        let p = localParts(ts)
        let ap = p.hour >= 12 ? "PM" : "AM"
        let h = p.hour % 12 == 0 ? 12 : p.hour % 12
        let mm = String(format: "%02d", p.minute)
        return "\(h):\(mm) \(ap)"
    }

    static func fmtAgo(ts: Int64, now: Int64) -> String {
        let s = max(0, now - ts)
        let m = s / minuteMs
        if m < 1 { return "just now" }
        if m < 60 { return "\(m)m ago" }
        let h = m / 60
        if h < 24 { return "\(h)h ago" }
        return "\(h / 24)d ago"
    }

    /// "Today" / "Tomorrow" / "Yesterday" / weekday — relative to the local calendar.
    static func fmtDay(ts: Int64, now: Int64) -> String {
        let diff = Int((Double(localDayKey(ts) - localDayKey(now)) / Double(D)).rounded())
        if diff == 0 { return "Today" }
        if diff == 1 { return "Tomorrow" }
        if diff == -1 { return "Yesterday" }
        return wdShort[localParts(ts).wd]
    }

    static func fmtMonthDay(_ ts: Int64) -> String {
        let p = localParts(ts)
        return "\(monShort[p.mo - 1]) \(p.d)"
    }

    /// "Jun 24, 2026" — a year-qualified date, used for premieres that can be far in the future.
    static func fmtFullDate(_ ts: Int64) -> String {
        let p = localParts(ts)
        return "\(monShort[p.mo - 1]) \(p.d), \(p.y)"
    }

    /// Prettify a curated release string from FranchiseUpcoming. A bare ISO date or year-month
    /// becomes a friendly label ("2026-07-05" -> "Jul 5, 2026", "2026-10" -> "Oct 2026");
    /// anything else (already-human windows like "October 2026", "2027", "TBA") passes through.
    static func prettyReleaseString(_ raw: String) -> String {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = s.split(separator: "-").map(String.init)
        func mon(_ m: Int) -> String? { (1...12).contains(m) ? monShort[m - 1] : nil }
        if parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
           let mm = mon(m) { return "\(mm) \(d), \(y)" }
        if parts.count == 2, let y = Int(parts[0]), let m = Int(parts[1]), let mm = mon(m) {
            return "\(mm) \(y)"
        }
        return s
    }

    static func fmtTodayDate(_ now: Int64) -> String {
        let p = localParts(now)
        return "\(wdFull[p.wd]), \(monFull[p.mo - 1]) \(p.d)"
    }

    static func greetingFor(_ now: Int64) -> String {
        let h = localParts(now).hour
        if h < 5 { return "Late night" }
        if h < 12 { return "Good morning" }
        if h < 18 { return "Good afternoon" }
        return "Good evening"
    }

    /// col 0=Mon .. 6=Sun
    static func weekdayNameMonFirst(_ col: Int) -> String {
        wdFull[(col + 1) % 7]
    }

    /// Strip HTML and truncate a synopsis, mirroring `stripHtml` in format.ts.
    static func stripHtml(_ s: String?) -> String {
        guard let s, !s.isEmpty else { return "" }
        let noTags = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let collapsed = noTags.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        let trimmed = collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > 440 {
            let cut = String(trimmed.prefix(437)).trimmingCharacters(in: .whitespacesAndNewlines)
            return cut + "…"
        }
        return trimmed
    }
}

// MARK: - Current "now" helper

extension Int64 {
    /// Current wall-clock time in ms since epoch.
    static var nowMs: Int64 { Int64((Date().timeIntervalSince1970 * 1000).rounded()) }
}
