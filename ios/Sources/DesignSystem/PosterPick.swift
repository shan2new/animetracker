import SwiftUI
import UIKit
import Vision

// Home's picture of a show, chosen by EYE (26 Sep: "choose the best-looking poster, even if it is
// from an earlier season", owner — after Slime's Season 4 key visual, dark and diagonal with its
// faces at the edges, took the billboard: "Slime's poster doesn't look nice… the poster image
// itself… This might happen to other series as well").
//
// Nothing upstream ever looks at a poster. The server keeps a show's six BIGGEST uploads
// (`rankArtwork` ranks on pixel area) for the show as a whole, and TMDB's "no language" tag is an
// uploader's word (Slime's second "textless" Season 4 poster prints the Japanese title). So every
// portrait the catalogue holds for a show — its gallery and each season's own cover, any season —
// is graded ONCE, on the device, from a small decode:
//   · LIGHT and COLOUR (mean OKLab L over the part of the poster the billboard shows, Hasler–
//     Süsstrunk colourfulness): murky art is a hole behind the words, a near-white one drowns them;
//   · its SUBJECT (a face, else attention saliency — `SubjectCrop.subject`): the billboard shows
//     the poster's upper middle, between the bar and the words;
//   · LETTERING (Vision text recognition, CJK included): the show's logo goes on a clean picture,
//     never over a second title;
//   · SHARPNESS (its measured width): a 460-px cover is soft across a 1179-px billboard.
// A grade is kept per picture for good and a show's pick with the candidate list it was made from
// (`Caches/poster-pick-v2.json`), so a show wears the same picture on every visit and only a new
// upload can change it. Home asks (`resolve`) for the billboard's show first, then the shelf's.
@MainActor @Observable
final class PosterPick {
    static let shared = PosterPick()

    /// One show's picture on Home.
    struct Choice: Codable, Equatable, Sendable {
        /// As the catalogue sent it (a TMDB `w780` poster, an AniList cover).
        let url: String
        /// It carries lettering — its own title, or an upload wrongly tagged textless.
        let lettered: Bool
        /// Where that lettering sits, top-left origin, 0…1 of the poster's height.
        let textTop: Double?
        let textBottom: Double?
        /// The candidate list it was chosen from: a changed gallery chooses again.
        let signature: String
    }

    /// What the eye found in one picture (top-left origin, 0…1).
    struct Grade: Codable, Equatable, Sendable {
        let light: Double
        let colour: Double
        let subjectY: Double
        let face: Bool
        /// It carries lettering: read on the picture, or declared by a language tag.
        var lettered: Bool
        /// Where the lettering sits, once it has been read (nil for a tag's word alone).
        var textTop: Double?
        var textBottom: Double?
    }

    /// A picture the show could wear.
    struct Candidate: Equatable, Sendable {
        let url: String
        /// Measured by the catalogue (TMDB); nil for a cover sent without its size.
        let width: Int?
        /// TMDB tags it with a language: it is TITLED — only its lettering's place is unknown. An
        /// untagged picture is read, since the tag's absence is an uploader's guess.
        let titled: Bool
        /// The picture's identity across sizes: TMDB's file name, else the URL.
        let key: String
        /// A small rendition to grade (TMDB `w342`; an AniList cover as it is).
        let gradeURL: String
    }

    private(set) var choices: [String: Choice] = [:]
    @ObservationIgnored private var grades: [String: Grade] = [:]
    @ObservationIgnored private var resolving: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    /// The most pictures one show's pick weighs.
    nonisolated static let candidateLimit = 10
    /// The most grades the file keeps (a few hundred bytes each).
    nonisolated static let gradeCapacity = 3_000
    /// The decode a grade is made from — enough for a title's letters, small enough to be quick.
    nonisolated static let gradePixels: CGFloat = 480
    nonisolated private static let fileURL = FileManager.default
        .urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("poster-pick-v2.json")
    /// Vision on its own queue, `parallel` pictures at a time.
    nonisolated private static let visionQueue = DispatchQueue(label: "poster-pick.vision", qos: .userInitiated,
                                                               attributes: .concurrent)

    private init() {
        // Read on first use, synchronously: a few kilobytes, and the billboard's FIRST frame needs
        // the answer — a pick that lands a frame later is a picture that changes under the reader.
        if let data = try? Data(contentsOf: Self.fileURL),
           let file = try? JSONDecoder().decode(StoreFile.self, from: data) {
            grades = file.grades
            choices = file.choices
        }
    }

    // MARK: API

    /// The show's picture, when one has been chosen for the candidates it has now.
    func choice(for f: Franchise) -> Choice? {
        guard let stored = choices[f.id] else { return nil }
        return stored.signature == Self.signature(Self.candidates(for: f), logo: f.hasDrawableLogo) ? stored : nil
    }

    /// Choose the show's picture, grading whatever has not been graded. One run per show at a time;
    /// nothing to do when the stored pick matches the show's candidates.
    func resolve(_ f: Franchise) async {
        let list = Self.candidates(for: f)
        let logo = f.hasDrawableLogo
        let signature = Self.signature(list, logo: logo)
        guard !list.isEmpty, choices[f.id]?.signature != signature else { return }
        if let running = resolving[f.id] { return await running.value }
        let id = f.id
        PerfProbe.mark("poster-pick-start", id)
        let task = Task { await self.decide(id, list, logo: logo, signature: signature) }
        resolving[id] = task
        await task.value
        resolving[id] = nil
        PerfProbe.mark("poster-pick-end", id)
    }

    /// Three passes, so a first visit's billboard is not kept waiting (it waits `pickPatience`): the
    /// sharp pictures TMDB calls textless first — the ones that can carry the show's logo, read for
    /// lettering since the tag can be wrong; then the sharp TITLED ones (tone and subject only, their
    /// tag already says what reading would); then the seasons' own covers (460 px — soft on a
    /// billboard, read in full). The pick is made after each pass and changes only when beaten.
    private func decide(_ id: String, _ list: [Candidate], logo: Bool, signature: String) async {
        let passes = [list.filter { $0.width != nil && !$0.titled },
                      list.filter { $0.width != nil && $0.titled },
                      list.filter { $0.width == nil }]
        for pass in passes where !pass.isEmpty {
            let missing = pass.filter { grades[$0.key] == nil }
            if !missing.isEmpty {
                for (key, grade) in await Self.gradeAll(missing) { grades[key] = grade }
            }
            var best: (candidate: Candidate, grade: Grade, score: Double)?
            for candidate in list {
                guard let grade = grades[candidate.key] else { continue }
                let score = Self.score(grade, width: candidate.width, logo: logo)
                if score > (best?.score ?? -.infinity) { best = (candidate, grade, score) }
            }
            guard var best else { continue }
            // A titled winner's lettering has not been read: read it now, for the name rule.
            if best.grade.lettered, best.grade.textTop == nil, let url = URL(string: best.candidate.gradeURL),
               let picture = try? await ImageLoader.shared.image(for: url, maxPixel: Self.gradePixels),
               let cg = picture.cgImage {
                let text = await Self.onVisionQueue { Self.lettering(cg) }
                best.grade.textTop = text?.top
                best.grade.textBottom = text?.bottom
                grades[best.candidate.key] = best.grade
            }
            PerfProbe.mark("poster-pick-pass", "\(id) \(pass.count)")
            let choice = Choice(url: best.candidate.url, lettered: best.grade.lettered,
                                textTop: best.grade.textTop, textBottom: best.grade.textBottom, signature: signature)
            if choices[id] != choice { choices[id] = choice }
        }
        scheduleSave()
    }

    // MARK: Candidates

    /// Every portrait the catalogue holds for the show — its gallery, its own cover, then each
    /// season's gallery and cover, newest season first — once each, measured pictures first.
    nonisolated static func candidates(for f: Franchise) -> [Candidate] {
        var images: [ArtworkImage] = f.artwork?.portraits ?? []
        if let cover = f.images?.portrait { images.append(ArtworkImage(url: cover)) }
        for part in f.seasonPartsInOrder.reversed() {
            images += part.artwork?.portraits ?? []
            if let cover = part.images?.portrait { images.append(ArtworkImage(url: cover)) }
        }
        var index: [String: Int] = [:]
        var out: [Candidate] = []
        for image in images {
            // A landscape is not a poster.
            if let w = image.width, let h = image.height, w >= h { continue }
            let key = identity(image.url)
            let width = image.width.flatMap { $0 > 0 ? $0 : nil }
            let candidate = Candidate(url: image.url, width: width,
                                      titled: width != nil && ArtworkSet.nonEmpty(image.language) != nil,
                                      key: key, gradeURL: gradeURL(image.url))
            if let i = index[key] {
                // The same picture at another size: keep the measured entry.
                if out[i].width == nil, candidate.width != nil { out[i] = candidate }
                continue
            }
            index[key] = out.count
            out.append(candidate)
        }
        let measured = out.filter { $0.width != nil }
        let covers = out.filter { $0.width == nil }
        return Array((measured + covers).prefix(candidateLimit))
    }

    nonisolated private static func isTMDB(_ url: String) -> Bool { url.contains("image.tmdb.org/t/p/") }

    nonisolated private static func identity(_ url: String) -> String {
        isTMDB(url) ? (url.split(separator: "/").last.map(String.init) ?? url) : url
    }

    nonisolated private static func gradeURL(_ url: String) -> String {
        guard isTMDB(url) else { return url }
        return url.replacingOccurrences(of: #"/t/p/(w\d+|original)/"#, with: "/t/p/w342/", options: .regularExpression)
    }

    /// FNV-1a over the candidates' identities and the logo flag — stable across launches (Swift's
    /// `Hasher` is seeded per process).
    nonisolated static func signature(_ list: [Candidate], logo: Bool) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in (list.map(\.key).joined(separator: "|") + (logo ? "|L" : "|-")).utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return String(hash, radix: 16)
    }

    // MARK: Judging

    /// How good a picture is for Home, about 0…1. Measured on the owner's library (26 Sep).
    nonisolated static func score(_ g: Grade, width: Int?, logo: Bool) -> Double {
        func clamp(_ v: Double) -> Double { min(1, max(0, v)) }
        // L 0.30 is murk; 0.55 is a lit picture; past 0.82 the white words have nothing to stand on.
        let light = clamp((g.light - 0.30) / 0.25) - max(0, g.light - 0.82) * 3
        let colour = clamp(g.colour / 70)
        // The billboard shows ~14–64 % of the poster's height between the bar and the words.
        let y = g.subjectY
        let subject = y < 0.18 ? clamp(y / 0.18) : (y > 0.62 ? clamp((0.9 - y) / 0.28) : 1)
        let sharp: Double
        switch width ?? 0 {
        case 1400...: sharp = 1
        case 1000..<1400: sharp = 0.85
        case 700..<1000: sharp = 0.55
        default: sharp = 0.25 // an AniList cover (460 px wide), or a small upload
        }
        // Lettering competes with the name the billboard draws — most of all the show's logo.
        let lettering = g.lettered ? (logo ? 0.45 : 0.2) : 0
        return 0.32 * light + 0.23 * colour + 0.2 * subject + 0.25 * sharp + (g.face ? 0.03 : 0) - lettering
    }

    /// Pictures graded at most `parallel` at a time — the downloads overlap, and Vision's reading
    /// runs on as many cores.
    nonisolated private static func gradeAll(_ list: [Candidate]) async -> [(String, Grade)] {
        await withTaskGroup(of: (String, Grade)?.self) { group in
            var out: [(String, Grade)] = []
            var next = 0
            while next < min(parallel, list.count) {
                let candidate = list[next]
                group.addTask { await gradeOne(candidate) }
                next += 1
            }
            while let item = await group.next() {
                if let item { out.append(item) }
                if next < list.count {
                    let candidate = list[next]
                    group.addTask { await gradeOne(candidate) }
                    next += 1
                }
            }
            return out
        }
    }

    nonisolated private static let parallel = 4

    nonisolated private static func gradeOne(_ candidate: Candidate) async -> (String, Grade)? {
        guard let url = URL(string: candidate.gradeURL),
              let picture = try? await ImageLoader.shared.image(for: url, maxPixel: gradePixels),
              let cg = picture.cgImage else { return nil }
        let titled = candidate.titled
        return (candidate.key, await onVisionQueue { grade(cg, titled: titled) })
    }

    nonisolated private static func onVisionQueue<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            visionQueue.async { continuation.resume(returning: work()) }
        }
    }

    /// `titled`: its tag already says it carries lettering, so the (slowest) reading is skipped.
    nonisolated static func grade(_ cg: CGImage, titled: Bool) -> Grade {
        let tone = tone(cg)
        let subject = SubjectCrop.subject(in: cg)
        let text = titled ? nil : lettering(cg)
        return Grade(light: tone.light, colour: tone.colour, subjectY: Double(subject.rect.midY),
                     face: subject.face, lettered: titled || text != nil, textTop: text?.top, textBottom: text?.bottom)
    }

    /// Mean OKLab lightness over the rows the billboard shows (12–70 %), and the Hasler–Süsstrunk
    /// colourfulness of the whole picture, from one 24×36 sample.
    nonisolated static func tone(_ cg: CGImage) -> (light: Double, colour: Double) {
        let w = 24, h = 36
        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return (0.5, 0) }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var lightSum = 0.0, lightN = 0.0
        var rgSum = 0.0, ybSum = 0.0, rg2 = 0.0, yb2 = 0.0, n = 0.0
        for row in 0..<h {
            // The context's rows run bottom-up: row 0 is the picture's foot.
            let fromTop = 1 - (Double(row) + 0.5) / Double(h)
            let shown = fromTop >= 0.12 && fromTop <= 0.70
            for col in 0..<w {
                let i = (row * w + col) * 4
                let r = Double(px[i]), g = Double(px[i + 1]), b = Double(px[i + 2])
                if shown {
                    lightSum += PaletteCache.oklab(r: r / 255, g: g / 255, b: b / 255).0
                    lightN += 1
                }
                let rg = r - g, yb = 0.5 * (r + g) - b
                rgSum += rg; ybSum += yb; rg2 += rg * rg; yb2 += yb * yb; n += 1
            }
        }
        guard n > 0, lightN > 0 else { return (0.5, 0) }
        let mrg = rgSum / n, myb = ybSum / n
        let srg = max(0, rg2 / n - mrg * mrg).squareRoot(), syb = max(0, yb2 / n - myb * myb).squareRoot()
        let colour = (srg * srg + syb * syb).squareRoot() + 0.3 * (mrg * mrg + myb * myb).squareRoot()
        return (lightSum / lightN, colour)
    }

    /// The vertical extent of the picture's lettering — a title, a logotype — or nil when it is
    /// clean. Small print (a billing block) is under the height floor and does not count.
    nonisolated static func lettering(_ cg: CGImage) -> (top: Double, bottom: Double)? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.03
        if let supported = try? request.supportedRecognitionLanguages() {
            request.recognitionLanguages = ["en-US", "ja-JP", "zh-Hans", "ko-KR"].filter(supported.contains)
        }
        SubjectCrop.preferCPUInSimulator([request])
        try? VNImageRequestHandler(cgImage: cg, options: [:]).perform([request])
        let boxes = (request.results ?? []).compactMap { observation -> CGRect? in
            guard let best = observation.topCandidates(1).first, best.confidence >= 0.3,
                  best.string.filter(\.isLetter).count >= 2,
                  observation.boundingBox.height >= 0.025 else { return nil }
            return observation.boundingBox
        }
        guard let top = boxes.map(\.maxY).max(), let bottom = boxes.map(\.minY).min() else { return nil }
        // Vision's origin is bottom-left.
        return (1 - Double(top), 1 - Double(bottom))
    }

    // MARK: The file

    private struct StoreFile: Codable, Sendable {
        var grades: [String: Grade]
        var choices: [String: Choice]
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, !Task.isCancelled else { return }
            if self.grades.count > Self.gradeCapacity {
                // Keep what the stored picks were made from; drop the rest past the cap.
                let kept = Set(self.choices.values.map { Self.identity($0.url) })
                var trimmed = self.grades.filter { kept.contains($0.key) }
                for (key, grade) in self.grades where trimmed.count < Self.gradeCapacity { trimmed[key] = grade }
                self.grades = trimmed
            }
            let file = StoreFile(grades: self.grades, choices: self.choices)
            let url = Self.fileURL
            Task.detached(priority: .utility) {
                if let data = try? JSONEncoder().encode(file) { try? data.write(to: url, options: .atomic) }
            }
        }
    }
}

extension PosterPick.Choice {
    /// What the billboard draws for the show's name over this picture: the show's logo on a clean
    /// picture ("the posters used to have Picture Series Logos", owner, 26 Sep); nothing where the
    /// picture's own lettering is in view between the bar and the words (it names the show); the
    /// logo — else the name in type — where that lettering sits under either.
    func billboardName(for f: Franchise, visible: ClosedRange<Double> = 0.14...0.64) -> BillboardName {
        let logo: BillboardName? = f.hasDrawableLogo ? f.billboardLogo.map(BillboardName.logo) : nil
        guard lettered, let top = textTop, let bottom = textBottom, bottom > top else { return logo ?? .type }
        let seen = min(bottom, visible.upperBound) - max(top, visible.lowerBound)
        if seen >= (bottom - top) * 0.5 { return .embedded }
        return logo ?? .type
    }

    /// A poster tile's name on this picture: the show's logo on a clean one; otherwise the caption
    /// under the poster carries the name.
    func tileName(for f: Franchise) -> BillboardName {
        guard !lettered, f.hasDrawableLogo, let logo = f.billboardLogo else { return .type }
        return .logo(logo)
    }
}

extension Franchise {
    /// The show has a logo the app can draw (`billboardLogo`, measured).
    var hasDrawableLogo: Bool { billboardLogo.map { BillboardName.logo($0).hasGraphicLogo } ?? false }
}
