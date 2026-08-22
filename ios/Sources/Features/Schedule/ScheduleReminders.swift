import Foundation
import Observation
import UserNotifications

/// Which episodes have a pending local reminder (EpisodeNotifications schedules them as
/// "episode-<mediaId>-<episode>"). Read-only: the bell is passive, never a control.
@MainActor
@Observable
final class ScheduleReminders {
    static let shared = ScheduleReminders()
    private(set) var pending: Set<String> = []

    func has(mediaId: Int, episode: Int) -> Bool { pending.contains("episode-\(mediaId)-\(episode)") }

    func refresh() async {
        let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
        pending = Set(requests.map(\.identifier).filter { $0.hasPrefix("episode-") })
    }
}
