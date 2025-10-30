import Foundation
import Combine
import CloudKit
import CoreData

@MainActor
class ParentRemoteViewModel: ObservableObject {
    @Published var linkedChildDevices: [RegisteredDevice] = []
    @Published var selectedChildDevice: RegisteredDevice?
    @Published var usageRecords: [UsageRecord] = []
    @Published var dailySummaries: [DailySummary] = []
    @Published var appConfigurations: [AppConfiguration] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let cloudKitService = CloudKitSyncService.shared
    private let offlineQueue = OfflineQueueManager.shared
    private var cancellables = Set<AnyCancellable>()

    init() {
        setupCloudKitNotifications()
        Task {
            await loadLinkedChildDevices()
        }
    }

    deinit {
        cancellables.removeAll()
    }

    /// Setup CloudKit notifications to auto-refresh when data syncs
    private func setupCloudKitNotifications() {
        NotificationCenter.default.publisher(for: NSPersistentCloudKitContainer.eventChangedNotification)
            .sink { [weak self] notification in
                guard let self = self,
                      let event = notification.userInfo?["event"] as? NSPersistentCloudKitContainer.Event else {
                    return
                }

                #if DEBUG
                print("[ParentRemoteViewModel] CloudKit event: \(event)")
                #endif

                // Auto-refresh when import completes successfully
                if event.type == .import && event.succeeded {
                    #if DEBUG
                    print("[ParentRemoteViewModel] CloudKit import succeeded, refreshing child devices...")
                    #endif

                    Task { @MainActor in
                        await self.loadLinkedChildDevices()
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    /// Load all linked child devices for the parent
    func loadLinkedChildDevices() async {
        #if DEBUG
        print("[ParentRemoteViewModel] ===== Loading Linked Child Devices =====")
        #endif

        isLoading = true
        errorMessage = nil

        do {
            linkedChildDevices = try await cloudKitService.fetchLinkedChildDevices()

            #if DEBUG
            print("[ParentRemoteViewModel] Loaded \(linkedChildDevices.count) child devices")
            #endif

            // If no device is selected and we have devices, select the first one
            if selectedChildDevice == nil, let firstDevice = linkedChildDevices.first {
                #if DEBUG
                print("[ParentRemoteViewModel] Auto-selecting first device: \(firstDevice.deviceID ?? "nil")")
                #endif
                selectedChildDevice = firstDevice
                await loadChildData(for: firstDevice)
            }
        } catch let error as CKError {
            #if DEBUG
            print("[ParentRemoteViewModel] CloudKit error: \(error)")
            #endif
            handleCloudKitError(error)
        } catch {
            errorMessage = "Failed to load child devices: \(error.localizedDescription)"
            print("[ParentRemoteViewModel] Error loading child devices: \(error)")
        }

        isLoading = false
    }
    
    /// Load usage data and configurations for a specific child device
    func loadChildData(for device: RegisteredDevice) async {
        isLoading = true
        errorMessage = nil
        
        selectedChildDevice = device
        
        do {
            // Load usage records for the last 7 days
            let calendar = Calendar.current
            let endDate = Date()
            let startDate = calendar.date(byAdding: .day, value: -7, to: endDate)!
            let dateRange = DateInterval(start: startDate, end: endDate)
            
            usageRecords = try await cloudKitService.fetchChildUsageData(
                deviceID: device.deviceID ?? "",
                dateRange: dateRange
            )
            
            // Load daily summaries for the last 7 days
            dailySummaries = []
            for i in 0..<7 {
                if let date = calendar.date(byAdding: .day, value: -i, to: endDate) {
                    if let summary = try await cloudKitService.fetchChildDailySummary(
                        deviceID: device.deviceID ?? "",
                        date: date
                    ) {
                        dailySummaries.append(summary)
                    }
                }
            }
            
            // Load app configurations
            appConfigurations = try await cloudKitService.downloadParentConfiguration()
        } catch let error as CKError {
            handleCloudKitError(error)
        } catch {
            errorMessage = "Failed to load child data: \(error.localizedDescription)"
            print("[ParentRemoteViewModel] Error loading child data: \(error)")
        }
        
        isLoading = false
    }
    
    /// Send a configuration update to a child device
    func sendConfigurationUpdate(_ configuration: AppConfiguration) async {
        guard let selectedDevice = selectedChildDevice else { return }
        
        do {
            try await cloudKitService.sendConfigurationToChild(
                deviceID: selectedDevice.deviceID ?? "",
                configuration: configuration
            )
            
            // Refresh configurations
            await loadChildData(for: selectedDevice)
        } catch let error as CKError {
            handleCloudKitError(error)
        } catch {
            errorMessage = "Failed to send configuration: \(error.localizedDescription)"
            print("[ParentRemoteViewModel] Error sending configuration: \(error)")
        }
    }
    
    /// Request a sync from the child device
    func requestChildSync() async {
        guard let selectedDevice = selectedChildDevice else { return }
        
        do {
            try await cloudKitService.requestChildSync(deviceID: selectedDevice.deviceID ?? "")
        } catch let error as CKError {
            handleCloudKitError(error)
        } catch {
            errorMessage = "Failed to request sync: \(error.localizedDescription)"
            print("[ParentRemoteViewModel] Error requesting sync: \(error)")
        }
    }
    
    /// Force a sync now
    func forceSyncNow() async {
        do {
            try await cloudKitService.forceSyncNow()
        } catch let error as CKError {
            handleCloudKitError(error)
        } catch {
            errorMessage = "Failed to force sync: \(error.localizedDescription)"
            print("[ParentRemoteViewModel] Error forcing sync: \(error)")
        }
    }
    
    /// Handle CloudKit specific errors
    private func handleCloudKitError(_ error: CKError) {
        switch error.code {
        case .notAuthenticated:
            errorMessage = "iCloud account not signed in. Please sign in to iCloud in Settings."
        case .networkUnavailable, .networkFailure:
            errorMessage = "Network unavailable. Please check your connection and try again."
        case .quotaExceeded:
            errorMessage = "iCloud storage quota exceeded. Please free up space in iCloud."
        case .zoneBusy:
            errorMessage = "iCloud is busy. Please try again in a moment."
        case .badContainer, .badDatabase:
            errorMessage = "iCloud configuration error. Please contact support."
        case .permissionFailure:
            errorMessage = "Insufficient permissions. Please check iCloud settings."
        default:
            errorMessage = "iCloud error: \(error.localizedDescription)"
        }
        
        print("[ParentRemoteViewModel] CloudKit error (\(error.code)): \(error.localizedDescription)")
    }
}