package com.anitrack.app.ui.detail

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import com.anitrack.app.AppModel
import com.anitrack.app.data.UndoState
import com.anitrack.app.design.PreviouslyIcons
import com.anitrack.app.design.PreviouslyMaterialBridge
import com.anitrack.app.design.ThemeColor
import com.anitrack.app.design.ThemeMetrics
import com.anitrack.app.design.ThemeRadius
import com.anitrack.app.design.ThemeSpace
import com.anitrack.app.design.ThemeType
import com.anitrack.app.design.rememberSymbol
import com.anitrack.app.ui.AutoSizeText
import com.anitrack.app.ui.art.ArtBackdrop
import com.anitrack.app.ui.art.EpisodeArtworkDefaults
import com.anitrack.app.ui.card.ProgressBanner
import com.anitrack.app.ui.chrome.PushedScreenChrome
import com.anitrack.app.ui.chrome.TopScrollEdgeChrome
import com.anitrack.app.ui.chrome.chromeHazeSource
import com.anitrack.app.ui.control.PressStyle
import com.anitrack.app.ui.control.PreviouslySwitch
import com.anitrack.app.ui.control.materialGlyphBox
import com.anitrack.app.ui.control.minimumTapTarget
import com.anitrack.app.ui.image.rememberArtTint
import com.anitrack.app.ui.state.SkeletonBlock
import com.anitrack.app.ui.state.SkeletonLine
import com.anitrack.app.ui.state.SkeletonRow
import com.anitrack.model.AppRegion
import com.anitrack.model.Franchise
import com.anitrack.model.FranchisePart
import com.anitrack.model.WideArt
import com.anitrack.model.canonicalLabel
import com.anitrack.model.copy.Copy
import com.anitrack.model.displayTitle
import com.anitrack.model.episodicPartsInOrder
import com.anitrack.model.landscapeArt
import com.anitrack.model.markTarget
import com.anitrack.model.portraitArt
import com.anitrack.model.withEpisodes
import kotlin.math.max
import kotlin.math.min
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay

/*
 * THE SEASON SCREEN — the port of `SeasonEpisodesView`
 * (ios/Sources/Features/FranchiseDetail/FranchiseDetailView.swift).
 *
 * One season, every episode, in the SAME row anatomy the show page's six-row window draws. What is
 * different is the chrome and the header:
 *
 *   * It has a **real navigation bar with a real material** — the opposite of what shipped:
 *
 *     > This screen used to hide it and hand-build its own — a circular back button, a centred 22-pt
 *     > title, a circular ellipsis, no material and no scroll edge effect, so the first row was
 *     > chopped in half under a black band and left a decapitated poster ghost at 50 % alpha. It then
 *     > repeated itself, printing "Season 3" a second time 150 pt below the first in larger type.
 *
 *   * The bar names **the SHOW**, not the season: *"the season is the header below, where its poster,
 *     its picker and its progress live."*
 *
 *   * The header is a `ProgressBanner` of the **season's own** art — *"each season is its own
 *     catalogue entry with its own key art, so the picker changes the picture as well as the name"* —
 *     over the same picker + count row the show page uses. It was a portrait poster beside a title
 *     and a thin line ("absolutely trash", user, 3 Sep) and the one place in the app that put a 2:3
 *     cover next to a column of 16:9 stills.
 *
 * And the list is a `LazyColumn`, which is not a preference: One Piece Season 1 advertises ~1,140
 * episodes.
 */

/**
 * @param mediaId the season the push opened on. The header's picker can move off it in place, which
 *   is what [SeasonEpisodesScreen]'s own selection holds.
 * @param focusEpisode a Schedule deep link's episode, scrolled to the CENTRE once the push has
 *   settled.
 */
@Composable
fun SeasonEpisodesScreen(
    franchiseId: String,
    mediaId: Int,
    appModel: AppModel,
    api: DetailApi,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
    focusEpisode: Int? = null,
) {
    var selectedMediaId: Int? by remember(franchiseId) { mutableStateOf(null) }
    var fetched: Franchise? by remember(franchiseId) { mutableStateOf(null) }
    // Per-view on purpose: *"it is a viewing preference for the list in front of you, not an account
    // setting."*
    var revealAll by remember(franchiseId) { mutableStateOf(false) }
    var prompt: WritePrompt? by remember(franchiseId) { mutableStateOf(null) }

    val activeMediaId = selectedMediaId ?: mediaId
    val franchise = appModel.franchise(franchiseId) ?: fetched

    LaunchedEffect(franchiseId) {
        if (fetched != null) return@LaunchedEffect
        fetched = try {
            // iOS omits the market here, which its own transport layer calls out as the one legacy
            // call site that does. Sending it is strictly better — the audience rating then matches
            // the viewer's market on this screen too — and is recorded as a deliberate divergence.
            api.franchise(franchiseId, AppRegion.current)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            null
        }
    }

    // The live LIBRARY part wins for progress; the detail fetch supplies episodes when the library
    // row has none.
    val part: FranchisePart? = remember(franchise, fetched, activeMediaId) {
        val live = franchise?.parts?.firstOrNull { it.mediaId == activeMediaId }
        val eps = fetched?.parts?.firstOrNull { it.mediaId == activeMediaId }?.episodes.orEmpty()
        if (live != null && live.episodes.isEmpty() && eps.isNotEmpty()) live.withEpisodes(eps) else live
    }

    val tint = rememberArtTint(franchise?.portraitArt)
    val quietTint = remember(tint) { DetailTint.quiet(tint) }
    val band = ThemeMetrics.inlineBarBottom()
    val listState = rememberLazyListState()
    val now = appModel.now
    val inLibrary = appModel.isInLibrary(franchiseId)

    Box(modifier.fillMaxSize().background(ThemeColor.canvas)) {
        PushedScreenChrome(Modifier.fillMaxSize()) {
            // THE shared wash — one spec, one implementation, app-wide. This screen carried a
            // private copy for as long as `ArtBackdrop` did not exist; it does, and every other
            // root and pushed list already calls it.
            ArtBackdrop(
                url = franchise?.landscapeArt ?: franchise?.portraitArt,
                // The screen has already resolved the show's colour for its own chrome, so the
                // wash is handed it rather than starting a second palette job for the same art.
                tint = tint,
                modifier = Modifier.align(Alignment.TopCenter),
            )

            if (franchise == null || part == null) {
                SeasonSkeleton(topInset = band)
            } else {
                val total = episodeListCount(part, now)
                val controller = rememberEpisodeListController(activeMediaId, appModel)
                LazyColumn(
                    state = listState,
                    modifier = Modifier
                        .fillMaxSize()
                        .chromeHazeSource(),
                    // A scroll INSET, never padding on the last row: a complete "Episode 11" row
                    // rendered in the strip between the floating pill and the home indicator.
                    contentPadding = PaddingValues(
                        top = band,
                        bottom = DetailMetrics.bottomClearance(),
                    ),
                ) {
                    item(key = "season-header") {
                        SeasonHeader(
                            franchise = franchise,
                            part = part,
                            seasons = franchise.episodicPartsInOrder,
                            onSelect = { selectedMediaId = it },
                            modifier = Modifier
                                .padding(horizontal = ThemeMetrics.gutter)
                                .padding(vertical = ThemeSpace.x3),
                        )
                    }
                    episodeListItems(
                        franchise = franchise,
                        part = part,
                        // No window: EVERY episode.
                        range = 1..max(1, total),
                        now = now,
                        inLibrary = inLibrary,
                        controller = controller,
                        tint = quietTint,
                        revealAll = revealAll,
                        itemModifier = Modifier.padding(horizontal = ThemeMetrics.gutter),
                    )
                }
                WritePromptDialog(prompt = controller.prompt) { controller.prompt = null }

                // 400 ms after appearance, so the push transition has settled, then the row goes to
                // the CENTRE rather than to the top under the bar.
                LaunchedEffect(focusEpisode, activeMediaId, total) {
                    val episode = focusEpisode ?: return@LaunchedEffect
                    if (episode !in 1..max(1, total)) return@LaunchedEffect
                    delay(FOCUS_JUMP_DELAY_MILLIS)
                    val viewport = listState.layoutInfo.let {
                        it.viewportEndOffset - it.viewportStartOffset
                    }
                    val rowPx = listState.layoutInfo.visibleItemsInfo
                        .firstOrNull { it.index > 0 }?.size ?: 0
                    val centring = if (viewport > rowPx) -(viewport - rowPx) / 2 else 0
                    // Index 0 is the header, so the episode's row is one further along.
                    listState.animateScrollToItem(index = episode, scrollOffset = centring)
                }
            }

            // A pushed screen has a REAL bar, and that bar owns its edge: it is hardened from the
            // first frame rather than cross-fading in, because there is no hero behind it.
            TopScrollEdgeChrome(
                modifier = Modifier.align(Alignment.TopCenter),
                height = band + ThemeMetrics.barEdgeRamp,
                soft = false,
                holdHeight = band,
            )

            SeasonBar(
                franchise = franchise,
                part = part,
                appModel = appModel,
                now = now,
                inLibrary = inLibrary,
                revealAll = revealAll,
                onRevealAll = { revealAll = it },
                onPrompt = { prompt = it },
                onBack = onBack,
                modifier = Modifier.align(Alignment.TopCenter),
            )
        }
    }

    WritePromptDialog(prompt = prompt) { prompt = null }
}

/** Long enough for the push transition to settle before the list jumps under the reader. */
private const val FOCUS_JUMP_DELAY_MILLIS = 400L

// =================================================================================================
// MARK: - The bar
// =================================================================================================

@Composable
private fun SeasonBar(
    franchise: Franchise?,
    part: FranchisePart?,
    appModel: AppModel,
    now: Long,
    inLibrary: Boolean,
    revealAll: Boolean,
    onRevealAll: (Boolean) -> Unit,
    onPrompt: (WritePrompt) -> Unit,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(top = ThemeMetrics.topSafeInset())
            .height(ThemeMetrics.inlineBarHeight)
            .padding(horizontal = ThemeSpace.x1),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        DetailBackButton(onClick = onBack)
        Box(Modifier.weight(1f), contentAlignment = Alignment.Center) {
            // The SHOW's short name. The season is the header below.
            BasicText(
                text = franchise?.displayTitle.orEmpty(),
                style = ThemeType.bodyEmphasis.copy(color = ThemeColor.textPrimary),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
        if (franchise != null && part != null && inLibrary) {
            SeasonOverflow(
                franchise = franchise,
                part = part,
                appModel = appModel,
                now = now,
                revealAll = revealAll,
                onRevealAll = onRevealAll,
                onPrompt = onPrompt,
            )
        } else {
            Spacer(Modifier.size(minimumTapTarget))
        }
    }
}

/**
 * The season screen's overflow.
 *
 * > The app has a spoiler model and used it on the Next up card, then showed every still and every
 * > title in the one place where the next ten episodes are all on screen at once. Per-row reveal
 * > stays for the one episode you want; this is for the viewer who does not want the question asked.
 */
@Composable
private fun SeasonOverflow(
    franchise: Franchise,
    part: FranchisePart,
    appModel: AppModel,
    now: Long,
    revealAll: Boolean,
    onRevealAll: (Boolean) -> Unit,
    onPrompt: (WritePrompt) -> Unit,
) {
    var open by remember { mutableStateOf(false) }
    val markTarget = part.markTarget(now)
    val label = part.canonicalLabel.ifEmpty { part.title }

    Box {
        BarGlyphButton(
            symbol = PreviouslyIcons.MoreHoriz,
            // Detail's says "More actions". One overflow GLYPH across the two screens of a
            // franchise; the label names what the menu is about.
            label = Copy.Detail.episodeActions,
            glyph = DetailMetrics.barGlyph,
            onClick = { open = true },
        )
        DetailMenu(expanded = open, onDismiss = { open = false }) {
            if (markTarget > part.progress) {
                val count = markTarget - part.progress
                DetailMenuItem(label = Copy.Action.markAll(count)) {
                    open = false
                    onPrompt(
                        WritePrompt(
                            title = Copy.Confirm.batchMarkTitle(count),
                            message = Copy.Confirm.batchMarkMessage(
                                from = part.progress + 1,
                                to = markTarget,
                            ),
                            confirm = Copy.Confirm.batchMarkConfirm(count),
                        ) {
                            appModel.markThrough(franchise.id, part.mediaId, markTarget)
                        },
                    )
                }
            }
            if (part.progress > 0) {
                val total = max(part.headerTotal(), part.progress)
                val prev = part.progress
                DetailMenuItem(
                    label = Copy.Action.markAllUnwatched(total),
                    destructive = true,
                ) {
                    open = false
                    onPrompt(
                        WritePrompt(
                            title = Copy.Confirm.resetSeasonTitle(total),
                            message = Copy.Confirm.resetSeason(label = label, total = total),
                            confirm = Copy.Confirm.resetSeasonConfirm(total),
                        ) {
                            appModel.setProgress(franchise.id, part.mediaId, 0)
                            appModel.presentUndo(
                                UndoState(
                                    mediaId = part.mediaId,
                                    franchiseId = franchise.id,
                                    prevProgress = prev,
                                    title = franchise.title,
                                    customMessage = Copy.Detail.labelMarkedUnwatched(label),
                                    undoAction = {
                                        appModel.setProgress(
                                            franchise.id,
                                            part.mediaId,
                                            prev,
                                            haptic = false,
                                        )
                                    },
                                ),
                            )
                        },
                    )
                }
            }
            DetailMenuDivider()
            RevealAllItem(revealAll = revealAll, onRevealAll = onRevealAll)
        }
    }
}

/**
 * The whole-list spoiler switch.
 *
 * A `DropdownMenu` has no toggle item, so the row IS the switch: one toggleable element with the
 * switch role and a spoken on/off value, exactly as `GroupedRow`'s toggle branch does.
 */
@Composable
private fun RevealAllItem(revealAll: Boolean, onRevealAll: (Boolean) -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .toggleable(
                value = revealAll,
                interactionSource = null,
                indication = PressStyle.groupedRow,
                role = Role.Switch,
                onValueChange = onRevealAll,
            )
            .height(minimumTapTarget)
            .padding(horizontal = ThemeMetrics.gutter),
        horizontalArrangement = Arrangement.spacedBy(ThemeSpace.x3),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Image(
            imageVector = rememberSymbol(
                if (revealAll) PreviouslyIcons.Visibility else PreviouslyIcons.VisibilityOff,
            ),
            contentDescription = null,
            modifier = Modifier.size(materialGlyphBox(DetailMetrics.barGlyph)),
            colorFilter = ColorFilter.tint(ThemeColor.interactive),
        )
        BasicText(
            text = Copy.Action.revealEpisodeTitlesAndStills,
            style = ThemeType.body.copy(color = ThemeColor.interactive),
            maxLines = 2,
            modifier = Modifier.weight(1f),
        )
        // The app's one switch. The ROW owns the gesture and the semantics; the control itself is
        // inert, which is `PreviouslySwitch`'s whole contract.
        PreviouslySwitch(revealAll)
    }
}

// =================================================================================================
// MARK: - The header
// =================================================================================================

/**
 * A `ProgressBanner` of the SEASON's own art over the same picker + count row the show page draws —
 * **never a poster beside a title and a line.**
 *
 * `WideArt` makes the one decision a wide frame makes: a landscape asset fills it; a portrait one is
 * composited whole on its own blurred ground. The season's cover falls back to the show's, so a
 * season the catalogue never illustrated still has a picture.
 */
@Composable
private fun SeasonHeader(
    franchise: Franchise,
    part: FranchisePart,
    seasons: List<FranchisePart>,
    onSelect: (Int) -> Unit,
    modifier: Modifier = Modifier,
) {
    val total = part.headerTotal()
    val watched = min(part.progress, max(total, part.progress))
    val wide = remember(part, franchise) {
        WideArt.from(part.landscapeArt, part.portraitArt ?: franchise.portraitArt)
    }
    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(ThemeSpace.x3),
    ) {
        ProgressBanner(
            url = wide.url,
            portraitSource = wide.portraitSource,
            // Where-you-are is a BAR, never "11 of 24 watched" in words. The count row below speaks
            // for it; the bar itself is silent.
            progress = if (total > 0) watched.toFloat() / total.toFloat() else null,
            modifier = Modifier.clearAndSetSemantics { },
        )
        SeasonPickerRow(
            part = part,
            seasons = seasons,
            total = total,
            watched = watched,
            onSelect = onSelect,
        )
    }
}

/**
 * Byte for byte the show page's `episodesHeader`, with two differences: the label has no "Episodes"
 * fallback here (the screen is about one season, which has a name or a title), and there is an extra
 * count branch for a season whose length the catalogue has never stated.
 */
@Composable
private fun SeasonPickerRow(
    part: FranchisePart,
    seasons: List<FranchisePart>,
    total: Int,
    watched: Int,
    onSelect: (Int) -> Unit,
) {
    var open by remember { mutableStateOf(false) }
    val label = part.canonicalLabel.ifEmpty { part.title }

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .semantics(mergeDescendants = false) { },
        horizontalArrangement = Arrangement.spacedBy(ThemeSpace.x2),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (seasons.size > 1) {
            Box(Modifier.weight(1f, fill = false)) {
                Row(
                    modifier = Modifier
                        .clickable(
                            interactionSource = null,
                            indication = PressStyle.textAction,
                            role = Role.Button,
                            onClick = { open = true },
                        )
                        .semantics(mergeDescendants = true) {
                            heading()
                            contentDescription = Copy.Detail.seasonPicker(label)
                        }
                        .height(minimumTapTarget),
                    horizontalArrangement = Arrangement.spacedBy(DetailMetrics.glyphGap),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    AutoSizeText(
                        text = label,
                        style = ThemeType.sectionTitle.copy(color = ThemeColor.textPrimary),
                        minScale = 0.85f,
                        maxLines = 1,
                    )
                    Image(
                        imageVector = rememberSymbol(PreviouslyIcons.UnfoldMore),
                        contentDescription = null,
                        modifier = Modifier.size(materialGlyphBox(DetailMetrics.pickerGlyph)),
                        colorFilter = ColorFilter.tint(ThemeColor.textTertiary),
                    )
                }
                DetailMenu(expanded = open, onDismiss = { open = false }) {
                    seasons.forEach { season ->
                        DetailMenuItem(
                            label = season.canonicalLabel.ifEmpty { season.title },
                            symbol = if (season.mediaId == part.mediaId) {
                                PreviouslyIcons.Check
                            } else {
                                null
                            },
                        ) {
                            open = false
                            // No animation wrapper here, where the show page's picker uses one: the
                            // whole list is re-keyed on the choice and there is nothing to tween.
                            onSelect(season.mediaId)
                        }
                    }
                }
            }
        } else {
            AutoSizeText(
                text = label,
                style = ThemeType.sectionTitle.copy(color = ThemeColor.textPrimary),
                minScale = 0.85f,
                maxLines = 1,
                modifier = Modifier
                    .weight(1f, fill = false)
                    .semantics { heading() },
            )
        }
        Spacer(Modifier.weight(1f))
        when {
            total > 0 -> BasicText(
                text = Copy.Progress.watchedOfCount(watched, total),
                style = ThemeType.metadata.copy(
                    color = ThemeColor.textTertiary,
                    fontFeatureSettings = "tnum",
                ),
                maxLines = 1,
                modifier = Modifier.semantics {
                    contentDescription = Copy.Progress.watchedOf(watched, total)
                },
            )

            part.progress > 0 -> BasicText(
                text = Copy.episodesWatched(part.progress),
                style = ThemeType.metadata.copy(color = ThemeColor.textTertiary),
                maxLines = 1,
            )
        }
    }
}

// =================================================================================================
// MARK: - The skeleton
// =================================================================================================

/**
 * Drawn whenever the franchise or the part is missing.
 *
 * Deliberately **not** wrapped in `SkeletonGate`: this screen was pushed from a row the reader just
 * tapped, so there is no "a fast response must never flash a skeleton" window to protect — the frame
 * has to have a shape from the moment it arrives.
 */
@Composable
private fun SeasonSkeleton(topInset: Dp) {
    Column(
        Modifier
            .fillMaxSize()
            .padding(horizontal = ThemeMetrics.gutter)
            .padding(top = topInset + ThemeSpace.x2),
    ) {
        SkeletonBlock(
            height = null,
            radius = ThemeRadius.card,
            modifier = Modifier
                .fillMaxWidth()
                .aspectRatio(ThemeMetrics.wideAspect)
                .padding(top = ThemeSpace.x3),
        )
        SkeletonLine(
            width = 120.dp,
            height = 20.dp,
            modifier = Modifier.padding(vertical = ThemeSpace.x3),
        )
        repeat(8) {
            SkeletonRow(
                poster = DpSize(
                    EpisodeArtworkDefaults.slot.width,
                    EpisodeArtworkDefaults.slot.height,
                ),
                lines = listOf(190.dp, 120.dp),
                posterRadius = ThemeRadius.episodeStill,
                spacing = ThemeMetrics.artGap,
                height = ThemeMetrics.rowEpisode,
            )
        }
    }
}
