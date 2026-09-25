import SwiftUI

// Home's pieces: what it draws (`HomeFeed`, composed once per library and minute) and the views
// that draw it — the bar, the billboard, the Up next tiles. See `HomeView`.

// MARK: - What Home draws

/// The one thing to watch next, as the billboard says it.
struct HomeHero: Identifiable {
    enum Kind: Equatable {
        /// A drop you have not seen: `behind` episodes are out and unwatched on this part.
        case outNow(behind: Int)
        /// Nothing out: the next airing, at `at` (today's, else the week's first).
        case airing(at: Int64)
        /// Nothing new: the show at the top of your queue.
        case resume
    }

    let franchise: Franchise
    let part: FranchisePart
    /// The episode the billboard offers — the next to WATCH, or the one that airs next.
    let episode: Int
    let kind: Kind
    /// "Episode 24 aired yesterday", under a backlog's count: the drop, named.
    var drop: String? = nil

    var id: String { "\(franchise.id)/\(part.mediaId)/\(episode)" }

    /// Out, so there is something to mark.
    var canMark: Bool {
        if case .airing = kind { return false }
        return true
    }
}

/// A show in your queue, at the episode you left off.
struct HomeQueueItem: Identifiable, Equatable {
    let franchise: Franchise
    let part: FranchisePart
    /// Episodes out recently and unwatched — the NEW tag; 0 for a backlog.
    let fresh: Int

    var id: String { franchise.id }
    var episode: Int { part.progress + 1 }

    static func == (a: Self, b: Self) -> Bool {
        a.franchise.id == b.franchise.id && a.part.mediaId == b.part.mediaId
            && a.part.progress == b.part.progress && a.fresh == b.fresh
    }
}

/// One airing on the calendar, with its day — an episode out this past week and not marked
/// (Recently aired), or one still to come (This week).
struct HomeAiring: Identifiable {
    let entry: AppModel.ScheduleEntry
    /// Day offset from today: ≤ 0 for Recently aired, ≥ 0 for This week.
    let day: Int
    /// Local noon of that day.
    let noon: Int64
    var id: String { entry.id }
}

struct HomeFeed {
    var hero: HomeHero?
    /// The past week's episodes you have not marked, newest first — the billboard's show aside.
    var recent: [HomeAiring] = []
    /// The rest of your queue: shows the billboard and Recently aired do not already carry.
    var queue: [HomeQueueItem] = []
    var week: [HomeAiring] = []

    /// How many rows a list shows before its header's chevron takes over.
    static let listLimit = 5

    var isEmpty: Bool { hero == nil && recent.isEmpty && queue.isEmpty && week.isEmpty }
}

@MainActor
enum HomeCompose {
    static func feed(_ m: AppModel) -> HomeFeed {
        let now = m.nowMinute
        var out = HomeFeed()

        // Up next — Library's Continue rule: every Watching show with a part to resume. A fresh
        // drop leads (newest first), then the shelf's own order (the biggest backlog first).
        let shelf: [HomeQueueItem] = m.watchingShelf.compactMap { f in
            guard let part = f.resumePart else { return nil }
            return HomeQueueItem(franchise: f, part: part, fresh: freshCount(f, now: now))
        }
        let rank = Dictionary(uniqueKeysWithValues: shelf.enumerated().map { ($1.id, $0) })
        let queue = shelf.sorted { a, b in
            if (a.fresh > 0) != (b.fresh > 0) { return a.fresh > 0 }
            if a.fresh > 0 {
                // The resume part's own drop: `Franchise.lastAired` reads only a RELEASING part,
                // and a finale's season has stopped releasing.
                let la = a.part.lastAired(now: now, anchor: a.franchise.timeAnchor) ?? 0
                let lb = b.part.lastAired(now: now, anchor: b.franchise.timeAnchor) ?? 0
                if la != lb { return la > lb }
            }
            return (rank[a.id] ?? 0) < (rank[b.id] ?? 0)
        }

        let days = m.scheduleDays
        // Recently aired — "what about previous week / unmarked episodes?" (owner, 26 Sep): every
        // episode out in the last seven days (today included) that is not marked, newest first.
        let recent: [HomeAiring] = days
            .filter { $0.id <= 0 && $0.id > -7 }
            .flatMap { d in d.entries.filter { $0.aired && !$0.watched }.map { HomeAiring(entry: $0, day: d.id, noon: d.noon) } }
            .sorted { $0.entry.at > $1.entry.at }
        // This week — what airs from now to six days out, soonest first.
        let week: [HomeAiring] = days
            .filter { $0.id >= 0 && $0.id < 7 }
            .flatMap { d in d.entries.filter { !$0.aired }.map { HomeAiring(entry: $0, day: d.id, noon: d.noon) } }

        // The billboard: a drop you have not seen; else tonight's airing; else the top of the
        // queue; else the week's first airing.
        var hero: HomeHero?
        if let item = queue.first(where: { $0.fresh > 0 }) {
            hero = heroFor(item, now: now)
        } else if let today = week.first(where: { $0.day == 0 }) {
            hero = HomeHero(franchise: today.entry.franchise, part: today.entry.part,
                            episode: today.entry.episode, kind: .airing(at: today.entry.at))
        } else if let item = queue.first {
            hero = heroFor(item, now: now)
        } else if let next = week.first {
            hero = HomeHero(franchise: next.entry.franchise, part: next.entry.part,
                            episode: next.entry.episode, kind: .airing(at: next.entry.at))
        }
        out.hero = hero

        // Each show once, in the first place that carries it: the billboard, then Recently aired,
        // then Up next. This week is the future, so a show may be there as well.
        let heroShow = hero?.franchise.id
        out.recent = Array(recent.filter { $0.entry.franchise.id != heroShow }.prefix(HomeFeed.listLimit))
        let recentShows = Set(out.recent.map(\.entry.franchise.id))
        out.queue = queue.filter { $0.id != heroShow && !recentShows.contains($0.id) }
        let onBillboard: String? = {
            guard let hero, case .airing = hero.kind else { return nil }
            return "\(hero.franchise.id)/\(hero.part.mediaId)/\(hero.episode)"
        }()
        out.week = Array(week.filter { $0.id != onBillboard }.prefix(HomeFeed.listLimit))
        return out
    }

    /// Unwatched episodes of a drop inside the out-now window — `AppModel.outNow`'s own test, minus
    /// its "still releasing" gate: a FINALE is the freshest drop there is, and the season it ends
    /// stops releasing the moment it airs (Slime's Season 4, 25 Sep, was out of `outNow` the next
    /// morning with three episodes unwatched).
    private static func freshCount(_ f: Franchise, now: Int64) -> Int {
        let window = AppModel.outNowWindow
        guard let part = f.freshPart(now: now, window: window) ?? f.resumePart,
              part.mediaId == f.resumePart?.mediaId || f.resumePart == nil else { return 0 }
        let behind = part.unwatchedOut(now: now, anchor: f.timeAnchor)
        guard behind > 0, part.isNews(now: now, anchor: f.timeAnchor, window: window),
              let last = part.lastAired(now: now, anchor: f.timeAnchor), now - last <= window else { return 0 }
        return behind
    }

    private static func heroFor(_ item: HomeQueueItem, now: Int64) -> HomeHero {
        let f = item.franchise, part = item.part
        guard item.fresh > 0 else {
            return HomeHero(franchise: f, part: part, episode: item.episode, kind: .resume)
        }
        // The same count the NEW tag and the stories say: episodes out and unwatched on the part.
        let behind = item.fresh
        // The drop is named only under a backlog: with one episode out, "New episode" IS the drop.
        var drop: String?
        if behind > 1, let last = part.lastAired(now: now, anchor: f.timeAnchor) {
            drop = Copy.Progress.dropAired(episode: part.airedByNow(now: now, anchor: f.timeAnchor),
                                           when: TemporalCopy.aired(at: last, now: now, source: f.source))
        }
        return HomeHero(franchise: f, part: part, episode: item.episode, kind: .outNow(behind: behind), drop: drop)
    }
}

/// The composed feed, held by reference so a cache fill inside a body read never invalidates the
/// view (Schedule's `DerivedBox`).
@MainActor
final class HomeFeedBox {
    var key: AppModel.ScheduleFeedKey?
    var value = HomeFeed()
}

// MARK: - The bar's one moving fact

/// Whether the billboard has gone under the bar — written by the scroll probe, read only by the bar
/// (the app's rule: the scroll offset is never screen state).
@MainActor @Observable
final class HomeChrome {
    private(set) var solid = false

    @ObservationIgnored private var billboardBottom: CGFloat = 0
    @ObservationIgnored private var copyTop: CGFloat = .infinity

    private var barBottom: CGFloat { ThemeMetrics.topSafeInset + FeedMetrics.headerRow }

    /// The page's content top, in the window, and the billboard's height (0 without one).
    func track(contentTop y: CGFloat, billboard: CGFloat) {
        billboardBottom = y + billboard
        if billboard == 0 { copyTop = .infinity }
        update()
    }

    /// The billboard's lockup top, in the window: the bar takes the canvas the moment the copy
    /// reaches it — the art may pass under the glyphs on its veil, words may not (the badge and
    /// the episode read through the bar's icons otherwise).
    func trackCopy(top: CGFloat) {
        copyTop = top
        update()
    }

    private func update() {
        let next = copyTop < barBottom + 12 || billboardBottom < barBottom + 24
        if next != solid { solid = next }
    }
}

// MARK: - The bar

/// X's row, as the feed's: you on the left, the mark alone in the middle — the scroll-to-top — and
/// the schedule on the right. Over the billboard it is only its glyphs on the art's veil; once the
/// billboard has passed under it, the canvas and one physical pixel of rule.
struct HomeHeader: View {
    let chrome: HomeChrome
    /// The bar's ground once solid: the page's own top colour (the show's hue at canvas depth, or
    /// the canvas), so the bar is FLUSH with what it sits on — never a black lid over a tinted page.
    var ground: Color = ThemeColor.canvas
    let onProfile: () -> Void
    let onTop: () -> Void
    let onSchedule: () -> Void

    @Environment(AuthManager.self) private var auth

    var body: some View {
        ZStack {
            Button(action: onTop) {
                PreviouslyMark(width: FeedHeader.markWidth, style: .glyph, ink: ThemeColor.feedText)
                    .padding(.horizontal, ThemeSpace.x3)
                    .frame(minHeight: FeedMetrics.headerRow)
                    .contentShape(Rectangle())
            }
            .buttonStyle(FeedIconPressStyle())
            .accessibilityLabel(Copy.Feed.scrollToTop)
            HStack(spacing: 0) {
                Button(action: onProfile) {
                    AccountDisc(identity: auth.identity, diameter: 32, quiet: true)
                        .frame(width: FeedMetrics.actionHitHeight, height: FeedMetrics.actionHitHeight,
                               alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(FeedIconPressStyle())
                .accessibilityLabel(Copy.Feed.profile)
                Spacer(minLength: 0)
                Button(action: onSchedule) {
                    AppGlyph(systemName: "calendar")
                        .font(.title3)
                        .foregroundStyle(ThemeColor.feedText)
                        .frame(width: FeedMetrics.actionHitHeight, height: FeedMetrics.actionHitHeight,
                               alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(FeedIconPressStyle())
                .accessibilityLabel(Copy.Schedule.title)
            }
        }
        .padding(.horizontal, ThemeMetrics.gutter)
        .frame(height: FeedMetrics.headerRow)
        .background { HomeHeaderGround(chrome: chrome, ground: ground) }
    }
}

/// The bar's ground and rule — the only reader of `HomeChrome`.
private struct HomeHeaderGround: View {
    let chrome: HomeChrome
    let ground: Color

    var body: some View {
        ground
            .ignoresSafeArea(edges: .top)
            .overlay(alignment: .bottom) {
                Rectangle().fill(ThemeColor.feedSeparator).frame(height: FeedMetrics.hairline)
            }
            .opacity(chrome.solid ? 1 : 0)
            .animation(ThemeMotion.uiGentle, value: chrome.solid)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

// MARK: - The billboard

/// The next thing to watch, full bleed — the retired Today billboard's grammar, which the owner
/// asked back for Home ("let's make it like the full bleed art it was earlier", 26 Sep): the show's
/// POSTER (`billboardArt`, textless where the catalogue has one) composited whole in a frame that is
/// nearly its own shape, breathing (`ArtHeader(drift:)`) and stretching with a pull, the bar's veil
/// over its top and a scrim sized to the copy that lands on canvas; then, centred, the state in its
/// badge, the show's logo else its name, the episode, where you are, the drop, and the mark.
///
/// A mark is a small event, not a jump: the pill says "Watched" for a beat (`committing`), then
/// the count, the episode and the bar ROLL to the next one (numeric text, one spring), and a show
/// you have caught up on hands the frame to the next thing (`HomeView`'s handoff).
struct HomeBillboard: View {
    let hero: HomeHero
    let now: Int64
    let height: CGFloat
    /// The status bar and the bar's row: the veil protects it, and a titled poster starts under it.
    let band: CGFloat
    /// The mark is mid-flight: the pill wears its watched state until the write lands.
    var committing: Bool = false
    /// The palette colour of the art (`HomeView` resolves it: the page is painted from it too) and
    /// the ground the frame lands on — the show's hue at canvas depth.
    var tint: Color? = nil
    var landing: Color = ThemeColor.canvas
    let onOpen: () -> Void
    let onMark: () -> Void
    var onArtLoaded: (() -> Void)? = nil
    /// The lockup's top in the window, for the bar (`HomeChrome.trackCopy`).
    var onCopyTop: ((CGFloat) -> Void)? = nil

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lightness: Double?
    @State private var copyHeight: CGFloat = 220
    /// The lockup has arrived (once per billboard): the words rise in over the art, a beat apart.
    @State private var arrived = false

    var body: some View {
        let art = hero.franchise.billboardArt
        let strength = HeroProtection.strength(lightness: lightness)
        let h = height
        ZStack(alignment: .bottom) {
            Button(action: onOpen) {
                ArtHeader(url: art.url, height: h, tint: tint, scrimTop: 0, scrimBottom: 0,
                          focus: .top, portraitSource: art.portraitSource, drift: true,
                          ultraWide: art.ultraWide, onArtLoaded: onArtLoaded,
                          // A poster's own logotype is INK a veil cannot remove: a name set in
                          // type starts its poster under the bar (the old Today's rule).
                          topInset: hero.franchise.billboardName == .type ? band : 0,
                          groundDim: HeroProtection.groundDim(strength)) { EmptyView() }
            }
            .buttonStyle(.plain)
            // A pull stretches the picture up into the space it opens, from its foot — read from
            // geometry in the render pass (`visualEffect`), so the pull never re-runs a body.
            .visualEffect { content, proxy in
                let pull = max(0, proxy.frame(in: .scrollView).minY)
                return content
                    .scaleEffect(1 + pull / max(h, 1), anchor: .bottom)
            }
            .accessibilityLabel("\(badge), \(hero.franchise.displayTitle), \(line)")
            .accessibilityHint(Copy.Accessibility.opensTheShowHint)

            HeroCopyScrim(copyHeight: copyHeight, strength: strength, landing: landing)

            lockup
                .padding(.horizontal, ThemeMetrics.gutter)
                .padding(.bottom, ThemeSpace.x5)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { copyHeight = $0 }
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { onCopyTop?($0) }
        }
        .frame(height: h)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .top) { HeroTopVeil(band: band, ramp: 100, strength: strength) }
        .task(id: art.url) {
            _ = await PaletteCache.shared.resolve(url: art.url, maxPixel: 360)
            lightness = PaletteCache.shared.lightness(for: art.url)
        }
        .task {
            // A beat after the picture, the words: an arrival, not a page that was always there.
            guard !arrived else { return }
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 160))
            arrived = true
        }
    }

    /// One line of the lockup rising in, `index` beats after the first (Apple TV's billboard copy).
    private func arrival(_ index: Int) -> some ViewModifier {
        HomeArrival(shown: arrived, delay: Double(index) * 0.07, reduceMotion: reduceMotion)
    }

    private var lockup: some View {
        let f = hero.franchise
        let name = f.billboardName
        return VStack(spacing: ThemeSpace.x3) {
            // The words are the picture's, not controls: a tap on them is a tap on the billboard.
            VStack(spacing: ThemeSpace.x2) {
                HeroBadge(text: badge)
                    .contentTransition(.numericText(countsDown: true))
                    .modifier(arrival(0))
                if case .logo = name, name.hasGraphicLogo, !typeSize.isAccessibilitySize {
                    ArtworkLogo(name: name, title: f.displayTitle, height: 96)
                        .padding(.horizontal, ThemeSpace.x8)
                        .padding(.vertical, ThemeSpace.x1)
                        .modifier(arrival(1))
                } else {
                    Text(f.displayTitle)
                        .type(ThemeType.displayXL)
                        .foregroundStyle(ThemeColor.textPrimary)
                        .multilineTextAlignment(.center)
                        .lineLimit(typeSize.isAccessibilitySize ? 3 : 2)
                        .minimumScaleFactor(0.82)
                        .shadow(.art)
                        .modifier(arrival(1))
                }
                Text(line)
                    .type(ThemeType.heroMeta)
                    .foregroundStyle(ThemeColor.textPrimary.opacity(0.88))
                    .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                    .contentTransition(.numericText())
                    .shadow(.art)
                    .modifier(arrival(2))
                if let progress {
                    ProgressBar(value: progress, spoken: nil)
                        .frame(maxWidth: 200)
                        .padding(.top, ThemeSpace.x1)
                        .modifier(arrival(2))
                }
                if let drop = hero.drop {
                    Text(drop)
                        .type(ThemeType.feedSmall)
                        .foregroundStyle(ThemeColor.textPrimary.opacity(0.66))
                        .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                        .shadow(.art)
                        .modifier(arrival(3))
                }
            }
            .multilineTextAlignment(.center)
            .allowsHitTesting(false)
            if hero.canMark {
                ScheduleMarkPill(watched: committing,
                                 label: committing ? Copy.Progress.episodeWatched(hero.episode)
                                                   : Copy.Action.markEpisodeWatched(hero.episode),
                                 action: onMark)
                    .animation(ThemeMotion.pick(ThemeMotion.uiSnappy, reduceMotion: reduceMotion), value: committing)
                    .disabled(committing)
                    .modifier(arrival(4))
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    /// Where you are in the season — nothing on a season not started.
    private var progress: Double? {
        let part = hero.part
        let total = max(part.progressDenominator(now: now, anchor: hero.franchise.timeAnchor), part.progress)
        return total > 0 && part.progress > 0 ? Double(part.progress) / Double(total) : nil
    }

    /// The state, in the badge.
    var badge: String {
        let f = hero.franchise
        switch hero.kind {
        case .outNow(let behind):
            // BEHIND a broadcast that is still going; LEFT in a season that has finished — the old
            // Today's badge vocabulary ("4 EPISODES BEHIND", "13 EPISODES LEFT").
            guard behind > 1 else { return Copy.Home.newEpisode }
            return hero.part.isReleasing ? Copy.Progress.behind(behind) : Copy.Progress.left(behind)
        case .resume:
            return Copy.Home.continueWatching
        case .airing(let at):
            let delta = at - now
            if !f.timeAnchor.isDateOnly, delta >= 60 * Formatting.minuteMs,
               Formatting.dayDiff(ts: at, now: now, anchor: f.timeAnchor) == 0,
               Formatting.isEvening(hour: Formatting.localParts(at, anchor: f.timeAnchor).hour) {
                return Copy.Schedule.tonightAt(Formatting.fmtTime(at, anchor: f.timeAnchor))
            }
            return TemporalCopy.airs(at: at, now: now, source: f.source)
        }
    }

    /// "Season 4 · Episode 22" — the billboard stands alone, so it names the season.
    var line: String {
        hero.franchise.watchContext(part: hero.part, episode: hero.episode)
    }
}

/// A line of the billboard's copy arriving: 10 pt below and clear, then in place — on one gentle
/// curve, `delay` after the first. Under Reduce Motion it is simply there.
private struct HomeArrival: ViewModifier {
    let shown: Bool
    let delay: Double
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 10)
            .animation(reduceMotion ? nil : ThemeMotion.uiGentle.delay(delay), value: shown)
    }
}

// MARK: - The page's ground

/// The page under the billboard in the show's hue (26 Sep, "maybe add subtle gradient too", owner):
/// the colour the billboard's scrim lands on, held for a breath, then easing to canvas over half a
/// screen — with one faint pool of the tint's light where the first section sits. The show page's
/// ground (`DetailTint`, the `medium` strength the owner settled on 24 Sep), shorter: Home is not
/// the show's page, so the hue is where the billboard is and gone by This week. It scrolls with the
/// content, drawn once — no image, nothing per frame.
struct HomeGround: View {
    let tint: Color?
    let top: Color
    let billboard: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            top.frame(height: max(0, billboard))
            LinearGradient(stops: [.init(color: top, location: 0),
                                   .init(color: top, location: 0.18),
                                   .init(color: ThemeColor.canvas, location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 520)
                .overlay(alignment: .top) {
                    RadialGradient(colors: [(tint ?? .clear).opacity(DetailTint.groundPool), .clear],
                                   center: .init(x: 0.5, y: 0.1), startRadius: 0, endRadius: 320)
                        .blendMode(.plusLighter)
                }
            Spacer(minLength: 0)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Up next

/// One show in the queue as the LIBRARY'S poster card (`ArtworkPoster`, 150 pt, 2:3 — the card For
/// you's tiles are too): the poster whole, where you are as a bar right under it (Netflix's
/// Continue Watching), the show and the episode, a NEW tag on a fresh drop, and the mark as the
/// card's corner control — a check on the poster's glass, as For you's add is a plus. Posters are
/// the art every show has, anime included; the 16:9 card this replaced composited a cover in a box
/// for most of the queue ("Up Next visuals feel utter trash", owner, 26 Sep).
struct HomeUpNextTile: View {
    let item: HomeQueueItem
    let now: Int64
    /// The mark is mid-flight: the disc fills and the check lands before the tile moves on.
    var committing: Bool = false
    let onOpen: () -> Void
    let onMark: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    private var poster: String? { item.part.portraitArt ?? item.franchise.portraitArt }

    /// Where you are in the season — nothing on a season not started.
    private var ratio: Double? {
        let total = max(item.part.progressDenominator(now: now, anchor: item.franchise.timeAnchor), item.part.progress)
        return total > 0 && item.part.progress > 0 ? Double(item.part.progress) / Double(total) : nil
    }

    private var line: String { item.franchise.watchContext(part: item.part, episode: item.episode) }

    var body: some View {
        let f = item.franchise
        ArtworkPoster(url: poster, name: .type, title: f.displayTitle, detailsInBand: true,
                      cornerMark: AnyView(
                        HomeMarkDisc(committing: committing,
                                     label: Copy.Action.markEpisodeWatched(item.episode), action: onMark)
                      ),
                      fixedAspect: 2.0 / 3.0, onOpen: onOpen,
                      openLabel: "\(f.displayTitle), \(line)") {
            VStack(alignment: .leading, spacing: ThemeSpace.x2) {
                // The bar sits right under the picture, the full width of the card — never over
                // the art, where it would fight the poster's own lettering.
                if let ratio {
                    ProgressBar(value: ratio, spoken: nil)
                        .accessibilityHidden(true)
                }
                PosterCaptionText(title: f.displayTitle.shelfShortened(fitting: 26), fact: line)
                    .contentTransition(.numericText())
            }
        }
        .overlay(alignment: .topLeading) {
            if item.fresh > 0 {
                HomeNewTag(text: Copy.Stories.ringTag(item.fresh))
                    .padding(ThemeSpace.x2)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: ForYouShelves.tileWidth(typeSize))
    }
}

/// The mark on a poster's corner — For you's add disc, with a check: glass at rest; while the write
/// lands, the accent disc with the check drawn in `onAccent` (the owned mark), one pulse.
struct HomeMarkDisc: View {
    var committing: Bool = false
    let label: String
    let action: () -> Void

    @ScaledMetric(relativeTo: .caption) private var disc: CGFloat = 26
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(committing ? ThemeColor.accent : ThemeColor.scrimStrong)
                Circle().strokeBorder(committing ? .clear : ThemeColor.posterEdge, lineWidth: FeedMetrics.hairline)
                AppGlyph(systemName: "checkmark")
                    .font(.system(size: disc * 0.46, weight: .bold))
                    .foregroundStyle(committing ? ThemeColor.onAccent : ThemeColor.textPrimary)
            }
            .frame(width: disc, height: disc)
            .scaleEffect(committing && !reduceMotion ? 1.12 : 1)
            .animation(ThemeMotion.pick(ThemeMotion.uiMilestone, reduceMotion: reduceMotion), value: committing)
            .frame(width: max(44, disc + 12), height: max(44, disc + 12))
            .contentShape(Circle())
        }
        .buttonStyle(OverArtPressStyle())
        .padding(-ThemeSpace.x1)
        .disabled(committing)
        .accessibilityLabel(label)
    }
}

/// The NEW tag on a fresh drop's art — the episode list's tag (`onAccent` on `accent`): amber is
/// STATE here, never an action.
struct HomeNewTag: View {
    let text: String

    var body: some View {
        Text(text)
            .type(ThemeType.feedEyebrow)
            .foregroundStyle(ThemeColor.onAccent)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(ThemeColor.accent, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .accessibilityHidden(true)
    }
}

// MARK: - Routes

/// Home's own pages, pushed as values on the Home tab's path (re-selecting Home clears them).
enum HomeRoute: Hashable, Sendable {
    /// The whole Schedule — the bar's calendar and "This week ›".
    case schedule
}
