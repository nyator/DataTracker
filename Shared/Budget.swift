import Foundation

/// Budget arithmetic. Pure functions, so they're easy to test.
enum Budget {
    /// MTN (like most carriers) bills 1 GB as 1024 MB, so binary units are used throughout.
    static let bytesPerGB: Double = 1_073_741_824

    static func bytes(fromGB gb: Double) -> Int64 { Int64((max(gb, 0) * bytesPerGB).rounded()) }
    static func gb(fromBytes bytes: Int64) -> Double { Double(bytes) / bytesPerGB }

    /// First day *after* the bundle ends (exclusive end).
    static func endDate(_ settings: BudgetSettings, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: settings.startDate)
        return calendar.date(byAdding: .day, value: max(settings.durationDays, 0), to: start) ?? start
    }

    /// Days remaining including today. 0 once the bundle period is over.
    /// A start date in the future counts the full duration.
    static func daysLeft(_ settings: BudgetSettings, now: Date, calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: settings.startDate)
        let today = calendar.startOfDay(for: now)
        if today < start { return max(settings.durationDays, 0) }
        let days = calendar.dateComponents([.day], from: today, to: endDate(settings, calendar: calendar)).day ?? 0
        return max(days, 0)
    }

    /// Today's budget.
    ///
    /// Adaptive mode: data left at the *start* of today ÷ days left including
    /// today. Using the start-of-day figure keeps the budget steady during the
    /// day, so using data today doesn't shrink today's target as you go.
    /// Under-use yesterday raises today's budget; over-use lowers it.
    static func dailyBudget(_ settings: BudgetSettings, bundleUsed: Int64, todayUsed: Int64,
                            now: Date, calendar: Calendar = .current) -> Int64 {
        if settings.useFixedBudget { return bytes(fromGB: settings.fixedDailyBudgetGB) }
        let days = daysLeft(settings, now: now, calendar: calendar)
        guard days > 0 else { return 0 }
        let usedBeforeToday = max(bundleUsed - todayUsed, 0)
        let remaining = max(bytes(fromGB: settings.bundleSizeGB) - usedBeforeToday, 0)
        return remaining / Int64(days)
    }

    /// What's left after today's usage, spread over the days after today.
    static func recommendedFromTomorrow(_ settings: BudgetSettings, bundleUsed: Int64,
                                        now: Date, calendar: Calendar = .current) -> Int64 {
        let remaining = max(bytes(fromGB: settings.bundleSizeGB) - bundleUsed, 0)
        let daysAfterToday = daysLeft(settings, now: now, calendar: calendar) - 1
        return daysAfterToday > 0 ? remaining / Int64(daysAfterToday) : remaining
    }

    /// How far usage is from an even pace through the bundle. Positive means
    /// under pace (data in hand), negative means over. Nil outside the bundle period.
    ///
    /// "Even pace" counts time to the second: at noon on day 29 of 90,
    /// 28.5/90 of the bundle is expected to be used. So it doesn't jump by a
    /// whole day's budget at midnight.
    static func pace(_ settings: BudgetSettings, bundleUsed: Int64,
                     now: Date, calendar: Calendar = .current) -> Int64? {
        let start = calendar.startOfDay(for: settings.startDate)
        let end = endDate(settings, calendar: calendar)
        guard now >= start, now < end else { return nil }
        let fraction = now.timeIntervalSince(start) / end.timeIntervalSince(start)
        let expected = Int64(Double(bytes(fromGB: settings.bundleSizeGB)) * fraction)
        return expected - bundleUsed
    }

    /// Thresholds that today's usage has reached but that haven't alerted yet.
    static func newlyCrossedThresholds(todayUsed: Int64, budget: Int64,
                                       thresholds: [Int], alreadyAlerted: [Int]) -> [Int] {
        guard budget > 0 else { return [] }
        let percent = Double(todayUsed) / Double(budget) * 100
        return thresholds.filter { Double($0) <= percent && !alreadyAlerted.contains($0) }
    }
}

enum DataFormat {
    /// "1.84 GB" for 1 GB and above, "312 MB" below.
    static func string(_ bytes: Int64) -> String {
        let gb = Budget.gb(fromBytes: bytes)
        if abs(gb) >= 1 { return String(format: "%.2f GB", gb) }
        return String(format: "%.0f MB", Double(bytes) / 1_048_576)
    }
}
