import SwiftUI

// Long-press quick actions for a library franchise — the same actions as the detail screen, one
// press away. Every item here also exists in Detail, so long-press is a shortcut, never the only
// route. Haptics: exactly one per transaction, none fired here (markCaughtUp, setStatus and
// removeWithUndo each fire their own).
struct FranchiseContextMenu: View {
    let f: Franchise
    let appModel: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let part = f.releasingPart, part.episodesBehind > 0 {
            Button {
                appModel.markCaughtUp(f.id)
            } label: {
                Label(Copy.Action.markAll(part.episodesBehind), systemImage: "text.append")
            }
        }
        let status = f.effectiveStatus
        ForEach(WatchStatus.menuOrder, id: \.self) { option in
            Button {
                appModel.setStatus(franchiseId: f.id, status: option)
            } label: {
                Label(option.displayName, systemImage: status == option ? "checkmark" : option.menuGlyph)
            }
        }
        Divider()
        RemoveFromLibraryButton(franchise: f, appModel: appModel)
    }
}

extension WatchStatus {
    /// Board 09's order — the order a viewer moves through them.
    static var menuOrder: [WatchStatus] { [.watching, .planned, .completed, .paused, .dropped] }

    /// The unselected glyph; the selected one is always `checkmark`.
    var menuGlyph: String {
        switch self {
        case .watching:  return "play.circle"
        case .planned:   return "clock"
        case .completed: return "checkmark.circle"
        case .paused:    return "pause.circle"
        case .dropped:   return "xmark.circle"
        }
    }
}

/// The destructive menu item, so every host adds remove in one line and no host can reintroduce a
/// confirmation dialog or a second haptic.
struct RemoveFromLibraryButton: View {
    let franchise: Franchise
    let appModel: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(role: .destructive) {
            appModel.removeWithUndo(franchise, reduceMotion: reduceMotion)
        } label: {
            Label(Copy.Action.removeFromLibrary, systemImage: "trash")
        }
    }
}
