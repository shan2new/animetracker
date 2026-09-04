package com.anitrack.app.ui.shell

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.isTraversalGroup
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import com.anitrack.app.design.LocalControlInk
import com.anitrack.app.design.PreviouslyIcons
import com.anitrack.app.design.ProvideControlInk
import com.anitrack.app.design.ThemeColor
import com.anitrack.app.design.ThemeMetrics
import com.anitrack.app.design.ThemeSpace
import com.anitrack.app.design.ThemeType
import com.anitrack.app.design.rememberSymbol
import com.anitrack.app.ui.control.PressStyle

/*
 * THE TAB BAR — the bar half of `MainTabView` in `ios/Sources/App/RootView.swift`.
 *
 * Two rules, and neither is cosmetic.
 *
 * 1. **THE TINT CHAIN, WHICH IS THREE LAYERS ON PURPOSE.** The app root is
 *    `ThemeColor.interactive`, so system chrome — back chevrons, dialog buttons, a search field's
 *    Cancel and its caret — draws in ink. This bar re-provides `ThemeColor.accent`, because *"the
 *    bar's selected item is state, so it alone is amber"*. Each tab's navigation host then
 *    re-provides `interactive` again, *"so the amber never reaches a back button or an alert"*.
 *    Amber is never an ACTION colour; a selected tab is not an action, it is where you are.
 *
 * 2. **NO RIPPLE, ANYWHERE.** `NavigationBarItem` constructs its own indication with no parameter
 *    to null it, and paints a `secondaryContainer` indicator pill behind the selected icon — a
 *    Material shape nobody in this design chose. The items are therefore app-drawn.
 *
 * `NavigationBar` itself is not used as the chassis either, and that IS a deviation from PLAN §3.1's
 * allowed-component list, taken deliberately: every service it offers here would be overridden —
 * its container colour (the bottom scroll-edge chrome already paints 180 dp of opaque canvas behind
 * this bar), its tonal elevation (0), its window insets, and its fixed 80-dp height. That last one
 * is the reason: `ThemeMetrics.bottomChromeHeight` is documented as "the bar's own height" and the
 * 64-dp ramp above it is sized to exactly that, so an 80-dp bar would put the ramp 16 dp inside its
 * own bar for no reason a reader could name. A `Row` at the token's height, plus the navigation-bar
 * inset, is the whole chassis.
 *
 * The bar is STATIC. iOS's `tabBarMinimizeBehavior(.onScrollDown)` is an iOS 26 flourish that is
 * already a no-op on the iOS 18 floor this port targets, and a hand-rolled `NestedScrollConnection`
 * version is a different component with different physics (PLAN D10).
 */

/**
 * The four tabs.
 *
 * Drawn OVER the content, never insetting it: every screen adds its own bottom clearance with
 * `tabBarContentPadding()`, and the bottom scroll-edge chrome over-draws past the layout's edge to
 * put opaque canvas beneath this bar and across the gesture strip. A `Scaffold` bottom bar would
 * inset the content instead, and the ramp would then stop 76 dp short of where it has to reach.
 */
@Composable
fun PreviouslyTabBar(
    selected: AppTab,
    onSelect: (AppTab) -> Unit,
    modifier: Modifier = Modifier,
) {
    ProvideControlInk(ThemeColor.accent) {
        Row(
            modifier = modifier
                .fillMaxWidth()
                // Transparent: the bottom chrome under it is already opaque canvas. A colour here
                // would be a second, slightly different black over the first.
                .background(Color.Transparent)
                // The system inset belongs to the BAR, never to the ramp above it — folding it into
                // the ramp would grow the ramp on a 3-button device and shrink it on a gesture one.
                .windowInsetsPadding(WindowInsets.navigationBars)
                .height(ThemeMetrics.bottomChromeHeight)
                .semantics {
                    isTraversalGroup = true
                    contentDescription = ShellCopy.tabBar
                },
            verticalAlignment = Alignment.CenterVertically,
        ) {
            for (tab in AppTab.entries) {
                TabItem(
                    tab = tab,
                    selected = tab == selected,
                    onSelect = { onSelect(tab) },
                )
            }
        }
    }
}

@Composable
private fun RowScope.TabItem(
    tab: AppTab,
    selected: Boolean,
    onSelect: () -> Unit,
) {
    // Amber is STATE here — where you are — and it is the one place in the app where a tinted glyph
    // and word are not an invitation to press something.
    val ink = if (selected) LocalControlInk.current else ThemeColor.textSecondary
    val interaction = remember { MutableInteractionSource() }

    Column(
        modifier = Modifier
            .weight(1f)
            .selectable(
                selected = selected,
                interactionSource = interaction,
                // The app's press language is part of its identity; a ripple is not in it, and a
                // second hand-rolled spelling of the same press is not either.
                indication = PressStyle.control,
                role = Role.Tab,
                onClick = onSelect,
            ),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        // Deliberately not material3's `Icon`: it reads `LocalContentColor` from a Material theme
        // this app never installs — an omitted tint would be `Color.Black` on the #09090B canvas —
        // and no screen may see an M3 type. `Image` at the vector's own box, because these glyphs
        // carry their optical padding inside it (see [tabIcon]); the `materialGlyphBox` ratio is
        // for a symbol drawn at an iOS POINT size, which is not what a tab glyph is.
        //
        // Decorative: the label underneath says the word, and `Role.Tab` says what it is.
        Image(
            imageVector = tabIcon(tab),
            contentDescription = null,
            colorFilter = ColorFilter.tint(ink),
        )
        BasicText(
            text = tab.label,
            style = (if (selected) ThemeType.tabLabelSelected else ThemeType.tabLabel)
                .copy(color = ink, textAlign = TextAlign.Center),
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.padding(top = ThemeSpace.x0_5),
        )
    }
}

/**
 * Four of the five glyphs are the app's own artwork (Hugeicons line set, ported as `ImageVector`s
 * because the source SVGs use a negative viewport origin); the fifth is the Material Symbol
 * `search`, because the Discover tab is named Search.
 *
 * No size is passed: each vector carries its own 24-dp box, and the box is where the artwork's
 * optical padding lives. Re-cropping it to get bigger ink would delete that padding.
 */
@Composable
private fun tabIcon(tab: AppTab): ImageVector = when (tab) {
    AppTab.TODAY -> PreviouslyIcons.TabToday
    AppTab.SCHEDULE -> PreviouslyIcons.TabSchedule
    AppTab.LIBRARY -> PreviouslyIcons.TabLibrary
    AppTab.DISCOVER -> rememberSymbol(PreviouslyIcons.Search)
}
