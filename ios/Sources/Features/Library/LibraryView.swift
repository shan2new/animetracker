import SwiftUI

// "Library" tab — searchable, with glass filter chips and Behind / Caught up / Finished / Plan
// buckets.
struct LibraryView: View {
    @Environment(AppModel.self) private var appModel
    let onOpenDetail: (_ franchiseId: String, _ zoomID: String) -> Void

    private var now: Int64 { appModel.now }
    @Namespace private var chipNS

    var body: some View {
        @Bindable var model = appModel

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageHeader(title: "Library")
                    .padding(.horizontal, 20)

                SearchField(text: $model.libQuery, prompt: "Search your library")
                    .padding(.horizontal, 20)
                    .padding(.top, 18)

                if !appModel.libraryEmpty {
                    filterChips.padding(.top, 16)
                }
                content.padding(.top, 6)
            }
            .padding(.top, 34)
            .padding(.bottom, 120)
            // Loading → content cross-fades instead of popping.
            .animation(.easeInOut(duration: 0.25), value: appModel.loading)
            .animation(.easeInOut(duration: 0.25), value: appModel.loadError)
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .scrollDismissesKeyboard(.interactively)
        .refreshable {
            await appModel.reload()
            // Quiet completion tick; failures already buzz via showError.
            if !appModel.loadError { Haptics.impact(.light) }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassGroup(spacing: 7) {
                HStack(spacing: 7) {
                    chip(label: "All", filter: .all)
                    ForEach(LibGroup.allCases, id: \.self) { g in
                        chip(label: g.chipLabel, filter: .group(g))
                    }
                }
                // Explicit trailing pad so the last chip clears the screen edge when scrolled.
                .padding(.trailing, 4)
            }
        }
        .contentMargins(.leading, 20, for: .scrollContent)
        .contentMargins(.trailing, 20, for: .scrollContent)
        .scrollClipDisabled()
    }

    private func chip(label: String, filter: LibFilter) -> some View {
        let on = appModel.libFilter == filter
        return Button {
            Haptics.selection()
            withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) { appModel.libFilter = filter }
        } label: {
            Text(label)
                .scaledFont(12.5, weight: .medium)
                .foregroundStyle(on ? Theme.background : Theme.text70)
                .padding(.horizontal, 14).padding(.vertical, 7)
        }
        .background {
            if on {
                Capsule().fill(Theme.accent)
                    .matchedGeometryEffect(id: "chipPill", in: chipNS)
            } else {
                Capsule().fill(Theme.fillSoft)
                    .overlay(Capsule().stroke(Theme.hairlineStrong, lineWidth: 1))
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var content: some View {
        if appModel.loadError && !appModel.libraryEmpty {
            RetryBanner { Task { await appModel.reload() } }.padding(.horizontal, 20)
        }

        if appModel.loading && appModel.library.isEmpty {
            Loader()
        } else if appModel.loadError && appModel.libraryEmpty {
            EmptyStateView(
                title: "Couldn't load your library",
                message: "The server couldn't be reached. Check your connection and try again.",
                ctaLabel: "Retry",
                onCta: { Task { await appModel.reload() } }
            )
        } else if appModel.librarySections.isEmpty {
            emptyState
        } else {
            VStack(alignment: .leading, spacing: 22) {
                ForEach(appModel.librarySections) { section in
                    sectionView(section)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            // Cards settle into place when a show is removed or re-buckets after a status change.
            .animation(.spring(response: 0.4, dampingFraction: 0.82),
                       value: appModel.librarySections.map { $0.franchises.map(\.id) })
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if appModel.libraryEmpty {
            EmptyStateView(
                title: "Your library is empty",
                message: "Add anime from the Add tab and they'll show up here, grouped by what's behind, caught up, and finished."
            )
        } else if !appModel.libQuery.trimmingCharacters(in: .whitespaces).isEmpty {
            Text("No shows match \u{201C}\(appModel.libQuery.trimmingCharacters(in: .whitespaces))\u{201D}.")
                .scaledFont(14)
                .foregroundStyle(Theme.text40)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
        } else {
            Text("Nothing in this filter yet.")
                .scaledFont(14)
                .foregroundStyle(Theme.text40)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
        }
    }

    private func sectionView(_ section: AppModel.LibrarySection) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(section.label)
                    .scaledFont(12.5, weight: .semibold)
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.text70)
                Text("\(section.count)")
                    .scaledFont(12, monospacedDigit: true)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.3), value: section.count)
                    .foregroundStyle(Theme.text36)
            }
            .padding(.bottom, 13)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 13), GridItem(.flexible(), spacing: 13)], spacing: 13) {
                ForEach(section.franchises) { f in
                    let action = appModel.bucket(of: f).cardAction
                    PosterCard(vm: CardModel(franchise: f, action: action, now: now),
                               justCaughtUp: appModel.justCaught.contains(f.id),
                               onOpen: { onOpenDetail(f.id, "lib/\(f.id)") },
                               onPrimary: { appModel.markCaughtUp(f.id) })
                        .zoomSource("lib/\(f.id)")
                        .contextMenu { FranchiseContextMenu(f: f, appModel: appModel) }
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.94)),
                            removal: .opacity
                        ))
                }
            }
        }
    }
}
