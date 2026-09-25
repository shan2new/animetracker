import SwiftUI

// TOP PICK FOR YOU (ios-spec §3.3): the one best recommendation as a card that sells it — key
// art, the show's logo (or its name in type), WHY, and a real Add. The launchpad opens on it; the
// "Recommended for you" shelf below carries the rest of the list (`scopedRecommendations.dropFirst()`).
//
// Two targets, never one inside the other: the CARD opens the show (a `Button` whose label is the
// art and the copy), and the ADD is its own `Button` layered over the card's foot. A capsule drawn
// inside the card's label was a picture of a button that opened the page (the spike's).

struct DiscoverTopPick: View, @MainActor Equatable {
    let item: RecommendationItem
    let reason: RecommendationItem.Reason
    let onOpen: () -> Void

    @Environment(AppModel.self) private var appModel
    @Environment(\.dynamicTypeSize) private var typeSize

    /// The foot row's measured height — the card's copy reserves exactly that much room under it,
    /// so the Add capsule never sits on the reason line at any text size.
    @State private var footHeight: CGFloat = Metrics.footEstimate

    /// Equatable on what the card SHOWS. The launchpad's body re-runs on every keystroke and on
    /// the field's focus (`DiscoverView`), and the `onOpen` closure alone would rebuild the card
    /// under the keyboard's animation each time. Ownership and the resolving spinner are read
    /// from `AppModel` inside the body, so observation still updates them directly.
    static func == (a: DiscoverTopPick, b: DiscoverTopPick) -> Bool {
        a.item.key == b.item.key && Copy.ForYou.reason(a.reason) == Copy.ForYou.reason(b.reason)
    }

    private var isAX: Bool { typeSize.isAccessibilitySize }
    private var width: CGFloat { ThemeMetrics.windowWidth - 2 * ThemeMetrics.gutter }
    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: ThemeRadius.focusCard, style: .continuous)
    }

    var body: some View {
        let owned = appModel.isOwned(item)
        let resolving = appModel.resolvingRecommendations.contains(item.key)
        let reasonText = Copy.ForYou.reason(reason)
        ZStack(alignment: .bottomLeading) {
            Button(action: onOpen) {
                cardLabel(reasonText: reasonText)
            }
            .buttonStyle(OverArtPressStyle())
            .accessibilityLabel([Copy.Discover.topPick, item.displayTitle, reasonText, meta]
                .filter { !$0.isEmpty }
                .joined(separator: ", "))
            .accessibilityHint(Copy.Accessibility.opensTheShowHint)

            footRow(owned: owned, resolving: resolving)
                .padding(ThemeSpace.x5)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in
                    if abs(h - footHeight) > 0.5 { footHeight = h }
                }
        }
        .frame(width: width)
        .contextMenu { ForYouMenu(item: item, reason: reason, onOpen: onOpen) }
    }

    // MARK: The card (the open target)

    private func cardLabel(reasonText: String) -> some View {
        let art = cardArt
        // The COPY sizes the card (at least `topPickAspect` of its width, taller when the text
        // needs it at the accessibility sizes); the art is its background, so it always fills
        // exactly the card — a ZStack of flexible layers under a `minHeight` frame is sized to
        // its copy and floated inside the frame instead.
        return VStack(alignment: .leading, spacing: Metrics.copySpacing) {
            HeroBadge(text: Copy.Discover.topPick)
            name
            Text(reasonText)
                .type(ThemeType.heroMeta)
                .foregroundStyle(ThemeColor.textPrimary.opacity(Metrics.reasonInk))
                .lineLimit(isAX ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)
            // The foot row (the Add and the facts) is drawn OVER this space by the card's
            // parent, as a separate target.
            Color.clear
                .frame(height: max(0, footHeight - ThemeSpace.x5) + Metrics.footGap)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, ThemeSpace.x5)
        .padding(.top, ThemeSpace.x5)
        .frame(width: width, alignment: .leading)
        .frame(minHeight: width * FeedMetrics.topPickAspect, alignment: .bottomLeading)
        .background {
            ZStack {
                shape.fill(ThemeColor.surfaceRaised)
                LandscapeArt(url: art.url, portraitSource: art.portraitSource,
                             maxPixel: Metrics.artMaxPixel, ultraWide: art.ultraWide)
                // Art protection, not a colour: the copy's ground under a photograph.
                LinearGradient(stops: Metrics.scrim, startPoint: .top, endPoint: .bottom)
            }
            .accessibilityHidden(true)
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(ThemeColor.posterEdge, lineWidth: FeedMetrics.hairline))
        .contentShape(shape)
    }

    /// The show's own logo over landscape key art; the name in type where there is no logo, where
    /// the art is a (titled) poster composited whole, and at the accessibility sizes.
    @ViewBuilder
    private var name: some View {
        if !isAX, !cardArt.portraitSource, let logo = item.stub?.billboardLogo?.url {
            RemoteImageView(url: logo, contentMode: .fit, maxPixel: Metrics.logoMaxPixel,
                            alignment: .leading, placeholderHidden: true)
                .frame(maxWidth: width * Metrics.logoWidthShare,
                       maxHeight: FeedMetrics.topPickLogoHeight, alignment: .leading)
                .padding(.vertical, ThemeSpace.x0_5)
                .accessibilityHidden(true)
        } else {
            Text(item.displayTitle)
                .type(ThemeType.displayL)
                .foregroundStyle(ThemeColor.textPrimary)
                .lineLimit(isAX ? nil : 2)
                .minimumScaleFactor(0.82)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Landscape key art, filled. An AniList banner (4.75:1) filled into a card this square shows
    /// a sliver of its middle — a pair of eyes — so a show whose only landscape is one draws its
    /// poster whole on its own blurred ground instead (`LandscapeArt(portraitSource:)`).
    private var cardArt: WideArt {
        let portrait = item.stub?.portraitArt ?? item.images?.portrait
        if let wide = item.stub?.wideArt, wide.url != nil, !wide.ultraWide { return wide }
        return WideArt(landscape: nil, portrait: portrait)
    }

    // MARK: The foot (a separate target)

    @ViewBuilder
    private func footRow(owned: Bool, resolving: Bool) -> some View {
        let layout = isAX
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: ThemeSpace.x2))
            : AnyLayout(HStackLayout(alignment: .center, spacing: ThemeSpace.x3))
        layout {
            addButton(owned: owned, resolving: resolving)
            if !meta.isEmpty {
                // Part of the card's spoken label; taps fall through to the card beneath.
                Text(meta)
                    .type(ThemeType.rowMeta)
                    .foregroundStyle(ThemeColor.textSecondary)
                    .lineLimit(isAX ? 2 : 1)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }

    /// "Add to Planned" → the lane's receipt (`addRecommendation` → `addToLibrary`). While the
    /// title is being materialised the capsule holds a spinner at full strength; once it is
    /// yours it states so, disabled.
    private func addButton(owned: Bool, resolving: Bool) -> some View {
        Button {
            appModel.addRecommendation(item)
        } label: {
            ZStack {
                Label(owned ? Copy.ForYou.addedToPlanned : Copy.ForYou.addToPlanned,
                      systemImage: owned ? "checkmark" : "plus")
                    .lineLimit(1)
                    .opacity(resolving ? 0 : 1)
                if resolving {
                    ProgressView().tint(ThemeColor.onAccent)
                }
            }
        }
        .buttonStyle(PrimaryButtonStyle2())
        .fixedSize(horizontal: !isAX, vertical: false)
        .disabled(owned)
        .allowsHitTesting(!resolving)
        .accessibilityLabel(owned ? Copy.ForYou.addedToPlanned
                                  : "\(Copy.ForYou.addToPlanned), \(item.displayTitle)")
        .accessibilityHint(owned ? "" : Copy.ForYou.addHint)
    }

    /// Kind · year · first genre.
    private var meta: String {
        [item.source == .tmdb ? Copy.Filter.tv : Copy.Filter.anime,
         item.year.map(String.init),
         item.genres.first]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: FactLine.separator)
    }
}

/// Sizes and stops with no token. Each says why it is the number it is.
private enum Metrics {
    /// The card is the width of the content column; its art decodes at about 3× that.
    static let artMaxPixel: CGFloat = 1400
    /// A logo's decode: it is drawn at most ~62 % of the card wide.
    static let logoMaxPixel: CGFloat = 700
    static let logoWidthShare: CGFloat = 0.62
    /// Badge → name → reason, the billboard lockup's rhythm at card scale.
    static let copySpacing: CGFloat = 6
    /// The reason sits a step under the name in ink, not in size (the lockup's one line).
    static let reasonInk: Double = 0.82
    /// Room between the reason and the Add capsule.
    static let footGap: CGFloat = ThemeSpace.x2
    /// The capsule's own height plus the card's padding, before the first measurement.
    static let footEstimate: CGFloat = 48 + ThemeSpace.x5 * 2
    /// The copy's ground: clear over the top quarter of the art, then down to near-black at the
    /// foot (the spike's stops, measured against a bright backdrop).
    static let scrim: [Gradient.Stop] = [
        .init(color: .clear, location: 0.25),
        .init(color: .black.opacity(0.55), location: 0.62),
        .init(color: .black.opacity(0.88), location: 1),
    ]
}
