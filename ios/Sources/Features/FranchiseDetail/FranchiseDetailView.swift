import SwiftUI

// Franchise detail sheet (AnimeDetails design). Fetches the full franchise (parts + subscription)
// and shows, top to bottom:
//  - a banner hero with the title overlaid on the bottom scrim,
//  - an "In Library" row + poster + Parts/Format/Aired meta + genres,
//  - a LIVE BROADCAST BAR for the currently-airing season (big countdown, aired progress), which
//    degrades to a quiet "Next up" line when nothing is airing but a future installment is known,
//  - synopsis, a sliding status segmented control,
//  - "Parts & Episodes" grouped into Seasons / Movies / OVAs / Specials / Music — episodic parts
//    use a tappable PIPS grid, movies a binary toggle.
struct FranchiseDetailView: View {
    @Environment(AppModel.self) private var appModel
    let franchiseId: String

    @State private var franchise: Franchise?
    @State private var loading = true
    @State private var loadError = false
    @State private var synopsisExpanded = false
    @State private var confirmRemove = false
    @Namespace private var statusPillNS

    private var now: Int64 { appModel.now }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if let f = franchise ?? appModel.franchise(id: franchiseId) {
                content(f)
            } else if loading {
                Loader()
            } else if loadError {
                VStack(spacing: 14) {
                    Text("Couldn't load this franchise.")
                        .foregroundStyle(Theme.text52)
                    Button("Retry") { Task { await load() } }
                        .buttonStyleProminentGlass()
                }
            }
        }
        // The sheet presents above MainTabView's toast layer, so mount the same host here —
        // adds/undo/errors triggered in-sheet stay visible.
        .overlay(alignment: .bottom) {
            ToastHost()
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
        }
        .task { await load() }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            franchise = try await appModel.api.franchise(id: franchiseId)
            loadError = false
        } catch {
            loadError = true
        }
    }

    /// The live franchise: prefer the in-library copy (so optimistic progress shows), else fetched.
    private func live(_ fallback: Franchise) -> Franchise {
        appModel.franchise(id: franchiseId) ?? franchise ?? fallback
    }

    @ViewBuilder
    private func content(_ initial: Franchise) -> some View {
        let f = live(initial)
        let inLibrary = appModel.isInLibrary(f.id)

        GeometryReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    hero(f)

                    VStack(alignment: .leading, spacing: 0) {
                        libraryRow(f, inLibrary: inLibrary)
                            .padding(.top, 16)
                        posterMeta(f).padding(.top, 18)
                        if !f.genres.isEmpty {
                            FlowChips(items: Array(f.genres.prefix(4)))
                                .padding(.top, 16)
                        }

                        releaseArea(f).padding(.top, 22)

                        synopsisBlock(f).padding(.top, 20)

                        if inLibrary {
                            statusControl(f).padding(.top, 26)
                        } else {
                            Button {
                                appModel.addToLibrary(franchiseId: f.id, title: f.title, isReleasing: f.isReleasing)
                            } label: {
                                HStack(spacing: 9) {
                                    Image(systemName: "plus").scaledFont(16, weight: .bold)
                                    Text("Add to library").scaledFont(15.5, weight: .semibold)
                                }
                                .frame(maxWidth: .infinity).padding(.vertical, 15)
                                .foregroundStyle(Theme.background)
                            }
                            .buttonStyleProminentGlass()
                            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                            .padding(.top, 24)
                        }

                        partsSections(f, inLibrary: inLibrary).padding(.top, 30)

                        if inLibrary {
                            removeButton(f).padding(.top, 28)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
                .frame(width: proxy.size.width, alignment: .topLeading)
            }
            .scrollIndicators(.hidden)
        }
        .ignoresSafeArea(edges: .top)
        .scrollContentBackground(.hidden)
        .overlay(alignment: .center) {
            ZStack {
                if appModel.justCaught.contains(f.id) {
                    CaughtUpOverlay(size: 62)
                        .frame(width: 200, height: 200)
                        .allowsHitTesting(false)
                }
            }
            .animation(.easeOut(duration: 0.22), value: appModel.justCaught.contains(f.id))
        }
    }

    // MARK: hero banner with overlaid title

    private func hero(_ f: Franchise) -> some View {
        ZStack(alignment: .bottomLeading) {
            RemoteImageView(url: f.banner ?? f.cover)
                .frame(maxWidth: .infinity, minHeight: 290, maxHeight: 290)
                .clipped()
                .opacity(0.62)
            // Strong bottom scrim so the title stays legible over any banner art.
            LinearGradient(
                stops: [
                    .init(color: Theme.background, location: 0.0),
                    .init(color: Theme.background.opacity(0.55), location: 0.42),
                    .init(color: Theme.background.opacity(0.0), location: 1.0),
                ],
                startPoint: .bottom, endPoint: .top
            )
            Text(f.title)
                .scaledFont(28, weight: .semibold)
                .tracking(-0.8)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .shadow(color: .black.opacity(0.65), radius: 14, y: 2)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, minHeight: 290, maxHeight: 290)
        .clipped()
    }

    // MARK: in-library row (pill + status word)

    @ViewBuilder
    private func libraryRow(_ f: Franchise, inLibrary: Bool) -> some View {
        HStack(spacing: 12) {
            if inLibrary {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark").scaledFont(9, weight: .bold)
                    Text("In Library").scaledFont(12, weight: .semibold)
                }
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 11).padding(.vertical, 6)
                .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Theme.accentBorder, lineWidth: 1))
                Text(statusLabel(f.effectiveStatus))
                    .scaledFont(14)
                    .foregroundStyle(Theme.text50)
            } else {
                Text("Not in library")
                    .scaledFont(14)
                    .foregroundStyle(Theme.text50)
            }
        }
    }

    // MARK: poster + meta

    private func posterMeta(_ f: Franchise) -> some View {
        let releasing = f.releasingPart
        return HStack(alignment: .top, spacing: 16) {
            Thumb(cover: f.cover, width: 104, height: 152, radius: 13)
                .shadow(color: .black.opacity(0.55), radius: 20, y: 16)
            VStack(alignment: .leading, spacing: 15) {
                if let breakdown = partBreakdown(f.partCounts) {
                    metaRow(label: "Parts", value: breakdown)
                }
                if let releasing, let fmt = releasing.format, !fmt.isEmpty {
                    metaRow(label: "Format", value: fmt)
                }
                if let releasing, releasing.totalEpisodes > 0 || releasing.airedEpisodes > 0 {
                    metaRow(label: "Aired", value: episodesValue(releasing))
                }
            }
            .padding(.top, 3)
            Spacer(minLength: 0)
        }
    }

    /// A compact label / value pair for the metadata stack beside the poster.
    private func metaRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .scaledFont(10, weight: .semibold)
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(Theme.text40)
            Text(value)
                .scaledFont(13, weight: .medium, monospacedDigit: true)
                .foregroundStyle(Theme.text70)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// "4 Seasons · 1 Movie · 2 OVAs" — only non-zero kinds, properly pluralised.
    private func partBreakdown(_ counts: PartCounts?) -> String? {
        guard let c = counts else { return nil }
        func unit(_ n: Int, _ singular: String, _ plural: String) -> String? {
            n > 0 ? "\(n) \(n == 1 ? singular : plural)" : nil
        }
        let pieces = [
            unit(c.season, "Season", "Seasons"),
            unit(c.movie, "Movie", "Movies"),
            unit(c.ova, "OVA", "OVAs"),
            unit(c.ona, "ONA", "ONAs"),
            unit(c.special, "Special", "Specials"),
            unit(c.music, "Music", "Music"),
        ].compactMap { $0 }
        return pieces.isEmpty ? nil : pieces.joined(separator: " · ")
    }

    /// Aired-episode summary for the releasing part. Always reads as "aired" so it is never
    /// confused with the user's watched "X/Y" progress.
    private func episodesValue(_ part: FranchisePart) -> String {
        if part.totalEpisodes > 0 {
            if part.isReleasing && part.airedEpisodes < part.totalEpisodes {
                return "\(part.airedEpisodes) of \(part.totalEpisodes) aired"
            }
            return "\(part.totalEpisodes) total"
        }
        return "\(part.airedEpisodes) aired"
    }

    // MARK: synopsis (expandable)

    /// Synopsis clamped to a few lines with a Read more / Less toggle — AniList descriptions can
    /// run long, and hard truncation hid the text with no way to finish reading it.
    @ViewBuilder
    private func synopsisBlock(_ f: Franchise) -> some View {
        let synopsis = Formatting.stripHtml(f.synopsis)
        VStack(alignment: .leading, spacing: 8) {
            Text(synopsis.isEmpty ? "No synopsis available." : synopsis)
                .scaledFont(14.5)
                .foregroundStyle(Theme.text66)
                .lineSpacing(5)
                .lineLimit(synopsisExpanded ? nil : 6)
            // ~6 rendered lines ≈ 300 chars at this size; below that the clamp never bites.
            if synopsis.count > 300 {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { synopsisExpanded.toggle() }
                } label: {
                    Text(synopsisExpanded ? "Less" : "Read more")
                        .scaledFont(13, weight: .semibold)
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: remove from library

    /// Quiet destructive action at the end of the sheet — confirmation-gated, since removing
    /// drops the subscription (and the meaning of its progress) in one tap.
    private func removeButton(_ f: Franchise) -> some View {
        Button(role: .destructive) {
            confirmRemove = true
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "trash").scaledFont(12, weight: .semibold)
                Text("Remove from library").scaledFont(13.5, weight: .medium)
            }
            .foregroundStyle(Color(hex: 0xE5484D).opacity(0.9))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
        }
        .buttonStyle(.plain)
        .background(Theme.fillFaint, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
            .stroke(Color(hex: 0xE5484D).opacity(0.22), lineWidth: 1))
        .confirmationDialog("Remove \u{201C}\(f.title)\u{201D} from your library?",
                            isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                appModel.removeFromLibrary(franchiseId: f.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your episode progress for this franchise will no longer be tracked.")
        }
    }

    // MARK: release area (live broadcast bar / next-up / hidden)

    @ViewBuilder
    private func releaseArea(_ f: Franchise) -> some View {
        if let part = f.releasingPart, part.isReleasing {
            liveBar(part, upcoming: f.upcoming)
        } else if let up = f.upcoming, up.isFutureInstallment {
            nextUpBar(up)
        }
    }

    /// The currently-airing season: big countdown to the next episode (when AniList has dated it),
    /// aired-progress bar, and the franchise's "what's next" folded into the footer.
    private func liveBar(_ part: FranchisePart, upcoming: FranchiseUpcoming?) -> some View {
        let total = part.totalEpisodes
        let airedFrac = total > 0 ? min(1, Double(part.airedEpisodes) / Double(total)) : 0
        let seasonLabel = part.label.isEmpty ? part.title : part.label
        let upShort = (upcoming?.isFutureInstallment == true) ? (upcoming?.cardBadge ?? "") : ""

        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                airingNowLabel
                Spacer(minLength: 8)
                Text(seasonLabel)
                    .scaledFont(12.5, weight: .medium)
                    .foregroundStyle(Theme.text50)
                    .lineLimit(1)
            }

            if let next = part.nextAiringAt {
                let countdownText = Formatting.fmtCountdown(target: next, now: now)
                HStack(alignment: .firstTextBaseline, spacing: 11) {
                    Text(countdownText)
                        .scaledFont(40, weight: .semibold, monospacedDigit: true)
                        .tracking(-0.6)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .layoutPriority(1)
                        // Digits roll down as the 20s clock ticks instead of snapping.
                        .contentTransition(.numericText(countsDown: true))
                        .animation(.snappy(duration: 0.35), value: countdownText)
                    Text("UNTIL AIR")
                        .scaledFont(11, weight: .semibold)
                        .tracking(0.5)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.text36)
                }
                .padding(.top, 16)

                (Text("Episode \(part.nextEpisodeNumber.map(String.init) ?? "?")")
                    .foregroundStyle(Theme.accent)
                 + Text(" · airs \(Formatting.fmtDay(ts: next, now: now)), \(Formatting.fmtTime(next))")
                    .foregroundStyle(Theme.text62))
                    .scaledFont(13.5, weight: .medium)
                    .padding(.top, 9)
            }

            if total > 0 {
                ProgressBar(fraction: airedFrac, height: 5)
                    .padding(.top, part.nextAiringAt != nil ? 18 : 16)
            }

            HStack {
                Text(total > 0 ? "\(part.airedEpisodes) of \(total) aired" : "\(part.airedEpisodes) aired")
                    .scaledFont(11.5, monospacedDigit: true)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.3), value: part.airedEpisodes)
                    .foregroundStyle(Theme.text50)
                Spacer(minLength: 8)
                if !upShort.isEmpty {
                    Text(upShort)
                        .scaledFont(12, weight: .medium)
                        .foregroundStyle(Theme.text44)
                        .lineLimit(1)
                }
            }
            .padding(.top, 9)
        }
        .releaseBarChrome()
    }

    /// Not airing, but a future installment is known. A sibling of the live bar: same chrome, with
    /// the announced installment standing in for the countdown as the prominent line.
    private func nextUpBar(_ up: FranchiseUpcoming) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 7) {
                    Image(systemName: "calendar")
                        .scaledFont(11, weight: .bold)
                        .foregroundStyle(Theme.accent)
                    Text(up.tag.uppercased())
                        .scaledFont(11, weight: .bold)
                        .tracking(0.6)
                        .foregroundStyle(Theme.accent)
                }
                Spacer(minLength: 8)
                Text("NEXT UP")
                    .scaledFont(10.5, weight: .semibold)
                    .tracking(0.6)
                    .foregroundStyle(Theme.text36)
            }

            // The announced installment is the hero line, echoing the bar's big countdown.
            Text((up.next?.isEmpty == false) ? up.next! : "New installment")
                .scaledFont(24, weight: .semibold, monospacedDigit: true)
                .tracking(-0.4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)

            if !up.displayRelease.isEmpty {
                Text(up.displayRelease)
                    .scaledFont(13.5, weight: .medium, monospacedDigit: true)
                    .foregroundStyle(Theme.accent)
                    .padding(.top, 8)
            }

            if let note = up.note, !note.isEmpty {
                Text(note)
                    .scaledFont(12.5)
                    .foregroundStyle(Theme.text50)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            }
        }
        .releaseBarChrome()
    }

    private var airingNowLabel: some View {
        HStack(spacing: 7) {
            LivePulseDot()
            Text("AIRING NOW")
                .scaledFont(11, weight: .bold)
                .tracking(0.6)
                .foregroundStyle(Theme.accent)
        }
    }

    // MARK: status control — sliding pill via matchedGeometryEffect

    private func statusControl(_ f: Franchise) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("Status")
                .scaledFont(12, weight: .semibold)
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(Theme.text40)
            HStack(spacing: 8) {
                statusButton(f, .watching, "Watching")
                statusButton(f, .completed, "Completed")
                statusButton(f, .planned, "Plan")
            }
        }
    }

    private func statusButton(_ f: Franchise, _ status: WatchStatus, _ label: String) -> some View {
        let on = f.effectiveStatus == status
        return Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
                appModel.setStatus(franchiseId: f.id, status: status)
            }
        } label: {
            Text(label)
                .scaledFont(12.5, weight: .medium)
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .foregroundStyle(on ? Theme.background : Theme.text70)
        }
        .background {
            if on {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.accent)
                    .matchedGeometryEffect(id: "statusPill", in: statusPillNS)
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.fillSoft)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.hairlineStrong, lineWidth: 1))
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: parts sections

    private func partsSections(_ f: Franchise, inLibrary: Bool) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            SectionHeader(label: "Parts & Episodes", trailing: partBreakdown(f.partCounts))
                .padding(.bottom, -10)
            ForEach(f.sections, id: \.kind) { section in
                VStack(alignment: .leading, spacing: 0) {
                    SectionHeader(label: section.kind.sectionTitle, trailing: "\(section.parts.count)")
                    VStack(spacing: 11) {
                        ForEach(section.parts) { part in
                            PartCard(part: part,
                                     inLibrary: inLibrary,
                                     onSetProgress: { eps in
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            appModel.setProgress(franchiseId: f.id, mediaId: part.mediaId, episodes: eps)
                                        }
                                     })
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statusLabel(_ s: WatchStatus) -> String {
        switch s {
        case .watching: return "Watching"
        case .completed: return "Completed"
        case .planned: return "Plan to watch"
        }
    }
}

// A gently pulsing accent dot for the "AIRING NOW" label (mirrors the prototype's livepulse).
private struct LivePulseDot: View {
    @State private var on = false
    var body: some View {
        Circle()
            .fill(Theme.accent)
            .frame(width: 6, height: 6)
            .shadow(color: Theme.accent.opacity(0.9), radius: 4)
            .scaleEffect(on ? 0.82 : 1)
            .opacity(on ? 0.45 : 1)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}

// The watch state of a single part, used to drive its status chip.
private enum PartStatus {
    case watched          // movie watched, or a finite part finished to the end
    case behind(Int)      // releasing & unwatched aired episodes remain
    case caughtUp         // releasing & up to date with what's aired
    case airing           // releasing, nothing watched yet
    case watching         // partially watched, not releasing
    case upcoming         // announced, not yet aired
    case notStarted

    var label: String {
        switch self {
        case .watched: return "Watched"
        case .behind(let n): return "\(n) behind"
        case .caughtUp: return "Caught up"
        case .airing: return "Airing"
        case .watching: return "Watching"
        case .upcoming: return "Announced"
        case .notStarted: return "Not started"
        }
    }

    var systemImage: String {
        switch self {
        case .watched: return "checkmark"
        case .behind: return "exclamationmark"
        case .caughtUp: return "checkmark"
        case .airing: return "dot.radiowaves.left.and.right"
        case .watching: return "play.fill"
        case .upcoming: return "calendar"
        case .notStarted: return "circle"
        }
    }

    /// Behind is the only "filled accent" (highest urgency) status; the rest read as quiet chips.
    var isUrgent: Bool { if case .behind = self { return true }; return false }
}

// A single part card: poster + title + status chip header, then a PIPS grid (episodic parts) or a
// binary "Mark watched" toggle (movies). Behind, releasing parts get an accent-tinted background.
private struct PartCard: View {
    let part: FranchisePart
    let inLibrary: Bool
    let onSetProgress: (Int) -> Void

    /// Highest watchable episode: aired count while releasing, else the season total.
    private var cap: Int {
        if part.isReleasing { return max(part.airedEpisodes, part.progress) }
        if part.totalEpisodes > 0 { return part.totalEpisodes }
        return part.progress
    }
    private var behind: Int { part.episodesBehind }
    private var attention: Bool { part.isReleasing && behind > 0 }
    private var complete: Bool { part.totalEpisodes > 0 && part.progress >= part.totalEpisodes }
    /// Episodes drawn as pips — total for finite parts, else the aired/progress cap.
    private var pipCount: Int { part.totalEpisodes > 0 ? part.totalEpisodes : cap }

    private var status: PartStatus {
        if part.isUpcoming { return .upcoming }
        if part.isMovie { return part.progress > 0 ? .watched : .notStarted }
        if part.isReleasing {
            if part.isBehind { return .behind(part.episodesBehind) }
            return part.progress > 0 ? .caughtUp : .airing
        }
        if part.isFinished { return .watched }
        return part.progress > 0 ? .watching : .notStarted
    }

    /// One-tap shortcut: catch up to the latest aired episode while releasing, else finish the season.
    private var quickAction: (label: String, target: Int)? {
        if part.isReleasing && behind > 0 { return ("Catch up to \(part.airedEpisodes)", part.airedEpisodes) }
        if !part.isReleasing && !complete && part.totalEpisodes > 0 { return ("Mark all", part.totalEpisodes) }
        return nil
    }

    private var countLabel: String {
        part.totalEpisodes > 0 ? "\(part.progress) / \(part.totalEpisodes)" : "\(part.progress)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if inLibrary && !part.isUpcoming {
                if part.isMovie {
                    movieToggle.padding(.horizontal, 13).padding(.bottom, 13)
                } else if pipCount > 0 {
                    pipsSection.padding(.horizontal, 13).padding(.bottom, 14)
                }
            } else if !inLibrary && !part.isUpcoming && !part.isMovie && pipCount > 0 {
                // Out-of-library: pips are display-only (no quick-action, not tappable).
                pipsGrid.padding(.horizontal, 13).padding(.bottom, 14)
            }
        }
        .background(
            (attention ? Theme.accent.opacity(0.06) : Theme.fillSoft),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(attention ? Color.white.opacity(0.07) : Theme.hairline, lineWidth: 1))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(spacing: 13) {
            Thumb(cover: part.cover, width: 44, height: 62, radius: 9)
            VStack(alignment: .leading, spacing: 4) {
                Text(part.label.isEmpty ? part.title : part.label)
                    .scaledFont(14.5, weight: .semibold)
                    .lineLimit(1)
                    .foregroundStyle(Theme.textPrimary)
                HStack(spacing: 8) {
                    if let fmt = part.format, !fmt.isEmpty {
                        Text(fmt).scaledFont(11.5).foregroundStyle(Theme.text40)
                    }
                    if part.isReleasing {
                        Text("\(part.airedEpisodes) aired")
                            .scaledFont(11.5, weight: .medium).foregroundStyle(Theme.accent)
                    }
                }
                if part.isUpcoming {
                    Text(part.premiereAt.map { "Premieres \(Formatting.fmtFullDate($0))" } ?? "Release date TBA")
                        .scaledFont(12, weight: .medium)
                        .foregroundStyle(Theme.accent)
                }
            }
            Spacer(minLength: 8)
            StatusChip(status: status)
        }
        .padding(13)
    }

    // Binary watched / not-watched control for movies.
    private var movieToggle: some View {
        let watched = part.progress > 0
        return Button {
            onSetProgress(watched ? 0 : 1)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: watched ? "checkmark" : "play.fill")
                    .scaledFont(13, weight: .bold)
                    // Morph play → checkmark instead of swapping instantly.
                    .contentTransition(.symbolEffect(.replace))
                Text(watched ? "Watched" : "Mark watched")
                    .scaledFont(14, weight: .semibold)
            }
            .frame(maxWidth: .infinity).frame(height: 44)
            .foregroundStyle(watched ? Theme.background : Theme.text90)
        }
        .background(
            (watched ? Theme.accent : Theme.fillSoft),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(watched ? .clear : Theme.hairlineStrong, lineWidth: 1))
        .buttonStyle(BounceButtonStyle())
    }

    // Episode pips with the "Episodes / quick-action / count" header above.
    private var pipsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Episodes")
                    .scaledFont(10, weight: .semibold)
                    .tracking(0.7)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.text36)
                Spacer(minLength: 8)
                if let qa = quickAction {
                    Button { onSetProgress(qa.target) } label: {
                        Text(qa.label).scaledFont(11.5, weight: .semibold).foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                }
                Text(countLabel)
                    .scaledFont(11.5, monospacedDigit: true)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.3), value: part.progress)
                    .foregroundStyle(Theme.text50)
            }
            pipsGrid
        }
    }

    private var pipsGrid: some View {
        // 12 equal columns per row, laid out as chunked HStacks. Each pip fills its share via
        // maxWidth:.infinity, so the grid is exactly the card width and never overflows (a LazyVGrid
        // of all-.flexible columns inside a ScrollView can mis-size and push the layout wider).
        let count = max(1, pipCount)
        let perRow = 12
        let rows = stride(from: 1, through: count, by: perRow).map { start in
            Array(start...min(start + perRow - 1, count))
        }
        return VStack(spacing: 5) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 5) {
                    ForEach(row, id: \.self) { i in
                        Pip(index: i, part: part, attention: attention, interactive: inLibrary) {
                            pipTap(i)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    // Pad the final row so its pips keep the same width as full rows.
                    if row.count < perRow {
                        ForEach(0..<(perRow - row.count), id: \.self) { _ in
                            Color.clear.frame(maxWidth: .infinity, minHeight: 18, maxHeight: 18)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func pipTap(_ i: Int) {
        guard inLibrary else { return }
        if part.isReleasing && i > part.airedEpisodes { return }   // can't watch unaired
        onSetProgress(i == part.progress ? i - 1 : i)
    }
}

// A single episode pip. Filled when watched, glowing+pulsing for the next episode, dashed when
// unaired (releasing past the aired count).
private struct Pip: View {
    let index: Int
    let part: FranchisePart
    let attention: Bool
    let interactive: Bool
    let onTap: () -> Void

    @State private var pulse = false

    private var watched: Bool { index <= part.progress }
    private var unaired: Bool { part.isReleasing && index > part.airedEpisodes }
    private var isNext: Bool {
        index == part.progress + 1 && (!part.isReleasing || index <= part.airedEpisodes)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        Button(action: onTap) {
            shape
                .fill(fill)
                .overlay {
                    if unaired {
                        shape.strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                            .foregroundStyle(Color.white.opacity(0.12))
                    } else if isNext {
                        shape.strokeBorder(Theme.accent, lineWidth: 1.6)
                            .shadow(color: Theme.accent.opacity(0.5), radius: 5)
                    }
                }
                .frame(height: 18)
                .scaleEffect(isNext && pulse ? 1.16 : 1)
                .animation(isNext ? .easeInOut(duration: 0.85).repeatForever(autoreverses: true) : .default, value: pulse)
        }
        .buttonStyle(.plain)
        .disabled(!interactive || unaired)
        .onAppear { pulse = isNext }
        .onChange(of: isNext) { _, nowNext in pulse = nowNext }
        .accessibilityLabel("Episode \(index)")
        .accessibilityValue(watched ? "watched" : (unaired ? "not aired" : "not watched"))
    }

    private var fill: Color {
        if watched { return attention ? Theme.accent : Color(hex: 0xF5F5F7).opacity(0.34) }
        if unaired || isNext { return .clear }
        return Color.white.opacity(0.10)
    }
}

// A compact per-part status chip. "Behind" is the only filled-accent (urgent) variant; everything
// else is a quiet outlined chip so the row reads calm until something needs attention.
private struct StatusChip: View {
    let status: PartStatus

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: status.systemImage).scaledFont(9, weight: .bold)
            Text(status.label).scaledFont(11, weight: .semibold)
        }
        .foregroundStyle(status.isUrgent ? Theme.background : Theme.text62)
        .padding(.leading, 7).padding(.trailing, 8).padding(.vertical, 4)
        .background(
            status.isUrgent ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.fillSoft),
            in: shape
        )
        .overlay(shape.stroke(status.isUrgent ? .clear : Theme.hairlineStrong, lineWidth: 1))
        .fixedSize()
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 8, style: .continuous) }
}

private extension View {
    /// Shared container for the release bars (live broadcast + next-up): full-width soft card with
    /// a corner accent glow and a hairline border, so the airing and announced states read as one
    /// component in two states.
    func releaseBarChrome() -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.fillSoft)
                    // Soft accent glow bleeding from the top-right corner.
                    RadialGradient(colors: [Theme.accent.opacity(0.16), .clear],
                                   center: .topTrailing, startRadius: 0, endRadius: 180)
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.hairlineStrong, lineWidth: 1))
    }
}

// Simple wrapping chip row for genres.
struct FlowChips: View {
    let items: [String]
    var body: some View {
        FlexibleWrap(spacing: 7, lineSpacing: 7) {
            ForEach(items, id: \.self) { g in
                Text(g)
                    .scaledFont(12)
                    .foregroundStyle(Theme.text62)
                    .padding(.horizontal, 11).padding(.vertical, 5)
                    .background(Theme.fillSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Theme.hairline, lineWidth: 1))
            }
        }
    }
}
