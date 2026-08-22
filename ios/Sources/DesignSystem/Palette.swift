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
        guard let url, !url.isEmpty else { return PaletteCache.fallback }
        if let hit = cache[url] { return hit }
        guard !inFlight.contains(url) else { return cache[url] ?? PaletteCache.fallback }
        inFlight.insert(url)
        defer { inFlight.remove(url) }
        guard let u = URL(string: url) else { return PaletteCache.fallback }
        let image: UIImage?
        if let cached = ImageCache.shared.image(for: u, atLeast: maxPixel) {
            image = cached
        } else {
            image = try? await ImageLoader.shared.image(for: u, maxPixel: maxPixel)
        }
        guard let image else { return PaletteCache.fallback }
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
        // Clamp lightness and chroma.
        l = min(max(l, 0.24), 0.38)
        let c = (a * a + bb * bb).squareRoot()
        let cc = min(max(c, 0.04), 0.12)
        if c > 0 { a *= cc / c; bb *= cc / c }
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

/// The art-adaptive card ground: derived colour at 52 % → 18 % over the flat surface, then a
/// 44 % black overlay. A stable result for any poster; text contrast is verified by the gate.
struct ArtAdaptiveGround: View {
    let tint: Color?

    var body: some View {
        ZStack {
            ThemeColor.surfaceFlat
            LinearGradient(
                colors: [(tint ?? PaletteCache.fallback).opacity(0.52), (tint ?? PaletteCache.fallback).opacity(0.18)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Color.black.opacity(0.44)
        }
        .animation(ThemeMotion.uiPoster, value: tint == nil)
    }
}
