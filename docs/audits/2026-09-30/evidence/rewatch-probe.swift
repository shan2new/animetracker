import Foundation

// Presentation-only dependencies of the actual app RewatchStore source.
enum Copy {
    enum Progress {
        static func ordinalWatch(_ n: Int) -> String { "Watch \(n)" }
        static func inProgress(nextEpisode: Int) -> String { "Next \(nextEpisode)" }
        static func sessionSpan(started: Int64?, completed: Int64?, episodes: Int, now: Int64) -> String { "Session" }
    }
    static func episodeInSentence(_ n: Int) -> String { "Episode \(n)" }
}

@main struct RewatchAuditProbe {
    @MainActor static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("previously-release-audit-rewatch-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let primary = directory.appendingPathComponent("sessions.json")
        let backup = directory.appendingPathComponent("sessions.backup.json")
        let store = RewatchStore(directory: directory)
        store.startRewatch(franchiseId: "synthetic-account-a-title", scope: .franchise, startedAt: 1, episodes: 12)
        try await waitUntil { (try? decode(primary).count) == 2 }
        store.reset()
        try await waitUntil { (try? decode(primary).isEmpty) == true && FileManager.default.fileExists(atPath: backup.path) }
        let retained = try decode(backup)
        precondition(retained.count == 2)
        // Missing/corrupt primary takes the existing app's backup load path.
        try FileManager.default.removeItem(at: primary)
        let reloaded = RewatchStore(directory: directory)
        precondition(reloaded.sessions.count == 2)
        print("AUDIT_REPRODUCTION primaryAfterReset=0 backupAfterReset=\(retained.count) sessionsReloadedFromBackup=\(reloaded.sessions.count)")
        print("Boundary: actual app RewatchStore source; synthetic temporary data; missing-primary recovery explicitly induced; no real account storage read or changed")
    }

    static func decode(_ url: URL) throws -> [WatchSession] {
        try JSONDecoder().decode([WatchSession].self, from: Data(contentsOf: url))
    }

    @MainActor static func waitUntil(_ predicate: () -> Bool) async throws {
        for _ in 0..<100 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw NSError(domain: "AuditProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: "Persistence did not finish within two seconds"])
    }
}
