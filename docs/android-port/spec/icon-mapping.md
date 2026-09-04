# SF Symbols → Material Symbols mapping

**42 distinct SF Symbols** are used across `ios/Sources` and `ios/Widgets`. An earlier count of 24
was wrong: it only matched `systemName: "…"` literals and missed every symbol passed as a stored
property or enum payload — which is most of the state-screen iconography (`EmptyState`,
`InlineNotice`, `SyncBanner`). The inventory below is the authoritative one.

## How to read this table

- **Material Symbols** is the target set, shipped as the `material-symbols` font or as individual
  vector drawables. Use the **Rounded** optical family — SF Symbols' default is a rounded-terminal
  geometric face, and Material Symbols Outlined has squarer terminals that read colder against
  Outfit. Weight 400, grade 0, optical size 24 unless noted.
- **Fill** matters: SF's `.fill` suffix means a solid glyph. Material Symbols expresses this with
  the `FILL` axis (0 → 1), not a different glyph name.
- Where a symbol carries **meaning** in this app, the meaning column says what it must keep saying;
  a visually closer glyph that changes the meaning is the wrong pick.
- `⚠` marks the ones with no clean equivalent — decide these deliberately, do not let an
  implementer improvise.

| # | SF Symbol | Material Symbol | Fill | Notes / meaning to preserve |
|---|---|---|---|---|
| 1 | `arrow.triangle.2.circlepath` | `sync` | 0 | Rewatch / restart. NOT `refresh` — that reads as reload. |
| 2 | `arrow.up.backward` | **`open_in_new`** | 0 | "Opens elsewhere" affordance. **ERRATUM (2026-09-04, PLAN D29/§9.2): was `arrow_outward` mirrored / `north_west`.** Decided as `open_in_new` — the Android reflex for "leaves the app", same reasoning as the share glyph (D3). |
| 3 | `arrow.up.right` | **`open_in_new`** | 0 | External link (trailer provider, JustWatch). **ERRATUM (2026-09-04, PLAN D29/§9.2): was `arrow_outward`.** |
| 4 | `bell` | `notifications` | 0 | Reminder, unset. |
| 5 | `bell.badge` | `notifications_active` | 0 | Reminder set. Material's badge dot differs — acceptable. |
| 6 | `bell.fill` | `notifications` | **1** | Reminder committed (amber state). |
| 7 | `bookmark` | `bookmark` | 0 | Planned / saved. |
| 8 | `calendar` | `calendar_month` | 0 | Schedule empty state. |
| 9 | `checkmark` | `check` | 0 | Bare tick. The settled `MarkRing` watched state. |
| 10 | `checkmark.circle.fill` | `check_circle` | **1** | "Everything synced". |
| 11 | `chevron.down` | `keyboard_arrow_down` | 0 | Not `expand_more` at small sizes — same glyph, `keyboard_arrow_*` is the metric-matched one. |
| 12 | `chevron.forward` | `chevron_right` | 0 | Row/section navigation. Must mirror in RTL. |
| 13 | `chevron.up.chevron.down` | `unfold_more` | 0 | The season picker. Good match. |
| 14 | `clock.arrow.circlepath` | `history` | 0 | Watch history. |
| 15 | `curlybraces` | `data_object` | 0 | Debug/JSON affordance. |
| 16 | `doc.text` | `description` | 0 | Export / legal doc. |
| 17 | `dot.radiowaves.left.and.right` | `sensors` | 0 | ⚠ "Live / airing now". `sensors` is the closest; `podcasts` is visually nearer but means audio. Consider a custom vector — this one carries the Now Bar's meaning. |
| 18 | `ellipsis` | `more_horiz` | 0 | Overflow menu. |
| 19 | `envelope` | `mail` | 0 | Support contact. |
| 20 | `exclamationmark.circle` | `error` | 0 | Recoverable failure. Material `error` is filled-ish; use FILL 0. |
| 21 | `exclamationmark.triangle.fill` | `warning` | **1** | Sync failure. |
| 22 | `eye` | `visibility` | 0 | Show watched. |
| 23 | `eye.slash` | `visibility_off` | 0 | Hide watched (Schedule filter). |
| 24 | `hand.raised` | `front_hand` | 0 | Privacy policy row. |
| 25 | `hand.tap` | `touch_app` | 0 | Haptics setting. |
| 26 | `line.3.horizontal.decrease` | `filter_list` | 0 | Filter. |
| 27 | `magnifyingglass` | `search` | 0 | Search. |
| 28 | `person.fill` | `person` | **1** | Avatar fallback. |
| 29 | `photo` | `image` | 0 | Art placeholder. |
| 30 | `play.fill` | `play_arrow` | **1** | Trailer play. |
| 31 | `play.rectangle` | `smart_display` | 0 | Trailer card affordance. `ondemand_video` is an alternative. |
| 32 | `plus` | `add` | 0 | Add to library. Stays **neutral ink**, never amber — see the accent rule. |
| 33 | `rectangle.portrait.and.arrow.right` | `logout` | 0 | Sign out. |
| 34 | `rectangle.stack` | `layers` | 0 | Library / all titles. |
| 35 | `slider.horizontal.3` | `tune` | 0 | "No titles match" filter state. |
| 36 | `square.and.arrow.up` | `ios_share` | 0 | ⚠ Share. On Android this should become the **system share sheet** and Material's `share` glyph — the iOS share box-and-arrow is an iOS idiom. Per the fidelity decision (Android reflexes), use `share`. |
| 37 | `tablecells` | `table` | 0 | Export as table. |
| 38 | `trash` | `delete` | 0 | Destructive. |
| 39 | `tv` | `tv` | 0 | TV scope / source. |
| 40 | `wifi.exclamationmark` | `wifi_tethering_error` | 0 | ⚠ Weak match. `signal_wifi_statusbar_not_connected` is closer in meaning. Verify visually. |
| 41 | `wifi.slash` | `wifi_off` | 0 | Offline. |
| 42 | `xmark` | `close` | 0 | Dismiss. |

## Non-symbol image assets (port directly, no mapping needed)

| Asset | Source | Android destination |
|---|---|---|
| `TabToday`, `TabSchedule`, `TabLibrary`, `TabAdd` | `icon/navbar/vector/*.svg` — simple stroked paths, `viewBox="-3 -3 30 30"` | Compose `ImageVector`. **Translate paths by +3,+3**: VectorDrawable has no negative viewport origin. `viewportWidth/Height = 30`, `defaultWidth/Height = 24.dp`, stroke width 1.5, round caps/joins, colour from `LocalControlInk` so tab tinting stays runtime-controlled. |
| `SplashLayerCard`, `SplashLayerPeek`, `SplashLayerProgress` | PNG @1x/2x/3x | `res/drawable-xhdpi` (=@2x) and `drawable-xxhdpi` (=@3x). iOS has no @4x, so **generate xxxhdpi by re-rendering from vector**, don't upscale. |
| `TMDBLogo` | SVG | VectorDrawable. Attribution line is mandatory per the API contract. |
| App icon | `icon/background.svg` + `icon/midground.svg` + `icon/foreground.svg` | Adaptive icon: background layer + foreground layer (merge midground into foreground), plus a **monochrome** layer for Android 13+ themed icons — this does not exist yet and must be drawn. |

## Density mapping reference

iOS `@1x/@2x/@3x` are not Android's buckets. The correct correspondence:

| iOS | Scale | Android bucket | Scale |
|---|---|---|---|
| @1x | 1.0 | `mdpi` | 1.0 |
| — | 1.5 | `hdpi` | 1.5 |
| @2x | 2.0 | `xhdpi` | 2.0 |
| @3x | 3.0 | `xxhdpi` | 3.0 |
| — | 4.0 | `xxxhdpi` | 4.0 |

The emulator in use (`PreviouslyQA_API36`, Pixel 9 Pro geometry) is **480 dpi = xxhdpi**, so it
exercises the @3x-equivalent assets. Test at `xxxhdpi` too — several current flagships are there,
and iOS never had to supply that size.
