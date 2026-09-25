import SwiftUI

// The stories tray above the feed (ios-spec §7.2, §1.2): Instagram's row of rings, one per library
// show with a NEW episode you have not seen. A story is an alert, not an archive: once seen (viewed
// to its end, or its episodes watched) the reel LEAVES the tray, and it comes back only when a newer
// episode airs — so the tray is something to wait for, and every ring in it is lit (the icon's five
// gels). The tapped ring breaks into turning dashes while its first picture loads (FeedView's open,
// ≤ 0.9 s), and the viewer grows out of it. While the viewer is up the tray holds the reels it
// opened with (a seen ring goes quiet behind it); they leave a beat after the close flight lands.
//
// The reels are the model's memoised `trayReels` (or FeedView's held snapshot) — nothing is built here.

/// Where each story bubble's PHOTO is on screen, in global coordinates. Written by the tray as it
/// lays out, read when a story opens and closes — never observed, so a scroll frame never re-runs
/// the feed (the app's scroll-offset rule).
@MainActor final class StoryOrigins { var frames: [String: CGRect] = [:] }

struct StoryTray: View {
    let reels: [StoryReel]
    /// The reel whose ring is spinning while its first frame loads.
    let loadingReelId: String?
    let origins: StoryOrigins
    let onOpen: (_ index: Int) -> Void

    @Environment(AppModel.self) private var appModel

    var body: some View {
        let inset = StoryBubble.photoInset
        let side = FeedMetrics.storyBubble - inset * 2
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: FeedMetrics.storyBubbleSpacing) {
                ForEach(Array(reels.enumerated()), id: \.element.id) { i, reel in
                    let seen = reel.seen || appModel.hasViewed(reel)
                    Button { onOpen(i) } label: {
                        StoryBubble(reel: reel, seen: seen, loading: loadingReelId == reel.id)
                    }
                    .buttonStyle(StoryBubblePressStyle())
                    // A seen reel leaving: it sinks into itself while the rest close the gap.
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                    .accessibilityLabel(Copy.Stories.bubble(show: reel.showTitle, unwatched: reel.unwatched))
                    .onGeometryChange(for: CGRect.self) { g in
                        // The ring's PHOTO, not the name under it: the flight starts from the face.
                        let f = g.frame(in: .global)
                        return CGRect(x: f.minX + inset, y: f.minY + inset, width: side, height: side)
                    } action: { origins.frames[reel.id] = $0 }
                }
            }
            .padding(.horizontal, FeedMetrics.storyBubbleSpacing)
            .padding(.vertical, ThemeSpace.x0_5)
        }
        .scrollIndicators(.hidden)
        // The press dip and the ring's outer edge are never cut by the strip's bounds.
        .scrollClipDisabled()
    }
}

/// One ring and its name. The ring's state is Instagram's: gels while unseen, turning dashes while
/// the reel loads, and a quiet grey circle once seen — drawn only behind the viewer and for the
/// beat before a seen reel leaves the tray.
struct StoryBubble: View {
    let reel: StoryReel
    let seen: Bool
    let loading: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Where the photo sits inside the ring — `FeedAvatar`'s own inset at the bubble size (the
    /// ring's width, then the gap), so the flight starts exactly on the face.
    nonisolated static var photoInset: CGFloat { FeedAvatar.photoInset(ringed: FeedMetrics.storyBubble) }

    var body: some View {
        VStack(spacing: ThemeSpace.x2) {
            FeedAvatar(candidates: reel.avatarCandidates, size: FeedMetrics.storyBubble,
                       ring: loading ? .loading : (seen ? .seen : .unseen))
                .animation(ThemeMotion.pick(ThemeMotion.uiGentle, reduceMotion: reduceMotion), value: seen)
                // Instagram's LIVE tag, saying what the ring means here: an episode is out that
                // you have not watched. It leaves with the mark (and with the reel, once seen).
                .overlay(alignment: .bottom) {
                    if reel.unwatched > 0 {
                        StoryRingTag(text: Copy.Stories.ringTag(reel.unwatched))
                            .offset(y: FeedMetrics.ringTagHeight / 2)
                            .transition(.opacity)
                    }
                }
            Text(reel.showTitle)
                .type(ThemeType.storyName)
                .foregroundStyle(seen ? ThemeColor.feedSecondary : ThemeColor.feedText)
                .lineLimit(1)
                .frame(width: FeedMetrics.storyBubble + FeedMetrics.storyNameWidthExtra)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
    }
}

/// The ring's NEW tag: the story gels' warm end in a small tag, white heavy caps, cut out of the
/// ring by a rim of the page's own black — Instagram's LIVE tag, in the app's colours.
struct StoryRingTag: View {
    let text: String

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: FeedMetrics.ringTagRadius, style: .continuous)
        Text(text)
            .type(ThemeType.storyRingTag)
            .foregroundStyle(ThemeColor.textPrimary)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, ThemeSpace.x1 + ThemeSpace.x0_5)
            .frame(height: FeedMetrics.ringTagHeight)
            .background(LinearGradient(colors: [ThemeGel.coral, ThemeGel.rose], startPoint: .leading, endPoint: .trailing),
                        in: shape)
            .padding(FeedMetrics.ringTagRim)
            .background(ThemeColor.canvas, in: RoundedRectangle(cornerRadius: FeedMetrics.ringTagRadius + FeedMetrics.ringTagRim,
                                                                  style: .continuous))
            .accessibilityHidden(true)
    }
}
