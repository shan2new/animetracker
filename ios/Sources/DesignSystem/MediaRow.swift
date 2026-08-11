import SwiftUI

/// The redesign's borderless list row — the shared primitive behind Today and Schedule.
///
/// A plain-gradient poster thumb, the title, and ONE metadata line led by the quiet source glyph,
/// plus an optional single trailing control. No card fill or border: rows sit in a plain stack and
/// are separated by a `HairlineDivider` inset past the thumbnail. Restraint rule #6: one fact per
/// row, accent only where it means something. The `meta` Text is built by the caller so it can tint
/// a lead token (e.g. accent "New episode"); runs without an explicit colour inherit `text52`.
struct MediaRow<Trailing: View>: View {
    let cover: String?
    let source: MediaSource
    let title: String
    let meta: Text
    var thumbWidth: CGFloat = 44
    var thumbHeight: CGFloat = 60
    let onTap: () -> Void
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                Thumb(cover: cover, width: thumbWidth, height: thumbHeight, radius: Theme.Radius.thumb)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .scaledFont(16, weight: .semibold)
                        .tracking(-0.3)
                        .lineLimit(1)
                        .foregroundStyle(Theme.textPrimary)
                    HStack(spacing: 6) {
                        SourceGlyph(source: source, size: 12)
                        meta
                            .scaledFont(13, weight: .medium, monospacedDigit: true)
                            .foregroundStyle(Theme.text52)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 10)
                trailing()
            }
            .padding(.vertical, Theme.Space.row)
            .contentShape(Rectangle())
        }
        .buttonStyle(SpringPressButtonStyle(scale: 0.98))
    }
}

/// Hairline separator between borderless rows, inset past the thumbnail (thumb width + gap = 58).
struct HairlineDivider: View {
    var inset: CGFloat = 58
    var body: some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(height: 1)
            .padding(.leading, inset)
    }
}

/// The ✓ "mark caught up" circle on Today's Out now rows — accent ring over a soft accent fill.
/// Tapping advances progress to the latest aired episode. Distinct from the passive "Caught up"
/// status badge; the bounce press-style supplies the "small pop".
struct MarkCaughtUpCircle: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "checkmark")
                .scaledFont(15, weight: .bold)
                .foregroundStyle(Theme.accent)
                .frame(width: 34, height: 34)
                .background(Theme.accentSoft, in: Circle())
                .overlay(Circle().stroke(Theme.accentBorder, lineWidth: 1.5))
        }
        .buttonStyle(BounceButtonStyle())
        .accessibilityLabel("Mark caught up")
    }
}

/// Quiet "See all 7" expander for Today's collapsed sections — a text affordance, not a button
/// chrome, so it never competes with the rows above it.
struct SeeMoreButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            HStack(spacing: 5) {
                Text(label).scaledFont(13, weight: .semibold)
                Image(systemName: "chevron.down").scaledFont(10, weight: .semibold)
            }
            .foregroundStyle(Theme.text52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Accent minute-countdown text ("2d 4h") for anime Up-next rows. Rolls with numericText so the
/// ticking number stays calm. Anime only — TV has no minute-precise countdown.
struct CountdownText: View {
    let text: String
    var body: some View {
        Text(text)
            .scaledFont(13.5, weight: .semibold, monospacedDigit: true)
            .foregroundStyle(Theme.accent)
            .contentTransition(.numericText(countsDown: true))
            .animation(.uiSnappy, value: text)
    }
}

/// Accent "Start ▸" affordance for a not-yet-started drop (e.g. a freshly available TV season).
struct StartLink: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text("Start").scaledFont(13.5, weight: .semibold)
                Image(systemName: "play.fill").scaledFont(10)
            }
            .foregroundStyle(Theme.accent)
            .fixedSize()
        }
        .buttonStyle(SpringPressButtonStyle(scale: 0.94))
    }
}

/// Anime schedule trailing — a right-aligned airing-time stack. Today: the clock time over an
/// accent relative countdown ("5:30 PM" / "in 8h"). A future day: an "AIRS" eyebrow over the clock
/// ("AIRS" / "9:00 PM"). Anime only — TV never shows a time.
struct AirtimeStack: View {
    let clock: String
    let countdown: String?   // non-nil → today (accent countdown); nil → "AIRS" eyebrow

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            if let countdown, !countdown.isEmpty {
                Text(clock)
                    .scaledFont(15, weight: .medium, monospacedDigit: true)
                    .foregroundStyle(Theme.textPrimary)
                Text(countdown)
                    .scaledFont(11, weight: .semibold, monospacedDigit: true)
                    .foregroundStyle(Theme.accent)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.uiSnappy, value: countdown)
            } else {
                Text("AIRS")
                    .scaledFont(9, weight: .semibold)
                    .tracking(1)
                    .foregroundStyle(Theme.text28)
                Text(clock)
                    .scaledFont(15, weight: .medium, monospacedDigit: true)
                    .foregroundStyle(Theme.textPrimary)
            }
        }
        .fixedSize()
        // One spoken fact, not three fragments — the bare "AIRS" eyebrow reads as letters.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(voiceLabel)
    }

    private var voiceLabel: String {
        if let countdown, !countdown.isEmpty { return "Airs \(clock), \(countdown)" }
        return "Airs \(clock)"
    }
}

/// TV schedule trailing — a plain-text label, never a time. "Season drop" / "Premiere" read accent
/// (a genuine availability event); "New episode" stays quiet; "Finale" is quiet with a small accent
/// dot. The date is already conveyed by the day bucket, so no relative span here.
struct ScheduleTVLabel: View {
    let text: String
    var accent: Bool = false
    var dot: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            if dot { Circle().fill(Theme.accent).frame(width: 5, height: 5) }
            Text(text)
                .scaledFont(12, weight: .semibold)
                .foregroundStyle(accent ? Theme.accent : Theme.text62)
        }
        .fixedSize()
    }
}

/// A compact two-line airing badge for an episode's next-air date (Detail accordion). TV shows day
/// words ("Sun" / "in 4d"); anime shows the clock time over a minute countdown ("9:00 PM" / "2d 4h").
/// Accent + soft fill when imminent, ghost otherwise — the one accent moment in the airing list.
struct DateBadge: View {
    let ts: Int64
    let now: Int64
    let source: MediaSource

    /// Which calendar `ts` is read in. A date-only (TV) timestamp is a UTC day, not an instant —
    /// formatting it locally pushes the badge a day forward east of UTC+7.
    private var anchor: Formatting.TimeAnchor { source.timeAnchor }

    private var imminent: Bool {
        // Day precision for a date-only release (there is no hour to compare), hours for an instant.
        anchor.isDateOnly
            ? Formatting.dayDiff(ts: ts, now: now, anchor: anchor) <= 7
            : (ts - now) <= 24 * Formatting.H
    }
    private var lines: (top: String, bottom: String) {
        if anchor.isDateOnly { return Formatting.fmtDayBadge(ts: ts, now: now, anchor: anchor) }
        // fmtCountdown collapses to "now" once imminent/past — "in now" doesn't read.
        let countdown = Formatting.fmtCountdown(target: ts, now: now, anchor: anchor)
        return (Formatting.fmtTime(ts, anchor: anchor), countdown == "now" ? "now" : "in \(countdown)")
    }

    var body: some View {
        let l = lines
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return VStack(spacing: 1) {
            Text(l.top)
                .scaledFont(11.5, weight: .bold, monospacedDigit: true)
                .foregroundStyle(imminent ? Theme.accent : Theme.text72)
            Text(l.bottom)
                .scaledFont(9, weight: .semibold, monospacedDigit: true)
                .foregroundStyle(imminent ? Theme.accent70 : Theme.text40)
        }
        .frame(minWidth: 46)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(imminent ? Theme.accentSoft : Theme.fillSoft, in: shape)
        .overlay(shape.stroke(imminent ? Theme.accentBorder : Theme.hairlineStrong, lineWidth: 1))
        // Two stacked fragments are one fact ("Tomorrow, in 1d"), so speak them together.
        .accessibilityElement(children: .combine)
    }
}
