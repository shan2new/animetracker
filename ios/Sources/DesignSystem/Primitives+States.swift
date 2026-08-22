import SwiftUI

// The shared component inventory for states, milestones and history (spec boards 09, 10, 12).
//
// This file is the single declaration site for every component more than one screen renders.
// A screen composes from here; it does not re-declare an empty state, a failure notice, a stale
// strip, a skeleton gate or a history rail with its own geometry.
//
// House rules for everything below: tokens only (`ThemeColor` / `ThemeSpace` / `ThemeRadius` /
// `ThemeType` / `ThemeMotion`); every interactive element ≥ 44 pt; every motion goes through
// `ThemeMotion.pick(_:reduceMotion:)`; every haptic through `FeedbackCoordinator.fire(_:)`, at
// most one per transaction; nothing truncates at accessibility sizes — the container grows.

extension ThemeMotion {
    /// Board 09's "120-ms crossfade" and board 11's Reduce Motion fallback are the same curve, so
    /// this is a name for `uiReduced`, not a fourteenth token.
    static let uiCrossfade = ThemeMotion.uiReduced
}

// MARK: - Empty state

/// The one empty state. Always inside a card, always left-aligned: centring would introduce a
/// second alignment grammar and the frame would jump when data arrives. The empty state occupies
/// the rectangle the content will occupy — that *is* structural continuity.
///
/// `primary` is the last parameter so the common single-action call reads as a trailing closure.
struct EmptyState: View {
    enum Prominence {
        /// The whole surface has nothing to show.
        case major
        /// One section of a populated surface has nothing to show.
        case section
    }

    let copy: EmptyStateCopy
    var prominence: Prominence = .major
    var secondary: (() -> Void)? = nil
    var primary: (() -> Void)? = nil

    @Environment(\.dynamicTypeSize) private var typeSize

    init(_ copy: EmptyStateCopy,
         prominence: Prominence = .major,
         secondary: (() -> Void)? = nil,
         primary: (() -> Void)? = nil) {
        self.copy = copy
        self.prominence = prominence
        self.secondary = secondary
        self.primary = primary
    }

    private var isAX: Bool { typeSize.isAccessibilitySize }
    private var minHeight: CGFloat { isAX ? 0 : (prominence == .major ? 212 : 132) }
    private var pad: CGFloat { prominence == .major ? ThemeSpace.x5 : ThemeSpace.x4 }
    private var radius: CGFloat { prominence == .major ? ThemeRadius.focusCard : ThemeRadius.card }
    private var titleToken: TypeToken { prominence == .major ? ThemeType.displayL : ThemeType.showTitleM }
    private var supportToken: TypeToken { prominence == .major ? ThemeType.callout : ThemeType.metadata }
    private var titleGap: CGFloat { prominence == .major ? 6 : 4 }
    private var actionGap: CGFloat { prominence == .major ? ThemeSpace.x5 : ThemeSpace.x4 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                if let symbol = copy.symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(ThemeColor.textTertiary)
                        .padding(.bottom, ThemeSpace.x3)
                }
                Text(copy.title)
                    .type(titleToken)
                    .foregroundStyle(ThemeColor.textPrimary)
                    // At accessibility sizes the card grows instead of clipping the title.
                    .lineLimit(isAX ? nil : (prominence == .major ? 3 : 2))
                    .fixedSize(horizontal: false, vertical: true)
                if let supporting = copy.supporting {
                    Text(supporting)
                        .type(supportToken)
                        .foregroundStyle(ThemeColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, titleGap)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(copy.spokenLabel)

            if copy.primaryLabel != nil || copy.secondaryLabel != nil {
                VStack(alignment: .leading, spacing: ThemeSpace.x2) {
                    if let label = copy.primaryLabel {
                        Button(label) { primary?() }
                            .buttonStyle(PrimaryButtonStyle2())
                            .disabled(primary == nil)
                    }
                    if let label = copy.secondaryLabel {
                        Button(label) { secondary?() }
                            .buttonStyle(TertiaryButtonStyle2())
                            .disabled(secondary == nil)
                    }
                }
                .padding(.top, actionGap)
            }
        }
        .padding(pad)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
        .background(ThemeColor.surfaceFlat, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
            .stroke(ThemeColor.separator, lineWidth: 1))
        // Opacity only: an empty state that scales in reads as a celebration of having nothing.
        .transition(.opacity)
    }
}

// MARK: - Inline notice

/// "This section's refresh failed" — content stays, the notice sits under the section header.
/// Never a full-screen error, never a toast: a background failure is silent and repairable.
struct InlineNotice: View {
    enum Kind {
        case failure
        case info
    }

    let message: String
    var kind: Kind = .failure
    var retry: (() -> Void)? = nil

    @Environment(\.dynamicTypeSize) private var typeSize

    init(_ message: String, kind: Kind = .failure, retry: (() -> Void)? = nil) {
        self.message = message
        self.kind = kind
        self.retry = retry
    }

    private var isAX: Bool { typeSize.isAccessibilitySize }
    private var strokeColor: Color {
        kind == .failure ? ThemeColor.warning.opacity(0.35) : ThemeColor.separator
    }

    var body: some View {
        Group {
            if isAX {
                VStack(alignment: .leading, spacing: 10) {
                    label
                    if let retry {
                        Button(Copy.Action.retry, action: retry)
                            .buttonStyle(SecondaryButtonStyle2())
                            .accessibilityHint(Copy.Accessibility.retryHint)
                    }
                }
                .padding(.trailing, ThemeSpace.x3)
                .padding(.vertical, ThemeSpace.x3)
            } else {
                HStack(spacing: 10) {
                    label
                    Spacer(minLength: ThemeSpace.x2)
                    if let retry {
                        Button(Copy.Action.retry, action: retry)
                            .buttonStyle(TertiaryButtonStyle2())
                            .accessibilityHint(Copy.Accessibility.retryHint)
                    }
                }
                .padding(.trailing, 6)
            }
        }
        .padding(.leading, 14)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(ThemeColor.surfaceFlat, in: RoundedRectangle(cornerRadius: ThemeRadius.row, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: ThemeRadius.row, style: .continuous)
            .stroke(strokeColor, lineWidth: 1))
        .transition(.opacity)
    }

    private var label: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: kind == .failure ? "exclamationmark.triangle" : "info.circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(kind == .failure ? ThemeColor.warning : ThemeColor.textTertiary)
            Text(message)
                .type(ThemeType.metadataEmphasis)
                .foregroundStyle(ThemeColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, ThemeSpace.x2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }
}

// MARK: - Stale strip

/// "Updated 8h ago". Passive by decision: pull-to-refresh is the refresh affordance, and a
/// tappable strip would be a second, invisible one. No ground, no stroke, no 44-pt rule.
struct StaleStrip: View {
    let since: Int64
    let now: Int64

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(ThemeColor.textTertiary)
            Text(Copy.updated(at: since, now: now))
                .type(ThemeType.metadata)
                .foregroundStyle(ThemeColor.textTertiary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 28)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Copy.updatedSpokenLabel(at: since, now: now))
        .accessibilityAddTraits(.isStaticText)
        .transition(.opacity)
    }
}

// MARK: - Refresh indicator

/// The small spinner beside a screen title while a refresh runs over content that is already on
/// screen. Appears only after 400 ms in flight — below that it is a flicker — and is suppressed
/// while a native pull is driving, because the system indicator owns that moment.
struct RefreshIndicator: View {
    let isRefreshing: Bool
    var suppressed: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false

    var body: some View {
        ProgressView()
            .controlSize(.small)
            .tint(ThemeColor.textTertiary)
            .frame(width: 16, height: 16)
            .opacity(visible ? 1 : 0)
            .animation(ThemeMotion.pick(ThemeMotion.uiGentle, reduceMotion: reduceMotion), value: visible)
            .accessibilityHidden(true)
            .task(id: [isRefreshing, suppressed]) {
                guard isRefreshing, !suppressed else { visible = false; return }
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled, isRefreshing, !suppressed else { return }
                visible = true
            }
    }
}

// MARK: - Sync banner

/// The persistent write-failure surface, above the tab bar. A failed write is never a transient
/// toast: it stays until it is retried or discarded. Silent on appearance — a background failure
/// earns no haptic; the explicit Retry earns one `.directError` if it fails again, fired by
/// `SyncCenter`, not here.
///
/// Retry is optimistic, like every other write in the app: the banner leaves as soon as the retry
/// is issued and returns if the write fails again. There is no spinner, because a local-first
/// write returns before the network does — a spinner here could only be a lie about waiting.
struct SyncBanner: View {
    let count: Int
    var retry: (() -> Void)? = nil

    @Environment(\.dynamicTypeSize) private var typeSize

    init(count: Int, retry: (() -> Void)? = nil) {
        self.count = count
        self.retry = retry
    }

    private var isAX: Bool { typeSize.isAccessibilitySize }

    var body: some View {
        let layout = isAX
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: ThemeSpace.x3))
            : AnyLayout(HStackLayout(spacing: ThemeSpace.x3))
        return layout {
            Text(Copy.Toast.syncFailed(count))
                .type(ThemeType.body)
                .foregroundStyle(ThemeColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let retry {
                if isAX {
                    Button(Copy.Action.retry, action: retry)
                        .buttonStyle(SecondaryButtonStyle2())
                        .accessibilityHint(Copy.Accessibility.retryHint)
                } else {
                    Button(Copy.Action.retry, action: retry)
                        .buttonStyle(TertiaryButtonStyle2())
                        .accessibilityHint(Copy.Accessibility.retryHint)
                }
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, isAX ? 14 : 6)
        .padding(.vertical, isAX ? ThemeSpace.x3 : 0)
        .frame(minHeight: 52)
        .background(ThemeColor.surfaceFloating, in: RoundedRectangle(cornerRadius: ThemeRadius.toast, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: ThemeRadius.toast, style: .continuous)
            .stroke(ThemeColor.strokeStrong, lineWidth: 1))
        .shadow(color: .black.opacity(0.40), radius: 16, y: 12)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isSummaryElement)
        // Persistent chrome fades; it never springs in.
        .transition(.opacity)
    }
}

// MARK: - Episode artwork

/// The episode slot. A real, spoiler-safe still is 96×54 (16:9 exactly — the measured aspect, so
/// nothing is cropped). Anything else is the 48×48 glyph tile: board 10 says "no image slot" for a
/// missing still, and a spoiler-protected still is **replaced, never blurred** — a blur is a tease
/// with no VoiceOver equivalent. The episode number is drawn exactly once, in the row's text.
struct EpisodeArtwork: View {
    let url: String?
    var spoilerSafe: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tint: Color?

    private var hasStill: Bool { spoilerSafe && !(url ?? "").isEmpty }

    var body: some View {
        Group {
            if hasStill {
                ZStack {
                    RoundedRectangle(cornerRadius: ThemeRadius.episodeStill, style: .continuous)
                        .fill(tint ?? ThemeColor.surfaceRaised)
                    RemoteImageView(url: url, contentMode: .fill, maxPixel: 288)
                        .transition(.opacity.animation(
                            ThemeMotion.pick(ThemeMotion.uiPoster, reduceMotion: reduceMotion)))
                }
                .frame(width: 96, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: ThemeRadius.episodeStill, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: ThemeRadius.episodeStill, style: .continuous)
                    .stroke(ThemeColor.separator, lineWidth: 1))
                .task(id: url) {
                    tint = await PaletteCache.shared.resolve(url: url, maxPixel: 288)
                }
            } else {
                EpisodeGlyphTile()
            }
        }
        .accessibilityHidden(true)
    }
}

/// The neutral episode tile: 48×48, no image, no number, no blur.
struct EpisodeGlyphTile: View {
    var body: some View {
        RoundedRectangle(cornerRadius: ThemeRadius.compactControl, style: .continuous)
            .fill(ThemeColor.surfaceFloating)
            .frame(width: 48, height: 48)
            .overlay(
                Image(systemName: "play.rectangle")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(ThemeColor.textTertiary)
            )
            .overlay(RoundedRectangle(cornerRadius: ThemeRadius.compactControl, style: .continuous)
                .stroke(ThemeColor.separator, lineWidth: 1))
            .accessibilityHidden(true)
    }
}

// MARK: - Small passive primitives

/// A completed thing. Never a button, never accent — "complete" is a fact, not an action.
/// `boxed` puts it in a 44×44 box so a row's trailing edge lines up with a real control.
struct PassiveTick: View {
    var boxed: Bool = false

    var body: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 18, weight: .regular))
            .foregroundStyle(ThemeColor.textTertiary)
            .frame(width: boxed ? 44 : nil, height: boxed ? 44 : nil)
            .accessibilityElement()
            .accessibilityValue(Copy.Accessibility.complete)
            .accessibilityAddTraits(.isStaticText)
    }
}

/// Progress copy, rendered. Passive: it reports, it never invites a tap.
struct ProgressText: View {
    let text: String
    var emphasis: Bool = false
    var tint: Color = ThemeColor.textSecondary

    init(_ text: String, emphasis: Bool = false, tint: Color = ThemeColor.textSecondary) {
        self.text = text
        self.emphasis = emphasis
        self.tint = tint
    }

    var body: some View {
        Text(text)
            .type(emphasis ? ThemeType.metadataEmphasis : ThemeType.metadata)
            .foregroundStyle(tint)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isStaticText)
    }
}

/// The 1-pt bar under the search field while a query is in flight. Board 12 refuses perpetual
/// animation in general; this is the named exception in board 07, and it runs only while a real
/// request is running.
struct QueryProgressBar: View {
    let active: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -0.28

    /// The one sanctioned repeating curve outside `ThemeMotion` (board 07: "1-pt progress under
    /// the field"), kept here so it cannot spread.
    private static let sweep = Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: false)

    var body: some View {
        GeometryReader { geo in
            if active {
                if reduceMotion {
                    Rectangle().fill(ThemeColor.accent.opacity(0.30))
                } else {
                    Rectangle()
                        .fill(ThemeColor.accent)
                        .frame(width: geo.size.width * 0.28)
                        .offset(x: phase * geo.size.width)
                        .onAppear {
                            phase = -0.28
                            withAnimation(QueryProgressBar.sweep) { phase = 1.0 }
                        }
                }
            }
        }
        .frame(height: 1)
        .background(ThemeColor.accent.opacity(active ? 0.14 : 0))
        .animation(ThemeMotion.pick(ThemeMotion.uiGentle, reduceMotion: reduceMotion), value: active)
        .accessibilityHidden(true)
    }
}

// MARK: - Rows

/// The canonical 44-pt selection row: optional 40×60 cover, optional subtitle, optional trailing
/// value, a check when selected. Differentiate Without Colour passes because selection is a check,
/// not a tint.
struct SelectionRow: View {
    let title: String
    var subtitle: String? = nil
    var secondary: String? = nil
    var cover: String? = nil
    var selected: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: ThemeSpace.x3) {
                if let cover {
                    PosterSlot(url: cover, width: 40, height: 60, radius: ThemeRadius.poster)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .type(ThemeType.body)
                        .foregroundStyle(ThemeColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let subtitle {
                        Text(subtitle)
                            .type(ThemeType.metadata)
                            .foregroundStyle(ThemeColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: ThemeSpace.x2)
                if let secondary {
                    Text(secondary)
                        .type(ThemeType.metadata)
                        .foregroundStyle(ThemeColor.textTertiary)
                }
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(ThemeColor.accent)
                    .opacity(selected ? 1 : 0)
                    .frame(width: 22)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// A section header with an optional count and one optional 44-pt trailing action. Replaces the
/// legacy `SectionHeader`, whose pulsing dot board 12 refuses by name.
struct SectionHeaderRow: View {
    let text: String
    var count: Int? = nil
    var dot: Bool = false
    var actionLabel: String? = nil
    var action: (() -> Void)? = nil

    init(_ text: String, count: Int? = nil, dot: Bool = false,
         actionLabel: String? = nil, action: (() -> Void)? = nil) {
        self.text = text
        self.count = count
        self.dot = dot
        self.actionLabel = actionLabel
        self.action = action
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: ThemeSpace.x2) {
            SectionLabel(text: text, dot: dot)
            if let count {
                Text("\(count)")
                    .type(ThemeType.sectionLabel)
                    .foregroundStyle(ThemeColor.textDisabled)
                    .monospacedDigit()
            }
            Spacer(minLength: ThemeSpace.x2)
            if let actionLabel, let action {
                Button(actionLabel, action: action)
                    .buttonStyle(TertiaryButtonStyle2())
                    .frame(height: 20)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// The canonical subordinate row control: 44 pt tall, visually secondary, never a second primary.
struct CompactActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .type(ThemeType.metadataEmphasis)
            .foregroundStyle(ThemeColor.textPrimary)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(configuration.isPressed ? ThemeColor.surfacePressed : ThemeColor.surfaceFloating,
                        in: RoundedRectangle(cornerRadius: ThemeRadius.compactControl, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: ThemeRadius.compactControl, style: .continuous)
                .stroke(ThemeColor.stroke, lineWidth: 1))
            // Reduce Motion presses in opacity, never in scale (board 11).
            .opacity(isEnabled ? (reduceMotion && configuration.isPressed ? 0.72 : 1) : 0.38)
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.985 : 1))
            .animation(ThemeMotion.pick(ThemeMotion.uiPress, reduceMotion: reduceMotion),
                       value: configuration.isPressed)
    }
}

// MARK: - Watch history

/// Where a row sits on the rail. Rows are ordered newest first, so `.first` is the newest session.
enum HistoryRailPosition {
    case only
    case first
    case middle
    case last
}

/// The history timeline's container: it owns the 22-pt leading gutter the rail lives in and the
/// 10-pt row rhythm. Each row draws its own rail segment and node, so no geometry has to be
/// measured across rows.
struct HistoryRail<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: HistoryRailMetrics.rowGap) {
            content
        }
    }
}

enum HistoryRailMetrics {
    /// x-centre of the 1-pt rail, measured from the container's leading edge.
    static let railX: CGFloat = 4
    /// Leading edge of the card.
    static let cardX: CGFloat = 22
    static let node: CGFloat = 8
    static let rowGap: CGFloat = 10
    static let minRowHeight: CGFloat = 68
}

/// One watch session on the rail.
///
/// New-session choreography (board 06/11): the sheet dismisses with system motion, then the rail
/// segment draws top→bottom over 520 ms (`uiSweep`), then the node settles 0.6 → 1 over 220 ms
/// (`uiMicro`). The two never overlap — the second starts from the first's completion, not a timer.
struct HistorySessionRow: View {
    let title: String
    let subtitle: String
    var poster: String? = nil
    var active: Bool = false
    var position: HistoryRailPosition = .middle
    /// Set on a session that was just created, so its arrival is drawn exactly once.
    var isNew: Bool = false
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var segment: CGFloat = 1
    @State private var nodeScale: CGFloat = 1

    var body: some View {
        card
            .padding(.leading, HistoryRailMetrics.cardX)
            // The rail is a BACKGROUND, not a ZStack sibling: a GeometryReader beside the card
            // would claim the whole proposed height and stretch every row.
            .background(alignment: .topLeading) { rail }
            .onChange(of: isNew, initial: true) { _, new in
                guard new else { segment = 1; nodeScale = 1; return }
                guard !reduceMotion else { segment = 1; nodeScale = 1; return }
                segment = 0
                nodeScale = 0.6
                withAnimation(ThemeMotion.uiSweep) {
                    segment = 1
                } completion: {
                    withAnimation(ThemeMotion.uiMicro) { nodeScale = 1 }
                }
            }
    }

    // The rail: a hairline through the card's vertical centre, trimmed at the first and last node.
    // The downward segment overshoots by the row gap so the line stays continuous between cards.
    private var rail: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let mid = h / 2
            ZStack(alignment: .topLeading) {
                if position != .first, position != .only {
                    Rectangle()
                        .fill(ThemeColor.strokeStrong)
                        .frame(width: 1, height: mid)
                        .offset(x: HistoryRailMetrics.railX - 0.5)
                }
                if position != .last, position != .only {
                    Rectangle()
                        .fill(ThemeColor.strokeStrong)
                        .frame(width: 1, height: (h - mid + HistoryRailMetrics.rowGap) * segment)
                        .offset(x: HistoryRailMetrics.railX - 0.5, y: mid)
                }
                node.offset(x: HistoryRailMetrics.railX - HistoryRailMetrics.node / 2,
                            y: mid - HistoryRailMetrics.node / 2)
            }
            .frame(width: geo.size.width, height: h, alignment: .topLeading)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var node: some View {
        Circle()
            .fill(active ? ThemeColor.accent : ThemeColor.surfaceFlat)
            .frame(width: HistoryRailMetrics.node, height: HistoryRailMetrics.node)
            .overlay {
                if !active {
                    Circle().stroke(ThemeColor.textTertiary, lineWidth: 1.5)
                }
            }
            .background {
                if active {
                    Circle()
                        .fill(ThemeColor.accentSoft)
                        .frame(width: HistoryRailMetrics.node + 8, height: HistoryRailMetrics.node + 8)
                }
            }
            .scaleEffect(nodeScale)
    }

    private var card: some View {
        Button(action: action) {
            HStack(spacing: ThemeSpace.x3) {
                if let poster {
                    // Slots under 80 pt on the long edge use the 6-pt radius (matches the queue row).
                    PosterSlot(url: poster, width: 36, height: 54, radius: 6)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .type(ThemeType.body)
                        .foregroundStyle(ThemeColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle)
                        .type(ThemeType.metadata)
                        .foregroundStyle(ThemeColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: ThemeSpace.x2)
                Image(systemName: "chevron.forward")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ThemeColor.textTertiary)
            }
            .padding(.vertical, ThemeSpace.x3)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: HistoryRailMetrics.minRowHeight, alignment: .leading)
            .background(ThemeColor.surfaceRaised, in: RoundedRectangle(cornerRadius: ThemeRadius.row, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: ThemeRadius.row, style: .continuous)
                .stroke(active ? ThemeColor.accent.opacity(0.45) : Color.clear, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(subtitle)")
        .accessibilityValue(active ? Copy.Accessibility.active : "")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Milestone

/// The season-complete hairline: a 1-pt amber line under the Focus Card's title, 64 % of the
/// title's own width, drawn once over 520 ms. A milestone acknowledged without theatre — no
/// scrim, no disc, no confetti. It fires no haptic of its own; the transaction's single
/// `.success` is the confirmation.
private struct SeasonCompleteSweep: ViewModifier {
    let active: Bool
    let reduceMotion: Bool

    @State private var progress: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottomLeading) {
                GeometryReader { geo in
                    Rectangle()
                        .fill(LinearGradient(colors: [ThemeColor.accent, ThemeColor.accent.opacity(0)],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * 0.64 * progress, height: 1)
                        .offset(y: geo.size.height + 3)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            // `onChange` (not a re-render) drives it, so the draw can never replay.
            .onChange(of: active, initial: true) { _, isActive in
                guard isActive else { progress = 0; return }
                if reduceMotion {
                    progress = 1
                } else {
                    withAnimation(ThemeMotion.uiSweep) { progress = 1 }
                }
            }
    }
}

extension View {
    /// Applied to the title of a card whose season just completed.
    func seasonCompleteSweep(_ active: Bool, reduceMotion: Bool) -> some View {
        modifier(SeasonCompleteSweep(active: active, reduceMotion: reduceMotion))
    }

    /// `contentTransition(.numericText())` on the four numbers board 12 allows it on: the backlog
    /// count after a mark, the library count, a confirmation summary, and the foreground
    /// countdown. Nowhere else — constant movement turns state into spectacle.
    func numericFact<V: Equatable>(_ value: V) -> some View {
        contentTransition(.numericText())
            .animation(ThemeMotion.uiNumeric, value: value)
    }

    /// The form for a number whose change the caller already wraps in `withAnimation`.
    func numericFact() -> some View {
        contentTransition(.numericText())
    }

    /// Native `refreshable`, plus the one thing board 11 asks of a pull: `.refreshArmed` at the
    /// threshold, and only once per pull.
    ///
    /// Board 12's bookmark fill is **not** drawn this round: suppressing the system indicator is
    /// not supported API, and board 10 forbids custom refresh physics in the same sentence. Two
    /// indicators is worse than none.
    func previouslyRefreshable(threshold: CGFloat = 80,
                               _ action: @escaping @Sendable () async -> Void) -> some View {
        modifier(PreviouslyRefreshable(threshold: threshold, action: action))
    }
}

private struct PreviouslyRefreshable: ViewModifier {
    let threshold: CGFloat
    let action: @Sendable () async -> Void

    @State private var armed = false

    func body(content: Content) -> some View {
        let run = action
        return content
            .refreshable { await run() }
            .onScrollGeometryChange(for: CGFloat.self) { geo in
                -(geo.contentOffset.y + geo.contentInsets.top)
            } action: { _, pull in
                let progress = pull / threshold
                if !armed, progress >= 1 {
                    armed = true
                    FeedbackCoordinator.fire(.refreshArmed)
                } else if armed, progress < 0.3 {
                    // Re-arm only after the finger has come well back, so a wobble at the
                    // threshold cannot buzz twice.
                    armed = false
                }
            }
    }
}

// MARK: - Previews

/// The copy table's own invariants, rendered. This preview must read "No problems".
#Preview("Copy rules") {
    ScrollView {
        VStack(alignment: .leading, spacing: ThemeSpace.x3) {
            SectionHeaderRow("Copy audit", count: Copy.auditProblems.count)
            if Copy.auditProblems.isEmpty {
                ProgressText("No problems", emphasis: true, tint: ThemeColor.success)
            } else {
                ForEach(Copy.auditProblems, id: \.self) { problem in
                    ProgressText(problem, tint: ThemeColor.destructive)
                }
            }
            ForEach(Copy.Action.commands, id: \.self) { command in
                ProgressText("\(command.label)  \u{2192}  \(command.opensConfirmation ? "confirms" : "immediate")")
            }
        }
        .padding(ThemeSpace.x4)
    }
    .background(ThemeColor.canvas)
}

#Preview("Empty states") {
    ScrollView {
        VStack(spacing: ThemeSpace.x4) {
            EmptyState(.emptyAccount) {}
            EmptyState(.serverNoCache) {}
            EmptyState(.calmToday(title: "Frieren: Beyond Journey\u{2019}s End", when: "returns tomorrow"))
            EmptyState(.noSearchResults(query: "one pece"), prominence: .section)
            EmptyState(.everythingSynced, prominence: .section)
        }
        .padding(ThemeSpace.x4)
    }
    .background(ThemeColor.canvas)
}

#Preview("Empty state · AX5") {
    ScrollView {
        VStack(spacing: ThemeSpace.x4) {
            EmptyState(.emptyAccount) {}
            EmptyState(.noFilterMatches, prominence: .section) {}
        }
        .padding(ThemeSpace.x4)
    }
    .background(ThemeColor.canvas)
    .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("Notices and strips") {
    VStack(alignment: .leading, spacing: ThemeSpace.x4) {
        StaleStrip(since: .nowMs - 8 * Formatting.H, now: .nowMs)
        InlineNotice(Copy.Notice.today) {}
        InlineNotice(Copy.Notice.searchAnime) {}
        InlineNotice(Copy.Toast.offlinePending, kind: .info)
        SyncBanner(count: 1) {}
        SyncBanner(count: 3) {}
        HStack(spacing: ThemeSpace.x3) {
            RefreshIndicator(isRefreshing: true)
            PassiveTick()
            PassiveTick(boxed: true)
            ProgressText(Copy.Progress.watchedOf(18, 24))
        }
        QueryProgressBar(active: true)
    }
    .padding(ThemeSpace.x4)
    .background(ThemeColor.canvas)
}

#Preview("Notices · AX5") {
    VStack(alignment: .leading, spacing: ThemeSpace.x4) {
        InlineNotice(Copy.Notice.schedule) {}
        SyncBanner(count: 2) {}
    }
    .padding(ThemeSpace.x4)
    .background(ThemeColor.canvas)
    .environment(\.dynamicTypeSize, .accessibility5)
}

/// Reduce Motion is a system setting, not a writable environment value, so it is previewed by
/// passing the flag the components actually read.
#Preview("Milestone · Reduce Motion") {
    VStack(alignment: .leading, spacing: ThemeSpace.x5) {
        Text("That Time I Got Reincarnated as a Slime")
            .type(ThemeType.showTitleM)
            .foregroundStyle(ThemeColor.textPrimary)
            .seasonCompleteSweep(true, reduceMotion: true)
        QueryProgressBar(active: true)
        HistoryRail {
            HistorySessionRow(title: Copy.Progress.ordinalWatch(2),
                              subtitle: Copy.Progress.inProgress(nextEpisode: 3),
                              active: true, position: .only) {}
        }
    }
    .padding(ThemeSpace.x4)
    .background(ThemeColor.canvas)
}

#Preview("History rail") {
    HistoryRail {
        HistorySessionRow(title: Copy.Progress.ordinalWatch(3),
                          subtitle: Copy.Progress.inProgress(nextEpisode: 7),
                          active: true, position: .first, isNew: true) {}
        HistorySessionRow(title: Copy.Progress.ordinalWatch(2),
                          subtitle: Copy.Progress.sessionSpan(started: .nowMs - 40 * Formatting.D,
                                                              completed: .nowMs - 25 * Formatting.D,
                                                              episodes: 26, now: .nowMs),
                          position: .middle) {}
        HistorySessionRow(title: Copy.Progress.ordinalWatch(1),
                          subtitle: Copy.Progress.sessionSpan(started: nil, completed: nil,
                                                              episodes: 26, now: .nowMs),
                          position: .last) {}
    }
    .padding(ThemeSpace.x4)
    .background(ThemeColor.canvas)
}

#Preview("Rows and milestone") {
    VStack(alignment: .leading, spacing: ThemeSpace.x4) {
        SectionHeaderRow("Seasons & movies", count: 4, actionLabel: Copy.Action.seeAll) {}
        SelectionRow(title: "Season 4", subtitle: Copy.Progress.watchedOf(18, 24),
                     secondary: "24", selected: true) {}
        SelectionRow(title: "Entire franchise", selected: false) {}
        HStack(spacing: ThemeSpace.x3) {
            EpisodeArtwork(url: nil, spoilerSafe: false)
            EpisodeGlyphTile()
            Button(Copy.Action.viewEpisodes) {}.buttonStyle(CompactActionButtonStyle())
        }
        Text("That Time I Got Reincarnated as a Slime")
            .type(ThemeType.showTitleM)
            .foregroundStyle(ThemeColor.textPrimary)
            .seasonCompleteSweep(true, reduceMotion: false)
            .padding(.bottom, ThemeSpace.x2)
    }
    .padding(ThemeSpace.x4)
    .background(ThemeColor.canvas)
}
