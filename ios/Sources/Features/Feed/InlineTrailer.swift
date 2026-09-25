import SwiftUI
import WebKit

// X's inline video, for the feed's trailers (the X pass, 25 Sep). X's timeline MOVES: the video a
// reader stops on starts playing in its post, silent, with the time left in one corner and the
// sound in the other; it stops the moment it leaves the screen, only one ever plays, and a finished
// one offers "Watch again". Tapping it still opens the stage (`VideoSheet`), which picks up where
// the post was. The feed's trailers were stills with a play glyph — the one place the feed read as
// a page of pictures rather than X.
//
// What starts it is the system's word, not ours: never with Auto-Play Video Previews off
// (Accessibility → Motion), on a Low Data or Low Power path, while anything covers the feed, or in
// the background. The picture is YouTube's embed in a page of our own (the stage's rule — a
// neutral origin, `VideoEmbed`), driven through YouTube's IFrame API, with the post's still ON TOP
// until the provider says it is playing, so its loading chrome is never seen. The web view takes no
// touches: the post's own gestures (open, double-tap to like) and the two buttons stay SwiftUI's.

// MARK: - Which trailer plays

/// Decides the one trailer that plays, from where each trailer's frame is on screen. The frames
/// are reported by the trailers themselves and never observed; only `playingId` and `muted` are.
@MainActor
@Observable
final class FeedAutoplay {
    /// The post whose trailer plays in place.
    private(set) var playingId: String?
    /// X's sound choice holds for the session: turn one trailer's sound on and the next starts
    /// with it on.
    var muted = true

    @ObservationIgnored private var frames: [String: CGRect] = [:]
    @ObservationIgnored private var scrolling = false
    @ObservationIgnored private var suspended = false
    @ObservationIgnored private var pending: Task<Void, Never>?
    /// Where each trailer had got to (the stage and a return to the post pick up from there).
    @ObservationIgnored private var positions: [String: Double] = [:]
    /// Trailers the provider will not play embedded (101/150) — not tried again this session.
    @ObservationIgnored private var refused: Set<String> = []

    /// A trailer starts once this share of it is on screen, and stops below `stopShare`.
    private static let startShare: CGFloat = 0.6
    private static let stopShare: CGFloat = 0.25
    /// The choice is made once the scroll has come to rest, a beat after (X starts the video the
    /// reader stops on, not every one they pass).
    private static let settleDelay: Duration = .milliseconds(220)

    /// The system's switches for pictures that start themselves.
    private var allowed: Bool {
        UIAccessibility.isVideoAutoplayEnabled
            && !SyncCenter.shared.isConstrained
            && !ProcessInfo.processInfo.isLowPowerModeEnabled
            && !suspended
    }

    func report(_ postId: String, frame: CGRect) {
        frames[postId] = frame
        if postId == playingId {
            if share(frame) < Self.stopShare { stop() }
        } else if playingId == nil, !scrolling {
            schedule()
        }
    }

    func gone(_ postId: String) {
        frames[postId] = nil
        if postId == playingId { stop() }
    }

    /// The feed's scroll phase: the choice waits for rest.
    func scrollMoving(_ moving: Bool) {
        guard moving != scrolling else { return }
        scrolling = moving
        if !moving { schedule() }
    }

    /// Covered, backgrounded or left: nothing plays until the feed is back in front.
    func suspend(_ on: Bool) {
        guard on != suspended else { return }
        suspended = on
        if on { stop() } else { schedule() }
    }

    func position(_ postId: String) -> Double { positions[postId] ?? 0 }
    func record(_ postId: String, at seconds: Double) { positions[postId] = seconds }

    func refuse(_ postId: String) {
        refused.insert(postId)
        if playingId == postId { stop() }
    }

    private func stop() {
        pending?.cancel()
        if playingId != nil { playingId = nil }
    }

    private func schedule() {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: Self.settleDelay)
            guard !Task.isCancelled else { return }
            self?.choose()
        }
    }

    /// The most visible trailer past `startShare` (the higher one on a tie) — or none.
    private func choose() {
        guard allowed else { return stop() }
        var best: (id: String, share: CGFloat, y: CGFloat)?
        for (id, frame) in frames where !refused.contains(id) {
            let s = share(frame)
            guard s >= Self.startShare else { continue }
            if let b = best, s < b.share || (s == b.share && frame.minY >= b.y) { continue }
            best = (id, s, frame.minY)
        }
        if let current = playingId, let f = frames[current], share(f) >= Self.stopShare { return }
        if playingId != best?.id { playingId = best?.id }
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
    /// The feed's autoplay, where a list installs one (the feed, the post page).
    @Entry var feedAutoplay: FeedAutoplay? = nil
}

// MARK: - The trailer in its post

/// Over a trailer's still: its play glyph at rest; while it plays, the picture itself with the time
/// left and the sound button (X's corners); once finished, "Watch again".
struct InlineTrailerSlot: View {
    let postId: String
    let video: FranchiseVideo
    let autoplay: FeedAutoplay

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The provider is playing: the picture is up over the still.
    @State private var shown = false
    @State private var ended = false
    @State private var left: Double?
    @State private var replays = 0

    /// X's corner controls: a 30-pt disc (the sound) and a 22-pt capsule (the time), 8 pt in.
    private static let disc: CGFloat = 30
    private static let chipHeight: CGFloat = 22
    /// Seconds of play before the picture replaces the still.
    private static let revealAfter: Double = 0.4

    var body: some View {
        let active = autoplay.playingId == postId && video.youtubeID != nil
        ZStack {
            if active, let id = video.youtubeID {
                InlineYouTubePlayer(videoId: id, muted: autoplay.muted, start: autoplay.position(postId),
                                    replays: replays, onEvent: handle)
                    .opacity(shown && !ended ? 1 : 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            if active, ended {
                watchAgain
                    .transition(.opacity)
            } else if !(active && shown) {
                PlayGlyph()
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottomLeading) {
            if active, shown, !ended, let left {
                timeChip(left)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if active, shown, !ended {
                soundButton
                    .transition(.opacity)
            }
        }
        .animation(ThemeMotion.pick(ThemeMotion.uiGentle, reduceMotion: reduceMotion), value: shown)
        .animation(ThemeMotion.pick(ThemeMotion.uiGentle, reduceMotion: reduceMotion), value: ended)
        // Where the trailer is on screen — recorded, never observed.
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { frame in
            autoplay.report(postId, frame: frame)
        }
        .onDisappear { autoplay.gone(postId) }
        .onChange(of: active) { _, now in
            if !now {
                shown = false
                ended = false
                left = nil
            }
        }
    }

    private func handle(_ event: InlineYouTubePlayer.Event) {
        switch event {
        case .playing:
            ended = false
        case .time(let current, let duration):
            // The picture goes up once the video is MOVING, not on the provider's first "playing"
            // (a buffering frame, a black frame).
            if !shown, !ended, current >= Self.revealAfter { shown = true }
            if duration > 0 { left = max(0, duration - current) }
            autoplay.record(postId, at: current)
        case .ended:
            ended = true
            autoplay.record(postId, at: 0)
        case .failed:
            autoplay.refuse(postId)
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

    private var soundButton: some View {
        Button { autoplay.muted.toggle() } label: {
            Image(systemName: autoplay.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(ThemeType.feedSmall.font.weight(.semibold))
                .foregroundStyle(FeedStage.ink)
                .contentTransition(.symbolEffect(.replace))
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
    private var watchAgain: some View {
        Button { replays += 1 } label: {
            Label(Copy.Feed.watchAgain, systemImage: "arrow.counterclockwise")
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

// MARK: - The provider's player

/// YouTube's embed, inline and silent, driven through the IFrame API from a page of our own (a
/// neutral origin — the stage's `VideoEmbed` explains why a bare embed URL is refused). It reports
/// playing, ended, the time and a refusal; it takes no touches.
struct InlineYouTubePlayer: UIViewRepresentable {
    enum Event {
        case playing, ended, failed
        case time(current: Double, duration: Double)
    }

    let videoId: String
    let muted: Bool
    let start: Double
    /// Bumped by "Watch again".
    let replays: Int
    let onEvent: (Event) -> Void

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler {
        var onEvent: (Event) -> Void = { _ in }
        var muted = true
        var replays = 0

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let kind = body["t"] as? String else { return }
            switch kind {
            case "state":
                // YouTube's states: 1 playing, 0 ended (2 paused, 3 buffering, 5 cued, -1 unstarted).
                switch body["s"] as? Int {
                case 1: onEvent(.playing)
                case 0: onEvent(.ended)
                default: break
                }
            case "time":
                let current = (body["c"] as? NSNumber)?.doubleValue ?? 0
                let duration = (body["d"] as? NSNumber)?.doubleValue ?? 0
                onEvent(.time(current: current, duration: duration))
            case "error":
                onEvent(.failed)
            default:
                break
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsPictureInPictureMediaPlayback = false
        config.allowsAirPlayForMediaPlayback = false
        config.userContentController.add(context.coordinator, name: Self.channel)
        let view = WKWebView(frame: .zero, configuration: config)
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.isScrollEnabled = false
        view.scrollView.backgroundColor = .clear
        // The post's gestures and buttons are SwiftUI's; the page never sees a touch.
        view.isUserInteractionEnabled = false
        let coordinator = context.coordinator
        coordinator.onEvent = onEvent
        coordinator.muted = muted
        coordinator.replays = replays
        view.loadHTMLString(Self.page(videoId: videoId, start: start, muted: muted), baseURL: Self.origin)
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onEvent = onEvent
        if coordinator.muted != muted {
            coordinator.muted = muted
            view.evaluateJavaScript("setMuted(\(muted ? "true" : "false"))")
        }
        if coordinator.replays != replays {
            coordinator.replays = replays
            view.evaluateJavaScript("replay()")
        }
    }

    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        view.configuration.userContentController.removeScriptMessageHandler(forName: channel)
        view.stopLoading()
        view.loadHTMLString("", baseURL: nil)
    }

    private static let channel = "yt"
    /// The page's own origin — the referrer the provider sees, and the API's `origin`.
    private static let origin = URL(string: "https://previously.local/inline")

    /// The player in a black page; muted autoplay, no controls, no related wall, no captions or
    /// cards; the page reports back every half second while it plays. The player is three frames
    /// TALL, centred on the frame: its video (letterboxed to the middle of a 16:27 player) fills
    /// the frame edge to edge, while the chrome YouTube draws along the player's top and bottom
    /// edges for the first seconds of play — the title bar, the channel, the share arrow, the
    /// logo, the "more videos" card (filmed 25 Sep) — falls outside it.
    private static func page(videoId: String, start: Double, muted: Bool) -> String {
        let id = videoId.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        let from = max(0, Int(start))
        return """
        <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
        <style>html,body{margin:0;padding:0;background:#000;height:100%;overflow:hidden}#p{position:absolute;left:0;top:-100%;width:100%;height:300%;border:0}</style></head>
        <body><div id="p"></div>
        <script>
        var player;
        function post(m){try{window.webkit.messageHandlers.\(channel).postMessage(m)}catch(e){}}
        function onYouTubeIframeAPIReady(){
          player=new YT.Player('p',{width:'100%',height:'100%',videoId:'\(id)',
            playerVars:{autoplay:1,mute:1,playsinline:1,controls:0,rel:0,iv_load_policy:3,disablekb:1,fs:0,modestbranding:1,cc_load_policy:0,start:\(from),origin:'https://previously.local'},
            events:{
              onReady:function(e){\(muted ? "e.target.mute();" : "e.target.unMute();e.target.setVolume(100);")e.target.playVideo();},
              onStateChange:function(e){post({t:'state',s:e.data});},
              onError:function(e){post({t:'error',c:e.data});}
            }});
          setInterval(function(){if(player&&player.getCurrentTime&&player.getPlayerState&&player.getPlayerState()===1){post({t:'time',c:player.getCurrentTime(),d:player.getDuration()});}},500);
        }
        function setMuted(m){if(!player)return;if(m){player.mute();}else{player.unMute();player.setVolume(100);}}
        function replay(){if(!player)return;player.seekTo(0,true);player.playVideo();}
        </script>
        <script src="https://www.youtube.com/iframe_api"></script>
        </body></html>
        """
    }
}
