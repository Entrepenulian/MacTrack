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
                // Non-interactive glass: it's a visual material only, so it never
                // intercepts the click (the interactive variant was swallowing taps)
                // and there's no hover-lift to cause flicker. White-on-hover is manual.
                .glassEffect(.regular, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
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
