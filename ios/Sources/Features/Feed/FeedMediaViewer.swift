import SwiftUI

/// The black stage a picture or a trailer's still is looked at on, and the ink over it. A picture's
/// stage is black whatever the app's canvas (X's, Photos'): these are its only colours.
enum FeedStage {
    /// The stage itself.
    static let ground = Color.black
    /// Glyphs and words over a picture.
    static let ink = Color.white
    /// A glyph's disc over a picture (the close button, the play button, the menu).
    static let glyphGround = Color.black.opacity(0.45)
    /// A glyph disc's hairline.
    static let glyphEdge = Color.white.opacity(0.12)
    /// The foot's protection under the post's words.
    static let footScrim = Color.black.opacity(0.78)
}

// X's media viewer (round 4). A post's picture zooms out of the feed onto a black stage (the
// system's zoom transition, so a swipe down carries it back into the post it came from); pinch or
// double-tap to look closer; one tap clears the chrome; the post's own words and its action bar sit
// along the foot in white, as X's do. Dragging the picture away thins the black and steps the
// chrome aside; let go far enough and it goes home.

struct FeedMediaViewer: View {
    let model: FeedPostModel
    let onComment: () -> Void
    let onOpenShow: () -> Void

    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    @State private var chrome = true
    @State private var scale: CGFloat = 1
    @State private var base: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var panBase: CGSize = .zero
    /// The drag-to-close: the picture follows the finger, the black thins, the chrome steps aside.
    @State private var drag: CGSize = .zero

    private enum Reach {
        /// The drag that closes, in points (or its predicted end).
        static let closeDistance: CGFloat = 110
        static let closePredicted: CGFloat = 320
        /// How far a drag has to go for the stage to be fully "away".
        static let awayDistance: CGFloat = 360
        /// X's double-tap zoom, and the pinch's ceiling.
        static let doubleTapScale: CGFloat = 2.5
        static let maxScale: CGFloat = 4
    }

    private static let closeGlyph: CGFloat = 36
    private static let footTop: CGFloat = 36
    private static let footSide: CGFloat = 14

    /// The picture: the post's art (its poster, when it has no landscape), or a trailer's best still.
    private var url: String? {
        switch model.media {
        case .art(let art): return art.url
        case .trailer(let stills, _): return stills.first
        case .none: return model.franchise.portraitArt
        }
    }

    private var decodePixels: CGFloat {
        let constrained = SyncCenter.shared.isConstrained || SyncCenter.shared.isExpensive
        let screen = max(ThemeMetrics.windowWidth, ThemeMetrics.windowHeight) * displayScale
        return min(constrained ? PostMedia.maxPixels : Self.maxPixels, screen)
    }

    private static let maxPixels: CGFloat = 2400

    var body: some View {
        let away = min(1, abs(drag.height) / Reach.awayDistance)
        ZStack {
            FeedStage.ground
                .opacity(1 - away * 0.75)
                .ignoresSafeArea()
            RemoteImageView(url: url, contentMode: .fit, maxPixel: decodePixels, placeholderHidden: true)
                .scaleEffect(scale * (1 - away * 0.18))
                .offset(x: pan.width + drag.width, y: pan.height + drag.height)
                .ignoresSafeArea()
                .accessibilityLabel(Copy.Feed.pictureFrom(model.showName))
                .accessibilityAddTraits(.isImage)
            if chrome {
                VStack(spacing: 0) {
                    top
                    Spacer(minLength: 0)
                    // The tab bar's lane is under this cover: "Saved to Profile" and "Reminder set
                    // for …" are drawn here, over the foot, where the reader is. The spacer takes
                    // its height — the foot does not move.
                    CoverLane()
                    // First claim on the height: a stack offers its flexible children equal shares,
                    // and a post's whole words would otherwise stop at half the screen.
                    foot.layoutPriority(1)
                }
                .opacity(1 - away * 1.6)
                .transition(.opacity)
            }
        }
        // X's viewer answers anywhere on the screen, not only on the picture: one tap clears the
        // chrome, two zoom, a pinch zooms, a drag pans when zoomed and closes when not.
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { toggleZoom() }
        .onTapGesture {
            withAnimation(ThemeMotion.pick(ThemeMotion.uiGentle, reduceMotion: reduceMotion)) { chrome.toggle() }
        }
        .simultaneousGesture(magnify)
        .gesture(dragGesture)
        .statusBarHidden(!chrome)
        .preferredColorScheme(.dark)
        .accessibilityAction(named: Copy.Feed.closeViewer) { dismiss() }
        .perfScreen("Media")
    }

    private var top: some View {
        HStack {
            Button { dismiss() } label: {
                AppGlyph(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(FeedStage.ink)
                    .frame(width: Self.closeGlyph, height: Self.closeGlyph)
                    .background(FeedStage.glyphGround, in: Circle())
                    .overlay(Circle().strokeBorder(FeedStage.glyphEdge, lineWidth: FeedMetrics.hairline))
                    .frame(width: FeedMetrics.actionHitHeight, height: FeedMetrics.actionHitHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(FeedIconPressStyle())
            .accessibilityLabel(Copy.Feed.closeViewer)
            Spacer()
            PostMenuButton(model: model, onOpenShow: { dismiss(); onOpenShow() }, tint: FeedStage.ink,
                           insideLine: false)
                .background(FeedStage.glyphGround, in: Circle().inset(by: ThemeSpace.x1))
        }
        .padding(.horizontal, ThemeSpace.x3)
    }

    /// X's foot: the account line, the words, then the bar in white — over a scrim so it reads on a
    /// bright picture too.
    private var foot: some View {
        VStack(alignment: .leading, spacing: ThemeSpace.x1 + ThemeSpace.x0_5) {
            HStack(spacing: ThemeSpace.x1) {
                Text(model.showName)
                    .type(ThemeType.feedNoteTitle)
                    .foregroundStyle(FeedStage.ink)
                    .lineLimit(1)
                if model.showsOfficialMark { ConfirmedMark(size: 15) }
                Text(Copy.Feed.afterDot(model.stamp))
                    .type(ThemeType.feedSubhead)
                    .foregroundStyle(FeedStage.ink.opacity(0.6))
                    .fixedSize()
            }
            // The post's own words, whole (`FeedPostModel.body`), as X's viewer carries them — not a
            // three-line clip. Not `fixedSize`: only a foot taller than the screen (the largest
            // text sizes) ends its words early, rather than pushing the close button off the top.
            Text(model.body)
                .type(ThemeType.feedNote)
                .foregroundStyle(FeedStage.ink.opacity(0.92))
                .readingLines(FeedPostLayout.lineHeight)
            PostActionBar(model: model, onDark: true, onComment: { dismiss(); onComment() })
                .padding(.top, ThemeSpace.x0_5)
            // Remind while notifications are not allowed: the primer the feed row would draw — it
            // is under this cover too, and the tap would otherwise answer nothing (§4.4).
            if appModel.reminderPrimerPostId == model.id {
                AlertsPrimerLine(model: model)
                    .padding(.bottom, ThemeSpace.x1)
                    .transition(.opacity)
            }
        }
        .animation(ThemeMotion.pick(ThemeMotion.uiGentle, reduceMotion: reduceMotion),
                   value: appModel.reminderPrimerPostId == model.id)
        .padding(.horizontal, Self.footSide)
        .padding(.top, Self.footTop)
        .padding(.bottom, ThemeSpace.x1)
        .background(alignment: .bottom) {
            LinearGradient(colors: [.clear, FeedStage.footScrim], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
        }
    }

    // MARK: Zoom

    private var magnify: some Gesture {
        MagnifyGesture()
            .onChanged { v in scale = min(Reach.maxScale, max(1, base * v.magnification)) }
            .onEnded { _ in
                base = scale
                if scale <= 1.02 {
                    withAnimation(ThemeMotion.pick(ThemeMotion.uiSnappy, reduceMotion: reduceMotion)) { reset() }
                }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: ThemeSpace.x2)
            .onChanged { v in
                if scale > 1.01 {
                    pan = CGSize(width: panBase.width + v.translation.width,
                                 height: panBase.height + v.translation.height)
                } else {
                    drag = v.translation
                }
            }
            .onEnded { v in
                if scale > 1.01 {
                    panBase = pan
                } else if abs(v.translation.height) > Reach.closeDistance
                            || abs(v.predictedEndTranslation.height) > Reach.closePredicted {
                    dismiss()
                } else {
                    withAnimation(ThemeMotion.pick(ThemeMotion.uiSnappy, reduceMotion: reduceMotion)) { drag = .zero }
                }
            }
    }

    /// X's double tap: in to 2.5×, and back out.
    private func toggleZoom() {
        withAnimation(ThemeMotion.pick(ThemeMotion.uiSnappy, reduceMotion: reduceMotion)) {
            if scale > 1.01 {
                reset()
            } else {
                scale = Reach.doubleTapScale
                base = Reach.doubleTapScale
            }
        }
    }

    private func reset() {
        scale = 1
        base = 1
        pan = .zero
        panBase = .zero
    }
}
