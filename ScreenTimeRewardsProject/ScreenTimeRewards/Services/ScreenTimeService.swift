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
    /// Suppresses MONITORING_STOP/START logs when called internally by restart/reload paths
    private var isInternalRestart = false
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

    // Diagnostic polling timer
    private var diagnosticPollingTimer: Timer?

    private var diagnosticPollCount = 0
    private var lastPolledUsageValues: [String: Int] = [:]  // logicalID -> todaySeconds

    // MARK: - Monitoring Lifecycle Log

    private static let lifecycleDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    /// Write to the dedicated monitoring lifecycle log (shared with extension via app group)
    private func lifecycleLog(_ message: String) {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else { return }
        let timestamp = Self.lifecycleDateFormatter.string(from: Date())
        let entry = "[\(timestamp)] \(message)\n"

        var log = defaults.string(forKey: "monitoring_lifecycle_log") ?? ""
        log.append(entry)

        if log.utf8.count > 100_000 {
            let lines = log.split(separator: "\n", omittingEmptySubsequences: true)
            let kept = lines.suffix(400)
            log = kept.joined(separator: "\n") + "\n"
        }

        defaults.set(log, forKey: "monitoring_lifecycle_log")
    }

    /// Write to midnight diagnostic log (only when active between midnight and first scheduleActivity)
    private func midnightDiagnosticLog(_ message: String) {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else { return }
        guard defaults.bool(forKey: "midnight_diagnostic_active") else { return }
        let timestamp = Self.lifecycleDateFormatter.string(from: Date())
        let entry = "[\(timestamp)] [SERVICE] \(message)\n"

        var log = defaults.string(forKey: "midnight_diagnostic_log") ?? ""
        log.append(entry)

        if log.utf8.count > 15_000 {
            let lines = log.split(separator: "\n", omittingEmptySubsequences: true)
            let kept = lines.suffix(75)
            log = kept.joined(separator: "\n") + "\n"
        }

        defaults.set(log, forKey: "midnight_diagnostic_log")
    }

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
            let tokens = applications.map { $0.token }
            if #available(iOS 17.4, *) {
                return DeviceActivityEvent(
                    applications: Set(tokens),
                    threshold: threshold,
                    includesPastActivity: true
                )
            } else {
                return DeviceActivityEvent(
                    applications: Set(tokens),
                    threshold: threshold
                )
            }
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

    // MARK: - Stable Hash Function
    /// DJB2 hash - deterministic across app launches (unlike Swift's .hashValue)
    /// Swift's .hashValue changes on every app launch for security reasons.
    /// This caused usage inflation as iOS saw "new" event names on each launch.
    private func stableHash(_ string: String) -> UInt64 {
        var hash: UInt64 = 5381
        for char in string.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(char)
        }
        return hash
    }

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

        // Set up BlockingCoordinator with reference to this service
        BlockingCoordinator.shared.setScreenTimeService(self)

        // Restore web restrictions (blocked websites, browsers) from persistence
        restoreWebRestrictions()

        // Apply adult content filter if this is a child device (always-on)
        applyAdultContentFilterIfNeeded()

        #if DEBUG
        print("=" + String(repeating: "=", count: 50))
        print("[ScreenTimeService] 🚀 SERVICE INITIALIZED")
        print("[ScreenTimeService] appUsages count: \(appUsages.count)")
        print("[ScreenTimeService] isMonitoring: \(isMonitoring)")
        print("[ScreenTimeService] adultContentFilter: \(isAdultContentFilterEnabled ? "ENABLED" : "disabled")")
        print("=" + String(repeating: "=", count: 50))
        #endif
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

        // Sync extension data written while app was force-closed
        // This catches any thresholds that fired while the main app wasn't running
        if let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) {
            #if DEBUG
            print("[ScreenTimeService] 🔄 Syncing extension data written during force-close...")
            #endif
            readExtensionUsageData(defaults: sharedDefaults)

            // DIAGNOSTIC: Report notification delivery stats on launch
            #if DEBUG
            let sentSeq = sharedDefaults.integer(forKey: "darwin_notification_seq_sent")
            let receivedSeq = sharedDefaults.integer(forKey: "darwin_notification_seq_received")
            let lastSentTime = sharedDefaults.double(forKey: "darwin_notification_last_sent")
            let lastReceivedTime = sharedDefaults.double(forKey: "darwin_notification_last_received")

            print("[ScreenTimeService] 📊 === DARWIN NOTIFICATION DIAGNOSTICS ===")
            print("[ScreenTimeService] 📤 Total SENT by extension: \(sentSeq)")
            print("[ScreenTimeService] 📥 Total RECEIVED by main app: \(receivedSeq)")

            if sentSeq > receivedSeq {
                let missed = sentSeq - receivedSeq
                print("[ScreenTimeService] ⚠️ MISSED NOTIFICATIONS: \(missed)")
                print("[ScreenTimeService] ℹ️ This is expected when running from Xcode - Darwin notifications")
                print("[ScreenTimeService]    from extension process may not be delivered to debugged app.")
                print("[ScreenTimeService] ℹ️ In production (TestFlight/App Store), notifications work correctly.")
            } else if sentSeq == receivedSeq && sentSeq > 0 {
                print("[ScreenTimeService] ✅ All notifications delivered successfully!")
            } else if sentSeq == 0 {
                print("[ScreenTimeService] ℹ️ No notifications sent yet (extension hasn't fired thresholds)")
            }

            if lastSentTime > 0 {
                let sentDate = Date(timeIntervalSince1970: lastSentTime)
                print("[ScreenTimeService] 📤 Last sent: \(sentDate)")
            }
            if lastReceivedTime > 0 {
                let receivedDate = Date(timeIntervalSince1970: lastReceivedTime)
                print("[ScreenTimeService] 📥 Last received: \(receivedDate)")
            }
            print("[ScreenTimeService] 📊 ========================================")
            #endif
        }

        // Load FamilyActivitySelection if available
        let restoredSelection = restoreFamilySelection()
        if !restoredSelection.applications.isEmpty {
            self.familySelection = restoredSelection

            // RECONCILIATION: Clean up UsagePersistence to match restored selection
            // This removes stale entries that accumulated from past deletions
            let validLogicalIDs = Set(restoredSelection.applicationTokens.compactMap { getLogicalID(for: $0) })
            usagePersistence.reconcileWithSelection(validLogicalIDs: validLogicalIDs)

            // NOTE: CloudKit reconciliation (uploadAppConfigurationsToParent) is NOT called here.
            // The startup flow in ScreenTimeRewardsApp.swift already handles this — it runs
            // backfillAppConfigurations then uploadAppConfigurationsToParent in sequence.
            // Calling it here too would create duplicate records that immediately get deduped.

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
            if let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) {
                let wasMonitoring = sharedDefaults.bool(forKey: "wasMonitoringActive")

                // RECOVERY: If we have a valid selection but flag is false, assume user wants monitoring
                // This recovers from the restartMonitoring() bug that incorrectly set the flag to false
                if !wasMonitoring && !restoredSelection.applications.isEmpty {
                    #if DEBUG
                    print("[ScreenTimeService] 🔧 RECOVERY: Found valid selection (\(restoredSelection.applications.count) apps) but wasMonitoringActive=false")
                    print("[ScreenTimeService] 🔧 RECOVERY: Auto-recovering by setting wasMonitoringActive=true")
                    #endif
                    sharedDefaults.set(true, forKey: "wasMonitoringActive")
                }

                if sharedDefaults.bool(forKey: "wasMonitoringActive") {
                #if DEBUG
                print("[ScreenTimeService] 🔄 Monitoring was previously active - restarting automatically...")
                #endif

                // Check if monitoring is already active at the OS level
                // DeviceActivity monitoring persists across app/extension process deaths
                // Calling startMonitoring() unnecessarily creates a new session,
                // which causes iOS to fire catch-up events for ALL cumulative daily usage (phantom floods)
                let registeredActivities = deviceActivityCenter.activities
                #if DEBUG
                print("[ScreenTimeService] 📊 Currently registered activities with iOS: \(registeredActivities.map { $0.rawValue })")
                #endif

                if registeredActivities.contains(activityName) {
                    // Monitoring already active at OS level — don't restart
                    isMonitoring = true
                    lifecycleLog("MONITORING_ALIVE — OS confirms active, skipping restart (app launch)")
                    #if DEBUG
                    print("[ScreenTimeService] ✅ Monitoring already active at OS level — skipping restart to prevent phantom floods")
                    #endif

                    // Check midnight_pending even when monitoring is alive.
                    // After midnight, thresholds become stale (yesterday's ranges
                    // don't cover today's 0 cumulative) and SKIP_MIDNIGHT blocks
                    // all events. Must restart for fresh thresholds.
                    // This check runs at init (before scenePhase .active) to catch
                    // brief app opens where checkMonitoringHealth() never fires.
                    if let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier),
                       sharedDefaults.bool(forKey: "midnight_pending_refresh") {
                        lifecycleLog("MIDNIGHT_PENDING — detected during init, restarting for fresh thresholds")
                        #if DEBUG
                        print("[ScreenTimeService] 🌙 Midnight pending refresh detected at init — triggering restart")
                        #endif
                        // Refresh timestamp so SKIP_MIDNIGHT's 2h window anchors to NOW, not
                        // midnight. Prevents yesterday's residual from bypassing the expired
                        // safety timeout when BGTask missed and app opens late (e.g. 4am > 2h).
                        sharedDefaults.set(Date().timeIntervalSince1970, forKey: "midnight_pending_timestamp")
                        Task { [weak self] in
                            await self?.restartMonitoring(reason: "midnight pending refresh (init)")
                        }
                    }
                } else {
                    // Monitoring genuinely dead — restart needed
                    // Smart threshold filtering in scheduleActivity() prevents catch-up floods
                    do {
                        try scheduleActivity()
                        isMonitoring = true
                        lifecycleLog("MONITORING_RECOVERED — was dead, restarted on app launch")

                        #if DEBUG
                        print("[ScreenTimeService] Monitoring restarted (was genuinely dead)")
                        #endif
                    } catch {
                        // CRITICAL: Reset state on failure to prevent blocking manual start later
                        isMonitoring = false

                        #if DEBUG
                        print("[ScreenTimeService] ❌ Failed to restart monitoring: \(error)")
                        print("[ScreenTimeService] ⚠️ Reset isMonitoring to false - user must start manually")
                        #endif
                    }
                }
            } else {
                #if DEBUG
                print("[ScreenTimeService] ℹ️ Monitoring was not previously active - user must start manually")
                #endif
            }
            }  // Close: if let sharedDefaults
        } else {
            #if DEBUG
            print("[ScreenTimeService] ℹ️ No persisted selection found - starting fresh")
            #endif
        }

        // Debug summary at launch disabled to reduce log noise
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
        print("[ScreenTimeService] Configuring monitoring with \(selection.applications.count) apps, \(categoryAssignments.count) categories, \(rewardPoints.count) reward points")
        #endif

        // Use sorted applications to ensure consistent iteration order
        let sortedApplications = selection.sortedApplications(using: usagePersistence)
    
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
            } else {
                // Fallback: auto-categorize by bundle ID or display name
                if let bundleId = bundleIdentifier, !bundleId.isEmpty {
                    category = categorizeApp(bundleIdentifier: bundleId)
                } else {
                    category = categorizeApp(bundleIdentifier: displayName.lowercased())
                }
            }
            
            // Use user-assigned reward points if available, otherwise use defaults
            let points: Int
            if let assignedPoints = rewardPoints[token] {
                points = assignedPoints
            } else {
                points = getDefaultRewardPoints(for: category)
            }

            // Resolve logical ID (stable across launches) and token hash
            let mapping = usagePersistence.resolveLogicalID(
                for: token,
                bundleIdentifier: bundleIdentifier,
                displayName: displayName
            )
            let logicalID = mapping.logicalID
            let tokenArchiveHash = mapping.tokenHash


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
            
            // CRITICAL FIX: Preserve custom displayName if it exists and is not a default "Unknown App" name
            // This prevents overwriting user-entered names on app restart
            let finalDisplayName: String
            if let existing = existingApp,
               !existing.displayName.isEmpty,
               !existing.displayName.hasPrefix("Unknown App") {
                // Preserve the custom name
                finalDisplayName = existing.displayName
                #if DEBUG
                print("[ScreenTimeService]   ✅ Preserving custom name: '\(finalDisplayName)'")
                #endif
            } else {
                // Use the default name for new apps or apps with default names
                finalDisplayName = displayName
            }
            
            let persistedApp = UsagePersistence.PersistedApp(
                logicalID: logicalID,
                displayName: finalDisplayName,
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

        }

        #if DEBUG
        // Summary log instead of per-app verbosity
        for (category, apps) in groupedApplications {
            let names = apps.map { $0.displayName }.joined(separator: ", ")
            print("[ScreenTimeService] \(category.rawValue): \(apps.count) apps (\(names))")
        }
        #endif

        // INITIAL THRESHOLD TEMPLATE (1-60 per app):
        // Creates a base set of threshold events that scheduleActivity() will rebuild
        // with a SLIDING WINDOW based on current usage. The window shifts:
        //   0 min usage → min.1-60, 45 min → min.46-105, 100 min → min.101-160
        // Always exactly 60 thresholds per app, staying under iOS ~500 total limit.
        // FIX: Use stable logicalID.hashValue instead of sequential eventIndex to prevent
        // usage doubling when apps are reordered (e.g., when adding a new app)
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

            // Create threshold events per app with STATIC minute thresholds
            // iOS automatically skips thresholds that already fired today
            // Using static thresholds avoids mismatch between our persistence and iOS's internal counter
            // NOTE: iOS silently drops events when too many are registered (limit ~500 total)
            // With 60 events per app: 5 apps = 300 events (safe), 8 apps = 480 events (safe)
            for app in applications {
                let startMinute = 1   // Always start at 1 minute
                let endMinute = 60    // 1 hour - reliable tracking within iOS limits
                // Use stable app identifier instead of sequential index to prevent
                // usage doubling when app list order changes
                // NOTE: Using DJB2 hash instead of Swift's .hashValue because
                // .hashValue is NOT stable across app launches (changes every time!)
                let stableAppID = stableHash(app.logicalID)

                #if DEBUG
                print("[ScreenTimeService]   App: \(app.displayName) (stableID: \(stableAppID))")
                print("[ScreenTimeService]     Thresholds: \(startMinute) to \(endMinute) min (static)")
                #endif

                for minuteNumber in startMinute...endMinute {
                    let eventName = DeviceActivityEvent.Name("usage.app.\(stableAppID).min.\(minuteNumber)")
                    let threshold = DateComponents(minute: minuteNumber)

                    result[eventName] = MonitoredEvent(
                        name: eventName,
                        category: category,
                        threshold: threshold,
                        applications: [app]
                    )
                }
            }
        }

        #if DEBUG
        let totalEvents = monitoredEvents.count
        print("[ScreenTimeService] Created \(totalEvents) threshold event templates (60 per app, sliding window applied in scheduleActivity)")
        #endif

        // Save event name → logical ID mapping for extension
        saveEventMappings()

        // Clean up orphaned extension keys for apps that are no longer monitored
        // This fixes stale data that causes phantom/inflated usage when apps are removed then re-added
        let currentLogicalIDs = Set(groupedApplications.values.flatMap { $0 }.map { $0.logicalID })
        cleanupOrphanedExtensionKeys(currentLogicalIDs: currentLogicalIDs)

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
                }
            }
        }
        appUsages = refreshedUsages
        notifyUsageChange()

        if isMonitoring {
            lifecycleLog("MONITORING_RELOAD — threshold refresh")
            isInternalRestart = true
            deviceActivityCenter.stopMonitoring([activityName])
            do {
                try scheduleActivity()
            } catch {
                lifecycleLog("MONITORING_RELOAD_FAILED — \(error.localizedDescription)")
                #if DEBUG
                print("Failed to reschedule monitoring: \(error)")
                #endif
            }
            isInternalRestart = false
        }
    }
    
    private func getDefaultRewardPoints(for category: AppUsage.AppCategory) -> Int {
        // Use a single default so every new app starts at 10 pts/min
        return 10
    }

    /// Get existing today's usage in minutes for an app (reads from extension's primitive keys)
    /// FIX: Also checks if the data is from today - returns 0 if it's stale data from a previous day
    private func getExistingTodayUsageMinutes(for logicalID: String) -> Int {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else { return 0 }

        // First try extension's primitive keys
        let todayKey = "usage_\(logicalID)_today"
        let resetKey = "usage_\(logicalID)_reset"
        let todaySeconds = defaults.integer(forKey: todayKey)

        if todaySeconds > 0 {
            // FIX: Check if this data is actually from today
            let lastReset = defaults.double(forKey: resetKey)
            let startOfToday = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970

            if lastReset < startOfToday {
                // Data is stale (from yesterday or earlier) - return 0
                #if DEBUG
                print("[ScreenTimeService] ⚠️ Stale today data for \(logicalID): lastReset=\(lastReset), startOfToday=\(startOfToday)")
                #endif
                return 0
            }

            return todaySeconds / 60
        }

        // Fallback to persisted data - also check lastResetDate
        if let persisted = usagePersistence.app(for: logicalID) {
            let startOfToday = Calendar.current.startOfDay(for: Date())
            if persisted.lastResetDate < startOfToday {
                // Stale data from yesterday or earlier
                return 0
            }
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

        // CRITICAL FIX: Clean up all old event mappings before writing new ones
        // This prevents stale mappings from threshold changes (240→60)
        let allKeys = Array(sharedDefaults.dictionaryRepresentation().keys)
        var cleanedCount = 0
        for key in allKeys where key.hasPrefix("map_usage.app.") {
            sharedDefaults.removeObject(forKey: key)
            cleanedCount += 1
        }
        #if DEBUG
        if cleanedCount > 0 {
            print("[ScreenTimeService] 🧹 Cleaned \(cleanedCount) old event mapping keys before saving new ones")
        }
        #endif

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
            // Add category for extension to detect reward apps and handle time expiration
            sharedDefaults.set(app.category.rawValue, forKey: "map_\(eventName.rawValue)_category")
            // Also write using logicalID key for ExtensionCloudKitSync lookup
            // (ExtensionCloudKitSync reads category by logicalID, not eventName)
            sharedDefaults.set(app.category.rawValue, forKey: "map_\(app.logicalID)_category")
            // Also write display name using logicalID key for ExtensionCloudKitSync lookup
            // (Required for parent app to show real app names instead of "Privacy Protected App #X")
            sharedDefaults.set(app.displayName, forKey: "map_\(app.logicalID)_name")
            // Store serialized token so extension can rebuild DeviceActivityEvent objects
            // without the main app — needed for extension-side sliding window refresh.
            // Written once per app (overwrites are harmless, token is stable).
            if let tokenData = try? PropertyListEncoder().encode(app.token) {
                sharedDefaults.set(tokenData, forKey: "app_token_\(app.logicalID)")
            }
        }

        if let data = try? JSONSerialization.data(withJSONObject: mappings) {
            sharedDefaults.set(data, forKey: "eventMappings")

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

        switch name {
        case Self.eventDidReachNotification:
            if let eventRaw {
                handleEventThresholdReached(DeviceActivityEvent.Name(eventRaw), timestamp: timestamp)
            }
        case Self.eventWillReachNotification:
            if let eventRaw {
                handleEventWillReachThresholdWarning(DeviceActivityEvent.Name(eventRaw))
            }
        case Self.intervalDidStartNotification:
            if let activityRaw {
                handleIntervalDidStart(for: DeviceActivityName(activityRaw))
            }
        case Self.intervalDidEndNotification:
            if let activityRaw {
                handleIntervalDidEnd(for: DeviceActivityName(activityRaw))
            }
        case Self.intervalWillStartNotification:
            if let activityRaw {
                handleIntervalWillStartWarning(for: DeviceActivityName(activityRaw))
            }
        case Self.intervalWillEndNotification:
            if let activityRaw {
                handleIntervalWillEndWarning(for: DeviceActivityName(activityRaw))
            }
        case Self.extensionUsageRecordedNotification:
            // Track received sequence for diagnostic comparison
            let receivedSeq = sharedDefaults.integer(forKey: "darwin_notification_seq_received")
            let newReceivedSeq = receivedSeq + 1
            sharedDefaults.set(newReceivedSeq, forKey: "darwin_notification_seq_received")
            sharedDefaults.set(Date().timeIntervalSince1970, forKey: "darwin_notification_last_received")

            print("[ScreenTimeService] 📡 Darwin notification received (#\(newReceivedSeq)) - triggering sync")
            handleExtensionUsageRecorded(defaults: sharedDefaults)

        default:
            break
        }
    }

    // MARK: - Extension Usage Update Handler (240 Static Thresholds)

    /// Handle usage recorded notification from extension
    /// With 240 static thresholds (1min, 2min, ... 240min), NO restart is needed!
    /// Each threshold fires once when cumulative usage reaches that minute.
    private func handleExtensionUsageRecorded(defaults: UserDefaults) {
        print("[ScreenTimeService] 🔄 Syncing extension usage data...")
        
        // Read updated usage data from extension's primitive keys
        readExtensionUsageData(defaults: defaults)

        // Clear any re-arm flags (legacy from old single-threshold approach)
        for (logicalID, _) in appUsages {
            let rearmKey = "rearm_\(logicalID)_requested"
            if defaults.bool(forKey: rearmKey) {
                defaults.set(false, forKey: rearmKey)
                clearRearmFlag(for: logicalID, defaults: defaults)
            }
        }

        // Notify UI of usage updates
        notifyUsageChange()

        // Trigger real-time CloudKit sync for usage data (throttled to 30s)
        Task { @MainActor in
            RealTimeSyncCoordinator.shared.triggerUsageDataSync()
        }

        // Immediately refresh blocking states when usage is recorded
        Task { @MainActor in
            BlockingCoordinator.shared.refreshAllBlockingStates()
        }
    }

    /// Read usage data from extension's primitive keys
    /// Read extension usage data and sync to persistence.
    /// NOTE: Staleness is handled by forceResetAllDailyCounters (v5 migration) and
    /// resetDailyCounters (day change). This function trusts extension data for real-time sync.
    private func readExtensionUsageData(defaults: UserDefaults) {
        // DEFENSIVE: If appUsages is empty, load from persistence first
        // This prevents data loss when sync happens before apps are loaded
        if appUsages.isEmpty {
            print("⚠️ [ScreenTimeService] appUsages is empty - loading from persistence first")
            let apps = usagePersistence.loadAllApps()
            self.appUsages = apps.reduce(into: [:]) { dict, pair in
                let (logicalID, persistedApp) = pair
                dict[logicalID] = appUsage(from: persistedApp)
            }
            print("✅ [ScreenTimeService] Loaded \(appUsages.count) apps from persistence")
        }

        // Track sync statistics for summary log
        var syncedApps: [(name: String, delta: Int)] = []
        var unchangedCount = 0

        // Compute todayDateString once for all apps (used by correction + isFromToday check)
        let todayDateString: String = {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.string(from: Date())
        }()

        for (logicalID, var usage) in appUsages {
            // Read from PROTECTED ext_ keys (SET semantics - source of truth)
            // These keys use max(current, threshold) logic, preventing phantom inflation
            let extTodayKey = "ext_usage_\(logicalID)_today"
            let extTotalKey = "ext_usage_\(logicalID)_total"
            let extDateKey = "ext_usage_\(logicalID)_date"

            // 4th correction path: Apply pending catchup_max corrections from extension burst handling.
            // This runs on every foreground (via refreshFromExtension), much more reliable than
            // waiting for extension events to trigger correction.
            // UP-only: only increase usage to match iOS ground truth, never decrease
            // Skip for Reward apps — they're protected by SKIP_SHIELDED in extension,
            // so any catchup_max for a reward app is phantom (from catch-up bursts).
            let catchupMaxKey = "catchup_max_\(logicalID)"
            let catchupMax = defaults.integer(forKey: catchupMaxKey)
            if catchupMax > 0 {
                if usage.category == .reward {
                    #if DEBUG
                    print("[ScreenTimeService] CATCHUP_SKIP_REWARD \(logicalID.prefix(8))... clearing phantom catchup_max=\(catchupMax)s")
                    #endif
                    defaults.removeObject(forKey: catchupMaxKey)
                } else {
                    let currentToday = defaults.integer(forKey: extTodayKey)
                    if catchupMax > currentToday {
                        let correction = catchupMax - currentToday
                        defaults.set(catchupMax, forKey: extTodayKey)
                        defaults.set(catchupMax, forKey: "usage_\(logicalID)_today")
                        let currentTotal = defaults.integer(forKey: extTotalKey)
                        defaults.set(max(0, currentTotal + correction), forKey: extTotalKey)
                        defaults.set(max(0, currentTotal + correction), forKey: "usage_\(logicalID)_total")
                        #if DEBUG
                        print("[ScreenTimeService] CATCHUP_CORRECTION \(logicalID.prefix(8))... \(currentToday)s → \(catchupMax)s (+\(correction)s)")
                        #endif
                    }
                    // ALWAYS set date when catchup_max exists — value may already match but date could be missing
                    defaults.set(todayDateString, forKey: extDateKey)
                    defaults.set(Date().timeIntervalSince1970, forKey: "ext_usage_\(logicalID)_timestamp")
                    defaults.removeObject(forKey: catchupMaxKey)
                }
            }

            // Safety: ensure date is set for any non-zero ext_usage (covers calibration reset edge case)
            if defaults.integer(forKey: extTodayKey) > 0 && defaults.string(forKey: extDateKey) == nil {
                defaults.set(todayDateString, forKey: extDateKey)
            }

            let extTodaySeconds = defaults.integer(forKey: extTodayKey)
            let extTotalSeconds = defaults.integer(forKey: extTotalKey)
            let extDateString = defaults.string(forKey: extDateKey)

            if extTodaySeconds > 0 || extTotalSeconds > 0 {
                // Update in-memory usage - totalTime is the cumulative value
                usage.totalTime = TimeInterval(extTotalSeconds)
                appUsages[logicalID] = usage

                // Also sync to usagePersistence so UI snapshots show correct data
                if var persistedApp = usagePersistence.app(for: logicalID) {
                    // Check if ext_ data is from today using the date string
                    let isFromToday = extDateString == todayDateString

                    // Trust extension as source of truth for today's usage
                    if isFromToday {
                        let deltaSeconds = extTodaySeconds - persistedApp.todaySeconds

                        // FIX: Archive yesterday's data before overwriting if day changed
                        // This ensures dailyHistory gets populated for historical charts
                        let calendar = Calendar.current
                        let today = calendar.startOfDay(for: Date())
                        if !calendar.isDate(persistedApp.lastResetDate, inSameDayAs: today) {
                            // Day changed - archive previous day's data before resetting
                            if persistedApp.todaySeconds > 0 || persistedApp.todayPoints > 0 {
                                let summary = UsagePersistence.DailyUsageSummary(
                                    date: persistedApp.lastResetDate,
                                    seconds: persistedApp.todaySeconds,
                                    points: persistedApp.todayPoints,
                                    hourlySeconds: persistedApp.todayHourlySeconds,
                                    hourlyPoints: persistedApp.todayHourlyPoints
                                )
                                persistedApp.dailyHistory.append(summary)

                                // Cleanup: keep only last 30 days
                                if let cutoff = calendar.date(byAdding: .day, value: -30, to: today) {
                                    persistedApp.dailyHistory.removeAll { $0.date < cutoff }
                                }

                                #if DEBUG
                                print("[ScreenTimeService] 📅 Archived \(persistedApp.displayName): \(persistedApp.todaySeconds)s from \(persistedApp.lastResetDate)")
                                #endif
                            }

                            // Reset hourly data for new day
                            persistedApp.todayHourlySeconds = nil
                            persistedApp.todayHourlyPoints = nil
                        }

                        if extTodaySeconds != persistedApp.todaySeconds {
                            // Track for summary log
                            syncedApps.append((name: persistedApp.displayName, delta: deltaSeconds))

                            persistedApp.todaySeconds = extTodaySeconds
                            persistedApp.totalSeconds = max(extTotalSeconds, persistedApp.totalSeconds)
                            persistedApp.lastUpdated = Date()
                            persistedApp.lastResetDate = Calendar.current.startOfDay(for: Date())

                            // Read hourly breakdown directly from extension's UserDefaults
                            // The extension tracks usage by hour correctly, so we just copy it
                            var hourlySecondsFromExtension = Array(repeating: 0, count: 24)
                            for hour in 0..<24 {
                                hourlySecondsFromExtension[hour] = defaults.integer(forKey: "ext_usage_\(logicalID)_hourly_\(hour)")
                            }
                            persistedApp.todayHourlySeconds = hourlySecondsFromExtension

                            usagePersistence.saveApp(persistedApp)

                            // Also create/update Core Data UsageRecord for CloudKit sync
                            // This ensures parent devices can see child usage data
                            syncUsageRecordFromExtensionData(
                                logicalID: logicalID,
                                displayName: persistedApp.displayName,
                                category: usage.category,
                                todaySeconds: extTodaySeconds,
                                todayPoints: persistedApp.todayPoints
                            )
                        } else {
                            unchangedCount += 1
                        }
                    }
                }
            }
        }

        // Print summary log
        #if DEBUG
        if !syncedApps.isEmpty || unchangedCount > 0 {
            let syncSummary = syncedApps.map { "\($0.name): \($0.delta > 0 ? "+" : "")\($0.delta)s" }.joined(separator: ", ")
            if syncedApps.isEmpty {
                print("[ScreenTimeService] 📊 No changes, \(unchangedCount) apps unchanged")
            } else {
                print("[ScreenTimeService] 📊 Synced \(syncedApps.count) app(s): \(syncSummary) | \(unchangedCount) unchanged")
            }
        }
        #endif
    }

    // MARK: - UsageRecord Sync from Extension Data

    /// Create or update UsageRecord Core Data entity from extension usage data
    /// Called by readExtensionUsageData() to ensure usage data is persisted for CloudKit sync
    ///
    /// SAFEGUARDS:
    /// - Only runs if device is paired with parent
    /// - Finds ANY record for app on given day (prevents duplicates)
    /// - Updates existing record instead of creating duplicates
    /// - Only saves if values actually changed (minimizes Core Data writes)
    private func syncUsageRecordFromExtensionData(
        logicalID: String,
        displayName: String,
        category: AppUsage.AppCategory,
        todaySeconds: Int,
        todayPoints: Int
    ) {
        // SAFEGUARD 1: Only create records if device is paired with parent (supports multi-parent format)
        guard !DevicePairingService.shared.getPairedParents().isEmpty else {
            return  // Not paired, skip record creation
        }

        // SAFEGUARD 2: Only create records for apps with actual usage
        guard todaySeconds > 0 else {
            return  // No usage to record
        }

        let context = PersistenceController.shared.container.viewContext
        let deviceID = DeviceModeManager.shared.deviceID

        // SAFEGUARD 3: Find ANY existing record for this app TODAY
        // Uses date range to catch records created by BOTH code paths:
        // - Extension-based: sessionStart = start of day (00:00)
        // - Threshold-based: sessionStart = actual usage time (e.g., 14:32)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!

        let fetchRequest: NSFetchRequest<UsageRecord> = UsageRecord.fetchRequest()
        fetchRequest.predicate = NSPredicate(
            format: "logicalID == %@ AND deviceID == %@ AND sessionStart >= %@ AND sessionStart < %@",
            logicalID,
            deviceID,
            today as NSDate,
            tomorrow as NSDate
        )
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "sessionStart", ascending: false)]
        fetchRequest.fetchLimit = 1

        do {
            let existing = try context.fetch(fetchRequest).first

            if let record = existing {
                // SAFEGUARD 4: Update existing record ONLY if values changed
                // Minimizes Core Data writes and CloudKit uploads
                if record.totalSeconds != Int32(todaySeconds) ||
                   record.earnedPoints != Int32(todayPoints) ||
                   record.displayName != displayName {
                    record.totalSeconds = Int32(todaySeconds)
                    record.earnedPoints = Int32(todayPoints)
                    record.displayName = displayName  // Update custom name if changed
                    record.sessionEnd = Date()
                    record.isSynced = false  // Mark for re-upload to CloudKit

                    try context.save()
                }
            } else {
                // Create new record for today
                let record = UsageRecord(context: context)
                record.recordID = UUID().uuidString
                record.deviceID = deviceID
                record.logicalID = logicalID
                record.displayName = displayName
                record.category = category.rawValue
                record.totalSeconds = Int32(todaySeconds)
                record.sessionStart = today  // Use start of day for consistency
                record.sessionEnd = Date()
                record.earnedPoints = Int32(todayPoints)
                record.isSynced = false  // Mark for CloudKit upload

                try context.save()

                #if DEBUG
                print("[ScreenTimeService] 💾 Created NEW UsageRecord from extension:")
                print("   App: \(displayName)")
                print("   Usage: \(todaySeconds)s (\(todaySeconds/60)min)")
                print("   Points: \(todayPoints)pts")
                print("   Category: \(category.rawValue)")
                print("   Ready for CloudKit upload")
                #endif
            }
        } catch {
            #if DEBUG
            print("[ScreenTimeService] ❌ Failed to sync UsageRecord from extension data:")
            print("   App: \(displayName)")
            print("   Error: \(error.localizedDescription)")
            #endif
        }
    }

    /// Handle re-arm request - with 240 static thresholds, NO restart needed
    private func clearRearmFlag(for logicalID: String, defaults: UserDefaults) {
        // NO restart! 240 static thresholds are already in place
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
        // Check if already authorized — avoid triggering the system dialog unnecessarily.
        // authorizationStatus persists across app launches; our in-memory flag doesn't.
        if AuthorizationCenter.shared.authorizationStatus == .approved {
            authorizationGranted = true
            DispatchQueue.main.async {
                completion(.success(()))
            }
            return
        }

        Task { [weak self] in
            do {
                // Since our minimum deployment target is iOS 16.6, we can use the async version directly
                try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
                await MainActor.run {
                    self?.authorizationGranted = true

                    // Enable adult content filter immediately after authorization (always-on for child devices)
                    self?.applyAdultContentFilterIfNeeded()

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
        #if DEBUG
        print("[ScreenTimeService] 🎯 startMonitoring() called")
        #endif

        requestPermission { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                // Skip if monitoring is already registered with iOS (e.g., init recovery already started it)
                if self.isMonitoring && self.deviceActivityCenter.activities.contains(self.activityName) {
                    self.lifecycleLog("MONITORING_ALREADY_ACTIVE — skipping redundant startMonitoring (iOS confirms registered)")
                    #if DEBUG
                    print("[ScreenTimeService] ✅ Monitoring already active at iOS level — skipping redundant start")
                    #endif
                    DispatchQueue.main.async {
                        completion(.success(()))
                    }
                    return
                }
                print("[ScreenTimeService] ✅ Permission granted, scheduling activity...")
                do {
                    try self.scheduleActivity()
                    self.isMonitoring = true
                    print("[ScreenTimeService] ✅ Activity scheduled successfully!")

                    // Refresh event mappings to ensure category keys are written
                    // (Required for extension to detect reward apps for time expiration blocking)
                    self.saveEventMappings()

                    // Persist monitoring state for auto-restart on app launch
                    if let sharedDefaults = UserDefaults(suiteName: self.appGroupIdentifier) {
                        sharedDefaults.set(true, forKey: "wasMonitoringActive")
                        print("[ScreenTimeService] 💾 Persisted monitoring state: ACTIVE")
                    }

                    // Print diagnostics after monitoring starts (always, not just DEBUG)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self.printUsageTrackingDiagnostics()
                    }

                    DispatchQueue.main.async {
                        completion(.success(()))
                    }
                } catch {
                    print("[ScreenTimeService] ❌ Failed to schedule activity: \(error)")
                    self.isMonitoring = false
                    DispatchQueue.main.async {
                        completion(.failure(.monitoringFailed(error)))
                    }
                }
            case .failure(let error):
                print("[ScreenTimeService] ❌ Permission denied: \(error)")
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
        if !isInternalRestart {
            lifecycleLog("MONITORING_STOP — user/app action")
            // Only clear monitoring state for user-initiated stops.
            // During internal restarts, keep wasMonitoringActive=true so if restart
            // fails all retries, the next app launch still attempts recovery.
            if let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) {
                sharedDefaults.set(false, forKey: "wasMonitoringActive")
                #if DEBUG
                print("[ScreenTimeService] Persisted monitoring state: INACTIVE")
                #endif
            }
        }
    }

    // MARK: - Darwin Notification Diagnostics

    /// Get diagnostic stats about Darwin notification delivery
    /// Returns: (sent, received, missed, lastSentDate, lastReceivedDate)
    func getDarwinNotificationDiagnostics() -> (sent: Int, received: Int, missed: Int, lastSent: Date?, lastReceived: Date?) {
        guard let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            return (0, 0, 0, nil, nil)
        }

        let sentSeq = sharedDefaults.integer(forKey: "darwin_notification_seq_sent")
        let receivedSeq = sharedDefaults.integer(forKey: "darwin_notification_seq_received")
        let lastSentTime = sharedDefaults.double(forKey: "darwin_notification_last_sent")
        let lastReceivedTime = sharedDefaults.double(forKey: "darwin_notification_last_received")

        let lastSent = lastSentTime > 0 ? Date(timeIntervalSince1970: lastSentTime) : nil
        let lastReceived = lastReceivedTime > 0 ? Date(timeIntervalSince1970: lastReceivedTime) : nil
        let missed = max(0, sentSeq - receivedSeq)

        return (sentSeq, receivedSeq, missed, lastSent, lastReceived)
    }

    /// Reset Darwin notification diagnostic counters (useful for fresh testing)
    func resetDarwinNotificationDiagnostics() {
        guard let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) else { return }

        sharedDefaults.set(0, forKey: "darwin_notification_seq_sent")
        sharedDefaults.set(0, forKey: "darwin_notification_seq_received")
        sharedDefaults.removeObject(forKey: "darwin_notification_last_sent")
        sharedDefaults.removeObject(forKey: "darwin_notification_last_received")

        #if DEBUG
        print("[ScreenTimeService] 🔄 Reset Darwin notification diagnostic counters")
        #endif
    }

    /// Get extension debug log (circular buffer of last 50 entries)
    func getExtensionDebugLog() -> String {
        guard let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            return "Unable to access App Group"
        }
        return sharedDefaults.string(forKey: "extension_debug_log") ?? "No extension logs yet"
    }

    /// Comprehensive diagnostic for troubleshooting usage tracking issues
    func printUsageTrackingDiagnostics() {
        print("\n" + String(repeating: "=", count: 60))
        print("📊 USAGE TRACKING DIAGNOSTICS")
        print(String(repeating: "=", count: 60))

        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else {
            print("❌ CRITICAL: Cannot access App Group!")
            return
        }

        // 0. Print MONITORED APPS with details
        print("\n🎯 MONITORED APPS (FamilyActivitySelection):")
        print("   Total apps: \(familySelection.applications.count)")
        print("   Total categories: \(familySelection.categories.count)")
        for (index, app) in familySelection.applications.enumerated() {
            let displayName = app.localizedDisplayName ?? "Unknown"
            let tokenHash = app.token.map { usagePersistence.tokenHash(for: $0).prefix(20) } ?? "no-token"
            print("   [\(index)] \(displayName) (hash: \(tokenHash)...)")
        }
        if familySelection.applications.isEmpty {
            print("   ⚠️ NO APPS IN SELECTION - this is likely the problem!")
        }

        // 1. Extension heartbeat
        let heartbeat = defaults.double(forKey: "extension_heartbeat")
        if heartbeat > 0 {
            let age = Date().timeIntervalSince1970 - heartbeat
            print("✅ Extension heartbeat: \(Int(age))s ago")
        } else {
            print("⚠️ No extension heartbeat recorded")
        }

        // 2. Extension initialized
        let extInit = defaults.bool(forKey: "extension_initialized_flag")
        print("Extension initialized: \(extInit ? "✅ Yes" : "❌ No")")

        // 3. Darwin notification stats
        let sent = defaults.integer(forKey: "darwin_notification_seq_sent")
        let received = defaults.integer(forKey: "darwin_notification_seq_received")
        print("Darwin notifications: sent=\(sent), received=\(received)")

        // 3b. Total events received by extension (helps diagnose if iOS is calling)
        let totalEventsReceived = defaults.integer(forKey: "ext_total_events_received")
        print("📊 Total events received by extension: \(totalEventsReceived)")

        // 4. Check event mappings
        if let mappingData = defaults.data(forKey: "eventMappings"),
           let mappings = try? JSONSerialization.jsonObject(with: mappingData) as? [String: Any] {
            print("Event mappings: \(mappings.count) events configured")

            // Show first 3 mappings as sample
            for (i, key) in mappings.keys.prefix(3).enumerated() {
                print("  [\(i)] \(key)")
            }
        } else {
            print("⚠️ No event mappings found!")
        }

        // 5. Check usage counters for known apps
        print("\n📱 Usage counters (from extension):")
        for (logicalID, app) in appUsages.prefix(5) {
            let todayKey = "usage_\(logicalID)_today"
            let totalKey = "usage_\(logicalID)_total"
            let today = defaults.integer(forKey: todayKey)
            let total = defaults.integer(forKey: totalKey)
            print("  \(app.appName): today=\(today)s, total=\(total)s")
        }

        // 6. Extension debug log (last 50 lines)
        print("\n📝 Extension log (last 50 lines):")
        let log = defaults.string(forKey: "extension_debug_log") ?? ""
        let lines = log.components(separatedBy: "\n").filter { !$0.isEmpty }
        for line in lines.suffix(50) {
            print("  \(line)")
        }

        // 7. Monitoring state
        print("\n🔍 Monitoring state:")
        print("  isMonitoring: \(isMonitoring)")
        print("  monitoredEvents count: \(monitoredEvents.count)")
        print("  appUsages count: \(appUsages.count)")

        print(String(repeating: "=", count: 60) + "\n")
    }

    // MARK: - Production Background Sync (Safety net for missed Darwin notifications)

    private var backgroundSyncTimer: Timer?

    /// Start background polling as safety net for missed Darwin notifications
    /// Unlike DEBUG polling, this runs in production with longer interval (5 min)
    func startBackgroundSync(interval: TimeInterval = 300) {  // 5 minutes default
        guard backgroundSyncTimer == nil else { return }

        print("[ScreenTimeService] 🔄 Starting background sync (every \(Int(interval))s)")
        print("[ScreenTimeService] ℹ️ This provides safety net for missed Darwin notifications")

        backgroundSyncTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.syncExtensionDataSafely()
            }
        }
        RunLoop.current.add(backgroundSyncTimer!, forMode: .common)
    }

    /// Stop background sync timer
    func stopBackgroundSync() {
        backgroundSyncTimer?.invalidate()
        backgroundSyncTimer = nil
    }

    /// Safely sync extension data with error handling and logging
    private func syncExtensionDataSafely() {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else {
            print("⚠️ [ScreenTimeService] Background sync failed - app group unavailable")
            return
        }

        print("[ScreenTimeService] ⏰ Background sync triggered")

        // Read extension data
        readExtensionUsageData(defaults: defaults)

        // Notify UI to update
        notifyUsageChange()
    }

    // MARK: - Diagnostic Polling System (Disabled for performance)

    /// Start polling extension data - DISABLED for performance
    func startDiagnosticPolling(interval: TimeInterval = 10) {
        // Disabled - was causing excessive logging and lag
    }

    /// Stop diagnostic polling
    func stopDiagnosticPolling() {
        diagnosticPollingTimer?.invalidate()
        diagnosticPollingTimer = nil
    }

    /// Poll extension data and log any changes
    private func pollExtensionData() {
        diagnosticPollCount += 1

        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else {
            print("[DiagnosticPolling] ❌ Cannot access App Group!")
            return
        }

        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        print("\n[DiagnosticPolling] ━━━ Poll #\(diagnosticPollCount) @ \(timestamp) ━━━")

        // 1. Check extension heartbeat
        let heartbeat = defaults.double(forKey: "extension_heartbeat")
        if heartbeat > 0 {
            let age = Int(Date().timeIntervalSince1970 - heartbeat)
            print("  ❤️ Extension heartbeat: \(age)s ago")
        } else {
            print("  ⚠️ No extension heartbeat")
        }

        // 2. Check last event from extension
        if let lastEvent = defaults.string(forKey: "lastEvent") {
            let lastEventTime = defaults.double(forKey: "lastEventTimestamp")
            let eventAge = lastEventTime > 0 ? Int(Date().timeIntervalSince1970 - lastEventTime) : -1
            print("  📩 Last event: \(lastEvent) (\(eventAge)s ago)")
        }

        // 3. Check Darwin notification sequence
        let sent = defaults.integer(forKey: "darwin_notification_seq_sent")
        let received = defaults.integer(forKey: "darwin_notification_seq_received")
        let missed = sent - received
        print("  📡 Darwin: sent=\(sent) received=\(received) missed=\(missed)")

        // 4. Read usage values for ALL known apps and detect changes
        var hasChanges = false
        print("  📱 Usage per app:")

        for (logicalID, app) in appUsages {
            let todayKey = "usage_\(logicalID)_today"
            let totalKey = "usage_\(logicalID)_total"
            let resetKey = "usage_\(logicalID)_reset"
            let rearmKey = "usage_\(logicalID)_needsRearm"

            let today = defaults.integer(forKey: todayKey)
            let total = defaults.integer(forKey: totalKey)
            let resetTimestamp = defaults.double(forKey: resetKey)
            let needsRearm = defaults.bool(forKey: rearmKey)

            // Check for change since last poll
            let previousValue = lastPolledUsageValues[logicalID] ?? 0
            let delta = today - previousValue
            let changeIndicator = delta > 0 ? " 📈+\(delta)s" : ""

            if delta > 0 {
                hasChanges = true
            }

            // Also get persistence value for comparison
            let persistedApp = usagePersistence.app(for: logicalID)
            let persistedToday = persistedApp?.todaySeconds ?? 0

            let resetAge = resetTimestamp > 0 ? Int(Date().timeIntervalSince1970 - resetTimestamp) : -1
            let rearmFlag = needsRearm ? " 🔄REARM" : ""

            print("     \(app.appName):")
            print("       extension: today=\(today)s, total=\(total)s, reset=\(resetAge)s ago\(rearmFlag)\(changeIndicator)")
            print("       persisted: today=\(persistedToday)s")

            // Store for next comparison
            lastPolledUsageValues[logicalID] = today
        }

        // 5. Summary
        if !hasChanges && diagnosticPollCount > 1 {
            print("  ⏸️ No usage changes detected this poll")
        }

        // 6. Check if any thresholds might be stuck
        let activities = deviceActivityCenter.activities
        print("  🎯 Active schedules: \(activities.count)")
        for activity in activities {
            print("     - \(activity.rawValue)")
        }

        // 7. Show total events configured (check for potential limit issues)
        print("  📊 Configured events: \(monitoredEvents.count) (60/app sliding window, limit ~500 total)")
        if monitoredEvents.count > 500 {
            print("  ⚠️ WARNING: High event count (>\(monitoredEvents.count)) may cause iOS to silently drop events!")
        }

        // 8. Check extension debug log for recent entries
        let extLog = defaults.string(forKey: "extension_debug_log") ?? ""
        let logLines = extLog.components(separatedBy: "\n").filter { !$0.isEmpty }
        if !logLines.isEmpty {
            print("  📝 Extension log (last 20 entries):")
            for line in logLines.suffix(20) {
                print("     \(line)")
            }
        } else {
            print("  📝 Extension log: (empty)")
        }

        // 9. Check event mappings for the apps
        if let mappingData = defaults.data(forKey: "eventMappings"),
           let mappings = try? JSONSerialization.jsonObject(with: mappingData) as? [String: Any] {
            print("  🗺️ Event mappings stored: \(mappings.count)")

            // Check for specific threshold events (e.g., minute 35, 36, 37 for debugging)
            for (logicalID, app) in appUsages {
                let currentMinutes = (defaults.integer(forKey: "usage_\(logicalID)_today")) / 60
                let nextMinute = currentMinutes + 1

                // Look for events that SHOULD fire next
                var foundNextEvent = false
                for key in mappings.keys {
                    if key.contains(".min.\(nextMinute)") {
                        if let eventInfo = mappings[key] as? [String: Any],
                           let eventLogicalID = eventInfo["logicalID"] as? String,
                           eventLogicalID == logicalID {
                            foundNextEvent = true
                            print("  ✅ Next event for \(app.appName): \(key) (min \(nextMinute))")
                        }
                    }
                }
                if !foundNextEvent && currentMinutes > 0 {
                    print("  ❌ NO next event for \(app.appName) at minute \(nextMinute)!")
                }
            }
        } else {
            print("  ⚠️ No event mappings found in UserDefaults!")
        }

        // 10. Check primitive key mappings (map_<eventName>_id)
        print("  🔑 Checking primitive event mappings:")
        var primitiveMapCount = 0
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("map_") && key.hasSuffix("_id") {
            primitiveMapCount += 1
        }
        print("     Found \(primitiveMapCount) primitive event mappings")

        print("[DiagnosticPolling] ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        #if DEBUG
        // Print full usage tracking debug summary with ext_ vs app comparison
        print("\n⏱️⏱️⏱️ POLLING CYCLE #\(diagnosticPollCount) - USAGE TRACKING DEBUG ⏱️⏱️⏱️")
        printUsageTrackingDebugSummary()
        #endif
    }

    /// Check if diagnostic polling is active
    var isDiagnosticPollingActive: Bool {
        return diagnosticPollingTimer != nil
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

            // Check if app is currently shielded - skip recording shield time as usage
            if isLogicalIDShielded(logicalID) {
                NSLog("[Snapshot] \(bundleID): SHIELDED - skipping (shield time, not real usage)")
                skippedCount += 1
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

    /// Force reset ALL daily counters regardless of lastResetDate.
    /// This is a one-time migration to fix data corrupted by the faulty decoder default.
    func forceResetAllDailyCounters() {
        usagePersistence.forceResetAllDailyCounters()
        reloadAppUsagesFromPersistence()
        notifyUsageChange()
    }

    /// Check if monitoring is registered with iOS and restart if dead.
    /// Safe to call frequently — smart threshold filtering prevents catch-up floods.
    func checkMonitoringHealth() {
        guard isMonitoring else { return }
        let activities = deviceActivityCenter.activities

        // Check 1: Monitoring dead at OS level
        if !activities.contains(activityName) {
            lifecycleLog("MONITORING_DEAD — detected on foreground, restarting")
            #if DEBUG
            print("[ScreenTimeService] Monitoring dead at OS level — triggering restart")
            #endif
            Task { [weak self] in
                await self?.restartMonitoring(reason: "foreground health check")
            }
            return
        }

        // Check 2: Midnight pending — monitoring alive but thresholds stale.
        // At midnight, intervalDidStart() set this flag. scheduleActivity() hasn't run yet.
        // Force restart to register fresh thresholds and clear the SKIP_MIDNIGHT block.
        if let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier),
           sharedDefaults.bool(forKey: "midnight_pending_refresh") {
            lifecycleLog("MIDNIGHT_PENDING — detected on foreground, restarting for fresh thresholds")
            #if DEBUG
            print("[ScreenTimeService] Midnight pending refresh — triggering restart for fresh thresholds")
            #endif
            // Refresh timestamp so SKIP_MIDNIGHT's 2h window anchors to NOW, not midnight.
            sharedDefaults.set(Date().timeIntervalSince1970, forKey: "midnight_pending_timestamp")
            Task { [weak self] in
                await self?.restartMonitoring(reason: "midnight pending refresh")
            }
            return
        }
    }

    /// Refresh usage data from extension's UserDefaults.
    /// Call this when app becomes active to ensure UI shows latest data.
    func refreshFromExtension() {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else {
            print("⚠️ [ScreenTimeService] refreshFromExtension: Failed to access app group UserDefaults")
            return
        }

        #if DEBUG
        print("[ScreenTimeService] 🔄 refreshFromExtension: Reading extension data...")
        #endif

        readExtensionUsageData(defaults: defaults)
        notifyUsageChange()

        #if DEBUG
        print("[ScreenTimeService] ✅ refreshFromExtension: Complete")
        #endif
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

    /// Restart monitoring with retry logic for robustness.
    /// If scheduleActivity() fails, retries up to 3 times with exponential backoff.
    func restartMonitoring(reason: String, force: Bool = false) async {
        #if DEBUG
        print("[ScreenTimeService] ♻️ Restart requested (\(reason))")
        #endif

        lifecycleLog("MONITORING_RESTART — reason: \(reason)")

        isInternalRestart = true
        stopMonitoring()

        // Retry up to 3 times with exponential backoff
        var lastError: Error?
        for attempt in 1...3 {
            do {
                try scheduleActivity()
                isMonitoring = true
                isInternalRestart = false

                // Re-persist monitoring state after successful restart
                // stopMonitoring() sets wasMonitoringActive=false, so we must restore it
                if let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) {
                    sharedDefaults.set(true, forKey: "wasMonitoringActive")
                }

                lifecycleLog("MONITORING_RESTART_OK — reason: \(reason), attempt \(attempt)")
                #if DEBUG
                print("[ScreenTimeService] ✅ Restarted monitoring (\(reason)) on attempt \(attempt)")
                #endif

                return  // Success, exit

            } catch {
                lastError = error
                print("[ScreenTimeService] ⚠️ Restart attempt \(attempt)/3 failed: \(error)")

                if attempt < 3 {
                    // Wait before retry (exponential backoff: 1s, 2s)
                    try? await Task.sleep(nanoseconds: UInt64(attempt) * 1_000_000_000)
                }
            }
        }

        // All retries failed
        isInternalRestart = false
        if let error = lastError {
            lifecycleLog("MONITORING_RESTART_FAILED — reason: \(reason), error: \(error.localizedDescription)")
            print("[ScreenTimeService] ❌ CRITICAL: Failed to restart monitoring after 3 attempts: \(error)")
        }
    }

    #if DEBUG
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
    #endif

    /// Diagnostic: Validate all event mappings for corruption
    /// Returns a detailed report string that can be displayed or copied
    func diagnosticValidateMappings() -> String {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else {
            return "ERROR: Cannot access App Group defaults"
        }

        var report: [String] = ["=== MAPPING DIAGNOSTIC REPORT ==="]
        let allKeys = defaults.dictionaryRepresentation()

        // 1. Collect all map_{eventName}_id mappings
        var eventMappings: [String: String] = [:] // eventName → logicalID
        var logicalIDToEvents: [String: [String]] = [:] // logicalID → [eventNames]

        for (key, value) in allKeys {
            if key.hasPrefix("map_") && key.hasSuffix("_id") {
                let eventName = String(key.dropFirst(4).dropLast(3)) // Remove "map_" and "_id"
                if let logicalID = value as? String {
                    eventMappings[eventName] = logicalID
                    logicalIDToEvents[logicalID, default: []].append(eventName)
                }
            }
        }

        report.append("\n📊 Found \(eventMappings.count) event mappings")
        report.append("📊 Mapping to \(logicalIDToEvents.count) unique logicalIDs")

        // 2. Check for stableHash collisions
        var stableHashToLogicalID: [UInt64: [String]] = [:]
        for logicalID in logicalIDToEvents.keys {
            let hash = stableHash(logicalID)
            stableHashToLogicalID[hash, default: []].append(logicalID)
        }

        let collisions = stableHashToLogicalID.filter { $0.value.count > 1 }
        if !collisions.isEmpty {
            report.append("\n⚠️ HASH COLLISIONS DETECTED:")
            for (hash, ids) in collisions {
                report.append("  Hash \(hash): \(ids.joined(separator: ", "))")
            }
        } else {
            report.append("\n✅ No stableHash collisions detected")
        }

        // 3. Check event count per app
        report.append("\n📋 Events per logicalID:")
        for (logicalID, events) in logicalIDToEvents.sorted(by: { $0.value.count > $1.value.count }) {
            let shortID = String(logicalID.prefix(12))
            let displayName = defaults.string(forKey: "map_\(logicalID)_name") ?? "Unknown"
            report.append("  \(shortID)... (\(displayName)): \(events.count) events")
            if events.count != 60 {
                report.append("    ⚠️ Expected 60 events, found \(events.count)")
            }
        }

        // 4. Check ext_usage keys match mappings
        report.append("\n📋 ext_usage_* keys:")
        var extUsageApps: Set<String> = []
        for key in allKeys.keys where key.hasPrefix("ext_usage_") && key.hasSuffix("_today") {
            let appID = String(key.dropFirst(10).dropLast(6)) // Remove "ext_usage_" and "_today"
            extUsageApps.insert(appID)

            let todaySeconds = defaults.integer(forKey: key)
            let dateStr = defaults.string(forKey: "ext_usage_\(appID)_date") ?? "nil"
            let displayName = defaults.string(forKey: "map_\(appID)_name") ?? "Unknown"

            let hasMapping = logicalIDToEvents[appID] != nil
            let mappingStatus = hasMapping ? "✅" : "⚠️ NO MAPPING"

            report.append("  \(appID.prefix(12))... (\(displayName)): \(todaySeconds)s, date=\(dateStr) \(mappingStatus)")
        }

        // 5. Check for orphaned mappings (mappings without ext_usage data)
        let orphanedMappings = Set(logicalIDToEvents.keys).subtracting(extUsageApps)
        if !orphanedMappings.isEmpty {
            report.append("\n⚠️ Orphaned mappings (no ext_usage data):")
            for appID in orphanedMappings {
                let displayName = defaults.string(forKey: "map_\(appID)_name") ?? "Unknown"
                report.append("  \(appID.prefix(12))... (\(displayName))")
            }
        }

        // 6. Check hourly distribution for anomalies
        report.append("\n📋 Hourly Usage Distribution (hours with usage):")
        for appID in extUsageApps.sorted() {
            let displayName = defaults.string(forKey: "map_\(appID)_name") ?? "Unknown"
            var hourlyUsage: [String] = []
            for hour in 0..<24 {
                let seconds = defaults.integer(forKey: "ext_usage_\(appID)_hourly_\(hour)")
                if seconds > 0 {
                    hourlyUsage.append("h\(hour)=\(seconds)s")
                }
            }
            if !hourlyUsage.isEmpty {
                report.append("  \(appID.prefix(12))... (\(displayName)): \(hourlyUsage.joined(separator: ", "))")
            }
        }

        // 7. Check for currently monitored apps vs mappings
        report.append("\n📋 Currently monitored apps (\(monitoredEvents.count) events):")
        var monitoredLogicalIDs: Set<String> = []
        for (_, event) in monitoredEvents {
            if let app = event.applications.first {
                monitoredLogicalIDs.insert(app.logicalID)
            }
        }
        for logicalID in monitoredLogicalIDs.sorted() {
            let shortID = String(logicalID.prefix(12))
            let displayName = defaults.string(forKey: "map_\(logicalID)_name") ?? "Unknown"
            let eventCount = logicalIDToEvents[logicalID]?.count ?? 0
            report.append("  \(shortID)... (\(displayName)): \(eventCount) events")
        }

        // 8. Check for stale mappings (mappings not in current monitoring)
        let staleMappings = Set(logicalIDToEvents.keys).subtracting(monitoredLogicalIDs)
        if !staleMappings.isEmpty {
            report.append("\n⚠️ Stale mappings (not currently monitored):")
            for appID in staleMappings {
                let displayName = defaults.string(forKey: "map_\(appID)_name") ?? "Unknown"
                let eventCount = logicalIDToEvents[appID]?.count ?? 0
                report.append("  \(appID.prefix(12))... (\(displayName)): \(eventCount) orphaned events")
            }
        }

        report.append("\n=== END DIAGNOSTIC REPORT ===")
        return report.joined(separator: "\n")
    }

    /// Clean up all stale event mappings that don't match current monitoring configuration
    /// This fixes corruption from threshold changes (240→60) and removed apps
    func cleanupStaleMappings() {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else { return }

        let allKeys = Array(defaults.dictionaryRepresentation().keys)
        var keysToRemove: [String] = []

        // Get current valid event names from monitoredEvents
        let validEventNames = Set(monitoredEvents.keys.map { $0.rawValue })
        let currentLogicalIDs = Set(monitoredEvents.values.compactMap { $0.applications.first?.logicalID })

        #if DEBUG
        print("[ScreenTimeService] 🧹 Starting stale mapping cleanup...")
        print("   - Valid event names: \(validEventNames.count)")
        print("   - Current logical IDs: \(currentLogicalIDs.count)")
        #endif

        // Find all map_* keys that should be removed
        for key in allKeys {
            // Clean up event mappings for events not in current monitoring
            if key.hasPrefix("map_") && key.hasSuffix("_id") {
                let eventName = String(key.dropFirst(4).dropLast(3))
                if !validEventNames.contains(eventName) {
                    keysToRemove.append(key)
                    // Also remove associated keys
                    keysToRemove.append("map_\(eventName)_inc")
                    keysToRemove.append("map_\(eventName)_sec")
                    keysToRemove.append("map_\(eventName)_category")
                }
            }

            // Clean up ext_usage_* keys for apps no longer monitored
            if key.hasPrefix("ext_usage_") && key.contains("_today") {
                let appID = key.replacingOccurrences(of: "ext_usage_", with: "")
                    .replacingOccurrences(of: "_today", with: "")
                if !currentLogicalIDs.contains(appID) {
                    // Remove all ext_usage keys for this orphaned app
                    keysToRemove.append("ext_usage_\(appID)_today")
                    keysToRemove.append("ext_usage_\(appID)_total")
                    keysToRemove.append("ext_usage_\(appID)_date")
                    keysToRemove.append("ext_usage_\(appID)_hour")
                    keysToRemove.append("ext_usage_\(appID)_timestamp")
                    keysToRemove.append("ext_usage_\(appID)_hourly_date")
                    for h in 0..<24 {
                        keysToRemove.append("ext_usage_\(appID)_hourly_\(h)")
                    }
                }
            }

            // Clean up usage_* keys for apps no longer monitored
            if key.hasPrefix("usage_") && key.hasSuffix("_today") {
                let appID = String(key.dropFirst(6).dropLast(6))
                if !currentLogicalIDs.contains(appID) {
                    keysToRemove.append("usage_\(appID)_today")
                    keysToRemove.append("usage_\(appID)_total")
                    keysToRemove.append("usage_\(appID)_reset")
                    keysToRemove.append("usage_\(appID)_lastThreshold")
                    keysToRemove.append("usage_\(appID)_modified")
                    keysToRemove.append("usage_\(appID)_lastEventTime")
                }
            }

            // Clean up map_{logicalID}_* keys for apps no longer monitored
            if key.hasPrefix("map_") && (key.hasSuffix("_name") || key.hasSuffix("_category")) {
                // Extract logicalID from key like "map_{logicalID}_name"
                let withoutPrefix = String(key.dropFirst(4))
                if let suffixRange = withoutPrefix.range(of: "_name") ?? withoutPrefix.range(of: "_category") {
                    let appID = String(withoutPrefix[..<suffixRange.lowerBound])
                    if !currentLogicalIDs.contains(appID) {
                        keysToRemove.append(key)
                    }
                }
            }
        }

        // Remove duplicates and delete keys
        let uniqueKeys = Set(keysToRemove)
        for key in uniqueKeys {
            defaults.removeObject(forKey: key)
        }

        #if DEBUG
        print("[ScreenTimeService] 🧹 Cleaned up \(uniqueKeys.count) stale keys")
        #endif
    }

    private func scheduleActivity() throws {
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true
        )

        // ONE-TIME CALIBRATION: Clear inflated ext_usage from previous version's flood correction bug.
        // Inflated ext_usage causes smart filtering to skip all thresholds → no catch-up events →
        // no corrections → deadlock. Resetting to 0 lets iOS catch-ups recalibrate via catchup_max.
        if let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier),
           !sharedDefaults.bool(forKey: "ext_usage_calibrated_v1") {
            let logicalIDs = Set(monitoredEvents.values.compactMap { $0.applications.first?.logicalID })
            for logicalID in logicalIDs {
                sharedDefaults.set(0, forKey: "ext_usage_\(logicalID)_today")
                sharedDefaults.removeObject(forKey: "ext_usage_\(logicalID)_date")
                sharedDefaults.set(0, forKey: "usage_\(logicalID)_today")
                sharedDefaults.removeObject(forKey: "catchup_max_\(logicalID)")
            }
            for logicalID in logicalIDs {
                if var persistedApp = usagePersistence.app(for: logicalID) {
                    persistedApp.todaySeconds = 0
                    usagePersistence.saveApp(persistedApp)
                }
            }
            sharedDefaults.set(true, forKey: "ext_usage_calibrated_v1")
            lifecycleLog("CALIBRATION_RESET — cleared ext_usage for \(logicalIDs.count) apps")
        }

        // ONE-TIME FIX: Clear stale catchup_max values AND phantom-inflated usage counters
        // from previous version that captured catch-up events in SKIP_RESTART.
        // Those values include residual data from yesterday causing phantom 60-min inflation.
        if let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier),
           !sharedDefaults.bool(forKey: "catchup_fix_v2") {
            let logicalIDs = Set(monitoredEvents.values.compactMap { $0.applications.first?.logicalID })
            for logicalID in logicalIDs {
                sharedDefaults.removeObject(forKey: "catchup_max_\(logicalID)")
                sharedDefaults.set(0, forKey: "ext_usage_\(logicalID)_today")
                sharedDefaults.removeObject(forKey: "ext_usage_\(logicalID)_date")
                sharedDefaults.set(0, forKey: "usage_\(logicalID)_today")
            }
            for logicalID in logicalIDs {
                if var persistedApp = usagePersistence.app(for: logicalID) {
                    persistedApp.todaySeconds = 0
                    usagePersistence.saveApp(persistedApp)
                }
            }
            sharedDefaults.set(true, forKey: "catchup_fix_v2")
            lifecycleLog("CATCHUP_FIX_V2 — cleared stale catchup_max + reset usage for \(logicalIDs.count) apps")
        }

        // ONE-TIME FIX: Clear inflated usage from catchup_max capturing stale cross-midnight
        // catch-up events in SKIP_COOLDOWN. With includesPastActivity:true, iOS retains cumulative
        // across midnight; catch-up bursts (delivered via extension kill/relaunch cycles, potentially
        // 40+ min after restart) carried yesterday's residual data into catchup_max, inflating
        // usage by 60+ min. catchup_max capture is now removed from SKIP_COOLDOWN entirely.
        if let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier),
           !sharedDefaults.bool(forKey: "catchup_fix_v3") {
            let logicalIDs = Set(monitoredEvents.values.compactMap { $0.applications.first?.logicalID })
            for logicalID in logicalIDs {
                sharedDefaults.removeObject(forKey: "catchup_max_\(logicalID)")
                sharedDefaults.set(0, forKey: "ext_usage_\(logicalID)_today")
                sharedDefaults.removeObject(forKey: "ext_usage_\(logicalID)_date")
                sharedDefaults.set(0, forKey: "usage_\(logicalID)_today")
            }
            for logicalID in logicalIDs {
                if var persistedApp = usagePersistence.app(for: logicalID) {
                    persistedApp.todaySeconds = 0
                    usagePersistence.saveApp(persistedApp)
                }
            }
            sharedDefaults.set(true, forKey: "catchup_fix_v3")
            lifecycleLog("CATCHUP_FIX_V3 — cleared stale catchup_max + reset inflated usage for \(logicalIDs.count) apps")
        }

        // ONE-TIME FIX: Clear stale catchup_max and midnight flags for clean start.
        // catchup_max capture is now re-enabled in SKIP_RESTART (safe with SKIP_MIDNIGHT
        // blocking stale cross-midnight catch-ups upstream).
        if let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier),
           !sharedDefaults.bool(forKey: "catchup_fix_v4") {
            let logicalIDs = Set(monitoredEvents.values.compactMap { $0.applications.first?.logicalID })
            for logicalID in logicalIDs {
                sharedDefaults.removeObject(forKey: "catchup_max_\(logicalID)")
            }
            sharedDefaults.removeObject(forKey: "midnight_pending_refresh")
            sharedDefaults.removeObject(forKey: "midnight_pending_timestamp")
            sharedDefaults.set(true, forKey: "catchup_fix_v4")
            lifecycleLog("CATCHUP_FIX_V4 — cleared stale catchup_max and midnight flags for clean start")
        }

        // ONE-TIME FIX: Clear phantom-inflated usage from catchup_max being captured for shielded
        // reward apps (SKIP_RESTART ran before SKIP_SHIELDED, and correction paths had no shield check).
        // Rapid restarts caused iOS to fire catch-ups for ALL registered thresholds including 0-usage
        // reward apps, inflating them by ~60 min each. Now fixed: shield checks in SKIP_RESTART +
        // correction paths + scheduleActivity clears catchup_max before startMonitoring.
        if let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier),
           !sharedDefaults.bool(forKey: "catchup_fix_v5") {
            let logicalIDs = Set(monitoredEvents.values.compactMap { $0.applications.first?.logicalID })
            for logicalID in logicalIDs {
                sharedDefaults.removeObject(forKey: "catchup_max_\(logicalID)")
                sharedDefaults.set(0, forKey: "ext_usage_\(logicalID)_today")
                sharedDefaults.removeObject(forKey: "ext_usage_\(logicalID)_date")
                sharedDefaults.set(0, forKey: "usage_\(logicalID)_today")
                if var persistedApp = usagePersistence.app(for: logicalID) {
                    persistedApp.totalSeconds = 0
                    usagePersistence.saveApp(persistedApp)
                }
            }
            sharedDefaults.set(true, forKey: "catchup_fix_v5")
            lifecycleLog("CATCHUP_FIX_V5 — cleared phantom-inflated usage from shielded reward app catchup_max bug")
        }

        // SLIDING WINDOW THRESHOLDS:
        // Generate thresholds (currentMinutes+1) to (currentMinutes+60) for real tracking.
        // Budget: 60 thresholds per app (stays under iOS ~500 limit)
        var appCurrentMinutes: [String: Int] = [:]
        if let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) {
            let todayDateString: String = {
                let fmt = DateFormatter()
                fmt.dateFormat = "yyyy-MM-dd"
                return fmt.string(from: Date())
            }()
            var seenLogicalIDs = Set<String>()
            for event in monitoredEvents.values {
                guard let app = event.applications.first,
                      seenLogicalIDs.insert(app.logicalID).inserted else { continue }
                let extDate = sharedDefaults.string(forKey: "ext_usage_\(app.logicalID)_date")
                let extTodaySeconds = sharedDefaults.integer(forKey: "ext_usage_\(app.logicalID)_today")
                if extDate == todayDateString {
                    appCurrentMinutes[app.logicalID] = extTodaySeconds / 60
                    lifecycleLog("SLIDING_WINDOW_READ \(app.logicalID.prefix(8))... extDate=\(extDate ?? "nil") today=\(todayDateString) → \(extTodaySeconds / 60) min")
                    midnightDiagnosticLog("SCHEDULE_READ \(app.logicalID.prefix(8))... extDate=\(extDate ?? "nil") extTodaySeconds=\(extTodaySeconds) currentMinutes=\(extTodaySeconds / 60)")
                } else {
                    lifecycleLog("SLIDING_WINDOW_DATE_MISMATCH \(app.logicalID.prefix(8))... extDate=\(extDate ?? "nil") today=\(todayDateString) extTodaySeconds=\(extTodaySeconds) → defaulting to 0 min")
                    midnightDiagnosticLog("SCHEDULE_READ_MISMATCH \(app.logicalID.prefix(8))... extDate=\(extDate ?? "nil") today=\(todayDateString) extTodaySeconds=\(extTodaySeconds) → 0min")
                }
            }
        }

        // Collect one template per app from existing monitoredEvents (for metadata)
        var appTemplates: [String: (app: MonitoredApplication, category: AppUsage.AppCategory)] = [:]
        for event in monitoredEvents.values {
            guard let app = event.applications.first else { continue }
            if appTemplates[app.logicalID] == nil {
                appTemplates[app.logicalID] = (app: app, category: event.category)
            }
        }

        // Rebuild monitoredEvents with sliding window per app
        var newMonitoredEvents: [DeviceActivityEvent.Name: MonitoredEvent] = [:]
        var totalSkipped = 0
        for (logicalID, template) in appTemplates {
            let currentMinutes = appCurrentMinutes[logicalID] ?? 0
            totalSkipped += currentMinutes
            let stableAppID = stableHash(logicalID)

            // Sliding window: 60 thresholds above current usage
            let minutesToRegister = Array((currentMinutes + 1)...(currentMinutes + 60))

            for minuteNumber in minutesToRegister {
                let eventName = DeviceActivityEvent.Name("usage.app.\(stableAppID).min.\(minuteNumber)")
                newMonitoredEvents[eventName] = MonitoredEvent(
                    name: eventName,
                    category: template.category,
                    threshold: DateComponents(minute: minuteNumber),
                    applications: [template.app]
                )
            }
        }
        monitoredEvents = newMonitoredEvents
        saveEventMappings()

        // Ensure extension has fresh shield configs for shield control
        // (app launch sync may have run before categoryAssignments was populated)
        syncGoalConfigsToExtension()

        // Pre-populate tracked_app_ids so extension's RESTART_THRESHOLD_RESET
        // resets lastThreshold for ALL monitored apps (not just previously recorded ones)
        if let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) {
            let allLogicalIDs = Array(appTemplates.keys)
            sharedDefaults.set(allLogicalIDs, forKey: "tracked_app_ids")
            lifecycleLog("TRACKED_APP_IDS_SET count=\(allLogicalIDs.count) ids=\(allLogicalIDs.map { String($0.prefix(8)) }.joined(separator: ","))")

            // Clear stale catchup_max before startMonitoring — each restart cycle starts fresh.
            // The new monitoring session's catch-up burst will repopulate catchup_max correctly.
            // Prevents stale values from accumulating across rapid restarts.
            for logicalID in allLogicalIDs {
                sharedDefaults.removeObject(forKey: "catchup_max_\(logicalID)")
            }

            // Store window top + stable hash per app so extension can detect exhaustion
            // and self-rebuild the sliding window without the main app.
            for logicalID in allLogicalIDs {
                let currentMinutes = appCurrentMinutes[logicalID] ?? 0
                sharedDefaults.set(currentMinutes + 60, forKey: "window_top_min_\(logicalID)")
                sharedDefaults.set(String(stableHash(logicalID)), forKey: "app_stable_hash_\(logicalID)")
            }
        }

        // Register all events (all are above current usage — no filtering needed)
        let events = monitoredEvents.reduce(into: [DeviceActivityEvent.Name: DeviceActivityEvent]()) { result, entry in
            result[entry.key] = entry.value.deviceActivityEvent()
        }

        for (logicalID, _) in appTemplates {
            let mins = appCurrentMinutes[logicalID] ?? 0
            lifecycleLog("SLIDING_WINDOW \(logicalID.prefix(8))... current=\(mins)min range=\(mins + 1)-\(mins + 60) (60 thresholds) windowTop=\(mins + 60)")
            midnightDiagnosticLog("SCHEDULE_WINDOW \(logicalID.prefix(8))... current=\(mins)min thresholds=\(mins + 1)-\(mins + 60)")
        }

        // CRITICAL: Set restart timestamp BEFORE starting monitoring
        // This closes the race window where events could arrive before the timestamp is set
        // Extension uses this to skip catch-up events within 60 seconds of restart
        if let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) {
            sharedDefaults.set(Date().timeIntervalSince1970, forKey: "monitoring_restart_timestamp")
            #if DEBUG
            print("[ScreenTimeService] Set monitoring_restart_timestamp BEFORE startMonitoring")
            #endif
        }

        try deviceActivityCenter.startMonitoring(activityName, during: schedule, events: events)

        // Clear midnight pending flag and close diagnostic window
        if let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) {
            // Clear SKIP_MIDNIGHT block — fresh thresholds are now registered
            if sharedDefaults.bool(forKey: "midnight_pending_refresh") {
                sharedDefaults.set(false, forKey: "midnight_pending_refresh")
                lifecycleLog("MIDNIGHT_PENDING_CLEARED — fresh thresholds registered")
                midnightDiagnosticLog("MIDNIGHT_PENDING_CLEARED — scheduleActivity complete")
            }

            // Close midnight diagnostic window
            if sharedDefaults.bool(forKey: "midnight_diagnostic_active") {
                midnightDiagnosticLog("DIAGNOSTIC_CLOSED — scheduleActivity done, \(events.count) events registered")
                sharedDefaults.set(false, forKey: "midnight_diagnostic_active")
            }
        }

        lifecycleLog("MONITORING_START — events=\(events.count) (sliding window, \(totalSkipped) min already tracked)")

        #if DEBUG
        print("[ScreenTimeService] DeviceActivity monitoring started successfully")
        print("   - Total threshold events: \(events.count) (60/app sliding window)")
        print("   - Schedule: 00:00 - 23:59 (repeating daily)")
        print("   - Activity name: \(activityName)")
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
        NotificationCenter.default.post(name: Self.usageDidChangeNotification, object: nil)
    }

    // MARK: - ManagedSettings App Blocking

    // ManagedSettings store for app blocking
    private let managedSettingsStore = ManagedSettingsStore()

    // Track currently shielded (blocked) apps
    private var currentlyShielded: Set<ApplicationToken> = []

    // Track apps that should always be accessible (learning apps)
    private var alwaysAccessible: Set<ApplicationToken> = []

    // MARK: - Web Content Restrictions

    // Track blocked web domains
    private var blockedWebDomains: Set<WebDomainToken> = []

    // Track blocked browser bundle IDs
    private var blockedBrowserBundleIDs: Set<String> = []

    // Known browser bundle IDs for blocking
    static let knownBrowserBundleIDs: [String: String] = [
        "com.apple.mobilesafari": "Safari",
        "com.google.chrome.ios": "Chrome",
        "org.mozilla.ios.Firefox": "Firefox",
        "com.microsoft.msedge": "Edge",
        "com.duckduckgo.mobile.ios": "DuckDuckGo",
        "com.brave.ios.browser": "Brave",
        "com.opera.gx": "Opera"
    ]

    /// Enable Apple's built-in adult content filter (always-on for child devices)
    /// This blocks adult websites automatically using Apple's content detection
    /// Side effect: Disables private/incognito browsing in Safari
    func enableAdultContentFilter() {
        #if !targetEnvironment(simulator)
        managedSettingsStore.webContent.blockedByFilter = .auto(except: [])

        #if DEBUG
        print("[ScreenTimeService] 🛡️ Adult content filter ENABLED")
        print("[ScreenTimeService] ℹ️ Side effect: Private/incognito browsing disabled in Safari")
        #endif
        #else
        #if DEBUG
        print("[ScreenTimeService] 🛡️ Adult content filter (simulated - not available on Simulator)")
        #endif
        #endif
    }

    /// Check if adult content filter is currently enabled
    var isAdultContentFilterEnabled: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return managedSettingsStore.webContent.blockedByFilter != nil
        #endif
    }

    /// Apply adult content filter on app launch if in child mode
    /// Called from init and should be called on app launch
    func applyAdultContentFilterIfNeeded() {
        // Only apply for child devices
        guard DeviceModeManager.shared.isChildDevice else {
            #if DEBUG
            print("[ScreenTimeService] ⏭️ Skipping adult content filter (not child device)")
            #endif
            return
        }

        enableAdultContentFilter()
    }

    // MARK: - Website Blocking

    /// Block specific websites by shielding their web domains
    func blockWebDomains(tokens: Set<WebDomainToken>) {
        #if DEBUG
        print("[ScreenTimeService] 🌐 Blocking \(tokens.count) web domains")
        #endif

        blockedWebDomains.formUnion(tokens)

        #if !targetEnvironment(simulator)
        managedSettingsStore.shield.webDomains = blockedWebDomains
        #endif

        // Persist blocked domains
        persistBlockedWebDomains()

        #if DEBUG
        print("[ScreenTimeService] ✅ Web domain shields applied: \(blockedWebDomains.count) total")
        #endif
    }

    /// Unblock specific websites
    func unblockWebDomains(tokens: Set<WebDomainToken>) {
        #if DEBUG
        print("[ScreenTimeService] 🔓 Unblocking \(tokens.count) web domains")
        #endif

        blockedWebDomains.subtract(tokens)

        #if !targetEnvironment(simulator)
        managedSettingsStore.shield.webDomains = blockedWebDomains.isEmpty ? nil : blockedWebDomains
        #endif

        // Persist blocked domains
        persistBlockedWebDomains()

        #if DEBUG
        print("[ScreenTimeService] ✅ Web domains unblocked. Remaining: \(blockedWebDomains.count)")
        #endif
    }

    /// Sync web domain shields with a complete set (replaces existing)
    func syncWebDomainShields(currentBlockedDomains: Set<WebDomainToken>) {
        #if DEBUG
        print("[ScreenTimeService] 🔄 Syncing web domain shields")
        print("[ScreenTimeService] Previous: \(blockedWebDomains.count), New: \(currentBlockedDomains.count)")
        #endif

        blockedWebDomains = currentBlockedDomains

        #if !targetEnvironment(simulator)
        managedSettingsStore.shield.webDomains = currentBlockedDomains.isEmpty ? nil : currentBlockedDomains
        #endif

        // Persist blocked domains
        persistBlockedWebDomains()

        #if DEBUG
        print("[ScreenTimeService] ✅ Web domain shields synced: \(blockedWebDomains.count) total")
        #endif
    }

    /// Get currently blocked web domains
    var currentlyBlockedWebDomains: Set<WebDomainToken> {
        return blockedWebDomains
    }

    // MARK: - Browser Blocking

    /// Block browsers by their bundle IDs
    func blockBrowsers(bundleIDs: Set<String>) {
        #if DEBUG
        print("[ScreenTimeService] 🚫 Blocking \(bundleIDs.count) browsers")
        for bundleID in bundleIDs {
            let name = Self.knownBrowserBundleIDs[bundleID] ?? bundleID
            print("[ScreenTimeService]   - \(name)")
        }
        #endif

        blockedBrowserBundleIDs.formUnion(bundleIDs)

        #if !targetEnvironment(simulator)
        let browsers = blockedBrowserBundleIDs.compactMap { Application(bundleIdentifier: $0) }
        managedSettingsStore.application.blockedApplications = Set(browsers)
        #endif

        // Persist blocked browsers
        persistBlockedBrowsers()

        #if DEBUG
        print("[ScreenTimeService] ✅ Browser blocking applied: \(blockedBrowserBundleIDs.count) browsers")
        #endif
    }

    /// Unblock browsers by their bundle IDs
    func unblockBrowsers(bundleIDs: Set<String>) {
        #if DEBUG
        print("[ScreenTimeService] 🔓 Unblocking \(bundleIDs.count) browsers")
        #endif

        blockedBrowserBundleIDs.subtract(bundleIDs)

        #if !targetEnvironment(simulator)
        if blockedBrowserBundleIDs.isEmpty {
            managedSettingsStore.application.blockedApplications = nil
        } else {
            let browsers = blockedBrowserBundleIDs.compactMap { Application(bundleIdentifier: $0) }
            managedSettingsStore.application.blockedApplications = Set(browsers)
        }
        #endif

        // Persist blocked browsers
        persistBlockedBrowsers()

        #if DEBUG
        print("[ScreenTimeService] ✅ Browsers unblocked. Remaining: \(blockedBrowserBundleIDs.count)")
        #endif
    }

    /// Block all known browsers
    func blockAllBrowsers() {
        let allBrowserIDs = Set(Self.knownBrowserBundleIDs.keys)
        blockBrowsers(bundleIDs: allBrowserIDs)
    }

    /// Unblock all browsers
    func unblockAllBrowsers() {
        let allBrowserIDs = Set(Self.knownBrowserBundleIDs.keys)
        unblockBrowsers(bundleIDs: allBrowserIDs)
    }

    /// Check if browsers are currently blocked
    var areBrowsersBlocked: Bool {
        return !blockedBrowserBundleIDs.isEmpty
    }

    /// Get currently blocked browser bundle IDs
    var currentlyBlockedBrowsers: Set<String> {
        return blockedBrowserBundleIDs
    }

    // MARK: - Web Restrictions Persistence

    private func persistBlockedWebDomains() {
        guard let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) else { return }

        // Serialize web domain tokens to Data array
        let tokenDataArray = blockedWebDomains.compactMap { token -> Data? in
            try? JSONEncoder().encode(token)
        }

        sharedDefaults.set(tokenDataArray, forKey: "blockedWebDomainTokens")

        #if DEBUG
        print("[ScreenTimeService] 💾 Persisted \(tokenDataArray.count) blocked web domains")
        #endif
    }

    private func persistBlockedBrowsers() {
        guard let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) else { return }

        sharedDefaults.set(Array(blockedBrowserBundleIDs), forKey: "blockedBrowserBundleIDs")

        #if DEBUG
        print("[ScreenTimeService] 💾 Persisted \(blockedBrowserBundleIDs.count) blocked browsers")
        #endif
    }

    /// Restore web restrictions from persistence (called on app launch)
    func restoreWebRestrictions() {
        guard let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) else { return }

        // Restore blocked web domains
        if let tokenDataArray = sharedDefaults.array(forKey: "blockedWebDomainTokens") as? [Data] {
            blockedWebDomains = Set(tokenDataArray.compactMap { data -> WebDomainToken? in
                try? JSONDecoder().decode(WebDomainToken.self, from: data)
            })

            #if !targetEnvironment(simulator)
            if !blockedWebDomains.isEmpty {
                managedSettingsStore.shield.webDomains = blockedWebDomains
            }
            #endif

            #if DEBUG
            print("[ScreenTimeService] 📂 Restored \(blockedWebDomains.count) blocked web domains")
            #endif
        }

        // Restore blocked browsers
        if let browserIDs = sharedDefaults.array(forKey: "blockedBrowserBundleIDs") as? [String] {
            blockedBrowserBundleIDs = Set(browserIDs)

            #if !targetEnvironment(simulator)
            if !blockedBrowserBundleIDs.isEmpty {
                let browsers = blockedBrowserBundleIDs.compactMap { Application(bundleIdentifier: $0) }
                managedSettingsStore.application.blockedApplications = Set(browsers)
            }
            #endif

            #if DEBUG
            print("[ScreenTimeService] 📂 Restored \(blockedBrowserBundleIDs.count) blocked browsers")
            #endif
        }
    }

    /// Clear all web restrictions
    func clearAllWebRestrictions() {
        #if DEBUG
        print("[ScreenTimeService] 🧹 Clearing all web restrictions...")
        #endif

        blockedWebDomains.removeAll()
        blockedBrowserBundleIDs.removeAll()

        #if !targetEnvironment(simulator)
        managedSettingsStore.shield.webDomains = nil
        managedSettingsStore.application.blockedApplications = nil
        managedSettingsStore.webContent.blockedByFilter = nil
        #endif

        // Clear persistence
        if let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) {
            sharedDefaults.removeObject(forKey: "blockedWebDomainTokens")
            sharedDefaults.removeObject(forKey: "blockedBrowserBundleIDs")
        }

        #if DEBUG
        print("[ScreenTimeService] ✅ All web restrictions cleared")
        #endif
    }

    // MARK: - Web Restrictions CloudKit Sync

    /// Sync current web restrictions to all paired child devices via CloudKit
    /// Called when browser blocking or website blocking changes on parent device
    func syncWebRestrictionsToChildren() async {
        // Only parent devices should sync restrictions
        guard DeviceModeManager.shared.isParentDevice else {
            #if DEBUG
            print("[ScreenTimeService] ⚠️ Not a parent device, skipping web restriction sync")
            #endif
            return
        }

        #if DEBUG
        print("[ScreenTimeService] 📤 Syncing web restrictions to children...")
        print("[ScreenTimeService]   Blocked websites: \(blockedWebDomains.count)")
        print("[ScreenTimeService]   Blocked browsers: \(blockedBrowserBundleIDs.count)")
        #endif

        do {
            // Fetch all paired child devices
            let childDevices = try await CloudKitSyncService.shared.fetchLinkedChildDevices()

            guard !childDevices.isEmpty else {
                #if DEBUG
                print("[ScreenTimeService] No paired child devices, skipping sync")
                #endif
                return
            }

            #if DEBUG
            print("[ScreenTimeService] Found \(childDevices.count) paired child device(s)")
            #endif

            // Create payload from current state
            let blockedDomainData = currentlyBlockedWebDomains.compactMap { token -> Data? in
                try? JSONEncoder().encode(token)
            }
            let payload = WebRestrictionPayload.fromCurrentState(
                parentDeviceID: DeviceModeManager.shared.deviceID,
                targetDeviceID: "", // Will be set per-device
                blockedWebDomainTokens: blockedDomainData,
                blockedBrowserBundleIDs: [] // Browser blocking handled separately
            )

            // Send to each child device
            for child in childDevices {
                guard let childDeviceID = child.deviceID else { continue }

                let childPayload = WebRestrictionPayload(
                    parentDeviceID: payload.parentDeviceID,
                    targetDeviceID: childDeviceID,
                    blockedWebDomainTokens: payload.blockedWebDomainTokens,
                    blockedBrowserBundleIDs: payload.blockedBrowserBundleIDs
                )

                do {
                    try await CloudKitSyncService.shared.sendWebRestrictionCommand(
                        deviceID: childDeviceID,
                        payload: childPayload
                    )

                    #if DEBUG
                    print("[ScreenTimeService] ✅ Web restrictions sent to child: \(childDeviceID)")
                    #endif
                } catch {
                    #if DEBUG
                    print("[ScreenTimeService] ❌ Failed to send web restrictions to \(childDeviceID): \(error)")
                    #endif
                }
            }

            #if DEBUG
            print("[ScreenTimeService] 📤 Web restriction sync complete")
            #endif
        } catch {
            #if DEBUG
            print("[ScreenTimeService] ❌ Failed to fetch child devices: \(error)")
            #endif
        }
    }

    /// Block reward apps (shield them)
    func blockRewardApps(tokens: Set<ApplicationToken>) {
        // If subscription expired, don't apply any new shields
        guard SubscriptionManager.shared.hasAccess else {
            #if DEBUG
            print("[ScreenTimeService] ⏭️ Subscription expired - not applying new shields")
            #endif
            return
        }

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

    /// Sync shields with the current reward app selection
    /// IMPORTANT: This REPLACES all shields with only the current reward tokens
    /// This ensures removed apps get unshielded even after app restart
    func syncRewardAppShields(currentRewardTokens: Set<ApplicationToken>) {
        // If subscription expired, clear all shields instead of applying
        guard SubscriptionManager.shared.hasAccess else {
            #if DEBUG
            print("[ScreenTimeService] ⏭️ Subscription expired - clearing all shields")
            #endif
            clearAllShields()
            return
        }

        #if DEBUG
        print("[ScreenTimeService] 🔄 Syncing shields with current reward app selection")
        print("[ScreenTimeService] Current reward tokens to shield: \(currentRewardTokens.count)")
        print("[ScreenTimeService] Previous in-memory tracked: \(currentlyShielded.count)")
        #endif

        // CRITICAL FIX: Replace ALL shields with ONLY the current reward tokens
        // This ensures that:
        // 1. Apps removed from rewards get unshielded (even after app restart)
        // 2. New reward apps get shielded
        // 3. We don't rely on in-memory state which resets on app launch

        let previousCount = currentlyShielded.count

        // Update our in-memory tracking
        currentlyShielded = currentRewardTokens

        // REPLACE the entire shield set in ManagedSettingsStore
        // Setting to nil clears all shields, setting to a set replaces entirely
        if currentRewardTokens.isEmpty {
            managedSettingsStore.shield.applications = nil
            #if DEBUG
            print("[ScreenTimeService] 🔓 Cleared ALL shields (no reward apps)")
            #endif
        } else {
            managedSettingsStore.shield.applications = currentRewardTokens
            #if DEBUG
            print("[ScreenTimeService] 🔒 Replaced shields with \(currentRewardTokens.count) reward apps")
            #endif
        }

        #if DEBUG
        print("[ScreenTimeService] ✅ Shield sync complete")
        print("[ScreenTimeService] Before: \(previousCount) shielded, After: \(currentRewardTokens.count) shielded")
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

    /// Get currently shielded tokens (for BlockingCoordinator refresh)
    func getCurrentlyShieldedTokens() -> Set<ApplicationToken> {
        return currentlyShielded
    }

    /// Check if a logical ID corresponds to a currently shielded app
    private func isLogicalIDShielded(_ logicalID: String) -> Bool {
        for token in currentlyShielded {
            if getLogicalID(for: token) == logicalID {
                return true
            }
        }
        return false
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
                    print("[ScreenTimeService] 💾 ===== UsageRecord CREATED =====")
                    print("   - App: \(application.displayName)")
                    print("   - Duration: \(Int(duration))s (\(Int(duration/60))min)")
                    print("   - Points: \(recordMinutes * application.rewardPoints)")
                    print("   - Category: \(application.category.rawValue)")
                    print("   - IsSynced: false (ready for CloudKit upload)")
                    print("   - DeviceID: \(deviceID)")
                    #endif
                } catch {
                    #if DEBUG
                    print("[ScreenTimeService] ❌ Failed to save UsageRecord: \(error)")
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
        print("[ScreenTimeService] 🔔 ===== THRESHOLD EVENT RECEIVED =====")
        print("   - Event name: \(event.rawValue)")
        print("   - Timestamp: \(timestamp)")
        print("   - Thread: \(Thread.isMainThread ? "Main" : "Background")")
        #endif

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

            // Check if device is paired with a parent (supports multi-parent format)
            if !DevicePairingService.shared.getPairedParents().isEmpty {
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

    /// Get display name for a given logicalID (looks up from persisted apps)
    func getDisplayName(for logicalID: String) -> String? {
        let persistedApps = usagePersistence.loadAllApps()
        return persistedApps[logicalID]?.displayName
    }

    /// Get the app group identifier for UserDefaults access
    func getAppGroupIdentifier() -> String {
        return "group.com.screentimerewards.shared"
    }

    // MARK: - Extension Shield Config Sync

    /// Get all reward app tokens from category assignments
    /// Used by BlockingCoordinator to ensure reward tokens are available for goal evaluation
    func getRewardTokens() -> Set<ApplicationToken> {
        Set(categoryAssignments.filter { $0.value == .reward }.map { $0.key })
    }

    /// Persist goal configurations to App Group for extension access
    /// This allows the extension to check learning goals and update shields directly
    func syncGoalConfigsToExtension() {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else {
            #if DEBUG
            print("[ScreenTimeService] ❌ Cannot access App Group for shield config sync")
            #endif
            return
        }

        var configs: [ExtensionGoalConfig] = []

        for (token, category) in categoryAssignments where category == .reward {
            guard let logicalID = getLogicalID(for: token),
                  let schedule = AppScheduleService.shared.getSchedule(for: logicalID),
                  !schedule.linkedLearningApps.isEmpty else {
                continue
            }

            // Serialize token using PropertyListEncoder (ApplicationToken is not directly Codable)
            guard let tokenData = try? PropertyListEncoder().encode(token) else {
                #if DEBUG
                print("[ScreenTimeService] ⚠️ Failed to encode token for \(logicalID)")
                #endif
                continue
            }

            let linkedGoals = schedule.linkedLearningApps.map { linked in
                // Read ratio from the learning app's own schedule (not from the per-link fields)
                let learningSchedule = AppScheduleService.shared.getSchedule(for: linked.logicalID)
                return ExtensionGoalConfig.LinkedGoal(
                    learningAppLogicalID: linked.logicalID,
                    minutesRequired: linked.minutesRequired,
                    ratioLearningMinutes: learningSchedule?.ratioLearningMinutes ?? 1,
                    rewardMinutesEarned: learningSchedule?.rewardMinutesEarned ?? 1
                )
            }

            // Get today's daily limit for the extension to enforce (snapshot fallback)
            let todayLimit = schedule.dailyLimits.todayLimit

            // Get today's time window for downtime enforcement (snapshot fallback)
            let todayWindow = schedule.todayTimeWindow

            // Build per-day arrays so extension can dynamically compute correct limit/window
            // regardless of which day the config was synced
            let dailyLimitsPerDay = (1...7).map { schedule.dailyLimits.limit(for: $0) }
            let timeWindowsPerDay = (1...7).map { weekday -> ExtensionGoalConfig.DayTimeWindow in
                let window = schedule.effectiveTimeWindow(for: weekday)
                return ExtensionGoalConfig.DayTimeWindow(
                    startHour: window.startHour,
                    startMinute: window.startMinute,
                    endHour: window.endHour,
                    endMinute: window.endMinute,
                    isFullDay: window.isFullDay
                )
            }

            configs.append(ExtensionGoalConfig(
                rewardAppLogicalID: logicalID,
                rewardAppTokenData: tokenData,
                linkedLearningApps: linkedGoals,
                unlockMode: schedule.unlockMode.rawValue,
                dailyLimitMinutes: todayLimit,
                allowedStartHour: todayWindow.startHour,
                allowedStartMinute: todayWindow.startMinute,
                allowedEndHour: todayWindow.endHour,
                allowedEndMinute: todayWindow.endMinute,
                isFullDayAllowed: todayWindow.isFullDay,
                dailyLimitsPerDay: dailyLimitsPerDay,
                timeWindowsPerDay: timeWindowsPerDay
            ))
        }

        let container = ExtensionShieldConfigs(goalConfigs: configs, lastUpdated: Date())
        if let data = try? JSONEncoder().encode(container) {
            defaults.set(data, forKey: ExtensionShieldConfigs.userDefaultsKey)
            #if DEBUG
            print("[ScreenTimeService] ✅ Synced \(configs.count) goal configs to extension")
            for config in configs {
                print("[ScreenTimeService]   • \(config.rewardAppLogicalID): \(config.linkedLearningApps.count) linked apps, mode=\(config.unlockMode)")
            }
            #endif
        } else {
            #if DEBUG
            print("[ScreenTimeService] ❌ Failed to encode shield configs")
            #endif
        }
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

        // Sync goal configs to extension when reward apps are assigned
        // This ensures the extension can check learning goals when usage is recorded
        if category == .reward {
            syncGoalConfigsToExtension()
        }

        // Sync AppConfiguration to CloudKit so parent device can see app list
        Task {
            await syncAppConfigurationToCloudKit(token: token, category: category)
        }
    }

    /// Sync app configuration to CloudKit for parent device visibility
    private func syncAppConfigurationToCloudKit(token: ApplicationToken, category: AppUsage.AppCategory) async {
        let context = PersistenceController.shared.container.viewContext
        let logicalID = getLogicalID(for: token) ?? usagePersistence.tokenHash(for: token)
        let deviceID = DeviceModeManager.shared.deviceID  // Use consistent ID from registration
        // Use logicalID-based lookup first (reads from persisted apps - more reliable),
        // fallback to token-based lookup (reads from familySelection), then "Unknown App"
        let displayName = getDisplayName(for: logicalID) ?? getDisplayName(for: token) ?? "Unknown App"

        await context.perform {
            // Fetch or create AppConfiguration
            let fetchRequest: NSFetchRequest<AppConfiguration> = AppConfiguration.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "logicalID == %@ AND deviceID == %@", logicalID, deviceID)

            let config: AppConfiguration
            if let existing = try? context.fetch(fetchRequest).first {
                config = existing
            } else {
                config = AppConfiguration(context: context)
                config.logicalID = logicalID
                config.deviceID = deviceID
                config.dateAdded = Date()
            }

            // Update fields
            config.category = category.rawValue
            config.displayName = displayName
            config.tokenHash = self.usagePersistence.tokenHash(for: token)
            config.pointsPerMinute = Int16(self.rewardPointsAssignments[token] ?? 1)
            config.isEnabled = true
            config.lastModified = Date()
            config.syncStatus = "pending"

            do {
                try context.save()
                #if DEBUG
                print("[ScreenTimeService] Saved AppConfiguration for \(displayName) (\(category.rawValue))")
                #endif
            } catch {
                print("[ScreenTimeService] Error saving AppConfiguration: \(error)")
            }
        }

        // Trigger CloudKit upload
        do {
            try await CloudKitSyncService.shared.uploadAppConfigurationsToParent()
        } catch {
            print("[ScreenTimeService] Error uploading AppConfiguration to CloudKit: \(error)")
        }
    }

    /// Clean up all extension UserDefaults keys for a removed app
    /// This prevents stale data from causing inflated/phantom usage when the app is re-added
    private func cleanupExtensionKeys(for logicalID: String) {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else { return }

        // Remove all ext_usage_* keys for this app
        defaults.removeObject(forKey: "ext_usage_\(logicalID)_today")
        defaults.removeObject(forKey: "ext_usage_\(logicalID)_total")
        defaults.removeObject(forKey: "ext_usage_\(logicalID)_date")
        defaults.removeObject(forKey: "ext_usage_\(logicalID)_hour")
        defaults.removeObject(forKey: "ext_usage_\(logicalID)_timestamp")
        defaults.removeObject(forKey: "ext_usage_\(logicalID)_hourly_date")

        // Remove hourly buckets (0-23)
        for hour in 0..<24 {
            defaults.removeObject(forKey: "ext_usage_\(logicalID)_hourly_\(hour)")
        }

        // Remove usage_* keys (extension internal tracking)
        defaults.removeObject(forKey: "usage_\(logicalID)_today")
        defaults.removeObject(forKey: "usage_\(logicalID)_total")
        defaults.removeObject(forKey: "usage_\(logicalID)_reset")
        defaults.removeObject(forKey: "usage_\(logicalID)_lastThreshold")
        defaults.removeObject(forKey: "usage_\(logicalID)_modified")
        defaults.removeObject(forKey: "usage_\(logicalID)_lastEventTime")

        // Remove event mapping keys (for all 60 possible events)
        let stableAppID = stableHash(logicalID)
        for minute in 1...60 {
            let eventName = "usage.app.\(stableAppID).min.\(minute)"
            defaults.removeObject(forKey: "map_\(eventName)_id")
            defaults.removeObject(forKey: "map_\(eventName)_inc")
            defaults.removeObject(forKey: "map_\(eventName)_sec")
            defaults.removeObject(forKey: "map_\(eventName)_category")
        }

        // Remove logicalID-based mappings
        defaults.removeObject(forKey: "map_\(logicalID)_category")
        defaults.removeObject(forKey: "map_\(logicalID)_name")

        // Remove re-arm keys
        defaults.removeObject(forKey: "rearm_\(logicalID)_requested")
        defaults.removeObject(forKey: "rearm_\(logicalID)_time")

        #if DEBUG
        print("[ScreenTimeService] 🧹 Cleaned up extension keys for \(logicalID)")
        #endif
    }

    /// Clean up orphaned ext_usage keys for apps that are no longer monitored
    /// This fixes existing stale data for users who already have phantom/inflated usage
    /// Call this during configureMonitoring() to clean up on app restart
    private func cleanupOrphanedExtensionKeys(currentLogicalIDs: Set<String>) {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else { return }

        let allKeys = defaults.dictionaryRepresentation().keys
        var orphanedAppIDs = Set<String>()

        // Find all app IDs by looking for ext_usage_*_today keys
        for key in allKeys where key.hasPrefix("ext_usage_") && key.hasSuffix("_today") {
            // Extract appID from "ext_usage_{appID}_today"
            let prefixLen = "ext_usage_".count
            let suffixLen = "_today".count
            guard key.count > prefixLen + suffixLen else { continue }

            let startIdx = key.index(key.startIndex, offsetBy: prefixLen)
            let endIdx = key.index(key.endIndex, offsetBy: -suffixLen)
            guard startIdx < endIdx else { continue }

            let appID = String(key[startIdx..<endIdx])
            guard !appID.isEmpty else { continue }

            // If this appID is not in the current monitored set, it's orphaned
            if !currentLogicalIDs.contains(appID) {
                orphanedAppIDs.insert(appID)
            }
        }

        // Clean up all orphaned apps
        if !orphanedAppIDs.isEmpty {
            #if DEBUG
            print("[ScreenTimeService] 🧹 Found \(orphanedAppIDs.count) orphaned app(s) with stale data")
            #endif

            for orphanedID in orphanedAppIDs {
                cleanupExtensionKeys(for: orphanedID)
            }

            #if DEBUG
            print("[ScreenTimeService] ✅ Cleaned up orphaned extension keys for \(orphanedAppIDs.count) app(s)")
            #endif
        }
    }

    /// Delete AppConfiguration entity from CoreData when an app is removed
    /// The CloudKit sync will detect this and delete the record from the cloud
    func deleteAppConfiguration(logicalID: String) {
        // Clean up extension UserDefaults keys FIRST to prevent stale data
        cleanupExtensionKeys(for: logicalID)

        let context = PersistenceController.shared.container.viewContext
        let deviceID = DeviceModeManager.shared.deviceID

        let fetchRequest: NSFetchRequest<AppConfiguration> = AppConfiguration.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "logicalID == %@ AND deviceID == %@", logicalID, deviceID)

        do {
            if let config = try context.fetch(fetchRequest).first {
                let displayName = config.displayName ?? "Unknown"
                context.delete(config)
                try context.save()
                #if DEBUG
                print("[ScreenTimeService] 🗑️ Deleted AppConfiguration for '\(displayName)' (logicalID: \(logicalID))")
                #endif
            } else {
                #if DEBUG
                print("[ScreenTimeService] No AppConfiguration found to delete for logicalID: \(logicalID)")
                #endif
            }
        } catch {
            print("[ScreenTimeService] Error deleting AppConfiguration: \(error)")
        }
    }

    /// Backfill AppConfiguration entities from all existing persisted apps
    /// This ensures apps configured before this feature was added get synced to CloudKit
    func backfillAppConfigurationsForCloudKit() async {
        #if DEBUG
        print("[ScreenTimeService] ===== Backfilling AppConfigurations from PersistedApps =====")
        #endif

        let persistedApps = usagePersistence.loadAllApps()
        guard !persistedApps.isEmpty else {
            #if DEBUG
            print("[ScreenTimeService] No persisted apps to backfill")
            #endif
            return
        }

        #if DEBUG
        print("[ScreenTimeService] Found \(persistedApps.count) persisted apps to backfill")
        #endif

        let context = PersistenceController.shared.container.viewContext
        let deviceID = DeviceModeManager.shared.deviceID  // Use consistent ID from registration

        await context.perform {
            var createdCount = 0
            var updatedCount = 0

            for (logicalID, persistedApp) in persistedApps {
                // Skip uncategorized apps
                guard persistedApp.category == "Learning" || persistedApp.category == "Reward" else {
                    continue
                }

                // Fetch or create AppConfiguration
                let fetchRequest: NSFetchRequest<AppConfiguration> = AppConfiguration.fetchRequest()
                fetchRequest.predicate = NSPredicate(format: "logicalID == %@ AND deviceID == %@", logicalID, deviceID)

                let config: AppConfiguration
                if let existing = try? context.fetch(fetchRequest).first {
                    config = existing
                    updatedCount += 1
                } else {
                    config = AppConfiguration(context: context)
                    config.logicalID = logicalID
                    config.deviceID = deviceID
                    config.dateAdded = persistedApp.createdAt
                    createdCount += 1
                }

                // Update fields from persisted app
                config.category = persistedApp.category
                config.displayName = persistedApp.displayName
                config.pointsPerMinute = Int16(persistedApp.rewardPoints)
                config.isEnabled = true
                config.lastModified = Date()
                config.syncStatus = "pending"
            }

            do {
                try context.save()
                #if DEBUG
                print("[ScreenTimeService] ✅ Backfilled \(createdCount) new + \(updatedCount) updated AppConfigurations")
                #endif
            } catch {
                print("[ScreenTimeService] ❌ Error saving backfilled AppConfigurations: \(error)")
            }
        }
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

    /// Dump all UsageRecords for debugging
    func dumpUsageRecords() {
        print("[ScreenTimeService] ===== UsageRecords Dump =====")

        let context = PersistenceController.shared.container.viewContext
        let fetchRequest: NSFetchRequest<UsageRecord> = UsageRecord.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "sessionStart", ascending: false)]

        do {
            let records = try context.fetch(fetchRequest)
            print("[ScreenTimeService] Total records: \(records.count)")

            let unsynced = records.filter { !$0.isSynced }
            let synced = records.filter { $0.isSynced }
            print("[ScreenTimeService] Unsynced: \(unsynced.count) | Synced: \(synced.count)")

            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "MM/dd HH:mm"

            for (i, r) in records.prefix(15).enumerated() {
                let date = r.sessionStart.map { dateFormatter.string(from: $0) } ?? "?"
                let mins = r.totalSeconds / 60
                let syncStatus = r.isSynced ? "✅" : "⏳"
                print("  \(i+1). \(syncStatus) \(r.displayName ?? "?") | \(mins)m | \(r.earnedPoints)pts | \(date)")
            }

            if records.count > 15 {
                print("  ... and \(records.count - 15) more")
            }
        } catch {
            print("[ScreenTimeService] ❌ Failed to fetch records: \(error)")
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

    // MARK: - Protected Extension Data (ext_ keys - Source of Truth)

    /// Structure representing protected extension usage data
    struct ExtensionUsageData {
        let todaySeconds: Int
        let totalSeconds: Int
        let date: String?
        let hour: Int
        let timestamp: Double
        let isStale: Bool  // True if data is older than 5 minutes
    }

    /// Read protected extension usage data for an app (NEVER write to these keys from main app)
    /// - Parameter appID: The logical ID of the app
    /// - Returns: Extension usage data or nil if not available
    func readExtensionUsageData(for appID: String) -> ExtensionUsageData? {
        guard let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            print("[ScreenTimeService] ⚠️ Failed to access App Group for reading ext_ keys")
            return nil
        }

        let todaySeconds = sharedDefaults.integer(forKey: "ext_usage_\(appID)_today")
        let totalSeconds = sharedDefaults.integer(forKey: "ext_usage_\(appID)_total")
        let date = sharedDefaults.string(forKey: "ext_usage_\(appID)_date")
        let hour = sharedDefaults.integer(forKey: "ext_usage_\(appID)_hour")
        let timestamp = sharedDefaults.double(forKey: "ext_usage_\(appID)_timestamp")

        // Check if we have any data
        if totalSeconds == 0 && todaySeconds == 0 && timestamp == 0 {
            return nil
        }

        // Check staleness (data older than 5 minutes)
        let isStale = timestamp > 0 && (Date().timeIntervalSince1970 - timestamp) > 300

        return ExtensionUsageData(
            todaySeconds: todaySeconds,
            totalSeconds: totalSeconds,
            date: date,
            hour: hour,
            timestamp: timestamp,
            isStale: isStale
        )
    }

    /// Validate usage data by comparing extension data (source of truth) vs app data
    /// - Parameter appID: The logical ID of the app
    /// - Returns: Tuple with extension seconds, app seconds, and difference (positive = inflation)
    func validateUsageData(for appID: String) -> (ext: Int, app: Int, diff: Int, isInflated: Bool)? {
        guard let extData = readExtensionUsageData(for: appID) else {
            return nil
        }

        let appSeconds = appUsages[appID].map { Int($0.totalTime) } ?? 0
        let diff = appSeconds - extData.totalSeconds
        let isInflated = diff > 0

        return (ext: extData.totalSeconds, app: appSeconds, diff: diff, isInflated: isInflated)
    }

    /// Validate all tracked apps and return a summary
    func validateAllUsageData() -> [(appID: String, displayName: String, ext: Int, app: Int, diff: Int, isInflated: Bool)] {
        var results: [(appID: String, displayName: String, ext: Int, app: Int, diff: Int, isInflated: Bool)] = []

        for (appID, appUsage) in appUsages {
            if let validation = validateUsageData(for: appID) {
                results.append((
                    appID: appID,
                    displayName: appUsage.appName,
                    ext: validation.ext,
                    app: validation.app,
                    diff: validation.diff,
                    isInflated: validation.isInflated
                ))
            }
        }

        return results
    }

    /// Print a comprehensive debug summary of all usage tracking data
    func printUsageTrackingDebugSummary() {
        let timestamp = ISO8601DateFormatter().string(from: Date())

        print("")
        print("╔════════════════════════════════════════════════════════════════════════════╗")
        print("║                    📊 USAGE TRACKING DEBUG SUMMARY                         ║")
        print("║                    \(timestamp)                          ║")
        print("╠════════════════════════════════════════════════════════════════════════════╣")

        // 1. Monitoring Status
        print("║ 🔍 MONITORING STATUS")
        print("║   isMonitoring: \(isMonitoring)")
        print("║   Family Selection Apps: \(familySelection.applications.count)")

        // 2. App Group Access
        print("╟────────────────────────────────────────────────────────────────────────────╢")
        print("║ 💾 APP GROUP STATUS")
        if let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) {
            print("║   ✅ App Group accessible")

            // Check for event mappings
            if let mappingData = sharedDefaults.data(forKey: "eventMappings") {
                print("║   ✅ Event mappings present: \(mappingData.count) bytes")
            } else {
                print("║   ❌ Event mappings MISSING - extension won't work!")
            }
        } else {
            print("║   ❌❌❌ CRITICAL: Cannot access App Group!")
        }

        // 3. App Usage Data with ext_ comparison
        print("╟────────────────────────────────────────────────────────────────────────────╢")
        print("║ 📱 APP USAGE DATA (\(appUsages.count) apps)")

        if appUsages.isEmpty {
            print("║   ⚠️ No app usage data recorded yet")
        } else {
            for (appID, usage) in appUsages.sorted(by: { $0.value.totalTime > $1.value.totalTime }) {
                let mins = Int(usage.totalTime) / 60
                let secs = Int(usage.totalTime) % 60
                print("║   • \(usage.appName.prefix(20)) | \(mins)m \(secs)s | \(usage.earnedRewardPoints)pts")

                // Compare with ext_ data
                if let extData = readExtensionUsageData(for: appID) {
                    let extMins = extData.totalSeconds / 60
                    let extSecs = extData.totalSeconds % 60
                    let diff = Int(usage.totalTime) - extData.totalSeconds
                    let status = diff > 0 ? "⚠️ INFLATED +\(diff)s" : (diff < 0 ? "❓ UNDER \(diff)s" : "✅ OK")
                    print("║     └─ ext_: \(extMins)m \(extSecs)s | \(status)")
                } else {
                    print("║     └─ ext_: NO DATA")
                }
            }
        }

        // 4. Validation Summary
        print("╟────────────────────────────────────────────────────────────────────────────╢")
        print("║ 🔍 VALIDATION SUMMARY")

        let validationResults = validateAllUsageData()
        if validationResults.isEmpty {
            print("║   ⚠️ No apps with ext_ data to validate")
        } else {
            let inflatedCount = validationResults.filter { $0.isInflated }.count
            let okCount = validationResults.count - inflatedCount
            print("║   Total: \(validationResults.count) | ✅ OK: \(okCount) | ❌ Inflated: \(inflatedCount)")
            if inflatedCount > 0 {
                print("║   ⚠️ DATA INFLATION DETECTED!")
                for r in validationResults where r.isInflated {
                    print("║      • \(r.displayName): app=\(r.app)s, ext=\(r.ext)s, diff=+\(r.diff)s")
                }
            }
        }

        print("╚════════════════════════════════════════════════════════════════════════════╝")
        print("")
    }

    /// Quick status line for frequent monitoring
    func printQuickStatus() {
        let totalMins = Int(appUsages.values.reduce(0) { $0 + $1.totalTime }) / 60
        let totalPts = appUsages.values.reduce(0) { $0 + $1.earnedRewardPoints }
        print("[ScreenTimeService] 📊 Status: \(appUsages.count) apps, \(totalMins)m total, \(totalPts)pts | monitoring: \(isMonitoring)")
    }
}
#endif
