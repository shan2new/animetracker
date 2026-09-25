import SwiftUI

// Discover at rest, rebuilt in Today's language (25 Sep: "Discover UX needs an overhaul to match
// this new awesome Today UX", owner). Today speaks X and Instagram; Discover spoke Apple TV — a
// "TOP PICK FOR YOU" billboard with an amber capsule, shelves under chevroned headers, a row of
// scope chips, a poster wall. It is now X's and Instagram's EXPLORE:
//   · under the field, X's tabs — For you · Trending · Genres — the words bold 16, the underline
//     riding the pager while the finger drags (Today's `FeedTabsRow`, the same numbers), each page
//     keeping its own place;
//   · For you is Instagram's Explore grid: the recommendations as an edge-to-edge wall of posters
//     two points apart, a feature tile two columns wide every other block (the reason it is here
//     on its foot — the library-based list is the point of the tab), trending filling the wall;
//   · Trending is X's list: "1 · Anime · Trending", the title in bold, one fact, a small poster;
//   · Genres is the catalogue's genre tiles, all of them, as a page of its own.
// The scope (All / Anime / TV) is a menu in the bar; the field and its results are unchanged.

enum DiscoverSection: CaseIterable, Hashable {
    case forYou, trending, genres

    var title: String {
        switch self {
        case .forYou: Copy.Discover.tabForYou
        case .trending: Copy.Discover.tabTrending
        case .genres: Copy.Discover.tabGenres
        }
    }
}

/// The pager's position as a fraction of a page, written by the pager's probe and read ONLY by
/// the tab row, so a swipe redraws three words and a capsule.
@MainActor
@Observable
final class PagerProgress {
    private(set) var value: CGFloat = 0

    func set(_ v: CGFloat, pages: Int) {
        let clamped = min(max(v, 0), CGFloat(max(0, pages - 1)))
        let landed = clamped == clamped.rounded()
        if abs(clamped - value) >= 0.002 || (landed && clamped != value) { value = clamped }
    }
}

/// One tile of the For you wall: a recommendation, or a trending show filling the wall.
enum ExploreItem: Identifiable {
    case rec(RecommendationItem)
    case trend(FranchiseSummary)

    var id: String {
        switch self {
        case .rec(let r): "rec/\(r.key)"
        case .trend(let s): "trend/\(s.id)"
        }
    }

    var poster: String? {
        switch self {
        case .rec(let r): r.stub?.tilePoster.url ?? r.images?.portrait
        case .trend(let s): s.tilePoster.url ?? s.portraitArt
        }
    }

    var title: String {
        switch self {
        case .rec(let r): r.displayTitle
        case .trend(let s): s.title
        }
    }

    /// How the tile names the show: the logo over a textless poster, else the poster's own title.
    var name: BillboardName {
        switch self {
        case .rec(let r): r.stub?.tilePoster.name ?? .type
        case .trend(let s): s.tilePoster.name
        }
    }
}

struct DiscoverExplore: View {
    /// In the scope, best first.
    let recommendations: [RecommendationItem]
    let trending: [FranchiseSummary]
    let genres: [DiscoverGenre]
    let reason: (RecommendationItem) -> RecommendationItem.Reason
    /// A trending show's one fact, and whether it LEADS (a time this week, in amber).
    let caption: (FranchiseSummary) -> (text: String, lead: Bool)
    let spoken: (FranchiseSummary) -> String
    let onOpenRecommendation: (RecommendationItem) -> Void
    let onOpenShow: (FranchiseSummary) -> Void
    let onRefresh: @Sendable () async -> Void
    /// Drawn over the For you wall (the notification primer after an add).
    var header: AnyView? = nil

    @Environment(AppModel.self) private var appModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var section: DiscoverSection = .forYou
    @State private var pagerSection: DiscoverSection? = .forYou
    @State private var progress = PagerProgress()
    @State private var proxies: [DiscoverSection: ScrollViewProxy] = [:]

    private static let top = "top"

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                ExploreTabs(selected: section, progress: progress) { next in
                    if next == section {
                        withAnimation(ThemeMotion.pick(ThemeMotion.uiSnappy, reduceMotion: reduceMotion)) {
                            proxies[next]?.scrollTo(Self.top, anchor: .top)
                        }
                    } else {
                        withAnimation(ThemeMotion.pick(ThemeMotion.uiSnappy, reduceMotion: reduceMotion)) {
                            pagerSection = next
                        }
                    }
                }
                pager(width: geo.size.width, bottom: geo.safeAreaInsets.bottom)
            }
        }
        .onChange(of: pagerSection) { _, next in
            if let next, next != section { section = next }
        }
    }

    // MARK: The pager

    private func pager(width: CGFloat, bottom: CGFloat) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                ForEach(DiscoverSection.allCases, id: \.self) { s in
                    page(s, bottom: bottom)
                        .frame(width: width)
                        .id(s)
                }
            }
            .scrollTargetLayout()
            .background {
                Color.clear.onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.frame(in: .global).minX
                } action: { minX in
                    guard width > 0 else { return }
                    progress.set(-minX / width, pages: DiscoverSection.allCases.count)
                }
            }
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $pagerSection)
        .scrollIndicators(.hidden)
        .ignoresSafeArea(.container, edges: .bottom)
    }

    private func page(_ s: DiscoverSection, bottom: CGFloat) -> some View {
        ScrollViewReader { reader in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: 0).id(Self.top)
                    switch s {
                    case .forYou: forYou
                    case .trending: trendingList
                    case .genres: genreWall
                    }
                }
            }
            .safeAreaPadding(.bottom, bottom)
            .scrollIndicators(.hidden)
            .tabBarContentMargin()
            .laneClearance(appModel)
            .previouslyRefreshable(onRefresh)
            .onAppear { proxies[s] = reader }
        }
    }

    // MARK: For you — Instagram's Explore grid

    private var wall: [ExploreItem] {
        let recs = recommendations.map(ExploreItem.rec)
        let recIds = Set(recommendations.compactMap(\.franchiseId))
        let fill = trending.filter { !recIds.contains($0.id) }.map(ExploreItem.trend)
        return Array((recs + fill).prefix(Self.wallLimit))
    }

    private static let wallLimit = 36

    @ViewBuilder
    private var forYou: some View {
        if let header { header.padding(.vertical, ThemeSpace.x3) }
        let items = wall
        if items.isEmpty {
            placeholder
        } else {
            ExploreGrid(items: items, reason: reason, spoken: spoken,
                        onOpenRecommendation: onOpenRecommendation, onOpenShow: onOpenShow)
                .padding(.top, ExploreGrid.gap)
        }
    }

    // MARK: Trending — X's list

    @ViewBuilder
    private var trendingList: some View {
        if trending.isEmpty {
            placeholder
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(trending.enumerated()), id: \.element.id) { i, item in
                    TrendRow(rank: i + 1, item: item, caption: caption(item), spoken: spoken(item)) {
                        onOpenShow(item)
                    }
                }
            }
        }
    }

    // MARK: Genres

    @ViewBuilder
    private var genreWall: some View {
        if genres.isEmpty {
            ProgressView()
                .tint(ThemeColor.feedSecondary)
                .frame(maxWidth: .infinity, minHeight: 200)
                .accessibilityLabel(Copy.Accessibility.loading)
        } else {
            DiscoverGenres(genres: genres, limit: nil, header: false)
                .padding(.top, ThemeSpace.x3)
        }
    }

    // MARK: States

    @ViewBuilder
    private var placeholder: some View {
        if !SyncCenter.shared.isOnline {
            EmptyState(.searchOffline, primary: { appModel.loadTrendingIfNeeded() })
                .padding(.horizontal, ThemeMetrics.gutter)
                .padding(.vertical, ThemeSpace.x8)
        } else {
            ProgressView()
                .tint(ThemeColor.feedSecondary)
                .frame(maxWidth: .infinity, minHeight: 200)
                .accessibilityLabel(Copy.Accessibility.loading)
        }
    }
}

// MARK: - The tabs

/// X's tabs under the field — Today's `FeedTabsRow`, the same numbers: bold 16 in both states,
/// the ink and a 3-pt capsule following the pager (`PagerProgress`), a one-pixel rule under.
struct ExploreTabs: View {
    let selected: DiscoverSection
    let progress: PagerProgress
    let onSelect: (DiscoverSection) -> Void

    @State private var words: [DiscoverSection: CGRect] = [:]

    private static let underlineHeight: CGFloat = 3
    private static let underlineOverhang: CGFloat = 11
    private static let space = "exploreTabs"

    var body: some View {
        let p = progress.value
        let tabs = DiscoverSection.allCases
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(tabs.enumerated()), id: \.element) { index, t in
                    let lit = max(0, 1 - abs(p - CGFloat(index)))
                    Button { onSelect(t) } label: {
                        word(t, ink: ThemeColor.feedSecondary)
                            .overlay { word(t, ink: ThemeColor.feedText).opacity(lit) }
                            .onGeometryChange(for: CGRect.self) { proxy in
                                proxy.frame(in: .named(Self.space))
                            } action: { frame in
                                if words[t] != frame { words[t] = frame }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .frame(height: FeedMetrics.headerTabs)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(t == selected ? .isSelected : [])
                }
            }
            .overlay(alignment: .bottomLeading) { underline(p, tabs: tabs) }
            .coordinateSpace(.named(Self.space))
            FeedHairline()
        }
        .background(ThemeColor.canvas)
    }

    private func word(_ t: DiscoverSection, ink: Color) -> some View {
        Text(t.title)
            .type(ThemeType.feedTab)
            .foregroundStyle(ink)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    /// The capsule between the two words either side of `p`, `p`'s fraction of the way across.
    @ViewBuilder
    private func underline(_ p: CGFloat, tabs: [DiscoverSection]) -> some View {
        let lower = max(0, min(tabs.count - 1, Int(p.rounded(.down))))
        let upper = min(tabs.count - 1, lower + 1)
        if let a = words[tabs[lower]], let b = words[tabs[upper]] {
            let f = p - CGFloat(lower)
            let width = a.width + (b.width - a.width) * f + 2 * Self.underlineOverhang
            let midX = a.midX + (b.midX - a.midX) * f
            Capsule()
                .fill(ThemeColor.feedText)
                .frame(width: width, height: Self.underlineHeight)
                .offset(x: midX - width / 2)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Instagram's Explore grid

/// The wall: three columns two points apart, edge to edge, each tile a poster FILLING its 2:3
/// cell; every other block leads with a FEATURE tile two columns wide and two rows tall (itself
/// 2:3), on the left, then on the right — Instagram's rhythm. Posters carry no caption (the titled
/// poster names the show); a feature tile carries its reason on its foot. Eager rows in a lazy
/// stack: only the blocks on screen are built.
struct ExploreGrid: View {
    let items: [ExploreItem]
    let reason: (RecommendationItem) -> RecommendationItem.Reason
    let spoken: (FranchiseSummary) -> String
    let onOpenRecommendation: (RecommendationItem) -> Void
    let onOpenShow: (FranchiseSummary) -> Void

    static let gap: CGFloat = 2
    private static let columns: CGFloat = 3

    private enum Block { case featureLeading, featureTrailing, row }

    private var cell: CGFloat { (ThemeMetrics.windowWidth - Self.gap * (Self.columns - 1)) / Self.columns }

    var body: some View {
        let blocks = chunks()
        LazyVStack(spacing: Self.gap) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { i, block in
                blockView(block, kind: kind(i, count: block.count))
            }
        }
    }

    private func chunks() -> [[ExploreItem]] {
        stride(from: 0, to: items.count, by: 3).map { Array(items[$0..<min($0 + 3, items.count)]) }
    }

    private func kind(_ i: Int, count: Int) -> Block {
        guard count == 3 else { return .row }
        switch i % 4 {
        case 0: return .featureLeading
        case 2: return .featureTrailing
        default: return .row
        }
    }

    @ViewBuilder
    private func blockView(_ block: [ExploreItem], kind: Block) -> some View {
        let w = cell, h = cell * 1.5
        let fw = w * 2 + Self.gap, fh = h * 2 + Self.gap
        switch kind {
        case .row:
            HStack(spacing: Self.gap) {
                ForEach(block) { item in tile(item, width: w, height: h, feature: false) }
                if block.count < 3 { Spacer(minLength: 0) }
            }
        case .featureLeading:
            HStack(alignment: .top, spacing: Self.gap) {
                tile(block[0], width: fw, height: fh, feature: true)
                VStack(spacing: Self.gap) {
                    tile(block[1], width: w, height: h, feature: false)
                    tile(block[2], width: w, height: h, feature: false)
                }
            }
        case .featureTrailing:
            HStack(alignment: .top, spacing: Self.gap) {
                VStack(spacing: Self.gap) {
                    tile(block[1], width: w, height: h, feature: false)
                    tile(block[2], width: w, height: h, feature: false)
                }
                tile(block[0], width: fw, height: fh, feature: true)
            }
        }
    }

    @ViewBuilder
    private func tile(_ item: ExploreItem, width: CGFloat, height: CGFloat, feature: Bool) -> some View {
        switch item {
        case .rec(let r):
            let why = reason(r)
            ExploreTile(poster: item.poster, name: item.name, title: item.title, width: width, height: height,
                        owned: false, footnote: feature ? Copy.ForYou.tileReasons(why).first : nil) {
                onOpenRecommendation(r)
            }
            .accessibilityLabel("\(r.displayTitle), \(Copy.ForYou.reasonList(why))")
            .contextMenu { ForYouMenu(item: r, reason: why, onOpen: { onOpenRecommendation(r) }) }
        case .trend(let s):
            ExploreTrendTile(item: s, width: width, height: height, spoken: spoken(s)) { onOpenShow(s) }
        }
    }
}

/// A trending show on the wall: its poster, the owned check when it is yours, and its long-press
/// actions (the library's quick actions).
private struct ExploreTrendTile: View {
    let item: FranchiseSummary
    let width: CGFloat
    let height: CGFloat
    let spoken: String
    let onOpen: () -> Void

    @Environment(AppModel.self) private var appModel

    var body: some View {
        ExploreTile(poster: item.tilePoster.url ?? item.portraitArt, name: item.tilePoster.name, title: item.title,
                    width: width, height: height,
                    owned: appModel.isInLibrary(item.id), footnote: nil, action: onOpen)
            .accessibilityLabel(spoken)
            .accessibilityHint(Copy.Accessibility.opensTheShowHint)
            .franchiseQuickActions(appModel.franchise(id: item.id), appModel: appModel)
    }
}

/// One cell of the wall: the poster filling it from the top, square-cornered as Instagram's are.
/// A TEXTLESS poster carries the show's LOGO on its foot, over a short shade (`ArtworkPoster`'s
/// treatment, the one every poster in the app wears — "WTF don't the posters contain logo
/// image??", owner, when the first cut drew the bare picture); a titled poster names itself.
private struct ExploreTile: View {
    let poster: String?
    let name: BillboardName
    let title: String
    let width: CGFloat
    let height: CGFloat
    let owned: Bool
    /// A feature tile's line on its foot (the reason it is here).
    let footnote: String?
    let action: () -> Void

    @Environment(\.displayScale) private var displayScale

    /// The logo's box scales with the tile: ~36 pt on a third of the width, 66 on a feature.
    private var logoHeight: CGFloat { min(66, max(28, width * 0.26)) }

    var body: some View {
        Button(action: action) {
            RemoteImageView(url: poster, contentMode: .fill, maxPixel: min(1600, height * displayScale),
                            alignment: .top)
                .frame(width: width, height: height)
                .clipped()
                .overlay(alignment: .bottom) {
                    if name.hasGraphicLogo || footnote != nil {
                        VStack(alignment: .leading, spacing: ThemeSpace.x2) {
                            if name.hasGraphicLogo {
                                ArtworkLogo(name: name, title: title, height: logoHeight)
                                    .frame(maxWidth: .infinity)
                            }
                            if let footnote {
                                Text(footnote)
                                    .type(ThemeType.feedNoteTitle)
                                    .foregroundStyle(ThemeColor.textPrimary)
                                    .lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(.horizontal, ThemeSpace.x3)
                        .padding(.bottom, ThemeSpace.x3)
                        .padding(.top, ThemeSpace.x5)
                        .background {
                            LinearGradient(colors: [.clear, .black.opacity(0.72)], startPoint: .top, endPoint: .bottom)
                                .allowsHitTesting(false)
                        }
                        .allowsHitTesting(false)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if owned { OwnedMark().padding(ThemeSpace.x2) }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(OverArtPressStyle())
    }
}

// MARK: - X's trending row

/// "1 · Anime · Trending" in grey, the title in bold, its one fact (a time this week in amber), a
/// small poster at the trailing edge; the row opens the show, its long press is the library's quick
/// actions. A one-pixel rule under it.
private struct TrendRow: View {
    let rank: Int
    let item: FranchiseSummary
    let caption: (text: String, lead: Bool)
    let spoken: String
    let action: () -> Void

    @Environment(AppModel.self) private var appModel

    private static let thumbWidth: CGFloat = 52
    private static let thumbRadius: CGFloat = 6

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.thumbRadius, style: .continuous)
        VStack(spacing: 0) {
            Button(action: action) {
                HStack(alignment: .top, spacing: ThemeSpace.x3) {
                    VStack(alignment: .leading, spacing: ThemeSpace.x0_5) {
                        Text(Copy.Discover.trendEyebrow(rank: rank, kind: item.source.kindWord))
                            .type(ThemeType.feedSmall)
                            .foregroundStyle(ThemeColor.feedSecondary)
                            .lineLimit(1)
                        Text(item.title)
                            .type(ThemeType.feedName)
                            .foregroundStyle(ThemeColor.feedText)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text(caption.text)
                            .type(ThemeType.feedNote)
                            .foregroundStyle(caption.lead ? ThemeColor.accent : ThemeColor.feedSecondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    RemoteImageView(url: item.tilePoster.url ?? item.portraitArt, contentMode: .fill, maxPixel: 240,
                                    alignment: .top)
                        .frame(width: Self.thumbWidth, height: Self.thumbWidth * 1.5)
                        .clipShape(shape)
                        .overlay(shape.strokeBorder(ThemeColor.posterEdge, lineWidth: FeedMetrics.hairline))
                        .overlay(alignment: .topTrailing) {
                            if appModel.isInLibrary(item.id) { OwnedMark().scaleEffect(0.8).offset(x: 6, y: -6) }
                        }
                }
                .padding(.horizontal, ThemeMetrics.gutter)
                .padding(.vertical, ThemeSpace.x3)
                .contentShape(Rectangle())
            }
            .buttonStyle(FeedRowPressStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken)
            .accessibilityHint(Copy.Accessibility.opensTheShowHint)
            .franchiseQuickActions(appModel.franchise(id: item.id), appModel: appModel)
            FeedHairline()
        }
    }
}
