import Foundation

@MainActor
enum ScreenTimeNotifications {
    static let eventDidReachThreshold = "com.screentimerewards.eventDidReachThreshold"
    static let eventWillReachThreshold = "com.screentimerewards.eventWillReachThreshold"
    static let intervalDidStart = "com.screentimerewards.intervalDidStart"
    static let intervalDidEnd = "com.screentimerewards.intervalDidEnd"
    static let intervalWillStart = "com.screentimerewards.intervalWillStart"
    static let intervalWillEnd = "com.screentimerewards.intervalWillEnd"
}