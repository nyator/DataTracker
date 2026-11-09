import Charts
import SwiftUI

/// The body of one detail page.
struct InsightPage: View {
    let insight: Insight
    let figures: InsightFigures
    let editLimit: () -> Void

    var body: some View {
        switch insight {
        case .trend: TrendPage(figures: figures)
        case .bundle: BundlePage(figures: figures)
        case .calendar: CalendarPage(figures: figures)
        case .pace: PacePage(figures: figures)
        case .plan: PlanPage(figures: figures, editLimit: editLimit)
        case .remaining: RemainingPage(figures: figures)
        }
    }
}

// MARK: - Building blocks

/// A small caption, a large figure, and a line under it.
private struct Headline<Detail: View>: View {
    let caption: String
    let figure: Text
    @ViewBuilder var detail: () -> Detail

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(caption)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
            figure
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            detail()
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// The dark, outlined panel charts sit in.
private struct Panel<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12, content: content)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.black.opacity(0.28)))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }
}

/// Grouped rows with hairlines between them.
private struct RowGroup: View {
    struct Row: Identifiable {
        var id: String { label }
        var dot: Color?
        let label: String
        let value: String
        var dim = false
    }

    let rows: [Row]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                HStack(spacing: 12) {
                    if let dot = row.dot {
                        Circle().fill(dot).frame(width: 10, height: 10)
                    }
                    Text(row.label)
                        .foregroundStyle(row.dim ? Theme.secondaryText : .white)
                    Spacer(minLength: 8)
                    Text(row.value)
                        .monospacedDigit()
                        .foregroundStyle(row.dim ? Theme.tertiaryText : Theme.secondaryText)
                        .multilineTextAlignment(.trailing)
                }
                .font(.body)
                .padding(.vertical, 14)
                .accessibilityElement(children: .combine)
                if index < rows.count - 1 {
                    Divider().overlay(Color.white.opacity(0.06))
                }
            }
        }
        .padding(.horizontal, 16)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.white.opacity(0.08)))
    }
}

/// "What is …?" and a paragraph or two.
private struct Explainer: View {
    let title: String
    let paragraphs: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
            ForEach(paragraphs, id: \.self) { p in
                Text(p)
                    .font(.body)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }
}

/// Three label-over-figure stats side by side.
private struct StatTriple: View {
    let items: [(label: String, text: Text)]

    var body: some View {
        HStack(alignment: .top) {
            ForEach(items.indices, id: \.self) { i in
                VStack(spacing: 6) {
                    Text(items[i].label)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.secondaryText)
                    items[i].text
                        .monospacedDigit()
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

private func gbAxis() -> some AxisContent {
    AxisMarks(position: .trailing) { value in
        AxisGridLine().foregroundStyle(Color.white.opacity(0.08))
        AxisValueLabel {
            if let gb = value.as(Double.self) { Text(String(format: "%.1f GB", gb)) }
        }
        .foregroundStyle(Theme.secondaryText)
    }
}

private func dayAxis() -> some AxisContent {
    AxisMarks(values: .stride(by: .day, count: 3)) { _ in
        AxisGridLine().foregroundStyle(Color.white.opacity(0.05))
        AxisValueLabel(format: .dateTime.day()).foregroundStyle(Theme.secondaryText)
    }
}

// MARK: - Trend

private struct TrendPage: View {
    let figures: InsightFigures
    @State private var selectedDate: Date?

    var body: some View {
        let accent = Insight.trend.tint.accent
        let days = figures.days
        let selected = selectedDate.flatMap { d in days.first { Calendar.current.isDate($0.date, inSameDayAs: d) } }

        VStack(alignment: .leading, spacing: 20) {
            Headline(caption: selected.map { $0.date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)) }
                        ?? "Average over the last 7 days",
                     figure: figureText(selected?.bytes ?? figures.recentAverage ?? 0,
                                        font: FigureFont.page, unitFont: .title3)) {
                if let selected {
                    if let budget = figures.budget(on: selected) {
                        let diff = selected.bytes - budget
                        Label("\(DataFormat.string(abs(diff))) \(diff > 0 ? "over" : "under") budget",
                              systemImage: diff > 0 ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                    } else {
                        Text("No budget recorded that day")
                    }
                } else if let p = figures.trendPercent {
                    Label("\(abs(p))% \(p >= 0 ? "more" : "less") than the week before",
                          systemImage: p >= 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                } else {
                    Text("Shows once there are two weeks of usage")
                }
            }

            Panel {
                Chart {
                    ForEach(days) { day in
                        let gb = Budget.gb(fromBytes: day.bytes)
                        AreaMark(x: .value("Day", day.date, unit: .day), y: .value("GB", gb))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(LinearGradient(colors: [accent.opacity(0.3), accent.opacity(0)],
                                                            startPoint: .top, endPoint: .bottom))
                        LineMark(x: .value("Day", day.date, unit: .day), y: .value("GB", gb),
                                 series: .value("Series", "Used"))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(accent)
                            .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                        if let budget = figures.budget(on: day) {
                            LineMark(x: .value("Day", day.date, unit: .day),
                                     y: .value("GB", Budget.gb(fromBytes: budget)),
                                     series: .value("Series", "Budget"))
                                .interpolationMethod(.monotone)
                                .foregroundStyle(Color.white.opacity(0.5))
                                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [6, 5]))
                        }
                    }
                    if let selected {
                        RuleMark(x: .value("Day", selected.date, unit: .day))
                            .foregroundStyle(Color.white.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        PointMark(x: .value("Day", selected.date, unit: .day),
                                  y: .value("GB", Budget.gb(fromBytes: selected.bytes)))
                            .foregroundStyle(accent)
                            .symbolSize(80)
                    } else if let last = days.last {
                        PointMark(x: .value("Day", last.date, unit: .day),
                                  y: .value("GB", Budget.gb(fromBytes: last.bytes)))
                            .foregroundStyle(accent)
                            .symbolSize(80)
                    }
                }
                .chartXSelection(value: $selectedDate)
                .chartYAxis { gbAxis() }
                .chartXAxis { dayAxis() }
                .frame(height: 260)

                HStack(spacing: 16) {
                    DotLabel("Daily use", color: accent)
                    DotLabel("Daily budget", color: Color.white.opacity(0.5))
                }
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
            }

            Explainer(title: "What is Trend?", paragraphs: [
                "Compares your average daily use over the last 7 days with the week before, to show whether your usage is creeping up or settling down.",
                "The solid line is what you used each day. The dashed line is that day's budget. Touch and drag on the chart to see a day.",
            ])
        }
    }
}

// MARK: - Bundle

private struct BundlePage: View {
    let figures: InsightFigures

    @ScaledMetric(relativeTo: .largeTitle) private var donutSize: CGFloat = 250

    var body: some View {
        let s = figures.snapshot
        let slices = BundleDonut.slices(s)
        let lastDay = Calendar.current.date(byAdding: .day, value: -1, to: Budget.endDate(figures.settings)) ?? Date()

        VStack(spacing: 24) {
            ZStack {
                BundleDonut(figures: figures, innerRatio: 0.72)
                VStack(spacing: 4) {
                    figureText(s.bundleUsedBytes, font: .title.weight(.bold), unitFont: .headline)
                        .monospacedDigit()
                    Text("used of \(DataFormat.string(s.bundleBytes))")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(width: min(donutSize, 300) * 0.6)
            }
            .frame(width: min(donutSize, 300), height: min(donutSize, 300))
            .padding(.top, 8)
            .accessibilityElement(children: .combine)

            RowGroup(rows: slices.map {
                RowGroup.Row(dot: $0.color, label: $0.id, value: DataFormat.string($0.bytes))
            })

            RowGroup(rows: [
                RowGroup.Row(label: "Bundle size", value: DataFormat.string(s.bundleBytes)),
                RowGroup.Row(label: "Started", value: figures.settings.startDate.formatted(date: .abbreviated, time: .omitted)),
                RowGroup.Row(label: "Last day", value: lastDay.formatted(date: .abbreviated, time: .omitted)),
                RowGroup.Row(label: "Days left", value: "\(s.daysLeft)"),
            ])

            Explainer(title: "What is Bundle?", paragraphs: [
                "Your whole data bundle at a glance: what you used before today, what you've used today, and what's left.",
                "If these numbers drift from what MTN reports (e.g. *138#), correct them under Settings → Correction.",
            ])
        }
    }
}

// MARK: - Calendar

private struct CalendarPage: View {
    let figures: InsightFigures
    @State private var selectedKey: String?

    var body: some View {
        let accent = Insight.calendar.tint.accent
        let byKey = Dictionary(figures.days.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        let selected = selectedKey.flatMap { byKey[$0] } ?? figures.today
        let average = figures.days.isEmpty ? 0 : figures.fortnightTotal / Int64(figures.days.count)

        VStack(alignment: .leading, spacing: 20) {
            Headline(caption: "Used in the last 14 days",
                     figure: figureText(figures.fortnightTotal, font: FigureFont.page, unitFont: .title3)) {
                Text("\(DataFormat.string(average)) a day on average")
            }

            Panel {
                MonthGrid(figures: figures, byKey: byKey, selectedKey: selected?.key, accent: accent) { key in
                    withAnimation(.easeOut(duration: 0.2)) { selectedKey = key }
                }
            }

            if let day = selected {
                VStack(alignment: .leading, spacing: 10) {
                    Text(day.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year()))
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.leading, 4)
                    RowGroup(rows: dayRows(day))
                }
            }

            Explainer(title: "What is Calendar?", paragraphs: [
                "Each day of the last two weeks with the gigabytes you used underneath. Days in red went over that day's budget.",
                "Tap a day to see its usage against its budget.",
            ])
        }
    }

    private func dayRows(_ day: UsageSnapshot.Day) -> [RowGroup.Row] {
        var rows = [RowGroup.Row(dot: figures.isOver(day) ? Palette.red : Palette.orange,
                                 label: figures.isToday(day) ? "Used so far" : "Used",
                                 value: DataFormat.string(day.bytes))]
        if let budget = figures.budget(on: day) {
            rows.append(RowGroup.Row(label: "Budget", value: DataFormat.string(budget)))
            let diff = day.bytes - budget
            rows.append(RowGroup.Row(label: diff > 0 ? "Over by" : "Under by", value: DataFormat.string(abs(diff))))
        } else {
            rows.append(RowGroup.Row(label: "Budget", value: "Not recorded", dim: true))
        }
        return rows
    }
}

/// Calendar weeks covering the history, with each day's usage under its date.
private struct MonthGrid: View {
    let figures: InsightFigures
    let byKey: [String: UsageSnapshot.Day]
    let selectedKey: String?
    let accent: Color
    let select: (String) -> Void

    var body: some View {
        let cal = Calendar.current
        let dates = gridDates(cal)
        let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

        VStack(spacing: 10) {
            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(weekdaySymbols(cal), id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.tertiaryText)
                }
            }
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(dates, id: \.self) { date in
                    cell(date, cal: cal)
                }
            }
        }
    }

    @ViewBuilder
    private func cell(_ date: Date, cal: Calendar) -> some View {
        let key = DayMath.key(for: date)
        let day = byKey[key]
        let isToday = day.map(figures.isToday) ?? false
        let isSelected = key == selectedKey
        let number = Text("\(cal.component(.day, from: date))")
            .font(.body.weight(isToday ? .bold : .regular))
            .foregroundStyle(day == nil ? Theme.tertiaryText : .white)
            .frame(width: 34, height: 34)
            .background(Circle().fill(isToday ? Palette.blue.opacity(0.35) : .clear))

        VStack(spacing: 2) {
            number
            Text(day.map { $0.bytes > 0 ? shortAmount($0.bytes) : "–" } ?? " ")
                .font(.caption2.weight(.bold))
                .foregroundStyle(day.map { figures.isOver($0) ? Palette.red : accent } ?? .clear)
                .monospacedDigit()
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 10).fill(isSelected ? Color.white.opacity(0.1) : .clear))
        .contentShape(Rectangle())
        .onTapGesture { if day != nil { select(key) } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(date, day))
        .accessibilityAddTraits(day != nil ? .isButton : [])
    }

    private func accessibilityText(_ date: Date, _ day: UsageSnapshot.Day?) -> String {
        let d = date.formatted(.dateTime.weekday(.wide).day().month(.wide))
        guard let day else { return d }
        return "\(d), \(DataFormat.string(day.bytes))\(figures.isOver(day) ? ", over budget" : "")"
    }

    /// Whole weeks from the one holding the first history day to the one holding today.
    private func gridDates(_ cal: Calendar) -> [Date] {
        guard let first = figures.days.first?.date, let last = figures.days.last?.date,
              let start = cal.dateInterval(of: .weekOfYear, for: first)?.start,
              let end = cal.dateInterval(of: .weekOfYear, for: last)?.end else { return [] }
        var dates: [Date] = []
        var d = start
        while d < end {
            dates.append(d)
            guard let next = cal.date(byAdding: .day, value: 1, to: d) else { break }
            d = next
        }
        return dates
    }

    private func weekdaySymbols(_ cal: Calendar) -> [String] {
        let symbols = cal.shortStandaloneWeekdaySymbols.map { $0.uppercased() }
        let first = cal.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }
}

// MARK: - Pace

private struct PacePage: View {
    let figures: InsightFigures

    var body: some View {
        let accent = Insight.pace.tint.accent
        let s = figures.snapshot
        let status = figures.paceStatus

        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(status.label)
                    .font(FigureFont.page)
                    .foregroundStyle(.white)
                Text(sentence)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)

            ArcGauge(position: figures.paceGaugePosition, color: accent, lineWidth: 14,
                     dimmed: figures.pace == nil)
                .frame(height: 80)
                .padding(.horizontal, -8)

            if let expected = figures.expectedUsed, let pace = figures.pace {
                StatTriple(items: [
                    ("Even pace", figureText(expected, font: FigureFont.stat, unitFont: .footnote)),
                    ("You used", figureText(s.bundleUsedBytes, font: FigureFont.stat, unitFont: .footnote)),
                    ("Difference", signedFigureText(pace, font: FigureFont.stat, unitFont: .footnote)),
                ])
            }

            Panel {
                Text("Under or over each day's budget")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                Chart {
                    ForEach(figures.days) { day in
                        if let budget = figures.budget(on: day) {
                            let diff = Budget.gb(fromBytes: budget - day.bytes)
                            BarMark(x: .value("Day", day.date, unit: .day), y: .value("GB", diff),
                                    width: .ratio(0.6))
                                .foregroundStyle(diff >= 0 ? accent : Palette.yellow)
                                .cornerRadius(3)
                        }
                    }
                    RuleMark(y: .value("Zero", 0))
                        .foregroundStyle(Color.white.opacity(0.3))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
                .chartYAxis { gbAxis() }
                .chartXAxis { dayAxis() }
                .frame(height: 200)
                HStack(spacing: 16) {
                    DotLabel("Under budget", color: accent)
                    DotLabel("Over budget", color: Palette.yellow)
                }
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
            }

            RowGroup(rows: [
                RowGroup.Row(dot: accent, label: "Ahead", value: "100 MB+ under", dim: status != .ahead),
                RowGroup.Row(dot: Palette.skyBlue, label: "On pace", value: "Within 100 MB", dim: status != .onPace),
                RowGroup.Row(dot: Palette.yellow, label: "Behind", value: "100 MB+ over", dim: status != .behind),
            ])

            Explainer(title: "What is Pace?", paragraphs: [
                "Compares what you've used with what an even pace through the bundle would have used by now, counted to the minute.",
                "Ahead means you have data in hand, so your daily budget grows. Behind means it shrinks to make the bundle last.",
            ])
        }
    }

    private var sentence: String {
        guard let pace = figures.pace else {
            return "Enter how much you've used so far in Settings to see your pace."
        }
        switch figures.paceStatus {
        case .ahead: return "You've used \(DataFormat.string(pace)) less than an even pace would have by now."
        case .behind: return "You've used \(DataFormat.string(-pace)) more than an even pace would have by now."
        case .onPace, .unknown: return "You're within 100 MB of an even pace through your bundle."
        }
    }
}

// MARK: - Daily plan

private struct PlanPage: View {
    let figures: InsightFigures
    let editLimit: () -> Void

    var body: some View {
        let accent = Insight.plan.tint.accent
        let s = figures.snapshot
        let change = figures.planChange
        let bars: [(label: String, bytes: Int64, color: Color)] = [
            ("Even split of the bundle", figures.bundleAverage, Color.white.opacity(0.35)),
            ("Today's limit", s.dailyBudgetBytes, accent.opacity(0.55)),
            ("Used today", s.todayBytes, s.level.ringColors.last ?? accent),
            ("From tomorrow", s.recommendedFromTomorrowBytes, accent),
        ]
        let top = Double(max(bars.map(\.bytes).max() ?? 1, 1))

        VStack(alignment: .leading, spacing: 20) {
            Headline(caption: "From tomorrow",
                     figure: figureText(s.recommendedFromTomorrowBytes, font: FigureFont.page, unitFont: .title3)
                        + Text(" a day").font(.title3).foregroundColor(Theme.secondaryText)) {
                if abs(change) < 10 * 1_048_576 {
                    Text("About the same as today")
                } else {
                    Label("\(DataFormat.string(abs(change))) \(change > 0 ? "more" : "less") than today's limit",
                          systemImage: change > 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                }
            }

            Panel {
                ForEach(bars, id: \.label) { bar in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(bar.label).foregroundStyle(.white)
                            Spacer()
                            Text(DataFormat.string(bar.bytes))
                                .monospacedDigit()
                                .foregroundStyle(Theme.secondaryText)
                        }
                        .font(.subheadline)
                        GeometryReader { g in
                            Capsule()
                                .fill(bar.color)
                                .frame(width: max(g.size.width * Double(bar.bytes) / top, 8))
                        }
                        .frame(height: 18)
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                }
            }

            Button(action: editLimit) {
                Label("Change daily limit", systemImage: "slider.horizontal.3")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Capsule().fill(.white))
            }

            Explainer(title: "What is Daily plan?", paragraphs: figures.settings.useFixedBudget ? [
                "You've set your own daily limit, so it stays the same every day.",
                "From tomorrow shows what you could use each day and still make the bundle last, based on what's left now.",
            ] : [
                "Your daily budget is worked out each morning: data left ÷ days left. Use less today and tomorrow's budget grows; use more and it shrinks.",
                "From tomorrow is what's left after today, spread over the remaining days.",
            ])
        }
    }
}

// MARK: - Data left

private struct RemainingPage: View {
    let figures: InsightFigures

    var body: some View {
        let accent = Insight.remaining.tint.accent
        let s = figures.snapshot
        let series = figures.remainingSeries
        let values = series.map { Budget.gb(fromBytes: $0.bytes) }
        let low = values.min() ?? 0
        let high = values.max() ?? 1
        let pad = max((high - low) * 0.2, 0.5)
        let lastDay = Calendar.current.date(byAdding: .day, value: -1, to: Budget.endDate(figures.settings)) ?? Date()

        VStack(alignment: .leading, spacing: 20) {
            Headline(caption: "Data left",
                     figure: figureText(s.bundleRemainingBytes, font: FigureFont.page, unitFont: .title3)) {
                Text("of \(DataFormat.string(s.bundleBytes)) · \(s.daysLeft) \(s.daysLeft == 1 ? "day" : "days") left")
            }

            Panel {
                Chart {
                    ForEach(series) { p in
                        AreaMark(x: .value("Day", p.date, unit: .day),
                                 yStart: .value("Base", max(low - pad, 0)),
                                 yEnd: .value("GB", Budget.gb(fromBytes: p.bytes)))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(LinearGradient(colors: [accent.opacity(0.3), accent.opacity(0)],
                                                            startPoint: .top, endPoint: .bottom))
                        LineMark(x: .value("Day", p.date, unit: .day), y: .value("GB", Budget.gb(fromBytes: p.bytes)))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(accent)
                            .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                    }
                    if let last = series.last {
                        PointMark(x: .value("Day", last.date, unit: .day), y: .value("GB", Budget.gb(fromBytes: last.bytes)))
                            .foregroundStyle(accent)
                            .symbolSize(80)
                    }
                }
                .chartYScale(domain: max(low - pad, 0)...(high + pad))
                .chartYAxis { gbAxis() }
                .chartXAxis { dayAxis() }
                .frame(height: 240)
            }

            RowGroup(rows: [
                RowGroup.Row(label: "7-day average",
                             value: figures.recentAverage.map { "\(DataFormat.string($0)) a day" } ?? "—"),
                RowGroup.Row(label: "Lasts at that rate",
                             value: figures.daysOfDataLeft.map { "\($0) \($0 == 1 ? "day" : "days")" } ?? "—"),
                RowGroup.Row(label: "Bundle's last day", value: lastDay.formatted(date: .abbreviated, time: .omitted)),
            ])

            if let lasts = figures.daysOfDataLeft, let ok = figures.lastsTheBundle {
                Label(ok ? "At your recent rate your data outlasts the bundle."
                         : "At your recent rate your data runs out \(s.daysLeft - lasts) \(s.daysLeft - lasts == 1 ? "day" : "days") before the bundle ends.",
                      systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(ok ? accent : Palette.yellow)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Explainer(title: "What is Data left?", paragraphs: [
                "How much of your bundle remained at the end of each of the last 14 days. Each drop is a day's usage.",
                "The projection uses your average over the last 7 days, so a heavy or light week moves it.",
            ])
        }
    }
}
