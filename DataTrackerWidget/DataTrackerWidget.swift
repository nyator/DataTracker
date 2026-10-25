import SwiftUI
import WidgetKit

@main
struct DataTrackerWidgetBundle: WidgetBundle {
    var body: some Widget {
        DataTrackerWidget()
    }
}

struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot
}

struct UsageProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: Date(), snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
        } else {
            completion(UsageEntry(date: Date(), snapshot: UsageTracker.shared.snapshot()))
        }
    }

    /// Every timeline reload also takes a counter reading. That gives the
    /// tracker extra samples between background refreshes, which keeps gaps
    /// short enough to catch 32-bit wraps. Alerts are left to the app
    /// (`evaluateAlerts: false`), which posts the notifications.
    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        let now = Date()
        let current = UsageTracker.shared.refresh(evaluateAlerts: false).snapshot
        var entries = [UsageEntry(date: now, snapshot: current)]

        // Pre-render midnight, so the widget switches to the new day's (empty)
        // usage and budget even if iOS doesn't reload it right on time.
        let calendar = Calendar.current
        if let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) {
            entries.append(UsageEntry(date: midnight, snapshot: UsageTracker.shared.snapshot(at: midnight)))
        }

        // Ask for a reload in 30 minutes. iOS budgets widget reloads, so the
        // actual cadence varies (typically 15–60 minutes).
        let next = calendar.date(byAdding: .minute, value: 30, to: now) ?? now.addingTimeInterval(1800)
        completion(Timeline(entries: entries, policy: .after(next)))
    }
}

struct DataTrackerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: AppGroup.widgetKind, provider: UsageProvider()) { entry in
            UsageWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Data Today")
        .description("Today's mobile data usage and what's left of your budget.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

struct UsageWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UsageEntry

    private var s: UsageSnapshot { entry.snapshot }

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .systemMedium: medium
        default: small
        }
    }

    private var percentText: String { "\(Int((s.todayFraction * 100).rounded()))%" }

    private var remainingText: String {
        s.todayBytes > s.dailyBudgetBytes
            ? "\(DataFormat.string(s.todayBytes - s.dailyBudgetBytes)) over"
            : "\(DataFormat.string(s.todayRemainingBytes)) left"
    }

    private var small: some View {
        VStack(spacing: 6) {
            UsageRing(fraction: s.todayFraction, color: s.level.color, lineWidth: 9) {
                VStack(spacing: 0) {
                    Text(DataFormat.string(s.todayBytes))
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .minimumScaleFactor(0.7)
                    Text(percentText)
                        .font(.caption2)
                        .foregroundStyle(s.level.color)
                }
            }
            Text(remainingText)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private var medium: some View {
        HStack(spacing: 16) {
            UsageRing(fraction: s.todayFraction, color: s.level.color, lineWidth: 11) {
                VStack(spacing: 0) {
                    Text(DataFormat.string(s.todayBytes))
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .minimumScaleFactor(0.7)
                    Text("of \(DataFormat.string(s.dailyBudgetBytes))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .minimumScaleFactor(0.7)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                row("Today", remainingText, color: s.level.color)
                row("Bundle left", DataFormat.string(s.bundleRemainingBytes))
                row("Days left", "\(s.daysLeft)")
                if let last = s.lastSampleDate {
                    Text("Updated \(last, style: .time)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func row(_ title: String, _ value: String, color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(color).lineLimit(1)
        }
    }

    private var circular: some View {
        Gauge(value: min(s.todayFraction, 1)) {
            Image(systemName: "antenna.radiowaves.left.and.right")
        } currentValueLabel: {
            Text(percentText).minimumScaleFactor(0.6)
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetAccentable()
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Data today").font(.headline).widgetAccentable()
            Text("\(DataFormat.string(s.todayBytes)) / \(DataFormat.string(s.dailyBudgetBytes))")
            Text(remainingText).foregroundStyle(.secondary)
        }
        .font(.caption)
    }
}

#Preview(as: .systemSmall) {
    DataTrackerWidget()
} timeline: {
    UsageEntry(date: .now, snapshot: .sample)
}

#Preview(as: .systemMedium) {
    DataTrackerWidget()
} timeline: {
    UsageEntry(date: .now, snapshot: .sample)
}
