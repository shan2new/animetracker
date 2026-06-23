import SwiftUI

// "Schedule" tab — the IST Mon..Sun week, each releasing part bucketed by its next airing day.
struct ScheduleView: View {
    @Environment(AppModel.self) private var appModel
    let onOpenDetail: (String) -> Void

    private var now: Int64 { appModel.now }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Schedule")
                    .font(.system(size: 27, weight: .semibold))
                    .tracking(-0.8)
                Text("Your week of airings, in IST. Today is highlighted.")
                    .font(.system(size: 14))
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
    }

    private func dayBlock(_ day: AppModel.ScheduleDay) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                if day.isToday {
                    Circle().fill(Theme.accent).frame(width: 7, height: 7)
                        .shadow(color: Theme.accent.opacity(0.85), radius: 5)
                }
                Text(day.label)
                    .font(.system(size: 16, weight: .semibold))
                    .tracking(-0.3)
                    .foregroundStyle(day.isToday ? Theme.accent : Theme.textPrimary)
                Text(day.dateLabel)
                    .font(Theme.mono(13))
                    .foregroundStyle(Theme.text36)
                Spacer(minLength: 8)
                if day.isToday {
                    Text("TODAY")
                        .font(.system(size: 10, weight: .bold))
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
                Text("Nothing airing")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text26)
                    .padding(.vertical, 13)
            } else {
                VStack(spacing: 9) {
                    ForEach(day.franchises) { f in
                        row(f)
                    }
                }
                .padding(.top, 11)
            }
        }
    }

    private func row(_ f: Franchise) -> some View {
        let vm = CardModel(franchise: f, action: .none, now: now)
        return Button { onOpenDetail(f.id) } label: {
            HStack(spacing: 14) {
                Thumb(cover: vm.cover, width: 46, height: 64, radius: 9)
                VStack(alignment: .leading, spacing: 3) {
                    Text(vm.title)
                        .font(.system(size: 15, weight: .semibold))
                        .tracking(-0.2)
                        .lineLimit(1)
                        .foregroundStyle(Theme.textPrimary)
                    Text("Ep \(vm.nextEp.map(String.init) ?? "?") · \(vm.airTime)")
                        .font(Theme.mono(12.5))
                        .foregroundStyle(Theme.text46)
                    if vm.isBehind {
                        HStack(spacing: 6) {
                            Circle().fill(Theme.accent).frame(width: 5, height: 5)
                            Text(vm.behindLabel)
                                .font(.system(size: 11.5, weight: .semibold))
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
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1)
                        .foregroundStyle(Theme.text28)
                    Text(vm.countdown)
                        .font(Theme.mono(16, weight: .medium))
                        .foregroundStyle(vm.countdownColor)
                }
            }
            .padding(11)
        }
        .buttonStyle(SpringPressButtonStyle(scale: 0.98))
        .background(Color.white.opacity(0.028), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(Theme.hairline, lineWidth: 1))
    }
}
