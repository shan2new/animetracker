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

// The four tabs.
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

    // Custom tab-bar glyphs (asset-catalog template images, see icon/navbar/). They tint with
    // the accent color when selected and gray when not, just like SF Symbols.
    var icon: String {
        switch self {
        case .today:    "TabToday"
        case .schedule: "TabSchedule"
        case .library:  "TabLibrary"
        case .discover: "TabAdd"
        }
    }
}

// Native four-tab app. On iOS 26 the system renders the floating, morphing glass tab bar with
// scroll-edge effects; on iOS 17–25 it's the standard tab bar. Franchise detail presents as a
// native drawer sheet that slides up over the current tab (medium detent, drag to full).
struct MainTabView: View {
    @Environment(AppModel.self) private var appModel
    @State private var selectedTab: AppTab = .today

    // The franchise detail presented as a drawer sheet over the current tab, plus its current
    // resting detent so we can fire a snap haptic as the user drags between medium and full.
    @State private var detail: DetailRoute?
    @State private var detailDetent: PresentationDetent = .medium

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                NavigationStack {
                    TodayView(onOpenDetail: openDetail)
                }
                .tabItem { Label(AppTab.today.label, image: AppTab.today.icon) }
                .tag(AppTab.today)

                NavigationStack {
                    ScheduleView(onOpenDetail: openDetail)
                }
                .tabItem { Label(AppTab.schedule.label, image: AppTab.schedule.icon) }
                .tag(AppTab.schedule)

                NavigationStack {
                    LibraryView(onOpenDetail: openDetail)
                }
                .tabItem { Label(AppTab.library.label, image: AppTab.library.icon) }
                .tag(AppTab.library)

                NavigationStack {
                    DiscoverView(onOpenDetail: openDetail)
                }
                .tabItem { Label(AppTab.discover.label, image: AppTab.discover.icon) }
                .tag(AppTab.discover)
            }
            .sensoryFeedback(.selection, trigger: selectedTab)

            // Undo toast floats above the tab bar.
            if let undo = appModel.undo {
                UndoToast(state: undo) { appModel.performUndo() }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 96)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: appModel.undo != nil)
            }
        }
        // Detail slides up as a native drawer: opens at half height, drag the grabber up to full.
        .sheet(item: $detail) { route in
            FranchiseDetailView(franchiseId: route.id)
                .presentationDetents([.medium, .large], selection: $detailDetent)
                .presentationDragIndicator(.visible)
                // Light snap as the drawer settles between medium and full.
                .sensoryFeedback(.impact(weight: .light), trigger: detailDetent)
        }
        // Tactile tap as the drawer rises (nil → id) and again as it dismisses (id → nil).
        .sensoryFeedback(.impact(weight: .medium), trigger: detail?.id)
    }

    // Open at the medium detent every time, regardless of where the last drawer was left.
    private func openDetail(_ id: String) {
        detailDetent = .medium
        detail = DetailRoute(id: id)
    }
}

// Identifiable wrapper so a franchise id can drive `.sheet(item:)`.
private struct DetailRoute: Identifiable { let id: String }
