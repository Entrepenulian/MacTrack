import SwiftUI

/// A scheduled block of an app or website until a fixed end time. Persisted, so
/// it survives quitting and relaunching the app. There is intentionally no way
/// to end a block early — the only exit is the clock running out.
struct BlockRecord: Identifiable {
    let id: String        // "app:bundleID" / "site:domain"
    let kind: String      // "app" / "site"
    let value: String     // bundle id / domain
    var endsAt: Date
    let createdAt: Date

    var remaining: TimeInterval { max(0, endsAt.timeIntervalSinceNow) }
    var label: String { value }
}

/// Owns active blocks and the locked countdown. Enforcement (hiding apps,
/// bouncing tabs) is done by `ActivityMonitor`, which reads this controller.
///
/// Clock-tamper resistance (while running): if the wall clock jumps forward
/// beyond real elapsed time, every block's end is pushed forward by the same
/// amount, so setting the clock ahead can't skip a block.
@MainActor
final class BlockController: ObservableObject {
    @Published private(set) var blocks: [BlockRecord] = []

    /// Shared with the Network Extension (Tier 3) so the system filter sees the
    /// same blocked sites. Must match the App Group on both targets.
    static let appGroup = "group.com.julianhahne.MacTrack"

    private let db: DatabaseStore?
    private var lastMonotonic = ProcessInfo.processInfo.systemUptime
    private var lastWall = Date()

    init(db: DatabaseStore?) {
        self.db = db
        let loaded = db?.loadBlocks() ?? []
        let now = Date()
        blocks = loaded.filter { $0.endsAt > now }
        for stale in loaded where stale.endsAt <= now { db?.deleteBlock(id: stale.id) }
        syncToAppGroup()
    }

    var activeBlocks: [BlockRecord] {
        blocks.filter { $0.endsAt > Date() }.sorted { $0.endsAt < $1.endsAt }
    }

    func isAppBlocked(_ bundleID: String) -> Bool {
        blocks.contains { $0.kind == "app" && $0.value == bundleID && $0.endsAt > Date() }
    }
    func isSiteBlocked(_ domain: String) -> Bool {
        blocks.contains { $0.kind == "site" && $0.value == domain && $0.endsAt > Date() }
    }

    /// Start (or extend) a block. Never shortens an existing one.
    func block(kind: String, value: String, minutes: Int) {
        let id = kind + ":" + value
        let now = Date()
        let end = now.addingTimeInterval(Double(minutes) * 60)
        if let i = blocks.firstIndex(where: { $0.id == id }) {
            guard end > blocks[i].endsAt else { return }
            blocks[i].endsAt = end
            db?.updateBlockEnds(id: id, endsAt: end.timeIntervalSince1970)
        } else {
            blocks.append(BlockRecord(id: id, kind: kind, value: value, endsAt: end, createdAt: now))
            db?.upsertBlock(id: id, kind: kind, value: value,
                            endsAt: end.timeIntervalSince1970, createdAt: now.timeIntervalSince1970)
        }
        objectWillChange.send()
        syncToAppGroup()
    }

    /// Called once a second by the sampler: expire finished blocks and resist
    /// forward clock changes.
    func tick() {
        let now = Date()
        let mono = ProcessInfo.processInfo.systemUptime
        let realDelta = mono - lastMonotonic
        let wallDelta = now.timeIntervalSince(lastWall)
        if realDelta >= 0, wallDelta - realDelta > 3 {           // clock pushed forward
            let shift = wallDelta - realDelta
            for i in blocks.indices {
                blocks[i].endsAt = blocks[i].endsAt.addingTimeInterval(shift)
                db?.updateBlockEnds(id: blocks[i].id, endsAt: blocks[i].endsAt.timeIntervalSince1970)
            }
        }
        lastMonotonic = mono
        lastWall = now

        let expired = blocks.filter { $0.endsAt <= now }
        if !expired.isEmpty {
            for b in expired { db?.deleteBlock(id: b.id) }
            blocks.removeAll { $0.endsAt <= now }
            syncToAppGroup()
        }
        objectWillChange.send()   // keep countdowns live
    }

    /// Mirror the blocked-site list into the shared App Group file the Network
    /// Extension reads. No-op until the App Group entitlement is present, so the
    /// app-side build runs fine without it.
    private func syncToAppGroup() {
        guard let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroup) else { return }
        let domains = activeBlocks.filter { $0.kind == "site" }.map { $0.value }
        let url = dir.appendingPathComponent("blocked-domains.json")
        if let data = try? JSONEncoder().encode(domains) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
