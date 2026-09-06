import SwiftUI

// Gates the app on authentication, then shows the four-tab main UI.
struct RootView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(AppModel.self) private var appModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The cold launch: the icon's ribbon drawn by light, then the app coming through it.
    @State private var launch = LaunchHandoff()
    @State private var launchDone = false
    /// The app has started emerging beneath the ident.
    @State private var emerged = false

    var body: some View {
        ZStack {
            ThemeColor.canvas.ignoresSafeArea()
            // The app is laid out under the ident from the first frame and EMERGES through it: a
            // hair small while the ident holds, settling to full size as the ident pushes through
            // and fades off it. It is never faded itself — an opacity ramp over the whole tree is
            // an offscreen pass on every frame; the ident's two layers fading is the same picture
            // for the price of two layers. Under Reduce Motion nothing scales.
            Group {
                if auth.isSignedIn {
                    MainTabView()
                        .task(id: auth.isSignedIn) { appModel.start() }
                        .transition(.opacity.animation(ThemeMotion.uiGentle))
                } else {
                    SignInView()
                        .transition(.opacity.animation(ThemeMotion.uiGentle))
                }
            }
            // No scale on the whole tree (review i5): 0.96 → 1 on `uiSettle` was a full-screen
            // offscreen pass started in the frame the ident began leaving, and it froze the exit
            // at 80 % for half a second. The ident's ground IS the reveal.

            if !launchDone {
                LaunchIdent(
                    onLeaving: {
                        // The surface is the user's to read from here: the page-in (rise only —
                        // this emergence is the fade), the tab bar and the recap clock.
                        appModel.surfaceReady = true
                        withAnimation(ThemeMotion.pick(ThemeMotion.uiSettle, reduceMotion: reduceMotion)) {
                            emerged = true
                        }
                    },
                    onFinished: {
                        // The ident can end without `onLeaving` having fired (review i4: six
                        // captures had the app parked at 0.96 behind nothing). The surface is
                        // the user's the moment the ident is gone, whatever came before.
                        if !emerged {
                            appModel.surfaceReady = true
                            emerged = true
                        }
                        launchDone = true
                        launch.finished = true
                    })
                    .zIndex(10)
            }
        }
        .environment(launch)
        // The ident waits for auth's first answer before it leaves, so the screen it reveals is
        // the right one — never sign-in for a signed-in user.
        .onChange(of: auth.bootstrapped, initial: true) { _, ready in
            if ready { launch.authReady = true }
        }
        // Sign-out (chosen, or forced by an expired session) is the one moment the model outlives
        // its account: the library, the live clock, pending episode alerts and a running Live
        // Activity all survive the view tree. Tear them down here so signing in again starts clean.
        .onChange(of: auth.isSignedIn) { _, signedIn in
            if !signedIn { appModel.teardown() }
        }
        // Foreground refresh: a resumed app can be days stale (aired counts, "Out now") — the 20s
        // clock task alone can't fix data. AppModel decides how much staleness warrants a reload.
        .onChange(of: scenePhase) { _, phase in
            guard auth.isSignedIn else { return }
            switch phase {
            case .active: appModel.sceneBecameActive()
            case .background: appModel.sceneEnteredBackground()
            default: break
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
        // "Search", the same word the screen's title and the field's prompt use, and the word
        // VoiceOver already speaks for a search-role tab. It said "Add" — a tab named for one of
        // the things you can do on it, under a magnifier glyph.
        case .discover: "Search"
        }
    }

    // LocalizedStringKey form for the iOS 26 `Tab(_:image:value:)` initializer.
    var titleKey: LocalizedStringKey {
        switch self {
        case .today:    "Today"
        case .schedule: "Schedule"
        case .library:  "Library"
        case .discover: "Search"
        }
    }

    // Hugeicons tab-bar glyphs (asset-catalog template images, generated by icon/navbar/vector.py).
    // They tint with the accent color when selected and gray when not, just like SF Symbols.
    var icon: String {
        switch self {
        case .today:    "TabToday"
        case .schedule: "TabSchedule"
        case .library:  "TabLibrary"
        case .discover: "TabAdd"
        }
    }
}

// Native tab shell. On iOS 26 the system renders the floating Liquid Glass tab bar and the
// separated search island for a search-role tab.
struct MainTabView: View {
    @Environment(AppModel.self) private var appModel
    /// The launch in progress: the app emerges through the ident, so the launch tab's page-in
    /// only rises, and the tab bar waits for the emergence.
    @Environment(LaunchHandoff.self) private var launch: LaunchHandoff?
    @State private var selectedTab: AppTab = MainTabView.launchTab
    /// One navigation path per tab; Detail and its episode list push onto the active tab's path.
    @State private var paths: [AppTab: NavigationPath] = [:]
    /// An All-titles route requested from another tab, consumed by LibraryView on arrival.
    @State private var libraryRequest: LibraryView.AllTitlesRoute?
    /// Bumped when the Library tab is re-selected: All titles is an item destination, not a path
    /// entry, so clearing the path alone left it standing and the tap did nothing.
    @State private var libraryPops = 0
    /// The transition namespace every card registers its artwork in (`zoomSource(_:)`).
    ///
    /// Nothing consumes it today: Detail is a push again (see `detailDestinations` for the
    /// frames that retired the zoom). The sources are kept live because they are free, and a
    /// transition that fits a full page will want them.
    @Namespace private var zoom

    private func path(_ tab: AppTab) -> Binding<NavigationPath> {
        Binding(get: { paths[tab] ?? NavigationPath() }, set: { paths[tab] = $0 })
    }

    /// `-openTab today|schedule|library|discover` (DEBUG, like `-recapDemo`): open a scripted
    /// simulator run on a given tab for captures. `-openAllTitles 1` lives on `LibraryView`.
    private static var launchTab: AppTab {
        #if DEBUG
        switch UserDefaults.standard.string(forKey: "openTab") {
        case "schedule": return .schedule
        case "library": return .library
        case "discover", "search": return .discover
        default: return .today
        }
        #else
        return .today
        #endif
    }


    /// Re-selecting the active tab pops it to its root (system behaviour, made explicit).
    private var selection: Binding<AppTab> {
        Binding(get: { selectedTab }, set: { tab in
            if tab == selectedTab {
                paths[tab] = NavigationPath()
                if tab == .library { libraryPops += 1 }
            } else {
                selectedTab = tab
            }
        })
    }


    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: selection) {
                Tab(AppTab.today.titleKey, image: AppTab.today.icon, value: AppTab.today) {
                    NavigationStack(path: path(.today)) {
                        TodayView(onOpenDetail: openDetail,
                                  // The same route Library's own "See all" takes — a filtered
                                  // All titles — not a bare tab switch to the root, which left
                                  // "See all" meaning three things across two screens.
                                  onSeeAllWatching: {
                                      libraryRequest = .init(status: .watching)
                                      selectedTab = .library
                                  },
                                  // No status: Today's "N updates" counts `outNow`, which is any
                                  // status. Pinning Watching here made the count and the list
                                  // disagree the moment a Paused show aired.
                                  onViewAllUpdates: {
                                      libraryRequest = .init(status: nil, unwatchedOnly: true)
                                      selectedTab = .library
                                  },
                                  onOpenLibrary: { status in
                                      libraryRequest = .init(status: status)
                                      selectedTab = .library
                                  },
                                  onAddShow: { appModel.searchFieldRequested = true; selectedTab = .discover })
                            .detailDestinations(push: { push(.today, $0) })
                            .perfScreen("Today")
                    }
                    .tint(ThemeColor.interactive)
                    .pageInTransition(isActive: selectedTab == .today && appModel.surfaceReady, fadeIn: launch?.finished ?? true)
                    .launchTabBar(launch?.emerging ?? true)
                }
                Tab(AppTab.schedule.titleKey, image: AppTab.schedule.icon, value: AppTab.schedule) {
                    NavigationStack(path: path(.schedule)) {
                        ScheduleView(onOpenDetail: openEpisode, onAddShow: { appModel.searchFieldRequested = true; selectedTab = .discover })
                            .detailDestinations(push: { push(.schedule, $0) })
                            .perfScreen("Schedule")
                    }
                    .tint(ThemeColor.interactive)
                    .pageInTransition(isActive: selectedTab == .schedule && appModel.surfaceReady, fadeIn: launch?.finished ?? true)
                    .launchTabBar(launch?.emerging ?? true)
                }
                Tab(AppTab.library.titleKey, image: AppTab.library.icon, value: AppTab.library) {
                    NavigationStack(path: path(.library)) {
                        LibraryView(onOpenDetail: openDetail,
                                    onAddShow: { appModel.searchFieldRequested = true; selectedTab = .discover },
                                    requestedAll: $libraryRequest,
                                    popSignal: libraryPops)
                            .detailDestinations(push: { push(.library, $0) })
                            .perfScreen("Library")
                    }
                    .tint(ThemeColor.interactive)
                    .pageInTransition(isActive: selectedTab == .library && appModel.surfaceReady, fadeIn: launch?.finished ?? true)
                    .launchTabBar(launch?.emerging ?? true)
                }
                // An ORDINARY tab in the one tab pill, not the separated search island: the
                // field lives under the title on the screen itself (Apple Music's Search — user
                // reference, 24 Aug), which the search role's tab-bar morph did not allow.
                Tab(AppTab.discover.titleKey, systemImage: "magnifyingglass", value: AppTab.discover) {
                    NavigationStack(path: path(.discover)) {
                        DiscoverView(onOpenDetail: openDetail)
                            .detailDestinations(push: { push(.discover, $0) })
                            .perfScreen("Search")
                    }
                    .tint(ThemeColor.interactive)
                    .pageInTransition(isActive: selectedTab == .discover && appModel.surfaceReady, fadeIn: launch?.finished ?? true)
                    .launchTabBar(launch?.emerging ?? true)
                }
            }
            // The bar's selected item is state, so it alone is amber; every stack inside re-tints
            // to ink (above) so the amber never reaches a back button or an alert.
            .tint(ThemeColor.accent)
            // The bar gets out of the way of a long read the way Music's and Photos' do, and
            // comes back on the first upward scroll.
            .chromeTabBarMinimizeOnScroll()
            // The receipt LANE (5 Sep): a removal, a move, an add, a notice or a failure as the
            // bar's own accessory — the lane Music's mini player lives in. Below 26.1 the
            // `ToastHost` draws the same lane attached above the bar.
            .chromeBottomAccessory(isEnabled: appModel.laneItem != nil) {
                if let item = appModel.laneItem {
                    ReceiptLane(item: item) {
                        if case .undo(let u) = item { appModel.undoTapped(u) }
                    }
                }
            }
            .environment(\.zoomNamespace, zoom)
            // No haptic on a tab switch (review, 5 Sep): Music, TV and the App Store are silent
            // on the most frequent gesture in the app; a haptic is a signature for a WRITE.
            // A tapped episode alert opens its show — on Today, above whatever was there.
            .onChange(of: appModel.pendingOpen, initial: true) { _, id in
                guard let id else { return }
                appModel.pendingOpen = nil
                selectedTab = .today
                paths[.today] = NavigationPath([DetailRoute(id: id, zoomID: "alert/\(id)")])
            }
            .task {
                KeyboardMotion.install()
                KeyboardWarmup.install()
                // One freshness source for every stale strip and Profile's sync line.
                SyncCenter.shared.signals = {
                    .init(lastLoadedAt: appModel.lastLoadedAt, loading: appModel.loading)
                }
                SyncCenter.shared.startMonitoring()
                #if DEBUG
                ToastDemo.arm(appModel)
                #endif
            }

            // Undo / sync / error toasts float above the tab bar, over whatever is pushed.
            //
            // 22 pt is the tab bar's OWN horizontal margin; the shipped 17 disagreed with it by
            // 5 pt, which is exactly the kind of gap that reads as "assembled" rather than
            // "designed".
            //
            // The BOTTOM inset is measured from the window, not from the bar — this ZStack is
            // aligned to the window's bottom edge, so a 12-pt pad put the toast at 858–935 against
            // a tab pill at 873–935: it covered the tab bar outright on Today and Library, and on
            // Search it covered the field with the user's own query still in it, plus the
            // tab-return and dismiss controls. `toastClearance` was defined for exactly this and
            // referenced nowhere. Measured after the fix: the toast lands at 815–856 pt against a
            // pill whose top edge is 875, on all four tabs.
            ToastHost()
                .padding(.horizontal, 22)
                .padding(.bottom, ThemeMetrics.toastClearance)
        }
        // The text-input stack, loaded while the person is still reading Today (`KeyboardWarmup`):
        // only if they have not moved on — a tab switched or a page pushed means the moment has
        // passed, and the first field will pay for itself.
        .task(id: appModel.surfaceReady) {
            guard appModel.surfaceReady else { return }
            try? await Task.sleep(for: KeyboardWarmup.delay)
            guard !Task.isCancelled, selectedTab == MainTabView.launchTab,
                  (paths[selectedTab] ?? NavigationPath()).isEmpty else { return }
            // Not over a banner or a lane: the unseen keyboard's safe-area inset would move them.
            KeyboardWarmup.warm(allowed: appModel.laneItem == nil && SyncCenter.shared.failedChanges.isEmpty)
        }
    }

    private func push(_ tab: AppTab, _ value: any Hashable) {
        var p = paths[tab] ?? NavigationPath()
        p.append(value)
        paths[tab] = p
    }

    /// Navigation is silent (board 11): no haptic on open.
    private func openDetail(_ id: String, zoomID: String) {
        push(selectedTab, DetailRoute(id: id, zoomID: zoomID))
    }

    /// Schedule variant: lands on a specific season + episode. ONE push — the episodes are on the
    /// show page (6 Sep), which scrolls to the row (`FranchiseDetailView.landOnFocus`); it used to
    /// append the season screen in the same transaction.
    private func openEpisode(_ id: String, zoomID: String, focus: EpisodeFocus?) {
        push(selectedTab, DetailRoute(id: id, zoomID: zoomID, focus: focus))
    }
}

private extension View {
    /// The floating tab bar is composited above the launch ident's overlay (it is the system's
    /// layer, not the content's), so it would show on the bare canvas during the ident. Hidden
    /// until the app emerges; the system slides it in with the content.
    func launchTabBar(_ ready: Bool) -> some View {
        toolbarVisibility(ready ? .visible : .hidden, for: .tabBar)
    }

    /// The two destinations every tab can reach: a franchise, and a season's episode list.
    ///
    /// Detail is a PUSH — the system slide, the transition Apple TV, Disney+ and Crunchyroll open
    /// a show with. It was `.zoom` from the tapped artwork (2 Sep) and the frames say why that is
    /// wrong here: the zoom scales the WHOLE destination into the source's frame, so for its
    /// first 150 ms the show page was a miniature of itself — billboard, pill, title and amber
    /// capsule squeezed into a 60×90 poster — inflating ("the details opening motion is just
    /// trash", user, 3 Sep). The HIG reserves zoom for a destination that IS the source, larger
    /// (a photo, a card's own art); a page with a landscape billboard cropped from a different
    /// picture is not that. The `zoomSource` registrations stay: they cost nothing and are the
    /// hook if a transition that fits ever arrives.
    func detailDestinations(push: @escaping (FranchiseDetailView.DetailPush) -> Void) -> some View {
        self
            .navigationDestination(for: DetailRoute.self) { route in
                FranchiseDetailView(franchiseId: route.id, focus: route.focus, push: push)
                    .pushedScreenChrome()
                    .perfScreen("Detail")
            }
            .navigationDestination(for: FranchiseDetailView.DetailPush.self) { p in
                Group {
                    switch p {
                    case .episodes(let franchiseId, let mediaId, let focusEpisode):
                        SeasonEpisodesView(franchiseId: franchiseId, mediaId: mediaId, focusEpisode: focusEpisode)
                            .perfScreen("Episodes")
                    case .history(let franchiseId):
                        WatchHistoryView(franchiseId: franchiseId)
                            .perfScreen("History")
                    case .detail(let franchiseId):
                        // A related title, opened from a show page: the same page, one deeper.
                        FranchiseDetailView(franchiseId: franchiseId, push: push)
                            .perfScreen("Detail")
                    }
                }
                // A pushed screen is still inside the TabView, so the floating pill is still over
                // it — but `scrollEdgeChrome` was applied on tab ROOTS only, so Detail's season and
                // episode lists rendered whole rows at full opacity under and beside the bar, with
                // no `bottomUnderfill` for its glass to refract. The treatment belongs to the
                // pushed-screen scaffold, here, not to six per-screen opt-ins.
                .pushedScreenChrome()
            }
    }
}
