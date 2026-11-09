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
                    // Near-black with a wash in today's status colour (blue / orange / pink).
                    WashBackground(color: entry.snapshot.level.wash)
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
        s.isOverToday
            ? "\(DataFormat.string(s.todayBytes - s.dailyBudgetBytes)) over"
            : "\(DataFormat.string(s.todayRemainingBytes)) left"
    }

    /// The dashboard's ring: drains through the day, refills in pink once over.
    private var ring: some View {
        HeroRing(fraction: s.ringFraction, colors: s.level.ringColors, lineWidth: 11, dotCount: 28) {
            VStack(spacing: 1) {
                figureText(s.ringFigureBytes, font: .system(.title3).weight(.bold), unitFont: .caption2.weight(.semibold))
                    .monospacedDigit()
                Text(s.isOverToday ? "over today" : "left today")
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryText)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 26)
        }
    }

    private var small: some View {
        ring
            .environment(\.colorScheme, .dark)
    }

    private var medium: some View {
        HStack(spacing: 18) {
            ring
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Circle().fill(s.level.ringColors.last ?? .white).frame(width: 7, height: 7)
                    Text(s.level.label)
                }
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.white.opacity(0.1)))

                stat("Used today", s.todayBytes, suffix: "of \(DataFormat.string(s.dailyBudgetBytes))")

                VStack(alignment: .leading, spacing: 5) {
                    stat("Bundle left", s.bundleRemainingBytes,
                         suffix: "\(s.daysLeft) \(s.daysLeft == 1 ? "day" : "days")")
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.12))
                            Capsule().fill(Palette.teal)
                                .frame(width: max(g.size.width * (1 - min(s.bundleFraction, 1)), 6))
                        }
                    }
                    .frame(height: 6)
                }
            }
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .environment(\.colorScheme, .dark)
    }

    private func stat(_ label: String, _ bytes: Int64, suffix: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.secondaryText)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                figureText(bytes, font: .headline.weight(.bold), unitFont: .caption2)
                    .monospacedDigit()
                Text(suffix)
                    .font(.caption2)
                    .foregroundStyle(Theme.tertiaryText)
            }
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
