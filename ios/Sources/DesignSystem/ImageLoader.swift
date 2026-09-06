import SwiftUI
import UIKit
import ImageIO

// A seamless image pipeline for the poster grids. AsyncImage was the bottleneck: it keeps no
// decoded-image cache, so every LazyVGrid cell recycle re-fetched, re-decoded on the main actor,
// and flashed the placeholder back in — visible flicker and scroll hitches. This pipeline:
//   • caches DECODED, downsampled images in memory (NSCache), so recycled cells render instantly;
//   • de-duplicates concurrent loads of the same URL;
//   • downsamples via ImageIO off the main thread (bounded memory, no main-thread decode);
//   • serves synchronous cache hits at init, so a scrolled-away-and-back card never flashes.

enum ImageLoadError: Error { case badData }

// Decodes + downsamples to a thumbnail no larger than `maxPixel` on its longest edge, forcing the
// decode up front (kCGImageSourceShouldCacheImmediately) so rendering never decodes on the main thread.
func downsampleImage(_ data: Data, maxPixel: CGFloat) throws -> UIImage {
    let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
    guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
        throw ImageLoadError.badData
    }
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceShouldCacheImmediately: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixel),
    ]
    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
        throw ImageLoadError.badData
    }
    return UIImage(cgImage: cgImage)
}

// Thread-safe (NSCache is) store of decoded images, sized by real byte cost so memory stays bounded.
//
// Keyed on (url, SIZE BUCKET), not on url alone. Keying on the URL made the FIRST decode win for
// the whole session: a Library thumb asks for ~207px, so the detail hero that wants 700px got the
// 207px decode handed back and rendered a blurry upscale until the app restarted.
//
// The rule is one-directional. A request is served by any cached decode at least as detailed as it
// asked for (downscaling at draw time is free and lossless-looking); it is never served a smaller
// one. Sizes are rounded UP to a fixed ladder and the decode is done at the bucket, not at the
// caller's exact request — otherwise a 207px decode filed under the 256 bucket would shortchange
// the next caller who genuinely wants 256. The ladder plus the serve-larger rule keeps entries per
// URL to a small handful (in practice one or two), and NSCache's byte-cost limit bounds the rest.
final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()
    private let cache = NSCache<NSString, UIImage>()

    private init() { cache.totalCostLimit = 96 * 1024 * 1024 } // ~96 MB of decoded posters

    /// Decode sizes we round up to. Spaced ~1.4x so rounding never wastes much memory, and wide
    /// enough at the top to cover full-bleed banners on a 3x device.
    static let buckets: [CGFloat] = [128, 192, 256, 384, 512, 768, 1024, 1536, 2048]

    /// The bucket a request decodes and files itself under — the smallest one that satisfies it.
    /// A request beyond the ladder keeps its own exact size rather than being silently downgraded.
    static func bucket(for maxPixel: CGFloat) -> CGFloat {
        buckets.first { $0 >= maxPixel } ?? maxPixel.rounded(.up)
    }

    private static func key(_ url: URL, _ bucket: CGFloat) -> NSString {
        "\(Int(bucket))|\(url.absoluteString)" as NSString
    }

    /// The best cached decode that is AT LEAST as detailed as `maxPixel`, or nil.
    /// Never returns a smaller decode — that's the bug this cache exists to prevent.
    func image(for url: URL, atLeast maxPixel: CGFloat) -> UIImage? {
        let want = ImageCache.bucket(for: maxPixel)
        for b in ImageCache.buckets where b >= want {
            if let hit = cache.object(forKey: ImageCache.key(url, b)) { return hit }
        }
        // Above the ladder there is no larger bucket to fall back on: only an exact match serves.
        return want > (ImageCache.buckets.last ?? 0) ? cache.object(forKey: ImageCache.key(url, want)) : nil
    }

    /// File a decode under the bucket it was decoded at.
    func store(_ image: UIImage, for url: URL, bucket: CGFloat) {
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        cache.setObject(image, forKey: ImageCache.key(url, bucket), cost: cost)
    }

    /// A bitmap DERIVED from a decode — a pre-blur (`BlurredImages`) — filed beside the decodes
    /// under its own key, so it lives and dies with them.
    func derived(_ key: String) -> UIImage? {
        cache.object(forKey: "derived|\(key)" as NSString)
    }

    func storeDerived(_ image: UIImage, key: String) {
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        cache.setObject(image, forKey: "derived|\(key)" as NSString, cost: cost)
    }
}

// Serializes in-flight requests so two cells asking for the same poster share one fetch+decode.
// De-dup is keyed on (url, bucket) for the same reason the cache is: two surfaces wanting the same
// poster at different sizes are not the same request, and collapsing them handed the loser a decode
// too small to render sharply.
actor ImageLoader {
    static let shared = ImageLoader()
    private var inFlight: [String: Task<UIImage, Error>] = [:]

    func image(for url: URL, maxPixel: CGFloat) async throws -> UIImage {
        if let cached = ImageCache.shared.image(for: url, atLeast: maxPixel) { return cached }

        // Decode at the bucket, not at the caller's exact request, so the entry honours every
        // later request that resolves to the same bucket.
        let bucket = ImageCache.bucket(for: maxPixel)
        let key = "\(Int(bucket))|\(url.absoluteString)"
        if let existing = inFlight[key] { return try await existing.value }

        let task = Task.detached(priority: .userInitiated) { () throws -> UIImage in
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad // URLCache handles the on-disk layer
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw ImageLoadError.badData
            }
            return try downsampleImage(data, maxPixel: bucket)
        }
        inFlight[key] = task
        do {
            let image = try await task.value
            ImageCache.shared.store(image, for: url, bucket: bucket)
            inFlight[key] = nil
            return image
        } catch {
            inFlight[key] = nil
            throw error
        }
    }
}

// Drop-in image view: instant for cache hits (no placeholder flash), gentle cross-fade for fresh
// loads, robust to the URL changing on a reused view.
struct CachedAsyncImage: View {
    let url: URL?
    var maxPixel: CGFloat
    var contentMode: ContentMode
    /// Where a `.fill` image anchors inside the frame; hosts with their own ground hide the placeholder.
    var alignment: Alignment
    var placeholderHidden: Bool
    /// The frame's aspect ratio (w/h) a `.fit` image may SNAP TO FILL against. Posters aspect-fit
    /// by rule, but a cover whose ratio misses the slot's by a couple of per cent left a 2-pt
    /// tinted sliver along one edge — read on every shelf as a rendering artifact, not as the
    /// deliberate letterbox mat the rule is for. Within `fitSnapTolerance` the crop is invisible
    /// (≤ ~2 % of one axis) and the image fills; a real mismatch keeps the honest fit + mat.
    var fitSnapAspect: CGFloat?
    /// A contact shadow under a `.fit` image, drawn by a shape the size of the FITTED picture and
    /// rasterised with it. `.shadow` on the image layer itself was an offscreen pass per
    /// composited card per frame (5 Sep).
    var fitShadow: ShadowToken?

    // 0.08, not 0.05: AniList's standard cover is 460×654 (0.703) against the 2:3 slot (0.667) —
    // a 5.4 % miss, i.e. exactly the sliver this exists to remove. At 8 % the fill crops ≤4 % per
    // edge, still imperceptible on a poster; genuine lockups and stills miss by far more.
    private static let fitSnapTolerance: CGFloat = 0.08

    @State private var image: UIImage?
    @State private var loadedURL: URL?
    @State private var didFail = false

    /// Called once an image is on screen — from the cache on the first frame, or when a load lands.
    var onLoaded: (() -> Void)? = nil

    init(url: URL?, maxPixel: CGFloat = 700, contentMode: ContentMode = .fill,
         alignment: Alignment = .center, placeholderHidden: Bool = false,
         fitSnapAspect: CGFloat? = nil, fitShadow: ShadowToken? = nil, onLoaded: (() -> Void)? = nil) {
        self.url = url
        self.maxPixel = maxPixel
        self.contentMode = contentMode
        self.alignment = alignment
        self.placeholderHidden = placeholderHidden
        self.fitSnapAspect = fitSnapAspect
        self.fitShadow = fitShadow
        self.onLoaded = onLoaded
        // Synchronous cache hit → first frame already shows the poster, so recycled cells don't
        // flash. `atLeast:` so a hero never inherits a thumbnail-sized decode as its first frame.
        _image = State(initialValue: url.flatMap { ImageCache.shared.image(for: $0, atLeast: maxPixel) })
    }

    var body: some View {
        // The art hangs off a Color.clear SIZING BOX and is drawn as an overlay. This is load-bearing:
        // an `Image` reports its pixel dimensions as its ideal size (our decoded UIImages are scale
        // 1.0, so a 1100px banner claims 1100pt), and `.frame(maxWidth:.infinity)` only clamps that
        // ideal when the parent proposes a concrete width — during an HStack/ZStack's sizing pass the
        // proposal is nil, so the ideal leaks out and inflates the whole enclosing layout. (That's
        // what threw Schedule's rail off-screen: one hero banner widened the ScrollView's content
        // past the screen and the feed rendered horizontally centred/clipped.) `Color.clear` has no
        // intrinsic size and an overlay never contributes to its parent's size, so this view now
        // measures exactly what its container proposes — never more.
        Color.clear
            .overlay(alignment: alignment) {
                if let image {
                    let mode = resolvedContentMode(for: image)
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: mode)
                        // The fitted picture's own frame, so the shadow shape needs no geometry.
                        .background {
                            if let fitShadow, mode == .fit {
                                Rectangle().fill(Color.black.shadow(.drop(color: fitShadow.color, radius: fitShadow.radius,
                                                                          x: 0, y: fitShadow.y)))
                            }
                        }
                        .transition(.opacity)
                } else if !placeholderHidden {
                    GradientPlaceholder()
                }
            }
            .clipped()
            .task(id: url) { await load() }
            // The synchronous cache hit is on screen from the first frame.
            .onAppear { if image != nil { onLoaded?() } }
    }

    /// `.fit` that would leave only a sliver of mat snaps to `.fill` — see `fitSnapAspect`.
    private func resolvedContentMode(for image: UIImage) -> ContentMode {
        guard contentMode == .fit, let target = fitSnapAspect, target > 0,
              image.size.height > 0 else { return contentMode }
        let aspect = image.size.width / image.size.height
        return abs(aspect / target - 1) <= Self.fitSnapTolerance ? .fill : .fit
    }

    private func load() async {
        if image != nil && loadedURL == url { return } // already showing this exact URL
        guard let url else { image = nil; loadedURL = nil; return }

        if let cached = ImageCache.shared.image(for: url, atLeast: maxPixel) {
            image = cached
            loadedURL = url
            onLoaded?()
            return
        }

        image = nil          // URL changed to something uncached — clear any stale art
        didFail = false
        do {
            let loaded = try await ImageLoader.shared.image(for: url, maxPixel: maxPixel)
            // Reported when the fade COMPLETES, not when it begins (review i3): the launch's
            // gate opened on the fade's first frame and the app emerged mid-decode.
            withAnimation(ThemeMotion.uiGentle, completionCriteria: .logicallyComplete) {
                image = loaded
            } completion: {
                onLoaded?()
            }
            loadedURL = url
        } catch {
            if !Task.isCancelled { didFail = true }
        }
    }
}
