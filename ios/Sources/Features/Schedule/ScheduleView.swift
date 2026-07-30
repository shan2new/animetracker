import SwiftUI

// "Schedule" tab — the time-rail design (schedule-v5): a Monday-first week strip up top, then one
// continuous chronological rail. A 2pt spine runs down a fixed-width left gutter and every row is
// [gutter | content], so day-rule ticks, episode nodes and the NOW marker share one exact vertical
// axis (the gutter centre) by construction — no per-node offsets to drift. Node grammar: ✓ = aired,
// ring = scheduled, glowing accent dot = the next episode today (whose row is the banner hero).
// Source rules unchanged: anime shows real clock times/countdowns; TV never shows a time.
struct ScheduleView: View {
    @Environment(AppModel.self) private var appModel
    /// Opens the detail drawer deep-linked to the row's season + episode (focus nil = plain open).
    let onOpenDetail: (_ franchiseId: String, _ zoomID: String, _ focus: EpisodeFocus?) -> Void

    // Guards the initial scroll-to-now so it fires once, not on every data refresh.
    @State private var didAnchor = false
    // Large title scrolled away → compact blurred bar (same grammar as Library/Search).
    @State private var scrolled = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Scroll-synced week-strip highlight. Day-rule positions are recorded in CONTENT coordinates,
    // which don't change while scrolling — geometry callbacks fire only on layout, and the single
    // scroll handler below does a plain dictionary scan (no model access) per frame. The box is a
    // reference type (mutating it doesn't re-render); only the derived `focusDay` is @State, and
    // it only changes when the viewport actually crosses into another day.
    private final class RuleTracker { var ys: [Int: CGFloat] = [:] }
    @State private var ruleTracker = RuleTracker()
    @State private var focusDay = 0
    // Drives the live node's glow breath (GPU-composited scale/opacity, not a per-frame redraw).
    @State private var livePulse = false

    private var now: Int64 { appModel.now }

    // Rail geometry. The spine and every node centre on gutterW/2; the trailing column is a fixed
    // width so times/labels right-align down the whole feed.
    private let gutterW: CGFloat = 30
    private let trailW: CGFloat = 76
    private let spineColor = Color.white.opacity(0.11)

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header

                    if appModel.loadError && !appModel.libraryEmpty {
                        RetryBanner { Task { await appModel.reload() } }
                    }

                    if appModel.loading && appModel.library.isEmpty {
                        Loader()
                    } else if appModel.loadError && appModel.libraryEmpty {
                        EmptyStateView(
                            title: "Couldn't load your shows",
                            message: "The server couldn't be reached. Check your connection and try again.",
                            ctaLabel: "Retry",
                            onCta: { Task { await appModel.reload() } }
                        )
                    } else if appModel.airingFranchises.isEmpty {
                        EmptyStateView(
                            title: "No airing shows yet",
                            message: appModel.libraryEmpty
                                ? "Add currently-airing shows and your weekly schedule fills in here."
                                : "None of your shows are currently airing. Add airing anime or TV to see them here."
                        )
                    } else {
                        weekStrip(proxy).padding(.top, 14)
                        rail
                            .onAppear { anchorToNow(proxy) }
                    }
                }
                .padding(.horizontal, Theme.Space.gutter)
                .padding(.top, 18)
                .padding(.bottom, 120)
                .animation(.uiGentle, value: appModel.loading)
                .animation(.uiGentle, value: appModel.loadError)
                .coordinateSpace(name: "railContent")
            }
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)
            // One handler per scroll frame: compact-bar threshold + week-strip focus, both derived
            // from the offset alone. State only mutates on a crossing, so scrolling doesn't
            // re-evaluate the body per frame.
            .onScrollGeometryChange(for: CGFloat.self,
                                    of: { $0.contentOffset.y + $0.contentInsets.top }) { _, y in
                let isPast = y > 64
                if isPast != scrolled { withAnimation(.uiGentle) { scrolled = isPast } }
                let f = focusedDay(atScrollOffset: y)
                if f != focusDay { withAnimation(.uiGentle) { focusDay = f } }
            }
            .overlay(alignment: .top) { compactHeader }
        }
        .background(AppBackground())
        .refreshable {
            await appModel.reload()
            if !appModel.loadError { Haptics.impact(.light) }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
    }

    /// Lands the initial scroll with the NOW marker mid-viewport — past reads upward, upcoming
    /// downward — without animating. `scheduleDays` can be empty while the library is still
    /// loading, so re-attempt on data arrival.
    private func anchorToNow(_ proxy: ScrollViewProxy) {
        guard !didAnchor, appModel.scheduleDays.contains(where: \.isToday) else { return }
        didAnchor = true
        proxy.scrollTo("now", anchor: .center)
    }

    // MARK: header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Schedule")
                .scaledFont(28, weight: .bold)
                .tracking(-0.8)
            Spacer(minLength: 12)
            if !appModel.airingFranchises.isEmpty {
                Text(weekMetaLabel)
                    .scaledFont(10, weight: .semibold, monospacedDigit: true)
                    .tracking(1.4)
                    .foregroundStyle(Theme.text36)
            }
        }
    }

    // Blurred compact bar once the large title scrolls away (Apple large-title pattern).
    @ViewBuilder
    private var compactHeader: some View {
        if scrolled {
            Text("Schedule")
                .scaledFont(16, weight: .bold)
                .tracking(-0.2)
                .frame(maxWidth: .infinity)
                .padding(.top, 6)
                .padding(.bottom, 12)
                .background(.ultraThinMaterial)
                .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
                .transition(.opacity)
        }
    }

    private var weekMetaLabel: String {
        let todayCol = Formatting.localMondayCol(now)
        let week = (-todayCol)...(6 - todayCol)
        var ids = Set<String>()
        for day in appModel.scheduleDays where week.contains(day.id) {
            for f in day.franchises { ids.insert(f.id) }
            for f in day.airedToday { ids.insert(f.id) }
        }
        return "\(ids.count) AIRING THIS WEEK"
    }

    // MARK: week strip

    private struct WeekCell: Identifiable {
        let id: Int        // Monday-first column
        let offset: Int    // day offset from today (= ScheduleDay.id)
        let letter: String
        let dayNum: Int
        let count: Int
        let isPast: Bool
        let isToday: Bool
    }

    private var weekCells: [WeekCell] {
        // Anchor on local noon so a day step survives DST transitions (same trick as scheduleDays).
        let p = Formatting.localParts(now)
        let noon = now - (Int64(p.hour) * Formatting.H + Int64(p.minute) * Formatting.minuteMs) + 12 * Formatting.H
        let todayCol = Formatting.localMondayCol(now)
        let counts = Dictionary(uniqueKeysWithValues: appModel.scheduleDays.map {
            ($0.id, $0.franchises.count + $0.airedToday.count)
        })
        return (0..<7).map { col in
            let offset = col - todayCol
            return WeekCell(
                id: col,
                offset: offset,
                letter: String(Formatting.weekdayNameMonFirst(col).prefix(1)),
                dayNum: Formatting.localParts(noon + Int64(offset) * Formatting.D).d,
                count: counts[offset] ?? 0,
                isPast: offset < 0,
                isToday: offset == 0
            )
        }
    }

    /// Days with episodes are tappable (scroll the rail to that day); the day currently under the
    /// viewport gets a quiet ring, so the strip doubles as a position indicator.
    private func weekStrip(_ proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 4) {
            ForEach(weekCells) { cell in
                weekCellView(cell, proxy: proxy)
            }
        }
    }

    private func weekCellView(_ cell: WeekCell, proxy: ScrollViewProxy) -> some View {
        let focused = !cell.isToday && cell.offset == focusDay
        let shape = RoundedRectangle(cornerRadius: 13, style: .continuous)
        return Button {
            Haptics.selection()
            withAnimation(.uiSmooth) {
                if cell.isToday {
                    proxy.scrollTo("now", anchor: .center)
                } else {
                    proxy.scrollTo("rule-\(cell.offset)", anchor: .top)
                }
            }
        } label: {
            VStack(spacing: 3) {
                Text(cell.letter)
                    .scaledFont(8.5, weight: .medium)
                    .tracking(0.8)
                    .foregroundStyle(cell.isToday ? Theme.background.opacity(0.6) : Theme.text36)
                Text("\(cell.dayNum)")
                    .scaledFont(13.5, weight: cell.isToday ? .bold : .semibold, monospacedDigit: true)
                    .foregroundStyle(cell.isToday ? Theme.background
                                     : (cell.isPast ? Theme.text36 : Theme.text72))
                HStack(spacing: 3) {
                    ForEach(0..<min(cell.count, 3), id: \.self) { _ in
                        Circle()
                            .fill(cell.isToday ? Theme.background
                                  : (cell.isPast ? Color.white.opacity(0.28) : Theme.accent))
                            .frame(width: 3.5, height: 3.5)
                    }
                }
                .frame(height: 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background {
                if cell.isToday {
                    shape.fill(Theme.accent)
                } else if focused {
                    shape.fill(Theme.fillSoft)
                        .overlay(shape.stroke(Theme.hairlineStrong, lineWidth: 1))
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(SpringPressButtonStyle(scale: 0.94))
        .disabled(!cell.isToday && cell.count == 0)
        .animation(.uiGentle, value: focused)
    }

    /// The day whose rule most recently crossed the reading line (~150pt below the viewport top).
    /// Pure dictionary scan over recorded content-space positions — deliberately no model access;
    /// this runs on every scroll frame.
    private func focusedDay(atScrollOffset y: CGFloat) -> Int {
        var best: (day: Int, y: CGFloat)?
        var first: (day: Int, y: CGFloat)?
        for (day, ruleY) in ruleTracker.ys {
            if first == nil || ruleY < first!.y { first = (day, ruleY) }
            if ruleY <= y + 150, best == nil || ruleY > best!.y { best = (day, ruleY) }
        }
        return best?.day ?? first?.day ?? 0
    }

    // MARK: rail model — the flattened chronological feed

    private enum RailNode { case ring, unwatched, done, live, nowTick }

    private struct RailRow: Identifiable {
        enum Kind {
            case rule(AppModel.ScheduleDay)
            case episode(Franchise, day: AppModel.ScheduleDay, aired: Bool, hero: Bool)
            case nowMarker
            case note(String)
        }
        let id: String
        let kind: Kind
        var divider = false   // hairline above — only between two adjacent plain episode rows
    }

    private var railRows: [RailRow] {
        var rows: [RailRow] = []
        var prevWasEpisode = false
        func add(_ id: String, _ kind: RailRow.Kind, episode: Bool = false) {
            rows.append(RailRow(id: id, kind: kind, divider: episode && prevWasEpisode))
            prevWasEpisode = episode
        }
        for day in appModel.scheduleDays {
            add("rule-\(day.id)", .rule(day))
            if day.isToday {
                for f in day.airedToday {
                    add("aired/\(f.id)", .episode(f, day: day, aired: true, hero: false), episode: true)
                }
                add("now", .nowMarker)
                if day.franchises.isEmpty {
                    add("note-today", .note(day.airedToday.isEmpty
                                            ? "Nothing airing today" : "No more airings today"))
                } else {
                    // The next episode today gets the live node + banner hero treatment.
                    for (i, f) in day.franchises.enumerated() {
                        add("sched/\(f.id)", .episode(f, day: day, aired: false, hero: i == 0),
                            episode: i != 0)
                    }
                }
            } else if day.isPast {
                for f in day.airedToday {
                    add("past/\(day.id)/\(f.id)", .episode(f, day: day, aired: true, hero: false),
                        episode: true)
                }
            } else {
                for f in day.franchises {
                    add("sched/\(f.id)", .episode(f, day: day, aired: false, hero: false),
                        episode: true)
                }
            }
        }
        return rows
    }

    private var rail: some View {
        let rows = railRows
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                railRowView(row, fadeTop: idx == 0, fadeBottom: idx == rows.count - 1)
                    .id(row.id)
            }
            endcap
        }
    }

    @ViewBuilder
    private func railRowView(_ row: RailRow, fadeTop: Bool, fadeBottom: Bool) -> some View {
        switch row.kind {
        case .rule(let day):
            railRow(node: nil, fadeTop: fadeTop, fadeBottom: fadeBottom) { dayRule(day) }
                // Content-space frame: constant while scrolling, so this fires only when layout
                // actually changes. The scroll handler owns the per-frame focus math.
                .onGeometryChange(for: CGFloat.self) {
                    $0.frame(in: .named("railContent")).minY
                } action: { y in
                    ruleTracker.ys[day.id] = y
                }
        case .nowMarker:
            railRow(node: .nowTick, fadeTop: fadeTop, fadeBottom: fadeBottom) { nowLine }
        case .note(let text):
            railRow(node: nil, fadeTop: fadeTop, fadeBottom: fadeBottom) {
                Text(text)
                    .scaledFont(13)
                    .foregroundStyle(Theme.text26)
                    .padding(.vertical, 13)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .episode(let f, let day, let aired, let hero):
            // The ✓ node means WATCHED, not merely aired — an aired episode you haven't seen
            // keeps an accent ring (actionable, matching its check CTA in the row).
            let watched = f.releasingPart.map { $0.progress >= $0.airedEpisodes } ?? true
            railRow(node: aired ? (watched ? .done : .unwatched) : (hero ? .live : .ring),
                    fadeTop: fadeTop, fadeBottom: fadeBottom) {
                Group {
                    if hero {
                        heroCard(f, zoomID: row.id)
                    } else {
                        episodeRow(f, day: day, aired: aired, zoomID: row.id)
                    }
                }
                .overlay(alignment: .top) {
                    if row.divider { Rectangle().fill(Theme.hairline).frame(height: 1) }
                }
            }
        }
    }

    // MARK: rail scaffold — [gutter | content], node centred on the spine by construction

    private func railRow<Content: View>(node: RailNode?, fadeTop: Bool, fadeBottom: Bool,
                                        @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 8) {
            railGutter(node: node, fadeTop: fadeTop, fadeBottom: fadeBottom)
            content().frame(maxWidth: .infinity, alignment: .leading)
        }
        // Content decides the row height; the gutter (greedy) then stretches to match it.
        .fixedSize(horizontal: false, vertical: true)
    }

    private func railGutter(node: RailNode?, fadeTop: Bool, fadeBottom: Bool) -> some View {
        VStack(spacing: 0) {
            spineSegment(fadeUp: fadeTop)
            if let node {
                nodeView(node).padding(.vertical, 6)
            }
            spineSegment(fadeDown: fadeBottom)
        }
        .frame(width: gutterW)
        .frame(maxHeight: .infinity)
    }

    /// One flexible stretch of the spine. Both segments flex equally, which is what keeps the
    /// node vertically centred on the row.
    private func spineSegment(fadeUp: Bool = false, fadeDown: Bool = false) -> some View {
        Group {
            if fadeUp {
                LinearGradient(colors: [.clear, spineColor], startPoint: .top, endPoint: .bottom)
            } else if fadeDown {
                LinearGradient(colors: [spineColor, .clear], startPoint: .top, endPoint: .bottom)
            } else {
                spineColor
            }
        }
        .frame(width: 2)
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private func nodeView(_ node: RailNode) -> some View {
        switch node {
        case .ring:
            Circle()
                .strokeBorder(Color.white.opacity(0.38), lineWidth: 2)
                .frame(width: 10, height: 10)
        case .unwatched:
            // Aired but not yet watched — an accent ring: open like the future, warm like the CTA.
            Circle()
                .strokeBorder(Theme.accent.opacity(0.7), lineWidth: 2)
                .frame(width: 10, height: 10)
        case .done:
            ZStack {
                Circle().fill(Color(hex: 0x26211A))
                Image(systemName: "checkmark")
                    .scaledFont(7.5, weight: .bold)
                    .foregroundStyle(Theme.text50)
            }
            .frame(width: 17, height: 17)
        case .live:
            // The one ambient motion on the rail — a slow breath on a gradient halo, animated via
            // repeatForever scale/opacity (compositor-cheap; no per-frame shadow re-render, unlike
            // a TimelineView redrawing at 30fps). The dot itself never moves; Reduce Motion
            // freezes the glow at rest.
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Theme.accent.opacity(0.5), Theme.accent.opacity(0)],
                                         center: .center, startRadius: 1, endRadius: 13))
                    .frame(width: 26, height: 26)
                    .scaleEffect(livePulse ? 1.25 : 0.85)
                    .opacity(livePulse ? 1 : 0.6)
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 11, height: 11)
                    .shadow(color: Theme.accent.opacity(0.7), radius: 5)
            }
            .frame(width: 11, height: 11)   // layout footprint stays the dot; the halo overflows
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    livePulse = true
                }
            }
        case .nowTick:
            Circle()
                .fill(Theme.accent)
                .frame(width: 7, height: 7)
                .shadow(color: Theme.accent.opacity(0.8), radius: 5)
        }
    }

    // MARK: day rule — quiet, functional

    private func dayRule(_ day: AppModel.ScheduleDay) -> some View {
        let count = day.franchises.count + day.airedToday.count
        let accent = day.isToday
        return HStack(spacing: 10) {
            Text(ruleLabel(day))
                .scaledFont(10.5, weight: .bold, monospacedDigit: true)
                .tracking(1.6)
                .foregroundStyle(accent ? Theme.accent : (day.isPast ? Theme.text40 : Theme.text52))
                .fixedSize()
            Rectangle()
                .fill(accent ? Theme.accent.opacity(0.25) : Theme.hairline)
                .frame(height: 1)
            if count > 0 {
                Text(count == 1 ? "1 EP" : "\(count) EPS")
                    .scaledFont(10, weight: .medium, monospacedDigit: true)
                    .tracking(0.6)
                    .foregroundStyle(accent ? Theme.accent.opacity(0.8) : Theme.text36)
                    .fixedSize()
            }
        }
        .padding(.top, 24)
        .padding(.bottom, 7)
    }

    private func ruleLabel(_ day: AppModel.ScheduleDay) -> String {
        let wd = day.label.prefix(3).uppercased()
        let date = day.dateLabel.uppercased()
        return day.isToday ? "TODAY · \(wd) \(date)" : "\(wd) · \(date)"
    }

    // MARK: NOW marker

    private var nowLine: some View {
        HStack(spacing: 9) {
            Text("NOW")
                .scaledFont(9, weight: .bold)
                .tracking(1.4)
                .foregroundStyle(Theme.accent)
            LinearGradient(colors: [Theme.accent.opacity(0.55), Theme.accent.opacity(0.04)],
                           startPoint: .leading, endPoint: .trailing)
                .frame(height: 1)
            Text(Formatting.fmtTime(now))
                .scaledFont(9, weight: .semibold, monospacedDigit: true)
                .tracking(0.8)
                .foregroundStyle(Theme.accent.opacity(0.65))
        }
        .frame(height: 26)
    }

    // MARK: episode row — fixed anatomy, aligned trailing column

    /// Deep-link target for a row: the releasing season, at the episode the row is about — the
    /// one that aired that day, or the next one to air.
    private func episodeFocus(_ f: Franchise, aired: Bool) -> EpisodeFocus? {
        guard let part = f.releasingPart else { return nil }
        let ep = aired ? part.airedEpisodes : (part.nextEpisodeNumber ?? part.airedEpisodes + 1)
        return ep > 0 ? EpisodeFocus(mediaId: part.mediaId, episode: ep) : nil
    }

    private func episodeRow(_ f: Franchise, day: AppModel.ScheduleDay, aired: Bool,
                            zoomID: String) -> some View {
        let vm = CardModel(franchise: f, action: .none, now: now)
        // An aired episode you haven't watched is actionable — it keeps a check CTA and most of
        // its ink; only watched history fully recedes.
        let watched = f.releasingPart.map { $0.progress >= $0.airedEpisodes } ?? true
        return Button {
            onOpenDetail(f.id, zoomID, episodeFocus(f, aired: aired))
        } label: {
            HStack(spacing: 13) {
                Thumb(cover: vm.cover, width: 52, height: 70, radius: 8)
                VStack(alignment: .leading, spacing: 5) {
                    Text(vm.title)
                        .scaledFont(15.5, weight: .semibold)
                        .tracking(-0.25)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(Theme.textPrimary)
                    HStack(spacing: 6) {
                        SourceGlyph(source: vm.source, size: 11)
                        metaText(vm, aired: aired)
                            .scaledFont(11.5, weight: .medium, monospacedDigit: true)
                            .tracking(0.4)
                            .foregroundStyle(Theme.text50)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                trailingColumn(vm, f: f, day: day, aired: aired, watched: watched)
                    .frame(width: trailW, alignment: .trailing)
            }
            .padding(.vertical, 11)
            .contentShape(Rectangle())
            // Watched history recedes; an unwatched aired episode stays near full strength so its
            // check CTA reads as live. The node stays full-strength on the spine either way.
            .opacity(aired ? (watched ? 0.45 : 0.9) : 1)
        }
        .buttonStyle(SpringPressButtonStyle(scale: 0.98))
        .zoomSource(zoomID)
        .contextMenu { FranchiseContextMenu(f: f, appModel: appModel) }
    }

    // Metadata line: anime → "Ep 12"; TV → "Season 2 · Ep 7", or "Season 2 · 8 episodes" for a drop.
    private func metaText(_ vm: CardModel, aired: Bool) -> Text {
        let season = (vm.source == .tmdb && !vm.partLabel.isEmpty) ? "\(vm.partLabel) · " : ""
        if aired { return Text("\(season)Ep \(vm.airedEpisodes)") }
        if vm.source == .tmdb && vm.nextAiringCount > 1 {
            return Text("\(season)\(vm.nextAiringCount) episodes")
        }
        return Text("\(season)Ep \(vm.nextEp.map(String.init) ?? "?")")
    }

    @ViewBuilder
    private func trailingColumn(_ vm: CardModel, f: Franchise, day: AppModel.ScheduleDay,
                                aired: Bool, watched: Bool = true) -> some View {
        if aired {
            if !watched {
                // Mark this aired episode watched (catch-up through it) without leaving the rail.
                MarkCaughtUpCircle { appModel.markCaughtUp(f.id) }
            } else {
                // Anime carries the real clock time it aired at; TV's instant is synthesized, so
                // the eyebrow stands alone.
                VStack(alignment: .trailing, spacing: 2) {
                    Text("AIRED")
                        .scaledFont(9, weight: .semibold)
                        .tracking(1)
                        .foregroundStyle(Theme.text28)
                    if vm.source == .anilist, let last = f.releasingPart?.lastAiredAt {
                        Text(Formatting.fmtTime(last))
                            .scaledFont(14, weight: .medium, monospacedDigit: true)
                            .foregroundStyle(Theme.text62)
                    }
                }
            }
        } else if vm.source == .tmdb {
            tvLabel(vm)
        } else if day.isToday {
            AirtimeStack(clock: vm.airTime,
                         countdown: vm.countdown == "now" ? "now" : "in \(vm.countdown)")
        } else {
            AirtimeStack(clock: vm.airTime, countdown: nil)
        }
    }

    // TV airing label — Season drop (same-day multi-episode release, from the server's
    // `nextAiringCount`) / Finale (last episode) / Premiere (first) / New episode.
    private func tvLabel(_ vm: CardModel) -> ScheduleTVLabel {
        if vm.nextAiringCount > 1 { return ScheduleTVLabel(text: "Season drop", accent: true) }
        let total = vm.totalEpisodes
        let n = vm.nextEp ?? 0
        if total > 0 && n == total { return ScheduleTVLabel(text: "Finale", dot: true) }
        if n == 1 { return ScheduleTVLabel(text: "Premiere", accent: true) }
        return ScheduleTVLabel(text: "New episode")
    }

    // MARK: hero card — the next episode today, banner treatment on the live node

    private func heroCard(_ f: Franchise, zoomID: String) -> some View {
        let vm = CardModel(franchise: f, action: .none, now: now)
        // No landscape banner → don't crop the portrait cover to fill; use it as an ambient
        // blurred wash and float the sharp poster inside the card instead.
        let hasBanner = f.banner != nil
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return Button {
            onOpenDetail(f.id, zoomID, episodeFocus(f, aired: false))
        } label: {
            ZStack(alignment: .leading) {
                if hasBanner {
                    RemoteImageView(url: vm.banner, maxPixel: 1100)
                        .frame(height: 118)
                        .frame(maxWidth: .infinity)
                        .clipped()
                    LinearGradient(stops: [
                        .init(color: Color(hex: 0x100D09).opacity(0.94), location: 0),
                        .init(color: Color(hex: 0x100D09).opacity(0.60), location: 0.44),
                        .init(color: Color(hex: 0x100D09).opacity(0.15), location: 1),
                    ], startPoint: .leading, endPoint: .trailing)
                } else {
                    RemoteImageView(url: vm.cover, maxPixel: 500)
                        .frame(height: 118)
                        .frame(maxWidth: .infinity)
                        .scaleEffect(1.2)
                        .blur(radius: 26)
                        .overlay(Color(hex: 0x100D09).opacity(0.58))
                        // Flatten the live Gaussian blur into one rasterized layer so scrolling
                        // composites a texture instead of re-evaluating the filter.
                        .drawingGroup()
                }
                HStack(spacing: 12) {
                    if !hasBanner {
                        Thumb(cover: vm.cover, width: 58, height: 82, radius: 8)
                            .shadow(color: .black.opacity(0.5), radius: 8, y: 4)
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text(vm.title)
                            .scaledFont(18, weight: .bold)
                            .tracking(-0.4)
                            .lineLimit(1)
                            .foregroundStyle(Theme.textPrimary)
                            .shadow(color: .black.opacity(0.55), radius: 10, y: 1)
                        metaText(vm, aired: false)
                            .scaledFont(10, weight: .medium, monospacedDigit: true)
                            .tracking(0.8)
                            .foregroundStyle(Theme.text72)
                        if vm.source == .anilist && !vm.countdown.isEmpty {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Theme.accent)
                                    .frame(width: 5, height: 5)
                                    .shadow(color: Theme.accent, radius: 4)
                                Text(vm.countdown == "now" ? "OUT NOW" : "IN \(vm.countdown.uppercased())")
                                    .scaledFont(9.5, weight: .bold, monospacedDigit: true)
                                    .tracking(1.2)
                                    .foregroundStyle(Theme.accent)
                            }
                            .padding(.top, 3)
                        }
                    }
                    Spacer(minLength: 8)
                    heroTrailing(vm, f: f)
                        .frame(width: trailW, alignment: .trailing)
                }
                .padding(.horizontal, 16)
            }
            .frame(height: 118)
            .clipShape(shape)
            .overlay(shape.stroke(Theme.accent.opacity(0.30), lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 20, y: 9)
            .contentShape(shape)
        }
        .buttonStyle(SpringPressButtonStyle(scale: 0.985))
        .zoomSource(zoomID)
        .contextMenu { FranchiseContextMenu(f: f, appModel: appModel) }
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func heroTrailing(_ vm: CardModel, f: Franchise) -> some View {
        if vm.source == .tmdb {
            tvLabel(vm)
        } else {
            VStack(alignment: .trailing, spacing: 2) {
                Text(heroEyebrow(f))
                    .scaledFont(9, weight: .bold)
                    .tracking(1.2)
                    .foregroundStyle(Theme.text50)
                Text(vm.airTime)
                    .scaledFont(20, weight: .bold, monospacedDigit: true)
                    .tracking(-0.3)
                    .foregroundStyle(Theme.textPrimary)
            }
            .shadow(color: .black.opacity(0.6), radius: 10, y: 1)
        }
    }

    /// "TONIGHT" when the episode airs in the evening, "TODAY" before that — keyed to the
    /// episode's air hour, not the current clock.
    private func heroEyebrow(_ f: Franchise) -> String {
        guard let next = f.releasingPart?.nextAiringAt else { return "TODAY" }
        return Formatting.localParts(next).hour >= 17 ? "TONIGHT" : "TODAY"
    }

    // MARK: endcap

    private var endcap: some View {
        Text("NOTHING ELSE SCHEDULED")
            .scaledFont(9.5, weight: .medium)
            .tracking(1.6)
            .foregroundStyle(Theme.text26)
            .frame(maxWidth: .infinity)
            .padding(.top, 32)
    }
}
