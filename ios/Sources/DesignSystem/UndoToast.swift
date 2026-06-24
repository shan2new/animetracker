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
            return "Added \(title) to \(statusLabel ?? "library")"
        }
        return "Marked \(title) · Ep \(episode)"
    }
}

// Floating glass undo toast. Rendered above the tab bar (and detail sheet) so in-sheet actions
// stay undoable.
struct UndoToast: View {
    let state: UndoState
    let onUndo: () -> Void

    var body: some View {
        GlassGroup(spacing: 6) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Theme.accent).frame(width: 20, height: 20)
                    CheckmarkShape()
                        .stroke(Theme.background, style: StrokeStyle(lineWidth: 3.4, lineCap: .round, lineJoin: .round))
                        .frame(width: 11, height: 11)
                }
                Text(state.message)
                    .scaledFont(13.5)
                    .foregroundStyle(Theme.text90)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Undo", action: onUndo)
                    .scaledFont(13.5, weight: .semibold)
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
            }
            .padding(.leading, 15)
            .padding(.trailing, 12)
            .padding(.vertical, 11)
            .glassChrome(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Theme.hairlineStrong, lineWidth: 1)
            )
        }
        .frame(maxWidth: 360)
        .shadow(color: .black.opacity(0.55), radius: 20, y: 12)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
