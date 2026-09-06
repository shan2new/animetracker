@file:OptIn(ExperimentalFoundationApi::class)

package com.anitrack.app.ui.discover

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.ExperimentalAnimationApi
import androidx.compose.animation.SizeTransform
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.material3.DropdownMenu
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.ColorProducer
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.PointerEventTimeoutCancellationException
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.animation.core.VisibilityThreshold
import com.anitrack.app.AppModel
import com.anitrack.app.MediaFilter
import com.anitrack.app.data.UndoState
import com.anitrack.app.design.ContinuousCornerShape
import com.anitrack.app.design.MaterialSymbol
import com.anitrack.app.design.LocalControlInk
import com.anitrack.app.design.LocalReduceMotion
import com.anitrack.app.design.PosterSize
import com.anitrack.app.design.PreviouslyIcons
import com.anitrack.app.design.PreviouslyMaterialBridge
import com.anitrack.app.design.ShadowToken
import com.anitrack.app.design.ThemeColor
import com.anitrack.app.design.ThemeMetrics
import com.anitrack.app.design.ThemeMotion
import com.anitrack.app.design.ThemeRadius
import com.anitrack.app.design.ThemeSpace
import com.anitrack.app.design.ThemeType
import com.anitrack.app.design.rememberSymbol
import com.anitrack.app.ui.control.ChipButton
import com.anitrack.app.ui.control.InlineLink
import com.anitrack.app.ui.control.InlineLinkButton
import com.anitrack.app.ui.control.PressStyle
import com.anitrack.app.ui.control.SymbolIcon
import com.anitrack.app.ui.control.minimumTapTarget
import com.anitrack.app.ui.isAccessibilityTextSize
import com.anitrack.app.ui.negativePadding
import com.anitrack.model.Franchise
import com.anitrack.model.FranchiseSummary
import com.anitrack.model.WatchStatus
import com.anitrack.model.behind
import com.anitrack.model.copy.Copy
import com.anitrack.model.effectiveStatus
import com.anitrack.model.releasingPart
import com.anitrack.model.timeAnchor

// =====================================================================================
// SEARCH'S OWN COMPONENTS — the port of
// `ios/Sources/Features/Discover/SearchComponents.swift`, plus the two rows `DiscoverView`
// declares inline (the bare-term row and the notification primer).
//
// Two app-wide rules govern almost everything in this file, and a build that breaks either
// is wrong even if it compiles:
//
//   1. **Amber is never an action colour.** The ONLY amber here is the owned tick, its soft
//      fill and its ring — ownership is STATE. The `+` that adds a show is `textPrimary`
//      ink, "Turn on" and "Clear" are `interactive`. This screen had that right before the
//      rest of the app did.
//
//   2. **One control, two states, one 44-dp frame, one visual width, on every surface.**
//      The shipped iOS control measured ~25 pt over artwork, 55×43 as a bordered `Add` in a
//      row, and VANISHED in the added state — replaced by a bare grey checkmark with no
//      chrome, no target and no way to undo, so the trailing column's edge was ragged down
//      the list and the most important control on the screen was its quietest object.
//
// `FactLine` (the view) and `RankGutter` are **deliberately not ported**: neither reaches
// the screen in the shipped build. Only `FactLine.separator` survives, below.
// =====================================================================================

/**
 * The one separator every joined fact line on this screen uses — U+00B7 with a plain space either
 * side — so a row and a card never punctuate differently.
 *
 * The `FactLine` VIEW is dead code on iOS (`DiscoverView.cardMeta`, its only constructor, has no
 * call sites) and is not ported. Its rule is worth keeping on record even so: **drop a whole fact
 * rather than print a fragment** — `truncationMode(.tail)` on a joined metadata string is how
 * "2026 ·" and "2018 · 11 parts · Friday…" reached the screen. `RankGutter` likewise has no call
 * sites at all; the over-art numeral is gone and the ranks moved to the caption and then off it.
 */
object FactLine {
    const val separator: String = " · "
}

// -------------------------------------------------------------------------------------
// Geometry
//
// Component-local, as the design system's primitives are: a SCREEN spends no literal, and a
// primitive is where the literals live.
// -------------------------------------------------------------------------------------

/** The over-art control's visible disc. The TARGET around it is [minimumTapTarget]. */
private val overArtDisc = 26.dp

/**
 * The outset that puts the visible disc 8 dp inside the artwork's corner rather than straddling
 * its edge.
 *
 * The 44-dp target is centred on the 26-dp disc, so there are 9 dp of slack per side; pushing the
 * target 1 dp outward lands the disc at 8. (iOS spells the same thing `.padding(-1)`.)
 */
private val overArtOutset = 1.dp

/** The glyph over art, at its iOS text-style size (`.caption`, 12). */
private val addGlyphOverArt = 12.dp

/** The glyph in a row or card's trailing column (`.subheadline`, 15). */
private val addGlyphInRow = 15.dp

/**
 * The owned ring's alpha, by placement.
 *
 * They differ because on a surface the `accentSoft` fill already carries the state; over art the
 * fill is under a 72 % scrim and the ring has to do more of the work.
 */
private const val ownedRingOverArt = 0.45f
private const val ownedRingInRow = 0.35f

/** The recent-term row's circular tile — the row slot's width, so the rows share one left edge. */
private val termTile = PosterSize.Row.width

/** The magnifier inside it: `.body` weight semibold on iOS. */
private val termGlyph = 17.dp

/** The fill-the-field arrow, at its iOS point size. */
private val termTrailingGlyph = 13.dp

/**
 * The trailing column, verbatim [com.anitrack.app.ui.row.MediaRow]'s chevron geometry, so the term
 * rows share the media rows' x. A Material Symbol's ink fills ~20 of its 24-dp box, so the
 * metric-matched box for a 13-pt SF glyph is 18 dp.
 */
private val termTrailingColumn = 18.dp

/** The term row's own height floor: art-free, so it is shorter than a catalogue row. */
private val termRowHeight = 60.dp

/** The separator is a hairline, not a rule: one device-independent point. */
private val separatorHeight = ThemeMetrics.hairline

/** The primer's bell, and the fixed column it sits in. */
private val primerGlyph = 20.dp
private val primerGlyphColumn = 28.dp

/** The primer's dismiss disc. The TARGET around it is [minimumTapTarget]. */
private val dismissDisc = 28.dp

/** The × inside it, at its iOS point size (`.caption2`, 11, bold). */
private val dismissGlyph = 11.dp

/**
 * The pull-back that keeps an inline link off a row's height.
 *
 * [InlineLinkButton] holds its own 44-dp target with 14 dp of vertical padding; without taking that
 * back the answer sets the primer row's height instead of sitting on its baseline.
 */
private val inlineActionOverhang = InlineLink.sideOverhang

// -------------------------------------------------------------------------------------
// The add control
// -------------------------------------------------------------------------------------

/**
 * Where an [AddControl] is sitting, which is the only thing that decides its shape.
 *
 * **These are the only two, they are chosen by what is underneath the control, and neither ever
 * appears in the other's context** — including at accessibility sizes, where the shipped iOS build
 * grew the card's square into a full-width capsule and so drew one verb three ways.
 */
enum class AddControlPlacement {
    /** ON artwork: a 26-dp disc inset into the poster's corner. */
    OverArt,

    /** In a row or card's trailing column: a 44-dp rounded square. */
    Row,
}

/**
 * **The primary action of the whole screen**, in both of its states.
 *
 * Tap adds; long-press shows the one verb the tap performs, so the two states are one control with
 * one gesture grammar. **Owned does not remove on tap** — a tick that unsubscribed on contact was
 * the only destructive one-tap in the app, 44 dp from the add it replaced, and it never said which
 * shelf the show was on. Owned taps open the menu.
 *
 * ### Ownership is amber; adding is not
 *
 * Added is drawn in `accent`, unadded in `textPrimary`. The two states were previously separated by
 * the glyph's *colour alone* inside identical grey chrome, so "in your library" and "not in your
 * library" both read as live grey buttons. And **unadded is a stroke, not a fill**: four identical
 * filled grey tiles running down the right edge of the one screen whose job is showing artwork made
 * the trailing column the heaviest thing in every row. The fill is what *ownership* looks like.
 *
 * The over-art disc is scrim-filled in **both** states so the reading never depends on what the
 * poster happens to be doing behind it (measured 7.0:1 / 16.6:1 / 14.8:1 against the brightest
 * posters in the chart).
 *
 * @param onAdd the screen's own `add(item)` — the optimistic write, the recents record and the
 *   notification primer's arming. This component performs no write and fires no haptic; the SCREEN
 *   owns the transaction, because only the screen knows what the transaction is.
 */
@Composable
fun AddControl(
    item: FranchiseSummary,
    placement: AddControlPlacement,
    appModel: AppModel,
    onAdd: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val owned = appModel.isInLibrary(item.id)
    val franchise = appModel.franchise(item.id)
    var expanded by remember { mutableStateOf(false) }
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()

    Box(modifier) {
        Box(
            modifier = Modifier
                .combinedClickable(
                    interactionSource = interaction,
                    // A round control gets compression only — no rounded-rect wash behind a circle.
                    indication = when (placement) {
                        AddControlPlacement.OverArt -> PressStyle.mark
                        AddControlPlacement.Row -> PressStyle.control
                    },
                    role = Role.Button,
                    onClickLabel = if (owned) Copy.Search.ownedHint else Copy.Search.addHint,
                    onLongClickLabel = if (owned) null else Copy.Search.addToLibrary,
                    // Compose fires its own `LONG_PRESS` constant on a long click by default. Every
                    // haptic in this app goes through `FeedbackCoordinator`, at most one per
                    // transaction — and opening a menu is not a transaction — so the platform's is
                    // switched off rather than allowed to buzz beside the add's own `.success`.
                    hapticFeedbackEnabled = false,
                    // Owned: tap opens the menu, and there is no long-press — the same gesture
                    // twice is not a second affordance. Unowned: tap acts, long-press shows the
                    // menu (iOS `Menu(content:label:primaryAction:)`).
                    onLongClick = if (owned) null else ({ expanded = true }),
                    onClick = { if (owned) expanded = true else onAdd() },
                )
                // Declared on the control itself so a MediaRow's own merge cannot absorb it: a
                // merging node inside a merging node stays its own node. iOS ships the COMBINED
                // behaviour here (the row and its control are one element); the Android component
                // library requires the trailing control to stay separately reachable, and this is
                // that rule.
                .semantics(mergeDescendants = true) {
                    contentDescription = item.title
                    // Not `selected`: the amber tick is ownership, not a selection state.
                    stateDescription =
                        if (owned) Copy.Search.inLibrary else Copy.Search.notInLibrary
                }
                .size(minimumTapTarget),
            contentAlignment = Alignment.Center,
        ) {
            when (placement) {
                AddControlPlacement.OverArt -> OverArtShape(owned)
                AddControlPlacement.Row -> RowShape(owned = owned, pressed = pressed)
            }
        }

        AddMenu(
            expanded = expanded,
            onDismiss = { expanded = false },
            owned = owned,
            item = item,
            franchise = franchise,
            appModel = appModel,
            onAdd = onAdd,
        )
    }
}

/** The 26-dp disc. Scrim-filled in both states; the owned state warms the fill underneath it. */
@Composable
private fun OverArtShape(owned: Boolean) {
    Box(
        modifier = Modifier
            .size(overArtDisc)
            // Order is load-bearing and matches SwiftUI's stacked `.background`s: the warm fill is
            // BEHIND the scrim, so the added state reads as a warmer black rather than as a
            // different control.
            .background(if (owned) ThemeColor.accentSoft else Color.Transparent, CircleShape)
            .background(ThemeColor.scrimStrong, CircleShape)
            // `border` insets in Compose, which is SwiftUI's `strokeBorder`; a centred stroke on a
            // circle renders as a soft smear outside the shape.
            .border(
                width = ThemeMetrics.hairline,
                color = if (owned) {
                    ThemeColor.accent.copy(alpha = ownedRingOverArt)
                } else {
                    ThemeColor.posterEdge
                },
                shape = CircleShape,
            ),
        contentAlignment = Alignment.Center,
    ) {
        AddGlyph(owned = owned, glyph = addGlyphOverArt)
    }
}

/** The 44-dp rounded square. The target IS the visual here, so nothing is nested inside it. */
@Composable
private fun RowShape(owned: Boolean, pressed: Boolean) {
    val shape = ContinuousCornerShape(ThemeRadius.compactControl)
    Box(
        modifier = Modifier
            .size(minimumTapTarget)
            .background(
                color = when {
                    pressed -> ThemeColor.surfacePressed
                    owned -> ThemeColor.accentSoft
                    else -> Color.Transparent
                },
                shape = shape,
            )
            .border(
                width = ThemeMetrics.hairline,
                color = if (owned) {
                    ThemeColor.accent.copy(alpha = ownedRingInRow)
                } else {
                    ThemeColor.stroke
                },
                shape = shape,
            ),
        contentAlignment = Alignment.Center,
    ) {
        AddGlyph(owned = owned, glyph = addGlyphInRow)
    }
}

/**
 * `plus` ⇄ `checkmark`, replaced rather than re-created.
 *
 * iOS gets this from `.contentTransition(.symbolEffect(.replace.downUp))` on one `Image` whose
 * identity survives the flip. `AnimatedContent` with a vertical slide plus a fade is the Android
 * spelling; `SizeTransform(clip = false)` keeps the outgoing glyph from being cut off as it leaves,
 * and the two glyphs are the same box so nothing actually resizes.
 */
@OptIn(ExperimentalAnimationApi::class)
@Composable
private fun AddGlyph(owned: Boolean, glyph: Dp) {
    val reduceMotion = LocalReduceMotion.current
    AnimatedContent(
        targetState = owned,
        transitionSpec = {
            if (reduceMotion) {
                (fadeIn(ThemeMotion.uiReduced()) togetherWith fadeOut(ThemeMotion.uiReduced()))
                    .using(SizeTransform(clip = false))
            } else {
                val rise = ThemeMotion.uiMicro<IntOffset>(IntOffset.VisibilityThreshold)
                (
                    slideInVertically(rise) { it } + fadeIn(ThemeMotion.uiMicro()) togetherWith
                        slideOutVertically(rise) { -it } + fadeOut(ThemeMotion.uiMicro())
                    ).using(SizeTransform(clip = false))
            }
        },
        label = "addGlyph",
    ) { isOwned ->
        SymbolIcon(
            symbol = if (isOwned) PreviouslyIcons.Check else PreviouslyIcons.Add,
            tint = if (isOwned) ThemeColor.accent else ThemeColor.textPrimary,
            glyph = glyph,
        )
    }
}

/** The menu behind the control, in whichever of its three shapes applies. */
@Composable
private fun AddMenu(
    expanded: Boolean,
    onDismiss: () -> Unit,
    owned: Boolean,
    item: FranchiseSummary,
    franchise: Franchise?,
    appModel: AppModel,
    onAdd: () -> Unit,
) {
    PreviouslyMenu(expanded = expanded, onDismiss = onDismiss) {
        when {
            // The long-press shows the one verb the tap performs.
            !owned -> MenuCommand(
                label = Copy.Search.addToLibrary,
                symbol = PreviouslyIcons.Add,
                onClick = {
                    onDismiss()
                    onAdd()
                },
            )

            franchise != null -> FranchiseMenuItems(
                franchise = franchise,
                appModel = appModel,
                onDismiss = onDismiss,
            )

            // The one remove in the app with no way back: a show added seconds ago and not yet in
            // the loaded library has no `Franchise` for `removeWithUndo`, so the receipt is built
            // here — same toast, same six seconds, same Undo.
            else -> MenuCommand(
                label = Copy.Action.removeFromLibrary,
                symbol = PreviouslyIcons.Delete,
                destructive = true,
                onClick = {
                    onDismiss()
                    appModel.removeFromLibrary(item.id)
                    appModel.presentUndo(
                        UndoState(
                            franchiseId = item.id,
                            title = item.title,
                            customMessage = Copy.Toast.removed,
                            undoAction = {
                                appModel.addToLibrary(
                                    franchiseId = item.id,
                                    title = item.title,
                                    isReleasing = item.isReleasing,
                                    source = item.source,
                                )
                            },
                        ),
                    )
                },
            )
        }
    }
}

/**
 * The owned menu's contents, shared by the add control and the row/card long-press.
 *
 * **An owned show's menu is the whole vocabulary Library's own rows use**: catch up if there is a
 * backlog, the five shelves, and the removal. The tick alone said "in your library" and never which
 * of five lists it was on.
 */
@Composable
private fun ColumnScope.FranchiseMenuItems(
    franchise: Franchise,
    appModel: AppModel,
    onDismiss: () -> Unit,
) {
    // Freshness is derived from `airings`, never from the catalogue's counts — `behind` is the
    // anchor-aware reading, and `nowMinute` is what this screen observes.
    val behind = franchise.releasingPart
        ?.behind(appModel.nowMinute, franchise.timeAnchor)
        ?: 0
    if (behind > 0) {
        MenuCommand(
            label = Copy.Action.markAll(behind),
            symbol = PreviouslyIcons.Pending.PlaylistAdd,
            onClick = {
                onDismiss()
                appModel.markCaughtUp(franchise.id)
            },
        )
    }

    val current = franchise.effectiveStatus
    StatusMenuOrder.forEach { status ->
        MenuCommand(
            label = Copy.statusLabel(status.wire),
            // The current shelf shows a tick instead of its own glyph.
            symbol = if (status == current) PreviouslyIcons.Check else statusSymbol(status),
            onClick = {
                onDismiss()
                appModel.setStatus(franchiseId = franchise.id, status = status)
            },
        )
    }

    MenuDivider()

    MenuCommand(
        label = Copy.Action.removeFromLibrary,
        symbol = PreviouslyIcons.Delete,
        destructive = true,
        onClick = {
            onDismiss()
            appModel.removeWithUndo(franchise)
        },
    )
}

/**
 * Display order for the status menu, independent of the enum's declaration order — the enum form of
 * `Copy.statusesInOrder`.
 */
private val StatusMenuOrder = listOf(
    WatchStatus.WATCHING,
    WatchStatus.PLANNED,
    WatchStatus.COMPLETED,
    WatchStatus.PAUSED,
    WatchStatus.DROPPED,
)

/**
 * The glyph for a shelf.
 *
 * **Divergence, recorded:** iOS draws SF `clock` for Planned. The vendored icon vocabulary has no
 * clock, and `bookmark`'s declared meaning is literally "Planned / saved for later" — so the port
 * takes the glyph whose MEANING matches rather than the one whose outline does.
 */
private fun statusSymbol(status: WatchStatus) = when (status) {
    WatchStatus.WATCHING -> PreviouslyIcons.Pending.PlayCircle
    WatchStatus.PLANNED -> PreviouslyIcons.Bookmark
    WatchStatus.COMPLETED -> PreviouslyIcons.Pending.CheckCircle
    WatchStatus.PAUSED -> PreviouslyIcons.Pending.PauseCircle
    WatchStatus.DROPPED -> PreviouslyIcons.Pending.Cancel
}

// -------------------------------------------------------------------------------------
// The menu chassis
// -------------------------------------------------------------------------------------

/**
 * The app's dropdown menu.
 *
 * `DropdownMenu` is the native answer — iOS's blurred lift-and-platter has no Android equivalent
 * and reproducing one is exactly the heavy engineering the fidelity line rules out. It is wrapped
 * in [PreviouslyMaterialBridge] so it cannot arrive wearing `lightColorScheme()`, and its rows are
 * plain `clickable` `Row`s rather than `DropdownMenuItem`s, which build their own ripple with no
 * way to turn it off.
 */
@Composable
private fun PreviouslyMenu(
    expanded: Boolean,
    onDismiss: () -> Unit,
    content: @Composable ColumnScope.() -> Unit,
) {
    PreviouslyMaterialBridge {
        DropdownMenu(
            expanded = expanded,
            onDismissRequest = onDismiss,
            // The `.floating` surface level, spelled out: an opaque ground (it covers content it
            // must never be mistaken for), a full `strokeStrong` ring, and the floating shadow.
            shape = ContinuousCornerShape(ThemeRadius.compactControl),
            containerColor = ThemeColor.surfaceFloating,
            tonalElevation = 0.dp,
            shadowElevation = ShadowToken.Floating.elevation,
            border = BorderStroke(ThemeMetrics.hairline, ThemeColor.strokeStrong),
            content = content,
        )
    }
}

/**
 * One command in a menu.
 *
 * `interactive` ink, never amber — a menu item is an action, and actions are not amber. A
 * destructive command is the one exception, and it is `destructive` red rather than accent.
 */
@Composable
private fun MenuCommand(
    label: String,
    symbol: MaterialSymbol?,
    onClick: () -> Unit,
    destructive: Boolean = false,
) {
    val ink = if (destructive) ThemeColor.destructive else LocalControlInk.current
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(
                interactionSource = null,
                indication = PressStyle.groupedRow,
                role = Role.Button,
                onClick = onClick,
            )
            .defaultMinSize(minHeight = minimumTapTarget)
            .padding(horizontal = ThemeMetrics.gutter, vertical = ThemeSpace.x2),
        horizontalArrangement = Arrangement.spacedBy(ThemeSpace.x3),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (symbol != null) SymbolIcon(symbol = symbol, tint = ink, glyph = addGlyphInRow)
        BasicText(text = label, style = ThemeType.body, color = ColorProducer { ink })
    }
}

/** The rule above a destructive command. `separatorQuiet`, like every other divider in the app. */
@Composable
private fun MenuDivider() {
    Spacer(
        Modifier
            .fillMaxWidth()
            .height(separatorHeight)
            .background(ThemeColor.separatorQuiet),
    )
}

/**
 * A long-press menu over a row or card — the port of `.franchiseQuickActions(...)` and of the
 * recents rows' `.contextMenu`.
 *
 * ### Why this screen carries its own, and what to do about it
 *
 * `ui/library/LibraryScreen.kt` has a twin (`FranchiseQuickActions` + its private
 * `longPressAction`), and there should be exactly one in the app. The reason Search does not simply
 * call it is a DATA rule rather than a layout one: that twin counts the backlog with
 * `episodesBehind`, the catalogue's hourly-cron field, while every live surface must read
 * `behind(now, anchor)` — *"a slot in the part's own `airings` list that has struck IS an aired
 * episode"*. Search's add control already reads the live count, so borrowing the calm one for the
 * long-press would put two different numbers on the same show on the same screen, one tap apart.
 *
 * **The fix is to hoist ONE of these into the control library and give it `behind(now, anchor)`**,
 * at which point this whole section deletes.
 *
 * @param enabled `false` mounts no pointer input at all; an inert long-press is better than an
 *   empty platter.
 */
@Composable
internal fun LongPressMenu(
    enabled: Boolean,
    modifier: Modifier = Modifier,
    menuContent: @Composable ColumnScope.(onDismiss: () -> Unit) -> Unit,
    content: @Composable BoxScope.() -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }
    Box(
        modifier = modifier.then(
            if (!enabled) Modifier else Modifier.longPressAction { expanded = true },
        ),
    ) {
        content()
        PreviouslyMenu(expanded = expanded, onDismiss = { expanded = false }) {
            menuContent { expanded = false }
        }
    }
}

/**
 * Long-press detection that does **not** disturb the row's own tap.
 *
 * The row owns its `clickable`, and a plain `combinedClickable` on a wrapper loses every gesture to
 * it: hit-testing reaches the innermost node first and the row consumes the press in the Main pass.
 * So this watches the **Initial** pass, which runs parent-first, times the press itself, and on a
 * long press consumes the remainder of the gesture — which the row's `clickable` reads as a
 * cancellation, so exactly one of the two fires. Movement past the touch slop abandons the attempt,
 * leaving the scroll gesture untouched.
 *
 * (The twin of `ui/library`'s own `longPressAction`, which is private to that file. One of the two
 * moves into the control library the moment anything else needs it.)
 */
private fun Modifier.longPressAction(onLongPress: () -> Unit): Modifier =
    pointerInput(onLongPress) {
        awaitEachGesture {
            val down = awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Initial)
            val slop = viewConfiguration.touchSlop
            var longPressed = false
            try {
                withTimeout(viewConfiguration.longPressTimeoutMillis) {
                    while (true) {
                        val event = awaitPointerEvent(PointerEventPass.Initial)
                        val change = event.changes.firstOrNull { it.id == down.id }
                            ?: return@withTimeout
                        if (!change.pressed) return@withTimeout
                        if ((change.position - down.position).getDistance() > slop) {
                            return@withTimeout
                        }
                    }
                }
            } catch (_: PointerEventTimeoutCancellationException) {
                longPressed = true
            }
            if (!longPressed) return@awaitEachGesture

            onLongPress()
            while (true) {
                val event = awaitPointerEvent(PointerEventPass.Initial)
                val change = event.changes.firstOrNull { it.id == down.id } ?: break
                change.consume()
                if (!change.pressed) break
            }
        }
    }

/**
 * The owned menu, as a [LongPressMenu] payload — the port of `.franchiseQuickActions(...)`.
 *
 * It is the SAME list the add control's owned state opens, from the same function, so a show cannot
 * offer one backlog count on a tap and another on a long press.
 */
@Composable
internal fun ColumnScope.FranchiseCommands(
    franchise: Franchise,
    appModel: AppModel,
    onDismiss: () -> Unit,
) {
    FranchiseMenuItems(franchise = franchise, appModel = appModel, onDismiss = onDismiss)
}

/**
 * "Remove" — the one command behind a long press on a recents row.
 *
 * A recents entry is device-local browsing history, so forgetting one is not a library write and
 * carries no Undo: the row simply leaves.
 */
@Composable
internal fun ColumnScope.RecentRemoveCommand(onRemove: () -> Unit) {
    MenuCommand(
        label = Copy.Search.removeRecent,
        symbol = PreviouslyIcons.Delete,
        destructive = true,
        onClick = onRemove,
    )
}

// -------------------------------------------------------------------------------------
// The bare-term row
// -------------------------------------------------------------------------------------

/**
 * A recent QUERY, in the two-line anatomy of the media rows around it.
 *
 * Three decisions, each recorded against what the row was:
 *
 * * **The tile is a CIRCLE in the field's own colours.** It is a search, not a poster, and a grey
 *   square beside art tiles read as a poster that failed. Neutral, *not* amber: a recent query is
 *   neither a next step nor a state, and the amber disc made a search term the warmest object in a
 *   list of real shows.
 * * **A second line** ("Search"), so the row has the same two-line anatomy as its neighbours
 *   instead of one bold word floating in a 60-dp band.
 * * **The trailing glyph is the fill-the-field arrow, not a chevron.** A chevron promises a push;
 *   this row puts the words back in the field (Safari's and YouTube's convention).
 *
 * @param onFill puts the term back in the field, which re-schedules the search through the model's
 *   own setter.
 */
@Composable
fun SearchTermRow(
    term: String,
    separator: Boolean,
    onFill: () -> Unit,
    onRemove: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val spoken = "$term, ${Copy.Search.termKind}"
    val separatorInset = termTile + ThemeMetrics.artGap

    LongPressMenu(
        enabled = true,
        modifier = modifier,
        menuContent = { dismiss ->
            RecentRemoveCommand(
                onRemove = {
                    dismiss()
                    onRemove()
                },
            )
        },
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clickable(
                    interactionSource = null,
                    // The same press language as every other row in the app: a `surfacePressed`
                    // wash at 60 % over the row plus a 0.992 compression, at the row's own radius.
                    indication = PressStyle.row(ThemeRadius.row),
                    onClickLabel = Copy.Search.termHint,
                    role = Role.Button,
                    onClick = onFill,
                )
                // One element, labelled by hand: the tile and the type line are furniture, and the
                // arrow is silent.
                .semantics(mergeDescendants = true) { contentDescription = spoken }
                .drawWithContent {
                    drawContent()
                    if (separator) {
                        val inset = separatorInset.toPx()
                        val thickness = separatorHeight.toPx()
                        val left = if (layoutDirection == LayoutDirection.Ltr) inset else 0f
                        drawRect(
                            color = ThemeColor.separatorQuiet,
                            topLeft = Offset(left, size.height - thickness),
                            size = Size(size.width - inset, thickness),
                        )
                    }
                }
                .heightIn(min = termRowHeight)
                .padding(vertical = ThemeSpace.x2),
            horizontalArrangement = Arrangement.spacedBy(ThemeMetrics.artGap),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                modifier = Modifier
                    .size(termTile)
                    .background(ThemeColor.surfaceFlat, CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                SymbolIcon(
                    symbol = PreviouslyIcons.Search,
                    tint = ThemeColor.textSecondary,
                    glyph = termGlyph,
                )
            }

            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(ThemeMetrics.titleGap),
            ) {
                BasicText(
                    text = term,
                    style = ThemeType.rowTitle.copy(color = ThemeColor.textPrimary),
                    maxLines = 1,
                )
                BasicText(
                    text = Copy.Search.termKind,
                    style = ThemeType.rowMeta.copy(color = ThemeColor.textSecondary),
                    maxLines = 1,
                )
            }

            Spacer(Modifier.width(ThemeSpace.x3))

            // The one glyph in these two files drawn to a FIXED box rather than to a point size:
            // it has to share `MediaRow`'s 18-dp chevron column so the term rows and the media rows
            // above them end on one x. No ratio is spelled here — 18 is the column, not a
            // conversion.
            Image(
                imageVector = rememberSymbol(PreviouslyIcons.RecentQuery),
                contentDescription = null,
                modifier = Modifier.size(termTrailingColumn),
                colorFilter = ColorFilter.tint(ThemeColor.textTertiary),
            )
        }
    }
}

// -------------------------------------------------------------------------------------
// The notification primer
// -------------------------------------------------------------------------------------

/**
 * "Episode alerts / Know the moment a new episode airs. / Turn on · ×"
 *
 * **The system permission dialog is never raised by an add.** The row is the ask, and it appears at
 * least a full undo window later, only if the add stuck. It was a plate with a bell in a tile, a
 * paragraph and a full-width amber capsule — a promo card from a marketing site, on a search
 * screen. It is a row on the canvas now, in the app's own row grammar: a glyph, a title, one line,
 * and the answer as a link.
 *
 * At an accessibility text size the layout flips to a column so the words take the full width and
 * the answers drop to their own line — beside two controls the sentence was wrapping one word per
 * line.
 *
 * @param onNotNow "Not now", not "No thanks": the OS raises its own prompt once, so the honest
 *   offer is a deferral, and Profile → Notifications keeps it available for good.
 */
@Composable
fun NotificationPrimerRow(
    onTurnOn: () -> Unit,
    onNotNow: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val isAX = isAccessibilityTextSize()

    val words: @Composable (Modifier) -> Unit = { slot ->
        Row(
            modifier = slot,
            horizontalArrangement = Arrangement.spacedBy(ThemeMetrics.artGap),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(Modifier.width(primerGlyphColumn), contentAlignment = Alignment.Center) {
                SymbolIcon(
                    symbol = PreviouslyIcons.NotificationsActive,
                    tint = ThemeColor.textTertiary,
                    glyph = primerGlyph,
                )
            }
            Column(verticalArrangement = Arrangement.spacedBy(ThemeMetrics.titleGap)) {
                BasicText(
                    text = Copy.Search.primerTitle,
                    style = ThemeType.rowTitle.copy(color = ThemeColor.textPrimary),
                )
                BasicText(
                    text = Copy.Search.primerBody,
                    style = ThemeType.rowMeta.copy(color = ThemeColor.textSecondary),
                )
            }
        }
    }

    val answers: @Composable () -> Unit = {
        Row(
            horizontalArrangement = Arrangement.spacedBy(ThemeSpace.x2),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            InlineLinkButton(
                label = Copy.Search.primerTurnOn,
                onClick = onTurnOn,
                modifier = Modifier.negativePadding(
                    top = inlineActionOverhang,
                    bottom = inlineActionOverhang,
                    start = if (isAX) inlineActionOverhang else 0.dp,
                ),
            )
            PrimerDismiss(onNotNow)
        }
    }

    val container = modifier
        .fillMaxWidth()
        // The rule under the primer, drawn after the content, so it spans the full width like every
        // other separator in the app.
        .drawWithContent {
            drawContent()
            val thickness = separatorHeight.toPx()
            drawRect(
                color = ThemeColor.separatorQuiet,
                topLeft = Offset(0f, size.height - thickness),
                size = Size(size.width, thickness),
            )
        }
        .padding(horizontal = ThemeMetrics.gutter)
        .heightIn(min = ThemeMetrics.rowCompact)
        .padding(vertical = ThemeSpace.x2)

    if (isAX) {
        Column(
            modifier = container,
            verticalArrangement = Arrangement.spacedBy(ThemeSpace.x2),
            horizontalAlignment = Alignment.Start,
        ) {
            words(Modifier.fillMaxWidth())
            answers()
        }
    } else {
        Row(
            modifier = container,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            words(Modifier.weight(1f))
            answers()
        }
    }
}

/** The deferral: a 28-dp disc in a 44-dp target. */
@Composable
private fun PrimerDismiss(onClick: () -> Unit) {
    Box(
        modifier = Modifier
            .clickable(
                interactionSource = null,
                indication = PressStyle.textAction,
                role = Role.Button,
                onClick = onClick,
            )
            .semantics(mergeDescendants = true) {
                contentDescription = Copy.Search.primerNotNow
            }
            .size(minimumTapTarget)
            .padding(ThemeSpace.x1),
        contentAlignment = Alignment.Center,
    ) {
        Box(
            modifier = Modifier
                .size(dismissDisc)
                .background(ThemeColor.surfaceRaised, CircleShape)
                .border(ThemeMetrics.hairline, ThemeColor.posterEdge, CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            SymbolIcon(
                symbol = PreviouslyIcons.Close,
                tint = ThemeColor.textTertiary,
                glyph = dismissGlyph,
            )
        }
    }
}

// -------------------------------------------------------------------------------------
// The scope bar
// -------------------------------------------------------------------------------------

/**
 * All · Anime · TV — **the app's own chip row, not `SingleChoiceSegmentedButtonRow`.**
 *
 * The M3 segmented row brings an outlined container, a `secondaryContainer` selected fill and a
 * sliding leading check: a second chip anatomy on a screen that already has the app's own. The
 * selected scope is a solid amber capsule with `onAccent` ink, which is legal amber — a selected
 * value is STATE — and draws no amber *word*.
 *
 * The bar exists only while there is text, because **the scope bar is a RESULTS control**. On the
 * focused-but-empty page it was a full-width pill pushing the recents down for a choice that had
 * nothing to filter yet; the active scope shows there as the launchpad's removable token instead.
 */
@Composable
fun SearchScopeBar(
    selected: MediaFilter,
    onSelect: (MediaFilter) -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(ThemeSpace.x2),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        MediaFilter.entries.forEach { filter ->
            ChipButton(
                text = Copy.Search.scopeWord(filter.wire),
                onClick = { onSelect(filter) },
                selected = filter == selected,
            )
        }
    }
}

// -------------------------------------------------------------------------------------
// Shared offsets the screen needs to place an over-art badge
// -------------------------------------------------------------------------------------

/**
 * Places an over-art [AddControl] in the artwork's top-trailing corner.
 *
 * The badge sits OUTSIDE the card's own button on purpose: a button nested inside another button's
 * label is a coin-toss for which one gets the tap.
 */
internal fun Modifier.overArtBadgePosition(bottom: Boolean = false): Modifier =
    offset(x = overArtOutset, y = if (bottom) overArtOutset else -overArtOutset)

/**
 * The disc on the POSTER's bottom-trailing corner (i4): anchored at the card's top and offset by
 * the poster's height, so it lands where a poster keeps its credits and never on the caption —
 * while staying outside the card's own button.
 */
internal fun Modifier.overArtFootPosition(posterHeight: Dp): Modifier =
    offset(x = 0.dp, y = posterHeight - minimumTapTarget + (minimumTapTarget - overArtDisc) / 2 - ThemeSpace.x2)
