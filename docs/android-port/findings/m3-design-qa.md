# Design QA — first real render, 2026-09-04

Captured with `docs/android-port/qa/capture.sh` on **both** AVDs, against the local server with the
seeded QA library (13 shows, all five statuses).

- `qa-shots/api36/…` — 21 states, blur available
- `qa-shots/api26/…` — 21 states, **no blur** (the floor / reduce-transparency path)

## The headline result

**The floor device renders identically to API 36.** Same hero, pill, title, progress bar, capsule,
rows and tab bar. The only differences are platform chrome (3-button navigation vs the gesture bar,
Android 8 vs 16 status-bar styling). `TOOLCHAIN.md`'s rule — *a difference between the two AVDs must
be a chrome difference, never a layout difference* — holds. **The minSdk 26 decision is validated in
pixels, not in theory.**

## What is confirmed working, on screen

| Screen | Confirmed |
|---|---|
| **Today** | Billboard hero, recency pill with dot, title, `ProgressBar`, ONE amber action capsule (a ground with `onAccent` ink), `Next up` header, `MediaRow` with poster + amber lead + "Season 1 · Episode 6" + `MarkRing`, tab bar with the custom vector icons |
| **Schedule** | **Today's section drawn even when EMPTY**, with "NOTHING SCHEDULED" in the header's count slot — the load-bearing rule. Ticker with today as a filled amber disc, empty days dimmed and non-targetable, day headers as eyebrows with no ground, `AiringCard` gutter-to-gutter at 16:9 with the time as an over-art pill, the "EARLIER · 10 EPISODES · 6 TO WATCH" fold |
| **Library** | The **art-adaptive ambient wash is live** (the ground takes its colour from the artwork — this was `NoArtPalette` before the blocker remediation). `SectionHeaderRow` chevrons where the title IS the button, Continue shelf as 16:9 `ProgressBanner`s with the bar inset on the art |
| **Detail** | Billboard hero, ink back chevron and status picker (never amber), full title at `heroTitle`, identity line "Anime · 2026 · Action · Fantasy", "CAUGHT UP" eyebrow, synopsis dissolving into the bottom ramp |
| **Search** | 3-column poster grid, and the owned `✓` amber while the add affordance stays neutral — the rule this screen had right before the rest of the app did |
| **Profile** | Identity row with provenance, ONE quiet stats line (no plate of numerals), Watching shelf, grouped verb-only settings, amber toggle (legal: a toggle whose value means state), "Up to date · Checked just now" footnote with **no** sync plate |
| **Offline** | **The library persists from the offline cache** — the hero still renders, so a launch without a network opens on the shows and not on an error. The failure is an `InlineNotice` FOOTNOTE LINE (glyph + "Airing dates couldn't refresh" + a "Retry" link in ink), never an alert box. Verified genuinely offline on API 26. |
| **Accessibility** | At **1.6× font scale** nothing clips or overlaps, and the Today queue row correctly swaps to the LARGER poster slot as the spec requires |

## Three suspected violations — all three were FALSE POSITIVES

Recorded because the reasoning matters more than the result: each *looked* wrong against
`CLAUDE.md`'s prose, and acting on any of them would have introduced a divergence from the shipping
iOS app.

1. **"● AIRED YESTERDAY" — a dot on a non-today event.** The design law says *"the pill's dot belongs
   only to today's drop or a later-today airing."* But iOS's `eyebrowDot` is
   `now - last <= nowBarLiveWindow` — a **24-hour rolling window**, not a calendar-day test. An 8 PM
   drop seen at 9 AM is 13 hours old: dot shows, copy says "Aired yesterday". The prose and the
   implementation disagree **in the iOS source itself**, and the project's own rule is that the code
   wins. The Kotlin is faithful.
2. **Amber "Aired yesterday" on a queue row.** Same story — iOS's `queueLead` is byte-for-byte the
   same `now - last <= nowBarLiveWindow` test.
3. **The Profile stats line wrapping to two lines with six facts.** `CLAUDE.md` shows three
   ("635 episodes · 5 watching · 13 watched"), but iOS's `minorStatusLine` appends planned/paused/
   dropped whenever non-zero, for a documented reason: a paused show otherwise vanished from the UI
   entirely. It wraps here only because the QA library seeds all five statuses deliberately; iOS
   wraps identically on the same data.

**Lesson for later passes: check the Swift before "fixing" a design finding.** The port is faithful
in places where the design law's prose has drifted from its own implementation.

## Harness bugs found and fixed (not app bugs)

1. **Every capture in the first run was the sign-in screen** — 21 identical 455 KB PNGs. `capture.sh`
   built with the real `pk_test_` Clerk key, so `isClerkConfigured` was true, the dev bypass never
   engaged and `devSignInAuto` was ignored. `app/build.gradle.kts` already supports `-PclerkKey=` for
   exactly this; the script now uses it. **The identical file sizes were the tell** — real screens
   compress to 1.2–3.3 MB.
2. **The "offline" captures on API 26 were silently online.** `svc wifi disable` needs
   `CHANGE_WIFI_STATE`, which the shell user lacks on Android 8 — the *command* died with a
   `SecurityException` (which my crash detector then misreported as an app crash) and connectivity
   never changed. Now `adb root` first, and the script **verifies `wifi_on == 0` and SKIPS the
   captures rather than saving two online screenshots labelled offline**.
3. **The crash detector matched logcat's own "--------- beginning of main" headers** and crashes in
   unrelated system commands. It now greps `FATAL EXCEPTION` filtered to the app's package.
