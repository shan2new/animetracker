import SwiftUI

// Library (spec board 05): a calm root with ONE art moment and everything else quiet, and
// "All titles" — the instrument (search, sort, filter, view) behind one row. Urgency lives on
// Today, never here.
//
// Fix round 2. What the adversarial panel drew blood on, and what this is:
//
//  * **The A–Z index rail failed on every axis it was measured** — 11-pt hard-coded type that never
//    scaled, `textDisabled` (3.6:1) on text, 15-pt bands in a 225-pt column floating in the middle
//    of the screen, letters sitting ON the third poster column, `accessibilityHidden(true)` with no
//    substitute, and a 300 ms haptic floor that made an A→W drag produce two taps. See `indexRail`.
//  * **The WATCHING shelf answered "what do I owe" with a release year.** Three consecutive rows
//    read "Anime · 2013" / "TV · 2024" / "Anime · 2019" because `standing()` refused to speak
//    without a current part. See `LibraryRowFacts.standing`.
//  * **One show, three statuses.** The poster wall and the list derived their caption from two
//    different functions and disagreed, and nothing anywhere said a rewatch was in progress.
//    `LibraryRowFacts.catalogue(compact:)` is now the single source for both. See `gridCaption`.
//  * **Accent was the caption colour.** Every visible caption on the root shelf was amber, none of
//    them an action. `ReturnFact.soon` decides it once, for the shelf and the catalogue alike.
//  * **"All titles" was a filled rounded rectangle under a large title** — the same silhouette as
//    the search field it opens. It is a hairline row on the canvas now. See `allTitlesRow`.
//  * **The root hid its navigation bar** and drew "Library" as scrolling content, so the app had
//    three header grammars across three tab roots. It is a real inline title now — Schedule's
//    model, on every root.
//  * **"Unwatched only" could contradict "Status"** and did not say unwatched *what*. It is its
//    own axis now ("Has unwatched episodes"), composed with Status, and its predicate is the set
//    Today counts. Sort gained "Recently added" and a direction. See `filtered()`.
//
// Round 3 (audit): the root and All titles each computed their sections several times per render
// — `sections` from the wash and every loop, `results` from eight sites — so both are resolved
// ONCE at the top of `body` and passed down. Every string moved to `Copy.Library`.
private enum LibraryRootTab: String, Hashable, CaseIterable {
    case overview
    case watching
    case planned
    case watched

    var status: WatchStatus? {
        switch self {
        case .overview: nil
        case .watching: .watching
        case .planned: .planned
        case .watched: .completed
        }
    }

    var section: LibrarySection? {
        switch self {
        case .overview: nil
        case .watching: .watching
        case .planned: .planned
        case .watched: .finished
        }
    }

    var label: String {
        switch self {
        case .overview: Copy.Library.overview
        case .watching: Copy.Status(.watching)
        case .planned: Copy.Status(.planned)
        case .watched: Copy.Status(.completed)
        }
    }

    func count(_ counts: LibraryTabCounts) -> Int? {
        switch self {
        case .overview: nil
        case .watching: counts.watching
        case .planned: counts.planned
        case .watched: counts.watched
        }
    }

    func title(_ counts: LibraryTabCounts) -> String {
        guard let count = count(counts) else { return label }
        return "\(label) \(count)"
    }

    var accessibilityHint: String {
        guard let status else { return Copy.Library.overviewTabHint }
        return Copy.Library.statusTabHint(status)
    }

    var emptyCopy: EmptyStateCopy? {
        switch self {
        case .overview: nil
        case .watching: Copy.Library.noWatchingTab
        case .planned: Copy.Library.noPlannedTab
        case .watched: Copy.Library.noWatchedTab
        }
    }
}

private struct LibraryTabCounts {
    let watching: Int
    let planned: Int
    let watched: Int
}

/// One pass over the account for both tab counts and tab membership. Paused and Dropped remain
/// available in All titles; the selected reference intentionally promotes the three everyday lists.
private struct LibraryTabSnapshot {
    let watching: [Franchise]
    let planned: [Franchise]
    let watched: [Franchise]

    init(library: [Franchise]) {
        var watching: [Franchise] = []
        var planned: [Franchise] = []
        var watched: [Franchise] = []
        for franchise in library {
            switch franchise.effectiveStatus {
            case .watching: watching.append(franchise)
            case .planned: planned.append(franchise)
            case .completed: watched.append(franchise)
            case .paused, .dropped: break
            }
        }
        self.watching = watching
        self.planned = planned
        self.watched = watched
    }

    var counts: LibraryTabCounts {
        LibraryTabCounts(watching: watching.count, planned: planned.count, watched: watched.count)
    }

    func items(for tab: LibraryRootTab) -> [Franchise] {
        switch tab {
        case .overview: []
        case .watching: watching
        case .planned: planned
        case .watched: watched
        }
    }
}

struct LibraryView: View {
    @Environment(AppModel.self) private var appModel
    let onOpenDetail: (_ franchiseId: String, _ zoomID: String) -> Void
    /// Where shows are added. Today and Schedule already take this; the Library's empty state
    /// printed the same `Add a show` label with nothing behind it.
    var onAddShow: () -> Void = {}

    @State private var all: AllTitlesRoute?
    /// The title at the centre of the art-first carousel. Kept as an id so live progress updates
    /// can replace a `Franchise` value without resetting the user's place.
    @State private var focusedHeroID: String?
    /// The selected reference treats Overview and the three everyday statuses as peer tabs.
    @State private var selectedTab: LibraryRootTab = .overview
    /// A route another screen asked for ("View all N updates", a Profile stat); consumed once.
    @Binding var requestedAll: AllTitlesRoute?
    /// True while the user's finger owns a pull. The system's own indicator is then the only
    /// spinner on screen — see `L-17` above.
    @State private var pullDriving = false
    /// The scroll view's own height, so a state that owns the whole surface can be centred in it.
    @State private var contentHeight: CGFloat = 0

    /// Where a `See all` lands. Two independent axes, because the root's buckets are not all
    /// statuses: `Returning` and `Announced` are facts about a show's future, not list states.
    struct AllTitlesRoute: Hashable, Identifiable {
        var status: WatchStatus?
        var returning: ReturnScope?
        var unwatchedOnly: Bool = false
        var id: String { "\(status?.rawValue ?? "-")/\(returning?.rawValue ?? "-")/\(unwatchedOnly)" }
    }

    var body: some View {
        // ONE pass over the shelves per render. `sections` used to be recomputed by the wash and
        // by the section loop, and each pass ran `ReturnFact.of` twice per title.
        let sections = rootSections()
        let tabSnapshot = LibraryTabSnapshot(library: appModel.library)
        // `watchingShelf` also contains titles that are caught up and merely waiting. The hero is
        // an instruction to continue, so only a title with a real resume part may enter it.
        let heroItems = appModel.watchingShelf.filter { $0.resumePart != nil }
        let selectedStatusItems = tabSnapshot.items(for: selectedTab)
        let ambientArtwork = washArtwork(sections, heroItems: heroItems,
                                         selectedItems: selectedStatusItems)
        return ZStack(alignment: .top) {
            ThemeColor.canvas.ignoresSafeArea()
            // The wash runs to the very top of the screen, status bar included; the soft top veil
            // only settles it under the title. With no artwork in the library there is nothing for
            // it to be ABOUT, so first run gets the app's own colour.
            ArtBackdrop(url: ambientArtwork,
                        tint: ambientArtwork == nil ? ThemeColor.accent : nil,
                        height: LibraryRootMetrics.backdropHeight,
                        intensity: LibraryRootMetrics.backdropIntensity)
                .ignoresSafeArea(edges: .top)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // The refresh indicator and the stale strip, composed by the shared modifier
                    // that arbitrates them against `.refreshable`'s own spinner. The screen TITLE
                    // is not part of this stack: it is a real `navigationTitle`, so the tab roots
                    // stop having three header grammars (see `body`'s toolbar).
                    Color.clear.frame(height: 0)
                        .freshness(.catalogue, appModel: appModel, pullDriving: pullDriving)
                        .padding(.horizontal, ThemeMetrics.gutter)

                    if appModel.sectionFailed {
                        InlineNotice(Copy.Notice.library) { Task { await appModel.reload() } }
                            .padding(.horizontal, ThemeMetrics.gutter).padding(.top, ThemeSpace.x3)
                    }

                    LibraryRootTabs(selection: $selectedTab, counts: tabSnapshot.counts)
                        .padding(.horizontal, ThemeMetrics.gutter)
                        .padding(.top, ThemeSpace.x1)

                    SkeletonGate(isLoading: appModel.loading && appModel.library.isEmpty) {
                        skeleton
                    } content: {
                        if appModel.library.isEmpty {
                            // Centred in the content area, not pinned to the top of it: the error
                            // card sat above ~1,000 pt of black while the identical card on Today
                            // was centred.
                            // `ambient: false`: this screen already owns an ambient wash, and the
                            // plate's own radial bloom stacked on it met the canvas in a hard
                            // full-width step (measured: 10 -> 35 in one pixel row at y≈302 pt).
                            // One wash per screen, and on this screen it is the screen's.
                            EmptyState(appModel.emptyStateCopy, prominence: .major,
                                       primary: emptyStateAction, ambient: false)
                                .padding(.horizontal, ThemeMetrics.gutter)
                                .centredState(contentH: contentHeight)
                        } else {
                            if selectedTab == .overview {
                                root(sections, heroItems: heroItems)
                            } else if let emptyCopy = selectedTab.emptyCopy {
                                LibraryStatusContent(
                                    items: statusItems(selectedStatusItems, tab: selectedTab),
                                    emptyCopy: emptyCopy,
                                    onOpen: { franchise in
                                        onOpenDetail(franchise.id, "lib/\(franchise.id)")
                                    })
                            }
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
            // A scroll-content MARGIN, not padding inside the stack: padding under a stack that is
            // shorter than the viewport changes no layout at all, which is exactly the case a short
            // library is in when it comes to rest inside the bottom ramp.
            .tabBarContentMargin()
            .onScrollPhaseChange { _, phase in
                pullDriving = (phase == .tracking || phase == .interacting)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            .previouslyRefreshable { await appModel.reload() }
        }
        // BOTTOM only. The top edge belongs to a real navigation bar: the screen used to hide the
        // bar and draw "Library" as scrolling content, so nothing named the screen once you had
        // scrolled, and the app had three different header grammars across its three tab roots.
        // The bottom edge is ours; the TOP is the bar's own veil (`rootBarVeil`) — the same
        // gradient the tab bar's edge carries, "relayed upwards" to the title (user, 24 Aug), drawn
        // from the very top of the screen — over the wash the navigation container paints
        // (`rootWash`). With no artwork in the library there is nothing for the wash to be ABOUT,
        // so first run gets the app's own colour: the first frame a new user sees should carry the
        // product's identity rather than none.
        .scrollEdgeChromeBody(top: true, bottom: true, softTop: true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .scrollEdgeEffectHidden(true, for: .all)
        .navigationTitle(Copy.Library.title)
        // Inline on every root — Schedule's model. A large title collapses on the first scroll and
        // moves the top safe area ~50 pt mid-flight; an inline one holds still over the wash.
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(Copy.titles(appModel.library.count)) {
                    all = AllTitlesRoute()
                }
                // Keep this as the reference's quiet count/action, not a second glass island
                // competing with the tab bar.
                .buttonStyle(.plain)
                .type(ThemeType.listAction)
                .foregroundStyle(ThemeColor.textSecondary)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel(Copy.Library.allTitlesAccessibility(appModel.library.count))
                .accessibilityHint(Copy.Library.allTitlesHint)
            }
            // On iOS 27 the capsule belongs to the toolbar item, not to the ButtonStyle. This is
            // the same treatment Profile uses for its plain text action.
            .sharedBackgroundVisibility(.hidden)
        }
        .navigationDestination(item: $all) { route in
            LibraryAllView(initialStatus: route.status, initialReturning: route.returning,
                           initialUnwatchedOnly: route.unwatchedOnly,
                           onOpenDetail: onOpenDetail, onAddShow: onAddShow)
        }
        .onAppear {
            reconcileHeroSelection(heroItems)
            #if DEBUG
            // `-openAllTitles 1` (DEBUG, like `-recapDemo`): open straight onto All titles.
            if UserDefaults.standard.bool(forKey: "openAllTitles"), all == nil { all = AllTitlesRoute() }
            // Exact-device visual QA can open any tab without synthetic HID input.
            if let raw = UserDefaults.standard.string(forKey: "libraryTab"),
               let tab = LibraryRootTab(rawValue: raw) {
                selectedTab = tab
            }
            #endif
        }
        .onChange(of: heroItems.map(\.id)) { _, _ in reconcileHeroSelection(heroItems) }
        .onChange(of: requestedAll, initial: true) { _, route in
            guard let route else { return }
            all = route
            requestedAll = nil
        }
    }

    /// The empty state's one action, and it is always a live one.
    private var emptyStateAction: () -> Void {
        appModel.loadError ? { Task { await appModel.reload() } } : onAddShow
    }

    /// The wash is taken from the first show on the first shelf — the same artwork the eye lands
    /// on first, so the room is lit by the thing you are looking at.
    private func washArtwork(_ sections: [RootSection], heroItems: [Franchise],
                             selectedItems: [Franchise]) -> String? {
        let overviewFranchise = heroItems.first(where: { $0.id == focusedHeroID })
            ?? heroItems.first
            ?? sections.first?.items.first
        let franchise = selectedItems.first ?? overviewFranchise ?? appModel.library.first
        guard let franchise else { return nil }
        return [franchise.resumePart?.banner, franchise.banner,
                franchise.resumePart?.cover, franchise.cover]
            .compactMap { $0 }
            .first(where: { !$0.isEmpty })
    }

    private func reconcileHeroSelection(_ items: [Franchise]) {
        guard !items.isEmpty else { focusedHeroID = nil; return }
        if focusedHeroID == nil || !items.contains(where: { $0.id == focusedHeroID }) {
            focusedHeroID = items[0].id
        }
    }

    // MARK: - Root

    private func root(_ sections: [RootSection], heroItems: [Franchise]) -> some View {
        // Returning is the strongest supporting shelf. If an account has none, keep the root
        // useful with the first non-Watching shelf instead of leaving a paid user's library blank.
        let supporting = sections.first(where: { $0.key == .returning })
            ?? sections.first(where: { $0.key != .watching })
            ?? (heroItems.isEmpty ? sections.first : nil)

        return VStack(alignment: .leading, spacing: ThemeMetrics.sectionGap) {
            if !heroItems.isEmpty {
                LibraryWatchingSpotlight(items: heroItems, focusedID: $focusedHeroID,
                                         onOpen: onOpenDetail)
            }

            if let supporting {
                LibraryLandscapeShelf(title: supporting.key.label,
                                      items: supportingItems(supporting)) {
                    all = route(for: supporting.key)
                } onOpen: { franchise in
                    onOpenDetail(franchise.id, "lib/\(franchise.id)")
                }
            }
        }
        // The artwork starts immediately below the inline bar. The old 20-pt lead-in plus the
        // spotlight's own 20-pt gap left the first third looking like the screen we replaced.
        .padding(.top, LibraryRootMetrics.contentTopPadding)
    }

    private func supportingItems(_ section: RootSection) -> [LibraryLandscapeItem] {
        section.items.prefix(LibraryRootMetrics.supportingPreviewCount).map { franchise in
            let facts = LibraryRowFacts.root(franchise, section: section.key, appModel: appModel)
            return LibraryLandscapeItem(franchise: franchise, caption: facts.lead ?? facts.meta)
        }
    }

    private func statusItems(_ franchises: [Franchise], tab: LibraryRootTab) -> [LibraryLandscapeItem] {
        guard let section = tab.section else { return [] }
        return franchises.map { franchise in
            let facts = LibraryRowFacts.root(franchise, section: section, appModel: appModel)
            return LibraryLandscapeItem(franchise: franchise, caption: facts.lead ?? facts.meta)
        }
    }

    struct RootSection: Identifiable {
        let key: LibrarySection
        let items: [Franchise]
        var id: Int { key.id }
    }

    /// `AppModel.libraryShelves` stays the source of truth for membership and order; the only thing
    /// done here is splitting `comingBack` in two, because a heading that says RETURNING may not
    /// contain a show whose own detail screen says "Finished" and "No date announced".
    ///
    /// A function, not a computed property, so a call site cannot read it twice by accident: it
    /// is resolved once in `body` and handed down.
    private func rootSections() -> [RootSection] {
        var out: [RootSection] = []
        for shelf in appModel.libraryShelves {
            switch shelf.shelf {
            case .comingBack:
                // Already sorted soonest-first by `AppModel`, so the dated ones lead and the
                // partition preserves that order inside each half. One `ReturnFact` per title.
                var dated: [Franchise] = [], undated: [Franchise] = []
                for f in shelf.franchises {
                    if ReturnFact.of(f, appModel: appModel).dated { dated.append(f) } else { undated.append(f) }
                }
                if !dated.isEmpty { out.append(RootSection(key: .returning, items: dated)) }
                if !undated.isEmpty { out.append(RootSection(key: .announced, items: undated)) }
            case .watching: out.append(RootSection(key: .watching, items: shelf.franchises))
            case .planned:  out.append(RootSection(key: .planned, items: shelf.franchises))
            case .finished: out.append(RootSection(key: .finished, items: shelf.franchises))
            }
        }
        return out.sorted { $0.key.rank < $1.key.rank }
    }

    /// Every section now has an honest destination, including the two that are not statuses.
    private func route(for key: LibrarySection) -> AllTitlesRoute {
        switch key {
        case .returning: return AllTitlesRoute(returning: .dated)
        case .announced: return AllTitlesRoute(returning: .undated)
        case .watching:  return AllTitlesRoute(status: .watching)
        case .planned:   return AllTitlesRoute(status: .planned)
        case .finished:  return AllTitlesRoute(status: .completed)
        }
    }

    // MARK: - Loading

    /// The loading frame is the selected composition itself: one cover-flow hero, its compact
    /// progress block, then two landscape cards. The handoff therefore changes content, not shape.
    private var skeleton: some View {
        VStack(alignment: .leading, spacing: ThemeMetrics.sectionGap) {
            VStack(alignment: .leading, spacing: ThemeSpace.x5) {
                SkeletonLine(width: LibraryRootMetrics.skeletonHeroHeading,
                             height: LibraryRootMetrics.skeletonEyebrowHeight)
                    .padding(.horizontal, ThemeMetrics.gutter)
                ZStack {
                    SkeletonPoster(width: LibraryRootMetrics.heroWidth,
                                   height: LibraryRootMetrics.heroHeight,
                                   radius: LibraryRootMetrics.heroRadius)
                        .scaleEffect(LibraryRootMetrics.sideScale)
                        .offset(x: -LibraryRootMetrics.sideOffset)
                        .opacity(LibraryRootMetrics.sideOpacity)
                    SkeletonPoster(width: LibraryRootMetrics.heroWidth,
                                   height: LibraryRootMetrics.heroHeight,
                                   radius: LibraryRootMetrics.heroRadius)
                        .scaleEffect(LibraryRootMetrics.sideScale)
                        .offset(x: LibraryRootMetrics.sideOffset)
                        .opacity(LibraryRootMetrics.sideOpacity)
                    SkeletonPoster(width: LibraryRootMetrics.heroWidth,
                                   height: LibraryRootMetrics.heroHeight,
                                   radius: LibraryRootMetrics.heroRadius)
                }
                .frame(maxWidth: .infinity)
                .frame(height: LibraryRootMetrics.heroStageHeight)

                VStack(alignment: .leading, spacing: ThemeSpace.x2) {
                    SkeletonLine(width: LibraryRootMetrics.skeletonHeroTitle,
                                 height: LibraryRootMetrics.skeletonTitleHeight)
                    SkeletonLine(width: LibraryRootMetrics.skeletonHeroMeta,
                                 height: LibraryRootMetrics.skeletonMetaHeight)
                    SkeletonLine(height: LibraryRootMetrics.skeletonProgressHeight)
                }
                .frame(width: LibraryRootMetrics.heroInfoWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
            }

            VStack(alignment: .leading, spacing: ThemeSpace.x3) {
                HStack {
                    SkeletonLine(width: LibraryRootMetrics.skeletonShelfHeading,
                                 height: LibraryRootMetrics.skeletonHeadingHeight)
                    Spacer()
                    SkeletonLine(width: LibraryRootMetrics.skeletonShelfAction,
                                 height: LibraryRootMetrics.skeletonMetaHeight)
                }
                .padding(.horizontal, ThemeMetrics.gutter)
                HStack(spacing: ThemeMetrics.shelfGap) {
                    ForEach(0..<2, id: \.self) { _ in
                        VStack(alignment: .leading, spacing: ThemeSpace.x2) {
                            SkeletonPoster(width: LibraryRootMetrics.landscapeSkeletonWidth,
                                           height: LibraryRootMetrics.landscapeHeight,
                                           radius: LibraryRootMetrics.landscapeRadius)
                            SkeletonLine(width: LibraryRootMetrics.landscapeSkeletonWidth * 0.72,
                                         height: LibraryRootMetrics.skeletonShelfTitleHeight)
                            SkeletonLine(width: LibraryRootMetrics.landscapeSkeletonWidth * 0.55,
                                         height: LibraryRootMetrics.skeletonMetaHeight)
                        }
                    }
                }
                .padding(.horizontal, ThemeMetrics.gutter)
            }
        }
        .padding(.top, LibraryRootMetrics.contentTopPadding)
    }

}

// MARK: - Art-first Library root

/// The geometry of the selected iPhone reference, kept in one place so the real content and its
/// loading frame cannot drift. These are composition measurements, not reusable design tokens.
private enum LibraryRootMetrics {
    /// The visible rail is compact; each button still owns the full 44-pt touch target.
    static let tabHeight: CGFloat = 44
    static let tabIndicatorWidth: CGFloat = 22
    static let tabIndicatorHeight: CGFloat = 2
    /// The content needs a real breath after the index; the copied rail put a section title almost
    /// directly on its rule while leaving the navigation area comparatively empty.
    static let contentTopPadding: CGFloat = 20
    /// Library carries more artwork than the list roots, so its wash stays visible far enough to
    /// join the hero instead of ending as a grey navigation-band stain.
    static let backdropHeight: CGFloat = 380
    static let backdropIntensity: Double = 0.54
    static let heroWidth: CGFloat = 192
    static let heroHeight: CGFloat = 288
    static let heroRadius: CGFloat = 18
    static let heroStageHeight: CGFloat = 296
    /// Details align to the selected cover's edges. The wider block made the title and progress
    /// look detached from the art they described.
    static let heroInfoWidth: CGFloat = heroWidth
    // Leaves the same ~10-pt outer breathing room as the selected reference while the centre
    // card occludes the inner portion of each neighbour.
    static let sideOffset: CGFloat = 100
    static let sideScale: CGFloat = 0.88
    static let sideOpacity: Double = 0.34
    static let sideTilt: Double = 3
    static let swipeThreshold: CGFloat = 38
    static let progressTrackHeight: CGFloat = 3
    static let progressMinimumFill: CGFloat = 3
    static let landscapeHeight: CGFloat = 104
    static let landscapeRadius: CGFloat = 13
    static let landscapeDecodePixel: CGFloat = 560
    static let supportingPreviewCount = 6
    static let landscapeSkeletonWidth: CGFloat = 174

    static let statusFeatureHeight: CGFloat = 176
    static let statusFeatureRadius: CGFloat = 18
    static let statusFeatureDecodePixel: CGFloat = 920
    static let statusPosterWidth: CGFloat = 64
    static let statusPosterHeight: CGFloat = 96
    static let statusPosterRadius: CGFloat = 10
    static let statusRowMinHeight: CGFloat = 112
    static let statusEmptyTopPadding: CGFloat = 72

    static let skeletonHeroHeading: CGFloat = 108
    static let skeletonHeroTitle: CGFloat = 154
    static let skeletonHeroMeta: CGFloat = 196
    static let skeletonShelfHeading: CGFloat = 92
    static let skeletonShelfAction: CGFloat = 54
    static let skeletonEyebrowHeight: CGFloat = 10
    static let skeletonHeadingHeight: CGFloat = 19
    static let skeletonTitleHeight: CGFloat = 18
    static let skeletonMetaHeight: CGFloat = 12
    static let skeletonProgressHeight: CGFloat = 3
    static let skeletonShelfTitleHeight: CGFloat = 14
}

/// A quiet editorial index rather than a dashboard rail. Counts are tertiary information, not part
/// of the label's visual weight, and the selected state gets one short mark instead of a full-width
/// spreadsheet rule. Every label still owns a full-height hit target.
private struct LibraryRootTabs: View {
    @Binding var selection: LibraryRootTab
    let counts: LibraryTabCounts

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(LibraryRootTab.allCases, id: \.self) { tab in
                let selected = selection == tab
                Button {
                    withAnimation(ThemeMotion.pick(ThemeMotion.uiSettle, reduceMotion: reduceMotion)) {
                        selection = tab
                    }
                } label: {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        HStack(alignment: .firstTextBaseline, spacing: ThemeSpace.x1) {
                            Text(tab.label)
                                .font(.system(.subheadline,
                                              weight: selected ? .semibold : .regular))
                                .foregroundStyle(selected ? ThemeColor.accent
                                                          : ThemeColor.textSecondary)
                            if let count = tab.count(counts) {
                                Text(count, format: .number)
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(selected ? ThemeColor.accent.opacity(0.78)
                                                              : ThemeColor.textDisabled)
                                    .monospacedDigit()
                            }
                        }
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .frame(maxWidth: .infinity)

                        Spacer(minLength: ThemeSpace.x2)
                        Capsule()
                            .fill(selected ? ThemeColor.accent : .clear)
                            .frame(width: LibraryRootMetrics.tabIndicatorWidth,
                                   height: LibraryRootMetrics.tabIndicatorHeight)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: LibraryRootMetrics.tabHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title(counts))
                .accessibilityHint(tab.accessibilityHint)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// The selected direction's single art moment: the active title at full weight, adjacent titles
/// dimmed behind it, with the current progress directly underneath. Progress mutation belongs to
/// Today and Schedule; repeating that action here would spend the root's most valuable space on a
/// third copy of the same control.
private struct LibraryWatchingSpotlight: View {
    let items: [Franchise]
    @Binding var focusedID: String?
    let onOpen: (_ franchiseId: String, _ zoomID: String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    private var currentIndex: Int? {
        guard !items.isEmpty else { return nil }
        return items.firstIndex(where: { $0.id == focusedID }) ?? 0
    }

    private var current: Franchise? { currentIndex.map { items[$0] } }

    private func neighbour(_ offset: Int) -> Franchise? {
        guard let index = currentIndex, items.count > 1 else { return nil }
        // With two titles, one supporting card is enough; mirroring it on both sides looks like a
        // duplicate library entry. With three or more the carousel wraps naturally.
        if items.count == 2, offset < 0 { return nil }
        return items[(index + offset + items.count) % items.count]
    }

    var body: some View {
        if let franchise = current, let part = franchise.resumePart {
            VStack(alignment: .leading, spacing: 0) {
                Text(Copy.Library.continueWatchingEyebrow)
                    .type(ThemeType.sectionLabel)
                    .foregroundStyle(ThemeColor.textTertiary)
                    .padding(.horizontal, ThemeMetrics.gutter)
                    .padding(.bottom, ThemeSpace.x3)

                if typeSize.isAccessibilitySize {
                    accessibleArtwork(franchise)
                } else {
                    coverFlow(franchise)
                }

                LibraryHeroDetails(franchise: franchise, part: part)
                    .frame(width: typeSize.isAccessibilitySize ? nil : LibraryRootMetrics.heroInfoWidth,
                           alignment: .leading)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, typeSize.isAccessibilitySize ? ThemeMetrics.gutter : 0)
                    .padding(.top, ThemeSpace.x4)
            }
        }
    }

    private func coverFlow(_ franchise: Franchise) -> some View {
        ZStack {
            if let previous = neighbour(-1) {
                sideArtwork(previous, direction: -1)
            }
            if let next = neighbour(1) {
                sideArtwork(next, direction: 1)
            }
            LibraryHeroArtwork(franchise: franchise, prominent: true) {
                onOpen(franchise.id, "lib-hero/\(franchise.id)")
            }
            .zIndex(2)
        }
        .frame(maxWidth: .infinity)
        .frame(height: LibraryRootMetrics.heroStageHeight)
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: ThemeSpace.x3)
                .onEnded { value in
                    if value.translation.width < -LibraryRootMetrics.swipeThreshold { step(1) }
                    if value.translation.width > LibraryRootMetrics.swipeThreshold { step(-1) }
                }
        )
    }

    private func accessibleArtwork(_ franchise: Franchise) -> some View {
        LibraryHeroArtwork(franchise: franchise, prominent: true) {
            onOpen(franchise.id, "lib-hero/\(franchise.id)")
        }
        .frame(maxWidth: .infinity)
    }

    private func sideArtwork(_ franchise: Franchise, direction: CGFloat) -> some View {
        LibraryHeroArtwork(franchise: franchise, prominent: false) {
            select(franchise.id)
        }
        .scaleEffect(LibraryRootMetrics.sideScale)
        .rotationEffect(.degrees(Double(direction) * LibraryRootMetrics.sideTilt))
        .offset(x: direction * LibraryRootMetrics.sideOffset)
        .saturation(0.72)
        .brightness(-0.06)
        .opacity(LibraryRootMetrics.sideOpacity)
        .zIndex(1)
        .accessibilityHint(Copy.Library.focusTitleHint)
    }

    private func step(_ offset: Int) {
        guard let index = currentIndex, items.count > 1 else { return }
        let destination = (index + offset + items.count) % items.count
        select(items[destination].id)
    }

    private func select(_ id: String) {
        withAnimation(ThemeMotion.pick(ThemeMotion.uiSettle, reduceMotion: reduceMotion)) {
            focusedID = id
        }
    }
}

private struct LibraryHeroArtwork: View {
    let franchise: Franchise
    let prominent: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            PosterSlot(url: franchise.resumePart?.cover ?? franchise.cover,
                       width: LibraryRootMetrics.heroWidth,
                       height: LibraryRootMetrics.heroHeight,
                       radius: LibraryRootMetrics.heroRadius,
                       shadow: prominent ? .artHero : .art)
                .zoomSource("lib-hero/\(franchise.id)")
        }
        .buttonStyle(OverArtPressStyle())
        .accessibilityLabel(franchise.title)
        .accessibilityHint(prominent ? Copy.Accessibility.opensTheShowHint : Copy.Library.focusTitleHint)
    }
}

private struct LibraryHeroDetails: View {
    let franchise: Franchise
    let part: FranchisePart

    private var total: Int? {
        let known = max(part.totalEpisodes, part.airedEpisodes)
        return known > 0 ? known : nil
    }

    private var nextEpisode: Int { part.progress + 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: ThemeSpace.x2) {
            Text(franchise.displayTitle)
                .type(ThemeType.showTitleL)
                .foregroundStyle(ThemeColor.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.82)

            if let total {
                Text(Copy.Library.partProgress(part.label, watched: part.progress, total: total))
                    .type(ThemeType.heroMeta)
                    .foregroundStyle(ThemeColor.textSecondary)
                    .lineLimit(2)

                HStack(spacing: ThemeSpace.x3) {
                    GeometryReader { proxy in
                        let ratio = min(1, max(0, CGFloat(part.progress) / CGFloat(total)))
                        ZStack(alignment: .leading) {
                            Capsule().fill(ThemeColor.strokeStrong)
                            Capsule().fill(ThemeColor.accent)
                                .frame(width: max(LibraryRootMetrics.progressMinimumFill,
                                                  proxy.size.width * ratio))
                        }
                    }
                    .frame(height: LibraryRootMetrics.progressTrackHeight)

                    Text(Copy.Library.progressCompact(part.progress, total))
                        .type(ThemeType.metadata)
                        .foregroundStyle(ThemeColor.textSecondary)
                        .monospacedDigit()
                        .fixedSize()
                }
                .padding(.top, ThemeSpace.x1)
            } else {
                Text(Copy.Progress.episodeNext(nextEpisode))
                    .type(ThemeType.heroMeta)
                    .foregroundStyle(ThemeColor.textSecondary)
            }

        }
        .accessibilityElement(children: .contain)
    }
}

private struct LibraryLandscapeItem: Identifiable {
    let franchise: Franchise
    let caption: String?
    var id: String { franchise.id }
}

private struct LibraryLandscapeShelf: View {
    let title: String
    let items: [LibraryLandscapeItem]
    let onViewAll: () -> Void
    let onOpen: (Franchise) -> Void

    @Environment(AppModel.self) private var appModel
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: ThemeSpace.x3) {
            HStack(spacing: ThemeSpace.x3) {
                Text(title)
                    .type(ThemeType.sectionTitle)
                    .foregroundStyle(ThemeColor.textPrimary)
                Spacer()
                Button(Copy.Library.viewAll, action: onViewAll)
                    .buttonStyle(TertiaryButtonStyle2())
                    .accessibilityLabel(Copy.Library.viewAllSection(title))
            }
            .padding(.horizontal, ThemeMetrics.gutter)

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: ThemeMetrics.shelfGap) {
                    ForEach(items) { item in
                        LibraryLandscapeCard(item: item) { onOpen(item.franchise) }
                            .containerRelativeFrame(.horizontal,
                                                    count: typeSize.isAccessibilitySize ? 1 : 2,
                                                    span: 1,
                                                    spacing: ThemeMetrics.shelfGap)
                            .franchiseQuickActions(item.franchise, appModel: appModel)
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, ThemeMetrics.gutter, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct LibraryLandscapeCard: View {
    let item: LibraryLandscapeItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: ThemeSpace.x2) {
                ZStack {
                    RoundedRectangle(cornerRadius: LibraryRootMetrics.landscapeRadius,
                                     style: .continuous)
                        .fill(ThemeColor.surfaceRaised)
                    RemoteImageView(url: item.franchise.banner ?? item.franchise.cover,
                                    contentMode: .fill,
                                    maxPixel: LibraryRootMetrics.landscapeDecodePixel,
                                    alignment: .top,
                                    placeholderHidden: true)
                }
                .frame(maxWidth: .infinity)
                .frame(height: LibraryRootMetrics.landscapeHeight)
                .clipShape(RoundedRectangle(cornerRadius: LibraryRootMetrics.landscapeRadius,
                                            style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: LibraryRootMetrics.landscapeRadius,
                                          style: .continuous)
                    .strokeBorder(ThemeColor.posterEdge, lineWidth: 1))
                .shadow(.art)
                .zoomSource("lib/\(item.franchise.id)")

                VStack(alignment: .leading, spacing: ThemeSpace.x0_5) {
                    Text(item.franchise.displayTitle)
                        .type(ThemeType.shelfTitle)
                        .foregroundStyle(ThemeColor.textPrimary)
                        .lineLimit(1)
                    if let caption = item.caption {
                        Text(caption)
                            .type(ThemeType.shelfCaption)
                            .foregroundStyle(ThemeColor.textSecondary)
                            .lineLimit(1)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(OverArtPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel([item.franchise.title, item.caption].compactMap { $0 }.joined(separator: ", "))
        .accessibilityHint(Copy.Accessibility.opensTheShowHint)
    }
}

/// Content beneath Watching, Planned, and Watched. Each status gets one art-led focal title and a
/// calm poster list beneath it. The old two-column landscape grid forced every long title into a
/// different height and made these tabs look like a catalogue bolted under the Overview carousel.
private struct LibraryStatusContent: View {
    let items: [LibraryLandscapeItem]
    let emptyCopy: EmptyStateCopy
    let onOpen: (Franchise) -> Void

    @Environment(AppModel.self) private var appModel

    var body: some View {
        if items.isEmpty {
            LibraryStatusEmptyState(copy: emptyCopy)
                .padding(.top, LibraryRootMetrics.statusEmptyTopPadding)
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                LibraryStatusFeatureCard(item: items[0]) { onOpen(items[0].franchise) }
                    .franchiseQuickActions(items[0].franchise, appModel: appModel)

                if items.count > 1 {
                    VStack(spacing: 0) {
                        ForEach(items.dropFirst()) { item in
                            LibraryStatusRow(
                                item: item,
                                showsSeparator: item.id != items.last?.id
                            ) { onOpen(item.franchise) }
                            .franchiseQuickActions(item.franchise, appModel: appModel)
                        }
                    }
                    .padding(.top, ThemeSpace.x6)
                }
            }
            .padding(.horizontal, ThemeMetrics.gutter)
            .padding(.top, LibraryRootMetrics.contentTopPadding)
        }
    }
}

private struct LibraryStatusFeatureCard: View {
    let item: LibraryLandscapeItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: ThemeSpace.x3) {
                ZStack {
                    RoundedRectangle(cornerRadius: LibraryRootMetrics.statusFeatureRadius,
                                     style: .continuous)
                        .fill(ThemeColor.surfaceRaised)
                    RemoteImageView(url: item.franchise.banner ?? item.franchise.cover,
                                    contentMode: .fill,
                                    maxPixel: LibraryRootMetrics.statusFeatureDecodePixel,
                                    alignment: .top,
                                    placeholderHidden: true)
                }
                .frame(maxWidth: .infinity)
                .frame(height: LibraryRootMetrics.statusFeatureHeight)
                .clipShape(RoundedRectangle(cornerRadius: LibraryRootMetrics.statusFeatureRadius,
                                            style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: LibraryRootMetrics.statusFeatureRadius,
                                          style: .continuous)
                    .strokeBorder(ThemeColor.posterEdge, lineWidth: 1))
                .shadow(.art)
                .zoomSource("lib/\(item.franchise.id)")

                VStack(alignment: .leading, spacing: ThemeMetrics.titleGap) {
                    Text(item.franchise.displayTitle)
                        .type(ThemeType.showTitleM)
                        .foregroundStyle(ThemeColor.textPrimary)
                        .lineLimit(2)
                    if let caption = item.caption {
                        Text(caption)
                            .type(ThemeType.rowMeta)
                            .foregroundStyle(ThemeColor.textSecondary)
                            .lineLimit(2)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(OverArtPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel([item.franchise.title, item.caption]
            .compactMap { $0 }.joined(separator: ", "))
        .accessibilityHint(Copy.Accessibility.opensTheShowHint)
    }
}

private struct LibraryStatusRow: View {
    let item: LibraryLandscapeItem
    let showsSeparator: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: ThemeMetrics.artGap) {
                PosterSlot(url: item.franchise.cover,
                           width: LibraryRootMetrics.statusPosterWidth,
                           height: LibraryRootMetrics.statusPosterHeight,
                           radius: LibraryRootMetrics.statusPosterRadius,
                           shadow: .art)
                    .zoomSource("lib/\(item.franchise.id)")

                VStack(alignment: .leading, spacing: ThemeMetrics.titleGap) {
                    Text(item.franchise.displayTitle)
                        .type(ThemeType.rowTitle)
                        .foregroundStyle(ThemeColor.textPrimary)
                        .lineLimit(2)
                    if let caption = item.caption {
                        Text(caption)
                            .type(ThemeType.rowMeta)
                            .foregroundStyle(ThemeColor.textSecondary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, minHeight: LibraryRootMetrics.statusRowMinHeight,
                   alignment: .leading)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                if showsSeparator {
                    Rectangle()
                        .fill(ThemeColor.separatorQuiet)
                        .frame(height: 1)
                        .padding(.leading, LibraryRootMetrics.statusPosterWidth + ThemeMetrics.artGap)
                }
            }
        }
        .buttonStyle(RowPressStyle(radius: ThemeRadius.row))
        .accessibilityElement(children: .combine)
        .accessibilityLabel([item.franchise.title, item.caption]
            .compactMap { $0 }.joined(separator: ", "))
        .accessibilityHint(Copy.Accessibility.opensTheShowHint)
    }
}

/// A zero count is a quiet fact, not a recovery task. The selected tab already tells the user where
/// they are and Overview remains one tap away, so this state needs no plate and no banner CTA.
private struct LibraryStatusEmptyState: View {
    let copy: EmptyStateCopy

    var body: some View {
        VStack(spacing: 0) {
            if let symbol = copy.symbol {
                Image(systemName: symbol)
                    .font(.title3.weight(.regular))
                    .foregroundStyle(ThemeColor.textTertiary)
                    .frame(width: 44, height: 44)
                    .padding(.bottom, ThemeSpace.x3)
            }

            Text(copy.title)
                .type(ThemeType.showTitleM)
                .foregroundStyle(ThemeColor.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let supporting = copy.supporting {
                Text(supporting)
                    .type(ThemeType.callout)
                    .foregroundStyle(ThemeColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, ThemeSpace.x2)
            }
        }
        .frame(maxWidth: 300)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, ThemeMetrics.gutter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(copy.spokenLabel)
        .transition(.opacity)
    }
}

// MARK: - All titles (the instrument)

/// Which half of "coming back" a filter means. Not a `WatchStatus` — a show's future is not a list
/// state, which is the confusion the whole round is about.
enum ReturnScope: String, Hashable, CaseIterable {
    case dated, undated
    var label: String { self == .dated ? LibrarySection.returning.label : LibrarySection.announced.label }
    var section: LibrarySection { self == .dated ? .returning : .announced }
}

/// The one screen in the Library with controls on it. Rows sit on the canvas at `rowMedia` with
/// 60×90 art, under **pinned letter headers with an index rail** — thirty alphabetical rows with
/// no section headers and no index made the sort order invisible until you scrolled, and at the
/// stated 300 titles reaching "Vinland Saga" was a flick-scroll lottery.
struct LibraryAllView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    let onOpenDetail: (_ franchiseId: String, _ zoomID: String) -> Void
    /// The empty-library state's action, the same one the root offers.
    var onAddShow: () -> Void = {}

    /// The incoming filter is seeded into `@State` at INIT, not applied in `onAppear`. Applied
    /// late, the screen builds once unfiltered and once filtered — the user sees the whole library
    /// flash past on the way to the six rows they asked for, and the rows that survive both passes
    /// can keep the first pass's copy (rows under a `Watching` chip still reading "Watching").
    ///
    /// `initialUnwatchedOnly` composes with `initialStatus` rather than replacing it: Today's
    /// "View all N updates" asks for Watching AND unwatched, and dropping the status on the way in
    /// was how the list could disagree with the count that opened it.
    init(initialStatus: WatchStatus? = nil, initialReturning: ReturnScope? = nil,
         initialSort: Sort = .title, initialUnwatchedOnly: Bool = false,
         onOpenDetail: @escaping (_ franchiseId: String, _ zoomID: String) -> Void,
         onAddShow: @escaping () -> Void = {}) {
        self.onOpenDetail = onOpenDetail
        self.onAddShow = onAddShow
        _status = State(initialValue: initialStatus.map(StatusFilter.status) ?? .any)
        _unwatchedOnly = State(initialValue: initialUnwatchedOnly)
        _returning = State(initialValue: initialReturning)
        _sort = State(initialValue: initialSort)
    }

    enum Sort: String, CaseIterable, Identifiable {
        /// "Recently added" is backed by `Subscription.addedAt`, which the API already sends. It is
        /// the one order a user needs after importing or adding twenty shows — "what did I just
        /// add" — and the shipped sheet had no way to produce it.
        case title, added, recent, progress
        var id: String { rawValue }

        var label: String {
            switch self {
            case .title: return Copy.Library.sortTitle
            case .added: return Copy.Library.sortAdded
            case .recent: return Copy.Library.sortRecent
            case .progress: return Copy.Library.sortProgress
            }
        }

        /// The reversed direction, said in the reader's terms rather than as "ascending".
        var reversedHint: String {
            switch self {
            case .title: return Copy.Library.reversedTitle
            case .added: return Copy.Library.reversedAdded
            case .recent: return Copy.Library.reversedRecent
            case .progress: return Copy.Library.reversedProgress
            }
        }
    }
    enum Display: String, CaseIterable, Identifiable {
        case posters, list
        var id: String { rawValue }
        var label: String { self == .posters ? Copy.Library.posters : Copy.Library.list }
    }

    /// **One** single-select control for "which titles" by list state.
    ///
    /// "Has unwatched episodes" is a separate axis (`unwatchedOnly`) that composes with it: Today
    /// asks for Watching AND unwatched, and a value that replaced the status could not say both.
    /// Its noun is named — the identical word on Schedule's menu means episodes.
    enum StatusFilter: Hashable, Identifiable {
        case any
        case status(WatchStatus)

        var id: String {
            switch self {
            case .any: return "any"
            case .status(let s): return s.rawValue
            }
        }

        var label: String {
            switch self {
            case .any: return Copy.Library.anyStatus
            case .status(let s): return Copy.Status(s)
            }
        }

        /// The chip form. A chip states the criterion, and "Any" is not one.
        var chip: String? { self == .any ? nil : label }

        /// True when this filter already tells the reader the row's list state, so the rows can
        /// stop repeating it.
        var givesState: Bool { if case .status = self { return true } else { return false } }

        var watchStatus: WatchStatus? { if case .status(let s) = self { return s } else { return nil } }
    }

    @State private var query = ""
    @State private var sort: Sort = .title
    /// Newest first for the date sorts, A→Z for title, most-behind first for progress — then this
    /// flips whichever it is. Three single-direction sorts meant "oldest first" simply did not
    /// exist in the product.
    @State private var sortAscending = false
    @State private var status: StatusFilter = .any
    /// Titles with an episode out now that you have not watched — Today's "N updates" set.
    @State private var unwatchedOnly = false
    @State private var returning: ReturnScope?
    @State private var display: Display = .list
    @State private var showArrange = false
    @State private var contentWidth: CGFloat = 0
    /// The scroll view's own height, so a state that owns the whole surface can be centred in it.
    @State private var contentHeight: CGFloat = 0
    @State private var railTouching = false
    /// Ties each pinned section header to its rotor entry, so VoiceOver can jump between letters
    /// even while the lazy stack has not built the rows in between.
    @Namespace private var rotorSpace

    private var isAX: Bool { typeSize.isAccessibilitySize }

    /// The filtered, sorted catalogue. A function, not a property: it was read from eight sites
    /// per render (the list, the grid, the rail, the rotor, `showsRail`, `isSectioned`, the
    /// footer, the rail's VoiceOver value), each one re-filtering and re-sorting the library. It
    /// is resolved once in `body` and passed down.
    ///
    /// "Has unwatched episodes" is **the set Today counts** — `AppModel.outNow`, resolved once per
    /// pass — so "View all 12 updates" lands on twelve rows. The shipped predicate was its own
    /// (`markTarget > progress`), which counted unaired seasons as unwatched and could not agree
    /// with the number that opened the screen.
    private func filtered() -> [Franchise] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let outNow: Set<String> = unwatchedOnly ? Set(appModel.outNow.map(\.id)) : []
        var arr = appModel.library.filter { f in
            let statusOK: Bool
            switch status {
            case .any: statusOK = true
            case .status(let s): statusOK = f.effectiveStatus == s
            }
            return statusOK
                && (!unwatchedOnly || outNow.contains(f.id))
                && (returning == nil
                    || LibraryShelving.section(of: f, appModel: appModel) == returning?.section)
                && (q.isEmpty || f.title.lowercased().contains(q))
        }
        switch sort {
        case .title: arr.sort(by: LibraryAllView.titleAscending)
        // `addedAt` is absent in older server responses; an unknown date sorts LAST in the default
        // (newest-first) order rather than pretending to be 1970.
        case .added: arr.sort(by: LibraryAllView.descending { $0.subscription?.addedAt ?? .min })
        case .recent: arr.sort(by: LibraryAllView.descending { $0.lastAiredSortKey })
        case .progress: arr.sort(by: LibraryAllView.descending { $0.continueBacklog })
        }
        return sortAscending ? arr.reversed() : arr
    }

    /// The ONE tie-break, and the one title order. Three sorts used to break ties three ways
    /// (`lowercased()`, raw `title`, and a locale-aware compare), so "Ōoku" moved between them.
    private static func titleAscending(_ a: Franchise, _ b: Franchise) -> Bool {
        a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
    }

    /// Largest key first, `titleAscending` between equals.
    private static func descending<K: Comparable>(_ key: @escaping (Franchise) -> K)
        -> (Franchise, Franchise) -> Bool {
        { a, b in
            let ka = key(a), kb = key(b)
            return ka != kb ? ka > kb : titleAscending(a, b)
        }
    }

    /// A filter is a thing the user chose that hides rows. The **view mode** is not one — which is
    /// why the shipped "Posters … Clear" row offered a destructive-sounding action against a state
    /// that was nowhere on screen, and why the amber glyph in the bar meant nothing you could see.
    private var hasFilters: Bool {
        status != .any || unwatchedOnly || returning != nil || sort != .title || sortAscending
    }

    var body: some View {
        // Resolved ONCE per render, top to bottom: the rows, their sections, and the two facts
        // the chrome derives from them.
        let results = filtered()
        let sections = titleSections(results)
        let sectioned = isSectioned(results)
        let rail = showsRail(results)
        // The reader wraps the SCROLL VIEW. It used to sit inside the content, around the lazy
        // stack — which then had no scroll container to size against, reported zero height, and
        // drew its rows over the footer count that followed it ("30 titles" under the first row).
        return ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // The same freshness pair, failure notice and loading gate the root carries: this
                // screen used to open on a bare list whatever the catalogue's state was.
                Color.clear.frame(height: 0)
                    .freshness(.catalogue, appModel: appModel)
                    .padding(.horizontal, ThemeMetrics.gutter)

                if appModel.sectionFailed {
                    InlineNotice(Copy.Notice.library) { Task { await appModel.reload() } }
                        .padding(.horizontal, ThemeMetrics.gutter).padding(.top, ThemeSpace.x3)
                }

                if !activeChips.isEmpty { chipRow }

                SkeletonGate(isLoading: appModel.loading && appModel.library.isEmpty) {
                    skeleton
                } content: {
                  // ONE view. `SkeletonGate` lays its content out in a ZStack, so the list and the
                  // footer count handed to it as two siblings were drawn on top of each other —
                  // "30 titles" sitting across the first row.
                  VStack(alignment: .leading, spacing: 0) {
                    if appModel.library.isEmpty {
                        // The account, not a filter, is why there is nothing here — so the card
                        // is the root's, with the root's action. `.noFilterMatches` with no
                        // handler is the SYS-4 bug the DEBUG assert exists to catch.
                        EmptyState(appModel.emptyStateCopy, prominence: .major,
                                   primary: emptyLibraryAction, ambient: false)
                            .padding(.horizontal, ThemeMetrics.gutter)
                            .centredState(contentH: contentHeight)
                    } else if results.isEmpty {
                        // `hasFilters` is what emptied a query-less list, so `.noFilterMatches`
                        // always has its Clear; with a query the card still offers to clear
                        // whatever filters are narrowing it.
                        EmptyState(emptyResultsCopy, prominence: .major,
                                   primary: hasFilters ? { resetFilters() } : nil, ambient: false)
                            .padding(.horizontal, ThemeMetrics.gutter)
                            .centredState(contentH: contentHeight)
                    } else if display == .posters {
                        grid(sections, sectioned: sectioned, rail: rail).padding(.top, ThemeSpace.x2)
                    } else {
                        // No lead-in: the search drawer already carries its own margin, and the
                        // first row's own 8-pt padding is the gap iOS lists keep under a field.
                        list(sections, sectioned: sectioned, rail: rail)
                    }
                    if !results.isEmpty {
                        // Spoken, like the root's: the count is a fact about the list.
                        Text(Copy.titles(results.count))
                            .type(ThemeType.metadata).foregroundStyle(ThemeColor.textTertiary)
                            .numericFact(results.count)
                            .frame(maxWidth: .infinity)
                            .padding(.top, ThemeSpace.x6)
                    }
                  }
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { contentWidth = $0 }
        }
        .scrollIndicators(.hidden)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        .onChange(of: railScroll) { _, key in
            guard let key else { return }
            proxy.scrollTo("sec-\(key)", anchor: .top)
        }
        // The same wash the root carries, at the one root spec, so the push does not change the
        // room's light — and, like every root now, it begins BELOW the chrome and ramps in from
        // zero there. Run under the bar and its search drawer it drew a step under the field.
        // The same wash and the same bar veil every root carries (`rootWash` / `rootBarVeil`),
        // so the push does not change the room's light; the bottom edge is ours.
        .background(alignment: .top) {
            ZStack(alignment: .top) {
                ThemeColor.canvas
                ArtBackdrop(url: results.first?.cover ?? appModel.library.first?.cover,
                            height: ThemeMetrics.rootWashHeight,
                            intensity: ThemeMetrics.rootWashIntensity)
                    .frame(maxWidth: .infinity, alignment: .top)
            }
            .ignoresSafeArea()
        }
        .scrollEdgeChromeBody(top: true, bottom: true,
                              topHeight: ThemeMetrics.topSafeInset + ArrangeMetrics.searchDrawerHeight,
                              softTop: true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .scrollEdgeEffectHidden(true, for: .all)
        .contentMargins(.bottom, ThemeMetrics.tabBarClearance, for: .scrollContent)
        // The rail owns a lane. Rows reserve it through `listTrailingInset`, so a chevron and an
        // index letter can never land on the same 4 pt of screen, and the poster grid narrows its
        // available width by the same amount — the letters used to sit ON the third column's
        // artwork, and a tap near a poster's right edge could be swallowed by the rail's gesture.
        .environment(\.listTrailingInset, rail ? LibraryAllView.railLane : 0)
        .overlay(alignment: .trailing) { if rail { indexRail(sections) } }
        .navigationTitle(Copy.Heading.allTitles)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: Copy.Library.searchPrompt)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showArrange = true } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                }
                // Accent is selection here, and only here: an idle filter control is not the
                // screen's primary action and has no business being the loudest thing on it.
                .tint(hasFilters ? ThemeColor.accent : ThemeColor.textPrimary)
                .accessibilityLabel(ArrangeSheet.title)
            }
        }
        .sheet(isPresented: $showArrange) {
            ArrangeSheet(sort: $sort, ascending: $sortAscending, status: $status,
                         unwatchedOnly: $unwatchedOnly, display: $display, onReset: resetFilters)
                // Resolved BEFORE presentation from the row count and the type size. A detent that
                // measures itself cannot be right on the first frame: the sheet grew 68 pt under
                // the user's eye and only looked correct the second time it opened.
                .presentationDetents([.custom(ArrangeDetent.self), .large])
                .presentationDragIndicator(.visible)
                // Without this the sheet's plate stopped 34 pt short of the screen and the
                // undimmed list showed through the gap — it read as a rendering failure.
                .presentationBackground(ThemeColor.canvasRaised)
        }
        }
    }

    /// The empty-library action, and it is always a live one — the root's rule.
    private var emptyLibraryAction: () -> Void {
        appModel.loadError ? { Task { await appModel.reload() } } : onAddShow
    }

    /// Which "nothing here" card. A query names itself; a filter names the way out.
    private var emptyResultsCopy: EmptyStateCopy {
        query.isEmpty ? .noFilterMatches : Copy.Library.noSearchResults(query: query, filtered: hasFilters)
    }

    /// The list's stand-in: rows at the row slot, so the swap lands flush.
    private var skeleton: some View {
        VStack(spacing: 0) {
            ForEach(0..<Metrics.skeletonRowCount, id: \.self) { _ in
                SkeletonRow(poster: PosterSize.row.size, lines: Metrics.skeletonRowLines,
                            posterRadius: PosterSize.row.radius,
                            spacing: ThemeMetrics.artGap)
            }
        }
        .padding(.horizontal, ThemeMetrics.gutter)
        .padding(.top, ThemeSpace.x1)
    }

    // MARK: - Active filters, as chips

    private struct Chip: Identifiable {
        let id: String
        let text: String
        let clear: () -> Void
    }

    /// The iOS 26 filter-chip pattern: the criteria that are actually narrowing the list, each one
    /// removable on its own. The shipped row named the *view mode* in grey and offered an amber
    /// `Clear` beside it that reset four unrelated things at once, none of them on screen.
    private var activeChips: [Chip] {
        var chips: [Chip] = []
        if let text = status.chip {
            chips.append(Chip(id: "status", text: text) { self.status = .any })
        }
        if unwatchedOnly {
            chips.append(Chip(id: "unwatched", text: Copy.Library.hasUnwatched) { self.unwatchedOnly = false })
        }
        if let returning {
            chips.append(Chip(id: "returning", text: returning.label) { self.returning = nil })
        }
        if sort != .title || sortAscending {
            chips.append(Chip(id: "sort", text: sortChipLabel) { sort = .title; sortAscending = false })
        }
        return chips
    }

    /// The chip names the order the way the sheet does, direction included — a "Recently added"
    /// chip that silently means *oldest* first is a lie the reader cannot see.
    private var sortChipLabel: String {
        sortAscending ? Copy.Library.reversed(sort.label) : sort.label
    }

    private var chipRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: ThemeSpace.x2) {
                ForEach(activeChips) { chip in
                    Button {
                        FeedbackCoordinator.fire(.selection)
                        withAnimation(ThemeMotion.pick(ThemeMotion.uiSnappy, reduceMotion: reduceMotion)) {
                            chip.clear()
                        }
                    } label: {
                        FilterChipLabel(text: chip.text)
                    }
                    .buttonStyle(FilterChipStyle())
                    .accessibilityLabel(Copy.Accessibility.removeFilter(chip.text))
                }
                if activeChips.count > 1 {
                    Button(Copy.Action.reset) {
                        FeedbackCoordinator.fire(.selection)
                        withAnimation(ThemeMotion.pick(ThemeMotion.uiSnappy, reduceMotion: reduceMotion)) {
                            resetFilters()
                        }
                    }
                    // Neutral, not amber: returning to the default is the smallest thing on the
                    // row, and the screen's one accent is not spent on a utility.
                    .buttonStyle(ChipButtonStyle())
                }
            }
            .padding(.horizontal, ThemeMetrics.gutter)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .padding(.bottom, ThemeSpace.x2)
    }

    private func resetFilters() {
        // The VIEW MODE is deliberately untouched: it is a preference, not a filter, and nothing
        // on this row claims otherwise.
        sort = .title; sortAscending = false; status = .any; unwatchedOnly = false; returning = nil
    }

    // MARK: - Sections and the index

    struct TitleSection: Identifiable {
        let key: String
        let items: [Franchise]
        var id: String { key }
    }

    /// Grouped by the ACTIVE sort key — first letter for `.title`, month for the date sort. The
    /// backlog sort has no natural grouping, so it stays one flat list and the rail is suppressed
    /// with it; a header the sort cannot justify is noise.
    private func titleSections(_ results: [Franchise]) -> [TitleSection] {
        // One bucket when the list is not sectioned. A `Section` inside a `LazyVGrid` starts a new
        // ROW even when its header is an `EmptyView`, so leaving the per-letter buckets in place
        // and merely hiding the headers laid a ten-title poster wall out two-then-one down the
        // page with holes where the letters changed.
        guard isSectioned(results) else { return [TitleSection(key: "", items: results)] }
        switch sort {
        case .title:
            var buckets: [String: [Franchise]] = [:]
            for f in results { buckets[LibraryAllView.indexKey(f.title), default: []].append(f) }
            return buckets.keys.sorted { a, b in
                if (a == "#") != (b == "#") { return b == "#" }
                return a < b
            }.map { TitleSection(key: $0, items: buckets[$0] ?? []) }
        case .recent, .added:
            var order: [String] = []
            var buckets: [String: [Franchise]] = [:]
            for f in results {
                // `addedAt` is the user's own instant (local); an airing is read in the
                // franchise's calendar, so a TMDB date-only row lands in the month it names.
                let key = sort == .added
                    ? LibraryAllView.monthKey(f.subscription?.addedAt ?? 0, anchor: .local)
                    : LibraryAllView.monthKey(f.lastAiredSortKey, anchor: f.timeAnchor)
                if buckets[key] == nil { order.append(key) }
                buckets[key, default: []].append(f)
            }
            return order.map { TitleSection(key: $0, items: buckets[$0] ?? []) }
        case .progress:
            return [TitleSection(key: "", items: results)]
        }
    }

    /// Headers earn their keep only once the list is long enough that the sort order stops being
    /// obvious. Below that they cost more than they explain — and in the three-column grid an
    /// alphabetical break with one title behind it burns two empty cells, which is what a filtered
    /// poster wall looked like: one cover per row. Same threshold as the rail, so the two controls
    /// never disagree about whether this list has sections.
    private func isSectioned(_ results: [Franchise]) -> Bool {
        sort != .progress && results.count > LibraryAllView.sectionFloor
    }

    static let sectionFloor = 48

    /// Forty-eight rows is about five screens; below that a flick is faster than an alphabet, and
    /// a thirty-title library dressed in letter headers and a rail read as a phone book for one
    /// street. At the stated 300 titles the rail is the difference between finding "Vinland Saga"
    /// and hunting for it. Suppressed for every other sort order, where A–Z would be a lie.
    private func showsRail(_ results: [Franchise]) -> Bool {
        sort == .title && results.count > LibraryAllView.sectionFloor && !isAX
    }

    /// "A"…"Z" and "#" for everything that does not start with a letter.
    static func indexKey(_ title: String) -> String {
        let folded = title.folding(options: [.diacriticInsensitive, .caseInsensitive],
                                   locale: .current)
        guard let first = folded.first(where: { $0.isLetter || $0.isNumber }) else { return "#" }
        return first.isLetter ? String(first).uppercased() : "#"
    }

    /// `at` is **milliseconds**, like every other instant in this app. It was read as seconds here,
    /// which put the "Recently updated" month headers roughly fifty-five thousand years out.
    private static func monthKey(_ at: Int64, anchor: Formatting.TimeAnchor) -> String {
        guard at > 0 else { return Copy.Library.noDate }
        return LibraryDates.monthYear(at, anchor: anchor)
    }

    /// A pinned strip, not a floating label: content scrolls UNDER it, so it is opaque canvas with
    /// a quiet rule beneath — the same separator the rows carry.
    ///
    /// `inset` puts that rule on the SAME left edge as the row separators below it. Full width, it
    /// was a second separator inset on one screen (rows start their hairline at the title, x≈164)
    /// and the letter read as a stray character standing beside a rule that belonged to nothing.
    private func sectionHeader(_ key: String, inset: CGFloat, rail: Bool) -> some View {
        HStack(spacing: 0) {
            Text(key)
                .type(ThemeType.sectionLabel)
                .foregroundStyle(ThemeColor.textTertiary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, ThemeMetrics.gutter)
        .padding(.top, ThemeSpace.x3)
        .padding(.bottom, ThemeSpace.x1)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Opaque, and FULL-BLEED. Inset to the gutter it painted a visible canvas rectangle
        // against the ambient wash behind the list — a plate, which is exactly what a pinned
        // header must not look like. A pinned bar reaches both bezels.
        .background { ThemeColor.canvas.padding(.horizontal, -ThemeMetrics.gutter) }
        .overlay(alignment: .bottom) {
            Rectangle().fill(ThemeColor.separatorQuiet).frame(height: 1)
                .padding(.leading, inset)
                .padding(.trailing, rail ? LibraryAllView.railLane : 0)
        }
        .accessibilityAddTraits(.isHeader)
    }

    /// The A–Z rail — rebuilt. Everything it was measured on failed:
    ///
    ///  * **Type.** `.font(.system(size: 11, weight: .semibold))` is hard-coded, so it stayed 11 pt
    ///    at AX5; `sectionLabel` is the app's smallest token and it scales.
    ///  * **Contrast.** `textDisabled` is 3.6:1 — the non-text threshold — on TEXT. `textTertiary`
    ///    is 5.14:1, and while the finger is down the letters lift to `textSecondary` with the
    ///    ACTIVE one in accent, so the rail says which letter it is on instead of all of them.
    ///  * **Extent.** 15 letters × 15 pt was a 225-pt column floating in the vertical middle,
    ///    attached to nothing. It now spans the list, top to bottom, so its geometry means what it
    ///    looks like it means — and every band is at least 22 pt.
    ///  * **Target.** 22×15 pt bands inside a 22-pt column. The letters sit right-aligned in the
    ///    `railLane` (28 pt) the rows reserve (`listTrailingInset`); the GESTURE host is `railHit`
    ///    (44 pt) wide, reaching 16 pt into the rows' trailing padding, so the hit area is what
    ///    the comment says it is and the rail no longer sits on the third poster column's artwork.
    ///  * **VoiceOver.** It was `.accessibilityHidden(true)` with no substitute, so a user with 500
    ///    titles had to swipe every row. It is one adjustable element now, and the list carries a
    ///    "Sections" rotor.
    ///  * **Feel.** The 300 ms blanket haptic floor meant an A→W drag produced two taps. `.selection`
    ///    now has its own 40 ms floor (SYS-7), which is what makes this control feel alive.
    private func indexRail(_ sections: [TitleSection]) -> some View {
        let keys = sections.map(\.key)
        return GeometryReader { geo in
            let step = max(LibraryAllView.railMinStep,
                           geo.size.height / CGFloat(max(keys.count, 1)))
            VStack(spacing: 0) {
                ForEach(Array(keys.enumerated()), id: \.element) { i, key in
                    Text(key)
                        .type(ThemeType.sectionLabel)
                        .foregroundStyle(railTint(index: i))
                        .frame(maxWidth: .infinity)
                        .frame(height: step)
                }
            }
            .frame(width: LibraryAllView.railLane)
            .frame(width: LibraryAllView.railHit, height: geo.size.height, alignment: .topTrailing)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        railTouching = true
                        let i = Int(value.location.y / step)
                        select(index: max(0, min(keys.count - 1, i)), keys: keys)
                    }
                    .onEnded { _ in railTouching = false; railIndex = nil; railScroll = nil }
            )
        }
        .frame(width: LibraryAllView.railHit)
        // Between the search drawer and the tab bar, so the column IS the list's extent.
        .padding(.top, ThemeSpace.x3)
        .padding(.bottom, ThemeMetrics.tabBarClearance)
        .background(alignment: .trailing) {
            // The ground appears only under the finger, and only behind the letters.
            Capsule()
                .fill(ThemeColor.surfaceRaised.opacity(railTouching ? 1 : 0))
                .frame(width: LibraryAllView.railLane)
                .padding(.vertical, ThemeSpace.x2)
        }
        .animation(ThemeMotion.pick(ThemeMotion.uiMicro, reduceMotion: reduceMotion), value: railTouching)
        .accessibilityElement()
        .accessibilityLabel(Copy.Library.sectionIndex)
        .accessibilityValue(railIndex.flatMap { keys.indices.contains($0) ? keys[$0] : nil }
                            ?? keys.first ?? "")
        .accessibilityHint(Copy.Library.sectionIndexHint)
        .accessibilityAdjustableAction { direction in
            let current = railIndex ?? 0
            let next = direction == .increment ? current + 1 : current - 1
            guard keys.indices.contains(next) else { return }
            select(index: next, keys: keys)
        }
    }

    /// One selection, wherever it came from — the finger or the VoiceOver rotor.
    private func select(index: Int, keys: [String]) {
        guard keys.indices.contains(index), index != railIndex else { return }
        railIndex = index
        FeedbackCoordinator.fire(.selection)
        railScroll = keys[index]
    }

    private func railTint(index: Int) -> Color {
        guard railTouching else { return ThemeColor.textTertiary }
        return index == railIndex ? ThemeColor.accent : ThemeColor.textSecondary
    }

    @State private var railIndex: Int?
    @State private var railScroll: String?

    /// The reserved trailing lane. Rows stop short of it and the poster grid narrows by it, which
    /// is what Contacts does and what stops a letter landing on a cover.
    static let railLane: CGFloat = 28
    /// The rail's gesture host — the minimum touch target, wider than the lane the letters draw in.
    static let railHit: CGFloat = 44
    /// Where a list row's hairline starts — the title's leading edge. The section-letter rule uses
    /// the same x, so one screen carries one separator inset.
    static let rowRuleInset: CGFloat =
        ThemeMetrics.gutter + PosterSize.row.size.width + ThemeMetrics.artGap
    /// A band is never smaller than this, however few letters there are; above that the rail fills
    /// the list's height so the column is anchored to the thing it scrolls.
    private static let railMinStep: CGFloat = 22

    // MARK: - List

    private func list(_ sections: [TitleSection], sectioned: Bool, rail: Bool) -> some View {
        // LAZY, and SECTIONED. At the stated 300-title library an eager `VStack` instantiates 300
        // `MediaRow`s and 300 `RemoteImageView`s on push, and thirty unbroken alphabetical rows
        // make the sort order invisible until you have already scrolled past it.
        LazyVStack(spacing: 0, pinnedViews: sectioned ? [.sectionHeaders] : []) {
            ForEach(sections) { section in
                Section {
                    ForEach(Array(section.items.enumerated()), id: \.element.id) { i, f in
                        row(f, last: i == section.items.count - 1)
                    }
                } header: {
                    listHeader(section, sectioned: sectioned, rail: rail)
                }
            }
        }
        .padding(.horizontal, ThemeMetrics.gutter)
        // The rail's VoiceOver counterpart: the same jumps, through the system's own rotor.
        .accessibilityRotor(Copy.Library.sectionsRotor, entries: sections, entryID: \.key, entryLabel: \.key)
    }

    /// Extracted: the pinned header, inset to the rows' own hairline and wired to the rotor.
    @ViewBuilder
    private func listHeader(_ section: TitleSection, sectioned: Bool, rail: Bool) -> some View {
        if sectioned {
            sectionHeader(section.key, inset: LibraryAllView.rowRuleInset, rail: rail)
                .id("sec-\(section.key)")
                .accessibilityRotorEntry(id: section.key, in: rotorSpace)
        }
    }

    private func row(_ f: Franchise, last: Bool) -> some View {
        let facts = LibraryRowFacts.catalogue(f, appModel: appModel, stateIsGiven: status.givesState)
        // `.row` (60×90 at `rowMedia`) — the one list-row slot. At 48 pt wide a logo-led cover is
        // below the recognition floor ("Avatar: Seven Havens" rendered as a black rectangle with
        // unreadable type), and this is the catalogue, the one screen whose whole job is picking
        // a title out of three hundred.
        return MediaRow(title: f.displayTitle,
                        meta: facts.meta,
                        lead: facts.lead,
                        poster: f.cover,
                        slot: .row,
                        separator: !last,
                        hint: Copy.Accessibility.opensTheShowHint,
                        zoomID: "all/\(f.id)") {
            onOpenDetail(f.id, "all/\(f.id)")
        }
        .franchiseQuickActions(f, appModel: appModel)
    }

    // MARK: - Poster wall

    /// Three columns that exactly fill the gutters instead of an adaptive grid that leaves a ragged
    /// 30 pt down the trailing edge — and the same pinned headers the list carries, because a wall
    /// of 300 covers needs the alphabet even more than a list of them does.
    private func grid(_ sections: [TitleSection], sectioned: Bool, rail: Bool) -> some View {
        let columns = 3
        let lane = rail ? LibraryAllView.railLane : 0
        let available = max(0, contentWidth - ThemeMetrics.gutter * 2 - lane)
        let cellWidth = available > 0
            ? (available - ThemeMetrics.shelfGap * CGFloat(columns - 1)) / CGFloat(columns)
            : PosterSize.shelfMedium.size.width
        return LazyVGrid(columns: Array(repeating: GridItem(.fixed(cellWidth), spacing: ThemeMetrics.shelfGap,
                                                            alignment: .top),
                                        count: columns),
                         alignment: .leading, spacing: ThemeSpace.x6,
                         pinnedViews: sectioned ? [.sectionHeaders] : []) {
                ForEach(sections) { section in
                    Section {
                        ForEach(section.items) { f in
                            cell(f, width: cellWidth, alignCaptions: section.items.count > 1)
                        }
                    } header: {
                        if sectioned {
                            // No poster column to align to in the wall, so the rule starts at the
                            // gutter — and stops short of the rail's lane, like every row does.
                            sectionHeader(section.key, inset: ThemeMetrics.gutter, rail: rail)
                                .padding(.horizontal, -ThemeMetrics.gutter)
                                .id("sec-\(section.key)")
                                .accessibilityRotorEntry(id: section.key, in: rotorSpace)
                        }
                    }
                }
            }
            .padding(.horizontal, ThemeMetrics.gutter)
            .accessibilityRotor(Copy.Library.sectionsRotor, entries: sections, entryID: \.key, entryLabel: \.key)
    }

    /// A `ShelfCard` at the grid's own width. The card's rules, verbatim — `shelfShortened`
    /// title, THREE reserved lines at a 0.82 floor, two-line tail-truncated caption, the shelf
    /// slot's radius — because the wall and the Returning shelf are one poster-plus-caption
    /// object and were drifting on every one of those (two lines here, no scale floor, a
    /// hand-picked radius). `ShelfCard` itself sizes from a slot and cannot take the computed
    /// column width, which is the only reason this is not a call to it.
    ///
    /// `alignCaptions` reserves the title lines so a row of cells keeps ONE caption baseline. A
    /// section holding a single title has nothing to align with, and reserving there left a hole
    /// between a one-line title and its caption — the caption ended up nearer the next section
    /// than its own cover.
    private func cell(_ f: Franchise, width: CGFloat, alignCaptions: Bool = true) -> some View {
        // Resolved once — calling the accessor twice to pick a colour is how a caption and its
        // colour drift apart.
        let caption = gridCaption(f)
        let radius = PosterSize.shelfMedium.radius
        return Button { onOpenDetail(f.id, "all/\(f.id)") } label: {
            VStack(alignment: .leading, spacing: ThemeSpace.x2) {
                PosterSlot(url: f.cover, width: width, height: (width * 3 / 2).rounded(),
                           radius: radius, shadow: .art)
                    // The list variant zooms into Detail and the wall slid, so the transition
                    // changed with a VIEW-MODE TOGGLE. Same id the push already passes.
                    .zoomSource("all/\(f.id)")
                VStack(alignment: .leading, spacing: ThemeSpace.x0_5) {
                    Text(f.displayTitle)
                        .type(ThemeType.shelfTitle).foregroundStyle(ThemeColor.textPrimary)
                        // `ShelfCard`'s rule: nothing reserved, up to two lines.
                        .lineLimit(isAX ? 1...6 : 1...2)
                        .minimumScaleFactor(0.82)
                        .allowsTightening(true)
                        .multilineTextAlignment(.leading)
                    if let caption {
                        Text(caption.text)
                            .type(ThemeType.shelfCaption)
                            .foregroundStyle(caption.lead ? ThemeColor.accent : ThemeColor.textSecondary)
                            .lineLimit(2)
                            .truncationMode(.tail)
                    }
                }
                .frame(width: width, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle(radius: radius))
        .franchiseQuickActions(f, appModel: appModel)
        .accessibilityElement(children: .combine)
        // The spoken title is the WHOLE title, never the shortened one.
        .accessibilityLabel([f.title, caption?.text].compactMap { $0 }.joined(separator: ", "))
        .accessibilityHint(Copy.Accessibility.opensTheShowHint)
    }

    /// The grid cell is ~136 pt wide, not 360 — so it gets the SHORTEST honest form of the **same**
    /// facts, from the same function the list rows use.
    ///
    /// This used to be a second implementation, and it reached a different conclusion: the wall
    /// said "Episode 1 next" in amber where the list said "Watched" in grey for the same show one
    /// segment apart, and neither mentioned the rewatch that was actually in progress. A user reads
    /// that as the app losing their data. `catalogue(compact:)` is now the single source; the mode
    /// changes the layout and never the facts. Board 09's rule holds: drop a fact, never truncate.
    private func gridCaption(_ f: Franchise) -> (text: String, lead: Bool)? {
        let facts = LibraryRowFacts.catalogue(f, appModel: appModel,
                                              stateIsGiven: status.givesState, compact: true)
        if let lead = facts.lead { return (lead, true) }
        if let meta = facts.meta { return (meta, false) }
        return nil
    }

    /// Geometry this screen owns and no token names. One line of reason each.
    private enum Metrics {
        /// Enough skeleton rows to fill a phone screen at the row slot; the same line widths the
        /// root's list stand-in uses, so the two loading frames are one object.
        static let skeletonRowCount = 8
        static let skeletonRowLines: [CGFloat] = [196, 108]
    }
}

// MARK: - Sort and filter

/// The detent, resolved before the sheet is on screen.
///
/// `arrangeHeight` used to start at a 340-pt guess and be corrected by `onGeometryChange` feeding
/// `.presentationDetents([.height(h)])`, so the sheet grew 68 pt under the user's eye on first open
/// and only looked right the second time. A custom detent computes from what the sheet actually
/// contains — five rows, two groups, a header — scaled by the type size, and is correct on frame 1.
private enum ArrangeGeometry {
    /// What the detent measures: four rows in the first group, one in the second.
    static let rowCount: CGFloat = 5
    /// Header (52) + its top pad (12) + the groups' top pad (20) + the gap between the groups (30)
    /// + the bottom pad (24) + the home-indicator strip a sheet's scroll view inherits (34) — less
    /// the 42 pt the sheet measured under that sum on the simulator. A detent computed purely from
    /// first principles left 42 pt of void beneath the last row.
    /// The one `SectionLabel` group header the sheet gained is paid for out of the gap between the
    /// groups, which the label now occupies — measured on the simulator, the sum above still lands
    /// the last row's baseline where it was.
    static let chrome: CGFloat = ArrangeMetrics.headerHeight + 12 + 20 + 30 + 24 + 34 - 42
}

/// Geometry the sheet owns and no token names. One line of reason each.
private enum ArrangeMetrics {
    /// The height the search field adds under the title on All titles — the top veil covers both.
    static let searchDrawerHeight: CGFloat = 52

    /// The sheet's hand-built header: a 44-pt link row plus the drag indicator's clearance.
    static let headerHeight: CGFloat = 52
    /// `GroupedRow`'s own insets (14 leading, 16 trailing), so a menu row and a toggle row in the
    /// same plate share one text edge.
    static let rowInsetLeading: CGFloat = 14
    static let rowInsetTrailing: CGFloat = 16
    /// The pop-up glyph (`chevron.up.chevron.down`) at the size the system draws it in a menu row.
    static let popupGlyphSize: CGFloat = 12
    /// Two segments ("Posters" / "List") at their natural width beside a label on one row.
    static let segmentedWidth: CGFloat = 168
}

private struct ArrangeDetent: CustomPresentationDetent {
    static func height(in context: Context) -> CGFloat? {
        let rows = ArrangeGeometry.rowCount * ThemeMetrics.rowCompact * typeFactor(context.dynamicTypeSize)
        return min(rows + ArrangeGeometry.chrome, context.maxDetentValue * 0.92)
    }

    /// Body text grows roughly linearly with the Dynamic Type ramp; the rows are `minHeight`
    /// bound, so this only has to be right to a few points.
    private static func typeFactor(_ size: DynamicTypeSize) -> CGFloat {
        switch size {
        case .xSmall: return 0.92
        case .small: return 0.95
        case .medium: return 0.98
        case .large: return 1.00
        case .xLarge: return 1.08
        case .xxLarge: return 1.16
        case .xxxLarge: return 1.26
        case .accessibility1: return 1.52
        case .accessibility2: return 1.74
        case .accessibility3: return 2.05
        case .accessibility4: return 2.35
        case .accessibility5: return 2.60
        @unknown default: return 1.00
        }
    }
}

/// Board 05, verbatim: "a grouped list, not a chip cloud — Sort by and Status rows, a segmented
/// View, native toggles, Reset."
///
/// Titled **Sort & filter** (sentence case, `Copy.Heading`), because "Arrange" is Files.app's word
/// for ordering a grid and this sheet holds a sort, its direction and a status filter. "Has
/// unwatched episodes" is a native toggle under Status — its own axis, composed with the status,
/// and named for its noun. What is left over is `View as`, which is neither a sort nor a filter —
/// so it gets its own named group and stops reading as an afterthought.
///
/// The header is hand-built rather than a `NavigationStack` toolbar: on this OS a toolbar button
/// renders as a filled glass capsule, which made `Done` the single heaviest object in a sheet whose
/// whole job is to be quiet. `Done` is a link. `Reset` is a link. The rows are the content.
private struct ArrangeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @Binding var sort: LibraryAllView.Sort
    @Binding var ascending: Bool
    @Binding var status: LibraryAllView.StatusFilter
    @Binding var unwatchedOnly: Bool
    @Binding var display: LibraryAllView.Display
    let onReset: () -> Void

    private var isAX: Bool { typeSize.isAccessibilitySize }

    private var hasFilters: Bool { sort != .title || ascending || status != .any || unwatchedOnly }

    /// Sentence case, and the `&` only because these are two nouns in a label that has to hold one
    /// line. `Copy.Heading` settles both rules once for the whole app.
    static var title: String { Copy.Heading.sortAndFilter }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                groups
                    .padding(.horizontal, ThemeMetrics.gutter)
                    .padding(.top, ThemeSpace.x5)
                    .padding(.bottom, ThemeSpace.x6)
            }
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        // The sheet's own ground is set with `.presentationBackground` at the call site so it
        // reaches the screen's bottom edge; painting it on this scroll view left the plate 34 pt
        // short and the undimmed list showing through underneath.
    }

    private var groups: some View {
        VStack(alignment: .leading, spacing: ThemeMetrics.sectionGap) {
            // The first group needs no label: the sheet's own title names it, and repeating
            // "SORT & FILTER" 30 pt under "Sort & filter" is an echo. The SECOND group gets one,
            // which is the whole point — "View as" is neither a sort nor a filter, and unlabelled
            // it read as an afterthought stranded in a plate of its own. (iOS Settings grammar:
            // the first group is implicit, later groups are named.)
            GroupedList {
                valueRow(title: Copy.Library.sortBy, value: sort.label, separator: true) {
                    Picker(Copy.Library.sortBy, selection: sortBinding) {
                        ForEach(LibraryAllView.Sort.allCases) { s in
                            Text(s.label).tag(s)
                        }
                    }
                    .pickerStyle(.inline)
                }
                // Every sort shipped in exactly one direction, so "oldest first" did not exist.
                GroupedRow(title: Copy.Library.reverseOrder,
                           subtitle: ascending ? sort.reversedHint : nil,
                           trailing: .toggle(ascendingBinding), separator: true)
                valueRow(title: Copy.Library.status, value: status.label, separator: true) {
                    Picker(Copy.Library.status, selection: statusBinding) {
                        Text(LibraryAllView.StatusFilter.any.label)
                            .tag(LibraryAllView.StatusFilter.any)
                        ForEach(WatchStatus.menuOrder, id: \.self) { s in
                            Text(LibraryRowFacts.listState(status: s))
                                .tag(LibraryAllView.StatusFilter.status(s))
                        }
                    }
                    .pickerStyle(.inline)
                }
                // Its own axis, so Today's "Watching AND unwatched" is representable — and a
                // native toggle, which is what board 05 asked for.
                GroupedRow(title: Copy.Library.hasUnwatched,
                           trailing: .toggle(unwatchedBinding), separator: false)
            }

            GroupedList(header: Copy.Library.view) { viewAsRow }
        }
    }

    /// Board 05 asks for a segmented View. At accessibility sizes two words cannot share a row with
    /// their label, so the control drops under it rather than squeezing to 60 pt.
    private var viewAsRow: some View {
        let picker = Picker(Copy.Library.viewAs, selection: displayBinding) {
            ForEach(LibraryAllView.Display.allCases) { d in
                Text(d.label).tag(d)
            }
        }
        .pickerStyle(.segmented)

        return Group {
            if isAX {
                VStack(alignment: .leading, spacing: ThemeSpace.x2) {
                    Text(Copy.Library.viewAs).type(ThemeType.body).foregroundStyle(ThemeColor.textPrimary)
                    picker
                }
                .padding(.vertical, ThemeSpace.x3)
            } else {
                HStack(spacing: ThemeSpace.x3) {
                    Text(Copy.Library.viewAs).type(ThemeType.body).foregroundStyle(ThemeColor.textPrimary)
                    Spacer(minLength: ThemeSpace.x3)
                    picker.frame(width: ArrangeMetrics.segmentedWidth)
                }
            }
        }
        .padding(.leading, ArrangeMetrics.rowInsetLeading).padding(.trailing, ArrangeMetrics.rowInsetLeading)
        .frame(minHeight: ThemeMetrics.rowCompact)
    }

    /// A `GroupedRow` that opens a menu instead of pushing. Same 14/16 insets, same 56-pt height,
    /// same quiet separator — it is the shared row's geometry with a `Menu` where the `Button` is,
    /// which `GroupedRow` has no case for yet (see the shared-file request in the report).
    private func valueRow<Content: View>(title: String, value: String, separator: Bool,
                                         @ViewBuilder menu: () -> Content) -> some View {
        Menu {
            menu()
        } label: {
            HStack(spacing: ThemeSpace.x3) {
                Text(title).type(ThemeType.body).foregroundStyle(ThemeColor.textPrimary)
                Spacer(minLength: ThemeSpace.x3)
                Text(value)
                    .type(ThemeType.body).foregroundStyle(ThemeColor.textTertiary)
                    .lineLimit(1)
                // The pop-up glyph, not `chevron.forward`: this row opens a menu in place, it does
                // not push a screen, and iOS has one symbol for each.
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: ArrangeMetrics.popupGlyphSize, weight: .semibold))
                    .foregroundStyle(ThemeColor.textDisabled)
            }
            .padding(.leading, ArrangeMetrics.rowInsetLeading).padding(.trailing, ArrangeMetrics.rowInsetTrailing)
            .frame(minHeight: ThemeMetrics.rowCompact)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                if separator {
                    Rectangle().fill(ThemeColor.separatorQuiet)
                        .frame(height: 1).padding(.leading, ArrangeMetrics.rowInsetLeading)
                }
            }
        }
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }

    /// The title is an OVERLAY, not a stack member: with `Reset` present on one side only, a
    /// three-item HStack puts the title wherever the two buttons' widths happen to leave it.
    private var header: some View {
        HStack {
            if hasFilters {
                Button(Copy.Action.reset) {
                    FeedbackCoordinator.fire(.selection)
                    withAnimation(ThemeMotion.pick(ThemeMotion.uiSnappy, reduceMotion: reduceMotion)) {
                        onReset()
                    }
                }
                .buttonStyle(InlineLinkButtonStyle())
            }
            Spacer(minLength: 0)
            Button(Copy.Action.done) { dismiss() }
                .buttonStyle(InlineLinkButtonStyle())
        }
        .overlay {
            Text(ArrangeSheet.title)
                .type(ThemeType.showTitleM).foregroundStyle(ThemeColor.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, ThemeMetrics.gutter)
        .frame(height: ArrangeMetrics.headerHeight)
        .padding(.top, ThemeSpace.x3)
    }

    // MARK: - Bindings
    //
    // A `Picker` writes straight through its binding, so the haptic and the settle animation the
    // spec asks of a selection have to live in the binding rather than at a tap site.

    private func select<V: Equatable>(_ current: V, _ new: V, _ apply: @escaping () -> Void) {
        guard new != current else { return }
        FeedbackCoordinator.fire(.selection)
        withAnimation(ThemeMotion.pick(ThemeMotion.uiMicro, reduceMotion: reduceMotion), apply)
    }

    private var sortBinding: Binding<LibraryAllView.Sort> {
        Binding(get: { sort }, set: { new in select(sort, new) { sort = new } })
    }

    private var statusBinding: Binding<LibraryAllView.StatusFilter> {
        Binding(get: { status }, set: { new in select(status, new) { status = new } })
    }

    private var displayBinding: Binding<LibraryAllView.Display> {
        Binding(get: { display }, set: { new in select(display, new) { display = new } })
    }

    private var ascendingBinding: Binding<Bool> {
        Binding(get: { ascending }, set: { new in select(ascending, new) { ascending = new } })
    }

    private var unwatchedBinding: Binding<Bool> {
        Binding(get: { unwatchedOnly }, set: { new in select(unwatchedOnly, new) { unwatchedOnly = new } })
    }
}
