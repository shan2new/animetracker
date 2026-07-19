import SwiftUI

/// All / Anime / TV filter chips — the media-source sibling of LibraryView's bucket chips
/// (same glass-capsule + sliding-pill pattern, its own matched-geometry namespace). Bound to
/// `AppModel.mediaFilter`, which Today, Schedule, Library, and search all respect.
struct MediaFilterChips: View {
    @Environment(AppModel.self) private var appModel
    @Namespace private var pillNS

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassGroup(spacing: 7) {
                HStack(spacing: 7) {
                    ForEach(MediaFilter.allCases, id: \.self) { f in
                        chip(f)
                    }
                }
                .padding(.trailing, 4)
            }
        }
        .contentMargins(.leading, 20, for: .scrollContent)
        .contentMargins(.trailing, 20, for: .scrollContent)
        .scrollClipDisabled()
    }

    private func chip(_ filter: MediaFilter) -> some View {
        let on = appModel.mediaFilter == filter
        return Button {
            Haptics.selection()
            withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) { appModel.mediaFilter = filter }
        } label: {
            Text(filter.chipLabel)
                .scaledFont(12.5, weight: .medium)
                .foregroundStyle(on ? Theme.background : Theme.text70)
                .padding(.horizontal, 14).padding(.vertical, 7)
        }
        .background {
            if on {
                Capsule().fill(Theme.accent)
                    .matchedGeometryEffect(id: "mediaChipPill", in: pillNS)
            } else {
                Capsule().fill(Theme.fillSoft)
                    .overlay(Capsule().stroke(Theme.hairlineStrong, lineWidth: 1))
            }
        }
        .buttonStyle(.plain)
    }
}
