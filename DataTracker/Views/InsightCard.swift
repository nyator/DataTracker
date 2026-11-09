import Charts
import SwiftUI

/// One tile in the dashboard's Insights grid: icon and title, a large
/// figure, a small chart, and a status line, on the insight's tinted card.
struct InsightCard: View {
    let insight: Insight
    let figures: InsightFigures

    @ScaledMetric(relativeTo: .body) private var chartHeight: CGFloat = 64

    var body: some View {
        let tint = insight.tint
        VStack(alignment: .leading, spacing: 10) {
            Label(insight.title, systemImage: insight.icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)

            figure
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            chart
                .frame(height: chartHeight)
                .frame(maxWidth: .infinity)

            status
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(LinearGradient(colors: [tint.card.opacity(0.95), tint.card],
                                     startPoint: .top, endPoint: .bottom))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens \(insight.title) details")
    }

    private var s: UsageSnapshot { figures.snapshot }

    // MARK: Figure

    @ViewBuilder private var figure: some View {
        switch insight {
        case .trend:
            if let p = figures.trendPercent {
                percentFigureText(p, font: FigureFont.card)
            } else {
                Text("—").font(FigureFont.card).foregroundColor(.white)
            }
        case .bundle:
            figureText(s.bundleUsedBytes, font: FigureFont.card)
        case .calendar:
            figureText(figures.fortnightTotal, font: FigureFont.card)
        case .pace:
            if let pace = figures.pace {
                signedFigureText(pace, font: FigureFont.card)
            } else {
                Text("—").font(FigureFont.card).foregroundColor(.white)
            }
        case .plan:
            figureText(s.recommendedFromTomorrowBytes, font: FigureFont.card)
        case .remaining:
            figureText(s.bundleRemainingBytes, font: FigureFont.card)
        }
    }

    // MARK: Chart

    @ViewBuilder private var chart: some View {
        let accent = insight.tint.accent
        switch insight {
        case .trend:
            Sparkline(values: figures.days.map { (date: $0.date, bytes: $0.bytes) }, color: accent)
        case .bundle:
            BundleDonut(figures: figures, innerRatio: 0.58)
        case .calendar:
            Chart(figures.days) { day in
                BarMark(x: .value("Day", day.date, unit: .day),
                        y: .value("GB", Budget.gb(fromBytes: day.bytes)), width: .ratio(0.45))
                    .foregroundStyle(figures.isOver(day) ? Palette.red : accent.opacity(figures.isToday(day) ? 1 : 0.8))
                    .cornerRadius(2)
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
        case .pace:
            ArcGauge(position: figures.paceGaugePosition, color: accent, lineWidth: 9,
                     dimmed: figures.pace == nil)
        case .plan:
            PlanBars(today: s.dailyBudgetBytes, tomorrow: s.recommendedFromTomorrowBytes,
                     color: accent)
        case .remaining:
            Sparkline(values: figures.remainingSeries.map { (date: $0.date, bytes: $0.bytes) },
                      color: accent, fromZero: false)
        }
    }

    // MARK: Status

    @ViewBuilder private var status: some View {
        let accent = insight.tint.accent
        switch insight {
        case .trend:
            switch figures.trendDirection {
            case .up: Label("Increasing", systemImage: "arrow.up.circle.fill")
            case .down: Label("Decreasing", systemImage: "arrow.down.circle.fill")
            case .steady: Label("Steady", systemImage: "equal.circle.fill")
            case .unknown: Label("Needs 2 weeks", systemImage: "clock")
            }
        case .bundle:
            DotLabel("\(Int((s.bundleFraction * 100).rounded()))% used", color: Palette.orange)
        case .calendar:
            DotLabel(figures.daysOver == 0 ? "None over budget"
                     : "\(figures.daysOver) \(figures.daysOver == 1 ? "day" : "days") over",
                     color: figures.daysOver == 0 ? accent : Palette.red)
        case .pace:
            DotLabel(figures.paceStatus.label, color: figures.paceStatus == .behind ? Palette.yellow : accent)
        case .plan:
            let change = figures.planChange
            if abs(change) < 10 * 1_048_576 {
                Label("Same as today", systemImage: "equal.circle.fill")
            } else {
                Label("\(DataFormat.string(abs(change))) \(change > 0 ? "more" : "less")",
                      systemImage: change > 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
            }
        case .remaining:
            if let lasts = figures.daysOfDataLeft {
                Label(figures.lastsTheBundle == true ? "Lasts the bundle" : "Lasts \(lasts) days",
                      systemImage: figures.lastsTheBundle == true ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
            } else {
                Label("of \(DataFormat.string(s.bundleBytes))", systemImage: "simcard.fill")
            }
        }
    }
}

/// A coloured dot and a label, as in the cards' status lines.
struct DotLabel: View {
    let text: String
    let color: Color

    init(_ text: String, color: Color) {
        self.text = text
        self.color = color
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text)
        }
    }
}

/// A smooth line with a fading fill and a dot at its latest point.
struct Sparkline: View {
    let values: [(date: Date, bytes: Int64)]
    let color: Color
    /// Start the y-axis at zero (usage); off for data left, where the change is what matters.
    var fromZero = true

    var body: some View {
        let gbs = values.map { Budget.gb(fromBytes: $0.bytes) }
        let top = max(gbs.max() ?? 1, 0.1)
        let bottom = fromZero ? 0 : (gbs.min() ?? 0)
        let pad = max((top - bottom) * 0.15, 0.05)
        Chart {
            ForEach(values, id: \.date) { v in
                AreaMark(x: .value("Day", v.date),
                         yStart: .value("Base", fromZero ? 0 : bottom - pad),
                         yEnd: .value("GB", Budget.gb(fromBytes: v.bytes)))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(LinearGradient(colors: [color.opacity(0.35), color.opacity(0)],
                                                    startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Day", v.date), y: .value("GB", Budget.gb(fromBytes: v.bytes)))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
            }
            if let last = values.last {
                PointMark(x: .value("Day", last.date), y: .value("GB", Budget.gb(fromBytes: last.bytes)))
                    .foregroundStyle(color)
                    .symbolSize(50)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: (fromZero ? 0 : bottom - pad)...(top + pad))
        .accessibilityHidden(true)
    }
}

/// Used before today, used today and left, as a donut.
struct BundleDonut: View {
    let figures: InsightFigures
    var innerRatio: CGFloat = 0.62

    struct Slice: Identifiable {
        let id: String
        let bytes: Int64
        let color: Color
    }

    static func slices(_ s: UsageSnapshot) -> [Slice] {
        let today = min(s.todayBytes, s.bundleUsedBytes)
        return [
            Slice(id: "Left", bytes: s.bundleRemainingBytes, color: Palette.teal),
            Slice(id: "Used before today", bytes: s.bundleUsedBytes - today, color: Palette.orange),
            Slice(id: "Used today", bytes: today, color: Palette.magenta),
        ]
    }

    var body: some View {
        let slices = Self.slices(figures.snapshot).filter { $0.bytes > 0 }
        Chart(slices) { slice in
            SectorMark(angle: .value("Bytes", Double(slice.bytes)),
                       innerRadius: .ratio(innerRatio), angularInset: 2)
                .cornerRadius(3)
                .foregroundStyle(slice.color)
        }
        .chartLegend(.hidden)
        .accessibilityHidden(true)
    }
}

/// An upper arc with a knob marking a position along it (0 left … 1 right).
/// The ends are tinted: yellow for behind, the accent for ahead.
struct ArcGauge: View {
    let position: Double
    let color: Color
    var lineWidth: CGFloat = 10
    var dimmed = false

    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let h = g.size.height
            // A circle much wider than the view, so only a gentle arc shows.
            let radius = max(w * 0.85, h)
            let center = CGPoint(x: w / 2, y: radius + lineWidth)
            let half = asin(min((w / 2 - lineWidth) / radius, 1))
            let start = -Double.pi / 2 - half
            let end = -Double.pi / 2 + half
            let knobAngle = start + (end - start) * position
            let knob = CGPoint(x: center.x + radius * cos(knobAngle), y: center.y + radius * sin(knobAngle))

            ZStack {
                arc(center: center, radius: radius, from: start, to: end)
                    .stroke(Color.white.opacity(0.1), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                arc(center: center, radius: radius, from: start + (end - start) * 0.12, to: end - (end - start) * 0.12)
                    .stroke(LinearGradient(colors: [Palette.yellow, color, color],
                                           startPoint: .leading, endPoint: .trailing),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .opacity(dimmed ? 0.3 : 1)
                if !dimmed {
                    Circle()
                        .fill(Palette.ink)
                        .frame(width: lineWidth * 1.8, height: lineWidth * 1.8)
                        .overlay(Circle().strokeBorder(.white, lineWidth: lineWidth * 0.35))
                        .shadow(color: color.opacity(0.9), radius: 8)
                        .position(knob)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func arc(center: CGPoint, radius: CGFloat, from: Double, to: Double) -> Path {
        Path { p in
            p.addArc(center: center, radius: radius, startAngle: .radians(from), endAngle: .radians(to), clockwise: false)
        }
    }
}

/// Today's budget against the amount from tomorrow, as two bars.
struct PlanBars: View {
    let today: Int64
    let tomorrow: Int64
    let color: Color

    var body: some View {
        let top = Double(max(today, tomorrow, 1))
        VStack(alignment: .leading, spacing: 10) {
            bar(icon: "sun.max", fraction: Double(today) / top, color: color.opacity(0.55))
            bar(icon: "arrow.right", fraction: Double(tomorrow) / top, color: color)
        }
        .frame(maxHeight: .infinity)
        .accessibilityHidden(true)
    }

    private func bar(icon: String, fraction: Double, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 14)
            GeometryReader { g in
                Capsule()
                    .fill(color)
                    .frame(width: max(g.size.width * fraction, 8))
            }
            .frame(height: 16)
        }
    }
}

#Preview {
    let figures = InsightFigures(snapshot: .sample, settings: {
        var s = BudgetSettings()
        s.isSetUp = true
        return s
    }())
    return ScrollView {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(Insight.allCases) { InsightCard(insight: $0, figures: figures) }
        }
        .padding()
    }
    .background(.black)
}
