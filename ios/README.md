# AniTrack (iOS)

A native SwiftUI rewrite of the AniTrack web app — an airing-first, franchise-centric anime
tracker. Built for **iOS 26** with Liquid Glass chrome, Swift 6, the Observation framework, and
the Clerk iOS SDK for auth. Talks to the AniTrack backend (see `../docs/api-contract.md`).

## Prerequisites

- macOS with **Xcode 26** (iOS 26 SDK).
- [XcodeGen](https://github.com/yonaskolb/XcodeGen):

  ```sh
  brew install xcodegen
  ```

## Generate the Xcode project

From this directory:

```sh
xcodegen generate
open AniTrack.xcodeproj
```

XcodeGen reads `project.yml`, resolves the Clerk SwiftPM package, and produces
`AniTrack.xcodeproj`. (The `.xcodeproj` is generated — don't edit it by hand; re-run
`xcodegen generate` after changing `project.yml`.)

## Configure

You must fill these in before a real build:

1. **Bundle identifier & signing** — `project.yml` sets a placeholder bundle id
   `com.anitrack.app`. In Xcode, select the `AniTrack` target → Signing & Capabilities, pick your
   Team, and adjust the bundle id if needed. (Or set `DEVELOPMENT_TEAM` in `project.yml`.)

2. **API base URL** — `API_BASE_URL` in `project.yml` (build settings) defaults to
   `http://localhost:8787`. It flows into `Info.plist` as `APIBaseURL` and is read by
   `AppConfig.apiBaseURL`. Local HTTP is allowed via `NSAllowsLocalNetworking`.

3. **Clerk publishable key** — `CLERK_PUBLISHABLE_KEY` in `project.yml` (build settings) is a
   placeholder (`pk_test_REPLACE_ME`). Replace it with your real key
   (`pk_test_…` / `pk_live_…`). It flows into `Info.plist` as `ClerkPublishableKey` and is read
   by `AppConfig.clerkPublishableKey`.

### Running without Clerk (dev mode)

If no real Clerk key is set, the app starts in **dev-bypass** mode: the sign-in screen lets you
enter a developer user id and signs in with an `Authorization: Bearer dev:<id>` token. This works
against a backend started with `DEV_AUTH_BYPASS=1`, so you can run the full app against the local
server before wiring real Clerk keys.

Tip: prefer keeping the Clerk key and API base URL out of source control by overriding the
`CLERK_PUBLISHABLE_KEY` / `API_BASE_URL` build settings via an `.xcconfig` rather than editing
`project.yml`.

## Build & run

Select the `AniTrack` scheme and an iOS 26 simulator (or device), then Build & Run (⌘R).

## Architecture

```
Sources/
  App/            @main app, root/auth gating, four-tab glass TabView, central AppModel
  Models/         Codable models matching the API contract (ms-epoch Int64 times)
  Networking/     APIClient (URLSession, Bearer injection), AppConfig (Info.plist)
  Auth/           AuthManager (Clerk + dev-bypass token vending), SignInView
  Features/
    Today/        "Out now" / "Airing soon" with briefing/spotlight/grid layouts
    Schedule/     IST Mon–Sun week
    Library/      Behind / Caught up / Finished / Plan buckets + chips + search
    Discover/     Trending + AniList-backed search, add-to-library
    FranchiseDetail/ per-part progress steppers, status control, subscribe
  DesignSystem/   colors, glass helpers, poster/briefing/hero cards, overlays, toast
  Util/           Formatting.swift (verbatim IST/format.ts port)
```

The deployment target is iOS 26.0, but every Liquid Glass API is gated behind
`if #available(iOS 26.0, *)` with `.ultraThinMaterial`/solid fallbacks for safety.
