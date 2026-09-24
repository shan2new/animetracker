import UIKit
import QuartzCore

/// AFTERGLOW — the lights going down before an episode (`SplashAfterglow.metal`).
///
/// A soft glow of the brand's warm light drifts up in the dark around the middle of the screen;
/// the name surfaces in it, soft and warm, and clears to crisp white from left to right; then the
/// glow gathers into the coral full stop and rests there, a small light of its own, and the app
/// comes up. Relaxed on purpose: nothing solid, nothing glossy, nothing fast — the audience opens
/// this app to wind down with a show (24 Sep: the macro bead read "2004, heavy and intimidating").
struct SplashAfterglowScript: SplashShaderScript, @unchecked Sendable {
    let vertexFunction = "glowVertex"
    let fragmentFunction = "glowFragment"
    let mipmapped = true

    static let pointSize: CGFloat = 48
    static let glowFor = 0.70
    static let surfaceAt = 0.22
    static let clearFrom = 0.34
    static let clearedAt = 1.00
    static let gatherAt = 0.92
    static let gatheredAt = 1.52

    let size: CGSize
    let scale: CGFloat
    let name: CGImage
    let text: CGRect
    let stop: CGPoint
    let stopRadius: CGFloat
    var landAt: Double { Self.gatheredAt + 0.06 }

    @MainActor
    init?(scene: SplashScene) {
        let title = SplashTitle(pointSize: Self.pointSize, tracking: -1.1, contentsScale: scene.scale)
        guard let shot = title.snapshot(scale: scene.scale * 2, blur: 0, includeStop: false) else { return nil }
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

    func params(at t: Double) -> [SIMD4<Float>] {
        let ease = SplashEase(x1: 0.4, y1: 0, x2: 0.2, y2: 1)
        // The glow rises, breathes once, and — gathering — draws into the full stop and dims.
        let rise = ease(min(t / Self.glowFor, 1))
        let gather = SplashEase(x1: 0.55, y1: 0, x2: 0.25, y2: 1)(
            min(max((t - Self.gatherAt) / (Self.gatheredAt - Self.gatherAt), 0), 1))
        let glow = rise * (1 - 0.82 * gather)
        let breath = sin(min(t / 1.4, 1) * Double.pi)
        // The name surfaces, then settles to white behind a front moving left to right.
        let presence = ease(min(max((t - Self.surfaceAt) / 0.46, 0), 1))
        let clear = ease(min(max((t - Self.clearFrom) / (Self.clearedAt - Self.clearFrom), 0), 1))
        let front = text.minX - 60 + (text.width + 140) * clear
        let warmth = 1 - SplashEase.step(t, Self.gatherAt, Self.gatheredAt)
        // The full stop takes the light as it gathers, and keeps a little of it.
        // It brightens as the light arrives in it, then settles to a small glow of its own.
        let stopLight = SplashEase.step(t, Self.gatherAt + 0.14, Self.gatherAt + 0.46)
            * (1 + 0.35 * sin(Double.pi * SplashEase.step(t, Self.gatherAt + 0.30, Self.gatheredAt)))
            * (1 - 0.40 * SplashEase.step(t, Self.gatheredAt - 0.10, Self.gatheredAt + 0.35))
        let canvas = SIMD4<Float>(0x09 / 255, 0x09 / 255, 0x0B / 255, 1)
        let coral = SIMD4<Float>(0xF0 / 255, 0x56 / 255, 0x3F / 255, 1)
        return [
            SIMD4(Float(size.width), Float(size.height), Float(scale), Float(t)),
            SIMD4(Float(text.minX), Float(text.minY), Float(text.width), Float(text.height)),
            SIMD4(Float(stop.x), Float(stop.y), Float(stopRadius), 0),
            SIMD4(Float(glow), Float(gather), Float(breath), 0),
            SIMD4(Float(front), Float(presence), Float(warmth), Float(stopLight)),
            canvas,
            coral,
        ]
    }
}
