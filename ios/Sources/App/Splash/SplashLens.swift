import UIKit
import QuartzCore

/// LENS — the full stop, as glass, reading the name into being.
///
/// On the dark, one small bead of clear glass. It glides along the line where the name will be,
/// and through it — magnified, the way the system's glass loupe magnifies text — "Previously" is
/// already there; behind it the letters stay, one by one, as it passes. At the end of the word it
/// slows, settles down onto the baseline and shrinks into place, and the glass fills with coral:
/// it was the full stop all along. One object, one gesture — the brand's own mark doing the one
/// thing a full stop does, finishing the sentence.
@MainActor
final class SplashLens: SplashFilm {
    static let pointSize: CGFloat = 48
    /// The bead's radius while it reads.
    static let lensRadius: CGFloat = 23
    /// How much it magnifies.
    static let power: CGFloat = 1.5
    /// It sets off; it runs a hair past its mark, clear of the "y"; it settles back into it.
    static let departAt = 0.08
    static let arriveAt = 0.78
    static let settledAt = 0.96
    /// How far past its mark it runs before settling back.
    static let overrun: CGFloat = 9
    /// A long glide, gentle to start and softer still to land.
    static let glide = SplashEase(x1: 0.42, y1: 0, x2: 0.18, y2: 1)

    private var group: CALayer?
    private var ground: CALayer?

    func build(on root: CALayer, scene: SplashScene) -> Double {
        let s = scene.scale
        let size = scene.size
        let bounds = CGRect(origin: .zero, size: size)

        let ground = CALayer.splash(bounds, scale: s)
        ground.backgroundColor = SplashInk.canvas.cgColor
        root.addSublayer(ground)
        self.ground = ground

        let title = SplashTitle(pointSize: Self.pointSize, tracking: -1.2, contentsScale: s)
        let group = CALayer.splash(CGRect(origin: .zero, size: title.size), scale: s)
        group.position = CGPoint(x: (size.width / 2).rounded(), y: (size.height * 0.46).rounded())
        group.addSublayer(title.layer)
        title.layer.position = CGPoint(x: title.size.width / 2, y: title.size.height / 2)
        root.addSublayer(group)
        self.group = group
        // The glyph's own full stop never draws: the bead becomes it.
        title.stop.opacity = 0

        let r0 = Self.lensRadius
        let stop = title.stop.frame
        let stopRadius = stop.width / 2
        let line = title.ascent - title.xHeight / 2
        let first = title.letters.first?.frame.minX ?? 0
        let from = CGPoint(x: first - r0 * 0.35, y: line)
        let to = CGPoint(x: stop.midX, y: stop.midY)

        if scene.reduceMotion {
            let bead = Self.coral(radius: stopRadius, scale: s)
            bead.position = to
            group.addSublayer(bead)
            group.play(SplashTrack("opacity", 0.0).to(1.0, at: 0.3, SplashCurve.fade))
            return 0.6
        }

        // Through the glass: the whole name, magnified, drawn once at the resolution it is seen at.
        let copy = CALayer.splash(CGRect(origin: .zero, size: title.size), scale: s)
        if let shot = title.snapshot(scale: s * Self.power, blur: 0, includeStop: false) {
            copy.contents = shot.image
        }
        let reader = CAShapeLayer()
        reader.bounds = CGRect(x: 0, y: 0, width: r0 * 2, height: r0 * 2)
        reader.path = CGPath(ellipseIn: reader.bounds, transform: nil)
        copy.mask = reader

        // The bead, in two halves around that view: under it a disc of the dark (the letters it
        // is over are not seen twice), over it the glass and, at the last, the coral.
        let under = CALayer.splash(CGRect(x: 0, y: 0, width: r0 * 2, height: r0 * 2), scale: s)
        under.cornerRadius = r0
        under.backgroundColor = SplashInk.canvas.cgColor
        let over = CALayer.splash(CGRect(x: 0, y: 0, width: r0 * 2, height: r0 * 2), scale: s)
        let glass = Self.glass(radius: r0, scale: s)
        over.addSublayer(glass)
        let coral = Self.coral(radius: r0, scale: s)
        coral.position = CGPoint(x: r0, y: r0)
        over.addSublayer(coral)

        group.addSublayer(under)
        group.addSublayer(copy)
        group.addSublayer(over)

        // One progress drives it all, sampled: where the bead is, how large, how strong a lens.
        let centre = CGPoint(x: title.size.width / 2, y: title.size.height / 2)
        var place = SplashTrack("position", NSValue(cgPoint: from), at: 0)
        var grow = SplashTrack("transform.scale", 1.0, at: 0)
        var lens = SplashTrack("transform", NSValue(caTransform3D: Self.lensTransform(power: Self.power, at: from, around: centre)), at: 0)
        var aperture = SplashTrack("transform.scale", 1 / Self.power, at: 0)
        var clearness = SplashTrack("opacity", 1.0, at: 0)
        var fill = SplashTrack("opacity", 0.0, at: 0)
        let step = 1.0 / 120.0
        let past = CGPoint(x: to.x + Self.overrun, y: to.y)
        let settle = SplashEase(x1: 0.45, y1: 0, x2: 0.25, y2: 1)
        var t = Self.departAt
        while t <= Self.settledAt + step / 2 {
            let c: CGPoint, r: CGFloat, m: CGFloat, clear: Double, coralness: Double
            if t <= Self.arriveAt {
                // Reading: along the line, then down onto the baseline just past the mark,
                // shrinking to a bead and losing its magnification as it leaves the last letter.
                let p = Self.glide((t - Self.departAt) / (Self.arriveAt - Self.departAt))
                c = CGPoint(x: from.x + (past.x - from.x) * CGFloat(p),
                            y: from.y + (past.y - from.y) * CGFloat(SplashEase.step(p, 0.78, 1)))
                r = r0 + (stopRadius * 1.12 - r0) * CGFloat(SplashEase.step(p, 0.72, 1))
                m = Self.power + (1 - Self.power) * CGFloat(SplashEase.step(p, 0.66, 0.96))
                // The coral comes in only clear of the "y": over it, it read as a smudge.
                clear = 1 - SplashEase.step(p, 0.84, 1)
                coralness = SplashEase.step(p, 0.88, 1)
            } else {
                // Settling back into its place, tucked under the "y" as the glyph's own stop is.
                let q = settle((t - Self.arriveAt) / (Self.settledAt - Self.arriveAt))
                c = CGPoint(x: past.x + (to.x - past.x) * CGFloat(q), y: to.y)
                r = stopRadius * (1.12 + (1 - 1.12) * CGFloat(q))
                m = 1
                clear = 0
                coralness = 1
            }
            place = place.to(NSValue(cgPoint: c), at: t, SplashCurve.linear)
            grow = grow.to(r / r0, at: t, SplashCurve.linear)
            lens = lens.to(NSValue(caTransform3D: Self.lensTransform(power: m, at: c, around: centre)), at: t, SplashCurve.linear)
            aperture = aperture.to(r / r0 / m, at: t, SplashCurve.linear)
            clearness = clearness.to(clear, at: t, SplashCurve.linear)
            fill = fill.to(coralness, at: t, SplashCurve.linear)
            t += step
        }
        // The bead appears where it will set off from.
        let appear = SplashTrack("opacity", 0.0).to(1.0, at: 0.12, SplashCurve.fade)
        under.play(place, grow, appear)
        over.play(place, grow, appear)
        copy.play(lens, appear)
        reader.play(place, aperture)
        glass.play(clearness)
        coral.play(fill)

        // The letters stay behind as the bead passes each one.
        for letter in title.letters {
            let reached = Self.time(whenAt: letter.frame.midX - r0 * 0.25, from: from.x, to: to.x)
            letter.play(SplashTrack("opacity", 0.0, at: reached).to(1.0, at: reached + 0.10, SplashCurve.fade))
        }

        // One breath of the full stop's own light as it lands.
        let glow = SplashShade.radial(stop.insetBy(dx: -stop.width * 2.2, dy: -stop.width * 2.2),
                                      color: SplashInk.stop, stops: [(0, 0.45), (0.4, 0.14), (1, 0)], scale: s)
        group.insertSublayer(glow, below: under)
        glow.play(
            SplashTrack("opacity", 0.0).hold(until: Self.settledAt - 0.10).to(1.0, at: Self.settledAt + 0.02, SplashCurve.arrive)
                .to(0.0, at: Self.settledAt + 0.50, SplashCurve.fade),
            SplashTrack("transform.scale", 0.6).hold(until: Self.settledAt - 0.10).to(1.3, at: Self.settledAt + 0.50, SplashCurve.arrive))
        return Self.settledAt + 0.26
    }

    /// The name recedes a hair as the dark lifts off the app.
    func exit(on root: CALayer, scene: SplashScene, at t: Double) -> Double {
        guard let group, let ground else { return 0 }
        group.play(
            SplashTrack("transform.scale", 1.0, at: t).to(0.985, at: t + 0.32, SplashCurve.fade),
            SplashTrack("opacity", 1.0, at: t).to(0.0, at: t + 0.26, SplashCurve.fade))
        ground.play(SplashTrack("opacity", 1.0, at: t + 0.04).to(0.0, at: t + 0.38, SplashCurve.fade))
        return 0.38
    }

    // MARK: - Geometry

    /// Scale by `power` about the point `c` (in the layer's own space), for a layer anchored at
    /// `centre`: `p' = centre + m(p − centre) + (1 − m)(c − centre)`.
    private static func lensTransform(power m: CGFloat, at c: CGPoint, around centre: CGPoint) -> CATransform3D {
        let scale = CATransform3DMakeScale(m, m, 1)
        let shift = CATransform3DMakeTranslation((1 - m) * (c.x - centre.x), (1 - m) * (c.y - centre.y), 0)
        return CATransform3DConcat(scale, shift)
    }

    /// The film time at which the bead's centre reaches `x`.
    private static func time(whenAt x: CGFloat, from x0: CGFloat, to x1: CGFloat) -> Double {
        let target = Double((x - x0) / (x1 - x0))
        guard target > 0 else { return departAt }
        var lo = 0.0, hi = 1.0
        for _ in 0..<40 {
            let mid = (lo + hi) / 2
            if glide(mid) < target { lo = mid } else { hi = mid }
        }
        return departAt + (arriveAt - departAt) * lo
    }

    // MARK: - The bead

    /// Clear glass: the dark deepening toward its rim, a bright rim where the light catches it
    /// (strongest at the upper left, a return glow at the lower right), and one soft highlight.
    private static func glass(radius r: CGFloat, scale: CGFloat) -> CALayer {
        let box = CGRect(x: 0, y: 0, width: r * 2, height: r * 2)
        let glass = CALayer.splash(box, scale: scale)

        let depth = SplashShade.radial(box, color: .black, stops: [(0, 0), (0.72, 0.06), (1, 0.34)], scale: scale)
        depth.cornerRadius = r
        depth.masksToBounds = true
        glass.addSublayer(depth)

        let rim = CAGradientLayer()
        rim.frame = box
        rim.contentsScale = scale
        rim.colors = [UIColor(white: 1, alpha: 0.92).cgColor, UIColor(white: 1, alpha: 0.10).cgColor,
                      UIColor(white: 1, alpha: 0.10).cgColor, UIColor(white: 1, alpha: 0.55).cgColor]
        rim.locations = [0, 0.45, 0.62, 1]
        rim.startPoint = CGPoint(x: 0.15, y: 0.05)
        rim.endPoint = CGPoint(x: 0.85, y: 0.95)
        let ring = CAShapeLayer()
        ring.frame = box
        ring.path = CGPath(ellipseIn: box.insetBy(dx: 0.75, dy: 0.75), transform: nil)
        ring.fillColor = nil
        ring.strokeColor = UIColor.white.cgColor
        ring.lineWidth = 1.5
        rim.mask = ring
        glass.addSublayer(rim)

        let shine = SplashShade.radial(CGRect(x: r * 0.36, y: r * 0.30, width: r * 0.62, height: r * 0.34),
                                       color: .white, stops: [(0, 0.62), (0.55, 0.18), (1, 0)], scale: scale)
        shine.transform = CATransform3DMakeRotation(-0.6, 0, 0, 1)
        glass.addSublayer(shine)
        return glass
    }

    /// The full stop: the brand's coral, lit from the upper left as `PeriodBead` is.
    private static func coral(radius r: CGFloat, scale: CGFloat) -> CALayer {
        let box = CGRect(x: 0, y: 0, width: r * 2, height: r * 2)
        let bead = CALayer.splash(box, scale: scale)
        bead.cornerRadius = r
        bead.backgroundColor = SplashInk.stop.cgColor
        let light = SplashShade.radial(CGRect(x: -r * 0.28, y: -r * 0.36, width: r * 2.0, height: r * 2.0),
                                       color: .white, stops: [(0, 0.20), (1, 0)], scale: scale)
        bead.masksToBounds = true
        bead.addSublayer(light)
        return bead
    }
}
