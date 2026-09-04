# Verified dependency versions

Every version below was resolved **empirically** on 2026-09-04 by fetching `maven-metadata.xml` from
Google Maven (`dl.google.com/dl/android/maven2`) or Maven Central (`repo1.maven.org/maven2`) — not
quoted from documentation and not recalled from training data. Use these numbers.

`latest` is the newest version the repository lists, including pre-release. Where `pick` differs
from `latest`, the reason is given.

| Artifact | Repo | **Pick** | Latest listed | Note |
|---|---|---|---|---|
| `com.android.tools.build:gradle` (AGP) | Google | **9.4.0** | 9.5.0-alpha04 | 9.4.0 is the newest **stable**. |
| `org.jetbrains.kotlin:kotlin-gradle-plugin` | Central | **2.4.10** | 2.4.20-RC3 | 2.4.10 is the newest **stable**. The Compose compiler ships inside the Kotlin release, so this one number governs both. |
| `androidx.compose:compose-bom` | Google | **2026.08.00** | 2026.08.00 | Newest, and stable. |
| `com.google.dagger:hilt-android` | Central | **2.60.1** | 2.60.1 | Newest. |
| `androidx.navigation3:navigation3-runtime` | Google | **1.1.7** | 1.2.0-beta01 | 1.1.7 is the newest **stable**. |
| `androidx.glance:glance-appwidget` | Google | **1.2.0** | 1.3.0-alpha02 | 1.2.0 is the newest **stable**. |
| `io.coil-kt.coil3:coil` | Central | **3.6.1** | 3.6.1 | ⚠ Newest stable is **3.6.1**, not 3.0.x. Stable line runs 3.3.0 → 3.6.1. |
| `com.clerk:clerk-android-api` | Central | **1.1.5** | 1.1.5 | Newest. |
| `com.clerk:clerk-android-ui` | Central | **1.1.5** | 1.1.5 | Newest. Optional — only if the prebuilt `AuthView` is used. |
| `com.google.devtools.ksp:symbol-processing-api` | Central | **2.3.11** | 2.3.11 | ⚠ KSP2 no longer pins to the Kotlin version, so it is **not** `2.4.10-x.y.z`. `compose-architecture.md` correctly flagged this as the one version not to paste blind — it was right. **⚠⚠ But the PAIRING is not verified:** 2.3.11 (published 2026-08-03, the newest KSP there is — there is no 2.4.x KSP) declares `org.jetbrains.kotlin:kotlin-stdlib:2.3.20`, and KSP2 embeds the Kotlin Analysis API, so KSP-on-2.3.20 driving a **2.4.10** compiler is the classic mismatch — with Hilt codegen on the M0 critical path. Haze 1.7.3 and Compose BOM 2026.08.00 are also on the 2.3.20 line. See PLAN §2.1, R41, Q24: it is a **named M0 gate**, with **Kotlin 2.3.21** as the documented fallback. |
| `androidx.lifecycle:lifecycle-viewmodel-navigation3` | Google | **2.11.0** | 2.12.0-alpha02 | 2.11.0 is **stable** — the "may still be alpha" caveat elsewhere is stale. Needed: `NavDisplay`'s entry-decorator list. |
| `androidx.lifecycle:lifecycle-process` | Google | **2.11.0** | — | `ProcessLifecycleOwner` ON_START/ON_STOP (PLAN §4.4). |
| `androidx.datastore:datastore-preferences` | Google | **1.2.0** | — | `Prefs`, `FailedChangeStore`, the haptics key, both a11y toggles. Was used throughout the plan but never pinned. |
| `androidx.work:work-runtime-ktx` | Google | **2.11.0** | — | The widget's 30-min `PeriodicWorkRequest` — **only if the widget is scoped in** (PLAN Q22); otherwise omit the artifact. |
| `androidx.core:core-splashscreen` | Google | **1.2.0** | — | **Mandatory.** At minSdk 26 the platform `SplashScreen` API (31+) does not exist, and at targetSdk 36 the system always draws its own splash — `installSplashScreen()` + `setKeepOnScreenCondition` is the only way to hand off into `SplashScreen.kt` without showing two splashes (PLAN §4.4). |

## Corrections this makes to the research notes

1. **Coil**: any reference to `coil3` `3.0.x` should read **3.6.1**.
2. **KSP**: the composite `<kotlin>-<ksp>` version scheme does not apply. Use the bare `2.3.11`.
3. **Gradle**: `compose-architecture.md` proposes Gradle 9.6.1; the Gradle installed on this machine
   via Homebrew is **9.7.1**. AGP 9.4.0's floor is Gradle ≥ 9.6.0, so 9.7.1 satisfies it — but AGP
   also declares a *maximum tested* Gradle. **Pin the wrapper explicitly** (`gradle-wrapper.properties`)
   rather than inheriting whatever Homebrew has, so CI and this machine agree. Generate the wrapper
   once with the system Gradle, then never use the system Gradle again.

## Still to verify at setup time

These were not probed and must be checked before they are written into `build.gradle.kts`:

- The **declared `minSdk` of each dependency** against our floor of 26. Clerk declares 24 (from its
  own `gradle/libs.versions.toml`), so it is satisfied; **Glance, Coil 3, and any Media3/WebView
  usage are unconfirmed.** A dependency with `minSdk 28` silently raises the app's effective floor
  via manifest merger, which would quietly undo the product decision in
  `minsdk-decision.md`.
- Whether **core library desugaring** is still wanted. At `minSdk 26`, `java.time` is native so the
  main reason is gone, but some AndroidX artifacts request it anyway.
- Compose **1.12 requires `compileSdk 37`** per the BOM release notes — confirm once the project
  actually assembles, since it is the constraint most likely to produce a confusing first error.

---

## RESOLVED EMPIRICALLY (2026-09-04): the KSP ↔ Kotlin pairing is fine

**PLAN R41 / Q24 and the ⚠⚠ warning on the KSP row above are now closed. Do NOT downgrade to
Kotlin 2.3.21.**

The concern was sound on paper: KSP tops out at **2.3.11** (there is no KSP on the 2.4 line at all —
verified against Maven Central's full version list), its POM declares
`org.jetbrains.kotlin:kotlin-stdlib:2.3.20`, and KSP2 embeds the Kotlin Analysis API — so KSP built
against 2.3.20 driving a **2.4.10** compiler is the classic mismatch, with Hilt codegen sitting on
the M0 critical path.

It was tested rather than reasoned about. A throwaway Android project — AGP 9.4.0, Gradle 9.6.1,
Kotlin 2.4.10 (AGP built-in), KSP 2.3.11, Hilt 2.60.1, `@HiltAndroidApp` + an `@Inject` constructor,
compileSdk 37 / minSdk 26 / targetSdk 36 — assembled clean:

```
> Task :app:kspDebugKotlin
> Task :app:compileDebugKotlin
> Task :app:hiltCollectClassesDebug
> Task :app:hiltAggregateDepsDebug
> Task :app:hiltJavaCompileDebug
BUILD SUCCESSFUL in 33s
```

Every Hilt codegen task ran and the APK assembled. **Kotlin 2.4.10 + KSP 2.3.11 + Hilt 2.60.1 is a
working combination on this toolchain.**

Keep the risk *recorded* rather than deleted: it will resurface on the next Kotlin bump, and the
answer then is the same — build the probe, do not reason from POM metadata. The `kotlin-stdlib`
version in KSP's POM is a floor, not a compiler binding.

### Separately: an erratum on this document's own evidence standard

An earlier note in `TOOLCHAIN.md` claimed `ro.surface_flinger.supports_background_blur = 1` proved
the app's blur would work. **That property is not evidence for this app's chrome** — it gates
SurfaceFlinger's cross-window background blur (`Window.setBackgroundBlurRadius`), whereas
`Modifier.blur` / `RenderEffect` / Haze are HWUI-Skia `RenderNode` effects on the app's own render
thread that never consult it. The *conclusions* were unaffected (blur on API 36, none on API 26) but
the reason was wrong: `Modifier.blur` is a no-op on the floor device because **`RenderEffect` is
API 31**, full stop. `TOOLCHAIN.md` now carries the corrected text.
