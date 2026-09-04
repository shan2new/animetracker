# Android toolchain & QA recipe

Everything below was installed and **verified working** on this Mac (Apple M5, macOS Darwin 27) on
2026-09-04. No Android Studio is involved — the command-line tools do the whole build → install →
boot → screenshot loop.

## What is installed

| Component | Version | Location |
|---|---|---|
| JDK | OpenJDK 21.0.12.1 | `/opt/homebrew/opt/openjdk@21` (Homebrew **formula**, keg-only) |
| Android cmdline-tools | 22.0 | `/opt/homebrew/share/android-commandlinetools` |
| Platform | `android-36` (Android 16) + `android-37.0` | " |
| Build tools | 36.1.0 | " |
| Platform tools (adb) | 37.0.1 | " |
| Emulator | 37.1.11 | " |
| System image | `android-36;google_apis;arm64-v8a` | " |
| Gradle | 9.7.1 (bundles Kotlin 2.4.0) | `/opt/homebrew/bin/gradle` |

Total SDK footprint: **6.1 GB**.

> The JDK was installed with `brew install openjdk@21` — the **formula**, not the `temurin` cask.
> The cask writes to `/Library/Java/JavaVirtualMachines` and needs a password; the formula stays
> inside `/opt/homebrew` and installs unattended. Gradle finds it through `JAVA_HOME`.

## Environment

Already appended to `~/.zshrc`:

```bash
export JAVA_HOME="/opt/homebrew/opt/openjdk@21"
export ANDROID_HOME="/opt/homebrew/share/android-commandlinetools"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"
```

Non-interactive shells (and agents) do not source `~/.zshrc`, so **any script must export these
itself**. Same class of gotcha as the iOS side's xcodebuild overrides.

> `sdkmanager` now prints a deprecation warning: the replacement is `android sdk` (the `android`
> binary in `cmdline-tools/latest/bin`). `sdkmanager` still works and every command below is written
> against it; migrate when it actually breaks.

## The two emulators

The port has a **floor device and a ceiling device**, and both are required. `minSdk` is 26 with the
no-blur reduce-transparency path (see `research/minsdk-decision.md`), and a path nobody looks at is
a path that ships broken.

| AVD | API | Android | Role |
|---|---|---|---|
| `PreviouslyQA_API36` | 36 | 16 | Primary. Blur available → the material-chrome design. |
| `PreviouslyFloor_API26` | 26 | 8.0.0 | The floor. **No blur** → the opaque-bar reduce-transparency design. |

Both are configured with **identical Pixel 9 Pro geometry** (1280 × 2856 @ 480 dpi), so a screenshot
from one can be diffed directly against the other. Any difference between them is a *chrome*
difference, never a layout difference — if layout moves, that is a bug.

**Verified on the floor device (2026-09-04):**

```
ro.build.version.release = 8.0.0
ro.build.version.sdk     = 26
ro.surface_flinger.supports_background_blur = (absent)
```

Pre-31 devices genuinely cannot blur, which is why every chrome surface must branch explicitly —
but **the causality here was inverted (ERRATUM 2026-09-04, PLAN §9.2): `Modifier.blur` is a no-op on
API 26 because `RenderEffect` is API 31**, not because this property is absent. The property gates
SurfaceFlinger's *window* background blur, which the app never uses. See the blur note below.

### Primary emulator details

`PreviouslyQA_API36` — Android 16 (API 36), Pixel 9 Pro geometry.

| Property | Value | Why it matters |
|---|---|---|
| Resolution | 1280 × 2856 px | |
| Density | 480 dpi (**xxhdpi**, = iOS @3x) | Exercises the @3x-equivalent assets |
| Logical size | **427 × 952 dp** | The iPhone captures are 393 × 852 pt — Android is ~34 dp wider and ~100 dp taller. Layouts that were tuned to the iPhone's width WILL have slack here; that is a real difference to design for, not a bug to hide. |
| RAM | 4096 MB | |
| Hardware keyboard | on | |

### Boot it

```bash
emulator -avd PreviouslyQA_API36 -no-snapshot-load -no-boot-anim -gpu host -netdelay none -netspeed full &
adb wait-for-device
until [ "$(adb shell getprop sys.boot_completed | tr -d '\r')" = "1" ]; do sleep 3; done
```

**Always `-gpu host`.** Verified renderer: `Android Emulator OpenGL ES Translator (Apple M5),
OpenGL ES 3.0 (4.1 Metal)`, with Vulkan through MoltenVK. `-gpu swiftshader_indirect` boots fine but
is software rasterisation and will misrepresent blur and animation smoothness.

### Blur renders here — but this says nothing about what it costs

```
[ro.surface_flinger.supports_background_blur]: [1]
dumpsys SurfaceFlinger → override disableBackgroundBlur=false
```

**ERRATUM (2026-09-04, PLAN R5 / §3.5 / §9.2): this property is NOT evidence for the app's chrome,
and the paragraph that stood here has been struck.** `ro.surface_flinger.supports_background_blur`
gates SurfaceFlinger's **window** background blur (`Window.setBackgroundBlurRadius`, dim-and-blur
behind dialogs) — a compositor feature for **cross-window** blur. Haze, `Modifier.blur` and
`RenderEffect` are HWUI/Skia `RenderNode` effects executed on the app's own render thread and never
consult it; they work with the property at 0. Likewise `Modifier.blur` is a no-op on the API 26 floor
device because **`RenderEffect` is API 31**, not because that device lacks this property.

What this emulator *can* do is let you **look at** the chrome. What it cannot do is tell you what it
**costs**: the floor AVD takes the no-blur branch by design, and this AVD renders through an M5 GPU
under MoltenVK, which says nothing about an Exynos/Dimensity/Adreno-6xx mid-ranger. The app's
worst-case frame is a full-width `ScrollEdgeChrome` Haze band (a full-screen offscreen capture +
blur, every frame) over a drifting `ArtHeader` and a `LazyRow`. **That frame is measured on a real
mid-range handset with `dumpsys gfxinfo` / JankStats — 99th percentile under 16.6 ms — as an M11 exit
criterion** (PLAN §5, device named in Q21). If it misses, the surface takes the app's own 1.0 opaque
branch on that device class; never a half-blur.

### Screenshot

```bash
adb exec-out screencap -p > shot.png
```

Produces a clean 1280×2856 PNG. This is the Android analogue of `xcrun simctl io screenshot` and is
the basis of the design-QA loop.

### Accessibility / state toggles for QA

| State | Command |
|---|---|
| **Reduce Motion** on | `adb shell settings put global animator_duration_scale 0` (also `window_animation_scale`, `transition_animation_scale`) |
| Reduce Motion off | `... put global animator_duration_scale 1` |
| Font scale (Dynamic Type) | `adb shell settings put system font_scale 1.3` (AX sizes: up to 2.0) |
| Display size | `adb shell wm density 540` — reset with `adb shell wm density reset` |
| Dark/light | The app is dark-only, but verify it ignores `adb shell cmd uimode night no` |
| Airplane / offline | `adb shell svc wifi disable && adb shell svc data disable` |
| Locale | `adb shell am broadcast -a android.intent.action.SETTING_CHANGED` after `settings put system system_locales` |

`animator_duration_scale` reads back as `null` when never set — treat `null` and `1` alike; only an
explicit `0` means Reduce Motion.

### Driving the UI

```bash
adb shell input tap <x> <y>              # coordinates in PIXELS, not dp
adb shell input swipe <x1> <y1> <x2> <y2> <ms>
adb shell input text "hello"             # only when a capture proves the field has focus
adb shell input keyevent KEYCODE_BACK
adb shell am start -n <pkg>/.MainActivity -e <key> <value>   # the launch-arg analogue
```

Pixel coordinates are 3× the dp values at this density (480 dpi ÷ 160). The iOS side's launch-arg
debug routes (`-openDetail`, `-recapDemo`, `-calmDemo`, `-scheduleEarlier`, …) should be mirrored as
**intent extras** so the same capture scripts exist on both platforms.

## Offline / failure-state capture

The iOS side photographs non-happy states by pointing `API_BASE_URL` at a local proxy
(`proxy.py`, modes: pass / down / refuse / slow / empty / searcherr / detailfail / writefail). The
same proxy works here — the emulator reaches the host machine at **`10.0.2.2`**, not `localhost`.
So a debug build pointed at `http://10.0.2.2:8799` gets the identical failure matrix.

Note: cleartext HTTP to `10.0.2.2` needs a `network_security_config.xml` permitting it for debug
builds only — the Android analogue of `NSAllowsLocalNetworking`.

## QA data

Design QA needs a library with real shows in every state, or half the screens render their empty
state and the shelves never appear.

`docs/android-port/qa/seed-library.py` seeds the account `dev:qa_android` against a local server:

```bash
cd server && npm run dev          # http://localhost:8787
python3 docs/android-port/qa/seed-library.py
```

It subscribes ~13 trending franchises across **all five** watch statuses — `watching`, `planned`,
`completed`, `paused`, `dropped` (note: the status is `paused`, **not** `on_hold`; the enum lives in
`server/src/routes/me.ts` and matches iOS `WatchStatus`) — and sets per-part progress a few episodes
short of what has aired, so the "behind" states, the Continue shelf and Today's focus stack all have
something real to draw.

Point a debug build at `http://10.0.2.2:8787` (the emulator's alias for the host) and authenticate
with `Authorization: Bearer dev:qa_android`, which the server accepts when `DEV_AUTH_BYPASS=1`.
