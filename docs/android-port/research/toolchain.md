# Android toolchain from zero on this Mac

**Status:** research / decision note. Written 2026-09-04. Every command below was **executed on this
machine** (Apple Silicon, macOS 27.0 / Darwin 27.0.0, Homebrew 6.0.21) and the output quoted is real.
Version claims are checked against primary sources; links and dates in §9.

**Scope:** getting from bare metal to a working `build → install → boot → screenshot` loop with no
Android Studio. It does **not** cover architecture, libraries or design — those are
`research/compose-architecture.md` and `spec/*`. A companion `docs/android-port/TOOLCHAIN.md`
records the *installed state* of this Mac; this note records *how to reproduce it anywhere* and the
things that bite on the way.

---

## 1. Recommendation up front

| Decision | Pick | One-line reason |
|---|---|---|
| **Android Studio** | **Not required.** Command-line tools do the whole loop. | Verified end to end below: a real Compose app built, installed, launched and screenshotted on a headless emulator without Studio ever being installed. |
| JDK | **`brew install openjdk@21`** (formula, keg-only) | Unattended, no password, stays in `/opt/homebrew`. AGP's floor is 17; 21 is the LTS the port targets. |
| SDK | **`brew install --cask android-commandlinetools`** → cmdline-tools **22.0** | One command, correct `cmdline-tools/latest` layout, no manual unzip-and-rename dance. |
| SDK package manager | **`android sdk …`** (the new Android CLI), with `sdkmanager` as the fallback | Google **deprecated `sdkmanager`**; the `android` CLI is the supported path. Note the **package-id syntax changed** (`platforms/android-36`, slash) — see §4.1. |
| Android CLI | **`brew install --cask android-cli`** → **1.0.16251017** | Pins the version instead of letting the `android` shim self-download ~81 MB on first run. |
| Gradle | **The project's wrapper.** Do *not* rely on `brew install gradle`. | AGP 9.4.0 requires Gradle ≥ 9.6.0; the wrapper guarantees it per-project and per-CI. |
| AVD creation | **`avdmanager create avd -k "system-images;android-36;google_apis;arm64-v8a"`** | Deterministic and fast. `android emulator create` silently pulls a **different, 2.3 GB Play-Store** image and takes ~9 min with zero output — see §5.2. |
| System image | **`system-images;android-36;google_apis;arm64-v8a`** (arm64, Apple Silicon native) | `google_apis` (not `_playstore`) keeps `adb root` available for QA. |
| Emulator GPU | **`-gpu host`** for visual QA, `-gpu swiftshader_indirect` for CI | `host` uses Metal and renders blur honestly; swiftshader is a software rasteriser and misrepresents the chrome this port is built around. |
| Screenshot | **`adb exec-out screencap -p > shot.png`** | One command, no temp file on device. Verified: 1280 × 2856 PNG. |

**Total download ≈ 6.5 GB; ≈ 11 GB on disk** once Gradle's caches are warm (§6). Budget 30–45 min
on a fast connection.

**Confidence: high** for everything executed here. The one soft spot is the `sdkmanager` →
`android` CLI transition, which is mid-flight across the ecosystem (§4.1) — that is the item most
likely to change under you.

---

## 2. The state this Mac was actually in

The brief said "no Java, no Android SDK, no adb, no gradle". **That was already false when I
started** — an earlier session had installed the toolchain at 02:01 today:

```
openjdk 26.0.2.1, openjdk@21 21.0.12.1   (brew formulae)
gradle 9.7.1                             (brew formula)
android-commandlinetools 22.0            (brew cask, /opt/homebrew/share/android-commandlinetools)
platform-tools 37.0.1, emulator 37.1.11, build-tools 36.1.0 + 36.0.0
platforms android-36 + android-37.0, system-images android-36/google_apis/arm64-v8a
AVD PreviouslyQA_API36, all 7 SDK licences accepted
```

`/usr/libexec/java_home` still reports *"Unable to locate a Java Runtime"* — that is expected and
harmless: Homebrew's `openjdk` **formula** is keg-only and does not register with macOS's
`JavaVirtualMachines` directory. `JAVA_HOME` is how Gradle finds it. Do not "fix" this by
installing the Temurin cask on top.

§3 is written as a genuine from-zero sequence anyway (it is what a second machine or CI needs), and
every step is idempotent, so running it here is a no-op.

---

## 3. From zero — the whole sequence

```bash
# ── 1. JDK ────────────────────────────────────────────────────────────────────
# The FORMULA, not the temurin cask: keg-only, no sudo, no /Library writes.
brew install openjdk@21

# ── 2. SDK command-line tools + the new Android CLI ───────────────────────────
brew install --cask android-commandlinetools   # cmdline-tools 22.0, ~181 MB
brew install --cask android-cli                # `android` 1.0.16251017, ~81 MB

# ── 3. Environment (see §3.1 — non-interactive shells do NOT get this) ────────
export JAVA_HOME="/opt/homebrew/opt/openjdk@21"
export ANDROID_HOME="/opt/homebrew/share/android-commandlinetools"
export ANDROID_SDK_ROOT="$ANDROID_HOME"          # legacy name, some tools still read it
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"

# ── 4. Licences, non-interactively ────────────────────────────────────────────
yes | sdkmanager --licenses --sdk_root="$ANDROID_HOME"
# → "All SDK package licenses accepted."   (verified on this machine)

# ── 5. SDK packages ───────────────────────────────────────────────────────────
# NEW syntax — slashes, and each package is a separate argument:
android sdk install --no-metrics \
  platform-tools \
  build-tools/36.1.0 \
  platforms/android-36 \
  platforms/android-37.0 \
  emulator \
  system-images/android-36/google_apis/arm64-v8a

# ── 6. An AVD ─────────────────────────────────────────────────────────────────
avdmanager create avd -n PreviouslyQA_API36 --force \
  -k "system-images;android-36;google_apis;arm64-v8a"     # ← semicolons here! §4.1
```

`compileSdk 37` is required by Compose 1.12 (per `research/compose-architecture.md`), which is why
**both** `android-36` and `android-37.0` are installed: 37.0 to compile against, 36 to run on.

### 3.1 The environment gotcha

Non-interactive shells — every `Bash` tool call, every CI step, every `nohup` — **do not source
`~/.zshrc`**. Exporting the four variables in your dotfile is necessary but not sufficient: any
script must export them itself. This is the same class of bug as the iOS side's `xcodebuild`
overrides, and it is the single most common reason a working setup "stops working" under an agent.

Belt and braces: the generated `local.properties` also carries `sdk.dir`, so Gradle finds the SDK
even with `ANDROID_HOME` unset — but `adb` and `emulator` on `PATH` still won't.

### 3.2 Licence pre-seeding (CI without any interactive step)

`yes | sdkmanager --licenses` needs the network. To skip it entirely, write the hash files
directly — these are the seven accepted on this machine:

```bash
mkdir -p "$ANDROID_HOME/licenses"
cat > "$ANDROID_HOME/licenses/android-sdk-license" <<'EOF'
24333f8a63b6825ea9c5514f83c2829b004d1fee
EOF
cat > "$ANDROID_HOME/licenses/android-sdk-arm-dbt-license" <<'EOF'
859f317696f67ef3d7f30a50a5560e7834b43903
EOF
cat > "$ANDROID_HOME/licenses/android-sdk-preview-license" <<'EOF'
84831b9409646a918e30573bab4c9c91346d8abd
EOF
```

(`android-sdk-arm-dbt-license` is the one people forget on Apple Silicon; without it the arm64
system image refuses to install.) The other four — `android-googletv-license`,
`android-googlexr-license`, `google-gdk-license`, `mips-android-sysimage-license` — are only needed
for those respective packages.

---

## 4. `sdkmanager` is deprecated — read this before copying any older recipe

### 4.1 What changed

The official `sdkmanager` page now carries: **"The `sdkmanager` tool is deprecated"**, directing you
to `android sdk [install|list|update|remove]`. The `android` CLI ships inside cmdline-tools from
**22.0**, and community reports put the actual `sdkmanager` deprecation/removal at cmdline-tools
**23.0** — which is exactly what `android sdk list` on this machine offers as an upgrade:

```
cmdline-tools/latest      unknown   ->   23.0.0      Android SDK Command-line Tools (latest)
```

Homebrew currently ships **22.0**, where `sdkmanager` still works — verified, `sdkmanager --version`
→ `22.0`, and `--licenses` succeeded. **Do not upgrade `cmdline-tools` to 23.0 casually**: Flutter
has open issues where `flutter doctor --android-licenses` breaks on 23.0 because it shells out to
`sdkmanager` (§9). We are not a Flutter project, but the same shape of breakage applies to any
script of ours that calls `sdkmanager`.

**The package-id syntax differs between the two tools, and this is the trap:**

| Tool | Separator | Example |
|---|---|---|
| `android sdk install` | **`/`** | `platforms/android-36`, `system-images/android-36/google_apis/arm64-v8a` |
| `sdkmanager`, `avdmanager -k` | **`;`** | `"platforms;android-36"`, `"system-images;android-36;google_apis;arm64-v8a"` |

`avdmanager` has **not** been replaced, so `-k` keeps the old semicolon form even in a script that
otherwise uses `android sdk`. Mixed syntax in one script is correct, not a mistake.

### 4.2 Two Android CLI wrinkles

**It self-downloads.** The `android` binary in cmdline-tools 22.0 is a shim. First invocation
prints `Downloading Android CLI... / Unpacking embedded installation...` and drops an **81 MB**
`~/.android/bin/android-cli`. In CI that is a surprise network fetch and an implicit ToS
acceptance on first run. `brew install --cask android-cli` installs it up front instead — and the
cask version (`1.0.16251017`) matches what the shim fetches, so the two agree.

Interesting: `1.0.16251017` is **newer than anything in the published release notes** (which stop at
`1.0.15985488`, July 2026). The docs lag the binary.

**Metrics are on by default.** The CLI states it sends commands, sub-commands and flags to Google.
Opt out per-invocation with `--no-metrics`, or once via `~/.androidrc`:

```
--no-metrics
--sdk=/opt/homebrew/share/android-commandlinetools
```

---

## 5. The emulator

### 5.1 Boot it headless

```bash
emulator -avd PreviouslyQA_API36 \
  -no-window -no-audio -no-boot-anim -no-snapshot \
  -gpu swiftshader_indirect -port 5554 &

adb wait-for-device
until [ "$(adb shell getprop sys.boot_completed | tr -d '\r')" = "1" ]; do sleep 3; done
echo BOOTED
```

Verified: boots to `emulator-5554  device` in roughly 1–2 minutes on this Mac. The emulator itself
prints `Emulator is performing a full startup. This may take upto two minutes, or more.`

`adb wait-for-device` alone is **not** enough — it returns as soon as the device is *connected*,
while Android is still booting. The `sys.boot_completed` loop is the real gate.

**`-gpu` choice is a real decision, not a default:**
- `-gpu host` — Metal-backed, honest blur and animation. Use for anything you will *look* at.
  `docs/android-port/TOOLCHAIN.md` verifies background blur is supported on this AVD, which is
  load-bearing for this port's chrome.
- `-gpu swiftshader_indirect` — software. Boots fine headless (used above), correct for
  build-verification and instrumented tests, **wrong for design QA**.

**Running two emulators off one AVD fails.** Hit this live:

```
FATAL | Running multiple emulators with the same AVD is an experimental feature.
        Please use -read-only flag to enable this feature.
```

Add `-read-only` for the second instance, or give each its own AVD and `-port`.

### 5.2 Why `android emulator create` is not the recommendation

`android emulator create medium_phone` **does work** — it created the AVD — but:

- it took **~9 minutes** and printed **nothing at all** while stdout was piped (progress is only
  drawn to a TTY), so it is indistinguishable from a hang; I killed it once before realising;
- it silently downloaded `sys-img/google_apis_playstore/arm64-v8a-36_r07.zip` — a **2.3 GB
  Play-Store** image, *not* the `google_apis` image already on disk. Play-Store images are
  Play-signed: **no `adb root`**, which costs you device-state manipulation in QA.

Its profiles are `small_phone`, `medium_phone`, `large_desktop`, `medium_desktop`, `small_desktop`,
`medium_tablet`. `avdmanager` remains the predictable tool.

One `avdmanager` wart, also hit live: `-d medium_phone` fails with
`Could not load devices from …/system-images/…/devices.xml` while still creating the AVD. Omit
`-d` and set resolution/density in `config.ini`, or accept the image's default geometry.

---

## 6. Sizes — measured on this machine, not estimated

| Component | Download | On disk |
|---|---:|---:|
| `openjdk@21` (brew formula) | ~180 MB | **331 MB** |
| `android-commandlinetools` cask | **181 MB** | 173 MB |
| `android-cli` cask | ~81 MB | **81 MB** |
| `platform-tools` 37.0.1 | ~15 MB | **37 MB** |
| `build-tools/36.1.0` | ~60 MB | **192 MB** |
| `platforms/android-36` | ~70 MB | **134 MB** |
| `platforms/android-37.0` | ~80 MB | **152 MB** |
| `emulator` 37.1.11 | ~600 MB | **1.1 GB** |
| `system-images/android-36/google_apis/arm64-v8a` | ~1.6 GB | **4.3 GB** |
| **SDK subtotal** | **≈ 2.9 GB** | **≈ 6.1 GB** |
| Gradle wrapper dist (9.1.0) | ~230 MB | **287 MB** |
| Gradle dependency cache (one Compose app) | ~900 MB | **946 MB** |
| Gradle auto-provisioned Adoptium JDK 17 | 193 MB | **309 MB** (+193 MB tarball kept) |
| One booted AVD's userdata | — | **2.0 GB** |
| **Grand total** | **≈ 6.5 GB** | **≈ 11 GB** |

Two of those deserve a flag:

- **The system image is 4.3 GB on disk from a ~1.6 GB download.** It is the single biggest item and
  it is unavoidable.
- **Gradle silently downloaded a JDK 17.** The scaffolded project sets `kotlin { jvmToolchain(17) }`,
  and Gradle's toolchain auto-provisioning fetched Eclipse Adoptium 17.0.20.1 into `~/.gradle/jdks`
  (**502 MB** including the retained tarball) even though `JAVA_HOME` pointed at 21. The build
  succeeded because of it — but if you want to *avoid* the download, set `jvmToolchain(21)` to match
  the installed JDK, or disable provisioning with
  `org.gradle.java.installations.auto-download=false` and accept that the build then fails unless a
  matching JDK is present.

Free space on this Mac was **41 GiB** before and **45 GiB** after cleanup — comfortable, but a
machine near full will not survive this install.

---

## 7. Android Studio is not required — proof

I built and ran a real Compose app with nothing but the command line. Full transcript, condensed:

```bash
# scaffold — the Android CLI ships project templates
android create empty-activity --name "Probe" --output ./Probe --minSdk 26 --no-metrics
# → INFO: Successfully created project 'Empty Activity'

cd Probe && ./gradlew assembleDebug --no-daemon
# → BUILD SUCCESSFUL in 3m 6s   (36 tasks; cold cache, incl. the JDK-17 provisioning)
# → app/build/outputs/apk/debug/app-debug.apk   (11.9 MB)

adb install -r app/build/outputs/apk/debug/app-debug.apk      # → Success
adb shell monkey -p com.example.probe -c android.intent.category.LAUNCHER 1
adb exec-out screencap -p > shot.png                          # → PNG 1280 × 2856
```

`dumpsys` confirmed `topResumedActivity=ActivityRecord{… com.example.probe/.MainActivity}` and the
PNG showed the rendered Compose `Hello Android!` on a headless, `-no-window` emulator.

**Cold build was 3m 06s** — that includes downloading Gradle 9.1.0, the Adoptium JDK 17 and every
AndroidX artifact. Warm incremental builds are seconds.

### 7.1 What you *do* give up without Studio

Honest list, so nobody is surprised later: interactive **Compose Previews** (`@Preview` still
compiles; you just cannot render it in an IDE pane), **Layout Inspector**, the **profilers**
(CPU/memory/energy), **Database Inspector**, and the visual **AVD Manager**. For a
build-and-screenshot loop driven by an agent, none of those are on the critical path — and
screenshot-diffing (Paparazzi/Roborazzi) replaces Preview for regression work far better than
eyeballing a pane. Studio remains worth installing for a human doing sustained UI work; it is not a
dependency of the pipeline.

### 7.2 Screenshots — three ways, all verified

```bash
adb exec-out screencap -p > shot.png                 # best: no temp file, one command
adb shell screencap /sdcard/s.png && adb pull /sdcard/s.png   # older, two steps
android screen capture --output shot.png --no-metrics # Android CLI; also works
```

`adb exec-out` is the one to standardise on — `exec-out` streams raw bytes, where `adb shell` would
mangle the PNG with CRLF translation on some hosts. For video:
`adb shell screenrecord --time-limit 30 /sdcard/d.mp4 && adb pull /sdcard/d.mp4` (no audio, 3 min
max).

---

## 8. The scaffold's versions are stale — bump them

`android create empty-activity` is a genuinely useful starting point (it emits Compose **and**
Navigation 3 wiring, a version catalog, and `configuration-cache` + `caching` already on in
`gradle.properties`). But it pins versions well behind current:

| | Template emits | Current (Sept 2026) | Source |
|---|---|---|---|
| AGP | 9.0.1 | **9.4.0** (Sept 2026) | AGP 9.4.0 release notes |
| Gradle wrapper | 9.1.0 | **9.6.0+** — AGP 9.4's floor | AGP 9.4.0 compatibility table |
| Kotlin | 2.3.20 | **2.4.10** (14 Jul 2026) | JetBrains/kotlin releases |
| Compose BOM | 2026.03.01 | **2026.08.00** → ui/foundation 1.12.0, material3 1.4.0 | BOM-to-library mapping |

AGP 9.4.0's published compatibility table, verbatim: **Gradle min 9.6.0**, **SDK Build Tools
36.0.0**, **JDK min 17**, max supported **API level 37**.

So after scaffolding:

```bash
./gradlew wrapper --gradle-version 9.6.1
```

```toml
# gradle/libs.versions.toml
androidGradlePlugin = "9.4.0"
kotlin             = "2.4.10"
androidxComposeBom = "2026.08.00"
```

```kotlin
// app/build.gradle.kts — compileSdk 37 is required by Compose 1.12
android { compileSdk = 37; defaultConfig { targetSdk = 36 } }
kotlin { jvmToolchain(21) }   // match the installed JDK; avoids the 502 MB auto-download
```

Cross-check these against `research/compose-architecture.md` §2 rather than treating either note as
sole authority — that note owns the version decisions; this one owns the install mechanics.

---

## 9. Evidence

Fetched 2026-09-04:

- [sdkmanager](https://developer.android.com/tools/sdkmanager) — carries the deprecation notice and
  the `android sdk` redirect; documents `--sdk_root`, `--licenses`, `--package_file`, and the
  required `cmdline-tools/latest/bin/sdkmanager` layout.
- [Android CLI overview](https://developer.android.com/tools/agents/android-cli) — `android sdk
  install/list/update/remove`, `android emulator create/list/start/stop`, `android run`,
  `android screen capture`, `~/.androidrc`, the metrics disclosure, and the known issue that
  `android emulator` is disabled on Windows.
- [Android CLI release notes](https://developer.android.com/tools/agents/android-cli/release-notes)
  — latest published `1.0.15985488` (July 2026); the binary installed here is `1.0.16251017`, newer
  than the docs.
- [AGP 9.4.0 release notes](https://developer.android.com/build/releases/agp-9-4-0-release-notes)
  (September 2026) — the compatibility table quoted in §8.
- [Compose BOM mapping](https://developer.android.com/develop/ui/compose/bom/bom-mapping) — newest
  BOM `2026.08.00` → ui/foundation/runtime 1.12.0, material3 1.4.0.
- [Kotlin 2.4.10 release](https://github.com/JetBrains/kotlin/releases/tag/v2.4.10) — 14 Jul 2026;
  2.4.20 is at RC3, not stable.
- [Emulator command-line options](https://developer.android.com/studio/run/emulator-commandline) —
  `-no-window`, `-no-audio`, `-no-boot-anim`, `-no-snapshot`, `-gpu`, `-port`, `-wipe-data`.
- [adb](https://developer.android.com/tools/adb) — `adb exec-out screencap -p > screen.png` is the
  documented single-command form ("use `exec-out` … to get raw data").
- [platform-tools release notes](https://developer.android.com/tools/releases/platform-tools) —
  37.0.1, July 2026. Note: **macOS now disables libusb by default** (`ADB_LIBUSB=1` to re-enable) —
  irrelevant for emulators, relevant if you ever attach a physical device.
- Flutter issues [#191558](https://github.com/flutter/flutter/issues/191558) and
  [#191487](https://github.com/flutter/flutter/issues/191487) — third-party evidence that
  cmdline-tools **23.0** breaks `sdkmanager`-based licence flows. Treated as corroboration for the
  "pin 22.0" call, not as primary documentation.

Sources disagree on one point worth naming: the
[cmdline-tools release notes](https://developer.android.com/tools/releases/cmdline-tools) page still
lists nothing past **5.0 (December 2020)** and says nothing about the `android` CLI or the
deprecation — while the shipping tool is 22.0 and the sdkmanager page says it is deprecated. **That
page is stale; do not use it to date anything.**

---

## 10. Alternatives rejected

| Rejected | Why |
|---|---|
| **Android Studio** as the install vehicle | Multi-GB IDE, an interactive first-run wizard, and it installs the SDK under `~/Library/Android/sdk` — a second SDK root to keep in sync. Nothing in the loop needs it (§7). Install it later as a *tool for a human*, pointed at the same `ANDROID_HOME`. |
| **Temurin cask** (`brew install --cask temurin@21`) | Writes to `/Library/Java/JavaVirtualMachines`, needs an admin password — so it cannot be scripted unattended. The keg-only formula is strictly better here. Its one advantage (registering with `/usr/libexec/java_home`) buys us nothing, since Gradle reads `JAVA_HOME`. |
| **JDK 26** (the default `brew install openjdk`, already on this Mac) | AGP 9.4 documents a *floor* of 17, not support for 26. Gradle 9.7.1 runs on 26, but AGP/KGP on a JDK newer than the toolchains they are tested against is a known source of obscure failures. 21 is the boring, tested choice. |
| **Homebrew `gradle`** (9.7.1, installed here) | Fine for scratch work, wrong for the project: it floats on `brew upgrade` and does not match CI. Use `./gradlew`. Note the brew gradle currently defaults to the **JDK 26** launcher, which is another reason not to build with it. |
| **`android emulator create`** for AVDs | Silent 9-minute run, and it pulls a *different* 2.3 GB Play-Store image (§5.2). |
| **`google_apis_playstore` system image** | Play-signed → no `adb root`, so you cannot manipulate device state for QA. Only needed if you must test Play Billing or Play Services gating. |
| **x86_64 system image** | Would run under emulation on Apple Silicon: dramatically slower, and not what users run. arm64-v8a is native. |
| **Manual `commandlinetools-mac-*.zip` download** | Requires the unzip-and-rename-to-`latest` ritual the docs describe, and pins nothing. The cask does it correctly. Keep this as the fallback for a machine without Homebrew. |
| **`sdkmanager` as the primary package manager** | Deprecated (§4.1). Kept only for `--licenses`, which the `android` CLI has no documented equivalent for. |

---

## 11. Open questions for a human

1. **Do we upgrade `cmdline-tools` to 23.0?** `android sdk list` offers it. 23.0 is where
   `sdkmanager` goes away, and our licence step (§3) currently depends on `sdkmanager --licenses`.
   Before upgrading, someone must establish the supported non-interactive licence path under 23.0 —
   the `android` CLI has no documented `--licenses` equivalent, and the §3.2 hash pre-seeding may
   become the only option. **Recommend staying on 22.0 until that is answered.**
2. **Is the Android CLI's telemetry acceptable?** It is on by default and reports commands and flags
   to Google. `--no-metrics` / `~/.androidrc` turns it off; someone should decide whether that goes
   in the repo's setup script as a default.
3. **`jvmToolchain(17)` or `(21)`?** Matching the installed JDK saves a 502 MB download and a
   provisioning step; staying at 17 matches AGP's documented floor and what most CI images carry.
   Cheap either way, but it should be decided once and written into the template.
4. **Which `-gpu` for the QA screenshots that get reviewed?** §5.1 argues `host` for anything
   design-related. If screenshots are ever produced on CI (no GPU), the two will not be
   pixel-comparable — so a screenshot-diff baseline must be pinned to one mode.
5. **Leftover from my probing:** a **2.3 GB** `system-images/android-36/google_apis_playstore/arm64-v8a`
   is now on disk, pulled by the `android emulator create` experiment. Nothing references it — the
   test AVD is deleted. Remove it with
   `android sdk remove system-images/android-36/google_apis_playstore/arm64-v8a` unless Play-Services
   testing is wanted.
6. **Second SDK root risk.** If anyone later installs Android Studio, it will default to
   `~/Library/Android/sdk` and you will have two SDKs. Point Studio at
   `/opt/homebrew/share/android-commandlinetools` on first run.

---

## 12. Cleanup / machine state after this research

Left exactly as found except where noted: the `Probe` scratch project lives only in the session
scratchpad; `com.example.probe` was uninstalled from the emulator; the test AVD `medium_phone` was
deleted; the `google_apis_playstore` image remains (open question 5). `PreviouslyQA_API36` is booted
and attached as `emulator-5554`.
