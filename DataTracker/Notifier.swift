import UserNotifications

/// Local notifications for budget thresholds.
enum Notifier {
    static func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Thresholds are only evaluated (and marked as sent) when an alert can
    /// actually be shown. While notifications are off or not yet answered, an
    /// alert stays pending and fires once they're allowed.
    static func canPost() async -> Bool {
        switch await authorizationStatus() {
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }

    /// Posts one notification for the highest threshold just crossed. If usage
    /// jumped past both 80% and 100% between readings, you get only the 100% one.
    static func post(thresholds: [Int], snapshot: UsageSnapshot) async {
        guard let threshold = thresholds.max() else { return }

        let used = DataFormat.string(snapshot.todayBytes)
        let budget = DataFormat.string(snapshot.dailyBudgetBytes)
        let content = UNMutableNotificationContent()
        if threshold >= 100 {
            let over = DataFormat.string(max(snapshot.todayBytes - snapshot.dailyBudgetBytes, 0))
            content.title = threshold == 100 ? "Daily data budget reached" : "\(threshold)% of today's data budget"
            content.body = "You've used \(used) of \(budget) today (\(over) over). "
                + "Going over lowers the budget for the rest of your bundle."
        } else {
            content.title = "\(threshold)% of today's data budget used"
            content.body = "\(used) of \(budget) used today. "
                + "\(DataFormat.string(snapshot.todayRemainingBytes)) left until midnight."
        }
        content.sound = .default

        // One identifier per day and threshold, so a duplicate can only replace, never stack.
        let id = "budget-\(DayMath.key(for: snapshot.date))-\(threshold)"
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
