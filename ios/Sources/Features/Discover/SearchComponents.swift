import SwiftUI

// The three objects Search repeats everywhere, each of which the shipped build drew more than one
// way.
//
//  • `AddControl` — the primary action of the whole screen. It measured ~25 pt over artwork (below
//    the 44-pt minimum), 55×43 as a bordered `Add` in a row (1 pt under it), and **vanished
//    entirely** in the added state, replaced by a bare grey checkmark with no chrome, no target
//    and no way to undo — so the trailing column's edge was ragged down the list and the most
//    important control on the screen was its quietest object. One component, two states, one
//    44-pt frame, one visual width, in both states, on every surface.
//  • `FactLine` — "2018 · 11 parts", "2023 · 6 parts / Airing", "2004 · 12 parts · Airing": the
//    same data set rendered three ways in three places, truncating mid-word in the narrow ones
//    ("2026 ·" — an orphaned separator). Facts are supplied in priority order and the line prints
//    only as many as actually fit. A dropped fact beats a fragment.
//  • `RankNumeral` / `RankGutter` — a chart position, drawn over the artwork where the artwork is
//    big enough to carry it and in the row's own leading gutter where it is not.

// MARK: - Add / added

/// The one add control.
///
/// **The placement rule, written down, because "two shapes for one verb 12 pt apart" was a finding:**
/// a control that sits ON artwork is a 26-pt disc inset into the poster's corner (shelf cards, and
/// any future grid); a control that sits in a row or card's trailing column is a 44-pt rounded
/// square. Those are the only two, they are chosen by *what is underneath the control*, and neither
/// one ever appears in the other's context — including at accessibility sizes, where the shipped
/// build grew the card's square into a full-width capsule and so drew one verb three ways.
///
/// Both placements are 44 pt of target, both keep the same footprint whether the show is in the
/// library or not, and both are live in both states — added is not a dead end, it is "tap to take
/// it back out".
struct AddControl: View {
    enum Placement {
        /// Inset into the corner of a poster.
        case overArt
        /// The trailing column of a row or card, on a surface rather than on art.
        case row
    }

    let title: String
    let owned: Bool
    var placement: Placement = .row
    let add: () -> Void
    let remove: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            owned ? remove() : add()
        } label: {
            glyph
        }
        .buttonStyle(placement == .overArt
                     ? AnyButtonStyle(MarkPressStyle())
                     : AnyButtonStyle(CompactSquareStyle(owned: owned)))
        // Three icon-only controls on this screen had no spoken name at all, and the amber tick was
        // the worst of them: unlabelled, it reads as a selection state rather than as ownership.
        .accessibilityLabel(owned ? "\(title), in your library. Remove" : "\(Copy.Action.add) \(title)")
        .accessibilityAddTraits(owned ? .isSelected : [])
    }

    /// `plus` and `checkmark` at the same size, in the same shape, so the state change is a symbol
    /// replacement rather than a crossfade between two differently-shaped objects.
    ///
    /// Added is drawn in `accent`; unadded in `textPrimary`. The two states were previously
    /// separated by the glyph's *colour alone* inside identical grey chrome, so "in your library"
    /// and "not in your library" both read as live grey buttons.
    private var glyph: some View {
        Image(systemName: owned ? "checkmark" : "plus")
            .font(.system(size: placement == .overArt ? 12 : 15, weight: .bold))
            .foregroundStyle(owned ? ThemeColor.accent : ThemeColor.textPrimary)
            .contentTransition(.symbolEffect(.replace.downUp))
            .animation(ThemeMotion.pick(ThemeMotion.uiMicro, reduceMotion: reduceMotion), value: owned)
            .modifier(AddControlShape(placement: placement, owned: owned))
    }
}

/// The disc / square the glyph sits in. Split out so the two placements cannot drift apart.
private struct AddControlShape: ViewModifier {
    let placement: AddControl.Placement
    let owned: Bool

    func body(content: Content) -> some View {
        switch placement {
        case .overArt:
            // A 26-pt disc centred in a 44-pt target. Scrim-filled in BOTH states with a hairline
            // ring, so the reading never depends on what the poster happens to be doing behind it —
            // measured 7.0:1 / 16.6:1 / 14.8:1 against the brightest posters in the chart. The
            // added state warms the fill so the two states differ in more than the glyph's colour.
            content
                .frame(width: 26, height: 26)
                .background(ThemeColor.scrimStrong, in: Circle())
                .background(owned ? ThemeColor.accentSoft : .clear, in: Circle())
                .overlay(Circle().strokeBorder(owned ? ThemeColor.accent.opacity(0.45) : ThemeColor.posterEdge,
                                               lineWidth: 1))
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        case .row:
            // Square, not a text capsule: "Add" and "✓" are different widths, and a trailing
            // column that changes width between rows is why the list's right edge was ragged.
            content
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
    }
}

/// `CompactActionButtonStyle`'s chrome at a fixed 44×44. The style itself pads to a label's width,
/// which is exactly what the ragged column needed to stop doing.
///
/// **Unadded is a stroke, not a fill.** Four identical filled grey tiles running down the right
/// edge of the one screen whose job is showing artwork made the trailing column the heaviest thing
/// in every row. The fill is now what *ownership* looks like — `accentSoft`, which is also the only
/// state that is a settled fact rather than an offer.
private struct CompactSquareStyle: ButtonStyle {
    let owned: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: ThemeRadius.compactControl, style: .continuous)
    }

    private func fill(pressed: Bool) -> Color {
        if pressed { return ThemeColor.surfacePressed }
        return owned ? ThemeColor.accentSoft : .clear
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(fill(pressed: configuration.isPressed), in: shape)
            .overlay(shape.strokeBorder(owned ? ThemeColor.accent.opacity(0.35) : ThemeColor.stroke,
                                        lineWidth: 1))
            .opacity(reduceMotion && configuration.isPressed ? 0.72 : 1)
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.985 : 1))
            .animation(ThemeMotion.pick(ThemeMotion.uiPress, reduceMotion: reduceMotion),
                       value: configuration.isPressed)
    }
}

/// Type-erases a `ButtonStyle` so one control can carry two of them without duplicating its body.
private struct AnyButtonStyle: ButtonStyle {
    private let make: (Configuration) -> AnyView

    init<S: ButtonStyle>(_ style: S) {
        make = { AnyView(style.makeBody(configuration: $0)) }
    }

    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}

// MARK: - Metadata

/// One metadata line, built from facts in priority order, printing only what fits.
///
/// The rule the direction states and the shipped build broke on every card: **drop a fact rather
/// than print a fragment.** `.truncationMode(.tail)` on a joined metadata string is how "2026 ·"
/// and "2018 · 11 parts · Friday…" reached the screen.
///
/// `lead` is the one fact that is allowed to be amber: a real next step, always printed first and
/// never dropped. Everything else is `textSecondary`. The shipped line set "29 Aug 2:00 PM" in the
/// same grey as the year and the season count, so the only time-sensitive fact on the screen read
/// as trivia — the inverse of the rule Today, Library and Schedule follow.
struct FactLine: View {
    let facts: [String]
    /// The forward-looking fact, in `rowMetaLead` accent. Printed before the grey facts.
    var lead: String? = nil
    var token: TypeToken = ThemeType.rowMeta
    var tint: Color = ThemeColor.textSecondary

    @Environment(\.dynamicTypeSize) private var typeSize

    private static let separator = " \u{00B7} "

    private func greyText(_ n: Int) -> String {
        facts.prefix(n).joined(separator: FactLine.separator)
    }

    /// One line: the amber lead, then as many grey facts as fit after it.
    ///
    /// `fixed` is what makes the ladder work — a candidate that reports its IDEAL width is one
    /// `ViewThatFits` can reject. The floor candidate is the only flexible one.
    private func line(_ n: Int, fixed: Bool = true) -> some View {
        HStack(spacing: 0) {
            if let lead {
                Text(lead)
                    .type(ThemeType.rowMetaLead)
                    .foregroundStyle(ThemeColor.accent)
                if n > 0 { Text(FactLine.separator).type(token).foregroundStyle(tint) }
            }
            if n > 0 {
                Text(greyText(n))
                    .type(token)
                    .foregroundStyle(tint)
            }
        }
        .lineLimit(1)
        .fixedSize(horizontal: fixed, vertical: false)
    }

    var body: some View {
        // ONE joined line at every size, dropping facts to fit — including at accessibility sizes,
        // where the shipped build broke the same data into three stacked lines and so showed MORE
        // information at AX than at the default size.
        ViewThatFits(in: .horizontal) {
            line(facts.count)
            line(3)
            line(2)
            line(1)
            line(0)
            // The floor. `ViewThatFits` renders its LAST candidate whether or not it fits, so this
            // one must be able to give: without it a lead that outgrew a 124-pt shelf caption kept
            // its ideal width and ran clean across the card beside it. Shrunk, then truncated —
            // never spilled.
            line(0, fixed: false)
                .minimumScaleFactor(0.75)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - The rank numeral

/// A chart position, drawn INSIDE the artwork it belongs to, over the legibility ramp `ArtScrim`
/// supplies. In the shipped build ranks 01–04 were 28-pt white numerals over the posters and ranks
/// 05+ were 13-pt `textDisabled` numerals in a separate 50-pt gutter — one ranking rendered as two
/// species, changing position, size and contrast halfway down the screen.
///
/// Used only where the artwork is big enough to carry a numeral without competing with it: the
/// 124×186 shelf card. A 60×90 row thumbnail is not — see `RankGutter`.
struct RankNumeral: View {
    let rank: Int
    let slot: PosterSize

    var body: some View {
        Text(String(format: "%02d", rank))
            .type(ThemeType.displayL)
            .monospacedDigit()
            .foregroundStyle(ThemeColor.textPrimary)
            .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
            .frame(maxWidth: slot.size.width, alignment: .leading)
            .background(alignment: .bottom) {
                ArtScrim(top: 0, bottom: 0.72)
                    .frame(height: slot.size.height * 0.45)
                    .clipShape(UnevenRoundedRectangle(
                        bottomLeadingRadius: slot.radius, bottomTrailingRadius: slot.radius,
                        style: .continuous))
            }
            .accessibilityHidden(true)
    }
}

/// The same chart position at row altitude: in the row's own leading gutter, beside the poster
/// rather than burned into it.
///
/// At 60 pt wide a numeral covers roughly a quarter of the thumbnail, and "06" landed on a bright
/// character with nothing protecting it — the rank competing with the identity art it is supposed
/// to be labelling. A chart's numerals are chrome; chrome goes in a gutter and holds one x.
struct RankGutter: View {
    /// The lane the numerals hold at the default text size, so a row's separator and its art can be
    /// inset from one number.
    static let width: CGFloat = 24

    let rank: Int

    /// The lane grows with the type in it. Held at 24 pt, the numeral rendered as a bare "…" at
    /// AX1 — a chart with no numbers in its rank column.
    @ScaledMetric(relativeTo: .caption2) private var lane: CGFloat = RankGutter.width

    var body: some View {
        Text(String(format: "%02d", rank))
            .type(ThemeType.sectionLabel)
            .monospacedDigit()
            .foregroundStyle(ThemeColor.textDisabled)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .fixedSize(horizontal: true, vertical: false)
            .frame(width: lane, alignment: .leading)
            .accessibilityHidden(true)
    }
}
