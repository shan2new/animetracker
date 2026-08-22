import SwiftUI
import UIKit

// Profile (spec board 08): the modal where trust is inspectable — who is signed in, whether the
// library is actually saved, every failed change with a way to fix it, and the two account actions
// that cannot be taken back.
//
// POLISH PASS 3. What the adversarial panel drew off `after-*.png`, and what replaces it:
//
//  • THE APP COULD NOT BE SUBMITTED (P-1 / SYS-20). Guideline 5.1.1(v) requires in-app account
//    deletion, and 5.1.1 requires reachable Privacy, Terms and support. None existed: `grep` across
//    `ios/Sources` returned no "Delete account". There is now an ACCOUNT plate — Privacy Policy,
//    Terms of Use, Contact support, all from `AppConfig` build settings, never a URL hard-coded
//    into copy — and a Delete account row on its own plate, behind a confirmation that states the
//    blast radius with the user's real counts, wired to `DELETE /me`.
//  • THE ONLY WAY OUT OF A FAILED WRITE WAS TO THROW IT AWAY (P-4), drawn in `textTertiary` — the
//    disabled ramp — truncated against the plate's corner. The failure row now carries **Retry**
//    as the primary at `accent` and **Discard** at `destructive`, both real 44-pt controls, the
//    subject first ("Black Clover · Moved to Paused") and the time it failed. `Retry all` sits on
//    the summary row when more than one change is standing.
//  • A DESTRUCTIVE CONFIRMATION WITH NO CANCEL (P-3). `confirmationDialog` on this SDK renders as
//    a source-anchored card that drops the `.cancel` button entirely — the capture shows the
//    dialog floating over the stats plate with a single red "Sign out" and no dimming, so the only
//    escape was tapping outside. Both confirmations are `alert`s now: a real scrim, a centred
//    title, an explicit Cancel, and the destructive verb in `destructive`.
//  • ZERO ARTWORK ON A SCREEN WHOSE SUBJECT IS A 30-TITLE LIBRARY (P-13). The account's own covers
//    now fan behind the monogram, and the wash no longer dies two swipes in (P-12).
//  • Plus: the version string sliced by the bezel (P-10), the numeric roll called raw instead of
//    through `numericFact` (P-18), sign-out with no in-flight state (P-19), the stats block
//    reflowing into a settings table at AX (P-16), the stretched switch (SYS-5), section eyebrows
//    aligned to nothing (P-15), the healthiest state drawn in the dimmest grey (P-28), and a
//    footer that read as three ragged grey lines (P-32).
struct ProfileView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.openURL) private var openURL

    @State private var hapticsOn = FeedbackCoordinator.enabled
    @State private var confirmSignOut = false
    @State private var confirmDelete = false
    @State private var discardTarget: UUID?
    @State private var signingOut = false
    @State private var deleting = false
    /// The one failure this screen has to report itself: the account deletion that did not happen.
    @State private var deleteFailure: String?
    /// Resolved here rather than read off `PaletteCache` synchronously: nothing else on this screen
    /// primes the cache on a cold open, so the wash would fall back to neutral.
    @State private var washTint: Color?
    /// Drives the wash out. Read from scroll geometry rather than a `GeometryReader` sentinel so
    /// nothing in the content tree has to know the wash exists.
    @State private var scrollOffset: CGFloat = 0

    /// Trailing indicators scale with the row titles they sit beside. At AX1 the fixed-size chevron
    /// and arrow shrank to specks against ~24-pt titles (P-30).
    @ScaledMetric(relativeTo: .body) private var indicatorSize: CGFloat = 14

    private var now: Int64 { appModel.now }
    private var sync: SyncCenter { SyncCenter.shared }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                ProfileWash(tint: washTint)
                    // It fades as the sheet scrolls, but never to nothing. Round 2 took it to zero
                    // over 40 pt, so two swipes in the screen was plain black with three grey
                    // plates — indistinguishable from Settings.app (P-12).
                    .opacity(washOpacity)
                    .ignoresSafeArea(edges: .top)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        identity
                        if !appModel.library.isEmpty {
                            stats.padding(.top, ThemeMetrics.heroClearance)
                        }
                        syncSection.padding(.top, ThemeMetrics.sectionGap)
                        settings.padding(.top, ThemeMetrics.sectionGap)
                        accountSection.padding(.top, ThemeMetrics.sectionGap)
                        signOutSection.padding(.top, ThemeMetrics.sectionGap)
                        deleteSection.padding(.top, ThemeSpace.x3)
                        colophon.padding(.top, ThemeSpace.x10)
                    }
                    .padding(.horizontal, ThemeMetrics.gutter)
                    // Generous under the bar: the identity is the hero of this screen and 16 pt
                    // put the monogram's shadow within a hair of the bar's edge.
                    .padding(.top, ThemeSpace.x6)
                }
                .scrollIndicators(.hidden)
                // The sheet had no bottom inset, so the last line of the colophon ended flush
                // against the bezel — text sliced by the screen edge (P-10).
                .safeAreaPadding(.bottom, 34)
                // A settings sheet needs a real edge, not a progressive blur: with the soft
                // default the 28-pt account name scrolled up and ghosted through the bar directly
                // behind the word "Profile". `.hard` is the system's own answer.
                .scrollEdgeEffectStyle(.hard, for: .top)
                // The row is tappable, but the gesture people already know is the one that should
                // work: this is the screen that answers "is my library actually saved".
                .previouslyRefreshable { await appModel.reload() }
                .onScrollGeometryChange(for: CGFloat.self) { geo in
                    geo.contentOffset.y + geo.contentInsets.top
                } action: { _, y in
                    scrollOffset = y
                }
            }
            .background(ThemeColor.canvas.ignoresSafeArea())
            .task { washTint = await PaletteCache.shared.resolve(url: washArtwork, maxPixel: 320) }
            // A real inline navigation bar: VoiceOver announces the screen, and the system's own
            // scroll-edge material takes over from the wash as it fades.
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            // An OPAQUE bar, not the SDK's default progressive blur: that let the 28-pt account
            // name dissolve directly behind the word "Profile" on the way up.
            .toolbarBackground(ThemeColor.canvas, for: .navigationBar)
            .toolbarBackgroundVisibility(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    // Plain text where iOS puts plain text. On this SDK the capsule is the
                    // toolbar's own shared glass, so `buttonStyle` alone does not remove it.
                    Button(Copy.Action.done) { dismiss() }
                        .buttonStyle(.plain)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(ThemeColor.accent)
                }
                .sharedBackgroundVisibility(.hidden)
            }
        }
        .onAppear { sync.profileIsOpen = true }
        .onDisappear { sync.profileIsOpen = false }
        // ALERTS, not `confirmationDialog`. On this SDK a confirmation dialog renders as a
        // source-anchored card that suppresses its own `.cancel` button — the capture shows one
        // red "Sign out" capsule floating over undimmed content, so the only way to back out of a
        // destructive confirmation was to tap outside it, which is undiscoverable (P-3). An alert
        // is the presentation that guarantees the three things this moment needs: a dimming scrim,
        // an explicit Cancel, and the destructive verb rendered as destructive.
        .alert(AccountCopy.signOutTitle, isPresented: $confirmSignOut) {
            Button(Copy.Confirm.cancel, role: .cancel) {}
            Button(AccountCopy.signOut, role: .destructive) { performSignOut() }
        } message: {
            Text(signOutMessage)
        }
        .alert(AccountCopy.deleteTitle, isPresented: $confirmDelete) {
            Button(Copy.Confirm.cancel, role: .cancel) {}
            Button(AccountCopy.deleteConfirm, role: .destructive) { performDelete() }
        } message: {
            Text(deleteMessage)
        }
        .alert(AccountCopy.deleteFailedTitle,
               isPresented: Binding(get: { deleteFailure != nil },
                                    set: { if !$0 { deleteFailure = nil } })) {
            Button(Copy.Action.done, role: .cancel) { deleteFailure = nil }
        } message: {
            Text(deleteFailure ?? "")
        }
        .alert(Copy.Confirm.discardChangeTitle,
               isPresented: Binding(get: { discardTarget != nil },
                                    set: { if !$0 { discardTarget = nil } })) {
            Button(Copy.Confirm.cancel, role: .cancel) { discardTarget = nil }
            Button(Copy.Confirm.discardChangeConfirm, role: .destructive) {
                if let id = discardTarget { sync.discard(id) }
                discardTarget = nil
            }
        } message: {
            Text(Copy.Confirm.discardChangeMessage)
        }
    }

    /// Full at rest, 0.35 once the header has left. Never zero.
    private var washOpacity: Double {
        let travel = max(0, min(1, Double(scrollOffset) / 140))
        return 1 - 0.65 * travel
    }

    // MARK: - Identity

    /// The account's own artwork, the monogram, the name, and how this device is signed in. The
    /// sync line is NOT one of them: it lives in the Sync section, once.
    private var identity: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                if !fanCovers.isEmpty { posterFan }
                avatar
                    .offset(y: fanCovers.isEmpty ? 0 : 30)
            }
            .padding(.bottom, fanCovers.isEmpty ? 0 : 30)
            Text(accountName)
                .type(ThemeType.heroTitle)
                .foregroundStyle(ThemeColor.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                // An account name is an identity title: it scales down before it truncates, and an
                // email address is long enough that this matters on the first screen.
                .minimumScaleFactor(0.55)
                .padding(.top, ThemeSpace.x3)
                .accessibilityAddTraits(.isHeader)
            Text(provenance)
                .type(ThemeType.heroMeta)
                .foregroundStyle(ThemeColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.top, ThemeMetrics.titleGap)
        }
        .frame(maxWidth: .infinity)
    }

    /// Three of the account's own covers, fanned. The screen's subject is a library and it drew no
    /// image at all (P-13) — the code even documented removing the art rather than fixing the crop
    /// that made it ugly. These posters are already decoded in `ImageCache`; the fan costs nothing
    /// and it is the only place on a settings surface where identity art belongs.
    private var posterFan: some View {
        ZStack {
            ForEach(Array(fanCovers.enumerated()), id: \.offset) { i, cover in
                PosterSlot(url: cover, .focus)
                    .rotationEffect(.degrees(fanAngle(i)), anchor: .bottom)
                    .offset(x: fanOffset(i))
                    // The centre poster is the subject; its neighbours are context.
                    .opacity(i == fanCovers.count / 2 ? 1 : 0.82)
                    .zIndex(i == fanCovers.count / 2 ? 1 : 0)
            }
        }
        .accessibilityHidden(true)
    }

    private func fanAngle(_ i: Int) -> Double {
        guard fanCovers.count > 1 else { return 0 }
        return [-7.0, 0, 7.0][i]
    }

    private func fanOffset(_ i: Int) -> CGFloat {
        guard fanCovers.count > 1 else { return 0 }
        return [-58, 0, 58][i]
    }

    /// Up to three covers, in the order Today ranks them, so the sheet's artwork is the artwork the
    /// user just tapped away from. Always 1 or 3 — a two-poster "fan" has no centre.
    private var fanCovers: [String] {
        let covers = orderedLibrary.compactMap(\.cover)
        if covers.count >= 3 { return Array(covers.prefix(3)) }
        return Array(covers.prefix(1))
    }

    /// The monogram, on the one warm disc this screen is allowed.
    ///
    /// `AccountDisc` with `AuthManager.identity` — the SAME derivation Today's header uses. Two
    /// independent ones produced "U" there (off the raw Clerk id) and "Y" here (off this screen's
    /// own fallback label "Your account"): one user, two meaningless letters, one tap apart.
    private var avatar: some View {
        AccountDisc(identity: auth.identity, diameter: 56)
            // `accentSoft` is a 14 % fill — over the poster fan the artwork would read straight
            // through the monogram. The disc gets its own opaque ground, which doubles as the cut
            // that separates it from the art behind it.
            .background(Circle().fill(ThemeColor.canvas).padding(-4))
            .shadow(.art)
            .accessibilityHidden(true)
    }

    // MARK: - Library counts

    private struct LibraryStat: Identifiable {
        let status: WatchStatus
        let count: Int
        var id: String { status.rawValue }
        var label: String { Copy.Status(status) }
    }

    private var libraryStats: [LibraryStat] {
        [WatchStatus.watching, .completed, .planned].map { status in
            LibraryStat(status: status, count: appModel.library.filter { $0.status == status }.count)
        }
    }

    /// Three counts on one plate — the one designed block on a settings surface, so it stays
    /// designed at accessibility sizes. Round 2 reflowed it into label/value rows, which turned the
    /// screen into three identical plates of label/value pairs and dropped the only thing that made
    /// it not-a-settings-table (P-16). At AX the numeral simply stacks above its caps label, one
    /// per row: the numbers stay the hero rather than becoming right-aligned values.
    private var stats: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: ThemeSpace.x5) {
                    ForEach(libraryStats) { stat in
                        VStack(alignment: .leading, spacing: ThemeSpace.x0_5) {
                            Text("\(stat.count)")
                                .type(ThemeType.numberXL)
                                .foregroundStyle(ThemeColor.textPrimary)
                                .numericFact(stat.count)
                            Text(stat.label)
                                .type(ThemeType.sectionLabel)
                                .textCase(.uppercase)
                                .foregroundStyle(ThemeColor.textTertiary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(ThemeSpace.x4)
            } else {
                HStack(spacing: 0) {
                    ForEach(Array(libraryStats.enumerated()), id: \.element.id) { i, stat in
                        if i > 0 {
                            Rectangle().fill(ThemeColor.separatorQuiet).frame(width: 1, height: 30)
                        }
                        VStack(spacing: ThemeSpace.x1) {
                            Text("\(stat.count)")
                                .type(ThemeType.numberXL)
                                .foregroundStyle(ThemeColor.textPrimary)
                                // Not `.contentTransition(.numericText())` raw: SwiftUI does not
                                // disable a numeric roll under Reduce Motion, and the check lives
                                // in `numericFact` once, for exactly these four numbers (P-18).
                                .numericFact(stat.count)
                            Text(stat.label)
                                .type(ThemeType.sectionLabel)
                                .textCase(.uppercase)
                                .foregroundStyle(ThemeColor.textTertiary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, ThemeSpace.x4)
            }
        }
        .surface(.plate, radius: ThemeRadius.row)
        .accessibilityElement(children: .combine)
        // Spoken in the natural order whatever the visual order is. Combined, the row read
        // "9, Watching, 15, Finished, 6, Planned" at default size and the other way round at AX —
        // the same data spoken two ways depending on a display setting (P-35).
        .accessibilityLabel(libraryStats.map { "\($0.count) \($0.label.lowercased())" }
            .joined(separator: ", "))
    }

    // MARK: - Sync

    private var syncSection: some View {
        ProfileSection(label: "Sync") {
            if sync.failedChanges.isEmpty {
                // Calm: the row IS the control, and it says so. A status row rendered in the same
                // grammar as the tappable rows below it, with nothing to press when the device is
                // stale, was a dead end (P-26).
                ProfileRow(symbol: syncSymbol,
                           symbolTint: syncTint,
                           title: syncTitle,
                           subtitle: syncStamp,
                           separator: false,
                           action: { Task { await appModel.reload() } }) {
                    if sync.checking {
                        ProgressView().controlSize(.small).tint(ThemeColor.textTertiary)
                            .frame(width: 44, height: 44)
                    } else {
                        Text(AccountCopy.syncNow)
                            .type(ThemeType.listAction)
                            .foregroundStyle(ThemeColor.accent)
                            .padding(.trailing, ThemeSpace.x2)
                    }
                }
                .accessibilityLabel(syncStamp.map { "\(syncTitle). \($0)" } ?? syncTitle)
                .accessibilityHint("Checks for changes")
            } else {
                // Failing: the summary row is a heading, not a button, because the plate below it
                // now carries real controls and a row cannot be two things.
                ProfileRowLabel(symbol: syncSymbol,
                                symbolTint: syncTint,
                                title: syncTitle,
                                separator: true) {
                    if sync.canRetryAny && sync.failedChanges.count > 1 {
                        Button(AccountCopy.retryAll) { sync.retryAll() }
                            .buttonStyle(InlineLinkButtonStyle())
                            .padding(.trailing, ThemeSpace.x2)
                    }
                }

                // No glyph on the detail rows: the section's state is declared ONCE, above them. A
                // stack of identical triangles down one plate is the same defect as a column of
                // grey check discs — the alarm stops being an alarm.
                ForEach(Array(sync.failedChanges.enumerated()), id: \.element.id) { i, change in
                    failureRow(change, isLast: i == sync.failedChanges.count - 1)
                }
            }
        }
    }

    /// One failed write, with the two things a user can actually do about it.
    ///
    /// The shipped row offered exactly one action — `Discard…`, in `textTertiary` (the disabled
    /// ramp), at the far trailing edge with zero inset, so the label truncated against the plate's
    /// rounded corner and read as a disabled fragment. "The app lost my progress and only offered
    /// to delete it" is a one-star review written for you (P-4).
    private func failureRow(_ change: FailedChange, isLast: Bool) -> some View {
        ProfileRowLabel(symbol: nil,
                        // Subject first, the order every other row in the app uses. The shipped
                        // row put the action before the show: "Moved to Paused · Black Clover".
                        title: "\(change.title) · \(change.command)",
                        subtitle: failureDetail(change),
                        separator: !isLast) {
            HStack(spacing: ThemeSpace.x2) {
                if change.canRetry(sync) {
                    Button(Copy.Action.retry) { sync.retry(change.id) }
                        .buttonStyle(InlineLinkButtonStyle())
                }
                // At accessibility sizes two controls plus a two-line title cannot share a row, so
                // the reversible one stays inline and Discard moves to the context menu below.
                if !dynamicTypeSize.isAccessibilitySize || !change.canRetry(sync) {
                    Button(AccountCopy.discard) { discardTarget = change.id }
                        .buttonStyle(InlineLinkButtonStyle(destructive: true))
                }
            }
            .padding(.trailing, ThemeSpace.x2)
        }
        .contextMenu {
            if change.canRetry(sync) {
                Button { sync.retry(change.id) } label: {
                    Label(Copy.Action.retry, systemImage: "arrow.clockwise")
                }
            }
            Button(role: .destructive) { discardTarget = change.id } label: {
                Label(AccountCopy.discard, systemImage: "trash")
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// "Couldn’t reach the server · 6:31 PM". The shipped row printed `Server error` and no time at
    /// all, so a user could not tell whether this failed a second ago or last week.
    ///
    /// The reason string itself comes from `Copy.Notice.reason(_:)` at record time and is shared
    /// with the sync banner on the roots; softening "Server error" belongs in `Copy` so both say
    /// the same thing, and that edit is filed as a shared request. Until it lands, this maps the
    /// one engineer-vocabulary string on the way to the screen — and passes anything else through,
    /// so the mapping becomes a no-op the moment the shared copy changes.
    private func failureDetail(_ change: FailedChange) -> String {
        let reason = change.reason == Copy.Notice.serverError
            ? AccountCopy.couldNotReachServer
            : change.reason
        return "\(reason) · \(Formatting.fmtTime(change.at))"
    }

    /// The state, in one sentence. Precedence matches `SyncCenter.syncedLine`; only the stamp is
    /// split off, because a stamp is not a state.
    private var syncTitle: String {
        if !sync.failedChanges.isEmpty { return Copy.Toast.syncFailed(sync.failedChanges.count) }
        if sync.checking { return Copy.State.checkingForChanges }
        if !sync.isOnline { return Copy.State.couldNotCheck }
        if sync.lastSyncedAt == nil { return Copy.State.neverSynced }
        return Copy.State.everythingSynced
    }

    /// Just the WHEN. "Everything synced" over "Synced just now" was two lines with one word doing
    /// all the work in both — the subtitle exists to add the time, and the title supplies the verb
    /// (P-23). Suppressed while something has failed: a stamp of the last successful check under
    /// "1 change couldn't sync" is a contradiction.
    private var syncStamp: String? {
        guard sync.failedChanges.isEmpty else { return nil }
        if !sync.isOnline { return Copy.Notice.noConnection }
        guard let at = sync.lastSyncedAt else { return nil }
        return stampWord(at)
    }

    /// "Just now" · "12 min ago" · "9:41 AM" · "Aug 19". Same ladder as `Copy.synced(at:now:)`
    /// without the verb the title already carries.
    private func stampWord(_ ts: Int64) -> String {
        let elapsed = max(0, now - ts)
        let minutes = Int(elapsed / Formatting.minuteMs)
        if minutes < 1 { return "Just now" }
        if minutes < 60 { return "\(minutes) min ago" }
        if Formatting.dayDiff(ts: ts, now: now) == 0 { return Formatting.fmtTime(ts) }
        return TemporalCopy.dateWord(ts, now: now, anchor: .local)
    }

    private var syncSymbol: String {
        if !sync.failedChanges.isEmpty { return "exclamationmark.triangle.fill" }
        if !sync.isOnline { return "wifi.slash" }
        if sync.checking || sync.lastSyncedAt == nil { return "arrow.triangle.2.circlepath" }
        // The healthiest state was the dimmest thing on the screen: a bare `checkmark` in
        // `textTertiary`, the grey used for disabled affordances (P-28). The two states now differ
        // in shape AND colour, not only glyph.
        return "checkmark.circle.fill"
    }

    private var syncTint: Color {
        // `destructive`, not `warning`: this is a write that FAILED — a data problem, not a
        // caution — and the amber triangle sat 400 pt from the amber switch and the amber Done
        // with neither of them meaning the same thing (P-17). `warning` stays on the stale-cache
        // edge the direction assigns it to.
        if !sync.failedChanges.isEmpty { return ThemeColor.destructive }
        if !sync.isOnline { return ThemeColor.textSecondary }
        if sync.checking || sync.lastSyncedAt == nil { return ThemeColor.textTertiary }
        return ThemeColor.success
    }

    // MARK: - Settings

    private var settings: some View {
        ProfileSection(label: "Settings") {
            Menu {
                // A header, and each format says what it is FOR. The shipped menu offered two bare
                // acronyms with no statement of what happens next (P-9).
                Section(AccountCopy.exportAs) {
                    // No `systemImage`. iOS puts a menu item's symbol on the trailing edge in the
                    // label colour; the shipped menu drew leading AMBER `curlybraces` and
                    // `tablecells`, which is a web/Android dropdown idiom — and accent on a menu
                    // item is never a primary action. `ScheduleView`'s filter menu removed its
                    // symbols for exactly this reason; that precedent wins.
                    ShareLink(item: LibraryExport(appModel: appModel, format: .json),
                              preview: SharePreview("Previously library (JSON)")) {
                        Text(AccountCopy.exportJSON)
                    }
                    ShareLink(item: LibraryExport(appModel: appModel, format: .csv),
                              preview: SharePreview("Previously library (CSV)")) {
                        Text(AccountCopy.exportCSV)
                    }
                }
            } label: {
                ProfileRowLabel(symbol: "tray.and.arrow.up",
                                title: "Export library",
                                subtitle: "Every title with progress and status") {
                    // `chevron.up.chevron.down` is the value-picker glyph — it implies a value the
                    // user can change, on a row that performs an action (P-14). Up/down is
                    // reserved for real pickers such as the Arrange sheet's Sort by.
                    trailingGlyph("chevron.forward", tint: ThemeColor.textDisabled, scale: 0.86)
                }
            }
            .buttonStyle(GroupedRowPressStyle())
            .accessibilityLabel("Export library")

            ProfileRow(symbol: "bell",
                       title: "Notifications",
                       // "the Live Activity" presumed knowledge of a capitalised Apple product
                       // term, and there is more than one of them (P-38).
                       subtitle: "Episode alerts and Live Activities",
                       action: { open(URL(string: UIApplication.openSettingsURLString)) }) {
                // This row leaves the app. An external arrow says so; a chevron would not.
                trailingGlyph("arrow.up.forward", tint: ThemeColor.textTertiary)
            }

            ProfileRowLabel(symbol: "hand.tap",
                            title: "Haptics",
                            // "marks" is internal vocabulary for "mark as watched" (P-38).
                            subtitle: "Feedback when you mark an episode watched",
                            separator: false) {
                // `.fixedSize()` is the whole fix for SYS-5: without it the row's layout stretched
                // the track to ~61×29 against the native 51×31 and rendered the knob as a rounded
                // pill instead of a circle — the most immediate "this is not a real iOS app" tell
                // there is. It is a real `Toggle`, not inside a `Button`'s label, so VoiceOver
                // announces the switch trait and its On/Off value (P-6).
                //
                // Amber, not system green: a switch reports selection, and selection in this app is
                // one colour. The `alignmentGuide` keeps it on the row's first line at AX sizes,
                // where a `labelsHidden` toggle carries no text baseline of its own.
                Toggle("Haptics", isOn: $hapticsOn)
                    .labelsHidden()
                    .fixedSize()
                    .tint(ThemeColor.accent)
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 6 }
            }
        }
        .onChange(of: hapticsOn) { _, on in
            FeedbackCoordinator.enabled = on
            if on { FeedbackCoordinator.fire(.selection) }
        }
    }

    // MARK: - Account (App Store guideline 5.1.1)

    /// Privacy, Terms and a way to reach a human — the three things guideline 5.1.1 asks for
    /// besides deletion, and the reason the account row now also states which account this is.
    ///
    /// Every destination comes from a build setting through `AppConfig`, never a URL written into
    /// copy: a placeholder baked into a shipped string is a broken Privacy Policy link, which is
    /// itself a rejection. The rows are always present and always look like rows — a legal link
    /// that is *missing* is the rejection; a build where one is unset is a misconfigured build,
    /// caught by the debug assertion in `open(_:)`, not something to dress up in the UI.
    private var accountSection: some View {
        ProfileSection(label: "Account") {
            legalRow(symbol: "hand.raised", title: AccountCopy.privacy, url: AppConfig.privacyURL)
            legalRow(symbol: "doc.text", title: AccountCopy.terms, url: AppConfig.termsURL)
            legalRow(symbol: "envelope",
                     title: AccountCopy.support,
                     subtitle: AppConfig.supportEmail,
                     url: AppConfig.supportURL,
                     separator: false)
        }
    }

    private func legalRow(symbol: String, title: String, subtitle: String? = nil,
                          url: URL?, separator: Bool = true) -> some View {
        ProfileRow(symbol: symbol,
                   title: title,
                   subtitle: subtitle,
                   separator: separator,
                   action: { open(url) }) {
            trailingGlyph("arrow.up.forward", tint: ThemeColor.textTertiary)
        }
    }

    // MARK: - Sign out / delete

    /// A `GroupedRow`, not a centred word. The shipped control was the only centred row on the
    /// screen and its plate had no icon column, so it broke the grammar of the two plates above it
    /// — a button wearing a list row's clothes (P-31). The colour carries the weight.
    private var signOutSection: some View {
        ProfileSection {
            ProfileRow(symbol: "rectangle.portrait.and.arrow.right",
                       symbolTint: ThemeColor.destructive,
                       title: AccountCopy.signOut,
                       titleTint: ThemeColor.destructive,
                       separator: false,
                       action: { confirmSignOut = true }) {
                // Every other write in the app is optimistic and shows its result immediately; the
                // one that cannot be undone showed nothing at all, so a user who waited a second
                // tapped Sign out again (P-19).
                if signingOut {
                    ProgressView().controlSize(.small).tint(ThemeColor.destructive)
                        .frame(width: 44, height: 44)
                }
            }
            .disabled(signingOut || deleting)
        }
    }

    /// Its own plate, below sign-out and separated from it: one of these two rows is reversible and
    /// the other is not, and the layout should never let a thumb confuse them.
    private var deleteSection: some View {
        ProfileSection {
            ProfileRow(symbol: "trash",
                       symbolTint: ThemeColor.destructive,
                       title: AccountCopy.delete,
                       titleTint: ThemeColor.destructive,
                       subtitle: AccountCopy.deleteSubtitle,
                       separator: false,
                       action: { confirmDelete = true }) {
                if deleting {
                    ProgressView().controlSize(.small).tint(ThemeColor.destructive)
                        .frame(width: 44, height: 44)
                }
            }
            .disabled(signingOut || deleting)
        }
    }

    /// States the outcome with the count. "Changes that haven't synced yet are kept on this device"
    /// left the user asking kept and uploaded? kept and orphaned? kept until I delete the app? (P-24)
    private var signOutMessage: String {
        let pending = sync.failedChanges.count
        guard pending > 0 else {
            return "Your library stays in your account. Signing back in brings it all back."
        }
        return "Your library stays in your account. \(Copy.changes(pending)) hasn’t synced yet — "
            + "it stays on this device and uploads the next time you sign in."
    }

    /// The blast radius, in the user's own numbers.
    private var deleteMessage: String {
        let titles = appModel.library.count
        return "This permanently deletes your account and everything in it"
            + (titles > 0 ? " — \(Copy.titles(titles)), all progress and watch history" : "")
            + ". It can’t be undone."
    }

    private func performSignOut() {
        FeedbackCoordinator.fire(.destructive)
        withAnimation(ThemeMotion.pick(ThemeMotion.uiGentle, reduceMotion: reduceMotion)) {
            signingOut = true
        }
        Task {
            await auth.signOut()
            signingOut = false
        }
    }

    private func performDelete() {
        FeedbackCoordinator.fire(.destructive)
        withAnimation(ThemeMotion.pick(ThemeMotion.uiGentle, reduceMotion: reduceMotion)) {
            deleting = true
        }
        Task {
            do {
                try await AccountDeletion.deleteAccount(token: auth.currentToken)
                // The account is gone; the session must go with it, and the sheet with that.
                await auth.signOut()
                deleting = false
                dismiss()
            } catch {
                deleting = false
                deleteFailure = (error as? LocalizedError)?.errorDescription
                    ?? AccountDeletion.Failure.refused.errorDescription
            }
        }
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - About

    /// How the screen ends: the mark, the version, and the attribution the TMDB terms require —
    /// set as fine print, because that is what it is. Round 2's three centred grey lines at
    /// near-identical sizes with uneven gaps read ragged, and the disclaimer wrapped to a two-word
    /// orphan (P-32).
    private var colophon: some View {
        VStack(spacing: ThemeSpace.x2) {
            HStack(spacing: 7) {
                PreviouslyMark(width: 11, detail: .none)
                Text("Previously.")
                    .type(ThemeType.brandWordmark)
                    .foregroundStyle(ThemeColor.textSecondary)
            }
            Text(version)
                .type(ThemeType.caption)
                .foregroundStyle(ThemeColor.textTertiary)
                .monospacedDigit()
            Text("Data from AniList and TMDB. This product uses the TMDB API but is not endorsed "
                 + "or certified by TMDB.")
                .type(ThemeType.caption)
                .foregroundStyle(ThemeColor.textDisabled)
                .multilineTextAlignment(.center)
                .padding(.top, ThemeSpace.x2)
        }
        .frame(maxWidth: 300)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Helpers

    /// A trailing indicator that scales with the row's text. Fixed-size glyphs shrank to specks
    /// against ~24-pt titles at AX1 (P-30).
    private func trailingGlyph(_ symbol: String, tint: Color, scale: CGFloat = 1) -> some View {
        Image(systemName: symbol)
            .font(.system(size: indicatorSize * scale, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 28, height: 44)
            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 6 }
    }

    private func open(_ url: URL?) {
        guard let url else {
            // A legal destination that is not configured is a build problem, not a runtime state
            // to render — it can never reach a shipping build, where `PRIVACY_POLICY_URL` /
            // `TERMS_URL` / `SUPPORT_EMAIL` are all set. It is logged rather than asserted: a
            // developer build that traps on a Privacy Policy tap is a worse debugging experience
            // than one line in the console, and QA runs against Debug builds.
            #if DEBUG
            print("[Profile] A legal or support destination is not configured for this build.")
            #endif
            return
        }
        openURL(url)
    }

    /// A Clerk user id is not a name. `AccountIdentity` already answers this, once, for every
    /// surface — this screen no longer decides it for itself.
    private var accountName: String { auth.identity.displayName }

    /// The one fact a profile screen exists to answer besides "who": how this device is signed in.
    private var provenance: String {
        switch auth.identity.provenance {
        case .developer: return "Developer session"
        default: return "Signed in with Clerk"
        }
    }

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        return b.map { "\(v) (\($0))" } ?? v
    }

    /// The library in the order Today ranks it — so the sheet's wash and its poster fan are drawn
    /// from the same cover that is on screen behind the sheet, instead of an unrelated one (P-11).
    private var orderedLibrary: [Franchise] {
        let ranked = appModel.outNow + appModel.keepWatching
        let rest = appModel.library.filter { f in !ranked.contains(where: { $0.id == f.id }) }
        return ranked + rest.filter { $0.status == .watching } + rest.filter { $0.status != .watching }
    }

    /// The wash is the user's own library. `nil` on an empty account, where the plain canvas is the
    /// honest ground.
    private var washArtwork: String? { orderedLibrary.first?.cover }
}

// MARK: - Copy

/// The strings this screen introduces. Not in `Copy.swift` because that table is shared design
/// system and this track does not own it; the destructive and legal vocabulary is kept in one
/// place here so no row can invent its own wording.
private enum AccountCopy {
    static let signOut = "Sign out"
    static let signOutTitle = "Sign out?"

    static let delete = "Delete account\u{2026}"
    static let deleteSubtitle = "Erases your library, progress and history"
    static let deleteTitle = "Delete your account?"
    static let deleteConfirm = "Delete account"
    static let deleteFailedTitle = "Couldn\u{2019}t delete your account"

    static let privacy = "Privacy Policy"
    static let terms = "Terms of Use"
    static let support = "Contact support"

    static let syncNow = "Sync now"
    static let retryAll = "Retry all"
    /// The full word, never truncated. `Discard\u{2026}`'s ellipsis was ambiguous — a confirmation
    /// or a truncation? It was both (P-39). It still opens a confirmation; the row's own control
    /// no longer has to carry that in three dots it does not have room for.
    static let discard = "Discard"
    static let couldNotReachServer = "Couldn\u{2019}t reach the server"

    static let exportAs = "Export as"
    static let exportJSON = "JSON \u{2014} everything"
    static let exportCSV = "CSV \u{2014} for spreadsheets"
}

// MARK: - Wash

/// The ambient field at the top of the sheet — the local stand-in for the shared `ArtBackdrop` fix
/// filed with this pass.
///
/// It draws NO image. `ArtBackdrop` blurs the poster's own top-left corner, which is why this
/// screen measured rgb(66,80,94) on one side against rgb(29,49,67) on the other: a blurred crop of
/// an off-centre region is lit by whatever happened to be in that region, and a 2.2x left-to-right
/// falloff reads as a bug, not as atmosphere. An elliptical field centred on the top edge is even
/// by construction, and mixing the derived colour half-way to `accent` keeps every screen's
/// atmosphere inside the brand's warm range instead of letting one poster turn the app steel blue.
private struct ProfileWash: View {
    var tint: Color?
    var height: CGFloat = 540

    /// Where the field is allowed to start: the bottom of the opaque navigation bar. Above this
    /// there is nothing to see, and the ramp below it means the bar's bottom edge is never a seam.
    private var barBottom: CGFloat { ThemeMetrics.topSafeInset + 44 }

    /// The field's HUE is the brand's; the poster only modulates how saturated and how present it
    /// is. A straight 50/50 RGB mix with `accent` measured rgb(37,36,33) on the capture — this
    /// account's cover derives a steel blue, and blue plus amber in equal parts is grey. Anchoring
    /// the hue is what delivers the rule the finding was written for: the app's atmosphere must not
    /// change hue from tab to tab.
    private var warm: Color {
        var bh: CGFloat = 0, bs: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        var ah: CGFloat = 0, asat: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        UIColor(tint ?? PaletteCache.fallback).getHue(&bh, saturation: &bs, brightness: &bb, alpha: &ba)
        UIColor(ThemeColor.accent).getHue(&ah, saturation: &asat, brightness: &ab, alpha: &aa)
        let saturation = min(max(bs * 0.5 + asat * 0.5, 0.30), asat)
        return Color(hue: Double(ah), saturation: Double(saturation), brightness: 0.85)
    }

    var body: some View {
        EllipticalGradient(
            stops: [
                .init(color: warm.opacity(0.28), location: 0.00),
                .init(color: warm.opacity(0.16), location: 0.42),
                .init(color: warm.opacity(0.09), location: 0.62),
                .init(color: warm.opacity(0.04), location: 0.80),
                .init(color: .clear, location: 1.00),
            ],
            center: UnitPoint(x: 0.5, y: 0.42),
            startRadiusFraction: 0,
            endRadiusFraction: 0.92
        )
        .frame(height: height)
        .frame(maxWidth: .infinity, alignment: .top)
        // Nothing above the bar, and a 90-pt ramp under it. The peak lands behind the monogram,
        // which is where a wash on an identity screen belongs.
        .mask(
            VStack(spacing: 0) {
                Color.clear.frame(height: barBottom)
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: 90)
                Rectangle().fill(.black)
            }
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Section

/// A labelled plate. It is deliberately not `GroupedList`: that primitive indents its header by a
/// further 16 pt in the iOS grouped-table tradition. Everything else — the plate, the radius, the
/// label gap — is the design system's.
private struct ProfileSection<Content: View>: View {
    var label: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: ThemeMetrics.labelGap) {
            if let label {
                SectionLabel(text: label)
                    // The eyebrow aligns to the leading edge of the ROW CONTENT inside the plate it
                    // labels — the same relationship the Arrange sheet has, where the rows carry no
                    // icon column so its content edge and its text are the same line. On Profile
                    // the eyebrows sat on the plate's OUTER edge while the row content began 16 pt
                    // further in: two conventions for one relationship in two sheets of one app
                    // (P-15).
                    .padding(.leading, ThemeSpace.x4)
                    // VoiceOver's heading rotor is how a settings screen is skimmed. Only the
                    // account name carried `.isHeader`, so a five-section screen had one stop
                    // (P-22). Filed as a shared request against `SectionLabel` itself.
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(spacing: 0) { content() }
                .surface(.plate, radius: ThemeRadius.row)
        }
    }
}

// MARK: - Rows

/// A settings row, in the shape this screen needs: one monochrome glyph column, a title, one
/// support line, and a trailing control area.
///
/// It is deliberately not `GroupedRow`: that primitive paints a tinted 28-pt tile behind its
/// symbol, hard-codes `success` as its toggle tint and has no destructive or in-flight state.
/// The geometry, the plate, the press style and the quiet separator all still come from the
/// design system.
private struct ProfileRowLabel<Trailing: View>: View {
    /// `nil` keeps the column's width and draws nothing — a continuation row under one that
    /// already carries the group's state.
    let symbol: String?
    var symbolTint: Color = ThemeColor.textSecondary
    var symbolWeight: Font.Weight = .medium
    let title: String
    var titleTint: Color = ThemeColor.textPrimary
    var subtitle: String? = nil
    var separator = true
    @ViewBuilder var trailing: () -> Trailing

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Glyph column + its gap. The separator starts where the TITLE starts, never at the plate
    /// edge — an inset separator is what makes a group read as one thing.
    private var textInset: CGFloat { ThemeSpace.x4 + 22 + ThemeSpace.x3 }

    var body: some View {
        // At accessibility sizes a two-line title makes a vertically centred glyph sit beside the
        // SUBTITLE. Baseline alignment keeps it with the line it belongs to.
        HStack(alignment: dynamicTypeSize.isAccessibilitySize ? .firstTextBaseline : .center,
               spacing: ThemeSpace.x3) {
            Group {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 16, weight: symbolWeight))
                        .foregroundStyle(symbolTint)
                } else {
                    Color.clear.frame(height: 1)
                }
            }
            .frame(width: 22)
            VStack(alignment: .leading, spacing: ThemeSpace.x0_5) {
                Text(title)
                    .type(ThemeType.body)
                    .foregroundStyle(titleTint)
                    .lineLimit(2)
                if let subtitle {
                    Text(subtitle)
                        .type(ThemeType.metadata)
                        .foregroundStyle(ThemeColor.textTertiary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: ThemeSpace.x2)
            trailing()
        }
        .padding(.leading, ThemeSpace.x4)
        .padding(.trailing, ThemeSpace.x2)
        .padding(.vertical, ThemeSpace.x2)
        .frame(minHeight: ThemeMetrics.rowCompact)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            if separator {
                Rectangle().fill(ThemeColor.separatorQuiet).frame(height: 1)
                    .padding(.leading, textInset)
            }
        }
    }
}

private struct ProfileRow<Trailing: View>: View {
    let symbol: String?
    var symbolTint: Color = ThemeColor.textSecondary
    var symbolWeight: Font.Weight = .medium
    let title: String
    var titleTint: Color = ThemeColor.textPrimary
    var subtitle: String? = nil
    var separator = true
    let action: () -> Void
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        Button(action: action) {
            ProfileRowLabel(symbol: symbol, symbolTint: symbolTint, symbolWeight: symbolWeight,
                            title: title, titleTint: titleTint, subtitle: subtitle,
                            separator: separator, trailing: trailing)
        }
        .buttonStyle(GroupedRowPressStyle())
    }
}
