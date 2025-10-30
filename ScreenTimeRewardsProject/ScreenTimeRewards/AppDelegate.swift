import UIKit
import CloudKit
import UserNotifications
import BackgroundTasks

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Set up notification center delegate
        UNUserNotificationCenter.current().delegate = self
        
        // Register for remote notifications
        application.registerForRemoteNotifications()
        
        // Register background tasks using our service
        ChildBackgroundSyncService.shared.registerBackgroundTasks()
        
        return true
    }
    
    /// Handle usage upload background task
    private func handleUsageUploadTask(_ task: BGTask) {
        ChildBackgroundSyncService.shared.handleUsageUploadTask(task)
    }
    
    /// Handle config check background task
    private func handleConfigCheckTask(_ task: BGTask) {
        ChildBackgroundSyncService.shared.handleConfigCheckTask(task)
    }
    
    /// Schedule next usage upload task
    private func scheduleNextUsageUpload() {
        ChildBackgroundSyncService.shared.scheduleNextUsageUpload()
    }
    
    /// Schedule next config check task
    private func scheduleNextConfigCheck() {
        ChildBackgroundSyncService.shared.scheduleNextConfigCheck()
    }
    
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        print("[AppDelegate] Device token: \(token)")
        // Store token if needed for custom push
    }
    
    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("[AppDelegate] Failed to register for remote notifications: \(error)")
    }
    
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        print("[AppDelegate] Received remote notification: \(userInfo)")
        
        // Handle CloudKit push notifications
        Task {
            await CloudKitSyncService.shared.handlePushNotification(userInfo: userInfo)
            completionHandler(.newData)
        }
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notification in foreground
        completionHandler([.banner, .sound])
    }
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Handle notification tap
        completionHandler()
    }
}