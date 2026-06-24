import SwiftUI

// "Add" tab — Discover. Trending by default, AniList-backed search, add-to-library with undo.
struct DiscoverView: View {
    @Environment(AppModel.self) private var appModel
    let onOpenDetail: (String) -> Void

    private var now: Int64 { appModel.now }

    private let columns = [GridItem(.flexible(), spacing: 13), GridItem(.flexible(), spacing: 13)]
    private var showSkeletons: Bool { appModel.searchBusy && appModel.searchResults.isEmpty }

    var body: some View {
        @Bindable var model = appModel

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageHeader(title: "Add anime")
                    .padding(.bottom, 18)

                SearchField(text: $model.searchQuery, prompt: "Search anime")
                    .padding(.bottom, 18)

                hintLabel
                    .padding(.bottom, appModel.searchBusy ? 9 : 13)

                // Indeterminate sweep while a search is in flight — keeps the screen feeling active
                // even when results are already on screen and we're re-querying.
                if appModel.searchBusy {
                    IndeterminateBar()
                        .padding(.bottom, 13)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                ZStack(alignment: .top) {
                    if showSkeletons {
                        skeletonGrid
                            .transition(.opacity)
                    } else if appModel.searchResults.isEmpty {
                        emptyState
                            .transition(.opacity)
                    } else {
                        resultsGrid
                            .transition(.opacity)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 34)
            .padding(.bottom, 120)
            .animation(.easeInOut(duration: 0.28), value: showSkeletons)
            .animation(.easeInOut(duration: 0.22), value: appModel.searchBusy)
            .animation(.easeInOut(duration: 0.25), value: appModel.searchResults.isEmpty)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .refreshable { await appModel.loadTrending() }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
    }

    // Eyebrow label above the grid. While searching, the text itself shimmers so the state reads
    // as live; a content-transition cross-fades the copy as it changes.
    private var hintLabel: some View {
        Text(hint)
            .scaledFont(12.5, weight: .semibold)
            .tracking(0.9)
            .textCase(.uppercase)
            .foregroundStyle(appModel.searchError ? Theme.accent : Theme.text72)
            .shimmering(appModel.searchBusy)
            .contentTransition(.opacity)
            .animation(.easeInOut(duration: 0.2), value: hint)
    }

    // Shimmering placeholder grid shown on first load / a fresh query, matching the results layout.
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
                    onOpen: { onOpenDetail(summary.id) },
                    onPrimary: {
                        appModel.addToLibrary(franchiseId: summary.id,
                                              title: summary.title,
                                              isReleasing: summary.isReleasing)
                    }
                )
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

    // Centered fallback when there's nothing to show — a failed fetch or a query with no matches —
    // so the blank cases read as intentional rather than broken.
    private var emptyState: some View {
        let trimmed = appModel.searchQuery.trimmingCharacters(in: .whitespaces)
        return VStack(spacing: 11) {
            Image(systemName: appModel.searchError ? "wifi.exclamationmark" : "magnifyingglass")
                .font(.system(size: 33, weight: .light))
                .foregroundStyle(Theme.text36)
                .padding(.bottom, 2)
            Text(appModel.searchError ? "Couldn't reach the server"
                                      : (trimmed.isEmpty ? "Nothing here yet" : "No results"))
                .scaledFont(15, weight: .semibold)
                .foregroundStyle(Theme.text72)
            Text(appModel.searchError ? "Pull down to try again."
                 : (trimmed.isEmpty ? "Pull down to refresh." : "Nothing matches “\(trimmed).” Try another title."))
                .scaledFont(13)
                .foregroundStyle(Theme.text40)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 72)
        .padding(.horizontal, 24)
    }

    private var hint: String {
        if appModel.searchBusy { return "Searching…" }
        if appModel.searchError { return "Couldn't reach the server — check your connection." }
        if !appModel.searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
            let n = appModel.searchResults.count
            return "\(n) result\(n == 1 ? "" : "s")"
        }
        return "Trending now"
    }
}
