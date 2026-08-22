import Foundation

// The copy table (spec board 09), as a Swift source of truth.
//
// Every visible state, action, status, toast, notice, progress line and confirmation string in
// the app resolves to a symbol in here. No screen inlines a sentence again: a string that appears
// on screen either comes from `Copy` or is interpolated data (a title, a date, a count).
//
// Voice: sentence case, no exclamation marks, one supporting sentence, curly apostrophes (U+2019),
// "Previously." always with its full stop. Notation is "Season 4 · Episode 19" — never E19, Ep 19
// or S5 E19.
//
// Capitalisation rule (resolves the board 09 / board 03 apparent conflict):
//   • `Episode 19` is capitalised when it is a LABEL or identifier
//     ("Season 4 · Episode 19", "Episode 19 next", "Episode 19 marked as watched");
//   • it is lower-case inside a sentence-case COMMAND ("Mark through episode 1128").
// `episode(_:)` and `episodeInSentence(_:)` are the two forms; nothing else builds the string.
enum Copy {

    // MARK: - Notation

    /// "Episode 19" — the label form.
    static func episode(_ n: Int) -> String { "Episode \(n)" }

    /// "episode 19" — the form used inside a sentence-case command or message.
    static func episodeInSentence(_ n: Int) -> String { "episode \(n)" }

    /// "Season 4 · Episode 19". `label` is the source's own part label, never derived from order.
    static func watchContext(part label: String, episode n: Int) -> String {
        label.isEmpty ? episode(n) : "\(label) · \(episode(n))"
    }

    /// English-only pluraliser. A `.stringsdict` is out of scope for this prototype (confirmed);
    /// every count that reaches the user goes through here so the singular is never "1 episodes".
    static func plural(_ n: Int, _ one: String, _ many: String) -> String {
        "\(n) \(n == 1 ? one : many)"
    }

    static func episodes(_ n: Int) -> String { plural(n, "episode", "episodes") }
    static func changes(_ n: Int) -> String { plural(n, "change", "changes") }
    static func watchSessions(_ n: Int) -> String { plural(n, "watch session", "watch sessions") }
    static func updates(_ n: Int) -> String { plural(n, "update", "updates") }
    static func titles(_ n: Int) -> String { plural(n, "title", "titles") }

    // MARK: - Status

    /// The five user-facing statuses. Internal `.completed` reads "Finished" and `.planned` reads
    /// "Planned" — "Completed" and "Plan to watch" never appear.
    ///
    /// Switched on the raw value rather than the case set so it already covers `paused` and
    /// `dropped`, which the shared `WatchStatus` gains in the shared-model patch.
    static func Status(_ status: WatchStatus) -> String { statusLabel(status.rawValue) }

    static func statusLabel(_ raw: String) -> String {
        switch raw {
        case "watching":  return "Watching"
        case "planned":   return "Planned"
        case "completed": return "Finished"
        case "paused":    return "Paused"
        case "dropped":   return "Dropped"
        default:          return raw.prefix(1).uppercased() + raw.dropFirst()
        }
    }

    /// Display order for a status menu, independent of the enum's case order.
    static let statusesInOrder = ["Watching", "Planned", "Finished", "Paused", "Dropped"]

    // MARK: - Actions

    /// One form per intent (board 09). A command that exists here must not be reworded at a call
    /// site, shortened to fit a control, or given a second form for a narrow layout.
    enum Action {
        static let markAsWatched = "Mark as watched"
        static let markAsUnwatched = "Mark as unwatched"
        static func markThrough(_ n: Int) -> String { "Mark through \(Copy.episodeInSentence(n))" }
        static func markAll(_ n: Int) -> String { "Mark all \(Copy.episodes(n)) as watched" }
        static let markAllEpisodes = "Mark all episodes as watched"
        static func markAllUnwatched(_ n: Int) -> String { "Mark all \(Copy.episodes(n)) as unwatched\u{2026}" }
        static let markCaughtUp = "Mark caught up"

        static let startRewatch = "Start rewatch"
        static let continueRewatch = "Continue rewatch"
        static let restartRewatch = "Restart rewatch\u{2026}"
        static let fromAnEpisode = "From an episode\u{2026}"

        static let add = "Add"
        static let addAShow = "Add a show"
        static let removeFromLibrary = "Remove from Library"
        static let deleteWatchHistory = "Delete watch history\u{2026}"
        static let deleteThisSession = "Delete this session\u{2026}"
        static let editSessions = "Edit sessions"

        static let viewEpisodes = "View episodes"
        static let viewWatchHistory = "View watch history"
        static func viewAllUpdates(_ n: Int) -> String { "View all \(Copy.updates(n))" }
        static let browseYourLibrary = "Browse your library"
        static let seeAll = "See all"

        static let showTitle = "Show title"
        static let hideTitle = "Hide title"

        static let tryAgain = "Try again"
        static let retry = "Retry"
        static let clear = "Clear"
        static let cancel = "Cancel"
        static let done = "Done"
        static let arrange = "Arrange"
        static let reset = "Reset"
        static let discard = "Discard\u{2026}"
        static let undo = "Undo"

        // MARK: The ellipsis rule, as data

        /// Board 09 states the rule as "commands that open a confirmation end in …", but its own
        /// action table omits the ellipsis from the forward batch marks — which do confirm. The
        /// table's concrete strings win, so `opensConfirmation` is recorded **independently** of
        /// the trailing character and the two are never inferred from one another.
        struct Command: Hashable, Sendable {
            let label: String
            let opensConfirmation: Bool
            var endsInEllipsis: Bool { label.hasSuffix("\u{2026}") }
        }

        /// Every command in the table, with a representative argument for the parameterised ones.
        static let commands: [Command] = [
            Command(label: markAsWatched, opensConfirmation: false),
            Command(label: markAsUnwatched, opensConfirmation: false),
            Command(label: markThrough(10), opensConfirmation: true),
            Command(label: markAll(18), opensConfirmation: true),
            Command(label: markAllEpisodes, opensConfirmation: true),
            Command(label: markAllUnwatched(24), opensConfirmation: true),
            Command(label: markCaughtUp, opensConfirmation: false),
            Command(label: startRewatch, opensConfirmation: false),
            Command(label: continueRewatch, opensConfirmation: false),
            Command(label: restartRewatch, opensConfirmation: true),
            Command(label: fromAnEpisode, opensConfirmation: true),
            Command(label: add, opensConfirmation: false),
            Command(label: removeFromLibrary, opensConfirmation: false),
            Command(label: deleteWatchHistory, opensConfirmation: true),
            Command(label: deleteThisSession, opensConfirmation: true),
            Command(label: viewEpisodes, opensConfirmation: false),
            Command(label: viewWatchHistory, opensConfirmation: false),
            Command(label: showTitle, opensConfirmation: false),
            Command(label: hideTitle, opensConfirmation: false),
            Command(label: tryAgain, opensConfirmation: false),
            Command(label: retry, opensConfirmation: false),
            Command(label: clear, opensConfirmation: false),
            Command(label: discard, opensConfirmation: true),
        ]

        /// True when the command with this exact label opens a confirmation. Unknown labels are
        /// answered `false` — an unknown label is a copy defect, not a silent confirmation.
        static func opensConfirmation(_ label: String) -> Bool {
            commands.first { $0.label == label }?.opensConfirmation ?? false
        }

        /// The invariant the rule really carries: an ellipsis promises a confirmation. (The
        /// converse is deliberately not required — see `Command`.) Empty means the table is sound.
        static var ellipsisViolations: [String] {
            commands.filter { $0.endsInEllipsis && !$0.opensConfirmation }.map(\.label)
        }

        /// A confirmation BUTTON never ends in an ellipsis. Empty means the table is sound.
        static var confirmationButtonViolations: [String] {
            Confirm.buttons.filter { $0.hasSuffix("\u{2026}") }
        }
    }

    // MARK: - Toasts

    enum Toast {
        static func marked(episode n: Int) -> String { "\(Copy.episode(n)) marked as watched" }
        static func batchMarked(_ n: Int) -> String { "\(Copy.episodes(n)) marked as watched" }
        /// Remove never touches history, and the toast says so in words.
        static let removed = "Removed from Library. Watch history kept."
        static func added(title: String, status: String) -> String { "Added \(title) to \(status)" }
        /// Shown only where the row leaves the screen as a result of the change (Library).
        static func movedTo(_ status: String) -> String { "Moved to \(status)" }
        static let offlinePending = "Saved on this device. Waiting to sync."
        /// The SyncBanner's line. A failure is never a transient toast.
        static func syncFailed(_ n: Int) -> String { "\(Copy.changes(n)) couldn\u{2019}t sync" }
    }

    // MARK: - Inline notices

    /// Noun-first: the thing that failed, then what happened to it.
    enum Notice {
        static let today = "Airing dates couldn\u{2019}t refresh"
        static let schedule = "The schedule couldn\u{2019}t refresh"
        static let library = "Your library couldn\u{2019}t refresh"
        static let detailEpisodes = "Episodes couldn\u{2019}t refresh"
        static let searchAnime = "Anime results couldn\u{2019}t refresh"
        static let searchTV = "TV results couldn\u{2019}t refresh"

        static let noConnection = "No connection"
        static let serverError = "Server error"
        static let signedOut = "Signed out"
        static let timedOut = "Timed out"
        static let rateLimited = "Rate limited"

        /// The reason a write failed, in the user's words. Never a status code, never a stack of
        /// `localizedDescription` — Sync status shows this beside each failed command.
        static func reason(_ error: Error) -> String {
            if let api = error as? APIError {
                switch api {
                case .unauthorized: return signedOut
                case .http(let code, _): return code == 429 ? rateLimited : serverError
                case .transport(let underlying): return transportReason(underlying)
                default: return serverError
                }
            }
            return transportReason(error)
        }

        private static func transportReason(_ error: Error) -> String {
            let code = (error as NSError).code
            guard (error as NSError).domain == NSURLErrorDomain else { return serverError }
            switch code {
            case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost,
                 NSURLErrorDataNotAllowed, NSURLErrorCannotConnectToHost,
                 NSURLErrorCannotFindHost, NSURLErrorInternationalRoamingOff:
                return noConnection
            case NSURLErrorTimedOut:
                return timedOut
            default:
                return serverError
            }
        }
    }

    // MARK: - Progress text (passive — never an action)

    enum Progress {
        static func watchedOf(_ watched: Int, _ total: Int) -> String { "\(watched) of \(total) watched" }
        static func episodeNext(_ n: Int) -> String { "\(Copy.episode(n)) next" }
        static func episodeAiring(_ n: Int) -> String { "\(Copy.episode(n)) airing" }
        static func behind(_ n: Int) -> String { "\(Copy.episodes(n)) behind" }
        static func left(_ n: Int) -> String { "\(Copy.episodes(n)) left" }
        static let caughtUp = "Caught up"
        static let caughtUpAfterThisEpisode = "Caught up after this episode"
        static let lastEpisodeOfTheSeason = "Last episode of the season"
        static func complete(_ label: String) -> String {
            label.isEmpty ? "Complete" : "\(label) complete"
        }

        /// "Watched once" · "Watched twice" · "Watched 4 times".
        static func watchedTimes(_ n: Int) -> String {
            switch n {
            case ..<1: return "Not watched yet"
            case 1: return "Watched once"
            case 2: return "Watched twice"
            default: return "Watched \(n) times"
            }
        }

        /// "First watch" · "Second watch" · "Third watch" · "7th watch".
        static func ordinalWatch(_ n: Int) -> String {
            let words = ["", "First", "Second", "Third", "Fourth", "Fifth", "Sixth", "Seventh",
                         "Eighth", "Ninth", "Tenth"]
            if n >= 1, n < words.count { return "\(words[n]) watch" }
            return "\(n)\(ordinalSuffix(n)) watch"
        }

        private static func ordinalSuffix(_ n: Int) -> String {
            let tens = n % 100
            if (11...13).contains(tens) { return "th" }
            switch n % 10 {
            case 1: return "st"
            case 2: return "nd"
            case 3: return "rd"
            default: return "th"
            }
        }

        /// The active session's subtitle: "In progress · Episode 7 next".
        static func inProgress(nextEpisode n: Int) -> String {
            "In progress \u{00B7} \(Copy.episodeNext(n))"
        }

        static let datesUnknown = "Dates unknown"

        /// A completed session's subtitle: "Jul 4 – Jul 19 · 26 episodes", year-qualified when the
        /// session did not finish this year. `nil` dates read "Dates unknown" rather than inventing.
        static func sessionSpan(started: Int64?, completed: Int64?, episodes: Int, now: Int64) -> String {
            let count = Copy.episodes(episodes)
            guard let completed else { return "\(datesUnknown) \u{00B7} \(count)" }
            let end = TemporalCopy.dateWord(completed, now: now, anchor: .local)
            guard let started, started < completed else { return "\(end) \u{00B7} \(count)" }
            let sameYear = Formatting.localParts(started).y == Formatting.localParts(completed).y
            let start = sameYear
                ? Formatting.fmtMonthDay(started)
                : TemporalCopy.dateWord(started, now: now, anchor: .local)
            return "\(start) \u{2013} \(end) \u{00B7} \(count)"
        }
    }

    /// "Episode 19 next" at the top level too — the single most reused progress line.
    static func episodeNext(_ n: Int) -> String { Progress.episodeNext(n) }

    // MARK: - Confirmations (every one states its exact blast radius)

    enum Confirm {
        static let cancel = "Cancel"

        // Contiguous / whole-backlog batch mark.
        static func batchMarkTitle(_ n: Int) -> String { "Mark \(Copy.episodes(n)) as watched?" }
        static func batchMarkMessage(from a: Int, to b: Int) -> String {
            "Your progress will move from \(Copy.episodeInSentence(a)) to \(Copy.episodeInSentence(b))."
        }
        static func batchMarkConfirm(_ n: Int) -> String { "Mark \(Copy.episodes(n)) as watched" }

        // Reset a season's progress. Nothing is deleted — only progress moves.
        static func resetSeasonTitle(_ total: Int) -> String { "Mark \(Copy.episodes(total)) as unwatched?" }
        static func resetSeason(label: String, total: Int) -> String {
            "This sets \(label) back to \(Copy.Progress.watchedOf(0, total)). Your watch history is kept."
        }
        static func resetSeasonConfirm(_ total: Int) -> String { "Mark \(Copy.episodes(total)) as unwatched" }

        // Restart the active rewatch.
        static let restartRewatchTitle = "Restart rewatch?"
        static func restartRewatch(count n: Int) -> String {
            "Restarting discards \(Copy.episodes(n)) of progress in this run. Earlier watches are kept."
        }
        static let restartRewatchConfirm = "Restart rewatch"

        // Delete one session.
        static let deleteSessionTitle = "Delete this session?"
        static func deleteSession(count n: Int) -> String {
            "This permanently removes \(Copy.episodes(n)) from your history. Your other sessions are unchanged."
        }
        static let deleteSessionConfirm = "Delete this session"

        // Delete the whole history.
        static let deleteHistoryTitle = "Delete watch history?"
        static func deleteHistory(sessions: Int, episodes: Int) -> String {
            "This permanently removes \(Copy.watchSessions(sessions)) covering \(Copy.episodes(episodes))."
        }
        static let deleteHistoryConfirm = "Delete watch history"

        // Discard a failed change from Sync status.
        static let discardChangeTitle = "Discard this change?"
        static let discardChangeMessage =
            "The change stays on this device but is never sent to the server."
        static let discardChangeConfirm = "Discard change"

        /// Every confirmation BUTTON label. None may end in an ellipsis (board 09).
        static let buttons: [String] = [
            batchMarkConfirm(18), resetSeasonConfirm(24), restartRewatchConfirm,
            deleteSessionConfirm, deleteHistoryConfirm, discardChangeConfirm, cancel,
        ]
    }

    // MARK: - Session / account state

    enum State {
        static let signedOut = "You\u{2019}re signed out. Sign in again to continue."
        static let checkingForChanges = "Checking for changes"
        static let couldNotCheck = "Couldn\u{2019}t check for changes"
        static let everythingSynced = "Everything synced"
        static let neverSynced = "Not synced yet"
    }

    // MARK: - Freshness

    /// "Updated 8m ago" · "Updated 8h ago" · "Updated yesterday" · "Updated Wednesday" ·
    /// "Updated Aug 19" · "Updated Aug 19, 2025". Elapsed time only, so a date-only source can
    /// never produce a clock here.
    static func updated(at ts: Int64, now: Int64) -> String {
        "Updated \(elapsedWord(at: ts, now: now))"
    }

    /// "Synced 2 min ago" — Profile's account line, same ladder, different verb.
    static func synced(at ts: Int64, now: Int64) -> String {
        "Synced \(elapsedWord(at: ts, now: now))"
    }

    /// VoiceOver reads the elapsed time spelled out: "Updated 8 hours ago", never "8h".
    static func updatedSpokenLabel(at ts: Int64, now: Int64) -> String {
        let elapsed = max(0, now - ts)
        let minutes = Int(elapsed / Formatting.minuteMs)
        if minutes < 1 { return "Updated just now" }
        if minutes < 60 { return "Updated \(plural(minutes, "minute", "minutes")) ago" }
        if Formatting.dayDiff(ts: ts, now: now) == 0 {
            return "Updated \(plural(Int(elapsed / Formatting.H), "hour", "hours")) ago"
        }
        return updated(at: ts, now: now)
    }

    /// One elapsed ladder, so board 09's "Updated 8h ago" and board 08's "Synced 2 min ago" are
    /// the same function rendered under two verbs.
    private static func elapsedWord(at ts: Int64, now: Int64) -> String {
        let elapsed = max(0, now - ts)
        let minutes = Int(elapsed / Formatting.minuteMs)
        if minutes < 1 { return "just now" }
        if minutes < 60 { return "\(minutes) min ago" }
        switch Formatting.dayDiff(ts: ts, now: now) {
        case 0: return "\(Int(elapsed / Formatting.H))h ago"
        case -1: return "yesterday"
        // `fmtDayLong` only names weekdays in the FUTURE; the past needs the name directly.
        case -6 ... -2: return Formatting.weekdayNameMonFirst(Formatting.localMondayCol(ts))
        default: return TemporalCopy.dateWord(ts, now: now, anchor: .local)
        }
    }

    // MARK: - Accessibility values

    enum Accessibility {
        static let loading = "Loading"
        static let refreshing = "Refreshing"
        static let complete = "Complete"
        static let active = "Active"
        static let retryHint = "Tries the request again"
        static let changeStatus = "Change status"
        /// The wordmark's full stop is the only live indicator in the app.
        static func wordmarkLive(_ n: Int) -> String {
            n == 1
                ? "One followed episode is airing now"
                : "\(n) followed episodes are airing now"
        }
    }

    // MARK: - Empty states

    /// Board 09's canonical empty copy, plus four states the board's table does not name. Each
    /// added one is recorded with the reason it exists in `EmptyStateCopy`.
    enum Empty {
        static let account = EmptyStateCopy.emptyAccount
        static let noWatching = EmptyStateCopy.noWatching
        static let offlineCached = EmptyStateCopy.offlineCached
        static let offlineNoData = EmptyStateCopy.offlineNoData
        static let serverNoCache = EmptyStateCopy.serverNoCache
        static let nothingScheduled = EmptyStateCopy.nothingScheduled
        static let noFilterMatches = EmptyStateCopy.noFilterMatches
        static let everythingSynced = EmptyStateCopy.everythingSynced
        static func calmToday(title: String?, when: String?) -> EmptyStateCopy {
            EmptyStateCopy.calmToday(title: title, when: when)
        }
        static func caughtUp(title: String?, when: String?) -> EmptyStateCopy {
            EmptyStateCopy.caughtUp(title: title, when: when)
        }
        static func noSearchResults(query: String) -> EmptyStateCopy {
            EmptyStateCopy.noSearchResults(query: query)
        }
    }
}

// MARK: - Audit
//
// The table's own invariants, checkable without a test target (the prototype has none). The
// "Copy rules" preview in `Primitives+States.swift` renders `auditProblems`; it must be empty.

extension Copy {

    /// Every table string, with a representative argument for the parameterised ones.
    static var allSampleStrings: [String] {
        var out = Action.commands.map(\.label)
        out += Confirm.buttons
        out += [
            Toast.marked(episode: 19), Toast.batchMarked(3), Toast.removed,
            Toast.added(title: "One Piece", status: "Watching"), Toast.movedTo("Finished"),
            Toast.offlinePending, Toast.syncFailed(1),
            Notice.today, Notice.schedule, Notice.library, Notice.detailEpisodes,
            Notice.searchAnime, Notice.searchTV,
            Notice.noConnection, Notice.serverError, Notice.signedOut, Notice.timedOut,
            Notice.rateLimited,
            Progress.watchedOf(18, 24), Progress.episodeNext(19), Progress.behind(3),
            Progress.left(1), Progress.caughtUp, Progress.caughtUpAfterThisEpisode,
            Progress.lastEpisodeOfTheSeason, Progress.complete("Season 4"),
            Progress.watchedTimes(2), Progress.ordinalWatch(3),
            Progress.inProgress(nextEpisode: 7), Progress.datesUnknown,
            Confirm.batchMarkTitle(18), Confirm.batchMarkMessage(from: 1122, to: 1140),
            Confirm.resetSeasonTitle(24), Confirm.resetSeason(label: "Season 4", total: 24),
            Confirm.restartRewatchTitle, Confirm.restartRewatch(count: 6),
            Confirm.deleteSessionTitle, Confirm.deleteSession(count: 26),
            Confirm.deleteHistoryTitle, Confirm.deleteHistory(sessions: 2, episodes: 59),
            Confirm.discardChangeTitle, Confirm.discardChangeMessage,
            State.signedOut, State.checkingForChanges, State.couldNotCheck,
            State.everythingSynced, State.neverSynced,
            Accessibility.wordmarkLive(1), Accessibility.wordmarkLive(3),
        ]
        out += statusesInOrder
        for copy in [EmptyStateCopy.emptyAccount, .noWatching, .offlineCached, .offlineNoData,
                     .serverNoCache, .noFilterMatches, .nothingScheduled, .everythingSynced,
                     .calmToday(title: "Frieren", when: "Returns tomorrow"),
                     .caughtUp(title: "Frieren", when: "Returns tomorrow"),
                     .noSearchResults(query: "one pece")] {
            out.append(copy.title)
            if let s = copy.supporting { out.append(s) }
            if let s = copy.primaryLabel { out.append(s) }
            if let s = copy.secondaryLabel { out.append(s) }
        }
        return out
    }

    /// Empty when the table is sound.
    static var auditProblems: [String] {
        var problems: [String] = []
        problems += Action.ellipsisViolations.map {
            "\u{201C}\($0)\u{201D} ends in an ellipsis but opens no confirmation"
        }
        problems += Action.confirmationButtonViolations.map {
            "confirmation button \u{201C}\($0)\u{201D} ends in an ellipsis"
        }
        problems += allSampleStrings.filter(hasBannedNotation).map {
            "\u{201C}\($0)\u{201D} uses banned episode notation"
        }
        problems += allSampleStrings.filter { $0.contains("!") }.map {
            "\u{201C}\($0)\u{201D} uses an exclamation mark"
        }
        problems += allSampleStrings.filter { $0.contains("'") }.map {
            "\u{201C}\($0)\u{201D} uses a straight apostrophe"
        }
        return problems
    }

    /// "E19", "Ep 19", "S5 E19" — never written anywhere in the app.
    private static func hasBannedNotation(_ s: String) -> Bool {
        if s.contains("Ep ") || s.contains("Ep.") { return true }
        let chars = Array(s)
        for i in chars.indices where chars[i] == "E" {
            if i + 1 < chars.count, chars[i + 1].isNumber { return true }
        }
        return false
    }
}

// MARK: - Empty-state copy as data

/// One empty state's copy. It is data, not a view, so the same values drive the card, the
/// VoiceOver label and a unit test. `symbol` is `nil` where the state has no glyph (the calm day
/// is a sentence about the user's shows, not an icon).
struct EmptyStateCopy: Equatable, Sendable {
    let symbol: String?
    let title: String
    let supporting: String?
    let primaryLabel: String?
    let secondaryLabel: String?

    init(symbol: String?, title: String, supporting: String?,
         primaryLabel: String? = nil, secondaryLabel: String? = nil) {
        self.symbol = symbol
        self.title = title
        self.supporting = supporting
        self.primaryLabel = primaryLabel
        self.secondaryLabel = secondaryLabel
    }

    // Board 09's table, verbatim.

    static let emptyAccount = EmptyStateCopy(
        symbol: "plus",
        title: "Your library is empty",
        supporting: "Add your first show and Today builds itself.",
        primaryLabel: Copy.Action.addAShow)

    static let noWatching = EmptyStateCopy(
        symbol: "bookmark",
        title: "Nothing in Watching",
        supporting: "Move a show to Watching to build Today.",
        primaryLabel: Copy.Action.browseYourLibrary)

    static let offlineCached = EmptyStateCopy(
        symbol: "wifi.slash",
        title: "You\u{2019}re offline",
        supporting: "Showing saved data. Changes will sync when you reconnect.")

    static let noSessions = EmptyStateCopy(
        symbol: "clock.arrow.circlepath",
        title: "No watch history yet",
        supporting: "Your first watch is recorded when you finish the show. Rewatches appear here as sessions.")
    static let searchFailed = EmptyStateCopy(
        symbol: "wifi.exclamationmark",
        title: "Search couldn\u{2019}t reach the server",
        supporting: "Check your connection and try again.",
        primaryLabel: "Try again")
    static let offlineNoData = EmptyStateCopy(
        symbol: "wifi.slash",
        title: "Connect to load your library",
        supporting: "Previously has no saved copy on this device yet.",
        primaryLabel: Copy.Action.tryAgain)

    /// Calm day. Variant A names the next known event; variant B admits there is none. Never both.
    static func calmToday(title: String?, when: String?) -> EmptyStateCopy {
        let supporting: String
        if let title, let when { supporting = "\(title) \(when.lowercasedFirst())." }
        else { supporting = "No new dates have been announced." }
        return EmptyStateCopy(symbol: nil,
                              title: "Nothing changed since you were last here",
                              supporting: supporting)
    }

    /// Caught up. Carries the next event when one is known — never a second "caught up" sentence.
    static func caughtUp(title: String?, when: String?) -> EmptyStateCopy {
        let supporting: String?
        if let title, let when { supporting = "\(title) \(when.lowercasedFirst())." } else { supporting = nil }
        return EmptyStateCopy(symbol: "checkmark.circle.fill",
                              title: "You\u{2019}re caught up",
                              supporting: supporting)
    }

    // Four states board 09's table does not name. Recorded here as the source of truth.

    /// The network is fine and we are not. Chosen over `offlineNoData` by `SyncCenter.isOnline`
    /// (NWPathMonitor), never guessed from the error.
    static let serverNoCache = EmptyStateCopy(
        symbol: "exclamationmark.triangle",
        title: "Previously couldn\u{2019}t reach the server",
        supporting: "Your saved library will appear as soon as the connection returns.",
        primaryLabel: Copy.Action.tryAgain)

    /// Search returned nothing. Carried forward from the v5 state tiles, reworded to the v9 voice.
    static func noSearchResults(query: String) -> EmptyStateCopy {
        EmptyStateCopy(symbol: "magnifyingglass",
                       title: "No results for \u{201C}\(query)\u{201D}",
                       supporting: "Check the spelling or try another title.")
    }

    /// A filter, not the account, is why the list is empty — so the action clears the filter.
    static let noFilterMatches = EmptyStateCopy(
        symbol: "slider.horizontal.3",
        title: "No titles match",
        supporting: "Clear the filters to see everything in your library.",
        primaryLabel: Copy.Action.clear)

    /// Schedule with a library that has no dated episodes. Not an error and not empty-account.
    static let nothingScheduled = EmptyStateCopy(
        symbol: "calendar",
        title: "Nothing scheduled",
        supporting: "None of the shows you follow have an upcoming date.")

    /// Sync status's calm frame. It claims only what `SyncCenter.failedChanges` can prove.
    static let everythingSynced = EmptyStateCopy(
        symbol: "checkmark.circle.fill",
        title: Copy.State.everythingSynced,
        supporting: "No changes are waiting to sync.")

    /// "{Title}. {Supporting}" — the card's single VoiceOver label.
    var spokenLabel: String {
        guard let supporting else { return title }
        return "\(title). \(supporting)"
    }
}

private extension String {
    /// "Returns tomorrow" → "returns tomorrow", so a `TemporalCopy` phrase can follow a title
    /// inside one sentence without a second capital.
    func lowercasedFirst() -> String {
        guard let first else { return self }
        return first.lowercased() + dropFirst()
    }
}
