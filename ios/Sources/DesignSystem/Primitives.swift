import SwiftUI

// Component primitives for the interaction system (spec board 10). Each has exact geometry,
// named states, and no local colour or radius values.

// MARK: - Surfaces

/// The surface hierarchy, as one decision instead of forty.
///
/// The shipped build gave every container the same treatment — `surfaceFlat` plus a 1-px
/// `stroke` — so a menu, a card, a row group and an error notice were the same object at four
/// sizes. Depth then had nowhere to go and the whole app read as a wireframe.
///
/// The rule from here: **tone separates, light describes, strokes are for things that float.**
///
/// | Level      | Fill               | Edge                  | Shadow     | Used by                              |
/// |------------|--------------------|-----------------------|------------|--------------------------------------|
/// | `.plate`   | `surfaceFlat`      | none                  | none       | grouped lists, section grounds, notices |
/// | `.raised`  | `surfaceRaised`    | top hairline          | `.card`    | a card that carries an action        |
/// | `.floating`| `surfaceFloating`  | `strokeStrong` all round | `.floating` | toast, sync banner, menu-like chrome |
/// | `.art`     | derived palette    | top hairline          | `.card`    | Focus / Recap / hero identity cards  |
///
/// Nothing else is a legal container. If a surface needs an outline to be visible, it is the wrong
/// level — move it up, do not draw a box around it.
enum SurfaceLevel: Equatable {
    /// Sits ON the canvas and holds rows. No edge at all: the fill is the whole statement.
    case plate
    /// Sits ABOVE a plate or the canvas and carries the screen's action.
    case raised
    /// Sits OVER content it must never be confused with.
    case floating
    /// Identity: the ground is derived from the artwork. `tint` is `PaletteCache`'s colour.
    case art(Color?)

    var fill: Color {
        switch self {
        case .plate: return ThemeColor.surfaceFlat
        case .raised: return ThemeColor.surfaceRaised
        case .floating: return ThemeColor.surfaceFloating
        case .art: return ThemeColor.surfaceFlat
        }
    }

    var shadow: ShadowToken {
        switch self {
        case .plate: return .none
        case .raised, .art: return .card
        case .floating: return .floating
        }
    }
}

private struct SurfaceModifier: ViewModifier {
    let level: SurfaceLevel
    let radius: CGFloat

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: radius, style: .continuous) }

    func body(content: Content) -> some View {
        content
            .background {
                if case .art(let tint) = level {
                    ArtAdaptiveGround(tint: tint)
                } else {
                    level.fill
                }
            }
            .clipShape(shape)
            .overlay { edge }
            .shadow(level.shadow)
    }

    /// A raised surface is lit from above, so its highlight lives on the TOP edge and dies by the
    /// vertical centre. A ring of uniform grey is the thing this replaces.
    @ViewBuilder
    private var edge: some View {
        switch level {
        case .plate:
            EmptyView()
        case .raised, .art:
            shape.strokeBorder(
                LinearGradient(colors: [ThemeColor.hairline, .clear],
                               startPoint: .top, endPoint: .center),
                lineWidth: 1
            )
            .allowsHitTesting(false)
        case .floating:
            shape.strokeBorder(ThemeColor.strokeStrong, lineWidth: 1)
                .allowsHitTesting(false)
        }
    }
}

extension View {
    /// Apply a surface level. This is the ONLY way a container gets a ground in this app.
    func surface(_ level: SurfaceLevel, radius: CGFloat = ThemeRadius.card) -> some View {
        modifier(SurfaceModifier(level: level, radius: radius))
    }
}

// MARK: - Poster slot

/// Identity artwork: always aspect-fit in its slot, never cropped. The slot is the cached palette
/// tint first (never grey), the poster cross-dissolves in over 180 ms. Missing art keeps the tint
/// with a centred `photo` symbol.
struct PosterSlot: View {
    let url: String?
    let width: CGFloat
    let height: CGFloat
    var radius: CGFloat = ThemeRadius.poster
    /// The contact shadow under the art. Defaults to the size-appropriate token — art at or above
    /// 88 pt on its long edge reads as a physical object and gets one; a 44-pt thumb does not.
    var shadow: ShadowToken

    @State private var tint: Color?

    init(url: String?, width: CGFloat, height: CGFloat,
         radius: CGFloat = ThemeRadius.poster, shadow: ShadowToken? = nil) {
        self.url = url
        self.width = width
        self.height = height
        self.radius = radius
        self.shadow = shadow ?? (max(width, height) >= 88 ? .art : .none)
    }

    /// The context form: `PosterSlot(url: cover, .row)`. Size, radius and shadow all come from the
    /// slot table so a screen never has to remember three numbers.
    init(url: String?, _ slot: PosterSize) {
        self.init(url: url, width: slot.size.width, height: slot.size.height,
                  radius: slot.radius, shadow: slot.shadow)
    }

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
        // `posterEdge` (white 5 %), not `separator` (8 %): the job is to stop a dark poster
        // dissolving into a black canvas, NOT to draw a frame around every piece of artwork. The
        // shipped build's outline is visible ON the art at the top of a bright poster — a grey
        // hairline over someone's illustration is the definition of cheap.
        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
            .strokeBorder(ThemeColor.posterEdge, lineWidth: 1))
        .shadow(shadow)
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
            // A lit top edge. Flat #F0A24E across 48×376 pt is a swatch of orange; one 22 %-white
            // hairline along the top, dead by the vertical centre, is what makes it read as a
            // physical, pressable object — the same trick every native filled control uses.
            .overlay(Capsule().strokeBorder(
                LinearGradient(colors: [ThemeColor.controlSheen, .clear],
                               startPoint: .top, endPoint: .center),
                lineWidth: 1))
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
            // `strokeBorder`, not `stroke`: a centred 1-pt line straddles the capsule's edge and
            // renders as a soft 2-px smear on the outside of the shape. A CONTROL is allowed a
            // full-perimeter edge (a container is not) — but it has to be a crisp one.
            .overlay(Capsule().strokeBorder(ThemeColor.stroke, lineWidth: 1))
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
///
/// `radius` must match the surface being pressed. Left at the default, a pressed 24-pt Focus card
/// paints a 16-pt highlight inside its own corners — a 4-pt sliver of un-highlighted card at each
/// corner, visible on every single tap of the app's most important control.
struct RowPressStyle: ButtonStyle {
    var radius: CGFloat = ThemeRadius.row

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(ThemeColor.surfacePressed.opacity(configuration.isPressed ? 0.6 : 0)))
            .scaleEffect(configuration.isPressed ? 0.992 : 1)
            .animation(configuration.isPressed ? ThemeMotion.uiPress : ThemeMotion.uiMicro, value: configuration.isPressed)
    }
}

/// An inline text action beside a label — "See all", "Clear", "Read more". Accent, footnote
/// semibold, 44-pt target held by `contentShape` rather than by a frame, so it can sit on a
/// section header's baseline without shoving the header 12 pt taller.
struct InlineLinkButtonStyle: ButtonStyle {
    var destructive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .type(ThemeType.listAction)
            .foregroundStyle(destructive ? ThemeColor.destructive : ThemeColor.accent)
            .padding(.vertical, 12)
            .padding(.leading, 12)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.55 : 1)
            .animation(ThemeMotion.uiPress, value: configuration.isPressed)
    }
}

// MARK: - Labels

/// Eyebrow / section label: caption2 semibold, +1.0 tracking, tertiary, uppercase via textCase.
/// The optional 4-pt leading dot means "newly changed" only.
struct SectionLabel: View {
    let text: String
    var dot = false
    var tint: Color = ThemeColor.textTertiary
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if dot { Circle().fill(ThemeColor.accent).frame(width: 4, height: 4) }
            Text(text).type(ThemeType.sectionLabel).textCase(.uppercase)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(tint)
        .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
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
        // `chromeGlass`, not `glassChrome`: identical on a normal device, and the solid
        // `surfaceFloating` fallback the spec asks for when Reduce Transparency is on.
        .chromeGlass(in: Capsule(), interactive: true)
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
        VStack(alignment: .leading, spacing: ThemeMetrics.labelGap) {
            if let header {
                SectionLabel(text: header).padding(.leading, ThemeSpace.x4)
            }
            // A plate, not a stroked box: this is the iOS grouped-table grammar, and a grouped
            // table has never had an outline. The fill IS the group.
            VStack(spacing: 0) { content() }
                .surface(.plate, radius: ThemeRadius.row)
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
            .frame(minHeight: ThemeMetrics.rowCompact)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                if separator {
                    // `separatorQuiet`: eight of these down one plate at 8 % white is a grid.
                    Rectangle().fill(ThemeColor.separatorQuiet).frame(height: 1).padding(.leading, symbol == nil ? 14 : 54)
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

// MARK: - Media row

/// The canonical repeating row: artwork, an identity title, one fact, one optional forward-looking
/// fact in accent, and a trailing control. Library, Schedule, Search and Detail all render this
/// shape; the shipped build hand-rolled it four times at four sizes with four different poster
/// slots, which is most of why the app read as four apps.
///
/// It sits on the CANVAS with a hairline under it — not inside a stroked box. A list of shows is
/// not a form.
struct MediaRow<Trailing: View>: View {
    let title: String
    var meta: String? = nil
    /// The forward-looking fact: "Returns Oct 2", "Episode 19 next". Amber, because a real next
    /// step is exactly what amber is for. Never use it for a status that has already happened.
    var lead: String? = nil
    var poster: String? = nil
    var slot: PosterSize = .row
    var chevron: Bool = true
    var dimmed: Bool = false
    var separator: Bool = true
    @ViewBuilder var trailing: () -> Trailing
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    private var isAX: Bool { typeSize.isAccessibilitySize }

    var body: some View {
        Button(action: action) {
            HStack(spacing: ThemeMetrics.artGap) {
                if poster != nil { PosterSlot(url: poster, slot) }
                VStack(alignment: .leading, spacing: ThemeMetrics.titleGap) {
                    Text(title)
                        .type(ThemeType.rowTitle)
                        .foregroundStyle(ThemeColor.textPrimary)
                        .lineLimit(isAX ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                    if let lead {
                        Text(lead)
                            .type(ThemeType.rowMetaLead)
                            .foregroundStyle(ThemeColor.accent)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let meta {
                        Text(meta)
                            .type(ThemeType.rowMeta)
                            .foregroundStyle(ThemeColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: ThemeSpace.x3)
                trailing()
                if chevron {
                    Image(systemName: "chevron.forward")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ThemeColor.textDisabled)
                }
            }
            .padding(.vertical, ThemeSpace.x2)
            .frame(minHeight: slot == .row ? ThemeMetrics.rowStandard : ThemeMetrics.rowMedia,
                   alignment: .leading)
            .contentShape(Rectangle())
            // Past / already-handled rows recede as a GROUP rather than each element being given
            // its own grey — one opacity keeps the artwork's colour relationship intact.
            .opacity(dimmed ? 0.45 : 1)
            .overlay(alignment: .bottom) {
                if separator {
                    Rectangle().fill(ThemeColor.separatorQuiet)
                        .frame(height: 1)
                        .padding(.leading, poster == nil ? 0 : slot.size.width + ThemeMetrics.artGap)
                }
            }
        }
        .buttonStyle(RowPressStyle())
        .accessibilityElement(children: .combine)
    }
}

extension MediaRow where Trailing == EmptyView {
    init(title: String, meta: String? = nil, lead: String? = nil, poster: String? = nil,
         slot: PosterSize = .row, chevron: Bool = true, dimmed: Bool = false,
         separator: Bool = true, action: @escaping () -> Void) {
        self.init(title: title, meta: meta, lead: lead, poster: poster, slot: slot,
                  chevron: chevron, dimmed: dimmed, separator: separator,
                  trailing: { EmptyView() }, action: action)
    }
}

// MARK: - Shelf card

/// One poster on a horizontal shelf. Two things the shipped build got wrong and this fixes:
/// the caption block reserves **two lines whether or not the title needs them**, so a shelf of
/// mixed-length titles keeps one baseline instead of a staircase; and the forward-looking caption
/// is allowed to be accent, because "Returns Oct 2" is the reason the shelf exists.
struct ShelfCard: View {
    let title: String
    var caption: String? = nil
    var captionIsLead: Bool = false
    var poster: String? = nil
    var slot: PosterSize = .shelfLarge
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: ThemeSpace.x2) {
                PosterSlot(url: poster, slot)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .type(ThemeType.shelfTitle)
                        .foregroundStyle(ThemeColor.textPrimary)
                        .lineLimit(2, reservesSpace: !typeSize.isAccessibilitySize)
                        .multilineTextAlignment(.leading)
                    if let caption {
                        Text(caption)
                            .type(ThemeType.shelfCaption)
                            .foregroundStyle(captionIsLead ? ThemeColor.accent : ThemeColor.textSecondary)
                            .lineLimit(1)
                    }
                }
                .frame(width: slot.size.width, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle(radius: slot.radius))
        .accessibilityElement(children: .combine)
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
            .surface(.plate, radius: ThemeRadius.row)
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
        .surface(.floating, radius: ThemeRadius.toast)
        // A failure toast keeps its warning edge ON TOP of the floating stroke — the one place a
        // full-perimeter stroke earns its keep, because the colour is the message.
        .overlay {
            if failure {
                RoundedRectangle(cornerRadius: ThemeRadius.toast, style: .continuous)
                    .strokeBorder(ThemeColor.warning.opacity(0.5), lineWidth: 1)
            }
        }
        .transition(.opacity.combined(with: .offset(y: 4)))
    }
}

// MARK: - Chrome edges

/// The scroll edge.
///
/// The single most damaging detail in the shipped build is invisible in a design tool and obvious
/// on a device: **content scrolls straight through the status bar**. On Schedule a poster and a
/// truncated show title sit on top of the clock; on Library a poster crosses the Dynamic Island.
/// No shipping media app does this, and no amount of card polish survives it.
///
/// The fix is one veil per root screen: full canvas through the status-bar band, gone 22 pt below
/// it. Content does not slide under a grey bar — it dissolves into the app. `.ultraThinMaterial`
/// rides along, masked to the same band, so what is dissolving also softens; under Reduce
/// Transparency the material is dropped and the canvas veil does the whole job.
///
/// Apply it to the root of a scrolling screen, OUTSIDE the scroll view:
/// ```swift
/// ZStack { ArtBackdrop(...); ScrollView { … } }.scrollEdgeChrome()
/// ```
struct ScrollEdgeChrome: View {
    enum Side { case top, bottom }
    let side: Side
    /// Top only: total height, safe area included.
    var height: CGFloat = ThemeMetrics.topChromeHeight

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var hold: CGFloat { max(0, min(1, ThemeMetrics.topSafeInset / max(height, 1))) }

    /// Canvas opacity from the screen edge inward. The top holds full canvas across the whole
    /// status bar, then falls off fast; the bottom never reaches full, because the tab bar is
    /// glass and glass with nothing behind it is a grey pill.
    private var veil: LinearGradient {
        switch side {
        case .top:
            return LinearGradient(stops: [
                .init(color: ThemeColor.chromeVeil, location: 0),
                .init(color: ThemeColor.chromeVeil, location: hold),
                .init(color: ThemeColor.chromeVeil.opacity(0.34), location: hold + (1 - hold) * 0.45),
                .init(color: ThemeColor.chromeVeil.opacity(0), location: 1),
            ], startPoint: .top, endPoint: .bottom)
        case .bottom:
            return LinearGradient(stops: [
                .init(color: ThemeColor.chromeVeil.opacity(0), location: 0),
                .init(color: ThemeColor.chromeVeil.opacity(0.30), location: 0.52),
                .init(color: ThemeColor.chromeVeil.opacity(0.78), location: 1),
            ], startPoint: .top, endPoint: .bottom)
        }
    }

    /// The blur runs out on exactly the same ramp as the veil, and reaches zero at the same
    /// place. A mask that terminates while the veil is still at a third leaves a visible seam
    /// straight across the screen — which is precisely what a hand-rolled scroll edge looks like.
    private var blurMask: LinearGradient {
        switch side {
        case .top:
            return LinearGradient(stops: [
                .init(color: .black, location: 0),
                .init(color: .black, location: hold * 0.85),
                .init(color: .black.opacity(0.42), location: hold + (1 - hold) * 0.45),
                .init(color: .clear, location: 1),
            ], startPoint: .top, endPoint: .bottom)
        case .bottom:
            return LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .black.opacity(0.34), location: 0.52),
                .init(color: .black.opacity(0.85), location: 1),
            ], startPoint: .top, endPoint: .bottom)
        }
    }

    var body: some View {
        ZStack {
            if !reduceTransparency {
                Rectangle().fill(.ultraThinMaterial).mask(blurMask)
            }
            veil
        }
        .frame(height: side == .top ? height : ThemeMetrics.bottomChromeHeight)
        .frame(maxWidth: .infinity)
        .ignoresSafeArea(edges: side == .top ? .top : .bottom)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct ScrollEdgeChromeModifier: ViewModifier {
    let top: Bool
    let bottom: Bool
    let topHeight: CGFloat

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) { if bottom { ScrollEdgeChrome(side: .bottom) } }
            .overlay(alignment: .top) { if top { ScrollEdgeChrome(side: .top, height: topHeight) } }
    }
}

/// Reads the accessibility environment so `chromeGlass` can branch on it.
struct ChromeGlassBox<S: Shape, Content: View>: View {
    let shape: S
    let interactive: Bool
    @ViewBuilder var content: () -> Content

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if reduceTransparency {
            content()
                .background(ThemeColor.surfaceFloating, in: shape)
                .overlay(shape.stroke(ThemeColor.strokeStrong, lineWidth: 1))
        } else {
            content().glassChrome(in: shape, interactive: interactive)
        }
    }
}

extension View {
    /// Give a scrolling root screen its status-bar and tab-bar edges. Every root screen gets this;
    /// a pushed screen with a real navigation bar does not need it.
    func scrollEdgeChrome(top: Bool = true, bottom: Bool = true,
                          topHeight: CGFloat = ThemeMetrics.topChromeHeight) -> some View {
        modifier(ScrollEdgeChromeModifier(top: top, bottom: bottom, topHeight: topHeight))
    }

    /// Native Liquid Glass for chrome, with the Reduce Transparency fallback the spec requires
    /// (`surfaceFloating` + `strokeStrong`, no refraction). `glassChrome` alone keeps refracting
    /// when the user has asked it not to.
    func chromeGlass(in shape: some Shape, interactive: Bool = false) -> some View {
        ChromeGlassBox(shape: shape, interactive: interactive) { self }
    }
}

// MARK: - Full-bleed art

/// The vertical scrim over full-bleed artwork: it protects the status bar at the top and hands the
/// image over to the canvas at the bottom, in one gradient with a transparent middle so the art is
/// never uniformly greyed.
///
/// The shipped build has no full-bleed art anywhere, which is why it lost the atmosphere the
/// original had. Anything that puts art behind text uses this — nobody hand-rolls a black overlay.
struct ArtScrim: View {
    /// Protection at the top, for the status bar and any floating toolbar.
    var top: Double = 1
    /// The handover to the canvas at the bottom.
    var bottom: Double = 1

    var body: some View {
        LinearGradient(stops: [
            .init(color: .black.opacity(0.55 * top), location: 0.00),
            .init(color: .black.opacity(0.16 * top), location: 0.22),
            .init(color: .clear, location: 0.46),
            .init(color: ThemeColor.canvas.opacity(0.55 * bottom), location: 0.80),
            .init(color: ThemeColor.canvas.opacity(1.00 * bottom), location: 1.00),
        ], startPoint: .top, endPoint: .bottom)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A cinematic, edge-to-edge art header with content laid over its lower third.
///
/// This is the shape the ORIGINAL Today and Detail screens had and the rebuild replaced with a
/// 78-pt thumbnail beside a 20-pt title. Identity art is this product's only real material; when
/// it is 78 pt wide inside a stroked box there is nothing left for the design to be made of.
///
/// The art fills and crops (a hero is a backdrop, not a poster — `PosterSlot` is for artwork that
/// must stay whole). Everything the caller passes is bottom-aligned inside the gutter.
struct ArtHeader<Overlay: View>: View {
    let url: String?
    /// Full height of the art, safe area included. 0.44–0.52 × screen height is the cinematic band.
    var height: CGFloat
    /// Palette colour, used as the ground until the image decodes so the header never flashes black.
    var tint: Color? = nil
    var scrimTop: Double = 1
    var scrimBottom: Double = 1
    @ViewBuilder var overlay: () -> Overlay

    var body: some View {
        ZStack(alignment: .bottom) {
            (tint ?? PaletteCache.fallback)
            if let url, !url.isEmpty {
                RemoteImageView(url: url, contentMode: .fill, maxPixel: 1200)
                    .transition(.opacity)
            }
            ArtScrim(top: scrimTop, bottom: scrimBottom)
            overlay()
                .padding(.horizontal, ThemeMetrics.gutter)
                .padding(.bottom, ThemeSpace.x5)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipped()
    }
}

/// An eyebrow that sits ON artwork — "CONTINUE", "NEW EPISODE", "AIRED 10H AGO".
///
/// Over a photograph, plain tertiary-grey caps are unreadable half the time and washed out the
/// rest. A dark capsule makes it legible over anything and reads as a label rather than as text
/// that happens to be floating.
struct OverArtLabel: View {
    let text: String
    var dot: Bool = false
    var tint: Color = ThemeColor.textPrimary

    var body: some View {
        HStack(spacing: 6) {
            if dot { Circle().fill(ThemeColor.accent).frame(width: 5, height: 5) }
            Text(text).type(ThemeType.sectionLabel).textCase(.uppercase)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(ThemeColor.scrimStrong, in: Capsule())
        .overlay(Capsule().strokeBorder(ThemeColor.hairline, lineWidth: 1))
    }
}

// MARK: - Chips

/// A selectable chip — search scope, a recent query, a filter value.
///
/// Unselected chips carry NO stroke. The shipped Search screen draws a grey-outlined pill for
/// every scope and every recent query, so eight outlined objects compete with the three posters
/// underneath them. Tone alone separates an unselected chip from the canvas; the selected one is
/// the only chip allowed to use colour, which is what makes the selection readable at a glance.
struct ChipButtonStyle: ButtonStyle {
    var selected: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .type(ThemeType.metadataEmphasis)
            .foregroundStyle(selected ? ThemeColor.onAccent : ThemeColor.textSecondary)
            .padding(.horizontal, 14)
            .frame(minHeight: 34)
            .background {
                Capsule().fill(
                    selected
                        ? (configuration.isPressed ? ThemeColor.accentPressed : ThemeColor.accent)
                        : (configuration.isPressed ? ThemeColor.surfacePressed : ThemeColor.surfaceRaised)
                )
            }
            .overlay {
                if selected {
                    Capsule().strokeBorder(
                        LinearGradient(colors: [ThemeColor.controlSheen, .clear],
                                       startPoint: .top, endPoint: .center),
                        lineWidth: 1)
                }
            }
            .contentShape(Capsule())
            .frame(minHeight: 44)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(ThemeMotion.uiPress, value: configuration.isPressed)
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
