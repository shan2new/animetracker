import SwiftUI

// Cover/banner image with the legacy gradient fallback. Poster art is the star — no glass here.
// Backed by CachedAsyncImage (decoded-image cache + off-main downsampling) so grids scroll without
// flicker or hitches. `maxPixel` bounds the decode to the display size — posters need far less than
// AniList's extraLarge source.
struct RemoteImageView: View {
    let url: String?
    var contentMode: ContentMode = .fill
    var maxPixel: CGFloat = 700

    var body: some View {
        CachedAsyncImage(url: parsedURL, maxPixel: maxPixel, contentMode: contentMode)
    }

    private var parsedURL: URL? {
        guard let url, !url.isEmpty else { return nil }
        return URL(string: url)
    }
}

struct GradientPlaceholder: View {
    var body: some View {
        LinearGradient(
            colors: [Color(hex: 0x27272F), Color(hex: 0x141418)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// A fixed-size rounded thumbnail (the legacy `Thumb`).
struct Thumb: View {
    let cover: String?
    let width: CGFloat
    let height: CGFloat
    var radius: CGFloat = 10

    var body: some View {
        // Bound the decode to the thumbnail's display size (3x = max device scale) instead of the
        // poster-grid default — a 160pt thumb needs ~480px, not 700.
        RemoteImageView(url: cover, maxPixel: max(width, height) * 3)
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .background(Theme.surface)
    }
}
