import Foundation

enum ScreenTimeNotifications {
    nonisolated(unsafe) static let eventDidReachThreshold = "com.screentimerewards.eventDidReachThreshold"
    nonisolated(unsafe) static let eventWillReachThreshold = "com.screentimerewards.eventWillReachThreshold"
    nonisolated(unsafe) static let intervalDidStart = "com.screentimerewards.intervalDidStart"
    nonisolated(unsafe) static let intervalDidEnd = "com.screentimerewards.intervalDidEnd"
    nonisolated(unsafe) static let intervalWillStart = "com.screentimerewards.intervalWillStart"
    nonisolated(unsafe) static let intervalWillEnd = "com.screentimerewards.intervalWillEnd"
}
