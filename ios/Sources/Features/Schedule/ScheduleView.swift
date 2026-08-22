import SwiftUI

// Schedule (spec board 04). One chronological feed: day headers → "Date only" / "Timed" groups →
// 68-pt event rows. The NOW line crosses only timed rows and moves once a minute. A date-only
// (TMDB) row never shows a clock. The only write here is "Mark as watched" on a past row.
struct ScheduleView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    let onOpenDetail: (_ franchiseId: String, _ zoomID: String, _ focus: EpisodeFocus?) -> Void
    var onAddShow: () -> Void = {}

    @State private var selectedDay = 0
    /// The day whose header is at the top of the feed; the strip follows it while scrolling.
    @State private var visibleDay = 0
    @State private var typeFilter: MediaFilter = .all
    @State private var unwatchedOnly = false
    @State private var committed: Set<String> = []
    @State private var prompt: FranchiseDetailView.WritePrompt?

    private var now: Int64 { appModel.now }
    private var nowMinute: Int64 { (now / Formatting.minuteMs) * Formatting.minuteMs }
    private var isAX: Bool { typeSize.isAccessibilitySize }

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

    // MARK: - Body

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        content(proxy)
                    } header: {
                        stickyBar(proxy)
                    }
                }
                .padding(.bottom, 120)
            }
            .coordinateSpace(name: "schedule.feed")
            .onPreferenceChange(DayHeaderKey.self) { offsets in
                // The last header that has scrolled under the sticky bar is the current day.
                let threshold: CGFloat = 120
                if let top = offsets.filter({ $0.value <= threshold }).max(by: { $0.value < $1.value })?.key ?? offsets.min(by: { $0.value < $1.value })?.key,
                   top != visibleDay {
                    visibleDay = top
                    selectedDay = top
                }
            }
            .scrollIndicators(.hidden)
            .background(ThemeColor.canvas.ignoresSafeArea())
            .refreshable { await appModel.reload() }
            .task { await ScheduleReminders.shared.refresh() }
            .navigationTitle("Schedule")
            .navigationBarTitleDisplayMode(.large)
            .toolbar(.visible, for: .navigationBar)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if selectedDay != 0 {
                        Button("Today") {
                            FeedbackCoordinator.fire(.selection)
                            selectedDay = 0
                            withAnimation(reduceMotion ? nil : ThemeMotion.uiSnappy) { proxy.scrollTo("day-0", anchor: .top) }
                        }
                        .accessibilityHint("Scrolls to today")
                        .transition(.opacity)
                    }
                    Menu {
                        Picker("Type", selection: $typeFilter) {
                            Text("All").tag(MediaFilter.all)
                            Text("Anime").tag(MediaFilter.anime)
                            Text("TV").tag(MediaFilter.tv)
                        }
                        .pickerStyle(.inline)
                        Section("Watched state") {
                            Toggle("Unwatched only", isOn: $unwatchedOnly)
                        }
                    } label: {
                        Label("Filter", systemImage: "slider.horizontal.3")
                            .foregroundStyle(filterActive ? ThemeColor.accent : ThemeColor.textPrimary)
                    }
                    .accessibilityLabel("Filter")
                    .accessibilityValue(filterValue)
                }
            }
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

    private func stickyBar(_ proxy: ScrollViewProxy) -> some View {
        let week = weekCells()
        return VStack(alignment: .leading, spacing: 4) {
            SectionLabel(text: monthLabel(week))
                .padding(.leading, ThemeSpace.x4)
                .accessibilityLabel(monthLabel(week))
            if isAX {
                ScrollView(.horizontal) {
                    HStack(spacing: 4) { ForEach(week) { cell in weekCell(cell, proxy: proxy).frame(minWidth: 44) } }
                        .padding(.horizontal, ThemeSpace.x4)
                }
                .scrollIndicators(.hidden)
            } else {
                HStack(spacing: 0) {
                    ForEach(week) { cell in weekCell(cell, proxy: proxy).frame(maxWidth: .infinity) }
                }
                .padding(.horizontal, ThemeSpace.x2)
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 10)
        .background(ThemeColor.canvas)
        .overlay(alignment: .bottom) { Rectangle().fill(ThemeColor.separator).frame(height: 1) }
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

    private func weekCell(_ cell: WeekCell, proxy: ScrollViewProxy) -> some View {
        let selected = cell.offset == selectedDay
        let enabled = cell.hasContent || cell.isToday
        return Button {
            FeedbackCoordinator.fire(.selection)
            selectedDay = cell.offset
            withAnimation(reduceMotion ? nil : ThemeMotion.uiSnappy) { proxy.scrollTo("day-\(cell.offset)", anchor: .top) }
        } label: {
            VStack(spacing: 3) {
                Text(cell.weekday).type(ThemeType.caption)
                    .foregroundStyle(selected ? ThemeColor.onAccent.opacity(0.6) : ThemeColor.textTertiary)
                Text(cell.number).type(ThemeType.time)
                    .foregroundStyle(selected ? ThemeColor.onAccent : (cell.isToday ? ThemeColor.accent : (enabled ? ThemeColor.textPrimary : ThemeColor.textDisabled)))
                Circle().fill(selected ? ThemeColor.onAccent.opacity(0.6) : ThemeColor.accent)
                    .frame(width: 3, height: 3)
                    .opacity(cell.hasContent || cell.isToday ? 1 : 0)
                    .frame(height: 4)
            }
            .frame(width: 44, height: 50)
            .background(selected ? ThemeColor.accent : .clear, in: RoundedRectangle(cornerRadius: ThemeRadius.compactControl, style: .continuous))
            .frame(maxWidth: .infinity, minHeight: 50)
            .contentShape(Rectangle())
            .animation(ThemeMotion.pick(ThemeMotion.uiMicro, reduceMotion: reduceMotion), value: selected)
        }
        .buttonStyle(RowPressStyle())
        .disabled(!enabled)
        .accessibilityLabel(cell.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
        .accessibilityValue(selected ? "Selected" : (cell.isToday ? "Today" : (cell.hasContent ? "" : "No episodes")))
    }

    // MARK: - Content (state matrix)

    @ViewBuilder
    private func content(_ proxy: ScrollViewProxy) -> some View {
        if appModel.loading && appModel.library.isEmpty {
            Skeleton.schedule.padding(.top, ThemeSpace.x4)
        } else if appModel.loadError && appModel.libraryEmpty {
            EmptyState(SyncCenter.shared.isOnline ? .serverNoCache : .offlineNoData, prominence: .major) { Task { await appModel.reload() } }
                .padding(ThemeSpace.x4)
        } else if appModel.libraryEmpty {
            EmptyState(.emptyAccount, prominence: .major, primary: onAddShow).padding(ThemeSpace.x4)
        } else {
            if appModel.sectionFailed {
                InlineNotice(Copy.Notice.schedule) { Task { await appModel.reload() } }
                    .padding(.horizontal, ThemeSpace.x4).padding(.top, ThemeSpace.x3)
            } else if let since = appModel.staleSince(.exactAiring) {
                StaleStrip(since: since, now: now).padding(.horizontal, ThemeSpace.x4).padding(.top, ThemeSpace.x2)
            }
            let all = unfilteredDays
            let shown = days
            if all.allSatisfy(\.isEmpty) {
                EmptyState(.nothingScheduled, prominence: .major).padding(ThemeSpace.x4)
            } else if shown.allSatisfy(\.isEmpty) && filterActive {
                EmptyState(.noFilterMatches, prominence: .major, primary: {
                    withAnimation(ThemeMotion.pick(ThemeMotion.uiSnappy, reduceMotion: reduceMotion)) { typeFilter = .all; unwatchedOnly = false }
                })
                .padding(ThemeSpace.x4)
            } else {
                ForEach(shown) { day in
                    if !day.isEmpty || day.isToday {
                        dayView(day)
                    }
                }
            }
        }
    }

    // MARK: - Day

    private func dayView(_ day: Day) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                SectionLabel(text: day.header, tint: day.isToday ? ThemeColor.accent : ThemeColor.textTertiary)
                Rectangle().fill(day.isToday ? ThemeColor.accent.opacity(0.25) : ThemeColor.separator).frame(height: 1)
            }
            .padding(.horizontal, ThemeSpace.x4)
            .padding(.top, ThemeSpace.x6)
            .padding(.bottom, 6)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(day.header)
            .accessibilityAddTraits(.isHeader)
            .id("day-\(day.id)")
            .background(GeometryReader { geo in
                Color.clear.preference(key: DayHeaderKey.self, value: [day.id: geo.frame(in: .named("schedule.feed")).minY])
            })

            if day.isEmpty {
                Text(day.timed.isEmpty && day.dateOnly.isEmpty && hasAiredEarlierToday(day) ? "Nothing else airs today" : "Nothing airs today")
                    .type(ThemeType.metadata).foregroundStyle(ThemeColor.textTertiary)
                    .padding(.horizontal, ThemeSpace.x4).padding(.top, 10)
            }
            if !day.dateOnly.isEmpty {
                group("Date only", events: day.dateOnly, withNow: false)
            }
            if !day.timed.isEmpty {
                group("Timed", events: day.timed, withNow: day.isToday)
            }
        }
    }

    private func hasAiredEarlierToday(_ day: Day) -> Bool {
        guard day.isToday, let raw = appModel.scheduleDays.first(where: \.isToday) else { return false }
        return !raw.airedToday.isEmpty
    }

    private func group(_ label: String, events: [Event], withNow: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(text: label)
                .padding(.horizontal, ThemeSpace.x4).padding(.top, 12).padding(.bottom, 2)
                .accessibilityAddTraits(.isHeader)
            let nowIndex = withNow ? (events.firstIndex { $0.at > nowMinute } ?? events.count) : -1
            ForEach(Array(events.enumerated()), id: \.element.id) { i, e in
                if i == nowIndex { nowLine }
                row(e, isLast: i == events.count - 1)
            }
            if withNow && nowIndex == events.count { nowLine }
        }
    }

    private var nowLine: some View {
        HStack(spacing: 8) {
            Circle().fill(ThemeColor.accent).frame(width: 7, height: 7)
            Text("Now · \(Formatting.fmtTime(nowMinute))").type(ThemeType.sectionLabel).textCase(.uppercase).foregroundStyle(ThemeColor.accent)
            Rectangle().fill(ThemeColor.accent.opacity(0.7)).frame(height: 1)
        }
        .padding(.horizontal, ThemeSpace.x4)
        .frame(height: 26)
        .padding(.vertical, 4)
        .animation(reduceMotion ? nil : ThemeMotion.uiGentle, value: nowMinute)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Now, \(Formatting.fmtTime(nowMinute))")
    }

    // MARK: - Row

    private func row(_ e: Event, isLast: Bool) -> some View {
        let f = e.franchise
        let showsAction = e.aired && !e.watched && !committed.contains(e.id) && appModel.isInLibrary(f.id)
        let isCommitted = committed.contains(e.id)
        let watched = e.watched || isCommitted
        let batch = e.aired && e.episode > e.part.progress + 1
        let time = e.dateOnly ? nil : Formatting.fmtTime(e.at, anchor: f.timeAnchor)
        let meta = metaLine(e, inlineTime: showsAction && !isAX ? time : nil)
        let layout = isAX ? AnyLayout(VStackLayout(alignment: .leading, spacing: ThemeSpace.x2))
                          : AnyLayout(HStackLayout(alignment: .center, spacing: ThemeSpace.x3))
        return VStack(spacing: 0) {
            layout {
                Button { onOpenDetail(f.id, "sched/\(f.id)", EpisodeFocus(mediaId: e.part.mediaId, episode: e.episode)) } label: {
                    HStack(spacing: ThemeSpace.x3) {
                        PosterSlot(url: f.cover, width: 36, height: 54, radius: 6)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(f.title).type(ThemeType.showTitleS).foregroundStyle(ThemeColor.textPrimary).lineLimit(isAX ? 3 : 1)
                            Text(meta).type(ThemeType.metadata).foregroundStyle(ThemeColor.textSecondary).lineLimit(isAX ? 2 : 1)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(f.title), \(meta)\(time != nil && !showsAction ? ", \(time!)" : "")\(!e.aired && ScheduleReminders.shared.has(mediaId: e.part.mediaId, episode: e.episode) ? ", reminder set" : "")")
                .accessibilityValue(watched ? "Complete" : "")
                .accessibilityHint("Opens the show")

                HStack(spacing: ThemeSpace.x2) {
                    if !e.aired, ScheduleReminders.shared.has(mediaId: e.part.mediaId, episode: e.episode) {
                        Image(systemName: "bell.fill").font(.system(size: 14)).foregroundStyle(ThemeColor.textTertiary)
                            .accessibilityHidden(true)
                    }
                    if let time, !showsAction, !isAX {
                        Text(time).type(ThemeType.time).foregroundStyle(ThemeColor.textSecondary)
                    }
                    if showsAction {
                        Button(batch ? "\(Copy.Action.markAsWatched)\u{2026}" : Copy.Action.markAsWatched) { mark(e, batch: batch) }
                            .buttonStyle(CompactActionButtonStyle())
                            .accessibilityLabel(batch ? "Mark \(Copy.episodes(e.episode - e.part.progress)) of \(f.title) as watched"
                                                      : "Mark \(Copy.episode(e.episode)) of \(f.title) as watched")
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    } else if e.aired && watched {
                        PassiveTick(boxed: true)
                            .transition(.opacity.combined(with: .scale(scale: 0.6)))
                    }
                }
                .fixedSize()
                .animation(ThemeMotion.pick(ThemeMotion.uiMicro, reduceMotion: reduceMotion), value: isCommitted)
                .frame(maxWidth: isAX ? .infinity : nil, alignment: .leading)
            }
            .padding(.horizontal, ThemeSpace.x4)
            .frame(minHeight: 68)
            .fixedSize(horizontal: false, vertical: true)
        }
        .overlay(alignment: .bottom) {
            if !isLast { Rectangle().fill(ThemeColor.separator).frame(height: 1).padding(.leading, 64).padding(.trailing, ThemeSpace.x4) }
        }
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

    /// The button is replaced in place by the tick; the row never moves (a calendar keeps its
    /// history) unless "Unwatched only" is on, in which case it leaves after a 650 ms hold.
    private func commit(_ e: Event, then present: @escaping () -> Void) {
        withAnimation(ThemeMotion.pick(ThemeMotion.uiMicro, reduceMotion: reduceMotion)) {
            committed.insert(e.id)
        } completion: {
            if unwatchedOnly {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(650))
                    withAnimation(ThemeMotion.pick(ThemeMotion.uiSettle, reduceMotion: reduceMotion)) {
                        committed.remove(e.id)
                    } completion: { present() }
                }
            } else {
                present()
            }
        }
    }
}


private struct DayHeaderKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] { [:] }
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}
