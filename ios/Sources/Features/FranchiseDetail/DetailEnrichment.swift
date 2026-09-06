import SwiftUI
import WebKit

// The show page's catalogue shelves — trailers, the people, related titles, where to watch — and
// the in-app trailer sheet. One shelf scaffold (`DetailShelf`) so the four sections share the
// Movies & extras shelf's anatomy exactly: `SectionHeaderRow`, a horizontal scroller that lets
// art run off the trailing edge and never type, the page gutter on the leading side.

// MARK: - Shelf scaffold

struct DetailShelf<Content: View>: View {
    let title: String
    var count: Int? = nil
    var action: (() -> Void)? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: ThemeMetrics.labelGap) {
            SectionHeaderRow(title, count: count, action: action)
            // LAZY (5 Sep): a show page carries up to 13 trailers, 16 people and 12 related
            // titles, and an eager row built every one of them on the push — most of a 400-ms
            // stall on the simulator for cards three screens off to the right.
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: ThemeMetrics.shelfGap) { content() }
                    .padding(.leading, ThemeMetrics.gutter)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            // Art may run off the trailing edge; TYPE may not. See `shelfScroller`.
            .shelfScroller()
            // The section sits inside the page gutter; the shelf runs edge to edge.
            .padding(.horizontal, -ThemeMetrics.gutter)
        }
    }
}

// MARK: - Trailer card

/// A 16:9 still with the one glyph that says "this moves", the video's name beneath and what it
/// is ("Trailer · Season 6") under that — Apple TV's Trailers row, Netflix's Trailers & More.
struct TrailerCard: View {
    let video: FranchiseVideo
    /// The show, so the card's name can drop it ("Game of Thrones | Official Series Trailer").
    var showTitle: String? = nil
    let action: () -> Void

    static let width: CGFloat = 200

    private var name: String { video.title(cleanedFor: showTitle) ?? video.displayTitle }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: ThemeRadius.card, style: .continuous)
        Button(action: action) {
            VStack(alignment: .leading, spacing: ThemeSpace.x2) {
                ZStack {
                    shape.fill(ThemeColor.surfaceRaised)
                    RemoteImageView(url: video.thumbnailURL, contentMode: .fill, maxPixel: 640,
                                    placeholderHidden: true)
                    // The play disc in the scrim's glass, the way the over-art pills are drawn.
                    Image(systemName: "play.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(ThemeColor.textPrimary)
                        .padding(.leading, 2)
                        .frame(width: 40, height: 40)
                        .background(ThemeColor.scrimStrong, in: Circle())
                        .overlay(Circle().strokeBorder(ThemeColor.hairline, lineWidth: 1))
                }
                .frame(width: Self.width, height: (Self.width * 9 / 16).rounded())
                .clipShape(shape)
                .overlay(shape.strokeBorder(ThemeColor.posterEdge, lineWidth: 1))
                .shadow(.art)
                VStack(alignment: .leading, spacing: 2) {
                    // The grid's rule on a shelf whose names are sentences (review i3): two
                    // reserved lines, so every meta line shares a baseline.
                    Text(name)
                        .type(ThemeType.shelfTitle)
                        .foregroundStyle(ThemeColor.textPrimary)
                        .lineLimit(2, reservesSpace: true)
                        .multilineTextAlignment(.leading)
                    // ALWAYS a meta line (review i2): one caption anatomy per shelf — neighbouring
                    // cards were two and three rows tall.
                    Text(Self.meta(video, name: name))
                        .type(ThemeType.shelfCaption)
                        .foregroundStyle(ThemeColor.textSecondary)
                        .lineLimit(1)
                }
                .frame(width: Self.width, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle(radius: ThemeRadius.card))
        .accessibilityElement(children: .combine)
        .accessibilityLabel([name, Self.meta(video, name: name)].joined(separator: ", "))
        .accessibilityHint(Copy.Accessibility.playsTrailerHint)
    }

    /// "Trailer · Season 6": what it is, then the part it belongs to. The kind is dropped when the
    /// title already says it, and the whole line when there is nothing left to add.
    static func meta(_ video: FranchiseVideo, name: String?) -> String {
        let kind = Copy.Video.kind(video.kind)
        // "Official Series Trailer" over "Trailer" said it twice (review i4).
        let saysKind = name?.localizedCaseInsensitiveContains(kind) == true
        let bits = [saysKind ? nil : kind, video.partLabel].compactMap { $0 }
        if !bits.isEmpty { return bits.joined(separator: " \u{00B7} ") }
        return FranchiseVideo.providerName(video.site) ?? kind
    }
}

// MARK: - Person card

/// A disc, a name, a role — centred, the way Apple TV draws its cast. Not a control: there is no
/// person page, so it claims no tap.
struct PersonCard: View {
    let person: CatalogPerson

    static let disc: CGFloat = 72
    static let width: CGFloat = 108

    var body: some View {
        VStack(spacing: ThemeSpace.x2) {
            ZStack {
                Circle().fill(ThemeColor.surfaceRaised)
                if person.image != nil {
                    RemoteImageView(url: person.image, contentMode: .fill, maxPixel: 216,
                                    alignment: .top, placeholderHidden: true)
                } else {
                    Image(systemName: "person.fill")
                        .font(.system(size: 26, weight: .regular))
                        .foregroundStyle(ThemeColor.textTertiary)
                }
            }
            .frame(width: Self.disc, height: Self.disc)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(ThemeColor.posterEdge, lineWidth: 1))
            VStack(spacing: 2) {
                // ONE line each (review i3): Apple TV's cast row. A reserved two-line box gave
                // four of five names a 24-pt hole; a name compresses a step before it ellipsizes.
                // One size for every name on the row (review i5: a long name at 0.85 lifted its
                // own role 7 px off the row); a long name wraps and moves only its role.
                Text(person.name)
                    .type(ThemeType.shelfTitle)
                    .foregroundStyle(ThemeColor.textPrimary)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if let role = person.displayRole {
                    Text(role)
                        .type(ThemeType.shelfCaption)
                        .foregroundStyle(ThemeColor.textSecondary)
                        // One line, a step of scale before the ellipsis.
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .truncationMode(.tail)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(width: Self.width)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Copy.Accessibility.person(person.name, role: person.role))
    }
}

// MARK: - Where to watch

/// The providers' marks in a row under a header that opens the options, and the attribution the
/// provider data requires as a footnote. The marks are not controls: the data carries one link
/// for the whole title and none per provider, so a mark that looked pressable would lie.
struct WatchProvidersRow: View {
    let availability: WatchAvailability
    let open: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ThemeMetrics.labelGap) {
            SectionHeaderRow(Copy.Heading.whereToWatch, action: availability.linkURL == nil ? nil : open)
                .accessibilityHint(availability.linkURL == nil ? "" : Copy.Accessibility.opensStreamingOptionsHint)
            ScrollView(.horizontal) {
                HStack(spacing: ThemeMetrics.shelfGap) {
                    ForEach(availability.providers) { ProviderMark(provider: $0) }
                }
                .padding(.leading, ThemeMetrics.gutter)

            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            .shelfScroller()
            .padding(.horizontal, -ThemeMetrics.gutter)
            Text(Copy.Watch.attribution(availability.attribution))
                .type(ThemeType.caption)
                .foregroundStyle(ThemeColor.textTertiary)
        }
    }
}

/// One provider's mark: its logo on a raised square, or its initials where it has none.
struct ProviderMark: View {
    let provider: WatchProvider

    static let size: CGFloat = 52

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: ThemeRadius.compactControl, style: .continuous)
        ZStack {
            shape.fill(ThemeColor.surfaceRaised)
            if provider.logo != nil {
                RemoteImageView(url: provider.logo, contentMode: .fill, maxPixel: 156, placeholderHidden: true)
            } else {
                Text(initials)
                    .type(ThemeType.metadataEmphasis)
                    .foregroundStyle(ThemeColor.textSecondary)
            }
        }
        .frame(width: Self.size, height: Self.size)
        .clipShape(shape)
        .overlay(shape.strokeBorder(ThemeColor.posterEdge, lineWidth: 1))
        .accessibilityLabel("\(provider.name), \(Copy.Watch.access(provider.access))")
    }

    private var initials: String {
        provider.name.split(separator: " ").prefix(2).compactMap { $0.first.map(String.init) }.joined().uppercased()
    }
}

// MARK: - The trailer stage

/// A trailer is a STAGE, not a sheet: the show's art blurred and slowly breathing across the whole
/// screen, a glow in the show's colour around the picture, the show's name in the billboard's
/// lockup, and the tapped card zooming into all of it (`navigationTransition(.zoom)`). The picture
/// is the trailer's still at the width of the screen with the provider's page over it; its video
/// is NOT allowed inline, so the moment it starts the system presents its own full-screen player
/// (transport controls, scrubbing, rotation, AirPlay), and leaving that player dismisses the stage.
/// The 3 Sep sheet — a small embed at the top of a black sheet with nothing under it — was "utter
/// trash"; the first black cover was "better but not quite there"; "it has to feel surreal
/// according to 2026 standards. Immersive… absolute bliss to watch" (user, 4 Sep).
struct VideoSheet: View {
    let video: FranchiseVideo
    let showTitle: String
    /// The show's landscape art (else its poster): the ambient stage behind the picture.
    var ambientArt: String? = nil
    /// The show's colour: the glow around the picture.
    var tint: Color? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The ambient art is lit a beat after the zoom lands, so the stage lights up around the
    /// picture rather than arriving with it.
    @State private var lit = false
    /// The art breathes: one transform on one blurred layer, 20 s out and back.
    @State private var drifting = false
    /// The system player has taken over at least once.
    @State private var enteredFullscreen = false
    /// The provider's own inline player, shown only if the system player has NOT taken over
    /// within a few seconds (autoplay refused, no network): until then the trailer's still covers
    /// the page, so its loading chrome — a channel avatar, a title bar, a spinner, a logo — is
    /// never on the stage (it was, for five seconds, in the first cut).
    @State private var revealPlayer = false
    /// The provider's page is loading behind the still: the play disc becomes a spinner.
    @State private var loadingPlayer = false
    /// The words arrive on the app's settle spring as the zoom lands; only the picture blooms
    /// slowly (review i2: the lockup was the last thing on a stage that exists for it).
    @State private var copyLit = false

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            ambient
            VStack(alignment: .leading, spacing: 0) {
                // The lockup and the picture are ONE composition, a fixed x8 apart, floated to
                // the screen's centre: with the picture pinned high the lower half was void
                // (review, 5 Sep). Equal spacers above and below; the controls stay in the bar.
                Spacer(minLength: 64)
                lockup
                    .padding(.horizontal, ThemeMetrics.gutter)
                Spacer().frame(height: ThemeSpace.x8)
                player
                    .padding(.horizontal, ThemeSpace.x2)
                    // The glow: the show's colour, twice — a tight halo and a wide bloom.
                    .shadow(color: glow.opacity(0.55), radius: 36, y: 8)
                    .shadow(color: glow.opacity(0.30), radius: 110)
                Spacer(minLength: 64)
            }
            controls
        }
        .preferredColorScheme(.dark)
        // The system player may rotate while the stage is up; the app stays portrait otherwise.
        .onAppear { OrientationGate.set(allowsLandscape: true) }
        .onDisappear { OrientationGate.set(allowsLandscape: false) }
        .task {
            if reduceMotion {
                lit = true
                copyLit = true
            } else {
                try? await Task.sleep(for: .milliseconds(60))
                guard !Task.isCancelled else { return }
                withAnimation(ThemeMotion.uiSettle) { copyLit = true }
                withAnimation(.easeOut(duration: 0.9)) { lit = true }
                withAnimation(.easeInOut(duration: 20).repeatForever(autoreverses: true)) { drifting = true }
            }
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled, !enteredFullscreen else { return }
            withAnimation(ThemeMotion.pick(ThemeMotion.uiGentle, reduceMotion: reduceMotion)) { loadingPlayer = true }
            try? await Task.sleep(for: .milliseconds(4100))
            guard !Task.isCancelled, !enteredFullscreen else { return }
            withAnimation(ThemeMotion.pick(ThemeMotion.uiGentle, reduceMotion: reduceMotion)) { revealPlayer = true }
        }
    }

    private var glow: Color { tint ?? ThemeColor.textPrimary }

    /// OKLab lightness of the show's colour under 0.34 — the same threshold Detail's bloom uses.
    private var artIsDark: Bool {
        guard let tint else { return false }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(tint).getRed(&r, green: &g, blue: &b, alpha: &a) else { return false }
        return PaletteCache.oklab(r: Double(r), g: Double(g), b: Double(b)).0 < 0.34
    }

    /// The show's art across the whole screen, blurred to light, dimmed to a stage, breathing.
    private var ambient: some View {
        GeometryReader { geo in
            // Lit, not buried: at 0.42 + a 0.10/0.20 middle the "ambient art" photographed as
            // black with a warm rim (review, 5 Sep).
            // Exposure follows the palette (review i3): a dark key art — Thrones, Wednesday —
            // under the same dimming was a black room; Music's player lifts dark covers so
            // they glow too.
            // The blur AND the lift are baked into one small bitmap (`BlurredArt`): a `.blur`
            // with `.saturation` and `.brightness` on a breathing layer was three filter passes
            // over the whole screen on every frame of the 20-second breath.
            // A floor, not a nudge (review i5: on Thrones the ambient measured 3 % above
            // the canvas — a black room). Dark art is lifted hard and never veiled; a pool
            // of the show's own hue is added with light, so a dark palette still has a lit room.
            BlurredArt(url: ambientArt ?? video.thumbnailURL, sourceMaxPixel: 720, fraction: 0.11,
                       saturation: artIsDark ? 1.6 : 1.0, brightness: artIsDark ? 0.24 : 0)
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
                .scaleEffect(drifting ? 1.22 : 1.10)
                .overlay(
                    Rectangle()
                        .fill(RadialGradient(colors: [(DetailTint.chrome(tint ?? glow) ?? glow).opacity(0.35), .clear],
                                             center: .center, startRadius: 0, endRadius: geo.size.width * 0.9))
                        .blendMode(.plusLighter)
                )
                .overlay(Color.black.opacity(artIsDark ? 0 : 0.22))
                .overlay(LinearGradient(stops: [
                    .init(color: .black.opacity(0.50), location: 0),
                    .init(color: .black.opacity(0.0), location: 0.42),
                    .init(color: .black.opacity(0.08), location: 0.62),
                    .init(color: .black.opacity(0.62), location: 1),
                ], startPoint: .top, endPoint: .bottom))
                .opacity(lit ? 1 : 0)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The billboard's lockup: what it is as the badge, the show as the title, the video's own
    /// name and its season as one line.
    private var lockup: some View {
        VStack(alignment: .leading, spacing: ThemeSpace.x2) {
            HeroBadge(text: Copy.Video.kind(video.kind))
            if !showTitle.isEmpty {
                Text(showTitle)
                    .type(ThemeType.displayXL)
                    .foregroundStyle(ThemeColor.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let line = subline {
                Text(line)
                    .type(ThemeType.heroMeta)
                    .foregroundStyle(ThemeColor.textSecondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(copyLit ? 1 : 0)
    }

    /// "Official Trailer · Season 4" — the video's own name where it adds to the badge, then the
    /// season it belongs to.
    private var subline: String? {
        var bits: [String] = []
        let kind = Copy.Video.kind(video.kind)
        if let t = video.title(cleanedFor: showTitle), t.caseInsensitiveCompare(kind) != .orderedSame { bits.append(t) }
        if let label = video.partLabel { bits.append(label) }
        return bits.isEmpty ? nil : bits.joined(separator: " \u{00B7} ")
    }

    /// The trailer's still at the screen's width — the first frame — with the provider's page
    /// (transparent until it paints) over it; the still alone where the provider cannot be
    /// embedded (the glyph at the top is the way to it then).
    private var player: some View {
        let shape = RoundedRectangle(cornerRadius: ThemeRadius.card, style: .continuous)
        return ZStack {
            Color.black
            if let embed = video.embedURL {
                VideoEmbed(url: embed,
                           onEnterFullscreen: { enteredFullscreen = true },
                           onLeaveFullscreen: { dismiss() })
            }
            // The still ON TOP of the page: the frame is a picture until the system player has
            // it, and only a refused autoplay uncovers the provider's own controls.
            RemoteImageView(url: video.thumbnailURL, contentMode: .fill, maxPixel: 1200, placeholderHidden: true)
                .opacity(revealPlayer ? 0 : 1)
                .allowsHitTesting(!revealPlayer)
            // A player has a play glyph; a picture that is about to become one says so. The
            // card's disc, then a spinner once the page is loading (review, 5 Sep: "a still with
            // no play glyph is not a player" and nothing said anything was happening).
            if !revealPlayer && !enteredFullscreen {
                ZStack {
                    Circle().fill(.ultraThinMaterial)
                    Circle().strokeBorder(ThemeColor.hairline, lineWidth: 1)
                    if loadingPlayer {
                        ProgressView().controlSize(.regular).tint(ThemeColor.textPrimary)
                    } else {
                        Image(systemName: "play.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(ThemeColor.textPrimary)
                            .offset(x: 2)
                    }
                }
                .frame(width: 56, height: 56)
                .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
                .transition(.opacity)
                .allowsHitTesting(false)
            }
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(shape)
        .overlay(shape.strokeBorder(ThemeColor.posterEdge, lineWidth: 1))
    }

    private var controls: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(ThemeColor.textPrimary)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .chromeGlass(in: Circle(), interactive: true)
            .accessibilityLabel(Copy.Action.done)
            Spacer()
            if let url = video.watchURL {
                Button { openURL(url) } label: {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(ThemeColor.interactive)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .chromeGlass(in: Circle(), interactive: true)
                .accessibilityLabel(video.youtubeID != nil ? Copy.Action.openOnYouTube : Copy.Action.openInBrowser)
            }
        }
        .padding(.horizontal, ThemeSpace.x3)
        .padding(.top, ThemeSpace.x2)
    }
}

/// The provider's own embedded player, autoplaying, with nothing of the page around it scrollable.
/// Built once per cover — a new video is a new cover — so nothing reloads.
///
/// Inline playback is OFF: the system presents its native full-screen player the moment the video
/// starts, and `fullscreenState` (KVO, iOS 16) reports when the viewer leaves it — the cover goes
/// with it (`onLeaveFullscreen`).
///
/// The player is an `<iframe>` in a page of our own with a base URL, not the embed URL loaded
/// bare: YouTube refuses an embed that arrives with no referring origin ("Video player
/// configuration error", captured 3 Sep), and it refuses one that claims to BE youtube.com
/// ("This video is unavailable · 152-4", the next capture). A neutral origin of our own is what
/// a page embedding a video looks like from the provider's side.
private struct VideoEmbed: UIViewRepresentable {
    let url: URL
    /// Called when the system's full-screen player takes over.
    var onEnterFullscreen: () -> Void = {}
    /// Called once the viewer leaves the system's full-screen player.
    var onLeaveFullscreen: () -> Void = {}

    /// Touched on the main thread only — WebKit posts `fullscreenState` there, and the handler
    /// hops to the main actor before reading it — hence `@unchecked Sendable`, so the KVO closure
    /// may hold it under strict concurrency.
    final class Coordinator: @unchecked Sendable {
        var observation: NSKeyValueObservation?
        var wasFullscreen = false
        var onEnter: () -> Void = {}
        var onLeave: () -> Void = {}
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // NOT inline: playback goes straight to the system's full-screen player.
        config.allowsInlineMediaPlayback = false
        config.mediaTypesRequiringUserActionForPlayback = []
        let view = WKWebView(frame: .zero, configuration: config)
        // Transparent, so the trailer's still under it holds the frame until the page paints.
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.isScrollEnabled = false
        view.scrollView.backgroundColor = .clear
        let coordinator = context.coordinator
        coordinator.onEnter = onEnterFullscreen
        coordinator.onLeave = onLeaveFullscreen
        coordinator.observation = view.observe(\.fullscreenState, options: [.new]) { [weak coordinator] view, _ in
            let state = view.fullscreenState
            Task { @MainActor in
                guard let coordinator else { return }
                switch state {
                case .inFullscreen:
                    if !coordinator.wasFullscreen { coordinator.onEnter() }
                    coordinator.wasFullscreen = true
                case .notInFullscreen where coordinator.wasFullscreen:
                    coordinator.wasFullscreen = false
                    coordinator.onLeave()
                default:
                    break
                }
            }
        }
        view.loadHTMLString(Self.page(for: url), baseURL: Self.origin)
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        context.coordinator.onEnter = onEnterFullscreen
        context.coordinator.onLeave = onLeaveFullscreen
    }

    /// The page's own origin — the referrer the provider sees.
    private static let origin = URL(string: "https://previously.local/trailer")

    /// A transparent page with the player filling it edge to edge (the still shows through until
    /// the provider paints).
    private static func page(for url: URL) -> String {
        """
        <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
        <style>html,body{margin:0;padding:0;background:transparent;height:100%;overflow:hidden}iframe{position:absolute;inset:0;width:100%;height:100%;border:0;background:transparent}</style></head>
        <body><iframe src="\(url.absoluteString)" referrerpolicy="strict-origin-when-cross-origin" allow="autoplay; encrypted-media; picture-in-picture; fullscreen" allowfullscreen allowtransparency="true"></iframe></body></html>
        """
    }
}
