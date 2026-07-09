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

    // Counts/countdowns: Outfit with monospaced digits requested, so ticking numbers stay on-brand
    // and don't jitter where the font provides tabular figures.
    static func numeric(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        AppFont.font(size: size, weight: weight).monospacedDigit()
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
