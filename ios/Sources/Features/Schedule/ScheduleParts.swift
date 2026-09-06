import SwiftUI

// Schedule's row and its calendar (6 Sep, evening — the second rebuild of this screen in a day).
//
// Two complaints settled it ("Lots of problem in the Schedule page", user):
//   1. "The calendar part is utterly confusing and poorly executed."
//   2. "There is no instant visual distinction between an episode that has been marked as
//      completed, not seen, and upcoming. Everything feels of the same weight."
//
// Four headers and three densities were built behind launch arguments and photographed side by
// side on the real account; the user picked the MONTH GRID behind a bar button, on COMPACT rows.
// What the photographs showed, in order of how much they mattered:
//
//   · The rail that shipped that morning was pointing at days the reader was not looking at. In
//     the capture the feed sat on Wednesday 2 Sep and Friday 4 Sep and NEITHER day was on the
//     rail — both had scrolled off its left edge while the selected capsule said "TODAY". NN/g's
//     eye-tracking puts ~1 % of attention past the edge of a horizontal strip, and a jump list
//     whose targets are off-screen is not a jump list. It also named every day twice: "WED 9" in
//     the rail, "WEDNESDAY · 9 SEP" in the feed a hundred points below.
//   · A list of only the non-empty days cannot show a month's SHAPE — which weeks are busy, which
//     are spent, which are empty — by construction. The grid can, and at rest it costs nothing.
//   · At a gutter-to-gutter 16:9 card an airing plus its day header is ~305 pt, so exactly two fit
//     between the chrome and the tab bar. A state ladder you can only see two rungs of is not a
//     ladder. The same feed at 104×59 runs six deep and ends on "That's everything through 18 Sep".
//
// The reference apps: animeschedule.net prints day headers and pages by WEEK, with no day picker;
// Fantastical's DayTicker pulls down into a month; Google Calendar's Schedule view puts the jump
// behind a month dropdown that OVERLAYS the agenda. Trakt v3 dropped its date picker entirely.

// MARK: - Debug

/// The two launch arguments this screen keeps, in the family `-scheduleFilter` already uses.
enum ScheduleDebug {
    /// `-scheduleDemoStates 1` — the test account has no AIRED-AND-UNWATCHED airing (both past
    /// slots are watched, and Mushoku is `planned`, so its four are correctly off the calendar),
    /// so the ladder cannot be photographed with all three rungs on real data. This draws the most
    /// recent aired airing as though it were still waiting. It changes what is DRAWN, never what
    /// is stored.
    static var demoStates: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "scheduleDemoStates")
        #else
        return false
        #endif
    }

    /// `-scheduleMonthOpen 1` — open with the calendar already down, for a capture.
    static var monthOpen: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "scheduleMonthOpen")
        #else
        return false
        #endif
    }
}

// MARK: - The state ladder

/// The three states an airing can be in, and the ONE place they are told apart.
///
/// What shipped put the three signals in three corners of a 249-pt card: the clock's colour at the
/// leading edge, the ring's presence at the trailing edge, a 26-pt check on the art's top-right —
/// and "watched" was `opacity(0.72)` over a photograph on black, which is not a state, it is a
/// haze. Jellyfin's #706 is the same bug with better contrast: readers cannot parse states that
/// differ only in glyph at the same weight ("I keep getting that small moment of excitement
/// thinking there is a new episode, and upon closer inspection it's just the same blue circle with
/// a check mark").
///
/// The fix is a LADDER at one x-position — the trailing slot, which every airing reserves whether
/// or not it has a control, so the eye runs down one column and reads:
///
///   · `upcoming` — an empty slot, and the time in accent. Nothing to do; the fact is the clock.
///   · `toWatch`  — the accent RING with its episode numeral. The only lit thing in the column.
///   · `watched`  — a settled DISC with a check, and the art dimmed a step below the ink.
///
/// The urgency also stops being inverted: the ring, not the clock, is what the accent buys on an
/// aired row, and a watched row gives up its picture's brightness rather than a tenth of its alpha.
enum AiringState {
    case upcoming
    case toWatch
    case watched

    var isWatched: Bool { self == .watched }
}

/// The trailing column, at one width for all three states so the column exists even where it is
/// empty. 44 pt is the ring's own target; an upcoming row reserves it rather than closing the gap,
/// which is what let "watched" and "upcoming" look identical here before.
struct AiringStateControl: View {
    let state: AiringState
    let episode: Int
    /// The mark is mid-flight: the ring fills and the check draws in place (`MarkRing` owns it).
    let committing: Bool
    let title: String
    /// Marking this row would cover more than one episode.
    let batch: Bool
    let count: Int
    /// The show is in the library, so there is progress to write. A catalogue row that merely airs
    /// keeps the column's width and draws nothing in it.
    let canMark: Bool
    let action: () -> Void

    var body: some View {
        Group {
            switch state {
            case .toWatch where !canMark:
                Color.clear.frame(width: 44, height: 44)
            case .toWatch:
                // `lead: true` is what makes the ring ACCENT rather than `markRingIdle`. On a
                // schedule every unwatched aired row is a next step, so every one of them leads;
                // the episode list's "one accent ring in the column" rule is about a column of
                // episodes of ONE show, which this is not.
                MarkRing(marked: committing,
                         style: .quiet,
                         lead: true,
                         episode: episode,
                         committing: committing,
                         label: batch ? "Mark \(Copy.episodes(count)) of \(title) as watched"
                                      : "Mark \(Copy.episode(episode)) of \(title) as watched",
                         markedLabel: Copy.Progress.episodeWatched(episode),
                         action: action)
            case .watched:
                // The receipt, kept: a disc with the check, the form the episode list settles
                // into. Not a control here — a schedule is a record, and the row's own long-press
                // menu already carries the corrections.
                MarkRing(marked: true, style: .settled, episode: nil, action: {})
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            case .upcoming:
                Color.clear.frame(width: 44, height: 44)
            }
        }
        .frame(width: 44)
    }
}

// Schedule's row — the date rides it (7 Sep).
//
// The complaint: "The Schedule page looks good but it is ultra dense and extremely confusing."
// Measured on the production account — 5 airings, 2 shows, a 22-day window:
//
//   · SIX full-width date bands for FIVE rows. A band costs ~48 pt (24 gap + label + 10 labelGap)
//     against a 59–80 pt row, so roughly 40 % of the feed's height was a banner introducing exactly
//     one row. The 6 Sep pass saw the symptom ("a feed of one-row days was half header by area")
//     and treated it by shrinking the gap 30 → 24, which is a spacing answer to a structural fault.
//   · Of "7:30 PM · Season 4 · Episode 22", TWO of the three facts are constant for that show
//     across the whole window: a weekly show cannot leave Season 4 inside 22 days, and it airs at
//     the same minute every week. Only the episode number varied — and it sat LAST on the line,
//     the least-scanned position on the row.
//   · "That Time I Got Reincarnated as a Slime" was printed three times, two lines each, with the
//     same tile beside it three times.
//   · Fifteen middot-joined fragments on one screen, about five of which carried news. No fact had
//     a fixed x, so the screen was READ line by line instead of scanned down a column.
//
// So the screen was not dense with content — it was dense with repetition. Three shapes were built
// behind `-scheduleShape` and photographed side by side on the real account (the method that
// settled the month grid, the compact rows and the state ladder), and the user chose THIS one:
//
//   A ✓ the date rides the row      — Google Calendar's Schedule view / Fantastical's agenda
//   B ✗ the bands stay, rows empty  — fixed the caption, left the 40 % of banners untouched
//   C ✗ one block per show          — no repetition at all, but today vanished from the screen
//                                     and the dates ran 2, 9, 16, 4, 11, 18 down the page
//
// B and C are deleted, not flagged off.
//
// THE WIDTH BUDGET, because every question about this row is really a question about it. On a
// 393-pt screen: 16 gutter + date + art + lane + 44 ladder + 16 gutter, with 8–12 pt between.
// "Reincarnated as a Slime" measures 184 pt in Outfit SemiBold 17, so the title needs a lane of at
// least ~184 to keep the two-line break it has today (189 pt). That leaves ~95 pt for the date
// column AND the art together — which is why the art here is a small PORTRAIT rather than the
// 104×59 landscape tile the band-and-row shape carried: a landscape wide enough to read (88 pt)
// leaves a 159-pt lane, and the title then breaks onto three ragged lines, unevenly, since a short
// name like "Re:ZERO" still takes one. The portrait gives every row the same 72-pt floor.

// MARK: - Ink

/// The clock says WHEN, and its ink says which side of now that is: accent while the episode is
/// ahead (the app's one colour rule for a future time), ink the moment it has aired and you have
/// not seen it, tertiary once it is spent.
private func clockInk(_ state: AiringState) -> Color {
    switch state {
    case .upcoming: return ThemeColor.accent
    case .toWatch:  return ThemeColor.textPrimary
    case .watched:  return ThemeColor.textTertiary
    }
}

private func metaInk(_ state: AiringState) -> Color {
    state.isWatched ? ThemeColor.textTertiary : ThemeColor.textSecondary
}

private func titleInk(_ state: AiringState) -> Color {
    state.isWatched ? ThemeColor.textSecondary : ThemeColor.textPrimary
}

/// A reminder is armed for this exact episode — passive, never a control; the row's spoken value
/// says it.
private func bell() -> Text {
    Text(" ") + Text(Image(systemName: "bell.fill"))
        .font(.system(size: 9, weight: .semibold))
        .foregroundStyle(ThemeColor.textTertiary)
}

// MARK: - The date column

/// "WED" over "9" — the weekday as the app's eyebrow, the numeral in the calendar grid's own `time`
/// face, so the column reads as the same instrument the month grid does. Today is accent, the one
/// rule this screen already follows for today. Empty on the second and later airings of a day: the
/// date is printed once and its rows stack under it, as every agenda does.
struct ScheduleDateColumn: View {
    let weekday: String?
    let numeral: String?
    let isToday: Bool
    @ScaledMetric(relativeTo: .subheadline) private var scale: CGFloat = 1

    /// Capped for the same reason the tile is: uncapped it reaches ~70 pt at the accessibility
    /// sizes and eats the lane it exists to protect.
    private var w: CGFloat { min(RowMetrics.dateW * scale, RowMetrics.dateW + 16) }

    var body: some View {
        VStack(alignment: .center, spacing: 1) {
            if let weekday, let numeral {
                Text(weekday)
                    .type(ThemeType.sectionLabel)
                    .textCase(.uppercase)
                    .foregroundStyle(isToday ? ThemeColor.accent : ThemeColor.textTertiary)
                Text(numeral)
                    .type(ThemeType.time)
                    .foregroundStyle(isToday ? ThemeColor.accent : ThemeColor.textSecondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(width: w, alignment: .center)
        .accessibilityHidden(true)
    }
}

// MARK: - The row

/// One airing: the date at a fixed x, the show's art, the show, what varies about this episode, and
/// the state ladder's slot. No day band — the dates ARE the calendar at rest, and the month grid
/// behind the bar's glyph is still there for the shape of a month.
/// The width budget, resolved. See the header: the date column and the tile together may not
/// exceed ~95 pt or the title loses its lane, and a tile narrower than ~88 stops being a picture.
/// Three lines is what that costs the longest names, and it is the cheaper loss. (File scope, not
/// nested: `ScheduleDateRow` is generic over its trailing view, and a generic type may not carry
/// static stored properties.)
private enum RowMetrics {
    static let dateW: CGFloat = 38
    static let tileW: CGFloat = 88
    static let tileH: CGFloat = 50
    static let titleLines = 3
}

struct ScheduleDateRow<Trailing: View>: View {

    /// Nil on the second and later airings of one day.
    let weekday: String?
    let numeral: String?
    let isToday: Bool
    let franchise: Franchise
    /// What VARIES — "Episode 16". No season: it cannot change inside the window.
    let episodeText: String
    let time: String?
    let state: AiringState
    let hasReminder: Bool
    let zoomID: String
    var receiptHost: String? = nil
    @Environment(AppModel.self) private var appModel
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .subheadline) private var artScale: CGFloat = 1
    @ViewBuilder var trailing: () -> Trailing
    let action: () -> Void

    /// The tile scales with Dynamic Type, but only so far: uncapped it eats the lane it sits
    /// beside, and the title then breaks inside a word.
    private var artW: CGFloat { min(RowMetrics.tileW * artScale, RowMetrics.tileW * 1.35) }
    private var artH: CGFloat { min(RowMetrics.tileH * artScale, RowMetrics.tileH * 1.35) }

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize { stacked } else { inline }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel([dateSpoken, franchise.title, episodeText, time]
            .compactMap { $0 }.joined(separator: ", "))
    }

    /// Date, tile, words, ladder — four columns at four fixed x's.
    private var inline: some View {
        HStack(alignment: .top, spacing: ThemeSpace.x3) {
            HStack(alignment: .top, spacing: ThemeSpace.x2) {
                ScheduleDateColumn(weekday: weekday, numeral: numeral, isToday: isToday)
                artButton
            }
            words
            trailing()
        }
        .frame(minHeight: artH)
    }

    /// At the ACCESSIBILITY sizes the row UNFOLDS: the date, the tile and the ladder keep one line
    /// and the words take the screen's full width beneath them.
    ///
    /// Four columns cannot survive that type. Measured at AX-XL: the date column reaches 54, the
    /// tile 119 and the ladder keeps 44, which leaves the words a ~112-pt lane against a ~28-pt
    /// face — and the row printed "Re:ZER / O" broken inside the word, "That Time I Got Reinc…"
    /// truncated (a row may grow at these sizes; it may not lie about which show it is) and pushed
    /// the ladder off the screen entirely. Unfolded, the words have ~361 pt and every part
    /// survives. The same fault, and the same answer, as the clock column this row replaced.
    private var stacked: some View {
        VStack(alignment: .leading, spacing: ThemeSpace.x2) {
            HStack(alignment: .center, spacing: ThemeSpace.x3) {
                ScheduleDateColumn(weekday: weekday, numeral: numeral, isToday: isToday)
                artButton
                Spacer(minLength: 0)
                trailing()
            }
            words
        }
    }

    private var artButton: some View {
        Button(action: action) { artwork.contentShape(Rectangle()) }
            .buttonStyle(OverArtPressStyle())
    }

    private var words: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: ThemeSpace.x0_5) {
                Text(franchise.displayTitle)
                    .type(ThemeType.rowTitle)
                    .foregroundStyle(titleInk(state))
                    .lineLimit(typeSize.isAccessibilitySize ? 4 : RowMetrics.titleLines)
                    .multilineTextAlignment(.leading)
                if let receiptHost, ReceiptLine.isLive(appModel, host: receiptHost) {
                    ReceiptLine(host: receiptHost, compact: true, inline: true)
                } else {
                    caption
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
    }

    /// A watched airing gives up its PICTURE — a flat veil inside the clipped shape, never
    /// `.saturation`/`.blur`, which are per-frame passes on a scrolling list (the 5 Sep rule).
    private var artwork: some View {
        let shape = RoundedRectangle(cornerRadius: ThemeRadius.episodeStill, style: .continuous)
        let wide = franchise.wideArt
        return ZStack {
            shape.fill(ThemeColor.surfaceRaised)
            LandscapeArt(url: wide.url, portraitSource: wide.portraitSource,
                         maxPixel: wide.ultraWide ? 1900 : 420, ultraWide: wide.ultraWide)
        }
        .frame(width: artW, height: artH)
        .clipShape(shape)
        .overlay { if state.isWatched { shape.fill(ThemeColor.canvas.opacity(0.55)) } }
        .overlay(shape.strokeBorder(ThemeColor.posterEdge, lineWidth: 1))
        .zoomSource(zoomID)
    }

    /// "Episode 16 · 6:30 PM" — the fact that VARIES leads, the clock follows it. ONE concatenated
    /// `Text`, never an `HStack` of two: as a stack one run holds `layoutPriority` and the other
    /// carries `lineLimit(1)`, so at the accessibility sizes the row printed a bare clock and never
    /// said which episode — the one fact it exists to give (measured 6 Sep, on the row this
    /// replaces). Concatenated, the run wraps like prose and every part survives.
    private var caption: some View {
        var line = Text(episodeText).foregroundStyle(metaInk(state))
        if let time {
            line = line + Text(" · ").foregroundStyle(ThemeColor.textTertiary)
            line = line + Text(time).foregroundStyle(clockInk(state)).monospacedDigit()
            if hasReminder { line = line + bell() }
        }
        return line
            .type(ThemeType.rowMeta)
            .lineLimit(typeSize.isAccessibilitySize ? 3 : 2)
            .multilineTextAlignment(.leading)
    }

    private var dateSpoken: String? {
        guard let weekday, let numeral else { return nil }
        return "\(weekday) \(numeral)"
    }
}

// MARK: - The calendar

/// The month grid, behind the bar's calendar button.
///
/// At rest the screen has NO date chrome — the feed's day headers are the calendar, which is what
/// animeschedule.net and Trakt v3 do. The grid is what the reader asks for, which is where
/// Fantastical (pull the DayTicker down) and Google Calendar (the month dropdown) both put it; it
/// is a TAP here rather than a pull because this screen already owns the pull gesture for refresh.
///
/// It OVERLAYS the feed rather than pushing it (Google Calendar's dropdown, not Fantastical's
/// inline expansion): 500 pt of grid inserted above a lazy stack shoved the reader's place three
/// screens down and back again on every toggle.
///
/// **The grid only answers for days the feed actually holds.** `AppModel.scheduleBack…scheduleAhead`
/// is a 22-day window; a month has thirty-odd. A cell outside the window used to be an ordinary
/// target that landed on "Nothing scheduled" — which is a lie, since the truth is that nothing is
/// KNOWN about 25 September. Those days are drawn quiet and are inert, and the month arrows stop
/// at the window's own months.
struct ScheduleMonthGrid: View {
    let todayNoon: Int64
    /// Day offset from today → how many airings that day carries.
    let counts: [Int: Int]
    /// Days with something still to come or still to watch.
    let live: Set<Int>
    let selected: Int
    /// The days the feed can actually answer for.
    let window: ClosedRange<Int>
    /// Which month is on screen, as a day offset from today of any day inside it.
    @Binding var monthAnchor: Int
    /// The tallest the panel may be — the feed's viewport, less the room the grid should not eat.
    /// A six-row month at the accessibility sizes is ~660 pt and the screen has ~650 to give.
    let maxHeight: CGFloat
    let onPick: (Int) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The numeral's disc, and the row's height with the dot under it.
    @ScaledMetric(relativeTo: .subheadline) private var scaledDisc: CGFloat = 34
    /// The height of everything above the weeks (the month row and the weekday letters), measured
    /// rather than assumed — both scale with Dynamic Type.
    @State private var headerH: CGFloat = 68

    private static let cal = Calendar(identifier: .gregorian)

    /// The disc scales with Dynamic Type up to the column it has to live in. Seven columns share
    /// ~353 pt, so a cell is ~50 wide; uncapped the disc reached ~78 at the accessibility sizes
    /// and seven of them forced the panel 180 pt wider than the screen — the arrows, Sunday and
    /// Saturday were all off the edges (captured 6 Sep). A grid's cell cannot be wider than a
    /// seventh of its grid, whatever the text size says.
    private var discSize: CGFloat { min(scaledDisc, 44) }

    /// A week's row: the numeral's disc, the gap, the dot.
    private var cellH: CGFloat { discSize + 3 + 6 }

    private func date(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: Double(todayNoon + Int64(offset) * Formatting.D) / 1000)
    }

    /// Offsets of the days drawn in the grid: the anchor month's days, preceded by blanks for the
    /// weekdays before the 1st. Sunday-first, stated by the app rather than read from the device's
    /// region, which resolves to Monday in much of the world (the user's rule, 6 Sep: "the mental
    /// model for anyone in general").
    private var slots: [Int?] {
        let cal = Self.cal
        let anchor = date(monthAnchor)
        guard let range = cal.range(of: .day, in: .month, for: anchor),
              let first = cal.date(from: cal.dateComponents([.year, .month], from: anchor))
        else { return [] }
        // `.weekday` is 1 = Sunday … 7 = Saturday, so the lead-in is weekday − 1.
        let lead = cal.component(.weekday, from: first) - 1
        let firstOffset = cal.dateComponents([.day], from: cal.startOfDay(for: date(0)),
                                             to: cal.startOfDay(for: first)).day ?? 0
        return Array(repeating: nil, count: lead) + range.map { firstOffset + $0 - 1 }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: ThemeSpace.x2) {
                header
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { col in
                        // Sunday-first: column 0 is Sunday whatever the device's region says.
                        Text(Formatting.weekdayLetterMonFirst((col + 6) % 7))
                            .type(ThemeType.caption)
                            .textCase(.uppercase)
                            .foregroundStyle(ThemeColor.textTertiary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.bottom, ThemeSpace.x1)
            }
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { if $0 > 0 { headerH = $0 } }
            let cells = slots
            let weekRows = (cells.count + 6) / 7
            // A `ScrollView` is GREEDY — it takes every point it is offered, and a `maxHeight` on
            // it or on the panel let it pad the surface out to the cap and centre the month inside
            // a hand's width of nothing. Its height is STATED: the weeks it has, or as much of them
            // as the screen can give, whichever is less.
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    ForEach(0..<weekRows, id: \.self) { row in
                        // THE WEEK SEPARATOR (user, 6 Sep: "a visual cue for week separation is
                        // also necessary to avoid confusion"). Five rows of loose numerals in one
                        // field have nothing telling the eye where a week ends, so a date and the
                        // date below it read as neighbours. A hairline rule above each row but the
                        // first is what every month grid on the platform draws, and it is the
                        // lightest mark that can do it — `hairline` is white at 0.055.
                        if row > 0 {
                            Rectangle()
                                .fill(ThemeColor.hairline)
                                .frame(height: 1)
                                .padding(.horizontal, ThemeSpace.x1)
                        }
                        HStack(spacing: 0) {
                            ForEach(0..<7, id: \.self) { col in
                                let i = row * 7 + col
                                if i < cells.count, let offset = cells[i] {
                                    cell(offset)
                                } else {
                                    Color.clear.frame(maxWidth: .infinity).frame(height: cellH)
                                }
                            }
                        }
                        .padding(.vertical, ThemeSpace.x1)
                    }
                }
            }
            .frame(height: min(naturalWeeksH(weekRows), weeksBudget))
            .scrollBounceBehavior(.basedOnSize, axes: .vertical)
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, ThemeSpace.x2)
        .padding(.vertical, ThemeSpace.x3)
    }

    /// The weeks at their natural height — every row drawn, nothing scrolling. A row is the cells
    /// plus their padding, and every row but the first carries a 1-pt rule.
    private func naturalWeeksH(_ rows: Int) -> CGFloat {
        let row = cellH + ThemeSpace.x1 * 2
        return CGFloat(rows) * row + CGFloat(max(0, rows - 1))
    }

    /// What is left for the weeks once the month row, the weekday letters and the panel's own
    /// padding have taken theirs. A six-row month at the accessibility sizes wants more than the
    /// screen has to give, and this is what makes it scroll instead of running under the tab bar.
    private var weeksBudget: CGFloat {
        max(120, maxHeight - headerH - ThemeSpace.x3 * 2)
    }

    /// "September 2026" — the month NAMED, in the app's emphasis body, not an 11-pt grey eyebrow.
    /// A calendar's month is the one thing on the panel that says where you are.
    private var header: some View {
        HStack(spacing: 0) {
            arrow("chevron.left", step: -1, label: Copy.Schedule.previousMonth)
            Spacer(minLength: 0)
            Text(Formatting.fmtMonthNameYear(todayNoon + Int64(monthAnchor) * Formatting.D))
                .type(ThemeType.bodyEmphasis)
                .foregroundStyle(ThemeColor.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Spacer(minLength: 0)
            arrow("chevron.right", step: 1, label: Copy.Schedule.nextMonth)
        }
    }

    /// A month arrow, live only while the window reaches into the month it would show. Past the
    /// horizon there is nothing to page to, and an arrow that pages to a blank month is an
    /// invitation to keep pressing it.
    private func arrow(_ glyph: String, step: Int, label: String) -> some View {
        let target = monthOffset(by: step)
        let reachable = target.map { monthIntersectsWindow($0) } ?? false
        return Button {
            guard let target else { return }
            FeedbackCoordinator.fire(.selection)
            withAnimation(ThemeMotion.pick(ThemeMotion.uiSnappy, reduceMotion: reduceMotion)) {
                monthAnchor = target
            }
        } label: {
            Image(systemName: glyph).font(.system(size: 15, weight: .semibold))
        }
        .frame(width: 44, height: 34)
        .tint(ThemeColor.interactive)
        .disabled(!reachable)
        .opacity(reachable ? 1 : 0.25)
        .accessibilityLabel(label)
    }

    private func monthOffset(by step: Int) -> Int? {
        let cal = Self.cal
        guard let next = cal.date(byAdding: .month, value: step, to: date(monthAnchor)) else { return nil }
        return cal.dateComponents([.day], from: cal.startOfDay(for: date(0)),
                                  to: cal.startOfDay(for: next)).day
    }

    /// Does the month containing `offset` hold any day the feed can answer for?
    private func monthIntersectsWindow(_ offset: Int) -> Bool {
        let cal = Self.cal
        let anchor = date(offset)
        guard let range = cal.range(of: .day, in: .month, for: anchor),
              let first = cal.date(from: cal.dateComponents([.year, .month], from: anchor)),
              let firstOffset = cal.dateComponents([.day], from: cal.startOfDay(for: date(0)),
                                                   to: cal.startOfDay(for: first)).day
        else { return false }
        return firstOffset <= window.upperBound && firstOffset + range.count - 1 >= window.lowerBound
    }

    /// One day. Apple Calendar's anatomy, which is the one every reader already knows: the numeral
    /// in a disc that fills when the day is SELECTED, today's numeral in the accent, and the day's
    /// content as a dot beneath. Every numeral is the same weight and size — TONE carries the
    /// hierarchy, as it does everywhere else in the app — because a grid of mixed weights reads as
    /// a grid of mistakes.
    private func cell(_ offset: Int) -> some View {
        let ts = todayNoon + Int64(offset) * Formatting.D
        let isToday = offset == 0
        let isSelected = offset == selected
        let known = window.contains(offset)
        let n = counts[offset] ?? 0
        return Button {
            FeedbackCoordinator.fire(.selection)
            onPick(offset)
        } label: {
            VStack(spacing: 3) {
                ZStack {
                    if isSelected {
                        Circle().fill(ThemeColor.surfaceFloating)
                    }
                    Text("\(Formatting.localParts(ts).d)")
                        .type(ThemeType.time)
                        .foregroundStyle(numeralInk(isToday: isToday, hasContent: n > 0))
                        // The numeral gives way inside the capped disc rather than pushing it.
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .frame(width: discSize, height: discSize)
                // The day's content: amber while something on it is still to come or still to
                // watch, quiet once it is spent, nothing at all where there is none.
                Circle()
                    .fill(n == 0 ? .clear
                          : (live.contains(offset) ? ThemeColor.accent : ThemeColor.textTertiary))
                    .frame(width: 6, height: 6)
            }
            .frame(maxWidth: .infinity)
            .frame(height: cellH)
            .contentShape(Rectangle())
        }
        .buttonStyle(CalendarCellPressStyle())
        // Outside the feed's window there is no answer to give: the day is drawn as context and
        // does not take a tap. "Nothing scheduled" would claim knowledge the app does not have.
        .disabled(!known)
        .opacity(known ? 1 : 0.4)
        .accessibilityLabel(Date(timeIntervalSince1970: Double(ts) / 1000)
            .formatted(.dateTime.weekday(.wide).day().month(.wide)))
        .accessibilityValue(!known ? Copy.Schedule.beyondHorizon
                            : (n > 0 ? Copy.episodes(n) : Copy.Schedule.noEpisodes))
    }

    private func numeralInk(isToday: Bool, hasContent: Bool) -> Color {
        if isToday { return ThemeColor.accent }
        return hasContent ? ThemeColor.textPrimary : ThemeColor.textSecondary
    }
}

/// A calendar cell's press feedback: the app's compression floor and a dip, nothing painted.
struct CalendarCellPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.985 : 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(ThemeMotion.pick(ThemeMotion.uiPress, reduceMotion: reduceMotion),
                       value: configuration.isPressed)
    }
}
