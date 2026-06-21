import SwiftUI

/// A small, curated set of categories. Each owns one muted color so the
/// attention ribbon reads as a calm spectrum rather than a rainbow. The goal
/// is meaning, not decoration: color tells you *kind of work*, nothing else.
enum ActivityCategory: String, CaseIterable, Codable {
    case dev          // editors, terminals, IDEs
    case web          // browsers
    case communication
    case creative     // design / media production
    case media        // music, video, reading
    case productivity // notes, docs, mail, calendars
    case other

    var label: String {
        switch self {
        case .dev: return "Development"
        case .web: return "Web"
        case .communication: return "Communication"
        case .creative: return "Creative"
        case .media: return "Media"
        case .productivity: return "Productivity"
        case .other: return "Other"
        }
    }

    /// Muted, slightly desaturated jewel tones tuned to sit under glass.
    var color: Color {
        switch self {
        case .dev:           return Color(hex: 0x7FB3E0) // cool slate-blue
        case .web:           return Color(hex: 0xE0A45E) // focused amber (signature)
        case .communication: return Color(hex: 0x7FD0A8) // muted jade
        case .creative:      return Color(hex: 0xC79BE6) // soft orchid
        case .media:         return Color(hex: 0xE08B9A) // dusty rose
        case .productivity:  return Color(hex: 0x9AD0C2) // pale teal
        case .other:         return Color(hex: 0x9C9CA8) // graphite
        }
    }

    /// Best-effort classification from a bundle identifier. Deliberately small —
    /// unknowns fall to `.other` rather than guessing.
    static func classify(bundleID: String) -> ActivityCategory {
        let id = bundleID.lowercased()
        func has(_ needles: [String]) -> Bool { needles.contains { id.contains($0) } }

        if has(["safari", "chrome", "firefox", "arc", "edgemac", "brave", "thebrowser", "orion", "vivaldi", "zen"]) { return .web }
        if has(["xcode", "vscode", "code", "jetbrains", "intellij", "terminal", "iterm", "ghostty", "warp", "sublime", "nova", "zed", "cursor", "fork", "tower", "tableplus", "postico", "docker"]) { return .dev }
        if has(["slack", "discord", "zoom", "teams", "messages", "telegram", "whatsapp", "facetime", "webex", "signal"]) { return .communication }
        if has(["figma", "sketch", "photoshop", "illustrator", "affinity", "blender", "finalcut", "premiere", "aftereffects", "logic", "ableton", "pixelmator", "cinema4d", "davinci"]) { return .creative }
        if has(["music", "spotify", "vlc", "tv", "podcasts", "books", "quicktime", "iina", "netflix", "plex", "kindle"]) { return .media }
        if has(["mail", "notes", "notion", "obsidian", "things", "omnifocus", "fantastical", "calendar", "reminders", "pages", "numbers", "keynote", "word", "excel", "powerpoint", "craft", "bear", "drafts", "linear"]) { return .productivity }
        return .other
    }
}

// MARK: - Color hex convenience

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}
