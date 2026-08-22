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
}
