import SwiftUI

/// A franchise destination inside a tab's navigation stack (board 02: Detail is navigational
/// content, never modal). `zoomID` names the tapped card so the same franchise can be reached from
/// several surfaces; `focus` lands on one episode (Schedule rows).
struct DetailRoute: Hashable, Identifiable {
    let id: String
    let zoomID: String
    var focus: EpisodeFocus? = nil
}
