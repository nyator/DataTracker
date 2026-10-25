import Foundation

/// Entry point used by the app, the background task, and the widget.
final class UsageTracker {
    static let shared: UsageTracker = {
        #if DEBUG
        if DemoMode.isOn { return DemoMode.makeTracker() }
        #endif
        return UsageTracker()
    }()

    struct RefreshResult {
        let snapshot: UsageSnapshot
        /// Thresholds (percent) crossed for the first time today. Empty unless
        /// `refresh(evaluateAlerts: true)`.
        let newAlerts: [Int]
    }

    let store: UsageStore
    private let readCounters: () -> CounterReading
    private let calendar: Calendar

    init(store: UsageStore = .shared,
         readCounters: @escaping () -> CounterReading = CounterReading.current,
         calendar: Calendar = .current) {
        self.store = store
        self.readCounters = readCounters
        self.calendar = calendar
    }

    /// Reads the counters, adds the usage since the last reading to the stored
    /// totals, and returns fresh numbers.
    ///
    /// - Parameter evaluateAlerts: Pass true only from code that will actually
    ///   post the notifications (the app). Thresholds returned here are marked
    ///   as sent, so the widget passes false to avoid using them up.
    @discardableResult
    func refresh(evaluateAlerts: Bool) -> RefreshResult {
        store.withLock {
            let settings = store.loadSettings()
            var state = store.loadState()
            let reading = readCounters()

            TrackerEngine.ingest(reading, into: &state, settings: settings, calendar: calendar)
            let alerts = evaluateAlerts
                ? TrackerEngine.takeAlerts(from: &state, settings: settings, now: reading.date, calendar: calendar)
                : []
            store.saveState(state)

            return RefreshResult(snapshot: TrackerEngine.snapshot(of: state, settings: settings,
                                                                  now: reading.date, calendar: calendar),
                                 newAlerts: alerts)
        }
    }

    /// Current numbers without taking a new reading. The widget uses this for
    /// its future (midnight) timeline entry.
    func snapshot(at date: Date = Date()) -> UsageSnapshot {
        TrackerEngine.snapshot(of: store.loadState(), settings: store.loadSettings(), now: date, calendar: calendar)
    }

    var settings: BudgetSettings { store.loadSettings() }

    func updateSettings(_ settings: BudgetSettings) {
        store.withLock {
            store.saveSettings(settings)
            var state = store.loadState()
            TrackerEngine.recordBudget(in: &state, settings: settings, now: Date(), calendar: calendar)
            store.saveState(state)
        }
    }

    /// Manual correction: sets the bundle's total used so far (e.g. from MTN's
    /// USSD balance check). Tracking continues from this figure.
    func setBundleUsed(bytes: Int64) {
        store.withLock {
            var settings = store.loadSettings()
            settings.isSetUp = true
            store.saveSettings(settings)
            var state = store.loadState()
            state.bundleUsedBytes = max(bytes, 0)
            TrackerEngine.recordBudget(in: &state, settings: settings, now: Date(), calendar: calendar)
            store.saveState(state)
        }
    }

    /// New bundle bought today: start date = today, bundle usage = 0.
    /// Daily history is kept.
    func startNewBundleToday() {
        store.withLock {
            var settings = store.loadSettings()
            settings.startDate = calendar.startOfDay(for: Date())
            settings.isSetUp = true
            store.saveSettings(settings)
            var state = store.loadState()
            state.bundleUsedBytes = 0
            TrackerEngine.recordBudget(in: &state, settings: settings, now: Date(), calendar: calendar)
            store.saveState(state)
        }
    }
}
