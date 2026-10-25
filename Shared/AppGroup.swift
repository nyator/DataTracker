import Foundation

/// Identifiers shared by the app and the widget extension.
enum AppGroup {
    static let identifier = "group.com.builtelo.DataTracker"

    /// Must match BGTaskSchedulerPermittedIdentifiers in DataTracker/Info.plist.
    static let refreshTaskIdentifier = "com.builtelo.DataTracker.refresh"

    /// Widget kind, used to reload just our widget's timelines.
    static let widgetKind = "DataTrackerWidget"

    /// UserDefaults shared between the app and the widget via the App Group.
    /// If the App Group entitlement is missing, this silently becomes a
    /// per-process store and the widget won't see the app's data.
    static let defaults: UserDefaults = UserDefaults(suiteName: identifier) ?? .standard

    /// The shared container directory (used for the cross-process lock file).
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }
}
