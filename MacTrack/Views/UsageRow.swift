import SwiftUI

/// One ranked entry. Monochrome: a faint white wash behind the row encodes its
/// share of the day, so the list reads as a quiet bar chart without any color.
///
/// Deliberately a pure value view (no `@EnvironmentObject`): it takes its tag and
/// action callbacks from the parent and is `Equatable` at minute resolution. That
/// way the list's per-second store updates don't re-render rows whose visible
/// content is unchanged — which is what made an open context submenu flicker.
struct UsageRow: View, Equatable {
    let entry: UsageEntry
    var currentTag: ProductivityTag? = nil
    var onBlock: (Int) -> Void = { _ in }
    var onTag: (ProductivityTag?) -> Void = { _ in }
    var onExclude: () -> Void = {}

    @State private var hovering = false

    static func == (lhs: UsageRow, rhs: UsageRow) -> Bool {
        lhs.entry.id == rhs.entry.id &&
        lhs.entry.title == rhs.entry.title &&
        lhs.entry.subtitle == rhs.entry.subtitle &&
        Format.duration(lhs.entry.seconds) == Format.duration(rhs.entry.seconds) &&
        Int((lhs.entry.fraction * 100).rounded()) == Int((rhs.entry.fraction * 100).rounded()) &&
        lhs.currentTag == rhs.currentTag
    }

    var body: some View {
        HStack(spacing: 11) {
            icon

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title)
                    .font(.rowTitle)
                    .foregroundStyle(Theme.Ink.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let subtitle = entry.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.rowMeta)
                        .foregroundStyle(Theme.Ink.tertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: Theme.Space.sm)

            Text(Format.duration(entry.seconds))
                .font(.rowValue.monospacedDigit())
                .foregroundStyle(Theme.Ink.secondary)
                .contentTransition(.numericText())
                // Flip the digits only when the actual time changes — never on hover.
                .animation(.calm, value: entry.seconds)
        }
        .padding(.horizontal, 10)
        .frame(height: entry.subtitle?.isEmpty == false ? 42 : 36)
        .background(alignment: .leading) {
            ZStack(alignment: .leading) {
                // Quiet bar-chart wash: width encodes this row's share of the day.
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                        .frame(width: max(geo.size.width * CGFloat(entry.fraction), Theme.Radius.row * 2))
                        .animation(.calm, value: entry.fraction)
                }
                // Full-row hover highlight — a clear state, not just a brighter bar.
                RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                    .fill(Color.primary.opacity(hovering ? 0.09 : 0))
                    .animation(.calm, value: hovering)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
        .onHover { h in withAnimation(.calm) { hovering = h } }
        .contextMenu {
            Menu {
                Button("15 minutes") { onBlock(15) }
                Button("30 minutes") { onBlock(30) }
                Button("1 hour") { onBlock(60) }
                Button("2 hours") { onBlock(120) }
            } label: {
                Label("Block…", systemImage: "hand.raised")
            }
            Menu {
                Button { onTag(.productive) } label: {
                    Label("Productive", systemImage: currentTag == .productive ? "checkmark" : "leaf")
                }
                Button { onTag(.unproductive) } label: {
                    Label("Unproductive", systemImage: currentTag == .unproductive ? "checkmark" : "minus.circle")
                }
                Button { onTag(nil) } label: {
                    Label("Clear", systemImage: currentTag == nil ? "checkmark" : "circle")
                }
            } label: {
                Label("Productivity", systemImage: "chart.pie")
            }
            Button("Don't track", systemImage: "eye.slash", role: .destructive) { onExclude() }
        }
    }

    @ViewBuilder private var icon: some View {
        switch entry.kind {
        case .app(let bundleID):
            AppIconView(bundleID: bundleID, size: 22)
        case .site(let domain):
            FaviconView(domain: domain, size: 22)
        }
    }
}
