import Charts
import SwiftUI

/// Daily usage for the last 14 days, styled after the kit's weekly expenses
/// chart: past days are dim, today is lit in the ring's colour, and days that
/// went over their budget are pink. The dashed line is today's budget
/// (labelled in the card header, so the label never covers a bar).
struct HistoryChart: View {
    let days: [UsageSnapshot.Day]
    let budgetBytes: Int64
    /// Today's bar matches the ring's colour, marking it as the day in progress.
    var todayColor: Color = Theme.green

    var body: some View {
        Chart {
            ForEach(days) { day in
                BarMark(
                    x: .value("Day", day.date, unit: .day),
                    y: .value("GB", Budget.gb(fromBytes: day.bytes))
                )
                .foregroundStyle(style(for: day))
                .cornerRadius(4)
            }
            if budgetBytes > 0 {
                RuleMark(y: .value("Budget", Budget.gb(fromBytes: budgetBytes)))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 2)) { _ in
                AxisValueLabel(format: .dateTime.day(), centered: true)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.08))
                AxisValueLabel {
                    if let gb = value.as(Double.self) { Text("\(gb, specifier: "%.1f") GB") }
                }
                .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    private func style(for day: UsageSnapshot.Day) -> AnyShapeStyle {
        if day.id == days.last?.id {
            return AnyShapeStyle(LinearGradient(colors: [todayColor, todayColor.opacity(0.45)],
                                                startPoint: .top, endPoint: .bottom))
        }
        if day.budgetBytes > 0 && day.bytes > day.budgetBytes { return AnyShapeStyle(Theme.pink) }
        return AnyShapeStyle(Color.white.opacity(0.22))
    }
}

#Preview {
    HistoryChart(days: UsageSnapshot.sample.history, budgetBytes: UsageSnapshot.sample.dailyBudgetBytes)
        .frame(height: 200)
        .padding()
        .background(.black)
}
