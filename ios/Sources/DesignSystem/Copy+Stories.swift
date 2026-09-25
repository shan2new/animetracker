import Foundation

// The stories tray and viewer's strings (spec §1.9.2): the bubbles, the frame's badge and meta,
// the discussion lock, the rating sticker, the episode discussion and the viewer's VoiceOver
// actions. Marks reuse `Copy.Action.markEpisodeWatched(_:)` and `markThrough(from:to:)`, and their
// confirmation `Copy.Confirm.batchMark*` — a story's mark is the same write as anywhere else.
//
// Voice (Copy.swift, top): sentence case, no exclamation marks, curly apostrophes, "Episode 19"
// never E19, counts through `Copy.plural`.

extension Copy {
    enum Stories {

        // MARK: The tray

        /// A bubble's spoken label: "Re:ZERO, 2 new episodes" · a reel you have watched through:
        /// "Re:ZERO, watched".
        static func bubble(show: String, unwatched: Int) -> String {
            unwatched <= 0
                ? "\(show), watched"
                : "\(show), \(Copy.plural(unwatched, "new episode", "new episodes"))"
        }

        /// The tag on a ring whose show has an episode out you have not watched — Instagram's LIVE
        /// tag, saying what the ring alone did not ("doesn't feel like a new episode is out",
        /// owner, 25 Sep): "NEW", or "2 NEW" when more than one is waiting.
        static func ringTag(_ unwatched: Int) -> String { unwatched > 1 ? "\(unwatched) NEW" : "NEW" }

        // MARK: The frame

        /// `HeroBadge` draws the NEWS family (a text beginning "New ") in red, every other state
        /// amber — so an aired frame's badge starts with "New".
        static let badgeNewEpisode = "New episode"
        static let badgeNewFinale = "New \u{00B7} Finale"
        /// The upcoming frame's badges (amber: a state, not news yet).
        static let badgeNextEpisode = "Next episode"
        static let badgeFinaleNext = "Finale next"
        static let outNow = "Out now"

        /// "Season 4 · Aired 2h ago". `moment` is `TemporalCopy.aired(at:now:source:)` or
        /// `airsSentence`; a single-part show has no season to state.
        static func meta(season: String, moment: String) -> String {
            let compact = Copy.compactPartLabel(season)
            if moment.isEmpty { return compact }
            return compact.isEmpty ? moment : "\(compact) \u{00B7} \(moment)"
        }
        /// The upcoming frame's moment with its wait: "Airs Friday at 7:30 PM · in 2d 4h". `wait`
        /// is `Formatting.fmtCountdown` ("2d 4h", "31m"); a date-only slot has no clock to count
        /// to and states the day alone.
        static func airsCountdown(_ airs: String, wait: String) -> String { "\(airs) \u{00B7} in \(wait)" }
        /// What VoiceOver says for a frame after the show's name (the page's value, §5.5):
        /// "New episode, Episode 5, Season 4 · Aired 2h ago".
        static func pageValue(badge: String?, episode n: Int, meta: String) -> String {
            [badge, Copy.episode(n), meta.isEmpty ? nil : meta].compactMap { $0 }.joined(separator: ", ")
        }

        // MARK: The discussion lock

        /// The line under a mark that unlocks the discussion.
        static let youreIn = "You\u{2019}re in"
        /// The mark's capsule answering in place while the room opens ("✓ Watched") — the check
        /// is drawn beside it.
        static let watched = "Watched"
        /// "Mark it watched to join the discussion" · "… to join 38 comments".
        static func joinDiscussion(_ n: Int) -> String {
            n <= 0
                ? "Mark it watched to join the discussion"
                : "Mark it watched to join \(Copy.plural(n, "comment", "comments"))"
        }
        /// The reply field's placeholder in the viewer.
        static func commentOnEpisode(_ n: Int) -> String { "Comment on \(Copy.episode(n))" }

        // MARK: The frame's controls

        static let likeEpisode = "Like episode"
        static let unlikeEpisode = "Unlike episode"
        /// The share sheet's text: "Frieren · Season 2 · Episode 5".
        static func shareEpisode(show: String, season: String, episode n: Int) -> String {
            "\(show) \u{00B7} \(Copy.watchContext(part: season, episode: n))"
        }
        static let showPage = "Show page"
        /// A passive label: the episode's alert is armed (iD4 — the REAL state, never a promise).
        static let alertOn = "Episode alert on"
        /// The affordance when episode alerts are off. It does not confirm, so no ellipsis.
        static let turnOnAlerts = "Turn on episode alerts"

        // MARK: The rating sticker

        static func howWasEpisode(_ n: Int) -> String { "How was \(Copy.episode(n))?" }
        /// `avg10` is the room's average / 10 with one decimal ("7.6").
        static func ratingAverage(_ avg10: String) -> String { "Average \(avg10)" }
        static func ratingCount(_ n: Int) -> String { Copy.plural(n, "rating", "ratings") }
        /// Beside the average: "you 8".
        static func ratingYours(_ v10: String) -> String { "you \(v10)" }
        /// The slider's accessibility value: "8 out of 10".
        static func ratingValue(_ v10: String) -> String { "\(v10) out of 10" }
        static let notRated = "Not rated"
        /// The sticker's glyph (Instagram's emoji slider): decorative, hidden from VoiceOver.
        static let ratingGlyph = "\u{1F525}"
        /// Under the settled sticker: "Average 7.6 · 42 ratings · you 8"; before the room's
        /// average has come back, "you 8" alone. `average` and `yours` are out of 10.
        static func ratingLine(average: String?, count: Int, yours: String) -> String {
            guard let average, count > 0 else { return ratingYours(yours) }
            return "\(ratingAverage(average)) \u{00B7} \(ratingCount(count)) \u{00B7} \(ratingYours(yours))"
        }

        // MARK: The episode discussion

        static func discussionTitle(_ n: Int) -> String { "\(Copy.episode(n)) discussion" }
        static func spoilers(_ n: Int) -> String { "Spoilers for \(Copy.episode(n)) and earlier." }
        static func lockedUnwatched(_ n: Int) -> String { "Watch \(Copy.episode(n)) to read the discussion." }
        static func lockedUnaired(_ n: Int) -> String { "\(Copy.episode(n)) hasn\u{2019}t aired yet." }
        /// The room waits for the progress write to land before it asks the server (§4.2).
        static let savingProgress = "Saving your progress"

        // MARK: The viewer's accessibility actions

        static let next = "Next"
        static let previous = "Previous"
        static let nextShow = "Next show"
        static let previousShow = "Previous show"
        static let close = "Close"
        static let pause = "Pause"
        static let play = "Play"
        static let holdHint = "Double-tap and hold to pause"

        // MARK: Audit

        /// One sample per constant and per function (spec §1.9), for `Copy.allSampleStrings`.
        static var sampleStrings: [String] {
            [
                bubble(show: "Re:ZERO", unwatched: 1), bubble(show: "Re:ZERO", unwatched: 2),
                bubble(show: "Re:ZERO", unwatched: 0),
                badgeNewEpisode, badgeNewFinale, badgeNextEpisode, badgeFinaleNext, outNow,
                meta(season: "Season 4", moment: "Aired 2h ago"), meta(season: "", moment: "Aired 2h ago"),
                meta(season: "Season 4", moment: ""),
                airsCountdown("Airs Friday at 7:30 PM", wait: "2d 4h"),
                pageValue(badge: "New episode", episode: 5, meta: "Season 4 \u{00B7} Aired 2h ago"),
                pageValue(badge: nil, episode: 5, meta: "Season 4 \u{00B7} Aired 2h ago"),
                youreIn, watched, joinDiscussion(0), joinDiscussion(1), joinDiscussion(38),
                commentOnEpisode(5), likeEpisode, unlikeEpisode,
                shareEpisode(show: "Frieren", season: "Season 2", episode: 5),
                showPage, alertOn, turnOnAlerts,
                howWasEpisode(5), ratingAverage("7.6"), ratingCount(1), ratingCount(42),
                ratingYours("8"), ratingValue("8"), notRated, ratingGlyph,
                ratingLine(average: "7.6", count: 42, yours: "8"), ratingLine(average: nil, count: 0, yours: "8"),
                discussionTitle(5), spoilers(5), lockedUnwatched(5), lockedUnaired(5), savingProgress,
                next, previous, nextShow, previousShow, close, pause, play, holdHint,
            ]
        }
    }
}
