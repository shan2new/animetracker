import SwiftUI

// The pending undo action (mark caught up, or add to library), mirroring the legacy `Undo`.
struct UndoState: Identifiable, Equatable {
    let id = UUID()
    let mediaId: Int?
    let franchiseId: String?
    let prevProgress: Int
    let title: String
    let episode: Int
    var added: Bool = false
    var statusLabel: String? = nil

    var message: String {
        if added {
            return "Added \(title) to \(statusLabel ?? "Library")"
        }
        return "Episode \(episode) marked as watched"
    }
}

// The shared toast layer: undo + error toasts stacked above the bottom chrome. A sheet presents
// ABOVE the tab view's ZStack, so this host is mounted in BOTH MainTabView and the detail sheet —
// whichever is frontmost shows the same state, and a toast survives the sheet dismissing.
// Keeping the host always mounted (with `if let` children) also means the insert/remove
// transitions actually animate — the animation lives on this container, not the transient child.
struct ToastHost: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        VStack(spacing: 9) {
            if let message = appModel.errorToast {
                ErrorToast(message: message)
            }
            if let undo = appModel.undo {
                UndoToast(state: undo) { appModel.performUndo() }
            }
        }
        .animation(ThemeMotion.uiSnappy, value: appModel.undo?.id)
        .animation(ThemeMotion.uiSnappy, value: appModel.errorToast)
    }
}

// Failure toast: persists until dismissed by a new write (spec: failure toasts persist).
struct ErrorToast: View {
    let message: String
    var body: some View {
        ToastView(message: message, failure: true).frame(maxWidth: 420)
    }
}

// Canonical Undo toast (spec board 02): 6 s, one action, lands when the handoff settles.
struct UndoToast: View {
    let state: UndoState
    let onUndo: () -> Void
    var body: some View {
        ToastView(message: state.message, actionLabel: "Undo", action: onUndo).frame(maxWidth: 420)
    }
}
