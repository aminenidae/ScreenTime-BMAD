import Foundation
import SwiftUI
import Combine

/// Manages deep linking from notifications to specific app destinations
@MainActor
final class DeepLinkManager: ObservableObject {
    static let shared = DeepLinkManager()

    // MARK: - App Destinations

    enum AppDestination: Equatable {
        case childDashboard
        case learningApps
        case rewardApps
        case streakDetails(appLogicalID: String?)
        case subscription
        case settings
        case parentDashboard
        case childUsageDetails(childDeviceID: String?)
    }

    // MARK: - Published State

    @Published var pendingDestination: AppDestination?

    private init() {}

    // MARK: - Notification Action Handling

    /// Handle notification action from UNNotificationResponse
    func handleNotificationAction(
        actionIdentifier: String,
        userInfo: [AnyHashable: Any]
    ) {
        #if DEBUG
        print("[DeepLinkManager] Handling action: \(actionIdentifier)")
        print("[DeepLinkManager] UserInfo: \(userInfo)")
        #endif

        switch actionIdentifier {
        case NotificationService.Action.openStreaks.rawValue:
            // Navigate to streak details
            if let appID = userInfo["appLogicalID"] as? String {
                pendingDestination = .streakDetails(appLogicalID: appID)
            } else {
                pendingDestination = .childDashboard
            }

        case NotificationService.Action.openLearning.rawValue:
            // Navigate to learning apps section
            pendingDestination = .learningApps

        case NotificationService.Action.openRewards.rawValue:
            // Navigate to reward apps section
            pendingDestination = .rewardApps

        case NotificationService.Action.openSubscription.rawValue:
            // Navigate to subscription screen
            pendingDestination = .subscription

        case NotificationService.Action.snooze1Hour.rawValue:
            // Reschedule notification for 1 hour
            if let appID = userInfo["appLogicalID"] as? String,
               let appName = userInfo["appName"] as? String {
                NotificationService.shared.scheduleSnoozeReminder(
                    for: appID,
                    appName: appName,
                    delay: 3600
                )
            }

        case "com.apple.UNNotificationDefaultActionIdentifier":
            // Default tap - route based on notification type
            if let type = userInfo["type"] as? String {
                routeByNotificationType(type, userInfo: userInfo)
            } else {
                pendingDestination = .childDashboard
            }

        case "com.apple.UNNotificationDismissActionIdentifier":
            // User dismissed notification - no action needed
            break

        default:
            // Unknown action - try to route by notification type
            if let type = userInfo["type"] as? String {
                routeByNotificationType(type, userInfo: userInfo)
            }
        }
    }

    /// Route to appropriate destination based on notification type
    private func routeByNotificationType(_ type: String, userInfo: [AnyHashable: Any]) {
        switch type {
        case "streakMilestone", "streakAtRisk", "streakAtRiskSnooze":
            let appID = userInfo["appLogicalID"] as? String
            pendingDestination = .streakDetails(appLogicalID: appID)

        case "learningGoalCompleted":
            pendingDestination = .rewardApps

        case "approachingLimit", "timeBankLow":
            pendingDestination = .childDashboard

        case "downtimeWarning":
            pendingDestination = .childDashboard

        case "trial_reminder", "subscription_reminder":
            pendingDestination = .subscription

        case "parentNotification":
            if let childID = userInfo["childDeviceID"] as? String {
                pendingDestination = .childUsageDetails(childDeviceID: childID)
            } else {
                pendingDestination = .parentDashboard
            }

        case "weeklySummary":
            pendingDestination = .parentDashboard

        default:
            // Default to appropriate dashboard based on device mode
            if DeviceModeManager.shared.isChildDevice {
                pendingDestination = .childDashboard
            } else {
                pendingDestination = .parentDashboard
            }
        }

        #if DEBUG
        print("[DeepLinkManager] Set pending destination to: \(String(describing: pendingDestination))")
        #endif
    }

    // MARK: - Destination Clearing

    /// Clear pending destination after navigation
    func clearPendingDestination() {
        pendingDestination = nil
    }

    /// Check if there's a pending destination
    var hasPendingDestination: Bool {
        pendingDestination != nil
    }
}
