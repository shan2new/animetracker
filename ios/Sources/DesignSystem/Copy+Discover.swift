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
        /// A chart row's rank numeral.
        static func trendRank(_ rank: Int) -> String { "\(rank)" }
        /// A trending show's next installment: "Season 2 · Jan 2027"; with no window yet,
        /// "Season 2 announced"; a rumour says so ("Season 2 rumoured").
        static func trendNext(installment: String, window: String?, rumoured: Bool) -> String {
            if rumoured { return "\(installment) rumoured" }
            guard let window, !window.isEmpty, window.uppercased() != "TBA" else { return "\(installment) announced" }
            return "\(installment) \u{00B7} \(window)"
        }
        /// A chart row, spoken: "3, Trapped in a Dating Sim, Airs Sunday, Anime · Isekai".
        static func trendA11y(rank: Int, title: String, facts: [String]) -> String {
            ([String(rank), title] + facts.filter { !$0.isEmpty }).joined(separator: ", ")
        }
        /// The scope menu in the bar: its spoken name, and the section heading inside it.
        static let scopeMenu = "Show"

        // MARK: Audit

        /// One sample per constant and per function (spec §1.9), for `Copy.allSampleStrings`.
        static var sampleStrings: [String] {
            [
                title, topPick, recommended, browseByGenre, genreCount(1), genreCount(24),
                genreA11y(name: "Action", count: 1), genreA11y(name: "Action", count: 24),
                genreFailed, owned, tabForYou, tabTrending, tabGenres,
                trendRank(1), trendNext(installment: "Season 2", window: "Jan 2027", rumoured: false),
                trendNext(installment: "Season 2", window: nil, rumoured: false),
                trendNext(installment: "Season 2", window: nil, rumoured: true),
                trendA11y(rank: 3, title: "Frieren", facts: ["Airs Sunday", "Anime \u{00B7} Fantasy"]), scopeMenu,
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
