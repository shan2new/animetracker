package com.anitrack.app.ui.detail

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.anitrack.app.design.ContinuousCornerShape
import com.anitrack.app.design.PosterSize
import com.anitrack.app.design.PreviouslyIcons
import com.anitrack.app.design.ShadowToken
import com.anitrack.app.design.ThemeColor
import com.anitrack.app.design.ThemeMetrics
import com.anitrack.app.design.ThemeRadius
import com.anitrack.app.design.ThemeSpace
import com.anitrack.app.design.ThemeType
import com.anitrack.app.design.artEdge
import com.anitrack.app.design.rememberSymbol
import com.anitrack.app.design.shadowToken
import com.anitrack.app.ui.card.ShelfCard
import com.anitrack.app.ui.control.PressStyle
import com.anitrack.app.ui.control.materialGlyphBox
import com.anitrack.app.ui.image.ArtMaxPixel
import com.anitrack.app.ui.image.RemoteImage
import com.anitrack.app.ui.isAccessibilityTextSize
import com.anitrack.app.ui.section.SectionHeaderRow
import com.anitrack.model.CatalogPerson
import com.anitrack.model.Franchise
import com.anitrack.model.FranchisePart
import com.anitrack.model.FranchisePeople
import com.anitrack.model.FranchiseVideo
import com.anitrack.model.PartKind
import com.anitrack.model.RelatedTitle
import com.anitrack.model.TemporalCopy
import com.anitrack.model.WatchAvailability
import com.anitrack.model.WatchProvider
import com.anitrack.model.announcedDateLabel
import com.anitrack.model.behind
import com.anitrack.model.canonicalLabel
import com.anitrack.model.copy.Copy
import com.anitrack.model.currentPart
import com.anitrack.model.isComplete
import com.anitrack.model.isUpcoming
import com.anitrack.model.nextAiring
import com.anitrack.model.portraitArt
import com.anitrack.model.releasingPart
import com.anitrack.model.timeAnchor
import java.util.Locale
import com.anitrack.app.ui.AutoSizeText

/*
 * DETAIL'S SHELVES — the port of `ios/Sources/Features/FranchiseDetail/DetailEnrichment.swift`,
 * plus the "Movies & extras" shelf, which is the same anatomy and belongs beside its siblings.
 *
 * FIVE shelves, in Apple TV's order after the episode list: **Movies & extras · Trailers ·
 * Cast & crew · More like this · Where to watch.** Each is [DetailShelf] — a `SectionHeaderRow` over
 * an edge-to-edge horizontal scroller — and each emits NOTHING when it has no content, so the 30-dp
 * section gap can never double.
 *
 * Two of them are deliberately **not controls**: a [PersonCard] claims no tap because there is no
 * person page, and a [ProviderMark] claims none because the data carries one link for the whole
 * title and none per provider — *"a mark that looked pressable would lie."*
 *
 * ## The gutter, and why the shelf owns it
 *
 * iOS lays every section inside one 16-pt content gutter and then pulls the shelf back out with
 * `.padding(.horizontal, -16)` so art can leave the screen. Compose has no negative padding that
 * also widens a child's constraints, and the native answer is the other way round: the content
 * column is **full-bleed**, each block pads itself, and the shelf spends the gutter as its
 * scroller's own leading `contentPadding`. Same picture, no fake modifier.
 */

// =================================================================================================
// MARK: - The shelf chassis
// =================================================================================================

/**
 * Art may run off the trailing edge; TYPE may not.
 *
 * 40 and not 28: *"at 28 the peeking card's caption still reached the bezel and sheared mid-word
 * ('Avatar:', 'Caught u', 'So', 'Re')."*
 */
private val shelfTrailingMargin = 40.dp

/**
 * Vertical slack inside the scroller.
 *
 * iOS spends 4 pt and disables the scroll clip so the cards' `.art` shadows are not sheared into a
 * hard line. Compose has no `scrollClipDisabled`, and the trailing mask needs an offscreen layer,
 * which clips — so the slack is doubled instead and the shadow lands inside the layer. Re-tuned so
 * it READS the same, per the fidelity line; it is not a transcription of the 4.
 */
private val shelfVerticalSlack = ThemeSpace.x2

/**
 * The trailing fade, skipped at accessibility text sizes — there the shelf is effectively a list,
 * and a fade over the one card a reader can see is a subtraction rather than a hint.
 */
private fun Modifier.shelfMask(masked: Boolean): Modifier {
    if (!masked) return this
    return this
        // `DstIn` multiplies the content's alpha by the mask's, which needs the content composited
        // into a layer of its own first.
        .graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }
        .drawWithContent {
            drawContent()
            drawRect(
                brush = Brush.horizontalGradient(
                    0.00f to Color.Black,
                    0.86f to Color.Black,
                    0.95f to Color.Black.copy(alpha = 0.45f),
                    1.00f to Color.Transparent,
                ),
                blendMode = BlendMode.DstIn,
            )
        }
}

/**
 * A section header over an edge-to-edge horizontal shelf.
 *
 * The header is `SectionHeaderRow`, which means **the title IS the button** when [onAction] is set,
 * with a trailing chevron and no "See all" word — the Apple TV / Netflix shelf grammar.
 *
 * @param content `LazyRow` items. Lazy because the people shelf runs to 20 cards and the related
 *   shelf to 12, each carrying a remote image.
 */
@Composable
fun DetailShelf(
    title: String,
    modifier: Modifier = Modifier,
    count: Int? = null,
    actionLabel: String? = null,
    onAction: (() -> Unit)? = null,
    content: LazyListScope.() -> Unit,
) {
    val masked = !isAccessibilityTextSize()
    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(ThemeMetrics.labelGap),
    ) {
        SectionHeaderRow(
            text = title,
            count = count,
            actionLabel = actionLabel,
            onAction = onAction,
            modifier = Modifier.padding(horizontal = ThemeMetrics.gutter),
        )
        LazyRow(
            modifier = Modifier
                .fillMaxWidth()
                .shelfMask(masked),
            contentPadding = PaddingValues(
                start = ThemeMetrics.gutter,
                end = shelfTrailingMargin,
                top = shelfVerticalSlack,
                bottom = shelfVerticalSlack,
            ),
            horizontalArrangement = Arrangement.spacedBy(ThemeMetrics.shelfGap),
            content = content,
        )
    }
}

// =================================================================================================
// MARK: - Movies & extras
// =================================================================================================

/** The settled tick a complete unit wears: a check on a dark disc, top-trailing on the art. */
private val settledBadgeSize = 26.dp
private val settledBadgeInset = 6.dp

/** The badge's tick, at its iOS point size. */
private val settledBadgeGlyph = 12.dp

/**
 * Everything that is **not** on the episodic spine, as art. The seasons live in the picker above.
 *
 * A catalogue of featurettes is not a member of the work: TMDB's season 0 on Game of Thrones carries
 * **300** of them, and printed inline after Season 1 with an empty tick column it read as "this app
 * thinks there are 300 Game of Thrones specials" — *"and a viewer who disbelieves one count
 * disbelieves every count above it."* So an extra is dimmed, inert, and not a control.
 */
@Composable
fun MoviesAndExtrasShelf(
    franchise: Franchise,
    parts: List<FranchisePart>,
    now: Long,
    inLibrary: Boolean,
    onToggle: (FranchisePart) -> Unit,
    onOpen: (FranchisePart) -> Unit,
    modifier: Modifier = Modifier,
) {
    if (parts.isEmpty()) return
    DetailShelf(title = Copy.Heading.moviesAndExtras, modifier = modifier) {
        items(parts, key = { it.mediaId }) { part ->
            ExtraCard(
                franchise = franchise,
                part = part,
                now = now,
                inLibrary = inLibrary,
                onToggle = { onToggle(part) },
                onOpen = { onOpen(part) },
            )
        }
    }
}

@Composable
private fun ExtraCard(
    franchise: Franchise,
    part: FranchisePart,
    now: Long,
    inLibrary: Boolean,
    onToggle: () -> Unit,
    onOpen: () -> Unit,
) {
    val isExtra = part.kind == PartKind.SPECIAL || part.kind == PartKind.MUSIC
    // A run of episodes (an OVA series, an ONA, a spin-off) is marked episode by episode on its
    // own screen; a single unit toggles whole.
    val episodic = !isExtra && part.totalEpisodes > 1
    val facts = remember(part, now, franchise) { partFacts(franchise, part, now) }
    // A FINISHED unit says nothing: the tick is the statement.
    val settled = !isExtra && part.isComplete && !part.isReleasing
    val caption = if (isExtra) {
        if (part.totalEpisodes > 1) Copy.episodes(part.totalEpisodes) else null
    } else {
        facts.lead ?: facts.meta
    }
    val title = part.canonicalLabel.ifEmpty { part.title }
    val spoken = listOfNotNull(title, caption).joinToString(", ")

    Box {
        ShelfCard(
            title = title,
            caption = caption,
            captionIsLead = facts.lead != null,
            poster = part.portraitArt ?: franchise.portraitArt,
            slot = PosterSize.ShelfMedium,
            hint = when {
                isExtra -> null
                episodic -> Copy.Detail.opensEpisodes
                inLibrary -> Copy.Detail.togglesWatched
                else -> null
            },
            onClick = {
                when {
                    isExtra -> Unit
                    episodic -> onOpen()
                    inLibrary -> onToggle()
                }
            },
            modifier = Modifier
                .alpha(if (isExtra) 0.6f else 1f)
                .semantics { if (settled) stateDescription = Copy.Accessibility.complete },
        )
        if (settled) {
            SettledBadge(Modifier.align(Alignment.TopEnd).padding(settledBadgeInset))
        }
        if (isExtra) {
            // "A catalogue of featurettes the app does not track is not a control" — and it offered
            // a double-tap that did nothing. The overlay eats the gesture; `clearAndSetSemantics`
            // drops the button trait and re-states the label as plain text.
            Box(
                Modifier
                    .matchParentSize()
                    .pointerInput(Unit) { detectTapGestures { } }
                    .clearAndSetSemantics { contentDescription = spoken },
            )
        }
    }
}

@Composable
private fun SettledBadge(modifier: Modifier = Modifier) {
    Box(
        modifier
            .size(settledBadgeSize)
            .background(ThemeColor.scrimStrong, CircleShape)
            .border(ThemeMetrics.hairline, ThemeColor.hairline, CircleShape)
            .clearAndSetSemantics { },
        contentAlignment = Alignment.Center,
    ) {
        Image(
            imageVector = rememberSymbol(PreviouslyIcons.Check),
            contentDescription = null,
            modifier = Modifier.size(materialGlyphBox(settledBadgeGlyph)),
            colorFilter = ColorFilter.tint(ThemeColor.textPrimary),
        )
    }
}

/** A non-spine part's one caption: `lead` is amber (a real next step), `meta` is grey. */
internal data class PartFacts(val meta: String?, val lead: String?)

/**
 * The caption ladder.
 *
 * Words for what has already happened are gone — *"a FINISHED season says nothing: the tick is the
 * statement"* — and an unstarted one states its size as a count, not "0 of 12 watched".
 */
internal fun partFacts(franchise: Franchise, part: FranchisePart, now: Long): PartFacts {
    val anchor = franchise.timeAnchor
    if (part.isUpcoming) {
        val date = part.announcedDateLabel(franchise.source)
        return if (date != null) {
            PartFacts(meta = null, lead = TemporalCopy.premieres(date))
        } else {
            PartFacts(meta = TemporalCopy.noDateAnnounced, lead = null)
        }
    }
    if (part.kind == PartKind.SPECIAL || part.kind == PartKind.MUSIC) {
        val scale =
            if (part.totalEpisodes > 1) Copy.episodes(part.totalEpisodes) else Copy.Detail.extras
        return PartFacts(meta = "$scale · ${Copy.Detail.notCountedTowardsProgress}", lead = null)
    }
    if (part.kind != PartKind.SEASON && part.totalEpisodes <= 1) {
        // A film or a single-unit OVA. "Movie" is spelled "Film".
        val kind = singularKindWord(part.kind)
        val year = part.year
        return PartFacts(meta = if (year != null) "$kind · $year" else kind, lead = null)
    }
    val total = part.headerTotal()
    if (part.isReleasing) {
        val behind = part.behind(now, anchor)
        if (behind > 0) return PartFacts(meta = null, lead = Copy.Progress.behind(behind))
        val next = franchise.nextAiring(now)
        if (next != null && franchise.releasingPart?.mediaId == part.mediaId) {
            return PartFacts(
                meta = null,
                lead = TemporalCopy.airs(at = next, now = now, source = franchise.source),
            )
        }
        return PartFacts(meta = Copy.Progress.caughtUp, lead = null)
    }
    if (franchise.currentPart?.mediaId == part.mediaId && part.progress < total) {
        return PartFacts(meta = null, lead = Copy.Progress.episodeNext(part.progress + 1))
    }
    // The tick is the statement.
    if (part.isComplete && !part.isReleasing) return PartFacts(meta = null, lead = null)
    val started = total > 0 && part.progress in 1 until total
    if (started) return PartFacts(meta = null, lead = Copy.Progress.left(total - part.progress))
    // Not started: its SIZE, as a count.
    return PartFacts(meta = if (total > 0) Copy.episodes(total) else null, lead = null)
}

/**
 * The singular word for a kind — what this one thing IS. `PartKind.sectionTitle` is the plural
 * section heading ("OVAs") and would read as a category instead.
 *
 * The words themselves are `Copy.Detail.partKind`'s; this only hands it the wire value. They used
 * to be spelled inline in a `when` here, and "Season" — a word the season picker, the show page's
 * header and Schedule's meta line all draw — was therefore spelled in several places at once.
 */
private fun singularKindWord(kind: PartKind): String = Copy.Detail.partKind(kind.wire)

// =================================================================================================
// MARK: - Trailers
// =================================================================================================

/** The card's own width; the art is exactly 16:9 of it (200 × 9 / 16, rounded). */
private val trailerCardWidth = 200.dp
private val trailerArtHeight = 113.dp
private val trailerPlayDisc = 40.dp

/** The play triangle inside that disc, at its iOS point size. */
private val trailerPlayGlyph = 15.dp

/** Optical centring: a triangle's visual centre sits right of its box's. */
private val trailerPlayNudge = 2.dp

/**
 * The title a video is drawn under: the catalogue's own, else the kind word.
 *
 * Presentation derived from a wire type — it belongs in `:model`'s derive layer beside
 * `FranchiseVideo.watchUrl`, and should move there when that file next grows.
 */
val FranchiseVideo.displayTitle: String
    get() = title ?: Copy.Video.kind(kind.wire)

/**
 * "Trailer · Season 6".
 *
 * Note the title guard: when the catalogue gave **no** title, [displayTitle] *is* the kind word, and
 * the kind is not repeated here — the caption is then just the part label, or absent.
 */
fun trailerMeta(video: FranchiseVideo, name: String?): String {
    val bits = ArrayList<String>(2)
    val kind = Copy.Video.kind(video.kind.wire)
    // "Official Series Trailer" over "Trailer" said it twice (i4).
    if (name == null || !name.contains(kind, ignoreCase = true)) bits.add(kind)
    video.partLabel?.let { bits.add(it) }
    if (bits.isNotEmpty()) return bits.joinToString(" · ")
    return providerName(video.site) ?: kind
}

@Composable
fun TrailerCard(video: FranchiseVideo, onPlay: () -> Unit, modifier: Modifier = Modifier, showTitle: String? = null) {
    val name = remember(video, showTitle) { video.titleCleanedFor(showTitle) ?: video.displayTitle }
    val meta = remember(video, name) { trailerMeta(video, name) }
    val spoken = listOfNotNull(name, meta).joinToString(", ")
    Column(
        modifier = modifier
            .width(trailerCardWidth)
            .clickable(
                interactionSource = null,
                indication = PressStyle.row(ThemeRadius.card),
                onClickLabel = Copy.Accessibility.playsTrailerHint,
                role = Role.Button,
                onClick = onPlay,
            )
            .semantics(mergeDescendants = true) { contentDescription = spoken },
        verticalArrangement = Arrangement.spacedBy(ThemeSpace.x2),
    ) {
        Box(
            Modifier
                .width(trailerCardWidth)
                .height(trailerArtHeight)
                .shadowToken(ShadowToken.Art, ContinuousCornerShape(ThemeRadius.card))
                .clip(ContinuousCornerShape(ThemeRadius.card))
                .background(ThemeColor.surfaceRaised)
                .artEdge(ThemeRadius.card),
            contentAlignment = Alignment.Center,
        ) {
            RemoteImage(
                url = video.thumbnailUrl,
                modifier = Modifier.matchParentSize(),
                maxPixel = ArtMaxPixel.TRAILER_THUMB,
                placeholder = false,
            )
            Box(
                Modifier
                    .size(trailerPlayDisc)
                    .background(ThemeColor.scrimStrong, CircleShape)
                    .border(ThemeMetrics.hairline, ThemeColor.hairline, CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                Image(
                    imageVector = rememberSymbol(PreviouslyIcons.PlayArrowFilled),
                    contentDescription = null,
                    // Optical centring: a triangle's visual centre sits right of its box's.
                    modifier = Modifier
                        .padding(start = trailerPlayNudge)
                        .size(materialGlyphBox(trailerPlayGlyph)),
                    colorFilter = ColorFilter.tint(ThemeColor.textPrimary),
                )
            }
        }
        Column(
            modifier = Modifier.width(trailerCardWidth),
            verticalArrangement = Arrangement.spacedBy(ThemeSpace.x0_5),
        ) {
            BasicText(
                text = name,
                style = ThemeType.shelfTitle.copy(color = ThemeColor.textPrimary),
                // Two lines held (i3): a one-line name beside a two-line one put the shelf's
                // captions on two baselines.
                minLines = 2,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            if (meta != null) {
                BasicText(
                    text = meta,
                    style = ThemeType.shelfCaption.copy(color = ThemeColor.textSecondary),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}

// =================================================================================================
// MARK: - Cast & crew
// =================================================================================================

private val personDisc = 72.dp
private val personCardWidth = 100.dp

/** The figure drawn when a person has no portrait, at its iOS point size. */
private val personFallbackGlyph = 26.dp

/** Detail draws at most this many faces. */
const val PEOPLE_LIMIT = 20

/**
 * Creators, then directors, then cast — de-duplicated by `id`, which carries the role, so **one
 * person can appear once per role** (a director who also acts).
 *
 * A creator or director the catalogue listed without a role word is given one, *"so a face is never
 * unexplained."*
 *
 * This is a model derivation (`FranchisePeople.ordered` on iOS) and belongs in `:model`'s derive
 * layer; it is here because that file does not carry it yet.
 */
fun FranchisePeople.orderedPeople(): List<CatalogPerson> {
    val out = ArrayList<CatalogPerson>(creators.size + directors.size + cast.size)
    val seen = HashSet<String>()
    fun add(person: CatalogPerson, fallbackRole: String?) {
        val resolved = if (person.role.isNullOrEmpty() && fallbackRole != null) {
            person.copy(role = fallbackRole)
        } else {
            person
        }
        if (seen.add(resolved.id)) out.add(resolved)
    }
    // CAST first (i1-F7) — the faces a viewer recognises are the row's reason — then the
    // creators, then only the directors who direct (the server files camera and AD crew under
    // `directors`). Capped at 16.
    val keep = setOf("director", "creator", "showrunner", "writer", "executive producer", "series director")
    cast.take(10).forEach { add(it, null) }
    creators.forEach { add(it, Copy.People.creator) }
    directors.filter { p -> p.role?.lowercase()?.let { it in keep } ?: true }
        .forEach { add(it, Copy.People.director) }
    return out.take(16)
}

/**
 * A face and what it is. **Not a control** — there is no person page, so it claims no tap.
 *
 * The crop anchor is the TOP: a portrait head-shot cropped to a circle from its centre is a chin.
 */
@Composable
fun PersonCard(person: CatalogPerson, modifier: Modifier = Modifier) {
    val spoken = Copy.Accessibility.person(person.name, person.role)
    Column(
        modifier = modifier
            .width(personCardWidth)
            .semantics(mergeDescendants = true) { contentDescription = spoken },
        verticalArrangement = Arrangement.spacedBy(ThemeSpace.x2),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(
            Modifier
                .size(personDisc)
                .clip(CircleShape)
                .background(ThemeColor.surfaceRaised)
                .border(ThemeMetrics.hairline, ThemeColor.posterEdge, CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            val image = person.image
            if (image != null) {
                RemoteImage(
                    url = image,
                    modifier = Modifier.matchParentSize(),
                    maxPixel = ArtMaxPixel.PERSON_DISC,
                    alignment = Alignment.TopCenter,
                    placeholder = false,
                )
            } else {
                Image(
                    imageVector = rememberSymbol(PreviouslyIcons.PersonFilled),
                    contentDescription = null,
                    modifier = Modifier.size(materialGlyphBox(personFallbackGlyph)),
                    colorFilter = ColorFilter.tint(ThemeColor.textTertiary),
                )
            }
        }
        Column(
            modifier = Modifier.width(personCardWidth),
            verticalArrangement = Arrangement.spacedBy(ThemeSpace.x0_5),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            // One line at a step of scale (i1, iOS's rule): a name that wrapped put the roles on
            // two baselines across the shelf.
            AutoSizeText(
                text = person.name,
                style = ThemeType.shelfTitle.copy(
                    color = ThemeColor.textPrimary,
                    textAlign = TextAlign.Center,
                ),
                minScale = 0.85f,
                maxLines = 1,
            )
            val role = person.displayRole
            if (role != null) {
                BasicText(
                    text = role,
                    style = ThemeType.shelfCaption.copy(
                        color = ThemeColor.textSecondary,
                        textAlign = TextAlign.Center,
                    ),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}

// =================================================================================================
// MARK: - More like this
// =================================================================================================

/** Detail draws at most this many recommendations. */
const val RELATED_LIMIT = 12

/**
 * A recommendation, as a poster card.
 *
 * @param resolving the card is waiting on the exact-title search that materialises it. It dims
 *   rather than spawning a spinner: the wait is one network round trip, not a task with progress.
 */
@Composable
fun RelatedCard(
    related: RelatedTitle,
    resolving: Boolean,
    onOpen: () -> Unit,
    modifier: Modifier = Modifier,
) {
    ShelfCard(
        title = related.title,
        caption = related.identityLine,
        reserveTitleLines = true,
        poster = related.portraitArt,
        slot = PosterSize.ShelfMedium,
        hint = Copy.Accessibility.opensTheShowHint,
        onClick = onOpen,
        modifier = modifier.alpha(if (resolving) 0.55f else 1f),
    )
}

// =================================================================================================
// MARK: - Where to watch
// =================================================================================================

private val providerMarkSize = 52.dp

/**
 * The streaming row.
 *
 * **Drawn only for [WatchAvailability.Status.AVAILABLE]** — a section that says "not here" is not a
 * section — and the caller branches on `status`, never on `providers.isEmpty()`: `NOT_AVAILABLE` is
 * a matched title with nothing streaming in that country, `UNMATCHED` means the anime→TMDB bridge
 * could not establish identity safely, and `DISABLED` means this deployment has no TMDB token.
 *
 * The HEADER is the link (the provider data gives one regional watch page, not per-provider deep
 * links) and grows a chevron when there is one; the marks themselves are inert.
 */
@Composable
fun WatchProvidersRow(
    availability: WatchAvailability,
    onOpenLink: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    val link = availability.link
    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(ThemeMetrics.labelGap),
    ) {
        DetailShelf(
            title = Copy.Heading.whereToWatch,
            onAction = if (link == null) null else ({ onOpenLink(link) }),
        ) {
            // Subscription services first, then free and ad-supported. The order is contractual —
            // never re-sorted here.
            items(availability.providers, key = { it.id }) { provider ->
                ProviderMark(provider)
            }
        }
        // Required attribution for the provider data.
        BasicText(
            text = Copy.Watch.attribution(availability.attribution),
            style = ThemeType.caption.copy(color = ThemeColor.textTertiary),
            modifier = Modifier.padding(horizontal = ThemeMetrics.gutter),
        )
    }
}

/** A provider's mark. Not a control — see [WatchProvidersRow]. */
@Composable
fun ProviderMark(provider: WatchProvider, modifier: Modifier = Modifier) {
    val spoken = "${provider.name}, ${Copy.Watch.access(provider.access.wire)}"
    Box(
        modifier
            .size(providerMarkSize)
            .clip(ContinuousCornerShape(ThemeRadius.compactControl))
            .background(ThemeColor.surfaceRaised)
            .artEdge(ThemeRadius.compactControl)
            .semantics(mergeDescendants = true) { contentDescription = spoken },
        contentAlignment = Alignment.Center,
    ) {
        val logo = provider.logo
        if (logo != null) {
            RemoteImage(
                url = logo,
                modifier = Modifier.matchParentSize(),
                maxPixel = ArtMaxPixel.PROVIDER_LOGO,
                placeholder = false,
            )
        } else {
            BasicText(
                text = providerInitials(provider.name),
                style = ThemeType.metadataEmphasis.copy(color = ThemeColor.textSecondary),
                maxLines = 1,
            )
        }
    }
}

/** The first letter of each of the first two words, upper-cased in the device's own locale. */
internal fun providerInitials(name: String): String =
    name.split(' ')
        .filter { it.isNotBlank() }
        .take(2)
        .joinToString("") { it.first().toString() }
        .uppercase(Locale.getDefault())

// =================================================================================================
// MARK: - Shared geometry
// =================================================================================================

/** The gutter every non-shelf block on the show page pads itself by. */
internal val detailGutter: Dp = ThemeMetrics.gutter

/** The provider's name as it is written, from the wire's lowercase `site` ("youtube"). */
private fun providerName(site: String?): String? = when (site?.trim()?.lowercase()) {
    null, "" -> null
    "youtube" -> "YouTube"
    "vimeo" -> "Vimeo"
    else -> site.replaceFirstChar { it.uppercase() }
}
