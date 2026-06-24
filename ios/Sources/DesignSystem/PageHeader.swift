import SwiftUI

// Shared inline page header — the same title + subtitle treatment Today and Schedule draw at the
// top of their scroll content (native nav bar hidden). Library and Add use this so every tab's
// header reads identically instead of falling back to iOS's large navigation title.
struct PageHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .scaledFont(27, weight: .semibold)
                .tracking(-0.8)
            if let subtitle {
                Text(subtitle)
                    .scaledFont(14)
                    .foregroundStyle(Theme.text52)
                    .lineSpacing(2)
                    .padding(.top, 8)
            }
        }
    }
}

// In-content search field that matches the design system, replacing the native `.searchable`
// navigation-bar drawer so the search bar lives under our custom header (like the screenshots)
// instead of inside the system large-title bar.
struct SearchField: View {
    @Binding var text: String
    let prompt: String
    @FocusState private var focused: Bool

    private var shape: Capsule { Capsule() }

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .scaledFont(15, weight: .medium)
                .foregroundStyle(focused ? Theme.text62 : Theme.text40)
            TextField("", text: $text, prompt: Text(prompt).foregroundColor(Theme.text40))
                .scaledFont(16)
                .foregroundStyle(Theme.textPrimary)
                .tint(Theme.accent)
                .focused($focused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .scaledFont(15)
                        .foregroundStyle(Theme.text36)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 11)
        // Native Liquid Glass material (iOS 26) with an interactive response to touch; falls back to
        // .ultraThinMaterial on older systems. An accent ring fades in on focus.
        .glassChrome(in: shape, interactive: true)
        .overlay(shape.stroke(Theme.accentBorder, lineWidth: 1).opacity(focused ? 1 : 0))
        .animation(.easeInOut(duration: 0.18), value: focused)
        .animation(.easeInOut(duration: 0.18), value: text.isEmpty)
    }
}
