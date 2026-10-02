# Second-pass audit evidence

All files concern commit `572cb857d73222f5a1b16a4025a24fe1566387c8` on 30 September 2026. Product source, production data/configuration and dependencies were not changed.

## Release build

Executed from the repository root:

```sh
xcodebuild -project ios/Previously.xcodeproj -scheme Previously \
  -configuration Release -destination 'generic/platform=iOS Simulator' build \
  > docs/audits/2026-09-30/round-2-evidence/ios-release-simulator-build.log 2>&1
```

Normal simulator signing and configuration; succeeded. `release-bundle-inspection.json` records selected Info.plist fields, privacy-manifest paths and distinct warning diagnostics. It records Clerk key environment without reproducing the full publishable key. The inspected bundle is the resulting DerivedData `Release-iphonesimulator/Previously.app`. This is not an archive, App Store validator result, physical-device build or runtime proof. The Release app was not installed over the normal signed Debug simulator installation restored in the first pass.

## Real database reproduction

```sh
python3 docs/audits/2026-09-30/round-2-evidence/run-database-probe.py
```

The wrapper verifies that a generated `previously_release_audit_tests_20260930_<8 hex digits>` database does not exist, creates it on loopback, applies repository migrations and runs the actual Fastify routes/services/SQL through `tsx`. The TypeScript probe checks the DB name/host and synthetic environment before doing work. Dev bypass is enabled only in the test process; provider, LLM and TMDB keys are blank; search correction, grouping and news are disabled. Requests use two invented identities and invented catalogue/social records.

The wrapper closes clients and checks zero connections before dropping **only its newly owned database**, without force. `database-probe-run.json` records cleanup. Results/assertions in `database-probe-results.json` concern:

- Five invalid requests returning 500 instead of 400, with authenticated search/trending requests.
- Status PATCH returning success when there is no subscription.
- Requested progress 12, stored progress 5, acknowledgement omitting canonical value.
- Single INT4 overflow rejected with 400; bulk unsized overflow producing 500; transaction rollback confirmed; valid atomic bulk canonical response.
- Anonymous export denial, forged owner body rejection and own-only/no-store export behavior for the seeded private content.
- Suspended reads/export/deletion, erasure of seeded owned and incoming relationships across 17 tables, preservation of another author's reply and data, retained ban and no recreation after the process-memory hold is cleared.

Direct SQL seeding of a ban is followed by the existing `invalidateBanCache()` hook. Ordinary operator writes respect the documented cache TTL. The hook is test setup, not a product-bug workaround. Clearing `resetErasures()` models loss of the hold; it is not an actual process restart or a real JWT/provider test.

The final successful DB was `previously_release_audit_tests_20260930_dab0de7b` and was removed. Earlier harness-only corrections concerned ESM module format, typed JSON parameter setup and ban-cache invalidation after direct test seeding; those are not reported as app defects. Each wrapper run removed its own database, including failed runs. Existing databases were not targeted.

## Platform lifecycle diagnostic

```sh
swift docs/audits/2026-09-30/round-2-evidence/path-monitor-probe.swift \
  > docs/audits/2026-09-30/round-2-evidence/path-monitor-probe.log 2>&1
```

Uses macOS `Network.NWPathMonitor`, with two-second callback bounds. The first object delivers; after cancel, restarting that object does not deliver; a fresh object delivers. This diagnoses the platform primitive used by the app and agrees with Apple DTS. It does not execute UIKit `SyncCenter` or an actual iPhone sign-out journey, and it does not change host connectivity.

## Health recheck

`health-recheck.json` records loopback and public `/health` at 07:30 UTC. The public URL was read from the built Release Info.plist. No bearer token; diagnostic native-style user agent; 12-second request timeout. Both returned 200. This supersedes the earlier outage as the latest point-in-time result while preserving that incident in the original evidence. It is not an external-network monitor or signed-in native app test.

## Native and test boundaries

No additional current-run native interaction screenshots were generated in the second pass because Device Hub accessibility control again timed out. First-pass screenshots were captured at the same source commit and are explicitly identified as reused fixture evidence. The first pass's server typecheck and 972 mocked tests remain its results; they were not rerun after documentation/probe-only edits. Actual Release compiler warnings and the new real-DB/platform checks provide additional evidence, not a declaration of full release certification.
