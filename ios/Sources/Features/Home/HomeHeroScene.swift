import SwiftUI
import UIKit
import CoreMotion

// The billboard's GLOW (26 Sep: "The Home Hero has to feel utterly delightful and an eye candy
// without going overboard", then "Glow is sick, let's do that", owner): light and depth, nothing
// added to the page. The poster settles into focus as the launch's curtain lifts, the logo resolves
// out of a blur with a halo of its own light, the art moves slower than the page (scroll) and with
// the phone (tilt), the lockup sits in a pool of the poster's colour, and a mark sends a ring out of
// its pill. Rejected the same day, and deleted: COVER — the show's logo as a masthead IN the
// picture with the poster's subject cut out in front of it (Vision's foreground mask, the Lock
// Screen's depth effect). Striking on One Punch Man and One Piece; it hid "Shadow" behind heads on
// The Eminence in Shadow, and most key visuals fill their top with characters, leaving it nowhere
// to go — the "overboard" the brief ruled out.

// MARK: - Tilt

/// How far the phone leans from how it has been held lately — a slow baseline follows the hand, so
/// the picture recentres over a couple of seconds and only MOVEMENT shows as depth. −1…1 on each
/// axis. Runs only while a billboard is on screen, never under Reduce Motion; a device without
/// motion (the simulator) stays at 0.
@MainActor @Observable
final class HeroTilt {
    static let shared = HeroTilt()

    private(set) var x: Double = 0
    private(set) var y: Double = 0

    @ObservationIgnored private let manager = CMMotionManager()
    @ObservationIgnored private var users = 0
    @ObservationIgnored private var baseRoll: Double?
    @ObservationIgnored private var basePitch: Double = 0

    /// A lean of this many radians from the baseline is a full shift.
    private static let full = 0.30

    func start() {
        users += 1
        guard users == 1, manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30
        baseRoll = nil
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let motion else { return }
            MainActor.assumeIsolated { self?.update(roll: motion.attitude.roll, pitch: motion.attitude.pitch) }
        }
    }

    func stop() {
        users = max(0, users - 1)
        guard users == 0 else { return }
        manager.stopDeviceMotionUpdates()
        if x != 0 || y != 0 { x = 0; y = 0 }
    }

    private func update(roll: Double, pitch: Double) {
        guard let baseRoll else {
            self.baseRoll = roll
            basePitch = pitch
            return
        }
        // The baseline follows the hand (a ~1.5 s time constant at 30 Hz).
        self.baseRoll = baseRoll + (roll - baseRoll) * 0.022
        basePitch += (pitch - basePitch) * 0.022
        let nx = max(-1, min(1, (roll - baseRoll) / Self.full))
        let ny = max(-1, min(1, (pitch - basePitch) / Self.full))
        let sx = x + (nx - x) * 0.25, sy = y + (ny - y) * 0.25
        if abs(sx - x) > 0.004 || abs(sy - y) > 0.004 { x = sx; y = sy }
    }
}

/// A layer shifted with the phone's lean — `amount` points at a full lean. The modifier is the only
/// reader of `HeroTilt`, so a motion sample re-runs this one small body, never the billboard's.
struct TiltShift: ViewModifier {
    let amount: CGFloat

    func body(content: Content) -> some View {
        let tilt = HeroTilt.shared
        content.offset(x: CGFloat(tilt.x) * amount, y: CGFloat(tilt.y) * amount)
    }
}

// MARK: - Arrival

/// The picture settling into focus as it arrives: from 5 % large to its place, as the sharp layer
/// fades in over its blurred ground — a camera finding its mark. Once per billboard.
struct FocusSettle: ViewModifier {
    let settled: Bool
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .scaleEffect(settled || reduceMotion ? 1 : 1.05, anchor: .top)
            .animation(reduceMotion ? nil : .easeOut(duration: 1.1), value: settled)
    }
}

/// A logo resolving out of a soft blur, a touch large — a title card's reveal. The blur is on only
/// for the reveal's second, never at rest.
struct LogoResolve: ViewModifier {
    let shown: Bool
    let reduceMotion: Bool
    var delay: Double = 0.06

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .blur(radius: shown || reduceMotion ? 0 : 12)
            .scaleEffect(shown || reduceMotion ? 1 : 1.04)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.75).delay(delay), value: shown)
    }
}

// MARK: - The mark

/// A ring that leaves the pill once when the mark lands — the receipt's small flourish, drawn
/// behind the pill. Nothing under Reduce Motion.
struct MarkPulse: View {
    let fired: Bool
    let reduceMotion: Bool
    @State private var out = false

    var body: some View {
        Capsule()
            .strokeBorder(ThemeColor.feedText.opacity(out ? 0 : 0.55), lineWidth: 1.5)
            .scaleEffect(x: out ? 1.22 : 1, y: out ? 1.6 : 1)
            .opacity(fired && !reduceMotion ? 1 : 0)
            .onChange(of: fired) { _, now in
                guard now, !reduceMotion else { out = false; return }
                out = false
                withAnimation(.easeOut(duration: 0.65)) { out = true }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// A clip that cuts only BELOW its frame: what is drawn above it (a pull's stretch) is kept.
struct BelowClip: Shape {
    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: rect.minX - 2000, y: rect.minY - 4000, width: rect.width + 4000, height: rect.height + 4000))
    }
}

// MARK: - Light

/// The poster's own light for the pool under the lockup: its dominant colour lifted to a luminous
/// mid-tone (OKLab L 0.62, chroma kept, at most 0.13) — the colour of the picture, glowing, where
/// `DetailTint.ground` keeps only its hue at canvas depth.
enum HeroLight {
    static func glow(_ color: Color?) -> Color? {
        guard let color else { return nil }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        var (_, ca, cb) = PaletteCache.oklab(r: Double(r), g: Double(g), b: Double(b))
        let chroma = (ca * ca + cb * cb).squareRoot()
        if chroma > 0.13 { ca *= 0.13 / chroma; cb *= 0.13 / chroma }
        let (qr, qg, qb) = PaletteCache.srgb(l: 0.62, a: ca, b: cb)
        return Color(.sRGB, red: max(0, min(1, qr)), green: max(0, min(1, qg)), blue: max(0, min(1, qb)), opacity: 1)
    }
}
