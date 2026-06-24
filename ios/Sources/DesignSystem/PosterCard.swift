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
            // A flexible Color.clear fills the full grid-cell width and fixes the 2:3 ratio, so every
            // card is identical in size. ALL visible content (art, scrim, badges, title) lives in
            // overlays — overlays never influence layout size, so varying title length / hints can't
            // change the card's width or height (which is what made the grid look ragged).
            Color.clear
                .aspectRatio(2.0 / 3.0, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .overlay {
                    RemoteImageView(url: vm.cover)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .overlay {
                    // Bottom scrim for legibility.
                    LinearGradient(
                        stops: [
                            .init(color: Theme.background.opacity(0.94), location: 0.04),
                            .init(color: Theme.background.opacity(0.2), location: 0.44),
                            .init(color: .clear, location: 0.68),
                        ],
                        startPoint: .bottom, endPoint: .top
                    )
                }
                .overlay(alignment: .topLeading) { badges }
                .overlay(alignment: .bottomLeading) { titleBlock }
                .overlay {
                    if justCaughtUp { CaughtUpOverlay(size: 52) }
                }
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

    // Title + progress (+ subtle airing hint when there's no progress bar), pinned bottom-leading.
    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(vm.title)
                .scaledFont(14, weight: .semibold)
                .tracking(-0.2)
                .lineLimit(2)
                .foregroundStyle(Theme.textPrimary)
            if vm.showProgress {
                VStack(alignment: .leading, spacing: 5) {
                    Text(vm.progressLabel)
                        .scaledFont(11, monospacedDigit: true)
                        .foregroundStyle(Theme.text62)
                    ProgressBar(fraction: vm.progressFraction, height: 3)
                }
                .padding(.top, 8)
            } else {
                airingHint.padding(.top, 6)
            }
            newSeasonHint
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
    }

    // A "new season coming" line for franchises with an announced future installment that the
    // airing schedule can't surface (no AniList broadcast date yet). Shown regardless of progress
    // so a caught-up library show still advertises its next season.
    @ViewBuilder
    private var newSeasonHint: some View {
        if !vm.newSeason.isEmpty {
            HStack(spacing: 5) {
                Image(systemName: "sparkles")
                    .scaledFont(9, weight: .semibold)
                    .foregroundStyle(Theme.accent)
                Text(vm.newSeason)
                    .scaledFont(10.5, weight: .semibold)
                    .foregroundStyle(Theme.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .padding(.top, 6)
        }
    }

    private var badgeShape: RoundedRectangle { RoundedRectangle(cornerRadius: 8, style: .continuous) }

    @ViewBuilder
    private var badges: some View {
        VStack {
            HStack {
                if vm.isBehind {
                    // Behind: solid accent fill (highest urgency).
                    Text(vm.behindLabel)
                        .scaledFont(11, weight: .semibold)
                        .foregroundStyle(Theme.background)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Theme.accent, in: badgeShape)
                        .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
                } else if vm.caughtUp {
                    StatusBadge(systemName: "checkmark", label: "Caught up")
                } else if vm.action == .add && vm.owned {
                    StatusBadge(systemName: "checkmark", label: "In library")
                }
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
        }
        .padding(9)
    }

    // DECISION B / task 6 — next-airing hint for cards that are airing but not behind. A clock
    // glyph + "Airs in {countdown}" framing makes it unambiguous that this is the show's airing
    // schedule (not the viewer's progress), reading the same on owned and unowned cards.
    @ViewBuilder
    private var airingHint: some View {
        if vm.isAiring && !vm.isBehind && !vm.airingHint.isEmpty {
            HStack(spacing: 5) {
                Image(systemName: "clock")
                    .scaledFont(9, weight: .semibold)
                    .foregroundStyle(Theme.accent)
                Text(vm.airingHint)
                    .scaledFont(10.5, weight: .medium, monospacedDigit: true)
                    .foregroundStyle(Theme.text72)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        if vm.action == .mark && vm.isBehind {
            // DECISION A — "advance to latest aired" glyph, NOT a bare ✓ (which is reserved for the
            // passive "Caught up" status badge). On a "20 behind" show a ✓ read as a done/wipe
            // toggle; "text.append" reads as catching the count up to the newest episode.
            GlassCircleButton(systemName: "text.append", size: 40, iconSize: 17,
                              tint: Theme.accent, foreground: Theme.background) {
                onPrimary()
            }
            .padding(8)
        } else if vm.action == .add && !vm.owned {
            GlassCircleButton(systemName: "plus", size: 26, iconSize: 12,
                              foreground: Theme.textPrimary) {
                onPrimary()
            }
            .padding(8)
        }
    }
}

// A uniform status pill (Caught up / In library) for poster cards. Backed by a consistent dark
// scrim *under* the glass so it reads legibly over ANY artwork — the glass tint alone is too
// dependent on the underlying image, which is what made these look filled-vs-outline at random.
private struct StatusBadge: View {
    let systemName: String
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemName).scaledFont(9, weight: .bold)
            Text(label).scaledFont(11, weight: .semibold)
        }
        .foregroundStyle(Theme.accent)
        .padding(.leading, 7).padding(.trailing, 8).padding(.vertical, 4)
        .background(Theme.background.opacity(0.55), in: shape)
        .glassChrome(in: shape)
        .overlay(shape.stroke(Theme.accentBorder, lineWidth: 1))
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 8, style: .continuous) }
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
