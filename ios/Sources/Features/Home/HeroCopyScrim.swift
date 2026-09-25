import SwiftUI

// Restored from the retired Today billboard (git c78fe84^, DesignSystem/Primitives.swift) for Home's
// billboard — the one scrim that LANDS on canvas whatever the copy's height.

///
/// The stops are placed in POINTS off the measured copy height, not as fractions of the image. A
/// fixed fraction is a different physical distance at every type size, which is how AX1 came to
/// set a three-line 44-pt title over a face at ~55 % luminance while the same stops were
/// comfortable at default size. `lead` is the run-in above the copy — long, because this is the
/// only bottom protection on a resting billboard (the fractional `ArtScrim` is off), and without
/// pre-darkening a 24-pt rise to 0.72 read as a visible edge drawn across the picture. Apple TV's
/// billboard gradient has the same shape: it begins just above the lockup and eases in.
///
/// **The copy sits ON the picture, not in a void (4 Sep).** The stops used to reach 0.72 at the
/// copy's top edge and 0.90 fifty-six points in, so the whole lower third of the billboard was
/// canvas with type in it and the art stopped where the words began — the seam the user
/// photographed ("the top 1/3 looks gorgeous … as soon as the Today part starts it looks really
/// bad"). Now the run-in is longer (132) and the veil is 0.56 where the eyebrow sits, 0.72 at
/// the title's first line, 0.86 where the fact line ends, and still lands on full canvas at the
/// frame's bottom: the art stays visible behind the lockup the way it does under Apple TV's,
/// and a 28-pt bold title with its contact shadow holds ≥3:1 on the palest cover.
struct HeroCopyScrim: View {
    let copyHeight: CGFloat
    var lead: CGFloat = 132
    /// `HeroProtection.strength(lightness:)`: the ramp's body scales with the art's lightness;
    /// the LANDING does not — the frame still ends on full canvas whatever the picture.
    var strength: Double = 1
    /// The colour the frame lands on: canvas on Today; the show's ground on its page (6 Sep).
    var landing: Color = ThemeColor.canvas

    private var height: CGFloat { max(1, copyHeight + lead + 8) }

    /// The stops as DISTANCES down the scrim, clamped monotonic. The ramp reaches full canvas
    /// 40 pt above the frame's bottom whatever the copy's height: the last 5 % of the art's
    /// ground — and the tonal step where the composited cover ends on it — showed as a faint
    /// dithered band under the capsule (measured 4 Sep). The scrim must LAND, not hover.
    private var stops: [Gradient.Stop] {
        let h = height
        // Where the veil must be full canvas: 40 pt above the frame's bottom. Every ramp mark is
        // bounded by a share of that distance, so a SHORT copy compresses the ramp instead of
        // pushing the landing off the end. With the marks clamped only to `h`, a one-line copy
        // (h = 174) put 0.72 at 92 % and 0.86 at the last pixel and never reached canvas —
        // Re:ZERO's copyright line printed through and the hero ended on a hard step, luminance
        // 45 → 27 in one row (measured 5 Sep). A tall copy is unchanged.
        let land = max(1, h - 40)
        // The ramp's body scales with the strength, each stop above a FLOOR that keeps the last
        // stretch to the landing a ramp and not a step: at the least strength the stops run
        // 0.03 / 0.10 / 0.20 / 0.35 / 0.55 / 0.80 / 1 — the picture stays lit behind the copy
        // and the frame still eases onto canvas.
        let s = strength
        func a(_ full: Double, floor: Double) -> Double { max(full * s, floor) }
        // The last stretch to full canvas is never shorter than `tail`: with the 0.95 mark
        // clamped to `land` itself, a short copy (≤ 160 pt, any lockup without actions) put two
        // stops on one point and the frame ended on a hard seam — (21,36,46) → (0,26,44) in
        // 1.5 pt on 3 Body Problem (review i4, N4). Every earlier mark is a share of what is left.
        let tail = min(32, land * 0.2)
        let body = land - tail
        let marks: [(y: CGFloat, alpha: Double)] = [
            (0, 0),
            (min(lead * 0.35, body * 0.25), a(0.08, floor: 0)),
            (min(lead * 0.70, body * 0.50), a(0.28, floor: 0)),
            (min(lead, body * 0.72), a(0.56, floor: 0.20)),
            (min(lead + 28, body * 0.84), a(0.72, floor: 0.35)),
            (min(lead + 72, body * 0.95), a(0.86, floor: 0.55)),
            (min(lead + 128, body), a(0.95, floor: 0.80)),
            (land, 1), (h, 1),
        ]
        var out: [Gradient.Stop] = []
        var last: CGFloat = 0
        for mark in marks {
            last = max(last, min(max(0, mark.y), h))
            out.append(.init(color: mark.alpha == 0 ? .clear : landing.opacity(mark.alpha),
                             location: last / h))
        }
        return out
    }

    var body: some View {
        LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom)
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
