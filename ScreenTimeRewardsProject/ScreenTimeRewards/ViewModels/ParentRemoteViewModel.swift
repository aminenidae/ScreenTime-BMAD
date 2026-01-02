import Foundation
import Combine
import CloudKit
import CoreData

// MARK: - Full App Configuration DTO

/// Data transfer object containing full app configuration data from CloudKit
/// Includes schedule, linked apps, and streak settings that were JSON-encoded
struct FullAppConfigDTO: Identifiable, Hashable {
    var id: String { logicalID }

    // Basic fields
    let logicalID: String
    let deviceID: String
    let displayName: String
    let category: String
    let pointsPerMinute: Int
    let isEnabled: Bool
    let blockingEnabled: Bool
    let tokenHash: String?
    let lastModified: Date?
    let iconURL: String?

    // Full schedule configuration (decoded from JSON)
    var scheduleConfig: AppScheduleConfiguration?

    // Quick-access fields for display
    var dailyLimitSummary: String?
    var timeWindowSummary: String?

    // Linked learning apps (decoded from JSON)
    var linkedLearningApps: [LinkedLearningApp]
    var unlockMode: UnlockMode

    // Streak settings (decoded from JSON)
    var streakSettings: AppStreakSettings?

    /// Create from a CloudKit record
    init(from record: CKRecord) {
        self.logicalID = record["CD_logicalID"] as? String ?? ""
        self.deviceID = record["CD_deviceID"] as? String ?? ""
        self.displayName = record["CD_displayName"] as? String ?? "Unknown"
        self.category = record["CD_category"] as? String ?? "Unknown"
        self.pointsPerMinute = record["CD_pointsPerMinute"] as? Int ?? 1
        self.isEnabled = record["CD_isEnabled"] as? Bool ?? true
        self.blockingEnabled = record["CD_blockingEnabled"] as? Bool ?? false
        self.tokenHash = record["CD_tokenHash"] as? String
        self.lastModified = record["CD_lastModified"] as? Date
        self.iconURL = record["CD_iconURL"] as? String

        #if DEBUG
        print("[FullAppConfigDTO] Parsing record for: \(self.displayName)")
        print("[FullAppConfigDTO]   iconURL from record: \(self.iconURL ?? "nil")")
        // Print all record keys to see what fields are available
        print("[FullAppConfigDTO]   Available keys: \(record.allKeys())")
        #endif

        // Quick-access display fields
        self.dailyLimitSummary = record["CD_dailyLimitSummary"] as? String
        self.timeWindowSummary = record["CD_timeWindowSummary"] as? String

        // Decode full schedule config
        if let scheduleJSON = record["CD_scheduleConfigJSON"] as? String,
           let data = scheduleJSON.data(using: .utf8),
           let config = try? JSONDecoder().decode(AppScheduleConfiguration.self, from: data) {
            self.scheduleConfig = config
        }

        // Decode linked learning apps
        if let linkedJSON = record["CD_linkedAppsJSON"] as? String,
           let data = linkedJSON.data(using: .utf8),
           let apps = try? JSONDecoder().decode([LinkedLearningApp].self, from: data) {
            self.linkedLearningApps = apps
        } else {
            self.linkedLearningApps = []
        }

        // Parse unlock mode
        if let modeStr = record["CD_unlockMode"] as? String,
           let mode = UnlockMode(rawValue: modeStr) {
            self.unlockMode = mode
        } else {
            self.unlockMode = .all
        }

        // Decode streak settings
        if let streakJSON = record["CD_streakSettingsJSON"] as? String,
           let data = streakJSON.data(using: .utf8),
           let settings = try? JSONDecoder().decode(AppStreakSettings.self, from: data) {
            self.streakSettings = settings
        }
    }

    // Hashable conformance
    func hash(into hasher: inout Hasher) {
        hasher.combine(logicalID)
    }

    static func == (lhs: FullAppConfigDTO, rhs: FullAppConfigDTO) -> Bool {
        lhs.logicalID == rhs.logicalID
    }

    /// Create a new FullAppConfigDTO with changes from MutableAppConfigDTO applied
    func applying(changes: MutableAppConfigDTO) -> FullAppConfigDTO {
        let updated = FullAppConfigDTO(
            logicalID: logicalID,
            deviceID: deviceID,
            displayName: displayName,
            category: changes.category,
            pointsPerMinute: changes.pointsPerMinute,
            isEnabled: changes.isEnabled,
            blockingEnabled: changes.blockingEnabled,
            tokenHash: tokenHash,
            lastModified: Date(),
            iconURL: iconURL,
            scheduleConfig: changes.scheduleConfig,
            dailyLimitSummary: changes.scheduleConfig?.dailyLimits.displaySummary,
            timeWindowSummary: changes.scheduleConfig?.allowedTimeWindow.displayString,
            linkedLearningApps: changes.linkedLearningApps,
            unlockMode: changes.unlockMode,
            streakSettings: changes.streakSettings
        )
        return updated
    }

    /// Direct initializer for creating updated copies
    init(
        logicalID: String,
        deviceID: String,
        displayName: String,
        category: String,
        pointsPerMinute: Int,
        isEnabled: Bool,
        blockingEnabled: Bool,
        tokenHash: String?,
        lastModified: Date?,
        iconURL: String?,
        scheduleConfig: AppScheduleConfiguration?,
        dailyLimitSummary: String?,
        timeWindowSummary: String?,
        linkedLearningApps: [LinkedLearningApp],
        unlockMode: UnlockMode,
        streakSettings: AppStreakSettings?
    ) {
        self.logicalID = logicalID
        self.deviceID = deviceID
        self.displayName = displayName
        self.category = category
        self.pointsPerMinute = pointsPerMinute
        self.isEnabled = isEnabled
        self.blockingEnabled = blockingEnabled
        self.tokenHash = tokenHash
        self.lastModified = lastModified
        self.iconURL = iconURL
        self.scheduleConfig = scheduleConfig
        self.dailyLimitSummary = dailyLimitSummary
        self.timeWindowSummary = timeWindowSummary
        self.linkedLearningApps = linkedLearningApps
        self.unlockMode = unlockMode
        self.streakSettings = streakSettings
    }
}

// MARK: - Shield State DTO

/// Data transfer object for shield state from CloudKit
/// Shows whether a reward app is currently blocked or unlocked
struct ShieldStateDTO: Identifiable {
    var id: String { rewardAppLogicalID }

    let rewardAppLogicalID: String
    let deviceID: String
    let isUnlocked: Bool
    let unlockedAt: Date?
    let reason: String
    let syncTimestamp: Date?
    let rewardAppDisplayName: String?

    /// Create from a CloudKit record
    init(from record: CKRecord) {
        self.rewardAppLogicalID = record["CD_rewardAppLogicalID"] as? String ?? ""
        self.deviceID = record["CD_deviceID"] as? String ?? ""
        self.isUnlocked = record["CD_isUnlocked"] as? Bool ?? false
        self.unlockedAt = record["CD_unlockedAt"] as? Date
        self.reason = record["CD_reason"] as? String ?? "unknown"
        self.syncTimestamp = record["CD_syncTimestamp"] as? Date
        self.rewardAppDisplayName = record["CD_rewardAppDisplayName"] as? String
    }

    /// Display string for current status
    var statusDisplay: String {
        if isUnlocked {
            if let unlockedAt = unlockedAt {
                let formatter = DateFormatter()
                formatter.timeStyle = .short
                return "Unlocked at \(formatter.string(from: unlockedAt))"
            }
            return "Unlocked"
        } else {
            return "Blocked"
        }
    }

    /// Short status indicator
    var statusIcon: String {
        isUnlocked ? "lock.open.fill" : "lock.fill"
    }
}

// MARK: - Daily Usage History DTO

/// Data transfer object for daily usage history from CloudKit
/// Contains per-app daily usage summaries for historical display
struct DailyUsageHistoryDTO: Identifiable {
    var id: String { "\(logicalID)-\(date.timeIntervalSince1970)" }

    let deviceID: String
    let logicalID: String
    let displayName: String
    let date: Date
    let seconds: Int
    let category: String
    let syncTimestamp: Date?

    /// Create from a CloudKit record
    init(from record: CKRecord) {
        self.deviceID = record["CD_deviceID"] as? String ?? ""
        self.logicalID = record["CD_logicalID"] as? String ?? ""
        self.displayName = record["CD_displayName"] as? String ?? "Unknown"
        self.date = record["CD_date"] as? Date ?? Date()
        self.seconds = record["CD_seconds"] as? Int ?? 0
        self.category = record["CD_category"] as? String ?? "Unknown"
        self.syncTimestamp = record["CD_syncTimestamp"] as? Date
    }

    /// Formatted time string (e.g., "1h 23m")
    var formattedTime: String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

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

    // Child app configurations (synced from CloudKit) - basic Core Data entities
    @Published var childLearningApps: [AppConfiguration] = []
    @Published var childRewardApps: [AppConfiguration] = []

    // Full app configurations with schedule/goals/streaks (decoded from CloudKit JSON)
    @Published var childLearningAppsFullConfig: [FullAppConfigDTO] = []
    @Published var childRewardAppsFullConfig: [FullAppConfigDTO] = []

    // Shield states for reward apps (blocked/unlocked status)
    @Published var childShieldStates: [String: ShieldStateDTO] = [:]

    // Daily usage history (synced from CloudKit)
    @Published var childDailyUsageHistory: [DailyUsageHistoryDTO] = []
    @Published var childDailyUsageByApp: [String: [DailyUsageHistoryDTO]] = [:]  // Grouped by logicalID

    /// Aggregated daily totals from per-app history
    /// Returns array of (date, learningSeconds, rewardSeconds) sorted by date descending
    var aggregatedDailyTotals: [(date: Date, learningSeconds: Int, rewardSeconds: Int)] {
        var totals: [Date: (learning: Int, reward: Int)] = [:]
        let calendar = Calendar.current

        for record in childDailyUsageHistory {
            let dayStart = calendar.startOfDay(for: record.date)
            var current = totals[dayStart] ?? (learning: 0, reward: 0)
            if record.category == "Learning" {
                current.learning += record.seconds
            } else if record.category == "Reward" {
                current.reward += record.seconds
            }
            totals[dayStart] = current
        }

        return totals.map { (date: $0.key, learningSeconds: $0.value.learning, rewardSeconds: $0.value.reward) }
            .sorted { $0.date > $1.date }
    }

    private let cloudKitService = CloudKitSyncService.shared
    private let offlineQueue = OfflineQueueManager.shared
    private var cancellables = Set<AnyCancellable>()

    // Track apps with pending parent edits to prevent CloudKit auto-refresh from overwriting them
    // Maps logicalID → timestamp when edit was made
    private var pendingConfigUpdates: [String: Date] = [:]
    private let pendingUpdateTimeout: TimeInterval = 60  // Protect edits for 60 seconds

    init() {
        setupCloudKitNotifications()
        Task {
            await loadLinkedChildDevices()
        }
    }

    deinit {
        cancellables.removeAll()
    }

    // MARK: - Optimistic Update for Parent Edit

    /// Update a config in the local arrays after successful parent edit
    /// This provides immediate UI feedback while waiting for CloudKit sync
    func updateAppConfig(_ config: FullAppConfigDTO) {
        // Mark as pending to protect from CloudKit auto-refresh overwriting
        pendingConfigUpdates[config.logicalID] = Date()

        #if DEBUG
        print("[ParentRemoteViewModel] Marked \(config.displayName) as pending (protected from CloudKit overwrite)")
        #endif

        if config.category == "Learning" {
            if let index = childLearningAppsFullConfig.firstIndex(where: { $0.logicalID == config.logicalID }) {
                childLearningAppsFullConfig[index] = config
                #if DEBUG
                print("[ParentRemoteViewModel] Updated learning app config: \(config.displayName)")
                #endif
            }
        } else {
            if let index = childRewardAppsFullConfig.firstIndex(where: { $0.logicalID == config.logicalID }) {
                childRewardAppsFullConfig[index] = config
                #if DEBUG
                print("[ParentRemoteViewModel] Updated reward app config: \(config.displayName)")
                print("[ParentRemoteViewModel] Linked apps count: \(config.linkedLearningApps.count)")
                #endif
            }
        }
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

            // Validate that each child's zone still exists
            await validateChildPairings()

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

    /// Validate that each child's zone still exists
    /// Marks children as stale if their zone no longer exists
    private func validateChildPairings() async {
        #if DEBUG
        print("[ParentRemoteViewModel] ===== Validating Child Pairings =====")
        #endif

        for device in linkedChildDevices {
            guard let zoneName = device.sharedZoneID,
                  let zoneOwner = device.sharedZoneOwner else {
                #if DEBUG
                print("[ParentRemoteViewModel] ⚠️ Child \(device.deviceName ?? "unknown") has no zone info")
                #endif
                device.isStale = true
                continue
            }

            let zoneExists = await cloudKitService.validateChildZone(zoneName: zoneName, ownerName: zoneOwner)

            if !zoneExists {
                #if DEBUG
                print("[ParentRemoteViewModel] ❌ Zone \(zoneName) no longer exists for \(device.deviceName ?? "unknown")")
                #endif
                device.isStale = true
            } else {
                #if DEBUG
                print("[ParentRemoteViewModel] ✅ Zone \(zoneName) exists for \(device.deviceName ?? "unknown")")
                #endif
                device.isStale = false
            }
        }

        #if DEBUG
        let staleCount = linkedChildDevices.filter { $0.isStale }.count
        print("[ParentRemoteViewModel] Validation complete: \(staleCount) stale, \(linkedChildDevices.count - staleCount) valid")
        #endif
    }

    /// Unpair (remove) a child device from this parent
    /// Deletes the CloudKit zone and all associated data
    func unpairChildDevice(_ device: RegisteredDevice) async -> Bool {
        guard let deviceID = device.deviceID else {
            errorMessage = "Cannot unpair: Device ID is missing"
            return false
        }

        #if DEBUG
        print("[ParentRemoteViewModel] ===== Unpairing Child Device =====")
        print("[ParentRemoteViewModel] Device: \(device.deviceName ?? deviceID)")
        #endif

        isLoading = true
        errorMessage = nil

        do {
            // Delete the CloudKit zone and all records
            try await cloudKitService.unpairChildDevice(device)

            // Remove from local list
            linkedChildDevices.removeAll { $0.deviceID == deviceID }

            // If this was the selected device, clear selection
            if selectedChildDevice?.deviceID == deviceID {
                selectedChildDevice = linkedChildDevices.first
                if let newSelected = selectedChildDevice {
                    await loadChildData(for: newSelected)
                } else {
                    // No more children - clear all data
                    usageRecords = []
                    appConfigurations = []
                    childLearningApps = []
                    childRewardApps = []
                    childLearningAppsFullConfig = []
                    childRewardAppsFullConfig = []
                }
            }

            #if DEBUG
            print("[ParentRemoteViewModel] ✅ Child device unpaired successfully")
            #endif

            isLoading = false
            return true

        } catch {
            #if DEBUG
            print("[ParentRemoteViewModel] ❌ Failed to unpair child: \(error)")
            #endif
            errorMessage = "Failed to remove child device: \(error.localizedDescription)"
            isLoading = false
            return false
        }
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
            // Pass zone info for zone-specific query (avoids querying stale/orphaned zones)
            usageRecords = try await cloudKitService.fetchChildUsageDataFromCloudKit(
                deviceID: device.deviceID ?? "",
                dateRange: dateRange,
                zoneID: device.sharedZoneID,
                zoneOwner: device.sharedZoneOwner
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

            // Also load child app configurations from CloudKit
            await loadChildAppConfigurations(for: device)
        } catch let error as CKError {
            handleCloudKitError(error)
        } catch {
            errorMessage = "Failed to load child data: \(error.localizedDescription)"
            print("[ParentRemoteViewModel] Error loading child data: \(error)")
        }

        isLoading = false
    }

    /// Load child's app configurations from CloudKit (all configured apps, even with 0 usage)
    /// Fetches both basic AppConfiguration entities and full DTOs with schedule/goals/streaks
    func loadChildAppConfigurations(for device: RegisteredDevice) async {
        guard let deviceID = device.deviceID else { return }

        #if DEBUG
        print("[ParentRemoteViewModel] ===== Loading Child App Configurations =====")
        print("[ParentRemoteViewModel] Device ID: \(deviceID)")
        if let zoneID = device.sharedZoneID {
            print("[ParentRemoteViewModel] Zone-specific fetch: \(zoneID)")
        }
        #endif

        do {
            // Fetch basic configurations (for backward compatibility)
            // Pass zone info for zone-specific query (avoids querying stale/orphaned zones)
            let configs = try await cloudKitService.fetchChildAppConfigurations(
                deviceID: deviceID,
                zoneID: device.sharedZoneID,
                zoneOwner: device.sharedZoneOwner
            )

            #if DEBUG
            print("[ParentRemoteViewModel] Fetched \(configs.count) app configurations from CloudKit")
            #endif

            // Filter into learning and reward categories
            let learning = configs.filter { $0.category == "Learning" && $0.isEnabled }
            let reward = configs.filter { $0.category == "Reward" && $0.isEnabled }

            // Also fetch full DTOs with schedule/goals/streaks
            // Use zone-specific query if zone info available (optimization)
            let fullConfigs = try await cloudKitService.fetchChildAppConfigurationsFullDTO(
                deviceID: deviceID,
                zoneID: device.sharedZoneID,
                zoneOwner: device.sharedZoneOwner
            )

            #if DEBUG
            print("[ParentRemoteViewModel] Fetched \(fullConfigs.count) full app configurations (DTOs)")
            for dto in fullConfigs {
                print("[ParentRemoteViewModel]   App: \(dto.displayName) | Category: \(dto.category)")
                print("[ParentRemoteViewModel]       iconURL: \(dto.iconURL ?? "nil")")
                if let schedule = dto.scheduleConfig {
                    print("[ParentRemoteViewModel]       Daily Limit: \(schedule.dailyLimits.displaySummary)")
                    print("[ParentRemoteViewModel]       Time Window: \(schedule.todayTimeWindow.displayString)")
                }
                if !dto.linkedLearningApps.isEmpty {
                    print("[ParentRemoteViewModel]       Linked Apps: \(dto.linkedLearningApps.count) (\(dto.unlockMode.displayName))")
                }
            }
            #endif

            // Filter full DTOs into learning and reward categories
            let learningFull = fullConfigs.filter { $0.category == "Learning" && $0.isEnabled }
            let rewardFull = fullConfigs.filter { $0.category == "Reward" && $0.isEnabled }

            // Fetch shield states for reward apps
            // Pass zone info for zone-specific query (avoids querying stale/orphaned zones)
            let shieldStates = try await cloudKitService.fetchChildShieldStates(
                deviceID: deviceID,
                zoneID: device.sharedZoneID,
                zoneOwner: device.sharedZoneOwner
            )

            #if DEBUG
            print("[ParentRemoteViewModel] Fetched \(shieldStates.count) shield states")
            for (logicalID, state) in shieldStates {
                print("[ParentRemoteViewModel]   \(state.rewardAppDisplayName ?? logicalID): \(state.isUnlocked ? "UNLOCKED" : "BLOCKED")")
            }
            #endif

            // Fetch daily usage history (last 30 days)
            // Pass zone info for zone-specific query (avoids querying stale/orphaned zones)
            let usageHistory = try await cloudKitService.fetchChildDailyUsageHistory(
                deviceID: deviceID,
                daysToFetch: 30,
                zoneID: device.sharedZoneID,
                zoneOwner: device.sharedZoneOwner
            )

            #if DEBUG
            print("[ParentRemoteViewModel] Fetched \(usageHistory.count) daily usage history records")
            #endif

            // Group history by app logicalID
            let historyByApp = Dictionary(grouping: usageHistory) { $0.logicalID }

            await MainActor.run {
                // Basic AppConfiguration entities
                self.childLearningApps = learning
                self.childRewardApps = reward

                // Clean up expired pending updates
                let now = Date()
                self.pendingConfigUpdates = self.pendingConfigUpdates.filter {
                    now.timeIntervalSince($0.value) < self.pendingUpdateTimeout
                }

                // Get IDs of apps with pending edits (protected from overwrite)
                let pendingIDs = Set(self.pendingConfigUpdates.keys)

                #if DEBUG
                if !pendingIDs.isEmpty {
                    print("[ParentRemoteViewModel] Protecting \(pendingIDs.count) pending edit(s) from CloudKit overwrite")
                }
                #endif

                // Check if CloudKit data matches our pending edits (auto-clear if caught up)
                for cloudConfig in rewardFull {
                    if self.pendingConfigUpdates[cloudConfig.logicalID] != nil,
                       let localConfig = self.childRewardAppsFullConfig.first(where: { $0.logicalID == cloudConfig.logicalID }) {
                        // Compare linked apps count to see if CloudKit caught up
                        if cloudConfig.linkedLearningApps.count == localConfig.linkedLearningApps.count {
                            self.pendingConfigUpdates.removeValue(forKey: cloudConfig.logicalID)
                            #if DEBUG
                            print("[ParentRemoteViewModel] CloudKit caught up for \(cloudConfig.displayName), clearing pending status")
                            #endif
                        }
                    }
                }
                for cloudConfig in learningFull {
                    if self.pendingConfigUpdates[cloudConfig.logicalID] != nil,
                       let localConfig = self.childLearningAppsFullConfig.first(where: { $0.logicalID == cloudConfig.logicalID }) {
                        // Compare key fields to see if CloudKit caught up
                        if cloudConfig.pointsPerMinute == localConfig.pointsPerMinute &&
                           cloudConfig.isEnabled == localConfig.isEnabled {
                            self.pendingConfigUpdates.removeValue(forKey: cloudConfig.logicalID)
                            #if DEBUG
                            print("[ParentRemoteViewModel] CloudKit caught up for \(cloudConfig.displayName), clearing pending status")
                            #endif
                        }
                    }
                }

                // Refresh pending IDs after auto-clear
                let refreshedPendingIDs = Set(self.pendingConfigUpdates.keys)

                // Filter out pending apps from CloudKit results (don't overwrite them)
                let safeLearningFull = learningFull.filter { !refreshedPendingIDs.contains($0.logicalID) }
                let safeRewardFull = rewardFull.filter { !refreshedPendingIDs.contains($0.logicalID) }

                // Preserve pending optimistic updates
                let pendingLearning = self.childLearningAppsFullConfig.filter { refreshedPendingIDs.contains($0.logicalID) }
                let pendingReward = self.childRewardAppsFullConfig.filter { refreshedPendingIDs.contains($0.logicalID) }

                // Merge: CloudKit data for non-pending apps + preserved pending edits
                self.childLearningAppsFullConfig = safeLearningFull + pendingLearning
                self.childRewardAppsFullConfig = safeRewardFull + pendingReward

                // Shield states for reward apps (always refresh - not affected by pending edits)
                self.childShieldStates = shieldStates

                // Daily usage history (always refresh - not affected by pending edits)
                self.childDailyUsageHistory = usageHistory
                self.childDailyUsageByApp = historyByApp
            }

            #if DEBUG
            print("[ParentRemoteViewModel] Categorized: \(learning.count) learning apps, \(reward.count) reward apps")
            print("[ParentRemoteViewModel] Full configs: \(learningFull.count) learning, \(rewardFull.count) reward")
            print("[ParentRemoteViewModel] Shield states: \(shieldStates.count)")
            print("[ParentRemoteViewModel] Daily usage history: \(usageHistory.count) records for \(historyByApp.count) apps")
            print("[ParentRemoteViewModel] ===== End Loading Child App Configurations =====")
            #endif
        } catch {
            print("[ParentRemoteViewModel] Error loading child app configurations: \(error)")
        }
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

    /// Send a configuration update from MutableAppConfigDTO (used by DTO-based views)
    func sendConfigurationUpdate(_ mutableConfig: MutableAppConfigDTO) async {
        guard let selectedDevice = selectedChildDevice else { return }

        do {
            try await cloudKitService.sendConfigurationToChild(
                deviceID: selectedDevice.deviceID ?? "",
                mutableConfig: mutableConfig
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