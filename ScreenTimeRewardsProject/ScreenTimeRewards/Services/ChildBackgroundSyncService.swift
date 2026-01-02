import BackgroundTasks
import Foundation
import CoreData

class ChildBackgroundSyncService {
    static let shared = ChildBackgroundSyncService()
    
    private let cloudKitService = CloudKitSyncService.shared
    private let offlineQueue = OfflineQueueManager.shared
    
    private init() {}
    
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

        #if DEBUG
        print("[ChildBackgroundSyncService] Background tasks registered")
        #endif

        // Schedule the midnight reset task for the next midnight
        scheduleMidnightReset()
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
        do {
            let processedCount = try await ChildConfigCommandProcessor.shared.processPendingCommands()
            #if DEBUG
            if processedCount > 0 {
                print("[ChildBackgroundSyncService] Processed \(processedCount) parent config command(s)")
            }
            #endif
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
            let screenTimeService = ScreenTimeService.shared
            for config in configurations {
                screenTimeService.applyCloudKitConfiguration(config)
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
        
        // Check if device is paired with a parent
        guard UserDefaults.standard.string(forKey: "parentDeviceID") != nil else {
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
}
