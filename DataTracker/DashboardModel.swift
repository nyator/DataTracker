import SwiftUI
import WidgetKit

@MainActor
final class DashboardModel: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot
    @Published private(set) var settings: BudgetSettings

    private let tracker: UsageTracker

    init(tracker: UsageTracker = .shared) {
        self.tracker = tracker
        self.snapshot = tracker.snapshot()
        self.settings = tracker.settings
    }

    /// Takes a reading, posts any due alerts, and refreshes the widget.
    /// Called on launch, on every return to the foreground, and every minute while open.
    func refresh() {
        Task {
            let result = tracker.refresh(evaluateAlerts: await Notifier.canPost())
            snapshot = result.snapshot
            await Notifier.post(thresholds: result.newAlerts, snapshot: result.snapshot)
            WidgetCenter.shared.reloadTimelines(ofKind: AppGroup.widgetKind)
        }
    }

    func update(_ newSettings: BudgetSettings) {
        var newSettings = newSettings
        // Once set up, stays set up, even if a Settings screen holds an older copy.
        newSettings.isSetUp = newSettings.isSetUp || settings.isSetUp
        guard newSettings != settings else { return }
        settings = newSettings
        tracker.updateSettings(newSettings)
        reloadSnapshot()
    }

    func setBundleUsed(gb: Double) {
        tracker.setBundleUsed(bytes: Budget.bytes(fromGB: gb))
        settings = tracker.settings
        reloadSnapshot()
    }

    /// Hides the first-run card without entering anything.
    func skipSetup() {
        var s = settings
        s.isSetUp = true
        update(s)
    }

    func startNewBundleToday() {
        tracker.startNewBundleToday()
        settings = tracker.settings
        reloadSnapshot()
    }

    private func reloadSnapshot() {
        snapshot = tracker.snapshot()
        WidgetCenter.shared.reloadTimelines(ofKind: AppGroup.widgetKind)
    }
}
