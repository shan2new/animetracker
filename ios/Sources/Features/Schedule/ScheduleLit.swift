import SwiftUI
import UIKit

// Schedule, lit (26 Sep: "Schedule UI/UX needs to feel more beautiful and delightful", owner; two
// directions were filmed on the owner's calendar and the owner chose POLISH — "but the horizontal
// timeline is distracting and irritating", so its NOW line is gone). The structure the owner chose on
// 25 Sep stays — ONE card for the next thing over a banner-free agenda where the date rides the row,
// the month grid behind the calendar glyph — and it comes alive:
//   · the card is Home's billboard at card scale (`ScheduleLitCard`): the show's best-looking poster
//     (`PosterPick`) as a PICTURE, protection only under the words and scaled to the art's lightness,
//     landing on the art's own hue at depth, the show's logo on clean art, a glow of the art's colour
//     around the card;
//   · each row's face sits in a breath of its show's colour, and today's next airing says how long is
//     left ("in 2h 14m", accent) where its clock was;
//   · the card's words and the rows rise in, once a visit, in under a third of a second — and the feed
//     LANDS on today from its first frame, holding there until the reader touches it (`reland`).
// Rejected with it: BOARD (each day's numeral on split-flap tiles turning from blank, a countdown on
// flaps — on-brand, and an effect), the NOW line (an amber hairline and time capsule across the
// agenda, Apple Calendar's), and the clock tinted in the show's hue (most posters here are warm: every
// time came out salmon). Deleted, not flagged.

// MARK: - The show's colour

/// The palette colour (`PaletteCache`) re-set as LIGHT — a glow on the canvas: OKLab L 0.60, chroma
/// up to 0.14 (a glow is colour or it is grey). The hue is the show's; the lightness is the job's.
enum ScheduleHue {
    static func glow(_ tint: Color?) -> Color? {
        guard let tint else { return nil }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(tint).getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        var (_, ca, cb) = PaletteCache.oklab(r: Double(r), g: Double(g), b: Double(b))
        let c = (ca * ca + cb * cb).squareRoot()
        guard c > 0.0001 else { return nil }
        let k = min(max(c, 0.06), 0.14) / c
        ca *= k
        cb *= k
        let (sr, sg, sb) = PaletteCache.srgb(l: 0.60, a: ca, b: cb)
        return Color(.sRGB, red: sr, green: sg, blue: sb, opacity: 1)
    }
}

// MARK: - The arrival

/// Something arriving with the visit: `distance` below and clear, then in place on the reveal curve,
/// `delay` after the visit began. Under Reduce Motion it is simply there.
struct ScheduleRise: ViewModifier {
    let shown: Bool
    var delay: Double = 0
    var distance: CGFloat = ScheduleArrivalMetrics.rise
    var duration: Double = ScheduleArrivalMetrics.duration

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : distance)
            .animation(reduceMotion || !shown ? nil
                       : .timingCurve(0.22, 1, 0.36, 1, duration: duration).delay(delay),
                       value: shown)
    }
}

// MARK: - What a row wears

/// What a lit row wears, in one value so `ScheduleAgendaRow` keeps one signature for every caller
/// (Home's rows pass none).
struct ScheduleRowDecor {
    /// The art whose palette colour glows under the row's face.
    var hueURL: String? = nil
    /// The end of the caption drawn in accent — today's countdown ("in 2h 14m").
    var accentTail: String? = nil

    static let none = ScheduleRowDecor()
}

// MARK: - The lit card

/// The next thing to watch, as Home's billboard at card scale: the show's
/// best-looking poster (`PosterPick`, chosen by eye and kept) as a PICTURE, protection only under
/// the words and scaled to the art's own lightness, landing on the art's hue at depth rather than on
/// black; the show's logo on clean art (type only where there is none); and a glow of the art's own
/// colour around the card, drawn once by its shape. The words rise in over the picture once a visit.
///
/// What it replaced: a scrim of black at 0.6 → 0.9 across the lower half, over the catalogue's
/// season key visual — a dark smear with the art at maybe 30 %, and on Slime a dark, diagonal
/// picture with its faces at the edges.
struct ScheduleLitCard: View {
    let franchise: Franchise
    let eyebrow: String
    let line: String
    let state: AiringState
    let canToggle: Bool
    let markLabel: String
    /// This visit's arrival has begun.
    let arrived: Bool
    let onToggle: () -> Void
    let onOpen: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var settled: Shown?
    @State private var tint: Color?
    @State private var lightness: Double?
    @State private var copyHeight: CGFloat = ScheduleCardMetrics.copyEstimate

    struct Shown: Equatable {
        let franchiseId: String
        let url: String?
        let name: BillboardName
    }

    init(franchise: Franchise, eyebrow: String, line: String, state: AiringState, canToggle: Bool,
         markLabel: String, arrived: Bool, onToggle: @escaping () -> Void, onOpen: @escaping () -> Void) {
        self.franchise = franchise
        self.eyebrow = eyebrow
        self.line = line
        self.state = state
        self.canToggle = canToggle
        self.markLabel = markLabel
        self.arrived = arrived
        self.onToggle = onToggle
        self.onOpen = onOpen
        // The colour is remembered across launches (`PaletteCache`): the card opens in it on its
        // first frame when the pick is already known.
        let url = PosterPick.shared.choice(for: franchise).flatMap { WideArt.billboard(portrait: $0.url, landscape: nil).url }
        _tint = State(initialValue: PaletteCache.shared.tint(for: url))
        _lightness = State(initialValue: PaletteCache.shared.lightness(for: url))
    }

    /// A pick made before this card existed — on its first frame.
    private var storedPick: Shown? { PosterPick.shared.choice(for: franchise).map(shown(from:)) }

    private func shown(from pick: PosterPick.Choice) -> Shown {
        Shown(franchiseId: franchise.id,
              url: WideArt.billboard(portrait: pick.url, landscape: nil).url,
              name: pick.billboardName(for: franchise, visible: ScheduleCardMetrics.clearBand))
    }

    private var catalogue: Shown {
        Shown(franchiseId: franchise.id, url: franchise.billboardArt.url ?? franchise.portraitArt,
              name: franchise.billboardName)
    }

    /// The picture this card shows: settled for this show, else the stored pick. Nothing but the
    /// ground until one is known — never one poster, then another (Home's rule).
    private var shown: Shown? {
        if let settled, settled.franchiseId == franchise.id { return settled }
        return storedPick
    }

    var body: some View {
        let width = ThemeMetrics.windowWidth - 2 * ThemeMetrics.gutter
        let height = (width * ScheduleCardMetrics.aspect).rounded()
        let shape = RoundedRectangle(cornerRadius: ThemeRadius.card, style: .continuous)
        let shown = shown
        let strength = HeroProtection.strength(lightness: lightness)
        let depth = DetailTint.ground(tint, lightness: ScheduleCardMetrics.groundLightness)
        ZStack(alignment: .bottom) {
            Button(action: onOpen) {
                ZStack(alignment: .bottom) {
                    (tint == nil ? ThemeColor.surfaceFlat : DetailTint.ground(tint, lightness: DetailTint.groundTopLightness))
                    if let url = shown?.url {
                        RemoteImageView(url: url, contentMode: .fill, maxPixel: 1400, alignment: .top,
                                        placeholderHidden: true)
                            .frame(width: width, height: height)
                            .transition(.opacity)
                    }
                    // Only under the words, as deep as the art needs (`HeroProtection`), landing on
                    // the picture's own colour at depth. Part of the picture, drawn with it.
                    HeroCopyScrim(copyHeight: copyHeight, lead: ScheduleCardMetrics.scrimLead, strength: strength,
                                  landing: depth)
                        // Never animated in: on a first visit the tab's page-in transaction carried
                        // the card's first pass and faded the protection in ~0.1 s after the
                        // picture — a frame of bare art under words about to arrive.
                        .transaction { $0.animation = nil }
                }
                .frame(width: width, height: height)
                .clipped()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(eyebrow), \(franchise.displayTitle), \(line)")
            .accessibilityHint(Copy.Accessibility.opensTheShowHint)

            lockup(name: shown?.name ?? .type)
                .padding(.horizontal, ThemeSpace.x4)
                .padding(.bottom, ThemeSpace.x4)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { copyHeight = $0 }
        }
        .frame(width: width, height: height)
        .clipShape(shape)
        .overlay(shape.strokeBorder(ThemeColor.posterEdge, lineWidth: FeedMetrics.hairline))
        .background { glow(shape) }
        .padding(.horizontal, ThemeMetrics.gutter)
        .task(id: franchise.id) { await settle() }
        .task(id: shown?.url) { await readArt(shown?.url) }
    }

    /// The art's colour as light under the card: a canvas-filled copy of its shape whose shadow is
    /// the colour — drawn with the shape, once (`cardShadow`'s rule), so nothing is re-rendered as
    /// the card scrolls.
    @ViewBuilder
    private func glow(_ shape: RoundedRectangle) -> some View {
        if let light = ScheduleHue.glow(tint) {
            shape
                .fill(ThemeColor.canvas.shadow(.drop(color: light.opacity(ScheduleCardMetrics.glowOpacity),
                                                     radius: ScheduleCardMetrics.glowRadius,
                                                     x: 0, y: ScheduleCardMetrics.glowDrop)))
                .transition(.opacity.animation(ThemeMotion.uiPoster))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// The moment on its tag, the show's logo (else its name), the episode, and the mark once out.
    private func lockup(name: BillboardName) -> some View {
        VStack(spacing: ThemeSpace.x3) {
            VStack(spacing: ThemeSpace.x2) {
                HomeNewTag(text: eyebrow)
                    .textCase(.uppercase)
                    .modifier(rise(0))
                if case .logo = name, name.hasGraphicLogo, !typeSize.isAccessibilitySize {
                    ArtworkLogo(name: name, title: franchise.displayTitle, height: ScheduleCardMetrics.logoHeight)
                        .padding(.horizontal, ThemeSpace.x10)
                        .modifier(rise(1))
                } else if name != .embedded || typeSize.isAccessibilitySize {
                    Text(franchise.displayTitle)
                        .type(ThemeType.displayL)
                        .foregroundStyle(ThemeColor.textPrimary)
                        .lineLimit(typeSize.isAccessibilitySize ? 3 : 2)
                        .minimumScaleFactor(0.75)
                        .shadow(.art)
                        .modifier(rise(1))
                }
                Text(line)
                    .type(ThemeType.feedMeta)
                    .foregroundStyle(ThemeColor.textPrimary.opacity(0.88))
                    .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                    .shadow(.art)
                    .modifier(rise(2))
            }
            .multilineTextAlignment(.center)
            .allowsHitTesting(false)
            if canToggle {
                ScheduleMarkPill(watched: state.isWatched, label: markLabel, action: onToggle)
                    .modifier(rise(3))
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    private func rise(_ index: Int) -> ScheduleRise {
        ScheduleRise(shown: arrived, delay: Double(index) * ScheduleArrivalMetrics.wordsStep,
                     distance: ScheduleArrivalMetrics.wordsRise, duration: 0.32)
    }

    /// The show's pick, when it is known or becomes known within `pickPatience`; else the
    /// catalogue's picture. Once per show.
    private func settle() async {
        let f = franchise
        if let settled, settled.franchiseId == f.id { return }
        // Grade the show's pictures if nobody has (Home asks for its billboard's and shelf's shows).
        Task { await PosterPick.shared.resolve(f) }
        if PosterPick.shared.choice(for: f) == nil, !PosterPick.candidates(for: f).isEmpty {
            let deadline = ContinuousClock.now + ScheduleCardMetrics.pickPatience
            while PosterPick.shared.choice(for: f) == nil, ContinuousClock.now < deadline, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        guard !Task.isCancelled else { return }
        let next = PosterPick.shared.choice(for: f).map(shown(from:)) ?? catalogue
        PerfProbe.mark("schedule-card-settled", PosterPick.shared.choice(for: f) == nil ? "catalogue" : "pick")
        // The picture already on screen (a stored pick) is kept as it is — an animated no-op
        // transaction here carried the card's first layout pass with it and faded the scrim in.
        if next == storedPick {
            settled = next
        } else {
            withAnimation(ThemeMotion.uiPoster) { settled = next }
        }
    }

    /// The picture's colour and lightness: the glow, the ground the words land on, and how much
    /// protection the words need.
    private func readArt(_ url: String?) async {
        guard let url else { return }
        if let hit = PaletteCache.shared.tint(for: url) {
            if tint != hit { tint = hit }
            lightness = PaletteCache.shared.lightness(for: url)
            return
        }
        let resolved = await PaletteCache.shared.resolveIfAvailable(url: url, maxPixel: 360)
        guard !Task.isCancelled, let resolved else { return }
        withAnimation(ThemeMotion.uiPoster) {
            tint = resolved
            lightness = PaletteCache.shared.lightness(for: url)
        }
    }
}
