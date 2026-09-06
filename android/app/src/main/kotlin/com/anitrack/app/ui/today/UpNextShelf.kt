package com.anitrack.app.ui.today

import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.snapping.rememberSnapFlingBehavior
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.ColorProducer
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import com.anitrack.app.AppModel
import com.anitrack.app.design.ThemeColor
import com.anitrack.app.design.ThemeMetrics
import com.anitrack.app.design.ThemeRadius
import com.anitrack.app.design.ThemeSpace
import com.anitrack.app.design.ThemeType
import com.anitrack.app.ui.card.ProgressBanner
import com.anitrack.app.ui.control.MarkRing
import com.anitrack.app.ui.control.MarkRingStyle
import com.anitrack.app.ui.control.PressStyle
import com.anitrack.app.ui.library.FranchiseQuickActions
import com.anitrack.app.ui.library.cardWidth
import com.anitrack.app.ui.section.SectionHeaderRow
import com.anitrack.model.Franchise
import com.anitrack.model.FranchisePart
import com.anitrack.model.ShelfWindows
import com.anitrack.model.TemporalCopy
import com.anitrack.model.airedByNow
import com.anitrack.model.availableEpisodes
import com.anitrack.model.canonicalLabel
import com.anitrack.model.copy.Copy
import com.anitrack.model.displayTitle
import com.anitrack.model.lastAired
import com.anitrack.model.nextAiring
import com.anitrack.model.releasingPart
import com.anitrack.model.timeAnchor
import com.anitrack.model.watchContext
import com.anitrack.model.wideArt
import com.anitrack.app.data.ReceiptHost
import com.anitrack.app.ui.state.ReceiptLine

// =====================================================================================
// THE UP NEXT SHELF — everything waiting for you, as television (4 Sep).
//
// Ported from `TodayView.upNextShelf` / `upNextCard`. One shelf of 16:9 cards under the
// billboard: the rest of the queue first (episodes you can watch now, each with its mark ring),
// then what is coming (the moment as a pill on the art). Apple TV's Up Next row, in the Library's
// Continue-card geometry — four fifths of the content width, the next card peeking.
//
// It replaces two vertical lists: a "Next up" of poster rows with a ring and an "Upcoming" of
// rows with an amber second line — a settings table under a billboard, on the most-viewed screen
// in the app. The header says `nextUp` while a card can be marked and `upcoming` when nothing has
// aired, so the one "next" rule holds. At accessibility sizes the rows stay (`QueueSection` /
// `UpcomingSection`): a 16:9 card gives a grown caption four words.
// =====================================================================================

/** One card: a show, the episode the card is about, and the focus grammar's own kind. */
@Immutable
internal data class UpNextItem(
    val franchise: Franchise,
    val kind: FocusKind,
    val part: FranchisePart,
)

private val FocusKind.isMarkable: Boolean
    get() = this is FocusKind.Fresh || this is FocusKind.Backlog

/** The shelf's card: four fifths of the content width, so the next one peeks. */
private const val UP_NEXT_COUNT = 5
private const val UP_NEXT_SPAN = 4

private const val MIDDLE_DOT = "·"

@Composable
internal fun UpNextShelf(
    queue: List<Pair<Franchise, Pair<FocusKind, FranchisePart>>>,
    committedQueue: Collection<String>,
    showsViewAll: Boolean,
    updateCount: Int,
    now: Long,
    appModel: AppModel,
    onOpenDetail: (String) -> Unit,
    onViewAllUpdates: () -> Unit,
    onMarkQueueRow: (Franchise) -> Unit,
    modifier: Modifier = Modifier,
) {
    // Only what is OUT NOW (6 Sep). The upcoming airings this shelf used to append were
    // Schedule's own first rows, and a future airing is not actionable by definition.
    val cards = remember(queue) { queue.map { (f, kp) -> UpNextItem(f, kp.first, kp.second) } }
    val state = rememberLazyListState()

    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(ThemeMetrics.labelGap),
    ) {
        SectionHeaderRow(
            text = Copy.Label.nextUp,
            modifier = Modifier.padding(horizontal = ThemeMetrics.gutter),
            actionLabel = if (showsViewAll) Copy.Action.viewAllUpdates(updateCount) else null,
            onAction = if (showsViewAll) onViewAllUpdates else null,
        )

        BoxWithConstraints(Modifier.fillMaxWidth()) {
            val width = cardWidth(
                container = maxWidth - ThemeMetrics.gutter * 2,
                count = UP_NEXT_COUNT,
                // A shelf of one runs gutter to gutter (i1-F12).
                span = if (cards.size == 1) UP_NEXT_COUNT else UP_NEXT_SPAN,
                spacing = ThemeMetrics.shelfGap,
            )
            LazyRow(
                state = state,
                contentPadding = PaddingValues(horizontal = ThemeMetrics.gutter),
                horizontalArrangement = Arrangement.spacedBy(ThemeMetrics.shelfGap),
                flingBehavior = rememberSnapFlingBehavior(state),
            ) {
                items(count = cards.size, key = { cards[it].franchise.id }) { index ->
                    val item = cards[index]
                    FranchiseQuickActions(franchise = item.franchise, appModel = appModel) {
                        UpNextCard(
                            item = item,
                            now = now,
                            marked = committedQueue.contains(item.franchise.id),
                            modifier = Modifier.width(width),
                            onOpen = { onOpenDetail(item.franchise.id) },
                            onMark = { onMarkQueueRow(item.franchise) },
                        )
                    }
                }
            }
        }
    }
}

/**
 * One card: the show's wide art with the moment on it, the episode as a pill in the top-start
 * corner, the show and its season named beneath, the mark ring beside that while there is
 * something to mark — Schedule's airing card at shelf width, on the Library's Continue-card frame
 * ([ProgressBanner]), with the season bar on the art for a show in progress.
 */
@Composable
private fun UpNextCard(
    item: UpNextItem,
    now: Long,
    marked: Boolean,
    onOpen: () -> Unit,
    onMark: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val f = item.franchise
    val part = item.part
    val wide = remember(f, part) { part.wideArt(f) }
    val episode = upNextEpisode(item)?.let(Copy::episode)
    val caption = upNextCaption(item, now)
    val spoken = listOfNotNull(f.title, episode, caption?.first).joinToString(", ")

    Column(
        modifier = modifier.semantics { contentDescription = spoken },
        verticalArrangement = Arrangement.spacedBy(ThemeSpace.x2),
    ) {
        ProgressBanner(
            url = wide.url,
            portraitSource = wide.portraitSource,
            progress = upNextProgress(item, now),
            episode = episode,
            ultraWide = wide.ultraWide,
            modifier = Modifier.clickable(
                interactionSource = null,
                // A target that IS a photograph dips in brightness; it never takes a grey wash.
                indication = PressStyle.overArt,
                onClickLabel = Copy.Accessibility.opensTheShowHint,
                role = Role.Button,
                onClick = onOpen,
            ),
        )
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(ThemeSpace.x3),
        ) {
            Column(
                modifier = Modifier
                    .weight(1f)
                    .clickable(
                        interactionSource = null,
                        indication = PressStyle.row(ThemeRadius.row),
                        role = Role.Button,
                        onClick = onOpen,
                    ),
                verticalArrangement = Arrangement.spacedBy(ThemeSpace.x0_5),
            ) {
                BasicText(
                    text = f.displayTitle,
                    style = ThemeType.rowTitle,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                    color = ColorProducer { ThemeColor.textPrimary },
                )
                if (caption != null) {
                    // The rows' two-colour grammar: a forward-looking TIME is amber, an identity
                    // or a count is grey.
                    BasicText(
                        text = caption.first,
                        style = if (caption.second) ThemeType.rowMetaLead else ThemeType.rowMeta,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                        color = ColorProducer { if (caption.second) ThemeColor.accent else ThemeColor.textSecondary },
                    )
                }
            }
            if (item.kind.isMarkable) {
                MarkRing(
                    marked = marked,
                    onMark = onMark,
                    style = MarkRingStyle.Quiet,
                    episode = part.progress + 1,
                    label = "${Copy.Action.markAsWatched}, " +
                        "${f.watchContext(part, part.progress + 1)} of ${f.title}",
                )
            }
        }
        // The ring's receipt, in place under the caption (5 Sep).
        ReceiptLine(host = ReceiptHost.todayQueue(f.id), compact = true)
    }
}

/** The episode the card is about: the next unwatched one, or the one coming. */
private fun upNextEpisode(item: UpNextItem): Int? = when (item.kind) {
    is FocusKind.Waiting -> item.part.nextEpisodeNumber ?: item.part.airedEpisodes + 1
    is FocusKind.Fresh, is FocusKind.Backlog -> item.part.progress + 1
    FocusKind.CaughtUp -> null
}

/**
 * The card's one caption, in the rows' two-colour grammar — the episode itself is the pill on the
 * art. A forward-looking TIME (`second` = true, amber): the airing ("Sunday at 8:30 PM") or today's
 * drop ("Aired 2h ago"). Else the count in grey ("6 episodes left", "3 episodes behind" — Today is
 * the urgency room), else the season on a multi-part show, else nothing. (The card used to wear the
 * moment as a SECOND pill on the art over a caption that said only "Season 5".)
 */
private fun upNextCaption(item: UpNextItem, now: Long): Pair<String, Boolean>? {
    val f = item.franchise
    val part = item.part
    val season = part.canonicalLabel.takeIf { f.parts.size > 1 && it.isNotEmpty() }
    return when (val kind = item.kind) {
        is FocusKind.Waiting -> TemporalCopy.airs(kind.at, now, f.source) to true
        is FocusKind.Fresh -> {
            val last = f.lastAired(now)
            when {
                last != null && now - last <= ShelfWindows.NOW_BAR_LIVE ->
                    TemporalCopy.aired(last, now, f.source) to true
                kind.behind > 1 -> Copy.Progress.behind(kind.behind) to false
                else -> season?.let { it to false }
            }
        }
        is FocusKind.Backlog ->
            if (kind.left > 1) Copy.Progress.left(kind.left) to false else season?.let { it to false }
        FocusKind.CaughtUp -> Copy.Progress.caughtUp to false
    }
}

/**
 * Where you are in the season, on the art — watched over aired-by-now for a fresh drop, over the
 * available run for a backlog; nothing for a show with nothing started or nothing left.
 */
private fun upNextProgress(item: UpNextItem, now: Long): Float? {
    val part = item.part
    val total = when (item.kind) {
        is FocusKind.Fresh -> part.airedByNow(now, item.franchise.timeAnchor)
        is FocusKind.Backlog -> part.availableEpisodes()
        else -> return null
    }
    if (total <= 0 || part.progress <= 0 || part.progress >= total) return null
    return part.progress.toFloat() / total.toFloat()
}

