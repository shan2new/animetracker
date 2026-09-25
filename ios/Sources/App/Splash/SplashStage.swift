import SwiftUI
import UIKit
import QuartzCore

// The launch. A short brand film, committed to the render server on the app's first frame —
// then the app.
//
// The films (`SplashFilm`) need nothing from the network, the library or the image pipeline: a
// splash plays in exactly the seconds none of those have answered yet, so it is made of the brand
// alone (a first cut that ended on Today's billboard art was "heavily centred on hero, which we
// will not have most of the time", user, 24 Sep). They are pure layer trees with keyframe tracks
// in FILM time. This view owns the clock: the tree is built frozen at 0, and the first
// display-link tick after it is committed — the first frame actually presented — starts it. From
// then on the render server plays it, so the main thread building the whole app underneath costs
// the film nothing. The view only decides WHEN to leave: never before the film has finished,
// never before auth has answered (so the screen underneath is the right one), and — briefly — not
// before Today's billboard has its picture (`artReady`), so the app arrives as a picture rather
// than as a tint. A wall ceiling bounds all of it.

/// What a film is given to build with.
struct SplashScene {
    let size: CGSize
    let scale: CGFloat
    let safeTop: CGFloat
    let reduceMotion: Bool
    /// Auth's answer when the film was built (false while it is still unknown): the lockup lands
    /// where the sign-in gate draws it unless the launch is known to be a signed-in one.
    var signedIn = false
}

/// A launch film.
@MainActor
protocol SplashFilm {
    /// Builds every layer under `root` and every move, in film time. Returns the film time at
    /// which the last frame is complete and still: the earliest the app may come through.
    func build(on root: CALayer, scene: SplashScene) -> Double
    /// The way out, begun at film time `t` once the app underneath is ready. Returns its length.
    /// By default the film's frame dissolves off the app.
    func exit(on root: CALayer, scene: SplashScene, at t: Double) -> Double
    // Requirements, not only extension methods: called through `SplashFilm`, an extension-only
    // method dispatches statically to its default, and a film's own clock never started.
    func roll(at media: CFTimeInterval)
    func still(at t: Double)
    func end()
    /// DEBUG: the film's own frame at `t`, for a film Core Animation does not draw.
    func frame(at t: Double) -> CGImage?
    /// How far a film that keeps its own clock has got on screen (`nil`: the root layer's time is
    /// the film's). The film lands when the landing has been SEEN, not when the wall clock says so.
    var elapsed: Double? { get }
    /// `action`, once the film's first frame is on the screen (at once for a film Core Animation
    /// draws: it is in the same commit as everything else).
    func whenFirstFrameShown(_ action: @escaping @MainActor () -> Void)
}

extension SplashFilm {
    func exit(on root: CALayer, scene: SplashScene, at t: Double) -> Double {
        let d = 0.34
        root.play(SplashTrack("opacity", 1.0, at: t).to(0.0, at: t + d, SplashCurve.fade))
        return d
    }
    /// The film's clock has started: film time 0 is presented at media time `media`. A film drawn
    /// by Core Animation needs nothing — its root layer carries the clock — but one that draws its
    /// own frames (`SplashGlassFilm`) keeps time from here.
    func roll(at media: CFTimeInterval) {}
    /// Hold the film at `t` and have that frame on screen now (DEBUG photography).
    func still(at t: Double) {}
    /// The splash is gone.
    func end() {}
    func frame(at t: Double) -> CGImage? { nil }
    var elapsed: Double? { nil }
    func whenFirstFrameShown(_ action: @escaping @MainActor () -> Void) { action() }
}

/// The film. `-splashDirection <name>` (DEBUG) picks a variant while one is being explored.
enum SplashDirection: String, CaseIterable {
    /// The departures board turns to "P.", then the name surfaces (`SplashFlapFilm`): the
    /// Split-Flap identity's own gesture (26 Sep).
    case flap
    /// Five layers of coloured glass come into register as the mark (`SplashAlignScript`).
    case align
    /// One ribbon of silk light that becomes the mark (`SplashRibbonScript`).
    case ribbon
    /// Ribbons of light gathered into the flat wordmark (`SplashSilkScript`).
    case silk
    /// The icon's glass ribbon, lit on a dark stage (`SplashPrismScript`).
    case prism
    /// Warm light gathers into the full stop (`SplashAfterglowScript`).
    case afterglow
    /// The film opens inside the full stop and pulls back to the name (`SplashMacroScript`).
    case macro
    /// The bead as real optics, drawn on the GPU (`SplashGlassFilm`).
    case glass
    /// The same gesture in Core Animation layers (`SplashLens`) — the fallback without Metal.
    case lens

    static var current: SplashDirection {
        #if DEBUG
        if let raw = UserDefaults.standard.string(forKey: "splashDirection"),
           let d = SplashDirection(rawValue: raw) { return d }
        #endif
        return .flap
    }

    @MainActor
    func film() -> SplashFilm {
        switch self {
        case .flap: return SplashFlapFilm()
        case .align: return SplashGlassFilm { SplashAlignScript(scene: $0) }
        case .ribbon: return SplashGlassFilm { SplashRibbonScript(scene: $0) }
        case .silk: return SplashGlassFilm { SplashSilkScript(scene: $0) }
        case .prism: return SplashGlassFilm { SplashPrismScript(scene: $0) }
        case .afterglow: return SplashGlassFilm { SplashAfterglowScript(scene: $0) }
        case .macro: return SplashGlassFilm { SplashMacroScript(scene: $0) }
        case .glass: return SplashGlassFilm()
        case .lens: return SplashLens()
        }
    }
}

// MARK: - The SwiftUI side

struct SplashView: View {
    @Environment(LaunchHandoff.self) private var handoff
    /// Auth's answer so far: a signed-out launch never waits on Today's picture.
    let signedIn: Bool
    /// The splash has started to leave: the app should begin emerging.
    let onLeaving: () -> Void
    /// The splash is gone.
    let onFinished: () -> Void

    var body: some View {
        SplashStageRepresentable(authReady: handoff.authReady, artReady: handoff.artReady, signedIn: signedIn,
                                 intent: handoff.intent,
                                 onLeaving: {
                                     handoff.phase = .leaving
                                     onLeaving()
                                 },
                                 onFinished: onFinished)
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}

private struct SplashStageRepresentable: UIViewRepresentable {
    let authReady: Bool
    let artReady: Bool
    let signedIn: Bool
    let intent: Bool
    let onLeaving: () -> Void
    let onFinished: () -> Void

    func makeUIView(context: Context) -> SplashStageView { SplashStageView() }

    func updateUIView(_ view: SplashStageView, context: Context) {
        view.onLeaving = onLeaving
        view.onFinished = onFinished
        view.update(authReady: authReady, artReady: artReady, signedIn: signedIn, intent: intent)
    }
}

// MARK: - The stage

@MainActor
final class SplashStageView: UIView {
    var onLeaving: (() -> Void)?
    var onFinished: (() -> Void)?

    // The hand-off.
    /// Held after the landing before the app may come through: long enough for the landed frame
    /// to register as a frame, short enough that the chrome arriving is the next thing.
    static let landedHold = 0.08
    /// How long past the film's end the splash waits for Today's picture before it leaves anyway.
    static let artPatience = 0.35
    /// Nothing holds the launch longer than this, from the first frame.
    static let ceiling = 3.2
    /// The system's own launch transition covers the app's first frames; the film waits a beat.
    static let preroll = 0.06

    private enum State { case idle, loading, armed, playing, frozen, filming, leaving, done }
    private var state: State = .idle
    private let root = CALayer()
    private var landAt: Double = 0
    private var film: SplashFilm?
    private var scene: SplashScene?
    private var leaveAt: Double?
    private var exitFor: Double = 0.34
    private var link: CADisplayLink?
    private var authReady = false
    private var artReady = false
    private var signedIn = true
    /// The launch was for somewhere (a tapped alert, a link): the film gives way at once.
    private var intent = false

    #if DEBUG
    /// `-splashFreeze <seconds>`: hold the film at one moment, for a photograph.
    private static let freezeAt: Double? = {
        let v = UserDefaults.standard.double(forKey: "splashFreeze")
        return v > 0 ? v : nil
    }()
    /// `-splashFilm 1`: once the app underneath is ready, render the whole film frame by frame
    /// (30 fps) to Documents/splash-film/<direction>/ — the splash cannot be screen-recorded at
    /// launch, but a frozen film can be stepped and photographed exactly.
    private static let filming = UserDefaults.standard.bool(forKey: "splashFilm")
    private var recorder = SplashFilmRecorder()
    #endif

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = SplashInk.canvas
        layer.addSublayer(root)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        root.frame = bounds
        CATransaction.commit()
        startIfNeeded()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        startIfNeeded()
        if window == nil { link?.invalidate(); link = nil }
    }

    func update(authReady: Bool, artReady: Bool, signedIn: Bool, intent: Bool) {
        if authReady != self.authReady { SplashTrace.mark("authReady signedIn=\(signedIn)") }
        if artReady != self.artReady { SplashTrace.mark("artReady") }
        if intent != self.intent { SplashTrace.mark("intent") }
        self.authReady = authReady
        self.artReady = artReady
        self.signedIn = signedIn
        self.intent = intent
    }

    /// A tap gives the film way once the app beneath is the right one: a film is for the first
    /// look, never a wall between someone and what they opened the app for.
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        if state == .playing, authReady { leave(at: now, film: film?.elapsed ?? now, reason: "tap") }
    }

    // MARK: Start

    private func startIfNeeded() {
        guard state == .idle, window != nil, bounds.width > 0 else { return }
        state = .loading
        SplashTrace.mark("stage-in-window")
        build()
    }

    private func build() {
        guard state == .loading, let window else { return }
        var reduceMotion = UIAccessibility.isReduceMotionEnabled
        #if DEBUG
        // `-splashReduceMotion 1`: the Reduce Motion film, for a photograph.
        reduceMotion = reduceMotion || UserDefaults.standard.bool(forKey: "splashReduceMotion")
        #endif
        var voiceOver = UIAccessibility.isVoiceOverRunning
        #if DEBUG
        voiceOver = voiceOver || UserDefaults.standard.bool(forKey: "splashVoiceOver")
        #endif
        let scene = SplashScene(size: bounds.size, scale: window.screen.scale,
                                safeTop: window.safeAreaInsets.top,
                                reduceMotion: reduceMotion,
                                signedIn: authReady && signedIn)
        // The resting lockup, faded up, instead of the film: under Reduce Motion (the layers would
        // travel), with VoiceOver running (the film is decoration, and for a VoiceOver user pure
        // latency), and on a phone already running hot.
        let hot = ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue
        let still = reduceMotion || voiceOver || hot
        let film: SplashFilm = still ? SplashLockup() : SplashDirection.current.film()
        self.film = film
        self.scene = scene
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Frozen on its first frame until that frame is on screen.
        root.speed = 0
        root.timeOffset = 0
        landAt = film.build(on: root, scene: scene)
        CATransaction.commit()
        // The view's own canvas covers the app until the film's first frame is on the SCREEN — a
        // Metal layer has nothing to show until its first drawable lands, and clearing this at
        // build flashed the screen beneath (the sign-in gate, at ~12 %) for a frame on the Pro
        // Max. From then the film's ground covers it, and the dissolve must reveal the app.
        film.whenFirstFrameShown { [weak self] in self?.backgroundColor = .clear }
        state = .armed
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    /// Film time now.
    private var now: Double { root.convertTime(CACurrentMediaTime(), from: nil) }

    @objc private func tick(_ link: CADisplayLink) {
        switch state {
        case .armed:
            #if DEBUG
            if let t = Self.freezeAt {
                root.timeOffset = t
                film?.still(at: t)
                state = .frozen
                return
            }
            if Self.filming {
                state = .filming
                recorder.begin(direction: SplashDirection.current.rawValue)
                return
            }
            #endif
            // The first frame is on screen: roll.
            SplashTrace.mark("first-tick roll")
            let begin = CACurrentMediaTime() + Self.preroll
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            root.beginTime = begin
            root.timeOffset = 0
            root.speed = 1
            CATransaction.commit()
            film?.roll(at: begin)
            state = .playing
        case .playing:
            // The film's own clock decides when it has landed (a stall pauses it); the wall
            // clock bounds the whole launch and schedules the way out.
            let wall = now
            let t = film?.elapsed ?? wall
            if intent, authReady { leave(at: wall, film: t, reason: "intent"); return }
            let ready = authReady && (!signedIn || artReady || t >= landAt + Self.artPatience)
            if (t >= landAt + Self.landedHold && ready) || wall >= Self.ceiling { leave(at: wall, film: t) }
        case .leaving:
            if let leaveAt, now >= leaveAt + exitFor { finish() }
        #if DEBUG
        case .filming:
            filmStep()
        #endif
        default:
            break
        }
    }

    // MARK: Leave

    /// The film's way out (a dissolve off the app, which is already drawing the same picture
    /// underneath, unless the film has its own). Touches reach the app from here on.
    private func leave(at t: Double, film elapsed: Double, reason: String = "landed") {
        guard state == .playing else { return }
        let start = t + 1.0 / 120.0
        leaveAt = start
        SplashTrace.mark(String(format: "leave film=%.3f wall=%.3f auth=%d art=%d (%@)", elapsed, t,
                                authReady ? 1 : 0, artReady ? 1 : 0, reason))
        if let film, let scene {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            exitFor = film.exit(on: root, scene: scene, at: start)
            CATransaction.commit()
        }
        isUserInteractionEnabled = false
        state = .leaving
        onLeaving?()
    }

    private func finish() {
        guard state != .done else { return }
        state = .done
        SplashTrace.mark("finished")
        link?.invalidate()
        link = nil
        film?.end()
        onFinished?()
        // VoiceOver lands on the first element of the screen the splash has revealed.
        UIAccessibility.post(notification: .screenChanged, argument: nil)
    }

    #if DEBUG
    // MARK: Filming

    private func filmStep() {
        switch recorder.step(ready: authReady && (artReady || !signedIn)) {
        case .wait:
            return
        case .frame(let i):
            let t = Double(i) / SplashFilmRecorder.fps
            let exitAt = landAt + Self.landedHold
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            if leaveAt == nil, t >= exitAt, let film, let scene {
                print(String(format: "SPLASH_FILM_EXIT %.4f", exitAt))
                leaveAt = exitAt
                exitFor = film.exit(on: root, scene: scene, at: exitAt)
                onLeaving?()
            }
            root.timeOffset = t
            CATransaction.commit()
            film?.still(at: t)
            CATransaction.flush()
            guard let window else { return }
            if let own = film?.frame(at: t) {
                // A film that draws its own frames is recorded from them; its way out is laid
                // over one photograph of the app beneath.
                if t >= exitAt, recorder.app == nil {
                    root.isHidden = true
                    recorder.app = recorder.photograph(window)
                    root.isHidden = false
                }
                let lift = SplashGlassFilm.groundLifts
                let out = 1 - SplashEase(x1: 0.45, y1: 0, x2: 0.55, y2: 1)(min(max((t - exitAt - lift.0) / (lift.1 - lift.0), 0), 1))
                recorder.write(own, over: recorder.app, opacity: out, index: i)
            } else {
                recorder.capture(window, index: i)
            }
            if t >= exitAt + exitFor + 0.2 { recorder.end(frames: i + 1); finish() }
        }
    }
    #endif
}

#if DEBUG
/// `-splashFilm 1`: steps the frozen film at 30 fps and photographs the whole window each step.
@MainActor
struct SplashFilmRecorder {
    static let fps = 30.0
    enum Step { case wait, frame(Int) }
    private var directory: URL?
    private var readySince: CFTimeInterval?
    private var startedWaiting = CACurrentMediaTime()
    private var index = 0

    mutating func begin(direction: String) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("splash-film/\(direction)", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        directory = dir
        startedWaiting = CACurrentMediaTime()
        print("SPLASH_FILM_BEGIN \(dir.path)")
    }

    /// Waits for the app underneath to be ready (and a settle for its images), then hands out
    /// frame indices one per tick.
    mutating func step(ready: Bool) -> Step {
        let clock = CACurrentMediaTime()
        if readySince == nil {
            if ready || clock - startedWaiting > 10 { readySince = clock }
            return .wait
        }
        guard clock - (readySince ?? clock) > 2.0 else { return .wait }
        defer { index += 1 }
        return .frame(index)
    }

    func capture(_ window: UIWindow, index: Int) {
        guard let directory else { return }
        let image = photograph(window)
        let url = directory.appendingPathComponent(String(format: "f%04d.jpg", index))
        try? image.jpegData(compressionQuality: 0.9)?.write(to: url)
    }

    /// The app beneath, for a film whose own frames are laid over it on the way out.
    var app: UIImage?

    func photograph(_ window: UIWindow) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true
        return UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
    }

    /// One of the film's own frames, over the app at `opacity`, at the recorder's 2× size.
    func write(_ frame: CGImage, over app: UIImage?, opacity: Double, index: Int) {
        guard let directory else { return }
        let size = CGSize(width: CGFloat(frame.width) / 1.5, height: CGFloat(frame.height) / 1.5)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            app?.draw(in: CGRect(origin: .zero, size: size))
            UIImage(cgImage: frame).draw(in: CGRect(origin: .zero, size: size), blendMode: .normal, alpha: opacity)
        }
        let url = directory.appendingPathComponent(String(format: "f%04d.jpg", index))
        try? image.jpegData(compressionQuality: 0.9)?.write(to: url)
    }

    func end(frames: Int) {
        print("SPLASH_FILM_DONE frames=\(frames) dir=\(directory?.path ?? "-")")
    }
}
#endif

#if DEBUG
/// `-splashTrace 1`: the launch's milestones in seconds since the PROCESS started, so a slow
/// first frame (the app's) can be told from a slow film (the splash's).
enum SplashTrace {
    static let on = UserDefaults.standard.bool(forKey: "splashTrace")
    private static let processStart: Double = {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        sysctl(&mib, u_int(mib.count), &info, &size, nil, 0)
        let t = info.kp_proc.p_starttime
        return Double(t.tv_sec) + Double(t.tv_usec) / 1_000_000
    }()

    static func mark(_ event: String) {
        guard on else { return }
        print(String(format: "SPLASH_TRACE %.3f %@", Date().timeIntervalSince1970 - processStart, event))
    }
}
#else
enum SplashTrace { static func mark(_ event: String) {} }
#endif
