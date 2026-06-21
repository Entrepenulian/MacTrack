import AppKit

/// Helpers for the one permission MacTrack needs: Automation, so it can read the
/// active tab's URL from your browser. We can't query Automation state directly
/// without prompting, so the UI infers it from whether reads are succeeding
/// (see ActivityMonitor.automationDenied) and offers a shortcut to Settings.
enum Permissions {

    /// Opens System Settings → Privacy & Security → Automation.
    static func openAutomationSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!
        NSWorkspace.shared.open(url)
    }

    /// Nudges Safari/Chrome to surface the Automation prompt by issuing one read.
    static func primeAutomationPrompt(reader: BrowserURLReader) {
        for bundleID in BrowserURLReader.browsers.keys {
            if NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first != nil {
                reader.fetch(bundleID: bundleID) { _ in }
            }
        }
    }
}
