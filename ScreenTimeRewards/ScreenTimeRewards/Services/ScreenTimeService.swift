import Foundation
import DeviceActivity
import FamilyControls

/// Service to handle Screen Time API functionality while exposing deterministic
/// state for the SwiftUI layer.
class ScreenTimeService: NSObject {
    static let shared = ScreenTimeService()
    
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
    
    override private init() {
        deviceActivityCenter = DeviceActivityCenter()
        super.init()
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
        try deviceActivityCenter.startMonitoring(activityName, during: schedule)
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
    }
}
