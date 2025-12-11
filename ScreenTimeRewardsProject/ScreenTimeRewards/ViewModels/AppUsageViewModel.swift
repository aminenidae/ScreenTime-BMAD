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
    let earnedPoints: Int  // Actual earned points (stored, not computed)
    let tokenHash: String
    
    // TASK L: Use token hash as stable ID instead of logicalID to prevent re-identification
    var id: String { tokenHash }
    
    init(token: ManagedSettings.ApplicationToken, logicalID: String, displayName: String, pointsPerMinute: Int, totalSeconds: TimeInterval, earnedPoints: Int, tokenHash: String) {
        self.token = token
        self.logicalID = logicalID
        self.displayName = displayName
        self.pointsPerMinute = pointsPerMinute
        self.totalSeconds = totalSeconds
        self.earnedPoints = earnedPoints
        self.tokenHash = tokenHash
    }
}

struct RewardAppSnapshot: Identifiable {
    let token: ManagedSettings.ApplicationToken
    let logicalID: String
    let displayName: String
    let pointsPerMinute: Int
    let totalSeconds: TimeInterval
    let earnedPoints: Int  // Actual earned points (stored, not computed)
    let tokenHash: String
    
    // TASK L: Use token hash as stable ID instead of logicalID to prevent re-identification
    var id: String { tokenHash }
    
    init(token: ManagedSettings.ApplicationToken, logicalID: String, displayName: String, pointsPerMinute: Int, totalSeconds: TimeInterval, earnedPoints: Int, tokenHash: String) {
        self.token = token
        self.logicalID = logicalID
        self.displayName = displayName
        self.pointsPerMinute = pointsPerMinute
        self.totalSeconds = totalSeconds
        self.earnedPoints = earnedPoints
        self.tokenHash = tokenHash
    }
}

/// View model to manage app usage data for the UI
@MainActor
class AppUsageViewModel: ObservableObject {
    @Published var appUsages: [AppUsage] = []
    @Published var isMonitoring = false
    @Published var learningTime: TimeInterval = 0
    @Published var rewardTime: TimeInterval = 0
    @Published var totalRewardPoints: Int = 0
    @Published var learningRewardPoints: Int = 0
    @Published var rewardRewardPoints: Int = 0
    @Published var errorMessage: String?
    @Published var familySelection: FamilyActivitySelection = .init(includeEntireCategory: true)
    @Published var thresholdMinutes: [AppUsage.AppCategory: Int] = [:]
    @Published var isFamilyPickerPresented = false
    @Published var isAuthorizationGranted = false
    @Published var isCategoryAssignmentPresented = false
    @Published var categoryAssignments: [ApplicationToken: AppUsage.AppCategory] = [:]
    @Published var rewardPoints: [ApplicationToken: Int] = [:]
    // Task 0: Add pending selection to capture picker results before they're merged
    @Published var pendingSelection: FamilyActivitySelection = .init(includeEntireCategory: true)
    @Published var appHistoryMapping: [String: [UsagePersistence.DailyUsageSummary]] = [:]
    
    // Track when the picker produced a fresh selection that should be auto-applied
    @Published private var shouldUsePendingSelectionForSheet = false
    
    // TASK 12 REVISED: Add sorted applications snapshot property
    @Published private(set) var sortedApplications: [Application] = []

    // Picker error handling
    @Published var pickerError: String?
    @Published var pickerLoadingTimeout = false
    @Published var pickerRetryCount = 0

    // Snapshot properties for deterministic ordering
    @Published private(set) var learningSnapshots: [LearningAppSnapshot] = []
    @Published private(set) var rewardSnapshots: [RewardAppSnapshot] = []

    // MARK: - Task M: Duplicate Assignment Prevention
    @Published var duplicateAssignmentError: String?

    // MARK: - Point Transfer System
    @Published var unlockedRewardApps: [ApplicationToken: UnlockedRewardApp] = [:]

    /// Total points consumed (spent) from using unlocked reward apps
    /// These points are permanently spent and should not return to available pool
    @Published var totalConsumedPoints: Int = 0

    /// Available learning points (total earned - reserved for unlocked apps - consumed points)
    /// This uses the NEW linked learning app reward system where points are earned
    /// when learning goals are met, not minute-by-minute accrual.
    var availableLearningPoints: Int {
        // Calculate total earned from linked learning goals (new system)
        let totalEarnedFromLinkedGoals = BlockingCoordinator.shared.getTotalEarnedRewardMinutes(for: currentRewardTokens)

        // Reserved points are still tracked the same way
        let totalReserved = unlockedRewardApps.values
            .filter { _ in true }
            .reduce(0) { $0 + $1.reservedPoints }
        let totalConsumed = totalConsumedPoints
        let available = max(0, totalEarnedFromLinkedGoals - totalReserved - totalConsumed)

        #if DEBUG
        print("[AppUsageViewModel] 💰 AVAILABLE POINTS CALCULATION (Linked Goal System):")
        print("[AppUsageViewModel]   Total Earned from Goals: \(totalEarnedFromLinkedGoals)")
        print("[AppUsageViewModel]   Total Reserved: \(totalReserved)")
        print("[AppUsageViewModel]   Total Consumed (spent): \(totalConsumed)")
        print("[AppUsageViewModel]   Available: \(available)")
        #endif

        return available
    }

    /// Get earned reward minutes for a specific reward app based on its linked learning goals
    func getEarnedRewardMinutes(for token: ApplicationToken) -> Int {
        return BlockingCoordinator.shared.getEarnedRewardMinutes(for: token)
    }

    /// Total earned reward minutes from all linked learning goals
    /// This is the total earned from learning - NOT affected by reward app usage
    var totalEarnedMinutes: Int {
        BlockingCoordinator.shared.getTotalEarnedRewardMinutes(for: currentRewardTokens)
    }

    /// Total points reserved for unlocked reward apps
    /// Formula: Reserved Points = Sum of (Redeemed - Consumed) for all unlocked apps
    var reservedLearningPoints: Int {
        let reserved = unlockedRewardApps.values
            .filter { _ in true }
            .reduce(0) { $0 + $1.reservedPoints }

        #if DEBUG
        print("[AppUsageViewModel] 🔒 RESERVED POINTS CALCULATION:")
        for (token, app) in unlockedRewardApps {
            let appName = resolvedDisplayName(for: token) ?? "Unknown"
            print("[AppUsageViewModel]   \(appName): \(app.reservedPoints) points remaining")
        }
        print("[AppUsageViewModel]   Total Reserved: \(reserved)")
        #endif

        return reserved
    }

    /// Total learning points (no bonus calculation)
    var totalLearningPointsWithBonuses: Int {
        return learningRewardPoints
    }

    /// Bonus points (always 0 - challenges removed)
    var bonusLearningPoints: Int {
        return 0
    }

    // MARK: - Streak and Badges (Challenge system removed)
    @Published var currentStreak: Int = 0
    @Published var badges: [Badge] = []
    @Published var showCompletionCelebration = false
    @Published var lastRewardUnlockMinutes: Int = 0

    // Flag to track when we're resetting picker state
    private var isResettingPickerState = false
    
    // Add a new flag to control state reset without affecting presentation (Issue 1 fix)
    @Published private var isPreparing = false

    private let service: ScreenTimeService
    private var masterSelection: FamilyActivitySelection
    private var activePickerContext: PickerContext?
    private var cancellables = Set<AnyCancellable>()
    private let defaultThresholdMinutes = 1
    private let appGroupIdentifier = "group.com.screentimerewards.shared"
    private var pickerTimeoutWorkItem: DispatchWorkItem?
    private let pickerTimeoutSeconds: TimeInterval = 15.0
    private var shouldPresentAssignmentAfterPickerDismiss = false
    private var rewardUsageObserver: Any?  // BF-1 FIX: Observer for reward app usage

    // MARK: - Computed Properties for Tab Views

    /// All application tokens assigned to Learning category
    var learningApps: [ApplicationToken] {
        categoryAssignments.filter { $0.value == AppUsage.AppCategory.learning }.map { $0.key }
    }

    /// All application tokens assigned to Reward category
    var rewardApps: [ApplicationToken] {
        categoryAssignments.filter { $0.value == AppUsage.AppCategory.reward }.map { $0.key }
    }
    
    // MARK: - Child Mode Filtering
    
    /// Filtered learning apps with usage > 0 for Child Mode
    var usedLearningApps: [LearningAppSnapshot] {
        learningSnapshots.filter { $0.totalSeconds > 0 }
    }
    
    /// Filtered reward apps with usage > 0 for Child Mode
    var usedRewardApps: [RewardAppSnapshot] {
        rewardSnapshots.filter { $0.totalSeconds > 0 }
    }
    
    // Task 0: Expose active picker context for sheet presentation
    var currentPickerContext: PickerContext? {
        activePickerContext
    }
    
    // TASK 12: Add sorted category properties
    /// Learning application tokens in stable sorted order
    var sortedLearningApps: [ApplicationToken] {
        sortedApplications
            .compactMap { app -> ApplicationToken? in
                guard let token = app.token,
                      categoryAssignments[token] == AppUsage.AppCategory.learning else { return nil }
                return token
            }
    }

    /// Reward application tokens in stable sorted order
    var sortedRewardApps: [ApplicationToken] {
        sortedApplications
            .compactMap { app -> ApplicationToken? in
                guard let token = app.token,
                      categoryAssignments[token] == AppUsage.AppCategory.reward else { return nil }
                return token
            }
    }
    
    func presentLearningPicker() {
        // FIX: Reset picker state before presenting to prevent ActivityPickerRemoteViewError
        resetPickerStateForNewPresentation()
        
        activePickerContext = .learning
        shouldPresentAssignmentAfterPickerDismiss = false
        
        // CRITICAL FIX: Rehydrate familySelection from masterSelection before every picker launch
        // This ensures the next presentation includes both categories and prevents cross-category data loss
        familySelection = masterSelection
        
        // Set familySelection to include both learning apps and preserve reward apps
        // This prevents reward apps from being lost when opening the learning picker
        let learningSelection = selection(for: AppUsage.AppCategory.learning)
        let rewardSelection = selection(for: AppUsage.AppCategory.reward)

        var combinedSelection = FamilyActivitySelection(includeEntireCategory: true)
        combinedSelection.applicationTokens = learningSelection.applicationTokens.union(rewardSelection.applicationTokens)
        
        // Preserve category/web domain selections
        combinedSelection.categoryTokens = masterSelection.categoryTokens
        combinedSelection.webDomainTokens = masterSelection.webDomainTokens
        
        familySelection = combinedSelection
        requestAuthorizationAndOpenPicker()
    }

    func presentRewardPicker() {
        // FIX: Reset picker state before presenting to prevent ActivityPickerRemoteViewError
        resetPickerStateForNewPresentation()
        
        activePickerContext = .reward
        shouldPresentAssignmentAfterPickerDismiss = false
        
        // CRITICAL FIX: Rehydrate familySelection from masterSelection before every picker launch
        // This ensures the next presentation includes both categories and prevents cross-category data loss
        familySelection = masterSelection
        
        // Set familySelection to include both reward apps and preserve learning apps
        // This prevents learning apps from being lost when opening the reward picker
        let rewardSelection = selection(for: AppUsage.AppCategory.reward)
        let learningSelection = selection(for: AppUsage.AppCategory.learning)

        var combinedSelection = FamilyActivitySelection(includeEntireCategory: true)
        combinedSelection.applicationTokens = rewardSelection.applicationTokens.union(learningSelection.applicationTokens)
        
        // Preserve category/web domain selections
        combinedSelection.categoryTokens = masterSelection.categoryTokens
        combinedSelection.webDomainTokens = masterSelection.webDomainTokens
        
        familySelection = combinedSelection
        requestAuthorizationAndOpenPicker()
    }
    
    // Task 0: Add methods to show category assignment view with proper context
    func showAllLearningApps() {
        activePickerContext = .learning
        // Task 0: Clear pending selection and flag when showing from tabs to prevent stale data
        pendingSelection = .init(includeEntireCategory: true)
        shouldPresentAssignmentAfterPickerDismiss = false
        // Fix: Reset the flag for tab-driven sheets
        shouldUsePendingSelectionForSheet = false
        isCategoryAssignmentPresented = true
    }

    func showAllRewardApps() {
        activePickerContext = .reward
        // Task 0: Clear pending selection and flag when showing from tabs to prevent stale data
        pendingSelection = .init(includeEntireCategory: true)
        shouldPresentAssignmentAfterPickerDismiss = false
        // Fix: Reset the flag for tab-driven sheets
        shouldUsePendingSelectionForSheet = false
        isCategoryAssignmentPresented = true
    }
    
    enum PickerContext {
        case learning
        case reward
        
        // Task 0: Add method to get the corresponding category
        var category: AppUsage.AppCategory {
            switch self {
            case .learning:
                return AppUsage.AppCategory.learning
            case .reward:
                return AppUsage.AppCategory.reward
            }
        }
    }
    
    // MARK: - PickerContext Description

    @MainActor
    init() {
        self.service = ScreenTimeService.shared

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

        // Load unlocked reward apps from persistence
        loadUnlockedApps()

        loadData()

        // BF-1 FIX: Add observer for reward app usage notifications
        setupRewardAppUsageObserver()

        NotificationCenter.default
            .publisher(for: ScreenTimeService.usageDidChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.usageDidChange()
            }
            .store(in: &cancellables)
    }
    
    // BF-1 FIX: Setup observer for reward app usage
    private func setupRewardAppUsageObserver() {
        // Listen for reward app usage notifications from ScreenTimeService
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            { (center, observer, name, object, userInfo) in
                DispatchQueue.main.async {
                    let unmanaged = Unmanaged<AppUsageViewModel>.fromOpaque(observer!)
                    unmanaged.takeUnretainedValue().handleRewardAppUsage()
                }
            },
            "com.screentimerewards.rewardAppUsed" as CFString,
            nil,
            .deliverImmediately
        )
    }

    // BF-1 FIX: Handle reward app usage notification
    private func handleRewardAppUsage() {
        guard let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) else { return }
        
        // Retrieve the reward usage data
        guard let rewardUsageData = sharedDefaults.dictionary(forKey: "rewardUsageData") as? [String: [String: Any]] else {
            return
        }
        
        #if DEBUG
        print("[AppUsageViewModel] 📝 Processing reward app usage data...")
        #endif
        
        // Process each reward app usage entry
        for (logicalID, data) in rewardUsageData {
            guard let usageSeconds = data["usageSeconds"] as? TimeInterval,
                  let tokenHash = data["tokenHash"] as? String else {
                continue
            }
            
            #if DEBUG
            print("[AppUsageViewModel] Processing usage for logicalID: \(logicalID), seconds: \(usageSeconds)")
            #endif
            
            // Find the matching token in our master selection
            if let token = masterSelection.applicationTokens.first(where: { String($0.hashValue) == tokenHash }) {
                #if DEBUG
                let appName = masterSelection.applications.first { $0.token == token }?.localizedDisplayName ?? "Unknown App"
                print("[AppUsageViewModel] Found matching token for \(appName), consuming reserved points...")
                #endif
                
                // Consume reserved points for this reward app
                consumeReservedPoints(token: token, usageSeconds: usageSeconds)
            }
        }
        
        // Clear the processed data
        sharedDefaults.removeObject(forKey: "rewardUsageData")
        sharedDefaults.synchronize()
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
                // For now, just track the category mapping logic
                // Real implementation would need need token persistence strategy
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
        // PHASE 1 FIX: Check for and reset stale data at midnight
        // This ensures usage resets to 0 when the app is opened after midnight
        let startOfToday = Calendar.current.startOfDay(for: Date())
        var needsReset = false

        // Check if any app has stale data (lastResetDate < today)
        for application in sortedApplications {
            guard let token = application.token else { continue }
            let tokenHash = service.usagePersistence.tokenHash(for: token)
            let logicalID = service.usagePersistence.logicalID(for: tokenHash) ?? tokenHash
            if let persistedApp = service.usagePersistence.app(for: logicalID) {
                if persistedApp.lastResetDate < startOfToday {
                    needsReset = true
                    #if DEBUG
                    print("[AppUsageViewModel] 🕐 Detected stale data for \(persistedApp.displayName): lastResetDate=\(persistedApp.lastResetDate) < today=\(startOfToday)")
                    #endif
                    break
                }
            }
        }

        // If any app has stale data, reset all daily counters
        if needsReset {
            #if DEBUG
            print("[AppUsageViewModel] 🔄 Triggering midnight reset for all apps")
            #endif
            service.usagePersistence.resetDailyCounters()
            // Notify other parts of the system about the reset
            NotificationCenter.default.post(name: .dailyUsageReset, object: nil)
        }

        var newLearningSnapshots: [LearningAppSnapshot] = []
        var newRewardSnapshots: [RewardAppSnapshot] = []

        // Use a set to track token hashes we've already processed to avoid duplicates
        var processedTokenHashes: Set<String> = []

        // Single pass over sorted applications
        for application in sortedApplications {
            guard let token = application.token else { continue }

            // FIX: Check against masterSelection instead of familySelection to prevent
            // apps from disappearing when opening a different category's picker
            // masterSelection contains all apps across all categories, while familySelection
            // may be filtered to only show apps for the current picker context
            if !masterSelection.applicationTokens.contains(token) {
                #if DEBUG
                print("[AppUsageViewModel] Skipping orphaned token: \(token.hashValue)")
                #endif
                continue
            }
            
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
            let category = categoryAssignments[token] ?? AppUsage.AppCategory.learning
            
            // CRITICAL FIX: Read directly from persistence instead of computed todayUsage
            // BUG: appUsage.todayUsage is computed from sessions array, which contains a mega-session
            // spanning from createdAt (days ago) to lastUpdated (today), causing huge overcounts
            // FIX: Use persisted todaySeconds which is accurately updated by threshold events
            // FIX 2: Also check lastResetDate to handle stale data from previous days
            var totalSeconds: TimeInterval = 0
            var earnedPoints: Int = 0

            if let persistedApp = service.usagePersistence.app(for: logicalID) {
                // FIX: Check if the data is actually from today
                let startOfToday = Calendar.current.startOfDay(for: Date())
                if persistedApp.lastResetDate >= startOfToday {
                    totalSeconds = TimeInterval(persistedApp.todaySeconds)
                    earnedPoints = persistedApp.todayPoints
                } else {
                    // Data is stale (from yesterday or earlier) - treat as 0
                    #if DEBUG
                    print("[AppUsageViewModel] ⚠️ Stale data for \(displayName): lastResetDate=\(persistedApp.lastResetDate) < startOfToday=\(startOfToday)")
                    #endif
                    totalSeconds = 0
                    earnedPoints = 0
                }
            }

            #if DEBUG
            if totalSeconds > 0 {
                print("[AppUsageViewModel] 🔍 DIAGNOSTIC: Reading usage for '\(displayName)'")
                print("[AppUsageViewModel] 🔍 DIAGNOSTIC: logicalID=\(logicalID), todayUsage=\(totalSeconds)s")
            }
            #endif

            // Look up assigned points
            let pointsPerMinute = rewardPoints[token] ?? getDefaultRewardPoints(for: category)

            switch category {
            case AppUsage.AppCategory.learning:
                let snapshot = LearningAppSnapshot(
                    token: token,
                    logicalID: logicalID,
                    displayName: displayName,
                    pointsPerMinute: pointsPerMinute,
                    totalSeconds: totalSeconds,
                    earnedPoints: earnedPoints,
                    tokenHash: tokenHash
                )
                newLearningSnapshots.append(snapshot)
            case AppUsage.AppCategory.reward:
                let snapshot = RewardAppSnapshot(
                    token: token,
                    logicalID: logicalID,
                    displayName: displayName,
                    pointsPerMinute: pointsPerMinute,
                    totalSeconds: totalSeconds,
                    earnedPoints: earnedPoints,
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
        // Standardize default rate so new learning/reward apps start at 10 pts/min
        return 10
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

        #if DEBUG
        print("[AppUsageViewModel] 🔄 MERGE CURRENT SELECTION INTO MASTER STARTED")
        print("[AppUsageViewModel]   Active picker context: \(context)")
        print("[AppUsageViewModel]   Current tokens count: \(currentTokens.count)")
        print("[AppUsageViewModel]   Master selection tokens count (before merge): \(merged.applicationTokens.count)")
        print("[AppUsageViewModel]   Category assignments count (before merge): \(categoryAssignments.count)")
        
        // Log current tokens
        for token in currentTokens {
            let appName = masterSelection.applications.first { $0.token == token }?.localizedDisplayName ?? "Unknown App"
            if let category = categoryAssignments[token] {
                print("[AppUsageViewModel]     Current token: \(appName) (token: \(token.hashValue)) → \(category.rawValue)")
            } else {
                print("[AppUsageViewModel]     Current token: \(appName) (token: \(token.hashValue)) → unassigned")
            }
        }
        #endif

        let retainedTokens = merged.applicationTokens.filter { token in
            let category = categoryAssignments[token] ?? AppUsage.AppCategory.learning
            switch context {
            case .learning:
                return category == AppUsage.AppCategory.reward
            case .reward:
                return category == AppUsage.AppCategory.learning
            }
        }

        var combinedTokens = Set(retainedTokens)
        combinedTokens.formUnion(currentTokens)
        merged.applicationTokens = combinedTokens

        // FIX: Preserve application objects with display names when merging
        // Create a new set of applications that includes both retained and current applications
        var mergedApplications: Set<Application> = []
        
        // Add applications that should be retained from the existing master selection
        for application in masterSelection.applications {
            if let token = application.token {
                let category = categoryAssignments[token] ?? AppUsage.AppCategory.learning
                switch context {
                case .learning:
                    // Retain reward apps when processing learning picker
                    if category == AppUsage.AppCategory.reward {
                        mergedApplications.insert(application)
                    }
                case .reward:
                    // Retain learning apps when processing reward picker
                    if category == AppUsage.AppCategory.learning {
                        mergedApplications.insert(application)
                    }
                }
            }
        }
        
        // Add applications from the current family selection (these have the display names from the picker)
        mergedApplications.formUnion(familySelection.applications)
        
        // Since we can't directly set applications, we need to work with what we have
        // The applications will be preserved through the familySelection which is updated below

        // Preserve category/web domain selections as-is for now
        merged.categoryTokens = masterSelection.categoryTokens
        merged.webDomainTokens = masterSelection.webDomainTokens

        masterSelection = merged
        // FIX: Don't set familySelection to the merged selection
        // Instead, keep familySelection as is (containing only the current context's apps)
        // This ensures that subsequent calls to selection(for:) work correctly
        activePickerContext = nil
        
        #if DEBUG
        print("[AppUsageViewModel]   Retained tokens count: \(retainedTokens.count)")
        print("[AppUsageViewModel]   Combined tokens count: \(combinedTokens.count)")
        print("[AppUsageViewModel]   Master selection tokens count (after merge): \(masterSelection.applicationTokens.count)")
        print("[AppUsageViewModel]   Master selection applications count (after merge): \(masterSelection.applications.count)")
        print("[AppUsageViewModel]   Family selection tokens count (after merge): \(familySelection.applicationTokens.count)")
        print("[AppUsageViewModel] 🔄 MERGE CURRENT SELECTION INTO MASTER COMPLETED")
        #endif
        
        // REHYDRATION FIX: Set familySelection = masterSelection after merge to ensure
        // everyday UI and future picker launches start from the full, consistent selection
        familySelection = masterSelection
        
        // TASK L: Ensure sorted applications are updated after master selection change
        updateSortedApplications()
    }
    
    func selection(for category: AppUsage.AppCategory) -> FamilyActivitySelection {
        // Task 0: If we have a pending selection, use that for filtering
        // Otherwise, use the master selection
        let sourceSelection = !pendingSelection.applications.isEmpty ? pendingSelection : masterSelection

        var result = FamilyActivitySelection(includeEntireCategory: true)
        let filteredTokens = sourceSelection.applicationTokens.filter { token in
            categoryAssignments[token] == category
        }
        result.applicationTokens = Set(filteredTokens)
        
        #if DEBUG
        print("[AppUsageViewModel] 🔄 SELECTION FOR CATEGORY: \(category.rawValue)")
        print("[AppUsageViewModel]   Source selection tokens count: \(sourceSelection.applicationTokens.count)")
        print("[AppUsageViewModel]   Category assignments count: \(categoryAssignments.count)")
        print("[AppUsageViewModel]   Filtered tokens count: \(filteredTokens.count)")
        
        for token in filteredTokens {
            let appName = sourceSelection.applications.first { $0.token == token }?.localizedDisplayName ?? "Unknown App"
            print("[AppUsageViewModel]     Filtered token: \(appName) (token: \(token.hashValue)) → \(category.rawValue)")
        }
        #endif
        
        return result
    }
    
    // Task 0: Overload selection method to accept PickerContext
    func selection(for context: PickerContext) -> FamilyActivitySelection {
        switch context {
        case .learning:
            return selection(for: AppUsage.AppCategory.learning)
        case .reward:
            return selection(for: AppUsage.AppCategory.reward)
        }
    }
    
    /// Handle category assignment completion
    func onCategoryAssignmentSave() {
        #if DEBUG
        print("[AppUsageViewModel] 🔄 ON CATEGORY ASSIGNMENT SAVE STARTED")
        print("[AppUsageViewModel]   Current category assignments count: \(categoryAssignments.count)")
        for (token, category) in categoryAssignments {
            let appName = masterSelection.applications.first { $0.token == token }?.localizedDisplayName ?? "Unknown App"
            print("[AppUsageViewModel]     Current: \(appName) (token: \(token.hashValue)) → \(category.rawValue)")
        }
        #endif

        // Task M: Check for duplicate assignments before proceeding
        // Note: This validation is now primarily handled in the view, but we keep it as a safety check
        if hasDuplicateAssignments() {
            #if DEBUG
            print("[AppUsageViewModel] ❌ Duplicate assignments detected in hasDuplicateAssignments(), aborting save")
            #endif
            
            return
        }

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
        
        // CRITICAL FIX: Remove the line that copies familySelection back into masterSelection after configureMonitoring()
        // This overwrite drops the opposite category whenever a picker saves
        // Instead, rely on familySelection = masterSelection after persistence (done below)
        // masterSelection = familySelection  // REMOVED THIS LINE - CONFIRMED REMOVED

        // Task 0: Clear the pending selection after successful save
        pendingSelection = FamilyActivitySelection(includeEntireCategory: true)
        shouldPresentAssignmentAfterPickerDismiss = false
        // Fix: Reset the flag when sheet finishes
        shouldUsePendingSelectionForSheet = false

        // INSTRUMENTATION: Log view-model snapshots after service call completes
        #if DEBUG
        print("[AppUsageViewModel] === VIEW MODEL SNAPSHOT AFTER configureMonitoring ===")
        logViewModelSnapshots()
        print("[AppUsageViewModel] === END VIEW MODEL SNAPSHOT AFTER configureMonitoring ===")
        #endif
        // END INSTRUMENTATION
        
        // REHYDRATION FIX: Set familySelection = masterSelection after persistence to ensure
        // everyday UI and future picker launches start from the full, consistent selection
        familySelection = masterSelection
        
        // TASK L: Trigger UI refresh after save & monitor to eliminate need for restart
        // This re-sorts apps and refreshes UI immediately without requiring app restart
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // Refresh the ViewModel data to update the UI
            self.refreshData()
        }
        
        #if DEBUG
        print("[AppUsageViewModel] 🔄 ON CATEGORY ASSIGNMENT SAVE COMPLETED")
        #endif
    }

    func cancelCategoryAssignment() {
        familySelection = masterSelection
        activePickerContext = nil
        pendingSelection = FamilyActivitySelection(includeEntireCategory: true)  // Task 0: Clear pending selection on cancel
        shouldPresentAssignmentAfterPickerDismiss = false
        // Fix: Reset the flag when sheet is cancelled
        shouldUsePendingSelectionForSheet = false
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
        // Use the shared resolver so debug logging matches production UI
        return resolvedDisplayName(for: token)
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
    /// - Parameter force: If true, bypasses the isMonitoring check (for explicit user-requested starts)
    func startMonitoring(force: Bool = false) {
        // ALWAYS print this - not wrapped in DEBUG - for troubleshooting
        print("[AppUsageViewModel] 🎯 startMonitoring() called (force=\(force), isMonitoring=\(isMonitoring))")

        guard !isMonitoring || force else {
            print("[AppUsageViewModel] ⚠️ Monitoring already active, skipping start")
            return
        }

        if force && isMonitoring {
            print("[AppUsageViewModel] 🔄 Force-starting monitoring despite isMonitoring=true")
        }
        print("[AppUsageViewModel] 🚀 Starting monitoring...")

        errorMessage = nil
        service.startMonitoring { [weak self] result in
            guard let self else { return }
            DispatchQueue.main.async {
                switch result {
                case .success:
                    print("[AppUsageViewModel] ✅ Monitoring started successfully!")
                    self.isMonitoring = true
                    self.refreshData()
                    // Run diagnostics after successful start
                    self.service.printUsageTrackingDiagnostics()
                case .failure(let error):
                    print("[AppUsageViewModel] ❌ Failed to start monitoring: \(error)")
                    print("[AppUsageViewModel] ❌ Error: \(error.errorDescription ?? "No description")")
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
        appUsages = service.getAppUsages().sorted { $0.totalTime > $1.totalTime }
        appHistoryMapping = service.getDailyHistories()
        updateCategoryTotals()
        updateTotalRewardPoints()
        updateCategoryRewardPoints()
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

        // Also refresh blocking states to ensure shields are synced
        // This catches any missed updates from the periodic timer
        BlockingCoordinator.shared.refreshAllBlockingStates()
    }

    /// Refresh snapshots to reflect updated point values
    func refreshSnapshotsOnly() {
        updateSnapshots()
    }
    
    /// Update category totals using the locally cached data
    private func updateCategoryTotals() {
        let previousLearningTime = learningTime
        let previousRewardTime = rewardTime

        // Read from snapshots (which use todaySeconds) instead of appUsages (which use stale sessions)
        learningTime = learningSnapshots
            .reduce(0) { $0 + $1.totalSeconds }
        rewardTime = rewardSnapshots
            .reduce(0) { $0 + $1.totalSeconds }
        
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
            .filter { $0.category == AppUsage.AppCategory.learning }
            .reduce(0) { $0 + $1.earnedRewardPoints }
        rewardRewardPoints = appUsages
            .filter { $0.category == AppUsage.AppCategory.reward }
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
        familySelection = .init(includeEntireCategory: true)
        masterSelection = .init(includeEntireCategory: true)
        // TASK 12 REVISED: Update sorted applications snapshot after reset
        updateSortedApplications()
        // Task 0: Clear pending selection on reset
        pendingSelection = .init(includeEntireCategory: true)
    }

    /// Request authorization BEFORE opening FamilyActivityPicker
    func requestAuthorizationAndOpenPicker() {
        #if DEBUG
        print("[AppUsageViewModel] Requesting FamilyControls authorization before opening picker")

        // Validate picker state before proceeding
        guard validatePickerState() else {
            #if DEBUG
            print("[AppUsageViewModel] ❌ Picker state validation failed - aborting picker presentation")
            #endif
            errorMessage = "Unable to present app selector. Please try again."
            return
        }

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

                    // No need to wait 0.5s - authorization is already done
                    // Just set to true immediately to prevent flicker
                    self.isFamilyPickerPresented = true
                    self.startPickerTimeout()
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
    
    // HARDENING FIX: Add method to handle picker presentation with retry logic
    /// Present picker with error handling and retry capability
    func presentPickerWithRetry(for context: PickerContext) {
        #if DEBUG
        print("[AppUsageViewModel] 🔁 Presenting picker with retry logic for context: \(context)")
        #endif
        
        // Reset picker state for clean presentation
        resetPickerStateForNewPresentation()
        
        // Set the active picker context and family selection based on context
        activePickerContext = context
        shouldPresentAssignmentAfterPickerDismiss = false
        
        // Set familySelection to the appropriate category selection
        switch context {
        case .learning:
            familySelection = selection(for: AppUsage.AppCategory.learning)
        case .reward:
            familySelection = selection(for: AppUsage.AppCategory.reward)
        }
        
        // Request authorization and open picker
        requestAuthorizationAndOpenPicker()
    }
    
    /// Present picker with error handling and retry capability (backward compatibility)
    func presentPickerWithRetry() {
        #if DEBUG
        print("[AppUsageViewModel] 🔁 Presenting picker with retry logic (no context specified)")
        #endif
        
        // Reset picker state for clean presentation
        resetPickerStateForNewPresentation()
        
        // Request authorization and open picker
        requestAuthorizationAndOpenPicker()
    }
    
    // TASK M: Add method to handle ActivityPickerRemoteViewError specifically
    /// Handle FamilyControls.ActivityPickerRemoteViewError and attempt recovery
    func handleActivityPickerRemoteViewError(error: String, context: PickerContext? = nil) {
        #if DEBUG
        print("[AppUsageViewModel] ❌ ActivityPickerRemoteViewError detected: \(error)")
        print("[AppUsageViewModel] 🔁 Attempting recovery for context: \(String(describing: context))")
        #endif
        
        // Log the error for diagnostics
        pickerError = "Picker error: \(error)"
        
        // Perform full state reset
        resetPickerState()
        
        // Rehydrate familySelection from masterSelection
        familySelection = masterSelection
        
        // Retry counter
        pickerRetryCount += 1
        
        // If this is the first retry, attempt to reopen picker with proper context
        if pickerRetryCount <= 1, let context = context {
            #if DEBUG
            print("[AppUsageViewModel] 🔁 First retry attempt with context \(context) - reopening picker")
            #endif
            
            // Small delay before retry
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self.presentPickerWithRetry(for: context)
            }
        } else {
            #if DEBUG
            print("[AppUsageViewModel] ❌ Retry limit exceeded or no context - showing user-facing error")
            #endif
            
            // Show user-facing error message if retry fails
            pickerError = """
            Unable to open the app selector due to a system error.
            
            Please try:
            • Close the app completely and reopen
            • Check that Screen Time is enabled in Settings
            • Try again in a few minutes
            
            If the problem persists, please restart your device.
            """
        }
    }

    // FIX: Add method to validate picker state before presentation
    /// Validate picker state before presentation to prevent ActivityPickerRemoteViewError
    private func validatePickerState() -> Bool {
        #if DEBUG
        print("[AppUsageViewModel] 🔍 Validating picker state before presentation")
        #endif
        
        // Check if we have a valid active picker context
        guard activePickerContext != nil else {
            #if DEBUG
            print("[AppUsageViewModel] ⚠️ No active picker context - cannot present picker")
            #endif
            return false
        }
        
        // Check if family selection is in a valid state
        if familySelection.applicationTokens.isEmpty && 
           familySelection.categoryTokens.isEmpty && 
           familySelection.webDomainTokens.isEmpty {
            #if DEBUG
            print("[AppUsageViewModel] ℹ️ Family selection is empty - this is normal for new picker presentation")
            #endif
        }
        
        #if DEBUG
        print("[AppUsageViewModel] ✅ Picker state validation passed")
        #endif
        return true
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
        shouldPresentAssignmentAfterPickerDismiss = false

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
            case .some(.learning):
                self.presentLearningPicker()
            case .some(.reward):
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
        
        // Task 0: Capture the pending selection when picker changes
        pendingSelection = familySelection
        
        // Fix: Set flag to true when capturing new picker results
        shouldUsePendingSelectionForSheet = true
        
        if isFamilyPickerPresented && !familySelection.applicationTokens.isEmpty {
            shouldPresentAssignmentAfterPickerDismiss = true
        } else if familySelection.applicationTokens.isEmpty {
            shouldPresentAssignmentAfterPickerDismiss = false
        }

        // TASK 12 REVISED: Update sorted applications snapshot when picker selection changes
        updateSortedApplications()
    }
    
    /// Called when the FamilyActivityPicker is dismissed to decide whether to open the assignment sheet
    func onFamilyPickerDismissed() {
        #if DEBUG
        print("[AppUsageViewModel] 🔽 Picker dismissed")
        #endif

        cancelPickerTimeout()
        pickerLoadingTimeout = false

        guard shouldPresentAssignmentAfterPickerDismiss,
              shouldUsePendingSelectionForSheet,
              !pendingSelection.applicationTokens.isEmpty else {
            shouldPresentAssignmentAfterPickerDismiss = false
            shouldUsePendingSelectionForSheet = false
            // CRITICAL FIX: Reset picker flag even when not showing assignment sheet
            isFamilyPickerPresented = false
            return
        }

        shouldPresentAssignmentAfterPickerDismiss = false
        isFamilyPickerPresented = false

        #if DEBUG
        print("[AppUsageViewModel] ⚙️ Auto-applying \(pendingSelection.applicationTokens.count) apps for context \(currentPickerContext?.category.rawValue ?? "unknown")")
        #endif

        autoAssignPendingSelectionAndStartMonitoring()
    }
    
    private func autoAssignPendingSelectionAndStartMonitoring() {
        guard !pendingSelection.applicationTokens.isEmpty else { return }
        guard let context = currentPickerContext else {
            shouldUsePendingSelectionForSheet = false
            return
        }

        let targetCategory = context.category

        var updatedAssignments = categoryAssignments
        var updatedRewardPoints = rewardPoints

        for token in pendingSelection.applicationTokens {
            updatedAssignments[token] = targetCategory
            updatedRewardPoints[token] = getDefaultRewardPoints(for: targetCategory)
        }

        categoryAssignments = updatedAssignments
        rewardPoints = updatedRewardPoints
        shouldUsePendingSelectionForSheet = false

        onCategoryAssignmentSave()

        if context == .reward {
            blockRewardApps()
        }

        startMonitoring()
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
    
    // Task 0: Add method to get the appropriate selection for CategoryAssignmentView
    func getSelectionForCategoryAssignment() -> FamilyActivitySelection {
        // Fix: Use pendingSelection when flag is set and payload is not empty
        if shouldUsePendingSelectionForSheet && !pendingSelection.applications.isEmpty {
            return pendingSelection
        } else if let context = activePickerContext {
            return selection(for: context.category)
        } else {
            return familySelection
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
    /// Uses unified TimeFormatting utility for consistent display across all views
    func formatTime(_ timeInterval: TimeInterval) -> String {
        return TimeFormatting.formatSecondsCompact(timeInterval)
    }
    
    /// Get reward points for an app token
    func rewardPoints(for token: ApplicationToken) -> Int {
        return rewardPoints[token] ?? 0
    }

    /// Resolve a user-facing display name for a token using the best available cache
    func resolvedDisplayName(for token: ApplicationToken) -> String? {
        // First, try to get the name from the current familySelection (most recent)
        if let name = familySelection.applications.first(where: { $0.token == token })?.localizedDisplayName {
            return name
        }

        // Then, try the masterSelection
        if let name = masterSelection.applications.first(where: { $0.token == token })?.localizedDisplayName {
            return name
        }

        // Finally, try the service
        if let name = service.getDisplayName(for: token) {
            return name
        }
        
        // As a fallback, try to get the name from the pending selection
        if let name = pendingSelection.applications.first(where: { $0.token == token })?.localizedDisplayName {
            return name
        }

        return nil
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

    /// Get current reward tokens as a set (for BlockingCoordinator)
    private var currentRewardTokens: Set<ApplicationToken> {
        Set(categoryAssignments.filter { $0.value == AppUsage.AppCategory.reward }.map { $0.key })
    }

    /// Sync shields with current reward app selection
    /// Uses BlockingCoordinator to determine blocking reasons and apply shields appropriately
    func blockRewardApps() {
        let rewardTokens = currentRewardTokens

        #if DEBUG
        print("[AppUsageViewModel] 🔄 Syncing shields with \(rewardTokens.count) reward apps via BlockingCoordinator")
        #endif

        // Use BlockingCoordinator instead of direct ScreenTimeService call
        // This ensures proper blocking reasons are set based on downtime, limits, and learning goals
        BlockingCoordinator.shared.syncAllRewardApps(tokens: rewardTokens)

        // Update coordinator's tracked tokens for periodic refresh
        BlockingCoordinator.shared.updateTrackedTokens(rewardTokens)
    }

    /// Unblock (unlock) reward apps - routes through BlockingCoordinator
    /// Note: Apps will only actually unblock if ALL conditions are met (learning goal, not in downtime, under limit)
    func unlockRewardApps() {
        let rewardTokens = currentRewardTokens

        guard !rewardTokens.isEmpty else {
            #if DEBUG
            print("[AppUsageViewModel] No reward apps to unlock")
            #endif
            return
        }

        #if DEBUG
        print("[AppUsageViewModel] 🔓 Requesting unlock for \(rewardTokens.count) reward apps via BlockingCoordinator")
        #endif

        // Route through BlockingCoordinator - it will check all conditions
        // and only unblock apps where ALL blocking conditions are cleared
        BlockingCoordinator.shared.syncAllRewardApps(tokens: rewardTokens)
    }

    /// Clear all shields (unlock all apps)
    func clearAllShields() {
        #if DEBUG
        print("[AppUsageViewModel] 🧹 Clearing all shields")
        #endif

        service.clearAllShields()
    }

    // MARK: - Point Transfer System Methods

    /// Check if a reward app can be unlocked (checks downtime, limits, learning goal, and points)
    func canUnlockRewardApp(token: ApplicationToken) -> (canUnlock: Bool, reason: String?) {
        // Check if already unlocked
        if unlockedRewardApps[token] != nil {
            return (false, "App is already unlocked")
        }

        // Check blocking conditions via BlockingCoordinator (downtime, daily limit, learning goal)
        let decision = BlockingCoordinator.shared.evaluateBlockingState(for: token)
        if decision.shouldBlock {
            // Return user-friendly message for the blocking reason
            switch decision.primaryReason {
            case .downtime:
                if let startHour = decision.downtimeWindowStartHour,
                   let startMinute = decision.downtimeWindowStartMinute,
                   let endHour = decision.downtimeWindowEndHour,
                   let endMinute = decision.downtimeWindowEndMinute,
                   let dayName = decision.downtimeDayName {
                    let startTime = formatTime(hour: startHour, minute: startMinute)
                    let endTime = formatTime(hour: endHour, minute: endMinute)
                    return (false, "App is in downtime. Available \(dayName) \(startTime)-\(endTime).")
                }
                return (false, "App is in downtime.")
            case .dailyLimitReached:
                if let limit = decision.dailyLimitMinutes {
                    return (false, "Daily limit of \(limit) minutes reached.")
                }
                return (false, "Daily limit reached.")
            case .learningGoal:
                if let target = decision.learningTargetMinutes, let current = decision.learningCurrentMinutes {
                    let remaining = target - current
                    return (false, "Complete \(remaining) more minutes of learning first.")
                }
                return (false, "Complete your learning goal first.")
            case .rewardTimeExpired:
                return (false, "Your reward time has expired. Complete more learning to earn more!")
            case .none:
                break
            }
        }

        // Get points per minute for this app
        guard let pointsPerMinute = rewardPoints[token], pointsPerMinute > 0 else {
            return (false, "Reward points not configured for this app")
        }

        // Calculate minimum points needed (15 minutes)
        let minimumPoints = pointsPerMinute * 15

        // Check if user has enough available points
        if availableLearningPoints < minimumPoints {
            return (false, "Need \(minimumPoints) points (15 min minimum). You have \(availableLearningPoints) available.")
        }

        return (true, nil)
    }

    /// Helper to format time for display
    private func formatTime(hour: Int, minute: Int) -> String {
        let period = hour >= 12 ? "PM" : "AM"
        let displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
        if minute == 0 {
            return "\(displayHour) \(period)"
        }
        return String(format: "%d:%02d %@", displayHour, minute, period)
    }

    /// Unlock a reward app by reserving learning points
    /// Note: Also checks downtime/daily limit conditions via BlockingCoordinator
    func unlockRewardApp(
        token: ApplicationToken,
        minutes: Int,
        bypassPointValidation: Bool = false,
        isChallengeReward: Bool = false
    ) {
        // Check blocking conditions via BlockingCoordinator (downtime, daily limit)
        // Note: For challenge rewards, we still check but may want to allow unlock
        // and show appropriate message when they try to use the app
        if !isChallengeReward {
            let decision = BlockingCoordinator.shared.evaluateBlockingState(for: token)
            // Check only downtime and daily limit (not learning goal since they're redeeming points)
            let hasDowntimeOrLimit = decision.allActiveReasons.contains(.downtime) ||
                                     decision.allActiveReasons.contains(.dailyLimitReached)
            if hasDowntimeOrLimit {
                let appName = resolvedDisplayName(for: token) ?? "Unknown App"
                switch decision.primaryReason {
                case .downtime:
                    if let startHour = decision.downtimeWindowStartHour,
                       let startMinute = decision.downtimeWindowStartMinute,
                       let endHour = decision.downtimeWindowEndHour,
                       let endMinute = decision.downtimeWindowEndMinute,
                       let dayName = decision.downtimeDayName {
                        let startTime = formatTime(hour: startHour, minute: startMinute)
                        let endTime = formatTime(hour: endHour, minute: endMinute)
                        errorMessage = "\(appName) is in downtime. Available \(dayName) \(startTime)-\(endTime)."
                    } else {
                        errorMessage = "\(appName) is in downtime."
                    }
                case .dailyLimitReached:
                    errorMessage = "\(appName) has reached its daily limit."
                default:
                    break
                }
                #if DEBUG
                print("[AppUsageViewModel] ❌ Cannot unlock - \(decision.primaryReason?.displayMessage ?? "blocked")")
                #endif
                return
            }
        }

        guard let pointsPerMinute = rewardPoints[token], pointsPerMinute > 0 else {
            #if DEBUG
            print("[AppUsageViewModel] ❌ Cannot unlock - no points configured for app")
            #endif
            return
        }

        // Ensure minimum minutes (challenge unlocks can be lower)
        let minimumMinutes = isChallengeReward ? 1 : 15
        let actualMinutes = max(minimumMinutes, minutes)
        let pointsNeeded = pointsPerMinute * actualMinutes

        // Check if user has enough available points
        if !bypassPointValidation {
            guard availableLearningPoints >= pointsNeeded else {
                #if DEBUG
                print("[AppUsageViewModel] ❌ Cannot unlock - insufficient points")
                print("[AppUsageViewModel]   Need: \(pointsNeeded), Available: \(availableLearningPoints)")
                #endif
                errorMessage = "Insufficient points. Need \(pointsNeeded) points for \(actualMinutes) minutes."
                return
            }
        }

        #if DEBUG
        let appName = resolvedDisplayName(for: token) ?? "Unknown App"
        let earnedBefore = learningRewardPoints
        #endif

        if var existing = unlockedRewardApps[token] {
            if isChallengeReward && existing.isChallengeReward {
                existing.reservedPoints += pointsNeeded
                unlockedRewardApps[token] = existing
                persistUnlockedApps()
                #if DEBUG
                print("[AppUsageViewModel] 🎁 EXTENDED CHALLENGE UNLOCK \(appName): +\(actualMinutes) min")
                #endif
                return
            } else if isChallengeReward {
                #if DEBUG
                print("[AppUsageViewModel] ℹ️ \(appName) already unlocked with points – challenge unlock skipped")
                #endif
                return
            }
        }

        // Create unlocked app entry with stable token hash
        let tokenHash = service.usagePersistence.tokenHash(for: token)
        let unlockedApp = UnlockedRewardApp(
            token: token,
            tokenHash: tokenHash,
            reservedPoints: pointsNeeded,
            pointsPerMinute: pointsPerMinute,
            isChallengeReward: isChallengeReward
        )

        unlockedRewardApps[token] = unlockedApp

        // Unblock the app via shield management
        service.unblockRewardApps(tokens: [token])

        // Persist the unlock state
        persistUnlockedApps()

        #if DEBUG
        if isChallengeReward {
            print("[AppUsageViewModel] 🎁 CHALLENGE UNLOCK \(appName): \(actualMinutes) min bonus access")
        } else {
            print("[AppUsageViewModel] ✅ UNLOCKED \(appName):")
            print("[AppUsageViewModel]   Redemption: \(actualMinutes) minutes × \(pointsPerMinute) pts/min = \(pointsNeeded) points")
            print("[AppUsageViewModel]   Total Earned: \(earnedBefore) points")
            print("[AppUsageViewModel]   Reserved: \(pointsNeeded) points (initially redeemed)")
            print("[AppUsageViewModel]   Available: \(availableLearningPoints) points (\(earnedBefore) - \(pointsNeeded))")
        }
        #endif
    }

    /// Lock a reward app and return unused reserved points
    func lockRewardApp(token: ApplicationToken) {
        guard let unlockedApp = unlockedRewardApps[token] else {
            #if DEBUG
            print("[AppUsageViewModel] ⚠️ App not unlocked")
            #endif
            return
        }

        #if DEBUG
        let appName = resolvedDisplayName(for: token) ?? "Unknown App"
        let earnedTotal = learningRewardPoints
        let reservedBefore = reservedLearningPoints
        let pointsToReturn = unlockedApp.reservedPoints
        #endif

        // Remove from unlocked apps (returns points to available pool)
        unlockedRewardApps.removeValue(forKey: token)

        // Block the app via shield management
        service.blockRewardApps(tokens: [token])

        // Persist the state
        persistUnlockedApps()

        #if DEBUG
        let reservedAfter = reservedLearningPoints
        print("[AppUsageViewModel] 🔒 LOCKED \(appName):")
        print("[AppUsageViewModel]   Points being returned: \(pointsToReturn)")
        print("[AppUsageViewModel]   Total Earned: \(earnedTotal) points")
        print("[AppUsageViewModel]   Reserved before lock: \(reservedBefore) points")
        print("[AppUsageViewModel]   Reserved after lock: \(reservedAfter) points")
        print("[AppUsageViewModel]   Available after lock: \(availableLearningPoints) points (\(earnedTotal) - \(reservedAfter))")
        #endif
    }

    /// Consume reserved points for a reward app based on usage time
    /// Formula: Reserved Points = Redeemed Points - Consumed Points
    /// Consumed points are permanently spent and tracked separately
    func consumeReservedPoints(token: ApplicationToken, usageSeconds: TimeInterval) {
        guard var unlockedApp = unlockedRewardApps[token] else {
            return
        }

        let usageMinutes = Int(usageSeconds / 60)
        let pointsToConsume = usageMinutes * unlockedApp.pointsPerMinute
        let previousReserved = unlockedApp.reservedPoints

        // Reduce reserved points
        unlockedApp.reservedPoints = max(0, unlockedApp.reservedPoints - pointsToConsume)

        // Track consumed points globally (these are permanently spent)
        if !unlockedApp.isChallengeReward {
            totalConsumedPoints += pointsToConsume
        }

        // If expired, auto-lock the app
        if unlockedApp.isExpired {
            let usedMinutes = unlockedApp.pointsPerMinute > 0
                ? (previousReserved + pointsToConsume) / unlockedApp.pointsPerMinute
                : 0

            BlockingReasonService.shared.setRewardTimeExpiredBlocking(
                token: token,
                usedMinutes: usedMinutes
            )

            unlockedRewardApps.removeValue(forKey: token)
            service.blockRewardApps(tokens: [token])
        } else {
            unlockedRewardApps[token] = unlockedApp
        }

        persistUnlockedApps()
    }

    /// Persist unlocked apps and consumed points to UserDefaults
    private func persistUnlockedApps() {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else { return }

        // Convert to array for encoding
        let appsArray = Array(unlockedRewardApps.values)

        if let encoded = try? JSONEncoder().encode(appsArray) {
            defaults.set(encoded, forKey: "unlockedRewardApps")

            // Also persist total consumed points
            defaults.set(totalConsumedPoints, forKey: "totalConsumedPoints")

            defaults.synchronize()

            #if DEBUG
            print("[AppUsageViewModel] 💾 Persisted \(appsArray.count) unlocked apps")
            print("[AppUsageViewModel] 💾 Persisted \(totalConsumedPoints) consumed points")
            #endif
        }

        // EXTENSION-SAFE PERSISTENCE: Persist data that extension can read without ApplicationToken
        // This enables the extension to block reward apps when time expires (even when main app is not running)
        persistUnlockedAppsForExtension(defaults: defaults)
    }

    /// Persist unlocked apps in extension-safe format (without ApplicationToken which requires special decoding)
    /// The extension uses this to track and block reward apps when time expires
    private func persistUnlockedAppsForExtension(defaults: UserDefaults) {
        // Create minimal structs that extension can decode
        var extUnlockedApps: [[String: Any]] = []
        var tokenDataMap: [String: Data] = [:]

        for (token, app) in unlockedRewardApps {
            let tokenHash = service.usagePersistence.tokenHash(for: token)

            // Minimal app data for extension
            let appData: [String: Any] = [
                "tokenHash": tokenHash,
                "logicalID": app.id,
                "reservedPoints": app.reservedPoints,
                "pointsPerMinute": app.pointsPerMinute,
                "unlockedAt": app.unlockedAt.timeIntervalSince1970,
                "isChallengeReward": app.isChallengeReward
            ]
            extUnlockedApps.append(appData)

            // Serialize token for extension to use when blocking
            if let tokenData = try? PropertyListEncoder().encode(token) {
                tokenDataMap[tokenHash] = tokenData
            }
        }

        // Persist extension-safe unlocked apps
        if let extData = try? JSONSerialization.data(withJSONObject: extUnlockedApps) {
            defaults.set(extData, forKey: "ext_unlockedRewardApps")
        }

        // Persist token data map (tokenHash -> serialized token)
        if let tokenMapData = try? JSONEncoder().encode(tokenDataMap) {
            defaults.set(tokenMapData, forKey: "ext_rewardTokenData")
        }

        #if DEBUG
        print("[AppUsageViewModel] 💾 Persisted \(extUnlockedApps.count) unlocked apps for extension")
        #endif
    }

    /// Load unlocked apps and consumed points from UserDefaults
    private func loadUnlockedApps() {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else { return }

        // Load consumed points
        totalConsumedPoints = defaults.integer(forKey: "totalConsumedPoints")

        // Load unlocked apps
        if let data = defaults.data(forKey: "unlockedRewardApps"),
           let appsArray = try? JSONDecoder().decode([UnlockedRewardApp].self, from: data) {

            // Re-match tokens from current masterSelection using stable token hash
            for app in appsArray {
                // Match using stable SHA-256 token hash instead of unstable hashValue
                if let matchedToken = masterSelection.applicationTokens.first(where: {
                    service.usagePersistence.tokenHash(for: $0) == app.id
                }) {
                    // Create new instance with matched token, preserving unlock timestamp
                    let rehydratedApp = UnlockedRewardApp(
                        token: matchedToken,
                        tokenHash: app.id,  // Use the stored stable hash
                        reservedPoints: app.reservedPoints,
                        pointsPerMinute: app.pointsPerMinute,
                        unlockedAt: app.unlockedAt,
                        isChallengeReward: app.isChallengeReward
                    )
                    unlockedRewardApps[matchedToken] = rehydratedApp
                }
            }

            #if DEBUG
            print("[AppUsageViewModel] 📂 Loaded \(unlockedRewardApps.count) unlocked apps from persistence")
            print("[AppUsageViewModel] 📂 Loaded \(totalConsumedPoints) consumed points from persistence")
            #endif
        }
    }

    // MARK: - ManagedSettings Testing Methods

    /// Test blocking reward apps
    func testBlockRewardApps() {
        #if DEBUG
        print("[AppUsageViewModel] TEST: Blocking reward apps")
        #endif

        // Get all tokens assigned to "Reward" category
        let rewardTokens = categoryAssignments.filter { $0.value == AppUsage.AppCategory.reward }.map { $0.key }

        if rewardTokens.isEmpty {
            errorMessage = "No reward apps assigned. Please assign some apps to 'Reward' category first."
            #if DEBUG
            print("[AppUsageViewModel] ❌ Cannot block - no reward apps assigned")
            #endif
            return
        }

        #if DEBUG
        print("[AppUsageViewModel] Blocking \(rewardTokens.count) reward apps:")
        for (token, category) in categoryAssignments where category == AppUsage.AppCategory.reward {
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

        let rewardTokens = categoryAssignments.filter { $0.value == AppUsage.AppCategory.reward }.map { $0.key }

        if rewardTokens.isEmpty {
            errorMessage = "No reward apps assigned."
            #if DEBUG
            print("[AppUsageViewModel] ❌ Cannot unblock - no reward apps assigned")
            #endif
            return
        }

        #if DEBUG
        print("[AppUsageViewModel] Unblocking \(rewardTokens.count) reward apps:")
        for (token, category) in categoryAssignments where category == AppUsage.AppCategory.reward {
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

    // BF-1 FIX: Remove observer when view model is deallocated
    deinit {
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            CFNotificationName("com.screentimerewards.rewardAppUsed" as CFString),
            nil
        )
    }
}

// MARK: - FamilyActivitySelection Extension for Consistent Sorting

// MARK: - Task M: Duplicate Assignment Prevention
extension AppUsageViewModel {
    private struct HashAssignmentEntry {
        let token: ApplicationToken
        let category: AppUsage.AppCategory
        let tokenHash: String
        let logicalID: String?
        let displayName: String?
    }

    private struct AssignmentGroups {
        var byHash: [String: [HashAssignmentEntry]] = [:]
        var byDisplayName: [String: [HashAssignmentEntry]] = [:]
    }

    /// Build grouped views of the assignments keyed by token hash and display name.
    private func groupedAssignments(_ assignments: [ApplicationToken: AppUsage.AppCategory]) -> AssignmentGroups {
        assignments.reduce(into: AssignmentGroups()) { result, element in
            let (token, category) = element
            let tokenHash = service.usagePersistence.tokenHash(for: token)
            let logicalID = service.getLogicalID(for: token)
            let name = displayName(for: token)
            let entry = HashAssignmentEntry(
                token: token,
                category: category,
                tokenHash: tokenHash,
                logicalID: logicalID,
                displayName: name
            )

            result.byHash[tokenHash, default: []].append(entry)
            if let name {
                result.byDisplayName[name, default: []].append(entry)
            }
        }
    }

    private func displayName(for token: ApplicationToken) -> String? {
        resolvedDisplayName(for: token)
    }

    private func makeDuplicateMessage(existingCategory: AppUsage.AppCategory,
                                      conflictingCategory: AppUsage.AppCategory,
                                      localEntries: [HashAssignmentEntry],
                                      existingEntries: [HashAssignmentEntry],
                                      displayNameOverride: String? = nil) -> String {
        let combinedEntries = localEntries + existingEntries

        if let name = displayNameOverride
            ?? combinedEntries.compactMap({ $0.displayName }).first {
            return "\"\(name)\" is already in the \(existingCategory.rawValue) list. You can't pick it in the \(conflictingCategory.rawValue) list."
        }

        if let entry = combinedEntries.first {
        return "An app (token hash: \(entry.tokenHash)) is assigned to both Learning and Reward categories. Please fix the conflict."
        }

        return "An app is assigned to both Learning and Reward categories. Please fix the conflict."
    }

    #if DEBUG
    private func debugLog(entries: [HashAssignmentEntry], context: String) {
        print("[AppUsageViewModel]   \(context) entries:")
        for entry in entries {
            let name = entry.displayName ?? "Unknown App"
            let logical = entry.logicalID ?? "nil"
            print("[AppUsageViewModel]     • name=\(name), category=\(entry.category.rawValue), tokenHash=\(entry.tokenHash), logicalID=\(logical)")
        }
    }
    #endif

    /// Check for duplicate app assignments between categories before saving
    /// Task M: Block Duplicate App Assignments Between Tabs
    private func hasDuplicateAssignments() -> Bool {
        // Clear any previous error
        duplicateAssignmentError = nil
        
        let groups = groupedAssignments(categoryAssignments)

        for (hash, entries) in groups.byHash {
            let categories = Set(entries.map { $0.category })
            guard categories.contains(AppUsage.AppCategory.learning), categories.contains(AppUsage.AppCategory.reward) else { continue }

            duplicateAssignmentError = makeDuplicateMessage(
                existingCategory: AppUsage.AppCategory.learning,
                conflictingCategory: AppUsage.AppCategory.reward,
                localEntries: [],
                existingEntries: entries
            )

            #if DEBUG
            print("[AppUsageViewModel] ❌ Duplicate assignment detected for token hash: \(hash)")
            debugLog(entries: entries, context: "Persisted hash")
            #endif

            return true
        }

        // Fallback detection using display names when hashes differ (e.g. hashValue fallback)
        for (name, entries) in groups.byDisplayName {
            let categories = Set(entries.map { $0.category })
            guard categories.contains(AppUsage.AppCategory.learning), categories.contains(AppUsage.AppCategory.reward) else { continue }

            duplicateAssignmentError = makeDuplicateMessage(
                existingCategory: AppUsage.AppCategory.learning,
                conflictingCategory: AppUsage.AppCategory.reward,
                localEntries: [],
                existingEntries: entries,
                displayNameOverride: name
            )

            #if DEBUG
            print("[AppUsageViewModel] ❌ Duplicate assignment detected by display name: \(name)")
            debugLog(entries: entries, context: "Persisted display name")
            #endif

            return true
        }

        return false
    }
    
    /// Validate assignments and handle duplicates
    /// Task M: Block Duplicate App Assignments Between Tabs
    func validateAndHandleAssignments() -> Bool {
        // Check for duplicates
        if hasDuplicateAssignments() {
            #if DEBUG
            print("[AppUsageViewModel] ⚠️ Duplicate assignments found, blocking save")
            #endif
            
            // Post notification to display error in UI
            NotificationCenter.default.post(
                name: NSNotification.Name("DuplicateAssignmentError"),
                object: duplicateAssignmentError
            )
            
            return false
        }
        
        // Clear any previous error if validation passes
        duplicateAssignmentError = nil
        return true
    }
    
    /// Task M: Enhanced validation that checks local assignments in CategoryAssignmentView
    /// Uses token hashes for reliable equality checks
    func validateLocalAssignments(_ localCategoryAssignments: [ApplicationToken: AppUsage.AppCategory]) -> Bool {
        #if DEBUG
        print("[AppUsageViewModel] 🔍 VALIDATE LOCAL ASSIGNMENTS STARTED")
        print("[AppUsageViewModel]   Local assignments count: \(localCategoryAssignments.count)")
        for (token, category) in localCategoryAssignments {
            let appName = masterSelection.applications.first { $0.token == token }?.localizedDisplayName ?? "Unknown App"
            print("[AppUsageViewModel]     Local: \(appName) (token: \(token.hashValue)) → \(category.rawValue)")
        }
        
        print("[AppUsageViewModel]   Persisted assignments count: \(categoryAssignments.count)")
        for (token, category) in categoryAssignments {
            let appName = masterSelection.applications.first { $0.token == token }?.localizedDisplayName ?? "Unknown App"
            print("[AppUsageViewModel]     Persisted: \(appName) (token: \(token.hashValue)) → \(category.rawValue)")
        }
        #endif
        
        // Clear any previous error
        duplicateAssignmentError = nil
        
        let localGroups = groupedAssignments(localCategoryAssignments)
        let existingGroups = groupedAssignments(categoryAssignments)

        #if DEBUG
        print("[AppUsageViewModel]   Hash index counts — local: \(localGroups.byHash.count), existing: \(existingGroups.byHash.count)")
        #endif

        // Detect duplicates within the sheet's working copy
        for (hash, entries) in localGroups.byHash {
            let categories = Set(entries.map { $0.category })
            guard categories.contains(AppUsage.AppCategory.learning), categories.contains(AppUsage.AppCategory.reward) else { continue }

            duplicateAssignmentError = makeDuplicateMessage(
                existingCategory: AppUsage.AppCategory.learning,
                conflictingCategory: AppUsage.AppCategory.reward,
                localEntries: entries,
                existingEntries: existingGroups.byHash[hash] ?? []
            )

            #if DEBUG
            print("[AppUsageViewModel] ❌ Duplicate assignments detected inside local sheet state for hash: \(hash)")
            debugLog(entries: entries, context: "Local hash")
            if let persisted = existingGroups.byHash[hash], !persisted.isEmpty {
                debugLog(entries: persisted, context: "Persisted hash counterpart")
            }
            #endif

            return false
        }

        // Detect conflicts between local edits and persisted assignments
        for (hash, localEntries) in localGroups.byHash {
            let localCategories = Set(localEntries.map { $0.category })
            guard !localCategories.isEmpty else { continue }

            let persistedEntries = existingGroups.byHash[hash] ?? []
            let persistedCategories = Set(persistedEntries.map { $0.category })

            if localCategories.contains(AppUsage.AppCategory.learning), persistedCategories.contains(AppUsage.AppCategory.reward) {
                duplicateAssignmentError = makeDuplicateMessage(
                    existingCategory: AppUsage.AppCategory.reward,
                    conflictingCategory: AppUsage.AppCategory.learning,
                    localEntries: localEntries,
                    existingEntries: persistedEntries
                )

                #if DEBUG
                print("[AppUsageViewModel] ❌ Cross-tab conflict detected: local learning vs persisted reward for hash: \(hash)")
                #endif

                return false
            }

            if localCategories.contains(AppUsage.AppCategory.reward), persistedCategories.contains(AppUsage.AppCategory.learning) {
                duplicateAssignmentError = makeDuplicateMessage(
                    existingCategory: AppUsage.AppCategory.learning,
                    conflictingCategory: AppUsage.AppCategory.reward,
                    localEntries: localEntries,
                    existingEntries: persistedEntries
                )

                #if DEBUG
                print("[AppUsageViewModel] ❌ Cross-tab conflict detected: local reward vs persisted learning for hash: \(hash)")
                #endif

                return false
            }
        }

        // Display name checks within the sheet
        for (name, entries) in localGroups.byDisplayName {
            let categories = Set(entries.map { $0.category })
            guard !categories.isEmpty else { continue }

            if categories.contains(AppUsage.AppCategory.learning), categories.contains(AppUsage.AppCategory.reward) {
                duplicateAssignmentError = makeDuplicateMessage(
                    existingCategory: AppUsage.AppCategory.learning,
                    conflictingCategory: AppUsage.AppCategory.reward,
                    localEntries: entries,
                    existingEntries: existingGroups.byDisplayName[name] ?? [],
                    displayNameOverride: name
                )

                #if DEBUG
                print("[AppUsageViewModel] ❌ Duplicate assignments detected inside local sheet state by display name: \(name)")
                debugLog(entries: entries, context: "Local display name")
                if let persisted = existingGroups.byDisplayName[name], !persisted.isEmpty {
                    debugLog(entries: persisted, context: "Persisted display name counterpart")
                }
                #endif

                return false
            }

            let persistedEntries = existingGroups.byDisplayName[name] ?? []
            let persistedCategories = Set(persistedEntries.map { $0.category })

            if categories.contains(AppUsage.AppCategory.learning), persistedCategories.contains(AppUsage.AppCategory.reward) {
                duplicateAssignmentError = makeDuplicateMessage(
                    existingCategory: AppUsage.AppCategory.reward,
                    conflictingCategory: AppUsage.AppCategory.learning,
                    localEntries: entries,
                    existingEntries: persistedEntries,
                    displayNameOverride: name
                )

                #if DEBUG
                print("[AppUsageViewModel] ❌ Cross-tab conflict detected by display name: \(name) (local learning vs persisted reward)")
                debugLog(entries: entries, context: "Local display name")
                debugLog(entries: persistedEntries, context: "Persisted display name counterpart")
                #endif

                return false
            }

            if categories.contains(AppUsage.AppCategory.reward), persistedCategories.contains(AppUsage.AppCategory.learning) {
                duplicateAssignmentError = makeDuplicateMessage(
                    existingCategory: AppUsage.AppCategory.learning,
                    conflictingCategory: AppUsage.AppCategory.reward,
                    localEntries: entries,
                    existingEntries: persistedEntries,
                    displayNameOverride: name
                )

                #if DEBUG
                print("[AppUsageViewModel] ❌ Cross-tab conflict detected by display name: \(name) (local reward vs persisted learning)")
                debugLog(entries: entries, context: "Local display name")
                debugLog(entries: persistedEntries, context: "Persisted display name counterpart")
                #endif

                return false
            }
        }

        #if DEBUG
        print("[AppUsageViewModel] ✅ NO DUPLICATE OR CROSS-TAB CONFLICTS DETECTED")
        #endif

        duplicateAssignmentError = nil
        return true
    }
}

private extension CategoryAssignmentView {
}

extension AppUsageViewModel {
    // Task M: Add method to handle app removal
    func removeApp(_ token: ApplicationToken) {
        #if DEBUG
        print("[AppUsageViewModel] Removing app with token: \(token.hashValue)")
        #endif
        
        // Get app information before removal for user feedback
        let appName = resolvedDisplayName(for: token) ?? "Unknown App"
        let category = categoryAssignments[token] ?? .learning
        
        // Show confirmation dialog before removal
        // In a real implementation, this would trigger a UI confirmation dialog
        #if DEBUG
        print("[AppUsageViewModel] ⚠️ CONFIRMATION REQUIRED: Removing \(appName) from \(category.rawValue) category")
        print("[AppUsageViewModel] This will:")
        print("[AppUsageViewModel]   • Clear earned points for this app")
        if category == .reward {
            print("[AppUsageViewModel]   • Remove shield/block for this app")
        }
        print("[AppUsageViewModel]   • Reset usage time to zero")
        #endif
        
        // Proceed with removal
        removeAppWithoutConfirmation(token)
    }
    
    // Task M: Add method to handle app removal without confirmation (for programmatic use)
    private func removeAppWithoutConfirmation(_ token: ApplicationToken) {
        #if DEBUG
        print("[AppUsageViewModel] Removing app without confirmation: \(token.hashValue)")
        #endif
        
        // Get the category before removal
        let category = categoryAssignments[token] ?? .learning
        let appName = resolvedDisplayName(for: token) ?? "Unknown App"
        
        // 1. Drop reward shields immediately when apps leave the reward category
        if category == .reward {
            #if DEBUG
            print("[AppUsageViewModel] Removing shield for reward app: \(appName)")
            #endif
            service.unblockRewardApps(tokens: [token])
        }
        
        // 2. Remove the app from category assignments
        categoryAssignments.removeValue(forKey: token)
        
        // 3. Remove reward points assignment
        rewardPoints.removeValue(forKey: token)
        
        // 4. Reset usage time and points when re-adding an app
        // Remove the app usage data so it starts fresh when re-added
        if let logicalID = service.getLogicalID(for: token) {
            #if DEBUG
            print("[AppUsageViewModel] Resetting usage data for app: \(appName) (logicalID: \(logicalID))")
            #endif
            
            // Remove from service's appUsages
            service.resetUsageData(for: logicalID)
            
            // Delete the persisted data for this app instead of re-saving it
            service.usagePersistence.deleteApp(logicalID: logicalID)
        }
        
        // 5. Update all selection sources to remove this token
        // Remove from familySelection tokens
        familySelection.applicationTokens.remove(token)
        
        // Remove from masterSelection tokens
        masterSelection.applicationTokens.remove(token)
        
        // Remove from pendingSelection if present
        pendingSelection.applicationTokens.remove(token)
        
        // PRUNING FIX: Also remove the Application objects to prevent orphaned objects
        // This is critical to prevent FamilyControls.ActivityPickerRemoteViewError
        if familySelection.applications.first(where: { $0.token == token }) != nil {
            familySelection.applicationTokens.remove(token)
            // Note: We can't directly modify the applications set, but removing the token
            // will cause the framework to handle the applications collection correctly
        }
        
        if masterSelection.applications.first(where: { $0.token == token }) != nil {
            masterSelection.applicationTokens.remove(token)
            // Note: We can't directly modify the applications set, but removing the token
            // will cause the framework to handle the applications collection correctly
        }
        
        if pendingSelection.applications.first(where: { $0.token == token }) != nil {
            pendingSelection.applicationTokens.remove(token)
            // Note: We can't directly modify the applications set, but removing the token
            // will cause the framework to handle the applications collection correctly
        }
        
        // 6. Update sorted applications and snapshots
        updateSortedApplications()
        
        // 7. Reconfigure monitoring to reflect the removal
        configureMonitoring()
        
        // REHYDRATION FIX: Reset picker state and restore full selection
        resetPickerState()
        
        #if DEBUG
        print("[AppUsageViewModel] ✅ App removal completed for: \(appName)")
        #endif
    }
    
    // FIX: Add method to reset picker state after app removal
    /// Reset the picker state to prevent FamilyControls.ActivityPickerRemoteViewError
    /// This error typically occurs when the picker's internal state becomes inconsistent
    /// after selection changes, especially after app removals
    private func resetPickerState() {
        #if DEBUG
        print("[AppUsageViewModel] 🔁 Resetting picker state to prevent ActivityPickerRemoteViewError")
        #endif
        
        // Reset all picker-related state
        isFamilyPickerPresented = false
        isCategoryAssignmentPresented = false
        activePickerContext = nil
        pendingSelection = FamilyActivitySelection(includeEntireCategory: true)
        shouldUsePendingSelectionForSheet = false
        shouldPresentAssignmentAfterPickerDismiss = false
        
        // Clear any picker errors
        pickerError = nil
        pickerLoadingTimeout = false
        pickerRetryCount = 0
        cancelPickerTimeout()
        
        // REHYDRATION FIX: Restore familySelection to full merged selection
        // Set familySelection = masterSelection so everyday UI and future picker launches 
        // start from the full, consistent selection instead of the context-specific subset
        familySelection = masterSelection
        
        #if DEBUG
        print("[AppUsageViewModel] ✅ Picker state reset completed")
        #endif
    }
    
    /// Reset picker state specifically for new presentation to prevent ActivityPickerRemoteViewError
    private func resetPickerStateForNewPresentation() {
        #if DEBUG
        print("[AppUsageViewModel] 🔁 Resetting picker state for new presentation")
        #endif

        // Mark as preparing (prevents onChange handlers from firing)
        isPreparing = true

        // CRITICAL: Only reset if picker is NOT already being presented
        // This prevents the flicker caused by false→true toggle
        if isFamilyPickerPresented {
            #if DEBUG
            print("[AppUsageViewModel] ⚠️ Picker already presented - skipping reset to prevent flicker")
            #endif

            // Clear preparing flag and return early
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.isPreparing = false
            }
            return
        }

        // Set flag to prevent snapshot updates during reset
        isResettingPickerState = true

        // Reset other state (but DON'T toggle isFamilyPickerPresented false→true)
        isCategoryAssignmentPresented = false
        shouldPresentAssignmentAfterPickerDismiss = false
        shouldUsePendingSelectionForSheet = false
        activePickerContext = nil

        // Clear errors
        pickerError = nil
        pickerLoadingTimeout = false
        pickerRetryCount = 0
        cancelPickerTimeout()

        // Clear preparing flag after brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.isPreparing = false
            self.isResettingPickerState = false
        }

        #if DEBUG
        print("[AppUsageViewModel] ✅ Picker state reset completed (no flicker)")
        #endif
    }
    
    // Task M: Add method to check if an app can be safely removed
    func canRemoveApp(_ token: ApplicationToken) -> Bool {
        // Check if the app is currently assigned to any category
        return categoryAssignments[token] != nil
    }
    
    // Task M: Add method to get removal warning message
    func getRemovalWarningMessage(for token: ApplicationToken) -> String {
        guard let category = categoryAssignments[token] else {
            return "Are you sure you want to remove this app?"
        }
        
        let appName = resolvedDisplayName(for: token) ?? "Unknown App"
        
        if category == .reward {
            return "Removing \"\(appName)\" will:\n• Clear all earned points for this app\n• Remove the shield/block for this app\n• Reset usage time to zero\n\nDo you want to continue?"
        } else {
            return "Removing \"\(appName)\" will:\n• Clear all earned points for this app\n• Reset usage time to zero\n\nDo you want to continue?"
        }
    }
    
    // MARK: - Chart Data Helpers

    /// Returns aggregated daily usage for a category over the last N days
    /// - Parameters:
    ///   - category: The app category (learning or reward)
    ///   - days: Number of days to include (default 7)
    /// - Returns: Dictionary of date -> total minutes for that day
    func getDailyUsageForCategory(_ category: AppUsage.AppCategory, lastDays days: Int = 7) -> [Date: Int] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let startDate = calendar.date(byAdding: .day, value: -(days - 1), to: today)!

        // Initialize all dates with 0 minutes
        var dailyUsage: [Date: Int] = [:]
        for dayOffset in 0..<days {
            if let date = calendar.date(byAdding: .day, value: dayOffset, to: startDate) {
                dailyUsage[date] = 0
            }
        }

        // Get all apps in this category
        let categoryApps = appUsages.filter { $0.category == category }

        // Aggregate usage from all apps
        for app in categoryApps {
            // Get daily history for this app
            let history = service.getDailyHistory(for: app.bundleIdentifier)

            // Add each day's usage to the total
            for daySummary in history {
                let dayStart = calendar.startOfDay(for: daySummary.date)
                if dayStart >= startDate && dayStart <= today {
                    let minutes = daySummary.seconds / 60
                    dailyUsage[dayStart, default: 0] += minutes
                }
            }
        }

        // Add today's usage (not yet in history)
        let todayMinutes = Int((category == .learning ? learningTime : rewardTime) / 60)
        dailyUsage[today] = todayMinutes

        return dailyUsage
    }

    /// Returns sorted array of daily usage data for charting
    /// - Parameters:
    ///   - category: The app category
    ///   - days: Number of days to include
    /// - Returns: Array of (date, minutes) tuples sorted by date
    func getChartDataForCategory(_ category: AppUsage.AppCategory, lastDays days: Int = 7) -> [(date: Date, minutes: Int)] {
        let dailyUsage = getDailyUsageForCategory(category, lastDays: days)
        return dailyUsage
            .sorted { $0.key < $1.key }
            .map { (date: $0.key, minutes: $0.value) }
    }
}
