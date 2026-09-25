import Foundation

extension Copy {
    /// Home — the departures board (26 Sep): what is out, what is next, what airs this week.
    enum Home {
        static let title = "Home"
        static let upNext = "Up next"
        /// The past week's episodes you have not marked.
        static let recentlyAired = "Recently aired"
        static let thisWeek = "This week"
        /// The card's moment for a single fresh drop; a backlog says its count instead.
        static let newEpisode = "New episode"
        /// The card's moment when nothing is new: the top of the queue.
        static let continueWatching = "Continue watching"

        /// The board is clear: nothing out, nothing queued, nothing this week.
        static let caughtUp = EmptyStateCopy(symbol: "checkmark.circle", title: "You\u{2019}re all caught up",
                                             supporting: "New episodes land here the moment they air.",
                                             primaryLabel: "See the schedule")

        static var samples: [String] {
            [title, upNext, recentlyAired, thisWeek, newEpisode, continueWatching,
             caughtUp.title, caughtUp.supporting ?? "", caughtUp.primaryLabel ?? ""]
        }
    }
}
