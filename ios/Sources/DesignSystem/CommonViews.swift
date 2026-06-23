import SwiftUI

// Section header (the legacy `SectionHead`): optional accent dot, optional SF Symbol icon,
// uppercase label, optional trailing text.
struct SectionHeader: View {
    var dot: Bool = false
    var systemIcon: String? = nil
    let label: String
    var trailing: String? = nil

    var body: some View {
        HStack(spacing: 9) {
            if dot {
                PulsingDot()
            }
            if let systemIcon {
                Image(systemName: systemIcon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.text50)
            }
            Text(label)
                .font(.system(size: 12.5, weight: .semibold))
                .tracking(0.9)
                .textCase(.uppercase)
                .foregroundStyle(Theme.text72)
            if let trailing {
                Spacer(minLength: 8)
                Text(trailing)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.text40)
            }
        }
        .padding(.bottom, 14)
    }
}

// Gently breathing accent dot used in the "Out now" section header.
private struct PulsingDot: View {
    @State private var glowing = false

    var body: some View {
        Circle()
            .fill(Theme.accent)
            .frame(width: 7, height: 7)
            .shadow(color: Theme.accent.opacity(glowing ? 1.0 : 0.45), radius: glowing ? 9 : 4)
            .scaleEffect(glowing ? 1.18 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                    glowing = true
                }
            }
    }
}

// Friendly empty / first-run state with an optional call-to-action.
struct EmptyStateView: View {
    let title: String
    let message: String
    var ctaLabel: String? = nil
    var onCta: (() -> Void)? = nil

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            Text("✦")
                .font(.system(size: 30))
                .foregroundStyle(Theme.accent)
                .shadow(color: Theme.accent.opacity(0.55), radius: 15)
            Text(title)
                .font(.system(size: 21, weight: .semibold))
                .padding(.top, 16)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(Theme.text50)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 290)
                .padding(.top, 9)
            if let ctaLabel, let onCta {
                Button(action: onCta) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus").font(.system(size: 14, weight: .bold))
                        Text(ctaLabel).font(.system(size: 14.5, weight: .semibold))
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, 22)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 70)
        .padding(.bottom, 40)
        .padding(.horizontal, 20)
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.93)
        .animation(.spring(response: 0.5, dampingFraction: 0.78).delay(0.08), value: appeared)
        .onAppear { appeared = true }
    }
}

// Spinner loader.
struct Loader: View {
    @State private var spinning = false
    var body: some View {
        Circle()
            .trim(from: 0, to: 0.75)
            .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            .frame(width: 28, height: 28)
            .rotationEffect(.degrees(spinning ? 360 : 0))
            .animation(.linear(duration: 0.8).repeatForever(autoreverses: false), value: spinning)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 60)
            .onAppear { spinning = true }
    }
}

// Inline banner shown when live data couldn't be reached.
struct RetryBanner: View {
    let onRetry: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            Text("Couldn't reach the server. Showing what's saved.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.text72)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Retry", action: onRetry)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.background)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(Color(hex: 0xF0A24E).opacity(0.2), lineWidth: 1)
        )
        .padding(.top, 16)
    }
}

// Primary accent button (the legacy `.at-btn-primary` filled style).
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Theme.background)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .shadow(color: Theme.accent.opacity(0.3), radius: 12, y: 4)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

// Subtle spring-scale press feedback for tappable cards and rows.
struct SpringPressButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// Pronounced elastic bounce for compact action buttons (steppers, circle buttons).
struct BounceButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.84 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.42), value: configuration.isPressed)
    }
}
