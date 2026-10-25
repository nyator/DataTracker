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
        guard newSettings != settings else { return }
        settings = newSettings
        tracker.updateSettings(newSettings)
        reloadSnapshot()
    }

    func setBundleUsed(gb: Double) {
        tracker.setBundleUsed(bytes: Budget.bytes(fromGB: gb))
        reloadSnapshot()
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
