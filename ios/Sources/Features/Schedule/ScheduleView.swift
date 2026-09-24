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
    /// Immediate visual state for the bottom-right toggle. Real writes update the model
    /// optimistically; this also lets the DEBUG three-state fixture be interacted with without
    /// changing the account it is derived from.
    @State private var watchedOverrides: [String: Bool] = [:]
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
        static let rowGap: CGFloat = ThemeSpace.x5
        /// The app's gutter: 20 here made the left edge jump 4 pt on every tab switch (review i3).
        static let horizontalInset: CGFloat = ThemeMetrics.gutter
        /// Date heading to its first artwork card.
        static let headingGap: CGFloat = 14
        /// How far past today a Later date may be, in days: the heading prints no year.
        static let laterReach = 365
    }

    /// The artwork the wash is derived from: the next thing to air, else the most recent thing
    /// that did, else whatever the library leads with.
    private var washCover: String? {
        let d = derived
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
        /// Past the window: each show's next dated airing, one row per show (`laterRows`), filtered.
        var later: [Row] = []
        /// The Later rows per day offset, for the month grid.
        var laterCounts: [Int: Int] = [:]
        var allEmpty = true
        var shownEmpty = true
        var feedKey: [Int] = []
        /// `-scheduleDemoStates 1`: the id of the one aired row drawn as UNWATCHED, so the three
        /// states can be photographed together. The test account has none of its own — both past
        /// airings are watched — and a ladder cannot be judged with a rung missing.
        var demoUnwatched: String? = nil
        /// ...and one drawn WATCHED, so the third rung shows even when every aired row is unwatched
        /// (review i4: capture 12 was capture 10 again).
        var demoWatched: String? = nil
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
        let later = laterRows(after: raw)
        out.later = later.filter(passes)
        // The Later group's days answer on the calendar too — known, dotted, and a tap lands on
        // the card (`laterGroup` gives each day's first card the day's scroll id).
        for r in out.later {
            let d = laterDay(r)
            out.laterCounts[d, default: 0] += 1
        }
        out.allEmpty = all.allSatisfy(\.isEmpty) && later.isEmpty
        out.shownEmpty = shown.allSatisfy(\.isEmpty) && out.later.isEmpty
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
        out.feedKey = (out.earlier + out.ahead).map { $0.id * 1000 + $0.count } + [1_000_000 + out.later.count]
        if ScheduleDebug.demoStates {
            // The two most recent aired rows, so both sit near the landing: the last unwatched,
            // the one before it watched.
            let rows = out.earlier.flatMap(\.rows)
            out.demoUnwatched = rows.last?.id
            out.demoWatched = rows.dropLast().last?.id
        }
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

    /// LATER — each tracked show's next dated airing past the window, one row per show, for the
    /// shows the window goes quiet on: nothing still to come inside it. Bleach's Episode 8 aired
    /// on the 18th and Episode 9 is not until 19 Oct, and the feed could not say so — it ended on
    /// the break. A show with something still ahead inside the window is left out: its next
    /// episode past the edge would be the same show again, a week on, and this is a list of shows,
    /// not episodes. Every part is walked, as `buildScheduleDays` walks them, so a season whose
    /// dated premiere lies past the window has its row. No new data: the catalogue's own next slot
    /// is the one fact that reaches past the server's `airings`.
    private func laterRows(after raw: [AppModel.ScheduleDay]) -> [Row] {
        let todayKey = Formatting.localDayKey(appModel.scheduleTodayNoon)
        let waiting = Set(raw.flatMap(\.entries).filter { !$0.aired }.map(\.franchise.id))
        var out: [Row] = []
        // A PLANNED show contributes its dated premiere too — the one date a bookmark carries,
        // and the one its premiere alert fires for (iteration 2: the alert rang for a Seven Havens
        // premiere the calendar never showed). Only the premiere: Planned is not a weekly habit.
        for f in appModel.library where (f.tracksAirings || f.effectiveStatus == .planned) && !waiting.contains(f.id) {
            let planned = !f.tracksAirings
            var best: (part: FranchisePart, slot: Airing)?
            for part in f.parts where !planned || part.isUpcoming {
                for slot in knownSlots(of: part) where !planned || slot.episode == 1 {
                    let offset = Int((f.dayKey(of: slot.at) - todayKey) / Formatting.D)
                    guard offset > AppModel.scheduleAhead, offset < Metrics.laterReach else { continue }
                    // The soonest, and the lowest episode of a drop that shares its instant.
                    if let b = best, (b.slot.at, b.slot.episode) <= (slot.at, slot.episode) { continue }
                    best = (part, slot)
                }
            }
            guard let best else { continue }
            out.append(Row(franchise: f, part: best.part, episodes: best.slot.episode...best.slot.episode,
                           at: best.slot.at, aired: false, dateOnly: f.timeAnchor.isDateOnly))
        }
        return out.sorted { $0.at != $1.at ? $0.at < $1.at : $0.franchise.title < $1.franchise.title }
    }

    /// Every dated slot the app holds for a part: the calendar's (`scheduleAirings` — the server's
    /// `airings`, which reach 15 days ahead), plus the catalogue's own next slot, the one fact past
    /// them (AniList's next broadcast after a cour break, TMDB's next air date). That slot counts
    /// only with its episode known, by `scheduleAirings`' own rule: a dated season announcement is
    /// not automatically Episode 1.
    private func knownSlots(of part: FranchisePart) -> [Airing] {
        var out = part.scheduleAirings
        guard let next = part.nextAiringAt, next > 0 else { return out }
        let ep = part.nextEpisodeNumber ?? (part.isReleasing && part.airedEpisodes > 0 ? part.airedEpisodes + 1 : 0)
        if ep > 0, !out.contains(where: { $0.episode == ep }) { out.append(Airing(episode: ep, at: next)) }
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
                // The Later group's ids reach past the window; the rail stays on the window's
                // own weeks rather than turning to a week of disabled days.
                readingDay = min(day, AppModel.scheduleAhead)
            }
            // The calendar OVERLAYS the feed (Google Calendar's month dropdown), it does not push
            // it: 500 pt of grid inserted above a lazy stack threw the reader's place three
            // screens down and back again on every toggle. Last in the stack, so it is above the
            // feed; it hangs from the chrome band's bottom edge, so it reads as coming out of the
            // bar.
            calendarOverlay(proxy)
            }
        // The calendar owns an opaque neutral top band so scrolling artwork cannot show
        // through its date numerals or navigation title. The bottom edge remains shared.
        .scrollEdgeChromeBody(top: false, bottom: true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .chromeScrollEdgeHidden(.top)
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
            // The way back when TODAY is not on the rail — the rail shows the week you are
            // reading, so on a Later landing ("SUN 18…SAT 24" of October) there was no today cell
            // and nothing else to tap (review i4, N9). Ink, not amber: a command.
            if todayOffRail {
                ToolbarItem(placement: .topBarLeading) {
                    Button(Copy.Schedule.today) { goToToday(proxy) }
                        .tint(ThemeColor.interactive)
                        .accessibilityLabel(Copy.Schedule.scrollToToday)
                        .accessibilityHint(Copy.Schedule.scrollToTodayHint)
                }
            }
        }
        // An alert, not a popover pinned under the bar 180 pt from the ring (interactive review):
        // a batch changes a number the user did not type, and it always offers Cancel.
        .alert(prompt?.title ?? "", isPresented: Binding(get: { prompt != nil }, set: { if !$0 { prompt = nil } }),
               presenting: prompt) { p in
            if p.destructive {
                Button(p.confirm, role: .destructive) { p.perform() }
            } else {
                Button(p.confirm) { p.perform() }
            }
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

    /// Today is outside the week the rail is showing.
    private var todayOffRail: Bool {
        let noon = appModel.scheduleTodayNoon + Int64(selectedDay) * Formatting.D
        let start = selectedDay - Formatting.localParts(noon).wd
        return !(start...(start + 6)).contains(0)
    }

    // MARK: - Scrolling

    /// The feed opens on today's section, un-animated, with the past above it and the ticker's
    /// first visible cell today. True on a day with nothing on it too, since an empty today still
    /// renders: the agenda always opens where the reader is standing. (It used to open on a
    /// folded "Earlier" row with today under it; the fold is gone.)
    private func land(_ proxy: ScrollViewProxy) {
        guard !userScrolled, !appModel.library.isEmpty, !showsWholeScreenState else { return }
        var t = Transaction()
        t.disablesAnimations = true
        // Today is the stable opening anchor even when it carries no releases. Empty dates draw no
        // explanatory row; the next dated group simply begins beneath this zero-height position.
        // An EMPTY today with yesterday's drop still unwatched lands on yesterday (the 5 Sep
        // interactive pass's rule, lost in the 20 Sep restore): at 00:03 the feed opened on
        // "TOMORROW" with Re:ZERO's episode — aired five hours earlier, unwatched — scrolled away
        // above it (review i3).
        let yesterdayDrop: Int? = {
            let d = derived
            guard d.ahead.first(where: { $0.id == 0 })?.isEmpty ?? true,
                  let yesterday = d.earlier.first(where: { $0.id == -1 }),
                  yesterday.rows.contains(where: { ($0.aired && !$0.watched) || $0.id == d.demoUnwatched })
            else { return nil }
            return -1
        }()
        // `-scheduleDemoStates`: land on the day of the row drawn WATCHED, so the capture holds
        // all three rungs (the watched one sat above the landing, review i4/i5).
        let demoDay: Int? = ScheduleDebug.demoStates
            ? derived.earlier.first(where: { d in d.rows.contains { $0.id == derived.demoWatched } })?.id : nil
        let target = ScheduleDebug.captureDay.flatMap { day in
            derived.all.contains(where: { $0.id == day }) || derived.laterCounts[day] != nil ? day : nil
        } ?? demoDay ?? yesterdayDrop ?? 0
        withTransaction(t) { proxy.scrollTo(AgendaID.day(target), anchor: .top) }
        // Landing on yesterday's drop still STANDS on today: the rail keeps Thursday and no
        // "Today" button appears on the screen's first frame (review i3).
        let standing = yesterdayDrop != nil && target == -1 ? 0 : target
        if selectedDay != standing { selectedDay = standing }
        readingDay = standing
        // The calendar opens on the month the feed landed in (a Later landing opened the grid on
        // September — review i4's capture 42).
        monthAnchor = standing
    }

    /// A strip tap: the feed lands on that day's section. A day with nothing on it gets one drawn
    /// for the purpose (`pinnedEmptyDay`) a beat before the scroll, so there is a section to land on.
    private func pick(_ offset: Int, count: Int, proxy: ScrollViewProxy) {
        // A LATER day is never pinned as an empty section: its card already carries the day's
        // scroll id, and a pinned twin took the id from it — the grid's 19 Oct landed on a bare
        // "LATER" label and the card vanished (review i5, F10). The merged counts at the call
        // sites say it is not empty; this guards any caller that forgets.
        if count == 0 && offset != 0 && derived.laterCounts[offset] == nil {
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
        scroll(to: .day(0), day: 0, proxy: proxy)
    }

    // MARK: - The calendar

    /// The grid, a scrim, and the rules for getting out of it. Mounted only while it is down —
    /// a held-at-zero-opacity overlay over a scrolling feed is a composited layer per frame.
    @ViewBuilder
    private func calendarOverlay(_ proxy: ScrollViewProxy) -> some View {
        if monthOpen {
            ZStack(alignment: .top) {
                // Anywhere off the grid closes it, as a menu does. The feed under it steps BACK
                // (0.32): undimmed, the card under the panel's foot peeked out as a second edge
                // beneath it (review i3/i4, U3-N21) and the panel did not read as the layer on top.
                // Light enough that the day the grid is about to take you to still reads.
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { toggleCalendar() }
                    .accessibilityHidden(true)
                    .transition(.opacity)
                ScheduleMonthGrid(todayNoon: appModel.scheduleTodayNoon,
                                  counts: derived.counts.merging(derived.laterCounts) { a, _ in a },
                                  live: derived.live.union(derived.laterCounts.keys), selected: selectedDay,
                                  window: AppModel.scheduleBack...AppModel.scheduleAhead,
                                  extraDays: Set(derived.laterCounts.keys),
                                  monthAnchor: $monthAnchor,
                                  maxHeight: max(260, viewportH - ThemeMetrics.tabBarClearance)) { day in
                    // A pick closes the calendar. Leaving it down over the day it just took you to
                    // means the answer is hidden behind the question.
                    toggleCalendar()
                    pick(day, count: derived.counts[day] ?? derived.laterCounts[day] ?? 0, proxy: proxy)
                }
                // GLASS over the feed, not a flat grey slab: the panel is chrome that floats,
                // which is what every other floating surface in the app is made of, and #242428
                // filling a third of the screen read as a debug view. The canvas veil under the
                // material is what keeps the numerals legible over busy art — the same pairing
                // the bars use (`chromeBarOpacity`).
                // 0.74, the hardened bar's (`chromeBarOpacity`): at 0.62 the feed's art showed
                // through the weeks as colour blobs (review i3).
                .background(ThemeColor.canvas.opacity(ThemeMetrics.chromeBarOpacity),
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
            if !tickerCollapsed {
                ScheduleWeekRail(todayNoon: appModel.scheduleTodayNoon,
                                 selected: selectedDay,
                                 counts: derived.counts.merging(derived.laterCounts) { a, _ in a },
                                 live: derived.live.union(derived.laterCounts.keys),
                                 window: AppModel.scheduleBack...AppModel.scheduleAhead,
                                 extraDays: Set(derived.laterCounts.keys)) { offset in
                    pick(offset, count: derived.counts[offset] ?? derived.laterCounts[offset] ?? 0, proxy: proxy)
                }
                .transition(.opacity)
            }
            filterChips
        }
        // Only the filter chips can give this band height, so only they earn its padding.
        .padding(.bottom, filterActive ? ThemeSpace.x2 : 0)
        .animation(ThemeMotion.pick(ThemeMotion.uiGentle, reduceMotion: reduceMotion), value: filterActive)
        // The band's ground is THE WASH, over opaque canvas and sized to end at the band's own
        // bottom edge (its last stop IS canvas, so there is no seam) — the root spec every tab
        // carries. Drawn at a STATED height, bottom-aligned, so a short band never lets the feed
        // print through the status bar (6 Sep).
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
                                        withAnimation(ThemeMotion.pick(ThemeMotion.uiSnappy, reduceMotion: reduceMotion)) {
                            typeFilter = .all; unwatchedOnly = false
                        }
                    })
                }
            } else {
                // The past, then today (always), then what is ahead — one agenda, no fold. The
                // feed lands on today (`land`); the calendar's dimmed cells are the way back.
                ForEach(daysToDraw(d)) { day in dateColumnDay(day) }
                laterGroup(d.later)
            }
        }
    }

    /// The feed's loading state at THIS screen's geometry — three day blocks in the airing card's
    /// anatomy (header, 16:9 art, title, meta), so the swap lands in place. It drew poster rows
    /// until 3 Sep, the row the calendar stopped using.
    private var feedSkeleton: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<2, id: \.self) { _ in
                SkeletonLine(width: 126, height: 14)
                    .padding(.top, ThemeSpace.x8)
                    .padding(.bottom, Metrics.headingGap)
                SkeletonBlock(height: nil, radius: 18)
                    .aspectRatio(2.04, contentMode: .fit)
            }
        }
        .padding(.horizontal, Metrics.horizontalInset)
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

    /// The first day drawn in the feed.
    private func isFirstDay(_ day: Day) -> Bool {
        (derived.earlier + derived.ahead).first?.id == day.id
    }

    // MARK: - Row

    /// Everything a row needs, whatever anatomy draws it — computed once, so the four shapes
    /// cannot disagree about a row's state the way the pre-6-Sep card's three corners did.
    private struct RowFacts {
        let state: AiringState
        let time: String?
        let hasReminder: Bool
        let zoom: String
        /// The show is in the library and the episode has aired, so the bottom-right control can
        /// toggle the progress in either direction.
        let canToggle: Bool
    }

    private func facts(_ r: Row) -> RowFacts {
        let f = r.franchise
        // `-scheduleDemoStates`: one aired row is drawn as though it were still waiting, so the
        // ladder can be photographed with all three rungs.
        let demoUnseen = derived.demoUnwatched == r.id
        let demoSeen = derived.demoWatched == r.id
        let watched = watchedOverrides[r.id] ?? ((r.watched || demoSeen) && !demoUnseen)
        return RowFacts(state: !r.aired ? .upcoming : (watched ? .watched : .toWatch),
                        time: r.dateOnly ? nil : Formatting.fmtTime(r.at, anchor: f.timeAnchor),
                        hasReminder: !r.aired && ScheduleReminders.shared.has(mediaId: r.part.mediaId,
                                                                             episode: r.episode),
                        zoom: "sched/\(f.id)/\(r.episode)",
                        canToggle: r.aired && appModel.isInLibrary(f.id))
    }

    private func openAction(_ r: Row, _ x: RowFacts) -> () -> Void {
        { onOpenDetail(r.franchise.id, x.zoom,
                       EpisodeFocus(mediaId: r.part.mediaId, episode: r.episode)) }
    }

    // MARK: - The feed

    /// A date group is a heading followed by generous, full-width artwork. Empty dates remain
    /// scroll anchors for the calendar but draw no explanatory row.
    @ViewBuilder
    private func dateColumnDay(_ day: Day) -> some View {
        if day.isEmpty {
            Color.clear
                .frame(height: 1)
                .id(AgendaID.day(day.id))
                .accessibilityHidden(true)
        } else {
            VStack(alignment: .leading, spacing: Metrics.headingGap) {
                ScheduleDayHeading(relative: relativeDay(day),
                                   weekday: shortWeekday(day),
                                   numeral: dayNumeral(day))
                ForEach(Array(day.rows.enumerated()), id: \.element.id) { index, row in
                    dateRow(row, day: day)
                        .padding(.top, index == 0 ? 0 : Metrics.rowGap - Metrics.headingGap)
                }
            }
            .padding(.horizontal, Metrics.horizontalInset)
            .padding(.top, ThemeSpace.x8)
            .id(AgendaID.day(day.id))
        }
    }

    private func dateRow(_ r: Row, day: Day) -> some View {
        let f = r.franchise
        let x = facts(r)
        return ScheduleAiringCard(title: f.displayTitle,
                                  episodeText: episodeText(r),
                                  time: x.time,
                                  timeIsLead: !r.aired,
                                  art: f.wideArt,
                                  poster: f.portraitArt,
                                  name: f.sceneName,
                                  hasReminder: x.hasReminder,
                                  zoomID: x.zoom,
                                  trailing: {
                                      if x.canToggle {
                                          ScheduleWatchToggle(watched: x.state.isWatched,
                                                              title: f.title,
                                                              episode: r.episode) {
                                              toggleWatched(r, watched: x.state.isWatched)
                                          }
                                      }
                                  },
                                  action: openAction(r, x))
            .franchiseQuickActions(appModel.isInLibrary(f.id) ? f : nil, appModel: appModel)
            .animation(ThemeMotion.pick(ThemeMotion.uiMicro, reduceMotion: reduceMotion), value: x.state.isWatched)
            .id(AgendaID.row(day.id, r.id))
    }

    /// LATER — past the window, each show's next dated airing (or a Planned show's premiere), in
    /// the feed's own grammar: a date heading over its artwork card. Each card is a DIRECT child
    /// of the lazy feed with its day's id, so the month grid can land on it (review i3: the grid
    /// greyed out 19 Oct while this group listed Bleach on it; nested in one block, the ids were
    /// not scroll targets).
    @ViewBuilder
    private func laterGroup(_ rows: [Row]) -> some View {
        if !rows.isEmpty {
            SectionLabel(text: Copy.Schedule.later)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, ThemeSpace.x8)
                .padding(.horizontal, Metrics.horizontalInset)
            ForEach(Array(rows.enumerated()), id: \.element.id) { i, r in
                let p = Formatting.localParts(r.at, anchor: r.franchise.timeAnchor)
                let day = laterDay(r)
                let firstOfDay = i == 0 || laterDay(rows[i - 1]) != day
                VStack(alignment: .leading, spacing: Metrics.headingGap) {
                    ScheduleDayHeading(relative: nil,
                                       weekday: Formatting.weekdayShort(p.wd),
                                       numeral: "\(p.d) \(monthShort(p.mo))")
                    laterCard(r)
                }
                .padding(.top, ThemeSpace.x6)
                .padding(.horizontal, Metrics.horizontalInset)
                .id(firstOfDay ? AgendaID.day(day) : AgendaID.row(day, r.id))
            }
        }
    }

    /// A Later row's day, as an offset from today in its own calendar — the grid's key.
    private func laterDay(_ r: Row) -> Int {
        Formatting.dayDiff(ts: r.at, now: appModel.now, anchor: r.franchise.timeAnchor)
    }

    private func laterCard(_ r: Row) -> some View {
        let f = r.franchise
        let x = facts(r)
        return ScheduleAiringCard(title: f.displayTitle,
                                  episodeText: episodeText(r),
                                  time: x.time,
                                  timeIsLead: true,
                                  art: f.wideArt,
                                  poster: f.portraitArt,
                                  name: f.sceneName,
                                  hasReminder: x.hasReminder,
                                  zoomID: x.zoom,
                                  trailing: { EmptyView() },
                                  action: openAction(r, x))
            .franchiseQuickActions(appModel.isInLibrary(f.id) ? f : nil, appModel: appModel)
    }

    /// Built once: a `DateFormatter` per heading per render was the cost of every scroll frame
    /// that re-evaluated the feed.
    private static let monthSymbols = DateFormatter().shortMonthSymbols ?? []

    private func monthShort(_ month: Int) -> String {
        let symbols = Self.monthSymbols
        return symbols.indices.contains(month - 1) ? symbols[month - 1].uppercased() : ""
    }

    private func relativeDay(_ day: Day) -> String? {
        switch day.id {
        case -1: "YESTERDAY"
        case 0: "TODAY"
        case 1: "TOMORROW"
        default: nil
        }
    }

    private func shortWeekday(_ day: Day) -> String {
        Formatting.weekdayShortMonFirst(Formatting.localMondayCol(day.noon))
    }

    /// "3", or "3 OCT" in a month other than today's — the feed crossed from "WED 30" to "SAT 3"
    /// with nothing saying October had begun (review i3; Later's headings already say it).
    private func dayNumeral(_ day: Day) -> String {
        let p = Formatting.localParts(day.noon)
        let today = Formatting.localParts(appModel.now)
        return p.mo == today.mo ? "\(p.d)" : "\(p.d) \(monthShort(p.mo))"
    }

    // MARK: - What the row says

    /// What actually VARIES down the feed, with the season dropped. A weekly show cannot leave its
    /// season inside a 22-day window, so on this screen "Season 4" is a constant printed once per
    /// row — the biggest single contributor to the run-on grammar the spike is testing against.
    private func episodeText(_ r: Row) -> String {
        let n = r.episodes.count
        let count = n > 1 ? Copy.episodes(n) : nil
        if r.part.kind == .movie || r.episodes.lowerBound == 1 {
            return [Copy.Schedule.premiere(premiereName(r)), count].compactMap { $0 }.joined(separator: " \u{00B7} ")
        }
        // The card's compact notation (20 Sep): "E18", "E3–E5" — the artwork carries the show,
        // the line is a label on it. A premiere and another part still say what they are.
        guard namesPart(r) else {
            return r.episodes.count == 1 ? "E\(r.episode)" : "E\(r.episodes.lowerBound)\u{2013}E\(r.episodes.upperBound)"
        }
        guard let count else { return r.franchise.watchContext(part: r.part, episode: r.episode) }
        let label = Copy.compactPartLabel(r.part.canonicalLabel)
        return label.isEmpty ? count : "\(label) \u{00B7} \(count)"
    }

    /// The row is from a part other than the one the user is in: an EXTRA airing beside the show (a
    /// spin-off, a side story, a special — off the story's spine), or a season other than the
    /// furthest one their progress has reached (Season 4 airing over a Season 3 backlog, or a new
    /// season not yet started). The furthest part with progress, not `resumePart`: one half-watched
    /// older season steers that, and would put the season back on every ordinary row of the one
    /// airing. A user with no progress at all is following what airs, so the airing part is theirs.
    private func namesPart(_ r: Row) -> Bool {
        let f = r.franchise
        guard f.parts.count > 1 else { return false }
        let spine = f.mainStoryEpisodicParts
        guard spine.contains(where: { $0.mediaId == r.part.mediaId }) else { return true }
        guard let current = spine.last(where: { $0.progress > 0 }) else { return false }
        return current.mediaId != r.part.mediaId
    }

    /// The part as its premiere names it: a film by its title; a season by its own compacted label
    /// ("Season 5: Hashira Training Arc" → "Season 5"); nothing on a show of one part, whose title
    /// on the row says it — the rule `Franchise.watchContext` follows.
    private func premiereName(_ r: Row) -> String {
        if r.part.kind == .movie { return r.part.canonicalLabel }
        return r.franchise.parts.count > 1 ? Copy.compactPartLabel(r.part.canonicalLabel) : ""
    }

    // MARK: - Watched toggle (the only write)

    private func toggleWatched(_ r: Row, watched: Bool) {
        let part = r.part
        if watched {
            let target = max(0, r.episodes.lowerBound - 1)
            let count = max(1, part.progress - target)
            if count > 1 {
                prompt = .init(title: "Mark \(Copy.episodes(count)) as unwatched?",
                               message: Copy.Confirm.batchMarkMessage(from: part.progress, to: target),
                               confirm: "Mark \(Copy.episodes(count)) as unwatched",
                               destructive: true) {
                    setProgress(r, to: target, watched: false)
                }
            } else {
                setProgress(r, to: target, watched: false)
            }
            return
        }

        let target = r.episodes.upperBound
        let count = target - part.progress
        // The DEBUG state fixture may draw an already-watched row as waiting. Let its control
        // animate for visual QA, but do not send a no-op account write.
        if count <= 0 {
            withAnimation(ThemeMotion.pick(ThemeMotion.uiMicro, reduceMotion: reduceMotion)) {
                watchedOverrides[r.id] = true
            }
        } else if count > 1 {
            prompt = .init(title: Copy.Confirm.batchMarkTitle(count),
                           message: Copy.Confirm.batchMarkMessage(from: part.progress, to: target),
                           confirm: Copy.Confirm.batchMarkConfirm(count)) {
                setProgress(r, to: target, watched: true)
            }
        } else {
            setProgress(r, to: target, watched: true)
        }
    }

    /// The control itself is the receipt: it fills or opens in place. No second success line is
    /// inserted under the card, and no redundant success toast competes with the next release.
    private func setProgress(_ r: Row, to target: Int, watched: Bool) {
        // A mark on a show filed Watched (a new season on the calendar) watches it again
        // (`AppModel.resume`) — the one case this control says anything beyond itself, on the lane.
        let prev = r.part.progress
        let shelvedAs = watched && target > prev ? appModel.resumableStatus(r.franchise, part: r.part) : nil
        withAnimation(ThemeMotion.pick(ThemeMotion.uiMicro, reduceMotion: reduceMotion)) {
            watchedOverrides[r.id] = watched
            appModel.setProgress(franchiseId: r.franchise.id,
                                 mediaId: r.part.mediaId,
                                 episodes: target)
        }
        if shelvedAs != nil {
            var receipt = UndoState(mediaId: r.part.mediaId, franchiseId: r.franchise.id, prevProgress: prev,
                                    title: r.franchise.title, episode: target, count: max(1, target - prev))
            appModel.resume(shelvedAs, franchiseId: r.franchise.id, mediaId: r.part.mediaId,
                            prevProgress: prev, receipt: &receipt)
            if receipt.subtitle != nil { appModel.presentUndo(receipt) }
        }
    }
}
