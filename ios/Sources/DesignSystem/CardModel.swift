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

    let isBehind: Bool
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
    let countdown: String
    let countdownIsImminent: Bool
    let airTime: String
    let dayLabel: String

    /// Compact "new season coming" hint (e.g. "Season 3 · Jul 5, 2026"), empty when there's no
    /// flagged future installment. Lets a card advertise an announced season the airing schedule
    /// can't (AniList only dates episodes once a broadcast slot exists).
    let newSeason: String

    static let imminentWindow = 24 * Formatting.H

    /// From a library/home franchise (operates on its releasing part).
    init(franchise: Franchise, action: CardAction, now: Int64, owned: Bool = true) {
        let part = franchise.releasingPart
        self.id = franchise.id
        self.mediaId = part?.mediaId
        self.title = franchise.title
        self.cover = franchise.cover ?? part?.cover
        self.banner = franchise.banner ?? franchise.cover

        let behind = part?.episodesBehind ?? (franchise.behind ?? 0)
        self.isBehind = behind > 0
        self.behindLabel = behind > 0 ? "\(behind) behind" : ""
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
            && (part?.nextAiringAt != nil || part?.nextEpisodeNumber != nil)
        self.showProgress = total > 0 && action != .add && !caughtUpAndAiring
        self.progressLabel = "\(progress) / \(total > 0 ? String(total) : "?")"
        self.progressFraction = total > 0 ? min(1, Double(progress) / Double(total)) : 0

        self.action = action
        self.owned = owned

        self.airedEpisodes = part?.airedEpisodes ?? 0
        if let last = part?.lastAiredAt {
            self.airedAgo = Formatting.fmtAgo(ts: last, now: now)
        } else {
            self.airedAgo = ""
        }
        self.nextEp = part?.nextEpisodeNumber
        if let next = part?.nextAiringAt {
            self.countdown = Formatting.fmtCountdown(target: next, now: now)
            self.countdownIsImminent = (next - now) <= CardModel.imminentWindow
            self.airTime = Formatting.fmtTime(next)
            self.dayLabel = Formatting.fmtDay(ts: next, now: now)
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
        self.isBehind = false
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
        self.nextEp = nil
        if let next = summary.nextAiringAt {
            self.countdown = Formatting.fmtCountdown(target: next, now: now)
            self.countdownIsImminent = (next - now) <= CardModel.imminentWindow
            self.airTime = Formatting.fmtTime(next)
            self.dayLabel = Formatting.fmtDay(ts: next, now: now)
        } else {
            self.countdown = ""
            self.countdownIsImminent = false
            self.airTime = ""
            self.dayLabel = ""
        }
        self.newSeason = summary.upcoming?.cardBadge ?? ""
    }

    var countdownColor: Color { countdownIsImminent ? Theme.accent : Theme.text70 }

    /// A show is "currently airing" if it has a scheduled next episode.
    var isAiring: Bool { nextEp != nil || !countdown.isEmpty }

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
        return "Next: Ep \(nextToWatch)"
    }

    /// DECISION B — next-airing hint for cards that are airing but not behind/caught-up. Framed
    /// explicitly as the show's *airing* schedule ("Airs in {countdown}") so it never reads as
    /// the viewer's own watch progress. Empty when there's nothing useful to surface.
    var airingHint: String {
        guard isAiring else { return "" }
        if !countdown.isEmpty { return "Airs in \(countdown)" }
        if let next = nextEp { return "Ep \(next) airing" }
        return "Airing"
    }
}
