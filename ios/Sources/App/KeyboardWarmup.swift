import SwiftUI
import UIKit

/// The text-input session, started ONCE, unseen, at an idle moment after launch — so the first
/// tap on a search field gets the system's transition and not the system's setup.
///
/// What the first focus of a process costs, sampled on the simulator (5–6 Sep, the focus films,
/// `Tools/perf/focus_film.py`): the text-input session (`TextInput`, `RemoteTextInput`,
/// `liblangid` through AutoFill), the keyboard's own layout and key images (`TextInputUI`,
/// `CoreUI`), the search controller's view — 750 ms of main thread with no warm-up, against
/// ~240 ms for every later focus (the system's presentation work). A real keyboard cannot be
/// warmed unseen: on iOS 26+ the keyboard is composited from outside the app — the only window a
/// presentation adds to our scene is `UITextEffectsWindow` (level 10) — so there is nothing in
/// this process to hide, and a warm-up that let the keyboard present was filmed showing it over
/// Today for 0.7 s (6 Sep). What CAN be warmed is the session: a search text field with the
/// searchable field's traits and an EMPTY input view takes first responder — the session starts,
/// the frameworks load, no keyboard is asked for (`keyboardWillShow` reports a zero height) —
/// holds for `hold` so the asynchronous parts settle, and resigns. Nothing is ever on screen.
///
/// It runs a beat after the app has emerged, only while the person is still at rest on the tab
/// they launched on, only after `idle` without a touch (`install()` timestamps them), never over a
/// banner or a lane, never in Low Power Mode, never under `-perfNoWarm 1`.
@MainActor
final class KeyboardWarmup: NSObject {
    /// After the app has emerged: long enough that the ident and the first billboard are settled,
    /// short enough to beat a person's first tap on Search.
    static let delay: Duration = .milliseconds(1800)
    /// How long the field keeps first responder, so the session's asynchronous setup lands.
    static let hold: Duration = .milliseconds(500)
    /// How long the screen must have been untouched before the session is started.
    static let idle: TimeInterval = 0.8
    /// How long `warm` keeps waiting for that idle span before giving up for this launch.
    static let patience: Duration = .seconds(8)

    private static var done = false
    private static var current: KeyboardWarmup?
    private static var lastTouch: Date = .distantPast
    private static var touchWatch: TouchWatch?

    /// The class the system's search bar uses, with the traits the searchable field carries.
    private let field = UISearchTextField(frame: .zero)

    /// Call once, early (the app's root task): from then on the key window's touches are
    /// timestamped, which is what `warm` waits on.
    static func install() {
        guard touchWatch == nil,
              let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
                .flatMap(\.windows).first(where: \.isKeyWindow) else { return }
        let watch = TouchWatch()
        let press = UILongPressGestureRecognizer(target: watch, action: #selector(TouchWatch.press(_:)))
        press.minimumPressDuration = 0
        press.cancelsTouchesInView = false
        press.delaysTouchesBegan = false
        press.delaysTouchesEnded = false
        press.delegate = watch
        window.addGestureRecognizer(press)
        touchWatch = watch
    }

    /// `allowed` is the caller's word that nothing on screen would move with an input view's
    /// safe-area inset (no banner, no lane) — the inset is zero here, but the notifications fire.
    static func warm(allowed: Bool = true) {
        guard !done, allowed, !ProcessInfo.processInfo.isLowPowerModeEnabled, !PerfProbe.flag("perfNoWarm") else { return }
        done = true
        Task { @MainActor in
            let deadline = ContinuousClock.now + patience
            while Date().timeIntervalSince(lastTouch) < idle {
                if ContinuousClock.now > deadline { PerfProbe.mark("keyboard-warm", "skipped-busy"); return }
                try? await Task.sleep(for: .milliseconds(250))
            }
            guard let window = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .first(where: { $0.activationState == .foregroundActive })?
                    .windows.first(where: \.isKeyWindow)
            else { return }
            let warmup = KeyboardWarmup()
            current = warmup
            warmup.run(in: window)
        }
    }

    private func run(in keyWindow: UIWindow) {
        field.alpha = 0
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.returnKeyType = .search
        field.enablesReturnKeyAutomatically = true
        // No keyboard: an empty input view is what the session presents, and it has no height.
        field.inputView = UIView(frame: .zero)
        field.inputAccessoryView = nil
        keyWindow.addSubview(field)
        field.becomeFirstResponder()
        PerfProbe.mark("keyboard-warm", "begin")
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: KeyboardWarmup.hold)
            guard let self else { return }
            if self.field.isFirstResponder { self.field.resignFirstResponder() }
            self.field.removeFromSuperview()
            if KeyboardWarmup.current === self { KeyboardWarmup.current = nil }
            PerfProbe.mark("keyboard-warm", "end")
        }
    }

    /// Timestamps touch-downs; recognises alongside everything and cancels nothing.
    private final class TouchWatch: NSObject, UIGestureRecognizerDelegate {
        @objc func press(_ g: UILongPressGestureRecognizer) {
            if g.state == .began { KeyboardWarmup.lastTouch = Date() }
        }
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool { false }
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRequireFailureOf other: UIGestureRecognizer) -> Bool { false }
    }
}
