import SwiftUI

/// Deep-link target inside the detail: a season part and one episode (Schedule rows pass it).
struct EpisodeFocus: Equatable {
    let mediaId: Int
    let episode: Int
}

extension EpisodeFocus: Hashable {}

struct FlowChips: View {
    let items: [String]
    var body: some View {
        FlexibleWrap(spacing: 7, lineSpacing: 7) {
            ForEach(items, id: \.self) { g in
                Text(g)
                    .scaledFont(12)
                    .foregroundStyle(Theme.text62)
                    .padding(.horizontal, 11).padding(.vertical, 5)
                    .background(Theme.fillSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Theme.hairline, lineWidth: 1))
            }
        }
    }
}

struct LivePulseDot: View {
    @State private var on = false
    var body: some View {
        Circle()
            .fill(Theme.accent)
            .frame(width: 6, height: 6)
            .shadow(color: Theme.accent.opacity(0.9), radius: 4)
            .scaleEffect(on ? 0.82 : 1)
            .opacity(on ? 0.45 : 1)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}
