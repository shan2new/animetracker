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
        // The subject-carrying forms: the same toast fires from Today, a Schedule row and a Library
        // context menu, and "Episode 2 marked as watched" cannot say which show it means.
        if count > 1 { return Copy.Toast.batchMarked(title: title, count) }
        return Copy.Toast.marked(title: title, episode: episode)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        // `pick`, so a toast does not still spring in with a 4-pt rise under Reduce Motion — the
        // three shipped calls were raw `uiSnappy`. `uiDismiss` was minted at ThemeTokens:376 for
        // exactly this moment and had zero call sites: a toast that leaves on the same spring it
        // arrived on reads as a bounce out, not a dismissal.
        .animation(ThemeMotion.pick(ThemeMotion.uiSnappy, reduceMotion: reduceMotion),
                   value: sync.failedChanges.count)
        .animation(ThemeMotion.pick(ThemeMotion.uiSnappy, reduceMotion: reduceMotion),
                   value: appModel.undo?.id)
        .animation(ThemeMotion.pick(ThemeMotion.uiSnappy, reduceMotion: reduceMotion),
                   value: appModel.errorToast)
        // A VoiceOver user was never told the toast existed, let alone that Undo was available for
        // the next six (or ten) seconds.
        .onChange(of: appModel.undo?.id) { _, _ in
            guard let undo = appModel.undo else { return }
            Announce.status("\(undo.message). \(Copy.Action.undo) available.")
        }
        .onChange(of: appModel.errorToast) { _, message in
            if let message { Announce.status(message) }
        }
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
        ToastView(message: state.message, actionLabel: Copy.Action.undo, action: onUndo)
            .frame(maxWidth: 420)
    }
}
