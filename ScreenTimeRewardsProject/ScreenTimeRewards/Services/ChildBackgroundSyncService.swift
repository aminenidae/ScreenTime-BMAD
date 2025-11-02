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
        
        #if DEBUG
        print("[ChildBackgroundSyncService] Background tasks registered")
        #endif
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
