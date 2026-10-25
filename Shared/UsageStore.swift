import Foundation

/// Persists settings and tracker state in the App Group's UserDefaults.
final class UsageStore {
    static let shared = UsageStore(defaults: AppGroup.defaults,
                                   lockURL: AppGroup.containerURL?.appendingPathComponent("tracker.lock"))

    private enum Key {
        static let settings = "budgetSettings.v1"
        static let state = "trackerState.v1"
    }

    private let defaults: UserDefaults
    private let lockURL: URL?
    private let threadLock = NSLock()

    init(defaults: UserDefaults, lockURL: URL?) {
        self.defaults = defaults
        self.lockURL = lockURL
    }

    func loadSettings() -> BudgetSettings {
        guard let data = defaults.data(forKey: Key.settings),
              let settings = try? JSONDecoder().decode(BudgetSettings.self, from: data) else { return BudgetSettings() }
        return settings
    }

    func saveSettings(_ settings: BudgetSettings) {
        if let data = try? JSONEncoder().encode(settings) { defaults.set(data, forKey: Key.settings) }
    }

    func loadState() -> TrackerState {
        guard let data = defaults.data(forKey: Key.state),
              let state = try? JSONDecoder().decode(TrackerState.self, from: data) else { return TrackerState() }
        return state
    }

    func saveState(_ state: TrackerState) {
        if let data = try? JSONEncoder().encode(state) { defaults.set(data, forKey: Key.state) }
    }

    /// Runs `body` while holding a lock shared by the app *and* the widget
    /// extension (an `flock` on a file in the App Group container).
    ///
    /// Both processes read the counters and update the state. Without the lock,
    /// two read-modify-write cycles could interleave and add the same delta
    /// twice. The critical section is short and synchronous. If the lock can't
    /// be taken within ~2 s (another process stuck holding it), we go ahead
    /// anyway rather than hang the widget.
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        threadLock.lock()
        defer { threadLock.unlock() }

        guard let path = lockURL?.path else { return try body() }
        let fd = open(path, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else { return try body() }
        defer { close(fd) }

        var locked = false
        for _ in 0..<20 {
            if flock(fd, LOCK_EX | LOCK_NB) == 0 { locked = true; break }
            usleep(100_000)
        }
        defer { if locked { flock(fd, LOCK_UN) } }
        return try body()
    }
}
