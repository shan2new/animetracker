import Foundation
import OSLog
import UserNotifications

// Local "episode is out" alerts. AniList gives us each watching show's next airing instant
// (`nextAiringAt`), so the app schedules one local notification per show — no push
// infrastructure needed. AppModel re-syncs the pending set after every confirmed library
// change (reload / status change / remove), so the schedule always mirrors the library.
@MainActor
final class EpisodeNotifications {
    static let shared = EpisodeNotifications()
    nonisolated static let log = Logger(subsystem: "app.previously", category: "alerts")

    /// iOS caps pending local notifications at 64 per app; stay safely under it. One per show
    /// (only the next airing is known), soonest first — a library bigger than this keeps alerts
    /// for the 48 shows airing next.
    static let maxPending = 48

    private let center = UNUserNotificationCenter.current()
    /// Held strongly here — `center.delegate` is weak, and a deallocated delegate silently
    /// restores the "drop it" default.
    private let foregroundPresenter = ForegroundPresenter()

    /// Where a tapped alert lands: the franchise id it named. Installed at launch by the app.
    /// Before this, tapping "Episode 12 is out now" merely foregrounded whatever tab was up.
    var onOpen: (@MainActor (String) -> Void)? {
        get { foregroundPresenter.onOpen }
        set { foregroundPresenter.onOpen = newValue }
    }

    /// Install the foreground presentation delegate. Called once at launch, before the window
    /// exists, because iOS only consults a delegate that was set by the end of launch.
    func registerForegroundPresenter() {
        center.delegate = foregroundPresenter
    }

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

    /// Alerts per show. One used to be all there was, so a viewer who got the alert for episode
    /// 5 and did not open the app for three weeks heard nothing about 6, 7 or 8 — the feature
    /// went quiet for exactly the person it exists to bring back. The per-part `airings` carry
    /// the next fortnight, so each show arms its next three within the budget.
    static let perShow = 3

    /// Rebuild the pending-notification set from the current library: an alert at air time for
    /// each watching show's next few episodes, soonest first, one round per show.
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
        let perShow: [[UpcomingAiring]] = library
            .filter { $0.effectiveStatus == .watching && $0.source == .anilist }
            .compactMap { f -> [UpcomingAiring]? in
                guard let part = f.releasingPart else { return nil }
                var slots = part.airings
                    .filter { $0.at > now }
                    .sorted { $0.at < $1.at }
                    .prefix(EpisodeNotifications.perShow)
                    .map { UpcomingAiring(franchiseId: f.id, title: f.displayTitle, mediaId: part.mediaId,
                                          episode: $0.episode, airsAt: $0.at) }
                if slots.isEmpty, let at = part.nextAiringAt, at > now {
                    slots = [UpcomingAiring(franchiseId: f.id, title: f.displayTitle, mediaId: part.mediaId,
                                            episode: part.nextEpisodeNumber, airsAt: at)]
                }
                return slots.isEmpty ? nil : slots
            }
        // Round by round: every show keeps its soonest alert before any show gets its second,
        // so a large library never starves a show of its next episode for another's third.
        var upcoming: [UpcomingAiring] = []
        for rank in 0..<EpisodeNotifications.perShow {
            upcoming += perShow.compactMap { $0.count > rank ? $0[rank] : nil }
                .sorted { $0.airsAt < $1.airsAt }
        }
        upcoming = Array(upcoming.prefix(EpisodeNotifications.maxPending))

        // The app schedules nothing else, so a full clear + re-add keeps this idempotent.
        center.removeAllPendingNotificationRequests()

        for airing in upcoming {
            let content = UNMutableNotificationContent()
            content.title = airing.title
            content.body = Copy.Alert.episodeOut(airing.episode)
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

    /// Drop every alert this app owns — pending and already delivered. Sign-out calls this: the
    /// schedule is built from one account's library, so leaving it armed would announce the
    /// previous user's episodes to whoever signs in next (or to nobody at all).
    func cancelAll() {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }
}

// An episode alert most often fires while you're IN the app — that's what "it's out now" means.
// Without a delegate iOS suppresses it entirely, so the one notification the app schedules was
// silently dropped at exactly its most likely moment. Present it like any other alert.
private final class ForegroundPresenter: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    var onOpen: (@MainActor (String) -> Void)?

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    /// The tap. `threadIdentifier` is the franchise id every alert is filed under.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
        let id = response.notification.request.content.threadIdentifier
        guard !id.isEmpty else { return }
        EpisodeNotifications.log.info("alert opened: \(response.notification.request.identifier, privacy: .public)")
        await MainActor.run { onOpen?(id) }
    }
}
