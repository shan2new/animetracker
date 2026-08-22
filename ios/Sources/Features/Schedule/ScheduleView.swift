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
    // No `accessibilityReduceTransparency` here any more: the top band is opaque for everyone, so
    // there is no material to drop and no second rendering path to keep honest. Reduce Transparency
    // used to make this screen's ghosting *worse* — it removed the blur and kept the 34 % veil.
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
    /// A week the READER asked for that the feed cannot travel to (it holds no rendered day). The
    /// pager still moves the strip; the scroll observer must not then snap it back on the next
    /// preference tick, which is how the shipped pager silently undid itself. Cleared the moment a
    /// finger touches the feed — from then on the strip follows the reader again.
    @State private var weekPinned = false
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
        /// ONE reserved column for the row's state — the mark ring while there is something to do,
        /// the air time once there is not. Both are drawn at this width, so a commit swaps ink and
        /// never geometry, and every row in the list shares one right-hand edge whether or not it
        /// carries a control.
        static let stateColumn: CGFloat = 62
    }

    /// Node geometry answers to Dynamic Type — a 4-pt mark does not read as a ring at AX5 any more
    /// than it does at default size.
    @ScaledMetric(relativeTo: .footnote) private var node: CGFloat = 8
    private var nodeStroke: CGFloat { max(1.5, node * 0.1875) }
    /// The week strip's "something airs here" mark. Scales with the caption it sits under.
    @ScaledMetric(relativeTo: .caption) private var dot: CGFloat = 6

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
                // The ambient wash. Schedule was the only art screen opening on flat black — a
                // table with small posters on it — and the baseline it is measured against opened
                // on a warm art-derived atmosphere across the top third.
                //
                // It begins BELOW the chrome band, not behind it: the band is opaque (see
                // `barGround`), so a wash drawn under it would be a wash nobody sees, and a wash
                // drawn *through* it would be the leak this pass exists to close. Masked so it
                // arrives at zero exactly at the band's bottom edge — the boundary between chrome
                // and content carries no step at all — blooms over the first rows and is gone.
                ambientWash
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
                // Nothing may come to rest inside the bottom ramp. A `.padding` inside the stack
                // does nothing at all when the content is shorter than the viewport — which is
                // exactly the case a three-day feed is in — so the clearance is a scroll-content
                // MARGIN, honoured either way.
                .tabBarContentMargin()
                // The moment a finger touches the feed it belongs to the user, and the landing
                // stops correcting. This is what replaces the old 250-ms `didLand` timer.
                .onScrollPhaseChange { _, phase in
                    if phase == .interacting { didLand = true; weekPinned = false }
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
                        // While the pager owns the strip, the scroll it started may not rewrite
                        // what the pager just said.
                        guard !weekPinned else { return }
                        selectedDay = current
                        // The strip is the screen's orientation device; it may not keep pointing at
                        // a week the reader has left — unless the reader is the one who put it on
                        // an empty week with the pager, in which case snapping it back here is the
                        // control undoing itself one frame after it was used.
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
            // ONE veil owns the whole top band.
            //
            // The shipped build split it in two and neither half owned the status bar: the system
            // scroll-edge effect was told to apply at the *strip's* boundary (the strip is a
            // `safeAreaInset`, so that is where the effect lands), which left the 60 pt above it
            // to whatever happened to be scrolling underneath — a blurred poster and two lines of
            // row text rendered beside the clock — and put a 7.6 % full-width luminance step at
            // 116 pt where the bar's material met the strip's own ground.
            //
            // So the strip's ground is now OPAQUE and runs up through the navigation bar and the
            // status bar as one surface (`barGround` + `.ignoresSafeArea(edges: .top)`), the
            // navigation bar contributes no second material of its own, and the system effect is
            // hidden on both edges because ours replaces both. Nothing scrolls through the clock,
            // there is no material boundary left to draw a seam, and Reduce Transparency changes
            // nothing about the occlusion — the band was never relying on a blur to hide content.
            .toolbarBackground(ThemeColor.canvas, for: .navigationBar)
            .toolbarBackgroundVisibility(.visible, for: .navigationBar)
            .scrollEdgeChromeBody(top: false)
            .scrollEdgeEffectHidden(true, for: .all)
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
                    // "Now", not "Today". Two controls labelled "Today" shipped on one frame — this
                    // one and the tab, 1 500 px apart, going to completely different places and
                    // distinguished only by position. This one scrolls to the NOW marker, so it is
                    // named after the thing it lands on.
                    //
                    // Scoped to the one control that appears and disappears. This animation used to
                    // sit on the whole ScrollView, so any structural identity change that happened
                    // to coincide with it animated too.
                    Group {
                        if awayFromToday {
                            Button("Now") { goToToday(proxy) }
                                .accessibilityLabel("Scroll to now")
                                .accessibilityHint("Scrolls to today's episodes")
                                .transition(.opacity)
                        }
                    }
                    .animation(ThemeMotion.pick(ThemeMotion.uiGentle, reduceMotion: reduceMotion), value: awayFromToday)
                }
                // Two unrelated actions in one glass container read as a single compound control
                // with ambiguous hit areas — iOS 26 merges adjacent `.topBarTrailing` items by
                // default, and this screen registers two. A fixed spacer gives each its own.
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
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

    private var filterValue: String {
        var bits: [String] = []
        if typeFilter != .all { bits.append(typeFilter == .anime ? "Anime" : "TV") }
        if unwatchedOnly { bits.append("watched episodes hidden") }
        return bits.isEmpty ? "Off" : bits.joined(separator: ", ")
    }

    /// The reader is somewhere other than today — either the feed has moved or the strip is
    /// showing another week. Either one earns the "Now" control; the shipped build watched only
    /// the first, so paging the strip a week forward left no way back.
    private var awayFromToday: Bool { selectedDay != 0 || (weekPage ?? 0) != 0 }

    /// The screen is showing a whole-surface state rather than a feed: nothing to page through,
    /// nothing to count, and a fully populated week strip over it is decoration over nothing.
    private var showsWholeScreenState: Bool {
        if appModel.loading && appModel.library.isEmpty { return true }
        if appModel.libraryEmpty { return true }
        return unfilteredDays.allSatisfy(\.isEmpty) || (days.allSatisfy(\.isEmpty) && filterActive)
    }

    /// The sticky bar's height, composed rather than measured: a `@State` written from the bar's own
    /// geometry feeds straight back into the body that lays the bar out, and this screen already
    /// pays for one preference-driven layout loop (see `offsets`). The pieces are all constants —
    /// the label row's 44-pt targets, the strip, and the paddings around them.
    private var barHeight: CGFloat {
        let labelRow: CGFloat = isAX ? 44 + 26 : 44
        let strip: CGFloat = showsWholeScreenState ? 0 : stripHeight + ThemeSpace.x0_5
        let chips: CGFloat = filterActive ? 44 + ThemeSpace.x0_5 : 0
        return ThemeSpace.x0_5 + labelRow + strip + chips + ThemeSpace.x2
    }

    // MARK: - Atmosphere

    /// Art-derived warmth over the first third of the feed, and nothing above the chrome.
    ///
    /// Masked to arrive at zero exactly where the opaque band ends, so the handover from chrome to
    /// content carries no step; it blooms across the first day's rows and has reached canvas again
    /// before the second. Static — one already-cached image, drawn once, never animated.
    @ViewBuilder
    private var ambientWash: some View {
        if !showsWholeScreenState {
            // Deliberately quiet. The colour this screen derives is an average of covers, and a
            // half-strength wash of it read as a dirty olive stain on a true-black ground rather
            // than as atmosphere — the reason the previous pass removed it outright. At this
            // strength the warmth is present under the first day and the ground is still black.
            ArtBackdrop(url: ambientCover, height: 300, intensity: 0.3)
                .mask(LinearGradient(stops: [.init(color: .clear, location: 0),
                                             .init(color: .black, location: 0.24),
                                             .init(color: .black, location: 1)],
                                     startPoint: .top, endPoint: .bottom))
                .padding(.top, barHeight)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
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
        // BOTH mechanisms, together. The feed is driven declaratively by `position` and
        // imperatively by the proxy; a `proxy.scrollTo` that leaves `position` holding the landing
        // day is a scroll the binding is entitled to undo, and it did — a jump to next week came
        // to rest a section *above* today.
        let land = {
            position = ScrollPosition(id: dayId, anchor: .top)
            proxy.scrollTo(dayId, anchor: .top)
        }
        if let delta, abs(delta) <= viewportH {
            // `uiReveal`, not a raw `.easeInOut(duration: 0.28)` literal. This is the motion the
            // screen runs most, and it was the one place in the file reaching past the token table.
            withAnimation(ThemeMotion.pick(ThemeMotion.uiReveal, reduceMotion: reduceMotion), land)
        } else {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t, land)
        }
    }

    private func goToToday(_ proxy: ScrollViewProxy) {
        FeedbackCoordinator.fire(.selection)
        didLand = true
        weekPinned = false
        selectedDay = 0
        withAnimation(ThemeMotion.pick(ThemeMotion.uiGentle, reduceMotion: reduceMotion)) { weekPage = 0 }
        scroll(to: 0, proxy: proxy)
    }

    /// Where the feed should travel to when the reader asks for week `page`.
    ///
    /// The first day of that week that the feed actually renders — that is the whole answer when
    /// the week has anything in it. When it does not (a past week with nothing, or a week past the
    /// end of the horizon) the feed travels to the edge of what it *does* hold, so the reader lands
    /// on the closing line that names the horizon rather than on an unchanged screen. Whether the
    /// day is inside the requested week is reported back, because that is what decides whether the
    /// strip has to be pinned against the scroll observer.
    private func landing(forWeek page: Int) -> (day: Int, insideWeek: Bool)? {
        let rendered = Set(visibleDays.map(\.id))
        let cells = weekCells(page: page)
        if let hit = cells.first(where: { rendered.contains($0.offset) }) { return (hit.offset, true) }
        guard let edge = (page > 0 ? visibleDays.last : visibleDays.first)?.id else { return nil }
        return (edge, false)
    }

    // MARK: - Sticky bar

    /// ONE ground for the whole top band, and it is OPAQUE.
    ///
    /// It was glass — `.ultraThinMaterial` plus a 34 % canvas veil — sitting under a navigation bar
    /// that brought a second, different material of its own. Two grounds means a boundary, and the
    /// boundary measured a 7.6 % full-width luminance step at 116 pt; the glass also blurred rather
    /// than occluded, so a poster and two lines of row text were legible in the status bar beside
    /// the clock, and *worse* for a user with Reduce Transparency on, whose blur was dropped while
    /// the 34 % veil stayed. Chrome that content passes behind has to be opaque; only chrome that
    /// content passes *beside* can be glass.
    ///
    /// It is plain `canvas`, deliberately: the ambient wash begins where this ends, so any tint
    /// here would be a step at the handover — the exact defect the glass was introducing.
    private var barGround: some View {
        ThemeColor.canvas
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// The bar's hand-off to the content: the same canvas, ramped out over 22 pt, so a day header
    /// dissolves into the chrome instead of being guillotined by it.
    private var barFade: some View {
        ThemeColor.canvas
            .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func stickyBar(_ proxy: ScrollViewProxy) -> some View {
        let page = weekPage ?? 0
        let week = weekCells(page: page)
        return VStack(alignment: .leading, spacing: 0) {
            weekLabelRow(week, page: page, proxy: proxy)
            // A fully populated week strip over a screen that is showing "nothing scheduled" is a
            // calendar asserting a selected date over a surface that says there is nothing, so it
            // collapses to its range label — which still says *when* nothing is scheduled.
            //
            // Collapsed by HEIGHT, never by a conditional: taking the strip out of the view tree
            // and putting it back re-creates the paged scroll view, and a re-created
            // `.scrollPosition(id:)` does not re-apply, so the strip came back materialising no
            // page at all and rendered as 74 pt of empty canvas.
            weekStrip(proxy)
                .frame(height: showsWholeScreenState ? 0 : nil)
                .opacity(showsWholeScreenState ? 0 : 1)
                .clipped()
                .accessibilityHidden(showsWholeScreenState)
            // An active filter has to be visible ON the screen, not only in the toolbar glyph and
            // the VoiceOver value — a reader who filters, leaves and comes back was shown a
            // schedule that simply appeared to be missing shows. It lives in the CHROME, not at the
            // top of the feed: a token that scrolls away after one flick is invisible again, which
            // is the defect. Library ships the same removable-token pattern.
            filterChips
        }
        .padding(.bottom, ThemeSpace.x2)
        // Opaque, and the same canvas the navigation bar above it is now painted in, so the two
        // butt together as one surface: there is exactly one veil over the top band, nothing
        // scrolls through the clock, and no material boundary is left to draw a seam.
        .background { barGround }
        // The hand-off ramp exists so scrolling CONTENT dissolves into the bar. A pinned day header
        // is chrome and brings its own ground, so veiling it with a third material only greyed the
        // one line the screen most wants legible — TODAY and its NOW time.
        .overlay(alignment: .bottom) {
            if pinnedDay == nil { barFade.frame(height: 22).offset(y: 22) }
        }
    }

    /// "‹  17 AUG – 23 AUG        1 EPISODE LEFT  ›".
    ///
    /// The pagers are pinned to the two edges at every size — they were `chevron.compact` glyphs
    /// with no button ground and no visible target, reading as punctuation around the label on the
    /// screen's primary temporal navigation. Their 44-pt boxes are centred on the gutter + rail
    /// lane (16 + 22), so the glyphs sit on the same vertical line every day header starts on.
    @ViewBuilder
    private func weekLabelRow(_ week: [WeekCell], page: Int, proxy: ScrollViewProxy) -> some View {
        let summary = weekSummary(week, page: page)
        let range = weekRangeLabel(week)
        let label = SectionLabel(text: range)
            .accessibilityAddTraits(.isHeader)
            .contentTransition(.opacity)
        let count = summary.map {
            Text($0).type(ThemeType.sectionLabel).textCase(.uppercase)
                .foregroundStyle(ThemeColor.textTertiary)
                .lineLimit(1)
                .contentTransition(.opacity)
                .accessibilityHidden(true)
        }
        Group {
            if isAX {
                // One alignment, not two. At AX the range stayed centred with its pagers clustered
                // left of centre while the count dropped to a left-aligned second line — two
                // alignments in one header block and pagers with nothing to align to.
                VStack(alignment: .leading, spacing: ThemeSpace.x1) {
                    HStack(spacing: ThemeSpace.x1) {
                        weekStep(-1, proxy: proxy)
                        label
                        Spacer(minLength: ThemeSpace.x2)
                        weekStep(1, proxy: proxy)
                    }
                    // Aligned under the range label it qualifies, not to a third x of its own.
                    if let count { count.padding(.leading, 44 + ThemeSpace.x1) }
                }
            } else {
                HStack(alignment: .center, spacing: ThemeSpace.x2) {
                    weekStep(-1, proxy: proxy)
                    label
                    Spacer(minLength: ThemeSpace.x2)
                    count
                    weekStep(1, proxy: proxy)
                }
            }
        }
        // The 44-pt targets start at the gutter, so their glyphs are centred on 16 + 22 — the same
        // vertical line every day header, row and the rail itself begins on.
        .padding(.horizontal, ThemeMetrics.gutter)
        .padding(.top, ThemeSpace.x0_5)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(summary.map { "\(range), \($0)" } ?? range)
    }

    /// A real control: a 15-pt semibold chevron in a 44 × 44 target with a pressed state, pinned to
    /// its edge. And it now DOES something — `weekStep` used to mutate `weekPage` and nothing else,
    /// so the strip advanced a week over a pixel-identical list, and the scroll observer then
    /// snapped the strip back the moment the user moved a finger.
    private func weekStep(_ delta: Int, proxy: ScrollViewProxy? = nil) -> some View {
        Button {
            let page = (weekPage ?? 0) + delta
            let cells = weekCells(page: page)
            let target = landing(forWeek: page)
            FeedbackCoordinator.fire(.selection)
            didLand = true
            // The pager OWNS the strip until the reader touches the feed again. Without this the
            // scroll observer re-derives `weekPage` from the header that happens to be under the
            // line while the programmed scroll is still in flight, and writes the requested week
            // straight back out — the control undoing itself, one frame after it was used. Cleared
            // by `onScrollPhaseChange`, by a day tap, and by "Now".
            weekPinned = true
            selectedDay = target?.insideWeek == true
                ? target!.day
                : (cells.first(where: \.hasContent) ?? cells.first)?.offset ?? selectedDay
            withAnimation(ThemeMotion.pick(ThemeMotion.uiGentle, reduceMotion: reduceMotion)) {
                weekPage = page
            }
            if let target, let proxy { scroll(to: target.day, proxy: proxy) }
        } label: {
            Image(systemName: delta < 0 ? "chevron.left" : "chevron.right")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ThemeColor.textSecondary)
                .frame(width: 44, height: 44)
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
        // Explicitly ZERO. `contentMargins` is inherited through the environment, so the feed's
        // own bottom clearance (76 pt, to clear the tab bar) was also being applied to this strip
        // — a 74-pt-tall scroll view given a 76-pt bottom margin has nowhere left to draw, and the
        // week strip rendered as an empty band. A nested scroll view has to state its own margins.
        .contentMargins(.all, 0, for: .scrollContent)
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
                Picker("Source", selection: sourceBinding) {
                    Text("All").tag(MediaFilter.all)
                    Text("Anime").tag(MediaFilter.anime)
                    Text("TV").tag(MediaFilter.tv)
                }
                .pickerStyle(.inline)
            }
            // No header on the second group: a 17-pt grey `Text` above a single toggle rendered as
            // a disabled menu item. The divider already separates the two decisions.
            //
            // A verb, not a bare adjective phrase: "Unwatched only" sat under a single-select
            // Picker with a checkmark in it, so it read as a fourth mutually-exclusive source.
            Toggle("Hide watched episodes", isOn: hideWatchedBinding)
        } label: {
            Image(systemName: filterActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease")
        }
        .tint(filterActive ? ThemeColor.accent : ThemeColor.textPrimary)
        .accessibilityLabel("Filter")
        .accessibilityValue(filterValue)
    }

    // The haptic fires from the MUTATION, not from an `onChange` observer. Two observed values
    // written in one transaction (the filter reset) enqueued two `.selection` events in one frame,
    // and only the coordinator's blanket 300 ms floor made that inaudible — a floor that no longer
    // applies to `.selection`, which now tracks a finger at 40 ms.
    private var sourceBinding: Binding<MediaFilter> {
        Binding(get: { typeFilter }, set: { typeFilter = $0; FeedbackCoordinator.fire(.selection) })
    }

    private var hideWatchedBinding: Binding<Bool> {
        Binding(get: { unwatchedOnly }, set: { unwatchedOnly = $0; FeedbackCoordinator.fire(.selection) })
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
    ///
    /// **On the current week it counts what is LEFT, and says so.** The feed is a rolling agenda
    /// that opens on today, so "17 AUG – 23 AUG · 3 EPISODES" sat directly above a list whose first
    /// row was 23 Aug: two of the three were behind the reader, above the fold. The number was
    /// true of the week and false of the screen, which is the only thing a reader can check it
    /// against. Counting forward from today makes the number describe the list under it, and the
    /// word "left" says which of the two quantities it is.
    private func weekSummary(_ week: [WeekCell], page: Int) -> String? {
        guard page == 0 else {
            let total = week.reduce(0) { $0 + $1.count }
            return total > 0 ? Copy.episodes(total) : nil
        }
        let left = week.filter { $0.offset >= 0 }.reduce(0) { $0 + $1.count }
        return left > 0 ? "\(Copy.episodes(left)) left" : nil
    }

    private func weekCell(_ cell: WeekCell, proxy: ScrollViewProxy) -> some View {
        let selected = cell.offset == selectedDay && !surfaceEmpty
        let enabled = cell.hasContent || cell.isToday
        // ONE encoding of past-vs-future: the whole cell recedes as a group. The shipped build said
        // "past" with dot colour and "has content" with numeral weight, so 17/18 (past, empty) and
        // 20 (future, empty) looked identical and a 4-pt hue difference carried the screen's
        // primary scanning job.
        let past = cell.offset < 0
        // Amber is the loudest thing in the app and a date is not allowed to be it — the SELECTION
        // was the third amber object within 200 pt of the two (the TODAY rule and the NOW time)
        // that have a reason to be. Selection is now a neutral raised ground with the numerals at
        // full ink; today keeps its tint, because today is the screen's anchor, and it keeps it
        // *and* an underline when Differentiate Without Color is on.
        let numberColor: Color = cell.isToday ? ThemeColor.accent : ThemeColor.textPrimary
        return Button {
            FeedbackCoordinator.fire(.selection)
            didLand = true
            weekPinned = false
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
                                .fill(ThemeColor.surfaceRaised)
                                .overlay(RoundedRectangle(cornerRadius: ThemeRadius.compactControl, style: .continuous)
                                    .strokeBorder(ThemeColor.strokeStrong, lineWidth: 1))
                        }
                    }
                    // "Today" was encoded by hue alone — a grep of all of `Sources/` returned zero
                    // references to `accessibilityDifferentiateWithoutColor`, so for a reader who
                    // has asked the system for shapes there was nothing to see. WCAG 1.4.1.
                    .differentiatingUnderline(cell.isToday, tint: ThemeColor.accent)
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
                Circle().strokeBorder(ThemeColor.textSecondary, lineWidth: max(1.5, dot * 0.25))
            } else {
                Color.clear
            }
        }
        // Scaled: a fixed 6-pt indicator does not grow with the numerals above it, so at AX5 the
        // one mark that says "something airs here" was the only thing on the strip that did not.
        .frame(width: dot, height: dot)
        .accessibilityHidden(true)
    }

    // MARK: - Content (state matrix)

    /// A whole-screen state sits in the MIDDLE of the content area, not pinned under the week strip
    /// with 1 100 pt of canvas beneath it.
    ///
    /// Centred against the tab bar's VISUAL height, not `tabBarClearance`: subtracting the scroll
    /// inset put the card ~81 pt above true optical centre, reading as top-pinned on a screen with
    /// 400 pt of canvas under it.
    @ViewBuilder
    private func centred<V: View>(@ViewBuilder _ state: () -> V) -> some View {
        state()
            .padding(.horizontal, ThemeMetrics.gutter)
            .centredState(contentH: viewportH - barHeight)
            .background(alignment: .top) { stateWash }
    }

    /// The identity wash behind a whole-screen state.
    ///
    /// `EmptyState` can draw its own, but it draws it inside a box only 64 pt larger than the plate
    /// — so a 340-pt radius is cut off by its own container and lands as a hard full-width seam
    /// across the screen, which is the defect this pass exists to remove. Drawn at the size of the
    /// whole state block instead, the gradient reaches clear well inside its own bounds and there
    /// is no edge anywhere. (SHARED-FILE REQUEST filed against `EmptyState.wash`.)
    private var stateWash: some View {
        RadialGradient(colors: [ThemeColor.accentSoft, .clear],
                       center: .init(x: 0.5, y: 0.42), startRadius: 0, endRadius: 460)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
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
                           primary: { Task { await appModel.reload() } },
                           ambient: false)
            }
        } else if appModel.libraryEmpty {
            // Schedule's own empty sentence — the shipped card said "Your library is empty / Add
            // your first show and Today builds itself" on a screen that is neither.
            centred { EmptyState(.emptySchedule, prominence: .major, primary: onAddShow, ambient: false) }
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
                centred { EmptyState(.nothingScheduled, prominence: .major, ambient: false) }
            } else if shown.allSatisfy(\.isEmpty) && filterActive {
                centred {
                    EmptyState(.noFilterMatches, prominence: .major, primary: {
                        FeedbackCoordinator.fire(.selection)
                        withAnimation(ThemeMotion.pick(ThemeMotion.uiSnappy, reduceMotion: reduceMotion)) { typeFilter = .all; unwatchedOnly = false }
                    }, ambient: false)
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

    /// The removable tokens for whatever is currently filtering the feed. Each one clears exactly
    /// the filter it names; the whole row is absent when nothing is filtering.
    @ViewBuilder
    private var filterChips: some View {
        if filterActive {
            HStack(spacing: ThemeSpace.x2) {
                if typeFilter != .all {
                    filterChip(typeFilter.chipLabel) { typeFilter = .all }
                }
                if unwatchedOnly {
                    filterChip("Watched hidden") { unwatchedOnly = false }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, ThemeMetrics.gutter)
            .padding(.top, ThemeSpace.x0_5)
            .transition(.opacity)
        }
    }

    private func filterChip(_ text: String, clear: @escaping () -> Void) -> some View {
        Button {
            FeedbackCoordinator.fire(.selection)
            withAnimation(ThemeMotion.pick(ThemeMotion.uiSnappy, reduceMotion: reduceMotion)) { clear() }
        } label: {
            HStack(spacing: 5) {
                Text(text)
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
            }
            .type(ThemeType.metadataEmphasis)
            .foregroundStyle(ThemeColor.accent)
            .padding(.horizontal, 12)
            .frame(minHeight: 32)
            .background { Capsule().fill(ThemeColor.accentSoft) }
            .contentShape(Capsule())
            .frame(minHeight: 44)
        }
        .buttonStyle(WeekCellPressStyle())
        .accessibilityLabel("\(text). Remove filter")
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
        .background(alignment: .topLeading) { railLine(head: true, tail: true) }
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
                .opacity(settled ? 0.72 : 1)
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

    /// The 1-pt timeline. On the FIRST day it fades up across the whole header band, so the line
    /// emerges where the first row does rather than starting hard 37 pt above the first node with
    /// nothing attached to it — a stub is what a rail looks like when nobody decided where it began.
    private func railLine(head: Bool, tail: Bool = false) -> some View {
        GeometryReader { geo in
            let h = geo.size.height
            let fade: CGFloat = head ? 1 : 0
            // The skeleton's rail is the only one with nothing below it, so it is the only one that
            // has to end. A 1-pt line stopping dead mid-canvas is the same drawing bug the feed's
            // closing node was.
            let out: CGFloat = tail ? max(fade, 1 - 24 / max(h, 1)) : 1
            Rectangle()
                .fill(ThemeColor.separator)
                .frame(width: 1, height: h)
                .mask(LinearGradient(stops: [.init(color: .clear, location: 0),
                                             .init(color: .black, location: fade),
                                             .init(color: .black, location: out),
                                             .init(color: tail ? .clear : .black, location: 1)],
                                     startPoint: .top, endPoint: .bottom))
                .offset(x: ThemeMetrics.gutter + Rail.x - 0.5)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The end of the horizon, and it NAMES the horizon. "Nothing scheduled" alone read as a second
    /// failure two screens below the first one, and it had no scope: nothing scheduled *when*?
    /// "Through 28 Aug" INCLUDES 28 Aug, and there is an episode on 28 Aug forty points above this
    /// sentence — the closing line of the feed was literally contradicted by the row it closed.
    private var horizonLine: String {
        guard let last = appModel.scheduleDays.last else { return Copy.Empty.nothingScheduled.title }
        let ts = todayNoon + Int64(last.id) * Formatting.D
        return "That's everything through \(Formatting.fmtMonthDay(ts))"
    }

    /// The rail runs on past the last event and fades out over its last 24 pt. No terminator node:
    /// a node means "an event happens here", and the closing sentence is not an event — a hollow
    /// ring beside it was the rail claiming a fourth meaning it had not defined.
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
                    Rectangle().fill(ThemeColor.separator)
                        .frame(width: 1, height: capY)
                        .mask(LinearGradient(stops: [.init(color: .black, location: 0),
                                                     .init(color: .black, location: max(0, 1 - 24 / max(capY, 1))),
                                                     .init(color: .clear, location: 1)],
                                             startPoint: .top, endPoint: .bottom))
                        .offset(x: ThemeMetrics.gutter + Rail.x - 0.5)
                }
                .allowsHitTesting(false)
            }
            .accessibilityElement(children: .combine)
    }

    /// "Nothing scheduled." The header supplies "today", so the sentence does not repeat it — and
    /// it no longer names the next day either: on a seven-day feed that day's own header is ~120 pt
    /// below, naming itself, and the pointer was also the fifth "next up" in the app's vocabulary.
    private var nothingTodayLine: String {
        hasAiredEarlierToday() ? "Nothing else scheduled" : "Nothing scheduled"
    }

    private func dayHeader(_ day: Day) -> some View {
        let todayEmpty = day.isToday && day.isEmpty
        return HStack(alignment: .firstTextBaseline, spacing: ThemeMetrics.labelGap) {
            // Neutral, even on today. Three amber objects stated one fact within 200 pt — this
            // label, its rule, and the NOW time — on a screen with no primary action, so the
            // loudest thing on it was a date. NOW keeps the accent; it is the only mark here that
            // moves and the only one worth spending it on.
            Text(day.header).type(ThemeType.dayLabel).textCase(.uppercase)
                .foregroundStyle(day.isToday ? ThemeColor.textSecondary : ThemeColor.textTertiary)
                .lineLimit(isAX ? 2 : 1)
                .fixedSize(horizontal: false, vertical: true)
                // The date names the section. It takes its width before the rule and before the
                // clock beside it — "TODAY · SAT 22 A…" is not a day header.
                .layoutPriority(1)
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
                liveNow { time in
                    HStack(spacing: 5) {
                        Text("Now").type(ThemeType.dayLabel).textCase(.uppercase)
                        Text(Formatting.fmtTime(time)).type(ThemeType.time)
                    }
                    .foregroundStyle(ThemeColor.accent)
                    .lineLimit(1)
                }
                // `TimelineView` is a container and takes every point it is offered; unhugged it
                // stole the width the day label needed and truncated "TODAY · SAT 22 AUG".
                .fixedSize()
            } else if day.count > 1 {
                // Only when it says something. "1 EPISODE" over three consecutive single-row days
                // is 40 % of the header's width spent restating the row underneath it; the count
                // earns its place on a four-episode Saturday.
                Text(Copy.episodes(day.count)).type(ThemeType.sectionLabel).textCase(.uppercase)
                    .foregroundStyle(ThemeColor.textTertiary)
                    .lineLimit(1)
            } else if day.count == 1 {
                EmptyView()
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

    /// The clock this screen prints, driven by a periodic timeline rather than by a model value.
    ///
    /// "NOW 9:35 PM" was measured beside a 9:41 phone clock, and 9:01 on two captures taken minutes
    /// apart — the app's own clock disagreeing with the phone's by up to 40 minutes, on the one
    /// element whose entire content is the current time. `TimelineView(.periodic)` is re-evaluated
    /// by the system on the minute and re-arms itself when the scene comes back, which is exactly
    /// the guarantee a wall clock needs and the one a shared model property cannot give.
    private func liveNow<V: View>(@ViewBuilder _ content: @escaping (Int64) -> V) -> some View {
        TimelineView(.periodic(from: .now, by: 60)) { ctx in
            let ms = Int64(ctx.date.timeIntervalSince1970 * 1000)
            content((ms / Formatting.minuteMs) * Formatting.minuteMs)
                .animation(ThemeMotion.pick(ThemeMotion.uiGentle, reduceMotion: reduceMotion), value: ms / Formatting.minuteMs)
        }
    }

    /// An 8-pt filled node with a 14-pt halo — the same size as every other node on the rail. It
    /// was a 16-pt disc inside an 18-pt dark halo, a 2× jump inside one repeating element, so the
    /// rail's rhythm broke at the one place it should read as continuous.
    private var nowNode: some View {
        Circle().fill(ThemeColor.accent)
            .frame(width: node, height: node)
            .background {
                Circle().fill(ThemeColor.accent.opacity(0.18)).frame(width: node + 6, height: node + 6)
            }
            .accessibilityHidden(true)
    }

    /// `NOW ————————— 5:54 AM`, on the rail, in the one place amber is unambiguously right.
    /// It is the only thing on this screen that moves on its own, once a minute.
    private var nowMarker: some View {
        liveNow { time in
            HStack(spacing: ThemeMetrics.labelGap) {
                Text("Now").type(ThemeType.dayLabel).textCase(.uppercase).foregroundStyle(ThemeColor.accent)
                if !isAX {
                    Rectangle().fill(LinearGradient(colors: [ThemeColor.accent.opacity(0.60), ThemeColor.accent.opacity(0.28)],
                                                    startPoint: .leading, endPoint: .trailing))
                        .frame(height: 1)
                } else {
                    Spacer(minLength: ThemeSpace.x2)
                }
                Text(Formatting.fmtTime(time)).type(ThemeType.time).foregroundStyle(ThemeColor.accent)
            }
            .padding(.leading, Rail.gutter)
            .padding(.vertical, ThemeMetrics.labelGap)
            .overlay(alignment: .leading) { nowNode.offset(x: Rail.x - node / 2) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Now, \(Formatting.fmtTime(time))")
        }
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
                        // The only list-to-detail route in the product that slid rather than
                        // zoomed: the id was passed to the destination but no source was ever
                        // registered, because the row builds its slot by hand.
                        .zoomSource("sched/\(f.id)")
                        // A faded POSTER reads as an image that failed to load, so the group dim
                        // stops at the artwork: it steps back on saturation and a little ink while
                        // the text carries the recession.
                        .opacity(watched ? 0.82 : 1)
                        .saturation(watched ? 0.9 : 1)
                    // The trailing time shares the TITLE's first baseline. Laid out as a sibling of
                    // the whole text block it floated ~10 pt under the baseline on a one-line title
                    // and landed on the second line of a two-line one — the time danced down the
                    // column as titles wrapped, in the one column a schedule is scanned by.
                    HStack(alignment: .firstTextBaseline, spacing: ThemeSpace.x3) {
                        VStack(alignment: .leading, spacing: ThemeMetrics.titleGap) {
                            if let leadTime { leadingTime(leadTime) }
                            Text(f.displayTitle).type(ThemeType.rowTitle).foregroundStyle(ThemeColor.textPrimary)
                                .lineLimit(isAX ? nil : 2)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(meta).type(ThemeType.rowMeta).foregroundStyle(ThemeColor.textSecondary)
                                .lineLimit(isAX ? nil : 1)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: ThemeSpace.x2)
                        if !isAX, let time, !showsAction {
                            timeColumn(time, hasReminder: hasReminder)
                        }
                    }
                    // Greedy, so the text block gets the row's whole remaining width and the time
                    // sits on the row's trailing edge. Hugged, the pair floated in the middle of
                    // the row and guillotined the title 70 pt short of the bezel.
                    .frame(maxWidth: .infinity)
                    // 0.72, not 0.48: at 0.48 `textSecondary` composites to ≈2.64:1 on exactly the
                    // rows a reader opens this screen to read — which episode aired, and when.
                    .opacity(watched ? 0.72 : 1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPressStyle(radius: ThemeRadius.poster))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(f.title), \(meta)\(spokenTime)\(hasReminder ? ", reminder set" : "")")
            .accessibilityValue(watched ? Copy.Accessibility.complete : "")
            .accessibilityHint("Opens the show")

            trailing(e, showsAction: showsAction, marked: isCommitted, watched: watched,
                     batch: batch, time: time, hasReminder: hasReminder,
                     axInset: posterW + ThemeMetrics.artGap)
        }
        .padding(.leading, Rail.gutter)
        .padding(.vertical, ThemeSpace.x2)
        .frame(minHeight: ThemeMetrics.rowMedia, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .overlay(alignment: .leading) { railNode(watched: watched, aired: e.aired) }
        .animation(ThemeMotion.pick(ThemeMotion.uiMicro, reduceMotion: reduceMotion), value: isCommitted)
    }

    /// The trailing time, on the title's baseline, with any reminder bell beside it rather than
    /// stacked over it — two glyphs in one trailing column is a toolbar, not a row.
    private func timeColumn(_ time: String, hasReminder: Bool, alignment: Alignment = .trailing) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if hasReminder {
                Image(systemName: "bell.fill").font(.system(size: 10))
                    .foregroundStyle(ThemeColor.textDisabled)
                    .accessibilityHidden(true)
            }
            Text(time).type(ThemeType.time).foregroundStyle(ThemeColor.textSecondary)
        }
        // The mark control and the settled time occupy one reserved column, so a commit swaps ink
        // and never moves the row.
        .frame(minWidth: Rail.stateColumn, alignment: alignment)
        .accessibilityHidden(true)
    }

    /// The row's clock at accessibility sizes: it LEADS the text block instead of sitting in a
    /// trailing column, because a 60-pt-wide column beside a 230-pt row is a stray third line.
    /// Same token and same ink as the trailing form — at default size the time was `textSecondary`
    /// and at AX1 it turned accent, so the identical fact changed meaning with the text size.
    private func leadingTime(_ time: String) -> some View {
        Text(time).type(ThemeType.time).foregroundStyle(ThemeColor.textSecondary)
    }

    /// The row's one trailing control, in a column that is RESERVED whether or not it is occupied.
    ///
    /// The commit used to run as two unrelated animations: `MarkRing` filled and drew its check in
    /// place (correct), then `showsAction` flipped and the ring scaled out at 60 % while a
    /// differently-sized tick-and-time stack scaled in — by a wide margin the largest motion in an
    /// app whose stated reveal limits are a 0.985 press floor and 6 pt of travel, and it moved the
    /// row while it played. It is now the shared handoff: the ring leaves on `uiDismiss`, the
    /// settled time arrives on `uiSettle` in a column of the same width, and nothing shifts.
    ///
    /// The settled state is the time ALONE. It used to be the group dim, plus a filled rail node
    /// with a knocked-out check, plus a bare `PassiveTick` stacked over the time — the same fact
    /// three times, and two glyphs in one trailing column, which at 8 pt made a dim tick and a dim
    /// ring nearly indistinguishable. The rail node and the dim already carry "watched".
    @ViewBuilder
    private func trailing(_ e: Event, showsAction: Bool, marked: Bool, watched: Bool, batch: Bool,
                          time: String?, hasReminder: Bool, axInset: CGFloat) -> some View {
        if showsAction {
            // The shared mark control, so the same gesture has the same shape on Schedule, the
            // episode list and Detail — and the check DRAWS on commit here too. It occupies the
            // same reserved column the settled time occupies, so the swap moves nothing.
            MarkRing(marked: marked,
                     label: batch ? "Mark \(Copy.episodes(e.episode - e.part.progress)) of \(e.franchise.title) as watched"
                                  : "Mark \(Copy.episode(e.episode)) of \(e.franchise.title) as watched",
                     markedLabel: Copy.Progress.episodeWatched(e.episode)) {
                guard !marked else { return }
                mark(e, batch: batch)
            }
            .frame(width: isAX ? nil : Rail.stateColumn, alignment: .trailing)
            .padding(.leading, isAX ? axInset : 0)
            .frame(maxWidth: isAX ? .infinity : nil, alignment: .leading)
            .transition(.handoff(reduceMotion: reduceMotion))
        } else if time == nil && hasReminder {
            Image(systemName: "bell.fill").font(.system(size: 12))
                .foregroundStyle(ThemeColor.textDisabled)
                .frame(width: isAX ? 44 : Rail.stateColumn, height: 44, alignment: .trailing)
                .padding(.leading, isAX ? axInset : 0)
                .accessibilityHidden(true)
        } else if time == nil && !isAX {
            // A date-only row has no clock and nothing to do: the column is still reserved, so it
            // keeps the list's one right-hand edge.
            Color.clear.frame(width: Rail.stateColumn, height: 44).accessibilityHidden(true)
        }
        // Otherwise nothing at all: a timed row below accessibility sizes carries its clock inside
        // the text block, on the title's baseline, and a second reserved column out here would take
        // 74 pt off the title for a view with nothing in it.
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
