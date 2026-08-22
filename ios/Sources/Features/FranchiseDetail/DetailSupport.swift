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

// MARK: - The last session this device created

/// Which watch session was created a moment ago, so Watch history can draw its arrival exactly once.
///
/// The rail's new-session choreography (`HistorySessionRow.isNew` — rail draw on `uiSweep`, then the
/// node settling on `uiMicro`) was specified, implemented in the design system and then called from
/// nothing but a `#Preview`: starting a rewatch and opening Watch history showed a fully drawn rail
/// with no arrival at all. The two surfaces are a push apart and neither owns the other's state, so
/// the hand-off is a one-shot token: `FranchiseDetailView.startRewatch` records the id, the first
/// `WatchHistoryView` that renders consumes it, and every later render draws a settled rail.
@MainActor
enum RewatchArrival {
    private static var pending: UUID?

    static func record(_ id: UUID) { pending = id }

    /// True exactly once, for the session that was just created.
    static func claim(_ id: UUID) -> Bool {
        guard pending == id else { return false }
        pending = nil
        return true
    }
}

// MARK: - Strings this round needs that `Copy` does not have yet

/// Detail's half of the round-2 copy fixes.
///
/// Every one of these belongs in `DesignSystem/Copy.swift` — that file is the only place a
/// user-facing string is allowed to live, and `Copy.Action.commands` is the table the ellipsis and
/// confirmation rules are checked against. The shared diff is filed; this is the local half, kept
/// in one enum rather than scattered as literals at call sites so the move is a rename.
enum DetailCopy {
    /// `Copy.Action.showTitle` is "Show title" — a noun phrase, on a card that displays the show's
    /// title 100 pt above it, for a control whose subject is the EPISODE's title. Verb + object.
    static let revealEpisodeTitle = "Reveal episode title"
    static let hideEpisodeTitle = "Hide episode title"
    /// The season list's whole-list form of the same switch.
    static let revealEpisodeTitlesAndStills = "Reveal episode titles and stills"

    /// The series-level mark. `markCaughtUp` touches the releasing part only and
    /// `setStatus(.completed)` changes the word without touching an episode, so there was no way to
    /// say "I watched all of this" that the seasons list would agree with.
    static let markSeriesWatched = "Mark series as watched"

    /// The rewatch scope that covers the whole work. "All seasons" was printed over a list
    /// containing "OVA 1", "OVA 2: No Regrets" and "OVA 3: Lost Girls" — none of which is a season.
    /// The app's word for a work is "title"; "Everything" is the word for all of it.
    static let everything = "Everything"

    /// Ending a rewatch. `RewatchStore.complete(_:at:)` existed and was called only from the mark
    /// path, so a user who abandoned a rewatch at episode 26 could only DELETE the record — leaving
    /// the "In progress" badge lit and Today offering the rewatch for ever.
    static let markRewatchComplete = "Mark this rewatch complete"
    static let stopRewatch = "Stop this rewatch\u{2026}"
}

// MARK: - Episode title sanitising

enum EpisodeCopy {
    /// The catalogue's episode title, or `nil` when there isn't a real one.
    ///
    /// The flagship show's first row read `Episode 1 · Episode  - That Time I Got Reincarnated as
    /// a Slime…`: the word "Episode" twice, a double space, a dangling hyphen, the franchise's own
    /// title inside its episode title, and then ellipsised — because `rowTitle` concatenated
    /// `Copy.episode(n)` with whatever string the source stored and did no checking at all.
    ///
    /// AniList's episode-1 titles routinely embed the show name, and both sources emit
    /// `"Episode 1"`, `"Episode - "` and `"Episode 12 - Foo"` as *titles*. A title that repeats the
    /// label the row already prints, or repeats the show the hero already printed, is not a title.
    static func title(_ raw: String?, franchise: String) -> String? {
        guard let raw else { return nil }
        // Collapse every run of whitespace (the double space came from an empty numeral slot).
        var t = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        // Strip a leading "Episode", an optional number, and an optional separator.
        if let r = t.range(of: "^[Ee]pisode\\s*\\d*\\s*[-–—:·]?\\s*", options: .regularExpression) {
            t = String(t[r.upperBound...])
        }
        // A dangling separator at either end is what is left of "Episode - " once the show's name
        // was the only content.
        t = t.trimmingCharacters(in: CharacterSet(charactersIn: " -–—:·"))
        guard !t.isEmpty else { return nil }
        let normalised = t.lowercased()
        // The franchise's own name is identity, not an episode title, and it is 400 pt above
        // already. Equality is not enough: AniList's episode-1 slot on the flagship show holds
        // "Episode  - That Time I Got Reincarnated as a Slime the Movie: Tears of the Azure Sea |
        // Trailer" — the show's name, then a *different work*, then a promo tag. Anything that
        // OPENS with the show's own name is a catalogue string, not the name of an episode.
        let show = franchise.lowercased()
        if !show.isEmpty, normalised.hasPrefix(show) { return nil }
        // Anything still starting "episode" is a numbering scheme, not a name.
        if normalised.hasPrefix("episode") { return nil }
        // Promotional material the catalogue files in the episode list. A trailer is not episode n.
        for tag in ["trailer", "teaser", "promo", " pv", "preview"] where normalised.hasSuffix(tag) {
            return nil
        }
        return t
    }
}

// MARK: - The episode image slot

/// One 96×54 rectangle for an episode — the still if the catalogue has one, the show's own artwork
/// if it does not.
///
/// The build this replaces drew ten to eighteen consecutive identical `play.rectangle` tiles on a
/// tint that resolved within ~4 % luminance of the card ground: a placeholder farm down the middle
/// of the flagship show's episode list. **A glyph is only honest where there is no art at all, and
/// there is always art — the season has a poster.** So the slot falls back to the season's own
/// cover, cropped from its top (posters are faces at the top and logotype at the bottom) under a
/// gradient dark enough that the tile never competes with a real still beside it.
///
/// The episode number is deliberately NOT drawn on the tile: the row's own text states it 8 pt
/// away, and an identifier printed twice in one row is exactly the defect `WithheldStillTile`'s
/// note records. What stops a season becoming a wall of one repeated poster is upstream, in
/// `SeasonEpisodesView.artPolicy`: a season the catalogue barely illustrated drops the art column
/// entirely rather than repeating one image eighteen times.
struct EpisodeStill: View {
    /// The episode's own still.
    let url: String?
    /// The season's (or the show's) poster — the fallback ART, never a glyph.
    let poster: String?
    /// The palette ground under both, so the slot is never grey.
    var tint: Color? = nil
    /// `nil` fills the width it is offered (the accessibility-size card); a number pins the slot.
    var width: CGFloat? = EpisodeArtwork.slot.width

    @State private var stillTint: Color?

    private var hasStill: Bool { !(url ?? "").isEmpty }
    private var hasPoster: Bool { !(poster ?? "").isEmpty }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: ThemeRadius.episodeStill, style: .continuous)
                .fill(stillTint ?? tint ?? ThemeColor.surfaceRaised)
            if hasStill {
                RemoteImageView(url: url, contentMode: .fill, maxPixel: (width ?? 400) * 3,
                                placeholderHidden: true)
            } else if hasPoster {
                // A backdrop crop of the poster: `.top`, because a 2:3 cover carries the face in
                // its upper half and the logotype band in its lower one.
                RemoteImageView(url: poster, contentMode: .fill, maxPixel: (width ?? 400) * 3,
                                alignment: .top, placeholderHidden: true)
                LinearGradient(colors: [.black.opacity(0.25), .black.opacity(0.50)],
                               startPoint: .top, endPoint: .bottom)
            } else {
                // Genuinely no artwork anywhere for this show. The show's colour, and nothing else
                // — a play glyph here would claim a picture failed to load.
                LinearGradient(colors: [.black.opacity(0.10), .black.opacity(0.34)],
                               startPoint: .top, endPoint: .bottom)
            }
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .frame(width: width)
        .frame(maxWidth: width == nil ? .infinity : nil)
        .clipShape(RoundedRectangle(cornerRadius: ThemeRadius.episodeStill, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: ThemeRadius.episodeStill, style: .continuous)
            .strokeBorder(ThemeColor.posterEdge, lineWidth: 1))
        .task(id: url ?? poster) {
            stillTint = DetailTint.quiet(await PaletteCache.shared.resolve(url: url ?? poster, maxPixel: 288))
        }
        .accessibilityHidden(true)
    }
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
    /// The ramp. 40 pt left a poster fragment surviving at ~50 % alpha directly under the back
    /// button on the seasons list — a sliced piece of artwork reading as a rendering error. 58 pt
    /// puts the whole art sliver inside the dissolve, and matches the episode list one push deeper,
    /// which gets the same treatment from its real navigation bar.
    private static let ramp: CGFloat = 58
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
