import BackgroundTasks
import Foundation
import CoreData
import Combine

/// Subscription status from parent's Firebase family
enum ParentSubscriptionStatus: String, Codable {
    case active
    case trial
    case grace
    case expired
    case unpaired

    var allowsFullAccess: Bool {
        switch self {
        case .active, .trial, .grace:
            return true
        case .expired, .unpaired:
            return false
        }
    }
}

class ChildBackgroundSyncService: ObservableObject {
    static let shared = ChildBackgroundSyncService()

    // MARK: - Published State

    /// Current subscription status from parent's family
    @Published private(set) var parentSubscriptionStatus: ParentSubscriptionStatus = .unpaired

    /// Whether child has full access (paired with subscribed parent)
    @Published private(set) var hasFullAccess: Bool = true

    /// Days remaining in trial (for Family path)
    @Published private(set) var trialDaysRemaining: Int?

    private let cloudKitService = CloudKitSyncService.shared
    private let offlineQueue = OfflineQueueManager.shared

    private init() {
        loadCachedSubscriptionStatus()
    }
    
    /// Register background tasks for usage upload and configuration checking
    func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.screentimerewards.usage-upload",
            using: nil
        ) { task in
            self.handleUsageUploadTask(task)
        }

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.screentimerewards.config-check",
            using: nil
        ) { task in
            self.handleConfigCheckTask(task)
        }

        // PHASE 2 FIX: Register midnight reset task
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.screentimerewards.midnight-reset",
            using: nil
        ) { task in
            self.handleMidnightResetTask(task)
        }

        // Register subscription verification task (Firebase validation)
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.screentimerewards.subscription-verify",
            using: nil
        ) { task in
            self.handleSubscriptionVerifyTask(task)
        }

        // Register shield state sync task (BGAppRefreshTask for more frequent updates)
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.screentimerewards.shield-state-sync",
            using: nil
        ) { task in
            self.handleShieldStateSyncTask(task as! BGAppRefreshTask)
        }

        #if DEBUG
        print("[ChildBackgroundSyncService] Background tasks registered")
        #endif

        // Schedule the midnight reset task for the next midnight
        scheduleMidnightReset()

        // Schedule initial subscription verification
        scheduleSubscriptionVerification()

        // Schedule shield state sync (more frequent than BGProcessingTask)
        scheduleShieldStateSync()
    }
    
    /// Schedule a usage upload task
    func scheduleUsageUpload() {
        let request = BGProcessingTaskRequest(identifier: "com.screentimerewards.usage-upload")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 1) // Start almost immediately
        request.requiresNetworkConnectivity = true
        
        do {
            try BGTaskScheduler.shared.submit(request)
            #if DEBUG
            print("[ChildBackgroundSyncService] Scheduled immediate usage upload")
            #endif
        } catch {
            #if DEBUG
            print("[ChildBackgroundSyncService] Failed to schedule usage upload: \(error)")
            #endif
        }
    }
    
    /// Schedule a config check task
    func scheduleConfigCheck() {
        let request = BGProcessingTaskRequest(identifier: "com.screentimerewards.config-check")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 1) // Start almost immediately
        request.requiresNetworkConnectivity = true
        
        do {
            try BGTaskScheduler.shared.submit(request)
            #if DEBUG
            print("[ChildBackgroundSyncService] Scheduled immediate config check")
            #endif
        } catch {
            #if DEBUG
            print("[ChildBackgroundSyncService] Failed to schedule config check: \(error)")
            #endif
        }
    }
    
    /// Handle usage upload background task
    func handleUsageUploadTask(_ task: BGTask) {
        #if DEBUG
        print("[ChildBackgroundSyncService] Handling usage upload task")
        #endif

        // Check if still paired with parent before syncing
        guard DevicePairingService.shared.hasValidPairing() else {
            #if DEBUG
            print("[ChildBackgroundSyncService] ⏭️ Skipping upload - no valid pairing")
            #endif
            task.setTaskCompleted(success: true) // Complete without error since unpaired is expected state
            return
        }

        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }

        Task {
            do {
                // Upload usage records to parent's shared zone (Task 7)
                try await self.uploadUsageRecordsToParent()
                
                // Process the offline queue which includes other uploads
                await self.offlineQueue.processQueue()
                
                // Schedule next task
                self.scheduleNextUsageUpload()
                
                task.setTaskCompleted(success: true)
            } catch {
                #if DEBUG
                print("[ChildBackgroundSyncService] Usage upload task failed: \(error)")
                #endif
                
                // Schedule next task even on failure
                self.scheduleNextUsageUpload()
                
                task.setTaskCompleted(success: false)
            }
        }
    }
    
    /// Handle configuration check background task
    func handleConfigCheckTask(_ task: BGTask) {
        #if DEBUG
        print("[ChildBackgroundSyncService] Handling config check task")
        #endif

        // Check if still paired with parent before syncing
        guard DevicePairingService.shared.hasValidPairing() else {
            #if DEBUG
            print("[ChildBackgroundSyncService] ⏭️ Skipping config check - no valid pairing")
            #endif
            task.setTaskCompleted(success: true) // Complete without error since unpaired is expected state
            return
        }

        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }

        Task {
            do {
                // Check for configuration updates
                try await self.checkForConfigurationUpdates()
                
                // Schedule next task
                self.scheduleNextConfigCheck()
                
                task.setTaskCompleted(success: true)
            } catch {
                #if DEBUG
                print("[ChildBackgroundSyncService] Config check task failed: \(error)")
                #endif
                
                // Schedule next task even on failure
                self.scheduleNextConfigCheck()
                
                task.setTaskCompleted(success: false)
            }
        }
    }
    
    /// Check for configuration updates from parent device
    func checkForConfigurationUpdates() async throws {
        #if DEBUG
        print("[ChildBackgroundSyncService] Checking for configuration updates")
        #endif

        // 1. Process any pending full config commands from parent
        var configsWereUpdated = false
        do {
            let processedCount = try await ChildConfigCommandProcessor.shared.processPendingCommands()
            if processedCount > 0 {
                configsWereUpdated = true
                #if DEBUG
                print("[ChildBackgroundSyncService] Processed \(processedCount) parent config command(s)")
                #endif
            }
        } catch {
            #if DEBUG
            print("[ChildBackgroundSyncService] Error processing parent commands: \(error)")
            #endif
            // Continue even if command processing fails - don't block other updates
        }

        // 2. Download and apply basic configuration updates (legacy path)
        do {
            let configurations = try await cloudKitService.downloadParentConfiguration()

            // Apply configurations
            let screenTimeService = await ScreenTimeService.shared
            for config in configurations {
                await screenTimeService.applyCloudKitConfiguration(config)
            }

            if !configurations.isEmpty {
                configsWereUpdated = true
            }

            #if DEBUG
            print("[ChildBackgroundSyncService] Applied \(configurations.count) configuration updates")
            #endif
        } catch {
            #if DEBUG
            print("[ChildBackgroundSyncService] Failed to check for configuration updates: \(error)")
            #endif
            throw error
        }

        // 3. Sync goal configs to extension if any configurations were updated
        // This ensures the DeviceActivityMonitorExtension has the latest learning goal requirements
        if configsWereUpdated {
            await syncGoalConfigsToExtension()
        }

        // 4. Check extension state and sync to CloudKit
        // This ensures parent dashboard shows current shield state after config updates
        await syncExtensionStateToCloudKit()
    }

    /// Sync goal configs to extension after background config update
    @MainActor
    private func syncGoalConfigsToExtension() {
        #if DEBUG
        print("[ChildBackgroundSyncService] Syncing goal configs to extension after background update")
        #endif

        ScreenTimeService.shared.syncGoalConfigsToExtension()

        #if DEBUG
        print("[ChildBackgroundSyncService] ✅ Goal configs synced to extension")
        #endif
    }

    /// Sync extension state to CloudKit after background operations
    @MainActor
    private func syncExtensionStateToCloudKit() async {
        #if DEBUG
        print("[ChildBackgroundSyncService] Checking extension state for CloudKit sync")
        #endif

        // Check if extension made any state changes
        BlockingCoordinator.shared.checkExtensionUnlockState()

        // Upload current shield states to parent
        do {
            try await CloudKitSyncService.shared.uploadShieldStatesToParent()
            #if DEBUG
            print("[ChildBackgroundSyncService] ✅ Shield states uploaded to parent CloudKit")
            #endif
        } catch {
            #if DEBUG
            print("[ChildBackgroundSyncService] ⚠️ Failed to upload shield states: \(error)")
            #endif
        }
    }
    
    /// Schedule next usage upload task
    func scheduleNextUsageUpload() {
        let request = BGProcessingTaskRequest(identifier: "com.screentimerewards.usage-upload")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60) // 30 minutes
        request.requiresNetworkConnectivity = true
        
        do {
            try BGTaskScheduler.shared.submit(request)
            #if DEBUG
            print("[ChildBackgroundSyncService] Scheduled next usage upload task")
            #endif
        } catch {
            #if DEBUG
            print("[ChildBackgroundSyncService] Failed to schedule usage upload task: \(error)")
            #endif
        }
    }
    
    /// Schedule next config check task
    func scheduleNextConfigCheck() {
        let request = BGProcessingTaskRequest(identifier: "com.screentimerewards.config-check")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 minutes
        request.requiresNetworkConnectivity = true

        do {
            try BGTaskScheduler.shared.submit(request)
            #if DEBUG
            print("[ChildBackgroundSyncService] Scheduled next config check task")
            #endif
        } catch {
            #if DEBUG
            print("[ChildBackgroundSyncService] Failed to schedule config check task: \(error)")
            #endif
        }
    }

    // MARK: - Midnight Reset Task (PHASE 2 FIX)

    /// Handle midnight reset background task
    func handleMidnightResetTask(_ task: BGTask) {
        #if DEBUG
        print("[ChildBackgroundSyncService] 🕐 Handling midnight reset task at \(Date())")
        #endif

        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }

        // Reset daily usage counters
        let persistence = UsagePersistence()
        persistence.resetDailyCounters()

        // Notify the app if it's running
        NotificationCenter.default.post(name: .dailyUsageReset, object: nil)

        #if DEBUG
        print("[ChildBackgroundSyncService] ✅ Daily usage counters reset successfully")
        #endif

        // Schedule the next midnight reset
        scheduleMidnightReset()

        task.setTaskCompleted(success: true)
    }

    /// Schedule midnight reset task for the next midnight
    func scheduleMidnightReset() {
        let calendar = Calendar.current
        let now = Date()

        // Calculate next midnight (00:01 to avoid exact midnight edge cases)
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = 0
        components.minute = 1
        components.second = 0

        guard var nextMidnight = calendar.date(from: components) else {
            #if DEBUG
            print("[ChildBackgroundSyncService] ❌ Failed to calculate next midnight")
            #endif
            return
        }

        // If we've already passed 00:01 today, schedule for tomorrow
        if nextMidnight <= now {
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: nextMidnight) else {
                #if DEBUG
                print("[ChildBackgroundSyncService] ❌ Failed to calculate tomorrow's midnight")
                #endif
                return
            }
            nextMidnight = tomorrow
        }

        let request = BGAppRefreshTaskRequest(identifier: "com.screentimerewards.midnight-reset")
        request.earliestBeginDate = nextMidnight

        do {
            try BGTaskScheduler.shared.submit(request)
            #if DEBUG
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            print("[ChildBackgroundSyncService] 🕐 Scheduled midnight reset for \(formatter.string(from: nextMidnight))")
            #endif
        } catch {
            #if DEBUG
            print("[ChildBackgroundSyncService] ❌ Failed to schedule midnight reset: \(error)")
            #endif
        }
    }

    // === TASK 7 TRIGGER IMPLEMENTATION ===
    /// Upload unsynced usage records to parent's shared zone
    func uploadUsageRecordsToParent() async throws {
        #if DEBUG
        print("[ChildBackgroundSyncService] ===== Uploading Usage Records To Parent =====")
        #endif
        
        // Check if device is paired with a parent (supports multi-parent format)
        let pairedParents = DevicePairingService.shared.getPairedParents()
        guard !pairedParents.isEmpty else {
            #if DEBUG
            print("[ChildBackgroundSyncService] Device not paired with parent, skipping upload")
            #endif
            return
        }
        
        // Fetch unsynced usage records
        let context = PersistenceController.shared.container.viewContext
        let fetchRequest: NSFetchRequest<UsageRecord> = UsageRecord.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "isSynced == NO")
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "sessionStart", ascending: true)]
        
        let unsyncedRecords = try context.fetch(fetchRequest)
        
        #if DEBUG
        print("[ChildBackgroundSyncService] Found \(unsyncedRecords.count) unsynced usage records")
        #endif
        
        if !unsyncedRecords.isEmpty {
            // Upload to parent's shared zone
            try await cloudKitService.uploadUsageRecordsToParent(unsyncedRecords)
            
            #if DEBUG
            print("[ChildBackgroundSyncService] ✅ Successfully uploaded \(unsyncedRecords.count) usage records to parent")
            #endif
        } else {
            #if DEBUG
            print("[ChildBackgroundSyncService] No unsynced records to upload")
            #endif
        }
    }
    
    /// Trigger immediate usage upload to parent
    func triggerImmediateUsageUpload() async {
        #if DEBUG
        print("[ChildBackgroundSyncService] Triggering immediate usage upload to parent")
        #endif
        
        do {
            try await uploadUsageRecordsToParent()
        } catch {
            #if DEBUG
            print("[ChildBackgroundSyncService] Immediate usage upload failed: \(error)")
            #endif
        }
    }
    // === END TASK 7 TRIGGER IMPLEMENTATION ===
    
    /// Trigger immediate usage upload
    func triggerImmediateUpload() async {
        #if DEBUG
        print("[ChildBackgroundSyncService] Triggering immediate upload")
        #endif

        // Process the offline queue immediately
        await offlineQueue.processQueue()
    }

    // MARK: - Subscription Verification (Firebase)

    /// Handle subscription verification background task
    func handleSubscriptionVerifyTask(_ task: BGTask) {
        #if DEBUG
        print("[ChildBackgroundSyncService] 🔐 Handling subscription verification task")
        #endif

        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }

        Task {
            await verifyParentSubscription()
            scheduleSubscriptionVerification()
            task.setTaskCompleted(success: true)
        }
    }

    /// Schedule subscription verification task (daily)
    func scheduleSubscriptionVerification() {
        let request = BGProcessingTaskRequest(identifier: "com.screentimerewards.subscription-verify")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 24 * 60 * 60) // 24 hours
        request.requiresNetworkConnectivity = true

        do {
            try BGTaskScheduler.shared.submit(request)
            #if DEBUG
            print("[ChildBackgroundSyncService] 🔐 Scheduled subscription verification (24 hours)")
            #endif
        } catch {
            #if DEBUG
            print("[ChildBackgroundSyncService] ❌ Failed to schedule subscription verification: \(error)")
            #endif
        }
    }

    /// Verify parent's subscription status via Firebase
    @MainActor
    func verifyParentSubscription() async {
        #if DEBUG
        print("[ChildBackgroundSyncService] 🔐 Verifying parent subscription...")
        #endif

        // Check if device is paired
        guard DevicePairingService.shared.hasValidPairing() else {
            // Not paired - check if in trial period
            updateStatusForUnpairedDevice()
            return
        }

        // Verify with Firebase
        do {
            let isValid = try await FirebaseValidationService.shared.verifyFamilySubscription()

            if isValid {
                parentSubscriptionStatus = .active
                hasFullAccess = true
                trialDaysRemaining = nil
                cacheSubscriptionStatus()

                #if DEBUG
                print("[ChildBackgroundSyncService] ✅ Parent subscription is active")
                #endif
            } else {
                parentSubscriptionStatus = .expired
                hasFullAccess = false
                trialDaysRemaining = nil
                cacheSubscriptionStatus()

                #if DEBUG
                print("[ChildBackgroundSyncService] ⚠️ Parent subscription expired")
                #endif

                // Post notification for UI to show limited mode
                NotificationCenter.default.post(name: .parentSubscriptionExpired, object: nil)
            }
        } catch {
            #if DEBUG
            print("[ChildBackgroundSyncService] ❌ Subscription verification failed: \(error)")
            #endif

            // On error, use cached status with grace period
            // hasFullAccess remains at cached value
        }
    }

    /// Update status for unpaired device (trial check)
    private func updateStatusForUnpairedDevice() {
        // Check if we're in a trial period (Family path onboarding)
        if let trialStartString = UserDefaults.standard.string(forKey: "family_trial_start"),
           let trialStart = ISO8601DateFormatter().date(from: trialStartString) {

            let daysSinceStart = Calendar.current.dateComponents([.day], from: trialStart, to: Date()).day ?? 0
            let trialDays = 14
            let remaining = max(0, trialDays - daysSinceStart)

            trialDaysRemaining = remaining

            if remaining > 0 {
                parentSubscriptionStatus = .trial
                hasFullAccess = true

                #if DEBUG
                print("[ChildBackgroundSyncService] 📅 Trial period: \(remaining) days remaining")
                #endif
            } else {
                parentSubscriptionStatus = .expired
                hasFullAccess = false

                #if DEBUG
                print("[ChildBackgroundSyncService] ⚠️ Trial period expired")
                #endif

                // Post notification for UI to show limited mode
                NotificationCenter.default.post(name: .trialExpired, object: nil)
            }
        } else {
            // No trial, not paired - limited access
            parentSubscriptionStatus = .unpaired
            hasFullAccess = false
            trialDaysRemaining = nil

            #if DEBUG
            print("[ChildBackgroundSyncService] ⚠️ Device not paired and no trial")
            #endif
        }

        cacheSubscriptionStatus()
    }

    /// Start the 14-day trial (called from Family path onboarding)
    func startFamilyTrial() {
        let now = ISO8601DateFormatter().string(from: Date())
        UserDefaults.standard.set(now, forKey: "family_trial_start")

        parentSubscriptionStatus = .trial
        hasFullAccess = true
        trialDaysRemaining = 14

        cacheSubscriptionStatus()

        #if DEBUG
        print("[ChildBackgroundSyncService] 🎁 Started 14-day family trial")
        #endif
    }

    // MARK: - Testing Helper (REMOVE BEFORE RELEASE)
    /// Reset trial for testing purposes - gives fresh 14 days
    static func resetTrialForTesting() {
        let defaults = UserDefaults.standard
        // Set trial start to now (gives fresh 14 days)
        defaults.set(ISO8601DateFormatter().string(from: Date()), forKey: "family_trial_start")
        defaults.set(SubscriptionStatus.trial.rawValue, forKey: "cached_parent_subscription_status")
        defaults.set(true, forKey: "cached_has_full_access")
        defaults.set(14, forKey: "cached_trial_days_remaining")
        defaults.synchronize()
        print("[ChildBackgroundSyncService] 🔓 Trial reset for testing - 14 days from now")
    }

    /// Cache subscription status locally
    private func cacheSubscriptionStatus() {
        UserDefaults.standard.set(parentSubscriptionStatus.rawValue, forKey: "cached_parent_subscription_status")
        UserDefaults.standard.set(hasFullAccess, forKey: "cached_has_full_access")
        if let days = trialDaysRemaining {
            UserDefaults.standard.set(days, forKey: "cached_trial_days_remaining")
        } else {
            UserDefaults.standard.removeObject(forKey: "cached_trial_days_remaining")
        }
        UserDefaults.standard.set(Date(), forKey: "subscription_status_cached_at")
    }

    /// Load cached subscription status
    private func loadCachedSubscriptionStatus() {
        if let statusString = UserDefaults.standard.string(forKey: "cached_parent_subscription_status"),
           let status = ParentSubscriptionStatus(rawValue: statusString) {
            parentSubscriptionStatus = status
        }

        hasFullAccess = UserDefaults.standard.bool(forKey: "cached_has_full_access")

        if UserDefaults.standard.object(forKey: "cached_trial_days_remaining") != nil {
            trialDaysRemaining = UserDefaults.standard.integer(forKey: "cached_trial_days_remaining")
        }

        // Check if cached status is stale (> 7 days old) - default to restricted if so
        if let cachedAt = UserDefaults.standard.object(forKey: "subscription_status_cached_at") as? Date {
            let daysSinceCached = Calendar.current.dateComponents([.day], from: cachedAt, to: Date()).day ?? 0
            if daysSinceCached > 7 {
                #if DEBUG
                print("[ChildBackgroundSyncService] ⚠️ Cached subscription status is stale, defaulting to restricted")
                #endif
                hasFullAccess = false
            }
        }
    }

    /// Trigger immediate subscription verification
    func triggerImmediateSubscriptionVerification() async {
        await verifyParentSubscription()
    }

    // MARK: - Shield State Sync Task (BGAppRefreshTask)

    /// Handle shield state sync background app refresh task
    /// This runs more frequently than BGProcessingTask to keep parent dashboard updated
    func handleShieldStateSyncTask(_ task: BGAppRefreshTask) {
        #if DEBUG
        print("[ChildBackgroundSyncService] 🛡️ Handling shield state sync task")
        #endif

        // Check if still paired with parent before syncing
        guard DevicePairingService.shared.hasValidPairing() else {
            #if DEBUG
            print("[ChildBackgroundSyncService] ⏭️ Skipping shield sync - no valid pairing")
            #endif
            task.setTaskCompleted(success: true)
            return
        }

        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }

        Task {
            do {
                // Sync extension state to CloudKit
                await syncExtensionStateToCloudKit()

                // Schedule next sync
                scheduleShieldStateSync()

                task.setTaskCompleted(success: true)

                #if DEBUG
                print("[ChildBackgroundSyncService] ✅ Shield state sync completed")
                #endif
            }
        }
    }

    /// Schedule shield state sync task (using BGAppRefreshTask for more frequent updates)
    func scheduleShieldStateSync() {
        let request = BGAppRefreshTaskRequest(identifier: "com.screentimerewards.shield-state-sync")
        // Request to run in 15 minutes (iOS may adjust based on usage patterns)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)

        do {
            try BGTaskScheduler.shared.submit(request)
            #if DEBUG
            print("[ChildBackgroundSyncService] 🛡️ Scheduled shield state sync (15 min)")
            #endif
        } catch {
            #if DEBUG
            print("[ChildBackgroundSyncService] ❌ Failed to schedule shield state sync: \(error)")
            #endif
        }
    }

    // MARK: - Development Mode

    #if DEBUG
    /// Grant dev access on child device (for testing).
    /// This bypasses parent subscription verification.
    func activateDevAccess() {
        parentSubscriptionStatus = .active
        hasFullAccess = true
        trialDaysRemaining = nil
        print("[ChildBackgroundSyncService] 🔓 Dev access activated")
    }
    #endif
}

// MARK: - Notification Names

extension Notification.Name {
    static let parentSubscriptionExpired = Notification.Name("parentSubscriptionExpired")
    static let trialExpired = Notification.Name("trialExpired")
    // dailyUsageReset is defined in ScreenTimeNotifications.swift
}
