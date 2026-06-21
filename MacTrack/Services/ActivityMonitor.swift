import AppKit
import Combine

/// The sampling engine. Once a second it measures the real elapsed time since
/// the previous tick and credits it to whatever is genuinely in focus right now:
/// the frontmost app, and — if that app is a browser — the active tab's domain.
///
/// Using measured deltas (not a fixed increment) keeps totals accurate even when
/// the timer is coalesced, and a clamp drops the gap across sleep/wake so we
/// never dump an hour of "away" time onto whatever you opened next.
@MainActor
final class ActivityMonitor: ObservableObject {

    // Live state for the header's "now tracking" line.
    @Published private(set) var currentAppName: String?
    @Published private(set) var currentBundleID: String?
    @Published private(set) var currentDomain: String?
    @Published private(set) var isPaused = false      // user toggle
    @Published private(set) var isPresent = true       // idle/lock state

    private let store: UsageStore
    private let idle = IdleDetector()
    private let browserReader = BrowserURLReader()

    private var timer: Timer?
    private var lastTick = Date()
    private let interval: TimeInterval = 1.0

    /// Per-browser last-known tab, refreshed asynchronously so a tick never
    /// blocks on Apple Events.
    private var lastTab: [String: BrowserURLReader.TabInfo] = [:]
    private var pendingFetch: Set<String> = []

    var automationDenied: Bool { browserReader.automationDenied }

    init(store: UsageStore) {
        self.store = store
    }

    func start() {
        guard timer == nil else { return }
        lastTick = Date()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func setPaused(_ paused: Bool) {
        isPaused = paused
        lastTick = Date()  // don't backfill the paused gap
    }

    func setIdleThreshold(_ seconds: TimeInterval) {
        idle.idleThreshold = seconds
    }

    // MARK: - The tick

    private func tick() {
        let now = Date()
        let delta = now.timeIntervalSince(lastTick)
        lastTick = now

        let present = idle.isPresent
        isPresent = present

        // Drop unreasonable gaps (sleep/wake, debugger pauses) and idle/paused time.
        guard !isPaused, present, delta > 0, delta < interval * 4 else {
            refreshLiveLabelsOnly()
            return
        }

        guard let front = NSWorkspace.shared.frontmostApplication,
              let bundleID = front.bundleIdentifier else { return }

        // Only count real, Dock-visible apps the user is actually using — skip
        // system/background UI (loginwindow, Notification Center, Spotlight, …)
        // and anything the user has marked "Don't track".
        guard front.activationPolicy == .regular,
              !SystemApps.isBlocked(bundleID),
              !store.isAppExcluded(bundleID) else { return }

        let appName = front.localizedName ?? bundleID
        currentAppName = appName
        currentBundleID = bundleID

        store.addAppTime(delta, bundleID: bundleID, name: appName)

        if BrowserURLReader.isBrowser(bundleID) {
            if let tab = lastTab[bundleID],
               let domain = DomainReducer.registrableDomain(from: tab.url),
               !store.isSiteExcluded(domain) {
                currentDomain = domain
                store.addSiteTime(delta, domain: domain, title: tab.title)
            } else {
                currentDomain = nil
            }
            refreshBrowserTab(bundleID: bundleID)
        } else {
            currentDomain = nil
        }
    }

    /// Keep the "now tracking" line truthful even while idle/paused.
    private func refreshLiveLabelsOnly() {
        guard let front = NSWorkspace.shared.frontmostApplication,
              let bundleID = front.bundleIdentifier,
              front.activationPolicy == .regular,
              !SystemApps.isBlocked(bundleID),
              !store.isAppExcluded(bundleID) else { return }
        currentAppName = front.localizedName ?? bundleID
        currentBundleID = bundleID
        if BrowserURLReader.isBrowser(bundleID) { refreshBrowserTab(bundleID: bundleID) }
    }

    private func refreshBrowserTab(bundleID: String) {
        guard !pendingFetch.contains(bundleID) else { return }
        pendingFetch.insert(bundleID)
        browserReader.fetch(bundleID: bundleID) { [weak self] result in
            guard let self else { return }
            self.pendingFetch.remove(bundleID)
            switch result {
            case .tab(let info):
                self.lastTab[bundleID] = info
            case .noURL:
                // Empty/new tab or Start Page — stop crediting the previous site.
                self.lastTab[bundleID] = nil
                self.currentDomain = nil
            case .failed:
                break // permission/transient — keep the last known tab
            }
            self.objectWillChange.send()
        }
    }
}
