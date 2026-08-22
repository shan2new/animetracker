import SwiftUI
import UIKit

// Profile (spec board 08): a modal with Done, in the iOS grouped-list grammar. Trust is
// inspectable here — the sync line and every failed change, with Retry — and nothing else is
// decorated. No import this version.
struct ProfileView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @State private var hapticsOn = FeedbackCoordinator.enabled
    @State private var confirmSignOut = false

    private var now: Int64 { appModel.now }
    private var sync: SyncCenter { SyncCenter.shared }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ThemeSpace.x5) {
                    account
                    syncSection
                    settings
                    about
                    signOut
                }
                .padding(ThemeSpace.x4)
                .padding(.bottom, 80)
            }
            .scrollIndicators(.hidden)
            .background(ThemeColor.canvasRaised.ignoresSafeArea())
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(Copy.Action.done) { dismiss() }.fontWeight(.semibold)
                }
            }
        }
        .onAppear { sync.profileIsOpen = true }
        .onDisappear { sync.profileIsOpen = false }
        .confirmationDialog("Sign out?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) {
                FeedbackCoordinator.fire(.destructive)
                Task { await auth.signOut() }
            }
            Button(Copy.Confirm.cancel, role: .cancel) {}
        } message: {
            Text("Your library stays in your account. Changes that haven’t synced yet are kept on this device.")
        }
    }

    // MARK: - Sections

    private var account: some View {
        GroupedList {
            HStack(spacing: ThemeSpace.x3) {
                ZStack {
                    Circle().fill(ThemeColor.surfaceFloating)
                    Circle().stroke(ThemeColor.stroke, lineWidth: 1)
                    Text(initials).type(ThemeType.bodyEmphasis).foregroundStyle(ThemeColor.textSecondary)
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(accountName).type(ThemeType.bodyEmphasis).foregroundStyle(ThemeColor.textPrimary).lineLimit(1)
                    Text("\(Copy.titles(appModel.library.count)) in your library")
                        .type(ThemeType.metadata).foregroundStyle(ThemeColor.textSecondary)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 68)
        }
    }

    private var syncSection: some View {
        GroupedList(header: "Sync") {
            GroupedRow(symbol: sync.isOnline ? "arrow.triangle.2.circlepath" : "wifi.slash",
                       symbolTint: sync.isOnline ? ThemeColor.accentSoft : ThemeColor.warning.opacity(0.2),
                       title: sync.syncedLine(now: now),
                       subtitle: sync.isOnline ? nil : Copy.Notice.noConnection,
                       trailing: appModel.isRefreshing ? .none : .chevron(nil),
                       separator: !sync.failedChanges.isEmpty) {
                Task { await appModel.reload() }
            }
            ForEach(Array(sync.failedChanges.enumerated()), id: \.element.id) { i, change in
                GroupedRow(symbol: "exclamationmark.triangle", symbolTint: ThemeColor.warning.opacity(0.2),
                           title: "\(change.command) · \(change.title)", subtitle: change.reason, warning: true,
                           trailing: change.canRetry(sync) ? .chevron(Copy.Action.retry) : .none,
                           separator: i < sync.failedChanges.count - 1) {
                    if change.canRetry(sync) { sync.retry(change.id) }
                }
                .contextMenu {
                    Button(role: .destructive) { sync.discard(change.id) } label: { Label(Copy.Action.discard, systemImage: "trash") }
                }
            }
        }
    }

    private var settings: some View {
        GroupedList(header: "Settings") {
            ShareLink(item: LibraryExport(appModel: appModel, format: .json), preview: SharePreview("Previously library (JSON)")) {
                exportRow(title: "Export as JSON", subtitle: "Every title with progress and status")
            }
            .buttonStyle(GroupedRowPressStyle())
            ShareLink(item: LibraryExport(appModel: appModel, format: .csv), preview: SharePreview("Previously library (CSV)")) {
                exportRow(title: "Export as CSV", subtitle: "One row per season or movie")
            }
            .buttonStyle(GroupedRowPressStyle())
            GroupedRow(symbol: "bell", symbolTint: ThemeColor.information.opacity(0.2), title: "Notifications",
                       subtitle: "Episode alerts and the Live Activity", trailing: .chevron(nil)) {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            GroupedRow(symbol: "hand.tap", symbolTint: ThemeColor.accentSoft, title: "Haptics",
                       subtitle: "Confirms marks and milestones", trailing: .toggle($hapticsOn), separator: false)
        }
        .onChange(of: hapticsOn) { _, on in
            FeedbackCoordinator.enabled = on
            if on { FeedbackCoordinator.fire(.selection) }
        }
    }

    private var about: some View {
        GroupedList(header: "About") {
            GroupedRow(symbol: "info.circle", symbolTint: ThemeColor.surfacePressed, title: "Previously",
                       trailing: .value(version))
            GroupedRow(symbol: "film", symbolTint: ThemeColor.surfacePressed, title: "Data from AniList and TMDB",
                       subtitle: "This product uses the TMDB API but is not endorsed or certified by TMDB.", separator: false)
        }
    }

    private var signOut: some View {
        Button("Sign out") { confirmSignOut = true }
            .buttonStyle(TertiaryButtonStyle2(destructive: true))
            .frame(maxWidth: .infinity)
            .padding(.top, ThemeSpace.x2)
    }

    private func exportRow(title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "square.and.arrow.up").font(.system(size: 15, weight: .medium)).foregroundStyle(ThemeColor.textPrimary)
                .frame(width: 28, height: 28).background(ThemeColor.surfacePressed, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).type(ThemeType.body).foregroundStyle(ThemeColor.textPrimary)
                Text(subtitle).type(ThemeType.metadata).foregroundStyle(ThemeColor.textSecondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.forward").font(.system(size: 13, weight: .semibold)).foregroundStyle(ThemeColor.textTertiary)
        }
        .padding(.leading, 14).padding(.trailing, 16)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) { Rectangle().fill(ThemeColor.separator).frame(height: 1).padding(.leading, 54) }
    }

    // MARK: - Helpers

    /// A Clerk user id is not a name: show the account generically rather than an opaque token.
    private var accountName: String {
        let n = auth.displayName.trimmingCharacters(in: .whitespaces)
        return (n.isEmpty || n.hasPrefix("user_")) ? "Your account" : n
    }

    private var initials: String {
        let parts = accountName.split(separator: " ").prefix(2).compactMap { $0.first }
        let s = String(parts).uppercased()
        return s.isEmpty ? "•" : s
    }

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        return b.map { "\(v) (\($0))" } ?? v
    }
}
