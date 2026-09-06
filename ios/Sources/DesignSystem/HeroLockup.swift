import SwiftUI

/// The billboard LOCKUP — Today's hero and the show page's, ONE view (5 Sep).
///
/// Reading order, top to bottom: the STATE as a filled `HeroBadge` ("NEW EPISODE", "4 EPISODES
/// BEHIND", "COMPLETE"); the show's NAME (`HeroTitle` — the logo treatment at the headline's
/// mass, else the name in type); ONE line, the moment then the episode ("Today at 7:30 PM ·
/// Season 4 · Episode 21", "Aired 29 min ago · Season 4 · Episode 12", a backlog's "Season 2 ·
/// Episode 7" alone), with an optional accessory on its trailing edge (the show page's reveal
/// glyph); the season bar; a support line where one is earned; and the actions beneath (the mark
/// capsule, "Start rewatch", "Add to Library"). Prime Video's and Disney+'s grammar: a badge is
/// the signal, the size goes to the name, the rest is one line.
///
/// The show page drew its own version until 5 Sep — the name and a grey identity line on the
/// art, then the badge, the fact and the capsule as a second block on canvas: two lockups with
/// two grammars in 150 pt, the hero's foot the greyest line on the screen and the first thing
/// under the seam the loudest ("poorly built and rushed", user). One view, two callers; the
/// page's identity line heads its synopsis now.
struct HeroLockup<Accessory: View, Actions: View>: View {
    let badge: String
    /// The badge names something OUT NOW and unwatched, so it takes the finite entrance beat.
    var badgeAttention: Bool = false
    /// The name in type, and what VoiceOver says for a logo.
    let title: String
    var name: BillboardName = .type
    var font: TypeToken = ThemeType.displayXL
    var lineLimit: Int? = 2
    var minimumScale: CGFloat = 0.82
    /// The WHEN, leading the one line. Nil for a state with no live moment.
    var moment: String? = nil
    /// The episode — "Season 4 · Episode 21" — or the season, or the finished show's count.
    let fact: String
    var support: String? = nil
    /// A third, tertiary line — the finished show's "Last finished 3 Aug". Today never has one.
    var third: String? = nil
    /// Where you are, 0–1, as the one `ProgressBar` under the line — never a count in words.
    var progress: Double? = nil
    var progressSpoken: String? = nil
    /// Today: the whole copy block opens the show. Nil on the show page, where the block IS the
    /// page and nothing opens.
    var onOpen: (() -> Void)? = nil
    /// False while a mark is handing over to the next show on Today.
    var interactive: Bool = true
    /// The in-place receipt's host (`ReceiptHost`), drawn as an OVERLAY hanging under the
    /// actions — never a layout child: mounted in the flow it pushed the whole lockup up 48 pt a
    /// second after the tap and dropped it back six seconds later (review, 5 Sep).
    var receiptHost: String? = nil
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var actions: () -> Actions

    @Environment(\.dynamicTypeSize) private var typeSize
    private var isAX: Bool { typeSize.isAccessibilitySize }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let onOpen {
                // The largest target on the home screen had no press state at all. A
                // `surfacePressed` wash over a photograph is a grey film over someone's
                // illustration, so the art dips in brightness and compresses a hair instead.
                Button(action: onOpen) { copy }
                    .buttonStyle(OverArtPressStyle())
                    .shadow(.art)
                    .accessibilityElement(children: .combine)
                    .accessibilityHint(Copy.Accessibility.opensTheShowHint)
            } else {
                copy
                    .shadow(.art)
                    .accessibilityElement(children: .combine)
            }
            // No action row when there is nothing to do: a calm hero is the art, the state and
            // the moment. A lone grey capsule under it read as a primary that had gone missing.
            actions()
                .padding(.top, isAX ? ThemeSpace.x5 : ThemeSpace.x4)
                .overlay(alignment: .bottom) {
                    if let receiptHost {
                        ReceiptLine(host: receiptHost)
                            // Hung under the capsule's bottom edge, in the room between it and
                            // the next section, so nothing it confirms moves. An offset by its
                            // own height, not an alignment guide: a guide set inside the
                            // overlay's conditional was ignored and the line sat on the capsule.
                            // By its own height, no more (review i3: at +34 the line sat three
                            // times closer to the next section's title than to the capsule).
                            .offset(y: ReceiptLine.height)
                    }
                }
        }
        .allowsHitTesting(interactive)
    }

    /// Type laid on a photograph needs a contact shadow the same way art laid on a canvas does —
    /// without it the descenders dissolve into whatever is behind them (`.shadow(.art)`, applied
    /// by the caller above so the capsule beneath does not carry one).
    /// CENTRED (5 Sep): the whole lockup on the billboard's axis — the badge, the name, the line
    /// with its accessory beside it, the bar — with the capsule full width beneath. The Netflix
    /// billboard's lockup, chosen from three photographed placements (foot-left, centred, on the
    /// art) after the show's logotype came back as the headline; the rest of the page keeps its
    /// left axis.
    private var copy: some View {
        VStack(alignment: .center, spacing: 0) {
            HeroBadge(text: badge, attention: badgeAttention)
                .numericFact(badge)
            HeroTitle(text: title, name: name, font: font, lineLimit: lineLimit, minimumScale: minimumScale)
                .padding(.top, ThemeSpace.x3)
            // ONE line: the moment, then the episode. Secondary, so the name and the line never
            // read as one. The accessory is a 44-pt control that shares the row without growing
            // it, pulled back onto the gutter optically.
            // ONE line: the moment, then the episode, centred, with the accessory (the show
            // page's reveal glyph) riding its trailing edge as part of the same group — a 44-pt
            // control that shares the row without growing it.
            HStack(alignment: .center, spacing: ThemeSpace.x1) {
                line([moment, fact].compactMap { $0 }.joined(separator: " \u{00B7} "))
                    .multilineTextAlignment(.center)
                accessory()
                    .padding(.vertical, -12)
                    .padding(.trailing, -8)
            }
            .padding(.top, ThemeSpace.x1)
            if let progress {
                ProgressBar(value: progress, spoken: progressSpoken)
                    .frame(maxWidth: isAX ? .infinity : 200)
                    .padding(.top, ThemeSpace.x2)
            }
            if let support {
                Text(support)
                    .type(ThemeType.metadata)
                    .foregroundStyle(ThemeColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, ThemeSpace.x1)
            }
            if let third {
                Text(third)
                    .type(ThemeType.metadata)
                    .foregroundStyle(ThemeColor.textTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, ThemeSpace.x0_5)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .contentShape(Rectangle())
    }

    private func line(_ text: String) -> some View {
        Text(text)
            .type(ThemeType.heroMeta)
            .foregroundStyle(ThemeColor.textSecondary)
            .numericFact(text)
            .fixedSize(horizontal: false, vertical: true)
    }
}
