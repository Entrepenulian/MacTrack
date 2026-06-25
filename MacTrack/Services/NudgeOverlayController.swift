import AppKit
import SwiftUI

/// The quote card is fixed (the "Light" look: a Newsreader serif quote in white).
/// These three cases change ONLY how the author's name is set beneath it, so the
/// user can compare attribution treatments.
enum QuoteCardStyle: String, CaseIterable, Identifiable {
    case italic       // "— Naval Ravikant" in serif italic, a printed signoff
    case smallcaps    // "Naval Ravikant" in true serif small caps
    case roman        // "Naval Ravikant" in quiet roman serif, title case

    var id: String { rawValue }

    var title: String {
        switch self {
        case .italic:    return "Italic"
        case .smallcaps: return "Small Caps"
        case .roman:     return "Roman"
        }
    }

    var blurb: String {
        switch self {
        case .italic:    return "Serif italic with an em-dash"
        case .smallcaps: return "Elegant serif small caps"
        case .roman:     return "Quiet roman, title case"
        }
    }
}

/// Owns the full-screen blur overlay that Focus Guard puts up when you've spent
/// too long on something you've tagged unproductive.
///
/// One borderless, non-activating panel per screen, placed above the menu bar
/// and over fullscreen apps via `CGShieldingWindowLevel()`. The panel uses a
/// native `NSVisualEffectView` so the desktop behind it is genuinely frosted.
@MainActor
final class NudgeOverlayController {

    private var panels: [NSPanel] = []
    private(set) var isShowing = false

    var onDismiss: (() -> Void)?

    func show(quote: Quote, style: QuoteCardStyle) {
        guard !isShowing else { return }
        isShowing = true
        for screen in NSScreen.screens {
            let panel = makePanel(on: screen, quote: quote, style: style)
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

    private func makePanel(on screen: NSScreen, quote: Quote, style: QuoteCardStyle) -> NSPanel {
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
            let host = NSHostingView(rootView: NudgeOverlayView(quote: quote, style: style) { [weak self] in
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

// MARK: - Author treatment per style

private struct AuthorSpec {
    var weight: CGFloat
    var size: CGFloat
    var italic: Bool
    var smallCaps: Bool
    var tracking: CGFloat
    var dash: Bool
    var topPad: CGFloat
    var opacity: Double
}

private extension QuoteCardStyle {
    var author: AuthorSpec {
        switch self {
        case .italic:
            return AuthorSpec(weight: 470, size: 25, italic: true, smallCaps: false,
                              tracking: 0.3, dash: true, topPad: 40, opacity: 0.62)
        case .smallcaps:
            return AuthorSpec(weight: 560, size: 19, italic: false, smallCaps: true,
                              tracking: 2.4, dash: false, topPad: 46, opacity: 0.62)
        case .roman:
            return AuthorSpec(weight: 500, size: 23, italic: false, smallCaps: false,
                              tracking: 0.4, dash: false, topPad: 44, opacity: 0.55)
        }
    }
}

// MARK: - The card (fixed "Light" quote; author varies by style)

private struct NudgeOverlayView: View {
    let quote: Quote
    let style: QuoteCardStyle
    let onDismiss: () -> Void

    @State private var revealed = false
    @State private var exitShown = false

    private let base = 0.55
    private let stagger = 0.075
    private let wordDur = 0.66

    private var words: [String] { quote.text.split(separator: " ").map(String.init) }
    private var tailStart: Double { base + Double(words.count) * stagger }

    // The serif used everywhere on the card.
    private let serif = "Newsreader"

    var body: some View {
        let a = style.author
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
                    // Fixed quote: Newsreader, light, short quotes stay on one line.
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

                    authorView(a)
                        .padding(.top, a.topPad)
                        .riseIn(revealed, delay: tailStart + 0.18, duration: 0.75)

                    ResumeText(action: onDismiss)
                        .opacity(exitShown ? 1 : 0)
                        .offset(y: exitShown ? 0 : 8)
                        .allowsHitTesting(exitShown)
                        .animation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.55), value: exitShown)
                        .padding(.top, 58)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { if !exitShown { exitShown = true } }
        .onAppear { revealed = true }
    }

    /// The name plus a small partner mark, composed differently per style so the
    /// attribution reads as a designed unit rather than a bare line of text.
    private func authorView(_ a: AuthorSpec) -> some View {
        let baseFont = AppFont.custom(serif, a.size, weight: a.weight, italic: a.italic)
        let font = a.smallCaps ? baseFont.smallCaps() : baseFont
        // The italic signoff leads with an em-dash, like a printed citation.
        let displayName = style == .italic ? "\u{2014}\u{2009}\(quote.author)" : quote.author
        let name = Text(displayName)
            .font(font)
            .tracking(a.tracking)
            .foregroundStyle(.white.opacity(a.opacity))
        let mark = Color.white.opacity(0.3)

        return Group {
            switch style {
            case .italic:
                // The em-dash on the name is its partner mark.
                name
            case .smallcaps:
                // Hairline rules flank the small-caps name on either side.
                HStack(spacing: 18) {
                    Rectangle().fill(mark).frame(width: 28, height: 1)
                    name
                    Rectangle().fill(mark).frame(width: 28, height: 1)
                }
            case .roman:
                // A small diamond centres above the roman name.
                VStack(spacing: 15) {
                    Rectangle().fill(mark).frame(width: 5, height: 5).rotationEffect(.degrees(45))
                    name
                }
            }
        }
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
