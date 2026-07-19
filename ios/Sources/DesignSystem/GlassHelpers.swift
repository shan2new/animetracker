import SwiftUI

// Liquid Glass (iOS 26) helpers, each gated behind `if #available(iOS 26.0, *)` with a graceful
// `.ultraThinMaterial` fallback so the project still compiles and runs on iOS 17–25.
//
// Glass is applied ONLY to the navigation/functional chrome (tab bar, toolbars, sheet headers,
// floating action buttons, the "mark caught up" buttons, chips) — never stacked on poster/content
// cards. Adjacent glass elements should be wrapped in a GlassEffectContainer by the caller.

extension View {
    /// Glass background clipped to a shape, for chrome surfaces (chips, header bars, callouts).
    @ViewBuilder
    func glassChrome(in shape: some Shape, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            if interactive {
                self.glassEffect(.regular.interactive(), in: shape)
            } else {
                self.glassEffect(.regular, in: shape)
            }
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }

    /// Tinted glass for accent-forward callouts (e.g. the "next episode airs" panel).
    @ViewBuilder
    func glassTinted(_ tint: Color, in shape: some Shape) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.tint(tint), in: shape)
        } else {
            self.background(tint.opacity(0.4), in: shape)
                .background(.ultraThinMaterial, in: shape)
        }
    }
}

// A circular icon button rendered as glass chrome (close button, floating "+"/check actions).
// Press feedback comes from the glass button style itself — an earlier DragGesture
// (minimumDistance: 0) bounce fired on every touch-down, including scrolls over the button.
struct GlassCircleButton: View {
    let systemName: String
    var size: CGFloat = 40
    var iconSize: CGFloat = 18
    var tint: Color? = nil
    var foreground: Color = Theme.textPrimary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(width: size, height: size)
        }
        .buttonStyleGlass(tint: tint)
        .clipShape(Circle())
    }
}

extension View {
    /// `.buttonStyle(.glass)` (or prominent when tinted) on iOS 26, plain fallback otherwise.
    @ViewBuilder
    func buttonStyleGlass(tint: Color? = nil) -> some View {
        if #available(iOS 26.0, *) {
            if let tint {
                self.buttonStyle(.glassProminent).tint(tint)
            } else {
                self.buttonStyle(.glass)
            }
        } else {
            if let tint {
                self.background(tint, in: Circle())
            } else {
                self.background(.ultraThinMaterial, in: Circle())
            }
        }
    }
}

// A glass container wrapper that morphs adjacent glass shapes together on iOS 26.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder var content: () -> Content

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content() }
        } else {
            content()
        }
    }
}
