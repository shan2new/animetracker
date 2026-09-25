import SwiftUI

// The player's controls — ONE family inline and full screen, YouTube's anatomy in the app's type:
// the play/pause disc in the middle; along the foot the time, the sound and the full-screen switch
// over a scrubber. A tap brings them; while the trailer plays they leave on their own
// (`TrailerPlayback.chromeVisible`); paused, ended or mid-scrub, they stay. White over the picture
// (the progress is where-you-are over a moving image, not a fact: no amber on it).

enum TrailerStyle {
    static let ink = Color.white
    static let track = Color.white.opacity(0.3)
    /// A glyph's disc over a picture — the feed's own over-art disc.
    static let disc = FeedStage.glyphGround
    static let discEdge = FeedStage.glyphEdge
    /// The light veil under inline controls, so white reads on any frame.
    static let veil = Color.black.opacity(0.3)
}

// MARK: - The scrubber

/// Where the trailer is, and the way to move it: drag anywhere along it. VoiceOver adjusts it ten
/// seconds at a time.
struct TrailerScrubber: View {
    let playback: TrailerPlayback
    /// The track's weight at rest; it thickens under the finger.
    var track: CGFloat = 3
    var knob: CGFloat = 12
    /// The height that takes the finger.
    var hitHeight: CGFloat = 28

    var body: some View {
        GeometryReader { geo in
            let width = max(1, geo.size.width)
            let total = max(playback.duration, 0.01)
            let t = playback.scrubbing ?? playback.current
            let fraction = playback.duration > 0 ? min(1, max(0, t / total)) : 0
            let active = playback.scrubbing != nil
            let weight = active ? track + 2 : track
            let knobSize = active ? knob + 6 : knob
            ZStack(alignment: .leading) {
                Capsule().fill(TrailerStyle.track).frame(height: weight)
                Capsule().fill(TrailerStyle.ink).frame(width: max(weight, width * fraction), height: weight)
                Circle()
                    .fill(TrailerStyle.ink)
                    .frame(width: knobSize, height: knobSize)
                    .offset(x: width * fraction - knobSize / 2)
            }
            .frame(width: width, height: geo.size.height)
            .contentShape(Rectangle())
            // HIGH priority: a drag that starts on the scrubber is a scrub, never the feed's scroll
            // or the pager's swipe underneath it.
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if playback.scrubbing == nil { playback.beginScrub() }
                        playback.scrub(to: Double(min(max(0, value.location.x), width) / width) * playback.duration)
                    }
                    .onEnded { _ in playback.endScrub() }
            )
            .animation(ThemeMotion.pick(ThemeMotion.uiMicro, reduceMotion: false), value: active)
        }
        .frame(height: hitHeight)
        .accessibilityElement()
        .accessibilityLabel(Copy.Video.position)
        .accessibilityValue(Copy.Video.positionValue(playback.current, of: playback.duration))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: playback.skip(10)
            case .decrement: playback.skip(-10)
            @unknown default: break
            }
        }
    }
}

// MARK: - Buttons

/// Play, pause, or play again — a glass disc; a spinner while the picture is loading or catching up.
struct TrailerPlayPauseButton: View {
    let playback: TrailerPlayback
    var size: CGFloat = 56

    private var playing: Bool { playback.phase == .playing || playback.phase == .buffering }
    private var waiting: Bool { playback.phase == .loading || playback.phase == .buffering }

    var body: some View {
        Button { playback.togglePlay() } label: {
            ZStack {
                Circle().fill(TrailerStyle.disc)
                Circle().strokeBorder(TrailerStyle.discEdge, lineWidth: FeedMetrics.hairline)
                if waiting {
                    ProgressView().controlSize(size > 60 ? .large : .regular).tint(TrailerStyle.ink)
                } else {
                    AppGlyph(systemName: glyph)
                        .font(.system(size: size * 0.36, weight: .bold))
                        .foregroundStyle(TrailerStyle.ink)
                        // The play triangle's optical centre sits right of its box.
                        .offset(x: glyph == "play.fill" ? size * 0.03 : 0)
                        // A Tabler picture, not an SF Symbol: play and pause crossfade.
                        .contentTransition(.opacity)
                }
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
        }
        .buttonStyle(FeedIconPressStyle())
        .accessibilityLabel(playback.phase == .ended ? Copy.Feed.watchAgain : (playing ? Copy.Video.pause : Copy.Video.play))
    }

    private var glyph: String {
        if playback.phase == .ended { return "arrow.counterclockwise" }
        return playing ? "pause.fill" : "play.fill"
    }
}

/// A bare glyph on the controls' foot: the sound, the full-screen switch, the skips.
struct TrailerGlyphButton: View {
    let systemName: String
    let label: String
    var size: CGFloat = 17
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            AppGlyph(systemName: systemName)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(TrailerStyle.ink)
                .contentTransition(.opacity)
                .frame(width: FeedMetrics.actionHitHeight, height: FeedMetrics.actionHitHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(FeedIconPressStyle())
        .accessibilityLabel(label)
    }
}

extension TrailerPlayback {
    var soundGlyph: String { muted ? "speaker.slash.fill" : "speaker.wave.2.fill" }
    var soundLabel: String { muted ? Copy.Feed.soundOn : Copy.Feed.soundOff }
}

// MARK: - Inline

/// The controls ON the post's (or the card's) picture while it is being watched: the disc in the
/// middle; the time, the sound and the full-screen switch over the scrubber along the foot.
/// `compact` is a show page's 200-pt card: no time, a smaller disc.
struct TrailerInlineControls: View {
    let playback: TrailerPlayback
    let onFullScreen: () -> Void
    var compact = false

    var body: some View {
        ZStack {
            TrailerStyle.veil.allowsHitTesting(false)
            TrailerPlayPauseButton(playback: playback, size: compact ? 44 : 56)
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                HStack(spacing: 0) {
                    if !compact {
                        Text(Copy.Video.clockPair(playback.scrubbing ?? playback.current, playback.duration))
                            .type(ThemeType.feedCount)
                            .foregroundStyle(TrailerStyle.ink)
                            .padding(.leading, ThemeSpace.x3)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                    Spacer(minLength: 0)
                    TrailerGlyphButton(systemName: playback.soundGlyph, label: playback.soundLabel, size: compact ? 14 : 16) {
                        playback.setMuted(!playback.muted)
                        playback.showChrome()
                    }
                    TrailerGlyphButton(systemName: "arrow.up.left.and.arrow.down.right", label: Copy.Video.fullScreen,
                                       size: compact ? 14 : 16, action: onFullScreen)
                }
                .frame(height: compact ? 36 : FeedMetrics.actionHitHeight)
                TrailerScrubber(playback: playback, track: compact ? 2 : 3, knob: compact ? 10 : 12, hitHeight: compact ? 20 : 24)
                    .padding(.horizontal, ThemeSpace.x3)
                    .padding(.bottom, compact ? ThemeSpace.x1 : ThemeSpace.x2)
            }
        }
    }
}
