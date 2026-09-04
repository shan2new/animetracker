package com.anitrack.app.ui.library

import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.snapping.rememberSnapFlingBehavior
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import com.anitrack.app.AppModel
import com.anitrack.app.design.ThemeColor
import com.anitrack.app.design.ThemeMetrics
import com.anitrack.app.design.ThemeSpace
import com.anitrack.app.design.ThemeType
import com.anitrack.app.ui.card.BannerCard
import com.anitrack.app.ui.card.ProgressBanner
import com.anitrack.app.ui.isAccessibilityTextSize
import com.anitrack.app.ui.control.PressStyle
import com.anitrack.app.ui.section.SectionHeaderRow
import com.anitrack.model.Franchise
import com.anitrack.model.FranchisePart
import com.anitrack.model.copy.Copy
import com.anitrack.model.copy.CopyLibrary
import com.anitrack.model.displayTitle
import com.anitrack.model.resumePart
import com.anitrack.model.wideArt
import com.anitrack.model.watchContext

/*
 * THE LIBRARY'S SHELVES — the port of `LibraryContinueShelf` / `LibraryContinueCard` /
 * `LibraryLandscapeShelf` from `ios/Sources/Features/Library/LibraryView.swift`.
 *
 * **Continue watching is an Up Next shelf.** Apple TV's *Up Next* / Netflix's *Continue Watching*
 * grammar: a horizontal shelf of landscape cards, each with progress drawn ON the art and the next
 * episode named beneath. It replaced a centred cover-flow spotlight — *"a carousel from another era
 * … it spent the root's first 300 pt on ONE show while hiding the rest behind a swipe."* Do not
 * reintroduce it.
 *
 * **There is no "See all" word in a shelf header.** `SectionHeaderRow`'s title IS the button and the
 * chevron carries the affordance; the label it takes is spoken, never drawn. That is the Apple TV /
 * Netflix shelf grammar, and it is also what keeps amber off the header — Library put an amber "See
 * all" directly over amber "Returns Oct 2" captions, which is the collision `interactive` exists to
 * end.
 */

// =================================================================================================
// MARK: - Card widths
// =================================================================================================

/**
 * The port of SwiftUI's `containerRelativeFrame(.horizontal, count:span:spacing:)`, which Compose
 * has no equivalent for.
 *
 * ```
 * unit  = (container − spacing × (count − 1)) / count
 * width = unit × span + spacing × (span − 1)
 * ```
 *
 * The container is the scroll CONTENT region — the screen minus both gutters — not the screen. On a
 * 393-dp device the Continue shelf's 5/4 yields ≈286 dp (161 dp tall at 16:9) and the landscape
 * shelves' 2/1 yields ≈174 dp; those are exactly the skeleton's own constants, which is how to
 * verify a port.
 *
 * The next card therefore **peeks**, and that peek is the point.
 */
private fun cardWidth(container: Dp, count: Int, span: Int, spacing: Dp): Dp {
    if (count <= 1) return container
    val unit = (container - spacing * (count - 1)) / count
    return unit * span + spacing * (span - 1)
}

/** Continue watching: four fifths of the content width. */
private const val CONTINUE_COUNT = 5
private const val CONTINUE_SPAN = 4

/** The four quiet shelves: two cards to a screen. */
private const val LANDSCAPE_COUNT = 2
private const val LANDSCAPE_SPAN = 1

/**
 * At an accessibility text size both shelves go to **one full-width card per screen**: a caption
 * that has grown by 60 % has nowhere to go inside a 174-dp column.
 */
private const val AX_COUNT = 1
private const val AX_SPAN = 1

/** iOS `.lineLimit(1...2).minimumScaleFactor(0.85)` on the Continue card's title. */
private const val CONTINUE_TITLE_LINES = 2

// =================================================================================================
// MARK: - Continue watching
// =================================================================================================

/**
 * The lead surface: an Up Next shelf of the shows you are in the middle of.
 *
 * @param items already filtered to titles with a real `resumePart` — *"the hero is an instruction to
 *   continue, so only a title with a real resume part may enter it."* The filter is applied again
 *   here because the card cannot be drawn without one, not because the caller is untrusted.
 * @param onViewAll the header's destination: All titles, filtered to Watching.
 */
@Composable
fun LibraryContinueShelf(
    items: List<Franchise>,
    appModel: AppModel,
    onOpenDetail: (String) -> Unit,
    onViewAll: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val isAX = isAccessibilityTextSize()
    val state = rememberLazyListState()

    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(ThemeMetrics.labelGap),
    ) {
        SectionHeaderRow(
            text = CopyLibrary.continueWatching,
            modifier = Modifier.padding(horizontal = ThemeMetrics.gutter),
            actionLabel = Copy.Action.seeAll,
            onAction = onViewAll,
        )

        BoxWithConstraints(Modifier.fillMaxWidth()) {
            val container = maxWidth - ThemeMetrics.gutter * 2
            val width = cardWidth(
                container = container,
                count = if (isAX) AX_COUNT else CONTINUE_COUNT,
                span = if (isAX) AX_SPAN else CONTINUE_SPAN,
                spacing = ThemeMetrics.shelfGap,
            )
            LazyRow(
                state = state,
                contentPadding = PaddingValues(horizontal = ThemeMetrics.gutter),
                horizontalArrangement = Arrangement.spacedBy(ThemeMetrics.shelfGap),
                // The nearest thing Compose has to `.scrollTargetBehavior(.viewAligned)`. It snaps
                // to an item's start rather than reproducing UIKit's deceleration, which is the
                // native answer per the fidelity line: the peeking rhythm is what carries the
                // grammar, not a particular rubber-band curve.
                flingBehavior = rememberSnapFlingBehavior(state),
            ) {
                items(
                    count = items.size,
                    key = { items[it].id },
                ) { index ->
                    val franchise = items[index]
                    val part = franchise.resumePart ?: return@items
                    FranchiseQuickActions(franchise = franchise, appModel = appModel) {
                        LibraryContinueCard(
                            franchise = franchise,
                            part = part,
                            modifier = Modifier.width(width),
                            onOpen = { onOpenDetail(franchise.id) },
                        )
                    }
                }
            }
        }
    }
}

/**
 * One Up Next card: the ONE 16:9 art-with-progress surface in the app, with the next episode named
 * beneath it.
 *
 * Where-you-are is the [ProgressBanner]'s wordless bar, never "11 of 24 watched" in words. The count
 * is spoken once, inside the card's own combined label — **and the spoken title is the WHOLE title,
 * not the shortened one**.
 */
@Composable
private fun LibraryContinueCard(
    franchise: Franchise,
    part: FranchisePart,
    onOpen: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val wide = remember(franchise, part) { part.wideArt(franchise) }
    val total = maxOf(part.totalEpisodes, part.airedEpisodes, part.progress)
    val ratio = if (total > 0) part.progress.toFloat() / total.toFloat() else 0f
    val next = remember(franchise, part) { nextEpisodeLine(franchise, part) }
    val spoken = remember(franchise, next, total, part.progress) {
        listOfNotNull(
            franchise.title,
            next,
            if (total > 0) Copy.Progress.watchedOf(part.progress, total) else null,
        ).joinToString(separator = ", ")
    }

    Column(
        modifier = modifier
            // The target IS a photograph: `overArt` dips it in brightness and compresses a hair.
            // A grey wash over someone's illustration is what that style exists to avoid.
            .clickable(
                // `null`, like every other card in the app: the press feel is the indication's, and
                // this card once collected `collectIsPressedAsState()` into a value nothing read —
                // subscribing every Continue card to the press stream and recomposing it on press
                // for a `Boolean` that was never used.
                interactionSource = null,
                indication = PressStyle.overArt,
                onClickLabel = Copy.Accessibility.opensTheShowHint,
                role = Role.Button,
                onClick = onOpen,
            )
            .semantics(mergeDescendants = true) { contentDescription = spoken },
        verticalArrangement = Arrangement.spacedBy(ThemeSpace.x2),
    ) {
        ProgressBanner(
            url = wide.url,
            portraitSource = wide.portraitSource,
            progress = if (total > 0) ratio else null,
        )
        Column(verticalArrangement = Arrangement.spacedBy(ThemeSpace.x0_5)) {
            BasicText(
                text = franchise.displayTitle,
                style = ThemeType.rowTitle.copy(color = ThemeColor.textPrimary),
                maxLines = CONTINUE_TITLE_LINES,
                overflow = TextOverflow.Ellipsis,
            )
            BasicText(
                text = next,
                style = ThemeType.rowMeta.copy(color = ThemeColor.textSecondary),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

/**
 * "Season 4 · Episode 12", upgraded to "Season 4 · Episode 12 · The Lion and the Sea" **only when
 * the server's own pointer agrees** that this is the episode we are naming.
 *
 * `continueWatching` is user-specific and never points at an unaired episode, so naming it is
 * spoiler-safe by the row model's own rule: the NEXT episode's title is always shown.
 */
private fun nextEpisodeLine(franchise: Franchise, part: FranchisePart): String {
    val episode = part.progress + 1
    val context = franchise.watchContext(part, episode)
    val pointer = franchise.continueWatching ?: return context
    if (pointer.mediaId != part.mediaId || pointer.episode.number != episode) return context
    val title = episodeTitle(pointer.episode.title, franchise.title) ?: return context
    return "$context · $title"
}

// -------------------------------------------------------------------------------------------------
// The episode-title sanitiser
// -------------------------------------------------------------------------------------------------

private val WHITESPACE_RUN = Regex("\\s+")
private val LEADING_EPISODE = Regex("^[Ee]pisode\\s*\\d*\\s*[-–—:·]?\\s*")
private val TITLE_TRIM = charArrayOf(' ', '-', '–', '—', ':', '·')
private val NON_TITLE_SUFFIXES = listOf("trailer", "teaser", "promo", " pv", "preview")

/**
 * The port of `EpisodeCopy.title(_:franchise:)` — returns `null` when the catalogue's string is not
 * really an episode title.
 *
 * Six rules, in order: collapse whitespace runs; strip a leading `Episode 12 —`; trim the separator
 * set; reject an empty result; reject one that starts with the show's own name (AniList's episode-1
 * slots embed it); reject one that still starts with "episode"; reject a trailer, teaser, promo, PV
 * or preview.
 *
 * Private here rather than shared: it is the only call site in this area, and the shared home for it
 * is the show page's own copy layer.
 */
private fun episodeTitle(raw: String?, franchiseTitle: String): String? {
    if (raw == null) return null
    var text = WHITESPACE_RUN.replace(raw, " ").trim()
    text = LEADING_EPISODE.replace(text, "")
    text = text.trim(*TITLE_TRIM)
    if (text.isEmpty()) return null
    val lowered = text.lowercase()
    if (franchiseTitle.isNotEmpty() && lowered.startsWith(franchiseTitle.lowercase())) return null
    if (lowered.startsWith("episode")) return null
    if (NON_TITLE_SUFFIXES.any { lowered.endsWith(it) }) return null
    return text
}

// =================================================================================================
// MARK: - The four quiet shelves
// =================================================================================================

/**
 * One card on a quiet shelf: the show, and the two fact lines resolved ONCE by the caller.
 *
 * [lead] and [meta] are carried **separately, never merged** — the amber decision is made from which
 * of the two is populated, and "the old merged `caption` is how this screen came to render 'Returns
 * today' in grey while Today drew the identical class of fact in accent."
 */
@Immutable
data class LibraryLandscapeItem(
    val franchise: Franchise,
    val lead: String? = null,
    val meta: String? = null,
)

/**
 * A quiet shelf of wide art cards — Returning, Watching (only when the Continue shelf cannot draw),
 * Planned, Announced, Watched.
 *
 * Identical scroller mechanics to the Continue shelf, two cards to a screen.
 */
@Composable
fun LibraryLandscapeShelf(
    title: String,
    items: List<LibraryLandscapeItem>,
    appModel: AppModel,
    onOpenDetail: (String) -> Unit,
    onViewAll: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val isAX = isAccessibilityTextSize()
    val state = rememberLazyListState()

    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(ThemeMetrics.labelGap),
    ) {
        SectionHeaderRow(
            text = title,
            modifier = Modifier.padding(horizontal = ThemeMetrics.gutter),
            actionLabel = Copy.Action.seeAll,
            onAction = onViewAll,
        )

        BoxWithConstraints(Modifier.fillMaxWidth()) {
            val container = maxWidth - ThemeMetrics.gutter * 2
            val width = cardWidth(
                container = container,
                count = if (isAX) AX_COUNT else LANDSCAPE_COUNT,
                span = if (isAX) AX_SPAN else LANDSCAPE_SPAN,
                spacing = ThemeMetrics.shelfGap,
            )
            LazyRow(
                state = state,
                contentPadding = PaddingValues(horizontal = ThemeMetrics.gutter),
                horizontalArrangement = Arrangement.spacedBy(ThemeMetrics.shelfGap),
                flingBehavior = rememberSnapFlingBehavior(state),
            ) {
                items(
                    count = items.size,
                    key = { items[it].franchise.id },
                ) { index ->
                    val item = items[index]
                    val franchise = item.franchise
                    val art = remember(franchise) { franchise.wideArt }
                    FranchiseQuickActions(franchise = franchise, appModel = appModel) {
                        BannerCard(
                            // The WHOLE title: `BannerCard` shortens it for display and speaks it
                            // entire.
                            title = franchise.title,
                            onClick = { onOpenDetail(franchise.id) },
                            modifier = Modifier.width(width),
                            lead = item.lead,
                            meta = item.meta,
                            art = art.url,
                            portraitSource = art.portraitSource,
                        )
                    }
                }
            }
        }
    }
}
