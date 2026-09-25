import SwiftUI

// Schedule in the new language (25 Sep: "We need to Overhaul the Schedule Screen completely for this
// new awesome UX", owner). Three directions were photographed on the owner's own calendar — every
// airing an X post; X's compact agenda under day headings; the next thing to watch as one big card
// over the agenda — and the owner chose TONIGHT, then: "tonight still feels cluttered". Its day
// headings were 20-pt banners over one or two rows each (the 7 Sep finding again: ~40 % of the feed
// was banners), every upcoming line was amber, and an empty "Today" heading sat under a card that
// already said tonight. What it is now:
//   · the next thing to watch as ONE card (`ScheduleTonightCard`): the show's poster, one amber line
//     ("OUT NOW", "TONIGHT AT 7:30 PM", "SUNDAY AT 4:30 PM"), the show's logo else its name, the
//     episode, and the mark once it is out;
//   · then the agenda with THE DATE RIDING THE ROW (`ScheduleAgendaRow`, the 7 Sep anatomy): the
//     day once, in the date column, amber only on today; the show's face; its name; "Episode 14 ·
//     4:30 PM" in grey; the state ladder's slot (`AiringStateControl`). No day banners, no rules —
//     a day's break is the only space.

/// The agenda's columns, shared by the airing row and the empty day's row so the two line up. (Not
/// on the row: it is generic over its trailing view, and a generic type may not carry statics.)
enum AgendaMetrics {
    static var avatar: CGFloat { 40 }
    static var leading: CGFloat { ThemeMetrics.gutter - ThemeSpace.x1 }
    static var trailing: CGFloat { ThemeSpace.x3 }
    static var vertical: CGFloat { ThemeSpace.x1 + 2 }
}

/// One airing in the agenda: the date (on a day's first row only), the show's face, its name, what
/// airs and when, and the state ladder's slot.
struct ScheduleAgendaRow<Trailing: View>: View {
    let franchise: Franchise
    /// "SUN" over "27" — a day's first row only (Later: "OCT" over "19").
    let date: (top: String, numeral: String)?
    let isToday: Bool
    let line: String
    let state: AiringState
    /// What VoiceOver says for the row (the date column is hidden from it).
    let spoken: String
    let onOpen: () -> Void
    @ViewBuilder var trailing: () -> Trailing
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize { stacked } else { inline }
        }
        .padding(.leading, AgendaMetrics.leading)
        .padding(.trailing, AgendaMetrics.trailing)
        .padding(.vertical, AgendaMetrics.vertical)
    }

    /// Date, face, words, ladder — four columns at four fixed x's.
    private var inline: some View {
        HStack(spacing: ThemeSpace.x3) {
            dateColumn
            Button(action: onOpen) {
                HStack(spacing: ThemeSpace.x3) {
                    face
                    words
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPressStyle())
            .accessibilityLabel(spoken)
            .accessibilityHint(Copy.Accessibility.opensTheShowHint)
            trailing()
        }
    }

    /// At the ACCESSIBILITY sizes the row unfolds, as the 7 Sep row did: the date, the face and the
    /// ladder keep one line and the words take the full width beneath them — four columns at that
    /// type left the name a lane narrower than one word.
    private var stacked: some View {
        VStack(alignment: .leading, spacing: ThemeSpace.x2) {
            HStack(spacing: ThemeSpace.x3) {
                dateColumn
                face.accessibilityHidden(true)
                Spacer(minLength: 0)
                trailing()
            }
            Button(action: onOpen) {
                words
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(RowPressStyle())
            .accessibilityLabel(spoken)
            .accessibilityHint(Copy.Accessibility.opensTheShowHint)
        }
    }

    private var dateColumn: some View {
        ScheduleDateColumn(weekday: date?.top, numeral: date?.numeral, isToday: isToday)
    }

    /// The show as an ACCOUNT — the feed's rounded square (`ShowAvatar`; circles are people and
    /// the story tray), so a show wears one face on every screen. A watched airing gives it up a
    /// step, as the ladder's disc says it is spent.
    private var face: some View {
        ShowAvatar(franchise: franchise, size: AgendaMetrics.avatar)
            .opacity(state.isWatched ? 0.55 : 1)
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(franchise.displayTitle)
                .type(ThemeType.feedName)
                .foregroundStyle(state.isWatched ? ThemeColor.feedSecondary : ThemeColor.feedText)
                .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
            Text(line)
                .type(ThemeType.feedMeta)
                .foregroundStyle(ThemeColor.feedSecondary)
                .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
        }
        .multilineTextAlignment(.leading)
    }
}

/// A day with nothing on it — today, or a day picked on the grid: its date in the column, and one
/// grey line where the names are.
struct ScheduleEmptyDayRow: View {
    let weekday: String
    let numeral: String
    let isToday: Bool
    let text: String
    let spoken: String

    var body: some View {
        HStack(spacing: ThemeSpace.x3) {
            ScheduleDateColumn(weekday: weekday, numeral: numeral, isToday: isToday)
            Color.clear.frame(width: AgendaMetrics.avatar, height: 1)
            Text(text)
                .type(ThemeType.feedMeta)
                .foregroundStyle(ThemeColor.feedSecondary)
            Spacer(minLength: 0)
        }
        .frame(minHeight: AgendaMetrics.avatar)
        .padding(.leading, AgendaMetrics.leading)
        .padding(.trailing, AgendaMetrics.trailing)
        .padding(.vertical, AgendaMetrics.vertical)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }
}

/// The next thing to watch, as one card: the show's poster to the card's edges, and at its foot one
/// amber line (the moment), the show's logo else its name, the episode, and the mark once it is out.
struct ScheduleTonightCard: View {
    let franchise: Franchise
    let eyebrow: String
    let line: String
    let state: AiringState
    let canToggle: Bool
    let markLabel: String
    let onToggle: () -> Void
    let onOpen: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    private static let aspect: CGFloat = 1.0
    private static let scrimLead: CGFloat = 96

    var body: some View {
        let width = ThemeMetrics.windowWidth - 2 * ThemeMetrics.gutter
        let height = (width * Self.aspect).rounded()
        let shape = RoundedRectangle(cornerRadius: ThemeRadius.card, style: .continuous)
        let name = franchise.billboardName
        ZStack(alignment: .bottom) {
            Button(action: onOpen) {
                RemoteImageView(url: franchise.billboardArt.url ?? franchise.portraitArt, contentMode: .fill,
                                maxPixel: 1400, alignment: .top, placeholderHidden: true)
                    .frame(width: width, height: height)
                    .clipped()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(eyebrow), \(franchise.displayTitle), \(line)")
            .accessibilityHint(Copy.Accessibility.opensTheShowHint)
            VStack(spacing: ThemeSpace.x2) {
                Text(eyebrow)
                    .type(ThemeType.feedEyebrow)
                    .textCase(.uppercase)
                    .foregroundStyle(ThemeColor.accent)
                    .lineLimit(1)
                    .shadow(.art)
                if case .logo = name, name.hasGraphicLogo {
                    ArtworkLogo(name: name, title: franchise.displayTitle, height: 64)
                        .padding(.horizontal, ThemeSpace.x10)
                } else {
                    Text(franchise.displayTitle)
                        .type(ThemeType.displayL)
                        .foregroundStyle(ThemeColor.textPrimary)
                        .multilineTextAlignment(.center)
                        // A name may grow at the accessibility sizes; it may not lose the show.
                        .lineLimit(typeSize.isAccessibilitySize ? 3 : 2)
                        .minimumScaleFactor(0.75)
                        .shadow(.art)
                }
                Text(line)
                    .type(ThemeType.feedMeta)
                    .foregroundStyle(ThemeColor.textPrimary.opacity(0.85))
                    .lineLimit(1)
                    .shadow(.art)
                if canToggle {
                    ScheduleMarkPill(watched: state.isWatched, label: markLabel, action: onToggle)
                        .padding(.top, ThemeSpace.x1)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, ThemeSpace.x4)
            .padding(.bottom, ThemeSpace.x4)
            // The scrim is sized to the WORDS, not to the card: a ramp of `scrimLead` above them,
            // then a ground under them — so the amber moment reads at 0.6 whether the pill is
            // there or not, at every text size (a fixed ramp left "OUT NOW" on the bright middle
            // of the art once the pill pushed the words up).
            .background(alignment: .bottom) {
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                        .frame(height: Self.scrimLead)
                    LinearGradient(colors: [.black.opacity(0.6), .black.opacity(0.9)], startPoint: .top, endPoint: .bottom)
                }
                .padding(.top, -Self.scrimLead)
                .allowsHitTesting(false)
            }
            .accessibilityElement(children: .contain)
        }
        .frame(width: width, height: height)
        .clipShape(shape)
        .overlay(shape.strokeBorder(ThemeColor.posterEdge, lineWidth: 1))
        .padding(.horizontal, ThemeMetrics.gutter)
    }
}

/// The card's mark as X's pill: "Mark as watched" in ink on white until it is, then "Watched" in a
/// one-pixel outline with the check (a tap undoes).
struct ScheduleMarkPill: View {
    let watched: Bool
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            AppGlyphLabel(watched ? Copy.Action.watched : Copy.Action.markWatched, systemName: watched ? "checkmark" : "plus")
                .type(ThemeType.feedNoteTitle)
                .foregroundStyle(watched ? ThemeColor.feedText : ThemeColor.canvas)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, ThemeSpace.x4)
                .frame(minHeight: 36)
                .background(watched ? Color.clear : ThemeColor.feedText, in: Capsule())
                .overlay(Capsule().strokeBorder(watched ? ThemeColor.feedText.opacity(0.4) : .clear, lineWidth: FeedMetrics.hairline))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(FeedIconPressStyle())
        .accessibilityLabel(label)
    }
}

/// A label over the agenda — the month it crosses into, "LATER" — in Schedule's caps.
struct ScheduleEyebrow: View {
    let text: String

    var body: some View {
        Text(text)
            .type(ThemeType.feedEyebrow)
            .textCase(.uppercase)
            .foregroundStyle(ThemeColor.textSecondary)
            .lineLimit(1)
            .padding(.horizontal, ThemeMetrics.gutter)
            .accessibilityAddTraits(.isHeader)
    }
}
