import SwiftUI

// "Out now" briefing row (legacy `BriefingRow`): art-forward dense row — a larger poster, the
// "Ep N just aired" subtitle, and a COMPACT trailing labeled "Catch up" action (matching the
// PosterCard `.mark` affordance) rather than a full-width billboard button.
//
// The whole card is one Button (SpringPressButtonStyle) so press feedback only fires on a real
// press — an earlier DragGesture(minimumDistance: 0) version squished rows while scrolling.
// CatchUpPill nests inside the label; the innermost button wins its own taps.
struct BriefingRow: View {
    let vm: CardModel
    var justCaughtUp: Bool = false
    let onOpen: () -> Void
    let onPrimary: () -> Void

    private var subtitle: String {
        var parts = ["Ep \(vm.airedEpisodes) just aired"]
        if !vm.behindLabel.isEmpty { parts.append(vm.behindLabel) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        Button(action: onOpen) {
            ZStack {
                HStack(spacing: 14) {
                    Thumb(cover: vm.cover, width: 64, height: 96, radius: 11)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(vm.title)
                            .scaledFont(16, weight: .semibold)
                            .tracking(-0.3)
                            .lineLimit(2)
                            .foregroundStyle(Theme.textPrimary)
                        Text(subtitle)
                            .scaledFont(12.5, weight: .medium, monospacedDigit: true)
                            .foregroundStyle(Theme.accent)
                        // DECISION C — exactly what to play next (next UNWATCHED episode).
                        if let nextWatch = vm.nextWatchLabel {
                            Text(nextWatch)
                                .scaledFont(12, weight: .medium, monospacedDigit: true)
                                .foregroundStyle(Theme.text62)
                        } else if !vm.airedAgo.isEmpty {
                            Text(vm.airedAgo)
                                .scaledFont(12, monospacedDigit: true)
                                .foregroundStyle(Theme.text42)
                        }
                    }
                    Spacer(minLength: 8)

                    // DECISION A — a clearly-actionable, LABELED "Catch up" control. NOT a bare
                    // checkmark (the ✓ is reserved for the passive "Caught up" status badge).
                    CatchUpPill(action: onPrimary)
                }
                .padding(12)

                if justCaughtUp { CaughtUpOverlay(size: 50) }
            }
            .animation(.easeOut(duration: 0.22), value: justCaughtUp)
            .background(Theme.fillFaint, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.hairline, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(SpringPressButtonStyle(scale: 0.98))
    }
}

// DECISION A — the "Catch up" action affordance for dense rows. A compact LABELED accent capsule
// (glyph + word) that reads unambiguously as "advance my progress to the latest aired episode",
// distinct from the bare ✓ "Caught up" status badge. Styled to match the countdown pill in
// "Airing soon" — flat accent fill, own metrics. (The `.glassProminent` button style stacked its
// oversized system metrics on top of ours, ballooning the pill and wrapping its label.)
// `.fixedSize()` keeps it one-line at its natural width; the row title truncates instead.
struct CatchUpPill: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "text.append").scaledFont(12, weight: .bold)
                Text("Catch up").scaledFont(13, weight: .semibold)
            }
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(Theme.background)
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(Theme.accent, in: Capsule())
            // Invisible vertical inset so the tap target clears ~44pt without growing the pill.
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(BounceButtonStyle())
    }
}

extension View {
    // Prominent (tinted accent) glass button used for primary CTAs in the functional layer.
    @ViewBuilder
    func buttonStyleProminentGlass() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glassProminent).tint(Theme.accent)
        } else {
            self.buttonStyle(PrimaryButtonStyle())
        }
    }
}

extension Theme {
    static let text42 = Color(hex: 0xF5F5F7).opacity(0.42)
}
