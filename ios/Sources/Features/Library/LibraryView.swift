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
//    three header grammars across three tab roots. It is a real large title that collapses inline.
//  * **"Unwatched only" could contradict "Status"** and did not say unwatched *what*. It is a
//    Status value now ("Has unwatched episodes"), and its predicate stopped counting unaired
//    episodes as unwatched. Sort gained "Recently added" and a direction. See `StatusFilter`.
//
struct LibraryView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dynamicTypeSize) private var typeSize
    let onOpenDetail: (_ franchiseId: String, _ zoomID: String) -> Void
    /// Where shows are added. Today and Schedule already take this; the Library's empty state
    /// printed the same `Add a show` label with nothing behind it.
    var onAddShow: () -> Void = {}

    @State private var all: AllTitlesRoute?
    /// A route another screen asked for ("View all N updates", a Profile stat); consumed once.
    @Binding var requestedAll: AllTitlesRoute?
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
        var unwatchedOnly: Bool = false
        var id: String { "\(status?.rawValue ?? "-")/\(returning?.rawValue ?? "-")/\(unwatchedOnly)" }
    }

    var body: some View {
        ZStack(alignment: .top) {
            ThemeColor.canvas.ignoresSafeArea()
            // The ambient identity wash. Pinned to the screen rather than scrolled with the
            // content, exactly as the original was: it is the room's light, not an element.
            wash

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // The refresh indicator and the stale strip, composed by the shared modifier
                    // that arbitrates them against `.refreshable`'s own spinner. The screen TITLE
                    // is no longer part of this stack: it is a real `navigationTitle` now, so the
                    // three tab roots stop having three header grammars (see `body`'s toolbar).
                    Color.clear.frame(height: 0)
                        .freshness(.catalogue, appModel: appModel, pullDriving: pullDriving)
                        .padding(.horizontal, ThemeMetrics.gutter)

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
                            // `ambient: false`: this screen already owns an ambient wash, and the
                            // plate's own radial bloom stacked on it met the canvas in a hard
                            // full-width step (measured: 10 -> 35 in one pixel row at y≈302 pt).
                            // One wash per screen, and on this screen it is the screen's.
                            EmptyState(appModel.emptyStateCopy, prominence: .major,
                                       primary: emptyStateAction, ambient: false)
                                .padding(.horizontal, ThemeMetrics.gutter)
                                .centredState(contentH: contentHeight)
                        } else {
                            root
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
        // BOTTOM only. The top edge belongs to a real navigation bar now: the screen used to hide
        // the bar and draw "Library" as scrolling content, so nothing named the screen once you had
        // scrolled, and the app had three different header grammars across its three tab roots
        // (Library hand-drawn, Schedule inline, Search large). A large title that collapses to
        // inline is the system's answer and it is the same one Search already gives.
        .scrollEdgeChromeBody(top: false, bottom: true)
        .scrollEdgeEffectHidden(true, for: .bottom)
        // `.hard`, the style Schedule already uses: the soft effect let a poster sliver and a
        // blurred title ghost through under the clock. A tab root's status-bar band is opaque.
        .scrollEdgeEffectStyle(.hard, for: .top)
        .navigationTitle("Library")
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.visible, for: .navigationBar)
        .navigationDestination(item: $all) { route in
            LibraryAllView(initialStatus: route.status, initialReturning: route.returning, initialUnwatchedOnly: route.unwatchedOnly,
                           onOpenDetail: onOpenDetail)
        }
        .onAppear { appModel.libQuery = "" }
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
    private var washCover: String? {
        sections.first?.items.first?.cover ?? appModel.library.first?.cover
    }

    private var wash: some View {
        // With no artwork in the library there is nothing for the wash to be ABOUT, and a blurred
        // nothing renders as a near-black band — so first run gets the app's own colour instead,
        // taller and softer. It is the first frame a new user and an App Store reviewer see, and
        // it should carry the product's identity rather than none.
        let firstRun = washCover == nil
        return ArtBackdrop(url: washCover,
                           tint: firstRun ? ThemeColor.accent : nil,
                           height: firstRun ? 520 : LibraryView.washHeight,
                           intensity: firstRun ? 0.5 : LibraryView.washIntensity)
            .ignoresSafeArea(edges: .top)
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
            allTitlesRow
                .padding(.top, ThemeSpace.x3)

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
                // `textTertiary`, like All titles' matching footer: `textDisabled` is the chevron
                // ink (decoration, 3:1), never a line of type.
                .foregroundStyle(ThemeColor.textTertiary)
                .numericFact(appModel.library.count)
                .frame(maxWidth: .infinity)
                .padding(.top, ThemeSpace.x2)
                .accessibilityHidden(true)
        }
    }

    /// The catalogue's front door, and it is **not a plate**.
    ///
    /// Shipped, this was a `GroupedList` row: a lone full-width filled rectangle at radius 16 with
    /// a leading glyph and grey trailing text, sitting directly under a large title — which is,
    /// pixel for pixel, where iOS puts a search field, and it is literally the search field the row
    /// opens one tap later. "Looks like a disabled text field" stopped being a metaphor.
    ///
    /// A hairline is the one thing a text field never has. So: canvas ground, an accent glyph, the
    /// count in the same `sectionLabel` the section headers below it use, and a rule underneath
    /// inset to the title exactly like every list row on this screen. It now reads as what it is —
    /// the head of the list, in the list's own grammar.
    private var allTitlesRow: some View {
        Button { all = AllTitlesRoute() } label: {
            HStack(spacing: ThemeSpace.x3) {
                Image(systemName: "rectangle.stack")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(ThemeColor.accent)
                    .frame(width: 26)
                Text(Copy.Heading.allTitles)
                    .type(ThemeType.rowTitle)
                    .foregroundStyle(ThemeColor.textPrimary)
                Spacer(minLength: ThemeSpace.x3)
                Text("\(appModel.library.count)")
                    .type(ThemeType.sectionLabel)
                    .foregroundStyle(ThemeColor.textTertiary)
                    .monospacedDigit()
                    .numericFact(appModel.library.count)
                Image(systemName: "chevron.forward")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ThemeColor.textDisabled)
                    .frame(width: 11, alignment: .trailing)
            }
            .padding(.horizontal, ThemeMetrics.gutter)
            .frame(minHeight: ThemeMetrics.rowCompact)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                Rectangle().fill(ThemeColor.separatorQuiet).frame(height: 1)
                    .padding(.leading, ThemeMetrics.gutter + 26 + ThemeSpace.x3)
            }
        }
        .buttonStyle(RowPressStyle())
        .accessibilityLabel("\(Copy.Heading.allTitles), \(Copy.titles(appModel.library.count))")
        .accessibilityHint("Opens your whole library, with search, sorting and filters")
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
            // The All-titles row is a hairline row on the canvas now, not a plate — so its
            // stand-in is a title-width line, not a 56-pt filled block.
            SkeletonLine(width: 140, height: 17)
                .padding(.horizontal, ThemeMetrics.gutter)
                .frame(height: ThemeMetrics.rowCompact, alignment: .center)

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
                              // `soon`, not `dated`. Every visible caption on this shelf was amber
                              // — six accent strings, none of them an action — because a date in
                              // 2027 counted as a "next step". Inside the 60-day horizon the date
                              // leads; outside it, it is a fact in grey. The catalogue reads the
                              // same flag, so a show cannot be amber here and grey there.
                              captionIsLead: fact.soon,
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
        // At accessibility sizes the RETURNING shelf reflows into rows — correct adaptation. It
        // reflowed into 112×168 art, though, which at AX1 made 182-pt rows carrying two short lines
        // vertically centred beside the poster: a 240×160 pt hole in every one of them. 60×90 is
        // still four times the area of a `.row` thumb (the art does not collapse for the readers
        // who need it most) and the TEXT sets the row height again, which is what removes the hole.
        let slot: PosterSize = (section.key == .returning && isAX) ? .searchRow : .row
        return VStack(spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { i, f in
                let facts = LibraryRowFacts.root(f, section: section.key, appModel: appModel)
                MediaRow(title: f.title,
                         meta: facts.meta,
                         lead: facts.lead,
                         poster: f.cover,
                         slot: slot,
                         separator: i < shown.count - 1,
                         hint: "Opens the show",
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
         initialSort: Sort = .title, initialUnwatchedOnly: Bool = false,
         onOpenDetail: @escaping (_ franchiseId: String, _ zoomID: String) -> Void) {
        self.onOpenDetail = onOpenDetail
        _status = State(initialValue: initialUnwatchedOnly ? .unwatched
                                                           : (initialStatus.map(StatusFilter.status) ?? .any))
        _returning = State(initialValue: initialReturning)
        _sort = State(initialValue: initialSort)
    }

    enum Sort: String, CaseIterable, Identifiable {
        /// "Recently added" is backed by `Subscription.addedAt`, which the API already sends. It is
        /// the one order a user needs after importing or adding twenty shows — "what did I just
        /// add" — and the shipped sheet had no way to produce it.
        case title = "Title", added = "Recently added",
             recent = "Recently updated", progress = "Most left to watch"
        var id: String { rawValue }
    }
    enum Display: String, CaseIterable, Identifiable {
        case posters = "Posters", list = "List"
        var id: String { rawValue }
    }

    /// **One** single-select control for "which titles", so it cannot contradict itself.
    ///
    /// Shipped, "Status" and "Unwatched only" were independent: Status = Watched **and** Unwatched
    /// only = on produced an empty list with nothing on screen to explain why, and "Unwatched" did
    /// not say unwatched *what* — the identical word on Schedule's menu means episodes. Folding the
    /// toggle in as a Status VALUE makes the contradiction unrepresentable and names its noun.
    enum StatusFilter: Hashable, Identifiable {
        case any
        case status(WatchStatus)
        /// Titles with at least one episode you have not watched yet.
        case unwatched

        var id: String {
            switch self {
            case .any: return "any"
            case .status(let s): return s.rawValue
            case .unwatched: return "unwatched"
            }
        }

        var label: String {
            switch self {
            case .any: return "Any"
            case .status(let s): return Copy.Status(s)
            case .unwatched: return "Has unwatched episodes"
            }
        }

        /// The chip form. A chip states the criterion, and "Any" is not one.
        var chip: String? { self == .any ? nil : label }

        /// True when this filter already tells the reader the row's list state, so the rows can
        /// stop repeating it. `.unwatched` spans several statuses, so it tells them nothing.
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
    @State private var returning: ReturnScope?
    @State private var display: Display = .list
    @State private var showArrange = false
    @State private var contentWidth: CGFloat = 0
    @State private var railTouching = false
    /// Ties each pinned section header to its rotor entry, so VoiceOver can jump between letters
    /// even while the lazy stack has not built the rows in between.
    @Namespace private var rotorSpace

    private var now: Int64 { appModel.now }
    private var isAX: Bool { typeSize.isAccessibilitySize }

    /// Episodes that **exist and have aired** and you have not watched.
    ///
    /// The shipped predicate was `markTarget > progress` with no `isUpcoming` guard, so a title
    /// whose current part is a not-yet-premiered season counted as having unwatched episodes: the
    /// list came back holding "Black Clover · Watched", "Chainsaw Man · Watched" and "ONE PIECE ·
    /// Caught up" under a filter that says the opposite. A filter that returns rows contradicting
    /// its own name is worse than no filter.
    private func hasUnwatched(_ f: Franchise) -> Bool {
        guard let p = f.currentPart, !p.isUpcoming else { return false }
        return p.markTarget(now: now) > p.progress
    }

    private var results: [Franchise] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        var arr = appModel.library.filter { f in
            let statusOK: Bool
            switch status {
            case .any: statusOK = true
            case .status(let s): statusOK = f.effectiveStatus == s
            case .unwatched: statusOK = hasUnwatched(f)
            }
            return statusOK
                && (returning == nil
                    || LibraryShelving.section(of: f, appModel: appModel) == returning?.section)
                && (q.isEmpty || f.title.lowercased().contains(q))
        }
        switch sort {
        case .title: arr.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        // `addedAt` is absent in older server responses; an unknown date sorts LAST in the default
        // (newest-first) order rather than pretending to be 1970.
        case .added: arr.sort { ($0.subscription?.addedAt ?? .min, $0.title.lowercased())
                                > ($1.subscription?.addedAt ?? .min, $1.title.lowercased()) }
        case .recent: arr.sort { ($0.lastAiredSortKey, $0.title) > ($1.lastAiredSortKey, $1.title) }
        case .progress: arr.sort { ($0.continueBacklog, $0.title) > ($1.continueBacklog, $1.title) }
        }
        return sortAscending ? arr.reversed() : arr
    }

    /// A filter is a thing the user chose that hides rows. The **view mode** is not one — which is
    /// why the shipped "Posters … Clear" row offered a destructive-sounding action against a state
    /// that was nowhere on screen, and why the amber glyph in the bar meant nothing you could see.
    private var hasFilters: Bool {
        status != .any || returning != nil || sort != .title || sortAscending
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
                        .type(ThemeType.metadata).foregroundStyle(ThemeColor.textTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, ThemeSpace.x6)
                }
            }
            .padding(.top, ThemeSpace.x2)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { contentWidth = $0 }
        }
        .scrollIndicators(.hidden)
        // The densest artwork screen in the app opened on flat #09090B with a grey search field
        // while the root 40 pt behind it carried a warm wash — the two read as different apps. Same
        // wash, same semantics, lower: this screen's identity is the grid, not the band above it.
        .background(alignment: .top) {
            ZStack(alignment: .top) {
                ThemeColor.canvas
                // Short and warm rather than tall and faint: the band it has to light is the
                // navigation bar and the search drawer. Any lower and the pinned section letters
                // have to paint an opaque ground over it, which reads as a grey plate.
                ArtBackdrop(url: results.first?.cover ?? appModel.library.first?.cover,
                            height: 240, intensity: 0.7)
                    .frame(maxWidth: .infinity, alignment: .top)
            }
            .ignoresSafeArea()
        }
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
        .contentMargins(.bottom, ThemeMetrics.tabBarClearance, for: .scrollContent)
        // The rail owns a lane. Rows reserve it through `listTrailingInset`, so a chevron and an
        // index letter can never land on the same 4 pt of screen, and the poster grid narrows its
        // available width by the same amount — the letters used to sit ON the third column's
        // artwork, and a tap near a poster's right edge could be swallowed by the rail's gesture.
        .environment(\.listTrailingInset, showsRail ? LibraryAllView.railLane : 0)
        .overlay(alignment: .trailing) { if showsRail { indexRail } }
        .navigationTitle(Copy.Heading.allTitles)
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
            ArrangeSheet(sort: $sort, ascending: $sortAscending, status: $status,
                         display: $display, onReset: resetFilters)
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
        if let text = status.chip {
            chips.append(Chip(id: "status", text: text) { self.status = .any })
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
        sortAscending ? "\(sort.rawValue), reversed" : sort.rawValue
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
        sort = .title; sortAscending = false; status = .any; returning = nil
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
        case .recent, .added:
            var order: [String] = []
            var buckets: [String: [Franchise]] = [:]
            for f in results {
                let at = sort == .added ? (f.subscription?.addedAt ?? 0) : f.lastAiredSortKey
                let key = LibraryAllView.monthKey(at)
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

    /// `at` is **milliseconds**, like every other instant in this app. It was read as seconds here,
    /// which put the "Recently updated" month headers roughly fifty-five thousand years out.
    private static func monthKey(_ at: Int64) -> String {
        guard at > 0 else { return "No date" }
        return monthLabel.string(from: Date(timeIntervalSince1970: TimeInterval(at) / 1000))
    }

    private static let monthLabel: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMMyyyy")
        return formatter
    }()

    /// A pinned strip, not a floating label: content scrolls UNDER it, so it is opaque canvas with
    /// a quiet rule beneath — the same separator the rows carry.
    ///
    /// `inset` puts that rule on the SAME left edge as the row separators below it. Full width, it
    /// was a second separator inset on one screen (rows start their hairline at the title, x≈164)
    /// and the letter read as a stray character standing beside a rule that belonged to nothing.
    private func sectionHeader(_ key: String, inset: CGFloat) -> some View {
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
                .padding(.trailing, showsRail ? LibraryAllView.railLane : 0)
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
    ///  * **Target.** 22×15 pt bands inside a 22-pt column. The column is `railLane` (28 pt) wide
    ///    with a 44-pt hit area, and the rows reserve that lane (`listTrailingInset`) so the rail
    ///    no longer sits on the third poster column's artwork.
    ///  * **VoiceOver.** It was `.accessibilityHidden(true)` with no substitute, so a user with 500
    ///    titles had to swipe every row. It is one adjustable element now, and the list carries a
    ///    "Sections" rotor.
    ///  * **Feel.** The 300 ms blanket haptic floor meant an A→W drag produced two taps. `.selection`
    ///    now has its own 40 ms floor (SYS-7), which is what makes this control feel alive.
    private var indexRail: some View {
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
            .frame(height: geo.size.height, alignment: .top)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        railTouching = true
                        let i = Int(value.location.y / step)
                        select(index: max(0, min(keys.count - 1, i)))
                    }
                    .onEnded { _ in railTouching = false; railIndex = nil; railScroll = nil }
            )
        }
        .frame(width: LibraryAllView.railLane)
        // Between the search drawer and the tab bar, so the column IS the list's extent.
        .padding(.top, ThemeSpace.x3)
        .padding(.bottom, ThemeMetrics.tabBarClearance)
        .background {
            // The ground appears only under the finger, and only behind the letters.
            Capsule()
                .fill(ThemeColor.surfaceRaised.opacity(railTouching ? 1 : 0))
                .padding(.vertical, ThemeSpace.x2)
        }
        .animation(ThemeMotion.pick(ThemeMotion.uiMicro, reduceMotion: reduceMotion), value: railTouching)
        .accessibilityElement()
        .accessibilityLabel("Section index")
        .accessibilityValue(railIndex.flatMap { sections.indices.contains($0) ? sections[$0].key : nil }
                            ?? sections.first?.key ?? "")
        .accessibilityHint("Jumps the list to a section")
        .accessibilityAdjustableAction { direction in
            let current = railIndex ?? 0
            let next = direction == .increment ? current + 1 : current - 1
            guard sections.indices.contains(next) else { return }
            select(index: next)
        }
    }

    /// One selection, wherever it came from — the finger or the VoiceOver rotor.
    private func select(index: Int) {
        guard sections.indices.contains(index), index != railIndex else { return }
        railIndex = index
        FeedbackCoordinator.fire(.selection)
        railScroll = sections[index].key
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
    /// Where a list row's hairline starts — the title's leading edge. The section-letter rule uses
    /// the same x, so one screen carries one separator inset.
    static let rowRuleInset: CGFloat =
        ThemeMetrics.gutter + PosterSize.searchRow.size.width + ThemeMetrics.artGap
    /// A band is never smaller than this, however few letters there are; above that the rail fills
    /// the list's height so the column is anchored to the thing it scrolls.
    private static let railMinStep: CGFloat = 22

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
                        listHeader(section)
                    }
                }
            }
            .padding(.horizontal, ThemeMetrics.gutter)
            .onChange(of: railScroll) { _, key in
                guard let key else { return }
                proxy.scrollTo("sec-\(key)", anchor: .top)
            }
            // The rail's VoiceOver counterpart: the same jumps, through the system's own rotor.
            .accessibilityRotor("Sections", entries: sections, entryID: \.key, entryLabel: \.key)
        }
    }

    /// Extracted: the pinned header, inset to the rows' own hairline and wired to the rotor.
    @ViewBuilder
    private func listHeader(_ section: TitleSection) -> some View {
        if isSectioned {
            sectionHeader(section.key, inset: LibraryAllView.rowRuleInset)
                .id("sec-\(section.key)")
                .accessibilityRotorEntry(id: section.key, in: rotorSpace)
        }
    }

    private func row(_ f: Franchise, last: Bool) -> some View {
        let facts = LibraryRowFacts.catalogue(f, appModel: appModel, stateIsGiven: status.givesState)
        // `.searchRow` (60×90) at a 100-pt row, not `.row` (48×72) at 88. At 48 pt wide a logo-led
        // cover is below the recognition floor — "Avatar: Seven Havens" rendered as a black
        // rectangle with unreadable type — and this is the catalogue, the one screen whose whole
        // job is picking a title out of three hundred. It is the slot Schedule already runs.
        return MediaRow(title: f.title,
                        meta: facts.meta,
                        lead: facts.lead,
                        poster: f.cover,
                        slot: .searchRow,
                        separator: !last,
                        hint: "Opens the show",
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
        let lane = showsRail ? LibraryAllView.railLane : 0
        let available = max(0, contentWidth - ThemeMetrics.gutter * 2 - lane)
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
                        ForEach(section.items) { f in
                            cell(f, width: cellWidth, alignCaptions: section.items.count > 1)
                        }
                    } header: {
                        if isSectioned {
                            // No poster column to align to in the wall, so the rule starts at the
                            // gutter — and stops short of the rail's lane, like every row does.
                            sectionHeader(section.key, inset: ThemeMetrics.gutter)
                                .padding(.horizontal, -ThemeMetrics.gutter)
                                .id("sec-\(section.key)")
                                .accessibilityRotorEntry(id: section.key, in: rotorSpace)
                        }
                    }
                }
            }
            .padding(.horizontal, ThemeMetrics.gutter)
            .onChange(of: railScroll) { _, key in
                guard let key else { return }
                proxy.scrollTo("sec-\(key)", anchor: .top)
            }
            .accessibilityRotor("Sections", entries: sections, entryID: \.key, entryLabel: \.key)
        }
    }

    /// `alignCaptions` reserves the second title line so a row of cells keeps ONE caption baseline.
    /// A section holding a single title has nothing to align with, and reserving the line there
    /// left a 39-pt hole between a one-line title and its caption — the caption ended up nearer the
    /// next section than its own cover.
    private func cell(_ f: Franchise, width: CGFloat, alignCaptions: Bool = true) -> some View {
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
                    // The list variant zooms into Detail and the wall slid, so the transition
                    // changed with a VIEW-MODE TOGGLE. Same id the push already passes.
                    .zoomSource("all/\(f.id)")
                VStack(alignment: .leading, spacing: 2) {
                    Text(f.title)
                        .type(ThemeType.shelfTitle).foregroundStyle(ThemeColor.textPrimary)
                        .lineLimit(2, reservesSpace: !isAX && alignCaptions)
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
            // A bare stroked ring sat directly on the artwork with no ground, sliced by the card's
            // corner radius so only part of it survived — on a bright orange poster it read as a
            // rendering glitch, which is the "sticker on a poster" failure Search already fixed.
            // A `scrimStrong` disc, inset far enough that the corner radius never reaches it.
            ZStack {
                Circle().fill(ThemeColor.scrimStrong)
                Circle().strokeBorder(Color.white.opacity(0.22), lineWidth: 2)
                    .padding(4)
                Circle().trim(from: 0, to: fraction)
                    .stroke(ThemeColor.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(5)
            }
            .frame(width: 26, height: 26)
            .padding(ThemeSpace.x2)
            .accessibilityHidden(true)
        }
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
}

// MARK: - Segmented selection

/// The segmented control keeps the platform's own selection language — a raised NEUTRAL segment.
///
/// It was overridden to a solid `#F0A24E` pill with black text on the argument that "selection
/// everywhere in this app is accent". It is not: accent in this product means *a forward-looking
/// step you can take*, and a view mode is neither forward-looking nor a step. The result was the
/// loudest object in a sheet of quiet pickers, in a colour iOS has never used for a segment, and
/// it was the only control in the app whose selected state was a filled capsule with no
/// `controlSheen`. Accent is not the selection colour; it is the *action* colour.
///
/// The proxy still runs, because the stock control's unselected label is system grey on our dark
/// plate — the two neutrals belong to two different palettes. Ours, and nothing else.
@MainActor
private enum SegmentedAppearance {
    private static var installed = false

    static func install() {
        guard !installed else { return }
        installed = true
        let proxy = UISegmentedControl.appearance()
        proxy.selectedSegmentTintColor = UIColor(ThemeColor.surfaceFloating)
        proxy.backgroundColor = UIColor(ThemeColor.surfaceRaised)
        proxy.setTitleTextAttributes([.foregroundColor: UIColor(ThemeColor.textPrimary)], for: .selected)
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

// MARK: - Sort and filter

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
    /// The one `SectionLabel` group header the sheet gained is paid for out of the gap between the
    /// groups, which the label now occupies — measured on the simulator, the sum above still lands
    /// the last row's baseline where it was.
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
/// Titled **Sort & filter** (sentence case, `Copy.Heading`), because "Arrange" is Files.app's word
/// for ordering a grid and this sheet holds a sort, its direction and a status filter. The separate
/// `Unwatched only` switch is gone: it could contradict the Status row above it, so it became a
/// Status VALUE ("Has unwatched episodes"). What is left over is `View as`, which is neither a sort
/// nor a filter — so it gets its own named group and stops reading as an afterthought.
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
    @Binding var display: LibraryAllView.Display
    let onReset: () -> Void

    private var isAX: Bool { typeSize.isAccessibilitySize }

    private var hasFilters: Bool { sort != .title || ascending || status != .any }

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
                valueRow(title: "Sort by", value: sort.rawValue, separator: true) {
                    Picker("Sort by", selection: sortBinding) {
                        ForEach(LibraryAllView.Sort.allCases) { s in
                            Text(s.rawValue).tag(s)
                        }
                    }
                    .pickerStyle(.inline)
                }
                // Every sort shipped in exactly one direction, so "oldest first" did not exist.
                GroupedRow(title: "Reverse order",
                           subtitle: ascending ? reversedHint : nil,
                           trailing: .toggle(ascendingBinding), separator: true)
                valueRow(title: "Status", value: status.label, separator: false) {
                    Picker("Status", selection: statusBinding) {
                        Text(LibraryAllView.StatusFilter.any.label)
                            .tag(LibraryAllView.StatusFilter.any)
                        ForEach(WatchStatus.menuOrder, id: \.self) { s in
                            Text(LibraryRowFacts.listState(status: s))
                                .tag(LibraryAllView.StatusFilter.status(s))
                        }
                        // The old "Unwatched only" toggle, as a VALUE. As a separate switch it
                        // could contradict the row above it (Status = Watched + Unwatched only =
                        // an empty list with no explanation), and its noun was ambiguous —
                        // unwatched *what*? A single-select control cannot contradict itself.
                        Text(LibraryAllView.StatusFilter.unwatched.label)
                            .tag(LibraryAllView.StatusFilter.unwatched)
                    }
                    .pickerStyle(.inline)
                }
            }

            GroupedList(header: "View") { viewAsRow }
        }
    }

    /// The direction, said in the reader's terms rather than as "ascending".
    private var reversedHint: String {
        switch sort {
        case .title: return "Z to A"
        case .added: return "Oldest first"
        case .recent: return "Least recent first"
        case .progress: return "Least left to watch first"
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
}
