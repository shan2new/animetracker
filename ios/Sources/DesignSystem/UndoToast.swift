import SwiftUI

// The pending undo action (mark caught up, or add to library), mirroring the legacy `Undo`.
struct UndoState: Identifiable {
    let id = UUID()
    let mediaId: Int?
    let franchiseId: String?
    let prevProgress: Int
    let title: String
    let episode: Int
    var added: Bool = false
    var statusLabel: String? = nil
    /// A removal: `removedFranchise` is the exact snapshot Undo puts back, with `prevStatus`.
    var removed: Bool = false
    var removedFranchise: Franchise? = nil
    var prevStatus: WatchStatus = .watching
    /// Episodes covered by a batch mark (1 = a single episode).
    var count: Int = 1
    /// Overrides the derived message (board 09 copy table only).
    var customMessage: String? = nil
    /// A custom undo (e.g. restore a reset season); runs instead of `performUndo`.
    var undoAction: (() -> Void)? = nil

    var message: String {
        if let customMessage { return customMessage }
        if removed { return Copy.Toast.removed }
        if added { return Copy.Toast.added(title: title, status: statusLabel ?? "Library") }
        if count > 1 { return Copy.Toast.batchMarked(count) }
        return Copy.Toast.marked(episode: episode)
    }
}

extension UndoState: Equatable {
    static func == (a: UndoState, b: UndoState) -> Bool { a.id == b.id }
}

// The shared toast layer: undo + error toasts stacked above the bottom chrome. A sheet presents
// ABOVE the tab view's ZStack, so this host is mounted in BOTH MainTabView and the detail sheet —
// whichever is frontmost shows the same state, and a toast survives the sheet dismissing.
// Keeping the host always mounted (with `if let` children) also means the insert/remove
// transitions actually animate — the animation lives on this container, not the transient child.
struct ToastHost: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        let sync = SyncCenter.shared
        VStack(spacing: 9) {
            if !sync.failedChanges.isEmpty {
                SyncBanner(count: sync.failedChanges.count, retry: sync.canRetryAny ? { sync.retryAll() } : nil)
                    .frame(maxWidth: 420)
            }
            if let message = appModel.errorToast {
                ErrorToast(message: message)
            }
            if let undo = appModel.undo {
                UndoToast(state: undo) { appModel.undoTapped(undo) }
            }
        }
        .animation(ThemeMotion.uiSnappy, value: sync.failedChanges.count)
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
