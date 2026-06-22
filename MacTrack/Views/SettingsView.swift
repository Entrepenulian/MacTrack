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
                        Slider(value: $idleThreshold, in: 30...600, step: 30)
                            .controlSize(.small).tint(Theme.settingsAccent)
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
        HStack {
            Text(title).font(.rowTitle).foregroundStyle(Theme.Ink.primary)
            Spacer()
            Text(hourLabel(value.wrappedValue)).font(.rowValue.monospacedDigit()).foregroundStyle(Theme.settingsAccent)
            Stepper("", value: value, in: range).labelsHidden()
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
    }

    private func hourLabel(_ hour: Int) -> String {
        let h12 = hour % 12 == 0 ? 12 : hour % 12
        let ap = (hour >= 12 && hour < 24) ? "PM" : "AM"
        return "\(h12) \(ap)"
    }
}
