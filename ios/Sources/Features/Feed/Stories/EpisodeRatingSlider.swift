import SwiftUI

// Instagram's emoji slider, as an episode's rating (ios-spec §1.2, §4.2): the flame grows as you
// drag it toward "the best", the five gels fill the track behind it; let go and it settles, the
// room's REAL average drops onto the track and the numbers roll in.
//
// It writes the real rating: `appModel.rateEpisode` on release (0…100; optimistic, newest word
// wins, one lane per episode) — the model signs the write with one `.selection`, so the sticker
// fires no haptic of its own and nothing per drag step (a haptic is a signature for a write). The
// average and the count come from the room (`GET /social/episodes/:m/:n`), never invented: before
// anyone has rated, there is no average to draw. Drawn only when the client says the episode is
// open (§4.2 step 5) — the host decides that.

struct EpisodeRatingSlider: View {
    let mediaId: Int
    let episode: Int
    /// A finger is on the track — the story viewer holds its clock while it is.
    var onInteracting: ((Bool) -> Void)? = nil

    @Environment(AppModel.self) private var appModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drag: Double?

    /// Your score as a fraction of the track, with the pending word over the room's.
    private var yours: Double? {
        appModel.yourRating(mediaId: mediaId, episode: episode).map { Double(min(100, max(0, $0))) / 100 }
    }

    private var rating: EpisodeRating {
        appModel.episodeRoom(mediaId: mediaId, episode: episode)?.rating ?? .empty
    }

    var body: some View {
        let mine = drag ?? yours ?? 0.5
        let settled = yours != nil && drag == nil
        let room = rating
        let average = room.average.map { min(1, max(0, $0 / 100)) }
        VStack(spacing: ThemeSpace.x3 + ThemeSpace.x0_5) {
            Text(Copy.Stories.howWasEpisode(episode))
                .type(ThemeType.stickerQuestion)
                .foregroundStyle(ThemeColor.stickerInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            GeometryReader { g in
                let w = max(1, g.size.width)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(ThemeColor.stickerInk.opacity(0.1))
                        .frame(height: Self.track)
                    // The gels fill the track up to the flame — the whole ramp is there to be
                    // earned. The gradient spans the full track and is CLIPPED to the fill, never
                    // masked.
                    Rectangle()
                        .fill(ThemeGel.track)
                        .frame(width: w, height: Self.track)
                        .frame(width: max(Self.track, w * mine), alignment: .leading)
                        .clipShape(Capsule())
                    if settled, let average {
                        // The room's average: a small disc dropped onto the track.
                        Circle()
                            .fill(ThemeColor.stickerCard)
                            .overlay(Circle().strokeBorder(ThemeColor.stickerInk.opacity(0.25), lineWidth: 1))
                            .frame(width: Self.averageDisc, height: Self.averageDisc)
                            .offset(x: w * average - Self.averageDisc / 2)
                            .transition(reduceMotion ? .opacity : .scale(scale: 0.1).combined(with: .opacity))
                    }
                    Text(Copy.Stories.ratingGlyph)
                        .font(.largeTitle)
                        // A picture, not words: it keeps its size at every text size (the track is
                        // a fixed 44-pt target).
                        .dynamicTypeSize(.large)
                        .scaleEffect(drag != nil && !reduceMotion ? 0.9 + 0.65 * mine : 1, anchor: .bottom)
                        .offset(x: w * mine - Self.glyphHalf)
                        .animation(reduceMotion ? nil : .interactiveSpring(response: 0.18, dampingFraction: 0.8), value: drag)
                        .accessibilityHidden(true)
                }
                .frame(height: FeedMetrics.actionHitHeight)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onChanged { v in
                            if drag == nil { onInteracting?(true) }
                            drag = min(1, max(0, v.location.x / w))
                        }
                        .onEnded { _ in
                            if let d = drag {
                                withAnimation(ThemeMotion.pick(ThemeMotion.uiSnappy, reduceMotion: reduceMotion)) {
                                    appModel.rateEpisode(mediaId: mediaId, episode: episode,
                                                         score: Int((d * 100).rounded()))
                                    drag = nil
                                }
                            }
                            onInteracting?(false)
                        })
            }
            .frame(height: FeedMetrics.actionHitHeight)
            if settled, let score = appModel.yourRating(mediaId: mediaId, episode: episode) {
                Text(Copy.Stories.ratingLine(average: room.average.map(Self.tenths), count: room.count,
                                             yours: Self.tenths(Double(score))))
                    .type(ThemeType.metadataEmphasis)
                    .foregroundStyle(ThemeColor.stickerInk.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .contentTransition(.numericText())
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 4)))
            }
        }
        .padding(.horizontal, ThemeSpace.x5)
        .padding(.vertical, ThemeSpace.x4 + ThemeSpace.x0_5)
        // The card's white ground and its shadow, drawn by the ground SHAPE (never `.shadow` on
        // the composited card — an offscreen pass every frame the story is up).
        .cardShadow(.floating, shape: RoundedRectangle(cornerRadius: ThemeRadius.card, style: .continuous),
                    fill: ThemeColor.stickerCard)
        .animation(ThemeMotion.pick(ThemeMotion.uiSnappy, reduceMotion: reduceMotion), value: settled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Copy.Stories.howWasEpisode(episode))
        .accessibilityValue(appModel.yourRating(mediaId: mediaId, episode: episode)
            .map { Copy.Stories.ratingValue(Self.tenths(Double($0))) } ?? Copy.Stories.notRated)
        .accessibilityAdjustableAction { direction in
            // One tenth a step, from the middle when unrated — each step is a real rating write.
            let current = appModel.yourRating(mediaId: mediaId, episode: episode) ?? 50
            let next = direction == .increment ? current + 10 : current - 10
            appModel.rateEpisode(mediaId: mediaId, episode: episode, score: min(100, max(0, next)))
        }
        .onDisappear { if drag != nil { drag = nil; onInteracting?(false) } }
    }

    /// 0–100 → out of 10, one decimal when it has one: 76 → "7.6", 80 → "8".
    private static func tenths(_ score: Double) -> String {
        (score / 10).formatted(.number.precision(.fractionLength(0...1)))
    }

    private static let track: CGFloat = 10
    private static let averageDisc: CGFloat = 16
    private static let glyphHalf: CGFloat = 22
}
