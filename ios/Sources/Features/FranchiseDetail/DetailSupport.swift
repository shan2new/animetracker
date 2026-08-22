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

// MARK: - The Next up card's still

/// The card's episode image: a 16:9 rectangle at whatever width the card gives it.
///
/// The slot used to be spoiler-gated behind `revealed`, so on every first view the most important
/// card on the screen rendered a flat grey rounded rectangle with grey text in it — a placeholder
/// that outlined brighter than the card ground, where a photograph belongs. **A still is not a
/// spoiler; an episode TITLE is.** So the picture shows by default and the reveal control now
/// governs the title alone.
///
/// It takes a width rather than the fixed 96×54 slot because at accessibility sizes the card is a
/// VStack: a 96-pt thumbnail stacked over 30-pt type is a stamp, and deleting it (what the shipped
/// build did) leaves the card with no identity art at exactly the sizes where it matters most.
/// Same rectangle, same aspect, one number different.
struct NextUpStill: View {
    let url: String?
    /// Already quieted — this sits over a `.art` ground.
    let tint: Color?
    /// `nil` fills the width it is offered (the accessibility-size layout); a number pins the
    /// thumbnail slot beside the text.
    var width: CGFloat? = EpisodeArtwork.slot.width

    @State private var stillTint: Color?

    private var hasStill: Bool { !(url ?? "").isEmpty }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: ThemeRadius.episodeStill, style: .continuous)
                .fill(stillTint ?? tint ?? ThemeColor.surfaceRaised)
            if hasStill {
                RemoteImageView(url: url, contentMode: .fill, maxPixel: (width ?? 400) * 3)
            } else {
                // No still anywhere in the catalogue for this episode: the show's own colour under
                // a quiet glyph, never a grey box and never an invented identifier.
                LinearGradient(colors: [.black.opacity(0.10), .black.opacity(0.34)],
                               startPoint: .top, endPoint: .bottom)
                Image(systemName: "play.rectangle")
                    .font(.system(size: width == nil ? 24 : 17, weight: .regular))
                    .foregroundStyle(ThemeColor.textPrimary.opacity(0.34))
            }
        }
        // 16:9 either way. A width pins the slot; no width takes the card's own width, so the
        // still grows with the type instead of vanishing.
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .frame(width: width)
        .frame(maxWidth: width == nil ? .infinity : nil)
        .clipShape(RoundedRectangle(cornerRadius: ThemeRadius.episodeStill, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: ThemeRadius.episodeStill, style: .continuous)
            .strokeBorder(ThemeColor.posterEdge, lineWidth: 1))
        .task(id: url) {
            guard hasStill else { stillTint = nil; return }
            stillTint = DetailTint.quiet(await PaletteCache.shared.resolve(url: url, maxPixel: 288))
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Withheld still

/// The 96×54 rectangle that stands in for a still the app is deliberately NOT showing.
///
/// The tile it replaces printed an identifier — `S7 · E2` — built from `sequence`, the raw ordinal
/// among all parts, where OVAs and films occupy slots. On every AniList franchise with an OVA it
/// disagreed with the fact line 8 pt away ("Season 4 · Episode 19" beside "S5 · E19"), broke the
/// copy table's own notation rule twice over, and was the screenshot attached to the one-star
/// review. A string that cannot contradict its neighbour is the one that does not exist: the
/// episode's identity is stated once, in the row's text, and the rectangle says only what it is
/// doing — withholding a picture.
///
/// Distinct from the shared `EpisodeGlyphTile` (`play.rectangle` = there is no still at all): a
/// withheld still is a choice the user can reverse, and `eye.slash` is the glyph on the control
/// that reverses it.
struct WithheldStillTile: View {
    /// Already quieted — this sits over a `.art` ground and must not out-shout it.
    let tint: Color?

    var body: some View {
        RoundedRectangle(cornerRadius: ThemeRadius.episodeStill, style: .continuous)
            .fill(tint ?? ThemeColor.surfaceRaised)
            .frame(width: EpisodeArtwork.slot.width, height: EpisodeArtwork.slot.height)
            .overlay {
                LinearGradient(colors: [.black.opacity(0.10), .black.opacity(0.34)],
                               startPoint: .top, endPoint: .bottom)
            }
            .overlay {
                Image(systemName: "eye.slash")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(ThemeColor.textPrimary.opacity(0.62))
            }
            .clipShape(RoundedRectangle(cornerRadius: ThemeRadius.episodeStill, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: ThemeRadius.episodeStill, style: .continuous)
                .strokeBorder(ThemeColor.posterEdge, lineWidth: 1))
            .accessibilityHidden(true)
    }
}
