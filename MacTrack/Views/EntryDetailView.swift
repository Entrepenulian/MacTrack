import SwiftUI

/// Tapping a row opens this — the stats for one app or site. The headline is an
/// hourly bar chart: for each hour of the tracking window, how many of its 60
/// minutes went to this app/site. Bars grow in on appear and thicken + glow on
/// hover, mirroring the donut's slice hover.
struct EntryDetailView: View {
    let entry: UsageEntry
    let day: String
    let startHour: Int
    let endHour: Int
    let onBack: () -> Void
    /// Reports the currently-shown title + total up to the header's hero readout, so
    /// the big timer reflects the detail's selection (e.g. "All" → the x.com total).
    var onReadout: (String, Double) -> Void = { _, _ in }
    @EnvironmentObject private var store: UsageStore
    @State private var range: DetailRange = .day
    /// The bars take the app/site's own brand color, pulled from its icon/favicon.
    @State private var barColor: Color = Theme.focus
    /// For X (an account-split site): the account whose chart + tag are shown.
    @State private var selectedAccount: String = ""

    private var entryDomain: String? {
        if case .site(let d) = entry.kind { return d }
        return nil
    }
    /// The X/Twitter base ("x.com") if this entry is one of its rows, else nil.
    private var xBase: String? {
        guard let d = entryDomain, SiteKey.splits(SiteKey.base(d)) else { return nil }
        return SiteKey.base(d)
    }
    /// The detected accounts for that base — present means we show the switcher.
    private var xAccounts: [(key: String, handle: String, seconds: Double)] {
        guard let base = xBase else { return [] }
        return store.siteAccounts(base: base, for: day)
    }
    private var isXSwitcher: Bool { !xAccounts.isEmpty }
    /// The un-split X base ("x.com") with no detected accounts — prompts enabling.
    private var isUnsplitX: Bool { xBase != nil && xAccounts.isEmpty }

    /// The entry whose chart is shown: "All" → the x.com aggregate, an account → that
    /// account, anything else → this entry.
    private var chartEntryID: String {
        guard isXSwitcher else { return entry.id }
        if selectedAccount.isEmpty, let base = xBase { return "site:" + base }
        return "site:" + selectedAccount
    }
    private var bars: [(hour: Int, minutes: Double)] {
        store.hourlyMinutes(entryID: chartEntryID, for: day, startHour: startHour, endHour: endHour)
    }
    private var weekBars: [(key: String, date: Date, seconds: Double)] {
        store.weeklyTotals(entryID: chartEntryID, week: day)
    }

    // Header follows the slider: "All" shows the x.com total, an account its own.
    private var titleText: String {
        guard isXSwitcher else { return entry.title }
        return selectedAccount.isEmpty ? "x.com" : SiteKey.display(selectedAccount)
    }
    private var totalSeconds: Double {
        guard isXSwitcher else { return entry.seconds }
        // "All" is the true aggregate — every account plus any untagged x.com time.
        if selectedAccount.isEmpty { return store.entrySeconds(entryID: "site:" + (xBase ?? ""), for: day) }
        return xAccounts.first { $0.key == selectedAccount }?.seconds ?? 0
    }

    /// Opening from a specific account row pre-selects it; otherwise default to
    /// "All" (the aggregate), matching how x.com used to show.
    private func initSelection() {
        guard isXSwitcher, selectedAccount.isEmpty else { return }
        if let d = entryDomain, SiteKey.isAccount(d) { selectedAccount = d }
    }

    /// A standalone "All" button (separate from the account slider) that shows the
    /// aggregate x.com total.
    private var allButton: some View {
        let isSel = selectedAccount.isEmpty
        return Button { withAnimation(.pill) { selectedAccount = "" } } label: {
            Text("All")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isSel ? Theme.Ink.primary : Theme.Ink.secondary)
                .padding(.vertical, 9)
                .padding(.horizontal, 16)
                .background(isSel ? Theme.fill(2) : Theme.fill(0), in: Capsule(style: .continuous))
                .overlay(Capsule(style: .continuous).strokeBorder(isSel ? Theme.hairlineStrong : Theme.hairline, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if isXSwitcher {
                HStack(spacing: 8) {
                    allButton
                    AccountSlider(accounts: xAccounts, selected: $selectedAccount)
                }
                .padding(.top, 14)
            }

            Rectangle().fill(Theme.hairline).frame(height: 0.5).padding(.top, 14)

            HStack(spacing: 8) {
                SectionLabel(text: range == .day ? "Minutes per hour" : "Total per day")
                Spacer()
                DayWeekToggle(selection: $range)
            }
            .padding(.top, 14)
            .padding(.bottom, 8)

            ZStack {
                if range == .day {
                    HourBarChart(bars: bars, color: barColor)
                        .transition(.opacity)
                } else {
                    WeekBarChart(days: weekBars, viewedDay: day, color: barColor)
                        .transition(.opacity)
                }
            }
            .id(chartEntryID)   // switching accounts re-draws the chart for that one
            .animation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.25), value: range)

            if isUnsplitX {
                xAccountHint.padding(.top, 16)
            }
        }
        .onAppear { initSelection(); onReadout(titleText, totalSeconds) }
        .onChange(of: selectedAccount) { onReadout(titleText, totalSeconds) }
        .onChange(of: totalSeconds) { onReadout(titleText, totalSeconds) }
        .task(id: entry.id) {
            let c = await IconColor.resolve(for: entry)
            withAnimation(.easeOut(duration: 0.35)) { barColor = c }
        }
    }

    private var header: some View {
        HStack(spacing: 11) {
            GlassIconButton(systemName: "chevron.left", size: 26, help: "Back", action: onBack)
            icon.frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(titleText)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Ink.primary)
                    .lineLimit(1).truncationMode(.middle)
                Text("\(Format.duration(totalSeconds)) total")
                    .font(.rowMeta.monospacedDigit())
                    .foregroundStyle(Theme.Ink.tertiary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(dayPercent)%")
                    .font(.system(size: 17, weight: .bold).monospacedDigit())
                    .foregroundStyle(barColor)
                    .contentTransition(.numericText())
                Text(day == DayKey.today ? "of today" : "of that day")
                    .font(.rowMeta)
                    .foregroundStyle(Theme.Ink.tertiary)
            }
        }
    }

    /// Shown on the bare "x.com" detail when account detection is off — points the
    /// user to the one browser setting that splits X into per-account rows.
    private var xAccountHint: some View {
        HStack(spacing: 9) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(barColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("Tracking all X accounts together")
                    .font(.rowTitle).foregroundStyle(Theme.Ink.primary)
                Text("To split into a row per account, turn on “Allow JavaScript from Apple Events” in your browser’s Develop menu.")
                    .font(.rowMeta).foregroundStyle(Theme.Ink.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(11)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).fill(Theme.fill(1)))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.5))
    }

    /// This entry's share of the day's total tracked time (≥1% for any real time).
    private var dayPercent: Int {
        let s = store.productivitySplit(for: day)
        let total = s.productive + s.unproductive + s.other
        guard total > 0, totalSeconds > 0 else { return 0 }
        return min(100, max(1, Int((totalSeconds / total * 100).rounded())))
    }

    @ViewBuilder private var icon: some View {
        switch entry.kind {
        case .app(let bundleID): AppIconView(bundleID: bundleID, size: 24)
        case .site(let domain): FaviconView(domain: domain, size: 24)
        }
    }
}

/// The hourly bars. X = each hour of the window; Y = minutes (0–60). Empty hours
/// keep a faint baseline tick so the time axis stays legible.
private struct HourBarChart: View {
    let bars: [(hour: Int, minutes: Double)]
    let color: Color

    @State private var hovered: Int? = nil
    @State private var appeared = false

    private let height: CGFloat = 150
    private let labelH: CGFloat = 15
    private let topPad: CGFloat = 14      // room for the 60m gridline label

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let plotH = height - labelH - topPad
            let n = max(1, bars.count)
            let slot = w / CGFloat(n)
            // Chunky bars sitting close together — just a 3pt gap between them.
            let barW = max(9, min(slot - 3, 24))

            ZStack(alignment: .topLeading) {
                grid(w: w, plotH: plotH)

                ForEach(bars.indices, id: \.self) { i in
                    bar(i: i, slot: slot, barW: barW, plotH: plotH)
                }

                hourLabels(slot: slot)

                if let i = hovered, i < bars.count {
                    tooltip(i: i, slot: slot, w: w, plotH: plotH)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let p):
                    let i = Int(p.x / slot)
                    hovered = (i >= 0 && i < bars.count) ? i : nil
                case .ended:
                    hovered = nil
                }
            }
        }
        .frame(height: height)
        .onAppear { appeared = true }
    }

    private func barHeight(_ i: Int, _ plotH: CGFloat) -> CGFloat {
        let frac = min(1, bars[i].minutes / 60)
        return max(bars[i].minutes > 0 ? 3 : 2, plotH * frac)
    }

    @ViewBuilder
    private func bar(i: Int, slot: CGFloat, barW: CGFloat, plotH: CGFloat) -> some View {
        let hot = hovered == i
        let has = bars[i].minutes > 0
        let full = barHeight(i, plotH)
        let h = appeared ? full : 0
        let x = slot * (CGFloat(i) + 0.5)
        let width = hot ? barW + 1.5 : barW
        // Full domed tops (a touch rounder), small rounding at the base.
        // Rounded top corners with a flat spot between them — not a full dome.
        let topR = min(5, h / 2)
        UnevenRoundedRectangle(topLeadingRadius: topR, bottomLeadingRadius: 2,
                               bottomTrailingRadius: 2, topTrailingRadius: topR,
                               style: .continuous)
            .fill(color.opacity(has ? (hot ? 1 : 0.88) : 0.16))
            .frame(width: width, height: h)
            // Hover just thickens and brightens the bar — no glow.
            .position(x: x, y: topPad + plotH - h / 2)     // grows up from the baseline
            .animation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.24), value: hot)
            .animation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.5)
                .delay(Double(min(i, 16)) * 0.022), value: appeared)
            .zIndex(hot ? 1 : 0)
    }

    /// Faint 60m / 30m gridlines, their labels, and the baseline.
    private func grid(w: CGFloat, plotH: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach([0.0, 0.5, 1.0], id: \.self) { frac in
                let y = topPad + plotH * CGFloat(1 - frac)
                Path { p in
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: w, y: y))
                }
                .stroke(Theme.hairline, lineWidth: 0.5)
            }
            ForEach([30, 60], id: \.self) { m in
                let y = topPad + plotH * CGFloat(1 - Double(m) / 60)
                Text("\(m)")
                    .font(.system(size: 8.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(Theme.Ink.faint)
                    .position(x: 8, y: y - 6)
            }
        }
    }

    /// Sparse hour ticks (≈ every 1/5 of the range) so the axis isn't crowded.
    private func hourLabels(slot: CGFloat) -> some View {
        let step = max(1, Int((Double(bars.count) / 5).rounded()))
        return ForEach(Array(bars.enumerated()), id: \.offset) { i, b in
            if i % step == 0 || i == bars.count - 1 {
                Text(hourLabel(b.hour))
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(Theme.Ink.faint)
                    .fixedSize()
                    .position(x: slot * (CGFloat(i) + 0.5), y: height - 6)
            }
        }
    }

    /// A clean single-line glass pill: a coloured dot, the hour, then the minutes.
    /// Slides between bars and crossfades on enter/exit.
    private func tooltip(i: Int, slot: CGFloat, w: CGFloat, plotH: CGFloat) -> some View {
        let mins = bars[i].minutes
        let half: CGFloat = 52
        let x = min(max(half, slot * (CGFloat(i) + 0.5)), w - half)
        return HStack(spacing: 6) {
            Text(hourClean(bars[i].hour))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.Ink.secondary)
            Text("·")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.Ink.faint)
            Text("\(Int(mins.rounded()))m")
                .font(.system(size: 11.5, weight: .bold).monospacedDigit())
                .foregroundStyle(mins > 0 ? color : Theme.Ink.secondary)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .glassControl(interactive: false)
        .shadow(color: .black.opacity(0.30), radius: 10, y: 3)
        .fixedSize()
        .position(x: x, y: topPad + 8)
        .animation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.18), value: hovered)
        .transition(.opacity)
    }

    private func hourLabel(_ hour: Int) -> String {
        let h12 = hour % 12 == 0 ? 12 : hour % 12
        return "\(h12)\(hour >= 12 && hour < 24 ? "P" : "A")"
    }
    /// "3 PM" — the clean hour the bar represents.
    private func hourClean(_ hour: Int) -> String {
        let h24 = ((hour % 24) + 24) % 24
        let h12 = h24 % 12 == 0 ? 12 : h24 % 12
        return "\(h12) \(h24 >= 12 ? "PM" : "AM")"
    }
}

// MARK: - Day / Week toggle

enum DetailRange: String, CaseIterable, Identifiable {
    case day = "Day", week = "Week"
    var id: String { rawValue }
}

/// A two-segment sliding pill — Day / Week — matching the scope toggle's style.
private struct DayWeekToggle: View {
    @Binding var selection: DetailRange
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 3) {
            ForEach(DetailRange.allCases) { r in
                let sel = selection == r
                Button { withAnimation(.pill) { selection = r } } label: {
                    Text(r.rawValue)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(sel ? Theme.Ink.primary : Theme.Ink.tertiary)
                        .padding(.vertical, 5)
                        .padding(.horizontal, 13)
                        .background {
                            if sel {
                                Capsule(style: .continuous)
                                    .fill(Theme.fill(2))
                                    .overlay(Capsule().strokeBorder(Theme.hairlineStrong, lineWidth: 0.5))
                                    .matchedGeometryEffect(id: "dwpill", in: ns)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Theme.fill(0), in: Capsule(style: .continuous))
    }
}

// MARK: - Week chart

/// Seven bars, one per day of the viewed week (Sun…Sat), each the total time on
/// this app/site that day. Auto-scaled to the busiest day; the viewed day's label
/// is tinted. Same rounded bars, hover-thicken, and glass tooltip as the day view.
private struct WeekBarChart: View {
    let days: [(key: String, date: Date, seconds: Double)]
    let viewedDay: String
    let color: Color

    @State private var hovered: Int? = nil
    @State private var appeared = false

    private let height: CGFloat = 150
    private let labelH: CGFloat = 15
    private let topPad: CGFloat = 14

    private var maxSeconds: Double { max(1, days.map(\.seconds).max() ?? 1) }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let plotH = height - labelH - topPad
            let n = max(1, days.count)
            let slot = w / CGFloat(n)
            let barW = max(16, min(slot - 12, 30))

            ZStack(alignment: .topLeading) {
                ForEach([0.0, 0.5, 1.0], id: \.self) { f in
                    let y = topPad + plotH * CGFloat(1 - f)
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: w, y: y))
                    }
                    .stroke(Theme.hairline, lineWidth: 0.5)
                }

                ForEach(days.indices, id: \.self) { i in
                    bar(i: i, slot: slot, barW: barW, plotH: plotH)
                }

                ForEach(days.indices, id: \.self) { i in
                    Text(weekdayInitial(days[i].date))
                        .font(.system(size: 9, weight: days[i].key == viewedDay ? .bold : .medium))
                        .foregroundStyle(days[i].key == viewedDay ? color : Theme.Ink.faint)
                        .fixedSize()
                        .position(x: slot * (CGFloat(i) + 0.5), y: height - 6)
                }

                if let i = hovered, i < days.count {
                    tooltip(i: i, slot: slot, w: w)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let p):
                    let i = Int(p.x / slot)
                    hovered = (i >= 0 && i < days.count) ? i : nil
                case .ended:
                    hovered = nil
                }
            }
        }
        .frame(height: height)
        .onAppear { appeared = true }
    }

    @ViewBuilder
    private func bar(i: Int, slot: CGFloat, barW: CGFloat, plotH: CGFloat) -> some View {
        let hot = hovered == i
        let secs = days[i].seconds
        let has = secs > 0
        let frac = min(1, secs / maxSeconds)
        let full = max(has ? 3 : 2, plotH * CGFloat(frac))
        let h = appeared ? full : 0
        let x = slot * (CGFloat(i) + 0.5)
        let width = hot ? barW + 1.5 : barW
        // Rounded top corners with a flat spot between them — not a full dome.
        let topR = min(5, h / 2)
        UnevenRoundedRectangle(topLeadingRadius: topR, bottomLeadingRadius: 2,
                               bottomTrailingRadius: 2, topTrailingRadius: topR,
                               style: .continuous)
            .fill(color.opacity(has ? (hot ? 1 : 0.88) : 0.16))
            .frame(width: width, height: h)
            .position(x: x, y: topPad + plotH - h / 2)
            .animation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.24), value: hot)
            .animation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.5)
                .delay(Double(i) * 0.03), value: appeared)
            .zIndex(hot ? 1 : 0)
    }

    private func tooltip(i: Int, slot: CGFloat, w: CGFloat) -> some View {
        let half: CGFloat = 60
        let x = min(max(half, slot * (CGFloat(i) + 0.5)), w - half)
        let secs = days[i].seconds
        return HStack(spacing: 5) {
            Text(dayLabel(days[i].date))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.Ink.secondary)
            Text("·")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.Ink.faint)
            Text(secs > 0 ? Format.duration(secs) : "0m")
                .font(.system(size: 11.5, weight: .bold).monospacedDigit())
                .foregroundStyle(secs > 0 ? color : Theme.Ink.secondary)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .glassControl(interactive: false)
        .shadow(color: .black.opacity(0.30), radius: 10, y: 3)
        .fixedSize()
        .position(x: x, y: topPad + 8)
        .animation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.18), value: hovered)
        .transition(.opacity)
    }

    private func weekdayInitial(_ d: Date) -> String {
        let i = Calendar.current.component(.weekday, from: d) - 1
        return ["S", "M", "T", "W", "T", "F", "S"][max(0, min(6, i))]
    }
    private static let dayFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE, MMM d"; return f
    }()
    private func dayLabel(_ d: Date) -> String { Self.dayFmt.string(from: d) }
}

// MARK: - Account switcher

/// A sliding segmented control with one segment per X account. Picking one drives
/// the chart and tag control below; segments split the width evenly. ("All" lives
/// outside this control, as a separate button.)
private struct AccountSlider: View {
    let accounts: [(key: String, handle: String, seconds: Double)]
    @Binding var selected: String
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 3) {
            ForEach(accounts, id: \.key) { a in
                segment(key: a.key, label: a.handle)
            }
        }
        .padding(3)
        .frame(maxWidth: .infinity)
        .background(Theme.fill(0), in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.5))
    }

    private func segment(key: String, label: String) -> some View {
        let isSel = selected == key
        return Button { withAnimation(.pill) { selected = key } } label: {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isSel ? Theme.Ink.primary : Theme.Ink.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background {
                    if isSel {
                        Capsule(style: .continuous).fill(Theme.fill(2))
                            .overlay(Capsule(style: .continuous).strokeBorder(Theme.hairlineStrong, lineWidth: 0.5))
                            .matchedGeometryEffect(id: "accpill", in: ns)
                    }
                }
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
