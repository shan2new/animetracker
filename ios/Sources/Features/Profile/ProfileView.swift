import SwiftUI

// Profile — presented in the SAME grammar as the franchise detail drawer (the app's one
// big-surface pattern): a .large sheet on Theme.background, a color-wash hero with a floating
// centerpiece (the avatar, where detail floats the poster), a centered title block, then the
// content column. Real-data-only: live library stats, the contractual data-source credits,
// and a version + sign-out footer. Streaks/history/settings wait for real features.
struct ProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthManager.self) private var auth
    @Environment(AppModel.self) private var appModel

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    hero

                    VStack(alignment: .leading, spacing: 0) {
                        titleBlock
                        statsRow.padding(.top, 26)
                        sectionCap("DATA SOURCES").padding(.top, 28)
                        sourceList.padding(.top, 8)
                        footer.padding(.top, 30)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 44)
                }
            }
            .scrollIndicators(.hidden)
        }
        .ignoresSafeArea(edges: .top)
        .scrollContentBackground(.hidden)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: hero — the detail drawer's color wash, warmed to the brand, avatar floating

    private var hero: some View {
        ZStack(alignment: .top) {
            // Same construction as the detail hero's wash — warm-tinted for the profile.
            LinearGradient(
                colors: [Color(hex: 0x3A2F1F), Theme.background],
                startPoint: .top, endPoint: .bottom
            )
            .overlay(alignment: .top) {
                RadialGradient(
                    colors: [Color(hex: 0x4A3B24).opacity(0.85), .clear],
                    center: .top, startRadius: 0, endRadius: 300
                )
            }
            .frame(height: 232)
            .frame(maxWidth: .infinity)

            // Floating centerpiece — the avatar, where detail floats the cover.
            Text(auth.avatarInitial)
                .scaledFont(36, weight: .bold)
                .foregroundStyle(Theme.background)
                .frame(width: 96, height: 96)
                .background(
                    LinearGradient(colors: [Theme.accent, Color(hex: 0xC9702E)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: Circle()
                )
                .overlay(Circle().stroke(Color.white.opacity(0.10), lineWidth: 1))
                .shadow(color: .black.opacity(0.6), radius: 24, y: 16)
                .padding(.top, 88)

            // Overlaid dismiss control, same as the detail drawer's.
            HStack {
                GlassCircleButton(systemName: "chevron.down", size: 34, iconSize: 16,
                                  foreground: Theme.textPrimary) { dismiss() }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
        .frame(height: 232)
        .frame(maxWidth: .infinity)
    }

    // MARK: title block — centered, like the detail's

    private var titleBlock: some View {
        VStack(spacing: 6) {
            Text(auth.displayName)
                .scaledFont(23, weight: .semibold)
                .tracking(-0.6)
                .multilineTextAlignment(.center)
                .lineLimit(1)
            Text(accountLine)
                .scaledFont(12.5, weight: .medium)
                .foregroundStyle(Theme.text62)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
    }

    private var accountLine: String {
        switch auth.mode {
        case .clerk: "Signed in with Clerk"
        case let .dev(clerkId): clerkId.isEmpty ? "Dev mode" : "Dev · \(clerkId)"
        }
    }

    // MARK: stats (live library data only)

    private var statsRow: some View {
        let watching = appModel.library.filter { $0.effectiveStatus == .watching }.count
        let completed = appModel.library.filter { $0.effectiveStatus == .completed }.count
        let planned = appModel.library.filter { $0.effectiveStatus == .planned }.count
        return HStack(spacing: 0) {
            stat(watching, label: "WATCHING")
            listDivider
            stat(completed, label: "COMPLETED")
            listDivider
            stat(planned, label: "PLANNED")
        }
        .background(cardShape)
    }

    private func stat(_ value: Int, label: String) -> some View {
        VStack(spacing: 3) {
            Text("\(value)")
                .scaledFont(20, weight: .bold, monospacedDigit: true)
                .tracking(-0.4)
                .contentTransition(.numericText())
            Text(label)
                .scaledFont(8.5)
                .tracking(1.4)
                .foregroundStyle(Theme.text36)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
    }

    private var listDivider: some View {
        Rectangle().fill(Theme.hairline).frame(width: 1).padding(.vertical, 8)
    }

    // MARK: data sources — compact, quiet

    private func sectionCap(_ label: String) -> some View {
        Text(label)
            .scaledFont(9)
            .tracking(1.6)
            .foregroundStyle(Theme.text36)
            .padding(.leading, 4)
    }

    private var sourceList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("AniList")
                    .scaledFont(13.5, weight: .semibold)
                    .foregroundStyle(Theme.text72)
                Spacer(minLength: 8)
                Text("Anime metadata & airing schedules")
                    .scaledFont(11)
                    .foregroundStyle(Theme.text40)
                    .lineLimit(1)
            }
            .padding(.vertical, 12)

            Rectangle().fill(Theme.hairline).frame(height: 1)

            // TMDB attribution — the logo + this exact line are a condition of TMDB's API terms.
            HStack(alignment: .center, spacing: 12) {
                Image("TMDBLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 11)
                Spacer(minLength: 8)
                Text("This product uses the TMDB API but is not endorsed or certified by TMDB.")
                    .scaledFont(9.5)
                    .foregroundStyle(Theme.text40)
                    .lineSpacing(1.5)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 220, alignment: .trailing)
            }
            .padding(.vertical, 12)
        }
        .padding(.horizontal, 14)
        .background(cardShape)
    }

    // MARK: footer

    private var footer: some View {
        HStack {
            Text("PREVIOUSLY. 1.0")
                .scaledFont(9.5, weight: .medium)
                .tracking(1.4)
                .foregroundStyle(Theme.text36)
            Spacer()
            Button {
                Haptics.impact(.soft)
                Task { await auth.signOut() }
            } label: {
                Text("SIGN OUT")
                    .scaledFont(9.5, weight: .semibold)
                    .tracking(1.4)
                    .foregroundStyle(Theme.destructive.opacity(0.85))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
    }

    // MARK: chrome

    private var cardShape: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.white.opacity(0.03))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Theme.hairline, lineWidth: 1)
            )
    }
}