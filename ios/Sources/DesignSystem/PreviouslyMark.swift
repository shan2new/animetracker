import SwiftUI

// The Previously. identity, drawn from the app icon's own geometry
// (design/app-icon-v2/glass/x9-final.icon): a ribbon hanging by its top edge, gold at the top-left
// falling to coral at the tails, and — where the composition calls for it — the coral full stop
// beside the tails. Every drawing of the mark in the app goes through this file: the launch
// ident, the wordmark, the sign-in gate and the account disc all draw THIS ribbon, so the tile on
// the home screen, the object that arrives at launch and the mark beside the name are one thing.
//
// The rules the icon settled (4 Sep) hold here: flat, stroke-built, one hue-shifting ramp, no
// sphere, no glow. Where the mark is the subject (the launch, the gate) it is `lit:` — the icon's
// own material at scale: a hairline rim where the light catches the edge, the volume of the
// ramp, and the coloured shadow the ribbon casts on the canvas. Beside a name it is flat.

/// The mark's anatomy in fractions of the ribbon's width, so one number sizes every use of it.
enum MarkGeometry {
    /// Height ÷ width. The icon shows 800 px of its 376-px-wide ribbon above the tile's foot.
    static let aspect: CGFloat = 800.0 / 376.0
    /// The notch, up from the tails.
    static let notchDepth: CGFloat = 0.40
    static let tipRadius: CGFloat = 0.045
    static let apexRadius: CGFloat = 0.035
    /// The icon's ribbon runs off the tile's top edge. Standing alone it needs a finished top: the
    /// same small radius as its tips, so it reads as a cut length of ribbon, never a plaque.
    static let topRadius: CGFloat = 0.06
    /// The full stop: a 90-px bead in the icon, its foot flush with the tails, 38 px clear of the edge.
    static let periodDiameter: CGFloat = 180.0 / 376.0
    static let periodGap: CGFloat = 38.0 / 376.0
    /// The bead's centre from the ribbon's leading edge, in widths: past the trailing edge, the
    /// gap, and its own radius (the icon: x0 + 376 + 38 + 90).
    static var periodCenterX: CGFloat { 1 + periodGap + periodDiameter / 2 }
    /// The bead's centre from the ribbon's top, in widths.
    static var periodCenterY: CGFloat { aspect - periodDiameter / 2 }
    /// The composition's width (ribbon + gap + bead), in widths.
    static var lockupWidth: CGFloat { 1 + periodGap + periodDiameter }

    // The ramp: the icon's, exactly.
    static let rampTop = Color(hex: 0xFFBB48)
    static let rampMid = Color(hex: 0xF28C3C)
    static let rampFoot = Color(hex: 0xDE4A3C)
    /// The icon's coloured shadow: the warm light the ribbon leaves on the tile beneath it.
    static let ribbonShadow = Color(hex: 0xE8702E)
}

/// The ribbon's outline: a strip with a notch cut up into its foot, every corner a tangent arc —
/// the icon's polygon (design/app-icon-v2/ribbon.py `ribbon_pts` + `rounded`) as a `Shape`.
struct RibbonShape: InsettableShape {
    var inset: CGFloat = 0

    func inset(by amount: CGFloat) -> RibbonShape {
        var copy = self
        copy.inset += amount
        return copy
    }

    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: inset, dy: inset)
        let w = rect.width
        let tl = CGPoint(x: rect.minX, y: rect.minY)
        let tr = CGPoint(x: rect.maxX, y: rect.minY)
        let br = CGPoint(x: rect.maxX, y: rect.maxY)
        let apex = CGPoint(x: rect.midX, y: rect.maxY - MarkGeometry.notchDepth * w)
        let bl = CGPoint(x: rect.minX, y: rect.maxY)
        let corners: [(CGPoint, CGPoint, CGFloat)] = [
            (tr, br, MarkGeometry.topRadius * w),
            (br, apex, MarkGeometry.tipRadius * w),
            (apex, bl, MarkGeometry.apexRadius * w),
            (bl, tl, MarkGeometry.tipRadius * w),
            (tl, tr, MarkGeometry.topRadius * w),
        ]
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        for (vertex, next, radius) in corners {
            path.addArc(tangent1End: vertex, tangent2End: next, radius: radius)
        }
        path.closeSubpath()
        return path
    }
}

/// The shaded ribbon. The ramp runs the icon's diagonal; two quiet overlays give it the icon's
/// volume (lit at the head, shaded at the foot) and its curl (a cylinder's light across the width).
/// `material` (0…1) adds the hairline rim where light catches the top-left edges, and
/// `castShadow` (0…1) the coloured shadow on the ground — the icon's material at scale, for the
/// two places the mark is the subject; the launch fades both out as the ribbon docks. The shadow
/// is a blurred layer BENEATH the fill rather than a `.shadow` filter on it: a filter re-renders
/// with every change to the fill (the light pass, the flight's every frame), which on the
/// simulator's software path is what made the flight drop frames; a layer whose inputs do not
/// change is drawn once. `width` sizes the material; it is not read for layout.
struct RibbonFill: View {
    var material: Double = 0
    var castShadow: Double = 0
    var width: CGFloat = 0
    /// A single pass of light across the ribbon, 0 → 1 from its head to its foot, or `nil` for
    /// none: the icon's specular, once, at scale.
    var sweep: Double? = nil
    /// How much of the ribbon exists, head to foot (0 → 1). The launch draws it in behind a
    /// travelling light; everywhere else it is whole.
    var reveal: Double = 1
    /// Where that drawing light is along the ribbon (0 head → 1 foot), or `nil` for none.
    var light: Double? = nil

    var body: some View {
        RibbonShape()
            .fill(LinearGradient(stops: [
                .init(color: MarkGeometry.rampTop, location: 0),
                .init(color: MarkGeometry.rampMid, location: 0.5),
                .init(color: MarkGeometry.rampFoot, location: 1),
            ], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                RibbonShape().fill(LinearGradient(stops: [
                    .init(color: .white.opacity(0.09), location: 0),
                    .init(color: .clear, location: 0.35),
                    .init(color: .black.opacity(0.22), location: 1),
                ], startPoint: .top, endPoint: .bottom))
            }
            .overlay {
                RibbonShape().fill(LinearGradient(stops: [
                    .init(color: .black.opacity(0.08), location: 0),
                    .init(color: .white.opacity(0.09), location: 0.35),
                    .init(color: .black.opacity(0.18), location: 1),
                ], startPoint: .leading, endPoint: .trailing))
            }
            .overlay {
                // The drawing light: a soft band at the leading edge of the reveal.
                if let light {
                    GeometryReader { geo in
                        let h = geo.size.height
                        Rectangle()
                            .fill(LinearGradient(colors: [.clear, .white.opacity(0.34), .clear],
                                                 startPoint: .top, endPoint: .bottom))
                            .frame(width: geo.size.width * 1.4, height: geo.size.width * 0.34)
                            .position(x: geo.size.width / 2, y: h * light)
                            .opacity(sin(light * .pi) * 0.85 + 0.15)
                    }
                    .clipShape(RibbonShape())
                    .allowsHitTesting(false)
                }
            }
            .overlay {
                if let sweep, sweep > 0, sweep < 1 {
                    GeometryReader { geo in
                        let w = geo.size.width
                        let h = geo.size.height
                        Rectangle()
                            .fill(LinearGradient(colors: [.clear, .white.opacity(0.16), .clear],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: w * 0.6, height: h * 2.4)
                            .rotationEffect(.degrees(-24))
                            .position(x: w * (-0.7 + 2.4 * sweep), y: h * (0.15 + 0.7 * sweep))
                            .opacity(sin(sweep * .pi) * material)
                    }
                    .clipShape(RibbonShape())
                    .allowsHitTesting(false)
                }
            }
            .overlay {
                if material > 0 {
                    // The edge: light catching the near side, the far side falling into shade.
                    RibbonShape().strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.34), .white.opacity(0.06), .clear],
                                       startPoint: .topLeading, endPoint: .bottom),
                        lineWidth: max(0.8, width * 0.012))
                    .opacity(material)
                    RibbonShape().strokeBorder(
                        LinearGradient(colors: [.clear, .black.opacity(0.22)],
                                       startPoint: .top, endPoint: .bottomTrailing),
                        lineWidth: max(0.8, width * 0.010))
                    .opacity(material)
                }
            }
            // Drawn head to foot behind a feathered edge — light, not a wipe. Not a mask: a mask
            // re-renders the masked group on every frame it moves. This is a canvas-coloured
            // cover, one flat layer, clipped to the ribbon and sliding off its foot; the launch
            // draws on the canvas, so the cover is invisible.
            .overlay {
                if reveal < 1 {
                    GeometryReader { geo in
                        let h = geo.size.height
                        let edge = h * min(max(reveal, 0), 1)
                        let feather = geo.size.width * 0.22
                        LinearGradient(colors: [ThemeColor.canvas.opacity(0), ThemeColor.canvas],
                                       startPoint: .top, endPoint: .bottom)
                            .frame(height: feather)
                            .position(x: geo.size.width / 2, y: edge - feather * 0.4 + feather / 2)
                        ThemeColor.canvas
                            .frame(height: max(0, h - (edge - feather * 0.4 + feather)) + h)
                            .position(x: geo.size.width / 2,
                                      y: edge - feather * 0.4 + feather + (max(0, h - (edge - feather * 0.4 + feather)) + h) / 2)
                    }
                    .clipShape(RibbonShape())
                    .allowsHitTesting(false)
                }
            }
            .background {
                if castShadow > 0 {
                    // Rasterised ONCE (`drawingGroup`), then faded by layer opacity: a blur
                    // left as a layer filter is re-run by the render server on every frame the
                    // light travels, which is every frame of the ident.
                    //
                    // The padding pair is not decoration: `drawingGroup` rasterises the view's
                    // BOUNDS, so a blur is cut off square at them. Without room to spread, the
                    // pool of light the ribbon casts became a RECTANGLE of lifted canvas with
                    // visible edges around the mark (7 Sep, seen at full resolution on the
                    // launch). The padding grows the buffer; the negative padding hands the
                    // original frame back to the layout.
                    let spread = width * 0.16
                    RibbonShape()
                        .fill(MarkGeometry.ribbonShadow.opacity(0.34))
                        .blur(radius: spread)
                        .padding(spread * 3)
                        .drawingGroup()
                        .padding(-spread * 3)
                        .offset(y: width * 0.07)
                        .opacity(castShadow)
                        .allowsHitTesting(false)
                }
            }
    }
}

/// The full stop: the icon's coral bead, catching the same light from the upper left.
struct PeriodBead: View {
    let diameter: CGFloat
    var lit = false

    var body: some View {
        Circle()
            .fill(ThemeColor.brandPeriod)
            .overlay {
                Circle().fill(RadialGradient(colors: [.white.opacity(0.18), .clear],
                                             center: UnitPoint(x: 0.36, y: 0.32),
                                             startRadius: 0, endRadius: diameter * 0.62))
            }
            .overlay {
                if lit {
                    Circle().strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.26), .clear],
                                       startPoint: .topLeading, endPoint: .bottom),
                        lineWidth: max(0.8, diameter * 0.025))
                }
            }
            .background {
                if lit {
                    // Padded before the rasterisation, for the reason `RibbonFill`'s shadow is:
                    // clipped to the bead's own bounds this glow drew a lit SQUARE behind the
                    // brand's full stop.
                    let spread = diameter * 0.22
                    Circle()
                        .fill(ThemeColor.brandPeriod.opacity(0.38))
                        .blur(radius: spread)
                        .padding(spread * 3)
                        .drawingGroup()
                        .padding(-spread * 3)
                        .offset(y: diameter * 0.10)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: diameter, height: diameter)
    }
}

/// The identity: the ribbon, and with `period:` the icon's composition of ribbon and full stop.
///
/// `lit:` is the icon's material at scale (rim, coloured shadow) — for the launch and the sign-in
/// gate, where the mark is the subject; beside a name the ribbon is flat.
struct PreviouslyMark: View {
    let width: CGFloat
    var period = false
    var lit = false

    var body: some View {
        let height = width * MarkGeometry.aspect
        let bead = width * MarkGeometry.periodDiameter
        ZStack(alignment: .topLeading) {
            RibbonFill(material: lit ? 1 : 0, castShadow: lit ? 1 : 0, width: width)
                .frame(width: width, height: height)
            if period {
                PeriodBead(diameter: bead, lit: lit)
                    .position(x: width * MarkGeometry.periodCenterX, y: width * MarkGeometry.periodCenterY)
            }
        }
        .frame(width: period ? width * MarkGeometry.lockupWidth : width, height: height, alignment: .topLeading)
        .accessibilityHidden(true)
    }
}
