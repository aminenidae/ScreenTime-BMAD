import Foundation
import CoreFoundation
import DeviceActivity
import FamilyControls
import ManagedSettings
import CoreData

/// Service to handle Screen Time API functionality while exposing deterministic
/// state for the SwiftUI layer.
@available(iOS 16.0, *)
@MainActor
class ScreenTimeService: NSObject, ScreenTimeActivityMonitorDelegate {
    static let shared = ScreenTimeService()
    static let usageDidChangeNotification = Notification.Name("ScreenTimeService.usageDidChange")
    static let reportRefreshRequestedNotification = Notification.Name("reportRefreshRequested")
    
    enum ScreenTimeServiceError: LocalizedError {
        case authorizationDenied(Error?)
        case monitoringFailed(Error)
        
        var errorDescription: String? {
            switch self {
            case .authorizationDenied(let error):
                let fallback = "Screen Time authorization was not granted."
                return error?.localizedDescription ?? fallback
            case .monitoringFailed(let error):
                return "Unable to start monitoring: \(error.localizedDescription)"
            }
        }
    }
    
    private let deviceActivityCenter: DeviceActivityCenter
    private let activityName = DeviceActivityName("ScreenTimeTracking")
    private var appUsages: [String: AppUsage] = [:]  // Key = logicalID
    private var hasSeededSampleData = false
    private var authorizationGranted = false
    private(set) var isMonitoring = false
    private static let eventDidReachNotification = CFNotificationName(ScreenTimeNotifications.eventDidReachThreshold as CFString)
    private static let eventWillReachNotification = CFNotificationName(ScreenTimeNotifications.eventWillReachThreshold as CFString)
    private static let intervalDidStartNotification = CFNotificationName(ScreenTimeNotifications.intervalDidStart as CFString)
    private static let intervalDidEndNotification = CFNotificationName(ScreenTimeNotifications.intervalDidEnd as CFString)
    private static let intervalWillStartNotification = CFNotificationName(ScreenTimeNotifications.intervalWillStart as CFString)
    private static let intervalWillEndNotification = CFNotificationName(ScreenTimeNotifications.intervalWillEnd as CFString)

    // Extension re-arm notification - sent when extension records usage and needs threshold re-armed
    private static let extensionUsageRecordedNotification = CFNotificationName("com.screentimerewards.usageRecorded" as CFString)

    // App Group identifier - must match extension
    private let appGroupIdentifier = "group.com.screentimerewards.shared"

    // Shared persistence helper for logical ID-based storage
    private(set) var usagePersistence = UsagePersistence()

    // Configuration
    private let sessionAggregationWindowSeconds: TimeInterval = 300  // 5 minutes

    // MARK: - App Name Extraction Helpers

    /// Common app bundle ID mappings for better display names
    private let commonAppBundleIDs: [String: String] = [
        "com.apple.mobilesafari": "Safari",
        "com.apple.MobileSMS": "Messages",
        "com.apple.camera": "Camera",
        "com.apple.mobilemail": "Mail",
        "com.apple.Music": "Music",
        "com.apple.tv": "TV",
        "com.apple.Videos": "Videos",
        "com.apple.AppStore": "App Store",
        "com.apple.Preferences": "Settings",
        "com.apple.calculator": "Calculator",
        "com.apple.weather": "Weather",
        "com.apple.podcasts": "Podcasts",
        "com.apple.books": "Books",
        "com.apple.facetime": "FaceTime",
        "com.apple.Passbook": "Wallet",
        "com.apple.Compass": "Compass",
        "com.apple.Maps": "Maps",
        "com.apple.Health": "Health",
        "com.apple.Photos": "Photos",
        "com.apple.VoiceMemos": "Voice Memos",
        "com.apple.reminders": "Reminders",
        "com.apple.Notes": "Notes",
        "com.apple.Stocks": "Stocks",
        "com.apple.Translate": "Translate"
    ]

    /// Extract a human-readable app name from a bundle identifier
    /// - Parameter bundleIdentifier: The bundle identifier to process
    /// - Returns: A human-readable app name or nil if extraction fails
    private func extractAppName(from bundleIdentifier: String) -> String? {
        // Check lookup table first for common apps
        if let knownName = commonAppBundleIDs[bundleIdentifier] {
            return knownName
        }

        // Fallback: extract from bundle ID
        let components = bundleIdentifier.split(separator: ".")
        guard let lastComponent = components.last else { return nil }
        
        // Convert to string and capitalize first letter
        let name = String(lastComponent)
        if name.isEmpty { return nil }
        
        // Handle special cases
        switch name.lowercased() {
        case "mobilesafari": return "Safari"
        case "mobilemail": return "Mail"
        case "cal": return "Calendar"
        default:
            // Capitalize first letter and return
            return name.prefix(1).uppercased() + name.dropFirst()
        }
    }

    private struct MonitoredApplication {
        let token: ManagedSettings.ApplicationToken  // Required for monitoring
        let logicalID: String  // Stable identifier (bundleID or UUID)
        let displayName: String
        let category: AppUsage.AppCategory
        let rewardPoints: Int
        let bundleIdentifier: String?  // Optional - may be nil for privacy
    }


    private struct MonitoredEvent {
        let name: DeviceActivityEvent.Name
        let category: AppUsage.AppCategory
        var threshold: DateComponents  // Mutable for re-arm mechanism
        let applications: [MonitoredApplication]

        func deviceActivityEvent() -> DeviceActivityEvent {
            // Create DeviceActivityEvent using application tokens
            let tokens = applications.map { $0.token }
            #if DEBUG
            print("[ScreenTimeService] Creating DeviceActivityEvent with \(tokens.count) tokens")
            for (index, app) in applications.enumerated() {
                print("[ScreenTimeService]   App \(index): \(app.displayName) (Bundle ID: \(app.bundleIdentifier ?? "nil"))")
            }
            #endif

            return DeviceActivityEvent(
                applications: Set(tokens),
                threshold: threshold
            )
        }
    }

    private let activityMonitor = ScreenTimeActivityMonitor()
    // Use 1-minute threshold with deduplication guard to prevent cascades
    // Cascade prevention: no monitoring restarts + 5-second dedup window
    private let defaultThreshold = DateComponents(minute: 1)
    private var monitoredEvents: [DeviceActivityEvent.Name: MonitoredEvent] = [:]

    // MARK: - Report-based tracking (DISABLED - doesn't work in background)
    // DeviceActivityReport is a UI-only view extension, won't update in background
    // Keeping report snapshot reconciliation as backup/validation only

    // MARK: - Snapshot reconciliation safeguards
    /// Track last processed snapshot to prevent duplicate applications
    private var lastProcessedSnapshot: [String: (timestamp: TimeInterval, seconds: Int)] = [:]
    /// Track when each app last received a threshold event (for sanity checks)
    private var lastThresholdTime: [String: Date] = [:]
    /// Configuration gate to enable/disable snapshot reconciliation
    private var enableSnapshotReconciliation: Bool = true

    // MARK: - Phantom event protection
    /// Track when monitoring last started to ignore phantom events
    private var monitoringStartTime: Date?
    /// Grace period after monitoring starts to ignore all events (prevents phantom historical events)
    private let phantomEventGracePeriod: TimeInterval = 30.0

    // Store category assignments and selection for sharing across ViewModels
    private(set) var categoryAssignments: [ApplicationToken: AppUsage.AppCategory] = [:]
    private(set) var rewardPointsAssignments: [ApplicationToken: Int] = [:]
    private(set) var familySelection: FamilyActivitySelection = .init(includeEntireCategory: true)

    override private init() {
        deviceActivityCenter = DeviceActivityCenter()
        super.init()
        activityMonitor.delegate = self
        registerForExtensionNotifications()
        loadPersistedAssignments()
    }

    // MARK: - Helper Methods


    // MARK: - FamilyActivitySelection Persistence

    /// Persist FamilyActivitySelection using Codable (if available) or fallback to individual token archiving
    func persistFamilySelection(_ selection: FamilyActivitySelection) {
        guard let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            #if DEBUG
            print("[ScreenTimeService] ❌ Failed to access App Group for persisting family selection")
            #endif
            return
        }

        // Try to encode using Codable first
        if let encoded = try? JSONEncoder().encode(selection) {
            sharedDefaults.set(encoded, forKey: "familySelection_persistent")
            sharedDefaults.synchronize()

            #if DEBUG
            print("[ScreenTimeService] ✅ Persisted FamilyActivitySelection to disk (Codable)")
            print("[ScreenTimeService]   Applications: \(selection.applications.count)")
            print("[ScreenTimeService]   Categories: \(selection.categories.count)")
            print("[ScreenTimeService]   Web domains: \(selection.webDomains.count)")
            #endif
            return
        }

        #if DEBUG
        print("[ScreenTimeService] ⚠️ FamilyActivitySelection is not Codable, using token archiving fallback")
        #endif

        // Fallback: Archive individual application tokens
        var archivedTokens: [Data] = []
        for application in selection.applications {
            if let token = application.token,
               let archived = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) {
                archivedTokens.append(archived)
            }
        }

        if !archivedTokens.isEmpty,
           let encoded = try? JSONEncoder().encode(archivedTokens) {
            sharedDefaults.set(encoded, forKey: "familySelection_tokens_persistent")
            sharedDefaults.synchronize()

            #if DEBUG
            print("[ScreenTimeService] ✅ Persisted \(archivedTokens.count) application tokens to disk")
            #endif
        } else {
            #if DEBUG
            print("[ScreenTimeService] ❌ Failed to persist family selection")
            #endif
        }
    }

    /// Restore FamilyActivitySelection from persistent storage
    func restoreFamilySelection() -> FamilyActivitySelection {
        guard let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            #if DEBUG
            print("[ScreenTimeService] ⓘ No shared defaults available")
            #endif
            return FamilyActivitySelection(includeEntireCategory: true)
        }

        // Try to decode using Codable first
        if let data = sharedDefaults.data(forKey: "familySelection_persistent"),
           let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) {
            #if DEBUG
            print("[ScreenTimeService] ✅ Restored FamilyActivitySelection from disk (Codable)")
            print("[ScreenTimeService]   Applications: \(selection.applications.count)")
            print("[ScreenTimeService]   Categories: \(selection.categories.count)")
            print("[ScreenTimeService]   Web domains: \(selection.webDomains.count)")
            #endif
            return selection
        }

        #if DEBUG
        print("[ScreenTimeService] ⓘ No Codable FamilyActivitySelection found, trying token restoration")
        print("[ScreenTimeService] ⚠️ WARNING: Cannot fully restore FamilyActivitySelection - user must reselect apps")
        print("[ScreenTimeService] This is an Apple framework limitation: FamilyActivitySelection cannot be reconstructed programmatically")
        #endif

        return FamilyActivitySelection(includeEntireCategory: true)
    }


    /// Load persisted assignments from disk on init
    private func loadPersistedAssignments() {
        #if DEBUG
        print("[ScreenTimeService] 🔄 Loading persisted data using bundleID-based persistence...")
        #endif

        // Load all persisted apps from shared storage
        let persistedApps = usagePersistence.loadAllApps()

        // Convert to AppUsage dictionary
        self.appUsages = persistedApps.reduce(into: [:]) { result, entry in
            let (logicalID, persisted) = entry
            result[logicalID] = appUsage(from: persisted)
        }

        #if DEBUG
        print("[ScreenTimeService] ✅ Loaded \(appUsages.count) apps from persistence")
        for (logicalID, usage) in appUsages {
            // Also show todaySeconds and todayPoints from persistence
            if let persisted = persistedApps[logicalID] {
                print("[ScreenTimeService]   - \(usage.appName) (\(logicalID)):")
                print("[ScreenTimeService]       Total: \(usage.totalTime)s, \(usage.earnedRewardPoints)pts")
                print("[ScreenTimeService]       Today: \(persisted.todaySeconds)s, \(persisted.todayPoints)pts ← Used by snapshots")
            }
        }
        usagePersistence.printDebugInfo()
        #endif

        // Load FamilyActivitySelection if available
        let restoredSelection = restoreFamilySelection()
        if !restoredSelection.applications.isEmpty {
            self.familySelection = restoredSelection

            // Rebuild categoryAssignments and rewardPointsAssignments from loaded apps
            // We need to map tokens back to their categories/points
            // FIX: Use sorted applications to ensure consistent iteration order
            let sortedApplications = restoredSelection.sortedApplications(using: usagePersistence)
            for (index, application) in sortedApplications.enumerated() {
                guard let token = application.token else { continue }

                // CRITICAL: Use same display name format as configureMonitoring!
                let displayName = application.localizedDisplayName ?? "Unknown App \(index)"

                let mapping = usagePersistence.resolveLogicalID(
                    for: token,
                    bundleIdentifier: application.bundleIdentifier,
                    displayName: displayName
                )
                let logicalID = mapping.logicalID

                // Restore assignments from persisted app data (category & points now in PersistedApp!)
                if let persistedApp = persistedApps[logicalID],
                   let category = AppUsage.AppCategory(rawValue: persistedApp.category) {
                    categoryAssignments[token] = category
                    rewardPointsAssignments[token] = persistedApp.rewardPoints

                    #if DEBUG
                    print("[ScreenTimeService]   ✅ Restored \(persistedApp.displayName): \(category.rawValue), \(persistedApp.rewardPoints)pts")
                    #endif
                }
            }

            #if DEBUG
            print("[ScreenTimeService] ✅ Rebuilt token mappings:")
            print("[ScreenTimeService]   Category assignments: \(categoryAssignments.count)")
            print("[ScreenTimeService]   Reward points: \(rewardPointsAssignments.count)")
            #endif

            // Reconfigure monitoring with restored data (rebuilds monitoredEvents)
            #if DEBUG
            print("[ScreenTimeService] 🔄 Reconfiguring monitoring with restored data...")
            #endif

            configureMonitoring(
                with: restoredSelection,
                categoryAssignments: categoryAssignments,
                rewardPoints: rewardPointsAssignments
            )

            // Check if monitoring was previously active and restart it
            if let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier),
               sharedDefaults.bool(forKey: "wasMonitoringActive") {
                #if DEBUG
                print("[ScreenTimeService] 🔄 Monitoring was previously active - restarting automatically...")
                #endif

                // Start monitoring automatically
                do {
                    try scheduleActivity()
                    isMonitoring = true

                    #if DEBUG
                    print("[ScreenTimeService] ✅ Monitoring automatically restarted after app launch")
                    #endif
                } catch {
                    // CRITICAL: Reset state on failure to prevent blocking manual start later
                    isMonitoring = false

                    #if DEBUG
                    print("[ScreenTimeService] ❌ Failed to restart monitoring: \(error)")
                    print("[ScreenTimeService] ⚠️ Reset isMonitoring to false - user must start manually")
                    #endif
                }
            } else {
                #if DEBUG
                print("[ScreenTimeService] ℹ️ Monitoring was not previously active - user must start manually")
                #endif
            }
        } else {
            #if DEBUG
            print("[ScreenTimeService] ℹ️ No persisted selection found - starting fresh")
            #endif
        }
    }
    
    // MARK: - Sample Data
    
    func bootstrapSampleDataIfNeeded() {
        guard !hasSeededSampleData else { return }
        seedSampleData()
        hasSeededSampleData = true
    }
    
    private func seedSampleData() {
        let now = Date()
        let hour: TimeInterval = 3600
        let halfHour: TimeInterval = 1800
        
        let booksSessions = [
            AppUsage.UsageSession(
                startTime: now.addingTimeInterval(-hour * 2),
                endTime: now.addingTimeInterval(-hour)
            )
        ]
        let calculatorSessions = [
            AppUsage.UsageSession(
                startTime: now.addingTimeInterval(-hour * 6),
                endTime: now.addingTimeInterval(-hour * 6 + 600)
            )
        ]
        let musicSessions = [
            AppUsage.UsageSession(
                startTime: now.addingTimeInterval(-halfHour * 2),
                endTime: now.addingTimeInterval(-halfHour)
            )
        ]
        
        let books = AppUsage(
            bundleIdentifier: "com.apple.books",
            appName: "Books",
            category: .learning,
            totalTime: hour,
            sessions: booksSessions,
            firstAccess: now.addingTimeInterval(-86400),
            lastAccess: now.addingTimeInterval(-hour),
            rewardPoints: 20,
            earnedRewardPoints: Int(hour / 60) * 20  // 60 min * 20 pts/min = 1200
        )
        let calculator = AppUsage(
            bundleIdentifier: "com.apple.calculator",
            appName: "Calculator",
            category: .learning,
            totalTime: 600,
            sessions: calculatorSessions,
            firstAccess: now.addingTimeInterval(-172800),
            lastAccess: now.addingTimeInterval(-hour * 6 + 600),
            rewardPoints: 20,
            earnedRewardPoints: Int(600 / 60) * 20  // 10 min * 20 pts/min = 200
        )
        let music = AppUsage(
            bundleIdentifier: "com.apple.Music",
            appName: "Music",
            category: .reward,
            totalTime: halfHour,
            sessions: musicSessions,
            firstAccess: now.addingTimeInterval(-432000),
            lastAccess: now.addingTimeInterval(-halfHour),
            rewardPoints: 10,
            earnedRewardPoints: Int(halfHour / 60) * 10  // 30 min * 10 pts/min = 300
        )
        
        appUsages = [
            books.bundleIdentifier: books,
            calculator.bundleIdentifier: calculator,
            music.bundleIdentifier: music
        ]
    }

    private func categorizeApp(bundleIdentifier: String) -> AppUsage.AppCategory {
        #if DEBUG
        print("[ScreenTimeService] Categorizing app with bundle ID: \(bundleIdentifier)")
        #endif
        
        if bundleIdentifier.contains("education") || bundleIdentifier.contains("book") || bundleIdentifier.contains("learn") || bundleIdentifier.contains("calculator") {
            #if DEBUG
            print("[ScreenTimeService] Categorized as learning")
            #endif
            return .learning
        } else {
            #if DEBUG
            print("[ScreenTimeService] Categorized as reward")
            #endif
            return .reward
        }
    }

    /// Configure monitoring using a user-selected family activity selection.
    /// - Parameters:
    ///   - selection: The selection of applications/categories chosen by the parent.
    ///   - categoryAssignments: User-assigned categories for each app token.
    ///   - rewardPoints: User-assigned reward points for each app token.
    ///   - thresholds: Optional per-category thresholds that dictate when events fire.
    func configureMonitoring(
        with selection: FamilyActivitySelection,
        categoryAssignments: [ApplicationToken: AppUsage.AppCategory] = [:],
        rewardPoints: [ApplicationToken: Int] = [:],
        thresholds: [AppUsage.AppCategory: DateComponents]? = nil
    ) {
        // Store for sharing across ViewModels
        self.familySelection = selection
        self.categoryAssignments = categoryAssignments
        self.rewardPointsAssignments = rewardPoints

        #if DEBUG
        print("[ScreenTimeService] Configuring monitoring with \(selection.applications.count) applications")
        print("[ScreenTimeService] Storing \(categoryAssignments.count) category assignments and \(rewardPoints.count) reward points")
        print("[ScreenTimeService] Selection details:")
        print("[ScreenTimeService]   Applications count: \(selection.applications.count)")
        print("[ScreenTimeService]   Categories count: \(selection.categories.count)")
        print("[ScreenTimeService]   WebDomains count: \(selection.webDomains.count)")
        #endif
    
        // Log detailed information about each selected application
        // FIX: Use sorted applications to ensure consistent iteration order
        let sortedApplications = selection.sortedApplications(using: usagePersistence)
        for (index, application) in sortedApplications.enumerated() {
            #if DEBUG
            print("[ScreenTimeService]   Application \(index):")
            print("[ScreenTimeService]     Localized display name: \(application.localizedDisplayName ?? "nil")")
            print("[ScreenTimeService]     Bundle identifier: \(application.bundleIdentifier ?? "nil")")
            print("[ScreenTimeService]     Token: \(application.token != nil ? "Available" : "nil")")
            print("[ScreenTimeService]     Has token: \(application.token != nil)")
            #endif
        }
    
        let providedThresholds = thresholds ?? [:]

        var groupedApplications: [AppUsage.AppCategory: [MonitoredApplication]] = [:]

        // FIX: Use sorted applications to ensure consistent iteration order
        for (index, application) in sortedApplications.enumerated() {
            // Token is required for monitoring - skip apps without tokens
            guard let token = application.token else {
                #if DEBUG
                print("[ScreenTimeService] ⚠️ Skipping app without token at index \(index)")
                #endif
                continue
            }

            let displayName: String
            if let localizedName = application.localizedDisplayName {
                displayName = localizedName
            } else if let bundleId = application.bundleIdentifier, !bundleId.isEmpty {
                displayName = extractAppName(from: bundleId) ?? "Unknown App \(index)"
            } else {
                displayName = "Unknown App \(index)"
            }
            let bundleIdentifier = application.bundleIdentifier

            // Use user-assigned category if available, otherwise try auto-categorization
            let category: AppUsage.AppCategory
            if let assignedCategory = categoryAssignments[token] {
                category = assignedCategory
                #if DEBUG
                print("[ScreenTimeService] Processing application: \(displayName)")
                print("[ScreenTimeService]   Display Name: \(displayName)")
                print("[ScreenTimeService]   Bundle ID: \(bundleIdentifier ?? "nil (this is normal)")")
                print("[ScreenTimeService]   Token: Available")
                print("[ScreenTimeService]   Category: \(category.rawValue) (user-assigned ✓)")
                #endif
            } else {
                // Fallback: auto-categorize by bundle ID or display name
                if let bundleId = bundleIdentifier, !bundleId.isEmpty {
                    category = categorizeApp(bundleIdentifier: bundleId)
                } else {
                    category = categorizeApp(bundleIdentifier: displayName.lowercased())
                }
                #if DEBUG
                print("[ScreenTimeService] Processing application: \(displayName)")
                print("[ScreenTimeService]   Display Name: \(displayName)")
                print("[ScreenTimeService]   Bundle ID: \(bundleIdentifier ?? "nil (this is normal)")")
                print("[ScreenTimeService]   Token: Available")
                print("[ScreenTimeService]   Category: \(category.rawValue) (auto-categorized)")
                print("[ScreenTimeService]   ⚠️ No user assignment - using auto-categorization")
                #endif
            }
            
            // Use user-assigned reward points if available, otherwise use defaults
            let points: Int
            if let assignedPoints = rewardPoints[token] {
                points = assignedPoints
                #if DEBUG
                print("[ScreenTimeService]   Reward Points: \(points) (user-assigned ✓)")
                #endif
            } else {
                // Use default points based on category
                points = getDefaultRewardPoints(for: category)
                #if DEBUG
                print("[ScreenTimeService]   Reward Points: \(points) (default)")
                #endif
            }

            // Resolve logical ID (stable across launches) and token hash
            let mapping = usagePersistence.resolveLogicalID(
                for: token,
                bundleIdentifier: bundleIdentifier,
                displayName: displayName
            )
            let logicalID = mapping.logicalID
            let tokenArchiveHash = mapping.tokenHash

            #if DEBUG
            print("[ScreenTimeService]   Logical ID: \(logicalID)")
            print("[ScreenTimeService]   Token archive hash: \(tokenArchiveHash.prefix(20))...")
            #endif

            let monitored = MonitoredApplication(
                token: token,
                logicalID: logicalID,
                displayName: displayName,
                category: category,
                rewardPoints: points,
                bundleIdentifier: bundleIdentifier
            )
            groupedApplications[category, default: []].append(monitored)

            // Save app configuration to persistence immediately
            let existingApp = usagePersistence.app(for: logicalID)
            let now = Date()
            let persistedApp = UsagePersistence.PersistedApp(
                logicalID: logicalID,
                displayName: displayName,
                category: category.rawValue,
                rewardPoints: points,
                totalSeconds: existingApp?.totalSeconds ?? 0,
                earnedPoints: existingApp?.earnedPoints ?? 0,
                createdAt: existingApp?.createdAt ?? now,
                lastUpdated: existingApp?.lastUpdated ?? now,
                todaySeconds: existingApp?.todaySeconds ?? 0,
                todayPoints: existingApp?.todayPoints ?? 0,
                lastResetDate: existingApp?.lastResetDate,
                dailyHistory: existingApp?.dailyHistory ?? []
            )
            usagePersistence.saveApp(persistedApp)

            #if DEBUG
            if let existingApp {
                print("[ScreenTimeService]   💾 Updated app configuration (preserved total: \(existingApp.totalSeconds)s, \(existingApp.earnedPoints)pts, today: \(existingApp.todaySeconds)s, \(existingApp.todayPoints)pts)")
            } else {
                print("[ScreenTimeService]   💾 Saved app configuration to persistence")
            }
            #endif
        }

        // INSTRUMENTATION: Log service ordering before writing to persistence
        #if DEBUG
        print("[ScreenTimeService] === SERVICE ORDERING LOG ===")
        for (category, apps) in groupedApplications {
            print("[ScreenTimeService] Category: \(category.rawValue)")
            for (index, app) in apps.enumerated() {
                let totalSeconds = usagePersistence.app(for: app.logicalID)?.totalSeconds ?? 0
                print("[ScreenTimeService]   \(index): tokenHash=\(usagePersistence.tokenHash(for: app.token).prefix(20))..., logicalID=\(app.logicalID), displayName=\(app.displayName), rewardPoints=\(app.rewardPoints), totalSeconds=\(totalSeconds)")
            }
        }
        print("[ScreenTimeService] === END SERVICE ORDERING LOG ===")
        #endif
        // END INSTRUMENTATION

        #if DEBUG
        print("[ScreenTimeService] Grouped applications by category:")
        for (category, apps) in groupedApplications {
            print("[ScreenTimeService]   \(category.rawValue): \(apps.count) applications")
            for app in apps {
                print("[ScreenTimeService]     - \(app.displayName) (\(app.bundleIdentifier ?? "nil")) - \(app.rewardPoints) points")
            }
        }
        #endif

        // PRE-SET 60 MINUTE THRESHOLDS PER APP:
        // Create 60 consecutive 1-minute threshold events per app
        // Each threshold fires once when that minute is reached - NO re-arm/restart needed
        // Extension uses memory-efficient primitive key storage (not JSON parsing)
        // This avoids the bug where restarting monitoring resets iOS usage counters
        var eventIndex = 0
        monitoredEvents = groupedApplications.reduce(into: [:]) { result, entry in
            let (category, applications) = entry
            guard !applications.isEmpty else {
                #if DEBUG
                print("[ScreenTimeService] No applications in category \(category.rawValue)")
                #endif
                return
            }

            #if DEBUG
            print("[ScreenTimeService] Creating 60 threshold events for \(applications.count) \(category.rawValue) app(s)")
            #endif

            // Create 60 events per app with minute thresholds 1-60
            // Starting from existing usage + 1 to avoid re-firing already-passed thresholds
            for app in applications {
                let existingMinutes = getExistingTodayUsageMinutes(for: app.logicalID)
                let startMinute = existingMinutes + 1  // Start 1 minute ahead of current usage
                let endMinute = max(startMinute + 59, 60)  // At least 60 minutes of tracking

                #if DEBUG
                print("[ScreenTimeService]   App: \(app.displayName)")
                print("[ScreenTimeService]     Existing usage: \(existingMinutes) min")
                print("[ScreenTimeService]     Thresholds: \(startMinute) to \(endMinute) min")
                #endif

                for minuteNumber in startMinute...endMinute {
                    let eventName = DeviceActivityEvent.Name("usage.app.\(eventIndex).min.\(minuteNumber)")
                    let threshold = DateComponents(minute: minuteNumber)

                    result[eventName] = MonitoredEvent(
                        name: eventName,
                        category: category,
                        threshold: threshold,
                        applications: [app]
                    )
                }

                eventIndex += 1
            }
        }

        #if DEBUG
        let totalEvents = monitoredEvents.count
        print("[ScreenTimeService] Created \(totalEvents) total threshold events (60 per app)")
        #endif

        // Save event name → logical ID mapping for extension
        saveEventMappings()

        hasSeededSampleData = false

        // CRITICAL FIX: Always reload from persistence to get updated rewardPoints configuration
        // When user changes points/minute, we save the new config above (line 508-521)
        // but we must reload it here to ensure in-memory AppUsage uses the NEW rate
        var refreshedUsages: [String: AppUsage] = [:]
        for apps in groupedApplications.values {
            for app in apps {
                // Always reload from persistence to get the latest configuration
                if let persisted = usagePersistence.app(for: app.logicalID) {
                    refreshedUsages[app.logicalID] = appUsage(from: persisted)
                    #if DEBUG
                    print("[ScreenTimeService] Reloaded \(app.displayName): \(persisted.rewardPoints) pts/min, \(persisted.earnedPoints) earned, \(persisted.totalSeconds)s total")
                    #endif
                }
            }
        }
        appUsages = refreshedUsages
        notifyUsageChange()

        if isMonitoring {
            deviceActivityCenter.stopMonitoring([activityName])
            do {
                try scheduleActivity()
            } catch {
                #if DEBUG
                print("Failed to reschedule monitoring: \(error)")
                #endif
            }
        }
    }
    
    private func getDefaultRewardPoints(for category: AppUsage.AppCategory) -> Int {
        // Use a single default so every new app starts at 10 pts/min
        return 10
    }

    /// Get existing today's usage in minutes for an app (reads from extension's primitive keys)
    private func getExistingTodayUsageMinutes(for logicalID: String) -> Int {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else { return 0 }

        // First try extension's primitive keys
        let todayKey = "usage_\(logicalID)_today"
        let todaySeconds = defaults.integer(forKey: todayKey)
        if todaySeconds > 0 {
            return todaySeconds / 60
        }

        // Fallback to persisted data
        if let persisted = usagePersistence.app(for: logicalID) {
            return persisted.todaySeconds / 60
        }

        return 0
    }

    private func appUsage(from persisted: UsagePersistence.PersistedApp) -> AppUsage {
        let category = AppUsage.AppCategory(rawValue: persisted.category) ?? .learning

        // CRITICAL FIX: Don't create mega-session that breaks todayUsage calculation
        // OLD BUG: Created session with startTime=createdAt (days ago) and endTime=lastUpdated (today)
        // This caused todayUsage to return ENTIRE lifetime usage if lastUpdated is today
        // FIX: Use empty sessions array - sessions are only meaningful for live tracking
        // For persisted data, totalSeconds and earnedPoints are the source of truth
        return AppUsage(
            bundleIdentifier: persisted.logicalID,
            appName: persisted.displayName,
            category: category,
            totalTime: TimeInterval(persisted.totalSeconds),
            sessions: [],  // Empty - prevents todayUsage miscalculation
            firstAccess: persisted.createdAt,
            lastAccess: persisted.lastUpdated,
            rewardPoints: persisted.rewardPoints,
            earnedRewardPoints: persisted.earnedPoints
        )
    }

    /// Save event name → app info mapping for extension to use
    private func saveEventMappings() {
        guard let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            #if DEBUG
            print("[ScreenTimeService] ⚠️ Failed to save event mappings")
            #endif
            return
        }

        // Create mapping: eventName → (logicalID, rewardPoints, thresholdSeconds, incrementSeconds)
        var mappings: [String: [String: Any]] = [:]
        for (eventName, event) in monitoredEvents {
            guard let app = event.applications.first else { continue }

            let thresholdSeconds = seconds(from: event.threshold)
            // Each event records exactly 60 seconds (1 minute increments for continuous tracking)
            let incrementSeconds = 60
            mappings[eventName.rawValue] = [
                "logicalID": app.logicalID,
                "displayName": app.displayName,
                "category": app.category.rawValue,
                "rewardPoints": app.rewardPoints,
                "thresholdSeconds": Int(thresholdSeconds),
                "incrementSeconds": incrementSeconds
            ]

            // Also write primitive keys for memory-efficient extension access
            // These avoid JSON parsing in the extension (reduces memory from ~16MB to <6MB)
            sharedDefaults.set(app.logicalID, forKey: "map_\(eventName.rawValue)_id")
            sharedDefaults.set(incrementSeconds, forKey: "map_\(eventName.rawValue)_inc")
            sharedDefaults.set(Int(thresholdSeconds), forKey: "map_\(eventName.rawValue)_sec")
        }

        if let data = try? JSONSerialization.data(withJSONObject: mappings) {
            sharedDefaults.set(data, forKey: "eventMappings")
            sharedDefaults.synchronize()

            #if DEBUG
            print("[ScreenTimeService] 💾 Saved \(mappings.count) event mappings for extension (JSON + primitive keys)")
            #endif
        }
    }

    private func registerForExtensionNotifications() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        let callback: CFNotificationCallback = { _, observer, name, _, userInfo in
            guard let observer, let name else { return }
            let service = Unmanaged<ScreenTimeService>.fromOpaque(observer).takeUnretainedValue()
            service.handleDarwinNotification(name: name, userInfo: userInfo)
        }

        [Self.eventDidReachNotification,
         Self.eventWillReachNotification,
         Self.intervalDidStartNotification,
         Self.intervalDidEndNotification,
         Self.intervalWillStartNotification,
         Self.intervalWillEndNotification,
         Self.extensionUsageRecordedNotification].forEach { notification in
            CFNotificationCenterAddObserver(
                center,
                observer,
                callback,
                notification.rawValue,
                nil,
                .deliverImmediately
            )
        }
    }

    private func handleDarwinNotification(name: CFNotificationName, userInfo: CFDictionary?) {
        // Darwin notifications can't carry userInfo, read from shared UserDefaults instead
        guard let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            #if DEBUG
            print("[ScreenTimeService] ⚠️ Failed to access App Group: \(appGroupIdentifier)")
            #endif
            return
        }

        let eventRaw = sharedDefaults.string(forKey: "lastEvent")
        let activityRaw = sharedDefaults.string(forKey: "lastActivity")
        let timestamp = sharedDefaults.object(forKey: "lastEventData").flatMap { obj -> Date? in
            guard let jsonString = obj as? String,
                  let jsonData = jsonString.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let ts = dict["timestamp"] as? Double else {
                return nil
            }
            return Date(timeIntervalSince1970: ts)
        } ?? Date()

        #if DEBUG
        print("[ScreenTimeService] Received Darwin notification: \(name.rawValue)")
        print("[ScreenTimeService] Event from App Group: \(eventRaw ?? "nil")")
        print("[ScreenTimeService] Activity from App Group: \(activityRaw ?? "nil")")
        print("[ScreenTimeService] Timestamp: \(timestamp)")
        #endif

        switch name {
        case Self.eventDidReachNotification:
            if let eventRaw {
                #if DEBUG
                print("[ScreenTimeService] Handling eventDidReachThreshold for event: \(eventRaw)")
                #endif
                handleEventThresholdReached(DeviceActivityEvent.Name(eventRaw), timestamp: timestamp)
            } else {
                #if DEBUG
                print("[ScreenTimeService] ⚠️ eventDidReachThreshold received but no event data in App Group")
                #endif
            }
        case Self.eventWillReachNotification:
            if let eventRaw {
                #if DEBUG
                print("[ScreenTimeService] Handling eventWillReachThreshold for event: \(eventRaw)")
                #endif
                handleEventWillReachThresholdWarning(DeviceActivityEvent.Name(eventRaw))
            }
        case Self.intervalDidStartNotification:
            if let activityRaw {
                #if DEBUG
                print("[ScreenTimeService] Handling intervalDidStart for activity: \(activityRaw)")
                #endif
                handleIntervalDidStart(for: DeviceActivityName(activityRaw))
            }
        case Self.intervalDidEndNotification:
            if let activityRaw {
                #if DEBUG
                print("[ScreenTimeService] Handling intervalDidEnd for activity: \(activityRaw)")
                #endif
                handleIntervalDidEnd(for: DeviceActivityName(activityRaw))
            }
        case Self.intervalWillStartNotification:
            if let activityRaw {
                #if DEBUG
                print("[ScreenTimeService] Handling intervalWillStart for activity: \(activityRaw)")
                #endif
                handleIntervalWillStartWarning(for: DeviceActivityName(activityRaw))
            }
        case Self.intervalWillEndNotification:
            if let activityRaw {
                #if DEBUG
                print("[ScreenTimeService] Handling intervalWillEnd for activity: \(activityRaw)")
                #endif
                handleIntervalWillEndWarning(for: DeviceActivityName(activityRaw))
            }
        case Self.extensionUsageRecordedNotification:
            #if DEBUG
            print("[ScreenTimeService] 📥 Received usage recorded notification from extension")
            #endif
            handleExtensionUsageRecorded(defaults: sharedDefaults)
        default:
            #if DEBUG
            print("[ScreenTimeService] Unknown notification received: \(name.rawValue)")
            #endif
            break
        }
    }

    // MARK: - Extension Usage Update Handler (60 Static Thresholds)

    /// Handle usage recorded notification from extension
    /// With 60 static thresholds (1min, 2min, ... 60min), NO restart is needed!
    /// Each threshold fires once when cumulative usage reaches that minute.
    private func handleExtensionUsageRecorded(defaults: UserDefaults) {
        #if DEBUG
        print("[ScreenTimeService] 📥 Processing extension usage update...")
        #endif

        // Read updated usage data from extension's primitive keys
        readExtensionUsageData(defaults: defaults)

        // Clear any re-arm flags (legacy from old single-threshold approach)
        var updateCount = 0
        for (logicalID, _) in appUsages {
            let rearmKey = "rearm_\(logicalID)_requested"
            if defaults.bool(forKey: rearmKey) {
                // Clear the flag
                defaults.set(false, forKey: rearmKey)

                #if DEBUG
                print("[ScreenTimeService] 📊 Usage update for: \(logicalID)")
                #endif

                // Just log - NO restart with 60 static thresholds
                clearRearmFlag(for: logicalID, defaults: defaults)
                updateCount += 1
            }
        }

        defaults.synchronize()

        #if DEBUG
        print("[ScreenTimeService] ✅ Processed \(updateCount) usage updates (NO restart - 60 static thresholds)")
        #endif

        // Notify UI of usage updates
        notifyUsageChange()
    }

    /// Read usage data from extension's primitive keys
    private func readExtensionUsageData(defaults: UserDefaults) {
        for (logicalID, var usage) in appUsages {
            // Read from extension's primitive keys
            let totalKey = "usage_\(logicalID)_total"
            let todayKey = "usage_\(logicalID)_today"

            let totalSeconds = defaults.integer(forKey: totalKey)
            let todaySeconds = defaults.integer(forKey: todayKey)

            if totalSeconds > 0 || todaySeconds > 0 {
                // Update in-memory usage - totalTime is the cumulative value
                usage.totalTime = TimeInterval(totalSeconds)
                appUsages[logicalID] = usage

                #if DEBUG
                print("[ScreenTimeService] 📊 Updated \(usage.appName): total=\(totalSeconds)s, today=\(todaySeconds)s")
                #endif
            }
        }
    }

    /// Handle re-arm request - with 60 static thresholds, NO restart needed
    /// The thresholds (1min, 2min, 3min... 60min) are already pre-set
    /// We just clear the re-arm flag and log the update
    private func clearRearmFlag(for logicalID: String, defaults: UserDefaults) {
        guard let usage = appUsages[logicalID] else {
            #if DEBUG
            print("[ScreenTimeService] ⚠️ Cannot clear re-arm: app not found for \(logicalID)")
            #endif
            return
        }

        let todayKey = "usage_\(logicalID)_today"
        let currentTodaySeconds = defaults.integer(forKey: todayKey)
        let currentMinutes = currentTodaySeconds / 60

        #if DEBUG
        print("[ScreenTimeService] ✅ Usage update for \(usage.appName): \(currentMinutes) minutes recorded")
        print("[ScreenTimeService]    (60 static thresholds already set - NO restart needed)")
        #endif

        // NO restart! 60 static thresholds are already in place
        // Next threshold will fire automatically when usage reaches next minute
    }
    
    // MARK: - Authorization & Monitoring
    
    func requestPermission(completion: @escaping (Result<Void, ScreenTimeServiceError>) -> Void) {
        if authorizationGranted {
            DispatchQueue.main.async {
                completion(.success(()))
            }
            return
        }
        
        #if targetEnvironment(simulator)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.authorizationGranted = true
            completion(.success(()))
        }
        #else
        Task { [weak self] in
            do {
                // Since our minimum deployment target is iOS 16.6, we can use the async version directly
                try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
                await MainActor.run {
                    self?.authorizationGranted = true
                    completion(.success(()))
                }
            } catch {
                await MainActor.run {
                    completion(.failure(.authorizationDenied(error)))
                }
            }
        }
        #endif
    }
    
    func startMonitoring(completion: @escaping (Result<Void, ScreenTimeServiceError>) -> Void) {
        requestPermission { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                do {
                    try self.scheduleActivity()
                    self.isMonitoring = true

                    // Persist monitoring state for auto-restart on app launch
                    if let sharedDefaults = UserDefaults(suiteName: self.appGroupIdentifier) {
                        sharedDefaults.set(true, forKey: "wasMonitoringActive")
                        sharedDefaults.synchronize()
                        #if DEBUG
                        print("[ScreenTimeService] 💾 Persisted monitoring state: ACTIVE")
                        #endif
                    }

                    DispatchQueue.main.async {
                        completion(.success(()))
                    }
                } catch {
                    self.isMonitoring = false
                    DispatchQueue.main.async {
                        completion(.failure(.monitoringFailed(error)))
                    }
                }
            case .failure(let error):
                self.isMonitoring = false
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    func stopMonitoring() {
        deviceActivityCenter.stopMonitoring([activityName])
        isMonitoring = false

        // Persist monitoring state so we don't auto-restart on next launch
        if let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) {
            sharedDefaults.set(false, forKey: "wasMonitoringActive")
            sharedDefaults.synchronize()
            #if DEBUG
            print("[ScreenTimeService] 💾 Persisted monitoring state: INACTIVE")
            #endif
        }
    }

    // MARK: - REMOVED: Dynamic threshold advancement (caused cascade fires)
    // The approach of incrementing thresholds after each fire is fundamentally broken
    // because DeviceActivity thresholds are cumulative. Restarting monitoring causes
    // all thresholds < current usage to fire immediately in rapid succession.
    // Solution: Use static 24hr threshold + DeviceActivityReport for tracking.

    // MARK: - REMOVED: Event-driven restart & Report refresh timer
    // Event-driven restarts caused cascade fires - removed
    // Report refresh timer doesn't work (DeviceActivityReport is UI-only) - removed
    // Primary tracking now uses 1-min threshold events with deduplication

    // MARK: - Usage report sync helpers

    /// Ask the DeviceActivityReport extension to refresh its snapshot and notify listeners.
    func requestUsageReportRefresh() {
        NSLog("[ScreenTimeService] 📊 Requesting DeviceActivityReport refresh...")

        if let defaults = UserDefaults(suiteName: appGroupIdentifier) {
            defaults.set(Date().timeIntervalSince1970, forKey: "report_request_timestamp")
            defaults.synchronize()
        }

        NotificationCenter.default.post(name: Self.reportRefreshRequestedNotification, object: nil)
    }

    /// Read the latest snapshot written by the DeviceActivityReport extension and reconcile usage.
    func syncFromReportSnapshot() {
        // Configuration gate: allow disabling snapshot reconciliation
        guard enableSnapshotReconciliation else {
            NSLog("[ScreenTimeService] ℹ️ Snapshot reconciliation is disabled")
            return
        }

        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else {
            NSLog("[ScreenTimeService] ❌ Cannot access app group for report sync")
            return
        }

        guard let snapshot = defaults.dictionary(forKey: "report_snapshot") else {
            NSLog("[ScreenTimeService] ℹ️ No report snapshot available yet")
            return
        }

        guard let timestamp = snapshot["timestamp"] as? TimeInterval,
              let appsData = snapshot["apps"] as? [String: Int] else {
            NSLog("[ScreenTimeService] ⚠️ Invalid report snapshot format")
            return
        }

        let snapshotDate = Date(timeIntervalSince1970: timestamp)
        let age = Date().timeIntervalSince(snapshotDate)

        guard age < 60 else {
            NSLog("[ScreenTimeService] ⚠️ Report snapshot is stale (\(Int(age))s old)")
            return
        }

        NSLog("[ScreenTimeService] 📊 Processing report snapshot from \(snapshotDate) (age: \(Int(age))s) with \(appsData.count) apps")

        var didUpdateAnyApp = false
        var appliedCount = 0
        var skippedCount = 0

        for (bundleID, reportedSeconds) in appsData {
            guard let logicalID = findLogicalID(for: bundleID) else {
                NSLog("[ScreenTimeService] ⚠️ No logical ID found for bundle: \(bundleID)")
                continue
            }

            guard let persistedApp = usagePersistence.app(for: logicalID) else {
                NSLog("[ScreenTimeService] ⚠️ No persisted app found for: \(logicalID)")
                continue
            }

            let currentSeconds = persistedApp.todaySeconds

            if reportedSeconds > currentSeconds {
                let additionalSeconds = reportedSeconds - currentSeconds

                // SAFEGUARD 1: Check for duplicate snapshot processing
                if let lastProcessed = lastProcessedSnapshot[logicalID],
                   lastProcessed.timestamp == timestamp,
                   lastProcessed.seconds == reportedSeconds {
                    NSLog("[Snapshot] \(persistedApp.displayName): DUPLICATE snapshot (timestamp: \(timestamp), seconds: \(reportedSeconds)) → SKIPPED")
                    skippedCount += 1
                    continue
                }

                // SAFEGUARD 2: Check if threshold fired recently (within 90s)
                let now = Date()
                if let lastThreshold = lastThresholdTime[logicalID] {
                    let timeSinceThreshold = now.timeIntervalSince(lastThreshold)
                    if timeSinceThreshold < 90 {
                        NSLog("[Snapshot] \(persistedApp.displayName): Recent threshold \(Int(timeSinceThreshold))s ago → SKIPPED (too soon)")
                        skippedCount += 1
                        continue
                    }
                }

                // SAFEGUARD 3: Sanity check on delta size (max 90s per app)
                if additionalSeconds > 90 {
                    // Calculate elapsed time since last threshold or last update
                    var elapsedSeconds: TimeInterval = 90  // default
                    if let lastThreshold = lastThresholdTime[logicalID] {
                        elapsedSeconds = now.timeIntervalSince(lastThreshold)
                    }

                    NSLog("[Snapshot] \(persistedApp.displayName): Large delta detected")
                    NSLog("[Snapshot]   Reported: \(reportedSeconds)s, Persisted: \(currentSeconds)s, Delta: \(additionalSeconds)s")
                    NSLog("[Snapshot]   Elapsed since last threshold: \(Int(elapsedSeconds))s")

                    // SAFEGUARD 4: Clamp delta to reasonable value
                    let maxReasonableDelta = min(Int(elapsedSeconds + 90), additionalSeconds)
                    if maxReasonableDelta < additionalSeconds {
                        NSLog("[Snapshot]   → SKIPPED (delta \(additionalSeconds)s exceeds reasonable \(maxReasonableDelta)s)")
                        skippedCount += 1
                        continue
                    }
                }

                // All safeguards passed - apply the delta
                NSLog("[Snapshot] \(persistedApp.displayName): \(currentSeconds)s → \(reportedSeconds)s (+\(additionalSeconds)s) → APPLIED")

                usagePersistence.recordUsage(
                    logicalID: logicalID,
                    additionalSeconds: additionalSeconds,
                    rewardPointsPerMinute: persistedApp.rewardPoints
                )

                Task {
                    await ChallengeService.shared.updateProgressForUsage(
                        appID: logicalID,
                        duration: TimeInterval(additionalSeconds),
                        earnedPoints: max(0, (additionalSeconds / 60) * persistedApp.rewardPoints),
                        deviceID: DeviceModeManager.shared.deviceID
                    )
                }

                // Track this snapshot as processed
                lastProcessedSnapshot[logicalID] = (timestamp: timestamp, seconds: reportedSeconds)

                didUpdateAnyApp = true
                appliedCount += 1
            } else if reportedSeconds < currentSeconds {
                NSLog("[ScreenTimeService] ℹ️ Report shows less usage than persisted for \(persistedApp.displayName) (report: \(reportedSeconds)s, persisted: \(currentSeconds)s)")
            }
        }

        if didUpdateAnyApp {
            reloadAppUsagesFromPersistence()
            notifyUsageChange()
            NSLog("[ScreenTimeService] ✅ Snapshot sync complete: applied \(appliedCount), skipped \(skippedCount) - UI refreshed")
        } else {
            NSLog("[ScreenTimeService] ℹ️ Snapshot sync complete: no updates (skipped: \(skippedCount))")
        }
    }

    /// Map a bundle identifier from the report back to a logical ID in persistence.
    private func findLogicalID(for bundleID: String) -> String? {
        if usagePersistence.app(for: bundleID) != nil {
            return bundleID
        }
        return nil
    }

    /// Reload persisted usage into memory. Currently just refreshes the persistence cache.
    private func reloadAppUsagesFromPersistence() {
        _ = usagePersistence.reloadAppsFromDisk()
    }

    /// Handle day rollover: reset daily counters and refresh in-memory state.
    func handleMidnightTransition() {
        usagePersistence.resetDailyCounters()
        reloadAppUsagesFromPersistence()
        notifyUsageChange()
    }

    /// Return daily histories for all apps keyed by logical ID.
    func getDailyHistories() -> [String: [UsagePersistence.DailyUsageSummary]] {
        let apps = usagePersistence.loadAllApps()
        var histories: [String: [UsagePersistence.DailyUsageSummary]] = [:]
        for (logicalID, app) in apps {
            histories[logicalID] = app.dailyHistory
        }
        return histories
    }

    /// Return the daily history for a specific app by logical ID.
    func getDailyHistory(for logicalID: String) -> [UsagePersistence.DailyUsageSummary] {
        usagePersistence.app(for: logicalID)?.dailyHistory ?? []
    }

    /// Convenience overload: resolve history from an application token via stored mapping.
    func getDailyHistory(for token: ManagedSettings.ApplicationToken) -> [UsagePersistence.DailyUsageSummary] {
        let tokenHash = usagePersistence.tokenHash(for: token)
        if let logicalID = usagePersistence.logicalID(for: tokenHash) {
            return getDailyHistory(for: logicalID)
        }
        return []
    }

    // MARK: - Diagnostics helpers

    /// Simple restart wrapper used by diagnostics views.
    func restartMonitoring(reason: String, force: Bool = false) async {
        #if DEBUG
        print("[ScreenTimeService] ♻️ Restart requested (")
        #endif
        stopMonitoring()
        do {
            try scheduleActivity()
            isMonitoring = true
            #if DEBUG
            print("[ScreenTimeService] ✅ Restarted monitoring (")
            #endif
        } catch {
            #if DEBUG
            print("[ScreenTimeService] ❌ Failed to restart monitoring: \(error)")
            #endif
        }
    }

    /// Returns a basic extension health snapshot (placeholder values until full telemetry is wired).
    func getExtensionHealthStatus() -> ExtensionHealthStatus {
        let now = Date()
        // Placeholder: assume healthy with no gap; memory usage unknown
        return ExtensionHealthStatus(lastHeartbeat: now, heartbeatGapSeconds: 0, isHealthy: true, memoryUsageMB: 0)
    }

    /// Detect usage gaps from persisted history (placeholder: returns empty).
    func detectUsageGaps() -> [UsageGap] {
        return []
    }
    
    private func scheduleActivity() throws {
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true
        )
        
        let events = monitoredEvents.reduce(into: [DeviceActivityEvent.Name: DeviceActivityEvent]()) { result, entry in
            result[entry.key] = entry.value.deviceActivityEvent()
        }
        
        #if DEBUG
        print("[ScreenTimeService] Scheduling activity:")
        print("[ScreenTimeService]   Activity name: \(activityName.rawValue)")
        print("[ScreenTimeService]   Schedule: 00:00 - 23:59 (repeating)")
        print("[ScreenTimeService]   Events count: \(events.count)")
        
        for (name, event) in events {
            print("[ScreenTimeService]   Event: \(name.rawValue)")
            print("[ScreenTimeService]     Applications count: \(event.applications.count)")
            print("[ScreenTimeService]     Threshold: \(event.threshold)")
            
            // Log application details
            for (index, token) in event.applications.enumerated() {
                print("[ScreenTimeService]       App \(index): Token \(token)")
            }
        }
        #endif
        
        try deviceActivityCenter.startMonitoring(activityName, during: schedule, events: events)

        // Set monitoring start time for phantom event protection
        monitoringStartTime = Date()

        #if DEBUG
        print("[ScreenTimeService] Successfully started monitoring")
        print("[ScreenTimeService] 🛡️ Phantom event protection: ignoring events for \(phantomEventGracePeriod)s")
        #endif
    }
    
    // MARK: - Data Accessors
    
    func getAppUsages() -> [AppUsage] {
        Array(appUsages.values)
    }

    func getUsage(for token: ApplicationToken) -> AppUsage? {
        // Look up logical ID from token hash
        let tokenHash = usagePersistence.tokenHash(for: token)
        guard let logicalID = usagePersistence.logicalID(for: tokenHash) else {
            #if DEBUG
            print("[ScreenTimeService] ⚠️ No logical ID found for token hash: \(tokenHash.prefix(20))...")
            #endif
            return nil
        }
        return appUsages[logicalID]
    }

    func getUsageDuration(for token: ApplicationToken) -> TimeInterval {
        getUsage(for: token)?.totalTime ?? 0
    }

    func getAppUsages(by category: AppUsage.AppCategory) -> [AppUsage] {
        appUsages.values.filter { $0.category == category }
    }
    
    func getTotalTime(for category: AppUsage.AppCategory) -> TimeInterval {
        getAppUsages(by: category).reduce(0) { $0 + $1.totalTime }
    }
    
    func getTotalRewardPoints() -> Int {
        return appUsages.values.reduce(0) { $0 + $1.earnedRewardPoints }
    }
    
    func resetData() {
        appUsages.removeAll()
        hasSeededSampleData = false
        isMonitoring = false
        notifyUsageChange()
    }

    private func notifyUsageChange() {
        #if DEBUG
        print("[ScreenTimeService] Notifying usage change to observers")
        #endif
        NotificationCenter.default.post(name: Self.usageDidChangeNotification, object: nil)
    }

    // MARK: - ManagedSettings App Blocking

    // ManagedSettings store for app blocking
    private let managedSettingsStore = ManagedSettingsStore()

    // Track currently shielded (blocked) apps
    private var currentlyShielded: Set<ApplicationToken> = []

    // Track apps that should always be accessible (learning apps)
    private var alwaysAccessible: Set<ApplicationToken> = []

    /// Block reward apps (shield them)
    func blockRewardApps(tokens: Set<ApplicationToken>) {
        #if DEBUG
        print("[ScreenTimeService] 🔒 Blocking \(tokens.count) reward apps")
        print("[ScreenTimeService] Starting shield application...")
        let startTime = Date()
        #endif

        // BF-2 FIX: Change from assignment to formUnion to properly add tokens to existing set
        // Previously: currentlyShielded = tokens (which replaced the entire set)
        // Now: currentlyShielded.formUnion(tokens) (which adds tokens to existing set)
        currentlyShielded.formUnion(tokens)
        managedSettingsStore.shield.applications = currentlyShielded

        #if DEBUG
        let elapsed = Date().timeIntervalSince(startTime)
        print("[ScreenTimeService] ✅ Shield applied to \(tokens.count) apps in \(String(format: "%.2f", elapsed)) seconds")
        print("[ScreenTimeService] ⚠️  IMPORTANT: If apps are already running, user must close and reopen them")
        print("[ScreenTimeService] Shield tokens: \(tokens.map { String($0.hashValue) })")
        #endif

        // Post notification
        NotificationCenter.default.post(name: .rewardAppsBlocked, object: nil)
    }

    /// Unblock reward apps (remove shield)
    func unblockRewardApps(tokens: Set<ApplicationToken>) {
        #if DEBUG
        print("[ScreenTimeService] 🔓 Unblocking \(tokens.count) reward apps")
        print("[ScreenTimeService] Removing shields...")
        let startTime = Date()
        #endif

        // Remove from currently shielded
        currentlyShielded.subtract(tokens)

        // Update ManagedSettings
        managedSettingsStore.shield.applications = currentlyShielded

        #if DEBUG
        let elapsed = Date().timeIntervalSince(startTime)
        print("[ScreenTimeService] ✅ Shield removed from \(tokens.count) apps in \(String(format: "%.2f", elapsed)) seconds")
        print("[ScreenTimeService] Currently shielded: \(currentlyShielded.count) apps")
        print("[ScreenTimeService] ⚠️  RESEARCH FINDING: Requires app relaunch to take effect (shield staleness)")
        print("[ScreenTimeService] Unblocked tokens: \(tokens.map { String($0.hashValue) })")
        #endif

        // Post notification
        NotificationCenter.default.post(
            name: .rewardAppsUnlocked,
            object: nil,
            userInfo: ["requiresRelaunch": true, "count": tokens.count]
        )
    }

    /// Block ALL apps except learning and system apps
    func blockAllExceptLearning(learningTokens: Set<ApplicationToken>) {
        #if DEBUG
        print("[ScreenTimeService] ⚠️  Attempting to block all apps except \(learningTokens.count) learning apps")
        #endif

        alwaysAccessible = learningTokens

        // Note: ManagedSettings doesn't have a "block all except" mode
        // We can only block specific apps we know about
        #if DEBUG
        print("[ScreenTimeService] ⚠️  LIMITATION DISCOVERED:")
        print("[ScreenTimeService] ManagedSettings cannot block 'all except X'")
        print("[ScreenTimeService] Can only block explicitly specified apps")
        print("[ScreenTimeService] Workaround: Block known reward apps explicitly")
        print("[ScreenTimeService] This is a documented Apple limitation")
        #endif
    }

    /// Get current shield status
    func getShieldStatus() -> (blocked: Int, accessible: Int) {
        let status = (blocked: currentlyShielded.count, accessible: alwaysAccessible.count)

        #if DEBUG
        print("[ScreenTimeService] Shield status: \(status.blocked) blocked, \(status.accessible) accessible")
        #endif

        return status
    }

    /// Clear all shields
    func clearAllShields() {
        #if DEBUG
        print("[ScreenTimeService] 🧹 Clearing all shields...")
        let startTime = Date()
        #endif

        currentlyShielded.removeAll()
        managedSettingsStore.shield.applications = nil

        #if DEBUG
        let elapsed = Date().timeIntervalSince(startTime)
        print("[ScreenTimeService] ✅ All shields cleared in \(String(format: "%.2f", elapsed)) seconds")
        print("[ScreenTimeService] All apps should now be accessible")
        #endif

        // Post notification
        NotificationCenter.default.post(name: .allShieldsCleared, object: nil)
    }

    /// Test if app blocking is working (development only)
    func testShieldBehavior() {
        #if DEBUG
        print("[ScreenTimeService] 🧪 Running shield behavior test...")
        print("[ScreenTimeService] This will help identify shield staleness and other issues")

        let status = getShieldStatus()
        print("[ScreenTimeService] Current status: \(status.blocked) apps blocked")

        if status.blocked > 0 {
            print("[ScreenTimeService] ✅ Shields are active")
            print("[ScreenTimeService] Test: Try opening a blocked app now")
            print("[ScreenTimeService] Expected: Shield screen should appear")
        } else {
            print("[ScreenTimeService] ⚠️  No apps currently shielded")
            print("[ScreenTimeService] Run 'Block Reward Apps' first")
        }
        #endif
    }

    // MARK: - Path 2: Bundle ID Discovery (ShieldConfiguration Extension)

    /// Read bundle ID mappings discovered by ShieldConfiguration extension
    /// These are only available AFTER an app has been shielded (blocked) at least once
    func getBundleIDMappings() -> [(bundleID: String, appName: String, category: String)] {
        guard let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            #if DEBUG
            print("[ScreenTimeService] ⚠️ Failed to access App Group for bundle ID mappings")
            #endif
            return []
        }

        let categoryMappings = sharedDefaults.dictionary(forKey: "bundleIDCategoryMappings") as? [String: String] ?? [:]
        let nameMappings = sharedDefaults.dictionary(forKey: "bundleIDNameMappings") as? [String: String] ?? [:]

        #if DEBUG
        print("[ScreenTimeService] 📱 Reading bundle ID mappings from shield extension:")
        print("[ScreenTimeService] Found \(categoryMappings.count) apps discovered via shield")
        #endif

        var results: [(bundleID: String, appName: String, category: String)] = []

        for (bundleID, category) in categoryMappings {
            let appName = nameMappings[bundleID] ?? "Unknown"
            results.append((bundleID: bundleID, appName: appName, category: category))

            #if DEBUG
            print("[ScreenTimeService]   \(bundleID) → \(appName) (\(category))")
            #endif
        }

        return results
    }

    /// Get count of apps discovered via ShieldConfiguration extension
    func getDiscoveredAppsCount() -> Int {
        guard let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            return 0
        }

        let categoryMappings = sharedDefaults.dictionary(forKey: "bundleIDCategoryMappings") as? [String: String] ?? [:]
        return categoryMappings.count
    }

    /// Check if a specific bundle ID has been discovered
    func isAppDiscovered(bundleID: String) -> Bool {
        guard let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            return false
        }

        let categoryMappings = sharedDefaults.dictionary(forKey: "bundleIDCategoryMappings") as? [String: String] ?? [:]
        return categoryMappings[bundleID] != nil
    }

    /// Get auto-categorization suggestion for a bundle ID (from shield extension)
    func getAutoCategorySuggestion(for bundleID: String) -> AppUsage.AppCategory? {
        guard let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            return nil
        }

        let categoryMappings = sharedDefaults.dictionary(forKey: "bundleIDCategoryMappings") as? [String: String] ?? [:]

        guard let categoryString = categoryMappings[bundleID] else {
            return nil
        }

        return AppUsage.AppCategory(rawValue: categoryString)
    }

    /// Clear all bundle ID mappings (for testing)
    func clearBundleIDMappings() {
        guard let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            return
        }

        sharedDefaults.removeObject(forKey: "bundleIDCategoryMappings")
        sharedDefaults.removeObject(forKey: "bundleIDNameMappings")
        sharedDefaults.removeObject(forKey: "bundleIDTimestamps")

        #if DEBUG
        print("[ScreenTimeService] 🧹 Cleared all bundle ID mappings")
        #endif
    }

    private func recordUsage(for applications: [MonitoredApplication], duration: TimeInterval, endingAt endDate: Date = Date()) {
        #if DEBUG
        print("[ScreenTimeService] Recording usage for \(applications.count) applications, duration: \(duration) seconds")
        for app in applications {
            print("[ScreenTimeService] App: \(app.displayName) (Bundle ID: \(app.bundleIdentifier ?? "nil")), Category: \(app.category.rawValue), Reward Points: \(app.rewardPoints)")
        }
        #endif

        guard duration > 0 else {
            #if DEBUG
            print("[ScreenTimeService] Skipping recording - duration is 0 or negative")
            #endif
            return
        }

        // 🔒 CRITICAL FIX: Check if apps are currently blocked
        // If blocked, this is shield time (not real usage) - skip recording
        var recordedCount = 0
        var skippedCount = 0
    
        // Use a set to track logical IDs we've already processed to avoid duplicates
        var processedLogicalIDs: Set<String> = []

        for application in applications {
            // Check if app is currently shielded (blocked)
            if currentlyShielded.contains(application.token) {
                #if DEBUG
                print("[ScreenTimeService] 🛑 SKIPPING \(application.displayName) - currently blocked (shield time, not real usage)")
                #endif
                skippedCount += 1
                continue  // Skip this app - it's shield time!
            }
        
            let logicalID = application.logicalID
        
            // Skip if we've already processed this logical ID
            if processedLogicalIDs.contains(logicalID) {
                #if DEBUG
                print("[ScreenTimeService] Skipping duplicate logical ID: \(logicalID)")
                #endif
                continue
            }
        
            // Mark this logical ID as processed
            processedLogicalIDs.insert(logicalID)

            #if DEBUG
            print("[ScreenTimeService] ✅ Recording usage for \(application.displayName) - app is unblocked")
            #endif

            if var existing = appUsages[logicalID] {
                #if DEBUG
                print("[ScreenTimeService] Updating existing usage for \(logicalID)")
                #endif
                existing.recordUsage(duration: duration, endingAt: endDate)
                appUsages[logicalID] = existing
            } else {
                #if DEBUG
                print("[ScreenTimeService] Creating new usage record for \(logicalID)")
                #endif
                let session = AppUsage.UsageSession(startTime: endDate.addingTimeInterval(-duration), endTime: endDate)
                let minutes = Int(duration / 60)
                let calculatedPoints = minutes * application.rewardPoints
                let usage = AppUsage(
                    bundleIdentifier: logicalID,  // Use logicalID as bundleIdentifier for storage
                    appName: application.displayName,
                    category: application.category,
                    totalTime: duration,
                    sessions: [session],
                    firstAccess: session.startTime,
                    lastAccess: endDate,
                    rewardPoints: application.rewardPoints,
                    earnedRewardPoints: calculatedPoints
                )
                appUsages[logicalID] = usage
            }

            // Persist to shared storage immediately
            let appUsage = appUsages[logicalID]!

            // Load existing persisted data to update today's values correctly
            let existingApp = usagePersistence.app(for: logicalID)

            // Calculate today's incremental values
            let newTodaySeconds: Int
            let newTodayPoints: Int

            if let existing = existingApp {
                // Add to existing today's values
                newTodaySeconds = existing.todaySeconds + Int(duration)
                let minutesAdded = Int(duration) / 60
                newTodayPoints = existing.todayPoints + (minutesAdded * appUsage.rewardPoints)

                #if DEBUG
                print("[ScreenTimeService] Updating today's values for \(logicalID)")
                print("[ScreenTimeService]   Previous todaySeconds: \(existing.todaySeconds)")
                print("[ScreenTimeService]   Adding: \(Int(duration)) seconds")
                print("[ScreenTimeService]   New todaySeconds: \(newTodaySeconds)")
                print("[ScreenTimeService]   New todayPoints: \(newTodayPoints)")
                #endif
            } else {
                // First recording today
                newTodaySeconds = Int(duration)
                let minutesAdded = Int(duration) / 60
                newTodayPoints = minutesAdded * appUsage.rewardPoints

                #if DEBUG
                print("[ScreenTimeService] First recording today for \(logicalID)")
                print("[ScreenTimeService]   todaySeconds: \(newTodaySeconds)")
                print("[ScreenTimeService]   todayPoints: \(newTodayPoints)")
                #endif
            }

            let persistedApp = UsagePersistence.PersistedApp(
                logicalID: logicalID,
                displayName: appUsage.appName,
                category: appUsage.category.rawValue,
                rewardPoints: appUsage.rewardPoints,
                totalSeconds: Int(appUsage.totalTime),
                earnedPoints: appUsage.earnedRewardPoints,
                createdAt: appUsage.firstAccess,
                lastUpdated: appUsage.lastAccess,
                todaySeconds: newTodaySeconds,  // ✅ FIX: Now updated correctly!
                todayPoints: newTodayPoints,  // ✅ FIX: Now updated correctly!
                lastResetDate: existingApp?.lastResetDate,
                dailyHistory: existingApp?.dailyHistory ?? []
            )
            usagePersistence.saveApp(persistedApp)

            // === TASK 7 + TASK 17: Create OR UPDATE Core Data UsageRecord for CloudKit Sync ===
            let context = PersistenceController.shared.container.viewContext
            let deviceID = DeviceModeManager.shared.deviceID

            // Check for recent record within last 5 minutes
            if let recentRecord = findRecentUsageRecord(
                logicalID: logicalID,
                deviceID: deviceID,
                withinSeconds: sessionAggregationWindowSeconds  // 5 minutes
            ) {
                // UPDATE existing record
                #if DEBUG
                print("[ScreenTimeService] 📝 Updating existing UsageRecord for \(logicalID)")
                #endif

                // Extend session end time
                recentRecord.sessionEnd = endDate

                // Add to total seconds
                recentRecord.totalSeconds += Int32(duration)

                // Recalculate earned points based on new total time
                let totalMinutes = Int(recentRecord.totalSeconds / 60)
                recentRecord.earnedPoints = Int32(totalMinutes * application.rewardPoints)

                // Mark as unsynced so it gets uploaded again with updated data
                recentRecord.isSynced = false

                #if DEBUG
                print("[ScreenTimeService] 💾 Updated UsageRecord:")
                print("[ScreenTimeService]   LogicalID: \(logicalID)")
                print("[ScreenTimeService]   DisplayName: \(application.displayName)")
                print("[ScreenTimeService]   Category: '\(application.category.rawValue)'")
                print("[ScreenTimeService]   TotalSeconds: \(recentRecord.totalSeconds)")
                print("[ScreenTimeService]   EarnedPoints: \(recentRecord.earnedPoints)")
                #endif

                do {
                    try context.save()
                    #if DEBUG
                    print("[ScreenTimeService] ✅ Updated UsageRecord: \(recentRecord.totalSeconds)s total")
                    #endif
                } catch {
                    #if DEBUG
                    print("[ScreenTimeService] ⚠️ Failed to update UsageRecord: \(error)")
                    #endif
                }
            } else {
                // CREATE new record (no recent session found)
                #if DEBUG
                print("[ScreenTimeService] 💾 Creating NEW UsageRecord for \(logicalID)")
                #endif

                let usageRecord = UsageRecord(context: context)
                usageRecord.recordID = UUID().uuidString
                usageRecord.deviceID = deviceID
                usageRecord.logicalID = logicalID
                usageRecord.displayName = application.displayName
                usageRecord.category = application.category.rawValue
                usageRecord.totalSeconds = Int32(duration)
                usageRecord.sessionStart = endDate.addingTimeInterval(-duration)
                usageRecord.sessionEnd = endDate
                let recordMinutes = Int(duration / 60)
                usageRecord.earnedPoints = Int32(recordMinutes * application.rewardPoints)
                usageRecord.isSynced = false

                #if DEBUG
                print("[ScreenTimeService] 💾 Created UsageRecord:")
                print("[ScreenTimeService]   LogicalID: \(logicalID)")
                print("[ScreenTimeService]   DisplayName: \(application.displayName)")
                print("[ScreenTimeService]   Category: '\(application.category.rawValue)'")  // VERIFY THIS
                print("[ScreenTimeService]   TotalSeconds: \(duration)")
                print("[ScreenTimeService]   EarnedPoints: \(recordMinutes * application.rewardPoints)")
                #endif

                do {
                    try context.save()
                    #if DEBUG
                    print("[ScreenTimeService] ✅ Created NEW UsageRecord for CloudKit sync: \(logicalID)")
                    #endif
                } catch {
                    #if DEBUG
                    print("[ScreenTimeService] ⚠️ Failed to save UsageRecord: \(error)")
                    #endif
                }
            }

            // BF-1 FIX: Consume reserved points for reward apps when usage is recorded
            // Check if this is a reward app and consume reserved points
            if application.category == .reward {
                #if DEBUG
                print("[ScreenTimeService] 🔍 Checking if \(application.displayName) is an unlocked reward app...")
                #endif
                
                // Notify the main app to consume reserved points for this reward app
                // We'll use a Darwin notification since this might be called from the extension
                if let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) {
                    // Store the usage data for the main app to process
                    var rewardUsageData = sharedDefaults.dictionary(forKey: "rewardUsageData") ?? [:]
                    rewardUsageData[logicalID] = [
                        "tokenHash": String(application.token.hashValue),
                        "usageSeconds": duration,
                        "timestamp": Date().timeIntervalSince1970
                    ]
                    sharedDefaults.set(rewardUsageData, forKey: "rewardUsageData")
                    sharedDefaults.synchronize()
                    
                    #if DEBUG
                    print("[ScreenTimeService] 📝 Stored reward usage data for \(application.displayName)")
                    #endif
                }
                
                // Post notification so AppUsageViewModel can consume the reserved points
                CFNotificationCenterPostNotification(
                    CFNotificationCenterGetDarwinNotifyCenter(),
                    CFNotificationName("com.screentimerewards.rewardAppUsed" as CFString),
                    nil,
                    nil,
                    true
                )
            }

            // Notify challenge service of learning app usage
            if application.category == .learning {
                let earnedPointsForChallenge = max(0, Int(duration / 60) * application.rewardPoints)
                Task {
                    await ChallengeService.shared.updateProgressForUsage(
                        appID: logicalID,
                        duration: duration,
                        earnedPoints: earnedPointsForChallenge,
                        deviceID: DeviceModeManager.shared.deviceID
                    )
                }
            }

            recordedCount += 1

            // Track threshold timestamp for snapshot reconciliation safeguards
            lastThresholdTime[logicalID] = endDate
        }

        #if DEBUG
        print("[ScreenTimeService] ✅ Recorded usage for \(recordedCount) apps, skipped \(skippedCount) blocked apps")
        #endif

        // Only notify if we actually recorded something
        if recordedCount > 0 {
            notifyUsageChange()
            // Note: Data is already persisted in the loop above via usagePersistence.saveApp()
        }
    }

    /// Find the most recent UsageRecord for a given app within a time window
    /// - Parameters:
    ///   - logicalID: The logical ID of the app
    ///   - deviceID: The device ID
    ///   - withinSeconds: Time window to search within (default 5 minutes)
    /// - Returns: The most recent UsageRecord or nil if none found
    private func findRecentUsageRecord(
        logicalID: String,
        deviceID: String,
        withinSeconds timeWindow: TimeInterval = 300  // 5 minutes default
    ) -> UsageRecord? {
        let context = PersistenceController.shared.container.viewContext
        let fetchRequest: NSFetchRequest<UsageRecord> = UsageRecord.fetchRequest()

        let now = Date()
        let cutoffTime = now.addingTimeInterval(-timeWindow)

        fetchRequest.predicate = NSPredicate(
            format: "logicalID == %@ AND deviceID == %@ AND sessionEnd >= %@",
            logicalID,
            deviceID,
            cutoffTime as NSDate
        )
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "sessionEnd", ascending: false)]
        fetchRequest.fetchLimit = 1

        do {
            let results = try context.fetch(fetchRequest)
            return results.first
        } catch {
            #if DEBUG
            print("[ScreenTimeService] ⚠️ Failed to fetch recent usage record: \(error)")
            #endif
            return nil
        }
    }


    private func seconds(from components: DateComponents) -> TimeInterval {
        let hours = Double(components.hour ?? 0) * 3600
        let minutes = Double(components.minute ?? 0) * 60
        let seconds = Double(components.second ?? 0)
        let total = hours + minutes + seconds
        return total > 0 ? total : 60
    }

    fileprivate func handleIntervalDidStart(for activity: DeviceActivityName) {
        #if DEBUG
        print("[ScreenTimeService] Monitoring interval started for \(activity.rawValue)")
        #endif
    }

    fileprivate func handleIntervalWillStartWarning(for activity: DeviceActivityName) {
        #if DEBUG
        print("[ScreenTimeService] Monitoring interval will start soon for \(activity.rawValue)")
        #endif
    }

    fileprivate func handleIntervalDidEnd(for activity: DeviceActivityName) {
        #if DEBUG
        print("[ScreenTimeService] Monitoring interval ended for \(activity.rawValue)")
        print("[ScreenTimeService] Note: Daily interval ended at midnight, will restart automatically")
        #endif
    }

    fileprivate func handleIntervalWillEndWarning(for activity: DeviceActivityName) {
        #if DEBUG
        print("[ScreenTimeService] Monitoring interval will end soon for \(activity.rawValue)")
        #endif
    }

    fileprivate func handleEventThresholdReached(_ event: DeviceActivityEvent.Name, timestamp: Date = Date()) {
        #if DEBUG
        print("[ScreenTimeService] Event threshold reached: \(event.rawValue) at \(timestamp)")
        #endif

        // === PHANTOM EVENT PROTECTION ===
        // When monitoring starts, iOS fires ALL past threshold events for apps with historical usage
        // Ignore all events that occur within grace period after monitoring started
        if let startTime = monitoringStartTime {
            let timeSinceMonitoringStarted = timestamp.timeIntervalSince(startTime)
            if timeSinceMonitoringStarted < phantomEventGracePeriod {
                #if DEBUG
                print("[ScreenTimeService] 🛡️ PHANTOM EVENT IGNORED")
                print("[ScreenTimeService]    Event: \(event.rawValue)")
                print("[ScreenTimeService]    Time since monitoring started: \(String(format: "%.1f", timeSinceMonitoringStarted))s")
                print("[ScreenTimeService]    Grace period: \(phantomEventGracePeriod)s")
                print("[ScreenTimeService]    Reason: Historical threshold event fired on monitoring start")
                #endif
                return
            }
        }

        guard let configuration = monitoredEvents[event] else {
            #if DEBUG
            print("[ScreenTimeService] ⚠️ No configuration found for event \(event.rawValue)")
            #endif
            return
        }

        // CONTINUOUS TRACKING: Each threshold fire = 60 seconds of usage
        // Extension handles re-arm signaling, main app handles re-arm execution
        let eventName = event.rawValue
        let isContinuousEvent = eventName.hasSuffix(".continuous")

        #if DEBUG
        if isContinuousEvent {
            let thresholdMinutes = configuration.threshold.minute ?? 0
            print("[ScreenTimeService] ✅ Continuous tracking event fired")
            print("[ScreenTimeService]   Event: \(eventName)")
            print("[ScreenTimeService]   Threshold: \(thresholdMinutes) minutes")
            print("[ScreenTimeService]   App: \(configuration.applications.first?.displayName ?? "unknown")")
        } else {
            // Legacy static threshold event support
            let components = eventName.split(separator: ".")
            if components.count >= 4,
               components[components.count - 2] == "min",
               let minuteNumber = Int(components.last ?? "") {
                print("[ScreenTimeService] ✅ Legacy threshold event fired: minute \(minuteNumber)")
            }
            print("[ScreenTimeService] Category: \(configuration.category.rawValue)")
            print("[ScreenTimeService] App: \(configuration.applications.first?.displayName ?? "unknown")")
        }
        #endif

        // === LAYER 4: Multi-layer validation before recording ===
        // Get app identifier for validation (use token hash as unique identifier)
        let appID = configuration.applications.first.map { String($0.token.hashValue) } ?? "unknown"

        // Validate event through all layers (duplicate/rate-limit/cascade detection)
        let isValidEvent = UsageValidationService.shared.recordThresholdFire(
            eventID: eventName,
            appID: appID,
            at: timestamp
        )

        guard isValidEvent else {
            #if DEBUG
            print("[ScreenTimeService] ⚠️ Event REJECTED by validation service")
            print("[ScreenTimeService]    Reason: Duplicate/Cascade/Rate-Limit violation")
            print("[ScreenTimeService]    Event: \(eventName)")
            print("[ScreenTimeService]    App: \(configuration.applications.first?.displayName ?? "unknown")")
            print("[ScreenTimeService]    This event will NOT be recorded (overcounting protection)")
            #endif

            // Post notification for diagnostic tracking
            NotificationCenter.default.post(
                name: NSNotification.Name("ScreenTimeEventRejected"),
                object: nil,
                userInfo: ["category": configuration.category.rawValue]
            )

            return  // Don't record usage for invalid events
        }

        // === Event passed validation - safe to record ===
        // Each threshold event represents exactly 60 seconds of usage
        // (Except first minute which represents 0→60s, but that's still 60s)
        let incrementalDuration: TimeInterval = 60.0
        let thresholdMinutes = configuration.threshold.minute ?? 0

        #if DEBUG
        print("[ScreenTimeService] ✅ Recording \(incrementalDuration)s for threshold minute \(thresholdMinutes)")
        #endif

        recordUsage(for: configuration.applications, duration: incrementalDuration, endingAt: timestamp)

        // Post notification for diagnostic tracking
        NotificationCenter.default.post(
            name: NSNotification.Name("ScreenTimeThresholdFired"),
            object: nil,
            userInfo: [
                "category": configuration.category.rawValue,
                "duration": incrementalDuration,
                "timestamp": timestamp
            ]
        )

        // === TASK 7 TRIGGER IMPLEMENTATION ===
        // Trigger immediate usage upload to parent when threshold is reached (near real-time sync)
        Task { [weak self] in
            #if DEBUG
            print("[ScreenTimeService] Triggering immediate usage upload to parent...")
            #endif

            // Check if device is paired with a parent
            if UserDefaults.standard.string(forKey: "parentDeviceID") != nil {
                let childSyncService = ChildBackgroundSyncService.shared
                await childSyncService.triggerImmediateUsageUpload()
            } else {
                #if DEBUG
                print("[ScreenTimeService] Device not paired with parent, skipping upload")
                #endif
            }
        }
        // === END TASK 7 TRIGGER IMPLEMENTATION ===
    }

    // OPTION A: advanceThreshold() no longer needed with static thresholds
    // Keeping this function commented out for now in case we need to revert
    /*
    /// Advances the threshold for an event by 1 minute to enable continuous tracking
    /// DeviceActivity thresholds fire ONCE per value, so we must advance to get subsequent fires
    @MainActor
    private func advanceThreshold(for event: DeviceActivityEvent.Name, from currentThreshold: DateComponents) async {
        #if DEBUG
        print("[ScreenTimeService] 🔄 Advancing threshold for event: \(event.rawValue)")
        print("[ScreenTimeService] Current threshold: \(currentThreshold.minute ?? 0) minutes")
        #endif

        // Calculate new threshold (current + 1 minute)
        var newThreshold = currentThreshold
        let currentMinutes = currentThreshold.minute ?? 1
        newThreshold.minute = currentMinutes + 1

        #if DEBUG
        print("[ScreenTimeService] New threshold: \(newThreshold.minute ?? 0) minutes")
        #endif

        // Look up the current MonitoredEvent
        guard let currentEvent = monitoredEvents[event] else {
            #if DEBUG
            print("[ScreenTimeService] ⚠️ Event not found in monitoredEvents, cannot advance threshold")
            #endif
            return
        }

        // Create new MonitoredEvent with incremented threshold
        let updatedEvent = MonitoredEvent(
            name: currentEvent.name,
            category: currentEvent.category,
            threshold: newThreshold,
            applications: currentEvent.applications
        )

        // Update the monitoredEvents dictionary
        monitoredEvents[event] = updatedEvent

        #if DEBUG
        print("[ScreenTimeService] ✅ Updated event threshold in memory")
        #endif

        // Save event mappings to shared UserDefaults
        saveEventMappings()

        // Restart monitoring with new threshold
        // Note: deduplication guard will prevent cascade if user has accumulated usage > new threshold
        #if DEBUG
        print("[ScreenTimeService] Restarting monitoring with new threshold...")
        #endif

        await restartMonitoring(reason: "threshold_advance")

        #if DEBUG
        print("[ScreenTimeService] ✅ Threshold advancement complete")
        #endif
    }
    */
    // END COMMENTED advanceThreshold() - Option A uses static thresholds instead

    fileprivate func handleEventWillReachThresholdWarning(_ event: DeviceActivityEvent.Name) {
        #if DEBUG
        print("[ScreenTimeService] Event \(event.rawValue) will reach threshold soon")
        #endif
    }

#if DEBUG
/// Get the number of monitored events for debugging
func getMonitoredEventsCount() -> Int {
    return monitoredEvents.count
}

/// Get the names of monitored events for debugging
func getMonitoredEventNames() -> [String] {
    return monitoredEvents.keys.map { $0.rawValue }
}

/// Configure monitored events using plain bundle identifiers for unit testing.
/// NOTE: This simulates app monitoring without requiring FamilyActivityPicker.
/// In production, tokens come from FamilyActivitySelection.
func configureForTesting(
    applications: [(bundleIdentifier: String?, name: String, category: AppUsage.AppCategory, rewardPoints: Int)],
    threshold: DateComponents = DateComponents(minute: 15)
) {
    #if DEBUG
    print("[ScreenTimeService] ⚠️ Configuring for TESTING mode with \(applications.count) applications")
    print("[ScreenTimeService] This creates mock events that won't receive real DeviceActivity callbacks")
    for app in applications {
        print("[ScreenTimeService] Test app: \(app.name) (Bundle ID: \(app.bundleIdentifier ?? "nil")), Category: \(app.category.rawValue), Reward Points: \(app.rewardPoints)")
    }
    #endif

    // For testing, we simulate the event structure without actual monitoring
    // This allows UI and data flow testing without real Screen Time data
    let grouped = applications.reduce(into: [AppUsage.AppCategory: [(String?, String, AppUsage.AppCategory, Int)]]()) { result, entry in
        result[entry.category, default: []].append((entry.bundleIdentifier, entry.name, entry.category, entry.rewardPoints))
    }

    // Create placeholder events (won't be used for actual monitoring)
    monitoredEvents = grouped.reduce(into: [:]) { result, element in
        let (category, apps) = element
        guard !apps.isEmpty else { return }
        let name = DeviceActivityEvent.Name("usage.\(category.rawValue.lowercased())")

        #if DEBUG
        print("[ScreenTimeService] Creating test event for category \(category.rawValue) with \(apps.count) applications")
        #endif

        // Note: Can't create real MonitoredApplication without tokens
        // In testing, we'll manually trigger usage recording instead
        result[name] = MonitoredEvent(name: name, category: category, threshold: threshold, applications: [])
    }

    hasSeededSampleData = false
    appUsages.removeAll()
    notifyUsageChange()
}

/// Manually record test usage data (for testing without real tokens)
func recordTestUsage(
    appName: String,
    category: AppUsage.AppCategory,
    rewardPoints: Int = 10,
    duration: TimeInterval,
    bundleIdentifier: String? = nil
) {
    #if DEBUG
    print("[ScreenTimeService] Recording test usage: \(appName), duration: \(duration)s, reward points: \(rewardPoints)")
    #endif

    let storageKey = bundleIdentifier ?? "app.\(appName.replacingOccurrences(of: " ", with: ".").lowercased())"
    let endDate = Date()

    if var existing = appUsages[storageKey] {
        existing.recordUsage(duration: duration, endingAt: endDate)
        appUsages[storageKey] = existing
    } else {
        let session = AppUsage.UsageSession(
            startTime: endDate.addingTimeInterval(-duration),
            endTime: endDate
        )
        let minutes = Int(duration / 60)
        let calculatedPoints = minutes * rewardPoints
        let usage = AppUsage(
            bundleIdentifier: storageKey,
            appName: appName,
            category: category,
            totalTime: duration,
            sessions: [session],
            firstAccess: session.startTime,
            lastAccess: endDate,
            rewardPoints: rewardPoints,
            earnedRewardPoints: calculatedPoints
        )
        appUsages[storageKey] = usage
    }
    notifyUsageChange()
}

/// Configure monitoring with known test applications for debugging
func configureWithTestApplications() {
    #if DEBUG
    print("[ScreenTimeService] Configuring with test applications")
    #endif

    let testApps: [(bundleIdentifier: String?, name: String, category: AppUsage.AppCategory, rewardPoints: Int)] = [
        (bundleIdentifier: "com.apple.books", name: "Books", category: .learning, rewardPoints: 20),
        (bundleIdentifier: "com.apple.calculator", name: "Calculator", category: .learning, rewardPoints: 20),
        (bundleIdentifier: "com.apple.Music", name: "Music", category: .reward, rewardPoints: 10)
    ]

    configureForTesting(applications: testApps, threshold: DateComponents(minute: 5))

    // Manually add test usage data since we don't have real tokens
    recordTestUsage(appName: "Books", category: .learning, rewardPoints: 20, duration: 3600, bundleIdentifier: "com.apple.books")
    recordTestUsage(appName: "Calculator", category: .learning, rewardPoints: 20, duration: 600, bundleIdentifier: "com.apple.calculator")
    recordTestUsage(appName: "Music", category: .reward, rewardPoints: 10, duration: 1800, bundleIdentifier: "com.apple.Music")
}
#endif

    /// Public method to record usage for a logical ID, replacing existing entries rather than appending
    /// - Parameters:
    ///   - logicalID: The logical ID of the app
    ///   - additionalSeconds: Additional seconds to add to the app's usage
    ///   - rewardPointsPerMinute: Reward points per minute for this app
    func recordUsage(logicalID: String, additionalSeconds: TimeInterval, rewardPointsPerMinute: Int) {
        #if DEBUG
        print("[ScreenTimeService] Public recordUsage called for logicalID: \(logicalID), additionalSeconds: \(additionalSeconds), rewardPointsPerMinute: \(rewardPointsPerMinute)")
        #endif
        
        // Check if we already have an entry for this logical ID
        if var existing = appUsages[logicalID] {
            #if DEBUG
            print("[ScreenTimeService] Updating existing usage for \(logicalID)")
            #endif
            // Update the existing entry rather than creating a new one
            existing.recordUsage(duration: additionalSeconds)
            appUsages[logicalID] = existing
        } else {
            #if DEBUG
            print("[ScreenTimeService] Creating new usage record for \(logicalID)")
            #endif
            // Create a new entry if one doesn't exist
            let now = Date()
            let session = AppUsage.UsageSession(startTime: now.addingTimeInterval(-additionalSeconds), endTime: now)
            let minutes = Int(additionalSeconds / 60)
            let calculatedPoints = minutes * rewardPointsPerMinute
            let usage = AppUsage(
                bundleIdentifier: logicalID,
                appName: "Unknown App",
                category: .learning,
                totalTime: additionalSeconds,
                sessions: [session],
                firstAccess: session.startTime,
                lastAccess: now,
                rewardPoints: rewardPointsPerMinute,
                earnedRewardPoints: calculatedPoints
            )
            appUsages[logicalID] = usage
        }
        
        // Persist to shared storage immediately
        if let appUsage = appUsages[logicalID] {
            let existingApp = usagePersistence.app(for: logicalID)
            let persistedApp = UsagePersistence.PersistedApp(
                logicalID: logicalID,
                displayName: appUsage.appName,
                category: appUsage.category.rawValue,
                rewardPoints: appUsage.rewardPoints,
                totalSeconds: Int(appUsage.totalTime),
                earnedPoints: appUsage.earnedRewardPoints,
                createdAt: appUsage.firstAccess,
                lastUpdated: appUsage.lastAccess,
                todaySeconds: existingApp?.todaySeconds ?? 0,
                todayPoints: existingApp?.todayPoints ?? 0,
                lastResetDate: existingApp?.lastResetDate,
                dailyHistory: existingApp?.dailyHistory ?? []
            )
            usagePersistence.saveApp(persistedApp)
        }
        
        // Notify that usage has changed
        notifyUsageChange()
    }
    
    // Task M: Add method to reset usage data for an app
    /// Reset usage data for a specific app by logical ID
    /// - Parameter logicalID: The logical ID of the app to reset
    func resetUsageData(for logicalID: String) {
        #if DEBUG
        print("[ScreenTimeService] Resetting usage data for logicalID: \(logicalID)")
        #endif
        
        // Remove the app usage data
        appUsages.removeValue(forKey: logicalID)
        
        // Notify that usage has changed
        notifyUsageChange()
    }
    
    // Task EXP-2: Implement Category Token Expansion Service
    /// Expand category tokens into individual app tokens
    /// - Parameter selection: The FamilyActivitySelection containing categories and apps
    /// - Returns: A set of ApplicationToken with categories expanded to individual apps
    func expandCategoryTokens(_ selection: FamilyActivitySelection) async -> Set<ApplicationToken> {
        #if DEBUG
        print("[ScreenTimeService] Expanding category tokens:")
        print("[ScreenTimeService]   Categories count: \(selection.categories.count)")
        print("[ScreenTimeService]   Applications count: \(selection.applications.count)")
        #endif
        
        // Start with existing application tokens
        var expandedTokens = selection.applications.compactMap { $0.token }
        
        // If no categories, return the existing application tokens
        if selection.categories.isEmpty {
            #if DEBUG
            print("[ScreenTimeService] No categories to expand, returning \(selection.applications.count) existing app tokens")
            #endif
            return Set(expandedTokens)
        }
        
        // Try to expand categories using our existing familySelection data
        // This is our best strategy - use the master selection that contains all previously selected apps
        if !familySelection.applications.isEmpty {
            #if DEBUG
            print("[ScreenTimeService] Expanding using master selection data (\(familySelection.applications.count) apps)")
            #endif
            
            // For "All Apps" selection, we might get a special category
            // Let's check if we have the "All Apps" category
            let allAppsCategory = selection.categories.first { category in
                // This is a heuristic - the "All Apps" category might have a specific identifier
                category.localizedDisplayName?.lowercased().contains("all") ?? false
            }
            
            if allAppsCategory != nil {
                #if DEBUG
                print("[ScreenTimeService] Detected 'All Apps' selection, expanding to all authorized apps")
                #endif
                
                // For "All Apps", we want to include all apps from our master selection
                let allTokens = familySelection.applications.compactMap { $0.token }
                expandedTokens.append(contentsOf: allTokens)
            } else {
                // For specific categories, we'll try to match apps
                #if DEBUG
                print("[ScreenTimeService] Expanding specific categories")
                #endif
                
                // For each category in the selection, find matching apps in our master selection
                for categoryToken in selection.categories {
                    #if DEBUG
                    print("[ScreenTimeService] Processing category: \(categoryToken.localizedDisplayName ?? "Unknown Category")")
                    #endif
                    
                    // Find apps in master selection that belong to this category
                    // This is a simplified approach - in a real implementation, we'd need a better way to match categories
                    let matchingApps = familySelection.applications.filter { app in
                        // For now, we'll add all apps from master selection as they're all authorized
                        return app.token != nil
                    }
                    
                    let categoryTokens = matchingApps.compactMap { $0.token }
                    expandedTokens.append(contentsOf: categoryTokens)
                    
                    #if DEBUG
                    print("[ScreenTimeService]   Added \(categoryTokens.count) apps from master selection")
                    #endif
                }
            }
        } else {
            #if DEBUG
            print("[ScreenTimeService] No master selection data available, falling back to all authorized apps")
            #endif
            
            // Fallback: Return all authorized apps if we have no master data
            // This would require requesting a new FamilyActivityPicker selection with "All Apps"
            // For now, we'll just return what we have plus the existing tokens
        }
        
        // Remove duplicates by converting to Set
        let uniqueTokens = Set(expandedTokens)
        
        #if DEBUG
        print("[ScreenTimeService] Expansion complete:")
        print("[ScreenTimeService]   Original app tokens: \(selection.applications.count)")
        print("[ScreenTimeService]   Categories processed: \(selection.categories.count)")
        print("[ScreenTimeService]   Final expanded tokens: \(uniqueTokens.count)")
        #endif
        
        return uniqueTokens
    }
    
    /// Get display name for a given token (for debugging purposes)
    func getDisplayName(for token: ApplicationToken) -> String? {
        // Find the application in our familySelection that matches this token
        guard let application = familySelection.applications.first(where: { $0.token == token }) else {
            return nil
        }
        return application.localizedDisplayName
    }
    
    /// Get logical ID for a given token (for debugging purposes)
    func getLogicalID(for token: ApplicationToken) -> String? {
        let tokenHash = usagePersistence.tokenHash(for: token)
        return usagePersistence.logicalID(for: tokenHash)
    }
    
    /// Get the app group identifier for UserDefaults access
    func getAppGroupIdentifier() -> String {
        return "group.com.screentimerewards.shared"
    }
    
    // MARK: - Master Selection Seeding Methods
    
    /// Save the master selection for category expansion
    /// - Parameter selection: The FamilyActivitySelection containing all trackable apps
    func saveMasterSelection(_ selection: FamilyActivitySelection) {
        self.familySelection = selection
        
        // Persist to UserDefaults for permanent storage
        // Note: FamilyActivitySelection itself cannot be encoded,
        // but we can persist app count and metadata
        let defaults = UserDefaults(suiteName: getAppGroupIdentifier())
        defaults?.set(selection.applications.count, forKey: "masterSelectionAppCount")
        defaults?.set(Date(), forKey: "masterSelectionLastUpdated")
        
        #if DEBUG
        print("[ScreenTimeService] ✅ Master selection saved:")
        print("[ScreenTimeService]   Apps: \(selection.applications.count)")
        print("[ScreenTimeService]   Categories: \(selection.categories.count)")
        #endif
    }
    
    /// Load master selection metadata
    func loadMasterSelection() {
        let defaults = UserDefaults(suiteName: getAppGroupIdentifier())
        let count = defaults?.integer(forKey: "masterSelectionAppCount") ?? 0
        
        #if DEBUG
        print("[ScreenTimeService] ℹ️ Master selection metadata loaded:")
        print("[ScreenTimeService]   Previously saved app count: \(count)")
        #endif
        
        // Note: Actual FamilyActivitySelection will need re-seeding on fresh launch
        // This is an Apple limitation - we can't reconstruct the selection
    }
}

// MARK: - CloudKit Integration Helpers
extension ScreenTimeService {
    /// Assign a category to an application token
    /// This method provides a way for external code to modify category assignments
    func assignCategory(_ category: AppUsage.AppCategory, to token: ApplicationToken) {
        // Update the internal category assignments
        categoryAssignments[token] = category
        
        #if DEBUG
        let appName = getDisplayName(for: token) ?? "Unknown App"
        print("[ScreenTimeService] Assigned category \(category.rawValue) to \(appName)")
        #endif
    }
    
    /// Assign reward points to an application token
    /// This method provides a way for external code to modify reward point assignments
    func assignRewardPoints(_ points: Int, to token: ApplicationToken) {
        // Update the internal reward points assignments
        rewardPointsAssignments[token] = points
        
        #if DEBUG
        let appName = getDisplayName(for: token) ?? "Unknown App"
        print("[ScreenTimeService] Assigned \(points) reward points to \(appName)")
        #endif
    }
    
    /// Get category assignments for external access
    func getCategoryAssignments() -> [ApplicationToken: AppUsage.AppCategory] {
        return categoryAssignments
    }
    
    /// Get reward points assignments for external access
    func getRewardPointsAssignments() -> [ApplicationToken: Int] {
        return rewardPointsAssignments
    }
    
    /// Get category for a specific token
    func getCategory(for token: ApplicationToken) -> AppUsage.AppCategory? {
        return categoryAssignments[token]
    }
    
    /// Get reward points for a specific token
    func getRewardPoints(for token: ApplicationToken) -> Int {
        return rewardPointsAssignments[token] ?? 0
    }

    /// Check if an app is currently blocked
    func isAppBlocked(_ token: ApplicationToken) -> Bool {
        // This would need to check the current shielded applications
        // For now, we'll return false as we don't have access to the shielded apps here
        return false
    }
}

// MARK: - FamilyActivitySelection Extension for Consistent Sorting
extension FamilyActivitySelection {
    /// Returns applications sorted by token hash for consistent iteration order
    /// This fixes the Set reordering bug that causes data shuffling when adding new apps
    /// TASK L: Ensure deterministic sorting using token hash
    func sortedApplications(using usagePersistence: UsagePersistence) -> [Application] {
        return self.applications.sorted { app1, app2 in
            guard let token1 = app1.token, let token2 = app2.token else { return false }
            let hash1 = usagePersistence.tokenHash(for: token1)
            let hash2 = usagePersistence.tokenHash(for: token2)
            return hash1 < hash2
        }
    }
}

// MARK: - ScreenTimeActivityMonitor
@MainActor
private protocol ScreenTimeActivityMonitorDelegate: AnyObject {
    func activityMonitorDidStartInterval(_ activity: DeviceActivityName)
    func activityMonitorWillStartInterval(_ activity: DeviceActivityName)
    func activityMonitorDidEndInterval(_ activity: DeviceActivityName)
    func activityMonitorWillEndInterval(_ activity: DeviceActivityName)
    func activityMonitorDidReachThreshold(for event: DeviceActivityEvent.Name)
    func activityMonitorWillReachThreshold(for event: DeviceActivityEvent.Name)
}

private final class ScreenTimeActivityMonitor: DeviceActivityMonitor {
    nonisolated(unsafe) weak var delegate: ScreenTimeActivityMonitorDelegate?

    private nonisolated func deliverToMain(_ handler: @escaping @MainActor (ScreenTimeActivityMonitorDelegate) -> Void) {
        Task { [weak self] in
            guard let self else { return }
            await MainActor.run {
                guard let delegate = self.delegate else { return }
                handler(delegate)
            }
        }
    }

    override nonisolated init() {
        super.init()
    }

    override nonisolated func intervalDidStart(for activity: DeviceActivityName) {
        deliverToMain { delegate in
            delegate.activityMonitorDidStartInterval(activity)
        }
    }

    override nonisolated func intervalWillStartWarning(for activity: DeviceActivityName) {
        deliverToMain { delegate in
            delegate.activityMonitorWillStartInterval(activity)
        }
    }

    override nonisolated func intervalDidEnd(for activity: DeviceActivityName) {
        deliverToMain { delegate in
            delegate.activityMonitorDidEndInterval(activity)
        }
    }

    override nonisolated func intervalWillEndWarning(for activity: DeviceActivityName) {
        deliverToMain { delegate in
            delegate.activityMonitorWillEndInterval(activity)
        }
    }

    override nonisolated func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        deliverToMain { delegate in
            delegate.activityMonitorDidReachThreshold(for: event)
        }
    }

    override nonisolated func eventWillReachThresholdWarning(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        deliverToMain { delegate in
            delegate.activityMonitorWillReachThreshold(for: event)
        }
    }
}

// MARK: - ScreenTimeActivityMonitorDelegate
extension ScreenTimeService {
    func activityMonitorDidStartInterval(_ activity: DeviceActivityName) {
        handleIntervalDidStart(for: activity)
    }

    func activityMonitorWillStartInterval(_ activity: DeviceActivityName) {
        handleIntervalWillStartWarning(for: activity)
    }

    func activityMonitorDidEndInterval(_ activity: DeviceActivityName) {
        handleIntervalDidEnd(for: activity)
    }

    func activityMonitorWillEndInterval(_ activity: DeviceActivityName) {
        handleIntervalWillEndWarning(for: activity)
    }

    func activityMonitorDidReachThreshold(for event: DeviceActivityEvent.Name) {
        handleEventThresholdReached(event)
    }

    func activityMonitorWillReachThreshold(for event: DeviceActivityEvent.Name) {
        handleEventWillReachThresholdWarning(event)
    }
    
    /// Trigger immediate usage data upload
    func triggerImmediateUpload() async {
        #if DEBUG
        print("[ScreenTimeService] Triggering immediate usage upload")
        #endif
        
        // Process the offline queue immediately
        let offlineQueue = OfflineQueueManager.shared
        await offlineQueue.processQueue()
    }
}

// 🔴 TASK 12: Add Test Usage Records for Upload - CRITICAL
#if DEBUG
extension ScreenTimeService {
    /// Create test usage records for upload testing
    /// This function creates fresh unsynced usage records to test the upload flow
    func createTestUsageRecordsForUpload() {
        print("[ScreenTimeService] ===== Creating Test Usage Records =====")

        let context = PersistenceController.shared.container.viewContext

        // Create 3 test records with different categories
        for i in 0..<3 {
            let record = UsageRecord(context: context)
            record.deviceID = DeviceModeManager.shared.deviceID
            record.logicalID = "test-app-\(UUID().uuidString)"
            record.displayName = "Test App \(i)"
            record.sessionStart = Date().addingTimeInterval(Double(-3600 * i))  // Staggered times
            record.sessionEnd = Date().addingTimeInterval(Double(-3600 * i + 300))  // 5 min sessions
            record.totalSeconds = 300
            record.earnedPoints = Int32(10 * (i + 1))  // 10, 20, 30 points
            record.category = i % 2 == 0 ? "learning" : "reward"
            record.isSynced = false  // CRITICAL: Mark as unsynced
            record.syncTimestamp = nil

            print("[ScreenTimeService] Created test record: \(record.displayName ?? "nil"), category: \(record.category ?? "nil"), points: \(record.earnedPoints)")
        }

        do {
            try context.save()
            print("[ScreenTimeService] ✅ Created 3 test usage records (marked as unsynced)")
            print("[ScreenTimeService] Device ID: \(DeviceModeManager.shared.deviceID)")
        } catch {
            print("[ScreenTimeService] ❌ Failed to create test records: \(error)")
        }
    }

    /// Mark all existing usage records as unsynced for testing
    func markAllRecordsAsUnsynced() {
        print("[ScreenTimeService] ===== Marking All Records As Unsynced =====")

        let context = PersistenceController.shared.container.viewContext
        let fetchRequest: NSFetchRequest<UsageRecord> = UsageRecord.fetchRequest()

        do {
            let records = try context.fetch(fetchRequest)
            print("[ScreenTimeService] Found \(records.count) usage records")

            for record in records {
                record.isSynced = false
                record.syncTimestamp = nil
            }

            try context.save()
            print("[ScreenTimeService] ✅ Marked \(records.count) records as unsynced")
        } catch {
            print("[ScreenTimeService] ❌ Failed to mark records: \(error)")
        }
    }
}
#endif
