import SwiftUI

// How you appear beside your replies (spec §4.5 step 2, brief §7): a first name and a username the
// person picks. Two readings of one page:
//   • `.firstReply` — the composer's second gate (after the rules). "Continue" saves and goes on to
//     the composer with the draft intact.
//   • `.edit` — Profile's "Name and username". "Save" saves and says so in the lane.
//
// Nothing about the account is published as-is: the name is prefilled ONLY from a real first name
// (`AccountIdentity.provenance == .name`) — never an email, never "Your account" — and the username
// is that name folded to `[a-z0-9_.]` (empty when nothing survives). The username is checked as it
// is typed: the server's own first four rules locally (so a bad character is said at once), then
// availability from the server, 300 ms after the last keystroke.
//
// No NavigationStack of its own: the composer embeds it as a step, Profile pushes it.

struct IdentitySetupView: View {
    enum Mode { case firstReply, edit }

    let mode: Mode
    let onDone: (SocialProfile) -> Void

    @Environment(AppModel.self) private var appModel
    @Environment(AuthManager.self) private var auth
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var name = ""
    @State private var handle = ""
    /// The person typed in the username field: the name stops suggesting one.
    @State private var handleEdited = false
    @State private var seeded = false
    @State private var availability: Availability = .idle
    @State private var nameProblem: String?
    @State private var problem: String?
    @State private var saving = false
    @FocusState private var focus: Field?

    private enum Field: Hashable { case name, handle }

    /// What the server said about the username in the field.
    private enum Availability: Equatable {
        case idle, checking, available, taken, rejected(String)
        /// Profile's edit screen: the username already yours.
        case yours
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ThemeSpace.x5) {
                nameField
                usernameField
                Text(Copy.Social.identityNote)
                    .type(ThemeType.feedSmall)
                    .foregroundStyle(ThemeColor.feedSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let problem {
                    Text(problem)
                        .type(ThemeType.metadata)
                        .foregroundStyle(ThemeColor.destructive)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, ThemeMetrics.gutter)
            .padding(.top, ThemeSpace.x4)
            .padding(.bottom, ThemeSpace.x8)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(ThemeColor.canvas.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) { saveBar }
        .navigationTitle(mode == .firstReply ? Copy.Social.identityTitle : Copy.Social.identityRow)
        .navigationBarTitleDisplayMode(.inline)
        .task { await seed() }
        .task(id: handle) { await checkAvailability() }
        .onChange(of: name) { _, newName in
            nameProblem = Self.localNameIssue(newName).map { Copy.Social.nameRejection($0) }
            // Until the person types a username of their own, it follows the name.
            if seeded, !handleEdited, mode == .firstReply, appModel.socialProfile?.handle == nil {
                handle = Self.suggestedHandle(from: newName)
            }
        }
    }

    // MARK: Fields

    private var nameField: some View {
        VStack(alignment: .leading, spacing: ThemeSpace.x2) {
            Text(Copy.Social.nameLabel)
                .type(ThemeType.feedSmall)
                .foregroundStyle(ThemeColor.feedSecondary)
                .accessibilityHidden(true)
            TextField(Copy.Social.namePlaceholder, text: $name)
                .type(ThemeType.composeField)
                .foregroundStyle(ThemeColor.feedText)
                .textContentType(.givenName)
                .textInputAutocapitalization(.words)
                .submitLabel(.next)
                .focused($focus, equals: .name)
                .onSubmit { focus = .handle }
                .modifier(SocialFieldChrome())
                .accessibilityLabel(Copy.Social.nameLabel)
            if let nameProblem {
                Text(nameProblem)
                    .type(ThemeType.metadata)
                    .foregroundStyle(ThemeColor.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var usernameField: some View {
        VStack(alignment: .leading, spacing: ThemeSpace.x2) {
            Text(Copy.Social.usernameLabel)
                .type(ThemeType.feedSmall)
                .foregroundStyle(ThemeColor.feedSecondary)
                .accessibilityHidden(true)
            HStack(spacing: ThemeSpace.x0_5) {
                Text(Copy.Social.handlePrefix)
                    .type(ThemeType.composeField)
                    .foregroundStyle(ThemeColor.feedSecondary)
                    .accessibilityHidden(true)
                TextField(Copy.Social.usernamePlaceholder, text: handleBinding)
                    .type(ThemeType.composeField)
                    .foregroundStyle(ThemeColor.feedText)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .submitLabel(.done)
                    .focused($focus, equals: .handle)
                    .onSubmit(save)
                    .accessibilityLabel(Copy.Social.usernameLabel)
            }
            .modifier(SocialFieldChrome())
            statusLine
                .animation(ThemeMotion.pick(ThemeMotion.uiGentle, reduceMotion: reduceMotion), value: availability)
        }
    }

    /// Typed input, normalised the server's way (lower case, no leading "@", no spaces).
    private var handleBinding: Binding<String> {
        Binding(get: { handle }, set: { raw in
            handleEdited = true
            handle = Self.normalised(raw)
        })
    }

    /// Under the username: the rules while it is short or empty, the local rule it breaks, then
    /// the server's answer.
    @ViewBuilder
    private var statusLine: some View {
        let local = Self.localHandleIssue(handle)
        if handle.isEmpty || (local == "length" && handle.count < SocialMetrics.handleMin) {
            status(Copy.Social.usernameHelp, ink: ThemeColor.feedSecondary)
        } else if let local {
            status(Copy.Social.handleRejection(local), ink: ThemeColor.destructive, glyph: "xmark.circle.fill")
        } else {
            switch availability {
            case .idle, .yours:
                status(Copy.Social.usernameHelp, ink: ThemeColor.feedSecondary)
            case .checking:
                HStack(spacing: ThemeSpace.x2) {
                    ProgressView().controlSize(.mini).tint(ThemeColor.feedSecondary)
                    Text(Copy.Social.usernameHelp)
                        .type(ThemeType.metadata)
                        .foregroundStyle(ThemeColor.feedSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            case .available:
                status(Copy.Social.usernameAvailable, ink: ThemeColor.success, glyph: "checkmark.circle.fill")
            case .taken:
                status(Copy.Social.usernameTaken, ink: ThemeColor.destructive, glyph: "xmark.circle.fill")
            case .rejected(let reason):
                status(Copy.Social.handleRejection(reason), ink: ThemeColor.destructive, glyph: "xmark.circle.fill")
            }
        }
    }

    private func status(_ text: String, ink: Color, glyph: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: ThemeSpace.x1) {
            if let glyph {
                Image(systemName: glyph).accessibilityHidden(true)
            }
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .type(ThemeType.metadata)
        .foregroundStyle(ink)
        .accessibilityElement(children: .combine)
    }

    // MARK: Save

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canSave: Bool {
        guard !saving, !trimmedName.isEmpty, Self.localNameIssue(name) == nil,
              Self.localHandleIssue(handle) == nil else { return false }
        switch availability {
        case .taken, .rejected: return false
        default: break
        }
        if mode == .edit, let profile = appModel.socialProfile,
           profile.displayName == trimmedName, profile.handle == handle {
            return false            // nothing to save
        }
        return true
    }

    private var saveBar: some View {
        Button(action: save) {
            ZStack {
                Text(mode == .firstReply ? Copy.Social.identityContinue : Copy.Social.identitySave)
                    .opacity(saving ? 0 : 1)
                if saving { ProgressView().tint(ThemeColor.onAccent) }
            }
        }
        .buttonStyle(PrimaryButtonStyle2())
        .disabled(!canSave)
        .accessibilityLabel(mode == .firstReply ? Copy.Social.identityContinue : Copy.Social.identitySave)
        .padding(.horizontal, ThemeMetrics.gutter)
        .padding(.top, ThemeSpace.x3)
        .padding(.bottom, ThemeSpace.x2)
        .frame(maxWidth: .infinity)
        .background { ThemeColor.canvas.ignoresSafeArea(edges: .bottom) }
    }

    private func save() {
        guard canSave else { return }
        saving = true
        problem = nil
        let handle = handle
        let displayName = trimmedName
        Task {
            let result = await appModel.saveIdentity(handle: handle, displayName: displayName)
            saving = false
            let animation = ThemeMotion.pick(ThemeMotion.uiGentle, reduceMotion: reduceMotion)
            switch result {
            case .success(let profile):
                if mode == .edit { appModel.showNotice(Copy.Social.identitySaved) }
                onDone(profile)
            case .failure(.handleTaken):
                withAnimation(animation) { availability = .taken }
                focus = .handle
            case .failure(.invalidHandle(let reason)):
                withAnimation(animation) { availability = .rejected(reason) }
                focus = .handle
            case .failure(.invalidDisplayName(let reason)):
                withAnimation(animation) { nameProblem = Copy.Social.nameRejection(reason) }
                focus = .name
            case .failure(let failure):
                withAnimation(animation) { problem = CommunityRulesSheet.message(for: failure) }
            }
        }
    }

    // MARK: Seeding and checking

    private func seed() async {
        guard !seeded else { return }
        var profile = appModel.socialProfile
        if profile == nil { profile = await appModel.loadSocialProfile() }
        if let known = profile?.displayName, !known.isEmpty {
            name = known
        } else if auth.identity.provenance == .name {
            // A real first name only — never an email, never interface copy.
            name = auth.identity.displayName
        }
        if let known = profile?.handle, !known.isEmpty {
            handle = known
        } else {
            handle = Self.suggestedHandle(from: name)
        }
        nameProblem = Self.localNameIssue(name).map { Copy.Social.nameRejection($0) }
        seeded = true
        // Focus once the presentation has settled (no sleep): the first field still to fill.
        await Task.yield()
        focus = trimmedName.isEmpty ? .name : .handle
    }

    private func checkAvailability() async {
        guard seeded else { return }
        availability = .idle
        let candidate = handle
        guard !candidate.isEmpty, Self.localHandleIssue(candidate) == nil else { return }
        if mode == .edit, candidate == appModel.socialProfile?.handle {
            availability = .yours
            return
        }
        try? await Task.sleep(for: SocialMetrics.handleCheckDelay)
        guard !Task.isCancelled else { return }
        availability = .checking
        let answer = await appModel.checkHandle(candidate)
        guard !Task.isCancelled, candidate == handle else { return }
        guard let answer, answer.handle.lowercased() == candidate else {
            availability = .idle            // the question could not be asked; the save will
            return
        }
        if answer.available {
            availability = .available
        } else if let reason = answer.reason, reason != "taken" {
            availability = .rejected(reason)
        } else {
            availability = .taken
        }
    }

    // MARK: Rules (pure)

    /// The username field's normalisation: the server's `normalizeHandle` (trim, one leading "@",
    /// lower case), plus no whitespace anywhere (a username has none).
    static func normalised(_ raw: String) -> String {
        var s = raw.lowercased().filter { !$0.isWhitespace }
        if s.hasPrefix("@") { s.removeFirst() }
        return s
    }

    /// The server's first four handle rules (server §4.3), in its order, as its reason codes. The
    /// reserved words and the blocklist are the server's alone.
    static func localHandleIssue(_ h: String) -> String? {
        guard !h.isEmpty else { return "length" }
        if h.count < SocialMetrics.handleMin || h.count > SocialMetrics.handleMax { return "length" }
        if !h.unicodeScalars.allSatisfy(isHandleScalar) { return "characters" }
        if h.hasPrefix(".") || h.hasSuffix(".") || h.contains("..") { return "dots" }
        if !h.unicodeScalars.contains(where: { ("a"..."z").contains($0) }) { return "no_letter" }
        return nil
    }

    /// The display name's rules the client can say at once: its length (code points, as the
    /// server counts) and the "@" that marks an email.
    static func localNameIssue(_ raw: String) -> String? {
        let n = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if n.precomposedStringWithCanonicalMapping.unicodeScalars.count > SocialMetrics.nameLimit { return "too_long" }
        if n.contains("@") { return "at_sign" }
        return nil
    }

    /// A first name folded to a username: diacritics dropped, lower case, only `[a-z0-9_.]`, no
    /// dot at either end or twice in a row, at most 20. Empty when nothing survives.
    static func suggestedHandle(from name: String) -> String {
        let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive],
                                  locale: Locale(identifier: "en_US_POSIX")).lowercased()
        var out = String.UnicodeScalarView()
        for scalar in folded.unicodeScalars where isHandleScalar(scalar) {
            if scalar == ".", out.last == "." { continue }
            out.append(scalar)
        }
        var handle = String(out)
        while handle.hasPrefix(".") { handle.removeFirst() }
        handle = String(handle.prefix(SocialMetrics.handleMax))
        while handle.hasSuffix(".") { handle.removeLast() }
        return handle
    }

    private static func isHandleScalar(_ s: Unicode.Scalar) -> Bool {
        ("a"..."z").contains(s) || ("0"..."9").contains(s) || s == "_" || s == "."
    }
}

/// A social form field's ground: the feed's field colour, a 44-pt floor, the compact radius.
struct SocialFieldChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, ThemeSpace.x3)
            .padding(.vertical, ThemeSpace.x2)
            .frame(minHeight: FeedMetrics.actionHitHeight)
            .background(ThemeColor.feedField,
                        in: RoundedRectangle(cornerRadius: ThemeRadius.compactControl, style: .continuous))
    }
}
