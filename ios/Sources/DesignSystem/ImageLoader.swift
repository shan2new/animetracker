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
final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()
    private let cache = NSCache<NSURL, UIImage>()

    private init() { cache.totalCostLimit = 96 * 1024 * 1024 } // ~96 MB of decoded posters

    subscript(_ url: URL) -> UIImage? {
        get { cache.object(forKey: url as NSURL) }
        set {
            guard let newValue else { cache.removeObject(forKey: url as NSURL); return }
            let cost = newValue.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
            cache.setObject(newValue, forKey: url as NSURL, cost: cost)
        }
    }
}

// Serializes in-flight requests so two cells asking for the same poster share one fetch+decode.
actor ImageLoader {
    static let shared = ImageLoader()
    private var inFlight: [URL: Task<UIImage, Error>] = [:]

    func image(for url: URL, maxPixel: CGFloat) async throws -> UIImage {
        if let cached = ImageCache.shared[url] { return cached }
        if let existing = inFlight[url] { return try await existing.value }

        let task = Task.detached(priority: .userInitiated) { () throws -> UIImage in
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad // URLCache handles the on-disk layer
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw ImageLoadError.badData
            }
            return try downsampleImage(data, maxPixel: maxPixel)
        }
        inFlight[url] = task
        do {
            let image = try await task.value
            ImageCache.shared[url] = image
            inFlight[url] = nil
            return image
        } catch {
            inFlight[url] = nil
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

    @State private var image: UIImage?
    @State private var loadedURL: URL?
    @State private var didFail = false

    init(url: URL?, maxPixel: CGFloat = 700, contentMode: ContentMode = .fill) {
        self.url = url
        self.maxPixel = maxPixel
        self.contentMode = contentMode
        // Synchronous cache hit → first frame already shows the poster, so recycled cells don't flash.
        _image = State(initialValue: url.flatMap { ImageCache.shared[$0] })
    }

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            } else {
                GradientPlaceholder()
            }
        }
        .task(id: url) { await load() }
    }

    private func load() async {
        if image != nil && loadedURL == url { return } // already showing this exact URL
        guard let url else { image = nil; loadedURL = nil; return }

        if let cached = ImageCache.shared[url] {
            image = cached
            loadedURL = url
            return
        }

        image = nil          // URL changed to something uncached — clear any stale art
        didFail = false
        do {
            let loaded = try await ImageLoader.shared.image(for: url, maxPixel: maxPixel)
            withAnimation(.easeOut(duration: 0.25)) { image = loaded }
            loadedURL = url
        } catch {
            if !Task.isCancelled { didFail = true }
        }
    }
}
