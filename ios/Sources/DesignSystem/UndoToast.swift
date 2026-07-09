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
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: appModel.undo?.id)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: appModel.errorToast)
    }
}

// Floating glass toast shown when a write failed and was rolled back.
struct ErrorToast: View {
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color(hex: 0xE5484D)).frame(width: 20, height: 20)
                Image(systemName: "exclamationmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            }
            Text(message)
                .scaledFont(13.5)
                .foregroundStyle(Theme.text90)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 15)
        .padding(.trailing, 12)
        .padding(.vertical, 11)
        .glassChrome(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(hex: 0xE5484D).opacity(0.35), lineWidth: 1)
        )
        .frame(maxWidth: 360)
        .shadow(color: .black.opacity(0.55), radius: 20, y: 12)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

// Floating glass undo toast.
struct UndoToast: View {
    let state: UndoState
    let onUndo: () -> Void

    @State private var checkTrim: CGFloat = 0

    var body: some View {
        GlassGroup(spacing: 6) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Theme.accent).frame(width: 20, height: 20)
                    // Checkmark draws itself in just after the toast lands (echoes CaughtUpOverlay).
                    CheckmarkShape()
                        .trim(from: 0, to: checkTrim)
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
                    .buttonStyle(SpringPressButtonStyle(scale: 0.92))
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
        .onAppear {
            withAnimation(.easeOut(duration: 0.35).delay(0.15)) { checkTrim = 1 }
        }
    }
}
