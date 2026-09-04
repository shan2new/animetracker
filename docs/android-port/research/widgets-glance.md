# Home-screen widget with Glance

**Status:** research / decision note. Written **2026-09-04**. Every version, API signature and quoted
sentence below was checked against a primary source on that date — release notes, `developer.android.com`
reference pages, the AndroidX source on `androidx-main`, or the official `android/user-interface-samples`
repo. Links and dates are in §14.

**Scope:** the home-screen widget for the Android port of *Previously.* — the framework choice, what it
can draw, how it gets art and data, when it refreshes, how it stays on the app's own dark palette
instead of the user's wallpaper, and how a tap lands on the right show. It also settles the
*separate* question of what happens to the iOS **Live Activity**, because that is what
`ios/Widgets/AniTrackWidgets.swift` actually contains today (see §2).

Companion notes: `compose-architecture.md` (toolchain, state holder, Navigation 3),
`../spec/design-tokens.md` (the palette), `../spec/today.md` (the hero this widget is a compression of),
`../spec/appmodel.md` §10.3 (`pendingOpen`, the alert-tap route this widget must reuse).

---

## 1. Recommendation up front

| Decision | Pick | One-line reason |
|---|---|---|
| Framework | **Jetpack Glance**, `androidx.glance:glance-appwidget:1.2.0` (stable, **26 Aug 2026**) | Google's documented recommendation, it is the Compose runtime so the port's `CompositionLocal` theming and `collectAsState` habits transfer, and it is the only path that inherits RemoteCompose as the platform moves to it. |
| Not | `1.3.0-alpha02` (1 Jul 2026), `androidx.glance.adaptive:*:1.0.0-alpha01` (26 Aug 2026) | Alpha. Revisit `adaptive` when the port grows a Wear target; revisit 1.3.x when snap-scrolling or an API 37-only flourish is actually wanted. |
| Widget | **One** widget — "Up Next", the Today hero compressed. 4×2 (`targetCellWidth/Height`), resizable, `SizeMode.Responsive` with two breakpoints | The app has exactly one urgent fact. A second widget is a Library shelf nobody glances at. |
| Art | **Coil → disk cache → `FileProvider` content URI → `ImageProvider(uri)`**, fetched in a `CoroutineWorker`, never `ImageProvider(bitmap)` for the banner | Bitmaps count against a hard per-widget RemoteViews budget of `screen_w × screen_h × 4 × 1.5` bytes; a content URI does not. This is the pattern in Google's own sample. |
| Refresh cadence | **Event-driven `updateAll()` from the app + one `PeriodicWorkRequest` at 30 min + one inexact `AlarmManager.setWindow` fired at each episode boundary.** `updatePeriodMillis="0"` in the XML | `updatePeriodMillis` is capped by the platform at "not more than once every 30 minutes"; WorkManager's periodic floor is 15 min; exact alarms need a Play-policy-gated permission this app cannot justify. |
| App ↔ widget data | **The widget reads the app's own persisted library cache** (the Android analogue of iOS `library-cache.json`) — a DataStore/Room read inside `provideGlance`, observed with `collectAsState`. `PreferencesGlanceStateDefinition` is used **only** for per-instance widget state (the resolved art URI, the chosen franchise) | Same process, same files — there is no App Group / shared container problem to solve. The trap is the opposite one: the widget process may be cold, so in-memory `AppModel` state is invisible to it. |
| Theming | **`GlanceTheme(colors = ColorProviders(previouslyDarkScheme))`** from `androidx.glance:glance-material3`, a *fixed* scheme (no day/night pair) | Glance's default `LocalColors` is `DynamicThemeColorProviders` — **the widget picks up Material You wallpaper colours unless you pass `colors` explicitly.** The fixed-scheme overload is documented as "a fixed scheme and does not have day/night modes", which is exactly the dark-only contract. |
| Type | **System font.** Outfit does not ship to the widget | "Custom fonts in apps aren't supported" — a RemoteViews constraint, not a Glance one. The iOS Live Activity already made the same concession in its own header comment; be consistent and do not bitmap-render text. |
| Interaction | `actionStartActivity(Intent(ACTION_VIEW, "previously://franchise/<id>".toUri()))` → `MainActivity.onNewIntent` → the **existing** `pendingOpen` single-shot channel | Reuses the notification-tap route the spec already defines, and is testable from `adb shell am start`. |
| Mark-as-watched from the widget | **v1: no.** Tap opens the show | A widget write needs the whole `sendProgress` serialisation + `SyncCenter` retry policy to be reachable from a cold process. It is a v1.1 feature with a real design cost, not a freebie. |
| Live Activity | **Not a widget.** Port it to **Android 16 Live Updates** (`Notification.ProgressStyle`, optionally promoted) with a plain ongoing notification below 16 | Different surface, different API, different note. Flagged here so it is not silently dropped. |

**Confidence: medium-high.** The framework call, the image pattern, the update ceilings, the theming
default and the deep-link route are all read off primary sources. Two things are judgement, not
evidence, and are called out in §13: whether a widget is worth building at all before launch, and
whether shipping on Glance 1.2.0 in the last months before RemoteCompose becomes the default
rendering path is timing you want.

---

## 2. What is actually being ported (read this before designing anything)

`ios/Widgets/AniTrackWidgets.swift` is 122 lines and its `WidgetBundle` contains **one** entry:

```swift
@main
struct AniTrackWidgetBundle: WidgetBundle {
    var body: some Widget {
        AiringLiveActivity()          // ← the only member
    }
}
```

There is **no `StaticConfiguration` / `AppIntentConfiguration` home-screen widget on iOS.** So this
note is not a port of an existing surface; it is two decisions wearing one name:

1. **A new Android home-screen widget** (§3–§10). Home-screen widgets are a first-class, discoverable
   Android surface in a way that iOS widgets were not when this app was built; the platform expects
   one, and *Previously.* has an unusually good widget premise (a single urgent fact: what airs next).
   This note designs it.
2. **The Live Activity's Android equivalent** (§11) — the ticking "Re:ZERO · Episode 19 · 04:12"
   lock-screen surface. That is **not** a widget on Android. It is a notification. Do not let the word
   "widget" carry it into the wrong file.

Two design facts from the iOS file that survive the port verbatim:

- The extension **does not bundle the Outfit fonts or the `Theme` namespace**; it inlines
  `accent 0xF0A24E` and `backdrop 0x0B0B0E` and uses the system font. Glance forces the same
  concession for a different reason (§8), so this is a continuity, not a regression.
- The copy is the app's own — `"Episode 19"`, never `"E19"`; `"Out now"` once the instant passes.
  `Copy` is the single home for user-facing strings (`CLAUDE.md`), and the widget is inside that rule.

---

## 3. Glance in September 2026 — versions and what changed

### 3.1 The version table (checked 2026-09-04 against the Glance release page)

| Artifact | Version | Date | Status |
|---|---|---|---|
| `androidx.glance:glance` / `:glance-appwidget` / `:glance-material3` | **1.2.0** | **26 Aug 2026** | **Stable — take this** |
| " | 1.3.0-alpha02 | 1 Jul 2026 | Alpha |
| " | 1.3.0-alpha01 | 19 May 2026 | Alpha |
| " | 1.1.1 | 16 Oct 2024 | Stable (previous) |
| `androidx.glance.adaptive:adaptive-{core,appwidget,wear}` | 1.0.0-alpha01 | 26 Aug 2026 | Alpha — new library |
| `androidx.glance:glance-wear-tiles` | 1.0.0-alpha07 | — | Alpha, **deprecated** in favour of `androidx.glance.wear` |

Two things worth naming plainly, because they look alarming in isolation:

- **1.1.0 → 1.2.0 took 26 months** (12 Jun 2024 → 26 Aug 2026), with `1.2.0-rc01` sitting from
  3 Dec 2025 to the stable cut. That is a slow library. It is *not* an abandoned one: 1.3.0 alphas
  shipped in that window, `glance.adaptive` was started, and Glance is the framework named in
  Google's I/O '26 widget story (§3.3). But do not plan around a fast Glance release train.
- **1.3.0-alpha01's own note reads "Updated Compose `compileSdk` to API 37. This means that a minimum
  AGP version of 9.2.0 is required when using Compose."** The port is already on `compileSdk 37` /
  AGP 9.4.0 (`compose-architecture.md` §2), so 1.3.x is *technically* takeable. Take 1.2.0 anyway;
  nothing in 1.3.x is load-bearing here (its headline is snap scrolling on API 37+, §4.4).

### 3.2 Dependency floors (read out of the published POMs, 2026-09-04)

`glance:1.2.0` and `glance:1.3.0-alpha02` both declare:

| Transitive dep | Floor in the POM |
|---|---|
| `androidx.compose.runtime:runtime` | 1.6.0 |
| `androidx.compose.ui:ui-graphics` / `ui-unit` | 1.6.0 |
| `androidx.datastore:datastore-preferences` (+ `-core`, `datastore-core`) | 1.0.0 |
| `androidx.work:work-runtime` / `-ktx` | 2.7.1 |

Meaning: **`glance-appwidget` drags in DataStore-Preferences and WorkManager whether you use them or
not** — they are how Glance stores per-widget state and how it runs `provideGlance`. Gradle resolves
these upward to whatever the port already declares (Compose 1.12.0 via BOM 2026.08.00). Floors this
old have not been a source of breakage, but the Compose-runtime pairing is the one thing to smoke-test
on the first build.

`minSdk`: Glance moved from API 21 to **API 23** at `1.2.0-beta01` (27 Aug 2025). The port's floor is
31, so this is moot — but it does mean nothing in Glance forces the floor upward.

### 3.3 The RemoteCompose transition — the reason this call has a shelf life

Under a widget, `RemoteViews` has always been an XML view hierarchy inflated in the *launcher's*
process. The platform is replacing that transport:

- `RemoteViews(RemoteViews.DrawInstructions)` — "A data parcel that carries the instructions to draw
  the RemoteViews, **as an alternative to XML layout**" — is **added in API level 35** (Android 15)
  per the `RemoteViews` reference. Its doc carries a hard number: *"The total raw byte size of the
  DrawInstructions payload must not exceed the strict limit of 21MB (defined by
  `AppWidgetServiceImpl.MAX_REMOTE_COMPOSE_SIZE`)."*
- Google's **"Building Premium Android Experiences at Google I/O '26"** (2 Jun 2026) puts Glance at
  the top of that stack: *"By using a consistent, Compose-based model, you can elevate the content
  most important to your users straight to the phone's home screen, Wear Widgets (previously Tiles!),
  and cars with a familiar workflow."* RemoteCompose is described as the engine — the thing that
  "renders natively on remote surfaces" — not the thing you write against.
- Glance 1.3.0-alpha01's notes bump "api and remote compose versions" and add
  "snap scrolling support **when remote compose is used**". `androidx.glance.adaptive` (alpha01,
  26 Aug 2026) is explicitly *"template-first `RemoteCompose` widgets … across multiple form factors"*.

**What this means for the decision:** writing `RemoteViews` by hand in 2026 is writing against the
transport that is being replaced. Writing Glance is writing against the API that will sit on top of
whichever transport the OS picks — the docs already state that on Android 15 and below Glance
"automatically provide[s] safe fallback options". That is the single strongest argument for Glance
and it has nothing to do with Kotlin ergonomics.

**Caveat, stated plainly:** the `adaptive` library appearing on the *same day* as Glance 1.2.0 stable
is ambiguous. It may be a Wear/car-focused sibling, or it may be where Glance's centre of gravity
moves. The docs do not say. `glance-appwidget` is not deprecated and is what every current widget
guide teaches — so 1.2.0 is the safe read — but re-check this before a 2027 refactor. It is open
question **Q4** in §13.

---

## 4. What Glance can and cannot render, versus Compose

This is the part that breaks people who assume "it's Compose". It is the *Compose runtime* driving a
`RemoteViews` tree. The constraint set is the platform's, not the library's.

### 4.1 The floor: what `RemoteViews` supports at all

Quoted verbatim from the `android.widget.RemoteViews` reference (fetched 2026-09-04):

> RemoteViews is limited to support for the following layouts: `AdapterViewFlipper` `FrameLayout`
> `GridLayout` `GridView` `LinearLayout` `ListView` `RelativeLayout` `StackView` `ViewFlipper`
> And the following widgets: `AnalogClock` `Button` `Chronometer` `ImageButton` `ImageView`
> `ProgressBar` `TextClock` `TextView`
> As of API 31, the following widgets and layouts may also be used: `CheckBox` `RadioButton`
> `RadioGroup` `Switch`
> **Descendants of these classes are not supported.**

Everything a Glance widget can ever draw is a composition of that list. There is no `Canvas`, no
custom `View`, no shader, no `RenderEffect`, no `Modifier.blur`. **The whole `glassChrome` /
`HeroTopVeil` / hardened-bar language of the app is unavailable on this surface** — which is fine,
because a widget sits on wallpaper and has no chrome to veil, but it means the widget cannot be
"the hero, smaller". It is a different drawing, built from the same tokens.

### 4.2 The Glance composable set

`androidx.glance` + `androidx.glance.appwidget` (from the package reference, 2026-09-04):

| Have | Notes |
|---|---|
| `Box` `Column` `Row` `Spacer` | → `RelativeLayout` / `LinearLayout`. `Box` is the only overlay primitive. |
| `Text` | `TextStyle(color, fontSize, fontWeight, fontStyle, textAlign, textDecoration, fontFamily)` |
| `Image` | `ImageProvider(resId | bitmap | Icon | Uri)`; `contentScale`, `colorFilter`, `alpha` (1.2.0+) |
| `Button`, `ImageButton` (`components`) | plus `FilledButton` / `OutlineButton` / `CircleIconButton` in `androidx.glance.appwidget.components` |
| `LazyColumn` / `LazyRow` | → `ListView` via RemoteViews collections |
| `CheckBox` `Switch` `RadioButton` | API 31+ stateful, with backport |
| `CircularProgressIndicator` `LinearProgressIndicator` | **indeterminate only** — see below |
| `Scaffold` `TitleBar` (`components`) | Scaffold sets the widget background + corner radius for you |
| `AndroidRemoteViews` | the escape hatch (§4.5) |

| Do **not** have | Consequence for this app |
|---|---|
| Any determinate progress bar in Glance | `ProgressBanner`'s inset progress bar — the app's *one* "where you are" primitive — has no Glance composable. `LinearProgressIndicator` is documented as "indeterminate". **Draw the bar as two nested `Box`es with `background` + `width`**, sized from `LocalSize.current`. That is the correct workaround and it is cheap. |
| Custom fonts | *"Custom fonts in apps aren't supported"*; `fontFamily` takes only Monospace / SansSerif / Serif. Outfit is out (§8.4). |
| `Canvas`, `drawBehind`, `graphicsLayer`, `blur` | No gradients-by-shader. A gradient must be a `@drawable` XML `<shape><gradient>` used as `ImageProvider(R.drawable.…)` or a `background(imageProvider = …)`. |
| Animation of any kind | `ThemeMotion` does not exist here. A widget update is a hard cut. `ArtHeader(drift:)` is meaningless. |
| Arbitrary `Modifier` order semantics | `GlanceModifier` is a flat property bag translated to view attributes, not a draw chain. `padding` then `background` does not do what it does in Compose. |
| Horizontal gestures | *"The only gestures available for widgets are touch and vertical swipe"* (App widgets overview) — horizontal is reserved for home-screen paging. **A `ShelfCard` shelf cannot be a widget.** This is why "Up Next" is one card, not a carousel. |
| Nested scrolling | documented limitation of `LazyColumn` → `ListView` |
| `remember` across updates | the composition is torn down (§6.2) |

### 4.3 Sizing

`SizeMode.Single` (one layout, `LocalSize` = the metadata min size) / `SizeMode.Responsive(setOf(DpSize…))`
(the system picks the best fit; Android 12+ maps each bucket at bind time, below 12 it re-composes per
size) / `SizeMode.Exact` (a composition per resize; the docs warn about "complete widget recreation on
size change (performance issues possible)" and that "available size differs by launcher implementation").

**Take `SizeMode.Responsive` with exactly two buckets** — a 4×2 and a 5×3 — and branch on
`LocalSize.current.height`. `Exact` is only worth it when the art must be decoded at the exact pixel
size, which the `FileProvider`-URI path (§5) removes the need for.

### 4.4 Snap scrolling (1.3.0-alpha02+, API 37+)

`LazyColumn(verticalScrollMode = VerticalScrollMode.SnapScrollMatchHeight(height))` needs
Glance ≥ 1.3.0-alpha02, `compileSdk ≥ 37`, and `Build.VERSION.SDK_INT >= 37` at runtime, and uses
Remote Compose rather than RemoteViews. **Not needed here** — the widget is one card. Noted so nobody
reaches for 1.3.x thinking they need it.

### 4.5 The escape hatch: `AndroidRemoteViews`

When Glance has no composable for something RemoteViews *does* support, drop through:

```kotlin
// Overload 1 — a raw RemoteViews beside composables
val packageName = LocalContext.current.packageName
Column(modifier = GlanceModifier.fillMaxSize()) {
    Text("Isn't that cool?")
    AndroidRemoteViews(RemoteViews(packageName, R.layout.example_layout))
}

// Overload 2 — Glance content inside a RemoteViews container
AndroidRemoteViews(
    remoteViews = RemoteViews(packageName, R.layout.my_container_view),
    containerViewId = R.id.example_view
) {
    Column(modifier = GlanceModifier.fillMaxSize()) {
        Text("My title")
        Text("Maybe a long content...")
    }
}
```

The container "must be a `ViewGroup`", "any existing children … are removed and replaced", and the
`ViewGroup` "must be supported by `RemoteViews`". This is how you would reach `Chronometer` or
`TextClock` (§9.3) — the two self-updating views Glance does not expose.

---

## 5. Remote images — the one thing that will bite

### 5.1 The budget

The launcher does not fetch your art; you push it across a Binder transaction. AOSP's
`AppWidgetServiceImpl` enforces a bitmap-memory ceiling and throws
`IllegalArgumentException: RemoteViews for widget update exceeds maximum bitmap memory usage
(used: …, max: …)`. The documented formula is **`screen_width × screen_height × 4 × 1.5` bytes**
(i.e. `6 × w × h`) — *the memory required to fill the screen 1.5 times*, across the **whole**
`RemoteViews` object, and `SizeMode.Responsive` means several layouts are in that one object.

On the QA emulator (`PreviouslyQA_API36`, 1280 × 2856 px, from `TOOLCHAIN.md`) that is
`1280 × 2856 × 6` ≈ **21.9 MB**. Generous — until you notice a 16:9 banner at 4×2 on a xxhdpi device
is ~1000 × 560 px ≈ 2.2 MB decoded, and `SizeMode.Responsive` with 2 buckets plus a poster fallback
composite is already 3 bitmaps per update. It is survivable but it is not free, and on a 1080 × 2400
budget phone the ceiling is ~15.5 MB.

**Google's own sample says so in a code comment**
(`android/user-interface-samples/AppWidget/.../ImageGlanceWidget.kt`):

> *"Note: When using bitmaps directly your might reach the memory limit for RemoteViews. If you do
> reach the memory limit, you'll need to generate a URI granting permissions to the launcher."*

### 5.2 The pattern to copy — content URI, not bitmap

`ImageProvider(uri: Uri)` sends a **reference**; the launcher opens the stream itself, so the bitmap
never crosses the Binder transaction and never counts against the budget. That is the pattern to
adopt for the banner. Keep `ImageProvider(resId)` for glyphs (the docs recommend resource ids
generally: *"Provide resource IDs directly to reduce RemoteViews size"*) and reserve
`ImageProvider(bitmap)` for something genuinely small.

The sample's `ImageWorker` is the canonical shape. Translated to Coil 3 and this app's `WideArt`
(`portraitArt` / `landscapeArt` / `wideArt` — never `cover`/`banner` in a view, per `CLAUDE.md`):

Coil is **3.6.1** (1 Sep 2026; 3.6.0 on 26 Aug 2026 moved Coil to compileSdk 37 / Kotlin 2.4.10 /
Compose 1.12.0 — the same floor the port is on). Inject the app's `ImageLoader` through Hilt rather
than reaching for the singleton, so the widget shares the app's disk cache and its bucketed
`MemoryCache.Key` interceptor (see `../spec/chrome-images.md`).

```kotlin
// app/src/main/java/app/previously/widget/UpNextArtWorker.kt
@HiltWorker
class UpNextArtWorker @AssistedInject constructor(
    @Assisted private val context: Context,
    @Assisted params: WorkerParameters,
    private val loader: ImageLoader,          // the app's own Coil 3 loader
) : CoroutineWorker(context, params) {

    override suspend fun doWork(): Result = try {
        val url = inputData.getString(KEY_URL)!!
        val wPx = inputData.getInt(KEY_W, 0)
        val hPx = inputData.getInt(KEY_H, 0)

        val request = ImageRequest.Builder(context)
            .data(url)
            .size(wPx, hPx)                 // decode to the widget's real box, not the source size
            .precision(Precision.INEXACT)
            .memoryCachePolicy(CachePolicy.DISABLED)   // the widget only needs the file on disk
            .build()

        val result = loader.execute(request)
        if (result is ErrorResult) throw result.throwable

        // Coil 3 renamed DiskCache.get/edit to openSnapshot/openEditor. Key off the RESULT's
        // diskCacheKey, not the URL — a custom key transform would otherwise miss.
        val key = (result as SuccessResult).diskCacheKey ?: url
        val contentUri = loader.diskCache?.openSnapshot(key)?.use { snapshot ->
            val file = snapshot.data.toFile()
            val uri = FileProvider.getUriForFile(context, "$AUTHORITY", file)
            // The launcher is a different app: it needs an explicit read grant, and the current
            // launcher must be resolved every time (the user can change it).
            context.packageManager.resolveActivity(
                Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME),
                PackageManager.MATCH_DEFAULT_ONLY,
            )?.activityInfo?.packageName?.let { launcher ->
                context.grantUriPermission(
                    launcher, uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or
                        Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
                )
            }
            uri.toString()
        } ?: return Result.retry()

        GlanceAppWidgetManager(context)
            .getGlanceIds(UpNextWidget::class.java)
            .forEach { id ->
                updateAppWidgetState(context, id) { prefs -> prefs[ArtUriKey] = contentUri }
            }
        UpNextWidget().updateAll(context)
        Result.success()
    } catch (e: Exception) {
        if (runAttemptCount < 5) Result.retry() else Result.failure()
    }
}
```

and in the composition, the sample's own dispatcher:

```kotlin
private fun artProvider(path: String): ImageProvider =
    if (path.startsWith("content://")) ImageProvider(path.toUri())
    else ImageProvider(BitmapFactory.decodeFile(path))
```

`FileProvider` needs the usual manifest entry plus a `cache-path` root that covers Coil's disk cache
directory:

```xml
<provider
    android:name="androidx.core.content.FileProvider"
    android:authorities="app.previously.fileprovider"
    android:exported="false"
    android:grantUriPermissions="true">
    <meta-data android:name="android.support.FILE_PROVIDER_PATHS"
               android:resource="@xml/file_paths" />
</provider>
```

```xml
<!-- res/xml/file_paths.xml -->
<paths>
    <cache-path name="image_cache" path="image_cache/" />
</paths>
```

### 5.3 The landscape-vs-portrait rule still applies

`CLAUDE.md`: *"Landscape frames never `.fill` a portrait cover"* — a show with no banner is
"composited whole on its own blurred ground". A widget cannot blur (§4.1). So the widget's rule is
narrower and must be written down:

- `wideArt` present → fill the 16:9 frame with it.
- No `wideArt` → **do not stretch the poster.** Draw the poster at its own ratio, leading-aligned,
  on a flat `surfaceFlat` (`#171719`) ground, with the copy beside it. That is a second layout, not a
  degraded first one. (A pre-blurred ground could be baked into the same worker as a second
  `FileProvider` file if the flat ground reads cheap — measure before spending it.)

### 5.4 Failure is a state, not an exception

The widget cannot show a spinner forever. Follow the app's own state grammar
(`EmptyState` / `InlineNotice` copy rules in `CLAUDE.md`): no art → the copy on flat ground; no data
at all → one line in the app's voice ("Nothing scheduled", "Couldn't load your library"), never a
stack trace and never the word "server". Glance has an error path of its own —
`GlanceAppWidget(errorUiLayout: Int)` / `onCompositionError` — whose default *"creates a `RemoteViews`
from `errorUiLayout` and sets this as the widget's content"*. **Override `onCompositionError`** to log
and to draw the app's own line instead of the stock Glance error layout.

---

## 6. Update cadence, and the ceilings you cannot argue with

### 6.1 The three ceilings

| Mechanism | Ceiling | Source |
|---|---|---|
| `android:updatePeriodMillis` | *"Updates requested with `updatePeriodMillis` will **not be delivered more than once every 30 minutes**."* Also: *"The AppWidget manager may place a limit on how often a AppWidget is updated."* | `AppWidgetProviderInfo` reference |
| `WorkManager` `PeriodicWorkRequest` | 15-minute minimum interval; Glance's own doc says use it *"for more frequent updates (e.g. every 15 minutes)"* | Manage & update GlanceAppWidget |
| Exact `AlarmManager` | `SCHEDULE_EXACT_ALARM` is **not pre-granted** for targetSdk ≥ 33 and must be granted by the user; `USE_EXACT_ALARM` is normal-permission but is Play-policy-restricted to apps whose *"user-facing function … requires precisely-timed actions"* (alarm clocks, calendar reminders) | Schedule alarms / Exact alarms denied by default |

**A TV tracker is not an alarm clock.** Do not declare `USE_EXACT_ALARM` for widget freshness; it is a
policy fight you will lose at review. Inexact `AlarmManager.set` / `setWindow` needs no permission and
is the right tool for "wake up somewhere near 19:30 and re-render".

### 6.2 The Glance session lifecycle (this is the non-obvious part)

Straight from the `provideGlance` KDoc:

> *"Before `provideContent` is called, `provideGlance` is subject to the typical
> `androidx.work.WorkManager` time limit (currently ten minutes). After `provideContent` is called,
> the composition continues to run and recompose for about **45 seconds**. When UI interactions or
> update requests are received, additional time is added to process these requests. Note: `update`
> and `updateAll` do **not** restart `provideGlance` if it is already running. As a result, you should
> load initial data before calling `provideContent`, and then observe your sources of data within the
> composition (e.g. `collectAsState`). This ensures that your widget will continue to update while the
> composition is active. When you update your data source from elsewhere in the app, make sure to call
> `update` in case a Worker for this widget is not currently running."*

Three consequences:

1. **`remember { }` is worthless across updates.** Nothing survives 45 s. Every displayed value comes
   from a persisted source or from `currentState`.
2. **Reactive updates work — but only for ~45 s at a time.** `collectAsState` on a Flow is real and
   is the pattern the docs prescribe; it is a *live window*, not a subscription. Outside the window
   you must call `updateAll()`.
3. **`updateAll()` while a session is live is a no-op for restarting `provideGlance`.** If your data
   load lives *before* `provideContent`, a fresh `updateAll()` during a live session will not re-run
   it. Put the load in a Flow the composition observes, and it stops mattering.

### 6.3 The cadence this app should ship

The app's freshness ladder (`CLAUDE.md`: `airedByNow` / `behind` / `upcomingAiring`, "a slot in the
part's own `airings` list that has struck IS an aired episode") is **derived from data the widget
already has** — it does not need a network call to flip "Airs at 7:30 PM" into "Out now". It needs a
*re-render at the right moment*. So:

| Trigger | Mechanism | Why |
|---|---|---|
| The app changed the library (mark, add, remove, reload) | `UpNextWidget().updateAll(context)` from the same place that writes the library cache | Free, instant, and the only one users actually notice |
| Sign-out / teardown | `updateAll()` after clearing the cache | The widget must not outlive the account — the iOS `teardown()` rule |
| The next episode's air instant | one-shot **inexact** `AlarmManager.setWindow(RTC_WAKEUP, airsAt, 5.minutes, pi)` → a `BroadcastReceiver` → `updateAll()`, re-armed each render for the *new* next boundary | This is the only moment the widget's meaning changes on its own. One alarm, not a repeating one. |
| Everything else | one `PeriodicWorkRequest(30, MINUTES)` with `NetworkType.CONNECTED`, `ExistingPeriodicWorkPolicy.KEEP` | Catches a missed alarm, a server-side schedule change, day rollover. 30 min matches the platform's own `updatePeriodMillis` ceiling — going below it buys nothing a user sees. |
| **Not** | `android:updatePeriodMillis` | Set it to **`0`**. It wakes the device, cannot go below 30 min anyway, and duplicates the WorkManager path. |

Glance's own warning, quoted: *"Updating your widget every minute when the app isn't awake drains
users' battery."* The iOS app renders a live countdown on a Live Activity precisely because a
home-screen surface cannot afford one. §9.3 handles the countdown without a single extra update.

```kotlin
// Enqueue once, from Application.onCreate (or a Hilt initialiser).
WorkManager.getInstance(context).enqueueUniquePeriodicWork(
    "up-next-widget-refresh",
    ExistingPeriodicWorkPolicy.KEEP,
    PeriodicWorkRequestBuilder<UpNextRefreshWorker>(30, TimeUnit.MINUTES)
        .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
        .build(),
)
```

### 6.4 Do not fight Glance's own workers

Glance schedules its sessions through WorkManager under unique work names derived from the session
key. Cancelling work broadly (`cancelAllWork`, or a blanket tag sweep) will cancel Glance's sessions
and the widget silently stops updating. Namespace every worker this app enqueues, and never call
`WorkManager.cancelAllWork()`.

---

## 7. Sharing data between the app process and the widget

### 7.1 There is no App Group problem

This is where the iOS mental model misleads. On iOS a widget extension is a **separate process with a
separate container**, so `library-cache.json` has to move into an App Group. On Android:

- `GlanceAppWidgetReceiver` is a `BroadcastReceiver` **declared in the same APK and, unless you set
  `android:process`, running in the same process as the app.**
- It therefore has the same `filesDir`, the same DataStore, the same Room DB, the same OkHttp/Coil
  disk cache, the same Hilt graph.

So: **the widget reads the app's own store directly.** No duplication, no serialisation format to
agree on, no sync. `MultiProcessGlanceAppWidget` + `MultiProcessConfig` exist for apps that
deliberately run widget receivers in another process — this app should not.

### 7.2 The real trap: the process is usually cold

The widget's process may be started *only* to render the widget. There is no Activity, no
`AppModel` in memory, no live `library` list, no auth session warm. The freshness ladder derivations
live in `:model` (`compose-architecture.md`: a pure-Kotlin JVM module) precisely so they can be run
against persisted rows without an Android context — use that.

So the contract is:

```
[server] → AppModel.reload() → writes library cache (DataStore/Room) → updateAll()
                                          ↑
                                          └── provideGlance() reads it, cold or warm
```

The Android analogue of iOS's `library-cache.json` (`CLAUDE.md`: *"the library has an offline copy …
stamped with its real `savedAt`"*) is the widget's data source. It already has to exist for the
offline launch; the widget is a second reader of it. **Do not invent a second widget-only cache** —
two caches drift and the widget becomes the app's liar.

### 7.3 What `GlanceStateDefinition` is actually for

`stateDefinition` is **per-widget-instance** state, keyed by `GlanceId`, stored in its own DataStore
file. Use it only for things that are genuinely about *this placed instance*:

- the resolved `content://` art URI for this instance's current size (§5.2),
- (later) which franchise a configured instance is pinned to.

Not for the library. `PreferencesGlanceStateDefinition` is the built-in Preferences-DataStore
implementation and is what `updateAppWidgetState` writes to.

```kotlin
class UpNextWidget : GlanceAppWidget() {

    override val stateDefinition = PreferencesGlanceStateDefinition
    override val sizeMode = SizeMode.Responsive(setOf(SMALL, WIDE))

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        // Runs in a CoroutineWorker. Load ENOUGH to render once, then observe.
        val repo = WidgetEntryPoint.get(context).libraryRepository()   // Hilt EntryPoint, no Activity
        val first = repo.upNextOnce()                                   // suspend, from the cache

        provideContent {
            // Live for ~45 s; recomposes on every cache write in that window.
            val upNext by repo.upNext.collectAsState(initial = first)
            val artUri = currentState(ArtUriKey)

            PreviouslyGlanceTheme {                                     // §8
                UpNextCard(upNext, artUri)
            }
        }
    }

    override suspend fun onDelete(context: Context, glanceId: GlanceId) {
        super.onDelete(context, glanceId)
        WorkManager.getInstance(context).cancelAllWorkByTag(glanceId.toString())
    }

    override fun onCompositionError(
        context: Context, glanceId: GlanceId, appWidgetId: Int, throwable: Throwable,
    ) { /* log; draw Copy.State.somethingWentWrong, not the stock layout */ }
}
```

Hilt does not inject into a `BroadcastReceiver`'s composition for free; reach the graph with an
`@EntryPoint` on the application component — that keeps the widget on the same repository instance
the app uses and away from a second OkHttp/DataStore.

### 7.4 Anything a `Bundle` could hold, put in `LocalAppWidgetOptions`

`LocalAppWidgetOptions` exposes the host's option `Bundle` (sizes, category). It is the only channel
the *launcher* has to your composition; do not confuse it with app state.

---

## 8. Theming a widget to the app's dark palette

### 8.1 The default is Material You, and that is the bug

From the AndroidX source (`androidx/glance/CompositionLocals.kt`, `androidx-main`, read 2026-09-04):

```kotlin
internal val LocalColors: ProvidableCompositionLocal<ColorProviders> = staticCompositionLocalOf {
    DynamicThemeColorProviders
}
```

and `DynamicThemeColorProviders` is built entirely from `R.color.glance_color*` resources —
*"a Material 3 style dynamic color theme. On devices that support it, this theme is derived from the
user specific platform colors."* `GlanceTheme`'s own KDoc: *"Unlike a standard compose theme, this
only provides color."*

So a widget that never mentions `GlanceTheme` — or that calls `GlanceTheme { … }` with no `colors`
argument — **renders in the user's wallpaper palette.** For an app whose entire identity is one amber
(`#F0A24E`) on one near-black (`#09090B`), and whose design rules ration that amber to *meaning*,
that is a total loss of the brand. This is the single highest-value line in this note.

### 8.2 The fix: a fixed scheme, no day/night pair

`androidx.glance:glance-material3` gives two overloads, and their KDocs are the decision:

- `ColorProviders(scheme: ColorScheme)` — *"This is a **fixed scheme and does not have day/night
  modes**."*
- `ColorProviders(light: ColorScheme, dark: ColorScheme)` — *"Each color in the theme will have a day
  and night mode."*

The app is dark-only (`compose-architecture.md` §2: *"The app is dark-only and portrait-only"*), and
the day/night resolution happens **in the launcher's process against the launcher's configuration** —
which you do not control. Take the fixed overload. One palette, always.

```kotlin
// app/src/main/java/app/previously/widget/PreviouslyGlanceTheme.kt
private val PreviouslyWidgetScheme = darkColorScheme(
    primary          = Color(0xFFF0A24E),  // ThemeColor.accent
    onPrimary        = Color(0xFF0B0B0D),  // ThemeColor.onAccent
    background       = Color(0xFF09090B),  // ThemeColor.canvas
    onBackground     = Color(0xFFF4F1EC),  // ThemeColor.textPrimary
    surface          = Color(0xFF171719),  // ThemeColor.surfaceFlat
    onSurface        = Color(0xFFF4F1EC),  // ThemeColor.textPrimary
    surfaceVariant   = Color(0xFF242428),  // ThemeColor.surfaceRaised
    onSurfaceVariant = Color(0xFFAAA6A0),  // ThemeColor.textSecondary
    outline          = Color(0xFF85817C),  // ThemeColor.textTertiary
    error            = Color(0xFFFF453A),  // ThemeColor.destructive
)

private val PreviouslyWidgetColors: ColorProviders =
    ColorProviders(PreviouslyWidgetScheme)   // androidx.glance.material3 — FIXED, no day/night

@Composable
fun PreviouslyGlanceTheme(content: @Composable () -> Unit) =
    GlanceTheme(colors = PreviouslyWidgetColors) {
        CompositionLocalProvider(
            LocalWidgetType provides PreviouslyWidgetType,   // your own, see 8.4
            content = content,
        )
    }
```

`ColorProviders` is a **sealed** class — you cannot subclass it. Your two constructors are the
`colorProviders(...)` factory in `androidx.glance.color` (26–27 named `ColorProvider` arguments,
including `widgetBackground`) and the `glance-material3` overloads above. The material3 route is far
less code and maps cleanly onto tokens the port already defines.

### 8.3 Where the palette is *not* enough

The M3 slot names do not cover the app's vocabulary — there is no `accentSoft`, no `interactive`, no
`canvasRaised`. Do the same thing the port does in the app (`compose-architecture.md` §2.2: *"do not
adopt `MaterialTheme` as the app's theme"* — a `CompositionLocal`-based `PreviouslyTheme`): pass the
extra tokens through your own `CompositionLocal` alongside `GlanceTheme`. Glance is the Compose
runtime, so `staticCompositionLocalOf` works exactly as it does in the app.

**And keep the amber rule.** `CLAUDE.md`: *"Amber is not an action colour"* — accent is for MEANING
(a real next step, a future air time) and STATE (today, selected, committed). On the widget that means
the air time and the "TODAY" pill may be amber; a tappable word may not. There are no tappable words
in the v1 design anyway (§9).

### 8.4 Type: the widget speaks system

*"Custom fonts in apps aren't supported"*; `TextStyle.fontFamily` accepts only Monospace / SansSerif /
Serif. This is a `RemoteViews` limitation — *"widgets live in other processes, they can only use
system typefaces"* — not a Glance gap, so `AndroidRemoteViews` with a layout that sets
`android:fontFamily="@font/outfit_semibold"` is **not a reliable escape**: whether a `@font` resource
survives cross-process inflation depends on the host resolving your package's resources, and reports
differ. **Do not build the design on it.** If someone wants to try, treat it as an experiment with a
device matrix, not a plan (open question **Q3**).

The other workaround — rendering text to a `Bitmap` with a `Paint` carrying the Outfit `Typeface` and
shipping it as `ImageProvider(bitmap)` — is technically real and is what people do. **Reject it here**:
it burns the §5.1 bitmap budget on *text*, breaks selection and TalkBack unless every image carries a
`contentDescription`, and does not reflow at accessibility font scales. The iOS extension already
concedes the same point in its own comment: *"extensions don't bundle the Outfit fonts … type is the
system font, which is conventional for lock-screen surfaces."* Be consistent.

Practical consequence: the widget's hierarchy is carried by **size, weight and colour**, not by
typeface. `sectionTitle`-equivalent → SansSerif 20sp `FontWeight.Medium`; the time → 28–34sp
`FontWeight.Bold` in accent; the fact line → 13sp in `onSurfaceVariant`.

### 8.5 Background and corners

Mark exactly one view as the widget background and give it the system radius:

```kotlin
Box(
    modifier = GlanceModifier
        .fillMaxSize()
        .appWidgetBackground()                                    // @android:id/background — required
        .background(GlanceTheme.colors.widgetBackground)
        .cornerRadius(android.R.dimen.system_app_widget_background_radius), // API 31+
) { … }
```

`appWidgetBackground()`'s KDoc: *"There can be only one view with this modifier … This modifier does
not automatically set corner radius. To have these set for you, use the
`androidx.glance.appwidget.components.Scaffold` component."* Marking it is what enables the launcher's
smooth open transition. `system_app_widget_background_radius` is API 31+ — fine at `minSdk 31`.

---

## 9. Interaction and deep links

### 9.1 The action set

| API | Use |
|---|---|
| `actionStartActivity<T>()` / `(ComponentName)` / `(Intent)` | **The one you want.** Launches an Activity directly. |
| `actionRunCallback<T : ActionCallback>()` | A suspend `onAction(context, glanceId, parameters)` for widget-local work (refresh, toggle). |
| `actionSendBroadcast` / `actionStartService` | Rarely right for this app. |
| `clickable { … }` / `Button(onClick = { … })` lambda actions | *"Lambda functions execute as callbacks in a `WorkManager` worker context within a `Service`."* Non-experimental since 1.2.0-alpha01. |

**The documented trap**, quoted: *"Apps targeting Android 12+ cannot start activities from services or
broadcast receivers that act as trampolines. Use `actionStartActivity` instead."* So: never open the
app from a lambda or an `ActionCallback` — always `actionStartActivity`.

### 9.2 The route, reusing what the port already specifies

`../spec/appmodel.md` §10.3 already defines the single-shot open channel (`pendingOpen`, "consumed
exactly once", Android note: *"a notification `PendingIntent` → `Activity.onNewIntent` → a single-shot
event channel"*). The widget must enter through **the same door**, exactly as `-openDetail` does on
iOS. Do not add a second navigation path.

```kotlin
// Widget side
private fun openShow(id: String): Action = actionStartActivity(
    Intent(Intent.ACTION_VIEW, "previously://franchise/$id".toUri())
        .setPackage(context.packageName)
)

Box(modifier = GlanceModifier.fillMaxSize().clickable(openShow(upNext.franchiseId))) { … }
```

```xml
<!-- ERRATUM (2026-09-04, PLAN §2.5/§9.2): singleTop, NOT singleTask.
     singleTask clears the tab back stacks on every notification/widget tap; singleTop is what
     onNewIntent needs and is what notifications-liveupdates.md already specifies. -->
<activity android:name=".MainActivity" android:launchMode="singleTop" android:exported="true">
    <intent-filter>
        <action android:name="android.intent.action.VIEW" />
        <category android:name="android.intent.category.DEFAULT" />
        <category android:name="android.intent.category.BROWSABLE" />
        <data android:scheme="previously" android:host="franchise" />
    </intent-filter>
</activity>
```

```kotlin
// MainActivity
override fun onNewIntent(intent: Intent) { super.onNewIntent(intent); consume(intent) }
private fun consume(intent: Intent) {
    intent.data?.takeIf { it.scheme == "previously" && it.host == "franchise" }
        ?.lastPathSegment
        ?.let { appModel.pendingOpen = it }   // same channel the notification tap uses
}
```

Two mechanics worth knowing:

- **Glance already solves PendingIntent collision.** In `ApplyAction.kt` (`androidx-main`), for a
  `StartActivityAction` with no data URI Glance sets a unique identifier derived from the view id
  before calling `PendingIntent.getActivity(context, 0, intent, FLAG_IMMUTABLE or FLAG_UPDATE_CURRENT, …)`
  — *"If there is no data URI set already, add a unique URI to ensure we get a distinct PendingIntent."*
  Supplying your own distinct `data` URI per row (as above) is equally safe and has the bonus of being
  drivable from adb.
- **`ActionParameters` is the alternative** and works fine (`actionStartActivity<MainActivity>(actionParametersOf(key to id))`
  → read `intent.extras`), but a URI is testable:
  `adb shell am start -a android.intent.action.VIEW -d "previously://franchise/16498"`.

### 9.3 The countdown — how to tick without updating

The iOS Live Activity uses `Text(timerInterval:countsDown:)`, which the system re-renders for free.
Glance has no equivalent composable. Three options, in the order to consider them:

1. **Static relative copy + boundary refresh (recommended).** Render the app's own `TemporalCopy`
   string ("in 3h 12m", "Airs at 7:30 PM", "Out now") and let §6.3's alarm flip it at the boundary.
   This is the only option that keeps the app's copy grammar — and the grammar is the point
   (`CLAUDE.md`: one temporal expression per item; TMDB date-only never shows a clock).
2. **`Chronometer` via `AndroidRemoteViews`** if a truly live tick is wanted in the final hour.
   `RemoteViews` supports `Chronometer`, plus `setChronometer(viewId, base, format, started)` and
   `setChronometerCountDown(viewId, isCountDown)` — the view ticks **in the launcher's process with
   zero widget updates**. The base is in the `SystemClock.elapsedRealtime()` timebase, so:
   `base = SystemClock.elapsedRealtime() + (airsAtMillis - System.currentTimeMillis())`.
   **Its format is `H:MM:SS`** — it cannot say "in 3h 12m", so adopting it means changing the copy on
   this surface. Treat that as a design decision, not an implementation detail (open question **Q2**).
3. **`TextClock`** (also RemoteViews-supported) for a live wall clock. Not useful here.

### 9.4 What the widget should *not* do in v1

`actionRunCallback<MarkWatchedAction>()` looks like a one-line win. It is not. Every progress write in
this app goes through `AppModel.sendProgress` — *"one PUT in flight per part, the newest target waits
behind it and superseded targets are dropped"* — with `WriteIntent` failure capture and
`SyncCenter.replay`. Reaching that policy from a cold `ActionCallback`, with the optimistic copy
(`FranchisePart.withProgress`, which must not drop `airings`) and the Undo toast that lives in the app
UI, is a real piece of work. **Ship tap-to-open. Add the mark ring when the write path has a
process-agnostic entry point.** (Open question **Q1**.)

---

## 10. Manifest, sizing, previews

```kotlin
// UpNextWidgetReceiver.kt
class UpNextWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = UpNextWidget()
}
```

```xml
<receiver
    android:name=".widget.UpNextWidgetReceiver"
    android:exported="true"
    android:label="@string/widget_up_next_label">
    <intent-filter>
        <action android:name="android.appwidget.action.APPWIDGET_UPDATE" />
    </intent-filter>
    <meta-data
        android:name="android.appwidget.provider"
        android:resource="@xml/up_next_widget_info" />
</receiver>
```

```xml
<!-- res/xml/up_next_widget_info.xml -->
<appwidget-provider xmlns:android="http://schemas.android.com/apk/res/android"
    android:minWidth="250dp"  android:minHeight="110dp"
    android:targetCellWidth="4" android:targetCellHeight="2"
    android:minResizeWidth="180dp" android:minResizeHeight="110dp"
    android:maxResizeWidth="440dp" android:maxResizeHeight="290dp"
    android:resizeMode="horizontal|vertical"
    android:widgetCategory="home_screen"
    android:updatePeriodMillis="0"
    android:description="@string/widget_up_next_description"
    android:previewImage="@drawable/widget_up_next_preview"
    android:initialLayout="@layout/glance_default_loading_layout" />
```

- `android:initialLayout="@layout/glance_default_loading_layout"` is Glance's own resource and is what
  the launcher shows for the fraction of a second before the first composition lands.
- `targetCellWidth/Height` are Android 12+; `minWidth/minHeight` are the pre-12 fallback. Both.
- `updatePeriodMillis="0"` — see §6.3.
- **`previewImage` is not optional.** The widget picker is where a widget is won or lost, and a widget
  with no preview is a grey box.

**Generated previews (API 35+).** `GlanceAppWidget.providePreview(context, widgetCategory: Int)` +
`GlanceAppWidgetManager.setWidgetPreviews(...)` (`@RequiresApi(35)`) publish a *real* rendered preview
with the user's own data. Two constraints from the docs: it is **rate-limited to roughly two calls per
hour**, and *"there is no callback from the system, so your app must decide when to call
`setWidgetPreviews`"*. Set it once after the library first loads for a signed-in user, and again at
most daily. Keep `previewImage` as the pre-35 fallback. Set `previewSizeMode = SizeMode.Responsive(...)`
so the preview renders at the same breakpoints as the widget.

**Pinning from inside the app** (API 26+): `GlanceAppWidgetManager(context).requestPinGlanceAppWidget(receiver = UpNextWidgetReceiver::class.java, preview = UpNextWidget(), previewState = DpSize(245.dp, 115.dp))`
returns `true` if the request reached the system. A good Profile row, once the widget is worth
advertising — and the only reliable way to place the widget on the QA emulator (§13.1).

---

## 11. The Live Activity — a different surface, named here so it is not lost

`AiringLiveActivity` (Dynamic Island + lock screen + a ticking countdown, gated on iOS to
`source == .anilist` because TMDB dates are date-only) has **no widget counterpart on Android**. Its
equivalent is Android 16's **Live Updates**:

- `Notification.ProgressStyle` (Android 16) — *"a new notification style that lets you create
  progress-centric notifications, with key use cases including rideshare, delivery, and navigation"* —
  with segments and points along a journey.
- A progress-centric notification can be **promoted** to a Live Update, which *"appear[s] more
  prominently on system surfaces, including at the top of the notification drawer and the lock screen,
  and as a chip in the status bar"*. The exact promotion API name is **not** confirmed here — read it off
  the Android 16 notification reference when writing that note, do not paste one from memory.
- Below Android 16 the fallback is an ordinary ongoing notification with `setWhen` + `setUsesChronometer(true)`
  (the notification-shade sibling of §9.3's `Chronometer`).

Whether a *"this show airs in 12 minutes"* countdown is a legitimate ProgressStyle use case, or an
abuse of a surface Google scoped to deliveries and navigation, is a product/policy question — one that
belongs in the notifications research note, not here. Flagged as open question **Q5**.

---

## 12. Alternatives considered and rejected

| Option | Why not |
|---|---|
| **Hand-written `RemoteViews` + `AppWidgetProvider`** | Zero extra dependency, total control, and every RemoteViews feature (`Chronometer`, `TextClock`, `setTextViewTextSize`) reachable directly. **Rejected**: it is a second UI language in a codebase whose whole thesis is one design system in Compose; the official widget overview says *"Jetpack Compose is the recommended UI toolkit for Android"* and links Glance; and it writes against a transport (XML view inflation) the platform is moving off (§3.3). Keep it as a targeted escape via `AndroidRemoteViews`, not as the base. |
| **Glance 1.3.0-alpha02** | Alpha. Its two visible additions (Remote Compose version bump, snap scrolling on API 37) are irrelevant to a one-card widget. Revisit if a scrolling list widget is ever designed. |
| **`androidx.glance.adaptive:*:1.0.0-alpha01`** | 9 days old at time of writing, alpha, template-first, and aimed at "multiple form factors and surfaces". No Wear/car target exists in this port. Right library to watch, wrong library to ship. |
| **`ImageProvider(bitmap)` for the banner** | Counts against `screen_w × screen_h × 4 × 1.5` bytes across the whole `RemoteViews`; with `SizeMode.Responsive` you pay per layout. Google's own sample tells you to switch to a URI when you hit it. Use `ImageProvider(uri)` from the start. |
| **`android:updatePeriodMillis="1800000"`** | Wakes the device, is capped at 30 min anyway, and duplicates the WorkManager path — two schedulers producing the same render. Set it to 0. |
| **Exact alarms (`USE_EXACT_ALARM`) for the air instant** | Play restricts the permission to apps whose *"user-facing function … requires precisely-timed actions"*. A TV tracker is not an alarm clock. `setWindow` with a 5-minute window is indistinguishable to a user reading a widget. |
| **Bitmap-rendered Outfit text** | Burns the bitmap budget on text, breaks TalkBack and font scaling, and contradicts the concession the iOS extension already made. §8.4. |
| **A second "Library" or "Schedule" widget** | Horizontal gestures are unavailable to widgets (*"The only gestures available for widgets are touch and vertical swipe"*), so a `ShelfCard` shelf cannot exist here, and a vertical list of shows is what the app itself is one tap away from. One widget, one fact. |
| **A widget-only cache file** | Two caches drift. The widget reads the app's offline library copy, or it lies. §7.2. |
| **Compose Multiplatform / shared widget UI** | Widgets are RemoteViews-shaped and Android-only; there is nothing to share. Consistent with `compose-architecture.md`'s CMP call. |

---

## 13. Open questions for a human

**Q1 — Does the widget get a mark-as-watched control?** The app's identity is the `MarkRing`, and a
widget that can only open the app is a bookmark. But a widget write must reach `sendProgress`'s
serialisation and `SyncCenter`'s replay from a cold process, and the Undo toast — the safety net the
app's write rules assume — cannot be shown on the home screen. Recommendation: **no in v1**; revisit
when the write path has a documented process-agnostic entry point. *This is a product call.*

**Q2 — Live tick, or the app's own temporal copy?** §9.3. A `Chronometer` gives a real ticking
`H:MM:SS` for free, but breaks `TemporalCopy`'s "in 3h 12m" grammar on exactly one surface. Picking
the tick means accepting that the widget speaks slightly differently from the app. *This is a design
call and it should be made deliberately, not discovered in review.*

**Q3 — Is a custom font reachable at all?** Sources disagree on whether `android:fontFamily="@font/…"`
in a RemoteViews layout resolves in the host process. The plan above assumes **no** and designs around
it. If someone wants the answer, it is one XML layout, one `AndroidRemoteViews` call and a device
matrix — but do not let the design depend on the outcome.

**Q4 — Glance 1.2.0 now, or wait for the RemoteCompose story to settle?** `glance-appwidget` is
current, documented and not deprecated, and `glance.adaptive` is alpha — so shipping on 1.2.0 is the
defensible read. But 1.1.0 → 1.2.0 took 26 months, and a template-first sibling library appeared on the
same day 1.2.0 went stable. If the widget is not on the launch critical path, there is a real argument
for deferring it one release and re-reading the release notes.

**Q5 — Does the Live Activity port to `Notification.ProgressStyle`, and is that within policy?** §11.
Belongs in the notifications note; naming it here so the surface is not silently dropped in the port.

**Q6 — Which show does the widget pick when nothing is airing?** Today's calm state has a rule
(`CLAUDE.md`: *"Today is never without a billboard"* — `nextUp`, else the first Watching show, else the
trending #1 for an empty account). The widget should reuse `kind(of:)` and the same stack order rather
than invent a third ranking — confirm that the `:model` module exposes that decision as a pure
function the widget process can call.

### 13.1 QA recipe on the emulator

Extends `TOOLCHAIN.md`. The emulator has no gesture automation for the widget picker, so:

```bash
# 1. Place the widget: call requestPinGlanceAppWidget from a debug entry point,
#    then confirm the system dialog. (There is no adb command that pins a widget.)

# 2. Force a re-render without waiting for a worker. Glance ships this for exactly this purpose:
adb shell am broadcast \
  -a androidx.glance.appwidget.action.DEBUG_UPDATE \
  -n app.previously/.widget.UpNextWidgetReceiver
#    Requires the receiver exported (it is) or adb root. DEBUG BUILDS ONLY —
#    add the androidx.glance.appwidget.DEBUG_UPDATE intent-filter in a debug manifest and
#    make sure it is absent from release.

# 3. Inspect what the system thinks is bound
adb shell dumpsys appwidget | sed -n '1,120p'

# 4. Exercise the deep link without touching the screen
adb shell am start -a android.intent.action.VIEW -d "previously://franchise/16498"

# 5. Capture
adb exec-out screencap -p > widget.png

# 6. Prove the theme is not Material You: change the wallpaper accent and re-capture.
#    A correct widget does not move.
adb shell settings put secure theme_customization_overlay_packages \
  '{"android.theme.customization.system_palette":"FF00FF00","android.theme.customization.theme_style":"VIBRANT"}'
```

Also worth running the state matrix through the existing proxy (`CLAUDE.md`'s `proxy.py` modes) with
the app killed, so the widget is rendered from a genuinely cold process against a stale cache — that is
the state most users will actually see.

---

## 14. Sources

All fetched **2026-09-04** unless a page states its own "last updated" date.

**Official — release notes and reference**
- Glance release notes (version table, 1.2.0 stable 26 Aug 2026, 1.3.0-alpha01 19 May 2026, 1.3.0-alpha02 1 Jul 2026, minSdk 21→23 at 1.2.0-beta01) — https://developer.android.com/jetpack/androidx/releases/glance
- Glance Adaptive release notes (1.0.0-alpha01, 26 Aug 2026) — https://developer.android.com/jetpack/androidx/releases/glance-adaptive
- `RemoteViews` reference (supported layout/widget list; `DrawInstructions` API 35, 21 MB `MAX_REMOTE_COMPOSE_SIZE`; `setChronometer` / `setChronometerCountDown`) — https://developer.android.com/reference/android/widget/RemoteViews
- `AppWidgetProviderInfo` reference (*"Updates requested with `updatePeriodMillis` will not be delivered more than once every 30 minutes"*; `previewLayout` API 31, `previewImage` API 11) — https://developer.android.com/reference/android/appwidget/AppWidgetProviderInfo
- `GlanceAppWidget` reference (`provideGlance` 10-minute worker limit / ~45-second composition window; `providePreview(context, widgetCategory)`; `previewSizeMode` added 1.2.0; `compose` / `composeForPreview` / `runComposition`) — https://developer.android.com/reference/kotlin/androidx/glance/appwidget/GlanceAppWidget
- `androidx.glance.appwidget` package summary (`appWidgetBackground`, `cornerRadius`, `ImageProvider(uri)`, `setWidgetPreviews` `@RequiresApi(35)`, `MultiProcessGlanceAppWidget`) — https://developer.android.com/reference/kotlin/androidx/glance/appwidget/package-summary
- `androidx.glance.color` package summary (`ColorProvider(day, night)` added 1.2.0; `colorProviders(...)` incl. `widgetBackground`) — https://developer.android.com/reference/kotlin/androidx/glance/color/package-summary
- `androidx.glance.material3` package summary (*"This is a fixed scheme and does not have day/night modes"*) — https://developer.android.com/reference/kotlin/androidx/glance/material3/package-summary
- `GlanceTheme` reference — https://developer.android.com/reference/kotlin/androidx/glance/GlanceTheme

**Official — guides**
- Create an app widget with Glance (manifest, provider XML, `SizeMode`, rounded corners) — https://developer.android.com/develop/ui/compose/glance/create-app-widget
- Build UI with Glance (composable set; *"Custom fonts in apps aren't supported"*; `LazyColumn` → `ListView`; snap scrolling requirements) — https://developer.android.com/develop/ui/compose/glance/build-ui
- Manage and update GlanceAppWidget (`update` / `updateAll` / `updateIf`; *"`updatePeriodMillis` for updates up to once every 30 minutes"*, *"`WorkManager` for more frequent updates (e.g. every 15 minutes)"*, the battery warning) — https://developer.android.com/develop/ui/compose/glance/glance-app-widget
- Handle user interaction (`actionStartActivity` / `actionRunCallback` / lambda actions; the Android-12 trampoline warning; `ActionParameters`) — https://developer.android.com/develop/ui/compose/glance/user-interaction
- Glance interoperability (`AndroidRemoteViews`, both overloads) — https://developer.android.com/develop/ui/compose/glance/interoperability
- Generated widget previews (API 35; *"approximately two calls per hour"*; no system callback) — https://developer.android.com/develop/ui/compose/glance/generated-previews
- Pin Glance widgets in-app (`requestPinGlanceAppWidget`, API 26+) — https://developer.android.com/develop/ui/compose/glance/pin-in-app
- App widgets overview (*"Jetpack Compose is the recommended UI toolkit for Android"*; *"The only gestures available for widgets are touch and vertical swipe"*) — https://developer.android.com/develop/ui/views/appwidgets/overview
- Progress-centric notifications, Android 16 — https://developer.android.com/about/versions/16/features/progress-centric-notifications
- Schedule exact alarms are denied by default (Android 14) — https://developer.android.com/about/versions/14/changes/schedule-exact-alarms
- Schedule alarms — https://developer.android.com/develop/background-work/services/alarms

**Official — source and samples**
- `androidx-main` `glance/glance/src/main/java/androidx/glance/GlanceTheme.kt` (*"this only provides color"*) and `color/ColorProviders.kt` + `CompositionLocals.kt` (`LocalColors` default = `DynamicThemeColorProviders`) — https://github.com/androidx/androidx
- `androidx-main` `glance-appwidget/.../action/ApplyAction.kt` (unique-URI PendingIntent construction) and `GlanceAppWidgetReceiver.kt` (`ACTION_DEBUG_UPDATE` + its adb one-liner) — same repo
- `android/user-interface-samples` `AppWidget/.../glance/image/ImageGlanceWidget.kt` and `ImageWorker.kt` (the FileProvider content-URI image pattern, the bitmap-limit comment, the launcher `grantUriPermission` dance) — https://github.com/android/user-interface-samples
- Coil `CHANGELOG.md` on `main` (3.6.1, 1 Sep 2026; 3.6.0, 26 Aug 2026 — compileSdk 37, Kotlin 2.4.10, Compose 1.12.0) and `docs/upgrading_to_coil3.md` (`DiskCache.get`/`edit` → `openSnapshot`/`openEditor`; `Coil` → `SingletonImageLoader`) — https://github.com/coil-kt/coil
- Published POMs for `androidx.glance:glance:1.2.0` and `:1.3.0-alpha02` (compose-runtime 1.6.0 / datastore 1.0.0 / work 2.7.1 floors) — https://dl.google.com/dl/android/maven2/androidx/glance/glance/1.2.0/glance-1.2.0.pom

**Official — blog**
- *Building Premium Android Experiences at Google I/O '26*, 2 Jun 2026 (Glance as the consistent Compose-based model across home screen, Wear Widgets and cars; RemoteCompose as the rendering engine) — https://android-developers.googleblog.com/2026/06/building-premium-android-experiences-google-io-26.html

**Secondary (corroborating, lower trust — used only where the primary source is silent)**
- The `screen_w × screen_h × 4 × 1.5` bitmap-limit formula and the verbatim `IllegalArgumentException` text: openhab-android issue #2053 and bumptech/glide issue #5214, both quoting the platform message. The *existence* of the limit is confirmed by Google's own sample comment above; the *formula* is not documented on `developer.android.com`.
- *Jetpack-Glance: No way to custom fonts* (ProAndroidDev / droidcon, Nov 2023) — the Canvas/bitmap workaround, rejected in §8.4.
- *From RemoteViews to RemoteCompose* (Medium, Luca Fioravanti) — context on the Android 16 rendering shift; **its "Android 16" framing conflicts with the `RemoteViews` reference, which puts `DrawInstructions` at API 35 (Android 15)**. Trust the reference.

**In-repo**
- `/Users/shantanusinha/Desktop/workspace/animetracker/ios/Widgets/AniTrackWidgets.swift` — the Live Activity, and the "no Outfit in the extension" precedent
- `/Users/shantanusinha/Desktop/workspace/animetracker/CLAUDE.md` — amber rule, copy rules, freshness ladder, write rules, offline library copy
- `/Users/shantanusinha/Desktop/workspace/animetracker/docs/android-port/TOOLCHAIN.md` — emulator geometry (1280 × 2856 px, 480 dpi) used for the §5.1 budget arithmetic
- `/Users/shantanusinha/Desktop/workspace/animetracker/docs/android-port/research/compose-architecture.md` — minSdk 31 / targetSdk 36 / compileSdk 37, AGP 9.4.0, Compose BOM 2026.08.00, "do not adopt `MaterialTheme`"
- `/Users/shantanusinha/Desktop/workspace/animetracker/docs/android-port/spec/design-tokens.md` — the hex values in §8.2
- `/Users/shantanusinha/Desktop/workspace/animetracker/docs/android-port/spec/appmodel.md` §10.3 — `pendingOpen`, the route §9.2 reuses
