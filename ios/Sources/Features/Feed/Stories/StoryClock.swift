import SwiftUI
import Observation

// The story viewer's clock (ios-spec §5.2). The spike ticked `@State progress` every 50 ms, which
// re-ran the viewer and every visible page twenty times a second. Here the clock is a class the
// viewer holds, the segment bar is the ONLY view that reads its progress (through a
// `TimelineView`, and only while running), and advancing is one sleeping task per frame.
//
// What is observed is only what changes rarely: `paused` (a hold, a sheet, VoiceOver) and
// `generation` (a new frame, or the same frame restarted after a mark). The running time itself
// is `@ObservationIgnored` — no body re-runs because a second passed.

@MainActor
@Observable
final class StoryClock {
    /// Observed: a flip re-schedules the segment bar's timeline and the viewer's advance task.
    private(set) var paused = true
    /// Observed: the frame the clock is timing.
    private(set) var frameKey = ""
    /// Observed: bumped by every `start`, so restarting the SAME frame (after a mark lands, the
    /// reader gets a whole frame with the room) re-arms the advance task.
    private(set) var generation = 0

    @ObservationIgnored private var startedAt: Date?
    @ObservationIgnored private var elapsedBefore: TimeInterval = 0

    let duration: TimeInterval = FeedMetrics.storyFrameSeconds

    /// Elapsed back to `fraction` of the frame (0 for a real session; a frozen capture holds a
    /// frame part-way). Running unless the clock is paused — the viewer owns the pause reasons.
    func start(frameKey: String, at fraction: Double = 0) {
        self.frameKey = frameKey
        elapsedBefore = duration * min(1, max(0, fraction))
        startedAt = paused ? nil : Date()
        generation &+= 1
    }

    /// Folds the running stretch into `elapsedBefore`.
    func pause() {
        guard !paused else { return }
        if let startedAt { elapsedBefore += Date().timeIntervalSince(startedAt) }
        startedAt = nil
        paused = true
    }

    func resume() {
        guard paused else { return }
        startedAt = Date()
        paused = false
    }

    /// Pure: how far through the frame the clock is at `date`, 0…1.
    func progress(at date: Date) -> Double {
        min(1, max(0, elapsed(at: date) / duration))
    }

    /// What is left of the frame at `date`, never negative.
    func remaining(at date: Date) -> TimeInterval {
        max(0, duration - elapsed(at: date))
    }

    private func elapsed(at date: Date) -> TimeInterval {
        elapsedBefore + (startedAt.map { max(0, date.timeIntervalSince($0)) } ?? 0)
    }
}

// MARK: - The segment bar

/// Instagram's segments across the top of a story: one per frame, the ones before the current
/// full, the current one filling with the clock. The ONLY per-frame view in the viewer — and only
/// on the active page while the clock runs (`TimelineView(.animation(paused:))`).
struct StorySegmentBar: View {
    let count: Int
    let current: Int
    /// The active page's clock; nil on a neighbour turning in with the cube (its current segment
    /// is empty, as Instagram draws the next show's).
    let clock: StoryClock?

    var body: some View {
        if let clock {
            TimelineView(.animation(minimumInterval: nil, paused: clock.paused)) { ctx in
                StorySegments(count: count, current: current, fill: clock.progress(at: ctx.date))
            }
        } else {
            StorySegments(count: count, current: current, fill: 0)
        }
    }
}

/// The segments at one instant.
struct StorySegments: View {
    let count: Int
    let current: Int
    let fill: Double

    var body: some View {
        HStack(spacing: StoryStyle.segmentGap) {
            ForEach(0..<max(count, 1), id: \.self) { i in
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(StoryStyle.segmentTrack)
                        Capsule().fill(StoryStyle.segmentFill)
                            .frame(width: g.size.width * amount(i))
                    }
                }
                .frame(height: StoryStyle.segmentHeight)
            }
        }
        .padding(.horizontal, ThemeSpace.x0_5)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func amount(_ i: Int) -> CGFloat {
        if i < current { return 1 }
        if i > current { return 0 }
        return CGFloat(min(1, max(0, fill)))
    }
}
