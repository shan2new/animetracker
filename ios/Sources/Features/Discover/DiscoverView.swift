import SwiftUI

// Search surface (reached via the tab bar's magnifier button). Header is the exact Library
// grammar — large title + in-content SearchField — instead of the system search island (whose
// morph dropped frames). While search is active (field focused or a query present) the large
// title eases away and the field docks to the top. Body states:
//  - empty query  → the launchpad: recent-search chips + a numbered trending shelf,
//  - searching    → skeletons, then a top-match hero over disambiguation rows, or one of the two
//    empty states (nothing matched at all / the scope chip is hiding everything that did).
// Every one of those states keys on `results` — the FILTERED list, which is also the only list
// rendered — so a scope can never leave the screen blank. The chips exist only while a query does,
// so clearing the query also clears the scope.
// Adding to library (with undo, via ToastHost) is one tap on any result's — or trending card's —
// circle; the detail sheet is never required just to add.
struct DiscoverView: View {
    @Environment(AppModel.self) private var appModel
    let onOpenDetail: (_ franchiseId: String, _ zoomID: String) -> Void

    @State private var fieldFocused = false
    @State private var scrolled = false

    private var queryEmpty: Bool {
        appModel.searchQuery.trimmingCharacters(in: .whitespaces).isEmpty
    }
    /// The only list the body ever renders. Every state below keys on THIS — keying on the
    /// unfiltered `searchResults` while rendering the filtered one is how a scope that excludes
    /// every match produced a blank screen with no state at all.
    private var results: [FranchiseSummary] { appModel.filteredSearchResults }
    private var showSkeletons: Bool { appModel.searchBusy && results.isEmpty }
    /// The scope chip — not the query — is why nothing is on screen: the server did return
    /// matches for this query, they're all the other kind.
    private var scopedEmpty: Bool {
        appModel.mediaFilter != .all && results.isEmpty && !appModel.searchResults.isEmpty
    }
    /// Search is "active" the moment the field is focused or a query exists — the large title
    /// collapses and the whole screen eases upward, exactly as the field takes over.
    private var searchActive: Bool { fieldFocused || !queryEmpty }

    var body: some View {
        @Bindable var model = appModel
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !searchActive {
                    Text("Search")
                        .scaledFont(30, weight: .bold)
                        .tracking(-0.8)
                        .padding(.horizontal, Theme.Space.gutter)
                        .padding(.bottom, 12)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .top)),
                            removal: .opacity.combined(with: .move(edge: .top))
                        ))
                }

                SearchField(text: $model.searchQuery, prompt: "Search anime & TV",
                            onFocusChange: { fieldFocused = $0 })
                    .padding(.horizontal, Theme.Space.gutter)
                    .onSubmit { appModel.recordRecentSearch() }

                if !queryEmpty {
                    scopeRow
                        .padding(.horizontal, Theme.Space.gutter)
                        .padding(.top, 12)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                searchBody
                    .padding(.top, 16)
            }
            .padding(.top, 8)
            .padding(.bottom, 120)
            .animation(.uiGentle, value: searchActive)
            .animation(.uiGentle, value: queryEmpty)
        }
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .background(AppBackground())
        .task {
            appModel.loadTrendingIfNeeded()
            // The scope chips only exist while a query does, so a filter left over from a previous
            // session/visit would be invisible and unremovable. Arrive unscoped.
            if queryEmpty { appModel.mediaFilter = .all }
        }
        // Same rule on the way out: clearing the box clears the scope, so a stale invisible
        // filter can never survive into the next search.
        .onChange(of: queryEmpty) { _, isEmpty in
            guard isEmpty, appModel.mediaFilter != .all else { return }
            withAnimation(.uiGentle) { appModel.mediaFilter = .all }
        }
        .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y > 64 } action: { _, isPast in
            withAnimation(.uiGentle) { scrolled = isPast }
        }
        .overlay(alignment: .top) { compactHeader }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
    }

    // Blurred compact bar once the large title scrolls away — same pattern as Library. Hidden
    // while search is active (the title is already gone; results own the full height).
    @ViewBuilder
    private var compactHeader: some View {
        if scrolled && !searchActive {
            Text("Search")
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

    // All / Anime / TV — replaces the system search scopes now that the field is ours.
    private var scopeRow: some View {
        HStack(spacing: 7) {
            ForEach(MediaFilter.allCases, id: \.self) { scope in
                let selected = appModel.mediaFilter == scope
                Button {
                    guard !selected else { return }
                    Haptics.selection()
                    withAnimation(.uiSnappy) { appModel.mediaFilter = scope }
                } label: {
                    Text(scope.chipLabel)
                        .scaledFont(12.5, weight: .semibold)
                        .foregroundStyle(selected ? Theme.background : Theme.text62)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background {
                            if selected {
                                Capsule().fill(Theme.accent)
                            } else {
                                Capsule().stroke(Theme.hairlineStrong, lineWidth: 1)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    private var searchBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Re-query sweep while results are already on screen — keeps the screen feeling live.
            // Complementary to `showSkeletons`: busy + nothing rendered → skeletons, busy + rows
            // rendered → this bar. Both read the filtered list, so the two can't both be false.
            if appModel.searchBusy && !results.isEmpty {
                IndeterminateBar()
                    .padding(.horizontal, Theme.Space.gutter)
                    .padding(.bottom, 13)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // A refresh failed while older results are still on screen — say so instead of
            // silently presenting stale results as current.
            if appModel.searchError && !results.isEmpty && !queryEmpty {
                staleResultsBanner
                    .padding(.horizontal, Theme.Space.gutter)
                    .padding(.bottom, 13)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            ZStack(alignment: .top) {
                if queryEmpty {
                    launchpad.transition(.opacity)
                } else if showSkeletons {
                    skeletonList
                        .padding(.horizontal, Theme.Space.gutter)
                        .transition(.opacity)
                } else if scopedEmpty {
                    scopedNoResultsState.transition(.opacity)
                } else if results.isEmpty {
                    noResultsState.transition(.opacity)
                } else {
                    resultsList
                        .padding(.horizontal, Theme.Space.gutter)
                        .transition(.opacity)
                }
            }
        }
        .animation(.uiGentle, value: showSkeletons)
        .animation(.uiGentle, value: appModel.searchBusy)
        .animation(.uiGentle, value: results.isEmpty)
        .animation(.uiGentle, value: appModel.mediaFilter)
        .animation(.uiGentle, value: queryEmpty)
    }

    /// Mono-caps section eyebrow ("RECENT", "TOP MATCH", …) — the launchpad's quiet grammar.
    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .scaledFont(11, weight: .semibold)
            .tracking(1.6)
            .foregroundStyle(Theme.text50)
    }

    // MARK: launchpad (empty-query state)

    @ViewBuilder
    private var launchpad: some View {
        if appModel.recentSearches.isEmpty && appModel.trending.isEmpty {
            VStack(spacing: 11) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 33, weight: .light))
                    .foregroundStyle(Theme.text36)
                    .padding(.bottom, 2)
                Text("Search for anime & TV to add")
                    .scaledFont(15, weight: .semibold)
                    .foregroundStyle(Theme.text72)
                Text("Find a series and add it to your library.")
                    .scaledFont(13)
                    .foregroundStyle(Theme.text40)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 80)
            .padding(.horizontal, 24)
        } else {
            VStack(alignment: .leading, spacing: Theme.Space.section) {
                if !appModel.recentSearches.isEmpty {
                    recentChips.padding(.horizontal, Theme.Space.gutter)
                }
                if !appModel.trending.isEmpty {
                    trendingSection.transition(.opacity)
                }
            }
            .padding(.top, 8)
            .animation(.uiGentle, value: appModel.trending.isEmpty)
        }
    }

    private var recentChips: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                sectionLabel("RECENT")
                Spacer()
                Button { appModel.clearRecentSearches() } label: {
                    Text("Clear")
                        .scaledFont(12.5, weight: .semibold)
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
            }
            FlexibleWrap(spacing: 9, lineSpacing: 9) {
                ForEach(appModel.recentSearches, id: \.self) { term in
                    recentChip(term)
                }
            }
        }
    }

    /// Two SIBLING controls, not one nested inside the other: re-running the search owns the pill,
    /// removing the term owns a 40pt target laid over the pill's trailing padding. Nested, the tiny
    /// glyph sat under the chip's own content shape, so a near-miss re-ran the search instead of
    /// deleting — and VoiceOver read the whole thing out as "xmark".
    private func recentChip(_ term: String) -> some View {
        Button { appModel.searchQuery = term } label: {
            Text(term)
                .scaledFont(14, weight: .medium)
                .foregroundStyle(Theme.text90)
                .lineLimit(1)
                .padding(.leading, 15)
                .padding(.trailing, 36)   // room the delete control sits in
                .padding(.vertical, 8)
                .background(Theme.fillSoft, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(SpringPressButtonStyle(scale: 0.96))
        .overlay(alignment: .trailing) {
            Button {
                Haptics.impact(.soft)
                withAnimation(.uiGentle) { appModel.removeRecentSearch(term) }
            } label: {
                Image(systemName: "xmark")
                    .scaledFont(10, weight: .semibold)
                    .foregroundStyle(Theme.text36)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove “\(term)” from recent searches")
        }
    }

    // MARK: trending shelf

    private var trendingSection: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 7) {
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 5, height: 5)
                    .shadow(color: Theme.accentGlow, radius: 4)
                sectionLabel("TRENDING NOW")
                Spacer()
                Text(seasonTag)
                    .scaledFont(10.5, weight: .medium, monospacedDigit: true)
                    .tracking(1)
                    .foregroundStyle(Theme.text36)
            }
            .padding(.horizontal, Theme.Space.gutter)

            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(Array(appModel.trending.enumerated()), id: \.element.id) { i, summary in
                        trendingCell(rank: i + 1, summary)
                    }
                }
                .padding(.horizontal, Theme.Space.gutter)
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
            .scrollClipDisabled()   // let poster shadows breathe past the shelf bounds
        }
    }

    /// "SUMMER ’26" — the season the trending list reflects, derived from the live clock.
    private var seasonTag: String {
        let date = Date(timeIntervalSince1970: TimeInterval(appModel.now) / 1000)
        let comps = Calendar.current.dateComponents([.month, .year], from: date)
        let season: String
        switch comps.month ?? 1 {
        case 3...5:  season = "SPRING"
        case 6...8:  season = "SUMMER"
        case 9...11: season = "FALL"
        default:     season = "WINTER"
        }
        return "\(season) ’\(String(format: "%02d", (comps.year ?? 0) % 100))"
    }

    private func trendingCell(rank: Int, _ summary: FranchiseSummary) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        let owned = appModel.isInLibrary(summary.id)
        return Button {
            onOpenDetail(summary.id, "trend/\(summary.id)")
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    RemoteImageView(url: summary.cover, maxPixel: 400)
                        .frame(width: 132, height: 184)
                    LinearGradient(colors: [.clear, Color.black.opacity(0.72)],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 86)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                    Text(String(format: "%02d", rank))
                        .scaledFont(34, weight: .bold)
                        .tracking(-0.8)
                        .foregroundStyle(Theme.accent.opacity(0.92))
                        .shadow(color: .black.opacity(0.5), radius: 6, y: 2)
                        .padding(.leading, 10)
                        .padding(.bottom, 4)
                }
                .background(Theme.surface)
                .clipShape(shape)
                .overlay(shape.stroke(Theme.hairlineStrong, lineWidth: 1))
                // This tab's whole job is adding — trending must not be the one shelf where that
                // takes a detail-sheet round trip. Same circle as the result rows, backed with a
                // scrim so the ghost fill stays legible over bright art.
                .overlay(alignment: .topTrailing) {
                    AddCircle(owned: owned) { add(summary) }
                        .background(Color.black.opacity(0.42), in: Circle())
                        .padding(7)
                }
                .shadow(color: .black.opacity(0.35), radius: 14, y: 8)

                Text(summary.title)
                    .scaledFont(12.5, weight: .semibold)
                    .foregroundStyle(Theme.text90)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(height: 34, alignment: .topLeading)
                    .padding(.top, 9)

                HStack(spacing: 5) {
                    SourceGlyph(source: summary.source, size: 10)
                    Text(trailingMeta(summary))
                        .scaledFont(10, weight: .medium, monospacedDigit: true)
                        .tracking(0.6)
                        .foregroundStyle(Theme.text50)
                        .lineLimit(1)
                }
                .padding(.top, 4)
            }
            .frame(width: 132)
            .contentShape(Rectangle())
        }
        .buttonStyle(SpringPressButtonStyle(scale: 0.97))
        .zoomSource("trend/\(summary.id)")
        .contextMenu { resultContextMenu(summary) }
    }

    // MARK: search results (top match + disambiguation rows)

    private var resultsList: some View {
        let results = self.results
        return VStack(alignment: .leading, spacing: 0) {
            if let top = results.first {
                sectionLabel("TOP MATCH")
                    .padding(.bottom, 11)
                topMatchHero(top)
            }
            if results.count > 1 {
                VStack(spacing: 0) {
                    ForEach(results.dropFirst()) { summary in
                        resultRow(summary)
                        if summary.id != results.last?.id {
                            HairlineDivider(inset: 71)
                        }
                    }
                }
                .padding(.top, 6)
            }
        }
        .animation(.uiSmooth, value: results.map(\.id))
    }

    /// The first (most relevant) result, staged: cover art blurred into a backdrop, the poster
    /// sharp on top — the schedule hero's non-destructive treatment, no banner crop needed.
    private func topMatchHero(_ summary: FranchiseSummary) -> some View {
        let owned = appModel.isInLibrary(summary.id)
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        return Button {
            appModel.recordRecentSearch()   // acting on a result = a useful search
            onOpenDetail(summary.id, "disc/\(summary.id)")
        } label: {
            HStack(alignment: .top, spacing: 14) {
                Thumb(cover: summary.cover, width: 88, height: 124, radius: 12)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1))
                    .shadow(color: .black.opacity(0.4), radius: 12, y: 6)

                VStack(alignment: .leading, spacing: 0) {
                    Text(highlighted(summary.title, size: 17.5))
                        .scaledFont(17.5, weight: .bold)
                        .tracking(-0.3)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 6) {
                        SourceGlyph(source: summary.source, size: 11)
                        Text(trailingMeta(summary, parts: true))
                            .scaledFont(11, weight: .medium, monospacedDigit: true)
                            .tracking(0.6)
                            .foregroundStyle(Theme.text72)
                    }
                    .padding(.top, 7)

                    Spacer(minLength: 12)

                    HStack(spacing: 8) {
                        if owned {
                            libraryChip(summary)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .scaledFont(12, weight: .semibold)
                                .foregroundStyle(Theme.text40)
                        } else {
                            Spacer(minLength: 0)
                            AddCircle(owned: false) { add(summary) }
                        }
                    }
                }
                .frame(minHeight: 124)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                // Blurred self-cover backdrop under a warm scrim; rasterized so the live Gaussian
                // blur isn't re-evaluated while the list scrolls.
                ZStack {
                    RemoteImageView(url: summary.banner ?? summary.cover, maxPixel: 500)
                        .scaleEffect(1.35)
                        .blur(radius: 30)
                        .opacity(0.55)
                    LinearGradient(colors: [Color(hex: 0x14110D).opacity(0.30),
                                            Color(hex: 0x14110D).opacity(0.82)],
                                   startPoint: .top, endPoint: .bottom)
                }
                .drawingGroup()
            }
            .clipShape(shape)
            .overlay(shape.stroke(Theme.hairlineStrong, lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 20, y: 10)
            .contentShape(shape)
        }
        .buttonStyle(SpringPressButtonStyle(scale: 0.98))
        .zoomSource("disc/\(summary.id)")
        .contextMenu { resultContextMenu(summary) }
    }

    /// "✓ IN LIBRARY · WATCHING" glass chip on an owned top match.
    private func libraryChip(_ summary: FranchiseSummary) -> some View {
        var label = "✓ IN LIBRARY"
        if let status = appModel.franchise(id: summary.id)?.status {
            label += " · \(Copy.Status(status).uppercased())"
        }
        return Text(label)
            .scaledFont(9, weight: .semibold, monospacedDigit: true)
            .tracking(1)
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.35), in: Capsule())
            .overlay(Capsule().stroke(Theme.accentBorder, lineWidth: 1))
            .lineLimit(1)
    }

    private func resultRow(_ summary: FranchiseSummary) -> some View {
        let owned = appModel.isInLibrary(summary.id)
        return Button {
            appModel.recordRecentSearch()
            onOpenDetail(summary.id, "disc/\(summary.id)")
        } label: {
            HStack(spacing: 13) {
                Thumb(cover: summary.cover, width: 58, height: 82, radius: 10)
                VStack(alignment: .leading, spacing: 5) {
                    Text(highlighted(summary.title, size: 15))
                        .scaledFont(15, weight: .semibold)
                        .tracking(-0.2)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        SourceGlyph(source: summary.source, size: 11)
                        Text(trailingMeta(summary, parts: true))
                            .scaledFont(11, weight: .medium, monospacedDigit: true)
                            .tracking(0.6)
                            .foregroundStyle(Theme.text50)
                            .lineLimit(1)
                    }
                    if owned {
                        Text("✓ IN LIBRARY")
                            .scaledFont(9, weight: .semibold)
                            .tracking(1)
                            .foregroundStyle(Theme.accent)
                    }
                }
                Spacer(minLength: 10)
                AddCircle(owned: owned) { add(summary) }
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(SpringPressButtonStyle(scale: 0.98))
        .zoomSource("disc/\(summary.id)")
        .contextMenu { resultContextMenu(summary) }
    }

    /// Year, optionally with the season/part count — the row's one differentiating-facts line.
    private func trailingMeta(_ summary: FranchiseSummary, parts: Bool = false) -> String {
        var bits: [String] = []
        if let year = summary.year { bits.append(String(year)) }
        if parts, summary.partCount > 1 { bits.append("\(summary.partCount) PARTS") }
        if bits.isEmpty { bits.append(summary.isReleasing ? "AIRING" : "SERIES") }
        return bits.joined(separator: " · ")
    }

    private func add(_ summary: FranchiseSummary) {
        appModel.recordRecentSearch()
        appModel.addToLibrary(franchiseId: summary.id,
                              title: summary.title,
                              isReleasing: summary.isReleasing)
    }

    @ViewBuilder
    private func resultContextMenu(_ summary: FranchiseSummary) -> some View {
        if let owned = appModel.franchise(id: summary.id) {
            FranchiseContextMenu(f: owned, appModel: appModel)
        } else {
            Button {
                add(summary)
            } label: {
                Label("Add to library", systemImage: "plus")
            }
        }
    }

    /// Title with the matched query span tinted accent — the "why this result" cue while typing.
    private func highlighted(_ title: String, size: CGFloat) -> AttributedString {
        var attributed = AttributedString(title)
        let query = appModel.searchQuery.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty,
           let match = title.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]),
           let range = Range(match, in: attributed) {
            attributed[range].foregroundColor = Theme.accent
        }
        return attributed
    }

    // MARK: loading / error / empty fallbacks

    // Skeletons in the results-list shape: a hero-sized slab over three ghost rows.
    private var skeletonList: some View {
        VStack(alignment: .leading, spacing: 0) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Theme.surface)
                .frame(height: 152)
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Theme.hairline, lineWidth: 1))
                .shimmering()
                .padding(.bottom, 6)
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 13) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.surface)
                        .frame(width: 58, height: 82)
                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.07))
                            .frame(width: 150, height: 12)
                        RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.05))
                            .frame(width: 90, height: 9)
                    }
                    Spacer()
                    Circle().fill(Theme.surface).frame(width: 34, height: 34)
                }
                .padding(.vertical, 12)
                .shimmering()
            }
        }
    }

    // Inline notice above a list of now-stale results after a failed re-query.
    private var staleResultsBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.exclamationmark")
                .scaledFont(12, weight: .semibold)
                .foregroundStyle(Theme.accent)
            Text("Couldn't refresh — results may be out of date.")
                .scaledFont(12.5)
                .foregroundStyle(Theme.text72)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Retry") { Haptics.impact(.soft); appModel.retrySearch() }
                .scaledFont(12.5, weight: .semibold)
                .foregroundStyle(Theme.accent)
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.accentBorder, lineWidth: 1))
    }

    /// The query DID match — the scope chip is hiding all of it. Name the scope, say how much is
    /// waiting behind it, and hand back one tap to All.
    private var scopedNoResultsState: some View {
        let trimmed = appModel.searchQuery.trimmingCharacters(in: .whitespaces)
        let scope = appModel.mediaFilter.chipLabel
        let hidden = appModel.searchResults.count
        return VStack(spacing: 11) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 33, weight: .light))
                .foregroundStyle(Theme.text36)
                .padding(.bottom, 2)
            Text("No \(scope) matches")
                .scaledFont(15, weight: .semibold)
                .foregroundStyle(Theme.text72)
            Text("Nothing under \(scope) matches “\(trimmed).” \(hidden == 1 ? "1 result is" : "\(hidden) results are") hidden by this filter.")
                .scaledFont(13)
                .foregroundStyle(Theme.text40)
                .multilineTextAlignment(.center)
            Button {
                Haptics.selection()
                withAnimation(.uiSnappy) { appModel.mediaFilter = .all }
            } label: {
                Text("Show all results")
                    .scaledFont(14, weight: .semibold)
                    .foregroundStyle(Theme.background)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
            }
            .buttonStyleProminentGlass()
            .clipShape(Capsule())
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 72)
        .padding(.horizontal, 24)
    }

    // Centered fallback while searching — a failed fetch or a query with no matches.
    private var noResultsState: some View {
        let trimmed = appModel.searchQuery.trimmingCharacters(in: .whitespaces)
        return VStack(spacing: 11) {
            Image(systemName: appModel.searchError ? "wifi.exclamationmark" : "magnifyingglass")
                .font(.system(size: 33, weight: .light))
                .foregroundStyle(Theme.text36)
                .padding(.bottom, 2)
            Text(appModel.searchError ? "Couldn't reach the server" : "No results")
                .scaledFont(15, weight: .semibold)
                .foregroundStyle(Theme.text72)
            Text(appModel.searchError ? "Check your connection and try again."
                                      : "Nothing matches “\(trimmed).” Try another title.")
                .scaledFont(13)
                .foregroundStyle(Theme.text40)
                .multilineTextAlignment(.center)
            if appModel.searchError {
                Button {
                    Haptics.impact(.soft)
                    appModel.retrySearch()
                } label: {
                    Text("Retry")
                        .scaledFont(14, weight: .semibold)
                        .foregroundStyle(Theme.background)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                }
                .buttonStyleProminentGlass()
                .clipShape(Capsule())
                .padding(.top, 10)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 72)
        .padding(.horizontal, 24)
    }
}

/// The one-tap add circle on every search result. `+` (quiet ghost) flips to an accent `✓` the
/// instant the optimistic add lands — undo lives in the toast, so the ✓ is a passive indicator.
/// Disabled once owned: a control with nothing left to do must not keep bouncing under taps.
private struct AddCircle: View {
    let owned: Bool
    let action: () -> Void

    var body: some View {
        Button {
            guard !owned else { return }
            action()
        } label: {
            Image(systemName: owned ? "checkmark" : "plus")
                .scaledFont(13, weight: .bold)
                .foregroundStyle(owned ? Theme.accent : Theme.text72)
                .frame(width: 34, height: 34)
                .background(owned ? Theme.accentChipFill : Theme.fillSoft, in: Circle())
                .overlay(Circle().stroke(owned ? Theme.accentBorder : Theme.hairlineStrong,
                                         lineWidth: 1))
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(BounceButtonStyle())
        .disabled(owned)
        .animation(.uiBouncy, value: owned)
        .accessibilityLabel(owned ? "In library" : "Add to library")
    }
}
