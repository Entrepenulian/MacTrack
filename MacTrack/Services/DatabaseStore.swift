import Foundation
import SQLite3

/// SQLITE_TRANSIENT tells SQLite to copy bound text/blob immediately, which is
/// required when binding Swift strings (their storage may be freed after the call).
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Durable local storage backed by SQLite (WAL mode), using the system library —
/// no external dependencies.
///
/// Why a database and not a JSON file:
///  - Incremental, transactional writes — a tick updates one row, never rewrites
///    the whole dataset, so a crash mid-write can't corrupt everything.
///  - WAL journaling = crash-safe durability.
///  - Schema **migrations** (via `PRAGMA user_version`): future app changes evolve
///    the schema in place, so updating MacTrack never wipes your history.
///
/// Plus a daily `VACUUM INTO` backup (last 14 kept) and auto-restore if the live
/// database is unreadable. The file lives in Application Support, is user-private,
/// and is never synced anywhere. Accessed only from the main actor (single
/// connection, single thread), so no cross-thread locking is needed.
final class DatabaseStore {

    enum DBError: Error { case open(String), prepare(String), step(String) }

    private var db: OpaquePointer?
    let dbURL: URL
    private let backupsDir: URL

    init() throws {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacTrack", isDirectory: true)
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        dbURL = base.appendingPathComponent("MacTrack.sqlite")
        backupsDir = base.appendingPathComponent("Backups", isDirectory: true)
        try? fm.createDirectory(at: backupsDir, withIntermediateDirectories: true)

        do {
            try openDatabase()
        } catch {
            // Live DB unreadable — restore the most recent backup, then reopen.
            if restoreFromLatestBackup() { try openDatabase() } else { throw error }
        }
        try configure()
        try migrate()
        pruneOldSamples()
    }

    deinit { if db != nil { sqlite3_close(db) } }

    private func openDatabase() throws {
        if db != nil { sqlite3_close(db); db = nil }
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
        guard sqlite3_open_v2(dbURL.path, &db, flags, nil) == SQLITE_OK else {
            throw DBError.open(lastError)
        }
    }

    private func configure() throws {
        try exec("PRAGMA journal_mode=WAL;")
        try exec("PRAGMA synchronous=NORMAL;")
        try exec("PRAGMA foreign_keys=ON;")
        try exec("PRAGMA busy_timeout=3000;")
    }

    private var lastError: String { String(cString: sqlite3_errmsg(db)) }

    // MARK: Migrations (PRAGMA user_version)

    private func migrate() throws {
        var version = userVersion()
        if version < 1 {
            try exec("""
                CREATE TABLE IF NOT EXISTS appUsage(
                    day TEXT NOT NULL, bundleID TEXT NOT NULL, name TEXT,
                    seconds REAL NOT NULL DEFAULT 0, lastActive REAL,
                    PRIMARY KEY(day, bundleID));
                CREATE TABLE IF NOT EXISTS siteUsage(
                    day TEXT NOT NULL, domain TEXT NOT NULL,
                    seconds REAL NOT NULL DEFAULT 0, lastActive REAL, lastTitle TEXT,
                    PRIMARY KEY(day, domain));
                CREATE TABLE IF NOT EXISTS exclusion(
                    kind TEXT NOT NULL, value TEXT NOT NULL,
                    PRIMARY KEY(kind, value));
                """)
            try setUserVersion(1)
            version = 1
        }

        if version < 2 {
            // Page titles are no longer a saved data point — wipe any previously
            // stored ones. Titles now live only in memory for the live preview.
            try exec("UPDATE siteUsage SET lastTitle = NULL;")
            try setUserVersion(2)
            version = 2
        }

        if version < 3 {
            // Per-minute time-series samples that drive the usage line chart.
            try exec("""
                CREATE TABLE IF NOT EXISTS usageSample(
                    day TEXT NOT NULL, kind TEXT NOT NULL, key TEXT NOT NULL,
                    minute INTEGER NOT NULL, seconds REAL NOT NULL DEFAULT 0,
                    PRIMARY KEY(day, kind, key, minute));
                """)
            try setUserVersion(3)
            version = 3
        }
        // Future schema changes: `if version < 3 { ...; try setUserVersion(3) }`
        // Existing data is preserved — migrations are additive.
    }

    private func userVersion() -> Int {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "PRAGMA user_version;", -1, &stmt, nil) == SQLITE_OK else { return 0 }
        return sqlite3_step(stmt) == SQLITE_ROW ? Int(sqlite3_column_int64(stmt, 0)) : 0
    }
    private func setUserVersion(_ v: Int) throws { try exec("PRAGMA user_version=\(v);") }

    // MARK: Low-level helpers

    private enum Param { case text(String), double(Double), int(Int64), null }

    private func exec(_ sql: String) throws {
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errMsg) != SQLITE_OK {
            let message = errMsg.map { String(cString: $0) } ?? lastError
            sqlite3_free(errMsg)
            throw DBError.step(message)
        }
    }

    private func run(_ sql: String, _ params: [Param]) {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            NSLog("MacTrack DB prepare failed: \(lastError) — \(sql)"); return
        }
        bind(params, to: stmt)
        if sqlite3_step(stmt) != SQLITE_DONE { NSLog("MacTrack DB step failed: \(lastError)") }
    }

    private func bind(_ params: [Param], to stmt: OpaquePointer?) {
        for (i, p) in params.enumerated() {
            let idx = Int32(i + 1)
            switch p {
            case .text(let s): sqlite3_bind_text(stmt, idx, s, -1, SQLITE_TRANSIENT)
            case .double(let d): sqlite3_bind_double(stmt, idx, d)
            case .int(let n): sqlite3_bind_int64(stmt, idx, n)
            case .null: sqlite3_bind_null(stmt, idx)
            }
        }
    }

    private func textColumn(_ stmt: OpaquePointer?, _ i: Int32) -> String? {
        guard sqlite3_column_type(stmt, i) != SQLITE_NULL,
              let c = sqlite3_column_text(stmt, i) else { return nil }
        return String(cString: c)
    }
    private func doubleColumn(_ stmt: OpaquePointer?, _ i: Int32) -> Double? {
        sqlite3_column_type(stmt, i) == SQLITE_NULL ? nil : sqlite3_column_double(stmt, i)
    }

    // MARK: Reads

    func loadDays() -> [String: DayRecord] {
        var days: [String: DayRecord] = [:]
        query("SELECT day, bundleID, name, seconds, lastActive FROM appUsage") { stmt in
            guard let day = textColumn(stmt, 0), let bundleID = textColumn(stmt, 1) else { return }
            var rec = days[day] ?? DayRecord(dayKey: day)
            rec.apps[bundleID] = AppStat(
                bundleID: bundleID,
                name: textColumn(stmt, 2) ?? bundleID,
                seconds: doubleColumn(stmt, 3) ?? 0,
                lastActive: doubleColumn(stmt, 4).map { Date(timeIntervalSince1970: $0) }
            )
            days[day] = rec
        }
        query("SELECT day, domain, seconds, lastActive, lastTitle FROM siteUsage") { stmt in
            guard let day = textColumn(stmt, 0), let domain = textColumn(stmt, 1) else { return }
            var rec = days[day] ?? DayRecord(dayKey: day)
            rec.sites[domain] = SiteStat(
                domain: domain,
                seconds: doubleColumn(stmt, 2) ?? 0,
                lastActive: doubleColumn(stmt, 3).map { Date(timeIntervalSince1970: $0) },
                lastTitle: nil   // titles are never loaded from disk — live preview only
            )
            days[day] = rec
        }
        return days
    }

    func loadExclusions() -> (apps: Set<String>, sites: Set<String>) {
        var apps = Set<String>(), sites = Set<String>()
        query("SELECT kind, value FROM exclusion") { stmt in
            guard let kind = textColumn(stmt, 0), let value = textColumn(stmt, 1) else { return }
            if kind == "app" { apps.insert(value) } else if kind == "site" { sites.insert(value) }
        }
        return (apps, sites)
    }

    var isEmpty: Bool {
        var empty = true
        query("SELECT 1 FROM appUsage LIMIT 1") { _ in empty = false }
        return empty
    }

    private func query(_ sql: String, _ row: (OpaquePointer?) -> Void) {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            NSLog("MacTrack DB query prepare failed: \(lastError) — \(sql)"); return
        }
        while sqlite3_step(stmt) == SQLITE_ROW { row(stmt) }
    }

    // MARK: Writes (incremental upserts)

    func addApp(day: String, bundleID: String, name: String, addSeconds: Double, lastActive: Date) {
        run("""
            INSERT INTO appUsage(day, bundleID, name, seconds, lastActive) VALUES(?, ?, ?, ?, ?)
            ON CONFLICT(day, bundleID) DO UPDATE SET
              seconds = seconds + excluded.seconds, name = excluded.name, lastActive = excluded.lastActive
            """, [.text(day), .text(bundleID), .text(name), .double(addSeconds), .double(lastActive.timeIntervalSince1970)])
    }

    func addSite(day: String, domain: String, addSeconds: Double, lastActive: Date) {
        // Only the domain + time is persisted — never the page title / what you're
        // doing on the site. The lastTitle column is left unused (always NULL).
        run("""
            INSERT INTO siteUsage(day, domain, seconds, lastActive) VALUES(?, ?, ?, ?)
            ON CONFLICT(day, domain) DO UPDATE SET
              seconds = seconds + excluded.seconds, lastActive = excluded.lastActive
            """, [.text(day), .text(domain), .double(addSeconds), .double(lastActive.timeIntervalSince1970)])
    }

    /// Per-minute time-series sample for the chart. kind is "app"/"site",
    /// key is the bundle id / domain, minute is minute-of-day (0–1439).
    func addSample(day: String, kind: String, key: String, minute: Int, addSeconds: Double) {
        run("""
            INSERT INTO usageSample(day, kind, key, minute, seconds) VALUES(?, ?, ?, ?, ?)
            ON CONFLICT(day, kind, key, minute) DO UPDATE SET seconds = seconds + excluded.seconds
            """, [.text(day), .text(kind), .text(key), .int(Int64(minute)), .double(addSeconds)])
    }

    /// Today's samples keyed by "kind:key" → (minute → seconds).
    func loadSamples(day: String) -> [String: [Int: Double]] {
        var result: [String: [Int: Double]] = [:]
        query("SELECT kind, key, minute, seconds FROM usageSample WHERE day = '\(day)'") { stmt in
            guard let kind = textColumn(stmt, 0), let key = textColumn(stmt, 1) else { return }
            let minute = Int(sqlite3_column_int64(stmt, 2))
            let seconds = sqlite3_column_double(stmt, 3)
            result[kind + ":" + key, default: [:]][minute] = seconds
        }
        return result
    }

    private func pruneOldSamples(keepDays: Int = 35) {
        guard let cutoffDate = Calendar.current.date(byAdding: .day, value: -keepDays, to: Date()) else { return }
        try? exec("DELETE FROM usageSample WHERE day < '\(DayKey.key(for: cutoffDate))';")
    }

    func deleteApp(bundleID: String) { run("DELETE FROM appUsage WHERE bundleID = ?", [.text(bundleID)]) }
    func deleteSite(domain: String) { run("DELETE FROM siteUsage WHERE domain = ?", [.text(domain)]) }
    func setExclusion(kind: String, value: String) {
        run("INSERT OR IGNORE INTO exclusion(kind, value) VALUES(?, ?)", [.text(kind), .text(value)])
    }

    func importDay(_ record: DayRecord) {
        for stat in record.apps.values {
            addApp(day: record.dayKey, bundleID: stat.bundleID, name: stat.name,
                   addSeconds: stat.seconds, lastActive: stat.lastActive ?? Date())
        }
        for stat in record.sites.values {
            addSite(day: record.dayKey, domain: stat.domain, addSeconds: stat.seconds,
                    lastActive: stat.lastActive ?? Date())
        }
    }

    /// Flush the WAL into the main file — called on quit for extra safety.
    func checkpoint() { try? exec("PRAGMA wal_checkpoint(TRUNCATE);") }

    // MARK: Backups

    func makeDailyBackup(keepLast: Int = 14) {
        let dest = backupsDir.appendingPathComponent("MacTrack-\(DayKey.today).sqlite")
        let fm = FileManager.default
        if !fm.fileExists(atPath: dest.path) {
            let escaped = dest.path.replacingOccurrences(of: "'", with: "''")
            do { try exec("VACUUM INTO '\(escaped)';") } catch { NSLog("MacTrack backup: \(error)") }
        }
        if let files = try? fm.contentsOfDirectory(at: backupsDir, includingPropertiesForKeys: nil)
            .filter({ $0.lastPathComponent.hasPrefix("MacTrack-") && $0.pathExtension == "sqlite" })
            .sorted(by: { $0.lastPathComponent < $1.lastPathComponent }),
           files.count > keepLast {
            for f in files.prefix(files.count - keepLast) { try? fm.removeItem(at: f) }
        }
    }

    private func restoreFromLatestBackup() -> Bool {
        let fm = FileManager.default
        guard let latest = try? fm.contentsOfDirectory(at: backupsDir, includingPropertiesForKeys: nil)
            .filter({ $0.pathExtension == "sqlite" })
            .sorted(by: { $0.lastPathComponent > $1.lastPathComponent })
            .first else { return false }
        try? fm.removeItem(at: dbURL)
        do {
            try fm.copyItem(at: latest, to: dbURL)
            NSLog("MacTrack restored database from backup \(latest.lastPathComponent)")
            return true
        } catch { return false }
    }
}
