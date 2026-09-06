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
    /// A day the reader picked on the strip that has nothing on it. It is drawn as an empty
    /// section ("Nothing scheduled") so the pick lands somewhere — every day on the strip is a
    /// target now (4 Sep). The aired days are no longer folded behind an "Earlier" row: the past
    /// is simply above today in the feed, as in Calendar's list, and the strip's dimmed cells
    /// are the way back to it ("the day strip … the EARLIER row" were the confusion, user).
    @State private var pinnedEmptyDay: Int? = nil

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
    /// The day the feed is showing, recorded during the scroll and read only when it stops — so
    /// the calendar's highlight never moves while the feed is moving (6 Sep).
    @State private var readingDay = 0
    /// Any day inside the month the calendar is showing, as an offset from today.
    @State private var monthAnchor = 0
    /// Whether the calendar is down. At rest it is NOT: the screen's whole point is that it has no
    /// date chrome until the reader asks for one.
    @State private var monthOpen = ScheduleDebug.monthOpen
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
        /// Between two airings on one day.
        static let rowGap: CGFloat = ThemeSpace.x4
        /// Between one day and the next. NOT `ThemeMetrics.sectionGap` (30): a schedule is sparse —
        /// measured on the test library ten of the window's twenty-two days carry an episode and
        /// none carries more than one — so at the section gap a feed of one-row days was half
        /// header by area, and the eyebrow floated between two rows belonging to neither.
        static let dayGap: CGFloat = ThemeSpace.x6
    }

    /// The artwork the wash is derived from: the next thing to air, else the most recent thing
    /// that did, else whatever the library leads with on a screen with nothing scheduled.
    private var washCover: String? {
        let d = derived
        // `first(where:)`, not `first`: today leads `ahead` even when it is empty, and an empty
        // day would otherwise hand the wash to the LAST thing that aired instead of the next.
        if let next = d.ahead.first(where: { !$0.isEmpty })?.rows.first?.franchise.portraitArt { return next }
        if let last = d.earlier.last?.rows.last?.franchise.portraitArt { return last }
        return appModel.library.first?.portraitArt
    }

    // MARK: - Identity

    /// Every scroll target in the feed maps back to a day, so the position the system reports —
    /// whichever header or row happens to be at the top — names the day the ticker should show.
    enum AgendaID: Hashable {
        case day(Int)
        case row(Int, String)

        var day: Int {
            switch self {
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
        /// `-scheduleDemoStates 1`: the id of the one aired row drawn as UNWATCHED, so the three
        /// states can be photographed together. The test account has none of its own — both past
        /// airings are watched — and a ladder cannot be judged with a rung missing.
        var demoUnwatched: String? = nil
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
        if ScheduleDebug.demoStates { out.demoUnwatched = out.earlier.last?.rows.last?.id }
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

    /// The day strip stays up while the first library loads — its days come from the clock,
    /// not the data — so the feed lands under it instead of shoving everything down 60 pt the
    /// instant the response arrives. Only a settled whole-screen state folds it away, animated.
    private var tickerCollapsed: Bool {
        // Never mid-load — neither the first one (its days come from the clock, not the data) nor
        // a refresh, which passes through a moment with no derived days: folding on that moment is
        // what made the rail collapse and re-expand while the feed was being read (6 Sep, device).
        !appModel.loading && showsWholeScreenState
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
                .animation(ThemeMotion.pick(ThemeMotion.uiSnappy, reduceMotion: reduceMotion), value: pinnedEmptyDay)
                // The stale strip arrives on the 30-minute clock while the feed is being read;
                // it used to snap in and push every row down unannounced.
                .animation(ThemeMotion.pick(ThemeMotion.uiGentle, reduceMotion: reduceMotion),
                           value: appModel.staleSince(.exactAiring) != nil)
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
            .laneClearance(appModel)
            .scrollIndicators(.hidden)
            // The moment a finger touches the feed it belongs to the reader.
            .onScrollPhaseChange { _, phase in
                if phase == .interacting { userScrolled = true }
                // At rest, the calendar's selection moves to the day that was read — and only at
                // rest: every automatic movement of a date control while the feed was moving was
                // read as "bouncing" (five rounds of it, 6 Sep).
                if phase == .idle, readingDay != selectedDay {
                    withAnimation(ThemeMotion.pick(ThemeMotion.uiGentle, reduceMotion: reduceMotion)) {
                        selectedDay = readingDay
                        // The calendar follows the feed across a month boundary, so opening it
                        // never shows a month the reader has scrolled away from.
                        monthAnchor = readingDay
                    }
                }
            }
            // The system says which targets are on screen; the earliest day among them is the
            // section at the top. No coordinate spaces, no pin-line arithmetic — the one thing the
            // previous screen got wrong in every capture.
            .onScrollTargetVisibilityChange(idType: AgendaID.self, threshold: 0.2) { ids in
                // Only RECORDED here; the calendar's selection reads it when the feed comes to
                // rest. Following live meant the highlight hopped from cell to cell mid-drag and,
                // at a section boundary where the reported day flips between two values, hopped
                // back and forth — read as the dates bouncing around (user, 6 Sep).
                guard let day = ids.map(\.day).min() else { return }
                readingDay = day
            }
            // The calendar OVERLAYS the feed (Google Calendar's month dropdown), it does not push
            // it: 500 pt of grid inserted above a lazy stack threw the reader's place three
            // screens down and back again on every toggle. Last in the stack, so it is above the
            // feed; it hangs from the chrome band's bottom edge, so it reads as coming out of the
            // bar.
            calendarOverlay(proxy)
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
        .chromeScrollEdgeHidden(.all)
        .previouslyRefreshable { await appModel.reload() }
        .task { await ScheduleReminders.shared.refresh() }
        // The feed opens on TODAY — which is no longer its first item, now that the past sits
        // above it — whenever the feed's identity changes and the reader has not taken the wheel.
        // Once more a beat later: the first pass can run before the lazy stack has laid out the
        // sections above today, and land short.
        .onChange(of: derived.feedKey, initial: true) { _, _ in land(proxy) }
        .task {
            try? await Task.sleep(for: .milliseconds(250))
            land(proxy)
        }
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
                            // Explicitly `interactive`: unstyled, this inherited the app-wide
                            // accent tint and rendered as an amber tappable word — the exact
                            // collision the `interactive` token exists to forbid, worst on the
                            // one screen where amber means "today".
                            .tint(ThemeColor.interactive)
                            .accessibilityLabel(Copy.Schedule.scrollToToday)
                            .accessibilityHint(Copy.Schedule.scrollToTodayHint)
                            .transition(.opacity)
                    }
                }
                .animation(ThemeMotion.pick(ThemeMotion.uiGentle, reduceMotion: reduceMotion), value: awayFromToday)
            }
            // The calendar's switch. A TAP, not a pull — Fantastical pulls its DayTicker down
            // into a month, but this screen already owns the pull gesture for refresh. ONE glyph
            // in both states, tinted when the grid is down: a control that changes its symbol on
            // press reads as a different control (`calendar.badge.minus` also means "remove an
            // event", which this has never done).
            ToolbarItem(placement: .topBarTrailing) {
                Button { toggleCalendar() } label: { Image(systemName: "calendar") }
                    .tint(monthOpen ? ThemeColor.accent : ThemeColor.textPrimary)
                    .accessibilityLabel(Copy.Schedule.calendar)
                    .accessibilityValue(monthOpen ? Copy.Schedule.calendarShown : Copy.Schedule.calendarHidden)
            }
            ToolbarItem(placement: .topBarTrailing) { filterMenu }
        }
        // An alert, not a popover pinned under the bar 180 pt from the ring (interactive review):
        // a batch changes a number the user did not type, and it always offers Cancel.
        .alert(prompt?.title ?? "", isPresented: Binding(get: { prompt != nil }, set: { if !$0 { prompt = nil } }),
               presenting: prompt) { p in
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
    private var awayFromToday: Bool { selectedDay != 0 }

    // MARK: - Scrolling

    /// The feed opens on today's section, un-animated, with the past above it and the ticker's
    /// first visible cell today. True on a day with nothing on it too, since an empty today still
    /// renders: the agenda always opens where the reader is standing. (It used to open on a
    /// folded "Earlier" row with today under it; the fold is gone.)
    private func land(_ proxy: ScrollViewProxy) {
        guard !userScrolled, !appModel.library.isEmpty, !showsWholeScreenState else { return }
        var t = Transaction()
        t.disablesAnimations = true
        // An empty today over yesterday's unwatched drop lands on THAT card (interactive review:
        // the one card to act on sat above the landing with its caption under the ticker), with
        // today's section right beneath it; the Today button is one tap.
        let d = derived
        let target: Int = {
            // `-scheduleDemoStates`: open on the aired days, which is where the ladder's other two
            // rungs are. The demo is a DRAWING override, so the real landing rule below cannot see
            // the row it un-watches.
            if ScheduleDebug.demoStates, let e = d.earlier.first { return e.id }
            guard let today = d.ahead.first, today.id == 0, today.rows.isEmpty,
                  let y = d.earlier.last, y.id >= -2, y.rows.contains(where: { !$0.watched }) else { return 0 }
            return y.id
        }()
        withTransaction(t) { proxy.scrollTo(AgendaID.day(target), anchor: .top) }
        if selectedDay != target { selectedDay = target }
        readingDay = target
    }

    /// A strip tap: the feed lands on that day's section. A day with nothing on it gets one drawn
    /// for the purpose (`pinnedEmptyDay`) a beat before the scroll, so there is a section to land on.
    private func pick(_ offset: Int, count: Int, proxy: ScrollViewProxy) {
        if count == 0 && offset != 0 {
            pinnedEmptyDay = offset
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(60))
                scroll(to: .day(offset), day: offset, proxy: proxy)
            }
        } else {
            scroll(to: .day(offset), day: offset, proxy: proxy)
        }
    }

    private func scroll(to id: AgendaID, day: Int, proxy: ScrollViewProxy) {
        userScrolled = true
        selectedDay = day
        readingDay = day
        // The calendar follows an explicit move as well as a scroll, so pressing Today with the
        // grid open does not leave it on a month the feed has left.
        monthAnchor = day
        withAnimation(ThemeMotion.pick(ThemeMotion.uiReveal, reduceMotion: reduceMotion)) {
            proxy.scrollTo(id, anchor: .top)
        }
    }

    /// Back to today's section.
    private func goToToday(_ proxy: ScrollViewProxy) {
        FeedbackCoordinator.fire(.selection)
        scroll(to: .day(0), day: 0, proxy: proxy)
    }

    // MARK: - The calendar

    /// The grid, a scrim, and the rules for getting out of it. Mounted only while it is down —
    /// a held-at-zero-opacity overlay over a scrolling feed is a composited layer per frame.
    @ViewBuilder
    private func calendarOverlay(_ proxy: ScrollViewProxy) -> some View {
        if monthOpen {
            ZStack(alignment: .top) {
                // Anywhere off the grid closes it, as a menu does. No dimming of the feed: the
                // grid has its own surface and a tap-to-dismiss, and a scrim over a schedule the
                // reader is trying to read against is theatre.
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { toggleCalendar() }
                    .accessibilityHidden(true)
                ScheduleMonthGrid(todayNoon: appModel.scheduleTodayNoon, counts: derived.counts,
                                  live: derived.live, selected: selectedDay,
                                  window: AppModel.scheduleBack...AppModel.scheduleAhead,
                                  monthAnchor: $monthAnchor,
                                  maxHeight: max(260, viewportH - ThemeMetrics.tabBarClearance)) { day in
                    // A pick closes the calendar. Leaving it down over the day it just took you to
                    // means the answer is hidden behind the question.
                    toggleCalendar()
                    pick(day, count: derived.counts[day] ?? 0, proxy: proxy)
                }
                // GLASS over the feed, not a flat grey slab: the panel is chrome that floats,
                // which is what every other floating surface in the app is made of, and #242428
                // filling a third of the screen read as a debug view. The canvas veil under the
                // material is what keeps the numerals legible over busy art — the same pairing
                // the bars use (`chromeBarOpacity`).
                .background(ThemeColor.canvas.opacity(0.62),
                            in: RoundedRectangle(cornerRadius: ThemeRadius.card, style: .continuous))
                .glassChrome(in: RoundedRectangle(cornerRadius: ThemeRadius.card, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: ThemeRadius.card, style: .continuous)
                    .strokeBorder(ThemeColor.stroke, lineWidth: 1))
                .shadow(.card)
                .padding(.horizontal, ThemeSpace.x3)
                .padding(.top, ThemeSpace.x1)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            .zIndex(2)
        }
    }

    private func toggleCalendar() {
        FeedbackCoordinator.fire(.selection)
        withAnimation(ThemeMotion.pick(ThemeMotion.uiSnappy, reduceMotion: reduceMotion)) {
            monthOpen.toggle()
        }
    }

    // MARK: - Chrome

    /// The band under the title: the day ticker, and the active filters as removable tokens.
    /// Opaque canvas, the same the navigation bar is painted in, so the two are one surface.
    @ViewBuilder
    private func chrome(_ proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // The band draws no date control — the feed's day headers are the calendar, and the
            // grid is an OVERLAY (see `calendarOverlay`), not a member of this stack. It is still
            // not nothing: it paints the ground behind the navigation bar, which this screen hides
            // the system's copy of.
            Color.clear.frame(height: 1)
            filterChips
        }
        // Only the filter chips can give this band height, so only they earn its padding.
        .padding(.bottom, filterActive ? ThemeSpace.x2 : 0)
        .animation(ThemeMotion.pick(ThemeMotion.uiGentle, reduceMotion: reduceMotion), value: filterActive)
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
        //
        // The ground is drawn at a STATED height, bottom-aligned to the band — not by letting
        // `ignoresSafeArea` grow the band's own frame upward. `chromeBottom` is the band's bottom
        // edge in global space, so a view of exactly that height whose bottom sits there spans
        // y = 0 → the band's bottom, whatever the band contains. With the band's intrinsic height
        // doing the work, a band with NOTHING in it (`none`, and `month` with the grid up) drew a
        // zero-height ground and the feed printed through the status bar and the word "Schedule" —
        // the bug that was blamed on the header-less direction itself on 6 Sep and killed it. It
        // was never that direction's bug; it was this background's.
        .background(alignment: .bottom) {
            ZStack(alignment: .top) {
                ThemeColor.canvas
                ArtBackdrop(url: washCover, tint: washCover == nil ? ThemeColor.accent : nil,
                            height: max(chromeBottom, ThemeMetrics.topChromeHeight),
                            intensity: ThemeMetrics.rootWashIntensity)
            }
            .frame(height: max(chromeBottom, ThemeMetrics.topChromeHeight))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.frame(in: .global).maxY },
                          action: { chromeBottom = $0 })
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
        Binding(get: { typeFilter }, set: { typeFilter = $0 })
    }

    private var hideWatchedBinding: Binding<Bool> {
        Binding(get: { unwatchedOnly }, set: { unwatchedOnly = $0 })
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
            // Through the gate every other root uses: no skeleton before 240 ms, so a fast
            // answer never flashes structure. (The feed stays a lazy stack, so the gate holds
            // the skeleton alone and the swap rides the stack's own `feedKey` animation.)
            SkeletonGate(isLoading: true) { feedSkeleton } content: { EmptyView() }
        } else if appModel.loadError && appModel.libraryEmpty {
            centred {
                EmptyState(SyncCenter.shared.isOnline ? .serverNoCache : .offlineNoData,
                           prominence: .major,
                           primary: { Task { await appModel.reload() } })
            }
        } else if appModel.libraryEmpty {
            centred { EmptyState(.emptySchedule, prominence: .major, primary: onAddShow) }
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
                centred { EmptyState(.nothingScheduled, prominence: .major) }
            } else if d.shownEmpty && filterActive {
                centred {
                    EmptyState(.noScheduleMatches, prominence: .major, primary: {
                        FeedbackCoordinator.fire(.selection)
                        withAnimation(ThemeMotion.pick(ThemeMotion.uiSnappy, reduceMotion: reduceMotion)) {
                            typeFilter = .all; unwatchedOnly = false
                        }
                    })
                }
            } else {
                // The past, then today (always), then what is ahead — one agenda, no fold. The
                // feed lands on today (`land`); the calendar's dimmed cells are the way back.
                ForEach(daysToDraw(d)) { day in dateColumnDay(day) }
                feedTail
            }
        }
    }

    /// The feed's loading state at THIS screen's geometry — three day blocks in the airing card's
    /// anatomy (header, 16:9 art, title, meta), so the swap lands in place. It drew poster rows
    /// until 3 Sep, the row the calendar stopped using.
    private var feedSkeleton: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<3, id: \.self) { _ in
                SkeletonLine(width: 116, height: 11)
                    .padding(.top, ThemeMetrics.sectionGap)
                    .padding(.bottom, ThemeMetrics.labelGap)
                SkeletonBlock(height: nil, radius: ThemeRadius.card)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                SkeletonLine(width: 212, height: 13)
                    .padding(.top, ThemeSpace.x2)
                SkeletonLine(width: 96, height: 10)
                    .padding(.top, ThemeSpace.x1)
            }
        }
        .padding(.horizontal, ThemeMetrics.gutter)
        .accessibilityHidden(true)
    }

    // MARK: - Days

    /// The feed's days: the past, today (always), everything ahead that carries something — and
    /// the one empty day the reader picked on the strip, drawn as a section that says "Nothing
    /// scheduled" so the pick lands somewhere instead of doing nothing.
    private func daysToDraw(_ d: Derived) -> [Day] {
        var days = d.earlier + d.ahead
        if let pinned = pinnedEmptyDay, pinned != 0, !days.contains(where: { $0.id == pinned }) {
            let noon = appModel.scheduleTodayNoon + Int64(pinned) * Formatting.D
            days.append(Day(id: pinned, noon: noon, rows: []))
            days.sort { $0.id < $1.id }
        }
        return days
    }

    // MARK: - Day

    /// What an empty today says. "No episodes" when the filter is what emptied it.
    private var emptyDayText: String {
        derived.todayFiltered ? Copy.Schedule.noEpisodes : Copy.Schedule.nothingScheduled
    }

    /// The first day drawn in the feed.
    private func isFirstDay(_ day: Day) -> Bool {
        (derived.earlier + derived.ahead).first?.id == day.id
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

    /// Everything a row needs, whatever anatomy draws it — computed once, so the four shapes
    /// cannot disagree about a row's state the way the pre-6-Sep card's three corners did.
    private struct RowFacts {
        let state: AiringState
        let time: String?
        let hasReminder: Bool
        let zoom: String
        let isCommitted: Bool
        let batch: Bool
        let count: Int
        /// The show is in the library and the episode has aired, so there is progress to write.
        let showsAction: Bool
        let host: String
    }

    private func facts(_ r: Row) -> RowFacts {
        let f = r.franchise
        let isCommitted = committed.contains(r.id)
        // `-scheduleDemoStates`: one aired row is drawn as though it were still waiting, so the
        // ladder can be photographed with all three rungs.
        let demoUnseen = derived.demoUnwatched == r.id && !isCommitted
        // The control stays put through the commit so the check can DRAW in place; only a row that
        // was already watched when the screen loaded starts as a settled one.
        let watched = (r.watched && !demoUnseen) || isCommitted
        return RowFacts(state: !r.aired ? .upcoming : (watched ? .watched : .toWatch),
                        time: r.dateOnly ? nil : Formatting.fmtTime(r.at, anchor: f.timeAnchor),
                        hasReminder: !r.aired && ScheduleReminders.shared.has(mediaId: r.part.mediaId,
                                                                             episode: r.episode),
                        zoom: "sched/\(f.id)/\(r.episode)",
                        isCommitted: isCommitted,
                        batch: r.aired && r.episode > r.part.progress + 1,
                        count: r.episode - r.part.progress,
                        showsAction: r.aired && !watched && appModel.isInLibrary(f.id),
                        host: ReceiptHost.schedule(r.part.mediaId, r.episode))
    }

    private func openAction(_ r: Row, _ x: RowFacts) -> () -> Void {
        { onOpenDetail(r.franchise.id, x.zoom,
                       EpisodeFocus(mediaId: r.part.mediaId, episode: r.episode)) }
    }

    private func ladder(_ r: Row, _ x: RowFacts) -> some View {
        AiringStateControl(state: x.state, episode: r.episode, committing: x.isCommitted,
                           title: r.franchise.title, batch: x.batch,
                           count: x.count, canMark: x.showsAction) {
            guard !x.isCommitted else { return }
            mark(r, batch: x.batch)
        }
    }

    // MARK: - The feed

    /// No header: the day's FIRST row carries the date and the rest stack under it, so a day costs
    /// nothing until it has something to say (Google Calendar's Schedule view).
    @ViewBuilder
    private func dateColumnDay(_ day: Day) -> some View {
        VStack(alignment: .leading, spacing: Metrics.rowGap) {
            if day.isEmpty {
                emptyDateRow(day)
            } else {
                ForEach(Array(day.rows.enumerated()), id: \.element.id) { i, r in
                    dateRow(r, day: day, showsDate: i == 0)
                }
            }
        }
        // A day break, not a section break — there is no band to give air to any more.
        .padding(.top, isFirstDay(day) ? ThemeSpace.x3 : ThemeSpace.x5)
        .id(AgendaID.day(day.id))
    }

    private func dateRow(_ r: Row, day: Day, showsDate: Bool) -> some View {
        let f = r.franchise
        let x = facts(r)
        return ScheduleDateRow(weekday: showsDate ? shortWeekday(day) : nil,
                               numeral: showsDate ? dayNumeral(day) : nil,
                               isToday: day.isToday,
                               franchise: f,
                               episodeText: episodeText(r), time: x.time, state: x.state,
                               hasReminder: x.hasReminder, zoomID: x.zoom,
                               receiptHost: x.host,
                               trailing: { ladder(r, x) }, action: openAction(r, x))
            .padding(.horizontal, ThemeMetrics.gutter)
            .franchiseQuickActions(appModel.isInLibrary(f.id) ? f : nil, appModel: appModel)
            .animation(ThemeMotion.pick(ThemeMotion.uiMicro, reduceMotion: reduceMotion), value: x.isCommitted)
            .id(AgendaID.row(day.id, r.id))
    }

    /// Today with nothing on it, in shape A's anatomy: the date keeps its column, so the one day
    /// with no body still has the same shape as every day that has one.
    private func emptyDateRow(_ day: Day) -> some View {
        HStack(alignment: .top, spacing: ThemeSpace.x3) {
            ScheduleDateColumn(weekday: shortWeekday(day), numeral: dayNumeral(day),
                               isToday: day.isToday)
            Text(emptyDayText)
                .type(ThemeType.rowMeta)
                .foregroundStyle(ThemeColor.textTertiary)
                .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
        }
        .padding(.horizontal, ThemeMetrics.gutter)
        .accessibilityElement(children: .combine)
    }

    private func shortWeekday(_ day: Day) -> String {
        Formatting.weekdayShortMonFirst(Formatting.localMondayCol(day.noon))
    }

    private func dayNumeral(_ day: Day) -> String { "\(Formatting.localParts(day.noon).d)" }

    // MARK: - What the row says

    /// What actually VARIES down the feed, with the season dropped. A weekly show cannot leave its
    /// season inside a 22-day window, so on this screen "Season 4" is a constant printed once per
    /// row — the biggest single contributor to the run-on grammar the spike is testing against.
    private func episodeText(_ r: Row) -> String {
        let n = r.episodes.count
        return n > 1 ? Copy.episodes(n) : Copy.episode(r.episode)
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
                                                   title: f.title, episode: r.episode, count: count)
                                            .placed(at: ReceiptHost.schedule(part.mediaId, r.episode)))
                }
            }
            return
        }
        guard let undo = appModel.markNext(franchiseId: f.id, mediaId: part.mediaId) else { return }
        // In place, under the card's caption.
        commit(r) { appModel.presentUndo(undo.placed(at: ReceiptHost.schedule(part.mediaId, r.episode))) }
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

