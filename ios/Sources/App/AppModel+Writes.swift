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

    // MARK: - Mark through an episode

    /// Move a part's progress to `episode` and present ONE undo that reports the real count and
    /// restores the exact prior value.
    ///
    /// The three halves of this were broken separately and had to be fixed together:
    ///   • `setProgress` creates no `UndoState` at all, so Today's "Mark through episode N" — a
    ///     multi-episode write, reached from a menu, with no confirmation — was **unreversible**.
    ///   • `markCaughtUp` left `UndoState.count` at 1, so a six-episode batch confirmed one.
    ///   • `UndoState.undoAction`, minted for multi-write undo, had no call site, which is also what
    ///     blocked a series-level "mark as watched" from ever being offered.
    ///
    /// One transaction, one haptic (fired inside `setProgress`), one toast, one restoring action.
    /// Returns the state it presented so a caller that owns a handoff can defer the toast instead.
    @discardableResult
    func markThrough(franchiseId: String, mediaId: Int, episode: Int,
                     present: Bool = true) -> UndoState? {
        guard let f = franchise(id: franchiseId),
              let part = f.parts.first(where: { $0.mediaId == mediaId }) else { return nil }
        let prev = part.progress
        let target = min(max(0, episode), part.progressCeiling)
        guard target != prev else { return nil }

        setProgress(franchiseId: franchiseId, mediaId: mediaId, episodes: target)

        // The restoring action is captured here, from the value read BEFORE the write, so undo
        // cannot be re-derived (wrongly) from state the write has already changed.
        let state = UndoState(
            mediaId: mediaId, franchiseId: franchiseId, prevProgress: prev,
            title: f.title, episode: target,
            count: max(1, abs(target - prev)),
            undoAction: { [weak self] in
                self?.setProgress(franchiseId: franchiseId, mediaId: mediaId,
                                  episodes: prev, haptic: false)
            })
        if present { presentUndo(state) }
        return state
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
                                         reason: Copy.Notice.reason(error)) {
                    self.undoTapped(state)
                }
            }
        }
    }
}
