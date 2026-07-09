import SwiftUI

// "Today" tab — greeting, "Out now" (fresh episodes since last open), and "Airing soon" (48h).
struct TodayView: View {
    @Environment(AppModel.self) private var appModel
    let onOpenDetail: (_ franchiseId: String, _ zoomID: String) -> Void

    private var now: Int64 { appModel.now }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header

                if appModel.loadError && !appModel.libraryEmpty {
                    RetryBanner { Task { await appModel.reload() } }
                }

                if appModel.loading && appModel.library.isEmpty {
                    Loader()
                } else if appModel.loadError && appModel.libraryEmpty {
                    // The load failed and we have nothing local — an error state, NOT the
                    // first-run welcome (we don't know the library is empty).
                    EmptyStateView(
                        title: "Couldn't load your shows",
                        message: "The server couldn't be reached. Check your connection and try again.",
                        ctaLabel: "Retry",
                        onCta: { Task { await appModel.reload() } }
                    )
                } else if appModel.libraryEmpty && !appModel.loading {
                    EmptyStateView(
                        title: "Welcome to AniTrack",
                        message: "Your airing-first tracker. Add shows you're watching and we'll tell you exactly what dropped and what's next. Use the Add tab to get started."
                    )
                } else if homeEmpty && !appModel.loading {
                    EmptyStateView(
                        title: "You're all caught up",
                        message: allCaughtUpBody
                    )
                }

                if !appModel.outNow.isEmpty {
                    outNowSection.padding(.top, 32)
                }
                if !appModel.soon.isEmpty {
                    soonSection.padding(.top, 34)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 140)
            // Loading → content and list membership changes cross-fade / settle instead of popping.
            .animation(.easeInOut(duration: 0.25), value: appModel.loading)
            .animation(.easeInOut(duration: 0.25), value: appModel.loadError)
            .animation(.spring(response: 0.42, dampingFraction: 0.82), value: appModel.outNow.map(\.id))
            .animation(.spring(response: 0.42, dampingFraction: 0.82), value: appModel.soon.map(\.id))
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .refreshable {
            await appModel.reload()
            // Quiet completion tick; failures already buzz via showError.
            if !appModel.loadError { Haptics.impact(.light) }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var homeEmpty: Bool { appModel.outNow.isEmpty && appModel.soon.isEmpty }

    // MARK: header

    // Compact header (#P2-13): date line + greeting on one tight block, single one-line context.
    // Keeps the orientation cues but drops the tall two-line subtitle so real content sits higher.
    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(Formatting.greetingFor(now))
                    .scaledFont(22, weight: .semibold)
                    .tracking(-0.6)
                Text(Formatting.fmtTodayDate(now))
                    .scaledFont(12.5, weight: .medium, monospacedDigit: true)
                    .foregroundStyle(Theme.accent)
            }
            Text(subtitle)
                .scaledFont(13.5)
                .foregroundStyle(Theme.text52)
                .lineLimit(1)
        }
    }

    private var subtitle: String {
        if appModel.libraryEmpty {
            return "Add your first show to get started."
        }
        let n = appModel.outNow.count
        if n > 0 {
            // outNow counts franchises, not episodes — say so.
            return n == 1 ? "1 show with a new episode." : "\(n) shows with new episodes."
        }
        return "You're all caught up."
    }

    private var allCaughtUpBody: String {
        if let next = appModel.nextUp?.releasingPart?.nextAiringAt {
            let label = "\(Formatting.fmtDay(ts: next, now: now)) \(Formatting.fmtTime(next))"
            return "Nothing new since you were last here. Your next episode lands \(label)."
        }
        return "Nothing new since you were last here."
    }

    // MARK: Out now

    private var outNowSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(dot: true, label: "Out now",
                          trailing: appModel.outNow.isEmpty ? nil :
                            "\(appModel.outNow.count) \(appModel.outNow.count == 1 ? "show" : "shows")")
            VStack(spacing: 11) {
                ForEach(appModel.outNow) { f in
                    BriefingRow(vm: CardModel(franchise: f, action: .mark, now: now),
                                justCaughtUp: appModel.justCaught.contains(f.id),
                                onOpen: { onOpenDetail(f.id, "outnow/\(f.id)") },
                                onPrimary: { appModel.markCaughtUp(f.id) })
                        .zoomSource("outnow/\(f.id)")
                        .contextMenu { FranchiseContextMenu(f: f, appModel: appModel) }
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
        }
    }

    // MARK: Airing soon

    // Airing soon (#P1-4): a confident peer section. Each upcoming episode is its own card with a
    // larger thumb and a prominent countdown pill, so it no longer reads as a buried list at the
    // very bottom. Order is unchanged (still below "Out now").
    private var soonSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(systemIcon: "clock", label: "Airing soon", trailing: "next 48h")
            VStack(spacing: 10) {
                ForEach(appModel.soon) { f in
                    let vm = CardModel(franchise: f, action: .none, now: now)
                    Button { onOpenDetail(f.id, "soon/\(f.id)") } label: {
                        HStack(spacing: 13) {
                            Thumb(cover: vm.cover, width: 44, height: 62, radius: 9)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(vm.title)
                                    .scaledFont(15, weight: .semibold)
                                    .tracking(-0.2)
                                    .lineLimit(1)
                                    .foregroundStyle(Theme.textPrimary)
                                // "Ep N" here is the next episode to AIR (airing context), with day/time.
                                Text("Ep \(vm.nextEp.map(String.init) ?? "?") · \(vm.dayLabel) \(vm.airTime)")
                                    .scaledFont(12.5, weight: .medium, monospacedDigit: true)
                                    .foregroundStyle(Theme.text52)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            countdownPill(vm)
                        }
                        .padding(.horizontal, 13).padding(.vertical, 11)
                        .background(Theme.fillFaint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.hairline, lineWidth: 1))
                    }
                    .buttonStyle(SpringPressButtonStyle(scale: 0.98))
                    .zoomSource("soon/\(f.id)")
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
        }
    }

    // Prominent countdown pill — accent-filled when the episode is imminent (<24h), tinted glass
    // otherwise — so "Airing soon" carries real urgency.
    @ViewBuilder
    private func countdownPill(_ vm: CardModel) -> some View {
        let shape = Capsule()
        Text(vm.countdown)
            .scaledFont(13.5, weight: .semibold, monospacedDigit: true)
            .contentTransition(.numericText(countsDown: true))
            .animation(.snappy(duration: 0.3), value: vm.countdown)
            .foregroundStyle(vm.countdownIsImminent ? Theme.background : Theme.accent)
            .padding(.horizontal, 11).padding(.vertical, 6)
            .background {
                if vm.countdownIsImminent {
                    shape.fill(Theme.accent)
                } else {
                    shape.fill(Theme.accentSoft).overlay(shape.stroke(Theme.accentBorder, lineWidth: 1))
                }
            }
    }
}
