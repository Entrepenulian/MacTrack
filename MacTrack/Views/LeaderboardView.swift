import SwiftUI

/// A leaderboard of your best days — ranked by the *least* time spent on
/// unproductive apps and sites (the amount, never the date). It reuses the home
/// list's exact look: a small-caps header and monochrome rows with a faint
/// share-of-day wash and hover highlight.
struct LeaderboardView: View {
    @EnvironmentObject var store: UsageStore

    private var days: [Double] { store.lowestUnproductiveDays(limit: 3) }
    private var maxSeconds: Double { max(days.max() ?? 1, 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                SectionLabel(text: "Least distracted")
                Spacer()
                SectionLabel(text: "Unproductive")
            }
            .padding(.bottom, 6)

            if days.isEmpty {
                EmptyStateView(scope: .all)
            } else {
                VStack(spacing: 2) {
                    ForEach(Array(days.enumerated()), id: \.offset) { i, seconds in
                        LeaderboardRow(rank: i + 1, seconds: seconds,
                                       fraction: seconds / maxSeconds)
                    }
                }
            }
        }
    }
}

/// One rank — the same row as the home list: a badge in the icon slot, a title and
/// subtitle, the time on the right, a faint wash bar behind it, and a hover state.
private struct LeaderboardRow: View {
    let rank: Int
    let seconds: Double
    let fraction: Double
    @State private var hovering = false

    private var label: String {
        switch rank { case 1: "Your best day"; case 2: "Runner-up"; default: "Third best" }
    }

    var body: some View {
        HStack(spacing: 11) {
            Text("\(rank)")
                .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(Theme.Ink.secondary)
                .frame(width: 22, height: 22)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.fill(2)))

            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.rowTitle).foregroundStyle(Theme.Ink.primary)
                    .lineLimit(1)
                Text("on unproductive apps & sites")
                    .font(.rowMeta).foregroundStyle(Theme.Ink.tertiary)
                    .lineLimit(1).truncationMode(.tail)
            }

            Spacer(minLength: Theme.Space.sm)

            Text(Format.duration(seconds))
                .font(.rowValue.monospacedDigit())
                .foregroundStyle(Theme.Ink.secondary)
                .contentTransition(.numericText())
                .animation(.calm, value: seconds)
        }
        .padding(.horizontal, 10)
        .frame(height: 42)
        .background(alignment: .leading) {
            ZStack(alignment: .leading) {
                // Quiet bar-chart wash: width encodes this day's unproductive time.
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                        .frame(width: max(geo.size.width * CGFloat(fraction), Theme.Radius.row * 2))
                        .animation(.calm, value: fraction)
                }
                RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                    .fill(Color.primary.opacity(hovering ? 0.09 : 0))
                    .animation(.calm, value: hovering)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
        .onHover { h in withAnimation(.calm) { hovering = h } }
    }
}
