import SwiftUI
import UserNotifications

// Search (spec board 07). Empty query = the launchpad; a query = results.
//
// Fix round 1. The panel scored this the lowest screen in the build (median 3.5). What changed:
//
//  • **The field is the system's again.** `Tab(value:role: .search)` exists specifically to pair
//    with `.searchable`, and the screen hand-rolled a `TextField` inside a header with the
//    navigation bar hidden — throwing away the iOS 26 search morph, Cancel, the scope bar, the
//    keyboard's return semantics and the localised prompt, and gaining nothing. `.searchable` +
//    `.searchScopes` now do all of it, which also deletes the hand-drawn scope pills (a segmented
//    control drawn as three outlined web buttons) and the Material-Design progress rail that sat
//    under the field for an indeterminate network call.
//  • **One add control.** It used to be ~25 pt over art, 55×43 in a row and a bare grey checkmark
//    once added — three anatomies, one of them below the touch minimum, one of them not a control
//    at all. `AddControl` is one component, 44 pt, same width in both states, live in both.
//  • **One ranking.** Ranks 01–04 were poster cards and 05+ were text rows with the numeral in a
//    separate 50-pt gutter at `textDisabled`. Now: TOP 3 on the shelf, MORE TRENDING as rows, one
//    gutter, one add control.
//  • **The payoff frame is never emptier than the question.** A single result used to be one card
//    under a "TOP MATCH" label with 900 pt of black beneath it, and both the no-results and the
//    error state threw away artwork already decoded in order to say one sentence. Trending stays
//    mounted underneath in every one of those states, and the result count gives the void a
//    boundary.
//  • **"Parts" is gone**, the kind leads every result's metadata (the anime One Piece and the
//    live-action One Piece were distinguishable only by capitalisation at the moment of adding),
//    and `correctedQuery` — decoded since day one and read by nothing — is on screen.
//
// Fix round 2 (the audit). The rows and the shelf are the app's `MediaRow` and `ShelfCard` — the
// same objects Library, Schedule and Detail render — instead of a third hand-rolled pair; the
// owned tick opens a status menu instead of unsubscribing on contact; a failed catalogue is named
// above the rows that did arrive; the scope filters the chart as well as the results; and every
// string on the screen lives in `Copy.Search`.
struct DiscoverView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    let onOpenDetail: (_ franchiseId: String, _ zoomID: String) -> Void

    /// How many of the chart's entries get the big art treatment before it continues as rows.
    private static let featuredCount = 3
    /// The wire marker for a catalogue that failed (`docs/api-contract.md`, `sources`). Not copy.
    private static let failedMarker = "failed"

    /// The scroll view's own height, for centring a state that owns the whole surface.
    @State private var contentH: CGFloat = 0
    /// `.searchable(isPresented:)`. Raised by `AppModel.searchFieldRequested` — an "Add a show"
    /// CTA on another tab asked for the field itself, not just this tab.
    @State private var fieldPresented = false

    // MARK: Notification primer (see `notificationPrimer`)

    /// An add that stuck armed the primer. Persisted, because the ask is deferred well past the
    /// undo window and the user may leave the tab in the meantime — a `@State` flag would drop it.
    @AppStorage("previously.notifPrimerPending") private var primerPending = false
    /// The user has answered the primer once. iOS only ever shows its own alert once per install,
    /// so the primer is one-shot too: it is the thing that earns that one alert.
    @AppStorage("previously.notifPrimerAnswered") private var primerAnswered = false
    /// Resolved from `UNUserNotificationCenter`: only `.notDetermined` can still be asked.
    @State private var canAskForNotifications = false
    @State private var primerVisible = false

    /// Minute precision is all a "New episode tomorrow" needs; observing the 20-second tick would
    /// re-lay out every row on the screen three times a minute for nothing.
    private var now: Int64 { appModel.nowMinute }
    private var query: String { appModel.searchQuery.trimmingCharacters(in: .whitespaces) }
    private var isAX: Bool { typeSize.isAccessibilitySize }

    /// The ambient wash is keyed to the chart's leader: a poster this screen is already loading,
    /// so the atmosphere costs one decode and never changes under the user mid-session — not even
    /// when the scope hides it from the chart.
    private var washURL: String? { appModel.trending.first?.cover }

    var body: some View {
        @Bindable var model = appModel
        // Computed ONCE per body and handed down. `filteredSearchResults` is a filter over the
        // whole result set and the body used to read it eight times — and the duplicate-title scan
        // inside `ResultSet` ran once per ROW on top of that.
        let results = ResultSet(appModel.filteredSearchResults)
        // The chart honours the scope. With TV selected the results were TV-only and the chart
        // underneath them still led with an anime, so the scope bar appeared to govern half the
        // screen.
        let trending = appModel.trending.filter { appModel.matchesMediaFilter($0.source) }
        return ZStack(alignment: .top) {
            ThemeColor.canvas.ignoresSafeArea()
            // The wash runs to the very top of the screen, status bar included; the soft top veil
            // only settles it under the title. No opaque band anywhere (user, 24 Aug).
            ArtBackdrop(url: washURL, height: ThemeMetrics.rootWashHeight,
                        intensity: ThemeMetrics.rootWashIntensity)
                .ignoresSafeArea(edges: .top)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if primerVisible { notificationPrimer }
                    // The launchpad and the results are two entirely different view trees in one
                    // slot, so SwiftUI's default crossfade dissolved three 124×186 posters and a
                    // numbered chart THROUGH a list of rows for 220 ms — the double-exposure class
                    // of artefact, on this screen's one structural change. `handoff` is the app's
                    // one answer to that: the outgoing tree leaves first, the incoming settles into
                    // the space it left.
                    Group {
                        if query.isEmpty {
                            launchpad(trending: trending)
                        } else {
                            searchBody(results, trending: trending)
                        }
                    }
                    .id(query.isEmpty)
                    .transition(.handoff(reduceMotion: reduceMotion))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(ThemeMotion.pick(ThemeMotion.uiGentle, reduceMotion: reduceMotion), value: query.isEmpty)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            // A content MARGIN, not `.padding` inside the stack: padding under a stack that is
            // shorter than the viewport changes no layout at all, which is exactly the case the
            // launchpad is in — and it is why the sixth chart row came to rest inside the bottom
            // ramp with its enabled `+` at 131/255 against 241 for the identical control four rows
            // higher. The margin is honoured either way and the scroll indicator stops with it.
            .tabBarContentMargin()
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentH = $0 }
        }
        // The top edge belongs to the navigation bar and the search field now, so only the bottom
        // is ours — but it IS ours in both states. `scrollDismissesKeyboard(.interactively)` means
        // a scrolled results list ends up with the tab bar, not the keyboard, over its last row,
        // and the shipped build passed `bottom: false` on the assumption the keyboard owned the
        // bottom: which is how a saturated poster came to refract a doubled, mirrored show title
        // through the tab bar's glass and put an amber rim on the *Today* pill while Search was
        // the active tab.
        // The bottom edge is ours; the TOP is the bar's own veil (`rootBarVeil`) — the same
        // gradient the tab bar's edge carries, "relayed upwards" to the title (user, 24 Aug), drawn
        // from the very top of the screen — over the wash the navigation container paints
        // (`rootWash`): the launchpad used to open on flat near-black while every other root
        // carried its art.
        .scrollEdgeChromeBody(top: true, bottom: true,
                              topHeight: ThemeMetrics.topSafeInset + Metrics.searchDrawerHeight,
                              softTop: true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .scrollEdgeEffectHidden(true, for: .all)
        // Inline on every root (user decision): the field is the screen's identity here, and a
        // large title over it put two headlines on one screen.
        .navigationTitle(Copy.Search.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        // The field lives UNDER the title, always — Apple Music's Search (user reference, 24 Aug):
        // title, field, then the browse grid; focused, the field pins to the top with Cancel, the
        // scope bar appears and the recents take the page. Search is an ordinary tab in the one
        // tab pill now, not the separated search island, which is what let the field move here.
        // The prompt names the VERB, not the domain, and it follows the scope — see
        // `Copy.Search.prompt(for:)`.
        .searchable(text: $model.searchQuery, isPresented: $fieldPresented,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: Copy.Search.prompt(for: appModel.mediaFilter))
        // A catalogue query is not a sentence. Without these the system field capitalises the
        // first letter and autocorrects romaji titles into English words ("Sousou" → "Season"),
        // both of which the hand-rolled field had correctly turned off.
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        // `.onSearchPresentation`, not the default: the scope bar existed only once the field had
        // text, so the launchpad — the screen every first-run user lands on — showed a scope circle
        // and no scope, and the active scope was communicated solely by a placeholder that vanished
        // on the first keystroke.
        .searchScopes($model.mediaFilter, activation: .onSearchPresentation) {
            ForEach(MediaFilter.allCases, id: \.self) { filter in
                // The segment labels are ours; the bar around them is the system's. At AX1 they
                // were measured at exactly the same cap height as at the default size — the only
                // controls on the screen still at default size, so the whole bar read as a strip
                // borrowed from another app. A text style, so they scale with everything else.
                Text(Copy.Search.scopeWord(filter))
                    .font(.system(.footnote, weight: .semibold))
                    .tag(filter)
            }
        }
        // The field always carried a `.search` return key and then threw the submission away, so
        // RECENT could only ever hold terms left over from an older build.
        .onSubmit(of: .search) { appModel.recordRecentSearch() }
        .onAppear {
            appModel.loadTrendingIfNeeded()
            consumeFieldRequest()
            #if DEBUG
            // `-openSearchField 1` (DEBUG, like `-recapDemo`): open with the field focused. A
            // beat after appearance, or the searchable binding's first sync overwrites it.
            if UserDefaults.standard.bool(forKey: "openSearchField") {
                Task { try? await Task.sleep(for: .milliseconds(700)); fieldPresented = true }
            }
            #endif
        }
        // The CTA may fire while this tab is already mounted, in which case `onAppear` does not.
        .onChange(of: appModel.searchFieldRequested) { _, requested in
            if requested { consumeFieldRequest() }
        }
        .task(id: appModel.library.count) { await refreshNotificationEligibility() }
        .task { await refreshNotificationEligibility() }
        // WCAG 4.1.3. A VoiceOver user typed a query and results arrived, or didn't, or failed,
        // and nothing was spoken.
        .onChange(of: appModel.searchBusy) { _, busy in
            guard !busy, !query.isEmpty else { return }
            announceOutcome()
        }
        .onChange(of: appModel.mediaFilter) { _, _ in
            FeedbackCoordinator.fire(.selection)
            guard !query.isEmpty, !appModel.searchBusy else { return }
            announceOutcome()
        }
    }

    /// "Add a show" elsewhere asked for the field. Present it once and clear the request, so a
    /// later plain tab switch does not re-raise the keyboard.
    private func consumeFieldRequest() {
        guard appModel.searchFieldRequested else { return }
        fieldPresented = true
        appModel.searchFieldRequested = false
    }

    // MARK: - The notification ask

    /// **The system permission alert is never raised by an add.**
    ///
    /// `addToLibrary` used to set the undo state and then immediately raise the notification
    /// prompt, so the app's first-ever permission ask arrived unprimed, in the middle of an
    /// unrelated action, over the trending grid — with "Added … — Undo" counting down *underneath*
    /// a modal the user could not dismiss without answering. The Undo was unreachable for its whole
    /// six seconds and had expired by the time they got back to it, VoiceOver focus was stolen, and
    /// the reflex answer to an unexplained ask is Don't Allow — after which iOS never asks again
    /// and episode alerts are dead for that account permanently.
    ///
    /// So: the add arms this, and nothing else happens for the whole undo window. Once the add has
    /// *stuck*, the user gets a card that says what the permission buys, on their own screen, with
    /// a control they choose to press. The system alert only ever follows the user asking for it,
    /// which is what the HIG requires. Answered once, either way, it never appears again — Profile →
    /// Notifications is the permanent route.
    private var notificationPrimer: some View {
        VStack(alignment: .leading, spacing: ThemeSpace.x3) {
            HStack(alignment: .top, spacing: ThemeSpace.x3) {
                // `EmptyState`'s grammar, because that is what this card is: a quiet tile, a
                // `textTertiary` glyph, and exactly ONE accent object — the button. An accent
                // glyph in an accent tile beside an accent capsule is two things claiming to be
                // the point.
                Image(systemName: "bell.badge")
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(ThemeColor.textTertiary)
                    .frame(width: Metrics.primerGlyphTile, height: Metrics.primerGlyphTile)
                    .background(ThemeColor.surfaceRaised, in: Circle())
                VStack(alignment: .leading, spacing: ThemeMetrics.titleGap) {
                    Text(Copy.Search.primerTitle)
                        .type(ThemeType.showTitleM)
                        .foregroundStyle(ThemeColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(Copy.Search.primerBody)
                        .type(ThemeType.rowMeta)
                        .foregroundStyle(ThemeColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // Keeps the copy clear of the dismiss disc in the corner.
                Spacer(minLength: ThemeSpace.x8)
            }
            Button(Copy.Search.primerTurnOn) { answerPrimer(turnOn: true) }
                .buttonStyle(PrimaryButtonStyle2())
        }
        .padding(ThemeSpace.x4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(.plate, radius: ThemeRadius.card)
        // Dismissal is the app's own disc, not a second amber word beside the affirmative one —
        // "Turn on" in a grey capsule next to "Not now" in amber had the accent on the answer the
        // card is not asking for.
        .overlay(alignment: .topTrailing) { primerDismiss }
        .padding(.horizontal, ThemeMetrics.gutter)
        .padding(.top, ThemeMetrics.sectionGap)
        .accessibilityElement(children: .contain)
    }

    private var primerDismiss: some View {
        Button { answerPrimer(turnOn: false) } label: {
            Image(systemName: "xmark")
                .font(.system(.caption2, weight: .bold))
                .foregroundStyle(ThemeColor.textTertiary)
                .frame(width: Metrics.dismissDisc, height: Metrics.dismissDisc)
                .background(ThemeColor.surfaceRaised, in: Circle())
                .overlay(Circle().strokeBorder(ThemeColor.posterEdge, lineWidth: 1))
                .frame(width: Metrics.hitTarget, height: Metrics.hitTarget)
                .contentShape(Circle())
        }
        .accessibilityLabel(Copy.Search.primerNotNow)
        .padding(ThemeSpace.x1)
    }

    private func answerPrimer(turnOn: Bool) {
        primerAnswered = true
        primerPending = false
        withAnimation(ThemeMotion.pick(ThemeMotion.uiSettle, reduceMotion: reduceMotion)) {
            primerVisible = false
        }
        guard turnOn else { return }
        Task {
            _ = await EpisodeNotifications.shared.requestPermissionIfNeeded()
            await refreshNotificationEligibility()
        }
    }

    /// Only `.notDetermined` can still be asked; anything else and the primer would be a card that
    /// promises a system alert iOS will never show.
    ///
    /// The notification-centre round trip happens only while there is a primer to show. It used to
    /// run on every library change for every user, forever — including the ones who answered the
    /// primer on day one.
    private func refreshNotificationEligibility() async {
        guard primerPending, !primerAnswered else {
            if primerVisible { primerVisible = false }
            return
        }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        canAskForNotifications = settings.authorizationStatus == .notDetermined
        let shouldShow = canAskForNotifications
        guard shouldShow != primerVisible else { return }
        withAnimation(ThemeMotion.pick(ThemeMotion.uiSettle, reduceMotion: reduceMotion)) {
            primerVisible = shouldShow
        }
    }

    /// Arms the primer for one airing anime add, once the write has had the whole undo window to
    /// stick. TMDB air times are synthesised, so a TV-only add buys the user nothing and asks for
    /// nothing.
    private func armNotificationPrimer(_ item: FranchiseSummary) {
        guard item.isReleasing, item.source == .anilist, !primerAnswered else { return }
        Task {
            try? await Task.sleep(nanoseconds: UInt64((SyncCenter.shared.toastSeconds + 0.5) * 1_000_000_000))
            guard appModel.isInLibrary(item.id) else { return }
            primerPending = true
            await refreshNotificationEligibility()
        }
    }

    // MARK: - Outcome (spoken)

    /// Speaks the SAME title the visible state shows. It used to announce the anime catalogue's
    /// notice for a server error and the no-results title for a scoped-out set.
    private func announceOutcome() {
        Announce.status(outcomeTitle(ResultSet(appModel.filteredSearchResults)))
    }

    private func outcomeTitle(_ results: ResultSet) -> String {
        if scopedOut(results) { return scopedOutCopy.title }
        if results.isEmpty {
            return appModel.searchError ? errorCopy.title
                                        : EmptyStateCopy.noSearchResults(query: query).title
        }
        var parts = [Copy.Search.results(results.count)]
        if appModel.searchError { parts.append(Copy.Search.couldNotRefresh) }
        parts += catalogueNotices
        return parts.joined(separator: ". ")
    }

    // MARK: - States, as data

    /// The scope, not the query, emptied the list.
    private func scopedOut(_ results: ResultSet) -> Bool {
        appModel.mediaFilter != .all && results.isEmpty && !appModel.searchResults.isEmpty
    }

    private var scopedOutCopy: EmptyStateCopy {
        .noScopeMatches(scope: Copy.Search.scopeWord(appModel.mediaFilter), query: query)
    }

    /// `searchFailed` carries the wifi glyph and "check your connection", so it is the OFFLINE
    /// copy; the shipped build showed it while online and showed the library's "connect to load
    /// your library" while offline — both branches wrong, on a screen that has nothing to do with
    /// the library.
    private var errorCopy: EmptyStateCopy {
        SyncCenter.shared.isOnline ? .serverNoCache : .searchFailed
    }

    /// One catalogue failed while the other answered. `/search` names the outcome per source
    /// (`ok` / `failed` / `disabled`); a catalogue that failed is not a catalogue with no matches,
    /// so the rows that did arrive get a notice above them rather than standing in for the whole
    /// answer. Filtered by scope: an anime notice over a TV-only list names a failure the user
    /// cannot see.
    private var catalogueNotices: [String] {
        guard let sources = appModel.searchSources else { return [] }
        var out: [String] = []
        if sources[MediaSource.anilist.rawValue] == Self.failedMarker,
           appModel.matchesMediaFilter(.anilist) {
            out.append(Copy.Notice.searchAnime)
        }
        if sources[MediaSource.tmdb.rawValue] == Self.failedMarker,
           appModel.matchesMediaFilter(.tmdb) {
            out.append(Copy.Notice.searchTV)
        }
        return out
    }

    // MARK: - Launchpad

    /// Apple Music's two pages in one slot. At rest: the browse grid — trending, as art tiles.
    /// Focused with nothing typed: ONLY what belongs to a focused field — what you searched
    /// before, as rows of the shows themselves, or a quiet prompt. Never the tile grid: two
    /// columns of art crushed under the keyboard read as noise, not as a place to type.
    @ViewBuilder
    private func launchpad(trending: [FranchiseSummary]) -> some View {
        let recentsEmpty = appModel.recentItems.isEmpty && appModel.recentSearches.isEmpty
        VStack(alignment: .leading, spacing: 0) {
            if fieldPresented {
                // The focused page is a LIST, top to bottom: what you searched before, then what
                // everyone is watching — the same compact rows, so it never ends on a cliff after
                // one recent term.
                if !recentsEmpty {
                    recentsList.padding(.top, ThemeSpace.x2)
                }
                if !trending.isEmpty {
                    trendingList(trending)
                        .padding(.top, recentsEmpty ? ThemeSpace.x2 : ThemeMetrics.sectionGap)
                } else if recentsEmpty {
                    EmptyState(.searchLaunchpad, prominence: .section)
                        .padding(.horizontal, ThemeMetrics.gutter)
                        .padding(.top, ThemeMetrics.sectionGap)
                }
            } else if !trending.isEmpty {
                trendingTiles(trending).padding(.top, ThemeSpace.x2)
            } else if !SyncCenter.shared.isOnline {
                // No grid and no connection: say so. "Find your next show" over a grid that will
                // never load is a promise, and the path monitor knows it is an empty one.
                EmptyState(.searchOffline, primary: { appModel.loadTrendingIfNeeded() })
                    .padding(.horizontal, ThemeMetrics.gutter)
                    .centredState(contentH: contentH)
            } else {
                EmptyState(.searchLaunchpad)
                    .padding(.horizontal, ThemeMetrics.gutter)
                    .centredState(contentH: contentH)
            }
        }
        // Focus swaps the grid for the recents; the swap is a gentle cross-dissolve, not a snap.
        .animation(ThemeMotion.pick(ThemeMotion.uiGentle, reduceMotion: reduceMotion), value: fieldPresented)
    }

    // MARK: Browse grid

    /// Trending as a two-column wall of art tiles — the show's banner (its cover when it has
    /// none) filling the tile, the name over a dark foot. One column at accessibility sizes.
    private func trendingTiles(_ trending: [FranchiseSummary]) -> some View {
        let columns = isAX ? 1 : 2
        return VStack(alignment: .leading, spacing: ThemeMetrics.labelGap) {
            SectionHeaderRow(Copy.Search.trendingNow)
                .padding(.horizontal, ThemeMetrics.gutter)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: ThemeMetrics.shelfGap),
                                     count: columns),
                      spacing: ThemeMetrics.shelfGap) {
                ForEach(trending) { item in tile(item) }
            }
            .padding(.horizontal, ThemeMetrics.gutter)
        }
    }

    private func tile(_ item: FranchiseSummary) -> some View {
        let zoom = "trend/\(item.id)"
        let shape = RoundedRectangle(cornerRadius: ThemeRadius.card, style: .continuous)
        return Button { open(item, zoom: zoom) } label: {
            // The sizing element is an empty rectangle at the tile's ratio; the art fills it as
            // an overlay so a portrait cover can never stretch the cell.
            Color.clear
                .aspectRatio(Metrics.tileAspect, contentMode: .fit)
                .overlay {
                    RemoteImageView(url: item.banner ?? item.cover, contentMode: .fill,
                                    maxPixel: Metrics.tileMaxPixel)
                        .zoomSource(zoom)
                }
                .overlay {
                    // The foot the name sits on: canvas rising from nothing at the tile's middle.
                    LinearGradient(colors: [.clear, ThemeColor.canvas.opacity(Metrics.tileFoot)],
                                   startPoint: .center, endPoint: .bottom)
                }
                .overlay(alignment: .bottomLeading) {
                    Text(item.title.shelfShortened)
                        .type(ThemeType.showTitleM)
                        .foregroundStyle(ThemeColor.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .multilineTextAlignment(.leading)
                        .padding(ThemeSpace.x3)
                }
                .background(ThemeColor.surfaceRaised)
                .clipShape(shape)
                .overlay(shape.strokeBorder(ThemeColor.posterEdge, lineWidth: 1))
                .contentShape(shape)
        }
        .buttonStyle(RowPressStyle(radius: ThemeRadius.card))
        .accessibilityLabel(spoken(item, ambiguous: []))
        .accessibilityHint(Copy.Accessibility.opensTheShowHint)
        .overlay(alignment: .topTrailing) {
            addControl(item, placement: .overArt).padding(Metrics.overArtControlInset)
        }
        .franchiseQuickActions(appModel.franchise(id: item.id), appModel: appModel)
        .accessibilityElement(children: .contain)
    }

    // MARK: Recently searched

    /// The shows you acted on from a search, as the app's rows, then any bare terms left over.
    /// One Clear for the lot; one row at a time from its long-press.
    private var recentsList: some View {
        let items = appModel.recentItems
        let terms = appModel.recentSearches
        return VStack(alignment: .leading, spacing: ThemeMetrics.labelGap) {
            SectionHeaderRow(Copy.Search.recentlySearched, actionLabel: Copy.Action.clear) {
                withAnimation(ThemeMotion.pick(ThemeMotion.uiSnappy, reduceMotion: reduceMotion)) {
                    appModel.clearRecents()
                }
            }
            .padding(.horizontal, ThemeMetrics.gutter)
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                    let zoom = "recent/\(item.id)"
                    // `.queue` (44×66): Apple Music's recents density, and the same 44-pt left
                    // edge the bare-term rows' glyph tile sits on, so every title in the list
                    // starts at one x.
                    MediaRow(title: item.title,
                             meta: shelfFacts(item).joined(separator: FactLine.separator),
                             poster: item.cover,
                             slot: .queue,
                             separator: i < items.count - 1 || !terms.isEmpty,
                             hint: Copy.Accessibility.opensTheShowHint,
                             zoomID: zoom) {
                        open(item, zoom: zoom)
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            withAnimation(ThemeMotion.pick(ThemeMotion.uiSnappy, reduceMotion: reduceMotion)) {
                                appModel.removeRecentItem(item.id)
                            }
                        } label: {
                            Label(Copy.Search.removeRecent, systemImage: "trash")
                        }
                    }
                }
                ForEach(Array(terms.enumerated()), id: \.element) { i, term in
                    termRow(term, separator: i < terms.count - 1)
                }
            }
            .padding(.horizontal, ThemeMetrics.gutter)
        }
    }

    /// Trending, as the focused page's second section: the same compact rows the recents use,
    /// capped so the list stays a list and not the grid again.
    private func trendingList(_ trending: [FranchiseSummary]) -> some View {
        let items = Array(trending.prefix(Metrics.focusedTrendingCount))
        return VStack(alignment: .leading, spacing: ThemeMetrics.labelGap) {
            SectionHeaderRow(Copy.Search.trendingNow)
                .padding(.horizontal, ThemeMetrics.gutter)
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                    let zoom = "trendrow/\(item.id)"
                    MediaRow(title: item.title,
                             meta: shelfFacts(item).joined(separator: FactLine.separator),
                             poster: item.cover,
                             slot: .queue,
                             separator: i < items.count - 1,
                             hint: Copy.Accessibility.opensTheShowHint,
                             zoomID: zoom) {
                        open(item, zoom: zoom)
                    }
                    .franchiseQuickActions(appModel.franchise(id: item.id), appModel: appModel)
                }
            }
            .padding(.horizontal, ThemeMetrics.gutter)
        }
    }

    /// A bare term. Three decisions, each against what the row was:
    ///  * the tile is a CIRCLE in the field's own colours (accent glyph on `accentSoft`) — it is a
    ///    search, not a poster, and a grey square beside art tiles read as a poster that failed;
    ///  * a second line, `Copy.Search.termKind`, so the row has the same two-line anatomy as the
    ///    media rows around it instead of one bold word floating in a 60-pt band;
    ///  * the trailing glyph is the fill-the-field arrow, not a chevron. A chevron promises a push;
    ///    this row puts the words back in the field (Safari's and YouTube's convention).
    private func termRow(_ term: String, separator: Bool) -> some View {
        let tile = PosterSize.queue.size.width
        return Button { appModel.searchQuery = term } label: {
            HStack(spacing: ThemeMetrics.artGap) {
                Image(systemName: "magnifyingglass")
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(ThemeColor.accent)
                    .frame(width: tile, height: tile)
                    .background(ThemeColor.accentSoft, in: Circle())
                VStack(alignment: .leading, spacing: ThemeMetrics.titleGap) {
                    Text(term)
                        .type(ThemeType.rowTitle)
                        .foregroundStyle(ThemeColor.textPrimary)
                        .lineLimit(1)
                    Text(Copy.Search.termKind)
                        .type(ThemeType.rowMeta)
                        .foregroundStyle(ThemeColor.textSecondary)
                }
                Spacer(minLength: ThemeSpace.x3)
                Image(systemName: "arrow.up.backward")
                    .font(.system(size: Metrics.chevronSize, weight: .semibold))
                    .foregroundStyle(ThemeColor.textTertiary)
                    .frame(width: Metrics.chevronColumn, alignment: .trailing)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, ThemeSpace.x2)
            .frame(minHeight: Metrics.termRowHeight)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                if separator {
                    Rectangle().fill(ThemeColor.separatorQuiet).frame(height: 1)
                        .padding(.leading, tile + ThemeMetrics.artGap)
                }
            }
        }
        .buttonStyle(RowPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(term), \(Copy.Search.termKind)")
        .accessibilityHint(Copy.Search.termHint)
        .contextMenu {
            Button(role: .destructive) {
                withAnimation(ThemeMotion.pick(ThemeMotion.uiSnappy, reduceMotion: reduceMotion)) {
                    appModel.removeRecentSearch(term)
                }
            } label: {
                Label(Copy.Search.removeRecent, systemImage: "trash")
            }
        }
    }

    /// Trending as ONE chart in two densities: the top three carry full `.shelfLarge` artwork,
    /// the rest continue as rows under their own label. The add control is the same object in
    /// both, and the row gutter is the screen's gutter — the shipped build's 50-pt rank column
    /// made ranks 05+ look like a different list.
    private func trendingChart(_ trending: [FranchiseSummary]) -> some View {
        let ranked = Array(trending.enumerated())
        // At accessibility sizes the shelf goes away entirely: a 124-pt column cannot hold an AX
        // title, and the alternative is a shelf whose every caption ends in an ellipsis. The chart
        // becomes rows, which reflow honestly, and the ranks then run unbroken from 01.
        let featured = isAX ? [] : Array(ranked.prefix(DiscoverView.featuredCount))
        let rest = isAX ? ranked : Array(ranked.dropFirst(DiscoverView.featuredCount))
        return VStack(alignment: .leading, spacing: 0) {
            SectionHeaderRow(Copy.Search.trendingNow)
                .padding(.horizontal, ThemeMetrics.gutter)

            if !featured.isEmpty {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: ThemeMetrics.shelfGap) {
                        ForEach(featured, id: \.element.id) { i, item in
                            trendingCard(rank: i + 1, item)
                        }
                    }
                    .padding(.leading, ThemeMetrics.gutter)
                    .padding(.vertical, ThemeSpace.x1)
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
                // Art may run off the trailing edge; TYPE may not. See `shelfScroller`.
                .shelfScroller()
                .padding(.top, ThemeMetrics.labelGap)
            }

            if !rest.isEmpty {
                if !featured.isEmpty {
                    SectionHeaderRow(Copy.Search.moreTrending)
                        .padding(.horizontal, ThemeMetrics.gutter)
                        .padding(.top, ThemeMetrics.sectionGap)
                }
                VStack(spacing: 0) {
                    ForEach(rest, id: \.element.id) { i, item in
                        chartRow(rank: i + 1, item, isLast: item.id == rest.last?.element.id)
                    }
                }
                .padding(.horizontal, ThemeMetrics.gutter)
                .padding(.top, ThemeMetrics.labelGap)
            }
        }
    }

    /// A chart leader on the shelf — the app's `ShelfCard`, with the rank leading its caption.
    ///
    /// The numeral used to be painted over the artwork, where "03" landed on the poster's own title
    /// lockup on the first screen a new user and a reviewer see. Now it opens the caption line:
    /// "01 · Anime · 2018". No amber lead on the card — 124 pt holds "Anime · 2018" and not "New
    /// episode 29 Aug", and the rule is drop a fact rather than print a fragment; the airing fact
    /// leads the ROW and the top-match card, where there is width for it, and it is spoken here.
    private func trendingCard(rank: Int, _ item: FranchiseSummary) -> some View {
        let zoom = "trend/\(item.id)"
        let caption = ([Copy.Search.rank(rank)] + shelfFacts(item)).joined(separator: FactLine.separator)
        return ShelfCard(title: item.title, caption: caption, poster: item.cover,
                         slot: .shelfLarge, zoomID: zoom) {
            open(item, zoom: zoom)
        }
        // The rank, the WHOLE title and the lead — the card shows a shortened title and no lead.
        .accessibilityLabel(spoken(item, rank: rank, ambiguous: []))
        .accessibilityHint(Copy.Accessibility.opensTheShowHint)
        // The badge lives OUTSIDE the card's own button: a Button nested inside another Button's
        // label is a coin-toss for which one gets the tap. The inset puts the visible disc 8 pt
        // inside the artwork's corner rather than straddling it.
        .overlay(alignment: .topTrailing) {
            addControl(item, placement: .overArt).padding(Metrics.overArtControlInset)
        }
        .franchiseQuickActions(appModel.franchise(id: item.id), appModel: appModel)
        .accessibilityElement(children: .contain)
    }

    /// Ranks four and beyond. Same chart, same facts — row altitude, with the rank in the row's
    /// own leading gutter.
    private func chartRow(rank: Int, _ item: FranchiseSummary, isLast: Bool) -> some View {
        HStack(spacing: ThemeMetrics.artGap) {
            RankGutter(rank: rank)
            mediaRow(item, zoom: "trend/\(item.id)", ambiguous: [], separator: !isLast)
                .accessibilityLabel(spoken(item, rank: rank, ambiguous: []))
        }
    }

    /// The one row anatomy for both lists on this screen: the app's `MediaRow`, no chevron (the
    /// trailing column holds a control), the amber `when` as its lead so VoiceOver hears it inside
    /// the row's combined label, and the add control in the trailing slot.
    private func mediaRow(_ item: FranchiseSummary, zoom: String,
                          ambiguous: Set<String>, separator: Bool) -> some View {
        MediaRow(title: disambiguated(item, ambiguous: ambiguous),
                 meta: rowFacts(item, ambiguous: ambiguous).joined(separator: FactLine.separator),
                 lead: when(item),
                 poster: item.cover,
                 slot: .row,
                 chevron: false,
                 separator: separator,
                 hint: Copy.Accessibility.opensTheShowHint,
                 zoomID: zoom,
                 trailing: { addControl(item) }) {
            open(item, zoom: zoom)
        }
        .franchiseQuickActions(appModel.franchise(id: item.id), appModel: appModel)
    }

    // MARK: - Results

    @ViewBuilder
    private func searchBody(_ results: ResultSet, trending: [FranchiseSummary]) -> some View {
        SkeletonGate(isLoading: appModel.searchBusy && results.isEmpty && !scopedOut(results) && !appModel.searchError) {
            searchSkeleton
        } content: {
            resultsContent(results, trending: trending)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The shape the results are about to take: label, card, rows at exactly the `.focus` and
    /// `.row` geometry the content uses, so nothing reflows when the data lands.
    private var searchSkeleton: some View {
        VStack(alignment: .leading, spacing: 0) {
            SkeletonLine(width: Metrics.skeletonLabel.width, height: Metrics.skeletonLabel.height)
                .padding(.horizontal, ThemeMetrics.gutter)
                .padding(.top, ThemeMetrics.sectionGap)
            SkeletonRow(poster: PosterSize.focus.size, lines: Metrics.skeletonCardLines,
                        posterRadius: PosterSize.focus.radius,
                        spacing: ThemeMetrics.artGap, height: PosterSize.focus.size.height)
                .padding(ThemeSpace.x4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .surface(.plate, radius: ThemeRadius.card)
                .padding(.horizontal, ThemeMetrics.gutter)
                .padding(.top, ThemeMetrics.labelGap)
            VStack(spacing: 0) {
                ForEach(0..<4, id: \.self) { _ in
                    SkeletonRow(poster: PosterSize.row.size, lines: Metrics.skeletonRowLines,
                                posterRadius: PosterSize.row.radius,
                                spacing: ThemeMetrics.artGap, height: ThemeMetrics.rowMedia)
                }
            }
            .padding(.horizontal, ThemeMetrics.gutter)
            .padding(.top, ThemeSpace.x6)
        }
    }

    @ViewBuilder
    private func resultsContent(_ results: ResultSet, trending: [FranchiseSummary]) -> some View {
        if scopedOut(results) {
            stateWithTrending(trending) {
                EmptyState(scopedOutCopy, primary: {
                    withAnimation(ThemeMotion.pick(ThemeMotion.uiSnappy, reduceMotion: reduceMotion)) {
                        appModel.mediaFilter = .all
                    }
                })
            }
        } else if results.isEmpty {
            stateWithTrending(trending) {
                VStack(spacing: ThemeSpace.x4) {
                    // A catalogue that failed while the other found nothing: the notice says
                    // which, so "No results" is not the whole story.
                    notices(refreshFailed: false, inset: false)
                    EmptyState(appModel.searchError ? errorCopy : .noSearchResults(query: query),
                               primary: appModel.searchError ? { appModel.retrySearch() } : nil)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                // A stale result set with a failed refresh over it, or one catalogue down: the
                // content stays, the notice sits above it.
                notices(refreshFailed: appModel.searchError, inset: true)
                if let correction = appModel.searchCorrection { correctionLine(correction) }
                if let top = results.first {
                    // "Top match" in BOTH states, with the count in the header where Library and
                    // Detail put theirs. The single-result state used to drop the label and print
                    // "1 result" as a lone centred grey caption at the foot of the screen — the one
                    // centred thing on a screen where every label is left-aligned to the gutter,
                    // and a different anatomy for the same answer.
                    SectionHeaderRow(Copy.Search.topMatch)
                        .padding(.horizontal, ThemeMetrics.gutter)
                        .padding(.top, ThemeMetrics.sectionGap)
                    topMatch(top, ambiguous: results.ambiguous).padding(.top, ThemeMetrics.labelGap)
                }
                if results.count > 1 {
                    // The count lives on the header that names the set it counts, the way Library
                    // and Detail carry theirs.
                    SectionHeaderRow(Copy.Search.moreResults, count: results.count - 1)
                        .padding(.horizontal, ThemeMetrics.gutter)
                        .padding(.top, ThemeMetrics.sectionGap)
                    VStack(spacing: 0) {
                        ForEach(Array(results.items.dropFirst().enumerated()), id: \.element.id) { i, item in
                            mediaRow(item, zoom: "result/\(item.id)", ambiguous: results.ambiguous,
                                     separator: i < results.count - 2)
                        }
                    }
                    .padding(.horizontal, ThemeMetrics.gutter)
                    .padding(.top, ThemeMetrics.labelGap)
                }
                // One result used to end the screen 525 pt from the bottom, with the launchpad
                // immediately before it full of art. The chart is already loaded and decoded.
                if results.count < 3 && !trending.isEmpty {
                    trendingChart(trending).padding(.top, ThemeMetrics.sectionGap)
                }
            }
            // Refining a query that already has results: the old set steps back as a group while
            // the new one is in flight, so a list that is about to change never looks settled.
            .opacity(appModel.searchBusy ? Metrics.groupDim : 1)
            .animation(ThemeMotion.pick(ThemeMotion.uiGentle, reduceMotion: reduceMotion),
                       value: appModel.searchBusy)
            // Every new result set, not just the first: this is the modifier the container-level
            // one was standing in for.
            .animation(ThemeMotion.pick(ThemeMotion.uiSnappy, reduceMotion: reduceMotion),
                       value: results.items.map(\.id))
        }
    }

    /// The notices that belong above whatever the results are: the whole-request failure, then
    /// the per-catalogue ones. Each carries the same retry.
    @ViewBuilder
    private func notices(refreshFailed: Bool, inset: Bool) -> some View {
        let messages = (refreshFailed ? [Copy.Search.couldNotRefresh] : []) + catalogueNotices
        if !messages.isEmpty {
            VStack(spacing: ThemeSpace.x2) {
                ForEach(messages, id: \.self) { message in
                    InlineNotice(message) { appModel.retrySearch() }
                }
            }
            .padding(.horizontal, inset ? ThemeMetrics.gutter : 0)
            .padding(.top, inset ? ThemeSpace.x4 : 0)
        }
    }

    /// A whole-surface state, followed by the artwork this screen already has. The app used to
    /// throw away a decoded shelf in order to say one sentence, leaving a plate over 900 pt of
    /// black — on the screen a reviewer walks first.
    @ViewBuilder
    private func stateWithTrending(_ trending: [FranchiseSummary],
                                   @ViewBuilder _ state: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            state()
                .padding(.horizontal, ThemeMetrics.gutter)
                .padding(.top, ThemeMetrics.sectionGap)
            if !trending.isEmpty {
                trendingChart(trending).padding(.top, ThemeMetrics.sectionGap)
            } else {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The standard "we searched for something else" disclosure, with the literal search one tap
    /// away. `correctedQuery` has been on the wire and decoded since the endpoint shipped.
    private func correctionLine(_ correction: SearchCorrection) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Copy.Search.showingResultsFor(correction.corrected))
                .type(ThemeType.metadata)
                .foregroundStyle(ThemeColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(Copy.Search.searchInsteadFor(correction.original)) {
                appModel.searchLiterally(correction.original)
            }
            .buttonStyle(InlineLinkButtonStyle())
            .padding(.leading, -Metrics.inlineLinkInset)
        }
        .padding(.horizontal, ThemeMetrics.gutter)
        .padding(.top, ThemeMetrics.sectionGap)
        .accessibilityElement(children: .contain)
    }

    /// The one card on the screen: `.raised`, so it is visible because it is LIGHTER, not because
    /// it has a line drawn round it. Its own tap opens the show; adding is one subordinate control.
    private func topMatch(_ item: FranchiseSummary, ambiguous: Set<String>) -> some View {
        let zoom = "top/\(item.id)"
        return Button { open(item, zoom: zoom) } label: {
            Group {
                if isAX {
                    // Poster INLINE with the title, not stacked above the text: stacked, the card
                    // grew to ~400 pt with an L-shaped void in its top-right and the action
                    // orphaned in a corner aligned to nothing.
                    VStack(alignment: .leading, spacing: ThemeMetrics.artGap) {
                        HStack(alignment: .top, spacing: ThemeMetrics.artGap) {
                            PosterSlot(url: item.cover, .row).zoomSource(zoom)
                            // At AX the title has the card's full width and no line cap, so it can
                            // always be whole — the raw title, exactly as the catalogue spells it.
                            Text(disambiguated(item, ambiguous: ambiguous))
                                .type(ThemeType.showTitleL)
                                .foregroundStyle(ThemeColor.textPrimary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        cardMeta(item, ambiguous: ambiguous)
                    }
                } else {
                    HStack(alignment: .center, spacing: ThemeMetrics.artGap) {
                        PosterSlot(url: item.cover, .focus).zoomSource(zoom)
                        VStack(alignment: .leading, spacing: ThemeMetrics.titleGap) {
                            // 72 measured, not guessed: the card's text column is ~230 pt, so four
                            // lines of `showTitleL` at its 0.8 floor hold about 76 characters —
                            // and a 78-character title ellipsised at exactly that edge. Past the
                            // budget the colon rule takes over and the card prints "HELL MODE".
                            Text(fittedTitle(item, budget: Metrics.cardTitleBudget, ambiguous: ambiguous))
                                .type(ThemeType.showTitleL)
                                .foregroundStyle(ThemeColor.textPrimary)
                                .lineLimit(4)
                                .minimumScaleFactor(0.8)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            cardMeta(item, ambiguous: ambiguous)
                                .padding(.top, ThemeSpace.x1)
                        }
                        // Reserves the trailing control's lane so a long title can never run under it.
                        Spacer(minLength: Metrics.cardControlLane)
                    }
                }
            }
            .padding(ThemeSpace.x4)
            // The AX card reserves the action's row inside its own surface.
            .padding(.bottom, isAX ? Metrics.axActionRow : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .surface(.raised, radius: ThemeRadius.card)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle(radius: ThemeRadius.card))
        // The WHOLE title, the lead and the facts — the card may print the colon-cut identity half.
        .accessibilityLabel(spoken(item, ambiguous: ambiguous))
        .accessibilityHint(Copy.Accessibility.opensTheShowHint)
        // Centred on the poster's midline at the default size; at AX, right-aligned beneath the
        // metadata at its own natural 44 pt. NOT a full-width capsule — that was the card-body
        // primary the direction removed, reappearing at one size class only, so a single verb was
        // drawn one way at the default size and another way at AX.
        .overlay(alignment: isAX ? .bottomTrailing : .trailing) {
            addControl(item)
                .padding(.trailing, isAX ? ThemeSpace.x4 : ThemeSpace.x3)
                .padding(.bottom, isAX ? ThemeSpace.x3 : 0)
        }
        .franchiseQuickActions(appModel.franchise(id: item.id), appModel: appModel)
        .padding(.horizontal, ThemeMetrics.gutter)
        .accessibilityElement(children: .contain)
    }

    /// The card's metadata: the same facts a row carries, in the same order, on two lines instead
    /// of one.
    ///
    /// A row has ~230 pt and one line; the card has the same 230 pt (its poster and its trailing
    /// control take the rest) and vertical room to spare. Forcing the card onto one line dropped
    /// everything after "New episode tomorrow" — so the top match, the biggest object on the
    /// screen, said less about what it was than the rows beneath it. Two lines, same schema, no
    /// third anatomy.
    @ViewBuilder
    private func cardMeta(_ item: FranchiseSummary, ambiguous: Set<String>) -> some View {
        VStack(alignment: .leading, spacing: ThemeMetrics.titleGap) {
            if let w = when(item) {
                Text(w)
                    .type(ThemeType.rowMetaLead)
                    .foregroundStyle(ThemeColor.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            FactLine(facts: rowFacts(item, ambiguous: ambiguous), token: ThemeType.rowMeta)
        }
    }

    // MARK: - Actions

    private func open(_ item: FranchiseSummary, zoom: String) {
        // The SHOW the user acted on is what "Recently searched" remembers — the term only when
        // it came from the field.
        if !query.isEmpty { appModel.recordRecentItem(item) }
        onOpenDetail(item.id, zoom)
    }

    /// The add control, with the menu an OWNED tap opens: the same status options and the same
    /// Undo-carrying Remove the Library row's long-press offers once the franchise is loaded; while
    /// the add is still pending (owned, not yet in `library`) the one thing that can be done is
    /// take it back out.
    private func addControl(_ item: FranchiseSummary,
                            placement: AddControlPlacement = .row) -> some View {
        AddControl(title: item.title,
                   owned: appModel.isInLibrary(item.id),
                   placement: placement,
                   add: { add(item) }) {
            if let f = appModel.franchise(id: item.id) {
                FranchiseContextMenu(f: f, appModel: appModel)
            } else {
                Button(role: .destructive) {
                    appModel.removeFromLibrary(franchiseId: item.id)
                } label: {
                    Label(Copy.Action.removeFromLibrary, systemImage: "trash")
                }
            }
        }
    }

    private func add(_ item: FranchiseSummary) {
        appModel.addToLibrary(franchiseId: item.id, title: item.title, isReleasing: item.isReleasing)
        if !query.isEmpty { appModel.recordRecentItem(item) }
        // NOT a permission prompt — see `notificationPrimer`. Nothing at all happens for the whole
        // undo window; the ask is a card the user chooses to answer, later, on their own screen.
        armNotificationPrimer(item)
    }

    // MARK: - Copy helpers

    /// How big the thing is — **only where the app can say it truthfully.**
    ///
    /// "Part" is `FranchisePart`, an internal model word nobody outside this repository can
    /// interpret. But its replacement asserted something the app disproves two taps later: Search
    /// said One Piece had "45 seasons", and One Piece's own screen prints "SEASONS & MOVIES 23"
    /// with the remainder under EXTRAS. Renaming the number does not fix it — 41 is not 23 under
    /// any label. This is the figure a user checks before adding a 45-"season" show, and a tracker
    /// that gets it wrong on the add screen is not one you trust with your progress.
    ///
    /// `FranchiseSummary` carries a single `partCount` (every member), while the split lives in
    /// `partCounts` on the full franchise, which search results do not fetch. So: TMDB, where one
    /// member genuinely is one season, keeps its count; AniList prints no count at all until the
    /// server puts the by-kind breakdown on the summary. **Server follow-up:** add `partCounts` to
    /// `FranchiseListItem` (`services/franchiseView.ts:274`) and this becomes "5 seasons · 6 extras".
    private func size(_ item: FranchiseSummary) -> String? {
        guard item.partCount > 0, item.source == .tmdb else { return nil }
        return Copy.Search.seasons(item.partCount)
    }

    /// When the next episode lands, with a predicate.
    ///
    /// The shipped row printed a bare "29 Aug 2:00 PM" as its fourth fact, in the same grey as the
    /// year and the season count — a date-time with nothing saying whether it was a premiere, the
    /// next episode or the finale, set as though it were trivia. It is the one forward-looking fact
    /// on the screen, so it is named, it leads the line, and it is the one thing on it in amber —
    /// the rule Today, Library and Schedule already follow.
    private func when(_ item: FranchiseSummary) -> String? {
        guard item.isReleasing else { return nil }
        guard let at = item.nextAiringAt, at > now else { return Copy.Search.airingNow }
        let word = TemporalCopy.airsCompact(at: at, now: now, source: item.source)
        // "today" and "tomorrow" are common nouns mid-sentence; a weekday and a month are not.
        let cased = (word == "Today" || word == "Tomorrow") ? word.lowercased() : word
        return Copy.Search.newEpisode(day: cased)
    }

    /// The grey facts, in priority order. The amber `when` is passed separately and never dropped.
    ///
    /// **An owned show leads with its shelf.** The tick alone said "in your library" and never
    /// which of five lists it was on; the status word is the fact that answers that, in the same
    /// vocabulary Library's own rows use.
    ///
    /// **Kind next.** A search for "one piece" returns the 1999 anime, the 2023 live-action and
    /// the 2027 anime, separated by capitalisation and a year — and the scope bar directly above
    /// proves the app knows which is which. Adding the wrong one puts the wrong show in the
    /// library, and there is no other moment where the kind matters more.
    ///
    /// **The year goes when a next-episode date is present.** They are the same class of fact and
    /// the line only holds so much: for a show airing tomorrow, "1999" is the least useful thing
    /// on it, and keeping both is what pushed the row to four facts and a wrap.
    private func rowFacts(_ item: FranchiseSummary, ambiguous: Set<String>) -> [String] {
        var facts: [String] = []
        if let f = appModel.franchise(id: item.id) { facts.append(Copy.Status(f.effectiveStatus)) }
        facts.append(item.source.kindWord)
        // …and it goes when the title is already carrying it, because a disambiguated result
        // printed "ONE PIECE (2023)" over "TV · 2023 · 3 seasons" — the same number twice, 20 pt
        // apart, on a line whose whole job is telling this result apart from the one above it.
        if let y = item.year, when(item) == nil, !titleCarriesYear(item, ambiguous: ambiguous) {
            facts.append(String(y))
        }
        if let s = size(item) { facts.append(s) }
        return facts
    }

    /// The shelf caption carries the SAME schema as a row — shelf, then kind. It carries no lead,
    /// so it keeps the year.
    private func shelfFacts(_ item: FranchiseSummary) -> [String] {
        var facts: [String] = []
        if let f = appModel.franchise(id: item.id) { facts.append(Copy.Status(f.effectiveStatus)) }
        facts.append(item.source.kindWord)
        if let y = item.year { facts.append(String(y)) }
        if let s = size(item) { facts.append(s) }
        return facts
    }

    /// The spoken form of a result: rank (when it has one), the WHOLE title, the lead, the facts.
    private func spoken(_ item: FranchiseSummary, rank: Int? = nil, ambiguous: Set<String>) -> String {
        let title = disambiguated(item, ambiguous: ambiguous)
        var bits = [rank.map { "\($0). \(title)" } ?? title]
        if let w = when(item) { bits.append(w) }
        bits += rowFacts(item, ambiguous: ambiguous)
        return bits.joined(separator: ", ")
    }

    /// Titles that normalise to the same string carry their year INSIDE the title.
    ///
    /// A search for "one piece" returns five results whose titles differ only in capitalisation and
    /// a definite article, separated by a 13-pt grey line — so "One Piece (Anime · 1999)" and "ONE
    /// PIECE (TV · 2023)" read as the same show, and one of them is the wrong one to put in the
    /// library. Where the ambiguity is real the disambiguator is promoted into the identity line;
    /// where it is not, the source title is left exactly as the catalogue spells it, because in
    /// search the user is matching against what they typed.
    private func titleCarriesYear(_ item: FranchiseSummary, ambiguous: Set<String>) -> Bool {
        item.year != nil && ambiguous.contains(ResultSet.normalised(item.title))
    }

    private func disambiguated(_ item: FranchiseSummary, ambiguous: Set<String>) -> String {
        guard let year = item.year, titleCarriesYear(item, ambiguous: ambiguous) else { return item.title }
        return "\(item.title) (\(year))"
    }

    /// The top-match card's identity line, at the length the slot can actually hold.
    ///
    /// The rule is absolute — an identity title never ends in an ellipsis and never breaks
    /// mid-word — and four lines of the card is not enough for "HELL MODE: The Hardcore Gamer
    /// Dominates in Another World with Garbage Balancing". So the fallback is the one the direction
    /// names: **break at the colon and drop the subtitle.** "HELL MODE" is the name people use; the
    /// full string stays in the accessibility label and on the show's own screen. The rows do not
    /// go through this — `MediaRow` prints the title whole.
    ///
    /// `budget` is characters, not points — it only has to be conservative enough that the title
    /// that survives it fits with `minimumScaleFactor` still in hand.
    private func fittedTitle(_ item: FranchiseSummary, budget: Int, ambiguous: Set<String>) -> String {
        let full = disambiguated(item, ambiguous: ambiguous)
        guard full.count > budget, let colon = full.range(of: ": ") else { return full }
        let head = String(full[full.startIndex..<colon.lowerBound])
        return head.count >= 4 ? head : full
    }
}

// MARK: - The result set, scanned once

/// The visible results plus the normalised titles more than one of them shares — computed once
/// per body, not once per row. The scan is a regex over every title; at eight reads of `results`
/// and one scan per row it was running dozens of times per keystroke.
private struct ResultSet {
    let items: [FranchiseSummary]
    let ambiguous: Set<String>

    init(_ items: [FranchiseSummary]) {
        self.items = items
        var seen: Set<String> = []
        var duplicated: Set<String> = []
        for item in items {
            let key = ResultSet.normalised(item.title)
            if !seen.insert(key).inserted { duplicated.insert(key) }
        }
        ambiguous = duplicated
    }

    var isEmpty: Bool { items.isEmpty }
    var count: Int { items.count }
    var first: FranchiseSummary? { items.first }

    static func normalised(_ title: String) -> String {
        title.lowercased()
            .replacingOccurrences(of: "^the\\s+", with: "", options: .regularExpression)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }
}

// MARK: - Sizes with no token

/// Sizes this screen needs that have no token equivalent. Each says why it is the number it is.
private enum Metrics {
    /// The 44-pt minimum target (HIG).
    static let hitTarget: CGFloat = 44
    /// The browse tile's ratio — Apple Music's category tile (16:9-ish, a little squarer so a
    /// two-line name has room over the foot).
    static let tileAspect: CGFloat = 1.6
    /// A tile is ~180 pt wide at 3×; the banner is decoded to fit that, not the screen.
    static let tileMaxPixel: CGFloat = 640
    /// How dark the tile's foot gets under the name.
    static let tileFoot: Double = 0.88
    /// The height the search field adds under the title — the top veil covers both.
    static let searchDrawerHeight: CGFloat = 52
    /// A bare-term row: a 44-pt tile plus the row padding, denser than a media row.
    static let termRowHeight: CGFloat = 60
    /// Trending rows under the recents on the focused page — enough to fill a screen, no more.
    static let focusedTrendingCount = 8
    /// `MediaRow`'s disclosure chevron, verbatim, so the term rows share the media rows' x.
    static let chevronSize: CGFloat = 13
    static let chevronColumn: CGFloat = 11
    /// The primer's glyph tile — `EmptyState`'s grammar at row altitude: a 36-pt disc, not the
    /// state card's larger one.
    static let primerGlyphTile: CGFloat = 36
    /// The primer's dismiss disc, drawn inside its 44-pt target.
    static let dismissDisc: CGFloat = 28
    /// `InlineLinkButtonStyle` pads 12 pt leading to hold its target; pulled back by the same
    /// amount so the word starts on the gutter.
    static let inlineLinkInset: CGFloat = 12
    /// The over-art add control's inset from the card's corner: -1 puts the visible 26-pt disc
    /// 8 pt inside the artwork rather than straddling its edge.
    static let overArtControlInset: CGFloat = -1
    /// The lane the top-match card reserves for its 44-pt control plus the card's x4 inset, so a
    /// long title can never run under it.
    static let cardControlLane: CGFloat = 60
    /// The AX card's reserved action row: the 44-pt control plus its x3 bottom padding.
    static let axActionRow: CGFloat = 56
    /// Characters, not points: the card's ~230-pt text column holds about 76 characters over
    /// four lines of `showTitleL` at its 0.8 floor.
    static let cardTitleBudget = 72
    /// The app's group-dim (`MediaRow.dimmed`): 0.72 lands `textSecondary` at ≈5.4:1 and still
    /// reads as content that has stepped back.
    static let groupDim: Double = 0.72
    /// Skeleton geometry at the widths the real label, card lines and row lines land at.
    static let skeletonLabel = CGSize(width: 76, height: 9)
    static let skeletonCardLines: [CGFloat] = [52, 172, 118]
    static let skeletonRowLines: [CGFloat] = [188, 126]
}
