import SwiftUI
import UIKit

// The feed's shared parts (WP3's feed, WP4's stories, WP5's social surfaces): the show as an
// ACCOUNT (its avatar), a person's monogram disc, the gold mark, X's like with its burst,
// Instagram's double-tap heart, the gel spark a mark throws, the press styles, and the chained
// picture a trailer still is drawn with.
//
// Every effect here is one the references already taught people — X's like burst, Instagram's
// double-tap heart — so none of it has to be learned. Each plays once per act, is over in well
// under a second, and under Reduce Motion collapses to the state change alone. No effect fires a
// haptic: a haptic is a signature for a WRITE, and the model that makes the write signs it.

// MARK: - Rings and avatars

/// A story ring's state around an avatar.
enum FeedRing: Equatable {
    case none, unseen, seen, loading
}

/// A show as an account in a circle — the stories tray, the new-posts pill, the viewer's header —
/// cropped on its SUBJECT (`SubjectCropImage`), never on the logotype a poster prints at its top
/// or foot.
struct FeedAvatar: View {
    let candidates: [String]
    let size: CGFloat
    /// Instagram's unseen ring, in the icon's five gels.
    let ring: FeedRing

    init(candidates: [String], size: CGFloat = FeedMetrics.avatar, ring: FeedRing = .none) {
        self.candidates = candidates
        self.size = size
        self.ring = ring
    }

    @State private var spin = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            switch ring {
            case .none:
                EmptyView()
            case .unseen:
                Circle().strokeBorder(ThemeGel.ring, lineWidth: ringWidth)
            case .loading:
                // Instagram's wait: the ring breaks into dashes and turns until the story is in.
                // Under Reduce Motion the dashes hold still — the break alone says "loading".
                Circle()
                    .strokeBorder(ThemeGel.ring, style: StrokeStyle(lineWidth: ringWidth, lineCap: .round,
                                                                   dash: [ringWidth * 2.6, ringWidth * 1.9]))
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .onAppear {
                        guard !reduceMotion else { return }
                        withAnimation(ThemeMotion.feedRingSpin) { spin = true }
                    }
                    .onDisappear { spin = false }
            case .seen:
                Circle().strokeBorder(ThemeColor.storyRingSeen, lineWidth: 1)
            }
            SubjectCropImage(urls: candidates)
                .frame(width: max(0, size - inset * 2), height: max(0, size - inset * 2))
                .clipShape(Circle())
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    /// Instagram's proportions, measured at 92 pt (25 Sep): a 3.4-pt stroke and a 2.4-pt gap, so
    /// the photo is 80 pt — the face fills the ring, the ring is a line around it.
    nonisolated static func ringWidth(_ size: CGFloat) -> CGFloat { max(2, size * 0.037) }
    nonisolated static func ringGap(_ size: CGFloat) -> CGFloat { max(2, size * 0.026) }
    /// Where the photo sits inside a ringed avatar of `size`.
    nonisolated static func photoInset(ringed size: CGFloat) -> CGFloat { ringWidth(size) + ringGap(size) }

    private var ringWidth: CGFloat { Self.ringWidth(size) }
    private var inset: CGFloat {
        switch ring {
        case .none: 0
        case .unseen, .seen, .loading: Self.photoInset(ringed: size)
        }
    }

    /// Every picture worth trying for a show's avatar, best first: the textless poster, the TRUE
    /// landscapes (never an AniList banner — a 4.75:1 strip has no face to find), the poster.
    /// `SubjectCrop` takes the first with a face. Pure (`nonisolated`), so model code may call it.
    nonisolated static func candidates(_ f: Franchise) -> [String] {
        var out: [String] = []
        func add(_ url: String?) {
            if let url, !url.isEmpty, !out.contains(url) { out.append(url) }
        }
        add(f.textlessPortrait)
        let wides = [f.landscapeArt] + (f.artwork?.landscapes ?? []).map(\.url)
        for wide in wides where !(wide ?? "").contains("/anime/banner/") { add(wide) }
        add(f.portraitArt)
        return out
    }
}

/// A picture shown as the square around its subject (`SubjectCrop`), filling its frame. A placeholder
/// of `ThemeColor.surfaceRaised` until the crop is ready; a crop made earlier this session is on
/// screen from the first frame.
struct SubjectCropImage: View {
    let urls: [String]
    @State private var image: UIImage?
    @State private var shownKey: String?

    init(urls: [String]) {
        self.urls = urls
        let hit = SubjectCrop.cachedCrop(for: urls)
        _image = State(initialValue: hit)
        _shownKey = State(initialValue: hit == nil ? nil : SubjectCrop.key(urls))
    }

    var body: some View {
        // A colour as the sizing box: an `Image` would report its pixel size as its ideal size.
        ThemeColor.surfaceRaised
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                        .transition(.opacity)
                }
            }
            .clipped()
            .task(id: urls) { await load() }
    }

    private func load() async {
        guard !urls.isEmpty else {
            image = nil
            shownKey = nil
            return
        }
        let key = SubjectCrop.key(urls)
        if image != nil, shownKey == key { return }
        if let hit = SubjectCrop.cachedCrop(for: urls) {
            image = hit
            shownKey = key
            return
        }
        if shownKey != key {
            // A different show on a reused view: never leave the last one's face up.
            image = nil
            shownKey = nil
        }
        let out = await SubjectCrop.shared.crop(for: urls)
        guard !Task.isCancelled, let out else { return }
        withAnimation(ThemeMotion.uiPoster) { image = out }
        shownKey = key
    }
}

/// A show as an account in a ROW: X's organisation avatar — a rounded square — cropped on its
/// subject, with a hairline edge.
struct ShowAvatar: View {
    let candidates: [String]
    let size: CGFloat

    init(franchise: Franchise, size: CGFloat = FeedMetrics.avatar) {
        self.init(candidates: FeedAvatar.candidates(franchise), size: size)
    }

    /// For a surface that keeps the candidates rather than the show (a story reel whose show has
    /// left the library still draws the frame it is on).
    init(candidates: [String], size: CGFloat = FeedMetrics.avatar) {
        self.candidates = candidates
        self.size = size
    }

    /// Organisations (shows) wear rounded squares; people wear circles — X's own distinction.
    nonisolated static func shape(_ size: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: size * FeedMetrics.showCornerRatio, style: .continuous)
    }

    var body: some View {
        let shape = Self.shape(size)
        SubjectCropImage(urls: candidates)
            .frame(width: size, height: size)
            .clipShape(shape)
            .overlay(shape.strokeBorder(ThemeColor.avatarEdge, lineWidth: FeedMetrics.hairline))
            .accessibilityHidden(true)
    }
}

/// A person's face: their monogram on their gel (`ThemeGel.color(forUserId:)`). No uploaded
/// pictures. The viewer's own disc stays `AccountDisc`.
struct PersonDisc: View {
    let monogram: String?
    let userId: String
    let size: CGFloat

    init(user: PublicUser, size: CGFloat = FeedMetrics.personDisc) {
        self.init(monogram: user.monogram, userId: user.id, size: size)
    }

    init(monogram: String?, userId: String, size: CGFloat = FeedMetrics.personDisc) {
        self.monogram = monogram
        self.userId = userId
        self.size = size
    }

    var body: some View {
        ZStack {
            Circle().fill(ThemeGel.color(forUserId: userId).gradient)
            if let letter = letter {
                Text(letter)
                    .type(ThemeType.discMonogram(diameter: size))
                    .foregroundStyle(ThemeColor.onAccent)
                    .lineLimit(1)
                    // The disc is a fixed size and so is the letter (`discMonogram` is set at a
                    // fixed ≈ 0.42 × the disc, as `AccountDisc`'s is); the floor only catches a
                    // wide glyph.
                    .minimumScaleFactor(0.6)
                    .padding(size * 0.1)
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.44, weight: .semibold))
                    .foregroundStyle(ThemeColor.onAccent)
            }
        }
        .frame(width: size, height: size)
        .overlay(Circle().strokeBorder(ThemeColor.discEdge, lineWidth: FeedMetrics.hairline))
        .accessibilityHidden(true)
    }

    private var letter: String? {
        guard let first = monogram?.trimmingCharacters(in: .whitespacesAndNewlines).first else { return nil }
        return String(first).uppercased()
    }
}

/// A picture filled into a frame, its crop centred `focus` of the way down (a 2:3 poster's faces sit
/// around a third of the way down, its logotype at the top or the foot).
struct FeedFaceCrop: View {
    let url: String?
    var focus: CGFloat = 0.36
    var aspect: CGFloat = 2.0 / 3.0
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let tall = max(g.size.height, w / max(aspect, 0.01))
            ZStack(alignment: .top) {
                ThemeColor.surfaceRaised
                RemoteImageView(url: url, contentMode: .fill, maxPixel: max(w, tall) * displayScale,
                                alignment: .top, placeholderHidden: true)
                    .frame(width: w, height: tall)
                    .offset(y: -(tall - g.size.height) * focus)
            }
            .frame(width: w, height: g.size.height, alignment: .top)
            .clipped()
        }
    }
}

// MARK: - The mark and the count

/// X's gold organisation check — here, "from the studio or network". Amber is the app's gold, and
/// here it is a STATE (official), never an action. Callers draw it only for an official lead
/// source (`isOfficial`); a trade-press post has no mark, a rumour carries a note instead.
struct ConfirmedMark: View {
    let size: CGFloat

    init(size: CGFloat = 16) { self.size = size }

    var body: some View {
        Image(systemName: "checkmark.seal.fill")
            .font(.system(size: size))
            .symbolRenderingMode(.palette)
            .foregroundStyle(ThemeColor.onAccent, ThemeColor.accent)
            .accessibilityLabel(Copy.Feed.officialSource)
    }
}

enum FeedCount {
    /// X's compact numerals: 7, 482, 1.2K, 13K.
    static func text(_ n: Int) -> String {
        n < 1000 ? "\(n)" : n.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)))
    }
}

// MARK: - The like

/// X's like, measured off a screen recording: the outline heart collapses, fills pink, springs past
/// its size and settles, while a ring of dots bursts out of it and is gone in under half a second.
/// Only a like plays it — an unlike just empties the heart — and under Reduce Motion neither the
/// spring nor the burst plays.
struct LikeGlyph: View {
    let liked: Bool
    let size: CGFloat
    let idle: Color

    init(liked: Bool, size: CGFloat = FeedMetrics.actionGlyph, idle: Color = ThemeColor.feedSecondary) {
        self.liked = liked
        self.size = size
        self.idle = idle
    }

    @State private var burst = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: liked ? "heart.fill" : "heart")
            .font(.system(size: size))
            .foregroundStyle(liked ? ThemeColor.like : idle)
            // A keyframe animator is right HERE because its content is the glyph itself; the
            // dots below cannot use one (see `BurstRing`).
            .keyframeAnimator(initialValue: 1.0, trigger: burst) { view, scale in
                view.scaleEffect(scale)
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(0.62, duration: 0.07)
                    SpringKeyframe(1.26, duration: 0.15, spring: .snappy)
                    SpringKeyframe(1.0, duration: 0.34, spring: .bouncy)
                }
            }
            .background {
                if !reduceMotion {
                    BurstRing(trigger: burst, radius: size * 1.05, dot: max(3, size * 0.2))
                }
            }
            .onChange(of: liked) { was, now in
                if now, !was, !reduceMotion { burst += 1 }
            }
    }
}

/// The dots a like throws off: seven, the like's pink alternating with the gels' coral, out from the
/// glyph's centre, shrinking as they go.
///
/// Plain state animated with `withAnimation`, NOT a keyframe animator: an animator whose content is
/// an empty clear view is not redrawn per frame (filmed at 60 fps — the dots showed for one frame,
/// then parked at the first keyframe's value after every like). The dots exist only while they fly.
struct BurstRing: View {
    let trigger: Int
    var radius: CGFloat = 18
    var dot: CGFloat = 3.5
    var count = 7
    var colors: [Color] = [ThemeColor.like, ThemeGel.coral]
    var duration: Double = 0.45
    @State private var phase = FeedBurst.Phase()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if phase.on, !colors.isEmpty {
                ForEach(0..<count, id: \.self) { i in
                    let a = Double(i) / Double(max(count, 1)) * 2 * .pi - .pi / 2
                    let r = radius * (0.35 + 0.85 * phase.t)
                    Circle()
                        .fill(colors[i % colors.count])
                        .frame(width: dot, height: dot)
                        .scaleEffect(max(0.01, 1 - phase.t * 1.05))
                        .offset(x: cos(a) * r, y: sin(a) * r)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: trigger) {
            guard !reduceMotion else { return }
            FeedBurst.play($phase, duration: duration)
        }
    }
}

/// The one clock the bursts run on.
enum FeedBurst {
    /// `t` runs 0 → 1 across one burst; `on` mounts the pieces only while they fly; `run` makes a
    /// second burst started mid-flight the one whose end hides them.
    struct Phase: Equatable, Sendable {
        var t: CGFloat = 0
        var on = false
        var run = 0
    }

    /// Reset without animation, then run 0 → 1 on the next main-actor turn (so the reset is
    /// committed first), then hide — unless another burst has started since.
    @MainActor
    static func play(_ phase: Binding<Phase>, duration: Double) {
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) {
            phase.wrappedValue.t = 0
            phase.wrappedValue.on = true
            phase.wrappedValue.run += 1
        }
        let run = phase.wrappedValue.run
        Task { @MainActor in
            withAnimation(.easeOut(duration: duration)) {
                phase.wrappedValue.t = 1
            } completion: {
                guard phase.wrappedValue.run == run else { return }
                var hide = Transaction()
                hide.disablesAnimations = true
                withTransaction(hide) {
                    phase.wrappedValue.on = false
                    phase.wrappedValue.t = 0
                }
            }
        }
    }
}

/// Instagram's double-tap heart: white over the picture, springing up past its size, holding a beat,
/// then lifting away. Nothing under Reduce Motion (the like itself still lands).
struct BigHeartPop: View {
    let trigger: Int
    var size: CGFloat = 86
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Pop {
        var scale = 0.2
        var y = 0.0
        var opacity = 0.0
    }

    var body: some View {
        if !reduceMotion {
            Image(systemName: "heart.fill")
                .font(.system(size: size))
                .foregroundStyle(ThemeColor.likeOverArt)
                .shadow(.likeOverArt)
                .keyframeAnimator(initialValue: Pop(), trigger: trigger) { view, v in
                    view.scaleEffect(v.scale).offset(y: v.y).opacity(v.opacity)
                } keyframes: { _ in
                    // Every track opens on an invisible keyframe and closes on one: an animator at
                    // rest holds its first keyframe, so the heart must be gone there too.
                    KeyframeTrack(\.opacity) {
                        LinearKeyframe(0, duration: 0.001)
                        LinearKeyframe(1, duration: 0.06)
                        LinearKeyframe(1, duration: 0.52)
                        LinearKeyframe(0, duration: 0.2)
                    }
                    KeyframeTrack(\.scale) {
                        LinearKeyframe(0.2, duration: 0.001)
                        SpringKeyframe(1.12, duration: 0.2, spring: .bouncy)
                        SpringKeyframe(0.94, duration: 0.12)
                        SpringKeyframe(1.0, duration: 0.26)
                        LinearKeyframe(1.0, duration: 0.2)
                    }
                    KeyframeTrack(\.y) {
                        LinearKeyframe(0, duration: 0.58)
                        CubicKeyframe(-54, duration: 0.2)
                        LinearKeyframe(0, duration: 0.001)
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

/// The mark's moment: a small spark of the icon's five gels thrown out of the button — the Align
/// film's colours, once, for the moment an episode becomes something you can talk about. A spark,
/// not confetti: sixteen pieces, 0.7 s, gone before the room opens. Nothing under Reduce Motion.
struct GelSpark: View {
    let trigger: Int
    var count = 16
    /// How far the pieces fly, across and up/down — sized to clear what they burst from.
    var reachX: CGFloat = 92
    var reachY: CGFloat = 57
    var duration: Double = 0.7
    @State private var phase = FeedBurst.Phase()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if phase.on {
                ForEach(0..<count, id: \.self) { i in
                    let t = phase.t
                    let seed = Double((i * 73) % 97) / 97
                    let a = Double(i) / Double(max(count, 1)) * 2 * .pi + seed * 0.4
                    let k = (0.55 + 0.45 * seed) * t
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(ThemeGel.all[i % ThemeGel.all.count])
                        .frame(width: 5, height: i % 3 == 0 ? 5 : 9)
                        .rotationEffect(.degrees(Double(i) * 37 + t * 220 * (i % 2 == 0 ? 1 : -1)))
                        .scaleEffect(max(0.01, 1 - t * 0.7))
                        .offset(x: cos(a) * reachX * k, y: sin(a) * reachY * k + 18 * t)
                        .opacity(Double(1 - t * 0.9))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: trigger) {
            guard !reduceMotion else { return }
            FeedBurst.play($phase, duration: duration)
        }
    }
}

// MARK: - Presses

/// X's row press: the row's ground lifts a shade while the finger is down — no scale — and fades on
/// release. Only the ground animates; nothing inside the row rides the press's transaction.
struct FeedRowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                ThemeColor.feedPressed
                    .opacity(configuration.isPressed ? 1 : 0)
                    .animation(configuration.isPressed ? nil : ThemeMotion.feedPressRelease,
                               value: configuration.isPressed)
            }
    }
}

/// An icon's press on the action bar: a quick dip, back on release. Under Reduce Motion the dip is
/// a dim instead of a scale.
struct FeedIconPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        // Only the dip animates: a scoped animation, so a count or a fill changing inside the
        // label on the same release does not ride the press's spring.
        return configuration.label
            .animation(ThemeMotion.pick(ThemeMotion.uiMicro, reduceMotion: reduceMotion)) { label in
                label
                    .scaleEffect(!reduceMotion && pressed ? FeedMetrics.iconPressScale : 1)
                    .opacity(reduceMotion && pressed ? 0.6 : 1)
            }
    }
}

/// A story bubble's press: the ring and name dip together. Under Reduce Motion, a dim.
struct StoryBubblePressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .animation(ThemeMotion.pick(ThemeMotion.uiMicro, reduceMotion: reduceMotion)) { label in
                label
                    .scaleEffect(!reduceMotion && pressed ? FeedMetrics.bubblePressScale : 1)
                    .opacity(reduceMotion && pressed ? 0.7 : 1)
            }
    }
}

// MARK: - Chained pictures

/// A trailer's still, best first (iD10): YouTube's 1280-px frame, its 480-px frame, then whatever
/// the catalogue sent. The 1280-px frame 404s to a grey placeholder for some uploads, and the 480-px
/// one is 4:3 with letterbox bars — filled into 16:9 it loses exactly those bars.
enum FeedVideoStill {
    static func candidates(_ v: FranchiseVideo) -> [String] {
        var out: [String] = []
        func add(_ url: String?) {
            if let url, !url.isEmpty, !out.contains(url) { out.append(url) }
        }
        if let id = v.youtubeID, !id.isEmpty {
            add("https://i.ytimg.com/vi/\(id)/maxresdefault.jpg")
            add("https://i.ytimg.com/vi/\(id)/hqdefault.jpg")
        }
        add(v.thumbnailURL)
        return out
    }
}

/// A picture that tries its candidates in order through the one image pipeline
/// (`ImageLoader.shared`): a failed load, or a decode no wider than YouTube's 120-px grey
/// placeholder, moves on to the next. A candidate that answered with an error status is
/// remembered for the session, so a recycled row does not ask for it again; a network failure is
/// not remembered (it may work in a minute).
struct ChainedRemoteImage: View {
    let urls: [String]
    let contentMode: ContentMode
    let maxPixel: CGFloat
    /// Called once a picture is on screen — from the cache on the first frame, or when a load lands.
    let onLoaded: (() -> Void)?

    @State private var image: UIImage?
    @State private var shownURLs: [String]?

    init(urls: [String], contentMode: ContentMode = .fill, maxPixel: CGFloat, onLoaded: (() -> Void)? = nil) {
        self.urls = urls
        self.contentMode = contentMode
        self.maxPixel = maxPixel
        self.onLoaded = onLoaded
        let hit = Self.cachedHit(urls, maxPixel: maxPixel)
        _image = State(initialValue: hit)
        _shownURLs = State(initialValue: hit == nil ? nil : urls)
    }

    var body: some View {
        // A colour as the sizing box (as `CachedAsyncImage`): the picture never sizes its parent.
        Color.clear
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                        .transition(.opacity)
                } else {
                    GradientPlaceholder()
                }
            }
            .clipped()
            .task(id: urls) { await load() }
            .onAppear { if image != nil { onLoaded?() } }
    }

    /// The first candidate that is decoded already — walking past the ones known to have failed,
    /// and stopping at the first one that has never been tried (it must be asked first).
    private static func cachedHit(_ urls: [String], maxPixel: CGFloat) -> UIImage? {
        for string in urls {
            if ChainedImageFailures.contains(string) { continue }
            guard let url = URL(string: string) else { continue }
            if let hit = ImageCache.shared.image(for: url, atLeast: maxPixel), usable(hit, maxPixel: maxPixel) {
                return hit
            }
            return nil
        }
        return nil
    }

    private static func usable(_ image: UIImage, maxPixel: CGFloat) -> Bool {
        // The placeholder test only means something when the request could have been wider.
        maxPixel <= FeedMetrics.stillPlaceholderMaxWidth || image.size.width > FeedMetrics.stillPlaceholderMaxWidth
    }

    private func load() async {
        if image != nil, shownURLs == urls { return }
        if let hit = Self.cachedHit(urls, maxPixel: maxPixel) {
            image = hit
            shownURLs = urls
            onLoaded?()
            return
        }
        if shownURLs != urls {
            image = nil
            shownURLs = nil
        }
        for string in urls where !ChainedImageFailures.contains(string) {
            guard let url = URL(string: string) else { continue }
            do {
                let loaded = try await ImageLoader.shared.image(for: url, maxPixel: maxPixel)
                if Task.isCancelled { return }
                guard Self.usable(loaded, maxPixel: maxPixel) else {
                    ChainedImageFailures.insert(string)
                    continue
                }
                withAnimation(ThemeMotion.uiGentle, completionCriteria: .logicallyComplete) {
                    image = loaded
                } completion: {
                    onLoaded?()
                }
                shownURLs = urls
                return
            } catch {
                if Task.isCancelled { return }
                // A status or a body that is not a picture is final; a network error is not.
                if error is ImageLoadError { ChainedImageFailures.insert(string) }
            }
        }
    }
}

/// Candidates that answered with an error status or a placeholder this session. Bounded; cleared
/// wholesale at the cap (it only saves a request).
@MainActor
private enum ChainedImageFailures {
    private static var failed: Set<String> = []
    private static let cap = 400

    static func contains(_ url: String) -> Bool { failed.contains(url) }

    static func insert(_ url: String) {
        if failed.count >= cap { failed.removeAll(keepingCapacity: true) }
        failed.insert(url)
    }
}
