import SwiftUI

// "Library" tab — the user's Library v4 design (Claude Design: templates/library-v4, default
// config artMoment=shelf, progressStyle=ring). Top to bottom:
//  - large "Library" title + search, with a blurred compact header fading in on scroll,
//  - "Coming back" as a horizontal poster shelf (the anticipation section owns the art moment),
//  - Watching + Planned as native-ratio thumbnail rows (never crop a poster); Watching rows carry
//    a tappable progress ring that logs the next episode,
//  - Finished as a quiet 4-up mini poster grid,
//  - tapping any show opens the full franchise detail sheet directly. (A 292pt "quick sheet" used
//    to sit between the row and the detail; it was one hop of chrome with no information the
//    detail doesn't have, so it's gone.)
// The urgency pact still holds: facts, not obligations — the one time-bound accent is the
// airing-today fact ("Tonight, 9:00 PM" before the slot, "New episode out" after it) and the
// Coming back return dates (anticipation relaxes).
struct LibraryView: View {
    @Environment(AppModel.self) private var appModel
    let onOpenDetail: (_ franchiseId: String, _ zoomID: String) -> Void

    private var now: Int64 { appModel.now }
    @State private var scrolled = false

    var body: some View {
        @Bindable var model = appModel

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Library")
                    .scaledFont(30, weight: .bold)
                    .tracking(-0.8)
                    .padding(.horizontal, Theme.Space.gutter)

                SearchField(text: $model.libQuery, prompt: "Search your library")
                    .padding(.horizontal, Theme.Space.gutter)
                    .padding(.top, 12)

                content
            }
            .padding(.top, 8)
            .padding(.bottom, 120)
            .animation(.uiGentle, value: appModel.loading)
            .animation(.uiGentle, value: appModel.loadError)
        }
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .background(AppBackground())
        .scrollDismissesKeyboard(.interactively)
        .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y > 64 } action: { _, isPast in
            withAnimation(.uiGentle) { scrolled = isPast }
        }
        .overlay(alignment: .top) { compactHeader }
        .refreshable {
            await appModel.reload()
            if !appModel.loadError { Haptics.impact(.light) }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
    }

    /// Straight to the full detail — the row already names the show; the tap should answer it.
    private func openDetail(_ f: Franchise) {
        onOpenDetail(f.id, "lib/\(f.id)")
    }

    // Blurred compact bar once the large title scrolls away (Apple large-title pattern).
    @ViewBuilder
    private var compactHeader: some View {
        if scrolled {
            Text("Library")
                .scaledFont(16, weight: .bold)
                .tracking(-0.2)
                .frame(maxWidth: .infinity)
                .padding(.top, 6)
                .padding(.bottom, 12)
                .background(.ultraThinMaterial)
                .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
                .transition(.opacity)
        }
    }

    // MARK: content

    @ViewBuilder
    private var content: some View {
        if appModel.loadError && !appModel.libraryEmpty {
            RetryBanner { Task { await appModel.reload() } }
                .padding(.horizontal, Theme.Space.gutter).padding(.top, 14)
        }

        if appModel.loading && appModel.library.isEmpty {
            Loader()
        } else if appModel.loadError && appModel.libraryEmpty {
            EmptyStateView(
                title: "Couldn't load your library",
                message: "The server couldn't be reached. Check your connection and try again.",
                ctaLabel: "Retry",
                onCta: { Task { await appModel.reload() } }
            )
        } else if appModel.libraryEmpty && !appModel.loading {
            EmptyStateView(
                title: "Your library is empty",
                message: "Add shows from the Add tab and they'll live here — what you're watching, what's coming back, and what you've finished."
            )
        } else if appModel.libraryShelves.isEmpty {
            Text("No matches")
                .scaledFont(11, weight: .semibold)
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(Theme.text36)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 56)
        } else {
            let shelves = Dictionary(uniqueKeysWithValues: appModel.libraryShelves.map { ($0.shelf, $0.franchises) })
            VStack(alignment: .leading, spacing: 0) {
                if let coming = shelves[.comingBack] { comingBackShelf(coming) }
                if let watching = shelves[.watching] {
                    rowSection("Watching", watching) { f in watchingRow(f) }
                }
                if let planned = shelves[.planned] {
                    rowSection("Planned", planned) { f in plannedRow(f) }
                }
                if let finished = shelves[.finished] { finishedGrid(finished) }
            }
            .animation(.uiSmooth, value: appModel.libraryShelves.map { $0.franchises.map(\.id) })
        }
    }

    private func whisperHeader(_ label: String, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .scaledFont(11, weight: .semibold)
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(Theme.text46)
            Text("\(count)")
                .scaledFont(11, monospacedDigit: true)
                .contentTransition(.numericText())
                .foregroundStyle(Theme.text28)
        }
    }

    // MARK: Coming back — the poster shelf (the art moment)

    private func comingBackShelf(_ items: [Franchise]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            whisperHeader("Coming back", count: items.count)
                .padding(.horizontal, Theme.Space.gutter)
                .padding(.top, 22)

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(items) { f in
                        Button { openDetail(f) } label: {
                            VStack(alignment: .leading, spacing: 0) {
                                Thumb(cover: f.cover, width: 112, height: 168, radius: 12)
                                    .shadow(color: .black.opacity(0.45), radius: 12, y: 6)
                                Text(f.title)
                                    .scaledFont(12, weight: .semibold)
                                    .tracking(-0.1)
                                    .lineLimit(1)
                                    .foregroundStyle(Theme.textPrimary)
                                    .padding(.top, 8)
                                let fact = comingBackFact(f)
                                Text(fact.text)
                                    .scaledFont(11, monospacedDigit: true)
                                    .foregroundStyle(fact.dated ? Theme.accent : Theme.text46)
                                    .lineLimit(1)
                                    .padding(.top, 1)
                            }
                            .frame(width: 112, alignment: .leading)
                        }
                        .buttonStyle(SpringPressButtonStyle(scale: 0.96))
                        .contextMenu { FranchiseContextMenu(f: f, appModel: appModel) }
                    }
                }
                .padding(.horizontal, Theme.Space.gutter)
                .padding(.top, 12)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
        }
    }

    // MARK: row sections

    private func rowSection<Row: View>(
        _ label: String, _ items: [Franchise],
        @ViewBuilder row: @escaping (Franchise) -> Row
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            whisperHeader(label, count: items.count)
                .padding(.top, 24).padding(.bottom, 2)
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, f in
                    row(f)
                    if idx < items.count - 1 { HairlineDivider() }
                }
            }
        }
        .padding(.horizontal, Theme.Space.gutter)
    }

    private func watchingRow(_ f: Franchise) -> some View {
        let fact = watchingFact(f)
        return libRow(f, fact: fact.text, accent: fact.accent) {
            if let part = f.releasingPart ?? f.resumePart {
                // The ring only LOGS while there's an unwatched episode actually out. Once you're
                // level with what aired it becomes a plain progress indicator — a live "+1" here
                // has nothing left to count, and tapping on past the end of a season is exactly
                // how a 10-episode season ended up recorded at 59 watched.
                let canLog = part.progress < part.availableEpisodes()
                ProgressRing(fill: WatchProgress(part)?.ringFill ?? .fraction(0), onLog: canLog ? {
                    appModel.setProgress(franchiseId: f.id, mediaId: part.mediaId,
                                         episodes: part.progress + 1)
                } : nil)
            }
        }
    }

    private func plannedRow(_ f: Franchise) -> some View {
        let year = f.year.map { " · \($0)" } ?? ""
        return libRow(f, fact: "\(f.source.shortLabel)\(year)", accent: false) { EmptyView() }
    }

    private func libRow<Trailing: View>(
        _ f: Franchise, fact: String, accent: Bool,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) -> some View {
        Button { openDetail(f) } label: {
            HStack(spacing: 12) {
                Thumb(cover: f.cover, width: 46, height: 69, radius: 7)
                VStack(alignment: .leading, spacing: 2) {
                    Text(f.title)
                        .scaledFont(15, weight: .semibold)
                        .tracking(-0.2)
                        .lineLimit(1)
                        .foregroundStyle(Theme.textPrimary)
                    Text(fact)
                        .scaledFont(12, monospacedDigit: true)
                        .foregroundStyle(accent ? Theme.accent : Theme.text50)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                trailing()
                Image(systemName: "chevron.right")
                    .scaledFont(12, weight: .semibold)
                    .foregroundStyle(Theme.text36)
            }
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(SpringPressButtonStyle(scale: 0.98))
        .contextMenu { FranchiseContextMenu(f: f, appModel: appModel) }
    }

    // MARK: Finished — quiet 4-up poster grid

    private func finishedGrid(_ items: [Franchise]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            whisperHeader("Finished", count: items.count)
                .padding(.top, 26).padding(.bottom, 10)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4),
                      spacing: 10) {
                ForEach(items) { f in
                    Button { openDetail(f) } label: {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Theme.surface)
                            .aspectRatio(2.0 / 3.0, contentMode: .fit)
                            .overlay { RemoteImageView(url: f.cover, maxPixel: 300) }
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Theme.hairline, lineWidth: 1))
                            .opacity(0.82)
                    }
                    .buttonStyle(SpringPressButtonStyle(scale: 0.94))
                    .contextMenu { FranchiseContextMenu(f: f, appModel: appModel) }
                    .accessibilityLabel(f.title)
                }
            }
        }
        .padding(.horizontal, Theme.Space.gutter)
    }

    // MARK: facts

    /// Watching-row fact: accent "Tonight, 9:00 PM · S4 E2" when the next episode is still to land
    /// today, "New episode out · S4 E2" once that slot has passed (day words only for TV); quiet
    /// "S2 · E6 next" otherwise.
    private func watchingFact(_ f: Franchise) -> (text: String, accent: Bool) {
        if let part = f.releasingPart, let next = f.nextAiring(now: now), f.dayDiff(of: next, now: now) == 0 {
            let ep = [seasonToken(part), part.nextEpisodeNumber.map { "E\($0)" }].compactMap { $0 }
                .joined(separator: " ")
            // A same-day slot is KEPT after it passes (see `scheduledAiring`), so "Tonight, 9:00 AM"
            // was still being promised at 8pm for an episode out since morning. Once the instant is
            // behind us the episode is a fact, not a wait — but only for a real instant: a TV date's
            // 17:00 is synthesized, so it has no moment to be past.
            if !f.timeAnchor.isDateOnly, next <= now {
                // Unwatched is judged against the episode that just landed, not `airedEpisodes` —
                // the aired count trails the hourly sync, so it can still read yesterday's number.
                let unwatched = part.nextEpisodeNumber.map { part.progress < $0 } ?? part.isBehind
                if unwatched {
                    return (ep.isEmpty ? "New episode out" : "New episode out · \(ep)", true)
                }
            } else {
                let when = dayPartLabel(f, at: next)
                return (ep.isEmpty ? when : "\(when) · \(ep)", true)
            }
        }
        if let part = f.releasingPart ?? f.resumePart {
            let season = seasonToken(part).map { "\($0) · " } ?? ""
            return ("\(season)E\(part.progress + 1) next", false)
        }
        // An explicit "Watching" status keeps a show on this shelf even with nothing left to
        // resume (`libShelf` honours the user's word). Say what IS true rather than nothing —
        // an announced return if there is one, else the plain shape of the show. No accent:
        // Library stays calm, Today carries urgency.
        let comingBack = comingBackFact(f)
        return (comingBack.text.isEmpty ? quietFact(f) : comingBack.text, false)
    }

    /// "Tonight, 9:00 PM" / "Today, 9:00 AM" for a real broadcast instant; the bare day word for a
    /// date-only (TV) release, which has no clock to name a part of the day with.
    private func dayPartLabel(_ f: Franchise, at ts: Int64) -> String {
        guard !f.timeAnchor.isDateOnly else { return f.whenLabel(ts: ts, now: now) }
        let hour = Formatting.localParts(ts, anchor: f.timeAnchor).hour
        return "\(Formatting.isEvening(hour: hour) ? "Tonight" : "Today"), \(Formatting.fmtTime(ts, anchor: f.timeAnchor))"
    }

    private func comingBackFact(_ f: Franchise) -> (text: String, dated: Bool) {
        if let premiere = appModel.nextPremiere(of: f) {
            let part = f.parts.first { $0.premiereAt == premiere }
            let label = part.map { $0.label.isEmpty ? "New season" : $0.label } ?? "New season"
            let date = part?.premiereDateLabel(source: f.source)
                ?? Formatting.fmtFullDate(premiere, anchor: f.timeAnchor)
            return ("\(label) · \(date)", true)
        }
        if let badge = f.upcoming?.cardBadge, !badge.isEmpty {
            return (badge, f.upcoming?.releaseSortKey != nil)
        }
        return ("", false)
    }
}

// MARK: - Shared row facts

private func seasonToken(_ part: FranchisePart) -> String? {
    part.kind == .season && part.sequence >= 1 ? "S\(part.sequence)" : nil
}

/// The always-true, never-urgent descriptor for a show with nothing scheduled and nothing queued:
/// its season count, else source + year. Used wherever a fact line would otherwise be blank.
private func quietFact(_ f: Franchise) -> String {
    if let counts = f.partCounts, counts.season > 0 {
        return "\(counts.season) \(counts.season == 1 ? "season" : "seasons")"
    }
    let year = f.year.map { " · \($0)" } ?? ""
    return "\(f.source.shortLabel)\(year)"
}

/// What a progress indicator can HONESTLY say about a part you're watching.
///
/// A season whose size the catalogue doesn't publish (ongoing AniList shows carry `episodes: null`)
/// has no completion to express. Measuring progress against the AIRED count instead rendered a
/// caught-up ongoing show as a closed ring and "100% watched" — an in-progress series presented as
/// finished. Caught up is its own state, not 100%.
private enum WatchProgress {
    /// Known season size: a real fraction of the whole.
    case ofSeason(watched: Int, total: Int)
    /// Unknown size, level with everything aired so far.
    case caughtUp(watched: Int)
    /// Unknown size, still behind: progress through what has AIRED, and labelled as such.
    case throughAired(watched: Int, aired: Int)

    init?(_ part: FranchisePart) {
        if part.totalEpisodes > 0 {
            self = .ofSeason(watched: part.progress, total: part.totalEpisodes)
        } else if part.airedEpisodes > 0 {
            self = part.progress >= part.airedEpisodes
                ? .caughtUp(watched: part.progress)
                : .throughAired(watched: part.progress, aired: part.airedEpisodes)
        } else {
            return nil
        }
    }

    /// How the tappable ring fills. `caughtUp` never closes a circle — a closed ring reads as
    /// "series complete", and this one is still running.
    var ringFill: RingFill {
        switch self {
        case .ofSeason(let watched, let total): return .fraction(min(1, Double(watched) / Double(total)))
        case .caughtUp: return .caughtUp
        // Can't reach 1: this case exists only while watched < aired.
        case .throughAired(let watched, let aired): return .fraction(min(1, Double(watched) / Double(aired)))
        }
    }
}

/// How much of the Watching ring is filled — or that there is nothing left to fill toward.
private enum RingFill {
    case fraction(Double)
    case caughtUp
}

// MARK: - Progress ring

/// The v4 Watching-row ring: a conic progress fill you can TAP to log the next episode.
/// 20pt visual, 34pt tap target. Fills with accent; a small pop on change. A show that's level
/// with what aired but whose season size is unknown gets the passive ✓ instead of a closed ring
/// (the ✓ is the app's "Caught up" status mark — DECISION A).
private struct ProgressRing: View {
    let fill: RingFill
    /// nil ⇒ nothing left to log: render the ring as a passive indicator, not a dead button that
    /// still bounces and haptics on every tap.
    let onLog: (() -> Void)?

    var body: some View {
        Button(action: { onLog?() }) {
            ZStack {
                Circle().stroke(Theme.hairlineStrong, lineWidth: 3)
                switch fill {
                case .fraction(let fraction):
                    Circle()
                        .trim(from: 0, to: fraction)
                        .stroke(Theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.uiSnappy, value: fraction)
                case .caughtUp:
                    Image(systemName: "checkmark")
                        .scaledFont(10, weight: .bold)
                        .foregroundStyle(Theme.accent)
                }
            }
            .frame(width: 20, height: 20)
            .frame(width: 34, height: 34)
            .contentShape(Circle())
        }
        .buttonStyle(BounceButtonStyle())
        .disabled(onLog == nil)
        .accessibilityLabel(ringLabel)
    }

    private var ringLabel: String {
        if case .caughtUp = fill { return "Caught up" }
        return onLog == nil ? "Watch progress" : "Log next episode"
    }
}
