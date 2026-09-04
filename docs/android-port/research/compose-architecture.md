# Android app architecture for the Compose port of *Previously.*

**Status:** research / decision note. Written 2026-09-04. Every version below was checked against
primary sources on that date; links and dates are in §11.

**Scope:** the skeleton decisions an engineer needs before the first line of the port — toolchain,
SDK levels, state-holder pattern, DI, module layout, navigation, and whether Compose Multiplatform
belongs here at all. It does **not** cover networking, image loading, notifications or the design
system; those have their own specs under `docs/android-port/spec/`.

---

## 1. Recommendation up front

| Decision | Pick | One-line reason |
|---|---|---|
| Kotlin | **2.4.10** (Jul 14 2026) | Latest stable; Compose compiler ships inside the Kotlin release, so it can never be out of step. |
| AGP / Gradle | **AGP 9.4.0** (Sep 2026) / **Gradle 9.6.1**, JDK 21 toolchain (AGP floor is 17) | AGP 9.4 requires Gradle ≥ 9.6.0 and supports up to API 37. |
| Compose | **BOM 2026.08.00** → runtime/ui/foundation **1.12.0**, material3 **1.4.0** | Newest stable BOM. Compose 1.12 requires `compileSdk 37` and AGP ≥ 9.1.1. |
| compileSdk | **37** (Android 17) | Forced by Compose 1.12. |
| targetSdk | **36** for v1, with a dated plan to reach 37 | 36 is the Play floor since 31 Aug 2026; 37 removes the opt-out from ignoring orientation/resizability on sw≥600dp, and this app is portrait-only today. |
| minSdk | **31** (Android 12) — ≈ 79 % of active devices | The design is blur-dependent (`glassChrome`, `HeroTopVeil`, hardened bars). `Modifier.blur` / `RenderEffect` are API 31+. Below 31 you ship a visually different app. |
| State holder | **One session-scoped `AppModel` built from per-field Compose snapshot state** (`mutableStateOf` / `mutableLongStateOf` / `derivedStateOf`), owned by a single `@HiltViewModel` | Snapshot state is the exact analogue of Swift `@Observable` per-property tracking. A single `StateFlow<UiState>` is not, and the spec forbids it by name. |
| DI | **Hilt 2.60.1** (KSP), kept thin | Compile-time verified, official ViewModel/WorkManager/nav3 integration, needs AGP 9 (which we have). |
| Modules | **`:app` (Android) + `:model` (pure Kotlin JVM)** | The freshness-ladder derivations are the highest-risk part of the port; they belong where JVM unit tests run in milliseconds. Third module only when there is a reason. |
| Navigation | **Navigation 3** — `androidx.navigation3:navigation3-{runtime,ui}:1.1.7` | The back stack is a `SnapshotStateList` you own, which is literally the shape of the iOS per-tab `NavigationPath`. Per-tab stacks, pop-to-root and predictive back are all first-class. |
| Compose Multiplatform | **No** for UI. **Not yet** for shared logic. Use a shared *golden-fixture test corpus* instead. | The SwiftUI app exists, ships, and keeps evolving; CMP's value is UI you have not written yet. |

**Confidence: medium-high.** The toolchain, navigation and CMP calls are well-evidenced. The
`minSdk 31` call rests on third-party distribution data (Google no longer publishes API-level
distribution publicly — see §4.1) and on a product judgement about blur; it is the one number a
human should sign off on.

---

## 2. Toolchain

### 2.1 Versions and evidence

- **Kotlin 2.4.10**, released 14 Jul 2026 (bug-fix for 2.4.0, 3 Jun 2026). Source: the Kotlin
  releases table. Since Kotlin 2.0.0 the Compose compiler lives in the Kotlin repository and ships
  with the same version number, so you apply `org.jetbrains.kotlin.plugin.compose` at the Kotlin
  version and never think about a compatibility map again.
- **AGP 9.4.0**, September 2026. Its published compatibility table: Gradle **min 9.6.0** (default
  9.6.0), SDK Build Tools 36.0.0, **JDK min 17**, **max supported API level 37**.
- **Gradle 9.6.1** is current; 9.6.0 shipped 18 Jun 2026.
- **Compose BOM 2026.08.00** (announced 12 Aug 2026) maps to ui/foundation/runtime **1.12.0** and
  material3 **1.4.0**. The release post states Compose 1.12 **requires AGP ≥ 9.1.1 and
  `compileSdk` API 37**. There is no 2026.09 BOM yet as of 2026-09-04.
- **KSP**: KSP2 no longer pins to the Kotlin version — the current Kotlin quickstart pairs
  `kotlin 2.4.10` with `ksp 2.3.10`, and Maven Central shows 2.3.11 as newest. **Verify against
  github.com/google/ksp/releases at setup time**; this is the one version below I would not paste
  blind.

### 2.2 Material 3, and why it barely matters here

material3 stable is **1.4.0** (latest stable build dated 26 Aug 2026); **Material 3 Expressive is
still alpha-only** (1.5.0-alpha27, 26 Aug 2026 — expressive APIs are non-experimental within the
alpha but there is no stable release carrying them).

This is close to irrelevant for *Previously.*, and that is a design decision worth stating loudly:
**do not adopt `MaterialTheme` as the app's theme.** The iOS app forbids literal colours, sizes,
fonts and animations in screens and composes everything from `ThemeColor` / `ThemeSpace` /
`ThemeRadius` / `ThemeMetrics` / `ThemeType` / `ThemeMotion`. The Compose equivalent is a
`CompositionLocal`-based `PreviouslyTheme` carrying those same namespaces. Pull `material3` in for
the handful of behavioural components you actually want (`Scaffold`'s insets plumbing, ripple /
`Indication`, `ModalBottomSheet`, `AlertDialog`, `NavigationBar` if you use it as a chassis) and
wrap each one so no screen sees an M3 type. Track `MaterialTheme` only as far as needed to keep
those components from drawing purple.

The app is **dark-only and portrait-only** — no light palette to port, no landscape metrics. That
is a constraint the Android side must consciously re-take (see §4.3).

---

## 3. The state-holder pattern — the heart of the port

### 3.1 What the iOS app actually is

`AppModel` is `@MainActor @Observable final class` — one main-thread-confined store with ~40 stored
properties, and Swift's `@Observable` gives **per-property dependency tracking**: a view body that
reads `library` re-runs when `library` changes and not when `now` ticks. The port spec
(`docs/android-port/spec/appmodel.md`, §1) already states the rule:

> `mutableStateOf` per field, or a `StateFlow` per field. **Do not collapse into one immutable
> `UiState` data class** — the scroll/tick invalidation rules depend on fine-grained observation.

That is not a stylistic preference. The iOS app has two named, fixed performance bugs behind it:
the raw scroll offset held as `@State` re-ran Today's entire body at 60–120 Hz ("Today lags", twice),
and there is a 20-second wall-clock tick (`clockTick`) that every countdown reads. Put the clock and
the library in the same immutable `UiState` and every tick invalidates every screen.

### 3.2 The recommendation

**Port `AppModel` as a `@Stable` class whose fields are Compose snapshot state, and give it exactly
one `ViewModel` host.**

```kotlin
@Stable
class AppModel internal constructor(
    private val api: ApiClient,
    private val sync: SyncCenter,
    private val scope: CoroutineScope,          // the host ViewModel's viewModelScope
) {
    // --- library ---------------------------------------------------------
    var library: List<Franchise> by mutableStateOf(emptyList())
        private set
    var loading: Boolean by mutableStateOf(true); private set
    var loadError: Boolean by mutableStateOf(false); private set

    // libraryVersion is @ObservationIgnored on iOS -> a plain var, NOT snapshot state.
    // Bumping it must not invalidate anything.
    private var libraryVersion: Int = 0
    private var libraryIds: Set<String> = emptySet()

    // --- the 20s clock: its own primitive-specialised state ---------------
    var now: Long by mutableLongStateOf(System.currentTimeMillis())
        private set

    // --- derived feeds: derivedStateOf, so readers only wake on real change
    val outNow: List<Franchise> by derivedStateOf { computeOutNow(library, now) }

    // --- out-of-order protection: plain ints, not snapshot state ----------
    private var reloadSeq = 0
    private var searchSeq = 0

    fun reload() {
        val seq = ++reloadSeq
        scope.launch(Dispatchers.Main.immediate) {
            val result = runCatching { api.library() }
            if (seq != reloadSeq) return@launch          // superseded, or teardown() bumped it
            result.onSuccess { applyLibrary(it) }
                  .onFailure { if (!it.isCancellation) loadError = true }
        }
    }

    fun teardown() { reloadSeq++; searchSeq++; /* cancel named jobs */ }
}
```

Rules that fall out of the iOS source and must survive:

1. **Every user-visible field is snapshot state; every bookkeeping field is a plain `var`.**
   `libraryVersion` is `@ObservationIgnored` on iOS *specifically* so bumping it does not
   invalidate views. `reloadSeq`/`searchSeq` likewise. Getting this wrong is silent and expensive.
2. **Use the primitive-specialised builders.** `mutableLongStateOf` for `now` and every epoch-ms
   field, `mutableIntStateOf` for counters — they avoid autoboxing on a value that changes every
   20 s and is read by every countdown.
3. **Derived feeds are `derivedStateOf`, not recomputed in composition.** Today's stacks, the
   Schedule agenda and the Library shelves are all pure functions of `(library, now, localProgress)`.
   `derivedStateOf` gives you the equality gate for free: a tick that does not change the bucketing
   does not invalidate the shelf.
4. **Confine to `Dispatchers.Main.immediate`**, matching `@MainActor`. Snapshot state is
   thread-safe, but the spec's whole correctness argument ("there is **no** background mutation of
   model state anywhere") is easier to keep than to re-derive.
5. **Keep the integer-token pattern.** Do not swap `reloadSeq`/`searchSeq` for `collectLatest`.
   `teardown()` must invalidate responses that are already awaiting, and a bare `collectLatest`
   cannot do that. (Spec §1 says this explicitly.)
6. **Serialised progress writes**: one `Channel(capacity = Channel.CONFLATED)` plus a collector
   coroutine per `mediaId`, held in a `MutableMap<Int, Lane>`. CONFLATED gives you the one-slot
   mailbox and newest-wins drop semantics of `progressQueued` for free.

### 3.3 Why not `StateFlow` + one `UiState`

Google's own state-hoisting guidance recommends exposing screen UI state from a ViewModel as a
`StateFlow` (`stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), …)`), and that guidance
is right *for the shape it describes*: a screen-scoped ViewModel transforming repository flows into
one screen's state. **This app is not that shape.** There is one model behind five tabs, a
20-second tick, and an explicit requirement for per-field observation. Collapsing it into one
`StateFlow<AppUiState>` means:

- every tick allocates a new `AppUiState` and wakes every collector;
- `derivedStateOf`'s equality gate is replaced by hand-written `distinctUntilChanged` on projections;
- the `@ObservationIgnored` distinction (`libraryVersion`) has no expression at all.

I am recommending a **deliberate divergence from the letter of Google's guidance**, and the note
should say so out loud so the next engineer does not "fix" it. The escape hatch if you disagree:
`StateFlow` **per field** (not one blob) is behaviourally equivalent to per-field snapshot state and
is what the port spec offers as the alternative. It costs a `collectAsStateWithLifecycle()` per
field at every read site and buys nothing here, since nothing outside Compose consumes this state.

### 3.4 Why a ViewModel at all, and why only one

Use exactly **one** `@HiltViewModel` — call it `SessionViewModel` — scoped to the single Activity.
It constructs and owns `AppModel`, `SyncCenter` and `RewatchStore`, and calls `AppModel.teardown()`
in `onCleared()`. Screens do **not** get their own ViewModels; they take the `AppModel` from a
`CompositionLocal`, exactly as SwiftUI screens take it from `@Environment`.

```kotlin
@HiltViewModel
class SessionViewModel @Inject constructor(
    apiFactory: ApiClient.Factory,
) : ViewModel() {
    val model: AppModel = AppModel(apiFactory.create(), SyncCenter, viewModelScope)
    override fun onCleared() { model.teardown() }
}

val LocalAppModel = staticCompositionLocalOf<AppModel> { error("No AppModel") }
```

`staticCompositionLocalOf` (not `compositionLocalOf`) is correct: the *reference* never changes, so
you want no invalidation tracking on the local itself — the snapshot state inside does the tracking.

**Why ViewModel rather than the new `retain {}` API.** Compose 1.10 added
`androidx.compose.runtime:runtime-retain` (`retain {}` / `RetainScope`), which survives configuration
changes without serialization and sits between `remember` and `rememberSaveable`. It is tempting as a
"ViewModel-free" state holder. Don't use it for `AppModel`:

- Google's own comparison table assigns `retain` to "UI plumbing, caches, and objects managing
  third-party libraries", and `ViewModel` to "extracting UI-data layer logic … and sharing state
  across large UI areas". `AppModel` is squarely the second.
- `retain` does not survive process death; `SavedStateHandle` does, and the app needs a
  `pendingOpen` franchise id to survive a notification-tap cold start.
- `retain` has no `coroutineScope` and no Hilt integration.
- The docs warn explicitly against retaining anything holding a `Context`.

Do use `retain {}` where it is genuinely right: per-screen caches, and image/media objects that are
expensive to rebuild across rotation.

---

## 4. SDK levels

### 4.1 The honest framing of the iOS analogy

The brief says "the iOS floor is iOS 18 which is ~99 % of active iPhones — pick the Android
analogue." **There is no Android analogue.** iOS 18 is simultaneously recent *and* near-universal
because Apple controls the update path. On Android, recency and reach trade off linearly, and there
is no level that is both. Also: **Google no longer publishes API-level distribution on the public
Distribution dashboard** — that page now carries only Vulkan/OpenGL ES data (last collected
24 Nov 2025). The remaining sources are (a) Android Studio's "Help me choose" dialog, (b) Play
Console → Reach and devices, both of which need a signed-in tool, and (c) third-party
Statcounter-derived tables.

Best public numbers available (apilevels.com, cumulative share of devices at or above each level,
from Statcounter April 2026 data, page updated 28 May 2026):

| minSdk | Android | Cumulative reach |
|---|---|---|
| 28 | 9 Pie | 93.5 % |
| 29 | 10 | 91.1 % |
| **30** | **11** | **86.9 %** |
| **31** | **12** | **78.8 %** |
| 33 | 13 | 68.9 % |
| 34 | 14 | 54.5 % |
| 35 | 15 | 41.0 % |
| 36 | 16 | 22.3 % |

Treat these as ±3 points and skewed toward emerging markets relative to a paid/engaged anime-tracker
audience; real Play Console data for a comparable app usually runs several points *newer*. **Check
Play Console → Reach and devices before locking this in.**

### 4.2 The pick: minSdk 31 (Android 12)

The argument is not reach, it is **fidelity**, and it comes down to one capability:

> `Modifier.blur` requires API level 31; below Android 12 it is a **no-op**, because it is backed by
> `RenderEffect.createBlurEffect`, which is API 31+.

The whole chrome language of *Previously.* is material-over-blur. From `CLAUDE.md`:
`glassChrome` (→ `.ultraThinMaterial`), `HeroTopVeil`, `HeroCopyScrim`, `scrollEdgeChromeBody`, and
the explicit, hard-won rule that a hardened bar is `chromeBarOpacity` **0.74 canvas over
full-strength blur, never opaque canvas** — because at 1.0 the top ~100 pt of every scrolled screen
was a flat slab. On an API-30 device there is no blur under that 0.74 canvas. You would be shipping
the exact bug the iOS team already fixed, permanently, to 8 % of your users.

minSdk 31 also buys, without gating: dynamic colour (unused here, but `Palette`'s art-adaptive
ground is cheaper), the platform `SplashScreen` API (the app has a `SplashView` with a timeline and
an auth hand-off — `androidx.core:core-splashscreen` backports it but the native path is cleaner),
stretch overscroll matching iOS's rubber-banding, and `RenderEffect` for the `ArtBackdrop` blur.

**Cost:** ~8 points of reach versus minSdk 30, ~12 versus 29.

**The runner-up, and it is a real one: minSdk 30 with a gate.** This actually mirrors the iOS
codebase's own philosophy — `DesignSystem/GlassHelpers.swift` exists precisely to be "the one home
for 'iOS 26 flourish, graceful fallback'". An Android `GlassHelpers.kt` that returns
`Modifier.blur(...)` on 31+ and a solid `ThemeColor.canvas.copy(alpha = 0.92f)` scrim below it is
philosophically consistent and buys 8 points. Take this option **if** Play Console shows API 30 at
a meaningful share of your actual audience. Do not take it silently: the fallback is a visibly
different app and must be reviewed as such.

**Rejected:** minSdk 33/34 (you would be shipping to half the market for conveniences you can
gate), and minSdk 28/29 (blur gone, plus notification-permission and foreground-service branching
you do not need).

### 4.3 compileSdk 37, targetSdk 36 — and the portrait problem

- **compileSdk 37** is not a choice: Compose 1.12 requires it, and AGP 9.4 supports up to API 37.
- **targetSdk 36** for v1. Play has required API 36 for new apps and updates since **31 Aug 2026**
  (extensions to 1 Nov 2026 on request), so 36 is the floor, not a preference.
- **Do not jump to targetSdk 37 yet.** Android 16 (targetSdk 36) already ignores orientation,
  aspect-ratio and resizability restrictions on large screens (sw ≥ 600 dp) — but **apps targeting
  36 may still opt out, and apps targeting 37 may not.** *Previously.* is portrait-only by design
  (`UIUserInterfaceStyle: Dark` + portrait lock; the spec says there is "no landscape variant of any
  metric"). So:

  1. Ship v1 at targetSdk 36 with the large-screen opt-out set, portrait-locked on phones.
  2. Treat "does this app have a tablet/foldable layout?" as a **scheduled product decision**, not a
     bug found in 2027 — Play's floor will move to 37 around Aug 2027 and the opt-out disappears
     with it. Navigation 3's `SceneStrategy` is the designed answer (list-detail two-pane on
     sw ≥ 600 dp) and is another reason to pick nav3 now (§7).

- **Predictive back is on by default at targetSdk 36** on Android 16+ devices: `onBackPressed` is
  no longer called and `KEYCODE_BACK` is no longer dispatched. Everything must go through
  `OnBackPressedCallback` / `PredictiveBackHandler` — which Navigation 3's `NavDisplay` already does.
  Never set `android:enableOnBackInvokedCallback="false"`; that is a migration crutch and would cost
  you the animation the iOS app gets free from `NavigationStack`.

---

## 5. Dependency injection

**Pick: Hilt 2.60.1** (released 6 Jul 2026), applied with **KSP**, kept deliberately thin.

Constraint to know: **Hilt 2.59 (21 Jan 2026) added AGP 9 support and made AGP 9 / Gradle 9.1+ a
requirement.** Since we are on AGP 9.4 that is fine, but it means every "Hilt setup 2025" blog you
find (2.51–2.57) is wrong for this project. Also note 2.59.0 shipped a broken artifact
(`ComponentTreeDeps` missing from the runtime jar, google/dagger#5099) — start at 2.60.1, not 2.59.

**Why Hilt over manual DI.** The graph is small (~15 bindings) and a hand-written `AppGraph` built in
`Application.onCreate()` and passed down a `CompositionLocal` would genuinely work — it is what the
iOS app does with `static let shared` singletons. Hilt wins on three concrete integrations rather
than on principle:

1. `hiltViewModel()` for the one `SessionViewModel`, including the Navigation-3 path via
   `rememberViewModelStoreNavEntryDecorator()`.
2. `@HiltWorker` — the episode-notification scheduler ("three per watching anime show from
   `part.airings`, round-robin") is WorkManager work, and hand-wiring a `WorkerFactory` is the
   single most tedious thing manual DI makes you write.
3. Compile-time graph verification. Missing binding = build error, not a launch crash.

**Keep it thin.** One `@Module @InstallIn(SingletonComponent::class)` providing OkHttp/`ApiClient`/
`SyncCenter`/`RewatchStore`, one `@HiltAndroidApp`, one `@AndroidEntryPoint` Activity, one
`@HiltViewModel`. No `@Binds` interface per repository, no feature-scoped components. If that ever
grows past ~30 bindings, that is a signal the port drifted away from "one AppModel".

**Rejected: Koin.** Current stable is 4.1.1 (the docs' BOM page; the 4.2.x line exists with a
Navigation 3 module, `koin-compose-navigation3`, for nav3 1.0.0). Koin is fine software and its
KMP story is better than Hilt's. But: resolution is at runtime, so a missing binding is a crash on a
user's device rather than a red build; it has no WorkManager story comparable to `@HiltWorker`; and
its main advantage (KMP) is one we are explicitly declining in §8. Its LTS story is also aimed at
Kotlin 1.x holdouts, which we are not.

**Rejected: Dagger without Hilt.** All the ceremony, none of the Android integration.

**Rejected: Metro / other 2026 compiler-plugin DIs.** Interesting, but this is a solo-maintained
consumer app that must build reliably against a Kotlin version that moves every three months; the
official-and-boring choice is correct here.

---

## 6. Module structure

**Pick: two Gradle modules.**

```
android/
├── settings.gradle.kts
├── gradle/libs.versions.toml
├── app/                       # com.android.application
│   ├── ui/                    # screens, mirroring ios/Sources/Features/*
│   ├── design/                # PreviouslyTheme, primitives, Palette, GlassHelpers
│   ├── data/                  # ApiClient, auth, disk cache, RewatchStore
│   ├── state/                 # AppModel, SyncCenter, SessionViewModel
│   ├── nav/                   # NavKeys, TopLevelBackStack, NavDisplay wiring
│   └── notify/                # EpisodeNotifications, Glance widget
└── model/                     # org.jetbrains.kotlin.jvm — NO Android dependencies
    ├── Franchise, FranchisePart, airings, enrichment DTOs
    ├── the freshness ladder (airedByNow / behind / lastAired / upcomingAiring)
    ├── Copy (the one place a user-facing string lives)
    └── TemporalCopy / Formatting
```

**Why `:model` is worth the split and nothing else is.** Google's own modularization guide says
plainly that modularizing is not always worth it and that codebase size is the dominating factor —
a single module is the correct default for an app this size. The exception is the one place where
*testing speed* changes behaviour. `docs/android-port/spec/appmodel.md` §5.3 ("the freshness
ladder") is the highest-risk logic in the whole port: anchor-aware `passedAirings`, `airedByNow`,
`behind`, `upcomingAiring`, `scheduledAiring`, plus every sort key. It has already produced named
production bugs on iOS (the Re:ZERO 6:30 PM case; "Returns today" two months into a season). You
want hundreds of table-driven tests over it, running in a plain JVM in under a second, with no
Robolectric and no `android.jar`. A pure-Kotlin `:model` module makes that structurally impossible
to get wrong — you cannot accidentally reach for `android.text.format.DateUtils` in there.

Everything else stays in `:app`. Feature modules for five tabs would buy nothing: there is one
shared `AppModel`, so every "feature" depends on every other one's types anyway.

Escalate to a third module (`:design`) only when you add a screenshot-test harness or a second UI
surface (Wear, Auto) that needs the tokens.

---

## 7. Navigation

**Pick: Navigation 3.** `androidx.navigation3:navigation3-runtime:1.1.7` and
`navigation3-ui:1.1.7` (stable, 26 Aug 2026). 1.0.0 stable shipped 19 Nov 2025 and 1.1.0 stable on
8 Apr 2026, so this is a library with three stable minors behind it, not a bet.

### 7.1 Why it fits this app specifically

The requirement list in the brief — per-tab back stacks, push-detail, re-select-to-pop-to-root,
predictive back — maps onto Navigation 3 almost line for line, because nav3's model is *"the back
stack is a `List` you own"*. That is exactly the iOS model: `MainTabView` holds one
`NavigationPath` per tab and `RootView` pushes `DetailRoute` onto the active one.

- **Per-tab back stacks** are the official `TopLevelBackStack` recipe (developer.android.com,
  "Common UI Recipe", and `github.com/android/nav3-recipes`). It keeps a
  `LinkedHashMap<Key, SnapshotStateList<Key>>` and flattens it for `NavDisplay`. State is retained
  per tab across config changes and process death.
- **Re-select-to-pop-to-root** is one line — truncate that tab's list to its first element. In
  Navigation Compose it is `popUpTo(route) { saveState = true; inclusive = false }` plus
  `restoreState` plus `launchSingleTop`, which is exactly the kind of incantation the iOS code
  avoided by owning the path. It also has to cooperate with `LibraryView.popSignal`, which drops the
  All-titles item destination — trivial when you hold the list, fiddly when the library holds it.
- **Predictive back** is first-class in `NavDisplay` (it drives the pop with the gesture progress),
  which is what you need at targetSdk 36 where the system animation is on by default.
- **The push transition.** The iOS app tried `.zoom` and retired it (3 Sep) in favour of a plain
  push. nav3's `transitionSpec` / `popTransitionSpec` on `NavDisplay` gives you exactly that, and
  `predictivePopTransitionSpec` lets the gesture drive it.
- **The `focusConsumed` bug class.** iOS had a Schedule-routed `focus` that re-pushed on every pop
  and trapped the user. With an owned `SnapshotStateList` the fix is a plain flag next to the list;
  with a `NavController` it is a `savedStateHandle` dance.
- **Deep link → tab select → push** (the episode-alert route: `EpisodeNotifications.onOpen` →
  `pendingOpen` → select Today → push `DetailRoute`) is two mutations on two lists.
- **Future large-screen work** (§4.3) is `SceneStrategy` — the reason nav3 exists.

### 7.2 What it costs

- Nav3 gives you *primitives*, not a framework. You write `TopLevelBackStack` yourself (from the
  official recipe, ~40 lines). That is a feature here, not a cost — the iOS app hand-rolls the same
  thing — but it is a real difference from Navigation Compose.
- `androidx.lifecycle:lifecycle-viewmodel-navigation3` (for
  `rememberViewModelStoreNavEntryDecorator()`) is at **2.12.0-alpha02** while core lifecycle stable
  is **2.11.0** (17 Jun 2026). **Verify the current stable state of this artifact at setup time** —
  if it is still alpha, note that this architecture barely needs it (one Activity-scoped
  `SessionViewModel`, no per-destination ViewModels), so an alpha dependency here is low-risk and
  removable. This is the one loose thread in the nav3 recommendation.

### 7.3 Rejected alternatives

- **Navigation Compose (androidx.navigation 2.10.0, 26 Aug 2026).** The androidx.navigation release
  page now carries the caution *"This library is in maintenance mode and will only receive critical
  fixes; new features are not planned"* (pointing at the Compose-first guidance). **Read that
  carefully and verify before quoting it as gospel** — the banner sits on the page that covers the
  whole Navigation family, and its stated remedy is "use Jetpack Compose", which reads as aimed at
  the Fragment/XML/NavGraph half. Google's May 19 2026 "Android UI Development is Compose First"
  post explicitly named View widgets, Fragments, RecyclerView, ViewPager, the Navigation Editor and
  the Layout Editor as maintenance-mode; it did **not** name navigation-compose. Either way,
  Navigation Compose's `NavController` owns the back stack, which is the one thing this port needs
  to own itself, and its multiple-back-stack support is a bolt-on. Not the right tool even if it
  were fully supported.
- **Voyager** (last release 8 Jun 2026, still maintained). Ergonomic and CMP-friendly, but it is a
  third-party framework that owns your navigation model, and its predictive-back and adaptive-scene
  stories trail the platform's. Adopting it means betting a shipping consumer app on one maintainer
  for the layer Google is actively investing in.
- **Decompose.** Genuinely good, and the right answer if navigation logic must be testable outside
  Compose or must survive a UI-framework change. Neither applies: the iOS app's routing is
  ten lines and a `NavigationPath`, and we have already decided against sharing UI (§8).

---

## 8. Compose Multiplatform: argue both sides, then decide

**Current state of the art:** CMP for iOS has been stable and production-ready since **1.8.0
(6 May 2025)**. **1.10.0 (Jan 2026)** added a common `@Preview`, Navigation 3 on non-Android
targets, and stable Compose Hot Reload. **1.12.0 (26 Aug 2026)** is current; its iOS changelog is
full of SwiftUI-embedding and UIKit back-gesture fixes, which tells you both that people are doing
this seriously and that the seams are still being sanded.

### The case *for* CMP here

- **The logic will drift.** `AppModel` plus the derivations is ~2 000 lines of intricate, rule-heavy
  pure logic — the freshness ladder, the write policy (progress never rolls back, membership always
  does), the newest-wins progress lane, Today's stack ordering. Two independent implementations of
  that will diverge, and the divergences will be subtle, data-dependent and invisible to both test
  suites. This is the single strongest argument and it should not be waved away.
- **The design system is already token-driven and platform-agnostic in shape.** `ThemeColor` /
  `ThemeSpace` / `ThemeType` / `ThemeMotion` translate to Compose almost mechanically; a shared
  `PreviouslyTheme` would genuinely be written once.
- **The screens are the same product.** Today, Schedule, Library, Discover, Profile, Detail — same
  hierarchy, same copy, same states, on both platforms by design.
- Tooling in 2026 is real: hot reload, common previews, a CMP MCP server for agent-driven UI
  iteration (1.12.0).

### The case *against*, which wins

- **The iOS app already exists, ships, and is the differentiator.** CMP's value proposition is
  sharing UI *you have not written yet*. Here half the work is done — and it is the polished half.
  Adopting CMP means either (a) throwing the SwiftUI app away and rewriting it in Compose, or
  (b) maintaining SwiftUI *and* CMP, which is strictly worse than maintaining SwiftUI and native
  Compose.
- **The iOS app's value is precisely the stuff CMP cannot express.** Read `CLAUDE.md`: iOS-26
  Liquid Glass gated through `GlassHelpers`, `.ultraThinMaterial` chrome, `onGeometryChange` scroll
  probes (18 sites), `Tab { }` builders, `onScrollTargetVisibilityChange`, `.principal` toolbar
  docking, `ToolbarSpacer`, Live Activities, WidgetKit, VoiceOver-length-aware toast timers, the
  `.zoom` transition experiment. None of that survives a port to CMP. The whole *point* of this app
  is that it does not feel like a cross-platform app.
- **CMP's iOS scrolling/gesture/accessibility layer is good, not indistinguishable.** For a
  utility app that is fine. For an app whose product thesis is "world-class feel" and which has
  logged named bugs about 80 pt of title slide and 100 pt of flat-black bar, it is not.
- **It would freeze the SwiftUI app.** The brief says the iOS app "will keep evolving". Under CMP
  every iOS change becomes a common-code change reviewed against Android.
- **The Swift-side integration cost is real and ongoing.** Swift export is still **Alpha** as of
  2026 (JetBrains' stated goal is to make it the standard "by 2026"; it is enabled by default since
  Kotlin 2.2.20 but not stable). Absent it you are back to Objective-C interop shapes in Swift.
  And the iOS project is XcodeGen-generated with `project.yml` + a "never hand-edit
  `AniTrack.xcodeproj`" rule — bolting a Gradle-produced framework onto that build is a new class of
  build breakage in a repo that already has documented archive/Metal gotchas.

### Decision

**Do not use Compose Multiplatform for UI. Do not adopt KMP for shared logic on day one either.**

Instead, address the drift risk directly and cheaply:

> **Build a shared golden-fixture corpus.** Put JSON fixtures plus expected outputs in
> `docs/android-port/fixtures/` — a set of `(library payload, now)` inputs and the expected
> `outNow` / `soon` / `nextUp` / `behind` / `shelfState` / `scheduleDays` outputs. Run them from
> Swift XCTest against the shipping iOS model **and** from JVM tests against `:model`. When iOS
> changes a rule, the Android test goes red in CI on the same commit.

That buys you ~90 % of KMP's drift protection for a day of work, no build-system coupling, and no
constraint on either platform's idioms. It also produces something the iOS side does not currently
have: a regression suite over the freshness ladder.

**Revisit KMP for `:model` only if** the fixture corpus proves insufficient (i.e. you find real
drift bugs it did not catch), *and* Swift export has reached Beta/Stable, *and* someone is willing
to own a Gradle dependency inside the Xcode build. Note that `:model` was deliberately shaped in §6
as pure Kotlin with no Android dependencies — converting it to a KMP module later is a
`build.gradle.kts` change, not a rewrite. That is the option value; take it later or never.

---

## 9. Paste-ready configuration

### 9.1 `gradle/libs.versions.toml`

```toml
[versions]
agp = "9.4.0"
kotlin = "2.4.10"
ksp = "2.3.11"                  # VERIFY at github.com/google/ksp/releases — KSP2 no longer tracks the Kotlin version
composeBom = "2026.08.00"
hilt = "2.60.1"
nav3 = "1.1.7"
lifecycle = "2.11.0"
lifecycleNav3 = "2.12.0-alpha02" # VERIFY: check for a stable lifecycle-viewmodel-navigation3
activityCompose = "1.11.0"       # VERIFY against androidx.activity release notes
coroutines = "1.10.2"            # VERIFY
serialization = "1.9.0"          # VERIFY

[libraries]
compose-bom              = { group = "androidx.compose", name = "compose-bom", version.ref = "composeBom" }
compose-foundation       = { group = "androidx.compose.foundation", name = "foundation" }
compose-ui               = { group = "androidx.compose.ui", name = "ui" }
compose-ui-tooling       = { group = "androidx.compose.ui", name = "ui-tooling" }
compose-ui-tooling-prev  = { group = "androidx.compose.ui", name = "ui-tooling-preview" }
compose-material3        = { group = "androidx.compose.material3", name = "material3" }
compose-runtime-retain   = { group = "androidx.compose.runtime", name = "runtime-retain" }
androidx-activity-compose = { group = "androidx.activity", name = "activity-compose", version.ref = "activityCompose" }
androidx-lifecycle-runtime-compose = { group = "androidx.lifecycle", name = "lifecycle-runtime-compose", version.ref = "lifecycle" }
androidx-lifecycle-viewmodel-compose = { group = "androidx.lifecycle", name = "lifecycle-viewmodel-compose", version.ref = "lifecycle" }
nav3-runtime             = { group = "androidx.navigation3", name = "navigation3-runtime", version.ref = "nav3" }
nav3-ui                  = { group = "androidx.navigation3", name = "navigation3-ui", version.ref = "nav3" }
lifecycle-viewmodel-nav3 = { group = "androidx.lifecycle", name = "lifecycle-viewmodel-navigation3", version.ref = "lifecycleNav3" }
hilt-android             = { group = "com.google.dagger", name = "hilt-android", version.ref = "hilt" }
hilt-compiler            = { group = "com.google.dagger", name = "hilt-android-compiler", version.ref = "hilt" }
kotlinx-coroutines-core  = { group = "org.jetbrains.kotlinx", name = "kotlinx-coroutines-core", version.ref = "coroutines" }
kotlinx-serialization-json = { group = "org.jetbrains.kotlinx", name = "kotlinx-serialization-json", version.ref = "serialization" }

[plugins]
android-application = { id = "com.android.application", version.ref = "agp" }
kotlin-android      = { id = "org.jetbrains.kotlin.android", version.ref = "kotlin" }
kotlin-jvm          = { id = "org.jetbrains.kotlin.jvm", version.ref = "kotlin" }
kotlin-compose      = { id = "org.jetbrains.kotlin.plugin.compose", version.ref = "kotlin" }
kotlin-serialization = { id = "org.jetbrains.kotlin.plugin.serialization", version.ref = "kotlin" }
ksp                 = { id = "com.google.devtools.ksp", version.ref = "ksp" }
hilt                = { id = "com.google.dagger.hilt.android", version.ref = "hilt" }
```

### 9.2 `app/build.gradle.kts`

```kotlin
plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.ksp)
    alias(libs.plugins.hilt)
}

android {
    namespace = "app.previously"
    compileSdk = 37                 // required by Compose 1.12

    defaultConfig {
        applicationId = "app.previously"
        minSdk = 31                 // Android 12 — see §4.2 (blur / RenderEffect)
        targetSdk = 36              // Play floor since 2026-08-31; see §4.3 before moving to 37
        versionCode = 1
        versionName = "1.0"
        buildConfigField("String", "API_BASE_URL", "\"https://api.previously.app\"")
    }

    buildFeatures { compose = true; buildConfig = true }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    kotlin { jvmToolchain(21) }     // AGP 9.4 floor is JDK 17; 21 is fine and faster
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

composeCompiler {
    // Turn on for a perf pass; off by default so it does not slow every build.
    // reportsDestination = layout.buildDirectory.dir("compose_compiler")
    // metricsDestination = layout.buildDirectory.dir("compose_compiler")
}

dependencies {
    implementation(project(":model"))

    implementation(platform(libs.compose.bom))
    androidTestImplementation(platform(libs.compose.bom))
    implementation(libs.compose.foundation)
    implementation(libs.compose.ui)
    implementation(libs.compose.material3)
    implementation(libs.compose.runtime.retain)
    debugImplementation(libs.compose.ui.tooling)
    implementation(libs.compose.ui.tooling.prev)

    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)

    implementation(libs.nav3.runtime)
    implementation(libs.nav3.ui)
    implementation(libs.lifecycle.viewmodel.nav3)

    implementation(libs.hilt.android)
    ksp(libs.hilt.compiler)
}
```

`model/build.gradle.kts`:

```kotlin
plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.kotlin.serialization)
}
kotlin { jvmToolchain(21) }
dependencies {
    api(libs.kotlinx.serialization.json)
    implementation(libs.kotlinx.coroutines.core)
    testImplementation(kotlin("test"))
}
// No Android dependency here, on purpose: these tests must run in a plain JVM in milliseconds.
```

`gradle/wrapper/gradle-wrapper.properties`:

```properties
distributionUrl=https\://services.gradle.org/distributions/gradle-9.6.1-bin.zip
```

`gradle.properties`:

```properties
org.gradle.jvmargs=-Xmx4g -XX:+UseParallelGC
org.gradle.configuration-cache=true
org.gradle.caching=true
android.useAndroidX=true
kotlin.code.style=official
```

### 9.3 Navigation skeleton (per-tab back stacks, pop-to-root, predictive back)

Keys are `NavKey` + `@Serializable` so the stack survives process death via `rememberNavBackStack`.

```kotlin
@Serializable data object TodayKey    : NavKey
@Serializable data object ScheduleKey : NavKey
@Serializable data object LibraryKey  : NavKey
@Serializable data object DiscoverKey : NavKey
@Serializable data class  DetailKey(val franchiseId: String) : NavKey
@Serializable data class  SeasonKey(val franchiseId: String, val partId: Int) : NavKey

/** Official nav3 recipe shape (developer.android.com "Common UI Recipe"), plus pop-to-root. */
@Stable
class TopLevelBackStack<T : Any>(startKey: T) {
    private val topLevelStacks = linkedMapOf(startKey to mutableStateListOf(startKey))

    var topLevelKey by mutableStateOf(startKey); private set
    val backStack = mutableStateListOf(startKey)

    private fun sync() = backStack.apply {
        clear(); addAll(topLevelStacks.flatMap { it.value })
    }

    fun switchTo(key: T) {
        if (key == topLevelKey) { popToRoot(); return }          // re-select == pop to root
        if (topLevelStacks[key] == null) topLevelStacks[key] = mutableStateListOf(key)
        else topLevelStacks.remove(key)?.let { topLevelStacks[key] = it }
        topLevelKey = key
        sync()
    }

    /** The iOS "re-selecting the active tab pops to root" rule. */
    fun popToRoot() {
        topLevelStacks[topLevelKey]?.let { stack ->
            if (stack.size > 1) stack.removeRange(1, stack.size)
        }
        sync()
    }

    fun push(key: T) { topLevelStacks[topLevelKey]?.add(key); sync() }

    fun pop() {
        val stack = topLevelStacks[topLevelKey] ?: return
        if (stack.size > 1) stack.removeLastOrNull()
        else if (topLevelStacks.size > 1) {
            topLevelStacks.remove(topLevelKey)
            topLevelKey = topLevelStacks.keys.last()
        }
        sync()
    }
}

@Composable
fun MainTabs(model: AppModel) {
    val nav = remember { TopLevelBackStack<NavKey>(TodayKey) }

    // The alert-tap route: EpisodeNotifications.onOpen -> AppModel.pendingOpen -> Today + push detail.
    LaunchedEffect(model.pendingOpen) {
        model.pendingOpen?.let { id ->
            nav.switchTo(TodayKey)
            nav.push(DetailKey(id))
            model.consumePendingOpen()
        }
    }

    Scaffold(
        bottomBar = { PreviouslyTabBar(nav.topLevelKey, onSelect = nav::switchTo) }
    ) { _ ->
        NavDisplay(
            backStack = nav.backStack,
            onBack = { nav.pop() },                       // also drives predictive back
            entryDecorators = listOf(
                rememberSaveableStateHolderNavEntryDecorator(),
                rememberViewModelStoreNavEntryDecorator(),
            ),
            entryProvider = entryProvider {
                entry<TodayKey>    { TodayScreen(model, onOpen = { nav.push(DetailKey(it)) }) }
                entry<ScheduleKey> { ScheduleScreen(model, onOpen = { nav.push(DetailKey(it)) }) }
                entry<LibraryKey>  { LibraryScreen(model, onOpen = { nav.push(DetailKey(it)) }) }
                entry<DiscoverKey> { DiscoverScreen(model, onOpen = { nav.push(DetailKey(it)) }) }
                entry<DetailKey>   { key -> DetailScreen(model, key.franchiseId,
                                        onSeason = { nav.push(SeasonKey(key.franchiseId, it)) }) }
                entry<SeasonKey>   { key -> SeasonEpisodesScreen(model, key) }
            },
        )
    }
}
```

Note `entryProvider { entry<K> { … } }` is the DSL form; the raw `(key) -> NavEntry` lambda form
also works and is what the docs show first. Attach `transitionSpec` / `popTransitionSpec` /
`predictivePopTransitionSpec` on `NavDisplay` to match the iOS push (which is a plain push — the
`.zoom` transition was tried and retired on 3 Sep).

### 9.4 The Activity

```kotlin
@AndroidEntryPoint
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        installSplashScreen()                       // native at API 31+
        enableEdgeToEdge()                          // required behaviour at targetSdk 35+
        super.onCreate(savedInstanceState)
        setContent {
            val session: SessionViewModel = hiltViewModel()
            CompositionLocalProvider(LocalAppModel provides session.model) {
                PreviouslyTheme { RootView() }      // dark-only; do NOT wrap in MaterialTheme defaults
            }
        }
    }
}
```

---

## 10. Open questions for a human

1. **minSdk 31 vs 30.** Needs Play Console → Reach and devices for a comparable audience, not
   Statcounter. If API 30 is < 4 % of your realistic audience, take 31 and never think about blur
   gating. If it is > 8 %, take 30 and build `GlassHelpers.kt` with a scrim fallback — and accept
   that two visually different apps now need review.
2. **Portrait-only, or adaptive?** targetSdk 37 (mandatory by roughly Aug 2027) removes the
   large-screen orientation/resizability opt-out. Someone has to decide whether *Previously.* gets a
   tablet/foldable layout or accepts being stretched. This is a product decision with a deadline,
   and it should be made before the navigation layer hardens (nav3 `SceneStrategy` is the cheap
   answer if decided early, an expensive retrofit if decided late).
3. **Does `lifecycle-viewmodel-navigation3` have a stable release yet?** It was 2.12.0-alpha02 while
   core lifecycle stable was 2.11.0. If still alpha, confirm we are comfortable shipping one alpha
   AndroidX artifact — or drop it, since this architecture has exactly one ViewModel.
4. **Auth.** Clerk's official Android SDK went GA on 11 Sep 2025, is Kotlin-first and built for
   Compose. Someone should confirm it covers the exact hand-off the iOS app relies on
   (`Clerk.shared.isLoaded` gating, `auth.events` session changes, `signOut()` returning whether the
   session actually ended) before `docs/android-port/spec/networking-auth.md` is treated as settled.
5. **Where does `Copy` live?** Kotlin object in `:model` (matches "one place a user-facing string
   lives", keeps `:model` tests self-contained) vs `strings.xml` (gets you pseudolocale testing and
   future translation). The app is English-only today. My lean is the Kotlin object; flagging it
   because it is hard to reverse once 400 strings exist.
6. **Golden-fixture corpus — who owns it?** §8's drift mitigation only works if the iOS side
   actually runs it in CI. If nobody will own the Swift half, the honest options are (a) accept
   drift, or (b) reopen the KMP `:model` question.
7. **Widgets.** The iOS app has `AniTrackWidgets.swift`. Glance is the Android answer, has its own
   versioning and its own state story, and is not covered here.

---

## 11. Sources

Checked 2026-09-04.

| Claim | Source | Date on source |
|---|---|---|
| Kotlin 2.4.10 latest stable; 2.4.0 on 3 Jun 2026 | https://kotlinlang.org/docs/releases.html | 14 Jul 2026 |
| Compose compiler ships with Kotlin since 2.0.0 | https://developer.android.com/jetpack/androidx/releases/compose-compiler | — |
| AGP 9.4.0; Gradle min 9.6.0, JDK min 17, max API 37 | https://developer.android.com/build/releases/agp-9-4-0-release-notes | Sep 2026 |
| Gradle 9.6.0 released; 9.6.1 current | https://docs.gradle.org/9.6.0/release-notes.html · https://gradle.org/releases/ | 18 Jun 2026 |
| Compose BOM 2026.08.00 → 1.12.0 / material3 1.4.0 | https://developer.android.com/develop/ui/compose/bom/bom-mapping | Aug 2026 |
| Compose 1.12 requires AGP ≥ 9.1.1 and compileSdk 37 | https://android-developers.googleblog.com/2026/08/jetpack-compose-august-2026-release.html | 12 Aug 2026 |
| material3 stable 1.4.0; Expressive alpha-only (1.5.0-alpha27) | https://developer.android.com/jetpack/androidx/releases/compose-material3 | 26 Aug 2026 |
| Play: new apps & updates must target API 36 from 31 Aug 2026 (extension to 1 Nov 2026) | https://developer.android.com/google/play/requirements/target-sdk | — |
| Android 17 = API 37, stable 16 Jun 2026 | Android 17 release coverage; AGP 9.4 notes cap at API 37 | 16 Jun 2026 |
| targetSdk 37 removes the large-screen orientation/resizability opt-out | https://developer.android.com/about/versions/17/behavior-changes-17 | — |
| Predictive back on by default at targetSdk 36; `onBackPressed` not called | https://developer.android.com/about/versions/16/behavior-changes-16 | — |
| API-level cumulative distribution (28→93.5 %, 30→86.9 %, 31→78.8 %) | https://apilevels.com/ (Statcounter, April 2026 data) | page updated 28 May 2026 |
| Google's Distribution dashboard no longer carries API-level data | https://developer.android.com/about/dashboards | data to 24 Nov 2025 |
| `Modifier.blur` requires API 31 (`RenderEffect`), no-op below | Compose `Modifier.blur` reference + `RenderEffect` (API 31) | — |
| StateFlow guidance for ViewModel-exposed screen state | https://developer.android.com/develop/ui/compose/state-hoisting | — |
| `retain {}` in Compose 1.10; retain vs ViewModel guidance | https://developer.android.com/develop/ui/compose/state-lifespans | — |
| Hilt 2.60.1 (6 Jul 2026); 2.59 required AGP 9 / Gradle 9.1+; 2.59 artifact bug | https://libraries.io/maven/com.google.dagger:hilt-android · https://github.com/google/dagger/releases/tag/dagger-2.59 · google/dagger#5099 | Jul 2026 / Jan 2026 |
| Koin stable 4.1.1; 4.2.x adds `koin-compose-navigation3` | https://insert-koin.io/docs/setup/koin/ · https://insert-koin.io/docs/support/releases/ | — |
| Navigation 3: 1.0.0 stable 19 Nov 2025, 1.1.0 stable 8 Apr 2026, 1.1.7 latest stable, 1.2.0-beta01 | https://developer.android.com/jetpack/androidx/releases/navigation3 | 26 Aug 2026 |
| Nav3 model, `NavDisplay`, `entryProvider`, predictive back, per-tab stacks | https://developer.android.com/guide/navigation/navigation-3/basics · .../recipes/common-ui · https://github.com/android/nav3-recipes | — |
| androidx.navigation 2.10.0; maintenance-mode caution on the page | https://developer.android.com/jetpack/androidx/releases/navigation | 26 Aug 2026 |
| "Android UI Development is Compose First" — Views/Fragments/RecyclerView/ViewPager + Nav & Layout editors in maintenance mode | https://android-developers.googleblog.com/2026/05/android-ui-development-is-compose-first.html | 19 May 2026 |
| androidx.lifecycle 2.11.0 stable; lifecycle-viewmodel-navigation3 at 2.12.0-alpha02 | https://developer.android.com/jetpack/androidx/releases/lifecycle | 17 Jun 2026 |
| Modularization: not always worth it, size is the dominating factor | https://developer.android.com/topic/modularization | — |
| CMP iOS stable since 1.8.0 | https://blog.jetbrains.com/kotlin/2025/05/compose-multiplatform-1-8-0-released-compose-multiplatform-for-ios-is-stable-and-production-ready/ | 6 May 2025 |
| CMP 1.10.0 — common `@Preview`, Nav3 on non-Android targets, stable hot reload | https://blog.jetbrains.com/kotlin/2026/01/compose-multiplatform-1-10-0/ | Jan 2026 |
| CMP 1.12.0 current | https://blog.jetbrains.com/kotlin/2026/08/compose-multiplatform-1-12-0/ · https://github.com/JetBrains/compose-multiplatform/releases/tag/v1.12.0 | 26 Aug 2026 |
| Swift export still Alpha | https://kotlinlang.org/docs/native-swift-export.html | — |
| Voyager still released (8 Jun 2026) | https://github.com/adrielcafe/voyager/releases | Jun 2026 |
| Clerk Android SDK GA, Kotlin-first, Compose-oriented | https://clerk.com/changelog/2025-09-11-android-sdk-ga | 11 Sep 2025 |
| KSP2 version scheme decoupled from Kotlin (kotlin 2.4.10 + ksp 2.3.10 in quickstart) | https://kotlinlang.org/docs/ksp-quickstart.html · https://github.com/google/ksp/releases | — |

**Known soft spots in this note.** (a) The exact KSP, activity-compose, coroutines and
kotlinx-serialization versions in §9.1 were not each verified against a primary release page —
verify at setup. (b) The maintenance-mode banner quoted for `androidx.navigation` sits on a page
covering the whole Navigation family; do not quote it as "Navigation Compose is deprecated" without
re-reading it. (c) The distribution percentages are Statcounter-derived, not Play Console data, and
Google has stopped publishing the authoritative version publicly.
