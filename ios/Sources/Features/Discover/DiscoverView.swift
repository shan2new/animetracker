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
//    separate 50-pt gutter at `textDisabled`. Now: TOP 3 on the shelf, MORE TRENDING as rows, the
//    numeral over the artwork in both, one gutter, one add control.
//  • **The payoff frame is never emptier than the question.** A single result used to be one card
//    under a "TOP MATCH" label with 900 pt of black beneath it, and both the no-results and the
//    error state threw away artwork already decoded in order to say one sentence. Trending stays
//    mounted underneath in every one of those states, and the result count gives the void a
//    boundary.
//  • **"Parts" is gone**, the kind leads every result's metadata (the anime One Piece and the
//    live-action One Piece were distinguishable only by capitalisation at the moment of adding),
//    and `correctedQuery` — decoded since day one and read by nothing — is on screen.
struct DiscoverView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    let onOpenDetail: (_ franchiseId: String, _ zoomID: String) -> Void

    /// How many of the chart's entries get the big art treatment before it continues as rows.
    private static let featuredCount = 3

    /// The scroll view's own height, for centring a state that owns the whole surface.
    @State private var contentH: CGFloat = 0

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

    /// The chart's rank lane, scaled — the separator inset has to track the same number the
    /// numerals are drawn in, or a list that reflows at AX keeps a hairline aligned to nothing.
    @ScaledMetric(relativeTo: .caption2) private var rankLane: CGFloat = RankGutter.width

    private var now: Int64 { appModel.now }
    private var query: String { appModel.searchQuery.trimmingCharacters(in: .whitespaces) }
    private var results: [FranchiseSummary] { appModel.filteredSearchResults }
    private var scopedOut: Bool { appModel.mediaFilter != .all && results.isEmpty && !appModel.searchResults.isEmpty }
    private var isAX: Bool { typeSize.isAccessibilitySize }

    /// The ambient wash is keyed to the chart's leader: a poster this screen is already loading,
    /// so the atmosphere costs one decode and never changes under the user mid-session.
    private var washURL: String? { appModel.trending.first?.cover }

    var body: some View {
        @Bindable var model = appModel
        return ZStack(alignment: .top) {
            ThemeColor.canvas.ignoresSafeArea()
            // The launchpad opened on flat near-black while Today, Detail and Library all carried
            // their wash — and the screen this one replaced had a warm one. Same primitive, same
            // intensity Detail's list wash uses, keyed to a poster the chart is already decoding.
            ArtBackdrop(url: washURL, height: 400, intensity: 0.68)
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
                        if query.isEmpty { launchpad } else { searchBody }
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
        .scrollEdgeChromeBody(top: false, bottom: true)
        .scrollEdgeEffectHidden(true, for: .bottom)
        // Art-dense content under the search field needs the hard variant — the same one Photos
        // and the TV app use.
        .scrollEdgeEffectStyle(.hard, for: .top)
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.visible, for: .navigationBar)
        // No explicit placement. On a `Tab(role: .search)` iOS 26 owns where the field lives — it
        // morphs the tab bar itself into the field and animates back — and that morph is the whole
        // reason the two are paired. Naming `.navigationBarDrawer` here would be a placement the
        // system discards on iPhone while quietly changing the iPad layout.
        // The prompt names the VERB, not the domain. "🔍 Anime & TV" was the only control in the
        // app whose resting label named what it contains instead of what it does — it read as a
        // filter chip that happened to have a magnifier on it — and it said "&" 300 pt above the
        // launchpad's own copy saying "and" for the same pair. One wording, matching
        // `EmptyStateCopy.searchLaunchpad.supporting` word for word, and it follows the scope.
        .searchable(text: $model.searchQuery, prompt: searchPrompt)
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
                // borrowed from another app.
                Text(filter.chipLabel)
                    .scaledFont(13, weight: .semibold, relativeTo: .footnote)
                    .tag(filter)
            }
        }
        // The field always carried a `.search` return key and then threw the submission away, so
        // RECENT could only ever hold terms left over from an older build.
        .onSubmit(of: .search) { appModel.recordRecentSearch() }
        .onAppear { appModel.loadTrendingIfNeeded() }
        // The system search field lives inside the tab bar's morph, so SwiftUI gives no font hook
        // for it. The appearance proxy is the only one there is, and it is a Dynamic Type font, not
        // a fixed one — a content-size change tears down and rebuilds the field, so the new metric
        // is picked up on the rebuild.
        .task(id: typeSize) { scaleSearchField() }
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

    // MARK: - The notification ask

    /// The prompt, per scope. The launchpad's own supporting line is "Search anime and TV by
    /// title."; this is the same sentence with the same conjunction, minus the full stop.
    private var searchPrompt: String {
        switch appModel.mediaFilter {
        case .anime: return "Search anime"
        case .tv: return "Search TV"
        default: return "Search anime and TV"
        }
    }

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
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(ThemeColor.textTertiary)
                    .frame(width: 36, height: 36)
                    .background(ThemeColor.surfaceRaised, in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text("Get told when an episode drops")
                        .type(ThemeType.showTitleM)
                        .foregroundStyle(ThemeColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Previously. can alert you the moment a new episode of a show you\u{2019}re watching airs.")
                        .type(ThemeType.rowMeta)
                        .foregroundStyle(ThemeColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 30)
            }
            Button("Turn on") { answerPrimer(turnOn: true) }
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
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(ThemeColor.textTertiary)
                .frame(width: 28, height: 28)
                .background(ThemeColor.surfaceRaised, in: Circle())
                .overlay(Circle().strokeBorder(ThemeColor.posterEdge, lineWidth: 1))
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        // "Not now", not "No thanks": iOS raises its own alert once ever, so the honest offer is a
        // deferral — and Profile → Notifications keeps it available for good.
        .accessibilityLabel("Not now")
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
    private func refreshNotificationEligibility() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        canAskForNotifications = settings.authorizationStatus == .notDetermined
        let shouldShow = canAskForNotifications && primerPending && !primerAnswered
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

    /// The only font hook the system search field has.
    ///
    /// `.searchable` is worth keeping — on a `Tab(role: .search)` it is what lets iOS 26 morph the
    /// tab bar itself into the field — but SwiftUI exposes no font for it, so the query text was
    /// measured at exactly the same cap height at AX1 as at the default size (33 px both), while
    /// every other piece of type on the screen grew. `UIFontMetrics`, not a fixed point size, so it
    /// tracks the setting: measured after this change, 45 px at the default size and 68 px at AX1.
    ///
    /// The **scope bar's** labels are still fixed, and there is no hook for them. iOS 26 does not
    /// build that bar from a `UISegmentedControl` — the app's own global segmented proxy
    /// (`LibraryView.SegmentedAppearance`, which paints a selected segment amber) has no effect on
    /// it, which is how we know — so the only way to scale those three words is to stop using
    /// `.searchScopes` and hand-draw the scope control, which would also give up the tab-bar search
    /// morph. Recorded, not worked around.
    private func scaleSearchField() {
        UISearchTextField.appearance().font = UIFontMetrics(forTextStyle: .body)
            .scaledFont(for: .systemFont(ofSize: 17, weight: .regular))
    }

    private func announceOutcome() {
        if appModel.searchError {
            Announce.status(Copy.Notice.searchAnime)
        } else if results.isEmpty {
            Announce.status(EmptyStateCopy.noSearchResults(query: query).title)
        } else {
            Announce.status(resultCount)
        }
    }

    private var resultCount: String { Copy.plural(results.count, "result", "results") }

    // MARK: - Launchpad

    @ViewBuilder
    private var launchpad: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !appModel.recentSearches.isEmpty {
                recentSection.padding(.top, ThemeSpace.x2)
            }
            if !appModel.trending.isEmpty {
                trendingChart.padding(.top, appModel.recentSearches.isEmpty ? ThemeSpace.x2 : ThemeMetrics.sectionGap)
            } else if appModel.recentSearches.isEmpty {
                EmptyState(.searchLaunchpad)
                    .padding(.horizontal, ThemeMetrics.gutter)
                    .centredState(contentH: contentH)
            }
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: ThemeMetrics.labelGap) {
            SectionHeaderRow("Recent", actionLabel: Copy.Action.clear) {
                withAnimation(ThemeMotion.pick(ThemeMotion.uiSnappy, reduceMotion: reduceMotion)) {
                    appModel.clearRecentSearches()
                }
            }
            .padding(.horizontal, ThemeMetrics.gutter)
            ScrollView(.horizontal) {
                HStack(spacing: ThemeSpace.x2) {
                    ForEach(appModel.recentSearches, id: \.self) { term in
                        Button(term) { appModel.searchQuery = term }
                            .buttonStyle(ChipButtonStyle())
                    }
                }
                .padding(.leading, ThemeMetrics.gutter)
            }
            .scrollIndicators(.hidden)
            .shelfScroller(trailingMargin: ThemeMetrics.gutter, masked: false)
        }
    }

    /// Trending as ONE chart in two densities: the top three carry full `.shelfLarge` artwork,
    /// the rest continue as rows under their own label. The rank is over the poster in both, the
    /// add control is the same object in both, and the row gutter is the screen's gutter — the
    /// shipped build's 50-pt rank column made ranks 05+ look like a different list.
    private var trendingChart: some View {
        let ranked = Array(appModel.trending.enumerated())
        // At accessibility sizes the shelf goes away entirely: a 124-pt column cannot hold an AX
        // title, and the alternative is a shelf whose every caption ends in an ellipsis. The chart
        // becomes rows, which reflow honestly, and the ranks then run unbroken from 01.
        let featured = isAX ? [] : Array(ranked.prefix(DiscoverView.featuredCount))
        let rest = isAX ? ranked : Array(ranked.dropFirst(DiscoverView.featuredCount))
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: ThemeSpace.x2) {
                SectionLabel(text: "Trending now")
                Spacer(minLength: ThemeSpace.x2)
                // The season the chart belongs to. Small, quiet, and the kind of detail that makes
                // a screen feel authored rather than generated.
                SectionLabel(text: seasonLabel, tint: ThemeColor.textDisabled)
            }
            .padding(.horizontal, ThemeMetrics.gutter)

            if !featured.isEmpty {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: ThemeMetrics.shelfGap) {
                        ForEach(featured, id: \.element.id) { i, item in
                            trendingCard(rank: i + 1, item,
                                         captionLines: Self.captionLines(featured.map(\.element)))
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
                    SectionLabel(text: "More trending")
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

    /// How many caption lines the whole row reserves.
    ///
    /// Every card in a row reserves the SAME number, so the captions keep one baseline instead of a
    /// staircase — but the number is the longest title's, not a constant: three reserved lines over
    /// "Bleach" and "BLACK TORCH" is 30 pt of hole under two short names. At ~15 characters per line
    /// in a 124-pt caption, and clamped to the 2–3 the shelf can hold without becoming a text list.
    private static func captionLines(_ items: [FranchiseSummary]) -> Int {
        let longest = items.map { $0.title.shelfShortened.count }.max() ?? 0
        return min(3, max(2, Int(ceil(Double(longest) / 15.0))))
    }

    private func trendingCard(rank: Int, _ item: FranchiseSummary, captionLines: Int) -> some View {
        let slot = PosterSize.shelfLarge
        return Button { onOpenDetail(item.id, "trend/\(item.id)") } label: {
            VStack(alignment: .leading, spacing: ThemeSpace.x2) {
                PosterSlot(url: item.cover, slot)
                    .overlay(alignment: .bottomLeading) { RankNumeral(rank: rank, slot: slot) }
                    .zoomSource("trend/\(item.id)")
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title.shelfShortened)
                        .type(ThemeType.shelfTitle)
                        .foregroundStyle(ThemeColor.textPrimary)
                        // Reserved lines, all identical across the row, so the captions keep one
                        // baseline — and a title that needs a third line gets it instead of ending
                        // in an ellipsis. A fixed two put "That Time I Got Reincarnated as…" on the
                        // #1 trending card, on the first screen a new user and a reviewer see,
                        // where the rule that identity titles never truncate is absolute.
                        .lineLimit(captionLines, reservesSpace: true)
                        // The last 12 % of size, spent only where a title actually needs it. Below
                        // this the caption would stop matching the rest of the shelf.
                        .minimumScaleFactor(0.88)
                        .multilineTextAlignment(.leading)
                    // No amber lead here. 124 pt holds "Anime · 2018" and not "New episode 29 Aug",
                    // and the rule is drop a fact rather than print a fragment — a card that keeps
                    // the date by dropping what the thing IS has kept the wrong one. The airing
                    // fact leads the ROW and the top-match card, where there is width for it.
                    FactLine(facts: shelfFacts(item), token: ThemeType.shelfCaption)
                }
                .frame(width: slot.size.width, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle(radius: slot.radius))
        // The badge lives OUTSIDE the card's own button: a Button nested inside another Button's
        // label is a coin-toss for which one gets the tap. -1 puts the visible disc 8 pt inside
        // the artwork's corner rather than straddling it.
        .overlay(alignment: .topTrailing) { addControl(item, placement: .overArt).padding(-1) }
        .accessibilityElement(children: .contain)
    }

    /// Ranks four and beyond. Same chart, same facts, same numeral treatment — row altitude.
    private func chartRow(rank: Int, _ item: FranchiseSummary, isLast: Bool) -> some View {
        HStack(spacing: ThemeSpace.x2) {
            Button { onOpenDetail(item.id, "trend/\(item.id)") } label: {
                HStack(spacing: ThemeMetrics.artGap) {
                    // The rank in the row's own gutter, not burned into a 60×90 thumbnail where it
                    // covered a quarter of the poster and landed "06" on a bright character.
                    RankGutter(rank: rank)
                    PosterSlot(url: item.cover, .searchRow)
                        .zoomSource("trend/\(item.id)")
                    rowIdentity(item)
                    Spacer(minLength: ThemeSpace.x2)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPressStyle())
            .accessibilityLabel("\(rank). \(item.title), \(rowFacts(item).joined(separator: ", "))")
            addControl(item)
        }
        .padding(.vertical, ThemeSpace.x2)
        .frame(minHeight: ThemeMetrics.rowMedia)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle().fill(ThemeColor.separatorQuiet).frame(height: 1)
                    .padding(.leading, rankLane + ThemeMetrics.artGap
                             + PosterSize.searchRow.size.width + ThemeMetrics.artGap)
            }
        }
    }

    /// A result's title and facts, one anatomy for both lists on this screen.
    ///
    /// The title is allowed two lines and 15 % of scale before anything else happens, because
    /// "HELL MODE: The Hardcore Gamer Dominates in Another W…" cut mid-word is the identity of the
    /// thing the user is about to add. Where two results normalise to the same string the year is
    /// promoted INTO the title — "One Piece (1999)" / "One Piece (2023)" — because a 13-pt grey
    /// line is not enough to tell a user which of two identical-looking rows is the wrong one.
    private func rowIdentity(_ item: FranchiseSummary) -> some View {
        VStack(alignment: .leading, spacing: ThemeMetrics.titleGap) {
            Text(isAX ? disambiguated(item) : fittedTitle(item, budget: 54))
                .type(ThemeType.rowTitle)
                .foregroundStyle(ThemeColor.textPrimary)
                .lineLimit(isAX ? nil : 2)
                .minimumScaleFactor(isAX ? 1 : 0.85)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            FactLine(facts: rowFacts(item), lead: when(item))
        }
    }

    // MARK: - Results

    @ViewBuilder
    private var searchBody: some View {
        SkeletonGate(isLoading: appModel.searchBusy && results.isEmpty && !scopedOut && !appModel.searchError) {
            searchSkeleton
        } content: {
            resultsContent
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The shape the results are about to take: label, card, rows at exactly the `.focus` and
    /// `.searchRow` geometry the content uses, so nothing reflows when the data lands.
    private var searchSkeleton: some View {
        VStack(alignment: .leading, spacing: 0) {
            SkeletonLine(width: 76, height: 9)
                .padding(.horizontal, ThemeMetrics.gutter)
                .padding(.top, ThemeMetrics.sectionGap)
            SkeletonRow(poster: PosterSize.focus.size, lines: [52, 172, 118],
                        posterRadius: PosterSize.focus.radius,
                        spacing: ThemeMetrics.artGap, height: PosterSize.focus.size.height)
                .padding(ThemeSpace.x4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .surface(.plate, radius: ThemeRadius.card)
                .padding(.horizontal, ThemeMetrics.gutter)
                .padding(.top, ThemeMetrics.labelGap)
            VStack(spacing: 0) {
                ForEach(0..<4, id: \.self) { _ in
                    SkeletonRow(poster: PosterSize.searchRow.size, lines: [188, 126],
                                posterRadius: PosterSize.searchRow.radius,
                                spacing: ThemeMetrics.artGap, height: ThemeMetrics.rowMedia)
                }
            }
            .padding(.horizontal, ThemeMetrics.gutter)
            .padding(.top, ThemeSpace.x6)
        }
    }

    @ViewBuilder
    private var resultsContent: some View {
        if scopedOut {
            stateWithTrending {
                EmptyState(.noFilterMatches, primary: {
                    withAnimation(ThemeMotion.pick(ThemeMotion.uiSnappy, reduceMotion: reduceMotion)) {
                        appModel.mediaFilter = .all
                    }
                })
            }
        } else if results.isEmpty {
            // `searchFailed` carries the wifi glyph and "check your connection", so it is the
            // OFFLINE copy; the shipped build showed it while online and showed the library's
            // "connect to load your library" while offline — both branches wrong, on a screen
            // that has nothing to do with the library.
            let copy: EmptyStateCopy = appModel.searchError
                ? (SyncCenter.shared.isOnline ? .serverNoCache : .searchFailed)
                : .noSearchResults(query: query)
            stateWithTrending {
                VStack(spacing: ThemeSpace.x4) {
                    EmptyState(copy, primary: appModel.searchError ? { appModel.retrySearch() } : nil)
                    if let correction = appModel.searchCorrection, !appModel.searchError {
                        Button("Did you mean \u{201C}\(correction.corrected)\u{201D}?") {
                            appModel.searchQuery = correction.corrected
                        }
                        .buttonStyle(SecondaryButtonStyle2())
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                if appModel.searchError {
                    // A stale result set with a failed refresh over it: the content stays, the
                    // notice sits above it. `Copy.Notice` names the per-catalogue failures but not
                    // the "both sources, one request" case this screen has (requested).
                    InlineNotice("Results couldn\u{2019}t refresh") { appModel.retrySearch() }
                        .padding(.horizontal, ThemeMetrics.gutter)
                        .padding(.top, ThemeSpace.x4)
                }
                if let correction = appModel.searchCorrection { correctionLine(correction) }
                if let top = results.first {
                    // "Top match" in BOTH states, with the count in the header where Library and
                    // Detail put theirs. The single-result state used to drop the label and print
                    // "1 result" as a lone centred grey caption at the foot of the screen — the one
                    // centred thing on a screen where every label is left-aligned to the gutter,
                    // and a different anatomy for the same answer.
                    SectionLabel(text: "Top match")
                        .padding(.horizontal, ThemeMetrics.gutter)
                        .padding(.top, ThemeMetrics.sectionGap)
                    topMatch(top).padding(.top, ThemeMetrics.labelGap)
                }
                if results.count > 1 {
                    // The count lives on the header that names the set it counts, the way Library
                    // and Detail carry theirs. It used to be a lone centred grey "5 results" at the
                    // foot of the screen — the only centred thing on a screen where every label is
                    // left-aligned to the 16-pt gutter — and the single-result state, which also
                    // dropped "TOP MATCH", printed "1 result" under one card for no reason at all.
                    SectionHeaderRow("More results", count: results.count - 1)
                        .padding(.horizontal, ThemeMetrics.gutter)
                        .padding(.top, ThemeMetrics.sectionGap)
                    VStack(spacing: 0) {
                        ForEach(Array(results.dropFirst().enumerated()), id: \.element.id) { i, item in
                            resultRow(item, isLast: i == results.count - 2)
                        }
                    }
                    .padding(.horizontal, ThemeMetrics.gutter)
                    .padding(.top, ThemeMetrics.labelGap)
                }
                // One result used to end the screen 525 pt from the bottom, with the launchpad
                // immediately before it full of art. The chart is already loaded and decoded.
                if results.count < 3 && !appModel.trending.isEmpty {
                    trendingChart.padding(.top, ThemeMetrics.sectionGap)
                }
            }
            // Every new result set, not just the first: this is the modifier the container-level
            // one was standing in for.
            .animation(ThemeMotion.pick(ThemeMotion.uiSnappy, reduceMotion: reduceMotion),
                       value: results.map(\.id))
        }
    }

    /// A whole-surface state, followed by the artwork this screen already has. The app used to
    /// throw away a decoded shelf in order to say one sentence, leaving a plate over 900 pt of
    /// black — on the screen a reviewer walks first.
    @ViewBuilder
    private func stateWithTrending(@ViewBuilder _ state: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            state()
                .padding(.horizontal, ThemeMetrics.gutter)
                .padding(.top, ThemeMetrics.sectionGap)
            if !appModel.trending.isEmpty {
                trendingChart.padding(.top, ThemeMetrics.sectionGap)
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
            Text("Showing results for \u{201C}\(correction.corrected)\u{201D}")
                .type(ThemeType.metadata)
                .foregroundStyle(ThemeColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Search instead for \u{201C}\(correction.original)\u{201D}") {
                appModel.searchLiterally(correction.original)
            }
            .buttonStyle(InlineLinkButtonStyle())
            .padding(.leading, -12)
        }
        .padding(.horizontal, ThemeMetrics.gutter)
        .padding(.top, ThemeMetrics.sectionGap)
        .accessibilityElement(children: .contain)
    }

    /// The one card on the screen: `.raised`, so it is visible because it is LIGHTER, not because
    /// it has a line drawn round it. Its own tap opens the show; adding is one subordinate control.
    private func topMatch(_ item: FranchiseSummary) -> some View {
        Button { onOpenDetail(item.id, "top/\(item.id)") } label: {
            Group {
                if isAX {
                    // Poster INLINE with the title, not stacked above the text: stacked, the card
                    // grew to ~400 pt with an L-shaped void in its top-right and the action
                    // orphaned in a corner aligned to nothing.
                    VStack(alignment: .leading, spacing: ThemeMetrics.artGap) {
                        HStack(alignment: .top, spacing: ThemeMetrics.artGap) {
                            PosterSlot(url: item.cover, .searchRow).zoomSource("top/\(item.id)")
                            // At AX the title has the card's full width and no line cap, so it can
                            // always be whole — the raw title, exactly as the catalogue spells it.
                            Text(disambiguated(item))
                                .type(ThemeType.showTitleL)
                                .foregroundStyle(ThemeColor.textPrimary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        cardMeta(item)
                    }
                } else {
                    HStack(alignment: .center, spacing: ThemeMetrics.artGap) {
                        PosterSlot(url: item.cover, .focus).zoomSource("top/\(item.id)")
                        VStack(alignment: .leading, spacing: ThemeMetrics.titleGap) {
                            // 72 measured, not guessed: the card's text column is ~230 pt, so four
                            // lines of `showTitleL` at its 0.8 floor hold about 76 characters —
                            // and a 78-character title ellipsised at exactly that edge. Past the
                            // budget the colon rule takes over and the card prints "HELL MODE".
                            Text(fittedTitle(item, budget: 72))
                                .type(ThemeType.showTitleL)
                                .foregroundStyle(ThemeColor.textPrimary)
                                .lineLimit(4)
                                .minimumScaleFactor(0.8)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            cardMeta(item)
                                .padding(.top, ThemeSpace.x1)
                        }
                        // Reserves the trailing control's lane so a long title can never run under it.
                        Spacer(minLength: 60)
                    }
                }
            }
            .padding(ThemeSpace.x4)
            // The AX card reserves the action's row inside its own surface.
            .padding(.bottom, isAX ? 56 : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .surface(.raised, radius: ThemeRadius.card)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle(radius: ThemeRadius.card))
        // Centred on the poster's midline at the default size; at AX, right-aligned beneath the
        // metadata at its own natural 44 pt. NOT a full-width capsule — that was the card-body
        // primary the direction removed, reappearing at one size class only, so a single verb was
        // drawn one way at the default size and another way at AX.
        .overlay(alignment: isAX ? .bottomTrailing : .trailing) {
            addControl(item)
                .padding(.trailing, isAX ? ThemeSpace.x4 : ThemeSpace.x3)
                .padding(.bottom, isAX ? ThemeSpace.x3 : 0)
        }
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
    private func cardMeta(_ item: FranchiseSummary) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if let w = when(item) {
                Text(w)
                    .type(ThemeType.rowMetaLead)
                    .foregroundStyle(ThemeColor.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            FactLine(facts: cardFacts(item), token: ThemeType.rowMeta)
        }
    }

    private func resultRow(_ item: FranchiseSummary, isLast: Bool) -> some View {
        HStack(spacing: ThemeSpace.x2) {
            Button { onOpenDetail(item.id, "result/\(item.id)") } label: {
                HStack(spacing: ThemeMetrics.artGap) {
                    PosterSlot(url: item.cover, .searchRow).zoomSource("result/\(item.id)")
                    rowIdentity(item)
                    Spacer(minLength: ThemeSpace.x2)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPressStyle())
            .accessibilityLabel("\(item.title), \(rowFacts(item).joined(separator: ", "))")
            addControl(item)
        }
        .padding(.vertical, ThemeSpace.x2)
        .frame(minHeight: ThemeMetrics.rowMedia)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle().fill(ThemeColor.separatorQuiet).frame(height: 1)
                    .padding(.leading, PosterSize.searchRow.size.width + ThemeMetrics.artGap)
            }
        }
    }

    // MARK: - Add controls

    private func addControl(_ item: FranchiseSummary,
                            placement: AddControl.Placement = .row) -> some View {
        AddControl(title: item.title,
                   owned: appModel.isInLibrary(item.id),
                   placement: placement,
                   add: { add(item) },
                   remove: { remove(item) })
    }

    private func add(_ item: FranchiseSummary) {
        appModel.addToLibrary(franchiseId: item.id, title: item.title, isReleasing: item.isReleasing)
        // NOT a permission prompt — see `notificationPrimer`. Nothing at all happens for the whole
        // undo window; the ask is a card the user chooses to answer, later, on their own screen.
        armNotificationPrimer(item)
    }

    /// Added is not a dead end. Removal goes through the canonical transaction, so it carries the
    /// same 6-second Undo the Library row's swipe does — never a silent unsubscribe.
    private func remove(_ item: FranchiseSummary) {
        guard let franchise = appModel.library.first(where: { $0.id == item.id }) else { return }
        appModel.removeWithUndo(franchise, reduceMotion: reduceMotion)
    }

    // MARK: - Copy helpers

    /// The anime season this chart belongs to — Winter / Spring / Summer / Fall by quarter.
    private var seasonLabel: String {
        let cal = Calendar.current
        let date = Date()
        let month = cal.component(.month, from: date)
        let year = cal.component(.year, from: date) % 100
        let season: String
        switch month {
        case 1...3: season = "Winter"
        case 4...6: season = "Spring"
        case 7...9: season = "Summer"
        default: season = "Fall"
        }
        return "\(season) \u{2019}\(String(format: "%02d", year))"
    }

    /// **Kind first.** A search for "one piece" returns the 1999 anime, the 2023 live-action and
    /// the 2027 anime, separated by capitalisation and a year — and the scope bar directly above
    /// proves the app knows which is which. Adding the wrong one puts the wrong show in the
    /// library, and there is no other moment where the kind matters more.
    private func kind(_ item: FranchiseSummary) -> String { item.source == .tmdb ? "TV" : "Anime" }

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
        return Copy.plural(item.partCount, "season", "seasons")
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
        guard let at = item.nextAiringAt, at > now else { return "Airing now" }
        let word = TemporalCopy.airsCompact(at: at, now: now, source: item.source)
        // "today" and "tomorrow" are common nouns mid-sentence; a weekday and a month are not.
        let cased = (word == "Today" || word == "Tomorrow") ? word.lowercased() : word
        return "New episode \(cased)"
    }

    /// The grey facts, in priority order — the line decides for itself how many of these fit. The
    /// amber `when` is passed separately and never dropped.
    ///
    /// **The year goes when a next-episode date is present.** They are the same class of fact and
    /// the line only holds so much: for a show airing tomorrow, "1999" is the least useful thing
    /// on it, and keeping both is what pushed the row to four facts and a wrap.
    private func rowFacts(_ item: FranchiseSummary) -> [String] {
        var facts = [kind(item)]
        // …and it goes when the title is already carrying it, because a disambiguated result
        // printed "ONE PIECE (2023)" over "TV · 2023 · 3 seasons" — the same number twice, 20 pt
        // apart, on a line whose whole job is telling this result apart from the one above it.
        if let y = item.year, when(item) == nil, !titleCarriesYear(item) { facts.append(String(y)) }
        if let s = size(item) { facts.append(s) }
        return facts
    }

    private func cardFacts(_ item: FranchiseSummary) -> [String] { rowFacts(item) }

    /// The shelf caption carries the SAME schema as a row — kind first. The card used to omit the
    /// kind, which is the fact this file's own comment calls the most important one at the moment
    /// of adding, while the row 40 pt below carried it: two metadata schemas for one result. It
    /// carries no lead, so it keeps the year.
    private func shelfFacts(_ item: FranchiseSummary) -> [String] {
        var facts = [kind(item)]
        if let y = item.year { facts.append(String(y)) }
        if let s = size(item) { facts.append(s) }
        return facts
    }

    /// Titles that normalise to the same string carry their year INSIDE the title.
    ///
    /// A search for "one piece" returns five results whose titles differ only in capitalisation and
    /// a definite article, separated by a 13-pt grey line — so "One Piece (Anime · 1999)" and "ONE
    /// PIECE (TV · 2023)" read as the same show, and one of them is the wrong one to put in the
    /// library. Where the ambiguity is real the disambiguator is promoted into the identity line;
    /// where it is not, the source title is left exactly as the catalogue spells it, because in
    /// search the user is matching against what they typed.
    private func titleCarriesYear(_ item: FranchiseSummary) -> Bool {
        item.year != nil && ambiguousTitles.contains(Self.normalised(item.title))
    }

    private func disambiguated(_ item: FranchiseSummary) -> String {
        guard let year = item.year, titleCarriesYear(item) else { return item.title }
        return "\(item.title) (\(year))"
    }

    /// The identity line, at the length the slot can actually hold.
    ///
    /// The rule is absolute — an identity title never ends in an ellipsis and never breaks
    /// mid-word — and two lines of a row is not enough for "HELL MODE: The Hardcore Gamer Dominates
    /// in Another World with Garbage Balancing". So the fallback is the one the direction names:
    /// **break at the colon and drop the subtitle.** "HELL MODE" is the name people use; the full
    /// string stays in the accessibility label and on the show's own screen.
    ///
    /// `budget` is characters, not points — it only has to be conservative enough that the title
    /// that survives it fits with `minimumScaleFactor` still in hand.
    private func fittedTitle(_ item: FranchiseSummary, budget: Int) -> String {
        let full = disambiguated(item)
        guard full.count > budget, let colon = full.range(of: ": ") else { return full }
        let head = String(full[full.startIndex..<colon.lowerBound])
        return head.count >= 4 ? head : full
    }

    /// The normalised titles that more than one result in the current set shares.
    private var ambiguousTitles: Set<String> {
        var seen: Set<String> = []
        var duplicated: Set<String> = []
        for item in results {
            let key = Self.normalised(item.title)
            if !seen.insert(key).inserted { duplicated.insert(key) }
        }
        return duplicated
    }

    private static func normalised(_ title: String) -> String {
        title.lowercased()
            .replacingOccurrences(of: "^the\\s+", with: "", options: .regularExpression)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }
}
