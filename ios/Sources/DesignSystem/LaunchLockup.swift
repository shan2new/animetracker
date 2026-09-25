import SwiftUI
import UIKit
import ImageIO
import UniformTypeIdentifiers

/// The brand's identity at launch: the lit board ("P."), the name beneath it, the one light behind them.
///
/// The launch film lands on it and the sign-in gate is drawn around it, so there is ONE geometry and
/// one set of views for both. A signed-out launch then hands the mark to the gate without a seam:
/// the ribbon comes to rest exactly where the gate's mark is, and only the gate's line and its
/// button arrive. They were two lockups 50 pt apart, and the film's dissolve drew both at once
/// (25 Sep, on the SE and the Pro Max). The film lands on pictures of these same views
/// (`LaunchLockup.images`), so the match is by construction, not by measurement.
enum LaunchLockup {
    /// The board's width (the axle pins overhang it; `LaunchLockup.markBleed` makes room). The
    /// launch flips THIS board (`SplashFlapFilm`), so the film and the gate share the frame.
    static let markWidth: CGFloat = 120
    static var markHeight: CGFloat { markWidth * FlapGeometry.aspect }
    /// From the mark's foot to the top of the name's line.
    static let nameGap: CGFloat = ThemeSpace.x5
    /// The mark's centre, as a share of the screen's height. Signed out, the identity stands on the
    /// upper third, the gate's composition (its button owns the lower screen). Signed in there is
    /// no button to make room for, and a lockup that high sat over 500 pt of empty canvas, so it
    /// lands at the optical centre instead (review, 25 Sep).
    static let gateCentre: CGFloat = 0.36
    static let openCentre: CGFloat = 0.42

    /// Where the mark sits on a screen of `size` (full-screen points, safe area ignored).
    static func markFrame(in size: CGSize, signedIn: Bool = false) -> CGRect {
        let centre = signedIn ? openCentre : gateCentre
        return CGRect(x: (size.width - markWidth) / 2,
                      y: (size.height * centre - markHeight / 2).rounded(),
                      width: markWidth, height: markHeight)
    }

    /// The reader's text size, capped where the app caps it (`AniTrackApp`, AX2): the launch may
    /// not set its name larger than any text the app itself draws.
    static func typeSize(_ category: UIContentSizeCategory = UITraitCollection.current.preferredContentSizeCategory) -> DynamicTypeSize {
        min(DynamicTypeSize(category) ?? .large, .accessibility2)
    }

    // MARK: The views

    /// The mark as the gate draws it: the icon's board with its material at scale.
    static var mark: some View { PreviouslyMark(width: markWidth, lit: true) }

    /// The name, in the brand's own weight (SemiBold, the wordmark's), at display size.
    static var name: some View { BrandWord(style: ThemeType.brandDisplay) }

    /// The screen's one light source, centred on the one object it lights: a warm pool that stays
    /// close to the mark (it was 520 pt across, and read as a sepia fog 150 pt from the mark).
    struct Bloom: View {
        static let size: CGFloat = 360

        var body: some View {
            RadialGradient(stops: [.init(color: ThemeColor.accent.opacity(0.16), location: 0),
                                   .init(color: ThemeColor.accent.opacity(0.05), location: 0.30),
                                   .init(color: .clear, location: 1)],
                           center: .center, startRadius: 0, endRadius: Self.size / 2)
                .frame(width: Self.size, height: Self.size)
                .blur(radius: 20)
                // Rasterised once: a blur left as a layer filter re-runs every frame.
                .drawingGroup()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    // MARK: The film's last frame

    /// Room around the mark's picture for the coloured shadow it casts.
    static let markBleed: CGFloat = 28

    /// The three pictures the launch film lands on, rendered from the views above.
    struct Images {
        let mark: CGImage
        /// The mark's picture's box relative to the mark's own frame (it bleeds for the shadow).
        let markBox: CGRect
        let bloom: CGImage
        let name: CGImage
        let nameSize: CGSize
    }

    /// The pictures as an earlier launch cached them at this scale and text size — so the film's
    /// last frame, and the whole of the Reduce Motion film, are in the very first frame committed
    /// rather than drawn on a main thread busy building the app. `nil` on a first launch.
    static func cachedImages(scale: CGFloat, typeSize: DynamicTypeSize) -> Images? {
        guard let dir = cacheDirectory(scale: scale, typeSize: typeSize),
              let mark = loadPremultiplied(dir.appendingPathComponent("mark.png")),
              let bloom = loadPremultiplied(dir.appendingPathComponent("bloom.png")),
              let name = loadPremultiplied(dir.appendingPathComponent("name.png")) else { return nil }
        return assemble(mark: mark, bloom: bloom, name: name, scale: scale)
    }

    /// Renders the pictures from the views above, and caches them for the next launch.
    @MainActor
    static func images(scale: CGFloat, typeSize: DynamicTypeSize) -> Images? {
        func render<V: View>(_ view: V) -> CGImage? {
            let renderer = ImageRenderer(content: view.environment(\.dynamicTypeSize, typeSize))
            renderer.scale = scale
            renderer.isOpaque = false
            // Redrawn as 8-bit premultiplied sRGB: the renderer may hand back a wide-colour,
            // half-float picture, which Metal's texture loader refuses (the film then fell back to
            // its still lockup on every launch).
            return renderer.cgImage.flatMap(premultiplied)
        }
        SplashTrace.mark("pictures begin")
        guard let mark = render(Self.mark.padding(markBleed)),
              let bloom = render(Bloom()),
              let name = render(Self.name) else { return nil }
        SplashTrace.mark("pictures drawn")
        if let dir = cacheDirectory(scale: scale, typeSize: typeSize) {
            DispatchQueue.global(qos: .utility).async {
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                for (file, image) in [("mark", mark), ("bloom", bloom), ("name", name)] {
                    writePNG(image, to: dir.appendingPathComponent("\(file).png"))
                }
            }
        }
        #if DEBUG
        // `-splashDumpPictures 1`: the three pictures to Documents/splash-pictures, for the film
        // harness to land on.
        if UserDefaults.standard.bool(forKey: "splashDumpPictures"),
           let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let dump = docs.appendingPathComponent("splash-pictures", isDirectory: true)
            try? FileManager.default.createDirectory(at: dump, withIntermediateDirectories: true)
            for (file, image) in [("mark", mark), ("bloom", bloom), ("name", name)] {
                writePNG(image, to: dump.appendingPathComponent("\(file)@\(Int(scale))x.png"))
            }
        }
        #endif
        return assemble(mark: mark, bloom: bloom, name: name, scale: scale)
    }

    private static func assemble(mark: CGImage, bloom: CGImage, name: CGImage, scale: CGFloat) -> Images {
        Images(mark: mark,
               markBox: CGRect(x: -markBleed, y: -markBleed,
                               width: markWidth + markBleed * 2, height: markHeight + markBleed * 2),
               bloom: bloom,
               name: name,
               nameSize: CGSize(width: CGFloat(name.width) / scale, height: CGFloat(name.height) / scale))
    }

    // MARK: The cache

    /// Bump when any of the views above changes, so no launch lands on an old picture.
    private static let design = "v4-flap"

    private static func cacheDirectory(scale: CGFloat, typeSize: DynamicTypeSize) -> URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return caches.appendingPathComponent("launch-lockup", isDirectory: true)
            .appendingPathComponent("\(design)-\(build)-\(Int(scale))x-\(String(describing: typeSize))", isDirectory: true)
    }

    private static func premultiplied(_ image: CGImage) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }

    private static func loadPremultiplied(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return premultiplied(image)
    }

    private static func writePNG(_ image: CGImage, to url: URL) {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }
}
