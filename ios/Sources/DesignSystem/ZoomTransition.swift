import SwiftUI

// Zoom (hero) transition plumbing for poster/row → detail. Each tappable card registers itself
// as a matched transition source under a surface-scoped id ("lib/<id>", "outnow/<id>", …) — the
// same franchise can be on screen in several tabs at once, and duplicate source ids within one
// namespace are undefined. The detail sheet then zooms out of whichever card was actually tapped
// (see MainTabView), which is Apple's canonical thumbnail → detail pattern.
extension EnvironmentValues {
    @Entry var zoomNamespace: Namespace.ID? = nil
}

extension View {
    /// Marks this view as the zoom-transition source for `id` (no-op outside a zoom namespace).
    func zoomSource(_ id: String) -> some View {
        modifier(ZoomSourceModifier(id: id))
    }
}

private struct ZoomSourceModifier: ViewModifier {
    @Environment(\.zoomNamespace) private var namespace
    let id: String

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedTransitionSource(id: id, in: namespace)
        } else {
            content
        }
    }
}
