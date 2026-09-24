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
    /// Public release news takes the headline even when the viewer is seasons behind.
    var releaseNews: ReleaseNews? = nil
    /// The name in type, and what VoiceOver says for a logo.
    let title: String
    var name: BillboardName = .type
    /// A precomposed poster supplies the identity: the two small groups are staged around its
    /// actual lettering (`PosterStage`). Nil for filled art, where the lockup sits at the foot.
    var posterStage: PosterStage? = nil
    var onPosterHeadlineHeight: ((CGFloat) -> Void)? = nil
    var onPosterControlsHeight: ((CGFloat) -> Void)? = nil
    /// The picture's `HeroProtection.strength`: the poster stage's local scrims deepen over
    /// bright art.
    var posterProtection: Double = HeroProtection.full
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
    /// The bar's bottom edge (global): the lockup LEAVES as it passes under it (`FadesUnderBar`).
    /// Nil for a lockup that never scrolls under chrome.
    var fadeBand: CGFloat? = nil
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var actions: () -> Actions

    @Environment(\.dynamicTypeSize) private var typeSize
    private var isAX: Bool { typeSize.isAccessibilitySize }
    private var posterScrim: Color { HeroProtection.posterScrim(posterProtection) }

    var body: some View {
        if name == .embedded, let posterStage {
            PosterLockupLayout(stage: posterStage) {
                VStack(spacing: ThemeSpace.x2) {
                    headline
                    // A poster with no lettering does not carry the name: set it here, in type,
                    // between the badge and the news (`PosterTitleRegion.untitled`).
                    if posterStage.untitled {
                        HeroTitle(text: title, name: .type, font: font, lineLimit: lineLimit,
                                  minimumScale: minimumScale)
                            .padding(.top, ThemeSpace.x1)
                    }
                    newsDetail
                }
                .frame(maxWidth: .infinity)
                .shadow(.art)
                .background {
                    // A name set in type on an untitled poster gets the controls' soft local
                    // scrim: "That Time I Got Reincarnated as a Slime" in white across a busy,
                    // bright key visual read at a glance only where the art happened to be dark.
                    if posterStage.untitled {
                        LinearGradient(colors: [.clear, posterScrim, posterScrim],
                                       startPoint: .top, endPoint: .bottom)
                            .padding(.horizontal, -ThemeMetrics.gutter)
                            .padding(.top, -28)
                            // Down to the controls' top edge, where their scrim takes over.
                            .padding(.bottom, -PosterStage.gap)
                            .allowsHitTesting(false)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel([title, releaseNews?.headline ?? badge, releaseNews?.detail]
                    .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", "))
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { onPosterHeadlineHeight?($0) }
                .fadesUnderBar(fadeBand)

                VStack(spacing: 0) {
                    episodeCopy.shadow(.art)
                    actions()
                        .padding(.top, hasEpisodeCopy ? (isAX ? ThemeSpace.x5 : ThemeSpace.x4) : 0)
                }
                .frame(maxWidth: .infinity)
                .background {
                    // A soft, local legibility scrim, not a panel or blurred art extension.
                    // The pale floor in Re:ZERO otherwise swallows the episode/series actions.
                    // Under an untitled poster's typed name it CONTINUES the headline's ramp
                    // (starting at full strength, where that one ends) — two ramps met on a
                    // hard line across the art (23 Sep).
                    LinearGradient(colors: posterStage.untitled
                                        ? [posterScrim, posterScrim, .clear]
                                        : [.clear, posterScrim, posterScrim, .clear],
                                   startPoint: .top, endPoint: .bottom)
                        .padding(.horizontal, -ThemeMetrics.gutter)
                        .padding(.top, posterStage.untitled ? 0 : -24)
                        .padding(.bottom, -24)
                        .allowsHitTesting(false)
                }
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { onPosterControlsHeight?($0) }
                .fadesUnderBar(fadeBand)
            }
            .allowsHitTesting(interactive)
        } else {
            regularLockup
                .fadesUnderBar(fadeBand)
        }
    }

    private var regularLockup: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let onOpen {
                // The largest target on the home screen had no press state at all. A
                // `surfacePressed` wash over a photograph is a grey film over someone's
                // illustration, so the art dips in brightness and compresses a hair instead.
                Button(action: onOpen) { copy }
                    .buttonStyle(OverArtPressStyle())
                    .shadow(.art)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(spokenCopy)
                    .accessibilityHint(Copy.Accessibility.opensTheShowHint)
            } else {
                copy
                    .shadow(.art)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(spokenCopy)
            }
            // No action row when there is nothing to do: a calm hero is the art, the state and
            // the moment. A lone grey capsule under it read as a primary that had gone missing.
            actions()
                .padding(.top, isAX ? ThemeSpace.x5 : ThemeSpace.x4)
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
            headline
            if name != .embedded {
                HeroTitle(text: title, name: name, font: font, lineLimit: lineLimit, minimumScale: minimumScale)
                    .padding(.top, ThemeSpace.x3)
            }
            // ONE line: the moment, then the episode. Secondary, so the name and the line never
            // read as one. The accessory is a 44-pt control that shares the row without growing
            // it, pulled back onto the gutter optically.
            // ONE line: the moment, then the episode, centred, with the accessory (the show
            // page's reveal glyph) riding its trailing edge as part of the same group — a 44-pt
            // control that shares the row without growing it.
            newsDetail.padding(.top, releaseNews?.detail == nil ? 0 : ThemeSpace.x2)
            episodeCopy
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .contentShape(Rectangle())
    }

    /// The badge: the state, or — for a show you have not started — the catalogue's news in the
    /// SAME amber tag ("SEASON 3 ANNOUNCED"). The news drew a third badge style of its own, white
    /// on a dark pill, beside the amber tag and Today's white capsule (review, 23 Sep).
    @ViewBuilder private var headline: some View {
        if let news = releaseNews {
            HeroBadge(text: news.headline)
        } else if !badge.isEmpty {
            HeroBadge(text: badge, attention: badgeAttention).numericFact(badge)
        }
    }

    /// The news's one fact ("Oct 2026", "Episode 5 airs Friday at 7:30 PM") in the lockup's own
    /// line grammar.
    @ViewBuilder private var newsDetail: some View {
        if let detail = releaseNews?.detail {
            line(detail)
                .multilineTextAlignment(.center)
        }
    }

    private var hasEpisodeCopy: Bool {
        !fact.isEmpty || progress != nil || support != nil || third != nil
    }

    private var episodeCopy: some View {
        VStack(alignment: .center, spacing: 0) {
            if !fact.isEmpty {
                HStack(alignment: .center, spacing: ThemeSpace.x1) {
                    line([moment, fact].compactMap { $0 }.joined(separator: " \u{00B7} "))
                        .multilineTextAlignment(.center)
                    accessory()
                        .padding(.vertical, -12)
                        .padding(.trailing, -8)
                }
                .padding(.top, ThemeSpace.x1)
            }
            if let progress {
                // WHITE on the art (24 Sep): the badge is the news (red), the capsule the action
                // (amber) — an amber bar between them read with the capsule as one amber object
                // with a stripe (critique). On the page's ground the season bar stays amber.
                ProgressBar(value: progress, spoken: progressSpoken, onArt: true)
                    .frame(maxWidth: isAX ? .infinity : 200)
                    .padding(.top, ThemeSpace.x2)
            }
            if let support {
                Text(support)
                    .type(ThemeType.metadata)
                    .foregroundStyle(ThemeColor.textPrimary.opacity(0.86))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, ThemeSpace.x1)
            }
            if let third {
                Text(third)
                    .type(ThemeType.metadata)
                    .foregroundStyle(ThemeColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, ThemeSpace.x0_5)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .contentShape(Rectangle())
    }

    /// A poster's printed logo has no text node. Keep its full title in the spoken lockup
    /// without manufacturing a second visible heading or an empty title-sized spacer.
    private var spokenCopy: String {
        [title, releaseNews?.headline ?? badge, releaseNews?.detail, moment, fact,
         progressSpoken, support, third].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// ONE ink for the line on every billboard (review i3: a swipe across the deck turned it from
    /// white on the poster page to grey on the next). White, like every line laid on art; the
    /// name above it is a logo or display type, so the two never read as one.
    private func line(_ text: String) -> some View {
        Text(text)
            .type(ThemeType.heroMeta)
            .foregroundStyle(ThemeColor.textPrimary)
            .numericFact(text)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A poster that carries its own title, staged (23 Sep review): how tall the stage is, and where
/// the lockup's two groups — the headline (badge, news) and the controls (the episode, the bar,
/// the actions) — sit on it.
///   • The picture is ALWAYS full bleed from the top edge, the chrome floating over it (Apple TV,
///     Netflix). Moving a top-printed title down below the chrome, with a band of the show's
///     colour above it, cost the billboard its cinema — "the app no longer feels cinematic or
///     immersive" (user, 23 Sep) — so a title printed across the top simply stays there, under
///     glass.
///   • The headline may sit directly above the printed title; the controls are always BELOW it,
///     at the stage's foot. Percy's badge, date, capsule and link stacked ABOVE its logo, across
///     the faces, so the show's name read last.
///   • When the foot is too short for them the stage grows BELOW the picture, onto the ground the
///     poster fades into — never by zooming the poster, never by stacking controls over it.
///   • A poster with no lettering at all (`PosterTitleRegion.untitled`) carries the typed name
///     in the headline, and the whole lockup sits at its foot.
struct PosterStage: Equatable {
    static let gap: CGFloat = 12
    /// A printed title that ENDS within this share of the poster is a top title: the headline
    /// hangs beneath it rather than at the foot.
    static let topTitleShare: CGFloat = 0.4
    /// The chrome below the status bar on both billboards — Today's wordmark band, the show
    /// page's toolbar — that a printed title must clear.
    static let chromeBand: CGFloat = 56

    /// Where the picture starts inside the stage.
    let posterTop: CGFloat
    /// The picture's own height at the stage's width.
    let posterHeight: CGFloat
    /// The stage: the picture plus whatever ground the controls needed under it.
    let height: CGFloat
    let headlineY: CGFloat
    let controlsY: CGFloat
    /// Where the show's NAME begins and ends on the stage — the printed title's bounds, or the
    /// lockup's for an untitled poster. The show page docks its bar title once the name has
    /// passed UNDER the bar (`nameBottom`): a title printed at the top starts there.
    let nameTop: CGFloat
    let nameBottom: CGFloat
    let untitled: Bool

    /// `minHeight`: a stage that must match its neighbours — a page of Today's release deck is
    /// as tall as the deck, the extra ground under its poster, the lockup at its foot.
    init(posterHeight native: CGFloat, region: PosterTitleRegion, chromeBottom: CGFloat,
         headline: CGFloat, controls: CGFloat, minHeight: CGFloat = 0) {
        let gap = Self.gap
        let between: CGFloat = headline > 0 && controls > 0 ? gap : 0
        let total = headline + between + controls
        posterHeight = native
        untitled = region.isUntitled
        posterTop = 0
        if region.isUntitled {
            let h = max(native, chromeBottom + gap + total + gap, minHeight)
            height = h
            headlineY = h - gap - total
            controlsY = headlineY + headline + between
            nameTop = headlineY
            nameBottom = headlineY + headline
            return
        }
        let titleTop = region.top * native
        let titleBottom = region.bottom * native
        let foot = native
        nameTop = titleTop
        nameBottom = titleBottom
        // A title printed across the TOP of the poster: the headline hangs directly BENEATH its
        // lettering and the controls keep the foot (24 Sep). At the foot, Re:ZERO's "NEW EPISODE"
        // sat ~300 pt from the name it describes, over a character's lap, stacked on the bar and
        // the capsule — red, amber, amber in 130 pt (critique). Under the name, "Re:ZERO … SEASON
        // 4 / NEW EPISODE" is one lockup, the way a badge sits over a title printed lower down.
        if headline > 0, controls > 0, titleBottom <= native * Self.topTitleShare,
           titleBottom + gap + headline + gap + controls + gap <= max(foot, minHeight) {
            let h = max(foot, minHeight)
            height = h
            headlineY = titleBottom + gap
            controlsY = h - gap - controls
            return
        }
        if total <= foot - gap - (titleBottom + gap) {
            // Everything fits between the lettering and the foot: together at the foot.
            let h = max(foot, minHeight)
            height = h
            headlineY = h - gap - total
            controlsY = headlineY + headline + between
        } else if headline > 0, titleTop - gap - chromeBottom >= headline {
            // The badge over the lettering (the streaming apps' grammar); the controls at the
            // foot, the stage growing under the picture only if they need it.
            let h = max(foot, titleBottom + gap + controls + gap, minHeight)
            height = h
            headlineY = titleTop - gap - headline
            controlsY = h - gap - controls
        } else {
            let h = max(foot, titleBottom + gap + total + gap, minHeight)
            height = h
            headlineY = h - gap - total
            controlsY = headlineY + headline + between
        }
    }
}

/// Places the lockup's two groups where their `PosterStage` says.
struct PosterLockupLayout: Layout {
    let stage: PosterStage

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: proposal.width ?? ThemeMetrics.windowWidth, height: stage.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let ys = [stage.headlineY, stage.controlsY]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            subviews[index].place(at: CGPoint(x: bounds.minX, y: bounds.minY + ys[index]),
                                  anchor: .topLeading,
                                  proposal: ProposedViewSize(width: bounds.width, height: size.height))
        }
    }
}

// MARK: - The pull-down

/// The pull-down as art: the picture scales from its FOOT by exactly the pull, so its top edge
/// stays at the screen's top (the stretchy header) — Today's billboard and the show page's. One
/// transform; reads the offset here only, so a scroll frame re-runs this modifier and nothing else.
struct PullStretch: ViewModifier {
    let scroll: ScrollOffset?
    let height: CGFloat

    func body(content: Content) -> some View {
        let stretch = scroll?.stretch ?? 0
        content.scaleEffect(height > 0 ? (height + stretch) / height : 1, anchor: .bottom)
    }
}

/// Holds a layer at the screen's top through a pull-down (the hero's top veil over a stretched
/// picture): the content travels down with the pull, this travels back up by the same amount.
struct HoldsThroughPull: ViewModifier {
    let scroll: ScrollOffset?

    func body(content: Content) -> some View {
        content.offset(y: -(scroll?.stretch ?? 0))
    }
}

// MARK: - Leaving under the bar

/// A billboard's copy LEAVES as it passes under the bar instead of ghosting through it. The
/// hardened bar is 0.74 canvas over the blur by rule — it dims 15-pt white type, it does not
/// remove it — so at the foot of Today the episode line read through the wordmark at 2:1, the
/// season bar ran out of the full stop like a strike-through and a live capsule sat half inside
/// the band looking disabled (review i2). The copy starts to fade once its top edge is a beat
/// below the band and is gone by the time its middle reaches it — the name meets the docked
/// title in the bar as a handover, not a double exposure.
///
/// The opacity is a `visualEffect` — geometry read at render time, no body invalidated per frame
/// (the scroll-offset rule); only the hit-test flip is state, so a capsule that has faded out
/// cannot be pressed through the bar.
struct FadesUnderBar: ViewModifier {
    /// The bar's bottom edge, in global coordinates.
    let band: CGFloat
    /// How far below the band the fade begins.
    var lead: CGFloat = 24
    @State private var gone = false

    func body(content: Content) -> some View {
        let band = self.band, lead = self.lead
        content
            .visualEffect { effect, proxy in
                effect.opacity(Self.opacity(proxy.frame(in: .global), band: band, lead: lead))
            }
            .allowsHitTesting(!gone)
            .onGeometryChange(for: Bool.self) {
                Self.opacity($0.frame(in: .global), band: band, lead: lead) < 0.15
            } action: { gone = $0 }
    }

    nonisolated static func opacity(_ frame: CGRect, band: CGFloat, lead: CGFloat) -> Double {
        let start = band + lead
        let end = band - frame.height * 0.5
        guard start > end else { return frame.minY >= start ? 1 : 0 }
        let t = min(1, max(0, (frame.minY - end) / (start - end)))
        return Double(t * t * (3 - 2 * t))
    }
}

extension View {
    /// `FadesUnderBar` where a band is given; the view unchanged where it is not. `lead` starts
    /// the fade that far below the band — a small thing that belongs to a billboard (the deck's
    /// dots) leaves with it rather than by its own edge (review i4: they hung under the wordmark).
    @ViewBuilder func fadesUnderBar(_ band: CGFloat?, lead: CGFloat = 24) -> some View {
        if let band { modifier(FadesUnderBar(band: band, lead: lead)) } else { self }
    }
}
