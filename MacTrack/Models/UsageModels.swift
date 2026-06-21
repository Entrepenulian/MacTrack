import Foundation
import SwiftUI

// MARK: - Persisted records
//
// The store keeps one DayRecord per calendar day, keyed by an ISO "yyyy-MM-dd"
// string. Each day holds two rollups: focused time per application (by bundle
// identifier) and focused time per website (by registrable domain). We persist
// aggregates, never raw ticks, so the file stays small and reads instantly.

struct AppStat: Codable, Hashable {
    var bundleID: String
    var name: String
    var seconds: Double
    var lastActive: Date?
}

struct SiteStat: Codable, Hashable {
    var domain: String
    var seconds: Double
    var lastActive: Date?
    /// Most recent page title seen for this domain — used as a subtle subtitle.
    var lastTitle: String?
}

struct DayRecord: Codable {
    var dayKey: String
    var apps: [String: AppStat] = [:]      // bundleID -> stat
    var sites: [String: SiteStat] = [:]    // domain   -> stat

    var totalAppSeconds: Double { apps.values.reduce(0) { $0 + $1.seconds } }
    var totalSiteSeconds: Double { sites.values.reduce(0) { $0 + $1.seconds } }
}

// MARK: - View-facing rows

/// A single ranked entry in the Apps or Websites list.
struct UsageEntry: Identifiable, Hashable {
    enum Kind: Hashable { case app(bundleID: String), site(domain: String) }

    var id: String
    var kind: Kind
    var title: String
    var subtitle: String?
    var seconds: Double
    var category: ActivityCategory

    /// 0...1 share of the largest entry in its list, for proportional bars.
    var fraction: Double = 0
}

// MARK: - Date helpers

enum DayKey {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func key(for date: Date) -> String { formatter.string(from: date) }
    static func date(from key: String) -> Date? { formatter.date(from: key) }
    static var today: String { key(for: Date()) }

    /// Minute of the day (0–1439) in the local time zone — used to bucket the
    /// time-series samples that drive the line chart.
    static var minuteOfDay: Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: Date())
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}

/// One line in the usage chart: a cumulative-minutes series for a single item.
struct ChartLineData: Identifiable {
    let id: String          // matches UsageEntry.id ("app:bundleID" / "site:domain")
    let label: String
    let color: Color
    let points: [CGPoint]   // x = minute-of-day, y = cumulative minutes
    let totalMinutes: Double
}
