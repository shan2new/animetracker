import SwiftUI

// Smooth, premium "page-in" entrance for a main tab's FIRST appearance. On cold launch (and each
// tab's first visit) the content settles up into place — a gentle vertical rise paired with a
// fade — while the floating tab bar stays put. It runs ONCE per tab: replaying it on every switch
// turned ordinary tab changes into a 0.42s loading beat, so after the first landing a switch is
// the instant cut native tabs promise (user call, 2026-08-08).
//
// Driven by the *selection* (`isActive`), not by `onAppear`/`onDisappear` alone. TabView keeps
// every tab alive and fires those lifecycle callbacks inconsistently, which made an earlier
// onAppear-based version replay unevenly (or not at all) on Today/Schedule. `onChange(of:
// isActive)` fires deterministically whenever the selection changes, so the one entrance each tab
// gets is uniform no matter how it was mounted.
//
// The franchise detail drawer is a sheet, not a tab, so it never receives this — by design.
private struct PageInTransition: ViewModifier {
    /// True when this view's tab is the selected one.
    let isActive: Bool
    /// How far the content rises from, in points. Kept small so the motion reads as a settle —
    /// 6, not 10: at 10 the first landing reads as content sliding into place, which is a loading
    /// beat; at 6 it reads as the screen coming into focus.
    var travel: CGFloat = 6
    /// Whether the entrance fades. The launch's arrival is revealed by the ident's ground
    /// lifting, so the content itself only rises: an opacity ramp over the whole hero tree is an
    /// offscreen pass on every frame, and it cost the launch's flight its frames.
    var fadeIn = true
    @State private var shown = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // A non-overshooting "smooth" spring: no wobble, no directional bounce — just a calm landing.
    private var entrance: Animation {
        ThemeMotion.pick(ThemeMotion.uiReveal, reduceMotion: reduceMotion)
    }

    func body(content: Content) -> some View {
        content
            .opacity(shown || !fadeIn ? 1 : 0)
            // Under Reduce Motion the entrance is a pure crossfade: nothing travels.
            .offset(y: shown || reduceMotion ? 0 : travel)
            // `shown` is never reset — that's the once-only guarantee.
            .onChange(of: isActive) { _, active in
                if active, !shown { withAnimation(entrance) { shown = true } }
            }
            // First launch (and a tab's lazy first appearance): animate the active tab in.
            .onAppear { if isActive, !shown { withAnimation(entrance) { shown = true } } }
    }
}

extension View {
    /// Applies the shared page-in entrance to a main tab's content, once per tab. `isActive` is
    /// whether this tab is currently selected. See `PageInTransition`.
    func pageInTransition(isActive: Bool, travel: CGFloat = 6, fadeIn: Bool = true) -> some View {
        modifier(PageInTransition(isActive: isActive, travel: travel, fadeIn: fadeIn))
    }
}
