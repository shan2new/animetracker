import SwiftUI

// Rewatch surfaces (spec board 06 §1.3, 1.5–1.7): the Start rewatch sheet, the Watch history rail
// and one session's detail. Sessions live in RewatchStore; progress lives on the server.

// MARK: - Start rewatch (Surface C)

struct StartRewatchSheet: View {
    @Environment(\.dismiss) private var dismiss
    let franchise: Franchise
    let onStart: (_ scope: WatchSession.Scope, _ startedAt: Int64) -> Void

    @State private var scope: WatchSession.Scope = .franchise
    @State private var startDate = Date()

    private var parts: [FranchisePart] { franchise.episodicPartsInOrder }

    /// The scope that covers the whole work, with a count like every other row.
    ///
    /// It was "All seasons" — printed directly over a list containing "OVA 1", "OVA 2: No Regrets"
    /// and "OVA 3: Lost Girls", none of which is a season. ("Entire franchise" before that was
    /// server vocabulary; the code comment rejecting it already recorded that the app's word for a
    /// work is "title" — and then used the wrong word anyway.)
    private var everythingCount: String? {
        let total = parts.reduce(0) { $0 + max($1.totalEpisodes, $1.progress) }
        return total > 0 ? Copy.episodes(total) : nil
    }

    /// One scope row, in the app's OWN row grammar.
    ///
    /// The same season list is a push away, rendered as 88-pt poster rows on the canvas; here it
    /// was text-only 56-pt rows inside a plate with a trailing count — two grammars for one list,
    /// one tap apart, and the sheet's version was the one that looked like a settings table. This
    /// is `MediaRow`: artwork, the row's own rhythm, `separatorQuiet` inset to the title, and the
    /// selection tick as the single trailing control.
    private func scopeRow(title: String, count: String?, poster: String?, selected: Bool,
                          separator: Bool, action: @escaping () -> Void) -> some View {
        MediaRow(title: title, meta: count, poster: poster, slot: .queue,
                 chevron: false, separator: separator,
                 trailing: {
                     // Reserved whether or not the row is selected, so a tick landing never
                     // reflows the row it lands on.
                     Image(systemName: "checkmark")
                         .font(.system(size: 15, weight: .semibold))
                         .foregroundStyle(ThemeColor.accent)
                         .opacity(selected ? 1 : 0)
                         .frame(width: 18)
                         .accessibilityHidden(true)
                 }) {
            FeedbackCoordinator.fire(.selection)
            action()
        }
        .accessibilityLabel([title, count].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ThemeMetrics.sectionGap) {
                    // The context row from board 06: the sheet says which show it is about, with
                    // its own artwork, before it asks anything. A modal that opens on a grey
                    // sentence and a list of radio rows could be about anything.
                    HStack(alignment: .top, spacing: ThemeMetrics.artGap) {
                        PosterSlot(url: franchise.portraitArt, .queue)
                        VStack(alignment: .leading, spacing: ThemeMetrics.titleGap) {
                            Text(franchise.title)
                                .type(ThemeType.showTitleM)
                                .foregroundStyle(ThemeColor.textPrimary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Your previous watch history stays unchanged.")
                                .type(ThemeType.metadata).foregroundStyle(ThemeColor.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    VStack(alignment: .leading, spacing: ThemeMetrics.labelGap) {
                        SectionLabel(text: "Scope")
                        LazyVStack(spacing: 0) {
                            scopeRow(title: DetailCopy.everything, count: everythingCount,
                                     poster: franchise.portraitArt,
                                     selected: scope == .franchise, separator: !parts.isEmpty) {
                                scope = .franchise
                            }
                            ForEach(Array(parts.enumerated()), id: \.element.id) { i, part in
                                scopeRow(title: part.canonicalLabel.isEmpty ? part.title : part.canonicalLabel,
                                         count: part.totalEpisodes > 0 ? Copy.episodes(part.totalEpisodes) : nil,
                                         poster: part.portraitArt ?? franchise.portraitArt,
                                         selected: scope == .part(mediaId: part.mediaId),
                                         separator: i < parts.count - 1) {
                                    scope = .part(mediaId: part.mediaId)
                                }
                            }
                        }
                    }
                    // No "START DATE" label above a row that already says "Start date" — the
                    // header and the row were the same three words, 10 pt apart.
                    GroupedList {
                        HStack {
                            Text("Start date").type(ThemeType.body).foregroundStyle(ThemeColor.textPrimary)
                            Spacer()
                            DatePicker("Start date", selection: $startDate, in: ...Date(), displayedComponents: .date)
                                .labelsHidden()
                                .tint(ThemeColor.accent)
                        }
                        .padding(.leading, 14).padding(.trailing, 10)
                        .frame(minHeight: ThemeMetrics.rowCompact)
                    }
                }
                .padding(.horizontal, ThemeMetrics.gutter)
                .padding(.top, ThemeSpace.x4)
                .padding(.bottom, ThemeSpace.x4)
            }
            .background(ThemeColor.canvasRaised.ignoresSafeArea())
            // The commit, PINNED. It used to be the last thing in the scroll, below the scope list
            // and a start-date group — on a nine-part franchise a screen and a half below the fold —
            // so the user picked a scope and had nothing on screen to commit with, while the last
            // visible row was sliced flat by the screen edge with no home-indicator inset.
            .safeAreaInset(edge: .bottom) {
                Button(Copy.Action.startRewatch) {
                    onStart(scope, Int64(startDate.timeIntervalSince1970 * 1000))
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle2())
                .padding(.horizontal, ThemeMetrics.gutter)
                .padding(.top, ThemeSpace.x3)
                .padding(.bottom, ThemeSpace.x2)
                // The one raw material in Features: it ignored Reduce Transparency, which
                // `chromeGlass` honours.
                .chromeGlass(in: Rectangle())
            }
            .navigationTitle(Copy.Action.startRewatch)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        // NEUTRAL. Amber on the dismissive action made the loudest coloured object
                        // on the sheet the one that throws the work away — and the selection check
                        // was amber too, so there were two ambers and neither was the primary
                        // action. `body`, not `listAction`: a sheet's Cancel is a navigation
                        // control and iOS sets it at the sheet title's own size. `.plain` also gave
                        // the sheet's only visible control no press state at all.
                        // `interactive`, like every bare toolbar action (the app's one toolbar
                        // recipe: confirm = `bodyEmphasis` + interactive, dismiss = `body` +
                        // interactive). This was the one Cancel in the app set in secondary ink.
                        Text(Copy.Action.cancel)
                            .type(ThemeType.body)
                            .foregroundStyle(ThemeColor.interactive)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .buttonStyle(RowPressStyle(radius: ThemeRadius.compactControl))
                }
                // A plain text button — iOS has never put a filled pill in a sheet's leading
                // position. `.buttonStyle(.plain)` alone does not get there: the toolbar gives
                // every item its own glass capsule, which is what rendered rgb(26,27,29) behind
                // this word on a rgb(13,14,17) sheet. The shared background has to be dropped
                // from the item, not from the button inside it.
                .chromeSharedBackgroundHidden()
            }
        }
    }
}

// MARK: - Watch history (Surface D)

struct WatchHistoryView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    let franchiseId: String

    @State private var editing: WatchSession?
    @State private var confirmDeleteAll = false

    private var now: Int64 { appModel.now }
    private var store: RewatchStore { RewatchStore.shared }
    private var franchise: Franchise? { appModel.franchise(id: franchiseId) }
    private var sessions: [WatchSession] { store.sessions(for: franchiseId) }

    var body: some View {
        ZStack {
            ThemeColor.canvas.ignoresSafeArea()
            if let f = franchise {
                // The one wash spec (this screen carried a private 280/0.55).
                ArtBackdrop(url: f.landscapeArt ?? f.portraitArt, height: ThemeMetrics.rootWashHeight,
                            intensity: ThemeMetrics.rootWashIntensity)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .ignoresSafeArea(edges: .top)
            }
            if sessions.isEmpty {
                // Centred, not top-pinned. An empty state pinned under the navigation bar with
                // 1 400 pt of canvas under it reads as a screen that failed to load; centred in
                // the content area it reads as the answer to the question the screen asks.
                EmptyState(.noSessions, prominence: .major)
                    .padding(.horizontal, ThemeMetrics.gutter)
                    .padding(.bottom, DetailMetrics.bottomClearance)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
            ScrollView {
                // ONE leading edge for the record. The screen used to run three — an identity
                // poster at 16, the rail at 20, the cards at 40 — with the show's cover printed a
                // second time above a list of sessions that are all the same show. The identity is
                // the navigation bar's job now (title + subtitle), and what is left is the rail:
                // gutter 16 + the rail's own 22-pt gutter puts the cards at 38, exactly where
                // Schedule's rows start, so the app's two rail screens share one grammar.
                VStack(alignment: .leading, spacing: ThemeMetrics.sectionGap) {
                    if sessions.count == 1, let only = sessions.first {
                        // A rail needs two nodes to be a rail. One disconnected ring floating
                        // beside a single card was worse than no timeline at all, so a solo
                        // session is a plain row under its own label.
                        VStack(alignment: .leading, spacing: ThemeMetrics.labelGap) {
                            SectionLabel(text: "Sessions")
                            soloSessionRow(only)
                        }
                    } else {
                        HistoryRail {
                            ForEach(Array(sessions.enumerated()), id: \.element.id) { i, session in
                                // The SCOPE's own artwork. A record of a show with a full art
                                // library was showing zero artwork — the only list in the app that
                                // did. The earlier reasoning ("three identical covers read as
                                // duplicates") was right about the franchise cover and wrong about
                                // the fix: a season-scoped rewatch is a different picture, so the
                                // scope's poster distinguishes the sessions instead of repeating.
                                HistorySessionRow(title: session.title,
                                                  subtitle: sessionLine(session),
                                                  poster: sessionPoster(session),
                                                  active: session.isActive,
                                                  position: position(i, of: sessions.count),
                                                  // The rail's arrival choreography, finally
                                                  // called from production: the segment draws on
                                                  // `uiSweep`, then the node settles. Claimed once,
                                                  // for the session that was just created.
                                                  isNew: RewatchArrival.claim(session.id)) {
                                    editing = session
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, ThemeMetrics.gutter)
                // TOP-ALIGNED. Two cards started ~354 pt down the screen with ~230 pt of
                // unexplained void above them and 400–800 pt below — a record centred in its own
                // scroll view reads as a screen that failed to load, not as an answer. Only a
                // genuinely single or empty state is centred (below); a rail starts at the top,
                // where a list starts.
                .padding(.top, ThemeMetrics.heroClearance)
                // A two-session record is ~240 pt of content above 600 pt of black. That is what a
                // short list looks like, and it is the honest shape.
                .modifier(CentreShortList(active: sessions.count == 1 && !typeSize.isAccessibilitySize))
            }
            .contentMargins(.bottom, DetailMetrics.bottomClearance, for: .scrollContent)
            .scrollIndicators(.hidden)
            }
        }
        // A real navigation bar with a real material, and the show's own name on it: the shipped
        // screen was a hand-built row over hidden chrome, titled "Watch history" and nothing else,
        // so the name of the show whose history it was never appeared anywhere on it.
        .navigationTitle(franchise?.displayTitle ?? Copy.Action.viewWatchHistory.replacingOccurrences(of: "View ", with: "").capitalizedFirst())
        .chromeNavigationSubtitle(historySubtitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarRole(.editor)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !sessions.isEmpty {
                    Menu {
                        Button(role: .destructive) { confirmDeleteAll = true } label: {
                            Label(Copy.Action.deleteWatchHistory, systemImage: "trash")
                        }
                    } label: {
                        // The toolbar item supplies the material; no local glass disc inside it.
                        Image(systemName: "ellipsis")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(ThemeColor.textPrimary)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("More actions")
                }
            }
        }
        .sheet(item: $editing) { session in
            // The sheet sizes itself to its own content (see `SessionDetailView`).
            SessionDetailView(session: session)
        }
        .confirmationDialog(Copy.Confirm.deleteHistoryTitle, isPresented: $confirmDeleteAll, titleVisibility: .visible) {
            Button(Copy.Confirm.deleteHistoryConfirm, role: .destructive) {
                FeedbackCoordinator.fire(.destructive)
                withAnimation(ThemeMotion.pick(ThemeMotion.uiSettle, reduceMotion: reduceMotion)) { store.deleteAll(for: franchiseId) }
            }
            Button(Copy.Confirm.cancel, role: .cancel) {}
        } message: {
            Text(Copy.Confirm.deleteHistory(sessions: sessions.count, episodes: sessions.reduce(0) { $0 + $1.episodes }))
        }
    }

    /// Whose history this is. The shipped screen was one card and 700 pt of void under an inline
    /// title that said "Watch history" and nothing else — the show's name never appeared on it.
    /// The one session, as a record rather than as a media row: what it is called, when it ran,
    /// how many episodes it covered, and the way in.
    private func soloSessionRow(_ session: WatchSession) -> some View {
        let line = sessionLine(session)
        // The same row grammar the rail uses, and the same artwork: a record of a show with a full
        // art library was the one list in the app carrying none.
        return MediaRow(title: session.title,
                        meta: session.isActive ? nil : line,
                        lead: session.isActive ? line : nil,
                        poster: sessionPoster(session), slot: .queue,
                        hint: "Opens this session") {
            editing = session
        }
        .accessibilityLabel("\(session.title), \(line)")
    }

    /// The bar's subtitle: the whole record in one line. It was three stacked `ProgressText`
    /// lines inside the content, under a poster the screen did not need.
    private var historySubtitle: String {
        guard !sessions.isEmpty else { return "" }
        // Only FINISHED sessions contribute to "watched". A rewatch still running has a scope
        // length, not a tally — counting it here is how one noun phrase came to mean two different
        // quantities within one show.
        let episodes = sessions.filter(\.isCompleted).reduce(0) { $0 + $1.episodes }
        var bits = [Copy.watchSessions(sessions.count)]
        if episodes > 0 { bits.append(Copy.episodesWatched(episodes)) }
        return bits.joined(separator: " \u{b7} ")
    }

    /// One session's line, with ONE date formatter behind it.
    ///
    /// Adjacent rows read "24 May – 29 Jul" and "10 Dec, 2024" — two formats, one of them missing
    /// its year and the other punctuated in a way no locale writes. `TemporalCopy.dateRange` orders
    /// and punctuates per locale and states both years whenever the span is not this year's.
    private func sessionLine(_ session: WatchSession) -> String {
        // Every row carries WHEN. Five sessions across four years read as five ordinals and five
        // counts with nothing at all to tell them apart — on the one screen in the app whose entire
        // subject is when things happened. An active session states its start; a finished one its
        // span; a cancelled one where it stopped.
        let started = session.startedAt.flatMap { $0 > 0 ? "Started \(TemporalCopy.dateWord($0, now: now, anchor: .local))" : nil }
        if session.isActive {
            let progress = nextEpisode(session).map { Copy.episodeNext($0) } ?? "In progress"
            return [started, progress].compactMap { $0 }.joined(separator: " \u{b7} ")
        }
        if let cancelled = session.cancelledAtEpisode {
            return [started, "Cancelled at \(Copy.episodeInSentence(cancelled))"]
                .compactMap { $0 }.joined(separator: " \u{b7} ")
        }
        // Predicated only where it is TRUE. `WatchSession.episodes` is the SCOPE's length, so on a
        // finished session it is what was watched and on a running one it is not — "2 episodes
        // watched" beside "Episode 1 next" would be the same class of lie the predication exists to
        // stop, in the other direction.
        let count = session.episodes > 0
            ? (session.isCompleted ? Copy.episodesWatched(session.episodes) : Copy.episodes(session.episodes))
            : nil
        let when: String? = {
            guard let end = session.completedAt, end > 0 else { return started }
            guard let start = session.startedAt, start > 0, start < end else {
                return TemporalCopy.dateWord(end, now: now, anchor: .local)
            }
            return TemporalCopy.dateRange(start, end, now: now)
        }()
        let bits = [when, count].compactMap { $0 }
        return bits.isEmpty ? Copy.Progress.datesUnknown : bits.joined(separator: " \u{b7} ")
    }

    /// The artwork for one session: the season it covers, or the show.
    private func sessionPoster(_ session: WatchSession) -> String? {
        switch session.scope {
        case .franchise: return franchise?.portraitArt
        case .part(let mediaId):
            return franchise?.parts.first { $0.mediaId == mediaId }?.portraitArt ?? franchise?.portraitArt
        }
    }

    private func nextEpisode(_ session: WatchSession) -> Int? {
        guard session.isActive, let f = franchise else { return nil }
        switch session.scope {
        case .franchise: return f.currentPart.map { $0.progress + 1 }
        case .part(let mediaId): return f.parts.first { $0.mediaId == mediaId }.map { $0.progress + 1 }
        }
    }

    private func position(_ i: Int, of n: Int) -> HistoryRailPosition {
        if n == 1 { return .only }
        if i == 0 { return .first }
        if i == n - 1 { return .last }
        return .middle
    }
}

// MARK: - Session detail (Surface E)

struct SessionDetailView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    let session: WatchSession

    @State private var startDate: Date
    @State private var confirmDelete = false
    @State private var confirmStop = false
    /// Measured, so the sheet's detent is the content's own height.
    @State private var contentHeight: CGFloat = 0

    init(session: WatchSession) {
        self.session = session
        _startDate = State(initialValue: session.startedAt.map { Date(timeIntervalSince1970: Double($0) / 1000) } ?? Date())
    }

    private var now: Int64 { appModel.now }
    private var store: RewatchStore { RewatchStore.shared }
    private var franchise: Franchise? { appModel.franchise(id: session.franchiseId) }

    /// The one line that states the whole session: when it ran and how much of it there was, in
    /// the same formatter the row behind the sheet uses.
    ///
    /// The shipped sheet printed four date formats within two taps of each other — "Start date
    /// 24 May 2026" (with a year), "Completed 29 Jul" (without one), "10 Dec, 2024" in the list
    /// behind it and "24 May – 29 Jul" in the row it came from — all hand-assembled, none
    /// localised. Inside a form the year is never implied.
    private var spanLine: String {
        // Predicated only where it is TRUE: `episodes` is the scope's length, which is what was
        // watched on a finished session and is not on a running one.
        let count = session.episodes > 0
            ? (session.isCompleted ? Copy.episodesWatched(session.episodes) : Copy.episodes(session.episodes))
            : nil
        let when: String? = {
            // While the session is still running the start date is NOT stated here: the row below
            // is a date picker showing exactly that date, and "Started 22 Aug 2026" was printed
            // twice, 100–150 pt apart, in one sheet. The count alone is what this line adds.
            guard let end = session.completedAt, end > 0 else { return nil }
            guard let start = session.startedAt, start > 0, start < end else {
                return TemporalCopy.dateWord(end, now: now, anchor: .local)
            }
            return TemporalCopy.dateRange(start, end, now: now)
        }()
        let bits = [when, count].compactMap { $0 }
        return bits.isEmpty ? Copy.Progress.datesUnknown : bits.joined(separator: " \u{b7} ")
    }

    /// Where a stopped session stopped: the progress of the part it covers.
    private var stoppedAtEpisode: Int {
        switch session.scope {
        case .franchise: return franchise?.currentPart?.progress ?? 0
        case .part(let mediaId): return franchise?.parts.first { $0.mediaId == mediaId }?.progress ?? 0
        }
    }

    /// The session's state, on the identity block where the other facts are — not as a form row
    /// with a value in it. A static "Status | In progress" row inside a `GroupedList`, directly
    /// under a real date picker, looked exactly as tappable as the picker and was not.
    private var statusLine: String? {
        if session.isActive { return "In progress" }
        if session.cancelledAtEpisode != nil { return "Stopped" }
        return nil
    }

    /// The scope, in the app's own vocabulary.
    private var scopeLine: String? {
        switch session.scope {
        case .franchise: return DetailCopy.everything
        case .part(let mediaId):
            let label = franchise?.canonicalPartLabel(for: mediaId) ?? ""
            return label.isEmpty ? nil : label
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ThemeMetrics.sectionGap) {
                    // A SUMMARY, not a form. The sheet used to open on four label/value rows with
                    // no artwork, no title and no indication of which show it belonged to — and
                    // "Status: Completed" sat directly above "Completed: 29 Jul", so the word was
                    // both a value and a field label in adjacent rows while proving nothing the
                    // completion date did not already prove.
                    HStack(alignment: .top, spacing: ThemeMetrics.artGap) {
                        PosterSlot(url: franchise?.portraitArt, .row)
                        VStack(alignment: .leading, spacing: ThemeMetrics.titleGap) {
                            Text(franchise?.title ?? session.title)
                                .type(ThemeType.showTitleM)
                                .foregroundStyle(ThemeColor.textPrimary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                            // The scope, not the session's own name: the sheet's title already
                            // says "Second watch" 40 pt above this line.
                            Text(scopeLine ?? session.title)
                                .type(ThemeType.heroMeta)
                                .foregroundStyle(ThemeColor.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(spanLine)
                                .type(ThemeType.metadata)
                                .foregroundStyle(ThemeColor.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                            // The state, as a FACT on the identity block. It was a form row whose
                            // value looked like a control and was not.
                            if let statusLine {
                                Text(statusLine)
                                    .type(ThemeType.rowMetaLead)
                                    .foregroundStyle(session.isActive ? ThemeColor.accent : ThemeColor.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    GroupedList {
                        // The one thing on this sheet that is genuinely editable, and now the only
                        // row on it. A real `.compact` date picker, with the label and value the
                        // accessibility layer needs.
                        HStack {
                            Text("Started").type(ThemeType.body).foregroundStyle(ThemeColor.textPrimary)
                            Spacer()
                            DatePicker("Started", selection: $startDate, in: ...Date(), displayedComponents: .date)
                                .datePickerStyle(.compact)
                                .labelsHidden().tint(ThemeColor.accent)
                        }
                        .padding(.leading, 14).padding(.trailing, 10)
                        .frame(minHeight: ThemeMetrics.rowCompact)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Start date")
                        .accessibilityHint("Changes the date this watch began")
                        // `Finished` keeps its row — a date is a fact with a value, which is what a
                        // form row is for. The "Status" row that used to sit here is gone: it stated
                        // what the identity block now states, and it was the fake-editable pill.
                        if let completed = session.completedAt, completed > 0 {
                            GroupedRow(title: "Finished",
                                       trailing: .value(TemporalCopy.dateWord(completed, now: now, anchor: .local)),
                                       separator: false)
                        }
                    }
                    // ENDING a session, which the sheet never offered.
                    //
                    // `RewatchStore.complete(_:at:)` existed and was called only from the mark path,
                    // so a user who abandoned a rewatch at episode 26 could only DESTROY the record
                    // — leaving the "In progress" badge and the rail's accent ring lit for ever and
                    // Today still offering the rewatch. Two non-destructive verbs, above the
                    // destructive plate, where iOS puts them.
                    if session.isActive {
                        GroupedList {
                            GroupedRow(title: DetailCopy.markRewatchComplete, separator: true) {
                                FeedbackCoordinator.fire(.success)
                                store.complete(session.id, at: now)
                                dismiss()
                            }
                            GroupedRow(title: DetailCopy.stopRewatch, separator: false) {
                                confirmStop = true
                            }
                        }
                    }
                    // A destructive verb is a ROW in its own plate, not a red word floating
                    // centred under a void.
                    Button { confirmDelete = true } label: {
                        HStack {
                            Text(Copy.Action.deleteThisSession)
                                .type(ThemeType.body)
                                .foregroundStyle(ThemeColor.destructive)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 14)
                        .frame(minHeight: ThemeMetrics.rowCompact)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(GroupedRowPressStyle())
                    .surface(.plate, radius: ThemeRadius.row)
                }
                .padding(.horizontal, ThemeMetrics.gutter)
                .padding(.top, ThemeSpace.x4)
                .padding(.bottom, ThemeSpace.x6)
                // The sheet is exactly as tall as what is in it. At `.medium` it left 105–600 pt of
                // dead plate below the last group.
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(ThemeColor.canvasRaised.ignoresSafeArea())
            .navigationTitle(session.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    // Plain bold text, for the same reason `Cancel` is plain text on the rewatch
                    // sheet: the toolbar wraps every item in its own glass capsule, and a filled
                    // pill is not what iOS puts in a sheet's confirm slot.
                    Button {
                        let ts = Int64(startDate.timeIntervalSince1970 * 1000)
                        if ts != session.startedAt { store.setStartDate(session.id, to: ts) }
                        dismiss()
                    } label: {
                        Text(Copy.Action.done)
                            .type(ThemeType.bodyEmphasis)
                            .foregroundStyle(ThemeColor.interactive)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .buttonStyle(RowPressStyle(radius: ThemeRadius.compactControl))
                }
                .chromeSharedBackgroundHidden()
            }
            .confirmationDialog(Copy.Confirm.deleteSessionTitle, isPresented: $confirmDelete, titleVisibility: .visible) {
                Button(Copy.Confirm.deleteSessionConfirm, role: .destructive) {
                    FeedbackCoordinator.fire(.destructive)
                    store.delete(session.id)
                    dismiss()
                }
                Button(Copy.Confirm.cancel, role: .cancel) {}
            } message: {
                Text(Copy.Confirm.deleteSession(count: session.episodes))
            }
            // Stopping keeps the record and states where it stopped; it is not a deletion, so it
            // does not use the destructive verb's copy.
            .confirmationDialog("Stop this rewatch?", isPresented: $confirmStop, titleVisibility: .visible) {
                Button("Stop rewatch", role: .destructive) {
                    // Stopping keeps the record: a commit, not a deletion (review i2).
                    FeedbackCoordinator.fire(.commitLight)
                    store.cancel(session.id, atEpisode: stoppedAtEpisode, at: now)
                    dismiss()
                }
                Button(Copy.Confirm.cancel, role: .cancel) {}
            } message: {
                Text("The session stays in your history, stopped at \(Copy.episodeInSentence(stoppedAtEpisode)). Your progress is not changed.")
            }
        }
        .presentationDetents([.height(min(max(contentHeight + 64, 260), 620)), .large])
        .presentationDragIndicator(.visible)
    }
}

/// Centres a short list in the scroll view's own height rather than pinning it under the bar with
/// several hundred points of black beneath it. Off at accessibility sizes, where the content is
/// taller than the container and has to scroll from the top.
struct CentreShortList: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            content.containerRelativeFrame(.vertical, alignment: .center)
        } else {
            content
        }
    }
}

private extension String {
    func capitalizedFirst() -> String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
