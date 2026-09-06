# Shipping a TestFlight beta

The mechanical steps for getting a build in front of testers, and the reasons behind the
non-obvious ones. Written 3 Sep 2026 for the first beta (v1.0 build 1).

**Bundle IDs** — app `com.anitrack.app`, widget `com.anitrack.app.widgets`. Team `YLPZXZS2F4`.
**Display name** on the phone is `Previously.` (`CFBundleDisplayName`), independent of the App
Store listing name.
**Deployment target** is **iOS 18.0** (see the note at the top of `ios/project.yml` for why 18 and
not 17 or 26), so the beta reaches iPhone XR / XS and later. iOS 26 flourishes are gated, not
removed — `DesignSystem/GlassHelpers.swift`.

## Build with the RELEASE Xcode, not the beta

`xcode-select -p` points at `Xcode-beta.app` (Xcode 27, iOS 27 SDK) for day-to-day work.
**App Store Connect rejects builds made against a beta SDK.** Every archive command below therefore
pins the stable toolchain explicitly:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

Xcode 26.6 ships the iOS 26.5 SDK, which is what an 18.0 deployment target builds against
(`minos 18.0 / sdk 26.5` in the shipped binary). The app no longer ships any Metal shader (the
old splash's `SplashShaders.metal` went with the 4 Sep launch rebuild), so the stable Xcode needs
no Metal toolchain download; if one is ever added back, Xcode 26 stopped bundling `metal` and
needs `xcodebuild -downloadComponent MetalToolchain` once.

## 1. Deploy the backend first

The app's Privacy Policy and Terms URLs point at `https://anime.cognipin.com/{privacy,terms}`
(`server/src/routes/legal.ts`). Those routes must be **live before** the build goes for Beta App
Review — a 404 on the privacy URL is a rejection. The domain fronts the Mac mini through
Cloudflare, so deploying means pulling and restarting *there*, not on the laptop:

```bash
# on the Mac mini
cd ~/…/animetracker && git pull && cd server && npm install && npm run db:migrate
# then restart however the process is supervised (launchd / pm2 / tmux)
```

Verify from anywhere:

```bash
curl -s -o /dev/null -w "%{http_code}\n" https://anime.cognipin.com/privacy   # want 200
```

Also confirm production still refuses the dev bearer — `assertAuthConfig` enforces it at boot, but
check the deploy rather than trust it:

```bash
curl -s -o /dev/null -w "%{http_code}\n" -H "Authorization: Bearer dev:probe" \
  https://anime.cognipin.com/me/library    # want 401
```

## 2. Create the App Store Connect record

Apple's **app name must be globally unique**, and `Previously.` is a common word — expect it to be
taken. The listing name and the name on the home screen are separate, so a listing called
`Previously — TV Tracker` still installs as `Previously.`; only `CFBundleDisplayName` decides the
latter.

In App Store Connect → Apps → **+** :

| Field | Value |
|---|---|
| Platform | iOS |
| Name | `Previously.` (fall back to a qualified variant if taken) |
| Primary language | English (U.S.) |
| Bundle ID | `com.anitrack.app` |
| SKU | anything private, e.g. `previously-ios-1` |
| User access | Full Access |

If the bundle ID is not in the dropdown, the App ID has not been registered against the paid team
yet — archiving once with `-allowProvisioningUpdates` (step 3) registers it.

## 3. Archive and upload

```bash
cd ios && xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -scheme AniTrack -configuration Release -destination 'generic/platform=iOS' \
  -archivePath build/Previously.xcarchive -allowProvisioningUpdates archive
```

`-allowProvisioningUpdates` is what lets Xcode create the **Apple Distribution** certificate and
the App Store provisioning profiles for both bundle IDs. The machine only had an *Apple
Development* certificate before the first archive.

Then either open `build/Previously.xcarchive` in Xcode's Organizer and use **Distribute App →
App Store Connect**, or export and upload from the CLI:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -exportArchive \
  -archivePath build/Previously.xcarchive -exportOptionsPlist ExportOptions.plist \
  -exportPath build/export -allowProvisioningUpdates
```

The CLI *upload* (`xcrun altool --upload-app`) additionally needs an App Store Connect API key
(Users and Access → Integrations → App Store Connect API → generate, download the `.p8` once).
Worth doing for the second build; the Organizer is less setup for the first.

**Bump `CURRENT_PROJECT_VERSION` in `ios/project.yml` before every upload** — App Store Connect
rejects a build number it has already seen, and `manageAppVersionAndBuildNumber` is deliberately
`false` in `ExportOptions.plist` so nothing edits it behind your back.

### If the export fails with "does not have permission to create iOS App Store profiles"

Seen on the first attempt, 3 Sep, with `No provider associated with App Store Connect user`. It
means the Apple ID is still acting as a **free personal team**, whatever the purchase receipt says.
The tell is profile lifetime: run

```bash
security cms -D -i ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles/*.mobileprovision \
  | plutil -p - | grep -E "TeamName|ExpirationDate"
```

A free personal team issues **7-day** profiles; a paid team issues **one-year** ones. Check, in
order:

1. **Is enrolment actually active?** developer.apple.com/account → Membership details. Payment
   taken is not the same as activated — individual enrolments typically take 24–48 h and can need
   ID verification.
2. **Is the Program License Agreement accepted?** The commonest cause. Until the Account Holder
   accepts it, App Store Connect reports no provider and distribution is blocked entirely.
   developer.apple.com/account → Agreements, or the banner in App Store Connect.
3. **Is Xcode's session stale?** Xcode → Settings → Accounts → sign out and back in, then
   *Download Manual Profiles*. A cached personal-team session survives enrolment.
4. **Did enrolment create a NEW team ID?** An Apple ID can hold a personal team *and* a paid one at
   once. If Membership details shows a Team ID other than `YLPZXZS2F4`, update **both**
   `DEVELOPMENT_TEAM` entries in `ios/project.yml` and the `teamID` in `ios/ExportOptions.plist`,
   then `xcodegen generate`.

Nothing else in the pipeline is waiting on this — `archive` already succeeds. Once the membership
is live, `-exportArchive` is one command.

## 4. Testers

**Internal** (up to 100 App Store Connect users): Users and Access → **+** → invite the tester's
Apple ID, role *Developer* or *Marketing*, then TestFlight → Internal Testing → add them to the
group. **No Beta App Review**, available as soon as the build finishes processing (~5–20 min).
This is the fast path for one trusted friend; it does give them some App Store Connect visibility.

**External** (up to 10 000, public link, no ASC access): needs **Beta App Review** on the first
build of a version — roughly a day — plus, in App Information / TestFlight:

- Privacy Policy URL — `https://anime.cognipin.com/privacy`
- Feedback email — the support address in `project.yml`
- Beta app description and **review notes**. Say plainly that the backend is a self-hosted personal
  server, that sign-in is email-based via Clerk, and that the catalogue comes from AniList/TMDB and
  the app neither hosts nor links to video. Reviewers reject media apps they suspect of piracy;
  pre-empting that costs one sentence.

## Already handled in the repo

Things that bite on a first submission and are done — don't redo them:

- `ITSAppUsesNonExemptEncryption: false` in the Info.plist, so no export-compliance prompt per
  upload. The app's only cryptography is HTTPS via the OS.
- `ios/Resources/PrivacyInfo.xcprivacy` — the privacy manifest. Declares email address, user id and
  other user content (all *App Functionality*, none for tracking), and `UserDefaults` under reason
  `CA92.1`. Apple diffs this against the App Privacy answers in App Store Connect, so answer those
  to match. **Update it in the same commit as any change to what the app collects.**
- In-app account deletion (guideline 5.1.1(v)) — Profile → Delete Account → `DELETE /me`.
- No entitlements are needed: the Live Activity requires only `NSSupportsLiveActivities`, episode
  alerts are local notifications, and there is no App Group or push certificate.
- The developer sign-in panel is double-gated (`#if DEBUG` **and** `AppConfig.isLocalBackend`), so
  it cannot appear in a TestFlight build even if one were pointed at a local server.
- `qa/` (1.3 GB of capture PNGs) is gitignored.

## Known beta risks

- **Clerk is on a development instance** (`pk_test_…`). Fine for a handful of testers; it is capped
  and social sign-in uses Clerk's shared OAuth credentials. Moving to production needs a `pk_live_`
  key, CNAMEs on `cognipin.com` and a matching `CLERK_JWT_KEY` on the server — do it before opening
  the beta widely.
- **One self-hosted backend, no redundancy.** If the Mac mini is down the app still opens on its
  offline library cache, but nothing syncs. The Terms say as much.
- **Support contact is a personal Gmail**, and it is published on both legal pages. Consider an
  alias before the listing is public.
