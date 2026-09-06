import SwiftUI
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - Pre-blurred art

/// Art blurred ONCE, off the main thread, into a small bitmap — never `.blur(radius:)` on a
/// composited layer.
///
/// A Gaussian filter on a layer is re-run by the render server on every frame that layer is
/// composited: every scroll frame, every frame of the billboard's 24-second drift, every frame of
/// the stage's breath, over a screen-sized texture. The billboard's ground, the four root washes,
/// every composited card's ground and the trailer stage all wore one (5 Sep) — on the simulator
/// that was most of the compositor's frame, and on a device it is GPU time spent on a picture that
/// never changes. Here the blur is a property of the IMAGE: derived from the same decode the sharp
/// layer draws (`sourceMaxPixel` — one fetch, one decode, both layers in one transaction),
/// downsampled to `BlurredImages.width` pixels, blurred by `fraction` of that width (so the radius
/// scales with the frame the way a point radius did), colour-corrected if asked, cached under the
/// URL, and drawn as a bitmap the compositor merely scales. Bilinear upscaling of a blurred
/// 160-pixel image is indistinguishable from the filter at any radius that reads as a blur.
struct BlurredArt: View {
    let url: String?
    /// The decode the blur is derived from: the sharp layer's own bucket, so the two share one
    /// fetch and land together. A surface with no sharp layer asks for something small.
    var sourceMaxPixel: CGFloat = 320
    /// The blur radius as a fraction of the drawn width. 0.12 ≈ `.blur(radius: 48)` on a
    /// screen-wide layer; 0.09 ≈ 28 on a shelf card.
    var fraction: CGFloat = 0.12
    /// Baked colour controls (the stage lifts dark art): `.saturation` / `.brightness` are
    /// per-frame filters too.
    var saturation: Double = 1
    var brightness: Double = 0
    var alignment: Alignment = .center

    @State private var image: UIImage?

    init(url: String?, sourceMaxPixel: CGFloat = 320, fraction: CGFloat = 0.12,
         saturation: Double = 1, brightness: Double = 0, alignment: Alignment = .center) {
        self.url = url
        self.sourceMaxPixel = sourceMaxPixel
        self.fraction = fraction
        self.saturation = saturation
        self.brightness = brightness
        self.alignment = alignment
        // A cache hit is on screen from the first frame, like the sharp layer's.
        let spec = BlurredImages.Spec(url: url ?? "", fraction: fraction, saturation: saturation, brightness: brightness)
        _image = State(initialValue: BlurredImages.cached(spec))
    }

    private var spec: BlurredImages.Spec {
        BlurredImages.Spec(url: url ?? "", fraction: fraction, saturation: saturation, brightness: brightness)
    }

    var body: some View {
        // Sized by the container, never by the bitmap (see `CachedAsyncImage`).
        Color.clear
            .overlay(alignment: alignment) {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
                        .transition(.opacity)
                }
            }
            .clipped()
            .task(id: spec) { await load() }
    }

    private func load() async {
        let spec = spec
        guard !spec.url.isEmpty else { image = nil; return }
        if let hit = BlurredImages.cached(spec) { image = hit; return }
        guard let rendered = await BlurredImages.shared.image(spec, sourceMaxPixel: sourceMaxPixel),
              !Task.isCancelled else { return }
        withAnimation(ThemeMotion.uiGentle) { image = rendered }
    }
}

/// The blur pipeline: one render per (url, radius, colour controls), de-duplicated while in
/// flight, filed in `ImageCache` beside the decodes it was derived from.
actor BlurredImages {
    static let shared = BlurredImages()

    struct Spec: Hashable {
        let url: String
        let fraction: CGFloat
        let saturation: Double
        let brightness: Double

        var key: String {
            "blur|\(Int((fraction * 100).rounded()))|\(Int((saturation * 100).rounded()))|\(Int((brightness * 100).rounded()))|\(url)"
        }
    }

    /// The bitmap's width in pixels. Enough that a 0.09 blur (14 px) still has a dozen samples
    /// across, small enough that a screen of cards costs less than one poster decode.
    static let width: CGFloat = 160

    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    nonisolated static func cached(_ spec: Spec) -> UIImage? {
        guard !spec.url.isEmpty else { return nil }
        return ImageCache.shared.derived(spec.key)
    }

    func image(_ spec: Spec, sourceMaxPixel: CGFloat) async -> UIImage? {
        if let hit = ImageCache.shared.derived(spec.key) { return hit }
        if let running = inFlight[spec.key] { return await running.value }
        let task = Task<UIImage?, Never> {
            guard let u = URL(string: spec.url) else { return nil }
            let source: UIImage?
            if let hit = ImageCache.shared.image(for: u, atLeast: min(sourceMaxPixel, BlurredImages.width)) {
                source = hit
            } else {
                source = try? await ImageLoader.shared.image(for: u, maxPixel: sourceMaxPixel)
            }
            guard let source else { return nil }
            let rendered = await Task.detached(priority: .userInitiated) {
                BlurredImages.render(source, spec: spec)
            }.value
            if let rendered { ImageCache.shared.storeDerived(rendered, key: spec.key) }
            return rendered
        }
        inFlight[spec.key] = task
        defer { inFlight[spec.key] = nil }
        return await task.value
    }

    // MARK: rendering (off-main)

    nonisolated(unsafe) private static let context = CIContext(options: [.cacheIntermediates: false])

    /// Downsample with Core Graphics (area-averaging, so a 2048-px decode does not alias on its
    /// way to 160), then blur with Core Image, edges clamped so the picture never darkens at its
    /// borders the way an unclamped Gaussian does — the `opaque: true` the layer blur used.
    nonisolated static func render(_ source: UIImage, spec: Spec) -> UIImage? {
        guard let cg = source.cgImage, cg.width > 0, cg.height > 0 else { return nil }
        let w = Int(width)
        let h = max(1, Int((CGFloat(cg.height) / CGFloat(cg.width) * width).rounded()))
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let small = ctx.makeImage() else { return nil }

        let input = CIImage(cgImage: small)
        var image = input.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: spec.fraction * width])
            .cropped(to: input.extent)
        if spec.saturation != 1 || spec.brightness != 0 {
            image = image.applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: spec.saturation,
                kCIInputBrightnessKey: spec.brightness,
            ])
        }
        guard let out = context.createCGImage(image, from: input.extent) else { return nil }
        return UIImage(cgImage: out)
    }
}
