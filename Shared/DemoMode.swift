#if DEBUG
import Foundation

/// Debug builds only: launch with `-demoData` to see the app with realistic
/// numbers in the Simulator, which has no cellular interface.
/// (Xcode: Product → Scheme → Edit Scheme → Run → Arguments → add `-demoData`.)
///
/// Replaces the stored state with 13 days of history plus 1.95 GB today
/// (just under the 80% alert), then feeds fake counters that grow by 25 MB
/// per reading, so the first refresh crosses 80% and posts the alert.
enum DemoMode {
    static let isOn = ProcessInfo.processInfo.arguments.contains("-demoData")

    private static let bootTime = Date(timeIntervalSinceNow: -86_400)
    private static var rx: UInt32 = 3_000_000_000
    private static let lock = NSLock()

    static func makeTracker() -> UsageTracker {
        let store = UsageStore.shared
        seed(store)
        return UsageTracker(store: store, readCounters: reading)
    }

    private static func reading() -> CounterReading {
        lock.lock()
        defer { lock.unlock() }
        // Grows past 2^32 after a few dozen readings, exercising the wrap path too.
        rx = rx &+ 25 * 1_048_576
        return CounterReading(counters: ["pdp_ip0.rx": rx, "pdp_ip0.tx": 40_000_000],
                              bootTime: bootTime, uptime: ProcessInfo.processInfo.systemUptime, date: Date())
    }

    private static func seed(_ store: UsageStore) {
        let calendar = Calendar.current
        let now = Date()
        let gb = Budget.bytesPerGB

        var settings = BudgetSettings()
        settings.startDate = calendar.date(byAdding: .day, value: -28, to: calendar.startOfDay(for: now))!
        store.saveSettings(settings)

        var state = TrackerState()
        let pattern = [1.8, 2.6, 2.1, 1.2, 3.0, 2.2, 1.9, 2.4, 0.9, 2.8, 2.0, 1.5, 2.3]
        for (i, usedGB) in pattern.enumerated() {
            let day = calendar.date(byAdding: .day, value: i - pattern.count, to: now)!
            state.days[DayMath.key(for: day)] = DayRecord(bytes: Int64(usedGB * gb), budgetBytes: Int64(2.4 * gb))
        }
        let todayBytes = Int64(1.95 * gb)
        state.days[DayMath.key(for: now)] = DayRecord(bytes: todayBytes, budgetBytes: 0)
        state.bundleUsedBytes = Int64(64.8 * gb) + todayBytes
        state.lastCounters = ["pdp_ip0.rx": rx, "pdp_ip0.tx": 40_000_000]
        state.lastSampleDate = now.addingTimeInterval(-300)
        state.lastBootTime = bootTime
        state.lastUptime = ProcessInfo.processInfo.systemUptime - 300
        TrackerEngine.recordBudget(in: &state, settings: settings, now: now)
        store.saveState(state)
    }
}
#endif
