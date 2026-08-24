import Foundation

// Strings the screens staged locally during the polish rounds, now in the copy table where every
// user-facing string lives. Screens reference these; their local enums are thin forwards.
extension Copy.Action {
    static let details = "Details"
    static let continueLabel = "Continue"
    static let dismissRecap = "Dismiss what you missed"
    static let revealEpisodeTitle = "Reveal episode title"
    static let hideEpisodeTitle = "Hide episode title"
    static let revealEpisodeTitlesAndStills = "Reveal episode titles and stills"
    static let markSeriesWatched = "Mark series as watched"
    static let markRewatchComplete = "Mark this rewatch complete"
    static let stopRewatch = "Stop this rewatch\u{2026}"
    static let signOut = "Sign out"
    static let deleteAccount = "Delete account"
    static let privacyPolicy = "Privacy Policy"
    static let termsOfUse = "Terms of Use"
    static let contactSupport = "Contact support"
    static let syncNow = "Sync"
    static let retryAll = "Retry all"
    static let dismiss = "Dismiss"
}

extension Copy {
    enum Recap {
        static let whileYouWereAway = "While you were away"
        /// "Since your last visit, 23 Jul" — the window always names its anchor.
        static func sinceYourLastVisit(_ phrase: String) -> String {
            let tail = phrase.hasPrefix("Since ") ? String(phrase.dropFirst(6)) : phrase
            return "Since your last visit, \(tail)"
        }
    }

    enum Rewatch {
        /// The scope that covers the whole work (not "All seasons" over a list of OVAs).
        static let everything = "Everything"
    }

    enum Account {
        static let signOutTitle = "Sign out?"
        static let deleteSubtitle = "Erases your library, progress and history"
        static let deleteTitle = "Delete your account?"
        static let deleteConfirm = "Delete account"
        static let deleteFailedTitle = "Couldn\u{2019}t delete your account"
        static let upToDate = "Up to date"
        static let couldNotReachServer = "Couldn\u{2019}t reach the server"
        static let offlineSupporting = "Changes sync when you reconnect"
        static let showingSavedCopy = "Showing the copy saved on this device"
        static let signedInWithClerk = "Signed in with Clerk"
        static func discardChangesTitle(_ n: Int) -> String { "Discard \(Copy.changes(n))?" }
        static let discardChangesMessage = "They never reached the server. Your library here stays as it is."
        static func discardChangesConfirm(_ n: Int) -> String { "Discard \(Copy.changes(n))" }
    }
}

extension Copy.Accessibility {
    static let opensTheShowHint = "Opens the show"
    static let sectionHeader = "Section"
    static func removeFilter(_ text: String) -> String { "\(text). Remove filter" }
}

extension Copy.Progress {
    /// "Season 4 · Episode 5 next" — the postfix "next" form over a full watch context. Library
    /// used to concatenate this by hand; it is the only sibling `episodeNext` is allowed.
    static func next(context: String) -> String { "\(context) next" }
}

extension Copy {
    /// Filter vocabulary shared by Schedule's menu, its chips and Library's Arrange sheet. One
    /// phrasing per filter: the same toggle used to read "Hide watched episodes" in the menu,
    /// "Watched hidden" on the chip and "watched episodes hidden" to VoiceOver.
    enum Filter {
        static let filter = "Filter"
        static let off = "Off"
        static let source = "Source"
        static let all = "All"
        static let anime = "Anime"
        static let tv = "TV"
        static let hideWatched = "Hide watched"
    }

    enum Schedule {
        static let title = "Schedule"
        /// The bar's return control. It lands on today's section, which is in the feed whether or
        /// not anything airs — on a quiet day the section prints `nothingScheduled` instead of
        /// being skipped, so "Today" always means today.
        static let today = "Today"
        static let tomorrow = "Tomorrow"
        static let scrollToToday = "Scroll to today"
        static let scrollToTodayHint = "Scrolls to today\u{2019}s episodes"
        static let ticker = "Days"
        static let selected = "Selected"
        static let noEpisodes = "No episodes"
        /// The collapsed block of aired days above today — "the last seven days" without saying
        /// so twice: its value line counts them.
        static let earlier = "Earlier"
        static let showEarlier = "Show earlier episodes"
        static let hideEarlier = "Hide earlier episodes"
        /// A day in the feed with nothing on it — in practice only today, which is always drawn.
        static let nothingScheduled = "Nothing scheduled"
        static let reminderSet = "reminder set"
        static func everythingThrough(_ date: String) -> String { "That\u{2019}s everything through \(date)" }
        /// "3 to watch" — the unwatched count in the Earlier block's value line.
        static func toWatch(_ n: Int) -> String { "\(n) to watch" }
    }
}
