import Foundation

// The Library's strings — the root shelf and All titles. A Library screen renders nothing that is
// not here or in `Copy` proper: the status shelves are `Copy.Status`, the "All titles" heading is
// `Copy.Heading.allTitles`, progress lines are `Copy.Progress`.
extension Copy {
    enum Library {
        static let title = "Library"
        static let overview = "Overview"
        static let continueWatching = "Continue watching"
        static let continueWatchingEyebrow = "CONTINUE WATCHING"

        /// The root's four-section tab strip. Counts are part of the label, as in the selected
        /// reference, so the user can judge each list before switching into it.
        static func statusTab(_ status: WatchStatus, count: Int) -> String {
            "\(Copy.Status(status)) \(count)"
        }
        static let overviewTabHint = "Shows your library overview"
        static func statusTabHint(_ status: WatchStatus) -> String {
            "Shows titles in \(Copy.Status(status))"
        }

        static let noWatchingTab = EmptyStateCopy(
            symbol: "bookmark",
            title: "No titles in Watching",
            supporting: "Move a title to Watching and it will appear here.")
        static let noPlannedTab = EmptyStateCopy(
            symbol: "calendar",
            title: "Nothing planned yet",
            supporting: "Titles you plan to watch will appear here.")
        static let noWatchedTab = EmptyStateCopy(
            symbol: "checkmark",
            title: "No watched titles yet",
            supporting: "Finished titles will appear here.")

        /// The anticipation shelf. Board 05's word, and the word its captions use ("Returns Oct 2026").
        static let returning = "Returning"
        /// A sequel exists and nobody has said when. The absence of a date is the content.
        static let announced = "Announced"
        static let allTitlesHint = "Opens your whole library, with search, sorting and filters"
        static func allTitlesCount(_ count: Int) -> String { "All \(count)" }
        static func allTitlesAccessibility(_ count: Int) -> String {
            "All titles, \(Copy.titles(count))"
        }
        static let searchPrompt = "Search your library"

        static let viewAll = "View all"
        static func viewAllSection(_ section: String) -> String { "View all \(section.lowercased())" }
        static let focusTitleHint = "Shows this title in the centre"

        static func partProgress(_ label: String, watched: Int, total: Int) -> String {
            let progress = Copy.Progress.watchedOf(watched, total)
            return label.isEmpty ? progress : "\(label) \u{00B7} \(progress)"
        }

        static func progressCompact(_ watched: Int, _ total: Int) -> String {
            "\(watched) of \(total)"
        }

        // MARK: Sort & filter

        static let sortBy = "Sort by"
        static let reverseOrder = "Reverse order"
        static let status = "Status"
        /// The Status picker's "no filter" value. A chip never states it: "Any" is not a criterion.
        static let anyStatus = "Any"
        /// Says unwatched *what* — the identical word on Schedule's menu means episodes.
        static let hasUnwatched = "Has unwatched episodes"
        static let view = "View"
        static let viewAs = "View as"
        /// "Recently added, reversed" — the chip names the direction, or it is lying.
        static func reversed(_ label: String) -> String { "\(label), reversed" }

        static let sortTitle = "Title"
        static let sortAdded = "Recently added"
        static let sortRecent = "Recently updated"
        static let sortProgress = "Most left to watch"
        /// The direction, said in the reader's terms rather than as "ascending".
        static let reversedTitle = "Z to A"
        static let reversedAdded = "Oldest first"
        static let reversedRecent = "Least recent first"
        static let reversedProgress = "Least left to watch first"

        static let posters = "Posters"
        static let list = "List"

        // MARK: Sections and the index

        /// The month header for titles with no date behind the active sort.
        static let noDate = "No date"
        static let sectionIndex = "Section index"
        static let sectionIndexHint = "Jumps the list to a section"
        static let sectionsRotor = "Sections"

        /// Search found nothing while filters are ALSO narrowing the list: the card offers to
        /// clear them, the same action `noFilterMatches` carries. Without it a query under a
        /// "Watched" chip dead-ended on a card with no way out but the chip row.
        static func noSearchResults(query: String, filtered: Bool) -> EmptyStateCopy {
            let base = EmptyStateCopy.noSearchResults(query: query)
            guard filtered else { return base }
            return EmptyStateCopy(symbol: base.symbol, title: base.title, supporting: base.supporting,
                                  primaryLabel: Copy.Action.clear)
        }
    }
}
