import SwiftUI

// Search (spec board 07). Empty query = the launchpad; a query = results.
//
// Polish pass. What the shipped screen got wrong, and what replaced it:
//
//  • **The launchpad opened on #09090B.** The original opened on a warm, art-derived wash and it
//    is most of why that screen felt alive. `ArtBackdrop` is back, keyed to the chart's leader —
//    one already-cached image, drawn once, never animated.
//  • **Eight outlined objects fought three posters**: four stroked recent chips each carrying its
//    own ✕, a stroked field, a 16-pt amber `Clear`, and three stroked scope pills. Chips are now
//    `ChipButtonStyle` (no stroke unless selected), the field is separated by tone, `Clear` is an
//    `InlineLinkButtonStyle`, and the per-chip ✕ is gone — one `Clear` was always the affordance.
//  • **The add badge was a sticker**: a 32-pt solid accent disc planted over the corner of the
//    artwork. It is now a 26-pt `scrimStrong` disc sitting *inside* the art's inset, and only the
//    already-added ✓ uses accent.
//  • **Half the screen was void.** The trending shelf ended a third of the way down and 500 pt of
//    black followed. Trending is now a chart: the top five on a shelf that runs off the right
//    edge, the rest continuing as rows, so the screen is content all the way to the tab bar.
//  • **Results were one stroked card in a void** with a secondary capsule inside its body. The top
//    match is a `.raised` card with one subordinate trailing control; everything after it is a
//    rhythm of `MediaRow`s on the canvas.
//  • **Metadata truncated on every card** (`2018 · 11 parts · Friday…`). Each context now carries
//    only the facts that fit it — a dropped fact beats an ellipsis.
struct DiscoverView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    let onOpenDetail: (_ franchiseId: String, _ zoomID: String) -> Void

    @FocusState private var fieldFocused: Bool

    /// How many of the chart's entries get the big art treatment before it continues as rows.
    private static let featuredCount = 4

    private var now: Int64 { appModel.now }
    private var query: String { appModel.searchQuery.trimmingCharacters(in: .whitespaces) }
    private var results: [FranchiseSummary] { appModel.filteredSearchResults }
    private var scopedOut: Bool { appModel.mediaFilter != .all && results.isEmpty && !appModel.searchResults.isEmpty }
    private var isAX: Bool { typeSize.isAccessibilitySize }

    /// The ambient wash is keyed to the chart's leader: a poster this screen is already loading,
    /// so the atmosphere costs one decode and never changes under the user mid-session.
    private var washURL: String? { appModel.trending.first?.cover }

    var body: some View {
        ZStack(alignment: .top) {
            ThemeColor.canvas.ignoresSafeArea()
            ArtBackdrop(url: washURL, height: 340, intensity: 0.55)
                .ignoresSafeArea(edges: .top)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Search")
                        .type(ThemeType.screenTitle)
                        .foregroundStyle(ThemeColor.textPrimary)
                        .padding(.horizontal, ThemeMetrics.gutter)
                        .padding(.top, ThemeSpace.x2)
                    searchField.padding(.top, ThemeSpace.x4)
                    if query.isEmpty {
                        launchpad
                    } else {
                        scopeRow.padding(.top, ThemeSpace.x4)
                        searchBody
                    }
                }
                .padding(.bottom, ThemeMetrics.tabBarClearance)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        // The bottom edge stays on in BOTH states. `scrollDismissesKeyboard(.interactively)` means
        // a scrolled results list ends up with the tab bar — not the keyboard — over its last row,
        // and a poster cut in half by a glass pill with no fade is the same defect as content on
        // top of the clock. While the keyboard IS up the fade sits behind it and costs nothing.
        .scrollEdgeChrome()
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { appModel.loadTrendingIfNeeded() }
        .animation(ThemeMotion.pick(ThemeMotion.uiGentle, reduceMotion: reduceMotion), value: query.isEmpty)
    }

    // MARK: - Field

    private var searchField: some View {
        @Bindable var model = appModel
        return VStack(spacing: 0) {
            HStack(spacing: ThemeSpace.x2) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(ThemeColor.textTertiary)
                TextField("Search anime & TV", text: $model.searchQuery)
                    .type(ThemeType.body)
                    .foregroundStyle(ThemeColor.textPrimary)
                    .tint(ThemeColor.accent)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($fieldFocused)
                    // `AppModel.recordRecentSearch()` had no call site anywhere in the app: the
                    // field carried a `.search` submit label and then threw the submission away,
                    // so the RECENT section could only ever show terms left over from an older
                    // build and shrank to nothing on a fresh install. Search is the one screen
                    // whose empty state is built from the user's own history.
                    .onSubmit { appModel.recordRecentSearch() }
                if !appModel.searchQuery.isEmpty {
                    Button {
                        appModel.searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(ThemeColor.textTertiary)
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Copy.Action.clear)
                }
            }
            .padding(.leading, 14)
            .frame(minHeight: 48)
            // A field is separated by TONE, not by an outline: `surfaceFloating` is a real step off
            // the canvas, where `surfaceRaised` + a 12 %-white ring was a wireframe of a text field.
            // Focus is a TONE change plus the accent caret — not a ring. The shipped build drew a
            // 70 %-amber outline round a 376-pt capsule, which put a second amber object on screen
            // beside the selected scope chip; accent belongs to the action, the forward fact, the
            // selection and the link, and a focused text field is none of those.
            .background(fieldFocused ? ThemeColor.surfacePressed : ThemeColor.surfaceFloating, in: Capsule())
            // Board 07's named exception to "nothing animates on its own": a 1-pt bar under the
            // field, and only while a real request is in flight.
            QueryProgressBar(active: appModel.searchBusy)
                .padding(.horizontal, 18)
                .padding(.top, 6)
        }
        .padding(.horizontal, ThemeMetrics.gutter)
        .animation(ThemeMotion.pick(ThemeMotion.uiMicro, reduceMotion: reduceMotion), value: fieldFocused)
    }

    private var scopeRow: some View {
        @Bindable var model = appModel
        return ScrollView(.horizontal) {
            HStack(spacing: ThemeSpace.x2) {
                ForEach(MediaFilter.allCases, id: \.self) { f in
                    let on = appModel.mediaFilter == f
                    Button(f.chipLabel) {
                        FeedbackCoordinator.fire(.selection)
                        withAnimation(ThemeMotion.pick(ThemeMotion.uiMicro, reduceMotion: reduceMotion)) {
                            model.mediaFilter = f
                        }
                    }
                    .buttonStyle(ChipButtonStyle(selected: on))
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(.horizontal, ThemeMetrics.gutter)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Launchpad

    @ViewBuilder
    private var launchpad: some View {
        if !appModel.recentSearches.isEmpty {
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
                    .padding(.horizontal, ThemeMetrics.gutter)
                }
                .scrollIndicators(.hidden)
            }
            .padding(.top, ThemeMetrics.sectionGap)
        }
        if !appModel.trending.isEmpty {
            trendingChart.padding(.top, ThemeMetrics.sectionGap)
        } else if appModel.recentSearches.isEmpty {
            EmptyState(.searchLaunchpad, prominence: .section)
                .padding(.horizontal, ThemeMetrics.gutter)
                .padding(.top, ThemeMetrics.sectionGap)
        }
    }

    /// Trending as a CHART rather than a shelf that stops a third of the way down the screen: the
    /// top five carry full `.shelfLarge` artwork and run off the right edge, the rest continue as
    /// rows. Nothing appears twice, and the section reaches the tab bar.
    private var trendingChart: some View {
        let ranked = Array(appModel.trending.enumerated())
        // At accessibility sizes the shelf goes away entirely: a 116-pt column cannot hold an AX
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
                    .padding(.horizontal, ThemeMetrics.gutter)
                    .padding(.vertical, ThemeSpace.x1)
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
                .padding(.top, ThemeMetrics.labelGap)
            }

            if !rest.isEmpty {
                VStack(spacing: 0) {
                    ForEach(rest, id: \.element.id) { i, item in
                        chartRow(rank: i + 1, item, isLast: item.id == rest.last?.element.id)
                    }
                }
                .padding(.horizontal, ThemeMetrics.gutter)
                .padding(.top, featured.isEmpty ? ThemeMetrics.labelGap : ThemeSpace.x5)
            }
        }
    }

    private func trendingCard(rank: Int, _ item: FranchiseSummary) -> some View {
        let owned = appModel.isInLibrary(item.id)
        let slot = PosterSize.shelfLarge
        return Button { onOpenDetail(item.id, "trend/\(item.id)") } label: {
            VStack(alignment: .leading, spacing: ThemeSpace.x2) {
                PosterSlot(url: item.cover, slot)
                    .overlay(alignment: .bottomLeading) { rankNumeral(rank, slot: slot) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .type(ThemeType.shelfTitle)
                        .foregroundStyle(ThemeColor.textPrimary)
                        // Two reserved lines whether or not the title needs them, so a shelf of
                        // mixed-length titles keeps ONE caption baseline instead of a staircase.
                        .lineLimit(2, reservesSpace: !isAX)
                        .multilineTextAlignment(.leading)
                    Text(shelfCaption(item))
                        .type(ThemeType.shelfCaption)
                        .foregroundStyle(ThemeColor.textSecondary)
                        .lineLimit(1)
                }
                .frame(width: slot.size.width, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle(radius: slot.radius))
        // The badge lives OUTSIDE the card's own button: a Button nested inside another Button's
        // label is a coin-toss for which one gets the tap.
        .overlay(alignment: .topTrailing) { artBadge(item, owned: owned) }
        .accessibilityElement(children: .contain)
    }

    /// The chart position, over the artwork it belongs to. `ArtScrim` supplies the legibility ramp
    /// — nobody hand-rolls a black gradient over a poster.
    private func rankNumeral(_ rank: Int, slot: PosterSize) -> some View {
        Text(String(format: "%02d", rank))
            .type(ThemeType.displayL)
            .monospacedDigit()
            .foregroundStyle(ThemeColor.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
            .frame(maxWidth: slot.size.width, alignment: .leading)
            .background(alignment: .bottom) {
                ArtScrim(top: 0, bottom: 0.72)
                    .frame(height: slot.size.height * 0.45)
                    .clipShape(UnevenRoundedRectangle(
                        bottomLeadingRadius: slot.radius, bottomTrailingRadius: slot.radius,
                        style: .continuous))
            }
            .accessibilityHidden(true)
    }

    /// Ranks six and beyond. Same chart, same facts, row altitude — 48×72 art at `rowStandard`,
    /// the position in a 22-pt leading gutter, one trailing control.
    private func chartRow(rank: Int, _ item: FranchiseSummary, isLast: Bool) -> some View {
        let owned = appModel.isInLibrary(item.id)
        return HStack(spacing: ThemeSpace.x2) {
            Button { onOpenDetail(item.id, "trend/\(item.id)") } label: {
                HStack(spacing: ThemeMetrics.artGap) {
                    Text(String(format: "%02d", rank))
                        .type(ThemeType.rowMeta)
                        .monospacedDigit()
                        .foregroundStyle(ThemeColor.textDisabled)
                        // A fixed 22-pt column broke "05" onto two lines at AX sizes. The gutter
                        // has a minimum, not a maximum.
                        .lineLimit(1)
                        .fixedSize()
                        .frame(minWidth: 22, alignment: .leading)
                        .accessibilityHidden(true)
                    PosterSlot(url: item.cover, .row)
                    VStack(alignment: .leading, spacing: ThemeMetrics.titleGap) {
                        Text(item.title)
                            .type(ThemeType.rowTitle)
                            .foregroundStyle(ThemeColor.textPrimary)
                            .lineLimit(isAX ? nil : 2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(rowSubtitle(item))
                            .type(ThemeType.rowMeta)
                            .foregroundStyle(ThemeColor.textSecondary)
                            // Wraps at AX rather than printing `· Air…`.
                            .lineLimit(isAX ? nil : 1)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: ThemeSpace.x2)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(rank). \(item.title), \(rowSubtitle(item))")
            rowControl(item, owned: owned)
        }
        .padding(.vertical, ThemeSpace.x2)
        .frame(minHeight: ThemeMetrics.rowStandard)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle().fill(ThemeColor.separatorQuiet).frame(height: 1)
                    .padding(.leading, 22 + ThemeMetrics.artGap + PosterSize.row.size.width + ThemeMetrics.artGap)
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

    /// The shape the results are about to take. The shared `Skeleton.search` draws six identical
    /// 52×78 rows and no card, so every element moved when the data landed — which is the one
    /// thing a skeleton exists to prevent. This is the real layout: label, card, rows at exactly
    /// the `.focus` and `.searchRow` geometry the content uses.
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
            centeredState {
                EmptyState(.noFilterMatches, prominence: .section, primary: {
                    FeedbackCoordinator.fire(.selection)
                    withAnimation(ThemeMotion.pick(ThemeMotion.uiSnappy, reduceMotion: reduceMotion)) {
                        appModel.mediaFilter = .all
                    }
                })
            }
        } else if results.isEmpty {
            let copy: EmptyStateCopy = appModel.searchError
                ? (SyncCenter.shared.isOnline ? .searchFailed : .offlineNoData)
                : .noSearchResults(query: query)
            centeredState {
                EmptyState(copy, prominence: .section, primary: appModel.searchError ? { appModel.retrySearch() } : nil)
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                if appModel.searchError {
                    // `Copy.Notice` names the per-catalogue failures (`searchAnime` / `searchTV`)
                    // but not the "both sources, one request" case this screen actually has. The
                    // shipped line is kept verbatim; a `Copy.Notice.search` entry is requested.
                    InlineNotice("Results couldn\u{2019}t refresh") { appModel.retrySearch() }
                        .padding(.horizontal, ThemeMetrics.gutter)
                        .padding(.top, ThemeSpace.x4)
                }
                if let top = results.first {
                    SectionLabel(text: "Top match")
                        .padding(.horizontal, ThemeMetrics.gutter)
                        .padding(.top, ThemeMetrics.sectionGap)
                    topMatch(top).padding(.top, ThemeMetrics.labelGap)
                }
                if results.count > 1 {
                    VStack(spacing: 0) {
                        ForEach(Array(results.dropFirst().enumerated()), id: \.element.id) { i, item in
                            resultRow(item, isLast: i == results.count - 2)
                        }
                    }
                    .padding(.horizontal, ThemeMetrics.gutter)
                    .padding(.top, ThemeSpace.x6)
                }
            }
        }
    }

    /// The one card on the screen: `.raised`, so it is visible because it is LIGHTER, not because
    /// it has a line drawn round it. Its own tap opens the show; adding is one subordinate control.
    private func topMatch(_ item: FranchiseSummary) -> some View {
        let owned = appModel.isInLibrary(item.id)
        return Button { onOpenDetail(item.id, "top/\(item.id)") } label: {
            Group {
                if isAX {
                    VStack(alignment: .leading, spacing: ThemeMetrics.artGap) {
                        PosterSlot(url: item.cover, .focus)
                        topMatchText(item)
                    }
                } else {
                    HStack(alignment: .center, spacing: ThemeMetrics.artGap) {
                        PosterSlot(url: item.cover, .focus)
                        topMatchText(item)
                        // Reserves the trailing control's lane so a long title can never run under it.
                        Spacer(minLength: 78)
                    }
                }
            }
            .padding(ThemeSpace.x4)
            .padding(.bottom, isAX ? 52 : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .surface(.raised, radius: ThemeRadius.card)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle(radius: ThemeRadius.card))
        // Centred on the poster's midline (bottom-trailing at AX, where the card stacks): the
        // control belongs to the whole card, and hanging it in a corner left the card's middle dead.
        .overlay(alignment: isAX ? .bottomTrailing : .trailing) {
            rowControl(item, owned: owned).padding(.trailing, ThemeSpace.x3).padding(.bottom, isAX ? ThemeSpace.x3 : 0)
        }
        .padding(.horizontal, ThemeMetrics.gutter)
        .accessibilityElement(children: .contain)
    }

    private func topMatchText(_ item: FranchiseSummary) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(text: item.source == .tmdb ? "TV" : "Anime")
            Text(item.title)
                .type(ThemeType.showTitleL)
                .foregroundStyle(ThemeColor.textPrimary)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 5)
            // Two short lines rather than one that wraps: `1999 · 45 parts · Tomorrow at 7:46 PM`
            // broke after the separator and left a line ending in a bare "·". A metadata line that
            // has to wrap is two facts, so it is written as two.
            Text(identityFacts(item))
                .type(ThemeType.cardFact)
                .foregroundStyle(ThemeColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, ThemeMetrics.titleGap)
            if let when = airingFact(item) {
                Text(when)
                    .type(ThemeType.metadata)
                    .foregroundStyle(ThemeColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 1)
            }
        }
    }

    private func resultRow(_ item: FranchiseSummary, isLast: Bool) -> some View {
        let owned = appModel.isInLibrary(item.id)
        return MediaRow(
            title: item.title,
            meta: rowSubtitle(item),
            poster: item.cover,
            slot: .searchRow,
            chevron: false,
            separator: !isLast,
            trailing: { rowControl(item, owned: owned) },
            action: { onOpenDetail(item.id, "result/\(item.id)") }
        )
    }

    // MARK: - Add controls

    /// Over artwork: a 26-pt disc sitting INSIDE the art's inset, filled with the same scrim the
    /// art already carries. The shipped 32-pt solid-accent disc planted on the corner was a sticker
    /// on a poster. Only the settled ✓ is allowed accent — an add is not a next step, it is a verb.
    private func artBadge(_ item: FranchiseSummary, owned: Bool) -> some View {
        Button {
            guard !owned else { return }
            appModel.addToLibrary(franchiseId: item.id, title: item.title, isReleasing: item.isReleasing)
        } label: {
            Image(systemName: owned ? "checkmark" : "plus")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(owned ? ThemeColor.accent : ThemeColor.textPrimary)
                .frame(width: 26, height: 26)
                .background(ThemeColor.scrimStrong, in: Circle())
                .overlay(Circle().strokeBorder(ThemeColor.hairline, lineWidth: 1))
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(owned)
        // 26-pt disc centred in a 44-pt target: -1 puts the visible disc 8 pt inside the artwork.
        .padding(-1)
        .accessibilityLabel(owned ? "In your library" : "\(Copy.Action.add) \(item.title)")
    }

    /// In a row or a card, where there is no artwork behind it: a labelled control, because a bare
    /// glyph on a dark row is a guess. `PassiveTick` when it is already a settled fact.
    @ViewBuilder
    private func rowControl(_ item: FranchiseSummary, owned: Bool) -> some View {
        if owned {
            PassiveTick(boxed: true)
                .accessibilityLabel("In your library")
        } else {
            Button(Copy.Action.add) {
                appModel.addToLibrary(franchiseId: item.id, title: item.title, isReleasing: item.isReleasing)
            }
            .buttonStyle(CompactActionButtonStyle())
            .accessibilityLabel("\(Copy.Action.add) \(item.title)")
        }
    }

    // MARK: - Copy helpers

    private func centeredState(@ViewBuilder _ content: () -> some View) -> some View {
        content()
            .padding(.horizontal, ThemeMetrics.gutter)
            .frame(maxWidth: .infinity, minHeight: 300, alignment: .center)
            .padding(.top, ThemeSpace.x5)
    }

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

    /// What the title IS: year and size. Always fits, in every context on this screen.
    private func identityFacts(_ item: FranchiseSummary) -> String {
        if let y = item.year { return "\(y) \u{00B7} \(parts(item))" }
        return parts(item)
    }

    /// When the next part lands. Its own line on the top match; folded to the word "Airing" in a
    /// row, where a full date would have to truncate — and `· Friday…` is not a fact.
    private func airingFact(_ item: FranchiseSummary) -> String? {
        guard item.isReleasing else { return nil }
        if let at = item.nextAiringAt, at > now {
            return TemporalCopy.airs(at: at, now: now, source: item.source)
        }
        return "Airing"
    }

    /// At AX sizes the third fact is dropped rather than allowed to wrap: `2026 · 2 parts` followed
    /// by a line that begins `· Airing` is a broken sentence, and the rule is drop, never break.
    private func rowSubtitle(_ item: FranchiseSummary) -> String {
        item.isReleasing && !isAX ? "\(identityFacts(item)) \u{00B7} Airing" : identityFacts(item)
    }

    /// 116 pt of caption. Two facts fit; three do not.
    private func shelfCaption(_ item: FranchiseSummary) -> String { identityFacts(item) }

    private func parts(_ item: FranchiseSummary) -> String {
        item.partCount == 1 ? "1 part" : "\(item.partCount) parts"
    }
}
