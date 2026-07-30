import SwiftUI

// "Library" tab — the user's Library v4 design (Claude Design: templates/library-v4, default
// config artMoment=shelf, progressStyle=ring). Top to bottom:
//  - large "Library" title + search, with a blurred compact header fading in on scroll,
//  - "Coming back" as a horizontal poster shelf (the anticipation section owns the art moment),
//  - Watching + Planned as native-ratio thumbnail rows (never crop a poster); Watching rows carry
//    a tappable progress ring that logs the next episode,
//  - Finished as a quiet 4-up mini poster grid,
//  - tapping any show opens a quick sheet (blurred-art header, one primary action, ⋯ menu).
// The urgency pact still holds: facts, not obligations — the one time-bound accent is an
// airing-today "Tonight" fact and the Coming back return dates (anticipation relaxes).
struct LibraryView: View {
    @Environment(AppModel.self) private var appModel
    let onOpenDetail: (_ franchiseId: String, _ zoomID: String) -> Void

    private var now: Int64 { appModel.now }
    @State private var quickSheet: Franchise?
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
        .sheet(item: $quickSheet) { f in
            LibraryQuickSheet(
                franchise: f,
                onOpenDetail: { id in
                    quickSheet = nil
                    // Let the quick sheet finish dismissing before the full detail rises.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        onOpenDetail(id, "lib/\(id)")
                    }
                }
            )
            .presentationDetents([.height(292)])
            .presentationDragIndicator(.visible)
        }
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
                        Button { quickSheet = f } label: {
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
                ProgressRing(fraction: ringFraction(part)) {
                    // Log the next episode straight from the row — the v4 ring interaction.
                    appModel.setProgress(franchiseId: f.id, mediaId: part.mediaId,
                                         episodes: part.progress + 1)
                }
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
        Button { quickSheet = f } label: {
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
                    Button { quickSheet = f } label: {
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

    /// Watching-row fact: accent "Tonight, 9:00 PM · S4 E2" when the next episode airs today
    /// (day-word only for TV); quiet "S2 · E6 next" otherwise.
    private func watchingFact(_ f: Franchise) -> (text: String, accent: Bool) {
        if let part = f.releasingPart, let next = part.nextAiringAt,
           Formatting.fmtDay(ts: next, now: now) == "Today" {
            let ep = [seasonToken(part), part.nextEpisodeNumber.map { "E\($0)" }].compactMap { $0 }
                .joined(separator: " ")
            let when = f.source == .anilist ? "Tonight, \(Formatting.fmtTime(next))" : "Today"
            return (ep.isEmpty ? when : "\(when) · \(ep)", true)
        }
        if let part = f.releasingPart ?? f.resumePart {
            let season = seasonToken(part).map { "\($0) · " } ?? ""
            return ("\(season)E\(part.progress + 1) next", false)
        }
        return ("", false)
    }

    private func seasonToken(_ part: FranchisePart) -> String? {
        part.kind == .season && part.sequence >= 1 ? "S\(part.sequence)" : nil
    }

    private func ringFraction(_ part: FranchisePart) -> Double {
        let total = part.totalEpisodes > 0 ? part.totalEpisodes : part.airedEpisodes
        guard total > 0 else { return 0 }
        return min(1, Double(part.progress) / Double(total))
    }

    private func comingBackFact(_ f: Franchise) -> (text: String, dated: Bool) {
        if let premiere = appModel.nextPremiere(of: f) {
            let label = f.parts.first { $0.premiereAt == premiere }
                .map { $0.label.isEmpty ? "New season" : $0.label } ?? "New season"
            return ("\(label) · \(Formatting.fmtFullDate(premiere))", true)
        }
        if let badge = f.upcoming?.cardBadge, !badge.isEmpty {
            return (badge, f.upcoming?.releaseSortKey != nil)
        }
        return ("", false)
    }
}

// MARK: - Progress ring

/// The v4 Watching-row ring: a conic progress fill you can TAP to log the next episode.
/// 20pt visual, 34pt tap target. Fills with accent; a small pop on change.
private struct ProgressRing: View {
    let fraction: Double
    let onLog: () -> Void

    var body: some View {
        Button(action: onLog) {
            ZStack {
                Circle().stroke(Theme.hairlineStrong, lineWidth: 3)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.uiSnappy, value: fraction)
            }
            .frame(width: 20, height: 20)
            .frame(width: 34, height: 34)
            .contentShape(Circle())
        }
        .buttonStyle(BounceButtonStyle())
        .accessibilityLabel("Log next episode")
    }
}

// MARK: - Quick sheet

// The v4 quick sheet — a fast half-sheet for a tapped show: ambient blurred-art header with the
// poster, a status eyebrow, the show's one fact, a progress line for watching shows, and a single
// primary action + a ⋯ menu. The full FranchiseDetailView stays one tap deeper.
private struct LibraryQuickSheet: View {
    @Environment(AppModel.self) private var appModel
    let franchise: Franchise
    let onOpenDetail: (String) -> Void

    private var now: Int64 { appModel.now }
    /// The live copy, so optimistic progress/status changes reflect immediately.
    private var f: Franchise { appModel.franchise(id: franchise.id) ?? franchise }
    private var shelf: AppModel.LibShelf? { appModel.libShelf(of: f) }

    var body: some View {
        VStack(spacing: 0) {
            header
            HStack(spacing: 10) {
                Button {
                    Haptics.impact(.soft)
                    primaryAction()
                } label: {
                    Text(primaryLabel)
                        .scaledFont(14.5, weight: .bold)
                        .foregroundStyle(Theme.background)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(SpringPressButtonStyle(scale: 0.97))

                Menu {
                    FranchiseContextMenu(f: f, appModel: appModel)
                } label: {
                    Image(systemName: "ellipsis")
                        .scaledFont(16, weight: .semibold)
                        .foregroundStyle(Theme.text72)
                        .frame(width: 44, height: 44)
                        .background {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Theme.hairlineStrong, lineWidth: 1)
                        }
                }
            }
            .padding(.horizontal, Theme.Space.gutter)
            .padding(.top, 16)
            Spacer(minLength: 0)
        }
        .presentationBackground(Theme.surface)
    }

    // Ambient header: blurred art behind the uncropped poster (the B-treatment, at sheet scale).
    private var header: some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear
                .frame(height: 178)
                .frame(maxWidth: .infinity)
                .overlay {
                    RemoteImageView(url: f.cover, maxPixel: 500)
                        .blur(radius: 26)
                        .saturation(1.05)
                        .opacity(0.55)
                }
                .overlay { Color.black.opacity(0.30) }

            HStack(alignment: .bottom, spacing: 16) {
                Thumb(cover: f.cover, width: 92, height: 138, radius: 10)
                    .shadow(color: .black.opacity(0.5), radius: 14, y: 6)
                VStack(alignment: .leading, spacing: 4) {
                    Text(statusEyebrow)
                        .scaledFont(10, weight: .semibold)
                        .tracking(1.4)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.accent)
                    Text(f.title)
                        .scaledFont(19, weight: .bold)
                        .tracking(-0.4)
                        .lineLimit(2)
                        .foregroundStyle(Theme.textPrimary)
                    if !fact.isEmpty {
                        Text(fact)
                            .scaledFont(12.5, monospacedDigit: true)
                            .foregroundStyle(Theme.text72)
                            .lineLimit(1)
                    }
                    if let progress = progressLine {
                        VStack(alignment: .leading, spacing: 5) {
                            ProgressBar(fraction: progress.fraction, height: 3)
                                .frame(maxWidth: 160)
                            Text(progress.label)
                                .scaledFont(10.5, monospacedDigit: true)
                                .foregroundStyle(Theme.text52)
                        }
                        .padding(.top, 6)
                    }
                }
                .padding(.bottom, 2)
            }
            .padding(.horizontal, Theme.Space.gutter)
            .padding(.bottom, 18)
        }
        .clipped()
    }

    private var statusEyebrow: String {
        switch shelf {
        case .watching: return "Watching"
        case .comingBack: return "Coming back"
        case .planned: return "Planned"
        case .finished, nil: return "Finished"
        }
    }

    private var fact: String {
        switch shelf {
        case .watching:
            if let part = f.releasingPart ?? f.resumePart {
                let season = part.kind == .season ? "S\(part.sequence) · " : ""
                return "\(season)E\(part.progress + 1) next"
            }
            return ""
        case .comingBack:
            return f.upcoming?.cardBadge ?? ""
        case .planned:
            let year = f.year.map { " · \($0)" } ?? ""
            return "\(f.source.shortLabel)\(year)"
        case .finished, nil:
            if let counts = f.partCounts, counts.season > 0 {
                return "\(counts.season) \(counts.season == 1 ? "season" : "seasons")"
            }
            return ""
        }
    }

    private var progressLine: (fraction: Double, label: String)? {
        guard shelf == .watching, let part = f.releasingPart ?? f.resumePart else { return nil }
        let total = part.totalEpisodes > 0 ? part.totalEpisodes : part.airedEpisodes
        guard total > 0 else { return nil }
        let fraction = min(1, Double(part.progress) / Double(total))
        return (fraction, "\(Int((fraction * 100).rounded()))% watched")
    }

    private var primaryLabel: String {
        switch shelf {
        case .watching: return "Continue watching"
        case .planned: return "Start watching"
        case .comingBack, .finished, nil: return "View details"
        }
    }

    private func primaryAction() {
        switch shelf {
        case .planned:
            // "Start watching" genuinely starts it: the show moves to the Watching shelf.
            appModel.setStatus(franchiseId: f.id, status: .watching)
            onOpenDetail(f.id)
        default:
            onOpenDetail(f.id)
        }
    }
}