import SwiftUI

// Launch splash — a single-climax brand ident (~2s). The finished app icon lands from depth,
// the progress line sweeps and IGNITES the dot — the one signature beat: the scene's light
// floods up (after a subtle anticipation dip), the wordmark punches in on the same instant
// with a haptic — then the camera pushes forward THROUGH the icon (anchored on the ember
// dot), the ember blooming to carry the app out of warm light. No bounces, no particles;
// everything serves the ignition.
//
// All motion is pure math over elapsed real time, driven by TimelineView (120Hz on ProMotion
// via CADisableMinimumFrameDurationOnPhone). Base is true black for OLED — pixels stay off,
// seamless with the launch frame.
struct SplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onFinished: () -> Void

    /// Set on appear so a slow cold launch does not consume the timeline before the first frame.
    @State private var start: Date? = nil

    // The timeline (real seconds). IGNITE is when the sweep's leading edge crosses the dot
    // (inOutCubic over the sweep window hits dotX ≈ 0.557 at ~52% → ≈0.92s) — every climax
    // event (haptic, wordmark punch, light flood) is keyed to it.
    private static let ignite = 0.92
    /// Real time at which we hand off to the app — early in the push, so the RootView
    /// crossfade overlaps the zoom-through and the app emerges from inside the icon.
    private static let handoff = 1.68

    // Icon composition constants from the mock (fractions of the 1080×1920 frame / 640 comp).
    private static let compFraction  = 640.0 / 1080.0   // icon comp width ÷ screen width
    private static let compTop       = 560.0 / 1920.0
    // The bookmark's saved-place point, in composition space.
    private static let dotX          = 0.424
    private static let dotY = 0.297
    private static let wordmarkTop   = 1150.0 / 1920.0
    private static let taglineTop    = 1330.0 / 1920.0

    private static let ink = Color(hex: 0xF4EFE6)
    private static let accentDeep = Color(hex: 0xC9702E)

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation) { context in
                let tm = reduceMotion ? 1.4 : (start.map { context.date.timeIntervalSince($0) } ?? 0)
                stage(size: geo.size, tm: tm)
            }
        }
        .ignoresSafeArea()
        .onAppear { if start == nil { start = Date() } }
        .task {
            if !reduceMotion {
                // One soft tap exactly as the dot ignites — the signature beat, felt as
                // well as seen.
                try? await Task.sleep(for: .seconds(Self.ignite))
                FeedbackCoordinator.fire(.selection)
            }
            try? await Task.sleep(for: .seconds(reduceMotion ? 1.2 : Self.handoff - Self.ignite))
            onFinished()
        }
    }

    // MARK: - the scene at time `tm`

    private func stage(size: CGSize, tm: Double) -> some View {
        // arrive: the icon lands from depth — 1.16→1, blur clears, decisive not timid
        let ar = outQuint(seg(tm, 0, 0.55))
        // fill: the progress line sweeps left→right; the dot ignites as the sweep crosses it
        let fl = inOutCubic(seg(tm, 0.50, 1.30))
        let lit = seg(fl, Self.dotX - 0.02, Self.dotX + 0.12)
        // Anticipation: the stage light dips a breath before ignition, so the flood that
        // follows reads bigger — contrast bought just before it's spent.
        let dip = seg(tm, 0.70, 0.88) * (1 - lit)
        // IGNITION flood — the scene's light jumps on the beat, then settles high
        let flood = lit * (1 - 0.45 * seg(tm, 1.15, 1.60))
        // wordmark punches in ON the ignition beat; tagline follows a breath later
        let w = outQuint(seg(tm, Self.ignite, Self.ignite + 0.36))
        let tg = outQuint(seg(tm, 1.06, 1.46))
        // the dot's glow — blooms hard at ignition, settles, then breathes
        let breathe = seg(tm, 1.30, 1.60) * (0.5 + 0.5 * sin((tm - 1.30) * .pi / 1.1))
        let dotGlow = lit * (0.75 - 0.30 * seg(tm, 1.10, 1.50)) + breathe * 0.15
        let glowScale = 1 + 0.45 * lit * (1 - 0.75 * seg(tm, 1.10, 1.55))
        // one specular pass after ignition — light acknowledging the finished state
        let sheen = inOutQuint(seg(tm, 1.00, 1.70))
        // exit: the camera pushes forward — icon scales past the viewer, anchored on the
        // ember dot, so the app emerges from inside the ignition point
        let push = inCubic(seg(tm, 1.60, 2.10))
        let tgOut = outQuint(seg(tm, 1.55, 1.80))
        let wOut = outQuint(seg(tm, 1.60, 1.90))
        let iFade = seg(tm, 1.80, 2.08)

        let scale = (1.16 - 0.16 * ar) * (1 + 1.15 * push)
        let comp = size.width * Self.compFraction
        // The dot's fixed screen position — the push is anchored on it, so it never moves.
        let dotPoint = CGPoint(x: size.width / 2 + comp * (Self.dotX - 0.5),
                               y: size.height * Self.compTop + comp * Self.dotY)

        return ZStack(alignment: .topLeading) {
            background(arrived: ar, flood: flood, lit: lit, dip: dip)

            icon(comp: comp, ar: ar, fl: fl, push: push,
                 dotGlow: dotGlow, glowScale: glowScale, sheen: sheen)
                .frame(width: comp, height: comp)
                // Push scales around the dot itself — we zoom THROUGH the ember.
                .scaleEffect(scale, anchor: UnitPoint(x: Self.dotX, y: Self.dotY))
                .position(x: size.width / 2,
                          y: size.height * Self.compTop + comp / 2)
                .opacity(ar * (1 - iFade))

            // Shockwave off the ignition — a thin ring expanding from the dot, gone in
            // half a second. The beat's energy leaving the point it landed on.
            if tm > Self.ignite, tm < Self.ignite + 0.55 {
                let ring = outCubic(seg(tm, Self.ignite, Self.ignite + 0.55))
                Circle()
                    .stroke(Color(hex: 0xF6BD7D).opacity((1 - ring) * 0.45),
                            lineWidth: 1.5 + 5 * (1 - ring))
                    .frame(width: comp * 0.12, height: comp * 0.12)
                    .scaleEffect(0.4 + 6.5 * ring)
                    .position(dotPoint)
                    .blur(radius: 1 + 3 * ring)
                    .allowsHitTesting(false)
            }

            // The ember blooms during the push — a warm light expanding from the dot the
            // camera is diving into, so the app emerges out of the ignition's glow.
            Circle()
                .fill(RadialGradient(colors: [Color(hex: 0xF6BD7D).opacity(0.55),
                                              ThemeColor.accent.opacity(0.18),
                                              .clear],
                                     center: .center, startRadius: 0, endRadius: comp * 0.75))
                .frame(width: comp * 1.5, height: comp * 1.5)
                .scaleEffect(0.25 + 2.6 * push)
                .position(dotPoint)
                .opacity(sin(min(push * 1.25, 1) * .pi) * 0.6)
                .allowsHitTesting(false)

            wordmark(size: size, w: w)
                .scaleEffect(1 + 0.30 * outQuint(seg(tm, 1.60, 2.00)),
                             anchor: UnitPoint(x: 0.5, y: Self.wordmarkTop))
                .blur(radius: 4 * wOut)
                .opacity(1 - wOut)
            tagline(size: size, tg: tg)
                .scaleEffect(1 + 0.22 * outQuint(seg(tm, 1.55, 1.95)),
                             anchor: UnitPoint(x: 0.5, y: Self.taglineTop))
                .opacity(1 - tgOut)

            // Ignition flash — a warm full-screen lift that spikes on the beat and decays.
            Color(hex: 0xF6BD7D)
                .opacity(0.07 * lit * (1 - seg(tm, Self.ignite + 0.05, 1.35)))
                .allowsHitTesting(false)
        }
        .frame(width: size.width, height: size.height)
        // Film grain over the whole ident, quantized to 24fps — the cinema texture that
        // separates a graded piece of film from a UI screen. Deliberately near-invisible.
        .colorEffect(ShaderLibrary.filmGrain(.float(floor(tm * 24) / 24), .float(0.035)))
    }

    // Warm gradient breathes in over the true-black launch frame (OLED: pixels stay off
    // until the scene lights them). The ignition floods the stage light on the beat.
    private func background(arrived: Double, flood: Double, lit: Double, dip: Double) -> some View {
        ZStack {
            Color.black
            LinearGradient(stops: [
                .init(color: Color(hex: 0x2A1F14), location: 0),
                .init(color: Color(hex: 0x1C1510), location: 0.22),
                .init(color: Color(hex: 0x12100C), location: 0.45),
                .init(color: Color(hex: 0x0C0B09), location: 0.70),
                .init(color: .black, location: 1),
            ], startPoint: .top, endPoint: .bottom)
            .opacity(arrived * 0.9)
            // The stage light behind the composition — dim before ignition (dipping further
            // in the anticipation beat), flooding after.
            RadialGradient(colors: [Color(hex: 0x4A3B24).opacity(0.16 - 0.07 * dip + 0.34 * flood), .clear],
                           center: UnitPoint(x: 0.5, y: 0.42),
                           startRadius: 0, endRadius: 420 + 140 * lit)
                .opacity(arrived)
            // Vignette pulling the edges down.
            RadialGradient(colors: [.clear, .black.opacity(0.4)],
                           center: .center, startRadius: 0, endRadius: max(1, 700 * arrived))
        }
    }

    private func icon(comp: CGFloat, ar: Double, fl: Double, push: Double,
                      dotGlow: Double, glowScale: Double,
                      sheen: Double) -> some View {
        let markWidth = comp * 0.49
        return ZStack(alignment: .topLeading) {
            // The mark lands as a physical ribbon, then the camera pushes through its saved point.
            Ellipse()
                .fill(Color.black.opacity(0.25 + 0.30 * ar))
                .frame(width: markWidth * (1.25 - 0.15 * ar), height: markWidth * 0.16)
                .blur(radius: comp * (0.065 - 0.025 * ar))
                .offset(x: comp * 0.37, y: comp * 0.86)

            PreviouslyMark(width: markWidth, progress: CGFloat(fl))
                .shadow(color: .black.opacity(0.5), radius: comp * 0.08, y: comp * 0.05)
                .position(x: comp / 2, y: comp * 0.48)

            // The dot's glow — blooms hard as the traveling light lands, settles, breathes.
            Circle()
                .fill(RadialGradient(colors: [Color(hex: 0xF6BD7D).opacity(0.85),
                                              ThemeColor.accent.opacity(0.2),
                                              .clear],
                                     center: .center, startRadius: 0, endRadius: comp * 0.11))
                .frame(width: comp * 0.22, height: comp * 0.22)
                .scaleEffect(glowScale)
                .position(x: comp * Self.dotX, y: comp * Self.dotY)
                .opacity(dotGlow)

            // One specular pass across the ribbon after ignition.
            if sheen > 0, sheen < 1 {
                Color.clear
                    .frame(width: markWidth, height: markWidth * 1.58)
                    .overlay {
                        Rectangle()
                            // Falls off across the band's width, so the rotated band has
                            // no hard edge — just a soft passing light.
                            .fill(LinearGradient(colors: [.clear,
                                                          Color.white.opacity(0.09),
                                                          .clear],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: markWidth * 0.55, height: markWidth * 1.8)
                            .rotationEffect(.degrees(24))
                            .offset(x: markWidth * (-0.9 + 1.8 * sheen))
                            .opacity(sin(sheen * .pi))
                    }
                    .clipShape(BookmarkSplashShape())
                    .position(x: comp / 2, y: comp * 0.48)
                    .allowsHitTesting(false)
            }
        }
        .compositingGroup()
        // The camera push's radial zoom-smear + chromatic fringe, centered on the ember
        // (applied pre-scale, so the smear scales with the dive).
        .layerEffect(ShaderLibrary.emberZoom(.float2(comp * Self.dotX, comp * Self.dotY),
                                             .float(push)),
                     maxSampleOffset: CGSize(width: 140, height: 140),
                     isEnabled: push > 0)
        .opacity(ar)
        .blur(radius: ar < 0.99 ? (1 - ar) * 6 : 0)
    }

    private func wordmark(size: CGSize, w: Double) -> some View {
        let fs = size.width * (118.0 / 1080.0)
        return (
            Text("Previously\(Text(".").foregroundStyle(LinearGradient(colors: [ThemeColor.accent, Self.accentDeep], startPoint: .topLeading, endPoint: .bottomTrailing)))")
                .foregroundStyle(Self.ink)
        )
        .font(AppFont.font(size: fs, weight: .bold))
        // Tracking-in: letters start airy and settle tight as the unit punches in.
        .kerning(fs * (-0.03 * w + 0.025 * (1 - w)))
        .frame(maxWidth: .infinity)
        // The punch: arrives slightly large and settles — landing ON the ignition beat.
        .scaleEffect(1.06 - 0.06 * w)
        .position(x: size.width / 2, y: size.height * Self.wordmarkTop + fs / 2)
        .offset(y: (1 - w) * 14)
        .opacity(w)
        .blur(radius: w < 0.99 ? (1 - w) * 3 : 0)
    }

    private func tagline(size: CGSize, tg: Double) -> some View {
        let fs = size.width * (25.0 / 1080.0)
        // Completes the wordmark's sentence — the "Previously on…" recap card, made literal.
        // Fixed-art splash caption (the mock's ui-monospace) — deliberately not Dynamic Type.
        return Text("ON EVERYTHING YOU WATCH")
            .font(.system(size: fs, weight: .medium, design: .monospaced))
            .kerning(fs * 0.34)
            .foregroundStyle(ThemeColor.accent)
            .frame(maxWidth: .infinity)
            .position(x: size.width / 2 + fs * 0.17, y: size.height * Self.taglineTop + fs / 2)
            .offset(y: (1 - tg) * 7)
            .opacity(tg * 0.8)
    }

    // MARK: - easing

    private func seg(_ p: Double, _ a: Double, _ b: Double) -> Double {
        min(max((p - a) / (b - a), 0), 1)
    }
    private func outQuint(_ t: Double) -> Double { 1 - pow(1 - t, 5) }
    private func inOutQuint(_ t: Double) -> Double {
        t < 0.5 ? 16 * t * t * t * t * t : 1 - pow(-2 * t + 2, 5) / 2
    }
    private func inOutCubic(_ t: Double) -> Double {
        t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }
    private func inCubic(_ t: Double) -> Double { t * t * t }
    private func outCubic(_ t: Double) -> Double { 1 - pow(1 - t, 3) }
}

/// Splash-local copy of the mark silhouette, used only to clip its travelling highlight.
private struct BookmarkSplashShape: Shape {
    func path(in rect: CGRect) -> Path {
        let radius = rect.width * 0.17
        let notchApex = rect.height * 0.76
        let edgeBottom = rect.height * 0.96
        var path = Path()
        path.move(to: CGPoint(x: radius, y: 0))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: 0))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: radius), control: CGPoint(x: rect.maxX, y: 0))
        path.addLine(to: CGPoint(x: rect.maxX, y: edgeBottom))
        path.addLine(to: CGPoint(x: rect.midX, y: notchApex))
        path.addLine(to: CGPoint(x: 0, y: edgeBottom))
        path.addLine(to: CGPoint(x: 0, y: radius))
        path.addQuadCurve(to: CGPoint(x: radius, y: 0), control: .zero)
        path.closeSubpath()
        return path
    }
}
