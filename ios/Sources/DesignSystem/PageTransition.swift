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
    /// How far the content rises from, in points. Kept small so the motion reads as a settle.
    var travel: CGFloat = 10
    @State private var shown = false

    // A non-overshooting "smooth" spring: no wobble, no directional bounce — just a calm landing.
    private var entrance: Animation { .smooth(duration: 0.42) }

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : travel)
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
    func pageInTransition(isActive: Bool, travel: CGFloat = 10) -> some View {
        modifier(PageInTransition(isActive: isActive, travel: travel))
    }
}
