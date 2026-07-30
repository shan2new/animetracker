import SwiftUI

// Launch splash — the native build of the Claude Design exploration (explorations/Splash Screen):
// the finished app icon resolves from black, the progress line sweeps across and lights the dot,
// then the whole composition lifts as the wordmark + tagline fade up. One signature beat; no
// bounces, no particles.
//
// The mock's 6.2s timeline is video-exploration pacing — every phase and curve is kept, but the
// clock is compressed (`timeScale`) so the app isn't sitting on a splash. All motion is pure
// math over elapsed time (a straight port of the mock's easing), driven by TimelineView.
struct SplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onFinished: () -> Void

    @State private var start = Date()

    // Mock-seconds → real seconds. Phases below keep the mock's numbers; this is the one knob.
    private static let timeScale = 0.55
    /// Real time at which we hand off to the app — mid-outro in mock time, so the RootView
    /// crossfade overlaps the icon's staged exit and the app emerges under it.
    private static let handoff = 5.5 * timeScale

    // Icon composition constants from the mock (fractions of the 1080×1920 frame / 640 comp).
    private static let compFraction  = 640.0 / 1080.0   // icon comp width ÷ screen width
    private static let compTop       = 560.0 / 1920.0
    private static let dotX          = 0.557            // progress dot, in comp space
    private static let dotY = 0.69
    private static let wordmarkTop   = 1150.0 / 1920.0
    private static let taglineTop    = 1330.0 / 1920.0

    private static let ink = Color(hex: 0xF4EFE6)
    private static let accentDeep = Color(hex: 0xC9702E)

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation) { context in
                let tm = reduceMotion ? 6.0 : context.date.timeIntervalSince(start) / Self.timeScale
                stage(size: geo.size, tm: tm)
            }
        }
        .ignoresSafeArea()
        .task {
            if !reduceMotion {
                // One soft tap exactly as the progress dot ignites — the signature beat,
                // felt as well as seen. (≈ the sweep reaching the dot in mock time.)
                try? await Task.sleep(for: .seconds(2.1 * Self.timeScale))
                Haptics.impact(.soft)
            }
            try? await Task.sleep(for: .seconds(reduceMotion ? 1.2
                                                : Self.handoff - 2.1 * Self.timeScale))
            onFinished()
        }
    }

    // MARK: - the scene at mock-time `tm`

    private func stage(size: CGSize, tm: Double) -> some View {
        // arrive: the finished icon resolves from black — fade, 0.95→1, blur clears
        let ar = outQuint(seg(tm, 0, 1.5))
        // fill: the progress line sweeps left→right; the dot lights as the sweep reaches it
        let fl = inOutCubic(seg(tm, 1.3, 2.7))
        let lit = seg(fl, Self.dotX - 0.02, Self.dotX + 0.12)
        // lockup: slow lift; wordmark and tagline fade up as single units
        let lk = seg(tm, 2.7, 4.4)
        let m = inOutQuint(seg(lk, 0, 0.62))
        let w = outQuint(seg(lk, 0.3, 0.85))
        let tg = outQuint(seg(lk, 0.5, 1))
        // hold: imperceptible drift, faint breath in the dot's glow
        let drift = seg(tm, 3.6, 6.2)
        let breathe = seg(tm, 4.4, 5.2) * (0.5 + 0.5 * sin((tm - 4.4) * .pi / 1.6))
        let dotGlow = lit * (0.55 - 0.25 * seg(tm, 2.9, 3.6)) + breathe * 0.18
        let scale = (0.95 + 0.05 * ar) * (1 - 0.12 * m) * (1 + 0.012 * inOutQuint(drift))
        // One specular pass over the tile once the line has completed — light acknowledging
        // the finished state. Runs during the lift, like a rotation catching the light.
        let sheen = inOutQuint(seg(tm, 2.9, 4.1))
        // The glow blooms larger at ignition, then settles to the dot's resting size.
        let glowScale = 1 + 0.22 * lit * (1 - seg(tm, 2.9, 3.6))
        // Staged outro — elements leave in reverse order of arrival, continuing upward:
        // tagline first, then the wordmark, then the icon. The RootView crossfade overlaps
        // the icon's exit, so the app emerges while the last element is still leaving.
        let tgOut = outQuint(seg(tm, 5.0, 5.5))
        let wOut = outQuint(seg(tm, 5.15, 5.7))
        let iOut = inOutQuint(seg(tm, 5.3, 5.95))

        let comp = size.width * Self.compFraction

        return ZStack(alignment: .topLeading) {
            background(arrived: ar, lit: lit)

            icon(comp: comp, ar: ar, fl: fl, m: m, scale: scale * (1 + 0.025 * iOut),
                 dotGlow: dotGlow, glowScale: glowScale, sheen: sheen)
                .frame(width: comp, height: comp)
                .position(x: size.width / 2,
                          y: size.height * Self.compTop + comp / 2
                             - comp * (140.0 / 640.0) * m - 18 * iOut)
                .opacity(1 - iOut)

            wordmark(size: size, w: w)
                .offset(y: -10 * wOut)
                .opacity(1 - wOut)
            tagline(size: size, tg: tg)
                .offset(y: -8 * tgOut)
                .opacity(1 - tgOut)
        }
        .frame(width: size.width, height: size.height)
    }

    // Warm gradient breathes in over the launch-screen black so the first frame is seamless.
    // The dot's ignition lifts the stage light a touch — the scene responds to the beat.
    private func background(arrived: Double, lit: Double) -> some View {
        ZStack {
            Color(hex: 0x0B0B0E)
            LinearGradient(stops: [
                .init(color: Color(hex: 0x2A1F14), location: 0),
                .init(color: Color(hex: 0x1C1510), location: 0.22),
                .init(color: Color(hex: 0x12100C), location: 0.45),
                .init(color: Color(hex: 0x0C0B09), location: 0.70),
                .init(color: Color(hex: 0x0A0908), location: 1),
            ], startPoint: .top, endPoint: .bottom)
            .opacity(arrived)
            // A faint warm stage light behind the composition, brightening as the dot lights.
            RadialGradient(colors: [Color(hex: 0x4A3B24).opacity(0.22 + 0.14 * lit), .clear],
                           center: UnitPoint(x: 0.5, y: 0.42),
                           startRadius: 0, endRadius: 420)
                .opacity(arrived)
            // Vignette pulling the edges down.
            RadialGradient(colors: [.clear, .black.opacity(0.4)],
                           center: .center, startRadius: 0, endRadius: max(1, 700 * arrived))
        }
    }

    private func icon(comp: CGFloat, ar: Double, fl: Double, m: Double,
                      scale: Double, dotGlow: Double, glowScale: Double,
                      sheen: Double) -> some View {
        let radius = comp * 0.225
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return ZStack(alignment: .topLeading) {
            // Ground shadow beneath the tile.
            Ellipse()
                .fill(Color.black.opacity(0.55))
                .frame(width: comp * 0.82, height: comp * 0.11)
                .blur(radius: comp * 0.04)
                .offset(x: comp * 0.09, y: comp * 0.97)

            // Tile with a top-lit rim instead of a flat border — reads as a physical object.
            shape.fill(Color.black)
                .overlay(shape.stroke(
                    LinearGradient(colors: [Color(hex: 0xF5F0E6).opacity(0.22),
                                            Color(hex: 0xF5F0E6).opacity(0.04)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1))
                .shadow(color: .black.opacity(0.55), radius: comp * 0.11, y: comp * 0.05)

            // Icon layers: the peeking poster parallaxes down slightly during the lift.
            Image("SplashLayerPeek")
                .resizable().frame(width: comp, height: comp)
                .offset(y: comp * (10.0 / 640.0) * m)
            Image("SplashLayerCard")
                .resizable().frame(width: comp, height: comp)

            // Progress layer, revealed by a left→right sweep clipped to the line's band.
            Image("SplashLayerProgress")
                .resizable().frame(width: comp, height: comp)
                .mask(alignment: .topLeading) {
                    Rectangle()
                        .frame(width: comp * fl, height: comp * 0.16)
                        .offset(y: comp * (Self.dotY - 0.08))
                }

            // The sweep's leading edge is itself a small traveling light — it crosses the
            // line and lands on the dot, becoming the ignition. Fades out as it arrives.
            if fl > 0, fl < 1 {
                Circle()
                    .fill(RadialGradient(colors: [Color(hex: 0xF6BD7D).opacity(0.55), .clear],
                                         center: .center, startRadius: 0, endRadius: comp * 0.045))
                    .frame(width: comp * 0.09, height: comp * 0.09)
                    .position(x: comp * fl, y: comp * Self.dotY)
                    .opacity(min(seg(fl, 0.02, 0.15), 1 - seg(fl, Self.dotX, Self.dotX + 0.12)))
            }

            // The dot's glow — blooms as the traveling light lands, settles, then breathes.
            Circle()
                .fill(RadialGradient(colors: [Color(hex: 0xF6BD7D).opacity(0.85),
                                              Theme.accent.opacity(0.2),
                                              .clear],
                                     center: .center, startRadius: 0, endRadius: comp * 0.11))
                .frame(width: comp * 0.22, height: comp * 0.22)
                .scaleEffect(glowScale)
                .position(x: comp * Self.dotX, y: comp * Self.dotY)
                .opacity(dotGlow)

            // Specular sheen — a soft diagonal band of light crossing the tile once,
            // clipped to the tile shape. Peaks mid-travel, invisible at either end.
            if sheen > 0, sheen < 1 {
                Color.clear
                    .frame(width: comp, height: comp)
                    .overlay {
                        Rectangle()
                            .fill(LinearGradient(colors: [.clear,
                                                          Color.white.opacity(0.09),
                                                          .clear],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: comp * 0.55, height: comp * 1.6)
                            .rotationEffect(.degrees(24))
                            .offset(x: comp * (-0.9 + 1.8 * sheen))
                            .opacity(sin(sheen * .pi))
                    }
                    .clipShape(shape)
                    .allowsHitTesting(false)
            }
        }
        .compositingGroup()
        .opacity(ar)
        .scaleEffect(scale)
        .blur(radius: ar < 0.99 ? (1 - ar) * 4 : 0)
    }

    private func wordmark(size: CGSize, w: Double) -> some View {
        let fs = size.width * (118.0 / 1080.0)
        return (
            Text("Previously")
                .foregroundStyle(Self.ink)
            + Text(".")
                .foregroundStyle(LinearGradient(colors: [Theme.accent, Self.accentDeep],
                                                startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .font(AppFont.font(size: fs, weight: .bold))
        // Tracking-in: letters start airy and settle tight as the unit resolves.
        .kerning(fs * (-0.03 * w + 0.025 * (1 - w)))
        .frame(maxWidth: .infinity)
        .position(x: size.width / 2, y: size.height * Self.wordmarkTop + fs / 2)
        .offset(y: (1 - w) * 15)
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
            .foregroundStyle(Theme.accent)
            .frame(maxWidth: .infinity)
            .position(x: size.width / 2 + fs * 0.17, y: size.height * Self.taglineTop + fs / 2)
            .offset(y: (1 - tg) * 7)
            .opacity(tg * 0.8)
    }

    // MARK: - the mock's easing, verbatim

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
}
