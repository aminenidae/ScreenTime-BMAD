import Foundation
import Combine
import FamilyControls
import ManagedSettings

// Snapshot structs for deterministic ordering
// TASK L: Update snapshot structs to use token hash as ID for stability
struct LearningAppSnapshot: Identifiable {
    let token: ManagedSettings.ApplicationToken
    let logicalID: String
    let displayName: String
    let pointsPerMinute: Int
    let totalSeconds: TimeInterval
    // TASK L: Use token hash as stable ID instead of logicalID to prevent re-identification
    var id: String { tokenHash }
    let tokenHash: String
}

struct RewardAppSnapshot: Identifiable {
    let token: ManagedSettings.ApplicationToken
    let logicalID: String
    let displayName: String
    let pointsPerMinute: Int
    let totalSeconds: TimeInterval
    // TASK L: Use token hash as stable ID instead of logicalID to prevent re-identification
    var id: String { tokenHash }
    let tokenHash: String
}

/// View model to manage app usage data for the UI
class AppUsageViewModel: ObservableObject {
    @Published var appUsages: [AppUsage] = []
    @Published var isMonitoring = false
    @Published var learningTime: TimeInterval = 0
    @Published var rewardTime: TimeInterval = 0
    @Published var totalRewardPoints: Int = 0
    @Published var learningRewardPoints: Int = 0
    @Published var rewardRewardPoints: Int = 0
    @Published var errorMessage: String?
    @Published var familySelection: FamilyActivitySelection = .init()
    @Published var thresholdMinutes: [AppUsage.AppCategory: Int] = [:]
    @Published var isFamilyPickerPresented = false
    @Published var isAuthorizationGranted = false
    @Published var isCategoryAssignmentPresented = false
    @Published var categoryAssignments: [ApplicationToken: AppUsage.AppCategory] = [:]
    @Published var rewardPoints: [ApplicationToken: Int] = [:]

    // TASK 12 REVISED: Add sorted applications snapshot property
    @Published private(set) var sortedApplications: [Application] = []

    // Picker error handling
    @Published var pickerError: String?
    @Published var pickerLoadingTimeout = false
    @Published var pickerRetryCount = 0

    // Snapshot properties for deterministic ordering
    @Published private(set) var learningSnapshots: [LearningAppSnapshot] = []
    @Published private(set) var rewardSnapshots: [RewardAppSnapshot] = []

    private let service: ScreenTimeService
    private var masterSelection: FamilyActivitySelection
    private var activePickerContext: PickerContext?
    private var cancellables = Set<AnyCancellable>()
    private let defaultThresholdMinutes = 1
    private let appGroupIdentifier = "group.com.screentimerewards.shared"
    private var pickerTimeoutWorkItem: DispatchWorkItem?
    private let pickerTimeoutSeconds: TimeInterval = 15.0

    // MARK: - Computed Properties for Tab Views

    /// All application tokens assigned to Learning category
    var learningApps: [ApplicationToken] {
        categoryAssignments.filter { $0.value == .learning }.map { $0.key }
    }

    /// All application tokens assigned to Reward category
    var rewardApps: [ApplicationToken] {
        categoryAssignments.filter { $0.value == .reward }.map { $0.key }
    }
    
    // TASK 12: Add sorted category properties
    /// Learning application tokens in stable sorted order
    var sortedLearningApps: [ApplicationToken] {
        sortedApplications
            .compactMap { app -> ApplicationToken? in
                guard let token = app.token,
                      categoryAssignments[token] == .learning else { return nil }
                return token
            }
    }

    /// Reward application tokens in stable sorted order
    var sortedRewardApps: [ApplicationToken] {
        sortedApplications
            .compactMap { app -> ApplicationToken? in
                guard let token = app.token,
                      categoryAssignments[token] == .reward else { return nil }
                return token
            }
    }
    
    func presentLearningPicker() {
        activePickerContext = .learning
        familySelection = selection(for: .learning)
        requestAuthorizationAndOpenPicker()
    }

    func presentRewardPicker() {
        activePickerContext = .reward
        familySelection = selection(for: .reward)
        requestAuthorizationAndOpenPicker()
    }
    
    enum PickerContext {
        case learning
        case reward
    }

    init(service: ScreenTimeService = .shared) {
        self.service = service

        // Load from shared service
        self.familySelection = service.familySelection
        self.masterSelection = service.familySelection

        #if DEBUG
        print("[AppUsageViewModel] Initializing...")
        print("[AppUsageViewModel] Family selection has \(familySelection.applications.count) applications")
        #endif

        // Load assignments from service (already restored from persistence in service init)
        self.categoryAssignments = service.categoryAssignments
        self.rewardPoints = service.rewardPointsAssignments

        #if DEBUG
        print("[AppUsageViewModel] ✅ Initialization complete:")
        print("[AppUsageViewModel]   Category assignments: \(categoryAssignments.count)")
        print("[AppUsageViewModel]   Reward points: \(rewardPoints.count)")
        print("[AppUsageViewModel]   Selected apps: \(familySelection.applications.count)")
        #endif

        // TASK 12 REVISED: Update sorted applications snapshot after initialization
        updateSortedApplications()

        loadData()
        NotificationCenter.default
            .publisher(for: ScreenTimeService.usageDidChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.usageDidChange()
            }
            .store(in: &cancellables)
    }

    /// Load category assignments from App Group storage
    private func loadCategoryAssignments() {
        guard let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            #if DEBUG
            print("[AppUsageViewModel] Failed to access App Group for loading assignments")
            #endif
            return
        }

        if let data = sharedDefaults.data(forKey: "categoryAssignments"),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            // Convert String keys back to ApplicationToken
            categoryAssignments = decoded.compactMapValues { categoryString in
                AppUsage.AppCategory(rawValue: categoryString)
            }.reduce(into: [:]) { result, entry in
                // Note: We can't directly deserialize ApplicationToken, so we store by token data hash
                // This is a limitation - we'll need to reassign if selection changes
                // Fixed the issue: entry.value is already AppUsage.AppCategory, not Optional
                // Just access the value directly (we're not using it but need to avoid unused variable warning)
                _ = entry.value
                // For now, just track the category mapping logic
                // Real implementation would need token persistence strategy
            }

            #if DEBUG
            print("[AppUsageViewModel] Loaded \(categoryAssignments.count) category assignments")
            #endif
        }
    }
    
    /// Load reward points from App Group storage
    private func loadRewardPoints() {
        guard let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            #if DEBUG
            print("[AppUsageViewModel] Failed to access App Group for loading reward points")
            #endif
            return
        }

        if let data = sharedDefaults.data(forKey: "rewardPoints"),
           let decoded = try? JSONDecoder().decode([String: Int].self, from: data) {
            // We store reward points by token hash, but we can't reconstruct the actual tokens
            // For now, we'll just keep the data as is and use it when we have the actual tokens
            #if DEBUG
            print("[AppUsageViewModel] Loaded \(decoded.count) reward point assignments")
            #endif
        }
    }

    /// Save category assignments using service's persistent storage
    /// NOTE: Persistence now happens automatically in configureMonitoring()
    func saveCategoryAssignments() {
        #if DEBUG
        print("[AppUsageViewModel] Category assignments will be saved during configureMonitoring()")
        #endif
    }

    /// Save reward points using service's persistent storage
    /// NOTE: Persistence now happens automatically in configureMonitoring()
    func saveRewardPoints() {
        #if DEBUG
        print("[AppUsageViewModel] Reward points will be saved during configureMonitoring()")
        #endif
    }

    // TASK 12 REVISED: Create updateSortedApplications method
    private func updateSortedApplications() {
        // Use the master selection (union of all apps) for deterministic ordering
        self.sortedApplications = masterSelection.sortedApplications(using: service.usagePersistence)
        
        #if DEBUG
        print("[AppUsageViewModel] 🔄 Updated sorted applications snapshot: \(sortedApplications.count) apps")
        #endif
        
        // Update snapshots whenever sorted applications change
        updateSnapshots()
    }
    
    /// Build snapshot arrays from sorted applications
    private func updateSnapshots() {
        var newLearningSnapshots: [LearningAppSnapshot] = []
        var newRewardSnapshots: [RewardAppSnapshot] = []
        
        // Use a set to track token hashes we've already processed to avoid duplicates
        var processedTokenHashes: Set<String> = []
        
        // Single pass over sorted applications
        for application in sortedApplications {
            guard let token = application.token else { continue }
            
            // Resolve stable identifiers via usagePersistence
            let tokenHash = service.usagePersistence.tokenHash(for: token)
            let logicalID = service.usagePersistence.logicalID(for: tokenHash) ?? tokenHash

            // Skip if we've already processed this token hash
            if processedTokenHashes.contains(tokenHash) {
                #if DEBUG
                print("[AppUsageViewModel] Skipping duplicate token hash: \(tokenHash)")
                #endif
                continue
            }

            // Mark this token hash as processed
            processedTokenHashes.insert(tokenHash)
            
            // Get display name
            let displayName = application.localizedDisplayName ?? "Unknown App"
            
            // Determine category
            let category = categoryAssignments[token] ?? .learning
            
            // Pull usage from appUsages[logicalID] (default to zero)
            let appUsage = service.getUsage(for: token)
            let totalSeconds = appUsage?.totalTime ?? 0
            
            // Look up assigned points
            let pointsPerMinute = rewardPoints[token] ?? getDefaultRewardPoints(for: category)
            
            // Create appropriate snapshot based on category
            // TASK L: Include tokenHash in snapshot creation
            switch category {
            case .learning:
                let snapshot = LearningAppSnapshot(
                    token: token,
                    logicalID: logicalID,
                    displayName: displayName,
                    pointsPerMinute: pointsPerMinute,
                    totalSeconds: totalSeconds,
                    tokenHash: tokenHash
                )
                newLearningSnapshots.append(snapshot)
            case .reward:
                let snapshot = RewardAppSnapshot(
                    token: token,
                    logicalID: logicalID,
                    displayName: displayName,
                    pointsPerMinute: pointsPerMinute,
                    totalSeconds: totalSeconds,
                    tokenHash: tokenHash
                )
                newRewardSnapshots.append(snapshot)
            }
        }
        
        // Update published properties
        self.learningSnapshots = newLearningSnapshots
        self.rewardSnapshots = newRewardSnapshots
        
        #if DEBUG
        print("[AppUsageViewModel] 🔄 Updated snapshots - Learning: \(newLearningSnapshots.count), Reward: \(newRewardSnapshots.count)")
        // TASK L: Add targeted diagnostics to verify ordering stability
        let learningLogicalIDs = newLearningSnapshots.map(\.logicalID)
        let rewardLogicalIDs = newRewardSnapshots.map(\.logicalID)
        let learningTokenHashes = newLearningSnapshots.map(\.tokenHash)
        let rewardTokenHashes = newRewardSnapshots.map(\.tokenHash)
        print("[AppUsageViewModel] 📋 Learning snapshot logical IDs: \(learningLogicalIDs)")
        print("[AppUsageViewModel] 📋 Learning snapshot token hashes: \(learningTokenHashes)")
        print("[AppUsageViewModel] 📋 Reward snapshot logical IDs: \(rewardLogicalIDs)")
        print("[AppUsageViewModel] 📋 Reward snapshot token hashes: \(rewardTokenHashes)")
        #endif
    }
    
    private func getDefaultRewardPoints(for category: AppUsage.AppCategory) -> Int {
        switch category {
        case .learning:
            return 20
        case .reward:
            return 10
        }
    }
    
    private func mergeCurrentSelectionIntoMaster() {
        guard let context = activePickerContext else {
            masterSelection = familySelection
            // TASK L: Ensure sorted applications are updated after master selection change
            updateSortedApplications()
            return
        }

        var merged = masterSelection
        let currentTokens = familySelection.applicationTokens

        let retainedTokens = merged.applicationTokens.filter { token in
            let category = categoryAssignments[token] ?? .learning
            switch context {
            case .learning:
                return category == .reward
            case .reward:
                return category == .learning
            }
        }

        var combinedTokens = Set(retainedTokens)
        combinedTokens.formUnion(currentTokens)
        merged.applicationTokens = combinedTokens

        // Preserve category/web domain selections as-is for now
        merged.categoryTokens = masterSelection.categoryTokens
        merged.webDomainTokens = masterSelection.webDomainTokens

        masterSelection = merged
        familySelection = merged
        activePickerContext = nil
        
        // TASK L: Ensure sorted applications are updated after master selection change
        updateSortedApplications()
    }
    
    private func selection(for category: AppUsage.AppCategory) -> FamilyActivitySelection {
        var result = FamilyActivitySelection()
        let filteredTokens = masterSelection.applicationTokens.filter { token in
            categoryAssignments[token] == category
        }
        result.applicationTokens = Set(filteredTokens)
        return result
    }
    
    /// Handle category assignment completion
    func onCategoryAssignmentSave() {
        #if DEBUG
        print("[AppUsageViewModel] Category assignments saved")
        for (token, category) in categoryAssignments {
            print("[AppUsageViewModel]   Token \(token.hashValue) → \(category.rawValue)")
        }
        print("[AppUsageViewModel] Reward points saved")
        for (token, points) in rewardPoints {
            print("[AppUsageViewModel]   Token \(token.hashValue) → \(points) points")
        }
        #endif

        // INSTRUMENTATION: Log view-model snapshots before calling configureMonitoring
        #if DEBUG
        print("[AppUsageViewModel] === VIEW MODEL SNAPSHOT BEFORE configureMonitoring ===")
        logViewModelSnapshots()
        print("[AppUsageViewModel] === END VIEW MODEL SNAPSHOT BEFORE configureMonitoring ===")
        #endif
        // END INSTRUMENTATION

        // TASK L: Fix ViewModel sequencing - update sorted applications BEFORE merging
        updateSortedApplications()
        
        // CRITICAL: Merge current picker context back into master selection before persisting
        mergeCurrentSelectionIntoMaster()

        // Persist FamilyActivitySelection so tokens can be restored
        service.persistFamilySelection(familySelection)

        // Then persist assignments and points
        saveCategoryAssignments()
        saveRewardPoints()
        
        // TASK L: Update sorted applications snapshot BEFORE calling configureMonitoring
        // This ensures the snapshots use the correct ordering when building monitored events
        updateSortedApplications()
        
        configureMonitoring()
        masterSelection = familySelection
        
        // INSTRUMENTATION: Log view-model snapshots after service call completes
        #if DEBUG
        print("[AppUsageViewModel] === VIEW MODEL SNAPSHOT AFTER configureMonitoring ===")
        logViewModelSnapshots()
        print("[AppUsageViewModel] === END VIEW MODEL SNAPSHOT AFTER configureMonitoring ===")
        #endif
        // END INSTRUMENTATION
        
        // TASK L: Trigger UI refresh after save & monitor to eliminate need for restart
        // This re-sorts apps and refreshes UI immediately without requiring app restart
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // Refresh the ViewModel data to update the UI
            self.refreshData()
        }
    }

    func cancelCategoryAssignment() {
        familySelection = masterSelection
        activePickerContext = nil
        updateSortedApplications()
    }

    /// INSTRUMENTATION: Add helper method to log view-model snapshots
    #if DEBUG
    private func logViewModelSnapshots() {
        print("[AppUsageViewModel] Learning Apps Snapshot:")
        for (index, token) in sortedLearningApps.enumerated() {
            let tokenHash = String(token.hashValue).prefix(20)
            // We need to get the logical ID from the service
            let logicalID = getLogicalID(for: token) ?? "unknown"
            let usageSeconds = service.getUsageDuration(for: token)
            let pointsPerMin = rewardPoints[token] ?? 0
            let displayName = getDisplayName(for: token) ?? "Unknown App"
            print("[AppUsageViewModel]   \(index): tokenHash=\(tokenHash)..., logicalID=\(logicalID), displayName=\(displayName), usageSeconds=\(usageSeconds), pointsPerMin=\(pointsPerMin)")
        }
        
        print("[AppUsageViewModel] Reward Apps Snapshot:")
        for (index, token) in sortedRewardApps.enumerated() {
            let tokenHash = String(token.hashValue).prefix(20)
            // We need to get the logical ID from the service
            let logicalID = getLogicalID(for: token) ?? "unknown"
            let usageSeconds = service.getUsageDuration(for: token)
            let pointsPerMin = rewardPoints[token] ?? 0
            let displayName = getDisplayName(for: token) ?? "Unknown App"
            print("[AppUsageViewModel]   \(index): tokenHash=\(tokenHash)..., logicalID=\(logicalID), displayName=\(displayName), usageSeconds=\(usageSeconds), pointsPerMin=\(pointsPerMin)")
        }
    }
    
    private func getLogicalID(for token: ApplicationToken) -> String? {
        // We need to access the service's usagePersistence to get the logical ID
        return service.getLogicalID(for: token)
    }
    
    private func getDisplayName(for token: ApplicationToken) -> String? {
        // Use the service to get the display name
        return service.getDisplayName(for: token)
    }
    #endif
    /// END INSTRUMENTATION

    func thresholdValue(for category: AppUsage.AppCategory) -> Int {
        thresholdMinutes[category] ?? defaultThresholdMinutes
    }
    
    /// Load initial data from the service
    func loadData() {
        // Removed placeholder data - app now works with real apps only
        // service.bootstrapSampleDataIfNeeded()
        refreshData()
    }
    
    /// Start monitoring app usage, updating state based on the result
    func startMonitoring() {
        guard !isMonitoring else { 
            #if DEBUG
            print("[AppUsageViewModel] Monitoring already active, skipping start")
            #endif
            return 
        }
    
        #if DEBUG
        print("[AppUsageViewModel] Starting monitoring")
        #endif
    
        errorMessage = nil
        service.startMonitoring { [weak self] result in
            guard let self else { return }
            DispatchQueue.main.async {
                switch result {
                case .success:
                    #if DEBUG
                    print("[AppUsageViewModel] Monitoring started successfully")
                    print("[AppUsageViewModel] isMonitoring set to true")
                    #endif
                    self.isMonitoring = true
                    self.refreshData()
                case .failure(let error):
                    #if DEBUG
                    print("[AppUsageViewModel] Failed to start monitoring: \(error)")
                    print("[AppUsageViewModel] Error description: \(error.errorDescription ?? "No description")")
                    #endif
                    self.isMonitoring = false
                    self.errorMessage = error.errorDescription ?? "An unknown monitoring error occurred."
                }
            }
        }
    }
    
    /// Stop monitoring app usage
    func stopMonitoring() {
        service.stopMonitoring()
        isMonitoring = false
    }
    
    /// Refresh data from the service
    func refreshData() {
        #if DEBUG
        print("[AppUsageViewModel] Refreshing data")
        #endif
        appUsages = service.getAppUsages().sorted { $0.totalTime > $1.totalTime }
        #if DEBUG
        print("[AppUsageViewModel] Retrieved \(appUsages.count) app usages")
        for usage in appUsages {
            print("[AppUsageViewModel] App: \(usage.appName), Time: \(usage.totalTime) seconds, Points: \(usage.earnedRewardPoints)")
        }
        #endif
        updateCategoryTotals()
        updateTotalRewardPoints()
        updateCategoryRewardPoints()
        // Refresh sorted applications and snapshots after pulling new data
        updateSortedApplications()
    }
    
    /// Called when usage data changes
    private func usageDidChange() {
        // Refresh data and rebuild snapshots
        refreshData()
    }

    /// Support async refresh triggers (e.g., pull-to-refresh)
    @MainActor
    func refresh() async {
        refreshData()
    }
    
    /// Update category totals using the locally cached data
    private func updateCategoryTotals() {
        let previousLearningTime = learningTime
        let previousRewardTime = rewardTime
    
        learningTime = appUsages
            .filter { $0.category == .learning }
            .reduce(0) { $0 + $1.totalTime }
        rewardTime = appUsages
            .filter { $0.category == .reward }
            .reduce(0) { $0 + $1.totalTime }
        
        #if DEBUG
        if previousLearningTime != learningTime || previousRewardTime != rewardTime {
            print("[AppUsageViewModel] Updated category totals - Learning: \(learningTime), Reward: \(rewardTime)")
        }
        #endif
    }
    
    /// Update total reward points
    private func updateTotalRewardPoints() {
        let previousTotalPoints = totalRewardPoints
        totalRewardPoints = appUsages.reduce(0) { $0 + $1.earnedRewardPoints }
        
        #if DEBUG
        if previousTotalPoints != totalRewardPoints {
            print("[AppUsageViewModel] Updated total reward points: \(totalRewardPoints)")
        }
        #endif
    }
    
    /// Update category-based reward points
    private func updateCategoryRewardPoints() {
        let previousLearningPoints = learningRewardPoints
        let previousRewardPoints = rewardRewardPoints
        
        learningRewardPoints = appUsages
            .filter { $0.category == .learning }
            .reduce(0) { $0 + $1.earnedRewardPoints }
        rewardRewardPoints = appUsages
            .filter { $0.category == .reward }
            .reduce(0) { $0 + $1.earnedRewardPoints }
        
        #if DEBUG
        if previousLearningPoints != learningRewardPoints || previousRewardPoints != rewardRewardPoints {
            print("[AppUsageViewModel] Updated category reward points - Learning: \(learningRewardPoints), Reward: \(rewardRewardPoints)")
        }
        #endif
    }
    
    /// Reset all data
    func resetData() {
        service.resetData()
        appUsages = []
        learningTime = 0
        rewardTime = 0
        totalRewardPoints = 0
        learningRewardPoints = 0
        rewardRewardPoints = 0
        isMonitoring = false
        errorMessage = nil
        // Reset the family selection to allow re-picking
        familySelection = .init()
        masterSelection = .init()
        // TASK 12 REVISED: Update sorted applications snapshot after reset
        updateSortedApplications()
    }

    /// Request authorization BEFORE opening FamilyActivityPicker
    func requestAuthorizationAndOpenPicker() {
        #if DEBUG
        print("[AppUsageViewModel] Requesting FamilyControls authorization before opening picker")

        // Check current authorization status
        let currentStatus = AuthorizationCenter.shared.authorizationStatus
        print("[AppUsageViewModel] Current authorization status: \(currentStatus.rawValue)")
        print("[AppUsageViewModel]   0 = notDetermined, 1 = denied, 2 = approved")
        #endif

        // Reset error states
        errorMessage = nil
        pickerError = nil
        pickerLoadingTimeout = false
        cancelPickerTimeout()

        service.requestPermission { [weak self] result in
            guard let self = self else { return }
            DispatchQueue.main.async {
                switch result {
                case .success:
                    #if DEBUG
                    // Verify authorization status after success
                    let finalStatus = AuthorizationCenter.shared.authorizationStatus
                    print("[AppUsageViewModel] ✅ Authorization request completed")
                    print("[AppUsageViewModel] Final authorization status: \(finalStatus.rawValue)")

                    if finalStatus != .approved {
                        print("[AppUsageViewModel] ⚠️ WARNING: Authorization returned success but status is NOT .approved!")
                        print("[AppUsageViewModel] This may cause FamilyActivityPicker to return incomplete data")
                    }
                    #endif

                    self.isAuthorizationGranted = true

                    // Add small delay to ensure authorization propagates
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.isFamilyPickerPresented = true
                        self.startPickerTimeout()
                    }
                case .failure(let error):
                    #if DEBUG
                    print("[AppUsageViewModel] ❌ Authorization failed: \(error)")
                    #endif
                    self.isAuthorizationGranted = false
                    self.errorMessage = "Authorization required: \(error.errorDescription ?? "Please grant Screen Time permission in Settings")"
                }
            }
        }
    }

    /// Start timeout timer for picker loading
    private func startPickerTimeout() {
        #if DEBUG
        print("[AppUsageViewModel] Starting picker timeout timer (\(pickerTimeoutSeconds) seconds)")
        #endif

        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }

            // Only trigger timeout if picker is still presented and no apps selected
            if self.isFamilyPickerPresented && self.familySelection.applications.isEmpty {
                #if DEBUG
                print("[AppUsageViewModel] ⚠️ Picker timeout triggered - no apps selected after \(self.pickerTimeoutSeconds) seconds")
                #endif

                self.pickerLoadingTimeout = true
                self.pickerError = """
                The app selector is taking longer than expected.

                This can happen due to a system issue with the picker.

                Try:
                • Dismiss this screen and try again
                • If the screen appears blank, close the app completely and reopen
                • Check that Screen Time is enabled in Settings

                Retry attempt: \(self.pickerRetryCount + 1)
                """
            }
        }

        pickerTimeoutWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + pickerTimeoutSeconds, execute: workItem)
    }

    /// Cancel picker timeout timer
    private func cancelPickerTimeout() {
        pickerTimeoutWorkItem?.cancel()
        pickerTimeoutWorkItem = nil

        #if DEBUG
        if pickerTimeoutWorkItem != nil {
            print("[AppUsageViewModel] Cancelled picker timeout timer")
        }
        #endif
    }

    /// Retry opening the picker after timeout or error
    func retryPickerOpen() {
        #if DEBUG
        print("[AppUsageViewModel] Retrying picker open (attempt \(pickerRetryCount + 1))")
        #endif

        pickerRetryCount += 1

        // Close current picker if open
        if isFamilyPickerPresented {
            isFamilyPickerPresented = false
        }

        // Reset error states
        pickerError = nil
        pickerLoadingTimeout = false
        cancelPickerTimeout()

        // Wait a moment then try again
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            switch self.activePickerContext {
            case .learning:
                self.presentLearningPicker()
            case .reward:
                self.presentRewardPicker()
            case nil:
                self.requestAuthorizationAndOpenPicker()
            }
        }
    }

    /// Called when picker selection changes - cancel timeout since picker is working
    func onPickerSelectionChange() {
        #if DEBUG
        print("[AppUsageViewModel] Picker selection changed - cancelling timeout")
        #endif

        cancelPickerTimeout()
        pickerLoadingTimeout = false
        pickerError = nil
        pickerRetryCount = 0  // Reset retry count on successful selection
        // TASK 12 REVISED: Update sorted applications snapshot when picker selection changes
        updateSortedApplications()
    }
    
    /// Open category assignment view for adjusting existing categories
    func openCategoryAssignmentForAdjustment() {
        #if DEBUG
        print("[AppUsageViewModel] Opening category assignment for adjustment")
        print("[AppUsageViewModel] Current family selection has \(familySelection.applications.count) apps")
        #endif
        
        // If we have apps in the current selection, open the category assignment view directly
        if !familySelection.applications.isEmpty {
            isCategoryAssignmentPresented = true
        } else {
            // If no apps are selected, open the picker first
            requestAuthorizationAndOpenPicker()
        }
    }
    
#if DEBUG
/// Configure monitoring with test applications for debugging
func configureWithTestApplications() {
    #if DEBUG
    print("[AppUsageViewModel] Configuring with test applications")
    #endif
    service.configureWithTestApplications()
    // TASK 12 REVISED: Update sorted applications snapshot after test configuration
    updateSortedApplications()
}
#endif
    
    func configureMonitoring() {
        #if DEBUG
        print("[AppUsageViewModel] Configuring monitoring")
        print("[AppUsageViewModel] Family selection details:")
        print("[AppUsageViewModel]   Applications count: \(familySelection.applications.count)")
        print("[AppUsageViewModel]   Categories count: \(familySelection.categories.count)")
        print("[AppUsageViewModel]   Web domains count: \(familySelection.webDomains.count)")
        print("[AppUsageViewModel]   Category assignments: \(categoryAssignments.count)")
        print("[AppUsageViewModel]   Reward points: \(rewardPoints.count)")

        print("[AppUsageViewModel] Selected applications with assigned categories and reward points:")
        for (index, application) in familySelection.applications.enumerated() {
            if let token = application.token {
                let category = categoryAssignments[token]?.rawValue ?? "Not assigned"
                let points = rewardPoints[token] ?? 0
                print("[AppUsageViewModel]   \(index): Token \(token.hashValue) → \(category), \(points) points")
            }
        }

        print("[AppUsageViewModel] Threshold minutes: \(thresholdMinutes)")
        #endif

        let thresholds = thresholdMinutes.reduce(into: [AppUsage.AppCategory: DateComponents]()) { result, entry in
            result[entry.key] = DateComponents(minute: entry.value)
        }

        service.configureMonitoring(
            with: familySelection,
            categoryAssignments: categoryAssignments,
            rewardPoints: rewardPoints,
            thresholds: thresholds.isEmpty ? nil : thresholds
        )
        
        // TASK 12 REVISED: Update sorted applications snapshot after configuring monitoring
        updateSortedApplications()
    }
    
    /// Format time interval for display
    func formatTime(_ timeInterval: TimeInterval) -> String {
        let hours = Int(timeInterval) / 3600
        let minutes = Int(timeInterval) / 60 % 60
        let seconds = Int(timeInterval) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
    
    /// Get reward points for an app token
    func rewardPoints(for token: ApplicationToken) -> Int {
        return rewardPoints[token] ?? 0
    }

    /// Get usage times for all tokens in the current selection
    /// Returns a dictionary mapping ApplicationToken to TimeInterval (usage time in seconds)
    func getUsageTimes() -> [ApplicationToken: TimeInterval] {
        var usageTimes: [ApplicationToken: TimeInterval] = [:]

        #if DEBUG
        print("[AppUsageViewModel] ========== Building usage times map ==========")
        print("[AppUsageViewModel] Family selection has \(familySelection.applications.count) apps")
        #endif

        // TASK 12 REVISED: Use sorted applications snapshot to ensure consistent iteration order
        for (index, application) in sortedApplications.enumerated() {
            guard let token = application.token else {
                #if DEBUG
                print("[AppUsageViewModel]   App \(index): No token, skipping")
                #endif
                continue
            }

            let displayName = application.localizedDisplayName ?? "Unknown App \(index)"
            let duration = service.getUsageDuration(for: token)
            usageTimes[token] = duration

            #if DEBUG
            print("[AppUsageViewModel]   App \(index): \(displayName)")
            print("[AppUsageViewModel]     Token hash: \(token.hashValue)")
            print("[AppUsageViewModel]     Reported usage: \(duration)s")
            #endif
        }

        #if DEBUG
        print("[AppUsageViewModel] ========== Built usage times for \(usageTimes.count) tokens ==========")
        for (token, time) in usageTimes where time > 0 {
            print("[AppUsageViewModel]   Token \(token.hashValue) → \(time)s")
        }
        #endif

        return usageTimes
    }

    // MARK: - Shield Management

    /// Block (shield) all reward apps
    func blockRewardApps() {
        let rewardTokens = categoryAssignments.filter { $0.value == .reward }.map { $0.key }

        guard !rewardTokens.isEmpty else {
            #if DEBUG
            print("[AppUsageViewModel] No reward apps to block")
            #endif
            return
        }

        #if DEBUG
        print("[AppUsageViewModel] 🔒 Blocking \(rewardTokens.count) reward apps")
        #endif

        service.blockRewardApps(tokens: Set(rewardTokens))
    }

    /// Unblock (unlock) all reward apps
    func unlockRewardApps() {
        let rewardTokens = categoryAssignments.filter { $0.value == .reward }.map { $0.key }

        guard !rewardTokens.isEmpty else {
            #if DEBUG
            print("[AppUsageViewModel] No reward apps to unlock")
            #endif
            return
        }

        #if DEBUG
        print("[AppUsageViewModel] 🔓 Unlocking \(rewardTokens.count) reward apps")
        #endif

        service.unblockRewardApps(tokens: Set(rewardTokens))
    }

    /// Clear all shields (unlock all apps)
    func clearAllShields() {
        #if DEBUG
        print("[AppUsageViewModel] 🧹 Clearing all shields")
        #endif

        service.clearAllShields()
    }

    // MARK: - ManagedSettings Testing Methods

    /// Test blocking reward apps
    func testBlockRewardApps() {
        #if DEBUG
        print("[AppUsageViewModel] TEST: Blocking reward apps")
        #endif

        // Get all tokens assigned to "Reward" category
        let rewardTokens = categoryAssignments.filter { $0.value == .reward }.map { $0.key }

        if rewardTokens.isEmpty {
            errorMessage = "No reward apps assigned. Please assign some apps to 'Reward' category first."
            #if DEBUG
            print("[AppUsageViewModel] ❌ Cannot block - no reward apps assigned")
            #endif
            return
        }

        #if DEBUG
        print("[AppUsageViewModel] Blocking \(rewardTokens.count) reward apps:")
        for (token, category) in categoryAssignments where category == .reward {
            print("[AppUsageViewModel]   Token \(token.hashValue) → \(category.rawValue)")
        }
        #endif

        service.blockRewardApps(tokens: Set(rewardTokens))

        #if DEBUG
        print("[AppUsageViewModel] ✅ Block command sent")
        print("[AppUsageViewModel] 🧪 TEST: Try opening a reward app now")
        print("[AppUsageViewModel] Expected: Shield screen should appear")
        #endif

        errorMessage = nil
    }

    /// Test unblocking reward apps
    func testUnblockRewardApps() {
        #if DEBUG
        print("[AppUsageViewModel] TEST: Unblocking reward apps")
        #endif

        let rewardTokens = categoryAssignments.filter { $0.value == .reward }.map { $0.key }

        if rewardTokens.isEmpty {
            errorMessage = "No reward apps assigned."
            #if DEBUG
            print("[AppUsageViewModel] ❌ Cannot unblock - no reward apps assigned")
            #endif
            return
        }

        #if DEBUG
        print("[AppUsageViewModel] Unblocking \(rewardTokens.count) reward apps:")
        for (token, category) in categoryAssignments where category == .reward {
            print("[AppUsageViewModel]   Token \(token.hashValue) → \(category.rawValue)")
        }
        #endif

        service.unblockRewardApps(tokens: Set(rewardTokens))

        #if DEBUG
        print("[AppUsageViewModel] ✅ Unblock command sent")
        print("[AppUsageViewModel] ⚠️  IMPORTANT: If reward app is already running:")
        print("[AppUsageViewModel] 1. Swipe up to see multitasking")
        print("[AppUsageViewModel] 2. Swipe up on the reward app to close it completely")
        print("[AppUsageViewModel] 3. Reopen the app - shield should be GONE")
        print("[AppUsageViewModel] This is due to shield staleness (research finding)")
        #endif

        errorMessage = nil
    }

    /// Test clearing all shields
    func testClearAllShields() {
        #if DEBUG
        print("[AppUsageViewModel] TEST: Clearing all shields")
        #endif

        service.clearAllShields()

        #if DEBUG
        print("[AppUsageViewModel] ✅ All shields cleared")
        print("[AppUsageViewModel] All apps should now be accessible")
        #endif

        errorMessage = nil
    }

    /// Get shield status for display
    func getShieldStatus() -> (blocked: Int, accessible: Int) {
        return service.getShieldStatus()
    }
}

// MARK: - FamilyActivitySelection Extension for Consistent Sorting
