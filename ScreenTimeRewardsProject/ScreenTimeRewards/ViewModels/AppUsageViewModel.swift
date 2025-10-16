import Foundation
import Combine
import FamilyControls
import ManagedSettings

/// View model to manage app usage data for the UI
class AppUsageViewModel: ObservableObject {
    @Published var appUsages: [AppUsage] = []
    @Published var isMonitoring = false
    @Published var educationalTime: TimeInterval = 0
    @Published var entertainmentTime: TimeInterval = 0
    @Published var errorMessage: String?
    @Published var familySelection: FamilyActivitySelection = .init()
    @Published var thresholdMinutes: [AppUsage.AppCategory: Int] = [:]
    @Published var isFamilyPickerPresented = false
    @Published var isAuthorizationGranted = false
    @Published var isCategoryAssignmentPresented = false
    @Published var categoryAssignments: [ApplicationToken: AppUsage.AppCategory] = [:]

    private let service: ScreenTimeService
    private var cancellables = Set<AnyCancellable>()
    private let defaultThresholdMinutes = 1
    private let appGroupIdentifier = "group.com.screentimerewards.shared"
    
    init(service: ScreenTimeService = .shared) {
        self.service = service
        loadCategoryAssignments()
        loadData()
        NotificationCenter.default
            .publisher(for: ScreenTimeService.usageDidChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshData()
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

    /// Save category assignments to App Group storage
    func saveCategoryAssignments() {
        guard let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            #if DEBUG
            print("[AppUsageViewModel] Failed to access App Group for saving assignments")
            #endif
            return
        }

        // Note: ApplicationToken is not directly Codable
        // We'll save a simpler representation for now
        let assignmentsDict = categoryAssignments.reduce(into: [String: String]()) { result, entry in
            // Use token hash as key (not perfect but works for session)
            let tokenKey = String(entry.key.hashValue)
            result[tokenKey] = entry.value.rawValue
        }

        if let encoded = try? JSONEncoder().encode(assignmentsDict) {
            sharedDefaults.set(encoded, forKey: "categoryAssignments")
            sharedDefaults.synchronize()

            #if DEBUG
            print("[AppUsageViewModel] Saved \(categoryAssignments.count) category assignments")
            #endif
        }
    }

    /// Handle category assignment completion
    func onCategoryAssignmentSave() {
        #if DEBUG
        print("[AppUsageViewModel] Category assignments saved")
        for (token, category) in categoryAssignments {
            print("[AppUsageViewModel]   Token \(token.hashValue) → \(category.rawValue)")
        }
        #endif

        saveCategoryAssignments()
        configureMonitoring()
    }

    func thresholdValue(for category: AppUsage.AppCategory) -> Int {
        thresholdMinutes[category] ?? defaultThresholdMinutes
    }
    
    /// Load initial data from the service
    func loadData() {
        service.bootstrapSampleDataIfNeeded()
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
            print("[AppUsageViewModel] App: \(usage.appName), Time: \(usage.totalTime) seconds")
        }
        #endif
        updateCategoryTotals()
    }
    
    /// Update category totals using the locally cached data
    private func updateCategoryTotals() {
        let previousEducationalTime = educationalTime
        let previousEntertainmentTime = entertainmentTime
    
        educationalTime = appUsages
            .filter { $0.category == .educational }
            .reduce(0) { $0 + $1.totalTime }
        entertainmentTime = appUsages
            .filter { $0.category == .entertainment }
            .reduce(0) { $0 + $1.totalTime }
        
        #if DEBUG
        if previousEducationalTime != educationalTime || previousEntertainmentTime != entertainmentTime {
            print("[AppUsageViewModel] Updated category totals - Educational: \(educationalTime), Entertainment: \(entertainmentTime)")
        }
        #endif
    }
    
    /// Reset all data
    func resetData() {
        service.resetData()
        appUsages = []
        educationalTime = 0
        entertainmentTime = 0
        isMonitoring = false
        errorMessage = nil
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

        errorMessage = nil

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
    
#if DEBUG
/// Configure monitoring with test applications for debugging
func configureWithTestApplications() {
    #if DEBUG
    print("[AppUsageViewModel] Configuring with test applications")
    #endif
    service.configureWithTestApplications()
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

        print("[AppUsageViewModel] Selected applications with assigned categories:")
        for (index, application) in familySelection.applications.enumerated() {
            if let token = application.token {
                let category = categoryAssignments[token]?.rawValue ?? "Not assigned"
                print("[AppUsageViewModel]   \(index): Token \(token.hashValue) → \(category)")
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
            thresholds: thresholds.isEmpty ? nil : thresholds
        )
    }
    
    /// Format time interval for display
    func formatTime(_ timeInterval: TimeInterval) -> String {
        let hours = Int(timeInterval) / 3600
        let minutes = Int(timeInterval) / 60 % 60
        let seconds = Int(timeInterval) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}


