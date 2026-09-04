plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    // The offline library snapshot, the failed-write list and the watch-session file are all
    // `@Serializable` types declared in `:app` (they are session state, not wire types), so the
    // compiler plugin has to be here as well as in `:model`. It is a Kotlin *compiler* plugin —
    // like `kotlin.compose` above — not the Kotlin Gradle plugin, which AGP 9 already provides.
    alias(libs.plugins.kotlin.serialization)
}

android {
    namespace = "com.anitrack.app"
    compileSdk = 37

    defaultConfig {
        applicationId = "com.anitrack.app"
        // minSdk 26 — see docs/android-port/research/minsdk-decision.md.
        // Pre-31 devices take the no-blur reduce-transparency path; `Modifier.blur` is a SILENT
        // no-op below 31, so chrome must branch explicitly, never rely on graceful degradation.
        minSdk = 26
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"

        // Build-time configuration — the Android side of iOS's `project.yml` → `Info.plist` chain.
        // Nothing is read from the environment at runtime; see data/AppConfig.kt, which owns the
        // trimming, the `REPLACE_ME`/blank → null rule and the local-backend test.
        //
        // Clerk stays on the shared `pk_test_` DEV INSTANCE through both betas, deliberately: it is
        // ONE instance across iOS and Android, and cutting a `pk_live_` key orphans every beta
        // user's library server-side (rows are keyed on the Clerk id). See
        // docs/android-port/research/product-decisions.md §6.
        //
        // `-PclerkKey=` (an empty value) blanks it for a scripted QA run, which is the ONLY way to
        // reach the developer sign-in card: `AppConfig.isClerkConfigured` is the single boolean
        // that decides the whole auth mode, so a build carrying a real key never offers the
        // `dev:<clerkId>` bearer even against a local backend. This is the Android spelling of the
        // iOS `xcodebuild CLERK_PUBLISHABLE_KEY=` capture recipe; it changes no default, and a
        // build without the property is byte-for-byte the shipping configuration.
        //     ./gradlew -PclerkKey= :app:assembleDebug
        buildConfigField(
            "String",
            "CLERK_PUBLISHABLE_KEY",
            "\"${
                (project.findProperty("clerkKey") as String?)
                    ?: "pk_test_bGVnaWJsZS1nb2JibGVyLTU3LmNsZXJrLmFjY291bnRzLmRldiQ"
            }\"",
        )
        // A placeholder URL baked into a shipped string is a broken Privacy Policy link, which is
        // itself a store rejection — so a blank or `REPLACE_ME` value omits the row rather than
        // drawing one that goes nowhere.
        buildConfigField("String", "PRIVACY_POLICY_URL", "\"https://anime.cognipin.com/privacy\"")
        buildConfigField("String", "TERMS_URL", "\"https://anime.cognipin.com/terms\"")
        buildConfigField("String", "SUPPORT_EMAIL", "\"shantanusinha95@gmail.com\"")
    }

    buildTypes {
        debug {
            // `10.0.2.2` is the emulator's alias for the HOST machine's loopback. `localhost` would
            // be the emulated device itself. Cleartext to it is permitted by the debug-only
            // res/xml/network_security_config.xml (the analogue of iOS's NSAllowsLocalNetworking).
            // `10.0.2.2` is the emulator's alias for the HOST machine's loopback. `localhost` would
            // be the emulated device itself. Cleartext to it is permitted by the debug-only
            // res/xml/network_security_config.xml (the analogue of iOS's NSAllowsLocalNetworking).
            //
            // `-PapiBaseUrl=` overrides it for one build, the same escape hatch `-PclerkKey=` gives
            // the auth mode. It changes no default.
            //
            // ON A PHYSICAL DEVICE `10.0.2.2` means nothing — it is an emulator fiction. Use:
            //     adb reverse tcp:8787 tcp:8787
            //     ./gradlew -PclerkKey= -PapiBaseUrl=http://localhost:8787 :app:installDebug
            // `adb reverse` forwards the handset's OWN loopback to this machine, so the app talks to
            // `localhost` — which the network-security config already permits, on any network, with
            // no LAN IP baked into a build and no config edit when the Wi-Fi changes.
            buildConfigField(
                "String",
                "API_BASE_URL",
                "\"${(project.findProperty("apiBaseUrl") as String?)?.ifBlank { null } ?: "http://10.0.2.2:8787"}\"",
            )
        }
        release {
            buildConfigField("String", "API_BASE_URL", "\"https://anime.cognipin.com\"")
            isMinifyEnabled = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
        // `AppConfig` reads every build-time value through the generated BuildConfig class.
        buildConfig = true
    }
}

dependencies {
    implementation(project(":model"))

    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.lifecycle.runtime.ktx)

    // The system splash. At targetSdk 36 the platform draws its own splash before the first
    // composable runs; it cannot be skipped, only handed off from. Without `installSplashScreen()`
    // + `setKeepOnScreenCondition` the user sees the system frame AND THEN the app's own 0.92 s
    // ignite — two splashes on the app's very first frame.
    implementation(libs.androidx.core.splashscreen)

    // Navigation 3. The back stack is a `SnapshotStateList` the app OWNS, which is the exact shape
    // of the iOS per-tab `NavigationPath` — see research/compose-architecture.md §7. Navigation
    // Compose was rejected because its `NavController` owns the back stack, which is the one thing
    // this port has to own itself (per-tab stacks, re-select-to-pop-to-root, the one-shot
    // `focusConsumed` flag, and the alert route's "replace Today's path" semantics).
    implementation(libs.navigation3.runtime)
    implementation(libs.navigation3.ui)

    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.ui.graphics)
    implementation(libs.compose.foundation)
    implementation(libs.compose.material3)
    debugImplementation(libs.compose.ui.tooling)
    implementation(libs.compose.ui.tooling.preview)

    // Art. `coil-network-okhttp` is the fetcher; the loader itself is configured once at the
    // application root (a separate OkHttpClient from the API client — image hosts must never see
    // the Clerk bearer token). See docs/android-port/research/images-palette.md §2.2.
    implementation(libs.coil.compose)
    implementation(libs.coil.network.okhttp)
    // Declared directly rather than leaned on transitively: the art pipeline builds its own
    // OkHttpClient, so OkHttp is a compile dependency of :app in its own right.
    implementation(libs.okhttp)

    // Backdrop blur for the two chrome surfaces that must blur LIVE content — the scroll-edge
    // bands and the glass pill. `Modifier.blur` blurs a composable's own content rather than what
    // is behind it, and is a silent no-op below API 31; every use of these is gated behind
    // `LocalCanUseMaterial` in ui/chrome/ChromeSurface.kt and nowhere else.
    implementation(libs.haze)
    implementation(libs.haze.materials)

    // Transport. Retrofit is used for its declarative URL building only — every route returns a raw
    // `Response<ResponseBody>` so `ApiClient.send` can branch on (status, Content-Type, bytes) in
    // the shipped order before anything is decoded, and `converter-kotlinx-serialization` is
    // therefore deliberately NOT a dependency: `BuiltInConverters` already handles ResponseBody and
    // RequestBody, and encoding a request body happens in `ApiClient` so an encode failure lands in
    // the error taxonomy rather than inside the retry loop. See data/api/Dto.kt.
    implementation(libs.retrofit)
    implementation(libs.okhttp.logging)
    // `:model` already exposes kotlinx-serialization-json as `api`, but the transport layer names
    // `KSerializer` and `SerializationException` itself, so it declares the dependency it uses.
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.kotlinx.coroutines.core)

    // Identity. The SAME publishable key as iOS, so it is the same Clerk instance, the same
    // `user_…` ids and the same libraries — an account created on iPhone opens here, with no server
    // change at all. `clerk-android-ui` is the prebuilt Compose `AuthView` the gate presents, the
    // direct analogue of iOS presenting `ClerkKitUI.AuthView()`; it is themed with a `ClerkTheme`
    // built from this app's tokens in ui/auth/SignInScreen.kt. See
    // docs/android-port/research/clerk-android.md and product-decisions.md §7.
    //
    // The SDK's own library manifest already declares INTERNET, the SSO activities and the
    // `clerk://com.anitrack.app.{callback,oauth}` intent filters, so the app manifest needs nothing
    // for the OAuth round-trip.
    implementation(libs.clerk.api)
    implementation(libs.clerk.ui)

    // The "Up Next" home-screen widget (`widget/`). Glance is the Compose RUNTIME driving a
    // `RemoteViews` tree that the LAUNCHER inflates, so nothing in the design system crosses over:
    // no blur, no shader, no Canvas, no custom font, no animation. `glance-material3` is here for
    // exactly one call — `ColorProviders(darkColorScheme(...))`. Without it the widget inherits
    // Glance's default `DynamicThemeColorProviders` and renders in the user's Material You
    // wallpaper palette, which for this app is a total loss of the brand.
    //
    // `datastore-preferences` is Glance's own per-instance state store; `widget/` names
    // `stringPreferencesKey` directly (the resolved `content://` art URI for a placed card), so it
    // is declared rather than leaned on transitively.
    implementation(libs.glance.appwidget)
    implementation(libs.glance.material3)
    implementation(libs.datastore.preferences)

    // The widget's 30-minute refresh net. See the catalog note: Glance already needs WorkManager,
    // but `widget/WidgetState.kt` writes a `CoroutineWorker` of its own.
    //
    // NEVER call `WorkManager.cancelAllWork()` anywhere in this app: Glance runs its own widget
    // compositions through WorkManager, and a blanket cancel stops every widget updating, silently.
    implementation(libs.work.runtime.ktx)

    // The write policy is the highest-risk behavioural port after the derivations, and its
    // conflation semantics — one PUT in flight per part, newest-wins, superseded targets dropped —
    // read correct while being wrong. `ProgressLane` carries no Android and no model imports
    // precisely so a virtual-time scheduler can drive it.
    testImplementation(libs.junit)
    testImplementation(libs.kotlinx.coroutines.test)
}

// `:model` is a pure Kotlin JVM module, so the Compose compiler cannot infer stability for its
// types and treats every one as UNSTABLE. That makes any composable taking a Franchise/FranchisePart
// non-skippable, so the app's periodic `now` tick would recompose every row on every tab.
composeCompiler {
    stabilityConfigurationFiles.add(rootProject.layout.projectDirectory.file("compose_stability.conf"))
}
