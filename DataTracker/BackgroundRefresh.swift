import BackgroundTasks
import WidgetKit

/// Periodic background readings via BGAppRefreshTask.
///
/// iOS decides when (and whether) a refresh runs, based on how often you open
/// the app, battery, Low Power Mode and the Background App Refresh setting.
/// `earliestBeginDate` is a lower bound, not a schedule: expect runs every
/// 1–3 hours for a regularly used app, and fewer at night or in Low Power Mode.
/// If the app is force-quit from the app switcher, iOS stops running its
/// refreshes until you open it again.
enum BackgroundRefresh {
    static let interval: TimeInterval = 60 * 60

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: AppGroup.refreshTaskIdentifier, using: nil) { task in
            guard let task = task as? BGAppRefreshTask else { return task.setTaskCompleted(success: false) }
            handle(task)
        }
    }

    /// Submits (or replaces) the pending refresh request.
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: AppGroup.refreshTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: interval)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Common causes: Background App Refresh is off, or running in the Simulator.
            print("BGTaskScheduler submit failed: \(error)")
        }
    }

    /// When background refresh last ran, and how many times. Shown in Settings,
    /// so you can confirm on the phone that iOS is actually running the task.
    static var lastRunDate: Date? { AppGroup.defaults.object(forKey: "backgroundRefresh.lastRun") as? Date }
    static var runCount: Int { AppGroup.defaults.integer(forKey: "backgroundRefresh.count") }

    private static func handle(_ task: BGAppRefreshTask) {
        // Queue the next run first, so the chain continues even if this one expires.
        schedule()
        AppGroup.defaults.set(Date(), forKey: "backgroundRefresh.lastRun")
        AppGroup.defaults.set(runCount + 1, forKey: "backgroundRefresh.count")

        let work = Task {
            let result = UsageTracker.shared.refresh(evaluateAlerts: await Notifier.canPost())
            await Notifier.post(thresholds: result.newAlerts, snapshot: result.snapshot)
            WidgetCenter.shared.reloadTimelines(ofKind: AppGroup.widgetKind)
            task.setTaskCompleted(success: !Task.isCancelled)
        }
        task.expirationHandler = { work.cancel() }
    }
}
