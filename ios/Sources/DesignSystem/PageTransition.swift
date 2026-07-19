import SwiftUI

// Smooth, premium "page-in" entrance for a main tab. When a tab becomes the selected one its
// content settles up into place — a gentle vertical rise paired with a fade — while the floating
// tab bar stays put, so switching tabs feels like landing on a fresh page rather than a hard cut.
//
// Driven by the *selection* (`isActive`), not by `onAppear`/`onDisappear`. TabView keeps every tab
// alive and fires those lifecycle callbacks inconsistently, which made an earlier onAppear-based
// version replay unevenly (or not at all) on Today/Schedule. `onChange(of: isActive)` fires
// deterministically for every tab whenever the selection changes, so the entrance is uniform.
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
            .onChange(of: isActive) { _, active in
                if active {
                    withAnimation(entrance) { shown = true }
                } else {
                    // Reset instantly while off-screen so the next visit animates from scratch.
                    shown = false
                }
            }
            // First launch (and a tab's lazy first appearance): animate the active tab in.
            .onAppear { if isActive { withAnimation(entrance) { shown = true } } }
    }
}

extension View {
    /// Applies the shared page-in entrance to a main tab's content. `isActive` is whether this
    /// tab is currently selected. See `PageInTransition`.
    func pageInTransition(isActive: Bool, travel: CGFloat = 10) -> some View {
        modifier(PageInTransition(isActive: isActive, travel: travel))
    }
}
