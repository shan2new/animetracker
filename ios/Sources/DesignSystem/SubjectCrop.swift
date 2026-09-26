import SwiftUI
import UIKit
import Vision
import CoreML

// Avatars cropped on the SUBJECT (25 Sep: the Rick and Morty circle was a purple slice of a portal —
// a fixed crop height cannot work across thirty different posters).
//
// Vision finds a human face first (live action), else the region the eye goes to (attention
// saliency — a character in animation), and the avatar is the square around it: a face with its
// hair and shoulders, or the top of a character.
//
// Vision runs once per picture EVER (per install, until Caches is purged), not once per launch:
// the answer — a normalised square and which candidate it belongs to — is persisted in
// `Caches/subject-focus-v1.json`, and a known picture is drawn from its stored square after one
// 480-px decode with no Vision work at all. The pictures themselves are never held here: the decode
// comes from `ImageLoader` (`ImageCache` keeps it), and the small cropped bitmap an avatar draws is
// filed beside the decodes as a derived image (`ImageCache.derived`), so it lives and dies with them.

@MainActor
final class SubjectCrop {
    static let shared = SubjectCrop()

    /// A subject square in its picture's own unit space (top-left origin, 0…1), the candidate it
    /// was found in, and whether Vision saw a face there.
    struct Focus: Equatable, Sendable {
        let index: Int
        let rect: CGRect
        let face: Bool
    }

    /// Stored answers by candidate key (`key(_:)`), and their insertion order for the cap.
    private var focuses: [String: Focus] = [:]
    private var order: [String] = []
    private var loaded = false
    private var loading: Task<Void, Never>?
    /// Vision in flight per candidate key: two avatars of one show share one reading.
    private var detecting: [String: Task<Focus?, Never>] = [:]
    /// Crops in flight per candidate key.
    private var cropping: [String: Task<UIImage?, Never>] = [:]
    private var saveTask: Task<Void, Never>?
    /// Bumped by `clear()`: an answer that started before a sign-out is never stored after it.
    private var generation = 0

    /// The most answers the file keeps; the oldest insertion is dropped first.
    nonisolated static let capacity = 1_500
    /// How many of a show's candidates Vision may try before settling for the first one's saliency.
    nonisolated static let candidateLimit = 3
    /// The avatar's own bitmap, at most this many pixels on a side (a 66-pt bubble is 198 px at 3×).
    nonisolated static let cropPixels: CGFloat = 256
    nonisolated private static let saveDelay: Duration = .seconds(2)
    nonisolated private static let fileURL = FileManager.default
        .urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("subject-focus-v1.json")
    /// Vision, one picture at a time on its own queue (thirty concurrent requests starved the pool).
    nonisolated private static let visionQueue = DispatchQueue(label: "subject-crop.vision", qos: .utility)
    /// The file's reads, writes and deletes, in the order they were asked for — so a delete from
    /// `clear()` always lands after a write that was already on its way.
    nonisolated private static let ioQueue = DispatchQueue(label: "subject-crop.io", qos: .utility)

    private init() {}

    // MARK: Keys

    /// One show's candidate list, joined: the stored answer belongs to the LIST, since the winning
    /// picture is chosen among them.
    nonisolated static func key(_ urls: [String]) -> String { urls.joined(separator: "|") }

    nonisolated private static func derivedKey(_ key: String) -> String { "subject-crop|\(key)" }

    /// The avatar's bitmap when it has already been made this session — synchronous, for a view's
    /// first frame (a recycled row never flashes its placeholder).
    nonisolated static func cachedCrop(for urls: [String]) -> UIImage? {
        guard !urls.isEmpty else { return nil }
        return ImageCache.shared.derived(derivedKey(key(urls)))
    }

    // MARK: API

    /// The subject square for a show's avatar candidates, best first: the first picture where Vision
    /// finds a FACE wins (live action), else the first picture that loaded, cropped on its attention
    /// map (animation). Stored for good once found; nil when no picture could be loaded.
    func focus(for urls: [String]) async -> (url: String, rect: CGRect)? {
        guard let found = await resolveFocus(urls), found.index < urls.count else { return nil }
        return (urls[found.index], found.rect)
    }

    /// The avatar's own small bitmap: the subject square of the chosen picture, rendered off the main
    /// thread at no more than `cropPixels` a side.
    func crop(for urls: [String]) async -> UIImage? {
        guard !urls.isEmpty else { return nil }
        if let hit = Self.cachedCrop(for: urls) { return hit }
        let key = Self.key(urls)
        if let running = cropping[key] { return await running.value }
        let gen = generation
        let task = Task<UIImage?, Never> {
            guard let found = await self.resolveFocus(urls), found.index < urls.count,
                  let url = URL(string: urls[found.index]),
                  let picture = try? await ImageLoader.shared.image(for: url, maxPixel: FeedMetrics.avatarDecodePixels),
                  let cg = picture.cgImage else { return nil }
            let rect = found.rect
            let out = await Self.onVisionQueue { Self.render(cg, rect: rect) }
            if let out { ImageCache.shared.storeDerived(out, key: Self.derivedKey(key)) }
            return out
        }
        cropping[key] = task
        let out = await task.value
        if gen == generation { cropping[key] = nil }
        return out
    }

    /// Forget every answer and delete the file (account teardown).
    func clear() {
        generation += 1
        saveTask?.cancel()
        saveTask = nil
        focuses = [:]
        order = []
        detecting = [:]
        cropping = [:]
        // Memory is authoritative now (empty); a load still in flight discards what it read.
        loaded = true
        loading = nil
        let url = Self.fileURL
        Self.ioQueue.async { try? FileManager.default.removeItem(at: url) }
    }

    // MARK: Resolution

    private func resolveFocus(_ urls: [String]) async -> Focus? {
        guard !urls.isEmpty else { return nil }
        await ensureLoaded()
        let key = Self.key(urls)
        if let known = focuses[key], known.index < urls.count { return known }
        if let running = detecting[key] { return await running.value }
        let gen = generation
        let candidates = Array(urls.prefix(Self.candidateLimit))
        let task = Task<Focus?, Never> { await Self.detect(candidates) }
        detecting[key] = task
        let found = await task.value
        guard gen == generation else { return found }
        detecting[key] = nil
        if let found { remember(found, for: key) }
        return found
    }

    /// Several pictures of one show, in preference order.
    nonisolated private static func detect(_ urls: [String]) async -> Focus? {
        var fallback: Focus?
        for (index, string) in urls.enumerated() {
            guard let url = URL(string: string),
                  let picture = try? await ImageLoader.shared.image(for: url, maxPixel: FeedMetrics.avatarDecodePixels),
                  let cg = picture.cgImage else { continue }
            let found = await onVisionQueue { subject(in: cg) }
            if found.face { return Focus(index: index, rect: found.rect, face: true) }
            if fallback == nil { fallback = Focus(index: index, rect: found.rect, face: false) }
        }
        return fallback
    }

    nonisolated private static func onVisionQueue<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            visionQueue.async { continuation.resume(returning: work()) }
        }
    }

    // MARK: Vision

    /// A normalised square (top-left origin) around the picture's subject, and whether it is a face.
    nonisolated static func subject(in cg: CGImage) -> (rect: CGRect, face: Bool) {
        let W = CGFloat(cg.width), H = CGFloat(cg.height)
        let minSide = min(W, H)
        guard minSide > 0 else { return (CGRect(x: 0, y: 0, width: 1, height: 1), false) }
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        let faces = VNDetectFaceRectanglesRequest()
        let attention = VNGenerateAttentionBasedSaliencyImageRequest()
        preferCPUInSimulator([faces, attention])
        try? handler.perform([faces, attention])

        var cx: CGFloat, cy: CGFloat, side: CGFloat
        var isFace = false
        if let f = faces.results?.max(by: { $0.boundingBox.width < $1.boundingBox.width }),
           f.boundingBox.width * W > minSide * 0.06 {
            // A face: with its hair and shoulders, a touch below centre.
            let b = f.boundingBox
            let px = CGRect(x: b.minX * W, y: (1 - b.maxY) * H, width: b.width * W, height: b.height * H)
            side = max(px.width, px.height) * 2.3
            cx = px.midX
            cy = px.midY + px.height * 0.18
            isFace = true
        } else if let observation = attention.results?.first, let hot = hottest(observation.pixelBuffer) {
            // Where the eye goes: the centre of the hottest part of the attention map — a face in a
            // key visual, not the top of a region that may be the whole poster.
            side = minSide * 0.62
            cx = hot.x * W
            cy = hot.y * H
        } else {
            side = minSide
            cx = W / 2
            cy = H * 0.4
        }
        side = min(max(side, minSide * 0.3), minSide)
        let x = min(max(0, cx - side / 2), W - side)
        let y = min(max(0, cy - side / 2), H - side)
        return (CGRect(x: x / W, y: y / H, width: side / W, height: side / H), isFace)
    }

    /// The simulator's Neural Engine path never returns: run every stage on the CPU there.
    /// (`usesCPUOnly` is deprecated; the compute device is chosen per stage instead.) Shared with
    /// `PosterPick`'s text reading.
    nonisolated static func preferCPUInSimulator(_ requests: [VNRequest]) {
        #if targetEnvironment(simulator)
        for request in requests {
            guard let stages = try? request.supportedComputeStageDevices else { continue }
            for (stage, devices) in stages {
                if let cpu = devices.first(where: { device in
                    if case .cpu = device { true } else { false }
                }) {
                    request.setComputeDevice(cpu, for: stage)
                }
            }
        }
        #endif
    }

    /// The weighted centre of the attention map's top values (top-left origin, 0…1).
    nonisolated static func hottest(_ pb: CVPixelBuffer) -> CGPoint? {
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pb) else { return nil }
        let w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb)
        guard w > 0, h > 0 else { return nil }
        let rowBytes = CVPixelBufferGetBytesPerRow(pb)
        var peak: Float = 0
        for y in 0..<h {
            let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: Float.self)
            for x in 0..<w { peak = max(peak, row[x]) }
        }
        guard peak > 0 else { return nil }
        var sx: Float = 0, sy: Float = 0, sw: Float = 0
        for y in 0..<h {
            let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: Float.self)
            for x in 0..<w where row[x] >= peak * 0.7 {
                let v = row[x]
                sx += (Float(x) + 0.5) * v
                sy += (Float(y) + 0.5) * v
                sw += v
            }
        }
        guard sw > 0 else { return nil }
        return CGPoint(x: CGFloat(sx / sw) / CGFloat(w), y: CGFloat(sy / sw) / CGFloat(h))
    }

    /// The subject square as its own small, contiguous bitmap — never the whole 480-px decode drawn
    /// offset under a clip.
    nonisolated private static func render(_ cg: CGImage, rect: CGRect) -> UIImage? {
        let W = CGFloat(cg.width), H = CGFloat(cg.height)
        let pixels = CGRect(x: rect.minX * W, y: rect.minY * H, width: rect.width * W, height: rect.height * H)
            .integral
            .intersection(CGRect(x: 0, y: 0, width: W, height: H))
        guard !pixels.isNull, pixels.width >= 1, pixels.height >= 1,
              let sub = cg.cropping(to: pixels) else { return nil }
        let scale = min(1, cropPixels / max(pixels.width, pixels.height))
        let width = max(1, Int((pixels.width * scale).rounded()))
        let height = max(1, Int((pixels.height * scale).rounded()))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                          | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(sub, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage().map { UIImage(cgImage: $0) }
    }

    // MARK: The file

    /// `rects` maps a candidate key to `[x, y, w, h, face ? 1 : 0, candidate index]`; `keys` is the
    /// insertion order the 1,500-key cap drops from.
    private struct StoreFile: Codable, Sendable {
        var keys: [String]
        var rects: [String: [Double]]

        init(keys: [String], rects: [String: [Double]]) {
            self.keys = keys
            self.rects = rects
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            keys = (try? c.decode([String].self, forKey: .keys)) ?? []
            rects = (try? c.decode([String: [Double]].self, forKey: .rects)) ?? [:]
        }
    }

    private func ensureLoaded() async {
        if loaded { return }
        if let loading {
            await loading.value
            return
        }
        let gen = generation
        let task = Task<Void, Never> {
            let file = await Self.readFile()
            guard gen == self.generation else { return }
            self.merge(file)
            self.loaded = true
        }
        loading = task
        await task.value
        if gen == generation { loading = nil }
    }

    private func merge(_ file: StoreFile?) {
        guard let file else { return }
        var merged: [String: Focus] = [:]
        var mergedOrder: [String] = []
        // The listed order first, then any answer the order does not name (a hand-trimmed file).
        let named = Set(file.keys)
        let listed = file.keys + file.rects.keys.filter { !named.contains($0) }.sorted()
        for key in listed where merged[key] == nil {
            guard let values = file.rects[key], let focus = Self.focus(from: values) else { continue }
            merged[key] = focus
            mergedOrder.append(key)
        }
        // Anything answered while the file was loading is newer than the file.
        for key in order {
            guard let focus = focuses[key] else { continue }
            if merged[key] == nil { mergedOrder.append(key) }
            merged[key] = focus
        }
        focuses = merged
        order = mergedOrder
        trim()
    }

    private func remember(_ focus: Focus, for key: String) {
        if focuses[key] == nil { order.append(key) }
        focuses[key] = focus
        trim()
        scheduleSave()
    }

    private func trim() {
        let excess = order.count - Self.capacity
        guard excess > 0 else { return }
        for key in order.prefix(excess) { focuses[key] = nil }
        order.removeFirst(excess)
    }

    /// Debounced: a screen of new avatars is one write, two seconds after the last of them.
    private func scheduleSave() {
        saveTask?.cancel()
        let gen = generation
        saveTask = Task {
            try? await Task.sleep(for: Self.saveDelay)
            guard !Task.isCancelled, gen == self.generation else { return }
            var rects: [String: [Double]] = [:]
            for key in self.order {
                if let focus = self.focuses[key] { rects[key] = Self.values(of: focus) }
            }
            Self.writeFile(StoreFile(keys: self.order.filter { rects[$0] != nil }, rects: rects))
        }
    }

    nonisolated private static func readFile() async -> StoreFile? {
        let url = fileURL
        return await withCheckedContinuation { continuation in
            ioQueue.async {
                let file = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(StoreFile.self, from: $0) }
                continuation.resume(returning: file)
            }
        }
    }

    /// Encoded and written off the main thread, atomically.
    nonisolated private static func writeFile(_ file: StoreFile) {
        let url = fileURL
        ioQueue.async {
            guard let data = try? JSONEncoder().encode(file) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    nonisolated private static func values(of focus: Focus) -> [Double] {
        func r(_ v: CGFloat) -> Double { (Double(v) * 100_000).rounded() / 100_000 }
        return [r(focus.rect.minX), r(focus.rect.minY), r(focus.rect.width), r(focus.rect.height),
                focus.face ? 1 : 0, Double(focus.index)]
    }

    /// Five values (the index defaults to the first candidate) or six; anything outside the unit
    /// square is not an answer.
    nonisolated private static func focus(from v: [Double]) -> Focus? {
        guard v.count >= 5, v[0...3].allSatisfy({ $0.isFinite }) else { return nil }
        let rect = CGRect(x: v[0], y: v[1], width: v[2], height: v[3])
        guard rect.width > 0, rect.height > 0, rect.minX >= 0, rect.minY >= 0,
              rect.maxX <= 1.0001, rect.maxY <= 1.0001 else { return nil }
        let index = v.count >= 6 && v[5].isFinite ? max(0, Int(v[5])) : 0
        return Focus(index: index, rect: rect, face: v[4] >= 0.5)
    }
}
