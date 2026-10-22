import SwiftUI

/// A project ("tag") you can work on. Time is credited to whichever project is
/// active when the sampler ticks, so renaming or reassigning never relabels a
/// past day.
struct Project: Identifiable, Hashable {
    let id: String          // UUID().uuidString
    var name: String
    var colorHex: String    // six hex digits, no '#'
    var archived: Bool
    var sortOrder: Int

    var color: Color { Color(hex: UInt32(colorHex, radix: 16) ?? 0x70707A) }
    var badge: ProjectBadge { ProjectBadge(id: id, name: name, colorHex: colorHex) }
}

/// The immutable slice a row needs — keeps `UsageRow` a pure value view.
struct ProjectBadge: Equatable, Identifiable {
    let id: String
    let name: String
    let colorHex: String
    var color: Color { Color(hex: UInt32(colorHex, radix: 16) ?? 0x70707A) }
}

/// Keys in the "remembered association" table: "app:<bundleID>" / "site:<domain>".
enum ProjectKey {
    static func key(kind: String, value: String) -> String { kind + ":" + value }
}
