import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var model: DashboardModel
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let s = model.snapshot
        // Two tiles per row normally; one per row at accessibility text sizes.
        let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: typeSize.isAccessibilitySize ? 1 : 2)
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

                if !model.settings.isSetUp {
                    SetupCard(skip: model.skipSetup)
                }

                TodayCard(snapshot: s)

                LazyVGrid(columns: columns, spacing: 12) {
                    StatTile(title: "Bundle used",
                             value: DataFormat.string(s.bundleUsedBytes),
                             detail: "of \(DataFormat.string(s.bundleBytes)) · \(Int((s.bundleFraction * 100).rounded()))%",
                             // Pace is meaningless until real usage so far has been entered.
                             note: model.settings.isSetUp ? PaceNote(paceBytes: s.paceBytes) : nil)
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
                    let title = Text("Last 14 days").font(.headline)
                    let legend = Label("Budget \(DataFormat.string(s.dailyBudgetBytes))", systemImage: "line.horizontal.3")
                        .labelStyle(BudgetLegendStyle())
                    // Side by side when they fit; stacked at large text sizes.
                    ViewThatFits(in: .horizontal) {
                        HStack {
                            title.fixedSize()
                            Spacer()
                            legend.fixedSize()
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            title
                            legend
                        }
                    }
                    HistoryChart(days: s.history, budgetBytes: s.dailyBudgetBytes, todayColor: s.level.color)
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

    /// Grows with the text size, capped so it still fits a phone's width.
    @ScaledMetric(relativeTo: .title) private var ringSize: CGFloat = 220

    var body: some View {
        let size = min(ringSize, 300)
        VStack(spacing: 12) {
            UsageRing(fraction: snapshot.todayFraction, color: snapshot.level.color, lineWidth: 18) {
                // Each line stays whole and shrinks to fit inside the ring rather than wrapping.
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
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(width: size * 0.68)
            }
            .frame(width: size, height: size)

            Text(statusLine)
                .font(.headline)
                .foregroundStyle(snapshot.level == .ok ? Color.primary : snapshot.level.color)
                .multilineTextAlignment(.center)
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
    var note: PaceNote? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            // Numbers never break mid-figure; they shrink a little instead.
            Text(value).font(.title3.weight(.semibold)).monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(detail).font(.caption2).foregroundStyle(.secondary)
            if let note, let text = note.text {
                Text(text).font(.caption2.weight(.semibold)).foregroundStyle(note.color)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        // Fill the row's height so tiles side by side match.
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

/// Whether bundle usage is ahead of or behind an even pace.
private struct PaceNote {
    let paceBytes: Int64?

    /// Within 100 MB either way counts as on pace.
    private static let tolerance: Int64 = 100 * 1_048_576

    var text: String? {
        guard let pace = paceBytes else { return nil }
        if abs(pace) < Self.tolerance { return "On pace" }
        return pace > 0 ? "\(DataFormat.string(pace)) under pace" : "\(DataFormat.string(-pace)) over pace"
    }

    var color: Color {
        guard let pace = paceBytes, abs(pace) >= Self.tolerance else { return .secondary }
        return pace > 0 ? .green : .orange
    }
}

/// First-run prompt: the counters can't see usage from before the app was
/// installed, so ask for the bundle's start date and usage so far.
private struct SetupCard: View {
    let skip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Set up your bundle", systemImage: "slider.horizontal.3")
                .font(.headline)
            Text("Enter when your bundle started and how much you've used so far (check with MTN, e.g. *138#). Until then, totals only count data used since you installed the app.")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                NavigationLink {
                    SettingsView()
                } label: {
                    Text("Set up").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button(action: skip) {
                    Text("Skip").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
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
