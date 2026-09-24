import Foundation
import CoreGraphics
import QuartzCore
import simd
#if canImport(UIKit)
import SwiftUI
import UIKit
#endif

/// ALIGN — the mark as five layers of coloured glass that come into register (`SplashAlign.metal`).
///
/// Ribbon (25 Sep) told the right story — the silk becomes the mark — with the wrong body: one long
/// ribbon bending on an S with a forked tail ("feels like a Snake and feels extremely weird",
/// user). Here nothing bends and nothing has a head or a tail. The film opens on five layers of
/// coloured glass in the mark's shape — gold, amber, coral, rose, violet: Silk's light, as glass —
/// fanned apart in depth; one slow camera move brings the view head-on, and the layers slide into
/// register, each gel's colour sliding into the icon's own, until they are one sheet of it: the
/// gate's lit mark (`LaunchLockup`), exactly where the sign-in screen draws it. Its light comes
/// up; the name surfaces. Apple TV's coloured gels and visionOS's layered icons, in the brand's
/// warm light. Every value is a pure function of film time; the only motion is the camera's.
struct SplashAlignScript: SplashShaderScript, @unchecked Sendable {
    let vertexFunction = "alignVertex"
    let fragmentFunction = "alignFragment"
    let mipmapped = false

    let size: CGSize
    let scale: CGFloat
    /// The mark at rest: where the gate draws it (`LaunchLockup.markFrame`).
    let mark: CGRect
    /// The name's picture, then the lit mark's and the light's (`images`): the gate's own views,
    /// cached by an earlier launch, or blanks until `latePictures` draws them.
    let name: CGImage
    let images: [CGImage]
    let landing: Landing
    var landAt: Double { Beat.land }

    /// Where the pictures go, once they exist — shared with the render thread.
    final class Landing: @unchecked Sendable {
        struct Boxes { var name: CGRect; var mark: CGRect; var bloom: CGRect; var at: CFTimeInterval }
        private let lock = NSLock()
        private var stored: Boxes?
        var boxes: Boxes? { lock.lock(); defer { lock.unlock() }; return stored }
        func land(_ boxes: Boxes) { lock.lock(); stored = boxes; lock.unlock() }
    }

    enum Beat {
        /// The lights come up on the fanned glass — quickly, so no gel lingers dim (a dim gold is
        /// olive, a dim coral brown).
        static let lightsUp = (0.0, 0.22)
        /// The camera eases back and round to head-on.
        static let move = (0.0, 1.45)
        /// The fan holds open a beat longer, then closes: the layers slide into register.
        static let close = (0.30, 1.40)
        static let settle = (0.95, 1.50)
        /// Each gel's colour slides into the icon's own.
        static let register = (0.45, 1.25)
        /// Registered, the sheet is the mark.
        static let fuse = (1.30, 1.55)
        /// The light the glass caught while it turned.
        static let sheen = (1.00, 1.40)
        /// The gate's light comes up behind the mark.
        static let light = (1.00, 1.60)
        /// The film's mark hands over to the gate's own lit mark.
        static let markIn = (1.40, 1.62)
        /// The name surfaces: complete by 1.6 s, so the finished lockup stands still before the
        /// exit (a lockup still arriving when the exit began read as a cut away from it).
        static let name = (1.15, 1.60)
        static let land = 1.90
    }

    enum Open {
        /// The camera's first angle: the fan's spread.
        static let yaw = 0.72, pitch = -0.42, roll = 0.22
        /// How close it starts, on an 852-pt screen (it scales with the screen's height, so every
        /// phone opens on the same framing).
        static let zoom = 2.5
        /// The layers' spacing in depth, in the mark's points.
        static let spacing = 34.0
    }

    static let travel = SplashEase(x1: 0.36, y1: 0, x2: 0.24, y2: 1)
    static let closing = SplashEase(x1: 0.50, y1: 0, x2: 0.20, y2: 1)
    static let inOut = SplashEase(x1: 0.42, y1: 0, x2: 0.25, y2: 1)
    static let arrive = SplashEase(x1: 0.25, y1: 0, x2: 0, y2: 1)

    init(size: CGSize, scale: CGFloat, signedIn: Bool, name: CGImage, images: [CGImage], landing: Landing) {
        self.size = size
        self.scale = scale
        mark = LaunchLockup.markFrame(in: size, signedIn: signedIn)
        self.name = name
        self.images = images
        self.landing = landing
    }

    #if canImport(UIKit)
    @MainActor
    init?(scene: SplashScene) {
        let landing = Landing()
        let rest = LaunchLockup.markFrame(in: scene.size, signedIn: scene.signedIn)
        if let cached = LaunchLockup.cachedImages(scale: scene.scale, typeSize: LaunchLockup.typeSize()) {
            landing.land(Self.boxes(for: cached, mark: rest, screen: scene.size, at: 0))
            self.init(size: scene.size, scale: scene.scale, signedIn: scene.signedIn,
                      name: cached.name, images: [cached.mark, cached.bloom], landing: landing)
        } else {
            let space = CGColorSpace(name: CGColorSpace.sRGB)!
            guard let blank = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage() else { return nil }
            self.init(size: scene.size, scale: scene.scale, signedIn: scene.signedIn,
                      name: blank, images: [blank, blank], landing: landing)
        }
    }

    /// A first launch has no cached pictures: they are drawn once the film is rolling (the film
    /// needs none of them before 1.0 s), and cached for every launch after.
    @MainActor
    func latePictures() -> [CGImage]? {
        guard landing.boxes == nil,
              let pictures = LaunchLockup.images(scale: scale, typeSize: LaunchLockup.typeSize()) else { return nil }
        landing.land(Self.boxes(for: pictures, mark: mark, screen: size, at: CACurrentMediaTime()))
        return [pictures.name, pictures.mark, pictures.bloom]
    }
    #endif

    static func boxes(for pictures: LaunchLockup.Images, mark: CGRect, screen: CGSize, at: CFTimeInterval) -> Landing.Boxes {
        let bloom = LaunchLockup.Bloom.size
        return Landing.Boxes(
            name: CGRect(x: (screen.width - pictures.nameSize.width) / 2, y: mark.maxY + LaunchLockup.nameGap,
                         width: pictures.nameSize.width, height: pictures.nameSize.height),
            mark: pictures.markBox.offsetBy(dx: mark.minX, dy: mark.minY),
            bloom: CGRect(x: mark.midX - bloom / 2, y: mark.midY - bloom / 2, width: bloom, height: bloom),
            at: at)
    }

    // MARK: Frames

    private static func span(_ t: Double, _ s: (Double, Double)) -> Double { min(max((t - s.0) / (s.1 - s.0), 0), 1) }
    private static func mix(_ a: Double, _ b: Double, _ f: Double) -> Double { a + (b - a) * f }

    func params(at t: Double) -> [SIMD4<Float>] { params(at: t, leaving: 0) }

    func params(at t: Double, leaving: Double) -> [SIMD4<Float>] {
        func v(_ a: Double, _ b: Double, _ c: Double, _ d: Double) -> SIMD4<Float> { SIMD4(Float(a), Float(b), Float(c), Float(d)) }
        func r(_ rect: CGRect) -> SIMD4<Float> { v(rect.minX, rect.minY, rect.width, rect.height) }
        let W = Double(size.width), H = Double(size.height)
        let m = Self.travel(Self.span(t, Beat.move))
        let fan = 1 - Self.closing(Self.span(t, Beat.close))
        let zoom = exp(Self.mix(log(Open.zoom * H / 852), 0, m))
        let cx = Self.mix(W / 2, Double(mark.midX), m), cy = Self.mix(H * 0.47, Double(mark.midY), m)
        let spacing = Self.mix(Open.spacing, 0, Self.inOut(Self.span(t, Beat.settle)))
        let presence = SplashEase.step(t, Beat.lightsUp.0, Beat.lightsUp.1)
        // Nothing of the gate's lockup draws until its pictures exist; a late arrival fades in from
        // its arrival rather than popping.
        let boxes = landing.boxes
        let arrived = boxes.map { $0.at == 0 ? 1 : SplashEase.step(CACurrentMediaTime(), $0.at, $0.at + 0.25) } ?? 0
        let offstage = CGRect(x: -10, y: -10, width: 1, height: 1)
        let nameIn = Self.arrive(Self.span(t, Beat.name))
        let nameBox = (boxes?.name ?? offstage).offsetBy(dx: 0, dy: 8 * (1 - nameIn))
        return [
            v(W, H, Double(scale), t),
            r(mark),
            r(nameBox),
            r(boxes?.mark ?? offstage),
            r(boxes?.bloom ?? offstage),
            v(SplashEase.step(t, Beat.markIn.0, Beat.markIn.1) * arrived, SplashEase.step(t, Beat.light.0, Beat.light.1) * arrived,
              nameIn * arrived, leaving),
            SIMD4<Float>(0x09 / 255, 0x09 / 255, 0x0B / 255, 1),
            v(Open.yaw * fan, Open.pitch * fan, Open.roll * fan, zoom),
            v(cx, cy, spacing, SplashEase.step(t, Beat.fuse.0, Beat.fuse.1)),
            v(presence, 1 - SplashEase.step(t, Beat.sheen.0, Beat.sheen.1), SplashEase.step(t, Beat.register.0, Beat.register.1), 0),
        ]
    }
}
