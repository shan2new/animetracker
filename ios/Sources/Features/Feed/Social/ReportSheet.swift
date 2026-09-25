import SwiftUI

// Report a reply (spec §4.6, App Review 1.2): a reason, an optional note, one confirmation. The
// server hides the reply for its reporter at once (and for everyone after enough reports); the
// model takes it out of the loaded thread and says "Thanks. This reply is hidden for you while
// it’s reviewed." in the lane. A refusal keeps the sheet up with its line under the note.

struct ReportSheet: View {
    let comment: SocialComment

    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var reason: ReportReason?
    @State private var note = ""
    @State private var sending = false
    @State private var failed = false
    @FocusState private var noteFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(Copy.Social.reportPrompt)
                        .type(ThemeType.feedName)
                        .foregroundStyle(ThemeColor.feedText)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, ThemeMetrics.gutter)
                        .padding(.top, ThemeSpace.x2)
                        .padding(.bottom, ThemeSpace.x3)
                        .accessibilityAddTraits(.isHeader)
                    Rectangle().fill(ThemeColor.feedSeparator).frame(height: FeedMetrics.hairline)
                    ForEach(ReportReason.allCases, id: \.self) { r in
                        reasonRow(r)
                    }
                    noteField
                        .padding(.horizontal, ThemeMetrics.gutter)
                        .padding(.top, ThemeSpace.x5)
                    if failed {
                        Text(Copy.Social.reportFailed)
                            .type(ThemeType.metadata)
                            .foregroundStyle(ThemeColor.destructive)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, ThemeMetrics.gutter)
                            .padding(.top, ThemeSpace.x2)
                            .transition(.opacity)
                    }
                }
                .padding(.bottom, ThemeSpace.x8)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(ThemeColor.canvas.ignoresSafeArea())
            .navigationTitle(Copy.Social.reportTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Copy.Action.cancel) { dismiss() }
                        .foregroundStyle(ThemeColor.interactive)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if sending {
                        ProgressView().tint(ThemeColor.feedSecondary)
                    } else {
                        Button(Copy.Social.reportSend) { send() }
                            .fontWeight(.semibold)
                            .foregroundStyle(reason == nil ? ThemeColor.feedSecondary : ThemeColor.interactive)
                            .disabled(reason == nil)
                    }
                }
            }
        }
        .tint(ThemeColor.interactive)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(sending)
    }

    private func reasonRow(_ r: ReportReason) -> some View {
        Button {
            withAnimation(ThemeMotion.pick(ThemeMotion.uiMicro, reduceMotion: reduceMotion)) {
                reason = r
                failed = false
            }
        } label: {
            VStack(spacing: 0) {
                HStack(spacing: ThemeSpace.x3) {
                    Text(Copy.Social.reasonTitle(r))
                        .type(ThemeType.feedBody)
                        .foregroundStyle(ThemeColor.feedText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    // The chosen reason is a STATE (a filled check), never an action colour.
                    Image(systemName: reason == r ? "checkmark.circle.fill" : "circle")
                        .font(ThemeType.feedBody.font)
                        .imageScale(.large)
                        .foregroundStyle(reason == r ? ThemeColor.accent : ThemeColor.feedSecondary)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, ThemeMetrics.gutter)
                .frame(minHeight: ThemeMetrics.rowCompact)
                Rectangle().fill(ThemeColor.feedSeparator).frame(height: FeedMetrics.hairline)
                    .padding(.leading, ThemeMetrics.gutter)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(FeedRowPressStyle())
        .accessibilityAddTraits(reason == r ? [.isSelected] : [])
    }

    private var noteField: some View {
        TextField(Copy.Social.reportNoteLabel, text: $note, axis: .vertical)
            .type(ThemeType.feedBody)
            .foregroundStyle(ThemeColor.feedText)
            .lineLimit(3...6)
            .focused($noteFocused)
            .padding(ThemeSpace.x3)
            .background(ThemeColor.feedField, in: RoundedRectangle(cornerRadius: ThemeRadius.compactControl,
                                                                   style: .continuous))
            .onChange(of: note) { _, text in
                // The server takes 500 code points; the field stops there rather than refusing.
                let scalars = text.unicodeScalars
                guard scalars.count > SocialMetrics.reportNoteLimit else { return }
                note = String(String.UnicodeScalarView(scalars.prefix(SocialMetrics.reportNoteLimit)))
            }
    }

    private func send() {
        guard let reason, !sending else { return }
        noteFocused = false
        sending = true
        failed = false
        let comment = comment
        let note = note
        Task {
            let ok = await appModel.reportComment(comment, reason: reason, note: note)
            sending = false
            if ok {
                dismiss()
            } else {
                withAnimation(ThemeMotion.pick(ThemeMotion.uiGentle, reduceMotion: reduceMotion)) { failed = true }
            }
        }
    }
}
