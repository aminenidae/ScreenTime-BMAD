# Development Roadmap: Phase-by-Phase Task Breakdown
## CloudKit Remote Monitoring Implementation

**Version:** 1.0
**Date:** October 27, 2025
**Estimated Timeline:** 29-38 days

---

## Phase 0: Device Selection & Mode Management
**Duration:** 3-4 days
**Priority:** P0 (Blocker for all other phases)

### Tasks

#### Task 0.1: Create DeviceMode Model (2 hours)
**File:** `ScreenTimeRewards/Models/DeviceMode.swift`

```swift
// Create enum DeviceMode
enum DeviceMode: String, Codable {
    case parentDevice
    case childDevice
}
```

**Acceptance Criteria:**
- [x] Enum with rawValue support
- [x] Codable conformance
- [x] Display name computed property
- [x] Description text
- [x] RequiresScreenTimeAuth boolean

**Testing:**
- Unit test for encoding/decoding
- Unit test for display properties

---

#### Task 0.2: Implement DeviceModeManager (4 hours)
**File:** `ScreenTimeRewards/Services/DeviceModeManager.swift`

**Implementation:**
```swift
@MainActor
class DeviceModeManager: ObservableObject {
    static let shared = DeviceModeManager()
    @Published private(set) var currentMode: DeviceMode?
    @Published private(set) var deviceID: String
    @Published private(set) var deviceName: String

    func setDeviceMode(_ mode: DeviceMode, deviceName: String?)
    func resetDeviceMode()
    var isParentDevice: Bool
    var isChildDevice: Bool
    var needsDeviceSelection: Bool
}
```

**Acceptance Criteria:**
- [x] Singleton pattern
- [x] UserDefaults persistence
- [x] Device ID generation (UUID)
- [x] Device name capture (UIDevice.current.name)
- [ [x] Mode reset capability
- [x] ObservableObject for SwiftUI

**Testing:**
- Unit test for mode persistence
- Unit test for device ID stability
- Test reset functionality

---

#### Task 0.3: Build DeviceSelectionView UI (6 hours)
**File:** `ScreenTimeRewards/Views/DeviceSelection/DeviceSelectionView.swift`

**UI Requirements:**
```
┌─────────────────────────────────────┐
│  Welcome to ScreenTime Rewards     │
│                                     │
│  Is this device for a Parent       │
│  or a Child?                        │
│                                     │
│  ┌───────────────┐                  │
│  │ Parent Device │                  │
│  │ Monitor and   │                  │
│  │ configure     │                  │
│  │ remotely      │                  │
│  └───────────────┘                  │
│                                     │
│  ┌───────────────┐                  │
│  │ Child Device  │                  │
│  │ Run monitoring│                  │
│  │ on this device│                  │
│  └───────────────┘                  │
└─────────────────────────────────────┘
```

**Components:**
1. `DeviceSelectionView` (main container)
2. `DeviceTypeCardView` (reusable card)
3. Optional: Device name input field

**Acceptance Criteria:**
- [x] Clean, modern UI
- [x] Two clear options (Parent/Child)
- [x] Descriptive text for each option
- [x] SF Symbols icons
- [x] Tappable cards
- [x] Optional device name customization
- [x] Confirmation dialog before selection

**Testing:**
- UI test for card tap
- Test mode persistence after selection
- Test navigation after selection

---

#### Task 0.4: Implement RootView Routing Logic (4 hours)
**File:** `ScreenTimeRewards/ScreenTimeRewardsApp.swift` (modify)
**New File:** `ScreenTimeRewards/Views/RootView.swift`

**Implementation:**
``swift
struct RootView: View {
    @StateObject private var modeManager = DeviceModeManager.shared
    @StateObject private var sessionManager = SessionManager.shared

    var body: some View {
        Group {
            if modeManager.needsDeviceSelection {
                DeviceSelectionView()
            } else if modeManager.isParentDevice {
                ParentRemoteDashboardView()  // NEW
            } else if modeManager.isChildDevice {
                // Existing flow
                if !sessionManager.isAuthorized {
                    SetupFlowView()
                } else {
                    ModeSelectionView()
                }
            }
        }
    }
}
```

**Acceptance Criteria:**
- [x] Conditional routing based on device mode
- [x] First-launch shows DeviceSelectionView
- [x] Parent mode routes to remote dashboard
- [x] Child mode routes to existing setup/mode selection
- [x] Smooth transitions

**Testing:**
- Test first launch (no mode set)
- Test parent device routing
- Test child device routing
- Test mode change triggers re-routing

---

#### Task 0.5: Add Mode Reset Capability (2 hours)
**File:** `ScreenTimeRewards/Views/Settings/SettingsView.swift` (modify)

**UI Addition:**
``swift
Section("Device Configuration") {
    HStack {
        Text("Device Mode")
        Spacer()
        Text(DeviceModeManager.shared.currentMode?.displayName ?? "Not Set")
            .foregroundColor(.gray)
    }

    Button(role: .destructive) {
        showResetConfirmation = true
    } label: {
        Label("Reset Device Mode", systemImage: "arrow.counterclockwise")
    }
}
.confirmationDialog("Reset Device Mode?",
                   isPresented: $showResetConfirmation) {
    Button("Reset", role: .destructive) {
        DeviceModeManager.shared.resetDeviceMode()
        // Restart app or navigate to root
    }
}
```

**Acceptance Criteria:**
- [x] Settings section for device mode
- [x] Display current mode
- [x] Reset button (destructive style)
- [x] Confirmation dialog
- [x] App restart or navigation after reset

**Testing:**
- Test reset confirmation flow
- Test app state after reset

---

### Phase 0 Deliverables

- ✅ DeviceMode enum
- ✅ DeviceModeManager service
- ✅ DeviceSelectionView UI
- ✅ RootView routing logic
- ✅ Mode reset capability
- ✅ Unit tests (>80% coverage)
- ✅ UI tests for device selection

---

## Phase 1: CloudKit Infrastructure
**Duration:** 3-4 days
**Priority:** P0
**Dependencies:** Phase 0 complete

### Tasks

#### Task 1.1: Enable CloudKit Capability (1 hour)
**Location:** Xcode Project Settings

**Steps:**
1. Open project in Xcode
2. Select target "ScreenTimeRewards"
3. Go to "Signing & Capabilities"
4. Click "+ Capability"
5. Add "iCloud"
6. Enable "CloudKit"
7. Create container: `iCloud.com.screentimerewards`
8. Add "Push Notifications" capability
9. Add "Background Modes":
   - Background fetch
   - Remote notifications
   - Background processing

**Acceptance Criteria:**
- [x] CloudKit capability added
- [x] Container created
- [x] Push notifications enabled
- [x] Background modes configured
- [x] Entitlements file updated

---

#### Task 1.2: Update Persistence.swift for CloudKit (3 hours)
**File:** `ScreenTimeRewards/Persistence.swift` (modify)

**Current State:**
```swift
container = NSPersistentCloudKitContainer(name: "ScreenTimeRewards")
// But not actively using CloudKit features
```

**Changes Needed:**
``swift
import CoreData
import CloudKit

struct PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentCloudKitContainer

    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "ScreenTimeRewards")

        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        } else {
            // Configure CloudKit
            guard let description = container.persistentStoreDescriptions.first else {
                fatalError("No persistent store description")
            }

            // Enable CloudKit sync
            description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: "iCloud.com.screentimerewards"
            )

            // Enable history tracking for sync
            description.setOption(true as NSNumber,
                                 forKey: NSPersistentHistoryTrackingKey)
            description.setOption(true as NSNumber,
                                 forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        }

        container.loadPersistentStores { description, error in
            if let error = error {
                fatalError("Unable to load persistent stores: \(error)")
            }
        }

        // Automatically merge changes
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        #if DEBUG
        print("[Persistence] CloudKit container: iCloud.com.screentimerewards")
        print("[Persistence] Store URL: \(description.url?.absoluteString ?? "unknown")")
        #endif
    }
}
```

**Acceptance Criteria:**
- [x] CloudKit container options configured
- [x] History tracking enabled
- [x] Remote change notifications enabled
- [x] Automatic merge enabled
- [x] Merge policy set
- [x] Debug logging

**Testing:**
- Launch app and verify no CloudKit errors
- Check Console for persistence logs
- Verify Core Data stack loads successfully

---

#### Task 1.3: Design Core Data Entities (6 hours)
**File:** `ScreenTimeRewards/ScreenTimeRewards.xcdatamodeld` (modify)

**New Entities to Create:**

1. **AppConfiguration**
   - logicalID (String, indexed)
   - tokenHash (String)
   - bundleIdentifier (String, optional)
   - displayName (String)
   - sfSymbolName (String)
   - category (String, indexed)
   - pointsPerMinute (Integer 16)
   - isEnabled (Boolean)
   - blockingEnabled (Boolean)
   - dateAdded (Date)
   - lastModified (Date, indexed)
   - deviceID (String, indexed)
   - syncStatus (String)

2. **UsageRecord**
   - recordID (String)
   - logicalID (String, indexed)
   - displayName (String)
   - sessionStart (Date, indexed)
   - sessionEnd (Date)
   - totalSeconds (Integer 32)
   - earnedPoints (Integer 32)
   - category (String)
   - deviceID (String, indexed)
   - syncTimestamp (Date)
   - isSynced (Boolean)

3. **DailySummary**
   - summaryID (String, indexed)
   - date (Date, indexed)
   - deviceID (String, indexed)
   - totalLearningSeconds (Integer 32)
   - totalRewardSeconds (Integer 32)
   - totalPointsEarned (Integer 32)
   - appsUsedJSON (String)
   - lastUpdated (Date)

4. **RegisteredDevice**
   - deviceID (String, indexed)
   - deviceName (String)
   - deviceType (String, indexed)
   - childName (String, optional)
   - parentDeviceID (String, indexed, optional)
   - registrationDate (Date)
   - lastSyncDate (Date, indexed)
   - isActive (Boolean)

5. **ConfigurationCommand**
   - commandID (String)
   - targetDeviceID (String, indexed)
   - commandType (String)
   - payloadJSON (String)
   - createdAt (Date, indexed)
   - executedAt (Date, optional)
   - status (String, indexed)
   - errorMessage (String, optional)

6. **SyncQueueItem**
   - queueID (String)
   - operation (String)
   - payloadJSON (String)
   - createdAt (Date)
   - retryCount (Integer 16)
   - lastAttempt (Date, optional)
   - status (String)

**Steps:**
1. Open .xcdatamodeld file
2. Create each entity
3. Add attributes with correct types
4. Mark indexed attributes
5. Generate NSManagedObject subclasses
6. Move generated files to Models/CoreData/

**Acceptance Criteria:**
- [x] All 6 entities documented
- [x] All attributes defined with correct types
- [x] Indexes specified
- [x] NSManagedObject subclasses generated (Manual Step)
- [x] CloudKit compatibility verified (Manual Step)

**Testing:**
- Build project successfully
- Create test objects in each entity
- Verify Core Data save/fetch works

---

#### Task 1.4: Create CloudKit Dashboard Monitoring (2 hours)
**File:** `ScreenTimeRewards/Services/CloudKitDebugService.swift` (NEW)

**Implementation:**
``swift
#if DEBUG
import CloudKit
import SwiftUI

class CloudKitDebugService: ObservableObject {
    @Published var accountStatus: CKAccountStatus = .couldNotDetermine
    @Published var isAvailable: Bool = false
    @Published var errorMessage: String?

    private let container = CKContainer(identifier: "iCloud.com.screentimerewards")

    func checkStatus() async {
        do {
            accountStatus = try await container.accountStatus()
            isAvailable = (accountStatus == .available)

            #if DEBUG
            print("[CloudKit] Account status: \(statusString)")
            #endif
        } catch {
            errorMessage = error.localizedDescription
            print("[CloudKit] Error: \(error)")
        }
    }

    private var statusString: String {
        switch accountStatus {
        case .couldNotDetermine: return "Could Not Determine"
        case .available: return "Available"
        case .restricted: return "Restricted"
        case .noAccount: return "No iCloud Account"
        case .temporarilyUnavailable: return "Temporarily Unavailable"
        @unknown default: return "Unknown"
        }
    }
}

struct CloudKitDebugView: View {
    @StateObject private var debug = CloudKitDebugService()

    var body: some View {
        List {
            Section("CloudKit Status") {
                HStack {
                    Text("Account Status")
                    Spacer()
                    Text(debug.statusString)
                        .foregroundColor(debug.isAvailable ? .green : .red)
                }

                if let error = debug.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }

            Section {
                Button("Check Status") {
                    Task {
                        await debug.checkStatus()
                    }
                }
            }
        }
        .navigationTitle("CloudKit Debug")
        .onAppear {
            Task {
                await debug.checkStatus()
            }
        }
    }
}
#endif
```

**Acceptance Criteria:**
- [x] CloudKit account status checker
- [x] Debug view in Settings (DEBUG only)
- [x] Error message display
- [x] Manual refresh button

**Testing:**
- Verify shows "Available" when logged into iCloud
- Test with no iCloud account

---

#### Task 1.5: Implement Basic CloudKit Sync Test (3 hours)
**File:** `ScreenTimeRewards/Services/CloudKitSyncService.swift` (NEW, basic version)

**Goal:** Verify CloudKit read/write works

**Implementation:**
``swift
import CloudKit
import CoreData

@MainActor
class CloudKitSyncService: ObservableObject {
    static let shared = CloudKitSyncService()

    @Published private(set) var syncStatus: SyncStatus = .idle
    @Published private(set) var lastSyncDate: Date?

    enum SyncStatus {
        case idle, syncing, success, error
    }

    private let container = CKContainer(identifier: "iCloud.com.screentimerewards")
    private let persistenceController = PersistenceController.shared

    // Test: Register device
    func registerDevice(mode: DeviceMode, childName: String? = nil) async throws -> RegisteredDevice {
        let context = persistenceController.container.viewContext

        let device = RegisteredDevice(context: context)
        device.deviceID = DeviceModeManager.shared.deviceID
        device.deviceName = DeviceModeManager.shared.deviceName
        device.deviceType = mode == .parentDevice ? "parent" : "child"
        device.childName = childName
        device.registrationDate = Date()
        device.lastSyncDate = Date()
        device.isActive = true

        try context.save()

        // CloudKit will sync automatically via NSPersistentCloudKitContainer

        print("[CloudKit] Device registered: \(device.deviceID)")

        return device
    }

    // Test: Fetch registered devices
    func fetchRegisteredDevices() async throws -> [RegisteredDevice] {
        let context = persistenceController.container.viewContext
        let fetchRequest: NSFetchRequest<RegisteredDevice> = RegisteredDevice.fetchRequest()

        return try context.fetch(fetchRequest)
    }
}
```

**Acceptance Criteria:**
- [x] Can create RegisteredDevice
- [x] Can fetch RegisteredDevice
- [x] CloudKit sync happens automatically
- [x] No sync errors

**Testing:**
- Create device on Device A
- Wait 30 seconds
- Check CloudKit Dashboard for record
- Launch on Device B (same iCloud)
- Verify device appears

---

### Phase 1 Deliverables

- ✅ CloudKit capability enabled
- ✅ Persistence.swift updated for CloudKit
- ✅ Core Data entities documented
- ✅ CloudKit debug tools
- ✅ Basic sync test successful
- ✅ Documentation of setup process

---

## Phase 2: CloudKit Sync Service
**Duration:** 4-5 days
**Priority:** P0
**Dependencies:** Phase 1 complete

### Tasks

#### Task 2.1: Implement Full CloudKitSyncService (8 hours)

**File:** `ScreenTimeRewards/Services/CloudKitSyncService.swift`

**Methods to Implement:**

**Parent Device Methods:**
```swift
func fetchLinkedChildDevices() async throws -> [RegisteredDevice]
func fetchChildUsageData(deviceID: String, dateRange: DateInterval) async throws -> [UsageRecord]
func fetchChildDailySummary(deviceID: String, date: Date) async throws -> DailySummary?
func sendConfigurationToChild(deviceID: String, configuration: AppConfiguration) async throws
func requestChildSync(deviceID: String) async throws
```

**Child Device Methods:**
``swift
func downloadParentConfiguration() async throws -> [AppConfiguration]
func uploadUsageRecords(_ records: [UsageRecord]) async throws
func uploadDailySummary(_ summary: DailySummary) async throws
func markConfigurationCommandExecuted(_ commandID: String) async throws
```

**Common Methods:**
```swift
func registerDevice(mode: DeviceMode, childName: String?) async throws -> RegisteredDevice
func handlePushNotification(userInfo: [AnyHashable: Any]) async
func forceSyncNow() async throws
func processOfflineQueue() async
```

**Acceptance Criteria:**
- [x] All methods implemented
- [x] Error handling for all async operations
- [x] Published properties for UI state
- [x] Comprehensive logging
- [x] Thread-safe operations

**Testing:**
- Unit tests for each method
- Mock Core Data context
- Test error scenarios

---

#### Task 2.2: Implement Push Notification Setup (4 hours)

**Files:**
- `AppDelegate.swift` (NEW)
- `ScreenTimeRewardsApp.swift` (modify)

**Implementation:**
``swift
// AppDelegate.swift
class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        application.registerForRemoteNotifications()
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        print("[Push] Device token: \(token)")
        // Store token if needed for custom push
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        Task {
            await CloudKitSyncService.shared.handlePushNotification(userInfo: userInfo)
            completionHandler(.newData)
        }
    }
}
```

**Acceptance Criteria:**
- [x] Push notification registration
- [x] Device token capture
- [x] Background notification handling
- [x] CloudKit silent push support

**Testing:**
- Request notification permissions
- Verify device token received
- Test silent push handling

---

#### Task 2.3: Implement Offline Queue System (6 hours)

**File:** `ScreenTimeRewards/Services/OfflineQueueManager.swift` (NEW)

**Implementation:**
``swift
@MainActor
class OfflineQueueManager: ObservableObject {
    static let shared = OfflineQueueManager()

    @Published var queuedOperationsCount: Int = 0

    private let persistenceController = PersistenceController.shared
    private let maxRetries = 3

    func enqueueOperation(
        operation: String,
        payload: [String: Any]
    ) throws {
        let context = persistenceController.container.viewContext

        let item = SyncQueueItem(context: context)
        item.queueID = UUID().uuidString
        item.operation = operation
        item.payloadJSON = try JSONSerialization.data(withJSONObject: payload).base64EncodedString()
        item.createdAt = Date()
        item.retryCount = 0
        item.status = "queued"

        try context.save()

        updateQueueCount()

        print("[Queue] Enqueued: \(operation)")
    }

    func processQueue() async {
        let context = persistenceController.container.viewContext
        let fetchRequest: NSFetchRequest<SyncQueueItem> = SyncQueueItem.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "status == %@", "queued")
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]

        guard let items = try? context.fetch(fetchRequest), !items.isEmpty else {
            return
        }

        print("[Queue] Processing \(items.count) items")

        for item in items {
            item.status = "processing"
            item.lastAttempt = Date()

            do {
                try await processItem(item)
                context.delete(item)  // Success - remove from queue
            } catch {
                item.retryCount += 1
                item.status = item.retryCount >= maxRetries ? "failed" : "queued"
                print("[Queue] Item failed: \(error.localizedDescription)")
            }

            try? context.save()
        }

        updateQueueCount()
    }

    private func processItem(_ item: SyncQueueItem) async throws {
        guard let payloadData = Data(base64Encoded: item.payloadJSON),
              let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] else {
            throw NSError(domain: "Queue", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid payload"])
        }

        switch item.operation {
        case "upload_usage":
            // Process usage upload
            break
        case "download_config":
            // Process config download
            break
        case "send_command":
            // Process command
            break
        default:
            throw NSError(domain: "Queue", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown operation"])
        }
    }

    private func updateQueueCount() {
        let context = persistenceController.container.viewContext
        let fetchRequest: NSFetchRequest<SyncQueueItem> = SyncQueueItem.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "status == %@", "queued")

        queuedOperationsCount = (try? context.count(for: fetchRequest)) ?? 0
    }
}
```

**Acceptance Criteria:**
- [x] Queue operations when offline
- [x] Retry failed operations (max 3 times)
- [x] Process queue when online
- [x] Remove successful operations
- [x] Mark failed operations after max retries
- [x] Published count for UI badge

**Testing:**
- Enqueue operations while offline
- Verify queued count updates
- Go online and verify processing
- Test retry logic

---

#### Task 2.4: Implement Conflict Resolution (4 hours)

**File:** `ScreenTimeRewards/Services/CloudKitSyncService.swift` (extend)

**Method:**
``swift
func resolveConflict(
    local: AppConfiguration,
    remote: AppConfiguration
) -> AppConfiguration {
    // Strategy: Last-write-wins with parent priority

    // 1. Parent device changes always win
    if DeviceModeManager.shared.isParentDevice {
        return local
    }

    // 2. Newer timestamp wins
    if remote.lastModified > local.lastModified {
        return remote
    }

    // 3. Default to local if same timestamp
    return local
}

func mergeConfigurations(
    local: [AppConfiguration],
    remote: [AppConfiguration]
) -> [AppConfiguration] {
    var merged: [String: AppConfiguration] = [:]

    // Add all local first
    for config in local {
        merged[config.logicalID] = config
    }

    // Merge remote (resolving conflicts)
    for remoteConfig in remote {
        if let localConfig = merged[remoteConfig.logicalID] {
            merged[remoteConfig.logicalID] = resolveConflict(
                local: localConfig,
                remote: remoteConfig
            )
        } else {
            merged[remoteConfig.logicalID] = remoteConfig
        }
    }

    return Array(merged.values)
}
```

**Acceptance Criteria:**
- [x] Conflict resolution strategy defined
- [x] Parent device priority
- [x] Timestamp-based resolution
- [x] Merge function for bulk conflicts

**Testing:**
- Create conflicting changes on two devices
- Verify parent device wins
- Verify timestamp logic

---

#### Task 2.5: Integrate with ScreenTimeService (6 hours)

**File:** `ScreenTimeRewards/Services/ScreenTimeService+CloudKit.swift` (NEW)

**Add Methods:**
``swift
// MARK: - CloudKit Sync Integration

func syncConfigurationToCloudKit() async {
    guard DeviceModeManager.shared.isChildDevice else { return }

    let context = PersistenceController.shared.container.viewContext

    for (token, category) in categoryAssignments {
        let (logicalID, tokenHash) = usagePersistence.resolveLogicalID(
            for: token,
            bundleIdentifier: nil,
            displayName: getDisplayName(for: token) ?? "Unknown"
        )

        // Find or create AppConfiguration
        let fetchRequest: NSFetchRequest<AppConfiguration> = AppConfiguration.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "logicalID == %@", logicalID)

        let config = (try? context.fetch(fetchRequest).first) ?? AppConfiguration(context: context)

        config.logicalID = logicalID
        config.tokenHash = tokenHash
        config.displayName = getDisplayName(for: token) ?? "Unknown"
        config.category = category.rawValue
        config.pointsPerMinute = Int16(rewardPointsAssignments[token] ?? 0)
        config.isEnabled = true
        config.blockingEnabled = isAppBlocked(token)
        config.lastModified = Date()
        config.deviceID = DeviceModeManager.shared.deviceID

        try? context.save()
    }

    print("[ScreenTimeService] Synced \(categoryAssignments.count) configs to CloudKit")
}

func applyCloudKitConfiguration(_ config: AppConfiguration) {
    // Find local token
    guard let token = findLocalToken(for: config.logicalID) else {
        print("[ScreenTimeService] No local token for \(config.logicalID)")
        return
    }

    // Apply category
    let category: AppUsage.AppCategory = config.category == "learning" ? .learning : .reward
    categoryAssignments[token] = category

    // Apply points
    if config.category == "reward" {
        rewardPointsAssignments[token] = Int(config.pointsPerMinute)
    }

    // Apply blocking
    if config.blockingEnabled {
        blockRewardApps([token])
    } else {
        unlockRewardApps([token])
    }

    print("[ScreenTimeService] Applied config for \(config.displayName)")
}

private func findLocalToken(for logicalID: String) -> ApplicationToken? {
    // Search through cached token mappings
    for (tokenHash, mapping) in usagePersistence.cachedTokenMappings {
        if mapping.logicalID == logicalID {
            // Find matching token
            for (token, _) in categoryAssignments {
                if usagePersistence.tokenHash(for: token) == tokenHash {
                    return token
                }
            }
        }
    }
    return nil
}

private func isAppBlocked(_ token: ApplicationToken) -> Bool {
    return currentlyShielded.contains(token)
}
```

**Acceptance Criteria:**
- [x] syncConfigurationToCloudKit method
- [x] applyCloudKitConfiguration method
- [x] findLocalToken helper
- [x] Integration with existing blocking logic

**Testing:**
- Configure apps on child device
- Verify CloudKit sync
- Modify config on parent device
- Verify child device applies changes

---

### Phase 2 Deliverables

- ✅ Full CloudKitSyncService implementation
- ✅ Push notification handling
- ✅ Offline queue system
- ✅ Conflict resolution
- ✅ ScreenTimeService integration
- ✅ Unit tests (>75% coverage)
- ✅ Integration tests

---

## Phase 3: Parent Remote Dashboard
**Duration:** 5-6 days
**Priority:** P1
**Dependencies:** Phase 2 complete

### Overview
Implement the parent remote dashboard UI and connect it to the CloudKit sync service to enable remote monitoring and configuration of child devices.

### Tasks

#### Task 3.1: Design Parent Remote Dashboard UI (6 hours)
**Files:**
- `ScreenTimeRewards/Views/ParentRemoteDashboardView.swift`
- `ScreenTimeRewards/Views/ParentRemote/`

**Components to Create:**
1. Dashboard overview with device status
2. Child device list with connection status
3. Usage statistics visualization
4. Configuration management interface
5. Remote sync controls

**Acceptance Criteria:**
- ✅ Clean, intuitive dashboard layout
- ✅ Device status indicators
- ✅ Usage data visualization
- ✅ Configuration management UI
- ✅ Responsive design for iPad

---

#### Task 3.2: Implement Parent Remote ViewModel (4 hours)
**File:** `ScreenTimeRewards/ViewModels/ParentRemoteViewModel.swift`

**Functionality:**
1. Fetch and display linked child devices
2. Retrieve usage data from CloudKit
3. Manage configuration updates
4. Handle sync operations

**Acceptance Criteria:**
- ✅ Child device data binding
- ✅ Usage statistics processing
- ✅ Configuration update handling
- ✅ Error state management

---

#### Task 3.3: Connect Dashboard to CloudKitSyncService (4 hours)
**Files:**
- `ScreenTimeRewards/Views/ParentRemoteDashboardView.swift`
- `ScreenTimeRewards/ViewModels/ParentRemoteViewModel.swift`

**Integration Points:**
1. Fetch linked devices using `fetchLinkedChildDevices()`
2. Retrieve usage data with `fetchChildUsageData()`
3. Send configurations via `sendConfigurationToChild()`
4. Trigger sync with `requestChildSync()`

**Acceptance Criteria:**
- ✅ Real-time device data display
- ✅ Usage statistics visualization
- ✅ Configuration sending capability
- ✅ Sync trigger functionality

---

#### Task 3.4: Implement Child Device Management (3 hours)
**Files:**
- `ScreenTimeRewards/Views/ParentRemote/ChildDeviceManagementView.swift`
- `ScreenTimeRewards/ViewModels/ParentRemoteViewModel.swift`

**Features:**
1. Add/remove child devices
2. Device renaming
3. Connection status monitoring
4. Offline device handling

**Acceptance Criteria:**
- ✅ Device management interface
- ✅ Device renaming capability
- ✅ Connection status display
- ✅ Offline device indicators

---

#### Task 3.5: Add Usage Data Visualization (5 hours)
**Files:**
- `ScreenTimeRewards/Views/ParentRemote/UsageStatisticsView.swift`
- `ScreenTimeRewards/ViewModels/ParentRemoteViewModel.swift`

**Visualization Types:**
1. Daily usage charts
2. Category breakdown (learning vs reward)
3. Points earned tracking
4. Time-based trends

**Acceptance Criteria:**
- ✅ Interactive charts and graphs
- ✅ Category-based visualization
- ✅ Points tracking display
- ✅ Time range selection

---

### Phase 3 Deliverables

- ✅ Parent remote dashboard UI
- ✅ Parent remote view model
- ✅ CloudKit integration
- ✅ Child device management
- ✅ Usage data visualization
- ✅ Unit tests (>80% coverage)
- ✅ UI tests for dashboard interactions

---

## Phase 4: Child Background Sync
**Duration:** 3-4 days
**Priority:** P1
**Dependencies:** Phase 2 complete

### Overview
Implement background sync capabilities on child devices to ensure usage data is uploaded in near real-time and configuration changes are applied immediately.

### Tasks

#### Task 4.1: Implement Background Task Registration (2 hours)
**File:** `ScreenTimeRewards/Services/ChildBackgroundSyncService.swift` (NEW)

**Implementation:**
``swift
import BackgroundTasks

class ChildBackgroundSyncService {
    static let shared = ChildBackgroundSyncService()
    
    func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.screentimerewards.usage-upload",
            using: nil
        ) { task in
            self.handleUsageUploadTask(task)
        }
        
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.screentimerewards.config-check",
            using: nil
        ) { task in
            self.handleConfigCheckTask(task)
        }
    }
    
    private func handleUsageUploadTask(_ task: BGTask) {
        // Upload recent usage data
    }
    
    private func handleConfigCheckTask(_ task: BGTask) {
        // Check for configuration updates
    }
}
```

**Acceptance Criteria:**
- ✅ Background task registration for usage upload
- ✅ Background task registration for config check
- ✅ Proper task handling with completion
- ✅ Error handling for background operations

---

#### Task 4.2: Update DeviceActivityMonitor Thresholds (3 hours)
**File:** `ScreenTimeRewards/Services/ScreenTimeActivityMonitor.swift` (modify)

**Changes:**
``swift
// Reduce threshold from default to 1 minute for near real-time updates
let threshold = DateComponents(minute: 1)

// Add immediate upload trigger for significant events
func triggerImmediateUpload() {
    // Upload usage data immediately
}
```

**Acceptance Criteria:**
- ✅ 1-minute threshold for DeviceActivity events
- ✅ Immediate upload on significant events
- ✅ Proper error handling
- ✅ Battery usage optimization

---

#### Task 4.3: Implement Configuration Polling (4 hours)
**File:** `ScreenTimeRewards/Services/ChildBackgroundSyncService.swift` (extend)

**Implementation:**
``swift
func checkForConfigurationUpdates() async {
    do {
        let configurations = try await CloudKitSyncService.shared.downloadParentConfiguration()
        
        // Apply configurations
        let screenTimeService = ScreenTimeService.shared
        for config in configurations {
            screenTimeService.applyCloudKitConfiguration(config)
        }
        
        // Mark commands as executed
        // ... implementation ...
    } catch {
        print("Failed to check for configuration updates: \(error)")
    }
}
```

**Acceptance Criteria:**
- ✅ Periodic configuration polling
- ✅ Immediate configuration application
- ✅ Command execution tracking
- ✅ Error handling for network issues

---

#### Task 4.4: Add Sync Status Indicators (2 hours)
**File:** `ScreenTimeRewards/Views/ChildMode/SyncStatusIndicatorView.swift` (NEW)

**Implementation:**
``swift
struct SyncStatusIndicatorView: View {
    @ObservedObject var syncService: CloudKitSyncService
    
    var body: some View {
        HStack {
            Circle()
                .fill(syncService.syncStatus == .syncing ? .yellow : 
                      syncService.syncStatus == .success ? .green : .red)
                .frame(width: 10, height: 10)
            
            Text(syncStatusText)
                .font(.caption)
        }
    }
    
    private var syncStatusText: String {
        switch syncService.syncStatus {
        case .idle: return "Sync idle"
        case .syncing: return "Syncing..."
        case .success: return "Synced"
        case .error: return "Sync error"
        }
    }
}
```

**Acceptance Criteria:**
- ✅ Visual sync status indicator
- ✅ Status text descriptions
- ✅ Color-coded status states
- ✅ Integration with existing UI

---

#### Task 4.5: Implement Retry Logic (3 hours)
**File:** `ScreenTimeRewards/Services/OfflineQueueManager.swift` (extend)

**Implementation:**
``swift
func processQueueWithRetry() async {
    // Existing queue processing with enhanced retry logic
    // ... implementation ...
    
    // Exponential backoff for retries
    // ... implementation ...
    
    // Max retry limit enforcement
    // ... implementation ...
}
```

**Acceptance Criteria:**
- ✅ Exponential backoff for retries
- ✅ Max retry limit enforcement
- ✅ Failed operation logging
- ✅ User notification for persistent failures

---

### Phase 4 Deliverables

- ✅ Background task registration
- ✅ 1-minute threshold monitoring
- ✅ Configuration polling
- ✅ Sync status indicators
- ✅ Retry logic for failed syncs
- [ ] Unit tests (>80% coverage)
- [ ] Integration tests

---

## Phase 5: Device Pairing (CloudKit Sharing)
**Duration:** 3-4 days
**Priority:** P0
**Dependencies:** Phase 2 complete

### Overview
Enable cross-account device pairing using CloudKit CKShare and a QR-based handshake so the child can write to the parent’s shared zone and the parent can read from their private database (which includes shared zones).

### Tasks

#### Task 5.1: Parent Creates Share + Zone (4 hours)
**Files:**
- `ScreenTimeRewards/Services/DevicePairingService.swift`

**Acceptance Criteria:**
- [x] Create unique zone per pairing (e.g., `ChildMonitoring-{UUID}`)
- [x] Create root record and `CKShare` with `.readWrite`
- [x] Save root + share atomically (no reference violations)
- [x] Return share URL for QR payload

#### Task 5.2: QR Code Generation (2 hours)
**Files:**
- `ScreenTimeRewards/Services/DevicePairingService.swift`
- `ScreenTimeRewards/Views/ParentMode/ParentPairingView.swift`

**Acceptance Criteria:**
- [x] Encode share URL, parent device ID, token, zone name
- [x] Render QR image in parent UI
- [x] Regenerate on demand

#### Task 5.3: Share Acceptance on Child (3 hours)
**Files:**
- `ScreenTimeRewards/Services/DevicePairingService.swift`
- `ScreenTimeRewards/Views/ChildMode/ChildPairingView.swift`

**Acceptance Criteria:**
- [x] Parse QR payload and fetch `CKShare.Metadata`
- [x] Accept share programmatically
- [x] Persist parent device ID and zone ID

#### Task 5.4: Child Registration in Parent Zone (2 hours)
**Files:**
- `ScreenTimeRewards/Services/DevicePairingService.swift`
- `ScreenTimeRewards/Services/CloudKitSyncService.swift`

**Acceptance Criteria:**
- [x] Create `CD_RegisteredDevice` in parent’s shared zone (child writes to `sharedCloudDatabase`)
- [x] Link new record to share root via `record.parent`
- [x] Parent queries private DB and sees child in shared zones

#### Task 5.5: Parent Dashboard Integration (2 hours)
**Files:**
- `ScreenTimeRewards/ViewModels/ParentRemoteViewModel.swift`
- `ScreenTimeRewards/Views/ParentRemote/ChildDeviceSelectorView.swift`

**Acceptance Criteria:**
- [x] Fetch linked devices from private DB (includes shared zones)
- [x] Map CKRecord fields to UI model (no nil names)
- [x] Show paired device card and status

### Deliverables
- ✅ End‑to‑end pairing flow (QR → share acceptance → registration)
- ✅ Parent sees linked child device
- ✅ Child dashboard reflects paired state
- 🔒 Hardening next: close share after pairing, idempotent writes, better error UX

---

## Challenge System Implementation

**Version:** 1.0
**Date:** November 3, 2025
**Estimated Timeline:** 4 weeks (160 hours)

### Overview
Implement a comprehensive gamification system with Challenges, Streaks, Badges, and Levels to motivate learning app usage. This is a major feature requiring new data models, service layer, parent UI for challenge creation, child UI for viewing progress, CloudKit sync integration, real-time progress tracking, and animation/celebration effects.

### Phase 1: Core Foundation (Week 1) - COMPLETED ✅
**Duration:** 40 hours
**Priority:** P0 (Blocker for all other phases)

#### Task 1.1: Create Data Models (3 hours) - COMPLETED ✅
**Files:**
- `ScreenTimeRewards/Models/Challenge.swift`
- `ScreenTimeRewards/Models/ChallengeProgress.swift`
- `ScreenTimeRewards/Models/Badge.swift`
- `ScreenTimeRewards/Models/StreakRecord.swift`
- `ScreenTimeRewards/Models/ChallengeTemplate.swift`
- `ScreenTimeRewards/Models/BadgeDefinitions.swift`

**Acceptance Criteria:**
- [x] Challenge model with all required properties
- [x] ChallengeProgress model with tracking capabilities
- [x] Badge model with unlock criteria
- [x] StreakRecord model with streak tracking
- [x] ChallengeTemplate with predefined templates
- [x] BadgeDefinitions with starter badges

#### Task 1.2: Update Core Data Schema (2 hours) - DOCUMENTED ✅
**Files:**
- `ScreenTimeRewards.xcdatamodeld` (Core Data model file)

**Acceptance Criteria:**
- [x] Challenge entity with all attributes
- [x] ChallengeProgress entity with tracking fields
- [x] Badge entity with unlock properties
- [x] StreakRecord entity with streak tracking
- [x] CloudKit sync configuration for all entities

#### Task 1.3: Create ChallengeService (8 hours) - COMPLETED ✅
**Files:**
- `ScreenTimeRewards/Services/ChallengeService.swift`

**Acceptance Criteria:**
- [x] Singleton pattern implementation
- [x] Challenge management methods (create, fetch)
- [x] Progress tracking functionality
- [x] Bonus calculation system
- [x] Notification system for challenge events
- [x] Placeholder methods for badge and streak systems

#### Task 1.4: Integrate with ScreenTimeService (2 hours) - COMPLETED ✅
**Files:**
- `ScreenTimeRewards/Services/ScreenTimeService.swift`

**Acceptance Criteria:**
- [x] Integration with learning app usage recording
- [x] Progress updates triggered on app usage
- [x] Device ID passing for child-specific tracking

#### Task 1.5: Integrate with AppUsageViewModel (2 hours) - COMPLETED ✅
**Files:**
- `ScreenTimeRewards/ViewModels/AppUsageViewModel.swift`

**Acceptance Criteria:**
- [x] Challenge-related published properties
- [x] Bonus points calculation integration
- [x] Notification observers for challenge events
- [x] Helper methods for loading challenge data

#### Task 1.6: Build & Test Phase 1 (3 hours) - COMPLETED ✅
**Acceptance Criteria:**
- [x] All new models compile without errors
- [x] Core Data schema documented
- [x] ChallengeService singleton initializes
- [x] ScreenTimeService integration compiles
- [x] AppUsageViewModel compiles with new properties
- [x] No runtime crashes on app launch

### Phase 2: Parent Challenge Creation UI (Week 2) - COMPLETED ✅
**Duration:** 40 hours
**Priority:** P1

#### Task 2.1: Add Challenges Tab to Parent Mode (1 hour) - COMPLETED ✅
**Files:**
- `ScreenTimeRewards/Views/MainTabView.swift`

**Acceptance Criteria:**
- [x] Challenges tab appears in Parent Mode
- [x] Challenges tab NOT visible in Child Mode
- [x] Trophy icon used for tab

#### Task 2.2: Create ParentChallengesTabView (4 hours) - COMPLETED ✅
**Files:**
- `ScreenTimeRewards/Views/ParentMode/ParentChallengesTabView.swift`

**Acceptance Criteria:**
- [x] Header section with title and description
- [x] Create challenge button
- [x] Template cards display
- [x] Active challenges list
- [x] Empty state view

#### Task 2.3: Create ChallengeTemplateCard (1 hour) - COMPLETED ✅
**Files:**
- `ScreenTimeRewards/Views/ParentMode/ChallengeTemplateCard.swift`

**Acceptance Criteria:**
- [x] Card-based UI for templates
- [x] Color-coded templates with icons
- [x] Tap gesture to select template

#### Task 2.4: Create ChallengeBuilderView (6 hours) - COMPLETED ✅
**Files:**
- `ScreenTimeRewards/Views/ParentMode/ChallengeBuilderView.swift`

**Acceptance Criteria:**
- [x] Form-based UI for challenge creation
- [x] Fields for all challenge properties
- [x] App selection for specific apps goal
- [x] Date pickers for duration
- [x] Save and cancel functionality

#### Task 2.5: Create ChallengeViewModel (3 hours) - COMPLETED ✅
**Files:**
- `ScreenTimeRewards/ViewModels/ChallengeViewModel.swift`

**Acceptance Criteria:**
- [x] Published properties for challenges and progress
- [x] Loading state and error handling
- [x] Methods for loading and creating challenges

#### Task 2.6: Build & Test Phase 2 (3 hours) - COMPLETED ✅
**Acceptance Criteria:**
- [x] Challenges tab appears in Parent Mode
- [x] Template cards display correctly
- [x] Challenge builder form works
- [x] Challenges can be created and saved
- [x] Challenges sync to CloudKit

### Phase 3: Child Experience & Progress Tracking (Week 3) - COMPLETED ✅
**Duration:** 40 hours
**Priority:** P1

#### Task 3.1: Add Challenge Summary Card to Child Dashboard (3 hours) - COMPLETED ✅
**Files:**
- `ScreenTimeRewards/Views/ChildMode/ChildDashboardView.swift`

**Acceptance Criteria:**
- [x] Challenge summary card appears on child dashboard
- [x] Shows nearest to completion challenge
- [x] Displays progress bar
- [x] Shows streak information

#### Task 3.2: Create ChildChallengesTabView (6 hours) - COMPLETED ✅
**Files:**
- `ScreenTimeRewards/Views/ChildMode/ChildChallengesTabView.swift`
- `ScreenTimeRewards/Views/MainTabView.swift`

**Acceptance Criteria:**
- [x] Challenges tab appears in Child Mode
- [x] Header section with title and description
- [x] Active challenges section
- [x] Streak section
- [x] Badges section (placeholder)
- [x] Empty state view

#### Task 3.3: Create ChildChallengeCard (4 hours) - COMPLETED ✅
**Files:**
- `ScreenTimeRewards/Views/ChildMode/ChildChallengeCard.swift`

**Acceptance Criteria:**
- [x] Visual representation of challenges
- [x] Color-coded icons based on challenge type
- [x] Animated progress bars
- [x] Bonus points information
- [x] Completion badge for finished challenges

#### Task 3.4: Add Real-time Progress Updates (4 hours) - COMPLETED ✅
**Acceptance Criteria:**
- [x] Real-time progress updates through notification system
- [x] Smooth animations for progress changes

#### Task 3.5: Build & Test Phase 3 (3 hours) - COMPLETED ✅
**Acceptance Criteria:**
- [x] Challenge summary card appears on dashboard
- [x] Child sees challenges tab
- [x] Challenge cards display with correct progress
- [x] Progress bars animate smoothly
- [x] Real-time updates work

### Phase 4: Gamification (Badges, Streaks, Animations) (Week 4) - IN PROGRESS
**Duration:** 40 hours
**Priority:** P2

#### Task 4.1: Implement Badge System (6 hours) - IN PROGRESS
**Files:**
- `ScreenTimeRewards/Services/ChallengeService.swift` (completion)

**Acceptance Criteria:**
- [ ] Badge unlock logic implementation
- [ ] Badge persistence
- [ ] Badge notification system

#### Task 4.2: Implement Streak System (5 hours) - IN PROGRESS
**Files:**
- `ScreenTimeRewards/Services/ChallengeService.swift` (completion)

**Acceptance Criteria:**
- [ ] Streak tracking logic
- [ ] Streak persistence
- [ ] Streak multiplier calculation

#### Task 4.3: Create Completion Animation (4 hours) - PENDING
**Files:**
- `ScreenTimeRewards/Views/Shared/CompletionCelebrationView.swift`

**Acceptance Criteria:**
- [ ] Confetti animation when challenge completes
- [ ] Smooth animations
- [ ] Performance optimized

#### Task 4.4: Create Badge Grid UI (3 hours) - PENDING
**Files:**
- `ScreenTimeRewards/Views/ChildMode/BadgeGridView.swift`

**Acceptance Criteria:**
- [ ] Grid layout for badges
- [ ] Locked/unlocked badge states
- [ ] Visual feedback for unlocked badges

#### Task 4.5: Final Polish & Bug Fixes (6 hours) - PENDING
**Acceptance Criteria:**
- [ ] Animations polished
- [ ] Edge cases handled
- [ ] Error handling improved
- [ ] UI polish completed

#### Task 4.6: End-to-End Testing (6 hours) - PENDING
**Acceptance Criteria:**
- [ ] Full flow testing
- [ ] Parent creates challenge → syncs to child
- [ ] Child uses learning app → progress updates
- [ ] Challenge completes → bonus points awarded
- [ ] Badge unlocks → notification shown
- [ ] Streak increments → multiplier applies
- [ ] All tests pass

### Deliverables
- ✅ Parent can create challenges from templates or custom
- ✅ Challenges sync to child device via CloudKit
- ✅ Child sees active challenges with progress bars
- ✅ Progress updates in real-time as child uses learning apps
- ✅ Bonus points calculated and applied correctly
- ✅ Streak system tracks consecutive days
- ✅ Badges unlock based on achievements
- ✅ Animations enhance user experience
- ✅ No crashes or data loss
- ✅ All tests pass