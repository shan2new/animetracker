import SwiftUI

// Franchise detail sheet. Fetches the full franchise (parts + subscription) and shows:
//  - banner hero with concentric-corner close button,
//  - the releasing part's "next episode" callout + a glass "Mark caught up",
//  - parts grouped into Seasons / Movies / OVAs / Specials, each with its own progress stepper,
//  - a subscribe control (or status segmented control when subscribed).
struct FranchiseDetailView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
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
        .presentationBackground(Theme.background)
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
                        .font(.system(size: 14.5))
                        .foregroundStyle(Theme.text66)
                        .lineSpacing(5)
                        .padding(.top, 20)

                    if inLibrary {
                        if let part = releasing, part.isBehind {
                            MarkCaughtUpButton(label: "Mark caught up · Ep \(part.airedEpisodes)") {
                                appModel.markCaughtUp(f.id)
                            }
                            .padding(.top, 14)
                        }
                        statusControl(f).padding(.top, 22)
                        partsSections(f).padding(.top, 24)
                    } else {
                        Button {
                            appModel.addToLibrary(franchiseId: f.id, title: f.title, isReleasing: f.isReleasing)
                        } label: {
                            HStack(spacing: 9) {
                                Image(systemName: "plus").font(.system(size: 16, weight: .bold))
                                Text("Add to library").font(.system(size: 15.5, weight: .semibold))
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
        }
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
                .frame(height: 236)
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
            GlassCircleButton(systemName: "chevron.left", size: 40, iconSize: 17) { dismiss() }
                .padding(.leading, 16)
                .padding(.top, 18)
        }
        .frame(height: 236)
    }

    // MARK: header (poster + title + status line + genres)

    private func headerBlock(_ f: Franchise, inLibrary: Bool) -> some View {
        let releasing = f.releasingPart
        let behind = releasing?.episodesBehind ?? 0
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom, spacing: 16) {
                Thumb(cover: f.cover, width: 108, height: 160, radius: 13)
                    .shadow(color: .black.opacity(0.6), radius: 20, y: 16)
                VStack(alignment: .leading, spacing: 0) {
                    if behind > 0 {
                        Text("\(behind) behind")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(Theme.background)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .padding(.bottom, 9)
                    }
                    Text(inLibrary ? statusLabel(f.effectiveStatus) : "Not in library")
                        .font(Theme.mono(13))
                        .foregroundStyle(Theme.text50)
                }
                .padding(.bottom, 6)
                Spacer(minLength: 0)
            }

            Text(f.title)
                .font(.system(size: 24, weight: .semibold))
                .tracking(-0.7)
                .padding(.top, 18)

            if !f.genres.isEmpty {
                FlowChips(items: Array(f.genres.prefix(4)))
                    .padding(.top, 13)
            }
        }
    }

    // MARK: airing callout

    private func airingCallout(part: FranchisePart, next: Int64) -> some View {
        HStack(spacing: 13) {
            Image(systemName: "clock")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text("Episode \(part.nextEpisodeNumber.map(String.init) ?? "?") airs \(Formatting.fmtDay(ts: next, now: now))")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text62)
                Text(Formatting.fmtTime(next))
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.text40)
            }
            Spacer(minLength: 8)
            Text(Formatting.fmtCountdown(target: next, now: now))
                .font(Theme.mono(18, weight: .medium))
                .foregroundStyle(Theme.accent)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .glassTinted(Theme.accent.opacity(0.5), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(Theme.accentBorder, lineWidth: 1))
    }

    // MARK: status control — sliding pill via matchedGeometryEffect

    private func statusControl(_ f: Franchise) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Status")
                .font(.system(size: 12, weight: .semibold))
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
                .font(.system(size: 12.5, weight: .medium))
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

    private func statusLabel(_ s: WatchStatus) -> String {
        switch s {
        case .watching: return "Watching"
        case .completed: return "Completed"
        case .planned: return "Plan to watch"
        }
    }
}

// A single part row with a per-part progress stepper.
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Thumb(cover: part.cover, width: 44, height: 62, radius: 9)
                VStack(alignment: .leading, spacing: 3) {
                    Text(part.label.isEmpty ? part.title : part.label)
                        .font(.system(size: 14.5, weight: .semibold))
                        .lineLimit(1)
                        .foregroundStyle(Theme.textPrimary)
                    HStack(spacing: 8) {
                        if let fmt = part.format {
                            Text(fmt).font(.system(size: 11)).foregroundStyle(Theme.text40)
                        }
                        if part.isReleasing {
                            Text("Airing").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.accent)
                        }
                    }
                    Text("\(part.progress) / \(part.totalEpisodes > 0 ? String(part.totalEpisodes) : "?")")
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.text50)
                }
                Spacer(minLength: 8)
            }

            if part.totalEpisodes > 0 {
                ProgressBar(fraction: fraction, height: 4)
            }

            if inLibrary {
                HStack(spacing: 12) {
                    StepperButton(symbol: "minus", enabled: canDec) {
                        if canDec { onSetProgress(part.progress - 1) }
                    }
                    // numericText content transition animates the count as it changes.
                    Text("\(part.progress)")
                        .font(Theme.mono(20, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: part.progress)
                    StepperButton(symbol: "plus", enabled: canInc) {
                        if canInc { onSetProgress(part.progress + 1) }
                    }
                }
            }
        }
        .padding(13)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.hairline, lineWidth: 1))
    }
}

private struct StepperButton: View {
    let symbol: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
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
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.text62)
                    .padding(.horizontal, 11).padding(.vertical, 5)
                    .background(Theme.fillSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Theme.hairline, lineWidth: 1))
            }
        }
    }
}
