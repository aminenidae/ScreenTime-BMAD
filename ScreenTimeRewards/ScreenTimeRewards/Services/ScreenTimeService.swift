import Foundation
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

    private struct MonitoredApplication {
        let bundleIdentifier: String
        let displayName: String
        let category: AppUsage.AppCategory
        let token: ManagedSettings.ApplicationToken?
    }

    private struct MonitoredEvent {
        let name: DeviceActivityEvent.Name
        let category: AppUsage.AppCategory
        let threshold: DateComponents
        let applications: [MonitoredApplication]

        func deviceActivityEvent() -> DeviceActivityEvent {
            DeviceActivityEvent(
                applications: Set(applications.compactMap { $0.token }),
                threshold: threshold
            )
        }
    }

    private let activityMonitor = ScreenTimeActivityMonitor()
    private let defaultThreshold = DateComponents(minute: 15)
    private var monitoredEvents: [DeviceActivityEvent.Name: MonitoredEvent] = [:]
    
    override private init() {
        deviceActivityCenter = DeviceActivityCenter()
        super.init()
        activityMonitor.delegate = self
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
            category: .educational,
            totalTime: hour,
            sessions: booksSessions,
            firstAccess: now.addingTimeInterval(-86400),
            lastAccess: now.addingTimeInterval(-hour)
        )
        let calculator = AppUsage(
            bundleIdentifier: "com.apple.calculator",
            appName: "Calculator",
            category: .productivity,
            totalTime: 600,
            sessions: calculatorSessions,
            firstAccess: now.addingTimeInterval(-172800),
            lastAccess: now.addingTimeInterval(-hour * 6 + 600)
        )
        let music = AppUsage(
            bundleIdentifier: "com.apple.Music",
            appName: "Music",
            category: .entertainment,
            totalTime: halfHour,
            sessions: musicSessions,
            firstAccess: now.addingTimeInterval(-432000),
            lastAccess: now.addingTimeInterval(-halfHour)
        )
        
        appUsages = [
            books.bundleIdentifier: books,
            calculator.bundleIdentifier: calculator,
            music.bundleIdentifier: music
        ]
    }

    private func categorizeApp(bundleIdentifier: String) -> AppUsage.AppCategory {
        if bundleIdentifier.contains("education") || bundleIdentifier.contains("book") || bundleIdentifier.contains("learn") {
            return .educational
        } else if bundleIdentifier.contains("game") || bundleIdentifier.contains("games") {
            return .games
        } else if bundleIdentifier.contains("social") || bundleIdentifier.contains("facebook") || bundleIdentifier.contains("twitter") || bundleIdentifier.contains("instagram") {
            return .social
        } else if bundleIdentifier.contains("music") || bundleIdentifier.contains("video") || bundleIdentifier.contains("entertainment") {
            return .entertainment
        } else if bundleIdentifier.contains("productivity") || bundleIdentifier.contains("work") || bundleIdentifier.contains("office") {
            return .productivity
        } else if bundleIdentifier.contains("utility") || bundleIdentifier.contains("tool") {
            return .utility
        } else {
            return .other
        }
    }

    /// Configure monitoring using a user-selected family activity selection.
    /// - Parameters:
    ///   - selection: The selection of applications/categories chosen by the parent.
    ///   - thresholds: Optional per-category thresholds that dictate when events fire.
    func configureMonitoring(
        with selection: FamilyActivitySelection,
        thresholds: [AppUsage.AppCategory: DateComponents]? = nil
    ) {
        let providedThresholds = thresholds ?? [:]

        var groupedApplications: [AppUsage.AppCategory: [MonitoredApplication]] = [:]

        for application in selection.applications {
            guard let bundleIdentifier = application.bundleIdentifier else { continue }
            let category = categorizeApp(bundleIdentifier: bundleIdentifier)
            let displayName = application.localizedDisplayName ?? bundleIdentifier
            let monitored = MonitoredApplication(
                bundleIdentifier: bundleIdentifier,
                displayName: displayName,
                category: category,
                token: application.token
            )
            groupedApplications[category, default: []].append(monitored)
        }

        monitoredEvents = groupedApplications.reduce(into: [:]) { result, entry in
            let (category, applications) = entry
            guard !applications.isEmpty else { return }
            let threshold = providedThresholds[category] ?? defaultThreshold
            let safeCategoryIdentifier = category.rawValue
                .replacingOccurrences(of: " ", with: "")
                .lowercased()
            let eventName = DeviceActivityEvent.Name("usage.\(safeCategoryIdentifier)")
            result[eventName] = MonitoredEvent(
                name: eventName,
                category: category,
                threshold: threshold,
                applications: applications
            )
        }

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
        try deviceActivityCenter.startMonitoring(activityName, during: schedule, events: events)
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
    
    func resetData() {
        appUsages.removeAll()
        hasSeededSampleData = false
        isMonitoring = false
        notifyUsageChange()
    }

    private func notifyUsageChange() {
        NotificationCenter.default.post(name: Self.usageDidChangeNotification, object: nil)
    }

    private func recordUsage(for applications: [MonitoredApplication], duration: TimeInterval, endingAt endDate: Date = Date()) {
        guard duration > 0 else { return }
        for application in applications {
            if var existing = appUsages[application.bundleIdentifier] {
                existing.recordUsage(duration: duration, endingAt: endDate)
                appUsages[application.bundleIdentifier] = existing
            } else {
                let session = AppUsage.UsageSession(startTime: endDate.addingTimeInterval(-duration), endTime: endDate)
                let usage = AppUsage(
                    bundleIdentifier: application.bundleIdentifier,
                    appName: application.displayName,
                    category: application.category,
                    totalTime: duration,
                    sessions: [session],
                    firstAccess: session.startTime,
                    lastAccess: endDate
                )
                appUsages[application.bundleIdentifier] = usage
            }
        }
        notifyUsageChange()
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
        guard let configuration = monitoredEvents[event] else { return }
        let duration = seconds(from: configuration.threshold)
        recordUsage(for: configuration.applications, duration: duration, endingAt: timestamp)
    }

    fileprivate func handleEventWillReachThresholdWarning(_ event: DeviceActivityEvent.Name) {
        #if DEBUG
        print("[ScreenTimeService] Event \(event.rawValue) will reach threshold soon")
        #endif
    }

#if DEBUG
    /// Configure monitored events using plain bundle identifiers for unit testing.
    func configureForTesting(
        applications: [(bundleIdentifier: String, name: String, category: AppUsage.AppCategory)],
        threshold: DateComponents = DateComponents(minute: 15)
    ) {
        let grouped = applications.reduce(into: [AppUsage.AppCategory: [MonitoredApplication]]()) { result, entry in
            let monitored = MonitoredApplication(
                bundleIdentifier: entry.bundleIdentifier,
                displayName: entry.name,
                category: entry.category,
                token: nil
            )
            result[entry.category, default: []].append(monitored)
        }

        monitoredEvents = grouped.reduce(into: [:]) { result, element in
            let (category, apps) = element
            guard !apps.isEmpty else { return }
            let name = DeviceActivityEvent.Name("usage.\(category.rawValue.lowercased())")
            result[name] = MonitoredEvent(name: name, category: category, threshold: threshold, applications: apps)
        }

        hasSeededSampleData = false
        appUsages.removeAll()
        notifyUsageChange()
    }

    /// Simulate the delivery of a DeviceActivity event for testing purposes.
    func simulateEvent(named name: DeviceActivityEvent.Name, customDuration: TimeInterval? = nil, timestamp: Date = Date()) {
        if let duration = customDuration, let configuration = monitoredEvents[name] {
            recordUsage(for: configuration.applications, duration: duration, endingAt: timestamp)
        } else {
            handleEventThresholdReached(name, timestamp: timestamp)
        }
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

private protocol ScreenTimeActivityMonitorDelegate: AnyObject {
    func activityMonitorDidStartInterval(_ activity: DeviceActivityName)
    func activityMonitorWillStartInterval(_ activity: DeviceActivityName)
    func activityMonitorDidEndInterval(_ activity: DeviceActivityName)
    func activityMonitorWillEndInterval(_ activity: DeviceActivityName)
    func activityMonitorDidReachThreshold(for event: DeviceActivityEvent.Name)
    func activityMonitorWillReachThreshold(for event: DeviceActivityEvent.Name)
}

private final class ScreenTimeActivityMonitor: DeviceActivityMonitor {
    weak var delegate: ScreenTimeActivityMonitorDelegate?

    override nonisolated init() {
        super.init()
    }

    override nonisolated func intervalDidStart(for activity: DeviceActivityName) {
        delegate?.activityMonitorDidStartInterval(activity)
    }

    override nonisolated func intervalWillStartWarning(for activity: DeviceActivityName) {
        delegate?.activityMonitorWillStartInterval(activity)
    }

    override nonisolated func intervalDidEnd(for activity: DeviceActivityName) {
        delegate?.activityMonitorDidEndInterval(activity)
    }

    override nonisolated func intervalWillEndWarning(for activity: DeviceActivityName) {
        delegate?.activityMonitorWillEndInterval(activity)
    }

    override nonisolated func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        delegate?.activityMonitorDidReachThreshold(for: event)
    }

    override nonisolated func eventWillReachThresholdWarning(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        delegate?.activityMonitorWillReachThreshold(for: event)
    }
}
