import SwiftUI

/// A self-contained settings page: its own back/title header, then grouped cards
/// (General, Chart range, Privacy). Clean rows, hairline dividers, one accent.
struct SettingsView: View {
    @EnvironmentObject var monitor: ActivityMonitor
    @EnvironmentObject var loginItem: LoginItem
    @EnvironmentObject var filter: BlockFilterManager
    @AppStorage("idleThreshold") private var idleThreshold: Double = 120
    @AppStorage("chartStartHour") private var chartStartHour: Int = 8
    @AppStorage("chartEndHour") private var chartEndHour: Int = 22
    @AppStorage("wakeHour") private var wakeHour: Int = 8
    var onBack: () -> Void

    private let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            header

            section("General") {
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
                        PremiumSlider(value: $idleThreshold, range: 30...600, step: 30, accent: Theme.settingsAccent)
                            .onChange(of: idleThreshold) { _, v in monitor.setIdleThreshold(v) }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 11)
                }
            }

            section("Sleep") {
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

            section("Chart range") {
                card {
                    stepperRow("Start", value: $chartStartHour, range: 0...max(0, chartEndHour - 1))
                    rowDivider
                    stepperRow("End", value: $chartEndHour, range: min(23, chartStartHour + 1)...23)
                }
            }

            section("Privacy") {
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

            section("Blocking") {
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

            Text("MacTrack \(version) · all data stays on this Mac")
                .font(.rowMeta).foregroundStyle(Theme.Ink.faint)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .onAppear { loginItem.refresh(); filter.refresh() }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            GlassIconButton(systemName: "chevron.left", size: 26, help: "Back", action: onBack)
            Text("Settings")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.Ink.primary)
            Spacer()
        }
    }

    // MARK: Building blocks

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: title)
            content()
        }
    }

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
                // Accent fill is value-proportional (full at max), so the knob sits
                // *inside* the orange with an equal margin on its right — the fill
                // edge stays hidden under the knob for in-between values.
                Capsule().fill(accent)
                    .frame(width: max(0, frac * w))
                // Tick dots sit exactly on the snap positions (where the knob lands).
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
