import SwiftUI

// Search (spec board 07). Empty query = the launchpad (recent searches + the trending shelf);
// a query = results with a top match, scope chips, and honest states (skeleton · no results ·
// server failure · stale results). Adding is one tap with Undo through the shared toast.
struct DiscoverView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onOpenDetail: (_ franchiseId: String, _ zoomID: String) -> Void

    @FocusState private var fieldFocused: Bool

    private var now: Int64 { appModel.now }
    private var query: String { appModel.searchQuery.trimmingCharacters(in: .whitespaces) }
    private var results: [FranchiseSummary] { appModel.filteredSearchResults }
    private var scopedOut: Bool { appModel.mediaFilter != .all && results.isEmpty && !appModel.searchResults.isEmpty }

    var body: some View {
        @Bindable var model = appModel
        ScrollView {
            VStack(alignment: .leading, spacing: ThemeSpace.x4) {
                Text("Search").type(ThemeType.screenTitle).foregroundStyle(ThemeColor.textPrimary)
                    .padding(.horizontal, ThemeSpace.x4).padding(.top, ThemeSpace.x2)
                searchField
                if query.isEmpty {
                    launchpad
                } else {
                    scopeRow
                    searchBody
                }
            }
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(ThemeColor.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { appModel.loadTrendingIfNeeded() }
        .animation(ThemeMotion.pick(ThemeMotion.uiGentle, reduceMotion: reduceMotion), value: query.isEmpty)
    }

    // MARK: - Field

    private var searchField: some View {
        @Bindable var model = appModel
        return HStack(spacing: ThemeSpace.x2) {
            Image(systemName: "magnifyingglass").font(.system(size: 15, weight: .medium)).foregroundStyle(ThemeColor.textTertiary)
            TextField("Search anime & TV", text: $model.searchQuery)
                .type(ThemeType.body)
                .foregroundStyle(ThemeColor.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($fieldFocused)
            if !appModel.searchQuery.isEmpty {
                Button {
                    appModel.searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundStyle(ThemeColor.textTertiary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Copy.Action.clear)
            }
        }
        .padding(.leading, 14)
        .frame(minHeight: 48)
        .background(ThemeColor.surfaceRaised, in: Capsule())
        .overlay(Capsule().stroke(fieldFocused ? ThemeColor.focusRing : ThemeColor.stroke, lineWidth: 1))
        .padding(.horizontal, ThemeSpace.x4)
    }

    private var scopeRow: some View {
        @Bindable var model = appModel
        return HStack(spacing: ThemeSpace.x2) {
            ForEach(MediaFilter.allCases, id: \.self) { f in
                let on = appModel.mediaFilter == f
                Button {
                    FeedbackCoordinator.fire(.selection)
                    withAnimation(ThemeMotion.pick(ThemeMotion.uiMicro, reduceMotion: reduceMotion)) { model.mediaFilter = f }
                } label: {
                    Text(f.chipLabel).type(ThemeType.metadataEmphasis)
                        .foregroundStyle(on ? ThemeColor.onAccent : ThemeColor.textPrimary)
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .background(on ? ThemeColor.accent : ThemeColor.surfaceRaised, in: Capsule())
                        .overlay(Capsule().stroke(on ? .clear : ThemeColor.stroke, lineWidth: 1))
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
            Spacer()
        }
        .padding(.horizontal, ThemeSpace.x4)
    }

    // MARK: - Launchpad

    @ViewBuilder
    private var launchpad: some View {
        if !appModel.recentSearches.isEmpty {
            VStack(alignment: .leading, spacing: ThemeSpace.x3) {
                SectionHeaderRow("Recent", actionLabel: Copy.Action.clear) { appModel.clearRecentSearches() }
                    .padding(.horizontal, ThemeSpace.x4)
                ScrollView(.horizontal) {
                    HStack(spacing: ThemeSpace.x2) {
                        ForEach(appModel.recentSearches, id: \.self) { term in
                            HStack(spacing: 6) {
                                Button(term) { appModel.searchQuery = term }
                                    .buttonStyle(.plain)
                                Button {
                                    withAnimation(ThemeMotion.pick(ThemeMotion.uiSnappy, reduceMotion: reduceMotion)) { appModel.removeRecentSearch(term) }
                                } label: {
                                    Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).frame(width: 28, height: 32)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove \(term)")
                            }
                            .type(ThemeType.metadataEmphasis)
                            .foregroundStyle(ThemeColor.textPrimary)
                            .padding(.leading, 14)
                            .frame(height: 36)
                            .background(ThemeColor.surfaceRaised, in: Capsule())
                            .overlay(Capsule().stroke(ThemeColor.stroke, lineWidth: 1))
                        }
                    }
                    .padding(.horizontal, ThemeSpace.x4)
                }
                .scrollIndicators(.hidden)
            }
        }
        if !appModel.trending.isEmpty {
            VStack(alignment: .leading, spacing: ThemeSpace.x3) {
                SectionHeaderRow("Trending now", dot: true).padding(.horizontal, ThemeSpace.x4)
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: ThemeSpace.x3) {
                        ForEach(Array(appModel.trending.enumerated()), id: \.element.id) { i, item in
                            trendingCard(rank: i + 1, item)
                        }
                    }
                    .padding(.horizontal, ThemeSpace.x4)
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
            }
        } else if appModel.recentSearches.isEmpty {
            EmptyState(.searchLaunchpad, prominence: .section).padding(.horizontal, ThemeSpace.x4)
        }
    }

    private func trendingCard(rank: Int, _ item: FranchiseSummary) -> some View {
        let owned = appModel.isInLibrary(item.id)
        return Button { onOpenDetail(item.id, "trend/\(item.id)") } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .bottomLeading) {
                    PosterSlot(url: item.cover, width: 132, height: 198)
                    Text(String(format: "%02d", rank))
                        .type(ThemeType.displayL).foregroundStyle(ThemeColor.textPrimary.opacity(0.92))
                        .padding(10)
                        .accessibilityHidden(true)
                }
                .overlay(alignment: .topTrailing) { addBadge(item, owned: owned).padding(8) }
                Text(item.title).type(ThemeType.showTitleS).foregroundStyle(ThemeColor.textPrimary)
                    .lineLimit(2).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                Text(subtitle(item)).type(ThemeType.caption).foregroundStyle(ThemeColor.textTertiary).lineLimit(1)
            }
            .frame(width: 132, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(rank). \(item.title), \(subtitle(item))\(owned ? ", in your library" : "")")
    }

    // MARK: - Results

    @ViewBuilder
    private var searchBody: some View {
        if appModel.searchBusy && results.isEmpty && !scopedOut {
            Skeleton.search
        } else if scopedOut {
            EmptyState(.noFilterMatches, prominence: .section, primary: {
                FeedbackCoordinator.fire(.selection)
                withAnimation(ThemeMotion.pick(ThemeMotion.uiSnappy, reduceMotion: reduceMotion)) { appModel.mediaFilter = .all }
            })
            .padding(.horizontal, ThemeSpace.x4)
        } else if results.isEmpty {
            let copy: EmptyStateCopy = appModel.searchError
                ? (SyncCenter.shared.isOnline ? .searchFailed : .offlineNoData)
                : .noSearchResults(query: query)
            EmptyState(copy, prominence: .section, primary: appModel.searchError ? { appModel.retrySearch() } : nil)
                .padding(.horizontal, ThemeSpace.x4)
        } else {
            VStack(alignment: .leading, spacing: ThemeSpace.x3) {
                if appModel.searchError {
                    InlineNotice("Results couldn\u{2019}t refresh") { appModel.retrySearch() }.padding(.horizontal, ThemeSpace.x4)
                }
                if let top = results.first {
                    SectionLabel(text: "Top match").padding(.horizontal, ThemeSpace.x4)
                    topMatch(top)
                }
                if results.count > 1 {
                    VStack(spacing: 0) {
                        ForEach(Array(results.dropFirst().enumerated()), id: \.element.id) { i, item in
                            resultRow(item, isLast: i == results.count - 2)
                        }
                    }
                    .background(ThemeColor.surfaceRaised, in: RoundedRectangle(cornerRadius: ThemeRadius.row, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: ThemeRadius.row, style: .continuous).stroke(ThemeColor.separator, lineWidth: 1))
                    .padding(.horizontal, ThemeSpace.x4)
                }
            }
        }
    }

    private func topMatch(_ item: FranchiseSummary) -> some View {
        let owned = appModel.isInLibrary(item.id)
        return Button { onOpenDetail(item.id, "top/\(item.id)") } label: {
            HStack(alignment: .top, spacing: ThemeSpace.x4) {
                PosterSlot(url: item.cover, width: 80, height: 120)
                VStack(alignment: .leading, spacing: 5) {
                    SectionLabel(text: item.source == .tmdb ? "TV" : "Anime")
                    Text(item.title).type(ThemeType.showTitleL).foregroundStyle(ThemeColor.textPrimary)
                        .lineLimit(3).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    Text(subtitle(item)).type(ThemeType.metadata).foregroundStyle(ThemeColor.textSecondary).lineLimit(2)
                    Spacer(minLength: 0)
                    if owned {
                        Text(item.status.map { "In your library · \($0.displayName)" } ?? "In your library")
                            .type(ThemeType.metadataEmphasis).foregroundStyle(ThemeColor.textTertiary)
                    } else {
                        Button(Copy.Action.add) { appModel.addToLibrary(franchiseId: item.id, title: item.title, isReleasing: item.isReleasing) }
                            .buttonStyle(CompactActionButtonStyle())
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(ThemeSpace.x4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ThemeColor.surfaceFlat, in: RoundedRectangle(cornerRadius: ThemeRadius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: ThemeRadius.card, style: .continuous).stroke(ThemeColor.separator, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .padding(.horizontal, ThemeSpace.x4)
        .accessibilityLabel("\(item.title), \(subtitle(item))\(owned ? ", in your library" : "")")
    }

    private func resultRow(_ item: FranchiseSummary, isLast: Bool) -> some View {
        let owned = appModel.isInLibrary(item.id)
        return HStack(spacing: ThemeSpace.x3) {
            Button { onOpenDetail(item.id, "result/\(item.id)") } label: {
                HStack(spacing: ThemeSpace.x3) {
                    PosterSlot(url: item.cover, width: 40, height: 60)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).type(ThemeType.showTitleS).foregroundStyle(ThemeColor.textPrimary).lineLimit(2)
                        Text(subtitle(item)).type(ThemeType.metadata).foregroundStyle(ThemeColor.textSecondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            addBadge(item, owned: owned)
        }
        .padding(.leading, 14).padding(.trailing, 10)
        .frame(minHeight: 68)
        .overlay(alignment: .bottom) {
            if !isLast { Rectangle().fill(ThemeColor.separator).frame(height: 1).padding(.leading, 66) }
        }
        .accessibilityElement(children: .contain)
    }

    private func addBadge(_ item: FranchiseSummary, owned: Bool) -> some View {
        Button {
            guard !owned else { return }
            appModel.addToLibrary(franchiseId: item.id, title: item.title, isReleasing: item.isReleasing)
        } label: {
            Image(systemName: owned ? "checkmark" : "plus")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(owned ? ThemeColor.textSecondary : ThemeColor.onAccent)
                .frame(width: 30, height: 30)
                .background(owned ? ThemeColor.surfaceFloating : ThemeColor.accent, in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(owned)
        .accessibilityLabel(owned ? "In your library" : "Add \(item.title) to Library")
    }

    private func subtitle(_ item: FranchiseSummary) -> String {
        var bits: [String] = []
        if let y = item.year { bits.append(String(y)) }
        bits.append(item.partCount == 1 ? "1 part" : "\(item.partCount) parts")
        if item.isReleasing, let at = item.nextAiringAt, at > now {
            bits.append(TemporalCopy.airs(at: at, now: now, source: item.source))
        } else if item.isReleasing {
            bits.append("Airing")
        }
        return bits.joined(separator: " · ")
    }
}
