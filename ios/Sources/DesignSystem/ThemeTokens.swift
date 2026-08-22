import SwiftUI
import UIKit

// The interaction-system tokens (spec v8, board 10/11). Exact values, no ranges. The legacy
// `Theme` statics stay for screens not yet migrated; new surfaces use these namespaces only.

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

enum ThemeColor {
    // Canvas
    static let canvas = Color(hex: 0x09090B)
    static let canvasRaised = Color(hex: 0x0D0E11)
    // Opaque content surfaces
    static let surfaceFlat = Color(hex: 0x121318)
    static let surfaceRaised = Color(hex: 0x181A20)
    static let surfaceFloating = Color(hex: 0x202229)
    static let surfacePressed = Color(hex: 0x282A32)
    // Text
    static let textPrimary = Color(hex: 0xF4F1EC)
    static let textSecondary = Color(hex: 0xAAA6A0)
    static let textTertiary = Color(hex: 0x85817C)
    static let textDisabled = Color(hex: 0x6C6965)
    // Brand
    static let accent = Color(hex: 0xF0A24E)
    static let accentPressed = Color(hex: 0xD88D3B)
    static let accentSoft = Color(hex: 0xF0A24E).opacity(0.14)
    static let onAccent = Color(hex: 0x0B0B0D)
    // Semantic
    static let success = Color(hex: 0x30D158)
    static let warning = Color(hex: 0xFFD60A)
    static let destructive = Color(hex: 0xFF453A)
    static let information = Color(hex: 0x64D2FF)
    // Structure
    static let separator = Color.white.opacity(0.08)
    static let stroke = Color.white.opacity(0.12)
    static let strokeStrong = Color.white.opacity(0.20)
    static let skeleton = Color(hex: 0xF4F1EC).opacity(0.08)
    static let focusRing = Color(hex: 0xF0A24E).opacity(0.70)
    // Overlays
    static let scrim = Color.black.opacity(0.56)
    static let scrimStrong = Color.black.opacity(0.72)

    // MARK: - Edges (polish pass)
    //
    // On a #09090B ground an outline all the way round a card is the cheapest possible way to say
    // "this is a surface" — it is what a wireframe does. A premium dark UI separates surfaces by
    // TONE and lights their top edge, the way a physical object catches light. These four tokens
    // exist so no screen ever reaches for `stroke` to make a card visible again.

    /// 1-px highlight along the TOP edge of a raised surface, fading out by its vertical centre.
    /// This is the only "stroke" a content card is allowed.
    static let hairline = Color.white.opacity(0.055)
    /// Divider INSIDE a plate. `separator` (0.08) repeated eight times down one list reads as a
    /// spreadsheet; at 0.045 the eye reads grouping instead of ruling.
    static let separatorQuiet = Color.white.opacity(0.045)
    /// The edge of artwork. Never `stroke` — a 12 %-white outline around a bright poster is a
    /// picture frame, and around a dark poster it is a glow. Just enough to stop art bleeding
    /// into the canvas.
    static let posterEdge = Color.white.opacity(0.05)
    /// The bottom of a full-bleed ambient backdrop, where art hands over to the canvas.
    static let backdropFade = canvas
    /// The veil that hides scrolling content as it approaches the status bar. Full canvas, so the
    /// handover is invisible: content does not slide *under a grey bar*, it dissolves into the app.
    static let chromeVeil = canvas
    /// The light along the top edge of a filled control (the accent capsule, a chip). An orange
    /// rectangle is a swatch; an orange rectangle with a lit top edge is an object.
    static let controlSheen = Color.white.opacity(0.22)
}

// MARK: - Elevation

/// A shadow is one token, never three numbers at a call site. On a near-black canvas a shadow is
/// not "depth" on its own — it is the soft contact edge under a card whose FILL already separates
/// it. Never apply one to a surface that has no tone of its own.
struct ShadowToken {
    let color: Color
    let radius: CGFloat
    let y: CGFloat

    static let none = ShadowToken(color: .clear, radius: 0, y: 0)
    /// Content card sitting on the canvas or on a plate.
    static let card = ShadowToken(color: .black.opacity(0.45), radius: 18, y: 10)
    /// Artwork: posters and stills read as physical objects, so their shadow is tighter and darker.
    static let art = ShadowToken(color: .black.opacity(0.55), radius: 12, y: 7)
    /// A hero poster, which is the largest object on its screen.
    static let artHero = ShadowToken(color: .black.opacity(0.60), radius: 26, y: 14)
    /// Toast, sync banner, anything that floats over content it must not be mistaken for.
    static let floating = ShadowToken(color: .black.opacity(0.50), radius: 26, y: 14)
}

extension View {
    /// `.shadow(.card)` — the only sanctioned way to cast a shadow.
    func shadow(_ token: ShadowToken) -> some View {
        shadow(color: token.color, radius: token.radius, y: token.y)
    }
}

enum ThemeSpace {
    static let x0_5: CGFloat = 2
    static let x1: CGFloat = 4
    static let x2: CGFloat = 8
    static let x3: CGFloat = 12
    static let x4: CGFloat = 16
    static let x5: CGFloat = 20
    static let x6: CGFloat = 24
    static let x8: CGFloat = 32
    static let x10: CGFloat = 40
    static let x12: CGFloat = 48
    static let x16: CGFloat = 64
}

enum ThemeRadius {
    static let episodeStill: CGFloat = 8
    static let poster: CGFloat = 10
    static let compactControl: CGFloat = 12
    static let row: CGFloat = 16
    static let toast: CGFloat = 18
    static let card: CGFloat = 22
    static let focusCard: CGFloat = 24
}

// MARK: - Rhythm

/// Spacing is a scale (`ThemeSpace`); RHYTHM is which step a given relationship gets. Every screen
/// used 16 for everything, which is why the shipped build reads as a settings table: a section
/// break, a card gap and a title-to-metadata gap cannot all be the same distance and still say
/// anything. These are the relationships, named once.
enum ThemeMetrics {
    /// Screen side margin. Content, section labels and card edges all align to it.
    static let gutter: CGFloat = 16
    /// Between two SECTIONS. Big enough that the eye takes a breath and re-orients.
    static let sectionGap: CGFloat = 30
    /// Section label → the first thing under it. The label belongs to what follows.
    static let labelGap: CGFloat = 10
    /// Between two sibling cards inside one section.
    static let cardGap: CGFloat = 10
    /// Between shelf items.
    static let shelfGap: CGFloat = 12
    /// Title → its own metadata line. Tight: they are one thought.
    static let titleGap: CGFloat = 3
    /// Art → the text it belongs to.
    static let artGap: CGFloat = 14
    /// Below a hero, before the first content block.
    static let heroClearance: CGFloat = 26
    /// Bottom inset that clears the floating tab bar.
    static let tabBarClearance: CGFloat = 108

    // Row heights. A row's height is set by its ART, not by a hairline grid: 68 pt everywhere is
    // what makes a media app look like a list of settings.
    /// Text-only or 40-pt-art rows (menus, selection lists).
    static let rowCompact: CGFloat = 56
    /// The standard media row: 48×72 poster.
    static let rowStandard: CGFloat = 88
    /// The heavier media row: 56×84 poster, two-line title allowed.
    static let rowMedia: CGFloat = 100
    /// Episode row carrying a 96×54 still.
    static let rowEpisode: CGFloat = 78

    // MARK: Chrome edges
    //
    // Every root screen in the shipped build scrolls its content straight through the status bar:
    // a poster and a show title sit on top of the clock and the battery with nothing between them.
    // No shipping media app does this. The fix is systemic, not per-screen — see `scrollEdgeChrome`.

    /// The device's status-bar inset, read once from the key window and cached. 59 pt is the
    /// modern Dynamic Island default and is only used before a window exists.
    ///
    /// A `GeometryReader` cannot supply this: the chrome is an OVERLAY on a view that already sits
    /// inside the safe area, so its proxy reports an inset of zero. Reading the window is the
    /// honest way to know how tall the band the clock lives in actually is.
    nonisolated(unsafe) private static var cachedTopInset: CGFloat?

    static var topSafeInset: CGFloat {
        if let cachedTopInset { return cachedTopInset }
        guard Thread.isMainThread else { return 59 }
        let value = MainActor.assumeIsolated { () -> CGFloat in
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
            let inset = scene?.windows.first(where: \.isKeyWindow)?.safeAreaInsets.top
                ?? scene?.windows.first?.safeAreaInsets.top ?? 0
            return inset > 0 ? inset : 59
        }
        // Only cache a real measurement; a pre-window 59 must not become permanent.
        if value != 59 { cachedTopInset = value }
        return value
    }

    /// How far BELOW the status bar the veil takes to disappear. Short and hard on purpose: it
    /// must clear a large title that sits just underneath, so it may not be a lazy 120-pt wash.
    static let topChromeRamp: CGFloat = 22
    /// Total height of the top chrome, safe area included.
    static var topChromeHeight: CGFloat { topSafeInset + topChromeRamp }
    /// The soft landing above the floating tab bar. Never fully opaque — the tab bar is glass and
    /// must keep something to refract.
    static let bottomChromeHeight: CGFloat = 116
}

/// Artwork slots, named by CONTEXT rather than by number, so no screen has to remember that a
/// library row is 48×72 and a search row is 60×90. Art is this product's only real material —
/// every one of these is at or above the size the shipped build used, never below.
enum PosterSize {
    /// Detail hero. The largest identity object in the app.
    case hero
    /// Today's Focus / Recap card.
    case focus
    /// Library "Returning" shelf, Search trending.
    case shelfLarge
    /// Today "Watching" shelf.
    case shelfMedium
    /// A search result row.
    case searchRow
    /// The standard library / schedule row.
    case row
    /// Today's queue rows and Schedule's compact rows.
    case queue
    /// A recap beat — the smallest slot that still reads as a show.
    case beat

    var size: CGSize {
        switch self {
        case .hero: return CGSize(width: 112, height: 168)
        case .focus: return CGSize(width: 88, height: 132)
        case .shelfLarge: return CGSize(width: 116, height: 174)
        case .shelfMedium: return CGSize(width: 100, height: 150)
        case .searchRow: return CGSize(width: 60, height: 90)
        case .row: return CGSize(width: 48, height: 72)
        case .queue: return CGSize(width: 44, height: 66)
        case .beat: return CGSize(width: 34, height: 51)
        }
    }

    /// Radius tracks size: a 10-pt radius on a 34-pt slot is a blob, on a 112-pt slot it is sharp.
    var radius: CGFloat {
        switch self {
        case .hero, .shelfLarge, .shelfMedium: return 12
        case .focus, .searchRow: return 10
        case .row, .queue: return 8
        case .beat: return 6
        }
    }

    /// Only art large enough to read as an object earns a contact shadow.
    var shadow: ShadowToken {
        switch self {
        case .hero: return .artHero
        case .focus, .shelfLarge, .shelfMedium: return .art
        case .searchRow, .row, .queue, .beat: return .none
        }
    }
}

/// Type tokens. Outfit carries identity (wordmark, show titles); SF Pro carries information.
/// Outfit scales with Dynamic Type through `relativeTo:`; SF tokens are system text styles.
struct TypeToken {
    let font: Font
    let tracking: CGFloat
}

enum ThemeType {
    static let brandWordmark = TypeToken(font: .custom("Outfit-SemiBold", size: 20, relativeTo: .headline), tracking: -0.30)
    static let displayXL = TypeToken(font: .custom("Outfit-Bold", size: 34, relativeTo: .largeTitle), tracking: -0.80)
    static let displayL = TypeToken(font: .custom("Outfit-Bold", size: 28, relativeTo: .title), tracking: -0.60)
    static let showTitleL = TypeToken(font: .custom("Outfit-SemiBold", size: 22, relativeTo: .title2), tracking: -0.35)
    static let showTitleM = TypeToken(font: .custom("Outfit-SemiBold", size: 17, relativeTo: .headline), tracking: -0.20)
    static let showTitleS = TypeToken(font: .custom("Outfit-Medium", size: 15, relativeTo: .subheadline), tracking: -0.10)
    static let screenTitle = TypeToken(font: .system(.largeTitle, weight: .bold), tracking: -0.50)
    static let sectionTitle = TypeToken(font: .system(.title3, weight: .semibold), tracking: -0.20)
    static let body = TypeToken(font: .body, tracking: 0)
    static let bodyEmphasis = TypeToken(font: .system(.body, weight: .semibold), tracking: 0)
    static let button = TypeToken(font: .system(.callout, weight: .semibold), tracking: 0)
    static let callout = TypeToken(font: .callout, tracking: 0)
    static let metadata = TypeToken(font: .footnote, tracking: 0)
    static let metadataEmphasis = TypeToken(font: .system(.footnote, weight: .semibold), tracking: 0)
    static let sectionLabel = TypeToken(font: .system(.caption2, weight: .semibold), tracking: 1.0)
    static let caption = TypeToken(font: .caption2, tracking: 0)
    static let numberXL = TypeToken(font: .system(.largeTitle, weight: .bold).monospacedDigit(), tracking: -0.50)
    static let time = TypeToken(font: .system(.subheadline, weight: .semibold).monospacedDigit(), tracking: 0)
}

// MARK: - Type by context
//
// The tokens above are a PALETTE. This extension is the ASSIGNMENT: which token a thing gets
// because of where it sits. The shipped build set every title to `showTitleM` and every second
// line to `metadata`, at every altitude, which is why nothing on any screen was allowed to be the
// hero and nothing was allowed to be quiet.
//
//   HERO   (one per screen, the thing the screen is about)
//     title      heroTitle     Outfit Bold 28 / textPrimary
//     eyebrow    sectionLabel  SF 11 semibold +1.0 / textTertiary — above the title, never below
//     meta       heroMeta      SF 15 / textSecondary
//
//   CARD   (the one card that carries an action)
//     title      showTitleL    Outfit SemiBold 22 / textPrimary
//     fact       cardFact      SF 15 semibold / textPrimary  ← the fact is NOT grey
//     support    metadata      SF 13 / textTertiary
//
//   ROW    (repeating, scannable)
//     title      rowTitle      Outfit SemiBold 17 / textPrimary, 1 line (2 at AX)
//     meta       rowMeta       SF 13 / textSecondary
//     forward    rowMetaLead   SF 13 semibold / accent — only a real next step earns amber
//
//   SHELF  (poster + caption)
//     title      shelfTitle    Outfit Medium 15 / textPrimary, exactly 2 reserved lines
//     caption    shelfCaption  SF 12 medium / textSecondary (accent when it is a next step)
//
//   LABEL
//     section    sectionLabel  SF 11 semibold +1.0 / textTertiary
//     count      sectionLabel  / textDisabled
//     action     listAction    SF 13 semibold / accent  ← "See all" is a link, not a button
extension ThemeType {
    /// Detail hero. Identity gets the biggest cut in the app after the wordmark.
    static let heroTitle = TypeToken(font: .custom("Outfit-Bold", size: 28, relativeTo: .title), tracking: -0.55)
    /// The genre/network/year line under a hero title.
    static let heroMeta = TypeToken(font: .system(.subheadline), tracking: 0)
    /// The single load-bearing fact on a card ("Season 7 · Episode 2"). Primary, not secondary:
    /// a fact the whole card exists to deliver may not be rendered in the same grey as its footnote.
    static let cardFact = TypeToken(font: .system(.subheadline, weight: .semibold), tracking: 0)
    /// Repeating media row title.
    static let rowTitle = TypeToken(font: .custom("Outfit-SemiBold", size: 17, relativeTo: .headline), tracking: -0.20)
    /// Repeating media row metadata.
    static let rowMeta = TypeToken(font: .footnote, tracking: 0)
    /// A row's forward-looking fact — "Returns Oct 2", "Episode 19 next". Rendered in accent.
    static let rowMetaLead = TypeToken(font: .system(.footnote, weight: .semibold), tracking: 0)
    /// Shelf caption under a poster.
    static let shelfTitle = TypeToken(font: .custom("Outfit-Medium", size: 15, relativeTo: .subheadline), tracking: -0.10)
    static let shelfCaption = TypeToken(font: .system(.caption, weight: .medium), tracking: 0)
    /// An inline text action in a section header ("See all", "Clear"). Deliberately smaller than
    /// `button`: a 16-pt semibold amber word beside an 11-pt grey label wins a fight it should lose.
    static let listAction = TypeToken(font: .system(.footnote, weight: .semibold), tracking: 0)
    /// Schedule day headers — a shade larger than `sectionLabel` because they carry the date.
    static let dayLabel = TypeToken(font: .system(.caption, weight: .semibold), tracking: 0.7)
}

extension View {
    func type(_ token: TypeToken) -> some View {
        self.font(token.font).tracking(token.tracking)
    }
}

extension Text {
    func type(_ token: TypeToken) -> Text {
        self.font(token.font).tracking(token.tracking)
    }
}

/// Motion tokens (board 11). `uiBouncy` / `uiSmooth` from the older Theme are superseded.
enum ThemeMotion {
    /// Touch compression only.
    static let uiPress = Animation.easeOut(duration: 0.09)
    /// Checkmarks, icon replacement, chip selection, status change.
    static let uiMicro = Animation.spring(response: 0.22, dampingFraction: 0.88, blendDuration: 0)
    /// Fast local layout changes and user-requested expansion.
    static let uiSnappy = Animation.spring(response: 0.34, dampingFraction: 0.84, blendDuration: 0)
    /// Large but controlled card-to-card or source-to-destination motion.
    static let uiSettle = Animation.spring(response: 0.46, dampingFraction: 0.90, blendDuration: 0)
    /// One restrained overshoot for a meaningful milestone (series complete only).
    static let uiMilestone = Animation.spring(response: 0.38, dampingFraction: 0.74, blendDuration: 0)
    /// State fades, stale strips, error notices, NOW movement.
    static let uiGentle = Animation.easeInOut(duration: 0.22)
    /// Initial content reveal.
    static let uiReveal = Animation.timingCurve(0.22, 1.00, 0.36, 1.00, duration: 0.28)
    /// Poster tint to final image.
    static let uiPoster = Animation.easeOut(duration: 0.18)
    /// Numeric content transition.
    static let uiNumeric = Animation.easeOut(duration: 0.22)
    /// Season-complete hairline, History rail.
    static let uiSweep = Animation.timingCurve(0.40, 0.00, 0.20, 1.00, duration: 0.52)
    /// Toast dismissal only.
    static let uiDismiss = Animation.easeIn(duration: 0.16)
    /// Wordmark live indicator.
    static let uiLiveBreath = Animation.easeInOut(duration: 1.80).repeatForever(autoreverses: true)
    /// Universal Reduce Motion fallback.
    static let uiReduced = Animation.easeOut(duration: 0.12)

    /// The token, or the Reduce Motion fallback when the setting is on.
    static func pick(_ token: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? uiReduced : token
    }
}

/// Every haptic in the app goes through here. One-sentence justification per token (board 11).
enum FeedbackToken {
    case selection      // a discrete selected value changed
    case commitLight    // one watch fact recorded on this device
    case commitMedium   // a larger contiguous progress change recorded
    case success        // season/series complete · title added · rewatch started
    case destructive    // an irreversible deletion was accepted
    case refreshArmed   // releasing now will refresh
    case directError    // an explicit action failed
}

@MainActor
enum FeedbackCoordinator {
    private static var lastFire: TimeInterval = 0
    private static let minInterval: TimeInterval = 0.3
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let notify = UINotificationFeedbackGenerator()
    private static let select = UISelectionFeedbackGenerator()

    /// Haptics: On / Off (Accessibility). System settings remain authoritative.
    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "previously.haptics") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "previously.haptics") }
    }

    /// Fires at most one feedback event per 300 ms, never while the app is inactive.
    static func fire(_ token: FeedbackToken) {
        guard enabled, UIApplication.shared.applicationState == .active else { return }
        let now = Date().timeIntervalSinceReferenceDate
        guard now - lastFire >= minInterval else { return }
        lastFire = now
        switch token {
        case .selection: select.selectionChanged(); select.prepare()
        case .commitLight: light.impactOccurred(intensity: 0.65); light.prepare()
        case .commitMedium: medium.impactOccurred(intensity: 0.72); medium.prepare()
        case .success: notify.notificationOccurred(.success); notify.prepare()
        case .destructive: notify.notificationOccurred(.warning); notify.prepare()
        case .refreshArmed: light.impactOccurred(intensity: 0.50); light.prepare()
        case .directError: notify.notificationOccurred(.error); notify.prepare()
        }
    }
}
