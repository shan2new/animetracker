import SwiftUI

// Schedule (spec board 04). One chronological feed hung on a timeline rail: an ambient art wash
// under the navigation bar and a pinned week strip, day headers that stick while their rows scroll
// under them, ~100-pt event rows on a 22-pt rail gutter, and a NOW marker that crosses today.
//
// What this pass fixed (panel round 1, items SC-1 … SC-28):
//   · the screen hid the navigation bar and hand-rolled a header whose ground ended in a hard
//     horizontal seam across the full width. It now owns a real navigation bar with a large title
//     and a real toolbar (which is also what finally lets the filter menu anchor beside its
//     trigger instead of over it), and ONE continuous glass runs from the status bar down through
//     the week strip and ramps out — no seam anywhere;
//   · day headers were not pinned, so one scroll stranded a row with no date above it. They are
//     `Section` headers now, pinned, and they pick up the strip's glass exactly while they stick;
//   · landing on today was `asyncAfter(0.05) { proxy.scrollTo }` — an unanimated teleport on a
//     guessed timer that silently no-opped if the lazy stack had not materialised the anchor. The
//     first rendered frame is now already at today (`ScrollPosition`), with a *guarded* backstop
//     that keeps correcting until the anchor genuinely exists;
//   · the month label sat beside a count scoped to the week ("AUGUST 2026 · 3 EPISODES"). The
//     label names the week it counts now, and the strip pages week by week — the screen had no way
//     to see next week at all;
//   · the episode number printed a season only for TMDB rows, so Slime read "Episode 20" here and
//     "Season 4 · Episode 19" on its own detail screen. One `Copy.watchContext` for both sources;
//   · the strip encoded one fact two contradictory ways (weight said past/future, a 4-pt colour-only
//     dot said something else). Past dims as a group; the dot carries only "has episodes", at 6 pt,
//     distinguished by shape rather than hue;
//   · the selected date was the brightest, most saturated object on a screen about shows;
//   · the rail cut at both ends and every future node was the app's dimmest neutral — a column of
//     disabled-looking rings down a list of things that have not happened yet;
//   · at accessibility sizes the air time detached from its row and the week count silently
//     vanished. The time leads the row at AX and the count reflows under the label.
//
// The only write here is "Mark as watched" on a row that has aired.
struct ScheduleView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var typeSize
    let onOpenDetail: (_ franchiseId: String, _ zoomID: String, _ focus: EpisodeFocus?) -> Void
    var onAddShow: () -> Void = {}

    @State private var selectedDay = 0
    /// The day whose header is at the top of the feed; the strip follows it while scrolling.
    @State private var visibleDay = 0
    /// The day header currently stuck to the top of the content area, so only that one takes the
    /// chrome ground. Every header carrying glass at rest would be six glass bands down one screen.
    @State private var pinnedDay: Int?
    /// Day id → its header's y in the feed's coordinate space. Drives the pin, the strip and the
    /// distance-aware scroll (a spring must not drive an arbitrary-distance lazy scroll).
    ///
    /// A REFERENCE box, not `@State`: a scroll emits a preference change per frame, and writing
    /// that into `@State` re-evaluated the body — which recomputes the feed and re-emits the
    /// preference — every frame. The view live-locked and the scroll view stopped scrolling at all.
    /// Only the two derived facts that change rarely (`pinnedDay`, `visibleDay`) are state.
    @State private var offsets = DayOffsetBox()
    /// The feed is under the USER's control: they have dragged it, tapped a date or tapped Today.
    /// Until then the screen owns its own position and keeps today at the top; only afterwards does
    /// scroll tracking drive the strip.
    @State private var didLand = false
    /// Bounded, so a today that physically cannot reach the top (nothing below it to scroll into)
    /// stops asking rather than fighting the scroll view every frame.
    @State private var landAttempts = 0
    @State private var landGaveUp = false
    /// The week the strip is showing, in whole weeks from the week containing today.
    @State private var weekPage: Int? = 0
    @State private var typeFilter: MediaFilter = .all
    @State private var unwatchedOnly = false
    @State private var committed: Set<String> = []
    @State private var prompt: FranchiseDetailView.WritePrompt?
    /// The landing position, set BEFORE the first layout so the opening frame is already on today
    /// rather than rendering from the top of the week and jumping afterwards.
    @State private var position = ScrollPosition(id: 0, anchor: .top)
    @State private var viewportH: CGFloat = 720
    /// The strip's own height. A horizontal `ScrollView` inside a `safeAreaInset` is greedy on its
    /// cross axis and will happily eat the whole screen, so the strip states what it needs.
    @ScaledMetric(relativeTo: .subheadline) private var stripHeight: CGFloat = 74

    private var now: Int64 { appModel.now }
    private var nowMinute: Int64 { (now / Formatting.minuteMs) * Formatting.minuteMs }
    private var isAX: Bool { typeSize.isAccessibilitySize }

    // MARK: - Geometry
    //
    // The rail lives in the leading gutter, reusing the History timeline's numbers so the app has
    // one rail and not two. Art is 56×84: the original Schedule's poster was ~56 wide and shrinking
    // it to 36 is most of why this screen stopped looking like a media app.

    private enum Rail {
        static let x = HistoryRailMetrics.railX          // 4 pt from the day block's leading edge
        static let gutter = HistoryRailMetrics.cardX     // 22 pt: where row content starts
        static let posterW: CGFloat = 56
        static let posterH: CGFloat = 84
        /// The poster grows at accessibility sizes so it stays the row's anchor instead of a
        /// stranded thumbnail at the top-left of a 230-pt row.
        static let posterAXW: CGFloat = 72
        static let posterAXH: CGFloat = 108
    }

    /// Node geometry answers to Dynamic Type — a 4-pt mark does not read as a ring at AX5 any more
    /// than it does at default size.
    @ScaledMetric(relativeTo: .footnote) private var node: CGFloat = 8
    private var nodeStroke: CGFloat { max(1.5, node * 0.1875) }

    // MARK: - Feed

    struct Event: Identifiable {
        let franchise: Franchise
        let part: FranchisePart
        let episode: Int
        let at: Int64
        let aired: Bool
        let dateOnly: Bool
        var id: String { "\(franchise.id)/\(episode)/\(aired ? "a" : "n")" }
        var watched: Bool { aired && part.progress >= episode }
    }

    struct Day: Identifiable {
        let id: Int
        let isToday: Bool
        let header: String
        let dateOnly: [Event]
        let timed: [Event]
        var isEmpty: Bool { dateOnly.isEmpty && timed.isEmpty }
        var count: Int { dateOnly.count + timed.count }
    }

    private var unfilteredDays: [Day] { appModel.scheduleDays.map(day(from:)) }

    private var days: [Day] {
        unfilteredDays.map { d in
            Day(id: d.id, isToday: d.isToday, header: d.header,
                dateOnly: d.dateOnly.filter(passes), timed: d.timed.filter(passes))
        }
    }

    private func passes(_ e: Event) -> Bool {
        switch typeFilter {
        case .all: break
        case .anime: if e.franchise.source != .anilist { return false }
        case .tv: if e.franchise.source != .tmdb { return false }
        }
        if unwatchedOnly && e.watched { return false }
        return true
    }

    private func day(from d: AppModel.ScheduleDay) -> Day {
        var events: [Event] = []
        for f in d.airedToday {
            guard let part = f.releasingPart, let at = part.lastAiredAt else { continue }
            events.append(Event(franchise: f, part: part, episode: part.airedEpisodes, at: at, aired: true, dateOnly: f.timeAnchor.isDateOnly))
        }
        for f in d.franchises {
            guard let part = f.releasingPart, let at = part.nextAiringAt else { continue }
            let ep = part.nextEpisodeNumber ?? part.airedEpisodes + 1
            events.append(Event(franchise: f, part: part, episode: ep, at: at, aired: false, dateOnly: f.timeAnchor.isDateOnly))
        }
        let short = String(d.label.prefix(3))
        let header = d.isToday ? "Today · \(short) \(d.dateLabel)" : "\(short) · \(d.dateLabel)"
        return Day(id: d.id, isToday: d.isToday, header: header,
                   dateOnly: events.filter(\.dateOnly).sorted { $0.at < $1.at },
                   timed: events.filter { !$0.dateOnly }.sorted { $0.at < $1.at })
    }

    private var filterActive: Bool { typeFilter != .all || unwatchedOnly }

    /// The days actually drawn, in order. Today is always drawn even when it is empty — it is this
    /// screen's anchor.
    private var visibleDays: [Day] { days.filter { !$0.isEmpty || $0.isToday } }

    /// The identity of the whole feed, so a filter change animates as one structural change rather
    /// than being scoped to a value it has nothing to do with.
    private var feedKey: [Int] { visibleDays.map { $0.id * 1000 + $0.count } }

    /// The next day at or after today that carries something. Names the strip's one filled dot and
    /// the "next up" line when today is empty.
    private var nextEventDay: Day? { days.first { $0.id >= 0 && !$0.isEmpty } }

    /// The artwork the ambient wash is derived from: the next thing to air, else the most recent
    /// thing that did. One already-cached image, drawn once, never animated.
    private var ambientCover: String? {
        let all = unfilteredDays
        if let upcoming = all.first(where: { $0.id >= 0 && !$0.isEmpty }) {
            return (upcoming.timed.first ?? upcoming.dateOnly.first)?.franchise.cover
        }
        return all.last(where: { !$0.isEmpty }).flatMap { ($0.timed.last ?? $0.dateOnly.last)?.franchise.cover }
    }

    /// A live calendar must not assert a selected date over a surface that says there is nothing.
    private var surfaceEmpty: Bool { appModel.libraryEmpty }

    // MARK: - Body

    var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .top) {
                // No ambient wash here. Schedule was never in the direction's ambient list, and the
                // colour this screen derives — three covers averaged into a desaturated olive-brown
                // — reads as a dirty screen on a true-black OLED ground rather than as atmosphere.
                // It can come back the moment the palette refuses low-saturation 60–110° hues (see
                // the shared-file request); until then a clean canvas under full-colour posters is
                // the better frame.
                ScrollView {
                    // Pinned section headers: the screen's premise is that a date section supplies
                    // each row's context, and that premise broke the moment the user scrolled.
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        content()
                    }
                    .scrollTargetLayout()
                    // A user-requested layout change (a filter) is what `uiSnappy` is for, and it
                    // belongs on the thing that re-lays out. It used to sit on the whole ScrollView
                    // keyed on `selectedDay != 0`, so choosing "Anime" was an instant cut while any
                    // unrelated identity change animated.
                    .animation(ThemeMotion.pick(ThemeMotion.uiSnappy, reduceMotion: reduceMotion), value: feedKey)
                }
                .coordinateSpace(name: "schedule.feed")
                .scrollPosition($position, anchor: .top)
                .safeAreaInset(edge: .top, spacing: 0) { stickyBar(proxy) }
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }, action: { viewportH = $0 })
                // The moment a finger touches the feed it belongs to the user, and the landing
                // stops correcting. This is what replaces the old 250-ms `didLand` timer.
                .onScrollPhaseChange { _, phase in
                    if phase == .interacting { didLand = true }
                }
                .onPreferenceChange(DayHeaderKey.self) { values in
                    offsets.values = values
                    if !didLand, let y = values[0] { offsets.topLine = y }
                    // The current day is the last header at or above the line a pinned header comes
                    // to rest on.
                    let line = offsets.topLine + 0.5
                    let stuck = values.filter { $0.value <= line }.max(by: { $0.value < $1.value })?.key
                    if stuck != pinnedDay { pinnedDay = stuck }
                    guard didLand else { land(proxy); return }
                    let current = stuck ?? values.min(by: { $0.value < $1.value })?.key ?? 0
                    if current != visibleDay {
                        visibleDay = current
                        selectedDay = current
                        // The strip is the screen's orientation device; it may not keep pointing at
                        // a week the reader has left.
                        let page = weekIndex(of: current)
                        if page != weekPage {
                            withAnimation(ThemeMotion.pick(ThemeMotion.uiGentle, reduceMotion: reduceMotion)) {
                                weekPage = page
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            .background(ThemeColor.canvas.ignoresSafeArea())
            // The bottom edge is ours; the TOP edge belongs to the navigation bar. `scrollEdgeChrome`
            // hides the system scroll-edge effect `for: .all`, and that is what stopped the bar from
            // painting at all — rows and day headers scrolled straight through the clock and the
            // Dynamic Island with a real bar installed, because nothing was left to own the edge.
            // So: our ramp at the bottom, the system's at the top, one hidden effect each.
            .scrollEdgeChromeBody(top: false)
            .scrollEdgeEffectHidden(true, for: .bottom)
            // `.hard`, not the default soft blur: this screen's top edge has posters and 17-pt
            // titles passing under it, and a soft edge leaves them legible on the clock.
            .scrollEdgeEffectStyle(.hard, for: .top)
            .previouslyRefreshable { await appModel.reload() }
            .task { await ScheduleReminders.shared.refresh() }
            // The landing is a state, not a timer. `position` is already `day-0` before the first
            // layout; everything below only *corrects* it, and it keeps the right to correct until
            // today's header actually measures at the top — the old `asyncAfter(0.05)` silently
            // no-opped on a cold launch and then declared itself landed 250 ms later.
            .onChange(of: feedKey, initial: true) { _, _ in land(proxy) }
            .navigationTitle("Schedule")
            // Inline rather than large: a large title collapses on the first scroll, which changes
            // the top safe area by ~50 pt mid-flight — under a pinned week strip that reflow landed
            // the feed a row past today every time. It is still a real navigation bar with a real
            // title and real toolbar items, which is what "the screen has nothing to own the edge"
            // was asking for.
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    // Scoped to the one control that appears and disappears. This animation used to
                    // sit on the whole ScrollView, so any structural identity change that happened
                    // to coincide with it animated too.
                    Group {
                        if selectedDay != 0 {
                            Button("Today") { goToToday(proxy) }
                                .accessibilityHint("Scrolls to today")
                                .transition(.opacity)
                        }
                    }
                    .animation(ThemeMotion.pick(ThemeMotion.uiGentle, reduceMotion: reduceMotion), value: selectedDay != 0)
                }
                ToolbarItem(placement: .topBarTrailing) { filterMenu }
            }
            .onChange(of: typeFilter) { _, _ in FeedbackCoordinator.fire(.selection) }
            .onChange(of: unwatchedOnly) { _, _ in FeedbackCoordinator.fire(.selection) }
            .confirmationDialog(prompt?.title ?? "", isPresented: Binding(get: { prompt != nil }, set: { if !$0 { prompt = nil } }),
                                titleVisibility: .visible, presenting: prompt) { p in
                Button(p.confirm) { p.perform() }
                Button(Copy.Confirm.cancel, role: .cancel) {}
            } message: { p in
                Text(p.message)
            }
        }
    }

    private var filterValue: String {
        var bits: [String] = []
        if typeFilter != .all { bits.append(typeFilter == .anime ? "Anime" : "TV") }
        if unwatchedOnly { bits.append("unwatched only") }
        return bits.isEmpty ? "Off" : bits.joined(separator: ", ")
    }

    // MARK: - Scrolling

    /// Put today at the top of the content and HOLD it there until the user takes the wheel.
    ///
    /// The shipped build did this with `asyncAfter(0.05) { proxy.scrollTo }`: if the lazy stack had
    /// not materialised the anchor within 50 ms — cold launch, large library, slow device — the
    /// scroll silently no-opped, `didLand` went true 250 ms later and nothing ever corrected it.
    /// That is the failure that produced "it opens on the wrong week".
    ///
    /// Re-issuing the same scroll is idempotent (it moves nothing once today is already at the
    /// top), and `onPreferenceChange` only fires when a header actually moves — so this quiesces by
    /// itself the moment the layout settles, and wakes up again if a poster decoding above today
    /// pushes it down. The cap only bounds a today that physically cannot reach the top.
    private func land(_ proxy: ScrollViewProxy) {
        guard !didLand, !landGaveUp, !appModel.library.isEmpty else { return }
        guard visibleDays.contains(where: { $0.id == 0 }) else { return }
        landAttempts += 1
        guard landAttempts <= 60 else { landGaveUp = true; return }
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) { proxy.scrollTo(0, anchor: .top) }
    }

    /// Distance-aware, and never a spring. `uiSnappy` is defined for "fast LOCAL layout changes";
    /// pointing a 0.34 s spring at a lazy scroll view an arbitrary distance away either lands with
    /// a tail or fights rows materialising mid-flight. So: measure the journey from the header
    /// offsets already collected, and animate only when the animation can describe it.
    private func scroll(to dayId: Int, proxy: ScrollViewProxy) {
        let delta = offsets.values[dayId].map { $0 - offsets.topLine }
        if let delta, abs(delta) <= viewportH {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.28)) {
                proxy.scrollTo(dayId, anchor: .top)
            }
        } else {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { proxy.scrollTo(dayId, anchor: .top) }
        }
    }

    private func goToToday(_ proxy: ScrollViewProxy) {
        FeedbackCoordinator.fire(.selection)
        didLand = true
        selectedDay = 0
        withAnimation(ThemeMotion.pick(ThemeMotion.uiGentle, reduceMotion: reduceMotion)) { weekPage = 0 }
        scroll(to: 0, proxy: proxy)
    }

    // MARK: - Sticky bar

    /// The bar is CHROME, so it is glass over the art wash rather than an opaque black plate with a
    /// rule under it — and it runs UP through the navigation bar and the status bar as one surface.
    /// Terminating it at the safe-area line is what drew a hard horizontal seam across the full
    /// width of the screen, which is exactly what a hand-rolled scroll edge looks like.
    @ViewBuilder
    private var barGround: some View {
        ZStack {
            if reduceTransparency {
                ThemeColor.canvas
            } else {
                Rectangle().fill(.ultraThinMaterial)
                ThemeColor.canvas.opacity(0.34)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The bar's own hand-off to the content: the same material, ramped out over 22 pt, so a day
    /// header dissolves into the chrome instead of being guillotined by it.
    @ViewBuilder
    private var barFade: some View {
        let ramp = LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
        ZStack {
            if !reduceTransparency { Rectangle().fill(.ultraThinMaterial) }
            ThemeColor.canvas.opacity(reduceTransparency ? 1 : 0.34)
        }
        .mask(ramp)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func stickyBar(_ proxy: ScrollViewProxy) -> some View {
        let page = weekPage ?? 0
        let week = weekCells(page: page)
        return VStack(alignment: .leading, spacing: 0) {
            weekLabelRow(week)
            weekStrip(proxy)
        }
        .padding(.bottom, ThemeSpace.x2)
        // The strip continues the navigation bar's surface — same material, butted against it —
        // and its only edge is the bottom one, which RAMPS. The shipped build terminated its ground
        // in a hard horizontal seam straight across the full width at the safe-area line, which is
        // exactly what a hand-rolled scroll edge looks like.
        .background { barGround }
        // The hand-off ramp exists so scrolling CONTENT dissolves into the bar. A pinned day header
        // is chrome and brings its own ground, so veiling it with a third material only greyed the
        // one line the screen most wants legible — TODAY and its NOW time.
        .overlay(alignment: .bottom) {
            if pinnedDay == nil { barFade.frame(height: 22).offset(y: 22) }
        }
    }

    /// "‹ 17 AUG – 23 AUG ›  ————  3 EPISODES". The label names the week the count counts: it used
    /// to read "AUGUST 2026 · 3 EPISODES", so the number appeared to describe the month while it
    /// actually described the seven days below it.
    @ViewBuilder
    private func weekLabelRow(_ week: [WeekCell]) -> some View {
        let summary = weekSummary(week)
        let range = weekRangeLabel(week)
        let stepper = HStack(spacing: ThemeSpace.x1) {
            weekStep(-1)
            SectionLabel(text: range)
                .accessibilityAddTraits(.isHeader)
                .contentTransition(.opacity)
            weekStep(1)
        }
        Group {
            if isAX {
                // Never dropped, always reflowed: "3 EPISODES" used to vanish outright at
                // accessibility sizes, and a fact that can vanish was not needed at default size.
                VStack(alignment: .leading, spacing: ThemeSpace.x1) {
                    stepper
                    if let summary {
                        Text(summary).type(ThemeType.sectionLabel).textCase(.uppercase)
                            .foregroundStyle(ThemeColor.textTertiary)
                            .accessibilityHidden(true)
                    }
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: ThemeSpace.x2) {
                    stepper
                    Spacer(minLength: ThemeSpace.x2)
                    if let summary {
                        Text(summary).type(ThemeType.sectionLabel).textCase(.uppercase)
                            .foregroundStyle(ThemeColor.textTertiary)
                            .lineLimit(1)
                            .contentTransition(.opacity)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        // One text edge with everything the bar introduces: day headers, rows and the rail's
        // content column all start at gutter + 22.
        .padding(.leading, ThemeMetrics.gutter + Rail.gutter)
        .padding(.trailing, ThemeMetrics.gutter)
        .padding(.top, ThemeSpace.x1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(summary.map { "\(range), \($0)" } ?? range)
    }

    private func weekStep(_ delta: Int) -> some View {
        Button {
            FeedbackCoordinator.fire(.selection)
            withAnimation(ThemeMotion.pick(ThemeMotion.uiGentle, reduceMotion: reduceMotion)) {
                weekPage = (weekPage ?? 0) + delta
            }
        } label: {
            Image(systemName: delta < 0 ? "chevron.compact.left" : "chevron.compact.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(ThemeColor.textTertiary)
                .frame(width: 28, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(WeekCellPressStyle())
        .accessibilityLabel(delta < 0 ? "Previous week" : "Next week")
    }

    /// The strip pages week by week. The shipped build drew one week with a static month label and
    /// no forward/back anything — with the only two events four and six days out, the user could
    /// not see next week at all.
    private func weekStrip(_ proxy: ScrollViewProxy) -> some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(WeekPage.range, id: \.self) { p in
                    HStack(spacing: 0) {
                        ForEach(weekCells(page: p)) { cell in
                            weekCell(cell, proxy: proxy).frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal, ThemeSpace.x2)
                    .containerRelativeFrame(.horizontal)
                    .id(p)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $weekPage)
        .scrollIndicators(.hidden)
        .frame(height: stripHeight)
        .padding(.top, ThemeSpace.x0_5)
        .accessibilityLabel("Week")
    }

    private var filterMenu: some View {
        Menu {
            // No symbols on the choices. A UIKit menu tints content with the app accent, so three
            // amber glyphs appeared down the left of a three-item list — decoration the checkmark
            // already covers, in the one colour this screen spends carefully.
            Section("Source") {
                Picker("Source", selection: $typeFilter) {
                    Text("All").tag(MediaFilter.all)
                    Text("Anime").tag(MediaFilter.anime)
                    Text("TV").tag(MediaFilter.tv)
                }
                .pickerStyle(.inline)
            }
            // No header on the second group: a 17-pt grey `Text` above a single toggle rendered as
            // a disabled menu item. The divider already separates the two decisions.
            Toggle("Unwatched only", isOn: $unwatchedOnly)
        } label: {
            Image(systemName: filterActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease")
        }
        .tint(filterActive ? ThemeColor.accent : ThemeColor.textPrimary)
        .accessibilityLabel("Filter")
        .accessibilityValue(filterValue)
    }

    // MARK: - Week strip

    enum WeekPage {
        /// Half a year either way — more than the horizon the API ever loads, and lazy.
        static let range = Array(-26...26)
    }

    struct WeekCell: Identifiable {
        let offset: Int
        let weekday: String
        let number: String
        let date: Date
        let count: Int
        let isToday: Bool
        let isNext: Bool
        var hasContent: Bool { count > 0 }
        var id: Int { offset }
    }

    /// Noon on today, so day arithmetic never lands on a DST seam.
    private var todayNoon: Int64 {
        let p = Formatting.localParts(now)
        return now - (Int64(p.hour) * Formatting.H + Int64(p.minute) * Formatting.minuteMs) + 12 * Formatting.H
    }

    private var mondayOfToday: Int { -Formatting.localMondayCol(now) }

    private func weekIndex(of day: Int) -> Int {
        Int((Double(day - mondayOfToday) / 7).rounded(.down))
    }

    /// The Mon–Sun week `page` weeks from the week containing today.
    private func weekCells(page: Int) -> [WeekCell] {
        let monday = mondayOfToday + page * 7
        let counts = Dictionary(days.map { ($0.id, $0.count) }, uniquingKeysWith: { a, _ in a })
        let next = nextEventDay?.id
        return (0..<7).map { i in
            let offset = monday + i
            let ts = todayNoon + Int64(offset) * Formatting.D
            let parts = Formatting.localParts(ts)
            return WeekCell(offset: offset,
                            weekday: String(Formatting.weekdayNameMonFirst(i).prefix(1)),
                            number: String(parts.d),
                            date: Date(timeIntervalSince1970: Double(ts) / 1000),
                            count: counts[offset] ?? 0,
                            isToday: offset == 0,
                            isNext: offset == next)
        }
    }

    private func weekRangeLabel(_ week: [WeekCell]) -> String {
        guard let lo = week.first, let hi = week.last else { return "" }
        return TemporalCopy.dateRange(Int64(lo.date.timeIntervalSince1970 * 1000),
                                      Int64(hi.date.timeIntervalSince1970 * 1000), now: now)
    }

    /// The count of the week the label names — nothing when the week is empty, because "0 EPISODES"
    /// beside a date range is a fact nobody asked for.
    private func weekSummary(_ week: [WeekCell]) -> String? {
        let total = week.reduce(0) { $0 + $1.count }
        guard total > 0 else { return nil }
        return Copy.episodes(total)
    }

    private func weekCell(_ cell: WeekCell, proxy: ScrollViewProxy) -> some View {
        let selected = cell.offset == selectedDay && !surfaceEmpty
        let enabled = cell.hasContent || cell.isToday
        // ONE encoding of past-vs-future: the whole cell recedes as a group. The shipped build said
        // "past" with dot colour and "has content" with numeral weight, so 17/18 (past, empty) and
        // 20 (future, empty) looked identical and a 4-pt hue difference carried the screen's
        // primary scanning job.
        let past = cell.offset < 0
        // Amber is the loudest thing in the app; a date is not allowed to be it. The selection is a
        // tinted ground with an accent edge, and solid accent is reserved for the NOW node.
        let numberColor: Color = selected ? ThemeColor.accent
            : (cell.isToday ? ThemeColor.accent : ThemeColor.textPrimary)
        return Button {
            FeedbackCoordinator.fire(.selection)
            didLand = true
            selectedDay = cell.offset
            withAnimation(ThemeMotion.pick(ThemeMotion.uiGentle, reduceMotion: reduceMotion)) {
                weekPage = weekIndex(of: cell.offset)
            }
            scroll(to: cell.offset, proxy: proxy)
        } label: {
            VStack(spacing: 4) {
                Text(cell.weekday).type(ThemeType.caption)
                    .foregroundStyle(cell.isToday ? ThemeColor.accent : ThemeColor.textTertiary)
                Text(cell.number).type(ThemeType.time)
                    .foregroundStyle(numberColor)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    // Padding first, then the 34-pt minimum: a fixed box alone clipped the fill
                    // hard against the digits once Dynamic Type grew them.
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .frame(minWidth: 34, minHeight: 34)
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: ThemeRadius.compactControl, style: .continuous)
                                .fill(ThemeColor.accent.opacity(0.18))
                                .overlay(RoundedRectangle(cornerRadius: ThemeRadius.compactControl, style: .continuous)
                                    .strokeBorder(ThemeColor.accent, lineWidth: 1.5))
                        }
                    }
                // The dot now carries ONE fact — "something airs here" — at a size a low-vision
                // user can resolve, and it distinguishes the next airing day by SHAPE, not hue.
                dayDot(cell)
            }
            .frame(minWidth: 44, minHeight: 44)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            // Past recedes as a group — but never the SELECTED cell: dimming the one cell the user
            // just chose turned its accent edge into a brown smudge.
            .opacity(past && !selected ? 0.55 : 1)
            .contentShape(Rectangle())
            .animation(ThemeMotion.pick(ThemeMotion.uiMicro, reduceMotion: reduceMotion), value: selected)
        }
        .buttonStyle(WeekCellPressStyle())
        .disabled(!enabled)
        .accessibilityLabel(cell.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
        // Built as a list, not a nested ternary: a day that HAD episodes used to get an empty value
        // and go silent, while an empty day announced itself — the strip's entire purpose inverted.
        .accessibilityValue([selected ? "Selected" : nil,
                             cell.isToday ? "Today" : nil,
                             cell.hasContent ? Copy.episodes(cell.count) : "No episodes"]
            .compactMap { $0 }.joined(separator: ", "))
    }

    @ViewBuilder
    private func dayDot(_ cell: WeekCell) -> some View {
        let dotColor = surfaceEmpty ? ThemeColor.textTertiary : ThemeColor.accent
        Group {
            if cell.isNext {
                Circle().fill(dotColor)
            } else if cell.hasContent {
                Circle().strokeBorder(ThemeColor.textSecondary, lineWidth: 1.5)
            } else {
                Color.clear
            }
        }
        .frame(width: 6, height: 6)
        .accessibilityHidden(true)
    }

    // MARK: - Content (state matrix)

    /// A whole-screen state sits in the MIDDLE of the content area, not pinned under the week strip
    /// with 1 100 pt of canvas beneath it.
    @ViewBuilder
    private func centred<V: View>(@ViewBuilder _ state: () -> V) -> some View {
        state()
            .padding(.horizontal, ThemeMetrics.gutter)
            .frame(maxWidth: .infinity)
            .padding(.bottom, ThemeMetrics.tabBarClearance)
            .containerRelativeFrame(.vertical, alignment: .center)
    }

    @ViewBuilder
    private func content() -> some View {
        if appModel.loading && appModel.library.isEmpty {
            feedSkeleton
        } else if appModel.loadError && appModel.libraryEmpty {
            centred {
                // `primary:` explicitly. Written as a trailing closure this bound to `secondary` —
                // `serverNoCache` has no secondary label, so Schedule's whole-screen server error
                // shipped with no Try again at all and the only recovery was to change tabs.
                EmptyState(SyncCenter.shared.isOnline ? .serverNoCache : .offlineNoData,
                           prominence: .major,
                           primary: { Task { await appModel.reload() } })
            }
        } else if appModel.libraryEmpty {
            // Schedule's own empty sentence — the shipped card said "Your library is empty / Add
            // your first show and Today builds itself" on a screen that is neither.
            centred { EmptyState(.emptySchedule, prominence: .major, primary: onAddShow) }
        } else {
            if appModel.sectionFailed {
                InlineNotice(Copy.Notice.schedule) { Task { await appModel.reload() } }
                    .padding(.horizontal, ThemeMetrics.gutter).padding(.top, ThemeMetrics.labelGap)
            } else if let since = appModel.staleSince(.exactAiring) {
                StaleStrip(since: since, now: now)
                    .padding(.horizontal, ThemeMetrics.gutter).padding(.top, ThemeMetrics.labelGap)
            }
            let all = unfilteredDays
            let shown = days
            if all.allSatisfy(\.isEmpty) {
                centred { EmptyState(.nothingScheduled, prominence: .major) }
            } else if shown.allSatisfy(\.isEmpty) && filterActive {
                centred {
                    EmptyState(.noFilterMatches, prominence: .major, primary: {
                        withAnimation(ThemeMotion.pick(ThemeMotion.uiSnappy, reduceMotion: reduceMotion)) { typeFilter = .all; unwatchedOnly = false }
                    })
                }
            } else {
                let visible = visibleDays
                ForEach(Array(visible.enumerated()), id: \.element.id) { i, day in
                    dayView(day, isFirst: i == 0)
                }
                feedTail
            }
        }
    }

    /// The feed's loading state, composed from the shared skeleton atoms at THIS screen's geometry
    /// — same parts, right proportions, and the rail is already there when the data lands.
    private var feedSkeleton: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<3, id: \.self) { _ in
                SkeletonLine(width: 116, height: 11)
                    .padding(.leading, Rail.gutter)
                    .padding(.top, ThemeMetrics.sectionGap)
                    .padding(.bottom, ThemeSpace.x1)
                SkeletonRow(poster: CGSize(width: Rail.posterW, height: Rail.posterH),
                            lines: [212, 96], posterRadius: ThemeRadius.poster,
                            height: ThemeMetrics.rowMedia)
                    .padding(.leading, Rail.gutter)
                    .padding(.vertical, ThemeSpace.x2)
            }
        }
        .padding(.horizontal, ThemeMetrics.gutter)
        .background(alignment: .topLeading) { railLine(head: true) }
        .padding(.bottom, ThemeMetrics.tabBarClearance)
        .accessibilityHidden(true)
    }

    // MARK: - Day

    /// One day block: a pinned header and its rows. The rail is drawn as the background of BOTH so
    /// the line stays continuous while the header sticks — the header carries its own 1-pt segment
    /// with it, over the same glass the week strip uses.
    @ViewBuilder
    private func dayView(_ day: Day, isFirst: Bool) -> some View {
        let showKindLabel = !day.dateOnly.isEmpty && !day.timed.isEmpty
        // A past day whose every episode is watched is DONE, so its label recedes with its rows.
        let settled = day.id < 0 && !day.isEmpty
            && day.dateOnly.allSatisfy { $0.watched || committed.contains($0.id) }
            && day.timed.allSatisfy { $0.watched || committed.contains($0.id) }
        Section {
            VStack(alignment: .leading, spacing: 0) {
                if day.isToday && day.isEmpty {
                    // Today, empty: ONE line under one band. The shipped build stacked a day
                    // header, a full-width accent NOW rule and a grey sentence — the loudest
                    // horizontal element on the screen marking nothing, three deep, on the screen
                    // a user opens daily.
                    Text(nothingTodayLine)
                        .type(ThemeType.rowMeta).foregroundStyle(ThemeColor.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, Rail.gutter)
                        .padding(.top, ThemeSpace.x1)
                        .padding(.bottom, ThemeSpace.x3)
                } else {
                    if !day.dateOnly.isEmpty {
                        if showKindLabel { kindLabel("Date only") }
                        ForEach(day.dateOnly) { e in row(e) }
                    }
                    if !day.timed.isEmpty {
                        if showKindLabel { kindLabel("Timed") }
                        let nowIndex = day.isToday ? (day.timed.firstIndex { $0.at > nowMinute } ?? day.timed.count) : -1
                        ForEach(Array(day.timed.enumerated()), id: \.element.id) { i, e in
                            if i == nowIndex { nowMarker }
                            row(e)
                        }
                        if day.isToday && nowIndex == day.timed.count { nowMarker }
                    }
                    if day.isToday && day.timed.isEmpty && !day.dateOnly.isEmpty { nowMarker }
                }
            }
            .padding(.horizontal, ThemeMetrics.gutter)
            .background(alignment: .topLeading) { railLine(head: false) }
        } header: {
            dayHeader(day)
                .opacity(settled ? 0.62 : 1)
                .padding(.horizontal, ThemeMetrics.gutter)
                .background(alignment: .topLeading) { railLine(head: isFirst) }
                // Chrome only while it IS chrome. A header that always carried glass would be six
                // glass bands down one screen; a pinned header with no ground lets rows read
                // through it.
                .background {
                    if pinnedDay == day.id {
                        barGround
                            .overlay(alignment: .bottom) { barFade.frame(height: 12).offset(y: 12) }
                    }
                }
        }
    }

    /// The 1-pt timeline. On the FIRST day it fades up out of the header band over 24 pt — a hard
    /// 1-pt start under a glass bar is the tell of a hand-rolled rail.
    private func railLine(head: Bool) -> some View {
        GeometryReader { geo in
            let h = geo.size.height
            let fade = head ? min(0.6, 24 / max(h, 1)) : 0
            Rectangle()
                .fill(ThemeColor.separator)
                .frame(width: 1, height: h)
                .mask(LinearGradient(stops: [.init(color: .clear, location: 0),
                                             .init(color: .black, location: fade)],
                                     startPoint: .top, endPoint: .bottom))
                .offset(x: ThemeMetrics.gutter + Rail.x - 0.5)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The end of the horizon, and it NAMES the horizon. "Nothing scheduled" alone read as a second
    /// failure two screens below the first one, and it had no scope: nothing scheduled *when*?
    private var horizonLine: String {
        guard let last = appModel.scheduleDays.last else { return Copy.Empty.nothingScheduled.title }
        let ts = todayNoon + Int64(last.id) * Formatting.D
        return "No further episodes through \(Formatting.fmtMonthDay(ts))"
    }

    /// The rail runs on past the last event and *fades* into the closing sentence, terminating in a
    /// node rather than the stray horizontal tick that read as a drawing bug.
    private var feedTail: some View {
        let run = ThemeMetrics.sectionGap
        return Text(horizonLine)
            .type(ThemeType.rowMeta)
            .foregroundStyle(ThemeColor.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
            .padding(.leading, Rail.gutter)
            .padding(.top, run)
            .padding(.horizontal, ThemeMetrics.gutter)
            .overlay(alignment: .topLeading) {
                GeometryReader { geo in
                    let capY = run + (geo.size.height - run) / 2
                    ZStack(alignment: .topLeading) {
                        Rectangle().fill(ThemeColor.separator)
                            .frame(width: 1, height: capY)
                            .mask(LinearGradient(stops: [.init(color: .black, location: 0),
                                                         .init(color: .black, location: max(0, 1 - 10 / max(capY, 1))),
                                                         .init(color: .clear, location: 1)],
                                                 startPoint: .top, endPoint: .bottom))
                        Circle().strokeBorder(ThemeColor.separatorQuiet, lineWidth: 1.5)
                            .frame(width: node, height: node)
                            .offset(x: -node / 2 + 0.5, y: capY - node / 2)
                    }
                    .offset(x: ThemeMetrics.gutter + Rail.x - 0.5)
                }
                .allowsHitTesting(false)
            }
            .padding(.bottom, ThemeMetrics.tabBarClearance)
            .accessibilityElement(children: .combine)
    }

    /// "Nothing scheduled · Next up Sun 23 Aug" — the header supplies "today", so the sentence does
    /// not repeat it, and it names the next date rather than leaving the day a dead end.
    private var nothingTodayLine: String {
        let base = hasAiredEarlierToday() ? "Nothing else scheduled" : "Nothing scheduled"
        guard let next = appModel.scheduleDays.first(where: { $0.id > 0 && !day(from: $0).isEmpty }) else {
            return base
        }
        return "\(base) · Next up \(String(next.label.prefix(3))) \(next.dateLabel)"
    }

    private func dayHeader(_ day: Day) -> some View {
        let todayEmpty = day.isToday && day.isEmpty
        return HStack(alignment: .firstTextBaseline, spacing: ThemeMetrics.labelGap) {
            Text(day.header).type(ThemeType.dayLabel).textCase(.uppercase)
                .foregroundStyle(day.isToday ? ThemeColor.accent : ThemeColor.textTertiary)
                .lineLimit(isAX ? 2 : 1)
                .fixedSize(horizontal: false, vertical: true)
            if !isAX {
                // Neutral even on Today, and it fades out to the right rather than ruling edge to
                // edge — six full-width hairlines down one screen is what makes a feed read as a
                // table. It always connects two objects now: the trailing slot is never empty.
                Rectangle().fill(LinearGradient(colors: [ThemeColor.separatorQuiet, ThemeColor.separatorQuiet.opacity(0)],
                                                startPoint: .leading, endPoint: .trailing))
                    .frame(height: 1)
            } else {
                Spacer(minLength: ThemeSpace.x2)
            }
            if todayEmpty {
                // The NOW marker, folded INTO the header rather than given a rule and a row of its
                // own above an empty day.
                HStack(spacing: 5) {
                    Text("Now").type(ThemeType.dayLabel).textCase(.uppercase)
                    Text(Formatting.fmtTime(nowMinute)).type(ThemeType.time)
                }
                .foregroundStyle(ThemeColor.accent)
                .lineLimit(1)
                .animation(reduceMotion ? nil : ThemeMotion.uiGentle, value: nowMinute)
            } else if day.count > 0 {
                Text(Copy.episodes(day.count)).type(ThemeType.sectionLabel).textCase(.uppercase)
                    .foregroundStyle(ThemeColor.textTertiary)
                    .lineLimit(1)
            } else {
                Text("No episodes").type(ThemeType.sectionLabel).textCase(.uppercase)
                    .foregroundStyle(ThemeColor.textDisabled)
                    .lineLimit(1)
            }
        }
        .padding(.leading, Rail.gutter)
        .padding(.top, ThemeMetrics.sectionGap)
        .padding(.bottom, ThemeSpace.x1)
        .overlay(alignment: .leading) {
            if todayEmpty {
                nowNode.offset(x: Rail.x - node / 2, y: headerNodeDrop)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(todayEmpty
                            ? "\(day.header), no episodes, now \(Formatting.fmtTime(nowMinute))"
                            : (day.count > 0 ? "\(day.header), \(Copy.episodes(day.count))" : "\(day.header), no episodes"))
        .accessibilityAddTraits(.isHeader)
        .id(day.id)
        .background(GeometryReader { geo in
            Color.clear.preference(key: DayHeaderKey.self, value: [day.id: geo.frame(in: .named("schedule.feed")).minY])
        })
    }

    /// The overlay is centred on the header's whole box, which includes a 30-pt lead-in; the node
    /// has to come back down onto the label's own line.
    private var headerNodeDrop: CGFloat { (ThemeMetrics.sectionGap - ThemeSpace.x1) / 2 }

    /// "Date only" / "Timed" — printed ONLY when a day genuinely carries both kinds.
    private func kindLabel(_ text: String) -> some View {
        SectionLabel(text: text)
            .padding(.leading, Rail.gutter)
            .padding(.top, ThemeMetrics.labelGap)
            .padding(.bottom, ThemeSpace.x0_5)
            .accessibilityAddTraits(.isHeader)
    }

    private func hasAiredEarlierToday() -> Bool {
        guard let raw = appModel.scheduleDays.first(where: \.isToday) else { return false }
        return !raw.airedToday.isEmpty
    }

    // MARK: - NOW

    private var nowNode: some View {
        Circle().fill(ThemeColor.accent)
            .frame(width: node, height: node)
            .background { Circle().fill(ThemeColor.accentSoft).frame(width: node + 10, height: node + 10) }
            .accessibilityHidden(true)
    }

    /// `NOW ————————— 5:54 AM`, on the rail, in the one place amber is unambiguously right.
    /// It is the only thing on this screen that moves on its own, once a minute.
    private var nowMarker: some View {
        HStack(spacing: ThemeMetrics.labelGap) {
            Text("Now").type(ThemeType.dayLabel).textCase(.uppercase).foregroundStyle(ThemeColor.accent)
            if !isAX {
                Rectangle().fill(LinearGradient(colors: [ThemeColor.accent.opacity(0.60), ThemeColor.accent.opacity(0.28)],
                                                startPoint: .leading, endPoint: .trailing))
                    .frame(height: 1)
            } else {
                Spacer(minLength: ThemeSpace.x2)
            }
            Text(Formatting.fmtTime(nowMinute)).type(ThemeType.time).foregroundStyle(ThemeColor.accent)
        }
        .padding(.leading, Rail.gutter)
        .padding(.vertical, ThemeMetrics.labelGap)
        .overlay(alignment: .leading) { nowNode.offset(x: Rail.x - node / 2) }
        .animation(reduceMotion ? nil : ThemeMotion.uiGentle, value: nowMinute)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Now, \(Formatting.fmtTime(nowMinute))")
    }

    // MARK: - Row

    private func row(_ e: Event) -> some View {
        let f = e.franchise
        let isCommitted = committed.contains(e.id)
        let watched = e.watched || isCommitted
        // The control stays put through the commit so the check can DRAW in place; only a row that
        // was already watched when the screen loaded starts as a passive tick.
        let showsAction = e.aired && !e.watched && appModel.isInLibrary(f.id)
        let batch = e.aired && e.episode > e.part.progress + 1
        let time = e.dateOnly ? nil : Formatting.fmtTime(e.at, anchor: f.timeAnchor)
        // At accessibility sizes the air time LEADS the row — the schedule's organising fact — so
        // it never detaches into a stray third line 90 pt under the episode number.
        let leadTime = isAX ? time : nil
        let meta = metaLine(e, inlineTime: (showsAction && !isAX) ? time : nil)
        let spokenTime = time.map { ", \($0)" } ?? ""
        let hasReminder = !e.aired && ScheduleReminders.shared.has(mediaId: e.part.mediaId, episode: e.episode)
        let posterW = isAX ? Rail.posterAXW : Rail.posterW
        let posterH = isAX ? Rail.posterAXH : Rail.posterH
        let layout = isAX ? AnyLayout(VStackLayout(alignment: .leading, spacing: ThemeSpace.x3))
                          : AnyLayout(HStackLayout(alignment: .center, spacing: ThemeSpace.x3))
        return layout {
            Button { onOpenDetail(f.id, "sched/\(f.id)", EpisodeFocus(mediaId: e.part.mediaId, episode: e.episode)) } label: {
                // `.center`, always: at AX the poster used to strand at the top-left of a 230-pt row
                // with empty canvas beside and beneath it, and stopped being the row's anchor.
                HStack(alignment: .center, spacing: ThemeMetrics.artGap) {
                    PosterSlot(url: f.cover, width: posterW, height: posterH,
                               radius: ThemeRadius.poster, shadow: ShadowToken.none)
                    VStack(alignment: .leading, spacing: ThemeMetrics.titleGap) {
                        if let leadTime {
                            Text(leadTime).type(ThemeType.time).foregroundStyle(ThemeColor.accent)
                        }
                        Text(f.title).type(ThemeType.rowTitle).foregroundStyle(ThemeColor.textPrimary)
                            .lineLimit(isAX ? nil : 2)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(meta).type(ThemeType.rowMeta).foregroundStyle(ThemeColor.textSecondary)
                            .lineLimit(isAX ? nil : 1)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPressStyle(radius: ThemeRadius.poster))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(f.title), \(meta)\(spokenTime)\(hasReminder ? ", reminder set" : "")")
            .accessibilityValue(watched ? Copy.Accessibility.complete : "")
            .accessibilityHint("Opens the show")

            trailing(e, showsAction: showsAction, marked: isCommitted, watched: watched,
                     batch: batch, time: isAX ? nil : time, hasReminder: hasReminder)
                .padding(.leading, isAX ? posterW + ThemeMetrics.artGap : 0)
                .frame(maxWidth: isAX ? .infinity : nil, alignment: .leading)
        }
        .padding(.leading, Rail.gutter)
        .padding(.vertical, ThemeSpace.x2)
        .frame(minHeight: ThemeMetrics.rowMedia, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        // A handled row recedes as ONE opacity: element-by-element greys break the artwork's
        // colour relationship and read as five disabled controls rather than one settled row.
        .opacity(watched ? 0.48 : 1)
        .overlay(alignment: .leading) { railNode(watched: watched, aired: e.aired) }
        .animation(ThemeMotion.pick(ThemeMotion.uiMicro, reduceMotion: reduceMotion), value: isCommitted)
    }

    @ViewBuilder
    private func trailing(_ e: Event, showsAction: Bool, marked: Bool, watched: Bool, batch: Bool,
                          time: String?, hasReminder: Bool) -> some View {
        // Reduce Motion branched at BOTH sites: shortening the duration does not stop a 0.6 → 1
        // scale from playing, and Today's identical control is branched correctly.
        let markTransition: AnyTransition = reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.6))
        if showsAction {
            // The shared mark control, so the same gesture has the same shape on Schedule, the
            // episode list and Detail — and the check DRAWS on commit here too.
            MarkRing(marked: marked,
                     label: batch ? "Mark \(Copy.episodes(e.episode - e.part.progress)) of \(e.franchise.title) as watched"
                                  : "Mark \(Copy.episode(e.episode)) of \(e.franchise.title) as watched",
                     markedLabel: Copy.Progress.episodeWatched(e.episode)) {
                guard !marked else { return }
                mark(e, batch: batch)
            }
            .transition(markTransition)
        } else if e.aired {
            // Settled: the same two-line column the upcoming rows use, with the tick standing where
            // the time's state word stands. The row is already dimmed as a group.
            VStack(alignment: isAX ? .leading : .trailing, spacing: 1) {
                if watched { PassiveTick() }
                if let time {
                    Text(time).type(ThemeType.time).foregroundStyle(ThemeColor.textSecondary)
                }
            }
            .frame(minWidth: 44, alignment: isAX ? .leading : .trailing)
            .accessibilityHidden(true)
            .transition(markTransition)
        } else if let time {
            VStack(alignment: isAX ? .leading : .trailing, spacing: 1) {
                if hasReminder {
                    Image(systemName: "bell.fill").font(.system(size: 10))
                        .foregroundStyle(ThemeColor.textDisabled)
                        .accessibilityHidden(true)
                }
                Text(time).type(ThemeType.time).foregroundStyle(ThemeColor.textSecondary)
            }
            .accessibilityHidden(true)
        } else if hasReminder {
            Image(systemName: "bell.fill").font(.system(size: 12))
                .foregroundStyle(ThemeColor.textDisabled)
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
        }
    }

    /// The rail node, and it carries meaning rather than decoration. Three states, all legible at
    /// 8 pt with a 1.5-pt stroke that tracks Dynamic Type:
    ///   · **accent ring** — it has not happened yet. The shipped build gave every future episode a
    ///     hollow `textDisabled` ring, so a column of disabled-looking marks ran down a list of
    ///     things to look forward to;
    ///   · **`textSecondary` ring** — it aired and is waiting for you;
    ///   · **filled `textDisabled` + a knocked-out check** — done.
    /// Solid accent belongs to NOW alone.
    private func railNode(watched: Bool, aired: Bool) -> some View {
        Group {
            if watched {
                ZStack {
                    Circle().fill(ThemeColor.textDisabled)
                    Image(systemName: "checkmark")
                        .font(.system(size: node * 0.62, weight: .black))
                        .foregroundStyle(ThemeColor.canvas)
                }
            } else if aired {
                Circle().strokeBorder(ThemeColor.textSecondary, lineWidth: nodeStroke)
            } else {
                Circle().strokeBorder(ThemeColor.accent, lineWidth: nodeStroke)
            }
        }
        .frame(width: node, height: node)
        .offset(x: Rail.x - node / 2)
        .accessibilityHidden(true)
    }

    /// One meta line for both sources. It used to branch on `source == .tmdb`, so a multi-season
    /// anime printed a bare "Episode 20" here while its own detail screen said "Season 4 · Episode
    /// 19" — and an episode number alone is meaningless exactly when a show has seasons.
    /// `canonicalLabel` is empty for a single-part title and `watchContext` degrades to
    /// "Episode 9", so nothing regresses for shows that have only one part.
    private func metaLine(_ e: Event, inlineTime: String?) -> String {
        let label = e.part.canonicalLabel
        var s: String
        if !e.aired && e.part.nextAiringCount > 1 {
            s = label.isEmpty ? Copy.episodes(e.part.nextAiringCount) : "\(label) · \(Copy.episodes(e.part.nextAiringCount))"
        } else {
            s = Copy.watchContext(part: label, episode: e.episode)
        }
        if let inlineTime { s += " · \(inlineTime)" }
        return s
    }

    // MARK: - Mark as watched (the only write)

    private func mark(_ e: Event, batch: Bool) {
        let f = e.franchise, part = e.part
        if batch {
            let count = e.episode - part.progress
            prompt = .init(title: Copy.Confirm.batchMarkTitle(count),
                           message: Copy.Confirm.batchMarkMessage(from: part.progress, to: e.episode),
                           confirm: Copy.Confirm.batchMarkConfirm(count)) {
                let prev = part.progress
                appModel.setProgress(franchiseId: f.id, mediaId: part.mediaId, episodes: e.episode)
                commit(e) {
                    appModel.presentUndo(UndoState(mediaId: part.mediaId, franchiseId: f.id, prevProgress: prev, title: f.title, episode: e.episode, count: count))
                }
            }
            return
        }
        guard let undo = appModel.markNext(franchiseId: f.id, mediaId: part.mediaId) else { return }
        commit(e) { appModel.presentUndo(undo) }
    }

    /// The control fills and the check draws in place; the row settles into its dimmed state and
    /// never moves (a calendar keeps its history) unless "Unwatched only" is on, in which case it
    /// leaves after a 650 ms hold.
    private func commit(_ e: Event, then present: @escaping () -> Void) {
        _ = withAnimation(ThemeMotion.pick(ThemeMotion.uiMicro, reduceMotion: reduceMotion)) {
            committed.insert(e.id)
        } completion: {
            if unwatchedOnly {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(650))
                    _ = withAnimation(ThemeMotion.pick(ThemeMotion.uiSettle, reduceMotion: reduceMotion)) {
                        committed.remove(e.id)
                    } completion: { present() }
                }
            } else {
                present()
            }
        }
    }
}

/// The week strip's press feedback. `RowPressStyle` paints a 16-pt rounded wash across the whole
/// 44-pt column; a date cell wants nothing but its own compression — and the app's compression
/// floor is 0.985, not the 6 % this style used to take out of a 44-pt date.
private struct WeekCellPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.985 : 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(ThemeMotion.pick(ThemeMotion.uiPress, reduceMotion: reduceMotion),
                       value: configuration.isPressed)
    }
}

/// See the note on `offsets`: deliberately a reference type, so a scroll can record where every day
/// header is without invalidating the view sixty times a second.
@MainActor private final class DayOffsetBox {
    var values: [Int: CGFloat] = [:]
    /// The scroll view's own offset, so a target can be expressed as "where it is now, plus the
    /// error the day header reports" — arithmetic a pinned section header cannot confuse.
    /// Where a day header sits when it is at the top of the content. Calibrated from today's own
    /// header while the screen still owns the scroll, so nothing here has to assume which frame a
    /// named coordinate space is measured against.
    var topLine: CGFloat = 0
}

private struct DayHeaderKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] { [:] }
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}
