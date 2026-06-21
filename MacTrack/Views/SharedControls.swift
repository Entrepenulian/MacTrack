import SwiftUI

/// A small circular glass button for header/footer actions.
struct GlassIconButton: View {
    let systemName: String
    var size: CGFloat = 28
    var help: String = ""
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(hovering ? Color.white : Theme.Ink.secondary)
                .frame(width: size, height: size)
                .glassEffect(.regular.interactive(), in: Circle())
        }
        .buttonStyle(.plain)
        // Hover is detected on this FIXED outer frame, not on the glass itself.
        // The glass's hover-lift is render-only, so the hit area never moves and
        // the cursor can't fall outside — no flicker. Icon snaps straight to white.
        .frame(width: size, height: size)
        .contentShape(Circle())
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// Section label in the small-caps tracked style used across the app.
struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.caption2Strong)
            .tracking(0.6)
            .foregroundStyle(Theme.Ink.tertiary)
    }
}
