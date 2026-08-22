import SwiftUI

// The two objects Search repeats everywhere, each of which the shipped build drew three ways.
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

// MARK: - Add / added

/// The one add control.
///
/// Two placements, identical anatomy: a disc over artwork, a bordered square in a row. Both are
/// 44 pt of target, both keep the same footprint whether the show is in the library or not, and
/// both are live in both states — added is not a dead end, it is "tap to take it back out".
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
        .buttonStyle(placement == .overArt ? AnyButtonStyle(MarkPressStyle()) : AnyButtonStyle(CompactSquareStyle()))
        .accessibilityLabel(owned ? "Remove \(title) from your library" : "\(Copy.Action.add) \(title)")
        .accessibilityAddTraits(owned ? .isSelected : [])
    }

    /// `plus` and `checkmark` at the same size, in the same disc, so the state change is a symbol
    /// replacement rather than a crossfade between two differently-shaped objects. Accent belongs
    /// to the settled fact; an add is a verb, not a highlight.
    private var glyph: some View {
        Image(systemName: owned ? "checkmark" : "plus")
            .font(.system(size: placement == .overArt ? 12 : 15, weight: .bold))
            .foregroundStyle(owned ? ThemeColor.accent : ThemeColor.textPrimary)
            .contentTransition(.symbolEffect(.replace.downUp))
            .animation(ThemeMotion.pick(ThemeMotion.uiMicro, reduceMotion: reduceMotion), value: owned)
            .modifier(AddControlShape(placement: placement))
    }
}

/// The disc / square the glyph sits in. Split out so the two placements cannot drift apart.
private struct AddControlShape: ViewModifier {
    let placement: AddControl.Placement

    func body(content: Content) -> some View {
        switch placement {
        case .overArt:
            // A 26-pt disc centred in a 44-pt target, scrim-filled in BOTH states with a hairline
            // ring so it separates from bright sky as well as from a dark frame.
            content
                .frame(width: 26, height: 26)
                .background(ThemeColor.scrimStrong, in: Circle())
                .overlay(Circle().strokeBorder(ThemeColor.posterEdge, lineWidth: 1))
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
private struct CompactSquareStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? ThemeColor.surfacePressed : ThemeColor.surfaceFloating,
                        in: RoundedRectangle(cornerRadius: ThemeRadius.compactControl, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: ThemeRadius.compactControl, style: .continuous)
                .strokeBorder(ThemeColor.stroke, lineWidth: 1))
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
/// and "2018 · 11 parts · Friday…" reached the screen. At accessibility sizes the line wraps
/// instead — a wrapped fact is still a whole fact.
struct FactLine: View {
    let facts: [String]
    var token: TypeToken = ThemeType.rowMeta
    var tint: Color = ThemeColor.textSecondary

    @Environment(\.dynamicTypeSize) private var typeSize

    private static let separator = " \u{00B7} "
    /// Kind and year, bound so the pair cannot break: two short tokens that fit on one line at
    /// every accessibility size, joined by a dot that can never end up alone at the edge of one.
    private static let boundSeparator = "\u{00A0}\u{00B7}\u{00A0}"

    /// The accessibility layout: "Anime · 1999", then "45 seasons", then "Tomorrow 7:46 PM".
    private var axLines: [String] {
        guard !facts.isEmpty else { return [] }
        var lines = [facts.prefix(2).joined(separator: FactLine.boundSeparator)]
        lines.append(contentsOf: facts.dropFirst(2))
        return lines
    }

    private func line(_ n: Int) -> some View {
        Text(facts.prefix(n).joined(separator: FactLine.separator))
            .type(token)
            .foregroundStyle(tint)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    var body: some View {
        if typeSize.isAccessibilitySize {
            // At accessibility sizes every metadata line wraps, and a wrap through a separator
            // puts "· Fri 7:30 PM" at the head of a line or "Anime · 1999 ·" at the foot of one —
            // the orphaned separator, arriving by a different route. So the line is broken by US:
            // the short identity pair, then each remaining fact on its own line. No separator can
            // reach a line edge, and no fact is ever split.
            VStack(alignment: .leading, spacing: 1) {
                ForEach(Array(axLines.enumerated()), id: \.offset) { _, text in
                    Text(text)
                        .type(token)
                        .foregroundStyle(tint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else {
            ViewThatFits(in: .horizontal) {
                line(facts.count)
                line(3)
                line(2)
                line(1)
            }
            // The last candidate is one fact wide; below that the frame wins and truncates the
            // single word, which is the only place an ellipsis is honest.
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - The rank numeral

/// A chart position, drawn INSIDE the artwork it belongs to, over the legibility ramp `ArtScrim`
/// supplies. In the shipped build ranks 01–04 were 28-pt white numerals over the posters and ranks
/// 05+ were 13-pt `textDisabled` numerals in a separate 50-pt gutter — one ranking rendered as two
/// species, changing position, size and contrast halfway down the screen.
struct RankNumeral: View {
    let rank: Int
    let slot: PosterSize
    /// The shelf's numeral is display-sized; a 60×90 row's is footnote-sized. Same treatment.
    var large: Bool = false

    var body: some View {
        Text(String(format: "%02d", rank))
            .type(large ? ThemeType.displayL : ThemeType.metadataEmphasis)
            .monospacedDigit()
            .foregroundStyle(ThemeColor.textPrimary)
            .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, large ? 10 : 6)
            .padding(.bottom, large ? 6 : 4)
            .frame(maxWidth: slot.size.width, alignment: .leading)
            .background(alignment: .bottom) {
                ArtScrim(top: 0, bottom: 0.72)
                    .frame(height: slot.size.height * (large ? 0.45 : 0.55))
                    .clipShape(UnevenRoundedRectangle(
                        bottomLeadingRadius: slot.radius, bottomTrailingRadius: slot.radius,
                        style: .continuous))
            }
            .accessibilityHidden(true)
    }
}
