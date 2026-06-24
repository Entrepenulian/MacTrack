import SwiftUI

/// A GitHub-style contribution grid built from squircles: seven weekday rows
/// across as many whole weeks as the width allows, with month labels along the
/// top. Each past day is colored by the category that dominated it — Productive,
/// Unproductive, or Other — with a matching glow, mirroring the donut. Days that
/// haven't happened yet aren't drawn; today shows as a plain gray cell.
///
/// Tapping a past day with data selects it (`onSelect`), so the rest of the
/// popover can show that day; the selected cell lifts and rings.
struct ActivityGraph: View {
    /// Winning category per day key ("yyyy-MM-dd"): 0 Productive, 1 Unproductive,
    /// 2 Other. Days absent here have no tracked time and stay empty.
    var winners: [String: Int] = [:]
    /// The day currently being viewed, if it's one of these squares.
    var selectedDay: String? = nil
    /// Called when a past day with data is tapped.
    var onSelect: (String) -> Void = { _ in }

    @State private var hoverKey: String? = nil

    private let cell: CGFloat = 12       // square cell edge
    private let vGap: CGFloat = 3        // gap between days (vertical)
    private let rows = 7                 // days of the week
    private let labelH: CGFloat = 12     // month-label strip height
    private let labelGap: CGFloat = 6    // strip → grid spacing

    /// Empty cells — past days with no tracked time, and today before it's final —
    /// a whisper-quiet gray. Days later this week aren't drawn at all.
    private let emptyFill = Color.primary.opacity(0.07)

    /// Category colors — identical to the donut/legend so the two read as one.
    private let catColor: [Color] = [Theme.productive, Theme.unproductive, Theme.neutralSlice]

    private let cal = Calendar.current

    private var gridH: CGFloat { CGFloat(rows) * cell + CGFloat(rows - 1) * vGap }
    private var totalH: CGFloat { labelH + labelGap + gridH }

    private var weekStart: Date {
        cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? cal.startOfDay(for: Date())
    }
    private var todayRow: Int {
        (cal.component(.weekday, from: Date()) - cal.firstWeekday + 7) % 7
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let weeks = max(8, Int((w + vGap) / (cell + vGap)))
            let hGap = weeks > 1 ? max(vGap, (w - CGFloat(weeks) * cell) / CGFloat(weeks - 1)) : vGap
            let step = cell + hGap

            VStack(alignment: .leading, spacing: labelGap) {
                monthLabels(weeks: weeks, step: step)
                    .frame(height: labelH, alignment: .bottomLeading)

                HStack(spacing: hGap) {
                    ForEach(0..<weeks, id: \.self) { col in
                        VStack(spacing: vGap) {
                            ForEach(0..<rows, id: \.self) { row in
                                cellView(col: col, row: row, weeks: weeks)
                            }
                        }
                    }
                }
            }
        }
        .frame(height: totalH)
    }

    @ViewBuilder
    private func cellView(col: Int, row: Int, weeks: Int) -> some View {
        let shape = RoundedRectangle(cornerRadius: cell * 0.3, style: .continuous)
        let isCurrentWeek = col == weeks - 1
        let key = dayKey(col: col, row: row, weeks: weeks)
        if isCurrentWeek && row > todayRow {
            // Days later this week haven't happened — don't draw them. A clear
            // placeholder keeps every column the same height so rows stay aligned.
            Color.clear.frame(width: cell, height: cell)
        } else if isCurrentWeek && row == todayRow {
            // Today: a plain gray cell you can click to return to today's data —
            // deliberately no selection ring, since today isn't a picked past day.
            todayCell(shape, key: key)
        } else if let win = winners[key] {
            lit(shape, color: catColor[win], key: key)
        } else {
            emptyCell(shape)   // a past day with no tracked data
        }
    }

    private func emptyCell(_ shape: RoundedRectangle) -> some View {
        shape
            .fill(emptyFill)
            .overlay(shape.strokeBorder(Color.primary.opacity(0.04), lineWidth: 0.5))
            .frame(width: cell, height: cell)
    }

    /// Today — looks like an empty gray cell but is clickable to jump back to
    /// today's data. It only lifts on hover; it never takes the white selection
    /// ring that a chosen past day does.
    private func todayCell(_ shape: RoundedRectangle, key: String) -> some View {
        let hovered = hoverKey == key
        return shape
            .fill(emptyFill)
            .overlay(shape.strokeBorder(Color.primary.opacity(0.04), lineWidth: 0.5))
            .frame(width: cell, height: cell)
            .scaleEffect(hovered ? 1.12 : 1)
            .zIndex(hovered ? 1 : 0)
            .contentShape(shape)
            .pointerStyle(.link)
            .onHover { hoverKey = $0 ? key : (hoverKey == key ? nil : hoverKey) }
            .onTapGesture { onSelect(key) }
            .animation(.snappy(duration: 0.18), value: hovered)
    }

    /// A finalized, clickable day: its category color with a soft matching glow.
    /// Hovering lifts it; the selected day rings brighter and stays lifted.
    private func lit(_ shape: RoundedRectangle, color c: Color, key: String) -> some View {
        let selected = key == selectedDay
        let active = selected || hoverKey == key
        return shape
            .fill(c)
            .overlay(shape.strokeBorder(Color.white.opacity(selected ? 0.9 : 0.12),
                                        lineWidth: selected ? 1.2 : 0.5))
            .frame(width: cell, height: cell)
            .scaleEffect(active ? 1.16 : 1)
            .shadow(color: c.opacity(active ? 0.6 : 0.38), radius: active ? 2.5 : 1.5)
            .shadow(color: c.opacity(active ? 0.28 : 0.15), radius: active ? 5 : 3.5)
            .zIndex(active ? 1 : 0)
            .contentShape(shape)
            .pointerStyle(.link)
            .onHover { hoverKey = $0 ? key : (hoverKey == key ? nil : hoverKey) }
            .onTapGesture { onSelect(key) }
            .animation(.snappy(duration: 0.18), value: active)
    }

    /// The day key ("yyyy-MM-dd") for the cell at `(col, row)`, walking back from
    /// the current week. Row 0 is the week's first weekday (Sunday in the US).
    private func dayKey(col: Int, row: Int, weeks: Int) -> String {
        let ws = cal.date(byAdding: .weekOfYear, value: -(weeks - 1 - col), to: weekStart) ?? weekStart
        let d = cal.date(byAdding: .day, value: row, to: ws) ?? ws
        return DayKey.key(for: d)
    }

    private func monthLabels(weeks: Int, step: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(monthMarks(weeks: weeks), id: \.col) { mark in
                Text(mark.label)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(Theme.Ink.faint)
                    .fixedSize()
                    .offset(x: CGFloat(mark.col) * step)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func monthMarks(weeks: Int) -> [(col: Int, label: String)] {
        var marks: [(col: Int, label: String)] = []
        var lastMonth = -1
        for i in 0..<weeks {
            guard let d = cal.date(byAdding: .weekOfYear, value: -(weeks - 1 - i), to: weekStart) else { continue }
            let m = cal.component(.month, from: d)
            if m != lastMonth && i < weeks - 1 {
                marks.append((i, cal.shortMonthSymbols[m - 1]))
            }
            lastMonth = m
        }
        return marks
    }
}
