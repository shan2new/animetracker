import SwiftUI

// Gates the app on authentication, then shows the four-tab main UI.
struct RootView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(AppModel.self) private var appModel

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if auth.isSignedIn {
                MainTabView()
                    .task(id: auth.isSignedIn) { appModel.start() }
                    .transition(.opacity.animation(.easeOut(duration: 0.3)))
            } else {
                SignInView()
                    .transition(.opacity.animation(.easeOut(duration: 0.3)))
            }
        }
    }
}

// The four tabs. Drives both the ZStack switcher and the floating tab bar.
enum AppTab: Int, CaseIterable, Hashable {
    case today, schedule, library, discover

    var label: String {
        switch self {
        case .today:    "Today"
        case .schedule: "Schedule"
        case .library:  "Library"
        case .discover: "Add"
        }
    }

    // Outline icon (unselected state).
    var icon: String {
        switch self {
        case .today:    "house"
        case .schedule: "calendar"
        case .library:  "books.vertical"
        case .discover: "magnifyingglass"
        }
    }

    // Fill icon (selected state) — use explicit names because .symbolVariant behaves
    // inconsistently for calendar and magnifyingglass across OS versions.
    var iconFill: String {
        switch self {
        case .today:    "house.fill"
        case .schedule: "calendar.fill"
        case .library:  "books.vertical.fill"
        case .discover: "magnifyingglass"
        }
    }
}

// Four-tab app. All four content views stay mounted in a ZStack so scroll positions,
// navigation stacks, and search state survive tab switches. The selected tab is shown
// via opacity; a 0.22 s easeOut crossfade plays on every switch.
struct MainTabView: View {
    @Environment(AppModel.self) private var appModel
    @State private var selectedTab: AppTab = .today

    var body: some View {
        @Bindable var model = appModel

        ZStack(alignment: .bottom) {
            // Content — four views always in the hierarchy; only the active one is visible.
            ZStack {
                TodayView(onOpenDetail: open)
                    .opacity(selectedTab == .today ? 1 : 0)
                    .allowsHitTesting(selectedTab == .today)
                ScheduleView(onOpenDetail: open)
                    .opacity(selectedTab == .schedule ? 1 : 0)
                    .allowsHitTesting(selectedTab == .schedule)
                LibraryView(onOpenDetail: open)
                    .opacity(selectedTab == .library ? 1 : 0)
                    .allowsHitTesting(selectedTab == .library)
                DiscoverView(onOpenDetail: open)
                    .opacity(selectedTab == .discover ? 1 : 0)
                    .allowsHitTesting(selectedTab == .discover)
            }
            .animation(.easeOut(duration: 0.22), value: selectedTab)

            // Floating glass tab bar.
            FloatingTabBar(selectedTab: $selectedTab)
        }
        .ignoresSafeArea(.keyboard)
        // Undo toast floats above the tab bar.
        .overlay(alignment: .bottom) {
            if let undo = appModel.undo {
                UndoToast(state: undo) { appModel.performUndo() }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 96)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: appModel.undo != nil)
            }
        }
        .sheet(item: $model.detailRoute) { route in
            FranchiseDetailView(franchiseId: route.value)
        }
    }

    private func open(_ franchiseId: String) {
        appModel.detailRoute = DetailRoute(value: franchiseId)
    }
}

// Floating pill tab bar. Uses Liquid Glass on iOS 26, ultraThinMaterial on iOS 17–25.
private struct FloatingTabBar: View {
    @Binding var selectedTab: AppTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                TabBarItem(tab: tab, selectedTab: $selectedTab)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .glassChrome(in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Theme.hairlineStrong, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.45), radius: 28, y: 10)
        .padding(.horizontal, 28)
        .padding(.bottom, 12)
    }
}

private struct TabBarItem: View {
    let tab: AppTab
    @Binding var selectedTab: AppTab
    @GestureState private var pressing = false

    private var isSelected: Bool { selectedTab == tab }

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: isSelected ? tab.iconFill : tab.icon)
                    .font(.system(size: 21, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Theme.accent : Theme.text46)
                    .scaleEffect(isSelected ? 1.1 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected)
                Text(tab.label)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Theme.accent : Theme.text44)
                    .animation(.easeOut(duration: 0.15), value: isSelected)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scaleEffect(pressing ? 0.87 : 1)
        .animation(.spring(response: 0.2, dampingFraction: 0.5), value: pressing)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .updating($pressing) { _, state, _ in state = true }
        )
    }
}

// Small Identifiable wrapper so a franchise id can drive `.sheet(item:)`.
struct DetailRoute: Identifiable, Equatable {
    let value: String
    var id: String { value }
}
