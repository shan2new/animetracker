import SwiftUI
import UIKit

// The full-screen story viewer (ios-spec §4.1, §5.2, §5.5), on Instagram's physics (the round-4
// spike, kept):
//
//   · It OPENS OUT OF THE RING you tapped and closes back INTO it: the cover is presented with no
//     system animation over a clear background (FeedView), and the viewer itself grows from the
//     bubble's circle to the full screen and shrinks back, so the feed stays visible behind it.
//   · A swipe DOWN carries the story with your finger — shrinking, rounding, the feed showing
//     through — and past a threshold it lands back in its bubble; short of it, it springs home.
//   · HOLD anywhere to pause: the chrome clears and the picture is all there is.
//   · Shows turn on a CUBE, the page's edge the hinge, the face turning away darkening.
//   · Swipe UP for the show's page.
//
// Under Reduce Motion every one of these is a fade or a cut. The clock never runs under VoiceOver
// or Switch Control — the page's named actions and its adjustable value are the way through.

struct StoryLaunch: Identifiable, Equatable {
    let reelIndex: Int
    let frameIndex: Int
    var id: String { "\(reelIndex):\(frameIndex)" }
}

struct StoryViewer: View {
    let reels: [StoryReel]
    let start: StoryLaunch
    let origins: StoryOrigins
    let onOpenShow: (_ franchiseId: String) -> Void
    /// The presenter drops the cover WITHOUT an animation of its own — the viewer has already
    /// flown back into the ring.
    let onClose: () -> Void
    /// A capture (`-feedStory`, FeedCapture): the opening frame is held part-way, the clock never
    /// runs. Never set in a shipped session.
    var frozen: Bool = false

    init(reels: [StoryReel], start: StoryLaunch, origins: StoryOrigins,
         onOpenShow: @escaping (_ franchiseId: String) -> Void, onClose: @escaping () -> Void,
         frozen: Bool = false) {
        self.reels = reels
        self.start = start
        self.origins = origins
        self.onOpenShow = onOpenShow
        self.onClose = onClose
        self.frozen = frozen
        // The reel and frame it opens on are there from the first body, so the first frame the
        // clock times is the one tapped.
        let first = reels.isEmpty ? 0 : min(max(0, start.reelIndex), reels.count - 1)
        let frames = reels.isEmpty ? 1 : reels[first].frames.count
        _reel = State(initialValue: first)
        _frameOf = State(initialValue: [first: min(max(0, start.frameIndex), max(0, frames - 1))])
    }

    @Environment(AppModel.self) private var appModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.displayScale) private var displayScale
    @Environment(\.scenePhase) private var scenePhase

    @State private var clock = StoryClock()
    @State private var reel = 0
    @State private var frameOf: [Int: Int] = [:]
    /// 0: a circle the size of the bubble, where the bubble is. 1: the full screen.
    @State private var presented: CGFloat = 0
    /// The open has landed (the clock may run).
    @State private var opened = false
    @State private var pull: CGSize = .zero
    @State private var lift: CGFloat = 0
    @State private var cube: CGFloat = 0
    @State private var axis: DragAxis?
    @State private var holding = false
    @State private var holdTask: Task<Void, Never>?
    @State private var closing = false
    @State private var turning = false
    /// What the pages hold the clock for (an alert, a finger on the sticker, a prompt, the menu).
    @State private var holds: Set<StoryHold> = []
    @State private var discussing: StoryDiscussionTarget?
    @State private var showAfterSheet: String?
    @State private var switchControl = UIAccessibility.isSwitchControlRunning
    @State private var screen = CGSize(width: ThemeMetrics.windowWidth, height: ThemeMetrics.windowHeight)
    @State private var roomsAsked: Set<String> = []
    @GestureState private var touching = false

    private enum DragAxis { case horizontal, down, up }

    /// One episode's discussion, opened from a watched frame's reply field.
    private struct StoryDiscussionTarget: Identifiable {
        let franchiseId: String
        let mediaId: Int
        let episode: Int
        var id: String { ThreadSubject.episode(mediaId: mediaId, episode: episode) }
    }

    var body: some View {
        GeometryReader { geo in
            let insets = geo.safeAreaInsets
            let full = CGSize(width: geo.size.width, height: geo.size.height + insets.top + insets.bottom)
            ZStack {
                StoryStyle.backdrop
                    .opacity(backdrop)
                    .ignoresSafeArea()
                if !reels.isEmpty {
                    pages(full: full, insets: insets)
                        .frame(width: full.width, height: full.height)
                        .modifier(StoryFlight(presented: presented, pull: pull, origin: origin(for: reel, in: full),
                                              full: full, reduceMotion: reduceMotion))
                        .ignoresSafeArea()
                }
            }
            .onChange(of: full, initial: true) { _, size in if size != screen { screen = size } }
        }
        // The tab bar's lane is under this cover: a lane receipt written here (a failed write, a
        // notice) is drawn over the page, just above its reply row — never while the chrome is
        // cleared by a hold, and never on the way out (a live story receipt is handed to the tab
        // bar's lane as the viewer closes).
        .overlay(alignment: .bottom) {
            if !closing && !holding {
                CoverLane()
                    .padding(.bottom, FeedMetrics.actionHitHeight + ThemeSpace.x3)
            }
        }
        .preferredColorScheme(.dark)
        .perfScreen("Story")
        .accessibilityAction(.escape) { close() }
        .sheet(item: $discussing, onDismiss: {
            if let id = showAfterSheet {
                showAfterSheet = nil
                openShow(id)
            }
        }) { d in
            EpisodeDiscussionView(franchiseId: d.franchiseId, mediaId: d.mediaId, episode: d.episode,
                                  presentation: .sheet,
                                  onOpenShow: { id in
                                      showAfterSheet = id
                                      discussing = nil
                                  })
        }
        .onAppear(perform: appear)
        .task { await ScheduleReminders.shared.refresh() }
        .onChange(of: touching) { _, down in hold(down) }
        .onChange(of: pauseReason, initial: true) { _, paused in
            if paused { clock.pause() } else { clock.resume() }
        }
        .onChange(of: currentKey, initial: true) { _, key in
            guard !key.isEmpty else { return }
            clock.start(frameKey: key, at: frozen ? StoryPhysics.frozenFraction : 0)
            frameShown()
        }
        .onChange(of: voiceOver) { _, on in if on { cancelHold() } }
        .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.switchControlStatusDidChangeNotification)) { _ in
            switchControl = UIAccessibility.isSwitchControlRunning
        }
        // Advancing is ONE sleeping task per frame, re-armed by a pause flip or a restart — no
        // loop, no per-tick state.
        .task(id: "\(currentKey)|\(clock.paused)|\(clock.generation)") {
            guard !frozen, !clock.paused, !currentKey.isEmpty else { return }
            try? await Task.sleep(for: .seconds(clock.remaining(at: .now)))
            guard !Task.isCancelled, !clock.paused else { return }
            step(1)
        }
    }

    // MARK: Pages (the cube)

    @ViewBuilder
    private func pages(full: CGSize, insets: EdgeInsets) -> some View {
        ZStack {
            ForEach(visible, id: \.self) { i in
                StoryPage(reel: reels[i], frame: frame(i), clock: i == reel ? clock : nil, insets: insets,
                          chromeHidden: holding || (i == reel && closing), active: i == reel,
                          lift: i == reel ? lift : 0, actions: pageActions)
                    .equatable()
                    .frame(width: full.width, height: full.height)
                    .modifier(CubeFace(x: CGFloat(i - reel) * full.width + cube, width: full.width,
                                       flat: reduceMotion))
                    .zIndex(i == reel ? 1 : 0)
                    .allowsHitTesting(i == reel && !turning)
                    .accessibilityHidden(i != reel)
            }
        }
        // The page's own gestures — tap back / forward, hold to pause, swipe to turn, pull to
        // close, lift for the show — on the pages' parent, so a button or the sticker inside a
        // page keeps its own touches first.
        .gesture(pager(full))
    }

    /// The pages drawn: the current one, and the neighbour the drag is turning toward.
    private var visible: [Int] {
        guard reels.indices.contains(reel) else { return [] }
        var out = [reel]
        if cube < 0, reel + 1 < reels.count { out.append(reel + 1) }
        if cube > 0, reel - 1 >= 0 { out.insert(reel - 1, at: 0) }
        return out
    }

    private func frame(_ i: Int) -> Int {
        guard reels.indices.contains(i) else { return 0 }
        return min(frameOf[i] ?? 0, max(0, reels[i].frames.count - 1))
    }

    private var currentKey: String {
        guard reels.indices.contains(reel), !reels[reel].frames.isEmpty else { return "" }
        return reels[reel].frames[frame(reel)].id
    }

    private var pageActions: StoryPageActions {
        let nextShow: (() -> Void)? = reel + 1 < reels.count ? { turn(1) } : nil
        let previousShow: (() -> Void)? = reel > 0 ? { turn(-1) } : nil
        return StoryPageActions(
            next: { step(1) },
            previous: { step(-1) },
            nextShow: nextShow,
            previousShow: previousShow,
            close: { close() },
            openShow: { if reels.indices.contains(reel) { openShow(reels[reel].franchiseId) } },
            mute: mute,
            discuss: { episode in
                guard reels.indices.contains(reel) else { return }
                let r = reels[reel]
                discussing = StoryDiscussionTarget(franchiseId: r.franchiseId, mediaId: r.mediaId, episode: episode)
            },
            hold: { reason, on in
                if on { holds.insert(reason) } else { holds.remove(reason) }
            },
            restart: {
                guard !currentKey.isEmpty else { return }
                clock.start(frameKey: currentKey, at: frozen ? StoryPhysics.frozenFraction : 0)
            })
    }

    // MARK: Gestures

    private func pager(_ full: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .updating($touching) { _, state, _ in state = true }
            .onChanged { v in
                guard !closing, !turning else { return }
                let t = v.translation
                if axis == nil, hypot(t.width, t.height) > StoryPhysics.axisSlop {
                    axis = abs(t.width) > abs(t.height) ? .horizontal : (t.height > 0 ? .down : .up)
                    cancelHold()
                }
                switch axis {
                case .horizontal?: cube = resist(t.width)
                case .down?: pull = CGSize(width: t.width, height: max(0, t.height))
                case .up?: lift = max(-StoryPhysics.liftMax, min(0, t.height))
                case nil: break
                }
            }
            .onEnded { v in
                let t = v.translation, p = v.predictedEndTranslation
                let was = axis
                axis = nil
                guard !closing, !turning else { return }
                switch was {
                case nil:
                    // A tap: back in the leading third, forward anywhere else. A hold that was
                    // released is not a tap.
                    if !holding { v.startLocation.x < full.width * StoryPhysics.backShare ? step(-1) : step(1) }
                case .horizontal?:
                    let dir = t.width < 0 ? 1 : -1
                    let far = abs(t.width) > full.width * StoryPhysics.turnShare
                        || abs(p.width) > full.width * StoryPhysics.turnPredictedShare
                    if far, reels.indices.contains(reel + dir) {
                        turn(dir)
                    } else {
                        withAnimation(ThemeMotion.pick(StoryStyle.cubeReturn, reduceMotion: reduceMotion)) { cube = 0 }
                    }
                case .down?:
                    if t.height > StoryPhysics.closePull || p.height > StoryPhysics.closePredicted {
                        close()
                    } else {
                        withAnimation(ThemeMotion.pick(StoryStyle.pullReturn, reduceMotion: reduceMotion)) { pull = .zero }
                    }
                case .up?:
                    if t.height < StoryPhysics.openLift || p.height < StoryPhysics.openLiftPredicted {
                        if reels.indices.contains(reel) { openShow(reels[reel].franchiseId) }
                    } else {
                        withAnimation(ThemeMotion.pick(StoryStyle.liftReturn, reduceMotion: reduceMotion)) { lift = 0 }
                    }
                }
            }
    }

    /// Past the first and last show the cube pushes back, as Instagram's does.
    private func resist(_ dx: CGFloat) -> CGFloat {
        let atStart = reel == 0 && dx > 0
        let atEnd = reel == reels.count - 1 && dx < 0
        return atStart || atEnd ? dx * StoryPhysics.edgeResistance : dx
    }

    /// Hold: the clock stops at once (`touching`); the chrome clears only if the finger stays, so
    /// a tap never blinks the chrome.
    private func hold(_ down: Bool) {
        guard down else { cancelHold(); return }
        holdTask?.cancel()
        guard !voiceOver else { return }
        holdTask = Task { @MainActor in
            try? await Task.sleep(for: FeedMetrics.storyHoldDelay)
            guard !Task.isCancelled, axis == nil else { return }
            withAnimation(ThemeMotion.pick(StoryStyle.holdIn, reduceMotion: reduceMotion)) { holding = true }
        }
    }

    private func cancelHold() {
        holdTask?.cancel()
        holdTask = nil
        if holding {
            withAnimation(ThemeMotion.pick(StoryStyle.holdOut, reduceMotion: reduceMotion)) { holding = false }
        }
    }

    // MARK: Time

    /// Every reason the clock holds (§5.2). The viewer pauses/resumes the clock on its change.
    private var pauseReason: Bool {
        frozen || holding || touching || axis != nil || !holds.isEmpty || discussing != nil
            || closing || turning || !opened || voiceOver || switchControl
            // The scene is not in front: a system alert (the notification prompt), Control Centre,
            // the app switcher — the frame must not advance under something covering it.
            || scenePhase != .active
            || receiptLiveHere
    }

    /// The current frame's in-place mark receipt is still up. Its Undo lives only on this frame
    /// (the lane is hidden under the cover), so the clock waits out the undo window rather than
    /// auto-advancing to a frame with a different host and taking the Undo with it.
    private var receiptLiveHere: Bool {
        guard reels.indices.contains(reel), !reels[reel].frames.isEmpty else { return false }
        let r = reels[reel]
        let f = r.frames[frame(reel)]
        guard f.kind == .episode else { return false }
        return ReceiptLine.isLive(appModel, host: ReceiptHost.story(r.mediaId, f.episode))
    }

    /// A frame came up: the next pictures decoded ahead of the reader, the rooms asked for, the
    /// reel marked seen once its last frame shows, and VoiceOver told where it is.
    private func frameShown() {
        guard reels.indices.contains(reel) else { return }
        let r = reels[reel], f = frame(reel)
        prefetch()
        for i in [f, f + 1] where r.frames.indices.contains(i) && r.frames[i].kind == .episode {
            let key = ThreadSubject.episode(mediaId: r.mediaId, episode: r.frames[i].episode)
            guard roomsAsked.insert(key).inserted else { continue }
            let episode = r.frames[i].episode
            Task { await appModel.loadEpisodeRoom(mediaId: r.mediaId, episode: episode) }
        }
        if f == r.frames.count - 1 { appModel.markViewed(r) }
        if voiceOver, opened {
            Announce.status("\(r.showTitle). \(StoryPage.spoken(reel: r, frame: r.frames[f], now: appModel.nowMinute))")
        }
    }

    /// What the next tap or turn will show, decoded before it is asked for — never on a
    /// constrained or expensive path (`StoryArt.prefetch`).
    private func prefetch() {
        let r = reels[reel], f = frame(reel)
        if f + 1 < r.frames.count { StoryArt.prefetch(r.frames[f + 1].art, screen: screen, scale: displayScale) }
        for i in [reel + 1, reel - 1] where reels.indices.contains(i) {
            let n = reels[i]
            guard !n.frames.isEmpty else { continue }
            StoryArt.prefetch(n.frames[frame(i)].art, screen: screen, scale: displayScale)
        }
    }

    private func step(_ d: Int) {
        guard !closing, !turning, reels.indices.contains(reel) else { return }
        let r = reels[reel]
        let next = frame(reel) + d
        if next >= r.frames.count {
            appModel.markViewed(r)
            if reel + 1 < reels.count { turn(1) } else { close() }
            return
        }
        if next < 0 {
            if reel > 0 {
                turn(-1)
            } else if !currentKey.isEmpty {
                clock.start(frameKey: currentKey)
            }
            return
        }
        withAnimation(ThemeMotion.pick(StoryStyle.frameFade, reduceMotion: reduceMotion)) { frameOf[reel] = next }
    }

    /// The cube: the current face turns away on its hinge while the next turns in; then the next
    /// becomes the current, with no motion of its own. Under Reduce Motion a flat slide.
    private func turn(_ dir: Int) {
        guard reels.indices.contains(reel + dir), !turning, !closing else { return }
        turning = true
        cancelHold()
        let width = screen.width
        let settle = reduceMotion ? ThemeMotion.uiReduced : StoryStyle.cubeTurn
        withAnimation(settle) {
            cube = -CGFloat(dir) * width
        } completion: {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                reel += dir
                if frameOf[reel] == nil { frameOf[reel] = 0 }
                cube = 0
                turning = false
            }
        }
    }

    // MARK: Open and close

    private func appear() {
        guard !reels.isEmpty else { onClose(); return }
        guard presented == 0, !closing else { return }
        if frozen {
            presented = 1
            opened = true
            return
        }
        let fromRing = origin(for: reel, in: screen) != nil
        let animation: Animation = reduceMotion ? ThemeMotion.uiReduced : (fromRing ? StoryStyle.open : StoryStyle.openFade)
        // One frame at the bubble, then out of it.
        Task { @MainActor in
            withAnimation(animation) {
                presented = 1
            } completion: {
                opened = true
                if voiceOver { Announce.screenChanged() }
            }
        }
    }

    /// Back into the ring of the show on screen (not the one tapped): the flight ends where the
    /// eye is, and the cover goes without an animation of its own. `then` runs after the cover
    /// is gone (the show page's push waits for it).
    private func close(then after: (() -> Void)? = nil) {
        guard !closing else { return }
        closing = true
        cancelHold()
        let toRing = origin(for: reel, in: screen) != nil
        let animation: Animation = reduceMotion ? ThemeMotion.uiReduced : (toRing ? StoryStyle.closeToRing : StoryStyle.closeFade)
        withAnimation(animation) {
            presented = 0
            pull = .zero
            lift = 0
        } completion: {
            handReceiptToLane()
            onClose()
            if let after { Task { @MainActor in after() } }
        }
    }

    private func openShow(_ franchiseId: String) {
        close { onOpenShow(franchiseId) }
    }

    /// The ··· menu's Mute: the show's NEWS goes quiet and the viewer closes, saying so. Its reel
    /// stays in the tray — a reel is the user's own episode, not news (`StoryReel.build`).
    private func mute() {
        guard reels.indices.contains(reel) else { return }
        let r = reels[reel]
        appModel.muteShow(franchiseId: r.franchiseId, showName: r.showTitle, fromPostId: nil)
        close { appModel.showNotice(Copy.Feed.foldMuted(r.showTitle)) }
    }

    /// Leaving with a story's in-place receipt still live: its Undo moves to the lane for a fresh
    /// window (the lane was hidden under the cover) — §4.1 step 5.
    private func handReceiptToLane() {
        guard let u = appModel.undo, case .inPlace(let host) = u.placement, host.hasPrefix("story/") else { return }
        var lane = u
        lane.placement = .lane
        appModel.presentUndo(lane)
    }

    private var backdrop: Double {
        let fade = min(StoryPhysics.pullBackdropMaxFade, max(0, pull.height) / StoryPhysics.pullBackdropFade)
        return Double(presented) * Double(1 - fade)
    }

    /// The bubble the viewer flies from and back into — only while it is on screen (a ring
    /// scrolled off the tray's edge closes with a fade), and never under Reduce Motion.
    private func origin(for i: Int, in full: CGSize) -> CGRect? {
        guard !reduceMotion, reels.indices.contains(i), let r = origins.frames[reels[i].id] else { return nil }
        let bounds = CGRect(origin: .zero, size: full)
        return bounds.contains(CGPoint(x: r.midX, y: r.midY)) ? r : nil
    }
}

// MARK: - The flight

/// The whole viewer between the bubble and the screen: `presented` 0 is a circle the bubble's
/// size at the bubble, 1 the full screen; `pull` is the finger's drag-down on top of it —
/// Instagram's shrink, rounded corners and all. Without an origin (a ring off screen, Reduce
/// Motion) it is a fade.
///
/// One modifier chain whatever the inputs — a branch here would change the pages' identity and
/// rebuild them mid-session. The rounding is a CLIP of a rounded rectangle on a frame the flight
/// narrows, never a `.mask`: at rest the frame is the screen and the corner 0, a plain rectangle
/// clip with no offscreen pass (§5.2).
struct StoryFlight: ViewModifier {
    let presented: CGFloat
    let pull: CGSize
    let origin: CGRect?
    let full: CGSize
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        let p = presented
        let dy = max(0, pull.height)
        let pullScale = 1 - min(StoryPhysics.pullMaxShrink, dy / StoryPhysics.pullShrinkDistance)
        let pullCorner = min(StoryPhysics.pullMaxCorner, dy / StoryPhysics.pullCornerRate) / max(0.3, pullScale)
        let w = max(1, full.width)
        let hasOrigin = origin != nil
        let o = origin ?? CGRect(x: 0, y: 0, width: w, height: w)
        let side = max(1, o.width)
        let scale = hasOrigin ? (side / w) + (1 - side / w) * p : 1
        let clipH = hasOrigin ? w + (full.height - w) * p : full.height
        let corner = (hasOrigin ? (w / 2) * (1 - p) : 0) + pullCorner
        let cx = hasOrigin ? o.midX + (w / 2 - o.midX) * p : w / 2
        let cy = hasOrigin ? o.midY + (full.height / 2 - o.midY) * p : full.height / 2
        content
            .frame(width: full.width, height: max(1, clipH))
            .clipShape(RoundedRectangle(cornerRadius: max(0, corner), style: .continuous))
            .frame(width: full.width, height: full.height)
            .scaleEffect(scale * pullScale)
            .offset(x: cx - w / 2 + pull.width * StoryPhysics.pullFollowX,
                    y: cy - full.height / 2 + dy * StoryPhysics.pullFollowY)
            .opacity(hasOrigin ? 1 : Double(p))
    }
}

/// One face of the cube: hinged on the edge it shares with its neighbour, turning away as it
/// leaves, shaded as it turns. `flat` (Reduce Motion) is a plain slide.
struct CubeFace: ViewModifier {
    let x: CGFloat
    let width: CGFloat
    var flat = false

    func body(content: Content) -> some View {
        let t = max(-1, min(1, x / max(1, width)))
        content
            .overlay {
                StoryStyle.cubeShade
                    .opacity(flat ? 0 : Double(abs(t)) * StoryStyle.cubeShadeMax)
                    .allowsHitTesting(false)
            }
            .rotation3DEffect(.degrees(flat ? 0 : Double(t) * 90), axis: (x: 0, y: 1, z: 0),
                              anchor: t < 0 ? .trailing : .leading, perspective: StoryPhysics.cubePerspective)
            .offset(x: x)
    }
}
