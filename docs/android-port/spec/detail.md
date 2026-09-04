# Franchise Detail — hero, episodes, catalogue shelves, rewatch

The show page is the largest screen in Previously. and the one every other surface pushes into. It opens on a full-bleed billboard (the cover shown whole at 68 % of the screen with the title and one identity line laid over its foot), hands the title into the navigation bar the moment the hero's *copy* reaches the toolbar's bottom edge, and then runs a single ungrouped column on the canvas: a state block carrying the screen's one action, the synopsis, a season picker heading a six-row window of episodes, a "Movies & extras" art shelf, and four catalogue shelves in Apple TV's order (Trailers · Cast & crew · More like this · Where to watch). It owns two pushed screens of its own — the full season episode list and Watch history — and three sheets (trailer player, Start rewatch, Session detail). This document specifies all of it: exact geometry, exact copy, every conditional branch, every animation and haptic, and the accessibility contract. Where a rule exists because a specific bug was shipped and fixed, the source comment is quoted — those comments *are* the spec.

**Source files** (all under `ios/`):

| File | Contents |
|---|---|
| `Sources/Features/FranchiseDetail/FranchiseDetailView.swift` | The show page + `SeasonEpisodesView` (1937 lines) |
| `Sources/Features/FranchiseDetail/DetailSupport.swift` | `EpisodeList`, `EpisodeStill`, `WithheldStillTile`, `DetailTint`, `EpisodeCopy`, `DetailMetrics`, `RewatchArrival` |
| `Sources/Features/FranchiseDetail/DetailEnrichment.swift` | `DetailShelf`, `TrailerCard`, `PersonCard`, `WatchProvidersRow`, `ProviderMark`, `VideoSheet`, `VideoEmbed` |
| `Sources/Features/FranchiseDetail/RewatchViews.swift` | `StartRewatchSheet`, `WatchHistoryView`, `SessionDetailView`, `CentreShortList` |

---

## 0 · Tokens this area consumes

Only the tokens actually referenced below. Values are literal; nothing is a range.

### 0.1 Colour (`ThemeColor`)

| Token | Value | Used for |
|---|---|---|
| `canvas` | `#09090B` | Screen ground, `chromeVeil`, `HeroCopyScrim` stops |
| `canvasRaised` | `#0D0E11` | Sheet grounds (Start rewatch, Session detail) |
| `surfaceFlat` | `#171719` | `.plate` fill reference, `VideoSheet` player ground, inactive rail node |
| `surfaceRaised` | `#242428` | Poster/still/provider/trailer grounds, `.raised` fill reference |
| `surfaceFloating` | `#2A2D36` | Reduce-Transparency chrome fallback |
| `surfacePressed` | `#353842` | `RowPressStyle` wash (at 0.6 alpha) |
| `textPrimary` | `#F4F1EC` | Titles, glyphs on chrome |
| `textSecondary` | `#AAA6A0` | Synopsis, support lines, row meta |
| `textTertiary` | `#85817C` | Third lines, counts, chevrons, settled check ink |
| `textDisabled` | `#807C77` | `MediaRow` chevron only |
| `accent` | `#F0A24E` | Amber: `MarkRing` lead ring, `ProgressBar` fill, `rowMetaLead`, active-session ring, capsule ground |
| `accentPressed` | `#D88D3B` | Pressed accent capsule / split half |
| `accentSoft` | `#F0A24E` @ 0.14 | Active rail-node halo |
| `onAccent` | `#0B0B0D` | Ink on an amber ground |
| `interactive` | **alias of `textPrimary`** | Every bare tappable word/glyph: `+`, "Read more", "All 24 episodes", "Done", "Cancel", `arrow.up.right` |
| `ambientBackdropFallback` | `#432D21` | Skeleton hero ground of last resort |
| `destructive` | `#FF453A` | "Delete this session…" |
| `separatorQuiet` | white @ 0.045 | Episode-row rules, grouped-row rules |
| `hairline` | white @ 0.055 | Top-edge highlight on capsules/discs/raised surfaces |
| `posterEdge` | white @ 0.09 | Edge of every piece of artwork |
| `stroke` / `strokeStrong` | white @ 0.12 / 0.20 | Secondary capsule border; `ProgressBar` track; history rail line |
| `markRingIdle` | white @ 0.34 | Unmarked, non-lead `MarkRing` stroke |
| `scrim` | black @ 0.56 | `ProgressBanner` foot gradient end |
| `scrimStrong` | black @ 0.72 | `OverArtLabel` capsule, play disc, settled badge |
| `skeleton` | `#F4F1EC` @ 0.11 | Skeleton blocks |
| `plateLift` / `raisedLift` | white @ 0.055 / 0.11 | `.plate` / `.raised` are a **lift over whatever is beneath**, never an opaque fill |
| `controlSheen` | white @ 0.22 | Lit top edge of a filled capsule |

> **Amber is not an action colour.** `accent` is rationed to MEANING (a real next step: an air time, "Episode 19 next") and STATE (selected, committed, active), plus GROUNDS where the ink on top is `onAccent`. Every tappable *word* on this screen uses `interactive` — which is the same value as `textPrimary`. On Android: do **not** substitute your theme's primary colour for links.

### 0.2 Spacing, radius, metrics

| Token | Value |
|---|---|
| `ThemeSpace.x0_5 / x1 / x2 / x3 / x4 / x5 / x6 / x8` | 2 / 4 / 8 / 12 / 16 / 20 / 24 / 32 |
| `ThemeRadius.episodeStill` | 8 |
| `ThemeRadius.poster` | 10 |
| `ThemeRadius.compactControl` | 12 |
| `ThemeRadius.row` | 16 |
| `ThemeRadius.card` | 22 |
| `ThemeMetrics.gutter` | 16 |
| `ThemeMetrics.sectionGap` | 30 |
| `ThemeMetrics.labelGap` | 10 |
| `ThemeMetrics.cardGap` | 10 |
| `ThemeMetrics.shelfGap` | 12 |
| `ThemeMetrics.titleGap` | 3 |
| `ThemeMetrics.artGap` | 14 |
| `ThemeMetrics.heroClearance` | 26 |
| `ThemeMetrics.rowCompact` | 56 |
| `ThemeMetrics.rowStandard` | 88 |
| `ThemeMetrics.rowMedia` | 100 |
| `ThemeMetrics.rowEpisode` | 82 |
| `ThemeMetrics.bottomChromeHeight` | 64 |
| `ThemeMetrics.tabBarClearance` | 64 + 12 = **76** |
| `ThemeMetrics.inlineBarHeight` | 44 |
| `ThemeMetrics.barEdgeRamp` | 28 |
| `ThemeMetrics.chromeBarOpacity` | 0.74 |
| `ThemeMetrics.rootWashHeight` / `rootWashIntensity` | 320 / 0.4 |
| `ThemeMetrics.topSafeInset` | read once from the key window; **59** before a window exists (never cached at 59) |
| `ThemeMetrics.windowHeight` | read once from the key window; **852** fallback (never cached at 852) |
| `ThemeMetrics.scrollSample(y)` | `(clamp(y, −320, 240) × 2).rounded() / 2` — clamp + half-point quantise |
| `EpisodeArtwork.slot` | **120 × 68** (16:9) |
| `PosterSize.row` | 60 × 90, radius 10, shadow `.art` |
| `PosterSize.queue` | 44 × 66, radius 8, shadow `.none` |
| `PosterSize.shelfMedium` | 112 × 168, radius 12, shadow `.art` |
| `DetailMetrics.toolbarClearance` | 46 (and `FranchiseDetailView.toolbarBand` = 46, a private twin) |
| `DetailMetrics.bottomClearance` | `76 + (SyncCenter.failedChanges.isEmpty ? 0 : 72)` → **76 or 148** |

`ShadowToken`: `.art` = black 0.55 / radius 12 / y 7 · `.card` = black 0.45 / 18 / 10 · `.artHero` = black 0.60 / 26 / 14 · `.floating` = black 0.50 / 26 / 14.

### 0.3 Type

Outfit **speaks** (identity, buttons, row/body copy). SF **annotates** (dense metadata, section eyebrows, numerals, and the one long-form paragraph). `tracking` is in **points**; on Android convert to `em` = `tracking_pt / size_pt`.

| Token | Font | Size | Tracking | Dynamic-Type ref |
|---|---|---|---|---|
| `displayXL` | Outfit Bold | 34 | −0.80 | largeTitle |
| `heroTitle` | Outfit Bold | 28 | −0.55 | title |
| `showTitleL` | Outfit SemiBold | 22 | −0.35 | title2 |
| `sectionTitle` | Outfit SemiBold | 20 | −0.30 | title3 |
| `bodyEmphasis` | Outfit SemiBold | 17 | −0.20 | body |
| `rowTitle` | Outfit SemiBold | 17 | −0.20 | headline |
| `showTitleM` | Outfit SemiBold | 17 | −0.20 | headline |
| `body` | Outfit Regular | 17 | −0.10 | body |
| `button` | Outfit SemiBold | 16 | −0.15 | callout |
| `heroMeta` | Outfit Regular | 15 | −0.05 | subheadline |
| `shelfTitle` | Outfit Medium | 14 | −0.10 | subheadline |
| `listAction` | Outfit SemiBold | 13 | 0 | footnote |
| `prose` | **SF** system | subheadline | 0 | — |
| `metadata` / `rowMeta` | **SF** footnote | — | 0 | — |
| `metadataEmphasis` / `rowMetaLead` | **SF** footnote semibold | — | 0 | — |
| `shelfCaption` | **SF** caption medium | — | 0 | — |
| `sectionLabel` | **SF** caption2 semibold | — | **+1.0** | — (always `.textCase(.uppercase)`) |
| `caption` | **SF** caption2 | — | 0 | — |

### 0.4 Motion

| Token | Curve |
|---|---|
| `uiPress` | easeOut 0.09 |
| `uiMicro` | spring(response 0.22, damping 0.88) |
| `uiSnappy` | spring(0.34, 0.84) |
| `uiSettle` | spring(0.46, 0.90) |
| `uiMilestone` | spring(0.38, 0.74) |
| `uiGentle` | easeInOut 0.22 |
| `uiPoster` | easeOut 0.18 |
| `uiSweep` | cubic-bezier(0.40, 0.00, 0.20, 1.00) 0.52 |
| `uiDismiss` | easeIn 0.16 |
| `uiReduced` (= `uiCrossfade`) | easeOut 0.12 |

`ThemeMotion.pick(token, reduceMotion:)` returns `uiReduced` when Reduce Motion is on. **Every** animation on this screen except the hero drift and the skeleton breath goes through `pick`; those two are branched by an explicit `if reduceMotion` instead.

`AnyTransition.handoff(reduceMotion:)` — the one card-replacement transition:
- Reduce Motion → `.opacity` on `uiReduced`, symmetric.
- Otherwise **asymmetric**: insertion `.opacity` on `uiSettle` **delayed 0.08 s**; removal `.opacity` on `uiDismiss` (0.16 s). *"A symmetric crossfade superimposes two different sentences, which is what a smear is."*

### 0.5 Haptics (`FeedbackCoordinator`)

Global gate: haptics off → nothing; app not `.active` → nothing. Per-token throttle floor: `.selection` 0.04 s, everything else **0.3 s**.

| Token | iOS generator | Fired in this area by |
|---|---|---|
| `.selection` | `UISelectionFeedbackGenerator` | `setStatus`, scope-row tap in Start rewatch |
| `.commitLight` | impact light, intensity **0.65** | single episode mark |
| `.commitMedium` | impact medium, intensity **0.72** | `setProgress` where `|new − prev| > 1` |
| `.success` | notification success | mark that completes a season/series, start rewatch, restart rewatch, mark series watched, mark rewatch complete |
| `.destructive` | notification warning | cancel/stop rewatch, delete session, delete watch history |

**At most one haptic per transaction.** Multi-write commands pass `haptic: false` to every write and fire one `.success` themselves.

---

## 1 · Data pipeline

### 1.1 Inputs

```
FranchiseDetailView(franchiseId: String,
                    focus: EpisodeFocus? = nil,          // {mediaId, episode} — Schedule deep link
                    push: (DetailPush) -> Void)
```

`DetailPush` is a `Hashable` route enum pushed on the **owning tab's** `NavigationPath` (Detail is a plain push, never a sheet or a `.zoom`):

| Case | Destination |
|---|---|
| `.episodes(franchiseId, mediaId, focusEpisode: Int?)` | `SeasonEpisodesView` |
| `.history(franchiseId)` | `WatchHistoryView` |
| `.detail(franchiseId)` | another `FranchiseDetailView`, one deeper |

All three destinations get `.pushedScreenChrome()` from the router: bottom scroll-edge chrome + `chromeScrollEdgeHidden(.bottom)` + `contentMargins(.bottom, 76, for: .scrollContent)`. Detail and `SeasonEpisodesView` then override the bottom content margin with `DetailMetrics.bottomClearance`.

### 1.2 The two reads

```swift
.task(id: franchiseId) {
    await load()
    await loadProviders()
}
```

**`load(force: Bool = false)`**
1. `guard force || fetched?.id != franchiseId else { return }` — *"the appearance task passes nothing, so popping back from the season list no longer refetches the whole franchise under the user."*
2. `loading = true`; `defer { loading = false }`
3. `fetched = try await api.franchise(id: franchiseId, country: AppRegion.current)` → `GET /franchises/{id}?country=XX`
4. success → `loadError = false`; then `retryEnrichmentIfEmpty()`
5. failure → **`if !error.isCancellation { loadError = true }`**. A pop mid-fetch cancels the task; that is not a failed load and must not leave the "couldn't refresh" footnote standing when the user returns.

`AppRegion.current` = `Locale.current.region?.identifier` uppercased, accepted only when it is exactly 2 letters; otherwise **`"US"`**. *"An unset region is not 'no market'."*

**`loadProviders()`**
1. `guard providers == nil` — runs once per screen.
2. `guard let availability = try? await api.watchProviders(id:, country: AppRegion.current)` → `GET /franchises/{id}/watch-providers?country=XX`. **A throw is swallowed.** *"A failure here is a missing section, never an error state: the page is about the show, not about where to stream it."*
3. `withAnimation(pick(uiGentle)) { providers = availability }` — the section fades in.

### 1.3 The 6-second enrichment re-read

```swift
private func retryEnrichmentIfEmpty() {
    guard let f = fetched, f.looksUnenriched, enrichmentRetry == nil else { return }
    enrichmentRetry = Task {
        try? await Task.sleep(for: .seconds(6))
        guard !Task.isCancelled,
              let again = try? await api.franchise(id: franchiseId, country: AppRegion.current),
              !again.looksUnenriched else { return }
        withAnimation(pick(uiGentle)) { fetched = again }
    }
}
```

`Franchise.looksUnenriched` = `(people?.isEmpty ?? true) && related.isEmpty && videos.isEmpty && featuredVideo == nil`.

Why: *"The catalogue's deep metadata arrives stale-while-revalidate: the first read of a show can return before its people, related titles and trailers exist, and the server fills them in the background. One quiet re-read a few seconds later catches that, so the shelves fade in on this visit instead of the next."* It fires **at most once** per screen (`enrichmentRetry == nil` guard, never reset), and a second read that is *also* unenriched is discarded rather than re-rendered.

### 1.4 Which `Franchise` the screen draws

```swift
private var franchise: Franchise? {
    if let pinned { return pinned }                                     // mark timeline snapshot
    guard let base = appModel.franchise(id: franchiseId) ?? fetched else { return nil }
    return base.grafting(fetched)                                       // no-op if fetched == nil
}
```

Precedence: **pinned snapshot** (frozen during a mark's 650 ms result window) → **live library row grafted with the detail read** → **the detail read alone** (a show not in the library).

`Franchise.grafting(_ fetched:)` — the live LIBRARY copy (fresh progress/status) wins for user state; the DETAIL read wins for enrichment. It returns `self` unchanged if `fetched.id != id`.

Per-part merge, keyed by `mediaId` (a part with no detail twin passes through untouched):

| Field | Rule |
|---|---|
| `episodes` | live if non-empty, else detail's |
| `videos` | live if non-empty, else detail's |
| `images` | live if non-nil, else detail's |

If all three come out identical to the live part's own, the live part is returned unchanged (avoids a needless copy).

Franchise-level merge:

| Field | Rule |
|---|---|
| `images` | live ?? detail |
| `themes` | live if non-empty, else detail |
| `featuredVideo` | live ?? detail |
| `videos` | live if non-empty, else detail |
| `audience` | **detail ?? live** — the market-matched rating always comes from the `?country=` read |
| `people` | detail if live's is nil/empty |
| `related` | detail if live's is empty |
| `continueWatching` | **detail ?? live** — always the fresher pointer |

*"The library payload carries the enrichment too, but it was read at launch — before the server's stale-while-revalidate pass may have run — so a detail read that came back richer wins, field by field."*

### 1.5 Derived flags

| Name | Definition |
|---|---|
| `inLibrary` | `appModel.isInLibrary(franchiseId)` = `libraryIds.contains(id) \|\| pendingAdds.contains(id)` |
| `staleAfterFailure` | `loadError && fetched != nil` — content is on screen but the last refresh failed |
| `now` | `appModel.now` (ms epoch, ticked centrally) |
| `isAX` | `dynamicTypeSize.isAccessibilitySize` |

### 1.6 Art tints — two of them

```swift
.task(id: f.portraitArt)   { tint     = await PaletteCache.shared.resolve(url: f.portraitArt,   maxPixel: 420) }
.task(id: heroArt(f).url)  { heroTint = await PaletteCache.shared.resolve(url: heroArt(f).url,  maxPixel: 420) }
```

`tint` is the **cover's** palette; `heroTint` is the **hero art's**. They differ only when the show has no cover and the hero falls back to the banner. From the source:

> The hero's photograph is the banner, so the colour that continues it below the fold has to come from the banner too — derived from the cover it landed a warm brown under a magenta-and-cyan neon header, i.e. two light sources in one hero. The card and the episode tiles keep the cover's palette: they are the show's identity, not a continuation of this particular photograph.

`PaletteCache.resolve` returns `PaletteCache.fallback` = `#1C1A17` when it cannot resolve. Extraction algorithm (port it directly — AndroidX `Palette` gives different answers): downsample to **32×32** → discard pixels with alpha < 0.8 or OKLab L < 0.08 or > 0.92 → take the highest-population colour with chroma ≥ 0.035 → clamp L to 0.24…0.38 and C to 0.04…0.12 → all-neutral art falls back.

`DetailTint.quiet(_:)` re-conditions a palette colour to be a *ground* under type. In OKLab: chroma clamped to **≤ 0.045**, lightness clamped into **0.40…0.46**, then mixed **20 % toward `surfaceRaised` (#242428)**. Used for `EpisodeList(tint:)` and inside `EpisodeStill`'s own palette task.

---

## 2 · Chrome — the docked title and the two veils

This screen **hides the navigation bar's background** (`.toolbarBackground(.hidden, for: .navigationBar)`) so the hero can bleed under the status bar, and suppresses the system scroll-edge effect (`.chromeScrollEdgeHidden(.top)`). Two veils of its own replace the system edge. Bar style: `.navigationBarTitleDisplayMode(.inline)`, `.toolbarRole(.editor)` (the system back chevron at system size, no title beside it — *"Three hand-built circles in one navigation stack … is three answers to 'how do I go back'."*).

### 2.1 The scroll probe

A `Color.clear` **background** on the scroll content, not `onScrollGeometryChange` — *"`onScrollGeometryChange` never fires on the iOS 27 simulator, which left the bar's veil dead in every capture. The content's top edge in window space is the fact."*

```swift
Color.clear.onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { minY in
    let y = -minY
    scroll.set(y)
    let copyTop = heroHeight - ThemeSpace.x4 - heroCopyHeight     // 16
    let under = y > copyTop - (ThemeMetrics.topSafeInset + 46)
    if under != scrolledUnderBar {
        withAnimation(pick(uiGentle)) { scrolledUnderBar = under }
    }
}
```

**`scroll` is a `ScrollOffset` reference object held in `@State`, never a raw `CGFloat` in view state.** `ScrollOffset.set` quantises through `scrollSample` (clamp −320…240, half-point rounding) and only writes when the value actually changes, and the only view that *reads* `.y` in a body is `DetailVeils`. From CLAUDE.md: *"The raw offset as `@State` re-ran Today's entire body at 60–120 Hz on the first swipe."* On Android the equivalent is a `MutableState` read only inside the veil composable (or better, a `derivedStateOf`/snapshot-flow feeding just that subtree), never a state read in the screen's own composition.

`ScrollOffset` API used here:
- `y` — quantised offset, positive as content scrolls up.
- `veilOpacity` = `clamp((y − 16) / 64, 0, 1)`.

### 2.2 The docked-title threshold — `copyTop − band`, NOT a flat 130 pt

```
copyTop = heroHeight − 16 − heroCopyHeight       // top edge of the hero's copy block
band    = topSafeInset + 46                      // status bar + the floating toolbar's band
scrolledUnderBar = (scrollY > copyTop − band)
```

The flip therefore happens exactly when the **top of the hero's title** reaches the **bottom edge of the toolbar** — not when the picture does, and not at a constant. Source:

> The bar hardens — and docks the title — the moment the hero's COPY reaches the toolbar's bottom edge: Apple TV's handover, the title leaving the picture as it arrives in the bar. At a flat 130 pt the flip came ~80 pt later, so the title slid under the glass capsules half-lit and ghosted through them for the whole of that scroll (captured 3 Sep).

Because `heroCopyHeight` is *measured* (`.onGeometryChange` on the copy VStack), the threshold moves with Dynamic Type automatically. At AX sizes the copy is taller, `copyTop` is smaller, and the bar hardens earlier — which is correct.

Both the boolean flip and the title's opacity animate on `pick(uiGentle)` (easeInOut 0.22), and the flip is guarded (`if under != scrolledUnderBar`) so a scroll frame that does not change it costs nothing.

### 2.3 `DetailVeils`

Mounted as `.overlay(alignment: .top)` on the whole screen, `band = topSafeInset + 46`, `allowsHitTesting(false)`, `.animation(pick(uiGentle), value: hardOn)`.

Exactly one of two layers is mounted at a time — *"a material at opacity 0 is still a backdrop blur"*:

| Condition | Layer |
|---|---|
| `!hardOn && scroll.y > 12` | `ScrollEdgeChrome(side: .top, height: band + 100)` at `opacity = scroll.veilOpacity`, `.transition(.opacity)` — **the soft veil, while ARTWORK is behind the toolbar** |
| `hardOn` | `ScrollEdgeChrome(side: .top, height: band + 28, holdHeight: band)`, `.transition(.opacity)` — **the bar, once CONTENT is behind the toolbar** |
| otherwise | nothing |

Separately, the hero itself carries `HeroTopVeil(band:)` as its own top overlay — that one travels away with the picture.

### 2.4 `ScrollEdgeChrome(side: .top, height:, holdHeight:)`

`hold = clamp(holdHeight / max(height,1), 0, 1)` — the fraction of the band held at full bar opacity.

`bar = reduceTransparency ? 1.0 : 0.74`

**Veil gradient** (top → bottom):

| Stop | Colour |
|---|---|
| 0 | `canvas` @ `bar` |
| `hold` | `canvas` @ `bar` |
| `hold + (1 − hold) × 0.45` | `canvas` @ `bar × 0.45` |
| 1 | `canvas` @ 0 |

**Blur mask** (applied to a `Rectangle().fill(.ultraThinMaterial)`, dropped entirely under Reduce Transparency):

| Stop | Alpha |
|---|---|
| 0 | 1.0 |
| `hold` | 1.0 |
| `hold + (1 − hold) × 0.45` | 0.42 |
| 1 | 0 |

Layer order: material (masked) **under** the veil gradient. `.ignoresSafeArea(edges: .top)`, `allowsHitTesting(false)`, `accessibilityHidden(true)`.

Why 0.74 and not 1.0:

> "Hardened" means `ThemeMetrics.chromeBarOpacity` (0.74) canvas over the full-strength blur, NEVER opaque canvas (only Reduce Transparency, which has no blur, gets the opaque bar): at 1.0 the top ~100 pt of every scrolled screen was a flat #09090B slab ("pure black", 3 Sep) with the material under it painted for nothing.

### 2.5 Toolbar items

```swift
.toolbar {
    if let f = franchise {
        ToolbarItem(placement: .principal) { barTitle(f) }.chromeSharedBackgroundHidden()
    }
    if let f = franchise, inLibrary {
        ToolbarItem(placement: .topBarTrailing) { statusMenu(f) }
        if #available(iOS 26.0, *) { ToolbarSpacer(.fixed, placement: .topBarTrailing) }
        ToolbarItem(placement: .topBarTrailing) { overflowMenu(f) }
    } else if let f = franchise {
        ToolbarItem(placement: .topBarTrailing) { addButton(f) }
    }
}
```

**TWO items, never one `ToolbarItemGroup`** — a group is one glass capsule, and the status pill plus the `···` then drew their own materials *inside* it: *"three materials in one cluster, with a visible seam mid-capsule, an empty stretch of glass around the ellipsis, and a refracted inner pill over bright artwork that reads as a rendering bug."* Neither item carries a background of its own; the toolbar supplies the material.

**`barTitle(f)` — the docked title**

| Property | Value |
|---|---|
| Text | `f.displayTitle` (**shortened**; the full title is the billboard's) |
| Type | `bodyEmphasis` (Outfit SemiBold 17, −0.20), `textPrimary` |
| Lines | 1 |
| Opacity | `scrolledUnderBar ? 1 : 0`, animated `pick(uiGentle)` |
| VoiceOver | `.accessibilityHidden(!scrolledUnderBar)` — *"so the screen does not announce its name twice"* |

`displayTitle` = `title.shelfShortened`:
1. trim whitespace;
2. if it ends in `-` and contains `" -"`, drop from that `" -"` to the end (the `Re:ZERO -Starting Life in Another World-` wrapper);
3. trim any leading/trailing characters in `" -–—:"`;
4. if still > 40 chars, cut at the first of `": "`, `" – "`, `" — "`, `" - "`, `" ("` that occurs at index ≥ 12.

**`addButton(f)`** — shown only when the show is *not* in the library.

| Property | Value |
|---|---|
| Glyph | SF `plus`, `.system(size: 17, weight: .semibold)` |
| Colour | **`interactive`** (not accent) |
| Frame | 44 × 44, `.buttonStyle(.plain)` |
| Action | `appModel.addToLibrary(franchiseId: f.id, title: f.title, isReleasing: f.isReleasing)` |
| VoiceOver | `"Add \(f.title) to Library"` |

*"A GLYPH, not a word … '+ Add' was the last piece of prose in the bar (and this SDK broke it 'Ad / d')."* And: *"`interactive`, not `accent`: this glyph sits directly above the episode list's amber 'Episode 14 next', so one hue must not mean both 'press this' and 'this is what's coming'."*

`addToLibrary` is optimistic (`pendingAdds`), fires `.success`, sets status `.watching` if `isReleasing` else `.planned`, shows an Undo toast `"Added {title} to Watching|Planned"`, and **never raises the notification permission alert**.

**`statusMenu(f)`** — shown only when in library.

Label: `HStack(spacing: 6) { Text(f.effectiveStatus.displayName).type(metadataEmphasis).contentTransition(.opacity); Image("chevron.down").font(.system(size: 9, weight: .semibold)) }`, `foregroundStyle(textPrimary)`, `.frame(minHeight: 44)`. **No local background** — *"a second capsule inside it is the inner pill that reads as a refraction bug over bright artwork."*

Modifier: `.milestone(token: milestoneToken, reduceMotion:)` — see §5.6.
VoiceOver: `"Change status, \(displayName)"`.

Menu contents — `WatchStatus.menuOrder` = `[watching, planned, completed, paused, dropped]`, each `Button { appModel.setStatus(franchiseId:status:) }` with `Label(displayName, systemImage: isCurrent ? "checkmark" : menuGlyph)`:

| Status | Display name | Unselected glyph |
|---|---|---|
| `watching` | **Watching** | `play.circle` |
| `planned` | **Planned** | `clock` |
| `completed` | **Watched** | `checkmark.circle` |
| `paused` | **Paused** | `pause.circle` |
| `dropped` | **Dropped** | `xmark.circle` |

("Completed", "Plan to watch" and "Finished" never appear.) `setStatus` fires `.selection`, writes optimistically, and presents `"Moved to {status}"` with Undo; a failure **rolls back** and records on the SyncBanner.

**`overflowMenu(f)`** — label SF `ellipsis`, `.system(size: 15, weight: .semibold)`, `textPrimary`, 44 × 44. VoiceOver `"More actions"`.

Items, in order, each gated:

| # | Gate | Label | Action |
|---|---|---|---|
| 1 | `currentPart` exists && `!part.isUpcoming` && `behind > 1` && `through > progress+1` where `through = min(progress+5, markTarget)` | `Copy.Action.markThrough(from: progress+1, to: through)` → `"Mark episodes 6⁠–⁠10 watched"` | confirm → batch mark |
| 2 | same part gate && `behind > 0` | `"Mark all episodes as watched"` | confirm → batch mark to `markTarget` |
| 3 | same part gate && `progress > 0` | `"Mark all {N} episodes as unwatched…"` | confirm → reset season |
| 4 | same part gate | `"View episodes"` | `push(.episodes(f.id, part.mediaId, nil))` |
| 5 | `seriesBehind(f) > 0` | `"Mark series as watched"` | confirm → mark every episodic part |
| 6 | active rewatch session | *Divider*, then `"Restart rewatch…"` and `"Cancel rewatch…"` | see §13.4 |
| 7 | `!RewatchStore.sessions(for:).isEmpty` | `"View watch history"` | `push(.history(f.id))` |
| 8 | always | *Divider*, then `RemoveFromLibraryButton` — `role: .destructive`, `Label("Remove from Library", systemImage: "trash")` | `appModel.removeWithUndo(f, reduceMotion:)` |

`behind = max(0, part.markTarget(now) − part.progress)`.
`seriesBehind(f) = Σ over f.episodicPartsInOrder of max(0, markTarget(now) − progress)`.

Item 7's gate is deliberate: *"`RewatchStore` records the first watch implicitly, at the moment a REWATCH starts — so a finished show with no rewatch has no session, and this door led to 'No watch history yet' on a screen whose card, 40 pt above, said 'Watched once'. Two answers to the same question."*

**Copy notes.** `Copy.plural` binds the numeral to its noun with a **non-breaking space (U+00A0)**: `"11 episodes"` is `11\u{00A0}episodes`. `markThrough` welds the range with **word joiners (U+2060)** around an en dash: `"Mark episodes 6\u{2060}–\u{2060}10 watched"` — *"a narrow menu line broke it as 'episodes 1–' / '5', which reads as a typo, not a range."* Trailing ellipses are **U+2026**, apostrophes **U+2019**, separators **U+00B7 (·)**.

---

## 3 · The billboard hero

### 3.1 Geometry

```swift
static let heroFraction: CGFloat = 0.68      // Today's billboard uses 0.72
static let artBand:      CGFloat = 132       // least photograph that must survive above the copy
static let toolbarBand:  CGFloat = 46
static let heroBloomHeight: CGFloat = 220
static let bloomOverlap:    CGFloat = 56

var heroHeight: CGFloat {
    max(ThemeMetrics.windowHeight * 0.68, heroCopyHeight + 132)
}
```

*"Grows with the copy's OVERFLOW, never by a guessed accessibility bump."* On an 852-pt window that is **579.4 pt** at default type; at AX5 the second term takes over.

0.68 rather than Today's 0.72 *"so the state block and its capsule land above the tab bar on the first screen."*

Why a billboard at all, quoted in full because it is the design rationale a port must not undo:

> The previous hero was a 320-pt landscape band with the 112-pt poster floating over its lower edge and an eyebrow on the poster's baseline: a database entry's anatomy (Letterboxd, TMDB), and on this catalogue's art it was the app's worst crop — a 4.75:1 AniList banner `.fill`ed into a 1.2:1 band shows a quarter of itself, which put a forehead under the back button on the flagship title. Apple TV and Netflix open a show on its key art edge to edge with the lockup over it; the cover is within 4 % of this frame's aspect, so the composite path shows it whole and sharp, and the same asset is no longer drawn twice at two scales.

### 3.2 Which art

```swift
func heroArt(_ f: Franchise) -> (url: String?, portrait: Bool) {
    if let cover  = f.portraitArt  { return (cover,  true)  }
    if let banner = f.landscapeArt { return (banner, false) }
    return (nil, true)
}
```

Cover first; banner only when there is no cover at all.

- `Franchise.portraitArt` = `images?.portrait ?? nonEmpty(cover)`
- `Franchise.landscapeArt` = `images?.landscape ?? legacyBanner(banner, cover:)`, where `legacyBanner` returns `nil` when `banner == cover` — *"writers older than the explicit artwork set copied a portrait cover into `banner`; exact URL equality is that copy, and it is a poster, not a banner."*
- `nonEmpty` treats a whitespace-only string as absent.

### 3.3 Layer stack (bottom → top)

`ZStack(alignment: .bottom)`, `.frame(height: heroHeight).frame(maxWidth: .infinity)`, `.animation(uiPoster, value: art.url)`:

1. **Persistent ground** — solid `heroTint ?? tint ?? #1C1A17`. *"so the frame never flashes canvas while the image decodes."*
2. **`ArtHeader(url:height:tint:scrimTop:0,scrimBottom:0,focus:.top,portraitSource:,drift:true)`**, `.id(art.url ?? f.id)`.
3. **`HeroCopyScrim(copyHeight: heroCopyHeight)`**
4. **The copy block** (title + identity line), bottom-leading.
5. `.overlay(alignment: .top)` **`HeroTopVeil(band: topSafeInset + 46)`**
6. `.overlay(alignment: .top)` **the bloom**, `.frame(height: 220 + 56).padding(.top, heroHeight − 56)`
7. `.zoomSource("detail/\(f.id)")` — registered, **consumed by nothing** (the `.zoom` push transition was retired 3 Sep). Android: ignore.

### 3.4 `ArtHeader` internals

`ArtScrim(top: 0, bottom: 0)` is passed — every stop multiplies by 0 so it draws **nothing**. Deliberate: *"Both protections are drawn in POINTS — `HeroTopVeil` over the chrome band, `HeroCopyScrim` sized to the measured copy. A fractional scrim on a 580-pt frame blankets the middle of the picture."*

**`portraitSource == true`** (cover): two image layers.

| Layer | Content mode | maxPixel | Alignment | Treatment |
|---|---|---|---|---|
| Ground | `.fill` | 1024 | `.center` | `.blur(radius: 48, opaque: true)`, then `Color.black.opacity(0.28)` |
| Sharp | `.fit` | **2048** | `.top` (`focus`) | `.scaleEffect(driftScale, anchor: .top)`, `.transition(.opacity)` |

2048 and not 1024 because *"Today's billboard hero draws this layer at ~1770 px tall, and capping the decode below that softened the one sharp asset in the frame. The blurred ground stays at 1024 — it is blurred."*

**`portraitSource == false`** (banner): one layer, `.fill`, maxPixel **1536**, alignment `.top`, with the same drift transform.

`.clipped()` on the frame.

**Drift** (`drift: true`, both Today's and Detail's billboards, nothing else in the app):

```swift
.task(id: drift && !reduceMotion) {
    guard drift, !reduceMotion else { drifting = false; return }
    try? await Task.sleep(for: .milliseconds(80))
    guard !Task.isCancelled else { return }
    withAnimation(.easeInOut(duration: 24).repeatForever(autoreverses: true)) { drifting = true }
}
```

`driftScale = drifting ? 1.07 : 1`, anchor = `.top` (because `focus == .top`). ~7 % over 24 s, eased, reversing. Off under Reduce Motion. The 80 ms delay exists because *"an animation started in the same transaction as the view's own appearance is folded into it and never repeats."* One transform on one layer — **no body re-evaluates for it**.

### 3.5 `HeroTopVeil(band:, ramp: 100)`

`total = band + 100`, `mark = band / total`. Pure black, top → bottom:

| Location | Black alpha |
|---|---|
| 0 | 0.72 |
| `mark × 0.72` | 0.66 |
| `mark` | 0.52 |
| `mark + (1 − mark) × 0.30` | 0.30 |
| `mark + (1 − mark) × 0.62` | 0.12 |
| 1 | 0 |

*"A ramp that holds flat and then falls reads, over bright key art, as a hard-edged plate laid on the picture right where the brand mark (or the back button) is; a veil that can be seen is not protection, it is a smudge."* Its job is to neutralise the band for the clock and the (iOS 26) glass toolbar, whose rim otherwise takes a saturated colour off a bright cover and reads as a focus ring.

### 3.6 `HeroCopyScrim(copyHeight:, lead: 72)`

`h = max(1, copyHeight + 72 + 8)`. Colour is `ThemeColor.canvas`, top → bottom:

| Location | Canvas alpha |
|---|---|
| 0 | 0 |
| `min(0.99, 28.8 / h)` | 0.16 |
| `min(0.99, 50.4 / h)` | 0.44 |
| `min(0.99, 72 / h)` | 0.72 |
| `min(0.995, 128 / h)` | 0.90 |
| 1 | **1.0** |

Stops are placed in **points off the measured copy height, never as fractions of the image** — *"a fixed fraction is a different physical distance at every type size, which is how AX1 came to set a three-line 44-pt title over a face at ~55 % luminance while the same stops were comfortable at default size."* The final full-canvas stop is load-bearing: *"the 3 % of photograph left glowing through at the exact line where the hero meets the canvas rendered as a faint band across the screen — the scrim must LAND, not hover."*

### 3.7 The bloom

Drawn as an **overlay** starting **56 pt inside the photograph** and running 220 pt below it, with `.blendMode(.plusLighter)`, `allowsHitTesting(false)`, `accessibilityHidden(true)`, `.animation(uiPoster, value: heroTint == nil)`.

```
base = heroTint ?? tint ?? #1C1A17
heroIsDark = oklabLightness(heroTint ?? tint) < 0.34      // nil → treated as 0.5
lift = heroIsDark ? 1.8 : 1.0
```

Two gradients in a `ZStack`:

| Gradient | Stops |
|---|---|
| Linear, top → bottom | `base@0` at 0.00 · `base@(0.20 × lift)` at 0.30 · `base@(0.07 × lift)` at 0.70 · `base@0` at 1.00 |
| Radial, centre (0.18, 0.12), startRadius 0, endRadius 300 | `base@(0.16 × lift)` → `.clear` |

Why it starts *inside* the picture and is an overlay rather than a background:

> Ending it where the image ends put the whole colour ramp below the seam — a visible full-width line across the widest part of the hero. And as a `.background` it was occluded by the copy scrim (opaque canvas at the frame's bottom, by design) right up to the seam, then added its light from the first row below it: the same line, measured again on the billboard (2 Sep). As an overlay its ramp runs continuously across the edge; at the overlap's opacities (0 → 0.13) `plusLighter` is invisible on white type.

And why a dark show gets *more*: *"with the photograph sitting at canvas luminance the bloom is the only thing separating identity from background"* (Game of Thrones' Iron Throne is the named case).

`oklabLightness` reads the resolved palette colour's sRGB components and takes `PaletteCache.oklab(r:g:b:).0`. It is measured off the palette colour, **not** off a second decode of the image.

### 3.8 The copy block

`VStack(alignment: .leading, spacing: 0)`, `.shadow(.art)` (black 0.55 / r 12 / y 7 — *"Type laid on a photograph needs a contact shadow the same way art laid on a canvas does"*), `.padding(.horizontal, 16)`, `.padding(.bottom, 16)`, `.frame(maxWidth: .infinity, alignment: .leading)`, and `.onGeometryChange { $0.size.height } → heroCopyHeight`.

**Title** — `Text(f.title)`, the **full** title (the shortened one is the bar's and every row's):

| Property | Default | Accessibility sizes |
|---|---|---|
| Type | `heroTitle` (Outfit Bold 28, −0.55) | `displayXL` (Outfit Bold 34, −0.80) |
| Colour | `textPrimary` | same |
| Lines | 3 | unlimited |
| `minimumScaleFactor` | 0.85 | 0.85 |
| `allowsTightening` | true | true |

*"A scale floor at every size: the hero may never ellipsize the one name the screen exists to show."*

**Identity line** — `identityLine(f)`, `padding(.top, 3)`:

| Property | Default | AX |
|---|---|---|
| Type | `heroMeta` (Outfit Regular 15, −0.05) | same |
| Colour | `textSecondary` | same |
| Lines | 1 | 3 |
| `minimumScaleFactor` | 0.9 | 0.9 |

### 3.9 `identityLine(f)` — "Anime · 2016 · U/A 16+ · Action · Adventure"

```swift
let genres = f.parts.flatMap(\.genres).deduplicatedPreservingOrder.map(\.localizedCapitalized)
var head = [f.kindWord]                                   // "Anime" | "TV"
if let y = premiereYear(f) { head.append(String(y)) }
if let rating = f.contentRatingLabel { head.append(rating) }
let budget = isAX ? Int.max : 46
var tail = Array(genres.prefix(3))
while true {
    let line = (head + tail).joined(separator: " · ")
    if line.count <= budget || tail.isEmpty { return line }
    tail.removeLast()
}
```

- `kindWord` = `"TV"` for `.tmdb`, `"Anime"` for `.anilist`. The app never says "AniList" or "TMDB" to a viewer.
- `contentRatingLabel` = `audience?.contentRating?.rating` if non-empty, else `"18+"` when `audience?.isAdult == true`, else `nil`. The server returns only an **exact** market match; it never substitutes another country's rating.
- The budget is a **character count, not a measurement**, on purpose: *"`minimumScaleFactor` absorbs the last few points, and a `TextRenderer` pass on every identity change is not worth one line of type."*
- The **studio is not on the hero** — *"a studio is a credit, not identity"*, and `"8-Bit"` / `"WIT Studio"` read as genres with a missing separator when they closed the run.

**`premiereYear(f)`** — the year the *work* premiered, specials excluded:

```swift
let real = f.parts.filter { $0.kind != .special }.compactMap(\.year)
return (real.isEmpty ? f.parts.compactMap(\.year) : real).min()
```

> TMDB's season 0 carries the air date of the earliest featurette, which on Game of Thrones is 2010-12-05: a pre-launch promo, five months before the show existed. Taking a plain minimum across every part therefore printed "TV · 2010" on the flagship title. (The server computes this field the same wrong way; this is the client half so the screen is right either way.)

### 3.10 The hero is not a control

The billboard has no tap target of its own on Detail (unlike Today's, which opens the show). Its accessibility surface is just the two `Text`s.

---

## 4 · Screen scaffold, loading, error and stale states

### 4.1 Root

```swift
ZStack {
    ThemeColor.canvas.ignoresSafeArea()
    SkeletonGate(isLoading: franchise == nil && loading && !loadError) {
        detailSkeleton
    } content: {
        if let f = franchise { screen(f) }
        else if loadError {
            EmptyState(SyncCenter.shared.isOnline ? .serverNoCache : .offlineNoData, prominence: .major) {
                Task { await load() }
            }
            .padding(.horizontal, 16)
        }
    }
}
```

**No `ArtBackdrop` behind the header** — *"the hero's `ArtHeader` IS this screen's ambient art, and it hands over to the canvas through `ArtScrim`. Running a blurred wash behind the header as well put a 14-level luminance step straight across the screen at the header's bottom edge — a horizontal seam, measured, in the first capture."*

### 4.2 `SkeletonGate` timing (shared, applies verbatim)

| Phase | Behaviour |
|---|---|
| 0 – 240 ms of loading | **Nothing drawn** (a `Color.clear` of height 0). *"a fast response should never flash a skeleton"* |
| 240 ms → | Skeleton appears; a monotonic `ContinuousClock` stamp is taken |
| +800 ms | `slow` flips on `pick(uiGentle)` (state only; this screen draws nothing extra for it) |
| loading ends | Skeleton stays for a **minimum 320 ms** from when it appeared, then swaps |
| Swap | `.animation(uiCrossfade /* = uiReduced, easeOut 0.12 */)` on both `visible` and `isLoading` |

Skeleton breath: opacity oscillates **0.88 ↔ 1.0** on `easeInOut(1.4).repeatForever(autoreverses: true)`. Reduce Motion → flat **0.92**, no animation. VoiceOver: the skeleton is one element labelled `"Loading"`.

### 4.3 `detailSkeleton` — the shape that arrives

`VStack(alignment: .leading, spacing: 30)`, `.padding(.horizontal, 16)`, `.frame(maxWidth/.maxHeight: .infinity, alignment: .topLeading)`, `.ignoresSafeArea(edges: .top)`:

1. **Billboard** — `ZStack(alignment: .bottomLeading)`:
   - ground = `tint ?? TodayView.rememberedTint ?? #432D21`. `rememberedTint` is the previous hero's palette RGB persisted in `UserDefaults` under `"today.heroTint"` — *"the loading frame is the first thing a returning user sees, and it has no artwork yet by definition, so it was a black rectangle."*
   - `VStack(spacing: 8) { SkeletonLine(width: 250, height: 26); SkeletonLine(width: 176, height: 13) }`, `.padding(.horizontal, 16).padding(.bottom, 16)`
   - `.frame(height: heroHeight).padding(.horizontal, -16)` (bleeds past the gutter)
2. `SkeletonCard(height: 190) {}` — a `.plate`-surfaced rounded rect at radius 22
3. `VStack(spacing: 8) { SkeletonLine(height: 12); SkeletonLine(height: 12); SkeletonLine(width: 210, height: 12) }` — the synopsis
4. `VStack(spacing: 0) { 3 × SkeletonRow(poster: 60×90, lines: [150, 104], posterRadius: 10, spacing: 14) }`

`SkeletonLine` = a `#F4F1EC @ 0.11` rounded rect, radius 6. **Static — no shimmer** (the spec explicitly refuses shimmer). `SkeletonRow` scales its height with Dynamic Type (`@ScaledMetric` on `rowStandard` = 88) so the swap does not jump at accessibility sizes.

### 4.4 Whole-screen failure

Only when `franchise == nil && loadError` (no cached row and no fetch). `EmptyState` is `ContentUnavailableView`'s anatomy on the canvas — **no plate, no glyph tile, no bloom**:

- 44-pt SF symbol in `textTertiary`, `.padding(.bottom, 16)`
- Title `showTitleL`, `textPrimary`, centred, ≤ 3 lines (unlimited at AX)
- Supporting `callout` (Outfit Regular 16), `textSecondary`, centred, `.padding(.top, 8)`
- One hugging button, `.padding(.top, 20)`; because the label is `"Try again"` (`isRecovery == true`) it is the **quiet** `SecondaryButtonStyle2` capsule, not the amber one
- `.frame(maxWidth: 300)`, `.transition(.opacity)` — *"an empty state that scales in reads as a celebration of having nothing"*

Chosen by `SyncCenter.shared.isOnline` (NWPathMonitor), **never guessed from the error**:

| State | Symbol | Title | Supporting | Button |
|---|---|---|---|---|
| online → `.serverNoCache` | `exclamationmark.circle` | `Couldn’t load your library` | `Something went wrong. Try again in a moment.` | `Try again` |
| offline → `.offlineNoData` | `wifi.slash` | `You’re offline` | `Connect to the internet to load your library.` | `Try again` |

State copy never says "server". Apostrophes are U+2019.

### 4.5 Stale-after-failure footnote

When `loadError && fetched != nil` (content is on screen, the refresh failed), the **first** item in the content column is an `InlineNotice`:

- Layout: `HStack(.firstTextBaseline, spacing: 8)` at default sizes, **`VStack(.leading, spacing: 4)` at accessibility sizes**
- `Image("wifi.exclamationmark")` `.system(size: 12, weight: .semibold)`, `textTertiary`, 6 pt before the text
- `Text("Episodes couldn’t refresh")` — `metadata`, `textSecondary`
- `Button("Retry")` in `InlineLinkButtonStyle`, `.padding(.vertical, -12).padding(.leading, isAX ? -12 : -4)`, hint `"Tries the request again"` → `load(force: true)`
- `.frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)`, `.transition(.opacity)`

*"A background refresh that failed is a footnote (Mail's 'Cannot connect' at the foot of the list), never a warning."* `loadError` is flipped inside `withAnimation` so the footnote fades in rather than shoving content down.

`InlineLinkButtonStyle`: `listAction` type, `interactive` ink, `.padding(.vertical, 14).padding(.horizontal, 12).frame(minHeight: 44)` then `.contentShape(Rectangle())` — the 44-pt target is padding, so the caller can pull it back optically with negative padding without shrinking the hit area. Pressed → opacity 0.55 on `pick(uiPress)`.

### 4.6 Content column

```swift
ScrollView {
  VStack(alignment: .leading, spacing: 0) {
    hero(f)
    VStack(alignment: .leading, spacing: 30) {
      if staleAfterFailure { InlineNotice(...) }
      if inLibrary, let state = nextUpState(f) {
        VStack(alignment: .leading, spacing: 10) {
          ZStack(alignment: .top) { nextUpCard(f, state: state).id(state.identity).transition(.handoff(reduceMotion:)) }
            .frame(maxWidth: .infinity, alignment: .top)
          historyRow(f)
        }
      }
      about(f)
      episodesSection(f)
      extrasShelf(f)
      trailersShelf(f)
      peopleShelf(f)
      relatedShelf(f)
      whereToWatch(f)
    }
    .padding(.horizontal, 16)
    .padding(.top, 26)                       // heroClearance
    .animation(pick(uiSettle), value: nextUpState(f)?.identity)
  }
  .background { /* scroll probe, §2.1 */ }
}
.contentMargins(.bottom, DetailMetrics.bottomClearance, for: .scrollContent)
.scrollIndicators(.hidden)
.ignoresSafeArea(edges: .top)
```

Every section is `@ViewBuilder`-gated and emits **nothing** when it has no content, so `sectionGap` never doubles.

The bottom clearance is a **scroll-content margin, not padding inside the stack**:

> Padding inside the stack does nothing at all when the content is shorter than the viewport, which is exactly the case in which the last line came to rest inside the veil — the synopsis measured 4.39 → 1.04:1 over four lines.

It widens by 72 pt while a sync failure is pending because the floating `SyncBanner` is drawn **over** content rather than inset from it.

The whole screen is wrapped in `ScrollViewReader` purely to give the DEBUG capture driver a `proxy` (§16).

### 4.7 The `focus` deep link — consumed exactly once

```swift
.onAppear {
    guard let focus, !focusConsumed else { return }
    focusConsumed = true
    push(.episodes(franchiseId: franchiseId, mediaId: focus.mediaId, focusEpisode: focus.episode))
}
```

> Once. `onAppear` fires again when the episode list pops back to here, and the push re-fired with it — every Schedule-routed Detail was a screen you could not return to.

---

## 5 · The state block (Next up card)

Drawn only when `inLibrary` **and** `nextUpState(f) != nil`. It is **de-boxed** — it sits directly on the canvas, no plate, no container, no artwork thumbnail:

> DE-BOXED (user, 30 Aug: "extremely cheap… not Apple Music premium"). The block sat in an art-tinted plate with a 96×54 thumb and form rows — a home-screen widget directly under a cinematic hero … Apple Music sets its primary actions straight on the page under the art; Today's hero already speaks that grammar (eyebrow → fact → amber capsule, no container). This is the same anatomy, on the canvas.

### 5.1 The `NextUp` value

```swift
struct NextUp: Equatable {
    enum Kind { case actionable, backlog, caughtUp, seasonComplete, seriesComplete, waiting }
    let kind: Kind
    let part: FranchisePart?
    let eyebrow: String          // the STATE, staged in the capsule
    var dot: Bool = false        // amber dot — a fresh, actionable episode only
    let line1: String            // the FACT
    let line2: String?
    let line3: String?
    let episode: Int?
    let behind: Int
    var identity: String { "\(kind)/\(part?.mediaId ?? 0)/\(episode ?? 0)" }
    static func == (a, b) -> Bool { a.identity == b.identity && a.line2 == b.line2 }
}
```

`identity` drives the `.id()` swap and the `pick(uiSettle)` animation trigger. Equality deliberately also compares `line2` so a changed support line re-renders without a full handoff.

### 5.2 `nextUpState(f)` — the full decision tree

```
1. if f.isSeriesComplete                        → completeState(f)                       [.seriesComplete]
2. if f.currentPart == nil:
     a. if let up = f.parts.first(where: \.isUpcoming)                                   [.waiting]
     b. else if !f.episodicPartsInOrder.isEmpty && all are .isComplete
                                                → completeState(f)                       [.seriesComplete]
     c. else                                    → nil  (no block at all)
3. let part = f.currentPart
4. if part.isUpcoming                                                                    [.waiting]
5. target = part.markTarget(now); behind = max(0, target − part.progress)
6. if behind == 0:
     a. if part.isComplete && !part.isReleasing                                          [.seasonComplete]
     b. else                                                                             [.caughtUp]
7. episode = part.progress + 1; context = f.watchContext(part:episode:)
8. if behind > 1                                                                         [.backlog]
9. else                                                                                  [.actionable]
```

Per-kind content:

| Kind | eyebrow | dot | line1 | line2 | line3 | episode / behind |
|---|---|---|---|---|---|---|
| `.waiting` | `"Upcoming"` | – | `part.canonicalLabel` (case 2a: `canonicalLabel` or, if empty, `part.title`) | `announcedDateLabel.map { "Premieres \($0)" }` else `"No date announced"` | – | nil / 0 |
| `.seasonComplete` | `"Complete"` | – | `"{label} complete"` (or bare `"Complete"` when the label is empty) | `"{label} · {watched} of {max(totalEpisodes, progress)} watched"` | next upcoming episodic part → `"{label} returns tomorrow"` (`TemporalCopy.returns` with its first letter lower-cased) | nil / 0 |
| `.caughtUp` | `"Caught up"` | – | `f.watchContext(part:, episode: part.nextEpisodeNumber ?? progress+1)` | `f.nextAiring(now).map { TemporalCopy.airs(...) }` else `"No date announced"` | – | nil / 0 |
| `.backlog` | `part.isReleasing ? "{N} episodes behind" : "{N} episodes left"` | – | `context` | `newEpisodeLine(f)` | – | `progress+1` / `behind` |
| `.actionable` | `part.lastAired(now, anchor: f.timeAnchor).map { TemporalCopy.aired(...) }` else `"New episode"` | **true** | `context` | `newEpisodeLine(f)` | – | `progress+1` / 1 |
| `.seriesComplete` | `"Complete"` | – | `Copy.Progress.watchedTimes(max(1, completedCount))` | see §5.3 | see §5.3 | nil / 0 |

Two design notes quoted:

> The STATE goes to the eyebrow and the EPISODE is the fact (user, 30 Aug): a show airing tonight led with a 22-pt "Caught up" while "Today at 8:30 PM" — the thing the person opened the show for — hid in the support line.

> [`.actionable`] No third line. "Caught up after this episode" restated what the eyebrow's single aired-date and the one-episode CTA already say; the capsule is the sentence.

`newEpisodeLine(f)`:
```swift
guard f.tracksAirings, let at = f.nextAiring(now: now) else { return nil }
return Copy.Progress.newEpisode(when: TemporalCopy.airs(at: at, now: now, source: f.source))
```
`Copy.Progress.newEpisode(when:)` lower-cases the first letter of `when` when it starts with `"Today"`, `"Tomorrow"`, `"Airs"` or `"In "` → **"New episode Friday at 7:30 PM"**, **"New episode today at 6:30 PM"**, **"New episode airs in 27 min"**. `"New"`, not `"next"`: *"on a show nine episodes behind, 'next episode' is the one YOU watch next and the reader would take the day for its air date."*

`tracksAirings` = `effectiveStatus != .planned` — a `planned` show gets no cadence line.

### 5.3 `completeState(f)`

```swift
let summary = RewatchStore.shared.summary(for: f.id)
let last  = summary.lastCompletedAt.flatMap { $0 > 0 ? "Last finished \(TemporalCopy.dateWord($0, now: now, anchor: .local))" : nil }
let scale = { let e = f.episodicPartsInOrder.reduce(0) { $0 + max($1.totalEpisodes, $1.progress) }
              return e > 0 ? Copy.episodes(e) : nil }()          // "95 episodes"
let ahead = {
    guard let up = f.upcoming, up.isFutureInstallment, !up.hasArrived(now: now) else { return nil }
    let fact = ReturnFact.of(f, appModel: appModel).text
    if up.isRumored { return fact }                              // "Season 3 rumored"
    guard let next = up.next, !next.isEmpty else { return fact }
    return "\(next) · \(fact)"                                   // "Season 3 · Returns Oct 2026"
}()
let lines = [ahead, last, scale].compactMap { $0 }
line1 = Copy.Progress.watchedTimes(max(1, summary.completedCount))
line2 = lines.first
line3 = lines.count > 1 ? lines[1] : nil                          // the third is dropped
```

`watchedTimes`: `< 1` → `"Not watched yet"` · 1 → `"Watched once"` · 2 → `"Watched twice"` · else `"Watched {n} times"`.

Why the headline is the state and not the name:

> The headline used to be "You've finished Attack on Titan" at 22 pt, 180 pt below "Attack on Titan" at 28 pt: the show's name twice at near-hero weight in one viewport, while the two facts the card exists to deliver — how many times, and when — sat under it in tertiary grey. A card headlines its STATE; the identity is the hero's job and the hero already did it.

`ahead` exists so *"this page cannot say COMPLETE while the Library's shelf says 'Returns Oct 2026' about the same show — and a rumour is called one."* `FranchiseUpcoming.isRumored` = `status == "rumored"`; `hasArrived(now:)` is true once a **day-precision** window is strictly behind today in UTC.

`scale` exists because *"a show finished before the app ever saw it has no recorded date. The card still states what was watched rather than leaving the fact column empty."*

### 5.4 Layout

`VStack(alignment: .leading, spacing: 10)`, `.frame(maxWidth: .infinity, alignment: .leading)`:

1. **`OverArtLabel`** — text = `activeSession.map { "\($0.title) · \(eyebrow)" } ?? eyebrow` (an active rewatch prefixes its ordinal name, e.g. `"Second watch · 3 episodes behind"`), `dot: state.dot`.
   Anatomy: `HStack(spacing: 6)`; a **5 pt** accent circle when `dot`; `Text` in `sectionLabel` (SF caption2 semibold, tracking +1.0) **uppercased**; `foregroundStyle(textPrimary)`; `.padding(.horizontal, 10)`; `.frame(height: 24)`; `.background(scrimStrong, in: Capsule())`; `.overlay(Capsule().strokeBorder(hairline, lineWidth: 1))`.
2. **`HStack(alignment: .top, spacing: 12)`** — `factBlock(state)`, `Spacer(minLength: 0)`, and (default sizes only) the reveal toggle.
3. **The CTA**, when `part != nil && episode != nil && (kind == .actionable || .backlog)`, `.padding(.top, 8)`.
4. **`Button("Start rewatch")`** in `PrimaryButtonStyle2`, when `kind == .seriesComplete && activeSession == nil`, `.padding(.top, 4)`, `.transition(.opacity)`.
5. **The reveal toggle again**, at accessibility sizes only — *"at AX sizes the reveal control follows the action rather than being pushed off the trailing edge of a row that is now a column."*

Modifiers: `.seasonCompleteSweep(token: kind == .seasonComplete ? sweepToken : nil, reduceMotion:)` and the Start-rewatch `.sheet` (`presentationDetents([.large])`, drag indicator visible).

**`factBlock`** — `VStack(alignment: .leading, spacing: 3)`:

| Line | Type | Colour | Lines |
|---|---|---|---|
| `line1` | `showTitleL` (Outfit SemiBold 22) | `textPrimary` | 2 |
| `secondLine(state)` | `metadata` | `textSecondary` | 2 |
| `line3` | `metadata` | `textTertiary` | 2 |

*"The load-bearing support ('9 episodes behind', 'Aired 26 Aug') reads; only a third line stays tertiary."* Explicitly **no `.contentTransition(.numericText())`** here: it sat inside the very view that `.id(state.identity)` replaces on every mark, so *"the roll was swapped out from under itself. Two mechanisms for one change is a smear either way; the handoff is the one that survives."*

**`secondLine(state)`** — for `.actionable` only, the revealed episode title is appended:
```swift
guard state.kind == .actionable, let part = state.part, let ep = state.episode else { return state.line2 }
let title = revealed.contains(ep) ? EpisodeCopy.title(part.episodes.first { $0.number == ep }?.title, franchise: franchiseTitle) : nil
return [state.line2, title].compactMap { $0 }.joined(separator: " · ")
```

There is deliberately **no** "Title hidden to avoid spoilers" caption: *"the control and the sentence saying the same thing 100 pt apart, and the sentence advertising that there is a spoiler to be had. The control is the statement."*

### 5.5 The reveal toggle

Shown when `canReveal(part, episode)` = the part has that episode **and** `EpisodeCopy.title(e.title, franchise:)` returns non-nil. *"Only a REAL title can be revealed. The control used to appear whenever the catalogue held any string at all, including 'Episode 19' — so tapping it replaced the fact line with the same words the fact line already carried."*

It is a real `Toggle` (`.toggleStyle(.button)`, `.buttonStyle(.plain)`, `.fixedSize()`) — *"a `Toggle` is the control iOS publishes with a switch trait, a spoken On/Off value and a legible pressed state."*

| Property | Value |
|---|---|
| Glyph | `revealed ? "eye.slash" : "eye"`, `.system(size: 11, weight: .semibold)` |
| Label | `revealed ? "Hide episode title" : "Reveal episode title"`, type `listAction` |
| Colour | **`textTertiary`** — *"a utility, quieter than the eyebrow it shares a row with"* |
| Padding | `.vertical 8`, `.leading 12`, then `.contentShape(Rectangle())` |
| Animation | `withAnimation(pick(uiMicro))` on insert/remove from `revealed: Set<Int>` |

The word is "episode title", not "title": *"the word 'title' alone parses as the SHOW's title in a TV app."*

### 5.6 The CTA — `MarkSplitButton`

```swift
MarkSplitButton(episode: committed ? (committedEpisode ?? episode) : episode,
                committed: committedEpisode != nil && pinned != nil,
                behind: state.behind,
                title: f.title,
                onMark:        { mark(f, part: part) },
                onMarkThrough: { promptBatchMark(f, part: part, through: $0) },
                onMarkAll:     { promptBatchMark(f, part: part, through: part.markTarget(now: now)) })
```

One amber capsule containing **two 44-pt targets separated by a 1 × 24 pt hairline**, `showsMenu = behind > 1`.

| Region | Content |
|---|---|
| Left (primary) | `DrawnCheck(on: committed, size: 14, tint: accent)` — mounted **unconditionally**, `.padding(.trailing, 8)`, `.frame(width: committed ? nil : 0, alignment: .leading).clipped()`; then the label |
| Divider | `Rectangle().fill(onAccent.opacity(0.18)).frame(width: 1, height: 24)` — only when `showsMenu` |
| Right (menu) | `Image("chevron.down")` `.system(size: 12, weight: .semibold)`, `onAccent`, `.frame(width: 46, height: 48)` |

Label text: `committed ? "Episode {n} watched" : "Mark as watched"`. Type `button` (Outfit SemiBold 16), **1 line**, `minimumScaleFactor 0.78`, `allowsTightening`, `.contentTransition(.opacity)`.

- Not `"Mark episode 12 watched"`: *"the hero and Detail's block now state exactly ONE episode directly above this capsule, so the number the label used to repeat is no longer disambiguating anything. VoiceOver still hears the episode."*
- Not `.contentTransition(.interpolate)`: it *"printed 'Mark as watched' and 'Episode 19 watched' superimposed as an unreadable smear, twice per mark. Two different sentences crossfade; they do not interpolate."*
- The check is mounted unconditionally because *"a conditional insert inside an `.animation` container gave the check an implicit opacity transition on top of its own left-to-right mask… The mask IS the animation; nothing else may touch this glyph's opacity."*

Primary half: `.foregroundStyle(committed ? accent : onAccent)`, `.padding(.horizontal, 20)`, `.frame(maxWidth: .infinity, minHeight: 48)`, `SplitHalfStyle` (pressed → `accentPressed` behind that half only), `.allowsHitTesting(!committed)`.

Capsule: `.background(committed ? accent.opacity(0.18) : accent)`, `.clipShape(Capsule())`, `.overlay(Capsule().strokeBorder(LinearGradient([controlSheen, .clear], .top → .center), lineWidth: 1))`, `.animation(pick(uiMicro), value: committed)`.

Menu (long-press-free, a real target): a `Section(title)` header naming the show, then
- `"Mark episodes {episode}⁠–⁠{through} watched"` where `through = min(episode + 4, episode + behind − 1)`, shown only when `through > episode`;
- `"Mark all {behind} episodes as watched"`.

*"A Section header is the one Menu element that names without acting"* — with two number-carrying commands floating free the reader had to reconstruct whose episodes "2–5" were.

**`DrawnCheck`** — the app's signature motion. An SF `checkmark` at the given size, `.bold`, masked left-to-right by a `Rectangle` of width `geo.width × progress`. On `on == true`: `withAnimation(uiMicro) { progress = 1 }`; Reduce Motion → `progress = 1` instantly, no animation. On `on == false`: `progress = 0`. `accessibilityHidden(true)`.

VoiceOver on the primary half: `committed ? "Episode {n} watched" : "Mark episode {n} watched, {title}"`; `.accessibilityRemoveTraits(.isButton)` while committed. The chevron half is labelled `"More ways to mark"` and `accessibilityHidden(committed)`.

### 5.7 The mark timeline

```swift
private func mark(_ f: Franchise, part: FranchisePart) {
    guard committedEpisode == nil else { return }
    let completes = part.progress + 1 >= part.markTarget(now: now) && !part.isReleasing && part.totalEpisodes > 0
    let snapshot = f
    guard let undo = appModel.markNext(franchiseId: f.id, mediaId: part.mediaId,
                                       haptic: completes ? .success : .commitLight) else { return }
    if completes {
        sweepToken = UUID()
        let others = f.episodicPartsInOrder.filter { $0.mediaId != part.mediaId }
        let seriesDone = others.allSatisfy(\.isComplete) && !f.parts.contains { $0.isReleasing || $0.isUpcoming }
        if seriesDone {
            milestoneToken = UUID()
            if let active = RewatchStore.shared.activeSession(for: f.id) { RewatchStore.shared.complete(active.id, at: now) }
            appModel.setStatus(franchiseId: f.id, status: .completed, haptic: false, present: false)
        }
    }
    pinned = snapshot
    pendingUndo = undo
    withAnimation(pick(uiMicro)) { committedEpisode = undo.episode }
    Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(650))
        withAnimation(pick(uiSettle)) { pinned = nil; committedEpisode = nil }
        completion: { if let u = pendingUndo { appModel.presentUndo(u); pendingUndo = nil } }
    }
}
```

Sequence on Android:

1. Re-entrancy guard.
2. One haptic — `.success` if this mark completes the season, else `.commitLight`.
3. `markNext` writes optimistically (`progress + 1`, clamped to `progressCeiling`) and returns an `UndoState`. **A progress write never rolls back**; a failure goes to `SyncCenter` and the SyncBanner.
4. `pinned` freezes the pre-mark `Franchise` so the block keeps showing the episode that was just marked for the result window.
5. `committedEpisode` set on `uiMicro` → the capsule flips to `"Episode N watched"` at `accent @ 0.18` with the check drawing in.
6. **650 ms**, then `pinned`/`committedEpisode` clear on `uiSettle` — the `.id(identity)` change fires the asymmetric handoff.
7. **On the animation's completion**, the Undo toast is presented (`"{title} · Episode N watched" · Undo`, 6 s).

The swap happens in a `ZStack`, **out of the flow layout**:

> An `.id()` swap with a crossfade keeps BOTH cards in a VStack's layout for the whole 460 ms, so the block was momentarily two cards tall and About / Seasons & movies / the history row all shoved down a card height and lurched back — on every mark made from this screen. In a ZStack the outgoing and incoming card occupy the same slot.

There is **no `handoffGround`**: *"the block sits on the CANVAS, so there is no card object for the canvas to flash through between — the asymmetric handoff alone carries the swap."*

### 5.8 Milestone motion

**`seasonCompleteSweep(token:)`** — applied to the whole card, `overlay(alignment: .bottomLeading)`: a 1-pt rectangle filled `LinearGradient([accent, accent@0], .leading → .trailing)`, width `geo.width × 0.64 × progress`, offset `y: geo.height + 3`. On a new token: `progress 0 → 1` on `uiSweep` (0.52 s); Reduce Motion → instantly 1. **No haptic of its own** — the transaction's single `.success` is the confirmation.

**`milestone(token:)`** — applied to the *status chip* in the toolbar: `scale = 0.94`, then `withAnimation(uiMilestone) { scale = 1 }`. Reduce Motion → no animation.

Both claim through **`SeasonSweepLedger`**, a process-scoped ring buffer of the last **32** UUIDs. `claim(token)` returns `true` exactly once; every later call snaps to done. This cannot be `@State`:

> `@State` dies with the view, and the case this exists for is precisely the view being re-created while the milestone is still true. … a card scrolled off and back, a tab switch or a recycled row RE-CREATES this modifier with `progress` back at 0 and `initial: true` firing again, which would replay the whole 520-ms draw for a milestone the user already saw.

`SeasonSweepLedger.reset()` is called on sign-out.

### 5.9 History row

Under the card, inside the same 10-pt-spaced group, when `RewatchStore.sessions(for: f.id)` is non-empty:

`GroupedList { GroupedRow(...) }` — a `.plate`-surfaced (white @ 0.055 lift, radius 16, **no border**) container with one row:

| Property | Value |
|---|---|
| `symbol` | `clock.arrow.circlepath`, `.system(size: 15, weight: .medium)`, `textPrimary` |
| `symbolTint` | **`.clear`** — *"the glyph sits directly on the plate. A filled 28-pt tile inside a plate is a second container around a symbol, and tiles are for rows that carry ART."* |
| `title` | `"View watch history"`, type `body`, `textPrimary` |
| `subtitle` | `Copy.episodesWatched(Σ sessions.episodes)` → **`"50 episodes watched"`**, `metadata`, `textSecondary` |
| `trailing` | `.chevron(nil)` — `chevron.forward` 13 semibold `textTertiary` |
| `separator` | false |
| Height | `minHeight: 56`, `.padding(.leading, 14).padding(.trailing, 16)` |
| Action | `push(.history(franchiseId: f.id))` |

The subtitle is **predicated** on purpose: *"'95 episodes' (the work) and '50 episodes' (what the user watched) sat two taps apart in the same noun phrase, so within one show the same words meant two different quantities."*

---

## 6 · About — synopsis and themes

Drawn only when a synopsis exists. The source is **the first part with a non-empty synopsis**, not the franchise's own field:

```swift
let synopsis = Formatting.stripHtml(f.parts.first { !(($0.synopsis ?? "").isEmpty) }?.synopsis)
```

`stripHtml`: remove `<[^>]+>`, decode HTML entities (numeric forms plus `&lt; &gt; &quot; &apos; &nbsp; &mdash; &ndash;`, with `&amp;` decoded **last** so `&amp;lt;` yields `&lt;`), collapse `\s+` to a single space, trim.

There is **no "ABOUT" label**: *"Three stacked blocks at three weights were saying one thing; a synopsis under a hero does not need to be announced."*

`VStack(alignment: .leading, spacing: 0)`:

| Element | Spec |
|---|---|
| Synopsis `Text` | type **`prose`** (SF subheadline, **not** Outfit), `.lineSpacing(5)`, `textSecondary`, `.lineLimit(synopsisExpanded ? nil : 3)`, `.fixedSize(horizontal: false, vertical: true)` |
| Toggle | `Button(synopsisExpanded ? "Read less" : "Read more")` in `InlineLinkButtonStyle`, `.padding(.leading, -12).padding(.vertical, -4)`, `withAnimation(pick(uiSnappy))` |
| Themes | see below, `.padding(.top, 8)` |

Why `prose` and why SF: *"17-pt default-leading grey read as an unstyled default and out-sized the hero's own meta line… a synopsis is quoted CONTENT, not the app's voice, and SF reads better than a geometric sans over a full paragraph."* Three lines, not four: *"Apple TV shows two and a MORE."*

The negative padding cancels `InlineLinkButtonStyle`'s own 12/14-pt padding so the word starts on the gutter while the 44-pt target survives.

**Themes line** — `f.themesBeyondGenres.prefix(4)`, `.map(\.localizedCapitalized)`, joined with `" · "`, type `metadata`, `textTertiary`, **1 line**. `themesBeyondGenres` = `themes` minus (case-insensitively) everything already in `f.genres + parts.flatMap(\.genres)` — *"the catalogue's themes for an anime often ARE its genres, and a fact printed twice on one screen is a defect."* Netflix's "This show is: …", never a plate of chips.

---

## 7 · Episodes — the season picker and the six-row window

> **Episodes are ON the show page** (Apple TV, Netflix). The show page used to list all eleven parts as database rows and push a second screen for the episodes, so the thing a viewer opens a show for — which episode is next — was never on the page. **There is no seasons row list any more.**

### 7.1 Which season

```swift
func focusSeason(_ f: Franchise) -> FranchisePart? {
    let seasons = f.episodicPartsInOrder
    if let id = selectedSeasonId, let p = seasons.first(where: { $0.mediaId == id }) { return p }
    return f.currentPart.flatMap { c in seasons.first { $0.mediaId == c.mediaId } } ?? seasons.last
}
```

The picker's choice → the part the screen is about (airing, resuming, or the earliest unfinished) → the last season.

`episodicPartsInOrder` = parts whose `kind ∈ {season, ona, ova}`, sorted ascending by **`sequence`**. **`sequence` never displays** — it counts a franchise's members, which is not the number the world uses for a season.

`currentPart` = `releasingPart` → `resumePart` → first non-complete episodic part.
- `releasingPart`: among `parts.filter(\.isReleasing)`, prefer the one with the soonest `nextAiringAt`; otherwise the one with the greatest `lastAiredAt`.
- `resumePart`: the first part mid-way through (`0 < progress < availableEpisodes`); else the first unstarted part *after* the highest-sequence completed one; else the earliest part with anything left.

### 7.2 `episodesHeader` — "Season 4 ⌃⌄"

`HStack(alignment: .firstTextBaseline, spacing: 8)`, `.zIndex(1)` (so the negatively-padded 44-pt target paints and hit-tests **above** its siblings).

**When `seasons.count > 1`** — the title *is* the picker:

```
Menu {
    ForEach(seasons) { season in
        Button { withAnimation(pick(uiGentle)) { selectedSeasonId = season.mediaId } } label: {
            season.mediaId == part.mediaId ? Label(seasonLabel(season), systemImage: "checkmark")
                                           : Text(seasonLabel(season))
        }
    }
} label: {
    HStack(spacing: 6) {
        Text(seasonLabel(part)).type(sectionTitle).foregroundStyle(textPrimary).lineLimit(1).minimumScaleFactor(0.85)
        Image("chevron.up.chevron.down").font(.system(size: 13, weight: .semibold)).foregroundStyle(textTertiary)
    }
    .padding(.vertical, 10).contentShape(Rectangle())
}
.buttonStyle(SectionHeaderPressStyle())      // padding 10 + minHeight 44 + opacity 0.55 pressed on uiPress
.padding(.vertical, -10)
.accessibilityLabel("Season, \(seasonLabel(part))")
.accessibilityHint("Chooses another season")
.accessibilityAddTraits(.isHeader)
```

*"Detail's primary navigation control had no pressed state at all."* The `.padding(.vertical, -10)` keeps the header's **layout** height at the title's own while the target stays 44 pt.

**When there is one season**: a plain `Text` in `sectionTitle`, `textPrimary`, 1 line, header trait, no picker.

**`seasonLabel(part)`** = `canonicalLabel` if non-empty → else `part.title` if non-empty → else **`"Episodes"`**.
`canonicalLabel` is the source's own label ("Season 4", "Final Season", "Part 2"), trimmed. **Never derived from `sequence`**; empty string when the source gave none — *"a fabricated 'Season 1' is worse than nothing."*

**Trailing count**, after `Spacer(minLength: 8)`:

```swift
let total = max(part.totalEpisodes, part.airedEpisodes)      // NOTE: not EpisodeList.count
if total > 0 {
    Text("\(min(part.progress, total)) of \(total)")
        .type(metadata).foregroundStyle(textTertiary).monospacedDigit()
        .accessibilityLabel(Copy.Progress.watchedOf(min(part.progress, total), total))   // "11 of 24 watched"
}
```

The numeral pair replaces the words: *"where the old row list spelt '11 of 24 watched'."* The spoken label restores them.

⚠️ **Port faithfully:** the header's `total` (`max(totalEpisodes, airedEpisodes)`) and the list's `total` (`EpisodeList.count`) are computed differently and can disagree — the header can read "11 of 24" while the list draws 25 rows (a user marked past the catalogue's count). This is the shipped behaviour.

### 7.3 The window

```swift
static func episodeWindow(progress: Int, total: Int) -> ClosedRange<Int> {
    let n = max(1, total)
    let start = min(max(1, progress), max(1, n - 5))
    return start...min(n, start + 5)
}
```

**Six rows**: the last one watched for context, the next, and what follows. A finished season shows its tail; an unstarted one its head.

| progress | total | window |
|---|---|---|
| 0 | 24 | 1…6 |
| 11 | 24 | 11…16 |
| 24 | 24 | 19…24 |
| 0 | 3 | 1…3 |

### 7.4 Section body

```swift
VStack(alignment: .leading, spacing: 10) {
    episodesHeader(f, part: part)
    EpisodeList(franchise: f, part: part, window: window, tint: DetailTint.quiet(tint)).id(part.mediaId)
    if total > window.count {
        Button { push(.episodes(f.id, part.mediaId, nil)) } label: {
            HStack(spacing: 6) {
                Text(Copy.Action.allEpisodes(total))                       // "All 24 episodes"
                Image("chevron.forward").font(.system(size: 13, weight: .semibold))
            }
        }
        .buttonStyle(InlineLinkButtonStyle())
        .padding(.leading, -12).padding(.vertical, -4)
    }
}
```

`total = EpisodeList.count(part, now:)`; `window.count` is at most 6 (`upper − lower + 1`). `Copy.Action.allEpisodes(n)` = `"All " + Copy.episodes(n)` — with the **non-breaking space**: `All 24\u{00A0}episodes`. Ink is `interactive`, never amber.

`.id(part.mediaId)` re-keys the whole list on a picker change, so `EpisodeList`'s own `revealed` set and pending prompt reset and *"a picker change lands on a fresh list rather than rows morphing their numbers in place."*

---

## 8 · `EpisodeList` — the one episode row anatomy

Shared verbatim by the show page (windowed) and `SeasonEpisodesView` (full run). It is a `LazyVStack(spacing: 0)` — **lazy is mandatory**:

> One Piece Season 1 advertises ~1,140 episodes; eagerly building every row (each with a palette task) is a multi-second freeze on the push transition and a plausible watchdog termination.

Each row carries `.id("ep-\(n)")` so the focus jump works.

```swift
struct EpisodeList: View {
    let franchise: Franchise
    let part: FranchisePart
    var window: ClosedRange<Int>? = nil     // nil = every episode
    var revealAll: Bool = false             // the season screen's whole-list spoiler switch
    var tint: Color? = nil                  // already DetailTint.quiet-ed
    @State private var revealed: Set<Int> = []
    @State private var prompt: WritePrompt?
}
```

### 8.1 How many rows

```swift
static func count(_ part: FranchisePart, now: Int64) -> Int {
    max(part.renderableEpisodeCount(now: now), part.progress, part.episodes.map(\.number).max() ?? 0)
}
```

`renderableEpisodeCount(now:)`: `totalEpisodes` when > 0; otherwise `max(provenAiredCount, progress, isReleasing && nextAiringAt != nil ? provenAiredCount + 1 : 0)` — *"extend one past what has aired so the next-to-air row can carry its date badge. Row plumbing ONLY: it is a guess, and a guess must never be shown as a season length."*

`range` = `1...max(1, count)` when `window == nil`; otherwise the window clamped into `1...total`.

### 8.2 Per-row derivations

```swift
let episode     = part.episodes.first { $0.number == n }
let watched     = n <= part.progress
let aired       = !part.isReleasing || n <= part.provenAiredCount(now: now) || n <= part.airedEpisodes
let isNext      = n == part.progress + 1 && aired
let spoilerSafe = watched || isNext || revealAll || revealed.contains(n)
let interactive = appModel.isInLibrary(f.id) && aired
let cleanTitle  = EpisodeCopy.title(episode?.title, franchise: f.title)
let canReveal   = !spoilerSafe && (cleanTitle != nil || episode?.still != nil)
```

`provenAiredCount(now:)` — for a non-releasing part it is simply `airedEpisodes`. For a releasing one it is `max(airedEpisodes, latestDatedEpisodeStrictlyBeforeToday, latestStruckAiringSlot)` where:
- "dated" walks `part.episodes`, taking the greatest `number` whose `airDate` is **strictly before today** in the **UTC** calendar (`Episode.airDateAnchor == .utcDate`; `airDate` only ever comes from TMDB and is date-only);
- "struck" is `airings.filter { $0.at <= now }.map(\.episode).max()`.

Strictly-before, not today-or-earlier: *"today's slot is the one the catalogue is still counting down to, and swallowing it here would cost the next-to-air row its date badge on every healthy season the moment its drop day arrives."*

### 8.3 Row layout

```
HStack(spacing: 8)
├── Button (the whole text+tile area)        buttonStyle(RowPressStyle)
│   └── HStack(alignment: .center, spacing: 14)
│       ├── tile (120 × 68)
│       ├── VStack(alignment: .leading, spacing: 3)
│       │   ├── HStack(.firstTextBaseline, spacing: 8) { title ; revealGlyph? }
│       │   └── subtitle?
│       └── Spacer(minLength: 0)
└── MarkRing            — only when `aired`
```

Row modifiers: `.padding(.vertical, 6)`, `.frame(minHeight: 82, alignment: .center)`, `.opacity(aired ? 1 : 0.72)`, and a bottom `.overlay` rule when not last.

- **Unaired rows recede as a GROUP, one opacity.** 0.72 ≈ 5.4:1 against the canvas and still steps back; the value it replaced (0.45) composited `textSecondary` to ≈ 2.64:1 *"and it was applied to exactly the rows being scanned for a date."*
- **Separator**: `Rectangle().fill(separatorQuiet).frame(height: 1).padding(.leading, 120 + 14 = 134)` — inset to the title's leading edge, drawn for every row except the last in `range`.

**Title** — `rowTitle(cleanTitle, n, spoilerSafe)`:
```
spoilerSafe && cleanTitle != nil  →  "Episode 4 · The Name"
otherwise                         →  "Episode 4"
```
Type `rowTitle` (Outfit SemiBold 17, −0.20); colour **`watched ? textSecondary : textPrimary`**; `.lineLimit(2)`; `.minimumScaleFactor(0.92)` — *"An identity title never ellipsises."*

**Notation is fixed**: `"Episode 19"`, never `E19`, `Ep 19`, or `S5 E19`.

**Subtitle** — `rowSubtitle(...)` returns `(text, accent)`; type is `rowMetaLead` (SF footnote semibold) in `accent` when `accent == true`, else `rowMeta` (SF footnote) in `textSecondary`. **1 line.**

| Order | Condition | Text | Accent |
|---|---|---|---|
| 1 | `isNext` | **`"Next up"`** | **yes** |
| 2 | `!aired && n == part.airedEpisodes + 1 && part.scheduledAiring(now:, anchor: f.source.timeAnchor) != nil` | `TemporalCopy.airs(at:, now:, source: f.source)` | no |
| 3 | `!aired` otherwise | *nothing* — *"'Upcoming' says only what the row's position below the dated ones says."* | – |
| 4 | `episode?.airDate != nil` | `TemporalCopy.aired(at: d, now:, source: .tmdb)` — **hard-coded `.tmdb`**, because `airDate` only ever comes from TMDB and is date-only | no |
| 5 | `derivedAirDate(part, n) != nil` | `TemporalCopy.aired(at:, now:, source: f.source)` | no |
| 6 | else | nothing — *"an invented date is worse than a blank"* | – |

**`derivedAirDate`** — one week per episode, anchored on whichever real instant the part carries; `week = 604_800_000` ms:
```swift
if let next = part.nextAiringAt, let m = part.nextEpisodeNumber, m > n { return next − Int64(m − n) * week }
if let last = part.lastAiredAt, part.airedEpisodes >= n            { return last − Int64(part.airedEpisodes − n) * week }
return nil
```
*"Conservative: never runs forward past an anchor, never fires without one."*

**Temporal copy** (`TemporalCopy`, one expression per item; a date-only source never shows a clock):

`airs(at:now:source:)` — AniList: `"Airs in 27 min"` (`0 < Δ < 60 min`) · `"Today at 8:30 PM"` · `"Tomorrow at 8:30 PM"` · `"{Weekday} at 8:30 PM"` (2…6 days) · `"Aug 28 at 8:30 PM"` / `"Aug 28, 2027 at 8:30 PM"`. TMDB: the day word alone — `"Today"` · `"Tomorrow"` · `"{Weekday}"` · `"Aug 28"` / `"Aug 28, 2027"`.

`aired(at:now:source:)` — AniList: `"Aired just now"` (< 5 min) · `"Aired 27 min ago"` (< 60 min) · `"Aired 10h ago"` (same day) · `"Aired yesterday"` · `"Aired Wednesday"` (2…6 days) · `"Aired Aug 19"`. TMDB: `"Aired today"` instead of the clock forms.

`dateWord(ts, now:, anchor:)` = month-day in the current year, full date otherwise — **never string-joined**: `"\(md), \(year)"` produced `"31 Mar, 2013"` on a day-first device *"which no locale writes"*. Use the locale's own `MMMdyyyy` skeleton.

### 8.4 The tile — every row carries one

Three branches:

| Condition | View |
|---|---|
| `spoilerSafe` | `EpisodeStill(url: episode?.still, landscape: part.landscapeArt ?? f.landscapeArt, poster: part.portraitArt ?? f.portraitArt, tint: tint, number: n)` |
| `aired && episode?.still?.isEmpty == false` (i.e. a still exists but is being withheld) | `WithheldStillTile(tint: tint)` |
| otherwise | `EpisodeStill(url: **nil**, landscape:…, poster:…, tint:, number: n)` |

> EVERY row carries a tile: the episode's still, a withheld still, or the season's own cover under the episode's number. The list used to drop the art column for any season under a third illustrated — most anime — and became a column of bare "Episode 12 / Aired 3 Jul" text (user, 2 Sep: "not there yet").

**`EpisodeStill`** — `aspectRatio(16/9, .fit)`, `.frame(width: 120)` (or full width when `width == nil`, the AX card case), `clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))`, `overlay(strokeBorder(posterEdge, lineWidth: 1))`, `accessibilityHidden(true)`.

Layers, in order:
1. Rounded rect filled `stillTint ?? tint ?? surfaceRaised`.
2. Content, first match wins:

| Case | Image | Alignment | Overlay gradient (top → bottom) |
|---|---|---|---|
| has still | `.fill`, maxPixel `(width ?? 400) × 3` = **360** | default `.center` | none |
| has landscape | `.fill`, 360 | `.center` | black 0.20 → **0.46** |
| has poster | `.fill`, 360 | **`.top`** — *"a 2:3 cover carries the face in its upper half and the logotype band in its lower one"* | black 0.25 → **0.50** |
| nothing | – | – | black 0.10 → **0.34** — *"a play glyph here would claim a picture failed to load"* |

3. **The numeral**, drawn only when `number != nil && !hasStill`: `Text("\(number)")`, `.system(size: 17, weight: .bold).monospacedDigit()`, `textPrimary`, `.shadow(color: .black.opacity(0.55), radius: 3, y: 1)`, `.frame(maxWidth/.maxHeight: .infinity, alignment: .bottomLeading)`, `.padding(7)`.

> A real still is never labelled; the row's text is 8 pt away. … a column of tiles reads 11, 12, 13 instead of one poster eighteen times — which is what kept every anime season a wall of bare text rows.

4. `.task(id: url ?? landscape ?? poster) { stillTint = DetailTint.quiet(await PaletteCache.resolve(url: url ?? landscape ?? poster, maxPixel: 288)) }` — each tile resolves its **own** palette.

**`WithheldStillTile`** — fixed **120 × 68**, radius 8, fill `tint ?? surfaceRaised`, overlay `LinearGradient(black 0.10 → 0.34)`, overlay SF `eye.slash` `.system(size: 16, weight: .regular)` in `textPrimary @ 0.62`, clip + `posterEdge` 1-pt border, `accessibilityHidden(true)`.

> Distinct from the shared `EpisodeGlyphTile` (`play.rectangle` = there is no still at all): a withheld still is a choice the user can reverse, and `eye.slash` is the glyph on the control that reverses it.

And why no identifier is drawn on it: the tile it replaced printed `S7 · E2` built from `sequence`, which *"on every AniList franchise with an OVA disagreed with the fact line 8 pt away ('Season 4 · Episode 19' beside 'S5 · E19'), broke the copy table's own notation rule twice over, and was the screenshot attached to the one-star review."*

### 8.5 `EpisodeCopy.title(raw, franchise:)` — the sanitiser

Returns `nil` when there is no real title. Order of operations:

1. `nil` in → `nil` out.
2. Collapse every whitespace run to a single space (the double space came from an empty numeral slot).
3. Strip a leading `^[Ee]pisode\s*\d*\s*[-–—:·]?\s*`.
4. Trim characters in `" -–—:·"` from **both** ends.
5. Empty → `nil`.
6. Lower-cased, if it **starts with the franchise's own lower-cased title** → `nil`.
7. If it still starts with `"episode"` → `nil`.
8. If it **ends with** any of `"trailer"`, `"teaser"`, `"promo"`, `" pv"`, `"preview"` → `nil`.
9. Otherwise return the trimmed string (original case).

> The flagship show's first row read `Episode 1 · Episode  - That Time I Got Reincarnated as a Slime…`: the word "Episode" twice, a double space, a dangling hyphen, the franchise's own title inside its episode title, and then ellipsised. … Anything that OPENS with the show's own name is a catalogue string, not the name of an episode.

Step 6 is a **prefix** test, not equality, because AniList's episode-1 slot on that show holds "the show's name, then a *different work*, then a promo tag".

### 8.6 `MarkRing` at `.settled` — the exact contract

Rendered **only when `aired`** (an unaired row has no ring at all).

```swift
MarkRing(marked: watched, style: .settled, lead: isNext,
         episode: isNext ? n : nil,
         label: Copy.episode(n), markedLabel: Copy.episode(n)) { if interactive { tapped(...) } }
.disabled(!interactive)
.accessibilityValue(watched ? "Watched" : "Not watched")
.accessibilityHint(interactive ? (watched ? "Marks as unwatched" : "Marks as watched") : "")
```

Geometry, identical in every style: a **44 × 44** target (`.contentShape(Circle())`) holding a **22 × 22** ring at **1.5 pt** stroke. `.buttonStyle(MarkPressStyle())` — compression only (0.985 scale on `pick(uiPress)`), opacity 0.72 instead of scale under Reduce Motion; **no rounded-rect wash behind a circle**. `.animation(pick(uiMicro), value: marked)`.

Colour resolution for `.settled`:

| | fill | ring stroke | check ink |
|---|---|---|---|
| `marked == true` | `.clear` | `.clear` | `textTertiary` |
| `marked == false`, `lead == true` | `.clear` | **`accent`** | – |
| `marked == false`, `lead == false` | `.clear` | `markRingIdle` (white 0.34) | – |

So down one column: **a watched episode is a bare tertiary check with no ring; the NEXT episode is the ONE accent ring, carrying its numeral; every other unwatched aired episode is a quiet idle ring with its numeral.**

> `.quiet` still put eleven amber rings down one column: history is quiet, and amber goes to the ONE ring that is a next step.

**The numeral inside the ring** — drawn when `episode != nil && !marked && episode < 1000`. In this list `episode` is passed **only for the lead row** (`isNext ? n : nil`), so idle rings are bare circles here.
- Font: `.system(size: episode < 100 ? 9 : 7, weight: .semibold).monospacedDigit()`
- Colour: `lead ? accent : textSecondary`
- `.transition(.opacity)`

**The check** — `DrawnCheck(on: marked, size: 12, tint: ink)`, mounted **unconditionally** (see §5.6). Left-to-right mask on `uiMicro`; instant under Reduce Motion.

VoiceOver: label = `marked ? markedLabel ("Episode 19") : label ("Episode 19")`; traits `[.isButton, .isSelected]` when marked, `.isButton` otherwise; value and hint as above.

### 8.7 The reveal glyph (per row)

Sits **on the title's baseline**, inside the title `HStack`, not in the trailing control column — *"a row has one control column, not a toolbar."*

`Button` → `Image("eye")` `.system(size: 13, weight: .semibold)`, `textTertiary`, `.frame(width: 44, height: 44).contentShape(Rectangle())`, `.buttonStyle(MarkPressStyle())`, `.padding(.vertical, -14)` (*"so a hidden title does not sit 30 pt taller than the row beneath it"*), `.accessibilityLabel("Reveal episode title")`.

Action: `withAnimation(pick(uiMicro)) { revealed.insert(n) }` — **insert only; a row cannot be re-hidden.**

### 8.8 Tap behaviour

Both the row body and the `MarkRing` call the same `tapped(f, part, n, watched)`; both are inert when `!interactive` (not in library, or unaired).

| Case | Behaviour |
|---|---|
| `watched && n == part.progress` (un-marking the newest watched episode) | Immediate `setProgress(n − 1)`, Undo toast `"Episode {n} marked as unwatched"` |
| `watched && n < part.progress` | **Confirm** → un-mark down to `n − 1` (§9) |
| `!watched && n == part.progress + 1` | Immediate `markNext`; haptic `.success` if `n >= markTarget && !isReleasing && totalEpisodes > 0`, else `.commitLight`; Undo toast `"{title} · Episode {n} watched"` |
| `!watched && n > part.progress + 1` | **Confirm** → batch mark through `n` (§9) |

Note there is **no local mark-timeline** here (no pin, no 650 ms window, no `DrawnCheck` staging beyond the ring's own): the row's tick draws immediately and the Undo toast is presented at once.

---

## 9 · Confirmations — every write states its exact blast radius

`WritePrompt` is an `Identifiable` struct `{ title, message, confirm, destructive = false, perform }` presented through a `confirmationDialog(titleVisibility: .visible)` with the confirm button (role `.destructive` when flagged) and `"Cancel"` (role `.cancel`).

Three views each own an independent prompt: `FranchiseDetailView`, `EpisodeList`, `SeasonEpisodesView`.

| Command | Title | Message | Confirm |
|---|---|---|---|
| Batch mark forward | `Mark {n} episodes as watched?` | `Your progress will move from episode {a} to episode {b}.` | `Mark {n} episodes as watched` |
| Reset a season (to 0) | `Mark {n} episodes as unwatched?` | `This sets {label} back to 0 of {n} watched. Your watch history is kept.` | `Mark {n} episodes as unwatched` |
| Un-mark to a mid point | `Mark {n} episodes as unwatched?` | `Your progress will move from episode {p} to episode {t}.` | `Mark {n} episodes as unwatched` |
| Mark series watched | `Mark {behind} episodes as watched?` | `This marks every episode of {title} as watched, across {k} seasons.` | `Mark {behind} episodes as watched` |
| Restart rewatch | `Restart rewatch?` | `Restarting discards {n} episodes of progress in this run. Earlier watches are kept.` | `Restart rewatch` *(destructive)* |
| Cancel rewatch (Detail) | `Cancel this rewatch?` | `The session is kept in your history as cancelled at episode {n}.` | `Cancel rewatch` *(destructive)* |
| Stop rewatch (Session sheet) | `Stop this rewatch?` | `The session stays in your history, stopped at episode {n}. Your progress is not changed.` | `Stop rewatch` *(destructive)* |
| Delete one session | `Delete this session?` | `This permanently removes {n} episodes from your history. Your other sessions are unchanged.` | `Delete this session` *(destructive)* |
| Delete watch history | `Delete watch history?` | `This permanently removes {k} watch sessions covering {n} episodes.` | `Delete watch history` *(destructive)* |

Capitalisation rule: `"Episode 19"` is capitalised as a **label/identifier**; lower-case inside a sentence-case **command or message** (`"episode 19"`). Two functions, `Copy.episode(_:)` and `Copy.episodeInSentence(_:)`; nothing else builds the string.

**Two invariants the copy table enforces on itself** (`Copy.Action.ellipsisViolations` / `confirmationButtonViolations`, both must be empty):
- a command label ending in `…` (U+2026) **must** open a confirmation;
- a confirmation **button** label never ends in `…`.

### 9.1 Write policy

| Write class | On failure |
|---|---|
| **Progress** (`markNext`, `setProgress`) | **Never rolls back.** Failure goes to `SyncCenter.record` and the SyncBanner, carrying a `WriteIntent` so it can retry itself on a later launch. No red toast. |
| **Status / membership** (`setStatus`, `addToLibrary`, remove) | **Rolls back**, then records on the SyncBanner. |

Every progress write funnels through `AppModel.sendProgress`: **one PUT in flight per part**, the newest target waits behind it, superseded targets are dropped — *"so the server always ends on the user's last word."*

`setProgress` clamps to `part.progressCeiling` (= `max(totalEpisodes, airedEpisodes)`, or unbounded when both are 0, or 0 for an upcoming part) and picks its own haptic: `.commitMedium` when `|new − prev| > 1`, else `.commitLight`.

### 9.2 Undo toasts raised by this area

`UndoState.message` resolution: `customMessage` → `"Removed from Library. Watch history kept."` (removed) → `"Added {title} to {status}"` (added) → `"{title} · {n} episodes watched"` (`count > 1`) → `"{title} · Episode {n} watched"`.

| Origin | Toast |
|---|---|
| Single episode mark (block CTA or row) | `{title} · Episode {n} watched` |
| Batch mark | `{title} · {n} episodes watched` |
| Un-mark newest watched | `Episode {n} marked as unwatched` |
| Un-mark to a mid point | `{n} episodes marked as unwatched` |
| Reset season | `{label} marked as unwatched` |
| Movies & extras toggle | `{label} marked as watched` / `{label} marked as unwatched` |
| Mark series watched | `{title} · {behind} episodes watched` |
| Start rewatch | `Rewatch started` |
| Restart rewatch | `Rewatch restarted` |
| Status change | `Moved to {status}` |
| Related title not found | *(neutral notice, no Undo)* `Not in the catalogue yet` |

Toast anatomy: a content-width **glass capsule** (`chromeGlass` → `ultraThinMaterial`, or `surfaceFloating` + `strokeStrong` under Reduce Transparency), `maxWidth 420`, `.shadow(.floating)`, floating 62 pt above the safe-area bottom, in on `uiSnappy` with a 4-pt rise, out on `uiDismiss`. VoiceOver announces `"{message}. Undo available."`. Window: 6 s.

---

## 10 · Movies & extras

Everything that is **not** on the episodic spine, as art. The seasons live in the picker above.

```swift
let spine = Set(f.episodicPartsInOrder.map(\.mediaId))
let parts = f.parts.filter { !spine.contains($0.mediaId) }.sorted { $0.sequence < $1.sequence }
```

Layout — the same anatomy `DetailShelf` uses, written out inline:

```
VStack(alignment: .leading, spacing: 10)
├── SectionHeaderRow("Movies & extras")            // no count, no action → plain title
└── ScrollView(.horizontal)
    └── HStack(alignment: .top, spacing: 12) { cards }
        .padding(.leading, 16)
        .padding(.vertical, 4)
    .scrollIndicators(.hidden)
    .scrollClipDisabled()
    .shelfScroller()
    .padding(.horizontal, -16)                     // the shelf runs edge to edge
```

**`SectionHeaderRow`** (no action here): `Text` in `sectionTitle` (Outfit SemiBold 20, −0.30), `textPrimary`, 1 line, `minimumScaleFactor 0.85`, `.accessibilityAddTraits(.isHeader)`, `.zIndex(1)`.

**`shelfScroller(trailingMargin: 40, masked: true)`** — *"Art may run off the trailing edge; TYPE may not."*
- `.contentMargins(.trailing, 40, for: .scrollContent)`
- a horizontal mask, **skipped at accessibility sizes**: `black@1` at 0 → `black@1` at **0.86** → `black@0.45` at **0.95** → `black@0` at 1
- the mask is `.padding(.vertical, -24)` (vertically oversized) so it does not undo `.scrollClipDisabled()` and shear the cards' `.art` shadows into a hard line

40 pt and not 28: *"at 28 the peeking card's caption still reached the bezel and sheared mid-word ('Avatar:', 'Caught u', 'So', 'Re')."*

### 10.1 `extraCard`

```swift
let isExtra = [.special, .music].contains(part.kind)
let facts   = partFacts(f, part: part)
let settled = !isExtra && part.isComplete && !part.isReleasing
let caption: String? = isExtra ? (part.totalEpisodes > 1 ? Copy.episodes(part.totalEpisodes) : nil)
                               : (facts.lead ?? facts.meta)
```

`ShelfCard(title: canonicalLabel.isEmpty ? part.title : canonicalLabel, caption:, captionIsLead: facts.lead != nil, poster: part.portraitArt ?? f.portraitArt, slot: .shelfMedium)`, action `{ if !isExtra && inLibrary { toggleUnit(f, part:) } }`.

`ShelfCard` anatomy: `VStack(alignment: .leading, spacing: 8)`:
- `PosterSlot(url:, .shelfMedium)` — **112 × 168**, radius 12, `.art` shadow; art is `.fit` over the show's own palette colour at 0.60 (never grey), `posterEdge` 1-pt border; a `photo` symbol at `min(w,h) × 0.28` when there is no art; palette resolved at `max(w,h) × 3`.
- `VStack(alignment: .leading, spacing: 2)`:
  - title `shelfShortened`, type `shelfTitle` (Outfit Medium 14), `textPrimary`, `.lineLimit(1...2)` (1…6 at AX), `minimumScaleFactor 0.82`, `.fixedSize(horizontal: false, vertical: true)` — **nothing is reserved**; the caption sits directly under a one- or two-line title.
  - caption type `shelfCaption`, colour `captionIsLead ? accent : textSecondary`, `.lineLimit(2)`, `.truncationMode(.tail)`.
- caption block `.frame(width: 112, alignment: .leading)` (full width at AX).
- `.buttonStyle(RowPressStyle(radius: 12))`; `.accessibilityElement(children: .combine)`; label = the **whole** title + caption, never the shortened one.

Card-level overlays and traits:

| | |
|---|---|
| `settled` badge | `.overlay(alignment: .topTrailing) { settledBadge.padding(6) }` |
| `isExtra` | `.opacity(0.6)`, `.allowsHitTesting(false)`, `.accessibilityRemoveTraits(.isButton)` — *"A catalogue of featurettes the app does not track is not a control"* and *"it offered a double-tap that did nothing"* |
| a11y value | `settled ? "Complete" : ""` |
| a11y hint | `!isExtra && inLibrary ? "Toggles watched" : ""` |

**`settledBadge`** — SF `checkmark` `.system(size: 12, weight: .bold)`, `textPrimary`, `.frame(width: 26, height: 26)`, `.background(scrimStrong, in: Circle())`, `.overlay(Circle().strokeBorder(hairline, lineWidth: 1))`, `accessibilityHidden(true)`.

Why specials are dimmed and excluded from the spine:

> A catalogue of featurettes is not a member of the work. TMDB's season 0 on Game of Thrones carries **300** of them; printed inline after Season 1 with an empty tick column and a subtitle in a grammar no other row used, it read as "this app thinks there are 300 Game of Thrones specials" — and a viewer who disbelieves one count disbelieves every count above it.

### 10.2 `partFacts(f, part) -> (meta, lead, progress, spokenProgress)`

`lead` is amber; `meta` is grey; `progress` is a 0…1 bar; words for what has already happened are gone. (Only `meta`/`lead` are consumed by `extraCard`; the two progress fields are computed and currently unused here.)

```
1. part.isUpcoming:
     announcedDateLabel != nil → (nil, "Premieres {date}", nil, nil)
     else                      → ("No date announced", nil, nil, nil)
2. kind ∈ {special, music}:
     ("{scale} · not counted towards progress", nil, nil, nil)
     where scale = totalEpisodes > 1 ? "{n} episodes" : "Extras"
3. kind != .season && totalEpisodes <= 1:      // a film or a single-unit OVA
     ("{Film|Kind} · {year}", nil, nil, nil)   // "Movie" is spelled "Film"; year appended when known
4. total   = max(totalEpisodes, airedEpisodes)
   started = total > 0 && 0 < progress < total
   ratio   = started ? min(progress,total)/total : nil
   spoken  = started ? "{w} of {t} watched" : nil
5. part.isReleasing:
     behind > 0                                   → (nil, "{n} episodes behind", ratio, spoken)
     else if f.nextAiring != nil && this is the releasing part
                                                  → (nil, TemporalCopy.airs(...), ratio, spoken)
     else                                         → ("Caught up", nil, ratio, spoken)
6. f.currentPart == this && progress < total      → (nil, "Episode {progress+1} next", ratio, spoken)
7. isComplete && !isReleasing                     → (nil, nil, nil, nil)   // the tick is the statement
8. started                                        → (nil, "{n} episodes left", ratio, spoken)
9. else                                           → (total > 0 ? "{total} episodes" : nil, nil, nil, nil)
```

*"A FINISHED season says nothing: the tick is the statement."* And *"Not started: its size, as a count, not '0 of 12 watched'."*

`announcedDateLabel(source:)` = the part's own `premiereAt` formatted as a full date, else the earliest `episodes[].airDate` formatted as a full date — *"TMDB frequently leaves the premiere slot null while still dating the season through its first episode."*

### 10.3 `toggleUnit`

```swift
let full = max(part.totalEpisodes, 1)
let watched = part.progress >= full
appModel.setProgress(franchiseId:, mediaId:, episodes: watched ? 0 : full)
appModel.presentUndo(... customMessage: "{label} marked as {watched ? "unwatched" : "watched"}")
```

No confirmation — the write is one unit and Undo is immediate.

---

## 11 · The four catalogue shelves (Apple TV's order)

All four share `DetailShelf`, which is the Movies & extras anatomy factored out:

```swift
struct DetailShelf<Content: View>: View {
    let title: String
    var count: Int? = nil
    var action: (() -> Void)? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeaderRow(title, count: count, action: action)
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) { content() }
                    .padding(.leading, 16).padding(.vertical, 4)
            }
            .scrollIndicators(.hidden).scrollClipDisabled().shelfScroller()
            .padding(.horizontal, -16)
        }
    }
}
```

When `action != nil` and `inlineAction == false`, `SectionHeaderRow` makes **the title itself the button**, adding a trailing `chevron.forward` `.system(size: 14, weight: .semibold)` in `textTertiary`, wrapping it in `SectionHeaderPressStyle` (padding 10, `minHeight 44`, opacity 0.55 pressed on `uiPress`) with `.padding(.vertical, -10)`, and labelling it `"{title}, {actionLabel ?? "See all"}"` with `.isHeader`. **There is no "See all" word** — the Apple TV / Netflix shelf grammar.

Each shelf's root carries an `.id("anchor-…")` used only by the DEBUG capture driver (§16).

### 11.1 Trailers

Gate: `f.allVideos` non-empty. Title: **`"Trailers"`**. `.id("anchor-trailers")`.

`Franchise.allVideos` = `[featuredVideo] + videos + parts.flatMap(\.videos)`, de-duplicated by `"{site}/{id}"`, **featured first**.

**`TrailerCard`** — `static let width: CGFloat = 200`; art height = `(200 × 9 / 16).rounded()` = **113**.

Art block (`ZStack`, then `.frame(width: 200, height: 113)`, `.clipShape(card22)`, `.overlay(strokeBorder(posterEdge, 1))`, `.shadow(.art)`):
1. `RoundedRectangle(cornerRadius: 22, style: .continuous).fill(surfaceRaised)`
2. `RemoteImageView(url: video.thumbnailURL, contentMode: .fill, maxPixel: 640, placeholderHidden: true)`
3. The play disc: SF `play.fill` `.system(size: 15, weight: .bold)`, `textPrimary`, `.padding(.leading, 2)` (optical centring), `.frame(width: 40, height: 40)`, `.background(scrimStrong, in: Circle())`, `.overlay(Circle().strokeBorder(hairline, lineWidth: 1))`

Caption block, `.frame(width: 200, alignment: .leading)`, outer `VStack(spacing: 8)`, inner `VStack(spacing: 2)`:
- `video.displayTitle` — `shelfTitle`, `textPrimary`, 2 lines, leading, `.fixedSize(horizontal: false, vertical: true)`
- `TrailerCard.meta(video)` — `shelfCaption`, `textSecondary`, **1 line**

`.contentShape(Rectangle())`, `.buttonStyle(RowPressStyle(radius: 22))`, `.accessibilityElement(children: .combine)`, label `"{displayTitle}, {meta}"`, hint **`"Plays the video"`**. Tap → `video = v` (opens the sheet).

**`meta(video)`** — `"Trailer · Season 6"`:
```swift
var bits: [String] = []
let kind = Copy.Video.kind(video.kind)                       // Trailer|Teaser|Announcement|Featurette|Clip|Video
if let title = video.title, !title.localizedCaseInsensitiveContains(kind) { bits.append(kind) }
if let label = video.partLabel { bits.append(label) }
return bits.isEmpty ? nil : bits.joined(separator: " · ")
```
Note the `if let title` guard: when the catalogue gave **no** title, `displayTitle` *is* the kind word and the kind is **not** repeated in the meta line — the caption is then just the part label, or absent.

`video.displayTitle` = `title ?? Copy.Video.kind(kind)`.
`video.partLabel` = the scope's label when `scope == .part(mediaId:label:)` and the label is non-empty.
`video.thumbnailURL` = `thumbnail ?? "https://i.ytimg.com/vi/{youtubeID}/mqdefault.jpg"`.

### 11.2 Cast & crew

Gate: `(f.people?.ordered ?? []).prefix(20)` non-empty. Title: **`"Cast & crew"`**. `.id("anchor-people")`. Maximum **20** cards.

`FranchisePeople.ordered` = creators (each given the role word **`"Creator"`** when the catalogue supplied none) + directors (**`"Director"`**) + cast, de-duplicated by `id = "{source}:{externalId}:{role}"` — *"one person can appear once per role (a director who also acts)"*, and *"so a face is never unexplained."*

**`PersonCard`** — `disc = 72`, `width = 92`. **Not a control**: *"there is no person page, so it claims no tap."*

`VStack(spacing: 8)`:
1. Disc — `ZStack { Circle().fill(surfaceRaised); person.image != nil ? RemoteImageView(url:, .fill, maxPixel: 216, alignment: .top, placeholderHidden: true) : Image("person.fill").font(.system(size: 26, weight: .regular)).foregroundStyle(textTertiary) }`, `.frame(72 × 72)`, `.clipShape(Circle())`, `.overlay(Circle().strokeBorder(posterEdge, lineWidth: 1))`
2. `VStack(spacing: 2)` inside `.frame(width: 92)`:
   - name — `shelfTitle`, `textPrimary`, **2 lines, centred**, `.fixedSize(horizontal: false, vertical: true)`
   - role — `shelfCaption`, `textSecondary`, **2 lines, centred**

`.accessibilityElement(children: .combine)`, label `"{name}, {role}"` (or just the name).

Note the crop anchor is `.top` — a portrait head-shot cropped to a circle from its centre is a chin.

### 11.3 More like this

Gate: `f.related.prefix(12)` non-empty. Title: **`"More like this"`**. `.id("anchor-related")`. Maximum **12** cards.

`ShelfCard(title: r.title, caption: r.identityLine, poster: r.portraitArt, slot: .shelfMedium) { openRelated(r) }`, with `.opacity(resolvingRelated == r.id ? 0.55 : 1)` and `.accessibilityHint("Opens the show")`.

`RelatedTitle.identityLine` = `"{kindWord} · {year}"`, or just `kindWord` when the year is unknown → `"Anime · 2017"`.
`RelatedTitle.portraitArt` = `images?.portrait` (no legacy fallback).

**`openRelated(r)`** — three outcomes:

```swift
if let id = r.franchiseId { push(.detail(franchiseId: id)); return }     // already materialised
guard resolvingRelated == nil else { return }                            // a second tap waits for the first
resolvingRelated = r.id
Task {
    defer { resolvingRelated = nil }
    let res: SearchResponse? = try? await api.search(query: r.title, exact: true)
    let hits = res?.franchises.filter { $0.source == r.source } ?? []
    let hit = hits.first { $0.title.caseInsensitiveCompare(r.title) == .orderedSame } ?? hits.first
    if let hit { push(.detail(franchiseId: hit.id)) }
    else { appModel.showNotice(Copy.Notice.notInCatalogue) }              // "Not in the catalogue yet"
}
```

> The catalogue has not materialised this title yet. An exact-title search asks the server to, and the first same-source hit is the show.

The notice is a **neutral receipt with no action** — `ToastView(message:)`, no Undo, no failure styling.

### 11.4 Where to watch

Gate — all three must hold:
```swift
providers != nil && providers.status == .available && !providers.providers.isEmpty
```
*"a section that says 'not here' is not a section."* `WatchAvailability.Status` also has `notAvailable` (a matched title with nothing streaming in that country), `unmatched` (the anime→TMDB bridge could not establish identity safely) and `disabled` (this deployment has no TMDB token) — **branch on `status`, never on `providers.isEmpty`**.

`WatchProvidersRow` — `VStack(alignment: .leading, spacing: 10)`:
1. `SectionHeaderRow("Where to watch", action: availability.linkURL == nil ? nil : open)` with `.accessibilityHint(linkURL == nil ? "" : "Opens the streaming options")`. So the **header** is the link (and grows a chevron); when there is no link it is a plain title.
2. A horizontal scroller of `ProviderMark`s, `HStack(spacing: 12)`, `.padding(.leading, 16).padding(.vertical, 4)`, `.scrollIndicators(.hidden).scrollClipDisabled().shelfScroller().padding(.horizontal, -16)`.
3. `Text(Copy.Watch.attribution(availability.attribution))` → **`"Streaming availability by JustWatch"`**, type `caption` (SF caption2), `textTertiary`. Required attribution; `attribution` defaults to `"JustWatch"` when the server omits it.

`open` → `openURL(availability.linkURL!)`.

**`ProviderMark`** — `static let size: CGFloat = 52`.
`ZStack { RoundedRectangle(cornerRadius: 12, style: .continuous).fill(surfaceRaised); logo != nil ? RemoteImageView(url: logo, .fill, maxPixel: 156, placeholderHidden: true) : Text(initials).type(metadataEmphasis).foregroundStyle(textSecondary) }`, `.frame(52 × 52)`, `.clipShape(rr12)`, `.overlay(strokeBorder(posterEdge, 1))`.

`initials` = the first letter of each of the first two words of the name, uppercased.
VoiceOver: `"{name}, {Subscription|Free|Free with ads}"`.

**The marks are not controls**: *"the data carries one link for the whole title and none per provider, so a mark that looked pressable would lie."*

Providers arrive subscription-first, then free and ad-supported (server ordering; do not re-sort).

---

## 12 · `VideoSheet` — the trailer player

Presented from Detail with `.sheet(item: $video)`. **No detents are set**, so it is a full-height system sheet with `.presentationDragIndicator(.visible)`. A new video is a **new sheet**, so the player is built once and nothing reloads.

Structure: `NavigationStack { ZStack(alignment: .top) { canvas; VStack(alignment: .leading, spacing: 16) { player; copy; Spacer(minLength: 0) }.padding(.horizontal, 16).padding(.top, 8) }.navigationBarTitleDisplayMode(.inline).toolbar { … } }`.

**Player** — `ZStack { RoundedRectangle(22).fill(surfaceFlat); embedURL != nil ? VideoEmbed(url:) : RemoteImageView(url: thumbnailURL, .fill, maxPixel: 900, placeholderHidden: true) }`, `.aspectRatio(16/9, contentMode: .fit)`, `.clipShape(rr22)`, `.overlay(strokeBorder(posterEdge, 1))`. Where the provider cannot be embedded, the still stands in and the toolbar glyph is the way out to it.

**Copy** — `VStack(alignment: .leading, spacing: 3)`:
- `video.displayTitle` — `showTitleL`, `textPrimary`, 3 lines
- `meta` — `metadata`, `textSecondary`, 2 lines, where `meta = [showTitle (omitted if empty), Copy.Video.kind(kind), partLabel].joined(" · ")` → **`"Re:ZERO · Trailer · Season 4"`**

**Toolbar**
- `.topBarLeading`, only when `video.watchURL != nil`: SF `arrow.up.right` `.system(size: 15, weight: .semibold)`, **`interactive`**, `.frame(44 × 44)`, `.buttonStyle(.plain)`; label `video.youtubeID != nil ? "Open on YouTube" : "Open in browser"`; action `openURL(watchURL)`.
- `.topBarTrailing`: `Button("Done") { dismiss() }.tint(interactive)`.

`watchURL` = the catalogue's `url`, else `https://www.youtube.com/watch?v={id}` for a YouTube video.

### 12.1 `VideoEmbed` — the WKWebView, and the two failure modes

```swift
let config = WKWebViewConfiguration()
config.allowsInlineMediaPlayback = true
config.mediaTypesRequiringUserActionForPlayback = []        // autoplay allowed
let view = WKWebView(frame: .zero, configuration: config)
view.isOpaque = false
view.backgroundColor = .clear
view.scrollView.isScrollEnabled = false
view.scrollView.backgroundColor = .clear
view.loadHTMLString(page(for: url), baseURL: URL(string: "https://previously.local/trailer"))
```

The page:

```html
<!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
<style>html,body{margin:0;padding:0;background:#000;height:100%;overflow:hidden}iframe{position:absolute;inset:0;width:100%;height:100%;border:0}</style></head>
<body><iframe src="{embedURL}" referrerpolicy="strict-origin-when-cross-origin" allow="autoplay; encrypted-media; picture-in-picture" allowfullscreen playsinline></iframe></body></html>
```

`embedURL` = `https://www.youtube.com/embed/{id}?playsinline=1&autoplay=1&rel=0&modestbranding=1` (YouTube only — `site == "youtube"`).

**The two documented failure modes, and why the page exists at all** (source comment, verbatim):

> The player is an `<iframe>` in a page of our own with a base URL, not the embed URL loaded bare: YouTube refuses an embed that arrives with no referring origin (**"Video player configuration error"**, captured 3 Sep), and it refuses one that claims to BE youtube.com (**"This video is unavailable · 152-4"**, the next capture). A neutral origin of our own is what a page embedding a video looks like from the provider's side.

So: **do not** load the embed URL directly into the web view, and **do not** set the base URL to `https://www.youtube.com`. The base URL must be a neutral origin the app owns (`https://previously.local/trailer`), and the `referrerpolicy` must be `strict-origin-when-cross-origin` so YouTube receives that origin.

Android equivalent:
```kotlin
webView.settings.javaScriptEnabled = true
webView.settings.mediaPlaybackRequiresUserGesture = false     // == mediaTypesRequiringUserActionForPlayback = []
webView.settings.domStorageEnabled = true
webView.isVerticalScrollBarEnabled = false
webView.setOnTouchListener { _, e -> e.action == MotionEvent.ACTION_MOVE }   // == scrollEnabled = false
webView.setBackgroundColor(Color.TRANSPARENT)
webView.loadDataWithBaseURL("https://previously.local/trailer", html, "text/html", "utf-8", null)
```
plus a `WebChromeClient` if fullscreen is wanted. Both failure modes reproduce identically on Android WebView; the base-URL fix carries over unchanged.

---

## 13 · `SeasonEpisodesView` — the full season screen

Pushed by `.episodes(franchiseId:mediaId:focusEpisode:)`.

```swift
struct SeasonEpisodesView: View {
    let franchiseId: String
    let mediaId: Int                 // the season the push opened on
    var focusEpisode: Int? = nil
    @State private var selectedMediaId: Int?     // the header's picker can move in place
    @State private var fetched: Franchise?
    @State private var revealAll = false         // per-view, deliberately
    @State private var prompt: WritePrompt?
    @State private var tint: Color?
}
```

`activeMediaId = selectedMediaId ?? mediaId`. `franchise = appModel.franchise(id:) ?? fetched`.

```swift
var part: FranchisePart? {
    let live = f.parts.first { $0.mediaId == activeMediaId }
    let eps  = fetched?.parts.first { $0.mediaId == activeMediaId }?.episodes ?? []
    if let live, live.episodes.isEmpty, !eps.isEmpty { return live.withEpisodes(eps) }
    return live
}
```

The live library part wins for progress; the detail fetch supplies episodes when the library row has none.

**Reads.** `.task { if fetched == nil { fetched = try? await api.franchise(id: franchiseId) } }` — note: **no `country` parameter here**, unlike Detail. `.task(id: franchise?.portraitArt) { tint = await PaletteCache.resolve(url:, maxPixel: 420) }`; `quietTint = DetailTint.quiet(tint)`.

`revealAll` is per-view on purpose: *"it is a viewing preference for the list in front of you, not an account setting."*

### 13.1 Chrome

A **real navigation bar** with a real material — the opposite of what shipped:

> This screen used to hide it and hand-build its own — a circular back button, a centred 22-pt title, a circular ellipsis, no material and no scroll edge effect, so the first row was chopped in half under a black band and left a decapitated poster ghost at 50 % alpha. It then repeated itself, printing "Season 3" a second time 150 pt below the first in larger type.

- `.navigationTitle(franchise?.displayTitle ?? "")` — **the SHOW's short name**, not the season. *"the season is the header below, where its poster, its picker and its progress live."*
- `.navigationBarTitleDisplayMode(.inline)`, `.toolbarRole(.editor)`, `.toolbar(.visible, for: .navigationBar)`
- One trailing item: `seasonOverflow`, drawn only when `appModel.isInLibrary(f.id)`

Ambient wash: `ArtBackdrop(url: f.landscapeArt ?? f.portraitArt, tint: tint, height: 320, intensity: 0.4)`, top-aligned, `.ignoresSafeArea(edges: .top)` — the **one** wash spec app-wide. `ArtBackdrop` = the artwork `.fill`ed and centre-cropped **before** a 56-pt opaque blur at `opacity 0.70 × intensity`, then a base gradient in the palette colour (`0.60 × intensity` → `0.10 × intensity` → clear, with a pre-art floor of 0.55/0.12 that relaxes on `uiGentle` once the palette resolves), then a constant `accent @ 0.07 × intensity` breath, then the canvas handover (clear → `canvas@0.55` at 0.55 → `canvas` at 1.0).

### 13.2 Layout

```swift
ScrollView {
    seasonHeader(f, part: part)
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 12)
    EpisodeList(franchise: f, part: part, revealAll: revealAll, tint: quietTint)
        .padding(.horizontal, 16)
        .id(activeMediaId)
}
.contentMargins(.bottom, DetailMetrics.bottomClearance, for: .scrollContent)
.scrollIndicators(.hidden)
```

No `window:` → **every** episode. `.id(activeMediaId)` re-keys on a picker change.

The bottom clearance is again a **margin, not padding**:

> A complete "Episode 11" row — tile, title and check — rendered in the strip between the floating pill and the home indicator, and "Episode 10 · Mhysa" was sliced by the pill's edge with its air date entirely covered, because padding inside the stack is not an inset for the scroll view.

### 13.3 `seasonHeader` — a `ProgressBanner`, never a poster beside a title

```swift
let total    = max(part.totalEpisodes, part.airedEpisodes)
let watched  = min(part.progress, max(total, part.progress))
let siblings = f.episodicPartsInOrder
let wide     = WideArt(landscape: part.landscapeArt, portrait: part.portraitArt ?? f.portraitArt)
```

`WideArt` makes the one decision a wide frame makes: if a landscape asset exists, use it and `portraitSource = false`; otherwise use the portrait and `portraitSource = true`.

**The SEASON's own picture, not the show's** — *"each season is its own catalogue entry with its own key art, so the picker changes the picture as well as the name."*

`VStack(alignment: .leading, spacing: 12)`:

1. **`ProgressBanner(url: wide.url, portraitSource: wide.portraitSource, progress: total > 0 ? watched/total : nil)`**, `.accessibilityHidden(true)`.

   `ProgressBanner` anatomy — `ZStack(alignment: .bottom)`, `.aspectRatio(16/9, .fit)`, `.clipShape(rr22)`, `.overlay(strokeBorder(posterEdge, 1))`, `.shadow(.art)`:
   - `RoundedRectangle(22).fill(surfaceRaised)`
   - `LandscapeArt(url:, portraitSource:, maxPixel: 900)`
   - `LinearGradient([.clear, scrim], .top → .bottom).frame(height: 56)` — a short scrim, **never a plate**
   - `ProgressBar(value:)` `.padding(.horizontal, 12).padding(.bottom, 12)` (`ProgressBanner.inset = ThemeSpace.x3`)

   `ProgressBar`: height **3**, track `Capsule().fill(strokeStrong)`, fill `Capsule().fill(accent)` at `max(3, width × clamp(value,0,1))`. `accessibilityHidden` unless a `spoken` string is supplied (it is not here — the header's count row speaks instead).

   `LandscapeArt(portraitSource: true)` composites rather than crops: a `.fill` copy at maxPixel **160** blurred **28** opaque under `Color.black.opacity(0.32)`, with the whole cover `.fit` over it at the requested maxPixel, `.padding(.vertical, 8)` and a contact shadow (black 0.45, r 8, y 4) *"without it the two read as one badly-decoded image."* `portraitSource: false` is a plain `.fill` at `alignment: .top`.

2. **The picker + count row** — `HStack(alignment: .firstTextBaseline, spacing: 8)`, byte-for-byte Detail's `episodesHeader` with two differences: the label expression is `canonicalLabel.isEmpty ? title : canonicalLabel` (no `"Episodes"` fallback), and there is an extra count branch.

   - `siblings.count > 1` → the same `Menu` + `chevron.up.chevron.down` + `SectionHeaderPressStyle` + `.padding(.vertical, -10)` + `"Season, {canonicalLabel}"` / `"Chooses another season"` / `.isHeader`. Choosing a sibling sets `selectedMediaId` **without an animation wrapper** (Detail's picker uses `withAnimation(pick(uiGentle))`).
   - `Spacer(minLength: 8)`
   - `total > 0` → `Text("{watched} of {total}")`, `metadata`, `textTertiary`, `.monospacedDigit()`, spoken `"{w} of {t} watched"`
   - else `part.progress > 0` → `Text("{n} episodes watched")`, `metadata`, `textTertiary`
   - `.accessibilityElement(children: .contain)` on the whole header

   `seasonTitle(part)` = `Text(label).type(sectionTitle).foregroundStyle(textPrimary).lineLimit(1).minimumScaleFactor(0.85)`.

Why: *"It was a portrait poster beside a title and a thin line — a settings row for a TV show ('absolutely trash', user, 3 Sep) — and the one place in the app that put a 2:3 cover next to a column of 16:9 stills."*

### 13.4 `seasonOverflow`

Label: SF `ellipsis` `.system(size: 15, weight: .semibold)`, `textPrimary`, 44 × 44. VoiceOver **`"Episode actions"`** (Detail's says "More actions" — *"one overflow grammar across the two screens of a franchise"* refers to the glyph, not the label).

| Gate | Item |
|---|---|
| `markTarget > progress` | `"Mark all {target − progress} episodes as watched"` → confirm |
| `progress > 0` | `"Mark all {progress} episodes as unwatched…"`, `role: .destructive` → confirm (reset to 0) |
| always | *Divider* |
| always | `Toggle(isOn: $revealAll) { Label("Reveal episode titles and stills", systemImage: revealAll ? "eye" : "eye.slash") }` |

> The app has a spoiler model and used it on the Next up card, then showed every still and every title in the one place where the next ten episodes are all on screen at once. Per-row reveal stays for the one episode you want; this is for the viewer who does not want the question asked.

### 13.5 Focus jump

```swift
.onAppear {
    if let focusEpisode {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation(pick(uiSettle)) { proxy.scrollTo("ep-\(focusEpisode)", anchor: .center) }
        }
    }
}
```

400 ms after appearance (so the push transition has settled), scroll that row to the **centre** on `uiSettle`.

### 13.6 Skeleton

Drawn whenever `franchise == nil || part == nil`. `VStack(alignment: .leading, spacing: 0)`, `.padding(.horizontal, 16).padding(.top, 8)`:

1. `SkeletonBlock(height: nil, radius: 22).aspectRatio(16/9, .fit).padding(.top, 12)` — the wide art card
2. `SkeletonLine(width: 120, height: 20).padding(.top, 12).padding(.bottom, 12)` — the title line
3. `8 × SkeletonRow(poster: 120 × 68, lines: [190, 120], posterRadius: 8, spacing: 14, height: 82)`

Note this skeleton is **not** wrapped in `SkeletonGate` — it appears immediately, without the 240 ms delay.

---

## 14 · Rewatch

### 14.1 `RewatchStore` — the model

Device-local JSON, **never on the server**. *"Progress itself stays on the server; sessions explain it."*

```swift
struct WatchSession: Codable, Identifiable, Equatable {
    enum Scope: Codable, Equatable { case franchise; case part(mediaId: Int) }
    let id: UUID
    let franchiseId: String
    let scope: Scope
    let ordinal: Int              // 1 = first watch, 2 = second watch, …
    var startedAt: Int64?
    var completedAt: Int64?
    var cancelledAt: Int64?
    var cancelledAtEpisode: Int?
    var episodes: Int             // the SCOPE's length; 0 when unknown
    var isActive: Bool    { completedAt == nil && cancelledAt == nil }
    var isCompleted: Bool { completedAt != nil }
    var title: String { Copy.Progress.ordinalWatch(ordinal) }   // "First watch" … "Tenth watch", then "11th watch"
}
```

`ordinalWatch`: words for 1–10 (`First`…`Tenth`), then `"{n}{st|nd|rd|th} watch"` with the 11/12/13 exception.

Persistence: `<Application Support>/Previously/sessions.json` with **one backup generation** (`sessions.backup.json`). Every write: copy current → backup, then write the new file atomically, on a detached utility task. Load tries `sessions.json` then `sessions.backup.json`, then falls back to `[]`. *"A reinstall loses history but never corrupts it."*

Queries: `sessions(for:)` filters and sorts **descending by `ordinal`**; `activeSession(for:)` is the first active one; `summary(for:)` → `(completedCount, active, lastCompletedAt = max of completedAt)`.

Commands: `startRewatch`, `complete(id, at:)`, `cancel(id, atEpisode:, at:)`, `setStartDate(id, to:)`, `delete(id)`, `deleteAll(for:)`, `reset()` (sign-out).

**`startRewatch` records the first watch implicitly:**
```swift
var mine = sessions.filter { $0.franchiseId == franchiseId }
if mine.isEmpty {
    // an implicit first watch: scope .franchise, ordinal 1, startedAt nil, completedAt 0
    append(WatchSession(..., ordinal: 1, startedAt: nil, completedAt: 0, episodes: episodes))
}
let ordinal = (mine.map(\.ordinal).max() ?? 0) + 1
append(WatchSession(..., scope: scope, ordinal: ordinal, startedAt: startedAt, episodes: episodes))
```
`completedAt == 0` is the sentinel for "finished, date unknown" — every date formatter checks `> 0` before printing.

**`RewatchArrival`** — a one-shot hand-off so the history rail draws its arrival exactly once:
```swift
@MainActor enum RewatchArrival {
    private static var pending: UUID?
    static func record(_ id: UUID) { pending = id }
    static func claim(_ id: UUID) -> Bool { guard pending == id else { return false }; pending = nil; return true }
}
```
> The rail's new-session choreography … was specified, implemented in the design system and then called from nothing but a `#Preview`: starting a rewatch and opening Watch history showed a fully drawn rail with no arrival at all. The two surfaces are a push apart and neither owns the other's state, so the hand-off is a one-shot token.

### 14.2 `StartRewatchSheet` (Surface C)

Presented from the Next-up card's `"Start rewatch"` button, `.presentationDetents([.large])` — **`.large` only**: *"At `.medium` the scope list ran past the bottom of the sheet and the commit button — now pinned as a bottom inset — had a list a screen and a half tall above it."* Drag indicator visible.

`NavigationStack > ScrollView > VStack(alignment: .leading, spacing: 30)`, `.padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 16)`, `.background(canvasRaised.ignoresSafeArea())`:

1. **Context row** — `HStack(alignment: .top, spacing: 14)`: `PosterSlot(f.portraitArt, .queue)` (44 × 66, radius 8, no shadow); `VStack(alignment: .leading, spacing: 3) { Text(f.title).type(showTitleM).foregroundStyle(textPrimary).lineLimit(2); Text("Your previous watch history stays unchanged.").type(metadata).foregroundStyle(textSecondary) }`; `Spacer(minLength: 0)`.
   *"A modal that opens on a grey sentence and a list of radio rows could be about anything."*

2. **Scope** — `VStack(alignment: .leading, spacing: 10) { SectionLabel(text: "Scope"); LazyVStack(spacing: 0) { rows } }`.
   `SectionLabel` = `sectionLabel` type, **uppercased**, `textSecondary`, 1 line (2 at AX), optional 4-pt accent dot (not used here).

   Rows are `MediaRow`s — *"the same season list is a push away, rendered as 88-pt poster rows on the canvas; here it was text-only 56-pt rows inside a plate with a trailing count — two grammars for one list, one tap apart."*

   | Row | title | count (`meta`) | poster |
   |---|---|---|---|
   | first | **`"Everything"`** | `Σ over episodicPartsInOrder of max(totalEpisodes, progress)` as `"{n} episodes"`, or nil when 0 | `f.portraitArt` |
   | each episodic part | `canonicalLabel.isEmpty ? title : canonicalLabel` | `totalEpisodes > 0 ? "{n} episodes" : nil` | `part.portraitArt ?? f.portraitArt` |

   `"Everything"`, not "All seasons": *"printed directly over a list containing 'OVA 1', 'OVA 2: No Regrets' and 'OVA 3: Lost Girls', none of which is a season. ('Entire franchise' before that was server vocabulary.)"*

   `scopeRow` = `MediaRow(title:, meta: count, poster:, slot: .queue, chevron: false, separator:, trailing: { checkmark })` where the trailing is SF `checkmark` `.system(size: 15, weight: .semibold)` in **`accent`**, `.opacity(selected ? 1 : 0)`, `.frame(width: 18)`, `accessibilityHidden(true)` — **reserved whether or not selected, so a tick landing never reflows the row it lands on**. Tap fires `.selection` then sets the scope. Separator is drawn on every row except the last. VoiceOver label `"{title}, {count}"`; traits `[.isButton, .isSelected]` when selected.

   `MediaRow` geometry for `.queue`: `HStack(spacing: 14)`, `minHeight` **88** (`rowStandard`), `.padding(.vertical, 8)`, separator `separatorQuiet` inset by `44 + 14 = 58`.

3. **Start date** — `GroupedList { HStack { Text("Start date").type(body).foregroundStyle(textPrimary); Spacer(); DatePicker("Start date", selection: $startDate, in: ...Date(), displayedComponents: .date).labelsHidden().tint(accent) } .padding(.leading, 14).padding(.trailing, 10).frame(minHeight: 56) }`.
   No `"START DATE"` header: *"the header and the row were the same three words, 10 pt apart."* The picker is bounded to today or earlier.

**The commit, pinned** — `.safeAreaInset(edge: .bottom)`:
```swift
Button(Copy.Action.startRewatch) { onStart(scope, Int64(startDate.timeIntervalSince1970 * 1000)); dismiss() }
    .buttonStyle(PrimaryButtonStyle2())
    .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)
    .chromeGlass(in: Rectangle())
```
`PrimaryButtonStyle2`: `button` type, `onAccent` ink, `.frame(maxWidth: .infinity, minHeight: 48)`, `.padding(.horizontal, 18)`, accent capsule (`accentPressed` when pressed), a `controlSheen → clear` top-edge stroke, `opacity 0.38` when disabled, press feedback 0.985 scale (opacity 0.72 under Reduce Motion).

`chromeGlass` honours Reduce Transparency (`surfaceFloating` + `strokeStrong` instead of a material) — *"the one raw material in Features: it ignored Reduce Transparency."*

**Toolbar**: `.cancellationAction` → `Text("Cancel").type(body).foregroundStyle(interactive).lineLimit(1).fixedSize()`, `.buttonStyle(RowPressStyle(radius: 12))`, `.chromeSharedBackgroundHidden()`.
Neutral, not amber — *"amber on the dismissive action made the loudest coloured object on the sheet the one that throws the work away — and the selection check was amber too, so there were two ambers and neither was the primary action."*
Plain text, not a filled pill — *"iOS has never put a filled pill in a sheet's leading position … the shared background has to be dropped from the item, not from the button inside it."*
Title: `.navigationTitle("Start rewatch")`, inline.

### 14.3 `startRewatch(f, scope, startedAt)` — the transaction

```swift
let parts = scope == .franchise ? f.episodicPartsInOrder : f.parts.filter { $0.mediaId == mediaId }
let snapshot = parts.map { ($0.mediaId, $0.progress) }
let previousStatus = f.effectiveStatus
let episodes = parts.reduce(0) { $0 + max($1.totalEpisodes, $1.progress) }
let session = RewatchStore.shared.startRewatch(franchiseId: f.id, scope: scope, startedAt: startedAt, episodes: episodes)
RewatchArrival.record(session.id)
FeedbackCoordinator.fire(.success)                                   // the ONE haptic
withAnimation(pick(uiSettle)) {
    for (mediaId, progress) in snapshot where progress > 0 {
        appModel.setProgress(franchiseId: f.id, mediaId: mediaId, episodes: 0, haptic: false)
    }
    appModel.setStatus(franchiseId: f.id, status: .watching, haptic: false, present: false)
}
appModel.presentUndo(UndoState(..., customMessage: Copy.Toast.rewatchStarted /* "Rewatch started" */) {
    RewatchStore.shared.delete(session.id)
    for (mediaId, progress) in snapshot { appModel.setProgress(..., episodes: progress, haptic: false) }
    appModel.setStatus(franchiseId: f.id, status: previousStatus, haptic: false, present: false)
})
```

Note the Undo restores **every** part's progress (including the zeroes), the previous status, **and** deletes the session.

### 14.4 Restart / cancel (from Detail's overflow)

**Restart** — `watched = Σ episodicPartsInOrder.progress`. Confirm (§9), then: fire `.success`; snapshot; zero every part with `progress > 0` (`haptic: false`); present Undo `"Rewatch restarted"` restoring the snapshot. *"The same receipt a season reset gets: a toast that names what moved and an Undo that restores the exact snapshot. It wiped every tick with neither."*

**Cancel** — `at = f.currentPart?.progress ?? 0`. Confirm (§9), then fire `.destructive` and `RewatchStore.cancel(session.id, atEpisode: at, at: now)`. **No progress is touched**, no Undo.

### 14.5 `WatchHistoryView` (Surface D)

`ZStack { canvas; ArtBackdrop(f.landscapeArt ?? f.portraitArt, height: 320, intensity: 0.4) top-aligned, ignoresSafeArea top; … }`.

**Empty** (`sessions.isEmpty`): `EmptyState(.noSessions, prominence: .major)`, `.padding(.horizontal, 16).padding(.bottom, DetailMetrics.bottomClearance)`, `.frame(maxWidth: .infinity, maxHeight: .infinity)` — **centred**, *"an empty state pinned under the navigation bar with 1 400 pt of canvas under it reads as a screen that failed to load."*

> symbol `clock.arrow.circlepath` · title **`"No watch history yet"`** · supporting **`"Your first watch is recorded when you finish the show. Rewatches appear here as sessions."`** · no button.

**Populated**: `ScrollView { VStack(alignment: .leading, spacing: 30) { … } .padding(.horizontal, 16).padding(.top, 26).modifier(CentreShortList(active: sessions.count == 1 && !isAX)) }`, `.contentMargins(.bottom, DetailMetrics.bottomClearance, for: .scrollContent)`, `.scrollIndicators(.hidden)`.

- **Exactly one session** → `VStack(spacing: 10) { SectionLabel(text: "Sessions"); soloSessionRow(only) }`. *"A rail needs two nodes to be a rail. One disconnected ring floating beside a single card was worse than no timeline at all."* `CentreShortList` then applies `containerRelativeFrame(.vertical, alignment: .center)` — off at accessibility sizes, where the content is taller than the container.
- **Two or more** → `HistoryRail { ForEach(sessions) { HistorySessionRow(...) } }`, **top-aligned** (`padding(.top, 26)`): *"Two cards started ~354 pt down the screen with ~230 pt of unexplained void above them … a rail starts at the top, where a list starts."*

`soloSessionRow` = `MediaRow(title: session.title, meta: isActive ? nil : line, lead: isActive ? line : nil, poster: sessionPoster, slot: .queue, hint: "Opens this session")`, `.accessibilityLabel("{title}, {line}")`. An active session's line is therefore **amber** (`lead`).

**`HistoryRail` / `HistorySessionRow`** metrics: `railX = 4` (the 1-pt rail's x-centre from the container's leading edge), `cardX = 22`, `node = 8`, `rowGap = 10`, `minRowHeight = 68`. With the screen gutter of 16 the cards start at **38**, *"exactly where Schedule's rows start."*

The rail is a **`.background`**, not a `ZStack` sibling (*"a GeometryReader beside the card would claim the whole proposed height and stretch every row"*). Per row:
- upward segment (`position != .first && != .only`): 1 × `h/2` at `x = 3.5`, `strokeStrong`
- downward segment (`position != .last && != .only`): 1 × `(h − h/2 + 10) × segment` at `x = 3.5`, `y = h/2` — the `+ rowGap` overshoot keeps the line continuous between cards
- node at `(railX − 4, h/2 − 4)`: **active** → `accent` fill with an `accentSoft` halo of `8 + 8 = 16` pt behind; **inactive** → `surfaceFlat` fill with a 1.5-pt `textTertiary` stroke. `.scaleEffect(nodeScale)`

Card: `HStack(spacing: 12) { PosterSlot(.queue); VStack(spacing: 2) { title body/textPrimary; subtitle metadata/textSecondary }; Spacer(minLength: 8); chevron.forward 13 semibold textTertiary }`, `.padding(.vertical, 12).padding(.horizontal, 14)`, `.frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)`, `.surface(.raised, radius: 16)` (white 0.11 lift + a `hairline → clear` top-edge stroke + `.card` shadow). Active → `.overlay(RoundedRectangle(16).strokeBorder(accent.opacity(0.45), lineWidth: 1))` — *"here the colour IS the state, and the ring is the only thing separating this card from its identical neighbours."* `RowPressStyle`. VoiceOver: label `"{title}, {subtitle}"`, value `"Active"` when active, `.isButton`.

The **poster is the SCOPE's**, not the franchise's: *"a season-scoped rewatch is a different picture, so the scope's poster distinguishes the sessions instead of repeating."*

**Arrival choreography** (`isNew == RewatchArrival.claim(session.id)`): `segment = 0`, `nodeScale = 0.6`; `withAnimation(uiSweep) { segment = 1 }` **completion** → `withAnimation(uiMicro) { nodeScale = 1 }`. The two never overlap — the second starts from the first's completion, not a timer. Reduce Motion → both 1 immediately.

`position(i, n)`: `n == 1 → .only`; `i == 0 → .first`; `i == n−1 → .last`; else `.middle`.

**Bar**: `.navigationTitle(franchise?.displayTitle ?? "Watch history")`, `.chromeNavigationSubtitle(historySubtitle)` (iOS 26 only; below 26 the line is **dropped**, not faked), inline, `.toolbarRole(.editor)`. Trailing overflow (only when sessions exist): `ellipsis` 15 semibold 44 × 44, label `"More actions"`, one destructive item `Label("Delete watch history…", systemImage: "trash")`.

`historySubtitle` = `"{k} watch sessions"` + `" · {n} episodes watched"` when `n > 0`, where **`n` counts only COMPLETED sessions**: *"A rewatch still running has a scope length, not a tally — counting it here is how one noun phrase came to mean two different quantities within one show."*

**`sessionLine(session)`** — one formatter behind every row:
```
started = startedAt > 0 ? "Started {dateWord}" : nil
if isActive:              [started, nextEpisode.map { "Episode {n} next" } ?? "In progress"] joined " · "
if cancelledAtEpisode:    [started, "Cancelled at episode {n}"]                              joined " · "
count = episodes > 0 ? (isCompleted ? "{n} episodes watched" : "{n} episodes") : nil
when  = completedAt > 0 ? (startedAt > 0 && startedAt < completedAt ? dateRange(start,end) : dateWord(end)) : started
result = [when, count] joined " · ", or "Dates unknown" when both are nil
```
`dateRange` states **both years** whenever the span crosses a year or sits in a year that is not the current one; otherwise both ends are month-day. *"Adjacent rows read '24 May – 29 Jul' and '10 Dec, 2024' — two formats, one of them missing its year and the other punctuated in a way no locale writes."*

`nextEpisode(session)` = `currentPart.progress + 1` for a franchise scope; that part's `progress + 1` for a part scope; `nil` when the session is not active.

### 14.6 `SessionDetailView` (Surface E)

`.sheet(item: $editing)`, `.presentationDetents([.height(min(max(contentHeight + 64, 260), 620)), .large])`, drag indicator visible. `contentHeight` is **measured** (`onGeometryChange` on the content `VStack`) — *"the sheet is exactly as tall as what is in it. At `.medium` it left 105–600 pt of dead plate below the last group."* `.scrollBounceBehavior(.basedOnSize)`, background `canvasRaised`.

`VStack(alignment: .leading, spacing: 30)`, `.padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 24)`:

1. **Identity block** — `HStack(alignment: .top, spacing: 14)`: `PosterSlot(franchise?.portraitArt, .row)` (60 × 90); `VStack(alignment: .leading, spacing: 3)`:
   - `franchise?.title ?? session.title` — `showTitleM`, `textPrimary`, 2 lines
   - `scopeLine ?? session.title` — `heroMeta`, `textSecondary`. `scopeLine` = `"Everything"` for a franchise scope, else the part's `canonicalLabel` (nil when empty). *"the sheet's title already says 'Second watch' 40 pt above this line."*
   - `spanLine` — `metadata`, `textTertiary`
   - `statusLine` (if any) — `rowMetaLead`, **`accent` when active**, else `textSecondary`
   `Spacer(minLength: 0)`

   `spanLine` is `sessionLine`'s tail **without the start date**: while the session is running the start date is not stated here *"because the row below is a date picker showing exactly that date, and 'Started 22 Aug 2026' was printed twice, 100–150 pt apart, in one sheet."*
   `statusLine` = `"In progress"` (active) · `"Stopped"` (cancelled) · `nil` (completed) — a FACT on the identity block, *"not a form row whose value looked like a control and was not."*

2. **`GroupedList`** with the one genuinely editable row:
   - `HStack { Text("Started").type(body); Spacer(); DatePicker("Started", selection: $startDate, in: ...Date(), displayedComponents: .date).datePickerStyle(.compact).labelsHidden().tint(accent) }`, `.padding(.leading, 14).padding(.trailing, 10)`, `minHeight 56`, `.accessibilityElement(children: .combine)`, label `"Start date"`, hint `"Changes the date this watch began"`
   - when `completedAt > 0`: `GroupedRow(title: "Finished", trailing: .value(dateWord(completedAt)), separator: false)` — a value, `body`, `textTertiary`. The old `"Status"` row is gone; it stated what the identity block now states.

3. **When active** — a second `GroupedList`:
   - `GroupedRow("Mark this rewatch complete", separator: true)` → fire `.success`; `store.complete(id, at: now)`; dismiss
   - `GroupedRow("Stop this rewatch…", separator: false)` → confirm (§9)

   > `RewatchStore.complete(_:at:)` existed and was called only from the mark path, so a user who abandoned a rewatch at episode 26 could only DESTROY the record — leaving the "In progress" badge and the rail's accent ring lit for ever and Today still offering the rewatch. Two non-destructive verbs, above the destructive plate, where iOS puts them.

4. **Delete** — `Button` with `Text("Delete this session…").type(body).foregroundStyle(destructive)` + `Spacer(minLength: 0)`, `.padding(.horizontal, 14)`, `minHeight 56`, `.contentShape(Rectangle())`, `.buttonStyle(GroupedRowPressStyle())`, `.surface(.plate, radius: 16)` — *"A destructive verb is a ROW in its own plate, not a red word floating centred under a void."*

**Bar**: `.navigationTitle(session.title)` (e.g. "Second watch"), inline. `.confirmationAction` → `Text("Done").type(bodyEmphasis).foregroundStyle(interactive).lineLimit(1).fixedSize()`, `RowPressStyle(radius: 12)`, `.chromeSharedBackgroundHidden()`. Action: if `startDate` (as ms) differs from `session.startedAt`, `store.setStartDate(id, to:)`; then dismiss.

`stoppedAtEpisode` (for the Stop confirmation) = the progress of the part the session covers: `currentPart?.progress ?? 0` for a franchise scope, that part's `progress ?? 0` for a part scope.

---

## 15 · Accessibility contract

### 15.1 Labels, values, hints, traits

| Element | Label | Value | Hint | Traits |
|---|---|---|---|---|
| Docked bar title | (the text) | – | – | hidden until `scrolledUnderBar` |
| Toolbar `+` | `Add {full title} to Library` | – | – | button |
| Status chip | `Change status, {status}` | – | – | button |
| Detail overflow | `More actions` | – | – | button |
| Season overflow (season screen) | `Episode actions` | – | – | button |
| Season picker (both screens) | `Season, {label}` | – | `Chooses another season` | **header** |
| Season count | `{w} of {t} watched` | – | – | – |
| Mark capsule (idle) | `Mark episode {n} watched, {title}` | – | – | button |
| Mark capsule (committed) | `Episode {n} watched` | – | – | **button removed** |
| Split chevron | `More ways to mark` | – | – | hidden while committed |
| `MarkRing` | `Episode {n}` (both states) | `Watched` / `Not watched` | `Marks as watched` / `Marks as unwatched`, `""` when non-interactive | button (+ selected when marked) |
| Row reveal glyph | `Reveal episode title` | – | – | button |
| Card reveal toggle | (the label text) | On/Off (switch) | – | switch |
| `TrailerCard` | `{title}, {meta}` | – | `Plays the video` | button, combined |
| `PersonCard` | `{name}, {role}` | – | – | **not a button** |
| Related `ShelfCard` | `{full title}, {caption}` | – | `Opens the show` | button, combined |
| `ProviderMark` | `{name}, {Subscription\|Free\|Free with ads}` | – | – | **not a button** |
| Where-to-watch header | `Where to watch, See all` | – | `Opens the streaming options` | header, button |
| Extras card (extra) | `{title}, {caption}` | `Complete` when settled | `""` | **button trait removed** |
| Extras card (unit) | `{title}, {caption}` | `Complete` when settled | `Toggles watched` | button |
| History row | `View watch history` (+ subtitle via combine) | – | – | button |
| `HistorySessionRow` | `{title}, {subtitle}` | `Active` when active | – | button |
| Scope row | `{title}, {count}` | – | – | button (+ selected) |
| Session date row | `Start date` | (the picker's) | `Changes the date this watch began` | combined |
| `EmptyState` | `copy.spokenLabel` | – | – | contains |
| `InlineNotice` retry | `Retry` | – | `Tries the request again` | button |
| Undo toast | announced as `"{message}. Undo available."` | – | – | status announcement |

**Decorative and hidden**: `EpisodeStill`, `WithheldStillTile`, `ProgressBanner`, the hero bloom, `HeroTopVeil`, `HeroCopyScrim`, `ArtScrim`, `ArtBackdrop`, `ScrollEdgeChrome`, `DetailVeils`, `DrawnCheck`, the settled badge, the scope-row tick, all rail geometry, `SectionHeaderRow`'s chevron, `MediaRow`'s chevron, `ProgressBar` (unless a `spoken` string is supplied).

The skeleton is one element labelled **`"Loading"`** with `children: .ignore`.

### 15.2 Dynamic Type (`isAX = dynamicTypeSize.isAccessibilitySize`)

| Site | Default | Accessibility |
|---|---|---|
| Hero title | `heroTitle` 28, 3 lines | `displayXL` 34, unlimited lines |
| Hero identity line | 1 line | 3 lines |
| Identity-line genre budget | 46 characters | unbounded (no trimming) |
| Card reveal toggle | trailing, on the fact row | **below the CTA**, its own row |
| `ShelfCard` title | `1...2` lines, width-pinned to the poster | `1...6` lines, full width |
| `InlineNotice` | one `HStack` line | a `VStack`, retry on its own line |
| `EmptyState` title | 3 lines (major) | unlimited |
| `EmptyState` primary button | hugging (`fixedSize(horizontal: true)`) | full width |
| `shelfScroller` mask | on | **off** (the shelf is effectively a list) |
| `CentreShortList` | centres a single session | **off** — content is taller than the container |
| `SkeletonRow` height | 88 | `@ScaledMetric`-grown |
| `MediaRow` title | 2 lines | unlimited |

Every custom Outfit token is declared `relativeTo:` a system text style, so **all** type scales; nothing here is a fixed-size font except glyph point sizes.

### 15.3 Reduce Motion

Everything routed through `ThemeMotion.pick` collapses to `uiReduced` (easeOut 0.12). Explicitly branched:

| Behaviour | Reduce Motion |
|---|---|
| Hero drift (`ArtHeader(drift: true)`) | **off** — `drifting` stays false, no `scaleEffect` animation |
| Skeleton breath | **off** — static opacity 0.92 |
| `DrawnCheck` mask | jumps to `progress = 1`, no draw |
| `seasonCompleteSweep` | jumps to `progress = 1`, no sweep |
| `milestone` | no scale bounce at all |
| `HistorySessionRow` arrival | `segment = 1`, `nodeScale = 1` immediately |
| `AnyTransition.handoff` | symmetric `.opacity` on `uiReduced`, no 80 ms delay |
| `AnyTransition.toast` | plain `.opacity`, no 4-pt rise |
| Press feedback (all button styles) | **opacity 0.72 instead of scale**; scale pinned to 1 |
| `.numericText()` rolls | crossfade instead (via `numericFact`) |

### 15.4 Reduce Transparency

- `ScrollEdgeChrome`: the `.ultraThinMaterial` layer is **not mounted**, and the veil's canvas opacity goes from `0.74` to **`1.0`** — *"a 74 % veil with nothing softening what is under it is the half-lit row under 'Library' that the hardened bar was built to end."*
- `chromeGlass` (the Start-rewatch commit bar, toasts, the SyncBanner): `surfaceFloating` + a 1-pt `strokeStrong` border instead of glass.

### 15.5 Differentiate Without Color

`DifferentiateMark` / `differentiatingUnderline` exist in the design system and are **not** used anywhere in this area. Colour-only encodings that currently have no shape carrier here: the amber lead `MarkRing`, the amber `rowMetaLead` subtitle, the amber active-session ring on a history card, the amber selection tick in the scope list. A port should either add a shape carrier or replicate the gap knowingly.

---

## 16 · DEBUG capture hooks

`FranchiseDetailView` wraps its scroll content in a `ScrollViewReader` purely so `debugDetailDrive` can drive it. The whole modifier compiles to `self` outside DEBUG.

```swift
task {
    let d = UserDefaults.standard
    let anchor  = d.string(forKey: "detailAnchor")
    let trailer = d.bool(forKey: "detailTrailer")
    let wantsRelated = d.object(forKey: "detailOpenRelated") != nil
    guard anchor != nil || trailer || wantsRelated else { return }
    try? await Task.sleep(for: .seconds(2.5))
    if let anchor { withAnimation { proxy.scrollTo("anchor-\(anchor)", anchor: .top) } }
    if trailer { video.wrappedValue = f.allVideos.first }
    let index = d.integer(forKey: "detailOpenRelated")
    if wantsRelated, f.related.indices.contains(index) { openRelated(f.related[index]) }
}
```

| Launch argument | Effect |
|---|---|
| `-openDetail <franchiseId>` | `AniTrackApp` reads `UserDefaults["openDetail"]` → `AppModel.pendingOpen` → `MainTabView` selects **Today** and replaces its path with `[DetailRoute(id:, zoomID: "alert/{id}")]`. This is the same route a tapped episode alert takes. |
| `-detailAnchor trailers\|people\|related\|watch` | 2.5 s after appearance, scrolls `"anchor-{name}"` to the top |
| `-detailTrailer 1` | 2.5 s after appearance, opens the first trailer's `VideoSheet` |
| `-detailOpenRelated N` | 2.5 s after appearance, invokes `openRelated(f.related[N])` (bounds-checked) |

Purpose (from CLAUDE.md): *"the way to photograph the show page when the simulator cannot be touched — on 3 Sep System Events saw no Simulator window and `screencapture` was refused, so cliclick had nothing to hit; `xcrun simctl io screenshot` still works."*

The anchor ids are the only consumers of `.id("anchor-trailers")` / `"anchor-people"` / `"anchor-related"` / `"anchor-watch"` on the four shelves — a port can keep them as test tags.

---

## 17 · What Android cannot reproduce directly

Severity: **blocker** = no faithful equivalent, design decision needed · **hard** = substantial custom work · **moderate** = a known library or a day of work · **easy** = a direct API swap.

| Item | Why it does not port | Severity | Recommended substitute |
|---|---|---|---|
| **Liquid Glass toolbar capsules** (`glassEffect`, `ToolbarSpacer`, `sharedBackgroundVisibility`) | iOS 26-only compositor effect. The two-items-not-a-group rule and the "no local background" rule exist entirely to manage it. | blocker | Target the **iOS 18 fallback path**, which is already fully specified: `ultraThinMaterial`-equivalent bar, no capsules, no spacer. Then the "two items" rule is moot and the glyph/pill styling in §2.5 is the whole spec. |
| **`.ultraThinMaterial` live backdrop blur** in `ScrollEdgeChrome` | Compose has no built-in live backdrop blur. | hard | API 31+: `Modifier.graphicsLayer { renderEffect = RenderEffect.createBlurEffect(...) }` on a snapshot of the content behind, or the `haze` library. Below API 31 use the **Reduce Transparency branch** (opaque `canvas` veil at 1.0, no material) — it is already a specified, shipped rendering. |
| **`.blendMode(.plusLighter)`** on the hero bloom | Compose `BlendMode.Plus` is close but needs an offscreen compositing layer to behave. | moderate | `Modifier.graphicsLayer(compositingStrategy = CompositingStrategy.Offscreen)` + `BlendMode.Plus` on the gradient brushes. Verify against the 0 → 0.13 overlap opacities. |
| **`.blur(radius: 48, opaque: true)`** on the hero's composited ground | `Modifier.blur` is API 31+; `opaque: true` (edge clamping) has no direct flag. | moderate | API 31+: `Modifier.blur(48.dp, BlurredEdgeTreatment.Unbounded)`. Below: downscale the bitmap ~8× and upscale with bilinear filtering — visually equivalent at this radius. |
| **`minimumScaleFactor`** (0.78 / 0.82 / 0.85 / 0.9 / 0.92, ~10 sites) | No Compose equivalent before `BasicText(autoSize=)`. Load-bearing: *"the hero may never ellipsize the one name the screen exists to show."* | hard | Compose 1.8+: `BasicText(autoSize = TextAutoSize.StepBased(minFontSize = size × factor, maxFontSize = size))`. Otherwise a measure-and-shrink loop via `onTextLayout`. Do **not** substitute ellipsis. |
| **`lineLimit(1...2)` ranges** (`ShelfCard`) | Compose has `minLines`/`maxLines` but not the "take your wrapped height whatever the parent proposes" semantic that `.fixedSize(vertical:)` adds. | moderate | `maxLines = 2` + `Modifier.wrapContentHeight(unbounded = true)` inside a horizontally-scrolling row; verify the two-line case in a `LazyRow`. |
| **SF Symbols** — `plus`, `ellipsis`, `chevron.forward`, `chevron.down`, **`chevron.up.chevron.down`**, `checkmark`, `eye`, `eye.slash`, `play.fill`, `play.rectangle`, `person.fill`, `photo`, `clock.arrow.circlepath`, `trash`, `wifi.slash`, `wifi.exclamationmark`, `exclamationmark.circle`, `magnifyingglass`, `bookmark`, `pause.circle`, `xmark.circle`, `play.circle`, `clock`, `checkmark.circle` | Different glyph set, different optical weights. | moderate | **ERRATUM (2026-09-04, PLAN §3.3/§9.2): `docs/android-port/spec/icon-mapping.md` is the ONLY icon authority** — family (Rounded), axes (opsz 24 / GRAD −25 / wght 500 or 400 / FILL) and vendoring form (committed static `VectorDrawable` XML, never `material-icons-extended`, never an icon font). The notes here are indicative only; where they disagree with that file, that file wins. (`chevron.up.chevron.down` → `unfold_more` and `clock.arrow.circlepath` → `history` are the two that change shape.) |
| **`.zoom` navigation transition / `zoomSource`** | Registered but **consumed by nothing** — the transition was tried 2 Sep and retired 3 Sep. | none | Ignore entirely. Detail is a plain push. |
| **`presentationDetents([.height(x), .large])`** with a *measured* content height | Compose `ModalBottomSheet` has no content-height detent. | moderate | Custom `SheetState` anchors driven by `onGloballyPositioned`; formula is `min(max(contentHeight + 64, 260), 620)`. |
| **`confirmationDialog`** (action sheet with a destructive role) | Android convention is a dialog, not a sheet. | easy | `AlertDialog` with the confirm button tinted `destructive`; keep the exact title/message/button strings from §9. |
| **`Menu`** with `Label(_, systemImage:)`, a `Section(title)` header, and a `Toggle` inside | `DropdownMenu` has no section-header primitive and no toggle item. | moderate | `DropdownMenu` + a non-clickable `Text` header row + `DropdownMenuItem` with a trailing `Switch`. Keep the item **order** exactly. |
| **`UIImpactFeedbackGenerator(intensity:)`** at 0.65 / 0.72 | Android cannot set impact intensity below API 30. | moderate | API 30+: `VibrationEffect.startComposition().addPrimitive(PRIMITIVE_CLICK, 0.65f)`. Below: `HapticFeedbackConstants.CONTEXT_CLICK` / `CONFIRM` / `REJECT`. Keep the **per-token 0.3 s / 0.04 s throttle** and the one-per-transaction rule. |
| **Reduce Transparency** | No Android system setting. | blocker | Ship the opaque branch below API 31 (where there is no blur anyway) and expose an in-app "Reduce transparency" toggle beside the existing Haptics setting. |
| **Differentiate Without Color** | No Android equivalent. | blocker | Not currently used in this area (§15.5); if adopted, gate on an in-app toggle. |
| **`isAccessibilitySize`** | Android has a continuous `fontScale`, not a named AX band. | moderate | Define `isAX = fontScale >= 1.3f` as one constant and branch on it exactly where §15.2 lists. **ERRATUM (2026-09-04, PLAN D6a/§9.2): the old parenthetical "iOS AX1 ≈ 1.35×" is arithmetically wrong.** iOS `.body` is 17 pt at `.large` and 28 pt at `.accessibility1` — a ratio of **1.647×**. 1.3 is Android's ordinary *Largest* slider, not an accessibility one, so this threshold fires a full Dynamic Type band early: it is a **deliberate divergence** recorded as PLAN D6a, not a conversion, and the AX capture compares Android 1.3 against iOS `.accessibility1`. |
| **`@ScaledMetric`** | – | easy | `dimension * LocalDensity.current.fontScale`. |
| **`onGeometryChange` scroll probe** | – | easy | `Modifier.onGloballyPositioned { -it.positionInWindow().y }` on the scroll content root. Keep the `scrollSample` quantiser and the `if new != old` guards — they are the fix for a real 60–120 Hz jank bug. |
| **`ScrollViewProxy.scrollTo(id, anchor: .center)`** | Compose scrolls by index + pixel offset, not by id + anchor. | moderate | Maintain an id→index map; `animateScrollToItem(index, scrollOffset = -(viewportHeight - itemHeight)/2)`. |
| **`contentMargins(for: .scrollContent)`** vs padding | The distinction is load-bearing (§4.6, §13.2). | easy | `LazyColumn(contentPadding = PaddingValues(bottom = …))` — Compose's content padding has the same "insets the scroll, not the stack" semantics. |
| **`safeAreaInset(edge: .bottom)`** with a glass ground | – | easy | `Scaffold(bottomBar = …)` or a `Box` with the button pinned and the list padded by its height. |
| **`WKWebView.loadHTMLString(baseURL:)`** | – | easy | `WebView.loadDataWithBaseURL("https://previously.local/trailer", html, "text/html", "utf-8", null)` + `mediaPlaybackRequiresUserGesture = false`. **Both YouTube failure modes reproduce identically**; the neutral-base-URL fix is the same. |
| **Palette extraction** | AndroidX `Palette` uses a different algorithm and will produce different tints. | moderate | Port `PaletteCache.dominantTint` and the OKLab clamps (§1.6) and `DetailTint.quiet` (§1.6) **verbatim** — the whole ground/hero-bloom system is calibrated to them. |
| **Outfit `tracking` in points** | Compose `letterSpacing` is sp or em. | easy | `letterSpacing = (tracking_pt / size_pt).em`. |
| **`.monospacedDigit()`** | – | easy | `fontFeatureSettings = "tnum"`. |
| **`.localizedCapitalized`** | – | easy | per-word `replaceFirstChar { it.titlecase(locale) }`. Note `String.normalisedProperName` (acronym-preserving title case: a word ≤ 4 chars that is already all-caps and contains a letter is left alone) exists in this file but is **not called** from this area. |
| **Non-breaking space / word joiner in copy** | – | easy | Keep U+00A0 in `plural()` and U+2060 around the range dash in `markThrough` — both fix real line-break bugs. |
| **Live Activities / Dynamic Island** | – | n/a | Not used in this area. |
| **Atomic JSON + one backup generation** (`RewatchStore`) | – | easy | Write to a temp file and `renameTo`, after copying the current file to `.backup.json`. |

