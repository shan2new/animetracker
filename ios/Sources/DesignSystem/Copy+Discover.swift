import Foundation

// Discover's strings (spec §1.9.4): the tab and screen title, the top pick, the genre shelf and
// the genre page. The search field keeps `Copy.Search` (its prompt and VoiceOver); the
// recommendation shelf keeps `Copy.ForYou`.
//
// Voice (Copy.swift, top): sentence case, no exclamation marks, curly apostrophes, counts through
// `Copy.plural`.

extension Copy {
    enum Discover {
        /// The tab's label and the screen's title. `Copy.Search.title` stays for the field itself.
        static let title = "Discover"
        /// The billboard card's badge.
        static let topPick = "Top pick for you"
        /// The recommendation shelf under the top pick — the ForYou shelf's own header, one string.
        static let recommended = Copy.ForYou.shelf
        static let browseByGenre = "Browse by genre"
        /// A genre tile's count: "1 show" · "24 shows".
        static func genreCount(_ n: Int) -> String { Copy.plural(n, "show", "shows") }
        /// A genre tile's spoken label: "Action, 24 shows".
        static func genreA11y(name: String, count n: Int) -> String { "\(name), \(genreCount(n))" }
        /// The genre page with nothing in the selected scope.
        static let genreEmpty: EmptyStateCopy = EmptyStateCopy.genreEmpty
        static let genreFailed = "This genre couldn\u{2019}t load"
        /// A result tile's caption for a show already in the library — Search's words.
        static let owned = Copy.Search.inLibrary

        // MARK: Explore (the X / Instagram pass, 25 Sep)

        /// X's Explore tabs, under the field.
        static let tabForYou = "For you"
        static let tabTrending = "Trending"
        static let tabGenres = "Genres"
        /// X's trend eyebrow: "1 · Anime · Trending".
        static func trendEyebrow(rank: Int, kind: String) -> String { "\(rank) \u{00B7} \(kind) \u{00B7} Trending" }
        /// The scope menu in the bar: its spoken name, and the section heading inside it.
        static let scopeMenu = "Show"

        // MARK: Audit

        /// One sample per constant and per function (spec §1.9), for `Copy.allSampleStrings`.
        static var sampleStrings: [String] {
            [
                title, topPick, recommended, browseByGenre, genreCount(1), genreCount(24),
                genreA11y(name: "Action", count: 1), genreA11y(name: "Action", count: 24),
                genreFailed, owned, tabForYou, tabTrending, tabGenres,
                trendEyebrow(rank: 1, kind: "Anime"), scopeMenu,
            ]
        }
    }
}

extension EmptyStateCopy {
    /// A genre page whose scope filter leaves nothing. The scope, not the catalogue, is why.
    static let genreEmpty = EmptyStateCopy(
        symbol: "square.grid.2x2",
        title: "Nothing here yet",
        supporting: "No shows in this genre match the filter.")
}
