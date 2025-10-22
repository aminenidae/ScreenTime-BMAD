import Foundation
import CoreFoundation
import DeviceActivity
import FamilyControls
import ManagedSettings

/// Service to handle Screen Time API functionality while exposing deterministic
/// state for the SwiftUI layer.
@available(iOS 16.0, *)
class ScreenTimeService: NSObject {
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

    // App Group identifier - must match extension
    private let appGroupIdentifier = "group.com.screentimerewards.shared"

    // Shared persistence helper for logical ID-based storage
    private(set) var usagePersistence = UsagePersistence()

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
    private let defaultThreshold = DateComponents(minute: 1)
    private var monitoredEvents: [DeviceActivityEvent.Name: MonitoredEvent] = [:]

    // Timer for continuous tracking - restarts monitoring periodically to reset events
    private var monitoringRestartTimer: Timer?
    private let restartInterval: TimeInterval = 120  // 2 minutes

    // Store category assignments and selection for sharing across ViewModels
    private(set) var categoryAssignments: [ApplicationToken: AppUsage.AppCategory] = [:]
    private(set) var rewardPointsAssignments: [ApplicationToken: Int] = [:]
    private(set) var familySelection: FamilyActivitySelection = .init()

    override private init() {
        deviceActivityCenter = DeviceActivityCenter()
        super.init()
        activityMonitor.delegate = self
        registerForExtensionNotifications()
        loadPersistedAssignments()
    }

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
            return FamilyActivitySelection()
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

        return FamilyActivitySelection()
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
                    startMonitoringRestartTimer()

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
            rewardPoints: 20
        )
        let calculator = AppUsage(
            bundleIdentifier: "com.apple.calculator",
            appName: "Calculator",
            category: .learning,
            totalTime: 600,
            sessions: calculatorSessions,
            firstAccess: now.addingTimeInterval(-172800),
            lastAccess: now.addingTimeInterval(-hour * 6 + 600),
            rewardPoints: 20
        )
        let music = AppUsage(
            bundleIdentifier: "com.apple.Music",
            appName: "Music",
            category: .reward,
            totalTime: halfHour,
            sessions: musicSessions,
            firstAccess: now.addingTimeInterval(-432000),
            lastAccess: now.addingTimeInterval(-halfHour),
            rewardPoints: 10
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

            let displayName = application.localizedDisplayName ?? "Unknown App \(index)"
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
                lastUpdated: existingApp?.lastUpdated ?? now
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

        // CRITICAL FIX: Create one event per app for accurate individual tracking
        // (DeviceActivity has a limit of ~8 events, so this works for small app counts)
        var eventIndex = 0
        monitoredEvents = groupedApplications.reduce(into: [:]) { result, entry in
            let (category, applications) = entry
            guard !applications.isEmpty else {
                #if DEBUG
                print("[ScreenTimeService] No applications in category \(category.rawValue)")
                #endif
                return
            }
            let threshold = providedThresholds[category] ?? defaultThreshold

            // Create separate event for each app
            for app in applications {
                let eventName = DeviceActivityEvent.Name("usage.app.\(eventIndex)")
                eventIndex += 1

                #if DEBUG
                print("[ScreenTimeService] Creating monitored event for app: \(app.displayName)")
                print("[ScreenTimeService] Event name: \(eventName.rawValue)")
                print("[ScreenTimeService] Category: \(category.rawValue)")
                print("[ScreenTimeService] Threshold: \(threshold)")
                #endif

                result[eventName] = MonitoredEvent(
                    name: eventName,
                    category: category,
                    threshold: threshold,
                    applications: [app]  // Single app per event!
                )
            }
        }

        #if DEBUG
        print("[ScreenTimeService] Created \(monitoredEvents.count) monitored events")
        for (name, event) in monitoredEvents {
            print("[ScreenTimeService]   Event: \(name.rawValue) with \(event.applications.count) apps")
        }
        #endif

        // Save event name → logical ID mapping for extension
        saveEventMappings()

        hasSeededSampleData = false

        // Keep existing usage totals for monitored apps (and drop anything no longer selected)
        var refreshedUsages: [String: AppUsage] = [:]
        for apps in groupedApplications.values {
            for app in apps {
                if let existing = appUsages[app.logicalID] {
                    refreshedUsages[app.logicalID] = existing
                } else if let persisted = usagePersistence.app(for: app.logicalID) {
                    refreshedUsages[app.logicalID] = appUsage(from: persisted)
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
        switch category {
        case .learning:
            return 20
        case .reward:
            return 10
        }
    }

    private func appUsage(from persisted: UsagePersistence.PersistedApp) -> AppUsage {
        let category = AppUsage.AppCategory(rawValue: persisted.category) ?? .learning
        let session = AppUsage.UsageSession(startTime: persisted.createdAt, endTime: persisted.lastUpdated)
        return AppUsage(
            bundleIdentifier: persisted.logicalID,
            appName: persisted.displayName,
            category: category,
            totalTime: TimeInterval(persisted.totalSeconds),
            sessions: [session],
            firstAccess: persisted.createdAt,
            lastAccess: persisted.lastUpdated,
            rewardPoints: persisted.rewardPoints
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

        // Create mapping: eventName → (logicalID, rewardPoints, thresholdSeconds)
        var mappings: [String: [String: Any]] = [:]
        for (eventName, event) in monitoredEvents {
            guard let app = event.applications.first else { continue }

            let thresholdSeconds = seconds(from: event.threshold)
            mappings[eventName.rawValue] = [
                "logicalID": app.logicalID,
                "displayName": app.displayName,
                "rewardPoints": app.rewardPoints,
                "thresholdSeconds": Int(thresholdSeconds)
            ]
        }

        if let data = try? JSONSerialization.data(withJSONObject: mappings) {
            sharedDefaults.set(data, forKey: "eventMappings")
            sharedDefaults.synchronize()

            #if DEBUG
            print("[ScreenTimeService] 💾 Saved \(mappings.count) event mappings for extension")
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
         Self.intervalWillEndNotification].forEach { notification in
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
        default:
            #if DEBUG
            print("[ScreenTimeService] Unknown notification received: \(name.rawValue)")
            #endif
            break
        }
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
                if #available(iOS 16.0, *) {
                    try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
                } else {
                    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                        AuthorizationCenter.shared.requestAuthorization { result in
                            switch result {
                            case .success:
                                continuation.resume()
                            case .failure(let error):
                                continuation.resume(throwing: error)
                            }
                        }
                    }
                }
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
                    self.startMonitoringRestartTimer()

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
        stopMonitoringRestartTimer()
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

    // MARK: - Continuous Tracking via Periodic Restarts

    /// Start a timer that periodically restarts monitoring to reset threshold events
    /// This allows continuous tracking beyond the first threshold
    private func startMonitoringRestartTimer() {
        // Stop existing timer if any
        stopMonitoringRestartTimer()

        #if DEBUG
        print("[ScreenTimeService] 🔄 Starting monitoring restart timer (interval: \(restartInterval)s)")
        print("[ScreenTimeService] This enables continuous tracking by resetting events every \(Int(restartInterval/60)) minutes")
        #endif

        monitoringRestartTimer = Timer.scheduledTimer(withTimeInterval: restartInterval, repeats: true) { [weak self] _ in
            guard let self = self, self.isMonitoring else { return }

            #if DEBUG
            print("[ScreenTimeService] ⏰ Timer fired - restarting monitoring to reset events...")
            #endif

            do {
                try self.scheduleActivity()
                #if DEBUG
                print("[ScreenTimeService] ✅ Monitoring restarted successfully")
                #endif
            } catch {
                #if DEBUG
                print("[ScreenTimeService] ❌ Failed to restart monitoring: \(error)")
                #endif
            }
        }
    }

    /// Stop the monitoring restart timer
    private func stopMonitoringRestartTimer() {
        monitoringRestartTimer?.invalidate()
        monitoringRestartTimer = nil

        #if DEBUG
        print("[ScreenTimeService] 🛑 Stopped monitoring restart timer")
        #endif
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
        
        #if DEBUG
        print("[ScreenTimeService] Successfully started monitoring")
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

        currentlyShielded = tokens
        managedSettingsStore.shield.applications = tokens

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
                let usage = AppUsage(
                    bundleIdentifier: logicalID,  // Use logicalID as bundleIdentifier for storage
                    appName: application.displayName,
                    category: application.category,
                    totalTime: duration,
                    sessions: [session],
                    firstAccess: session.startTime,
                    lastAccess: endDate,
                    rewardPoints: application.rewardPoints
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
                lastUpdated: appUsage.lastAccess
            )
            usagePersistence.saveApp(persistedApp)

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
        print("[ScreenTimeService] Monitored events count: \(monitoredEvents.count)")
        print("[ScreenTimeService] Looking for event: \(event.rawValue)")
        #endif
    
        guard let configuration = monitoredEvents[event] else { 
            #if DEBUG
            print("[ScreenTimeService] No configuration found for event \(event.rawValue)")
            print("[ScreenTimeService] Available events: \(monitoredEvents.keys.map { $0.rawValue })")
            #endif
            return 
        }
    
        #if DEBUG
        print("[ScreenTimeService] Found configuration for event \(event.rawValue)")
        print("[ScreenTimeService] Category: \(configuration.category.rawValue)")
        print("[ScreenTimeService] Applications: \(configuration.applications.map { $0.displayName })")
        #endif
    
        let duration = seconds(from: configuration.threshold)
        #if DEBUG
        print("[ScreenTimeService] Recording usage with duration: \(duration) seconds")
        #endif
        recordUsage(for: configuration.applications, duration: duration, endingAt: timestamp)
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
        let usage = AppUsage(
            bundleIdentifier: storageKey,
            appName: appName,
            category: category,
            totalTime: duration,
            sessions: [session],
            firstAccess: session.startTime,
            lastAccess: endDate,
            rewardPoints: rewardPoints
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

}  // Closing brace for ScreenTimeService class

extension ScreenTimeService: ScreenTimeActivityMonitorDelegate {
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
}

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

extension ScreenTimeService {
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
            let usage = AppUsage(
                bundleIdentifier: logicalID,
                appName: "Unknown App",
                category: .learning,
                totalTime: additionalSeconds,
                sessions: [session],
                firstAccess: session.startTime,
                lastAccess: now,
                rewardPoints: rewardPointsPerMinute
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
                lastUpdated: appUsage.lastAccess
            )
            usagePersistence.saveApp(persistedApp)
        }
        
        // Notify that usage has changed
        notifyUsageChange()
    }
}
