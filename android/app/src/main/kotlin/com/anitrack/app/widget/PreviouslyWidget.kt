package com.anitrack.app.widget

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon
import android.net.Uri
import android.os.Build
import android.util.Log
import android.widget.RemoteViews
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.ColorFilter
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.LocalContext
import androidx.glance.LocalSize
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.appWidgetBackground
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.appwidget.state.updateAppWidgetState
import androidx.glance.background
import androidx.glance.currentState
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.ContentScale
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxHeight
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.material3.ColorProviders
import androidx.glance.semantics.contentDescription
import androidx.glance.semantics.semantics
import androidx.glance.state.GlanceStateDefinition
import androidx.glance.state.PreferencesGlanceStateDefinition
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import com.anitrack.app.MainActivity
import com.anitrack.app.R
import com.anitrack.app.design.PreviouslyIcons
import com.anitrack.app.design.ThemeColor
import com.anitrack.app.design.ThemeSpace
import com.anitrack.app.ui.shell.ShellIntents
import com.anitrack.model.copy.EmptyStateCopy
import java.util.Locale

/*
 * ============================================================================================
 * "UP NEXT" — the home-screen widget. Today's billboard, compressed to one card.
 * ============================================================================================
 *
 * ### Glance is not Compose
 *
 * This is the Compose *runtime* driving a `RemoteViews` tree that the LAUNCHER inflates in its own
 * process. Everything drawable here is a composition of the fourteen views `RemoteViews` supports —
 * `FrameLayout`, `LinearLayout`, `RelativeLayout`, `TextView`, `ImageView`, `ProgressBar` and a
 * handful more. There is **no `Canvas`, no custom `View`, no shader, no `Modifier.blur`, no
 * animation, and no `remember` that survives an update** — so the app's whole chrome language
 * (`glassChrome`, `HeroTopVeil`, the hardened bar, `ArtHeader(drift:)`) is unavailable here, and
 * none of it is missed: a widget sits on wallpaper and has no chrome to veil. It is a different
 * drawing built from the same tokens, not "the hero, smaller".
 *
 * Four consequences worth reading before the layout:
 *
 *  * **Shapes are `@drawable` XML.** A `<shape><gradient>` is the only vertical fade this surface
 *    can draw, and a `<corners>` shape is the only rounded capsule below API 31 — `cornerRadius`
 *    needs `RemoteViews.setViewOutlinePreferredRadius`, which arrives in 31, and this app's floor
 *    is 26. So the pill, the dot and both halves of the progress bar are shapes.
 *  * **The progress bar is two boxes with computed widths.** Glance's `LinearProgressIndicator` is
 *    indeterminate only and `defaultWeight()` has no fractional form, so the track and the fill are
 *    both sized in dp off `LocalSize.current` — sizing the *track* too is what keeps them agreeing
 *    when the launcher hands the composition a bucket that is not quite the real width.
 *  * **The type is the system font.** *"Custom fonts in apps aren't supported"* — a `RemoteViews`
 *    limitation, not a Glance gap. Outfit does not cross the process boundary, and the workaround
 *    (rendering words to a bitmap) spends the widget's bitmap budget on text, breaks TalkBack and
 *    ignores font scaling. The iOS Live Activity conceded exactly this, for the same class of
 *    reason. Hierarchy here is carried by size, weight and colour.
 *  * **There is no horizontal gesture.** *"The only gestures available for widgets are touch and
 *    vertical swipe"* — horizontal belongs to the launcher's pager. A `ShelfCard` shelf cannot
 *    exist on this surface, which is why "Up Next" is one card and not a carousel.
 *
 * ### It is themed to the app, never to the wallpaper
 *
 * Glance's `LocalColors` defaults to `DynamicThemeColorProviders`, so a widget that never mentions
 * `GlanceTheme` — or mentions it with no `colors` argument — renders in the user's **Material You
 * palette**. For a product whose identity is one amber on one near-black, and whose design law
 * rations that amber to MEANING and STATE, that is a total loss of the brand. [PreviouslyGlanceTheme]
 * passes a **fixed** scheme (`ColorProviders(scheme)` — "a fixed scheme and does not have day/night
 * modes"), which is also the only correct answer for a dark-only app: a day/night pair would be
 * resolved against the *launcher's* configuration, which this app does not control.
 *
 * QA has a one-liner for it: change the wallpaper accent and re-capture. **A correct widget does not
 * move.**
 */

// ---------------------------------------------------------------------------------------------
// MARK: - The widget
// ---------------------------------------------------------------------------------------------

class PreviouslyWidget : GlanceAppWidget() {

    /**
     * Per-INSTANCE state only — the resolved `content://` art URI for this placed card, and the URL
     * it was resolved from.
     *
     * The library does not live here: it lives in the app's own offline copy, which this process
     * reads directly (a Glance receiver runs in the app's own process, so there is no App Group
     * problem to solve). What this holds is the one thing genuinely about *this instance right now*,
     * so a render that arrives before a fetch returns keeps the art it already had instead of
     * flashing through the artless drawing.
     */
    override val stateDefinition: GlanceStateDefinition<*> = PreferencesGlanceStateDefinition

    /**
     * Two buckets, not `SizeMode.Exact`.
     *
     * `Exact` means "complete widget recreation on size change (performance issues possible)", and
     * the content-URI art path removes the only reason to want it — nothing here decodes to an
     * exact pixel box. From Android 12 the system maps each bucket at bind time; below it Glance
     * re-composes per size.
     */
    override val sizeMode = SizeMode.Responsive(setOf(SMALL, WIDE))

    /** The picker's preview renders at the same breakpoints the placed card does. */
    override val previewSizeMode = SizeMode.Responsive(setOf(SMALL, WIDE))

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        // The library read is a local file and costs nothing; the ART is a network fetch that can
        // take seconds on a cold disk cache. So the copy is read here — the first frame is never
        // wrong about what airs next — and the art is left to the flow, which seeds itself from
        // whatever THIS instance drew last time. A launcher restart therefore re-draws the banner
        // immediately instead of showing Glance's loading frame while a fetch runs.
        val loader = widgetImageLoader(context)
        val snapshot = WidgetData.read(context, System.currentTimeMillis())

        // Built ONCE, outside the composition: `collectAsState` keys on the Flow instance, and a
        // flow constructed inside the composable body would restart its collection every frame.
        val frames = widgetFrames(context, loader) { uri, forUrl ->
            updateAppWidgetState(context, id) { prefs ->
                if (uri == null) {
                    prefs.remove(ArtUriKey)
                    prefs.remove(ArtForUrlKey)
                } else {
                    prefs[ArtUriKey] = uri
                    prefs[ArtForUrlKey] = forUrl.orEmpty()
                }
            }
        }

        provideContent {
            // The stored URI is used only while it still describes the show on the card. Without
            // that check a card that changed show between renders would wear the previous show's
            // photograph for a frame, which is a worse lie than no art at all.
            val storedUri = currentState(ArtUriKey)
            val storedFor = currentState(ArtForUrlKey)
            val seed = WidgetFrame(
                snapshot = snapshot,
                artUri = storedUri?.takeIf { storedFor == snapshot.content.artUrl },
            )
            // The composition stays live for ~45 s, and `updateAll` does NOT restart `provideGlance`
            // while it does — so a value read once above would be frozen for that whole window, and
            // a mark made in the app with the home screen showing would leave a stale card behind.
            // Observing a flow is the documented answer, and it is also what keeps "in 3h 12m"
            // counting down instead of quietly lying.
            val frame by frames.collectAsState(seed)
            PreviouslyGlanceTheme { UpNextCard(frame) }
        }
    }

    /**
     * The picker's card, drawn from the real composition in its placeholder state.
     *
     * The widget picker is where a widget is won or lost. Generated previews are rate-limited to
     * roughly two calls an hour with no system callback, so this draws the deliberate empty card
     * rather than a library this process may not have loaded yet; `previewImage` in the provider
     * XML stays as the pre-API-35 fallback.
     */
    override suspend fun providePreview(context: Context, widgetCategory: Int) {
        val placeholder = WidgetFrame(
            snapshot = WidgetSnapshot(
                content = WidgetContent.Blank(EmptyStateCopy.emptyToday),
                boundary = null,
            ),
            artUri = null,
        )
        provideContent {
            PreviouslyGlanceTheme { UpNextCard(placeholder) }
        }
    }

    override suspend fun onDelete(context: Context, glanceId: GlanceId) {
        super.onDelete(context, glanceId)
        // The last card is gone: stop waking a device for a surface nobody can see. `onEnabled`
        // re-arms both when one is placed again.
        if (!WidgetPresence.anyPlaced(context)) WidgetRefresh.cancel(context)
    }

    /**
     * A composition that throws must not leave Glance's stock error layout on the home screen.
     *
     * This app has no "something failed" widget state, so the fallback is the app's own line — one
     * sentence, in the app's voice, on the app's canvas. The colours are set from [ThemeColor] in
     * code rather than written into the layout XML, so the token table stays the single source.
     */
    override fun onCompositionError(
        context: Context,
        glanceId: GlanceId,
        appWidgetId: Int,
        throwable: Throwable,
    ) {
        Log.e(LOG_TAG, "Up Next composition failed", throwable)
        val views = RemoteViews(context.packageName, R.layout.widget_error).apply {
            setInt(R.id.widget_error_root, "setBackgroundColor", ThemeColor.canvas.toArgb())
            setTextColor(R.id.widget_error_text, ThemeColor.textSecondary.toArgb())
            setTextViewText(R.id.widget_error_text, EmptyStateCopy.serverNoCache.title)
        }
        runCatching { AppWidgetManager.getInstance(context).updateAppWidget(appWidgetId, views) }
    }

    private companion object {
        const val LOG_TAG = "PreviouslyWidget"
    }
}

/**
 * 4 × 2 — the default placement, and the size the drawing is tuned for.
 *
 * Wide enough for a 16:9 banner at a readable height and tall enough for the pill, the moment, the
 * show and its fact. Anything smaller cannot carry four lines and would have to drop the one that
 * is the reason somebody looked.
 */
private val SMALL = DpSize(250.dp, 110.dp)

/** 4 × 3 / 5 × 3 — room for the progress bar and the one support line as well. */
private val WIDE = DpSize(320.dp, 180.dp)

/** Above this the WIDE drawing is used. Taken from [WIDE]'s own height, not guessed at. */
private val WIDE_THRESHOLD = 150.dp

private val ArtUriKey = stringPreferencesKey("upNextArtUri")
private val ArtForUrlKey = stringPreferencesKey("upNextArtForUrl")

// ---------------------------------------------------------------------------------------------
// MARK: - Theme
// ---------------------------------------------------------------------------------------------

/**
 * The app's palette, pinned.
 *
 * `ColorProviders(scheme)` is the **fixed** overload: one palette, always, resolved nowhere. The
 * two-argument `ColorProviders(light, dark)` would hand the choice to the launcher's configuration,
 * and this app has no light mode to hand it.
 *
 * The Material 3 slot names do not cover this app's vocabulary — there is no `accentSoft`, no
 * `interactive`, no `canvasRaised` — so the drawing below reads [ThemeColor] directly for
 * everything. This scheme exists to make sure that anything Glance colours *for* us lands on the
 * app's palette rather than on the wallpaper's.
 */
private val PreviouslyWidgetColors = ColorProviders(
    darkColorScheme(
        primary = ThemeColor.accent,
        onPrimary = ThemeColor.onAccent,
        background = ThemeColor.canvas,
        onBackground = ThemeColor.textPrimary,
        surface = ThemeColor.surfaceFlat,
        onSurface = ThemeColor.textPrimary,
        surfaceVariant = ThemeColor.surfaceRaised,
        onSurfaceVariant = ThemeColor.textSecondary,
        outline = ThemeColor.textTertiary,
        error = ThemeColor.destructive,
    ),
)

@Composable
private fun PreviouslyGlanceTheme(content: @Composable () -> Unit) =
    GlanceTheme(colors = PreviouslyWidgetColors, content = content)

// ---------------------------------------------------------------------------------------------
// MARK: - The card
// ---------------------------------------------------------------------------------------------

@Composable
private fun UpNextCard(frame: WidgetFrame) {
    val size = LocalSize.current
    val wide = size.height >= WIDE_THRESHOLD
    val content = frame.snapshot.content
    // Read out of the frame once: a `when` branch must not depend on smart-casting a property of a
    // value class it does not own.
    val artUri = frame.artUri
    val franchiseId = (content as? WidgetContent.UpNext)?.item?.franchiseId

    Box(
        modifier = GlanceModifier
            .fillMaxSize()
            // Exactly one view may carry this. It is what earns the launcher's open transition and
            // what tells the system where the widget's own background is.
            .appWidgetBackground()
            .background(ThemeColor.canvas)
            .then(systemWidgetCorners())
            .then(openShow(franchiseId))
            .semantics { contentDescription = spokenLabel(content) },
    ) {
        when (content) {
            is WidgetContent.UpNext ->
                if (artUri != null && !content.item.artIsPortrait) {
                    Billboard(content.item, artUri, size.width, wide)
                } else {
                    BesideArt(content.item, artUri, size.width, wide)
                }

            is WidgetContent.Blank -> Placeholder(content.empty, wide)
        }
    }
}

/**
 * The billboard: banner gutter to gutter, the copy over its foot.
 *
 * The same anatomy Today and Detail draw, and the same one Schedule's `AiringCard` draws — art, a
 * scrim, then pill → headline → show → fact reading down. Only a moment earns a headline, so a
 * waiting episode gets its clock in accent and an aired one does not: there the show and the
 * episode are the news.
 */
@Composable
private fun Billboard(item: UpNextItem, artUri: String, width: Dp, wide: Boolean) {
    Image(
        provider = artProvider(artUri),
        contentDescription = null,
        contentScale = ContentScale.Crop,
        modifier = GlanceModifier.fillMaxSize(),
    )
    // The only legibility device this surface has. There is no blur, and a flat plate over art
    // would read as a second card — so the fade is a `<shape><gradient>` drawn over the whole card
    // and weighted to its foot.
    Image(
        provider = ImageProvider(R.drawable.widget_art_scrim),
        contentDescription = null,
        contentScale = ContentScale.FillBounds,
        modifier = GlanceModifier.fillMaxSize(),
    )
    SlateCopy(
        item = item,
        // What is left inside the card's own gutters — the width the bar has to agree with.
        contentWidth = (width - CARD_INSET * 2).coerceAtLeast(0.dp),
        wide = wide,
        fillHeight = true,
    )
}

/**
 * No banner: the poster is drawn WHOLE, leading-aligned, with the copy beside it.
 *
 * **A landscape frame never fills a portrait cover.** In the app a cover with no banner is
 * composited whole over its own blurred ground; a widget cannot blur, so this is not a degraded
 * billboard — it is a second, deliberate drawing on the flat surface ground, which is the anatomy
 * `MediaRow` uses everywhere else. With no art at all the copy simply takes the whole card, which
 * is the same layout with one element missing rather than a third design.
 */
@Composable
private fun BesideArt(item: UpNextItem, artUri: String?, width: Dp, wide: Boolean) {
    val posterWidth = if (wide) WIDE_POSTER_WIDTH else SMALL_POSTER_WIDTH
    val posterHeight = if (wide) WIDE_POSTER_HEIGHT else SMALL_POSTER_HEIGHT

    Row(
        modifier = GlanceModifier
            .fillMaxSize()
            .background(ThemeColor.surfaceFlat)
            .padding(CARD_INSET),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (artUri != null) {
            Image(
                provider = artProvider(artUri),
                contentDescription = null,
                // Fit, never Crop: a 2:3 cover is drawn at 2:3 or it is not drawn.
                contentScale = ContentScale.Fit,
                modifier = GlanceModifier
                    .width(posterWidth)
                    .height(posterHeight)
                    .then(posterCorners()),
            )
            Spacer(GlanceModifier.width(CARD_INSET))
        }
        Box(
            modifier = GlanceModifier.fillMaxHeight().defaultWeight(),
            contentAlignment = Alignment.CenterStart,
        ) {
            SlateCopy(
                item = item,
                // What is left after the poster, its gap, and both card insets.
                contentWidth = (
                    width - CARD_INSET * 2 -
                        (if (artUri != null) posterWidth + CARD_INSET else 0.dp)
                    ).coerceAtLeast(0.dp),
                wide = wide,
                fillHeight = false,
            )
        }
    }
}

/**
 * badge → show → one line → bar → support — the hero's own lockup (4 Sep, direction B).
 *
 * What state this is (a filled amber badge), then whose moment it is (the title), then the moment
 * and the episode on ONE line ("Today at 7:30 PM · Season 4 · Episode 15"). Where-you-are is the
 * bar and is **wordless** — the count rides in the spoken label, never printed beside a numeral
 * that already says it.
 *
 * The bar and the support line are the two things a 4 × 2 card has no room for, and they are
 * exactly the two the hero itself treats as optional.
 */
@Composable
private fun SlateCopy(item: UpNextItem, contentWidth: Dp, wide: Boolean, fillHeight: Boolean) {
    Column(
        modifier = if (fillHeight) {
            GlanceModifier.fillMaxSize().padding(CARD_INSET)
        } else {
            GlanceModifier.fillMaxWidth()
        },
    ) {
        Badge(text = item.eyebrow)

        // On the billboard the art breathes between the pill and the copy; beside a poster there is
        // no art to breathe and the block is centred as a whole.
        if (fillHeight) {
            Spacer(GlanceModifier.defaultWeight())
        } else {
            Spacer(GlanceModifier.height(ThemeSpace.x2))
        }

        Text(
            text = item.title,
            maxLines = 1,
            style = TextStyle(
                color = ColorProvider(ThemeColor.textPrimary),
                fontSize = if (wide) 20.sp else 17.sp,
                fontWeight = FontWeight.Medium,
            ),
        )

        Spacer(GlanceModifier.height(ThemeSpace.x0_5))

        Text(
            text = listOfNotNull(item.moment, item.fact).joinToString(" \u00B7 "),
            maxLines = 1,
            style = TextStyle(
                color = ColorProvider(ThemeColor.textSecondary),
                fontSize = if (wide) 13.sp else 12.sp,
                fontWeight = FontWeight.Normal,
            ),
        )

        if (wide) {
            item.progress?.let { value ->
                Spacer(GlanceModifier.height(ThemeSpace.x2))
                ProgressTrack(value = value, trackWidth = contentWidth)
            }
            item.support?.let { support ->
                Spacer(GlanceModifier.height(ThemeSpace.x1))
                Text(
                    text = support,
                    maxLines = 1,
                    style = TextStyle(
                        color = ColorProvider(ThemeColor.textTertiary),
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Normal,
                    ),
                )
            }
        }
    }
}

/**
 * `OverArtLabel` — the small-caps state capsule, at the app's own 24 dp height and 10 dp inset.
 *
 * The capsule is a `<shape><corners>` background rather than `cornerRadius`, which needs API 31; at
 * `minSdk 26` a slice of the floor would otherwise wear a rectangle over a photograph. **The dot is
 * amber and the word is ink**: amber here is STATE (today's drop, a later-today airing), and an
 * amber *word* would be the "this is a button" reading this app never allows.
 */
@Composable
private fun Badge(text: String) {
    Row(
        modifier = GlanceModifier
            .height(BADGE_HEIGHT)
            .background(
                imageProvider = ImageProvider(R.drawable.widget_badge),
                contentScale = ContentScale.FillBounds,
            )
            .padding(horizontal = BADGE_INSET),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = text.uppercase(Locale.getDefault()),
            maxLines = 1,
            style = TextStyle(
                color = ColorProvider(ThemeColor.onAccent),
                fontSize = 11.sp,
                fontWeight = FontWeight.Bold,
            ),
        )
    }
}

private val BADGE_HEIGHT = 20.dp
private val BADGE_INSET = 7.dp

@Suppress("unused")
@Composable
private fun Pill(text: String, dot: Boolean) {
    Row(
        modifier = GlanceModifier
            .height(PILL_HEIGHT)
            .background(
                imageProvider = ImageProvider(R.drawable.widget_pill),
                contentScale = ContentScale.FillBounds,
            )
            .padding(horizontal = PILL_INSET),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (dot) {
            Image(
                provider = ImageProvider(R.drawable.widget_dot),
                contentDescription = null,
                contentScale = ContentScale.FillBounds,
                modifier = GlanceModifier.size(PILL_DOT),
            )
            Spacer(GlanceModifier.width(PILL_GAP))
        }
        Text(
            text = text.uppercase(Locale.getDefault()),
            maxLines = 1,
            style = TextStyle(
                color = ColorProvider(ThemeColor.textPrimary),
                fontSize = 11.sp,
                fontWeight = FontWeight.Medium,
            ),
        )
    }
}

/**
 * Where-you-are, wordless — 3 dp, the app's own height, with a floor on the fill so a started
 * season is never a zero-width bar.
 *
 * Both halves are shape drawables so the caps are round at every API level, and both are sized in
 * dp because Glance has no fractional weight and its only progress composable is indeterminate.
 */
@Composable
private fun ProgressTrack(value: Float, trackWidth: Dp) {
    val filled = (trackWidth * value.coerceIn(0f, 1f)).coerceAtLeast(PROGRESS_MINIMUM_FILL)

    Box(
        modifier = GlanceModifier
            .width(trackWidth)
            .height(PROGRESS_HEIGHT)
            .background(
                imageProvider = ImageProvider(R.drawable.widget_progress_track),
                contentScale = ContentScale.FillBounds,
            ),
        contentAlignment = Alignment.CenterStart,
    ) {
        Spacer(
            GlanceModifier
                .width(filled)
                .height(PROGRESS_HEIGHT)
                .background(
                    imageProvider = ImageProvider(R.drawable.widget_progress_fill),
                    contentScale = ContentScale.FillBounds,
                ),
        )
    }
}

/**
 * Nothing to say, said deliberately.
 *
 * `ContentUnavailableView`'s anatomy on the canvas — a quiet symbol, a title, one sentence. **No
 * button**: the whole card is already the target, and a second control inside a 250 dp box would be
 * the plate this design system spent a release removing. The copy is the app's own Today empty
 * state, so the widget and the screen agree about what an empty library is.
 */
@Composable
private fun Placeholder(state: EmptyStateCopy, wide: Boolean) {
    Column(
        modifier = GlanceModifier.fillMaxSize().padding(CARD_INSET),
        verticalAlignment = Alignment.CenterVertically,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        placeholderSymbol(state.symbol)?.let { resId ->
            Image(
                provider = ImageProvider(resId),
                contentDescription = null,
                colorFilter = ColorFilter.tint(ColorProvider(ThemeColor.textTertiary)),
                modifier = GlanceModifier.size(PLACEHOLDER_SYMBOL),
            )
            Spacer(GlanceModifier.height(ThemeSpace.x2))
        }
        Text(
            text = state.title,
            maxLines = 2,
            style = TextStyle(
                color = ColorProvider(ThemeColor.textPrimary),
                fontSize = if (wide) 17.sp else 15.sp,
                fontWeight = FontWeight.Medium,
            ),
        )
        if (wide) {
            state.supporting?.let { supporting ->
                Spacer(GlanceModifier.height(ThemeSpace.x1))
                Text(
                    text = supporting,
                    maxLines = 2,
                    style = TextStyle(
                        color = ColorProvider(ThemeColor.textSecondary),
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Normal,
                    ),
                )
            }
        }
    }
}

/**
 * `EmptyStateCopy.symbol` carries a Material Symbols name; the app's icon inventory carries the
 * drawable. Only the names an empty widget can actually produce are mapped — the rest of the
 * inventory has no business being reachable from a home screen.
 */
private fun placeholderSymbol(name: String?): Int? = when (name) {
    "tv" -> PreviouslyIcons.Tv.resId
    "layers" -> PreviouslyIcons.Layers.resId
    "error" -> PreviouslyIcons.Error.resId
    "wifi_off" -> PreviouslyIcons.WifiOff.resId
    else -> null
}?.takeIf { it != 0 }

private fun spokenLabel(content: WidgetContent): String = when (content) {
    is WidgetContent.UpNext -> content.item.spoken
    is WidgetContent.Blank -> content.empty.spokenLabel
}

// ---------------------------------------------------------------------------------------------
// MARK: - Interaction
// ---------------------------------------------------------------------------------------------

/**
 * Tapping opens the show — through the SAME single-shot door a tapped episode alert uses.
 *
 * `actionStartActivity`, never a lambda action or an `ActionCallback`: *"Apps targeting Android 12+
 * cannot start activities from services or broadcast receivers that act as trampolines."* The intent
 * carries `ShellIntents.EXTRA_OPEN_DETAIL`, which `MainActivity.consume` turns into
 * `AppModel.pendingOpen`, which the shell turns into "select Today, push that show". One route for
 * the alert, the capture script and this — so it cannot rot in one place while still passing in
 * another.
 *
 * `FLAG_ACTIVITY_SINGLE_TOP` pairs with the manifest's `launchMode="singleTop"`: without it a tap on
 * a warm app builds a second `MainActivity`, `onNewIntent` never fires, nothing happens — and a
 * cold-start test still passes. The distinct `data` URI per show is what keeps the `PendingIntent`s
 * distinct, and it is also what makes the route drivable from `adb`:
 *
 * ```
 * adb shell am start -a android.intent.action.VIEW -d "previously://franchise/16498"
 * ```
 *
 * **There is no mark control (PLAN Q14).** A widget write would have to reach `sendProgress`'s
 * serialisation and `SyncCenter`'s replay from a cold process, and the Undo toast the write rules
 * assume cannot be shown on a home screen.
 */
@Composable
private fun openShow(franchiseId: String?): GlanceModifier {
    val context = LocalContext.current
    val intent = Intent(Intent.ACTION_VIEW)
        .setClass(context, MainActivity::class.java)
        .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
    if (franchiseId != null) {
        intent.putExtra(ShellIntents.EXTRA_OPEN_DETAIL, franchiseId)
        intent.data = Uri.parse("previously://franchise/$franchiseId")
    }
    return GlanceModifier.clickable(actionStartActivity(intent))
}

// ---------------------------------------------------------------------------------------------
// MARK: - Geometry
// ---------------------------------------------------------------------------------------------

/**
 * The launcher's own background radius, and only where it exists.
 *
 * `system_app_widget_background_radius` and `RemoteViews.setViewOutlinePreferredRadius` both arrive
 * in API 31. Below it a widget has no system corner to match — and the card is square, which is
 * what every other widget on an API 26–30 home screen is.
 */
private fun systemWidgetCorners(): GlanceModifier =
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        GlanceModifier.cornerRadius(android.R.dimen.system_app_widget_background_radius)
    } else {
        GlanceModifier
    }

/** Same gate. The poster keeps `ThemeRadius.poster` where the platform can round an outline. */
private fun posterCorners(): GlanceModifier =
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        GlanceModifier.cornerRadius(POSTER_RADIUS)
    } else {
        GlanceModifier
    }

/**
 * The art, as a REFERENCE the launcher resolves — never a decoded bitmap.
 *
 * `ImageProvider` has no `Uri` overload (`androidx.glance:glance:1.2.0` ships exactly three: a
 * resource id, a `Bitmap` and an `Icon`), so the `content://` string `WidgetArt` produced travels
 * as `Icon.createWithContentUri`. That is the same wire shape the design asks for: `RemoteViews`
 * carries the URI, the LAUNCHER opens it under the per-URI grant `WidgetArt` issued, and the pixels
 * never cross the Binder transaction or count against the per-widget memory ceiling. Passing a
 * `Bitmap` here would compile and would also be the one thing the FileProvider exists to avoid.
 */
private fun artProvider(artUri: String) = ImageProvider(Icon.createWithContentUri(Uri.parse(artUri)))

/** The card's own gutter. A widget's edge is the launcher's, so it sits a little wider than a row's. */
private val CARD_INSET = 14.dp

private val PILL_HEIGHT = 24.dp
private val PILL_INSET = 10.dp
private val PILL_DOT = 5.dp
private val PILL_GAP = 6.dp

private val PROGRESS_HEIGHT = 3.dp

/** One episode of twenty-four is still a start, and a start has to be visible. */
private val PROGRESS_MINIMUM_FILL = 3.dp

/** `ThemeRadius.poster`. */
private val POSTER_RADIUS = 10.dp

private val SMALL_POSTER_WIDTH = 56.dp
private val SMALL_POSTER_HEIGHT = 84.dp
private val WIDE_POSTER_WIDTH = 80.dp
private val WIDE_POSTER_HEIGHT = 120.dp

private val PLACEHOLDER_SYMBOL = 28.dp
