import SwiftUI

// "Out now" briefing row (legacy `BriefingRow`): thumb + "Ep N just aired" + a full-width
// glass "Mark caught up" button.
struct BriefingRow: View {
    let vm: CardModel
    var justCaughtUp: Bool = false
    let onOpen: () -> Void
    let onPrimary: () -> Void

    @GestureState private var pressing = false

    var body: some View {
        ZStack {
            VStack(spacing: 12) {
                Button(action: onOpen) {
                    HStack(spacing: 14) {
                        Thumb(cover: vm.cover, width: 54, height: 80, radius: 10)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(vm.title)
                                .font(.system(size: 16, weight: .semibold))
                                .tracking(-0.3)
                                .lineLimit(1)
                                .foregroundStyle(Theme.textPrimary)
                            Text("Ep \(vm.airedEpisodes) just aired")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Theme.accent)
                                .padding(.top, 3)
                            Text(vm.airedAgo + (vm.behindLabel.isEmpty ? "" : " · \(vm.behindLabel)"))
                                .font(Theme.mono(12))
                                .foregroundStyle(Theme.text42)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)

                MarkCaughtUpButton(label: "Mark caught up", action: onPrimary)
            }
            .padding(13)

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
                        .font(.system(size: 11, weight: .semibold))
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
                            .font(.system(size: 19, weight: .semibold))
                            .tracking(-0.4)
                            .lineLimit(2)
                            .foregroundStyle(Theme.textPrimary)
                        Text("Ep \(Text("\(vm.airedEpisodes)").foregroundStyle(Theme.accent)) · \(Text(vm.airedAgo).foregroundStyle(Theme.text62))")
                            .font(.system(size: 13))
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

// The functional glass "Mark caught up" button used by briefing/hero cards and the detail sheet.
struct MarkCaughtUpButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: "checkmark").font(.system(size: 16, weight: .bold))
                Text(label).font(.system(size: 15, weight: .semibold))
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
