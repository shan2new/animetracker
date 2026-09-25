import Foundation

// Activity (the bell) and reminders — the model half (spec §1.6.5, §4.4, §4.7).
//
// There is no push (brief §10/§16): Activity is POLLED on the feed's load, on foreground, when
// the bell opens and on the pull (iD19). Opening the sheet marks the rows it showed read. Reminders on
// dated posts become local alerts through `EpisodeNotifications.sync` (`reminderAlerts(now:)`);
// undated ones need nothing here — the server tells reminder holders in Activity when the news
// firms up (server §5.3).

extension AppModel {
    /// One page of Activity.
    nonisolated static let activityPageSize = 50

    /// `GET /me/notifications?limit=50[&cursor]`. A reset reads the first page and replaces the
    /// list; otherwise the next page is appended. Deduped by id; `unread` comes from the page.
    func loadActivity(reset: Bool) async {
        guard !isIsolated, !erasing else { return }   // not during an account deletion
        if !reset {
            guard !activityLoading, activityCursor != nil else { return }
        }
        activitySeq &+= 1
        let seq = activitySeq
        let epoch = accountEpoch
        let cursor = reset ? nil : activityCursor
        activityLoading = true
        do {
            let page = try await api.notifications(limit: Self.activityPageSize, cursor: cursor)
            guard seq == activitySeq, epoch == accountEpoch else { return }
            if reset {
                var seen = Set<String>()
                let items = page.items.filter { seen.insert($0.id).inserted }
                if items != activity { activity = items }
            } else {
                var seen = Set(activity.map(\.id))
                let more = page.items.filter { seen.insert($0.id).inserted }
                if !more.isEmpty { activity += more }
            }
            activityCursor = page.nextCursor
            if activityUnread != page.unread { activityUnread = page.unread }
            activityFailed = false
            activityLoading = false
            feedLiveLoaded.insert("activity")
            scheduleFeedCacheWrite()
        } catch {
            guard seq == activitySeq, epoch == accountEpoch else { return }
            activityLoading = false
            guard !error.isCancellation else { return }
            activityFailed = true
            handleSocialReadError(error)
        }
    }

    /// "Show more": the next page, when there is one.
    func loadMoreActivity() async {
        guard activityCursor != nil, !activityLoading else { return }
        await loadActivity(reset: false)
    }

    /// Opening the bell marks what it SHOWED read (brief §11): the loaded rows still unread, by id
    /// (≤ 500, the server's cap) — never "everything", which would also clear rows past the loaded
    /// page and rows that arrived after the sheet loaded, replies the user never saw. Optimistic —
    /// those rows read now and the count drops by them — and a failure is silent: the next load
    /// restores the truth.
    func markActivityRead() {
        guard !isIsolated else { return }
        let stamp: Int64 = .nowMs
        let ids = Array(activity.filter { $0.readAt == nil && UUID(uuidString: $0.id) != nil }
            .map(\.id).prefix(500))
        guard !ids.isEmpty else { return }
        let marked = Set(ids)
        activity = activity.map { marked.contains($0.id) ? Self.marked($0, readAt: stamp) : $0 }
        let left = max(0, activityUnread - ids.count)
        if activityUnread != left { activityUnread = left }
        scheduleFeedCacheWrite()
        let epoch = accountEpoch
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.api.markNotificationsRead(ids: ids)
            } catch {
                guard epoch == self.accountEpoch else { return }
                self.handleSocialReadError(error)
            }
        }
    }

    /// A copy of a notification with `readAt` set (the wire type's fields are `let`).
    nonisolated static func marked(_ item: NotificationItem, readAt: Int64) -> NotificationItem {
        NotificationItem(id: item.id, franchiseId: item.franchiseId, kind: item.kind, title: item.title,
                         body: item.body, createdAt: item.createdAt, readAt: readAt, actor: item.actor,
                         actorCount: item.actorCount, subject: item.subject, postId: item.postId,
                         commentId: item.commentId, excerpt: item.excerpt, news: item.news)
    }

    /// Where a notification goes (server §5.2): a reply → its thread, at the reply; a post → its
    /// page; else the show.
    func openRoute(for item: NotificationItem) -> OpenRoute {
        if let commentId = item.commentId, let subject = item.subject ?? item.postId {
            return .thread(subject: subject, franchiseId: item.franchiseId, commentId: commentId)
        }
        if let postId = item.postId {
            return .post(postId: postId, commentId: nil)
        }
        return .show(franchiseId: item.franchiseId)
    }

    // MARK: - Reminders

    /// `GET /me/reminders` → the reminded posts and their shows. Re-arms the local alerts when the
    /// set of dated reminders changed.
    func loadReminders() async {
        guard !isIsolated else { return }
        let epoch = accountEpoch
        do {
            let res = try await api.reminders()
            guard epoch == accountEpoch else { return }
            let before = reminderAlerts(now: .nowMs).map(\.postId)
            reminderItems = res.items
            reminderFranchises = Dictionary(res.franchises.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            // Every item is reminded as the server knows it, whatever else a post payload said.
            var base = socialBase
            for item in res.items {
                var entry = item.post.map { SubjectSocial($0) } ?? base[item.postId] ?? SubjectSocial()
                entry.reminded = true
                if base[item.postId] != entry { base[item.postId] = entry }
            }
            if base != socialBase { socialBase = base }
            feedLiveLoaded.insert("reminders")
            scheduleFeedCacheWrite()
            if reminderAlerts(now: .nowMs).map(\.postId) != before { await syncAmbient() }
        } catch {
            guard epoch == accountEpoch else { return }
            handleSocialReadError(error)
        }
    }

    /// The local alerts the reminders ask for (§4.4): every reminded post — from `GET
    /// /me/reminders`, the loaded feed tabs and the loaded post pages — whose premiere is still
    /// ahead and whose reminder is still ON through the overlay. Deduped by post id, soonest first.
    func reminderAlerts(now: Int64) -> [ReminderAlert] {
        var alerts: [String: ReminderAlert] = [:]

        func consider(_ post: FeedPost, show: FeedFranchise?) {
            guard alerts[post.id] == nil, isReminded(post.id), let premiere = post.premiere,
                  // A premiere already behind us is never scheduled: a saved or reminded post whose
                  // part has premiered still composes by id (`live: false`) with its past premiere.
                  premiere.at > now || premiere.precision == .dateOnly,
                  !TemporalCopy.premiereHasPassed(premiere.at, anchor: premiere.anchor, now: now) else { return }
            let title = franchise(id: post.franchiseId)?.displayTitle ?? show?.stub.displayTitle
            guard let title else { return }
            let alert = ReminderAlert(postId: post.id, franchiseId: post.franchiseId, title: title,
                                      installment: post.installment, mediaId: post.part?.mediaId,
                                      at: premiere.at, dateOnly: premiere.precision == .dateOnly)
            guard let fires = EpisodeNotifications.fireTime(for: alert), fires > now else { return }
            alerts[post.id] = alert
        }

        for item in reminderItems {
            guard let post = item.post else { continue }
            consider(post, show: reminderFranchises[post.franchiseId])
        }
        for state in feedTabs.values {
            guard let response = state.response else { continue }
            let shows = Dictionary(response.franchises.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            for post in response.posts where post.premiere != nil {
                consider(post, show: shows[post.franchiseId])
            }
        }
        for page in postDetails.values {
            guard let detail = page.detail else { continue }
            consider(detail.post, show: detail.franchise)
        }
        return alerts.values.sorted { $0.at != $1.at ? $0.at < $1.at : $0.postId < $1.postId }
    }
}
