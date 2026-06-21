import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var monitor: ActivityMonitor
    @EnvironmentObject var loginItem: LoginItem
    @AppStorage("idleThreshold") private var idleThreshold: Double = 120
    @AppStorage("chartStartHour") private var chartStartHour: Int = 8
    @AppStorage("chartEndHour") private var chartEndHour: Int = 22

    private let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            settingRow(
                title: "Launch at login",
                subtitle: "Start tracking when you sign in",
                control: AnyView(
                    Toggle("", isOn: Binding(
                        get: { loginItem.isEnabled },
                        set: { loginItem.set($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(Theme.focus)
                )
            )

            Divider().overlay(Theme.hairline)

            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                HStack {
                    Text("Idle after")
                        .font(.rowTitle)
                        .foregroundStyle(Theme.Ink.primary)
                    Spacer()
                    Text("\(Int(idleThreshold))s")
                        .font(.rowValue.monospacedDigit())
                        .foregroundStyle(Theme.focus)
                }
                Slider(value: $idleThreshold, in: 30...600, step: 30)
                    .tint(Theme.focus)
                    .onChange(of: idleThreshold) { _, new in monitor.setIdleThreshold(new) }
                Text("Stop counting after this long without input.")
                    .font(.rowMeta)
                    .foregroundStyle(Theme.Ink.tertiary)
            }

            Divider().overlay(Theme.hairline)

            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                Text("Chart hours")
                    .font(.rowTitle)
                    .foregroundStyle(Theme.Ink.primary)
                Stepper(value: $chartStartHour, in: 0...max(0, chartEndHour - 1)) {
                    HStack {
                        Text("Start").font(.rowMeta).foregroundStyle(Theme.Ink.secondary)
                        Spacer()
                        Text(hourLabel(chartStartHour)).font(.rowValue.monospacedDigit()).foregroundStyle(Theme.focus)
                    }
                }
                Stepper(value: $chartEndHour, in: min(23, chartStartHour + 1)...23) {
                    HStack {
                        Text("End").font(.rowMeta).foregroundStyle(Theme.Ink.secondary)
                        Spacer()
                        Text(hourLabel(chartEndHour)).font(.rowValue.monospacedDigit()).foregroundStyle(Theme.focus)
                    }
                }
                Text("The time range the usage chart spans.")
                    .font(.rowMeta)
                    .foregroundStyle(Theme.Ink.tertiary)
            }

            Divider().overlay(Theme.hairline)

            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                Text("Website tracking")
                    .font(.rowTitle)
                    .foregroundStyle(Theme.Ink.primary)
                Text("MacTrack reads the active tab's address via Automation. Your history stays on this Mac; only site icons are fetched from the web.")
                    .font(.rowMeta)
                    .foregroundStyle(Theme.Ink.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Automation Settings") {
                    Permissions.openAutomationSettings()
                }
                .buttonStyle(.plain)
                .font(.rowValue)
                .foregroundStyle(Theme.focus)
                .padding(.top, 2)
            }

            Spacer(minLength: 0)

            Text("Version \(version) · all data stored locally")
                .font(.rowMeta)
                .foregroundStyle(Theme.Ink.faint)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .onAppear { loginItem.refresh() }
    }

    private func hourLabel(_ hour: Int) -> String {
        let h12 = hour % 12 == 0 ? 12 : hour % 12
        let ap = (hour >= 12 && hour < 24) ? "PM" : "AM"
        return "\(h12) \(ap)"
    }

    private func settingRow(title: String, subtitle: String, control: AnyView) -> some View {
        HStack(spacing: Theme.Space.md) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.rowTitle).foregroundStyle(Theme.Ink.primary)
                Text(subtitle).font(.rowMeta).foregroundStyle(Theme.Ink.tertiary)
            }
            Spacer(minLength: 0)
            control
        }
    }
}
