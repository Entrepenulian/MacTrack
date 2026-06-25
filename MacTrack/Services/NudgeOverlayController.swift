import AppKit
import SwiftUI

/// Owns the full-screen blur overlay that Focus Guard puts up when you've spent
/// too long on something you've tagged unproductive.
///
/// One borderless, non-activating panel per screen, placed above the menu bar
/// and over fullscreen apps via `CGShieldingWindowLevel()`. The panel uses a
/// native `NSVisualEffectView` so the desktop behind it is genuinely frosted,
/// not a fake gradient, with a SwiftUI card carrying a centred quote on top.
///
/// It never steals focus (`.nonactivatingPanel`) but it does eat clicks, so you
/// can't quietly keep scrolling behind it. The only way past is the dismiss
/// button, which calls back to Focus Guard.
@MainActor
final class NudgeOverlayController {

    private var panels: [NSPanel] = []
    private(set) var isShowing = false

    /// Called when the user taps the dismiss button.
    var onDismiss: (() -> Void)?

    func show(quote: Quote) {
        guard !isShowing else { return }
        isShowing = true

        for screen in NSScreen.screens {
            let panel = makePanel(on: screen, quote: quote)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.5
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
            panels.append(panel)
        }
    }

    func hide() {
        guard isShowing else { return }
        isShowing = false
        let closing = panels
        panels = []
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            for p in closing { p.animator().alphaValue = 0 }
        } completionHandler: {
            for p in closing { p.orderOut(nil) }
        }
    }

    private func makePanel(on screen: NSScreen, quote: Quote) -> NSPanel {
        let panel = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false

        // Native frosted backdrop.
        let blur = NSVisualEffectView(frame: screen.frame)
        blur.material = .fullScreenUI
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.autoresizingMask = [.width, .height]

        // The quote card shows only on the screen with the menu bar, so the
        // message lands once rather than mirrored across every display.
        if screen == NSScreen.main {
            let host = NSHostingView(rootView: NudgeOverlayView(quote: quote) { [weak self] in
                self?.onDismiss?()
            })
            host.frame = screen.frame
            host.autoresizingMask = [.width, .height]
            blur.addSubview(host)
        }

        panel.contentView = blur
        return panel
    }
}

// MARK: - The card

/// A quiet, editorial composition: the quote sets word by word once the blur has
/// settled, then a hairline rule, the attribution, and the way out fade up under
/// it. No header, no chrome — just the line and who said it.
///
/// The word reveal is the skill's number-pop-in pattern (per-element blurred
/// slide on a stagger), retuned slower and without the spring so it reads calm
/// and expensive rather than bouncy.
private struct NudgeOverlayView: View {
    let quote: Quote
    let onDismiss: () -> Void

    @State private var revealed = false

    // Timing. Words begin only after the backdrop has finished frosting.
    private let base = 0.5            // hold for the blur to settle
    private let stagger = 0.07        // gap between words
    private let wordDur = 0.62

    private var words: [String] {
        quote.text.split(separator: " ").map(String.init)
    }

    // When the last word lands, everything below it follows.
    private var tailStart: Double { base + Double(words.count) * stagger }

    // Warm ivory reads like ink on cream rather than stark UI white.
    private let ink = Color(red: 0.96, green: 0.935, blue: 0.875)

    var body: some View {
        ZStack {
            // A soft centre scrim keeps the words legible over any wallpaper,
            // deepest where the text sits and fading to nothing at the edges.
            RadialGradient(
                colors: [.black.opacity(0.55), .black.opacity(0.18), .clear],
                center: .center, startRadius: 30, endRadius: 880
            )
            .ignoresSafeArea()
            .opacity(revealed ? 1 : 0)
            .animation(.easeOut(duration: 0.7), value: revealed)

            VStack(spacing: 0) {
                // The oversized opening quotation mark: the classic anchor that
                // tells the eye "this is a quotation" before a word is read.
                Text("\u{201C}")
                    .font(AppFont.cormorant(168, weight: 600))
                    .foregroundStyle(ink.opacity(0.20))
                    .frame(height: 74, alignment: .top)
                    .clipped()
                    .opacity(revealed ? 1 : 0)
                    .scaleEffect(revealed ? 1 : 0.9, anchor: .bottom)
                    .blur(radius: revealed ? 0 : 5)
                    .animation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.85).delay(0.18), value: revealed)
                    .padding(.bottom, 10)

                // The line, set word by word in a printed-epigraph serif.
                FlowLayout(spacing: 15, lineSpacing: 4) {
                    ForEach(Array(words.enumerated()), id: \.offset) { i, word in
                        Text(word)
                            .modifier(WordReveal(revealed: revealed,
                                                 delay: base + Double(i) * stagger,
                                                 duration: wordDur))
                    }
                }
                .font(AppFont.cormorant(52, weight: 600))
                .foregroundStyle(ink)
                .shadow(color: .black.opacity(0.32), radius: 26, y: 7)
                .frame(maxWidth: 900)

                // The attribution, the way a printed quotation signs off.
                Text("\u{2014}\u{2009}\(quote.author)")
                    .font(AppFont.cormorant(27, weight: 500, italic: true))
                    .foregroundStyle(ink.opacity(0.6))
                    .padding(.top, 36)
                    .riseIn(revealed, delay: tailStart + 0.16, duration: 0.7)

                DismissButton(action: onDismiss, ink: ink)
                    .padding(.top, 46)
                    .riseIn(revealed, delay: tailStart + 0.3, duration: 0.7)
            }
            .padding(70)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { revealed = true }
    }
}

// MARK: - Reveal modifiers

/// One word entering: fade in while sliding up a few points and de-blurring.
/// Bounce-free easing keeps the cadence elegant.
private struct WordReveal: ViewModifier {
    let revealed: Bool
    let delay: Double
    let duration: Double

    func body(content: Content) -> some View {
        content
            .opacity(revealed ? 1 : 0)
            .blur(radius: revealed ? 0 : 7)
            .offset(y: revealed ? 0 : 16)
            .animation(.timingCurve(0.22, 1, 0.36, 1, duration: duration).delay(delay), value: revealed)
    }
}

/// A softer version of the same move for the elements below the quote.
private struct RiseIn: ViewModifier {
    let revealed: Bool
    let delay: Double
    let duration: Double

    func body(content: Content) -> some View {
        content
            .opacity(revealed ? 1 : 0)
            .offset(y: revealed ? 0 : 10)
            .animation(.timingCurve(0.22, 1, 0.36, 1, duration: duration).delay(delay), value: revealed)
    }
}

private extension View {
    func riseIn(_ revealed: Bool, delay: Double, duration: Double) -> some View {
        modifier(RiseIn(revealed: revealed, delay: delay, duration: duration))
    }
}

// MARK: - Dismiss button

/// The single way out. Quiet glass pill that lifts on hover and presses in on
/// click for tactile feedback.
private struct DismissButton: View {
    let action: () -> Void
    let ink: Color
    @State private var hovering = false
    @State private var pressed = false

    var body: some View {
        Text("I'll get back to it")
            .font(AppFont.cormorant(19, weight: 600))
            .tracking(0.3)
            .foregroundStyle(ink.opacity(hovering ? 1 : 0.82))
            .padding(.horizontal, 30)
            .padding(.vertical, 12)
            .background(ink.opacity(hovering ? 0.1 : 0), in: Capsule())
            .overlay(Capsule().strokeBorder(ink.opacity(hovering ? 0.45 : 0.26), lineWidth: 1))
            .scaleEffect(pressed ? 0.96 : 1)
            .contentShape(Capsule())
            .onHover { hovering = $0 }
            .onTapGesture { action() }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in pressed = true }
                    .onEnded { _ in pressed = false }
            )
            .animation(.easeOut(duration: 0.2), value: hovering)
            .animation(.easeOut(duration: 0.12), value: pressed)
    }
}

// MARK: - Flow layout

/// Wraps word views across lines and centres each line, so the quote breaks
/// naturally and stays symmetric. Measuring ignores opacity/blur/offset, so the
/// layout holds steady while the words animate in.
private struct FlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxW = proposal.width ?? .greatestFiniteMagnitude
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let plan = lines(sizes: sizes, maxWidth: maxW)
        return CGSize(width: proposal.width ?? plan.contentWidth, height: plan.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let plan = lines(sizes: sizes, maxWidth: bounds.width)

        var y = bounds.minY
        for line in plan.lines {
            var x = bounds.minX + (bounds.width - line.width) / 2
            for idx in line.indices {
                let s = sizes[idx]
                subviews[idx].place(
                    at: CGPoint(x: x, y: y + (line.height - s.height) / 2),
                    proposal: ProposedViewSize(s)
                )
                x += s.width + spacing
            }
            y += line.height + lineSpacing
        }
    }

    private struct Line { var indices: [Int]; var width: CGFloat; var height: CGFloat }

    private func lines(sizes: [CGSize], maxWidth: CGFloat) -> (lines: [Line], height: CGFloat, contentWidth: CGFloat) {
        var result: [Line] = []
        var current: [Int] = []
        var x: CGFloat = 0
        var lineH: CGFloat = 0
        var widest: CGFloat = 0

        func flush() {
            guard !current.isEmpty else { return }
            let w = max(0, x - spacing)
            result.append(Line(indices: current, width: w, height: lineH))
            widest = max(widest, w)
            current = []; x = 0; lineH = 0
        }

        for (i, s) in sizes.enumerated() {
            if x + s.width > maxWidth && !current.isEmpty { flush() }
            current.append(i)
            x += s.width + spacing
            lineH = max(lineH, s.height)
        }
        flush()

        let totalH = result.reduce(0) { $0 + $1.height } + lineSpacing * CGFloat(max(0, result.count - 1))
        return (result, totalH, widest)
    }
}
