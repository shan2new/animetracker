import SwiftUI

// Schedule — an AGENDA (rework, 24 Aug 2026).
//
// The shape Apple Calendar's list view, LiveChart, Sofa's Planner and Trakt's list calendar all
// converge on: one vertical list, a section per day that carries something (plus today, which is
// always drawn — empty, it says so), the day header pinned
// while its rows pass under it, opening on today. A day ticker across the top spans exactly the
// window the feed holds (a week back, two weeks ahead) and nothing beyond it. Aired days live in
// one collapsed "Earlier" block above today, so the screen opens on what is ahead and still lets
// the reader check what they missed.
//
// What this replaces, and why:
//   · the timeline rail (History's metaphor) with 8-pt three-state nodes, a NOW marker, and a
//     week strip that paged ±26 weeks over a 21-day feed — a third of the screen was chrome before
//     the first row, and a three-show week showed three rows in 900 pt;
//   · ~600 lines of hand-rolled scroll tracking (pin-line calibration, a 200-attempt landing loop,
//     a "pager owns the strip" flag) that shipped with the pinned header ghosting through the row
//     beneath it and the strip selecting the 30th while the feed sat on the 26th. The list's
//     position is now a `ScrollPosition` — the system reports which day is at the top and the
//     ticker follows it; a tap sets it and the feed goes there. Nothing is measured by hand;
//   · one `nextAiringAt` per show, which meant a weekly show appeared once and week two was empty
//     by construction — the feed now walks `FranchisePart.airings` (every dated episode in the
//     window) and the closing line names a horizon that is actually true;
//   · a hand-built row. Rows are `MediaRow` — the same 60×90 slot, lead/meta grammar and trailing
//     `MarkRing` Today's queue and Library's list draw — so Schedule stops being a third dialect.
//
// The only write here is "Mark as watched" on a row that has aired.
struct ScheduleView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    let onOpenDetail: (_ franchiseId: String, _ zoomID: String, _ focus: EpisodeFocus?) -> Void
    var onAddShow: () -> Void = {}

    // MARK: - State

    @State private var typeFilter: MediaFilter = ScheduleView.debugTypeFilter
    @State private var unwatchedOnly = ScheduleView.debugUnwatchedOnly
    /// The aired days above today are folded behind one row until asked for.
    ///
    /// `-scheduleEarlier 1` (DEBUG, like `-openTab` / `-recapDemo`) opens with the block already
    /// unfolded, so a scripted simulator run can capture the state without a tap.
    @State private var earlierExpanded = ScheduleView.debugEarlierExpanded

    private static var debugEarlierExpanded: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "scheduleEarlier")
        #else
        return false
        #endif
    }

    /// `-scheduleFilter anime|tv` and `-scheduleHideWatched 1` (DEBUG): open with a filter already
    /// applied, so the chip row and the filtered feed can be captured without driving the menu.
    private static var debugTypeFilter: MediaFilter {
        #if DEBUG
        switch UserDefaults.standard.string(forKey: "scheduleFilter") {
        case "anime": return .anime
        case "tv": return .tv
        default: return .all
        }
        #else
        return .all
        #endif
    }

    private static var debugUnwatchedOnly: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "scheduleHideWatched")
        #else
        return false
        #endif
    }
    @State private var committed: Set<String> = []
    @State private var prompt: FranchiseDetailView.WritePrompt?
    /// The day whose section is at the top of the feed — what the ticker highlights. Reported by
    /// the system (`onScrollTargetVisibilityChange`), never measured by hand.
    @State private var selectedDay = 0
    /// The ticker's own position, declared the same way the feed's is.
    @State private var tickerPosition = ScrollPosition(idType: Int.self)
    /// Once a finger has moved the feed it belongs to the reader; the landing stops correcting.
    @State private var userScrolled = false
    @State private var viewportH: CGFloat = 720
    /// Where the chrome band (title bar + ticker + any filter chips) actually ends, in screen
    /// space. The top veil is drawn down to here, so scrolling rows are carried out of sight
    /// before they reach the ticker instead of passing through it at full strength. MEASURED, not
    /// composed: the band's height answers to Dynamic Type and to whether chips are showing, and
    /// the veil is an overlay — it does not feed back into the band's own layout.
    @State private var chromeBottom: CGFloat = ThemeMetrics.topChromeHeight
    @State private var box = DerivedBox()

    private var now: Int64 { appModel.nowMinute }
    private var isAX: Bool { typeSize.isAccessibilitySize }

    // MARK: - Geometry

    private enum Metrics {
        /// A ticker cell. Seven and a bit fit the width, which is what says "this scrolls".
        static let cellWidth: CGFloat = 44
        static let cellGap: CGFloat = 6
        static let numeralMin: CGFloat = 34
        /// The trailing column every row reserves — the time, or the mark ring — so a commit swaps
        /// ink, never geometry, and every row shares one right-hand edge.
        static let stateColumn: CGFloat = 62
        /// Where a row's hairline starts: the title's leading edge. The day header's rule uses the
        /// same x, so the screen carries one separator inset.
        static let ruleInset: CGFloat = ThemeMetrics.gutter + PosterSize.row.size.width + ThemeMetrics.artGap
    }

    /// The ticker's "something airs here" mark. Scales with the caption it sits under.
    @ScaledMetric(relativeTo: .caption) private var dot: CGFloat = 5
    /// The artwork the wash is derived from: the next thing to air, else the most recent thing
    /// that did, else whatever the library leads with on a screen with nothing scheduled.
    private var washCover: String? {
        let d = derived
        // `first(where:)`, not `first`: today leads `ahead` even when it is empty, and an empty
        // day would otherwise hand the wash to the LAST thing that aired instead of the next.
        if let next = d.ahead.first(where: { !$0.isEmpty })?.rows.first?.franchise.cover { return next }
        if let last = d.earlier.last?.rows.last?.franchise.cover { return last }
        return appModel.library.first?.cover
    }

    // MARK: - Identity

    /// Every scroll target in the feed maps back to a day, so the position the system reports —
    /// whichever header or row happens to be at the top — names the day the ticker should show.
    enum AgendaID: Hashable {
        case earlier
        case day(Int)
        case row(Int, String)

        var day: Int? {
            switch self {
            case .earlier: return nil
            case .day(let d), .row(let d, _): return d
            }
        }
    }

    // MARK: - Feed

    /// One row on the calendar. A date-only part that drops several episodes on one day is ONE
    /// row ("Season 2 · 8 episodes"), not eight identical ones.
    struct Row: Identifiable {
        let franchise: Franchise
        let part: FranchisePart
        /// First and last episode number the row covers; equal for a single episode.
        let episodes: ClosedRange<Int>
        let at: Int64
        let aired: Bool
        let dateOnly: Bool
        var episode: Int { episodes.upperBound }
        var id: String { "\(franchise.id)/\(part.mediaId)/\(episode)" }
        var watched: Bool { aired && part.progress >= episode }
    }

    struct Day: Identifiable {
        let id: Int
        let noon: Int64
        let rows: [Row]
        var isToday: Bool { id == 0 }
        var isEmpty: Bool { rows.isEmpty }
        var count: Int { rows.count }
    }

    /// Everything the screen derives from the feed, computed ONCE per (feed, filter). The box is
    /// a reference so a cache fill inside a body read never invalidates the view.
    private struct Derived {
        var all: [Day] = []
        var earlier: [Day] = []
        /// Today and everything after it that carries something. TODAY IS ALWAYS IN HERE, empty
        /// or not — it is the feed's anchor, and the feed always opens on it (`land`). There is
        /// deliberately no "landing day" to go with it: the one this used to compute was the
        /// first NON-EMPTY day ≥ 0, and `awayFromToday` / `goToToday` then treated that as a
        /// synonym for today. On a day with nothing scheduled the agenda opened on a future day,
        /// hid the "Today" button (`selectedDay == landing`, so by its own test you were already
        /// there) and sent that button to the wrong day when it did show. The top row's bare
        /// clock — a Wednesday 6:30 PM episode — read as tonight's, and its missing mark control
        /// read as a bug rather than as "this has not aired".
        var ahead: [Day] = []
        /// Today has rows, but the active filter is hiding all of them — so the empty-today line
        /// says "No episodes" (there are some; you filtered them) rather than "Nothing scheduled".
        var todayFiltered = false
        var counts: [Int: Int] = [:]
        /// Days with something still to come or still to watch — the ticker's accent dots.
        var live: Set<Int> = []
        var earlierCount = 0
        var earlierUnwatched = 0
        var horizonId: Int? = nil
        var allEmpty = true
        var shownEmpty = true
        var feedKey: [Int] = []
    }

    private struct DerivedKey: Equatable {
        let feed: AppModel.ScheduleFeedKey
        let type: MediaFilter
        let unwatched: Bool
    }

    @MainActor private final class DerivedBox {
        var key: DerivedKey?
        var value = Derived()
    }

    private var derived: Derived {
        let key = DerivedKey(feed: appModel.scheduleFeedKey, type: typeFilter, unwatched: unwatchedOnly)
        if box.key == key { return box.value }
        let value = computeDerived()
        box.key = key
        box.value = value
        return value
    }

    private func computeDerived() -> Derived {
        let raw = appModel.scheduleDays
        let all = raw.map { Day(id: $0.id, noon: $0.noon, rows: rows(for: $0)) }
        let shown = all.map { Day(id: $0.id, noon: $0.noon, rows: $0.rows.filter(passes)) }
        var out = Derived()
        out.all = all
        out.allEmpty = all.allSatisfy(\.isEmpty)
        out.shownEmpty = shown.allSatisfy(\.isEmpty)
        out.earlier = shown.filter { $0.id < 0 && !$0.isEmpty }
        // `|| $0.id == 0`: today survives its own emptiness. `AppModel.buildScheduleDays` keeps
        // an empty today in the feed on purpose, as the anchor; dropping it here threw that away.
        out.ahead = shown.filter { $0.id >= 0 && (!$0.isEmpty || $0.id == 0) }
        out.todayFiltered = (shown.first { $0.id == 0 }?.isEmpty ?? true)
            && !(all.first { $0.id == 0 }?.isEmpty ?? true)
        out.counts = Dictionary(shown.map { ($0.id, $0.count) }, uniquingKeysWith: { a, _ in a })
        out.live = Set(shown.filter { $0.rows.contains { !$0.watched } }.map(\.id))
        out.earlierCount = out.earlier.reduce(0) { $0 + $1.count }
        out.earlierUnwatched = out.earlier.reduce(0) { $0 + $1.rows.filter { !$0.watched }.count }
        out.horizonId = raw.last?.id
        out.feedKey = (out.earlier + out.ahead).map { $0.id * 1000 + $0.count }
        return out
    }

    /// Groups a date-only part's same-day episodes into one row; everything else is one row each.
    private func rows(for day: AppModel.ScheduleDay) -> [Row] {
        var out: [Row] = []
        var dropIndex: [Int: Int] = [:]   // mediaId → index in `out`, for date-only parts only
        for e in day.entries {
            if e.dateOnly, let i = dropIndex[e.part.mediaId] {
                let r = out[i]
                out[i] = Row(franchise: r.franchise, part: r.part,
                             episodes: min(r.episodes.lowerBound, e.episode)...max(r.episodes.upperBound, e.episode),
                             at: r.at, aired: r.aired, dateOnly: true)
                continue
            }
            out.append(Row(franchise: e.franchise, part: e.part, episodes: e.episode...e.episode,
                           at: e.at, aired: e.aired, dateOnly: e.dateOnly))
            if e.dateOnly { dropIndex[e.part.mediaId] = out.count - 1 }
        }
        return out
    }

    private func passes(_ r: Row) -> Bool {
        switch typeFilter {
        case .all: break
        case .anime: if r.franchise.source != .anilist { return false }
        case .tv: if r.franchise.source != .tmdb { return false }
        }
        if unwatchedOnly && r.watched { return false }
        return true
    }

    private var filterActive: Bool { typeFilter != .all || unwatchedOnly }

    /// The screen is showing a whole-surface state rather than a feed: nothing to page through,
    /// and a populated ticker over it would be a calendar asserting dates over nothing.
    private var showsWholeScreenState: Bool {
        if appModel.loading && appModel.library.isEmpty { return true }
        if appModel.libraryEmpty { return true }
        let d = derived
        return d.allEmpty || (d.shownEmpty && filterActive)
    }

    // MARK: - Body

    var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .top) {
            ThemeColor.canvas.ignoresSafeArea()
            ScrollView {
                // NOT pinned. A pinned header has to occlude the rows passing under it, which
                // means an opaque full-bleed plate — and that plate's top edge cut the wash in a
                // hard horizontal step across the screen, the exact seam the shared chrome exists
                // to remove. A day section here is one to three rows, so its date is on screen
                // beside its rows the whole time it matters; pinning bought nothing and cost the
                // one thing the screen's ground is for.
                LazyVStack(alignment: .leading, spacing: 0) {
                    content()
                }
                .scrollTargetLayout()
                // A user-requested layout change (a filter, the Earlier block) is what `uiSnappy`
                // is for, and it belongs on the thing that re-lays out.
                .animation(ThemeMotion.pick(ThemeMotion.uiSnappy, reduceMotion: reduceMotion), value: derived.feedKey)
                .animation(ThemeMotion.pick(ThemeMotion.uiSnappy, reduceMotion: reduceMotion), value: earlierExpanded)
            }
            // NOT bound to a `ScrollPosition`. An id-bound position is sticky: the anchored view is
            // re-pinned to the top on every layout change, so a row's own press-scale moved the
            // feed 28 pt under the finger and the tap arrived as a cancelled scroll. The feed opens
            // where it should by construction — the Earlier row or today's section is its FIRST
            // item — and the two programmatic scrolls (a ticker tap, "Today") are one-shot.
            .safeAreaInset(edge: .top, spacing: 0) { chrome(proxy) }
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }, action: { viewportH = $0 })
            // Nothing may come to rest inside the bottom ramp. A scroll-content MARGIN, not
            // padding: padding inside a stack shorter than the viewport changes no layout at all.
            .tabBarContentMargin()
            .scrollIndicators(.hidden)
            // The moment a finger touches the feed it belongs to the reader.
            .onScrollPhaseChange { _, phase in
                if phase == .interacting { userScrolled = true }
            }
            // The system says which targets are on screen; the earliest day among them is the
            // section at the top, and the ticker follows it. No coordinate spaces, no pin-line
            // arithmetic — the one thing the previous screen got wrong in every capture.
            .onScrollTargetVisibilityChange(idType: AgendaID.self, threshold: 0.2) { ids in
                let days = ids.compactMap(\.day)
                // Only the Earlier row on screen means today is next under it.
                let day = days.min() ?? (ids.isEmpty ? selectedDay : 0)
                guard day != selectedDay else { return }
                selectedDay = day
                keepTickerVisible(day)
            }
            }
        // The bottom edge is the shared one. The TOP belongs to the chrome band itself, whose
        // ground IS the wash (see `chrome`) — the app's soft top veil is a translucent gradient,
        // and measured on this screen a poster and two lines of row text were plainly legible
        // through the ticker's date numerals and beside the title. (Library and Search show the
        // same ghosting under scroll; there it is a title over rows rather than a control over
        // them, so it reads as depth instead of breakage. Worth fixing app-wide, in the shared
        // modifier, rather than diverging here.)
        .scrollEdgeChromeBody(top: false, bottom: true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .scrollEdgeEffectHidden(true, for: .all)
        .previouslyRefreshable { await appModel.reload() }
        .task { await ScheduleReminders.shared.refresh() }
        // The feed opens on its first item; only the ticker's selection has to be told which day
        // that is, whenever the feed's identity changes and the reader has not taken the wheel.
        .onChange(of: derived.feedKey, initial: true) { _, _ in land() }
        .navigationTitle(Copy.Schedule.title)
        // Inline: a large title collapses on the first scroll and moves the top safe area ~50 pt
        // mid-flight, under a ticker that has to hold still.
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // LEADING, not trailing. Two items plus a spacer on the trailing side pushed the
            // inline title off centre — "Schedule" sat hard against the leading bezel while every
            // other root centres its title. It also reads better: the leading slot is where
            // navigation lives, the trailing slot is where the view's controls do.
            ToolbarItem(placement: .topBarLeading) {
                Group {
                    if awayFromToday {
                        Button(Copy.Schedule.today) { goToToday(proxy) }
                            .accessibilityLabel(Copy.Schedule.scrollToToday)
                            .accessibilityHint(Copy.Schedule.scrollToTodayHint)
                            .transition(.opacity)
                    }
                }
                .animation(ThemeMotion.pick(ThemeMotion.uiGentle, reduceMotion: reduceMotion), value: awayFromToday)
            }
            ToolbarItem(placement: .topBarTrailing) { filterMenu }
        }
        .confirmationDialog(prompt?.title ?? "", isPresented: Binding(get: { prompt != nil }, set: { if !$0 { prompt = nil } }),
                            titleVisibility: .visible, presenting: prompt) { p in
            Button(p.confirm) { p.perform() }
            Button(Copy.Confirm.cancel, role: .cancel) {}
        } message: { p in
            Text(p.message)
        }
        }
    }

    /// The reader is somewhere other than today's section. Measured against TODAY (day 0), which
    /// is always in the feed — never against "the first day that carries something", which on a
    /// quiet day is not today and made this read `false` while Wednesday filled the screen.
    private var awayFromToday: Bool { selectedDay != 0 || (earlierExpanded && selectedDay < 0) }

    // MARK: - Scrolling

    /// The feed opens on the Earlier row when there is one — a 44-pt line with today's section
    /// directly under it, so the reader sees that a past exists without being shown it — and on
    /// today's section otherwise. Both are the feed's first item, so nothing scrolls; the ticker
    /// opens with today as its first cell. True on a day with nothing on it too, now that an
    /// empty today still renders: the agenda always opens where the reader is standing.
    private func land() {
        guard !userScrolled, !appModel.library.isEmpty, !showsWholeScreenState else { return }
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) { tickerPosition.scrollTo(id: 0, anchor: .leading) }
        if selectedDay != 0 { selectedDay = 0 }
    }

    /// The ticker shows seven cells; it moves only when the selected day would fall outside them,
    /// and then by the least it can. Opening on today, the past sits off the leading edge.
    private func keepTickerVisible(_ day: Int) {
        let first = tickerPosition.viewID(type: Int.self) ?? 0
        let visible = 7
        let target: Int
        if day < first { target = day }
        else if day > first + visible - 1 { target = day - visible + 1 }
        else { return }
        withAnimation(ThemeMotion.pick(ThemeMotion.uiGentle, reduceMotion: reduceMotion)) {
            tickerPosition.scrollTo(id: max(AppModel.scheduleBack, min(target, AppModel.scheduleAhead)), anchor: .leading)
        }
    }

    private func scroll(to id: AgendaID, day: Int, proxy: ScrollViewProxy) {
        userScrolled = true
        selectedDay = day
        keepTickerVisible(day)
        withAnimation(ThemeMotion.pick(ThemeMotion.uiReveal, reduceMotion: reduceMotion)) {
            proxy.scrollTo(id, anchor: .top)
        }
    }

    /// Back to the top of what is ahead: the Earlier row while it is folded (today sits right
    /// under it), today's own section once the past has been opened.
    private func goToToday(_ proxy: ScrollViewProxy) {
        FeedbackCoordinator.fire(.selection)
        let d = derived
        scroll(to: earlierExpanded || d.earlier.isEmpty ? .day(0) : .earlier, day: 0, proxy: proxy)
    }

    // MARK: - Chrome

    /// The band under the title: the day ticker, and the active filters as removable tokens.
    /// Opaque canvas, the same the navigation bar is painted in, so the two are one surface.
    @ViewBuilder
    private func chrome(_ proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Collapsed by HEIGHT over a whole-screen state, never by a conditional: taking a
            // scroll view out of the tree and putting it back re-creates it, and a re-created
            // `.scrollPosition(id:)` does not re-apply.
            ticker(proxy)
                .frame(height: showsWholeScreenState ? 0 : nil)
                .opacity(showsWholeScreenState ? 0 : 1)
                .clipped()
                .accessibilityHidden(showsWholeScreenState)
            filterChips
        }
        .padding(.bottom, showsWholeScreenState ? 0 : ThemeSpace.x2)
        // The band's ground is THE WASH — the same `ArtBackdrop` Library, All titles and Search
        // hang, art-derived from the next thing to air, over opaque canvas and sized to end exactly
        // at the band's own bottom edge.
        //
        // That last part is what removes the seam. `ArtBackdrop`'s final stop IS `ThemeColor.canvas`,
        // so at the band's bottom the ground is already the canvas the feed scrolls on: warm behind
        // the title and the ticker, plain canvas the pixel below, no step anywhere. A flat canvas
        // strip (what this screen shipped) put a hard horizontal edge across the wash; a translucent
        // veil (what Library uses over its rows) let posters through the date numerals. This is
        // both: opaque, and continuous with the content.
        .background {
            ZStack(alignment: .top) {
                ThemeColor.canvas
                ArtBackdrop(url: washCover, tint: washCover == nil ? ThemeColor.accent : nil,
                            height: max(chromeBottom, ThemeMetrics.topChromeHeight),
                            intensity: ThemeMetrics.rootWashIntensity)
            }
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.frame(in: .global).maxY },
                          action: { chromeBottom = $0 })
    }

    /// Every day the feed can hold, a week back through two weeks ahead — no more. Opens with
    /// today as the first visible cell; the past sits to the left, dimmed, where the reader can
    /// pull it in. The cells are the feed's own index: the selected one is the section at the
    /// top, and tapping one takes the feed there.
    private func ticker(_ proxy: ScrollViewProxy) -> some View {
        let d = derived
        return ScrollView(.horizontal) {
            LazyHStack(spacing: Metrics.cellGap) {
                ForEach(Array(AppModel.scheduleBack...AppModel.scheduleAhead), id: \.self) { offset in
                    tickerCell(offset, count: d.counts[offset] ?? 0, live: d.live.contains(offset), proxy: proxy)
                        .id(offset)
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, ThemeMetrics.gutter)
        }
        .scrollPosition($tickerPosition, anchor: .leading)
        .scrollIndicators(.hidden)
        // A nested scroll view has to state its own margins: the feed's tab-bar clearance is
        // inherited through the environment and would otherwise apply here too.
        .contentMargins(.all, 0, for: .scrollContent)
        // A horizontal scroll view inside a `safeAreaInset` is greedy on its cross axis and will
        // take the whole screen; it states what it needs.
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, ThemeSpace.x1)
        .accessibilityLabel(Copy.Schedule.ticker)
    }

    private func tickerCell(_ offset: Int, count: Int, live: Bool, proxy: ScrollViewProxy) -> some View {
        let ts = appModel.scheduleTodayNoon + Int64(offset) * Formatting.D
        let parts = Formatting.localParts(ts)
        let isToday = offset == 0
        let selected = offset == selectedDay
        let past = offset < 0
        let enabled = count > 0 || isToday
        // The first of a month names the month where its weekday letter would go — the numerals
        // alone cannot say that "2" comes after "31".
        let top = parts.d == 1 ? Formatting.fmtMonthDay(ts).components(separatedBy: " ").first(where: { Int($0) == nil })?.uppercased() ?? ""
                               : String(Formatting.weekdayNameMonFirst(Formatting.localMondayCol(ts)).prefix(1))
        return Button {
            FeedbackCoordinator.fire(.selection)
            if offset < 0 { earlierExpanded = true }
            // Every enabled cell now has a section to land on: a day carries rows, or it is
            // today, which renders empty rather than being skipped.
            scroll(to: .day(offset), day: offset, proxy: proxy)
        } label: {
            VStack(spacing: 3) {
                Text(top).type(ThemeType.caption)
                    .foregroundStyle(isToday ? ThemeColor.accent : ThemeColor.textTertiary)
                    .lineLimit(1)
                Text(String(parts.d)).type(ThemeType.time)
                    .foregroundStyle(isToday ? ThemeColor.accent : ThemeColor.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(minWidth: Metrics.numeralMin, minHeight: Metrics.numeralMin)
                    .background {
                        // Selection is a neutral raised ground; amber is today's alone.
                        if selected {
                            RoundedRectangle(cornerRadius: ThemeRadius.compactControl, style: .continuous)
                                .fill(ThemeColor.surfaceRaised)
                                .overlay(RoundedRectangle(cornerRadius: ThemeRadius.compactControl, style: .continuous)
                                    .strokeBorder(ThemeColor.strokeStrong, lineWidth: 1))
                        }
                    }
                    .differentiatingUnderline(isToday, tint: ThemeColor.accent)
                // One fact — "something airs here" — accent while there is still something to
                // watch or wait for, quiet once the day is done.
                Circle()
                    .fill(count > 0 ? (live ? ThemeColor.accent : ThemeColor.textTertiary) : .clear)
                    .frame(width: dot, height: dot)
                    .accessibilityHidden(true)
            }
            .frame(width: Metrics.cellWidth)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            // The past recedes as a group — never the selected cell.
            .opacity(past && !selected ? 0.55 : 1)
            .animation(ThemeMotion.pick(ThemeMotion.uiMicro, reduceMotion: reduceMotion), value: selected)
        }
        .buttonStyle(TickerCellPressStyle())
        .disabled(!enabled)
        .accessibilityLabel(Date(timeIntervalSince1970: Double(ts) / 1000)
            .formatted(.dateTime.weekday(.wide).day().month(.wide)))
        .accessibilityValue([selected ? Copy.Schedule.selected : nil,
                             isToday ? Copy.Schedule.today : nil,
                             count > 0 ? Copy.episodes(count) : Copy.Schedule.noEpisodes]
            .compactMap { $0 }.joined(separator: ", "))
    }

    private var filterMenu: some View {
        Menu {
            Section(Copy.Filter.source) {
                Picker(Copy.Filter.source, selection: sourceBinding) {
                    Text(Copy.Filter.all).tag(MediaFilter.all)
                    Text(Copy.Filter.anime).tag(MediaFilter.anime)
                    Text(Copy.Filter.tv).tag(MediaFilter.tv)
                }
                .pickerStyle(.inline)
            }
            Toggle(Copy.Filter.hideWatched, isOn: hideWatchedBinding)
        } label: {
            Image(systemName: filterActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease")
        }
        .tint(filterActive ? ThemeColor.accent : ThemeColor.textPrimary)
        .accessibilityLabel(Copy.Filter.filter)
        .accessibilityValue(filterValue)
    }

    private var filterValue: String {
        var bits: [String] = []
        if typeFilter != .all { bits.append(typeFilter.chipLabel) }
        if unwatchedOnly { bits.append(Copy.Filter.hideWatched) }
        return bits.isEmpty ? Copy.Filter.off : bits.joined(separator: ", ")
    }

    // The haptic fires from the MUTATION, not from an observer, so one transaction is one haptic.
    private var sourceBinding: Binding<MediaFilter> {
        Binding(get: { typeFilter }, set: { typeFilter = $0; FeedbackCoordinator.fire(.selection) })
    }

    private var hideWatchedBinding: Binding<Bool> {
        Binding(get: { unwatchedOnly }, set: { unwatchedOnly = $0; FeedbackCoordinator.fire(.selection) })
    }

    /// The removable tokens for whatever is filtering the feed — in the CHROME, so a reader who
    /// filters, leaves and comes back is never shown a schedule that merely looks thin.
    @ViewBuilder
    private var filterChips: some View {
        if filterActive {
            HStack(spacing: ThemeSpace.x2) {
                if typeFilter != .all { filterChip(typeFilter.chipLabel) { typeFilter = .all } }
                if unwatchedOnly { filterChip(Copy.Filter.hideWatched) { unwatchedOnly = false } }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, ThemeMetrics.gutter)
            .padding(.top, ThemeSpace.x2)
            .transition(.opacity)
        }
    }

    private func filterChip(_ text: String, clear: @escaping () -> Void) -> some View {
        Button {
            FeedbackCoordinator.fire(.selection)
            withAnimation(ThemeMotion.pick(ThemeMotion.uiSnappy, reduceMotion: reduceMotion)) { clear() }
        } label: {
            FilterChipLabel(text: text)
        }
        .buttonStyle(FilterChipStyle())
        .accessibilityLabel(Copy.Accessibility.removeFilter(text))
    }

    // MARK: - Content (state matrix)

    /// A whole-screen state sits in the middle of the content area, centred against the tab
    /// bar's VISUAL height.
    private func centred<V: View>(@ViewBuilder _ state: () -> V) -> some View {
        state()
            .padding(.horizontal, ThemeMetrics.gutter)
            .centredState(contentH: viewportH)
    }

    @ViewBuilder
    private func content() -> some View {
        if appModel.loading && appModel.library.isEmpty {
            feedSkeleton
        } else if appModel.loadError && appModel.libraryEmpty {
            centred {
                EmptyState(SyncCenter.shared.isOnline ? .serverNoCache : .offlineNoData,
                           prominence: .major,
                           primary: { Task { await appModel.reload() } },
                           ambient: false)
            }
        } else if appModel.libraryEmpty {
            centred { EmptyState(.emptySchedule, prominence: .major, primary: onAddShow, ambient: false) }
        } else {
            if appModel.sectionFailed {
                InlineNotice(Copy.Notice.schedule) { Task { await appModel.reload() } }
                    .padding(.horizontal, ThemeMetrics.gutter).padding(.top, ThemeMetrics.labelGap)
            } else if let since = appModel.staleSince(.exactAiring) {
                StaleStrip(since: since, now: now)
                    .padding(.horizontal, ThemeMetrics.gutter).padding(.top, ThemeMetrics.labelGap)
            }
            let d = derived
            if d.allEmpty {
                centred { EmptyState(.nothingScheduled, prominence: .major, ambient: false) }
            } else if d.shownEmpty && filterActive {
                centred {
                    EmptyState(.noFilterMatches, prominence: .major, primary: {
                        FeedbackCoordinator.fire(.selection)
                        withAnimation(ThemeMotion.pick(ThemeMotion.uiSnappy, reduceMotion: reduceMotion)) {
                            typeFilter = .all; unwatchedOnly = false
                        }
                    }, ambient: false)
                }
            } else {
                if !d.earlier.isEmpty {
                    earlierRow(count: d.earlierCount, unwatched: d.earlierUnwatched)
                    if earlierExpanded {
                        ForEach(d.earlier) { day in daySection(day) }
                    }
                }
                ForEach(d.ahead) { day in daySection(day) }
                feedTail
            }
        }
    }

    /// The feed's loading state at THIS screen's geometry — three day blocks of the shared atoms.
    private var feedSkeleton: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<3, id: \.self) { _ in
                SkeletonLine(width: 116, height: 11)
                    .padding(.top, ThemeSpace.x3)
                    .padding(.bottom, ThemeSpace.x2)
                SkeletonRow(poster: PosterSize.row.size,
                            lines: [212, 96], posterRadius: PosterSize.row.radius,
                            height: ThemeMetrics.rowMedia)
                    .padding(.vertical, ThemeSpace.x2)
            }
        }
        .padding(.horizontal, ThemeMetrics.gutter)
        .accessibilityHidden(true)
    }

    // MARK: - Earlier

    /// The aired days, folded. One row that says how much is behind it and how much of that is
    /// still unwatched; opening it reveals the days in place, above today.
    private func earlierRow(count: Int, unwatched: Int) -> some View {
        Button {
            FeedbackCoordinator.fire(.selection)
            earlierExpanded.toggle()
        } label: {
            // The label and its count reflow onto two lines at accessibility sizes rather than
            // truncating the count away — "EARLIER 3 episodes · 1 to…" hid the only number on the
            // row that says whether opening it is worth it.
            let layout = isAX ? AnyLayout(VStackLayout(alignment: .leading, spacing: ThemeSpace.x1))
                              : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: ThemeSpace.x2))
            layout {
                Text(Copy.Schedule.earlier)
                    .type(ThemeType.sectionLabel).textCase(.uppercase)
                    .foregroundStyle(ThemeColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(unwatched > 0 ? "\(Copy.episodes(count)) · \(Copy.Schedule.toWatch(unwatched))" : Copy.episodes(count))
                    .type(ThemeType.rowMeta)
                    .foregroundStyle(unwatched > 0 ? ThemeColor.textSecondary : ThemeColor.textTertiary)
                    .lineLimit(isAX ? nil : 1)
                    .fixedSize(horizontal: false, vertical: true)
                if !isAX { Spacer(minLength: ThemeSpace.x2) }
                if !isAX {
                    Image(systemName: "chevron.forward")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ThemeColor.textDisabled)
                        .rotationEffect(.degrees(earlierExpanded ? 90 : 0))
                        .animation(ThemeMotion.pick(ThemeMotion.uiMicro, reduceMotion: reduceMotion), value: earlierExpanded)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, ThemeMetrics.gutter)
            .padding(.vertical, isAX ? ThemeSpace.x2 : 0)
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .padding(.top, ThemeSpace.x2)
        .id(AgendaID.earlier)
        .accessibilityLabel("\(Copy.Schedule.earlier), \(Copy.episodes(count))\(unwatched > 0 ? ", \(Copy.Schedule.toWatch(unwatched))" : "")")
        .accessibilityHint(earlierExpanded ? Copy.Schedule.hideEarlier : Copy.Schedule.showEarlier)
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Day

    @ViewBuilder
    private func daySection(_ day: Day) -> some View {
        Section {
            if day.isEmpty {
                emptyDayRow
            } else {
                ForEach(Array(day.rows.enumerated()), id: \.element.id) { i, r in
                    row(r, day: day.id, last: i == day.rows.count - 1)
                }
            }
        } header: {
            dayHeader(day)
        }
    }

    /// Today, with nothing on it. Only today can reach this — every other empty day is filtered
    /// out of the feed — and it has to be DRAWN rather than skipped: an agenda whose first
    /// section is a future day, on a screen whose rows carry a bare clock and no date, tells the
    /// reader that a Wednesday 6:30 PM episode is tonight's and that its missing mark control is
    /// a bug. A line that says the day is empty costs 44 pt and removes the whole misreading.
    private var emptyDayRow: some View {
        Text(derived.todayFiltered ? Copy.Schedule.noEpisodes : Copy.Schedule.nothingScheduled)
            .type(ThemeType.rowMeta)
            .foregroundStyle(ThemeColor.textTertiary)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.horizontal, ThemeMetrics.gutter)
    }

    /// "TODAY · MON 24 AUG" / "TOMORROW · TUE 25 AUG" / "WEDNESDAY · 26 AUG". No ground of its
    /// own: the wash is the screen's ground and a plate here would carve a step out of it. The
    /// hairline, inset to the title's leading edge, is what separates one day from the last.
    private func dayHeader(_ day: Day) -> some View {
        let word = dayWord(day)
        let date = Formatting.fmtMonthDay(day.noon)
        let shortDay = String(Formatting.weekdayNameMonFirst(Formatting.localMondayCol(day.noon)).prefix(3))
        let text = day.id == 0 || day.id == 1 ? "\(word) · \(shortDay) \(date)" : "\(word) · \(date)"
        return HStack(alignment: .firstTextBaseline, spacing: ThemeSpace.x2) {
            Text(text)
                .type(ThemeType.sectionLabel).textCase(.uppercase)
                .foregroundStyle(day.isToday ? ThemeColor.accent : ThemeColor.textTertiary)
                .lineLimit(1)
            Spacer(minLength: 0)
            // Only when it says something: "1 EPISODE" over a single row restates the row.
            if day.count > 1 {
                Text(Copy.episodes(day.count))
                    .type(ThemeType.sectionLabel).textCase(.uppercase)
                    .foregroundStyle(ThemeColor.textTertiary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, ThemeMetrics.gutter)
        .padding(.top, ThemeSpace.x4)
        .padding(.bottom, ThemeSpace.x1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle().fill(ThemeColor.separatorQuiet).frame(height: 1)
                .padding(.leading, Metrics.ruleInset)
        }
        .accessibilityElement(children: .ignore)
        // "0 episodes" is a count, not a state. An empty today speaks the same words the line
        // under it prints, so VoiceOver and the screen agree.
        .accessibilityLabel("\(text), \(day.isEmpty ? Copy.Schedule.nothingScheduled : Copy.episodes(day.count))")
        .accessibilityAddTraits(.isHeader)
        .id(AgendaID.day(day.id))
    }

    private func dayWord(_ day: Day) -> String {
        switch day.id {
        case 0: return Copy.Schedule.today
        case 1: return Copy.Schedule.tomorrow
        default: return Formatting.weekdayNameMonFirst(Formatting.localMondayCol(day.noon))
        }
    }

    /// The end of the horizon, and it NAMES the horizon — and it is now true, because the feed
    /// holds every dated episode up to it.
    private var feedTail: some View {
        let text = derived.horizonId.map { Copy.Schedule.everythingThrough(Formatting.fmtMonthDay(appModel.scheduleTodayNoon + Int64($0) * Formatting.D)) }
            ?? Copy.Empty.nothingScheduled.title
        return Text(text)
            .type(ThemeType.rowMeta)
            .foregroundStyle(ThemeColor.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.horizontal, ThemeMetrics.gutter)
            .padding(.top, ThemeSpace.x3)
    }

    // MARK: - Row

    private func row(_ r: Row, day: Int, last: Bool) -> some View {
        let f = r.franchise
        let isCommitted = committed.contains(r.id)
        let watched = r.watched || isCommitted
        // The control stays put through the commit so the check can DRAW in place; only a row
        // that was already watched when the screen loaded starts as a settled one.
        let showsAction = r.aired && !r.watched && appModel.isInLibrary(f.id)
        let batch = r.aired && r.episode > r.part.progress + 1
        let time = r.dateOnly ? nil : Formatting.fmtTime(r.at, anchor: f.timeAnchor)
        let hasReminder = !r.aired && ScheduleReminders.shared.has(mediaId: r.part.mediaId, episode: r.episode)
        // ONE trailing column, and one rule for what is in it: the action while there is something
        // to do, the clock once there is not. The clock is not ALSO appended to the meta line —
        // appended, it wrapped ("Season 5 · Episode 9 ·" / "8:30 PM", a line ending on a separator);
        // inlined into a fixed column beside the ring, it truncated ("…Episode 9 · 8:3…"), which is
        // what the shipped row did. An aired episode's exact minute is the least load-bearing fact
        // on a row that already names its day and offers its action; VoiceOver still speaks it.
        //
        // At ACCESSIBILITY sizes the clock has no column at all: "7:30 PM" set in accessibility type
        // is ~180 pt wide, and holding that beside the title squeezed the title into a ~150-pt lane
        // where it broke inside a word ("Reincarn / ated"). There it joins the meta line, which
        // wraps under the title with the row's full width to use.
        let meta = metaLine(r) + (isAX ? time.map { " · \($0)" } ?? "" : "")
        let zoom = "sched/\(f.id)/\(r.episode)"
        return MediaRow(title: f.displayTitle,
                        meta: meta,
                        poster: f.cover,
                        slot: .row,
                        // No chevron: the row's trailing column is a time or a CONTROL.
                        chevron: false,
                        dimmed: watched,
                        separator: !last,
                        hint: Copy.Accessibility.opensTheShowHint,
                        zoomID: zoom,
                        trailing: {
                            trailing(r, showsAction: showsAction, marked: isCommitted, batch: batch,
                                     time: time, hasReminder: hasReminder)
                        }) {
            onOpenDetail(f.id, zoom, EpisodeFocus(mediaId: r.part.mediaId, episode: r.episode))
        }
        .padding(.horizontal, ThemeMetrics.gutter)
        // The same long-press menu every Library card carries; a row here is the same show.
        .franchiseQuickActions(appModel.isInLibrary(f.id) ? f : nil, appModel: appModel)
        .accessibilityValue(watched ? Copy.Accessibility.complete : (time.map { "\($0)\(hasReminder ? ", \(Copy.Schedule.reminderSet)" : "")" } ?? ""))
        .animation(ThemeMotion.pick(ThemeMotion.uiMicro, reduceMotion: reduceMotion), value: isCommitted)
        .id(AgendaID.row(day, r.id))
    }

    /// The row's one trailing column, RESERVED whether or not it is occupied: the mark ring while
    /// there is something to do, the air time otherwise. Same width for both, so a commit swaps
    /// ink and never moves the row — and a title never loses its clock to a control.
    @ViewBuilder
    private func trailing(_ r: Row, showsAction: Bool, marked: Bool, batch: Bool,
                          time: String?, hasReminder: Bool) -> some View {
        if showsAction {
            MarkRing(marked: marked,
                     style: .quiet,
                     label: batch ? "Mark \(Copy.episodes(r.episode - r.part.progress)) of \(r.franchise.title) as watched"
                                  : "Mark \(Copy.episode(r.episode)) of \(r.franchise.title) as watched",
                     markedLabel: Copy.Progress.episodeWatched(r.episode)) {
                guard !marked else { return }
                mark(r, batch: batch)
            }
            .frame(width: Metrics.stateColumn, alignment: .trailing)
            .transition(.handoff(reduceMotion: reduceMotion))
        } else {
            HStack(alignment: .firstTextBaseline, spacing: ThemeSpace.x1) {
                if hasReminder {
                    Image(systemName: "bell.fill").font(.system(size: 10))
                        .foregroundStyle(ThemeColor.textDisabled)
                        .accessibilityHidden(true)
                }
                // The clock lives in the meta line at accessibility sizes (see `meta`), so the
                // column carries nothing but the reminder bell there.
                if let time, !isAX {
                    // Amber while the episode is still ahead — the app's one colour rule for a
                    // time — grey once it has aired.
                    Text(time).type(ThemeType.time)
                        .foregroundStyle(r.aired ? ThemeColor.textSecondary : ThemeColor.accent)
                        .lineLimit(1)
                }
            }
            .frame(minWidth: isAX ? 0 : Metrics.stateColumn, alignment: .trailing)
            .accessibilityHidden(true)
        }
    }

    /// One meta line for both sources: THE watch-context rule (a single-part show prints no
    /// season), shared with Today — and a same-day drop says how many.
    private func metaLine(_ r: Row) -> String {
        let n = r.episodes.count
        if n > 1 {
            let label = r.part.canonicalLabel
            let drop = "\(Copy.episodes(n))"
            return label.isEmpty || r.franchise.parts.count == 1 ? drop : "\(label) · \(drop)"
        }
        return r.franchise.watchContext(part: r.part, episode: r.episode)
    }

    // MARK: - Mark as watched (the only write)

    private func mark(_ r: Row, batch: Bool) {
        let f = r.franchise, part = r.part
        if batch {
            let count = r.episode - part.progress
            prompt = .init(title: Copy.Confirm.batchMarkTitle(count),
                           message: Copy.Confirm.batchMarkMessage(from: part.progress, to: r.episode),
                           confirm: Copy.Confirm.batchMarkConfirm(count)) {
                let prev = part.progress
                appModel.setProgress(franchiseId: f.id, mediaId: part.mediaId, episodes: r.episode)
                commit(r) {
                    appModel.presentUndo(UndoState(mediaId: part.mediaId, franchiseId: f.id, prevProgress: prev,
                                                   title: f.title, episode: r.episode, count: count))
                }
            }
            return
        }
        guard let undo = appModel.markNext(franchiseId: f.id, mediaId: part.mediaId) else { return }
        commit(r) { appModel.presentUndo(undo) }
    }

    /// The control fills and the check draws in place; the row settles into its dimmed state and
    /// stays (a calendar keeps its history) — unless watched rows are hidden, in which case it
    /// leaves after a short hold.
    private func commit(_ r: Row, then present: @escaping () -> Void) {
        _ = withAnimation(ThemeMotion.pick(ThemeMotion.uiMicro, reduceMotion: reduceMotion)) {
            committed.insert(r.id)
        } completion: {
            if unwatchedOnly {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(650))
                    _ = withAnimation(ThemeMotion.pick(ThemeMotion.uiSettle, reduceMotion: reduceMotion)) {
                        committed.remove(r.id)
                    } completion: { present() }
                }
            } else {
                present()
            }
        }
    }
}

/// The ticker cell's press feedback: the app's compression floor and a dip, nothing painted.
private struct TickerCellPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.985 : 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(ThemeMotion.pick(ThemeMotion.uiPress, reduceMotion: reduceMotion),
                       value: configuration.isPressed)
    }
}
