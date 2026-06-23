import SwiftUI

// "Today" tab — greeting, "Out now" (briefing / spotlight / grid layouts), and "Airing soon" (48h).
struct TodayView: View {
    @Environment(AppModel.self) private var appModel
    let onOpenDetail: (String) -> Void

    enum HomeLayout: String, CaseIterable { case briefing, spotlight, grid }
    @State private var layout: HomeLayout = .briefing
    @Namespace private var toggleNS

    private var now: Int64 { appModel.now }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header

                if appModel.loadError && !appModel.libraryEmpty {
                    RetryBanner { Task { await appModel.reload() } }
                }

                if !appModel.outNow.isEmpty {
                    layoutToggle.padding(.top, 18)
                }

                if appModel.loading && appModel.library.isEmpty {
                    Loader()
                }

                if appModel.libraryEmpty && !appModel.loading {
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
            .padding(.top, 34)
            .padding(.bottom, 120)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
    }

    private var homeEmpty: Bool { appModel.outNow.isEmpty && appModel.soon.isEmpty }

    // MARK: header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Formatting.fmtTodayDate(now))
                .font(Theme.mono(12.5, weight: .medium))
                .foregroundStyle(Theme.accent)
            Text(Formatting.greetingFor(now))
                .font(.system(size: 29, weight: .semibold))
                .tracking(-1)
                .padding(.top, 7)
            Text(subtitle)
                .font(.system(size: 14.5))
                .foregroundStyle(Theme.text52)
                .lineSpacing(2)
                .padding(.top, 9)
        }
    }

    private var subtitle: String {
        if appModel.libraryEmpty {
            return "Track what's airing — add your first show to get started."
        }
        let n = appModel.outNow.count
        if n > 0 {
            return "You have \(n) fresh \(n == 1 ? "episode" : "episodes") waiting since you were last here."
        }
        return "Nothing new has aired. You're all caught up."
    }

    private var allCaughtUpBody: String {
        if let next = appModel.nextUp?.releasingPart?.nextAiringAt {
            let label = "\(Formatting.fmtDay(ts: next, now: now)) \(Formatting.fmtTime(next))"
            return "Nothing new since you were last here. Your next episode lands \(label)."
        }
        return "Nothing new since you were last here."
    }

    // MARK: layout toggle — sliding pill via matchedGeometryEffect

    private var layoutToggle: some View {
        HStack(spacing: 3) {
            ForEach(HomeLayout.allCases, id: \.self) { k in
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) { layout = k }
                } label: {
                    Text(k.rawValue.capitalized)
                        .font(.system(size: 12.5, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .foregroundStyle(layout == k ? Theme.background : Theme.text52)
                        .background {
                            if layout == k {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(Theme.accent)
                                    .matchedGeometryEffect(id: "layoutPill", in: toggleNS)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Theme.fillSoft, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(Theme.hairline, lineWidth: 1))
    }

    // MARK: Out now

    private var outNowSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(dot: true, label: "Out now",
                          trailing: appModel.outNow.isEmpty ? nil :
                            "\(appModel.outNow.count) \(appModel.outNow.count == 1 ? "show" : "shows")")
            // .id(layout) destroys/recreates on layout switch, triggering the cross-fade transition.
            Group {
                switch layout {
                case .briefing:
                    VStack(spacing: 11) {
                        ForEach(appModel.outNow) { f in
                            BriefingRow(vm: CardModel(franchise: f, action: .mark, now: now),
                                        justCaughtUp: appModel.justCaught.contains(f.id),
                                        onOpen: { onOpenDetail(f.id) },
                                        onPrimary: { appModel.markCaughtUp(f.id) })
                        }
                    }
                case .spotlight:
                    VStack(spacing: 13) {
                        if let hero = appModel.outNow.first {
                            HeroCard(vm: CardModel(franchise: hero, action: .mark, now: now),
                                     justCaughtUp: appModel.justCaught.contains(hero.id),
                                     onOpen: { onOpenDetail(hero.id) },
                                     onPrimary: { appModel.markCaughtUp(hero.id) })
                        }
                        let rest = Array(appModel.outNow.dropFirst())
                        if !rest.isEmpty {
                            posterGrid(rest, action: .mark)
                        }
                    }
                case .grid:
                    posterGrid(appModel.outNow, action: .mark)
                }
            }
            .id(layout)
            .transition(.opacity.animation(.easeOut(duration: 0.18)))
        }
    }

    // MARK: Airing soon

    private var soonSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(systemIcon: "clock", label: "Airing soon", trailing: "next 48h")
            VStack(spacing: 0) {
                ForEach(Array(appModel.soon.enumerated()), id: \.element.id) { idx, f in
                    let vm = CardModel(franchise: f, action: .none, now: now)
                    Button { onOpenDetail(f.id) } label: {
                        HStack(spacing: 13) {
                            Thumb(cover: vm.cover, width: 34, height: 48, radius: 7)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(vm.title)
                                    .font(.system(size: 14.5, weight: .medium))
                                    .lineLimit(1)
                                    .foregroundStyle(Theme.textPrimary)
                                Text("Ep \(vm.nextEp.map(String.init) ?? "?") · \(vm.dayLabel) \(vm.airTime)")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.text44)
                            }
                            Spacer(minLength: 8)
                            Text(vm.countdown)
                                .font(Theme.mono(14, weight: .medium))
                                .foregroundStyle(vm.countdownColor)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 12)
                    }
                    .buttonStyle(SpringPressButtonStyle(scale: 0.98))
                    if idx < appModel.soon.count - 1 {
                        Divider().overlay(Color.white.opacity(0.05))
                    }
                }
            }
            .background(Color.white.opacity(0.018), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.hairline, lineWidth: 1))
        }
    }

    // MARK: helpers

    private func posterGrid(_ franchises: [Franchise], action: CardAction) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 13), GridItem(.flexible(), spacing: 13)], spacing: 13) {
            ForEach(franchises) { f in
                PosterCard(vm: CardModel(franchise: f, action: action, now: now),
                           justCaughtUp: appModel.justCaught.contains(f.id),
                           onOpen: { onOpenDetail(f.id) },
                           onPrimary: { appModel.markCaughtUp(f.id) })
            }
        }
    }
}
