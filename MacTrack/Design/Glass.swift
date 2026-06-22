import SwiftUI

/// Centralized Liquid Glass treatments. Keeping them in one place means the
/// material language stays consistent — and if the platform glass API shifts,
/// there is exactly one spot to adjust.
extension View {

    /// A glass panel with a continuous-rounded shape.
    func glassPanel(_ radius: CGFloat = Theme.Radius.card) -> some View {
        glassEffect(.regular, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    /// A subtly tinted glass panel — used sparingly for the signature surfaces.
    func glassPanelTinted(_ radius: CGFloat = Theme.Radius.card, tint: Color) -> some View {
        glassEffect(.regular.tint(tint.opacity(0.18)), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    /// An interactive glass capsule for buttons and toggles.
    func glassControl(interactive: Bool = true) -> some View {
        glassEffect(interactive ? .regular.interactive() : .regular, in: Capsule(style: .continuous))
    }
}

/// The unified frosted slab behind the whole popover. One glass pass for the
/// liquid refraction, plus a subtle appearance-aware scrim so dense text stays
/// legible over busy or dark wallpapers — the balance real Liquid Glass apps use.
struct GlassPanelBackground: View {
    var radius: CGFloat = 26
    @Environment(\.colorScheme) private var scheme

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: radius, style: .continuous) }
    private var scrim: Color {
        scheme == .dark ? Color.black.opacity(0.24) : Color.white.opacity(0.30)
    }

    var body: some View {
        Color.clear
            .glassEffect(.regular, in: shape)
            .overlay(shape.fill(scrim))
            .overlay(ambientGlow)
            .overlay(
                // A single, whisper-quiet rim — top a touch brighter than bottom,
                // the way light catches a real glass edge. No hard outline.
                shape.strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.12), .white.opacity(0.02)],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 0.5
                )
            )
    }

    /// A slight ambient glow so the panel feels lit, not flat: a soft cool light
    /// from the top and a faint warm wash rising from the bottom.
    private var ambientGlow: some View {
        ZStack {
            RadialGradient(
                colors: [Color.white.opacity(scheme == .dark ? 0.09 : 0.05), .clear],
                center: UnitPoint(x: 0.5, y: -0.08), startRadius: 0, endRadius: 300
            )
            RadialGradient(
                colors: [Theme.focus.opacity(0.06), .clear],
                center: UnitPoint(x: 0.5, y: 1.08), startRadius: 0, endRadius: 260
            )
        }
        .clipShape(shape)
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
    }
}

/// A flat, layered card for content that sits *inside* a glass panel — quiet
/// elevation via fill, not another glass pass (which would muddy the stack).
struct LayeredCard<Content: View>: View {
    var level: Int = 1
    var radius: CGFloat = Theme.Radius.card
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background(Theme.fill(level), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 0.5)
            )
    }
}
