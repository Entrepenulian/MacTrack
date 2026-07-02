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
    /// Per-minute samples for past days, loaded from the database on demand (for the
    /// chart) and cached so re-rendering a viewed day is cheap.
    private var pastSamples: [String: [String: [Int: Double]]] = [:]

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

    /// For each of the last `daysBack` days that has any tracked time, the category
    /// that dominated it — 0 Productive, 1 Unproductive, 2 Other — keyed by day.
    /// Powers the activity grid, which colors each day by its winner.
    func dailyWinners(daysBack: Int) -> [String: Int] {
        var result: [String: Int] = [:]
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        for i in 0..<max(0, daysBack) {
            guard let date = cal.date(byAdding: .day, value: -i, to: start) else { continue }
            let key = DayKey.key(for: date)
            guard days[key] != nil else { continue }     // no record → empty cell
            let s = productivitySplit(for: key)
            let vals = [s.productive, s.unproductive, s.other]
            if vals.reduce(0, +) <= 0 { continue }
            if let win = vals.indices.max(by: { vals[$0] < vals[$1] }) { result[key] = win }
        }
        return result
    }

    /// Your best days, ranked by the *least* time spent on unproductive apps and
    /// sites. Only days you actually used count — a day's total tracked time must
    /// clear `minTotal`, so an unused (near-empty) day can't sneak to the top with
    /// a hollow zero. Returns the unproductive seconds per day, ascending, capped at
    /// `limit`. Powers the leaderboard.
    func lowestUnproductiveDays(limit: Int = 3, minTotal: Double = 1800) -> [Double] {
        days.keys
            .compactMap { key -> Double? in
                let s = productivitySplit(for: key)
                let total = s.productive + s.unproductive + s.other
                return total >= minTotal ? s.unproductive : nil
            }
            .sorted()
            .prefix(limit)
            .map { $0 }
    }

    /// The apps/sites that make up one productivity bucket — `tag == nil` means
    /// Other (untagged) — sorted by time, with a within-bucket fraction for the row
    /// wash. Browsers are skipped (their time is represented by their sites).
    func productivityItems(tag: ProductivityTag?, for dayKey: String) -> [UsageEntry] {
        guard let day = days[dayKey] else { return [] }
        var items: [UsageEntry] = []
        for stat in day.apps.values
        where !excludedApps.contains(stat.bundleID)
            && !SystemApps.isBlocked(stat.bundleID)
            && !BrowserURLReader.isBrowser(stat.bundleID)
            && appTags[stat.bundleID] == tag {
            items.append(UsageEntry(
                id: "app:" + stat.bundleID, kind: .app(bundleID: stat.bundleID),
                title: stat.name, subtitle: nil, seconds: stat.seconds,
                category: ActivityCategory.classify(bundleID: stat.bundleID), fraction: 0))
        }
        for stat in day.sites.values
        where !excludedSites.contains(stat.domain) && siteTags[stat.domain] == tag {
            items.append(UsageEntry(
                id: "site:" + stat.domain, kind: .site(domain: stat.domain),
                title: SiteKey.display(stat.domain), subtitle: nil, seconds: stat.seconds,
                category: .web, fraction: 0))
        }
        let maxSeconds = items.map(\.seconds).max() ?? 1
        return items.sorted { $0.seconds > $1.seconds }.map { e in
            var x = e
            x.fraction = maxSeconds > 0 ? e.seconds / maxSeconds : 0
            return x
        }
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
        // Each X account (x.com/@handle) is its own row, shown as "@handle" with the
        // domain beneath. The site you're currently on always shows, even under the
        // minute floor.
        let sorted = day.sites.values
            .filter { !excludedSites.contains($0.domain) && ($0.seconds >= minSeconds || $0.domain == alwaysInclude) }
            .sorted { $0.seconds > $1.seconds }
        let maxSeconds = sorted.first?.seconds ?? 1
        return sorted.map { stat in
            UsageEntry(
                id: "site:" + stat.domain,
                kind: .site(domain: stat.domain),
                title: SiteKey.display(stat.domain),
                subtitle: SiteKey.isAccount(stat.domain) ? SiteKey.base(stat.domain) : stat.lastTitle,
                seconds: stat.seconds,
                category: .web,
                fraction: maxSeconds > 0 ? stat.seconds / maxSeconds : 0
            )
        }
    }

    /// The individual accounts behind a per-account base ("x.com") for a day — each
    /// with its handle, time, and (via siteTag) tag. Powers the account manager.
    func siteAccounts(base: String, for dayKey: String) -> [(key: String, handle: String, seconds: Double)] {
        guard let day = days[dayKey] else { return [] }
        return day.sites.values
            .filter { SiteKey.isAccount($0.domain) && SiteKey.base($0.domain) == base && !excludedSites.contains($0.domain) }
            .map { (key: $0.domain, handle: SiteKey.display($0.domain), seconds: $0.seconds) }
            .sorted { $0.seconds > $1.seconds }
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
    func chartLines(entries: [UsageEntry], for dayKey: String, colors: [String: Color] = [:], startMinute: Int, endMinute: Int) -> [ChartLineData] {
        let daySamples = samples(for: dayKey)
        // Today's line stops at the current minute; a finished past day runs to the
        // end of the window.
        let cap = dayKey == samplesDay ? min(DayKey.minuteOfDay, endMinute) : endMinute
        return entries.prefix(10).enumerated().map { index, entry in
            let samples = daySamples[entry.id] ?? [:]
            let minutes = samples.keys.sorted()
            var cumulative = 0.0
            var points: [CGPoint] = []
            var i = 0
            // Roll up everything that happened before the visible window starts.
            while i < minutes.count, minutes[i] < startMinute { cumulative += samples[minutes[i]] ?? 0; i += 1 }
            points.append(CGPoint(x: Double(startMinute), y: cumulative / 60.0))
            while i < minutes.count, minutes[i] <= cap {
                cumulative += samples[minutes[i]] ?? 0
                points.append(CGPoint(x: Double(minutes[i]), y: cumulative / 60.0))
                i += 1
            }
            // Extend the line flat to the cap so it always reaches the window's edge.
            let lastX = points.last.map { Double($0.x) } ?? Double(startMinute)
            if lastX < Double(cap) {
                points.append(CGPoint(x: Double(cap), y: cumulative / 60.0))
            }
            // Each line takes the app/site's own brand color (from its icon/favicon),
            // matching the detail bar chart; falls back to the palette until resolved.
            return ChartLineData(id: entry.id, label: entry.title,
                                 color: colors[entry.id] ?? Theme.chartColor(index),
                                 points: points, totalMinutes: cumulative / 60.0)
        }
    }

    /// Per-minute samples for a day: today's live cache, or a past day's loaded
    /// lazily from the database and kept for reuse.
    private func samples(for dayKey: String) -> [String: [Int: Double]] {
        if dayKey == samplesDay { return todaySamples }
        if let cached = pastSamples[dayKey] { return cached }
        let loaded = db?.loadSamples(day: dayKey) ?? [:]
        pastSamples[dayKey] = loaded
        return loaded
    }

    /// The day's real active window — the first and last minute-of-day with any
    /// tracked activity. Because time is only ever credited while you're present
    /// (idle, locked, and asleep time are dropped), the first minute is when you
    /// woke the Mac and started moving, and the last is when you got off. Powers a
    /// chart that spans your actual usage instead of a fixed schedule. Nil if the
    /// day has no activity yet.
    func activeWindowMinutes(for dayKey: String) -> (start: Int, end: Int)? {
        var lo = Int.max, hi = Int.min
        for (_, minutes) in samples(for: dayKey) {
            for (m, secs) in minutes where secs > 0 {
                if m < lo { lo = m }
                if m > hi { hi = m }
            }
        }
        return lo <= hi ? (lo, hi) : nil
    }

    /// Minutes spent on one entry during each hour of `[startHour, endHour)` — the
    /// per-app detail bar chart. Each value is 0…60 (an hour holds at most 60 min).
    func hourlyMinutes(entryID: String, for dayKey: String, startHour: Int, endHour: Int) -> [(hour: Int, minutes: Double)] {
        let s = mergedSamples(entryID: entryID, for: dayKey)
        return stride(from: startHour, to: max(startHour + 1, endHour), by: 1).map { h in
            var sec = 0.0
            for m in (h * 60)..<(h * 60 + 60) { sec += s[m] ?? 0 }
            return (h, min(60, sec / 60))
        }
    }

    /// Per-minute samples for an entry. An aggregate base ("site:x.com") sums all of
    /// its accounts; everything else is the single key.
    private func mergedSamples(entryID: String, for dayKey: String) -> [Int: Double] {
        let all = samples(for: dayKey)
        if entryID.hasPrefix("site:") {
            let key = String(entryID.dropFirst(5))
            if SiteKey.splits(key) && !SiteKey.isAccount(key) {
                var out: [Int: Double] = [:]
                let base = "site:" + key
                for (k, v) in all where k == base || k.hasPrefix(base + "/@") {
                    for (m, sec) in v { out[m, default: 0] += sec }
                }
                return out
            }
        }
        return all[entryID] ?? [:]
    }

    /// Total seconds an entry ("app:bundleID" / "site:domain") accrued on one day.
    /// An aggregate base ("site:x.com") sums all of its accounts.
    func entrySeconds(entryID: String, for dayKey: String) -> Double {
        guard let day = days[dayKey] else { return 0 }
        let parts = entryID.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return 0 }
        switch parts[0] {
        case "app": return day.apps[parts[1]]?.seconds ?? 0
        case "site":
            let key = parts[1]
            if SiteKey.splits(key) && !SiteKey.isAccount(key) {
                return day.sites.values
                    .filter { $0.domain == key || $0.domain.hasPrefix(key + "/@") }
                    .reduce(0) { $0 + $1.seconds }
            }
            return day.sites[key]?.seconds ?? 0
        default: return 0
        }
    }

    /// One entry's total for each of the seven days in `dayKey`'s calendar week
    /// (Sun…Sat) — the per-app "Week" bar chart.
    func weeklyTotals(entryID: String, week dayKey: String) -> [(key: String, date: Date, seconds: Double)] {
        let cal = Calendar.current
        let base = DayKey.date(from: dayKey) ?? Date()
        let start = cal.dateInterval(of: .weekOfYear, for: base)?.start ?? cal.startOfDay(for: base)
        return (0..<7).map { i in
            let d = cal.date(byAdding: .day, value: i, to: start) ?? start
            let k = DayKey.key(for: d)
            return (k, d, entrySeconds(entryID: entryID, for: k))
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
