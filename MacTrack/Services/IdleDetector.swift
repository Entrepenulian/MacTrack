import AppKit
import CoreGraphics

/// Decides whether the user is actually present. Two signals:
///   1. Seconds since the last HID input (keyboard/mouse/trackpad).
///   2. Screen-lock / display-sleep notifications.
/// If either says "away", the sampler attributes no time — so a window left
/// open while you make coffee never inflates your totals.
final class IdleDetector {

    /// Treat the user as away after this many seconds without input.
    var idleThreshold: TimeInterval = 120

    private(set) var isLocked = false

    init() {
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(self, selector: #selector(screenLocked),
                        name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)
        dnc.addObserver(self, selector: #selector(screenUnlocked),
                        name: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil)

        let wsnc = NSWorkspace.shared.notificationCenter
        wsnc.addObserver(self, selector: #selector(screenLocked),
                         name: NSWorkspace.screensDidSleepNotification, object: nil)
        wsnc.addObserver(self, selector: #selector(screenUnlocked),
                         name: NSWorkspace.screensDidWakeNotification, object: nil)
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func screenLocked() { isLocked = true }
    @objc private func screenUnlocked() { isLocked = false }

    /// Seconds since any input event across the whole session.
    var secondsSinceInput: TimeInterval {
        let anyInput = CGEventType(rawValue: ~0) ?? .null
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }

    var isPresent: Bool {
        !isLocked && secondsSinceInput < idleThreshold
    }
}
