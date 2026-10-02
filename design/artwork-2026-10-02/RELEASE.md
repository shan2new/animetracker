# Original artwork for Previously. — build 6

Approved by the user on 2 October 2026 for commit, push and TestFlight delivery.

The welcome screen uses an original softly lit viewing room as its full-screen backdrop.
The compact identity uses a 56-point split-flap mark and the existing 20-point brand wordmark.
There is no slogan. The public Clerk credential sheet uses the current mark.

Library, first-use Schedule and successfully loaded empty Saved posts use small original
graphite illustrations in a 128 × 100-point slot. Error states and accessibility text sizes
retain the existing symbol treatment. Populated content and recovery actions are unchanged.

The assets contain no show characters, actor likenesses or known fictional locations.
Built-in Image Gen generated the original artwork. Sunburst was not selectable or verified.
Asset packaging only crops transparent padding, resizes and encodes the output.

## Selected sources and prompts

- [Welcome room](source/login-cozy-backdrop-v3.png): [portrait prompt](login/prompt-v3.json),
  extended from the [cozy nook prompt](login/prompt-v2.json).
- [Library frames](source/empty-library-episode-frames-v2.png):
  [prompt](quiet-artwork-prompt-v2.json).
- [Schedule calendar](source/empty-schedule-flap-calendar-v1.png) and
  [Saved panels](source/empty-saved-bookmark-frames-v1.png): [prompts](expanded/prompts.json).

Only the four selected imagesets are included in the app asset catalogue. Earlier design
experiments and local data snapshots remain outside this release commit.

## Native rendering evidence

![Compact welcome](login/10-welcome-compact.jpg)

- [Welcome with larger text](login/11-compact-accessibility.jpg).
- [Library](expanded/06-library-current.jpg).
- [Schedule](expanded/03-schedule-after.jpg).
- [Saved](expanded/04-saved-after.jpg).

The Debug build and native iPhone 14 Pro / iOS 27 rendering checks passed. These captures
prove rendering only. Credentials, OAuth, recovery, physical-device behavior and the launch
transition were not verified. The artwork introduces no new runtime network request or animation.

## Release

`ios/project.yml` declares version 1.0, build 6. The release retains the configured
`https://anime.cognipin.com` API and existing Clerk instance. No server deployment is needed.
Archive, upload and TestFlight processing receipts will be recorded separately after delivery.
