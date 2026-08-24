import SwiftUI
import UIKit

// Art-adaptive tint for the Focus and Recap cards (spec board 10, "Palette"). Computed once per
// artwork URL, off the main thread, never during scroll. The card ground is a derived colour —
// related to the show, never hostage to its palette:
//   downsample to 32×32 → ignore alpha < 0.8 and OKLab lightness < 0.08 or > 0.92 →
//   highest-population non-neutral colour (chroma ≥ 0.035) → clamp L 0.24…0.38, C 0.04…0.12 →
//   gradient 52 % → 18 % over the flat surface, black overlay 44 % → all-neutral art falls back.
@MainActor
final class PaletteCache {
    static let shared = PaletteCache()
    private var cache: [String: Color] = [:]
    private var inFlight: Set<String> = []

    nonisolated static let fallback = Color(hex: 0x1C1A17)   // neutral warm surface

    func tint(for url: String?) -> Color? {
        guard let url else { return nil }
        return cache[url]
    }

    /// Resolves the tint for `url`, using the already-decoded poster when the image cache has it.
    func resolve(url: String?, maxPixel: CGFloat) async -> Color {
        await resolveIfAvailable(url: url, maxPixel: maxPixel) ?? PaletteCache.fallback
    }

    /// The optional form is for surfaces that own a meaningful branded fallback. Returning nil
    /// keeps that fallback on stage when a device is offline or the artwork decode is still busy,
    /// instead of replacing it with a neutral colour that is indistinguishable from the canvas.
    func resolveIfAvailable(url: String?, maxPixel: CGFloat) async -> Color? {
        guard let url, !url.isEmpty else { return nil }
        if let hit = cache[url] { return hit }
        guard !inFlight.contains(url) else { return cache[url] }
        inFlight.insert(url)
        defer { inFlight.remove(url) }
        guard let u = URL(string: url) else { return nil }
        let image: UIImage?
        if let cached = ImageCache.shared.image(for: u, atLeast: maxPixel) {
            image = cached
        } else {
            image = try? await ImageLoader.shared.image(for: u, maxPixel: maxPixel)
        }
        guard let image else { return nil }
        let color = await Task.detached(priority: .utility) { PaletteCache.dominantTint(of: image) }.value
        cache[url] = color
        return color
    }

    // MARK: - Extraction (runs off-main)

    nonisolated static func dominantTint(of image: UIImage) -> Color {
        guard let cg = image.cgImage else { return fallback }
        let w = 32, h = 32
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return fallback }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        // Bucket candidate colours in OKLab, weighted by population; skip near-black, near-white,
        // transparent and neutral pixels.
        var buckets: [Int: (l: Double, a: Double, b: Double, n: Int)] = [:]
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Double(pixels[i + 3]) / 255
            guard alpha >= 0.8 else { continue }
            let (l, a, b) = oklab(r: Double(pixels[i]) / 255, g: Double(pixels[i + 1]) / 255, b: Double(pixels[i + 2]) / 255)
            guard l >= 0.08, l <= 0.92 else { continue }
            let chroma = (a * a + b * b).squareRoot()
            guard chroma >= 0.035 else { continue }
            // 12-bin hue × 4-bin lightness buckets.
            let hue = atan2(b, a)
            let key = Int((hue + .pi) / (2 * .pi) * 12) * 10 + Int(l * 4)
            var e = buckets[key] ?? (0, 0, 0, 0)
            e.l += l; e.a += a; e.b += b; e.n += 1
            buckets[key] = e
        }
        guard let best = buckets.values.max(by: { $0.n < $1.n }), best.n > 0 else { return fallback }
        var l = best.l / Double(best.n), a = best.a / Double(best.n), bb = best.b / Double(best.n)
        // Clamp lightness and chroma, and lean the hue toward the brand's warmth so the app's
        // atmosphere never swings olive or steel from tab to tab.
        // The clamps the ambient wash regressed on. Measured against the baseline at (1200,300):
        // Library new rgb(36,30,27) vs original rgb(45,32,22) — 20 % dimmer with R−B falling 23→9;
        // Schedule new rgb(32,32,29) vs original rgb(71,64,59) — less than half the luminance,
        // R−B 12→3. Chroma clamped to 0.035–0.075 and then blended 35 % toward brand amber makes
        // "art-derived colour" arithmetically present and perceptually absent: neutral charcoal
        // where the baseline had warm ember. The chroma ceiling doubles, the lightness floor rises,
        // and the brand blend drops to a breath (0.15) that stops the app swinging olive or steel
        // from tab to tab without erasing the show's own hue.
        l = min(max(l, 0.30), 0.44)
        let c = (a * a + bb * bb).squareRoot()
        let cc = min(max(c, 0.075), 0.145)
        if c > 0 {
            var ua = a / c, ub = bb / c
            let (_, wa, wb) = oklab(r: 0xF0 / 255.0, g: 0xA2 / 255.0, b: 0x4E / 255.0)
            let wn = (wa * wa + wb * wb).squareRoot()
            ua = 0.85 * ua + 0.15 * (wa / wn); ub = 0.85 * ub + 0.15 * (wb / wn)
            let un = (ua * ua + ub * ub).squareRoot()
            a = ua / un * cc; bb = ub / un * cc
        }
        let (r, g, b2) = srgb(l: l, a: a, b: bb)
        return Color(.sRGB, red: r, green: g, blue: b2, opacity: 1)
    }

    // sRGB ↔ OKLab (Björn Ottosson).
    nonisolated private static func lin(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
    nonisolated private static func gam(_ v: Double) -> Double { v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055 }

    nonisolated static func oklab(r: Double, g: Double, b: Double) -> (Double, Double, Double) {
        let rl = lin(r), gl = lin(g), bl = lin(b)
        let l_ = cbrt(0.4122214708 * rl + 0.5363325363 * gl + 0.0514459929 * bl)
        let m_ = cbrt(0.2119034982 * rl + 0.6806995451 * gl + 0.1073969566 * bl)
        let s_ = cbrt(0.0883024619 * rl + 0.2817188376 * gl + 0.6299787005 * bl)
        return (0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
                1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
                0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_)
    }

    nonisolated static func srgb(l: Double, a: Double, b: Double) -> (Double, Double, Double) {
        let l_ = l + 0.3963377774 * a + 0.2158037573 * b
        let m_ = l - 0.1055613458 * a - 0.0638541728 * b
        let s_ = l - 0.0894841775 * a - 1.2914855480 * b
        let L = l_ * l_ * l_, M = m_ * m_ * m_, S = s_ * s_ * s_
        let r = 4.0767416621 * L - 3.3077115913 * M + 0.2309699292 * S
        let g = -1.2684380046 * L + 2.6097574011 * M - 0.3413193965 * S
        let bb = -0.0041960863 * L - 0.7034186147 * M + 1.7076147010 * S
        return (min(max(gam(r), 0), 1), min(max(gam(g), 0), 1), min(max(gam(bb), 0), 1))
    }
}

/// The art-adaptive card ground: derived colour at 52 % → 18 % over the flat surface, under a
/// black veil. A stable result for any poster; text contrast is verified by the gate.
///
/// **The veil is 30 %, not 44 %.** The spec's 44 % is a FLOOR to be raised until primary text
/// clears 4.5:1 — but the derived colour is already clamped to OKLab L ≤ 0.38, so the composite
/// landed at rgb(22,18,18) against a rgb(9,9,11) canvas: a 4 % luminance step, which is why the
/// shipped Focus card read as a hole with an outline round it rather than as a lit object. At 30 %
/// the same card composites near rgb(34,28,25) — still a deep, cinema-dark ground, `textPrimary`
/// (#F4F1EC) still clears 12:1 on it, and the card finally has a body.
struct ArtAdaptiveGround: View {
    let tint: Color?
    /// 1 is the card ground. Drop it for a large hero where the colour would otherwise dominate.
    var intensity: Double = 1

    private var base: Color { tint ?? PaletteCache.fallback }

    var body: some View {
        ZStack {
            ThemeColor.surfaceFlat
            LinearGradient(
                colors: [base.opacity(0.52 * intensity), base.opacity(0.18 * intensity)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            // A light source, not a flat wash: without it a large ground is one dead rectangle of
            // colour, which is what a gradient-filled div looks like.
            RadialGradient(colors: [base.opacity(0.30 * intensity), .clear],
                           center: .init(x: 0.16, y: 0.02), startRadius: 0, endRadius: 320)
            Color.black.opacity(0.30)
        }
        .animation(ThemeMotion.uiPoster, value: tint == nil)
    }
}

/// The ambient identity wash behind the top of a screen: the artwork itself, blurred past
/// recognition, bleeding under the status bar and dissolving into the canvas.
///
/// This is the single biggest thing the shipped build dropped. The original Detail, Library,
/// Schedule and Search screens all opened on a warm, art-derived atmosphere; the rebuilt ones open
/// on #09090B. Nothing else recovers that much perceived quality for as little structure — and it
/// costs one static, already-cached image, drawn once, never animated, never touched on scroll.
///
/// Composed as: art → tint bloom → vertical fade to canvas. Everything below `height` is canvas.
struct ArtBackdrop: View {
    var url: String? = nil
    var tint: Color? = nil
    var height: CGFloat = 380
    /// 1 for a Detail hero. Lower it on a list screen, where the wash is atmosphere, not identity.
    var intensity: Double = 1

    @State private var resolvedTint: Color?

    /// Never let the presence of a URL remove the gradient. A cache-warm simulator could draw the
    /// blurred art on frame one, while a physical device briefly had neither art nor a perceptible
    /// fallback. The branded ember renders immediately; the artwork palette replaces it later.
    private var base: Color { tint ?? resolvedTint ?? ThemeColor.ambientBackdropFallback }

    var body: some View {
        ZStack(alignment: .top) {
            if let url, !url.isEmpty {
                // Centre-cropped BEFORE the blur. Blurring a view whose art has not been made to
                // fill its frame samples whatever corner the image happened to land in — which is
                // why Profile drew no image at all — and it is why the wash lost its warmth even
                // where an image was present.
                RemoteImageView(url: url, contentMode: .fill, maxPixel: 320,
                                placeholderHidden: true)
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .clipped()
                    .blur(radius: 56, opaque: true)
                    // No `.saturation(0.85)`: the tint clamp already holds chroma in a narrow band,
                    // so desaturating on top of it is subtracting the one thing the wash is for.
                    .opacity(0.70 * intensity)
            }
            LinearGradient(colors: [base.opacity(0.60 * intensity), base.opacity(0.10 * intensity), .clear],
                           startPoint: .top, endPoint: .bottom)
            // A constant breath of the brand's warmth under every wash, so Schedule, Search and
            // Profile share one atmosphere instead of borrowing a different hue from whichever
            // poster happens to lead.
            LinearGradient(colors: [ThemeColor.accent.opacity(0.07 * intensity), .clear],
                           startPoint: .top, endPoint: .bottom)
            // The handover to the canvas. It must reach FULL canvas well before the content that
            // sits over it, or the first section looks like it is floating on a stain.
            LinearGradient(stops: [
                .init(color: .clear, location: 0.0),
                .init(color: ThemeColor.canvas.opacity(0.55), location: 0.55),
                .init(color: ThemeColor.canvas, location: 1.0),
            ], startPoint: .top, endPoint: .bottom)
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: url) {
            resolvedTint = nil
            let color = await PaletteCache.shared.resolveIfAvailable(url: url, maxPixel: 320)
            guard !Task.isCancelled else { return }
            resolvedTint = color
        }
    }
}
