import SwiftUI

// Long-press quick actions for a library franchise — the same actions as the detail screen,
// one press away. Attach via `.contextMenu { FranchiseContextMenu(f: f, appModel: appModel) }`.
struct FranchiseContextMenu: View {
    let f: Franchise
    let appModel: AppModel

    var body: some View {
        if let part = f.releasingPart, part.isBehind {
            Button {
                appModel.markCaughtUp(f.id)
            } label: {
                Label("Mark caught up · Ep \(part.airedEpisodes)", systemImage: "checkmark.circle")
            }
        }

        let status = f.effectiveStatus
        Button {
            appModel.setStatus(franchiseId: f.id, status: .watching)
        } label: {
            Label("Watching", systemImage: status == .watching ? "checkmark" : "play.circle")
        }
        Button {
            appModel.setStatus(franchiseId: f.id, status: .completed)
        } label: {
            Label("Completed", systemImage: status == .completed ? "checkmark" : "checkmark.seal")
        }
        Button {
            appModel.setStatus(franchiseId: f.id, status: .planned)
        } label: {
            Label("Plan to watch", systemImage: status == .planned ? "checkmark" : "clock")
        }

        Divider()

        Button(role: .destructive) {
            appModel.removeFromLibrary(franchiseId: f.id)
        } label: {
            Label("Remove from library", systemImage: "trash")
        }
    }
}
