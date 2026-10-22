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
    private let blocks: BlockController
    private let focusGuard: FocusGuard
    private let idle = IdleDetector()
    private let browserReader = BrowserURLReader()

    private var timer: Timer?
    private var lastTick = Date()
    private let interval: TimeInterval = 1.0

    /// Per-browser last-known tab, refreshed asynchronously so a tick never
    /// blocks on Apple Events.
    private var lastTab: [String: BrowserURLReader.TabInfo] = [:]
    private var pendingFetch: Set<String> = []
    /// Last-known active X account handle (read from the page DOM), and an in-flight
    /// guard so a tick never fires more than one account read at a time.
    private var lastXAccount: String?
    private var pendingAccountFetch = false
    /// Last "kind:value" focus the active project was inferred from, so the
    /// remembered-project switch runs once per focus change, not every tick.
    private var lastProjectFocus: String?
    /// Seconds the front tab has shown a *blocked* X account. After `accountBlockGrace`
    /// we try to auto-switch to an allowed account; if still stuck `accountSwitchWait`
    /// seconds later (no allowed account, or the switch didn't take), we bounce.
    private var blockedXAccountSeconds = 0
    private let accountBlockGrace = 2
    private let accountSwitchWait = 9

    /// Auto-resume: after pausing, the first real mouse movement resumes tracking
    /// so a pause can never be forgotten. A short grace ignores the click that
    /// started the pause; after that, any movement counts.
    private var pausedAt: Date?
    private var pausedMouseLoc: NSPoint = .zero
    private var mouseMonitor: Any?
    private let autoResumeGrace: TimeInterval = 1.0

    /// "Good night" mode: tracking is off until a chosen morning hour. Survives
    /// relaunch (persisted) and resumes on its own at the wake time.
    @Published private(set) var isSleeping = false
    private var sleepUntilDate: Date?
    private let sleepKey = "mactrack.sleepUntil"

    var automationDenied: Bool { browserReader.automationDenied }

    init(store: UsageStore, blocks: BlockController, focusGuard: FocusGuard) {
        self.store = store
        self.blocks = blocks
        self.focusGuard = focusGuard
        if let ts = UserDefaults.standard.object(forKey: sleepKey) as? Double {
            let until = Date(timeIntervalSince1970: ts)
            if until > Date() { sleepUntilDate = until; isSleeping = true }
            else { UserDefaults.standard.removeObject(forKey: sleepKey) }
        }
    }

    deinit { if let m = mouseMonitor { NSEvent.removeMonitor(m) } }

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
        guard paused != isPaused else { return }
        isPaused = paused
        lastTick = Date()      // don't backfill the paused gap
        if paused {
            pausedAt = Date()
            pausedMouseLoc = NSEvent.mouseLocation
            startMouseMonitor()
        } else {
            pausedAt = nil
            stopMouseMonitor()
        }
    }

    /// Pause tracking *and* put the display to sleep. The mouse monitor stays armed,
    /// so the first move both wakes the screen and auto-resumes tracking. Used by the
    /// header's Pause button.
    func pauseAndSleepDisplay() {
        setPaused(true)
        let sleep = Process()
        sleep.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        sleep.arguments = ["displaysleepnow"]
        try? sleep.run()
    }

    // MARK: - Auto-resume on return

    /// Instant path: a real mouse/scroll event anywhere resumes immediately. The
    /// tick's position check is the reliable fallback if this monitor doesn't fire.
    private func startMouseMonitor() {
        stopMouseMonitor()
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged,
                       .scrollWheel, .leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.autoResume() }
        }
    }

    private func stopMouseMonitor() {
        if let m = mouseMonitor { NSEvent.removeMonitor(m); mouseMonitor = nil }
    }

    /// Resume once we're past the grace window (so the pause click itself, and any
    /// settle right after, don't immediately unpause).
    private func autoResume() {
        guard isPaused, let pausedAt, Date().timeIntervalSince(pausedAt) >= autoResumeGrace else { return }
        let loc = NSEvent.mouseLocation
        guard hypot(loc.x - pausedMouseLoc.x, loc.y - pausedMouseLoc.y) > 6 else { return }
        setPaused(false)
    }

    // MARK: - Sleep ("good night") mode

    /// Toggle: tap once to stop tracking for the night; tap again to wake now.
    func sleepForNight(wakeHour: Int) {
        if isSleeping { wake(); return }
        let until = Self.nextOccurrence(hour: wakeHour)
        sleepUntilDate = until
        UserDefaults.standard.set(until.timeIntervalSince1970, forKey: sleepKey)
        isSleeping = true
        lastTick = Date()
    }

    func wake() {
        sleepUntilDate = nil
        UserDefaults.standard.removeObject(forKey: sleepKey)
        isSleeping = false
        lastTick = Date()
    }

    private static func nextOccurrence(hour: Int) -> Date {
        let cal = Calendar.current
        let now = Date()
        var comps = cal.dateComponents([.year, .month, .day], from: now)
        comps.hour = hour; comps.minute = 0; comps.second = 0
        var date = cal.date(from: comps) ?? now
        if date <= now { date = cal.date(byAdding: .day, value: 1, to: date) ?? date }
        return date
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

        // Blocking runs regardless of pause/idle — a block is a block.
        blocks.tick()
        enforceBlocks()

        if isSleeping {
            if let until = sleepUntilDate, now < until {
                refreshLiveLabelsOnly()
                return
            }
            wake()   // reached the wake hour — resume tracking
        }

        if isPaused {
            // Reliable fallback (no event monitor needed): if the cursor has moved
            // from where it was when paused, resume — once past the grace window.
            if let pausedAt, now.timeIntervalSince(pausedAt) >= autoResumeGrace {
                let loc = NSEvent.mouseLocation
                if hypot(loc.x - pausedMouseLoc.x, loc.y - pausedMouseLoc.y) > 6 {
                    setPaused(false)
                    return
                }
            }
            refreshLiveLabelsOnly()
            return
        }

        // Drop unreasonable gaps (sleep/wake, debugger pauses) and idle time.
        guard present, delta > 0, delta < interval * 4 else {
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
               // A search-results page is pass-through, not a destination — credit no
               // site (its time falls into the browser's uncredited total, like a new
               // tab), so it never lands in the productivity split.
               !DomainReducer.isSearchResults(tab.url),
               !store.isSiteExcluded(domain) {
                // X/Twitter time is split by the active account when we can read it;
                // otherwise it's the bare domain like any other site.
                if SiteKey.splits(domain) {
                    let credited = lastXAccount.map { SiteKey.account(base: domain, handle: $0) } ?? domain
                    currentDomain = credited
                    store.addSiteTime(delta, domain: credited, title: tab.title)
                    refreshXAccount(bundleID: bundleID)
                } else {
                    currentDomain = domain
                    store.addSiteTime(delta, domain: domain, title: tab.title)
                    lastXAccount = nil
                }
            } else {
                currentDomain = nil
                lastXAccount = nil
            }
            refreshBrowserTab(bundleID: bundleID)
        } else {
            currentDomain = nil
            lastXAccount = nil
        }

        // Attribute this tick to the active project, and switch projects when the
        // focused item has a remembered association. Browser chrome with no credited
        // site is deliberately not attributed to a project.
        let projectFocus: (kind: String, value: String)? =
            currentDomain.map { (kind: "site", value: $0) }
            ?? (BrowserURLReader.isBrowser(bundleID) ? nil : (kind: "app", value: bundleID))
        if let focus = projectFocus {
            let key = focus.kind + ":" + focus.value
            if key != lastProjectFocus {
                lastProjectFocus = key
                // Runs before the credit below, so the first tick on a newly focused
                // app lands in that app's remembered project.
                store.projectFocusChanged(kind: focus.kind, value: focus.value)
            }
            store.creditProject(delta, kind: focus.kind, value: focus.value)
        } else {
            lastProjectFocus = nil
        }

        // Feed the focus guard the tag of whatever's in focus (the site if we're
        // on one, otherwise the app) and the time just credited. It owns the
        // "too long on unproductive stuff → blur + quote" decision.
        let tag = currentDomain.flatMap { store.siteTag($0) } ?? store.appTag(bundleID)
        focusGuard.evaluate(tag: tag, delta: delta)
    }

    /// Keep the "now tracking" line truthful even while idle/paused.
    /// Hide a blocked app or bounce a blocked website's tab. Runs every tick.
    private func enforceBlocks() {
        guard let front = NSWorkspace.shared.frontmostApplication,
              let bundleID = front.bundleIdentifier else { return }
        if blocks.isAppBlocked(bundleID) {
            front.hide()
            return
        }
        if BrowserURLReader.isBrowser(bundleID) {
            if let tab = lastTab[bundleID],
               let domain = DomainReducer.registrableDomain(from: tab.url) {
                if blocks.isSiteBlocked(domain) {
                    browserReader.blockActiveTab(bundleID: bundleID)   // whole site blocked
                    blockedXAccountSeconds = 0
                } else if SiteKey.splits(domain), let handle = lastXAccount,
                          blocks.isSiteBlocked(SiteKey.account(base: domain, handle: handle)) {
                    // Only this X account is blocked. First try to route you to an
                    // allowed account (drive X's account switcher); if that isn't
                    // possible or doesn't take, bounce the tab as a last resort.
                    blockedXAccountSeconds += 1
                    if blockedXAccountSeconds == accountBlockGrace,
                       let target = unblockedXTarget(base: domain, current: handle) {
                        browserReader.switchXAccount(bundleID: bundleID, toHandle: target)
                    }
                    if blockedXAccountSeconds > accountBlockGrace + accountSwitchWait {
                        browserReader.blockActiveTab(bundleID: bundleID)
                    }
                } else {
                    blockedXAccountSeconds = 0
                }
                // Keep the active account current so the per-account check is fresh
                // even while idle.
                if SiteKey.splits(domain) { refreshXAccount(bundleID: bundleID) }
            } else {
                blockedXAccountSeconds = 0
            }
            refreshBrowserTab(bundleID: bundleID)   // keep the tab fresh to catch navigation
        } else {
            blockedXAccountSeconds = 0
        }
    }

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

    /// Reads the active X account (off the main thread) and caches it for the next
    /// ticks, so per-account crediting needs no per-tick Apple Event round trip.
    private func refreshXAccount(bundleID: String) {
        guard !pendingAccountFetch else { return }
        pendingAccountFetch = true
        browserReader.fetchAccount(bundleID: bundleID) { [weak self] handle in
            guard let self else { return }
            self.pendingAccountFetch = false
            self.lastXAccount = handle
        }
    }

    /// A known X account for `base` that isn't the current one and isn't blocked —
    /// the account to route you to. Nil when there's none (then we bounce instead).
    private func unblockedXTarget(base: String, current: String) -> String? {
        store.knownAccountHandles(base: base).first { h in
            h != current && !blocks.isSiteBlocked(SiteKey.account(base: base, handle: h))
        }
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
