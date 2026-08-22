import SwiftUI

// The card action a poster/row exposes (legacy `CardAction`).
enum CardAction {
    case mark   // "Mark caught up" check button (only when behind)
    case add    // "Add to library" + button
    case none
}

// View-model for a card, derived from a franchise + its releasing part. Mirrors the legacy
// `cardVM`. Home / Schedule / Library all operate on the releasing part; Discover uses the
// franchise summary directly (no part), so this also has a summary-based initializer.
struct CardModel: Identifiable {
    let id: String          // franchise id
    let mediaId: Int?       // releasing part media id (for progress writes)
    let title: String
    let cover: String?
    let banner: String?
    let source: MediaSource // .anilist (per-episode times) | .tmdb (dates only) — gates time copy
    let partLabel: String   // releasing part label, e.g. "Season 2" — for full-drop / continue copy
    let sequence: Int?      // releasing part sequence (season number for .season) — nil for summaries
    let kind: PartKind?     // releasing part kind — nil for summaries
    let year: Int?          // premiere year (discover "Anime · 2023")
    let nextAiringCount: Int // episodes sharing the next airing date; > 1 ⇒ a full-season drop

    let isBehind: Bool
    let behindCount: Int
    let behindLabel: String
    let caughtUp: Bool
    let showProgress: Bool
    let progressLabel: String
    let progressFraction: Double
    let progress: Int
    let totalEpisodes: Int

    let action: CardAction
    let owned: Bool

    let airedEpisodes: Int
    let airedAgo: String
    let nextEp: Int?
    /// Next-airing instant (day-word derivation for TV) — nil once it's in the past, so every
    /// derived accessor below is stale-data-safe. See `FranchisePart.scheduledAiring(now:)`.
    let nextAiringAt: Int64?
    let now: Int64
    let countdown: String      // anime only — empty for TV (its clock time is synthesized)
    let countdownIsImminent: Bool
    let airTime: String        // anime only — empty for TV
    let dayLabel: String

    /// Compact "new season coming" hint (e.g. "Season 3 · Jul 5, 2026"), empty when there's no
    /// flagged future installment. Lets a card advertise an announced season the airing schedule
    /// can't (AniList only dates episodes once a broadcast slot exists).
    let newSeason: String

    static let imminentWindow = 24 * Formatting.H

    /// From a library/home franchise (operates on its releasing part).
    init(franchise: Franchise, action: CardAction, now: Int64, owned: Bool = true) {
        let part = franchise.releasingPart
        // Every timestamp on this card is read in its source's calendar — a TMDB instant is a
        // date-only fact synthesized at 17:00 UTC, so a local breakdown lands a day late in
        // JST/KST/AEST and keeps yesterday's drop alive as "today".
        let anchor = franchise.source.timeAnchor
        self.id = franchise.id
        self.mediaId = part?.mediaId
        self.title = franchise.title
        self.cover = franchise.cover ?? part?.cover
        self.banner = franchise.banner ?? franchise.cover
        self.source = franchise.source
        self.partLabel = part?.label ?? ""
        self.sequence = part?.sequence
        self.kind = part?.kind
        self.year = franchise.year
        self.nextAiringCount = part?.nextAiringCount ?? 0

        let behind = part?.episodesBehind ?? (franchise.behind ?? 0)
        self.isBehind = behind > 0
        self.behindCount = behind
        // Same number, source-appropriate word: anime is "behind" (unwatched aired episodes of a
        // releasing season); TV frames the identical backlog as "unwatched".
        self.behindLabel = behind > 0 ? (franchise.source == .tmdb ? "\(behind) unwatched" : "\(behind) behind") : ""
        self.caughtUp = (part?.isCaughtUp ?? false)

        let total = part?.totalEpisodes ?? 0
        let progress = part?.progress ?? 0
        self.progress = progress
        self.totalEpisodes = total
        // A caught-up show that's still airing has a partial bar (e.g. 11/12) that contradicts its
        // own "Caught up" badge — you've watched everything aired; the season total just isn't
        // reached yet. Surface the next-airing countdown instead, which is the useful info once
        // caught up and matches caught-up shows whose total episode count is unknown.
        let caughtUpAndAiring = (part?.isCaughtUp ?? false)
            && (part?.scheduledAiring(now: now, anchor: anchor) != nil || part?.nextEpisodeNumber != nil)
        self.showProgress = total > 0 && action != .add && !caughtUpAndAiring
        self.progressLabel = "\(progress) / \(total > 0 ? String(total) : "?")"
        self.progressFraction = total > 0 ? min(1, Double(progress) / Double(total)) : 0

        self.action = action
        self.owned = owned

        self.airedEpisodes = part?.airedEpisodes ?? 0
        if let last = part?.lastAiredAt {
            self.airedAgo = Formatting.fmtAgo(ts: last, now: now, anchor: anchor)
        } else {
            self.airedAgo = ""
        }
        self.now = now
        self.nextAiringAt = part?.scheduledAiring(now: now, anchor: anchor)
        self.nextEp = part?.nextEpisodeNumber
        if let next = self.nextAiringAt {
            self.dayLabel = Formatting.fmtDay(ts: next, now: now, anchor: anchor)
            // Clock time + minute-precise countdown are ANIME-only. TMDB airs on dates, so a clock
            // or "2d 4h" there is fabricated; TV degrades to day words via `dayWordLong` / `dayBadge`.
            if franchise.source == .anilist {
                self.countdown = Formatting.fmtCountdown(target: next, now: now, anchor: anchor)
                self.countdownIsImminent = (next - now) <= CardModel.imminentWindow
                self.airTime = Formatting.fmtTime(next, anchor: anchor)
            } else {
                self.countdown = ""
                self.countdownIsImminent = false
                self.airTime = ""
            }
        } else {
            self.countdown = ""
            self.countdownIsImminent = false
            self.airTime = ""
            self.dayLabel = ""
        }
        self.newSeason = franchise.upcoming?.cardBadge ?? ""
    }

    /// From a discover/search summary (no per-part progress).
    init(summary: FranchiseSummary, owned: Bool, now: Int64) {
        self.id = summary.id
        self.mediaId = nil
        self.title = summary.title
        self.cover = summary.cover
        self.banner = summary.banner ?? summary.cover
        self.source = summary.source
        self.partLabel = ""
        self.sequence = nil
        self.kind = nil
        self.year = summary.year
        self.nextAiringCount = 0
        self.isBehind = false
        self.behindCount = 0
        self.behindLabel = ""
        self.caughtUp = false
        self.showProgress = false
        self.progressLabel = ""
        self.progressFraction = 0
        self.progress = 0
        self.totalEpisodes = 0
        self.action = .add
        self.owned = owned
        self.airedEpisodes = 0
        self.airedAgo = ""
        self.now = now
        let anchor = summary.source.timeAnchor
        // Same stale-airing rule as the franchise initializer: a past instant is not a schedule.
        self.nextAiringAt = summary.nextAiringAt.flatMap {
            Formatting.dayDiff(ts: $0, now: now, anchor: anchor) >= 0 ? $0 : nil
        }
        self.nextEp = nil
        if let next = self.nextAiringAt {
            self.dayLabel = Formatting.fmtDay(ts: next, now: now, anchor: anchor)
            if summary.source == .anilist {
                self.countdown = Formatting.fmtCountdown(target: next, now: now, anchor: anchor)
                self.countdownIsImminent = (next - now) <= CardModel.imminentWindow
                self.airTime = Formatting.fmtTime(next, anchor: anchor)
            } else {
                self.countdown = ""
                self.countdownIsImminent = false
                self.airTime = ""
            }
        } else {
            self.countdown = ""
            self.countdownIsImminent = false
            self.airTime = ""
            self.dayLabel = ""
        }
        self.newSeason = summary.upcoming?.cardBadge ?? ""
    }

    var countdownColor: Color { countdownIsImminent ? Theme.accent : Theme.text70 }

    /// A show is "currently airing" if it has a scheduled next episode. `nextAiringAt` counts on its
    /// own because TV carries a date without an episode number, and its countdown is always empty.
    var isAiring: Bool { nextEp != nil || nextAiringAt != nil || !countdown.isEmpty }

    /// The installment half of the watch context — the SOURCE'S OWN label ("Season 4", "Part 2"),
    /// never a number invented from `sequence` (board 13, P0 #3: the ordering key never displays).
    func seasonToken() -> String {
        guard kind == .season || kind == .movie else { return "" }
        return partLabel.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Watch context for a metadata line: "Season 4 · Episode 2" / "Episode 2" / "Season 4" / "".
    var seasonEpisodeToken: String {
        let season = seasonToken()
        let episode = nextEp.map { Copy.episode($0) } ?? ""
        if season.isEmpty { return episode }
        if episode.isEmpty { return season }
        return "\(season) · \(episode)"
    }

    /// Source-appropriate relative countdown to the NEXT airing, for trailing accents. Anime is
    /// minute-precise ("2d 4h" / "now"); TV degrades to day precision ("3d" / "2wk") because its
    /// clock time is synthesized.
    ///
    /// nil means "add nothing" — nothing is scheduled, or the TV date is TODAY. A same-day TV row
    /// already says TODAY in its base meta, and appending the span there rendered "· TODAY · IN
    /// TODAY". The countdown's job is to quantify a WAIT; on the day itself there isn't one.
    var relClock: String? {
        guard let next = nextAiringAt else { return nil }
        if source == .anilist {
            return Formatting.fmtCountdown(target: next, now: now, anchor: timeAnchor)
        }
        let span = Formatting.fmtRelSpanShort(ts: next, now: now, anchor: timeAnchor)
        return (span.isEmpty || span == "today") ? nil : span
    }

    /// DECISION C — the next UNWATCHED episode to *watch* = `progress + 1`. This is distinct from
    /// `nextEp` (the next episode to AIR). Only surfaced when the user is mid-watch and that
    /// episode actually exists (already aired for a releasing show, or within a finite total).
    /// Returns e.g. "Next: Ep 9", or nil when not applicable.
    var nextWatchLabel: String? {
        let nextToWatch = progress + 1
        if airedEpisodes > 0 {
            guard progress < airedEpisodes else { return nil }
        } else if totalEpisodes > 0 {
            guard progress < totalEpisodes else { return nil }
        } else {
            return nil
        }
        return "\(Copy.episode(nextToWatch)) next"
    }

    /// DECISION B — next-airing hint for cards that are airing but not behind/caught-up. Framed
    /// explicitly as the show's *airing* schedule ("Airs in {countdown}") so it never reads as
    /// the viewer's own watch progress. Empty when there's nothing useful to surface.
    var airingHint: String {
        guard isAiring else { return "" }
        // Anime: "Airs in 2d 4h" (minute-precise). TV: "Airs Thursday" (day word, no clock).
        if source == .tmdb {
            let word = dayWordLong
            return word.isEmpty ? "" : "Airs \(word)"
        }
        if !countdown.isEmpty { return "Airs in \(countdown)" }
        if let next = nextEp { return "\(Copy.episode(next)) airing" }
        return "Airing"
    }

    /// True for a TMDB (general-TV) card — dates only, no per-episode clock time.
    var isTV: Bool { source == .tmdb }

    /// The calendar this card's timestamps are read in — pass it to any `Formatting` helper a view
    /// still needs to call directly with `nextAiringAt` / `now`.
    var timeAnchor: Formatting.TimeAnchor { source.timeAnchor }

    /// Unwatched backlog count. For a releasing part this is `behindCount` (unwatched *aired*
    /// episodes); for a settled/binge backlog (Keep watching) it falls back to aired-or-total
    /// minus progress. Zero when caught up.
    var unwatchedCount: Int {
        if behindCount > 0 { return behindCount }
        let available = airedEpisodes > 0 ? airedEpisodes : totalEpisodes
        return max(0, available - progress)
    }

    /// Source-neutral "N unwatched" headline (Keep watching / TV backlog). Empty when caught up.
    var unwatchedLabel: String {
        let n = unwatchedCount
        return n > 0 ? "\(n) unwatched" : ""
    }

    /// TV-facing next-airing day word — never a clock time: "Today" / "Thursday" / "May 4".
    var dayWordLong: String {
        guard let next = nextAiringAt else { return "" }
        return Formatting.fmtDayLong(ts: next, now: now, anchor: timeAnchor)
    }

    /// The "when does it land" label for this card: anime gets day + clock ("Tomorrow 9:00 PM"),
    /// TV gets the day word alone. Views should use this instead of branching on `source`.
    var whenLabel: String {
        guard let next = nextAiringAt else { return "" }
        return Formatting.fmtWhen(ts: next, now: now, anchor: timeAnchor)
    }

    /// Two-line date badge (top day/date, bottom relative span) for date-only (TV) rows.
    var dayBadge: (top: String, bottom: String)? {
        guard let next = nextAiringAt else { return nil }
        return Formatting.fmtDayBadge(ts: next, now: now, anchor: timeAnchor)
    }
}
