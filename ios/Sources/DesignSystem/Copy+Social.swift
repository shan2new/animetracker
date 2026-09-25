import Foundation

// The social layer's strings (spec §1.9.3): replies and their sort, the composer and its gates
// (community rules, identity), report / block / delete, the server's rejection reasons, Activity,
// Saved, the Community lists in Profile and the suspended account.
//
// Voice (Copy.swift, top): sentence case, no exclamation marks, curly apostrophes, the brand never
// a clause subject, counts through `Copy.plural`, and an ellipsis only on a command that opens a
// confirmation ("Report…", "Block @dex…", "Delete reply…"); the confirmation BUTTONS never carry one.

extension Copy {
    enum Social {

        // MARK: Sort

        static let sortTop = "Top"
        static let sortLatest = "Latest"
        /// The sort's own word, for the control.
        static func sortTitle(_ sort: CommentSort) -> String {
            switch sort {
            case .top: return sortTop
            case .latest: return sortLatest
            }
        }
        /// The sort control's spoken value: "Sorted by Top".
        static func sortA11y(_ sort: CommentSort) -> String { "Sorted by \(sortTitle(sort))" }
        /// The sort control's spoken name.
        static let sortLabel = "Sort replies"

        // MARK: The reply bar and the composer

        static let replyPlaceholder = "Post your reply"
        /// The composer's header for a reply to the post itself: "Replying about Frieren".
        static func replyingTo(_ show: String) -> String { "Replying about \(show)" }
        /// The composer's header for a reply to a person: "Replying to @dex".
        static func replyingToUser(_ handle: String) -> String { "Replying to \(Social.handle(handle))" }
        static let everyoneCanReply = "Everyone can reply"
        /// An episode room's audience line, under the field.
        static func episodeAudience(_ n: Int) -> String {
            "Only people who\u{2019}ve watched \(Copy.episode(n)) can read this"
        }
        /// The composer's send button.
        static let reply = "Reply"
        static let sending = "Sending"
        /// Announced to VoiceOver when the server accepts the reply.
        static let replyPosted = "Reply posted"
        /// A pending row that failed: the SyncBanner carries the retry.
        static let notSent = "Not sent"
        /// The command Sync status names beside a failed reply.
        static let postReplyCommand = "Post reply"
        /// Sync status's subject for a failed reply: "Frieren · “Did anyone else catch…”".
        static func failedReplyTitle(show: String, excerpt: String) -> String {
            "\(show) \u{00B7} \u{201C}\(excerpt)\u{201D}"
        }
        /// A pending reply that failed: the row's second command beside Retry. It removes a reply
        /// that never reached anyone, so it asks nothing.
        static let discard = "Discard"
        /// The composer's ring, spoken: "20 characters left".
        static func charactersLeft(_ n: Int) -> String { "\(Copy.plural(n, "character", "characters")) left" }
        /// Past the limit: "3 characters over the limit".
        static func charactersOver(_ n: Int) -> String {
            "\(Copy.plural(n, "character", "characters")) over the limit"
        }
        /// The inline composer's corner button (X's ↗): the draft moves to the full composer.
        static let expandComposer = "Open full composer"
        /// Cancel with words in the field (the sheet will not swipe away with a draft in it).
        static let discardDraftTitle = "Discard this reply?"
        static let discardDraft = "Discard"
        static let keepEditing = "Keep editing"

        // MARK: A reply row

        /// Facts on one line, joined by the app's middot: "@dex · 2h".
        static func line(_ parts: [String]) -> String {
            parts.filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
        }

        /// The handle's sigil, drawn before the username field.
        static let handlePrefix = "@"
        /// "@dex" — a handle as it is printed.
        static func handle(_ h: String) -> String { "\(handlePrefix)\(h)" }
        /// The line above a reply to someone: "Replying to @mira.k".
        static func replyingToLine(_ handle: String) -> String { replyingToUser(handle) }
        /// The reply count's spoken form: "1 reply" · "4 replies".
        static func repliesCount(_ n: Int) -> String { Copy.plural(n, "reply", "replies") }
        static let showMoreReplies = "Show more replies"
        static let noReplies = "No replies yet"
        static let beFirst = "Start the conversation."
        /// A reply row's reply button, spoken: "Reply to @dex".
        static func replyTo(_ handle: String) -> String { "Reply to \(Social.handle(handle))" }
        /// A thread's first page failed (content, if any, stays).
        static let repliesFailed = "Replies couldn\u{2019}t load"

        // MARK: Report, block, delete (commands open a confirmation, so they end in "…")

        static let reportCommand = "Report\u{2026}"
        static func blockCommand(_ handle: String) -> String { "Block \(Social.handle(handle))\u{2026}" }
        static let deleteCommand = "Delete reply\u{2026}"

        static let reportTitle = "Report reply"
        static let reportPrompt = "Why are you reporting this reply?"
        static let reportFailed = "Your report couldn\u{2019}t be sent. Try again."
        static func reasonTitle(_ reason: ReportReason) -> String {
            switch reason {
            case .spam: return "Spam"
            case .harassment: return "Harassment or bullying"
            case .hate: return "Hate speech"
            case .sexual: return "Sexual content"
            case .violence: return "Violence or threats"
            case .spoiler: return "Spoilers"
            case .other: return "Something else"
            }
        }
        static let reportNoteLabel = "Add details (optional)"
        /// The report sheet's confirmation button.
        static let reportSend = "Report"
        static let reportedNotice = "Thanks. This reply is hidden for you while it\u{2019}s reviewed."

        static func blockTitle(_ handle: String) -> String { "Block \(Social.handle(handle))?" }
        static let blockMessage = "You won\u{2019}t see each other\u{2019}s replies. They won\u{2019}t be told."
        static let blockConfirm = "Block"
        static func blockedNotice(_ handle: String) -> String { "Blocked \(Social.handle(handle))" }
        static let unblock = "Unblock"

        static let deleteTitle = "Delete this reply?"
        static let deleteMessage = "It\u{2019}s removed for everyone. This can\u{2019}t be undone."
        static let deleteConfirm = "Delete"
        static let deletedNotice = "Reply deleted"
        static let deleteFailed = "Couldn\u{2019}t delete this reply"

        // The Community lists' own buttons: a row's state flips in place (X's), so the word says
        // what the tap will do now, and VoiceOver hears whom it is about.
        static let block = "Block"
        static func blockUser(_ handle: String) -> String { "Block \(Social.handle(handle))" }
        static func unblockUser(_ handle: String) -> String { "Unblock \(Social.handle(handle))" }
        static let mute = "Mute"
        static let unmute = "Unmute"

        // MARK: What the server refuses (server §3.1 `reason` codes)

        /// A `content_rejected` reply. `reason` is the server's machine code; an unknown or
        /// missing one reads as the general refusal.
        static func rejection(_ reason: String?) -> String {
            switch reason ?? "" {
            case "empty": return "Write something first."
            case "too_long": return "Replies can be up to \(SocialText.limit) characters."
            case "link": return "Links aren\u{2019}t allowed in replies."
            case "blocked_term": return "This reply goes against the community rules."
            case "invalid_characters": return "This reply has characters that can\u{2019}t be posted."
            default: return "This reply couldn\u{2019}t be posted."
            }
        }
        /// A 429 on a reply (the per-user limit).
        static let rateLimited = "You\u{2019}re replying quickly. Try again in a few minutes."
        /// A 429 on a reply or on the name and username, with the server's `retryAfter`. The same
        /// words for every per-user limit — a new account's lower hourly allowance, and a run of
        /// refused words that the server now answers as a 429 — so none of them reads as a fault:
        /// "Try again in 12 minutes" · "Try again in an hour".
        static func slowDown(seconds: Int) -> String {
            let minutes = max(1, Int((Double(max(0, seconds)) / 60).rounded(.up)))
            let wait: String
            if minutes <= 1 {
                wait = "a minute"
            } else if minutes < 60 {
                wait = "\(minutes) minutes"
            } else {
                let hours = Int((Double(minutes) / 60).rounded(.up))
                wait = hours <= 1 ? "an hour" : "\(hours) hours"
            }
            return "That\u{2019}s a lot in a short time. Try again in \(wait)."
        }
        /// `capabilities.comments == false`, or the server's `comments disabled`.
        static let commentsOff = "Replies are off right now."
        /// The subject is gone (a 404/410 on the thread).
        static let gone = "This conversation isn\u{2019}t available."

        // MARK: Community rules (the first-reply gate, and Profile's read-only copy)

        static let rulesTitle = "Community rules"
        static let rulesIntro = "Replies are public. Everyone who can see a post can read them."
        static let rulesItems: [String] = [
            "Be kind. No harassment, hate or threats.",
            "Keep spoilers in episode discussions.",
            "No sexual content, and nothing involving minors.",
            "No links, ads or spam.",
            "Reports are reviewed. Replies and accounts that break these rules are removed.",
            // App Review 1.2's explicit statement, and the age floor. The server's
            // SOCIAL_TERMS_VERSION moves with this text (2026-09-25.2): change one, bump the other.
            // The age (13, or 16 in the EU) is the owner's to confirm.
            "There\u{2019}s zero tolerance for objectionable content or abusive users. It\u{2019}s removed and the account is banned.",
            "You must be 13 or older to post.",
        ]
        static let rulesAgree = "Agree and continue"
        static let rulesReadTerms = "Read the full terms"
        /// `terms_version_mismatch`: the rules moved while the sheet was open.
        static let rulesChanged = "The rules were just updated. Read them again, then agree."

        // MARK: Identity (name and username)

        static let identityTitle = "Choose how you appear"
        static let identityNote = "Your name and username show with your replies. Your email is never shown."
        static let nameLabel = "Name"
        static let namePlaceholder = "First name"
        static let usernameLabel = "Username"
        static let usernamePlaceholder = "username"
        static let usernameHelp = "3\u{2013}20 letters, numbers, dots or underscores."
        static let usernameAvailable = "Available"
        static let usernameTaken = "Already taken"

        /// An `invalid_handle` (or a handle check's `reason`). Unknown codes read as the general
        /// refusal.
        static func handleRejection(_ reason: String?) -> String {
            switch reason ?? "" {
            case "length": return "Use 3 to 20 characters."
            case "characters": return "Use letters, numbers, dots or underscores."
            case "dots": return "Dots can\u{2019}t start, end or repeat."
            case "no_letter": return "Include at least one letter."
            case "reserved": return "That username isn\u{2019}t available."
            case "blocked_term": return "That username isn\u{2019}t allowed."
            default: return "That username can\u{2019}t be used."
            }
        }

        /// An `invalid_display_name`. Unknown codes read as the general refusal.
        static func nameRejection(_ reason: String?) -> String {
            switch reason ?? "" {
            case "empty": return "Add your name."
            case "too_long": return "Names can be up to 40 characters."
            case "at_sign", "link", "invalid_characters": return "Use your first name, not an email or a link."
            case "no_letter": return "Include at least one letter."
            case "blocked_term": return "That name isn\u{2019}t allowed."
            // The server's reserved words and impersonation rule (a staff title, the brand).
            case "reserved": return "That name isn\u{2019}t available."
            default: return "That name can\u{2019}t be used."
            }
        }

        /// The first-reply gate's button (it goes on to the composer).
        static let identityContinue = "Continue"
        /// Profile's edit screen's button.
        static let identitySave = "Save"
        /// The lane's receipt after Profile's edit screen saved.
        static let identitySaved = "Name and username saved"

        // MARK: Activity

        static let activityTitle = "Activity"
        /// "Mira replied to you on Frieren".
        static func activityReply(name: String, show: String) -> String {
            "\(name) replied to you on \(show)"
        }
        /// "Mira liked your reply" · "Mira and 1 other liked your reply" · "… and 41 others …".
        static func activityLike(name: String, others: Int) -> String {
            others <= 0
                ? "\(name) liked your reply"
                : "\(name) and \(Copy.plural(others, "other", "others")) liked your reply"
        }
        /// A like row with no `actor`: liking needs no handle, so the newest liker often has no
        /// public profile, and the server sends the row nameless by design. `count` is
        /// `actorCount`: "Someone liked your reply" · "3 people liked your reply".
        static func activityLikeAnonymous(_ count: Int) -> String {
            count <= 1 ? "Someone liked your reply" : "\(Copy.plural(count, "person", "people")) liked your reply"
        }
        /// A reply row with no `actor` (its author's name was reset): "Someone replied to you on Frieren".
        static func activityReplyAnonymous(show: String) -> String {
            show.isEmpty ? "Someone replied to you" : "Someone replied to you on \(show)"
        }
        /// A `comment_hidden` row, to the reply's author (DSA Art. 17's statement of reasons).
        /// `reason` is the server's category: `reports` — hidden automatically after reports;
        /// `operator` — hidden by a moderator. An unknown one reads as the plain fact.
        static func activityHidden(reason: String, show: String) -> String {
            let on = show.isEmpty ? "" : " on \(show)"
            switch reason {
            case "reports": return "Your reply\(on) was hidden after other people reported it."
            case "operator": return "A moderator hid your reply\(on) for breaking the community rules."
            default: return "Your reply\(on) was hidden."
            }
        }
        /// A `report_resolved` row, to each reporter (DSA Art. 16(5)). `outcome`: `hidden` — the
        /// reply was removed; `dismissed` — it was reviewed and stays up.
        static func activityReportResolved(outcome: String, show: String) -> String {
            let on = show.isEmpty ? "" : " on \(show)"
            switch outcome {
            case "hidden": return "The reply you reported\(on) was removed. Thanks for reporting it."
            case "dismissed":
                return "The reply you reported\(on) was reviewed. It doesn\u{2019}t break the community rules, so it stays up."
            default: return "The reply you reported\(on) was reviewed."
            }
        }
        /// The line under a moderation row: where to write about the decision.
        static func activitySupport(_ email: String) -> String { "Questions about this decision? Write to \(email)." }
        static let activityShowMore = Copy.ForYou.showMore
        /// A refresh over rows already on screen failed.
        static let activityRefreshFailed = "Activity couldn\u{2019}t refresh"
        /// A row's spoken value while it has not been seen.
        static let unread = "Unread"
        static let done = Copy.Action.done

        // MARK: Saved

        static let savedTitle = "Saved"
        /// A saved post the server no longer answers — the row stays so it can be removed.
        static let savedUnavailable = "This post is no longer available"
        static let removeFromSaved = "Remove from Saved"
        static let removedFromSaved = "Removed from Saved"

        // MARK: Profile's Community group

        static let blockedTitle = "Blocked accounts"
        static let mutedTitle = "Muted shows"
        static let communityHeader = "Community"
        static let identityRow = "Name and username"
        static let identityNotSet = Copy.State.ask

        // MARK: A suspended account (iD14)

        static let suspendedTitle = "Your account is suspended"
        static let suspendedMessage = "You can still delete your account and everything in it."
        /// `404 account not found`: the account behind this identity was already erased, so there
        /// is nothing to hand over — a fact, not a failure.
        static let suspendedExportNothing = "There\u{2019}s nothing to export. This account holds no data."

        // MARK: Audit

        /// One sample per constant and per function (spec §1.9), for `Copy.allSampleStrings`.
        static var sampleStrings: [String] {
            var out: [String] = [
                sortTop, sortLatest, sortTitle(.top), sortTitle(.latest), sortA11y(.top), sortA11y(.latest),
                replyPlaceholder, replyingTo("Frieren"), replyingToUser("dex"), everyoneCanReply,
                episodeAudience(5), reply, sending, replyPosted, notSent, postReplyCommand,
                failedReplyTitle(show: "Frieren", excerpt: "Did anyone else catch\u{2026}"),
                discard, charactersLeft(1), charactersLeft(20), charactersOver(1), charactersOver(3),
                discardDraftTitle, discardDraft, keepEditing, sortLabel,
                line(["@dex", "2h"]), handlePrefix, handle("dex"), replyingToLine("mira.k"), repliesCount(1), repliesCount(4),
                showMoreReplies, noReplies, beFirst, replyTo("dex"), repliesFailed,
                reportCommand, blockCommand("dex"), deleteCommand,
                reportTitle, reportPrompt, reportFailed, reportNoteLabel, reportSend, reportedNotice,
                blockTitle("dex"), blockMessage, blockConfirm, blockedNotice("dex"), unblock,
                deleteTitle, deleteMessage, deleteConfirm, deletedNotice, deleteFailed,
                block, blockUser("dex"), unblockUser("dex"), mute, unmute,
                rateLimited, commentsOff, gone,
                rulesTitle, rulesIntro, rulesAgree, rulesReadTerms, rulesChanged,
                identityTitle, identityNote, nameLabel, namePlaceholder,
                usernameLabel, usernamePlaceholder, usernameHelp, usernameAvailable, usernameTaken,
                identityContinue, identitySave, identitySaved,
                activityTitle, activityReply(name: "Mira", show: "Frieren"),
                activityLike(name: "Mira", others: 0), activityLike(name: "Mira", others: 1),
                activityLike(name: "Mira", others: 41), activityShowMore, activityRefreshFailed, unread, done,
                activityLikeAnonymous(1), activityLikeAnonymous(3),
                activityReplyAnonymous(show: "Frieren"), activityReplyAnonymous(show: ""),
                savedTitle, savedUnavailable, removeFromSaved, removedFromSaved,
                blockedTitle, mutedTitle, communityHeader, identityRow, identityNotSet,
                suspendedTitle, suspendedMessage, suspendedExportNothing,
                slowDown(seconds: 30), slowDown(seconds: 720), slowDown(seconds: 3600), slowDown(seconds: 7200),
                activityHidden(reason: "reports", show: "Frieren"), activityHidden(reason: "operator", show: "Frieren"),
                activityHidden(reason: "", show: ""),
                activityReportResolved(outcome: "hidden", show: "Frieren"),
                activityReportResolved(outcome: "dismissed", show: "Frieren"),
                activityReportResolved(outcome: "", show: ""),
                activitySupport("support@example.com"),
            ]
            out += ReportReason.allCases.map(reasonTitle)
            out += ["empty", "too_long", "link", "blocked_term", "invalid_characters", nil].map(rejection)
            out += ["length", "characters", "dots", "no_letter", "reserved", "blocked_term", nil].map(handleRejection)
            out += ["empty", "too_long", "at_sign", "link", "invalid_characters", "no_letter", "blocked_term",
                    "reserved", nil]
                .map(nameRejection)
            out += rulesItems
            // The social layer's own states (not in `Copy.allSampleStrings`' EmptyStateCopy list,
            // which this file does not own), audited here instead.
            for copy in EmptyStateCopy.socialStates {
                out.append(copy.title)
                if let s = copy.supporting { out.append(s) }
                if let s = copy.primaryLabel { out.append(s) }
                if let s = copy.secondaryLabel { out.append(s) }
            }
            return out
        }
    }
}

// MARK: - The social layer's empty states

extension EmptyStateCopy {
    /// Activity with nothing in it.
    static let activityEmpty = EmptyStateCopy(
        symbol: "bell",
        title: "Nothing yet",
        supporting: "Replies to you and news about your shows show up here.")

    /// Profile → Saved with nothing saved.
    static let savedEmpty = EmptyStateCopy(
        symbol: "bookmark",
        title: "No saved posts",
        supporting: "Tap the bookmark on a post to keep it here.")

    /// Profile → Blocked accounts with nobody blocked.
    static let blockedEmpty = EmptyStateCopy(
        symbol: "hand.raised",
        title: "No blocked accounts",
        supporting: "People you block show up here.")

    /// Profile → Muted shows with nothing muted.
    static let mutedEmpty = EmptyStateCopy(
        symbol: "speaker.slash",
        title: "No muted shows",
        supporting: "Shows you mute stop appearing in your feed.")

    /// Comments are switched off (`capabilities.comments == false`) while a composer was open.
    static let commentsOff = EmptyStateCopy(
        symbol: "bubble.left.and.bubble.right",
        title: Copy.Social.commentsOff,
        supporting: nil)

    /// Activity could not load and nothing is on screen.
    static let activityFailed = EmptyStateCopy(
        symbol: "exclamationmark.circle",
        title: "Couldn\u{2019}t load your activity",
        supporting: "Something went wrong. Try again in a moment.",
        primaryLabel: Copy.Action.tryAgain)
    static let activityOffline = EmptyStateCopy(
        symbol: "wifi.slash",
        title: "You\u{2019}re offline",
        supporting: "Connect to the internet to see your activity.",
        primaryLabel: Copy.Action.tryAgain)

    /// Saved could not load.
    static let savedFailed = EmptyStateCopy(
        symbol: "exclamationmark.circle",
        title: "Couldn\u{2019}t load your saved posts",
        supporting: "Something went wrong. Try again in a moment.",
        primaryLabel: Copy.Action.tryAgain)
    static let savedOffline = EmptyStateCopy(
        symbol: "wifi.slash",
        title: "You\u{2019}re offline",
        supporting: "Connect to the internet to see your saved posts.",
        primaryLabel: Copy.Action.tryAgain)

    /// Blocked accounts could not load.
    static let blockedFailed = EmptyStateCopy(
        symbol: "exclamationmark.circle",
        title: "Couldn\u{2019}t load blocked accounts",
        supporting: "Something went wrong. Try again in a moment.",
        primaryLabel: Copy.Action.tryAgain)

    /// Muted shows could not load.
    static let mutedFailed = EmptyStateCopy(
        symbol: "exclamationmark.circle",
        title: "Couldn\u{2019}t load muted shows",
        supporting: "Something went wrong. Try again in a moment.",
        primaryLabel: Copy.Action.tryAgain)

    /// A Community list (Blocked accounts, Muted shows) opened offline.
    static let communityOffline = EmptyStateCopy(
        symbol: "wifi.slash",
        title: "You\u{2019}re offline",
        supporting: "Connect to the internet to see this list.",
        primaryLabel: Copy.Action.tryAgain)

    /// The composer could not learn whether the rules and a name are in place.
    static let composeFailed = EmptyStateCopy(
        symbol: "exclamationmark.circle",
        title: "Couldn\u{2019}t start your reply",
        supporting: "Something went wrong. Try again in a moment.",
        primaryLabel: Copy.Action.tryAgain)
    static let composeOffline = EmptyStateCopy(
        symbol: "wifi.slash",
        title: "You\u{2019}re offline",
        supporting: "Connect to the internet to reply.",
        primaryLabel: Copy.Action.tryAgain)

    /// Every state above, for the audit (`Copy.Social.sampleStrings`).
    static var socialStates: [EmptyStateCopy] {
        [.activityEmpty, .savedEmpty, .blockedEmpty, .mutedEmpty, .commentsOff,
         .activityFailed, .activityOffline, .savedFailed, .savedOffline,
         .blockedFailed, .mutedFailed, .communityOffline, .composeFailed, .composeOffline]
    }
}
