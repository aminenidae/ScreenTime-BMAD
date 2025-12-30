import Foundation
import Combine
import CloudKit
import CoreData

@MainActor
class ParentRemoteViewModel: ObservableObject {
    @Published var linkedChildDevices: [RegisteredDevice] = []
    @Published var selectedChildDevice: RegisteredDevice?
    @Published var usageRecords: [UsageRecord] = []
    @Published var categorySummaries: [CategoryUsageSummary] = []
    @Published var dailySummaries: [DailySummary] = []
    @Published var appConfigurations: [AppConfiguration] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // Store summaries for each device (Multi-Child Device Support)
    @Published var deviceSummaries: [String: CategoryUsageSummary] = [:]

    private let cloudKitService = CloudKitSyncService.shared
    private let offlineQueue = OfflineQueueManager.shared
    private var cancellables = Set<AnyCancellable>()

    init() {
        setupCloudKitNotifications()
        Task {
            await loadLinkedChildDevices()
        }
    }

    deinit {
        cancellables.removeAll()
    }

    /// Setup CloudKit notifications to auto-refresh when data syncs
    private func setupCloudKitNotifications() {
        NotificationCenter.default.publisher(for: NSPersistentCloudKitContainer.eventChangedNotification)
            .sink { [weak self] notification in
                guard let self = self,
                      let event = notification.userInfo?["event"] as? NSPersistentCloudKitContainer.Event else {
                    return
                }

                // Auto-refresh when import completes successfully
                if event.type == .import && event.succeeded {
                    Task { @MainActor in
                        await self.loadLinkedChildDevices()
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    /// Load all linked child devices for the parent
    func loadLinkedChildDevices() async {
        #if DEBUG
        print("[ParentRemoteViewModel] ===== Loading Linked Child Devices =====")
        #endif

        isLoading = true
        errorMessage = nil

        do {
            linkedChildDevices = try await cloudKitService.fetchLinkedChildDevices()

            #if DEBUG
            print("[ParentRemoteViewModel] Loaded \(linkedChildDevices.count) child devices")
            #endif

            // If no device is selected and we have devices, select the first one
            if selectedChildDevice == nil, let firstDevice = linkedChildDevices.first {
                #if DEBUG
                print("[ParentRemoteViewModel] Auto-selecting first device: \(firstDevice.deviceID ?? "nil")")
                #endif
                selectedChildDevice = firstDevice
                await loadChildData(for: firstDevice)
            }
        } catch let error as CKError {
            #if DEBUG
            print("[ParentRemoteViewModel] CloudKit error: \(error)")
            #endif
            handleCloudKitError(error)
        } catch {
            errorMessage = "Failed to load child devices: \(error.localizedDescription)"
            print("[ParentRemoteViewModel] Error loading child devices: \(error)")
        }

        isLoading = false
    }
    
    /// Load usage data and configurations for a specific child device
    func loadChildData(for device: RegisteredDevice) async {
        isLoading = true
        errorMessage = nil
        
        selectedChildDevice = device
        
        do {
            // Load usage records for the last 7 days
            let calendar = Calendar.current
            let endDate = Date()
            let startDate = calendar.date(byAdding: .day, value: -7, to: endDate)!
            let dateRange = DateInterval(start: startDate, end: endDate)
            
            // Use the new CloudKit-based method to fetch usage data directly from shared zones
            usageRecords = try await cloudKitService.fetchChildUsageDataFromCloudKit(
                deviceID: device.deviceID ?? "",
                dateRange: dateRange
            )
            
            // Aggregate records by category
            await MainActor.run {
                self.categorySummaries = aggregateByCategory(self.usageRecords)
            }
            
            // Load daily summaries for the last 7 days
            dailySummaries = []
            for i in 0..<7 {
                if let date = calendar.date(byAdding: .day, value: -i, to: endDate) {
                    if let summary = try await cloudKitService.fetchChildDailySummary(
                        deviceID: device.deviceID ?? "",
                        date: date
                    ) {
                        dailySummaries.append(summary)
                    }
                }
            }
            
            // Load app configurations for the selected child device
            let context = PersistenceController.shared.container.viewContext
            let fetchRequest: NSFetchRequest<AppConfiguration> = AppConfiguration.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "deviceID == %@", device.deviceID ?? "")
            
            appConfigurations = try context.fetch(fetchRequest)
        } catch let error as CKError {
            handleCloudKitError(error)
        } catch {
            errorMessage = "Failed to load child data: \(error.localizedDescription)"
            print("[ParentRemoteViewModel] Error loading child data: \(error)")
        }
        
        isLoading = false
    }
    
    /// Send a configuration update to a child device
    func sendConfigurationUpdate(_ configuration: AppConfiguration) async {
        guard let selectedDevice = selectedChildDevice else { return }
        
        do {
            try await cloudKitService.sendConfigurationToChild(
                deviceID: selectedDevice.deviceID ?? "",
                configuration: configuration
            )
            
            // Refresh configurations
            await loadChildData(for: selectedDevice)
        } catch let error as CKError {
            handleCloudKitError(error)
        } catch {
            errorMessage = "Failed to send configuration: \(error.localizedDescription)"
            print("[ParentRemoteViewModel] Error sending configuration: \(error)")
        }
    }
    
    /// Request a sync from the child device
    func requestChildSync() async {
        guard let selectedDevice = selectedChildDevice else { return }
        
        do {
            try await cloudKitService.requestChildSync(deviceID: selectedDevice.deviceID ?? "")
        } catch let error as CKError {
            handleCloudKitError(error)
        } catch {
            errorMessage = "Failed to request sync: \(error.localizedDescription)"
            print("[ParentRemoteViewModel] Error requesting sync: \(error)")
        }
    }
    
    /// Force a sync now
    func forceSyncNow() async {
        do {
            try await cloudKitService.forceSyncNow()
        } catch let error as CKError {
            handleCloudKitError(error)
        } catch {
            errorMessage = "Failed to force sync: \(error.localizedDescription)"
            print("[ParentRemoteViewModel] Error forcing sync: \(error)")
        }
    }
    
    /// Handle CloudKit specific errors
    private func handleCloudKitError(_ error: CKError) {
        switch error.code {
        case .notAuthenticated:
            errorMessage = "iCloud account not signed in. Please sign in to iCloud in Settings."
        case .networkUnavailable, .networkFailure:
            errorMessage = "Network unavailable. Please check your connection and try again."
        case .quotaExceeded:
            errorMessage = "iCloud storage quota exceeded. Please free up space in iCloud."
        case .zoneBusy:
            errorMessage = "iCloud is busy. Please try again in a moment."
        case .badContainer, .badDatabase:
            errorMessage = "iCloud configuration error. Please contact support."
        case .permissionFailure:
            errorMessage = "Insufficient permissions. Please check iCloud settings."
        default:
            errorMessage = "iCloud error: \(error.localizedDescription)"
        }
        
        print("[ParentRemoteViewModel] CloudKit error (\(error.code)): \(error.localizedDescription)")
    }
    
    /// De-duplicate and aggregate usage records for the same app
    /// When the child device syncs records from multiple days, we may receive multiple records per app.
    /// This function aggregates all records for each unique app into a single summary record.
    private func deduplicateRecords(_ records: [UsageRecord]) -> [UsageRecord] {
        #if DEBUG
        print("[ParentRemoteViewModel] 🔍 De-duplicating and aggregating \(records.count) records...")
        #endif

        // Group by logicalID to find all records for each unique app
        let groupedByApp = Dictionary(grouping: records) { $0.logicalID ?? "unknown" }

        var aggregated: [UsageRecord] = []

        for (logicalID, appRecords) in groupedByApp {
            #if DEBUG
            if appRecords.count > 1 {
                print("[ParentRemoteViewModel] 🔍 Found \(appRecords.count) records for \(logicalID) - aggregating...")
            }
            #endif

            // Find the record with the most recent sessionEnd (for display name, category, etc.)
            let mostRecentRecord = appRecords.max { a, b in
                guard let aEnd = a.sessionEnd, let bEnd = b.sessionEnd else {
                    return (a.sessionEnd == nil) && (b.sessionEnd != nil)
                }
                return aEnd < bEnd
            } ?? appRecords[0]

            // Sum up total seconds and points from all records
            let totalSeconds = appRecords.reduce(0) { $0 + Int($1.totalSeconds) }
            let totalPoints = appRecords.reduce(0) { $0 + Int($1.earnedPoints) }

            // Create an aggregated record using the most recent record as template
            let entity = NSEntityDescription.entity(forEntityName: "UsageRecord", in: PersistenceController.shared.container.viewContext)!
            let aggregatedRecord = UsageRecord(entity: entity, insertInto: nil)

            // Copy metadata from most recent record
            aggregatedRecord.recordID = mostRecentRecord.recordID
            aggregatedRecord.deviceID = mostRecentRecord.deviceID
            aggregatedRecord.logicalID = logicalID
            aggregatedRecord.displayName = mostRecentRecord.displayName
            aggregatedRecord.category = mostRecentRecord.category
            aggregatedRecord.sessionStart = appRecords.compactMap { $0.sessionStart }.min() // Earliest session
            aggregatedRecord.sessionEnd = mostRecentRecord.sessionEnd // Latest session end
            aggregatedRecord.syncTimestamp = mostRecentRecord.syncTimestamp

            // Set aggregated totals
            aggregatedRecord.totalSeconds = Int32(totalSeconds)
            aggregatedRecord.earnedPoints = Int32(totalPoints)

            #if DEBUG
            if appRecords.count > 1 {
                let individualTotals = appRecords.map { Int($0.totalSeconds) }
                print("[ParentRemoteViewModel]   ✅ Aggregated \(appRecords.count) records: \(individualTotals) → \(totalSeconds)s total")
            }
            #endif

            aggregated.append(aggregatedRecord)
        }

        #if DEBUG
        print("[ParentRemoteViewModel] ✅ Aggregation complete: \(records.count) records → \(aggregated.count) unique apps")
        #endif

        return aggregated
    }

    func aggregateByCategory(_ records: [UsageRecord]) -> [CategoryUsageSummary] {
        #if DEBUG
        print("[ParentRemoteViewModel] ===== Aggregating \(records.count) Records by Category =====")
        for record in records {
            print("[ParentRemoteViewModel]   Record: \(record.logicalID ?? "nil") | Category: '\(record.category ?? "nil")' | Time: \(record.totalSeconds)s")
        }
        #endif

        // De-duplicate overlapping records first
        let uniqueRecords = deduplicateRecords(records)

        #if DEBUG
        print("[ParentRemoteViewModel] After de-duplication: \(uniqueRecords.count) unique records")
        #endif

        let grouped = Dictionary(grouping: uniqueRecords) { $0.category ?? "Unknown" }

        #if DEBUG
        print("[ParentRemoteViewModel] Grouped into \(grouped.keys.count) categories: \(Array(grouped.keys))")
        #endif

        let summaries = grouped.map { category, apps in
            CategoryUsageSummary(
                category: category,
                totalSeconds: apps.reduce(0) { $0 + Int($1.totalSeconds) },
                appCount: apps.count,
                totalPoints: apps.reduce(0) { $0 + Int($1.earnedPoints) },
                apps: apps
            )
        }.sorted { $0.totalSeconds > $1.totalSeconds }

        #if DEBUG
        print("[ParentRemoteViewModel] Created \(summaries.count) category summaries:")
        for summary in summaries {
            print("[ParentRemoteViewModel]   📊 \(summary.category): \(summary.appCount) apps, \(summary.totalSeconds)s, \(summary.totalPoints) pts")
        }
        print("[ParentRemoteViewModel] ===== End Category Aggregation =====")
        #endif

        return summaries
    }
    
    // Load summary for a specific device (Multi-Child Device Support)
    func loadDeviceSummary(for device: RegisteredDevice) async {
        guard let deviceID = device.deviceID else { return }

        // Load today's summary for this device
        await loadChildData(for: device)

        // Create summary from loaded data
        let summary = createTodaySummary(for: deviceID)

        await MainActor.run {
            self.deviceSummaries[deviceID] = summary
        }
    }

    private func createTodaySummary(for deviceID: String) -> CategoryUsageSummary {
        // Aggregate today's usage for this device
        let deviceRecords = usageRecords.filter { record in
            record.deviceID == deviceID &&
            Calendar.current.isDateInToday(record.sessionStart ?? Date())
        }

        let totalSeconds = deviceRecords.reduce(0) { $0 + Int($1.totalSeconds) }
        let totalPoints = deviceRecords.reduce(0) { $0 + Int($1.earnedPoints) }
        let appCount = Set(deviceRecords.compactMap { $0.logicalID }).count

        return CategoryUsageSummary(
            category: "All Apps",
            totalSeconds: totalSeconds,
            appCount: appCount,
            totalPoints: totalPoints,
            apps: deviceRecords
        )
    }
}