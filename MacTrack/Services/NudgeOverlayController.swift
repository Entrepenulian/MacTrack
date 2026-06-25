import AppKit
import SwiftUI

/// The three quote-card looks the user can preview and choose between. All three
/// are text-only and monochrome; they differ in typeface pairing and weight.
enum QuoteCardStyle: String, CaseIterable, Identifiable {
    case light       // Newsreader serif + Inter — clean editorial
    case stately     // Fraunces serif + Inter — warm, larger, commanding
    case literary    // Literata italic + Inter — book-letter feel

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light:    return "Light"
        case .stately:  return "Stately"
        case .literary: return "Literary"
        }
    }

    var blurb: String {
        switch self {
        case .light:    return "Newsreader · clean editorial"
        case .stately:  return "Fraunces · warm & bold"
        case .literary: return "Literata italic · book letter"
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

// MARK: - Per-style typography

private struct CardSpec {
    var qFamily: String; var qWeight: CGFloat; var qItalic: Bool; var qSize: CGFloat
    var qWordSpacing: CGFloat; var qLineSpacing: CGFloat; var qMaxFactor: CGFloat; var qMaxCap: CGFloat
    var nFamily: String; var nWeight: CGFloat; var nSize: CGFloat; var nTracking: CGFloat
    var nUpper: Bool; var nItalic: Bool; var nTopPad: CGFloat
    var rFamily: String; var rWeight: CGFloat; var rSize: CGFloat; var rTracking: CGFloat
    var rUpper: Bool; var rItalic: Bool
}

private extension QuoteCardStyle {
    var spec: CardSpec {
        switch self {
        case .light:
            return CardSpec(
                qFamily: "Newsreader", qWeight: 460, qItalic: false, qSize: 54,
                qWordSpacing: 16, qLineSpacing: 12, qMaxFactor: 0.88, qMaxCap: 1240,
                nFamily: "Inter", nWeight: 600, nSize: 13, nTracking: 3.5, nUpper: true, nItalic: false, nTopPad: 46,
                rFamily: "Inter", rWeight: 500, rSize: 13, rTracking: 0.2, rUpper: false, rItalic: false)
        case .stately:
            return CardSpec(
                qFamily: "Fraunces", qWeight: 600, qItalic: false, qSize: 60,
                qWordSpacing: 17, qLineSpacing: 6, qMaxFactor: 0.9, qMaxCap: 1320,
                nFamily: "Inter", nWeight: 600, nSize: 14, nTracking: 4, nUpper: true, nItalic: false, nTopPad: 46,
                rFamily: "Inter", rWeight: 600, rSize: 12, rTracking: 3, rUpper: true, rItalic: false)
        case .literary:
            return CardSpec(
                qFamily: "Literata", qWeight: 500, qItalic: true, qSize: 51,
                qWordSpacing: 15, qLineSpacing: 8, qMaxFactor: 0.88, qMaxCap: 1240,
                nFamily: "Inter", nWeight: 600, nSize: 13, nTracking: 4, nUpper: true, nItalic: false, nTopPad: 48,
                rFamily: "Literata", rWeight: 500, rSize: 18, rTracking: 0, rUpper: false, rItalic: true)
        }
    }
}

// MARK: - The card

private struct NudgeOverlayView: View {
    let quote: Quote
    let style: QuoteCardStyle
    let onDismiss: () -> Void

    @State private var revealed = false
    @State private var exitShown = false

    private let base = 0.55
    private let stagger = 0.075
    private let wordDur = 0.64

    private var words: [String] { quote.text.split(separator: " ").map(String.init) }
    private var tailStart: Double { base + Double(words.count) * stagger }

    var body: some View {
        let s = style.spec
        GeometryReader { geo in
            ZStack {
                RadialGradient(
                    colors: [.black.opacity(0.52), .black.opacity(0.17), .clear],
                    center: .center, startRadius: 30, endRadius: max(geo.size.width, geo.size.height)
                )
                .ignoresSafeArea()
                .opacity(revealed ? 1 : 0)
                .animation(.easeOut(duration: 0.7), value: revealed)

                VStack(spacing: 0) {
                    FlowLayout(spacing: s.qWordSpacing, lineSpacing: s.qLineSpacing) {
                        ForEach(Array(words.enumerated()), id: \.offset) { i, word in
                            Text(word)
                                .modifier(WordReveal(revealed: revealed,
                                                     delay: base + Double(i) * stagger,
                                                     duration: wordDur))
                        }
                    }
                    .font(AppFont.custom(s.qFamily, s.qSize, weight: s.qWeight, italic: s.qItalic))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.28), radius: 26, y: 6)
                    .frame(maxWidth: min(geo.size.width * s.qMaxFactor, s.qMaxCap))

                    Text(s.nUpper ? quote.author.uppercased() : quote.author)
                        .font(AppFont.custom(s.nFamily, s.nSize, weight: s.nWeight, italic: s.nItalic))
                        .tracking(s.nTracking)
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.top, s.nTopPad)
                        .riseIn(revealed, delay: tailStart + 0.16, duration: 0.7)

                    ResumeText(spec: s, action: onDismiss)
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
}

// MARK: - Resume text (plain, no underline; appears after one click)

private struct ResumeText: View {
    let spec: CardSpec
    let action: () -> Void
    @State private var hovering = false

    private let label = "I'll get back to it"

    var body: some View {
        Text(spec.rUpper ? label.uppercased() : label)
            .font(AppFont.custom(spec.rFamily, spec.rSize, weight: spec.rWeight, italic: spec.rItalic))
            .tracking(spec.rTracking)
            .foregroundStyle(.white.opacity(hovering ? 0.92 : 0.48))
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
