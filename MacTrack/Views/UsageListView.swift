import SwiftUI

/// The ranked list for the active scope. Shows up to `maxItems` entries (10 by
/// default) with a calm stagger on first appearance — no collapsing, no clip.
struct UsageListView: View {
    let entries: [UsageEntry]
    var maxItems: Int = 10

    @State private var appeared = false

    private var visible: [UsageEntry] { Array(entries.prefix(maxItems)) }

    var body: some View {
        VStack(spacing: 2) {
            ForEach(Array(visible.enumerated()), id: \.element.id) { index, entry in
                UsageRow(entry: entry)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 6)
                    .animation(.calm.delay(Double(min(index, 9)) * 0.022), value: appeared)
            }
        }
        .onAppear { appeared = true }
    }
}

/// Shown when a scope has no data yet.
struct EmptyStateView: View {
    let scope: UsageScope

    private var title: String {
        switch scope {
        case .apps: return "No focused app time yet"
        case .websites: return "No website time yet"
        case .all: return "No activity yet"
        }
    }
    private var subtitle: String {
        switch scope {
        case .apps: return "Switch to an app and MacTrack starts counting."
        case .websites: return "Browse in Safari or Chrome to see sites here."
        case .all: return "Use your Mac and your time shows up here."
        }
    }

    var body: some View {
        VStack(spacing: Theme.Space.sm) {
            Image(systemName: scope.icon)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Theme.Ink.faint)
            Text(title)
                .font(.rowTitle)
                .foregroundStyle(Theme.Ink.secondary)
            Text(subtitle)
                .font(.rowMeta)
                .foregroundStyle(Theme.Ink.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Space.xxl)
    }
}

/// Shown above the Websites list when Automation hasn't been granted, so the
/// user understands why site time might be missing — and can fix it in one tap.
struct PermissionNudge: View {
    let action: () -> Void

    var body: some View {
        HStack(spacing: Theme.Space.md) {
            Image(systemName: "lock.shield")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.focus)
            VStack(alignment: .leading, spacing: 1) {
                Text("Allow website tracking")
                    .font(.rowTitle)
                    .foregroundStyle(Theme.Ink.primary)
                Text("Grant Automation access to read the active tab.")
                    .font(.rowMeta)
                    .foregroundStyle(Theme.Ink.tertiary)
            }
            Spacer(minLength: 0)
            Button("Open", action: action)
                .buttonStyle(.borderless)
                .font(.rowValue)
                .foregroundStyle(Theme.focus)
        }
        .padding(.horizontal, Theme.Space.md)
        .padding(.vertical, Theme.Space.md)
        .background(Theme.focus.opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .strokeBorder(Theme.focus.opacity(0.25), lineWidth: 0.5)
        )
    }
}
