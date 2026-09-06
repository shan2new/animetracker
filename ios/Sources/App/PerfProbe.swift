import SwiftUI
import QuartzCore
import Darwin

/// The frame-pacing probe (`-perfProbe 1`, DEBUG only).
///
/// Two instruments in one file, because Instruments cannot attach to this simulator (both Xcodes'
/// xctrace record an empty trace against the iOS 27 runtime, 5 Sep):
///
/// 1. **Hitches.** A `CADisplayLink` on the main run loop — in the common modes, so it keeps
///    firing under a scroll — writes every gap between two presented frames longer than
///    `hitchFloor` to `Documents/perf.jsonl`, with the screen that was up.
/// 2. **Stalls, with stacks.** A watchdog thread notices when the main thread has not heartbeat
///    for `stallFloor` and samples its stack every `sampleEvery` until it moves again: the
///    thread is suspended, its frame-pointer chain is copied into a preallocated buffer (no
///    allocation, no symbolication, nothing that could take a lock the main thread holds), it
///    is resumed, and only then are the addresses symbolicated with `dladdr`. A hitch therefore
///    arrives with the code that caused it — the app's own frames, mangled; `perf/stalls.py`
///    demangles and aggregates them per step.
///
/// The scratchpad's `perf/flow.py` drives a scripted flow through idb, stamps its steps, and
/// scores the log against them. Inert without the launch argument, compiled out of every
/// non-DEBUG build, and never a cost to the thing it measures: one buffered write a second,
/// nothing per frame but an integer compare, and the watchdog sleeps unless the main thread is
/// already stuck.
@MainActor
enum PerfProbe {
    #if DEBUG || PERFPROBE
    static let enabled = UserDefaults.standard.bool(forKey: "perfProbe")
    #else
    static let enabled = false
    #endif

    /// A gap this long between two presented frames is a hitch worth a line: two frames at 60 Hz.
    nonisolated static let hitchFloor: Double = 34
    /// The main thread has not heartbeat for this long: a stall the watchdog starts sampling.
    nonisolated static let stallFloor: UInt64 = 40_000_000
    /// Between two samples of one stall.
    nonisolated static let sampleEvery: UInt32 = 20_000
    nonisolated static let maxSamplesPerStall = 80

    /// A DEBUG A/B switch (`-perfNoShelfMask 1`, `-perfNoMaterial 1`, `-perfNoDrift 1`): one build
    /// measured with and without a suspect, instead of a build per hypothesis. Always false
    /// outside DEBUG (or a `-D PERFPROBE` measurement build).
    static func flag(_ key: String) -> Bool {
        #if DEBUG || PERFPROBE
        if let hit = flags[key] { return hit }
        let v = UserDefaults.standard.bool(forKey: key)
        flags[key] = v
        return v
        #else
        return false
        #endif
    }
    private static var flags: [String: Bool] = [:]

    private(set) static var screen = "launch"
    private static var stack: [String] = []
    private static var link: CADisplayLink?
    private static var last: CFTimeInterval = 0
    private static var frames = 0
    private static var hitches = 0
    private static var lastFlush: CFTimeInterval = 0
    private static let log = PerfLog()

    static func start() {
        guard enabled, link == nil else { return }
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("perf.jsonl")
        log.open(url)
        let l = CADisplayLink(target: Ticker.shared, selector: #selector(Ticker.tick(_:)))
        l.add(to: .main, forMode: .common)
        link = l
        log.write(#"{"event":"start","t":\#(PerfLog.nowMs())}"#)
        log.flush()
        StallSampler.start(log: log)
        observeKeyboard()
        observeTouches()
    }

    /// Every touch-down on the key window, as a mark with its point — the honest zero for a
    /// tap's latency (a driver's own clock includes its transport). A press recogniser with no
    /// minimum duration that cancels nothing and recognises alongside everything.
    private static var touchProbe: TouchProbe?
    private static func observeTouches() {
        Task { @MainActor in
            for _ in 0..<40 {
                if let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
                    .flatMap(\.windows).first(where: \.isKeyWindow) {
                    let probe = TouchProbe()
                    let press = UILongPressGestureRecognizer(target: probe, action: #selector(TouchProbe.press(_:)))
                    press.minimumPressDuration = 0
                    press.cancelsTouchesInView = false
                    press.delaysTouchesBegan = false
                    press.delaysTouchesEnded = false
                    press.delegate = probe
                    window.addGestureRecognizer(press)
                    touchProbe = probe
                    return
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    @MainActor
    private final class TouchProbe: NSObject, UIGestureRecognizerDelegate {
        @objc func press(_ g: UILongPressGestureRecognizer) {
            guard g.state == .began else { return }
            let p = g.location(in: g.view)
            PerfProbe.mark("touch-down", "\(Int(p.x)),\(Int(p.y))")
        }
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool { false }
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRequireFailureOf other: UIGestureRecognizer) -> Bool { false }
    }

    /// A screen came up (`perfScreen`). The stack keeps a pushed page's parent for its pop.
    static func push(_ name: String) {
        guard enabled else { return }
        stack.append(name)
        setScreen(name)
    }

    static func pop(_ name: String) {
        guard enabled else { return }
        if let i = stack.lastIndex(of: name) { stack.remove(at: i) }
        setScreen(stack.last ?? "root")
    }

    /// A moment worth a line of its own — a push, a mark — stamped from the app's side.
    static func mark(_ name: String, _ detail: String = "") {
        guard enabled else { return }
        log.write(#"{"event":"mark","name":"\#(name)","detail":"\#(detail)","screen":"\#(screen)","t":\#(PerfLog.nowMs())}"#)
    }

    /// The keyboard's four moments, with the frame it is heading for and the system's own
    /// animation duration — so a focus can be scored from the app's clock: tap → field presented
    /// → keyboard will show → keyboard did show, and the same on the way out.
    private static func observeKeyboard() {
        let moments: [(String, Notification.Name)] = [
            ("keyboard-will-show", UIResponder.keyboardWillShowNotification),
            ("keyboard-did-show", UIResponder.keyboardDidShowNotification),
            ("keyboard-will-hide", UIResponder.keyboardWillHideNotification),
            ("keyboard-did-hide", UIResponder.keyboardDidHideNotification),
        ]
        for (name, note) in moments {
            NotificationCenter.default.addObserver(forName: note, object: nil, queue: .main) { n in
                let end = (n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect) ?? .zero
                let duration = (n.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0
                MainActor.assumeIsolated {
                    mark(name, "h=\(Int(end.height)) y=\(Int(end.minY)) dur=\(duration)")
                }
            }
        }
    }

    private static func setScreen(_ name: String) {
        guard name != screen else { return }
        screen = name
        StallSampler.screen = name
        log.write(#"{"event":"screen","screen":"\#(name)","t":\#(PerfLog.nowMs())}"#)
    }

    fileprivate static func frame(gapMs: Double, t: CFTimeInterval) {
        frames += 1
        StallSampler.heartbeat()
        if gapMs >= hitchFloor {
            hitches += 1
            log.write(#"{"event":"hitch","ms":\#(Int(gapMs.rounded())),"screen":"\#(screen)","t":\#(PerfLog.nowMs())}"#)
        }
        if t - lastFlush > 1 {
            lastFlush = t
            log.write(#"{"event":"frames","n":\#(frames),"hitches":\#(hitches),"screen":"\#(screen)","t":\#(PerfLog.nowMs())}"#)
            log.flush()
        }
    }

    @MainActor
    private final class Ticker: NSObject {
        static let shared = Ticker()

        @objc func tick(_ link: CADisplayLink) {
            let t = link.timestamp
            if PerfProbe.last > 0 { PerfProbe.frame(gapMs: (t - PerfProbe.last) * 1000, t: t) }
            PerfProbe.last = t
        }
    }
}

extension View {
    /// Names this screen for the frame-pacing probe. Inert unless the app was launched with
    /// `-perfProbe 1`.
    func perfScreen(_ name: String) -> some View {
        onAppear { PerfProbe.push(name) }
            .onDisappear { PerfProbe.pop(name) }
    }
}

// MARK: - The log

/// One append-only JSON-lines file, written from the main thread (hitches, screens) and the
/// watchdog (stalls) under a lock.
final class PerfLog: @unchecked Sendable {
    private let lock = NSLock()
    private var handle: FileHandle?
    private var pending = ""

    func open(_ url: URL) {
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        handle = try? FileHandle(forWritingTo: url)
        _ = try? handle?.seekToEnd()
    }

    func write(_ line: String) {
        lock.lock(); pending += line + "\n"; lock.unlock()
    }

    func flush() {
        lock.lock()
        let out = pending; pending = ""
        lock.unlock()
        guard !out.isEmpty, let handle else { return }
        handle.write(Data(out.utf8))
    }

    static func nowMs() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }
}

// MARK: - The stall sampler

/// See `PerfProbe`. Everything the watchdog touches while the main thread is SUSPENDED is a
/// preallocated buffer or a register read; the walk is bounded by the main thread's own stack.
enum StallSampler {
    nonisolated(unsafe) private static var mainThread: thread_t = 0
    nonisolated(unsafe) private static var stackLo: UInt = 0
    nonisolated(unsafe) private static var stackHi: UInt = 0
    nonisolated(unsafe) private static var lastBeat: UInt64 = 0
    nonisolated(unsafe) private static var pcs: UnsafeMutablePointer<UInt> = .allocate(capacity: 128)
    nonisolated(unsafe) private static var log: PerfLog?
    nonisolated(unsafe) static var screen = "launch"
    nonisolated(unsafe) private static var timebase = mach_timebase_info_data_t()

    @MainActor
    static func start(log: PerfLog) {
        self.log = log
        mainThread = mach_thread_self()
        let top = UInt(bitPattern: pthread_get_stackaddr_np(pthread_self()))
        let size = UInt(pthread_get_stacksize_np(pthread_self()))
        stackHi = top
        stackLo = top >= size ? top - size : 0
        mach_timebase_info(&timebase)
        lastBeat = now()
        let thread = Thread { watch() }
        thread.name = "perf.stall-sampler"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    /// The main thread is alive: called from the display link.
    static func heartbeat() { lastBeat = now() }

    private static func now() -> UInt64 {
        let t = mach_absolute_time()
        return timebase.denom == 0 ? t : t * UInt64(timebase.numer) / UInt64(timebase.denom)
    }

    private static func watch() {
        var samples: [(elapsed: UInt64, frames: [String])] = []
        var stalled = false
        var stallStart: UInt64 = 0
        var beatAtStart: UInt64 = 0
        while true {
            usleep(stalled ? sampleEvery : 4_000)
            let beat = lastBeat
            let t = now()
            if !stalled {
                guard t - beat >= PerfProbe.stallFloor else { continue }
                stalled = true; stallStart = beat; beatAtStart = beat; samples.removeAll(keepingCapacity: true)
            } else if beat != beatAtStart {
                // The main thread moved: the stall is over.
                emit(total: (beat - stallStart) / 1_000_000, samples: samples)
                stalled = false
                continue
            }
            guard samples.count < PerfProbe.maxSamplesPerStall else { continue }
            let n = walk()
            if n > 0 { samples.append((elapsed: (t - stallStart) / 1_000_000, frames: symbolicate(count: n))) }
        }
    }

    private static let sampleEvery = PerfProbe.sampleEvery

    /// Copy the main thread's frame-pointer chain into `pcs`. Returns the frame count.
    private static func walk() -> Int {
        let thread = mainThread
        guard thread != 0, thread_suspend(thread) == KERN_SUCCESS else { return 0 }
        defer { thread_resume(thread) }
        var count = 0
        var fp: UInt = 0
        #if arch(arm64)
        var state = arm_thread_state64_t()
        var stateCount = mach_msg_type_number_t(MemoryLayout<arm_thread_state64_t>.size / MemoryLayout<UInt32>.size)
        let kr = withUnsafeMutablePointer(to: &state) { p in
            p.withMemoryRebound(to: natural_t.self, capacity: Int(stateCount)) {
                thread_get_state(thread, thread_state_flavor_t(ARM_THREAD_STATE64), $0, &stateCount)
            }
        }
        guard kr == KERN_SUCCESS else { return 0 }
        pcs[count] = UInt(state.__pc); count += 1
        pcs[count] = UInt(state.__lr); count += 1
        fp = UInt(state.__fp)
        #elseif arch(x86_64)
        var state = x86_thread_state64_t()
        var stateCount = mach_msg_type_number_t(MemoryLayout<x86_thread_state64_t>.size / MemoryLayout<UInt32>.size)
        let kr = withUnsafeMutablePointer(to: &state) { p in
            p.withMemoryRebound(to: natural_t.self, capacity: Int(stateCount)) {
                thread_get_state(thread, thread_state_flavor_t(x86_THREAD_STATE64), $0, &stateCount)
            }
        }
        guard kr == KERN_SUCCESS else { return 0 }
        pcs[count] = UInt(state.__rip); count += 1
        fp = UInt(state.__rbp)
        #else
        return 0
        #endif
        while count < 120, fp >= stackLo, fp + 16 <= stackHi, fp & 7 == 0 {
            let frame = UnsafeRawPointer(bitPattern: fp)!
            let next = frame.load(as: UInt.self)
            let ret = frame.load(fromByteOffset: 8, as: UInt.self)
            guard ret != 0 else { break }
            pcs[count] = ret; count += 1
            guard next > fp else { break }
            fp = next
        }
        return count
    }

    /// After the resume: names for the copied addresses. Frames of the app's own binary are
    /// kept with their mangled symbol; system frames keep the image's name only, so the report
    /// can still see "in CoreText" without a thousand distinct strings.
    private static func symbolicate(count: Int) -> [String] {
        var out: [String] = []
        out.reserveCapacity(count)
        var info = Dl_info()
        for i in 0..<count {
            let pc = pcs[i]
            guard let p = UnsafeRawPointer(bitPattern: pc), dladdr(p, &info) != 0 else { out.append("?"); continue }
            let image = info.dli_fname.map { String(cString: $0) }.map { ($0 as NSString).lastPathComponent } ?? "?"
            // The app's code lives in `AniTrack.debug.dylib` under Xcode's debug-dylib builds.
            if image.hasPrefix("AniTrack"), let s = info.dli_sname {
                out.append(String(cString: s))
            } else {
                let sym = info.dli_sname.map { String(cString: $0) } ?? ""
                out.append("[\(image)] \(sym.prefix(80))")
            }
        }
        return out
    }

    private static func emit(total: UInt64, samples: [(elapsed: UInt64, frames: [String])]) {
        guard let log, !samples.isEmpty else { return }
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "\\", with: "/").replacingOccurrences(of: "\"", with: "'")
        }
        let body = samples.map { s in
            #"{"ms":\#(s.elapsed),"frames":[\#(s.frames.map { "\"\(esc($0))\"" }.joined(separator: ","))]}"#
        }.joined(separator: ",")
        log.write(#"{"event":"stall","ms":\#(total),"screen":"\#(screen)","t":\#(PerfLog.nowMs()),"samples":[\#(body)]}"#)
        log.flush()
    }
}
