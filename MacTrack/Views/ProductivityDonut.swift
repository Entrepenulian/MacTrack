import SwiftUI

/// The productivity overview: a ring split into Productive / Unproductive / Other,
/// the productive share called out in the center, and a legend below.
struct ProductivityDonut: View {
    let productive: Double
    let unproductive: Double
    let other: Double
    let hasTags: Bool

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

    private let lineWidth: CGFloat = 18
    private let gap: Double = 0.05   // gap between rounded segments (activity-ring look)

    var body: some View {
        VStack(spacing: 18) {
            ring
                .frame(width: 156, height: 156)
                .padding(.top, 6)
            legend
            if !hasTags {
                Text("Right-click any app or site to tag it productive or unproductive.")
                    .font(.rowMeta)
                    .foregroundStyle(Theme.Ink.tertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 4)
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
        let nonZero = rows.filter { $0.value > 0 }
        let useGap = nonZero.count > 1
        var cursor = 0.0
        var arcs: [(from: Double, to: Double, color: Color)] = []
        for r in nonZero {
            let frac = r.value / total
            // Inset each end for the gap, but never past the slice's midpoint, so a
            // small slice still draws a rounded nub instead of vanishing.
            let inset = useGap ? min(gap / 2, frac / 2) : 0
            let from = cursor + inset
            let to = max(from, cursor + frac - inset)
            arcs.append((from, to, r.color))
            cursor += frac
        }
        return ZStack {
            ForEach(Array(arcs.enumerated()), id: \.offset) { _, arc in
                Circle()
                    .trim(from: arc.from, to: arc.to)
                    .stroke(arc.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    // Each section glows in its own color — a tight glow plus a soft halo.
                    .shadow(color: arc.color.opacity(0.36), radius: 3)
                    .shadow(color: arc.color.opacity(0.18), radius: 8)
                    .rotationEffect(.degrees(-90))
            }
        }
        .animation(.calm, value: total)
    }

    private var center: some View {
        VStack(spacing: 1) {
            if total > 0 {
                Text("\(pct[0])%")
                    .font(.system(size: 32, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.Ink.primary)
                    .contentTransition(.numericText())
                Text("productive")
                    .font(.caption2Strong)
                    .foregroundStyle(Theme.Ink.tertiary)
            } else {
                Text("—").font(.system(size: 30, weight: .semibold)).foregroundStyle(Theme.Ink.tertiary)
                Text("no time yet").font(.caption2Strong).foregroundStyle(Theme.Ink.faint)
            }
        }
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
                    Text(Format.duration(r.value))
                        .font(.rowValue.monospacedDigit())
                        .foregroundStyle(Theme.Ink.primary)
                        .frame(minWidth: 54, alignment: .trailing)
                }
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
