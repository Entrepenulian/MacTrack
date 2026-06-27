import SwiftUI

struct HeaderView: View {
    @EnvironmentObject var store: UsageStore
    @EnvironmentObject var monitor: ActivityMonitor
    @Binding var showSettings: Bool
    @Binding var showOverview: Bool
    /// The day the popover is showing. Today → live focus; a past day → that day's
    /// date and total tracked time, with a "Today" button to return.
    var viewDay: String = DayKey.today
    var onReturnToToday: () -> Void = {}
    /// When a detail is open, the hero mirrors what it's showing (e.g. the X "All"
    /// total) instead of the live focus.
    var overrideLabel: String? = nil
    var overrideSeconds: Double? = nil
    @AppStorage("wakeHour") private var wakeHour: Int = 8

    private var isToday: Bool { viewDay == DayKey.today }

    /// The thing currently in focus — a website if you're on one, otherwise the
    /// app. The big readout reflects *this*, not the whole-day total.
    private var focusLabel: String {
        if let domain = monitor.currentDomain { return SiteKey.display(domain) }
        if let name = monitor.currentAppName { return name }
        return "Today"
    }

    private var focusSeconds: Double {
        store.focusSeconds(domain: monitor.currentDomain, bundleID: monitor.currentBundleID)
    }

    /// A past day's total tracked time (its three productivity buckets summed).
    private var dayTotalSeconds: Double {
        let s = store.productivitySplit(for: viewDay)
        return s.productive + s.unproductive + s.other
    }

    /// What the big number shows: an open detail's total, else live focus today, or
    /// the day's total in the past.
    private var readoutSeconds: Double { overrideSeconds ?? (isToday ? focusSeconds : dayTotalSeconds) }
    private var dimmed: Bool { isToday && (monitor.isPaused || monitor.isSleeping) }

    private var headerLabel: String {
        if let overrideLabel { return overrideLabel }
        if !isToday { return Self.dateLabel(viewDay) }
        if monitor.isSleeping { return "Asleep until \(hourLabel(wakeHour))" }
        if monitor.isPaused { return "Paused" }
        return focusLabel
    }

    private func hourLabel(_ hour: Int) -> String {
        let h12 = hour % 12 == 0 ? 12 : hour % 12
        let ap = (hour >= 12 && hour < 24) ? "PM" : "AM"
        return "\(h12) \(ap)"
    }

    var body: some View { hero }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Controls share the focus line. When viewing a past day the label
            // becomes that day's date, the pause control gives way to a "Today"
            // button, and the number below shows that day's total.
            HStack(alignment: .center, spacing: 6) {
                SectionLabel(text: headerLabel)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .contentTransition(.opacity)
                Spacer(minLength: Theme.Space.sm)

                if !isToday {
                    Button(action: onReturnToToday) {
                        Text("Today")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.settingsAccent)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Theme.fill(1), in: Capsule())
                            .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .help("Back to today")
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }

                GlassIconButton(systemName: showOverview ? "chart.pie.fill" : "chart.pie",
                                size: 26,
                                help: showOverview ? "Show details" : "Show productivity") {
                    // Toggling the view is "going home" — always snap back to today.
                    onReturnToToday()
                    showOverview.toggle()
                }
                if isToday {
                    GlassIconButton(systemName: monitor.isPaused ? "play.fill" : "pause.fill",
                                    size: 26,
                                    help: monitor.isPaused ? "Resume tracking" : "Pause tracking") {
                        monitor.setPaused(!monitor.isPaused)
                    }
                }
                GlassIconButton(systemName: "gearshape", size: 26, help: "Settings") {
                    showSettings = true
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                ForEach(Array(Format.readoutParts(readoutSeconds).enumerated()), id: \.offset) { _, part in
                    Text(part.value)
                        .font(.system(size: 34, weight: .semibold).monospacedDigit())
                        .foregroundStyle(dimmed ? Theme.Ink.tertiary : Theme.Ink.primary)
                        .contentTransition(.numericText())
                    Text(part.unit)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Theme.Ink.faint)
                        .padding(.trailing, 4)
                }
            }
            .lineLimit(1)
            // Seconds flip in with the native numeric transition; switching days
            // flips to that day's total.
            .animation(.smooth(duration: 0.3), value: Int(readoutSeconds))
            .animation(.calm, value: monitor.isPaused)
            .animation(.calm, value: monitor.isSleeping)
        }
        .animation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.4), value: isToday)
    }

    // MARK: Date label

    private static let keyParser: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
    private static let dayOut: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f
    }()
    /// "2026-06-21" → "Sun, Jun 21".
    static func dateLabel(_ key: String) -> String {
        guard let d = keyParser.date(from: key) else { return key }
        return dayOut.string(from: d)
    }
}
