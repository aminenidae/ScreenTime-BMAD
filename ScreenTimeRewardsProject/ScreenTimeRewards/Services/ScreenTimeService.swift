import Foundation
import CoreFoundation
import DeviceActivity
import FamilyControls
import ManagedSettings
import CoreData
import UIKit

/// Service to handle Screen Time API functionality while exposing deterministic
/// state for the SwiftUI layer.
@available(iOS 16.0, *)
@MainActor
class ScreenTimeService: NSObject, ScreenTimeActivityMonitorDelegate {
    static let shared = ScreenTimeService()
    static let usageDidChangeNotification = Notification.Name("ScreenTimeService.usageDidChange")
    
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
    private let primaryActivityName = DeviceActivityName("ScreenTimeTracking.primary")
    private var activityNames: [DeviceActivityName] { [primaryActivityName] }
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
    private static let usageRecordedNotification = CFNotificationName(ScreenTimeNotifications.usageRecorded as CFString)

    // App Group identifier - must match extension
    private let appGroupIdentifier = "group.com.screentimerewards.shared"
    private let notificationGapLogKey = "notification_gap_log"

    // Shared persistence helper for logical ID-based storage
    private(set) var usagePersistence = UsagePersistence()
    private var appUsageHistories: [String: [UsagePersistence.DailyUsageSummary]] = [:]  // Key = logicalID

    // Configuration
    private let sessionAggregationWindowSeconds: TimeInterval = 300  // 5 minutes
    private let maxScheduledIncrementsPerApp = 360  // queue ahead (~6 hours of 60s increments) to avoid restart gaps

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
        let threshold: DateComponents
        let applications: [MonitoredApplication]
        let increment: TimeInterval

        func deviceActivityEvent() -> DeviceActivityEvent {
            // Create DeviceActivityEvent using application tokens
            let tokens = applications.map { $0.token }
            #if DEBUG
            print("[ScreenTimeService] Creating DeviceActivityEvent with \(tokens.count) tokens")
            for (index, app) in applications.enumerated() {
                print("[ScreenTimeService]   App \(index): \(app.displayName) (Bundle ID: \(app.bundleIdentifier ?? "nil"))")
            }
            #endif

            // Always count fresh usage after each restart to prevent immediate re-triggers
            return DeviceActivityEvent(
                applications: Set(tokens),
                threshold: threshold
            )
        }
    }

    private let activityMonitor = ScreenTimeActivityMonitor()
    private let incrementSeconds: TimeInterval = 60  // Default increment when no category override is provided
    private var monitoredEvents: [DeviceActivityEvent.Name: MonitoredEvent] = [:]
    private var monitoredApplicationsByCategory: [AppUsage.AppCategory: [MonitoredApplication]] = [:]
    private var currentThresholds: [AppUsage.AppCategory: DateComponents] = [:]
    private var cumulativeExpectedUsage: [String: TimeInterval] = [:]
    private var recentUsageEvents: [String: Date] = [:]
    private var isRestarting = false
    private let cumulativeTrackingKey = "cumulativeExpectedUsage"
    private let firstLaunchFlagKey = "hasLaunchedBefore"
    private let cumulativeValidationTolerance: TimeInterval = 120
    private let minimumAutoRestartInterval: TimeInterval = 300
    private let extensionHeartbeatTimeout: TimeInterval = 180
    private let extensionHealthEventGraceWindow: TimeInterval = 180
    private var lastRestartDate: Date?
    private var lastEventFireTimestamps: [DeviceActivityEvent.Name: Date] = [:]
    private let eventDeduplicationWindow: TimeInterval = 2

    private var healthCheckTimer: Timer?
    private var lastReceivedSequence: Int = 0
    private var lastEventTimestamp: Date?

    // Store category assignments and selection for sharing across ViewModels
    private(set) var categoryAssignments: [ApplicationToken: AppUsage.AppCategory] = [:]
    private(set) var rewardPointsAssignments: [ApplicationToken: Int] = [:]
    private(set) var familySelection: FamilyActivitySelection = .init(includeEntireCategory: true)

    override private init() {
        deviceActivityCenter = DeviceActivityCenter()
        super.init()
        activityMonitor.delegate = self
        registerForExtensionNotifications()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
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

        loadCumulativeTracking()

        // Load all persisted apps from shared storage
        let persistedApps = usagePersistence.loadAllApps()

        // Convert to AppUsage dictionary and capture history
        self.appUsages = persistedApps.reduce(into: [:]) { result, entry in
            let (logicalID, persisted) = entry
            result[logicalID] = appUsage(from: persisted)
        }
        self.appUsageHistories = persistedApps.reduce(into: [:]) { result, entry in
            result[entry.key] = entry.value.dailyHistory
        }

        #if DEBUG
        print("[ScreenTimeService] ✅ Loaded \(appUsages.count) apps from persistence")
        for (logicalID, usage) in appUsages {
            print("[ScreenTimeService]   - \(usage.appName) (\(logicalID)): \(usage.totalTime)s, \(usage.earnedRewardPoints)pts")
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
                    #if DEBUG
                    print("[ScreenTimeService] ❌ Failed to restart monitoring: \(error)")
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
        appUsageHistories = [:]
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
                lastResetDate: existingApp?.lastResetDate
            )
            usagePersistence.saveApp(persistedApp)

            #if DEBUG
            if let existingApp {
                print("[ScreenTimeService]   💾 Updated app configuration (preserved \(existingApp.totalSeconds)s, \(existingApp.earnedPoints)pts)")
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

        monitoredApplicationsByCategory = groupedApplications
        currentThresholds = providedThresholds
        let activeLogicalIDs = Set(groupedApplications.values.flatMap { $0.map(\.logicalID) })
        let filteredTracking = cumulativeExpectedUsage.filter { activeLogicalIDs.contains($0.key) }
        if filteredTracking.count != cumulativeExpectedUsage.count {
            cumulativeExpectedUsage = filteredTracking
            saveCumulativeTracking()
        }
        hasSeededSampleData = false
        regenerateMonitoredEvents(refreshUsageCache: true)

        if isMonitoring {
            deviceActivityCenter.stopMonitoring(activityNames)
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

    private func appUsage(from persisted: UsagePersistence.PersistedApp) -> AppUsage {
        let category = AppUsage.AppCategory(rawValue: persisted.category) ?? .learning

        // Create today's session if there's usage today
        var sessions: [AppUsage.UsageSession] = []
        let now = Date()
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: now)

        // Migration: If todaySeconds is 0 but totalSeconds > 0, this is old data
        // Assume all usage is from today for backward compatibility
        let usageSecondsToday = persisted.todaySeconds > 0 ? persisted.todaySeconds : persisted.totalSeconds

        if usageSecondsToday > 0 {
            // Create a session representing today's accumulated usage
            // endTime is set to lastUpdated if it's today, otherwise use current time
            let sessionEnd = calendar.isDate(persisted.lastUpdated, inSameDayAs: now) ? persisted.lastUpdated : now
            let sessionStart = sessionEnd.addingTimeInterval(-TimeInterval(usageSecondsToday))

            let todaySession = AppUsage.UsageSession(
                startTime: max(sessionStart, todayStart), // Don't go before today
                endTime: sessionEnd
            )
            sessions.append(todaySession)

            #if DEBUG
            if persisted.todaySeconds == 0 && persisted.totalSeconds > 0 {
                print("[ScreenTimeService] 📦 Migration: Treating \(persisted.totalSeconds)s as today's usage for \(persisted.displayName)")
            }
            #endif
        }

        return AppUsage(
            bundleIdentifier: persisted.logicalID,
            appName: persisted.displayName,
            category: category,
            totalTime: TimeInterval(persisted.totalSeconds),
            sessions: sessions,
            firstAccess: persisted.createdAt,
            lastAccess: persisted.lastUpdated,
            rewardPoints: persisted.rewardPoints,
            earnedRewardPoints: persisted.earnedPoints
        )
    }

    /// Save event name → app info mapping for extension to use
    private func saveEventMappings() {
        guard let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            NSLog("[ScreenTimeService] ❌ CRITICAL: Cannot access app group to save event mappings")
            return
        }

        // Create mapping: eventName → (logicalID, rewardPoints, thresholdSeconds)
        var mappings: [String: [String: Any]] = [:]
        for (eventName, event) in monitoredEvents {
            guard let app = event.applications.first else { continue }

            let thresholdSeconds = seconds(from: event.threshold)
            mappings[eventName.rawValue] = [
                "logicalID": app.logicalID,
                "displayName": app.displayName,
                "category": app.category.rawValue,
                "rewardPoints": app.rewardPoints,
                "thresholdSeconds": Int(thresholdSeconds),
                "incrementSeconds": Int(event.increment)
            ]
        }

        NSLog("[ScreenTimeService] 💾 Saving \(mappings.count) event mappings for extension:")
        for (eventName, info) in mappings {
            let displayName = info["displayName"] as? String ?? "?"
            let logicalID = info["logicalID"] as? String ?? "?"
            NSLog("[ScreenTimeService]   '\(eventName)' → \(displayName) (\(logicalID))")
        }

        if let data = try? JSONSerialization.data(withJSONObject: mappings) {
            sharedDefaults.set(data, forKey: "eventMappings")
            sharedDefaults.removeObject(forKey: "currentRestartGeneration")
            sharedDefaults.removeObject(forKey: "previousRestartGeneration")
            sharedDefaults.synchronize()
            NSLog("[ScreenTimeService] ✅ Event mappings saved successfully to app group")
        } else {
            NSLog("[ScreenTimeService] ❌ FAILED to serialize event mappings to JSON")
        }
    }

    private func saveCumulativeTracking() {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else {
            NSLog("[ScreenTimeService] ⚠️ Cannot save cumulative tracking - no app group access")
            return
        }

        defaults.set(cumulativeExpectedUsage.mapValues { $0 }, forKey: cumulativeTrackingKey)
        defaults.synchronize()

        NSLog("[ScreenTimeService] 💾 Saved cumulative tracking for \(cumulativeExpectedUsage.count) apps")
        for (logicalID, expected) in cumulativeExpectedUsage {
            NSLog("[ScreenTimeService]   \(logicalID): \(Int(expected))s")
        }
    }

    private func loadCumulativeTracking() {
        let standardDefaults = UserDefaults.standard
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else {
            NSLog("[ScreenTimeService] ⚠️ Cannot load cumulative tracking - no app group access")
            cumulativeExpectedUsage.removeAll()
            return
        }

        let hasLaunchedBefore = standardDefaults.bool(forKey: firstLaunchFlagKey)
        if !hasLaunchedBefore {
            NSLog("[ScreenTimeService] 🆕 First launch detected - clearing persisted usage caches")
            usagePersistence.clearAllAppData(reason: "first_launch")
            cumulativeExpectedUsage.removeAll()
            defaults.removeObject(forKey: cumulativeTrackingKey)
            defaults.synchronize()
            saveCumulativeTracking()
            standardDefaults.set(true, forKey: firstLaunchFlagKey)
            standardDefaults.synchronize()
            return
        }

        if let saved = defaults.dictionary(forKey: cumulativeTrackingKey) as? [String: TimeInterval] {
            cumulativeExpectedUsage = saved
            NSLog("[ScreenTimeService] 📂 Loaded cumulative tracking for \(saved.count) apps")
            for (logicalID, expected) in saved {
                NSLog("[ScreenTimeService]   \(logicalID): \(Int(expected))s")
            }
        } else {
            cumulativeExpectedUsage.removeAll()
            NSLog("[ScreenTimeService] 📂 No cumulative tracking found, starting fresh")
        }
    }

    private func reconcileCumulativeTrackingWithPersistedUsage(_ persistedSnapshot: [String: UsagePersistence.PersistedApp]? = nil) {
        guard !cumulativeExpectedUsage.isEmpty else { return }

        let persistedApps = persistedSnapshot ?? usagePersistence.reloadAppsFromDisk()
        var didMutate = false

        for logicalID in Array(cumulativeExpectedUsage.keys) {
            guard let persisted = persistedApps[logicalID] else {
                NSLog("[ScreenTimeService] ⚠️ No persisted usage for \(logicalID) - removing cumulative tracking entry")
                cumulativeExpectedUsage.removeValue(forKey: logicalID)
                didMutate = true
                continue
            }

            let actualTodaySeconds = TimeInterval(persisted.todaySeconds)
            let expected = cumulativeExpectedUsage[logicalID] ?? 0
            if expected > actualTodaySeconds + cumulativeValidationTolerance {
                NSLog("[ScreenTimeService] ⚠️ Cumulative tracking for \(persisted.displayName) (\(logicalID)) is stale: expected \(Int(expected))s vs actual \(Int(actualTodaySeconds))s - resetting")
                cumulativeExpectedUsage[logicalID] = actualTodaySeconds
                didMutate = true
            }
        }

        if didMutate {
            saveCumulativeTracking()
        }
    }

    func resetDailyTracking() {
        usagePersistence.resetDailyCounters()
        cumulativeExpectedUsage.removeAll()
        saveCumulativeTracking()
        reloadAppUsagesFromPersistence()
        NSLog("[ScreenTimeService] 🔄 Reset cumulative tracking for new day")
    }

    @MainActor
    func handleMidnightTransition() async {
        NSLog("[ScreenTimeService] 🌅 Handling calendar day change")
        resetDailyTracking()
        if isMonitoring {
            await restartMonitoring(reason: "midnight_transition", force: true)
        }
    }

    // MARK: - Extension Health Monitoring

    private func startHealthMonitoring() {
        healthCheckTimer?.invalidate()
        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.checkExtensionHealth()
        }
        checkExtensionHealth()
    }

    private func stopHealthMonitoring() {
        healthCheckTimer?.invalidate()
        healthCheckTimer = nil
    }

    func checkExtensionHealth() {
        guard isMonitoring else { return }
        guard let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) else { return }
        let lastHeartbeat = sharedDefaults.double(forKey: "extension_heartbeat")
        guard lastHeartbeat > 0 else { return }

        let now = Date()
        let gapSeconds = now.timeIntervalSince1970 - lastHeartbeat
        guard gapSeconds > extensionHeartbeatTimeout else { return }

        if let lastEventTimestamp {
            let sinceLastEvent = now.timeIntervalSince(lastEventTimestamp)
            if sinceLastEvent < extensionHealthEventGraceWindow {
                #if DEBUG
                print("[ScreenTimeService] ⏱️ Skipping health restart (\(Int(gapSeconds))s gap) because last event fired \(Int(sinceLastEvent))s ago")
                #endif
                return
            }
        }

        NotificationCenter.default.post(
            name: .extensionUnhealthy,
            object: nil,
            userInfo: ["gap_seconds": Int(gapSeconds)]
        )

        Task { [weak self] in
            await self?.restartMonitoring(reason: "extension_health_gap_\(Int(gapSeconds))s")
        }
    }

    func getExtensionHealthStatus() -> ExtensionHealthStatus {
        guard let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            return ExtensionHealthStatus(
                lastHeartbeat: .distantPast,
                heartbeatGapSeconds: Int.max,
                isHealthy: false,
                memoryUsageMB: 0
            )
        }

        let lastHeartbeat = sharedDefaults.double(forKey: "extension_heartbeat")
        let memoryUsage = sharedDefaults.double(forKey: "extension_memory_mb")

        let gapSeconds = lastHeartbeat > 0
            ? Int(Date().timeIntervalSince1970 - lastHeartbeat)
            : Int.max
        let heartbeatDate = lastHeartbeat > 0 ? Date(timeIntervalSince1970: lastHeartbeat) : .distantPast

        return ExtensionHealthStatus(
            lastHeartbeat: heartbeatDate,
            heartbeatGapSeconds: gapSeconds,
            isHealthy: gapSeconds < 120,
            memoryUsageMB: memoryUsage
        )
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
         Self.usageRecordedNotification].forEach { notification in
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

    @objc private func handleAppDidBecomeActive() {
        let status = AuthorizationCenter.shared.authorizationStatus
        let granted = (status == .approved)
        authorizationGranted = granted
        NSLog("[ScreenTimeService] 🔐 App active - authorization status: \(status.rawValue), granted flag: \(granted)")

        let didSyncUsage = processSharedUsageData(reason: "app_active")
        if didSyncUsage {
            reloadAppUsagesFromPersistence()
        }

    }

    // MARK: - Gap Detection

    func detectUsageGaps() -> [UsageGap] {
        var gaps = [UsageGap]()
        gaps.append(contentsOf: detectNotificationGaps())
        gaps.append(contentsOf: detectHeartbeatGaps())
        gaps.append(contentsOf: detectSessionGaps())
        return gaps.sorted { $0.startTime < $1.startTime }
    }

    func shouldAlertUserAboutGaps() -> Bool {
        let totalLostMinutes = detectUsageGaps().reduce(0) { $0 + $1.durationMinutes }
        return totalLostMinutes > 15
    }

    private func detectNotificationGaps() -> [UsageGap] {
        loadNotificationGapLogs().map { log in
            let endDate = Date(timeIntervalSince1970: log.detectedAt)
            let durationMinutes = max(1, log.missedCount)
            let startDate = endDate.addingTimeInterval(TimeInterval(-durationMinutes * 60))
            return UsageGap(
                startTime: startDate,
                endTime: endDate,
                durationMinutes: durationMinutes,
                detectionMethod: "notification_gap"
            )
        }
    }

    private func detectHeartbeatGaps() -> [UsageGap] {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else { return [] }
        let lastHeartbeat = defaults.double(forKey: "extension_heartbeat")
        guard lastHeartbeat > 0 else { return [] }

        let gapSeconds = Date().timeIntervalSince1970 - lastHeartbeat
        guard gapSeconds > 300 else { return [] }

        return [UsageGap(
            startTime: Date(timeIntervalSince1970: lastHeartbeat),
            endTime: Date(),
            durationMinutes: Int(gapSeconds / 60),
            detectionMethod: "heartbeat_stale"
        )]
    }

    private func detectSessionGaps() -> [UsageGap] {
        let context = PersistenceController.shared.container.viewContext
        let request: NSFetchRequest<UsageRecord> = UsageRecord.fetchRequest()
        let startOfDay = Calendar.current.startOfDay(for: Date())
        request.predicate = NSPredicate(format: "sessionEnd >= %@ OR sessionStart >= %@", startOfDay as NSDate, startOfDay as NSDate)
        request.sortDescriptors = [NSSortDescriptor(key: "sessionEnd", ascending: true)]

        guard let records = try? context.fetch(request), records.count > 1 else {
            return []
        }

        var gaps: [UsageGap] = []

        for index in 0..<(records.count - 1) {
            let current = records[index]
            let next = records[index + 1]

            guard let currentEnd = current.sessionEnd ?? current.sessionStart,
                  let nextStart = next.sessionStart ?? next.sessionEnd else { continue }

            let gapSeconds = nextStart.timeIntervalSince(currentEnd)
            if gapSeconds > 600 {
                gaps.append(UsageGap(
                    startTime: currentEnd,
                    endTime: nextStart,
                    durationMinutes: Int(gapSeconds / 60),
                    detectionMethod: "session_gap"
                ))
            }
        }

        return gaps
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
        case Self.usageRecordedNotification:
            handleUsageSequenceNotification(sharedDefaults: sharedDefaults)
        default:
            #if DEBUG
            print("[ScreenTimeService] Unknown notification received: \(name.rawValue)")
            #endif
            break
        }
    }

    private func handleUsageSequenceNotification(sharedDefaults: UserDefaults) {
        NSLog("[ScreenTimeService] 📨 Received usage sequence notification")

        var currentSequence = sharedDefaults.integer(forKey: "usageNotificationSequence")
        if currentSequence == 0 {
            currentSequence = sharedDefaults.integer(forKey: "notification_sequence")
            if currentSequence > 0 {
                sharedDefaults.set(currentSequence, forKey: "usageNotificationSequence")
            }
        }

        NSLog("[ScreenTimeService] 📨 Current sequence: \(currentSequence), Last received: \(lastReceivedSequence)")

        if currentSequence > 0 && lastReceivedSequence > 0 {
            let missedCount = max(0, currentSequence - lastReceivedSequence - 1)
            NSLog("[ScreenTimeService] 📨 Sequence check result: missed \(missedCount) notifications")

            if missedCount > 0 {
                NSLog("[ScreenTimeService] ⚠️ Detected \(missedCount) missed usage notifications")
                NotificationCenter.default.post(
                    name: .missedUsageNotifications,
                    object: nil,
                    userInfo: ["missed_count": missedCount]
                )
                recordNotificationGap(missedCount: missedCount)
            }
        }

        lastReceivedSequence = currentSequence
        NSLog("[ScreenTimeService] 📨 Processing shared usage data...")
        let didSyncUsage = processSharedUsageData(reason: "usage_notification")
        if didSyncUsage {
            reloadAppUsagesFromPersistence()
        } else {
            NSLog("[ScreenTimeService] 📨 No persisted usage deltas detected")
        }
        NSLog("[ScreenTimeService] 📨 Usage notification processed")
    }

    @discardableResult
    private func processSharedUsageData(reason: String = "manual") -> Bool {
        let persistedApps = usagePersistence.reloadAppsFromDisk()
        guard !persistedApps.isEmpty else { return false }

        var didUpdateUsage = false

        for (logicalID, persistedApp) in persistedApps {
            let previousTotal = Int(appUsages[logicalID]?.totalTime ?? 0)
            if persistedApp.totalSeconds > previousTotal {
                let deltaSeconds = persistedApp.totalSeconds - previousTotal
                let category = AppUsage.AppCategory(rawValue: persistedApp.category) ?? .learning
                persistUsageDelta(
                    logicalID: logicalID,
                    displayName: persistedApp.displayName,
                    category: category,
                    rewardPoints: persistedApp.rewardPoints,
                    deltaSeconds: deltaSeconds,
                    endingAt: persistedApp.lastUpdated
                )
                didUpdateUsage = true
            }

            appUsages[logicalID] = appUsage(from: persistedApp)
            appUsageHistories[logicalID] = persistedApp.dailyHistory
        }

        if didUpdateUsage {
            NSLog("[ScreenTimeService] 🔄 Synced usage from shared defaults (\(reason))")
            // REMOVED: Restart monitoring after usage notification
            // This was causing duplicate threshold events:
            // 1. Extension writes usage → sends usageRecorded notification
            // 2. Main app syncs and restarts monitoring (HERE)
            // 3. Restart re-fires threshold events already fired by extension
            // 4. Extension also sends eventDidReachThreshold notification
            // 5. Result: ChallengeService updated twice for same usage
            //
            // if reason == "usage_notification" && isMonitoring {
            //     NSLog("[ScreenTimeService] 🔁 Restarting monitoring after usage notification (continuous loop)")
            //     NSLog("[ScreenTimeService] 🔁 Creating restart Task...")
            //     Task { @MainActor in
            //         NSLog("[ScreenTimeService] 🔁 INSIDE restart Task - executing...")
            //         await restartMonitoring()
            //         NSLog("[ScreenTimeService] 🔁 Restart Task completed")
            //     }
            //     NSLog("[ScreenTimeService] 🔁 Restart Task created")
            // }
        }

        return didUpdateUsage
    }

    private func recordNotificationGap(missedCount: Int) {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else { return }
        var logs = loadNotificationGapLogs()
        logs.append(NotificationGapLog(detectedAt: Date().timeIntervalSince1970, missedCount: missedCount))

        if logs.count > 20 {
            logs = Array(logs.suffix(20))
        }

        if let data = try? JSONEncoder().encode(logs) {
            defaults.set(data, forKey: notificationGapLogKey)
        }
    }

    private func loadNotificationGapLogs() -> [NotificationGapLog] {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier),
              let data = defaults.data(forKey: notificationGapLogKey),
              let decoded = try? JSONDecoder().decode([NotificationGapLog].self, from: data) else {
            return []
        }
        return decoded
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
                    self.loadCumulativeTracking()
                    NSLog("[ScreenTimeService] 📂 Loaded cumulative tracking for \(self.cumulativeExpectedUsage.count) apps before scheduling")
                    try self.scheduleActivity()
                    self.isMonitoring = true
                    self.startHealthMonitoring()

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
        deviceActivityCenter.stopMonitoring(activityNames)
        stopHealthMonitoring()
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

    /// Force a monitoring restart (stop + reschedule) to recover from gaps.
    func restartMonitoring(reason: String = "manual", force: Bool = false, file: String = #fileID, line: Int = #line) async {
        let callStack = Thread.callStackSymbols.joined(separator: "\n")
        NSLog("[ScreenTimeService] 🔁 restartMonitoring() requested | reason=\(reason) | force=\(force) | caller=\(file):\(line)")

        let now = Date()
        if !force, let lastRestartDate {
            let delta = now.timeIntervalSince(lastRestartDate)
            if delta < minimumAutoRestartInterval {
                NSLog("[ScreenTimeService] 🔁 restartMonitoring() skipped - last restart \(Int(delta))s ago (<\(Int(minimumAutoRestartInterval))s).")
                return
            }
        }

        lastRestartDate = now
        await executeMonitorRestart(reason: reason, callStack: callStack)
        NSLog("[ScreenTimeService] 🔁 restartMonitoring() completed | reason=\(reason)")
    }

    private func scheduleActivity() throws {
        regenerateMonitoredEvents(refreshUsageCache: false)
        try startMonitoringActivity(primaryActivityName)
    }

    private func regenerateMonitoredEvents(refreshUsageCache: Bool) {
        guard !monitoredApplicationsByCategory.isEmpty else {
            #if DEBUG
            print("[ScreenTimeService] ⚠️ No monitored applications available to generate events")
            #endif
            return
        }

        let persistedApps = usagePersistence.reloadAppsFromDisk()
        reconcileCumulativeTrackingWithPersistedUsage(persistedApps)

        var eventIndex = 0

        monitoredEvents = monitoredApplicationsByCategory.reduce(into: [:]) { result, entry in
            let (category, applications) = entry
            guard !applications.isEmpty else { return }
            let categoryThreshold = currentThresholds[category] ?? DateComponents(second: Int(incrementSeconds))
            let incrementValue = max(1, seconds(from: categoryThreshold))

            for app in applications {
                let logicalID = app.logicalID
                let actualTodaySeconds = TimeInterval(persistedApps[logicalID]?.todaySeconds ?? 0)
                let completedIncrements = floor(actualTodaySeconds / incrementValue)
                let nextThreshold = (completedIncrements + 1) * incrementValue

                NSLog("[ScreenTimeService] 📊 Event for \(app.displayName):")
                NSLog("[ScreenTimeService]   Today's usage: \(Int(actualTodaySeconds))s")
                NSLog("[ScreenTimeService]   Increment: \(Int(incrementValue))s")
                NSLog("[ScreenTimeService]   Next threshold (base): \(Int(nextThreshold))s (daily cumulative)")

                for offset in 0..<maxScheduledIncrementsPerApp {
                    let thresholdValue = nextThreshold + (incrementValue * Double(offset))
                    let eventName = DeviceActivityEvent.Name("usage.app.\(eventIndex)")
                    eventIndex += 1

                    #if DEBUG
                    print("[ScreenTimeService]   ↳ Scheduling threshold at \(Int(thresholdValue))s (offset \(offset)) as event \(eventName.rawValue)")
                    #endif

                    result[eventName] = MonitoredEvent(
                        name: eventName,
                        category: category,
                        threshold: DateComponents(second: Int(thresholdValue)),
                        applications: [app],
                        increment: incrementValue
                    )
                }
            }
        }

        NSLog("[ScreenTimeService] ✅ Generated \(monitoredEvents.count) events with incremental thresholds")

        saveEventMappings()

        if refreshUsageCache {
            reloadAppUsagesFromPersistence()
        }
    }

    private func reloadAppUsagesFromPersistence() {
        var refreshedUsages: [String: AppUsage] = [:]
        var refreshedHistories: [String: [UsagePersistence.DailyUsageSummary]] = [:]
        for apps in monitoredApplicationsByCategory.values {
            for app in apps {
                if let persisted = usagePersistence.app(for: app.logicalID) {
                    refreshedUsages[app.logicalID] = appUsage(from: persisted)
                    refreshedHistories[app.logicalID] = persisted.dailyHistory
                    #if DEBUG
                    print("[ScreenTimeService] 📦 Reloaded \(app.displayName): \(persisted.totalSeconds)s total, \(persisted.earnedPoints) pts")
                    #endif
                }
            }
        }
        appUsages = refreshedUsages
        appUsageHistories = refreshedHistories
        notifyUsageChange()
    }

    private func dailyDeviceActivitySchedule() -> DeviceActivitySchedule {
        let startComponents = DateComponents(hour: 0, minute: 0, second: 0)
        let endComponents = DateComponents(hour: 23, minute: 59, second: 59)
        NSLog("[ScreenTimeService] 📅 Creating midnight-to-midnight daily schedule (repeats: true)")
        return DeviceActivitySchedule(
            intervalStart: startComponents,
            intervalEnd: endComponents,
            repeats: true
        )
    }

    private func startMonitoringActivity(_ activity: DeviceActivityName) throws {
        let schedule = dailyDeviceActivitySchedule()

        let events = monitoredEvents.reduce(into: [DeviceActivityEvent.Name: DeviceActivityEvent]()) { result, entry in
            result[entry.key] = entry.value.deviceActivityEvent()
        }

        NSLog("[ScreenTimeService] ▶️ Starting monitoring '\(activity.rawValue)'")
        NSLog("[ScreenTimeService]   Schedule: 00:00:00 → 23:59:59 (repeats daily)")
        NSLog("[ScreenTimeService]   Event count: \(events.count)")
        NSLog("[ScreenTimeService]   Event names: \(events.keys.map { $0.rawValue }.joined(separator: ", "))")

        try deviceActivityCenter.startMonitoring(activity, during: schedule, events: events)

        NSLog("[ScreenTimeService] ✅ Monitoring started successfully")
    }

    private func executeMonitorRestart(reason: String, callStack: String) async {
        NSLog("[ScreenTimeService] 🔁 executeMonitorRestart() ENTRY - reason: \(reason)")
        NSLog("[ScreenTimeService] 🔁 restart call stack:\n\(callStack)")
        let authStatus = AuthorizationCenter.shared.authorizationStatus
        NSLog("[ScreenTimeService] 🔐 Authorization status during restart: \(authStatus.rawValue)")
        if authStatus != .approved {
            NSLog("[ScreenTimeService] ⚠️ Authorization status is \(authStatus.rawValue), proceeding because monitoring is active")
        }

        if isRestarting {
            NSLog("[ScreenTimeService] ⚠️ Restart already in progress, skipping duplicate request")
            return
        }

        isRestarting = true
        defer {
            isRestarting = false
            NSLog("[ScreenTimeService] 🔓 Restart lock released")
        }

        NSLog("[ScreenTimeService] 🔒 Restart lock acquired")
        NSLog("[ScreenTimeService] 🔁 Stopping current monitoring...")
        deviceActivityCenter.stopMonitoring(activityNames)
        NSLog("[ScreenTimeService] ✅ Monitoring stopped")

        NSLog("[ScreenTimeService] 🔁 Regenerating monitored events...")
        regenerateMonitoredEvents(refreshUsageCache: false)
        NSLog("[ScreenTimeService] ✅ Events regenerated (count: \(monitoredEvents.count))")

        do {
            NSLog("[ScreenTimeService] 🔁 Scheduling new activity...")
            try scheduleActivity()
            NSLog("[ScreenTimeService] ✅ Activity scheduled successfully")
            NSLog("[ScreenTimeService] ✅ Monitoring restarted (\(reason))")
        } catch {
            NSLog("[ScreenTimeService] ❌ Failed to restart monitoring (\(reason)): \(error)")
            NSLog("[ScreenTimeService] ❌ Error type: \(type(of: error))")
            NSLog("[ScreenTimeService] ❌ Error details: \(String(describing: error))")
        }

        NSLog("[ScreenTimeService] 🔁 executeMonitorRestart() EXIT")
    }
    
    // MARK: - Data Accessors
    
    func getAppUsages() -> [AppUsage] {
        Array(appUsages.values)
    }

    func getDailyHistory(for logicalID: String) -> [UsagePersistence.DailyUsageSummary] {
        appUsageHistories[logicalID] ?? []
    }

    func getDailyHistory(for token: ApplicationToken) -> [UsagePersistence.DailyUsageSummary] {
        let tokenHash = usagePersistence.tokenHash(for: token)
        guard let logicalID = usagePersistence.logicalID(for: tokenHash) else { return [] }
        return appUsageHistories[logicalID] ?? []
    }

    func getDailyHistories() -> [String: [UsagePersistence.DailyUsageSummary]] {
        appUsageHistories
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

    private func recordUsage(for applications: [MonitoredApplication], duration: TimeInterval, endingAt endDate: Date = Date(), eventTimestamp: Date = Date()) {
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

        // Prune dedup cache periodically
        recentUsageEvents = recentUsageEvents.filter { eventTimestamp.timeIntervalSince($0.value) < 3600 }

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

            if let last = recentUsageEvents[logicalID], eventTimestamp.timeIntervalSince(last) < 55 {
                #if DEBUG
                print("[ScreenTimeService] ⚠️ Deduped \(application.displayName) - last event \(eventTimestamp.timeIntervalSince(last))s ago")
                #endif
                continue
            }
            recentUsageEvents[logicalID] = eventTimestamp
        
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
            let persistedApp = UsagePersistence.PersistedApp(
                logicalID: logicalID,
                displayName: appUsage.appName,
                category: appUsage.category.rawValue,
                rewardPoints: appUsage.rewardPoints,
                totalSeconds: Int(appUsage.totalTime),
                earnedPoints: appUsage.earnedRewardPoints,
                createdAt: appUsage.firstAccess,
                lastUpdated: appUsage.lastAccess,
                todaySeconds: Int(appUsage.todayUsage),
                todayPoints: appUsage.todayPoints
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

    private func persistUsageDelta(logicalID: String,
                                   displayName: String,
                                   category: AppUsage.AppCategory,
                                   rewardPoints: Int,
                                   deltaSeconds: Int,
                                   endingAt: Date) {
        guard deltaSeconds > 0 else { return }

        let context = PersistenceController.shared.container.viewContext
        let deviceID = DeviceModeManager.shared.deviceID

        if let recentRecord = findRecentUsageRecord(
            logicalID: logicalID,
            deviceID: deviceID,
            withinSeconds: sessionAggregationWindowSeconds
        ) {
            recentRecord.sessionEnd = endingAt
            recentRecord.totalSeconds += Int32(deltaSeconds)
            let totalMinutes = Int(recentRecord.totalSeconds / 60)
            recentRecord.earnedPoints = Int32(totalMinutes * rewardPoints)
            recentRecord.isSynced = false
        } else {
            let usageRecord = UsageRecord(context: context)
            usageRecord.recordID = UUID().uuidString
            usageRecord.deviceID = deviceID
            usageRecord.logicalID = logicalID
            usageRecord.displayName = displayName
            usageRecord.category = category.rawValue
            usageRecord.totalSeconds = Int32(deltaSeconds)
            usageRecord.sessionStart = endingAt.addingTimeInterval(-TimeInterval(deltaSeconds))
            usageRecord.sessionEnd = endingAt
            let recordMinutes = Int(deltaSeconds / 60)
            usageRecord.earnedPoints = Int32(recordMinutes * rewardPoints)
            usageRecord.isSynced = false
        }

        do {
            try context.save()
        } catch {
            #if DEBUG
            print("[ScreenTimeService] ⚠️ Failed to persist usage delta for \(logicalID): \(error)")
            #endif
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
        NSLog("[ScreenTimeService] ⏰ Event threshold reached: \(event.rawValue) at \(timestamp)")
        NSLog("[ScreenTimeService] Monitored events count: \(monitoredEvents.count)")
        NSLog("[ScreenTimeService] Looking for event: \(event.rawValue)")

        guard let configuration = monitoredEvents[event] else {
            NSLog("[ScreenTimeService] ❌ No configuration found for event \(event.rawValue)")
            NSLog("[ScreenTimeService] Available events: \(monitoredEvents.keys.map { $0.rawValue })")
            return
        }

        if let lastFire = lastEventFireTimestamps[event],
           timestamp.timeIntervalSince(lastFire) < eventDeduplicationWindow {
            NSLog("[ScreenTimeService] ⚠️ Duplicate threshold \(event.rawValue) detected \(timestamp.timeIntervalSince(lastFire))s after previous fire - ignoring")
            return
        }
        lastEventFireTimestamps[event] = timestamp

        NSLog("[ScreenTimeService] Found configuration for event \(event.rawValue)")
        NSLog("[ScreenTimeService] Category: \(configuration.category.rawValue)")
        NSLog("[ScreenTimeService] Applications: \(configuration.applications.map { $0.displayName })")

        let cumulativeThreshold = seconds(from: configuration.threshold)
        let incrementDuration = max(configuration.increment, 1)

        for app in configuration.applications {
            let logicalID = app.logicalID
            let previousExpected = cumulativeExpectedUsage[logicalID] ?? 0
            cumulativeExpectedUsage[logicalID] = cumulativeThreshold

            NSLog("[ScreenTimeService] 📊 \(app.displayName) cumulative tracking:")
            NSLog("[ScreenTimeService]   Previous: \(Int(previousExpected))s")
            NSLog("[ScreenTimeService]   Current: \(Int(cumulativeThreshold))s")
            NSLog("[ScreenTimeService]   Increment: \(Int(incrementDuration))s")
        }

        saveCumulativeTracking()

        lastEventTimestamp = timestamp

        // FIX: Don't call recordUsage() because it writes to UserDefaults (causing double-write)
        // The extension already wrote to UserDefaults. We only need to update ChallengeService.
        // Update ChallengeService directly for learning apps
        for application in configuration.applications {
            if application.category == .learning {
                let earnedPointsForChallenge = max(0, Int(incrementDuration / 60) * application.rewardPoints)
                Task {
                    await ChallengeService.shared.updateProgressForUsage(
                        appID: application.logicalID,
                        duration: incrementDuration,
                        earnedPoints: earnedPointsForChallenge,
                        deviceID: DeviceModeManager.shared.deviceID
                    )
                }
            }
        }

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

        // Do not force a restart on threshold progression; keeping the interval stable prevents counter resets
    }

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
        result[name] = MonitoredEvent(
            name: name,
            category: category,
            threshold: threshold,
            applications: [],
            increment: seconds(from: threshold)
        )
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
            let persistedApp = UsagePersistence.PersistedApp(
                logicalID: logicalID,
                displayName: appUsage.appName,
                category: appUsage.category.rawValue,
                rewardPoints: appUsage.rewardPoints,
                totalSeconds: Int(appUsage.totalTime),
                earnedPoints: appUsage.earnedRewardPoints,
                createdAt: appUsage.firstAccess,
                lastUpdated: appUsage.lastAccess,
                todaySeconds: Int(appUsage.todayUsage),
                todayPoints: appUsage.todayPoints
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
