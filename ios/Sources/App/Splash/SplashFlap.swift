import SwiftUI
import UIKit
import QuartzCore
import CoreText

/// FLAP — the departures board turns to "P.", then the name surfaces.
///
/// The identity is a split-flap board (26 Sep, `FlapGeometry`), so the launch is the one thing a
/// board does. It comes up blank where the sign-in gate draws its mark; the letter's module runs
/// through two capitals and slows into the P; the full stop turns a beat later, so the two read as
/// one word arriving; the gate's light breathes up behind and the name surfaces beneath. Then
/// stillness.
///
/// Every turn is a real flap's. The old face's top half falls toward the viewer about the seam,
/// gathering speed, and its back — the new face's lower half — lands still gathering speed and lifts
/// once off the stack. Light follows the angle: a falling flap catches it as it tips, darkens
/// edge-on and throws a soft shadow on the flap it is about to cover; a landing flap comes out of
/// that shade into full light at the contact. The board is drawn as the gate's lit board is
/// (`PreviouslyMark`: its ramps, rims, shadows), and in the stillness at the end the gate's own
/// picture of it (`LaunchLockup.images`) comes up over it: what is left IS the mark the gate draws.
///
/// Pure Core Animation: every move is a keyframe track in film time, built once. The render server
/// plays it, so the app building its tree underneath cannot stall it.
@MainActor
final class SplashFlapFilm: SplashFilm {
    // MARK: The film

    /// The capitals the letter's module passes on its way to the P: the nearest before it in the
    /// alphabet that sit in the module with the P's own air. "M" and "O" are wider than the module
    /// in Outfit Bold, and "A" (as wide as it is tall) runs to within six units of the flap's
    /// edges. So the board counts up to P; it does not roll dice.
    static let passing: [Character] = ["L", "N"]

    enum Beat {
        /// The blank board comes up where the gate draws its mark.
        static let appear = (0.0, 0.18)
        /// The first flap lets go once the blank board has stood for a beat.
        static let firstFlip = 0.24
        /// The letter's turns, let-go to contact: quick through the passing capitals, slower into
        /// the P. The board finds its letter.
        static let letterTurns = [0.10, 0.11, 0.16]
        /// One small, damped lift off the stack: less under a capital the next flap covers at once,
        /// more under the P.
        static let passingBounce = Bounce(angle: 2.5 * .pi / 180, length: 0.045)
        static let landingBounce = Bounce(angle: 5 * .pi / 180, length: 0.064)
        /// The full stop turns a beat after the P lands, so the two read as one word arriving.
        static let stopBeat = 0.08
        static let stopTurn = 0.14
        static let stopBounce = Bounce(angle: 4 * .pi / 180, length: 0.056)
    }

    /// How a turning flap takes the light: washes of white or black laid over it, by its angle.
    enum Light {
        /// The light a falling flap catches as it tips toward the viewer, gone by `gleamSpan` of
        /// the way to edge-on. A lift, not a highlight: no gloss.
        static let gleamPeak = 0.07
        static let gleamSpan = 0.62
        /// Edge-on, a flap is this far into shade.
        static let edge = 0.5
        /// The passing flap's shadow on the lower flap: its strength at the seam, and how far down
        /// the flap it reaches.
        static let shadow: CGFloat = 0.30
        static let shadowReach: CGFloat = 0.7

        /// Over a falling flap, by how far it has turned (0 standing … π/2 edge-on).
        static func gleam(_ travel: Double) -> Double {
            let u = min(max(travel / (.pi / 2) / gleamSpan, 0), 1)
            let s = sin(.pi * u)
            return gleamPeak * s * s
        }

        static func falling(_ travel: Double) -> Double {
            edge * pow(SplashEase.step(travel / (.pi / 2), 0.15, 1), 1.15)
        }

        /// Over a landing flap, by its angle off the stack: in shade through its swing, full light
        /// at the contact.
        static func landing(_ angle: Double) -> Double {
            edge * pow(max(sin(angle), 0), 0.6)
        }

        /// Over a landed flap lifting once off the stack: a breath of shade, no more (at the
        /// landing's full measure the P's stem greyed for a moment).
        static func lifted(_ angle: Double) -> Double {
            landing(angle) * 0.5
        }
    }

    struct Bounce {
        let angle: Double
        let length: Double
    }

    /// One flap's turn. It lets go at `start` and falls from rest under a constant pull, so it is
    /// edge-on at 1/√2 of `length` and the landing half, still gathering speed, takes well under
    /// half the time the top half did. It lands at `contact`, lifts `bounce.angle` off the stack —
    /// up fast, down soft — and has settled at `settled`.
    struct Flip {
        let start: Double
        let length: Double
        let bounce: Bounce

        var edgeOn: Double { start + length / (2.0).squareRoot() }
        var contact: Double { start + length }
        var settled: Double { contact + bounce.length }

        /// How far the flap has turned at `t`: 0 standing, π/2 edge-on, π landed.
        func travel(_ t: Double) -> Double {
            let u = min(max((t - start) / length, 0), 1)
            return .pi * u * u
        }

        /// The landed flap's lift off the stack at `t` (radians, toward the viewer).
        func lift(_ t: Double) -> Double {
            let u = (t - contact) / bounce.length
            guard u > 0, u < 1 else { return 0 }
            if u < Self.peak {
                let v = 1 - u / Self.peak
                return bounce.angle * (1 - v * v)
            }
            return bounce.angle * (1 - SplashEase.step(u, Self.peak, 1))
        }

        static let peak = 0.4
    }

    /// When everything happens, from the turns.
    struct Plan {
        let letter: [Flip]
        let stop: Flip
        /// The gate's light breathes up behind the board as the P lands.
        let light: (Double, Double)
        /// The name surfaces once the stop has landed.
        let name: (Double, Double)
        /// In the stillness after, the gate's own picture of the board comes up over the film's.
        let handOff: (Double, Double)
        let land: Double

        /// For a letter module that passes `passing` capitals on its way to the P.
        init(passing: Int) {
            let turns = Beat.letterTurns
            let lengths = Array(repeating: turns[0], count: max(0, passing + 1 - turns.count)) + turns.suffix(passing + 1)
            var flips: [Flip] = []
            var at = Beat.firstFlip
            for (i, length) in lengths.enumerated() {
                flips.append(Flip(start: at, length: length,
                                  bounce: i == lengths.count - 1 ? Beat.landingBounce : Beat.passingBounce))
                at += length
            }
            let p = flips[flips.count - 1]
            let stop = Flip(start: p.contact + Beat.stopBeat, length: Beat.stopTurn, bounce: Beat.stopBounce)
            let name = (stop.contact + 0.05, stop.contact + 0.45)
            let handOff = (name.1 - 0.04, name.1 + 0.10)
            letter = flips
            self.stop = stop
            light = (p.start + 0.07, p.contact + 0.53)
            self.name = name
            self.handOff = handOff
            land = handOff.1 + 0.06
        }
    }

    /// One camera, head-on and not close: the perspective's distance, in board widths.
    static let depth: CGFloat = 4
    static let appearScale = 0.96
    /// The light breathes up from a hair smaller.
    static let lightFrom = 0.94
    /// The name surfaces from this far below its place.
    static let rise = 8.0
    /// A picture that arrives after its beat began fades up over this long.
    static let lateFade = 0.25
    /// A surfacing: gentle to start, long to settle.
    nonisolated(unsafe) static let surface = CAMediaTimingFunction(controlPoints: 0.25, 0, 0, 1)
    /// The light coming up.
    nonisolated(unsafe) static let breathe = CAMediaTimingFunction(controlPoints: 0.4, 0, 0.3, 1)

    // The lit board's own light and shade, in the numbers `PreviouslyMark` draws it with, so the
    // film's board and the gate's picture of it are one picture.
    /// A top flap's crown: white at its top edge, gone this many units down.
    static let crown: CGFloat = 0.09
    static let crownDepth: CGFloat = 44
    /// The top flap's shadow across the seam on the lower one.
    static let cast: CGFloat = 0.32
    static let castLength: CGFloat = 56
    /// The shadow the board casts, in board widths: its blur radius, its drop, the room it needs.
    /// Core Graphics' blur is twice SwiftUI's shadow radius (measured against `PreviouslyMark`'s
    /// own picture: within a level of alpha).
    static let dropRadius: CGFloat = 0.05
    static let dropOffset: CGFloat = 0.03
    static let dropRoom: CGFloat = 0.14
    static let dropInk: CGFloat = 0.55
    /// Clear room round each flap's picture: the top flap's rim straddles its edge, and a
    /// transparent margin keeps a turning flap's edges smooth.
    static let leafPad: CGFloat = 1

    // MARK: State

    /// The Reduce Motion film, when the board would otherwise turn.
    private var fallback: SplashLockup?
    private weak var root: CALayer?
    private var scene: SplashScene?
    private var plan: Plan?
    /// The gate's frame for its mark (`LaunchLockup.markFrame`): the board fills it.
    private var rest: CGRect = .zero
    private var ground: CALayer?
    /// Everything but the canvas, anchored on the mark so the way out can recede about it.
    private var lockup: CALayer?
    /// The film's board: its shadow on the canvas, and over that its flaps.
    private var board: CALayer?
    private var drop: CALayer?
    private var flaps: CALayer?
    private var landAt: Double = 0
    /// A first launch has no pictures cached: they are drawn once the film is rolling (`late`).
    /// Until they are up (`pending`) the film has not landed, and if they came after their beat it
    /// lands that much later (`lateBy`).
    private var late = false
    private var pending = false
    private var lateBy: Double = 0

    // MARK: Build

    func build(on root: CALayer, scene: SplashScene) -> Double {
        // Under Reduce Motion a turning board is the motion the setting asks to be spared: the
        // resting lockup, faded up (the stage already plays it there; this keeps the film honest).
        if scene.reduceMotion {
            let still = SplashLockup()
            fallback = still
            return still.build(on: root, scene: scene)
        }
        self.root = root
        self.scene = scene
        let s = scene.scale
        let size = scene.size
        let screen = CGRect(origin: .zero, size: size)
        // On the device's pixel grid, as SwiftUI lays the gate's mark out: half a pixel off (136.5 pt
        // on a 3× phone), every picture here would be resampled soft.
        let gate = LaunchLockup.markFrame(in: size, signedIn: scene.signedIn)
        let rest = CGRect(origin: CGPoint(x: Self.pixel(gate.minX, s), y: Self.pixel(gate.minY, s)), size: gate.size)
        self.rest = rest
        // Points per design unit: the board fills the gate's frame for its mark.
        let k = rest.width / FlapGeometry.span

        let ground = CALayer.splash(screen, scale: s)
        ground.backgroundColor = SplashInk.canvas.cgColor
        root.addSublayer(ground)
        self.ground = ground

        let lockup = CALayer.splash(screen, scale: s)
        lockup.anchorPoint = CGPoint(x: rest.midX / max(size.width, 1), y: rest.midY / max(size.height, 1))
        lockup.position = CGPoint(x: rest.midX, y: rest.midY)
        root.addSublayer(lockup)
        self.lockup = lockup

        let board = CALayer.splash(CGRect(x: rest.minX, y: rest.minY,
                                          width: FlapGeometry.span * k, height: FlapGeometry.height * k), scale: s)
        lockup.addSublayer(board)
        self.board = board
        let drop = Self.dropShadow(k: k, scale: s)
        board.addSublayer(drop)
        self.drop = drop
        // The flaps turn in depth under one camera, its eye on the board's centre, which is the seam's.
        let flaps = CALayer.splash(board.bounds, scale: s)
        var camera = CATransform3DIdentity
        camera.m34 = -1 / max(Self.depth * board.bounds.width, 1)
        flaps.sublayerTransform = camera
        board.addSublayer(flaps)
        self.flaps = flaps

        let capitals = Self.passing.compactMap { Self.capital($0, k: k) }
        let plan = Plan(passing: capitals.count)
        self.plan = plan
        let letterFaces = [Face.blank] + capitals.map { Face.glyph($0, evenOdd: false) }
            + [Face.glyph(FlapGeometry.letterPath(scale: k), evenOdd: true)]
        let letter = Self.stack(module: 0, faces: letterFaces, flips: plan.letter, k: k, scale: s)
        let stop = Self.stack(module: 1, faces: [.blank, .stop], flips: [plan.stop], k: k, scale: s)
        for layer in letter.lower + stop.lower + letter.upper + stop.upper { flaps.addSublayer(layer) }
        flaps.addSublayer(Self.pins(k: k, scale: s, in: flaps.bounds))

        board.play(
            SplashTrack("opacity", 0.0, at: Beat.appear.0).to(1.0, at: Beat.appear.1, SplashCurve.fade),
            SplashTrack("transform.scale", Self.appearScale, at: Beat.appear.0).to(1.0, at: Beat.appear.1, Self.surface))

        landAt = plan.land
        if let pictures = LaunchLockup.cachedImages(scale: s, typeSize: LaunchLockup.typeSize()) {
            place(pictures, arrival: 0)
        } else {
            // A first launch, or the first after an update: the pictures are drawn once the film is
            // rolling. The board needs none of them before its hand-off.
            late = true
            pending = true
        }
        return plan.land
    }

    // MARK: The gate's pictures

    /// The gate's own pictures, where the gate draws them: its light behind the board, its name
    /// beneath, and its mark over the film's board at the hand-off. `arrival` is when they were
    /// ready: a beat already begun plays from then.
    private func place(_ pictures: LaunchLockup.Images, arrival: Double) {
        guard let lockup, let board, let drop, let flaps, let plan, let scene else { return }
        let s = scene.scale
        // Each picture at its own pixel size, from a pixel corner: drawn 1:1, never resampled.
        func picture(_ image: CGImage, at x: CGFloat, _ y: CGFloat) -> CALayer {
            let layer = CALayer.splash(CGRect(x: Self.pixel(x, s), y: Self.pixel(y, s),
                                              width: CGFloat(image.width) / s, height: CGFloat(image.height) / s), scale: s)
            layer.contents = image
            return layer
        }
        let glow = LaunchLockup.Bloom.size
        let light = picture(pictures.bloom, at: rest.midX - glow / 2, rest.midY - glow / 2)
        lockup.insertSublayer(light, below: board)
        let mark = picture(pictures.mark, at: rest.minX + pictures.markBox.minX, rest.minY + pictures.markBox.minY)
        lockup.insertSublayer(mark, above: board)
        let name = picture(pictures.name, at: (scene.size.width - pictures.nameSize.width) / 2, rest.maxY + LaunchLockup.nameGap)
        lockup.addSublayer(name)

        let lit = Self.window(plan.light, after: arrival)
        let said = Self.window(plan.name, after: arrival)
        let handed = Self.window(plan.handOff, after: arrival)
        light.play(SplashTrack("opacity", 0.0, at: lit.0).to(1.0, at: lit.1, Self.breathe),
                   SplashTrack("transform.scale", Self.lightFrom, at: lit.0).to(1.0, at: lit.1, Self.breathe))
        name.play(SplashTrack("opacity", 0.0, at: said.0).to(1.0, at: said.1, SplashCurve.fade),
                  SplashTrack("transform.translation.y", Self.rise, at: said.0).to(0.0, at: said.1, Self.surface))
        // The hand-off. The gate's picture comes up over the film's board, which stays whole under
        // it (two pictures of one board, faded across each other, dip toward the canvas); the
        // film's shadow gives way to the picture's as it does, so the two never darken the canvas
        // twice; then the film's flaps go, covered.
        mark.play(SplashTrack("opacity", 0.0, at: handed.0).to(1.0, at: handed.1, SplashCurve.fade))
        drop.play(SplashTrack("opacity", 1.0, at: handed.0).to(0.0, at: handed.1, SplashCurve.fade))
        flaps.play(SplashTrack("opacity", 1.0).snap(0, at: handed.1))
        lateBy = max(0, max(lit.1, said.1, handed.1) - max(plan.light.1, plan.name.1, plan.handOff.1))
    }

    /// A beat for a picture that became ready at `arrival`: as planned, or, arrived after the beat
    /// began, from its arrival to the beat's own end, never quicker than `lateFade`.
    private static func window(_ beat: (Double, Double), after arrival: Double) -> (Double, Double) {
        guard arrival > beat.0 else { return beat }
        return (arrival, max(beat.1, arrival + lateFade))
    }

    /// A first launch: the gate's pictures, drawn on the main thread once the film is rolling, and
    /// cached for every launch after.
    private func drawLate(at arrival: Double?) {
        guard pending, let root, let scene else { return }
        pending = false
        guard let pictures = LaunchLockup.images(scale: scene.scale, typeSize: LaunchLockup.typeSize()) else { return }
        // Timed from when they are ready, not from when they were asked for: the process's first
        // text layout can take half a second.
        let at = arrival ?? max(root.convertTime(CACurrentMediaTime(), from: nil), 0)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        place(pictures, arrival: at)
        CATransaction.commit()
        SplashTrace.mark(String(format: "flap pictures at film %.3f", at))
    }

    func roll(at media: CFTimeInterval) {
        if let fallback { fallback.roll(at: media); return }
        guard pending else { return }
        DispatchQueue.main.async { [weak self] in self?.drawLate(at: nil) }
    }

    /// DEBUG photography holds the film without rolling it: late pictures are placed on their beats.
    func still(at t: Double) {
        if let fallback { fallback.still(at: t); return }
        if pending { drawLate(at: 0) }
    }

    var elapsed: Double? {
        if let fallback { return fallback.elapsed }
        guard late, let root else { return nil }
        let t = root.convertTime(CACurrentMediaTime(), from: nil)
        return pending ? min(t, landAt - 0.01) : t - lateBy
    }

    // MARK: The way out

    static let lockupLeaves = 0.16
    static let recede = 0.985
    /// The canvas lifts only once the lockup has gone (it began at 0.08, and for a tenth of a
    /// second the fading name and the arriving feed showed at once — a double exposure).
    static let groundLifts = (0.14, 0.42)
    nonisolated(unsafe) static let leaveCurve = CAMediaTimingFunction(controlPoints: 0.4, 0, 0.6, 1)
    nonisolated(unsafe) static let groundCurve = CAMediaTimingFunction(controlPoints: 0.45, 0, 0.55, 1)

    /// The way out, as the other films leave (`SplashGlassFilm`): the lockup goes to plain canvas
    /// first, receding a hair, so the brand is never printed over the app coming up underneath;
    /// then the canvas itself lifts off it.
    func exit(on root: CALayer, scene: SplashScene, at t: Double) -> Double {
        if let fallback { return fallback.exit(on: root, scene: scene, at: t) }
        guard let lockup, let ground else { return 0 }
        lockup.play(
            SplashTrack("opacity", 1.0, at: t).to(0.0, at: t + Self.lockupLeaves, Self.leaveCurve),
            SplashTrack("transform.scale", 1.0, at: t).to(Self.recede, at: t + Self.lockupLeaves, Self.leaveCurve))
        ground.play(SplashTrack("opacity", 1.0, at: t + Self.groundLifts.0).to(0.0, at: t + Self.groundLifts.1, Self.groundCurve))
        return Self.groundLifts.1 + 0.02
    }

    // MARK: The board

    private enum Face {
        case blank
        /// A glyph's outline in the board's space, and its fill rule.
        case glyph(CGPath, evenOdd: Bool)
        case stop
    }

    /// A module's faces, every half its own layer, stacked as a real module stacks its flaps: the
    /// lower halves oldest first (each landing flap covers the last), the upper halves newest at the
    /// back (each falling flap uncovers the next). `flips[j]` turns face j into face j + 1.
    private static func stack(module m: Int, faces: [Face], flips: [Flip], k: CGFloat, scale s: CGFloat)
        -> (lower: [CALayer], upper: [CALayer]) {
        let last = faces.count - 1
        let above = Half(module: m, upper: true, k: k, scale: s)
        let below = Half(module: m, upper: false, k: k, scale: s)
        var lower: [CALayer] = [], upper: [CALayer] = []
        for (j, face) in faces.enumerated() {
            // The upper half: uncovered when the flap in front of it falls, falling in its turn.
            let top = leaf(picture(above, face: face, k: k, scale: s), above, scale: s)
            var shown = SplashTrack("opacity", j == 0 ? 1.0 : 0.0)
            if j > 0 { shown = shown.snap(1, at: flips[j - 1].start) }
            if j < last {
                let flip = flips[j]
                shown = shown.snap(0, at: flip.edgeOn)
                let gleam = overlay(.white, on: top, above, scale: s)
                let shade = overlay(.black, on: top, above, scale: s)
                top.play(SplashTrack("transform.rotation.x", 0.0).follow(from: flip.start, to: flip.edgeOn) { -flip.travel($0) })
                gleam.play(SplashTrack("opacity", 0.0).follow(from: flip.start, to: flip.edgeOn) { Light.gleam(flip.travel($0)) })
                shade.play(SplashTrack("opacity", 0.0).follow(from: flip.start, to: flip.edgeOn) { Light.falling(flip.travel($0)) })
            }
            top.play(shown)
            upper.append(top)

            // The lower half: the back of the flap that fell, landing on the face before it.
            let bottom = leaf(picture(below, face: face, k: k, scale: s), below, scale: s)
            var present = SplashTrack("opacity", j == 0 ? 1.0 : 0.0)
            if j > 0 {
                let flip = flips[j - 1]
                present = present.snap(1, at: flip.edgeOn)
                // Its shadow, passing over the face it is about to cover.
                let shadow = passingShadow(below, scale: s)
                shadow.play(SplashTrack("opacity", 0.0).follow(from: flip.start, to: flip.contact) { sin(flip.travel($0)) })
                lower.append(shadow)
                let shade = overlay(.black, on: bottom, below, scale: s)
                bottom.play(SplashTrack("transform.rotation.x", Double.pi / 2)
                    .follow(from: flip.edgeOn, to: flip.contact) { .pi - flip.travel($0) }
                    .follow(from: flip.contact, to: flip.settled) { flip.lift($0) })
                shade.play(SplashTrack("opacity", Light.edge)
                    .follow(from: flip.edgeOn, to: flip.contact) { Light.landing(.pi - flip.travel($0)) }
                    .follow(from: flip.contact, to: flip.settled) { Light.lifted(flip.lift($0)) })
            }
            // Covered once the next face has landed on it and settled.
            if j < last { present = present.snap(0, at: flips[j].settled) }
            bottom.play(present)
            lower.append(bottom)
        }
        return (lower, upper.reversed())
    }

    /// A half of a module, placed on the device's pixel grid (the board's origin is on it).
    /// `picture` is its picture's box in board points, from a pixel corner, so a resting flap draws
    /// 1:1 and is never resampled soft. `hinge` is its seam-side edge carried to the nearest pixel
    /// row: two flaps meeting on an antialiased row let the ink of the face behind show through as a
    /// hairline. `outline` is the flap's shape with that edge, and `side` everything on its side of
    /// the hinge (both in board points).
    private struct Half {
        let picture: CGRect
        let hinge: CGFloat
        let side: CGRect
        let outline: CGPath
        let upper: Bool
        let module: Int

        @MainActor
        init(module m: Int, upper: Bool, k: CGFloat, scale s: CGFloat) {
            let span = FlapGeometry.modules[m]
            let x0 = span.x0 * k, x1 = span.x1 * k
            let top = (upper ? 0 : FlapGeometry.seamBottom) * k
            let foot = (upper ? FlapGeometry.seamTop : FlapGeometry.height) * k
            let pad = SplashFlapFilm.leafPad
            let px = SplashFlapFilm.pixel(x0 - pad, s, .down), py = SplashFlapFilm.pixel(top - pad, s, .down)
            picture = CGRect(x: px, y: py, width: SplashFlapFilm.pixel(x1 + pad, s, .up) - px,
                             height: SplashFlapFilm.pixel(foot + pad, s, .up) - py)
            let edge = upper ? foot : top
            hinge = SplashFlapFilm.pixel(edge, s)
            side = upper
                ? CGRect(x: picture.minX, y: picture.minY, width: picture.width, height: hinge - picture.minY)
                : CGRect(x: picture.minX, y: hinge, width: picture.width, height: picture.maxY - hinge)
            // The straight run of the seam edge (clear of its small rounded corners) carried a couple
            // of pixels past itself, then cut at the hinge row.
            let r = FlapGeometry.seamRadius * k
            let band = CGRect(x: x0 + r, y: edge - 2 / s, width: x1 - x0 - r * 2, height: 4 / s)
            outline = FlapGeometry.flapPath(m, upper: upper, scale: k)
                .union(CGPath(rect: band, transform: nil))
                .intersection(CGPath(rect: side, transform: nil))
            self.upper = upper
            module = m
        }
    }

    /// `v` on the pixel grid of a screen of `scale` pixels per point.
    private static func pixel(_ v: CGFloat, _ scale: CGFloat,
                              _ rule: FloatingPointRoundingRule = .toNearestOrAwayFromZero) -> CGFloat {
        (v * scale).rounded(rule) / scale
    }

    /// A half of a face as a flap that can turn: hinged at the seam (a top flap at its foot, a lower
    /// flap at its head), its back never shown.
    private static func leaf(_ picture: CGImage?, _ half: Half, scale: CGFloat) -> CALayer {
        let layer = CALayer()
        layer.bounds = CGRect(origin: .zero, size: half.picture.size)
        layer.anchorPoint = CGPoint(x: 0.5, y: (half.hinge - half.picture.minY) / half.picture.height)
        layer.position = CGPoint(x: half.picture.midX, y: half.hinge)
        layer.contentsScale = scale
        layer.contents = picture
        layer.isDoubleSided = false
        return layer
    }

    /// A wash over a turning flap, the light it catches or the shade it turns into; its opacity
    /// follows the flap's angle.
    private static func overlay(_ color: UIColor, on leaf: CALayer, _ half: Half, scale: CGFloat) -> CALayer {
        let wash = CAShapeLayer()
        wash.frame = leaf.bounds
        wash.contentsScale = scale
        var shift = CGAffineTransform(translationX: -half.picture.minX, y: -half.picture.minY)
        wash.path = half.outline.copy(using: &shift)
        wash.fillColor = color.cgColor
        wash.opacity = 0
        leaf.addSublayer(wash)
        return wash
    }

    /// The shadow a turning flap throws on the lower flap it is about to cover: strongest at the
    /// seam, gone `Light.shadowReach` of the way down.
    private static func passingShadow(_ below: Half, scale: CGFloat) -> CALayer {
        let flap = below.outline.boundingBoxOfPath
        let frame = CGRect(x: flap.minX, y: below.hinge, width: flap.width, height: (flap.maxY - below.hinge) * Light.shadowReach)
        let shadow = SplashShade.linear(frame, color: .black,
                                        stops: [(0, Light.shadow), (0.35, Light.shadow * 0.5), (1, 0)], scale: scale)
        shadow.opacity = 0
        return shadow
    }

    /// The shadow the board casts on the canvas, drawn once as the gate's lit board casts it: the
    /// flaps' silhouettes in black, one shadow for all of them (the seam and the gaps between the
    /// modules stay clear), under the flaps.
    private static func dropShadow(k: CGFloat, scale s: CGFloat) -> CALayer {
        let width = FlapGeometry.span * k, height = FlapGeometry.height * k
        let room = width * dropRoom
        let x0 = pixel(-room, s, .down), y0 = pixel(-room, s, .down)
        let frame = CGRect(x: x0, y: y0, width: pixel(width + room, s, .up) - x0, height: pixel(height + room, s, .up) - y0)
        let layer = CALayer.splash(frame, scale: s)
        let w = Int((frame.width * s).rounded()), h = Int((frame.height * s).rounded())
        guard w > 0, h > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return layer }
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: s, y: -s)
        ctx.translateBy(x: -frame.minX, y: -frame.minY)
        // A shadow is laid out in the context's base space (pixels, y up), whatever the CTM says.
        ctx.setShadow(offset: CGSize(width: 0, height: -width * dropOffset * s), blur: width * dropRadius * 2 * s,
                      color: black(dropInk))
        for m in FlapGeometry.modules.indices {
            ctx.addPath(FlapGeometry.flapPath(m, upper: true, scale: k))
            ctx.addPath(FlapGeometry.flapPath(m, upper: false, scale: k))
        }
        ctx.setFillColor(black(1))
        ctx.fillPath()
        layer.contents = ctx.makeImage()
        return layer
    }

    /// The axle caps at each module's sides. They never move.
    private static func pins(k: CGFloat, scale: CGFloat, in bounds: CGRect) -> CALayer {
        let caps = CGMutablePath()
        let r = FlapGeometry.pinRadius * k
        for c in FlapGeometry.pinCentres(scale: k) {
            caps.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        }
        let pins = CAShapeLayer()
        pins.frame = bounds
        pins.contentsScale = scale
        pins.path = caps
        pins.fillColor = srgb(FlapGeometry.pin)
        return pins
    }

    /// One half of a face, drawn once, as the gate's lit board draws it (`PreviouslyMark`): the
    /// flap's own ramp, the crown and rim light on a top flap, the top flap's shadow across the
    /// seam on a lower one, and the face's share of its glyph. The seam is left clear, as the gate
    /// leaves it.
    private static func picture(_ half: Half, face: Face, k: CGFloat, scale: CGFloat) -> CGImage? {
        let w = Int((half.picture.width * scale).rounded()), h = Int((half.picture.height * scale).rounded())
        guard w > 0, h > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // Points, y down, in the board's own space.
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: scale, y: -scale)
        ctx.translateBy(x: -half.picture.minX, y: -half.picture.minY)
        func ramp(_ colors: [CGColor], _ from: CGFloat, _ to: CGFloat) {
            guard let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: nil) else { return }
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: from * k), end: CGPoint(x: 0, y: to * k),
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
        ctx.saveGState()
        ctx.addPath(half.outline)
        ctx.clip()
        if half.upper {
            ramp([srgb(FlapGeometry.flapTopHigh), srgb(FlapGeometry.flapTopLow)], 0, FlapGeometry.seamTop)
            ramp([white(crown), white(0)], 0, crownDepth)
        } else {
            ramp([srgb(FlapGeometry.flapBottomHigh), srgb(FlapGeometry.flapBottomLow)], FlapGeometry.seamBottom, FlapGeometry.height)
            ramp([black(cast), black(0)], FlapGeometry.seamBottom, FlapGeometry.seamBottom + castLength)
        }
        ctx.restoreGState()
        if half.upper {
            // The lit board's rim: light along the top flap's edge, strongest at its crown, the
            // stroke straddling the edge as the gate's does.
            ctx.saveGState()
            ctx.clip(to: half.side)
            ctx.addPath(FlapGeometry.flapPath(half.module, upper: true, scale: k))
            ctx.setLineWidth(max(0.5, k * 2))
            ctx.replacePathWithStrokedPath()
            ctx.clip()
            ramp([white(0.16), white(0.02)], 0, FlapGeometry.seamTop)
            ctx.restoreGState()
        }
        ctx.saveGState()
        ctx.addPath(half.outline)
        ctx.clip()
        switch face {
        case .blank:
            break
        case .glyph(let outline, let evenOdd):
            ctx.addPath(outline)
            ctx.setFillColor(srgb(FlapGeometry.ink))
            ctx.fillPath(using: evenOdd ? .evenOdd : .winding)
        case .stop:
            ctx.setFillColor(srgb(FlapGeometry.stopInk))
            ctx.fillEllipse(in: FlapGeometry.stopRect(scale: k))
        }
        ctx.restoreGState()
        return ctx.makeImage()
    }

    /// A passing capital in the brand's face (Outfit Bold), set as the P is: its cap height, on its
    /// baseline, centred in the letter's module, and never wider than the module keeps clear of its
    /// rounded corners.
    private static func capital(_ letter: Character, k: CGFloat) -> CGPath? {
        let font = (UIFont(name: "Outfit-Bold", size: 1000) ?? .systemFont(ofSize: 1000, weight: .bold)) as CTFont
        let units = Array(String(letter).utf16)
        var glyphs = [CGGlyph](repeating: 0, count: units.count)
        guard !units.isEmpty, CTFontGetGlyphsForCharacters(font, units, &glyphs, units.count),
              let outline = CTFontCreatePathForGlyph(font, glyphs[0], nil) else { return nil }
        let box = outline.boundingBoxOfPath
        let cap = CTFontGetCapHeight(font)
        guard cap > 0, box.width > 0 else { return nil }
        let module = FlapGeometry.modules[0]
        let room = (module.x1 - module.x0 - FlapGeometry.outerRadius * 2) * k
        let s = min((FlapGeometry.capBottom - FlapGeometry.capTop) * k / cap, room / box.width)
        // Glyph space is y-up from the baseline; the board is y-down from its top.
        var place = CGAffineTransform(a: s, b: 0, c: 0, d: -s,
                                      tx: (module.x0 + module.x1) / 2 * k - box.midX * s, ty: FlapGeometry.capBottom * k)
        return outline.copy(using: &place)
    }

    /// A brand colour in sRGB, the space every picture here is drawn in.
    private static func srgb(_ color: Color) -> CGColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        _ = UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return CGColor(srgbRed: r, green: g, blue: b, alpha: a)
    }

    private static func white(_ alpha: CGFloat) -> CGColor { CGColor(srgbRed: 1, green: 1, blue: 1, alpha: alpha) }
    private static func black(_ alpha: CGFloat) -> CGColor { CGColor(srgbRed: 0, green: 0, blue: 0, alpha: alpha) }
}

private extension SplashTrack {
    /// Follows `value` from film time `a` to `b`, sampled at 120 Hz with a key exactly at `b`: a
    /// motion no one timing function describes (a fall, a bounce, the light on a turning flap).
    /// Holds where it was until `a`, so `value(a)` must be where the track already is.
    func follow(from a: Double, to b: Double, _ value: (Double) -> Double) -> SplashTrack {
        let step = 1.0 / 120.0
        var track = hold(until: a)
        var t = a + step
        while t < b - step / 4 {
            track = track.to(value(t), at: t, SplashCurve.linear)
            t += step
        }
        return track.to(value(b), at: b, SplashCurve.linear)
    }

    /// Holds, then steps to `value` at `t`: a face uncovered, or gone.
    func snap(_ value: Double, at t: Double) -> SplashTrack {
        hold(until: t).to(value, at: t + 0.001, SplashCurve.linear)
    }
}
