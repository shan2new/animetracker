import SwiftUI
import CoreGraphics

// The Split-Flap identity's geometry (26 Sep: the owner chose "P." on a departures board — what
// arrives next — over eleven other directions, then had it refined through three rounds; the
// sources are design/app-icon-splitflap). ONE description, in design units of the board, drawn by
// every copy of the mark: the app icon (Icon Composer layers rendered from the same numbers), the
// SwiftUI mark (`PreviouslyMark`) and the launch film (`SplashFlapFilm`, Core Animation) — so the
// film lands on the gate's mark by construction, not by measurement.
//
// The board is two flap modules, the letter's and the full stop's, each split by the hinge seam.
// The P is drawn FOR the board: its bowl ends just above the seam, so the top flap carries the bowl
// and the bottom flap the stem (a real split-flap face is cut that way; a letter centred on the
// module had the seam slicing its bowl). Units are the icon's 1024 canvas with the board's
// top-left at the origin: the board is 708 × 620.
enum FlapGeometry {
    /// The board's width and height in design units.
    static let span: CGFloat = 708
    static let height: CGFloat = 620
    /// Height ÷ width.
    static var aspect: CGFloat { height / span }

    // MARK: The modules

    /// The letter's module and the full stop's, left to right (x0, x1).
    static let modules: [(x0: CGFloat, x1: CGFloat)] = [(0, 486), (508, 708)]
    /// The hinge gap between the flaps: the top flap ends at `seamTop`, the bottom begins at
    /// `seamBottom`.
    static let seamTop: CGFloat = 304
    static let seamBottom: CGFloat = 316
    /// The module's outer corners, and the flaps' corners at the seam.
    static let outerRadius: CGFloat = 38
    static let seamRadius: CGFloat = 6
    /// The axle caps at each module's sides, on the seam's centre line.
    static let pinRadius: CGFloat = 13
    static let pinOffset: CGFloat = 6

    // MARK: The letter

    static let letterX0: CGFloat = 97
    static let letterWidth: CGFloat = 304
    static let capTop: CGFloat = 70
    static let capBottom: CGFloat = 548
    static let stem: CGFloat = 94
    static let bowlStroke: CGFloat = 62
    /// The bowl stops this far above the seam.
    static let bowlGap: CGFloat = 3
    static let corner: CGFloat = 10
    static let counterCorner: CGFloat = 10

    // MARK: The full stop

    /// On the board: centred on its own module, standing on the letter's baseline.
    static let stopCentre = CGPoint(x: 608, y: 501)
    static let stopRadius: CGFloat = 47
    /// Without the flaps (`PreviouslyMark(style: .glyph)`), kerned into the P's empty lower right,
    /// under the bowl: "P." as one word.
    static let glyphStopX: CGFloat = 388

    // MARK: Colour (the dark board, icon A — the app's canvas is dark)

    static let flapTopHigh = Color(hex: 0x42404B), flapTopLow = Color(hex: 0x33313B)
    static let flapBottomHigh = Color(hex: 0x2A2830), flapBottomLow = Color(hex: 0x1E1D23)
    static let ink = Color(hex: 0xF7F1E6)
    static let stopInk = Color(hex: 0xFF5A45)
    static let pin = Color(hex: 0x6E6C78)
    static let seamInk = Color(hex: 0x08080A)

    // MARK: Paths (at `scale` points per design unit, from `origin`)

    /// The P's outline, even-odd: the outer silhouette, then the counter.
    static func letterPath(scale s: CGFloat, origin o: CGPoint = .zero) -> CGPath {
        let x0 = letterX0, bowlBottom = seamTop - bowlGap
        let ro = (bowlBottom - capTop) / 2
        let ri = ro - bowlStroke
        let xc = x0 + letterWidth - ro
        let cy = capTop + ro
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: o.x + x * s, y: o.y + y * s) }
        let path = CGMutablePath()
        // The silhouette: the top-left corner, the bowl's run and round, back along the bowl's foot
        // to the stem, down the stem, its foot, up its left side.
        path.move(to: p(x0 + corner, capTop))
        path.addLine(to: p(xc, capTop))
        path.addArc(center: p(xc, cy), radius: ro * s, startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: false)
        path.addLine(to: p(x0 + stem, bowlBottom))
        path.addLine(to: p(x0 + stem, capBottom - corner))
        path.addArc(tangent1End: p(x0 + stem, capBottom), tangent2End: p(x0 + stem - corner, capBottom), radius: corner * s)
        path.addLine(to: p(x0 + corner, capBottom))
        path.addArc(tangent1End: p(x0, capBottom), tangent2End: p(x0, capBottom - corner), radius: corner * s)
        path.addLine(to: p(x0, capTop + corner))
        path.addArc(tangent1End: p(x0, capTop), tangent2End: p(x0 + corner, capTop), radius: corner * s)
        path.closeSubpath()
        // The counter: a D, its straight side on the stem (4 units into it, as the icon cuts it).
        let cl = x0 + stem - 4, ct = capTop + bowlStroke, cb = bowlBottom - bowlStroke
        path.move(to: p(cl + counterCorner, ct))
        path.addLine(to: p(xc, ct))
        path.addArc(center: p(xc, cy), radius: ri * s, startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: false)
        path.addLine(to: p(cl + counterCorner, cb))
        path.addArc(tangent1End: p(cl, cb), tangent2End: p(cl, cb - counterCorner), radius: counterCorner * s)
        path.addLine(to: p(cl, ct + counterCorner))
        path.addArc(tangent1End: p(cl, ct), tangent2End: p(cl + counterCorner, ct), radius: counterCorner * s)
        path.closeSubpath()
        return path
    }

    /// A flap: the top (`upper`) or bottom half of module `index`, its outer corners round, its
    /// seam-side corners nearly square.
    static func flapPath(_ index: Int, upper: Bool, scale s: CGFloat, origin o: CGPoint = .zero) -> CGPath {
        let m = modules[index]
        let rect = upper
            ? CGRect(x: o.x + m.x0 * s, y: o.y, width: (m.x1 - m.x0) * s, height: seamTop * s)
            : CGRect(x: o.x + m.x0 * s, y: o.y + seamBottom * s, width: (m.x1 - m.x0) * s, height: (height - seamBottom) * s)
        let big = outerRadius * s, small = seamRadius * s
        return roundedRect(rect, topLeft: upper ? big : small, topRight: upper ? big : small,
                           bottomRight: upper ? small : big, bottomLeft: upper ? small : big)
    }

    /// The full stop's box on the board (`glyph`: kerned under the bowl, for the flapless mark).
    static func stopRect(scale s: CGFloat, origin o: CGPoint = .zero, glyph: Bool = false) -> CGRect {
        let cx = glyph ? glyphStopX : stopCentre.x
        return CGRect(x: o.x + (cx - stopRadius) * s, y: o.y + (stopCentre.y - stopRadius) * s,
                      width: stopRadius * 2 * s, height: stopRadius * 2 * s)
    }

    /// The axle caps' centres: both sides of each module, on the seam's centre line.
    static func pinCentres(scale s: CGFloat, origin o: CGPoint = .zero) -> [CGPoint] {
        let y = o.y + (seamTop + seamBottom) / 2 * s
        return modules.flatMap { m in [CGPoint(x: o.x + (m.x0 - pinOffset) * s, y: y), CGPoint(x: o.x + (m.x1 + pinOffset) * s, y: y)] }
    }

    /// The flapless glyph's box in design units: the P and its kerned stop.
    static var glyphBounds: CGRect {
        CGRect(x: letterX0, y: capTop, width: glyphStopX + stopRadius - letterX0, height: capBottom - capTop)
    }

    private static func roundedRect(_ r: CGRect, topLeft: CGFloat, topRight: CGFloat, bottomRight: CGFloat, bottomLeft: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: r.minX + topLeft, y: r.minY))
        path.addLine(to: CGPoint(x: r.maxX - topRight, y: r.minY))
        path.addArc(tangent1End: CGPoint(x: r.maxX, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.minY + topRight), radius: topRight)
        path.addLine(to: CGPoint(x: r.maxX, y: r.maxY - bottomRight))
        path.addArc(tangent1End: CGPoint(x: r.maxX, y: r.maxY), tangent2End: CGPoint(x: r.maxX - bottomRight, y: r.maxY), radius: bottomRight)
        path.addLine(to: CGPoint(x: r.minX + bottomLeft, y: r.maxY))
        path.addArc(tangent1End: CGPoint(x: r.minX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.maxY - bottomLeft), radius: bottomLeft)
        path.addLine(to: CGPoint(x: r.minX, y: r.minY + topLeft))
        path.addArc(tangent1End: CGPoint(x: r.minX, y: r.minY), tangent2End: CGPoint(x: r.minX + topLeft, y: r.minY), radius: topLeft)
        path.closeSubpath()
        return path
    }
}
