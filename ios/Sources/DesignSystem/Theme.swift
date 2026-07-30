import SwiftUI

// The AniTrack dark palette, ported from the legacy web app's inline styles.
enum Theme {
    static let background = Color(hex: 0x0B0B0E)
    static let surface = Color(hex: 0x16161B)
    static let accent = Color(hex: 0xF0A24E)

    // Text tiers (opacity over #F5F5F7), mirroring the rgba(245,245,247,…) values in App.tsx.
    static let textPrimary = Color(hex: 0xF5F5F7)
    static let text90 = Color(hex: 0xF5F5F7).opacity(0.90)
    static let text72 = Color(hex: 0xF5F5F7).opacity(0.72)
    static let text70 = Color(hex: 0xF5F5F7).opacity(0.70)
    static let text66 = Color(hex: 0xF5F5F7).opacity(0.66)
    static let text62 = Color(hex: 0xF5F5F7).opacity(0.62)
    static let text52 = Color(hex: 0xF5F5F7).opacity(0.52)
    static let text50 = Color(hex: 0xF5F5F7).opacity(0.50)
    static let text46 = Color(hex: 0xF5F5F7).opacity(0.46)
    static let text44 = Color(hex: 0xF5F5F7).opacity(0.44)
    static let text42 = Color(hex: 0xF5F5F7).opacity(0.42)
    static let text40 = Color(hex: 0xF5F5F7).opacity(0.40)
    static let text36 = Color(hex: 0xF5F5F7).opacity(0.36)
    static let text28 = Color(hex: 0xF5F5F7).opacity(0.28)
    static let text26 = Color(hex: 0xF5F5F7).opacity(0.26)

    static let hairline = Color.white.opacity(0.06)
    static let hairlineStrong = Color.white.opacity(0.10)
    static let fillFaint = Color.white.opacity(0.028)
    static let fillSoft = Color.white.opacity(0.04)

    // Accent-tinted fills used by callout cards and "behind" chips.
    static let accentSoft = Color(hex: 0xF0A24E).opacity(0.08)
    static let accentBorder = Color(hex: 0xF0A24E).opacity(0.18)
    static let accentChipFill = Color(hex: 0xF0A24E).opacity(0.13)
    static let accent70 = Color(hex: 0xF0A24E).opacity(0.70)   // date-badge relative line
    static let accentGlow = Color(hex: 0xF0A24E).opacity(0.16) // airing pulse dot, used sparingly

    // The one destructive red in the app (remove-from-library). Previously inlined per-view.
    static let destructive = Color(hex: 0xE5484D)

    // Counts/countdowns: Outfit with monospaced digits requested, so ticking numbers stay on-brand
    // and don't jitter where the font provides tabular figures.
    static func numeric(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        AppFont.font(size: size, weight: weight).monospacedDigit()
    }

    // Corner radii — the redesign's continuous-style rounding. Historically inlined per-view; these
    // name the recurring ones so the mixed anime/TV surfaces round consistently.
    enum Radius {
        static let card: CGFloat = 15
        static let poster: CGFloat = 15
        static let thumb: CGFloat = 9
        static let chip: CGFloat = 12
        static let button: CGFloat = 13
        static let hero: CGFloat = 44
        static let pill: CGFloat = 999
    }

    // Layout rhythm from the handoff (screen gutter, list-row vertical padding, section gap).
    enum Space {
        static let gutter: CGFloat = 20
        static let row: CGFloat = 13
        static let section: CGFloat = 28
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

// AniTrack's motion language — a small set of fluid Liquid-Glass springs used app-wide so every
// surface moves consistently (the biggest lever on "premium feel"). Reach for these instead of
// hand-tuning a new curve per call site.
extension Animation {
    /// State / layout / disclosure changes — the everyday spring.
    static let uiSnappy = Animation.spring(response: 0.34, dampingFraction: 0.84)
    /// Satisfying toggles & pops (watched checks, catch-up) — a touch of overshoot.
    static let uiBouncy = Animation.spring(response: 0.30, dampingFraction: 0.62)
    /// Content settling into place (grids re-bucketing, larger moves) — calm, well-damped.
    static let uiSmooth = Animation.spring(response: 0.46, dampingFraction: 0.90)
    /// Simple cross-fades (loading → content, appear/disappear).
    static let uiGentle = Animation.easeInOut(duration: 0.22)
}
