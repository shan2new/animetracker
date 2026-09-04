package com.anitrack.app.ui.control

import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import com.anitrack.app.design.PreviouslyMaterialBridge
import com.anitrack.app.design.ThemeColor

/**
 * **The** switch. One recipe, one owner.
 *
 * The six-colour `SwitchDefaults.colors(...)` block below was written out byte-identically in three
 * places — `ui/list/GroupedList.kt`'s `RowSwitch`, `ui/profile/Settings.kt`'s `PreviouslySwitch` and
 * an inline `Switch` on the season screen's reveal row — and two of the three carried the comment
 * "the switch, and the only material3 component this file draws", which had stopped being true of
 * any of them. There was no switch primitive, so the next colour change had to be made in three
 * places or the app shipped two switch tints.
 *
 * `Switch` is one of the six material3 components this app is allowed, and it is wrapped in
 * [PreviouslyMaterialBridge] because a material3 component reads its colours from
 * `MaterialTheme.colorScheme`, and `MaterialTheme` with no scheme silently defaults to
 * `lightColorScheme()` — in a dark-only app that is not a tint error, it is a white slab.
 *
 * **`onCheckedChange = null` is load-bearing, and this component takes no handler at all.** The ROW
 * owns the gesture and the semantics; the switch itself must be inert, or the row would carry two
 * targets and announce twice. It also keeps material3's own 48-dp interactive inflation off, which
 * is the Android form of iOS's `.fixedSize()` — *"without it the row's layout stretched the track to
 * ~61×29 against the native 51×31 and rendered the knob as a rounded pill instead of a circle."*
 *
 * **Amber is legal here.** A switch reports STATE, which is one of amber's two legal readings, and
 * the ink on the amber track is [ThemeColor.onAccent] — so no amber *word* is drawn.
 */
@Composable
fun PreviouslySwitch(checked: Boolean, modifier: Modifier = Modifier) {
    PreviouslyMaterialBridge {
        Switch(
            checked = checked,
            onCheckedChange = null,
            modifier = modifier,
            colors = SwitchDefaults.colors(
                checkedThumbColor = ThemeColor.onAccent,
                checkedTrackColor = ThemeColor.accent,
                checkedBorderColor = Color.Transparent,
                uncheckedThumbColor = ThemeColor.textSecondary,
                uncheckedTrackColor = ThemeColor.surfaceRaised,
                uncheckedBorderColor = ThemeColor.stroke,
            ),
        )
    }
}
