import SwiftUI

// Library (spec board 05): a calm root with ONE art moment and everything else quiet, and
// "All titles" — the instrument (search, sort, filter, view) behind one row. Urgency lives on
// Today, never here.
//
// Polish round. What the shipped root got wrong, and what this is:
//
//  * **Four identical poster shelves.** Board 05 and the original both put ONE shelf on this
//    screen — Returning, the anticipation section, which is the only one whose subject is a
//    picture of a show you have not seen yet. Watching / Planned / Finished are lists, because
//    what you want from them is a name and a fact, not a wall of art. Four shelves gave the
//    screen no rhythm at all: it read as a store page.
//  * **`Announced` in grey on every returning caption.** The information the shelf exists to
//    deliver — *when* — was thrown away, along with the one legitimate use of colour here.
//    `returnCaption` recovers "Returns Oct 2" / "Returns Jan 2027" / "Returns in 2027" in amber,
//    because a real next step is exactly what amber is for — and leaves "No date announced" grey,
//    because the absence of a next step is not one.
//  * **No ambient wash.** The original opened on a warm, art-derived atmosphere and that is most
//    of why it felt alive. One `ArtBackdrop`, pinned to the screen (not the content), costs one
//    already-cached image drawn once.
//  * **Content crossing the status bar and cutting hard under the tab bar.** `scrollEdgeChrome()`.
//  * **A skeleton that promised a different screen.** The shared `Skeleton.libraryRoot` draws an
//    All-titles block and THREE poster shelves; this root is one shelf and three lists, so the
//    loading state changed shape when the data landed. Board 09's structural continuity means the
//    skeleton is the shape of what is coming — so it is composed here, from the shared atoms.
struct LibraryView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dynamicTypeSize) private var typeSize
    let onOpenDetail: (_ franchiseId: String, _ zoomID: String) -> Void
    /// Where shows are added. Today and Schedule already take this; the Library's empty state
    /// printed the same `Add a show` label with nothing behind it.
    var onAddShow: () -> Void = {}

    @State private var all: AllTitlesRoute?
    private var isAX: Bool { typeSize.isAccessibilitySize }

    private var now: Int64 { appModel.now }

    struct AllTitlesRoute: Hashable, Identifiable {
        var status: WatchStatus?
        var id: String { status?.rawValue ?? "all" }
    }

    var body: some View {
        ZStack(alignment: .top) {
            ThemeColor.canvas.ignoresSafeArea()
            // The ambient identity wash. Pinned to the screen rather than scrolled with the
            // content, exactly as the original was: it is the room's light, not an element.
            wash

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // The spinner trails the WORD, not the screen: parked against the trailing
                    // edge it is a lone 16-pt dot in 250 pt of dead air, which is the same defect
                    // as Today's empty header band.
                    HStack(alignment: .firstTextBaseline, spacing: ThemeSpace.x2) {
                        Text("Library").type(ThemeType.screenTitle).foregroundStyle(ThemeColor.textPrimary)
                        RefreshIndicator(isRefreshing: appModel.isRefreshing)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, ThemeMetrics.gutter)
                    .padding(.top, ThemeSpace.x2)

                    if let since = appModel.staleSince(.catalogue) {
                        StaleStrip(since: since, now: now)
                            .padding(.horizontal, ThemeMetrics.gutter).padding(.top, ThemeSpace.x3)
                    }
                    if appModel.sectionFailed {
                        InlineNotice(Copy.Notice.library) { Task { await appModel.reload() } }
                            .padding(.horizontal, ThemeMetrics.gutter).padding(.top, ThemeSpace.x3)
                    }

                    SkeletonGate(isLoading: appModel.loading && appModel.library.isEmpty) {
                        skeleton
                    } content: {
                        if appModel.library.isEmpty {
                            // Top-aligned, one hero clearance under the title — where the first
                            // section would have started. (Centring it reads better on a tall
                            // empty screen, but `containerRelativeFrame` inside `SkeletonGate`
                            // resolves against whichever of skeleton/content is taller at that
                            // instant, so the card landed in a different place depending on how
                            // fast the request failed. A stable position beats a nicer unstable
                            // one; see the shared-file request in the report.)
                            EmptyState(appModel.emptyStateCopy, prominence: .major,
                                       primary: emptyStateAction)
                                .padding(.horizontal, ThemeMetrics.gutter)
                                .padding(.top, ThemeMetrics.heroClearance)
                        } else {
                            root
                        }
                    }
                }
                .padding(.bottom, ThemeMetrics.tabBarClearance)
            }
            .scrollIndicators(.hidden)
            .previouslyRefreshable { await appModel.reload() }
        }
        .scrollEdgeChrome()
        .overlay(alignment: .top) { washOverChrome }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $all) { route in
            LibraryAllView(initialStatus: route.status, onOpenDetail: onOpenDetail)
        }
        .onAppear { appModel.libQuery = "" }
    }

    /// The empty state's one action, and it is always a live one.
    ///
    /// The label comes from the copy table — `Try again` when a first load failed, `Add a show`
    /// when the account is genuinely empty — and the handler has to match it. It was previously a
    /// closure that ran `reload()` only on an error, so on the first-run screen the app drew a
    /// full-width accent capsule reading "Add a show" that did nothing at all when tapped.
    private var emptyStateAction: () -> Void {
        appModel.loadError ? { Task { await appModel.reload() } } : onAddShow
    }

    /// The wash is taken from the first show on the first shelf — the same artwork the eye lands
    /// on first, so the room is lit by the thing you are looking at.
    private var washCover: String? {
        orderedShelves.first?.franchises.first?.cover ?? appModel.library.first?.cover
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
    /// wash, so the screen opened on a black bar exactly where the original opened on warm light:
    /// measured, the original reads rgb(51,36,23) two points under the clock and this screen read
    /// rgb(9,9,11). Re-drawing the wash on top of the veil, masked to the veil's OWN ramp, gives
    /// the band its colour back without letting a pixel of scrolling content through — the content
    /// is already hidden by the opaque canvas underneath, and this only recolours it.
    private var washOverChrome: some View {
        let hold = max(0, min(1, ThemeMetrics.topSafeInset / max(ThemeMetrics.topChromeHeight, 1)))
        // Same shape as `ScrollEdgeChrome`: a band exactly `topChromeHeight` tall whose LAST
        // modifier is `ignoresSafeArea`, which is what puts its origin on the screen's top edge
        // rather than under the clock.
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
                GroupedRow(symbol: "rectangle.stack",
                           title: "All titles", trailing: .chevron("\(appModel.library.count)"),
                           separator: false) {
                    all = AllTitlesRoute(status: nil)
                }
            }
            .padding(.horizontal, ThemeMetrics.gutter)
            .padding(.top, ThemeSpace.x5)

            ForEach(orderedShelves) { section in
                VStack(alignment: .leading, spacing: ThemeMetrics.labelGap) {
                    SectionHeaderRow(shelfLabel(section.shelf), count: section.franchises.count,
                                     actionLabel: seeAllLabel(section)) {
                        all = AllTitlesRoute(status: filterStatus(for: section.shelf))
                    }
                    .padding(.horizontal, ThemeMetrics.gutter)

                    if usesPosterShelf(section.shelf) {
                        posterShelf(section)
                    } else {
                        rowList(section)
                    }
                }
            }

            // The shelf ends and something says so. Without it the last row is followed by 190 pt
            // of #09090B and the screen simply stops — the same "nothing acknowledges the end"
            // defect the Today screen was pulled up on. It is the same object that closes All
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

    /// Board 05's word for the anticipation shelf is **Returning**, which is also the word its
    /// captions use ("Returns Oct 2"). `LibShelf.label` still says "Coming back"; the mapping lives
    /// here rather than in `AppModel` so the change stays inside this screen's files.
    private func shelfLabel(_ shelf: AppModel.LibShelf) -> String {
        shelf == .comingBack ? "Returning" : shelf.label
    }

    /// Exactly one shelf on this screen, and it is the anticipation one. At accessibility sizes a
    /// horizontal shelf of 116-pt cards cannot hold a title, so it becomes rows like the rest.
    private func usesPosterShelf(_ shelf: AppModel.LibShelf) -> Bool {
        shelf == .comingBack && !isAX
    }

    // MARK: - Loading
    //
    // The shape of what is coming: the All-titles row, one captioned shelf, one list. Composed
    // from the shared atoms rather than `Skeleton.libraryRoot`, which still draws three shelves.

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: ThemeMetrics.sectionGap) {
            SkeletonBlock(height: ThemeMetrics.rowCompact, radius: ThemeRadius.row)
                .padding(.horizontal, ThemeMetrics.gutter)

            VStack(alignment: .leading, spacing: ThemeMetrics.labelGap) {
                SkeletonLine(width: 92, height: 10)
                HStack(alignment: .top, spacing: ThemeMetrics.shelfGap) {
                    ForEach(0..<3, id: \.self) { _ in
                        VStack(alignment: .leading, spacing: ThemeSpace.x2) {
                            SkeletonPoster(width: PosterSize.shelfLarge.size.width,
                                           height: PosterSize.shelfLarge.size.height,
                                           radius: PosterSize.shelfLarge.radius)
                            SkeletonLine(width: 96, height: 11)
                            SkeletonLine(width: 64, height: 9)
                        }
                    }
                }
            }
            .padding(.horizontal, ThemeMetrics.gutter)

            VStack(alignment: .leading, spacing: ThemeMetrics.labelGap) {
                SkeletonLine(width: 74, height: 10)
                VStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { _ in
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

    /// Returning has no `See all`, at ANY type size: All titles filters by status and there is no
    /// "returning" status to send it to, so the link could only lie. (It did: at accessibility
    /// sizes the shelf becomes rows, the count clears six, and the link that appeared went to
    /// **Finished**.) The status-backed shelves show six and offer the rest.
    private func seeAllLabel(_ section: AppModel.LibShelfSection) -> String? {
        guard section.shelf != .comingBack, section.franchises.count > 6 else { return nil }
        return Copy.Action.seeAll
    }

    /// …which also means Returning must show everything it has wherever it lands: as a shelf it
    /// scrolls, and as rows it simply runs long. Six of thirteen with no way to the other seven
    /// is content that exists for sighted users at default sizes and nobody else.
    private func shown(_ section: AppModel.LibShelfSection) -> [Franchise] {
        section.shelf == .comingBack ? section.franchises : Array(section.franchises.prefix(6))
    }

    /// Board 05 order: Returning · Watching · Planned · Finished.
    private var orderedShelves: [AppModel.LibShelfSection] {
        let rank: [AppModel.LibShelf: Int] = [.comingBack: 0, .watching: 1, .planned: 2, .finished: 3]
        return appModel.libraryShelves.sorted { (rank[$0.shelf] ?? 9) < (rank[$1.shelf] ?? 9) }
    }

    private func filterStatus(for shelf: AppModel.LibShelf) -> WatchStatus? {
        switch shelf {
        case .watching: return .watching
        case .planned: return .planned
        case .finished, .comingBack: return .completed
        }
    }

    // MARK: - The one shelf

    private func posterShelf(_ section: AppModel.LibShelfSection) -> some View {
        ScrollView(.horizontal) {
            // Lazy, and NOT capped: the shelf is the only place a returning title appears (All
            // titles has no "returning" filter to send a `See all` to), so a 13th show behind a
            // `prefix(12)` would simply not exist in the app.
            LazyHStack(alignment: .top, spacing: ThemeMetrics.shelfGap) {
                ForEach(section.franchises) { f in
                    let caption = returnCaption(f)
                    ShelfCard(title: f.title,
                              caption: caption.text,
                              // Amber is for a real next step. "No date announced" is the ABSENCE
                              // of one — printing it in accent would make the shelf's least
                              // informative cards its loudest, which is what board 05's mock
                              // renders in grey and the shipped `Announced` got backwards.
                              captionIsLead: caption.dated,
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

    private func rowList(_ section: AppModel.LibShelfSection) -> some View {
        let shown = shown(section)
        return VStack(spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { i, f in
                MediaRow(title: f.title,
                         meta: rowMeta(f, shelf: section.shelf),
                         lead: rowLead(f, shelf: section.shelf),
                         poster: f.cover,
                         slot: .row,
                         separator: i < shown.count - 1) {
                    onOpenDetail(f.id, "lib/\(f.id)")
                }
                .contextMenu { FranchiseContextMenu(f: f, appModel: appModel) }
            }
        }
        .padding(.horizontal, ThemeMetrics.gutter)
    }

    /// The forward-looking fact, in amber — and only when there genuinely is one. A settled state
    /// ("Caught up", "Watched twice") is never a lead.
    private func rowLead(_ f: Franchise, shelf: AppModel.LibShelf) -> String? {
        switch shelf {
        case .comingBack:
            let caption = returnCaption(f)
            return caption.dated ? caption.text : nil
        case .watching:
            if let active = RewatchStore.shared.activeSession(for: f.id), let p = f.currentPart {
                return "\(active.title) · \(Copy.Progress.episodeNext(p.progress + 1))"
            }
            guard let p = f.currentPart, !p.isUpcoming else { return nil }
            if p.isReleasing && p.episodesBehind == 0 { return nil }
            if p.isReleasing && p.episodesBehind > 0 { return Copy.Progress.behind(p.episodesBehind) }
            let left = max(0, p.markTarget(now: now) - p.progress)
            return left > 0 ? "\(p.watchContext(episode: p.progress + 1)) next" : nil
        case .planned, .finished:
            return nil
        }
    }

    /// The quiet second line. Never repeats the section it sits under — "Planned" under PLANNED
    /// is a row telling you what you already read 10 pt above it.
    private func rowMeta(_ f: Franchise, shelf: AppModel.LibShelf) -> String? {
        switch shelf {
        case .comingBack:
            // Only reached at accessibility sizes, where the shelf becomes rows. A dated return
            // is the amber lead; an undated one still has to say so, in grey.
            let caption = returnCaption(f)
            return caption.dated ? nil : caption.text
        case .watching:
            // Only when there is no lead. "Caught up" is a claim, so it is made only about a part
            // that actually exists and has actually been caught: a show whose next season is
            // undated has nothing to say, and says what it is instead.
            guard rowLead(f, shelf: shelf) == nil else { return nil }
            guard let p = f.currentPart, !p.isUpcoming else { return identityMeta(f) }
            return p.progress >= p.markTarget(now: now) ? Copy.Progress.caughtUp : identityMeta(f)
        case .planned:
            return identityMeta(f)
        case .finished:
            let watched = RewatchStore.shared.summary(for: f.id).completedCount
            return watched >= 2 ? Copy.Progress.watchedTimes(watched) : identityMeta(f)
        }
    }

    /// "Anime · 2021" / "TV · 2024" — what the thing is and when it started. The original's line,
    /// and the only honest thing to say about a show you have not started.
    private func identityMeta(_ f: Franchise) -> String {
        guard let y = f.year else { return f.kindWord }
        return "\(f.kindWord) · \(y)"
    }

    /// "Returns Oct 2" · "Returns Oct 2026" · "Returns in 2027" · "No date announced".
    ///
    /// A dated premiere among the parts is the best fact there is, so it wins. Otherwise the
    /// curated release window is read at whatever precision it actually has — and, crucially, is
    /// re-emitted at the SHORTEST honest granularity rather than passed through: the server sends
    /// human windows like `October 2026`, and `Returns October 2026` is 20 characters in a 116-pt
    /// caption, which is how the shelf ended up printing `Returns October…`. Board 09's rule is to
    /// drop a fact, never to truncate one.
    ///
    /// `dated` is false only for "No date announced", which is the one caption that must NOT be
    /// amber: it is the absence of a next step, not a next step.
    ///
    /// SHARED-FILE REQUEST: this belongs beside `TemporalCopy.returns`; it is here only because
    /// `Util/TemporalCopy.swift` is the design director's file this round.
    private func returnCaption(_ f: Franchise) -> (text: String, dated: Bool) {
        if let at = appModel.nextPremiere(of: f) {
            return (TemporalCopy.returns(at: at, now: now, source: f.source), true)
        }
        guard let upcoming = f.upcoming, let key = upcoming.releaseSortKey else {
            return (TemporalCopy.returns(at: nil, now: now, source: f.source), false)
        }
        let y = key.value / 10000, month = (key.value / 100) % 100, day = key.value % 100
        // Day precision inside the current year gets the friendly form — "Returns tomorrow",
        // "Returns Saturday", "Returns Oct 2" — which is also always the shortest.
        if key.precision >= 3, y == Formatting.localParts(now, anchor: .utcDate).y,
           let date = Self.utcDay(y: y, month: month, day: day) {
            return (TemporalCopy.returns(at: Int64(date.timeIntervalSince1970), now: now, source: .tmdb), true)
        }
        // Everything else settles at month-and-year: "Returns Oct 2026" fits, "Oct 2, 2027"
        // does not, and a day nine months out is not a fact anybody acts on.
        if key.precision >= 2, let date = Self.utcDay(y: y, month: month, day: 1) {
            return ("Returns \(Self.monthYear.string(from: date))", true)
        }
        // `releaseSortKey` only reads ISO, but the curated windows arrive as prose — "October
        // 2026" resolves to year precision there and would throw away a month we actually know.
        let window = upcoming.displayRelease
        // A bare year is a year, and reads as one: "Returns in 2027", never "Returns 2027".
        if window.count == 4, Int(window) != nil { return ("Returns in \(window)", true) }
        if let date = Self.parseWindow(window) {
            return ("Returns \(Self.monthYear.string(from: date))", true)
        }
        // An unparseable window ("Fall 2027") is kept whole only while it fits on one caption
        // line. It is never shortened by ellipsis — a dropped fact beats a broken word.
        let caption = "Returns \(window)"
        return (caption.count <= 17 ? caption : "Returns in \(y)", true)
    }

    /// The prose release windows the catalogue actually ships, read in English because that is
    /// what the server writes them in. A failure here costs a month, never a wrong month.
    private static func parseWindow(_ s: String) -> Date? {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return windowParsers.lazy.compactMap { $0.date(from: trimmed) }.first
    }

    private static let windowParsers: [DateFormatter] = ["MMMM yyyy", "MMMM d, yyyy", "MMM d, yyyy"]
        .map { format in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "UTC")
            formatter.dateFormat = format
            return formatter
        }

    /// A curated release window is a calendar date, not an instant: read it in UTC or a device in
    /// UTC+9 reads "October 2026" as September.
    private static func utcDay(y: Int, month: Int, day: Int) -> Date? {
        var parts = DateComponents()
        parts.year = y; parts.month = month; parts.day = day
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar.date(from: parts)
    }

    /// "Oct 2026" — locale-ordered, so a device set to a different region still reads correctly.
    private static let monthYear: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.setLocalizedDateFormatFromTemplate("MMMyyyy")
        return formatter
    }()
}

// MARK: - All titles (the instrument)

/// The one screen in the Library with controls on it. Rows sit on the canvas at `rowStandard`
/// with 48×72 art — the shipped 68-pt rows with 40×60 thumbs inside a stroked plate read as an
/// address book with posters, which is precisely what a library must not be.
struct LibraryAllView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    var initialStatus: WatchStatus? = nil
    let onOpenDetail: (_ franchiseId: String, _ zoomID: String) -> Void

    enum Sort: String, CaseIterable, Identifiable {
        case title = "Title", recent = "Recently updated", progress = "Most left to watch"
        var id: String { rawValue }
    }
    enum Display: String, CaseIterable, Identifiable {
        case posters = "Posters", list = "List"
        var id: String { rawValue }
        var symbol: String { self == .posters ? "square.grid.2x2" : "list.bullet" }
    }

    @State private var query = ""
    @State private var sort: Sort = .title
    @State private var status: WatchStatus?
    @State private var display: Display = .list
    @State private var unwatchedOnly = false
    @State private var showArrange = false
    @State private var contentWidth: CGFloat = 0
    /// The Arrange sheet reports the height its four rows actually need, so the detent is the
    /// content. A fixed 650 pt left 80 pt of void under the last row — a sheet that does not know
    /// how big it is reads as a panel someone guessed at.
    @State private var arrangeHeight: CGFloat = ArrangeSheet.fallbackHeight

    private var now: Int64 { appModel.now }
    private var isAX: Bool { typeSize.isAccessibilitySize }

    private var results: [Franchise] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        var arr = appModel.library.filter { f in
            (status == nil || f.effectiveStatus == status)
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

    private var isArranged: Bool { sort != .title || status != nil || display != .list || unwatchedOnly }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if isArranged { summaryRow }
                if results.isEmpty {
                    EmptyState(query.isEmpty ? .noFilterMatches : .noSearchResults(query: query),
                               prominence: .section,
                               primary: isArranged ? { sort = .title; status = nil; unwatchedOnly = false } : nil)
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
        // A pushed screen owns a real navigation bar, so it needs the bottom edge only — but it
        // needs it: without this, posters cut against the tab-bar glass with a hard horizon.
        .scrollEdgeChrome(top: false)
        .navigationTitle("All titles")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search your library")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showArrange = true } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                // Accent is selection here, and only here: an idle filter control is not the
                // screen's primary action and has no business being the loudest thing on it.
                .tint(isArranged ? ThemeColor.accent : ThemeColor.textPrimary)
                .accessibilityLabel(Copy.Action.arrange)
            }
        }
        .sheet(isPresented: $showArrange) {
            ArrangeSheet(sort: $sort, status: $status, display: $display,
                         unwatchedOnly: $unwatchedOnly, measuredHeight: $arrangeHeight)
                // The measured detent first, `.large` behind it so an accessibility size that
                // outgrows the screen still has somewhere to go.
                .presentationDetents([.height(arrangeHeight), .large])
                .presentationDragIndicator(.visible)
        }
        .onAppear { if let initialStatus, status == nil { status = initialStatus } }
    }

    /// What is currently narrowing the list, and one way out of it. `Clear` is a link, not a
    /// stroked pill: it is the smallest thing on the row and it should look like it.
    private var summaryRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: ThemeSpace.x3) {
            Text(summary)
                .type(ThemeType.metadata).foregroundStyle(ThemeColor.textSecondary)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: ThemeSpace.x2)
            Button(Copy.Action.clear) {
                withAnimation(ThemeMotion.pick(ThemeMotion.uiSnappy, reduceMotion: reduceMotion)) {
                    sort = .title; status = nil; display = .list; unwatchedOnly = false
                }
            }
            .buttonStyle(InlineLinkButtonStyle())
            .padding(.vertical, -12)
        }
        .zIndex(1)
        .padding(.horizontal, ThemeMetrics.gutter)
        .padding(.bottom, ThemeSpace.x3)
    }

    private var summary: String {
        var bits: [String] = []
        if let status { bits.append(Copy.Status(status)) }
        if unwatchedOnly { bits.append("Unwatched only") }
        if sort != .title { bits.append(sort.rawValue) }
        if display != .list { bits.append(display.rawValue) }
        return bits.joined(separator: " · ")
    }

    private var list: some View {
        // LAZY. At the stated 300-title library an eager `VStack` instantiates 300 `MediaRow`s and
        // 300 `RemoteImageView`s on push — each with its own `PaletteCache.resolve` task — while
        // its sibling poster path was already a `LazyVGrid`.
        LazyVStack(spacing: 0) {
            ForEach(Array(results.enumerated()), id: \.element.id) { i, f in
                MediaRow(title: f.title,
                         meta: rowMeta(f),
                         lead: rowLead(f),
                         poster: f.cover,
                         slot: .row,
                         separator: i < results.count - 1,
                         zoomID: "all/\(f.id)") {
                    onOpenDetail(f.id, "all/\(f.id)")
                }
                .contextMenu { FranchiseContextMenu(f: f, appModel: appModel) }
            }
        }
        .padding(.horizontal, ThemeMetrics.gutter)
    }

    /// A poster wall, measured: three columns that exactly fill the gutters instead of an adaptive
    /// grid that leaves a ragged 30 pt down the trailing edge.
    private var grid: some View {
        let columns = 3
        let available = max(0, contentWidth - ThemeMetrics.gutter * 2)
        let cell = available > 0
            ? (available - ThemeMetrics.shelfGap * CGFloat(columns - 1)) / CGFloat(columns)
            : PosterSize.shelfLarge.size.width
        return LazyVGrid(columns: Array(repeating: GridItem(.fixed(cell), spacing: ThemeMetrics.shelfGap,
                                                            alignment: .top),
                                        count: columns),
                         alignment: .leading, spacing: ThemeSpace.x6) {
            ForEach(results) { f in
                // Resolved once — calling `rowLead` twice to pick a colour is how a caption and
                // its colour drift apart.
                let caption = gridCaption(f)
                Button { onOpenDetail(f.id, "all/\(f.id)") } label: {
                    VStack(alignment: .leading, spacing: ThemeSpace.x2) {
                        PosterSlot(url: f.cover, width: cell, height: (cell * 3 / 2).rounded(),
                                   radius: ThemeRadius.poster, shadow: .art)
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
                        .frame(width: cell, alignment: .leading)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowPressStyle(radius: ThemeRadius.poster))
                .contextMenu { FranchiseContextMenu(f: f, appModel: appModel) }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, ThemeMetrics.gutter)
    }

    /// The grid cell is 128 pt wide, not 360 — so it gets the SHORTEST honest form of the same
    /// facts. "Season 7 · Episode 2 next" is 25 characters and would be cut to
    /// "Season 7 · Episo…"; board 09's rule is to drop a fact, never to truncate one, so the
    /// season goes and the episode stays. Likewise the row's "Watching · Caught up" reduces to
    /// the status alone: the longest status word fits any cell at any of the three columns.
    private func gridCaption(_ f: Franchise) -> (text: String, lead: Bool)? {
        if f.effectiveStatus == .watching, let p = f.currentPart, !p.isUpcoming {
            if p.isReleasing && p.episodesBehind > 0 {
                return (Copy.Progress.behind(p.episodesBehind), true)
            }
            if !p.isReleasing, p.markTarget(now: now) > p.progress {
                return (Copy.Progress.episodeNext(p.progress + 1), true)
            }
        }
        return (Copy.Status(f.effectiveStatus), false)
    }

    /// The forward-looking fact, amber, only when there is one to state.
    private func rowLead(_ f: Franchise) -> String? {
        guard f.effectiveStatus == .watching, let p = f.currentPart, !p.isUpcoming else { return nil }
        if p.isReleasing && p.episodesBehind > 0 { return Copy.Progress.behind(p.episodesBehind) }
        if p.isReleasing && p.episodesBehind == 0 { return nil }
        let left = max(0, p.markTarget(now: now) - p.progress)
        return left > 0 ? "\(p.watchContext(episode: p.progress + 1)) next" : nil
    }

    /// The status. Unlike the root's shelves this list mixes every status, so the status IS the
    /// fact — but it is never printed twice, and never alongside a lead that already says it.
    private func rowMeta(_ f: Franchise) -> String? {
        let label = Copy.Status(f.effectiveStatus)
        guard f.effectiveStatus == .watching else { return label }
        if rowLead(f) != nil { return label }
        if let p = f.currentPart, p.isReleasing, p.episodesBehind == 0 {
            return "\(label) · \(Copy.Progress.caughtUp)"
        }
        return label
    }
}

// MARK: - Arrange

/// Board 05, verbatim: "a grouped list, not a chip cloud — Sort by and Status rows, a segmented
/// View, native toggles, Reset."
///
/// So it is four rows, not twenty-two. `Sort by` and `Status` are VALUE rows that open a native
/// menu, which is the iOS grammar for choosing one of a known set (Photos, Files, Music all do
/// exactly this) — and it is what makes the sheet a small instrument instead of a wall: the
/// expanded sort list plus six status chips needed 650 pt and still left dead space under the
/// last control. This sheet is the height of its own content.
///
/// The header is hand-built rather than a `NavigationStack` toolbar: on this OS a toolbar button
/// renders as a filled glass capsule, which made `Done` the single heaviest object in a sheet
/// whose whole job is to be quiet. `Done` is a link. `Reset` is a link. The rows are the content.
private struct ArrangeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @Binding var sort: LibraryAllView.Sort
    @Binding var status: WatchStatus?
    @Binding var display: LibraryAllView.Display
    @Binding var unwatchedOnly: Bool
    /// Reported upward so the detent is the content. See `LibraryAllView.arrangeHeight`.
    @Binding var measuredHeight: CGFloat

    private var isAX: Bool { typeSize.isAccessibilitySize }

    private var isArranged: Bool {
        sort != .title || status != nil || display != .list || unwatchedOnly
    }

    /// Used before the first measurement lands, and as the floor.
    static let fallbackHeight: CGFloat = 340
    /// A sheet may not out-grow the screen; past this the second detent (`.large`) takes over.
    private static let ceiling: CGFloat = 830

    var body: some View {
        // The header rides INSIDE the scroll view so one measurement covers the whole sheet:
        // measuring the groups alone means adding the header, both paddings and the indicator back
        // as constants, and a detent assembled from five guesses is how the sheet ended up with
        // 100 pt of void under its last row.
        ScrollView {
            VStack(spacing: 0) {
                header
                groups
                    .padding(.horizontal, ThemeMetrics.gutter)
                    .padding(.top, ThemeSpace.x5)
                    .padding(.bottom, ThemeSpace.x6)
            }
            // A scroll view pushes the sheet's bottom safe area into its content as padding, so
            // this height ALREADY carries the home-indicator strip. Adding it again is what left
            // the sheet 40 pt taller than its own contents.
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                let wanted = min(max(height, ArrangeSheet.fallbackHeight), ArrangeSheet.ceiling)
                // Sub-point churn would re-drive the detent on every layout pass.
                if abs(wanted - measuredHeight) > 1 { measuredHeight = wanted }
            }
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        // `canvas`, not `canvasRaised`: a plate is `surfaceFlat`, and on a raised ground the step
        // between them is 2 % — the plates were only just visible, which is the exact failure the
        // surface table exists to prevent. The sheet is already separated from what is behind it
        // by its own shape and the dimmed backdrop; it does not also need a lighter floor.
        .background(ThemeColor.canvas.ignoresSafeArea())
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
                valueRow(title: "Status", value: statusValue, separator: false) {
                    Picker("Status", selection: statusBinding) {
                        Text(ArrangeSheet.anyStatus).tag(WatchStatus?.none)
                        ForEach(WatchStatus.menuOrder, id: \.self) { s in
                            Text(Copy.Status(s)).tag(WatchStatus?.some(s))
                        }
                    }
                    .pickerStyle(.inline)
                }
            }

            GroupedList(header: "View") {
                viewAsRow
                GroupedRow(title: "Unwatched only",
                           trailing: .toggle(unwatchedBinding), separator: false)
            }
        }
    }

    /// Board 05 asks for a segmented View. At accessibility sizes two words cannot share a row
    /// with their label, so the control drops under it rather than squeezing to 60 pt.
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
        .overlay(alignment: .bottom) {
            Rectangle().fill(ThemeColor.separatorQuiet).frame(height: 1).padding(.leading, 14)
        }
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
                // The pop-up glyph, not `chevron.forward`: this row opens a menu in place, it
                // does not push a screen, and iOS has one symbol for each.
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
    /// three-item HStack puts the title wherever the two buttons' widths happen to leave it —
    /// which is how "Arrange" ended up 45 pt left of the sheet's centre line.
    private var header: some View {
        HStack {
            if isArranged {
                Button(Copy.Action.reset) {
                    FeedbackCoordinator.fire(.selection)
                    withAnimation(ThemeMotion.pick(ThemeMotion.uiSnappy, reduceMotion: reduceMotion)) {
                        sort = .title; status = nil; display = .list; unwatchedOnly = false
                    }
                }
                .buttonStyle(InlineLinkButtonStyle())
            }
            Spacer(minLength: 0)
            Button(Copy.Action.done) { dismiss() }
                .buttonStyle(InlineLinkButtonStyle())
        }
        .overlay {
            Text(Copy.Action.arrange)
                .type(ThemeType.showTitleM).foregroundStyle(ThemeColor.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, ThemeMetrics.gutter)
        .frame(height: 52)
        .padding(.top, ThemeSpace.x3)
    }

    /// "Any status" rather than "All": beside the word `Status` on the same line, "All" reads as
    /// a quantity of something rather than as the absence of a filter.
    private static let anyStatus = "Any status"

    private var statusValue: String { status.map(Copy.Status) ?? ArrangeSheet.anyStatus }

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
