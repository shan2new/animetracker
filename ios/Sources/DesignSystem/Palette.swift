import SwiftUI
import UIKit

// Art-adaptive tint for the show page's grounds and the art cards (spec board 10, "Palette").
// Computed once per artwork URL, off the main thread, never during scroll. The card ground is a derived colour —
// related to the show, never hostage to its palette:
//   downsample to 32×32 → ignore alpha < 0.8 and OKLab lightness < 0.08 or > 0.92 →
//   highest-population non-neutral colour (chroma ≥ 0.035) → clamp L 0.24…0.38, C 0.04…0.12 →
//   gradient 52 % → 18 % over the flat surface, black overlay 44 % → all-neutral art falls back.
@MainActor
final class PaletteCache {
    static let shared = PaletteCache()
    private var cache: [String: Color] = [:]
    /// The art's mean OKLab lightness (0…1), filled by the same extraction as the tint. The
    /// hero's protection scales with it (`HeroProtection`): a veil drawn for a bright cover
    /// buries a dark one ("the overlay on hero is too dark as the new images are themselves
    /// dark", user, 5 Sep).
    private var lightness: [String: Double] = [:]
    /// One resolve per URL at a time; a second caller AWAITS the first instead of being told
    /// "not available". The old `Set` answered the second caller with `cache[url]` — nil — and
    /// `resolve` turned that into the neutral fallback for good: Detail asks for the same poster
    /// twice (`tint` and `heroTint`, since the billboard went portrait-first), and its hardened
    /// bar came out the ember's warm grey on every show (measured (31,29,27) three times, 4 Sep).
    private var inFlight: [String: Task<Color?, Never>] = [:]

    /// Resolved colours are REMEMBERED across launches (24 Sep): a show page painted its ground
    /// umber on one visit, maroon on the next and olive on a third (the critique measured all
    /// three on Game of Thrones) — the analysis ran on whichever decode happened to be cached and
    /// broke ties in `Dictionary` order, which Swift seeds per launch. A show opens in ITS colour,
    /// on the first frame, every time.
    private struct Stored: Codable { let r: Double; let g: Double; let b: Double; let l: Double }
    private static let fileURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("palette.json")

    private var stored: [String: Stored] = [:]

    private init() {
        stored = (try? Data(contentsOf: Self.fileURL))
            .flatMap { try? JSONDecoder().decode([String: Stored].self, from: $0) } ?? [:]
        for (url, v) in stored {
            cache[url] = Color(.sRGB, red: v.r, green: v.g, blue: v.b, opacity: 1)
            lightness[url] = v.l
        }
    }

    private func remember(_ url: String, tint: Color, lightness l: Double) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(tint).getRed(&r, green: &g, blue: &b, alpha: &a) else { return }
        if stored.count >= 600 { stored.removeAll(keepingCapacity: true) }
        stored[url] = Stored(r: Double(r), g: Double(g), b: Double(b), l: l)
        guard let data = try? JSONEncoder().encode(stored) else { return }
        let fileURL = Self.fileURL
        Task.detached(priority: .utility) { try? data.write(to: fileURL, options: .atomic) }
    }

    nonisolated static let fallback = Color(hex: 0x1C1A17)   // neutral warm surface

    func tint(for url: String?) -> Color? {
        guard let url else { return nil }
        return cache[url]
    }

    /// The art's mean lightness, once its tint has been resolved; nil before.
    func lightness(for url: String?) -> Double? {
        guard let url else { return nil }
        return lightness[url]
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
        if let running = inFlight[url] { return await running.value }
        let task = Task<Color?, Never> { [self] in
            guard let u = URL(string: url) else { return nil }
            let image: UIImage?
            if let cached = ImageCache.shared.image(for: u, atLeast: maxPixel) {
                image = cached
            } else {
                image = try? await ImageLoader.shared.image(for: u, maxPixel: maxPixel)
            }
            guard let image else { return nil }
            let analysed = await Task.detached(priority: .utility) { PaletteCache.analyse(image) }.value
            self.cache[url] = analysed.tint
            self.lightness[url] = analysed.lightness
            self.remember(url, tint: analysed.tint, lightness: analysed.lightness)
            return analysed.tint
        }
        inFlight[url] = task
        defer { inFlight[url] = nil }
        return await task.value
    }

    // MARK: - Extraction (runs off-main)

    nonisolated static func dominantTint(of image: UIImage) -> Color { analyse(image).tint }

    /// The dominant tint and the mean OKLab lightness of the picture, from one 32×32 sample.
    nonisolated static func analyse(_ image: UIImage) -> (tint: Color, lightness: Double) {
        guard let cg = image.cgImage else { return (fallback, 0.5) }
        let w = 32, h = 32
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return (fallback, 0.5) }
        // `.high`: a 32×32 mean of the picture that barely depends on which decode was cached.
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        // Bucket candidate colours in OKLab, weighted by population; skip near-black, near-white,
        // transparent and neutral pixels.
        var buckets: [Int: (l: Double, a: Double, b: Double, n: Int)] = [:]
        var lightSum = 0.0, lightCount = 0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Double(pixels[i + 3]) / 255
            guard alpha >= 0.8 else { continue }
            let (l, a, b) = oklab(r: Double(pixels[i]) / 255, g: Double(pixels[i + 1]) / 255, b: Double(pixels[i + 2]) / 255)
            lightSum += l; lightCount += 1
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
        let meanLightness = lightCount > 0 ? lightSum / Double(lightCount) : 0.5
        // The winner by population, ties broken the same way every time — by the bucket's chroma,
        // then its key. `buckets.values.max` answered a tie in the dictionary's order, which Swift
        // seeds per launch, so a dark poster (a few dozen qualifying samples, ties likely) opened
        // in a different hue from one launch to the next.
        func chroma(_ e: (l: Double, a: Double, b: Double, n: Int)) -> Double {
            let a = e.a / Double(max(e.n, 1)), b = e.b / Double(max(e.n, 1))
            return (a * a + b * b).squareRoot()
        }
        let ranked = buckets.sorted { x, y in
            if x.value.n != y.value.n { return x.value.n > y.value.n }
            let cx = chroma(x.value), cy = chroma(y.value)
            if abs(cx - cy) > 1e-9 { return cx > cy }
            return x.key < y.key
        }
        guard let best = ranked.first?.value, best.n > 0 else { return (fallback, meanLightness) }
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
        return (Color(.sRGB, red: r, green: g, blue: b2, opacity: 1), meanLightness)
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

/// The last billboard's palette colour, kept across launches — the ground a show page's loading
/// frame is painted in before its own artwork has resolved.
///
/// A loading frame has no artwork yet by definition, so it was a black rectangle. The colour of
/// the last billboard a person looked at is the app's own atmosphere even when it is the wrong
/// show's, and far better than an empty canvas. Today's billboard wrote it until the Today feed
/// replaced it (25 Sep); the show page is the writer now (it resolves `heroTint` from its own
/// billboard art) and still its only reader (iD18). The key keeps Today's old name so a value an
/// earlier build stored carries over.
enum RememberedTint {
    private static let key = "today.heroTint"

    /// The remembered colour, or nil on a fresh install (or after a value that did not decode).
    static var color: Color? {
        guard let c = UserDefaults.standard.array(forKey: key) as? [Double], c.count >= 3 else { return nil }
        return Color(.sRGB, red: c[0], green: c[1], blue: c[2])
    }

    /// Stores `color` for the next loading frame. A nil colour (no art, a failed decode) is ignored:
    /// the last real palette stays, rather than being forgotten because one show had none.
    static func remember(_ color: Color?) {
        guard let color else { return }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a) else { return }
        let value = [Double(r), Double(g), Double(b)]
        let d = UserDefaults.standard
        // One write per new colour: a page re-resolving the same art must not touch the store.
        if let old = d.array(forKey: key) as? [Double], old.count >= 3,
           zip(old, value).allSatisfy({ abs($0 - $1) < 0.001 }) { return }
        d.set(value, forKey: key)
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

    /// The blurred artwork is (about to be) contributing luminance to the band — the palette
    /// resolve completes off the same decode the image view draws from.
    private var artSettled: Bool { resolvedTint != nil }

    /// The pre-art frame's strength. `ambientBackdropFallback` was made "visibly warmer than
    /// canvas" for exactly this moment — but that fix was applied at Detail's intensity 1. At a
    /// list root's 0.4 the same ember composites to ~rgb(38,36,32) on device: the status band
    /// reads BLACK for the whole first load, then jumps to twice the luminance when the art
    /// decodes (user, 30 Aug — "black, then it becomes flush"). Until the art is actually
    /// contributing, the base gradient holds a floor independent of `intensity`, so the wash
    /// looks like the wash from frame one; the art then arrives as a hue shift, not a light
    /// switching on. Relaxation is animated (`uiGentle`) with the palette handover.
    private var baseTop: Double { artSettled ? 0.60 * intensity : max(0.60 * intensity, 0.55) }
    private var baseMid: Double { artSettled ? 0.10 * intensity : max(0.10 * intensity, 0.12) }

    var body: some View {
        ZStack(alignment: .top) {
            if let url, !url.isEmpty {
                // Centre-cropped BEFORE the blur. Blurring a view whose art has not been made to
                // fill its frame samples whatever corner the image happened to land in — which is
                // why Profile drew no image at all — and it is why the wash lost its warmth even
                // where an image was present.
                // A pre-blurred bitmap (`BlurredArt`), not `.blur(radius: 56)` on the layer:
                // that was a Gaussian pass over a screen-wide texture on every scroll frame of
                // every root screen.
                BlurredArt(url: url, sourceMaxPixel: 320, fraction: 0.14)
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .clipped()
                    // No `.saturation(0.85)`: the tint clamp already holds chroma in a narrow band,
                    // so desaturating on top of it is subtracting the one thing the wash is for.
                    .opacity(0.70 * intensity)
            }
            LinearGradient(colors: [base.opacity(baseTop), base.opacity(baseMid), .clear],
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
        // The floor relaxing and the fallback→palette hue handover ride one gentle fade — the
        // snap between them was half of the "black, then flush" jump.
        .animation(ThemeMotion.uiGentle, value: resolvedTint)
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
