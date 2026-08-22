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
