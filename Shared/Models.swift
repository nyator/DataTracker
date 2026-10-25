import Foundation

/// User-configurable bundle and alert settings.
struct BudgetSettings: Codable, Equatable {
    var bundleSizeGB: Double = 217
    var startDate: Date = Calendar.current.startOfDay(for: Date())
    var durationDays: Int = 90
    /// First alert, as a percentage of today's budget.
    var warningPercent: Int = 80
    /// Second alert, as a percentage of today's budget.
    var limitPercent: Int = 100
    /// When false the daily budget adapts: remaining data ÷ days left.
    var useFixedBudget: Bool = false
    var fixedDailyBudgetGB: Double = 2.4

    init() {}

    // Decoded field by field with defaults, so adding settings in a later
    // version never wipes what's already saved.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = BudgetSettings()
        bundleSizeGB = try c.decodeIfPresent(Double.self, forKey: .bundleSizeGB) ?? d.bundleSizeGB
        startDate = try c.decodeIfPresent(Date.self, forKey: .startDate) ?? d.startDate
        durationDays = try c.decodeIfPresent(Int.self, forKey: .durationDays) ?? d.durationDays
        warningPercent = try c.decodeIfPresent(Int.self, forKey: .warningPercent) ?? d.warningPercent
        limitPercent = try c.decodeIfPresent(Int.self, forKey: .limitPercent) ?? d.limitPercent
        useFixedBudget = try c.decodeIfPresent(Bool.self, forKey: .useFixedBudget) ?? d.useFixedBudget
        fixedDailyBudgetGB = try c.decodeIfPresent(Double.self, forKey: .fixedDailyBudgetGB) ?? d.fixedDailyBudgetGB
    }

    /// The alert thresholds in ascending order, without duplicates.
    var thresholds: [Int] { Array(Set([warningPercent, limitPercent])).sorted() }
}

/// Usage recorded for one calendar day.
struct DayRecord: Codable, Equatable {
    var bytes: Int64 = 0
    /// The daily budget that applied on that day (for coloring history bars).
    var budgetBytes: Int64 = 0
}

/// Everything the tracker accumulates. Stored as one JSON blob so a save is
/// all-or-nothing.
struct TrackerState: Codable, Equatable {
    /// Raw counters at the last reading, keyed like `"pdp_ip0.rx"`.
    var lastCounters: [String: UInt32] = [:]
    var lastSampleDate: Date?
    var lastBootTime: Date?
    var lastUptime: TimeInterval?

    /// Bytes used since the bundle started (or since the last manual correction).
    var bundleUsedBytes: Int64 = 0

    /// Per-day usage keyed by local date, `"yyyy-MM-dd"`. Today's usage is the
    /// entry for today's key, so midnight rollover needs no reset step: a new day
    /// simply starts a new, empty entry, and yesterday's stays as history.
    var days: [String: DayRecord] = [:]

    /// Which day `alertedThresholds` refers to. When the day changes the list is
    /// cleared, so each threshold alerts at most once per day.
    var alertDayKey: String?
    var alertedThresholds: [Int] = []

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lastCounters = try c.decodeIfPresent([String: UInt32].self, forKey: .lastCounters) ?? [:]
        lastSampleDate = try c.decodeIfPresent(Date.self, forKey: .lastSampleDate)
        lastBootTime = try c.decodeIfPresent(Date.self, forKey: .lastBootTime)
        lastUptime = try c.decodeIfPresent(TimeInterval.self, forKey: .lastUptime)
        bundleUsedBytes = try c.decodeIfPresent(Int64.self, forKey: .bundleUsedBytes) ?? 0
        days = try c.decodeIfPresent([String: DayRecord].self, forKey: .days) ?? [:]
        alertDayKey = try c.decodeIfPresent(String.self, forKey: .alertDayKey)
        alertedThresholds = try c.decodeIfPresent([Int].self, forKey: .alertedThresholds) ?? []
    }
}

/// A read-only view of the numbers the UI and widget display.
struct UsageSnapshot: Equatable {
    struct Day: Equatable, Identifiable {
        var id: String { key }
        let key: String
        let date: Date
        let bytes: Int64
        let budgetBytes: Int64
    }

    var date: Date
    var todayBytes: Int64
    var dailyBudgetBytes: Int64
    var bundleBytes: Int64
    var bundleUsedBytes: Int64
    /// Days left in the bundle, including today.
    var daysLeft: Int
    /// What's left after today, spread over the days after today.
    var recommendedFromTomorrowBytes: Int64
    var warningPercent: Int
    var limitPercent: Int
    /// The last 14 days, oldest first, today last.
    var history: [Day]
    var lastSampleDate: Date?
    /// False when no pdp_ip interface exists (Simulator, or no cellular hardware).
    var hasCellularInterface: Bool

    var bundleRemainingBytes: Int64 { max(bundleBytes - bundleUsedBytes, 0) }
    var todayRemainingBytes: Int64 { max(dailyBudgetBytes - todayBytes, 0) }

    /// Fraction of today's budget used (can exceed 1).
    var todayFraction: Double {
        dailyBudgetBytes > 0 ? Double(todayBytes) / Double(dailyBudgetBytes) : (todayBytes > 0 ? 1 : 0)
    }

    var bundleFraction: Double {
        bundleBytes > 0 ? Double(bundleUsedBytes) / Double(bundleBytes) : 0
    }

    enum Level { case ok, warning, over }
    var level: Level {
        let percent = todayFraction * 100
        if percent >= Double(limitPercent) { return .over }
        if percent >= Double(warningPercent) { return .warning }
        return .ok
    }

    /// Plausible-looking numbers for previews and the widget gallery.
    static var sample: UsageSnapshot {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let gb = Budget.bytesPerGB
        let history: [Day] = (0..<14).map { i in
            let date = cal.date(byAdding: .day, value: i - 13, to: today)!
            let bytes = Int64(gb * [1.8, 2.6, 2.1, 1.2, 3.0, 2.2, 1.9, 2.4, 0.9, 2.8, 2.0, 1.5, 2.3, 1.6][i])
            return Day(key: DayMath.key(for: date), date: date, bytes: bytes, budgetBytes: Int64(gb * 2.4))
        }
        return UsageSnapshot(date: Date(), todayBytes: Int64(gb * 1.6), dailyBudgetBytes: Int64(gb * 2.4),
                             bundleBytes: Int64(gb * 217), bundleUsedBytes: Int64(gb * 68.4), daysLeft: 62,
                             recommendedFromTomorrowBytes: Int64(gb * 2.43), warningPercent: 80, limitPercent: 100,
                             history: history, lastSampleDate: Date(), hasCellularInterface: true)
    }
}
