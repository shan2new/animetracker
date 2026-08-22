import SwiftUI

// Schedule (spec board 04). One chronological feed hung on a timeline rail: an ambient art wash
// under a glass header, a week strip, day headers with their episode count, ~100-pt event rows on
// a 22-pt rail gutter, and a NOW marker that crosses today and moves once a minute.
//
// What this pass fixed (the shipped build read as a settings table):
//   · content scrolled through the status bar — the bar is a real safe-area inset that owns the
//     top edge, art wash and all, and the bottom gets `scrollEdgeChrome`. As a *pinned header* it
//     also meant the app opened with today hidden behind it; an inset lands today where the user
//     is looking;
//   · the rail, the NOW marker and the ambient wash were gone — all three are back, and the rail
//     now carries meaning: filled = it happened, hollow = it has not, one amber node for NOW;
//   · "TIMED" was printed above every row: a day section supplies the item's context, so it is
//     printed only when a day genuinely carries both kinds;
//   · 36×54 art at 68 pt with a hairline under every row → 56×84 art at `rowMedia`, no hairlines,
//     the rail carries the rhythm instead;
//   · watched rows recede as a group (one opacity) instead of a grey disc in the control column,
//     and the trailing column keeps one grammar throughout: a state over a time;
//   · amber is spent on TODAY, NOW and the one mark control — not on a date you scrolled past.
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
    /// The feed has landed on today; only then does scroll tracking drive the strip.
    @State private var didLand = false
    @State private var typeFilter: MediaFilter = .all
    @State private var unwatchedOnly = false
    @State private var committed: Set<String> = []
    @State private var prompt: FranchiseDetailView.WritePrompt?

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
        static let node = HistoryRailMetrics.node        // 8 pt
        static let posterW: CGFloat = 56
        static let posterH: CGFloat = 84
    }

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

    /// The artwork the ambient wash is derived from: the next thing to air, else the most recent
    /// thing that did. One already-cached image, drawn once, never animated.
    private var ambientCover: String? {
        let all = unfilteredDays
        if let upcoming = all.first(where: { $0.id >= 0 && !$0.isEmpty }) {
            return (upcoming.timed.first ?? upcoming.dateOnly.first)?.franchise.cover
        }
        return all.last(where: { !$0.isEmpty }).flatMap { ($0.timed.last ?? $0.dateOnly.last)?.franchise.cover }
    }

    // MARK: - Body

    var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .top) {
                // The atmosphere the original had and the rebuild dropped. It sits behind the
                // header too, so the glass bar picks up its warmth instead of being a black slab.
                ArtBackdrop(url: ambientCover, height: 620, intensity: 0.78)
                    .ignoresSafeArea(edges: .top)

                // The bar is a real safe-area inset, not a pinned section header. As a pinned header
                // it lived INSIDE the scroll content, so `scrollTo("day-0", anchor: .top)` aligned
                // today with the top of the viewport — which is *behind* the bar. The app opened
                // with its own anchor day, its NOW marker and half a row hidden under the week
                // strip. An inset makes the content area start below the bar, so landing on today
                // puts today at the top of the content, where the user is looking.
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        content(proxy)
                    }
                }
                .coordinateSpace(name: "schedule.feed")
                .safeAreaInset(edge: .top, spacing: 0) { stickyBar(proxy) }
                .onPreferenceChange(DayHeaderKey.self) { offsets in
                    guard didLand else { return }
                    // The current day is the last header at or above the line where a freshly
                    // scrolled-to header comes to rest. Now that the bar is a safe-area inset the
                    // feed's coordinate space starts at the content top, so that line is just the
                    // header's own section gap — no bar geometry involved, and no off-by-one-day.
                    let line = ThemeMetrics.sectionGap + 6
                    let passed = offsets.filter { $0.value < line }
                    let current = passed.max(by: { $0.value < $1.value })?.key ?? offsets.min(by: { $0.value < $1.value })?.key ?? 0
                    if current != visibleDay {
                        visibleDay = current
                        selectedDay = current
                    }
                }
                .scrollIndicators(.hidden)
            }
            .background(ThemeColor.canvas.ignoresSafeArea())
            // The bottom fade comes from the shared chrome. The TOP band is drawn here with the
            // pinned bar's own recipe rather than `scrollEdgeChrome(top:)`: this screen's chrome is
            // glass over the art wash, and an opaque-canvas veil above it would put a hard tonal
            // seam straight across the screen at the safe-area line. Same recipe, no seam, and the
            // rule it exists to enforce — nothing ever reaches the clock — is met either way.
            .scrollEdgeChrome(top: false)
            .overlay(alignment: .top) {
                barGround
                    .frame(height: ThemeMetrics.topSafeInset)
                    .frame(maxWidth: .infinity)
                    .ignoresSafeArea(edges: .top)
            }
            .refreshable { await appModel.reload() }
            .task { await ScheduleReminders.shared.refresh() }
            .onChange(of: appModel.loading, initial: true) { _, loading in
                guard !loading, !didLand, !appModel.library.isEmpty else { return }
                // Two frames so the lazy feed has laid out today's header before we jump to it.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    proxy.scrollTo("day-0", anchor: .top)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { didLand = true }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .onChange(of: typeFilter) { _, _ in FeedbackCoordinator.fire(.selection) }
            .onChange(of: unwatchedOnly) { _, _ in FeedbackCoordinator.fire(.selection) }
            .animation(ThemeMotion.pick(ThemeMotion.uiGentle, reduceMotion: reduceMotion), value: selectedDay != 0)
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

    // MARK: - Sticky bar

    /// The bar is CHROME, so it is glass over the art wash rather than an opaque black plate with a
    /// rule under it. The same recipe paints the status-bar band above it (see `body`), which is
    /// what stops a poster from ever reaching the clock — the defect no other polish survives.
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
        let week = weekCells()
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: ThemeSpace.x2) {
                Text("Schedule").type(ThemeType.displayL).foregroundStyle(ThemeColor.textPrimary)
                Spacer(minLength: ThemeSpace.x2)
                if selectedDay != 0 {
                    Button("Today") {
                        FeedbackCoordinator.fire(.selection)
                        selectedDay = 0
                        withAnimation(reduceMotion ? nil : ThemeMotion.uiSnappy) { proxy.scrollTo("day-0", anchor: .top) }
                    }
                    .buttonStyle(InlineLinkButtonStyle())
                    .accessibilityHint("Scrolls to today")
                    .transition(.opacity)
                }
                filterMenu
            }
            .padding(.leading, ThemeMetrics.gutter)
            .padding(.trailing, 10)
            .padding(.top, ThemeSpace.x1)

            HStack(alignment: .firstTextBaseline, spacing: ThemeSpace.x2) {
                SectionLabel(text: monthLabel(week))
                    .accessibilityLabel(weekSummary(week).map { "\(monthLabel(week)), \($0) this week" } ?? monthLabel(week))
                Spacer(minLength: ThemeSpace.x2)
                // Dropped rather than truncated at accessibility sizes: "3 EPISODES THIS WE…" is
                // exactly the orphaned-metadata defect this pass exists to remove.
                if !isAX, let summary = weekSummary(week) {
                    Text(summary).type(ThemeType.sectionLabel).textCase(.uppercase)
                        .foregroundStyle(ThemeColor.textDisabled)
                        .lineLimit(1)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, ThemeMetrics.gutter)
            .padding(.top, ThemeSpace.x1)

            if isAX {
                ScrollView(.horizontal) {
                    HStack(spacing: ThemeSpace.x1) { ForEach(week) { cell in weekCell(cell, proxy: proxy).frame(minWidth: 44) } }
                        .padding(.horizontal, ThemeMetrics.gutter)
                }
                .scrollIndicators(.hidden)
                .padding(.top, ThemeSpace.x1)
            } else {
                HStack(spacing: 0) {
                    ForEach(week) { cell in weekCell(cell, proxy: proxy).frame(maxWidth: .infinity) }
                }
                .padding(.horizontal, ThemeSpace.x2)
                .padding(.top, ThemeSpace.x0_5)
            }
        }
        .padding(.bottom, ThemeSpace.x2)
        .background(barGround)
        // Content dissolves into the bar instead of being guillotined by it: a hard edge across a
        // day header cuts its letters in half, which is exactly what a hand-rolled sticky bar
        // looks like. 14 pt of the same material, ramped out.
        .overlay(alignment: .bottom) { barFade.frame(height: 14).offset(y: 14) }
    }

    private var filterMenu: some View {
        Menu {
            // No symbols on the choices. A UIKit menu tints content with the app accent, so three
            // amber glyphs appeared down the left of a three-item list — decoration the checkmark
            // already covers, in the one colour this screen spends carefully. Both groups now
            // carry a header, so the menu reads as two decisions rather than a list and a stray.
            Section("Type") {
                Picker("Type", selection: $typeFilter) {
                    Text("All").tag(MediaFilter.all)
                    Text("Anime").tag(MediaFilter.anime)
                    Text("TV").tag(MediaFilter.tv)
                }
                .pickerStyle(.inline)
            }
            Section("Watched state") {
                Toggle("Unwatched only", isOn: $unwatchedOnly)
            }
        } label: {
            Image(systemName: filterActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(filterActive ? ThemeColor.accent : ThemeColor.textPrimary)
                .frame(width: 34, height: 34)
                .chromeGlass(in: Circle(), interactive: true)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .accessibilityLabel("Filter")
        .accessibilityValue(filterValue)
    }

    struct WeekCell: Identifiable {
        let offset: Int
        let weekday: String
        let number: String
        let date: Date
        let hasContent: Bool
        let isToday: Bool
        var id: Int { offset }
    }

    /// The week (Mon–Sun) containing the selected day.
    private func weekCells() -> [WeekCell] {
        let p = Formatting.localParts(now)
        let noon = now - (Int64(p.hour) * Formatting.H + Int64(p.minute) * Formatting.minuteMs) + 12 * Formatting.H
        let selectedDate = noon + Int64(selectedDay) * Formatting.D
        let col = Formatting.localMondayCol(selectedDate)   // 0 = Monday
        let monday = selectedDay - col
        let present = Set(unfilteredDays.filter { !$0.isEmpty }.map(\.id))
        return (0..<7).map { i in
            let offset = monday + i
            let ts = noon + Int64(offset) * Formatting.D
            let parts = Formatting.localParts(ts)
            return WeekCell(offset: offset, weekday: String(Formatting.weekdayNameMonFirst(i).prefix(1)),
                            number: String(parts.d), date: Date(timeIntervalSince1970: Double(ts) / 1000),
                            hasContent: present.contains(offset), isToday: offset == 0)
        }
    }

    private func monthLabel(_ week: [WeekCell]) -> String {
        guard let first = week.first?.date, let last = week.last?.date else { return "" }
        let cal = Calendar.current
        let fm = cal.component(.month, from: first), lm = cal.component(.month, from: last)
        let fy = cal.component(.year, from: first), ly = cal.component(.year, from: last)
        if fm == lm { return first.formatted(.dateTime.month(.wide).year()) }
        if fy == ly { return "\(first.formatted(.dateTime.month(.abbreviated)))–\(last.formatted(.dateTime.month(.abbreviated))) \(fy)" }
        return "\(first.formatted(.dateTime.month(.abbreviated).year())) – \(last.formatted(.dateTime.month(.abbreviated).year()))"
    }

    /// The week's episode count on the month row's trailing edge, in the same label/count grammar
    /// the day headers use ("AUGUST 2026 ——— 4 EPISODES"). It was "4 EPISODES THIS WEEK", which at
    /// the same size and case as the month read as a second heading arguing with the first.
    private func weekSummary(_ week: [WeekCell]) -> String? {
        guard let lo = week.first?.offset, let hi = week.last?.offset else { return nil }
        let total = days.filter { $0.id >= lo && $0.id <= hi }.reduce(0) { $0 + $1.count }
        guard total > 0 else { return nil }
        return Copy.episodes(total)
    }

    private func weekCell(_ cell: WeekCell, proxy: ScrollViewProxy) -> some View {
        let selected = cell.offset == selectedDay
        let enabled = cell.hasContent || cell.isToday
        // iOS Calendar's grammar, and the fix for "a date is the brightest object on a screen of
        // shows": amber means TODAY, never merely "the cell you scrolled to". Selecting another day
        // fills the cell with tone instead — it is still unmistakably the selection, and the one
        // amber date on the strip keeps meaning the one thing amber means everywhere else.
        let amberFill = selected && cell.isToday
        let toneFill = selected && !cell.isToday
        let numberColor: Color = amberFill ? ThemeColor.onAccent
            : (cell.isToday ? ThemeColor.accent : (enabled ? ThemeColor.textPrimary : ThemeColor.textDisabled))
        return Button {
            FeedbackCoordinator.fire(.selection)
            selectedDay = cell.offset
            withAnimation(reduceMotion ? nil : ThemeMotion.uiSnappy) { proxy.scrollTo("day-\(cell.offset)", anchor: .top) }
        } label: {
            VStack(spacing: 4) {
                Text(cell.weekday).type(ThemeType.caption)
                    .foregroundStyle(cell.isToday ? ThemeColor.accent : ThemeColor.textTertiary)
                // The selection is a 34-pt cell around the NUMBER only. The shipped build filled
                // the whole 50-pt column — weekday letter, number and dot — so the brightest
                // object on a screen of shows was a date.
                Text(cell.number).type(ThemeType.time)
                    .foregroundStyle(numberColor)
                    // Padding first, then the 34-pt minimum. A fixed 34-pt box alone clipped the
                    // fill hard against the digits once Dynamic Type grew them — the selected day
                    // read as a numeral wedged into a swatch.
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .frame(minWidth: 34, minHeight: 34)
                    .background {
                        if amberFill {
                            RoundedRectangle(cornerRadius: ThemeRadius.compactControl, style: .continuous)
                                .fill(ThemeColor.accent)
                                .overlay(RoundedRectangle(cornerRadius: ThemeRadius.compactControl, style: .continuous)
                                    .strokeBorder(LinearGradient(colors: [ThemeColor.controlSheen, .clear],
                                                                startPoint: .top, endPoint: .center), lineWidth: 1))
                        } else if toneFill {
                            // Tone alone could not carry it: a +6 % fill floating on a glass bar
                            // read as a smudge under the date, not as a selection. A control is one
                            // of the three things allowed a full-perimeter stroke, and a defined
                            // edge is what makes this one legible without spending amber on it.
                            RoundedRectangle(cornerRadius: ThemeRadius.compactControl, style: .continuous)
                                .fill(ThemeColor.surfacePressed)
                                .overlay(RoundedRectangle(cornerRadius: ThemeRadius.compactControl, style: .continuous)
                                    .strokeBorder(ThemeColor.strokeStrong, lineWidth: 1))
                        }
                    }
                // Amber on a dot is a forward-looking fact — something is coming. A day that has
                // already aired gets the neutral ramp, so the strip reads past→future at a glance
                // instead of printing the same alarm colour across the whole week.
                Circle().fill(cell.offset < 0 ? ThemeColor.textDisabled : ThemeColor.accent)
                    .frame(width: 3, height: 3)
                    .opacity(cell.hasContent ? 1 : 0)
                    .frame(height: 3)
            }
            .frame(minWidth: 44, minHeight: 44)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .animation(ThemeMotion.pick(ThemeMotion.uiMicro, reduceMotion: reduceMotion), value: selected)
        }
        .buttonStyle(WeekCellPressStyle())
        .disabled(!enabled)
        .accessibilityLabel(cell.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
        .accessibilityValue(selected ? "Selected" : (cell.isToday ? "Today" : (cell.hasContent ? "" : "No episodes")))
    }

    // MARK: - Content (state matrix)

    /// A whole-screen state sits in the MIDDLE of the content area, not pinned under the week strip
    /// with 1 100 pt of canvas beneath it. `containerRelativeFrame` measures the scroll container,
    /// which — the bar being a safe-area inset — is exactly the area the user can see.
    @ViewBuilder
    private func centred<V: View>(@ViewBuilder _ state: () -> V) -> some View {
        state()
            .padding(.horizontal, ThemeMetrics.gutter)
            .frame(maxWidth: .infinity)
            // Inside the container frame, so the centring is measured against the area the tab bar
            // does not cover — an optically centred card, not a mathematically centred one.
            .padding(.bottom, ThemeMetrics.tabBarClearance)
            .containerRelativeFrame(.vertical, alignment: .center)
    }

    @ViewBuilder
    private func content(_ proxy: ScrollViewProxy) -> some View {
        if appModel.loading && appModel.library.isEmpty {
            feedSkeleton
        } else if appModel.loadError && appModel.libraryEmpty {
            centred {
                EmptyState(SyncCenter.shared.isOnline ? .serverNoCache : .offlineNoData, prominence: .major) { Task { await appModel.reload() } }
            }
        } else if appModel.libraryEmpty {
            centred { EmptyState(.emptyAccount, prominence: .major, primary: onAddShow) }
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
                let visible = shown.filter { !$0.isEmpty || $0.isToday }
                ForEach(Array(visible.enumerated()), id: \.element.id) { i, day in
                    dayView(day, isFirst: i == 0)
                }
                feedTail
            }
        }
    }

    /// The feed's loading state, composed from the shared skeleton atoms at THIS screen's geometry.
    ///
    /// `Skeleton.schedule` draws a placeholder week strip, which — now that the bar is a real
    /// safe-area inset that renders the live strip whether or not data has arrived — appeared
    /// directly beneath it: two week strips, one of them fake. It also previews 36×54 posters
    /// against this screen's 56×84 rows, so the swap to content changed the row height under the
    /// user. Same parts, right proportions, and the rail is already there when the data lands.
    private var feedSkeleton: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<3, id: \.self) { i in
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

    /// One day block. The rail is drawn as this block's background so consecutive days chain into
    /// one continuous line without any cross-row geometry being measured — the same trick the
    /// History timeline uses.
    private func dayView(_ day: Day, isFirst: Bool) -> some View {
        let showKindLabel = !day.dateOnly.isEmpty && !day.timed.isEmpty
        // A past day whose every episode is watched is DONE, so its label recedes with its rows.
        // The original's past section read as handled at a glance because the whole group went
        // quiet together, not because five separate greys were picked for five elements.
        let settled = day.id < 0 && !day.isEmpty
            && day.dateOnly.allSatisfy { $0.watched || committed.contains($0.id) }
            && day.timed.allSatisfy { $0.watched || committed.contains($0.id) }
        return VStack(alignment: .leading, spacing: 0) {
            dayHeader(day).opacity(settled ? 0.62 : 1)

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
            // Today is the anchor of this screen: NOW renders even when nothing airs, which is
            // exactly the state the shipped capture was in when the marker went missing entirely.
            if day.isToday && day.timed.isEmpty {
                nowMarker
            }
            if day.isEmpty {
                Text(hasAiredEarlierToday(day) ? "Nothing else airs today" : "Nothing airs today")
                    .type(ThemeType.rowMeta).foregroundStyle(ThemeColor.textTertiary)
                    .padding(.leading, Rail.gutter)
                    .padding(.top, ThemeSpace.x3)
                    .padding(.bottom, ThemeSpace.x1)
            }
        }
        .padding(.horizontal, ThemeMetrics.gutter)
        .background(alignment: .topLeading) { railLine(head: isFirst) }
    }

    /// The 1-pt timeline. On the FIRST day it fades up out of the header band — a hard 1-pt start
    /// under a glass bar is the tell of a hand-rolled rail. The other end is finished by `feedTail`.
    private func railLine(head: Bool) -> some View {
        GeometryReader { geo in
            let h = geo.size.height
            // The fade runs from the block's top edge to just past the day header's baseline.
            let fade = head ? min(0.5, (ThemeMetrics.sectionGap + ThemeSpace.x3) / max(h, 1)) : 0
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

    /// The end of the horizon. The feed used to stop at its last poster and leave ~300 pt of bare
    /// canvas above the tab bar — the screen ended and nothing acknowledged it. The rail now runs
    /// on past the last event and terminates in a cap, the way a measuring rule ends, with the one
    /// fact the user actually wants there: past this point nothing is scheduled.
    private var feedTail: some View {
        let run = ThemeMetrics.sectionGap
        return Text(Copy.Empty.nothingScheduled.title)
            .type(ThemeType.rowMeta)
            .foregroundStyle(ThemeColor.textDisabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
            .padding(.leading, Rail.gutter)
            .padding(.top, run)
            .padding(.horizontal, ThemeMetrics.gutter)
            .overlay(alignment: .topLeading) {
                GeometryReader { geo in
                    // The cap sits on the caption's own centre line, whatever the type size does.
                    let capY = run + (geo.size.height - run) / 2
                    ZStack(alignment: .topLeading) {
                        Rectangle().fill(ThemeColor.separator).frame(width: 1, height: capY)
                        Rectangle().fill(ThemeColor.separator).frame(width: 11, height: 1)
                            .offset(x: -5, y: capY)
                    }
                    .offset(x: ThemeMetrics.gutter + Rail.x - 0.5)
                }
                .allowsHitTesting(false)
            }
            .padding(.bottom, ThemeMetrics.tabBarClearance)
            .accessibilityElement(children: .combine)
    }

    private func dayHeader(_ day: Day) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: ThemeMetrics.labelGap) {
            Text(day.header).type(ThemeType.dayLabel).textCase(.uppercase)
                .foregroundStyle(day.isToday ? ThemeColor.accent : ThemeColor.textTertiary)
                .lineLimit(isAX ? 2 : 1)
                .fixedSize(horizontal: false, vertical: true)
            if !isAX {
                // Neutral even on Today: the label already carries the amber, and a second amber
                // rule 40 pt above the NOW line's amber rule was two of the same gesture in one
                // glance. It also fades out to the right rather than ruling edge to edge — six
                // full-width hairlines down one screen is what makes a feed read as a table.
                Rectangle().fill(LinearGradient(colors: [ThemeColor.separatorQuiet, ThemeColor.separatorQuiet.opacity(0)],
                                                startPoint: .leading, endPoint: .trailing))
                    .frame(height: 1)
            } else {
                Spacer(minLength: ThemeSpace.x2)
            }
            if day.count > 0 {
                Text(Copy.episodes(day.count)).type(ThemeType.sectionLabel).textCase(.uppercase)
                    .foregroundStyle(ThemeColor.textDisabled)
                    .lineLimit(1)
            }
        }
        .padding(.leading, Rail.gutter)
        .padding(.top, ThemeMetrics.sectionGap)
        .padding(.bottom, ThemeSpace.x1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(day.count > 0 ? "\(day.header), \(Copy.episodes(day.count))" : day.header)
        .accessibilityAddTraits(.isHeader)
        .id("day-\(day.id)")
        .background(GeometryReader { geo in
            Color.clear.preference(key: DayHeaderKey.self, value: [day.id: geo.frame(in: .named("schedule.feed")).minY])
        })
    }

    /// "Date only" / "Timed" — printed ONLY when a day genuinely carries both kinds. A day section
    /// already supplies the item's context; repeating it above every row is five identical eyebrows
    /// carrying no information.
    private func kindLabel(_ text: String) -> some View {
        SectionLabel(text: text)
            .padding(.leading, Rail.gutter)
            .padding(.top, ThemeMetrics.labelGap)
            .padding(.bottom, ThemeSpace.x0_5)
            .accessibilityAddTraits(.isHeader)
    }

    private func hasAiredEarlierToday(_ day: Day) -> Bool {
        guard day.isToday, let raw = appModel.scheduleDays.first(where: \.isToday) else { return false }
        return !raw.airedToday.isEmpty
    }

    // MARK: - NOW

    /// `NOW ————————— 5:54 AM`, on the rail, in the one place amber is unambiguously right.
    /// It is the only thing on this screen that moves on its own, once a minute.
    private var nowMarker: some View {
        HStack(spacing: ThemeMetrics.labelGap) {
            Text("Now").type(ThemeType.dayLabel).textCase(.uppercase).foregroundStyle(ThemeColor.accent)
            if !isAX {
                // It has to LAND on the time, not evaporate two thirds of the way there, or the
                // clock at the end reads as an unrelated number floating in the gutter.
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
        .overlay(alignment: .leading) {
            Circle().fill(ThemeColor.accent)
                .frame(width: Rail.node, height: Rail.node)
                .background { Circle().fill(ThemeColor.accentSoft).frame(width: Rail.node + 10, height: Rail.node + 10) }
                .offset(x: Rail.x - Rail.node / 2)
                .accessibilityHidden(true)
        }
        .animation(reduceMotion ? nil : ThemeMotion.uiGentle, value: nowMinute)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Now, \(Formatting.fmtTime(nowMinute))")
    }

    // MARK: - Row

    private func row(_ e: Event) -> some View {
        let f = e.franchise
        let isCommitted = committed.contains(e.id)
        let watched = e.watched || isCommitted
        let showsAction = e.aired && !watched && appModel.isInLibrary(f.id)
        let batch = e.aired && e.episode > e.part.progress + 1
        let time = e.dateOnly ? nil : Formatting.fmtTime(e.at, anchor: f.timeAnchor)
        // The trailing column has ONE grammar for every row: a state word over the time. Future
        // reads AIRS / 8:30 PM; a watched row reads ✓ / 7:30 PM. Only an actionable row replaces
        // the pair with the mark control, because a row gets one primary action and no company.
        // (Previously a watched row hid its time in the meta line and put a bare 14-pt grey check
        // 350 pt away from the text it belonged to — a tick alone in an empty gutter.)
        let meta = metaLine(e, inlineTime: showsAction ? time : nil)
        let spokenTime = showsAction ? "" : (time.map { ", \($0)" } ?? "")
        let hasReminder = !e.aired && ScheduleReminders.shared.has(mediaId: e.part.mediaId, episode: e.episode)
        let layout = isAX ? AnyLayout(VStackLayout(alignment: .leading, spacing: ThemeSpace.x3))
                          : AnyLayout(HStackLayout(alignment: .center, spacing: ThemeSpace.x3))
        return layout {
            Button { onOpenDetail(f.id, "sched/\(f.id)", EpisodeFocus(mediaId: e.part.mediaId, episode: e.episode)) } label: {
                HStack(spacing: ThemeMetrics.artGap) {
                    PosterSlot(url: f.cover, width: Rail.posterW, height: Rail.posterH,
                               radius: ThemeRadius.poster, shadow: ShadowToken.none)
                    VStack(alignment: .leading, spacing: ThemeMetrics.titleGap) {
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
            // `meta` already carries the time when the trailing column is the mark control; every
            // other row keeps its time in that column, so VoiceOver picks it up from here instead.
            // `meta` already carries the time when the trailing column is the mark control; every
            // other row keeps its time in that column, so VoiceOver picks it up from here instead.
            .accessibilityLabel("\(f.title), \(meta)\(spokenTime)\(hasReminder ? ", reminder set" : "")")
            .accessibilityValue(watched ? Copy.Accessibility.complete : "")
            .accessibilityHint("Opens the show")

            // At accessibility sizes the row stacks, and the control lines up with the TEXT column
            // rather than with the poster — otherwise a lone check floats under the artwork with
            // nothing to belong to.
            trailing(e, showsAction: showsAction, watched: watched, batch: batch, time: time, hasReminder: hasReminder)
                .padding(.leading, isAX ? Rail.posterW + ThemeMetrics.artGap : 0)
                .frame(maxWidth: isAX ? .infinity : nil, alignment: .leading)
        }
        .padding(.leading, Rail.gutter)
        .padding(.vertical, ThemeSpace.x2)
        .frame(minHeight: ThemeMetrics.rowMedia, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        // A handled row recedes as ONE opacity: element-by-element greys break the artwork's
        // colour relationship and read as five disabled controls rather than one settled row.
        .opacity(watched ? 0.48 : 1)
        .overlay(alignment: .leading) { node(watched: watched, aired: e.aired) }
        .animation(ThemeMotion.pick(ThemeMotion.uiMicro, reduceMotion: reduceMotion), value: isCommitted)
    }

    @ViewBuilder
    private func trailing(_ e: Event, showsAction: Bool, watched: Bool, batch: Bool,
                          time: String?, hasReminder: Bool) -> some View {
        if showsAction {
            Button { mark(e, batch: batch) } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(ThemeColor.accent)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(ThemeColor.accentSoft))
                    .overlay(Circle().strokeBorder(ThemeColor.accent.opacity(0.55), lineWidth: 1.5))
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(MarkPressStyle())
            .accessibilityLabel(batch ? "Mark \(Copy.episodes(e.episode - e.part.progress)) of \(e.franchise.title) as watched"
                                      : "Mark \(Copy.episode(e.episode)) of \(e.franchise.title) as watched")
            .transition(.opacity.combined(with: .scale(scale: 0.6)))
        } else if e.aired {
            // Settled: the same two-line column the upcoming rows use, with the tick standing where
            // AIRS stands. The row is already dimmed as a group, so this needs no colour of its own.
            VStack(alignment: isAX ? .leading : .trailing, spacing: 1) {
                if watched { PassiveTick() }
                if let time {
                    Text(time).type(ThemeType.time).foregroundStyle(ThemeColor.textSecondary)
                }
            }
            .frame(minWidth: 44, alignment: isAX ? .leading : .trailing)
            .accessibilityHidden(true)
            .transition(.opacity.combined(with: .scale(scale: 0.6)))
        } else if let time {
            VStack(alignment: isAX ? .leading : .trailing, spacing: 1) {
                HStack(spacing: 4) {
                    if hasReminder {
                        Image(systemName: "bell.fill").font(.system(size: 10))
                            .foregroundStyle(ThemeColor.textDisabled)
                            .accessibilityHidden(true)
                    }
                    Text("Airs").type(ThemeType.sectionLabel).textCase(.uppercase)
                        .foregroundStyle(ThemeColor.textDisabled)
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

    /// The rail node, and it carries meaning rather than decoration: **filled = it happened,
    /// hollow = it has not yet**. So the eye can read past→future down the gutter without reading a
    /// word. Amber belongs to NOW alone here — the row's own control is already the amber thing
    /// when a row is actionable, and two ambers for one action is one too many.
    private func node(watched: Bool, aired: Bool) -> some View {
        Group {
            if watched {
                // Done. Smaller and quieter than a live one; the row above it is dimmed as a group.
                Circle().fill(ThemeColor.textDisabled)
                    .frame(width: Rail.node - 2, height: Rail.node - 2)
            } else if aired {
                Circle().fill(ThemeColor.textSecondary)
            } else {
                Circle().fill(ThemeColor.canvas)
                    .overlay(Circle().strokeBorder(ThemeColor.textDisabled, lineWidth: 1.5))
            }
        }
        .frame(width: Rail.node, height: Rail.node)
        .offset(x: Rail.x - Rail.node / 2)
        .accessibilityHidden(true)
    }

    private func metaLine(_ e: Event, inlineTime: String?) -> String {
        var s: String
        if e.franchise.source == .tmdb {
            let season = e.part.canonicalLabel
            if !e.aired && e.part.nextAiringCount > 1 {
                s = season.isEmpty ? Copy.episodes(e.part.nextAiringCount) : "\(season) · \(Copy.episodes(e.part.nextAiringCount))"
            } else {
                s = season.isEmpty ? Copy.episode(e.episode) : "\(season) · \(Copy.episode(e.episode))"
            }
        } else {
            s = Copy.episode(e.episode)
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

    /// The button is replaced in place by the tick and the row settles into its dimmed state; the
    /// row never moves (a calendar keeps its history) unless "Unwatched only" is on, in which case
    /// it leaves after a 650 ms hold.
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

/// Press feedback for the round mark control: compression only, no rounded-rect wash behind a
/// circle. Reduce Motion presses in opacity (board 11).
private struct MarkPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.985 : 1))
            .opacity(reduceMotion && configuration.isPressed ? 0.72 : 1)
            .animation(ThemeMotion.pick(ThemeMotion.uiPress, reduceMotion: reduceMotion),
                       value: configuration.isPressed)
    }
}

/// The week strip's press feedback. `RowPressStyle` paints a 16-pt rounded wash across the whole
/// 44-pt column; a date cell wants nothing but its own compression.
private struct WeekCellPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.94 : 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(ThemeMotion.pick(ThemeMotion.uiPress, reduceMotion: reduceMotion),
                       value: configuration.isPressed)
    }
}

private struct DayHeaderKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] { [:] }
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}
