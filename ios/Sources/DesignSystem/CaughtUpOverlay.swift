import SwiftUI

// The shared "just caught up" celebration overlay — a popping accent disc with a drawn checkmark
// and an expanding ring, over a blurred scrim. Ports the legacy CSS keyframes.
struct CaughtUpOverlay: View {
    var size: CGFloat = 52

    @State private var discScale: CGFloat = 0.2
    @State private var discOpacity: Double = 0
    @State private var ringScale: CGFloat = 0.6
    @State private var ringOpacity: Double = 1
    @State private var checkTrim: CGFloat = 0

    var body: some View {
        ZStack {
            Color.background70
                .background(.ultraThinMaterial)

            // Expanding ring.
            Circle()
                .stroke(Theme.accent, lineWidth: 2)
                .frame(width: size + 10, height: size + 10)
                .scaleEffect(ringScale)
                .opacity(ringOpacity)

            // Popping disc with drawn checkmark.
            ZStack {
                Circle()
                    .fill(Theme.accent)
                    .frame(width: size, height: size)
                    .shadow(color: Theme.accent.opacity(0.7), radius: 15)
                CheckmarkShape()
                    .trim(from: 0, to: checkTrim)
                    .stroke(Theme.background, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .frame(width: size * 0.52, height: size * 0.52)
            }
            .scaleEffect(discScale)
            .opacity(discOpacity)
        }
        .transition(.opacity)
        .onAppear {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.55)) {
                discScale = 1
                discOpacity = 1
            }
            withAnimation(.easeOut(duration: 0.75)) {
                ringScale = 1.25
                ringOpacity = 0
            }
            withAnimation(.easeOut(duration: 0.4).delay(0.12)) {
                checkTrim = 1
            }
        }
    }
}

// A checkmark path normalized to a unit-ish box (the legacy "M5 13l4 4L19 7").
struct CheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        // Map the 24x24 viewBox points (5,13)(9,17)(19,7) into rect.
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x / 24 * w, y: rect.minY + y / 24 * h)
        }
        p.move(to: pt(5, 13))
        p.addLine(to: pt(9, 17))
        p.addLine(to: pt(19, 7))
        return p
    }
}

extension Color {
    static let background70 = Theme.background.opacity(0.7)
}
