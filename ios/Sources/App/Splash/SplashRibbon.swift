import Foundation
import CoreGraphics
import simd
#if canImport(UIKit)
import SwiftUI
import UIKit
#endif

/// RIBBON — one ribbon of silk light that becomes the mark (`SplashRibbon.metal`).
///
/// Silk (24 Sep) had the look — warm spectral light on black, a crisp lit edge — but not the
/// story: three bands drifted at random and collapsed onto a line the name faded in on ("way too
/// random. The Silk transitions to what?", user). Here there is one ribbon and one move. The film
/// opens close on it, broad, satin light rippling down it; the camera eases back as it calms — its
/// notched tails come into the frame, the S of it straightens, it stands upright — and it is the
/// mark, in the icon's gold-to-coral, handing over to the gate's own lit mark
/// (`LaunchLockup`) exactly where the sign-in screen draws it; the name surfaces beneath. Every
/// value is a pure function of film time on long curves; there is no noise anywhere.
struct SplashRibbonScript: SplashShaderScript, @unchecked Sendable {
    let vertexFunction = "ribbonPageVertex"
    let fragmentFunction = "ribbonPageFragment"
    let meshVertexFunction: String? = "ribbonMeshVertex"
    let meshFragmentFunction: String? = "ribbonMeshFragment"
    let overFragmentFunction: String? = "ribbonHandoverFragment"
    let mipmapped = false

    let size: CGSize
    let scale: CGFloat
    /// Until the late pictures land: a blank the size of a pixel.
    let name: CGImage
    var images: [CGImage] { [name, name] }
    /// The ribbon at rest: where the gate draws its mark (`LaunchLockup.markFrame`).
    let mark: CGRect
    /// The film's last frame, rendered from the gate's own views once the film is rolling
    /// (`latePictures`): the name, the lit mark (with the bleed its shadow needs) and the light
    /// behind it, and where each goes.
    let late = LatePictures()
    var landAt: Double { Beat.land }

    final class LatePictures: @unchecked Sendable {
        struct Boxes { var name: CGRect; var mark: CGRect; var bloom: CGRect; var at: CFTimeInterval }
        private let lock = NSLock()
        private var stored: Boxes?
        var boxes: Boxes? { lock.lock(); defer { lock.unlock() }; return stored }
        func land(_ boxes: Boxes) { lock.lock(); stored = boxes; lock.unlock() }
    }

    init(size: CGSize, scale: CGFloat, blank: CGImage) {
        self.size = size
        self.scale = scale
        name = blank
        mark = LaunchLockup.markFrame(in: size)
    }

    #if canImport(UIKit)
    @MainActor
    init?(scene: SplashScene) {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let blank = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage() else { return nil }
        self.init(size: scene.size, scale: scene.scale, blank: blank)
    }

    @MainActor
    func latePictures() -> [CGImage]? {
        let typeSize = DynamicTypeSize(UITraitCollection.current.preferredContentSizeCategory) ?? .large
        guard let pictures = LaunchLockup.images(scale: scale, typeSize: typeSize) else { return nil }
        let bloom = LaunchLockup.Bloom.size
        late.land(LatePictures.Boxes(
            name: Self.lockup(screen: size, name: pictures.nameSize).name,
            mark: pictures.markBox.offsetBy(dx: mark.minX, dy: mark.minY),
            bloom: CGRect(x: mark.midX - bloom / 2, y: mark.midY - bloom / 2, width: bloom, height: bloom),
            at: CACurrentMediaTime()))
        return [pictures.name, pictures.mark, pictures.bloom]
    }
    #endif

    /// The launch lockup (`LaunchLockup`): the mark where the gate draws it, the name's line under
    /// it, centred.
    static func lockup(screen: CGSize, name: CGSize) -> (mark: CGRect, name: CGRect) {
        let mark = LaunchLockup.markFrame(in: screen)
        return (mark, CGRect(x: (screen.width - name.width) / 2, y: mark.maxY + LaunchLockup.nameGap,
                             width: name.width, height: name.height))
    }

    // MARK: The choreography

    enum Beat {
        /// The light comes up on the ribbon, already turning.
        static let fadeIn = (0.0, 0.45)
        /// The camera eases back and the ribbon calms into the mark — one move.
        static let move = (0.0, 1.62)
        /// The ripples settle; the ribbon lies flat.
        static let still = (0.30, 1.40)
        /// The light's soft far edge firms into the mark's.
        static let firm = (0.55, 1.30)
        /// Silk to the icon's ramp.
        static let resolve = (1.02, 1.56)
        /// A last catch of light down the ribbon as it lands.
        static let sheen = (1.06, 1.68)
        /// The name, surfacing beneath it.
        static let name = (1.14, 1.82)
        /// The gate's light comes up behind the mark as it lands.
        static let bloom = (0.95, 1.65)
        /// The silk ribbon hands over to the gate's own lit mark, which it has become.
        static let markIn = (1.40, 1.66)
        static let land = 1.90
    }

    /// Where the camera starts: close on the middle of the screen, the ribbon broad and running
    /// past both ends of it.
    enum Macro {
        static let zoom = 3.0
        static let length = 3.0      // x the mark's length
        static let tilt = -0.42      // radians from upright; the tails lean left
        static let bend = 0.26       // the S, radians of lean at its crests
        static let waveRate = 0.6    // radians a second: the S travels slowly down the ribbon
        /// The satin's ripple toward and away from us: its crests' pitch (radians), how many
        /// ripples the ribbon carries, and how fast they travel down it (radians a second).
        static let ripple = 0.72
        static let ripples = 1.55
        static let rippleRate = 2.3
    }

    /// The pull-back: gentle out of the first frame, gentle into the last, in the log of the scale
    /// — so every stretch of it shrinks the picture by the same proportion.
    static let pullBack = SplashEase(x1: 0.50, y1: 0, x2: 0.30, y2: 1)
    static let gentle = SplashEase(x1: 0.35, y1: 0, x2: 0.25, y2: 1)

    struct Pose {
        var zoom: Double
        var length: Double
        var tilt: Double
        var bend: Double
        var wave: Double
        var ripple: Double
        var centre: SIMD2<Double>
        var soft: Double
        var presence: Double
        var resolve: Double
        var name: Double
        var sheen: Double
        var bloom: Double
        var markIn: Double
    }

    private static func progress(_ t: Double, _ span: (Double, Double)) -> Double {
        min(max((t - span.0) / (span.1 - span.0), 0), 1)
    }

    private static func mix(_ a: Double, _ b: Double, _ f: Double) -> Double { a + (b - a) * f }

    func pose(at t: Double) -> Pose {
        let m = Self.pullBack(Self.progress(t, Beat.move))
        let L = Double(mark.height)
        let open = SIMD2(Double(size.width) / 2, Double(size.height) / 2)
        return Pose(
            zoom: exp(Self.mix(log(Macro.zoom), 0, m)),
            length: exp(Self.mix(log(L * Macro.length), log(L), m)),
            tilt: Macro.tilt * (1 - m),
            bend: Macro.bend * (1 - m),
            wave: Macro.waveRate * t,
            ripple: Macro.ripple * (1 - SplashEase.step(t, Beat.still.0, Beat.still.1)),
            centre: open + (SIMD2(Double(mark.midX), Double(mark.midY)) - open) * m,
            soft: 1 - SplashEase.step(t, Beat.firm.0, Beat.firm.1),
            presence: Self.gentle(Self.progress(t, Beat.fadeIn)),
            resolve: SplashEase.step(t, Beat.resolve.0, Beat.resolve.1),
            name: Self.gentle(Self.progress(t, Beat.name)),
            sheen: Self.mix(-0.25, 1.25, Self.gentle(Self.progress(t, Beat.sheen))),
            bloom: SplashEase.step(t, Beat.bloom.0, Beat.bloom.1),
            markIn: SplashEase.step(t, Beat.markIn.0, Beat.markIn.1))
    }

    /// The spine's lean from upright at `s` (0 head → 1 tails): the tilt, and an S that travels.
    private func lean(_ s: Double, _ p: Pose) -> Double {
        p.tilt + p.bend * cos(2 * Double.pi * (s - 0.5) - p.wave)
    }

    /// The satin's pitch toward or away from us at `s`: ripples travelling down the ribbon.
    private func pitch(_ s: Double, _ p: Pose, _ t: Double) -> Double {
        p.ripple * sin(2 * Double.pi * Macro.ripples * s - Macro.rippleRate * t + 0.8)
    }

    func params(at t: Double) -> [SIMD4<Float>] {
        let p = pose(at: t)
        // Nothing of the lockup draws until its pictures have landed (they are drawn while the
        // film opens, long before they are needed; if a starved launch makes them late, they
        // fade in from their arrival rather than popping).
        let boxes = late.boxes
        let arrived = boxes.map { SplashEase.step(CACurrentMediaTime(), $0.at, $0.at + 0.25) } ?? 0
        let offstage = CGRect(x: -10, y: -10, width: 1, height: 1)
        let nameBox = boxes?.name ?? offstage
        let markPictureBox = boxes?.mark ?? offstage
        let bloomBox = boxes?.bloom ?? offstage
        let centre = p.centre
        let rise = 10 * (1 - p.name)
        let canvas = SIMD4<Float>(0x09 / 255, 0x09 / 255, 0x0B / 255, 1)
        return [
            SIMD4(Float(size.width), Float(size.height), Float(scale), Float(t)),
            SIMD4(Float(centre.x), Float(centre.y), Float(min(p.zoom * p.length * 0.42, 260)), Float((1 - p.bloom) * p.presence)),
            SIMD4(Float(nameBox.minX), Float(nameBox.minY + rise), Float(nameBox.width), Float(nameBox.height)),
            SIMD4(Float(p.presence), Float(p.resolve), Float(p.name * arrived), Float(p.sheen)),
            SIMD4(Float(p.length), Float(mark.width), Float(p.soft), Float(p.zoom)),
            canvas,
            SIMD4(Float(markPictureBox.minX), Float(markPictureBox.minY), Float(markPictureBox.width), Float(markPictureBox.height)),
            SIMD4(Float(bloomBox.minX), Float(bloomBox.minY), Float(bloomBox.width), Float(bloomBox.height)),
            SIMD4(Float(p.markIn * arrived), Float(p.bloom * arrived), 0, 0),
        ]
    }

    /// The ribbon as a triangle strip: the spine integrated from its lean about its midpoint, which
    /// the camera carries from the middle of the screen to the mark's place; each sample a pair of
    /// vertices across the width: `(x, y, s, v)` and `(the satin's pitch, the spine's lean, the
    /// width on screen, 0)`. The strip overhangs every edge by a point and a half for the outline's
    /// anti-aliasing, and the lit edge by a fifth of the width more for the light beyond it.
    func mesh(at t: Double) -> [SIMD4<Float>] {
        let p = pose(at: t)
        let n = 220
        let reach = p.zoom * p.length
        let s0 = -1.5 / reach, s1 = 1 + 1.5 / reach
        let ds = (s1 - s0) / Double(n)
        var leans = [Double](repeating: 0, count: n + 1)
        var spine = [SIMD2<Double>](repeating: .zero, count: n + 1)
        for i in 0...n {
            leans[i] = lean(s0 + ds * Double(i), p)
            if i > 0 {
                let a = SIMD2(sin(leans[i - 1]), cos(leans[i - 1])), b = SIMD2(sin(leans[i]), cos(leans[i]))
                spine[i] = spine[i - 1] + (a + b) * (0.5 * ds * reach)
            }
        }
        let f = (0.5 - s0) / ds
        let k = min(Int(f), n - 1)
        let mid = spine[k] + (spine[k + 1] - spine[k]) * (f - Double(k))
        let width = p.zoom * Double(mark.width)
        let half = width * 0.5
        let litOver = max(0.2, 1.5 / half), farOver = 1.5 / half

        var out: [SIMD4<Float>] = []
        out.reserveCapacity((n + 1) * 4)
        for i in 0...n {
            let s = s0 + ds * Double(i)
            let at = p.centre + spine[i] - mid
            let normal = SIMD2(cos(leans[i]), -sin(leans[i]))
            let tilt = pitch(s, p, t)
            for v in [-(1 + litOver), 1 + farOver] {
                let q = at + normal * (half * v)
                out.append(SIMD4(Float(q.x), Float(q.y), Float(s), Float(v)))
                out.append(SIMD4(Float(tilt), Float(leans[i]), Float(width), 0))
            }
        }
        return out
    }
}
