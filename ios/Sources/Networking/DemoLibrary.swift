#if DEBUG
import Foundation

/// `-demoBusy 1` — a synthetic library state for CAPTURES, in the same family as `-calmDemo 1`
/// and `-scheduleDemoCounts 1`.
///
/// The QA account is permanently caught up (every watching show sits at `behind: 0`), so the
/// state Today actually exists to serve — a couple of drops waiting, a few shows mid-way through
/// whose run has finished — cannot be photographed from real data without writing fake progress
/// into the user's account. This rewrites the `/me/library` PAYLOAD on the way in instead: no
/// model changes, no writes, and the screen renders it exactly as it would render the real thing.
///
/// The shape it builds (the scenario under review, 6 Sep):
///   - two RELEASING shows whose latest episode struck YESTERDAY and is unwatched (`behind: 1`)
///   - three shows still in progress whose broadcast is OVER (backlog, no airings)
/// Everything else in the library is filed `completed` so it cannot crowd the stack.
enum DemoLibrary {
    static var isOn: Bool { UserDefaults.standard.bool(forKey: "demoBusy") }

    /// Titles are matched by prefix so the fixture survives a catalogue rename.
    // "Daemons of the Shadow Realm" is not in the QA library; Re:ZERO stands in for it,
    // so the fixture has the TWO simultaneous drops the scenario asks for.
    private static let freshTitles = ["Daemons", "Bleach", "Re:ZERO"]
    private static let backlogTitles = ["Game of Thrones", "House of the Dragon", "The Witcher"]

    static func rewriteIfNeeded(path: String, data: Data) -> Data {
        guard isOn, path == "/me/library" else { return data }
        guard var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              var franchises = root["franchises"] as? [[String: Any]] else { return data }

        let day: Int64 = 86_400_000                      // the payload's airings are in ms
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        // Yesterday at 20:00 local, so the drop reads "Aired yesterday" rather than "23h ago".
        var cal = Calendar.current
        cal.timeZone = .current
        let yesterday = cal.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        var comps = cal.dateComponents([.year, .month, .day], from: yesterday)
        comps.hour = 20
        let dropAt = Int64((cal.date(from: comps) ?? yesterday).timeIntervalSince1970 * 1000)

        func matches(_ title: String, _ prefixes: [String]) -> Bool {
            prefixes.contains { title.localizedCaseInsensitiveContains($0) }
        }

        for i in franchises.indices {
            let title = franchises[i]["title"] as? String ?? ""
            guard var parts = franchises[i]["parts"] as? [[String: Any]], !parts.isEmpty else { continue }

            if matches(title, freshTitles) {
                franchises[i]["status"] = "watching"
                franchises[i]["isReleasing"] = true
                // The highest-sequence episodic part is the one still on air.
                let idx = parts.indices.max(by: { (parts[$0]["sequence"] as? Int ?? 0) < (parts[$1]["sequence"] as? Int ?? 0) })!
                let watched = max(1, parts[idx]["progress"] as? Int ?? 1)
                let dropped = watched + 1                      // one unwatched episode, out yesterday
                parts[idx]["isReleasing"] = true
                parts[idx]["progress"] = watched
                parts[idx]["airedEpisodes"] = dropped
                parts[idx]["lastAiredAt"] = dropAt
                parts[idx]["totalEpisodes"] = max(dropped + 4, parts[idx]["totalEpisodes"] as? Int ?? 0)
                parts[idx]["nextEpisodeNumber"] = dropped + 1
                parts[idx]["nextAiringAt"] = dropAt + 7 * day
                parts[idx]["nextAiringCount"] = 1
                parts[idx]["airings"] = [
                    ["episode": dropped, "at": dropAt],
                    ["episode": dropped + 1, "at": dropAt + 7 * day],
                ]
                franchises[i]["parts"] = parts
                franchises[i]["behind"] = 1
            } else if matches(title, backlogTitles) {
                franchises[i]["status"] = "watching"
                franchises[i]["isReleasing"] = false
                // Mid-way through a run that has finished airing: no airings, nothing upcoming.
                for j in parts.indices {
                    parts[j]["isReleasing"] = false
                    parts[j]["airings"] = []
                    parts[j]["nextAiringAt"] = nil
                    parts[j]["nextEpisodeNumber"] = nil
                }
                // The first SEASON, never the sequence-0 special: `episodicParts` excludes
                // specials, so a backlog written onto one is invisible to `resumePart` — which
                // is why Game of Thrones and House of the Dragon first came out with no shelf.
                // One of them keeps a RUNNING season whose last drop is older than the
                // out-now window: backlog, but still on air. That is the state the airing dot
                // exists for, and it cannot occur in the two clean buckets.
                let stillAiring = title.localizedCaseInsensitiveContains("Witcher")
                if stillAiring {
                    franchises[i]["isReleasing"] = true
                    if let s = parts.indices.filter({ (parts[$0]["kind"] as? String) == "season" })
                        .max(by: { (parts[$0]["sequence"] as? Int ?? 0) < (parts[$1]["sequence"] as? Int ?? 0) }) {
                        parts[s]["isReleasing"] = true
                        parts[s]["lastAiredAt"] = dropAt - 9 * day        // well outside the window
                        parts[s]["nextAiringAt"] = dropAt + 5 * day
                        parts[s]["airings"] = [["episode": 4, "at": dropAt + 5 * day]]
                    }
                }
                let seasons = parts.indices.filter { (parts[$0]["kind"] as? String) == "season" }
                guard let idx = seasons.min(by: { (parts[$0]["sequence"] as? Int ?? 0) < (parts[$1]["sequence"] as? Int ?? 0) }) else { continue }
                let total = max(8, parts[idx]["totalEpisodes"] as? Int ?? 8)
                parts[idx]["totalEpisodes"] = total
                parts[idx]["airedEpisodes"] = total
                parts[idx]["progress"] = max(1, total / 3)     // a real, resumable backlog
                franchises[i]["parts"] = parts
                franchises[i]["behind"] = 0
            } else {
                // Everything else is done, so the stack is exactly the fixture.
                franchises[i]["status"] = "completed"
                franchises[i]["isReleasing"] = false
                for j in parts.indices {
                    parts[j]["isReleasing"] = false
                    parts[j]["airings"] = []
                    parts[j]["nextAiringAt"] = nil
                    let avail = max(parts[j]["airedEpisodes"] as? Int ?? 0, parts[j]["totalEpisodes"] as? Int ?? 0)
                    parts[j]["progress"] = avail
                }
                franchises[i]["parts"] = parts
                franchises[i]["behind"] = 0
            }
        }
        root["franchises"] = franchises
        _ = nowMs
        return (try? JSONSerialization.data(withJSONObject: root)) ?? data
    }
}
#endif
