import Foundation

@MainActor
enum ScreenTimeNotifications {
    static let eventDidReachThreshold = "com.screentimerewards.eventDidReachThreshold"
    static let eventWillReachThreshold = "com.screentimerewards.eventWillReachThreshold"
    static let intervalDidStart = "com.screentimerewards.intervalDidStart"
    static let intervalDidEnd = "com.screentimerewards.intervalDidEnd"
    static let intervalWillStart = "com.screentimerewards.intervalWillStart"
    static let intervalWillEnd = "com.screentimerewards.intervalWillEnd"
    static let usageRecorded = "com.screentimerewards.usageRecorded"
}

// Notification names for ManagedSettings blocking/unlocking
extension Notification.Name {
    static let rewardAppsBlocked = Notification.Name("com.screentimerewards.rewardAppsBlocked")
    static let rewardAppsUnlocked = Notification.Name("com.screentimerewards.rewardAppsUnlocked")
    static let allShieldsCleared = Notification.Name("com.screentimerewards.allShieldsCleared")
    static let extensionUnhealthy = Notification.Name("com.screentimerewards.extensionUnhealthy")
    static let missedUsageNotifications = Notification.Name("com.screentimerewards.missedUsageNotifications")
    static let dailyUsageReset = Notification.Name("com.screentimerewards.dailyUsageReset")
}
