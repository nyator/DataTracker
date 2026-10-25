import Foundation

/// One reading of the cellular counters plus the clocks needed to interpret it.
struct CounterReading {
    var counters: [String: UInt32]
    var bootTime: Date?
    /// Monotonic seconds since boot.
    var uptime: TimeInterval
    var date: Date

    static func current() -> CounterReading {
        CounterReading(counters: CellularCounters.read(),
                       bootTime: CellularCounters.bootTime(),
                       uptime: ProcessInfo.processInfo.systemUptime,
                       date: Date())
    }
}

/// Pure state transitions on `TrackerState`. There is no I/O here, so every
/// rule is unit-tested in DataTrackerTests.
enum TrackerEngine {
    /// How many days of history to keep.
    static let historyRetentionDays = 120

    /// Adds the usage since the previous reading to the stored totals.
    ///
    /// The raw counters are never treated as a total. Only the *difference*
    /// between consecutive readings is added to `bundleUsedBytes` and to the
    /// per-day records, so the stored totals survive wraps and reboots.
    static func ingest(_ reading: CounterReading, into state: inout TrackerState,
                       settings: BudgetSettings, calendar: Calendar = .current) {
        if let lastDate = state.lastSampleDate {
            let rebooted = CounterMath.didReboot(lastBoot: state.lastBootTime, currentBoot: reading.bootTime,
                                                 lastUptime: state.lastUptime, currentUptime: reading.uptime)
            // After a reboot the old readings mean nothing; every counter starts fresh.
            let delta = CounterMath.totalDelta(previous: rebooted ? [:] : state.lastCounters,
                                               current: reading.counters, rebooted: rebooted)

            // After a reboot the bytes were used since boot, not since the last reading.
            var from = lastDate
            if rebooted, let boot = reading.bootTime, boot > lastDate { from = boot }

            let startKey = DayMath.key(for: settings.startDate, calendar: calendar)
            for (dayKey, bytes) in DayMath.split(bytes: delta, from: from, to: reading.date, calendar: calendar) {
                state.days[dayKey, default: DayRecord()].bytes += bytes
                if dayKey >= startKey { state.bundleUsedBytes += bytes }
            }
        }
        // With no previous reading (first launch) this reading only sets the
        // baseline: we can't know when the bytes already on the counters were
        // used. Use "Set used so far" in Settings to enter the bundle's usage
        // up to now.

        state.lastCounters = reading.counters
        state.lastSampleDate = reading.date
        state.lastBootTime = reading.bootTime
        state.lastUptime = reading.uptime

        recordBudget(in: &state, settings: settings, now: reading.date, calendar: calendar)
        prune(&state, now: reading.date, calendar: calendar)
    }

    /// Stores today's budget on today's record (and fills in any earlier day that
    /// has none yet), so the history chart can show over/under per day.
    static func recordBudget(in state: inout TrackerState, settings: BudgetSettings,
                             now: Date, calendar: Calendar = .current) {
        let todayKey = DayMath.key(for: now, calendar: calendar)
        let budget = Budget.dailyBudget(settings, bundleUsed: state.bundleUsedBytes,
                                        todayUsed: state.days[todayKey]?.bytes ?? 0, now: now, calendar: calendar)
        state.days[todayKey, default: DayRecord()].budgetBytes = budget
        for (key, record) in state.days where record.budgetBytes == 0 {
            state.days[key]?.budgetBytes = budget
        }
    }

    /// Returns thresholds to alert on now, and marks them as sent for today.
    /// The sent-list belongs to one day. When the day changes it starts empty,
    /// so each threshold fires at most once per day.
    static func takeAlerts(from state: inout TrackerState, settings: BudgetSettings,
                           now: Date, calendar: Calendar = .current) -> [Int] {
        let todayKey = DayMath.key(for: now, calendar: calendar)
        if state.alertDayKey != todayKey {
            state.alertDayKey = todayKey
            state.alertedThresholds = []
        }
        let today = state.days[todayKey]?.bytes ?? 0
        let budget = Budget.dailyBudget(settings, bundleUsed: state.bundleUsedBytes,
                                        todayUsed: today, now: now, calendar: calendar)
        let crossed = Budget.newlyCrossedThresholds(todayUsed: today, budget: budget,
                                                    thresholds: settings.thresholds,
                                                    alreadyAlerted: state.alertedThresholds)
        state.alertedThresholds += crossed
        return crossed
    }

    static func snapshot(of state: TrackerState, settings: BudgetSettings,
                         now: Date, calendar: Calendar = .current) -> UsageSnapshot {
        let todayKey = DayMath.key(for: now, calendar: calendar)
        let todayBytes = state.days[todayKey]?.bytes ?? 0
        let budget = Budget.dailyBudget(settings, bundleUsed: state.bundleUsedBytes,
                                        todayUsed: todayBytes, now: now, calendar: calendar)
        let today = calendar.startOfDay(for: now)
        let history: [UsageSnapshot.Day] = (0..<14).compactMap { i in
            guard let date = calendar.date(byAdding: .day, value: i - 13, to: today) else { return nil }
            let key = DayMath.key(for: date, calendar: calendar)
            let record = state.days[key] ?? DayRecord()
            return UsageSnapshot.Day(key: key, date: date, bytes: record.bytes,
                                     budgetBytes: key == todayKey ? budget : record.budgetBytes)
        }
        return UsageSnapshot(
            date: now,
            todayBytes: todayBytes,
            dailyBudgetBytes: budget,
            bundleBytes: Budget.bytes(fromGB: settings.bundleSizeGB),
            bundleUsedBytes: state.bundleUsedBytes,
            daysLeft: Budget.daysLeft(settings, now: now, calendar: calendar),
            recommendedFromTomorrowBytes: Budget.recommendedFromTomorrow(settings, bundleUsed: state.bundleUsedBytes,
                                                                         now: now, calendar: calendar),
            warningPercent: settings.warningPercent,
            limitPercent: settings.limitPercent,
            history: history,
            lastSampleDate: state.lastSampleDate,
            hasCellularInterface: !state.lastCounters.isEmpty
        )
    }

    static func prune(_ state: inout TrackerState, now: Date, calendar: Calendar = .current) {
        guard let cutoff = calendar.date(byAdding: .day, value: -historyRetentionDays, to: now) else { return }
        let cutoffKey = DayMath.key(for: cutoff, calendar: calendar)
        state.days = state.days.filter { $0.key >= cutoffKey }
    }
}
