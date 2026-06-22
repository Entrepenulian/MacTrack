import AppKit

/// Reads the active tab's URL + title from a supported browser via Apple Events.
/// This is what makes per-website tracking possible. Scripts run off the main
/// thread on a serial queue; results hop back to the main queue.
///
/// The first read of each browser triggers macOS's Automation permission prompt.
/// We surface that state so the UI can ask the user to grant access.
final class BrowserURLReader {

    struct Browser {
        let bundleID: String
        let appName: String      // AppleScript application name
        let tabAccessor: String  // "current tab" (Safari) or "active tab" (Chromium)
    }

    /// Supported browsers, keyed by bundle identifier.
    static let browsers: [String: Browser] = [
        "com.apple.Safari":            Browser(bundleID: "com.apple.Safari", appName: "Safari", tabAccessor: "current tab"),
        "com.apple.SafariTechnologyPreview": Browser(bundleID: "com.apple.SafariTechnologyPreview", appName: "Safari Technology Preview", tabAccessor: "current tab"),
        "com.google.Chrome":           Browser(bundleID: "com.google.Chrome", appName: "Google Chrome", tabAccessor: "active tab"),
        "com.google.Chrome.canary":    Browser(bundleID: "com.google.Chrome.canary", appName: "Google Chrome Canary", tabAccessor: "active tab"),
        "com.microsoft.edgemac":       Browser(bundleID: "com.microsoft.edgemac", appName: "Microsoft Edge", tabAccessor: "active tab"),
        "com.brave.Browser":           Browser(bundleID: "com.brave.Browser", appName: "Brave Browser", tabAccessor: "active tab"),
        "company.thebrowser.Browser":  Browser(bundleID: "company.thebrowser.Browser", appName: "Arc", tabAccessor: "active tab"),
        "com.vivaldi.Vivaldi":         Browser(bundleID: "com.vivaldi.Vivaldi", appName: "Vivaldi", tabAccessor: "active tab"),
    ]

    static func isBrowser(_ bundleID: String) -> Bool { browsers[bundleID] != nil }

    private let queue = DispatchQueue(label: "com.mactrack.applescript", qos: .utility)
    private var compiled: [String: NSAppleScript] = [:]

    /// True once a read has failed with a permissions error and hasn't since
    /// succeeded. Lets the UI nudge the user toward System Settings.
    private(set) var automationDenied = false

    struct TabInfo { let url: URL; let title: String? }

    enum FetchResult {
        case tab(TabInfo)   // a real http(s) page
        case noURL          // front tab has no trackable URL (new/empty tab, Start Page, no window)
        case failed         // couldn't reach the browser (permission denied / transient)
    }

    func fetch(bundleID: String, completion: @escaping (FetchResult) -> Void) {
        guard let browser = Self.browsers[bundleID] else { completion(.failed); return }
        queue.async { [weak self] in
            guard let self else { return }
            let script = self.script(for: browser)
            var errorInfo: NSDictionary?
            let descriptor = script.executeAndReturnError(&errorInfo)

            if let errorInfo {
                let code = (errorInfo[NSAppleScript.errorNumber] as? Int) ?? 0
                // -1743 = not authorized to send Apple events; -600 = app not running.
                if code == -1743 { self.automationDenied = true }
                DispatchQueue.main.async { completion(.failed) }
                return
            }
            self.automationDenied = false

            let raw = descriptor.stringValue ?? ""
            let parts = raw.components(separatedBy: "\u{1F}") // unit separator
            let urlString = parts.first ?? ""
            let title = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines) : nil

            // No http(s) URL means an empty/new tab or Start Page — credit no site.
            guard let url = URL(string: urlString),
                  let scheme = url.scheme, scheme.hasPrefix("http") else {
                DispatchQueue.main.async { completion(.noURL) }
                return
            }
            DispatchQueue.main.async {
                completion(.tab(TabInfo(url: url, title: (title?.isEmpty == false) ? title : nil)))
            }
        }
    }

    /// Forces the active tab off a blocked site by loading about:blank.
    func blockActiveTab(bundleID: String) {
        guard let browser = Self.browsers[bundleID] else { return }
        queue.async {
            let source = """
            tell application "\(browser.appName)"
                if (count of windows) is 0 then return
                try
                    set URL of \(browser.tabAccessor) of front window to "about:blank"
                end try
            end tell
            """
            NSAppleScript(source: source)?.executeAndReturnError(nil)
        }
    }

    private func script(for browser: Browser) -> NSAppleScript {
        if let existing = compiled[browser.bundleID] { return existing }
        // Returns "url<US>title" or empty string if there's no front window.
        let source = """
        tell application "\(browser.appName)"
            if (count of windows) is 0 then return ""
            set theTab to \(browser.tabAccessor) of front window
            try
                set theURL to (URL of theTab) as text
            on error
                set theURL to ""
            end try
            try
                set theTitle to (name of theTab) as text
            on error
                set theTitle to ""
            end try
            return theURL & "\u{1F}" & theTitle
        end tell
        """
        let script = NSAppleScript(source: source)!
        compiled[browser.bundleID] = script
        return script
    }
}

// MARK: - Domain reduction

enum DomainReducer {
    // A pragmatic slice of multi-label public suffixes. Not the full PSL, but it
    // keeps the common cases ("bbc.co.uk", not "co.uk") honest.
    private static let multiPartSuffixes: Set<String> = [
        "co.uk", "org.uk", "ac.uk", "gov.uk", "co.jp", "ne.jp", "or.jp",
        "com.au", "net.au", "org.au", "co.nz", "com.br", "com.cn", "com.mx",
        "co.in", "co.kr", "com.tr", "com.sg", "com.hk", "co.za", "com.tw",
    ]

    /// "https://www.youtube.com/watch?v=x" -> "youtube.com"
    static func registrableDomain(from url: URL) -> String? {
        guard var host = url.host?.lowercased() else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        if host.isEmpty { return nil }

        let labels = host.split(separator: ".").map(String.init)
        guard labels.count > 2 else { return host }

        let lastTwo = labels.suffix(2).joined(separator: ".")
        if multiPartSuffixes.contains(lastTwo) {
            return labels.suffix(3).joined(separator: ".")
        }
        return lastTwo
    }
}
