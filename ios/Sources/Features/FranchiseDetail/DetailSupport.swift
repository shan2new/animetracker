import SwiftUI
import UIKit

/// Deep-link target inside the detail: a season part and one episode (Schedule rows pass it).
struct EpisodeFocus: Equatable, Hashable {
    let mediaId: Int
    let episode: Int
}

// MARK: - Metrics

enum DetailMetrics {
    /// The tab-bar clearance, plus room for the floating sync banner while one is presented.
    ///
    /// The banner is drawn OVER content rather than inset from it, so with a failure pending the
    /// last row of a scroll sits permanently sliced through its glyphs. Until the banner carries a
    /// presented-state content inset of its own — filed as a shared-file request — the screens
    /// that can show one make room for it.
    @MainActor static var bottomClearance: CGFloat {
        ThemeMetrics.tabBarClearance + (SyncCenter.shared.failedChanges.isEmpty ? 0 : bannerClearance)
    }

    /// The banner's own height plus the gap it keeps from the tab bar.
    private static let bannerClearance: CGFloat = 72

    /// The first line of a pushed screen's content starts BELOW the floating toolbar.
    ///
    /// These screens hide the navigation bar's background so the show's colour can reach the top,
    /// which also means the safe area stops at the status bar — and a screen header laid out at
    /// the top of it renders under the back button, permanently dimmed by the toolbar's own veil.
    static let toolbarClearance: CGFloat = 46
}

// MARK: - The floating toolbar's own edge

/// The veil that covers the FLOATING TOOLBAR band, over and above the status-bar veil every root
/// screen gets from `scrollEdgeChrome`.
///
/// `ScrollEdgeChrome` holds full canvas across the status bar and then ramps out — right for a
/// screen whose only top chrome is the clock. This screen's chrome is a glass toolbar sitting
/// 20–42 pt *below* the status bar, and the ramp runs straight through it: a season row rendered
/// at ~50 % in the gap between the back button and the status pill, its amber line level with the
/// `···`. Raising `topHeight` cannot fix that — the primitive's full-canvas hold is pinned to the
/// safe-area inset and a taller veil only lengthens the ramp.
///
/// It cannot simply be on all the time either: a veil that holds opaque canvas for 108 pt blanks
/// the top third of the hero photograph, which is the thing the screen exists for. So it behaves
/// the way a native navigation bar behaves — absent while there is artwork behind the bar, faded
/// in the moment there is *content* there. Same construction as the primitive (canvas veil plus an
/// identically-masked `.ultraThinMaterial`, material dropped under Reduce Transparency), with one
/// number changed: where the hold ends.
///
/// `ScrollEdgeChrome` wants a `holdHeight:` of its own; filed as a shared-file request, and this
/// collapses into one call when it lands.
struct FloatingToolbarVeil: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// Status bar plus the floating toolbar's 44-pt band and the 4 pt it clears it by.
    private static var hold: CGFloat { ThemeMetrics.topSafeInset + 46 }
    private static let ramp: CGFloat = 40
    private static var height: CGFloat { hold + ramp }
    private var holdFraction: CGFloat { Self.hold / Self.height }

    private var veil: LinearGradient {
        LinearGradient(stops: [
            .init(color: ThemeColor.chromeVeil, location: 0),
            .init(color: ThemeColor.chromeVeil, location: holdFraction),
            .init(color: ThemeColor.chromeVeil.opacity(0.34), location: holdFraction + (1 - holdFraction) * 0.45),
            .init(color: ThemeColor.chromeVeil.opacity(0), location: 1),
        ], startPoint: .top, endPoint: .bottom)
    }

    private var blurMask: LinearGradient {
        LinearGradient(stops: [
            .init(color: .black, location: 0),
            .init(color: .black, location: holdFraction * 0.92),
            .init(color: .black.opacity(0.42), location: holdFraction + (1 - holdFraction) * 0.45),
            .init(color: .clear, location: 1),
        ], startPoint: .top, endPoint: .bottom)
    }

    var body: some View {
        ZStack {
            if !reduceTransparency {
                Rectangle().fill(.ultraThinMaterial).mask(blurMask)
            }
            veil
        }
        .frame(height: Self.height)
        .frame(maxWidth: .infinity)
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Art-derived colour, made fit to be a ground

/// Detail's quiet form of a palette colour.
///
/// `PaletteCache` clamps the extracted colour to OKLab C ≤ 0.12, which on a warm poster is still a
/// fully saturated brown: composited through `ArtAdaptiveGround` it landed at rgb(37,20,11) —
/// R:B 3.4:1, i.e. an orange block — and on a magenta-and-cyan show it was *also* an orange block,
/// so the colour said nothing about the show it came from. The ground wants the show's HUE, not
/// its saturation.
///
/// Two moves, in OKLab so they are perceptual rather than channel arithmetic:
/// chroma to ≤ 0.045 and lightness held in 0.40…0.46 (desaturating a colour darkens it, and a
/// card with no body is the defect the last pass was fixing), then 20 % toward `surfaceRaised` so
/// every ground shares a little of the app's own neutral. The composite lands near rgb(41,31,28)
/// on the warm poster above — R:B 1.46 — with `textPrimary` at 15.8:1 on it.
///
/// This is a LOCAL workaround: the same transform belongs at the end of `PaletteCache.resolve`,
/// where every screen would inherit it. Filed as a shared-file request.
enum DetailTint {
    private static let maxChroma = 0.045
    private static let minLightness = 0.40
    private static let maxLightness = 0.46
    private static let towardNeutral = 0.20

    /// The card / tile ground form of an art-derived colour.
    static func quiet(_ color: Color?) -> Color? {
        guard let color, let (r, g, b) = components(color) else { return color }
        var (l, ca, cb) = PaletteCache.oklab(r: r, g: g, b: b)
        let chroma = (ca * ca + cb * cb).squareRoot()
        if chroma > maxChroma, chroma > 0 {
            ca *= maxChroma / chroma
            cb *= maxChroma / chroma
        }
        l = min(max(l, minLightness), maxLightness)
        let (qr, qg, qb) = PaletteCache.srgb(l: l, a: ca, b: cb)
        guard let (nr, ng, nb) = components(ThemeColor.surfaceRaised) else {
            return Color(.sRGB, red: qr, green: qg, blue: qb, opacity: 1)
        }
        let m = towardNeutral
        return Color(.sRGB,
                     red: qr * (1 - m) + nr * m,
                     green: qg * (1 - m) + ng * m,
                     blue: qb * (1 - m) + nb * m,
                     opacity: 1)
    }

    /// The opacity at which `quiet` sits over the card ground to read as that ground lifted ~6 %
    /// in luminance — the no-still tile's fill. Composited rather than computed, so the tile
    /// tracks the ground's own gradient and radial highlight instead of guessing one value for it.
    static let tileOverGround: Double = 0.35

    private static func components(_ color: Color) -> (Double, Double, Double)? {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        return (Double(r), Double(g), Double(b))
    }
}

// MARK: - Identity poster

/// Detail's identity poster: `PosterSlot`'s geometry from the slot table, with the two things the
/// shared primitive still gets wrong on this screen.
///
/// 1. `PosterSlot` fills its backing with the *extracted tint* permanently, so any art whose
///    aspect differs from the slot's is framed by a saturated coloured band — measured 6 pt deep
///    top and bottom on the 112×168 hero, in rgb(100,45,19). On the screen's identity object that
///    is an orange picture mat. The tint is a pre-load placeholder here and nothing else; once the
///    art lands the mat is `surfaceRaised`.
/// 2. Art within 8 % of the slot's aspect fills the slot instead of letterboxing. Every cover in
///    this catalogue is 2:3 ± 5 %, so in practice there is no mat at all — and a real 16:9 still
///    handed to a poster slot still fits whole, on neutral.
///
/// The image is loaded here rather than through `RemoteImageView` for one reason: the fit/fill
/// decision needs the decoded size, and deciding it *after* the art is already on screen is a pop.
/// One state update carries the image and its mode together. Same cache, same loader, same
/// `Color.clear` sizing box as `CachedAsyncImage` — an `Image`'s ideal size is its pixel size and
/// it will inflate an enclosing HStack if it is ever asked to size itself.
struct DetailPoster: View {
    let url: String?
    var slot: PosterSize = .hero

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var image: UIImage?
    @State private var mode: ContentMode = .fit
    @State private var tint: Color?

    private var decodePixels: CGFloat { max(slot.size.width, slot.size.height) * 3 }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: slot.radius, style: .continuous)
                .fill(image == nil ? (tint ?? ThemeColor.surfaceRaised) : ThemeColor.surfaceRaised)
            Color.clear
                .overlay {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: mode)
                    } else if (url ?? "").isEmpty {
                        Image(systemName: "photo")
                            .font(.system(size: min(slot.size.width, slot.size.height) * 0.28))
                            .foregroundStyle(ThemeColor.textTertiary)
                    }
                }
                .clipped()
        }
        .frame(width: slot.size.width, height: slot.size.height)
        .clipShape(RoundedRectangle(cornerRadius: slot.radius, style: .continuous))
        // `posterEdge` (5 % white), never `separator` — a 12 % line over someone's illustration.
        .overlay(RoundedRectangle(cornerRadius: slot.radius, style: .continuous)
            .strokeBorder(ThemeColor.posterEdge, lineWidth: 1))
        .shadow(slot.shadow)
        .task(id: url) { await load() }
        .accessibilityHidden(true)
    }

    private func load() async {
        image = nil
        tint = DetailTint.quiet(await PaletteCache.shared.resolve(url: url, maxPixel: decodePixels))
        guard let url, !url.isEmpty, let u = URL(string: url) else { return }
        var decoded = ImageCache.shared.image(for: u, atLeast: decodePixels)
        if decoded == nil { decoded = try? await ImageLoader.shared.image(for: u, maxPixel: decodePixels) }
        guard let decoded, decoded.size.width > 0, decoded.size.height > 0 else { return }
        let art = decoded.size.width / decoded.size.height
        let want = slot.size.width / slot.size.height
        let fits = abs(art / want - 1) < 0.08
        withAnimation(ThemeMotion.pick(ThemeMotion.uiPoster, reduceMotion: reduceMotion)) {
            mode = fits ? .fill : .fit
            image = decoded
        }
    }
}

// MARK: - No-still episode tile

/// The 96×54 rectangle an episode row or the Next up card shows when there is no still — or when
/// there is one and it is being withheld for spoilers.
///
/// The shared `EpisodeGlyphTile` puts a `play.rectangle` at 34 % over the raw show tint, which
/// reads as an image that failed to load: the first object inside the screen's one action card
/// looked broken. A withheld still is not a broken still. So the tile carries the one thing that
/// is true about the episode and safe to print — its number — on the show's own colour, and the
/// shape and rhythm of the list stay intact.
struct EpisodeIdentifierTile: View {
    /// Already quieted — this sits over a `.art` ground and must not out-shout it.
    let tint: Color?
    /// "S7 · E2" in a card, "E2" in a row. A numeral is information; a glyph over nothing is not.
    let identifier: String

    var body: some View {
        (tint ?? ThemeColor.surfaceRaised)
            .opacity(DetailTint.tileOverGround)
            .frame(width: EpisodeArtwork.slot.width, height: EpisodeArtwork.slot.height)
            .overlay {
                Text(identifier)
                    .type(ThemeType.cardFact)
                    .foregroundStyle(ThemeColor.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 6)
            }
            .clipShape(RoundedRectangle(cornerRadius: ThemeRadius.episodeStill, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: ThemeRadius.episodeStill, style: .continuous)
                .strokeBorder(ThemeColor.posterEdge, lineWidth: 1))
            .accessibilityHidden(true)
    }
}

extension FranchisePart {
    /// The compact identifier a tile prints: `S7 · E2` where a season number exists, `E2` where it
    /// does not (a film, an OVA run, a single-season show).
    func tileIdentifier(episode: Int) -> String {
        guard kind == .season, sequence > 0 else { return "E\(episode)" }
        return "S\(sequence) · E\(episode)"
    }
}
