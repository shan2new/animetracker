import SwiftUI

/// Deep-link target inside the detail: a season part and one episode (Schedule rows pass it).
struct EpisodeFocus: Equatable, Hashable {
    let mediaId: Int
    let episode: Int
}
