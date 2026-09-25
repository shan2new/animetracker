import SwiftUI
import WebKit

// X's inline video, for the feed's trailers (the X pass, 25 Sep) — and, since the same day, the
// trailer WATCHED where it is (owner: "It should not open full screen by a mere click, player
// should be inline"). X's timeline MOVES: the trailer a reader stops on starts playing in its post,
// silent, with the time left in one corner and the sound in the other; it stops the moment it
// leaves the screen, only one ever plays, and a finished one offers "Watch again". A TAP no longer
// leaves the feed: it turns the sound on and puts the player's controls on the picture
// (`TrailerInlineControls` — play/pause, the scrubber, the sound, full screen); full screen is only
// ever asked for (`TrailerFullScreen`), and it is the same player, handed over, never a reload.
//
// What starts a preview is the system's word, not ours: never with Auto-Play Video Previews off
// (Accessibility → Motion), on a Low Data or Low Power path, while anything covers the list, or in
// the background. A tap is the reader's word and plays regardless. The picture is YouTube's player
// driven from a page of our own (`TrailerPlayback`), with the post's still ON TOP until it moves, so
// the provider's loading chrome is never seen. The web view takes no touches: the post's gestures
// (a tap, a double tap to like) and every control are SwiftUI's.

// MARK: - Which trailer plays

/// Decides the one trailer that plays in a list — the feed, a post page, a show page's trailers —
/// from where each trailer's frame is on screen (reported by the trailers themselves, never
/// observed), and owns its player. Only `current` and `fullScreen` are observed.
@MainActor
@Observable
final class FeedAutoplay {
    /// The trailer playing in place — at most one.
    private(set) var current: TrailerPlayback?
    /// Its slot: a post's id (the feed, a post page), a video's id (a show page).
    var playingId: String? { current?.key }
    /// X's sound choice holds for the session: turn one trailer's sound on and the next starts
    /// with it on.
    var muted = true {
        didSet { if let current, !current.engaged { current.setMuted(muted) } }
    }
    /// The trailer on the full screen — the host's cover item.
    var fullScreen: TrailerPlayback?
    /// That full screen was opened by turning the phone (turning it upright again closes it).
    private(set) var fullScreenByRotation = false

    /// Starts trailers by itself (the feed, a post page); a show page's trailers wait for a tap.
    let autoplays: Bool

    @ObservationIgnored private var frames: [String: CGRect] = [:]
    @ObservationIgnored private var videos: [String: FranchiseVideo] = [:]
    @ObservationIgnored private var scrolling = false
    @ObservationIgnored private var suspendRequested = false
    @ObservationIgnored private var pending: Task<Void, Never>?
    /// Where each trailer had got to (a return to the post picks up from there).
    @ObservationIgnored private var positions: [String: Double] = [:]
    /// Trailers the provider will not play embedded (101/150) — not tried again this session.
    @ObservationIgnored private var refused: Set<String> = []

    /// A trailer starts once this share of it is on screen, and stops below `stopShare`.
    private static let startShare: CGFloat = 0.6
    private static let stopShare: CGFloat = 0.25
    /// The choice is made once the scroll has come to rest, a beat after (X starts the video the
    /// reader stops on, not every one they pass).
    private static let settleDelay: Duration = .milliseconds(220)

    init(autoplays: Bool = true) {
        self.autoplays = autoplays
    }

    /// The full screen holds the player: the list's comings and goings — a cover's disappearance,
    /// a suspension, a frame — are not acted on until it has handed the player back.
    private var frozen: Bool { fullScreen != nil || current?.presenting == true }

    /// The system's switches for pictures that start themselves.
    private var allowed: Bool {
        UIAccessibility.isVideoAutoplayEnabled
            && !SyncCenter.shared.isConstrained
            && !ProcessInfo.processInfo.isLowPowerModeEnabled
            && !suspendRequested
    }

    // MARK: Reports from the list

    func report(_ key: String, video: FranchiseVideo, frame: CGRect) {
        frames[key] = frame
        videos[key] = video
        guard !frozen else { return }
        if key == current?.key {
            if share(frame) < Self.stopShare { stop() }
        } else if current == nil, !scrolling {
            schedule()
        }
    }

    func gone(_ key: String) {
        frames[key] = nil
        guard !frozen else { return }
        if key == current?.key { stop() }
    }

    /// The list's scroll phase: the choice waits for rest.
    func scrollMoving(_ moving: Bool) {
        guard moving != scrolling else { return }
        scrolling = moving
        if !moving { schedule() }
    }

    /// Covered, backgrounded or left: nothing plays until the list is back in front.
    func suspend(_ on: Bool) {
        suspendRequested = on
        guard !frozen else { return }
        if on { stop() } else { schedule() }
    }

    func refuse(_ key: String) {
        refused.insert(key)
        if current?.key == key, !frozen { stop() }
    }

    // MARK: The reader's word

    /// A tap on a trailer: the first plays it here with its sound and its controls; the next ones
    /// bring the controls or send them away.
    func tap(_ key: String, video: FranchiseVideo) {
        if let current, current.key == key, current.engaged {
            current.toggleChrome()
        } else {
            engage(key, video: video)
        }
    }

    func engage(_ key: String, video: FranchiseVideo) {
        pending?.cancel()
        videos[key] = video
        if let current, current.key == key {
            current.engaged = true
            current.setMuted(false)
            if current.phase == .paused || current.phase == .ended { current.play() }
            current.showChrome()
        } else {
            stop()
            start(key, video: video, engaged: true)
        }
        if muted { muted = false }
    }

    /// Full screen, asked for (the switch on the controls, or the phone turned on its side).
    func openFullScreen(_ playback: TrailerPlayback, byRotation: Bool = false) {
        guard fullScreen == nil, !playback.presenting else { return }
        pending?.cancel()
        playback.engaged = true
        playback.presenting = true
        fullScreenByRotation = byRotation
        fullScreen = playback
    }

    /// The full screen has gone (`TrailerFullScreen.onDisappear`): the player comes home to its
    /// post, still playing — or goes, if the list let it go meanwhile.
    func fullScreenClosed(_ playback: TrailerPlayback) {
        playback.presenting = false
        if fullScreen === playback { fullScreen = nil }
        fullScreenByRotation = false
        if current !== playback {
            positions[playback.key] = playback.current
            playback.destroy()
        }
        // The list re-reads itself once it is back in front.
        schedule()
    }

    /// The phone turned: a trailer being WATCHED goes full screen on its side, YouTube's way.
    func deviceTurned() {
        guard !frozen, !suspendRequested, let current, current.engaged,
              current.phase == .playing || current.phase == .buffering,
              UIDevice.current.orientation.isLandscape else { return }
        openFullScreen(current, byRotation: true)
    }

    // MARK: Choosing

    private func start(_ key: String, video: FranchiseVideo, engaged: Bool) {
        current = TrailerPlayback(key: key, video: video, start: positions[key] ?? 0,
                                  muted: engaged ? false : muted, engaged: engaged)
    }

    private func stop() {
        pending?.cancel()
        guard let current, !frozen else { return }
        positions[current.key] = current.phase == .ended ? 0 : current.current
        current.destroy()
        self.current = nil
    }

    private func schedule() {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: Self.settleDelay)
            guard !Task.isCancelled else { return }
            self?.choose()
        }
    }

    /// Keeps a trailer that is still on screen; else the most visible trailer past `startShare`
    /// (the higher one on a tie), where the list starts its own — or none.
    private func choose() {
        guard !frozen else { return }
        if suspendRequested { return stop() }
        if let current, let f = frames[current.key], share(f) >= Self.stopShare { return }
        guard autoplays, allowed else { return stop() }
        var best: (id: String, share: CGFloat, y: CGFloat)?
        for (id, frame) in frames where !refused.contains(id) {
            let s = share(frame)
            guard s >= Self.startShare else { continue }
            if let b = best, s < b.share || (s == b.share && frame.minY >= b.y) { continue }
            best = (id, s, frame.minY)
        }
        guard best?.id != current?.key else { return }
        stop()
        if let id = best?.id, let video = videos[id] { start(id, video: video, engaged: false) }
    }

    /// The part of the screen a reader is looking at: under the bar's top row, over the tab bar.
    private var viewport: CGRect {
        let top = ThemeMetrics.topSafeInset + FeedMetrics.headerRow
        let bottom = ThemeMetrics.windowHeight - ThemeMetrics.tabBarVisualHeight
        return CGRect(x: 0, y: top, width: ThemeMetrics.windowWidth, height: max(0, bottom - top))
    }

    private func share(_ frame: CGRect) -> CGFloat {
        guard frame.width > 0, frame.height > 0 else { return 0 }
        let visible = frame.intersection(viewport)
        guard !visible.isNull else { return 0 }
        return (visible.width * visible.height) / (frame.width * frame.height)
    }
}

extension EnvironmentValues {
    /// The list's trailer director, where a list installs one (the feed, the post page).
    @Entry var feedAutoplay: FeedAutoplay? = nil
}

// MARK: - The trailer in its post

/// The PICTURE of a trailer in its post, under the post's own taps: its play glyph at rest; while it
/// previews, the picture itself with the time left (X's corner). Its buttons — the sound, "Watch
/// again", and the player's controls once it is being watched — are `InlineTrailerControlsLayer`,
/// laid ABOVE the post's taps (`PostMediaButton`): nested inside them, the post's double-tap to
/// like took every button's tap (filmed 25 Sep: the full-screen switch only hid the controls).
struct InlineTrailerSlot: View {
    let postId: String
    let video: FranchiseVideo
    let autoplay: FeedAutoplay

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL

    /// X's time capsule: 22 pt, 8 pt in.
    private static let chipHeight: CGFloat = 22

    var body: some View {
        let playback = autoplay.current?.key == postId ? autoplay.current : nil
        ZStack {
            if let playback {
                live(playback)
            } else {
                PlayGlyph()
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(ThemeMotion.pick(ThemeMotion.uiGentle, reduceMotion: reduceMotion), value: playback?.moving)
        .animation(ThemeMotion.pick(ThemeMotion.uiGentle, reduceMotion: reduceMotion), value: playback?.phase)
        // Where the trailer is on screen — recorded, never observed.
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { frame in
            autoplay.report(postId, video: video, frame: frame)
        }
        .onDisappear { autoplay.gone(postId) }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            if autoplay.current?.key == postId { autoplay.deviceTurned() }
        }
        .onChange(of: playback?.phase == .failed) { _, failed in
            guard failed, let playback else { return }
            // A trailer the provider will not play here: a watched one opens where it can be.
            if playback.engaged, let url = video.watchURL { openURL(url) }
            autoplay.refuse(postId)
        }
    }

    @ViewBuilder
    private func live(_ playback: TrailerPlayback) -> some View {
        let holds = !playback.presenting
        let picture = holds && playback.moving
        ZStack {
            TrailerSurface(playback: playback, role: .inline, presenting: playback.presenting)
                .opacity(picture ? 1 : 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            if !playback.engaged, !picture, playback.phase != .ended {
                PlayGlyph()
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if !playback.engaged, picture, playback.duration > 0 {
                timeChip(max(0, playback.duration - playback.current))
                    .transition(.opacity)
            }
        }
    }

    private func timeChip(_ seconds: Double) -> some View {
        Text(Copy.Feed.timeLeft(seconds))
            .type(ThemeType.feedCount)
            .foregroundStyle(FeedStage.ink)
            .padding(.horizontal, ThemeSpace.x2)
            .frame(height: Self.chipHeight)
            .background(FeedStage.glyphGround, in: RoundedRectangle(cornerRadius: ThemeSpace.x1, style: .continuous))
            .padding(ThemeSpace.x2)
            .accessibilityHidden(true)
    }
}

/// The trailer's BUTTONS over its post — above the post's own taps, so a button's tap is the
/// button's: X's sound disc while it previews, "Watch again" once a preview ends, and the player's
/// controls while it is watched. Everything else on it lets a touch through to the picture (a tap
/// there brings the controls or sends them away; two like the post).
struct InlineTrailerControlsLayer: View {
    let postId: String
    let autoplay: FeedAutoplay

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// X's corner control: a 30-pt disc, 8 pt in.
    private static let disc: CGFloat = 30

    var body: some View {
        let playback = autoplay.current?.key == postId ? autoplay.current : nil
        ZStack {
            if let playback, !playback.presenting {
                if playback.engaged {
                    if playback.chromeVisible {
                        TrailerInlineControls(playback: playback) { autoplay.openFullScreen(playback) }
                            .transition(.opacity)
                    }
                } else if playback.phase == .ended {
                    watchAgain(playback)
                        .transition(.opacity)
                } else if playback.moving {
                    soundButton
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .transition(.opacity)
                }
            }
        }
        .animation(ThemeMotion.pick(ThemeMotion.uiGentle, reduceMotion: reduceMotion), value: playback?.moving)
        .animation(ThemeMotion.pick(ThemeMotion.uiGentle, reduceMotion: reduceMotion), value: playback?.phase)
    }

    private var soundButton: some View {
        Button { autoplay.muted.toggle() } label: {
            AppGlyph(systemName: autoplay.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(ThemeType.feedSmall.font.weight(.semibold))
                .foregroundStyle(FeedStage.ink)
                // A Tabler picture, not an SF Symbol: the two speakers crossfade.
                .contentTransition(.opacity)
                .frame(width: Self.disc, height: Self.disc)
                .background(FeedStage.glyphGround, in: Circle())
                .overlay(Circle().strokeBorder(FeedStage.glyphEdge, lineWidth: FeedMetrics.hairline))
                .frame(width: FeedMetrics.actionHitHeight, height: FeedMetrics.actionHitHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(FeedIconPressStyle())
        .padding(ThemeSpace.x1)
        .accessibilityLabel(autoplay.muted ? Copy.Feed.soundOn : Copy.Feed.soundOff)
    }

    /// X's pill over a finished video: white, with the replay glyph.
    private func watchAgain(_ playback: TrailerPlayback) -> some View {
        Button { playback.replay() } label: {
            AppGlyphLabel(Copy.Feed.watchAgain, systemName: "arrow.counterclockwise")
                .type(ThemeType.feedNoteTitle)
                .foregroundStyle(ThemeColor.stickerInk)
                .padding(.horizontal, ThemeSpace.x4)
                .frame(minHeight: FeedMetrics.replyFieldHeight)
                .background(FeedStage.ink, in: Capsule())
                .frame(minHeight: FeedMetrics.actionHitHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(FeedIconPressStyle())
    }
}
