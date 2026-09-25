import SwiftUI

// The feed's tokens (25 Sep build). The Today feed, the post page, Activity and the composer are set
// on X's measured iOS grid and palette, and the stories, the people's discs, the bursts and the rating
// track wear the Align film's five gels. The spike carried these as literals in four places; they
// live here now, and a screen references only these names (never a hex, never a point size).

// MARK: - Colour

extension ThemeColor {
    // X's iOS palette, measured at 393 pt (25 Sep). The feed, thread, activity and composer only —
    // the rest of the app keeps its own ramp.
    static let feedText = Color(hex: 0xE7E9EA)
    /// X's grey, LIFTED: #71767B is 4.58:1 on X's #000 but 4.34:1 on this canvas (#09090B) and
    /// 3.88:1 on `feedCard` — under AA for the 13–16-pt stamps, meta lines and excerpts it sets.
    /// #7D8287 keeps X's hue at 5.13:1 on the canvas and 4.58:1 on `feedCard` (computed).
    static let feedSecondary = Color(hex: 0x7D8287)
    static let feedSeparator = Color(hex: 0x2F3336)
    static let feedCard = Color(hex: 0x16181C)
    static let feedField = Color(hex: 0x202327)
    /// A row's ground while pressed (X lifts the row a shade; no scale).
    static let feedPressed = Color.white.opacity(0.045)
    /// The like: the icon's rose gel — warmth, not news (red) and not a fact (amber).
    static let like = Color(hex: 0xF0467F)
    /// The rating sticker's ink on its white card.
    static let stickerInk = Color(hex: 0x16151A)
    static let stickerCard = Color.white
    /// Hairline around a show avatar.
    static let avatarEdge = Color.white.opacity(0.1)
    /// Hairline around a person's monogram disc.
    static let discEdge = Color.white.opacity(0.14)
    /// A story ring once its reel has been watched: a quiet grey circle where the gels were.
    static let storyRingSeen = Color.white.opacity(0.22)
    /// Instagram's double-tap heart over a picture — white, whatever the art.
    static let likeOverArt = Color.white
    /// The Activity bell's unread dot. The same red as NEWS (`ThemeColor.news`) because it says the
    /// same thing — something new is waiting — and it is that red's only use outside the NEW tags.
    /// Named for its role so `news` keeps its rule. The rows themselves mark unread with a ground
    /// (`accentSoft`, state), never with an amber glyph.
    static let unreadDot = ThemeColor.news
}

// MARK: - The five gels

/// The Align film's five gels (gold → amber → coral → rose → violet) — the stories ring, the
/// people's monogram discs, the bursts, the rating track, CaughtUpMarker. They are the brand's
/// light, and in the ring they still read as "stories" (Instagram's own ring runs the same way).
enum ThemeGel {
    static let gold = Color(hex: 0xFFCC57), amber = Color(hex: 0xFF8F33), coral = Color(hex: 0xFA5440)
    static let rose = Color(hex: 0xE63D85), violet = Color(hex: 0x8F4DF5)
    /// The five, in the icon's order.
    static let all: [Color] = [gold, amber, coral, rose, violet]
    /// The unseen story ring (and CaughtUpMarker's ring): the gels round the circle and back, so
    /// the seam at the top is gold meeting gold.
    static let ring = AngularGradient(colors: [gold, amber, coral, rose, violet, rose, amber, gold],
                                      center: .center, startAngle: .degrees(-40), endAngle: .degrees(320))
    /// The rating slider's track.
    static let track = LinearGradient(colors: all, startPoint: .leading, endPoint: .trailing)

    /// A person's disc colour: stable per user id (FNV-1a 32 of the id's UTF-8, mod 5). Not data —
    /// a colour, so the same person wears the same gel on every device and every launch.
    static func color(forUserId id: String) -> Color {
        var hash: UInt32 = 0x811C_9DC5
        for byte in id.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 0x0100_0193
        }
        return all[Int(hash % UInt32(all.count))]
    }
}

// MARK: - Metrics

enum FeedMetrics {
    /// Row side inset. With the 44-pt avatar and the 8-pt gap, the text column starts at 62 (X's).
    static let inset: CGFloat = 10
    /// A show's or a person's avatar in a row.
    static let avatar: CGFloat = 44
    /// Avatar → text column.
    static let gap: CGFloat = 8
    static let rowTop: CGFloat = 12, rowBottom: CGFloat = 6
    /// Reply / like / remind slots on the action bar.
    static let actionSlot: CGFloat = 68
    /// Save / share slots (the hit area is still 44).
    static let actionSlotSmall: CGFloat = 34
    /// Every action-bar target (the spike's were 36).
    static let actionHitHeight: CGFloat = 44
    /// Action glyphs; rows scale them with `@ScaledMetric(relativeTo: .footnote)`, capped at
    /// `actionGlyph * actionGlyphMaxScale` so the bar stays one row at the accessibility sizes.
    static let actionGlyph: CGFloat = 17, actionGlyphLarge: CGFloat = 19
    static let actionGlyphMaxScale: CGFloat = 1.6
    static let mediaRadius: CGFloat = 12
    static let noteRadius: CGFloat = 12
    /// A show wears a rounded square (X's organisation avatar), a person a circle.
    static let showCornerRatio: CGFloat = 0.22
    /// X's rule and border: one physical pixel (`ThemeMetrics.pixel`), never 0.5 pt or 1 pt — every
    /// separator, media edge, note box and capsule outline in the feed's surfaces uses it.
    static var hairline: CGFloat { ThemeMetrics.pixel }
    /// `FeedHeader.height` = headerRow + headerTabs + hairline.
    static let headerRow: CGFloat = 44, headerTabs: CGFloat = 44
    /// Instagram's tray, measured off the owner's screenshot at 393 pt (25 Sep): a 92-pt ring, a
    /// 3.4-pt stroke, a 2.4-pt gap, an 80-pt photo, 12 pt between rings. The build's 66 read as
    /// a row of badges ("Stories circle are much bigger and better", owner).
    static let storyBubble: CGFloat = 92, storyBubbleSpacing: CGFloat = 12, storyNameWidthExtra: CGFloat = 8
    /// The ring's NEW tag (Instagram's LIVE tag): 18 tall, a 4-pt corner, cut out of the ring by a
    /// 2-pt rim of the canvas, its middle on the ring's bottom edge.
    static let ringTagHeight: CGFloat = 18, ringTagRadius: CGFloat = 4, ringTagRim: CGFloat = 2
    static let pillHeight: CGFloat = 38, pillAvatar: CGFloat = 22
    static let caughtUpRing: CGFloat = 58
    static let composeAvatar: CGFloat = 40, replyBarAvatar: CGFloat = 34, replyFieldHeight: CGFloat = 36
    static let personDisc: CGFloat = 40
    static let storyFrameSeconds: Double = 6
    static let storyHoldDelay: Duration = .milliseconds(220)
    /// Discover's top pick card: h = w × aspect.
    static let topPickAspect: CGFloat = 1.02
    static let topPickLogoHeight: CGFloat = 64
    static let genreTileHeight: CGFloat = 112

    // Press feedback (FeedComponents' press styles).
    /// An action-bar icon's dip while the finger is down.
    static let iconPressScale: CGFloat = 0.86
    /// A story bubble's dip while the finger is down.
    static let bubblePressScale: CGFloat = 0.93
    /// A trailer still at or under this width is YouTube's grey "no frame" placeholder (120×90),
    /// served with a 200 for some uploads — `ChainedRemoteImage` moves on to the next candidate.
    static let stillPlaceholderMaxWidth: CGFloat = 120
    /// The pixel size an avatar's picture is decoded at for its subject crop (drawn at 22–66 pt).
    static let avatarDecodePixels: CGFloat = 480
}

// MARK: - Type

extension ThemeType {
    // X's type is SF Pro; these are TEXT STYLES so they scale with Dynamic Type (the spike's
    // `.system(size:)` did not). Point sizes at the default content size in comments.
    static let feedName = TypeToken(font: .system(.callout, weight: .bold), tracking: 0)          // 16
    static let feedMeta = TypeToken(font: .system(.callout), tracking: 0)                           // 16 grey
    static let feedBody = TypeToken(font: .system(.callout), tracking: 0)                           // 16
    static let feedBodyLarge = TypeToken(font: .system(.body), tracking: 0)                         // 17 — the post page
    static let feedNote = TypeToken(font: .system(.subheadline), tracking: 0)                       // 15
    static let feedNoteTitle = TypeToken(font: .system(.subheadline, weight: .bold), tracking: 0)   // 15
    static let feedSmall = TypeToken(font: .system(.footnote), tracking: 0)                         // 13
    static let feedCount = TypeToken(font: .system(.footnote).monospacedDigit(), tracking: 0)      // 13
    static let feedCountLarge = TypeToken(font: .system(.subheadline).monospacedDigit(), tracking: 0) // 15
    /// X's tabs, measured (round 3): bold 16 in BOTH states — only the ink says which is selected,
    /// so the word never reflows under the sliding underline.
    static let feedTab = TypeToken(font: .system(.callout, weight: .bold), tracking: 0)            // 16
    static let feedModuleTitle = TypeToken(font: .system(.title3, weight: .heavy), tracking: 0)     // 20
    /// X's page title beside its back arrow ("Post"): bold 20.
    static let feedPageTitle = TypeToken(font: .system(.title3, weight: .bold), tracking: 0)         // 20
    static let feedPill = TypeToken(font: .custom("Outfit-SemiBold", size: 14, relativeTo: .subheadline), tracking: 0)
    static let storyName = TypeToken(font: .system(.caption), tracking: 0)                          // 12
    /// The ring's NEW tag: Instagram's LIVE tag, heavy caps at a fixed size (the tag is part of the
    /// ring, which does not grow with Dynamic Type).
    static let storyRingTag = TypeToken(font: .system(size: 10, weight: .heavy), tracking: 0.6)
    static let storyReply = TypeToken(font: .system(.subheadline), tracking: 0)                     // 15
    static let composeField = TypeToken(font: .system(.body), tracking: 0)                          // 17
    /// A person's monogram at the 40-pt disc (`FeedMetrics.personDisc`). Other discs use
    /// `discMonogram(diameter:)`, which keeps the same letter-to-disc proportion. FIXED size, as
    /// `AccountDisc`'s is: the disc does not grow with Dynamic Type, so a letter that did would
    /// spill past its circle at the accessibility sizes.
    static let discMonogram = TypeToken(font: .custom("Outfit-SemiBold", fixedSize: discMonogramSize), tracking: 0)
    static let stickerQuestion = TypeToken(font: .custom("Outfit-SemiBold", size: 19, relativeTo: .headline), tracking: 0)

    /// `discMonogram` scaled to a disc of `diameter` points (`size / 40` ≈ 0.42 × the disc), so a
    /// 22-pt pill face and a 44-pt comment author carry the same proportion as the 40-pt disc.
    static func discMonogram(diameter: CGFloat) -> TypeToken {
        let size = discMonogramSize * max(diameter, 1) / FeedMetrics.personDisc
        return TypeToken(font: .custom("Outfit-SemiBold", fixedSize: size), tracking: 0)
    }

    private static let discMonogramSize: CGFloat = 17
}

// MARK: - Motion and elevation

extension ThemeMotion {
    /// X's row press: the ground appears at once under the finger and fades on release.
    static let feedPressRelease = Animation.easeOut(duration: 0.28)
    /// A story ring while its reel loads: dashes turning once every 1.1 s (Instagram's wait).
    /// Never under Reduce Motion — the dashes hold still there.
    static let feedRingSpin = Animation.linear(duration: 1.1).repeatForever(autoreverses: false)
}

extension ShadowToken {
    /// The double-tap heart's contact shadow over a picture (a transient glyph, not a card).
    static let likeOverArt = ShadowToken(color: .black.opacity(0.28), radius: 14, y: 4)
}
