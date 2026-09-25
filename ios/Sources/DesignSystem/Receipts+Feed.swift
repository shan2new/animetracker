import SwiftUI

extension ReceiptHost {
    /// The story viewer's mark: the lane is hidden under a fullScreenCover, so the receipt is drawn IN
    /// the viewer, under the mark control (the story's single mark and its batch confirm both write
    /// with `.placed(at: ReceiptHost.story(mediaId, episode))`, and the page's `ReceiptLine` reads the
    /// same spelling). Closing the viewer with a receipt still live hands its Undo to the lane.
    static func story(_ mediaId: Int, _ episode: Int) -> String { "story/\(mediaId)/\(episode)" }
}

/// The lane, over a cover. The tab bar's lane — the 26.1 accessory, or `ToastHost`'s fallback — is
/// drawn UNDER any `fullScreenCover` or large sheet, so a receipt written from inside one ("Saved to
/// Profile" from the picture viewer, "Reminder set for Sat 3 Oct", "Reply deleted" in an episode's
/// discussion) was drawn where nobody could see it, and a two-second notice expired before the cover
/// closed. The picture viewer, the story viewer, the discussion sheet and the composer mount this:
/// the same `LaneItem` in the same glass with `LaneFallback`'s transitions — one lane, drawn where
/// the reader is. It is never a layout child that moves the page: the host places it over its own
/// foot, or in its bottom inset above the bar that is already there.
struct CoverLane: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        LaneFallback()
            .frame(maxWidth: 420)
            .padding(.horizontal, ThemeMetrics.gutter)
            // Zero height while there is nothing to say: a host's bottom inset keeps its size.
            .padding(.bottom, appModel.laneItem == nil ? 0 : ThemeSpace.x2)
    }
}
