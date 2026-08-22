import Foundation

// Previously Recap — the arrival (spec board 01). Deterministic, built from the library and the
// last acknowledged visit; acknowledged only when the handoff completes or the user acts.
struct RecapBeat: Identifiable, Equatable {
    enum Kind: Equatable {
        case episodesAired(count: Int)
        case returning(at: Int64?)
        case nextUp(episode: Int, season: String)
        case returnDateAnnounced(at: Int64?)
    }
    let franchiseId: String
    let title: String
    let cover: String?
    let source: MediaSource
    let kind: Kind
    let score: Int
    var id: String { franchiseId + "/" + label(now: 0) }

    /// The beat's one line of supporting copy.
    func label(now: Int64) -> String {
        switch kind {
        case .episodesAired(let n): return n == 1 ? "1 episode aired" : "\(n) episodes aired"
        case .returning(let at): return TemporalCopy.returns(at: at, now: now, source: source)
        case .nextUp(let ep, let season): return season.isEmpty ? "Episode \(ep) next" : "\(season) · Episode \(ep) next"
        case .returnDateAnnounced(let at): return TemporalCopy.returns(at: at, now: now, source: source)
        }
    }
}

struct RecapDigest: Equatable {
    let since: Int64
    let beats: [RecapBeat]        // ≤ 3 visible
    let hiddenBeatCount: Int
    let score: Int
    /// Stable identity for acknowledgement: the beats and the window they describe.
    var digestID: String { "\(since)|" + beats.map(\.id).joined(separator: ",") }

    enum Presentation: Equatable { case full, strip, none }

    static let fullAbsence: Int64 = 72 * Formatting.H
    static let stripAbsence: Int64 = 8 * Formatting.H
    static let fullCooldown: Int64 = 7 * Formatting.D
    static let returningGap: Int64 = 30 * Formatting.D
    static let returningWindow: Int64 = 48 * Formatting.H
    static let announcedWindow: Int64 = 30 * Formatting.D

    /// Builds the digest for everything that changed since `since`. Nil when nothing did.
    static func build(library: [Franchise], since: Int64, now: Int64, keepWatching: [Franchise]) -> RecapDigest? {
        guard since > 0, since < now else { return nil }
        var beats: [RecapBeat] = []
        var newEpisodeTitles = 0
        for f in library where f.effectiveStatus == .watching {
            guard let part = f.releasingPart else { continue }
            // New episodes since the last visit that are still unwatched.
            if let last = part.lastAiredAt, last > since, part.episodesBehind > 0 {
                let count = min(part.episodesBehind, max(1, part.airedEpisodes - (part.progress)))
                newEpisodeTitles += 1
                beats.append(RecapBeat(franchiseId: f.id, title: f.title, cover: f.cover, source: f.source,
                                       kind: .episodesAired(count: count), score: count == 1 ? 5 : 3))
                continue
            }
            // A title returning after a long gap, within 48 hours.
            if let next = f.nextAiring(now: now), next - now <= returningWindow,
               let last = part.lastAiredAt, now - last >= returningGap {
                beats.append(RecapBeat(franchiseId: f.id, title: f.title, cover: f.cover, source: f.source,
                                       kind: .returning(at: next), score: 4))
            }
        }
        // Announced return dates within 30 days for shows you're not mid-way through.
        for f in library where f.effectiveStatus == .completed {
            if let premiere = f.parts.compactMap(\.premiereAt).filter({ $0 > now }).min(), premiere - now <= announcedWindow {
                beats.append(RecapBeat(franchiseId: f.id, title: f.title, cover: f.cover, source: f.source,
                                       kind: .returnDateAnnounced(at: premiere), score: 3))
            }
        }
        // Where you stopped — informational, fills the third slot.
        if let resume = keepWatching.first, let part = resume.resumePart, !beats.contains(where: { $0.franchiseId == resume.id }) {
            let season = part.kind == .season ? part.label : ""
            beats.append(RecapBeat(franchiseId: resume.id, title: resume.title, cover: resume.cover, source: resume.source,
                                   kind: .nextUp(episode: part.progress + 1, season: season), score: 0))
        }
        guard !beats.isEmpty else { return nil }
        let ordered = beats.sorted { $0.score > $1.score }
        var score = ordered.reduce(0) { $0 + $1.score }
        if newEpisodeTitles >= 2 { score += 4 }
        return RecapDigest(since: since, beats: Array(ordered.prefix(3)), hiddenBeatCount: max(0, ordered.count - 3), score: score)
    }

    /// Fire rules. `absence` = now − last acknowledged visit.
    func presentation(absence: Int64, lastFullRecapAt: Int64?, acknowledgedID: String?, now: Int64, enteredByDeepLink: Bool) -> Presentation {
        guard !enteredByDeepLink, acknowledgedID != digestID, beats.count >= 2 else { return .none }
        let cooldownOK = lastFullRecapAt.map { now - $0 >= RecapDigest.fullCooldown } ?? true
        if absence >= RecapDigest.fullAbsence, score >= 4, cooldownOK { return .full }
        if absence >= RecapDigest.stripAbsence, score >= 3 { return .strip }
        return .none
    }
}

/// Persisted acknowledgement (spec: synced through the account later; local for the prototype).
enum RecapState {
    private static let ackKey = "recap.acknowledgedDigestID"
    private static let fullKey = "recap.lastFullRecapAt"

    static var acknowledgedID: String? {
        get { UserDefaults.standard.string(forKey: ackKey) }
        set { UserDefaults.standard.set(newValue, forKey: ackKey) }
    }
    static var lastFullRecapAt: Int64? {
        get { let v = UserDefaults.standard.object(forKey: fullKey) as? Int64; return v == 0 ? nil : v }
        set { UserDefaults.standard.set(newValue ?? 0, forKey: fullKey) }
    }
}
