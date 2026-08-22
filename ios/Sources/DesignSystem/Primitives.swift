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
            .background { ground }
            .clipShape(shape)
            .overlay { edge }
            .shadow(level.shadow)
    }

    /// `.plate` and `.raised` are a LIFT over whatever they sit on, not an absolute fill. Painting
    /// an opaque near-black over an ambient art wash is what turned every plate into a hole (SYS-3);
    /// white over the same ground always reads as a step up, wash or no wash.
    ///
    /// `.floating` stays opaque on purpose: it is the one level that covers content it must never
    /// be mistaken for, and a translucent toast with a shelf scrolling through it is worse than a
    /// flat one.
    @ViewBuilder
    private var ground: some View {
        switch level {
        case .art(let tint): ArtAdaptiveGround(tint: tint)
        case .plate: ThemeColor.plateLift
        case .raised: ThemeColor.raisedLift
        case .floating: level.fill
        }
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

/// Identity artwork, filling its slot.
///
/// The shipped build aspect-**fitted** every poster into a fixed 2:3 frame. AniList and TMDB
/// covers are ~0.708, so every single piece of artwork in the app carried a 5–6 pt bar of exact
/// `surfaceRaised` grey across its top and bottom — with the art's square corners sitting inside a
/// rounded frame, so dark wedges showed at all four corners too, and TMDB's true 2:3 posters
/// filled while AniList's matted, two art behaviours side by side in one grid. A 0.708 → 0.667
/// crop loses 4 % of image height and is invisible; a 6-pt grey bar is not.
///
/// The slot is the cached palette tint first (never grey), the poster cross-dissolves in over
/// 180 ms. Missing art keeps the tint with a centred `photo` symbol.
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
            // The ground under the art while it decodes: the show's own colour, never grey. With
            // the poster filling the slot this is only ever visible for the 180 ms before the
            // image lands, or on a title with no artwork at all.
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(ThemeColor.surfaceRaised)
            if let tint {
                RoundedRectangle(cornerRadius: radius, style: .continuous).fill(tint.opacity(0.22))
            }
            if let url, !url.isEmpty {
                // `.fill`, and no blur backfill behind it. The blurred second copy existed purely
                // to disguise the mat this crop removes — and it cost a second full decode plus a
                // blur pass on every slot ≥ 72 pt, i.e. 60 of each on a 30-title poster grid.
                RemoteImageView(url: url, contentMode: .fill, maxPixel: max(width, height) * 3)
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

// MARK: Press feedback
//
// Board 11: Reduce Motion presses in OPACITY, never in scale. `CompactActionButtonStyle` was the
// only style in the shipped build that actually did it — every other style animated a raw
// `ThemeMotion.uiPress` and compressed unconditionally. This is that one pattern, written once.
private extension View {
    @ViewBuilder
    func pressFeedback(_ isPressed: Bool, reduceMotion: Bool, scale: CGFloat = 0.985) -> some View {
        self
            .opacity(reduceMotion && isPressed ? 0.72 : 1)
            .scaleEffect(reduceMotion ? 1 : (isPressed ? scale : 1))
            .animation(ThemeMotion.pick(ThemeMotion.uiPress, reduceMotion: reduceMotion),
                       value: isPressed)
    }
}

/// 48-pt capsule, accent on onAccent, press 0.985, disabled 0.38. Label comes from the copy table.
struct PrimaryButtonStyle2: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
            .pressFeedback(configuration.isPressed, reduceMotion: reduceMotion)
    }
}

/// 44-pt capsule on surfaceFloating with a stroke.
struct SecondaryButtonStyle2: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
            .pressFeedback(configuration.isPressed, reduceMotion: reduceMotion)
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(ThemeColor.surfacePressed.opacity(configuration.isPressed ? 0.6 : 0)))
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.992 : 1))
            .animation(ThemeMotion.pick(configuration.isPressed ? ThemeMotion.uiPress : ThemeMotion.uiMicro,
                                        reduceMotion: reduceMotion),
                       value: configuration.isPressed)
    }
}

/// Press feedback for the round mark control: compression only, no rounded-rect wash behind a
/// circle. Promoted out of `ScheduleView` — the episode-row controls and the Search add badge use
/// the same shape and had no press state at all.
struct MarkPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .pressFeedback(configuration.isPressed, reduceMotion: reduceMotion)
    }
}

/// The press state for a target that IS a photograph — the Today hero, the avatar, the recap card.
///
/// Those three are the largest targets on the home screen and had no press state whatsoever
/// (`.buttonStyle(.plain)`, or an `onTapGesture` with no button trait at all). They also may not
/// take `RowPressStyle`: a `surfacePressed` wash over artwork is a grey film over someone's
/// illustration. Art dips in brightness and compresses a hair instead.
struct OverArtPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? (reduceMotion ? 0.72 : 0.88) : 1)
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.99 : 1))
            .animation(ThemeMotion.pick(ThemeMotion.uiPress, reduceMotion: reduceMotion),
                       value: configuration.isPressed)
    }
}

/// One half of a split control: the press darkens only the half under the finger, inside the
/// shared capsule, so the boundary the divider promises is real.
struct SplitHalfStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? ThemeColor.accentPressed : Color.clear)
            .animation(ThemeMotion.pick(ThemeMotion.uiPress, reduceMotion: reduceMotion),
                       value: configuration.isPressed)
    }
}

/// An inline text action beside a label — "See all", "Clear", "Read more". Accent, footnote
/// semibold, 44-pt target held by `contentShape` rather than by a frame, so it can sit on a
/// section header's baseline without shoving the header 12 pt taller.
struct InlineLinkButtonStyle: ButtonStyle {
    var destructive = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .type(ThemeType.listAction)
            .foregroundStyle(destructive ? ThemeColor.destructive : ThemeColor.accent)
            .padding(.vertical, 12)
            .padding(.leading, 12)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.55 : 1)
            .animation(ThemeMotion.pick(ThemeMotion.uiPress, reduceMotion: reduceMotion),
                       value: configuration.isPressed)
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
        // A `Toggle` inside a `Button`'s label does not survive as an independent element:
        // VoiceOver announced "Unwatched only, button" with no switch trait and no On/Off value,
        // and the outer button's hit-test priority made the switch itself unreliable to hit. The
        // toggle case therefore renders a real `Toggle` whose LABEL is the row — one element, with
        // the switch trait, a spoken value, and the whole row as its target.
        if case .toggle(let binding) = trailing {
            Toggle(isOn: binding) { labelStack }
                .toggleStyle(.switch)
                .tint(ThemeColor.accent)
                .padding(.leading, 14).padding(.trailing, 16)
                .frame(minHeight: ThemeMetrics.rowCompact)
                .overlay(alignment: .bottom) { separatorLine }
        } else {
            Button { action?() } label: {
                HStack(spacing: 12) {
                    labelStack
                    Spacer(minLength: 8)
                    trailingView
                }
                .padding(.leading, 14).padding(.trailing, 16)
                .frame(minHeight: ThemeMetrics.rowCompact)
                .contentShape(Rectangle())
                .overlay(alignment: .bottom) { separatorLine }
            }
            .buttonStyle(GroupedRowPressStyle())
            .disabled(action == nil)
        }
    }

    private var labelStack: some View {
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
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var separatorLine: some View {
        if separator {
            // `separatorQuiet`: eight of these down one plate at 8 % white is a grid.
            Rectangle().fill(ThemeColor.separatorQuiet).frame(height: 1)
                .padding(.leading, symbol == nil ? 14 : 54)
        }
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
        case .toggle:
            // Handled by the `Toggle` branch in `body` — a switch is never drawn inside a Button.
            EmptyView()
        case .check(let on):
            Image(systemName: "checkmark").font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ThemeColor.accent).opacity(on ? 1 : 0).frame(width: 22)
        case .none:
            EmptyView()
        }
    }
}

struct GroupedRowPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? ThemeColor.surfacePressed : .clear)
            // The shipped style had NO animation at all: the pressed ground snapped on and off in
            // one frame, in both directions, on the densest grouped-row screens in the app.
            .animation(ThemeMotion.pick(configuration.isPressed ? ThemeMotion.uiPress : ThemeMotion.uiMicro,
                                        reduceMotion: reduceMotion),
                       value: configuration.isPressed)
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
    /// A chevron is a HINT, not an element: it sits with its row's text, never parked at the far
    /// edge of a 200–300 pt empty gutter with the middle 45 % of the row dead.
    var chevron: Bool = true
    var dimmed: Bool = false
    var separator: Bool = true
    /// Registers the row's artwork as the zoom-transition source, so pushing Detail from it grows
    /// out of this poster instead of sliding in from the right.
    var zoomID: String? = nil
    @ViewBuilder var trailing: () -> Trailing
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    private var isAX: Bool { typeSize.isAccessibilitySize }

    var body: some View {
        Button(action: action) {
            HStack(spacing: ThemeMetrics.artGap) {
                if poster != nil {
                    if let zoomID {
                        PosterSlot(url: poster, slot).zoomSource(zoomID)
                    } else {
                        PosterSlot(url: poster, slot)
                    }
                }
                VStack(alignment: .leading, spacing: ThemeMetrics.titleGap) {
                    titleText
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
        // Spelled out rather than left to `.combine`, so the inline chevron glyph is never spoken.
        .accessibilityLabel([title, lead, meta].compactMap { $0 }.joined(separator: ", "))
    }

    /// The chevron is CONCATENATED into the title, so it flows immediately after the last word and
    /// wraps with it. Laid out as a sibling it lands at x≈405 with 200–300 pt of dead gutter
    /// between it and the text it belongs to — the middle 45 % of the row saying nothing.
    private var titleText: Text {
        let name = Text(title)
            .type(ThemeType.rowTitle)
            .foregroundStyle(ThemeColor.textPrimary)
        guard chevron else { return name }
        let hint = Text(Image(systemName: "chevron.forward"))
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(ThemeColor.textDisabled)
        // Interpolation, not `Text + Text` (deprecated in iOS 26). A `Text` interpolated into a
        // `Text` keeps its own font and colour, which `\(Image(...))` alone would not.
        return Text("\(name)\u{2009}\(hint)")
    }
}

extension MediaRow where Trailing == EmptyView {
    init(title: String, meta: String? = nil, lead: String? = nil, poster: String? = nil,
         slot: PosterSize = .row, chevron: Bool = true, dimmed: Bool = false,
         separator: Bool = true, zoomID: String? = nil, action: @escaping () -> Void) {
        self.init(title: title, meta: meta, lead: lead, poster: poster, slot: slot,
                  chevron: chevron, dimmed: dimmed, separator: separator, zoomID: zoomID,
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
    /// Zoom-transition source id for the push into Detail.
    var zoomID: String? = nil
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: ThemeSpace.x2) {
                if let zoomID {
                    PosterSlot(url: poster, slot).zoomSource(zoomID)
                } else {
                    PosterSlot(url: poster, slot)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title.shelfShortened)
                        .type(ThemeType.shelfTitle)
                        .foregroundStyle(ThemeColor.textPrimary)
                        .lineLimit(2, reservesSpace: !typeSize.isAccessibilitySize)
                        // DIRECTION §3: never truncate an identity title. Two lines were correctly
                        // reserved, but nothing caught the titles that overflow them — so the app
                        // cut "That Time I Got / Reincarn…" on a shelf while Library's row rendered
                        // the same title whole. Tightening plus a 0.82 floor buys ~3 characters a
                        // line before anything is lost.
                        .minimumScaleFactor(0.82)
                        .allowsTightening(true)
                        .multilineTextAlignment(.leading)
                    if let caption {
                        Text(caption)
                            .type(ThemeType.shelfCaption)
                            .foregroundStyle(captionIsLead ? ThemeColor.accent : ThemeColor.textSecondary)
                            // Two lines and a tail ellipsis, so the last visible caption ends
                            // inside its own card instead of at the screen bezel.
                            .lineLimit(2)
                            .truncationMode(.tail)
                    }
                }
                .frame(width: slot.size.width, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle(radius: slot.radius))
        .accessibilityElement(children: .combine)
        // The spoken title is the WHOLE title, never the shortened one.
        .accessibilityLabel([title, caption].compactMap { $0 }.joined(separator: ", "))
    }
}

extension String {
    /// Identity titles as a shelf caption can carry them.
    ///
    /// Source titles arrive wrapped in subtitle punctuation — "Re:ZERO -Starting Life in Another
    /// World-" — and a line that opens on a hyphen reads as a hyphenation bug, not as a title.
    /// Stripping the dashes is lossless; what follows the em/en dash or the colon is a subtitle the
    /// shelf never had room for anyway.
    var shelfShortened: String {
        var s = trimmingCharacters(in: .whitespacesAndNewlines)
        // A trailing "-…-" subtitle wrapper.
        if s.hasSuffix("-"), let open = s.range(of: " -") {
            s = String(s[s.startIndex..<open.lowerBound])
        }
        return s.trimmingCharacters(in: CharacterSet(charactersIn: " -\u{2013}\u{2014}:"))
    }
}

extension View {
    /// The horizontal-shelf scroller: art may run off the trailing edge, TYPE may not.
    ///
    /// Every shelf's last card had its title and caption sliced mid-glyph by the hard screen edge
    /// with no fade and no content margin ("Solo L", "Return…", "HELL… / Hardc…"). Apple's shelves
    /// clip *artwork* at the viewport and never leave a title amputated. The trailing margin means
    /// a partial card always shows a poster rather than a fragment of a word, and the mask fades
    /// what does reach the edge. At accessibility sizes the shelf is already a vertical list, so
    /// the mask is skipped.
    func shelfScroller(trailingMargin: CGFloat = 28, masked: Bool = true) -> some View {
        modifier(ShelfScroller(trailingMargin: trailingMargin, masked: masked))
    }
}

private struct ShelfScroller: ViewModifier {
    let trailingMargin: CGFloat
    let masked: Bool

    @Environment(\.dynamicTypeSize) private var typeSize

    func body(content: Content) -> some View {
        let fade = masked && !typeSize.isAccessibilitySize
        return content
            .contentMargins(.trailing, trailingMargin, for: .scrollContent)
            .mask {
                Group {
                    if fade {
                        LinearGradient(stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: 0.93),
                            .init(color: .black.opacity(0), location: 1),
                        ], startPoint: .leading, endPoint: .trailing)
                    } else {
                        Rectangle()
                    }
                }
                // Vertically oversized on purpose. A mask is clipped to its own bounds, so a mask
                // exactly the scroller's height would undo `.scrollClipDisabled()` and shear the
                // posters' `.art` shadow into a hard line along each card's edge — trading one
                // clipping artefact for another.
                .padding(.vertical, -24)
            }
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

/// The canonical toast: a content-width glass **capsule**, centred over the tab bar's own margin.
///
/// The shipped shape — a full-width rounded rectangle with a 1-px perimeter stroke and a trailing
/// amber "Undo" — is an Android Material snackbar in shape, position and construction, and it put
/// a second amber object beside the amber CTA it had just been used to confirm. A capsule that
/// hugs its own text is the iOS grammar (the AirPods / silent-switch HUDs, the Photos "Copied"
/// pill), and hugging means it stops spanning the screen over content the user is reading.
struct ToastView: View {
    let message: String
    var actionLabel: String? = nil
    var failure = false
    var action: (() -> Void)? = nil

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(spacing: ThemeSpace.x3) {
            if failure {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ThemeColor.warning)
            }
            Text(message)
                .type(ThemeType.metadataEmphasis)
                .foregroundStyle(ThemeColor.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            if let actionLabel, let action {
                // Not accent: the mark this toast is confirming was committed by an amber control,
                // and a second amber word 6 pt away competes with it. Weight carries the action.
                Button(actionLabel, action: action)
                    .buttonStyle(ToastActionStyle())
            }
        }
        .padding(.leading, ThemeSpace.x4)
        .padding(.trailing, actionLabel == nil ? ThemeSpace.x4 : ThemeSpace.x1)
        .frame(minHeight: 48)
        // Hugs its content — but never past the screen, and never at accessibility sizes where the
        // message legitimately needs the width.
        .fixedSize(horizontal: !typeSize.isAccessibilitySize, vertical: false)
        .chromeGlass(in: Capsule())
        .shadow(.floating)
        .transition(.opacity)
    }
}

/// The toast's own action. A 44-pt target inside a 48-pt capsule, no container of its own.
private struct ToastActionStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .type(ThemeType.metadataEmphasis)
            .foregroundStyle(ThemeColor.textPrimary)
            .padding(.horizontal, ThemeSpace.x4)
            .frame(minHeight: 44)
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.55 : 1)
            .animation(ThemeMotion.pick(ThemeMotion.uiPress, reduceMotion: reduceMotion),
                       value: configuration.isPressed)
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
            // Reaches FULL canvas, and reaches it before the tab pill's top edge.
            //
            // Capping at 0.78 left the Liquid Glass rim with un-occluded body copy to refract, and
            // the bar duly mirrored it back as legible upside-down text (a second amber "Read more"
            // on Detail, a doubled show title on Search) — a frame that reads as GPU corruption.
            // Glass needs opaque canvas underneath it, not a 78 % veil.
            return LinearGradient(stops: [
                .init(color: ThemeColor.chromeVeil.opacity(0), location: 0),
                .init(color: ThemeColor.chromeVeil.opacity(0.42), location: 0.44),
                .init(color: ThemeColor.chromeVeil.opacity(0.72), location: 0.66),
                .init(color: ThemeColor.chromeVeil, location: 0.86),
                .init(color: ThemeColor.chromeVeil, location: 1),
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
                .init(color: .black.opacity(0.40), location: 0.44),
                .init(color: .black.opacity(0.70), location: 0.66),
                .init(color: .black, location: 0.86),
                .init(color: .black, location: 1),
            ], startPoint: .top, endPoint: .bottom)
        }
    }

    private var band: some View {
        ZStack {
            if !reduceTransparency {
                Rectangle().fill(.ultraThinMaterial).mask(blurMask)
            }
            veil
        }
    }

    var body: some View {
        Group {
            if side == .top {
                band.frame(height: height)
            } else {
                VStack(spacing: 0) {
                    band.frame(height: ThemeMetrics.bottomChromeHeight)
                    // See `ThemeMetrics.bottomUnderfill`: solid canvas continuing past the layout's
                    // bottom edge, under the bar and across the home-indicator strip.
                    ThemeColor.chromeVeil.frame(height: ThemeMetrics.bottomUnderfill)
                }
                .offset(y: ThemeMetrics.bottomUnderfill)
            }
        }
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
        /// Our edge chrome replaces the system scroll-edge effect; both together dim the last ~190 pt
    /// of every scroll view (a primary CTA at the bottom read as disabled).
    func scrollEdgeChrome(top: Bool = true, bottom: Bool = true,
                          topHeight: CGFloat = ThemeMetrics.topChromeHeight) -> some View {
        scrollEdgeChromeBody(top: top, bottom: bottom, topHeight: topHeight).scrollEdgeEffectHidden(true, for: .all)
    }

    func scrollEdgeChromeBody(top: Bool = true, bottom: Bool = true,
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            .pressFeedback(configuration.isPressed, reduceMotion: reduceMotion)
    }
}

// MARK: - Account

/// The account disc, drawn once for every surface that shows one.
///
/// The shipped build had two: Today derived a letter from `auth.displayName` (the raw Clerk id
/// `user_…` → "U") and Profile derived one from its own fallback label "Your account" (→ "Y") —
/// one user, two meaningless letters, one tap apart, while `AuthManager` already carried a helper
/// neither called. Both now read `AuthManager.identity`, and when there is nothing nameable this
/// draws the `person.fill` symbol rather than inventing a letter: **a wrong initial is worse than
/// none.**
///
/// `accentSoft` with the monogram in `accent`, not a filled accent disc — at 72 pt and full accent
/// the avatar was the loudest object in the app, on a screen whose subject is a library of shows.
struct AccountDisc: View {
    let identity: AuthManager.AccountIdentity
    var diameter: CGFloat = 56

    var body: some View {
        ZStack {
            Circle().fill(ThemeColor.accentSoft)
            Circle().strokeBorder(ThemeColor.accent.opacity(0.28), lineWidth: 1)
            if let initial = identity.initial {
                Text(initial)
                    .font(.system(size: diameter * 0.42, weight: .semibold))
                    .foregroundStyle(ThemeColor.accent)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            } else {
                Image(systemName: AuthManager.AccountIdentity.fallbackSymbol)
                    .font(.system(size: diameter * 0.40, weight: .medium))
                    .foregroundStyle(ThemeColor.textSecondary)
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }
}

// MARK: - The mark
//
// One verb, one control grammar. The shipped build had FOUR dialects — a labelled amber capsule on
// Today, the same capsule with the batch hidden behind a long-press-only `Menu(primaryAction:)` on
// Detail, a bare `textTertiary` checkmark pixel-identical to `PassiveTick` in the episode list, and
// an unlabelled 34-pt accent disc on Schedule — two of which used the same glyph to mean opposite
// things. The grammar from here, in a 44-pt target around a 22-pt ring:
//
//   hollow `strokeStrong` ring     unmarked, tappable
//   accent fill + `onAccent` check the commit frame
//   bare `textTertiary` check      settled, non-interactive (`PassiveTick`, Seasons only)

/// The check DRAWS. Nowhere in the shipped build did it: every tick was an opacity crossfade or a
/// scale pop, so the one moment the product exists to deliver had no signature motion. The mark is
/// masked left-to-right as it lands, which is what a hand-drawn tick does — and under Reduce Motion
/// it is simply there, at full width, with no animation to suppress.
struct DrawnCheck: View {
    /// `true` once the write has committed.
    var on: Bool
    var size: CGFloat = 14
    var tint: Color = ThemeColor.onAccent

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 0

    var body: some View {
        Image(systemName: "checkmark")
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(tint)
            .mask(alignment: .leading) {
                GeometryReader { geo in
                    Rectangle().frame(width: geo.size.width * progress)
                }
            }
            .onChange(of: on, initial: true) { _, on in
                guard on else { progress = 0; return }
                if reduceMotion {
                    progress = 1
                } else {
                    withAnimation(ThemeMotion.uiMicro) { progress = 1 }
                }
            }
            .accessibilityHidden(true)
    }
}

/// The round mark control: a 44-pt target holding a 22-pt ring. Used by Schedule's rows and the
/// episode list, so the same gesture has the same shape everywhere it is not a labelled capsule.
struct MarkRing: View {
    var marked: Bool
    /// Accessibility label for the unmarked state; the marked state speaks `episodeWatched`.
    var label: String = Copy.Action.markAsWatched
    var markedLabel: String? = nil
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(marked ? ThemeColor.accent : Color.clear)
                    .frame(width: 22, height: 22)
                Circle()
                    .strokeBorder(marked ? Color.clear : ThemeColor.strokeStrong, lineWidth: 1.5)
                    .frame(width: 22, height: 22)
                if marked { DrawnCheck(on: marked, size: 12) }
            }
            .frame(width: 44, height: 44)
            .contentShape(Circle())
            .animation(ThemeMotion.pick(ThemeMotion.uiMicro, reduceMotion: reduceMotion), value: marked)
        }
        .buttonStyle(MarkPressStyle())
        .accessibilityLabel(marked ? (markedLabel ?? Copy.Accessibility.complete) : label)
        .accessibilityAddTraits(marked ? [.isButton, .isSelected] : .isButton)
    }
}

/// "Mark as watched" with the batch options behind a real split.
///
/// One capsule containing two 44-pt targets separated by a hairline: tapping the label marks,
/// tapping the chevron opens the batch menu. Lifted out of `TodayView` because Detail — the surface
/// where a user actually catches up six episodes — had the batch behind a chevron-less
/// `Menu(primaryAction:)` that only a long press could reach.
struct MarkSplitButton: View {
    let episode: Int
    let committed: Bool
    let behind: Int
    let title: String
    let onMark: () -> Void
    let onMarkThrough: (Int) -> Void
    let onMarkAll: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var showsMenu: Bool { behind > 1 && !committed }

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onMark) {
                HStack(spacing: ThemeSpace.x2) {
                    if committed { DrawnCheck(on: committed) }
                    Text(committed ? Copy.Progress.episodeWatched(episode) : Copy.Action.markAsWatched)
                        .type(ThemeType.button)
                        // `.interpolate` tried to morph two unrelated strings and printed
                        // "Mark as watched" and "Episode 19 watched" superimposed as an unreadable
                        // smear, twice per mark. Two different sentences crossfade; they do not
                        // interpolate.
                        .contentTransition(.opacity)
                }
                .foregroundStyle(ThemeColor.onAccent)
                .padding(.horizontal, ThemeSpace.x5)
                .frame(maxWidth: .infinity, minHeight: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(SplitHalfStyle())
            .allowsHitTesting(!committed)
            .accessibilityLabel(committed
                                ? Copy.Progress.episodeWatched(episode)
                                : "\(Copy.Action.markAsWatched), \(Copy.episode(episode)) of \(title)")

            if showsMenu {
                Rectangle()
                    .fill(ThemeColor.onAccent.opacity(0.18))
                    .frame(width: 1, height: 24)
                Menu {
                    let through = min(episode + 4, episode + behind - 1)
                    if through > episode {
                        Button(Copy.Action.markThrough(through)) { onMarkThrough(through) }
                    }
                    Button(Copy.Action.markAll(behind)) { onMarkAll() }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ThemeColor.onAccent)
                        .frame(width: 46, height: 48)
                        .contentShape(Rectangle())
                }
                .buttonStyle(SplitHalfStyle())
                .accessibilityLabel("More ways to mark")
            }
        }
        .background(ThemeColor.accent)
        .clipShape(Capsule())
        // The lit top edge every filled control in this app carries: a flat #F0A24E rectangle is
        // a swatch, the same rectangle with one lit edge is an object.
        .overlay(Capsule().strokeBorder(
            LinearGradient(colors: [ThemeColor.controlSheen, .clear],
                           startPoint: .top, endPoint: .center),
            lineWidth: 1))
        .animation(ThemeMotion.pick(ThemeMotion.uiMicro, reduceMotion: reduceMotion), value: committed)
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
