import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var model: DashboardModel

    var body: some View {
        let s = model.snapshot
        ScrollView {
            VStack(spacing: 16) {
                if !s.hasCellularInterface {
                    NoticeCard(systemImage: "antenna.radiowaves.left.and.right.slash",
                               text: "No cellular interface found. Usage is only measured on an iPhone with mobile data.")
                }
                if s.daysLeft == 0 && !model.settings.useFixedBudget {
                    NoticeCard(systemImage: "calendar.badge.exclamationmark",
                               text: "This bundle's period has ended. Start a new bundle in Settings.")
                }

                TodayCard(snapshot: s)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    StatTile(title: "Bundle used",
                             value: DataFormat.string(s.bundleUsedBytes),
                             detail: "of \(DataFormat.string(s.bundleBytes)) · \(Int((s.bundleFraction * 100).rounded()))%")
                    StatTile(title: "Bundle left",
                             value: DataFormat.string(s.bundleRemainingBytes),
                             detail: "\(s.daysLeft) \(s.daysLeft == 1 ? "day" : "days") left")
                    StatTile(title: "Today's budget",
                             value: DataFormat.string(s.dailyBudgetBytes),
                             detail: model.settings.useFixedBudget ? "Fixed" : "Adapts daily")
                    StatTile(title: "From tomorrow",
                             value: DataFormat.string(s.recommendedFromTomorrowBytes),
                             detail: "Recommended per day")
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Last 14 days").font(.headline)
                        Spacer()
                        Label("Budget \(DataFormat.string(s.dailyBudgetBytes))", systemImage: "line.horizontal.3")
                            .labelStyle(BudgetLegendStyle())
                    }
                    HistoryChart(days: s.history, budgetBytes: s.dailyBudgetBytes)
                        .frame(height: 200)
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))

                Footer(lastSample: s.lastSampleDate)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .refreshable { model.refresh() }
    }
}

private struct TodayCard: View {
    let snapshot: UsageSnapshot

    var body: some View {
        VStack(spacing: 12) {
            UsageRing(fraction: snapshot.todayFraction, color: snapshot.level.color, lineWidth: 18) {
                VStack(spacing: 2) {
                    Text(DataFormat.string(snapshot.todayBytes))
                        .font(.system(.title, design: .rounded).weight(.bold))
                        .monospacedDigit()
                    Text("of \(DataFormat.string(snapshot.dailyBudgetBytes)) today")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("\(Int((snapshot.todayFraction * 100).rounded()))%")
                        .font(.headline)
                        .foregroundStyle(snapshot.level.color)
                }
            }
            .frame(width: 220, height: 220)

            Text(statusLine)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var statusLine: String {
        if snapshot.todayBytes > snapshot.dailyBudgetBytes {
            return "\(DataFormat.string(snapshot.todayBytes - snapshot.dailyBudgetBytes)) over today's budget"
        }
        return "\(DataFormat.string(snapshot.todayRemainingBytes)) left today"
    }
}

private struct StatTile: View {
    let title: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold)).monospacedDigit()
            Text(detail).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

/// A short dashed line + text, matching the budget line in the chart.
private struct BudgetLegendStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            Path { p in
                p.move(to: CGPoint(x: 0, y: 0.5))
                p.addLine(to: CGPoint(x: 16, y: 0.5))
            }
            .stroke(.secondary, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            .frame(width: 16, height: 1)
            configuration.title
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

private struct NoticeCard: View {
    let systemImage: String
    let text: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct Footer: View {
    let lastSample: Date?

    var body: some View {
        VStack(spacing: 4) {
            if let lastSample {
                Text("Updated \(lastSample.formatted(.relative(presentation: .named)))")
            }
            Text("Background updates run when iOS allows, roughly every 1–3 hours.")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
}

#Preview {
    NavigationStack { DashboardView() }
        .environmentObject(DashboardModel())
}
