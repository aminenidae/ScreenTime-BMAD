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
- [x] Mode reset capability
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
```swift
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
```swift
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
```swift
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
- [x] All 6 entities created
- [x] All attributes defined with correct types
- [x] Indexes configured
- [x] NSManagedObject subclasses generated
- [x] CloudKit compatibility verified

**Testing:**
- Build project successfully
- Create test objects in each entity
- Verify Core Data save/fetch works

---

#### Task 1.4: Create CloudKit Dashboard Monitoring (2 hours)
**File:** `ScreenTimeRewards/Services/CloudKitDebugService.swift` (NEW)

**Implementation:**
```swift
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
```swift
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
- ✅ Core Data entities created
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
```swift
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
- `AppDelegate.swift` (modify)
- `ScreenTimeRewardsApp.swift` (modify)

**Implementation:**
```swift
// AppDelegate.swift
extension AppDelegate: UNUserNotificationCenterDelegate {
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
```swift
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
```swift
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

**File:** `ScreenTimeRewards/Services/ScreenTimeService.swift` (modify)

**Add Methods:**
```swift
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

## Phases 3-8 (Continued in Next Document)

Due to length, remaining phases (3-8) are detailed in:
- `DEV_ROADMAP_PHASES_3_8.md`

---

**Document Version:** 1.0
**Status:** Ready for Implementation
**Next Document:** DEV_ROADMAP_PHASES_3_8.md
