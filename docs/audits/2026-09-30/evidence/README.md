# Audit evidence

These files support the adjacent App Store readiness report. Screenshots are current-run iPhone 18 Pro/iOS 27 captures. `01-sign-in.png` and `12-restored-normal-config.png` use the normal configured signed Debug app. Other screenshots use local synthetic fixtures; they do not prove production account, artwork, provider, interaction or device behavior.

`server-tests.log` and `server-typecheck.log` record the existing server suite. `ios-build-signed.log`, `ios-fixture-build.log` and `ios-restore-build.log` record successful simulator builds. The initial unsigned build was diagnostic and failed at runtime on Clerk keychain access; normal signing resolved that issue.

`fixture-server.py` serves synthetic data on loopback port 8799, performs no upstream/database calls, and refuses account deletion. It was stopped at the end of the audit. Product source was not edited.

`real-db-probe-results.json` records actual server-route/SQL behavior with a synthetic dev identity. `real-db-probe-run.json` confirms its uniquely owned test database was removed. Reproduction:

```sh
python3 docs/audits/2026-09-30/evidence/run-real-db-probe.py
```

Run from the repository root with its installed server dependencies and local PostgreSQL available. The launcher creates only a fresh uniquely named audit test database on 127.0.0.1, overrides upstream credentials with empty values, applies repository migrations, runs the probe, closes clients, checks zero remaining connections and removes only that database. It never targets the normal app database. The probe deliberately asserts the reported defects; success means those defects reproduced, not that erasure is release-ready. It uses the memory-hold reset hook to model restart and does not call Clerk.

`rewatch-probe.log` records the actual Swift store retaining old backup sessions after reset. Reproduction with a temporary binary of your choice:

```sh
swiftc -parse-as-library ios/Sources/App/RewatchStore.swift \
  docs/audits/2026-09-30/evidence/rewatch-probe.swift -o /tmp/anitrack-rewatch-audit
/tmp/anitrack-rewatch-audit
```

The probe uses only a unique temporary directory and presentation-only copy stubs. It explicitly removes the synthetic primary file to exercise existing backup recovery, then removes its temporary data. It does not assert a natural file failure or a detached-write race occurred.

`npm-audit.json` is a read-only production dependency inventory; `dependency-versions.json` records the lockfile and date-specific registry versions. Package advisories require affected-path review and are not proof of an exploitable app issue. No dependencies were upgraded. `final-health-check.json` records unauthenticated diagnostic requests from this Mac's network, not a real authenticated iPhone or continuous external uptime check.
