# Profile sheet, app shell, splash, notifications, widget, Live Activity

This is the behavioural specification for the *frame* of **Previously.** — everything that is not a
content screen. It covers the process boot order (`AniTrackApp`), the authentication gate and
cold-launch brand ident (`RootView` + `SplashView`), the four-tab shell with its per-tab navigation
stacks and its deliberately three-layer tint architecture (`MainTabView`), the Profile modal — an
*account sheet* in the App Store's reading order, not a dashboard (`ProfileView`, `LibraryExport`,
`AccountDeletion`), the local episode-alert scheduler (`EpisodeNotifications`), and the two ambient
surfaces the app owns outside its own window: the airing Live Activity (`AiringLiveActivityManager`)
and the widget extension that renders it (`Widgets/AniTrackWidgets.swift`). Three rules from
`CLAUDE.md` govern almost every decision below and must survive the port verbatim: **amber
(`ThemeColor.accent`) is never an action colour** — it means a fact or a state, and every tappable
bare word or glyph uses `ThemeColor.interactive`; **every haptic goes through
`FeedbackCoordinator.fire(_:)`, at most one per transaction**; and **Profile is an account sheet in
the App Store's order** — identity row, one quiet counts line, the Watching shelf, grouped Settings,
a sync *footnote*, Account, Sign out, colophon, Delete — never a plate of display numerals. Every
number here is literal and taken from the shipping source; where the source carries a comment
explaining *why* a number or an ordering is what it is, that comment is quoted, because those
decisions were arrived at by measurement and reverting one re-introduces a named bug.

**Source files covered**

| File | Contents |
| --- | --- |
| `ios/Sources/App/AniTrackApp.swift` | `@main` scene, boot order, tab-bar font proxy, global environment |
| `ios/Sources/App/RootView.swift` | Splash/auth gate, `AppTab`, `MainTabView`, `detailDestinations` |
| `ios/Sources/App/SplashView.swift` | The ~2 s brand ident and its hand-written timeline |
| `ios/Sources/App/SplashShaders.metal` | `emberZoom` (radial smear + chromatic fringe), `filmGrain` |
| `ios/Sources/App/Routing.swift` | `DetailRoute` |
| `ios/Sources/Features/Profile/ProfileView.swift` | The account sheet, `ProfileWash`, `ProfileSnapshot`, `ProfileRow(Label)`, `ExportOptionsView` |
| `ios/Sources/Features/Profile/LibraryExport.swift` | JSON/CSV export payloads |
| `ios/Sources/Features/Profile/AccountDeletion.swift` | `DELETE /me`, deliberately outside `APIClient` |
| `ios/Sources/Notifications/EpisodeNotifications.swift` | Local alert scheduling + foreground presenter + tap route |
| `ios/Sources/Notifications/AiringLiveActivityManager.swift` | Live Activity lifecycle |
| `ios/Shared/AiringActivityAttributes.swift` | The app↔widget ActivityKit contract (member of **both** targets) |
| `ios/Widgets/AniTrackWidgets.swift` | Lock-screen + Dynamic Island rendering |
| `ios/Sources/Auth/SignInView.swift` | First-run screen (summarised — it is the gate's other branch) |

Referenced but specified elsewhere: `design-tokens.md` (`ThemeColor`/`ThemeSpace`/`ThemeMetrics`/
`ThemeType`/`ThemeMotion`/`FeedbackCoordinator`/`PaletteCache`), `primitives.md`
(`GroupedList`, `ShelfCard`, `AccountDisc`, `Wordmark`, `PosterSlot`, button styles),
`primitives-states.md` (`SectionHeaderRow`, `CompactActionButtonStyle`, `SyncBanner`),
`networking-auth.md` (`AuthManager`, `SyncCenter`, `APIClient`), `copy.md` (the string table).

---

## 1. Process boot order

`AniTrackApp.init()` runs **before any view exists** and its statement order is load-bearing.

| # | Statement | Why it must happen here |
| --- | --- | --- |
| 1 | `Self.applyBrandFont()` | UIKit appearance proxies for `UITabBarItem`/`UITabBar` |
| 2 | `AppAppearance.install()` | The one global proxy: `UISearchTextField.appearance().font` |
| 3 | `if AppConfig.isClerkConfigured { Clerk.configure(publishableKey:) }` | *"Configure Clerk synchronously so `Clerk.shared` is valid before the view hierarchy builds."* Touching `Clerk.shared` before `configure()` trips an assertion |
| 4 | `let auth = AuthManager()` | |
| 5 | `let model = AppModel(api: APIClient(tokenProvider: auth))` | |
| 6 | `model.onSessionExpired = { [weak auth] in auth?.sessionExpired() }` | *"A rejected session is auth's problem, not the loader's: the model hands the 401 back here rather than rendering it as 'the server couldn't be reached'."* |
| 7 | `EpisodeNotifications.shared.registerForegroundPresenter()` | *"Delegates must be installed before launch completes, or an alert arriving while the app is open is dropped without ever being presented."* |
| 8 | `EpisodeNotifications.shared.onOpen = { [weak model] id in model?.pendingOpen = id }` | The alert-tap route |
| 9 | `#if DEBUG` `-openDetail <franchiseId>` → `model.pendingOpen = id` | Enters through the *same* route a tapped alert takes |
| 10 | `_auth`/`_appModel` assigned as `State(initialValue:)` | |

There is a discarded `AuthManager()` on line 7 of the file (`@State private var auth = AuthManager()`);
the instance actually used is the one created in `init` and installed via `_auth = State(initialValue:)`.
Port the `init`-created one.

### 1.1 Global scene environment

The root content is wrapped once, at the `WindowGroup`:

| Modifier | Value | Note |
| --- | --- | --- |
| `.environment(auth)` / `.environment(appModel)` | — | Observable objects |
| `.preferredColorScheme` | `.dark` | The app is dark-only; `UIUserInterfaceStyle: Dark` in Info.plist too |
| `.tint` | `ThemeColor.interactive` (= `textPrimary`, `#F4F1EC`) | *"Amber is not an action colour: system chrome — back chevrons, alert buttons, the search field's Cancel and caret — draws in ink."* |
| `.font` | `.custom("Outfit-Regular", size: 17, relativeTo: .body)` | The inherited default so any un-styled `Text` and every `TextField` renders in the brand face, scaled |
| `.dynamicTypeSize` | `...DynamicTypeSize.accessibility2` | *"Scale text for accessibility, but cap before the densest grids break."* AX3–AX5 are clamped to AX2 |
| `.task` | `await auth.bootstrap()` | Starts the ≤3 s Clerk wait |

`rootContent` injects `Clerk.shared` into the environment **only** when `AppConfig.isClerkConfigured`,
for the same assertion reason as step 3.

### 1.2 Tab-bar font proxy (`applyBrandFont`)

The tab item titles are drawn by UIKit, so SwiftUI's inherited font never reaches them.

```
normal   = AppFont.uiFont(size: 10, weight: .medium,   relativeTo: .caption2)   // Outfit-Medium
selected = AppFont.uiFont(size: 10, weight: .semibold, relativeTo: .caption2)   // Outfit-SemiBold
```

Both are set on `UITabBarItem.appearance()` (`.normal`/`.selected`) **and** merged into all three
layout appearances (`stackedLayoutAppearance`, `inlineLayoutAppearance`,
`compactInlineLayoutAppearance`) of a `UITabBarAppearance` that starts from
`configureWithDefaultBackground()`; that appearance is assigned to both `standardAppearance` and
`scrollEdgeAppearance`. Only the **font** is set — the selection tint is left to the system so the
`TabView`'s own `.tint(ThemeColor.accent)` still colours the selected item.

> **Android:** apply the Outfit typeface to the `NavigationBar`'s label `TextStyle`
> (10.sp, `FontWeight.Medium` unselected / `SemiBold` selected, scaled with the system font scale).
> No appearance-proxy equivalent is needed — style the composable directly.

### 1.3 Info.plist keys that change runtime behaviour

| Key | Value | Consequence |
| --- | --- | --- |
| `UIUserInterfaceStyle` | `Dark` | No light theme exists |
| `UISupportedInterfaceOrientations` | Portrait only | No landscape layouts anywhere |
| `CADisableMinimumFrameDurationOnPhone` | `true` | *"allow display-linked custom animation (the splash's TimelineView) to run at up to 120 Hz on iPhone — without this key iOS caps custom animation at 60 fps"* |
| `UILaunchScreen.UIColorName` | `LaunchBackground` = pure `#000000` sRGB | The static launch frame is **true black**, seamless with the splash's own black base |
| `NSSupportsLiveActivities` | `true` | Required for `Activity.request` |
| `UIAppFonts` | Outfit Light/Regular/Medium/SemiBold/Bold `.ttf` | |
| `APIBaseURL`, `ClerkPublishableKey`, `PrivacyPolicyURL`, `TermsURL`, `SupportEmail` | build settings | Read through `AppConfig`; a value that is empty or contains `REPLACE_ME` is treated as **absent** |
| `NSAppTransportSecurity.NSAllowsLocalNetworking` | `true` | Lets a LAN dev server on plain http work |
| `ITSAppUsesNonExemptEncryption` | `false` | Export-compliance answer baked in |

---

## 2. `RootView` — the gate

```
ZStack {
  ThemeColor.canvas.ignoresSafeArea()
  Group { auth.isSignedIn ? MainTabView() : SignInView() }
      .scaleEffect(splashDone || reduceMotion ? 1 : 0.965)
      .blur(radius:  splashDone || reduceMotion ? 0 : 4)
  if !splashDone { SplashView { splashFinished = true; handOffIfReady() }.zIndex(10).transition(.opacity) }
}
```

* Both branches carry `.transition(.opacity.animation(ThemeMotion.uiGentle))` (ease-in-out 0.22 s).
* `MainTabView` carries `.task(id: auth.isSignedIn) { appModel.start() }` — the library load starts
  the instant a session exists, *behind* the splash.
* **The app emerges from inside the ident.** While the splash is up the app tree is drawn at
  **scale 0.965** with a **4 pt blur**; both settle to 1.0/0 when `splashDone` flips, animated by the
  `withAnimation(ThemeMotion.uiSettle)` in `handOffIfReady`. Under Reduce Motion there is no camera
  push to emerge from, so scale and blur are pinned at their settled values and the splash simply
  crossfades away.

### 2.1 `handOffIfReady()` — the two-condition gate

```swift
guard !splashDone, splashFinished, auth.bootstrapped else { return }
withAnimation(ThemeMotion.uiSettle) { splashDone = true }
appModel.surfaceReady = true
```

Called from two places: the splash's `onFinished` callback, and `.onChange(of: auth.bootstrapped)`.
*"The splash leaves when its timeline is done AND auth knows whether there is a session — so the
screen it reveals is the right one, never sign-in for a signed-in user."* `AuthManager.bootstrap()`
waits up to **3 s** (polling `Clerk.shared.isLoaded` every **80 ms**) before setting `bootstrapped`,
so a cold launch on a slow network holds the splash past its 1.68 s timeline rather than flashing
the sign-in screen at a returning user. `appModel.surfaceReady` is the signal Today's recap clock
waits on.

### 2.2 Lifecycle observers

| Trigger | Action |
| --- | --- |
| `onChange(of: auth.bootstrapped)` | `handOffIfReady()` |
| `onChange(of: auth.isSignedIn)` → `false` | `appModel.teardown()`. *"Sign-out … is the one moment the model outlives its account: the library, the live clock, pending episode alerts and a running Live Activity all survive the view tree. Tear them down here so signing in again starts clean."* |
| `onChange(of: scenePhase)` → `.active` (and `auth.isSignedIn`) | `appModel.sceneBecameActive()` |
| `onChange(of: scenePhase)` → `.background` (and `auth.isSignedIn`) | `appModel.sceneEnteredBackground()` |

`sceneBecameActive` snaps the countdown clock (`now = .nowMs`), returns immediately on the launch
activation (`backgroundedAt == nil` — `start()` covers that), and otherwise reloads only when the
away time exceeds `AppModel.staleReloadAfter`, re-stamping `/me/opened` past `newVisitAfter`.

> **Android:** `scenePhase` maps to `Lifecycle.Event.ON_START`/`ON_STOP` on the process-level
> `ProcessLifecycleOwner` — **not** per-Activity `onResume`, which fires for dialogs too.

---

## 3. `SplashView` — the brand ident

A **single-climax ~2 s ident** driven by `TimelineView(.animation)`: *"All motion is pure math over
elapsed real time … Base is true black for OLED — pixels stay off, seamless with the launch frame."*
There are no SwiftUI animations at all; every value is a pure function of elapsed seconds `tm`.

`tm` = `context.date.timeIntervalSince(start)` where `start` is set once in `.onAppear`
(*"so a slow cold launch does not consume the timeline before the first frame"*).
**Under Reduce Motion `tm` is pinned at the constant `1.4`** — a still frame of the ident at its
settled state, held for 1.2 s, then hand-off.

### 3.1 Constants

| Constant | Value | Derivation / meaning |
| --- | --- | --- |
| `ignite` | `0.92` s | The climax. *"IGNITE is when the sweep's leading edge crosses the dot (inOutCubic over the sweep window hits dotX ≈ 0.557 at ~52% → ≈0.92 s) — every climax event (haptic, wordmark punch, light flood) is keyed to it."* |
| `handoff` | `1.68` s | *"Real time at which we hand off to the app — early in the push, so the RootView crossfade overlaps the zoom-through and the app emerges from inside the icon."* |
| `compFraction` | `640/1080` = `0.592593` | Icon comp width ÷ screen width |
| `compTop` | `560/1920` = `0.291667` | Comp top as a fraction of screen height |
| `dotX` | `0.5 + 0.49·0.56·0.32` = **`0.587808`** | *Derived* from `PreviouslyMark`'s geometry (mark width 0.49·comp centred at x 0.5; dot rest offset `+slotWidth·0.32`, slot width `0.56·markWidth`). *"The mock's hand-measured 0.424 was ~30 pt left of where the dot actually lands."* |
| `dotY` | `0.48 − 0.49·1.58·0.24` = **`0.294192`** | Mark centred at y 0.48, height = 1.58·width, slot lift `−height·0.24` |
| `dotArrive` | `0.571` | The sweep value at which the dot reaches its saved place — chosen so `fl` crosses it at `tm ≈ ignite` |
| `wordmarkTop` | `1150/1920` = `0.598958` | |
| `taglineTop` | `1330/1920` = `0.692708` | |
| `ink` | `#F4EFE6` | Wordmark ink (splash-local; **not** `textPrimary`) |
| `accentDeep` | `#C9702E` | Wordmark full-stop gradient end |

### 3.2 Easing helpers

```swift
seg(p, a, b)  = min(max((p - a) / (b - a), 0), 1)          // clamped normalise
outQuint(t)   = 1 - pow(1 - t, 5)
inOutQuint(t) = t < 0.5 ? 16t⁵ : 1 - pow(-2t + 2, 5)/2
inOutCubic(t) = t < 0.5 ? 4t³  : 1 - pow(-2t + 2, 3)/2
inCubic(t)    = t³
outCubic(t)   = 1 - pow(1 - t, 3)
```

### 3.3 Driver values, in order of evaluation

| Symbol | Formula | Window | Reads as |
| --- | --- | --- | --- |
| `ar` | `outQuint(seg(tm, 0, 0.55))` | 0 → 0.55 s | Icon lands from depth (scale 1.16 → 1, blur clears) |
| `fl` | `inOutCubic(seg(tm, 0.50, 1.30))` | 0.50 → 1.30 | The progress dot travels to its saved place |
| `lit` | `seg(fl, dotArrive − 0.07, dotArrive + 0.03)` | — | 0→1 across `fl` ∈ [0.501, 0.601]. **The ignition gate** |
| `dip` | `seg(tm, 0.70, 0.88) · (1 − lit)` | 0.70 → 0.88 | *"the stage light dips a breath before ignition, so the flood that follows reads bigger — contrast bought just before it's spent"* |
| `flood` | `lit · (1 − 0.45·seg(tm, 1.15, 1.60))` | — | Light jumps on the beat, then settles high |
| `w` | `outQuint(seg(tm, 0.92, 1.28))` | ignite → +0.36 | Wordmark punch-in |
| `tg` | `outQuint(seg(tm, 1.06, 1.46))` | | Tagline, a breath later |
| `breathe` | `seg(tm, 1.30, 1.60) · (0.5 + 0.5·sin((tm − 1.30)·π/1.1))` | | Post-ignition dot breath |
| `dotGlow` | `lit·(0.75 − 0.30·seg(tm, 1.10, 1.50)) + breathe·0.15` | | |
| `glowScale` | `1 + 0.45·lit·(1 − 0.75·seg(tm, 1.10, 1.55))` | | |
| `sheen` | `inOutQuint(seg(tm, 1.00, 1.70))` | | One specular pass across the ribbon |
| `push` | `inCubic(seg(tm, 1.60, 2.10))` | 1.60 → 2.10 | The camera dive |
| `tgOut` | `outQuint(seg(tm, 1.55, 1.80))` | | Tagline exit |
| `wOut` | `outQuint(seg(tm, 1.60, 1.90))` | | Wordmark exit |
| `iFade` | `seg(tm, 1.80, 2.08)` | | Icon fade during the dive |

Composites:
```
scale    = (1.16 − 0.16·ar) · (1 + 1.15·push)
comp     = screenWidth · compFraction
dotPoint = (screenWidth/2 + comp·(dotX − 0.5),  screenHeight·compTop + comp·dotY)
```

### 3.4 Layers (z-order, bottom → top)

1. **Background** — `Color.black`, then a 5-stop vertical `LinearGradient`
   `#2A1F14 @0 · #1C1510 @0.22 · #12100C @0.45 · #0C0B09 @0.70 · black @1` at `opacity(ar · 0.9)`;
   then the stage light: `RadialGradient([#4A3B24 @ opacity(0.16 − 0.07·dip + 0.34·flood), .clear])`
   centred `(0.5, 0.42)`, `startRadius 0`, `endRadius 420 + 140·lit`, at `opacity(ar)`;
   then a vignette `RadialGradient([.clear, black@0.4])` centred, `endRadius max(1, 700·ar)`.
2. **Icon** — frame `comp × comp`, `scaleEffect(scale, anchor: UnitPoint(dotX, dotY))` (*"Push scales
   around the dot itself — we zoom THROUGH the ember"*), positioned at
   `(width/2, height·compTop + comp/2)`, `opacity(ar · (1 − iFade))`. Contents:
   * contact ellipse: `black @ (0.22 + 0.26·ar)`, `w = markWidth·(1.25 − 0.15·ar)`,
     `h = markWidth·0.16`, `blur comp·(0.065 − 0.025·ar)`, at `(comp/2, comp·0.88)`;
   * `PreviouslyMark(width: comp·0.49, progress: min(fl/dotArrive, 1), finish: .hero)`
     with `shadow(black@0.5, radius comp·0.08, y comp·0.05)` at `(comp/2, comp·0.48)`;
   * dot glow: `Circle` filled `RadialGradient([#F6BD7D@0.85, accent@0.2, .clear], r 0…comp·0.11)`,
     `comp·0.22` square, `scaleEffect(glowScale)`, at `(comp·dotX, comp·dotY)`, `opacity(dotGlow)`;
   * sheen (drawn only while `0 < sheen < 1`): a `markWidth·0.55 × markWidth·1.8` white-0.09 band,
     rotated 24°, offset `markWidth·(−0.9 + 1.8·sheen)`, `opacity(sin(sheen·π))`, clipped to
     `BookmarkSplashShape` (a splash-local copy of the mark silhouette), at `(comp/2, comp·0.48)`;
   * the whole group is `.compositingGroup()`ed and gets
     `.layerEffect(ShaderLibrary.emberZoom(float2(comp·dotX, comp·dotY), float(push)),
     maxSampleOffset: 140×140, isEnabled: push > 0)`, then `opacity(ar)` and
     `blur((1 − ar)·6)` while `ar < 0.99`.
3. **Shockwave** — mounted only while `ignite < tm < ignite + 0.55`. `ring = outCubic(seg(tm, 0.92, 1.47))`;
   a `Circle().stroke(#F6BD7D @ ((1−ring)²·0.30), lineWidth: 1 + 3.5·(1−ring))`, base size
   `comp·0.12`, `scaleEffect(0.4 + 6.5·ring)`, positioned at `dotPoint`, `blur(1 + 3·ring)`.
4. **Ember bloom** — always mounted. `Circle` filled
   `RadialGradient([#F6BD7D@0.55, accent@0.18, .clear], r 0…comp·0.75)`, size `comp·1.5`,
   `scaleEffect(0.25 + 2.6·push)`, at `dotPoint`, `opacity(sin(min(push·1.25, 1)·π)·0.6)`.
5. **Wordmark** — `"Previously"` + a `"."` filled with
   `LinearGradient([accent, #C9702E], topLeading→bottomTrailing)`, ink `#F4EFE6`,
   font `AppFont.font(size: width·118/1080, weight: .bold)` (≈42.9 pt on a 393-pt screen),
   `kerning(fs·(−0.03·w + 0.025·(1−w)))` (*"letters start airy and settle tight"*),
   `scaleEffect(1.06 − 0.06·w)`, positioned at `(width/2, height·wordmarkTop + fs/2)`,
   `offset(y: (1−w)·14)`, `opacity(w)`, `blur((1−w)·3)` while `w < 0.99`.
   Exit: `scaleEffect(1 + 0.30·outQuint(seg(tm, 1.60, 2.00)), anchor: (0.5, wordmarkTop))`,
   `blur(4·wOut)`, `opacity(1 − wOut)`.
6. **Tagline** — `"ON EVERYTHING YOU WATCH"`, `.system(size: width·25/1080, weight: .medium,
   design: .monospaced)` (**deliberately not Dynamic Type** — *"Fixed-art splash caption"*),
   `kerning(fs·0.34)`, `ThemeColor.accent`, at `(width/2 + fs·0.17, height·taglineTop + fs/2)`,
   `offset(y: (1−tg)·7)`, `opacity(tg·0.8)`. Exit: `scaleEffect(1 + 0.22·outQuint(seg(tm, 1.55, 1.95)),
   anchor: (0.5, taglineTop))`, `opacity(1 − tgOut)`.
7. **Ignition flash** — full-screen `#F6BD7D` at `opacity(0.07·lit·(1 − seg(tm, 0.97, 1.35)))`.

The whole stage carries `.colorEffect(ShaderLibrary.filmGrain(.float(floor(tm·24)/24), .float(0.035)))`
— *"Film grain over the whole ident, quantized to 24 fps … Deliberately near-invisible."*

### 3.5 Shaders

```metal
emberZoom(position, layer, center, strength)
  // strength < 0.001 → passthrough
  // dir = position - center; N = 10 taps
  // tap i: t = i/(N-1); s = 1 - strength*0.18*t; sample layer at center + dir*s
  //   red  channel resampled at center + dir*(s - strength*0.012)
  //   blue channel resampled at center + dir*(s + strength*0.012)
  // result = mean of the 10 taps
filmGrain(position, color, time, intensity)
  // n = fract(sin(dot(position*1.37 + time*61.7, float2(12.9898, 78.233))) * 43758.5453)
  // rgb += (n - 0.5) * intensity * alpha        (intensity = 0.035, time quantised to 1/24 s)
```

### 3.6 The splash's own task (haptic + hand-off)

```swift
if !reduceMotion {
    try? await Task.sleep(for: .seconds(0.92))          // ignite
    FeedbackCoordinator.fire(.selection)                 // "one soft tap exactly as the dot ignites"
}
try? await Task.sleep(for: .seconds(reduceMotion ? 1.2 : 1.68 - 0.92))
onFinished()
```

So: **non-reduced** — haptic at 0.92 s, `onFinished` at 1.68 s, while the stage keeps animating to
2.10 s underneath the crossfade. **Reduced** — no haptic, a static frame of `tm = 1.4`, `onFinished`
at 1.2 s.

> **Android:** the whole ident ports as a `withInfiniteAnimationFrameNanos`/`Choreographer`-driven
> Compose canvas over the same pure-math timeline — nothing here uses a spring, so it is portable
> *exactly*. The two AGSL/RuntimeShader equivalents are available from API 33; below that, either
> drop `emberZoom` (fall back to a plain scale) and `filmGrain` (drop it — it is near-invisible by
> design), or precompose. `Text` with a per-character gradient fill needs a `Brush` on the
> `TextStyle`, which Compose supports. **Difficulty: moderate**, chiefly for the shaders.

---

## 4. `MainTabView` — the four-tab shell

### 4.1 `AppTab`

| Case | `label` / `titleKey` | Icon | Icon kind |
| --- | --- | --- | --- |
| `.today` | `"Today"` | `TabToday` | Asset-catalog **template** PNG (Hugeicons, `@1x/@2x/@3x`, `template-rendering-intent: template`) |
| `.schedule` | `"Schedule"` | `TabSchedule` | template PNG |
| `.library` | `"Library"` | `TabLibrary` | template PNG |
| `.discover` | **`"Search"`** | `magnifyingglass` (**SF Symbol**, not `TabAdd`) | system symbol |

The enum's `icon` property returns `"TabAdd"` for `.discover`, but the `Tab` for that case is built
with `systemImage: "magnifyingglass"` — so `TabAdd` is currently **unreferenced**. The label rule is
recorded in the source: *"'Search', the same word the screen's title and the field's prompt use, and
the word VoiceOver already speaks for a search-role tab. It said 'Add' — a tab named for one of the
things you can do on it, under a magnifier glyph."*

`.discover` is *"An ORDINARY tab in the one tab pill, not the separated search island: the field
lives under the title on the screen itself (Apple Music's Search — user reference, 24 Aug), which the
search role's tab-bar morph did not allow."* Do **not** give it a search role.

### 4.2 State

| Property | Type | Purpose |
| --- | --- | --- |
| `selectedTab` | `AppTab` | Initialised from `MainTabView.launchTab` |
| `paths` | `[AppTab: NavigationPath]` | *"One navigation path per tab; Detail and its episode list push onto the active tab's path."* |
| `libraryRequest` | `LibraryView.AllTitlesRoute?` | An All-titles route requested from another tab |
| `libraryPops` | `Int` | *"Bumped when the Library tab is re-selected: All titles is an item destination, not a path entry, so clearing the path alone left it standing and the tap did nothing."* |
| `zoom` | `@Namespace` | Registered by every card via `zoomSource(_:)`; **nothing consumes it** — see §4.6 |

`launchTab` (DEBUG only) reads `UserDefaults.standard.string(forKey: "openTab")`:
`"schedule"` → `.schedule`, `"library"` → `.library`, `"discover"`/`"search"` → `.discover`,
anything else → `.today`. Release builds always start on `.today`.

### 4.3 Selection binding — re-select pops to root

```swift
Binding(get: { selectedTab }, set: { tab in
    if tab == selectedTab {
        paths[tab] = NavigationPath()
        if tab == .library { libraryPops += 1 }
    } else { selectedTab = tab }
})
```

Because `selectedTab` does not change on a re-select, `.onChange(of: selectedTab) { FeedbackCoordinator.fire(.selection) }`
fires **only on an actual tab change**, never on a pop-to-root.

### 4.4 Tint architecture (three layers, deliberately)

| Layer | Tint | Reason |
| --- | --- | --- |
| App root (`AniTrackApp`) | `ThemeColor.interactive` | System chrome draws in ink |
| `TabView` | `ThemeColor.accent` | *"The bar's selected item is state, so it alone is amber"* |
| Each tab's `NavigationStack` | `ThemeColor.interactive` | *"every stack inside re-tints to ink … so the amber never reaches a back button or an alert"* |

Only controls that *mean state* (the Haptics `Toggle`, `GroupedRow`'s switch/check) carry an explicit
`.tint(ThemeColor.accent)`.

### 4.5 Per-tab wiring

Every tab is `Tab(titleKey, image/systemImage:, value:) { NavigationStack(path: path(tab)) { … }
.tint(.interactive).pageInTransition(isActive: selectedTab == tab) }`, and every root screen carries
`.detailDestinations(push: { push(tab, $0) })`.

| Tab | Root view | Callbacks |
| --- | --- | --- |
| Today | `TodayView` | `onOpenDetail: openDetail`; `onSeeAllWatching` → `libraryRequest = .init(status: .watching)`, `selectedTab = .library`; `onViewAllUpdates` → `libraryRequest = .init(status: nil, unwatchedOnly: true)` (*"No status: Today's 'N updates' counts `outNow`, which is any status. Pinning Watching here made the count and the list disagree the moment a Paused show aired."*); `onOpenLibrary(status)` → filtered All titles; `onAddShow` → `appModel.searchFieldRequested = true`, `selectedTab = .discover` |
| Schedule | `ScheduleView` | `onOpenDetail: openEpisode` (carries an `EpisodeFocus`); `onAddShow` as above |
| Library | `LibraryView` | `onOpenDetail`, `onAddShow`, `requestedAll: $libraryRequest`, `popSignal: libraryPops` |
| Search | `DiscoverView` | `onOpenDetail` |

`openDetail(id, zoomID)` pushes `DetailRoute(id:zoomID:)` on the **currently selected** tab;
`openEpisode(id, zoomID, focus)` pushes the same with `focus`. *"Navigation is silent (board 11): no
haptic on open."*

### 4.6 `detailDestinations` — Detail is a plain push

Applied to every tab root and to every pushed screen:

```swift
.navigationDestination(for: DetailRoute.self) { FranchiseDetailView(...).pushedScreenChrome() }
.navigationDestination(for: FranchiseDetailView.DetailPush.self) { p in
    switch p { case .episodes: SeasonEpisodesView; case .history: WatchHistoryView; case .detail: FranchiseDetailView }
}.pushedScreenChrome()
```

`DetailRoute` is `struct DetailRoute: Hashable, Identifiable { let id: String; let zoomID: String; var focus: EpisodeFocus? = nil }`.

The `.zoom` transition is **retired** and must not be reintroduced: *"the zoom scales the WHOLE
destination into the source's frame, so for its first 150 ms the show page was a miniature of itself —
billboard, pill, title and amber capsule squeezed into a 60×90 poster — inflating ('the details
opening motion is just trash', user, 3 Sep). The HIG reserves zoom for a destination that IS the
source, larger … The `zoomSource` registrations stay: they cost nothing and are the hook if a
transition that fits ever arrives."* Use the system slide.

`pushedScreenChrome()` = `scrollEdgeChromeBody(top: false, bottom: true)` +
`chromeScrollEdgeHidden(.bottom)` + `contentMargins(.bottom, ThemeMetrics.tabBarClearance /* 76 */, for: .scrollContent)`.
It lives on the destination, not on six per-screen opt-ins, *"so every future push inherits it"*.
The top edge is untouched — a pushed screen has a real navigation bar and the system owns that edge.

### 4.7 `pageInTransition` — once per tab

A tab's content fades in from `opacity 0` and rises `6 pt` on `ThemeMotion.uiReveal`
(`timingCurve(0.22, 1.00, 0.36, 1.00, duration: 0.28)`), driven by `onChange(of: isActive)` plus an
`onAppear` fallback. `shown` is **never reset** — *"It runs ONCE per tab: replaying it on every switch
turned ordinary tab changes into a 0.42 s loading beat, so after the first landing a switch is the
instant cut native tabs promise."* Travel is 6, not 10: *"at 10 the first landing reads as content
sliding into place, which is a loading beat; at 6 it reads as the screen coming into focus."*
Under Reduce Motion it is a pure crossfade (`offset` pinned to 0, `uiReduced` = ease-out 0.12 s).

### 4.8 The `.task` that installs the freshness source

```swift
SyncCenter.shared.signals = { .init(lastLoadedAt: appModel.lastLoadedAt, loading: appModel.loading) }
SyncCenter.shared.startMonitoring()
```

*"One freshness source for every stale strip and Profile's sync line."* Until this closure is
installed nothing can be stale and Profile reads **"Not synced yet"** — the honest reading of "this
build has no freshness source wired", never a silent claim of freshness. `startMonitoring()` starts
`NWPathMonitor` on a queue named `previously.reachability`.

### 4.9 Alert-tap routing

```swift
.onChange(of: appModel.pendingOpen, initial: true) { _, id in
    guard let id else { return }
    appModel.pendingOpen = nil
    selectedTab = .today
    paths[.today] = NavigationPath([DetailRoute(id: id, zoomID: "alert/\(id)")])
}
```

`initial: true` so a value set during `AniTrackApp.init` (a cold launch from a notification tap, or
`-openDetail`) is consumed on the first render. The Today path is **replaced**, not appended —
*"opens its show — on Today, above whatever was there."*

### 4.10 `ToastHost` placement

The `TabView` and the toast host sit in a `ZStack(alignment: .bottom)`; the host carries
`.padding(.horizontal, 22)` and `.padding(.bottom, ThemeMetrics.toastClearance /* 62 */)`.

* 22 is the tab bar's own horizontal margin — *"the shipped 17 disagreed with it by 5 pt, which is
  exactly the kind of gap that reads as 'assembled' rather than 'designed'."*
* The bottom inset is measured **from the window**, not from the bar: *"a 12-pt pad put the toast at
  858–935 against a tab pill at 873–935: it covered the tab bar outright … Measured after the fix:
  the toast lands at 815–856 pt against a pill whose top edge is 875, on all four tabs."*

`ToastHost` renders, top→bottom in a `VStack(spacing: 9)`: `SyncBanner` (only when
`!failedChanges.isEmpty && !profileIsOpen`), `ErrorToast`, a neutral `ToastView(message:)` notice, and
the `UndoToast`. Each child is capped at `maxWidth: 420`. Every insertion/removal is animated with
`ThemeMotion.pick(uiSnappy, reduceMotion:)`, and each change is announced to VoiceOver via
`Announce.status`.

### 4.11 `chromeTabBarMinimizeOnScroll()`

iOS 26 only: `tabBarMinimizeBehavior(.onScrollDown)`. Below 26 it is a no-op — *"the bar stays put,
which is what an iOS 18 user expects of a tab bar anyway — so this is a missing flourish, not a
broken layout."*

> **Android — ERRATUM (2026-09-04, PLAN §9.2):** not optional polish, **not done at all**. The port
> ships a **static `NavigationBar`** (PLAN D10): the iOS minimise behaviour is already a no-op on the
> iOS 18 floor, and a hand-rolled `NestedScrollConnection` version is a different component.

---

## 5. `SignInView` (the gate's other branch — summary)

Layout: `ZStack` on `canvas`; `VStack(spacing: 0)` with `Spacer(min 32) · identity · Spacer(min 32) ·
Spacer(min 0) · action`, `.padding(.horizontal, 24)`, `.padding(.bottom, 40)` — *"The identity now
sits on the upper third, where a title card sits."*

Identity: `PreviouslyMark(width: 58)` over a `RadialGradient([accent@0.20, accent@0.05, .clear],
r 0…260)` in a 520×520 frame, `blur 24` (*"The screen's one light source, centred on the one object
it lights"*); `"Previously"` + an **accent** `"."` in `displayXL`, `padding(.top, 20)`;
`"Know what changed. Record what you watched."` in `heroMeta`/`textSecondary`, centred,
`padding(.top, 10)`, `padding(.horizontal, isAX ? 0 : 24)`.

Action, three mutually exclusive branches:
1. `AppConfig.isClerkConfigured` → `Button("Sign in")` in `PrimaryButtonStyle2`, presenting Clerk's
   `AuthView()` in a sheet; on `Clerk.shared.session != nil` it calls `auth.refreshClerkSignInState()`
   and dismisses.
2. `devSignInAvailable` (**`#if DEBUG` AND** `!isClerkConfigured` AND `AppConfig.isLocalBackend`) →
   the developer card: `SectionLabel("Developer sign-in")`, an explanatory `metadata` line, a
   `TextField("dev user id")` (`surfaceFloating`, radius 12, `stroke` border, `minHeight 44`,
   caret `accent`), and `Button("Continue")` in `PrimaryButtonStyle2`; the card is `.surface(.raised,
   radius: ThemeRadius.card)`.
3. Otherwise → `"Sign-in isn’t available in this build."` in `metadata`/`textTertiary`, centred.
   *"Fails CLOSED: no key, no field, no bypass, and nothing a reviewer could mistake for a way in."*

`auth.lastError` renders as an `InlineNotice` beneath, animated with `pick(uiGentle)`.

---

## 6. `ProfileView` — the account sheet

Presented as a **sheet** from Today's header account disc (`AccountDisc(identity:, diameter: 34,
quiet: true)` inside a 44 × 44 target with `OverArtPressStyle`, a11y label `"Profile"`):

```swift
.sheet(isPresented: $showProfile) {
    ProfileView(onOpenLibrary: { status in (onOpenLibrary ?? { _ in onSeeAllWatching() })(status) },
                onOpenDetail: { id in onOpenDetail(id, "profile/\(id)") })
}
```

Both callbacks are optional (`nil` in a build whose presenter has not wired them — *"the tiles then
stay facts rather than pretending to be controls"*). Today wires both.

### 6.1 Scaffold

```
NavigationStack {
  ZStack(alignment: .top) {
    ProfileWash(tint: washTint, fadeEnd: washFadeEnd)
        .offset(y: -max(0, scrollOffset))
        .ignoresSafeArea(edges: .top)
    ScrollView { sheetContent.padding(.horizontal, 16).padding(.top, 16) }
        .scrollIndicators(.hidden)
        .safeAreaPadding(.bottom, 34)
        .chromeScrollEdgeHard(.top)
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top }
                                                   action: { _, y in scrollOffset = y }
  }
  .background(ThemeColor.canvas.ignoresSafeArea())
  .navigationTitle("Profile").navigationBarTitleDisplayMode(.inline)
  .toolbar { ToolbarItem(.topBarTrailing) { Button("Done") { dismiss() } … }.chromeSharedBackgroundHidden() }
}
.onAppear  { SyncCenter.shared.profileIsOpen = true }
.onDisappear { SyncCenter.shared.profileIsOpen = false }
```

Notes with their recorded reasons:

* **The wash travels with the content**, via `offset(y: -max(0, scrollOffset))` — *"Painted fixed to
  the screen it stayed where it was while the plates slid through it, so the SETTINGS plate was warm
  at the top of the scroll and the ACCOUNT plate neutral grey further down — one component, two hues,
  decided by scroll position (M6). Masking alone cannot fix that: 'ends above the stats plate' is only
  true at rest. Anchoring it to the content is."*
* **The system owns the top scroll edge.** `.chromeScrollEdgeHard(.top)` and nothing else — an earlier
  build added `.toolbarBackground(canvas)` on top of it and *"'SETTINGS' was bisected horizontally
  through its x-height by a hard line"* (M1). On iOS 18 `chromeScrollEdgeHard` is a no-op.
* `.safeAreaPadding(.bottom, 34)` — *"The sheet had no bottom inset, so the last line of the colophon
  ended flush against the bezel."*
* **No pull-to-refresh** — deliberately removed, *"from a sheet where it fights interactive dismiss"* (M10).
* `Done` is `Button(Copy.Action.done)` with `.buttonStyle(.plain)`, `ThemeType.bodyEmphasis`,
  `ThemeColor.interactive`; `chromeSharedBackgroundHidden()` drops iOS 26's shared glass capsule
  (*"the capsule renders a lit plate around something that was meant to read as text"*).
* `profileIsOpen` suppresses the global `SyncBanner`: *"Profile lists every failed change with its
  reason, Retry and Discard, so the global banner would be a duplicate of the screen the user is
  already reading."*

> **Known divergence:** Profile uses `onScrollGeometryChange`, while `CLAUDE.md` records that this
> callback *"never fires on the iOS 27 sim"* and that Today/Detail/Library/Search therefore use a
> `Color.clear.onGeometryChange` probe on the scroll content. On such a runtime the Profile wash
> simply does not travel; nothing else breaks. Port it as a scroll-offset observer either way.

### 6.2 Content order and spacing — App Store reading order

`sheetContent` is a `VStack(alignment: .leading, spacing: 0)`:

| # | Block | Top padding | Condition |
| --- | --- | --- | --- |
| 1 | `identity` | — (outer 16) | always |
| 2 | `watchingShelf` | `ThemeSpace.x6` = **24** | only when `shelfItems` is non-empty |
| 3 | `syncSection` | `ThemeMetrics.sectionGap` = **30** | only when `sync.failedChanges` is **non-empty** |
| 4 | `settings` | **30** | always |
| 5 | `syncFootnote` | `ThemeSpace.x2` = **8** | only when `sync.failedChanges` is **empty** |
| 6 | `accountSection` | **30** | always |
| 7 | `signOutSection` | **30** | always |
| 8 | `colophon` | `ThemeSpace.x10` = **40** | always |
| 9 | `deleteSection` | `ThemeSpace.x8` = **32** | always |

3 and 5 are mutually exclusive: the sync **plate** exists only while something failed; otherwise the
state is a one-line footnote under Settings. *"A 'Sync' plate with its own control beside a check mark
was the most SaaS object on the screen for a fact that needs no action while it is true."*

Delete sits **below** the colophon: *"one of these is routine and reversible, the other is not, and
the layout should never let a thumb confuse them. This is where iOS Settings puts it too."*

The header comment records the whole reading-order decision: *"Reading order: who, what they are
watching, then the controls — the App Store account sheet's order. A plate of three display numerals
sat between the name and the shelf and read as a dashboard; the counts are one quiet line under the
name now."*

### 6.3 Identity row

```
HStack(alignment: .center, spacing: 16) {
  avatar
  VStack(alignment: .leading, spacing: 2) {
    Text(accountName)      .type(showTitleL) .foregroundStyle(textPrimary) .lineLimit(1) .minimumScaleFactor(0.7)
    Text(provenance)       .type(metadata)   .foregroundStyle(textSecondary).lineLimit(1)
    if let librarySummary {
      Text(librarySummary) .type(metadata)   .foregroundStyle(textTertiary) .lineLimit(2).padding(.top, 2)
    }
  }
  Spacer(minLength: 0)
}
.padding(.horizontal, 4)
```

**avatar** = `AccountDisc(identity: auth.identity, diameter: 56)` (accent form: `accentSoft` ground,
monogram in `accent`, `posterEdge` ring), plus
`.overlay(Circle().strokeBorder(ThemeColor.hairline, lineWidth: 1).padding(-5))` — a ring drawn 5 pt
**outside** the 56-pt disc (66-pt outer circle) — plus `.shadow(.art)` and `accessibilityHidden(true)`.
*"A ring of canvas, not a hole in the artwork. The disc no longer overlaps the fan, so there is
nothing to punch through."*

`AccountDisc` never draws `person.fill`: the monogram chain is *real initial → first letter of the
label the account is shown under → the `PreviouslyMark` glyph* at `diameter · 0.34`. Monogram type is
`.system(size: diameter · 0.42, weight: .semibold)`, `minimumScaleFactor(0.6)`.

**accountName** = `auth.identity.displayName` — never derived locally: *"Two independent ones produced
'U' there (off the raw Clerk id) and 'Y' here (off this screen's own fallback label): one user, two
meaningless letters, one tap apart."*

**provenance**:

| `auth.identity.provenance` | Release build | Debug build |
| --- | --- | --- |
| `.developer` | `"Signed in"` | `"Developer session"` |
| `.name` / `.email` / `.anonymous` | `"Signed in"` | `"Signed in"` |

*"'Developer session' is a debug string one build configuration away from a TestFlight screenshot, so
it is gated (M5)."*

**Accessibility:** the whole row is one element —
`accessibilityLabel("Signed in as \(accountName)")`,
`accessibilityValue([provenance, librarySummary].compactMap{$0}.joined(separator: ", "))`,
`accessibilityAddTraits(.isHeader)`.

### 6.4 The one quiet counts line (`librarySummary`)

Built as `[String]` joined with `" · "` (`U+00B7` flanked by regular spaces):

1. `Copy.episodes(episodesWatched)` — *"635 episodes"*, with a **non-breaking space** between numeral
   and noun (`Copy.plural` uses `U+00A0`). Omitted when `episodesWatched == nil`.
2. For `.watching` then `.completed`, if the count is known **and > 0**:
   `"\(n) \(Copy.Status(status).lowercased())"` → `"5 watching"`, `"13 watched"` (regular space).
3. `minorStatusLine` — the same shape for `.planned`, `.paused`, `.dropped` (in that order), each
   only when known and > 0, themselves joined with `" · "`, appended as one element.

Result: `"635 episodes · 5 watching · 13 watched · 2 planned · 1 paused"`. `nil` when every part is
absent, in which case the third line is not drawn at all.

*Why `paused` and `planned` are here:* *"'Paused' appeared in 'Black Clover · Moved to Paused' and
nowhere else in the app — a user who paused a show watched Watching drop by one and saw nothing appear
anywhere (M13)."*

**Derivations** — note the deliberate three-valued logic (`nil` = unknown ≠ 0):

```swift
episodesWatched: Int? {
    if !library.isEmpty { return Σ over franchises Σ over parts (part.progress) }
    return sync.lastSyncedAt == nil ? nil : 0
}

count(of status) -> Int? {
    if !library.isEmpty { return library.filter { $0.status == status }.count }   // raw status, not effectiveStatus
    if let known = snapshot.counts[status.rawValue] { return known }
    return sync.lastSyncedAt == nil ? nil : 0    // "A library that loaded successfully and is empty
                                                 //  is a real zero. One that has never arrived is
                                                 //  unknown, and unknown is not zero."
}
```

`episodesWatched` deliberately does **not** consult the snapshot — the snapshot stores counts and
covers only, no episode total.

### 6.5 Watching shelf

```
VStack(alignment: .leading, spacing: ThemeMetrics.labelGap /* 10 */) {
  SectionHeaderRow(Copy.Label.watching /* "Watching" */,
                   actionLabel: onOpenLibrary == nil ? nil : Copy.Action.seeAll,
                   action: onOpenLibrary.map { open in { dismiss(); open(.watching) } })
  ScrollView(.horizontal) {
    HStack(alignment: .top, spacing: ThemeMetrics.shelfGap /* 12 */) { ShelfCard… }
      .padding(.leading, 16).padding(.vertical, 4)
  }
  .scrollIndicators(.hidden).scrollClipDisabled().shelfScroller()
  .padding(.horizontal, -16)     // "The section sits inside the page gutter; the shelf runs edge to edge."
}
.onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { y in
    if scrollOffset <= 1 { shelfTop = y }        // measured at rest only
}
```

`SectionHeaderRow` with a non-`nil` `action` and `inlineAction: false` makes **the title itself the
button**, followed by the count slot (unused here) and a trailing `chevron.forward` at
`.system(size: 14, weight: .semibold)` in `textTertiary`. **The words "See all" are never drawn** —
`actionLabel` only feeds the VoiceOver label `"Watching, See all"`. Tapping dismisses the sheet, then
opens All titles filtered to Watching.

**Cards:** `ShelfCard(title: f.title, caption:, captionIsLead:, poster: f.portraitArt, slot: .todayShelf)`
— poster 100 × 150, radius 11, `.art` shadow. Title uses `title.shelfShortened`, up to 2 lines
(6 at AX), `minimumScaleFactor(0.82)`; caption is `shelfCaption` type, `accent` when `captionIsLead`
else `textSecondary`, 2 lines with tail truncation. Tap: `dismiss()` then `onOpenDetail(f.id)`.
`accessibilityHint` = `"Opens the show"` when the callback exists, `""` otherwise.

**Item selection (`shelfItems`):**

```swift
let live = appModel.watchingShelf            // ranked: newEpisode → backlog → airingWait → premiereSoon
if live.count >= 3 { return Array(live.prefix(12)) }
// otherwise widen with any effectiveStatus == .watching franchise not already present, order preserved
return Array(wider.prefix(12))
```

*"This is the one thing a profile in a TV app should show that a settings screen cannot — the screen
used to go straight from three numbers to a sync row. Netflix's own profile tab opens on the person's
list for the same reason."*

**Caption grammar** — *"Today's shelf-caption grammar, verbatim: a forward-looking fact is amber, a
state is grey."*

| `appModel.shelfState(of: f)` | Caption | `lead` (amber) |
| --- | --- | --- |
| `.newEpisode` | `"New episode"` | **true** |
| `.backlog` | `Copy.Progress.episodeNext(resumePart.progress + 1)` → `"Episode 12 next"` | false |
| `.backlog` with no `resumePart` | *no caption* (`nil`) | — |
| `.airingWait` with a `nextAiring` | `TemporalCopy.airsCompact(at:now:source:)` → `"Today"` / `"Tomorrow"` / `"Friday"` / `"Sep 12"` | **true** |
| `.airingWait` without one | `"Caught up"` | false |
| `.premiereSoon` | `TemporalCopy.returns(at: nextPremiere(of: f), …)` → `"Returns today"` / `"Returns tomorrow"` / `"Returns Friday"` / `"Returns Oct 2"` | **true** |
| `nil` | `"Caught up"` | false |

### 6.6 Sync section (failures only)

```
GroupedList(header: "Sync") {
  ProfileRowLabel(symbol: syncGlyph, symbolTint: syncTint, title: syncTitle, separator: true) {
      if sync.canRetryAny && sync.failedChanges.count > 1 {
          Button(Copy.Action.retryAll /* "Retry all" */) { sync.retryAll() }.buttonStyle(InlineLinkButtonStyle())
      }
  }
  ForEach(failedChanges) { failureRow($0, isLast:) }
}
```

*"the summary row is a heading, not a button, because the plate below it carries real controls and a
row cannot be two things."* No glyph on the detail rows: *"the section's state is declared ONCE, above
them. A stack of identical triangles down one plate is the same defect as a column of grey check
discs — the alarm stops being an alarm."*

**`failureRow(change, isLast:)`** — four slots in reading order (WHAT, WHICH CHANGE, WHY, WHAT TO DO):

```
VStack(alignment: .leading, spacing: 4) {
  HStack(alignment: .firstTextBaseline, spacing: 12) {
      Text(change.title)                  .type(rowTitle)  .foregroundStyle(textPrimary)  .lineLimit(2)
      Spacer(minLength: 8)
      Text(Formatting.fmtTime(change.at)) .type(metadata)  .foregroundStyle(textTertiary)
                                          .monospacedDigit().lineLimit(1).layoutPriority(1)
  }
  Text(change.command)          .type(rowMeta)  .foregroundStyle(textSecondary).lineLimit(2)
  Text(failureReason(change))   .type(metadata) .foregroundStyle(textTertiary) .lineLimit(2)
  actionRow(change).padding(.top, 4)
}
.padding(.leading, 16 + 22 + 12 = 50).padding(.trailing, 16).padding(.vertical, 12)
.frame(maxWidth: .infinity, alignment: .leading)
.overlay(alignment: .bottom) { if !isLast { 1-pt separatorQuiet rule, .padding(.leading, 50) } }
```

The defect this replaced is recorded verbatim: *"the shipped row put 'Black Clover · Moved to Paused'
and 'Couldn't reach the server · 8:44 PM' through a text column narrowed by a fixed action lane, so
the title wrapped at half the available width, the middot dangled at a line end and the clock was
orphaned on line two — while Retry and Discard sat as two ~28-pt words in two competing colours ~20 pt
apart, with the destructive one a mis-tap away from the recovery one (B3, M3)."*

**`actionRow`** — right-aligned; `HStack(alignment: .center, spacing: 20)` normally, and
`VStack(alignment: .trailing, spacing: 8)` at accessibility sizes (*"At accessibility sizes they stack
rather than shrink."*):

| Control | Style | Shape |
| --- | --- | --- |
| `Copy.Action.retry` = `"Retry"` (only when `change.canRetry(sync)`) | `CompactActionButtonStyle` | Bordered: `metadataEmphasis` ink, h-pad 14, `minHeight 44`, `surfaceFloating` ground (`surfacePressed` when pressed), radius 12, 1-pt `stroke` border, press scale 0.985 (opacity 0.72 under Reduce Motion) |
| `Copy.Confirm.discardChangeConfirm` = `"Discard change"` | `InlineLinkButtonStyle(destructive: true)` | Bare text: `listAction` (Outfit SemiBold 13), `ThemeColor.destructive`, v-pad 14 / h-pad 12, `minHeight 44`, pressed opacity 0.55 |

*"Shape, not only colour, tells these two apart: one is a bordered control and the other is a plain
destructive verb. Two identically-shaped capsules differing only in ink is the pattern that makes a
destructive action a mis-tap."* Discard carries
`accessibilityHint("Throws this change away. It can’t be undone.")`.

**Context menu** on the row: `"Retry"` with `arrow.clockwise` (only when retryable) and a destructive
`"Discard change"` with `trash`. The row is `accessibilityElement(children: .contain)`.

**`failureReason(change)`** maps exactly one string on its way to the screen:
`change.reason == Copy.Notice.serverError ("Something went wrong") ? Copy.Account.couldNotReachServer
("Couldn’t connect") : change.reason`. Everything else passes through — *"so it becomes a no-op the
moment the shared copy changes."*

### 6.7 Sync footnote (the calm state)

```
HStack(alignment: .firstTextBaseline, spacing: 8) {
  if let glyph = syncGlyph { Image(systemName: glyph).font(.system(size: 10, weight: .semibold))
                                                     .foregroundStyle(syncTint).accessibilityHidden(true) }
  else { ProgressView().controlSize(.mini).tint(ThemeColor.textTertiary) }
  Text([syncTitle, syncStamp].compactMap{$0}.joined(separator: " · "))
      .type(caption).foregroundStyle(textTertiary).lineLimit(2)
}
.padding(.horizontal, 16)
.accessibilityElement(children: .combine)
```

*"The calm state, as the footnote iOS prints under a group ('Last backup: …'): one line, no plate, no
button."* A `nil` glyph means *"a spinner belongs in this column instead — which is how the row
guarantees it never shows two indicators for one wait."*

### 6.8 Sync state table (one pass, tested in this order)

**Offline is tested before `checking`** — *"the shipped order tested `checking` first, so a device
whose `NWPathMonitor` had already reported no path still watched 'Checking for changes' spin until the
request timed out, and nothing on the screen ever said the user was offline (M4)."*

| # | Condition | `syncTitle` | `syncStamp` | `syncGlyph` | `syncTint` |
| --- | --- | --- | --- | --- | --- |
| 1 | `!failedChanges.isEmpty` | `Copy.Toast.syncFailed(n)` → `"3 changes couldn’t sync"` (NBSP after the numeral) | `nil` | `exclamationmark.triangle.fill` | `ThemeColor.warning` `#FFD60A` |
| 2 | `!isOnline` | `"You’re offline"` | `"Changes sync when you reconnect"` | `wifi.slash` | `textSecondary` |
| 3 | `checking` | `"Checking for changes"` | `nil` | `nil` → **spinner** | falls through to 4/5 |
| 4a | `lastSyncedAt == nil`, snapshot **empty** | `"Not synced yet"` | `nil` | `arrow.triangle.2.circlepath` | `textTertiary` |
| 4b | `lastSyncedAt == nil`, snapshot **present** | `"Couldn’t check for changes"` | `"Showing the copy saved on this device"` | `wifi.exclamationmark` | `warning` |
| 5 | otherwise | `"Up to date"` | `"Checked \(stampWord(at).lowercasedFirstWord())"` | `checkmark` | `textSecondary` |

Case 4b's wording is explained in the source: *"'Not synced yet' is only true if there is also nothing
remembered — with a snapshot's counts and posters on screen it is the screen contradicting itself, and
it was the wording that left 'Checking for changes' looking like the terminal state of an unreachable
server."*

Case 5's three words are a rewrite: *"'Everything synced / Just now / Sync now' said 'sync' three
times and stated one thing twice. Three slots, three words, same information: `Up to date` /
`Checked just now` / `Sync` (M12)."*

Case 5's glyph is a **bare check in the text ramp**, not a green disc: *"The shipped glyph was a
filled `success` disc — the only green in the app, spent decorating a settled state, in a band that
already held an amber 'Sync now' and an amber 'Done' (M11). Colour is not what says 'fine'; the
sentence is."* And the tint is `warning`, never `destructive`, for every failure edge: *"red beside a
red Delete account row makes a recoverable write failure look like data loss (M3, SYS-4f)."*

**`stampWord(ts)` ladder** (elapsed = `max(0, now − ts)`, `minutes = elapsed / 60_000`):

| Condition | Word |
| --- | --- |
| `minutes < 1` | `"Just now"` |
| `minutes < 60` | `"\(minutes) min ago"` |
| `Formatting.dayDiff(ts:now:) == 0` | `Formatting.fmtTime(ts)` → `"9:41 AM"` (locale 12/24 h) |
| otherwise | `TemporalCopy.dateWord(ts, now:, anchor: .local)` → `"Aug 19"` (same year) / `"Aug 19, 2025"` |

`lowercasedFirstWord()` lowercases only the first character (`"Just now"` → `"just now"`), so the
footnote reads **"Up to date · Checked just now"**.

**Dead code to skip:** `syncCanRefresh` (`isOnline && !checking`) and `AccountCopy.syncNow` are
defined and never used — the calm state has no control. Do not port a "Sync" button.

### 6.9 Settings

`GroupedList(header: "Settings")` (header rendered by `SectionLabel`: SF caption2 semibold,
+1.0 tracking, uppercase, `textSecondary`, `padding(.leading, 16)`, `.isHeader` trait; plate is
`.surface(.plate, radius: ThemeRadius.row /* 16 */)` = `plateLift` white-5.5 % over whatever it sits
on, **no border**).

| Row | Symbol | Title | Trailing | Action |
| --- | --- | --- | --- | --- |
| Notifications | `bell` | `"Notifications"` | `HStack(spacing: 8) { Text("On"/"Off") in metadata/textTertiary when known; trailingGlyph("arrow.up.forward", textTertiary) }` | Opens `UIApplication.openSettingsURLString` |
| Haptics | `hand.tap` | `"Haptics"` | A real `Toggle`, `labelsHidden()`, **`.fixedSize()`**, `.tint(ThemeColor.accent)` | Two-way binding to `hapticsOn` |
| Export | `square.and.arrow.up` | `"Export library"` (separator `false`) | `trailingGlyph("chevron.forward", textDisabled, scale: 0.86)` | `NavigationLink` → `ExportOptionsView` |

* **Notifications state:** the row *"said nothing about the one thing it is for. A user who declined
  the system prompt had no way to learn, here, that alerts are off."* The value is refreshed by
  `.task` on first appearance **and** by `NotificationCenter` on
  `UIApplication.didBecomeActiveNotification` (*"Back from Settings: the sheet is still up, so the row
  re-reads the answer."*). `accessibilityValue` = `"On"`/`"Off"`/`""`; `accessibilityHint` =
  `"Opens Settings"`.

  ```swift
  switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
  case .authorized, .provisional, .ephemeral: notificationsOn = true
  case .denied:                               notificationsOn = false
  default:                                    notificationsOn = nil   // .notDetermined → no text at all
  }
  ```
* **The external-link arrow** is `arrow.up.forward`, not a chevron: *"This row leaves the app. An
  external arrow says so; a chevron would not — and an arrow glyph contributes nothing to VoiceOver,
  which announced this identically to the in-app Export row (m1)."*
* **`.fixedSize()` on the Toggle** is the whole fix for a stretched switch: *"without it the row's
  layout stretched the track to ~61×29 against the native 51×31 and rendered the knob as a rounded
  pill instead of a circle."* Its baseline is nudged with
  `.alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 6 }`. Amber, not system green:
  *"a switch reports selection, and selection in this app is one colour."*
* **Export is a push, not a menu:** *"the pushed screen gives each format a title and a real support
  line, and covers nothing (the menu anchored itself over the row that raised it)."*
* `.onChange(of: hapticsOn) { FeedbackCoordinator.enabled = $1; if $1 { FeedbackCoordinator.fire(.selection) } }`
  — turning haptics **on** immediately demonstrates one; turning them off is silent.
  `FeedbackCoordinator.enabled` is backed by `UserDefaults` key `"previously.haptics"`, default `true`.

### 6.10 Export screen (`ExportOptionsView`)

```
ScrollView { VStack(alignment: .leading, spacing: 0) {
    GroupedList {
        exportRow(.json, "JSON", "Every field, machine-readable",   symbol: "curlybraces")
        exportRow(.csv,  "CSV",  "One row per title, for spreadsheets", symbol: "tablecells", separator: false)
    }
    Text(AccountCopy.exportFootnote).type(metadata).foregroundStyle(textTertiary)
        .padding(.horizontal, 16).padding(.top, 10)
}.padding(.horizontal, 16).padding(.top, 16) }
.scrollIndicators(.hidden).background(canvas)
.navigationTitle("Export library").navigationBarTitleDisplayMode(.inline)
```

Footnote, verbatim: *"A copy is created on this device and handed to whatever you share it with.
Nothing leaves your account until you choose a destination."*

Each row is a `ShareLink(item: LibraryExport(appModel:format:), preview: SharePreview("Previously
library (JSON)"))` wrapping a `ProfileRowLabel(…, indicateWait: false)` whose trailing glyph is
`square.and.arrow.up` at `indicatorSize` semibold in `textTertiary` (28 × 44 frame), styled with
`GroupedRowPressStyle`. `accessibilityLabel` = `"Export as JSON"` / `"Export as CSV"`;
`accessibilityHint` = the subtitle.

**The JSON copy is a correctness fix, not a style choice:** *"'JSON — everything, for re-import' in the
one place a user goes when they are worried about their data. The owner's decision is that there is no
library import this round, so the copy stops claiming one … What the file IS, never what it could one
day be fed back into (B1)."* `AccountCopy.exportSubtitle` (`"Every title with progress and status"`) is
defined but **unused** — do not port it.

### 6.11 `LibraryExport`

Both payloads are built **eagerly on the main actor** in `init` (*"The bytes are produced on the main
actor when the export is created, so the transfer itself is plain data."*). The `Format` only selects
which `FileRepresentation` is exported (`.exportingCondition`).

File name: `previously-library.json` / `previously-library.csv`, written atomically to
`FileManager.default.temporaryDirectory`.

**JSON** — `JSONEncoder` with `[.prettyPrinted, .sortedKeys]`, an array of:

```json
{ "id": …, "title": …, "source": "anilist|tmdb", "status": <effectiveStatus.rawValue>,
  "parts": [ { "mediaId": …, "label": <canonicalLabel>, "kind": …,
               "progress": …, "totalEpisodes": … } ] }
```

**CSV** — header `title,source,status,part,kind,progress,total_episodes`, one row **per part**,
`title` and `part` quoted with `"` doubled inside, rows joined with `\n` (no trailing newline).

*"Titles, statuses and progress only — never account identifiers."*

### 6.12 Account section (App Store guideline 5.1.1)

`GroupedList(header: "Account")` with three `legalRow`s, each `ProfileRow` + trailing
`arrow.up.forward` in `textTertiary`:

| Symbol | Title | Subtitle | URL | a11y hint | `.isLink` trait |
| --- | --- | --- | --- | --- | --- |
| `hand.raised` | `"Privacy Policy"` | — | `AppConfig.privacyURL` | `"Opens in Safari"` | yes |
| `doc.text` | `"Terms of Use"` | — | `AppConfig.termsURL` | `"Opens in Safari"` | yes |
| `envelope` | `"Contact support"` | `AppConfig.supportEmail` | `AppConfig.supportURL` (`mailto:`) | `"Opens Mail"` | no (separator `false`) |

**The case rule, settled (m6):** *"Title Case is for the NAMES OF WORKS, and a privacy policy and terms
of use are named documents — 'Privacy Policy', 'Terms of Use'. Everything else on this screen is a verb
phrase in sentence case, including 'Contact support', which is an action and not the name of a
document. Two conventions, one rule, no exceptions."*

Every destination comes from a build setting through `AppConfig`; a value that is empty or contains
`REPLACE_ME` reads as `nil`. `open(nil)` prints one `#if DEBUG` line and returns — *"a developer build
that traps on a Privacy Policy tap is a worse debugging experience than one line in the console."*

> **Divergence to preserve or fix consciously:** `AppConfig`'s own comment says *"the Profile screen
> omits the row rather than drawing one that goes nowhere"*, but `ProfileView` draws all three rows
> unconditionally and only the tap is inert. The shipping build always has all three set, so the case
> is unreachable in production.

### 6.13 Sign out and Delete

Two separate `GroupedList`s (no header), separated by the colophon.

| | Sign out | Delete account |
| --- | --- | --- |
| Symbol | `rectangle.portrait.and.arrow.right` | `trash` |
| Symbol tint | `ThemeColor.textSecondary` | `ThemeColor.destructive` |
| Title | `"Sign out"` in `ThemeColor.destructive` | `"Delete account"` in `ThemeColor.destructive` |
| Subtitle | — | `"Erases your library, progress and history"` |
| In-flight | `ProgressView().controlSize(.small).tint(textSecondary)` in a 44 × 44 frame | same, tinted `destructive` |
| Disabled while | `signingOut \|\| deleting` | `signingOut \|\| deleting` |
| a11y hint | `"Your library stays in your account"` | `"Permanently deletes your account and library"` |

*"The colour carries the weight — but only on the LABEL: a fully saturated destructive icon on a
routine, reversible action made Sign out and Delete account read as a pair of equal choices (M8)."*
And on the spinner: *"Every other write in the app is optimistic and shows its result immediately; the
one that cannot be undone showed nothing at all, so a user who waited a second tapped Sign out again."*

### 6.14 Alerts — all five

**`.alert`, never `confirmationDialog`.** *"On this SDK a confirmation dialog renders as a
source-anchored card that suppresses its own `.cancel` button — the capture showed one red 'Sign out'
capsule floating over undimmed content, so the only way to back out of a destructive confirmation was
to tap outside it, which is undiscoverable. An alert is the presentation that guarantees the three
things this moment needs: a dimming scrim, an explicit Cancel, and the destructive verb rendered as
destructive."*

| Trigger | Title | Buttons | Message |
| --- | --- | --- | --- |
| `confirmSignOut` | `"Sign out?"` | `"Cancel"` (`.cancel`), `"Sign out"` (`.destructive`) → `performSignOut()` | `signOutMessage` |
| `confirmDelete` | `"Delete your account?"` | `"Cancel"`, `"Delete account"` (`.destructive`) → `performDelete()` | `deleteMessage` |
| `deleteFailure != nil` | `"Couldn’t delete your account"` | `"Done"` (`.cancel`) | the `LocalizedError` description, falling back to `AccountDeletion.Failure.refused` |
| `signOutFailed` | `"Couldn’t sign out"` | `"Done"` (`.cancel`) | `"Check your connection and try again."` |
| `discardTarget != nil` | `"Discard this change?"` | `"Cancel"`, `"Discard change"` (`.destructive`) → `sync.discard(id)` | `discardMessage` |

**`signOutMessage`** — one outcome, one supporting sentence:

```
pending == 0 → "Your library stays in your account — sign back in any time."      // em dash U+2014
otherwise    → "Your library stays in your account. \(Copy.changes(pending)) \(verb) synced yet — "
             + "\(pronoun) on this device and upload the next time you sign in."
               verb    = pending == 1 ? "hasn’t" : "haven’t"     // "'3 changes hasn't' — the one verb
               pronoun = pending == 1 ? "it stays" : "they stay" //  in the app that has to agree with its count."
```

**`deleteMessage`** — *"The blast radius, in the user's own numbers. The strongest copy in the app;
not shortened."*

```
"This permanently deletes your account and everything in it"
+ (titles > 0 ? " — \(Copy.titles(titles)), all progress and watch history" : "")
+ ". It can’t be undone."
```

**`discardMessage`** — names its object: `"“\(change.title) · \(change.command)”. It stays on this
device and is never saved to your account."` (curly quotes `U+201C`/`U+201D`), falling back to the bare
`Copy.Confirm.discardChangeMessage` when the target has already gone. *"'Discard' alone beside a show
name is genuinely ambiguous about its object."*

### 6.15 The two destructive flows

```swift
func performSignOut() {
    FeedbackCoordinator.fire(.destructive)                       // UINotificationFeedback .warning
    withAnimation(ThemeMotion.pick(.uiGentle, reduceMotion:)) { signingOut = true }
    Task { let ok = await auth.signOut(); signingOut = false; if !ok { signOutFailed = true } }
}

func performDelete() {
    FeedbackCoordinator.fire(.destructive)
    withAnimation(ThemeMotion.pick(.uiGentle, reduceMotion:)) { deleting = true }
    Task {
        do {
            try await AccountDeletion.deleteAccount(token: auth.currentToken)
            ProfileSnapshot.clear()      // "A deleted account may not leave its counts on the device."
            await auth.signOut()
            deleting = false
            dismiss()
        } catch {
            deleting = false
            deleteFailure = (error as? LocalizedError)?.errorDescription
                         ?? AccountDeletion.Failure.refused.errorDescription
        }
    }
}
```

`auth.signOut()` returns `false` when the session is still standing afterwards — *"before, the spinner
simply stopped and the Profile sheet sat there signed in with nothing to explain why."*
Signing out cascades: `RootView` sees `isSignedIn == false` → `appModel.teardown()` →
`SyncCenter.teardown()`, `RewatchStore.reset()`, `SeasonSweepLedger.reset()`, cached library file
removed, `EpisodeNotifications.cancelAll()`, `AiringLiveActivityManager.endAll()`.

### 6.16 `AccountDeletion`

*"It deliberately does NOT go through `APIClient`. That client is built for reads and for writes the
app can replay: it retries transport failures and silently refreshes a 401. Both behaviours are wrong
here. A request the app is not certain reached the server must be REPORTED, not quietly repeated, and a
session that has expired must be re-authenticated by the user before their account is destroyed …
One attempt, one answer, and the answer is shown to the user either way."*

`DELETE {apiBaseURL}/me`, `Authorization: Bearer <token>`, `Accept: application/json`,
**no body** (*"the route rejects a body it does not recognise"*), `timeoutInterval = 20`.

| Outcome | Result |
| --- | --- |
| No token / empty token | `throw .notSignedIn` |
| `URLSession` throws, or response is not `HTTPURLResponse` | `throw .unreachable` |
| `200` with a body decoding to `{ "deleted": true }` | success |
| `200` with anything else | `throw .refused` — *"a proxy or a captive portal answering for the server, and must not be read as a deletion"* |
| `204` | success |
| `401` / `403` | `throw .notSignedIn` |
| anything else | `throw .refused` |

| Failure | `errorDescription` |
| --- | --- |
| `.notSignedIn` | `"You’re signed out. Sign in again to delete your account."` |
| `.refused` | `"Your account couldn’t be deleted. Nothing was changed."` |
| `.unreachable` | `"Couldn’t reach the server. Your account wasn’t deleted."` |

*"Never a status code: the user is being told whether their account still exists, and '500' does not
answer that."*

### 6.17 Colophon

```
VStack(spacing: 8) {
  Wordmark(colophon: true)      // 11-pt PreviouslyMark (detail .none) + 7-pt gap + "Previously."
                                // in brandWordmark, textSecondary, no shadow
  Text(version).type(caption).foregroundStyle(textTertiary).monospacedDigit()
  Text("Data from AniList and TMDB. This product uses the TMDB API but is not endorsed or certified by TMDB.")
      .type(caption).foregroundStyle(textDisabled)
      .multilineTextAlignment(.center).frame(maxWidth: 330).padding(.top, 8)
}
.frame(maxWidth: .infinity)
.accessibilityElement(children: .combine)
```

`version` = `CFBundleShortVersionString` (fallback `"1.0"`) plus `" (\(CFBundleVersion))"` when present
→ `"1.0 (1)"`.

The attribution string is **App Review-sensitive and must not be reworded**: *"Verbatim-correct and App
Review looks for it — the STRING is untouched. Only the MEASURE changes: at 300 pt the first line
ended on the article 'the', and narrowing it further only bought a three-line set with 'by TMDB.'
orphaned on the last (m3). 330 pt is the width at which the two lines break after a noun."*

`Wordmark(colophon: true)` is the shared lockup: *"this footer had drifted into an accent-period
variant while Today's header drew the period in text ink."* In-app, the full stop is **text ink**;
only the splash and sign-in draw it in amber.

### 6.18 `ProfileWash`

An elliptical field behind the identity block. **It draws no image**: *"`ArtBackdrop` blurs the
poster's own top-left corner, which is why this screen measured rgb(66,80,94) on one side against
rgb(29,49,67) on the other: a blurred crop of an off-centre region is lit by whatever happened to be in
that region, and a 2.2× left-to-right falloff reads as a bug, not as atmosphere. An elliptical field
centred on the top edge is even by construction."*

**Geometry**

```
height = max(fadeEnd + 40, 420)
EllipticalGradient(stops: [ warm@0.28 → 0.00, warm@0.16 → 0.42, warm@0.09 → 0.62,
                            warm@0.04 → 0.80, .clear → 1.00 ],
                   center: UnitPoint(0.5, 0.42), startRadiusFraction: 0, endRadiusFraction: 0.92)
  .frame(height: height).frame(maxWidth: .infinity, alignment: .top)
  .mask(VStack(spacing: 0) {
      Color.clear.frame(height: barBottom)                                        // topSafeInset + 44
      LinearGradient(.clear → .black).frame(height: 90)                           // rampIn
      Rectangle().fill(.black).frame(height: max(0, fadeEnd - barBottom - 90 - 110))
      LinearGradient(.black → .clear).frame(height: 110)                          // rampOut
      Spacer(minLength: 0)
  })
  .allowsHitTesting(false).accessibilityHidden(true)
```

`washFadeEnd` = `shelfTop > 120 ? shelfTop : 260` — the measured screen-space top of the Watching
shelf, with a first-frame fallback. *"Nothing above the bar, a 90-pt ramp under it, and a 110-pt ramp
OUT that lands exactly on the [shelf]'s top edge — so no plate on this screen ever contains the end of
a gradient, which is what produced the visible horizontal tone step inside the stats card."*

**Hue derivation (`warm`)** — the field must vary with the library but never leave the brand's range:

```swift
(bh, bs, bb) = HSB(tint ?? PaletteCache.fallback /* #1C1A17 */)
(ah, as, ab) = HSB(ThemeColor.accent /* #F0A24E → h ≈ 0.0864 (31°), s ≈ 0.675 */)
travel     = clamp(shorterArc(from: ah, to: bh), −0.035, +0.035)   // ±0.035 turns ≈ ±13°
hue        = wrap01(ah + travel)                                   // spans 18°…44°
saturation = clamp(bs*0.5 + as*0.5, lower: 0.30, upper: as)
brightness = 0.85
```

`shorterArc(from,to)` = `to − from`, then `−1` if `> 0.5`, `+1` if `< −0.5`.

*"A free 55 % mix was tried first and is wrong on real artwork: Wistoria's cover derives a teal, and
55 % of the way from teal to amber is olive — a full-screen green field on a warm-branded app.
Interpolating toward a hue and clamping the distance to it are not the same operation, and only the
second one has a floor."*

The tint source is **the centre card of the fan**, resolved asynchronously in
`.task(id: washArtwork) { washTint = await PaletteCache.shared.resolve(url: washArtwork, maxPixel: 360) }`
— *"Resolved here rather than read off `PaletteCache` synchronously: nothing else on this screen primes
the cache on a cold open, so the wash would fall back to neutral."*

### 6.19 Cover selection (and the dead poster fan)

```swift
orderedLibrary = appModel.outNow + appModel.keepWatching
               + (rest where status == .watching) + (rest where status != .watching)
liveCovers     = orderedLibrary.compactMap(\.portraitArt) → count >= 3 ? first 3 : first 1   // 0, 1 or 3
fanCovers      = liveCovers.isEmpty ? snapshot.covers : liveCovers
washArtwork    = fanCovers.isEmpty ? nil : fanCovers[fanCovers.count / 2]
```

*"Always 1 or 3 — a two-poster 'fan' has no centre."* And on the ordering: *"The library in the order
Today ranks it — so the sheet's wash and its poster fan are drawn from the same cover that is on screen
behind the sheet, instead of an unrelated one."*

> **Dead code — do not port:** `posterFan`, `fanAngle` (`[-7°, 0, 7°]`) and `fanOffset`
> (`[-58, 0, 58]`) are fully written and **never rendered** in the current body. `fanCovers` survives
> only as the wash's colour source and the snapshot's payload. The screen draws **no artwork**.

### 6.20 `ProfileSnapshot`

*"Three integers and three URLs in `UserDefaults` is the whole cost of the frame surviving the
failure."* The defect it fixes: *"an offline open collapsed from `fan + disc + name + counts + sync +
settings` to `disc + name + sync + settings`: the stats plate and the artwork were REMOVED rather than
degraded (M4)."*

| Key | Type |
| --- | --- |
| `"profile.snapshot.counts"` | `[String: Int]` — keyed by `WatchStatus.rawValue`, one entry per `allCases` |
| `"profile.snapshot.covers"` | `[String]` — 0, 1 or 3 poster URLs |

`isEmpty` = both empty. *"The screen tells 'never synced' apart from 'couldn't check' with this."*

Capture/clear runs on `.onChange(of: appModel.library.count, initial: true)`:

```swift
if let fresh = ProfileSnapshot.capture(appModel.library, covers: liveCovers) {
    fresh.save(); snapshot = fresh
} else if sync.lastSyncedAt != nil, sync.isOnline {
    ProfileSnapshot.clear(); snapshot = ProfileSnapshot()
}
```

`capture` returns `nil` for an empty library — *"an empty library must never overwrite a real snapshot,
because 'the request failed' and 'the account is empty' arrive as the same value"* — and the clear
branch is gated on a **successful, online** load: *"A library that LOADED and is empty is a real empty
account, not a failure — and the memory has to go with it, or the last show the user removed keeps
posing as their artwork."*

### 6.21 Row primitives (`ProfileRowLabel` / `ProfileRow`)

*"It is deliberately not `GroupedRow`: that primitive paints a tinted 28-pt tile behind its symbol,
hard-codes `success` as its toggle tint and has no destructive or in-flight state."*

```
HStack(alignment: isAX ? .firstTextBaseline : .center, spacing: 12) {
   ── glyph column, width 22 ────────────────────────────────────────────
   symbol != nil          → Image(systemName:).font(.system(size: 16, weight: symbolWeight /* .medium */))
                                              .foregroundStyle(symbolTint /* textSecondary */)
   symbol == nil && wait  → ProgressView().controlSize(.small).tint(textTertiary)
   symbol == nil && !wait → Color.clear.frame(height: 1)
   ── text ──────────────────────────────────────────────────────────────
   VStack(alignment: .leading, spacing: 2) {
       Text(title)   .type(body)     .foregroundStyle(titleTint /* textPrimary */).lineLimit(2)
       Text(subtitle).type(metadata) .foregroundStyle(textTertiary)               .lineLimit(2)
   }
   Spacer(minLength: 8)
   trailing()
}
.padding(.leading, 16).padding(.trailing, 8).padding(.vertical, 8)
.frame(minHeight: ThemeMetrics.rowCompact /* 56 */)
.contentShape(Rectangle())
.overlay(alignment: .bottom) { if separator { 1-pt separatorQuiet, .padding(.leading, textInset) } }
```

* `textInset` = `16 + 22 + 12` = **50** — *"The separator starts where the TITLE starts, never at the
  plate edge — an inset separator is what makes a group read as one thing."*
* Baseline alignment at AX sizes: *"At accessibility sizes a two-line title makes a vertically centred
  glyph sit beside the SUBTITLE. Baseline alignment keeps it with the line it belongs to."*
* `indicateWait` defaults to `true`; the `nil`-symbol spinner is *"how the row guarantees a wait is
  shown once, in one place, and never as a glyph plus a spinner."*
* `ProfileRow` = the same label inside a `Button` with `GroupedRowPressStyle` and `indicateWait: false`.
  `GroupedRowPressStyle` swaps the background to `ThemeColor.surfacePressed` while pressed, animated
  `uiPress` (0.09 s) in and `uiMicro` (spring 0.22/0.88) out.

**`trailingGlyph(symbol, tint, scale)`**:
`Image(systemName:).font(.system(size: indicatorSize * scale, weight: .semibold)).foregroundStyle(tint)
.frame(width: 28, height: 44).alignmentGuide(.firstTextBaseline) { $0[.center] + 6 }`, where
`indicatorSize` is `@ScaledMetric(relativeTo: .body) 14`. *"Fixed-size glyphs shrank to specks against
~24-pt titles at AX1."*

### 6.22 Profile accessibility summary

| Element | Behaviour |
| --- | --- |
| Identity row | One element. Label `"Signed in as {name}"`, value `"{provenance}, {counts line}"`, `.isHeader` |
| `GroupedList` header | `SectionLabel` with `.isHeader` — *"VoiceOver's heading rotor is how a grouped screen is skimmed; without the trait a five-section settings page had one stop."* |
| Shelf card | Combined; label is the **whole** title plus the caption, never `shelfShortened` |
| Shelf header | `"Watching, See all"`, `.isHeader` |
| Notifications row | value `"On"`/`"Off"`, hint `"Opens Settings"` |
| Legal rows | hint `"Opens in Safari"` / `"Opens Mail"`; `.isLink` on the two web rows only |
| Sign out | hint `"Your library stays in your account"` |
| Delete account | hint `"Permanently deletes your account and library"` — *"VoiceOver carries a severity that colour alone no longer does."* |
| Discard change | hint `"Throws this change away. It can’t be undone."` |
| Failure row | `.contain` (children individually reachable) |
| Sync footnote | `.combine` |
| Colophon | `.combine`; `Wordmark` speaks `"Previously"` |
| Wash, avatar, poster art | `accessibilityHidden(true)` |

**Dynamic Type:** capped app-wide at AX2. `isAX` (`dynamicTypeSize.isAccessibilitySize`) switches the
failure row's action layout from horizontal to vertical, the row glyph alignment from centre to
baseline, and `ShelfCard`'s title from 2 lines to 6 with a full-width caption. `indicatorSize` scales
with `.body`.

**Reduce Motion:** every `withAnimation` on this screen goes through
`ThemeMotion.pick(_:reduceMotion:)` → `uiReduced` (ease-out 0.12 s). No screen-level transition,
parallax or drift exists here.

**Reduce Transparency:** not consulted on this screen; it affects `ChromeGlassBox` and the scroll-edge
veils elsewhere.

---

## 7. `EpisodeNotifications` — local episode alerts

A `@MainActor final class` singleton (`EpisodeNotifications.shared`) using `UNUserNotificationCenter`
only. *"AniList gives us each watching show's next airing instant, so the app schedules one local
notification per show — no push infrastructure needed."*

### 7.1 Constants

| Constant | Value | Reason |
| --- | --- | --- |
| `maxPending` | **48** | *"iOS caps pending local notifications at 64 per app; stay safely under it."* |
| `perShow` | **3** | *"One used to be all there was, so a viewer who got the alert for episode 5 and did not open the app for three weeks heard nothing about 6, 7 or 8 — the feature went quiet for exactly the person it exists to bring back."* |

`foregroundPresenter` is held **strongly** by the singleton: *"`center.delegate` is weak, and a
deallocated delegate silently restores the 'drop it' default."*

### 7.2 Permission

```swift
switch await center.notificationSettings().authorizationStatus {
case .notDetermined: return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
case .denied:        return false
default:             return true
}
```

Requested **only** from the Search-tab primer, *"the first time it's worth having (an airing show was
just added), so the system prompt lands with obvious context instead of firing at first launch."*
On grant: `FeedbackCoordinator.fire(.success)`, `appModel.showNotice("Episode alerts on")`, and
`await appModel.alertsWereAllowed()` → `syncAmbient()` — *"They used to wait for the next reload —
'Turn on' granted permission and scheduled nothing, so the first alert could be a day away."*
Declining produces no receipt: *"declined is the system's own answer and needs no second one."*

### 7.3 `sync(library:now:)` — the whole algorithm

1. Read `notificationSettings()`. **Return immediately** unless the status is `.authorized`,
   `.provisional` or `.ephemeral` — the pending set is left untouched.
2. Eligible shows: `effectiveStatus == .watching` **AND** `source == .anilist`.
   *"TMDB air times are date-precision only (synthesized 17:00 UTC), so time-of-day alerts would fire
   at a meaningless instant."* This is a **harder gate than Schedule/Today**, which admit any status
   with `tracksAirings`.
3. Per show: take `f.releasingPart` (skip if none), then
   `part.airings.filter { $0.at > now }.sorted { $0.at < $1.at }.prefix(3)`, mapping each to
   `(franchiseId: f.id, title: f.displayTitle, mediaId: part.mediaId, episode: slot.episode, airsAt: slot.at)`.
4. **Fallback** for a server that predates per-episode airings: if the slot list is empty and
   `part.nextAiringAt > now`, use a single slot with `part.nextEpisodeNumber`.
5. Shows with no slots are dropped.
6. **Round-robin flattening** — *"every show keeps its soonest alert before any show gets its second,
   so a large library never starves a show of its next episode for another's third"*:

   ```swift
   for rank in 0..<3 {
       upcoming += perShow.compactMap { $0.count > rank ? $0[rank] : nil }.sorted { $0.airsAt < $1.airsAt }
   }
   ```
   Each rank block is internally sorted by time, and the blocks concatenate — so the final order is
   *(all firsts, soonest→latest), (all seconds, soonest→latest), (all thirds …)*, **not** a global
   time sort.
7. `upcoming = Array(upcoming.prefix(48))`.
8. `center.removeAllPendingNotificationRequests()` — *"The app schedules nothing else, so a full clear
   + re-add keeps this idempotent."*
9. Add each request:

| Field | Value |
| --- | --- |
| `identifier` | `"episode-\(mediaId)-\(episode ?? 0)"` |
| `content.title` | `f.displayTitle` (i.e. `title.shelfShortened` — *"Re:ZERO"*, not the source string) |
| `content.body` | `Copy.Alert.episodeOut(episode)` → `"Episode 12 is out now"`, or `"A new episode is out now"` when the number is unknown. **No full stop** — *"Apple's own alerts carry none."* |
| `content.sound` | `.default` |
| `content.threadIdentifier` | `franchiseId` — *"group repeat alerts per franchise"*, and the tap route's payload |
| `trigger` | `UNTimeIntervalNotificationTrigger(timeInterval: max(1, Double(airsAt − now) / 1000), repeats: false)` |

**Callers of `sync`** — `AppModel.syncAmbient()`, invoked after: a successful library `reload()`,
`alertsWereAllowed()`, a confirmed `setStatus`, and a confirmed `removeFromLibrary`. *"AppModel
re-syncs the pending set after every confirmed library change (reload / status change / remove), so
the schedule always mirrors the library."*

### 7.4 `cancelAll()`

`removeAllPendingNotificationRequests()` **and** `removeAllDeliveredNotifications()`. Called from
`AppModel.teardown()` on every sign-out: *"the schedule is built from one account's library, so leaving
it armed would announce the previous user's episodes to whoever signs in next (or to nobody at all)."*

### 7.5 `ForegroundPresenter`

```swift
willPresent(_:) async -> UNNotificationPresentationOptions { [.banner, .sound, .list] }

didReceive(response) async {
    guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
    let id = response.notification.request.content.threadIdentifier
    guard !id.isEmpty else { return }
    log.info("alert opened: \(request.identifier)")     // subsystem "app.previously", category "alerts"
    await MainActor.run { onOpen?(id) }
}
```

*"An episode alert most often fires while you're IN the app — that's what 'it's out now' means. Without
a delegate iOS suppresses it entirely, so the one notification the app schedules was silently dropped
at exactly its most likely moment."*

The full tap route: `didReceive` → `onOpen(franchiseId)` → `AppModel.pendingOpen` →
`MainTabView.onChange` → select Today, replace its path with `[DetailRoute(id:, zoomID: "alert/\(id)")]`.

> **Android:** the scheduler ports to `AlarmManager`/`WorkManager` + `NotificationManager`. There is no
> 64-request cap, so `maxPending = 48` and the round-robin are not strictly required — **keep them
> anyway** so both platforms fire the same alerts. `threadIdentifier` → the notification **group key**
> plus a `franchiseId` extra on the `PendingIntent`. Foreground presentation is Android's default
> (heads-up on a high-importance channel), so no delegate is needed. **Difficulty: easy**, except that
> exact-time delivery needs `SCHEDULE_EXACT_ALARM` / `setExactAndAllowWhileIdle` and a POST_NOTIFICATIONS
> runtime permission (API 33+) — which maps cleanly onto the existing primer.

---

## 8. Live Activity (`AiringLiveActivityManager`)

*"Without push updates an activity can only be started/updated while the app runs, so the model is
deliberately simple: every ambient sync (launch, foreground, library change) picks the ONE soonest
watching-show episode airing within the lead window and makes the activity match it. The countdown
itself ticks natively in the widget (`Text(timerInterval:)`) — no updates needed while backgrounded."*

| Constant | Value |
| --- | --- |
| `leadWindow` | `60 * 60_000` = **1 hour** — *"Start the lock-screen countdown when an episode airs within the next hour."* |
| `linger` | `15 * 60_000` = **15 minutes** — *"Keep the activity visible this long after air time ('out now'), then let it go stale."* |

### 8.1 Candidate selection

```swift
let enabled = ActivityAuthorizationInfo().areActivitiesEnabled
candidate = enabled ? library
    .filter { $0.effectiveStatus == .watching && $0.source == .anilist }   // anime only, same reason
    .compactMap { f in
        guard let part = f.releasingPart, let at = part.nextAiringAt else { return nil }
        guard at - now <= leadWindow, now - at <= linger else { return nil }
        return Candidate(title: f.title /* RAW title, not displayTitle */, episode: part.nextEpisodeNumber, airsAt: at)
    }
    .min { $0.airsAt < $1.airsAt }
  : nil
```

Note the asymmetry with notifications: the Live Activity uses `f.title` (the full source string) while
alerts use `f.displayTitle`. Preserve it or fix it deliberately.

### 8.2 Reconciliation

All ActivityKit access happens inside **one `Task.detached`** — *"activity handles are fetched and
consumed in the same isolation region (Swift 6 rejects sending them across actors)."*

| State | Action |
| --- | --- |
| No candidate | `end(nil, dismissalPolicy: .immediate)` on **every** current activity |
| An activity already matches `(franchiseTitle, episodeNumber)` | `update(content)` on it, then end every other activity |
| Otherwise | End all, then `Activity.request(attributes:content:)` (errors swallowed with `try?`) |

`ActivityContent(state: ContentState(airsAt: Date(ms/1000)), staleDate: airsAt + 15 min)`.

`endAll()` ends every activity unconditionally; called from `AppModel.teardown()` — *"a lock-screen
countdown for a show in the previous account's library outlives the session that made it, and nothing
in `sync` can retire it once that library is gone."*

### 8.3 The shared contract

`ios/Shared/AiringActivityAttributes.swift` is a member of **both** targets — *"ActivityKit matches app
and widget by the attributes type name, so it must be identical."*

```swift
struct AiringActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable { var airsAt: Date }
    var franchiseTitle: String
    var episodeNumber: Int?
}
```

> **Android: there is no Live Activity.** The closest equivalents are (a) an ongoing notification with
> `setUsesChronometer(true)` + `setChronometerCountDown(true)`, which gives the self-ticking countdown
> for free and works on the lock screen; (b) Android 16's `Notification.ProgressStyle` / "Live Updates"
> for the promoted-notification treatment; (c) a Glance app widget for the home screen. **There is no
> Dynamic Island analogue at all.** Difficulty: **moderate** for (a) — the state machine ports one for
> one — and **blocker** for exact Dynamic Island parity.

---

## 9. Widget extension (`AniTrackWidgets`)

A `WidgetBundle` containing exactly one widget, `AiringLiveActivity`. There is **no home-screen widget**
in this build. Bundle id `com.anitrack.app.widgets`, `NSExtensionPointIdentifier
com.apple.widgetkit-extension`, display name `"Previously."`.

*"Design system note: extensions don't bundle the Outfit fonts or Theme — colors are inlined
(accent `0xF0A24E`, background `0x0B0B0E`) and type is the system font, which is conventional for
lock-screen surfaces."* Note `#0B0B0E` ≠ `ThemeColor.canvas` `#09090B`; the extension carries its own
near-black.

Configuration: `.activityBackgroundTint(backdrop.opacity(0.9))`,
`.activitySystemActionForegroundColor(accent)`.

### 9.1 Lock-screen / banner presentation

```
HStack(alignment: .center, spacing: 12) {
  VStack(alignment: .leading, spacing: 4) {
    HStack(spacing: 6) {
      Image(systemName: "dot.radiowaves.left.and.right").font(.caption.weight(.bold)).foregroundStyle(accent)
      Text(episodeLabel).font(.caption.weight(.semibold)).foregroundStyle(accent)
    }
    Text(franchiseTitle).font(.headline).foregroundStyle(.primary).lineLimit(1)
    Text(airLine).font(.caption).foregroundStyle(.secondary)
  }
  Spacer(minLength: 8)
  CountdownText.font(.title2.weight(.semibold).monospacedDigit()).foregroundStyle(accent)
}
.padding(16)
```

### 9.2 Dynamic Island

| Region | Content |
| --- | --- |
| Expanded `.leading` | `VStack(alignment: .leading, spacing: 2)`: title in `.headline`, 1 line; `episodeLabel` in `.caption`/`.secondary`. `.padding(.leading, 4)` |
| Expanded `.trailing` | `CountdownText` in `.title3.weight(.semibold).monospacedDigit()`, `accent`. `.padding(.trailing, 4)` |
| Expanded `.bottom` | `airLine` in `.caption`/`.secondary` |
| `compactLeading` | `Image(systemName: "dot.radiowaves.left.and.right")` in `accent` |
| `compactTrailing` | `CountdownText` in `.caption2.monospacedDigit()`, `accent`, `frame(maxWidth: 52)` |
| `minimal` | the same radiowaves glyph in `accent` |

### 9.3 Text derivations

```swift
CountdownText: airsAt <= Date()
    ? Text("Out now")
    : Text(timerInterval: min(Date(), airsAt)...airsAt, countsDown: true).multilineTextAlignment(.trailing)
```
*"The lower bound must not exceed the upper — clamp so a re-render near the boundary can't form an
invalid range."*

```swift
episodeLabel = episodeNumber.map { "Episode \($0)" } ?? "Next episode"
// "The app's own notation ('Episode 19', never all caps) — the lock screen is still the app."

airLine = airsAt <= Date() ? "Aired just now"
                           : "Airs at \(airsAt.formatted(date: .omitted, time: .shortened))"
```

---

## 10. Debug launch arguments (complete)

All are read via `UserDefaults.standard` (so `-key value` on the launch command line) and, except
`-openAllTitles`/`-openSearchField`/`-scheduleFilter`, are wrapped in `#if DEBUG`.

| Argument | Read in | Effect |
| --- | --- | --- |
| `-openDetail <franchiseId>` | `AniTrackApp.init` | Sets `pendingOpen` → lands on that show page via the alert-tap route |
| `-openTab today\|schedule\|library\|discover\|search` | `MainTabView.launchTab` | Chooses the initially selected tab (default `today`) |
| `-openProfile 1` | `TodayView.onAppear` | Opens the Profile sheet |
| `-openAllTitles 1` | `LibraryView` | One-shot: opens All titles |
| `-openSearchField 1` | `DiscoverView` | Opens Search with the field focused |
| `-recapDemo 1` | `TodayView` | Forces the full Previously Recap |
| `-calmDemo 1` | `TodayView` | Empties the focus stack so the calm open renders over a library with backlog |
| `-scheduleEarlier 1` | `ScheduleView` | Opens the Earlier block expanded |
| `-scheduleFilter anime\|tv` | `ScheduleView` | Opens with that source filter |
| `-scheduleHideWatched 1` | `ScheduleView` | Opens with watched episodes hidden |
| `-detailAnchor trailers\|people\|related\|watch` | `FranchiseDetailView` | Scrolls to a catalogue shelf |
| `-detailTrailer 1` | `FranchiseDetailView` | Opens the first trailer's sheet |
| `-detailOpenRelated <N>` | `FranchiseDetailView` | Opens the Nth related title |
| `-devSignInId <clerkId>` | `SignInView` | Pre-fills the dev id field (default `"demo-user"`) |
| `-devSignInAuto 1` | `SignInView` | Signs in on appear with the seeded id |

*"the way to photograph the show page when the simulator cannot be touched."*

> **Android:** map these onto `Intent` extras read in the launcher Activity, gated on `BuildConfig.DEBUG`,
> or `adb shell am start -e openTab library`. Nothing here is iOS-specific.

---

## 11. Values reference (things this area introduces)

| Name | Value | Where |
| --- | --- | --- |
| Profile sheet outer padding | h 16, top 16, bottom safe-area 34 | `ProfileView` |
| Identity disc | 56 pt; hairline ring at −5 pt inset (66 pt outer) | `avatar` |
| Failure row text inset | 50 (`16 + 22 + 12`) | `failureRow`, `ProfileRowLabel.textInset` |
| Failure action gap | 20 pt horizontal / 8 pt vertical at AX | `actionRow` |
| Profile row min height | 56 (`ThemeMetrics.rowCompact`) | `ProfileRowLabel` |
| Trailing glyph frame | 28 × 44, baseline nudge `+6` | `trailingGlyph` |
| Indicator base size | `@ScaledMetric(.body) 14` (chevron × 0.86) | `indicatorSize` |
| Colophon attribution measure | `maxWidth 330` | `colophon` |
| Wash bar clearance | `topSafeInset + 44` | `ProfileWash.barBottom` |
| Wash ramp in / out | 90 / 110 | `ProfileWash` |
| Wash hue travel | ±0.035 turns (±13°) | `ProfileWash.hueTravel` |
| Wash min height | `max(fadeEnd + 40, 420)` | `ProfileWash` |
| Wash fade-end fallback | 260 (used until `shelfTop > 120`) | `washFadeEnd` |
| Palette resolve size | `maxPixel 360` | `.task(id: washArtwork)` |
| Toast host insets | h 22, bottom 62 | `MainTabView` |
| Page-in travel | 6 pt, `uiReveal` 0.28 s, once per tab | `PageInTransition` |
| App-under-splash | scale 0.965, blur 4 pt | `RootView` |
| Splash ignite / hand-off | 0.92 s / 1.68 s (1.2 s under Reduce Motion) | `SplashView` |
| Auth bootstrap wait | ≤ 3 s, polling every 80 ms | `AuthManager.bootstrap` |
| Alerts per show / total cap | 3 / 48 | `EpisodeNotifications` |
| Live Activity window | lead 60 min, linger 15 min | `AiringLiveActivityManager` |
| Widget accent / backdrop | `#F0A24E` / `#0B0B0E` (0.9 alpha tint) | `AniTrackWidgets` |
| Deletion request timeout | 20 s | `AccountDeletion` |

---

## 12. Porting risks, ranked

| Item | Severity | Note |
| --- | --- | --- |
| Live Activity + Dynamic Island | **blocker** for parity | No Android equivalent of the Island. Ongoing notification with `setUsesChronometer(true)` + `setChronometerCountDown(true)` reproduces the countdown; Android 16 `ProgressStyle`/Live Updates gets closest to the lock-screen card |
| `emberZoom` / `filmGrain` Metal shaders | **hard** | AGSL `RuntimeShader` (API 33+) can express both; below 33 drop the grain and substitute a plain scale for the dive |
| SF Symbols (`bell`, `hand.tap`, `trash`, `wifi.slash`, `exclamationmark.triangle.fill`, `arrow.up.forward`, `checkmark`, `dot.radiowaves.left.and.right`, `curlybraces`, `tablecells`, `rectangle.portrait.and.arrow.right`, `hand.raised`, `doc.text`, `envelope`, `square.and.arrow.up`, `chevron.forward`, `arrow.clockwise`, `arrow.triangle.2.circlepath`, `wifi.exclamationmark`, `magnifyingglass`) | **moderate** | Map to Material Symbols per `icon-mapping.md`; `curlybraces` and `wifi.exclamationmark` have no direct match and need custom vectors |
| iOS 26 Liquid Glass shims (`chromeScrollEdgeHard`, `chromeSharedBackgroundHidden`, `chromeTabBarMinimizeOnScroll`, `glassChrome`) | **easy** | All are already no-ops on iOS 18; the Android build simply does not implement them |
| `ShareLink` + `Transferable` file export | **moderate** | `FileProvider` + `Intent.ACTION_SEND` with a `content://` URI and a `FileProvider` authority; the share sheet is a system chooser |
| `.sheet` interactive dismiss for Profile | **easy** | `ModalBottomSheet` with drag-to-dismiss; the "no pull-to-refresh inside a sheet" rule matters for the same reason |
| Per-tab `NavigationPath` + re-select-to-pop | **easy** | One `NavHostController` per tab (or a saved back-stack per tab with `navigation-compose`'s multiple back stacks); re-select → `popBackStack(startDestination, inclusive = false)` |
| `onScrollGeometryChange` / `onGeometryChange` probes | **easy** | `LazyColumn`'s `firstVisibleItemScrollOffset` or a `NestedScrollConnection`; `onGloballyPositioned` for the shelf's screen-space Y |
| `@ScaledMetric` | **easy** | `LocalDensity.current.fontScale` |
| `UNUserNotificationCenter` scheduling | **easy** | `AlarmManager.setExactAndAllowWhileIdle` + `NotificationManagerCompat`; requires `POST_NOTIFICATIONS` (33+) and `SCHEDULE_EXACT_ALARM` (31+) |
| Foreground notification presentation delegate | **easy** | Android shows heads-up notifications in-app by default on a high-importance channel |
| `UIApplication.openSettingsURLString` | **easy** | `Settings.ACTION_APP_NOTIFICATION_SETTINGS` with `EXTRA_APP_PACKAGE` |
| `didBecomeActiveNotification` re-read of permission | **easy** | `LifecycleEventEffect(ON_RESUME)` |
| `EllipticalGradient` with `startRadiusFraction`/`endRadiusFraction` | **easy** | `Brush.radialGradient` on a non-square box, or a `Canvas` with a scaled radial shader |
| `.alert` semantics (dimming scrim, explicit Cancel, destructive styling) | **easy** | `AlertDialog`; keep the destructive button visually destructive and always render Cancel |
| Clerk iOS SDK | **hard** | Clerk ships an Android SDK, but the `Clerk.shared.auth.events` stream and `getToken(skipCache:)` need re-expressing; the ≤3 s bootstrap gate must be preserved |
| ActivityKit `staleDate` | **moderate** | Android has no stale concept; schedule an explicit cancel `linger` after air time |
| Dark-only, portrait-only | **easy** | Lock `android:screenOrientation="portrait"` and ship only a dark `ColorScheme` |
