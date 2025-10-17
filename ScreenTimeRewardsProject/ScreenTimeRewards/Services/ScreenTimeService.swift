import Foundation
import CoreFoundation
import DeviceActivity
import FamilyControls
import ManagedSettings

/// Service to handle Screen Time API functionality while exposing deterministic
/// state for the SwiftUI layer.
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
    private var appUsages: [String: AppUsage] = [:]
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

    private struct MonitoredApplication {
        let token: ManagedSettings.ApplicationToken  // Required for monitoring
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
    
    override private init() {
        deviceActivityCenter = DeviceActivityCenter()
        super.init()
        activityMonitor.delegate = self
        registerForExtensionNotifications()
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
        #if DEBUG
        print("[ScreenTimeService] Configuring monitoring with \(selection.applications.count) applications")
        print("[ScreenTimeService] Selection details:")
        print("[ScreenTimeService]   Applications count: \(selection.applications.count)")
        print("[ScreenTimeService]   Categories count: \(selection.categories.count)")
        print("[ScreenTimeService]   WebDomains count: \(selection.webDomains.count)")
        #endif
    
        // Log detailed information about each selected application
        for (index, application) in selection.applications.enumerated() {
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

        for (index, application) in selection.applications.enumerated() {
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

            let monitored = MonitoredApplication(
                token: token,
                displayName: displayName,
                category: category,
                rewardPoints: points,
                bundleIdentifier: bundleIdentifier
            )
            groupedApplications[category, default: []].append(monitored)
        }

        #if DEBUG
        print("[ScreenTimeService] Grouped applications by category:")
        for (category, apps) in groupedApplications {
            print("[ScreenTimeService]   \(category.rawValue): \(apps.count) applications")
            for app in apps {
                print("[ScreenTimeService]     - \(app.displayName) (\(app.bundleIdentifier ?? "nil")) - \(app.rewardPoints) points")
            }
        }
        #endif

        monitoredEvents = groupedApplications.reduce(into: [:]) { result, entry in
            let (category, applications) = entry
            guard !applications.isEmpty else { 
                #if DEBUG
                print("[ScreenTimeService] No applications in category \(category.rawValue)")
                #endif
                return 
            }
            let threshold = providedThresholds[category] ?? defaultThreshold
            let safeCategoryIdentifier = category.rawValue
                .replacingOccurrences(of: " ", with: "")
                .lowercased()
            let eventName = DeviceActivityEvent.Name("usage.\(safeCategoryIdentifier)")
        
            #if DEBUG
            print("[ScreenTimeService] Creating monitored event for category \(category.rawValue) with \(applications.count) applications")
            print("[ScreenTimeService] Event name: \(eventName.rawValue)")
            print("[ScreenTimeService] Threshold: \(threshold)")
            #endif
        
            result[eventName] = MonitoredEvent(
                name: eventName,
                category: category,
                threshold: threshold,
                applications: applications
            )
        }

        #if DEBUG
        print("[ScreenTimeService] Created \(monitoredEvents.count) monitored events")
        for (name, event) in monitoredEvents {
            print("[ScreenTimeService]   Event: \(name.rawValue) with \(event.applications.count) apps")
        }
        #endif

        hasSeededSampleData = false
        appUsages.removeAll()
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

        for application in applications {
            // Check if app is currently shielded (blocked)
            if currentlyShielded.contains(application.token) {
                #if DEBUG
                print("[ScreenTimeService] 🛑 SKIPPING \(application.displayName) - currently blocked (shield time, not real usage)")
                #endif
                skippedCount += 1
                continue  // Skip this app - it's shield time!
            }

            #if DEBUG
            print("[ScreenTimeService] ✅ Recording usage for \(application.displayName) - app is unblocked")
            #endif

            // Use bundle ID if available, otherwise use display name as key
            let storageKey = application.bundleIdentifier ?? "app.\(application.displayName.replacingOccurrences(of: " ", with: ".").lowercased())"

            if var existing = appUsages[storageKey] {
                #if DEBUG
                print("[ScreenTimeService] Updating existing usage for \(storageKey)")
                #endif
                existing.recordUsage(duration: duration, endingAt: endDate)
                appUsages[storageKey] = existing
            } else {
                #if DEBUG
                print("[ScreenTimeService] Creating new usage record for \(storageKey)")
                #endif
                let session = AppUsage.UsageSession(startTime: endDate.addingTimeInterval(-duration), endTime: endDate)
                let usage = AppUsage(
                    bundleIdentifier: storageKey,  // Use storage key
                    appName: application.displayName,
                    category: application.category,
                    totalTime: duration,
                    sessions: [session],
                    firstAccess: session.startTime,
                    lastAccess: endDate,
                    rewardPoints: application.rewardPoints
                )
                appUsages[storageKey] = usage
            }
            recordedCount += 1
        }

        #if DEBUG
        print("[ScreenTimeService] ✅ Recorded usage for \(recordedCount) apps, skipped \(skippedCount) blocked apps")
        #endif

        // Only notify if we actually recorded something
        if recordedCount > 0 {
            notifyUsageChange()
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
}

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