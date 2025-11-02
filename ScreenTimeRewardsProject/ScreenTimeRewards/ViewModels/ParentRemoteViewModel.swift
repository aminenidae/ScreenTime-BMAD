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

                #if DEBUG
                print("[ParentRemoteViewModel] CloudKit event: \(event)")
                #endif

                // Auto-refresh when import completes successfully
                if event.type == .import && event.succeeded {
                    #if DEBUG
                    print("[ParentRemoteViewModel] CloudKit import succeeded, refreshing child devices...")
                    #endif

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
    
    /// De-duplicate overlapping usage records for the same app
    /// When the child device updates a record multiple times, we may receive multiple versions.
    /// This function keeps only the most recent/complete record for each unique session.
    private func deduplicateRecords(_ records: [UsageRecord]) -> [UsageRecord] {
        #if DEBUG
        print("[ParentRemoteViewModel] 🔍 De-duplicating \(records.count) records...")
        #endif

        // Group by logicalID to find potential duplicates
        let groupedByApp = Dictionary(grouping: records) { $0.logicalID ?? "unknown" }

        var deduplicated: [UsageRecord] = []

        for (logicalID, appRecords) in groupedByApp {
            if appRecords.count == 1 {
                // No duplicates for this app
                deduplicated.append(appRecords[0])
                continue
            }

            // Multiple records for same app - check for overlapping sessions
            #if DEBUG
            print("[ParentRemoteViewModel] 🔍 Found \(appRecords.count) records for \(logicalID)")
            #endif

            // Group by session start time (records with same/similar start are likely duplicates)
            var sessionGroups: [[UsageRecord]] = []

            for record in appRecords {
                guard let sessionStart = record.sessionStart else {
                    deduplicated.append(record)
                    continue
                }

                // Find a group with matching start time (within 1 minute tolerance)
                var foundGroup = false
                for i in 0..<sessionGroups.count {
                    if let firstRecordStart = sessionGroups[i].first?.sessionStart,
                       abs(sessionStart.timeIntervalSince(firstRecordStart)) < 60 {
                        sessionGroups[i].append(record)
                        foundGroup = true
                        break
                    }
                }

                if !foundGroup {
                    sessionGroups.append([record])
                }
            }

            // For each session group, keep only the record with latest sessionEnd (most complete)
            for group in sessionGroups {
                let mostRecent = group.max { a, b in
                    guard let aEnd = a.sessionEnd, let bEnd = b.sessionEnd else {
                        return a.totalSeconds < b.totalSeconds
                    }
                    return aEnd < bEnd
                }

                if let record = mostRecent {
                    #if DEBUG
                    print("[ParentRemoteViewModel]   ✅ Keeping most recent: \(record.totalSeconds)s (discarding \(group.count - 1) older versions)")
                    #endif
                    deduplicated.append(record)
                }
            }
        }

        #if DEBUG
        print("[ParentRemoteViewModel] ✅ De-duplication complete: \(records.count) → \(deduplicated.count) records")
        #endif

        return deduplicated
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