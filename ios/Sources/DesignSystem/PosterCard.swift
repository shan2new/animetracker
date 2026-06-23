import SwiftUI

// The 2:3 poster card (legacy `ShowCard`). Poster art is the star — NO glass on the card itself;
// glass is reserved for the floating action button overlaid on it.
struct PosterCard: View {
    let vm: CardModel
    var justCaughtUp: Bool = false
    let onOpen: () -> Void
    let onPrimary: () -> Void

    var body: some View {
        Button(action: onOpen) {
            ZStack(alignment: .bottomLeading) {
                Color.clear
                RemoteImageView(url: vm.cover)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()

                // Bottom scrim for legibility.
                LinearGradient(
                    stops: [
                        .init(color: Theme.background.opacity(0.94), location: 0.04),
                        .init(color: Theme.background.opacity(0.2), location: 0.44),
                        .init(color: .clear, location: 0.68),
                    ],
                    startPoint: .bottom, endPoint: .top
                )

                // Top-left badges.
                badges

                // Title + progress.
                VStack(alignment: .leading, spacing: 0) {
                    Text(vm.title)
                        .font(.system(size: 14, weight: .semibold))
                        .tracking(-0.2)
                        .lineLimit(2)
                        .foregroundStyle(Theme.textPrimary)
                    if vm.showProgress {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(vm.progressLabel)
                                .font(Theme.mono(11))
                                .foregroundStyle(Theme.text62)
                            ProgressBar(fraction: vm.progressFraction, height: 3)
                        }
                        .padding(.top, 8)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 11)

                if justCaughtUp {
                    CaughtUpOverlay(size: 52)
                }
            }
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(Theme.hairline, lineWidth: 1)
            )
            .background(Theme.surface)
            .overlay(alignment: .topTrailing) { actionButton }
        }
        .buttonStyle(SpringPressButtonStyle(scale: 0.96))
    }

    @ViewBuilder
    private var badges: some View {
        VStack {
            HStack {
                if vm.isBehind {
                    Text(vm.behindLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.background)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
                } else if vm.caughtUp {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
                        Text("Caught up").font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(Theme.accent)
                    .padding(.leading, 7).padding(.trailing, 8).padding(.vertical, 4)
                    .glassChrome(in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else if vm.action == .add && vm.owned {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
                        Text("In library").font(.system(size: 10.5, weight: .semibold))
                    }
                    .foregroundStyle(Theme.accent)
                    .padding(.leading, 7).padding(.trailing, 9).padding(.vertical, 5)
                    .glassChrome(in: Capsule())
                }
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
        }
        .padding(9)
    }

    @ViewBuilder
    private var actionButton: some View {
        if vm.action == .mark && vm.isBehind {
            GlassCircleButton(systemName: "checkmark", size: 40, iconSize: 18,
                              tint: Theme.accent, foreground: Theme.background) {
                onPrimary()
            }
            .padding(8)
        } else if vm.action == .add && !vm.owned {
            GlassCircleButton(systemName: "plus", size: 40, iconSize: 18,
                              foreground: Theme.textPrimary) {
                onPrimary()
            }
            .padding(8)
        }
    }
}

// A thin progress bar (track + accent fill) that animates its fill on appear and on change.
struct ProgressBar: View {
    let fraction: Double
    var height: CGFloat = 3

    @State private var displayed: Double = 0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.16))
                Capsule().fill(Theme.accent)
                    .frame(width: max(0, min(1, displayed)) * geo.size.width)
            }
        }
        .frame(height: height)
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.8).delay(0.12)) {
                displayed = fraction
            }
        }
        .onChange(of: fraction) { _, newValue in
            withAnimation(.spring(response: 0.42, dampingFraction: 0.75)) {
                displayed = newValue
            }
        }
    }
}
