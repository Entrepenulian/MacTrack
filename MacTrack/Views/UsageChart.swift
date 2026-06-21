import SwiftUI

/// A clean line chart of cumulative time spent across the day for the top items
/// of the current scope. X = clock time (configurable window), Y = minutes.
/// Minimal grid, ten muted colors, draw-in animation, and a hover scrubber with
/// an exact-value tooltip. The matching list rows act as the color legend.
struct UsageChartView: View {
    let lines: [ChartLineData]
    let startMinute: Int
    let endMinute: Int

    @State private var drawProgress: CGFloat = 0
    @State private var hoverPoint: CGPoint?

    // Plot insets.
    private let leftGutter: CGFloat = 30
    private let bottomGutter: CGFloat = 16
    private let topPad: CGFloat = 10
    private let rightPad: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack(alignment: .topLeading) {
                grid(w, h)
                axisLabels(w, h)
                linesLayer(w, h)
                hoverLayer(w, h)
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let p): hoverPoint = p
                case .ended: hoverPoint = nil
                }
            }
        }
        .frame(height: 132)
        .onAppear {
            drawProgress = 0
            withAnimation(.easeOut(duration: 0.55)) { drawProgress = 1 }
        }
    }

    // MARK: Scales

    private var yMax: Double {
        let maxTotal = lines.map(\.totalMinutes).max() ?? 0
        guard maxTotal > 0 else { return 1 }
        let steps: [Double] = [1, 2, 5, 10, 15, 20, 30, 45, 60, 90, 120, 180, 240, 360, 480, 600, 720, 840]
        return steps.first { $0 >= maxTotal } ?? ((maxTotal / 60).rounded(.up) * 60)
    }

    private func xPix(_ minute: Double, _ w: CGFloat) -> CGFloat {
        let span = Double(endMinute - startMinute)
        let frac = span > 0 ? (minute - Double(startMinute)) / span : 0
        return leftGutter + CGFloat(frac) * (w - leftGutter - rightPad)
    }
    private func yPix(_ minutes: Double, _ h: CGFloat) -> CGFloat {
        let plotH = h - topPad - bottomGutter
        let frac = yMax > 0 ? minutes / yMax : 0
        return topPad + plotH * (1 - CGFloat(frac))
    }

    // MARK: Grid + axes

    private var hourTicks: [Int] {
        let startHour = startMinute / 60, endHour = endMinute / 60
        let totalH = max(1, endHour - startHour)
        let step = max(1, Int((Double(totalH) / 4.0).rounded()))
        var ticks: [Int] = []
        var hr = startHour
        while hr < endHour { ticks.append(hr); hr += step }
        ticks.append(endHour)
        return ticks
    }
    private var yTicks: [Double] { [0, yMax / 2, yMax] }

    private func grid(_ w: CGFloat, _ h: CGFloat) -> some View {
        ZStack {
            ForEach(yTicks, id: \.self) { v in
                Path { p in
                    let y = yPix(v, h)
                    p.move(to: CGPoint(x: leftGutter, y: y))
                    p.addLine(to: CGPoint(x: w - rightPad, y: y))
                }
                .stroke(Theme.hairline, lineWidth: 0.5)
            }
        }
    }

    private func axisLabels(_ w: CGFloat, _ h: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(yTicks, id: \.self) { v in
                Text("\(Int(v))m")
                    .font(.system(size: 8.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(Theme.Ink.faint)
                    .position(x: leftGutter - 14, y: yPix(v, h))
            }
            ForEach(hourTicks, id: \.self) { hr in
                Text(hourLabel(hr))
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(Theme.Ink.faint)
                    .position(x: xPix(Double(hr * 60), w), y: h - 6)
            }
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        let h12 = hour % 12 == 0 ? 12 : hour % 12
        let ap = (hour >= 12 && hour < 24) ? "P" : "A"
        return "\(h12)\(ap)"
    }

    // MARK: Lines

    private func linesLayer(_ w: CGFloat, _ h: CGFloat) -> some View {
        let highlighted = nearestLine(w, h)?.id
        return ZStack {
            ForEach(lines) { line in
                linePath(line, w, h)
                    .trim(from: 0, to: drawProgress)
                    .stroke(line.color,
                            style: StrokeStyle(lineWidth: highlighted == line.id ? 2.2 : 1.6,
                                               lineCap: .round, lineJoin: .round))
                    .opacity(highlighted == nil || highlighted == line.id ? 1 : 0.18)
            }
        }
        .animation(.easeOut(duration: 0.15), value: highlighted)
    }

    private func linePath(_ line: ChartLineData, _ w: CGFloat, _ h: CGFloat) -> Path {
        Path { p in
            for (i, pt) in line.points.enumerated() {
                let cg = CGPoint(x: xPix(pt.x, w), y: yPix(pt.y, h))
                if i == 0 { p.move(to: cg) } else { p.addLine(to: cg) }
            }
        }
    }

    // MARK: Hover

    private func minuteAt(_ x: CGFloat, _ w: CGFloat) -> Int {
        let span = Double(endMinute - startMinute)
        let frac = Double((x - leftGutter) / (w - leftGutter - rightPad))
        return min(max(startMinute, Int(Double(startMinute) + frac * span)), endMinute)
    }

    /// Interpolated Y (minutes) of a line at a given minute.
    private func value(_ line: ChartLineData, at minute: Double) -> Double {
        let pts = line.points
        guard let first = pts.first else { return 0 }
        if minute <= Double(first.x) { return Double(first.y) }
        for i in 1..<pts.count {
            if minute <= Double(pts[i].x) {
                let ax = Double(pts[i - 1].x), ay = Double(pts[i - 1].y)
                let bx = Double(pts[i].x), by = Double(pts[i].y)
                let t = bx == ax ? 0 : (minute - ax) / (bx - ax)
                return ay + (by - ay) * t
            }
        }
        return Double(pts.last?.y ?? 0)
    }

    private func nearestLine(_ w: CGFloat, _ h: CGFloat) -> ChartLineData? {
        guard let pt = hoverPoint, !lines.isEmpty else { return nil }
        let minute = Double(minuteAt(pt.x, w))
        return lines.min { a, b in
            abs(yPix(value(a, at: minute), h) - pt.y) < abs(yPix(value(b, at: minute), h) - pt.y)
        }
    }

    private func hoverLayer(_ w: CGFloat, _ h: CGFloat) -> some View {
        Group {
            if let pt = hoverPoint {
                let minute = minuteAt(pt.x, w)
                let x = xPix(Double(minute), w)
                let near = nearestLine(w, h)

                // Vertical scrubber.
                Path { p in
                    p.move(to: CGPoint(x: x, y: topPad))
                    p.addLine(to: CGPoint(x: x, y: h - bottomGutter))
                }
                .stroke(Theme.hairlineStrong, lineWidth: 1)

                // A dot where each line crosses the scrubber.
                ForEach(lines) { line in
                    Circle()
                        .fill(line.color)
                        .frame(width: near?.id == line.id ? 7 : 5, height: near?.id == line.id ? 7 : 5)
                        .opacity(near == nil || near?.id == line.id ? 1 : 0.3)
                        .position(x: x, y: yPix(value(line, at: Double(minute)), h))
                }

                if let near {
                    tooltip(for: near, minute: minute, x: x, w: w)
                }
            }
        }
    }

    private func tooltip(for line: ChartLineData, minute: Int, x: CGFloat, w: CGFloat) -> some View {
        let value = self.value(line, at: Double(minute))
        let tipWidth: CGFloat = 132
        let clampedX = min(max(leftGutter + tipWidth / 2, x), w - rightPad - tipWidth / 2)
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Circle().fill(line.color).frame(width: 6, height: 6)
                Text(line.label)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Theme.Ink.primary)
                    .lineLimit(1)
            }
            Text("\(Int(value.rounded()))m · \(clockLabel(minute))")
                .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.Ink.tertiary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(width: tipWidth, alignment: .leading)
        .background(Theme.fill(2), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.5))
        .position(x: clampedX, y: topPad + 14)
    }

    private func clockLabel(_ minute: Int) -> String {
        let hour = minute / 60, min = minute % 60
        let h12 = hour % 12 == 0 ? 12 : hour % 12
        let ap = (hour >= 12 && hour < 24) ? "PM" : "AM"
        return String(format: "%d:%02d %@", h12, min, ap)
    }
}
