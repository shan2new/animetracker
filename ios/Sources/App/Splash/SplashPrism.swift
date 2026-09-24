import UIKit
import QuartzCore

/// PRISM — the app icon's ribbon, sculpted in glass, lit on a dark stage (`SplashPrism.metal`).
///
/// Researched, not invented (24 Sep): the premium streamers' launches all make the BRAND MARK the
/// hero, as a real material under light, on a dark stage, briefly — Netflix's ribbon-folded N built
/// in ~750 ms; Apple TV's November 2025 ident, a solid glass logo shot in macro with coloured light
/// moving through it; HBO Max's iridescent logo out of a blur. The icon here is already a Liquid
/// Glass ribbon with a coral full stop, so the launch is that object, alive: its bevels catch the
/// light first, then the icon's own ramp — gold, amber, coral — pours down through the glass; the
/// coral bead glows beside the tails; the name settles beneath; the app comes up.
struct SplashPrismScript: SplashShaderScript, @unchecked Sendable {
    let vertexFunction = "prismVertex"
    let fragmentFunction = "prismFragment"
    let mipmapped = false

    static let ribbonWidth: CGFloat = 104
    static let namePointSize: CGFloat = 36

    let size: CGSize
    let scale: CGFloat
    let name: CGImage
    let mark: CGRect
    let nameBox: CGRect
    let bead: CGPoint
    let beadRadius: CGFloat
    var landAt: Double { 1.36 }

    @MainActor
    init?(scene: SplashScene) {
        let title = SplashTitle(pointSize: Self.namePointSize, fontName: "Outfit-SemiBold", tracking: -0.8,
                                contentsScale: scene.scale)
        guard let shot = title.snapshot(scale: scene.scale * 2, blur: 0) else { return nil }
        size = scene.size
        scale = scene.scale
        name = shot.image
        // The icon's composition: the ribbon, and the full stop beside its tails.
        let w = Self.ribbonWidth
        let h = w * MarkGeometry.aspect
        let lockupWidth = w * MarkGeometry.lockupWidth
        let gap: CGFloat = 30
        let total = h + gap + title.size.height
        let top = (scene.size.height * 0.45 - total / 2).rounded()
        let left = (scene.size.width / 2 - lockupWidth / 2).rounded()
        mark = CGRect(x: left, y: top, width: w, height: h)
        bead = CGPoint(x: left + w * MarkGeometry.periodCenterX, y: top + w * MarkGeometry.periodCenterY)
        beadRadius = w * MarkGeometry.periodDiameter / 2
        nameBox = CGRect(x: (scene.size.width / 2 - title.size.width / 2).rounded(), y: top + h + gap,
                         width: title.size.width, height: title.size.height)
    }

    func params(at t: Double) -> [SIMD4<Float>] {
        let out = SplashEase(x1: 0.22, y1: 0.8, x2: 0.3, y2: 1)
        let gentle = SplashEase(x1: 0.4, y1: 0, x2: 0.2, y2: 1)
        let settle = out(min(t / 1.15, 1))
        let zoom = 1.28 + (1.0 - 1.28) * settle
        let tilt = -0.07 * (1 - settle)
        let reveal = gentle(min(max((t - 0.04) / 0.70, 0), 1))
        let pour = gentle(min(max((t - 0.10) / 0.95, 0), 1))
        let beadIn = gentle(min(max((t - 0.68) / 0.26, 0), 1))
        let nameIn = gentle(min(max((t - 0.84) / 0.32, 0), 1))
        let glint = (t - 0.98) / 0.50
        let canvas = SIMD4<Float>(0x09 / 255, 0x09 / 255, 0x0B / 255, 1)
        return [
            SIMD4(Float(size.width), Float(size.height), Float(scale), Float(t)),
            SIMD4(Float(mark.minX), Float(mark.minY), Float(mark.width), Float(mark.height)),
            SIMD4(Float(zoom), Float(tilt), Float(reveal), Float(pour)),
            SIMD4(Float(beadIn), Float(nameIn), Float(glint), Float(pour)),
            SIMD4(Float(nameBox.minX), Float(nameBox.minY), Float(nameBox.width), Float(nameBox.height)),
            SIMD4(Float(bead.x), Float(bead.y), Float(beadRadius), 0),
            canvas,
        ]
    }
}
