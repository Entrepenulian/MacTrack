import SwiftUI
import AppKit

/// The productivity overview: a ring split into Productive / Unproductive / Other,
/// the productive share called out in the center, and a legend below.
struct ProductivityDonut: View {
    let productive: Double
    let unproductive: Double
    let other: Double
    let hasTags: Bool
    /// The day whose data is shown — drives the slice drill-down's apps/sites too.
    var day: String = DayKey.today
    /// The day the popover is currently showing (so the matching square highlights).
    var selectedDay: String? = nil
    /// Called when a past day's square is tapped — the popover switches to that day.
    var onSelectDay: (String) -> Void = { _ in }

    @State private var hoveredSlice: Int? = nil
    @State private var cursorActive = false
    @State private var selected: Int? = nil          // tapped slice → its breakdown
    @EnvironmentObject private var store: UsageStore

    private var total: Double { productive + unproductive + other }

    private var rows: [(name: String, value: Double, color: Color)] {
        [("Productive", productive, Theme.productive),
         ("Unproductive", unproductive, Theme.unproductive),
         ("Other", other, Theme.neutralSlice)]
    }

    /// Integer percentages that always sum to 100, where any non-zero slice shows
    /// at least 1% — so the legend is internally consistent and the center never
    /// claims 100% while other slices still hold real time.
    private var pct: [Int] { Self.percentages([productive, unproductive, other]) }

    private let lineWidth: CGFloat = 14       // default slice thickness
    private let hoverWidth: CGFloat = 18      // the hovered slice grows to this
    private let gap: Double = 0.05   // gap between rounded segments (activity-ring look)

    var body: some View {
        VStack(spacing: 16) {
            ring
                .frame(width: 156, height: 156)
                .frame(width: 184, height: 184)        // larger, centered hit area
                .contentShape(Rectangle())
                .onContinuousHover(coordinateSpace: .local) { handleHover($0) }
                .onTapGesture { tapRing() }
                .onDisappear { if cursorActive { NSCursor.pop(); cursorActive = false } }
                .padding(.top, 2)

            // Tap a slice to drill into its apps/sites; tap again (or the back
            // chevron) to return to the legend.
            ZStack {
                if let sel = selected {
                    // .id(sel) gives each category its own identity, so switching from
                    // one slice to another crossfades the rows instead of snapping.
                    detail(for: sel)
                        .id(sel)
                        .transition(.opacity)
                } else {
                    VStack(spacing: 12) {
                        legend
                        if !hasTags { hint }
                        activitySection
                    }
                    .transition(.opacity)
                }
            }
            .animation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.3), value: selected)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 4)
    }

    /// A GitHub-style activity grid under the legend, separated by a hairline.
    /// Visual only for now — the squircles light up once its data is wired.
    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Rectangle().fill(Theme.hairline).frame(height: 0.5)
            ActivityGraph(winners: store.dailyWinners(daysBack: 140),
                          selectedDay: selectedDay,
                          onSelect: onSelectDay)
        }
        .padding(.horizontal, 4)
    }

    private var hint: some View {
        Text("Right-click any app or site to tag it productive or unproductive.")
            .font(.rowMeta)
            .foregroundStyle(Theme.Ink.tertiary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
    }

    private var ring: some View {
        ZStack {
            if total > 0 {
                segments
            } else {
                // A faint ring only when there's no data — never behind the colored
                // arcs, so the gaps stay clean instead of showing a gray track.
                Circle().stroke(Color.white.opacity(0.06), lineWidth: lineWidth)
            }
            center
        }
    }

    private var segments: some View {
        let layout = sliceLayout
        let useGap = layout.count > 1
        let arcs: [(from: Double, to: Double, color: Color, index: Int)] = layout.map { s in
            let inset = useGap ? gap / 2 : 0
            let from = s.start + inset
            let to = max(from + 0.004, s.end - inset)
            return (from, to, s.color, s.index)
        }
        return ZStack {
            ForEach(Array(arcs.enumerated()), id: \.offset) { _, arc in
                let hot = hoveredSlice == arc.index || selected == arc.index
                Circle()
                    .trim(from: arc.from, to: arc.to)
                    .stroke(arc.color, style: StrokeStyle(lineWidth: hot ? hoverWidth : lineWidth, lineCap: .round))
                    // Slices are thin by default; the hovered/selected one grows and glows.
                    .shadow(color: arc.color.opacity(hot ? 0.55 : 0.36), radius: hot ? 5 : 3)
                    .shadow(color: arc.color.opacity(hot ? 0.34 : 0.18), radius: hot ? 14 : 8)
                    .rotationEffect(.degrees(-90))
            }
        }
        .animation(.calm, value: total)
        .animation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.28), value: hoveredSlice)
        .animation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.28), value: selected)
    }

    /// Each non-zero slice's `[start, end]` span of the full ring. Every slice is
    /// allocated at least a minimum arc so a tiny one (1–4%) still draws a clear
    /// segment instead of vanishing into a gap; the surplus is taken from the
    /// larger slices. The center % and legend keep showing the true values — only
    /// the drawn proportions are nudged. Hit-testing reads this same layout.
    private var sliceLayout: [(index: Int, start: Double, end: Double, color: Color)] {
        guard total > 0 else { return [] }
        let nz = rows.enumerated().filter { $0.element.value > 0 }
        guard !nz.isEmpty else { return [] }
        // Reserve enough that, after the gap is inset on both ends, the smallest
        // slice still draws a visible arc (~0.04 of the ring).
        let minA = nz.count > 1 ? gap + 0.04 : 0
        let alloc = Self.allocate(nz.map { $0.element.value / total }, minA: minA)
        var cursor = 0.0
        var out: [(index: Int, start: Double, end: Double, color: Color)] = []
        for (k, item) in nz.enumerated() {
            out.append((item.offset, cursor, cursor + alloc[k], item.element.color))
            cursor += alloc[k]
        }
        return out
    }

    /// Give every slice at least `minA` of the ring, taking the surplus from the
    /// larger slices proportionally (pinning the smallest first, iterating). Input
    /// and output both sum to 1.
    static func allocate(_ fracs: [Double], minA: Double) -> [Double] {
        guard minA > 0, fracs.count > 1, minA * Double(fracs.count) < 1 else { return fracs }
        var a = fracs
        var pinned = [Bool](repeating: false, count: fracs.count)
        for _ in 0..<fracs.count {
            var deficit = 0.0
            for i in a.indices where !pinned[i] && a[i] < minA {
                deficit += minA - a[i]; a[i] = minA; pinned[i] = true
            }
            if deficit <= 0 { break }
            let freeSum = a.indices.filter { !pinned[$0] }.reduce(0.0) { $0 + a[$1] }
            guard freeSum > deficit else { break }
            let scale = (freeSum - deficit) / freeSum
            for i in a.indices where !pinned[i] { a[i] *= scale }
        }
        return a
    }

    private func handleHover(_ phase: HoverPhase) {
        switch phase {
        case .active(let p):
            let idx = sliceIndex(at: p)
            hoveredSlice = idx
            if idx != nil && !cursorActive { NSCursor.pointingHand.push(); cursorActive = true }
            else if idx == nil && cursorActive { NSCursor.pop(); cursorActive = false }
        case .ended:
            hoveredSlice = nil
            if cursorActive { NSCursor.pop(); cursorActive = false }
        }
    }

    /// Which slice (row index) the cursor is over on the ring, from its angle and
    /// distance from the center. Returns nil for the hole, the center, or outside.
    private func sliceIndex(at p: CGPoint) -> Int? {
        guard total > 0 else { return nil }
        let c = 92.0   // center of the 184×184 hit frame
        let dx = Double(p.x) - c, dy = Double(p.y) - c
        let r = (dx * dx + dy * dy).squareRoot()
        // Generous band around the ring (path radius ~78) so you don't have to land
        // exactly on the stroke — forgiving ~17px inward and ~10px outward.
        guard r >= 54, r <= 96 else { return nil }
        let ang = atan2(dy, dx) * 180 / .pi               // 0° = right, clockwise (y-down)
        var f = (ang + 90).truncatingRemainder(dividingBy: 360)
        if f < 0 { f += 360 }
        let frac = f / 360                                // clockwise from the top, [0,1)
        // Match the drawn (min-size-allocated) layout so you hover what you see.
        for s in sliceLayout where frac >= s.start && frac < s.end { return s.index }
        return nil
    }

    /// Which section the center shows: the hovered one, or — by default — the
    /// section with the highest percentage.
    private var shownIndex: Int {
        if let h = hoveredSlice { return h }
        if let s = selected { return s }
        let p = pct
        return p.indices.max(by: { p[$0] < p[$1] }) ?? 0
    }

    private var center: some View {
        VStack(spacing: 1) {
            if total > 0 {
                let idx = shownIndex
                Text("\(pct[idx])%")
                    .font(.system(size: 32, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.Ink.primary)
                    .contentTransition(.numericText())          // digits flip in/out on change
                Text(rows[idx].name.lowercased())
                    .font(.caption2Strong)
                    .foregroundStyle(Theme.Ink.tertiary)
                    .contentTransition(.opacity)                // crossfade the label on change
            } else {
                Text("—").font(.system(size: 30, weight: .semibold)).foregroundStyle(Theme.Ink.tertiary)
                Text("no time yet").font(.caption2Strong).foregroundStyle(Theme.Ink.faint)
            }
        }
        .animation(.smooth(duration: 0.3), value: shownIndex)
    }

    private var legend: some View {
        VStack(spacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                HStack(spacing: 9) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(r.color)
                        .frame(width: 9, height: 9)
                    Text(r.name)
                        .font(.rowTitle)
                        .foregroundStyle(Theme.Ink.secondary)
                    Spacer()
                    Text("\(total > 0 ? pct[i] : 0)%")
                        .font(.rowMeta.monospacedDigit())
                        .foregroundStyle(Theme.Ink.tertiary)
                        .contentTransition(.numericText())
                    Text(Format.duration(r.value))
                        .font(.rowValue.monospacedDigit())
                        .foregroundStyle(Theme.Ink.primary)
                        .frame(minWidth: 54, alignment: .trailing)
                        .contentTransition(.numericText())
                }
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: Tap-to-drill-down

    private func tapRing() {
        if let h = hoveredSlice {
            selected = (selected == h) ? nil : h
        } else {
            selected = nil
        }
    }

    private func tagFor(_ index: Int) -> ProductivityTag? {
        switch index {
        case 0: return .productive
        case 1: return .unproductive
        default: return nil          // Other = untagged
        }
    }

    /// The breakdown for one category: a header (back · dot · name · total) and the
    /// apps/sites that make it up, each with its share wash and time.
    private func detail(for index: Int) -> some View {
        let r = rows[index]
        let items = store.productivityItems(tag: tagFor(index), for: day)
        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.3)) { selected = nil }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.Ink.secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Text(r.name).font(.rowTitle).foregroundStyle(Theme.Ink.primary)
                Spacer()
                Text("\(total > 0 ? pct[index] : 0)%")
                    .font(.rowMeta.monospacedDigit()).foregroundStyle(Theme.Ink.tertiary)
                Text(Format.duration(r.value))
                    .font(.rowValue.monospacedDigit()).foregroundStyle(Theme.Ink.primary)
            }
            .padding(.bottom, 9)

            Rectangle().fill(Theme.hairline).frame(height: 0.5)

            if items.isEmpty {
                Text("Nothing tagged \(r.name.lowercased()) yet.")
                    .font(.rowMeta).foregroundStyle(Theme.Ink.tertiary)
                    .frame(maxWidth: .infinity).padding(.vertical, 18)
            } else {
                VStack(spacing: 2) {
                    ForEach(items.prefix(7)) { BreakdownRow(entry: $0, color: r.color, categoryTotal: r.value) }
                    if items.count > 7 {
                        Text("+\(items.count - 7) more")
                            .font(.rowMeta).foregroundStyle(Theme.Ink.faint)
                            .frame(maxWidth: .infinity).padding(.top, 5)
                    }
                }
                .padding(.top, 7)
            }
        }
        .padding(.horizontal, 4)
    }

    /// Largest-remainder apportionment to 100, with a 1% floor for any non-zero
    /// value (and a trim from the largest slice if the floor overshoots).
    static func percentages(_ values: [Double]) -> [Int] {
        let total = values.reduce(0, +)
        guard total > 0 else { return values.map { _ in 0 } }
        let raw = values.map { $0 / total * 100 }
        var pct = raw.map { Int($0.rounded(.down)) }
        for i in values.indices where values[i] > 0 && pct[i] == 0 { pct[i] = 1 }

        var remaining = 100 - pct.reduce(0, +)
        if remaining > 0 {
            let order = values.indices.sorted {
                (raw[$0] - raw[$0].rounded(.down)) > (raw[$1] - raw[$1].rounded(.down))
            }
            var i = 0
            while remaining > 0 { pct[order[i % order.count]] += 1; remaining -= 1; i += 1 }
        } else if remaining < 0 {
            let order = values.indices.sorted { pct[$0] > pct[$1] }
            var i = 0, guardCount = 0
            while remaining < 0, guardCount < 1000 {
                let idx = order[i % order.count]
                if pct[idx] > 1 { pct[idx] -= 1; remaining += 1 }
                i += 1; guardCount += 1
            }
        }
        return pct
    }
}

/// One row in a productivity breakdown: icon · name · time, with a share wash in
/// the category color and a subtle full-row highlight on hover.
private struct BreakdownRow: View {
    let entry: UsageEntry
    let color: Color
    let categoryTotal: Double
    @State private var hovering = false
    @EnvironmentObject private var store: UsageStore
    @EnvironmentObject private var blocks: BlockController

    private var currentTag: ProductivityTag? {
        switch entry.kind {
        case .app(let b): return store.appTag(b)
        case .site(let d): return store.siteTag(d)
        }
    }
    private func setTag(_ tag: ProductivityTag?) {
        switch entry.kind {
        case .app(let b): store.setAppTag(b, tag)
        case .site(let d): store.setSiteTag(d, tag)
        }
    }
    private func startBlock(_ minutes: Int) {
        switch entry.kind {
        case .app(let b): blocks.block(kind: "app", value: b, minutes: minutes)
        case .site(let d): blocks.block(kind: "site", value: d, minutes: minutes)
        }
    }
    private func dontTrack() {
        switch entry.kind {
        case .app(let b): store.excludeApp(b)
        case .site(let d): store.excludeSite(d)
        }
    }

    /// Share of its own category (e.g. 30m of 60m productive → 50%). Any real time
    /// shows at least 1%, so a tiny entry never reads "0%".
    private var percent: Int {
        guard categoryTotal > 0, entry.seconds > 0 else { return 0 }
        return max(1, Int((entry.seconds / categoryTotal * 100).rounded()))
    }

    var body: some View {
        HStack(spacing: 10) {
            icon.frame(width: 20, height: 20)
            Text(entry.title)
                .font(.rowTitle).foregroundStyle(Theme.Ink.primary)
                .lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 8)
            Text("\(percent)%")
                .font(.rowMeta.monospacedDigit()).foregroundStyle(Theme.Ink.tertiary)
            Text(Format.duration(entry.seconds))
                .font(.rowValue.monospacedDigit()).foregroundStyle(Theme.Ink.secondary)
                .frame(minWidth: 46, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .frame(height: 34)
        .background(alignment: .leading) {
            ZStack(alignment: .leading) {
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                        .fill(color.opacity(0.16))
                        .frame(width: max(geo.size.width * CGFloat(entry.fraction), Theme.Radius.row * 2))
                }
                RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                    .fill(Color.primary.opacity(hovering ? 0.08 : 0))
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hovering = h } }
        .contextMenu {
            Menu {
                Button("15 minutes") { startBlock(15) }
                Button("30 minutes") { startBlock(30) }
                Button("1 hour") { startBlock(60) }
                Button("2 hours") { startBlock(120) }
            } label: {
                Label("Block…", systemImage: "hand.raised")
            }
            Menu {
                Button { setTag(.productive) } label: {
                    Label("Productive", systemImage: currentTag == .productive ? "checkmark" : "leaf")
                }
                Button { setTag(.unproductive) } label: {
                    Label("Unproductive", systemImage: currentTag == .unproductive ? "checkmark" : "minus.circle")
                }
                Button { setTag(nil) } label: {
                    Label("Clear", systemImage: currentTag == nil ? "checkmark" : "circle")
                }
            } label: {
                Label("Productivity", systemImage: "chart.pie")
            }
            Button("Don't track", systemImage: "eye.slash", role: .destructive) { dontTrack() }
        }
    }

    @ViewBuilder private var icon: some View {
        switch entry.kind {
        case .app(let bundleID): AppIconView(bundleID: bundleID, size: 20)
        case .site(let domain): FaviconView(domain: domain, size: 20)
        }
    }
}
