import Foundation

// Derived state only. Nothing here is stored — a screen asks the model which of the five
// conditions it is in and renders the matching component, instead of each screen re-deriving
// "loading && empty && !error" in its own way and drifting.

/// The five conditions every root can be in (board 09). Anything not in this enum is not a state
/// the app has a treatment for.
enum SurfacePhase: Equatable {
    /// No cache and a request in flight. Structural skeleton, delayed 240 ms.
    case loading
    /// The request settled and the account has no titles. First-run content, immediately.
    case emptyAccount
    /// The request failed and there is nothing cached to show instead.
    case errorNoCache
    /// There is content. It may be refreshing, stale, or missing one section's refresh.
    case content(refreshing: Bool, staleSince: Int64?, sectionFailed: Bool)

    var isContent: Bool { if case .content = self { return true }; return false }
}

extension AppModel {

    /// The phase for a root that renders the whole library.
    ///
    /// Order matters: cached content always wins over a failed refresh (the network never blanks
    /// the library), and an empty account is never shown while a first load is still running.
    var surfacePhase: SurfacePhase {
        if library.isEmpty {
            if loading { return .loading }
            if loadError { return .errorNoCache }
            return .emptyAccount
        }
        return .content(refreshing: isRefreshing,
                        staleSince: staleSince(.exactAiring),
                        sectionFailed: loadError)
    }

    /// A refresh over content the user can already see. Distinct from `.loading`, which has no
    /// content behind it.
    var isRefreshing: Bool { loading && !library.isEmpty }

    /// The empty state to render when there is nothing to show. `isOnline` — not the error —
    /// decides between "you're offline" and "we couldn't reach the server", because only the path
    /// monitor knows which sentence is true.
    var emptyStateCopy: EmptyStateCopy {
        switch surfacePhase {
        case .errorNoCache:
            return SyncCenter.shared.isOnline ? .serverNoCache : .offlineNoData
        default:
            return .emptyAccount
        }
    }

    /// Past this data class's threshold (30 min exact airing · 6 h date-only · 24 h catalogue).
    func isStale(_ dataClass: SyncCenter.DataClass) -> Bool {
        SyncCenter.shared.isStale(dataClass, now: now)
    }

    /// The timestamp the stale strip renders, or `nil` when the data is fresh enough to say
    /// nothing at all.
    func staleSince(_ dataClass: SyncCenter.DataClass) -> Int64? {
        SyncCenter.shared.staleSince(dataClass, now: now)
    }

    /// Content is on screen but the last refresh failed — a section notice, never a blanked frame.
    var sectionFailed: Bool { loadError && !library.isEmpty }

    /// Writes are always permitted; this only decides whether the user is told they are queued.
    var writesAreOffline: Bool { !SyncCenter.shared.isOnline }
}
