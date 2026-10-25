import Charts
import SwiftUI

/// Daily usage for the last 14 days. A bar turns red when it went over that
/// day's budget; today's bar takes the ring's colour. The dashed line is
/// today's budget (labelled in the card header, so it never covers a bar).
struct HistoryChart: View {
    let days: [UsageSnapshot.Day]
    let budgetBytes: Int64
    /// Today's bar matches the ring's colour, marking it as the day in progress.
    var todayColor: Color = .accentColor

    var body: some View {
        Chart {
            ForEach(days) { day in
                BarMark(
                    x: .value("Day", day.date, unit: .day),
                    y: .value("GB", Budget.gb(fromBytes: day.bytes))
                )
                .foregroundStyle(color(for: day))
                .cornerRadius(3)
            }
            if budgetBytes > 0 {
                RuleMark(y: .value("Budget", Budget.gb(fromBytes: budgetBytes)))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(.secondary)
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 2)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.day(), centered: true)
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let gb = value.as(Double.self) { Text("\(gb, specifier: "%.1f") GB") }
                }
            }
        }
    }

    private func color(for day: UsageSnapshot.Day) -> Color {
        if day.id == days.last?.id { return todayColor }
        return day.budgetBytes > 0 && day.bytes > day.budgetBytes ? .red : .accentColor
    }
}

#Preview {
    HistoryChart(days: UsageSnapshot.sample.history, budgetBytes: UsageSnapshot.sample.dailyBudgetBytes)
        .frame(height: 200)
        .padding()
}
