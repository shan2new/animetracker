import Foundation
import ActivityKit

// The Live Activity contract shared by the app (which starts/updates activities) and the
// AniTrackWidgets extension (which renders them). This file is a member of BOTH targets —
// ActivityKit matches app and widget by the attributes type name, so it must be identical.
struct AiringActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// The episode's air instant. The widget renders a self-ticking countdown to this date
        /// (Text(timerInterval:)), so no live updates are needed while the app is closed.
        var airsAt: Date
    }

    var franchiseTitle: String
    var episodeNumber: Int?
}
