import UIKit
import QuartzCore

/// MACRO — the film opens inside the full stop (`SplashMacro.metal`).
///
/// The first frame is the coral bead in macro — the whole screen its glossy surface under a studio
/// light, drifting — and then the camera pulls back hard: the curve of the bead comes into view,
/// it shrinks away toward its place, and the name rushes in from the edge of the frame until the
/// camera settles on the finished lockup and the bead is its full stop. The zoom is exponential
/// (every doubling takes the same time, so the speed reads as one continuous pull, not an
/// acceleration into the ground), shot with a shutter at its fastest (`travel`).
struct SplashMacroScript: SplashShaderScript, @unchecked Sendable {
    let vertexFunction = "macroVertex"
    let fragmentFunction = "macroFragment"
    let mipmapped = true

    static let pointSize: CGFloat = 52
    /// The macro shot: the bead this many times its size — larger than the screen's diagonal.
    static let startZoom = 210.0
    /// Where the slow drift has got to when the camera commits to the pull: the bead's curve has
    /// just come into the frame at top and bottom.
    static let driftZoom = 120.0
    static let commitAt = 0.40
    static let arriveAt = 1.02
    static let settledAt = 1.12
    /// Commits slowly, pulls fast, glides in.
    static let pull = SplashEase(x1: 0.58, y1: 0, x2: 0.16, y2: 1)
    /// The shutter, as a share of a 60 Hz frame.
    static let shutter = 1.0 / 90.0

    let size: CGSize
    let scale: CGFloat
    let name: CGImage
    let text: CGRect
    let stop: CGPoint
    let stopRadius: CGFloat
    var landAt: Double { Self.settledAt + 0.08 }

    @MainActor
    init?(scene: SplashScene) {
        let title = SplashTitle(pointSize: Self.pointSize, tracking: -1.4, contentsScale: scene.scale)
        // The name is seen far larger than it rests on the way in; drawn at three times the
        // screen's density and sampled through mipmaps, it is sharp both close and at rest.
        guard let shot = title.snapshot(scale: scene.scale * 3, blur: 0, includeStop: false) else { return nil }
        size = scene.size
        scale = scene.scale
        name = shot.image
        let origin = CGPoint(x: (scene.size.width / 2 - title.size.width / 2).rounded(),
                             y: (scene.size.height * 0.46 - title.size.height / 2).rounded())
        text = CGRect(origin: origin, size: title.size)
        let frame = title.stop.frame.offsetBy(dx: origin.x, dy: origin.y)
        stop = CGPoint(x: frame.midX, y: frame.midY)
        stopRadius = frame.width / 2
    }

    /// Log zoom at film time `t`.
    private func logZoom(_ t: Double) -> Double {
        let start = log(Self.startZoom), drift = log(Self.driftZoom), rest = 0.0
        if t <= Self.commitAt {
            return start + (drift - start) * (t / Self.commitAt)
        }
        if t <= Self.arriveAt {
            let p = Self.pull((t - Self.commitAt) / (Self.arriveAt - Self.commitAt))
            // Arrives a hair past rest (pulled back slightly too far) and settles forward.
            return drift + (log(0.985) - drift) * p
        }
        let q = SplashEase.step(t, Self.arriveAt, Self.settledAt)
        return log(0.985) + (rest - log(0.985)) * q
    }

    /// How far toward the lockup the camera has panned: the bead starts centred on screen.
    private func pan(_ t: Double) -> Double {
        guard t > Self.commitAt else { return 0 }
        return Self.pull(min((t - Self.commitAt) / (Self.arriveAt - Self.commitAt), 1))
    }

    func params(at t: Double) -> [SIMD4<Float>] {
        let lz = logZoom(t)
        let travel = abs(logZoom(t + 0.004) - logZoom(t - 0.004)) / 0.008 * Self.shutter
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        let k = CGFloat(pan(t))
        let anchor = CGPoint(x: centre.x + (stop.x - centre.x) * k, y: centre.y + (stop.y - centre.y) * k)
        let fade = SplashEase.step(t, 0.0, 0.14)
        // The coral light the bead spills: wide up close, a soft breath at rest.
        let halo = 0.35 + 0.65 * min(max(lz / log(20.0), 0), 1)
        let glint = (t - (Self.settledAt - 0.10)) / 0.42
        let drift = min(t / Self.arriveAt, 1)
        let canvas = SIMD4<Float>(0x09 / 255, 0x09 / 255, 0x0B / 255, 1)
        let coral = SIMD4<Float>(0xF0 / 255, 0x56 / 255, 0x3F / 255, 1)
        return [
            SIMD4(Float(size.width), Float(size.height), Float(scale), Float(t)),
            SIMD4(Float(text.minX), Float(text.minY), Float(text.width), Float(text.height)),
            SIMD4(Float(stop.x), Float(stop.y), Float(stopRadius), 0),
            SIMD4(Float(anchor.x), Float(anchor.y), Float(lz), Float(travel)),
            SIMD4(Float(fade), Float(halo), Float(glint), Float(drift)),
            canvas,
            coral,
        ]
    }
}
