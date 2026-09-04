# Networking, Configuration, Auth & Sign-in

This document specifies the transport and identity layer of **Previously.** (bundle `com.anitrack.app`,
Swift target name `AniTrack`) precisely enough to rebuild it in Kotlin/Compose without reading the Swift.
It covers five source files — `Sources/Networking/APIClient.swift`, `Sources/Networking/AppConfig.swift`,
`Sources/Auth/AuthManager.swift`, `Sources/Auth/SignInView.swift`,
`Sources/Features/Profile/AccountDeletion.swift` — plus the call sites that give them meaning
(`App/AniTrackApp.swift`, `App/RootView.swift`, `App/AppModel.swift`, `Features/Profile/ProfileView.swift`,
`project.yml`, `Resources/Info.plist`) and reconciles all of it against `docs/api-contract.md` and the
Fastify routes that serve it. The single most important idea in this layer is a **three-way split of
"the request failed"**: *the session is dead* (sign the user out), *the infrastructure is in the way*
(keep the session, keep the content, show a footnote), and *we could not reach anything* (keep everything,
say "No connection"). A 403, an HTML body at any status, and an inability to **mint** a token are all in
the second or third bucket. Exactly one code path in the whole client ends a session. Getting that split
wrong is a shipped regression this codebase has already lived through (2026-08-22) and its comments name
it repeatedly.

---

## 1. Layer map

| Layer | Swift type | Responsibility | Android analogue |
|---|---|---|---|
| Build config | `enum AppConfig` | Reads `Info.plist` keys written from build settings | `BuildConfig` fields from Gradle `buildConfigField` / `manifestPlaceholders` |
| Token vending | `protocol TokenProvider` | `currentToken()`, `hasSession()`, `refreshedToken()` | interface + OkHttp `Authenticator`/`Interceptor` |
| Refresh coalescing | `actor TokenRefresher` | single-flight + 3 s reuse window | `Mutex` + cached value, or `kotlinx.coroutines.sync` |
| Retry policy | `enum RetryPolicy` | budget, backoff, `Retry-After` | plain object |
| Transport | `final class APIClient` | every endpoint, the state machine | Retrofit/Ktor + custom interceptor, or hand-rolled |
| Errors | `enum APIError: LocalizedError` | taxonomy + user copy + log copy | sealed class |
| Identity | `@Observable AuthManager` | Clerk + dev-bypass modes, sign-in state, display identity | `ViewModel` exposing `StateFlow` |
| Erasure | `enum AccountDeletion` | `DELETE /me`, deliberately **outside** `APIClient` | separate suspend fun with its own client |
| First-run UI | `SignInView` | brand + one action | Compose screen |

---

## 2. `AppConfig` — Info.plist plumbing

### 2.1 The chain

```
project.yml  targets.AniTrack.settings.base.<VAR>
      ↓ (Xcode build setting)
Resources/Info.plist  <key>X</key><string>$(VAR)</string>
      ↓ (substituted at build time)
Bundle.main.object(forInfoDictionaryKey: "X") as? String
      ↓ (trimmed of whitespace/newlines)
AppConfig.<accessor>
```

Nothing reads an environment variable at runtime; every value is baked into the app bundle. On Android
the equivalent is `buildConfigField("String", "API_BASE_URL", …)` per build type/flavour.

### 2.2 Keys and defaults

| Info.plist key | Build setting | Shipped value (`project.yml`) | Accessor | Behaviour when blank / placeholder |
|---|---|---|---|---|
| `APIBaseURL` | `API_BASE_URL` | `https://anime.cognipin.com` | `AppConfig.apiBaseURL: URL` | falls back to `http://localhost:8787` |
| `ClerkPublishableKey` | `CLERK_PUBLISHABLE_KEY` | `pk_test_bGVnaWJsZS1nb2JibGVyLTU3LmNsZXJrLmFjY291bnRzLmRldiQ` | `clerkPublishableKey: String` | empty string |
| `PrivacyPolicyURL` | `PRIVACY_POLICY_URL` | `https://anime.cognipin.com/privacy` | `privacyURL: URL?` | `nil` → Profile omits the row |
| `TermsURL` | `TERMS_URL` | `https://anime.cognipin.com/terms` | `termsURL: URL?` | `nil` → row omitted |
| `SupportEmail` | `SUPPORT_EMAIL` | `shantanusinha95@gmail.com` | `supportEmail: String?`, `supportURL: URL?` (`mailto:`) | `nil` → row omitted |

Validation rules, exactly:

- `apiBaseURL`: trim; accept only if `URL(string:)` parses **and** the raw string is non-empty **and**
  `url.scheme != nil`. Otherwise `http://localhost:8787`.
- `isClerkConfigured`: `key.hasPrefix("pk_") && !key.contains("REPLACE_ME")`. This one boolean decides
  the whole auth mode (Clerk vs dev-bypass) and whether `Clerk.configure` is called at all.
- `configuredString(key)`: trim; `nil` if empty **or** contains `REPLACE_ME`.
- `configuredURL(key)`: `configuredString` + parses + has a scheme.
- `supportEmail`: `configuredString` + `contains("@")`.

> *Why*: "a placeholder URL baked into a shipped string is a broken Privacy Policy link, which is itself
> a rejection" (App Store guideline 5.1.1). The screen omits a row rather than drawing one that goes nowhere.

### 2.3 `isLocalBackend` — the boundary a `dev:` bearer may never cross

```swift
static var isLocalBackend: Bool {
    guard let host = apiBaseURL.host?.lowercased() else { return false }
    if host == "localhost" || host == "127.0.0.1" || host == "::1" { return true }
    if host.hasSuffix(".local") { return true }
    return isPrivateIPv4(host)
}
```

`isPrivateIPv4` parses **by address, never by string prefix**: split on `.` (keeping empty
subsequences), require exactly 4 components, all parse as `Int`, all in `0...255`, then
`10.*` → true, `192.168.*` → true, `172.16…31.*` → true, else false.

> *Why (quoted)*: "`10.example.com` and `192.168.evil.tld` are ordinary internet hostnames that anyone
> can register; a `hasPrefix` test would classify them as local and release a `dev:` bearer toward them."

`isLocalBackend` gates three things: whether `resolveToken()` will emit a `dev:` token at all, whether
`hasSession()` counts a stored dev id as a session, and whether the developer sign-in card is drawn.

### 2.4 Other build/plist facts this layer depends on

| Key | Value | Why it matters |
|---|---|---|
| `NSAppTransportSecurity.NSAllowsLocalNetworking` | `true` | cleartext HTTP allowed to LAN/loopback only; production is HTTPS. Android equivalent: a `network_security_config.xml` with `cleartextTrafficPermitted="true"` scoped to `localhost` + a dev domain. |
| `NSLocalNetworkUsageDescription` | "Previously. connects to your self-hosted server running on your local network." | iOS shows a one-time local-network prompt; **without the key a connection to `192.168.x.x` fails silently.** Android has no equivalent prompt — nothing to port. |
| `UIUserInterfaceStyle` | `Dark` | app is dark-only; root also sets `.preferredColorScheme(.dark)`. |
| `ITSAppUsesNonExemptEncryption` | `false` | the app ships no crypto of its own; only OS HTTPS. |
| Deployment target | iOS 18.0 | Android floor should be chosen on the same "identical device coverage" logic, not copied. |

---

## 3. Endpoint catalogue

Base URL from `AppConfig.apiBaseURL`. All times in payloads are **ms since epoch (Int64)**.
Every endpoint except `/health` sends `Authorization: Bearer <token>`.

| # | Method | Path + query | Body | Response type | `auth` | `idempotent` (retryable) | Caller |
|---|---|---|---|---|---|---|---|
| 1 | GET | `/health` | — | `OKResponse { ok: Bool }` | **false** | true | **nobody** (see §12.2) |
| 2 | GET | `/franchises/trending?limit={n}` (default arg 30; every caller passes 10) | — | `FranchiseListResponse` → `.franchises` | true | true | `AppModel.loadTrendingIfNeeded/refreshTrending` |
| 3 | GET | `/search?q={strict-encoded}[&exact=1]` | — | `SearchEnvelope` → `SearchResponse` | true | true | `AppModel.runSearch`, Detail's related-title materialisation (`exact: true`) |
| 4 | GET | `/franchises/{id}[?country=XX]` | — | `Franchise` | true | true | `FranchiseDetailView.load()` with `country: AppRegion.current`; one call site omits `country` |
| 5 | GET | `/franchises/{id}/watch-providers?country=XX` | — | `WatchAvailability` | true | true | `FranchiseDetailView`, failure = missing section |
| 6 | GET | `/me/library` | — | `LibraryResponse { franchises: [Franchise], prevOpenedAt: Int64 }` | true | true | `AppModel.reload()` |
| 7 | POST | `/me/subscriptions` | `SubscribeBody { franchiseId: String, status: WatchStatus? }` | `OKResponse` | true | true | add-to-library, and the rollback restore in `AppModel+Writes` |
| 8 | PATCH | `/me/subscriptions/{franchiseId}` | `StatusBody { status: WatchStatus }` | `OKResponse` | true | true | `setStatus` |
| 9 | DELETE | `/me/subscriptions/{franchiseId}` | — | `OKResponse` | true | true | `unsubscribe` / remove-with-undo |
| 10 | PUT | `/me/progress` | `ProgressBody { mediaId: Int, episodes: Int }` | `OKResponse` | true | true | `AppModel.putProgress` only |
| 11 | POST | `/me/opened` | — | `OpenedResponse { prevOpenedAt: Int64 }` | true | **false** | `AppModel.stampOpened()` once per `start()` |
| 12 | DELETE | `/me` | — (empty; an unknown field is a 400) | `{ deleted: true }` | true | n/a — **not through `APIClient`** | `AccountDeletion.deleteAccount` |

`WatchStatus` is `watching | completed | planned | paused | dropped` (lowercase raw values).

### 3.1 Idempotency is a required argument, not a default

The private `request`/`send` helpers take `idempotent:` with **no default value**. Source comment:

> "Every call states its own retryability. It is a required argument, not a default, because exactly one
> endpoint in this app is unsafe to replay (`/me/opened`) and the next endpoint someone adds must make
> that decision consciously."

`/me/opened` returns the *previous* `lastOpenedAt` and then stamps now; a replay would return "now" and
"destroy 'since you were last here' — the recap's whole premise."

`POST /me/subscriptions` is marked idempotent because the server does an upsert; `PUT /me/progress` is
idempotent because it carries an **absolute** episode count, never a delta.

### 3.2 URL composition (port this exactly)

`APIClient` builds every URL as `URL(string: path, relativeTo: baseURL)` where `path` always begins with
`/`. Consequence: **any path component in the base URL is discarded.** A base of
`https://host/api` + `/search` resolves to `https://host/search`. `AccountDeletion` instead uses
`baseURL.appendingPathComponent("me")`, which *preserves* a base path. This inconsistency is latent
(the shipped base has no path) but a Kotlin port using `HttpUrl.Builder` must pick one behaviour and
should prefer resolve-against-authority to match `APIClient`.

### 3.3 Path and query encoding

| Case | Rule |
|---|---|
| Franchise id in a path | `addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)`, falling back to the raw id if that returns nil |
| `q=` search value | `CharacterSet.strictQueryValueAllowed` = `.urlQueryAllowed` **minus** the characters `& = + ? #`; failure → empty string |
| `country=` | interpolated raw (always a 2-letter uppercase code from `AppRegion.current`) |
| `limit=` | interpolated raw Int |

> *Why the strict set (quoted)*: "`.urlQueryAllowed` leaves `&`, `+`, and `=` unescaped, which corrupts
> the q parameter (searching "X & Y" truncated at the ampersand)."

Android: `URLEncoder.encode(q, "UTF-8")` is *stricter* than this and is a safe substitute; the important
part is that `&`, `=`, `+`, `?`, `#` never survive into the value.

### 3.4 `AppRegion.current`

```swift
let code = (Locale.current.region?.identifier ?? "").uppercased()
return code.count == 2 && code.allSatisfy(\.isLetter) ? code : "US"
```

ISO 3166-1 alpha-2, uppercase; **"US" when the device states no region** ("an unset region is not
'no market'"). Android: `Locale.getDefault().country` with the same validation.

### 3.5 Search response shape

`SearchResponse` (returned to callers) carries four fields:

| Field | Source | Note |
|---|---|---|
| `franchises: [FranchiseSummary]` | `franchises` | required — a body without it is a decode failure, deliberately **not** "no results" |
| `correctedQuery: String?` | `correctedQuery` | present only when the server spell-corrected AND the rewrite found something |
| `originalQuery: String?` | `originalQuery` **?? the query we sent** | the client substitutes its own query when the server omits the echo |
| `sources: [String: String]?` | `sources` | per-catalogue `ok` / `failed` / `disabled`; absent means "nothing to report", never "everything failed" |

There are two `search` overloads. **Swift resolves a bare `api.search(query: q)` to the results-only
overload** (`[FranchiseSummary]`) because Swift prefers the candidate needing no defaulted arguments; the
full response requires `exact:` explicitly or an explicit result annotation. Kotlin has no such hazard —
port a single function returning the full response and let callers take `.franchises`.

---

## 4. The transport state machine (`APIClient.send`)

### 4.1 Session configuration

Owned session, never the shared one:

| Setting | Value | Why |
|---|---|---|
| `timeoutIntervalForRequest` | `APIClient.requestTimeout` = **15 s** | "the default 60 s request timeout means a black-holed upstream leaves a skeleton on screen for a minute" |
| `timeoutIntervalForResource` | `RetryPolicy.budget + 1` = **17.6 s** | `timeoutIntervalForRequest` is an *inter-packet* timeout — "an upstream that trickles one byte every 14 s never trips it, so this is the only true wall-clock ceiling, and it must not outlive `RetryPolicy.budget`" |
| `waitsForConnectivity` | `false` | fail now, don't queue |
| `httpAdditionalHeaders` | `["Accept": "application/json"]` | also set per-request |

Encoding/decoding: stock `JSONEncoder` / `JSONDecoder`, **no key strategy** — the wire is already camelCase.
A body-encoding failure is thrown as `APIError.decoding` (note: an *encode* error surfaces under the
`decoding` case).

### 4.2 Budget and retry

| Constant | Value |
|---|---|
| `RetryPolicy.maxRetries` | 2 |
| backoff base (seconds) | `[0.4, 1.2]`, index = `attempt` clamped to `1...2`, minus 1 |
| jitter | multiply by `Double.random(in: 0.8...1.2)` (±20 %) |
| `RetryPolicy.budget` | **16.6 s** — one full 15 s attempt plus ≈1.6 s of backoff |
| `RetryPolicy.minAttempt` | **2 s** — floor on any single attempt's timeout, and the survivability test for a retry |
| `Retry-After` clamp | `0…8 s` |

```swift
static func canRetry(attempt: Int, delay: TimeInterval, deadline: Date) -> Bool {
    attempt < maxRetries && deadline.timeIntervalSinceNow - delay >= minAttempt
}
```

The **deadline is computed once**, at the top of `send`, as `now + 16.6 s`. Every attempt's own timeout is
`min(15, max(2, deadline.timeIntervalSinceNow))` — spent from the shared budget, never restarted.

> *Why (quoted)*: "a per-attempt timeout stacks — three fresh 15 s attempts against a black hole is 45 s
> of skeleton."

`Retry-After` parsing: trim; if it parses as a `TimeInterval`, clamp to `0…8`. Otherwise parse as an
HTTP-date with format `EEE, dd MMM yyyy HH:mm:ss zzz`, locale `en_US_POSIX`, timezone `GMT`, then
`clamp(date.timeIntervalSinceNow, 0…8)`. Unparseable → `nil`.

### 4.3 Per-attempt construction

1. `URLRequest(url:)`, `httpMethod = method`.
2. `timeoutInterval` = the clamped remainder (above).
3. `Accept: application/json`.
4. If a body exists: set it and `Content-Type: application/json`.
5. If `auth`: resolve a token — **`forcedToken` if a refresh produced one this request, else
   `await tokenProvider.currentToken()`**. If the token is `nil`, take the pre-flight branch (§4.4).
   Otherwise set `Authorization: Bearer <token>` and remember it as `sentToken`.

### 4.4 Pre-flight guard: "no token" is two different facts

```swift
guard let token = resolved else {
    if await tokenProvider.hasSession() {
        // log: "token unavailable while signed in — transport, session kept"
        throw APIError.transport(URLError(.notConnectedToInternet))
    }
    // log: "no session — unauthorized"
    throw APIError.unauthorized
}
```

> *Why (quoted)*: "Either there is no identity at all (signed out), or there IS one and we could not mint
> a token right now: a cold launch in airplane mode, where Clerk's ~60 s JWT has expired and nothing can
> renew it. Signing a user out for being offline is the same failure class as the 2026-08-22 regression."

### 4.5 Branch order after a response arrives (do not reorder)

Pre-branch: a thrown transport error is handled first —

- `URLError.cancelled` → **throw `.transport(error)` immediately, never retried** ("a request cancelled by
  the next keystroke is superseded").
- otherwise, if `idempotent && canRetry(...)`: `attempt += 1`, log `retry scheduled … status=0`,
  `Task.sleep(delay)`, `continue`. (A cancellation *during that sleep* propagates as a raw
  `CancellationError`, which `isCancellation` also recognises — see §6.)
- otherwise → `.transport(error)`.

Then, `response as? HTTPURLResponse` must succeed or → `.infrastructure(-1, "no-http-response")`.

Let `status`, and `contentType` = lowercased `Content-Type` header (`""` if absent).

| Order | Condition | Outcome |
|---|---|---|
| **1** | `status == 401 && auth && !isHTML` | If no refresh has been attempted yet: force one via `TokenRefresher`. `.token(fresh)` where `fresh != sentToken` → set `forcedToken`, `continue` (**does not consume the retry budget** — "a stale token is not a flaky network"). `.failed(err)` → **throw `.transport(err)`, session kept** ("we only learned that the issuer is unreachable"). `.token(same)` or `.notRefreshable` → fall through. Fall-through, or a second 401 → log `unauthorized after refresh`, **throw `.unauthorized`**. |
| **2** | `status == 403` | throw `.infrastructure(403, contentType.isEmpty ? "forbidden" : contentType)`. **Never a sign-out.** |
| **3** | `status == 429 \|\| status in 500...504` | `after` = `Retry-After` (429 only). `delay = after ?? RetryPolicy.delay(attempt+1)`. If `idempotent && canRetry` → retry with logging. Else if 429 → throw `.rateLimited(retryAfter: after)`. Else (5xx) **fall through** to branches 4/5. |
| **4** | `isHTML(data, contentType)` at **any** status | throw `.infrastructure(status, "html")` |
| **5** | `!(200..<300).contains(status)` | throw `.http(status, bodyAsUTF8String)` |
| **6** | otherwise | `decoder.decode(Response.self)`; a throw → `.decoding(error)` |

Branch 3 runs **before** the HTML test on purpose: "the ordinary production 502/503 arrives with an HTML
error page from nginx or Cloudflare; classifying on the body first would spend the retry budget on nothing."

Branch 1's two guards are the whole session-safety story:

> "`auth` — we actually SENT a credential. A 401 on an unauthenticated probe (`health()`) is the server's
> business, never a reason to sign anyone out. … not HTML — a real expired session from Fastify is
> `401 {"error":"invalid token"}` in `application/json`. An HTML 401 is nginx `auth_basic`, a Cloudflare
> Access challenge, or a captive portal."

### 4.6 HTML sniffing

```swift
private func isHTML(data: Data, contentType: String) -> Bool {
    if contentType.contains("text/html") { return true }
    guard let first = data.first(where: { !($0 == 0x20 || $0 == 0x0a || $0 == 0x0d || $0 == 0x09) })
    else { return false }
    return first == UInt8(ascii: "<")
}
```

Declared type, **or** first non-whitespace byte is `<` (skipping space, LF, CR, tab). "Cheap, and it
catches the proxies that serve an interstitial as `text/plain`." An empty body is not HTML.

### 4.7 Logging contract

Subsystem `com.anitrack.app`, category `api` (both `APIClient` and `TokenRefresher`, deliberately — so
`log stream --predicate 'subsystem == "com.anitrack.app"'` interleaves them). Everything is emitted at
`.error` level so it survives the default log filter. Lines a port should reproduce:

- `retry scheduled <METHOD> <path> attempt=<n> delay=<d.dd> status=<code|0>` (method/path marked `.public`)
- `<METHOD> <path>: <diagnostic>` on every thrown classification
- `<METHOD> <path>: transport error: <error>`
- `<METHOD> <path>: decoding failed: <error>`
- `<METHOD> <path>: token unavailable while signed in — transport, session kept`
- `<METHOD> <path>: no session — unauthorized`
- `<METHOD> <path>: auth.refresh unreachable — transport, session kept`
- `unauthorized after refresh`
- from the refresher: `auth.refresh begin`, `auth.refresh end(changed:true)`,
  `auth.refresh end(changed:false, notRefreshable)`, `auth.refresh end(changed:false, unreachable)`,
  `auth.refresh coalesced`, `auth.refresh reused`

Separately, `AppModel` logs under subsystem **`app.previously`**, category `model` (`library reload failed: …`).
The two subsystems disagree; keep both if you want log parity, or unify — but note the mismatch exists.

---

## 5. Error taxonomy

`enum APIError: LocalizedError` — seven cases, four projections.

| Case | Raised by | `errorDescription` (user-facing) | `failureReason` (short) | `diagnostic` (log only) | `isSessionEnding` |
|---|---|---|---|---|---|
| `.invalidURL` | URL failed to build | = `failureReason` | `Server error` | `invalid-url` | false |
| `.unauthorized` | branch 1 fall-through, or pre-flight with no session | **"You’re signed out. Sign in again to continue."** | `Signed out` | `unauthorized` | **true** |
| `.infrastructure(Int, String)` | 403; HTML at any status; non-HTTP response | = `failureReason` | `Server error` | `infrastructure status=<code> kind=<kind>` | false |
| `.rateLimited(retryAfter: TimeInterval?)` | 429 past the budget | = `failureReason` | `Rate limited` | `rate-limited retryAfter=<int or ->` | false |
| `.http(Int, String)` | any other non-2xx | = `failureReason` | `Server error` | `http status=<code> body=<first 200 chars>` | false |
| `.decoding(Error)` | decode failure, **and body-encode failure** | = `failureReason` | `Server error` | `decoding <error>` | false |
| `.transport(Error)` | URLSession throw; token-mint failure; refresh-unreachable | = `failureReason` | `Timed out` if the underlying `URLError.code == .timedOut`, else `No connection` | `transport <error>` | false |

**Invariant (board 14): `errorDescription` may never contain a status code or a MIME type**, because
`LocalizedError.errorDescription` is what `error.localizedDescription` yields and therefore the one place
technical detail could leak into a surface. All technical detail lives in `diagnostic`, which only the
logger reads.

`isSessionEnding` is the predicate callers *should* branch on; `AppModel` today still spells the same test
longhand as `catch APIError.unauthorized` (one call site, `AppModel.reload()`), and the comment says only
the predicate survives adding a case. In Kotlin, put the predicate on the sealed class and use it everywhere.

### 5.1 The write-failure copy map (`Copy.Notice.reason`)

Failed writes are recorded in `SyncCenter` with a short reason string produced here — **never a status code**:

```swift
if let api = error as? APIError {
    switch api {
    case .unauthorized:            return "Signed out"
    case .http(let code, _):       return code == 429 ? "Try again in a minute" : "Something went wrong"
    case .transport(let inner):    return transportReason(inner)
    default:                       return "Something went wrong"
    }
}
return transportReason(error)
```

`transportReason` looks at `NSError`: if the domain is not `NSURLErrorDomain` → `Something went wrong`.
Otherwise:

| `NSURLError…` code | String |
|---|---|
| `NotConnectedToInternet`, `NetworkConnectionLost`, `DataNotAllowed`, `CannotConnectToHost`, `CannotFindHost`, `InternationalRoamingOff` | **"No connection"** |
| `TimedOut` | **"Took too long"** |
| anything else | **"Something went wrong"** |

Other constants in the same table: `signedOut` = "Signed out", `rateLimited` = "Try again in a minute",
`notInCatalogue` = "Not in the catalogue yet". Note `.rateLimited` (the enum case) is **not** mapped here —
it falls into `default` → "Something went wrong". That is the code as written.

Profile's sync rows additionally rewrite exactly one string on the way to the screen:
`"Something went wrong"` → `"Couldn’t connect"` (`Copy.Account.couldNotReachServer`), passing anything
else through unchanged.

Screen-level notice headlines (used with the reason strings): "Airing dates couldn’t refresh",
"The schedule couldn’t refresh", "Your library couldn’t refresh", "Episodes couldn’t refresh",
"Anime results couldn’t refresh", "TV results couldn’t refresh". State copy says
"Couldn’t load your library" / "You’re offline" / "Something went wrong" — **never the word "server"**
in a user-facing string (the one exception is the deletion failure, §9.3, which must say what was not reached).

---

## 6. The cancellation rule

```swift
extension Error {
    var isCancellation: Bool {
        if self is CancellationError { return true }
        if (self as? URLError)?.code == .cancelled { return true }
        if let api = self as? APIError, case let .transport(inner) = api,
           (inner as? URLError)?.code == .cancelled { return true }
        return false
    }
}
```

**A cancelled request is not a failure.** Three shapes must all be recognised: a Swift structured-concurrency
`CancellationError` (e.g. cancelled during a backoff sleep), a bare `URLError.cancelled`, and the
`APIError.transport(URLError.cancelled)` wrapper the client produces.

Consumers:

- `AppModel.reload()` — `guard !error.isCancellation else { return }` **after** setting `loading = false`,
  so a superseded pull never raises "couldn't refresh" over good content.
- `AppModel.runSearch` — a private duplicate of the same predicate (`isCancellation(_:)`), returns silently.
- `FranchiseDetailView.load()` — `if !error.isCancellation { loadError = true }`.

Also: `loadError` always flips **inside `withAnimation(ThemeMotion.uiGentle)`** (ease-in-out, 0.22 s) so the
"couldn't refresh" footnote fades in instead of shoving content down 28 pt.

Kotlin analogue: `if (e is CancellationException) throw e` — but note the semantics differ. Here the app
*swallows* cancellation at the consumer; in Kotlin, structured concurrency requires rethrowing
`CancellationException` and instead suppressing the UI side-effect. Also fold in
`java.io.InterruptedIOException` / OkHttp's `"Canceled"` `IOException`.

---

## 7. `TokenProvider` and `TokenRefresher`

### 7.1 Protocol

```swift
protocol TokenProvider: Sendable {
    func currentToken() async -> String?      // may be cached; nil = none available right now
    func hasSession() async -> Bool           // an identity EXISTS — must not touch the network
    func refreshedToken() async -> TokenRefreshOutcome   // FORCED refresh, skipping any cache
}

enum TokenRefreshOutcome: Sendable {
    case token(String)     // a fresh credential
    case notRefreshable    // FINAL answer from the issuer — a 401 against it ends the session
    case failed(Error)     // network problem — says nothing about the credentials; session KEPT
}
```

> "Offline, a Clerk session still exists on this device; its ~60 s JWT does not. The two must never be
> confused: one is a signed-out user, the other is a user on a train."

### 7.2 Single-flight refresh

`actor TokenRefresher` with:

| Field | Value / meaning |
|---|---|
| `reuseWindow` | **3 s** — "long enough to cover one screen's fan-out, short enough that a genuinely new 401 refetches" |
| `inFlight` | the one running refresh task |
| `lastToken` / `lastAt` | only ever set on **success** |

`token(from:)` algorithm:

1. If `lastAt` and `lastToken` exist and `now - lastAt < 3 s` → log `auth.refresh reused`, return `.token(lastToken)`.
2. If a task is in flight → log `auth.refresh coalesced`, `await` its value.
3. Else log `auth.refresh begin`, start `Task { await provider.refreshedToken() }`, await, clear `inFlight`, log the matching `end(...)` line.
4. **Only `.token` primes the reuse window.**

> *Why (quoted)*: "Caching a refresh that failed because Clerk was unreachable would replay that failure to
> every 401 for the next 3 s, turning one network blip into a session-wide teardown."

The begin/end logging lives **inside** the actor deliberately: "a burst of six concurrent 401s prints one
pair plus five `coalesced`/`reused` lines. Logging at the call site would print six of each and make
single-flight unverifiable from `log stream`."

Kotlin: a `Mutex` plus a `Deferred<TokenRefreshOutcome>?` and a `lastToken/lastAt` pair inside a single
class; or `SharedFlow` + `conflate`. The 3 s window and the success-only priming are load-bearing.

One `TokenRefresher` per `APIClient` instance; a client allows **at most one forced refresh per logical
request** (`var refreshed = false`).

---

## 8. `AuthManager`

`@MainActor @Observable final class AuthManager: TokenProvider`. It is constructed in `AniTrackApp.init()`,
injected into the environment, and passed to `APIClient(tokenProvider:)`.

### 8.1 Modes

```swift
enum Mode: Equatable { case clerk; case dev(clerkId: String) }
```

Initialiser:

- `AppConfig.isClerkConfigured` → `.clerk`
- else → `.dev(clerkId: UserDefaults.standard.string(forKey: "anitrack.devClerkId") ?? "")`

Observable state: `mode`, `isSignedIn: Bool` (starts `false`), `lastError: String?`, `bootstrapped: Bool`
(starts `false`).

### 8.2 App start-up order (`AniTrackApp.init`)

1. `applyBrandFont()` (UIKit tab-bar appearance proxy — Outfit at 10 pt medium/semibold).
2. `AppAppearance.install()`.
3. **If `isClerkConfigured`: `Clerk.configure(publishableKey:)` — synchronously, before the view hierarchy
   builds.** "Accessing `Clerk.shared` without calling `configure()` first triggers an assertion failure."
4. Build `AuthManager`, then `AppModel(api: APIClient(tokenProvider: auth))`.
5. `model.onSessionExpired = { [weak auth] in auth?.sessionExpired() }` — "a rejected session is auth's
   problem, not the loader's."
6. Notification delegate + open handler installed **before launch completes**.
7. `rootContent` injects `Clerk.shared` into the environment **only when configured**.
8. `.task { await auth.bootstrap() }` on the root view.

### 8.3 `bootstrap()`

```
if AppConfig.isClerkConfigured:
    deadline = now + 3s
    while !Clerk.shared.isLoaded && now < deadline:
        sleep 80 ms
    refreshClerkSignInState()          // isSignedIn = (Clerk.shared.session != nil)
    bootstrapped = true
    cancel any previous watch
    start a Task: for await event in Clerk.shared.auth.events {
        if case .sessionChanged: refreshClerkSignInState()
    }
else:
    if case .dev(clerkId) = mode { isSignedIn = !clerkId.isEmpty }
    bootstrapped = true
```

Poll interval **80 ms**, hard cap **3 s**. `bootstrapped` is set **whether or not** Clerk finished loading —
the wait is a courtesy, not a gate.

> *Why (quoted)*: "The session used to be read exactly once, the instant this ran — before Clerk had
> necessarily restored it — and never re-derived, so a returning user could land on sign-in with a valid
> session and nothing to correct it."

`refreshClerkSignInState()`: `isSignedIn = Clerk.shared.session != nil`; **if signed in, clear `lastError`**
("a fresh session answers whatever the last one failed at").

### 8.4 The splash hand-off (`RootView`)

Two conditions, both required, before the splash leaves:

| Condition | Set by |
|---|---|
| `splashFinished` | `SplashView`'s own timeline: hand-off at **1.68 s** (Reduce Motion: a fixed frame at t = 1.4 and a **1.2 s** sleep, and **no haptic**) |
| `auth.bootstrapped` | `bootstrap()` |

`handOffIfReady()` → `withAnimation(ThemeMotion.uiSettle)` (`spring(response: 0.46, dampingFraction: 0.90)`)
sets `splashDone = true` and `appModel.surfaceReady = true`. Re-evaluated on `onChange(of: auth.bootstrapped)`
and from the splash callback; guarded by `!splashDone`.

Splash motion detail relevant to the port: at **0.92 s** ("ignite") one `.selection` haptic fires — suppressed
entirely under Reduce Motion. The revealed app is drawn at `scaleEffect(0.965)` + `blur(4)` until `splashDone`
(both skipped under Reduce Motion, which crossfades instead).

Then: `auth.isSignedIn ? MainTabView() : SignInView()`, each with `.transition(.opacity.animation(uiGentle))`.
`MainTabView` carries `.task(id: auth.isSignedIn) { appModel.start() }`, and
`onChange(of: auth.isSignedIn) { if !signedIn { appModel.teardown() } }`.

### 8.5 Dev bypass

`signInDev(clerkId:)`:

1. Trim whitespace/newlines.
2. Empty → `lastError = "Enter a dev user id."`, return (no state change).
3. Persist to `UserDefaults` key **`anitrack.devClerkId`**.
4. `mode = .dev(clerkId: trimmed)`, `isSignedIn = true`, `lastError = nil`.

Token form is `"dev:" + clerkId` (§8.9). The server accepts it only when `APP_ENV != production` **and**
`DEV_AUTH_BYPASS` is set; a production process rejects it with `401 {"error":"invalid token"}` regardless,
and **refuses to boot** if it has `DEV_AUTH_BYPASS` set or has neither `CLERK_JWT_KEY` nor `CLERK_SECRET_KEY`.

### 8.6 `signOut()` — the return contract

```swift
@discardableResult func signOut() async -> Bool
```

**Returns `true` only when the session actually ended.**

| Mode | Behaviour | Return |
|---|---|---|
| `.clerk` | `lastError = nil`; `try? await Clerk.shared.auth.signOut()` (**errors swallowed**); `refreshClerkSignInState()` | `!isSignedIn` — i.e. `false` if Clerk could not end the session (typically offline) |
| `.dev` | remove `anitrack.devClerkId`; `mode = isClerkConfigured ? .clerk : .dev(clerkId: "")`; `isSignedIn = false` | always `true` |

> *Why (quoted)*: "`false` when the session is still standing afterwards — Clerk could not end it (no
> connection, usually). The caller says so; before, the spinner simply stopped and the Profile sheet sat
> there signed in with nothing to explain why."

### 8.7 `sessionExpired()` — the one forced sign-out

```swift
func sessionExpired() {
    guard isSignedIn else { return }
    Task {
        await signOut()
        isSignedIn = false                                   // forced, even if Clerk's sign-out failed
        lastError = APIError.unauthorized.errorDescription   // "You’re signed out. Sign in again to continue."
    }
}
```

Reached only from `AppModel.handleSessionExpired()`, which is reached only from
`catch APIError.unauthorized` in `reload()`. That handler first calls `AppModel.teardown()` — which clears
the in-memory library, cancels the clock/search/trending tasks, deletes `library-cache.json`, resets
`RewatchStore`/`SeasonSweepLedger`, and tears down `SyncCenter` — and only then calls `onSessionExpired?()`.

> "A 403 must never reach here: a Cloudflare/WAF challenge says nothing about the user's session, and
> signing them out on it is the exact regression observed on 2026-08-22."

The forced `isSignedIn = false` after a failed Clerk sign-out is deliberate: "A Clerk sign-out that failed
locally must not leave us 'signed in' against a server that disagrees; the next sign-in re-authenticates
either way."

### 8.8 Display identity

Two accessors; only one is legal.

`displayName: String` — Clerk `user.firstName` (non-empty) → first email address → `"Signed in"`;
dev mode → the clerk id, or `"Developer"` when empty.

`avatarInitial` is **`@available(*, deprecated)`. Do not port it.**

> "It is what produced 'U' on Today (from the raw Clerk id `user_…`) while Profile independently produced
> 'Y' (from its own fallback label 'Your account'): one user, two meaningless letters, one tap apart.
> A wrong initial is worse than no initial."

`identity: AccountIdentity` is **the one identity** both the Today avatar and the Profile monogram read.

```swift
struct AccountIdentity: Equatable, Sendable {
    enum Provenance { case name, email, anonymous, developer }
    let displayName: String
    let initial: String?          // nil means "draw the symbol", NOT "draw a bullet"
    let provenance: Provenance
    static let fallbackSymbol = "person.fill"
    var monogram: String? { initial ?? AuthManager.letter(of: displayName) }
}
```

Resolution, strictly in this order:

| Mode / data | `displayName` | `initial` | `provenance` |
|---|---|---|---|
| Clerk, `user.firstName` trims to something whose first character is a **letter** | that name | uppercased first letter | `.name` |
| Clerk, first email address non-empty | the **full email** | first letter of the local part (before `@`), or nil | `.email` |
| Clerk, neither | `"Your account"` | `nil` | `.anonymous` |
| Dev | `"Your account"` | `nil` | `.developer` |

```swift
nonisolated static func letter(of raw: String) -> String? {
    guard let first = raw.trimmingCharacters(in: .whitespacesAndNewlines).first,
          first.isLetter else { return nil }
    return String(first).uppercased()
}
```

**A leading digit, punctuation or emoji is not an initial.** An opaque provider id (`user_2xK…`) and
interface copy ("Your account", "Signed in", "Developer") may never be reduced to a letter — which is why
dev mode's `displayName` is `"Your account"` and its id lives only in a debug affordance.

Note the fallback chain in `monogram` means `.anonymous`/`.developer` still yield **"Y"** (from
"Your account"). `AccountDisc` draws `PreviouslyMark(width: diameter * 0.34, detail: .none)` only when
`monogram` is nil — which, given the chain, is unreachable in practice for these two provenances. Port the
chain as written; do not "fix" it silently.

`AccountDisc` (56 pt on Profile): `Circle` filled `accentSoft` (`#F0A24E` @ 14 %) — or `surfaceRaised`
`#242428` in `quiet` mode (Today's header) — a 1 pt `posterEdge` (`white @ 9 %`) stroke border, monogram at
`system(size: diameter * 0.42, weight: .semibold)` in `accent` (or `textSecondary` when quiet),
`minimumScaleFactor 0.6`, `lineLimit 1`, whole view `accessibilityHidden(true)`.

Profile's identity row: 56-pt disc + name at `showTitleL` (Outfit SemiBold 22, tracking −0.35, `lineLimit 1`,
`minimumScaleFactor 0.7`), provenance at `metadata` (footnote) in `textSecondary`, then the one quiet library
line. VoiceOver: label `"Signed in as <accountName>"`, value = provenance + library summary joined `", "`,
trait `.isHeader`, children ignored.

Provenance string: `.developer` → `"Developer session"` **only under `#if DEBUG`**, else `"Signed in"`;
every other provenance → `"Signed in"`.

> "'Developer session' is a debug string one build configuration away from a TestFlight screenshot, so it
> is gated. A Release build that somehow reaches dev mode says the true thing instead of the embarrassing one."

### 8.9 `TokenProvider` implementation

| Method | `.dev(clerkId)` | `.clerk` |
|---|---|---|
| `currentToken()` | **`nil` unless `AppConfig.isLocalBackend`**; then `nil` if the id is empty, else `"dev:\(clerkId)"` | `try? await Clerk.shared.auth.getToken()` (may be cached; nil if signed out) |
| `hasSession()` | `!clerkId.isEmpty && AppConfig.isLocalBackend` | `Clerk.shared.session != nil` |
| `refreshedToken()` | `.notRefreshable` | `getToken(.init(skipCache: true))` → `nil` ⇒ `.notRefreshable`, value ⇒ `.token(v)`, throw ⇒ `.failed(error)` |

All three are `nonisolated` wrappers that hop to the main actor (Clerk is `@MainActor`).

Two rules a port must keep:

1. **A dev token is never sent toward a non-local backend** — even in a Debug build, even if one survived
   in storage. "In a Release build pointed at production this is what guarantees a stored dev id cannot leak."
2. **`hasSession()` must not touch the network.** "The whole point is to answer while the network is down."
   Dev mode additionally requires a local backend, "because a stored dev id is genuinely unusable against
   production — that IS a signed-out state, not a connectivity one."

---

## 9. Sign-in screen (`SignInView`)

Environment: `AuthManager`, `accessibilityReduceMotion`, `dynamicTypeSize`.
`isAX` = `typeSize.isAccessibilitySize`.

### 9.1 Layout

```
ZStack
├ ThemeColor.canvas (#09090B) .ignoresSafeArea()
└ VStack(spacing: 0)
  ├ Spacer(minLength: 32)          // ThemeSpace.x8
  ├ identity
  ├ Spacer(minLength: 32)          // x8   ─┐ two spacers below, one above:
  ├ Spacer(minLength: 0)           //      ─┘ the identity lands on the UPPER THIRD
  └ action
  .padding(.horizontal, 24)        // x6
  .padding(.bottom, 40)            // x10
```

> "Two equal spacers pinned the identity to the exact vertical centre and stapled the button to the floor.
> The identity now sits on the upper third, where a title card sits."

### 9.2 `identity` block

`VStack(spacing: 0)`, `.frame(maxWidth: .infinity)`:

| Element | Spec |
|---|---|
| Brand mark | `PreviouslyMark(width: 58)` → drawn height `58 × 1.58 = 91.64` pt. Vector bookmark shape, fill = linear gradient `#FFD6A0 → #F0A24E → #C9702E` topLeading→bottomTrailing, with a capsule "progress slot" of width `58 × 0.56 = 32.48` and height `58 × 0.12 = 6.96`. `finish: .flat` (no rim light / carve). |
| Bloom (background of the mark) | `RadialGradient(colors: [accent@0.20, accent@0.05, .clear], center: .center, startRadius: 0, endRadius: 260)`, framed `520 × 520`, `.blur(radius: 24)`, `.allowsHitTesting(false)`, `.accessibilityHidden(true)` |
| Wordmark | `Text("Previously" + Text(".").foregroundStyle(accent))` — the **period is amber, the word is `textPrimary` `#F4F1EC`**. Type `displayXL` = Outfit-Bold 34, tracking −0.80, relative to `.largeTitle`. `.padding(.top, 20)` (`ThemeSpace.x5`). `.accessibilityLabel("Previously")` |
| Tagline | **"Know what changed. Record what you watched."** Type `heroMeta` = Outfit-Regular 15, tracking −0.05, relative to `.subheadline`, colour `textSecondary` `#AAA6A0`, `.multilineTextAlignment(.center)`, `fixedSize(horizontal: false, vertical: true)`, `.padding(.top, 10)` (`ThemeMetrics.labelGap`), `.padding(.horizontal, isAX ? 0 : 24)` |

> *Why the bloom is centred (quoted)*: "The accent wash ran from the status bar downward while the mark sat
> in the middle of the screen, so the screen's only light source had nothing to do with its only object."
> And: `PreviouslyMark` used to carry a raw `.shadow(color: accent.opacity(0.3), …)` — "a coloured glow
> behind a logo, and not a `ShadowToken`. Removed; the bloom does that job honestly."

### 9.3 `action` block — three mutually exclusive branches

`VStack(spacing: 12)` (`ThemeSpace.x3`), with
`.animation(ThemeMotion.pick(uiGentle, reduceMotion:), value: auth.lastError)`.

| Condition | Content |
|---|---|
| `AppConfig.isClerkConfigured` | `Button("Sign in") { showClerkAuth = true }` styled `PrimaryButtonStyle2` |
| `devSignInAvailable` (see below) | `DevSignInCard` (DEBUG only) |
| otherwise | `Text("Sign-in isn’t available in this build.")`, type `metadata` (footnote), colour `textTertiary` `#85817C`, centred, full width |

Below the branch, when `auth.lastError != nil`: `InlineNotice(error)`.

> *Why the fail-closed branch (quoted)*: "no key, no field, no bypass, and nothing a reviewer could mistake
> for a way in. The condition is a build misconfiguration, so it is stated as one rather than dressed up as
> a temporary outage the user could wait out."

`devSignInAvailable` — **two gates, both required**:

```swift
#if DEBUG
return !AppConfig.isClerkConfigured && AppConfig.isLocalBackend
#else
return false
#endif
```

> "`#if DEBUG` keeps the panel out of any build that can reach the App Store — a raw text field and the
> string 'the backend must allow DEV_AUTH_BYPASS outside production' as the first screen of a submitted app
> is an automatic rejection and a one-star screenshot. `isLocalBackend` keeps it out of a debug build that
> has been pointed at a real host."

`PrimaryButtonStyle2`: label type `button` (Outfit-SemiBold 16, tracking −0.15, relative to `.callout`),
ink `onAccent` `#0B0B0D`, `frame(maxWidth: .infinity, minHeight: 48)`, `.padding(.horizontal, 18)`,
capsule background `accent` `#F0A24E` (pressed: `accentPressed` `#D88D3B`), plus a 1 pt `strokeBorder`
capsule of `LinearGradient([controlSheen (white @ 22 %), .clear], top → center)` — "a lit top edge … one
22 %-white hairline along the top, dead by the vertical centre, is what makes it read as a physical,
pressable object." Disabled opacity `0.38`. Press feedback via `pressFeedback(_:reduceMotion:)`.

`InlineNotice` (failure kind): a footnote **line**, never an alert box —
`HStack(alignment: .firstTextBaseline, spacing: 6)` of an SF Symbol `wifi.exclamationmark` at
`system(size: 12, weight: .semibold)` in `textTertiary`, then the message at `metadata` in `textSecondary`
with `fixedSize(vertical: true)`; the pair is `accessibilityElement(children: .combine)` with
`accessibilityLabel(message)`. Container `frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)`,
`.transition(.opacity)`. At accessibility text sizes the H-stack becomes a `VStack(alignment: .leading, spacing: 4)`.

### 9.4 Clerk sheet

```swift
.sheet(isPresented: $showClerkAuth) {
    AuthView()                                  // ClerkKitUI prebuilt sign-in/up flow
        .environment(Clerk.shared)
        .onChange(of: Clerk.shared.session != nil) { _, signedIn in
            if signedIn { auth.refreshClerkSignInState(); showClerkAuth = false }
        }
}
```

The app **does not implement email/password/OAuth UI itself** — it presents Clerk's own `AuthView`. This is
the single biggest port decision in this document (§13).

### 9.5 `DevSignInCard` (DEBUG only)

`VStack(alignment: .leading, spacing: 10)`, `.padding(16)` (`ThemeSpace.x4`),
`.surface(.raised, radius: ThemeRadius.card = 22)` — i.e. `surfaceRaised` `#242428` ground, clipped to a
continuous-corner rounded rect, with the surface system's lift overlay and a `.card` shadow.
**No grey outline** — "a card is visible because it is LIGHTER and lit along its top edge, not because it
has a grey line drawn round it."

| Element | Spec |
|---|---|
| auto-sign-in probe | `Color.clear.frame(height: 0).onAppear { if UserDefaults.standard.bool(forKey: "devSignInAuto"), !devId.isEmpty { onContinue() } }` |
| Eyebrow | `SectionLabel(text: "Developer sign-in")` → uppercased, `system(.caption2, weight: .semibold)`, tracking 1.0, `textSecondary`, 1 line (2 at AX sizes) |
| Explainer | **"No Clerk key configured. Sign in with a dev user id (the backend must allow DEV_AUTH_BYPASS outside production)."** — `metadata`, `textSecondary`, wraps |
| Field | `TextField("dev user id", text: $devId)`, autocapitalisation off, autocorrection disabled, type `body` (Outfit-Regular 17, tracking −0.10), ink `textPrimary`, caret `.tint(accent)`, `.padding(.horizontal, 14)`, `frame(minHeight: 44)`, background `surfaceFloating` `#2A2D36` in `RoundedRectangle(cornerRadius: 12, style: .continuous)`, overlaid `strokeBorder(stroke = white @ 12 %, lineWidth: 1)`, `.padding(.top, 4)` |
| Button | `Button("Continue")` with `PrimaryButtonStyle2`, `.padding(.top, 4)` |

`strokeBorder`, never `stroke`: "a control may carry a full-perimeter edge, but a centred 1-pt line
straddles the shape and smears outside it."

Initial field value: `UserDefaults.standard.string(forKey: "devSignInId") ?? "demo-user"`.

### 9.6 Debug launch arguments touching auth

| Argument | Effect |
|---|---|
| `-devSignInId <clerkId>` | pre-fills the dev field so a scripted simulator run needs no typing |
| `-devSignInAuto 1` | signs in on appear with the seeded id |

(These are `UserDefaults` reads of launch arguments — the standard iOS `-key value` mechanism.)

---

## 10. Account deletion (`AccountDeletion`)

### 10.1 Why it bypasses `APIClient` (quoted, in full, because it is the design)

> "That client is built for reads and for writes the app can replay: it retries transport failures and
> silently refreshes a 401. Both behaviours are wrong here. A request the app is not certain reached the
> server must be REPORTED, not quietly repeated, and a session that has expired must be re-authenticated
> by the user before their account is destroyed — not renewed behind a confirmation they gave a minute ago.
> One attempt, one answer, and the answer is shown to the user either way."

### 10.2 The request

```
DELETE  {baseURL}/me
Authorization: Bearer <token from AuthManager.currentToken>
Accept: application/json
(no body at all)
timeoutInterval = 20 s
session = URLSession.shared          // injectable for tests
```

No body: "the route rejects a body it does not recognise, and there is nothing an erasure needs to say
beyond who is asking." The server validates `z.object({}).strict()` on `req.body ?? {}` with `safeParse`
and answers **400 `{"error":"unexpected body"}`** for anything else (deliberately not a thrown ZodError,
which would surface as a 500 — "'the server broke' is the wrong answer to 'you sent me a field I do not know'
on the one route that cannot be undone").

### 10.3 Outcome mapping

| Condition | Thrown | Message shown |
|---|---|---|
| token is nil or empty (before any request) | `.notSignedIn` | "You’re signed out. Sign in again to delete your account." |
| `session.data(for:)` throws, **or** the response is not `HTTPURLResponse` | `.unreachable` | "Couldn’t reach the server. Your account wasn’t deleted." |
| 200 **and** body decodes to `{ deleted: true }` | — (success) | — |
| 200 with any other body | `.refused` | "Your account couldn’t be deleted. Nothing was changed." |
| 204 | — (success) | — |
| 401 or 403 | `.notSignedIn` | as above |
| any other status | `.refused` | as above |

The 200-but-wrong-body rule exists because "a 200 carrying anything else is a proxy or a captive portal
answering for the server, and must not be read as a deletion." **No retries. Ever.**

Note the deliberate divergence from `APIClient`: here **403 maps to "signed out"**, because on this one
route the safest report is "we did not delete anything and you may need to sign in again."

### 10.4 The Profile flow around it

State: `@State confirmDelete`, `@State deleting`, `@State deleteFailure: String?`.

Row (`deleteSection`) — its own `GroupedList` plate **below the colophon**, separated from Sign out by
`ThemeSpace.x8` (32) after `ThemeSpace.x10` (40) of colophon padding:

- symbol `trash` tinted `destructive` `#FF453A`, title **"Delete account"** in `destructive`,
  subtitle **"Erases your library, progress and history"**, no separator.
- While `deleting`: a small `ProgressView` tinted `destructive` in a 44 × 44 frame.
- `.disabled(signingOut || deleting)`.
- `accessibilityHint("Permanently deletes your account and library")` — "VoiceOver carries a severity that
  colour alone no longer does."

Confirmation is an **`.alert`, never a `confirmationDialog`**:

> "On this SDK a confirmation dialog renders as a source-anchored card that suppresses its own `.cancel`
> button — the capture showed one red 'Sign out' capsule floating over undimmed content, so the only way to
> back out of a destructive confirmation was to tap outside it, which is undiscoverable. An alert is the
> presentation that guarantees the three things this moment needs: a dimming scrim, an explicit Cancel, and
> the destructive verb rendered as destructive."

| Alert | Title | Buttons | Message |
|---|---|---|---|
| confirm delete | **"Delete your account?"** | "Cancel" (`.cancel`), **"Delete account"** (`.destructive`) | `deleteMessage` (below) |
| delete failed | **"Couldn’t delete your account"** | "Done" (`.cancel`) | the thrown `errorDescription` |

`deleteMessage` — "The blast radius, in the user's own numbers. The strongest copy in the app; not shortened":

```
"This permanently deletes your account and everything in it"
+ (titles > 0 ? " — \(Copy.titles(titles)), all progress and watch history" : "")
+ ". It can’t be undone."
```

where `titles = appModel.library.count` and `Copy.titles(n)` = `"\(n)\u{00A0}title"` / `"…titles"` —
**a NO-BREAK SPACE (U+00A0) between the number and its unit**, app-wide, so a line never wraps inside one fact.

`performDelete()`:

1. `FeedbackCoordinator.fire(.destructive)` → `UINotificationFeedbackGenerator.notificationOccurred(.warning)`.
2. `withAnimation(ThemeMotion.pick(uiGentle, reduceMotion:)) { deleting = true }`.
3. `try await AccountDeletion.deleteAccount(token: auth.currentToken)`.
4. On success: `ProfileSnapshot.clear()` → `await auth.signOut()` → `deleting = false` → `dismiss()`.
   ("A deleted account may not leave its counts on the device.")
   The resulting `isSignedIn == false` drives `RootView` to `appModel.teardown()` and back to `SignInView`.
5. On failure: `deleting = false`; `deleteFailure = (error as? LocalizedError)?.errorDescription ?? Failure.refused.errorDescription`.

---

## 11. Sign-out UI (Profile)

Row (`signOutSection`), its own `GroupedList`:

- symbol `rectangle.portrait.and.arrow.right` tinted **`textSecondary`** (not destructive), title
  **"Sign out"** tinted `destructive`, no separator, no subtitle.
  > "The colour carries the weight — but only on the LABEL: a fully saturated destructive icon on a routine,
  > reversible action made Sign out and Delete account read as a pair of equal choices."
- While `signingOut`: small `ProgressView` tinted `textSecondary` in a 44 × 44 frame.
  > "Every other write in the app is optimistic and shows its result immediately; the one that cannot be
  > undone showed nothing at all, so a user who waited a second tapped Sign out again."
- `.disabled(signingOut || deleting)`, `accessibilityHint("Your library stays in your account")`.

Alerts:

| Alert | Title | Buttons | Message |
|---|---|---|---|
| confirm | **"Sign out?"** | "Cancel" (`.cancel`), **"Sign out"** (`.destructive`) | `signOutMessage` |
| failed | **"Couldn’t sign out"** | "Done" (`.cancel`) | **"Check your connection and try again."** |

`signOutMessage` — one outcome, one supporting sentence; the pending-changes case earns a second clause
because it carries a second fact:

- no pending failed changes → **"Your library stays in your account — sign back in any time."** (em dash)
- `pending > 0` →
  `"Your library stays in your account. \(Copy.changes(pending)) \(verb) synced yet — \(pronoun) on this device and upload the next time you sign in."`
  with `verb = pending == 1 ? "hasn’t" : "haven’t"` and `pronoun = pending == 1 ? "it stays" : "they stay"`.
  > "'3 changes hasn't' — the one verb in the app that has to agree with its count."

`performSignOut()`: `.destructive` haptic → animate `signingOut = true` → `await auth.signOut()` →
`signingOut = false` → `if !signedOut { signOutFailed = true }`.
"Deletion had a failure alert; sign-out had none. Same moment, same answer."

Haptics reference for this layer (`FeedbackCoordinator`, the **only** haptic path in the app, at most one
per transaction, suppressed when the app is not `.active` and when the user's `previously.haptics` default
is off; per-token floor 0.3 s, 0.04 s for `.selection`):

| Token | Generator | Used here |
|---|---|---|
| `.destructive` | `UINotificationFeedbackGenerator(.warning)` | sign out, delete account |
| `.selection` | `UISelectionFeedbackGenerator` | splash ignite at 0.92 s |

---

## 12. Reconciliation with `docs/api-contract.md`

### 12.1 Agreements worth restating

- Bearer on everything but `/health`; times in ms epoch.
- Client failure semantics in the contract's **"Client failure semantics"** section match `APIClient`
  exactly: one refresh then sign out on 401; 403 and any HTML body are infrastructure with the session kept;
  a token that cannot be **minted** and a refresh that cannot **reach** the issuer are transport;
  "~16.6 s: a 15 s attempt plus at most ~1.6 s of backoff"; 429/5xx retried twice, `Retry-After` honoured
  and capped at 8 s; an exhausted 5xx with an HTML body lands as infrastructure.
- `FranchiseListResponse`'s honesty fields are `/search`-only and every one is optional, and the client
  decodes them leniently (`try? decodeIfPresent`) while `franchises` stays a hard requirement.
- `DELETE /me` semantics, including the empty-body rule and "the client signs out immediately afterwards."

### 12.2 Divergences and dead ends — flag these to the Android team

| # | Item | Status |
|---|---|---|
| 1 | `GET /me/notifications?limit=50` and `POST /me/notifications/read` are in the contract **and implemented on the server**, but **`APIClient` has no method for either** and nothing in the iOS app calls them. In-app "notifications" are local `UNUserNotification`s built from `part.airings`, not server rows. | Do **not** port these endpoints unless the Android product explicitly adds the feature. |
| 2 | `APIClient.health()` exists and is the only `auth: false` call — **no call site anywhere in the app**. | Dead code. Keep or drop; if kept, it is the natural reachability probe. |
| 3 | The contract's "Client-side derivation" section says all time math is **IST (Asia/Kolkata)** and names legacy helpers to port. The shipped app does **not** do this: it uses the device's local calendar for AniList and a **UTC date** anchor for TMDB (`MediaSource.timeAnchor`). | The contract paragraph is stale. Follow the code (and the model-layer spec), not the contract. |
| 4 | Contract §"Client-side derivation" also says `Today/"Out now"` = `lastAiredAt > prevOpenedAt` and `availableEpisodes` from `airedEpisodes`. The app derives freshness from `FranchisePart.airings` instead. | Stale; see the models/Today specs. |
| 5 | Contract lists `GET /franchises/:id?country=IN` as optional. The app **always** sends `country` on the detail read except one legacy call site (`FranchiseDetailView.swift:1749`). | Send it always. |
| 6 | Contract does not mention that the client treats a **200 with an HTML body** as infrastructure. It does (branch 4). | Port it. |
| 7 | `trending`'s Swift default is `limit: 30`; every real caller passes `10`. | Default to what the callers use. |
| 8 | `AccountDeletion` maps **403 → notSignedIn**, contradicting `APIClient`'s "403 is never a sign-out" rule. | Intentional, route-specific. Keep. |
| 9 | Two log subsystems: `com.anitrack.app` (api) and `app.previously` (model). | Cosmetic; unify if you like. |
| 10 | `APIError.decoding` is also thrown for request-**encoding** failures. | Name the Kotlin case `serialization` to cover both. |

---

## 13. Android portability notes

### 13.1 Straightforward

| iOS | Android | Notes |
|---|---|---|
| `URLSession` with request/resource timeouts | OkHttp `callTimeout` (= the 17.6 s resource cap), `readTimeout`/`connectTimeout` (the 15 s per-attempt) | OkHttp's `callTimeout` maps cleanly to `timeoutIntervalForResource`; set it per-call from the remaining budget with `newBuilder()`. |
| `JSONDecoder` (no key strategy) | `kotlinx.serialization` with `ignoreUnknownKeys = true`, `explicitNulls = false` | Lenient decoding is a stated requirement of the enrichment models. |
| `actor TokenRefresher` | class with `kotlinx.coroutines.sync.Mutex` + cached `token`/`at` | Preserve the 3 s reuse window and success-only priming. |
| `Logger(subsystem:category:)` | `Log`/Timber with a fixed tag | The exact line formats above make single-flight and retry verifiable. |
| `UserDefaults` (`anitrack.devClerkId`, `previously.haptics`, `devSignInId`, `devSignInAuto`) | `DataStore` (preferences) | The dev id is not a secret (it is only ever sent to a LAN host), so `EncryptedSharedPreferences` is optional. |
| `AppConfig` | `BuildConfig` fields per flavour | Reproduce the `REPLACE_ME`/blank → `null` rule so a placeholder never becomes a broken legal link. |
| `NSAllowsLocalNetworking` | `network_security_config.xml` scoped cleartext | No runtime permission prompt on Android. |
| SF Symbols used here (`wifi.exclamationmark`, `trash`, `rectangle.portrait.and.arrow.right`, `person.fill`, `info.circle`) | Material Symbols / custom vectors | Trivial; pick equivalents once, app-wide. |

### 13.2 Hard or blocked

1. **Clerk iOS SDK (`ClerkKit` + `ClerkKitUI`, pinned `from: "1.2.4"`) — BLOCKER-adjacent.** The app never
   implements a credential UI: it presents Clerk's prebuilt `AuthView()` and reads `Clerk.shared.session`,
   `.user`, `.auth.getToken(skipCache:)`, `.auth.signOut()`, and the `auth.events` async sequence.
   Clerk publishes an Android SDK, but its API surface, its prebuilt UI component, and its
   `isLoaded`/`events` equivalents are not guaranteed to match. **Verify the Android SDK's capabilities
   before committing**, and if a prebuilt component does not exist, the sign-in screen grows from "one
   button" into a whole flow (email/OAuth/MFA) that this spec does not describe. Everything downstream —
   the ≤3 s `isLoaded` wait, the session-changed subscription, `getToken(skipCache: true)` — must be mapped
   onto whatever the Android SDK offers, or the `TokenProvider` contract reimplemented against Clerk's REST API.
2. **`@Observable` + SwiftUI environment injection** → `StateFlow` in a `ViewModel` (or a DI-scoped singleton).
   Mechanical, but `AuthManager` is `@MainActor`; every `TokenProvider` method hops to the main actor and is
   awaited from a background transport. In Kotlin, make the provider thread-safe instead
   (`withContext(Dispatchers.Main.immediate)` only where the SDK demands it) — do **not** naively force the
   whole provider onto `Dispatchers.Main`.
3. **Cancellation semantics invert.** iOS swallows cancellation at the consumer; Kotlin must rethrow
   `CancellationException` and suppress only the UI effect. Also map OkHttp's cancelled-call `IOException`
   ("Canceled") and `InterruptedIOException` into the same predicate.
4. **`URL(string:relativeTo:)` resolution** discards a base path; `HttpUrl.resolve()` behaves the same way
   for a leading-slash path, so this ports — but `appendingPathComponent` in `AccountDeletion` does **not**,
   and the two must be reconciled deliberately.
5. **Splash → sign-in hand-off timing** (1.68 s / 1.2 s Reduce Motion, `scaleEffect(0.965)` + `blur(4)`,
   spring `response 0.46 / damping 0.90`) sits on SwiftUI's `withAnimation` + `TimelineView`. Compose can do
   all of it (`Animatable`, `spring(dampingRatio, stiffness)`), but the spring parameters do **not** map
   one-to-one: SwiftUI's `response`/`dampingFraction` must be converted (`stiffness ≈ (2π/response)²`,
   `dampingRatio = dampingFraction`). Blur on Android requires API 31+ `RenderEffect` or a
   `graphicsLayer`/shader fallback below it.
6. **Haptics.** `UINotificationFeedbackGenerator(.warning)` has no exact Android twin; use
   `VibrationEffect.createPredefined(EFFECT_HEAVY_CLICK)` or a short two-pulse `VibrationEffect.createWaveform`.
   Keep the per-token throttle (0.3 s; 0.04 s for selection) and the "never while inactive" and
   "respect the app's own haptics toggle" rules.
7. **Reduce Motion / Reduce Transparency.** Android exposes
   `Settings.Global.ANIMATOR_DURATION_SCALE == 0` and `AccessibilityManager.isReduceMotionEnabled` is not a
   thing pre-API 34 (`ACCESSIBILITY_DISPLAY_*`). Expect an approximation: read the animator duration scale.
   There is no Reduce Transparency equivalent at all — the material-bar rule ("never opaque canvas except
   under Reduce Transparency") loses its exception branch.
8. **Dynamic Type cap.** `.dynamicTypeSize(...DynamicTypeSize.accessibility2)` at the app root has no direct
   Compose analogue; clamp `LocalDensity.fontScale` manually (e.g. `min(fontScale, 1.8f)`) in a
   `CompositionLocalProvider` at the root, and reproduce the `isAX` branch (`fontScale >= ~1.6`) that the
   sign-in tagline and `InlineNotice` use.
9. **Bundled brand font (Outfit, 5 weights) as the inherited default** — trivial in Compose
   (`Typography` + `FontFamily`), but note iOS additionally sets it on `UITabBarItem.appearance()` because
   UIKit draws the tab titles. Compose has no such split.

---

## 14. Test hooks the port should keep

- `AccountDeletion.deleteAccount(baseURL:session:token:)` takes an injectable `URLSession` "so the call is
  exercisable without a network."
- `APIClient.init(baseURL:tokenProvider:session:)` takes an optional session for the same reason.
- The proxy recipe for photographing non-happy states: build with `API_BASE_URL=http://localhost:8799` and
  run the scratchpad `proxy.py` with a mode file (`pass / down / refuse / slow / empty / searcherr /
  detailfail / writefail`). An Android port wants the same fault-injection proxy.
- Server-side deploy assertion: `npm run auth:smoke -- https://<host>` asserts `GET /health` → 200 and
  `GET /me/library` with a `dev:` bearer → **401**, exiting non-zero otherwise. Run it against any host the
  Android client will point at.
