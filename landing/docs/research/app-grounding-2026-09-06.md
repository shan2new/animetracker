# Grounding the landing page in the iPhone app

The landing page at `6c39036` had an accepted poster-wall hero, but its lower demo invented a separate progress dashboard, calendar and show-specific update panel. Those arrangements did not represent the current native app. The initial revision preserved the hero and replaced that demo with an interactive tour of actual iPhone screens. The user then requested an improvement to the hero as well.

## Hero refinement

The opening now pairs a larger, left-aligned Outfit headline with the actual Library screenshot. Amber highlights the promise of keeping your place; supporting copy explains episode tracking, grouped seasons and returning shows. Existing posters remain behind the product at lower contrast, reduced from 21 to 12 images. The Library preview is loaded eagerly at high priority, while decorative posters receive low priority. The primary action scrolls to the app tour.

Desktop uses two columns; mobile places the message and action before the full, uncropped screen. The screenshot retains its native proportions. Existing branding, public availability and the four-tab tour remain intact. This was an authorized refinement of the existing design, not a new visual direction awaiting selection.

## Refinement after direction approval

The user welcomed the hero improvement and requested continued iteration. The next pass preserves that composition, aligns the tour's text and screenshot columns with it, and unifies the warm neutral palette through the FAQ and footer.

- The hero's actual Library screenshot and caption link to the Library tour.
- Desktop tour tabs now include brief explanations. Mobile keeps the four native names and uses targets sized to contain their labels.
- The tab bar remains visible while scrolling within the tour. Switching from a scrolled position returns to the new section's introduction, retains keyboard focus and respects the reduced-motion preference.
- Manual tab selection updates the URL fragment without adding history entries. Repeated Library links and reloads therefore match the visible section.
- Every image's full-screen control is visible below its capture. No control covers the app's status bar or native navigation.
- Verified a sticky tab switch from a scrolled mobile screen, all tab labels fitting their targets at 320 pixels, repeated hero-to-Library navigation after selecting Search, arrow-key and Enter activation, dialog focus containment, Escape dismissal and focus restoration. Desktop tabs measure 84 pixels high; mobile tabs 54 pixels; image controls 44 pixels.
- Constrained the decorative screenshot glow to the available page gutters after checking the new column alignment at laptop widths; it no longer extends the page beyond the viewport.

## Product evidence

Read the current iOS source and inspected the running app before changing the landing page. Root navigation is **Today, Schedule, Library, Search**. The tour uses these exact names and actual screens.

| Page content | Native evidence |
| --- | --- |
| Today: current watching state, next action and upcoming shows | `ios/Sources/Features/Today/TodayView.swift`; captured caught-up Re:ZERO hero and Upcoming shelf |
| Schedule: dated episode agenda and date picker | `ios/Sources/Features/Schedule/ScheduleView.swift`; captured actual 6 September agenda |
| Library: watching state and returning shows | `ios/Sources/Features/Library/LibraryView.swift`; captured Returning, Watching and Planned shelves |
| Search: anime and TV together, trending discovery and add controls | Native Search screen and `ios/Sources/App/RootView.swift` |
| Seasons, episode progress, movies and extras remain within a show | `ios/Sources/Features/FranchiseDetail/FranchiseDetailView.swift`; captured Game of Thrones season selector |
| Recap describes release changes since the last visit | `ios/Sources/Features/Today/RecapDigest.swift`; newly aired unwatched episodes and returning shows, not plot summaries |
| Unwatched episode titles and stills can remain concealed | Episode reveal controls in `FranchiseDetailView.swift` |
| JSON and CSV library export from Profile | `ios/Sources/Features/Profile/ProfileView.swift` and `LibraryExport.swift` |
| iOS minimum version | `ios/project.yml`: iOS 18.0 |

Returning and Announced are release facts, not extra personal watch statuses. General TV release dates are date-only; the tour does not turn them into invented clocks or countdowns. No progress, search, recap or account data is simulated by the website.

## Screenshot provenance

Captured on 6 September 2026 from the already-installed `com.anitrack.app`, displayed as Previously., version/build 1.0 / 1.0, on an iPhone 14 Pro simulator running iOS 27.0. The installed executable was dated 5 September at 23:54; its exact commit is unknown. Source inspection used the current local app checkout, including its in-progress changes. No rebuild, install, account edit or progress mutation was performed for these captures.

| Landing asset | Original capture | Content |
| --- | --- | --- |
| `public/app/today.webp` | `today.png` | Caught-up Today hero, next episode and Upcoming shelf |
| `public/app/schedule.webp` | `schedule.png` | Settled dated agenda |
| `public/app/library.webp` | `library.png` | Returning, Watching and Planned shelves |
| `public/app/search.webp` | `search.png` | Trending grid, combined search and add/saved controls |
| `public/app/seasons.webp` | `detail-season-menu.png` | Native season picker on the show page |

All originals are 1179 × 2556. Full images use lossless WebP with exact transparency preservation; decoded RGBA hashes matched their source PNGs. Four 786-pixel-wide previews use WebP quality 88. They load lazily as tabs become visible; the larger files load when their dialogs open. The screenshots were not redrawn, retouched or populated with demo dates. Release information is an app-rendered snapshot, not independently verified release reporting.

## Verification

- Existing poster and brand assets are unchanged. Hero markup was preserved in the initial grounding pass, then refined after the user's follow-up request.
- `npm run lint`, `npx tsc --noEmit`, `npm run build` and `git diff --check` passed. Vinext reported its existing inability to statically classify these routes; the build completed successfully.
- The server returned HTTP 200, one H1, valid internal anchor targets, FAQ answers in server-rendered HTML and the corrected iOS metadata.
- Checked all four tour tabs and their corresponding images, plus the native season-picker dialog.
- Checked desktop at 1440 pixels and mobile at 390 and 320 pixels: no horizontal overflow; all four tab targets fit and are at least 54 pixels tall.
- Verified arrow-key focus navigation and Enter activation, dialog focus containment, Escape dismissal and focus restoration, and FAQ expansion.
- Fixed a mobile dialog sizing bug found during QA. Enlarged screens now use an explicit viewport-constrained width and remain scrollable when taller than the viewport.
- Verified the built production page at `http://localhost:4322/`: legacy Library deep link, season dialog, scrolling in an 844 × 390 landscape viewport, dismissal and the 390-pixel mobile Today layout. No browser console errors or warnings were reported. The development server was stopped after build-related hot-reload state became stale; the review preview runs the production build.
- New motion has reduced-motion CSS overrides. Full screenshots retain their original proportions and content.
- Hero checked at 1440, 983, 390 and 320 pixels. The CTA routes to the Today tour. Tablet checking also identified a decorative glow extending the lower tour's page width by 24 pixels; its inset is now constrained at that breakpoint.

Before and after page screenshots are saved in this task's `previously-landing/qa` visualization folder. Native originals and detailed capture notes are in `/private/tmp/previously-ios-reference-20260906`.

## Scope

Work is isolated from the existing dirty iOS/Android checkout, in `/private/tmp/previously-landing-20260906` on `codex/previously-landing-grounding`, based on main at `6c39036`. No app source or account state was changed. The landing revision is kept on its dedicated branch. Public availability and existing legal-page drafts retain their previous status.
