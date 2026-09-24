import UIKit
import QuartzCore
import CoreText
import CoreImage

// The splash's vocabulary. The splash is a film for Core Animation, not a SwiftUI view: every
// layer and every move is committed to the render server once, on the first frame, and plays
// there — so the app building its whole tree on the main thread underneath cannot stall it (the
// old ident was a pure function of MAIN-thread time and needed a stall-cutting clock and a stall
// budget to limp through exactly that). Everything here is a keyframe track on a layer, in FILM
// time: seconds from the splash's first frame, the root layer's local time (`SplashStageView`).

// MARK: - Curves

/// Immutable once made, so shared freely (`nonisolated(unsafe)`: `CAMediaTimingFunction` predates
/// `Sendable`).
enum SplashCurve {
    nonisolated(unsafe) static let linear = CAMediaTimingFunction(name: .linear)
    /// Fast, then a long settle: things arriving.
    nonisolated(unsafe) static let arrive = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
    /// Symmetric: a move between two rests.
    nonisolated(unsafe) static let move = CAMediaTimingFunction(controlPoints: 0.65, 0, 0.35, 1)
    /// Gathering pace: things leaving.
    nonisolated(unsafe) static let depart = CAMediaTimingFunction(controlPoints: 0.55, 0, 1, 0.45)
    /// A camera push — slow to commit, fast through the middle, soft on arrival.
    nonisolated(unsafe) static let dive = CAMediaTimingFunction(controlPoints: 0.72, 0, 0.14, 1)
    /// Fades.
    nonisolated(unsafe) static let fade = CAMediaTimingFunction(controlPoints: 0.4, 0, 0.2, 1)
}

// MARK: - Tracks

/// One property's whole motion across the film, as keys at film times. Built into ONE keyframe
/// animation per property: two animations on one key path would let the later one's backwards
/// fill override the earlier one before it had even begun.
struct SplashTrack {
    let keyPath: String
    private(set) var times: [Double]
    private(set) var values: [Any]
    private(set) var curves: [CAMediaTimingFunction] = []

    init(_ keyPath: String, _ value: Any, at t: Double = 0) {
        self.keyPath = keyPath
        times = [t]
        values = [value]
    }

    /// Moves to `value`, arriving at film time `t`, from wherever the track last was.
    func to(_ value: Any, at t: Double, _ curve: CAMediaTimingFunction = SplashCurve.move) -> SplashTrack {
        var copy = self
        copy.times.append(max(t, times.last ?? 0))
        copy.values.append(value)
        copy.curves.append(curve)
        return copy
    }

    /// Stays put until `t`.
    func hold(until t: Double) -> SplashTrack {
        to(values.last as Any, at: t, SplashCurve.linear)
    }

    /// A damped spring from the last value to `value`, starting at `t` — sampled at 120 Hz into
    /// keys, so a spring can sit inside a keyframe track and be frozen at any film time.
    /// `response`/`damping` are SwiftUI's `spring(response:dampingFraction:)`.
    func spring(to value: CGFloat, at t: Double, response: Double, damping: Double) -> SplashTrack {
        let from = Self.scalar(values.last)
        var copy = hold(until: t)
        let step = 1.0 / 120.0
        var tt = step
        while tt < 4 {
            let s = Self.springStep(tt, response: response, damping: damping)
            copy = copy.to(from + (value - from) * CGFloat(s), at: t + tt, SplashCurve.linear)
            if tt > response * 0.5, abs(1 - s) < 0.0015,
               abs(1 - Self.springStep(tt + step, response: response, damping: damping)) < 0.0015 { break }
            tt += step
        }
        return copy.to(value, at: t + tt + step, SplashCurve.linear)
    }

    var animation: CAAnimation {
        let first = times.first ?? 0
        let last = times.last ?? 0
        let span = max(last - first, 1.0 / 240.0)
        let a = CAKeyframeAnimation(keyPath: keyPath)
        if values.count == 1 {
            a.values = [values[0], values[0]]
            a.keyTimes = [0, 1]
        } else {
            a.values = values
            a.keyTimes = times.map { NSNumber(value: ($0 - first) / span) }
            a.timingFunctions = curves
        }
        // Never exactly 0: Core Animation reads a zero begin time as "now", which is wrong for a
        // film that is frozen or started later.
        a.beginTime = max(first, 1e-4)
        a.duration = span
        a.fillMode = .both
        a.isRemovedOnCompletion = false
        a.calculationMode = .linear
        return a
    }

    /// The unit step response of a damped spring at rest — what SwiftUI's
    /// `spring(response:dampingFraction:)` traces.
    static func springStep(_ t: Double, response: Double, damping: Double) -> Double {
        guard t > 0 else { return 0 }
        let omega = 2 * Double.pi / response
        if damping < 1 {
            let damped = omega * (1 - damping * damping).squareRoot()
            return 1 - exp(-damping * omega * t) * (cos(damped * t) + (damping * omega / damped) * sin(damped * t))
        }
        return 1 - exp(-omega * t) * (1 + omega * t)
    }

    private static func scalar(_ v: Any?) -> CGFloat {
        switch v {
        case let d as Double: CGFloat(d)
        case let c as CGFloat: c
        case let n as NSNumber: CGFloat(n.doubleValue)
        case let i as Int: CGFloat(i)
        default: 0
        }
    }
}

extension CALayer {
    /// Plays these tracks on this layer, in film time.
    func play(_ tracks: SplashTrack...) {
        for track in tracks { add(track.animation, forKey: track.keyPath) }
    }

    /// A plain layer at `frame`, never implicitly animated.
    static func splash(_ frame: CGRect, scale: CGFloat) -> CALayer {
        let layer = CALayer()
        layer.frame = frame
        layer.contentsScale = scale
        return layer
    }
}

// MARK: - Colour

enum SplashInk {
    static let canvas = UIColor(red: 0x09 / 255.0, green: 0x09 / 255.0, blue: 0x0B / 255.0, alpha: 1)
    static let stop = UIColor(red: 0xF0 / 255.0, green: 0x56 / 255.0, blue: 0x3F / 255.0, alpha: 1)
    static let rampTop = UIColor(red: 0xFF / 255.0, green: 0xBB / 255.0, blue: 0x48 / 255.0, alpha: 1)
    static let rampMid = UIColor(red: 0xF2 / 255.0, green: 0x8C / 255.0, blue: 0x3C / 255.0, alpha: 1)
    static let rampFoot = UIColor(red: 0xDE / 255.0, green: 0x4A / 255.0, blue: 0x3C / 255.0, alpha: 1)
    static let ink = UIColor(white: 0.98, alpha: 1)
}

// MARK: - The name

/// "Previously." as one shape layer per glyph, from the bundled Outfit outlines — so each letter
/// can move on its own, and the name stays sharp at any scale the film pushes it to.
@MainActor
final class SplashTitle {
    /// The line's box: from the first glyph's pen position to the full stop's advance, ascent to
    /// descent. Anchored at its centre.
    let layer: CALayer
    /// The ten letters of "Previously", in order.
    private(set) var letters: [CAShapeLayer] = []
    /// The full stop, in the brand's coral.
    private(set) var stop: CAShapeLayer!
    let size: CGSize
    let ascent: CGFloat
    let capHeight: CGFloat
    let xHeight: CGFloat
    private var outlines: [(path: CGPath, frame: CGRect, color: CGColor)] = []

    init(pointSize: CGFloat, fontName: String = "Outfit-SemiBold", tracking: CGFloat,
         ink: UIColor = SplashInk.ink, stopInk: UIColor = SplashInk.stop, contentsScale: CGFloat) {
        let font = UIFont(name: fontName, size: pointSize) ?? .systemFont(ofSize: pointSize, weight: .semibold)
        let text = NSAttributedString(string: "Previously.", attributes: [.font: font, .kern: tracking])
        let line = CTLineCreateWithAttributedString(text)
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading)) - tracking
        self.ascent = ascent
        capHeight = font.capHeight
        xHeight = font.xHeight
        size = CGSize(width: width, height: ascent + descent)
        layer = CALayer()
        layer.bounds = CGRect(origin: .zero, size: size)
        layer.contentsScale = contentsScale

        let runs = (CTLineGetGlyphRuns(line) as? [CTRun]) ?? []
        var shapes: [CAShapeLayer] = []
        for run in runs {
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
            let attributes = CTRunGetAttributes(run) as NSDictionary
            let runFont = attributes[kCTFontAttributeName as String].map { $0 as! CTFont } ?? (font as CTFont)
            for i in 0..<count {
                guard let glyphPath = CTFontCreatePathForGlyph(runFont, glyphs[i], nil) else { continue }
                // Glyph space is y-up from the baseline; the layer is y-down from the top.
                var flip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: positions[i].x, ty: ascent)
                guard let placed = glyphPath.copy(using: &flip) else { continue }
                let box = placed.boundingBoxOfPath
                var shift = CGAffineTransform(translationX: -box.minX, y: -box.minY)
                let shape = CAShapeLayer()
                shape.frame = box
                shape.path = placed.copy(using: &shift)
                shape.contentsScale = contentsScale * 2
                layer.addSublayer(shape)
                shapes.append(shape)
                outlines.append((placed, box, ink.cgColor))
            }
        }
        if let last = shapes.popLast() {
            stop = last
            outlines[outlines.count - 1].color = stopInk.cgColor
        } else {
            stop = CAShapeLayer()
        }
        letters = shapes
        letters.forEach { $0.fillColor = ink.cgColor }
        stop.fillColor = stopInk.cgColor
    }

    /// The name drawn into one bitmap, optionally blurred — the defocused copy a rack focus
    /// crossfades to. Returned with the padding it was drawn with, so it can be laid exactly over
    /// the sharp glyphs.
    func snapshot(scale: CGFloat, blur: CGFloat, includeStop: Bool = true) -> (image: CGImage, pad: CGFloat)? {
        let pad = ceil(blur * 3)
        let w = Int((size.width + pad * 2) * scale), h = Int((size.height + pad * 2) * scale)
        guard w > 0, h > 0,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: scale, y: -scale)
        ctx.translateBy(x: pad, y: pad)
        for (i, o) in outlines.enumerated() where includeStop || i < outlines.count - 1 {
            ctx.addPath(o.path)
            ctx.setFillColor(o.color)
            ctx.fillPath()
        }
        guard let sharp = ctx.makeImage() else { return nil }
        guard blur > 0 else { return (sharp, pad) }
        let input = CIImage(cgImage: sharp)
        let blurred = input.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: blur * scale])
            .cropped(to: input.extent)
        guard let out = SplashTitle.context.createCGImage(blurred, from: input.extent) else { return nil }
        return (out, pad)
    }

    private static let context = CIContext(options: [.cacheIntermediates: false])
}

// MARK: - Light and shade

enum SplashShade {
    /// A vertical gradient in one colour, `stops` as (location, alpha).
    @MainActor
    static func linear(_ rect: CGRect, color: UIColor, stops: [(CGFloat, CGFloat)], scale: CGFloat) -> CAGradientLayer {
        let g = CAGradientLayer()
        g.frame = rect
        g.contentsScale = scale
        g.colors = stops.map { color.withAlphaComponent($0.1).cgColor }
        g.locations = stops.map { NSNumber(value: Double($0.0)) }
        g.startPoint = CGPoint(x: 0.5, y: 0)
        g.endPoint = CGPoint(x: 0.5, y: 1)
        return g
    }

    /// A radial pool: `stops` from the centre (0) to the rect's edge (1).
    @MainActor
    static func radial(_ rect: CGRect, color: UIColor, stops: [(CGFloat, CGFloat)], scale: CGFloat) -> CAGradientLayer {
        let g = CAGradientLayer()
        g.type = .radial
        g.frame = rect
        g.contentsScale = scale
        g.colors = stops.map { color.withAlphaComponent($0.1).cgColor }
        g.locations = stops.map { NSNumber(value: Double($0.0)) }
        g.startPoint = CGPoint(x: 0.5, y: 0.5)
        g.endPoint = CGPoint(x: 1, y: 1)
        return g
    }
}

// MARK: - Easing

/// A CSS/Core Animation cubic-bezier easing as a function, for curves that are sampled into keys
/// rather than handed to Core Animation (several properties driven by one progress).
struct SplashEase {
    let x1: Double, y1: Double, x2: Double, y2: Double

    func callAsFunction(_ t: Double) -> Double {
        let x = min(max(t, 0), 1)
        // Solve bezierX(u) = x for u (Newton, then bisection as a fallback), then return bezierY(u).
        var u = x
        for _ in 0..<8 {
            let dx = Self.bez(u, x1, x2) - x
            let d = Self.slope(u, x1, x2)
            if abs(dx) < 1e-6 { return Self.bez(u, y1, y2) }
            guard abs(d) > 1e-6 else { break }
            u -= dx / d
        }
        var lo = 0.0, hi = 1.0
        u = x
        for _ in 0..<30 {
            let v = Self.bez(u, x1, x2)
            if abs(v - x) < 1e-6 { break }
            if v < x { lo = u } else { hi = u }
            u = (lo + hi) / 2
        }
        return Self.bez(u, y1, y2)
    }

    private static func bez(_ u: Double, _ p1: Double, _ p2: Double) -> Double {
        let v = 1 - u
        return 3 * v * v * u * p1 + 3 * v * u * u * p2 + u * u * u
    }

    private static func slope(_ u: Double, _ p1: Double, _ p2: Double) -> Double {
        let v = 1 - u
        return 3 * v * v * p1 + 6 * v * u * (p2 - p1) + 3 * u * u * (1 - p2)
    }

    /// 0 → 1 across `[a, b]`, smoothly.
    static func step(_ x: Double, _ a: Double, _ b: Double) -> Double {
        let t = min(max((x - a) / (b - a), 0), 1)
        return t * t * (3 - 2 * t)
    }
}
