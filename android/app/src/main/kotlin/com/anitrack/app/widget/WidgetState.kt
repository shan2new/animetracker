package com.anitrack.app.widget

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import androidx.compose.runtime.Immutable
import androidx.core.content.FileProvider
import androidx.glance.appwidget.updateAll
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import coil3.ImageLoader
import coil3.request.CachePolicy
import coil3.request.ImageRequest
import coil3.request.SuccessResult
import coil3.size.Precision
import com.anitrack.app.PreviouslyApp
import com.anitrack.app.data.AmbientSync
import com.anitrack.app.data.LibraryCache
import com.anitrack.app.ui.today.FocusKind
import com.anitrack.app.ui.today.calmFocusKind
import com.anitrack.app.ui.today.focusKind
import com.anitrack.app.ui.today.heroSlate
import com.anitrack.model.Franchise
import com.anitrack.model.ShelfWindows
import com.anitrack.model.WatchStatus
import com.anitrack.model.behind
import com.anitrack.model.continueBacklog
import com.anitrack.model.copy.Copy
import com.anitrack.model.copy.EmptyStateCopy
import com.anitrack.model.displayTitle
import com.anitrack.model.effectiveStatus
import com.anitrack.model.lastAired
import com.anitrack.model.nextAiring
import com.anitrack.model.nextPremiere
import com.anitrack.model.releasingPart
import com.anitrack.model.resumePart
import com.anitrack.model.shelfState
import com.anitrack.model.timeAnchor
import com.anitrack.model.tracksAirings
import com.anitrack.model.upcomingAiring
import com.anitrack.model.wideArt
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.util.concurrent.TimeUnit
import kotlin.math.min

/*
 * ============================================================================================
 * THE WIDGET'S DATA LAYER — what "Up Next" knows, where it reads it, and when it re-renders.
 * ============================================================================================
 *
 * ### The one rule that shapes this whole file
 *
 * **The widget runs in a process that is usually cold.** `UpNextWidgetReceiver` is declared in the
 * same APK with no `android:process`, so it shares `filesDir`, the Coil disk cache and — if the
 * app happens to be alive — the very same [PreviouslyApp] object graph. What it does **not** share
 * is `AppModel`'s in-memory state: the library list, the 20-second `now` clock and the session's
 * `justCaught` set only exist while a composition is running, and a home-screen render is precisely
 * the case where none is.
 *
 * So the widget reads **the app's own offline library copy** (`library-cache.json`, written after
 * every successful `AppModel.reload()`), and derives everything else with the pure functions in
 * `:model`. There is deliberately **no second, widget-only cache**: two caches drift, and the
 * moment they do the widget becomes the app's liar.
 *
 * ### What it says
 *
 * The same slate Today's billboard says, compressed — [com.anitrack.app.ui.today.heroSlate] is
 * called directly, so the pill, the clock, the show, the fact line and the progress ratio are
 * literally the app's own sentences and can never drift into a second grammar. **PLAN Q15**: the
 * widget speaks `TemporalCopy` ("in 3h 12m"), not a system `Chronometer` — a `Chronometer` ticks
 * for free but can only ever say `H:MM:SS`, which is a grammar this product does not have.
 *
 * ### What it does NOT do
 *
 * **PLAN Q14 — there is no mark-as-watched control in v1.** Every progress write goes through
 * `AppModel.sendProgress`'s serialisation and `SyncCenter`'s replay, and the Undo toast — the
 * safety net the write rules assume — cannot be shown on a home screen. Tapping opens the show,
 * through the SAME single-shot door a tapped episode alert uses (`ShellIntents.EXTRA_OPEN_DETAIL`
 * → `AppModel.pendingOpen`). One route, so it cannot rot unnoticed.
 */

// ---------------------------------------------------------------------------------------------
// MARK: - The content model
// ---------------------------------------------------------------------------------------------

/**
 * One reading of "what is next", already worded.
 *
 * Every string on it came out of the copy catalogue via `heroSlate`; nothing here formats anything
 * itself. It is a plain value so the whole selection is testable without an Android context and
 * without Glance.
 */
@Immutable
internal data class UpNextItem(
    val franchiseId: String,
    /** The badge: the STATE, uppercased by the drawing. "NEW EPISODE", "4 EPISODES BEHIND". */
    val eyebrow: String,
    /** The MOMENT, leading the one line under the title: "Today at 7:30 PM", "Aired 29 min ago". */
    val moment: String?,
    /** `displayTitle` — "Re:ZERO", as every row and shelf draws it. */
    val title: String,
    /** "Season 4 · Episode 15" — the line is `moment · fact`. */
    val fact: String,
    /** At most one more thing. Drawn only where there is room for it. */
    val support: String?,
    /** Where-you-are, WORDLESS. Null when nothing is watched or everything is. */
    val progress: Float?,
    /** What a screen reader hears for the bar — the bar is silent without it. */
    val progressSpoken: String?,
    /** `wideArt.url` — the banner, else the cover. */
    val artUrl: String?,
    /** True when [artUrl] is a 2:3 cover: it is drawn WHOLE beside the copy, never stretched. */
    val artIsPortrait: Boolean,
) {

    /**
     * The whole card as one sentence.
     *
     * A widget is one target with one meaning; reading it out as five unlabelled fragments is worse
     * than reading it as a line. The bar's own count rides along because a Glance progress bar is
     * two coloured boxes and has nothing to speak with.
     */
    val spoken: String
        get() = (
            listOfNotNull(eyebrow, title, moment, fact, support, progressSpoken)
                .joinToString(SPOKEN_SEPARATOR)
            ) + SPOKEN_SEPARATOR + Copy.Accessibility.opensTheShowHint
}

/** What the widget has to say: a reading, or an honest absence. */
@Immutable
internal sealed interface WidgetContent {

    /** The art the frame wants, or null. Hoisted so the art resolver never unwraps the state. */
    val artUrl: String?

    @Immutable
    data class UpNext(val item: UpNextItem) : WidgetContent {
        override val artUrl: String? get() = item.artUrl
    }

    /**
     * Nothing to say — an empty account, a signed-out device, or a launch before the first
     * library ever landed. All three read the same and that is correct: the cache is cleared on
     * sign-out, so "no copy on this device" and "no shows yet" are the same fact about this phone.
     *
     * Named `Blank` rather than `Nothing` so the type never shadows `kotlin.Nothing`.
     */
    @Immutable
    data class Blank(val empty: EmptyStateCopy) : WidgetContent {
        override val artUrl: String? get() = null
    }
}

/**
 * A reading plus the instant it stops being true.
 *
 * [boundary] is the soonest upcoming airing anywhere in the library — the ONE moment the widget's
 * meaning changes without anybody touching the phone ("Airs in 3m" → "Out now"). It is what the
 * one-shot alarm in [WidgetRefresh] is armed against; everything else the widget shows changes only
 * because the app changed the library, and the app tells it so directly.
 */
@Immutable
internal data class WidgetSnapshot(
    val content: WidgetContent,
    val boundary: Long?,
)

/** A snapshot with its artwork resolved to something the launcher's process can actually open. */
@Immutable
internal data class WidgetFrame(
    val snapshot: WidgetSnapshot,
    /** A `content://` string from the app's `FileProvider`, or null for the artless drawing. */
    val artUri: String?,
)

// ---------------------------------------------------------------------------------------------
// MARK: - Selection
// ---------------------------------------------------------------------------------------------

/**
 * Reads the offline library copy and picks the one thing worth a home-screen card.
 *
 * ### The order is Today's order, deliberately
 *
 * The widget must never rank shows differently from the screen it compresses, so the stack below is
 * `TodayScreen.liveItems` + Today's calm fallback, evaluated over a plain list instead of over
 * `AppModel`'s property getters:
 *
 *   1. **Out now** — a releasing part with an aired, unwatched episode inside the 7-day window,
 *      Watching first, then by the airings-advanced `lastAired`.
 *   2. **Keep watching** — mid-watch backlog off any airing schedule, most backlog first.
 *   3. **The calm hero** — `nextUp`, else the most-claimed Watching show. Today is never without a
 *      billboard and neither is this.
 *
 * `justCaught` is passed as empty on purpose: it is a 650 ms in-app pulse belonging to the
 * composition that fired the mark, and there is no such moment on a home screen.
 *
 * > **Hoist me.** `outNow` / `keepWatching` / `nextUp` live on `AppModel` as property getters, so a
 * > second reader has to restate their predicates. The predicates themselves are all `:model`
 * > derivations, so nothing is *re-derived* here — but the three orderings are stated twice in the
 * > codebase, which is one time too many. The right fix is to move them into `:model` as pure
 * > functions over `List<Franchise>` and have `AppModel` call them too; it is deliberately not done
 * > from inside the widget's own area.
 */
internal object WidgetData {

    /** The whole read: cache → selection → wording. Safe to call from any dispatcher but IO-bound. */
    suspend fun read(context: Context, now: Long): WidgetSnapshot =
        withContext(Dispatchers.IO) { select(library(context), now) }

    /**
     * The offline copy, or an empty list.
     *
     * Every failure mode — no file, a corrupt file, a signed-out device — is "no library", exactly
     * as it is at launch. A widget may not have an error state the app does not have.
     */
    private fun library(context: Context): List<Franchise> =
        runCatching { LibraryCache(dir = context.filesDir).load()?.response?.franchises }
            .getOrNull()
            .orEmpty()

    /** Pure. The unit-testable half. */
    fun select(library: List<Franchise>, now: Long): WidgetSnapshot {
        val boundary = nextBoundary(library, now)
        if (library.isEmpty()) {
            return WidgetSnapshot(WidgetContent.Blank(EmptyStateCopy.emptyToday), boundary)
        }

        val chosen = focusStack(library, now)
            .firstNotNullOfOrNull { f -> focusKind(f, now, emptySet())?.let { f to it } }
            ?: calmChoice(library, now)?.let { f -> calmFocusKind(f, now)?.let { f to it } }
            ?: return WidgetSnapshot(WidgetContent.Blank(EmptyStateCopy.emptyToday), boundary)

        val franchise = chosen.first
        val (kind: FocusKind, part) = chosen.second
        val slate = heroSlate(
            f = franchise,
            kind = kind,
            part = part,
            now = now,
            // A widget cannot show an Undo toast, so it never carries the committed frame either:
            // the advanced wording exists to make a mark's receipt land in the same frame as the
            // button that caused it, and there is no button here (PLAN Q14).
            committedEpisode = null,
            nextPremiere = franchise.nextPremiere(now),
        )
        val art = franchise.wideArt

        return WidgetSnapshot(
            content = WidgetContent.UpNext(
                UpNextItem(
                    franchiseId = franchise.id,
                    eyebrow = slate.eyebrow,
                    moment = slate.moment,
                    title = slate.title,
                    fact = slate.fact,
                    support = slate.support,
                    progress = slate.progress,
                    progressSpoken = slate.progressSpoken,
                    artUrl = art.url,
                    artIsPortrait = art.portraitSource,
                ),
            ),
            boundary = boundary,
        )
    }

    /** `TodayScreen.liveItems`, over a list. */
    private fun focusStack(library: List<Franchise>, now: Long): List<Franchise> {
        val airing = library.filter { it.releasingPart != null && it.tracksAirings }

        val outNow = airing
            .filter { f ->
                val part = f.releasingPart ?: return@filter false
                if (part.behind(now, f.timeAnchor) <= 0) return@filter false
                now - (part.lastAired(now, f.timeAnchor) ?: 0L) <= ShelfWindows.OUT_NOW
            }
            .sortedWith(
                compareByDescending<Franchise> { it.effectiveStatus == WatchStatus.WATCHING }
                    .thenByDescending { it.lastAired(now) ?: 0L },
            )

        val claimed = outNow.mapTo(HashSet()) { it.id }
        val keepWatching = library
            .filter {
                it.effectiveStatus == WatchStatus.WATCHING &&
                    !claimed.contains(it.id) &&
                    it.resumePart != null
            }
            .sortedWith(
                compareByDescending<Franchise> { it.continueBacklog }.thenBy { it.displayTitle },
            )

        return outNow + keepWatching
    }

    /**
     * Today's calm hero: `nextUp`, else the Watching show with the liveliest claim.
     *
     * The final `firstOrNull` fallbacks are what keep the promise in `CLAUDE.md` — *"Today is never
     * without a billboard"* — true on a library where nothing is releasing and nothing is Watching.
     */
    private fun calmChoice(library: List<Franchise>, now: Long): Franchise? {
        val nextUp = library
            .filter { it.releasingPart != null && it.tracksAirings }
            .mapNotNull { f -> f.nextAiring(now)?.let { f to it } }
            .minByOrNull { it.second }
            ?.first
        if (nextUp != null) return nextUp

        val watching = library.filter { it.effectiveStatus == WatchStatus.WATCHING }
        return watching
            .mapNotNull { f -> f.shelfState(now)?.let { f to it } }
            .minByOrNull { it.second.order }
            ?.first
            ?: watching.firstOrNull()
            ?: library.firstOrNull()
    }

    /**
     * The soonest upcoming airing anywhere on the calendar.
     *
     * Across the WHOLE library, not just the chosen show: a different show's drop can take over the
     * card, so the boundary that matters is the first one anywhere. `planned` shows are excluded by
     * `tracksAirings` for the same reason they are excluded from Schedule — a bookmark is not an
     * obligation.
     */
    fun nextBoundary(library: List<Franchise>, now: Long): Long? = library
        .asSequence()
        .filter { it.tracksAirings }
        .mapNotNull { f -> f.releasingPart?.upcomingAiring(now, f.timeAnchor) }
        .filter { it > now }
        .minOrNull()
}

// ---------------------------------------------------------------------------------------------
// MARK: - Artwork
// ---------------------------------------------------------------------------------------------

/**
 * Art for a `RemoteViews` tree, as a **reference** rather than as pixels.
 *
 * `AppWidgetServiceImpl` enforces a hard bitmap-memory ceiling across the *whole* `RemoteViews`
 * object — the documented formula is `screen_w × screen_h × 4 × 1.5` bytes, i.e. enough to fill the
 * screen one and a half times — and blowing it throws `IllegalArgumentException` from inside the
 * system, not from here. `SizeMode.Responsive` means several layouts share that one budget, so a
 * decoded banner per bucket is a real risk on a 1080 × 2400 phone.
 *
 * `ImageProvider(uri)` sends a **path**: the launcher opens the stream in its own process and
 * nothing crosses the Binder transaction. That is the pattern Google's own AppWidget sample
 * switches to the moment it hits the limit, and it is what this uses for the banner. Resource ids
 * (`ImageProvider(resId)`) stay for glyphs, which are tiny and which the launcher resolves itself.
 *
 * **The grant is the part that makes it work at all.** The launcher is a different application, so
 * without an explicit `grantUriPermission` the banner is simply blank on most launchers with no
 * error anywhere; without `FLAG_GRANT_PERSISTABLE_URI_PERMISSION` it goes blank again the next time
 * the launcher process restarts. The current launcher is resolved on every call because the user
 * can change it.
 */
internal object WidgetArt {

    /**
     * Fetch [url] through the app's own Coil loader, then hand back a `content://` string.
     *
     * Returns null for "no art" — a missing banner is a *layout*, not an error: the artless drawing
     * is a deliberate second design, not a degraded first one.
     */
    suspend fun contentUri(
        context: Context,
        loader: ImageLoader,
        url: String?,
        widthPx: Int,
        heightPx: Int,
    ): String? {
        if (url.isNullOrEmpty()) return null
        // Not `runCatching`: it is wrapped around a suspension point, and a `runCatching` around a
        // suspension point also swallows the `CancellationException` thrown while it is parked.
        return try {
            resolve(context, loader, url, widthPx, heightPx)
        } catch (cancellation: CancellationException) {
            throw cancellation
        } catch (_: Throwable) {
            // A banner that could not be fetched is the artless drawing, never an error state.
            null
        }
    }

    private suspend fun resolve(
        context: Context,
        loader: ImageLoader,
        url: String,
        widthPx: Int,
        heightPx: Int,
    ): String? {
        val request = ImageRequest.Builder(context)
            .data(url)
            // Decode to the widget's real box, never to the source's size: this file is the one
            // place in the app where an over-large decode is charged to a system-wide budget.
            .size(widthPx, heightPx)
            .precision(Precision.INEXACT)
            // The widget only ever needs the FILE. Keeping the bitmap would hold a banner-sized
            // allocation in the app's memory cache for a surface that is not on screen.
            .memoryCachePolicy(CachePolicy.DISABLED)
            .diskCachePolicy(CachePolicy.ENABLED)
            .build()

        val result = loader.execute(request)
        if (result !is SuccessResult) return null

        // Key off the RESULT's disk-cache key, not off the URL: any key transform on the loader
        // would otherwise make this miss every time and silently re-download on every render.
        val key = result.diskCacheKey ?: return null
        val cache = loader.diskCache ?: return null

        // The snapshot is a read lock on the cache entry; it is released here and the LAUNCHER
        // opens the file long afterwards. That is inherent to handing out a reference rather than
        // pixels, and the window is why `file.exists()` is re-checked after the close rather than
        // trusted from before it. A banner Coil evicts between the two is simply no art.
        val snapshot = cache.openSnapshot(key) ?: return null
        val file: File = try {
            snapshot.data.toFile()
        } finally {
            snapshot.close()
        }
        if (!file.exists()) return null

        val uri = FileProvider.getUriForFile(context, authority(context), file)
        grantToLaunchers(context, uri)
        return uri.toString()
    }

    /** `${applicationId}.fileprovider` — kept in step with the `<provider>` in the manifest. */
    private fun authority(context: Context): String = "${context.packageName}.fileprovider"

    private fun grantToLaunchers(context: Context, uri: android.net.Uri) {
        val home = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
        val hosts = context.packageManager
            .queryIntentActivities(home, PackageManager.MATCH_DEFAULT_ONLY)
            .mapNotNull { it.activityInfo?.packageName }
            .distinct()
        for (host in hosts) {
            runCatching {
                context.grantUriPermission(
                    host,
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or
                        Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
                )
            }
        }
    }

    /**
     * The decode box for the banner, in pixels.
     *
     * A home-screen widget is at most as wide as the screen, and the card's art is 16:9. Capped at
     * [MAX_ART_WIDTH_PX] so a tablet-class display does not spend four megabytes on a card that is
     * 110 dp tall.
     */
    fun decodeBox(context: Context): Pair<Int, Int> {
        val metrics = context.resources.displayMetrics
        val width = min(metrics.widthPixels.coerceAtLeast(MIN_ART_WIDTH_PX), MAX_ART_WIDTH_PX)
        return width to (width * 9 / 16)
    }

    private const val MIN_ART_WIDTH_PX = 480
    private const val MAX_ART_WIDTH_PX = 1080
}

// ---------------------------------------------------------------------------------------------
// MARK: - The live frame
// ---------------------------------------------------------------------------------------------

/**
 * The stream the composition observes while it is alive.
 *
 * `provideGlance`'s own KDoc is the reason this exists: *"the composition continues to run and
 * recompose for about 45 seconds… `update` and `updateAll` do not restart `provideGlance` if it is
 * already running… you should load initial data before calling `provideContent`, and then observe
 * your sources of data within the composition."* A value read once before `provideContent` is
 * frozen for the whole window — so a mark made in the app while the home screen is showing would
 * leave a stale card behind.
 *
 * One flow does both jobs a live window needs: it re-reads the offline copy (so a library change
 * lands) and it re-evaluates against a fresh `now` (so "in 3h 12m" counts down rather than lying).
 * The art is only re-resolved when the URL actually changes, so the ordinary tick is one file read.
 *
 * It emits **immediately**, before the first delay: the composition's own seed is whatever art this
 * instance had last time, which is right for the frame it takes this flow to fetch and wrong the
 * moment the card changes show.
 *
 * @param onArtResolved hands the resolved `content://` back to the caller, which stores it against
 *   this placed instance. That is the only thing Glance's per-instance state holds — see
 *   `PreviouslyWidget.stateDefinition`.
 */
internal fun widgetFrames(
    context: Context,
    loader: ImageLoader?,
    onArtResolved: suspend (uri: String?, forUrl: String?) -> Unit,
): Flow<WidgetFrame> = flow {
    val (artWidth, artHeight) = WidgetArt.decodeBox(context)
    var resolvedFor: String? = null
    var resolvedUri: String? = null
    var firstPass = true

    while (true) {
        val snapshot = WidgetData.read(context, System.currentTimeMillis())
        val url = snapshot.content.artUrl
        if (firstPass || url != resolvedFor) {
            resolvedUri = if (loader == null || url == null) {
                null
            } else {
                WidgetArt.contentUri(context, loader, url, artWidth, artHeight)
            }
            resolvedFor = url
            firstPass = false
            onArtResolved(resolvedUri, url)
        }
        emit(WidgetFrame(snapshot, resolvedUri))
        delay(FRAME_TICK_MS)
    }
}

/**
 * 30 s. The composition lives for about 45, so this is one extra frame — enough for a countdown to
 * move and for a mark made in the app to reach the card, and not enough to be a cost.
 */
private const val FRAME_TICK_MS = 30_000L

/** `Copy`'s own reading punctuation, so the spoken card sounds like every other spoken card. */
private const val SPOKEN_SEPARATOR = ". "

// ---------------------------------------------------------------------------------------------
// MARK: - When it re-renders
// ---------------------------------------------------------------------------------------------

/**
 * The refresh ladder, and the ceilings it is built around.
 *
 * | Trigger | Mechanism | Why |
 * |---|---|---|
 * | The app changed the library | [WidgetAmbientSync] → [refresh] | Free, instant, and the only one anybody notices |
 * | Sign-out | [WidgetAmbientSync.cancelAll] | The widget must not outlive the account |
 * | The next episode's air instant | one inexact `setWindow` alarm, re-armed on every render | The one moment the meaning changes on its own |
 * | Everything else | a 30-minute `PeriodicWorkRequest` | A missed alarm, a day rollover, a launcher restart |
 *
 * `android:updatePeriodMillis` is **0** in the provider XML. The platform caps it at once per 30
 * minutes anyway, it wakes the device to do it, and it would duplicate the WorkManager path — two
 * schedulers producing the same render.
 *
 * Exact alarms are not used and must not be: `USE_EXACT_ALARM` is restricted by Play policy to
 * apps whose core function is alarms, timers or calendars, and a five-minute window is
 * indistinguishable to somebody reading a card that says "in 3h 12m".
 *
 * **Never call `WorkManager.cancelAllWork()` anywhere in this app.** Glance runs its own
 * compositions through WorkManager; a blanket cancel stops every widget updating, silently.
 */
object WidgetRefresh {

    /** Namespaced so no blanket sweep can take Glance's own sessions with it. */
    private const val PERIODIC_WORK = "previously.widget.up-next.periodic"

    private const val ALARM_REQUEST_CODE = 0x7d1

    /** Five minutes. The system may fire anywhere inside it; nobody reading a card can tell. */
    private val ALARM_WINDOW_MS = TimeUnit.MINUTES.toMillis(5)

    private const val PERIOD_MINUTES = 30L

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    /** Re-render every placed instance now, and re-arm the boundary alarm from what it says. */
    suspend fun refresh(context: Context) {
        val app = context.applicationContext
        try {
            PreviouslyWidget().updateAll(app)
        } catch (cancellation: CancellationException) {
            throw cancellation
        } catch (_: Throwable) {
            // A launcher that refused an update is not something this app can report, or should.
        }
        armBoundary(app)
    }

    /** [refresh] for callers that are not in a coroutine. Fire-and-forget by design. */
    fun refreshAsync(context: Context) {
        val app = context.applicationContext
        scope.launch { refresh(app) }
    }

    /**
     * Install the periodic net. Idempotent — `KEEP` leaves an already-enqueued schedule alone, so
     * this is safe to call from `onEnabled`, from app start, and from a receiver.
     *
     * **No network constraint**, deliberately, and this diverges from the research note: the widget
     * reads the offline copy and never touches the server, so requiring connectivity would strand
     * the card on exactly the flight where its "Airs in 20 min" quietly went stale.
     */
    fun schedule(context: Context) {
        val app = context.applicationContext
        runCatching {
            WorkManager.getInstance(app).enqueueUniquePeriodicWork(
                PERIODIC_WORK,
                ExistingPeriodicWorkPolicy.KEEP,
                PeriodicWorkRequestBuilder<WidgetRefreshWorker>(PERIOD_MINUTES, TimeUnit.MINUTES)
                    .setConstraints(Constraints.Builder().setRequiresBatteryNotLow(false).build())
                    .build(),
            )
        }
    }

    /**
     * Arm one inexact alarm at the next episode boundary, replacing whatever was armed before.
     *
     * One alarm, never a repeating one: each render works out the *new* next boundary and re-arms,
     * so the schedule follows the library instead of guessing at it.
     */
    suspend fun armBoundary(context: Context) {
        val app = context.applicationContext
        val alarms = app.getSystemService(AlarmManager::class.java) ?: return
        val pending = boundaryIntent(app)
        // **No card, no wake-up.** The boundary alarm buys one thing — a re-render at the instant
        // the card's own words stop being true — so with nothing placed it is a wake-up with no
        // surface, which is exactly what `onEnabled`/`onDisabled` own the schedule to avoid.
        //
        // The check belongs HERE, at the one place that arms, rather than at each caller, because
        // every path back into it is a path that would otherwise re-arm behind the schedule's back:
        // `cancel()` cancels the alarm and then calls `refreshAsync`, which lands here and would
        // put it straight back while the user still has a library; `WidgetAmbientSync` re-arms on
        // every confirmed library change whether or not a card exists; and the boundary receiver
        // re-arms itself by design. Gating one caller would have left the other two.
        val at = if (WidgetPresence.anyPlaced(app)) {
            WidgetData.read(app, System.currentTimeMillis()).boundary
        } else {
            null
        }
        if (at == null) {
            runCatching { alarms.cancel(pending) }
            return
        }
        // `RTC_WAKEUP` because an air time is a wall-clock instant from the server: it has to
        // survive a timezone change, and `ELAPSED_REALTIME` would drift straight through one.
        runCatching { alarms.setWindow(AlarmManager.RTC_WAKEUP, at, ALARM_WINDOW_MS, pending) }
    }

    /** Sign-out, or the last instance removed. Nothing armed by this account may survive it. */
    fun cancel(context: Context) {
        val app = context.applicationContext
        runCatching {
            app.getSystemService(AlarmManager::class.java)?.cancel(boundaryIntent(app))
        }
        runCatching { WorkManager.getInstance(app).cancelUniqueWork(PERIODIC_WORK) }
        // The card itself still has to stop showing the previous account's episode.
        refreshAsync(app)
    }

    /** `FLAG_IMMUTABLE` is mandatory from API 31 and correct everywhere: nobody may rewrite this. */
    private fun boundaryIntent(context: Context): PendingIntent = PendingIntent.getBroadcast(
        context,
        ALARM_REQUEST_CODE,
        Intent(context, WidgetBoundaryReceiver::class.java)
            .setAction(WidgetBoundaryReceiver.ACTION_BOUNDARY),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )
}

/** The 30-minute net. It reads the offline copy, so it needs neither network nor auth. */
class WidgetRefreshWorker(
    appContext: Context,
    params: WorkerParameters,
) : CoroutineWorker(appContext, params) {

    override suspend fun doWork(): Result {
        WidgetRefresh.refresh(applicationContext)
        return Result.success()
    }
}

// ---------------------------------------------------------------------------------------------
// MARK: - The seam into AppModel
// ---------------------------------------------------------------------------------------------

/**
 * The widget as an [AmbientSync] — the same seam the episode-alert scheduler uses.
 *
 * `AppModel` calls `sync` after every **confirmed** library change (a successful `reload()`, a
 * confirmed status write, a confirmed removal) and `cancelAll` on sign-out. That is exactly the set
 * of moments the card's content can change, so the widget needs no hook of its own and `AppModel`
 * needs no knowledge of Glance.
 *
 * `sync` must not throw — it is awaited inside the *successful* branch of `reload()`, where an
 * escaping exception would be read as a library failure and paint "couldn't refresh" over a library
 * that had just arrived intact. Everything here is wrapped for that reason and not out of caution.
 *
 * There is one seam and there will be two implementations (this and the alert scheduler); compose
 * them at the graph rather than picking one:
 *
 * ```kotlin
 * val ambient = CompositeAmbientSync(AiringAlerts(app), WidgetAmbientSync(app))
 * ```
 */
class WidgetAmbientSync(context: Context) : AmbientSync {

    private val app = context.applicationContext

    override suspend fun sync(library: List<Franchise>, now: Long) {
        try {
            // A user who has never placed a card must not pay for one. `onEnabled` installs the
            // 30-minute net the moment the first instance is placed and `onDisabled` tears it down
            // with the last — this path only has to keep an EXISTING card honest, so with none
            // placed there is nothing here to do and no schedule to install.
            //
            // Without the gate every signed-in launch enqueued a 30-minute `PeriodicWorkRequest`
            // and armed an `RTC_WAKEUP` alarm on a device with no widget on any home screen, which
            // is precisely the cost `onEnabled`/`onDisabled` exist to bound.
            if (!WidgetPresence.anyPlaced(app)) return
            WidgetRefresh.schedule(app)
            WidgetRefresh.refresh(app)
        } catch (cancellation: CancellationException) {
            // Cancellation is not a failure and `AppModel.syncAmbient` already knows that. What it
            // must never see from here is anything else.
            throw cancellation
        } catch (_: Throwable) {
            // Deliberately invisible: a card that did not re-render is not a library failure, and
            // an exception escaping here would paint "couldn't refresh" over a library that had
            // just arrived intact.
        }
    }

    override fun cancelAll() {
        runCatching { WidgetRefresh.cancel(app) }
    }
}

/**
 * The app's Coil loader, or null when this process has no graph.
 *
 * Never builds a second `ImageLoader`: two loaders over one disk-cache directory is a corrupted
 * cache, and the app's own loader already carries the art `OkHttpClient` that must never see the
 * Clerk bearer token. A process with no graph simply draws the artless card.
 */
internal fun widgetImageLoader(context: Context): ImageLoader? = runCatching {
    // `graph` is `lateinit`. A broadcast always arrives after `Application.onCreate`, so this is
    // not expected to fire — but a widget that throws on a cold process start would take the whole
    // card down for the sake of a photograph.
    (context.applicationContext as? PreviouslyApp)?.graph?.imageLoader
}.getOrNull()
