import SwiftUI

// Library (spec board 05): a calm root with ONE art moment and everything else quiet, and
// "All titles" — the instrument (search, sort, filter, view) behind one row. Urgency lives on
// Today, never here.
//
// Polish round 2. What the adversarial panel drew blood on, and what this is:
//
//  * **"Finished" meant two things at once** — the user's list state AND the series' production
//    state — so All titles said "Black Clover · Finished" one screen after the root said
//    "Black Clover · Returns Oct 2026". The list state is now **Watched**, and the forward fact
//    rides with it: "Watched · Returns Oct 2026". See `LibraryRowFacts.listState`.
//  * **A finished series with no announced date sat under RETURNING.** A section that promises a
//    return may only contain shows with a known date; everything else gets `ANNOUNCED`, where
//    "No date announced" is the point. See `LibrarySection` / `ReturnFact`.
//  * **Two spinners on every pull.** The hand-assembled header ran `RefreshIndicator` beside the
//    word "Library" while `.refreshable` ran the system one at the top. The composed
//    `.freshness(_:appModel:pullDriving:)` exists precisely to arbitrate that and had zero call
//    sites; this is the first.
//  * **The skeleton was a different screen from the one that arrived** — two text lines where a
//    `ShelfCard` reserves two title lines plus a caption, so everything below jumped 44 pt at the
//    swap, and three cards where the real shelf runs off the trailing edge.
//  * **The empty and error cards were pinned to the top of ~1,000 pt of void.** `centredState`.
//  * **RETURNING (13) had no `See all` while WATCHING (9) did** — the larger collection was the
//    one you could not open. Every section's count is now reachable.
struct LibraryView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dynamicTypeSize) private var typeSize
    let onOpenDetail: (_ franchiseId: String, _ zoomID: String) -> Void
    /// Where shows are added. Today and Schedule already take this; the Library's empty state
    /// printed the same `Add a show` label with nothing behind it.
    var onAddShow: () -> Void = {}

    @State private var all: AllTitlesRoute?
    /// True while the user's finger owns a pull. The system's own indicator is then the only
    /// spinner on screen — see `L-17` above.
    @State private var pullDriving = false
    /// The scroll view's own height, so a state that owns the whole surface can be centred in it.
    @State private var contentHeight: CGFloat = 0
    private var isAX: Bool { typeSize.isAccessibilitySize }

    private var now: Int64 { appModel.now }

    /// Where a `See all` lands. Two independent axes, because the root's buckets are not all
    /// statuses: `Returning` and `Announced` are facts about a show's future, not list states.
    struct AllTitlesRoute: Hashable, Identifiable {
        var status: WatchStatus?
        var returning: ReturnScope?
        var id: String { "\(status?.rawValue ?? "-")/\(returning?.rawValue ?? "-")" }
    }

    var body: some View {
        ZStack(alignment: .top) {
            ThemeColor.canvas.ignoresSafeArea()
            // The ambient identity wash. Pinned to the screen rather than scrolled with the
            // content, exactly as the original was: it is the room's light, not an element.
            wash

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Title, refresh indicator and stale strip as ONE composed unit. Hand-built,
                    // this screen ran its own `RefreshIndicator` next to `.refreshable`'s, so any
                    // pull past 400 ms showed two spinners.
                    Text("Library")
                        .type(ThemeType.screenTitle)
                        .foregroundStyle(ThemeColor.textPrimary)
                        .freshness(.catalogue, appModel: appModel, pullDriving: pullDriving)
                        .padding(.horizontal, ThemeMetrics.gutter)
                        .padding(.top, ThemeSpace.x2)

                    if appModel.sectionFailed {
                        InlineNotice(Copy.Notice.library) { Task { await appModel.reload() } }
                            .padding(.horizontal, ThemeMetrics.gutter).padding(.top, ThemeSpace.x3)
                    }

                    SkeletonGate(isLoading: appModel.loading && appModel.library.isEmpty) {
                        skeleton
                    } content: {
                        if appModel.library.isEmpty {
                            // Centred in the content area, not pinned to the top of it: the error
                            // card sat above ~1,000 pt of black while the identical card on Today
                            // was centred.
                            EmptyState(appModel.emptyStateCopy, prominence: .major,
                                       primary: emptyStateAction)
                                .padding(.horizontal, ThemeMetrics.gutter)
                                .centredState(contentH: contentHeight)
                        } else {
                            root
                        }
                    }
                }
                .padding(.bottom, ThemeMetrics.tabBarClearance)
            }
            .scrollIndicators(.hidden)
            .onScrollPhaseChange { _, phase in
                pullDriving = (phase == .tracking || phase == .interacting)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            .previouslyRefreshable { await appModel.reload() }
        }
        .scrollEdgeChrome()
        .overlay(alignment: .top) { washOverChrome }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $all) { route in
            LibraryAllView(initialStatus: route.status, initialReturning: route.returning,
                           onOpenDetail: onOpenDetail)
        }
        .onAppear { appModel.libQuery = "" }
    }

    /// The empty state's one action, and it is always a live one.
    private var emptyStateAction: () -> Void {
        appModel.loadError ? { Task { await appModel.reload() } } : onAddShow
    }

    /// The wash is taken from the first show on the first shelf — the same artwork the eye lands
    /// on first, so the room is lit by the thing you are looking at.
    private var washCover: String? {
        sections.first?.items.first?.cover ?? appModel.library.first?.cover
    }

    private var wash: some View {
        ArtBackdrop(url: washCover, height: LibraryView.washHeight,
                    intensity: LibraryView.washIntensity)
            .ignoresSafeArea(edges: .top)
    }

    /// The wash, drawn a second time OVER the scroll edge.
    ///
    /// `scrollEdgeChrome()` lays full canvas across the status-bar band — that is what stops a
    /// poster sitting on the clock, and it is not negotiable. But it also paints over the ambient
    /// wash, so the screen opened on a black bar exactly where the original opened on warm light.
    /// Re-drawing the wash on top of the veil, masked to the veil's OWN ramp, gives the band its
    /// colour back without letting a pixel of scrolling content through.
    private var washOverChrome: some View {
        let hold = max(0, min(1, ThemeMetrics.topSafeInset / max(ThemeMetrics.topChromeHeight, 1)))
        return ArtBackdrop(url: washCover, height: LibraryView.washHeight,
                           intensity: LibraryView.washIntensity)
            .frame(height: ThemeMetrics.topChromeHeight, alignment: .top)
            .clipped()
            .mask {
                LinearGradient(stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: hold),
                    .init(color: .black.opacity(0.34), location: hold + (1 - hold) * 0.45),
                    .init(color: .clear, location: 1),
                ], startPoint: .top, endPoint: .bottom)
            }
            .frame(maxWidth: .infinity)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// Tall enough that the warmth is still on the screen behind the first shelf, and gone before
    /// the second section — measured against `fresh/library-top.png`, which dies around 380 pt.
    private static let washHeight: CGFloat = 380
    /// The direction's band for a list screen is 0.55–0.7; the top of it, because this screen has
    /// no full-bleed hero of its own and the wash is the only art moment above the shelf.
    private static let washIntensity: Double = 0.68

    // MARK: - Root

    private var root: some View {
        VStack(alignment: .leading, spacing: ThemeMetrics.sectionGap) {
            GroupedList {
                // No icon TILE. A grouped row's symbol sits on the plate; a stroked 28-pt tile
                // inside a container at the bezel is what made this lone row read as a disabled
                // text field, and it was the first object on the screen.
                GroupedRow(symbol: "rectangle.stack", symbolTint: .clear,
                           title: "All titles", trailing: .chevron("\(appModel.library.count)"),
                           separator: false) {
                    all = AllTitlesRoute()
                }
            }
            .padding(.horizontal, ThemeMetrics.gutter)
            .padding(.top, ThemeSpace.x5)

            ForEach(sections) { section in
                VStack(alignment: .leading, spacing: ThemeMetrics.labelGap) {
                    SectionHeaderRow(section.key.label, count: section.items.count,
                                     actionLabel: seeAllLabel(section)) {
                        all = route(for: section.key)
                    }
                    .padding(.horizontal, ThemeMetrics.gutter)

                    if usesPosterShelf(section.key) {
                        posterShelf(section)
                    } else {
                        rowList(section)
                    }
                }
            }

            // The shelf ends and something says so. Without it the last row is followed by 190 pt
            // of #09090B and the screen simply stops. It is the same object that closes All
            // titles, so the two surfaces end the same way.
            Text(Copy.titles(appModel.library.count))
                .type(ThemeType.metadata)
                .foregroundStyle(ThemeColor.textDisabled)
                .numericFact(appModel.library.count)
                .frame(maxWidth: .infinity)
                .padding(.top, ThemeSpace.x2)
                .accessibilityHidden(true)
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
    private var sections: [RootSection] {
        var out: [RootSection] = []
        for shelf in appModel.libraryShelves {
            switch shelf.shelf {
            case .comingBack:
                // Already sorted soonest-first by `AppModel`, so the dated ones lead and the
                // partition preserves that order inside each half.
                let dated = shelf.franchises.filter { ReturnFact.of($0, appModel: appModel).dated }
                let undated = shelf.franchises.filter { !ReturnFact.of($0, appModel: appModel).dated }
                if !dated.isEmpty { out.append(RootSection(key: .returning, items: dated)) }
                if !undated.isEmpty { out.append(RootSection(key: .announced, items: undated)) }
            case .watching: out.append(RootSection(key: .watching, items: shelf.franchises))
            case .planned:  out.append(RootSection(key: .planned, items: shelf.franchises))
            case .finished: out.append(RootSection(key: .finished, items: shelf.franchises))
            }
        }
        return out.sorted { $0.key.rank < $1.key.rank }
    }

    /// Exactly one poster shelf on this screen, and it is the anticipation one. At accessibility
    /// sizes a horizontal shelf of 124-pt cards cannot hold a title, so it becomes rows.
    private func usesPosterShelf(_ key: LibrarySection) -> Bool { key == .returning && !isAX }

    /// One rule for every section: show a preview, and offer the rest. RETURNING having thirteen
    /// titles and no way to reach them while WATCHING had nine and a `See all` was the exact
    /// inversion of what a count is for.
    private static let previewCount = 6

    private func seeAllLabel(_ section: RootSection) -> String? {
        section.items.count > LibraryView.previewCount ? Copy.Action.seeAll : nil
    }

    private func shown(_ section: RootSection) -> [Franchise] {
        Array(section.items.prefix(LibraryView.previewCount))
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
    //
    // The shape of what is coming: the All-titles row, one captioned shelf that runs off the
    // trailing edge, one list of five. Composed from the shared atoms so the geometry is the
    // content's geometry — `SkeletonShelf(caption:)` reserves the caption line a `ShelfCard`
    // reserves, which is the 44-pt jump the panel measured at the swap.

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: ThemeMetrics.sectionGap) {
            SkeletonBlock(height: ThemeMetrics.rowCompact, radius: ThemeRadius.row)
                .padding(.horizontal, ThemeMetrics.gutter)

            VStack(alignment: .leading, spacing: ThemeMetrics.labelGap) {
                SkeletonLine(width: 92, height: 11)
                    .padding(.horizontal, ThemeMetrics.gutter)
                // Inside a (disabled) horizontal scroll view, exactly like the shelf it stands in
                // for. Five 124-pt cards are 668 pt wide; laid out as a plain stack that width
                // propagates up through the vertical scroll view's content, which then centres —
                // and the WHOLE loading screen renders 114 pt to the left, plate, rows and all.
                // A scroll view reports the width it was proposed, never its content's.
                ScrollView(.horizontal) {
                    SkeletonShelf(count: 5, size: PosterSize.shelfLarge.size,
                                  caption: true, titleLines: 2)
                        .padding(.leading, ThemeMetrics.gutter)
                }
                .scrollDisabled(true)
                .scrollIndicators(.hidden)
            }

            VStack(alignment: .leading, spacing: ThemeMetrics.labelGap) {
                SkeletonLine(width: 74, height: 11)
                VStack(spacing: 0) {
                    ForEach(0..<5, id: \.self) { _ in
                        SkeletonRow(poster: PosterSize.row.size, lines: [196, 108],
                                    posterRadius: PosterSize.row.radius,
                                    spacing: ThemeMetrics.artGap)
                    }
                }
            }
            .padding(.horizontal, ThemeMetrics.gutter)
        }
        .padding(.top, ThemeSpace.x5)
    }

    // MARK: - The one shelf

    private func posterShelf(_ section: RootSection) -> some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: ThemeMetrics.shelfGap) {
                ForEach(shown(section)) { f in
                    let fact = ReturnFact.of(f, appModel: appModel)
                    ShelfCard(title: f.title,
                              caption: fact.text,
                              // Amber is for a real next step. Every card in RETURNING has one
                              // now — the undated ones moved to their own section.
                              captionIsLead: fact.dated,
                              poster: f.cover,
                              slot: .shelfLarge,
                              zoomID: "lib/\(f.id)") {
                        onOpenDetail(f.id, "lib/\(f.id)")
                    }
                    .contextMenu { FranchiseContextMenu(f: f, appModel: appModel) }
                }
            }
            .padding(.leading, ThemeMetrics.gutter)
            // The posters carry an `.art` shadow; without this the scroll view clips it into a
            // hard grey line down each card's left edge.
            .padding(.vertical, 2)
        }
        // Art may run off the trailing edge; TYPE may not. See `shelfScroller`.
        .shelfScroller()
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }

    // MARK: - The lists

    private func rowList(_ section: RootSection) -> some View {
        let shown = shown(section)
        // At accessibility sizes the RETURNING shelf reflows into rows — correct adaptation — but
        // it also collapsed the largest artwork on the screen from 124×186 to 48×72, an 84 % cut
        // for exactly the users who need bigger targets. The type grows; the art does not shrink.
        let slot: PosterSize = (section.key == .returning && isAX) ? .shelfMedium : .row
        return VStack(spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { i, f in
                let facts = LibraryRowFacts.root(f, section: section.key, appModel: appModel,
                                                 accentAllowed: !isAX || i < 3)
                MediaRow(title: f.title,
                         meta: facts.meta,
                         lead: facts.lead,
                         poster: f.cover,
                         slot: slot,
                         separator: i < shown.count - 1,
                         zoomID: "lib/\(f.id)") {
                    onOpenDetail(f.id, "lib/\(f.id)")
                }
                .contextMenu { FranchiseContextMenu(f: f, appModel: appModel) }
            }
        }
        .padding(.horizontal, ThemeMetrics.gutter)
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

/// The one screen in the Library with controls on it. Rows sit on the canvas at `rowStandard` with
/// 48×72 art, under **pinned letter headers with an index rail** — thirty alphabetical rows with
/// no section headers and no index made the sort order invisible until you scrolled, and at the
/// stated 300 titles reaching "Vinland Saga" was a flick-scroll lottery.
struct LibraryAllView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    let onOpenDetail: (_ franchiseId: String, _ zoomID: String) -> Void

    /// The incoming filter is seeded into `@State` at INIT, not applied in `onAppear`. Applied
    /// late, the screen builds once unfiltered and once filtered — the user sees the whole library
    /// flash past on the way to the six rows they asked for, and the rows that survive both passes
    /// can keep the first pass's copy (rows under a `Watching` chip still reading "Watching").
    init(initialStatus: WatchStatus? = nil, initialReturning: ReturnScope? = nil,
         onOpenDetail: @escaping (_ franchiseId: String, _ zoomID: String) -> Void) {
        self.onOpenDetail = onOpenDetail
        _status = State(initialValue: initialStatus)
        _returning = State(initialValue: initialReturning)
    }

    enum Sort: String, CaseIterable, Identifiable {
        case title = "Title", recent = "Recently updated", progress = "Most left to watch"
        var id: String { rawValue }
    }
    enum Display: String, CaseIterable, Identifiable {
        case posters = "Posters", list = "List"
        var id: String { rawValue }
    }

    @State private var query = ""
    @State private var sort: Sort = .title
    @State private var status: WatchStatus?
    @State private var returning: ReturnScope?
    @State private var display: Display = .list
    @State private var unwatchedOnly = false
    @State private var showArrange = false
    @State private var contentWidth: CGFloat = 0
    @State private var railTouching = false

    private var now: Int64 { appModel.now }
    private var isAX: Bool { typeSize.isAccessibilitySize }

    private var results: [Franchise] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        var arr = appModel.library.filter { f in
            (status == nil || f.effectiveStatus == status)
            && (returning == nil
                || LibraryShelving.section(of: f, appModel: appModel) == returning?.section)
            && (q.isEmpty || f.title.lowercased().contains(q))
            && (!unwatchedOnly || (f.currentPart.map { $0.markTarget(now: now) > $0.progress } ?? false))
        }
        switch sort {
        case .title: arr.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .recent: arr.sort { ($0.lastAiredSortKey, $0.title) > ($1.lastAiredSortKey, $1.title) }
        case .progress: arr.sort { ($0.continueBacklog, $0.title) > ($1.continueBacklog, $1.title) }
        }
        return arr
    }

    /// A filter is a thing the user chose that hides rows. The **view mode** is not one — which is
    /// why the shipped "Posters … Clear" row offered a destructive-sounding action against a state
    /// that was nowhere on screen, and why the amber glyph in the bar meant nothing you could see.
    private var hasFilters: Bool {
        status != nil || returning != nil || unwatchedOnly || sort != .title
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !activeChips.isEmpty { chipRow }
                if results.isEmpty {
                    EmptyState(query.isEmpty ? .noFilterMatches : .noSearchResults(query: query),
                               prominence: .section,
                               primary: hasFilters ? { resetFilters() } : nil)
                        .padding(.horizontal, ThemeMetrics.gutter)
                        .padding(.top, ThemeMetrics.heroClearance)
                } else if display == .posters {
                    grid.padding(.top, ThemeSpace.x3)
                } else {
                    list.padding(.top, ThemeSpace.x1)
                }
                if !results.isEmpty {
                    Text(Copy.titles(results.count))
                        .type(ThemeType.metadata).foregroundStyle(ThemeColor.textDisabled)
                        .frame(maxWidth: .infinity)
                        .padding(.top, ThemeSpace.x6)
                }
            }
            .padding(.top, ThemeSpace.x2)
            .padding(.bottom, ThemeMetrics.tabBarClearance)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { contentWidth = $0 }
        }
        .scrollIndicators(.hidden)
        .background(ThemeColor.canvas.ignoresSafeArea())
        // A pushed screen owns a real navigation bar, so it gets our BOTTOM edge only — but it
        // needs that: without it, posters cut against the tab-bar glass with a hard horizon.
        //
        // And only the bottom SYSTEM effect is suppressed. `scrollEdgeChrome()` hides it
        // `for: .all`, which on a pushed screen with a hidden toolbar background left nothing at
        // all behind the navigation bar and its search drawer: scrolled rows rode over the title,
        // over the search field and over the clock, a poster sitting on the Dynamic Island — the
        // one defect the whole chrome pass exists to kill. The system's own top effect is the
        // correct background for a system bar, so it stays and the toolbar keeps it.
        .scrollEdgeChromeBody(top: false, bottom: true)
        .scrollEdgeEffectHidden(true, for: .bottom)
        .overlay(alignment: .trailing) { if showsRail { indexRail } }
        .navigationTitle("All titles")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search your library")
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
            ArrangeSheet(sort: $sort, status: $status, display: $display,
                         unwatchedOnly: $unwatchedOnly, onReset: resetFilters)
                // Resolved BEFORE presentation from the row count and the type size. A detent that
                // measures itself cannot be right on the first frame: the sheet grew 68 pt under
                // the user's eye and only looked correct the second time it opened.
                .presentationDetents([.custom(ArrangeDetent.self), .large])
                .presentationDragIndicator(.visible)
                // Without this the sheet's plate stopped 34 pt short of the screen and the
                // undimmed list showed through the gap — it read as a rendering failure.
                .presentationBackground(ThemeColor.canvasRaised)
        }
        // Installed before the sheet's picker is built (the proxy only reaches controls made
        // after it is set), which is why it lives here and not in the sheet.
        .onAppear { SegmentedAppearance.install() }
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
        if let status {
            chips.append(Chip(id: "status", text: LibraryRowFacts.listState(status: status)) {
                self.status = nil
            })
        }
        if let returning {
            chips.append(Chip(id: "returning", text: returning.label) { self.returning = nil })
        }
        if unwatchedOnly {
            chips.append(Chip(id: "unwatched", text: "Unwatched only") { unwatchedOnly = false })
        }
        if sort != .title {
            chips.append(Chip(id: "sort", text: sort.rawValue) { sort = .title })
        }
        return chips
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
                        HStack(spacing: 5) {
                            Text(chip.text)
                            Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                        }
                    }
                    .buttonStyle(FilterChipStyle())
                    .accessibilityLabel("\(chip.text). Remove filter")
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
        sort = .title; status = nil; returning = nil; unwatchedOnly = false
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
    private var sections: [TitleSection] {
        // One bucket when the list is not sectioned. A `Section` inside a `LazyVGrid` starts a new
        // ROW even when its header is an `EmptyView`, so leaving the per-letter buckets in place
        // and merely hiding the headers laid a ten-title poster wall out two-then-one down the
        // page with holes where the letters changed.
        guard isSectioned else { return [TitleSection(key: "", items: results)] }
        switch sort {
        case .title:
            var buckets: [String: [Franchise]] = [:]
            for f in results { buckets[LibraryAllView.indexKey(f.title), default: []].append(f) }
            return buckets.keys.sorted { a, b in
                if (a == "#") != (b == "#") { return b == "#" }
                return a < b
            }.map { TitleSection(key: $0, items: buckets[$0] ?? []) }
        case .recent:
            var order: [String] = []
            var buckets: [String: [Franchise]] = [:]
            for f in results {
                let key = LibraryAllView.monthKey(f.lastAiredSortKey)
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
    private var isSectioned: Bool { sort != .progress && results.count > LibraryAllView.sectionFloor }

    static let sectionFloor = 24

    /// Twenty-four rows is roughly two and a half screens; past that an alphabet is faster than a
    /// flick, and at the stated 300 titles it is the difference between finding "Vinland Saga" and
    /// hunting for it. Suppressed for every other sort order, where A–Z would be a lie.
    private var showsRail: Bool {
        sort == .title && results.count > LibraryAllView.sectionFloor && !isAX
    }

    /// "A"…"Z" and "#" for everything that does not start with a letter.
    static func indexKey(_ title: String) -> String {
        let folded = title.folding(options: [.diacriticInsensitive, .caseInsensitive],
                                   locale: .current)
        guard let first = folded.first(where: { $0.isLetter || $0.isNumber }) else { return "#" }
        return first.isLetter ? String(first).uppercased() : "#"
    }

    private static func monthKey(_ sortKey: Int64) -> String {
        guard sortKey > 0 else { return "No date" }
        let date = Date(timeIntervalSince1970: TimeInterval(sortKey))
        return monthLabel.string(from: date)
    }

    private static let monthLabel: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMMyyyy")
        return formatter
    }()

    /// A pinned strip, not a floating label: content scrolls UNDER it, so it is opaque canvas with
    /// a quiet rule beneath — the same separator the rows carry.
    private func sectionHeader(_ key: String) -> some View {
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
        .background(ThemeColor.canvas)
        .overlay(alignment: .bottom) {
            Rectangle().fill(ThemeColor.separatorQuiet).frame(height: 1)
                .padding(.leading, ThemeMetrics.gutter)
        }
        .accessibilityAddTraits(.isHeader)
    }

    /// The A–Z rail. `textDisabled` at rest — it is a hint, not content — and `accent` under the
    /// finger, with one selection tick per letter it crosses.
    private var indexRail: some View {
        let keys = sections.map(\.key)
        return VStack(spacing: 0) {
            ForEach(keys, id: \.self) { key in
                Text(key)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(railTouching ? ThemeColor.accent : ThemeColor.textDisabled)
                    .frame(width: 22, height: LibraryAllView.railStep)
            }
        }
        .padding(.vertical, ThemeSpace.x2)
        .background {
            Capsule().fill(railTouching ? ThemeColor.surfaceRaised : Color.clear)
        }
        .padding(.trailing, 4)
        .padding(.bottom, ThemeMetrics.tabBarClearance / 2)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    railTouching = true
                    let i = Int(value.location.y / LibraryAllView.railStep)
                    let clamped = max(0, min(keys.count - 1, i))
                    guard keys.indices.contains(clamped) else { return }
                    let target = sections[clamped].items.first?.id
                    guard target != railTarget else { return }
                    railTarget = target
                    FeedbackCoordinator.fire(.selection)
                    railScroll = sections[clamped].key
                }
                .onEnded { _ in railTouching = false; railTarget = nil; railScroll = nil }
        )
        .animation(ThemeMotion.pick(ThemeMotion.uiMicro, reduceMotion: reduceMotion), value: railTouching)
        .accessibilityHidden(true)
    }

    @State private var railTarget: String?
    @State private var railScroll: String?

    private static let railStep: CGFloat = 15

    // MARK: - List

    private var list: some View {
        // LAZY, and SECTIONED. At the stated 300-title library an eager `VStack` instantiates 300
        // `MediaRow`s and 300 `RemoteImageView`s on push, and thirty unbroken alphabetical rows
        // make the sort order invisible until you have already scrolled past it.
        ScrollViewReader { proxy in
            LazyVStack(spacing: 0, pinnedViews: isSectioned ? [.sectionHeaders] : []) {
                ForEach(sections) { section in
                    Section {
                        ForEach(Array(section.items.enumerated()), id: \.element.id) { i, f in
                            row(f, last: i == section.items.count - 1)
                        }
                    } header: {
                        if isSectioned { sectionHeader(section.key).id("sec-\(section.key)") }
                    }
                }
            }
            .padding(.horizontal, ThemeMetrics.gutter)
            .onChange(of: railScroll) { _, key in
                guard let key else { return }
                proxy.scrollTo("sec-\(key)", anchor: .top)
            }
        }
    }

    private func row(_ f: Franchise, last: Bool) -> some View {
        let facts = LibraryRowFacts.catalogue(f, appModel: appModel, stateIsGiven: status != nil)
        return MediaRow(title: f.title,
                        meta: facts.meta,
                        lead: facts.lead,
                        poster: f.cover,
                        slot: .row,
                        separator: !last,
                        zoomID: "all/\(f.id)") {
            onOpenDetail(f.id, "all/\(f.id)")
        }
        .contextMenu { FranchiseContextMenu(f: f, appModel: appModel) }
    }

    // MARK: - Poster wall

    /// Three columns that exactly fill the gutters instead of an adaptive grid that leaves a ragged
    /// 30 pt down the trailing edge — and the same pinned headers the list carries, because a wall
    /// of 300 covers needs the alphabet even more than a list of them does.
    private var grid: some View {
        let columns = 3
        let available = max(0, contentWidth - ThemeMetrics.gutter * 2)
        let cellWidth = available > 0
            ? (available - ThemeMetrics.shelfGap * CGFloat(columns - 1)) / CGFloat(columns)
            : PosterSize.shelfLarge.size.width
        return ScrollViewReader { proxy in
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(cellWidth), spacing: ThemeMetrics.shelfGap,
                                                         alignment: .top),
                                     count: columns),
                      alignment: .leading, spacing: ThemeSpace.x6,
                      pinnedViews: isSectioned ? [.sectionHeaders] : []) {
                ForEach(sections) { section in
                    Section {
                        ForEach(section.items) { f in cell(f, width: cellWidth) }
                    } header: {
                        if isSectioned {
                            sectionHeader(section.key)
                                .padding(.horizontal, -ThemeMetrics.gutter)
                                .id("sec-\(section.key)")
                        }
                    }
                }
            }
            .padding(.horizontal, ThemeMetrics.gutter)
            .onChange(of: railScroll) { _, key in
                guard let key else { return }
                proxy.scrollTo("sec-\(key)", anchor: .top)
            }
        }
    }

    private func cell(_ f: Franchise, width: CGFloat) -> some View {
        // Resolved once — calling the accessor twice to pick a colour is how a caption and its
        // colour drift apart.
        let caption = gridCaption(f)
        return Button { onOpenDetail(f.id, "all/\(f.id)") } label: {
            VStack(alignment: .leading, spacing: ThemeSpace.x2) {
                PosterSlot(url: f.cover, width: width, height: (width * 3 / 2).rounded(),
                           radius: ThemeRadius.poster, shadow: .art)
                    // A wall of 300 covers cannot say which ones are waiting on you; the caption
                    // carries a status word and nothing else. The ring is the fact the caption
                    // already computed, drawn where the eye is: on the art.
                    .overlay(alignment: .bottomLeading) {
                        if caption?.lead == true { progressRing(f) }
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text(f.title)
                        .type(ThemeType.shelfTitle).foregroundStyle(ThemeColor.textPrimary)
                        .lineLimit(2, reservesSpace: !isAX)
                        .multilineTextAlignment(.leading)
                    if let caption {
                        Text(caption.text)
                            .type(ThemeType.shelfCaption)
                            .foregroundStyle(caption.lead ? ThemeColor.accent : ThemeColor.textSecondary)
                            .lineLimit(1)
                    }
                }
                .frame(width: width, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle(radius: ThemeRadius.poster))
        .contextMenu { FranchiseContextMenu(f: f, appModel: appModel) }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func progressRing(_ f: Franchise) -> some View {
        // Only once there is an arc to draw. At zero watched the ring is a bare grey circle sitting
        // on the artwork saying nothing the caption ("Episode 1 next") does not already say.
        if let p = f.currentPart, !p.isUpcoming, p.progress > 0 {
            let target = max(1, p.markTarget(now: now))
            let fraction = min(1, max(0, Double(p.progress) / Double(target)))
            ZStack {
                Circle().stroke(Color.black.opacity(0.55), lineWidth: 3)
                Circle().trim(from: 0, to: fraction)
                    .stroke(ThemeColor.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 18, height: 18)
            .padding(ThemeSpace.x2)
            .accessibilityHidden(true)
        }
    }

    /// The grid cell is ~136 pt wide, not 360 — so it gets the SHORTEST honest form of the same
    /// facts. Board 09's rule is to drop a fact, never to truncate one.
    private func gridCaption(_ f: Franchise) -> (text: String, lead: Bool)? {
        if let step = LibraryRowFacts.progress(f, now: now) {
            // "Season 7 · Episode 2 next" is 25 characters in a 136-pt cell; the season goes and
            // the episode stays.
            if let p = f.currentPart, !p.isReleasing, p.markTarget(now: now) > p.progress {
                return (Copy.Progress.episodeNext(p.progress + 1), true)
            }
            return (step, true)
        }
        // Under a status chip the state word is already on screen once; the cell says what the
        // thing is instead. It keeps its caption line either way, so the captions stay aligned.
        return (status == nil ? LibraryRowFacts.listState(f) : LibraryRowFacts.identity(f), false)
    }
}

// MARK: - Segmented selection

/// Selection everywhere in this app is `accent`; a stock segmented control marks it with a grey
/// fill, which on a dark ground reads as *disabled* rather than *chosen* — it was the one control
/// in the app whose selected state used a different language from every other.
///
/// SwiftUI exposes no per-view hook for the selected segment, and `.tint` does not reach it, so
/// this goes through the appearance proxy. There is exactly one segmented control in the app
/// (`View as`), so a global proxy is the whole of its blast radius.
@MainActor
private enum SegmentedAppearance {
    private static var installed = false

    static func install() {
        guard !installed else { return }
        installed = true
        let proxy = UISegmentedControl.appearance()
        proxy.selectedSegmentTintColor = UIColor(ThemeColor.accent)
        proxy.backgroundColor = UIColor(ThemeColor.surfaceRaised)
        proxy.setTitleTextAttributes([.foregroundColor: UIColor(ThemeColor.onAccent)], for: .selected)
        proxy.setTitleTextAttributes([.foregroundColor: UIColor(ThemeColor.textSecondary)], for: .normal)
    }
}

// MARK: - Chips

/// An ACTIVE filter chip: `accentSoft` ground, `accent` label. Distinct from `ChipButtonStyle`,
/// whose selected state is a solid accent capsule meant for a primary choice (a search scope) —
/// four solid amber capsules above a list is louder than anything on the screen they are filtering.
///
/// SHARED-FILE REQUEST: this belongs in `Primitives.swift` as a prominence on `ChipButtonStyle`.
private struct FilterChipStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .type(ThemeType.metadataEmphasis)
            .foregroundStyle(ThemeColor.accent)
            .padding(.horizontal, 12)
            .frame(minHeight: 32)
            .background {
                Capsule().fill(configuration.isPressed ? ThemeColor.surfacePressed : ThemeColor.accentSoft)
            }
            .contentShape(Capsule())
            .frame(minHeight: 44)
            // `pressFeedback` is fileprivate to `Primitives.swift`; the same 0.985 scale, honoured
            // under Reduce Motion. (SHARED-FILE REQUEST: raise its visibility.)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(ThemeMotion.pick(ThemeMotion.uiPress, reduceMotion: reduceMotion),
                       value: configuration.isPressed)
    }
}

// MARK: - Sort & Filter

/// The detent, resolved before the sheet is on screen.
///
/// `arrangeHeight` used to start at a 340-pt guess and be corrected by `onGeometryChange` feeding
/// `.presentationDetents([.height(h)])`, so the sheet grew 68 pt under the user's eye on first open
/// and only looked right the second time. A custom detent computes from what the sheet actually
/// contains — four rows, two groups, a header — scaled by the type size, and is correct on frame 1.
private enum ArrangeGeometry {
    /// What the detent measures: three rows in the first group, one in the second.
    static let rowCount: CGFloat = 4
    /// Header (52) + its top pad (12) + groups' top pad (20) + the gap between groups (30) +
    /// bottom pad (24) + the home-indicator strip a sheet's scroll view inherits (34).
    /// Header (52) + its top pad (12) + the groups' top pad (20) + the gap between the groups (30)
    /// + the bottom pad (24) + the home-indicator strip a sheet's scroll view inherits (34) — less
    /// the 42 pt the sheet measured under that sum on the simulator. A detent computed purely from
    /// first principles left 42 pt of void beneath the last row.
    static let chrome: CGFloat = 52 + 12 + 20 + 30 + 24 + 34 - 42
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
/// Titled **Sort & Filter**, because "Arrange" is Files.app's word for ordering a grid and this
/// sheet holds a sort, a status filter, an unwatched filter and a view toggle. `Unwatched only` is
/// a filter and now sits with the other filter; `View` is left holding the only thing that is
/// actually a view choice, so neither group needs a label to explain itself.
///
/// The header is hand-built rather than a `NavigationStack` toolbar: on this OS a toolbar button
/// renders as a filled glass capsule, which made `Done` the single heaviest object in a sheet whose
/// whole job is to be quiet. `Done` is a link. `Reset` is a link. The rows are the content.
private struct ArrangeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @Binding var sort: LibraryAllView.Sort
    @Binding var status: WatchStatus?
    @Binding var display: LibraryAllView.Display
    @Binding var unwatchedOnly: Bool
    let onReset: () -> Void

    private var isAX: Bool { typeSize.isAccessibilitySize }

    private var hasFilters: Bool { sort != .title || status != nil || unwatchedOnly }

    static let title = "Sort & Filter"

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
            GroupedList {
                valueRow(title: "Sort by", value: sort.rawValue, separator: true) {
                    Picker("Sort by", selection: sortBinding) {
                        ForEach(LibraryAllView.Sort.allCases) { s in
                            Text(s.rawValue).tag(s)
                        }
                    }
                    .pickerStyle(.inline)
                }
                valueRow(title: "Status", value: statusValue, separator: true) {
                    Picker("Status", selection: statusBinding) {
                        Text(ArrangeSheet.anyStatus).tag(WatchStatus?.none)
                        ForEach(WatchStatus.menuOrder, id: \.self) { s in
                            Text(LibraryRowFacts.listState(status: s)).tag(WatchStatus?.some(s))
                        }
                    }
                    .pickerStyle(.inline)
                }
                // A filter, filed with the filters. It spent the shipped build under VIEW.
                GroupedRow(title: "Unwatched only",
                           trailing: .toggle(unwatchedBinding), separator: false)
            }

            GroupedList { viewAsRow }
        }
    }

    /// Board 05 asks for a segmented View. At accessibility sizes two words cannot share a row with
    /// their label, so the control drops under it rather than squeezing to 60 pt.
    private var viewAsRow: some View {
        let picker = Picker("View as", selection: displayBinding) {
            ForEach(LibraryAllView.Display.allCases) { d in
                Text(d.rawValue).tag(d)
            }
        }
        .pickerStyle(.segmented)

        return Group {
            if isAX {
                VStack(alignment: .leading, spacing: ThemeSpace.x2) {
                    Text("View as").type(ThemeType.body).foregroundStyle(ThemeColor.textPrimary)
                    picker
                }
                .padding(.vertical, ThemeSpace.x3)
            } else {
                HStack(spacing: ThemeSpace.x3) {
                    Text("View as").type(ThemeType.body).foregroundStyle(ThemeColor.textPrimary)
                    Spacer(minLength: ThemeSpace.x3)
                    picker.frame(width: 168)
                }
            }
        }
        .padding(.leading, 14).padding(.trailing, 14)
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
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ThemeColor.textDisabled)
            }
            .padding(.leading, 14).padding(.trailing, 16)
            .frame(minHeight: ThemeMetrics.rowCompact)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                if separator {
                    Rectangle().fill(ThemeColor.separatorQuiet)
                        .frame(height: 1).padding(.leading, 14)
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
        .frame(height: 52)
        .padding(.top, ThemeSpace.x3)
    }

    /// "Any", not "Any status": the row's own label already says Status, and repeating the noun in
    /// its own value is the tell of a control that was written twice.
    private static let anyStatus = "Any"

    private var statusValue: String {
        status.map { LibraryRowFacts.listState(status: $0) } ?? ArrangeSheet.anyStatus
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

    private var statusBinding: Binding<WatchStatus?> {
        Binding(get: { status }, set: { new in select(status, new) { status = new } })
    }

    private var displayBinding: Binding<LibraryAllView.Display> {
        Binding(get: { display }, set: { new in select(display, new) { display = new } })
    }

    private var unwatchedBinding: Binding<Bool> {
        Binding(get: { unwatchedOnly }, set: { new in select(unwatchedOnly, new) { unwatchedOnly = new } })
    }
}
