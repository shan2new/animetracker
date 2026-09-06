import SwiftUI

// iOS 26 chrome, each gated behind `if #available(iOS 26.0, *)` with a graceful fallback so the
// project compiles and runs on iOS 18 too. Two families live here: Liquid Glass (with an
// `.ultraThinMaterial` fallback) and the scroll-edge/tab-bar effects below.
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
    /// Every screen here draws its own veil instead (`scrollEdgeChromeBody`), so the system effect
    /// is always unwanted where this is called. Below iOS 26 there is no system effect to
    /// suppress and the shim is a plain no-op — which is exact, not a degradation.
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

    /// The tab bar getting out of the way of a long read on a downward scroll, the way Music's and
    /// Photos' do. There is no iOS 18 equivalent; the bar stays put, which is what an iOS 18 user
    /// expects of a tab bar anyway — so this is a missing flourish, not a broken layout.
    @ViewBuilder
    func chromeTabBarMinimizeOnScroll() -> some View {
        if #available(iOS 26.0, *) {
            tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
    }

    /// The tab bar's bottom accessory (iOS 26) — the lane Music's mini player lives in, which
    /// collapses into the bar when it minimises. Below 26 there is no such lane; the caller keeps
    /// whatever it draws instead (the receipt spike's bar direction, 5 Sep).
    @ViewBuilder
    func chromeBottomAccessory<A: View>(isEnabled: Bool, @ViewBuilder _ accessory: @escaping () -> A) -> some View {
        if #available(iOS 26.1, *) {
            // `isEnabled:` (26.1) — a conditionally EMPTY accessory still reserves its lane
            // (Apple Developer Forums thread 803428); the enabled flag is what removes it.
            tabViewBottomAccessory(isEnabled: isEnabled) { accessory() }
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

