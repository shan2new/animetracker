import SwiftUI

// The write transactions that need more than one AppModel call to be correct. Kept out of
// AppModel.swift so every screen (Library rows, the context menu, Detail's overflow) calls one
// canonical mechanism instead of three near-copies.
extension AppModel {

    // MARK: - Remove from Library

    /// Remove a show, with Undo. No confirmation dialog: remove is reversible for 6 s (10 s under
    /// VoiceOver) and never touches watch history — the server deletes only the subscription row,
    /// so every progress row survives and Undo brings the ticks back exactly.
    /// One haptic for the whole transaction (`.commitLight`), fired inside `removeFromLibrary`.
    func removeWithUndo(_ f: Franchise, reduceMotion: Bool) {
        let snapshot = f.snapshotForUndo
        let previousStatus = f.effectiveStatus
        withAnimation(ThemeMotion.pick(ThemeMotion.uiSettle, reduceMotion: reduceMotion)) {
            removeFromLibrary(franchiseId: f.id, haptic: true)
        }
        // Presented immediately: unlike a mark, a removal has no handoff to wait for.
        presentUndo(UndoState(mediaId: nil, franchiseId: f.id, prevProgress: 0, title: f.title, episode: 0,
                              removed: true, removedFranchise: snapshot, prevStatus: previousStatus))
    }

    // MARK: - Undo

    /// The single entry point for the toast's Undo button. Takes the state BY VALUE so a toast
    /// that is still on screen stays actionable even if `self.undo` has already moved on.
    func undoTapped(_ state: UndoState) {
        if let action = state.undoAction { undo = nil; FeedbackCoordinator.fire(.selection); return action() }
        if state.removed { return restoreRemoved(state) }
        performUndo()
    }

    /// Put a removed show back exactly as it was — instantly, from the snapshot, before any
    /// network round-trip. The re-subscribe carries the PREVIOUS status, so a Finished show
    /// returns to the Finished shelf rather than silently becoming Planned.
    private func restoreRemoved(_ state: UndoState) {
        guard let f = state.removedFranchise else { return }
        FeedbackCoordinator.fire(.selection)
        undo = nil
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        withAnimation(ThemeMotion.pick(ThemeMotion.uiSnappy, reduceMotion: reduceMotion)) {
            if !library.contains(where: { $0.id == f.id }) { library.append(f) }
        }
        Task {
            do {
                _ = try await api.subscribe(franchiseId: f.id, status: state.prevStatus)
                await reload()
            } catch {
                // Membership is a fact about the account, so it rolls back; the failure is
                // surfaced once, in the SyncBanner, with a Retry that re-issues exactly this call.
                withAnimation(ThemeMotion.pick(ThemeMotion.uiGentle, reduceMotion: reduceMotion)) {
                    library.removeAll { $0.id == f.id }
                }
                SyncCenter.shared.record(command: Copy.Action.add, title: f.title,
                                         reason: Copy.Notice.reason(error)) { [weak self] in
                    self?.undoTapped(state)
                }
            }
        }
    }
}
