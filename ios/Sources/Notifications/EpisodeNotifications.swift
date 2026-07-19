import Foundation
import UserNotifications

// Local "episode is out" alerts. AniList gives us each watching show's next airing instant
// (`nextAiringAt`), so the app schedules one local notification per show — no push
// infrastructure needed. AppModel re-syncs the pending set after every confirmed library
// change (reload / status change / remove), so the schedule always mirrors the library.
@MainActor
final class EpisodeNotifications {
    static let shared = EpisodeNotifications()

    /// iOS caps pending local notifications at 64 per app; stay safely under it. One per show
    /// (only the next airing is known), soonest first — a library bigger than this keeps alerts
    /// for the 48 shows airing next.
    static let maxPending = 48

    private let center = UNUserNotificationCenter.current()

    /// Ask for permission the first time it's worth having (an airing show was just added), so
    /// the system prompt lands with obvious context instead of firing at first launch.
    @discardableResult
    func requestPermissionIfNeeded() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        case .denied:
            return false
        default:
            return true
        }
    }

    /// Rebuild the pending-notification set from the current library: one alert at air time for
    /// each watching show with a scheduled next episode.
    func sync(library: [Franchise], now: Int64) async {
        let settings = await center.notificationSettings()
        let authorized = settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
            || settings.authorizationStatus == .ephemeral
        guard authorized else { return }

        struct UpcomingAiring {
            let franchiseId: String
            let title: String
            let mediaId: Int
            let episode: Int?
            let airsAt: Int64
        }

        // TMDB air times are date-precision only (synthesized 17:00 UTC), so time-of-day alerts
        // would fire at a meaningless instant — anime (AniList) only for now.
        let upcoming = library
            .filter { $0.effectiveStatus == .watching && $0.source == .anilist }
            .compactMap { f -> UpcomingAiring? in
                guard let part = f.releasingPart, let at = part.nextAiringAt, at > now else { return nil }
                return UpcomingAiring(franchiseId: f.id, title: f.title, mediaId: part.mediaId,
                                      episode: part.nextEpisodeNumber, airsAt: at)
            }
            .sorted { $0.airsAt < $1.airsAt }
            .prefix(EpisodeNotifications.maxPending)

        // The app schedules nothing else, so a full clear + re-add keeps this idempotent.
        center.removeAllPendingNotificationRequests()

        for airing in upcoming {
            let content = UNMutableNotificationContent()
            content.title = airing.title
            content.body = airing.episode.map { "Episode \($0) is out now." } ?? "A new episode is out now."
            content.sound = .default
            content.threadIdentifier = airing.franchiseId  // group repeat alerts per franchise

            let delay = max(1, Double(airing.airsAt - now) / 1000)
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
            let request = UNNotificationRequest(
                identifier: "episode-\(airing.mediaId)-\(airing.episode ?? 0)",
                content: content,
                trigger: trigger
            )
            try? await center.add(request)
        }
    }
}
