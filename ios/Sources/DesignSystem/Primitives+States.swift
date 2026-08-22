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

            // A label without a handler is a dead control, not a disabled one: an empty state
            // that draws `Try again` at 0.38 opacity is worse than an empty state with no button.
            // The button exists only when the caller supplied something for it to do.
            if (copy.primaryLabel != nil && primary != nil)
                || (copy.secondaryLabel != nil && secondary != nil) {
                VStack(alignment: .leading, spacing: ThemeSpace.x2) {
                    if let label = copy.primaryLabel, let primary {
                        Button(label, action: primary)
                            .buttonStyle(PrimaryButtonStyle2())
                    }
                    if let label = copy.secondaryLabel, let secondary {
                        Button(label, action: secondary)
                            .buttonStyle(TertiaryButtonStyle2())
                    }
                }
                .padding(.top, actionGap)
            }
        }
        .padding(pad)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
        // A plate. "Nothing here" is the quietest thing on any screen; outlining it in grey was
        // the loudest way to draw it.
        .surface(.plate, radius: radius)
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
        .surface(.plate, radius: ThemeRadius.row)
        // A 3-pt warning rule down the leading edge instead of a 1-px amber outline round the
        // whole notice: the colour lands where the eye enters the line, and the notice stops
        // looking like a disabled button.
        .overlay(alignment: .leading) {
            if kind == .failure {
                UnevenRoundedRectangle(topLeadingRadius: ThemeRadius.row,
                                       bottomLeadingRadius: ThemeRadius.row,
                                       bottomTrailingRadius: 0, topTrailingRadius: 0,
                                       style: .continuous)
                    .fill(ThemeColor.warning.opacity(0.85))
                    .frame(width: 3)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: ThemeRadius.row, style: .continuous))
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
                // At AX5 the metadata token is ~44 pt: "Updated Aug 19, 2025" cannot fit one line.
                // The strip is passive, so it wraps and the 28-pt minimum simply grows.
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 28, alignment: .leading)
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
/// (Plan §2.6 asks for a spinner in place of the label; that half is escalated, not silently
/// dropped. What plan §2.6 is actually protecting against — a second tap re-issuing the write —
/// is handled by `retryInFlight` below, which is a real guard rather than a fictional wait.)
struct SyncBanner: View {
    let count: Int
    var retry: (() -> Void)? = nil

    @Environment(\.dynamicTypeSize) private var typeSize
    /// A retry has been issued. The button is inert until the banner's row has had time to leave,
    /// so an impatient double-tap cannot send the same write twice.
    @State private var retryInFlight = false

    init(count: Int, retry: (() -> Void)? = nil) {
        self.count = count
        self.retry = retry
    }

    private var isAX: Bool { typeSize.isAccessibilitySize }

    /// A timed hold, not a gate on a spring: the sync closure returns immediately, so there is no
    /// completion to wait on. Long enough to swallow a double-tap, short enough that a banner
    /// which comes straight back is pressable again.
    private static let retryLockout: Duration = .milliseconds(800)

    private func issueRetry(_ retry: @escaping () -> Void) {
        guard !retryInFlight else { return }
        retryInFlight = true
        retry()
    }

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
                    Button(Copy.Action.retry) { issueRetry(retry) }
                        .buttonStyle(SecondaryButtonStyle2())
                        .disabled(retryInFlight)
                        .accessibilityHint(Copy.Accessibility.retryHint)
                } else {
                    Button(Copy.Action.retry) { issueRetry(retry) }
                        .buttonStyle(TertiaryButtonStyle2())
                        .disabled(retryInFlight)
                        .accessibilityHint(Copy.Accessibility.retryHint)
                }
            }
        }
        .task(id: retryInFlight) {
            guard retryInFlight else { return }
            try? await Task.sleep(for: SyncBanner.retryLockout)
            guard !Task.isCancelled else { return }
            retryInFlight = false
        }
        .padding(.leading, 14)
        .padding(.trailing, isAX ? 14 : 6)
        .padding(.vertical, isAX ? ThemeSpace.x3 : 0)
        .frame(minHeight: 52)
        .surface(.floating, radius: ThemeRadius.toast)
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
    /// The FRANCHISE's palette colour. A show whose stills are missing still has a colour, and a
    /// list where two rows carry a photograph and eight carry an identical grey play-glyph reads
    /// as a broken list. Passing this makes the glyph rows read as *this show, no still yet*.
    var showTint: Color? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tint: Color?

    private var hasStill: Bool { spoilerSafe && !(url ?? "").isEmpty }

    var body: some View {
        Group {
            if hasStill {
                ZStack {
                    RoundedRectangle(cornerRadius: ThemeRadius.episodeStill, style: .continuous)
                        .fill(tint ?? ThemeColor.surfaceRaised)
                    // The failed state, mirroring `PosterSlot`: the symbol sits *under* the image,
                    // so a fetch that never resolves leaves the tint plus a centred photo glyph
                    // instead of a bare rectangle. The image covers it the moment it lands.
                    Image(systemName: "photo")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(ThemeColor.textTertiary)
                    RemoteImageView(url: url, contentMode: .fill, maxPixel: 288)
                }
                // The tint-to-image fade is `CachedAsyncImage`'s own; there is no insertion here
                // to drive, so no `.transition` is claimed for it.
                .animation(ThemeMotion.pick(ThemeMotion.uiPoster, reduceMotion: reduceMotion),
                           value: tint)
                .frame(width: EpisodeArtwork.slot.width, height: EpisodeArtwork.slot.height)
                .clipShape(RoundedRectangle(cornerRadius: ThemeRadius.episodeStill, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: ThemeRadius.episodeStill, style: .continuous)
                    .strokeBorder(ThemeColor.posterEdge, lineWidth: 1))
                .task(id: url) {
                    tint = await PaletteCache.shared.resolve(url: url, maxPixel: 288)
                }
            } else {
                EpisodeGlyphTile(showTint: showTint)
            }
        }
        .accessibilityHidden(true)
    }

    /// One rectangle for every episode row, still or not. The shipped build put a 96×54 photograph
    /// on rows that had one and a 48×48 square on rows that did not, so a season list changed
    /// shape halfway down and the row rhythm broke with it.
    static let slot = CGSize(width: 96, height: 54)
}

/// The no-still episode tile: the SAME 96×54 rectangle as a real still, filled with the show's own
/// palette colour under a very quiet glyph. No image, no number, no blur — and no grey box.
struct EpisodeGlyphTile: View {
    var showTint: Color? = nil

    var body: some View {
        RoundedRectangle(cornerRadius: ThemeRadius.episodeStill, style: .continuous)
            .fill(showTint ?? ThemeColor.surfaceRaised)
            .frame(width: EpisodeArtwork.slot.width, height: EpisodeArtwork.slot.height)
            .overlay {
                // Darkened, so the tile never competes with the row beside it that has real art.
                LinearGradient(colors: [.black.opacity(0.10), .black.opacity(0.34)],
                               startPoint: .top, endPoint: .bottom)
            }
            .overlay(
                Image(systemName: "play.rectangle")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(ThemeColor.textPrimary.opacity(0.34))
            )
            .clipShape(RoundedRectangle(cornerRadius: ThemeRadius.episodeStill, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: ThemeRadius.episodeStill, style: .continuous)
                .strokeBorder(ThemeColor.posterEdge, lineWidth: 1))
            .accessibilityHidden(true)
    }
}

// MARK: - Small passive primitives

/// A completed thing. Never a button, never accent — "complete" is a fact, not an action.
/// `boxed` puts it in a 44×44 box so a row's trailing edge lines up with a real control.
struct PassiveTick: View {
    var boxed: Bool = false

    var body: some View {
        // A bare check, not a filled disc. `checkmark.circle.fill` at tertiary grey renders as a
        // 18-pt grey blob — read as a disabled control rather than as a settled fact — and a column
        // of them down a season list is the "grey tick glyphs" complaint exactly.
        Image(systemName: "checkmark")
            .font(.system(size: 14, weight: .semibold))
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
        // The 28 %-wide segment travels from -0.28w to 1.0w, i.e. fully outside the track at both
        // ends. Without this it paints over the 16-pt gutters and whatever sits beside the field.
        .clipped()
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
                    PosterSlot(url: cover, .row)
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
                    // `InlineLinkButtonStyle`, not `TertiaryButtonStyle2`: a section header's
                    // action is a LINK. At 16-pt semibold amber it was optically larger than the
                    // 11-pt label it belongs to, so on Library and Today "See all" read as the
                    // loudest thing in the section — louder than the shows.
                    .buttonStyle(InlineLinkButtonStyle())
                    // The style's target is held by padding + `contentShape`, so the row is pulled
                    // back optically instead of clamped: this shrinks the *layout* height to ~20 pt
                    // while the hit region stays ≥ 44 pt tall.
                    .padding(.vertical, -12)
            }
        }
        // That negative padding leaves the button DRAWING and HIT-TESTING 12 pt above and below
        // the row's layout rect. Siblings laid out after the header would otherwise win the taps
        // in the lower overlap band whenever the stack's spacing is under 12 pt, quietly eating
        // the bottom quarter of a 44-pt target. The header paints (and tests) above them.
        .zIndex(1)
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
                .strokeBorder(ThemeColor.stroke, lineWidth: 1))
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
                    PosterSlot(url: poster, .queue)
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
            .surface(.raised, radius: ThemeRadius.row)
            // The active session keeps its accent ring: here the colour IS the state, and the
            // ring is the only thing separating this card from its identical neighbours.
            .overlay {
                if active {
                    RoundedRectangle(cornerRadius: ThemeRadius.row, style: .continuous)
                        .strokeBorder(ThemeColor.accent.opacity(0.45), lineWidth: 1)
                }
            }
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
    /// Identifies the COMMIT, not the state. `nil` = no milestone on this card.
    let token: UUID?
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
            // Keyed on the commit token, and claimed against a ledger that outlives the view.
            // `onChange` alone is not enough: a card scrolled off and back, a tab switch or a
            // recycled row RE-CREATES this modifier with `progress` back at 0 and `initial: true`
            // firing again, which would replay the whole 520-ms draw for a milestone the user
            // already saw. A commit is acknowledged exactly once.
            .onChange(of: token, initial: true) { _, token in
                guard let token else { progress = 0; return }
                guard SeasonSweepLedger.claim(token) else { progress = 1; return }
                if reduceMotion {
                    progress = 1
                } else {
                    withAnimation(ThemeMotion.uiSweep) { progress = 1 }
                }
            }
    }
}

/// Which sweep commits have already been drawn in this process.
///
/// It cannot be `@State`: `@State` dies with the view, and the case this exists for is precisely
/// the view being re-created while the milestone is still true. Bounded to the last 32 commits —
/// a token that has scrolled out of the ledger belongs to a milestone long past its card.
@MainActor
enum SeasonSweepLedger {
    private static var drawn: [UUID] = []
    private static let limit = 32

    /// `true` exactly once per token: the caller owns the draw. Every later call snaps to done.
    static func claim(_ token: UUID) -> Bool {
        if drawn.contains(token) { return false }
        drawn.append(token)
        if drawn.count > limit { drawn.removeFirst(drawn.count - limit) }
        return true
    }

    /// Sign-out. The next account's first season completion is its own.
    static func reset() { drawn.removeAll() }
}

extension View {
    /// Applied to the title of a card whose season just completed. `token` identifies the WRITE
    /// that completed the season — mint a fresh `UUID` when the mark lands, keep it for as long as
    /// the card wants to carry the hairline, and pass `nil` when there is no milestone. Passing a
    /// `Bool` was the earlier shape and could not survive the view being re-created: the sweep
    /// replayed on every scroll back.
    func seasonCompleteSweep(token: UUID?, reduceMotion: Bool) -> some View {
        modifier(SeasonCompleteSweep(token: token, reduceMotion: reduceMotion))
    }

    /// `contentTransition(.numericText())` on the four numbers board 12 allows it on: the backlog
    /// count after a mark, the library count, a confirmation summary, and the foreground
    /// countdown. Nowhere else — constant movement turns state into spectacle.
    ///
    /// SwiftUI does **not** disable `.numericText()` under Reduce Motion, so the check lives here,
    /// once, rather than in every caller: with Reduce Motion on the digits crossfade instead of
    /// rolling. There is no non-value overload — a numeric roll needs the value it is rolling to.
    func numericFact<V: Equatable>(_ value: V) -> some View {
        modifier(NumericFact(value: value))
    }

    /// The freshness pair, composed once so that five screens do not hand-assemble it five ways:
    /// the 16-pt `RefreshIndicator` trails the screen title, and the 28-pt `StaleStrip` sits
    /// directly beneath it whenever this data class is past its threshold. Applied to a screen's
    /// title view. `pullDriving` is passed when a native pull owns the moment — the system
    /// indicator is then the only spinner on screen.
    func freshness(_ dataClass: SyncCenter.DataClass,
                   appModel: AppModel,
                   pullDriving: Bool = false) -> some View {
        modifier(Freshness(dataClass: dataClass, appModel: appModel, pullDriving: pullDriving))
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

/// Reduce Motion aware numeric transition. `.numericText()` rolls digits; under Reduce Motion the
/// roll is replaced by an opacity crossfade on the reduced curve.
private struct NumericFact<V: Equatable>: ViewModifier {
    let value: V

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .contentTransition(reduceMotion ? .opacity : .numericText())
            .animation(ThemeMotion.pick(ThemeMotion.uiNumeric, reduceMotion: reduceMotion),
                       value: value)
    }
}

private struct Freshness: ViewModifier {
    let dataClass: SyncCenter.DataClass
    let appModel: AppModel
    let pullDriving: Bool

    func body(content: Content) -> some View {
        VStack(alignment: .leading, spacing: ThemeSpace.x1) {
            HStack(alignment: .firstTextBaseline, spacing: ThemeSpace.x2) {
                content
                RefreshIndicator(isRefreshing: appModel.isRefreshing, suppressed: pullDriving)
                Spacer(minLength: 0)
            }
            if let since = appModel.staleSince(dataClass) {
                // 4 pt below the title (the VStack's own spacing), 8 pt above the first content
                // block — the strip is part of the header's rhythm, not a band pressed into it.
                StaleStrip(since: since, now: appModel.now)
                    .padding(.bottom, ThemeSpace.x2)
            }
        }
        // Both halves arrive and leave on the same gentle curve; neither is ever a spring.
        .animation(ThemeMotion.uiGentle, value: appModel.isRefreshing)
        .animation(ThemeMotion.uiGentle, value: appModel.staleSince(dataClass))
    }
}

private struct PreviouslyRefreshable: ViewModifier {
    let threshold: CGFloat
    let action: @Sendable () async -> Void

    @State private var armed = false
    /// A finger is on the glass. Scroll geometry alone cannot tell a pull from a momentum bounce.
    @State private var dragging = false

    func body(content: Content) -> some View {
        let run = action
        return content
            .refreshable { await run() }
            .onScrollPhaseChange { _, phase, _ in
                dragging = (phase == .tracking || phase == .interacting)
                // A bounce that ends without a refresh leaves nothing armed behind it.
                if phase == .idle { armed = false }
            }
            .onScrollGeometryChange(for: CGFloat.self) { geo in
                -(geo.contentOffset.y + geo.contentInsets.top)
            } action: { _, pull in
                let progress = pull / threshold
                // `dragging` is the whole point: a fast flick to the top overshoots well past the
                // threshold under momentum with no finger down, and the system `refreshable` does
                // NOT fire for that. `.refreshArmed` promises "let go now and it refreshes", so it
                // may only fire while there is something to let go of.
                if !armed, dragging, progress >= 1 {
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
            .seasonCompleteSweep(token: UUID(), reduceMotion: true)
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
            .seasonCompleteSweep(token: UUID(), reduceMotion: false)
            .padding(.bottom, ThemeSpace.x2)
    }
    .padding(ThemeSpace.x4)
    .background(ThemeColor.canvas)
}
