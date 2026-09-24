import SwiftUI
import UIKit
import QuartzCore

/// The launch's resting frame alone — the gate's lit mark, its light, the name beneath
/// (`LaunchLockup`), exactly where the film lands and the sign-in screen draws them — faded up,
/// held, and dissolved into the app. It is the film under Reduce Motion (a stack of glass coming
/// into register is the motion the setting asks to be spared; the system's own answer is a
/// crossfade), with VoiceOver running, on a hot phone, and wherever Metal is not there to draw.
///
/// Its pictures are the ones an earlier launch cached, committed WITH the canvas in the first
/// frame, so the fade is the render server's from the first tick whatever the main thread is
/// doing. (Drawn after the roll on a main thread busy building the app, the live launch showed
/// 2.4 s of black, then the lockup in one frame, gone 0.3 s later — review, 25 Sep.) Only a first
/// launch, with nothing cached, draws them late; its clock then starts when they land.
@MainActor
final class SplashLockup: SplashFilm {
    private weak var root: CALayer?
    private var scene: SplashScene?
    /// Film time at which a late lockup's pictures landed (nil: in the first frame, or not yet).
    private var landedAt: Double?
    private var late = false

    /// The lockup fades up over `fadeIn`, the name a beat behind, then stands still for `hold`.
    static let fadeIn = 0.34
    static let nameAt = (0.08, 0.44)
    static let hold = 0.60

    func build(on root: CALayer, scene: SplashScene) -> Double {
        let ground = CALayer.splash(CGRect(origin: .zero, size: scene.size), scale: scene.scale)
        ground.backgroundColor = SplashInk.canvas.cgColor
        root.addSublayer(ground)
        self.root = root
        self.scene = scene
        if let pictures = LaunchLockup.cachedImages(scale: scene.scale, typeSize: LaunchLockup.typeSize()) {
            place(pictures, on: root, scene: scene, at: 0)
        } else {
            late = true
        }
        return Self.nameAt.1 + Self.hold
    }

    func roll(at media: CFTimeInterval) {
        guard late else { return }
        DispatchQueue.main.async { [weak self] in self?.drawLate() }
    }

    /// DEBUG photography holds the film without rolling it: a late lockup is drawn on the first hold.
    func still(at t: Double) {
        if late, landedAt == nil { drawLate() }
    }

    var elapsed: Double? {
        guard late else { return nil }
        guard let root, let landedAt else { return 0 }
        return max(root.convertTime(CACurrentMediaTime(), from: nil) - landedAt, 0)
    }

    private func drawLate() {
        guard let root, let scene, landedAt == nil else { return }
        let t = root.convertTime(CACurrentMediaTime(), from: nil)
        if let pictures = LaunchLockup.images(scale: scene.scale, typeSize: LaunchLockup.typeSize()) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            place(pictures, on: root, scene: scene, at: t)
            CATransaction.commit()
        }
        landedAt = t
    }

    private func place(_ pictures: LaunchLockup.Images, on root: CALayer, scene: SplashScene, at t: Double) {
        let mark = LaunchLockup.markFrame(in: scene.size, signedIn: scene.signedIn)
        let bloomSize = LaunchLockup.Bloom.size
        func picture(_ image: CGImage, _ frame: CGRect) -> CALayer {
            let layer = CALayer.splash(frame, scale: scene.scale)
            layer.contents = image
            layer.opacity = 0
            root.addSublayer(layer)
            return layer
        }
        let light = picture(pictures.bloom, CGRect(x: mark.midX - bloomSize / 2, y: mark.midY - bloomSize / 2,
                                                   width: bloomSize, height: bloomSize))
        let ribbon = picture(pictures.mark, pictures.markBox.offsetBy(dx: mark.minX, dy: mark.minY))
        let name = picture(pictures.name, CGRect(x: (scene.size.width - pictures.nameSize.width) / 2,
                                                 y: mark.maxY + LaunchLockup.nameGap,
                                                 width: pictures.nameSize.width, height: pictures.nameSize.height))
        for layer in [light, ribbon] {
            layer.play(SplashTrack("opacity", 0.0, at: t).to(1.0, at: t + Self.fadeIn, SplashCurve.fade))
        }
        name.play(SplashTrack("opacity", 0.0, at: t + Self.nameAt.0).to(1.0, at: t + Self.nameAt.1, SplashCurve.fade))
    }
}
