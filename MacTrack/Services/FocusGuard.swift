import AppKit

/// Watches the continuous time you spend on things you've tagged `.unproductive`
/// and, once it crosses your threshold, raises the full-screen blur with a line
/// of discipline on it.
///
/// "Continuous" is the key: the streak counts uninterrupted unproductive time and
/// resets the moment you switch to anything that isn't tagged unproductive. So
/// the nudge means "you've been on this for 20 minutes straight", not "you've
/// racked up 20 minutes across the whole day".
///
/// It's a nudge, not a jail (that's what `BlockController` is for): the overlay
/// clears on its own as soon as you leave, and "I'll get back to it" dismisses it
/// by hand, which re-arms the streak so it nudges again only after another full
/// threshold rather than nagging on every tick.
///
/// Which quote collections feed the rotation is chosen per-source in Settings and
/// read fresh each time, so checking or unchecking a box takes effect immediately.
@MainActor
final class FocusGuard: ObservableObject {

    private let overlay = NudgeOverlayController()
    private var streak: TimeInterval = 0

    /// A Test from Settings shows the blur regardless of what you're doing. While
    /// it's up we stop the per-second evaluation from closing it, so it stays
    /// until the user dismisses it by hand.
    private var isTest = false

    static let enabledKey = "focusGuard.enabled"
    static let thresholdMinutesKey = "focusGuard.thresholdMinutes"

    private var enabled: Bool {
        UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? false
    }

    private var thresholdSeconds: TimeInterval {
        let m = UserDefaults.standard.object(forKey: Self.thresholdMinutesKey) as? Double ?? 20
        return max(60, m * 60)        // never less than a minute
    }

    /// The sources the user has checked. Empty means nothing to draw from.
    var enabledSources: [QuoteSource] { QuoteSource.allCases.filter(\.isEnabled) }

    /// True when the guard could actually fire: switched on, with at least one
    /// source selected. Drives the Test button's enabled state.
    var canFire: Bool { enabled && !enabledSources.isEmpty }

    init() {
        overlay.onDismiss = { [weak self] in self?.dismiss() }
    }

    /// Called from the sampler once a second with the focused thing's tag and the
    /// real elapsed time credited this tick. Only invoked while present and not
    /// paused, so idle time never builds the streak.
    func evaluate(tag: ProductivityTag?, delta: TimeInterval) {
        if isTest { return }            // a manual test owns the screen until dismissed

        guard enabled else {
            streak = 0
            if overlay.isShowing { overlay.hide() }
            return
        }

        if tag == .unproductive {
            streak += delta
            if streak >= thresholdSeconds, !overlay.isShowing, let quote = pick() {
                overlay.show(quote: quote)
            }
        } else {
            streak = 0
            if overlay.isShowing { overlay.hide() }
        }
    }

    /// Fire the blur now to preview it. Used by the Settings Test button. Falls
    /// back to all sources if none are selected so a preview always shows.
    func test() {
        let sources = enabledSources.isEmpty ? QuoteSource.allCases : enabledSources
        guard let quote = QuoteBank.next(from: sources) else { return }
        isTest = true
        overlay.show(quote: quote)
    }

    private func pick() -> Quote? { QuoteBank.next(from: enabledSources) }

    /// Drop the overlay (button tap or test end) and re-arm the streak so the
    /// next real nudge is a full threshold away.
    private func dismiss() {
        isTest = false
        streak = 0
        overlay.hide()
    }
}
