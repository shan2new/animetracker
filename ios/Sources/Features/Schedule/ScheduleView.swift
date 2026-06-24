import SwiftUI

// "Schedule" tab — today through the end of the local week, each releasing part bucketed by its next airing day.
struct ScheduleView: View {
    @Environment(AppModel.self) private var appModel
    let onOpenDetail: (String) -> Void

    private var now: Int64 { appModel.now }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Schedule")
                    .scaledFont(27, weight: .semibold)
                    .tracking(-0.8)
                Text("Your week of airings. Today is highlighted.")
                    .scaledFont(14)
                    .foregroundStyle(Theme.text52)
                    .lineSpacing(2)
                    .padding(.top, 8)

                if appModel.loadError { RetryBanner { Task { await appModel.reload() } } }

                if appModel.loading && appModel.library.isEmpty {
                    Loader()
                } else if appModel.airingFranchises.isEmpty {
                    EmptyStateView(
                        title: "No airing shows yet",
                        message: appModel.libraryEmpty
                            ? "Add currently-airing anime and your weekly schedule fills in here."
                            : "None of your shows are currently airing. Add airing anime to see them here."
                    )
                } else {
                    VStack(alignment: .leading, spacing: 24) {
                        ForEach(appModel.scheduleDays) { day in
                            dayBlock(day)
                        }
                    }
                    .padding(.top, 26)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 34)
            .padding(.bottom, 120)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .refreshable { await appModel.reload() }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
    }

    private func dayBlock(_ day: AppModel.ScheduleDay) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                if day.isToday {
                    Circle().fill(Theme.accent).frame(width: 7, height: 7)
                        .shadow(color: Theme.accent.opacity(0.85), radius: 5)
                }
                Text(day.label)
                    .scaledFont(16, weight: .semibold)
                    .tracking(-0.3)
                    .foregroundStyle(day.isToday ? Theme.accent : Theme.textPrimary)
                Text(day.dateLabel)
                    .scaledFont(13, monospacedDigit: true)
                    .foregroundStyle(Theme.text36)
                Spacer(minLength: 8)
                if day.isToday {
                    Text("TODAY")
                        .scaledFont(10, weight: .bold)
                        .tracking(0.8)
                        .foregroundStyle(Theme.background)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
            }
            .padding(.bottom, 11)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
            }

            if day.franchises.isEmpty {
                // Schedule only counts UPCOMING airings, so an empty list can be misleading when
                // episodes already dropped earlier today. Use accurate copy and surface what aired.
                Text(emptyLabel(for: day))
                    .scaledFont(13)
                    .foregroundStyle(Theme.text26)
                    .padding(.vertical, 13)

                if !day.airedToday.isEmpty {
                    airedTodaySection(day.airedToday)
                }
            } else {
                VStack(spacing: 9) {
                    ForEach(day.franchises) { f in
                        row(f)
                    }
                }
                .padding(.top, 11)

                // Even with upcoming airings, show episodes that already dropped today for context.
                if day.isToday && !day.airedToday.isEmpty {
                    airedTodaySection(day.airedToday)
                        .padding(.top, 6)
                }
            }
        }
    }

    /// Copy for an empty day. Today never claims "nothing airing" when episodes already aired.
    private func emptyLabel(for day: AppModel.ScheduleDay) -> String {
        guard day.isToday else { return "Nothing airing" }
        return day.airedToday.isEmpty ? "Nothing airing today" : "No more airings today"
    }

    @ViewBuilder
    private func airedTodaySection(_ franchises: [Franchise]) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Already aired today")
                .scaledFont(11, weight: .semibold)
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(Theme.text36)
            ForEach(franchises) { f in
                airedRow(f)
            }
        }
        .padding(.top, 6)
    }

    private func airedRow(_ f: Franchise) -> some View {
        let vm = CardModel(franchise: f, action: .none, now: now)
        return Button { onOpenDetail(f.id) } label: {
            HStack(spacing: 14) {
                Thumb(cover: vm.cover, width: 46, height: 64, radius: 9)
                VStack(alignment: .leading, spacing: 3) {
                    Text(vm.title)
                        .scaledFont(15, weight: .semibold)
                        .tracking(-0.2)
                        .lineLimit(1)
                        .foregroundStyle(Theme.textPrimary)
                    Text("Ep \(vm.airedEpisodes) · aired \(vm.airedAgo)")
                        .scaledFont(12.5, monospacedDigit: true)
                        .foregroundStyle(Theme.text46)
                }
                Spacer(minLength: 8)
            }
            .padding(11)
            .opacity(0.82)
        }
        .buttonStyle(SpringPressButtonStyle(scale: 0.98))
        .background(Color.white.opacity(0.02), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(Theme.hairline, lineWidth: 1))
        .contextMenu { FranchiseContextMenu(f: f, appModel: appModel) }
    }

    private func row(_ f: Franchise) -> some View {
        let vm = CardModel(franchise: f, action: .none, now: now)
        return Button { onOpenDetail(f.id) } label: {
            HStack(spacing: 14) {
                Thumb(cover: vm.cover, width: 46, height: 64, radius: 9)
                VStack(alignment: .leading, spacing: 3) {
                    Text(vm.title)
                        .scaledFont(15, weight: .semibold)
                        .tracking(-0.2)
                        .lineLimit(1)
                        .foregroundStyle(Theme.textPrimary)
                    Text("Ep \(vm.nextEp.map(String.init) ?? "?") · \(vm.airTime)")
                        .scaledFont(12.5, monospacedDigit: true)
                        .foregroundStyle(Theme.text46)
                    if vm.isBehind {
                        HStack(spacing: 6) {
                            Circle().fill(Theme.accent).frame(width: 5, height: 5)
                            Text(vm.behindLabel)
                                .scaledFont(11.5, weight: .semibold)
                                .foregroundStyle(Theme.accent)
                        }
                        .padding(.leading, 7).padding(.trailing, 9).padding(.vertical, 3)
                        .background(Theme.accentChipFill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .padding(.top, 4)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("IN")
                        .scaledFont(10, weight: .semibold)
                        .tracking(1)
                        .foregroundStyle(Theme.text28)
                    Text(vm.countdown)
                        .scaledFont(16, weight: .medium, monospacedDigit: true)
                        .foregroundStyle(vm.countdownColor)
                }
            }
            .padding(11)
        }
        .buttonStyle(SpringPressButtonStyle(scale: 0.98))
        .background(Color.white.opacity(0.028), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(Theme.hairline, lineWidth: 1))
        .contextMenu { FranchiseContextMenu(f: f, appModel: appModel) }
    }
}
