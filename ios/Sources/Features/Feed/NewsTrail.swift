import SwiftUI

// "How this story got here": the reporting trail behind a post (the server's `storyline`, one beat
// per dated report, oldest to newest) and every source behind it (`threadSources`). The feed is
// written by a research agent; this page is why anyone should believe it. Every link opens only
// when it is https (brief §14) — the server has already dropped anything else; this is the second
// guard.

private enum TrailLayout {
    /// A source's initial tile and a beat's.
    static let sourceTile: CGFloat = 36
    static let beatTile: CGFloat = 40
    /// X's thread line: 2 pt of the separator's grey, joining one report to the next.
    static let threadLine: CGFloat = 2
    static let beatGap: CGFloat = 18
    static let rowVertical: CGFloat = 10
}

/// A publisher's initial in a rounded square — the trail's stand-in for an account's avatar (the
/// app never fetches a publisher's logo).
private struct PublisherTile: View {
    let publisher: String
    let size: CGFloat
    var lit = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * FeedMetrics.showCornerRatio, style: .continuous)
        Text(String(publisher.prefix(1)).uppercased())
            .type(ThemeType.feedNoteTitle)
            .foregroundStyle(ThemeColor.feedText)
            .frame(width: size, height: size)
            .background(ThemeColor.feedField, in: shape)
            .overlay(shape.strokeBorder(lit ? ThemeColor.feedText.opacity(0.5) : .clear, lineWidth: FeedMetrics.hairline))
            .accessibilityHidden(true)
    }
}

// MARK: - A source

/// A source as X lists an account: the publisher's initial, the name in bold with the gold check
/// when it is the studio, network or streamer itself, the date and the site in grey, and the arrow
/// only when there is a page to open.
struct SourceRow: View {
    let source: FeedSource

    private var link: URL? { SafeURL.https(source.url?.absoluteString) }

    var body: some View {
        HStack(spacing: ThemeSpace.x3) {
            PublisherTile(publisher: source.publisher, size: TrailLayout.sourceTile)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: ThemeSpace.x1) {
                    Text(source.publisher)
                        .type(ThemeType.feedNoteTitle)
                        .foregroundStyle(ThemeColor.feedText)
                        .lineLimit(1)
                    if source.tier == .official { ConfirmedMark(size: 13) }
                }
                if !meta.isEmpty {
                    Text(meta)
                        .type(ThemeType.feedSmall)
                        .foregroundStyle(ThemeColor.feedSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if link != nil {
                Image(systemName: "arrow.up.right")
                    .font(ThemeType.feedSmall.font.weight(.semibold))
                    .foregroundStyle(ThemeColor.feedSecondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, TrailLayout.rowVertical)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(link != nil ? .isLink : [])
    }

    /// "23 Jun 2026 · crunchyroll.com".
    private var meta: String {
        let date = source.publishedAt.map {
            Formatting.formatted($0, skeleton: "dMMMyyyy", anchor: source.dateOnly ? .utcDate : .local)
        }
        let host = link?.host()?.replacingOccurrences(of: "www.", with: "")
        return Copy.Feed.separated([date, host].compactMap { $0 })
    }
}

// MARK: - The trail

/// The reporting trail as an X reply thread: each report is a reply — the publisher's initial,
/// "Publisher ✓ · 23 Jun 2026", that article's headline — joined by X's thread line. The beat on
/// the post's own news day is the one lit.
struct NewsTrailList: View {
    let beats: [NewsBeat]
    /// The post's news day: its beat's tile is edged, so the reader finds where the post stands.
    let newsDay: Int64

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(beats.enumerated()), id: \.element.id) { i, beat in
                let last = i == beats.count - 1
                let link = SafeURL.https(beat.url?.absoluteString)
                HStack(alignment: .top, spacing: ThemeSpace.x3) {
                    VStack(spacing: ThemeSpace.x1) {
                        PublisherTile(publisher: beat.publishers.first ?? "", size: TrailLayout.beatTile,
                                      lit: sameDay(beat.day, newsDay))
                        if !last {
                            Rectangle()
                                .fill(ThemeColor.feedSeparator)
                                .frame(width: TrailLayout.threadLine)
                                .frame(maxHeight: .infinity)
                        }
                    }
                    Button {
                        if let link { openURL(link) }
                    } label: {
                        beatBody(beat)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.bottom, last ? 0 : TrailLayout.beatGap)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(link == nil)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(link != nil ? .isLink : [])
                }
            }
        }
    }

    private func beatBody(_ beat: NewsBeat) -> some View {
        VStack(alignment: .leading, spacing: ThemeSpace.x0_5) {
            HStack(alignment: .firstTextBaseline, spacing: ThemeSpace.x1) {
                if let publisher = beat.publishers.first {
                    Text(publisher)
                        .type(ThemeType.feedNoteTitle)
                        .foregroundStyle(ThemeColor.feedText)
                        .lineLimit(1)
                }
                if beat.official { ConfirmedMark(size: 14) }
                Text(Copy.Feed.afterDot(Formatting.formatted(beat.day, skeleton: "dMMMyyyy", anchor: .utcDate)))
                    .type(ThemeType.feedNote)
                    .foregroundStyle(ThemeColor.feedSecondary)
                    .lineLimit(1)
                    .fixedSize()
            }
            if let headline = beat.headline, !headline.isEmpty {
                Text(headline)
                    .type(ThemeType.feedNote)
                    .foregroundStyle(ThemeColor.feedText)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if beat.publishers.count > 1 {
                Text(Copy.Feed.trailAlso(Array(beat.publishers.dropFirst().prefix(2)),
                                         more: max(0, beat.publishers.count - 3)))
                    .type(ThemeType.feedSmall)
                    .foregroundStyle(ThemeColor.feedSecondary)
                    .lineLimit(1)
            }
        }
    }

    /// The same UTC calendar day (a beat's `day` is a date, carried at noon UTC).
    private func sameDay(_ a: Int64, _ b: Int64) -> Bool {
        Formatting.formatted(a, skeleton: "yyyyMMdd", anchor: .utcDate)
            == Formatting.formatted(b, skeleton: "yyyyMMdd", anchor: .utcDate)
    }
}

// MARK: - The sheet

/// One tap from the post page's "How this story got here ›": the trail, then every source, then
/// the footnote that says where each report goes.
struct NewsTrailSheet: View {
    let detail: FeedPostDetail

    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !detail.storyline.isEmpty {
                        NewsTrailList(beats: detail.storyline, newsDay: detail.post.time.at)
                            .padding(.top, ThemeSpace.x3)
                    }
                    if !sources.isEmpty {
                        Text(Copy.Feed.sources)
                            .type(ThemeType.feedModuleTitle)
                            .foregroundStyle(ThemeColor.feedText)
                            .accessibilityAddTraits(.isHeader)
                            .padding(.top, detail.storyline.isEmpty ? ThemeSpace.x3 : ThemeSpace.x8)
                            .padding(.bottom, ThemeSpace.x2)
                        VStack(spacing: 0) {
                            ForEach(Array(sources.enumerated()), id: \.offset) { _, source in
                                let link = SafeURL.https(source.url?.absoluteString)
                                Button {
                                    if let link { openURL(link) }
                                } label: {
                                    SourceRow(source: source)
                                }
                                .buttonStyle(FeedRowPressStyle())
                                .disabled(link == nil)
                            }
                        }
                    }
                    Text(Copy.Feed.trailFootnote)
                        .type(ThemeType.feedSmall)
                        .foregroundStyle(ThemeColor.feedSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, ThemeSpace.x4)
                }
                .padding(.horizontal, ThemeMetrics.gutter)
                .padding(.bottom, ThemeSpace.x8)
            }
            .scrollIndicators(.hidden)
            .background(ThemeColor.canvas.ignoresSafeArea())
            .navigationTitle(Copy.Feed.howThisStoryGotHere)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(Copy.Action.done) { dismiss() }
                        .foregroundStyle(ThemeColor.interactive)
                }
            }
        }
        .tint(ThemeColor.interactive)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .perfScreen("Trail")
    }

    /// The thread's sources (every report behind the story), else the post's own. Primary first,
    /// then newest.
    private var sources: [FeedSource] {
        detail.threadSources.isEmpty ? detail.post.sources : detail.threadSources
    }
}
