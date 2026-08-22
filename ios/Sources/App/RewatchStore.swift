import Foundation
import Observation

// Watch sessions (spec board 06 · 13). Rewatching is first-class: every completed watch is a
// session; at most one session is active per franchise. Device-local this version — atomic JSON
// in Application Support with one backup generation — so a reinstall loses history but never
// corrupts it. Progress itself stays on the server; sessions explain it.
struct WatchSession: Codable, Identifiable, Equatable, Sendable {
    enum Scope: Codable, Equatable, Sendable {
        case franchise
        case part(mediaId: Int)
    }

    let id: UUID
    let franchiseId: String
    let scope: Scope
    /// 1 = first watch, 2 = second watch, …
    let ordinal: Int
    var startedAt: Int64?
    var completedAt: Int64?
    var cancelledAt: Int64?
    var cancelledAtEpisode: Int?
    /// Episodes the session covers (for history copy); 0 when unknown.
    var episodes: Int

    var isActive: Bool { completedAt == nil && cancelledAt == nil }
    var isCompleted: Bool { completedAt != nil }
}

@MainActor
@Observable
final class RewatchStore {
    static let shared = RewatchStore()

    private(set) var sessions: [WatchSession] = []

    struct Summary: Equatable {
        let completedCount: Int
        let active: WatchSession?
        let lastCompletedAt: Int64?
    }

    private let url: URL
    private let backupURL: URL

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Previously", isDirectory: true)
        url = base.appendingPathComponent("sessions.json")
        backupURL = base.appendingPathComponent("sessions.backup.json")
        load()
    }

    // MARK: - Queries

    func sessions(for franchiseId: String) -> [WatchSession] {
        sessions.filter { $0.franchiseId == franchiseId }.sorted { $0.ordinal > $1.ordinal }
    }

    func activeSession(for franchiseId: String) -> WatchSession? {
        sessions.first { $0.franchiseId == franchiseId && $0.isActive }
    }

    func summary(for franchiseId: String) -> Summary {
        let mine = sessions.filter { $0.franchiseId == franchiseId }
        return Summary(completedCount: mine.filter(\.isCompleted).count,
                       active: mine.first(where: \.isActive),
                       lastCompletedAt: mine.compactMap(\.completedAt).max())
    }

    // MARK: - Commands

    /// Starts a rewatch. The first watch is recorded implicitly (dates unknown) when no session
    /// exists yet, so the new one is the second watch. Returns the new active session.
    @discardableResult
    func startRewatch(franchiseId: String, scope: WatchSession.Scope, startedAt: Int64, episodes: Int) -> WatchSession {
        var mine = sessions.filter { $0.franchiseId == franchiseId }
        if mine.isEmpty {
            let first = WatchSession(id: UUID(), franchiseId: franchiseId, scope: .franchise, ordinal: 1,
                                     startedAt: nil, completedAt: 0, cancelledAt: nil, cancelledAtEpisode: nil, episodes: episodes)
            sessions.append(first)
            mine.append(first)
        }
        let ordinal = (mine.map(\.ordinal).max() ?? 0) + 1
        let session = WatchSession(id: UUID(), franchiseId: franchiseId, scope: scope, ordinal: ordinal,
                                   startedAt: startedAt, completedAt: nil, cancelledAt: nil, cancelledAtEpisode: nil, episodes: episodes)
        sessions.append(session)
        persist()
        return session
    }

    func complete(_ id: UUID, at ts: Int64) {
        guard let i = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[i].completedAt = ts
        persist()
    }

    func cancel(_ id: UUID, atEpisode episode: Int, at ts: Int64) {
        guard let i = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[i].cancelledAt = ts
        sessions[i].cancelledAtEpisode = episode
        persist()
    }

    func setStartDate(_ id: UUID, to ts: Int64) {
        guard let i = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[i].startedAt = ts
        persist()
    }

    func delete(_ id: UUID) {
        sessions.removeAll { $0.id == id }
        persist()
    }

    func deleteAll(for franchiseId: String) {
        sessions.removeAll { $0.franchiseId == franchiseId }
        persist()
    }

    /// Sign-out: sessions belong to the account that made them.
    func reset() {
        sessions = []
        persist()
    }

    // MARK: - Persistence (atomic, one backup generation)

    private func load() {
        for candidate in [url, backupURL] {
            if let data = try? Data(contentsOf: candidate),
               let decoded = try? JSONDecoder().decode([WatchSession].self, from: data) {
                sessions = decoded
                return
            }
        }
        sessions = []
    }

    private func persist() {
        let snapshot = sessions
        let target = url, backup = backupURL
        Task.detached(priority: .utility) {
            do {
                let dir = target.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                if FileManager.default.fileExists(atPath: target.path) {
                    _ = try? FileManager.default.removeItem(at: backup)
                    try? FileManager.default.copyItem(at: target, to: backup)
                }
                let data = try JSONEncoder().encode(snapshot)
                try data.write(to: target, options: .atomic)
            } catch {
                // A failed write keeps the previous file (atomic) and the backup; the in-memory
                // state stays authoritative for this session.
            }
        }
    }
}

// MARK: - Copy helpers

extension WatchSession {
    /// "Third watch" / "Second watch" / "First watch".
    var title: String { Copy.Progress.ordinalWatch(ordinal) }

    /// "In progress · Episode 7 next" / "4 Jul – 19 Jul 2026 · 26 episodes" / "Dates unknown".
    func subtitle(nextEpisode: Int?, now: Int64) -> String {
        if isActive {
            if let nextEpisode { return Copy.Progress.inProgress(nextEpisode: nextEpisode) }
            return "In progress"
        }
        if let cancelledAtEpisode {
            return "Cancelled at \(Copy.episodeInSentence(cancelledAtEpisode))"
        }
        return Copy.Progress.sessionSpan(started: startedAt, completed: completedAt == 0 ? nil : completedAt,
                                         episodes: episodes, now: now)
    }
}
