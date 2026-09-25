import SwiftUI

// iOS 26 chrome, each gated behind `if #available(iOS 26.0, *)` with a graceful fallback so the
// project compiles and runs on iOS 18 too. Two families live here: Liquid Glass (with an
// `.ultraThinMaterial` fallback) and the scroll-edge/tab-bar effects below — and one text shim,
// the reading line at the foot.
//
// Glass is applied ONLY to the navigation/functional chrome (tab bar, toolbars, sheet headers,
// floating action buttons, the "mark caught up" buttons, chips) — never stacked on poster/content
// cards. Adjacent glass elements should be wrapped in a GlassEffectContainer by the caller.

extension View {
    /// Glass background clipped to a shape, for chrome surfaces (chips, header bars, callouts).
    @ViewBuilder
    func glassChrome(in shape: some Shape, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            if interactive {
                self.glassEffect(.regular.interactive(), in: shape)
            } else {
                self.glassEffect(.regular, in: shape)
            }
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }

}

// `GlassCircleButton`, `glassTinted`, `GlassGroup` and the `buttonStyleGlass` pair were deleted
// in the cohesion pass (30 Aug): zero call sites each. `chromeGlass` (Primitives.swift) is the
// one sanctioned entry to glass — it routes through `glassChrome` above and carries the Reduce
// Transparency fallback.

// MARK: - Scroll edge and tab bar effects (iOS 26)

/// Which edges a scroll-edge shim addresses.
///
/// Ours rather than Apple's on purpose: the `for:` parameter of `scrollEdgeEffectHidden` and
/// `scrollEdgeEffectStyle` takes an iOS 26 type, and a function signature that names one cannot
/// compile against an iOS 18 deployment target — even if every call is inside an availability
/// check. The mapping onto Apple's type happens in the bodies below, where the symbol is legal.
enum ChromeEdge {
    case all, top, bottom
}

extension View {
    /// Suppresses the system scroll-edge effect.
    ///
    /// **`.top` is the only edge a screen here passes** (8 Sep). The top band is OURS because it is
    /// a bar — opaque canvas through the whole bar's height, a docked title riding on it — which no
    /// blur can stand in for. The bottom has no system effect to suppress: the app's bar
    /// (`AppTabBar`, 25 Sep) is a plain safe-area inset, not a system bar, and content never passes
    /// under it. A PUSHED screen hides nothing — the system owns its navigation bar's edge.
    ///
    /// Below iOS 26 there is no system effect to suppress and the shim is a plain no-op — which is
    /// exact, not a degradation.
    @ViewBuilder
    func chromeScrollEdgeHidden(_ edge: ChromeEdge) -> some View {
        if #available(iOS 26.0, *) {
            switch edge {
            case .all: scrollEdgeEffectHidden(true, for: .all)
            case .top: scrollEdgeEffectHidden(true, for: .top)
            case .bottom: scrollEdgeEffectHidden(true, for: .bottom)
            }
        } else {
            self
        }
    }

    /// The `.hard` scroll-edge style, for art-backed content whose eyebrow a soft blur would cut
    /// through — see the M1 note at the top of `ProfileView` ("SETTINGS" bisected through its
    /// x-height). iOS 18 has no scroll-edge effect at all, so nothing needs hardening there.
    @ViewBuilder
    func chromeScrollEdgeHard(_ edge: ChromeEdge) -> some View {
        if #available(iOS 26.0, *) {
            switch edge {
            case .all: scrollEdgeEffectStyle(.hard, for: .all)
            case .top: scrollEdgeEffectStyle(.hard, for: .top)
            case .bottom: scrollEdgeEffectStyle(.hard, for: .bottom)
            }
        } else {
            self
        }
    }
}

// MARK: - Toolbar and navigation bar (iOS 26)

extension ToolbarContent {
    /// Drops iOS 26's shared glass capsule from behind a single toolbar item.
    ///
    /// Wanted wherever the item is a bare word or a bare glyph — a "Done", a plain text action, a
    /// refresh spinner — because the capsule renders a lit plate around something that was meant to
    /// read as text (rgb(26,27,29) behind a word on a rgb(13,14,17) sheet, in the case that found
    /// this). iOS 18 draws no shared background in the first place, so below 26 there is nothing to
    /// hide and the shim returns the item untouched.
    @ToolbarContentBuilder
    func chromeSharedBackgroundHidden() -> some ToolbarContent {
        if #available(iOS 26.0, *) {
            self.sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}

extension View {
    /// The navigation bar's second line (iOS 26). Below 26 the bar has no subtitle slot, so the
    /// line is dropped rather than faked — a subtitle crammed into the title would wrap a two-line
    /// string into an inline bar, which is worse than not having it.
    @ViewBuilder
    func chromeNavigationSubtitle(_ subtitle: String) -> some View {
        if #available(iOS 26.0, *) {
            navigationSubtitle(subtitle)
        } else {
            self
        }
    }
}

// MARK: - The reading line (iOS 26)

extension View {
    /// Lines `factor` × the point size apart, whatever the fonts' own ascent and descent: X's fixed
    /// rhythm for a post's words (`FeedPostLayout.lineHeight`, 15 on 20). SwiftUI's own line follows
    /// the fonts, and the system opens SF's for a tall-script language anywhere in the preferred list
    /// — the QA sim's en-IN + hi-IN set 15 on 23, English alone 15 on 20 (bundled Outfit never
    /// moved). Below 26 Text cannot hold a line height, so the words keep SwiftUI's line — X's own
    /// with English alone — opened by `below26` points.
    @ViewBuilder
    func readingLines(_ factor: CGFloat, below26 spacing: CGFloat = 0) -> some View {
        if #available(iOS 26.0, *) {
            lineHeight(.multiple(factor: factor))
        } else {
            lineSpacing(spacing)
        }
    }
}
