# AppModel, Write Policy, SyncCenter, RewatchStore, Routing

This is the brain of *Previously.* — the one object every screen reads from and writes through. `AppModel` is a single main-thread-confined observable store that owns the signed-in account's library, a 20-second wall clock, the search subsystem, all derived feeds (Today's stacks, the Schedule agenda, the Library shelves), and every mutation the app can perform. `SyncCenter` is a separate singleton that owns *trust*: how fresh the data is, whether the device has a network path, and which of the user's writes the server never accepted (persisted across launches). `RewatchStore` is a device-local JSON store of watch sessions. `Routing` is one 10-line value type (`DetailRoute`) plus the per-tab navigation stacks in `MainTabView`. The rules that make this subsystem correct are not obvious from the type signatures: **a progress mark never rolls back, membership and status writes always do**; **one progress PUT is in flight per part, newest-wins, superseded targets are dropped**; **every derived "is it out / when is the next one" question is computed from the per-episode `airings` list, never from the catalogue's counters**; and **the library has an offline copy on disk so a launch with no network opens on the shows, not on an error**. A port that gets the pixels right and these rules wrong is wrong.

Source files specified here (all under `ios/`):
`Sources/App/AppModel.swift` (1375 lines), `Sources/App/AppModel+Writes.swift`, `Sources/App/AppModel+States.swift`, `Sources/App/SyncCenter.swift`, `Sources/App/RewatchStore.swift`, `Sources/App/Routing.swift`. Supporting reads: `Sources/Models/Models.swift`, `Models+Shared.swift`, `Util/Formatting.swift`, `DesignSystem/Copy.swift`, `DesignSystem/UndoToast.swift`, `DesignSystem/ThemeTokens.swift`, `App/RootView.swift`, `App/AniTrackApp.swift`.

---

## 1. Concurrency model

| Aspect | iOS | Android equivalent |
|---|---|---|
| Isolation | `@MainActor @Observable final class AppModel` — every stored property and every method is main-actor isolated. There is **no** background mutation of model state anywhere. | A single `@Stable` state holder scoped to the signed-in session; all mutations on `Dispatchers.Main.immediate`. |
| Observation | Swift `@Observable` (per-property dependency tracking). Reading `library` in a Compose-equivalent body subscribes that body to `library` only. | `mutableStateOf` per field, or a `StateFlow` per field. **Do not collapse into one immutable `UiState` data class** — see §5.3, the scroll/tick invalidation rules depend on fine-grained observation. |
| Async work | Unstructured `Task { }` handles held in the model, cancelled explicitly in `teardown()`. Detached, low-priority `Task.detached(priority: .utility)` for the two disk writes only. | `viewModelScope`/session `CoroutineScope` with named `Job`s in the same map/field shape; `Dispatchers.IO` for the disk writes. |
| Out-of-order protection | Two monotonic sequence counters, `searchSeq` and `reloadSeq`. Every fired request captures the next value; a response mutates state only if its captured value still equals the current one. `teardown()` bumps **both**, which invalidates every in-flight response at once. | Identical integer-token pattern. Do **not** substitute `collectLatest` alone — `teardown()` must be able to invalidate responses that were already awaiting. |
| Serialisation of writes | One `Task` per `mediaId` in `progressLane: [Int: Task<Void, Never>]`, draining a one-slot mailbox `progressQueued: [Int: ProgressWrite]`. See §7.2. | One `Channel(capacity = CONFLATED)` + collector coroutine per `mediaId`, or the same lane/mailbox map. |
| `SyncCenter` | `@MainActor @Observable final class`, `static let shared`. Stored state (it cannot be an extension of `AppModel` because Swift extensions cannot add stored properties — that is the stated reason it is a singleton). | Session-scoped singleton object; same main-thread confinement. |
| `RewatchStore` | `@MainActor @Observable final class`, `static let shared`, init loads synchronously from disk. | Same; the synchronous load at construction is load-bearing (Detail reads it in composition). |

`nonisolated static let log = Logger(subsystem: "app.previously", category: "model")` — the only logging in the file; used once, for a failed library reload, at `.error` with `privacy: .public`.

---

## 2. Constants

All time values are milliseconds unless noted. `Formatting.D = 86_400_000`, `Formatting.H = 3_600_000`, `Formatting.minuteMs = 60_000`.

| Constant | Value | Meaning |
|---|---|---|
| `AppModel.soonWindow` | `48 * H` = 172 800 000 | "Airing soon" lookahead. |
| `AppModel.newLookback` | `3 * D` = 259 200 000 | Fallback "out now" window when `/me/opened` never answered. |
| `AppModel.outNowWindow` | `7 * D` = 604 800 000 | How recent an unwatched drop stays "Out now". |
| `AppModel.scheduleBack` | `-7` | Calendar feed span, days before today. |
| `AppModel.scheduleAhead` | `14` | Calendar feed span, days after today. |
| `AppModel.clockTick` | `20` (seconds) | Wall-clock tick period. Countdowns are minute-grained; 20 s guarantees ≤20 s of lag. |
| `AppModel.recentsKey` | `"recentSearches"` | UserDefaults key, `[String]`. |
| `AppModel.recentItemsKey` | `"recentSearchItems"` | UserDefaults key, JSON `[FranchiseSummary]`. |
| `AppModel.maxRecents` | `10` | Cap for both recents lists. |
| `AppModel.staleReloadAfter` | `2 * minuteMs` = 120 000 | Away-time past which returning to foreground triggers `reload()`. |
| `AppModel.newVisitAfter` | `6 * H` = 21 600 000 | Away-time past which returning also re-stamps `/me/opened`. |
| `AppModel.nowBarLiveWindow` | `24 * H` | How long a fresh unwatched drop holds the Now Bar's LIVE state. Deliberately tighter than `outNowWindow`. |
| `AppModel.premiereShelfWindow` | `45 * D` | Window inside which an announced-but-unaired season earns a slot on the Watching shelf. |
| Search debounce | `300 ms` | `Task.sleep` before `runSearch`. |
| Celebration lifetime | `1300 ms` | `justCaught` membership. |
| Notice lifetime | `2.5 s` | `showNotice`. |
| `SyncCenter.toastSeconds` | `6.0`, or `10.0` while VoiceOver runs | Undo toast lifetime. |
| `SyncCenter.errorSeconds` | `4.0`, or `8.0` while VoiceOver runs | Error toast lifetime. |
| `SyncCenter.directErrorWindow` | `30_000` | A re-recorded failure inside this window of a user-pressed Retry earns one error haptic. |
| `DataClass.exactAiring.threshold` | `30 * minuteMs` | |
| `DataClass.dateOnlySchedule.threshold` | `6 * H` | |
| `DataClass.catalogue.threshold` | `24 * H` | |
| `SyncCenter.storeKey` | `"previously.sync.failedChanges"` | UserDefaults key for the failure list. |
| Haptics preference key | `"previously.haptics"` | Default `true` when absent. |

**Why `clockTick` is 20 s and toast lifetimes are not hard-coded** — quoting the source: *"Toast lifetimes live on `SyncCenter` (`toastSeconds` / `errorSeconds`), which is the only thing that knows whether VoiceOver is running. These two constants were the reason that knowledge never reached the live timer: `SyncCenter.toastSeconds` was declared, documented and never called, while the sleep below used a hard-coded 6 — so an Undo a VoiceOver user could not reach in time was still exactly 6 seconds long."*

---

## 3. State inventory

### 3.1 Library and account

| Property | Type | Initial | Notes |
|---|---|---|---|
| `library` | `[Franchise]` | `[]` | The whole signed-in library. `didSet` recomputes `libraryIds = Set(library.map(\.id))` and does `libraryVersion &+= 1` (wrapping add). |
| `libraryVersion` | `Int` (`@ObservationIgnored`, private) | `0` | Cache key for the schedule feed. **Not observable** — bumping it must not invalidate views. |
| `libraryIds` | `Set<String>` (`private(set)`) | `[]` | O(1) membership. The Discover grid calls `isInLibrary` per card per animating frame; a linear scan there was the reason this mirror exists. |
| `pendingAdds` | `Set<String>` (`private(set)`) | `[]` | Optimistically added, not yet confirmed by a reload. |
| `prevOpenedAt` | `Int64` | `0` | From `POST /me/opened`; drives "since you were last here". |
| `loading` | `Bool` | `true` | A library request is in flight. |
| `lastLoadedAt` | `Int64` | `0` | Epoch-ms of the last payload that actually **arrived**. The app's single freshness stamp. |
| `surfaceReady` | `Bool` | `false` | Set `true` by `RootView.handOffIfReady()` once the splash has left. Today's recap waits on it. |
| `loadError` | `Bool` | `false` | Last library refresh failed (never a cancellation, never a 401). |
| `localProgress` | `[Int: LocalWrite]` (private) | `[:]` | Optimistic progress overlay keyed by `mediaId`. See §7.4. |
| `onSessionExpired` | `(@MainActor () -> Void)?` | `nil` | Installed in `AniTrackApp.init`; calls `auth.sessionExpired()`. |
| `pendingOpen` | `String?` | `nil` | A franchise id a tapped episode alert (or `-openDetail`) asks to open. §10.3. |

### 3.2 Clock

| Property | Type | Notes |
|---|---|---|
| `now` | `Int64` | Epoch-ms, refreshed every 20 s and on foreground. `didSet` truncates to the minute and writes `nowMinute` **only when the minute actually changes**. |
| `nowMinute` | `Int64` (`private(set)`) | `now` floored to the minute. Screens whose every fact is minute-grained (Schedule) observe **this**, so the 20 s tick does not re-lay them out three times a minute for nothing. |

### 3.3 Search / discover

| Property | Type | Initial | Notes |
|---|---|---|---|
| `searchQuery` | `String` | `""` | `didSet` sets `searchExactOnce = false` then calls `scheduleSearch()`. |
| `searchResults` | `[FranchiseSummary]` | `[]` | Unfiltered; the media chip is applied by `filteredSearchResults`. |
| `searchBusy` | `Bool` | `false` | |
| `searchError` | `Bool` | `false` | |
| `searchCorrection` | `SearchCorrection?` | `nil` | The server's spell repair. Present **only when corrected ≠ original, case-insensitively** — "showing results for X" that echoes X back is noise. |
| `searchSources` | `[String: String]?` | `nil` | Per-catalogue outcome, `"anilist"`/`"tmdb"` → `"ok"` / `"failed"` / `"disabled"`. A TMDB outage must render as a notice, not as "no TV results". |
| `searchExactOnce` | `Bool` (private) | `false` | Opts exactly one request out of server correction (`&exact=1`). Any keystroke clears it. |
| `lastScheduledQuery` | `String` (private) | `""` | The trimmed text the last search was scheduled for. |
| `recentSearches` | `[String]` | from UserDefaults | Most-recent-first, de-duplicated case-insensitively, capped at 10. |
| `recentItems` | `[FranchiseSummary]` | from UserDefaults | Shows opened or added *from* a search. Apple Music's model: the things you found, not the strings you typed. |
| `trending` | `[FranchiseSummary]` | `[]` | Chart for the search zero-state and Today's empty-account billboard. |
| `trendingTask` | `Task?` (private) | `nil` | |
| `trendingLoading` | computed `Bool` | — | `trending.isEmpty && trendingTask != nil`. Today holds a skeleton on this rather than flashing "Nothing to watch yet" for ~300 ms. |
| `searchFieldRequested` | `Bool` | `false` | A CTA elsewhere asked for the search *field*, not just the tab. `DiscoverView` consumes and clears it. |
| `mediaFilter` | `MediaFilter` | `.all` | **Search only.** Today/Schedule/Library always show everything; a filter set once while browsing used to silently hide half of what aired. |

`MediaFilter` is `.all` / `.anime` / `.tv`, raw values `"all"`/`"anime"`/`"tv"`, chip labels **`"All"`**, **`"Anime"`**, **`"TV"`**.

### 3.4 Transients

| Property | Type | Notes |
|---|---|---|
| `justCaught` | `Set<String>` | Franchise ids currently celebrating; entries expire after 1300 ms. Read by `outNow` (to keep a just-caught row on screen through its celebration) and by Today's queue. |
| `undo` | `UndoState?` | The single live Undo toast. |
| `errorToast` | `String?` | Transient write-failure message. |
| `notice` | `String?` | Neutral receipt with no action ("Episode alerts on"). |

### 3.5 Task handles (all private, all cancelled in `teardown()`)

`clockTask`, `searchTask`, `trendingTask`, `undoTask`, `errorTask`, `noticeTask`, `ccTasks: [String: Task]` (celebration timers, keyed by franchise id), `progressLane: [Int: Task]`, plus the non-task `progressQueued: [Int: ProgressWrite]` and `backgroundedAt: Int64?`.

---

## 4. Lifecycle

### 4.1 `init(api:)`

Stores the API client, then synchronously hydrates recents:
```
recentSearches = UserDefaults.stringArray(forKey: "recentSearches") ?? []
recentItems    = (try? JSONDecoder().decode([FranchiseSummary].self,
                     from: UserDefaults.data(forKey: "recentSearchItems"))) ?? recentItems
```
A decode failure leaves `recentItems` empty; it is never an error.

### 4.2 `start()`

Called from `RootView` as `.task(id: auth.isSignedIn) { appModel.start() }` on the signed-in branch — i.e. on every transition into signed-in. Order matters:

1. `startClock()`.
2. Install `SyncCenter.shared.replay = { [weak self] intent in await self?.replay(intent) }` — this is what lets a failure restored from a *previous launch* re-issue its actual write instead of merely reloading.
3. **Offline copy**: if `library.isEmpty` and a cache file decodes, adopt it:
   `library = cached.response.franchises`; `prevOpenedAt = max(prevOpenedAt, cached.response.prevOpenedAt)`; `lastLoadedAt = cached.savedAt` — the cache's **real** save time, so `StaleStrip` and `InlineNotice` tell the truth rather than claiming the data is fresh.
4. `Task { await stampOpened() }` and `Task { await reload() }` — two independent tasks, deliberately not sequenced.

### 4.3 `stampOpened()`

`POST /me/opened` → `prevOpenedAt = res.prevOpenedAt`. On any error: swallowed, no UI. `/me/opened` is explicitly **not** idempotent/retryable — it stamps `lastOpenedAt` and returns the *previous* value, so a replay would return "now" and destroy "since you were last here". Falls back to a 3-day lookback (`effectivePrev`).

### 4.4 `reload()`

```
reloadSeq += 1; let seq = reloadSeq
loading = true
GET /me/library
```
On success — and only if `seq == reloadSeq` (a newer reload or a `teardown()` invalidates it; *"applying it would resurrect state we just tore down"*):

1. `library = reconcileLocalProgress(res.franchises, seq: seq)` (§7.4).
2. `if res.prevOpenedAt > 0 { prevOpenedAt = max(prevOpenedAt, res.prevOpenedAt) }`.
3. `withAnimation(ThemeMotion.uiGentle) { loadError = false }` — **animated at the source**: the "couldn't refresh" footnote carries a fade transition that only runs if an animation is in the transaction; without it the line snapped in and shoved the queue under it by 28 pt.
4. `loading = false`; `lastLoadedAt = .nowMs`; `persistLibrary(res, at: lastLoadedAt)`.
5. `await syncAmbient()`.

On `APIError.unauthorized` (guarded by `seq`): `handleSessionExpired()` → `teardown()` then `onSessionExpired?()`. **This is not a load failure** — retrying cannot fix a dead session and "the server couldn't be reached" would be a lie.

On any other error (guarded by `seq`): `loading = false`; **if `error.isCancellation`, return silently** (a pull-to-refresh torn down, or a superseding reload, must not raise a footnote over good content); else log and `withAnimation(ThemeMotion.uiGentle) { loadError = true }`.

`Error.isCancellation` is true for `CancellationError`, `URLError.cancelled`, and `APIError.transport(URLError.cancelled)`.

### 4.5 `teardown()` — full account teardown

Run on every sign-out, voluntary (`RootView.onChange(of: auth.isSignedIn)`) or forced (401). Anything that outlives the view tree must be dismantled here or it keeps serving the previous account.

Order, exactly:
1. `RewatchStore.shared.reset()`; `SeasonSweepLedger.reset()`; `clearCachedLibrary()` (delete `library-cache.json`).
2. Cancel and nil: `clockTask`, `searchTask`, `trendingTask`, `undoTask`, `errorTask`, `noticeTask`; `notice = nil`.
3. Cancel every `ccTasks` value, clear the map.
4. Cancel every `progressLane` value, clear `progressLane` **and** `progressQueued`.
5. `SyncCenter.shared.teardown()` — *"the next account must not inherit this one's failed writes — a Retry there would send the previous user's mark into the new user's library."*
6. `searchSeq += 1; reloadSeq += 1` — invalidates every in-flight response.
7. Reset: `library = []`, `pendingAdds = []`, `localProgress = [:]`, `prevOpenedAt = 0`, `loadError = false`, **`loading = true`** (so the next sign-in mounts on the loader, not on an empty shelf), `backgroundedAt = nil`.
8. Reset search: `lastScheduledQuery = ""`, `searchQuery = ""` (its `didSet` clears the results/busy/error triad), then explicitly `searchResults = []`, `searchBusy = false`, `searchError = false`, `searchCorrection = nil`, `searchSources = nil`, `trending = []`, `searchFieldRequested = false`, `mediaFilter = .all`.
9. `justCaught = []`, `undo = nil`, `errorToast = nil`.
10. `EpisodeNotifications.shared.cancelAll()`; `AiringLiveActivityManager.shared.endAll()`.

`surfaceReady` and `lastLoadedAt` are **not** reset here (`lastLoadedAt` is reset only implicitly by the next load; `SyncCenter` reads it through a closure and reports "Not synced yet" when it is 0).

### 4.6 Scene lifecycle

```
sceneEnteredBackground() { backgroundedAt = .nowMs }

sceneBecameActive() {
    now = .nowMs                                   // the 20s tick task was suspended
    guard let bg = backgroundedAt else { return }  // launch activation — start() covers it
    backgroundedAt = nil
    let away = now - bg
    guard away >= staleReloadAfter else { return } // < 2 min: nothing to do
    Task {
        if away >= newVisitAfter { await stampOpened() }   // ≥ 6 h: a NEW visit
        await reload()
    }
}
```
The two thresholds are separate on purpose: brief app switches must not wipe "Out now" by re-stamping `/me/opened`.

`RootView` wires this from `@Environment(\.scenePhase)`, gated on `auth.isSignedIn`.

### 4.7 Ambient sync

```
private func syncAmbient() async {
    await EpisodeNotifications.shared.sync(library: library, now: .nowMs)
    AiringLiveActivityManager.shared.sync(library: library, now: .nowMs)
}
```
Called after `reload()` succeeds, after a successful `setStatus`, after a successful `removeFromLibrary`, and from `alertsWereAllowed()` (the notification primer's Allow) — *"They used to wait for the next reload — 'Turn on' granted permission and scheduled nothing, so the first alert could be a day away."*

### 4.8 The offline library copy

| Fact | Value |
|---|---|
| Path | `applicationSupportDirectory/library-cache.json` (directory created with `withIntermediateDirectories: true` at first access) |
| Shape | `{ "response": <LibraryResponse>, "savedAt": <Int64 epoch-ms> }` |
| Written | after **every** successful `reload()`, on a detached `.utility` task, `Data.write(options: .atomic)` — *"Atomic, so a launch can never read a half-written file."* |
| Read | once, in `start()`, only when `library.isEmpty` |
| Deleted | in `teardown()` — *"The copy belongs to the account that fetched it; sign-out removes it."* |
| Failure mode | every read and write is `try?`; a corrupt or missing file is simply "no cache". |

`savedAt` is the cache's own timestamp, adopted as `lastLoadedAt` — so a launch from cache immediately shows the honest stale strip.

**Android:** `filesDir`/`noBackupFilesDir` + `kotlinx.serialization`; write to a temp file and `renameTo` for atomicity. Straightforward.

### 4.9 Clock task

```
clockTask = Task { while !Task.isCancelled {
    try? await Task.sleep(for: .seconds(20))
    await MainActor.run { self?.now = .nowMs }
} }
```
`startClock()` cancels any previous task first. **Android:** a `while(isActive) { delay(20_000); now = System.currentTimeMillis() }` coroutine, or `tickerFlow`. Note that the Swift task keeps running while backgrounded until iOS suspends the process; the `sceneBecameActive` snap exists precisely because it may have missed ticks.

---

## 5. Derived state

Everything in this section is **computed**, never stored. Only `scheduleDays` is memoised (§5.7).

### 5.1 Trivial helpers

| Member | Definition |
|---|---|
| `isInLibrary(_ id:)` | `libraryIds.contains(id) \|\| pendingAdds.contains(id)` |
| `filteredSearchResults` | `searchResults.filter { matchesMediaFilter($0.source) }` — the **only** surface `mediaFilter` touches. |
| `franchise(id:)` | `library.first { $0.id == id }` |
| `source(of:)` | library → searchResults → trending, in that order; `nil` when genuinely unknown (callers must treat `nil` as "not AniList", never guess). |
| `matchesMediaFilter(_:)` | `.all` → true; `.anime` → `source == .anilist`; `.tv` → `source == .tmdb`. |
| `libraryEmpty` | `library.isEmpty` |
| `effectivePrev` | `prevOpenedAt > 0 ? prevOpenedAt : now - newLookback` |
| `lastAiredKey(_:)` (private) | `f.lastAired(now: now) ?? 0` — the **airings-advanced** recency, not the catalogue field. |

### 5.2 `airingFranchises`

```
library.filter { $0.releasingPart != nil && $0.tracksAirings }
```
`Franchise.tracksAirings` is `effectiveStatus != .planned`. **Never media-filtered** — *"what aired today is a fact about your library, not about a chip you last touched in search."*

The `planned` exclusion is load-bearing: without it *"a mid-broadcast show you had only shelved arrived on Today as '20 episodes behind' and on Schedule with a mark ring whose action was 'Mark 20 episodes as watched' — an obligation invented out of a bookmark."*

### 5.3 The freshness ladder (read this before implementing any feed)

The server sends three catalogue counters per part — `airedEpisodes`, `lastAiredAt`, `nextAiringAt` — advanced by an **hourly** cron. It also sends `airings: [{episode, at}]`, the per-episode calendar. **Every "is it out / when is the next one" question is answered from `airings`, with the counters as a floor.** Reading only the counters made the one show that had just aired (Re:ZERO, 6:30 PM) the one show Today could not see, for up to an hour: not fresh (count unchanged), not waiting (slot passed) — gone.

The anchor-aware primitives on `FranchisePart` (`anchor` = `.local` for AniList, `.utcDate` for TMDB):

```
passedAirings(now, anchor) = airings.filter {
    anchor.isDateOnly ? dayDiff(ts: $0.at, now: now, anchor: anchor) < 0   // the day AFTER
                      : $0.at <= now                                       // the instant itself
}
airedByNow(now, anchor)  = isReleasing ? max(airedEpisodes, passedAirings.map(\.episode).max() ?? 0)
                                       : airedEpisodes
behind(now, anchor)      = isReleasing ? max(0, airedByNow - progress) : 0
lastAired(now, anchor)   = max(lastAiredAt, passedAirings.map(\.at).max())        // nil if both nil
upcomingAiring(now, anchor) = airings.filter { anchor.isDateOnly ? dayDiff >= 0 : $0.at > now }
                                     .map(\.at).min()
                              ?? (scheduledAiring(now, anchor) where date-only || slot > now)
```
`scheduledAiring` returns `nextAiringAt` only when `dayDiff(nextAiringAt, now, anchor) >= 0` — *"A `nextAiringAt` in the past is STALE DATA, not a schedule."* Same-day is kept.

Franchise-level wrappers pass the franchise's own anchor and must be preferred: `Franchise.nextAiring(now:)`, `Franchise.lastAired(now:)`, `Franchise.dayKey(of:)`, `Franchise.dayDiff(of:now:)`.

The raw sort keys still exist and are still correct for *calm* surfaces only: `nextAiringSortKey = releasingPart?.nextAiringAt ?? .max`, `lastAiredSortKey = releasingPart?.lastAiredAt ?? 0`.

`releasingPart` itself: among `parts.filter(\.isReleasing)`, prefer the one with a non-nil `nextAiringAt` and the soonest such value; otherwise the one with the greatest `lastAiredAt ?? 0`; `nil` when nothing is releasing.

### 5.4 Today's stacks

**`outNow`** — releasing parts with a recently-aired **unwatched** episode:
```
airingFranchises
  .filter { f in
      guard let part = f.releasingPart else { return false }
      let behind = part.behind(now: now, anchor: f.timeAnchor)
      guard behind > 0 || justCaught.contains(f.id) else { return false }
      return now - (part.lastAired(now: now, anchor: f.timeAnchor) ?? 0) <= outNowWindow
  }
  .sorted { lastAiredKey($0) > lastAiredKey($1) }          // descending recency
```
Two subtleties: (a) keyed on *unwatched-ness + recency*, **not** on `prevOpenedAt` — the old last-open comparison made a new episode vanish from Today the second time you opened the app, watched or not; (b) the `justCaught` escape hatch — `behind` drops to 0 the instant progress is written, *"which would otherwise yank the row (and the frame its result state renders on) before it is ever seen."*

**`soon`** — a genuine wait inside 48 h:
```
airingFranchises.filter { next = $0.nextAiring(now: now); next != nil && (next - now) > 0 && (next - now) <= soonWindow }
                .sorted { ($0.nextAiring(now:now) ?? .max) < ($1.nextAiring(now:now) ?? .max) }
```

**`nextUp`** — soonest upcoming airing across all airing franchises, *not* limited to 48 h:
```
airingFranchises.compactMap { f in f.nextAiring(now: now).map { (f, $0) } }.min { $0.1 < $1.1 }?.0
```
Documented invariant: *"this is the 'waiting' hero and the all-caught-up line, so every slot it yields must still be a genuine WAIT."* A date-only TV drop legitimately stays "up next" for the whole of its day (its clock is synthesized, the labels are day-granular); an AniList slot that has struck can never appear here because `upcomingAiring` has already moved to the following slot — which is what prevents "lands Today 9:00 AM" being rendered at 8 pm.

**`keepWatching`** — mid-watch backlog not already in Out now:
```
library.filter { $0.effectiveStatus == .watching && !outNowIds.contains($0.id) && $0.resumePart != nil }
       .sorted { continueBacklog desc, then title.localizedCaseInsensitiveCompare ascending }
       .prefix(8)                                  // "Today is a glance, not the whole library"
```

**`nowBarItem`** — one global answer to "when", deliberately mirroring the Live Activity's one-soonest-episode model so the lock screen and Today tell the same story:
```
struct NowBarItem: Equatable { enum State { case live, next }
                               let franchiseId: String; let state: State; let at: Int64 }
```
1. If `outNow.first` has a `lastAired`, compute `fresh`:
   - date-only source → `f.dayDiff(of: last, now: now) == 0` (same day; there is no real instant to measure hours against)
   - timed source → `now - last <= nowBarLiveWindow` (24 h)
   If fresh → `.live` at `last`.
2. Else if `nextUp` has a `nextAiring` → `.next` at that instant.
3. Else `nil` — *"the bar collapses to nothing (Today must not nag with an idle strip)."*

### 5.5 `ShelfState` and `watchingShelf`

```
enum ShelfState: Int {          // rawValue ascending IS the shelf order
    case newEpisode = 0         // unwatched episode aired recently — NEW badge
    case backlog                // something to resume ("S3 · E4 · 7 left")
    case airingWait             // caught up, next episode dated ("Sun · 3d")
    case premiereSoon           // announced season premiering within 45 days ("S3 · Oct 12")
}
```
`shelfState(of:)`, first match wins, `nil` = dormant (caught up with nothing dated, so it is off the shelf):

1. `.newEpisode` — `releasingPart.behind(now:anchor:) > 0` **and** `now - (releasingPart.lastAired(now:anchor:) ?? 0) <= outNowWindow`.
2. `.backlog` — `f.resumePart != nil`.
3. `.airingWait` — `releasingPart.isCaughtUp` **and** `f.nextAiring(now:) != nil`. Using `nextAiring` (not the raw `nextAiringAt`) is what stops a stale slot claiming "today" for days on end, *"in the franchise's OWN calendar, so a date-only TV slot doesn't expire a day early."*
4. `.premiereSoon` — `nextPremiere(of: f)` exists and `premiere - now <= premiereShelfWindow`. A dated premiere months out, or TBA, is noise on a "what am I watching" rail and is deliberately dropped.

`nextPremiere(of:) = f.parts.compactMap(\.premiereAt).filter { $0 > now }.min()`, where `FranchisePart.premiereAt = isUpcoming ? nextAiringAt : nil` and `isUpcoming = (status == "NOT_YET_RELEASED")` — keyed on status **alone**, because a catalogue that publishes an announced season's planned episode count (TMDB does) would otherwise masquerade as released.

`watchingShelf`:
```
library.filter { $0.effectiveStatus == .watching }
       .compactMap { f in shelfState(of: f).map { (f, $0) } }
       .sorted { a, b in
           if a.state != b.state { return a.state.rawValue < b.state.rawValue }
           switch a.state {
           case .newEpisode:   return a.f.lastAiredSortKey > b.f.lastAiredSortKey   // freshest drop
           case .backlog:      return a.f.continueBacklog > b.f.continueBacklog     // biggest backlog
           case .airingWait:   return a.f.nextAiringSortKey < b.f.nextAiringSortKey // soonest airing
           case .premiereSoon: return (nextPremiere(a.f) ?? .max) < (nextPremiere(b.f) ?? .max)
           }
       }.map(\.f)
```

### 5.6 `resumePart` / `continueBacklog` (Models.swift, quoted because the ordering rule is subtle)

Over `episodicParts` (kinds `.season`, `.ona`, `.ova`, sorted by `sequence` ascending), with `available(p) = p.availableEpisodes()` (`0` if `isUpcoming`, else `airedEpisodes > 0 ? airedEpisodes : totalEpisodes`):

1. the first part that is **mid-watch** (`progress > 0 && progress < available`), else
2. the first part **after** the highest-sequence fully-watched part that still has something left, else
3. the first part with anything left.

*"Picking by sequence (not by largest backlog) is the point: a max() would resume S3 at 3/10 into an untouched S5 just because S5 is longer. With non-sequential progress (S2 untouched, S3 half-watched) the mid-watch part still wins."*

`continueBacklog = max(0, available(resumePart) - resumePart.progress)`, `0` when `resumePart == nil`.

### 5.7 The Schedule agenda

```
struct ScheduleEntry: Identifiable {
    let franchise: Franchise; let part: FranchisePart
    let episode: Int; let at: Int64; let aired: Bool
    var id: String { "\(franchise.id)/\(part.mediaId)/\(episode)" }
    var dateOnly: Bool { franchise.timeAnchor.isDateOnly }
    var watched: Bool { aired && part.progress >= episode }
}
struct ScheduleDay: Identifiable {
    let id: Int          // day offset from today, negative = past
    let noon: Int64      // LOCAL NOON of the day — day arithmetic and labels never hit a DST seam
    var isToday: Bool { id == 0 }
    var isPast: Bool { id < 0 }
    let entries: [ScheduleEntry]
}
```

`scheduleTodayNoon` = `nowMinute - (hour*H + minute*minuteMs) + 12*H`, with `hour`/`minute` from `Formatting.localParts(nowMinute)` (device-local calendar). Subsequent days are `noon + offset * D` — plain ms arithmetic, safe because a ±1 h DST shift cannot move noon out of its day.

`buildScheduleDays()`:
```
now      = nowMinute
noon     = scheduleTodayNoon
todayKey = Formatting.localDayKey(noon)              // local anchor
buckets: [Int: [ScheduleEntry]] = [:]

for f in library where f.tracksAirings {             // planned shows are OFF the calendar
  for part in f.parts {                              // EVERY part, not only the releasing one
    for a in part.scheduleAirings {
      offset = Int((f.dayKey(of: a.at) - todayKey) / D)     // bucket in the SOURCE's calendar
      guard (-7...14).contains(offset) else { continue }
      aired = f.timeAnchor.isDateOnly ? offset <= 0 : a.at <= now
      buckets[offset, default: []].append(ScheduleEntry(...))
    }
  }
}

return (-7...14).compactMap { offset in
    entries = buckets[offset].sorted by (at asc, then franchise.title asc, then episode asc)
    guard offset == 0 || !entries.isEmpty else { return nil }   // TODAY IS ALWAYS PRESENT
    return ScheduleDay(id: offset, noon: noon + offset*D, entries: entries)
}
```

Four rules encoded here that a port must not "simplify":

* **Every part, not only the releasing one.** *"a season that premieres inside the window is announced, not releasing, and a finale that aired three days ago belongs to a finished part. The window is the filter, not the part's status."* The **show's** status *is* a filter (`tracksAirings`), and this is deliberately written as a `library` walk rather than `airingFranchises` (which is releasing-only) — an announced season premiering inside the window has no releasing part and still belongs here.
* **Bucket by the source's own calendar.** `f.dayKey(of:)` reads a TMDB timestamp in UTC; reading its synthesized 17:00 UTC instant locally filed it a day late east of UTC+7. `Formatting.localDayKey` normalises both anchors into one comparable space (midnight-UTC ms of the resolved y/m/d), so the subtraction is valid.
* **`aired` uses a different rule from `passedAirings`.** For a date-only source the whole day counts (`offset <= 0`), not the day after — *"a TMDB drop is out at some point on its day, and the calendar cannot know when, so the whole day counts (the row can be marked from the morning on)."*
* **Today's section is always emitted, empty or not**, and "today" always means day 0. With the empty section skipped the feed opened on a future day, the "Today" button hid itself (`selectedDay == landing` — by its own test you were already there), and a row's bare clock read as tonight.

`FranchisePart.scheduleAirings` is the compatibility shim: return `airings` when non-empty, otherwise synthesise from the two slots every server has always published — `Airing(episode: airedEpisodes, at: lastAiredAt)` when `lastAiredAt > 0 && airedEpisodes > 0`, plus `Airing(episode: nextEpisodeNumber ?? airedEpisodes + 1, at: nextAiringAt)` when `nextAiringAt > 0` and that episode number is not already present — sorted ascending by `at`. Against such a server a weekly show appears once, not weekly.

**Caching.** `scheduleDays` is memoised:
```
struct ScheduleFeedKey: Equatable { let library: Int; let minute: Int64 }
var scheduleFeedKey: ScheduleFeedKey { .init(library: libraryVersion, minute: nowMinute) }
@ObservationIgnored private var scheduleCache: (key: ScheduleFeedKey, days: [ScheduleDay])?
```
`scheduleDays` returns the cached days when the key matches, else rebuilds and stores. Reason, quoted: *"This used to be a bare computed property, and `ScheduleView` read it through a dozen of its own computed properties — about thirty full rebuilds per body evaluation."* Screens are expected to key their own derivations on `scheduleFeedKey` rather than walking the feed again.

**Android:** `derivedStateOf`/`remember(feedKey)` gives the same memoisation; the key must be `(libraryVersion, nowMinute)` and the cache field must not be observable.

### 5.8 The Library crate

```
enum LibShelf: Int, CaseIterable, Identifiable { case planned, comingBack, watching, finished }
```
Case order **is** shelf order on screen: Planned leads (*"the library is where you browse what to start next — Today already fronts what you're watching"*), then Coming back, Watching, Finished. The enum deliberately carries **no `label`** — the on-screen name lives on `LibrarySection.label` in LibraryFacts, so a second vocabulary cannot drift ("Coming back" vs "Returning").

`libShelf(of:)`, first match wins:
1. `effectiveStatus == .planned` → `.planned`
2. `effectiveStatus == .watching` → `.watching`. The user's own word outranks every derived signal — *"a finished series they've marked Watching sits on Watching instead of being filed under Finished while the context menu shows a tick next to Watching."*
3. `announced = f.upcoming.map { $0.isFutureInstallment && !$0.hasArrived(now: now) } ?? false`; if `announced || nextPremiere(of: f) != nil` → `.comingBack`
4. else `.finished`

`FranchiseUpcoming.isFutureInstallment` is true for status `"upcoming_dated"`, `"announced"`, `"announced_no_date"`, `"rumored"`. `hasArrived(now:)` is true only for a **day-precision** curated date whose UTC day is strictly in the past — *"Mushoku Tensei sat there reading 'Returns today' two months into its third season."*

`libraryShelves` = `LibShelf.allCases.compactMap { shelf in sortedForShelf(library.filter { libShelf(of:$0) == shelf }, shelf) }`, empty shelves omitted. **No filters** — the Library root is one collection; All titles owns search and Arrange.

`sortedForShelf`:
| Shelf | Order |
|---|---|
| `.watching` | `lastAiredSortKey` **descending**, ties by `title.localizedCaseInsensitiveCompare` ascending. Recently-active first. |
| `.comingBack` | `comingBackSortKey.value` ascending, then `precision` **descending** (more precise first), then title ascending. |
| `.planned`, `.finished` | title ascending (`localizedCaseInsensitiveCompare`). |

`comingBackSortKey(f) -> (value: Int, precision: Int)`:
- if `nextPremiere(of: f)` exists → read it in the franchise's own calendar (`Formatting.localParts(premiere, anchor: f.timeAnchor)`) and return `(y*10000 + mo*100 + d, 3)`;
- else `f.upcoming?.releaseSortKey ?? (Int.max, 0)`. `releaseSortKey` maps the server's `releaseWindow.precision` → `.day: 3`, `.month/.quarter: 2`, `.year: 1`, `.unknown: nil`. Genuinely unknown dates sort to the very end.

---

## 6. Surface phases (`AppModel+States.swift`)

*"Derived state only. Nothing here is stored — a screen asks the model which of the five conditions it is in and renders the matching component, instead of each screen re-deriving `loading && empty && !error` in its own way and drifting."*

```
enum SurfacePhase: Equatable {
    case loading                                   // no cache, request in flight → structural skeleton, DELAYED 240 ms
    case emptyAccount                              // settled, no titles → first-run content, IMMEDIATELY
    case errorNoCache                              // failed, nothing cached
    case content(refreshing: Bool, staleSince: Int64?, sectionFailed: Bool)
    var isContent: Bool
}
```

`surfacePhase` — **order matters**, cached content always wins over a failed refresh (the network never blanks the library), and an empty account is never shown while a first load is still running:
```
if library.isEmpty {
    if loading   { return .loading }
    if loadError { return .errorNoCache }
    return .emptyAccount
}
return .content(refreshing: isRefreshing,
                staleSince: staleSince(.exactAiring),
                sectionFailed: loadError)
```

| Member | Definition |
|---|---|
| `isRefreshing` | `loading && !library.isEmpty` |
| `sectionFailed` | `loadError && !library.isEmpty` |
| `isStale(_:)` | `SyncCenter.shared.isStale(dataClass, now: now)` |
| `staleSince(_:)` | `SyncCenter.shared.staleSince(dataClass, now: now)` |
| `writesAreOffline` | `!SyncCenter.shared.isOnline` — *"Writes are always permitted; this only decides whether the user is told they are queued."* |
| `emptyStateCopy` | `.errorNoCache` → `SyncCenter.shared.isOnline ? .serverNoCache : .offlineNoData`; every other phase → `.emptyAccount`. **`isOnline`, not the error, decides which sentence is true** — only the path monitor knows. |

Exact strings (`EmptyStateCopy`, `Copy.swift`):

| Copy | symbol | title | supporting | primary |
|---|---|---|---|---|
| `.emptyAccount` | `rectangle.stack` | `Your library is empty` | `Everything you add shows up here.` | `Add a show` |
| `.offlineNoData` | `wifi.slash` | `You’re offline` (U+2019) | `Connect to the internet to load your library.` | `Try again` |
| `.serverNoCache` | `exclamationmark.circle` | `Couldn’t load your library` | `Something went wrong. Try again in a moment.` | `Try again` |

`EmptyStateCopy.isRecovery` is `primaryLabel == "Try again" || primaryLabel == "Retry"`; a recovery draws the quiet capsule, a next step ("Add a show") draws the amber one.

---

## 7. The write policy

### 7.1 The two rules

> **A progress mark never rolls back.** A failed progress write keeps the local value and files the failure in `SyncCenter` with a Retry. Rationale in the source: *"a mark is a fact about the user"*. There is no red "couldn't save" toast and no rollback on this path.
>
> **Membership and status writes always roll back.** Add, remove and status changes are facts about the *account*; on failure the optimistic change is reverted and the failure goes to the SyncBanner with a Retry that re-issues exactly that call.

The reason this asymmetry is written down: *"This path used to roll back and flash a red toast, so the tick a user drew on an episode row survived a bad connection while the batch they confirmed above it vanished — two answers to one failure, on one screen."*

### 7.2 `sendProgress` — one lane per part, newest-wins, superseded-drop

```
private struct ProgressWrite { let franchiseId: String; let episodes: Int
                               let command: String; let title: String }

private func sendProgress(franchiseId:, mediaId:, episodes:,
                          command: String = Copy.Action.markAsWatched) {
    let title = franchise(id: franchiseId)?.title ?? ""
    progressQueued[mediaId] = ProgressWrite(franchiseId:, episodes:, command:, title:)  // one slot: overwrite
    guard progressLane[mediaId] == nil else { return }                                   // a drainer is running
    progressLane[mediaId] = Task { [weak self] in
        while let next = self?.progressQueued.removeValue(forKey: mediaId) {
            await self?.putProgress(next, mediaId: mediaId)
        }
        self?.progressLane[mediaId] = nil
    }
}
```
The mailbox holds **one** pending write per part, so a rapid 12 → 13 → 14 sequence issues the PUT for 12, then (once it settles) a single PUT for 14; the intermediate 13 is dropped without ever being sent. Quoting: *"Every mark used to spawn a bare `Task`, so marking 12 then 13 quickly raced two PUTs: when 13's answer landed first, 12's landed last, the server ended on 12 and the next reload walked the tick back. Now one PUT per part is in flight at a time, the newest target waits behind it and anything it superseded is dropped — the server always ends on the user's last word."*

```
private func putProgress(_ write: ProgressWrite, mediaId: Int) async {
    do {
        _ = try await api.setProgress(mediaId: mediaId, episodes: write.episodes)   // PUT /me/progress
        settleLocalProgress(mediaId: mediaId, episodes: write.episodes)
    } catch {
        guard !Task.isCancelled, progressQueued[mediaId] == nil else { return }
        SyncCenter.shared.record(command: write.command, title: write.title,
                                 reason: Copy.Notice.reason(error),
                                 intent: .progress(franchiseId:, mediaId:, episodes:)) {
            await self?.putProgress(write, mediaId: mediaId)
        }
    }
}
```
The failure guard is doubled: *"Teardown cancelled the lane, or a newer target is queued behind this one and will decide the outcome — either way this attempt has nothing to report."*

`PUT /me/progress {mediaId, episodes}` sends an **absolute** value, not a delta, so replaying it is a no-op.

Every progress write in the app funnels here: `markCaughtUp`, `markNext`, `setProgress` (and therefore `markThrough`), and `performUndo`'s revert. The undo's revert deliberately rides the same lane: *"so the server can never end on the mark after the user took it back."*

**Android:** per-`mediaId` `Channel<ProgressWrite>(Channel.CONFLATED)` with a launched collector, or a `MutableStateFlow<ProgressWrite?>` + `collectLatest`. The conflation semantics must match exactly: newest overwrites pending, in-flight is never cancelled mid-request.

### 7.3 `applyLocalProgress` and the immutable-copy rule

```
private func applyLocalProgress(franchiseId:, mediaId:, episodes:) {
    localProgress[mediaId] = LocalWrite(episodes: episodes, settledAtSeq: nil)
    guard let fi = library.firstIndex(where: { $0.id == franchiseId }) else { return }
    library[fi] = library[fi].withUpdatedProgress(mediaId: mediaId, episodes: episodes)
}
```
`Franchise.withUpdatedProgress` replaces one part via `FranchisePart.withProgress(_:)`, which **carries every field**. The hand-built copy it replaced omitted `airings`, *"so one local mark silently took the show off the calendar until the next library reload."* An Android port with a Kotlin `data class` gets this free from `copy()` — but the same trap exists if anyone hand-constructs the part.

`Franchise.withStatus(_:)` replaces both the top-level `status` and the `subscription` mirror so `effectiveStatus` (= `status ?? subscription?.status ?? .planned`) flips immediately, and **preserves `subscription.addedAt`** — *"`addedAt` is a fact about the account, not about the status."*

### 7.4 `localProgress` — the optimistic overlay and its retirement rules

```
private struct LocalWrite { var episodes: Int; var settledAtSeq: Int? }
private var localProgress: [Int: LocalWrite] = [:]      // keyed by mediaId (globally unique)
```
Two jobs it exists for, quoted: *"a franchise added seconds ago isn't in `library` until the add's reload lands, so the write has nowhere to go; and a reload already in flight when the write happened carries a pre-write snapshot that would silently revert it."*

| Function | Behaviour |
|---|---|
| `settleLocalProgress(mediaId:episodes:)` | Called **only on a successful PUT**. If the stored entry's `episodes` still equals this write's, stamp `settledAtSeq = reloadSeq`. A superseding write (different `episodes`) is a no-op. |
| `forgetLocalProgress(mediaId:)` | Drop the entry with no replacement value. Called for **every part of a removed franchise** in `removeFromLibrary` — *"re-adding it later must not replay a write against the fresh subscription."* |
| `reconcileLocalProgress(fetched, seq:)` | Run inside `reload()` before assigning `library`. |

```
private func reconcileLocalProgress(_ fetched: [Franchise], seq: Int) -> [Franchise] {
    guard !localProgress.isEmpty else { return fetched }
    var result = fetched
    for (mediaId, write) in localProgress {
        guard let fi = result.firstIndex(where: { $0.parts.contains { $0.mediaId == mediaId } })
        else { continue }                                        // franchise not in this snapshot: KEEP the entry
        let serverProgress = result[fi].parts.first { $0.mediaId == mediaId }?.progress
        let settledBeforeFetch = write.settledAtSeq.map { seq > $0 } ?? false
        if serverProgress == write.episodes || settledBeforeFetch {
            localProgress[mediaId] = nil                         // retire
        } else {
            result[fi] = result[fi].withUpdatedProgress(mediaId: mediaId, episodes: write.episodes)
        }
    }
    return result
}
```
Retirement, in the source's words: *"An entry retires when the server reports the same number — the write has landed and the overlay would only pin a stale value from then on — and also when this snapshot was fetched AFTER the write settled and still disagrees: the server had its say and said something else (a clamp, or a PUT that never arrived). Without that second rule a value the server will not accept is re-applied on every reload forever. Entries for franchises still missing from the snapshot (an add mid-flight) are kept for the next one."*

Note the consequence of `settleLocalProgress` being called only on success: a **failed** write leaves `settledAtSeq == nil`, so its overlay stays unconditional until a snapshot agrees with it. That is exactly the "a mark never rolls back" rule, expressed in the reconciler.

### 7.5 The write commands

Every one of these is `@MainActor` and returns immediately after the optimistic mutation; the network call runs in a `Task`.

#### `markCaughtUp(_ franchiseId: String)`
1. Resolve `f` and `f.releasingPart`; bail if either is missing.
2. `milestone = !part.isReleasing && part.totalEpisodes > 0 && part.airedEpisodes >= part.totalEpisodes`; fire `.success` if milestone else `.commitMedium`. (One haptic for the whole transaction.)
3. `aired = min(part.airedEpisodes, part.progressCeiling)` — *"Through the same ceiling `setProgress` uses: asserting a number the server would clamp shows 'caught up' against a server that disagrees, and the next launch silently reverts."*
4. `applyLocalProgress(...aired)`.
5. Undo state — **preserving the original `prevProgress` if a non-add undo for this franchise is already pending**, so repeated catch-ups still restore the true start:
   ```
   if let cur = undo, !cur.added, cur.franchiseId == franchiseId {
       undo = UndoState(mediaId: part.mediaId, franchiseId:, prevProgress: cur.prevProgress,
                        title: f.title, episode: aired, count: max(1, aired - cur.prevProgress))
   } else {
       undo = UndoState(..., prevProgress: prev, episode: aired, count: max(1, aired - prev))
   }
   ```
   `count` must be the real number: it was left at its default of 1, *"so catching up six episodes confirmed 'Episode 12 marked as watched' — the app under-reporting its own write by five, on the one control whose whole purpose is a batch. It is derived from the SAME prev the undo restores, so the sentence and the rollback can never disagree."*
6. `celebrate(franchiseId)`; `scheduleUndoDismissal()`; `sendProgress(...)`.

#### `markNext(franchiseId:mediaId:haptic:) -> UndoState?` (`@discardableResult`)
Part choice: explicit `mediaId` → `f.currentPart` → `f.releasingPart` → `f.resumePart`; nil if none.
`target = min(part.progress + 1, part.progressCeiling)`; **return `nil` if `target <= part.progress`** (a completed part yields no write and therefore no toast).
Fires `haptic` (default `.commitLight`; Detail passes `.success` when the mark completes the part). Applies the local write, calls `sendProgress`, and **returns** the `UndoState` without presenting it — *"no toast here: the card shows the result and the view presents the Undo toast when its handoff settles."*

#### `setProgress(franchiseId:mediaId:episodes:haptic:)`
The single choke point where every write is bounded:
```
clamped = min(max(0, episodes), part?.progressCeiling ?? Int.max)
if haptic { fire(abs(clamped - (prev ?? clamped)) > 1 ? .commitMedium : .commitLight) }
applyLocalProgress(...); sendProgress(...)
```
`FranchisePart.progressCeiling` = `0` when `isUpcoming`; else `max(totalEpisodes, airedEpisodes)` if that is `> 0`; else `Int.max` (unknown season size stays unbounded rather than guessing). *"a 10-episode season sat at 59/10 because every tap incremented and the progress ring clamped its visual at 100%, so the overrun was invisible."* Deliberately the season SIZE, not `availableEpisodes()`: *"blocking a legitimate write on stale sync data is worse than allowing a keen viewer to run a few episodes ahead."*
`setProgress` mints **no** `UndoState` — callers that need one use `markThrough`.

#### `markThrough(franchiseId:mediaId:episode:present:) -> UndoState?` (AppModel+Writes)
```
prev   = part.progress
target = min(max(0, episode), part.progressCeiling)
guard target != prev else { return nil }
setProgress(franchiseId:, mediaId:, episodes: target)      // fires the one haptic
state = UndoState(mediaId:, franchiseId:, prevProgress: prev, title: f.title, episode: target,
                  count: max(1, abs(target - prev)),
                  undoAction: { setProgress(..., episodes: prev, haptic: false) })
if present { presentUndo(state) }
return state
```
*"The restoring action is captured here, from the value read BEFORE the write, so undo cannot be re-derived (wrongly) from state the write has already changed."* One transaction, one haptic, one toast, one restoring action. Note it works **downward** too (`abs`), which is how a season reset is expressed.

#### `addToLibrary(franchiseId:title:isReleasing:)`
1. `guard !isInLibrary(franchiseId)`.
2. `FeedbackCoordinator.fire(.success)`.
3. `pendingAdds.insert(franchiseId)` — the card flips to "In library" instantly.
4. `status = isReleasing ? .watching : .planned`.
5. `undo = UndoState(mediaId: nil, franchiseId:, prevProgress: 0, title:, episode: 0, added: true, statusLabel: Copy.Status(status))`; `scheduleUndoDismissal()`.
6. `POST /me/subscriptions {franchiseId, status}` — **the status the toast promised is the status that is sent**; letting the server re-derive it from `nil` meant the toast could name one shelf and the show land on another. On success `await reload()`, then `pendingAdds.remove(franchiseId)` (after the reload, so the flag never flickers off before the real row arrives).
7. On failure: clear the undo if it is still this add's (`cur.added && cur.franchiseId == franchiseId`), `pendingAdds.remove`, and `SyncCenter.record(command: "Add", title:, reason:, intent: .subscribe(franchiseId:title:status:))` with a retry that re-calls `addToLibrary` identically. *"It was the only write in the app that ended in a transient toast with no way back."*

**An add never raises the system permission alert.** The full comment is worth carrying into the port verbatim in spirit: it used to ask for notification permission on the next line, *"so a modal system alert appeared over the results with 'Added … — Undo' counting down underneath it. The undo was unreachable for its whole six-second window, VoiceOver focus was stolen, and the app's first-ever permission ask arrived unprimed in the middle of an unrelated action — where the reflex answer is Don't Allow, after which iOS never asks again and episode alerts are dead for that account permanently."* The ask belongs to an explicit primer (`DiscoverView.notificationPrimer`, armed by an add that **stuck**, raised only after the undo window closed) and to Profile → Notifications.

#### `setStatus(franchiseId:status:haptic:present:)`
`haptic` default `true` → `.selection`. `intent = .status(franchiseId:, status: status.rawValue)`.

*Not in the loaded library* (a pending add): fire-and-forget PATCH; on failure (and not cancelled) record with `command: Copy.Toast.movedTo(status.displayName)`, `title: ""`, the same intent, and a retry that re-calls with `haptic: false, present: false`. *"it was fire-and-forget, the only silent write in the app."* Nothing to roll back.

*In the library*: capture `prevStatus`; **`guard prevStatus != status`**; `library[idx] = library[idx].withStatus(status)`; if `present`, `presentUndo` with `customMessage: Copy.Toast.movedTo(status.displayName)` and an `undoAction` that calls `setStatus(prevStatus, haptic: false, present: false)`. Then PATCH; on success `await syncAmbient()`; on failure (not cancelled) restore `withStatus(prevStatus)`, clear the undo **if it is still this one** (`cur.franchiseId == franchiseId && cur.customMessage != nil`), and record.

`present: false` is used inside multi-write transactions (a rewatch start, an undo's restore) so a transaction still shows exactly one toast.

#### `removeFromLibrary(franchiseId:haptic:)`
`haptic` default `true` → `.commitLight` (`false` on the undo path, which already fired `.selection`).
1. `pendingAdds.remove`.
2. Capture `idx` and `removed = library[idx]`.
3. **`removed?.parts.forEach { forgetLocalProgress(mediaId: $0.mediaId) }`**.
4. Remove from `library`.
5. `DELETE /me/subscriptions/{id}`; on success `await syncAmbient()`.
6. On failure (not cancelled): re-insert the snapshot at `min(idx ?? library.count, library.count)` **if it is not already back**, and `SyncCenter.record(command: "Remove from Library", title:, reason:, intent: .unsubscribe(franchiseId:title:))` with a retry that re-calls with `haptic: false`.

#### `removeWithUndo(_ f: Franchise, reduceMotion: Bool)` (AppModel+Writes)
```
snapshot = f.snapshotForUndo          // Franchise is a value type — the WHOLE show, frozen
previousStatus = f.effectiveStatus
withAnimation(ThemeMotion.pick(.uiSettle, reduceMotion)) { removeFromLibrary(f.id, haptic: true) }
presentUndo(UndoState(..., removed: true, removedFranchise: snapshot, prevStatus: previousStatus))
```
**No confirmation dialog** — *"remove is reversible for 6 s (10 s under VoiceOver) and never touches watch history — the server deletes only the subscription row, so every progress row survives and Undo brings the ticks back exactly."* One haptic for the whole transaction. The toast is presented **immediately**: *"unlike a mark, a removal has no handoff to wait for."*

#### `undoTapped(_ state: UndoState)` — the single entry point for the toast button
Takes the state **by value** *"so a toast that is still on screen stays actionable even if `self.undo` has already moved on."*
```
if let action = state.undoAction { undo = nil; fire(.selection); return action() }
if state.removed { return restoreRemoved(state) }
performUndo()
```

#### `restoreRemoved(_ state:)` (private, AppModel+Writes)
`fire(.selection)`; `undo = nil`; read `UIAccessibility.isReduceMotionEnabled`; `withAnimation(pick(.uiSnappy, reduceMotion))` append the snapshot back to `library` if absent (**instant, before any round-trip**); then `POST /me/subscriptions` with **`status: state.prevStatus`** — *"so a Finished show returns to the Finished shelf rather than silently becoming Planned"* — followed by `await reload()`. On failure: `withAnimation(pick(.uiGentle, reduceMotion))` remove it again, and `SyncCenter.record(command: "Add", title: f.title, reason:)` with retry `{ self.undoTapped(state) }`. **This record carries no `WriteIntent`**, so it cannot be replayed after a relaunch; the row's only exit is Discard.

#### `performUndo()`
```
guard let u = undo else { return }
fire(.selection)
if u.added, let fid = u.franchiseId {
    removeFromLibrary(franchiseId: fid, haptic: false)
} else if let fid = u.franchiseId, let mediaId = u.mediaId, isInLibrary(fid) {
    applyLocalProgress(franchiseId: fid, mediaId: mediaId, episodes: u.prevProgress)
    justCaught.remove(fid)
    sendProgress(franchiseId: fid, mediaId: mediaId, episodes: u.prevProgress,
                 command: Copy.Action.undo)          // command = "Undo"
}
undo = nil
undoTask?.cancel()
```

#### `replay(_ intent: WriteIntent) async`
Installed as `SyncCenter.shared.replay` in `start()`. Re-issues a write restored from a previous launch:
| Intent | Behaviour |
|---|---|
| `.progress(franchiseId, mediaId, episodes)` | Builds a `ProgressWrite` with `command: "Mark as watched"` and the live title, and calls `putProgress` **directly** — *"Progress replays straight to the server — the local value it defends is already on screen if the library still carries it."* Note this bypasses the lane. |
| `.status(franchiseId, raw)` | `setStatus(status, haptic: false, present: false)` if `WatchStatus(rawValue: raw)` decodes. |
| `.subscribe(franchiseId, title, raw)` | `addToLibrary(franchiseId:title:isReleasing: status == .watching)`, with `status = WatchStatus(rawValue: raw) ?? .planned`. |
| `.unsubscribe(franchiseId, _)` | `removeFromLibrary(franchiseId:, haptic: false)`. |
*"membership and status replays go through the live commands so their optimistic state, rollback and toasts stay the app's one grammar."*

### 7.6 Toasts, celebration and receipts

```
func presentUndo(_ state: UndoState) { undo = state; scheduleUndoDismissal() }

private func scheduleUndoDismissal() {
    undoTask?.cancel()
    undoTask = Task { try? await Task.sleep(for: .seconds(SyncCenter.shared.toastSeconds))
                      if Task.isCancelled { return }
                      await MainActor.run { self.undo = nil } }
}

func showNotice(_ message: String) {          // neutral receipt, NO haptic
    notice = message
    noticeTask?.cancel()
    noticeTask = Task { try? await Task.sleep(for: .seconds(2.5)); ...; notice = nil }
}

func showError(_ message: String) {
    FeedbackCoordinator.fire(.directError)
    errorToast = message
    errorTask?.cancel()
    errorTask = Task { try? await Task.sleep(for: .seconds(SyncCenter.shared.errorSeconds)); ...; errorToast = nil }
}

private func celebrate(_ franchiseId: String) {
    justCaught.insert(franchiseId)
    ccTasks[franchiseId]?.cancel()
    ccTasks[franchiseId] = Task { try? await Task.sleep(for: .milliseconds(1300))
                                  justCaught.remove(franchiseId); ccTasks[franchiseId] = nil }
}
```
Only **one** undo can be on screen at a time — `undo` is a single optional, and a new `presentUndo` restarts the dismissal timer.

**Undo-toast presentation timing (the "handoff").** A mark's toast is *not* presented by the model; the card that owns the animation presents it when its commit choreography settles. Today's `settleHero`:
1. `pinned = snapshot` (freeze the list), `pendingUndo = undo`, `handoffInFlight = true`.
2. `withAnimation(pick(.uiMicro, reduceMotion)) { committedEpisode = undo.episode }` — the drawn check + advanced bar on the **same** card.
3. `Announce.status(Copy.Progress.episodeWatched(undo.episode))` (VoiceOver).
4. sleep **650 ms**.
5. `withAnimation(pick(.uiSettle, reduceMotion)) { pinned = nil; committedEpisode = nil }` with a completion that (a) calls `presentUndo(pendingUndo)` and (b) after a further **300 ms** (skipped entirely under Reduce Motion) sets `handoffInFlight = false`.

A second mark is refused while `committedEpisode != nil || handoffInFlight` — *"`handoffInFlight` covers the window `committedEpisode` cannot: the 460 ms during which the NEXT show's card is fading in with a live Mark button on it."*
Detail's `mark(_:part:)` runs the same 650 ms + `.uiSettle` + `presentUndo` sequence without the 300 ms tail. Schedule's `commit(_:then:)` runs `.uiMicro` on the ring and presents in its completion.

### 7.7 `UndoState` and its message table

```
struct UndoState: Identifiable {                 // Equatable by `id` ONLY
    let id = UUID()
    let mediaId: Int?; let franchiseId: String?
    let prevProgress: Int; let title: String; let episode: Int
    var added = false;  var statusLabel: String? = nil
    var removed = false; var removedFranchise: Franchise? = nil; var prevStatus: WatchStatus = .watching
    var count = 1
    var customMessage: String? = nil
    var undoAction: (() -> Void)? = nil
}
```
`message`, in precedence order — **verbatim strings**:

| Condition | String | Example |
|---|---|---|
| `customMessage != nil` | that string | `Moved to Watching` · `Rewatch started` · `Rewatch restarted` |
| `removed` | `Removed from Library. Watch history kept.` | |
| `added` | `Added {title} to {status}` (status defaults to `"Library"`) | `Added Frieren to Watching` |
| `count > 1` | `{title} · {n} episodes watched`, or `{n} episodes marked as watched` when title is empty | `Re:ZERO · 6 episodes watched` |
| else | `{title} · Episode {n} watched`, or `Episode {n} marked as watched` when title is empty | `Re:ZERO · Episode 12 watched` |

The separator is U+00B7 (`·`). Counts go through `Copy.plural(n, "episode", "episodes")` which joins with a **non-breaking space** (U+00A0): `1 episode`, `6 episodes`.
Status words come from `Copy.Status`: `watching → "Watching"`, `planned → "Planned"`, `completed → **"Watched"**`, `paused → "Paused"`, `dropped → "Dropped"`. *"'Finished' is out of the vocabulary; it was carrying both the user's list state and the series' production state."*

Batch confirmations (alert copy, from `Copy.Confirm`):
- title `Mark {n} episodes as watched?`
- message `Your progress will move from episode {a} to episode {b}.`
- confirm button `Mark {n} episodes as watched`
- season reset: `Mark {n} episodes as unwatched?` / `This sets {label} back to {0 of n watched}. Your watch history is kept.` / `Mark {n} episodes as unwatched`
No confirmation button ends in an ellipsis.

Menu command that opens a batch: `Mark episodes {from}⁠–⁠{to} watched` (word-joiners U+2060 around the en dash so a narrow menu cannot break it as "episodes 1–" / "5"), collapsing to `Mark episode {to} watched` when `from >= to`.

### 7.8 Haptics fired from this layer

| Trigger | Token | iOS effect |
|---|---|---|
| `markCaughtUp` on a milestone (`!isReleasing && totalEpisodes > 0 && airedEpisodes >= totalEpisodes`) | `.success` | `UINotificationFeedbackGenerator(.success)` |
| `markCaughtUp` otherwise | `.commitMedium` | medium impact, intensity **0.72** |
| `markNext` | caller's token, default `.commitLight` | light impact, intensity **0.65** |
| `setProgress` with `abs(delta) > 1` | `.commitMedium` | |
| `setProgress` with `abs(delta) <= 1` | `.commitLight` | |
| `addToLibrary` | `.success` | |
| `setStatus` (`haptic: true`) | `.selection` | `UISelectionFeedbackGenerator` |
| `removeFromLibrary` (`haptic: true`) | `.commitLight` | |
| `performUndo`, `undoTapped` custom action, `restoreRemoved` | `.selection` | |
| `showError`, and `SyncCenter.record` inside a user-Retry window | `.directError` | notification error |

`FeedbackCoordinator.fire` is the **only** haptic call site allowed, and enforces: haptics preference on (`UserDefaults "previously.haptics"`, default `true`), app state `.active`, and a per-token rate floor of **0.04 s for `.selection`** and **0.3 s for everything else**. *"A blanket 300 ms floor is right for a commit — two marks 100 ms apart are one transaction and must buzz once. It is wrong for `.selection`, which is the token the A–Z index rail and the week strip use."* **At most one haptic per transaction** is a hard rule; that is why `markThrough` relies on `setProgress`'s haptic and adds none of its own, and why every `undoAction` passes `haptic: false`.

---

## 8. `SyncCenter` — the trust layer

Two rules it exists to enforce, quoted from the file header:
> *"a failure is never invisible and never auto-dismisses — it persists in `failedChanges` until it is retried or discarded, and survives a relaunch"*
> *"'offline' and 'the server is unreachable' are different sentences, and which one the user reads is decided by `isOnline` (NWPathMonitor), never guessed from an error."*

### 8.1 Freshness

There is exactly **one** freshness stamp in the app and `SyncCenter` does not own it: `AppModel.lastLoadedAt` does, and `SyncCenter` reads it through an installed closure. *"A stored copy is exactly what lets Profile's 'Synced 2 min ago' and a screen's stale strip disagree, so both properties below are deliberately computed."*

```
struct Signals: Equatable, Sendable { var lastLoadedAt: Int64 = 0; var loading: Bool = false }
var signals: (@MainActor () -> Signals)?          // installed once, at the app root
private var current: Signals { signals?() ?? Signals() }
var lastSyncedAt: Int64? { current.lastLoadedAt > 0 ? current.lastLoadedAt : nil }
var checking: Bool { current.loading }
```
Installed in `MainTabView.task`:
```
SyncCenter.shared.signals = { .init(lastLoadedAt: appModel.lastLoadedAt, loading: appModel.loading) }
SyncCenter.shared.startMonitoring()
```
Because the closure reads `@Observable` model properties, every view that renders `lastSyncedAt`/`checking` re-evaluates when the model's stamp moves. Until it is installed, nothing can be stale and Profile reads **"Not synced yet"** — the honest reading of "this build has no freshness source wired".

Per-class refinement (optional; nothing is required to call it):
```
func stamp(_ dataClass:, at ts: Int64 = .nowMs)
func age(of:now:) -> Int64?      // max(0, now - (stamps[class] ?? lastSyncedAt)); nil if never loaded
func isStale(_:now:) -> Bool     // age >= threshold; FALSE before the first successful load
func staleSince(_:now:) -> Int64?  // the stamp, only when stale
```
*"Never true before the first successful load: a page that has never loaded is not stale, it is loading. Artwork failures never reach here, so a failed poster can never mark a page stale."*

`syncedLine(now:)` — Profile's account line, **in precedence order**:
1. `!failedChanges.isEmpty` → `"{n} changes couldn’t sync"` (`Copy.Toast.syncFailed`, U+2019 apostrophe, `Copy.plural(n, "change", "changes")` with a non-breaking space)
2. `checking` → `"Checking for changes"`
3. `lastSyncedAt == nil` → `isOnline ? "Not synced yet" : "Couldn’t check for changes"`
4. else `"Synced {elapsed}"` where elapsed is the shared ladder: `just now` (<1 min) · `{n} min ago` (<60 min) · `{n}h ago` (same day) · `yesterday` · a weekday name (2–6 days back) · else a date word.

### 8.2 Reachability

```
private(set) var isOnline: Bool = true        // optimistic default
private let monitor = NWPathMonitor()
func startMonitoring()   // idempotent; pathUpdateHandler hops to @MainActor, isOnline = (status == .satisfied)
                         // queue label "previously.reachability"
func stopMonitoring()    // idempotent
```
*"A captive portal can report `true` while every request fails — accepted: claiming the user is offline when they are not is the worse lie, and the server-side copy is the honest fallback."*
Not started in `init` (*"Cheap, but not free"*); started from the app root, stopped in `teardown()`.

**Android:** `ConnectivityManager.registerDefaultNetworkCallback` with `NET_CAPABILITY_VALIDATED`; default to `true` before the first callback.

### 8.3 Failed changes

```
struct FailedChange: Identifiable {
    let id: UUID
    let command: String        // a Copy.Action string
    let title: String
    var reason: String         // a Copy.Notice.reason(_) string — NEVER a status code
    var at: Int64
    var attemptCount: Int
    var intent: WriteIntent?   // the write itself, when expressible
    let retry: (@MainActor () async -> Void)?   // nil for a row restored from a previous launch
    var key: String            // "\(command)\u{1F}\(title)"   — U+001F unit separator
}
```
`effectiveRetry(center)` returns `retry` if present, else `{ await center.replay!(intent!) }` if both exist, else **`nil`** — *"a missing retry must never be mistaken for a successful one, so there is deliberately no empty-closure fallback here."* `canRetry(center) = effectiveRetry != nil`; `SyncCenter.canRetryAny = failedChanges.contains { $0.canRetry(self) }` (a Retry button that would be a no-op is not drawn).

**`record(command:title:reason:intent:retry:)`** — called by every mutation's `catch`:
1. `key = FailedChange.key(command:title:)`; `attempts[key] += 1`.
2. **One row per (command, title)**: if a row with that key exists, update `reason`, `at`, `attemptCount`, and `intent` (`intent ?? existing.intent`, so a replay-only row keeps its intent); else append a new row. *"a repeatedly failing write is one problem, not a list."*
3. Haptic: **only** if `userRetriedAt[key]` exists and `now - asked <= 30 000`. Then clear the stamp and fire `.directError` — once, or once per `retryAll()` batch (`batchRetryToken`/`batchErrorFired`). An automatic/background failure is **silent**.
4. `persist()`.

**`retry(_ id:)`** — the row **leaves immediately** (the write is optimistic again), then runs:
```
guard let change, let run = change.effectiveRetry(self) else { return }   // nothing runnable: the row STAYS
userRetriedAt[key] = .nowMs
failedChanges.removeAll { $0.id == id }; persist()
Task { await run(); settleRetry(key) }
```
*"A row is **never** cleared when there is nothing to run… Clearing it would delete the record, persist an empty list and let `syncedLine()` report 'Everything synced' for a write that was never sent."*

**`settleRetry(_ key:)`** — by the time it runs, a re-failed write has already re-recorded itself synchronously inside the command's `catch` (consuming the stamp and firing the one `.directError`), *"so by the time this runs the stamp means 'the retry SUCCEEDED'."* It clears `userRetriedAt[key]`, and clears `attempts[key]` when no row with that key remains — *"a later unrelated failure must read '1st attempt', not inherit this key's history for the whole session."*

**`retryAll()`** — only rows with a runnable retry leave the banner; all their keys are stamped at one `now`; a `batchRetryToken` UUID is set and `batchErrorFired = false`, then the runnables execute **sequentially** in a single Task, each followed by `settleRetry`. *"One Retry press is one transaction: the whole batch earns at most one `.directError`, however many of its writes fail again and however far apart they land."* The token is cleared at the end only if it is still the current one.

**`discard(_ id:)`** clears that row's `attempts` and `userRetriedAt` and removes it. **`discardAll()`** clears everything. Both persist.

**`profileIsOpen: Bool`** — Profile lists every failed change with its reason, Retry and Discard, so `ToastHost` suppresses the global `SyncBanner` while it is true.

### 8.4 Persistence

UserDefaults key `"previously.sync.failedChanges"`, a JSON array of
`{ id, command, title, reason, at, attemptCount, intent? }`. `restore()` runs in `private init()`; restored rows have `retry: nil` and depend on `intent` + `replay`.
*"Not board 13's outbox: there is no idempotency key and no sequence. What survives a relaunch is the knowledge that a change failed AND, for the four writes the app makes, the write itself (`WriteIntent`) — so Retry after a relaunch re-issues the mark rather than reloading a library that never had it."*

```
enum WriteIntent: Codable, Equatable, Sendable {
    case progress(franchiseId: String, mediaId: Int, episodes: Int)
    case status(franchiseId: String, status: String)
    case subscribe(franchiseId: String, title: String, status: String)
    case unsubscribe(franchiseId: String, title: String)
}
```
All four server calls behind these are **idempotent** (progress is an absolute PUT; subscribe is an upsert), which is what makes blind replay safe.

### 8.5 `teardown()`

`failedChanges = []`, `stamps = [:]`, `attempts.removeAll()`, `userRetriedAt.removeAll()`, `batchRetryToken = nil`, `batchErrorFired = false`, `stopMonitoring()`, **`replay = nil`**, `SeasonSweepLedger.reset()`, `persist()`.
`signals` is deliberately **kept** — *"it is the wiring, not session data, and it captures the model weakly. The root re-installs it on the next sign-in either way."* `lastSyncedAt`/`checking` are not cleared because they are not stored here.

### 8.6 Failure reasons (`Copy.Notice.reason`)

| Error | String |
|---|---|
| `APIError.unauthorized` | `Signed out` |
| `APIError.http(429, _)` | `Try again in a minute` |
| `APIError.http(other, _)` and any unmapped case | `Something went wrong` |
| `URLError` `notConnectedToInternet`, `networkConnectionLost`, `dataNotAllowed`, `cannotConnectToHost`, `cannotFindHost`, `internationalRoamingOff` | `No connection` |
| `URLError.timedOut` | `Took too long` |
| anything else | `Something went wrong` |

Never a status code, never a raw `localizedDescription`.

---

## 9. `RewatchStore`

*"Rewatching is first-class: every completed watch is a session; at most one session is active per franchise. Device-local this version — atomic JSON in Application Support with one backup generation — so a reinstall loses history but never corrupts it. Progress itself stays on the server; sessions explain it."*

```
struct WatchSession: Codable, Identifiable, Equatable, Sendable {
    enum Scope: Codable, Equatable, Sendable { case franchise; case part(mediaId: Int) }
    let id: UUID
    let franchiseId: String
    let scope: Scope
    let ordinal: Int              // 1 = first watch, 2 = second watch, …
    var startedAt: Int64?
    var completedAt: Int64?
    var cancelledAt: Int64?
    var cancelledAtEpisode: Int?
    var episodes: Int             // episodes the session covers (for history copy); 0 when unknown
    var isActive: Bool    { completedAt == nil && cancelledAt == nil }
    var isCompleted: Bool { completedAt != nil }
}
```

| API | Behaviour |
|---|---|
| `sessions(for:)` | that franchise's sessions, **`ordinal` descending** |
| `activeSession(for:)` | first with `isActive` |
| `summary(for:)` | `Summary(completedCount: count of isCompleted, active: first isActive, lastCompletedAt: max completedAt)` |
| `startRewatch(franchiseId:scope:startedAt:episodes:)` | If the franchise has **no** sessions yet, first append an implicit first watch: `ordinal 1`, `scope .franchise`, `startedAt nil`, **`completedAt = 0`**, `episodes` as given — *"The first watch is recorded implicitly (dates unknown) when no session exists yet, so the new one is the second watch."* Then append the new session at `ordinal = max(existing ordinals) + 1`, active. Persists and returns it. |
| `complete(_ id:at:)` / `cancel(_ id:atEpisode:at:)` / `setStartDate(_ id:to:)` / `delete(_ id:)` / `deleteAll(for:)` | each mutates in place and persists |
| `reset()` | `sessions = []` + persist. Called from `AppModel.teardown()` — sessions belong to the account that made them. |

Note the sentinel: an implicit first watch carries `completedAt == 0`, and `subtitle(...)` maps `completedAt == 0` back to `nil` so it renders **"Dates unknown · {n} episodes"** rather than a 1970 date.

**Persistence.** Directory `applicationSupportDirectory/Previously/`, files `sessions.json` and `sessions.backup.json`.
`load()` (synchronous, in `init`) tries `sessions.json` then `sessions.backup.json`; if neither decodes, `sessions = []`.
`persist()` snapshots the array and runs detached at `.utility`: create the directory, copy the existing file to the backup (deleting the old backup first), then `JSONEncoder` + `write(options: .atomic)`. A throw is swallowed — *"A failed write keeps the previous file (atomic) and the backup; the in-memory state stays authoritative for this session."*

**Copy.** `WatchSession.title` = `Copy.Progress.ordinalWatch(ordinal)`: `"First watch"` … `"Tenth watch"` for 1–10, then `"{n}th watch"` with a correct ordinal suffix.
`subtitle(nextEpisode:now:)`:
1. active + known next → `"In progress · Episode {n} next"`; active without → `"In progress"`
2. `cancelledAtEpisode` → `"Cancelled at episode {n}"`
3. else `Copy.Progress.sessionSpan(started:completed:episodes:now:)` → `"Dates unknown · {n} episodes"` when completed is nil/0; `"{end} · {n} episodes"` when there is no earlier start; else `"{start} – {end} · {n} episodes"` (en dash U+2013), with `start` as a month-day when the two are in the same calendar year and a full date word otherwise.

**Rewatch transaction (Detail, for context — the store alone is not the whole flow):** starting a rewatch snapshots `(mediaId, progress)` for the scoped parts and the previous status, computes `episodes = Σ max(totalEpisodes, progress)`, creates the session, fires `.success`, then inside one `withAnimation(pick(.uiSettle, reduceMotion))` zeroes every part's progress via `setProgress(..., haptic: false)` and calls `setStatus(.watching, haptic: false, present: false)`. It presents **one** undo with `customMessage: "Rewatch started"` whose action deletes the session and restores every snapshot value and the previous status. Completing the final episode of the final part completes the active session (`RewatchStore.complete(active.id, at: now)`) and sets status `.completed`.

---

## 10. Routing

### 10.1 `DetailRoute` (the whole of `Routing.swift`)

```
struct DetailRoute: Hashable, Identifiable {
    let id: String        // franchise id
    let zoomID: String    // names the tapped card, so one franchise is reachable from several surfaces
    var focus: EpisodeFocus? = nil     // lands on one episode (Schedule rows)
}
struct EpisodeFocus: Equatable, Hashable { let mediaId: Int; let episode: Int }   // DetailSupport.swift
```
`zoomID` is retained but **unconsumed** — the `.zoom` transition was tried (2 Sep) and retired (3 Sep). Keep the field in a port only if you intend to use it; nothing depends on its value today.

### 10.2 Tab stacks

`MainTabView` holds `@State private var paths: [AppTab: NavigationPath]` — **one navigation path per tab**; Detail and its episode list push onto the *active* tab's path.

```
enum AppTab: Int, CaseIterable, Hashable { case today, schedule, library, discover }
```
Labels: `"Today"`, `"Schedule"`, `"Library"`, **`"Search"`** for `.discover` — *"It said 'Add' — a tab named for one of the things you can do on it, under a magnifier glyph."* Icons are asset-catalog template images `TabToday` / `TabSchedule` / `TabLibrary` / `TabAdd`, except the Search tab which uses the SF Symbol `magnifyingglass`.

`selection` binding: **re-selecting the active tab pops it to root** (`paths[tab] = NavigationPath()`); for `.library` it additionally bumps `libraryPops`, because All titles is an *item destination*, not a path entry — clearing the path alone left it standing and the tap did nothing. Switching tabs fires `.selection` (`onChange(of: selectedTab)`).

Two destinations, registered once for every tab via `detailDestinations(push:)`:
- `DetailRoute` → `FranchiseDetailView(franchiseId:focus:push:)`
- `FranchiseDetailView.DetailPush` → `.episodes(franchiseId, mediaId, focusEpisode)` → `SeasonEpisodesView`; `.history(franchiseId)` → `WatchHistoryView`; `.detail(franchiseId)` → another `FranchiseDetailView` (a related title, one deeper).
Both wear `.pushedScreenChrome()` — applied at the scaffold, not per screen.

Cross-tab jumps set a request value and switch tabs (`libraryRequest = LibraryView.AllTitlesRoute(status:unwatchedOnly:)`, then `selectedTab = .library`); `onAddShow` sets `appModel.searchFieldRequested = true` and selects `.discover`. Today's `onViewAllUpdates` passes **no status** — *"Today's 'N updates' counts `outNow`, which is any status. Pinning Watching here made the count and the list disagree the moment a Paused show aired."*

Navigation is **silent**: no haptic on `openDetail`.

### 10.3 `pendingOpen` — the alert-tap route

```
// AniTrackApp.init
EpisodeNotifications.shared.onOpen = { [weak model] id in model?.pendingOpen = id }
#if DEBUG
if let id = UserDefaults.standard.string(forKey: "openDetail"), !id.isEmpty { model.pendingOpen = id }
#endif

// MainTabView
.onChange(of: appModel.pendingOpen, initial: true) { _, id in
    guard let id else { return }
    appModel.pendingOpen = nil                      // consumed exactly once
    selectedTab = .today
    paths[.today] = NavigationPath([DetailRoute(id: id, zoomID: "alert/\(id)")])
}
```
`initial: true` matters: a value set during `init` (the debug arg, or a cold launch from a tapped notification) is honoured on first appearance. The Today path is **replaced**, not appended, so the show is the only thing on the stack.

A Schedule-routed `focus` pushes the season list **once** (`focusConsumed` inside Detail) — *"it used to re-push on every pop and trap the user."*

### 10.4 Splash hand-off (`RootView`)

`splashDone` flips only when the splash's own timeline is finished **and** `auth.bootstrapped` — *"so the screen it reveals is the right one, never sign-in for a signed-in user."* On hand-off, `appModel.surfaceReady = true`. The signed-in branch runs `.task(id: auth.isSignedIn) { appModel.start() }`; `onChange(of: auth.isSignedIn)` calls `appModel.teardown()` when it goes false.

### 10.5 Debug launch arguments (DEBUG builds only)

Read through `UserDefaults.standard` (iOS turns `-key value` launch args into defaults):
`-openTab today|schedule|library|discover` (also accepts `search`), `-openDetail <franchiseId>`, `-openAllTitles 1`, `-openProfile 1`, `-recapDemo 1`, `-calmDemo 1`, `-scheduleEarlier 1`, `-scheduleFilter anime|tv`, `-scheduleHideWatched 1`, `-detailAnchor trailers|people|related|watch`, `-detailTrailer 1`, `-detailOpenRelated N`, `-devSignInAuto`.

---

## 11. Accessibility behaviour owned by this layer

| Concern | Behaviour |
|---|---|
| Undo lifetime | `SyncCenter.toastSeconds` = **10 s** while VoiceOver runs, 6 s otherwise. *"an Undo the user cannot reach in time is not an Undo."* |
| Error toast lifetime | `errorSeconds` = **8 s** under VoiceOver, 4 s otherwise. |
| Toast announcement | `ToastHost` announces on every change of `undo?.id`: `"{undo.message}. Undo available."`; and announces `errorToast` / `notice` verbatim when they appear. *"A VoiceOver user was never told the toast existed, let alone that Undo was available for the next six (or ten) seconds."* |
| Commit announcement | The card that owns a mark announces `Copy.Progress.episodeWatched(n)` at commit time (step 3 of the handoff), before the toast. |
| Reduce Motion | The model itself never animates except `withAnimation(ThemeMotion.uiGentle)` around `loadError`. Every *view-side* transaction that wraps a model write picks through `ThemeMotion.pick(token, reduceMotion:)` (→ `Animation.easeOut(duration: 0.12)`), and `restoreRemoved` reads `UIAccessibility.isReduceMotionEnabled` directly because it has no environment. The 300 ms handoff tail in Today's `settleHero` is **skipped entirely** under Reduce Motion. |
| Reduce Transparency | Not consumed here (it is a chrome concern), but note it is the only condition under which a bar is drawn opaque. |
| Dynamic Type | Not consumed here; the app caps at `DynamicTypeSize.accessibility2` globally. Schedule's "Nothing scheduled" moves from the header's count slot to a row under it only at accessibility sizes. |
| Haptics preference | `FeedbackCoordinator.enabled`, `UserDefaults "previously.haptics"`, default `true`; system settings remain authoritative. Haptics are suppressed whenever the app is not `.active`. |

---

## 12. Edge cases a port must reproduce

1. **Whitespace-only query edits do not re-search.** `scheduleSearch` compares the *trimmed* text against `lastScheduledQuery` and returns early when they are equal, the text is non-empty, and `searchExactOnce` is false. *"'naruto' → 'naruto ' is not a new query. It used to cancel the in-flight request and re-issue the identical one 300 ms later."*
2. **Clearing the box** cancels the pending search and resets `searchBusy/searchError/searchResults/searchCorrection/searchSources/searchTask` — it never shows an error.
3. **`searchLiterally(term)`** sets `searchQuery` first (whose `didSet` clears the flag and re-schedules), **then** sets `searchExactOnce = true`, then calls `retrySearch()` — order matters, the request must read the flag.
4. **`retrySearch()`** runs with no debounce.
5. **A search cancelled by the next keystroke is not a failure** — `isCancellation` is checked *before* the sequence guard in `runSearch`'s catch.
6. **Trending** loads once per session, lazily (`loadTrendingIfNeeded` guards on `trending.isEmpty && trendingTask == nil`), releases the task in a `defer`, and is silent on failure — *"the launchpad simply shows recents alone; the next cold visit tries again."* `refreshTrending()` (the pull) cancels and re-fetches, and only replaces `trending` when the result is non-empty.
7. **Recents.** `recordRecentSearch` requires the trimmed query to be **≥ 2 characters**, de-duplicates case-insensitively, inserts at 0, caps at 10, persists. `recordRecentItem` de-duplicates by `id`. `clearRecents()` clears items *and* terms.
8. **An add whose `subscribe` succeeds but whose `reload` fails** still removes the `pendingAdds` entry (the removal is after the `do/catch`, on the success path only — a failing `reload()` inside the `do` does not throw, it swallows its own error).
9. **`setStatus` with an unchanged status is a no-op** (no write, no toast, no haptic beyond the one already fired).
10. **`markNext` on a complete part returns `nil`** — no write, no haptic, no toast.
11. **A removed-and-restored show re-subscribes with its previous status**, not the server default.
12. **A restored `FailedChange` with no `intent`** (only `restoreRemoved` produces one) can never be retried after a relaunch; Discard is the only exit, and it must not be silently cleared.
13. **`justCaught` keeps a row in `outNow` for 1300 ms after `behind` hits 0**, so the celebration frame is actually seen.
14. **`nowMinute` only changes on minute boundaries** — a 20 s tick must not invalidate Schedule three times a minute.
15. **The schedule cache key is `(libraryVersion, nowMinute)`** and `libraryVersion` uses wrapping addition (`&+=`), so it must be an unchecked/wrapping increment in Kotlin too (or just an `Int` that is allowed to overflow — equality is all that is used).

---

## 13. Android portability

| Item | Difficulty | Notes |
|---|---|---|
| `@Observable` fine-grained observation | easy | `mutableStateOf` per field. Do not collapse into one immutable UI-state object: `nowMinute` vs `now`, and `libraryVersion` being `@ObservationIgnored`, exist precisely to keep invalidation narrow. |
| Per-part write lane (`sendProgress`) | easy | `Channel(CONFLATED)` + collector per `mediaId`, or the same map-of-jobs. Conflation semantics must match exactly. |
| Sequence tokens (`searchSeq`, `reloadSeq`) | easy | Plain `Int` counters. Needed even with `collectLatest`, because `teardown()` must invalidate awaiting responses. |
| Offline `library-cache.json` | easy | `filesDir` + kotlinx.serialization, temp-file + rename for atomicity. |
| `RewatchStore` atomic write + one backup generation | easy | Same pattern; the synchronous load at construction must stay synchronous. |
| `UserDefaults` persistence (recents, failed changes, haptics flag) | easy | `SharedPreferences`/DataStore. `WriteIntent` needs a sealed class with polymorphic serialization matching the four cases. |
| `NWPathMonitor` → `isOnline` | easy | `ConnectivityManager.registerDefaultNetworkCallback` with `NET_CAPABILITY_VALIDATED`; keep the optimistic `true` default and the "captive portal may lie" acceptance. |
| Scene lifecycle (`sceneBecameActive` / `EnteredBackground`) | easy | `ProcessLifecycleOwner` `ON_START`/`ON_STOP`. Android may kill and recreate the process where iOS suspends it — on process death `backgroundedAt` is lost, so the app takes the `start()` path instead of the 2-min/6-h refresh path. Acceptable; document it. |
| Haptics (`UIImpactFeedbackGenerator` intensities 0.65 / 0.72, `UINotificationFeedbackGenerator` success/warning/error, `UISelectionFeedbackGenerator`) | **moderate** | Android has no notification-feedback taxonomy. Nearest: `HapticFeedbackConstants.CONFIRM` / `REJECT` / `SEGMENT_TICK` (API 30+/34+) or `VibrationEffect.createPredefined(EFFECT_CLICK / EFFECT_HEAVY_CLICK / EFFECT_DOUBLE_CLICK)` with composition primitives on API 30+. The *rate floors* (0.04 s selection, 0.3 s everything else) and "at most one haptic per transaction" port exactly and matter more than the exact waveform. |
| VoiceOver announcements (`Announce.status`) | easy | `View.announceForAccessibility` / `LiveRegionMode.Polite`. |
| VoiceOver-aware toast durations (`UIAccessibility.isVoiceOverRunning`) | easy | `AccessibilityManager.isTouchExplorationEnabled`; also honour `Settings.Secure.ACCESSIBILITY_*_TIMEOUT` where present. |
| Reduce Motion (`accessibilityReduceMotion`) | easy | `Settings.Global.ANIMATOR_DURATION_SCALE == 0f` (and `TRANSITION_ANIMATION_SCALE`). |
| One `NavigationPath` per tab, re-select pops to root | **moderate** | Navigation-Compose supports nested back stacks per tab, but pop-to-root-on-reselect and "clear the path **and** drop the Library item-destination" (`libraryPops`) need explicit wiring. |
| `pendingOpen` consumed via `onChange(initial: true)` | **moderate** | Android's equivalent is a notification `PendingIntent` → `Activity.onNewIntent` → a single-shot event channel. The "consume exactly once, replace the Today stack" semantics must be preserved or a rotation re-pushes the show. |
| Live Activity / Dynamic Island (`AiringLiveActivityManager.sync`) | **blocker (feature parity)** | No Android equivalent. Nearest is an ongoing/foreground notification with `setOngoing` + custom layout, or Android 14+ `Notification.ProgressStyle`/`CallStyle`-like promoted notifications. `nowBarItem` deliberately mirrors this manager's "one soonest episode" model, so the in-app Now Bar can ship unchanged while the ambient surface is degraded. |
| SF Symbols in `EmptyStateCopy` (`rectangle.stack`, `wifi.slash`, `exclamationmark.circle`) | easy | Map to Material Symbols; the *strings* are the spec, the glyph names are not. |
| `Formatting.TimeAnchor` (local vs synthesized-17:00-UTC date-only) | **moderate** | Reproduce with `java.time`: `.local` → `ZoneId.systemDefault()`, `.utcDate` → `ZoneOffset.UTC`. `localDayKey` must normalise both into the same midnight-UTC-ms space or the schedule bucketing breaks east of UTC+7. Cache the `Calendar` equivalent and re-key it on time-zone/locale change, as `CalendarStore` does (2.2 µs → 0.65 µs per call, and the Schedule feed calls it thousands of times). |
| `.zoom` navigation transition | n/a | Already retired on iOS; do **not** port it. Detail is a plain push/slide. |

---

## 14. Public surface (what other subsystems call)

Reading: `library`, `libraryIds`, `pendingAdds`, `loading`, `loadError`, `lastLoadedAt`, `prevOpenedAt`, `surfaceReady`, `now`, `nowMinute`, `justCaught`, `undo`, `notice`, `errorToast`, `searchQuery`, `searchResults`, `filteredSearchResults`, `searchBusy`, `searchError`, `searchCorrection`, `searchSources`, `recentSearches`, `recentItems`, `trending`, `trendingLoading`, `searchFieldRequested`, `mediaFilter`, `pendingOpen`.

Derived: `isInLibrary`, `franchise(id:)`, `source(of:)`, `matchesMediaFilter`, `airingFranchises`, `libraryEmpty`, `effectivePrev`, `outNow`, `soon`, `nextUp`, `nowBarItem`, `keepWatching`, `shelfState(of:)`, `nextPremiere(of:)`, `watchingShelf`, `scheduleDays`, `scheduleFeedKey`, `scheduleTodayNoon`, `libShelf(of:)`, `libraryShelves`, `surfacePhase`, `isRefreshing`, `sectionFailed`, `emptyStateCopy`, `isStale(_:)`, `staleSince(_:)`, `writesAreOffline`.

Commands: `start()`, `reload()`, `teardown()`, `sceneBecameActive()`, `sceneEnteredBackground()`, `alertsWereAllowed()`, `markCaughtUp`, `markNext`, `setProgress`, `markThrough`, `addToLibrary`, `setStatus`, `removeFromLibrary`, `removeWithUndo`, `presentUndo`, `undoTapped`, `performUndo`, `replay`, `showNotice`, `showError`, `recordRecentSearch`, `removeRecentSearch`, `clearRecentSearches`, `recordRecentItem`, `removeRecentItem`, `clearRecents`, `searchLiterally`, `retrySearch`, `loadTrendingIfNeeded`, `refreshTrending`.
