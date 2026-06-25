import AppKit
import SwiftUI

/// Owns the full-screen blur overlay that Focus Guard puts up when you've spent
/// too long on something you've tagged unproductive.
///
/// One borderless, non-activating panel per screen, placed above the menu bar
/// and over fullscreen apps via `CGShieldingWindowLevel()`. The panel uses a
/// native `NSVisualEffectView` so the desktop behind it is genuinely frosted.
///
/// The card is text only: a Newsreader serif quote in white that sets word by
/// word, an italic em-dash signoff for the author, and a quiet link that appears
/// only after one click.
@MainActor
final class NudgeOverlayController {

    private var panels: [NSPanel] = []
    private(set) var isShowing = false

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
            backing: .buffered, defer: false, screen: screen
        )
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false

        let blur = NSVisualEffectView(frame: screen.frame)
        blur.material = .fullScreenUI
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.autoresizingMask = [.width, .height]

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

private struct NudgeOverlayView: View {
    let quote: Quote
    let onDismiss: () -> Void

    @State private var revealed = false
    @State private var exitShown = false

    private let base = 0.55
    private let stagger = 0.075
    private let wordDur = 0.66
    private let serif = "Newsreader"

    private var words: [String] { quote.text.split(separator: " ").map(String.init) }
    private var tailStart: Double { base + Double(words.count) * stagger }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                RadialGradient(
                    colors: [.black.opacity(0.5), .black.opacity(0.16), .clear],
                    center: .center, startRadius: 40, endRadius: max(geo.size.width, geo.size.height)
                )
                .ignoresSafeArea()
                .opacity(revealed ? 1 : 0)
                .animation(.easeOut(duration: 0.7), value: revealed)

                VStack(spacing: 0) {
                    // The quote: Newsreader, light. Short quotes stay on one line.
                    FlowLayout(spacing: 16, lineSpacing: 12) {
                        ForEach(Array(words.enumerated()), id: \.offset) { i, word in
                            Text(word)
                                .modifier(WordReveal(revealed: revealed,
                                                     delay: base + Double(i) * stagger,
                                                     duration: wordDur))
                        }
                    }
                    .font(AppFont.custom(serif, 54, weight: 460))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.28), radius: 26, y: 6)
                    .frame(maxWidth: min(geo.size.width * 0.88, 1240))

                    // Author: an italic em-dash signoff.
                    Text("\u{2014}\u{2009}\(quote.author)")
                        .font(AppFont.custom(serif, 25, weight: 470, italic: true))
                        .tracking(0.3)
                        .foregroundStyle(.white.opacity(0.62))
                        .padding(.top, 40)
                        .riseIn(revealed, delay: tailStart + 0.18, duration: 0.75)
                }
                .frame(width: geo.size.width, height: geo.size.height)

                // The link sits low on the screen, centred, and only after a click.
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    ResumeText(action: onDismiss)
                        .opacity(exitShown ? 1 : 0)
                        .offset(y: exitShown ? 0 : 8)
                        .allowsHitTesting(exitShown)
                        .animation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.55), value: exitShown)
                        .padding(.bottom, 40)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { if !exitShown { exitShown = true } }
        .onAppear { revealed = true }
    }
}

// MARK: - Resume text (plain; appears after one click)

private struct ResumeText: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Text("I'll get back to it")
            .font(AppFont.custom("Inter", 13, weight: 500))
            .tracking(0.2)
            .foregroundStyle(.white.opacity(hovering ? 0.9 : 0.48))
            .padding(8)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .onTapGesture { action() }
            .animation(.easeOut(duration: 0.2), value: hovering)
    }
}

// MARK: - Reveal modifiers

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

// MARK: - Flow layout (wraps + centres each line)

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
                let sz = sizes[idx]
                subviews[idx].place(
                    at: CGPoint(x: x, y: y + (line.height - sz.height) / 2),
                    proposal: ProposedViewSize(sz)
                )
                x += sz.width + spacing
            }
            y += line.height + lineSpacing
        }
    }

    private struct Line { var indices: [Int]; var width: CGFloat; var height: CGFloat }

    private func lines(sizes: [CGSize], maxWidth: CGFloat) -> (lines: [Line], height: CGFloat, contentWidth: CGFloat) {
        var result: [Line] = []
        var current: [Int] = []
        var x: CGFloat = 0, lineH: CGFloat = 0, widest: CGFloat = 0
        func flush() {
            guard !current.isEmpty else { return }
            let w = max(0, x - spacing)
            result.append(Line(indices: current, width: w, height: lineH))
            widest = max(widest, w)
            current = []; x = 0; lineH = 0
        }
        for (i, sz) in sizes.enumerated() {
            if x + sz.width > maxWidth && !current.isEmpty { flush() }
            current.append(i); x += sz.width + spacing; lineH = max(lineH, sz.height)
        }
        flush()
        let totalH = result.reduce(0) { $0 + $1.height } + lineSpacing * CGFloat(max(0, result.count - 1))
        return (result, totalH, widest)
    }
}
