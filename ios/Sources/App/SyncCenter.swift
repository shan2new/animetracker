import Foundation
import Network
import Observation
import UIKit

// The trust layer: how fresh the data is, whether the device can reach anything, and which of the
// user's writes the server never accepted.
//
// It is a singleton rather than an `AppModel` extension because all of this is *stored* state and
// stored properties cannot live in an extension. It follows the `EpisodeNotifications.shared`
// precedent already in the app.
//
// Two rules it exists to enforce:
//   • a failure is never invisible and never auto-dismisses — it persists in `failedChanges`
//     until it is retried or discarded, and survives a relaunch (board 09/13);
//   • "offline" and "the server is unreachable" are different sentences, and which one the user
//     reads is decided by `isOnline` (NWPathMonitor), never guessed from an error.
@MainActor
@Observable
final class SyncCenter {

    static let shared = SyncCenter()

    // MARK: - Data classes and their staleness thresholds (board 09)

    enum DataClass: String, CaseIterable, Sendable {
        /// AniList airing instants. Wrong within half an hour is wrong.
        case exactAiring
        /// TMDB date-only schedule. A day's worth of drift is invisible; six hours is the limit.
        case dateOnlySchedule
        /// Titles, artwork, season structure. Changes on the order of days.
        case catalogue

        var threshold: Int64 {
            switch self {
            case .exactAiring: return 30 * Formatting.minuteMs
            case .dateOnlySchedule: return 6 * Formatting.H
            case .catalogue: return 24 * Formatting.H
            }
        }
    }

    // MARK: - Freshness
    //
    // There is exactly ONE freshness stamp in this app and `SyncCenter` does not own it: the model
    // that loads the library owns it (`AppModel.lastLoadedAt`) and `SyncCenter` reads it.
    // COHERENCE §1.3 spells that read `AppModel.shared?.lastLoadedAt`; neither `AppModel.shared`
    // nor `lastLoadedAt` exists in the tree yet — both are edits to `App/AppModel.swift`, a shared
    // file this track may not touch (filed as sharedFileRequest R2/SP-2) — so the read goes through
    // a closure the app installs once. The semantics are COHERENCE's: one stamp, owned by the
    // model, never copied here. A stored copy is exactly what lets Profile's "Synced 2 min ago"
    // and a screen's stale strip disagree, so both properties below are deliberately computed.

    /// What the live model currently knows about freshness. Read through `signals`, never stored.
    struct Signals: Equatable, Sendable {
        /// Epoch-ms of the last library payload that actually arrived. `0` = never.
        var lastLoadedAt: Int64 = 0
        /// A library request is in flight.
        var loading: Bool = false
    }

    /// Installed once, at the app root:
    /// ```
    /// SyncCenter.shared.signals = { [weak appModel] in
    ///     .init(lastLoadedAt: appModel?.lastLoadedAt ?? 0, loading: appModel?.loading ?? false)
    /// }
    /// ```
    /// Until it is installed, nothing can be stale and Profile reads "Not synced yet" — the honest
    /// reading of "this build has no freshness source wired", not a silent claim of freshness.
    /// Because the closure reads `@Observable` model properties, every SwiftUI view that renders
    /// `lastSyncedAt` / `checking` re-evaluates when the model's stamp moves.
    var signals: (@MainActor () -> Signals)?

    private var current: Signals { signals?() ?? Signals() }

    /// When the last library payload actually arrived. `nil` until the first successful load.
    var lastSyncedAt: Int64? {
        let ts = current.lastLoadedAt
        return ts > 0 ? ts : nil
    }

    /// A refresh is in flight. Drives Profile's "Checking for changes" line.
    var checking: Bool { current.loading }

    private var stamps: [DataClass: Int64] = [:]

    /// Optional per-class refinement: a surface that refreshes ONE class of data on its own (the
    /// schedule feed, say) stamps it here and that class stops inheriting the library-wide stamp.
    /// Nothing is required to call this — every class falls back to `lastSyncedAt`, so the stale
    /// strip works on a screen that never stamps anything.
    func stamp(_ dataClass: DataClass, at ts: Int64 = .nowMs) {
        stamps[dataClass] = ts
    }

    /// Elapsed ms since this class of data last arrived, or `nil` when it never has.
    func age(of dataClass: DataClass, now: Int64 = .nowMs) -> Int64? {
        guard let at = stamps[dataClass] ?? lastSyncedAt else { return nil }
        return max(0, now - at)
    }

    /// Past the class threshold. Never true before the first successful load: a page that has
    /// never loaded is not stale, it is loading. Artwork failures never reach here, so a failed
    /// poster can never mark a page stale.
    func isStale(_ dataClass: DataClass, now: Int64 = .nowMs) -> Bool {
        guard let age = age(of: dataClass, now: now) else { return false }
        return age >= dataClass.threshold
    }

    /// The timestamp the `StaleStrip` renders, or `nil` when nothing is stale.
    func staleSince(_ dataClass: DataClass, now: Int64 = .nowMs) -> Int64? {
        guard isStale(dataClass, now: now) else { return nil }
        return stamps[dataClass] ?? lastSyncedAt
    }

    /// Profile's account line, in precedence order: a real failure outranks a stale stamp, and a
    /// check in flight outranks a calm one.
    func syncedLine(now: Int64 = .nowMs) -> String {
        if !failedChanges.isEmpty { return Copy.Toast.syncFailed(failedChanges.count) }
        if checking { return Copy.State.checkingForChanges }
        guard let lastSyncedAt else {
            return isOnline ? Copy.State.neverSynced : Copy.State.couldNotCheck
        }
        return Copy.synced(at: lastSyncedAt, now: now)
    }

    // MARK: - Reachability

    /// The device believes it has a path to the network. A captive portal can report `true` while
    /// every request fails — accepted: claiming the user is offline when they are not is the
    /// worse lie, and the server-side copy is the honest fallback.
    private(set) var isOnline: Bool = true

    private let monitor = NWPathMonitor()
    private var monitoring = false

    /// Started once, from the app's root. Cheap, but not free — it is not started in `init`.
    func startMonitoring() {
        guard !monitoring else { return }
        monitoring = true
        monitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            Task { @MainActor in self?.isOnline = satisfied }
        }
        monitor.start(queue: DispatchQueue(label: "previously.reachability"))
    }

    func stopMonitoring() {
        guard monitoring else { return }
        monitoring = false
        monitor.cancel()
    }

    // MARK: - Failed writes

    private(set) var failedChanges: [FailedChange] = []

    /// At least one failed change has something `Retry` can actually run. A banner or a Profile
    /// row whose Retry would be a no-op must not draw the button at all.
    var canRetryAny: Bool { failedChanges.contains { $0.canRetry(self) } }

    /// What `Retry` does for a change restored from a previous launch — its closure could not be
    /// encoded, so the app supplies a full reload instead. Set once, at root.
    var onRestoredRetry: (@MainActor () async -> Void)?

    /// Keys the user has explicitly retried, and when. A re-record inside this window is a
    /// *directly* failed action and earns one `.directError`; an automatic failure is silent.
    private var userRetriedAt: [String: Int64] = [:]
    private static let directErrorWindow: Int64 = 30_000
    /// Attempts per key, kept across the optimistic removal a retry performs.
    private var attempts: [String: Int] = [:]
    /// Set while a `retryAll()` batch is in flight, so the batch fires one error haptic, not N.
    private var batchRetryToken: UUID?
    private var batchErrorFired = false

    /// Records a write the server never accepted. Called by every mutation's `catch`.
    /// The local value is NOT rolled back for progress writes — the mark is a fact about the user.
    func record(command: String, title: String, reason: String,
                retry: @escaping @MainActor () async -> Void) {
        let key = FailedChange.key(command: command, title: title)
        let now: Int64 = .nowMs
        attempts[key] = (attempts[key] ?? 0) + 1
        // One row per (command, title): a repeatedly failing write is one problem, not a list.
        if let i = failedChanges.firstIndex(where: { $0.key == key }) {
            failedChanges[i].reason = reason
            failedChanges[i].at = now
            failedChanges[i].attemptCount = attempts[key] ?? 1
        } else {
            failedChanges.append(FailedChange(id: UUID(), command: command, title: title,
                                              reason: reason, at: now,
                                              attemptCount: attempts[key] ?? 1, retry: retry))
        }
        // Exactly one error haptic, and only when the user asked for this attempt themselves.
        // Inside a `retryAll()` batch that is one haptic for the whole batch, not one per row.
        if let asked = userRetriedAt[key], now - asked <= SyncCenter.directErrorWindow {
            userRetriedAt[key] = nil
            if batchRetryToken == nil {
                FeedbackCoordinator.fire(.directError)
            } else if !batchErrorFired {
                batchErrorFired = true
                FeedbackCoordinator.fire(.directError)
            }
        }
        persist()
    }

    func discard(_ id: UUID) {
        if let change = failedChanges.first(where: { $0.id == id }) {
            attempts[change.key] = nil
            userRetriedAt[change.key] = nil
        }
        failedChanges.removeAll { $0.id == id }
        persist()
    }

    func discardAll() {
        failedChanges.removeAll()
        attempts.removeAll()
        userRetriedAt.removeAll()
        persist()
    }

    /// Retries one change. The row leaves immediately — the write is optimistic again — and the
    /// command re-records itself if it fails, which is what fires the single `.directError`.
    ///
    /// A row is **never** cleared when there is nothing to run: a restored change has no encoded
    /// closure, and if the app has not supplied `onRestoredRetry` the only honest behaviour is to
    /// leave the failure standing. Clearing it would delete the record, persist an empty list and
    /// let `syncedLine()` report "Everything synced" for a write that was never sent.
    func retry(_ id: UUID) {
        guard let change = failedChanges.first(where: { $0.id == id }),
              let run = change.effectiveRetry(self) else { return }
        let key = change.key
        userRetriedAt[key] = .nowMs
        failedChanges.removeAll { $0.id == id }
        persist()
        Task { @MainActor in
            await run()
            self.settleRetry(key)
        }
    }

    /// A retried write finished. If it failed it already re-recorded itself — `record` runs
    /// synchronously inside the command's `catch`, consuming the stamp and firing the single
    /// `.directError` — so by the time this runs the stamp means "the retry SUCCEEDED".
    ///
    /// It has to be dropped: the 30-s window is a safety net for a write that fails a moment after
    /// the tap, never a licence to treat the next unrelated background failure on the same key as
    /// something the user asked for. Board 11 says a background sync failure is silent.
    private func settleRetry(_ key: String) {
        userRetriedAt[key] = nil
        // The attempt counter belongs to a standing failure. With no row left, a later unrelated
        // failure must read "1st attempt", not inherit this key's history for the whole session.
        if !failedChanges.contains(where: { $0.key == key }) { attempts[key] = nil }
    }

    func retryAll() {
        // Only the rows that actually have something to run leave the banner.
        let runnable = failedChanges.compactMap { change -> (FailedChange, @MainActor () async -> Void)? in
            guard let run = change.effectiveRetry(self) else { return nil }
            return (change, run)
        }
        guard !runnable.isEmpty else { return }
        let now: Int64 = .nowMs
        for (change, _) in runnable { userRetriedAt[change.key] = now }
        let runnableIDs = Set(runnable.map(\.0.id))
        failedChanges.removeAll { runnableIDs.contains($0.id) }
        persist()
        // One Retry press is one transaction: the whole batch earns at most one `.directError`,
        // however many of its writes fail again and however far apart they land.
        let token = UUID()
        batchRetryToken = token
        batchErrorFired = false
        Task { @MainActor in
            for (change, run) in runnable {
                await run()
                self.settleRetry(change.key)
            }
            if batchRetryToken == token { batchRetryToken = nil }
        }
    }

    // MARK: - Banner suppression

    /// Profile lists every failed change with its reason, `Retry` and `Discard`, so the global
    /// banner would be a duplicate of the screen the user is already reading.
    var profileIsOpen: Bool = false

    /// 6 s, or 10 s while VoiceOver runs — an Undo the user cannot reach in time is not an Undo.
    var toastSeconds: Double { UIAccessibility.isVoiceOverRunning ? 10 : 6 }

    // MARK: - Persistence
    //
    // Not board 13's outbox: there is no idempotency key, no sequence and no compensating command
    // store in this prototype. What survives a relaunch is the *knowledge that a change failed*,
    // so Sync status is never falsely calm. The retry closure cannot be encoded, so a restored
    // entry retries by reloading.

    private static let storeKey = "previously.sync.failedChanges"

    private struct StoredChange: Codable {
        let id: UUID
        let command: String
        let title: String
        let reason: String
        let at: Int64
        let attemptCount: Int
    }

    private init() {
        restore()
    }

    private func persist() {
        let rows = failedChanges.map {
            StoredChange(id: $0.id, command: $0.command, title: $0.title,
                         reason: $0.reason, at: $0.at, attemptCount: $0.attemptCount)
        }
        guard let data = try? JSONEncoder().encode(rows) else { return }
        UserDefaults.standard.set(data, forKey: SyncCenter.storeKey)
    }

    private func restore() {
        guard let data = UserDefaults.standard.data(forKey: SyncCenter.storeKey),
              let rows = try? JSONDecoder().decode([StoredChange].self, from: data) else { return }
        failedChanges = rows.map {
            FailedChange(id: $0.id, command: $0.command, title: $0.title, reason: $0.reason,
                         at: $0.at, attemptCount: $0.attemptCount, retry: nil)
        }
    }

    /// Sign-out: the next account must not inherit this one's failures.
    ///
    /// `lastSyncedAt` and `checking` are not cleared here because they are not stored here — the
    /// model's own teardown resets `lastLoadedAt`, and this centre follows it.
    ///
    /// `signals` is deliberately KEPT: it is the wiring, not session data, and it captures the
    /// model weakly. The root re-installs it on the next sign-in either way.
    func teardown() {
        failedChanges = []
        stamps = [:]
        attempts.removeAll()
        userRetriedAt.removeAll()
        batchRetryToken = nil
        batchErrorFired = false
        // The path monitor runs a dispatch queue for as long as it is started; a signed-out app
        // has nothing to be reachable to. The root restarts it on the next sign-in.
        stopMonitoring()
        // Holds a closure capturing the previous session's model. Never retry into a dead account.
        onRestoredRetry = nil
        // The milestone ledger is per-account too: the next user's first season completion is
        // their own, not a token this one already spent.
        SeasonSweepLedger.reset()
        persist()
    }
}

/// One write the server never accepted. `command` is a `Copy.Action` string, `reason` a
/// `Copy.Notice.reason(_:)` string — never a status code.
struct FailedChange: Identifiable {
    let id: UUID
    let command: String
    let title: String
    var reason: String
    var at: Int64
    var attemptCount: Int
    /// `nil` for a change restored from a previous launch: the closure could not be encoded.
    let retry: (@MainActor () async -> Void)?

    /// Identity for de-duplication: the same command on the same title is one problem.
    var key: String { FailedChange.key(command: command, title: title) }
    static func key(command: String, title: String) -> String { "\(command)\u{1F}\(title)" }

    /// The retry to actually run — the recorded one, or the app-supplied reload for a restored
    /// row. `nil` when there is nothing to run: a missing retry must never be mistaken for a
    /// successful one, so there is deliberately no empty-closure fallback here.
    @MainActor
    func effectiveRetry(_ center: SyncCenter) -> (@MainActor () async -> Void)? {
        retry ?? center.onRestoredRetry
    }

    /// Whether `Retry` can do anything for this row. A row with no runnable retry keeps its place
    /// in the banner; Profile shows `Discard` as the only way out until `onRestoredRetry` is set.
    @MainActor
    func canRetry(_ center: SyncCenter) -> Bool { effectiveRetry(center) != nil }
}
