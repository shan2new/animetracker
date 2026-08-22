import SwiftUI

// Library (spec board 05): a calm root of shelves with zero controls, and "All titles" — the
// instrument (search, sort, filter, view) behind one row. Urgency lives on Today, never here.
struct LibraryView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onOpenDetail: (_ franchiseId: String, _ zoomID: String) -> Void

    @State private var all: AllTitlesRoute?

    private var now: Int64 { appModel.now }

    struct AllTitlesRoute: Hashable, Identifiable {
        var status: WatchStatus?
        var id: String { status?.rawValue ?? "all" }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Library").type(ThemeType.screenTitle).foregroundStyle(ThemeColor.textPrimary)
                    Spacer()
                    RefreshIndicator(isRefreshing: appModel.isRefreshing)
                }
                .padding(.horizontal, ThemeSpace.x4)
                .padding(.top, ThemeSpace.x2)

                if let since = appModel.staleSince(.catalogue) {
                    StaleStrip(since: since, now: now).padding(.horizontal, ThemeSpace.x4).padding(.top, ThemeSpace.x2)
                }
                if appModel.sectionFailed {
                    InlineNotice(Copy.Notice.library) { Task { await appModel.reload() } }
                        .padding(.horizontal, ThemeSpace.x4).padding(.top, ThemeSpace.x3)
                }

                SkeletonGate(isLoading: appModel.loading && appModel.library.isEmpty) {
                    Skeleton.libraryRoot.padding(.top, ThemeSpace.x4)
                } content: {
                    if appModel.library.isEmpty {
                        EmptyState(appModel.emptyStateCopy, prominence: .major) {
                            if appModel.loadError { Task { await appModel.reload() } }
                        }
                        .padding(ThemeSpace.x4)
                    } else {
                        root
                    }
                }
            }
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .background(ThemeColor.canvas.ignoresSafeArea())
        .refreshable { await appModel.reload() }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $all) { route in
            LibraryAllView(initialStatus: route.status, onOpenDetail: onOpenDetail)
        }
        .onAppear { appModel.libQuery = "" }
    }

    // MARK: - Root

    private var root: some View {
        VStack(alignment: .leading, spacing: ThemeSpace.x6) {
            GroupedList {
                GroupedRow(symbol: "rectangle.stack", symbolTint: ThemeColor.accentSoft,
                           title: "All titles", trailing: .chevron("\(appModel.library.count)"), separator: false) {
                    all = AllTitlesRoute(status: nil)
                }
            }
            .padding(.horizontal, ThemeSpace.x4)
            .padding(.top, ThemeSpace.x4)

            ForEach(orderedShelves) { section in
                VStack(alignment: .leading, spacing: ThemeSpace.x3) {
                    SectionHeaderRow(section.shelf.label, count: section.franchises.count,
                                     actionLabel: section.franchises.count > 6 ? Copy.Action.seeAll : nil) {
                        all = AllTitlesRoute(status: filterStatus(for: section.shelf))
                    }
                    .padding(.horizontal, ThemeSpace.x4)
                    ScrollView(.horizontal) {
                        HStack(alignment: .top, spacing: ThemeSpace.x3) {
                            ForEach(section.franchises.prefix(12)) { f in
                                shelfCard(f, shelf: section.shelf)
                            }
                        }
                        .padding(.horizontal, ThemeSpace.x4)
                    }
                    .scrollIndicators(.hidden)
                    .scrollClipDisabled()
                }
            }
        }
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

    private func shelfCard(_ f: Franchise, shelf: AppModel.LibShelf) -> some View {
        Button { onOpenDetail(f.id, "lib/\(f.id)") } label: {
            VStack(alignment: .leading, spacing: 6) {
                PosterSlot(url: f.cover, width: 104, height: 156)
                Text(f.title).type(ThemeType.showTitleS).foregroundStyle(ThemeColor.textPrimary)
                    .lineLimit(2).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                Text(caption(f, shelf: shelf)).type(ThemeType.caption).foregroundStyle(ThemeColor.textTertiary).lineLimit(1)
            }
            .frame(width: 104, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu { FranchiseContextMenu(f: f, appModel: appModel) }
        .accessibilityLabel("\(f.title), \(caption(f, shelf: shelf))")
    }

    /// Calm captions: a fact about where you are, never a nudge.
    private func caption(_ f: Franchise, shelf: AppModel.LibShelf) -> String {
        switch shelf {
        case .watching:
            if let p = f.currentPart, !p.isUpcoming {
                if p.isReleasing && p.episodesBehind == 0 { return Copy.Progress.caughtUp }
                return Copy.Progress.episodeNext(p.progress + 1)
            }
            return Copy.Status(.watching)
        case .comingBack:
            if let at = appModel.nextPremiere(of: f) { return TemporalCopy.returns(at: at, now: now, source: f.source) }
            return "Announced"
        case .planned:
            return Copy.Status(.planned)
        case .finished:
            return f.effectiveStatus == .completed ? Copy.Status(.completed) : f.effectiveStatus.displayName
        }
    }
}

// MARK: - All titles (the instrument)

struct LibraryAllView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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

    private var now: Int64 { appModel.now }

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
            VStack(alignment: .leading, spacing: ThemeSpace.x3) {
                if isArranged {
                    HStack(spacing: ThemeSpace.x2) {
                        Text(summary).type(ThemeType.metadata).foregroundStyle(ThemeColor.textSecondary).lineLimit(2)
                        Spacer()
                        Button(Copy.Action.clear) {
                            withAnimation(ThemeMotion.pick(ThemeMotion.uiSnappy, reduceMotion: reduceMotion)) {
                                sort = .title; status = nil; display = .list; unwatchedOnly = false
                            }
                        }
                        .buttonStyle(TertiaryButtonStyle2())
                    }
                    .padding(.horizontal, ThemeSpace.x4)
                }
                if results.isEmpty {
                    EmptyState(query.isEmpty ? .noFilterMatches : .noSearchResults(query: query), prominence: .section,
                               primary: isArranged ? { sort = .title; status = nil; unwatchedOnly = false } : nil)
                        .padding(.horizontal, ThemeSpace.x4)
                } else if display == .posters {
                    grid
                } else {
                    list
                }
                Text(Copy.titles(results.count))
                    .type(ThemeType.caption).foregroundStyle(ThemeColor.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, ThemeSpace.x2)
            }
            .padding(.top, ThemeSpace.x2)
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .background(ThemeColor.canvas.ignoresSafeArea())
        .navigationTitle("All titles")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search your library")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showArrange = true } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel(Copy.Action.arrange)
            }
        }
        .sheet(isPresented: $showArrange) {
            ArrangeSheet(sort: $sort, status: $status, display: $display, unwatchedOnly: $unwatchedOnly)
                .presentationDetents([.height(520), .large])
                .presentationDragIndicator(.visible)
        }
        .onAppear { if let initialStatus, status == nil { status = initialStatus } }
    }

    private var summary: String {
        var bits: [String] = []
        if let status { bits.append(status.displayName) }
        if unwatchedOnly { bits.append("Unwatched only") }
        if sort != .title { bits.append(sort.rawValue) }
        if display != .list { bits.append(display.rawValue) }
        return bits.joined(separator: " · ")
    }

    private var list: some View {
        VStack(spacing: 0) {
            ForEach(Array(results.enumerated()), id: \.element.id) { i, f in
                Button { onOpenDetail(f.id, "all/\(f.id)") } label: {
                    HStack(spacing: ThemeSpace.x3) {
                        PosterSlot(url: f.cover, width: 40, height: 60)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(f.title).type(ThemeType.showTitleS).foregroundStyle(ThemeColor.textPrimary).lineLimit(2)
                            Text(rowCaption(f)).type(ThemeType.metadata).foregroundStyle(ThemeColor.textSecondary).lineLimit(1)
                        }
                        Spacer(minLength: ThemeSpace.x2)
                        Image(systemName: "chevron.forward").font(.system(size: 12, weight: .semibold)).foregroundStyle(ThemeColor.textTertiary)
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 68)
                    .contentShape(Rectangle())
                    .overlay(alignment: .bottom) {
                        if i < results.count - 1 { Rectangle().fill(ThemeColor.separator).frame(height: 1).padding(.leading, 66) }
                    }
                }
                .buttonStyle(GroupedRowPressStyle())
                .contextMenu { FranchiseContextMenu(f: f, appModel: appModel) }
                .accessibilityLabel("\(f.title), \(rowCaption(f))")
            }
        }
        .background(ThemeColor.surfaceRaised, in: RoundedRectangle(cornerRadius: ThemeRadius.row, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: ThemeRadius.row, style: .continuous).stroke(ThemeColor.separator, lineWidth: 1))
        .padding(.horizontal, ThemeSpace.x4)
    }

    private var grid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104, maximum: 120), spacing: ThemeSpace.x3, alignment: .top)],
                  alignment: .leading, spacing: ThemeSpace.x4) {
            ForEach(results) { f in
                Button { onOpenDetail(f.id, "all/\(f.id)") } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        PosterSlot(url: f.cover, width: 104, height: 156)
                        Text(f.title).type(ThemeType.showTitleS).foregroundStyle(ThemeColor.textPrimary)
                            .lineLimit(2).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                        Text(rowCaption(f)).type(ThemeType.caption).foregroundStyle(ThemeColor.textTertiary).lineLimit(1)
                    }
                    .frame(width: 104, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu { FranchiseContextMenu(f: f, appModel: appModel) }
                .accessibilityLabel("\(f.title), \(rowCaption(f))")
            }
        }
        .padding(.horizontal, ThemeSpace.x4)
    }

    private func rowCaption(_ f: Franchise) -> String {
        let status = f.effectiveStatus.displayName
        guard f.effectiveStatus == .watching, let p = f.currentPart, !p.isUpcoming else { return status }
        if p.isReleasing && p.episodesBehind == 0 { return "\(status) · \(Copy.Progress.caughtUp)" }
        let left = max(0, p.markTarget(now: now) - p.progress)
        return left > 0 ? "\(status) · \(p.watchContext(episode: p.progress + 1)) next" : status
    }
}

// MARK: - Arrange (grouped-list grammar)

private struct ArrangeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var sort: LibraryAllView.Sort
    @Binding var status: WatchStatus?
    @Binding var display: LibraryAllView.Display
    @Binding var unwatchedOnly: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ThemeSpace.x5) {
                    GroupedList(header: "Sort by") {
                        ForEach(Array(LibraryAllView.Sort.allCases.enumerated()), id: \.element.id) { i, s in
                            GroupedRow(title: s.rawValue, trailing: .check(sort == s), separator: i < LibraryAllView.Sort.allCases.count - 1) {
                                FeedbackCoordinator.fire(.selection); sort = s
                            }
                        }
                    }
                    GroupedList(header: "Status") {
                        GroupedRow(title: "All", trailing: .check(status == nil)) { FeedbackCoordinator.fire(.selection); status = nil }
                        ForEach(Array(WatchStatus.menuOrder.enumerated()), id: \.element) { i, s in
                            GroupedRow(title: s.displayName, trailing: .check(status == s), separator: i < WatchStatus.menuOrder.count - 1) {
                                FeedbackCoordinator.fire(.selection); status = s
                            }
                        }
                    }
                    GroupedList(header: "View") {
                        GroupedRow(title: "Unwatched only", trailing: .toggle($unwatchedOnly), separator: true)
                        HStack {
                            Text("View as").type(ThemeType.body).foregroundStyle(ThemeColor.textPrimary)
                            Spacer()
                            Picker("View as", selection: $display) {
                                ForEach(LibraryAllView.Display.allCases) { d in
                                    Image(systemName: d.symbol).tag(d)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 120)
                        }
                        .padding(.leading, 14).padding(.trailing, 16)
                        .frame(minHeight: 52)
                    }
                }
                .padding(ThemeSpace.x4)
            }
            .background(ThemeColor.canvasRaised.ignoresSafeArea())
            .navigationTitle(Copy.Action.arrange)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if sort != .title || status != nil || display != .list || unwatchedOnly {
                        Button(Copy.Action.reset) { sort = .title; status = nil; display = .list; unwatchedOnly = false }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) { Button(Copy.Action.done) { dismiss() }.fontWeight(.semibold) }
            }
        }
    }
}
