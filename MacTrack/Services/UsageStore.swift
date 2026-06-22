import SwiftUI
import Combine

/// The single source of truth for tracked time. Keeps an in-memory cache of all
/// days for fast UI reads, while every change is written through to a durable
/// SQLite database (see `DatabaseStore`). MainActor-bound: all mutation happens
/// on the main thread, fed by the sampler's timer.
@MainActor
final class UsageStore: ObservableObject {

    @Published private(set) var days: [String: DayRecord] = [:]

    /// User-chosen exclusions ("Don't track"). Stored in the database.
    @Published private(set) var excludedApps: Set<String> = []
    @Published private(set) var excludedSites: Set<String> = []

    /// Productivity tags. Untagged apps/sites count as "Other". Stored in the database.
    @Published private(set) var appTags: [String: ProductivityTag] = [:]
    @Published private(set) var siteTags: [String: ProductivityTag] = [:]

    /// Today's per-minute samples, keyed "kind:key" → (minute → seconds). Drives
    /// the line chart. Persisted via the database; cached here for fast reads.
    private(set) var todaySamples: [String: [Int: Double]] = [:]
    /// The calendar day `todaySamples` belongs to — reset when the day rolls over.
    private var samplesDay: String = DayKey.today

    /// Bumped on every attribution so dependent views recompute live.
    @Published private(set) var revision: Int = 0

    private let db: DatabaseStore?

    init(database: DatabaseStore? = nil) {
        self.db = database ?? (try? DatabaseStore())

        if let database = db {
            database.makeDailyBackup()
            importLegacyJSONIfNeeded(into: database)
            days = database.loadDays()
            let ex = database.loadExclusions()
            excludedApps = ex.apps
            excludedSites = ex.sites
            todaySamples = database.loadSamples(day: DayKey.today)
            for t in database.loadTags() {
                guard let cat = ProductivityTag(rawValue: t.category) else { continue }
                if t.kind == "app" { appTags[t.value] = cat }
                else if t.kind == "site" { siteTags[t.value] = cat }
            }
        }
    }

    // MARK: Today

    var today: DayRecord {
        days[DayKey.today] ?? DayRecord(dayKey: DayKey.today)
    }

    /// Today's accumulated seconds for whatever is currently in focus: the website
    /// if on one, otherwise the app. Falls back to the day total when nothing is
    /// focused. Shared by the popover header and the menu-bar label so they match.
    func focusSeconds(domain: String?, bundleID: String?) -> Double {
        if let domain { return today.sites[domain]?.seconds ?? 0 }
        if let bundleID { return today.apps[bundleID]?.seconds ?? 0 }
        return today.totalAppSeconds
    }

    // MARK: Attribution (called by the sampler)

    func addAppTime(_ seconds: Double, bundleID: String, name: String) {
        guard seconds > 0 else { return }
        let key = DayKey.today
        let now = Date()
        var day = days[key] ?? DayRecord(dayKey: key)
        var stat = day.apps[bundleID] ?? AppStat(bundleID: bundleID, name: name, seconds: 0, lastActive: nil)
        stat.seconds += seconds
        stat.name = name
        stat.lastActive = now
        day.apps[bundleID] = stat
        days[key] = day
        db?.addApp(day: key, bundleID: bundleID, name: name, addSeconds: seconds, lastActive: now)
        recordSample(kind: "app", key: bundleID, seconds: seconds)
        revision &+= 1
    }

    func addSiteTime(_ seconds: Double, domain: String, title: String?) {
        guard seconds > 0 else { return }
        let key = DayKey.today
        let now = Date()
        var day = days[key] ?? DayRecord(dayKey: key)
        var stat = day.sites[domain] ?? SiteStat(domain: domain, seconds: 0, lastActive: nil, lastTitle: nil)
        stat.seconds += seconds
        stat.lastActive = now
        if let title { stat.lastTitle = title }   // in-memory only, for the live list preview
        day.sites[domain] = stat
        days[key] = day
        // The title is deliberately NOT passed to the database — never persisted.
        db?.addSite(day: key, domain: domain, addSeconds: seconds, lastActive: now)
        recordSample(kind: "site", key: domain, seconds: seconds)
        revision &+= 1
    }

    private func recordSample(kind: String, key: String, seconds: Double) {
        let today = DayKey.today
        if today != samplesDay {          // crossed midnight while running — start a fresh chart day
            todaySamples = [:]
            samplesDay = today
        }
        let minute = DayKey.minuteOfDay
        let id = kind + ":" + key
        todaySamples[id, default: [:]][minute, default: 0] += seconds
        db?.addSample(day: today, kind: kind, key: key, minute: minute, addSeconds: seconds)
    }

    // MARK: Exclusions ("Don't track")

    func isAppExcluded(_ bundleID: String) -> Bool { excludedApps.contains(bundleID) }
    func isSiteExcluded(_ domain: String) -> Bool { excludedSites.contains(domain) }

    func excludeApp(_ bundleID: String) {
        excludedApps.insert(bundleID)
        for key in days.keys { days[key]?.apps.removeValue(forKey: bundleID) }
        db?.deleteApp(bundleID: bundleID)
        db?.setExclusion(kind: "app", value: bundleID)
        revision &+= 1
    }

    func excludeSite(_ domain: String) {
        excludedSites.insert(domain)
        for key in days.keys { days[key]?.sites.removeValue(forKey: domain) }
        db?.deleteSite(domain: domain)
        db?.setExclusion(kind: "site", value: domain)
        revision &+= 1
    }

    // MARK: Productivity tags

    func appTag(_ bundleID: String) -> ProductivityTag? { appTags[bundleID] }
    func siteTag(_ domain: String) -> ProductivityTag? { siteTags[domain] }
    var hasAnyTags: Bool { !appTags.isEmpty || !siteTags.isEmpty }

    func setAppTag(_ bundleID: String, _ tag: ProductivityTag?) {
        if let tag {
            appTags[bundleID] = tag
            db?.setTag(kind: "app", value: bundleID, category: tag.rawValue)
        } else {
            appTags.removeValue(forKey: bundleID)
            db?.clearTag(kind: "app", value: bundleID)
        }
        revision &+= 1
    }

    func setSiteTag(_ domain: String, _ tag: ProductivityTag?) {
        if let tag {
            siteTags[domain] = tag
            db?.setTag(kind: "site", value: domain, category: tag.rawValue)
        } else {
            siteTags.removeValue(forKey: domain)
            db?.clearTag(kind: "site", value: domain)
        }
        revision &+= 1
    }

    /// Today's focused time split into Productive / Unproductive / Other. Browser
    /// apps are skipped (their per-site time is counted instead, so nothing is
    /// double-counted); untagged time falls into Other.
    func productivitySplit(for dayKey: String) -> (productive: Double, unproductive: Double, other: Double) {
        guard let day = days[dayKey] else { return (0, 0, 0) }
        var p = 0.0, u = 0.0, o = 0.0
        var browserSeconds = 0.0
        for stat in day.apps.values
        where !excludedApps.contains(stat.bundleID) && !SystemApps.isBlocked(stat.bundleID) {
            if BrowserURLReader.isBrowser(stat.bundleID) {
                browserSeconds += stat.seconds   // represented by its sites below
                continue
            }
            switch appTags[stat.bundleID] {
            case .productive: p += stat.seconds
            case .unproductive: u += stat.seconds
            case .none: o += stat.seconds
            }
        }
        var siteSeconds = 0.0
        for stat in day.sites.values where !excludedSites.contains(stat.domain) {
            siteSeconds += stat.seconds
            switch siteTags[stat.domain] {
            case .productive: p += stat.seconds
            case .unproductive: u += stat.seconds
            case .none: o += stat.seconds
            }
        }
        // Browser time on tabs with no resolvable domain (a new/empty tab, an
        // internal page, or any browsing before Automation permission is granted)
        // is never attributed to a site — count that residual as Other so the
        // donut total reflects all focused time.
        o += max(0, browserSeconds - siteSeconds)
        return (p, u, o)
    }

    // MARK: Derived rows

    func appEntries(for dayKey: String) -> [UsageEntry] {
        guard let day = days[dayKey] else { return [] }
        let sorted = day.apps.values
            .filter { !excludedApps.contains($0.bundleID) && !SystemApps.isBlocked($0.bundleID) }
            .sorted { $0.seconds > $1.seconds }
        let maxSeconds = sorted.first?.seconds ?? 1
        return sorted.map { stat in
            UsageEntry(
                id: "app:" + stat.bundleID,
                kind: .app(bundleID: stat.bundleID),
                title: stat.name,
                subtitle: nil,
                seconds: stat.seconds,
                category: ActivityCategory.classify(bundleID: stat.bundleID),
                fraction: maxSeconds > 0 ? stat.seconds / maxSeconds : 0
            )
        }
    }

    func siteEntries(for dayKey: String, minSeconds: Double = 0, alwaysInclude: String? = nil) -> [UsageEntry] {
        guard let day = days[dayKey] else { return [] }
        // The site you're currently on always shows, even under the minute floor,
        // so the list immediately reflects what you're looking at.
        let sorted = day.sites.values
            .filter { !excludedSites.contains($0.domain) && ($0.seconds >= minSeconds || $0.domain == alwaysInclude) }
            .sorted { $0.seconds > $1.seconds }
        let maxSeconds = sorted.first?.seconds ?? 1
        return sorted.map { stat in
            UsageEntry(
                id: "site:" + stat.domain,
                kind: .site(domain: stat.domain),
                title: stat.domain,
                subtitle: stat.lastTitle,   // shown live, but never saved to disk
                seconds: stat.seconds,
                category: .web,
                fraction: maxSeconds > 0 ? stat.seconds / maxSeconds : 0
            )
        }
    }

    /// Non-browser apps and websites merged into one ranking, sorted by time.
    /// Browser apps (Safari, Chrome, …) are omitted on purpose: their total is
    /// just the sum of their tabs, so the individual sites represent that time —
    /// showing "Safari" as a lump would double-represent it and bury the sites.
    func allEntries(for dayKey: String, currentDomain: String? = nil) -> [UsageEntry] {
        let nonBrowserApps = appEntries(for: dayKey).filter { entry in
            if case .app(let bundleID) = entry.kind { return !BrowserURLReader.isBrowser(bundleID) }
            return true
        }
        // Same 1-minute floor for sites as the Websites tab (plus the active site),
        // so a short site can't appear in All while being hidden from Websites.
        var combined = (nonBrowserApps + siteEntries(for: dayKey, minSeconds: 60, alwaysInclude: currentDomain))
            .sorted { $0.seconds > $1.seconds }
        let maxSeconds = combined.first?.seconds ?? 1
        for i in combined.indices {
            combined[i].fraction = maxSeconds > 0 ? combined[i].seconds / maxSeconds : 0
        }
        return combined
    }

    /// Builds cumulative-minutes line series for the given (already ranked) top
    /// entries, within the visible [startMinute, endMinute] window. Each line ends
    /// at its full total, so the chart's endpoints match the list's times.
    func chartLines(entries: [UsageEntry], startMinute: Int, endMinute: Int) -> [ChartLineData] {
        let nowMinute = min(DayKey.minuteOfDay, endMinute)
        return entries.prefix(10).enumerated().map { index, entry in
            let samples = todaySamples[entry.id] ?? [:]
            let minutes = samples.keys.sorted()
            var cumulative = 0.0
            var points: [CGPoint] = []
            var i = 0
            // Roll up everything that happened before the visible window starts.
            while i < minutes.count, minutes[i] < startMinute { cumulative += samples[minutes[i]] ?? 0; i += 1 }
            points.append(CGPoint(x: Double(startMinute), y: cumulative / 60.0))
            while i < minutes.count, minutes[i] <= nowMinute {
                cumulative += samples[minutes[i]] ?? 0
                points.append(CGPoint(x: Double(minutes[i]), y: cumulative / 60.0))
                i += 1
            }
            // Extend the line flat to "now" so it always reaches the current time.
            let lastX = points.last.map { Double($0.x) } ?? Double(startMinute)
            if lastX < Double(nowMinute) {
                points.append(CGPoint(x: Double(nowMinute), y: cumulative / 60.0))
            }
            return ChartLineData(id: entry.id, label: entry.title, color: Theme.chartColor(index),
                                 points: points, totalMinutes: cumulative / 60.0)
        }
    }

    /// Category breakdown (today) — kept for future use.
    func ribbonSegments(for dayKey: String) -> [(category: ActivityCategory, seconds: Double)] {
        guard let day = days[dayKey] else { return [] }
        var totals: [ActivityCategory: Double] = [:]
        for stat in day.apps.values where !excludedApps.contains(stat.bundleID) && !SystemApps.isBlocked(stat.bundleID) {
            totals[ActivityCategory.classify(bundleID: stat.bundleID), default: 0] += stat.seconds
        }
        return ActivityCategory.allCases.compactMap { cat in
            guard let s = totals[cat], s > 0 else { return nil }
            return (cat, s)
        }
        .sorted { $0.seconds > $1.seconds }
    }

    /// Last `count` days, oldest first, as (date, totalAppSeconds) for trends.
    func recentDailyTotals(count: Int) -> [(date: Date, seconds: Double)] {
        let cal = Calendar.current
        return (0..<count).reversed().compactMap { offset in
            guard let date = cal.date(byAdding: .day, value: -offset, to: Date()) else { return nil }
            let key = DayKey.key(for: date)
            return (date, days[key]?.totalAppSeconds ?? 0)
        }
    }

    // MARK: Lifecycle

    /// Called on quit — flush the WAL into the main database file.
    func saveNow() { db?.checkpoint() }

    // MARK: Legacy JSON migration

    /// One-time import of the old `usage.json` (if present) into the database, so
    /// upgrading from the JSON era never loses history. The file is renamed, not
    /// deleted, afterward.
    private func importLegacyJSONIfNeeded(into database: DatabaseStore) {
        guard database.isEmpty else { return }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacTrack", isDirectory: true)
        let jsonURL = base.appendingPathComponent("usage.json")
        guard let data = try? Data(contentsOf: jsonURL),
              let decoded = try? JSONDecoder().decode([String: DayRecord].self, from: data) else { return }
        for record in decoded.values { database.importDay(record) }
        try? FileManager.default.moveItem(at: jsonURL, to: base.appendingPathComponent("usage.json.imported"))
        NSLog("MacTrack imported \(decoded.count) days from legacy usage.json")
    }
}
