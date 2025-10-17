import Foundation

@MainActor
enum ScreenTimeNotifications {
    nonisolated(unsafe) static let eventDidReachThreshold = "com.screentimerewards.eventDidReachThreshold"
    nonisolated(unsafe) static let eventWillReachThreshold = "com.screentimerewards.eventWillReachThreshold"
    nonisolated(unsafe) static let intervalDidStart = "com.screentimerewards.intervalDidStart"
    nonisolated(unsafe) static let intervalDidEnd = "com.screentimerewards.intervalDidEnd"
    nonisolated(unsafe) static let intervalWillStart = "com.screentimerewards.intervalWillStart"
    nonisolated(unsafe) static let intervalWillEnd = "com.screentimerewards.intervalWillEnd"
}

// Notification names for ManagedSettings blocking/unlocking
extension Notification.Name {
    static let rewardAppsBlocked = Notification.Name("com.screentimerewards.rewardAppsBlocked")
    static let rewardAppsUnlocked = Notification.Name("com.screentimerewards.rewardAppsUnlocked")
    static let allShieldsCleared = Notification.Name("com.screentimerewards.allShieldsCleared")
}