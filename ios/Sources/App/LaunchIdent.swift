import SwiftUI

// The launch. The app icon's ribbon, at cinematic scale, drawn by light — then the app comes
// through it.
//
// iOS opens the app onto the bare canvas (the launch screen is `LaunchBackground`, nothing else:
// a launch image drawn from the asset catalogue is not reliably rendered — it never draws on the
// iOS 27 simulator — so the ident owns the whole entrance). On the app's first live frame a
// travelling light draws the ribbon from its head to its tails, the icon's material forming
// behind it — the ramp, the rim, the pool of warm light it casts on the canvas; as the light
// passes the tails the coral full stop lands, with one pulse of its own light. The composition
// holds, still. Then, once auth has answered, the ident pushes through: it grows a hair and fades
// as the app emerges beneath it, settling from a hair small. One gesture, one object, the brand's
// own material; no tagline, no flash, no grain, no haptic; nothing flies into a corner.
//
// EVERY value here is a pure function of live time — the seconds of frames actually presented,
// read off `TimelineView(.animation)`, with any real stall between two frames cut out of the
// clock. There are no implicit animations in the ident: an animation started in `onAppear` is
// folded into the view's first frame and never plays, and a `Task.sleep` counts wall time while
// the main thread is still busy. The ribbon is rasterised once at its size and touched only by
// a mask, a small light band and layer transforms.
//
// Under Reduce Motion nothing is drawn or pushed: the composition fades in, holds, and
// crossfades to the app.
struct LaunchIdent: View {
    @Environment(LaunchHandoff.self) private var handoff
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The ident has started to push through: the app should begin emerging beneath it.
    let onLeaving: () -> Void
    /// The ident is gone.
    let onFinished: () -> Void

    @State private var clock = IdentClock()
    @State private var done = false

    /// The ribbon's width: a third of the screen, where a title card sits.
    static let ribbonWidth: CGFloat = 120
    /// The ribbon's centre as a fraction of the screen — a hair high, a hair left, the full stop
    /// balancing it.
    static let restCentre = CGPoint(x: 0.5, y: 0.44)
    static let restOffset = CGPoint(x: -14, y: 0)

    // The beats, in seconds of live time.
    /// The system's own launch transition swallows the app's first frames; the drawing waits.
    static let preroll = 0.22
    /// The light draws the ribbon head to foot: gathering, then easing into the tails.
    static let revealFor = 0.60
    /// The full stop lands as the light passes the tails.
    // 0.52 (review i2): the stop begins as the light passes ~87 % of the draw, so it has landed
    // before the composition may leave.
    static let beadAt = 0.52
    static let strike = (response: 0.40, damping: 0.72)
    /// Its one pulse of light.
    static let bloomFor = 0.45
    /// The composition holds before it may leave.
    // Stated in the bead's own clock (review i2): `preroll + beadAt + 0.22` — the bead is
    // scheduled in LIVE time (t − preroll) while the hold is in ident time, and at a flat 0.82
    // the stop began 60 ms AFTER a fast launch had started leaving, so the brand's period landed
    // only on a slow network. 0.96 now; the pulse is half through when the exit begins.
    static let holdUntil = preroll + beadAt + 0.22
    /// The picture's own patience: the ident may leave without the hero's art after this.
    static let artPatience = 1.6
    /// The push through: the composition grows and is gone before the ground has finished
    /// lifting, so it never lingers as a ghost over the screen arriving beneath it.
    static let exitFor = 0.28
    static let exitScale = 1.12
    static let compositionExitFraction = 0.50
    /// The ground lifts a beat after the composition starts leaving, so the ribbon is gone
    /// before the picture is more than half through (review i5: a translucent ribbon over art).
    static let groundLag = 0.05
    /// Auth's own wait is capped at 3 s; the ident does not outlast it by much.
    static let patience = 4.0

    /// A WALL-clock ceiling from the first frame (review i4): live seconds cut stalls out, so on
    /// a starved device the ident had no ceiling at all and held for six seconds.
    static let wallCeiling = 2.4

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(paused: done)) { context in
                let t = clock.tick(context.date, authReady: handoff.authReady, artReady: handoff.artReady, reduceMotion: reduceMotion)
                let frame = IdentFrame(t: t, leaveAt: clock.leaveAt, reduceMotion: reduceMotion)
                stage(frame, size: geo.size)
                    .onChange(of: frame.stage) { _, stage in advance(to: stage) }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    // MARK: - The picture at time t

    private func stage(_ f: IdentFrame, size: CGSize) -> some View {
        let ribbon = Self.restRibbonRect(in: size)
        let bead = Self.restBeadRect(ribbon: ribbon)
        // The composition's own frame — the lockup plus room for the light it casts — so the push
        // through fades a small group, never a full-screen one.
        let pad = ribbon.width * 0.5
        let lockup = CGRect(x: ribbon.minX - pad, y: ribbon.minY - pad,
                            width: ribbon.width * MarkGeometry.lockupWidth + pad * 2,
                            height: ribbon.height + pad * 2)
        let ribbonLocal = CGRect(x: pad, y: pad, width: ribbon.width, height: ribbon.height)
        let beadLocal = Self.restBeadRect(ribbon: ribbonLocal)
        return ZStack {
            // The ground fades as one flat layer.
            ThemeColor.canvas.opacity(f.ground)

            ZStack(alignment: .topLeading) {
                RibbonFill(material: 1, castShadow: f.cast, width: ribbon.width, reveal: f.reveal, light: f.light)
                    .frame(width: ribbon.width, height: ribbon.height)
                    .position(x: ribbonLocal.midX, y: ribbonLocal.midY)

                // The full stop's one pulse of light as it lands.
                Circle()
                    .fill(RadialGradient(colors: [ThemeColor.brandPeriod.opacity(0.42), .clear],
                                         center: .center, startRadius: 0, endRadius: bead.width * 1.4))
                    .frame(width: bead.width * 2.8, height: bead.width * 2.8)
                    .scaleEffect(0.5 + 0.9 * f.bloom)
                    .opacity(f.bloom)
                    .position(x: beadLocal.midX, y: beadLocal.midY)
                PeriodBead(diameter: bead.width, lit: true)
                    .scaleEffect(max(f.bead, 0.001))
                    .opacity(min(f.bead * 3, 1))
                    .position(x: beadLocal.midX, y: beadLocal.midY)
            }
            .frame(width: lockup.width, height: lockup.height)
            // The push through: the composition grows a hair and fades.
            .scaleEffect(f.scale)
            .opacity(f.opacity)
            .position(x: lockup.midX, y: lockup.midY)
        }
        .frame(width: size.width, height: size.height)
    }

    // MARK: - The composition at rest

    static func restRibbonRect(in size: CGSize) -> CGRect {
        let w = ribbonWidth
        let h = ribbonWidth * MarkGeometry.aspect
        let cx = size.width * restCentre.x + restOffset.x
        let cy = size.height * restCentre.y + restOffset.y
        return CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)
    }

    static func restBeadRect(ribbon: CGRect) -> CGRect {
        let d = ribbon.width * MarkGeometry.periodDiameter
        let cx = ribbon.minX + ribbon.width * MarkGeometry.periodCenterX
        let cy = ribbon.minY + ribbon.width * MarkGeometry.periodCenterY
        return CGRect(x: cx - d / 2, y: cy - d / 2, width: d, height: d)
    }

    // MARK: - The hand-off

    private func advance(to stage: IdentFrame.Stage) {
        switch stage {
        case .holding:
            break
        case .leaving:
            handoff.phase = .leaving
            onLeaving()
        case .done:
            done = true
            onFinished()
        }
    }
}

/// Live time for the ident: seconds of frames actually presented, not wall time.
///
/// A reference type on purpose — it is written from inside the timeline's body, where a state
/// write is not allowed, and nothing needs to re-render because of it: the tick that writes it
/// is the tick that reads it.
@MainActor
final class IdentClock {
    private var start: Date?
    private var last: Date?
    /// Live time at which the ident was cleared to leave.
    private(set) var leaveAt: Double?
    private var firstFrame: Date?

    /// The largest gap between two frames that still counts as continuous. Anything longer is a
    /// stall — the main thread was busy, no frame was presented — and is cut out of the clock. A
    /// merely slow frame (the simulator at 8–10 fps) must NOT be cut: cutting it plays the motion
    /// in stepped slow motion.
    private static let stall: TimeInterval = 0.25

    func tick(_ date: Date, authReady: Bool, artReady: Bool = true, reduceMotion: Bool) -> Double {
        guard let start else {
            self.start = date
            last = date
            return 0
        }
        // Stalls are cut out only while HOLDING (review i5): once leaving, wall time drives the
        // exit, so a busy main thread shortens the ghost instead of freezing it mid-fade.
        if leaveAt == nil, let last, date.timeIntervalSince(last) > Self.stall {
            self.start = start.addingTimeInterval(date.timeIntervalSince(last) - 1.0 / 60.0)
        }
        last = date
        let t = date.timeIntervalSince(self.start ?? date)
        if firstFrame == nil { firstFrame = date }
        if leaveAt == nil {
            let held = t >= (reduceMotion ? 0.6 : LaunchIdent.holdUntil)
            let overdue = date.timeIntervalSince(firstFrame ?? date) >= LaunchIdent.wallCeiling
            // The app emerges beneath the ident WITH its picture (review i2: it used to come
            // through as a tint, then a blur, then the poster — three arrivals in the first
            // second); auth's patience stays the ceiling.
            let ready = authReady && (artReady || t >= LaunchIdent.artPatience)
            if held, ready || t >= LaunchIdent.patience { leaveAt = t } else if overdue { leaveAt = t }
        }
        return t
    }
}

/// Every value on screen at live time `t`, in one place.
struct IdentFrame: Equatable {
    enum Stage: Equatable { case holding, leaving, done }

    let stage: Stage
    /// The ribbon drawn head to foot, 0 → 1.
    let reveal: Double
    /// Where the drawing light is along the ribbon while it draws, or `nil` once it has.
    let light: Double?
    /// The pool of light beneath, forming with the ribbon.
    let cast: Double
    /// The full stop's strike, 0 → 1 (one restrained overshoot).
    let bead: Double
    /// Its pulse of light, 0 → 1 → 0.
    let bloom: Double
    /// The push through: the composition's scale and opacity, and the ground's opacity.
    let scale: Double
    let opacity: Double
    let ground: Double

    init(t: Double, leaveAt: Double?, reduceMotion: Bool) {
        if reduceMotion {
            // A crossfade in, a hold, a crossfade out. Nothing draws or pushes.
            let fadeIn = IdentFrame.ease(t, over: 0.12)
            let out = leaveAt.map { IdentFrame.ease(t - $0, over: 0.22) } ?? 0
            reveal = 1
            light = nil
            cast = 1
            bead = 1
            bloom = 0
            scale = 1
            opacity = fadeIn * (1 - out)
            ground = 1 - out
            stage = leaveAt.map { t >= $0 + 0.3 ? .done : .leaving } ?? .holding
            return
        }
        let live = t - LaunchIdent.preroll
        let drawn = IdentFrame.ease(live, over: LaunchIdent.revealFor)
        reveal = drawn
        light = drawn > 0 && drawn < 1 ? drawn : nil
        // The pool of light arrives as the ribbon finishes: it lights the page it hangs on.
        cast = IdentFrame.ease(live - LaunchIdent.revealFor * 0.75, over: 0.40)
        bead = IdentFrame.spring(live - LaunchIdent.beadAt, response: LaunchIdent.strike.response,
                                 damping: LaunchIdent.strike.damping)
        let pulse = min(max((live - LaunchIdent.beadAt) / LaunchIdent.bloomFor, 0), 1)
        bloom = pulse > 0 && pulse < 1 ? sin(pulse * .pi) : 0
        if let leaveAt {
            let since = t - leaveAt
            let out = IdentFrame.easeIn(since, over: LaunchIdent.exitFor * LaunchIdent.compositionExitFraction)
            scale = 1 + (LaunchIdent.exitScale - 1) * out
            opacity = 1 - out
            ground = 1 - IdentFrame.easeIn(since - LaunchIdent.groundLag, over: LaunchIdent.exitFor)
            stage = since >= LaunchIdent.exitFor + LaunchIdent.groundLag ? .done : .leaving
        } else {
            scale = 1
            opacity = 1
            ground = 1
            stage = .holding
        }
    }

    /// The unit-step response of a damped spring at rest — what SwiftUI's
    /// `spring(response:dampingFraction:)` traces — as a function, so it can be read at any live
    /// time rather than driven by the animation system.
    static func spring(_ t: Double, response: Double, damping: Double) -> Double {
        guard t > 0 else { return 0 }
        let omega = 2 * Double.pi / response
        if damping < 1 {
            let damped = omega * (1 - damping * damping).squareRoot()
            return 1 - exp(-damping * omega * t) * (cos(damped * t) + (damping * omega / damped) * sin(damped * t))
        }
        return 1 - exp(-omega * t) * (1 + omega * t)
    }

    /// A smooth 0 → 1 over `over` seconds.
    static func ease(_ t: Double, over duration: Double) -> Double {
        let x = min(max(t / duration, 0), 1)
        return x * x * (3 - 2 * x)
    }

    /// Fast, then easing into place (cubic out).
    static func easeOut(_ t: Double, over duration: Double) -> Double {
        let x = min(max(t / duration, 0), 1)
        return 1 - pow(1 - x, 3)
    }

    /// Gathering pace (quadratic in): the exit's own curve.
    static func easeIn(_ t: Double, over duration: Double) -> Double {
        let x = min(max(t / duration, 0), 1)
        return x * x
    }
}
