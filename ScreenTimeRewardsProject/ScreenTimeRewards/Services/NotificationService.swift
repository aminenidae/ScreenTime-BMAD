import Foundation
import UserNotifications
import CloudKit
import Combine

/// Central service for managing all local and push notifications in the app.
/// Handles scheduling, duplicate prevention, and coordination with CloudKit for parent notifications.
@MainActor
final class NotificationService: ObservableObject {
    static let shared = NotificationService()

    // MARK: - Dependencies

    private let center = UNUserNotificationCenter.current()
    private let defaults = UserDefaults(suiteName: "group.com.screentimerewards.shared")

    // MARK: - Notification Tracking Keys

    private let sentNotificationsKey = "NotificationService_SentIdentifiers"
    private let scheduledRemindersKey = "NotificationService_ScheduledReminders"

    // MARK: - Notification Categories

    enum Category: String, CaseIterable {
        case streakMilestone = "STREAK_MILESTONE"
        case learningGoal = "LEARNING_GOAL"
        case dailyLimit = "DAILY_LIMIT"
        case downtimeWarning = "DOWNTIME_WARNING"
        case timeBankLow = "TIME_BANK_LOW"
        case streakAtRisk = "STREAK_AT_RISK"
        case subscriptionReminder = "SUBSCRIPTION_REMINDER"
        case parentAlert = "PARENT_ALERT"
    }

    // MARK: - Notification Action Identifiers

    enum Action: String {
        case openStreaks = "OPEN_STREAKS"
        case openLearning = "OPEN_LEARNING"
        case openRewards = "OPEN_REWARDS"
        case snooze1Hour = "SNOOZE_1H"
        case openSubscription = "OPEN_SUBSCRIPTION"
        case dismiss = "DISMISS"
    }

    // MARK: - Published State

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    // MARK: - Initialization

    private init() {
        registerCategories()
        Task {
            await refreshAuthorizationStatus()
        }
    }

    // MARK: - Authorization

    /// Request notification authorization from the user
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(
                options: [.alert, .sound, .badge]
            )
            await refreshAuthorizationStatus()
            #if DEBUG
            print("[NotificationService] Authorization \(granted ? "granted" : "denied")")
            #endif
            return granted
        } catch {
            #if DEBUG
            print("[NotificationService] Authorization error: \(error)")
            #endif
            return false
        }
    }

    /// Refresh the current authorization status
    func refreshAuthorizationStatus() async {
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    /// Check if notifications are authorized
    var isAuthorized: Bool {
        authorizationStatus == .authorized
    }

    // MARK: - Category Registration

    private func registerCategories() {
        // Streak Milestone Category
        let milestoneOpen = UNNotificationAction(
            identifier: Action.openStreaks.rawValue,
            title: "View Streak",
            options: .foreground
        )
        let milestoneCategory = UNNotificationCategory(
            identifier: Category.streakMilestone.rawValue,
            actions: [milestoneOpen],
            intentIdentifiers: []
        )

        // Learning Goal Category
        let learningOpen = UNNotificationAction(
            identifier: Action.openLearning.rawValue,
            title: "Start Learning",
            options: .foreground
        )
        let learningCategory = UNNotificationCategory(
            identifier: Category.learningGoal.rawValue,
            actions: [learningOpen],
            intentIdentifiers: []
        )

        // Daily Limit Category
        let limitCategory = UNNotificationCategory(
            identifier: Category.dailyLimit.rawValue,
            actions: [],
            intentIdentifiers: []
        )

        // Downtime Warning Category
        let downtimeCategory = UNNotificationCategory(
            identifier: Category.downtimeWarning.rawValue,
            actions: [],
            intentIdentifiers: []
        )

        // Time Bank Low Category
        let timeBankOpen = UNNotificationAction(
            identifier: Action.openLearning.rawValue,
            title: "Earn More Time",
            options: .foreground
        )
        let timeBankCategory = UNNotificationCategory(
            identifier: Category.timeBankLow.rawValue,
            actions: [timeBankOpen],
            intentIdentifiers: []
        )

        // Streak at Risk Category
        let riskOpen = UNNotificationAction(
            identifier: Action.openLearning.rawValue,
            title: "Start Now",
            options: .foreground
        )
        let riskSnooze = UNNotificationAction(
            identifier: Action.snooze1Hour.rawValue,
            title: "Remind in 1 hour",
            options: []
        )
        let riskCategory = UNNotificationCategory(
            identifier: Category.streakAtRisk.rawValue,
            actions: [riskOpen, riskSnooze],
            intentIdentifiers: []
        )

        // Subscription Reminder Category
        let subscribeAction = UNNotificationAction(
            identifier: Action.openSubscription.rawValue,
            title: "Subscribe",
            options: .foreground
        )
        let subscriptionCategory = UNNotificationCategory(
            identifier: Category.subscriptionReminder.rawValue,
            actions: [subscribeAction],
            intentIdentifiers: []
        )

        // Parent Alert Category
        let parentCategory = UNNotificationCategory(
            identifier: Category.parentAlert.rawValue,
            actions: [],
            intentIdentifiers: []
        )

        center.setNotificationCategories([
            milestoneCategory,
            learningCategory,
            limitCategory,
            downtimeCategory,
            timeBankCategory,
            riskCategory,
            subscriptionCategory,
            parentCategory
        ])

        #if DEBUG
        print("[NotificationService] Registered \(Category.allCases.count) notification categories")
        #endif
    }

    // MARK: - Duplicate Prevention

    private func dateKey() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private func hasNotificationBeenSent(identifier: String, today: Bool = true) -> Bool {
        let key = today ? "\(identifier)_\(dateKey())" : identifier
        let sent = defaults?.stringArray(forKey: sentNotificationsKey) ?? []
        return sent.contains(key)
    }

    private func markNotificationAsSent(identifier: String, today: Bool = true) {
        let key = today ? "\(identifier)_\(dateKey())" : identifier
        var sent = defaults?.stringArray(forKey: sentNotificationsKey) ?? []
        if !sent.contains(key) {
            sent.append(key)
            defaults?.set(sent, forKey: sentNotificationsKey)
        }
    }

    /// Clean up old notification tracking (call daily)
    func cleanupOldNotificationTracking() {
        let currentDateKey = dateKey()
        var sent = defaults?.stringArray(forKey: sentNotificationsKey) ?? []

        // Remove entries from previous days (those that contain a date key that isn't today)
        sent = sent.filter { entry in
            // Keep entries that don't have a date suffix (non-daily) or have today's date
            !entry.contains("_20") || entry.hasSuffix("_\(currentDateKey)")
        }

        defaults?.set(sent, forKey: sentNotificationsKey)
    }

    // MARK: - Child Local Notifications

    // MARK: 1. Streak Milestone Achieved

    /// Schedule a notification when child achieves a streak milestone
    func scheduleStreakMilestoneNotification(
        milestone: Int,
        bonusMinutes: Int,
        appName: String,
        appLogicalID: String
    ) {
        let identifier = "streak_milestone_\(milestone)_\(appLogicalID)"
        guard !hasNotificationBeenSent(identifier: identifier, today: true) else {
            print("[NotificationService] Streak milestone notification already sent today for \(appName)")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Streak Achievement!"
        content.body = "\(milestone)-day streak on \(appName)! You earned \(bonusMinutes) bonus minutes!"
        content.sound = .default
        content.categoryIdentifier = Category.streakMilestone.rawValue
        content.userInfo = [
            "type": "streakMilestone",
            "milestone": milestone,
            "appName": appName,
            "appLogicalID": appLogicalID,
            "bonusMinutes": bonusMinutes
        ]

        // Deliver immediately
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )

        center.add(request) { [weak self] error in
            if let error = error {
                print("[NotificationService] Failed to schedule streak milestone: \(error)")
            } else {
                self?.markNotificationAsSent(identifier: identifier, today: true)
                print("[NotificationService] Scheduled streak milestone notification for \(appName)")
            }
        }
    }

    // MARK: 2. Learning Goal Completed

    /// Schedule a notification when child completes their daily learning goal
    func scheduleLearningGoalCompletedNotification(earnedMinutes: Int) {
        let identifier = "learning_goal_completed"
        guard !hasNotificationBeenSent(identifier: identifier, today: true) else {
            print("[NotificationService] Learning goal notification already sent today")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Goal Complete!"
        content.body = "You've earned \(earnedMinutes) minutes of reward time. Enjoy your games!"
        content.sound = .default
        content.categoryIdentifier = Category.learningGoal.rawValue
        content.userInfo = [
            "type": "learningGoalCompleted",
            "earnedMinutes": earnedMinutes
        ]

        let request = UNNotificationRequest(
            identifier: "\(identifier)_\(dateKey())",
            content: content,
            trigger: nil
        )

        center.add(request) { [weak self] error in
            if let error = error {
                print("[NotificationService] Failed to schedule learning goal: \(error)")
            } else {
                self?.markNotificationAsSent(identifier: identifier, today: true)
                print("[NotificationService] Scheduled learning goal completed notification")
            }
        }
    }

    // MARK: 3. Approaching Daily Limit (80%)

    /// Schedule a notification when child is approaching their daily limit
    func scheduleApproachingLimitNotification(
        appName: String,
        appLogicalID: String,
        usedMinutes: Int,
        limitMinutes: Int
    ) {
        let identifier = "approaching_limit_\(appLogicalID)"
        guard !hasNotificationBeenSent(identifier: identifier, today: true) else {
            print("[NotificationService] Approaching limit notification already sent today for \(appName)")
            return
        }

        let remaining = limitMinutes - usedMinutes

        let content = UNMutableNotificationContent()
        content.title = "Approaching Limit"
        content.body = "\(appName): \(remaining) minutes remaining today"
        content.sound = .default
        content.categoryIdentifier = Category.dailyLimit.rawValue
        content.userInfo = [
            "type": "approachingLimit",
            "appName": appName,
            "appLogicalID": appLogicalID,
            "usedMinutes": usedMinutes,
            "limitMinutes": limitMinutes
        ]

        let request = UNNotificationRequest(
            identifier: "\(identifier)_\(dateKey())",
            content: content,
            trigger: nil
        )

        center.add(request) { [weak self] error in
            if let error = error {
                print("[NotificationService] Failed to schedule approaching limit: \(error)")
            } else {
                self?.markNotificationAsSent(identifier: identifier, today: true)
                print("[NotificationService] Scheduled approaching limit notification for \(appName)")
            }
        }
    }

    // MARK: 4. Downtime Starting Soon

    /// Schedule a recurring notification before downtime starts
    func scheduleDowntimeWarning(
        for appLogicalID: String,
        appName: String,
        windowEndHour: Int,
        windowEndMinute: Int,
        minutesBefore: Int = 15
    ) {
        let identifier = "downtime_warning_\(appLogicalID)"

        // Cancel existing notification for this app
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        // Calculate warning time (minutesBefore before window ends = when downtime begins)
        var warningHour = windowEndHour
        var warningMinute = windowEndMinute - minutesBefore

        if warningMinute < 0 {
            warningMinute += 60
            warningHour -= 1
            if warningHour < 0 {
                warningHour = 23
            }
        }

        var dateComponents = DateComponents()
        dateComponents.hour = warningHour
        dateComponents.minute = warningMinute

        let content = UNMutableNotificationContent()
        content.title = "Downtime Starting Soon"
        content.body = "\(appName) will be unavailable in \(minutesBefore) minutes"
        content.sound = .default
        content.categoryIdentifier = Category.downtimeWarning.rawValue
        content.userInfo = [
            "type": "downtimeWarning",
            "appName": appName,
            "appLogicalID": appLogicalID
        ]

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: dateComponents,
            repeats: true
        )

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )

        center.add(request) { error in
            if let error = error {
                print("[NotificationService] Failed to schedule downtime warning: \(error)")
            } else {
                print("[NotificationService] Scheduled downtime warning for \(appName) at \(warningHour):\(warningMinute)")
            }
        }
    }

    /// Cancel downtime warning for an app
    func cancelDowntimeWarning(for appLogicalID: String) {
        let identifier = "downtime_warning_\(appLogicalID)"
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    // MARK: 5. Time Bank Low

    /// Schedule a notification when reward minutes are running low
    func scheduleTimeBankLowNotification(remainingMinutes: Int, threshold: Int = 5) {
        guard remainingMinutes <= threshold && remainingMinutes > 0 else { return }

        let identifier = "time_bank_low"
        guard !hasNotificationBeenSent(identifier: identifier, today: true) else {
            print("[NotificationService] Time bank low notification already sent today")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Time Bank Low"
        content.body = "Only \(remainingMinutes) minutes left. Use a learning app to earn more!"
        content.sound = .default
        content.categoryIdentifier = Category.timeBankLow.rawValue
        content.userInfo = [
            "type": "timeBankLow",
            "remainingMinutes": remainingMinutes
        ]

        let request = UNNotificationRequest(
            identifier: "\(identifier)_\(dateKey())",
            content: content,
            trigger: nil
        )

        center.add(request) { [weak self] error in
            if let error = error {
                print("[NotificationService] Failed to schedule time bank low: \(error)")
            } else {
                self?.markNotificationAsSent(identifier: identifier, today: true)
                print("[NotificationService] Scheduled time bank low notification")
            }
        }
    }

    // MARK: 6. Streak at Risk (Cancellable)

    /// Schedule streak at risk reminders (7 PM + 1 hour before downtime)
    func scheduleStreakAtRiskReminders(
        appLogicalID: String,
        appName: String,
        currentStreak: Int,
        downtimeHour: Int? = nil,
        downtimeMinute: Int? = nil
    ) {
        let identifier7PM = "streak_risk_7pm_\(appLogicalID)"
        let identifierDowntime = "streak_risk_downtime_\(appLogicalID)"

        // Cancel existing reminders first
        cancelStreakAtRiskReminders(for: appLogicalID)

        let content = UNMutableNotificationContent()
        content.title = "Complete Your Goal"
        content.body = "Don't lose your \(currentStreak > 0 ? "\(currentStreak)-day " : "")\(appName) streak! Complete your learning goal before bedtime."
        content.sound = .default
        content.categoryIdentifier = Category.streakAtRisk.rawValue
        content.userInfo = [
            "type": "streakAtRisk",
            "appLogicalID": appLogicalID,
            "appName": appName
        ]

        // Schedule 7 PM reminder
        var evening = DateComponents()
        evening.hour = 19
        evening.minute = 0

        let trigger7PM = UNCalendarNotificationTrigger(dateMatching: evening, repeats: true)
        let request7PM = UNNotificationRequest(
            identifier: identifier7PM,
            content: content,
            trigger: trigger7PM
        )

        center.add(request7PM) { error in
            if let error = error {
                print("[NotificationService] Failed to schedule 7PM streak reminder: \(error)")
            } else {
                print("[NotificationService] Scheduled 7PM streak at risk reminder for \(appName)")
            }
        }

        // Schedule 1 hour before downtime if provided
        if let downtimeHour = downtimeHour, let downtimeMinute = downtimeMinute {
            var reminderHour = downtimeHour - 1
            var reminderMinute = downtimeMinute

            if reminderHour < 0 {
                reminderHour = 23
            }

            // Don't schedule if it would be at the same time as 7 PM reminder
            if reminderHour != 19 || reminderMinute != 0 {
                var downtimeComponents = DateComponents()
                downtimeComponents.hour = reminderHour
                downtimeComponents.minute = reminderMinute

                let downtimeContent = UNMutableNotificationContent()
                downtimeContent.title = "Last Chance!"
                downtimeContent.body = "1 hour until downtime. Complete your \(appName) goal now!"
                downtimeContent.sound = .default
                downtimeContent.categoryIdentifier = Category.streakAtRisk.rawValue
                downtimeContent.userInfo = content.userInfo

                let triggerDowntime = UNCalendarNotificationTrigger(dateMatching: downtimeComponents, repeats: true)
                let requestDowntime = UNNotificationRequest(
                    identifier: identifierDowntime,
                    content: downtimeContent,
                    trigger: triggerDowntime
                )

                center.add(requestDowntime) { error in
                    if let error = error {
                        print("[NotificationService] Failed to schedule downtime streak reminder: \(error)")
                    } else {
                        print("[NotificationService] Scheduled 1hr-before-downtime streak reminder for \(appName)")
                    }
                }
            }
        }

        // Track scheduled reminders
        var scheduled = defaults?.stringArray(forKey: scheduledRemindersKey) ?? []
        scheduled.append(identifier7PM)
        scheduled.append(identifierDowntime)
        defaults?.set(scheduled, forKey: scheduledRemindersKey)
    }

    /// Cancel streak at risk reminders when goal is met
    func cancelStreakAtRiskReminders(for appLogicalID: String) {
        let identifiers = [
            "streak_risk_7pm_\(appLogicalID)",
            "streak_risk_downtime_\(appLogicalID)"
        ]
        center.removePendingNotificationRequests(withIdentifiers: identifiers)

        // Clean up tracking
        var scheduled = defaults?.stringArray(forKey: scheduledRemindersKey) ?? []
        scheduled.removeAll { identifiers.contains($0) }
        defaults?.set(scheduled, forKey: scheduledRemindersKey)

        print("[NotificationService] Cancelled streak at risk reminders for \(appLogicalID)")
    }

    /// Cancel all streak at risk reminders
    func cancelAllStreakAtRiskReminders() {
        let scheduled = defaults?.stringArray(forKey: scheduledRemindersKey) ?? []
        let streakRiskIdentifiers = scheduled.filter { $0.hasPrefix("streak_risk_") }
        center.removePendingNotificationRequests(withIdentifiers: streakRiskIdentifiers)

        var remaining = scheduled.filter { !$0.hasPrefix("streak_risk_") }
        defaults?.set(remaining, forKey: scheduledRemindersKey)
    }

    /// Schedule a snooze reminder (called from notification action)
    func scheduleSnoozeReminder(for appLogicalID: String, appName: String, delay: TimeInterval = 3600) {
        let identifier = "streak_risk_snooze_\(appLogicalID)"

        let content = UNMutableNotificationContent()
        content.title = "Reminder: Complete Your Goal"
        content.body = "Don't forget to complete your \(appName) learning goal!"
        content.sound = .default
        content.categoryIdentifier = Category.streakAtRisk.rawValue
        content.userInfo = [
            "type": "streakAtRiskSnooze",
            "appLogicalID": appLogicalID,
            "appName": appName
        ]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )

        center.add(request) { error in
            if let error = error {
                print("[NotificationService] Failed to schedule snooze reminder: \(error)")
            } else {
                print("[NotificationService] Scheduled snooze reminder for \(appName) in \(delay/60) minutes")
            }
        }
    }

    // MARK: - Subscription Reminders

    /// Schedule subscription/trial expiration reminders
    func scheduleSubscriptionReminders(
        expirationDate: Date,
        isTrial: Bool,
        remindDays: [Int] = [7, 3, 0]
    ) {
        // Cancel existing reminders first
        cancelSubscriptionReminders()

        let calendar = Calendar.current
        let type = isTrial ? "trial" : "subscription"

        for daysRemaining in remindDays {
            guard let reminderDate = calendar.date(byAdding: .day, value: -daysRemaining, to: expirationDate) else {
                continue
            }

            // Skip if reminder date is in the past
            guard reminderDate > Date() else { continue }

            // Set reminder for 10 AM
            var components = calendar.dateComponents([.year, .month, .day], from: reminderDate)
            components.hour = 10
            components.minute = 0

            let content = UNMutableNotificationContent()
            content.title = isTrial ? "Trial Ending Soon" : "Subscription Expiring"

            if daysRemaining == 0 {
                content.body = "Your \(isTrial ? "free trial" : "subscription") expires today. Subscribe to keep screen time controls active."
            } else {
                content.body = "Your \(isTrial ? "free trial" : "subscription") expires in \(daysRemaining) days. Renew to avoid interruption."
            }

            content.sound = .default
            content.categoryIdentifier = Category.subscriptionReminder.rawValue
            content.userInfo = [
                "type": "\(type)_reminder",
                "daysRemaining": daysRemaining
            ]

            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let identifier = "\(type)_reminder_\(daysRemaining)d"

            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: trigger
            )

            center.add(request) { error in
                if let error = error {
                    print("[NotificationService] Failed to schedule \(type) reminder: \(error)")
                } else {
                    print("[NotificationService] Scheduled \(type) reminder for \(daysRemaining) days before expiration")
                }
            }
        }
    }

    /// Cancel all subscription/trial reminders
    func cancelSubscriptionReminders() {
        let identifiers = [
            "trial_reminder_7d", "trial_reminder_3d", "trial_reminder_0d",
            "subscription_reminder_7d", "subscription_reminder_3d", "subscription_reminder_0d"
        ]
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    // MARK: - Parent Notifications (via CloudKit)

    /// Notify parent that child reached their daily limit
    func notifyParentOfDailyLimitReached(
        appName: String,
        usedMinutes: Int,
        limitMinutes: Int
    ) async {
        guard DeviceModeManager.shared.isChildDevice,
              !DevicePairingService.shared.getPairedParents().isEmpty else { return }

        let payload = ParentNotificationPayload(
            notificationID: UUID().uuidString,
            childDeviceID: DeviceModeManager.shared.deviceID,
            childDeviceName: DeviceModeManager.shared.deviceName,
            notificationType: .dailyLimitReached,
            title: "Daily Limit Reached",
            body: "\(DeviceModeManager.shared.deviceName) has reached their daily limit for \(appName)",
            timestamp: Date(),
            metadata: [
                "appName": appName,
                "usedMinutes": String(usedMinutes),
                "limitMinutes": String(limitMinutes)
            ]
        )

        do {
            try await CloudKitSyncService.shared.sendParentNotification(payload)
            print("[NotificationService] Notified parent of daily limit reached for \(appName)")
        } catch {
            print("[NotificationService] Failed to notify parent: \(error)")
        }
    }

    /// Notify parent that child completed their learning goal
    func notifyParentOfLearningGoalCompleted(earnedMinutes: Int) async {
        guard DeviceModeManager.shared.isChildDevice,
              !DevicePairingService.shared.getPairedParents().isEmpty else { return }

        let payload = ParentNotificationPayload(
            notificationID: UUID().uuidString,
            childDeviceID: DeviceModeManager.shared.deviceID,
            childDeviceName: DeviceModeManager.shared.deviceName,
            notificationType: .learningGoalCompleted,
            title: "Learning Goal Complete!",
            body: "\(DeviceModeManager.shared.deviceName) completed their learning goal and earned \(earnedMinutes) minutes",
            timestamp: Date(),
            metadata: [
                "earnedMinutes": String(earnedMinutes)
            ]
        )

        do {
            try await CloudKitSyncService.shared.sendParentNotification(payload)
            print("[NotificationService] Notified parent of learning goal completed")
        } catch {
            print("[NotificationService] Failed to notify parent: \(error)")
        }
    }

    /// Notify parent of child's streak milestone
    func notifyParentOfStreakMilestone(
        milestone: Int,
        appName: String,
        bonusMinutes: Int
    ) async {
        guard DeviceModeManager.shared.isChildDevice,
              !DevicePairingService.shared.getPairedParents().isEmpty else { return }

        let payload = ParentNotificationPayload(
            notificationID: UUID().uuidString,
            childDeviceID: DeviceModeManager.shared.deviceID,
            childDeviceName: DeviceModeManager.shared.deviceName,
            notificationType: .streakMilestone,
            title: "Streak Milestone!",
            body: "\(DeviceModeManager.shared.deviceName) reached a \(milestone)-day streak on \(appName)!",
            timestamp: Date(),
            metadata: [
                "milestone": String(milestone),
                "appName": appName,
                "bonusMinutes": String(bonusMinutes)
            ]
        )

        do {
            try await CloudKitSyncService.shared.sendParentNotification(payload)
            print("[NotificationService] Notified parent of streak milestone")
        } catch {
            print("[NotificationService] Failed to notify parent: \(error)")
        }
    }

    // MARK: - Weekly Summary

    /// Schedule weekly summary notification (Sunday 6 PM)
    func scheduleWeeklySummary() {
        let identifier = "weekly_summary"

        // Cancel existing
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        var components = DateComponents()
        components.weekday = 1 // Sunday
        components.hour = 18
        components.minute = 0

        let content = UNMutableNotificationContent()
        content.title = "Weekly Summary Ready"
        content.body = "See how your child did this week!"
        content.sound = .default
        content.categoryIdentifier = Category.parentAlert.rawValue
        content.userInfo = ["type": "weeklySummary"]

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )

        center.add(request) { error in
            if let error = error {
                print("[NotificationService] Failed to schedule weekly summary: \(error)")
            } else {
                print("[NotificationService] Scheduled weekly summary notification")
            }
        }
    }

    // MARK: - Parent Device Local Notifications

    /// Show a local notification on parent device for child events
    func showParentNotification(payload: ParentNotificationPayload) {
        let content = UNMutableNotificationContent()
        content.title = payload.title
        content.body = payload.body
        content.sound = .default
        content.categoryIdentifier = Category.parentAlert.rawValue
        content.userInfo = [
            "type": "parentNotification",
            "notificationType": payload.notificationType.rawValue,
            "childDeviceID": payload.childDeviceID,
            "childDeviceName": payload.childDeviceName
        ]

        let request = UNNotificationRequest(
            identifier: payload.notificationID,
            content: content,
            trigger: nil // Immediate
        )

        center.add(request) { error in
            if let error = error {
                print("[NotificationService] Failed to show parent notification: \(error)")
            }
        }
    }

    // MARK: - Utility Methods

    /// Remove all pending notifications
    func removeAllPendingNotifications() {
        center.removeAllPendingNotificationRequests()
        defaults?.removeObject(forKey: scheduledRemindersKey)
        print("[NotificationService] Removed all pending notifications")
    }

    /// Remove all delivered notifications
    func removeAllDeliveredNotifications() {
        center.removeAllDeliveredNotifications()
        print("[NotificationService] Removed all delivered notifications")
    }

    /// Get count of pending notifications
    func getPendingNotificationCount() async -> Int {
        let pending = await center.pendingNotificationRequests()
        return pending.count
    }

    /// Debug: Print all pending notifications
    func debugPrintPendingNotifications() async {
        let pending = await center.pendingNotificationRequests()
        print("[NotificationService] Pending notifications (\(pending.count)):")
        for request in pending {
            print("  - \(request.identifier): \(request.content.title)")
        }
    }
}
