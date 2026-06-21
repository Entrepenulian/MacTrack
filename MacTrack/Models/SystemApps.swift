import Foundation

/// Background / system UI processes that can momentarily hold focus (a
/// notification banner, the lock screen, Spotlight) but are not apps you "use".
/// These are filtered out so the list shows only real apps and websites.
///
/// The primary signal is `NSRunningApplication.activationPolicy == .regular`
/// (a real, Dock-visible app). This explicit set is a backstop and is also used
/// to hide any such entries already recorded before the filter existed.
enum SystemApps {
    static let blockedBundleIDs: Set<String> = [
        "com.apple.loginwindow",
        "com.apple.UserNotificationCenter",
        "com.apple.notificationcenterui",
        "com.apple.dock",
        "com.apple.controlcenter",
        "com.apple.Spotlight",
        "com.apple.systemuiserver",
        "com.apple.WindowManager",
        "com.apple.screencaptureui",
        "com.apple.coreautha",
        "com.apple.SecurityAgent",
        "com.apple.ScreenSaver.Engine",
        "com.apple.PowerChime",
        "com.apple.wifi.WiFiAgent",
        "com.apple.TextInputMenuAgent",
        "com.apple.TextInputSwitcher",
    ]

    static func isBlocked(_ bundleID: String) -> Bool { blockedBundleIDs.contains(bundleID) }
}
