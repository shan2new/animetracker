import SwiftUI

// "Today" tab — the v4 "Editorial" redesign (Claude Design: explorations/today-v4.html).
//  - a full-bleed 432pt HERO under the status bar: cover art with a top-biased crop, top+bottom
//    scrims melting into the app background, a ghost chip, a big Outfit display title, a mono-caps
//    tracker meta line ("S2 E6 · AIRED 2H AGO · 2 TO CATCH UP"), and dual CTAs
//    ("Mark E6 watched" = catch up to newest, + ghost "Details");
//  - the wordmark + avatar float pinned over the hero (the greeting header is retired);
//  - the NOW BAR: a persistent Live-Activity-style strip pinned under the wordmark — pulse dot,
//    26pt thumb, show token, and ONE big "when" value (LIVE "OUT NOW" / NEXT countdown or day
//    word). It mirrors `AppModel.nowBarItem` (same fact as the lock-screen Live Activity) and
//    collapses to nothing when idle. When the bar's franchise IS a hero page's franchise, that
//    hero's meta line drops its time fragment — one fact, one place, one size;
//  - hero pages full-width with animated pill dots; the ladder (new → continue → up next) stays;
//  - "Currently watching" shelf: 108×152 posters, mono captions, trailing edge fade, See-all card.
// Source rule unchanged: anime may show clock times/relative hours; TV never does.
struct TodayView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(AuthManager.self) private var auth
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onOpenDetail: (_ franchiseId: String, _ zoomID: String) -> Void
    var onSeeAllWatching: () -> Void = {}

    private var now: Int64 { appModel.now }
    @State private var showProfile = false
    @State private var heroPage: String?
    @State private var nowBarPulse = false

    private static let heroCap = 3
    private static let shelfCap = 10
    private static let heroHeight: CGFloat = 432
    /// Extra art height beyond the hero window — the crop shows the image's upper region
    /// (faces usually live in a poster's top third), standing in for the mock's hand-tuned focus.
    private static let heroCropOverflow: CGFloat = 80

    var body: some View {
        GeometryReader { geo in
            let topInset = geo.safeAreaInsets.top
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if appModel.loading && appModel.library.isEmpty {
                        Loader().padding(.top, topInset + 60)
                    } else if appModel.loadError && appModel.libraryEmpty {
                        EmptyStateView(
                            title: "Couldn't load your shows",
                            message: "The server couldn't be reached. Check your connection and try again.",
                            ctaLabel: "Retry",
                            onCta: { Task { await appModel.reload() } }
                        )
                        .padding(.top, topInset + 40)
                    } else if appModel.libraryEmpty && !appModel.loading {
                        EmptyStateView(
                            title: "Welcome to Previously.",
                            message: "Your airing-first tracker. Add shows you're watching and we'll tell you exactly what dropped and what's next. Use the Add tab to get started."
                        )
                        .padding(.top, topInset + 40)
                    } else if heroItems.isEmpty && shelf.isEmpty && !appModel.loading {
                        EmptyStateView(title: "You're all caught up", message: allCaughtUpBody)
                            .padding(.top, topInset + 40)
                    } else {
                        if appModel.loadError {
                            RetryBanner { Task { await appModel.reload() } }
                                .padding(.horizontal, Theme.Space.gutter)
                                // Clear the pinned now bar when it's present.
                                .padding(.top, topInset + (appModel.nowBarItem == nil ? 8 : 64))
                        }
                        heroSection
                        if heroItems.count > 1 { heroDots.padding(.top, 10) }
                        if !shelf.isEmpty { shelfSection.padding(.top, 22) }
                    }
                }
                .padding(.bottom, 140)
                .animation(.uiGentle, value: appModel.loading)
                .animation(.uiGentle, value: appModel.loadError)
                .animation(.uiSmooth, value: heroItems.map(\.franchise.id))
                .animation(.uiSmooth, value: shelf.map(\.id))
            }
            .ignoresSafeArea(edges: .top)
            .scrollIndicators(.hidden)
            .scrollContentBackground(.hidden)
            .background(AppBackground())
            .overlay(alignment: .top) {
                VStack(alignment: .leading, spacing: 10) {
                    brandHeader
                    if let item = appModel.nowBarItem,
                       let f = appModel.franchise(id: item.franchiseId) {
                        nowBar(f, item: item)
                            .padding(.horizontal, Theme.Space.gutter)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(.top, 10)
                .animation(.uiSmooth, value: appModel.nowBarItem)
            }
            .refreshable {
                await appModel.reload()
                if !appModel.loadError { Haptics.impact(.light) }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showProfile) { ProfileView() }
    }

    // MARK: brand header (pinned over the hero)

    private var brandHeader: some View {
        HStack {
            PreviouslyMark(width: 16, detail: .none)
                .padding(.trailing, 2)
            (Text("Previously") + Text(".").foregroundStyle(Theme.accent))
                .scaledFont(19, weight: .bold)
                .tracking(0.2)
                .shadow(color: .black.opacity(0.6), radius: 7, y: 1)
            Spacer()
            Button { showProfile = true } label: {   // navigation → silent per HIG
                Text(auth.avatarInitial)
                    .scaledFont(14, weight: .bold)
                    .foregroundStyle(Theme.background)
                    .frame(width: 34, height: 34)
                    .background(
                        LinearGradient(colors: [Theme.accent, Color(hex: 0xC9702E)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: Circle()
                    )
                    .overlay(Circle().stroke(Color.white.opacity(0.28), lineWidth: 1.5))
                    .shadow(color: .black.opacity(0.45), radius: 7, y: 2)
            }
            .buttonStyle(SpringPressButtonStyle(scale: 0.92))
        }
        .padding(.horizontal, Theme.Space.gutter)
    }

    // MARK: now bar

    /// The persistent answer to "when" — Live-Activity compact anatomy on a material plate:
    /// [dot] [thumb] [SHOW · S2 E7 / sub-line] ──── [one big value]. The big slot always answers
    /// *when* at the fidelity the source supports: anime gets a real countdown or OUT NOW with a
    /// clock beneath; TV gets day words only — never a clock, never a pulse (its 17:00 UTC
    /// instant is synthesized). Idle = not rendered at all; an ever-present "nothing airing"
    /// strip would turn Today's calmest state into a nag.
    private func nowBar(_ f: Franchise, item: AppModel.NowBarItem) -> some View {
        let vm = CardModel(franchise: f, action: .none, now: now)
        let live = item.state == .live
        let (big, sub) = nowBarCopy(f, vm: vm, item: item)
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return Button { onOpenDetail(f.id, "nowbar/\(f.id)") } label: {   // navigation → silent per HIG
            HStack(spacing: 10) {
                nowBarDot(live: live, pulses: live && vm.source == .anilist)
                Thumb(cover: vm.cover, width: 26, height: 26, radius: 6)
                VStack(alignment: .leading, spacing: 2) {
                    Text(nowBarTitle(vm, live: live))
                        .scaledFont(10, weight: .semibold, monospacedDigit: true)
                        .tracking(0.8)
                        .lineLimit(1)
                        .foregroundStyle(Theme.text72)
                    Text(sub)
                        .scaledFont(9.5, weight: .medium, monospacedDigit: true)
                        .tracking(0.8)
                        .lineLimit(1)
                        .foregroundStyle(live ? Theme.accent : Theme.text50)
                }
                Spacer(minLength: 10)
                Text(big)
                    .scaledFont(24, weight: .bold, monospacedDigit: true)
                    .tracking(-0.5)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(Theme.accent)
                    .contentTransition(.numericText())
                    .animation(.uiGentle, value: big)
            }
            .padding(.leading, 12).padding(.trailing, 14).padding(.vertical, 9)
            .background {
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    // LIVE: a whisper of accent under the stroke — tinted, not shouting.
                    if live { shape.fill(Theme.accent.opacity(0.10)) }
                }
            }
            .overlay(shape.stroke(live ? Theme.accentBorder : Theme.hairlineStrong, lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
        }
        .buttonStyle(SpringPressButtonStyle(scale: 0.97))
    }

    /// Schedule's `.live` node treatment, at bar scale: a slow breath on a gradient halo
    /// (compositor-cheap scale/opacity), frozen at rest under Reduce Motion. The halo mounts
    /// only while pulsing, so its `onAppear` re-arms the animation on every LIVE entry.
    private func nowBarDot(live: Bool, pulses: Bool) -> some View {
        ZStack {
            if pulses {
                Circle()
                    .fill(RadialGradient(colors: [Theme.accent.opacity(0.5), Theme.accent.opacity(0)],
                                         center: .center, startRadius: 1, endRadius: 11))
                    .frame(width: 22, height: 22)
                    .scaleEffect(nowBarPulse ? 1.25 : 0.85)
                    .opacity(nowBarPulse ? 1 : 0.6)
                    .onAppear {
                        nowBarPulse = false
                        guard !reduceMotion else { return }
                        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                            nowBarPulse = true
                        }
                    }
            }
            Circle()
                .fill(live ? Theme.accent : Theme.text36)
                .frame(width: 8, height: 8)
                .shadow(color: live ? Theme.accent.opacity(0.7) : .clear, radius: 4)
        }
        .frame(width: 11, height: 11)   // layout footprint stays the dot; the halo overflows
    }

    /// "FRIEREN: BEYOND JOURNEY'S END · S2 E7" — the episode half is the drop for LIVE, the
    /// next-to-air for NEXT.
    private func nowBarTitle(_ vm: CardModel, live: Bool) -> String {
        let episode = live
            ? (vm.airedEpisodes > 0 ? "E\(vm.airedEpisodes)" : "")
            : (vm.nextEp.map { "E\($0)" } ?? "")
        let token = [vm.seasonToken(), episode].filter { !$0.isEmpty }.joined(separator: " ")
        return token.isEmpty ? vm.title.uppercased() : "\(vm.title.uppercased()) · \(token)"
    }

    /// (big slot, sub-line). The big slot is ONE isolated value — never a serialized string;
    /// the sub-line carries the supporting clause.
    private func nowBarCopy(_ f: Franchise, vm: CardModel, item: AppModel.NowBarItem) -> (String, String) {
        switch item.state {
        case .live:
            // The big slot holds a VALUE, never a status word — a display-size "OUT NOW" reads
            // as a shouting badge. Availability lives in the small caps sub-line.
            if vm.source == .anilist {
                let time = Formatting.fmtTime(item.at, anchor: f.timeAnchor).uppercased()
                let sub = ["OUT NOW", time].filter { !$0.isEmpty }.joined(separator: " · ")
                return (vm.airedAgo.isEmpty ? "now" : vm.airedAgo, sub)
            }
            // TV: a whole-day fact. Several episodes landing at once is a drop, not an episode.
            if vm.progress == 0 && vm.airedEpisodes > 1 { return ("TODAY", "SEASON DROP · OUT NOW") }
            return ("TODAY", "NEW EPISODE · OUT NOW")
        case .next:
            if vm.source == .anilist {
                let countdown = Formatting.fmtCountdown(target: item.at, now: now, anchor: f.timeAnchor)
                let time = Formatting.fmtTime(item.at, anchor: f.timeAnchor).uppercased()
                let dayWord: String
                if f.dayDiff(of: item.at, now: now) == 0 {
                    let hour = Formatting.localParts(item.at, anchor: f.timeAnchor).hour
                    dayWord = Formatting.isEvening(hour: hour) ? "TONIGHT" : "TODAY"
                } else {
                    dayWord = Formatting.fmtDay(ts: item.at, now: now, anchor: f.timeAnchor).uppercased()
                }
                return (countdown, "AIRS \(time) \(dayWord)")
            }
            let day = vm.dayWordLong.uppercased()
            let span = vm.relClock.map { " · IN \($0.uppercased())" } ?? ""
            return (day.isEmpty ? "SOON" : day, "NEW EPISODE\(span)")
        }
    }

    private var allCaughtUpBody: String {
        // `whenLabel` already knows the difference: anime lands at a clock time, TV lands on a
        // day (its clock is synthesized). No source branch belongs at a formatting call site.
        if let f = appModel.nextUp, let next = f.nextAiring(now: now) {
            return "Nothing new since you were last here. Your next episode lands \(f.whenLabel(ts: next, now: now))."
        }
        return "Nothing new since you were last here."
    }

    // MARK: hero ladder

    private enum HeroVariant {
        case newEpisode   // ghost accent chip, full urgency
        case resume       // quiet CONTINUE chip
        case waiting      // quiet UP NEXT chip, no primary CTA
    }

    /// Hero pages by priority: fresh drops (max 3) → the resume target → the next airing.
    private var heroItems: [(franchise: Franchise, variant: HeroVariant)] {
        let fresh = appModel.outNow.prefix(Self.heroCap)
        if !fresh.isEmpty { return fresh.map { ($0, .newEpisode) } }
        if let resume = appModel.keepWatching.first { return [(resume, .resume)] }
        if let next = appModel.nextUp { return [(next, .waiting)] }
        return []
    }

    @ViewBuilder
    private var heroSection: some View {
        let items = heroItems
        if items.count <= 1 {
            if let item = items.first {
                heroCard(item.franchise, variant: item.variant)
            }
        } else {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(items, id: \.franchise.id) { item in
                        heroCard(item.franchise, variant: item.variant)
                            .containerRelativeFrame(.horizontal)
                            .id(item.franchise.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollIndicators(.hidden)
            .scrollPosition(id: $heroPage)
        }
    }

    // Animated pill dots — the active page's dot stretches into a small capsule.
    private var heroDots: some View {
        HStack(spacing: 5) {
            ForEach(heroItems, id: \.franchise.id) { item in
                let on = (heroPage ?? heroItems.first?.franchise.id) == item.franchise.id
                Capsule()
                    .fill(on ? Theme.accent : Theme.text28)
                    .frame(width: on ? 14 : 5, height: 5)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.uiSnappy, value: heroPage)
    }

    // MARK: hero card

    private func heroCard(_ f: Franchise, variant: HeroVariant) -> some View {
        let vm = CardModel(franchise: f, action: .none, now: now)
        return Button { onOpenDetail(f.id, "hero/\(f.id)") } label: {
            ZStack(alignment: .bottomLeading) {
                // Cover art, top-biased crop: the art window is taller than the hero and pinned to
                // its top edge, so the visible region favors the poster's upper third. Hung off
                // Color.clear so a `.fill` image can never inflate layout (learned the hard way).
                Color.clear
                    .frame(height: Self.heroHeight)
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .top) {
                        RemoteImageView(url: vm.cover ?? vm.banner, maxPixel: 1100)
                            .frame(height: Self.heroHeight + Self.heroCropOverflow)
                    }
                    .clipped()
                    .overlay {
                        LinearGradient(
                            stops: [
                                .init(color: Theme.background.opacity(0.55), location: 0),
                                .init(color: .clear, location: 0.28),
                            ],
                            startPoint: .top, endPoint: .bottom
                        )
                    }
                    .overlay {
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0.44),
                                .init(color: Theme.background.opacity(0.62), location: 0.72),
                                .init(color: Theme.background, location: 1),
                            ],
                            startPoint: .top, endPoint: .bottom
                        )
                    }

                VStack(alignment: .leading, spacing: 0) {
                    heroChip(variant)
                    Text(vm.title)
                        .scaledFont(34, weight: .bold)
                        .tracking(-1.2)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(Theme.textPrimary)
                        .shadow(color: .black.opacity(0.5), radius: 14, y: 2)
                        .padding(.top, 10)
                    heroMeta(f, vm: vm, variant: variant)
                        .padding(.top, 9)
                    heroCTAs(f, vm: vm, variant: variant)
                        .padding(.top, 14)
                }
                .padding(.horizontal, Theme.Space.gutter)
                .padding(.bottom, 18)

                if appModel.justCaught.contains(f.id) {
                    CaughtUpOverlay(size: 60)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(height: Self.heroHeight)
            .animation(.uiGentle, value: appModel.justCaught.contains(f.id))
        }
        .buttonStyle(SpringPressButtonStyle(scale: 0.99))
        .contextMenu { FranchiseContextMenu(f: f, appModel: appModel) }
    }

    // Ghost chip: dark translucent fill, accent for the NEW moment, quiet for the fallbacks.
    private func heroChip(_ variant: HeroVariant) -> some View {
        let (label, fg, border): (String, Color, Color) = switch variant {
        case .newEpisode: ("NEW EPISODE", Theme.accent, Theme.accentBorder)
        case .resume: ("CONTINUE", Theme.text72, Theme.hairlineStrong)
        case .waiting: ("UP NEXT", Theme.text72, Theme.hairlineStrong)
        }
        return Text(label)
            .scaledFont(9.5, weight: .bold)
            .tracking(1.0)
            .foregroundStyle(fg)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Theme.background.opacity(0.55),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(border, lineWidth: 1))
    }

    // Mono-caps tracker meta: "S2 E6 · AIRED 2H AGO · 2 TO CATCH UP" — quiet facts, accent tail.
    // Dedupe rule: when the now bar already states this franchise's "when" at display size, the
    // meta line drops its time fragment and keeps only watch context — one fact, one place.
    private func heroMeta(_ f: Franchise, vm: CardModel, variant: HeroVariant) -> some View {
        let inNowBar = appModel.nowBarItem?.franchiseId == f.id
        let (base, tail): (String, String) = switch variant {
        case .newEpisode: newEpisodeMeta(vm, dropTime: inNowBar)
        case .resume: resumeMeta(f)
        case .waiting: waitingMeta(vm, dropTime: inNowBar)
        }
        return (Text(base).foregroundColor(Theme.text72)
                + Text(tail.isEmpty ? "" : " · \(tail)").foregroundColor(Theme.accent))
            .scaledFont(11, weight: .medium, monospacedDigit: true)
            .tracking(0.8)
            .lineLimit(1)
            .shadow(color: .black.opacity(0.6), radius: 6, y: 1)
    }

    private func newEpisodeMeta(_ vm: CardModel, dropTime: Bool) -> (String, String) {
        // TV full-season drop is an availability event, not an episode number.
        if vm.source == .tmdb && vm.progress == 0 && vm.airedEpisodes > 1 {
            let label = (vm.partLabel.isEmpty ? vm.seasonToken() : vm.partLabel).uppercased()
            return (label.isEmpty ? "NEW SEASON" : label, dropTime ? "" : "NOW STREAMING")
        }
        var base = [vm.seasonToken(), vm.airedEpisodes > 0 ? "E\(vm.airedEpisodes)" : ""]
            .filter { !$0.isEmpty }.joined(separator: " ")
        if !dropTime {
            if vm.source == .anilist && !vm.airedAgo.isEmpty {
                base += " · AIRED \(vm.airedAgo.uppercased())"
            } else if vm.source == .tmdb {
                base += " · OUT NOW"
            }
        }
        let tail = vm.behindCount > 1 ? "\(vm.behindCount) TO CATCH UP" : "UP TO DATE AFTER THIS"
        return (base, tail)
    }

    private func resumeMeta(_ f: Franchise) -> (String, String) {
        guard let part = f.resumePart else { return ("", "") }
        let season = part.kind == .season ? "S\(part.sequence) " : ""
        return ("\(season)E\(part.progress + 1) NEXT", "\(f.continueBacklog) LEFT")
    }

    private func waitingMeta(_ vm: CardModel, dropTime: Bool) -> (String, String) {
        var base = [vm.seasonToken(), vm.nextEp.map { "E\($0)" } ?? ""]
            .filter { !$0.isEmpty }.joined(separator: " ")
        // The now bar owns this franchise's "when" at display size — keep only watch context.
        if dropTime { return (base, "") }
        // One label for "when does this land" — "TOMORROW 9:00 PM" for anime, "TOMORROW" for TV.
        let when = vm.whenLabel.uppercased()
        if !when.isEmpty { base += base.isEmpty ? when : " · \(when)" }
        // nil = nothing left to quantify: nothing is scheduled, or a TV drop is TODAY and the
        // base already says so. The accent tail exists to size a WAIT, not to repeat the day.
        guard let clock = vm.relClock else { return (base, "") }
        return (base, clock == "now" ? "NOW" : "IN \(clock.uppercased())")
    }

    @ViewBuilder
    private func heroCTAs(_ f: Franchise, vm: CardModel, variant: HeroVariant) -> some View {
        HStack(spacing: 8) {
            switch variant {
            case .newEpisode:
                if vm.progress == 0 && vm.airedEpisodes > 1 {
                    accentPill("Start watching", icon: "play.fill") { onOpenDetail(f.id, "hero/\(f.id)") }
                } else {
                    // Catch-up semantics: contiguous progress, one tap → watched through newest.
                    accentPill("Mark E\(vm.airedEpisodes) watched", icon: "checkmark") {
                        appModel.markCaughtUp(f.id)
                    }
                }
                ghostPill("Details") { onOpenDetail(f.id, "hero/\(f.id)") }
            case .resume:
                if let part = f.resumePart {
                    accentPill("Watched E\(part.progress + 1)", icon: "checkmark") {
                        appModel.setProgress(franchiseId: f.id, mediaId: part.mediaId,
                                             episodes: part.progress + 1)
                    }
                }
                ghostPill("Details") { onOpenDetail(f.id, "hero/\(f.id)") }
            case .waiting:
                ghostPill("Details") { onOpenDetail(f.id, "hero/\(f.id)") }
            }
        }
    }

    // No haptic here on purpose: the STATE CHANGE owns the feedback (markCaughtUp fires success,
    // setProgress fires .soft). Firing one on the press too gave the hero CTA a double tap.
    private func accentPill(_ label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).scaledFont(11, weight: .bold)
                Text(label).scaledFont(12.5, weight: .bold)
            }
            .foregroundStyle(Theme.background)
            .padding(.horizontal, 15).padding(.vertical, 9)
            .background(Theme.accent, in: Capsule())
            .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
        }
        .buttonStyle(SpringPressButtonStyle(scale: 0.94))
    }

    private func ghostPill(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .scaledFont(12.5, weight: .bold)
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 15).padding(.vertical, 9)
                .background(Theme.background.opacity(0.35), in: Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.28), lineWidth: 1))
        }
        .buttonStyle(SpringPressButtonStyle(scale: 0.94))
    }

    // MARK: currently watching shelf

    /// The rotation minus whatever the hero already shows.
    private var shelf: [Franchise] {
        let heroIds = Set(heroItems.map(\.franchise.id))
        return appModel.watchingShelf.filter { !heroIds.contains($0.id) }
    }

    private var shelfSection: some View {
        let items = shelf
        let visible = Array(items.prefix(Self.shelfCap))
        return VStack(alignment: .leading, spacing: 0) {
            SectionHeader(label: "Currently watching",
                          trailing: "\(items.count) \(items.count == 1 ? "show" : "shows")")
                .padding(.horizontal, Theme.Space.gutter)

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(visible) { f in shelfCard(f) }
                    if items.count > Self.shelfCap {
                        seeAllCard(total: items.count)
                    }
                }
                .padding(.horizontal, Theme.Space.gutter)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
            // Right-edge fade — hints at more without chrome.
            .overlay(alignment: .trailing) {
                LinearGradient(colors: [.clear, Theme.background.opacity(0.85)],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: 28)
                    .allowsHitTesting(false)
            }
        }
    }

    private func shelfCard(_ f: Franchise) -> some View {
        let state = appModel.shelfState(of: f)
        return Button { onOpenDetail(f.id, "shelf/\(f.id)") } label: {
            VStack(alignment: .leading, spacing: 0) {
                Thumb(cover: f.cover, width: 108, height: 152, radius: 12)
                    .shadow(color: .black.opacity(0.38), radius: 10, y: 5)
                    .overlay(alignment: .topLeading) {
                        if state == .newEpisode {
                            Text("NEW")
                                .scaledFont(9.5, weight: .bold)
                                .tracking(0.8)
                                .foregroundStyle(Theme.background)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .shadow(color: .black.opacity(0.45), radius: 5, y: 2)
                                .padding(8)
                        }
                    }
                Text(f.title)
                    .scaledFont(12, weight: .semibold)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(Theme.text72)
                    .frame(height: 31, alignment: .topLeading)
                    .padding(.top, 8)
                shelfCaption(f, state: state)
                    .padding(.top, 5)
            }
            .frame(width: 108, alignment: .leading)
        }
        .buttonStyle(SpringPressButtonStyle(scale: 0.96))
        .contextMenu { FranchiseContextMenu(f: f, appModel: appModel) }
    }

    // Mono caption = the card's whole state system: accent for time-bound facts, quiet for backlog.
    @ViewBuilder
    private func shelfCaption(_ f: Franchise, state: AppModel.ShelfState?) -> some View {
        switch state {
        case .newEpisode:
            let part = f.releasingPart
            let season = part.map { $0.kind == .season ? "S\($0.sequence) " : "" } ?? ""
            caption("\(season)E\(part?.airedEpisodes ?? 0) out now", color: Theme.accent)
        case .backlog:
            if let part = f.resumePart {
                let season = part.kind == .season ? "S\(part.sequence) · " : ""
                caption("\(season)\(f.continueBacklog) left", color: Theme.text50)
            }
        case .airingWait:
            // Read in the franchise's own calendar throughout — a TV date is a day, not an instant.
            if let next = f.nextAiring(now: now) {
                let day = Formatting.fmtDay(ts: next, now: now, anchor: f.timeAnchor)
                let span = Formatting.fmtRelSpanShort(ts: next, now: now, anchor: f.timeAnchor)
                let isToday = f.dayDiff(of: next, now: now) == 0
                caption(isToday ? "Today" : "\(day) · \(span)", color: Theme.accent)
            }
        case .premiereSoon:
            if let premiere = appModel.nextPremiere(of: f) {
                caption(Formatting.fmtMonthDay(premiere, anchor: f.timeAnchor), color: Theme.text46)
            }
        case nil:
            EmptyView()
        }
    }

    private func caption(_ text: String, color: Color) -> some View {
        Text(text)
            .scaledFont(10, weight: .medium, monospacedDigit: true)
            .tracking(0.4)
            .foregroundStyle(color)
            .lineLimit(1)
    }

    private func seeAllCard(total: Int) -> some View {
        Button {
            Haptics.selection()
            onSeeAllWatching()
        } label: {
            VStack(spacing: 5) {
                Text("See all")
                    .scaledFont(12, weight: .semibold)
                    .foregroundStyle(Theme.text72)
                Text("\(total)")
                    .scaledFont(13, weight: .semibold, monospacedDigit: true)
                    .foregroundStyle(Theme.text36)
            }
            .frame(width: 108, height: 152)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.hairlineStrong, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            }
        }
        .buttonStyle(SpringPressButtonStyle(scale: 0.96))
    }
}
