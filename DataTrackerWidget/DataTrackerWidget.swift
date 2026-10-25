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
                .containerBackground(for: .widget) {
                    // Near-black with a glow in today's status colour (green / orange / pink).
                    GlowBackground(color: entry.snapshot.level.color, from: .top, radius: 220)
                }
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
        UsageRing(fraction: s.todayFraction, color: s.level.color, lineWidth: 10) {
            VStack(spacing: 2) {
                Text("Today")
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryText)
                figureText(s.todayBytes, font: .system(.title3).weight(.medium), unitFont: .caption2)
                    .monospacedDigit()
                Text(remainingText)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(s.level.color)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 14)
        }
        .environment(\.colorScheme, .dark)
    }

    private var medium: some View {
        HStack(spacing: 16) {
            UsageRing(fraction: s.todayFraction, color: s.level.color, lineWidth: 10) {
                VStack(spacing: 2) {
                    Text("Used today")
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryText)
                    figureText(s.todayBytes, font: .system(.title3).weight(.medium), unitFont: .caption2)
                        .monospacedDigit()
                    Text("of \(DataFormat.string(s.dailyBudgetBytes))")
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryText)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 12)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(remainingText + " today")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(s.level.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Bundle")
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryText)
                    figureText(s.bundleRemainingBytes, font: .headline.weight(.medium), unitFont: .caption2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    TickMeter(fraction: s.bundleFraction, color: Theme.lime, segments: 20, height: 14)
                    Text("left · \(s.daysLeft) \(s.daysLeft == 1 ? "day" : "days")")
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .environment(\.colorScheme, .dark)
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
