import SwiftUI

// The Previously. identity. Since 26 Sep it is the Split-Flap mark — "P." on a departures board
// (`FlapGeometry`; the icon is design/app-icon-splitflap) — and every drawing of it in the app goes
// through `PreviouslyMark` at the foot of this file: the gate, the wordmark, the account disc and the
// feed's header, so the tile on the home screen, the board the launch flips and the mark beside the
// name are one thing.
//
// The ribbon above it (`MarkGeometry`, `RibbonShape`, `RibbonFill`, `PeriodBead`) is the RETIRED
// mark (4–25 Sep, design/app-icon-v2/glass/x9-final.icon). It stays only for the launch films kept
// behind `-splashDirection` for comparison and the old ident; nothing a person sees draws it.

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

    /// How much of the flat mark's shade the lit mark keeps.
    private var shade: Double { 1 - 0.55 * material }

    var body: some View {
        RibbonShape()
            .fill(LinearGradient(stops: [
                .init(color: MarkGeometry.rampTop, location: 0),
                .init(color: MarkGeometry.rampMid, location: 0.5),
                .init(color: MarkGeometry.rampFoot, location: 1),
            ], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                // Lit (the launch, the gate), the shade stops lift: the mark is the subject there,
                // lit like art, and at full shade it landed 17–26 % darker than the icon the user
                // had just tapped — ochre and rust against gold and coral (review, 25 Sep).
                RibbonShape().fill(LinearGradient(stops: [
                    .init(color: .white.opacity(0.09), location: 0),
                    .init(color: .clear, location: 0.35),
                    .init(color: .black.opacity(0.22 * shade), location: 1),
                ], startPoint: .top, endPoint: .bottom))
            }
            .overlay {
                RibbonShape().fill(LinearGradient(stops: [
                    .init(color: .black.opacity(0.08 * shade), location: 0),
                    .init(color: .white.opacity(0.09), location: 0.35),
                    .init(color: .black.opacity(0.18 * shade), location: 1),
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

// MARK: - The Split-Flap mark (26 Sep)

/// The identity: "P." on a departures board (`FlapGeometry`, the icon's own numbers).
///
/// `.board` is the icon's two flap modules — the launch, the gate, the colophon. `.glyph` is the
/// letter alone, its seam kept, the full stop kerned under its bowl — where the mark stands at
/// twenty-odd points (the feed's header, the account disc): at that size the flaps are noise and
/// the cut letter is the brand. `width` is the board's (the axle pins overhang it by a few points,
/// outside the layout) or the glyph's. `lit:` is the board at scale where it is the subject (the
/// launch, the gate): light on the flaps' crowns and edges, a soft shadow under them. Drawn in one
/// `Canvas` — static, so it is drawn once.
struct PreviouslyMark: View {
    enum Style { case board, glyph }

    let width: CGFloat
    var style: Style = .board
    var lit = false
    /// The glyph's letter (the feed's header draws it in its own ink). The board's is the icon's.
    var ink: Color = FlapGeometry.ink

    var body: some View {
        switch style {
        case .board: board
        case .glyph: glyph
        }
    }

    private var board: some View {
        let s = width / FlapGeometry.span
        let h = width * FlapGeometry.aspect
        let pad = max((FlapGeometry.pinOffset + FlapGeometry.pinRadius) * s, lit ? width * 0.14 : 0)
        return Canvas { ctx, _ in
            let o = CGPoint(x: pad, y: pad)
            func y(_ units: CGFloat) -> CGFloat { o.y + units * s }
            let flaps = (0..<FlapGeometry.modules.count).map {
                (top: Path(FlapGeometry.flapPath($0, upper: true, scale: s, origin: o)),
                 bottom: Path(FlapGeometry.flapPath($0, upper: false, scale: s, origin: o)))
            }
            if lit {
                // The shadow the board casts, from the flaps' own shapes (the gaps between them stay
                // clear); a filter inside a static canvas is drawn once.
                ctx.drawLayer { layer in
                    layer.addFilter(.shadow(color: .black.opacity(0.55), radius: width * 0.05, x: 0, y: width * 0.03))
                    for f in flaps { layer.fill(f.top, with: .color(.black)); layer.fill(f.bottom, with: .color(.black)) }
                }
            }
            for f in flaps {
                ctx.fill(f.top, with: .linearGradient(Gradient(colors: [FlapGeometry.flapTopHigh, FlapGeometry.flapTopLow]),
                                                      startPoint: CGPoint(x: 0, y: y(0)), endPoint: CGPoint(x: 0, y: y(FlapGeometry.seamTop))))
                ctx.fill(f.top, with: .linearGradient(Gradient(colors: [.white.opacity(lit ? 0.09 : 0.06), .clear]),
                                                      startPoint: CGPoint(x: 0, y: y(0)), endPoint: CGPoint(x: 0, y: y(44))))
                ctx.fill(f.bottom, with: .linearGradient(Gradient(colors: [FlapGeometry.flapBottomHigh, FlapGeometry.flapBottomLow]),
                                                         startPoint: CGPoint(x: 0, y: y(FlapGeometry.seamBottom)),
                                                         endPoint: CGPoint(x: 0, y: y(FlapGeometry.height))))
                // The top flap's shadow on the lower, at the seam.
                ctx.fill(f.bottom, with: .linearGradient(Gradient(colors: [.black.opacity(0.32), .clear]),
                                                         startPoint: CGPoint(x: 0, y: y(FlapGeometry.seamBottom)),
                                                         endPoint: CGPoint(x: 0, y: y(FlapGeometry.seamBottom + 56))))
                if lit {
                    ctx.stroke(f.top, with: .linearGradient(Gradient(colors: [.white.opacity(0.16), .white.opacity(0.02)]),
                                                            startPoint: CGPoint(x: 0, y: y(0)), endPoint: CGPoint(x: 0, y: y(FlapGeometry.seamTop))),
                               lineWidth: max(0.5, s * 2))
                }
            }
            var letter = ctx
            letter.clip(to: Path { p in
                p.addRect(CGRect(x: 0, y: 0, width: width + pad * 2, height: y(FlapGeometry.seamTop)))
                p.addRect(CGRect(x: 0, y: y(FlapGeometry.seamBottom), width: width + pad * 2, height: h + pad))
            })
            letter.fill(Path(FlapGeometry.letterPath(scale: s, origin: o)), with: .color(FlapGeometry.ink), style: FillStyle(eoFill: true))
            ctx.fill(Path(ellipseIn: FlapGeometry.stopRect(scale: s, origin: o)), with: .color(FlapGeometry.stopInk))
            let r = FlapGeometry.pinRadius * s
            for c in FlapGeometry.pinCentres(scale: s, origin: o) {
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(FlapGeometry.pin))
            }
        }
        .frame(width: width + pad * 2, height: h + pad * 2)
        .padding(-pad)
        .accessibilityHidden(true)
    }

    private var glyph: some View {
        let b = FlapGeometry.glyphBounds
        let s = width / b.width
        let h = b.height * s
        return Canvas { ctx, size in
            let o = CGPoint(x: -b.minX * s, y: -b.minY * s)
            let seamTop = o.y + FlapGeometry.seamTop * s
            // At least a point of seam: the board's 12 units are a hairline at 20 pt, and a seam
            // that vanishes leaves a plain P.
            let seamBottom = max(o.y + FlapGeometry.seamBottom * s, seamTop + 1)
            var letter = ctx
            letter.clip(to: Path { p in
                p.addRect(CGRect(x: 0, y: 0, width: size.width, height: seamTop))
                p.addRect(CGRect(x: 0, y: seamBottom, width: size.width, height: size.height - seamBottom))
            })
            letter.fill(Path(FlapGeometry.letterPath(scale: s, origin: o)), with: .color(ink), style: FillStyle(eoFill: true))
            ctx.fill(Path(ellipseIn: FlapGeometry.stopRect(scale: s, origin: o, glyph: true)), with: .color(FlapGeometry.stopInk))
        }
        .frame(width: width, height: h)
        .accessibilityHidden(true)
    }
}
