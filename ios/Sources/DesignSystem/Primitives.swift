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

    /// The PERSISTENT ground behind a card that is being handed off to its successor.
    ///
    /// `AnyTransition.handoff` fades the outgoing card out and the incoming one in; if the ground
    /// belongs to the cards themselves, the canvas flashes through the gap between them. Put this
    /// on the container that survives the swap and the two cards trade places over one continuous
    /// surface — which is the difference between a handoff and two separate events.
    func handoffGround(tint: Color?, radius: CGFloat = ThemeRadius.focusCard) -> some View {
        background {
            ArtAdaptiveGround(tint: tint)
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
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
                // Strong enough that the letterbox band an aspect-fit leaves reads as the SHOW's
                // colour rather than as a grey mat. At 0.22 over `surfaceRaised` it was still grey.
                RoundedRectangle(cornerRadius: radius, style: .continuous).fill(tint.opacity(0.60))
            }
            if let url, !url.isEmpty {
                // `.fit`, over the show's own colour, and no blur backfill behind it. The blurred
                // second copy existed purely to disguise a grey mat — and it cost a second full
                // decode plus a blur pass on every slot ≥ 72 pt, i.e. 60 of each on a 30-title grid.
                //
                // `.fill` was the answer while the ground was grey; with the ground being the
                // artwork's own palette colour it is the wrong one. **Posters aspect-fit and stay
                // whole; backdrops fill and crop** — that is the direction's own rule, and `.fill`
                // here side-cropped every asset that is not 2:3: Wistoria's announcement lockup
                // rendered as "son 3 制作". A 0.708 cover loses 4 % of its height against the slot,
                // which lands as a 2-pt tinted band, not a grey bar.
                RemoteImageView(url: url, contentMode: .fit, maxPixel: max(width, height) * 3, placeholderHidden: true)
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
            // A footnote cap-height is ~13 pt, so 12 pt of vertical padding gives a ~37–40 pt
            // target, and leading-only padding ends the hit area at the last glyph — the user has
            // to hit the WORD. Symmetric padding plus a 44-pt floor, applied before `contentShape`
            // so the shape is the padded box and not the label. Affects `See all`, `Read more`,
            // `Clear`, `Sync now` and Detail's `Details`, at every type size.
            .padding(.vertical, 14)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
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
extension EnvironmentValues {
    /// Width a list reserves along its trailing edge for chrome that floats over it — today that is
    /// Library's A–Z index rail, which lives in the same 16-pt gutter every row ends in.
    ///
    /// Set it once on the list; every `MediaRow` inside stops short of the reserved strip. Without
    /// it a fixed trailing chevron and a rail letter can land on the same 4 pt of screen, which is
    /// what an indexed list looks like when nobody reserved the gutter (Contacts reserves it).
    @Entry var listTrailingInset: CGFloat = 0
}

struct MediaRow<Trailing: View>: View {
    let title: String
    var meta: String? = nil
    /// The forward-looking fact: "Returns Oct 2", "Episode 19 next". Amber, because a real next
    /// step is exactly what amber is for. Never use it for a status that has already happened.
    var lead: String? = nil
    var poster: String? = nil
    var slot: PosterSize = .row
    /// The disclosure indicator, in a FIXED trailing column.
    ///
    /// It was concatenated into the title so it would sit beside the words it belongs to. That
    /// traded one defect for a worse one: the glyph's x became a function of title length, and it
    /// was measured at 370 / 418 / 520 / 600 / 712 down a single list — five different right edges
    /// in one column of a list whose whole job is to be scanned. A disclosure indicator is chrome,
    /// and chrome holds still; the gutter between the text and it is what every iOS list has.
    var chevron: Bool = true
    var dimmed: Bool = false
    var separator: Bool = true
    /// What tapping this row does, for VoiceOver. Schedule's and Detail's rows carry one; Today's
    /// did not, so the same control was self-describing on two screens and mute on a third.
    var hint: String? = nil
    /// Registers the row's artwork as the zoom-transition source, so pushing Detail from it grows
    /// out of this poster instead of sliding in from the right.
    var zoomID: String? = nil
    @ViewBuilder var trailing: () -> Trailing
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.listTrailingInset) private var trailingInset
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
                if chevron {
                    Image(systemName: "chevron.forward")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ThemeColor.textDisabled)
                        // A fixed column, so every chevron in a list shares one x.
                        .frame(width: 11, alignment: .trailing)
                        .accessibilityHidden(true)
                }
            }
            .padding(.trailing, trailingInset)
            .padding(.vertical, ThemeSpace.x2)
            .frame(minHeight: slot == .row ? ThemeMetrics.rowStandard : ThemeMetrics.rowMedia,
                   alignment: .leading)
            .contentShape(Rectangle())
            // Past / already-handled rows recede as a GROUP rather than each element being given
            // its own grey — one opacity keeps the artwork's colour relationship intact.
            //
            // 0.45 was not "recessed", it was unreadable: `textSecondary` at 0.45 over the canvas
            // composites to ≈#515151, i.e. 2.64:1, and it was applied to exactly the rows being
            // scanned for a date (Schedule's past week, Detail's unaired episodes). 0.72 lands at
            // ≈5.4:1 and still reads as a group that has stepped back.
            .opacity(dimmed ? 0.72 : 1)
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
        // Spelled out rather than left to `.combine`, so the trailing chevron is never spoken.
        .accessibilityLabel([title, lead, meta].compactMap { $0 }.joined(separator: ", "))
        .accessibilityHint(hint ?? "")
    }

    private var titleText: Text {
        Text(title)
            .type(ThemeType.rowTitle)
            .foregroundStyle(ThemeColor.textPrimary)
    }
}

extension MediaRow where Trailing == EmptyView {
    init(title: String, meta: String? = nil, lead: String? = nil, poster: String? = nil,
         slot: PosterSize = .row, chevron: Bool = true, dimmed: Bool = false,
         separator: Bool = true, hint: String? = nil, zoomID: String? = nil,
         action: @escaping () -> Void) {
        self.init(title: title, meta: meta, lead: lead, poster: poster, slot: slot,
                  chevron: chevron, dimmed: dimmed, separator: separator, hint: hint,
                  zoomID: zoomID, trailing: { EmptyView() }, action: action)
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
    /// `trailingMargin` 40, not 28: at 28 the peeking card's caption still reached the bezel and
    /// sheared mid-word ("Avatar:", "Caught u", "So", "Re") because the fade only covered the last
    /// 7 % (~30 pt) of the viewport. 40 pt of margin plus a 14 % fade means a partial card always
    /// shows artwork and its type has dissolved before the edge — verified against the longest
    /// caption in the app, "No date announced".
    func shelfScroller(trailingMargin: CGFloat = 40, masked: Bool = true) -> some View {
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
                            .init(color: .black, location: 0.86),
                            .init(color: .black.opacity(0.45), location: 0.95),
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: 420)
        .chromeGlass(in: Capsule())
        .shadow(.floating)
        // The toast owns its own timing. Its host used to declare three `uiSnappy` animations and
        // the toast a bare `.opacity`, so it arrived and LEFT on the same spring — a bounce out,
        // not a dismissal.
        .transition(.toast(reduceMotion: reduceMotion))
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
            // Reaches FULL canvas, and reaches it before the tab pill's top edge — but only in the
            // last ~10 pt of a 64-pt band, not across 140 pt of readable screen.
            //
            // Capping at 0.78 left the Liquid Glass rim with un-occluded body copy to refract, and
            // the bar duly mirrored it back as legible upside-down text (a second amber "Read more"
            // on Detail, a doubled show title on Search) — a frame that reads as GPU corruption.
            // Glass needs opaque canvas underneath it, not a 78 % veil. Going the other way and
            // reaching full canvas at 0.86 of *140 pt* solved the refraction by erasing the content:
            // a `See all` link at 1.42:1 and a live `+` button at 131/241, at rest, with nothing
            // scrolled. Both failures are the same mistake — the band's HEIGHT — so the stops stay
            // hard and the band is now the pill's own height.
            //
            // Held flat to 0.44 (≈28 pt above the pill) so nothing in the last readable line is
            // touched at all, then a fast run to opaque.
            return LinearGradient(stops: [
                .init(color: ThemeColor.chromeVeil.opacity(0), location: 0),
                .init(color: ThemeColor.chromeVeil.opacity(0.25), location: 0.55),
                .init(color: ThemeColor.chromeVeil.opacity(0.75), location: 0.85),
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
            // Re-stopped WITH the veil, not independently: a blur that keeps lifting where the veil
            // has already stopped is a second, invisible ramp — and it was the half that was
            // actually measured softening live body copy 137 pt above the bar.
            return LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .black.opacity(0.30), location: 0.55),
                .init(color: .black.opacity(0.75), location: 0.85),
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

    /// Bottom clearance for a tab root's scroll view, as a scroll-content MARGIN.
    ///
    /// `.padding(.bottom, tabBarClearance)` inside the scroll content does nothing at all when the
    /// stack is shorter than the viewport — the content is already above the fold, so padding under
    /// it changes no layout — which is exactly the case a short list is in when it comes to rest
    /// inside the ramp. A content margin is honoured either way, and it is also what makes the
    /// scroll indicator stop at the right place.
    ///
    /// Applied to the *scroll view* (or any ancestor of it), never inside the stack.
    func tabBarContentMargin(extra: CGFloat = 0) -> some View {
        contentMargins(.bottom, ThemeMetrics.tabBarClearance + extra, for: .scrollContent)
    }

    /// The bottom half of the chrome, for a screen that was PUSHED rather than selected.
    ///
    /// `scrollEdgeChrome` was applied on tab roots only, so a pushed screen — Detail, its episode
    /// list, Watch history — rendered whole rows at full opacity under and beside the floating pill,
    /// with no `bottomUnderfill` for the glass to refract. That is not a per-screen oversight to
    /// fix six times; it is the pushed-screen scaffold, so it lives on the navigation destination
    /// (`RootView.detailDestinations`) and every future push inherits it.
    ///
    /// The top edge is deliberately untouched: a pushed screen has a real navigation bar and the
    /// system owns that edge. Only the bottom system effect is suppressed, because ours replaces it.
    func pushedScreenChrome() -> some View {
        scrollEdgeChromeBody(top: false, bottom: true)
            .scrollEdgeEffectHidden(true, for: .bottom)
            .contentMargins(.bottom, ThemeMetrics.tabBarClearance, for: .scrollContent)
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
    /// Where the crop anchors. `.top` keeps faces in a tall band; a key-art lockup that lives in
    /// the lower third needs `.bottom`, and a centred composition needs `.center`. Hard-coding
    /// `.top` is why one hero was a forehead and another was a logo.
    ///
    /// (`Alignment`, not `UnitPoint`: it is handed straight to `RemoteImageView(alignment:)`, the
    /// one place in this app where a crop anchor is applied.)
    var focus: Alignment = .top
    /// The source is a PORTRAIT cover, not a landscape banner.
    ///
    /// A 2:3 cover `.fill`ed into a 0.46-screen band is upscaled ~2.5× and cropped to a horizontal
    /// slice of itself — the app's largest piece of artwork rendered as its worst. When there is no
    /// banner the cover is composited instead: a blurred, opaque copy of itself as the ground, the
    /// whole cover fitted over it. Nothing is upscaled and nothing is lost.
    var portraitSource: Bool = false
    @ViewBuilder var overlay: () -> Overlay

    var body: some View {
        ZStack(alignment: .bottom) {
            (tint ?? PaletteCache.fallback)
            if let url, !url.isEmpty {
                if portraitSource {
                    RemoteImageView(url: url, contentMode: .fill, maxPixel: 1024,
                                    alignment: .center, placeholderHidden: true)
                        .blur(radius: 48, opaque: true)
                        .overlay(Color.black.opacity(0.28))
                    RemoteImageView(url: url, contentMode: .fit, maxPixel: 1024,
                                    alignment: focus, placeholderHidden: true)
                        .transition(.opacity)
                } else {
                    RemoteImageView(url: url, contentMode: .fill, maxPixel: 1536,
                                    alignment: focus, placeholderHidden: true)
                        .transition(.opacity)
                }
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
/// neither called. Both now read `AuthManager.identity`.
///
/// **It never draws `person.fill`.** Both call sites were rendering the system's generic account
/// glyph inside a brand-coloured ring — the app spending its one accent on a placeholder, on the
/// element whose entire job is to be *this person*. On Profile the disc also cut a hole straight
/// through the poster fan behind it. The chain is: the real initial → the first letter of the label
/// the account is shown under → the Previously. mark. Only the first two are letters, so a wrong
/// initial is still never invented; the third is the app's own identity, which is never wrong.
///
/// `accentSoft` ground with the monogram in `accent`, and the ring at `posterEdge` — the same 9 %
/// white every piece of artwork in the app is bounded with, so the disc sits in the same material
/// world as the posters beside it instead of glowing.
struct AccountDisc: View {
    let identity: AuthManager.AccountIdentity
    var diameter: CGFloat = 56

    var body: some View {
        ZStack {
            Circle().fill(ThemeColor.accentSoft)
            Circle().strokeBorder(ThemeColor.posterEdge, lineWidth: 1)
            if let monogram = identity.monogram {
                Text(monogram)
                    .font(.system(size: diameter * 0.42, weight: .semibold))
                    .foregroundStyle(ThemeColor.accent)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            } else {
                PreviouslyMark(width: diameter * 0.34, detail: .none)
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
    /// How loudly the marked state is drawn. The geometry, the target and the motion are identical
    /// in both — only the ink changes, so there is still exactly ONE mark control in the app.
    enum Style {
        /// Accent fill, `onAccent` check. The row's own primary action: Schedule's rows, a season.
        case filled
        /// Accent ring, accent check, no fill. For a dense repeating list — an episode list where
        /// twenty filled amber discs down one column would turn a rhythm into a scoreboard. This is
        /// the shape `FranchiseDetailView` hand-rolled at :1271-1287 rather than reach for a token.
        case quiet
    }

    var marked: Bool
    var style: Style = .filled
    /// Accessibility label for the unmarked state; the marked state speaks `episodeWatched`.
    var label: String = Copy.Action.markAsWatched
    var markedLabel: String? = nil
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var fill: Color {
        guard marked, style == .filled else { return .clear }
        return ThemeColor.accent
    }

    private var ring: Color {
        switch (marked, style) {
        case (false, _):      return ThemeColor.strokeStrong
        case (true, .filled): return .clear
        case (true, .quiet):  return ThemeColor.accent
        }
    }

    private var ink: Color { style == .filled ? ThemeColor.onAccent : ThemeColor.accent }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(fill).frame(width: 22, height: 22)
                Circle().strokeBorder(ring, lineWidth: 1.5).frame(width: 22, height: 22)
                // Mounted unconditionally: a conditional insert re-creates `DrawnCheck` and hands
                // SwiftUI an implicit opacity transition ON TOP of the mask, so the app's signature
                // motion rendered as a smear instead of a stroke. The mask IS the animation.
                DrawnCheck(on: marked, size: 12, tint: ink)
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

    private var showsMenu: Bool { behind > 1 }

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onMark) {
                HStack(spacing: 0) {
                    // Mounted unconditionally and collapsed to zero width when there is nothing to
                    // draw. A conditional insert inside an `.animation` container gave the check an
                    // implicit opacity transition on top of its own left-to-right mask, so the one
                    // moment the product exists to deliver rendered as a smear. The mask IS the
                    // animation; nothing else may touch this glyph's opacity.
                    DrawnCheck(on: committed, tint: ThemeColor.accent)
                        .padding(.trailing, ThemeSpace.x2)
                        .frame(width: committed ? nil : 0, alignment: .leading)
                        .clipped()
                    Text(committed ? Copy.Progress.episodeWatched(episode) : Copy.Action.markAsWatched)
                        .type(ThemeType.button)
                        // `.interpolate` tried to morph two unrelated strings and printed
                        // "Mark as watched" and "Episode 19 watched" superimposed as an unreadable
                        // smear, twice per mark. Two different sentences crossfade; they do not
                        // interpolate.
                        .contentTransition(.opacity)
                }
                .foregroundStyle(committed ? ThemeColor.accent : ThemeColor.onAccent)
                .padding(.horizontal, ThemeSpace.x5)
                .frame(maxWidth: .infinity, minHeight: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(SplitHalfStyle())
            .allowsHitTesting(!committed)
            .accessibilityRemoveTraits(committed ? .isButton : [])
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
                .allowsHitTesting(!committed)
                .opacity(committed ? 0.45 : 1)
                .accessibilityLabel("More ways to mark")
                .accessibilityHidden(committed)
            }
        }
        // A past-tense fact does not get the app's one primary colour: the committed capsule
        // keeps its shape and drops to a soft tint with accent ink.
        .background(committed ? ThemeColor.accent.opacity(0.18) : ThemeColor.accent)
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

// MARK: - Colour is never the only carrier

/// The shape carrier for a state that is otherwise encoded in colour alone.
///
/// `accessibilityDifferentiateWithoutColor` had **zero** references in the whole of `Sources/`, so
/// every colour-only encoding in the app — Schedule's "today", an accent caption that means "this
/// is your next step" — was invisible to a user who has asked the system for shapes instead of
/// hues. This draws nothing at all until that setting is on, at which point the state also carries
/// a glyph. It is not an accessibility fallback bolted beside the design; it is the second carrier
/// the design should have had.
struct DifferentiateMark: View {
    var symbol: String = "circle.fill"
    var size: CGFloat = 6
    var tint: Color = ThemeColor.textPrimary

    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiate

    var body: some View {
        if differentiate {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
        }
    }
}

extension View {
    /// A 2-pt rule under an element whose selected/current state is otherwise only a colour.
    /// Unconditional when Differentiate Without Color is on, absent otherwise.
    func differentiatingUnderline(_ active: Bool, tint: Color = ThemeColor.textPrimary) -> some View {
        modifier(DifferentiatingUnderline(active: active, tint: tint))
    }
}

private struct DifferentiatingUnderline: ViewModifier {
    let active: Bool
    let tint: Color

    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiate

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if active && differentiate {
                Capsule().fill(tint).frame(height: 2).padding(.horizontal, 4).offset(y: 3)
                    .accessibilityHidden(true)
            }
        }
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
