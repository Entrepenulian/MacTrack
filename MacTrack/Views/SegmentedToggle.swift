import SwiftUI

enum UsageScope: String, CaseIterable, Identifiable {
    case apps = "Apps"
    case websites = "Websites"
    case all = "All"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .apps: return "square.grid.2x2"
        case .websites: return "globe"
        case .all: return "square.stack"
        }
    }
}

/// Apps / Websites slider with a single sliding glass pill. The "All" scope is a
/// separate button (see `AllButton`), so this control only holds the two.
struct SegmentedToggle: View {
    @Binding var selection: UsageScope
    @Namespace private var ns

    private let scopes: [UsageScope] = [.apps, .websites]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(scopes) { scope in
                let isSelected = selection == scope
                Button {
                    withAnimation(.pill) { selection = scope }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: scope.icon)
                            .font(.system(size: 11, weight: .semibold))
                        Text(scope.rawValue)
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(isSelected ? Theme.Ink.primary : Theme.Ink.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background {
                        if isSelected {
                            Capsule(style: .continuous)
                                .fill(Theme.fill(2))
                                .overlay(Capsule().strokeBorder(Theme.hairlineStrong, lineWidth: 0.5))
                                .matchedGeometryEffect(id: "pill", in: ns)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Theme.fill(0), in: Capsule(style: .continuous))
    }
}

/// A standalone "All" pill that matches the slider's styling but sits apart from
/// it. Selecting it shows every app and website merged, sorted by time.
struct AllButton: View {
    @Binding var selection: UsageScope

    var body: some View {
        let isSelected = selection == .all
        Button {
            withAnimation(.pill) { selection = .all }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: UsageScope.all.icon)
                    .font(.system(size: 11, weight: .semibold))
                Text("All")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(isSelected ? Theme.Ink.primary : Theme.Ink.tertiary)
            .padding(.vertical, 7)
            .padding(.horizontal, 13)
            .background {
                if isSelected {
                    Capsule(style: .continuous)
                        .fill(Theme.fill(2))
                        .overlay(Capsule().strokeBorder(Theme.hairlineStrong, lineWidth: 0.5))
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(3)
        .background(Theme.fill(0), in: Capsule(style: .continuous))
    }
}
