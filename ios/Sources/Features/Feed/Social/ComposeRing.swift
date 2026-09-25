import SwiftUI

// X's character ring (spec §4.5 step 3): it fills as you type; with twenty left it grows and
// counts down; past the limit the count is negative and the ring turns the destructive red. The
// count is the SERVER's (`SocialText.count`: code points of the NFC, trimmed text), so the ring can
// never pass a reply the server would refuse — a grapheme count would let 280 skin-toned emoji
// through that the server counts as 560.
//
// Amber here is STATE (close to the limit), never an action: the Reply capsule beside it is ink.

struct ComposeRing: View {
    let count: Int
    let limit: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var left: Int { limit - count }
    private var near: Bool { left <= SocialMetrics.ringNearLeft }
    private var over: Bool { left < 0 }
    private var size: CGFloat { near ? SocialMetrics.ringSizeNear : SocialMetrics.ringSize }
    private var ink: Color {
        if over { return ThemeColor.destructive }
        return near ? ThemeColor.accent : ThemeColor.feedText
    }

    var body: some View {
        ZStack {
            Circle().stroke(ThemeColor.feedSeparator, lineWidth: SocialMetrics.ringLine)
            Circle()
                .trim(from: 0, to: min(1, CGFloat(count) / CGFloat(max(1, limit))))
                .stroke(ink, style: StrokeStyle(lineWidth: SocialMetrics.ringLine, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if near {
                Text(left, format: .number)
                    .type(ThemeType.caption)
                    .monospacedDigit()
                    .foregroundStyle(over ? ThemeColor.destructive : ThemeColor.feedSecondary)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .contentTransition(reduceMotion ? ContentTransition.opacity : .numericText(value: Double(left)))
            }
        }
        .frame(width: size, height: size)
        .animation(ThemeMotion.pick(ThemeMotion.uiSnappy, reduceMotion: reduceMotion), value: near)
        .animation(ThemeMotion.pick(ThemeMotion.uiNumeric, reduceMotion: reduceMotion), value: count)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(over ? Copy.Social.charactersOver(-left) : Copy.Social.charactersLeft(left))
    }
}
