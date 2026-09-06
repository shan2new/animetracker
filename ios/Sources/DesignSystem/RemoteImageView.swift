import SwiftUI

// Cover/banner image with the legacy gradient fallback. Poster art is the star — no glass here.
// Backed by CachedAsyncImage (decoded-image cache + off-main downsampling) so grids scroll without
// flicker or hitches. `maxPixel` bounds the decode to the display size — posters need far less than
// AniList's extraLarge source.
struct RemoteImageView: View {
    let url: String?
    var contentMode: ContentMode = .fill
    var maxPixel: CGFloat = 700
    /// Where a `.fill` image anchors inside its frame (`.top` keeps faces in a tall crop).
    var alignment: Alignment = .center
    /// Hosts that draw their own ground (palette tint, art backdrop) hide the opaque placeholder.
    var placeholderHidden: Bool = false
    /// Frame aspect a near-matching `.fit` image snaps to fill against — see `CachedAsyncImage`.
    var fitSnapAspect: CGFloat? = nil
    /// A contact shadow under a `.fit` image — see `CachedAsyncImage.fitShadow`.
    var fitShadow: ShadowToken? = nil
    /// Called once the image is on screen (the launch waits for the hero's picture).
    var onLoaded: (() -> Void)? = nil

    var body: some View {
        CachedAsyncImage(url: parsedURL, maxPixel: maxPixel, contentMode: contentMode,
                         alignment: alignment, placeholderHidden: placeholderHidden,
                         fitSnapAspect: fitSnapAspect, fitShadow: fitShadow, onLoaded: onLoaded)
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
            .background(ThemeColor.surfaceRaised)
    }
}
