import SwiftUI

// Franchise detail sheet. Fetches the full franchise (parts + subscription) and shows:
//  - banner hero with concentric-corner close button,
//  - the releasing part's "next episode" callout + a glass "Mark caught up",
//  - parts grouped into Seasons / Movies / OVAs / Specials, each with its own progress stepper,
//  - a subscribe control (or status segmented control when subscribed).
struct FranchiseDetailView: View {
    @Environment(AppModel.self) private var appModel
    let franchiseId: String

    @State private var franchise: Franchise?
    @State private var loading = true
    @State private var loadError = false
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
        let releasing = f.releasingPart

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero(f)

                VStack(alignment: .leading, spacing: 0) {
                    headerBlock(f, inLibrary: inLibrary)

                    if let part = releasing, part.isReleasing, let next = part.nextAiringAt {
                        airingCallout(part: part, next: next).padding(.top, 20)
                    }

                    Text(Formatting.stripHtml(f.synopsis).isEmpty ? "No synopsis available." : Formatting.stripHtml(f.synopsis))
                        .scaledFont(14.5)
                        .foregroundStyle(Theme.text66)
                        .lineSpacing(5)
                        .padding(.top, 20)

                    if let up = f.upcoming {
                        upcomingCallout(up).padding(.top, 18)
                    }

                    if inLibrary {
                        if let part = releasing, part.isBehind {
                            watchActions(f, part: part).padding(.top, 18)
                        }
                        statusControl(f).padding(.top, 22)
                        partsSections(f).padding(.top, 28)
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

                        // Even before subscribing, show the parts breakdown.
                        partsSections(f).padding(.top, 28)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
                .offset(y: -80)
            }
            .frame(maxWidth: .infinity)
        }
        .ignoresSafeArea(edges: .top)
        .scrollContentBackground(.hidden)
        .overlay(alignment: .center) {
            if appModel.justCaught.contains(f.id) {
                CaughtUpOverlay(size: 62)
                    .frame(width: 200, height: 200)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: hero banner

    private func hero(_ f: Franchise) -> some View {
        ZStack(alignment: .topLeading) {
            RemoteImageView(url: f.banner ?? f.cover)
                .frame(maxWidth: .infinity, minHeight: 236, maxHeight: 236)
                .clipped()
                .opacity(0.6)
            LinearGradient(
                stops: [
                    .init(color: Theme.background, location: 0.03),
                    .init(color: Theme.background.opacity(0.35), location: 0.52),
                    .init(color: Theme.background.opacity(0.5), location: 1),
                ],
                startPoint: .bottom, endPoint: .top
            )
        }
        .frame(maxWidth: .infinity, minHeight: 236, maxHeight: 236)
        .clipped()
    }

    // MARK: header (poster + title + status line + genres)

    private func headerBlock(_ f: Franchise, inLibrary: Bool) -> some View {
        let releasing = f.releasingPart
        let behind = releasing?.episodesBehind ?? 0
        return VStack(alignment: .leading, spacing: 0) {
            // TITLE anchors the top so you know the show before reading metadata.
            Text(f.title)
                .scaledFont(26, weight: .semibold)
                .tracking(-0.7)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                if inLibrary {
                    // Explicit, glanceable confirmation that this franchise is saved.
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark").scaledFont(9, weight: .bold)
                        Text("In Library").scaledFont(11, weight: .semibold)
                    }
                    .foregroundStyle(Theme.accent)
                    .padding(.leading, 7).padding(.trailing, 8).padding(.vertical, 4)
                    .background(Theme.fillSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Theme.accentBorder, lineWidth: 1))
                }
                Text(inLibrary ? statusLabel(f.effectiveStatus) : "Not in library")
                    .scaledFont(13, monospacedDigit: true)
                    .foregroundStyle(Theme.text50)
                if behind > 0 {
                    Text("\(behind) behind")
                        .scaledFont(11.5, weight: .semibold)
                        .foregroundStyle(Theme.background)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .padding(.top, 10)

            // Supporting metadata + poster sit below the title.
            HStack(alignment: .top, spacing: 16) {
                Thumb(cover: f.cover, width: 108, height: 160, radius: 13)
                    .shadow(color: .black.opacity(0.6), radius: 20, y: 16)
                VStack(alignment: .leading, spacing: 12) {
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
                .padding(.top, 2)
                Spacer(minLength: 0)
            }
            .padding(.top, 16)

            if !f.genres.isEmpty {
                FlowChips(items: Array(f.genres.prefix(4)))
                    .padding(.top, 14)
            }
        }
    }

    /// A compact label / value pair for the metadata stack beside the poster.
    private func metaRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
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
    /// confused with the user's watched "X/Y" progress (DECISION B).
    private func episodesValue(_ part: FranchisePart) -> String {
        if part.totalEpisodes > 0 {
            if part.isReleasing && part.airedEpisodes < part.totalEpisodes {
                return "\(part.airedEpisodes) of \(part.totalEpisodes) aired"
            }
            return "\(part.totalEpisodes) total"
        }
        return "\(part.airedEpisodes) aired"
    }

    // MARK: airing callout

    private func airingCallout(part: FranchisePart, next: Int64) -> some View {
        HStack(spacing: 13) {
            Image(systemName: "clock")
                .scaledFont(20, weight: .medium)
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text("Episode \(part.nextEpisodeNumber.map(String.init) ?? "?") airs \(Formatting.fmtDay(ts: next, now: now))")
                    .scaledFont(13)
                    .foregroundStyle(Theme.text62)
                Text(Formatting.fmtTime(next))
                    .scaledFont(12, monospacedDigit: true)
                    .foregroundStyle(Theme.text40)
            }
            Spacer(minLength: 8)
            Text(Formatting.fmtCountdown(target: next, now: now))
                .scaledFont(18, weight: .medium, monospacedDigit: true)
                .foregroundStyle(Theme.accent)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .glassTinted(Theme.accent.opacity(0.5), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(Theme.accentBorder, lineWidth: 1))
    }

    // MARK: upcoming-season callout (web-sourced "what's next" news)

    /// Surfaces announced/airing future seasons & films that AniList can't date precisely
    /// (it only exposes per-episode airing times once a broadcast slot exists). The `release`
    /// here is a human-readable window like "October 2026" or "January 2027".
    @ViewBuilder
    private func upcomingCallout(_ up: FranchiseUpcoming) -> some View {
        let accent = up.isConcluded ? Theme.text50 : Theme.accent
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                Image(systemName: up.isConcluded ? "checkmark.seal" : "calendar")
                    .scaledFont(15, weight: .semibold)
                    .foregroundStyle(accent)
                Text(up.tag.uppercased())
                    .scaledFont(10.5, weight: .bold)
                    .tracking(0.7)
                    .foregroundStyle(accent)
                Spacer(minLength: 8)
                if !up.displayRelease.isEmpty {
                    Text(up.displayRelease)
                        .scaledFont(12.5, weight: .semibold, monospacedDigit: true)
                        .foregroundStyle(Theme.text70)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let next = up.next, !next.isEmpty {
                Text(next)
                    .scaledFont(15, weight: .semibold)
                    .foregroundStyle(Theme.text90)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let note = up.note, !note.isEmpty {
                Text(note)
                    .scaledFont(12.5)
                    .foregroundStyle(Theme.text50)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.vertical, 14)
        .glassTinted(accent.opacity(0.5), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(up.isConcluded ? Theme.hairlineStrong : Theme.accentBorder, lineWidth: 1)
        )
    }

    // MARK: watch actions (safe +1 vs. mark caught up)

    /// Two clear actions for a behind, in-library show. The PRIMARY "+1 Episode" is the safe
    /// single-step advance; "Mark caught up" is the secondary jump-to-latest (#P0-2).
    /// Surfaces the exact next-to-WATCH episode (progress + 1, DECISION C) — distinct from the
    /// next-to-AIR shown in the airing callout (#P1-6).
    private func watchActions(_ f: Franchise, part: FranchisePart) -> some View {
        // Cap the +1 at what's actually watchable: aired for a releasing part, else the total.
        let cap = part.isReleasing
            ? max(part.airedEpisodes, part.progress)
            : (part.totalEpisodes > 0 ? part.totalEpisodes : part.progress + 1)
        let nextToWatch = part.progress + 1

        return VStack(alignment: .leading, spacing: 12) {
            // "Next: Ep N" — the exact episode to play next (core promise).
            HStack(spacing: 8) {
                Image(systemName: "play.circle.fill")
                    .scaledFont(15, weight: .semibold)
                    .foregroundStyle(Theme.accent)
                Text("Next: Ep \(nextToWatch)")
                    .scaledFont(14, weight: .semibold, monospacedDigit: true)
                    .foregroundStyle(Theme.text90)
                Spacer(minLength: 8)
                Text("\(part.episodesBehind) to catch up")
                    .scaledFont(12, monospacedDigit: true)
                    .foregroundStyle(Theme.text46)
            }

            // Both actions share an identical frame/style so they read as an even, balanced pair.
            HStack(spacing: 10) {
                // PRIMARY: safe single-step advance.
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        appModel.setProgress(franchiseId: f.id, mediaId: part.mediaId,
                                             episodes: min(nextToWatch, cap))
                    }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "plus").scaledFont(15, weight: .bold)
                        Text("Watch Ep \(nextToWatch)").scaledFont(15, weight: .semibold)
                    }
                    .frame(maxWidth: .infinity).frame(height: 50)
                    .foregroundStyle(Theme.background)
                }
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .shadow(color: Theme.accent.opacity(0.3), radius: 12, y: 4)
                .buttonStyle(BounceButtonStyle())

                // SECONDARY: jump straight to the latest aired episode.
                Button {
                    appModel.markCaughtUp(f.id)
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "checkmark").scaledFont(14, weight: .bold)
                        Text("Catch up").scaledFont(15, weight: .semibold)
                    }
                    .frame(maxWidth: .infinity).frame(height: 50)
                    .foregroundStyle(Theme.text90)
                }
                .background(Theme.fillSoft, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(Theme.hairlineStrong, lineWidth: 1))
                .buttonStyle(BounceButtonStyle())
            }

            // Reassure that the jump is reversible (the app shows an undo toast).
            HStack(spacing: 5) {
                Image(systemName: "arrow.uturn.backward")
                    .scaledFont(10, weight: .semibold)
                Text("Any change can be undone")
                    .scaledFont(11.5)
            }
            .foregroundStyle(Theme.text40)
        }
    }

    // MARK: status control — sliding pill via matchedGeometryEffect

    private func statusControl(_ f: Franchise) -> some View {
        VStack(alignment: .leading, spacing: 10) {
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
                .frame(maxWidth: .infinity).padding(.vertical, 11)
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

    private func partsSections(_ f: Franchise) -> some View {
        // A single "Parts" anchor ties the header's "4 Seasons · 1 Movie" breakdown to the
        // per-part progress below, so the steppers read as the drill-down (#P2-11).
        VStack(alignment: .leading, spacing: 18) {
            SectionHeader(label: "Parts & Episodes",
                          trailing: partBreakdown(f.partCounts))
            VStack(alignment: .leading, spacing: 24) {
                ForEach(f.sections, id: \.kind) { section in
                    VStack(alignment: .leading, spacing: 0) {
                        SectionHeader(label: section.kind.sectionTitle, trailing: "\(section.parts.count)")
                        VStack(spacing: 10) {
                            ForEach(section.parts) { part in
                                PartRow(part: part,
                                        inLibrary: appModel.isInLibrary(f.id),
                                        onSetProgress: { eps in
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                appModel.setProgress(franchiseId: f.id, mediaId: part.mediaId, episodes: eps)
                                            }
                                        })
                            }
                        }
                    }
                }
            }
        }
    }

    private func statusLabel(_ s: WatchStatus) -> String {
        switch s {
        case .watching: return "Watching"
        case .completed: return "Completed"
        case .planned: return "Plan to watch"
        }
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

// A single part row with a per-part status chip and either a binary movie toggle or a stepper.
private struct PartRow: View {
    let part: FranchisePart
    let inLibrary: Bool
    let onSetProgress: (Int) -> Void

    private var cap: Int {
        if part.isReleasing { return max(part.airedEpisodes, part.progress) }
        if part.totalEpisodes > 0 { return part.totalEpisodes }
        return Int.max
    }
    private var canInc: Bool { part.progress < cap }
    private var canDec: Bool { part.progress > 0 }
    private var fraction: Double {
        part.totalEpisodes > 0 ? min(1, Double(part.progress) / Double(part.totalEpisodes)) : 0
    }

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

    /// Target for the one-tap "Mark all watched" shortcut: the full season for a finished part,
    /// or the latest aired episode while releasing. Nil when there's nothing watchable yet or
    /// the count is unknown.
    private var markAllTarget: Int? {
        if part.isMovie || part.isUpcoming { return nil }
        if part.isReleasing { return part.airedEpisodes > 0 ? part.airedEpisodes : nil }
        return part.totalEpisodes > 0 ? part.totalEpisodes : nil
    }

    /// The WATCHED count line. Movies use the binary toggle instead, and an unknown total never
    /// renders as the confusing "0/?" — it falls back to a bare count (or nothing when unstarted).
    private var watchedLabel: String? {
        if part.isMovie { return nil }
        if part.totalEpisodes > 0 { return "Watched \(part.progress)/\(part.totalEpisodes)" }
        if part.progress > 0 { return "Watched \(part.progress)" }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Thumb(cover: part.cover, width: 44, height: 62, radius: 9)
                VStack(alignment: .leading, spacing: 3) {
                    Text(part.label.isEmpty ? part.title : part.label)
                        .scaledFont(14.5, weight: .semibold)
                        .lineLimit(1)
                        .foregroundStyle(Theme.textPrimary)
                    HStack(spacing: 8) {
                        if let fmt = part.format {
                            Text(fmt).scaledFont(11).foregroundStyle(Theme.text40)
                        }
                        if part.isReleasing {
                            Text("\(part.airedEpisodes) aired")
                                .scaledFont(11, weight: .medium).foregroundStyle(Theme.accent)
                        }
                    }
                    if part.isUpcoming {
                        // Unaired: surface when it premieres instead of a watched count.
                        Text(part.premiereAt.map { "Premieres \(Formatting.fmtFullDate($0))" } ?? "Release date TBA")
                            .scaledFont(12, weight: .medium)
                            .foregroundStyle(Theme.accent)
                    } else if let watchedLabel {
                        Text(watchedLabel)
                            .scaledFont(12, monospacedDigit: true)
                            .foregroundStyle(Theme.text50)
                    }
                }
                Spacer(minLength: 8)
                StatusChip(status: status)
            }

            if !part.isMovie && !part.isUpcoming && part.totalEpisodes > 0 {
                ProgressBar(fraction: fraction, height: 4)
            }

            if inLibrary && !part.isUpcoming {
                if part.isMovie {
                    movieToggle
                } else {
                    stepper
                    if let target = markAllTarget, part.progress < target {
                        markAllButton(target)
                    }
                }
            }
        }
        .padding(13)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.hairline, lineWidth: 1))
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

    // Episode stepper for seasons / OVAs / specials.
    private var stepper: some View {
        HStack(spacing: 12) {
            StepperButton(symbol: "minus", enabled: canDec) {
                if canDec { onSetProgress(part.progress - 1) }
            }
            // numericText content transition animates the count as it changes.
            Text("\(part.progress)")
                .scaledFont(20, weight: .medium, monospacedDigit: true)
                .frame(maxWidth: .infinity)
                .contentTransition(.numericText())
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: part.progress)
            StepperButton(symbol: "plus", enabled: canInc) {
                if canInc { onSetProgress(part.progress + 1) }
            }
        }
    }

    // One-tap shortcut to finish a season without stepping through every episode (#season-quick-mark).
    private func markAllButton(_ target: Int) -> some View {
        Button {
            onSetProgress(target)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "checkmark.circle.fill").scaledFont(13, weight: .bold)
                Text(part.isReleasing ? "Mark caught up" : "Mark all watched")
                    .scaledFont(13.5, weight: .semibold)
            }
            .frame(maxWidth: .infinity).frame(height: 40)
            .foregroundStyle(Theme.text90)
        }
        .background(Theme.fillSoft, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(Theme.hairlineStrong, lineWidth: 1))
        .buttonStyle(BounceButtonStyle())
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

private struct StepperButton: View {
    let symbol: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .scaledFont(18, weight: .semibold)
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 44, height: 44)
                .background(Theme.fillSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.hairlineStrong, lineWidth: 1))
        }
        .buttonStyle(BounceButtonStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
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
