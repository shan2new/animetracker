import UIKit
import QuartzCore
import Metal
import MetalKit

/// GLASS — the Lens gesture (`SplashLens`), drawn as real optics on the GPU.
///
/// The same film: a bead of clear glass glides along the line where the name will be, and through
/// it the name is already there; the letters stay behind as it passes; past the "y" it fills with
/// coral and settles into the full stop's place. What Core Animation could only suggest — a flat
/// magnified circle inside a rim — is here the optics themselves (`SplashGlass.metal`): a dome that
/// magnifies at its centre and bends the letters hard toward its rim, with a trace of dispersion
/// there; a fresnel rim and two highlights from a light at the upper left; the light it focuses
/// glowing inside it and on the page beneath; the newest letters surfacing warm and settling to
/// white; coral ink blooming from the centre of the glass until the bead IS the full stop.
///
/// Frames are drawn on a thread of their own by a display link, each at the film time it will be
/// presented — so, like the Core Animation films, nothing the main thread does while the app builds
/// underneath can stall it. Without Metal the film plays as `SplashLockup`.
@MainActor
final class SplashGlassFilm: SplashFilm {
    private var renderer: SplashGlassRenderer?
    private var fallback: SplashLockup?
    private var layer: CAMetalLayer?
    private let makeScript: @MainActor (SplashScene) -> (any SplashShaderScript)?

    /// A film drawn by a fragment shader from a script (`SplashGlassScript`, `SplashMacroScript`).
    init(_ makeScript: @escaping @MainActor (SplashScene) -> (any SplashShaderScript)? = { SplashGlassScript(scene: $0) }) {
        self.makeScript = makeScript
    }

    private var script: (any SplashShaderScript)?

    func build(on root: CALayer, scene: SplashScene) -> Double {
        guard let script = makeScript(scene),
              let renderer = SplashGlassRenderer(size: scene.size, scale: scene.scale, script: script) else {
            SplashTrace.mark("glass unavailable: lockup fallback")
            let lockup = SplashLockup()
            fallback = lockup
            return lockup.build(on: root, scene: scene)
        }
        self.renderer = renderer
        self.script = script
        layer = renderer.layer
        root.addSublayer(renderer.layer)
        renderer.startLink()
        return script.landAt
    }

    private var latePicturesDrawn = false

    /// The script's costly pictures, drawn once the film is rolling — never before its first frame.
    private func drawLatePictures() {
        guard !latePicturesDrawn, let renderer, let script else { return }
        latePicturesDrawn = true
        if let pictures = script.latePictures() { renderer.replace(textures: pictures) }
    }

    /// The way out, in two stages so the brand is never printed over the app: the lockup goes to
    /// plain canvas inside the film first (`leaving`, 0.18 s, receding a hair), then the canvas
    /// itself lifts off the app (0.08–0.38 s). The canvas is never scaled: scaled, its edges
    /// uncovered a rim of the app at full strength that flickered round the screen (review, 25 Sep).
    func exit(on root: CALayer, scene: SplashScene, at t: Double) -> Double {
        if let fallback { return fallback.exit(on: root, scene: scene, at: t) }
        guard let layer, let renderer else { return 0 }
        exitStart = t
        renderer.beginLeaving(at: root.convertTime(t, to: nil))
        layer.play(SplashTrack("opacity", 1.0, at: t + Self.groundLifts.0)
            .to(0.0, at: t + Self.groundLifts.1, Self.groundCurve))
        return Self.groundLifts.1 + 0.02
    }

    static let groundLifts = (0.08, 0.38)
    nonisolated(unsafe) static let groundCurve = CAMediaTimingFunction(controlPoints: 0.45, 0, 0.55, 1)
    private var exitStart: Double?

    func roll(at media: CFTimeInterval) {
        if let fallback { fallback.roll(at: media); return }
        renderer?.roll(at: media)
        DispatchQueue.main.async { [weak self] in self?.drawLatePictures() }
    }
    var elapsed: Double? { fallback?.elapsed ?? renderer?.elapsed }
    func still(at t: Double) {
        if let fallback { fallback.still(at: t); return }
        drawLatePictures()
        renderer?.hold(at: t)
    }
    func end() { renderer?.stop() }
    func frame(at t: Double) -> CGImage? {
        renderer?.image(at: t, leaving: exitStart.map { SplashGlassRenderer.leaving(t - $0) } ?? 0)
    }
    func whenFirstFrameShown(_ action: @escaping @MainActor () -> Void) {
        if let renderer { renderer.onFirstPresented = action } else { action() }
    }
}

// MARK: - Scripts

/// A film for a fragment shader: its functions, the picture of the name it samples, when it has
/// landed, and every uniform at film time `t` as `float4`s, in the order the shader declares them.
protocol SplashShaderScript: Sendable {
    var vertexFunction: String { get }
    var fragmentFunction: String { get }
    var name: CGImage { get }
    /// The name is seen much larger than it rests (a camera move): sample it through mipmaps.
    var mipmapped: Bool { get }
    var landAt: Double { get }
    func params(at t: Double) -> [SIMD4<Float>]
    /// The uniforms while the film is leaving: `leaving` 0 → 1 over the lockup's own way out.
    func params(at t: Double, leaving: Double) -> [SIMD4<Float>]
    /// A second pass over the first: a triangle strip the script lays out each frame (each vertex
    /// two `float4`s, in buffer 1; the uniforms in buffer 0 of both stages), blended premultiplied.
    /// No functions, no pass.
    var meshVertexFunction: String? { get }
    var meshFragmentFunction: String? { get }
    func mesh(at t: Double) -> [SIMD4<Float>]
    /// More pictures for the first pass, bound from texture 1 on.
    var images: [CGImage] { get }
    /// A last pass over the mesh — a full-screen triangle through this fragment function, with the
    /// first pass's uniforms and pictures, blended premultiplied. `nil`: none.
    var overFragmentFunction: String? { get }
    /// Pictures too costly for the first frame — the process's first text layout can take half a
    /// second (measured 25 Sep: the name alone, 444 ms, on a signed-in cold launch) — drawn on the
    /// main thread once the film is rolling, then bound from texture 0 on in place of `name` and
    /// `images`. `nil`: none.
    @MainActor func latePictures() -> [CGImage]?
}

extension SplashShaderScript {
    func params(at t: Double, leaving: Double) -> [SIMD4<Float>] { params(at: t) }
    var meshVertexFunction: String? { nil }
    var meshFragmentFunction: String? { nil }
    func mesh(at t: Double) -> [SIMD4<Float>] { [] }
    var images: [CGImage] { [] }
    var overFragmentFunction: String? { nil }
    @MainActor func latePictures() -> [CGImage]? { nil }
}

/// Everything on screen at film time `t`, as the shader's inputs. The geometry is the name's own
/// (`SplashTitle`'s outlines, the bundled Outfit), the motion the Lens film's curves.
struct SplashGlassScript: SplashShaderScript, @unchecked Sendable {
    let vertexFunction = "glassVertex"
    let fragmentFunction = "glassFragment"
    let mipmapped = false
    static let pointSize: CGFloat = 50
    static let lensRadius: CGFloat = 27
    static let power: CGFloat = 1.55
    static let departAt = 0.10
    static let arriveAt = 0.80
    /// The coral fills the bead once it is the full stop's size, in place — never over the "y".
    static let inkedAt = 0.93
    static let settledAt = 1.06
    static let glide = SplashEase(x1: 0.42, y1: 0, x2: 0.18, y2: 1)

    let size: CGSize
    let scale: CGFloat
    /// The name's box on screen, and its picture (letters only; the bead is its full stop).
    let text: CGRect
    let name: CGImage
    let from: CGPoint
    let to: CGPoint
    let stopRadius: CGFloat
    var landAt: Double { Self.settledAt + 0.18 }

    @MainActor
    init?(scene: SplashScene) {
        let title = SplashTitle(pointSize: Self.pointSize, tracking: -1.3, contentsScale: scene.scale)
        // Drawn at twice the screen's density: the glass magnifies it by half again.
        guard let shot = title.snapshot(scale: scene.scale * 2, blur: 0, includeStop: false) else { return nil }
        size = scene.size
        scale = scene.scale
        let origin = CGPoint(x: (scene.size.width / 2 - title.size.width / 2).rounded(),
                             y: (scene.size.height * 0.46 - title.size.height / 2).rounded())
        text = CGRect(origin: origin, size: title.size)
        name = shot.image
        let stop = title.stop.frame.offsetBy(dx: origin.x, dy: origin.y)
        stopRadius = stop.width / 2
        let line = origin.y + title.ascent - title.xHeight / 2
        let first = origin.x + (title.letters.first?.frame.minX ?? 0)
        from = CGPoint(x: first - Self.lensRadius * 0.35, y: line)
        to = CGPoint(x: stop.midX, y: stop.midY)
    }

    /// The shader's seven `float4`s at film time `t`.
    func params(at t: Double) -> [SIMD4<Float>] {
        let r0 = Self.lensRadius
        // Reading: along the line, then down onto the baseline at its mark, shrinking — still clear
        // glass, the "y" seen through it — to the full stop's own size as it arrives.
        let p = Self.glide(min(max((t - Self.departAt) / (Self.arriveAt - Self.departAt), 0), 1))
        let c = CGPoint(x: from.x + (to.x - from.x) * CGFloat(p),
                        y: from.y + (to.y - from.y) * CGFloat(SplashEase.step(p, 0.76, 1)))
        let m = Self.power + (1 - Self.power) * CGFloat(SplashEase.step(p, 0.62, 0.96))
        // Then the coral fills it, and it settles with one soft give, the way a drop lands.
        let ink = SplashEase.step(t, Self.arriveAt - 0.09, Self.inkedAt - 0.03)
        let land = min(max((t - Self.inkedAt + 0.05) / (Self.settledAt - Self.inkedAt + 0.05), 0), 1)
        let give = 0.16 * sin(Double.pi * land) * (1 - land)
        let r = (r0 + (stopRadius - r0) * CGFloat(SplashEase.step(p, 0.68, 1))) * CGFloat(1 + give)
        let presence = SplashEase.step(t, 0.0, 0.16)
        // The letters surface behind the bead's trailing edge; as it arrives the front runs on
        // past the word, so every letter is whole.
        let front: CGFloat = c.x - r * 0.55 + CGFloat(SplashEase.step(t, Self.arriveAt - 0.10, Self.inkedAt)) * 140
        let develop = 1 - SplashEase.step(t, Self.arriveAt - 0.05, Self.settledAt + 0.20)
        let glow = SplashEase.step(t, Self.arriveAt - 0.02, Self.inkedAt + 0.02)
            * (1 - 0.65 * SplashEase.step(t, Self.inkedAt + 0.02, Self.settledAt + 0.55))
        let warmth = SplashEase.step(t, 0.0, 0.7)
        let sweep = (t - (Self.settledAt + 0.08)) / 0.42
        let canvas = SIMD4<Float>(0x09 / 255, 0x09 / 255, 0x0B / 255, 1)
        let coral = SIMD4<Float>(0xF0 / 255, 0x56 / 255, 0x3F / 255, 1)
        return [
            SIMD4(Float(size.width), Float(size.height), Float(scale), Float(t)),
            SIMD4(Float(text.minX), Float(text.minY), Float(text.width), Float(text.height)),
            SIMD4(Float(c.x), Float(c.y), Float(r), Float(m)),
            SIMD4(Float(ink), Float(presence), Float(front), Float(glow)),
            SIMD4(Float(develop), Float(warmth), Float(sweep), 0),
            canvas,
            coral,
        ]
    }
}

// MARK: - The renderer

/// Draws the script on a thread of its own, each frame at the film time it will be presented.
final class SplashGlassRenderer: NSObject, @unchecked Sendable {
    let layer: CAMetalLayer
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let meshPipeline: MTLRenderPipelineState?
    private let overPipeline: MTLRenderPipelineState?
    /// The first pass's pictures: the name, then the script's `images` (replaced under `lock` when
    /// the late pictures land).
    private var textures: [MTLTexture]
    private let loader: MTKTextureLoader
    private let sampler: MTLSamplerState
    private let script: any SplashShaderScript

    private let lock = NSLock()
    /// Media time at which film time 0 is presented; `nil` while held at `held`.
    private var start: CFTimeInterval?
    private var held: Double = 0
    /// The film's own clock: live time from the frames the link actually asked for, with any stall
    /// longer than `stallCut` taken out — up to `stallBudget` in all — so a hitch pauses the
    /// ribbon where it was instead of skipping the part of the film that says what it becomes.
    /// Past the budget wall time drives, so a starved launch still ends.
    private var clock: Double = 0
    private var lastTarget: CFTimeInterval?
    private var cutSoFar: Double = 0
    /// The film time of the newest frame the display actually SHOWED (a drawable's presented
    /// handler), and when the way out began. A frame committed is not a frame seen: on the Pro
    /// Max the screen held one frame for 0.33 s while the link kept committing on cadence.
    private var presented: Double?
    private var leaveMedia: CFTimeInterval?
    /// Called on the main queue when the first frame reaches the screen.
    var onFirstPresented: (@MainActor () -> Void)?
    private var firstPresented = false
    static let stallCut = 0.25
    static let stallBudget = 0.40
    private var stopped = false
    private var thread: Thread?

    @MainActor
    init?(size: CGSize, scale: CGFloat, script: any SplashShaderScript) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary(),
              let vertex = library.makeFunction(name: script.vertexFunction),
              let fragment = library.makeFunction(name: script.fragmentFunction),
              let name = try? MTKTextureLoader(device: device).newTexture(
                cgImage: script.name,
                options: [.SRGB: false, .generateMipmaps: script.mipmapped, .allocateMipmaps: script.mipmapped]) else {
            return nil
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }
        let loader = MTKTextureLoader(device: device)
        var pictures: [MTLTexture] = [name]
        for image in script.images {
            guard let texture = try? loader.newTexture(cgImage: image, options: [.SRGB: false]) else { return nil }
            pictures.append(texture)
        }
        var meshPipeline: MTLRenderPipelineState?
        if let vertexName = script.meshVertexFunction, let fragmentName = script.meshFragmentFunction {
            guard let meshVertex = library.makeFunction(name: vertexName),
                  let meshFragment = library.makeFunction(name: fragmentName) else { return nil }
            let mesh = MTLRenderPipelineDescriptor()
            mesh.vertexFunction = meshVertex
            mesh.fragmentFunction = meshFragment
            let colour = mesh.colorAttachments[0]!
            colour.pixelFormat = .bgra8Unorm
            colour.isBlendingEnabled = true
            colour.sourceRGBBlendFactor = .one
            colour.sourceAlphaBlendFactor = .one
            colour.destinationRGBBlendFactor = .oneMinusSourceAlpha
            colour.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            guard let state = try? device.makeRenderPipelineState(descriptor: mesh) else { return nil }
            meshPipeline = state
        }
        var overPipeline: MTLRenderPipelineState?
        if let fragmentName = script.overFragmentFunction {
            guard let overFragment = library.makeFunction(name: fragmentName) else { return nil }
            let over = MTLRenderPipelineDescriptor()
            over.vertexFunction = vertex
            over.fragmentFunction = overFragment
            let colour = over.colorAttachments[0]!
            colour.pixelFormat = .bgra8Unorm
            colour.isBlendingEnabled = true
            colour.sourceRGBBlendFactor = .one
            colour.sourceAlphaBlendFactor = .one
            colour.destinationRGBBlendFactor = .oneMinusSourceAlpha
            colour.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            guard let state = try? device.makeRenderPipelineState(descriptor: over) else { return nil }
            overPipeline = state
        }
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.mipFilter = script.mipmapped ? .linear : .notMipmapped
        samplerDescriptor.sAddressMode = .clampToZero
        samplerDescriptor.tAddressMode = .clampToZero
        guard let sampler = device.makeSamplerState(descriptor: samplerDescriptor) else { return nil }

        let layer = CAMetalLayer()
        layer.device = device
        layer.pixelFormat = .bgra8Unorm
        layer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        layer.framebufferOnly = true
        layer.isOpaque = true
        layer.contentsScale = scale
        layer.frame = CGRect(origin: .zero, size: size)
        layer.drawableSize = CGSize(width: size.width * scale, height: size.height * scale)
        layer.backgroundColor = SplashInk.canvas.cgColor

        self.layer = layer
        self.device = device
        self.queue = queue
        self.pipeline = pipeline
        self.meshPipeline = meshPipeline
        self.overPipeline = overPipeline
        self.textures = pictures
        self.loader = loader
        self.sampler = sampler
        self.script = script
        super.init()
    }

    /// Binds `images` from texture 0 on, in place of what was there.
    func replace(textures images: [CGImage]) {
        let loaded = images.compactMap { try? loader.newTexture(cgImage: $0, options: [.SRGB: false]) }
        guard loaded.count == images.count else { return }
        lock.lock()
        for (i, texture) in loaded.enumerated() where i < textures.count { textures[i] = texture }
        lock.unlock()
    }

    // MARK: Clock

    func roll(at media: CFTimeInterval) {
        lock.lock(); start = media; lastTarget = nil; clock = 0; cutSoFar = 0; lock.unlock()
    }

    /// The film time of the frame to be presented at `media`.
    private func filmTime(at media: CFTimeInterval) -> Double {
        lock.lock(); defer { lock.unlock() }
        guard let start else { return held }
        guard let last = lastTarget else {
            lastTarget = media
            clock = max(media - start, 0)
            return clock
        }
        var step = media - last
        if step > Self.stallCut, cutSoFar < Self.stallBudget {
            let cut = min(step - 1.0 / 60, Self.stallBudget - cutSoFar)
            cutSoFar += cut
            step -= cut
        }
        lastTarget = media
        clock += max(step, 0)
        // Frames drawn but never shown are a stall too: when the screen has fallen a quarter of a
        // second behind the film, the film goes back to the last frame seen (inside the same
        // budget), so the picture pauses where it was instead of jumping. Only where the screen
        // reports what it showed: the simulator's stand-in (the GPU finishing) runs late under
        // launch load with nothing wrong on screen, and rewound the film 0.35 s for nothing.
        #if targetEnvironment(simulator)
        let followsScreen = false
        #else
        let followsScreen = true
        #endif
        if followsScreen, let presented, clock - presented > Self.stallCut, cutSoFar < Self.stallBudget {
            let back = min(clock - presented - 1.0 / 60, Self.stallBudget - cutSoFar)
            cutSoFar += back
            clock -= back
        }
        return clock
    }

    /// How far the film has got ON SCREEN: the film time of the newest frame the display showed
    /// (the clock itself only if presentation is never reported).
    var elapsed: Double {
        lock.lock(); defer { lock.unlock() }
        if start == nil { return held }
        #if targetEnvironment(simulator)
        return clock
        #else
        return presented ?? (clock > 0.5 ? clock : 0)
        #endif
    }

    /// The way out has begun at media time `media`.
    func beginLeaving(at media: CFTimeInterval) {
        lock.lock(); leaveMedia = media; lock.unlock()
    }

    /// The lockup's own way out, 0 → 1 over its first 0.18 s.
    static func leaving(_ since: Double) -> Double {
        leaveCurve(min(max(since / 0.18, 0), 1))
    }
    static let leaveCurve = SplashEase(x1: 0.4, y1: 0, x2: 0.6, y2: 1)

    // MARK: Frames

    /// Frames on a thread of their own, paced by the display, from now until `stop()`.
    ///
    /// A plain `CADisplayLink` on this thread's run loop, not a `CAMetalDisplayLink`: the Metal
    /// link only fires while the system is compositing the window for some other reason, so on a
    /// launch whose app goes quiet under the film (signed out: sign-in lays out once and idles) it
    /// fell silent 0.4 s in and woke only when the exit's animation began — 1.7 s of one frozen
    /// frame, then a jump to the landing (measured 25 Sep, two devices, both signed out). This link
    /// fires every refresh whatever the rest of the app is doing, and the frame asks the layer for
    /// its drawable itself.
    func startLink() {
        let thread = Thread { [weak self] in
            guard let self else { return }
            let link = CADisplayLink(target: self, selector: #selector(self.step(_:)))
            // Low Power Mode asks the phone for less: the film holds to 60.
            link.preferredFrameRateRange = ProcessInfo.processInfo.isLowPowerModeEnabled
                ? CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
                : CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
            link.add(to: .current, forMode: .default)
            while !self.isStopped {
                RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.25))
            }
            link.invalidate()
        }
        thread.name = "splash.glass"
        thread.qualityOfService = .userInteractive
        self.thread = thread
        thread.start()
    }

    private var isStopped: Bool {
        lock.lock(); defer { lock.unlock() }
        return stopped
    }

    func stop() {
        lock.lock(); stopped = true; lock.unlock()
    }

    @objc private func step(_ link: CADisplayLink) {
        guard !isStopped, let drawable = layer.nextDrawable(), let buffer = queue.makeCommandBuffer() else { return }
        let target = link.targetTimestamp
        let t = filmTime(at: target)
        lock.lock(); let leftAt = leaveMedia; lock.unlock()
        encode(into: buffer, target: drawable.texture, at: t, leaving: leftAt.map { Self.leaving(target - $0) } ?? 0)
        #if DEBUG
        let asked = CACurrentMediaTime()
        #endif
        // What the screen showed. A phone reports each drawable's presentation; the simulator's
        // SDK has no presented handler, so there the GPU finishing the frame stands in for it.
        let seen: @Sendable (CFTimeInterval) -> Void = { [weak self] shownAt in
            guard let self else { return }
            #if DEBUG
            if SplashTrace.on {
                print(String(format: "SPLASH_FRAME asked=%.4f target=%.4f shown=%.4f film=%.4f",
                             asked, target, shownAt, t))
            }
            #endif
            guard shownAt > 0 else { return }       // dropped: never on screen
            self.lock.lock()
            self.presented = max(self.presented ?? 0, t)
            let first = !self.firstPresented
            self.firstPresented = true
            let action = first ? self.onFirstPresented : nil
            self.lock.unlock()
            if let action { DispatchQueue.main.async { MainActor.assumeIsolated { action() } } }
        }
        #if targetEnvironment(simulator)
        buffer.addCompletedHandler { _ in seen(CACurrentMediaTime()) }
        #else
        drawable.addPresentedHandler { shown in seen(shown.presentedTime) }
        #endif
        // Presented at the next refresh after the frame is done. `present(_:atTime:)` held each
        // drawable to its target, and with three in flight the link waited on `nextDrawable` —
        // 60 fps fell to 40 on every device (measured 25 Sep).
        buffer.present(drawable)
        buffer.commit()
    }

    /// DEBUG photography: the link keeps drawing, held at `t`.
    func hold(at t: Double) {
        lock.lock(); start = nil; held = t; lock.unlock()
    }

    /// DEBUG: the frame at `t`, drawn offscreen — the way a film is recorded frame-exact.
    func image(at t: Double, leaving: Double = 0) -> CGImage? {
        let w = Int(layer.drawableSize.width), h = Int(layer.drawableSize.height)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        guard let target = device.makeTexture(descriptor: descriptor), let buffer = queue.makeCommandBuffer() else { return nil }
        encode(into: buffer, target: target, at: t, leaving: leaving)
        buffer.commit()
        buffer.waitUntilCompleted()
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        target.getBytes(&bytes, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: space,
                       bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    private func encode(into buffer: MTLCommandBuffer, target: MTLTexture, at t: Double, leaving: Double = 0) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        var params = script.params(at: t, leaving: leaving)
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&params, length: MemoryLayout<SIMD4<Float>>.stride * params.count, index: 0)
        lock.lock(); let textures = self.textures; lock.unlock()
        for (i, texture) in textures.enumerated() { encoder.setFragmentTexture(texture, index: i) }
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        if let meshPipeline {
            let vertices = script.mesh(at: t)
            if vertices.count >= 8,
               let strip = device.makeBuffer(bytes: vertices, length: MemoryLayout<SIMD4<Float>>.stride * vertices.count) {
                encoder.setRenderPipelineState(meshPipeline)
                encoder.setVertexBytes(&params, length: MemoryLayout<SIMD4<Float>>.stride * params.count, index: 0)
                encoder.setVertexBuffer(strip, offset: 0, index: 1)
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: vertices.count / 2)
            }
        }
        if let overPipeline {
            encoder.setRenderPipelineState(overPipeline)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }
        encoder.endEncoding()
    }
}
