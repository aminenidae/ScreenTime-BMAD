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
    
    private let service: ScreenTimeService
    private var cancellables = Set<AnyCancellable>()
    
    init(service: ScreenTimeService = .shared) {
        self.service = service
        loadData()
        NotificationCenter.default
            .publisher(for: ScreenTimeService.usageDidChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshData()
            }
            .store(in: &cancellables)
    }
    
    /// Load initial data from the service
    func loadData() {
        service.bootstrapSampleDataIfNeeded()
        refreshData()
    }
    
    /// Start monitoring app usage, updating state based on the result
    func startMonitoring() {
        guard !isMonitoring else { return }
        errorMessage = nil
        service.startMonitoring { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                self.isMonitoring = true
                self.refreshData()
            case .failure(let error):
                self.isMonitoring = false
                self.errorMessage = error.errorDescription ?? "An unknown monitoring error occurred."
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
        updateCategoryTotals()
    }
    
    /// Update category totals using the locally cached data
    private func updateCategoryTotals() {
        educationalTime = appUsages
            .filter { $0.category == .educational }
            .reduce(0) { $0 + $1.totalTime }
        entertainmentTime = appUsages
            .filter { $0.category == .entertainment }
            .reduce(0) { $0 + $1.totalTime }
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
    
    func configureMonitoring() {
        #if DEBUG
        print("Selected applications: \(familySelection.applications.map { $0.bundleIdentifier ?? "unknown" })")
        #endif
        let thresholds = thresholdMinutes.reduce(into: [AppUsage.AppCategory: DateComponents]()) { result, entry in
            result[entry.key] = DateComponents(minute: entry.value)
        }
        service.configureMonitoring(with: familySelection, thresholds: thresholds.isEmpty ? nil : thresholds)
    }
    
    /// Format time interval for display
    func formatTime(_ timeInterval: TimeInterval) -> String {
        let hours = Int(timeInterval) / 3600
        let minutes = Int(timeInterval) / 60 % 60
        let seconds = Int(timeInterval) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}
