import UIKit
import CloudKit
import UserNotifications
import BackgroundTasks
#if canImport(FirebaseCore)
import FirebaseCore
#endif

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    private var midnightResetObserver: NSObjectProtocol?
    private var midnightCheckTimer: Timer?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Configure Firebase Analytics
        #if canImport(FirebaseCore)
        FirebaseApp.configure()
        #endif

        // Set up notification center delegate
        UNUserNotificationCenter.current().delegate = self
        
        // Register for remote notifications
        application.registerForRemoteNotifications()
        
        // Enable extension-side CloudKit sync. Gated by a UserDefaults flag so the
        // extension doesn't load CloudKit unnecessarily during development. With the
        // 10-slot throttle in ExtensionCloudKitSync, memory pressure is negligible.
        UserDefaults(suiteName: "group.com.screentimerewards.shared")?
            .set(true, forKey: "ext_cloudkit_sync_enabled")

        // Register background tasks using our service
        ChildBackgroundSyncService.shared.registerBackgroundTasks()

        setupMidnightResetObserver()
        setupMemoryWarningObserver()

        // FIX: Also check for day change on app launch
        // The .NSCalendarDayChanged notification only fires if the app is running at midnight
        // If user launches the app after midnight, stale data from yesterday won't be reset
        checkForDayChangeOnLaunch()

        return true
    }

    /// Check if we've crossed a day boundary since last launch and reset daily counters if needed
    private func checkForDayChangeOnLaunch() {
        let defaults = UserDefaults.standard
        let lastLaunchDateKey = "lastAppLaunchDate"
        // v10: Force reset AND clear extension's UserDefaults usage keys
        // v9 had a bug: readExtensionUsageData() would sync stale data and mark it as today's
        // v10 fix: readExtensionUsageData() now checks usage_<id>_reset timestamp before syncing
        let staleFix2Key = "staleDailyDataFix_v10_forceReset"
        let today = Calendar.current.startOfDay(for: Date())

        var needsReset = false
        var needsForceReset = false

        // Always log the check
        print("[AppDelegate] 🔍 checkForDayChangeOnLaunch - today: \(today)")
        print("[AppDelegate] 🔍 staleFix key: \(staleFix2Key), value: \(defaults.bool(forKey: staleFix2Key))")

        // Check 1: Day changed since last launch
        if let lastLaunchDate = defaults.object(forKey: lastLaunchDateKey) as? Date {
            let lastLaunchDay = Calendar.current.startOfDay(for: lastLaunchDate)
            print("[AppDelegate] 🔍 lastLaunchDay: \(lastLaunchDay)")
            if lastLaunchDay < today {
                print("[AppDelegate] 🌅 Day changed since last launch - resetting daily counters")
                needsReset = true
            }
        } else {
            print("[AppDelegate] 🔍 No lastLaunchDate found (first launch)")
        }

        // Check 2: First run after stale data fix v9 - FORCE reset ALL apps AND clear extension keys
        if !defaults.bool(forKey: staleFix2Key) {
            print("[AppDelegate] 🔧 First run after stale data fix v9 - FORCING complete reset of ALL todaySeconds AND extension keys")
            needsForceReset = true
            defaults.set(true, forKey: staleFix2Key)
        }

        print("[AppDelegate] 🔍 needsReset: \(needsReset), needsForceReset: \(needsForceReset)")

        if needsForceReset {
            print("[AppDelegate] 🚀 Calling forceResetAllDailyCounters SYNCHRONOUSLY...")
            ScreenTimeService.shared.forceResetAllDailyCounters()
            print("[AppDelegate] ✅ Force reset complete - data should now show 0")
        } else if needsReset {
            print("[AppDelegate] 🚀 Calling handleMidnightTransition SYNCHRONOUSLY...")
            ScreenTimeService.shared.handleMidnightTransition()
            print("[AppDelegate] ✅ Daily reset complete")
        } else {
            print("[AppDelegate] ℹ️ No reset needed")
        }

        // Print debug info once after the reset decision
        ScreenTimeService.shared.usagePersistence.printDebugInfo()

        // Update last launch date
        defaults.set(Date(), forKey: lastLaunchDateKey)
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

    private func setupMidnightResetObserver() {
        // Primary method: NSCalendarDayChanged notification
        midnightResetObserver = NotificationCenter.default.addObserver(
            forName: .NSCalendarDayChanged,
            object: nil,
            queue: .main
        ) { _ in
            NSLog("[AppDelegate] 🌅 New day detected via NSCalendarDayChanged - resetting cumulative tracking")
            Task { @MainActor in
                await ScreenTimeService.shared.handleMidnightTransition()
            }
        }

        // PHASE 4 FIX: Timer-based backup mechanism
        // Schedule a timer to check at 00:00:30 every day as a failsafe
        scheduleMidnightCheckTimer()
    }

    /// Schedule a timer to fire shortly after midnight as a backup reset mechanism
    private func scheduleMidnightCheckTimer() {
        // Cancel existing timer if any
        midnightCheckTimer?.invalidate()

        let calendar = Calendar.current
        let now = Date()

        // Calculate next midnight + 30 seconds (to avoid exact midnight edge cases)
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = 0
        components.minute = 0
        components.second = 30

        guard var nextCheck = calendar.date(from: components) else {
            print("[AppDelegate] ❌ Failed to calculate next midnight check time")
            return
        }

        // If we've already passed 00:00:30 today, schedule for tomorrow
        if nextCheck <= now {
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: nextCheck) else {
                print("[AppDelegate] ❌ Failed to calculate tomorrow's midnight check")
                return
            }
            nextCheck = tomorrow
        }

        let timeInterval = nextCheck.timeIntervalSince(now)

        // Schedule the timer
        midnightCheckTimer = Timer.scheduledTimer(withTimeInterval: timeInterval, repeats: false) { [weak self] _ in
            NSLog("[AppDelegate] 🕐 Timer-based midnight check triggered at \(Date())")

            // Check if we need to reset
            let persistence = UsagePersistence()
            let startOfToday = calendar.startOfDay(for: Date())

            // Check if any app has stale data
            var needsReset = false
            let allApps = persistence.loadAllApps()
            for (_, app) in allApps {
                if app.lastResetDate < startOfToday {
                    needsReset = true
                    break
                }
            }

            if needsReset {
                NSLog("[AppDelegate] 🔄 Timer detected stale data - triggering reset")
                persistence.resetDailyCounters()
                NotificationCenter.default.post(name: .dailyUsageReset, object: nil)

                Task { @MainActor in
                    await ScreenTimeService.shared.handleMidnightTransition()
                }
            }

            // Schedule the next timer for tomorrow
            self?.scheduleMidnightCheckTimer()
        }

        #if DEBUG
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        print("[AppDelegate] ⏰ Scheduled midnight check timer for \(formatter.string(from: nextCheck))")
        #endif
    }

    /// Release in-memory caches when iOS signals memory pressure
    private func setupMemoryWarningObserver() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                AppIconCacheService.shared.clearMemoryCache()
            }
            print("[AppDelegate] ⚠️ Memory warning received — cleared in-memory caches")
        }
    }

    deinit {
        if let midnightResetObserver {
            NotificationCenter.default.removeObserver(midnightResetObserver)
        }
        midnightCheckTimer?.invalidate()
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
        // Handle notification tap and actions
        let userInfo = response.notification.request.content.userInfo
        let actionIdentifier = response.actionIdentifier

        #if DEBUG
        print("[AppDelegate] Notification action: \(actionIdentifier)")
        print("[AppDelegate] Notification userInfo: \(userInfo)")
        #endif

        Task { @MainActor in
            DeepLinkManager.shared.handleNotificationAction(
                actionIdentifier: actionIdentifier,
                userInfo: userInfo
            )
        }

        completionHandler()
    }
}
