import SwiftUI

// Search surface (reached via the separate bottom search island). The bottom chrome provides the
// field bound to appModel.searchQuery; this view renders the body:
//  - empty query  → recent searches (or a gentle prompt when there are none),
//  - searching     → skeletons, AniList-backed results, or a no-results state.
// Adding to library (with undo) happens from each result card.
struct DiscoverView: View {
    @Environment(AppModel.self) private var appModel
    let onOpenDetail: (_ franchiseId: String, _ zoomID: String) -> Void

    private var now: Int64 { appModel.now }

    private let columns = [GridItem(.flexible(), spacing: 13), GridItem(.flexible(), spacing: 13)]
    private var queryEmpty: Bool {
        appModel.searchQuery.trimmingCharacters(in: .whitespaces).isEmpty
    }
    private var showSkeletons: Bool { appModel.searchBusy && appModel.searchResults.isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageHeader(
                    title: "Add anime",
                    subtitle: queryEmpty ? "Find anime to add to your library." : nil
                )
                .padding(.bottom, 18)

                // Re-query sweep while results are already on screen — keeps the screen feeling live.
                if appModel.searchBusy && !appModel.searchResults.isEmpty {
                    IndeterminateBar()
                        .padding(.bottom, 13)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // A refresh failed while older results are still on screen — say so instead of
                // silently presenting stale results as current.
                if appModel.searchError && !appModel.searchResults.isEmpty && !queryEmpty {
                    staleResultsBanner
                        .padding(.bottom, 13)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                ZStack(alignment: .top) {
                    if queryEmpty {
                        recentSearches.transition(.opacity)
                    } else if showSkeletons {
                        skeletonGrid.transition(.opacity)
                    } else if appModel.searchResults.isEmpty {
                        noResultsState.transition(.opacity)
                    } else {
                        resultsGrid.transition(.opacity)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 120)
            .animation(.easeInOut(duration: 0.28), value: showSkeletons)
            .animation(.easeInOut(duration: 0.22), value: appModel.searchBusy)
            .animation(.easeInOut(duration: 0.25), value: appModel.searchResults.isEmpty)
            .animation(.easeInOut(duration: 0.25), value: queryEmpty)
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: recent searches (empty-query state)

    @ViewBuilder
    private var recentSearches: some View {
        if appModel.recentSearches.isEmpty {
            VStack(spacing: 11) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 33, weight: .light))
                    .foregroundStyle(Theme.text36)
                    .padding(.bottom, 2)
                Text("Search for anime to add")
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
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Recent")
                        .scaledFont(12.5, weight: .semibold)
                        .tracking(0.9)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.text72)
                    Spacer()
                    Button { appModel.clearRecentSearches() } label: {
                        Text("Clear")
                            .scaledFont(12.5, weight: .semibold)
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 4)

                ForEach(appModel.recentSearches, id: \.self) { term in
                    recentRow(term)
                    if term != appModel.recentSearches.last {
                        Rectangle().fill(Theme.hairline).frame(height: 1)
                    }
                }
            }
        }
    }

    private func recentRow(_ term: String) -> some View {
        Button { appModel.searchQuery = term } label: {
            HStack(spacing: 12) {
                Image(systemName: "clock.arrow.circlepath")
                    .scaledFont(14)
                    .foregroundStyle(Theme.text40)
                Text(term)
                    .scaledFont(15)
                    .foregroundStyle(Theme.text90)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button { appModel.removeRecentSearch(term) } label: {
                    Image(systemName: "xmark")
                        .scaledFont(11, weight: .semibold)
                        .foregroundStyle(Theme.text36)
                        .padding(6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: search results

    private var skeletonGrid: some View {
        LazyVGrid(columns: columns, spacing: 13) {
            ForEach(0..<8, id: \.self) { _ in
                PosterCardSkeleton()
            }
        }
    }

    private var resultsGrid: some View {
        LazyVGrid(columns: columns, spacing: 13) {
            ForEach(appModel.searchResults) { summary in
                let owned = appModel.isInLibrary(summary.id)
                PosterCard(
                    vm: CardModel(summary: summary, owned: owned, now: now),
                    onOpen: {
                        appModel.recordRecentSearch()   // acting on a result = a useful search
                        onOpenDetail(summary.id, "disc/\(summary.id)")
                    },
                    onPrimary: {
                        appModel.recordRecentSearch()
                        appModel.addToLibrary(franchiseId: summary.id,
                                              title: summary.title,
                                              isReleasing: summary.isReleasing)
                    }
                )
                .zoomSource("disc/\(summary.id)")
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.94)),
                    removal: .opacity
                ))
                .contextMenu {
                    if let owned = appModel.franchise(id: summary.id) {
                        FranchiseContextMenu(f: owned, appModel: appModel)
                    } else {
                        Button {
                            appModel.addToLibrary(franchiseId: summary.id,
                                                  title: summary.title,
                                                  isReleasing: summary.isReleasing)
                        } label: {
                            Label("Add to library", systemImage: "plus")
                        }
                    }
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: appModel.searchResults.map(\.id))
    }

    // Inline notice above a grid of now-stale results after a failed re-query.
    private var staleResultsBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.exclamationmark")
                .scaledFont(12, weight: .semibold)
                .foregroundStyle(Theme.accent)
            Text("Couldn't refresh — results may be out of date.")
                .scaledFont(12.5)
                .foregroundStyle(Theme.text72)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Retry") { appModel.retrySearch() }
                .scaledFont(12.5, weight: .semibold)
                .foregroundStyle(Theme.accent)
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.accentBorder, lineWidth: 1))
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
