import SwiftUI

// The Library's vocabulary, in one place.
//
// The panel's blocking finding was that the two Library surfaces disagreed about the same show:
// "Black Clover — Finished" in All titles and "Black Clover — Returns Oct 2026" under RETURNING one
// screen earlier, with "Finished" carrying the user's LIST state on one screen and the series'
// PRODUCTION state on the other. And "Attack on Titan — No date announced" filed under a section
// headed RETURNING, a heading its own detail screen contradicts three ways.
//
// Both are vocabulary problems, so the vocabulary moved out of the views:
//
//  * `LibrarySection` — the buckets, and the ONE classifier that fills them. `RETURNING` now means
//    "a date is known"; everything announced without one gets its own `ANNOUNCED` section, where
//    "No date announced" is the point rather than a contradiction.
//  * `ReturnFact` — one formatter for "when does it come back", at the shortest honest precision.
//    Four phrasings of one fact ("Returns Oct 2026" / "Returns in 2027" / "Returns Jan 2027" /
//    "Returns Late 2027") appeared within six rows because the ≤17-character branch passed the
//    server's prose through verbatim, capital and all.
//  * `LibraryRowFacts` — the row's two lines, ONE implementation, one rule per surface. The root
//    and All titles each had their own `rowMeta`/`rowLead` pair, which is how two Watching rows in
//    one list ended up disagreeing about whether a progress fact appears at all.

// MARK: - Sections

/// A Library bucket. Four of these are `AppModel.LibShelf` verbatim; the fifth exists because
/// "coming back" is two different facts wearing one word.
enum LibrarySection: Int, Hashable, Identifiable, CaseIterable {
    /// A next installment with a KNOWN future date. This is the only section allowed to promise.
    case returning
    /// A next installment is announced and undated. The absence of a date is the content here.
    case announced
    case watching
    case planned
    /// Nothing left to watch and nothing announced.
    case finished

    var id: Int { rawValue }

    /// Board 05's word for the anticipation shelf is **Returning**, which is also the word its
    /// captions use ("Returns Oct 2026"); `LibShelf.label` still says "Coming back".
    var label: String {
        switch self {
        case .returning: return "Returning"
        case .announced: return "Announced"
        case .watching:  return "Watching"
        case .planned:   return "Planned"
        case .finished:  return "Watched"
        }
    }

    /// Board 05 order — Returning · Watching · Planned · Watched — with `Announced` filed between
    /// Planned and Watched. It is the weakest signal on the screen (a sequel exists, nobody has
    /// said when), so it must not sit between the dated returns and the shows you are actually
    /// living with: seven "No date announced" rows pushed WATCHING a full screen down.
    var rank: Int {
        switch self {
        case .returning: return 0
        case .watching:  return 1
        case .planned:   return 2
        case .announced: return 3
        case .finished:  return 4
        }
    }
}

/// The one classifier. Both Library surfaces route through it, so a show cannot be `RETURNING` on
/// the root and something else behind a `See all` that claims to show exactly that section.
@MainActor
enum LibraryShelving {
    static func section(of f: Franchise, appModel: AppModel) -> LibrarySection {
        switch appModel.libShelf(of: f) {
        case .planned:  return .planned
        case .watching: return .watching
        case .finished: return .finished
        case .comingBack:
            return ReturnFact.of(f, appModel: appModel).dated ? .returning : .announced
        }
    }
}

// MARK: - "When does it come back"

/// "Returns Oct 2" · "Returns Oct 2026" · "Returns in 2027" · "Returns in late 2027" ·
/// "No date announced".
///
/// A dated premiere among the parts is the best fact there is, so it wins. Otherwise the curated
/// release window is read at whatever precision it actually has — and re-emitted at the SHORTEST
/// honest granularity rather than passed through: the server sends human windows like
/// `October 2026`, and `Returns October 2026` is 20 characters in a 124-pt caption, which is how
/// the shelf ended up printing `Returns October…`. Board 09's rule is to drop a fact, never to
/// truncate one.
///
/// `dated` is false only for "No date announced" — the one caption that must never be amber, and
/// now also the thing that keeps a show out of a section headed RETURNING.
@MainActor
struct ReturnFact {
    let text: String
    let dated: Bool
    /// **The one flag that decides whether this fact is amber**, on the shelf and in the catalogue
    /// alike — the panel's `nextStepIsLead`.
    ///
    /// Amber means "a step you can take soon". A date fifteen months out is a note in the margin,
    /// and six of them on one shelf turned accent into the caption colour: every visible caption on
    /// the Library root was amber and none of them was an action. Inside the horizon the date
    /// leads on **both** surfaces; outside it, it rides the grey line on both. One derived value,
    /// two call sites, no drift — and it replaces the old `accentAllowed` rationing, which dimmed
    /// the fourth returning row at accessibility sizes for a reason the reader could not see.
    let soon: Bool

    /// Roughly two months. Long enough to cover "the next season starts soon", short enough that a
    /// shelf carrying amber still means something. **Milliseconds** — every instant in this app is
    /// (`AppModel.now` is `.nowMs`, `premiereAt` is `nextAiringAt`), and `Date.timeIntervalSince1970`
    /// is the one place seconds leak in, so it is converted at every crossing below.
    static let soonHorizon: Int64 = 60 * 86_400 * 1000

    /// The single seconds -> milliseconds crossing for a calendar date.
    private static func ms(_ date: Date) -> Int64 { Int64((date.timeIntervalSince1970 * 1000).rounded()) }

    private static func known(_ text: String, at: Int64?, now: Int64) -> ReturnFact {
        ReturnFact(text: text, dated: true, soon: at.map { $0 - now <= soonHorizon } ?? false)
    }

    static func of(_ f: Franchise, appModel: AppModel) -> ReturnFact {
        let now = appModel.now
        func unknown() -> ReturnFact {
            ReturnFact(text: TemporalCopy.returns(at: nil, now: now, source: f.source),
                       dated: false, soon: false)
        }
        if let at = appModel.nextPremiere(of: f) {
            return known(TemporalCopy.returns(at: at, now: now, source: f.source), at: at, now: now)
        }
        guard let upcoming = f.upcoming, let key = upcoming.releaseSortKey else { return unknown() }
        let y = key.value / 10000, month = (key.value / 100) % 100, day = key.value % 100
        // Day precision inside the current year gets the friendly form — "Returns tomorrow",
        // "Returns Saturday", "Returns Oct 2" — which is also always the shortest.
        if key.precision >= 3, y == Formatting.localParts(now, anchor: .utcDate).y,
           let date = utcDay(y: y, month: month, day: day) {
            let at = ms(date)
            return known(TemporalCopy.returns(at: at, now: now, source: .tmdb), at: at, now: now)
        }
        // Everything else settles at month-and-year: "Returns Oct 2026" fits, "Oct 2, 2027" does
        // not, and a day nine months out is not a fact anybody acts on.
        if key.precision >= 2, let date = utcDay(y: y, month: month, day: 1) {
            return known("Returns \(monthYear.string(from: date))", at: ms(date), now: now)
        }
        // `releaseSortKey` only reads ISO, but the curated windows arrive as prose — "October 2026"
        // resolves to year precision there and would throw away a month we actually know.
        let window = upcoming.displayRelease.trimmingCharacters(in: .whitespacesAndNewlines)
        if let date = parseWindow(window) {
            return known("Returns \(monthYear.string(from: date))", at: ms(date), now: now)
        }
        // Anything that is not a month is a WINDOW, and a window takes the preposition: "Returns in
        // 2027", "Returns in late 2027" — never "Returns 2027", and never the server's capital
        // dropped into the middle of a sentence. One rule, so six rows cannot phrase it four ways.
        // A window is never `soon`: "in late 2027" is not a step anybody takes this week.
        if window.count == 4, Int(window) != nil {
            return known("Returns in \(window)", at: nil, now: now)
        }
        if !window.isEmpty, window.count <= 20 {
            return known("Returns in \(ReturnFact.lowerFirst(window))", at: nil, now: now)
        }
        // A window too long to state whole is reduced to its year rather than ellipsed.
        if y > 1900 { return known("Returns in \(y)", at: nil, now: now) }
        return unknown()
    }

    /// `String.lowercasedFirst()` lives `fileprivate` in `Copy.swift`; this is the same rule.
    /// SHARED-FILE REQUEST: raise that helper's visibility rather than keeping two of it.
    nonisolated static func lowerFirst(_ s: String) -> String {
        guard let first = s.first else { return s }
        return first.lowercased() + s.dropFirst()
    }

    /// The prose release windows the catalogue actually ships, read in English because that is what
    /// the server writes them in. A failure here costs a month, never a wrong month.
    private static func parseWindow(_ s: String) -> Date? {
        guard !s.isEmpty else { return nil }
        return windowParsers.lazy.compactMap { $0.date(from: s) }.first
    }

    private static let windowParsers: [DateFormatter] = ["MMMM yyyy", "MMMM d, yyyy", "MMM d, yyyy"]
        .map { format in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "UTC")
            formatter.dateFormat = format
            return formatter
        }

    /// A curated release window is a calendar date, not an instant: read it in UTC or a device in
    /// UTC+9 reads "October 2026" as September.
    private static func utcDay(y: Int, month: Int, day: Int) -> Date? {
        var parts = DateComponents()
        parts.year = y; parts.month = month; parts.day = day
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar.date(from: parts)
    }

    /// "Oct 2026" — locale-ordered, so a device set to a different region still reads correctly.
    private static let monthYear: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.setLocalizedDateFormatFromTemplate("MMMyyyy")
        return formatter
    }()
}

// MARK: - Row facts

/// The two lines under a Library row title, resolved once for both surfaces.
///
/// `lead` is amber and is only ever a real NEXT STEP. `meta` is grey and states what the thing is
/// or where it stands. A fact never appears in both, and a section's own heading is never repeated
/// in the row underneath it.
@MainActor
struct LibraryRowFacts {
    var lead: String?
    var meta: String?

    /// LIBRARY ROOT — a shelf, not a catalogue. Progress only: the status word is already the
    /// section heading 10 pt above, and printing it again is a row telling you what you just read.
    ///
    /// Colour is decided by `ReturnFact.soon` and nothing else. The old `accentAllowed` parameter
    /// rationed amber by ROW INDEX at accessibility sizes — the fourth returning row printed the
    /// identical fact in a different colour from the third, with nothing in the content to explain
    /// it. The horizon rule says the same thing honestly: near dates lead, far dates do not.
    static func root(_ f: Franchise, section: LibrarySection, appModel: AppModel) -> LibraryRowFacts {
        switch section {
        case .returning:
            let fact = ReturnFact.of(f, appModel: appModel)
            return fact.soon ? LibraryRowFacts(lead: fact.text, meta: nil)
                             : LibraryRowFacts(lead: nil, meta: fact.text)
        case .announced:
            // Never amber: the ABSENCE of a next step is not a next step.
            return LibraryRowFacts(lead: nil, meta: ReturnFact.of(f, appModel: appModel).text)
        case .watching:
            // ONE grammar, in one order: the step you owe → the date it comes back → caught up.
            // The shipped rows fell through to "TV · 2024" whenever a Watching show's current part
            // had not aired yet, so four consecutive Watching rows read "Caught up", "TV · 2024",
            // "Anime · 2019" and "Season 7 · Episode 5 next" with no visible reason for the change.
            if let step = progress(f, now: appModel.now) {
                return LibraryRowFacts(lead: step, meta: nil)
            }
            // The return date only replaces "Caught up" when there is genuinely nothing airing:
            // a show you are mid-season on says where you stand, not when its next season lands.
            if f.currentPart.map(\.isUpcoming) ?? true {
                let fact = ReturnFact.of(f, appModel: appModel)
                if fact.dated {
                    return fact.soon ? LibraryRowFacts(lead: fact.text, meta: nil)
                                     : LibraryRowFacts(lead: nil, meta: fact.text)
                }
            }
            // `identity()` is NOT reachable from here. On the shelf you open to answer "what do I
            // owe", three consecutive rows answered with the year the show came out — "Attack on
            // Titan · Anime · 2013" — because `standing()` refused to speak without a current part.
            // A Watching show with nothing left in flight IS caught up; that is the whole meaning
            // of the word, and it is the only honest thing this row can say.
            return LibraryRowFacts(lead: nil, meta: standing(f) ?? Copy.Progress.caughtUp)
        case .planned, .finished:
            // A rewatch in flight outranks every settled word: it is forward-looking, so it leads.
            if let re = rewatch(f) { return LibraryRowFacts(lead: re, meta: nil) }
            return LibraryRowFacts(lead: nil, meta: settled(f, now: appModel.now) ?? identity(f))
        }
    }

    /// ALL TITLES — a catalogue that mixes every status, so the list state IS a fact and is always
    /// stated. One rule, no exceptions: state always, plus the one thing that is true about where
    /// you stand — caught up, or the season that is coming. The forward date rides the grey line
    /// here rather than the amber one; amber in a 300-row catalogue is reserved for the rows that
    /// are actually waiting on you.
    ///
    /// `stateIsGiven` is true when a status filter is active: the chip above the list already says
    /// "Watching", so printing it again on all ten rows is the row telling you what you just read.
    ///
    /// `compact` is the POSTER GRID asking the same question in a 136-pt cell. It is not a second
    /// implementation and it is not allowed to reach a different conclusion: the grid gets the same
    /// branches, with each fact stated at its shortest honest length and the joined second fact
    /// dropped (board 09 — drop a fact, never truncate one). The two view modes disagreeing about
    /// one show — grid "Episode 1 next" in amber, list "Watched" in grey, one segment apart — is
    /// what a user reads as the app losing their data, so the mode may change the layout and never
    /// the facts.
    static func catalogue(_ f: Franchise, appModel: AppModel,
                          stateIsGiven: Bool = false,
                          compact: Bool = false) -> LibraryRowFacts {
        let state: String? = stateIsGiven ? nil : listState(f)
        func joined(_ extra: String) -> String {
            guard let state else { return extra }
            return compact ? state : "\(state) \u{00B7} \(extra)"
        }
        func lead(_ full: String) -> String {
            compact ? (shortStep(f, now: appModel.now) ?? full) : full
        }
        if let step = progress(f, now: appModel.now) {
            return LibraryRowFacts(lead: lead(step), meta: compact ? nil : state)
        }
        // A rewatch of a WATCHED show never reached `progress()` (it guards on `.watching`), so the
        // catalogue said "Watched" about a show the user is actively re-watching and nothing on any
        // surface said a session was in flight.
        if let re = rewatch(f) {
            return LibraryRowFacts(lead: lead(re), meta: compact ? nil : state)
        }
        // A near date is the same next step here as it is on the shelf, and it wears the same
        // colour — that is `ReturnFact.soon`'s whole job. A far date rides the GREY line joined to
        // the state: "Watched · Returns Oct 2026" is the sentence that stops the catalogue
        // contradicting the shelf, and thirteen amber dates in a thirty-row list would drown the
        // four rows that are actually waiting.
        // ...but only for a show that genuinely went away and is coming back. "Returns" is the
        // wrong verb for a Planned show you never started ("Planned · Returns 9 Oct") and for one
        // you are mid-way through ("Watching · Returns today"); the classifier already knows the
        // difference, so it decides.
        let fact = ReturnFact.of(f, appModel: appModel)
        if fact.dated, LibraryShelving.section(of: f, appModel: appModel) == .returning {
            if fact.soon { return LibraryRowFacts(lead: fact.text, meta: compact ? nil : state) }
            return LibraryRowFacts(lead: nil, meta: joined(fact.text))
        }
        if let settled = settled(f, now: appModel.now) {
            return LibraryRowFacts(lead: nil, meta: joined(settled))
        }
        if let standing = standing(f) {
            return LibraryRowFacts(lead: nil, meta: joined(standing))
        }
        // With the state suppressed and nothing else to say, the row states what the thing IS
        // rather than going mute — a useful fact in place of a repeated one.
        return LibraryRowFacts(lead: nil, meta: state ?? identity(f))
    }

    /// "Caught up" — true of any Watching show with nothing left to watch, which now includes the
    /// case the shipped build fell through on: no current part at all.
    ///
    /// The `currentPart != nil` guard was the whole of B4. A show you are watching whose season has
    /// finished airing has no current part, so this returned nil and three consecutive WATCHING
    /// rows fell through to `identity()` — "Anime · 2013", "TV · 2024", "Anime · 2019". A release
    /// year is never an answer to "what do I owe". Having nothing in flight is exactly what being
    /// caught up means, so that is what it says.
    static func standing(_ f: Franchise) -> String? {
        guard f.effectiveStatus == .watching else { return nil }
        return Copy.Progress.caughtUp
    }

    /// The user's LIST state — never the series' production state. `completed` reads **Watched**;
    /// "Finished" is not in the app's vocabulary any more (`Copy.Status`), so the detail picker,
    /// the Profile tile and this list cannot spell one state three ways.
    static func listState(_ f: Franchise) -> String { listState(status: f.effectiveStatus) }

    static func listState(status: WatchStatus) -> String { Copy.Status(status) }

    /// An in-flight rewatch, whatever the list state says. It is the only forward-looking fact a
    /// *Watched* show can have, and until now no surface in the app printed it.
    static func rewatch(_ f: Franchise) -> String? {
        guard let active = RewatchStore.shared.activeSession(for: f.id),
              let p = f.currentPart else { return nil }
        return "\(active.title) \u{00B7} \(Copy.Progress.episodeNext(p.progress + 1))"
    }

    /// The forward-looking step, in amber, and only when there genuinely is one. A settled state
    /// ("Caught up", "Watched twice") is never a lead.
    static func progress(_ f: Franchise, now: Int64) -> String? {
        guard f.effectiveStatus == .watching, let p = f.currentPart, !p.isUpcoming else { return nil }
        if let re = rewatch(f) { return re }
        if p.isReleasing { return p.episodesBehind > 0 ? Copy.Progress.behind(p.episodesBehind) : nil }
        let left = max(0, p.markTarget(now: now) - p.progress)
        return left > 0 ? "\(p.watchContext(episode: p.progress + 1)) next" : nil
    }

    /// The same step with its context dropped — "Episode 5 next" where the row says "Season 7 ·
    /// Episode 5 next". A 136-pt grid cell has room for one fact, and the episode is the one you
    /// act on; the season (and the rewatch ordinal) stay in the list, which has the width for them.
    static func shortStep(_ f: Franchise, now: Int64) -> String? {
        guard let p = f.currentPart, !p.isUpcoming else { return nil }
        if p.isReleasing { return p.episodesBehind > 0 ? Copy.Progress.behind(p.episodesBehind) : nil }
        return p.markTarget(now: now) > p.progress ? Copy.Progress.episodeNext(p.progress + 1) : nil
    }

    /// Where a show stands when there is nothing to do about it. "Caught up" is a claim, so it is
    /// made only about a part that actually exists and has actually been caught.
    static func settled(_ f: Franchise, now: Int64) -> String? {
        if f.effectiveStatus == .completed {
            let watched = RewatchStore.shared.summary(for: f.id).completedCount
            if watched >= 2 { return Copy.Progress.watchedTimes(watched) }
        }
        return nil
    }

    /// "Anime · 2021" / "TV · 2024" — what the thing is and when it started. The original's line,
    /// and the only honest thing to say about a show you have not started.
    static func identity(_ f: Franchise) -> String {
        guard let y = f.year else { return f.kindWord }
        return "\(f.kindWord) \u{00B7} \(y)"
    }
}
