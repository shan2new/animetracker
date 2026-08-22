import SwiftUI
import UIKit

// Profile (spec board 08): the modal where trust is inspectable — the sync line and every failed
// change with Retry — in the iOS grouped-list grammar, over the ambient wash of the account's own
// library. No import this version.
//
// POLISH PASS. What the shipped screen (`g-profile-full.png`) got wrong, and what replaces it:
//
//  • It opened on a generic `person.fill` glyph beside the words "Your account" — a placeholder
//    where the identity belongs. It now opens on an 84-pt monogram over a full-bleed warm wash
//    taken from the account's own library, the name at `heroTitle`, how they signed in at
//    `heroMeta`, and a three-up count of what is in that library. `fresh/today-profile-sheet.png`
//    had exactly this block and it is most of why the original modal felt like a place.
//  • The wash could not be restored under an OPAQUE toolbar: a backdrop that reaches full strength
//    behind the bar meets the bar's bottom edge as a hard horizontal seam across the screen (the
//    first iteration of this pass shipped one: 17 luminance levels in 6 pt). The bar's background
//    is hidden instead, the art runs to the top of the sheet the way the original's did, and the
//    only thing over it is `Done` in its own glass capsule. There is no title to ghost under,
//    because the account name IS the title.
//  • Every row carried a 28-pt tinted tile: amber for Sync, amber for Haptics, blue for
//    Notifications, grey for About. Four decorative colours, two of them accent, on a screen whose
//    only real accent belongs to Done. The tiles are gone; the glyph column is one monochrome ramp
//    and colour appears only where it carries state (a warning) or selection (the toggle).
//  • The Sync row wore a chevron, which promises a push and delivers a refresh. The leading glyph
//    now reports the state (a bare `checkmark` when settled) and the trailing control is the verb —
//    `arrow.clockwise` in a 44-pt target, or a spinner while the check is in flight.
//  • Section labels sat at gutter + 16, aligned to nothing. They align to the 16-pt gutter now, so
//    the labels, the plates and the identity all share one left rail.
//  • "Sign out" was a floating red word under 300 pt of void. It is a row in its own plate.
//  • The About group was a list row with a film glyph and a three-line wrapping subtitle. It is
//    fine print, so it is set as fine print, under the wordmark that ends the screen.
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

    private var now: Int64 { appModel.now }
    private var sync: SyncCenter { SyncCenter.shared }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                // The account's own library warms the top of the modal — the one thing the
                // original profile had that the rebuild dropped. Full bleed under the bar, at full
                // strength where it starts, decaying to canvas on its own ramp: a wash that is
                // strongest at an edge it shares with nothing can never seam. `intensity` is the
                // list-screen value, not the hero's: at 1 the blurred poster lit the left third to
                // rgb(92,90,94) and the right to rgb(38,42,50), which reads as a stain rather than
                // as atmosphere.
                ArtBackdrop(url: washArtwork, tint: washTint, height: 360, intensity: 0.62)
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
                    .padding(.top, ThemeSpace.x4)
                    .padding(.bottom, ThemeSpace.x8)
                }
                .scrollIndicators(.hidden)
                // The screen has no navigation bar to hide behind, so scrolling content is
                // dissolved instead of cut: without this the account name slides up and prints
                // itself across the `Done` capsule. The wash is OUTSIDE this mask, so the
                // atmosphere at the top of the sheet is untouched by it.
                .mask(
                    VStack(spacing: 0) {
                        LinearGradient(stops: [
                            .init(color: .clear, location: 0.00),
                            .init(color: .black.opacity(0.10), location: 0.62),
                            .init(color: .black, location: 1.00),
                        ], startPoint: .top, endPoint: .bottom)
                        .frame(height: 84)
                        Rectangle().fill(.black)
                    }
                    .ignoresSafeArea(edges: .top)
                )
            }
            .background(ThemeColor.canvas.ignoresSafeArea())
            .task { washTint = await PaletteCache.shared.resolve(url: washArtwork, maxPixel: 320) }
            .navigationBarTitleDisplayMode(.inline)
            // No title, no bar background: the identity block is this screen's header, and a
            // second one printed 40 pt above it in a grey band is the "empty header row" defect
            // wearing a different hat. Done keeps the system's glass capsule, so content that
            // scrolls behind it stays legible without a bar to slide under.
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(Copy.Action.done) { dismiss() }.fontWeight(.semibold)
                }
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

    /// 84 pt, lit along its top edge like every other object in this app: tone and light, not an
    /// outline. The monogram when there is a name to take one from, the app's own mark when the
    /// account has no name — never a stock `person` glyph, and never "YA" scraped off a label.
    ///
    /// The disc is NEUTRAL. An accent-filled avatar is a fifth amber object on a screen whose one
    /// primary action is `Done`, and rule 7 gives accent to actions, forward facts, selection and
    /// links — not to decoration. What separates it from the wash is LIGHT: `controlSheen` poured
    /// down its dome, dead by the centre, exactly as a filled control is lit. Measured on the
    /// previous iteration, a plain `surfaceFloating` disc sat at rgb(32,34,42) inside a wash at
    /// rgb(48,56,65) — darker than its own ground, which is a hole, not an avatar.
    private var avatar: some View {
        ZStack {
            Circle().fill(
                LinearGradient(colors: [ThemeColor.surfaceFloating, ThemeColor.surfaceFlat],
                               startPoint: .top, endPoint: .bottom)
            )
            Circle().fill(
                LinearGradient(colors: [ThemeColor.controlSheen, .clear],
                               startPoint: .top, endPoint: .center)
            )
            Circle().strokeBorder(
                LinearGradient(colors: [ThemeColor.controlSheen, .clear], startPoint: .top, endPoint: .center),
                lineWidth: 1
            )
            if hasRealName {
                Text(initial).type(ThemeType.displayL).foregroundStyle(ThemeColor.textPrimary)
            } else {
                // `.none`: at this size the progress slot is a 3-pt black dash across the ribbon,
                // and a smudge is not an identity.
                PreviouslyMark(width: 30, detail: .none)
            }
        }
        .frame(width: 84, height: 84)
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
            ProfileRow(symbol: syncSymbol,
                       symbolTint: syncTint,
                       title: sync.syncedLine(now: now),
                       subtitle: sync.isOnline ? nil : Copy.Notice.noConnection,
                       separator: !sync.failedChanges.isEmpty,
                       action: { Task { await appModel.reload() } }) {
                // The verb, not a chevron: this row refreshes, it does not push.
                Group {
                    if sync.checking {
                        ProgressView().controlSize(.small).tint(ThemeColor.textTertiary)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(ThemeColor.textTertiary)
                    }
                }
                .frame(width: 28, height: 44)
            }
            .accessibilityLabel("\(sync.syncedLine(now: now)). Check for changes")

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

    private var syncSymbol: String {
        if !sync.failedChanges.isEmpty { return "exclamationmark.triangle.fill" }
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
            ShareLink(item: LibraryExport(appModel: appModel, format: .json),
                      preview: SharePreview("Previously library (JSON)")) {
                ProfileRowLabel(symbol: "curlybraces",
                                title: "Export as JSON",
                                subtitle: "Every title with progress and status") { shareGlyph }
            }
            .buttonStyle(GroupedRowPressStyle())

            ShareLink(item: LibraryExport(appModel: appModel, format: .csv),
                      preview: SharePreview("Previously library (CSV)")) {
                ProfileRowLabel(symbol: "tablecells",
                                title: "Export as CSV",
                                subtitle: "One row per season or movie") { shareGlyph }
            }
            .buttonStyle(GroupedRowPressStyle())

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
            }

            ProfileRowLabel(symbol: "hand.tap",
                            title: "Haptics",
                            subtitle: "Confirms marks and milestones",
                            separator: false) {
                // Amber, not system green: a switch reports selection, and selection in this app
                // is one colour. Green here is decoration, and `success` is never decoration.
                Toggle("Haptics", isOn: $hapticsOn).labelsHidden().tint(ThemeColor.accent)
            }
        }
        .onChange(of: hapticsOn) { _, on in
            FeedbackCoordinator.enabled = on
            if on { FeedbackCoordinator.fire(.selection) }
        }
    }

    private var shareGlyph: some View {
        Image(systemName: "square.and.arrow.up")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(ThemeColor.textTertiary)
            .frame(width: 28, height: 44)
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

    // MARK: - Colophon

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
    }

    // MARK: - Helpers

    /// A Clerk user id is not a name: show the account generically rather than an opaque token.
    private var accountName: String {
        if case .dev = auth.mode { return "Your account" }
        let n = auth.displayName.trimmingCharacters(in: .whitespaces)
        return (n.isEmpty || n == "Signed in" || n.hasPrefix("user_")) ? "Your account" : n
    }

    private var hasRealName: Bool { accountName != "Your account" }

    /// The one fact a profile screen exists to answer besides "who": how this device is signed in.
    /// It is deliberately not the sync line — that belongs to Sync, and printing it twice is how
    /// the shipped build ended up with two greys saying the same thing.
    private var provenance: String {
        if case .dev = auth.mode { return "Developer session" }
        return "Signed in with Clerk"
    }

    /// One letter, never two: "YA" scraped off the words "Your account" is not a monogram.
    private var initial: String {
        accountName.first.map { String($0).uppercased() } ?? "•"
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
/// support line, and exactly one trailing control.
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
                        .font(.system(size: 16, weight: .medium))
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
                        .foregroundStyle(ThemeColor.textSecondary)
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
    let title: String
    var subtitle: String? = nil
    var separator = true
    let action: () -> Void
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        Button(action: action) {
            ProfileRowLabel(symbol: symbol, symbolTint: symbolTint, title: title,
                            subtitle: subtitle, separator: separator, trailing: trailing)
        }
        .buttonStyle(GroupedRowPressStyle())
    }
}
