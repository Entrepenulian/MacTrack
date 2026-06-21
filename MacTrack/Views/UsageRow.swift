import SwiftUI

/// One ranked entry. Monochrome: a faint white wash behind the row encodes its
/// share of the day, so the list reads as a quiet bar chart without any color.
struct UsageRow: View {
    @EnvironmentObject var store: UsageStore
    let entry: UsageEntry
    @State private var hovering = false

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
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                    .fill(Color.primary.opacity(hovering ? 0.10 : 0.055))
                    .frame(width: max(geo.size.width * CGFloat(entry.fraction), Theme.Radius.row * 2))
                    .animation(.calm, value: entry.fraction)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
        .onHover { h in withAnimation(.calm) { hovering = h } }
        .contextMenu {
            Button("Don't track", systemImage: "eye.slash", role: .destructive) {
                switch entry.kind {
                case .app(let bundleID): store.excludeApp(bundleID)
                case .site(let domain): store.excludeSite(domain)
                }
            }
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
