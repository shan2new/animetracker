import UIKit
import QuartzCore

/// SILK — ribbons of light gathered into the name (`SplashSilk.metal`).
///
/// Researched against what the premium streamers shipped in 2025 — Apple TV's intro (macro light
/// through curved glass: silky spectral bands on black), Netflix's and HBO Max's crisp flat logos —
/// and against every rejection of the 24 Sep rounds: no 3D, no gloss, no balls ("2004"), nothing
/// that depends on content, nothing gimmicky. Macro ribbons of the icon's warm light flow across the
/// dark; they gather onto the name's line and into the letters; the lockup settles into the app's
/// own flat wordmark — the ribbon, "Previously", the coral full stop.
struct SplashSilkScript: SplashShaderScript, @unchecked Sendable {
    let vertexFunction = "silkVertex"
    let fragmentFunction = "silkFragment"
    let mipmapped = false

    static let pointSize: CGFloat = 44

    let size: CGSize
    let scale: CGFloat
    let name: CGImage
    let nameBox: CGRect
    let mark: CGRect
    var landAt: Double { 1.46 }

    @MainActor
    init?(scene: SplashScene) {
        let title = SplashTitle(pointSize: Self.pointSize, tracking: -1.0, contentsScale: scene.scale)
        guard let shot = title.snapshot(scale: scene.scale * 2, blur: 0) else { return nil }
        size = scene.size
        scale = scene.scale
        name = shot.image
        // The app's own lockup (`Wordmark`): the ribbon, a gap, the name — scaled from the header's
        // 11-pt ribbon beside 20-pt type.
        let k = Self.pointSize / 20
        let ribbonWidth = (11 * k).rounded()
        let ribbonHeight = ribbonWidth * MarkGeometry.aspect
        let gap = (8 * k).rounded()
        let total = ribbonWidth + gap + title.size.width
        let left = (scene.size.width / 2 - total / 2).rounded()
        let centreY = (scene.size.height * 0.46).rounded()
        mark = CGRect(x: left, y: centreY - ribbonHeight / 2, width: ribbonWidth, height: ribbonHeight)
        nameBox = CGRect(x: left + ribbonWidth + gap, y: centreY - title.size.height / 2,
                         width: title.size.width, height: title.size.height)
    }

    func params(at t: Double) -> [SIMD4<Float>] {
        let ease = SplashEase(x1: 0.45, y1: 0, x2: 0.2, y2: 1)
        func phase(_ from: Double, _ to: Double) -> Double { ease(min(max((t - from) / (to - from), 0), 1)) }
        let presence = phase(0.0, 0.28)
        let gather = phase(0.52, 1.06)
        let confine = phase(0.70, 1.12)
        let settle = phase(1.04, 1.36)
        let canvas = SIMD4<Float>(0x09 / 255, 0x09 / 255, 0x0B / 255, 1)
        return [
            SIMD4(Float(size.width), Float(size.height), Float(scale), Float(t)),
            SIMD4(Float(nameBox.minX), Float(nameBox.minY), Float(nameBox.width), Float(nameBox.height)),
            SIMD4(Float(mark.minX), Float(mark.minY), Float(mark.width), Float(mark.height)),
            SIMD4(Float(presence), Float(gather), Float(confine), Float(settle)),
            canvas,
        ]
    }
}
