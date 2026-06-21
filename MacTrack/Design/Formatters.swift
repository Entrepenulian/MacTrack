import Foundation

enum Format {

    /// Compact, human duration: "2h 14m", "47m", "38s", "0m".
    static func duration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        if total < 60 { return "\(total)s" }
        let m = (total / 60) % 60
        let h = total / 3600
        if h > 0 { return m > 0 ? "\(h)h \(m)m" : "\(h)h" }
        return "\(m)m"
    }

    /// The big readout, split so each unit can be styled smaller and animate
    /// independently. Always counts down to seconds: ("2","h"),("14","m"),("09","s").
    /// Trailing units are zero-padded so digits flip in place rather than reflow.
    static func readoutParts(_ seconds: Double) -> [(value: String, unit: String)] {
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total / 60) % 60
        let s = total % 60
        if h > 0 { return [("\(h)", "h"), (String(format: "%02d", m), "m"), (String(format: "%02d", s), "s")] }
        if m > 0 { return [("\(m)", "m"), (String(format: "%02d", s), "s")] }
        return [("\(s)", "s")]
    }

    /// "Tuesday, June 20" style header subtitle.
    static func longDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f.string(from: date)
    }

    /// Short weekday for trend columns: "Mon".
    static func shortWeekday(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f.string(from: date)
    }
}
