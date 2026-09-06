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
    /// Where the receipt is drawn (`Receipts.swift`): in place under a host that stays on
    /// screen, else the tab bar's lane. Default: the lane.
    var placement: ReceiptPlacement = .lane

    /// The same state, placed under a host.
    func placed(at host: String) -> UndoState {
        var s = self
        s.placement = .inPlace(host: host)
        return s
    }

    /// The fact alone — "Episode 19 watched" — for a receipt that sits where the show's name
    /// already is (the receipt spike, 5 Sep).
    var receipt: String {
        if let customMessage { return customMessage }
        // The lane's fact, with the show on the line beneath; the full sentence stays in
        // `message` for VoiceOver.
        if removed { return Copy.Toast.removedShort }
        if added { return Copy.Toast.added(title: title, status: statusLabel ?? "Library") }
        return count > 1 ? Copy.Toast.batchWatched(count) : Copy.Progress.episodeWatched(episode)
    }

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

// The bottom chrome's persistent surfaces, above the tab bar: the sync banner, and — below
// iOS 26.1, where the bar has no accessory lane — the receipt lane. Always mounted with `if let`
// children so the insert/remove transitions actually animate. The receipts themselves are
// `Receipts.swift`; the in-place line lives under the control that was pressed.
struct ToastHost: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let sync = SyncCenter.shared
        VStack(spacing: 9) {
            // Not over Profile: it lists every failed change with Retry and Discard, so the
            // banner there was a duplicate of the screen being read.
            if !sync.failedChanges.isEmpty, !sync.profileIsOpen {
                SyncBanner(count: sync.failedChanges.count, retry: sync.canRetryAny ? { sync.retryAll() } : nil)
                    .frame(maxWidth: 420)
            }
            if !ChromeCapability.tabBarAccessory {
                LaneFallback().frame(maxWidth: 420)
            }
        }
        .animation(ThemeMotion.pick(ThemeMotion.uiSnappy, reduceMotion: reduceMotion),
                   value: sync.failedChanges.count)
        // A VoiceOver user was never told the receipt existed, let alone that Undo was available
        // for the next six (or ten) seconds.
        .onChange(of: appModel.undo?.id) { _, _ in
            guard let undo = appModel.undo else { return }
            Announce.status("\(undo.message). \(Copy.Action.undo) available.")
        }
        .onChange(of: appModel.errorToast) { _, message in
            if let message { Announce.status(message) }
        }
        .onChange(of: appModel.notice) { _, message in
            if let message { Announce.status(message) }
        }
    }
}
