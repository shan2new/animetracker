import Foundation

// SP-7 — the derivations more than one screen needs. This file is the ONLY place they exist.
//
// Two halves, kept as separate extension blocks so the merge that produced them stayed textual:
//   • p0-engineering: canonical labels, watch context, the undo snapshot, `WatchStatus.displayName`;
//   • detail: the aired/renderable/mark-target ladder ported out of `SeasonAccordion`, plus the
//     franchise-level "which part am I on" and "is the whole thing finished" questions.
//
// House rule for everything here: **`sequence` is the ordering key and never displays.** It counts
// a franchise's members, which is not the number the world uses for a season — rendering "S5"
// beside a label that reads "Season 4" is spec board 13's P0 #3, observed live on 2026-08-22.

// MARK: - FranchisePart · canonical labels (spec board 13, P0 #3)

extension FranchisePart {
    /// The source's OWN label for this installment — "Season 4", "Final Season", "Part 2".
    ///
    /// **Never derived from `sequence`.** Empty string when the source gave no label — unknown
    /// says unknown; a fabricated "Season 1" is worse than nothing.
    var canonicalLabel: String {
        label.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// "Episode 19". Never "E19", never "Ep 19" (board 09 notation table).
    func episodeLabel(_ n: Int) -> String { Copy.episode(n) }

    /// The full watch context for a metadata line:
    /// "Season 4 · Episode 19" · "Episode 19" (no label) · "Kizumonogatari" (a movie has no
    /// episode to name).
    func watchContext(episode: Int) -> String {
        let label = canonicalLabel
        if kind == .movie { return label }
        if label.isEmpty { return episodeLabel(episode) }
        return "\(label) · \(episodeLabel(episode))"
    }
}

// MARK: - FranchisePart · the aired / renderable / mark-target ladder
//
// Ported out of `SeasonAccordion`, which is being retired. Three different questions that were
// repeatedly confused for one another:
//   provenAiredCount      — how many episodes we can PROVE have aired;
//   renderableEpisodeCount — how many rows to draw (plumbing; NEVER shown as a season length);
//   markTarget            — what "mark this season watched" writes.

extension FranchisePart {
    /// How many episodes of this part have provably aired.
    ///
    /// `airedEpisodes` is the server's derivation from catalogue airing data, but a part caught
    /// mid-sync can report 0 while its own episode list already carries dates in the past. Trusting
    /// that blindly dims every row and collapses `markTarget` onto the user's progress, so a season
    /// header renders "watched" purely because there is nothing left to compare against. An episode
    /// whose air date has passed HAS aired, so take the higher count.
    ///
    /// Strictly BEFORE today, not "today or earlier": today's slot is the one the catalogue is
    /// still counting down to, and swallowing it here would cost the next-to-air row its date badge
    /// on every healthy season the moment its drop day arrives.
    func provenAiredCount(now: Int64) -> Int {
        guard isReleasing else { return airedEpisodes }
        let dated = episodes.reduce(0) { acc, ep in
            guard let d = ep.airDate,
                  Formatting.dayDiff(ts: d, now: now, anchor: Episode.airDateAnchor) < 0 else { return acc }
            return max(acc, ep.number)
        }
        return max(airedEpisodes, dated)
    }

    /// How many episode rows to render.
    ///
    /// With a known total, never exceed it. With an unknown total (0 — common for ongoing AniList
    /// shows) extend one past what has aired so the next-to-air row can carry its date badge. Row
    /// plumbing ONLY: it is a guess, and a guess must never be shown as a season length.
    func renderableEpisodeCount(now: Int64) -> Int {
        if totalEpisodes > 0 { return totalEpisodes }
        let aired = provenAiredCount(now: now)
        let nextToAir = (isReleasing && nextAiringAt != nil) ? aired + 1 : 0
        return max(aired, progress, nextToAir)
    }

    /// What "mark this season as watched" writes: catch up to what has aired for a releasing
    /// season, else the full episode count. Bounded again by `progressCeiling` at the write.
    func markTarget(now: Int64) -> Int {
        isReleasing ? provenAiredCount(now: now) : renderableEpisodeCount(now: now)
    }

    /// Every available episode of this part is watched. Uses `.nowMs` because "complete" is a
    /// property of the part at the moment it is asked, and callers that need a pinned clock use
    /// `markTarget(now:)` directly.
    var isComplete: Bool {
        let target = markTarget(now: .nowMs)
        return target > 0 && progress >= target
    }

    /// "Jun 24, 2026" for an announced part — the date the UI can actually promise.
    ///
    /// `premiereDateLabel` reads the catalogue's own premiere slot, which TMDB frequently leaves
    /// null while still dating the season through its first episode. Falling back to the earliest
    /// episode air date is the difference between a real date and a bare "TBA".
    func announcedDateLabel(source: MediaSource) -> String? {
        if let label = premiereDateLabel(source: source) { return label }
        guard let first = episodes.compactMap({ $0.airDate }).min() else { return nil }
        return Formatting.fmtFullDate(first, anchor: Episode.airDateAnchor)
    }
}

// MARK: - Franchise · label lookup, current part, completion, the undo snapshot

extension Franchise {
    /// Episodic members in watch order. A movie is a binary unit and is handled separately;
    /// specials and music videos are not part of the spine.
    var episodicPartsInOrder: [FranchisePart] {
        parts
            .filter { $0.kind == .season || $0.kind == .ona || $0.kind == .ova }
            .sorted { $0.sequence < $1.sequence }
    }

    /// The part the whole screen is "about": what is airing, else what the user would resume,
    /// else the earliest thing they have not finished. `nil` only when there is nothing episodic.
    var currentPart: FranchisePart? {
        if let releasing = releasingPart { return releasing }
        if let resume = resumePart { return resume }
        return episodicPartsInOrder.first { !$0.isComplete }
    }

    /// The whole work is finished: every episodic member complete, nothing releasing, and no
    /// future installment announced. This is the question `Copy.Progress.complete(_:)` and the
    /// series-complete milestone both ask — it lives here so no screen re-derives it.
    var isSeriesComplete: Bool {
        let episodic = episodicPartsInOrder
        guard !episodic.isEmpty else { return false }
        guard episodic.allSatisfy({ $0.isComplete }) else { return false }
        guard !parts.contains(where: { $0.isReleasing || $0.isUpcoming }) else { return false }
        return upcoming?.isFutureInstallment != true
    }

    /// The canonical label of one member, by media id. "" when the part is unknown or unlabelled.
    func canonicalPartLabel(for mediaId: Int) -> String {
        parts.first { $0.mediaId == mediaId }?.canonicalLabel ?? ""
    }

    /// "Anime" | "TV" — the word for what this is, in the user's vocabulary. Board 09 never says
    /// "AniList" or "TMDB" to a viewer.
    var kindWord: String { source == .tmdb ? "TV" : "Anime" }

    /// The value `UndoState.removedFranchise` carries. `Franchise` is a value type, so this is the
    /// whole show — parts, progress and status — frozen at the instant of the removal. That is what
    /// lets Undo restore instantly, before any network round-trip.
    var snapshotForUndo: Franchise { self }
}

// MARK: - WatchStatus · the one place a status becomes words

extension WatchStatus {
    /// Board 09's status vocabulary, for all five cases. `.completed` is an internal name; the
    /// user's word is "Watched" (SYS-4 — "Finished" is out of the vocabulary; it was carrying both
    /// the user's list state and the series' production state).
    var displayName: String { Copy.Status(self) }
}
