import SwiftUI

struct HeaderView: View {
    @EnvironmentObject var store: UsageStore
    @EnvironmentObject var monitor: ActivityMonitor
    @Binding var showSettings: Bool

    /// The thing currently in focus — a website if you're on one, otherwise the
    /// app. The big readout reflects *this*, not the whole-day total.
    private var focusLabel: String {
        if let domain = monitor.currentDomain { return domain }
        if let name = monitor.currentAppName { return name }
        return "Today"
    }

    /// Today's accumulated time for the current focus (the website, or the app).
    private var focusSeconds: Double {
        store.focusSeconds(domain: monitor.currentDomain, bundleID: monitor.currentBundleID)
    }

    var body: some View {
        if showSettings {
            HStack(alignment: .center) {
                SectionLabel(text: "Settings")
                Spacer()
                GlassIconButton(systemName: "chevron.left", size: 26, help: "Back") {
                    withAnimation(.calmSlow) { showSettings = false }
                }
            }
        } else {
            hero
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Controls sit on the same line as the focus label — no wordmark, no
            // status dot. When paused, the label says so; otherwise it names what
            // you're looking at. Liveness is implicit in the number counting up.
            HStack(alignment: .center) {
                SectionLabel(text: monitor.isPaused ? "Paused" : focusLabel)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: Theme.Space.sm)
                GlassIconButton(systemName: monitor.isPaused ? "play.fill" : "pause.fill",
                                size: 26,
                                help: monitor.isPaused ? "Resume tracking" : "Pause tracking") {
                    monitor.setPaused(!monitor.isPaused)
                }
                GlassIconButton(systemName: "gearshape", size: 26, help: "Settings") {
                    withAnimation(.calmSlow) { showSettings = true }
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                ForEach(Array(Format.readoutParts(focusSeconds).enumerated()), id: \.offset) { _, part in
                    Text(part.value)
                        .font(.system(size: 34, weight: .semibold).monospacedDigit())
                        .foregroundStyle(monitor.isPaused ? Theme.Ink.tertiary : Theme.Ink.primary)
                        .contentTransition(.numericText())
                    Text(part.unit)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Theme.Ink.faint)
                        .padding(.trailing, 4)
                }
            }
            .lineLimit(1)
            // Seconds (and minutes when they roll) flip in with the native numeric
            // transition; switching apps/sites flips to that focus's running total.
            .animation(.smooth(duration: 0.3), value: Int(focusSeconds))
            .animation(.calm, value: monitor.isPaused)
        }
    }
}
