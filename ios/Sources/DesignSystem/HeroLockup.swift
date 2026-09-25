import SwiftUI

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

