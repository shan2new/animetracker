import SwiftUI
import UIKit

// A story's picture (ios-spec §5.2, §5.4), as Instagram draws a photo that is not 9:16: the
// picture WHOLE, fitted to the card's width, on a wash of its own colour (Instagram samples the
// photo for the gradient behind it). Rebuilt 25 Sep ("The Story experience is utterly trashy!",
// owner): the frame zoomed a titled poster 1.34× past its logotype and a landscape 1.9× across
// the upper part to FILL the glass — a 460-px AniList cover drawn ~1,300 px tall, soft on every
// frame, and a banner's face blown up to the screen. A picture here is never drawn past its own
// pixels' worth of zoom; the frame is the picture's shape.
//
// Cost rules (CLAUDE.md "Smoothness is measured"): no `.mask`, no layer blur, no drift — the wash
// is two stops of one colour (`PaletteCache`'s tint of the picture, resolved once, small).

struct StoryArt: View {
    let art: StoryPicture

    @Environment(\.displayScale) private var displayScale
    @State private var tint: Color?

    /// The wash: the picture's colour a little dimmed at the top, deep at the foot, so the caption
    /// and the reply row sit on something dark whatever the picture is.
    private static let washTop: Double = 0.18
    private static let washFoot: Double = 0.7

    var body: some View {
        GeometryReader { g in
            let size = g.size
            ZStack {
                wash
                RemoteImageView(url: art.url, contentMode: .fit,
                                maxPixel: Self.maxPixel(for: art, screen: size, scale: displayScale),
                                placeholderHidden: true)
                    .frame(width: size.width, height: size.height)
            }
            .frame(width: size.width, height: size.height)
            .clipped()
        }
        .task(id: art.url) {
            guard let url = art.url else { return }
            if let hit = PaletteCache.shared.tint(for: url) { tint = hit; return }
            let resolved = await PaletteCache.shared.resolveIfAvailable(url: url, maxPixel: StoryStyle.landscapeTintPixels)
            guard !Task.isCancelled else { return }
            withAnimation(ThemeMotion.uiGentle) { tint = resolved }
        }
        .accessibilityHidden(true)
    }

    private var wash: some View {
        let base = tint ?? StoryStyle.artGround
        return LinearGradient(colors: [base.mix(with: .black, by: Self.washTop), base.mix(with: .black, by: Self.washFoot)],
                              startPoint: .top, endPoint: .bottom)
    }

    // MARK: Decode sizes (§5.4) — one rule for the body, the prefetch and the tray's open

    /// The decode a frame's picture is drawn at: the fitted picture's LONG side in pixels. The
    /// prefetch and the tray's first-frame wait ask for EXACTLY this (the image cache answers a
    /// decode at least this large), so a tap forward, a turn of the cube or the open never lands on
    /// black.
    ///   · portrait (2:3): `min(2560, screen w × 1.5 × scale)`
    ///   · landscape (16:9): `min(1600, screen w × scale)`
    static func maxPixel(for art: StoryPicture, screen: CGSize, scale: CGFloat) -> CGFloat {
        let s = max(scale, 1)
        if art.portrait {
            return min(StoryStyle.portraitPixelCap, screen.width * 1.5 * s)
        }
        return min(StoryStyle.landscapePixelCap, screen.width * s)
    }

    /// Decodes a frame's picture at its story size and waits for it — the tray's open races this
    /// against its 0.9 s ceiling. True when the picture is in the cache.
    @discardableResult
    static func load(_ art: StoryPicture, screen: CGSize, scale: CGFloat) async -> Bool {
        guard let s = art.url, let url = URL(string: s) else { return false }
        let pixels = maxPixel(for: art, screen: screen, scale: scale)
        if ImageCache.shared.image(for: url, atLeast: pixels) != nil { return true }
        return (try? await ImageLoader.shared.image(for: url, maxPixel: pixels)) != nil
    }

    /// Decode a frame's picture before it is asked for, off the main actor. Never on a
    /// constrained or expensive path (Low Data Mode, cellular — iD9).
    static func prefetch(_ art: StoryPicture, screen: CGSize, scale: CGFloat) {
        guard !StoryArt.constrained else { return }
        guard let s = art.url, let url = URL(string: s) else { return }
        let pixels = maxPixel(for: art, screen: screen, scale: scale)
        if ImageCache.shared.image(for: url, atLeast: pixels) != nil { return }
        Task.detached(priority: .utility) { _ = try? await ImageLoader.shared.image(for: url, maxPixel: pixels) }
    }

    /// Low Data Mode or an expensive path: the reel's URLs are already at the smaller bucket, and
    /// nothing is fetched ahead of the reader.
    @MainActor
    static var constrained: Bool { SyncCenter.shared.isConstrained || SyncCenter.shared.isExpensive }
}
