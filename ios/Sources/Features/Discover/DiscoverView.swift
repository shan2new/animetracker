import SwiftUI

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
            ArtBackdrop(url: washURL, height: 340, intensity: 0.55)
                .ignoresSafeArea(edges: .top)
            ScrollView {
                // The animation belongs to the SWITCH, not to the container. On the ScrollView it
                // fired exactly once per session — `query.isEmpty` flips launchpad→results and
                // never again — while every later result set, scope change and skeleton→content
                // swap replaced instantly, on a screen whose content changes per keystroke.
                Group {
                    if query.isEmpty { launchpad } else { searchBody }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(ThemeMotion.pick(ThemeMotion.uiGentle, reduceMotion: reduceMotion), value: query.isEmpty)
                .padding(.bottom, ThemeMetrics.tabBarClearance)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
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
        .searchable(text: $model.searchQuery, prompt: "Anime & TV")
        // A catalogue query is not a sentence. Without these the system field capitalises the
        // first letter and autocorrects romaji titles into English words ("Sousou" → "Season"),
        // both of which the hand-rolled field had correctly turned off.
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .searchScopes($model.mediaFilter) {
            ForEach(MediaFilter.allCases, id: \.self) { filter in
                Text(filter.chipLabel).tag(filter)
            }
        }
        // The field always carried a `.search` return key and then threw the submission away, so
        // RECENT could only ever hold terms left over from an older build.
        .onSubmit(of: .search) { appModel.recordRecentSearch() }
        .onAppear { appModel.loadTrendingIfNeeded() }
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

    private func trendingCard(rank: Int, _ item: FranchiseSummary) -> some View {
        let slot = PosterSize.shelfLarge
        return Button { onOpenDetail(item.id, "trend/\(item.id)") } label: {
            VStack(alignment: .leading, spacing: ThemeSpace.x2) {
                PosterSlot(url: item.cover, slot)
                    .overlay(alignment: .bottomLeading) { RankNumeral(rank: rank, slot: slot, large: true) }
                    .zoomSource("trend/\(item.id)")
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title.shelfShortened)
                        .type(ThemeType.shelfTitle)
                        .foregroundStyle(ThemeColor.textPrimary)
                        // Two reserved lines whether or not the title needs them, so a shelf of
                        // mixed-length titles keeps ONE caption baseline instead of a staircase.
                        .lineLimit(2, reservesSpace: true)
                        .multilineTextAlignment(.leading)
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
                    PosterSlot(url: item.cover, .searchRow)
                        .overlay(alignment: .bottomLeading) { RankNumeral(rank: rank, slot: .searchRow) }
                        .zoomSource("trend/\(item.id)")
                    VStack(alignment: .leading, spacing: ThemeMetrics.titleGap) {
                        Text(item.title)
                            .type(ThemeType.rowTitle)
                            .foregroundStyle(ThemeColor.textPrimary)
                            .lineLimit(isAX ? nil : 2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        FactLine(facts: rowFacts(item))
                    }
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
                    .padding(.leading, PosterSize.searchRow.size.width + ThemeMetrics.artGap)
            }
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
                    // A section label that names a RANK with nothing ranked below it reads as a
                    // truncated response. "Top match" appears only when there is something for it
                    // to be the top OF.
                    if results.count > 1 {
                        SectionLabel(text: "Top match")
                            .padding(.horizontal, ThemeMetrics.gutter)
                            .padding(.top, ThemeMetrics.sectionGap)
                    }
                    topMatch(top).padding(.top, results.count > 1 ? ThemeMetrics.labelGap : ThemeMetrics.sectionGap)
                }
                if results.count > 1 {
                    SectionLabel(text: "More results")
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
                Text(resultCount)
                    .type(ThemeType.metadata)
                    .foregroundStyle(ThemeColor.textDisabled)
                    .frame(maxWidth: .infinity)
                    .padding(.top, ThemeSpace.x6)
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
                            Text(item.title)
                                .type(ThemeType.showTitleL)
                                .foregroundStyle(ThemeColor.textPrimary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        FactLine(facts: cardFacts(item), token: ThemeType.cardFact)
                    }
                } else {
                    HStack(alignment: .center, spacing: ThemeMetrics.artGap) {
                        PosterSlot(url: item.cover, .focus).zoomSource("top/\(item.id)")
                        VStack(alignment: .leading, spacing: ThemeMetrics.titleGap) {
                            Text(item.title)
                                .type(ThemeType.showTitleL)
                                .foregroundStyle(ThemeColor.textPrimary)
                                .lineLimit(3)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            // One line, fact-dropping. The card used to carry an "ANIME" eyebrow
                            // AND a metadata line AND a second airing line, while the identical
                            // data set was one line in a row and two facts on a shelf caption —
                            // three anatomies for one result, with nothing to say why.
                            FactLine(facts: cardFacts(item), token: ThemeType.cardFact)
                                .padding(.top, ThemeSpace.x1)
                        }
                        // Reserves the trailing control's lane so a long title can never run under it.
                        Spacer(minLength: 60)
                    }
                }
            }
            .padding(ThemeSpace.x4)
            // The AX card reserves the full-width action's row inside its own surface.
            .padding(.bottom, isAX ? 60 : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .surface(.raised, radius: ThemeRadius.card)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle(radius: ThemeRadius.card))
        // Centred on the poster's midline. At AX the control spans the card's width at its foot,
        // where a 44-pt square hanging in the corner read as debris.
        .overlay(alignment: isAX ? .bottom : .trailing) {
            if isAX {
                wideAddControl(item)
                    .padding(.horizontal, ThemeSpace.x4)
                    .padding(.bottom, ThemeSpace.x4)
            } else {
                addControl(item).padding(.trailing, ThemeSpace.x3)
            }
        }
        .padding(.horizontal, ThemeMetrics.gutter)
        .accessibilityElement(children: .contain)
    }

    private func resultRow(_ item: FranchiseSummary, isLast: Bool) -> some View {
        HStack(spacing: ThemeSpace.x2) {
            Button { onOpenDetail(item.id, "result/\(item.id)") } label: {
                HStack(spacing: ThemeMetrics.artGap) {
                    PosterSlot(url: item.cover, .searchRow).zoomSource("result/\(item.id)")
                    VStack(alignment: .leading, spacing: ThemeMetrics.titleGap) {
                        Text(item.title)
                            .type(ThemeType.rowTitle)
                            .foregroundStyle(ThemeColor.textPrimary)
                            .lineLimit(isAX ? nil : 2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        FactLine(facts: rowFacts(item))
                    }
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

    /// The AX variant: the same two states as a full-width capsule, because a 44-pt square in the
    /// corner of a 400-pt card is not a primary action.
    private func wideAddControl(_ item: FranchiseSummary) -> some View {
        let owned = appModel.isInLibrary(item.id)
        return Button(owned ? "In your library" : Copy.Action.add) {
            owned ? remove(item) : add(item)
        }
        .buttonStyle(SecondaryButtonStyle2())
        .frame(maxWidth: .infinity)
        .accessibilityLabel(owned ? "Remove \(item.title) from your library" : "\(Copy.Action.add) \(item.title)")
    }

    private func add(_ item: FranchiseSummary) {
        appModel.addToLibrary(franchiseId: item.id, title: item.title, isReleasing: item.isReleasing)
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

    /// How big the thing is. "Part" is `FranchisePart` — an internal model word that appeared
    /// nowhere else in the product and that nobody outside this repository can interpret; "45
    /// parts" for One Piece invites the reader to guess between seasons, arcs and films.
    private func size(_ item: FranchiseSummary) -> String? {
        guard item.partCount > 0 else { return nil }
        return Copy.plural(item.partCount, "season", "seasons")
    }

    /// When the next part lands. Compact: a row has no room for "Tomorrow at 7:46 PM", and the
    /// fact-dropping line will spend that room on the season count first.
    private func when(_ item: FranchiseSummary) -> String? {
        guard item.isReleasing else { return nil }
        if let at = item.nextAiringAt, at > now {
            return TemporalCopy.airsCompact(at: at, now: now, source: item.source)
        }
        return "Airing"
    }

    /// One builder, three contexts — the line decides for itself how many of these fit.
    private func rowFacts(_ item: FranchiseSummary) -> [String] {
        var facts = [kind(item)]
        if let y = item.year { facts.append(String(y)) }
        if let s = size(item) { facts.append(s) }
        if let w = when(item) { facts.append(w) }
        return facts
    }

    private func cardFacts(_ item: FranchiseSummary) -> [String] { rowFacts(item) }

    /// 124 pt of caption: the kind is already established by the section it sits in.
    private func shelfFacts(_ item: FranchiseSummary) -> [String] {
        var facts: [String] = []
        if let y = item.year { facts.append(String(y)) }
        if let s = size(item) { facts.append(s) }
        return facts
    }
}
