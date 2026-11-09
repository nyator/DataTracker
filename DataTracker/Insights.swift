import Foundation

/// The cards in the dashboard's Insights grid, in display order. Each opens a
/// detail page; the pages can be swiped through in the same order.
enum Insight: Int, CaseIterable, Identifiable {
    case trend, bundle, calendar, pace, plan, remaining

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .trend: return "Trend"
        case .bundle: return "Bundle"
        case .calendar: return "Calendar"
        case .pace: return "Pace"
        case .plan: return "Daily plan"
        case .remaining: return "Data left"
        }
    }

    var icon: String {
        switch self {
        case .trend: return "chart.line.uptrend.xyaxis"
        case .bundle: return "chart.pie"
        case .calendar: return "calendar"
        case .pace: return "gauge.with.dots.needle.50percent"
        case .plan: return "arrow.left.arrow.right"
        case .remaining: return "simcard"
        }
    }
}

/// Figures behind the Insights cards and pages, all derived from a snapshot
/// and the settings. Pure, so previews and the pager can build them freely.
struct InsightFigures {
    typealias Day = UsageSnapshot.Day

    let snapshot: UsageSnapshot
    let settings: BudgetSettings

    /// Within 100 MB either way counts as on pace.
    static let tolerance: Int64 = 100 * 1_048_576

    var days: [Day] { snapshot.history }
    var today: Day? { snapshot.history.last }
    /// Complete days before today, oldest first.
    var pastDays: ArraySlice<Day> { snapshot.history.dropLast() }

    func isToday(_ day: Day) -> Bool { day.id == today?.id }

    /// The budget that applied on `day`, or nil if none was recorded (before the app was installed).
    func budget(on day: Day) -> Int64? {
        let b = isToday(day) ? snapshot.dailyBudgetBytes : day.budgetBytes
        return b > 0 ? b : nil
    }

    func isOver(_ day: Day) -> Bool {
        guard let b = budget(on: day) else { return false }
        return day.bytes > b
    }

    // MARK: Trend

    /// Average of the last 7 complete days.
    var recentAverage: Int64? { Self.average(pastDays.suffix(7)) }
    /// Average of the complete days before those.
    var earlierAverage: Int64? { Self.average(pastDays.dropLast(7)) }

    /// Change from the earlier average to the recent one, in percent.
    var trendPercent: Int? {
        guard let recent = recentAverage, let earlier = earlierAverage, earlier > 0 else { return nil }
        return Int(((Double(recent) - Double(earlier)) / Double(earlier) * 100).rounded())
    }

    enum Direction { case up, down, steady, unknown }

    var trendDirection: Direction {
        guard let p = trendPercent else { return .unknown }
        if abs(p) < 5 { return .steady }
        return p > 0 ? .up : .down
    }

    /// Days with no usage are left out: they're almost always days before the
    /// app was installed, and would drag the average down.
    private static func average<C: Collection>(_ days: C) -> Int64? where C.Element == Day {
        let used = days.filter { $0.bytes > 0 }
        guard !used.isEmpty else { return nil }
        return used.reduce(0) { $0 + $1.bytes } / Int64(used.count)
    }

    // MARK: Calendar

    var fortnightTotal: Int64 { days.reduce(0) { $0 + $1.bytes } }
    var daysOver: Int { days.filter(isOver).count }

    // MARK: Pace

    enum PaceStatus {
        case ahead, onPace, behind, unknown

        var label: String {
            switch self {
            case .ahead: return "Ahead"
            case .onPace: return "On pace"
            case .behind: return "Behind"
            case .unknown: return "Not set up"
            }
        }
    }

    /// Meaningless until real usage so far has been entered, so nil until then.
    var pace: Int64? { settings.isSetUp ? snapshot.paceBytes : nil }

    var paceStatus: PaceStatus {
        guard let pace else { return .unknown }
        if abs(pace) < Self.tolerance { return .onPace }
        return pace > 0 ? .ahead : .behind
    }

    /// Where the gauge's knob sits: 0 is far behind, 0.5 on pace, 1 far ahead.
    /// Measured in days of budget, so ±3 days' worth reaches the ends.
    var paceGaugePosition: Double {
        guard let pace, snapshot.dailyBudgetBytes > 0 else { return 0.5 }
        let daysWorth = Double(pace) / Double(snapshot.dailyBudgetBytes)
        return min(max(0.5 + daysWorth / 6, 0), 1)
    }

    /// What an even pace would have used by now.
    var expectedUsed: Int64? { pace.map { max(snapshot.bundleUsedBytes + $0, 0) } }

    // MARK: Daily plan

    /// The bundle spread evenly over its whole period.
    var bundleAverage: Int64 {
        settings.durationDays > 0 ? snapshot.bundleBytes / Int64(settings.durationDays) : 0
    }

    /// From tomorrow's amount minus today's budget: positive means tomorrow gets more.
    var planChange: Int64 { snapshot.recommendedFromTomorrowBytes - snapshot.dailyBudgetBytes }

    // MARK: Data left

    struct Point: Identifiable {
        var id: Date { date }
        let date: Date
        let bytes: Int64
    }

    /// Data left at the end of each day in the history, worked back from now.
    var remainingSeries: [Point] {
        var after: Int64 = 0
        var points: [Point] = []
        for day in days.reversed() {
            let left = min(snapshot.bundleRemainingBytes + after, snapshot.bundleBytes)
            points.append(Point(date: day.date, bytes: left))
            after += day.bytes
        }
        return points.reversed()
    }

    /// How many days the data left lasts at the recent average.
    var daysOfDataLeft: Int? {
        guard let avg = recentAverage, avg > 0 else { return nil }
        return Int(snapshot.bundleRemainingBytes / avg)
    }

    /// True when the data left outlasts the bundle at the recent average.
    var lastsTheBundle: Bool? {
        daysOfDataLeft.map { $0 >= snapshot.daysLeft }
    }
}
