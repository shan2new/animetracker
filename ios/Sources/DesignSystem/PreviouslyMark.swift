import SwiftUI

/// The Previously. brand mark: a saved-place ribbon with a single progress point.
/// Keep this geometry as the source of truth for every in-app use of the identity.
struct PreviouslyMark: View {
    enum Detail: Equatable {
        case progress
        case none
    }

    let width: CGFloat
    var detail: Detail = .progress
    var progress: CGFloat = 0

    var body: some View {
        let height = width * 1.58
        let slotWidth = width * 0.56
        let slotHeight = width * 0.12
        let clampedProgress = min(max(progress, 0), 1)

        ZStack {
            BookmarkShape()
                .fill(
                    LinearGradient(colors: [Color(hex: 0xFFD6A0), ThemeColor.accent, Color(hex: 0xC9702E)],
                                   startPoint: .topLeading,
                                   endPoint: .bottomTrailing)
                )

            if detail == .progress {
                Capsule()
                    .fill(ThemeColor.canvas)
                    .frame(width: slotWidth, height: slotHeight)
                    .offset(y: -height * 0.24)

                Circle()
                    .fill(Color(hex: 0xFFF0DA))
                    .frame(width: width * 0.10, height: width * 0.10)
                    .offset(x: (-slotWidth * 0.32) + (slotWidth * 0.64 * clampedProgress),
                            y: -height * 0.24)
            }
        }
        .frame(width: width, height: height)
        .accessibilityHidden(true)
    }
}

/// A soft-cornered bookmark with its saved-place notch cut into the bottom edge.
private struct BookmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        let radius = rect.width * 0.17
        let notchApex = rect.height * 0.76
        let edgeBottom = rect.height * 0.96

        var path = Path()
        path.move(to: CGPoint(x: radius, y: 0))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: 0))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: radius),
                          control: CGPoint(x: rect.maxX, y: 0))
        path.addLine(to: CGPoint(x: rect.maxX, y: edgeBottom))
        path.addLine(to: CGPoint(x: rect.midX, y: notchApex))
        path.addLine(to: CGPoint(x: 0, y: edgeBottom))
        path.addLine(to: CGPoint(x: 0, y: radius))
        path.addQuadCurve(to: CGPoint(x: radius, y: 0), control: .zero)
        path.closeSubpath()
        return path
    }
}
