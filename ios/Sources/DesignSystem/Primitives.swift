import SwiftUI

// Component primitives for the interaction system (spec board 10). Each has exact geometry,
// named states, and no local colour or radius values.

// MARK: - Poster slot

/// Identity artwork: always aspect-fit in its slot, never cropped. The slot is the cached palette
/// tint first (never grey), the poster cross-dissolves in over 180 ms. Missing art keeps the tint
/// with a centred `photo` symbol.
struct PosterSlot: View {
    let url: String?
    let width: CGFloat
    let height: CGFloat
    var radius: CGFloat = ThemeRadius.poster

    @State private var tint: Color?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(tint ?? ThemeColor.surfaceRaised)
            if let url, !url.isEmpty {
                RemoteImageView(url: url, contentMode: .fit, maxPixel: max(width, height) * 3)
                    .transition(.opacity.animation(ThemeMotion.uiPoster))
            } else {
                Image(systemName: "photo")
                    .font(.system(size: min(width, height) * 0.28, weight: .regular))
                    .foregroundStyle(ThemeColor.textTertiary)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(ThemeColor.separator, lineWidth: 1))
        .task(id: url) {
            tint = await PaletteCache.shared.resolve(url: url, maxPixel: max(width, height) * 3)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Buttons

/// 48-pt capsule, accent on onAccent, press 0.985, disabled 0.38. Label comes from the copy table.
struct PrimaryButtonStyle2: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .type(ThemeType.button)
            .foregroundStyle(ThemeColor.onAccent)
            .frame(maxWidth: .infinity, minHeight: 48)
            .padding(.horizontal, 18)
            .background(configuration.isPressed ? ThemeColor.accentPressed : ThemeColor.accent, in: Capsule())
            .opacity(isEnabled ? 1 : 0.38)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(ThemeMotion.uiPress, value: configuration.isPressed)
    }
}

/// 44-pt capsule on surfaceFloating with a stroke.
struct SecondaryButtonStyle2: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .type(ThemeType.button)
            .foregroundStyle(ThemeColor.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, 18)
            .background(configuration.isPressed ? ThemeColor.surfacePressed : ThemeColor.surfaceFloating, in: Capsule())
            .overlay(Capsule().stroke(ThemeColor.stroke, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(ThemeMotion.uiPress, value: configuration.isPressed)
    }
}

/// Text in accent, 44×44 target, no container.
struct TertiaryButtonStyle2: ButtonStyle {
    var destructive = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .type(ThemeType.button)
            .foregroundStyle(destructive ? ThemeColor.destructive : ThemeColor.accent)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// Press feedback for content cards and rows: surface overlay only, scale never below 0.985.
struct RowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay(RoundedRectangle(cornerRadius: ThemeRadius.row, style: .continuous)
                .fill(ThemeColor.surfacePressed.opacity(configuration.isPressed ? 0.6 : 0)))
            .scaleEffect(configuration.isPressed ? 0.992 : 1)
            .animation(configuration.isPressed ? ThemeMotion.uiPress : ThemeMotion.uiMicro, value: configuration.isPressed)
    }
}

// MARK: - Labels

/// Eyebrow / section label: caption2 semibold, +1.0 tracking, tertiary, uppercase via textCase.
/// The optional 4-pt leading dot means "newly changed" only.
struct SectionLabel: View {
    let text: String
    var dot = false
    var tint: Color = ThemeColor.textTertiary

    var body: some View {
        HStack(spacing: 6) {
            if dot { Circle().fill(ThemeColor.accent).frame(width: 4, height: 4) }
            Text(text).type(ThemeType.sectionLabel).textCase(.uppercase)
        }
        .foregroundStyle(tint)
        .lineLimit(1)
    }
}

// MARK: - Status chip

/// 32 pt visible, 44 pt target, native glass, chevron.down 9 pt. Labels are the status language.
struct StatusChip: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(label).type(ThemeType.metadataEmphasis)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(ThemeColor.textPrimary)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .contentShape(Capsule())
        }
        .glassChrome(in: Capsule(), interactive: true)
        .frame(minHeight: 44)
        .accessibilityLabel("Change status, \(label)")
    }
}

// MARK: - Grouped list

/// Inset grouped list in the system grammar: radius 16, rows 52, leading 28-pt symbol tile,
/// trailing value / chevron / toggle / check; separators inset to the title.
struct GroupedList<Content: View>: View {
    var header: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let header {
                SectionLabel(text: header).padding(.leading, 16)
            }
            VStack(spacing: 0) { content() }
                .background(ThemeColor.surfaceRaised, in: RoundedRectangle(cornerRadius: ThemeRadius.row, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: ThemeRadius.row, style: .continuous).stroke(ThemeColor.separator, lineWidth: 1))
        }
    }
}

enum GroupedTrailing {
    case chevron(String?)
    case value(String)
    case toggle(Binding<Bool>)
    case check(Bool)
    case none
}

struct GroupedRow: View {
    var symbol: String? = nil
    var symbolTint: Color = Color(hex: 0x3A3D45)
    let title: String
    var subtitle: String? = nil
    var warning = false
    var trailing: GroupedTrailing = .none
    var separator = true
    var action: (() -> Void)? = nil

    var body: some View {
        Button { action?() } label: {
            HStack(spacing: 12) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(ThemeColor.textPrimary)
                        .frame(width: 28, height: 28)
                        .background(symbolTint, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 8) {
                        Text(title).type(ThemeType.body).foregroundStyle(ThemeColor.textPrimary)
                        if warning { Circle().fill(ThemeColor.warning).frame(width: 8, height: 8) }
                    }
                    if let subtitle {
                        Text(subtitle).type(ThemeType.metadata).foregroundStyle(ThemeColor.textSecondary)
                    }
                }
                Spacer(minLength: 8)
                trailingView
            }
            .padding(.leading, 14).padding(.trailing, 16)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                if separator {
                    Rectangle().fill(ThemeColor.separator).frame(height: 1).padding(.leading, symbol == nil ? 14 : 54)
                }
            }
        }
        .buttonStyle(GroupedRowPressStyle())
        .disabled(action == nil && !isInteractiveTrailing)
    }

    private var isInteractiveTrailing: Bool {
        if case .toggle = trailing { return true }
        return false
    }

    @ViewBuilder
    private var trailingView: some View {
        switch trailing {
        case .chevron(let value):
            HStack(spacing: 6) {
                if let value { Text(value).type(ThemeType.body).foregroundStyle(ThemeColor.textTertiary) }
                Image(systemName: "chevron.forward").font(.system(size: 13, weight: .semibold)).foregroundStyle(ThemeColor.textTertiary)
            }
        case .value(let v):
            Text(v).type(ThemeType.body).foregroundStyle(ThemeColor.textTertiary)
        case .toggle(let binding):
            Toggle("", isOn: binding).labelsHidden().tint(ThemeColor.success)
        case .check(let on):
            Image(systemName: "checkmark").font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ThemeColor.accent).opacity(on ? 1 : 0).frame(width: 22)
        case .none:
            EmptyView()
        }
    }
}

struct GroupedRowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? ThemeColor.surfacePressed : .clear)
    }
}

// MARK: - Recap strip

/// The compact recap: 44-pt minimum, full-width target, opens the digest. Persists until the
/// first mark or leaving Today.
struct RecapStrip: View {
    let text: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(text).type(ThemeType.metadataEmphasis).foregroundStyle(ThemeColor.textPrimary)
                Spacer()
                Image(systemName: "chevron.forward").font(.system(size: 12, weight: .semibold)).foregroundStyle(ThemeColor.textTertiary)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(ThemeColor.surfaceFlat, in: RoundedRectangle(cornerRadius: ThemeRadius.row, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: ThemeRadius.row, style: .continuous).stroke(ThemeColor.stroke, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityLabel(text)
    }
}

// MARK: - Toast

/// Canonical toast: margin 16, min 52, radius 18, 12 above the tab bar. Default 6 s; failure persists.
struct ToastView: View {
    let message: String
    var actionLabel: String? = nil
    var failure = false
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            Text(message)
                .type(ThemeType.body)
                .foregroundStyle(ThemeColor.textPrimary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let actionLabel, let action {
                Button(actionLabel, action: action)
                    .buttonStyle(TertiaryButtonStyle2())
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .frame(minHeight: 52)
        .background(ThemeColor.surfaceFloating, in: RoundedRectangle(cornerRadius: ThemeRadius.toast, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: ThemeRadius.toast, style: .continuous)
            .stroke(failure ? ThemeColor.warning.opacity(0.5) : ThemeColor.strokeStrong, lineWidth: 1))
        .shadow(color: .black.opacity(0.40), radius: 16, y: 12)
        .transition(.opacity.combined(with: .offset(y: 4)))
    }
}

// MARK: - Skeleton

/// Structural skeleton: static, no shimmer (spec: shimmer is refused).
struct SkeletonBlock: View {
    var width: CGFloat? = nil
    var height: CGFloat = 12
    var radius: CGFloat = 6
    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(ThemeColor.skeleton)
            .frame(width: width, height: height)
    }
}
