import SwiftUI

// "Out now" briefing row (legacy `BriefingRow`): art-forward dense row — a larger poster, the
// "Ep N just aired" subtitle, and a COMPACT trailing checkmark-circle action (matching the
// PosterCard `.mark` affordance) rather than a full-width billboard button.
struct BriefingRow: View {
    let vm: CardModel
    var justCaughtUp: Bool = false
    let onOpen: () -> Void
    let onPrimary: () -> Void

    @GestureState private var pressing = false

    private var subtitle: String {
        var parts = ["Ep \(vm.airedEpisodes) just aired"]
        if !vm.behindLabel.isEmpty { parts.append(vm.behindLabel) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        ZStack {
            HStack(spacing: 14) {
                Button(action: onOpen) {
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
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // DECISION A — a clearly-actionable, LABELED "Catch up" control. NOT a bare
                // checkmark (the ✓ is reserved for the passive "Caught up" status badge).
                CatchUpPill(action: onPrimary)
            }
            .padding(12)

            if justCaughtUp { CaughtUpOverlay(size: 50) }
        }
        .background(Theme.fillFaint, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.hairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .scaleEffect(pressing ? 0.98 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.65), value: pressing)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .updating($pressing) { _, state, _ in state = true }
        )
    }
}

// DECISION A — the "Catch up" action affordance for dense rows. A compact LABELED glass capsule
// (glyph + word) that reads unambiguously as "advance my progress to the latest aired episode",
// distinct from the bare ✓ "Caught up" status badge. Same callback as the old checkmark circle.
struct CatchUpPill: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "text.append").scaledFont(13, weight: .bold)
                Text("Catch up").scaledFont(13.5, weight: .semibold)
            }
            .foregroundStyle(Theme.background)
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
        }
        .buttonStyleProminentGlass()
        .clipShape(Capsule())
    }
}

// Spotlight hero card (legacy `HeroCard`): banner header, overlapping poster, "FRESH EPISODE"
// tag, and a glass mark-caught-up button.
struct HeroCard: View {
    let vm: CardModel
    var justCaughtUp: Bool = false
    let onOpen: () -> Void
    let onPrimary: () -> Void

    @GestureState private var pressing = false

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Banner.
                ZStack(alignment: .topLeading) {
                    RemoteImageView(url: vm.banner)
                        .frame(height: 168)
                        .clipped()
                        .opacity(0.85)
                    LinearGradient(
                        stops: [
                            .init(color: Theme.surface, location: 0.06),
                            .init(color: Theme.surface.opacity(0.2), location: 0.6),
                            .init(color: .clear, location: 1),
                        ],
                        startPoint: .bottom, endPoint: .top
                    )
                    Text("FRESH EPISODE")
                        .scaledFont(11, weight: .semibold)
                        .tracking(0.5)
                        .foregroundStyle(Theme.background)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Theme.accent.opacity(0.92), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .padding(13)
                }
                .frame(height: 168)

                // Poster + title, overlapping upward.
                HStack(spacing: 15) {
                    Thumb(cover: vm.cover, width: 84, height: 124, radius: 12)
                        .shadow(color: .black.opacity(0.55), radius: 15, y: 12)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(vm.title)
                            .scaledFont(19, weight: .semibold)
                            .tracking(-0.4)
                            .lineLimit(2)
                            .foregroundStyle(Theme.textPrimary)
                        Text("Ep \(Text("\(vm.airedEpisodes)").foregroundStyle(Theme.accent)) · \(Text(vm.airedAgo).foregroundStyle(Theme.text62))")
                            .scaledFont(13)
                    }
                    .padding(.top, 50)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .offset(y: -44)
                .padding(.bottom, -44 + 16)

                MarkCaughtUpButton(label: "Mark caught up", action: onPrimary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)

            if justCaughtUp { CaughtUpOverlay(size: 62) }
        }
        .background(Theme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.hairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .scaleEffect(pressing ? 0.98 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.65), value: pressing)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .updating($pressing) { _, state, _ in state = true }
        )
    }
}

// The functional glass "Mark caught up" button used by the hero card and the detail sheet.
// DECISION A — leads with the "advance to latest" glyph (NOT a bare ✓, which is reserved for the
// passive "Caught up" status badge), so the action never reads as a done/wipe toggle.
struct MarkCaughtUpButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: "text.append").scaledFont(16, weight: .bold)
                Text(label).scaledFont(15, weight: .semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .foregroundStyle(Theme.background)
        }
        .buttonStyleProminentGlass()
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
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
