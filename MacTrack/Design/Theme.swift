import SwiftUI

/// Design tokens. One place, named for this product's world — "ink", "focus",
/// "ribbon" — so the system reads as MacTrack and not a generic template.
enum Theme {

    // Spacing — base unit 4.
    enum Space {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 28
    }

    // Corner radii — sharper for small controls, softer for panels.
    enum Radius {
        static let chip: CGFloat = 8
        static let row: CGFloat = 11
        static let card: CGFloat = 18
        static let panel: CGFloat = 24
    }

    // Foreground hierarchy — four levels, used consistently. Tuned a little
    // brighter than default so lower tiers stay legible over translucent glass.
    enum Ink {
        static let primary = Color.primary
        static let secondary = Color.primary.opacity(0.72)
        static let tertiary = Color.primary.opacity(0.52)
        static let faint = Color.primary.opacity(0.32)
    }

    /// The single accent — "focused light". Warm amber, the color the Web
    /// category also uses, because attention online is where time leaks.
    static let focus = Color(hex: 0xE0A45E)

    /// Ten distinguishable, lightly-muted line colors for the usage chart. The
    /// first is the focus amber so the top item ties to the brand accent. Used
    /// by chart line N and the matching list row's color dot.
    static let chartPalette: [Color] = [
        Color(hex: 0xE0A45E), // amber
        Color(hex: 0x5B9BF0), // blue
        Color(hex: 0x5FC88F), // green
        Color(hex: 0xC79BE6), // orchid
        Color(hex: 0xE8736A), // coral
        Color(hex: 0x4FC4C4), // teal
        Color(hex: 0xE88FB6), // pink
        Color(hex: 0xA6CC52), // lime
        Color(hex: 0x7E86E0), // indigo
        Color(hex: 0x9C9CA8), // graphite
    ]

    static func chartColor(_ index: Int) -> Color { chartPalette[index % chartPalette.count] }

    // Hairline separators that define edges without demanding attention.
    static let hairline = Color.primary.opacity(0.08)
    static let hairlineStrong = Color.primary.opacity(0.14)

    // Fills layered over glass — whisper-quiet elevation steps.
    static func fill(_ level: Int) -> Color {
        switch level {
        case 0: return Color.primary.opacity(0.04)
        case 1: return Color.primary.opacity(0.06)
        case 2: return Color.primary.opacity(0.09)
        default: return Color.primary.opacity(0.12)
        }
    }
}

// MARK: - Typography

extension Font {
    /// Large total readout — precise, tight, tabular.
    static var totalReadout: Font { .system(size: 34, weight: .semibold, design: .default) }
    static var sectionTitle: Font { .system(size: 12, weight: .semibold) }
    static var rowTitle: Font { .system(size: 13, weight: .medium) }
    static var rowMeta: Font { .system(size: 11, weight: .regular) }
    static var rowValue: Font { .system(size: 12.5, weight: .semibold) }
    static var caption2Strong: Font { .system(size: 10, weight: .semibold) }
}

// MARK: - Motion

extension Animation {
    /// Smooth, no-bounce deceleration for professional surfaces.
    static var calm: Animation { .easeOut(duration: 0.22) }
    static var calmSlow: Animation { .easeInOut(duration: 0.32) }
    /// A single restrained spring, reserved for the segmented pill.
    static var pill: Animation { .spring(response: 0.34, dampingFraction: 0.82) }
}
