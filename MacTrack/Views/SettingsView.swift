import SwiftUI

/// Settings in two levels: a **home** that lists the categories, and a **detail**
/// for each one with just that group's controls — so no single screen runs off the
/// bottom. Tapping the gear lands on the home; each category pushes in and back.
struct SettingsView: View {
    @EnvironmentObject var monitor: ActivityMonitor
    @EnvironmentObject var loginItem: LoginItem
    @EnvironmentObject var filter: BlockFilterManager
    @EnvironmentObject var focusGuard: FocusGuard
    @AppStorage("idleThreshold") private var idleThreshold: Double = 120
    @AppStorage("chartStartHour") private var chartStartHour: Int = 8
    @AppStorage("chartEndHour") private var chartEndHour: Int = 22
    @AppStorage("wakeHour") private var wakeHour: Int = 8

    // Focus Guard: the smart quote blur.
    @AppStorage("focusGuard.enabled") private var fgEnabled = false
    @AppStorage("focusGuard.thresholdMinutes") private var fgThreshold: Double = 20
    @AppStorage("focusGuard.source.wikiquote") private var srcWikiquote = true
    @AppStorage("focusGuard.source.stoic") private var srcStoic = true
    @AppStorage("focusGuard.source.dwyl") private var srcDwyl = true
    @AppStorage("focusGuard.source.entrepreneur") private var srcEntrepreneur = true
    @AppStorage("focusGuard.source.motivation") private var srcMotivation = true
    @AppStorage("focusGuard.source.tate") private var srcTate = true
    @AppStorage("focusGuard.source.naval") private var srcNaval = true

    var onBack: () -> Void

    /// Navigation: nil shows the settings home (category list); a route shows that
    /// one category's page.
    @State private var route: Route? = nil

    enum Route: String, CaseIterable, Identifiable {
        case general, sleep, focusGuard, chart, tracking, blocking
        var id: String { rawValue }
        var title: String {
            switch self {
            case .general: "General"
            case .sleep: "Good Night"
            case .focusGuard: "Focus Guard"
            case .chart: "Chart"
            case .tracking: "Website Tracking"
            case .blocking: "Blocking"
            }
        }
        var icon: String {
            switch self {
            case .general: "gearshape.fill"
            case .sleep: "moon.stars.fill"
            case .focusGuard: "sparkles"
            case .chart: "chart.xyaxis.line"
            case .tracking: "globe"
            case .blocking: "hand.raised.fill"
            }
        }
        var summary: String {
            switch self {
            case .general: "Launch at login · idle timeout"
            case .sleep: "Pause overnight · wake time"
            case .focusGuard: "Quote blur on unproductive time"
            case .chart: "Daily chart hours"
            case .tracking: "Automation permission · privacy"
            case .blocking: "System-level content filter"
            }
        }
    }

    /// Pairs each source with its persisted toggle so the list and the Test
    /// button's enabled state both react to a change here.
    private var sourceBindings: [(QuoteSource, Binding<Bool>)] {
        [(.wikiquote, $srcWikiquote), (.stoic, $srcStoic), (.dwyl, $srcDwyl),
         (.entrepreneur, $srcEntrepreneur), (.motivation, $srcMotivation),
         (.tate, $srcTate), (.naval, $srcNaval)]
    }

    private var selectedCount: Int { sourceBindings.filter { $0.1.wrappedValue }.count }

    private let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"

    var body: some View {
        Group {
            if let route {
                detail(route)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(x: 18)),
                                            removal: .opacity.combined(with: .offset(x: 18))))
            } else {
                home
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(x: -12)),
                                            removal: .opacity.combined(with: .offset(x: -12))))
            }
        }
        .animation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.3), value: route)
        // Consistent breathing room below the last card on every settings page.
        .padding(.bottom, 10)
        .onAppear { loginItem.refresh(); filter.refresh() }
    }

    // MARK: Settings home (the category list)

    private var home: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            header
            LayeredCard(level: 1) {
                VStack(spacing: 0) {
                    ForEach(Array(Route.allCases.enumerated()), id: \.element) { i, r in
                        if i > 0 { rowDivider.padding(.leading, 54) }
                        SettingsHomeRow(route: r) { open(r) }
                    }
                }
            }
            versionFooter
        }
    }

    // MARK: Section detail

    private func detail(_ r: Route) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            detailHeader(r)
            switch r {
            case .general:    generalCard
            case .sleep:      sleepCard
            case .focusGuard: focusGuardCard
            case .chart:      chartCard
            case .tracking:   trackingCard
            case .blocking:   blockingCard
            }
        }
    }

    private func open(_ r: Route?) {
        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.3)) { route = r }
    }

    // MARK: Section cards

    private var generalCard: some View {
        card {
            row {
                labelBlock("Launch at login", "Start tracking when you sign in")
                Spacer(minLength: Theme.Space.sm)
                Toggle("", isOn: Binding(get: { loginItem.isEnabled }, set: { loginItem.set($0) }))
                    .labelsHidden().toggleStyle(.switch).tint(Theme.settingsAccent)
            }
            rowDivider
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("Idle timeout").font(.rowTitle).foregroundStyle(Theme.Ink.primary)
                    Spacer()
                    Text("\(Int(idleThreshold))s")
                        .font(.rowValue.monospacedDigit()).foregroundStyle(Theme.settingsAccent)
                }
                PremiumSlider(value: $idleThreshold, range: 60...600, step: 60, accent: Theme.settingsAccent)
                    .onChange(of: idleThreshold) { _, v in monitor.setIdleThreshold(v) }
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
        }
    }

    private var sleepCard: some View {
        card {
            row {
                labelBlock(
                    monitor.isSleeping ? "Asleep until \(hourLabel(wakeHour))" : "Good night",
                    monitor.isSleeping ? "Tracking is off for the night" : "Stop tracking until your wake time"
                )
                Spacer(minLength: Theme.Space.sm)
                Button(monitor.isSleeping ? "Wake now" : "Sleep") {
                    monitor.sleepForNight(wakeHour: wakeHour)
                }
                .buttonStyle(.plain).font(.rowValue).foregroundStyle(Theme.settingsAccent)
            }
            rowDivider
            stepperRow("Wake time", value: $wakeHour, range: 0...23)
        }
    }

    private var chartCard: some View {
        card {
            stepperRow("Start", value: $chartStartHour, range: 0...max(0, chartEndHour - 1))
            rowDivider
            stepperRow("End", value: $chartEndHour, range: min(23, chartStartHour + 1)...23)
        }
    }

    private var trackingCard: some View {
        card {
            VStack(alignment: .leading, spacing: 7) {
                Text("Website tracking").font(.rowTitle).foregroundStyle(Theme.Ink.primary)
                Text("MacTrack reads the active tab's address via Automation. Your history stays on this Mac; only site icons are fetched from the web.")
                    .font(.rowMeta).foregroundStyle(Theme.Ink.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Automation Settings") { Permissions.openAutomationSettings() }
                    .buttonStyle(.plain).font(.rowValue).foregroundStyle(Theme.settingsAccent).padding(.top, 3)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
        }
    }

    private var blockingCard: some View {
        card {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("System-level blocking").font(.rowTitle).foregroundStyle(Theme.Ink.primary)
                    Spacer()
                    Text(filter.statusText).font(.rowMeta).foregroundStyle(Theme.Ink.tertiary)
                }
                Text("A DoH-proof system filter that keeps blocking even if MacTrack quits. Needs a one-time approval in System Settings.")
                    .font(.rowMeta).foregroundStyle(Theme.Ink.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 16) {
                    Button("Enable") { filter.enable() }
                        .buttonStyle(.plain).font(.rowValue)
                        .foregroundStyle(Theme.settingsAccent).disabled(filter.isBusy)
                    Button("Turn off") { filter.disable() }
                        .buttonStyle(.plain).font(.rowValue)
                        .foregroundStyle(Theme.Ink.secondary)
                }
                .padding(.top, 3)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
        }
    }

    private var focusGuardCard: some View {
        card {
            // Master switch.
            row {
                labelBlock("Smart quote reminders",
                           "Blur the screen with a quote when you linger on unproductive apps")
                Spacer(minLength: Theme.Space.sm)
                Toggle("", isOn: $fgEnabled.animation(.easeInOut(duration: 0.28)))
                    .labelsHidden().toggleStyle(.switch).tint(Theme.settingsAccent)
            }

            if fgEnabled {
                rowDivider

                // How long is "too long".
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text("Nudge after").font(.rowTitle).foregroundStyle(Theme.Ink.primary)
                        Spacer()
                        Text("\(Int(fgThreshold)) min")
                            .font(.rowValue.monospacedDigit()).foregroundStyle(Theme.settingsAccent)
                    }
                    PremiumSlider(value: $fgThreshold, range: 5...60, step: 5, accent: Theme.settingsAccent)
                }
                .padding(.horizontal, 14).padding(.vertical, 11)

                rowDivider

                HStack {
                    Text("Quote sources").font(.rowTitle).foregroundStyle(Theme.Ink.primary)
                    Spacer()
                    Text("\(selectedCount) of \(sourceBindings.count)")
                        .font(.rowMeta.monospacedDigit()).foregroundStyle(Theme.Ink.tertiary)
                }
                .padding(.horizontal, 14).padding(.top, 11).padding(.bottom, 4)

                VStack(spacing: 0) {
                    ForEach(Array(sourceBindings.enumerated()), id: \.element.0) { idx, pair in
                        if idx > 0 { rowDivider.padding(.leading, 54) }
                        SourceRow(source: pair.0, isOn: pair.1, accent: Theme.settingsAccent)
                    }
                }

                rowDivider

                // Preview the blur with a random quote from the selection.
                row {
                    labelBlock("Preview", "Play the blur with a random quote you've selected")
                    Spacer(minLength: Theme.Space.sm)
                    TestButton(title: "Test") { focusGuard.test() }
                }
            }
        }
        .animation(.easeInOut(duration: 0.28), value: fgEnabled)
    }

    private var versionFooter: some View {
        Text("MacTrack \(version) · all data stays on this Mac")
            .font(.rowMeta).foregroundStyle(Theme.Ink.faint)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 2)
    }

    // MARK: Headers

    private var header: some View {
        HStack(spacing: 10) {
            GlassIconButton(systemName: "chevron.left", size: 26, help: "Back", action: onBack)
            Text("Settings")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.Ink.primary)
            Spacer()
        }
    }

    private func detailHeader(_ r: Route) -> some View {
        HStack(spacing: 9) {
            GlassIconButton(systemName: "chevron.left", size: 26, help: "Settings") { open(nil) }
            Image(systemName: r.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.settingsAccent)
            Text(r.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.Ink.primary)
            Spacer()
        }
    }

    // MARK: Building blocks

    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        LayeredCard(level: 1) { VStack(spacing: 0) { content() } }
    }

    private var rowDivider: some View {
        Rectangle().fill(Theme.hairline).frame(height: 0.5)
    }

    private func row<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 0) { content() }
            .padding(.horizontal, 14).padding(.vertical, 11)
    }

    private func labelBlock(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.rowTitle).foregroundStyle(Theme.Ink.primary)
            Text(subtitle).font(.rowMeta).foregroundStyle(Theme.Ink.tertiary)
        }
    }

    private func stepperRow(_ title: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        HStack(spacing: 10) {
            Text(title).font(.rowTitle).foregroundStyle(Theme.Ink.primary)
            Spacer()
            Text(hourLabel(value.wrappedValue)).font(.rowValue.monospacedDigit()).foregroundStyle(Theme.settingsAccent)
            PremiumStepper(value: value, range: range, accent: Theme.settingsAccent)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
    }

    private func hourLabel(_ hour: Int) -> String {
        let h12 = hour % 12 == 0 ? 12 : hour % 12
        let ap = (hour >= 12 && hour < 24) ? "PM" : "AM"
        return "\(h12) \(ap)"
    }
}

// MARK: - Settings home row

/// One category on the settings home: a tinted icon chip, its name and a one-line
/// summary, and a chevron — the whole row is the hit target and lifts on hover.
private struct SettingsHomeRow: View {
    let route: SettingsView.Route
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: route.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.settingsAccent)
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Theme.settingsAccent.opacity(0.12))
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(route.title).font(.rowTitle).foregroundStyle(Theme.Ink.primary)
                    Text(route.summary).font(.rowMeta).foregroundStyle(Theme.Ink.tertiary)
                        .lineLimit(1).truncationMode(.tail)
                }
                Spacer(minLength: Theme.Space.sm)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(hovering ? Theme.Ink.secondary : Theme.Ink.faint)
            }
            .padding(.horizontal, 12)
            .frame(height: 54)
            .background(Color.primary.opacity(hovering ? 0.05 : 0))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hovering = h } }
        .pointerStyle(.link)
    }
}

/// A compact custom stepper — a rounded pill with − / + buttons that tint to the
/// accent on hover. Replaces the native (clunky) Stepper.
private struct PremiumStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var accent: Color = Theme.focus

    var body: some View {
        HStack(spacing: 0) {
            StepperButton(symbol: "minus", enabled: value > range.lowerBound, accent: accent) {
                if value > range.lowerBound { value -= 1 }
            }
            Rectangle().fill(Theme.hairline).frame(width: 0.5, height: 14)
            StepperButton(symbol: "plus", enabled: value < range.upperBound, accent: accent) {
                if value < range.upperBound { value += 1 }
            }
        }
        .background(Theme.fill(1), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.5))
    }
}

private struct StepperButton: View {
    let symbol: String
    let enabled: Bool
    let accent: Color
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(!enabled ? Theme.Ink.faint : (hovering ? accent : Theme.Ink.secondary))
                .frame(width: 32, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { hovering = $0 }
    }
}

/// A normal fill-left slider: the accent fills only up to the knob, the rest is a
/// neutral track. Tick dots mark every step and the knob snaps to each one — it
/// can't land between dots.
private struct PremiumSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var accent: Color = Theme.focus

    private let trackHeight: CGFloat = 28
    private let knobW: CGFloat = 30
    private let knobH: CGFloat = 22

    private var dotCount: Int {
        guard step > 0 else { return 2 }
        return max(2, Int(((range.upperBound - range.lowerBound) / step).rounded()) + 1)
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let span = range.upperBound - range.lowerBound
            let frac = span > 0 ? min(max((value - range.lowerBound) / span, 0), 1) : 0
            // The knob keeps the same margin from the left/right ends as it has from
            // the top/bottom, so at the extremes it's never flush against the edge.
            let inset = (trackHeight - knobH) / 2
            let travel = w - knobW - inset * 2
            let knobX = inset + frac * travel               // knob leading-edge offset

            ZStack(alignment: .leading) {
                Capsule().fill(Theme.fill(2))               // neutral (unfilled) track
                // Accent fill always extends one inset past the knob's trailing edge, so
                // the knob keeps an equal orange margin on every side at any position
                // (and the fill reaches full width exactly at max).
                Capsule().fill(accent)
                    .frame(width: min(w, knobX + knobW + inset))
                // Tick dots on the snap positions, drawn on top so they show on both the
                // filled (orange) and unfilled parts.
                ForEach(0..<dotCount, id: \.self) { i in
                    let cx = inset + knobW / 2 + (Double(i) / Double(dotCount - 1)) * travel
                    Circle().fill(Color.white.opacity(0.33)).frame(width: 3, height: 3)
                        .position(x: cx, y: trackHeight / 2)
                }
                Capsule()
                    .fill(.white)
                    .frame(width: knobW, height: knobH)
                    .shadow(color: .black.opacity(0.22), radius: 2.5, y: 1)
                    .offset(x: knobX)
            }
            .frame(height: trackHeight)
            .contentShape(Capsule())
            .animation(.snappy(duration: 0.14), value: value)   // crisp snap between dots
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { g in
                    let f = min(max((g.location.x - inset - knobW / 2) / travel, 0), 1)
                    let raw = range.lowerBound + f * span
                    let stepped = step > 0 ? (raw / step).rounded() * step : raw
                    value = min(max(stepped, range.lowerBound), range.upperBound)
                }
            )
        }
        .frame(height: trackHeight)
    }
}

// MARK: - Focus Guard rows

/// One quote collection in the Focus Guard list: an icon chip, its name and
/// credit, and a checkbox. The whole row is the hit target, and the icon picks
/// up the accent when the source is on so the checked state reads at a glance.
private struct SourceRow: View {
    let source: QuoteSource
    @Binding var isOn: Bool
    let accent: Color
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: source.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isOn ? accent : Theme.Ink.tertiary)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(isOn ? accent.opacity(0.12) : Theme.fill(2))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(source.title).font(.rowTitle).foregroundStyle(Theme.Ink.primary)
                Text(source.subtitle).font(.rowMeta).foregroundStyle(Theme.Ink.tertiary)
                    .lineLimit(1).truncationMode(.tail)
            }

            Spacer(minLength: Theme.Space.sm)

            Checkbox(isOn: isOn, accent: accent)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .frame(minHeight: 46)
        .background(hovering ? Theme.fill(2).opacity(0.55) : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { isOn.toggle() } }
    }
}

/// A rounded-square checkbox. The tick scales and fades in from small (0.25 ->
/// 1) so toggling has a little life, matching the rest of the panel's restraint.
private struct Checkbox: View {
    let isOn: Bool
    let accent: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isOn ? accent : Color.clear)
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(isOn ? accent : Theme.Ink.faint, lineWidth: 1.5)
            if isOn {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .transition(.scale(scale: 0.25).combined(with: .opacity))
            }
        }
        .frame(width: 20, height: 20)
    }
}

/// The preview trigger. A quiet accent pill that fills on hover and presses in
/// on click.
private struct TestButton: View {
    let title: String
    let action: () -> Void
    @State private var hovering = false
    @State private var pressed = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "play.fill")
                .font(.system(size: 9, weight: .semibold))
            Text(title).font(.rowValue)
        }
        .foregroundStyle(hovering ? Color.white : Theme.settingsAccent)
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(Capsule().fill(hovering ? Theme.settingsAccent : Theme.settingsAccent.opacity(0.12)))
        .overlay(Capsule().strokeBorder(Theme.settingsAccent.opacity(0.3)))
        .scaleEffect(pressed ? 0.96 : 1)
        .frame(minHeight: 40)
        .contentShape(Capsule())
        .onHover { hovering = $0 }
        .onTapGesture { action() }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in pressed = false }
        )
        .animation(.easeOut(duration: 0.16), value: hovering)
        .animation(.easeOut(duration: 0.12), value: pressed)
    }
}
