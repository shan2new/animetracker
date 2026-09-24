import SwiftUI

// Long-press quick actions for a library franchise — the same actions as the detail screen, one
// press away. Every item here also exists in Detail, so long-press is a shortcut, never the only
// route. Haptics: exactly one per transaction, none fired here (markCaughtUp, setStatus and
// removeWithUndo each fire their own).
struct FranchiseContextMenu: View {
    let f: Franchise
    let appModel: AppModel
    /// "Mark all N episodes as watched…" is a batch, and every batch in the app confirms with its
    /// exact count first. The menu cannot present anything itself, so it hands the count to its
    /// host (`franchiseQuickActions`), which raises the same confirmation the show page does.
    /// `nil` hides the item — a menu with no host to confirm it offers no batch at all.
    var onMarkAll: ((FranchisePart, Int) -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // The show page's command, from anywhere: the same part (`currentPart`), the same
        // airings-derived count (`catchUpTarget`), and — through the host — the same confirmation.
        if let onMarkAll, let part = f.currentPart, !part.isUpcoming {
            let target = appModel.catchUpTarget(part)
            if target > part.progress {
                Button {
                    onMarkAll(part, target)
                } label: {
                    Label(Copy.Action.markAll(target - part.progress), systemImage: "text.append")
                }
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

/// A pending "Mark all N episodes as watched…" for one show — raised by a menu (which cannot
/// present anything itself), confirmed by `markAllConfirmation`.
struct MarkAllRequest: Identifiable {
    let id = UUID()
    let franchise: Franchise
    let from: Int
    let to: Int
    var count: Int { to - from }
}

extension View {
    /// The confirmation behind every menu's "Mark all N episodes as watched…": title, message and
    /// button from the same `Copy.Confirm` builders as the show page's, so the command reads and
    /// behaves the same wherever it is pressed. It used to write on the spot from the long press
    /// (and only there) with a count taken from the hourly-cron field (review, 23 Sep).
    func markAllConfirmation(_ request: Binding<MarkAllRequest?>, appModel: AppModel) -> some View {
        // An alert with Cancel, as every write confirmation (review i4).
        alert(request.wrappedValue.map { Copy.Confirm.batchMarkTitle($0.count) } ?? "",
              isPresented: Binding(get: { request.wrappedValue != nil },
                                   set: { if !$0 { request.wrappedValue = nil } }),
              presenting: request.wrappedValue) { r in
            Button(Copy.Confirm.batchMarkConfirm(r.count)) { appModel.markCaughtUp(r.franchise.id) }
            Button(Copy.Confirm.cancel, role: .cancel) {}
        } message: { r in
            Text(Copy.Confirm.batchMarkMessage(title: r.franchise.title,
                                               season: r.franchise.currentPart?.label ?? "",
                                               from: r.from, to: r.to))
        }
    }
}

/// The host half of the long press: the menu, and the confirmation its batch item raises.
private struct FranchiseQuickActions: ViewModifier {
    let f: Franchise
    let appModel: AppModel
    @State private var markAll: MarkAllRequest?

    func body(content: Content) -> some View {
        content
            .contextMenu {
                FranchiseContextMenu(f: f, appModel: appModel) { part, target in
                    markAll = MarkAllRequest(franchise: f, from: part.progress, to: target)
                }
            }
            .markAllConfirmation($markAll, appModel: appModel)
    }
}

extension View {
    /// Long-press quick actions on any franchise surface — one line per host, so a card or row on
    /// Today, Schedule, Library and Search carries the same menu. Pass `nil` for a title that is
    /// not in the library (an unowned search result) and the surface gets no menu at all.
    @ViewBuilder
    func franchiseQuickActions(_ f: Franchise?, appModel: AppModel) -> some View {
        if let f {
            modifier(FranchiseQuickActions(f: f, appModel: appModel))
        } else {
            self
        }
    }
}
