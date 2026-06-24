import SwiftUI

/// The menu-bar popover — the whole app. A clean vertical rhythm: header, hero
/// total, then the ranked Apps / Websites list. Monochrome with one gold accent
/// for the live state. Sections are separated by hairlines, not noise.
struct MenuRootView: View {
    @EnvironmentObject var store: UsageStore
    @EnvironmentObject var monitor: ActivityMonitor
    @EnvironmentObject var blocks: BlockController

    @State private var scope: UsageScope = {
        switch ProcessInfo.processInfo.environment["MACTRACK_SCOPE"] {
        case "websites": return .websites
        case "all": return .all
        default: return .apps
        }
    }()
    @State private var showSettings = ProcessInfo.processInfo.environment["MACTRACK_SETTINGS"] != nil
    /// The day the popover is showing. Defaults to today; tapping a past day in the
    /// activity grid switches every section — donut, list, chart — to that day.
    @State private var viewDay: String = DayKey.today
    @AppStorage("showOverview") private var showOverview = false
    @AppStorage("idleThreshold") private var idleThreshold: Double = 120
    @AppStorage("chartStartHour") private var chartStartHour: Int = 8
    @AppStorage("chartEndHour") private var chartEndHour: Int = 22

    private var isViewingToday: Bool { viewDay == DayKey.today }
    private var appEntries: [UsageEntry] { store.appEntries(for: viewDay) }
    private var siteEntries: [UsageEntry] { store.siteEntries(for: viewDay) }
    private var entries: [UsageEntry] {
        // The live "site you're on now" only applies to today.
        let live = isViewingToday ? monitor.currentDomain : nil
        switch scope {
        case .apps: return appEntries
        // Websites hides sub-minute visits, but always shows the site you're on now.
        case .websites: return store.siteEntries(for: viewDay, minSeconds: 60, alwaysInclude: live)
        case .all: return store.allEntries(for: viewDay, currentDomain: live)
        }
    }

    private let dayCurve: Animation = .timingCurve(0.22, 1, 0.36, 1, duration: 0.4)
    /// Switch to a day's data (or back to today if its square is tapped again).
    private func selectDay(_ day: String) {
        withAnimation(dayCurve) { viewDay = (viewDay == day) ? DayKey.today : day }
    }
    private func returnToToday() { withAnimation(dayCurve) { viewDay = DayKey.today } }

    var body: some View {
        Group {
            if showSettings {
                SettingsView(onBack: { showSettings = false })
            } else {
                mainContent
            }
        }
        .padding(18)
        .frame(width: 340)
        .background(GlassPanelBackground())
        .background(WindowAccessor())
        .onAppear { monitor.setIdleThreshold(idleThreshold) }
    }

    private var mainContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HeaderView(showSettings: $showSettings, showOverview: $showOverview,
                       viewDay: viewDay, onReturnToToday: returnToToday)

            // Active-block countdowns belong to "right now" on the details view —
            // hide them on the productivity overview and when looking back at a
            // past day.
            if !showOverview && isViewingToday && !blocks.activeBlocks.isEmpty {
                blockBanner
            }

            if showOverview {
                let split = store.productivitySplit(for: viewDay)
                ProductivityDonut(productive: split.productive,
                                  unproductive: split.unproductive,
                                  other: split.other,
                                  hasTags: store.hasAnyTags,
                                  day: viewDay,
                                  selectedDay: isViewingToday ? nil : viewDay,
                                  onSelectDay: selectDay)
                    .padding(.top, 16)
                    .transition(.opacity)
            } else {
                detailsBody
                    .transition(.opacity)
            }
        }
        .animation(.calm, value: showOverview)
    }

    /// The ranked Apps / Websites / All list plus the line chart and footer.
    private var detailsBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            divider.padding(.top, 16).padding(.bottom, 14)
            HStack(spacing: 8) {
                SegmentedToggle(selection: $scope)
                AllButton(selection: $scope)
            }

            listHeader
                .padding(.top, 14)
                .padding(.bottom, 4)

            VStack(spacing: 2) {
                if scope == .websites && monitor.automationDenied {
                    PermissionNudge { Permissions.openAutomationSettings() }
                        .padding(.bottom, 6)
                }
                if entries.isEmpty {
                    EmptyStateView(scope: scope)
                } else {
                    UsageListView(entries: entries)
                }
            }
            .id("\(scope)-\(viewDay)")
            .transition(.opacity)
            .animation(.calm, value: scope)

            if !entries.isEmpty {
                insetDivider.padding(.top, 14).padding(.bottom, 12)
                UsageChartView(
                    lines: store.chartLines(entries: entries, for: viewDay,
                                            startMinute: chartStartHour * 60,
                                            endMinute: chartEndHour * 60),
                    startMinute: chartStartHour * 60,
                    endMinute: chartEndHour * 60
                )
                .id("\(scope)-\(viewDay)")
                .transition(.opacity)
            }

            divider.padding(.top, 12).padding(.bottom, 11)
            footer
        }
    }

    /// Active blocks with a live countdown. No cancel control — a block can only
    /// end by running out, so there's deliberately nothing here to tap.
    private var blockBanner: some View {
        let blockColor = Color(hex: 0xF0544A)
        return VStack(spacing: 6) {
            ForEach(blocks.activeBlocks) { b in
                HStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(blockColor)
                    Text(b.label)
                        .font(.rowMeta.weight(.medium))
                        .foregroundStyle(Theme.Ink.primary)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 6)
                    Text(Format.countdown(b.remaining))
                        .font(.rowValue.monospacedDigit())
                        .foregroundStyle(blockColor)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(blockColor.opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                    .strokeBorder(blockColor.opacity(0.22), lineWidth: 0.5))
            }
        }
        .padding(.top, 12)
    }

    private var divider: some View {
        Rectangle().fill(Theme.hairline).frame(height: 0.5)
    }

    /// A shorter, centered hairline between the list and the chart — deliberately
    /// inset so it doesn't run to the panel edges.
    private var insetDivider: some View {
        Rectangle().fill(Theme.hairline).frame(height: 0.5).padding(.horizontal, 14)
    }

    private var listHeader: some View {
        HStack {
            SectionLabel(text: scope == .apps ? "Application" : scope == .websites ? "Website" : "Activity")
            Spacer()
            SectionLabel(text: "Focused")
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Text("\(appEntries.count) apps")
            Text("·").foregroundStyle(Theme.Ink.faint)
            Text("\(siteEntries.count) sites")
            Spacer()
            Button { NSApp.terminate(nil) } label: {
                Text("Quit")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.Ink.tertiary)
            }
            .buttonStyle(.plain)
        }
        .font(.system(size: 11))
        .foregroundStyle(Theme.Ink.tertiary)
    }
}

/// Makes the popover's host window clear so the rounded glass panel reads as a
/// floating slab instead of sitting on an opaque rectangle.
private struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            guard let window = v.window else { return }
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = true
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
