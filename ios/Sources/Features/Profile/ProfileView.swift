import SwiftUI
import UIKit

// Profile (spec board 08): the modal where trust is inspectable — the sync line and every failed
// change with Retry — in the iOS grouped-list grammar, over the ambient warmth of the account's own
// library. No import this version.
//
// POLISH PASS 2. What round 1 still got wrong, measured off `after-*.png`, and what replaces it:
//
//  • THE WASH WAS A GRADIENT BUG. `ArtBackdrop` blurs the poster's own top-left corner and pushes
//    `.saturation(1.25)` through it, so this screen opened on rgb(66,80,94) at the left and
//    rgb(29,49,67) at the right: a steel blue, 2.2x brighter on one side than the other, with no
//    relationship to the brand — and Schedule rendered the same primitive olive and Search slate,
//    so the app's atmosphere changed hue by tab. Scrolled, it became an opaque blue rectangle with
//    settings rows sliding under it. It is replaced here by `ProfileWash`: the derived colour mixed
//    half-way to `accent`, laid down as an elliptical field that is even by construction (no crop,
//    no blur, nothing to be brighter on one side of), and faded to nothing over the first 40 pt of
//    scroll so the settings sheet keeps no coloured band. The systemic fix belongs in `ArtBackdrop`
//    and is filed as a shared request; this is the local stand-in.
//  • THE AVATAR WORE THE APP'S OWN BOOKMARK. A product logo in an avatar slot, on an account whose
//    name renders "Your account", is the same failure the direction named for `person.crop.circle`.
//    It is a monogram now — Clerk first name, else the email's first letter, else the first letter
//    of the account label — on an `accentSoft` disc. Never the mark, never a stock glyph.
//  • THE SYNC ROW WAS A 56-PT GUTTER. "Synced just now" at the left, a 20-pt refresh glyph at the
//    far right, 300 pt of nothing between. The row is two lines now — the state, then the stamp —
//    the whole row is the refresh target, and the standard gesture (`.refreshable`) refreshes the
//    sheet. Nothing floats at the far edge.
//  • TWO EXPORT ROWS, IDENTICAL, one of them lead by `curlybraces` — a developer glyph in a
//    consumer list. One `Export library` row now, `tray.and.arrow.up`, and the format is a menu.
//  • `Done` was a bordered amber capsule floating on the wash where iOS puts plain text, and with
//    no navigation title VoiceOver never announced the screen. The bar is a real inline navigation
//    bar now: it announces "Profile", it earns its own scroll-edge material, and `Done` is text.
//  • The failure badge was a saturated filled `exclamationmark.triangle.fill` — a fourth warm hue
//    on a screen that already had amber Retry and red Sign out, and the loudest object in the frame
//    was the badge rather than the change it described. Unfilled, at `warning`, sized to its row.
struct ProfileView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var hapticsOn = FeedbackCoordinator.enabled
    @State private var confirmSignOut = false
    @State private var discardTarget: UUID?
    /// Resolved here rather than read off `PaletteCache` synchronously: this screen draws no
    /// poster, so nothing else on it would ever prime the cache and the wash would fall back to
    /// neutral on a cold open.
    @State private var washTint: Color?
    /// Drives the wash out. Read from scroll geometry rather than a `GeometryReader` sentinel so
    /// nothing in the content tree has to know the wash exists.
    @State private var scrollOffset: CGFloat = 0

    private var now: Int64 { appModel.now }
    private var sync: SyncCenter { SyncCenter.shared }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                ProfileWash(tint: washTint)
                    // Gone by 40 pt. A settings sheet that keeps a coloured band behind its rows
                    // while they scroll under it is a broken sticky header, not atmosphere.
                    .opacity(Double(max(0, 1 - scrollOffset / 40)))
                    .ignoresSafeArea(edges: .top)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        identity
                        if !appModel.library.isEmpty {
                            stats.padding(.top, ThemeMetrics.heroClearance)
                        }
                        syncSection.padding(.top, ThemeMetrics.sectionGap)
                        settings.padding(.top, ThemeMetrics.sectionGap)
                        signOut.padding(.top, ThemeMetrics.sectionGap)
                        colophon.padding(.top, ThemeSpace.x10)
                    }
                    .padding(.horizontal, ThemeMetrics.gutter)
                    // Generous under the bar: the identity is the hero of this screen and 16 pt
                    // put the monogram's shadow within a hair of the bar's edge.
                    .padding(.top, ThemeSpace.x6)
                    .padding(.bottom, ThemeSpace.x8)
                }
                .scrollIndicators(.hidden)
                // A settings sheet needs a real edge, not a progressive blur: with the soft
                // default the 28-pt account name scrolled up and ghosted through the bar directly
                // behind the word "Profile". `.hard` is the system's own answer and it lands the
                // rows cleanly at the bar's bottom.
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
            // A real inline navigation bar, for two reasons the round-1 screen paid for by not
            // having one: VoiceOver announces the screen, and the system's own scroll-edge
            // material takes over from the wash as it fades — so rows never slide under a
            // coloured rectangle. The identity block below is still the visual header.
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            // An OPAQUE bar, not the SDK's default progressive blur and not `.visible` glass:
            // both let the 28-pt account name dissolve directly behind the word "Profile" on the
            // way up, and a bold title ghosting through a title is an artefact, not a transition.
            // A settings sheet wants a real edge. The seam this would otherwise create with the
            // wash is handled in `ProfileWash`, which starts below the bar and ramps up.
            .toolbarBackground(ThemeColor.canvas, for: .navigationBar)
            .toolbarBackgroundVisibility(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    // Plain text where iOS puts plain text. A bordered capsule here is the same
                    // class of mistake as a filled Cancel in a sheet — and on this SDK the capsule
                    // is the toolbar's own shared glass, so `buttonStyle` alone does not remove it.
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
        .confirmationDialog("Sign out?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) {
                FeedbackCoordinator.fire(.destructive)
                Task { await auth.signOut() }
            }
            Button(Copy.Confirm.cancel, role: .cancel) {}
        } message: {
            Text("Your library stays in your account. Changes that haven’t synced yet are kept on this device.")
        }
        .confirmationDialog(Copy.Confirm.discardChangeTitle,
                            isPresented: Binding(get: { discardTarget != nil },
                                                 set: { if !$0 { discardTarget = nil } }),
                            titleVisibility: .visible) {
            Button(Copy.Confirm.discardChangeConfirm, role: .destructive) {
                if let id = discardTarget { sync.discard(id) }
                discardTarget = nil
            }
            Button(Copy.Confirm.cancel, role: .cancel) { discardTarget = nil }
        } message: {
            Text(Copy.Confirm.discardChangeMessage)
        }
    }

    // MARK: - Identity

    /// Avatar → name → how they signed in. Three beats, one column, centred over the wash. The
    /// sync line is NOT one of them: it lives in the Sync section, once.
    private var identity: some View {
        VStack(spacing: 0) {
            avatar
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

    /// The monogram, on the one warm disc this screen is allowed. Round 1 put the app's own
    /// bookmark here, which is a product logo standing in for a person.
    ///
    /// It is a filled `accent` disc with the monogram in `onAccent`, lit along its top edge by
    /// `controlSheen` the way rule 7 lights every filled object. The first attempt at this pass
    /// used `accentSoft` and it measured rgb(48,40,32) on the capture — a brown smudge that read
    /// as a hole in the wash, not as a person; `fresh/today-profile-sheet.png`, the baseline this
    /// screen has to beat, used exactly this lit amber disc. It is the only filled accent object
    /// on the screen: `Done` is text and `Sign out` is `destructive`.
    private var avatar: some View {
        // `AccountDisc` with `AuthManager.identity` — the SAME derivation Today's header uses.
        // Two independent ones produced "U" there (off the raw Clerk id) and "Y" here (off this
        // screen's own fallback label "Your account"): one user, two meaningless letters, one tap
        // apart. 56 pt, not 72: at full accent and 72 the disc was the loudest object in the app.
        AccountDisc(identity: auth.identity, diameter: 56)
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

    /// Three counts on one plate. At accessibility sizes three 34-pt numerals cannot share a
    /// 440-pt line, so the same plate becomes three rows rather than shrinking the type.
    private var stats: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 0) {
                    ForEach(Array(libraryStats.enumerated()), id: \.element.id) { i, stat in
                        HStack {
                            Text(stat.label).type(ThemeType.body).foregroundStyle(ThemeColor.textSecondary)
                            Spacer(minLength: ThemeSpace.x3)
                            Text("\(stat.count)").type(ThemeType.bodyEmphasis).foregroundStyle(ThemeColor.textPrimary)
                        }
                        .padding(.horizontal, ThemeSpace.x4)
                        .frame(minHeight: ThemeMetrics.rowCompact)
                        .overlay(alignment: .bottom) {
                            if i < libraryStats.count - 1 {
                                Rectangle().fill(ThemeColor.separatorQuiet).frame(height: 1)
                                    .padding(.horizontal, ThemeSpace.x4)
                            }
                        }
                    }
                }
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
                                .contentTransition(.numericText())
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
    }

    // MARK: - Sync

    private var syncSection: some View {
        ProfileSection(label: "Sync") {
            // Two lines, the way every other row on this plate is two lines: the state, then the
            // stamp. Round 1 printed the stamp as the title and then had nothing to put on the
            // second line, so it hung a lone glyph 300 pt away instead.
            ProfileRow(symbol: syncSymbol,
                       symbolTint: syncTint,
                       symbolWeight: sync.failedChanges.isEmpty ? .medium : .regular,
                       title: syncTitle,
                       subtitle: syncStamp,
                       separator: !sync.failedChanges.isEmpty,
                       action: { Task { await appModel.reload() } }) {
                // Nothing at rest. The row IS the control; a check in flight is the only thing
                // worth putting in the trailing column, because it is the only thing that changes.
                if sync.checking {
                    ProgressView().controlSize(.small).tint(ThemeColor.textTertiary)
                        .frame(width: 28, height: 44)
                }
            }
            .accessibilityLabel(syncStamp.map { "\(syncTitle). \($0)" } ?? syncTitle)
            .accessibilityHint("Checks for changes")

            // No glyph on the detail rows: the section's state is declared ONCE, by the summary
            // row above them. A stack of identical `warning` triangles down one plate is the same
            // defect as a column of grey check discs — the alarm stops being an alarm. The empty
            // glyph column keeps every title on one rail.
            ForEach(Array(sync.failedChanges.enumerated()), id: \.element.id) { i, change in
                ProfileRow(symbol: nil,
                           title: "\(change.command) · \(change.title)",
                           subtitle: change.reason,
                           separator: i < sync.failedChanges.count - 1,
                           action: { if change.canRetry(sync) { sync.retry(change.id) } else { discardTarget = change.id } }) {
                    // One way out, always visible. A change restored from a previous launch has no
                    // retry closure to re-run (`SyncCenter.onRestoredRetry` is never set), and the
                    // shipped row answered that by rendering NOTHING: a warning with a reason and
                    // no control, which is the definition of a dead end. `Discard…` earns its
                    // ellipsis — it opens the board-09 confirmation.
                    if change.canRetry(sync) {
                        Text(Copy.Action.retry)
                            .type(ThemeType.listAction)
                            .foregroundStyle(ThemeColor.accent)
                    } else {
                        Text(Copy.Action.discard)
                            .type(ThemeType.listAction)
                            .foregroundStyle(ThemeColor.textTertiary)
                    }
                }
                .contextMenu {
                    Button(role: .destructive) { discardTarget = change.id } label: {
                        Label(Copy.Action.discard, systemImage: "trash")
                    }
                }
            }
        }
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

    /// "Synced 2 min ago". Suppressed while something has FAILED to sync — the stamp of the last
    /// successful check under the words "1 change couldn't sync" reads as a contradiction, and the
    /// rows underneath already carry the detail. Suppressed too when there is no stamp to print.
    private var syncStamp: String? {
        guard sync.failedChanges.isEmpty else { return nil }
        if !sync.isOnline { return Copy.Notice.noConnection }
        guard let at = sync.lastSyncedAt else { return nil }
        return Copy.synced(at: at, now: now)
    }

    private var syncSymbol: String {
        // Unfilled. A saturated yellow solid was the loudest object on a screen whose subject is
        // the change that failed — `warning` belongs on the edge of a failure, not in a badge.
        if !sync.failedChanges.isEmpty { return "exclamationmark.triangle" }
        if !sync.isOnline { return "wifi.slash" }
        if sync.checking || sync.lastSyncedAt == nil { return "arrow.triangle.2.circlepath" }
        // A settled fact is a bare checkmark, never a filled disc.
        return "checkmark"
    }

    private var syncTint: Color {
        if !sync.failedChanges.isEmpty { return ThemeColor.warning }
        if !sync.isOnline { return ThemeColor.textSecondary }
        return ThemeColor.textTertiary
    }

    // MARK: - Settings

    private var settings: some View {
        ProfileSection(label: "Settings") {
            // One row, one glyph, one menu. Round 1 shipped two rows of identical shape carrying
            // the same trailing share glyph twice, the first of them lead by `curlybraces`.
            Menu {
                ShareLink(item: LibraryExport(appModel: appModel, format: .json),
                          preview: SharePreview("Previously library (JSON)")) {
                    Label("JSON", systemImage: "curlybraces")
                }
                ShareLink(item: LibraryExport(appModel: appModel, format: .csv),
                          preview: SharePreview("Previously library (CSV)")) {
                    Label("CSV", systemImage: "tablecells")
                }
            } label: {
                ProfileRowLabel(symbol: "tray.and.arrow.up",
                                title: "Export library",
                                subtitle: "Every title with progress and status") {
                    // The iOS menu affordance, not a chevron: this row opens a menu in place, it
                    // does not push.
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ThemeColor.textDisabled)
                        .frame(width: 28, height: 44)
                        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 6 }
                }
            }
            .buttonStyle(GroupedRowPressStyle())
            .accessibilityLabel("Export library")

            ProfileRow(symbol: "bell",
                       title: "Notifications",
                       subtitle: "Episode alerts and the Live Activity",
                       action: {
                           if let url = URL(string: UIApplication.openSettingsURLString) {
                               UIApplication.shared.open(url)
                           }
                       }) {
                // This row leaves the app. An external arrow says so; a chevron would not.
                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ThemeColor.textTertiary)
                    .frame(width: 28, height: 44)
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 6 }
            }

            ProfileRowLabel(symbol: "hand.tap",
                            title: "Haptics",
                            subtitle: "Confirms marks and milestones",
                            separator: false) {
                // Amber, not system green: a switch reports selection, and selection in this app
                // is one colour. Green here is decoration, and `success` is never decoration.
                //
                // The guide is the AX1 fix: a `labelsHidden` toggle carries no text baseline, so
                // in a baseline-aligned row it fell back to the row's vertical centre while its
                // three sibling glyphs sat on the first line. The column was visibly crooked.
                Toggle("Haptics", isOn: $hapticsOn).labelsHidden().tint(ThemeColor.accent)
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 6 }
            }
        }
        .onChange(of: hapticsOn) { _, on in
            FeedbackCoordinator.enabled = on
            if on { FeedbackCoordinator.fire(.selection) }
        }
    }

    // MARK: - Sign out

    private var signOut: some View {
        ProfileSection {
            Button { confirmSignOut = true } label: {
                Text("Sign out")
                    .type(ThemeType.body)
                    .foregroundStyle(ThemeColor.destructive)
                    .frame(maxWidth: .infinity, minHeight: ThemeMetrics.rowCompact)
                    .padding(.horizontal, ThemeSpace.x4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(GroupedRowPressStyle())
        }
    }

    // MARK: - About

    /// How the screen ends: the mark, the version, and the attribution the TMDB terms require —
    /// set as fine print, because that is what it is.
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
                .foregroundStyle(ThemeColor.textDisabled)
                .monospacedDigit()
            Text("Data from AniList and TMDB")
                .type(ThemeType.caption)
                .foregroundStyle(ThemeColor.textDisabled)
                .padding(.top, ThemeSpace.x2)
            Text("This product uses the TMDB API but is not endorsed or certified by TMDB.")
                .type(ThemeType.caption)
                .foregroundStyle(ThemeColor.textDisabled)
                .multilineTextAlignment(.center)
                .padding(.horizontal, ThemeSpace.x6)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Helpers

    /// A Clerk user id is not a name. `AccountIdentity` already answers this, once, for every
    /// surface — this screen no longer decides it for itself.
    private var accountName: String { auth.identity.displayName }

    /// The one fact a profile screen exists to answer besides "who": how this device is signed in.
    /// It is deliberately not the sync line — that belongs to Sync, and printing it twice is how
    /// the shipped build ended up with two greys saying the same thing.
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

    /// The wash is the user's own library: the first thing they are watching, else the first thing
    /// they have. `nil` on an empty account, where the plain canvas is the honest ground.
    private var washArtwork: String? {
        (appModel.library.first { $0.status == .watching } ?? appModel.library.first)?.cover
    }
}

// MARK: - Wash

/// The ambient field at the top of the sheet — the local stand-in for the shared `ArtBackdrop`
/// fix filed with this pass.
///
/// It draws NO image. `ArtBackdrop` blurs the poster's own top-left corner, which is why this
/// screen measured rgb(66,80,94) on one side against rgb(29,49,67) on the other: a blurred crop of
/// an off-centre region is lit by whatever happened to be in that region, and a 2.2x left-to-right
/// falloff reads as a bug, not as atmosphere. An elliptical field centred on the top edge is even
/// by construction, and mixing the derived colour half-way to `accent` keeps every screen's
/// atmosphere inside the brand's warm range instead of letting one poster turn the app steel blue.
private struct ProfileWash: View {
    var tint: Color?
    var height: CGFloat = 420

    /// Where the field is allowed to start: the bottom of the opaque navigation bar. Above this
    /// there is nothing to see, and the ramp below it means the bar's bottom edge is never a seam.
    private var barBottom: CGFloat { ThemeMetrics.topSafeInset + 44 }

    /// The field's HUE is the brand's; the poster only modulates how saturated and how present it
    /// is. A straight 50/50 RGB mix of the derived colour with `accent` — the first thing tried —
    /// measured rgb(37,36,33) on the capture: this account's cover derives a steel blue, and blue
    /// plus amber in equal parts is grey. Anchoring the hue is what actually delivers the rule the
    /// finding was written for: the app's atmosphere must not change hue from tab to tab.
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
                .init(color: warm.opacity(0.26), location: 0.00),
                .init(color: warm.opacity(0.15), location: 0.42),
                .init(color: warm.opacity(0.05), location: 0.75),
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
/// further 16 pt in the iOS grouped-table tradition, and on a screen whose plates, hero and
/// colophon all sit on the 16-pt gutter that leaves the labels aligned to nothing. Everything else
/// — the plate, the radius, the label gap — is the design system's.
private struct ProfileSection<Content: View>: View {
    var label: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: ThemeMetrics.labelGap) {
            if let label { SectionLabel(text: label) }
            VStack(spacing: 0) { content() }
                .surface(.plate, radius: ThemeRadius.row)
        }
    }
}

// MARK: - Rows

/// A settings row, in the shape this screen needs: one monochrome glyph column, a title, one
/// support line, and at most one trailing control.
///
/// It is deliberately not `GroupedRow`: that primitive paints a tinted 28-pt tile behind its
/// symbol, hard-codes `success` as its toggle tint and has no destructive or in-flight state —
/// three things this screen has to override. The geometry, the plate, the press style and the
/// quiet separator all still come from the design system.
private struct ProfileRowLabel<Trailing: View>: View {
    /// `nil` keeps the column's width and draws nothing — a continuation row under one that
    /// already carries the group's state.
    let symbol: String?
    var symbolTint: Color = ThemeColor.textSecondary
    var symbolWeight: Font.Weight = .medium
    let title: String
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
                    .foregroundStyle(ThemeColor.textPrimary)
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
    var subtitle: String? = nil
    var separator = true
    let action: () -> Void
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        Button(action: action) {
            ProfileRowLabel(symbol: symbol, symbolTint: symbolTint, symbolWeight: symbolWeight,
                            title: title, subtitle: subtitle, separator: separator,
                            trailing: trailing)
        }
        .buttonStyle(GroupedRowPressStyle())
    }
}
