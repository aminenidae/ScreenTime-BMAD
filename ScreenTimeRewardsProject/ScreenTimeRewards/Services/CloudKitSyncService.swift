import CloudKit
import CoreData
import Combine
import UIKit

@MainActor
class CloudKitSyncService: ObservableObject {
    static let shared = CloudKitSyncService()

    @Published private(set) var syncStatus: SyncStatus = .idle
    @Published private(set) var lastSyncDate: Date?

    enum SyncStatus {
        case idle, syncing, success, error
    }

    enum CloudKitSyncError: LocalizedError {
        case zoneNotFound(deviceID: String)
        case commandEncodingFailed
        case recordNotFound

        var errorDescription: String? {
            switch self {
            case .zoneNotFound(let deviceID):
                return String(localized: "Could not find shared zone for device: \(deviceID)")
            case .commandEncodingFailed:
                return String(localized: "Failed to encode command payload")
            case .recordNotFound:
                return String(localized: "Record not found in CloudKit")
            }
        }
    }

    private let container = CKContainer(identifier: "iCloud.com.screentimerewards")
    private let persistenceController = PersistenceController.shared
    private let offlineQueue = OfflineQueueManager.shared

    /// Session-scoped cache of (zoneName, recordType) pairs that returned
    /// `Did not find record type` once already. The fallback all-zones path for
    /// `CD_ShieldState` (and any other record type) would otherwise re-hit every
    /// zone on every fetch, trigger CK rate-limit ("Error rate mitigation activated"),
    /// and poison the rest of the session's latency.
    ///
    /// Cleared naturally at process exit; no disk persistence (schema could be added
    /// later in the process lifetime).
    private static let schemaMissLock = NSLock()
    private static var schemaMissSet = Set<String>()

    private static func schemaKey(zone: String, recordType: String) -> String {
        "\(zone):\(recordType)"
    }

    static func shouldSkipZone(_ zone: String, recordType: String) -> Bool {
        schemaMissLock.lock()
        defer { schemaMissLock.unlock() }
        return schemaMissSet.contains(schemaKey(zone: zone, recordType: recordType))
    }

    static func recordSchemaMiss(zone: String, recordType: String) {
        schemaMissLock.lock()
        defer { schemaMissLock.unlock() }
        schemaMissSet.insert(schemaKey(zone: zone, recordType: recordType))
    }

    // MARK: - Parent Zone Info Helper

    /// Holds zone info needed for syncing to parent's shared zone
    struct ParentZoneInfo {
        let zoneName: String
        let zoneOwner: String
        let rootRecordName: String
    }

    /// Gets zone info from multi-parent storage (new format)
    /// Falls back to legacy single-parent keys for backward compatibility
    private func getParentZoneInfo() -> ParentZoneInfo? {
        // Try new multi-parent format first
        let pairedParents = DevicePairingService.shared.getPairedParents()
        if let firstParent = pairedParents.first,
           let zoneName = firstParent.sharedZoneID,
           let zoneOwner = firstParent.sharedZoneOwner,
           let rootName = firstParent.rootRecordName {
            return ParentZoneInfo(zoneName: zoneName, zoneOwner: zoneOwner, rootRecordName: rootName)
        }

        // Fallback to legacy single-parent keys
        if let zoneName = UserDefaults.standard.string(forKey: "parentSharedZoneID"),
           let zoneOwner = UserDefaults.standard.string(forKey: "parentSharedZoneOwner"),
           let rootName = UserDefaults.standard.string(forKey: "parentSharedRootRecordName") {
            return ParentZoneInfo(zoneName: zoneName, zoneOwner: zoneOwner, rootRecordName: rootName)
        }

        return nil
    }

    // MARK: - Device Registration
    // Test: Register device
    func registerDevice(mode: DeviceMode, childName: String? = nil, parentDeviceID: String? = nil) async throws -> RegisteredDevice {
        let context = persistenceController.container.viewContext

        let device = RegisteredDevice(context: context)
        device.deviceID = DeviceModeManager.shared.deviceID
        device.deviceName = DeviceModeManager.shared.deviceName
        device.deviceType = mode == .parentDevice ? "parent" : "child"
        device.childName = childName
        device.parentDeviceID = parentDeviceID
        device.registrationDate = Date()
        device.lastSyncDate = Date()
        device.isActive = true

        #if DEBUG
        print("[CloudKit] ===== Registering Device =====")
        print("[CloudKit] Device ID: \(device.deviceID ?? "nil")")
        print("[CloudKit] Device Name: \(device.deviceName ?? "nil")")
        print("[CloudKit] Device Type: \(device.deviceType ?? "nil")")
        print("[CloudKit] Child Name: \(device.childName ?? "nil")")
        print("[CloudKit] Parent Device ID: \(device.parentDeviceID ?? "nil")")
        #endif

        try context.save()

        #if DEBUG
        print("[CloudKit] ✅ Device saved to Core Data")
        print("[CloudKit] Waiting for NSPersistentCloudKitContainer to sync to CloudKit...")
        print("[CloudKit] Check CloudKit Dashboard in 30-60 seconds for CD_RegisteredDevice record")
        #endif

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

    // MARK: - Zone Management

    /// Find existing ChildMonitoring zones for a specific child device
    /// Returns zones that contain records for this deviceID
    func findExistingZonesForChild(deviceID: String) async throws -> [(zone: CKRecordZone, hasRecords: Bool)] {
        let database = container.privateCloudDatabase
        let allZones = try await database.allRecordZones()

        var matchingZones: [(zone: CKRecordZone, hasRecords: Bool)] = []

        for zone in allZones where zone.zoneID.zoneName.hasPrefix("ChildMonitoring-") {
            // Check if this zone has records for the specified deviceID
            let predicate = NSPredicate(format: "CD_deviceID == %@", deviceID)
            let query = CKQuery(recordType: "CD_RegisteredDevice", predicate: predicate)

            do {
                let (matches, _) = try await database.records(matching: query, inZoneWith: zone.zoneID, resultsLimit: 1)
                let hasRecords = !matches.isEmpty
                matchingZones.append((zone: zone, hasRecords: hasRecords))

                #if DEBUG
                print("[CloudKitSyncService] Zone \(zone.zoneID.zoneName): hasRecords=\(hasRecords) for device \(deviceID)")
                #endif
            } catch {
                #if DEBUG
                print("[CloudKitSyncService] Error checking zone \(zone.zoneID.zoneName): \(error.localizedDescription)")
                #endif
            }
        }

        return matchingZones
    }

    /// Delete all records in a zone and optionally delete the zone itself
    func cleanupZone(_ zoneID: CKRecordZone.ID, deleteZone: Bool = true) async throws {
        let database = container.privateCloudDatabase

        #if DEBUG
        print("[CloudKitSyncService] Cleaning up zone: \(zoneID.zoneName)")
        #endif

        // First, delete all records in the zone
        let recordTypes = ["CD_RegisteredDevice", "CD_AppConfiguration", "CD_UsageRecord", "MonitoringSession"]

        for recordType in recordTypes {
            do {
                let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
                let (matches, _) = try await database.records(matching: query, inZoneWith: zoneID, resultsLimit: 200)

                let recordIDsToDelete = matches.compactMap { (recordID, result) -> CKRecord.ID? in
                    if case .success(_) = result { return recordID }
                    return nil
                }

                if !recordIDsToDelete.isEmpty {
                    let (_, deleteResults) = try await database.modifyRecords(saving: [], deleting: recordIDsToDelete)
                    #if DEBUG
                    print("[CloudKitSyncService] Deleted \(recordIDsToDelete.count) \(recordType) records")
                    #endif
                }
            } catch {
                #if DEBUG
                print("[CloudKitSyncService] Error deleting \(recordType) records: \(error.localizedDescription)")
                #endif
            }
        }

        // Delete the zone itself if requested
        if deleteZone {
            do {
                try await database.deleteRecordZone(withID: zoneID)
                #if DEBUG
                print("[CloudKitSyncService] ✅ Zone deleted: \(zoneID.zoneName)")
                #endif
            } catch {
                #if DEBUG
                print("[CloudKitSyncService] Error deleting zone: \(error.localizedDescription)")
                #endif
                throw error
            }
        }
    }

    /// Get all ChildMonitoring zones (for diagnostic/cleanup purposes)
    func getAllChildMonitoringZones() async throws -> [CKRecordZone] {
        let database = container.privateCloudDatabase
        let allZones = try await database.allRecordZones()
        return allZones.filter { $0.zoneID.zoneName.hasPrefix("ChildMonitoring-") }
    }

    /// Check if a specific zone exists and is accessible
    /// Used to validate if a child's pairing is still valid
    /// Compares by zoneName only: within a single user's private database, zone
    /// names are unique. Owner-name equality fails when the saved owner is the
    /// `__defaultOwner__` sentinel but `allRecordZones()` returns the resolved
    /// account record name (or vice versa) — that mismatch caused valid
    /// children to be flagged "Device Disconnected".
    func zoneExists(_ zoneID: CKRecordZone.ID) async -> Bool {
        do {
            let zones = try await container.privateCloudDatabase.allRecordZones()
            return zones.contains { $0.zoneID.zoneName == zoneID.zoneName }
        } catch {
            #if DEBUG
            print("[CloudKitSyncService] Error checking zone existence: \(error)")
            #endif
            return false
        }
    }

    /// Validate if a child's zone still exists (by zone name and owner)
    /// Returns true if zone exists, false if it's been deleted/is inaccessible
    func validateChildZone(zoneName: String, ownerName: String) async -> Bool {
        let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: ownerName)
        return await zoneExists(zoneID)
    }

    /// Delete orphaned zones that have no active child devices
    func cleanupOrphanedZones() async throws -> Int {
        let database = container.privateCloudDatabase
        let allZones = try await database.allRecordZones()
        var deletedCount = 0

        for zone in allZones where zone.zoneID.zoneName.hasPrefix("ChildMonitoring-") {
            // Check if this zone has any registered devices
            let predicate = NSPredicate(value: true)
            let query = CKQuery(recordType: "CD_RegisteredDevice", predicate: predicate)

            do {
                let (matches, _) = try await database.records(matching: query, inZoneWith: zone.zoneID, resultsLimit: 1)

                if matches.isEmpty {
                    // No devices in this zone - it's orphaned
                    #if DEBUG
                    print("[CloudKitSyncService] Found orphaned zone (no devices): \(zone.zoneID.zoneName)")
                    #endif

                    try await cleanupZone(zone.zoneID, deleteZone: true)
                    deletedCount += 1
                }
            } catch {
                #if DEBUG
                print("[CloudKitSyncService] Error checking zone \(zone.zoneID.zoneName): \(error.localizedDescription)")
                #endif
            }
        }

        #if DEBUG
        print("[CloudKitSyncService] Cleaned up \(deletedCount) orphaned zones")
        #endif

        return deletedCount
    }

    /// Delete ALL ChildMonitoring-* zones (use when creating fresh pairing)
    /// This is more aggressive than cleanupOrphanedZones - it deletes zones even with records
    func deleteAllChildMonitoringZones() async throws -> Int {
        let database = container.privateCloudDatabase
        let allZones = try await database.allRecordZones()
        var deletedCount = 0

        #if DEBUG
        print("[CloudKitSyncService] ===== Deleting ALL ChildMonitoring Zones =====")
        #endif

        for zone in allZones where zone.zoneID.zoneName.hasPrefix("ChildMonitoring-") {
            do {
                try await cleanupZone(zone.zoneID, deleteZone: true)
                deletedCount += 1
                #if DEBUG
                print("[CloudKitSyncService] ✅ Deleted zone: \(zone.zoneID.zoneName)")
                #endif
            } catch {
                #if DEBUG
                print("[CloudKitSyncService] ⚠️ Failed to delete zone \(zone.zoneID.zoneName): \(error.localizedDescription)")
                #endif
                // Continue with other zones even if one fails
            }
        }

        #if DEBUG
        print("[CloudKitSyncService] Deleted \(deletedCount) ChildMonitoring zone(s)")
        #endif

        return deletedCount
    }

    /// Unpair a child device from parent - deletes zone and all records
    /// Called from parent device to remove a child
    func unpairChildDevice(_ childDevice: RegisteredDevice) async throws {
        #if DEBUG
        print("[CloudKitSyncService] ===== Unpairing Child Device =====")
        print("[CloudKitSyncService] Child Device ID: \(childDevice.deviceID ?? "unknown")")
        print("[CloudKitSyncService] Zone: \(childDevice.sharedZoneID ?? "unknown")")
        #endif

        // 1. If we have zone info, delete that specific zone
        if let zoneName = childDevice.sharedZoneID,
           let zoneOwner = childDevice.sharedZoneOwner {
            let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: zoneOwner)

            #if DEBUG
            print("[CloudKitSyncService] Deleting zone: \(zoneName)")
            #endif

            try await cleanupZone(zoneID, deleteZone: true)

            #if DEBUG
            print("[CloudKitSyncService] ✅ Zone deleted successfully")
            #endif
        } else if let deviceID = childDevice.deviceID {
            // Fallback: Find zones containing this device and clean them up
            #if DEBUG
            print("[CloudKitSyncService] No zone info, searching for zones with device \(deviceID)")
            #endif

            let matchingZones = try await findExistingZonesForChild(deviceID: deviceID)
            for (zone, hasRecords) in matchingZones where hasRecords {
                try await cleanupZone(zone.zoneID, deleteZone: true)
                #if DEBUG
                print("[CloudKitSyncService] ✅ Cleaned up zone: \(zone.zoneID.zoneName)")
                #endif
            }
        }

        // 2. Decrement Firebase's child count so the slot is freed up.
        // Without this, Firebase's pairing limit check still counts the
        // unpaired child and rejects the next pair attempt with
        // "Device limit reached" — even though CloudKit shows the seat is open.
        if let childDeviceID = childDevice.deviceID {
            do {
                try await FirebaseValidationService.shared.removeChildFromFamily(
                    childDeviceId: childDeviceID,
                    familyId: FirebaseValidationService.shared.currentFamilyId
                )
            } catch {
                #if DEBUG
                print("[CloudKitSyncService] ⚠️ Firebase child removal failed (non-critical): \(error.localizedDescription)")
                #endif
                // Non-critical for the local unpair flow; CloudKit cleanup is
                // already done. The orphan Firebase entry can be reaped by a
                // future call (function is idempotent).
            }
        }

        #if DEBUG
        print("[CloudKitSyncService] ✅ Child device unpaired successfully")
        #endif
    }

    // MARK: - Parent Device Methods

    // MARK: - Known Child Zones Cache
    //
    // `fetchLinkedChildDevices` enumerates ChildMonitoring-* zones in the parent's
    // private DB. Over a device's lifetime that DB accumulates many orphan zones
    // (old test pairings, unpaired children, replaced devices). Scanning all of
    // them serially is the dominant cause of slow parent-dashboard load.
    //
    // The "restrict to known zones" optimization filters the enumeration down to
    // zones we have already proven contain *our* paired child. The set is
    // persisted in the app-group UserDefaults so it survives process restarts
    // and is shared across every entry point that triggers a fetch (subscription
    // manager, screen-time service, parent view model). Source of truth is the
    // last successful `fetchLinkedChildDevices` result; Core Data is only
    // consulted as a fallback because NSPersistentCloudKitContainer's mirror
    // doesn't carry our `sharedZoneID` field.

    private static let knownChildZonesUDKeyPrefix = "parent_known_child_zones_v1_"
    private static let orphanCleanupDoneKeyPrefix = "parent_orphan_zone_cleanup_v1_done_"
    private static let childZoneMappingUDKeyPrefix = "parent_child_zone_mapping_v1_"

    private func knownZonesUDKey(parentDeviceID: String) -> String {
        Self.knownChildZonesUDKeyPrefix + parentDeviceID
    }

    private func orphanCleanupUDKey(parentDeviceID: String) -> String {
        Self.orphanCleanupDoneKeyPrefix + parentDeviceID
    }

    private func childZoneMappingUDKey(parentDeviceID: String) -> String {
        Self.childZoneMappingUDKeyPrefix + parentDeviceID
    }

    /// Returns the cached (zoneName, zoneOwner) pair for a paired child device.
    /// Used by `populateFromLocalCache` on launch to enrich Core Data rows that
    /// don't carry the zone info — without it, every per-child data fetch
    /// (usage, configs, shields, history, snapshot, streaks) falls back to
    /// scanning every zone in the parent's private DB, multiplying the launch
    /// cost by ~6× per child.
    static func cachedZoneInfo(forDeviceID deviceID: String, parentDeviceID: String) -> (zoneName: String, zoneOwner: String)? {
        guard !deviceID.isEmpty, !parentDeviceID.isEmpty,
              let defaults = UserDefaults(suiteName: "group.com.screentimerewards.shared"),
              let map = defaults.dictionary(forKey: Self.childZoneMappingUDKeyPrefix + parentDeviceID) as? [String: [String]],
              let pair = map[deviceID], pair.count == 2 else {
            return nil
        }
        return (pair[0], pair[1])
    }

    private func saveChildZoneMapping(_ devices: [RegisteredDevice], parentDeviceID: String) {
        guard !parentDeviceID.isEmpty,
              let defaults = UserDefaults(suiteName: "group.com.screentimerewards.shared") else { return }
        var map: [String: [String]] = [:]
        for d in devices {
            guard let id = d.deviceID, let zone = d.sharedZoneID, let owner = d.sharedZoneOwner else { continue }
            map[id] = [zone, owner]
        }
        defaults.set(map, forKey: childZoneMappingUDKey(parentDeviceID: parentDeviceID))
    }

    /// Returns the set of ChildMonitoring zone names already known for this parent.
    /// Reads from app-group UserDefaults first (populated after every successful
    /// fetch), then falls back to Core Data (where `sharedZoneID` may be nil for
    /// rows materialized solely by NSPersistentCloudKitContainer). Returns an
    /// empty set when nothing has ever been cached — callers treat that as
    /// "fall back to full scan".
    private func knownChildZoneNames(parentDeviceID: String) -> Set<String> {
        guard !parentDeviceID.isEmpty else { return Set<String>() }

        if let defaults = UserDefaults(suiteName: "group.com.screentimerewards.shared"),
           let cached = defaults.array(forKey: knownZonesUDKey(parentDeviceID: parentDeviceID)) as? [String],
           !cached.isEmpty {
            return Set(cached)
        }

        let context = PersistenceController.shared.container.viewContext
        let req: NSFetchRequest<RegisteredDevice> = RegisteredDevice.fetchRequest()
        req.predicate = NSPredicate(format: "deviceType == %@ AND parentDeviceID == %@", "child", parentDeviceID)
        do {
            let rows = try context.fetch(req)
            return Set(rows.compactMap { $0.sharedZoneID })
        } catch {
            #if DEBUG
            print("[CloudKitSyncService] ⚠️ knownChildZoneNames Core Data fallback failed: \(error.localizedDescription)")
            #endif
            return Set<String>()
        }
    }

    /// Persist the canonical set of known zones after a successful fetch.
    /// Writes to app-group UserDefaults so every entry point (and the next
    /// launch's cold-start callers) sees the same set immediately.
    private func saveKnownChildZoneNames(_ zoneNames: Set<String>, parentDeviceID: String) {
        guard !parentDeviceID.isEmpty,
              let defaults = UserDefaults(suiteName: "group.com.screentimerewards.shared") else { return }
        defaults.set(Array(zoneNames), forKey: knownZonesUDKey(parentDeviceID: parentDeviceID))
    }

    /// Coalesces concurrent `fetchLinkedChildDevices` callers (with
    /// `restrictToKnownZones: true`, the default) onto a single in-flight
    /// fetch. Different code paths (SubscriptionManager checking the seat
    /// count, ScreenTimeService syncing web restrictions, ParentRemoteViewModel
    /// loading the dashboard) routinely fire within milliseconds of each
    /// other on launch. Without this coalescing each kicks off its own 20+
    /// -zone enumeration and the log shows two passes interleaved.
    private var inFlightFetchLinkedChildDevicesTask: Task<[RegisteredDevice], Error>?

    /// Timestamp of the last successful restricted-zone fetch. Used by the
    /// freshness short-circuit below — repeat callers within the freshness
    /// window get a synthesized result from local Core Data + cached zone
    /// mapping instead of round-tripping CloudKit. Cleared on cold launch
    /// so the first call of each session still validates against CK.
    private var lastSuccessfulFetchAt: Date?
    private static let fetchFreshnessWindow: TimeInterval = 30  // seconds

    /// Synthesize the linked-children list from local Core Data + the
    /// deviceID→zone mapping cache, without any CloudKit round-trip.
    /// NSPersistentCloudKitContainer keeps RegisteredDevice rows mirrored to
    /// CK in near-real-time; for the typical case (repeat callers within a
    /// few seconds of each other, page-swipe refreshes, etc.) this is the
    /// same result we'd get from a full scan — without paying the network
    /// cost of downloading thousands of unrelated records per zone.
    /// Returns nil if any device row is missing its zone mapping (caller
    /// must fall back to a real CK fetch in that case).
    private func synthesizeLinkedChildDevicesFromLocal() -> [RegisteredDevice]? {
        let parentDeviceID = DeviceModeManager.shared.deviceID
        guard !parentDeviceID.isEmpty else { return nil }
        let context = PersistenceController.shared.container.viewContext
        let req: NSFetchRequest<RegisteredDevice> = RegisteredDevice.fetchRequest()
        req.predicate = NSPredicate(format: "deviceType == %@ AND parentDeviceID == %@", "child", parentDeviceID)
        guard let rows = try? context.fetch(req), !rows.isEmpty else { return nil }

        // Dedupe by deviceID — NSPersistentCloudKitContainer can mirror the
        // same record into multiple rows after pair/unpair/repair cycles.
        var seen = Set<String>()
        var deduped: [RegisteredDevice] = []
        for row in rows {
            guard let id = row.deviceID, seen.insert(id).inserted else { continue }
            // Enrich from cache; if any device is missing its zone mapping,
            // we don't trust the synthesis — fall back to a real CK fetch.
            if row.sharedZoneID == nil || row.sharedZoneOwner == nil {
                guard let pair = Self.cachedZoneInfo(forDeviceID: id, parentDeviceID: parentDeviceID) else {
                    return nil
                }
                row.sharedZoneID = pair.zoneName
                row.sharedZoneOwner = pair.zoneOwner
            }
            deduped.append(row)
        }
        return deduped
    }

    /// Fetch linked child devices from private database by querying each ChildMonitoring zone
    ///
    /// - Parameter restrictToKnownZones: When `true` (default), only query zones whose
    ///   IDs are recorded on already-paired RegisteredDevice rows in local Core Data.
    ///   This skips orphan zones left behind by old test pairings — the parent's
    ///   private DB can accumulate dozens of stale ChildMonitoring-* zones over
    ///   time, and scanning them all serially was the dominant cause of multi-minute
    ///   dashboard load times. Falls back to a full scan if no known zones exist
    ///   yet (cold start, fresh install). Pairing/discovery flows must pass `false`
    ///   so a newly-paired child's zone (not yet in local cache) is found.
    func fetchLinkedChildDevices(restrictToKnownZones: Bool = true) async throws -> [RegisteredDevice] {
        // Freshness short-circuit: if we successfully fetched within the
        // freshness window AND the caller accepts cached data (restricted
        // path), synthesize the result from local Core Data + cached zone
        // mapping. Avoids re-downloading thousands of records per zone for
        // every refresh, swipe, or seat-count check. Pairing/discovery flows
        // (restrictToKnownZones=false) always bypass.
        if restrictToKnownZones,
           let last = lastSuccessfulFetchAt,
           Date().timeIntervalSince(last) < Self.fetchFreshnessWindow,
           let synthesized = synthesizeLinkedChildDevicesFromLocal() {
            #if DEBUG
            print("[CloudKitSyncService] Freshness short-circuit: returning \(synthesized.count) device(s) from local cache (last fetch \(Int(Date().timeIntervalSince(last)))s ago)")
            #endif
            return synthesized
        }

        // Coalesce concurrent callers on the common default path. Pairing/discovery
        // flows pass `restrictToKnownZones: false` — they expect a fresh full scan
        // and must not share a result with a restricted in-flight fetch.
        if restrictToKnownZones, let existing = inFlightFetchLinkedChildDevicesTask {
            #if DEBUG
            print("[CloudKitSyncService] Awaiting in-flight fetchLinkedChildDevices")
            #endif
            return try await existing.value
        }

        let task: Task<[RegisteredDevice], Error> = Task { [weak self] in
            guard let self = self else { return [] }
            return try await self.performFetchLinkedChildDevices(restrictToKnownZones: restrictToKnownZones)
        }
        if restrictToKnownZones {
            inFlightFetchLinkedChildDevicesTask = task
        }
        defer {
            if restrictToKnownZones {
                inFlightFetchLinkedChildDevicesTask = nil
            }
        }
        return try await task.value
    }

    private func performFetchLinkedChildDevices(restrictToKnownZones: Bool) async throws -> [RegisteredDevice] {
        #if DEBUG
        print("[CloudKitSyncService] ===== Fetching Linked Child Devices (CloudKit Sharing) =====")
        print("[CloudKitSyncService] Parent Device ID: \(DeviceModeManager.shared.deviceID)")
        #endif

        let privateDatabase = container.privateCloudDatabase
        let parentDeviceID = DeviceModeManager.shared.deviceID

        // 1. Get all zones owned by this parent
        let allZones: [CKRecordZone]
        do {
            allZones = try await privateDatabase.allRecordZones()
            #if DEBUG
            print("[CloudKitSyncService] Found \(allZones.count) total zones")
            #endif
        } catch {
            #if DEBUG
            print("[CloudKitSyncService] ❌ Error fetching zones: \(error)")
            #endif
            throw error
        }

        // 2. Filter to ChildMonitoring zones only
        let allChildMonitoringZones = allZones.filter { $0.zoneID.zoneName.hasPrefix("ChildMonitoring-") }

        // 3. If restricting to known zones, intersect with the persisted
        //    known-zones cache. This drops orphan zones from old pairings —
        //    typically reducing ~20 zones to the 1-5 actually in use.
        let knownZones = knownChildZoneNames(parentDeviceID: parentDeviceID)
        let childMonitoringZones: [CKRecordZone]
        if restrictToKnownZones, !knownZones.isEmpty {
            childMonitoringZones = allChildMonitoringZones.filter { knownZones.contains($0.zoneID.zoneName) }
            #if DEBUG
            let skipped = allChildMonitoringZones.count - childMonitoringZones.count
            print("[CloudKitSyncService] Restricting to \(childMonitoringZones.count) known zone(s), skipping \(skipped) orphan zone(s)")
            #endif
        } else {
            childMonitoringZones = allChildMonitoringZones
            #if DEBUG
            if restrictToKnownZones {
                print("[CloudKitSyncService] No known zones cached — falling back to full scan (will cache after this run)")
            }
            #endif
        }

        #if DEBUG
        print("[CloudKitSyncService] Found \(childMonitoringZones.count) ChildMonitoring zones to query")
        for zone in childMonitoringZones {
            print("[CloudKitSyncService]   - \(zone.zoneID.zoneName)")
        }
        #endif

        var devices: [RegisteredDevice] = []
        var zoneRecordCounts: [String: Int] = [:]  // Track record counts per zone for deduplication
        // Track which zones we successfully scanned (whether they had a matching
        // device or not). Used by the orphan-cleanup pass to ensure we never
        // delete a zone that errored — a transient network blip during fetch
        // would otherwise look identical to "no device here" and could wipe
        // a real child's data.
        var successfullyScannedZones: Set<String> = []

        // 3. Fetch only CD_RegisteredDevice records per zone, ALL ZONES IN
        // PARALLEL via TaskGroup. Previously this loop was sequential, and
        // when the CKQuery fast path falls back to zone-changes (schema not
        // queryable in production), each zone takes ~5-6s to download all
        // 1500+ records. 5 zones sequential = ~30s wall-clock for device
        // discovery alone. With concurrent fetches, total time collapses to
        // the slowest single zone (~5-6s).
        struct ZoneFetchResult {
            let zoneID: CKRecordZone.ID
            let zoneOwner: String
            let records: [CKRecord]
            let error: Error?
        }

        let zoneResults: [ZoneFetchResult] = await withTaskGroup(of: ZoneFetchResult.self) { group in
            for zone in childMonitoringZones {
                let zoneID = zone.zoneID
                let zoneOwner = zone.zoneID.ownerName
                group.addTask { [weak self] in
                    guard let self = self else {
                        return ZoneFetchResult(zoneID: zoneID, zoneOwner: zoneOwner, records: [], error: nil)
                    }
                    #if DEBUG
                    print("[CloudKitSyncService] Querying CD_RegisteredDevice records in zone \(zoneID.zoneName)...")
                    #endif
                    do {
                        let records = try await self.fetchRegisteredDeviceRecordsInZone(zoneID: zoneID, database: privateDatabase)
                        return ZoneFetchResult(zoneID: zoneID, zoneOwner: zoneOwner, records: records, error: nil)
                    } catch {
                        return ZoneFetchResult(zoneID: zoneID, zoneOwner: zoneOwner, records: [], error: error)
                    }
                }
            }
            var collected: [ZoneFetchResult] = []
            for await result in group {
                collected.append(result)
            }
            return collected
        }

        // Process results sequentially — fast operations, no I/O.
        for result in zoneResults {
            if let error = result.error {
                if let ckError = error as? CKError, ckError.code == .zoneNotFound {
                    #if DEBUG
                    print("[CloudKitSyncService] Zone \(result.zoneID.zoneName): zone not found (deleted), skipping")
                    #endif
                } else {
                    #if DEBUG
                    print("[CloudKitSyncService] Zone \(result.zoneID.zoneName): error fetching - \(error.localizedDescription)")
                    #endif
                }
                continue
            }

            let zoneRecords = result.records
            successfullyScannedZones.insert(result.zoneID.zoneName)
            zoneRecordCounts[result.zoneID.zoneName] = zoneRecords.count

            #if DEBUG
            print("[CloudKitSyncService] Zone \(result.zoneID.zoneName): fetched \(zoneRecords.count) CD_RegisteredDevice record(s)")
            #endif

            for record in zoneRecords {
                guard record.recordType == "CD_RegisteredDevice" else { continue }

                let deviceType = record["CD_deviceType"] as? String
                let recordParentID = record["CD_parentDeviceID"] as? String

                #if DEBUG
                print("[CloudKitSyncService]   Record: \(record.recordID.recordName)")
                print("[CloudKitSyncService]     - deviceType: \(deviceType ?? "nil")")
                print("[CloudKitSyncService]     - parentDeviceID: \(recordParentID ?? "nil")")
                #endif

                if deviceType == "child" && recordParentID == parentDeviceID {
                    let device = convertToRegisteredDevice(record)
                    device.sharedZoneID = result.zoneID.zoneName
                    device.sharedZoneOwner = result.zoneOwner

                    if let deviceID = device.deviceID,
                       let existingIndex = devices.firstIndex(where: { $0.deviceID == deviceID }) {
                        let existingDevice = devices[existingIndex]
                        let existingZoneCount = zoneRecordCounts[existingDevice.sharedZoneID ?? ""] ?? 0
                        let newZoneCount = zoneRecords.count

                        if newZoneCount > existingZoneCount {
                            devices[existingIndex] = device
                            #if DEBUG
                            print("[CloudKitSyncService]   🔄 Replaced with more active zone: \(device.childName ?? deviceID)")
                            print("[CloudKitSyncService]      \(result.zoneID.zoneName) (\(newZoneCount) records) > \(existingDevice.sharedZoneID ?? "?") (\(existingZoneCount) records)")
                            #endif
                        } else {
                            #if DEBUG
                            print("[CloudKitSyncService]   ⚠️ Skipping less active zone: \(device.childName ?? deviceID) from \(result.zoneID.zoneName) (\(newZoneCount) records)")
                            #endif
                        }
                    } else {
                        devices.append(device)
                        #if DEBUG
                        print("[CloudKitSyncService]   ✅ Found matching child: \(device.deviceName ?? "unknown") (\(device.deviceID ?? "nil"))")
                        #endif
                    }
                }
            }
        }

        #if DEBUG
        print("[CloudKitSyncService] ✅ Total: Found \(devices.count) child device(s) across all zones")
        #endif

        // Persist the canonical known-zone set so the next fetch (this launch
        // or a later one) can take the restricted-zone fast path.
        //
        // Two safety conditions: result non-empty (don't clobber a good cache
        // with a network-blip empty), AND every zone in this scan succeeded
        // (a partial result would lock subsequent fast-path runs onto the
        // wrong set and hide a real child whose zone just happened to error
        // out this time).
        let freshZoneSet = Set(devices.compactMap { $0.sharedZoneID })
        let didFullScan = childMonitoringZones.count == allChildMonitoringZones.count
        let allScansSucceeded = successfullyScannedZones.count == childMonitoringZones.count

        if !freshZoneSet.isEmpty && allScansSucceeded {
            saveKnownChildZoneNames(freshZoneSet, parentDeviceID: parentDeviceID)
            saveChildZoneMapping(devices, parentDeviceID: parentDeviceID)
            lastSuccessfulFetchAt = Date()
        } else if !freshZoneSet.isEmpty && !allScansSucceeded {
            #if DEBUG
            let failedCount = childMonitoringZones.count - successfullyScannedZones.count
            print("[CloudKitSyncService] ⏸ Skipping known-zones cache update: \(failedCount) zone(s) failed — keeping previous cache")
            #endif
        }

        // One-shot orphan-zone cleanup. Three safety conditions must all hold:
        //  1. We took the full-scan path (otherwise a not-yet-cached real zone
        //     would look like an orphan).
        //  2. EVERY zone in the scan succeeded — a single network error during
        //     fetch would make a real child's zone look empty, and we must not
        //     delete it.
        //  3. We did find at least one real child this run (sanity check that
        //     CloudKit is reachable and the parent is correctly authenticated).
        if didFullScan && allScansSucceeded && !freshZoneSet.isEmpty {
            await deleteOrphanChildMonitoringZonesOnce(
                keeping: freshZoneSet,
                parentDeviceID: parentDeviceID,
                scannedZoneNames: successfullyScannedZones,
                allZones: allChildMonitoringZones,
                database: privateDatabase
            )
        } else if didFullScan && !allScansSucceeded {
            #if DEBUG
            let failedCount = childMonitoringZones.count - successfullyScannedZones.count
            print("[CloudKitSyncService] ⏸ Skipping orphan cleanup: \(failedCount) zone(s) failed to scan — will retry next launch")
            #endif
        }

        return devices
    }

    /// Returns true if the given zone contains a CD_RegisteredDevice record for
    /// a child paired with this parent. Used by ParentPairingView's polling
    /// loop to detect when the just-paired child has written their device
    /// record into the freshly-created zone — querying a single known zone
    /// instead of full-scanning every zone in the account, which previously
    /// raced with the pairing itself (the slow full scan finished *after* the
    /// child had paired, so the polling baseline captured the new child as
    /// already-present and could never detect them appearing).
    func isChildPairedInZone(zoneID: CKRecordZone.ID) async throws -> Bool {
        let parentDeviceID = DeviceModeManager.shared.deviceID
        // Type-filtered fetch (1-2 records) instead of all records in zone
        // (1500+) — keeps each poll iteration sub-second instead of 30s+.
        let records = try await fetchRegisteredDeviceRecordsInZone(
            zoneID: zoneID,
            database: container.privateCloudDatabase
        )
        return records.contains { record in
            (record["CD_deviceType"] as? String) == "child"
                && (record["CD_parentDeviceID"] as? String) == parentDeviceID
        }
    }

    /// One-time cleanup of orphan ChildMonitoring zones in the parent's private
    /// database. Over time, unpair/re-pair cycles and old test pairings leave
    /// behind zones we never query but that get enumerated on every fetch — a
    /// few of these can balloon to thousands of stale records, turning the
    /// dashboard load into a multi-minute scan. Runs once per parent device
    /// (UserDefaults flag); subsequent launches skip the work entirely.
    ///
    /// A zone is treated as orphan ONLY if we successfully scanned it AND found
    /// no matching device record. Zones that errored out during scan are
    /// skipped — we don't know what's inside them, so we cannot safely delete.
    private func deleteOrphanChildMonitoringZonesOnce(
        keeping keepZoneNames: Set<String>,
        parentDeviceID: String,
        scannedZoneNames: Set<String>,
        allZones: [CKRecordZone],
        database: CKDatabase
    ) async {
        guard !parentDeviceID.isEmpty,
              let defaults = UserDefaults(suiteName: "group.com.screentimerewards.shared") else { return }

        let doneKey = orphanCleanupUDKey(parentDeviceID: parentDeviceID)
        if defaults.bool(forKey: doneKey) { return }

        // Orphan = successfully scanned this run AND not one of our real zones.
        // Never include a zone we failed to read — could be holding real data.
        let orphans = allZones.filter {
            scannedZoneNames.contains($0.zoneID.zoneName) && !keepZoneNames.contains($0.zoneID.zoneName)
        }
        guard !orphans.isEmpty else {
            defaults.set(true, forKey: doneKey)
            return
        }

        #if DEBUG
        print("[CloudKitSyncService] 🧹 Orphan cleanup: deleting \(orphans.count) stale ChildMonitoring zone(s)")
        for z in orphans {
            print("[CloudKitSyncService]   - \(z.zoneID.zoneName)")
        }
        #endif

        var deletedCount = 0
        for zone in orphans {
            do {
                _ = try await database.deleteRecordZone(withID: zone.zoneID)
                deletedCount += 1
            } catch let error as CKError where error.code == .zoneNotFound {
                // Already gone — count as success.
                deletedCount += 1
            } catch {
                #if DEBUG
                print("[CloudKitSyncService] ⚠️ Orphan delete failed for \(zone.zoneID.zoneName): \(error.localizedDescription)")
                #endif
            }
        }

        // Mark complete only if we deleted every orphan we found. Partial
        // failures (network blip) will retry on the next successful fetch.
        if deletedCount == orphans.count {
            defaults.set(true, forKey: doneKey)
            #if DEBUG
            print("[CloudKitSyncService] ✅ Orphan cleanup complete (\(deletedCount) zone(s) removed)")
            #endif
        } else {
            #if DEBUG
            print("[CloudKitSyncService] ⚠️ Orphan cleanup partial: \(deletedCount)/\(orphans.count) — will retry next launch")
            #endif
        }
    }

    /// Fetch all records in a zone using CKFetchRecordZoneChangesOperation
    /// This bypasses the need for QUERYABLE indexes on fields
    private func fetchAllRecordsInZone(zoneID: CKRecordZone.ID, database: CKDatabase) async throws -> [CKRecord] {
        return try await withCheckedThrowingContinuation { continuation in
            var fetchedRecords: [CKRecord] = []

            let config = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
            config.previousServerChangeToken = nil // Fetch all records from beginning

            let operation = CKFetchRecordZoneChangesOperation(
                recordZoneIDs: [zoneID],
                configurationsByRecordZoneID: [zoneID: config]
            )

            operation.recordWasChangedBlock = { _, result in
                switch result {
                case .success(let record):
                    fetchedRecords.append(record)
                case .failure(let error):
                    #if DEBUG
                    print("[CloudKitSyncService] Record fetch error: \(error.localizedDescription)")
                    #endif
                }
            }

            operation.recordZoneFetchResultBlock = { _, result in
                switch result {
                case .success:
                    #if DEBUG
                    print("[CloudKitSyncService] Zone fetch completed successfully")
                    #endif
                case .failure(let error):
                    #if DEBUG
                    print("[CloudKitSyncService] Zone fetch failed: \(error.localizedDescription)")
                    #endif
                }
            }

            operation.fetchRecordZoneChangesResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume(returning: fetchedRecords)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }

            database.add(operation)
        }
    }

    /// Targeted CKQuery for CD_RegisteredDevice records in a zone.
    ///
    /// Previously every fetchLinkedChildDevices iteration downloaded ALL
    /// records in each zone (1500+ usage / config / snapshot / shield records
    /// per child) just to extract the single CD_RegisteredDevice record.
    /// This made the slowest zone in the set dominate wall-clock time:
    /// ~30s per zone, regardless of parallelization.
    ///
    /// `NSPredicate(value: true)` references no fields, so it doesn't depend
    /// on per-field queryable indexes — only the recordType needs to be
    /// enumerable, which CloudKit supports for any auto-created Core Data
    /// type. If the query fails anyway (older schema, etc.), the caller's
    /// fallback path takes over.
    private static let registeredDeviceQuerySkipKey = "__registeredDeviceQueryUnsupported__"

    private func fetchRegisteredDeviceRecordsInZone(zoneID: CKRecordZone.ID, database: CKDatabase) async throws -> [CKRecord] {
        // Skip the fast query if we've learned this session that the CK
        // schema doesn't support it.
        if Self.shouldSkipZone(Self.registeredDeviceQuerySkipKey, recordType: "CD_RegisteredDevice") {
            return try await fetchAllRecordsInZoneWithRetry(zoneID: zoneID, database: database)
        }

        do {
            let predicate = NSPredicate(value: true)
            let query = CKQuery(recordType: "CD_RegisteredDevice", predicate: predicate)
            let (matches, _) = try await database.records(matching: query, inZoneWith: zoneID)
            return matches.compactMap { _, result -> CKRecord? in
                if case .success(let record) = result { return record }
                return nil
            }
        } catch let error as CKError {
            let msg = error.localizedDescription
            let isSchemaMiss = msg.localizedCaseInsensitiveContains("not marked queryable")
                || msg.localizedCaseInsensitiveContains("Did not find record type")
                || error.code == .invalidArguments
            if isSchemaMiss {
                // Once per session — every subsequent zone in this run goes
                // straight to the slow path without another wasted round-trip.
                Self.recordSchemaMiss(zone: Self.registeredDeviceQuerySkipKey, recordType: "CD_RegisteredDevice")
                #if DEBUG
                print("[CloudKitSyncService] CKQuery for CD_RegisteredDevice unsupported by schema — falling back to zone changes for the rest of this session")
                #endif
                return try await fetchAllRecordsInZoneWithRetry(zoneID: zoneID, database: database)
            }
            throw error
        }
    }

    /// Wraps `fetchAllRecordsInZone` with up to 2 retries on transient network
    /// errors. A single dropped packet during zone enumeration would otherwise
    /// silently exclude a real child from the result — and (worse) leave that
    /// child's zone looking like an orphan to the cleanup pass. Permanent
    /// errors (e.g. zoneNotFound) are rethrown immediately so callers can
    /// handle them normally.
    private func fetchAllRecordsInZoneWithRetry(zoneID: CKRecordZone.ID, database: CKDatabase) async throws -> [CKRecord] {
        let maxAttempts = 3
        var attempt = 0
        var lastError: Error?

        while attempt < maxAttempts {
            attempt += 1
            do {
                return try await fetchAllRecordsInZone(zoneID: zoneID, database: database)
            } catch let error as CKError {
                lastError = error
                let transient: Set<CKError.Code> = [
                    .networkUnavailable, .networkFailure, .serviceUnavailable,
                    .requestRateLimited, .zoneBusy
                ]
                guard transient.contains(error.code), attempt < maxAttempts else { throw error }
                let backoffSeconds = (error.retryAfterSeconds ?? Double(attempt)) // 1s, 2s, ...
                #if DEBUG
                print("[CloudKitSyncService] ↻ Retry \(attempt)/\(maxAttempts - 1) for zone \(zoneID.zoneName) after \(Int(backoffSeconds))s (\(error.code.rawValue))")
                #endif
                try? await Task.sleep(nanoseconds: UInt64(backoffSeconds * 1_000_000_000))
            } catch {
                throw error
            }
        }
        throw lastError ?? CKError(.internalError)
    }

    private func convertToRegisteredDevice(_ record: CKRecord) -> RegisteredDevice {
        // Create a transient RegisteredDevice not inserted into any context
        let context = persistenceController.container.viewContext
        let entity = NSEntityDescription.entity(forEntityName: "RegisteredDevice", in: context)!
        let device = RegisteredDevice(entity: entity, insertInto: nil)

        device.deviceID = record["CD_deviceID"] as? String
        device.deviceName = record["CD_deviceName"] as? String
        device.deviceType = record["CD_deviceType"] as? String
        device.parentDeviceID = record["CD_parentDeviceID"] as? String
        device.registrationDate = record["CD_registrationDate"] as? Date
        device.childName = record["CD_childName"] as? String
        if let active = record["CD_isActive"] as? Int { device.isActive = active != 0 } else { device.isActive = false }

        // Capture modification date for deduplication (prefer most recent zone)
        device.lastSyncDate = record.modificationDate

        // Extract zone info from the CKRecord for zone-specific queries
        device.sharedZoneID = record.recordID.zoneID.zoneName
        device.sharedZoneOwner = record.recordID.zoneID.ownerName

        return device
    }

    func fetchChildUsageData(deviceID: String, dateRange: DateInterval) async throws -> [UsageRecord] {
        let context = persistenceController.container.viewContext
        let fetchRequest: NSFetchRequest<UsageRecord> = UsageRecord.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "deviceID == %@ AND sessionStart >= %@ AND sessionStart <= %@", 
                                           deviceID, dateRange.start as NSDate, dateRange.end as NSDate)
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "sessionStart", ascending: true)]
        
        return try context.fetch(fetchRequest)
    }

    func fetchChildDailySummary(deviceID: String, date: Date) async throws -> DailySummary? {
        let context = persistenceController.container.viewContext
        let fetchRequest: NSFetchRequest<DailySummary> = DailySummary.fetchRequest()
        // Assuming we're looking for a summary for the specific date and device
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        fetchRequest.predicate = NSPredicate(format: "deviceID == %@ AND date >= %@ AND date < %@", 
                                           deviceID, startOfDay as NSDate, endOfDay as NSDate)
        
        let results = try context.fetch(fetchRequest)
        return results.first
    }

    func sendConfigurationToChild(deviceID: String, configuration: AppConfiguration) async throws {
        let context = persistenceController.container.viewContext

        // Create a configuration command for the child device
        let command = ConfigurationCommand(context: context)
        command.commandID = UUID().uuidString
        command.targetDeviceID = deviceID
        command.commandType = "update_configuration"

        // Serialize the configuration to JSON
        let configDict: [String: Any] = [
            "logicalID": configuration.logicalID ?? "",
            "tokenHash": configuration.tokenHash ?? "",
            "displayName": configuration.displayName ?? "",
            "category": configuration.category ?? "",
            "pointsPerMinute": Int(configuration.pointsPerMinute),
            "isEnabled": configuration.isEnabled,
            "blockingEnabled": configuration.blockingEnabled
        ]

        command.payloadJSON = try JSONSerialization.data(withJSONObject: configDict).base64EncodedString()
        command.createdAt = Date()
        command.status = "pending"

        try context.save()

        print("[CloudKit] Configuration command sent to device: \(deviceID)")
    }

    /// Send configuration update from MutableAppConfigDTO (used by DTO-based parent views)
    func sendConfigurationToChild(deviceID: String, mutableConfig: MutableAppConfigDTO) async throws {
        let context = persistenceController.container.viewContext

        // Create a configuration command for the child device
        let command = ConfigurationCommand(context: context)
        command.commandID = UUID().uuidString
        command.targetDeviceID = deviceID
        command.commandType = "update_configuration"

        // Serialize the configuration to JSON
        let configDict: [String: Any] = [
            "logicalID": mutableConfig.logicalID,
            "tokenHash": mutableConfig.tokenHash ?? "",
            "displayName": mutableConfig.displayName,
            "category": mutableConfig.category,
            "pointsPerMinute": mutableConfig.pointsPerMinute,
            "isEnabled": mutableConfig.isEnabled,
            "blockingEnabled": mutableConfig.blockingEnabled
        ]

        command.payloadJSON = try JSONSerialization.data(withJSONObject: configDict).base64EncodedString()
        command.createdAt = Date()
        command.status = "pending"

        try context.save()

        print("[CloudKit] Configuration command (from DTO) sent to device: \(deviceID)")
    }

    func requestChildSync(deviceID: String) async throws {
        let context = persistenceController.container.viewContext
        
        // Create a sync request command for the child device
        let command = ConfigurationCommand(context: context)
        command.commandID = UUID().uuidString
        command.targetDeviceID = deviceID
        command.commandType = "request_sync"
        command.payloadJSON = Data().base64EncodedString() // Empty payload
        command.createdAt = Date()
        command.status = "pending"
        
        try context.save()
        
        print("[CloudKit] Sync request sent to device: \(deviceID)")
    }

    /// Send a full configuration update command to a child device.
    /// This includes all editable fields: schedule, daily limits, time windows,
    /// linked learning apps, unlock mode, and streak settings.
    ///
    /// - Parameters:
    ///   - deviceID: The target child device ID
    ///   - payload: The full configuration payload from parent
    func sendFullConfigurationCommand(deviceID: String, payload: FullConfigUpdatePayload) async throws {
        let context = persistenceController.container.viewContext

        let command = ConfigurationCommand(context: context)
        command.commandID = payload.commandID
        command.targetDeviceID = deviceID
        command.commandType = "update_full_config"
        command.payloadJSON = try payload.toBase64String()
        command.createdAt = Date()
        command.status = "pending"

        try context.save()

        #if DEBUG
        print("[CloudKit] ===== Full Config Command Sent =====")
        print("[CloudKit] Command ID: \(payload.commandID)")
        print("[CloudKit] Target Device: \(deviceID)")
        print("[CloudKit] App: \(payload.logicalID)")
        print("[CloudKit] Category: \(payload.category)")
        print("[CloudKit] Points/min: \(payload.pointsPerMinute)")
        print("[CloudKit] Enabled: \(payload.isEnabled)")
        print("[CloudKit] Blocking: \(payload.blockingEnabled)")
        print("[CloudKit] Linked apps: \(payload.linkedLearningApps.count)")
        print("[CloudKit] Unlock mode: \(payload.unlockMode.rawValue)")
        print("[CloudKit] Has schedule: \(payload.scheduleConfig != nil)")
        print("[CloudKit] Has streak: \(payload.streakSettings != nil)")
        #endif
    }

    // MARK: - Parent Command Zone Infrastructure

    /// Zone name prefix for parent commands - separate from Core Data managed zones
    private static let parentCommandsZonePrefix = "ParentCommands-"

    /// Check CloudKit account status and log details
    private func checkAndLogCloudKitAccountStatus() async -> CKAccountStatus {
        do {
            let status = try await container.accountStatus()
            #if DEBUG
            let statusString: String
            switch status {
            case .available:
                statusString = "✅ available"
            case .noAccount:
                statusString = "❌ noAccount - User not signed into iCloud"
            case .restricted:
                statusString = "⚠️ restricted - Parental controls or MDM"
            case .couldNotDetermine:
                statusString = "⚠️ couldNotDetermine"
            case .temporarilyUnavailable:
                statusString = "⚠️ temporarilyUnavailable"
            @unknown default:
                statusString = "❓ unknown status: \(status.rawValue)"
            }
            print("[CloudKitSyncService] 🔍 Account Status: \(statusString)")
            #endif
            return status
        } catch {
            #if DEBUG
            print("[CloudKitSyncService] ❌ Failed to check account status: \(error)")
            #endif
            return .couldNotDetermine
        }
    }

    /// UserDefaults key persisting the parent's chosen ParentCommands zone name.
    /// Survives `DeviceModeManager.deviceID` rotation across reinstalls so we
    /// keep writing to whichever zone was originally shared with paired children.
    /// Bumped to _v2 on the participant-acceptance-aware detection upgrade so
    /// any cached _v1 value (which may have persisted a zone with no accepted
    /// participants) is ignored and a fresh scan runs.
    private static let primaryParentCommandsZoneKey = "primaryParentCommandsZoneName_v3"

    /// Result tuple from active-share discovery: the zone to write to AND the
    /// root record ID that records should use as their `parent` reference.
    /// We can't derive the root recordName from the zone name alone — historic
    /// zones may have root records named differently (or deleted), but as long
    /// as ANY record in the zone carries a non-nil `.share` with accepted
    /// participants, we use that record as the parent.
    typealias ActiveSharedZone = (zoneID: CKRecordZone.ID, rootRecordID: CKRecord.ID)

    /// Enumerate a zone's records via CKFetchRecordZoneChangesOperation and
    /// return the FIRST record found that has a `.share` attached. Bounded by
    /// a 10s timeout so a hung fetch doesn't block the scan.
    private func findSharedRootRecord(in zoneID: CKRecordZone.ID, db: CKDatabase) async -> CKRecord? {
        var sharedRoot: CKRecord?
        let fetchConfig = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
        fetchConfig.previousServerChangeToken = nil
        let op = CKFetchRecordZoneChangesOperation(
            recordZoneIDs: [zoneID],
            configurationsByRecordZoneID: [zoneID: fetchConfig])
        op.qualityOfService = .userInitiated

        actor RootResumeGuard { var done = false; func tryResume() -> Bool { if done { return false }; done = true; return true } }
        let resumeGuard = RootResumeGuard()

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            op.recordWasChangedBlock = { _, result in
                if case .success(let record) = result, record.share != nil, sharedRoot == nil {
                    sharedRoot = record
                }
            }
            op.fetchRecordZoneChangesResultBlock = { _ in
                Task { if await resumeGuard.tryResume() { continuation.resume() } }
            }
            db.add(op)
            Task {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                if await resumeGuard.tryResume() {
                    op.cancel()
                    continuation.resume()
                }
            }
        }
        return sharedRoot
    }

    /// Find an existing ParentCommands-* zone whose CKShare has at least one
    /// participant who has accepted the invitation. Discovery walks each zone's
    /// records to find the root (rather than guessing its recordName from the
    /// deviceID — historic zones may have root records named differently or
    /// missing entirely).
    ///
    /// Returns nil if no zone with accepted participants exists.
    private func findActiveSharedParentCommandsZone(in zones: [CKRecordZone], db: CKDatabase) async -> ActiveSharedZone? {
        let candidates = zones.filter { $0.zoneID.zoneName.hasPrefix(Self.parentCommandsZonePrefix) }
        #if DEBUG
        print("[CloudKitSyncService] 🔍 Scanning \(candidates.count) ParentCommands-* zones for active shares...")
        #endif
        for zone in candidates {
            // Walk the zone's records to discover the actual shared root record.
            // We don't assume a specific recordName — historic zones may have
            // roots named differently, or no root at all.
            guard let rootRecord = await findSharedRootRecord(in: zone.zoneID, db: db) else {
                #if DEBUG
                print("[CloudKitSyncService]   • \(zone.zoneID.zoneName): no shared root record found in zone")
                #endif
                continue
            }
            guard let shareRef = rootRecord.share else { continue }
            do {
                guard let share = try await db.record(for: shareRef.recordID) as? CKShare else {
                    #if DEBUG
                    print("[CloudKitSyncService]   • \(zone.zoneID.zoneName): share record fetched but not a CKShare")
                    #endif
                    continue
                }
                // Owner is always a participant; we want at least one OTHER
                // participant who has accepted the invitation.
                let activeParticipants = share.participants.filter { participant in
                    participant.role != .owner && participant.acceptanceStatus == .accepted
                }
                if !activeParticipants.isEmpty {
                    #if DEBUG
                    print("[CloudKitSyncService] 🔍 Found actively-shared parent commands zone: \(zone.zoneID.zoneName) (root=\(rootRecord.recordID.recordName), \(activeParticipants.count) accepted participant(s))")
                    #endif
                    return (zoneID: zone.zoneID, rootRecordID: rootRecord.recordID)
                } else {
                    #if DEBUG
                    let participantSummary = share.participants.map { p -> String in
                        let role: String
                        switch p.role { case .owner: role = "owner"; case .privateUser: role = "private"; case .publicUser: role = "public"; case .unknown: role = "unknown"; @unknown default: role = "?" }
                        let status: String
                        switch p.acceptanceStatus { case .pending: status = "pending"; case .accepted: status = "accepted"; case .removed: status = "removed"; case .unknown: status = "unknown"; @unknown default: status = "?" }
                        return "\(role)=\(status)"
                    }.joined(separator: ", ")
                    print("[CloudKitSyncService]   • \(zone.zoneID.zoneName): share exists (root=\(rootRecord.recordID.recordName)) but no accepted child participants — [\(participantSummary)]")
                    #endif
                }
            } catch {
                #if DEBUG
                print("[CloudKitSyncService]   • \(zone.zoneID.zoneName): share fetch failed: \(error.localizedDescription)")
                #endif
                continue
            }
        }
        return nil
    }

    /// Get or create the parent's command zone
    /// This zone is owned by the parent and shared with child devices.
    /// Survives DeviceModeManager.deviceID rotation by preferring an existing
    /// shared zone (i.e., the zone that paired children already accept invites
    /// for) over creating a fresh zone bound to the current deviceID.
    /// Returns the zone to write commands to AND the root recordID to use as
    /// each command's `parent` reference. The root recordID is discovered from
    /// the zone (not derived from the current deviceID) so it always matches
    /// the actual shared root, even after deviceID rotation.
    private func getOrCreateParentCommandsZone() async throws -> ActiveSharedZone {
        let db = container.privateCloudDatabase
        let parentDeviceID = DeviceModeManager.shared.deviceID
        let preferredZoneName = Self.parentCommandsZonePrefix + parentDeviceID

        #if DEBUG
        print("[CloudKitSyncService] ===== Zone Creation Diagnostics =====")
        print("[CloudKitSyncService] Preferred zone name (current deviceID): \(preferredZoneName)")
        print("[CloudKitSyncService] Container ID: \(container.containerIdentifier ?? "nil")")
        #endif

        // Check account status first
        let accountStatus = await checkAndLogCloudKitAccountStatus()
        guard accountStatus == .available else {
            #if DEBUG
            print("[CloudKitSyncService] ❌ CloudKit account not available, cannot create zone")
            #endif
            throw CloudKitSyncError.zoneNotFound(deviceID: parentDeviceID)
        }

        // Check if zone already exists
        #if DEBUG
        print("[CloudKitSyncService] 🔍 Fetching all zones from privateCloudDatabase...")
        #endif

        let existingZones = try await db.allRecordZones()

        #if DEBUG
        print("[CloudKitSyncService] 🔍 Found \(existingZones.count) zones:")
        for zone in existingZones {
            print("[CloudKitSyncService]   - \(zone.zoneID.zoneName) (owner: \(zone.zoneID.ownerName))")
        }
        #endif

        // Selection priority:
        //   1. Persisted choice from UserDefaults — survives deviceID rotation.
        //      Validate it still exists in private DB.
        //   2. Any ParentCommands-* zone with a CKShare attached — i.e. one that
        //      paired children already accept. Persist this choice.
        //   3. Zone matching the current deviceID — for fresh installs only.
        //   4. Fall through and create a new zone using the current deviceID.

        // Always run the active-share scan first. It both diagnoses each
        // zone's acceptance state in the log AND yields the discovered root
        // recordID — which is what we MUST use as the parent reference for
        // command records (otherwise the share doesn't include them).
        if let acceptedShared = await findActiveSharedParentCommandsZone(in: existingZones, db: db) {
            UserDefaults.standard.set(acceptedShared.zoneID.zoneName, forKey: Self.primaryParentCommandsZoneKey)
            #if DEBUG
            print("[CloudKitSyncService] ✅ Adopted active shared zone (deviceID likely rotated): \(acceptedShared.zoneID.zoneName)")
            #endif
            return acceptedShared
        }

        // Fall through: no zone has accepted participants. We will use the
        // current-deviceID zone (creating it if needed) with the deviceID-derived
        // root record name. This zone has no accepted children yet, so the
        // command won't actually reach anyone — but we don't persist the choice
        // and will keep re-scanning on every save in case a child accepts later.
        let fallbackRootID = CKRecord.ID(
            recordName: "CommandsRoot-\(parentDeviceID)",
            zoneID: CKRecordZone.ID(zoneName: preferredZoneName, ownerName: CKCurrentUserDefaultName))
        if let existing = existingZones.first(where: { $0.zoneID.zoneName == preferredZoneName }) {
            #if DEBUG
            print("[CloudKitSyncService] ⚠️ No accepted-share zone found — falling back to current-deviceID zone (NOT persisted): \(preferredZoneName)")
            print("[CloudKitSyncService] ⚠️ This command will NOT reach any child until a fresh pairing is performed.")
            #endif
            return (zoneID: existing.zoneID, rootRecordID: fallbackRootID)
        }

        // Create new zone using explicit CKModifyRecordZonesOperation for better control
        #if DEBUG
        print("[CloudKitSyncService] 🔨 Creating new parent commands zone: \(preferredZoneName)")
        #endif

        let zoneID = CKRecordZone.ID(zoneName: preferredZoneName, ownerName: CKCurrentUserDefaultName)
        let zone = CKRecordZone(zoneID: zoneID)

        // Use CKModifyRecordZonesOperation for explicit server sync with high QoS
        let savedZoneID = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CKRecordZone.ID, Error>) in
            let operation = CKModifyRecordZonesOperation(recordZonesToSave: [zone], recordZoneIDsToDelete: nil)
            operation.qualityOfService = .userInitiated

            operation.modifyRecordZonesResultBlock = { result in
                switch result {
                case .success:
                    #if DEBUG
                    print("[CloudKitSyncService] ✅ CKModifyRecordZonesOperation completed successfully")
                    #endif
                    continuation.resume(returning: zoneID)
                case .failure(let error):
                    #if DEBUG
                    print("[CloudKitSyncService] ❌ CKModifyRecordZonesOperation failed: \(error)")
                    if let ckError = error as? CKError {
                        print("[CloudKitSyncService] CKError code: \(ckError.code.rawValue) - \(ckError.code)")
                        if let partialErrors = ckError.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error] {
                            for (key, partialError) in partialErrors {
                                print("[CloudKitSyncService]   Partial error for \(key): \(partialError)")
                            }
                        }
                        if let retryAfter = ckError.userInfo[CKErrorRetryAfterKey] as? TimeInterval {
                            print("[CloudKitSyncService]   Retry after: \(retryAfter) seconds")
                        }
                    }
                    #endif
                    continuation.resume(throwing: error)
                }
            }

            db.add(operation)
        }

        // VERIFICATION: Immediately fetch zones again to confirm zone was actually created on server
        #if DEBUG
        print("[CloudKitSyncService] 🔍 Verifying zone was created on server...")
        #endif

        // Small delay to allow server propagation
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

        let verifyZones = try await db.allRecordZones()
        let verified = verifyZones.contains(where: { $0.zoneID.zoneName == preferredZoneName })

        #if DEBUG
        if verified {
            print("[CloudKitSyncService] ✅ VERIFIED: Zone exists on server after creation")
        } else {
            print("[CloudKitSyncService] ⚠️ WARNING: Zone NOT found on server after creation!")
            print("[CloudKitSyncService] ⚠️ This may indicate local caching without server sync")
            print("[CloudKitSyncService] Zones after verification: \(verifyZones.map { $0.zoneID.zoneName })")
        }
        #endif

        // Do NOT persist the just-created zone name. The zone has no accepted
        // child participants yet — persisting now would cache a dead zone and
        // suppress future scans. The persisted name is only set inside the
        // accepted-share branch of getOrCreateParentCommandsZone, after a child
        // joins the share.

        let newRootID = CKRecord.ID(
            recordName: "CommandsRoot-\(parentDeviceID)",
            zoneID: savedZoneID)
        return (zoneID: savedZoneID, rootRecordID: newRootID)
    }

    /// Share the parent commands zone with a specific child device
    /// Call this after pairing to ensure child can read commands
    func shareParentCommandsZoneWithChild(childShareURL: URL) async throws {
        let db = container.privateCloudDatabase
        let resolved = try await getOrCreateParentCommandsZone()
        let zoneID = resolved.zoneID
        let rootRecordID = resolved.rootRecordID

        #if DEBUG
        print("[CloudKitSyncService] Sharing parent commands zone with child...")
        print("[CloudKitSyncService] Zone: \(zoneID.zoneName)")
        print("[CloudKitSyncService] Root: \(rootRecordID.recordName)")
        #endif

        // Check if root record already exists
        do {
            _ = try await db.record(for: rootRecordID)
            #if DEBUG
            print("[CloudKitSyncService] Root record already exists, zone already shareable")
            #endif
            return
        } catch let error as CKError where error.code == .unknownItem {
            // Record doesn't exist, we'll create it
        }

        let rootRecord = CKRecord(recordType: "CommandsRoot", recordID: rootRecordID)
        rootRecord["parentDeviceID"] = DeviceModeManager.shared.deviceID as CKRecordValue
        rootRecord["createdAt"] = Date() as CKRecordValue

        // Create share with readWrite permission so child can mark commands as executed
        let share = CKShare(rootRecord: rootRecord)
        share[CKShare.SystemFieldKey.title] = "Parent Commands" as CKRecordValue
        share.publicPermission = .readWrite

        // Save root record and share together
        let (saveResults, _) = try await db.modifyRecords(saving: [rootRecord, share], deleting: [])

        for (recordID, result) in saveResults {
            switch result {
            case .success(let record):
                if let savedShare = record as? CKShare {
                    #if DEBUG
                    print("[CloudKitSyncService] ✅ Parent commands zone shared")
                    print("[CloudKitSyncService] Share URL: \(savedShare.url?.absoluteString ?? "nil")")
                    #endif
                }
            case .failure(let error):
                #if DEBUG
                print("[CloudKitSyncService] ⚠️ Error saving \(recordID): \(error.localizedDescription)")
                #endif
            }
        }
    }

    // MARK: - Parent → Child Configuration Commands (Parent-Owned Zone)

    /// Send a configuration command to the parent's own zone (which is shared with child)
    /// This is the correct approach: parent writes to their own zone, child reads from sharedCloudDatabase
    func sendConfigCommandToSharedZone(deviceID: String, payload: FullConfigUpdatePayload) async throws {
        #if DEBUG
        print("[CloudKitSyncService] ===== Sending Config Command to Parent's Zone =====")
        print("[CloudKitSyncService] Target Device: \(deviceID)")
        print("[CloudKitSyncService] Command ID: \(payload.commandID)")
        #endif

        // Check account status first
        let accountStatus = await checkAndLogCloudKitAccountStatus()
        guard accountStatus == .available else {
            #if DEBUG
            print("[CloudKitSyncService] ❌ CloudKit account not available, cannot send command")
            #endif
            throw CloudKitSyncError.zoneNotFound(deviceID: deviceID)
        }

        // Get or create the parent's command zone (and discovered root record).
        let db = container.privateCloudDatabase
        let resolved = try await getOrCreateParentCommandsZone()
        let zoneID = resolved.zoneID
        let rootRecordID = resolved.rootRecordID

        #if DEBUG
        print("[CloudKitSyncService] Using zone: \(zoneID.zoneName)")
        #endif

        // Create CKRecord for the command
        let recordID = CKRecord.ID(recordName: "ConfigCmd-\(payload.commandID)", zoneID: zoneID)
        let record = CKRecord(recordType: "ConfigurationCommand", recordID: recordID)

        // Link record to the share's root record so it's visible to child.
        // The root recordID came from getOrCreateParentCommandsZone, which
        // discovered it by enumerating the zone (not by guessing from the
        // current deviceID). This works even when historic root records use
        // a different naming scheme than CommandsRoot-{currentDeviceID}.
        record.parent = CKRecord.Reference(recordID: rootRecordID, action: .none)

        #if DEBUG
        print("[CloudKitSyncService] Setting parent reference to: \(rootRecordID.recordName)")
        #endif

        record["commandID"] = payload.commandID as CKRecordValue
        record["targetDeviceID"] = deviceID as CKRecordValue
        record["commandType"] = "update_full_config" as CKRecordValue
        record["payloadJSON"] = try payload.toBase64String() as CKRecordValue
        record["createdAt"] = Date() as CKRecordValue
        record["status"] = "pending" as CKRecordValue
        record["parentDeviceID"] = DeviceModeManager.shared.deviceID as CKRecordValue

        // Use explicit CKModifyRecordsOperation for better server sync control
        let savedRecordName = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            let operation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
            operation.qualityOfService = .userInitiated
            operation.savePolicy = .changedKeys

            // CRITICAL: Add per-record callback to catch individual record errors
            operation.perRecordSaveBlock = { recordID, result in
                #if DEBUG
                switch result {
                case .success(let savedRecord):
                    print("[CloudKitSyncService] [PER-RECORD] ✅ Record saved: \(recordID.recordName)")
                    print("[CloudKitSyncService] [PER-RECORD]   Type: \(savedRecord.recordType)")
                case .failure(let error):
                    print("[CloudKitSyncService] [PER-RECORD] ❌ Record FAILED: \(recordID.recordName)")
                    print("[CloudKitSyncService] [PER-RECORD]   Error: \(error.localizedDescription)")
                    if let ckError = error as? CKError {
                        print("[CloudKitSyncService] [PER-RECORD]   CKError code: \(ckError.code.rawValue) - \(ckError.code)")
                        // Check for specific errors
                        switch ckError.code {
                        case .serverRecordChanged:
                            print("[CloudKitSyncService] [PER-RECORD]   ⚠️ Server record changed (conflict)")
                        case .unknownItem:
                            print("[CloudKitSyncService] [PER-RECORD]   ⚠️ Unknown item (zone doesn't exist on server?)")
                        case .invalidArguments:
                            print("[CloudKitSyncService] [PER-RECORD]   ⚠️ Invalid arguments")
                        case .permissionFailure:
                            print("[CloudKitSyncService] [PER-RECORD]   ⚠️ PERMISSION FAILURE - security roles blocking write!")
                        case .zoneNotFound:
                            print("[CloudKitSyncService] [PER-RECORD]   ⚠️ Zone not found on server")
                        default:
                            break
                        }
                    }
                }
                #endif
            }

            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    #if DEBUG
                    print("[CloudKitSyncService] ✅ CKModifyRecordsOperation completed successfully")
                    #endif
                    continuation.resume(returning: recordID.recordName)
                case .failure(let error):
                    #if DEBUG
                    print("[CloudKitSyncService] ❌ CKModifyRecordsOperation failed: \(error)")
                    if let ckError = error as? CKError {
                        print("[CloudKitSyncService] CKError code: \(ckError.code.rawValue) - \(ckError.code)")
                        if let partialErrors = ckError.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error] {
                            for (key, partialError) in partialErrors {
                                print("[CloudKitSyncService]   Partial error for \(key): \(partialError)")
                            }
                        }
                        if let retryAfter = ckError.userInfo[CKErrorRetryAfterKey] as? TimeInterval {
                            print("[CloudKitSyncService]   Retry after: \(retryAfter) seconds")
                        }
                        // Check for specific error codes
                        switch ckError.code {
                        case .networkUnavailable:
                            print("[CloudKitSyncService] ⚠️ Network unavailable - record cached locally only")
                        case .networkFailure:
                            print("[CloudKitSyncService] ⚠️ Network failure - record cached locally only")
                        case .serverResponseLost:
                            print("[CloudKitSyncService] ⚠️ Server response lost")
                        case .zoneNotFound:
                            print("[CloudKitSyncService] ⚠️ Zone not found on server!")
                        default:
                            break
                        }
                    }
                    #endif
                    continuation.resume(throwing: error)
                }
            }

            db.add(operation)
        }

        #if DEBUG
        print("[CloudKitSyncService] ✅ Command saved to parent's zone: \(zoneID.zoneName)")
        print("[CloudKitSyncService] Record ID: \(savedRecordName)")
        print("[CloudKitSyncService] App: \(payload.logicalID)")
        print("[CloudKitSyncService] Linked apps: \(payload.linkedLearningApps.count)")
        #endif

        // VERIFICATION: Immediately fetch the record to confirm it exists on server
        #if DEBUG
        print("[CloudKitSyncService] 🔍 Verifying record was saved on server...")
        #endif

        // Small delay to allow server propagation
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

        do {
            let fetchedRecord = try await db.record(for: recordID)
            #if DEBUG
            print("[CloudKitSyncService] ✅ VERIFIED: Record exists on server")
            print("[CloudKitSyncService]   Record type: \(fetchedRecord.recordType)")
            print("[CloudKitSyncService]   commandID: \(fetchedRecord["commandID"] as? String ?? "nil")")
            #endif
        } catch let error as CKError where error.code == .unknownItem {
            #if DEBUG
            print("[CloudKitSyncService] ⚠️ WARNING: Record NOT found on server after save!")
            print("[CloudKitSyncService] ⚠️ This indicates the save was cached locally but not synced")
            #endif
        } catch {
            #if DEBUG
            print("[CloudKitSyncService] ⚠️ Verification fetch failed: \(error)")
            #endif
        }
    }

    // MARK: - Web Restriction Commands

    /// Send a web restriction command to child device via CloudKit
    /// This is called from the parent device to update child's web restrictions
    func sendWebRestrictionCommand(deviceID: String, payload: WebRestrictionPayload) async throws {
        #if DEBUG
        print("[CloudKitSyncService] ===== Sending Web Restriction Command =====")
        print("[CloudKitSyncService] Target Device: \(deviceID)")
        print("[CloudKitSyncService] Command ID: \(payload.commandID)")
        print("[CloudKitSyncService] Blocked websites: \(payload.blockedWebsiteCount)")
        print("[CloudKitSyncService] Blocked browsers: \(payload.blockedBrowserCount)")
        #endif

        // Check account status first
        let accountStatus = await checkAndLogCloudKitAccountStatus()
        guard accountStatus == .available else {
            #if DEBUG
            print("[CloudKitSyncService] ❌ CloudKit account not available, cannot send command")
            #endif
            throw CloudKitSyncError.zoneNotFound(deviceID: deviceID)
        }

        // Get or create the parent's command zone
        let db = container.privateCloudDatabase
        let resolved = try await getOrCreateParentCommandsZone()
        let zoneID = resolved.zoneID
        let rootRecordID = resolved.rootRecordID

        #if DEBUG
        print("[CloudKitSyncService] Using zone: \(zoneID.zoneName)")
        #endif

        // Create CKRecord for the command
        let recordID = CKRecord.ID(recordName: "WebCmd-\(payload.commandID)", zoneID: zoneID)
        let record = CKRecord(recordType: "ConfigurationCommand", recordID: recordID)

        // Link record to the share's discovered root record so it's visible to child.
        record.parent = CKRecord.Reference(recordID: rootRecordID, action: .none)

        #if DEBUG
        print("[CloudKitSyncService] Setting parent reference to: \(rootRecordID.recordName)")
        #endif

        record["commandID"] = payload.commandID as CKRecordValue
        record["targetDeviceID"] = deviceID as CKRecordValue
        record["commandType"] = "update_web_restrictions" as CKRecordValue
        record["payloadJSON"] = try payload.toBase64String() as CKRecordValue
        record["createdAt"] = Date() as CKRecordValue
        record["status"] = "pending" as CKRecordValue
        record["parentDeviceID"] = DeviceModeManager.shared.deviceID as CKRecordValue

        // Use explicit CKModifyRecordsOperation for better server sync control
        let savedRecordName = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            let operation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
            operation.qualityOfService = .userInitiated
            operation.savePolicy = .changedKeys

            operation.perRecordSaveBlock = { recordID, result in
                #if DEBUG
                switch result {
                case .success(let savedRecord):
                    print("[CloudKitSyncService] [WEB-CMD] ✅ Record saved: \(recordID.recordName)")
                    print("[CloudKitSyncService] [WEB-CMD]   Type: \(savedRecord.recordType)")
                case .failure(let error):
                    print("[CloudKitSyncService] [WEB-CMD] ❌ Record FAILED: \(recordID.recordName)")
                    print("[CloudKitSyncService] [WEB-CMD]   Error: \(error.localizedDescription)")
                }
                #endif
            }

            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    #if DEBUG
                    print("[CloudKitSyncService] ✅ Web restriction command saved successfully")
                    #endif
                    continuation.resume(returning: recordID.recordName)
                case .failure(let error):
                    #if DEBUG
                    print("[CloudKitSyncService] ❌ Web restriction command failed: \(error)")
                    #endif
                    continuation.resume(throwing: error)
                }
            }

            db.add(operation)
        }

        #if DEBUG
        print("[CloudKitSyncService] ✅ Web restriction command saved: \(savedRecordName)")
        #endif
    }

    /// Fetch pending commands from the shared zone (child side)
    /// This is called by the child device to get commands from the parent
    ///
    /// The parent saves commands to their own ParentCommands-* zone and shares it with child.
    /// Child reads from sharedCloudDatabase where the ParentCommands-* zone appears.
    func fetchPendingCommandsFromSharedZone() async throws -> [CKRecord] {
        let myDeviceID = DeviceModeManager.shared.deviceID

        #if DEBUG
        print("[CloudKitSyncService] ===== Fetching Pending Commands from Shared Zone =====")
        print("[CloudKitSyncService] My Device ID: \(myDeviceID)")
        #endif

        var commands: [CKRecord] = []

        // PRIMARY: Check sharedCloudDatabase for ParentCommands-* zones (parent's command zone shared with us)
        let sharedDB = container.sharedCloudDatabase
        let sharedZones = try await sharedDB.allRecordZones()

        #if DEBUG
        print("[CloudKitSyncService] Shared DB zones: \(sharedZones.map { $0.zoneID.zoneName })")
        #endif

        // First, look for ParentCommands-* zones (new architecture)
        for zone in sharedZones where zone.zoneID.zoneName.hasPrefix(Self.parentCommandsZonePrefix) {
            #if DEBUG
            print("[CloudKitSyncService] Checking parent commands zone: \(zone.zoneID.zoneName)")
            #endif

            do {
                // DIAGNOSTIC: First query ALL ConfigurationCommand records (no filter)
                // This helps determine if records exist but the predicate filter doesn't match
                #if DEBUG
                let debugQuery = CKQuery(recordType: "ConfigurationCommand", predicate: NSPredicate(value: true))
                do {
                    let (allRecords, _) = try await sharedDB.records(matching: debugQuery, inZoneWith: zone.zoneID, resultsLimit: 100)
                    print("[CloudKitSyncService] [DIAG] ParentCommands zone \(zone.zoneID.zoneName): \(allRecords.count) total ConfigurationCommand record(s)")
                    if !allRecords.isEmpty {
                        for (recordID, result) in allRecords {
                            if case .success(let record) = result {
                                let cmdID = record["commandID"] as? String ?? "?"
                                let targetID = record["targetDeviceID"] as? String ?? "?"
                                let status = record["status"] as? String ?? "?"
                                print("[CloudKitSyncService] [DIAG]   Record: \(cmdID) -> target:\(targetID) status:\(status)")
                            } else if case .failure(let error) = result {
                                print("[CloudKitSyncService] [DIAG]   Failed to fetch \(recordID): \(error.localizedDescription)")
                            }
                        }
                    }
                } catch {
                    print("[CloudKitSyncService] [DIAG] Error querying all records: \(error.localizedDescription)")
                }
                #endif

                // Query for pending commands targeting this device
                let predicate = NSPredicate(
                    format: "targetDeviceID == %@ AND status == %@",
                    myDeviceID,
                    "pending"
                )
                let query = CKQuery(recordType: "ConfigurationCommand", predicate: predicate)
                query.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]

                let (matches, _) = try await sharedDB.records(matching: query, inZoneWith: zone.zoneID)

                #if DEBUG
                print("[CloudKitSyncService] Zone \(zone.zoneID.zoneName) (ParentCommands): \(matches.count) pending command(s)")
                #endif

                for (_, result) in matches {
                    if case .success(let record) = result {
                        commands.append(record)
                        #if DEBUG
                        let cmdID = record["commandID"] as? String ?? "?"
                        print("[CloudKitSyncService] ✅ Found pending command from parent: \(cmdID)")
                        #endif
                    }
                }
            } catch {
                #if DEBUG
                print("[CloudKitSyncService] ⚠️ Error querying ParentCommands zone \(zone.zoneID.zoneName): \(error.localizedDescription)")
                #endif
            }
        }

        // FALLBACK: Also check ChildMonitoring-* zones for backward compatibility
        for zone in sharedZones where zone.zoneID.zoneName.hasPrefix("ChildMonitoring-") {
            do {
                // DIAGNOSTIC: First, try to fetch ALL ConfigurationCommand records (no filter)
                // This helps determine if the record exists but query filtering fails due to missing indexes
                #if DEBUG
                let debugQuery = CKQuery(recordType: "ConfigurationCommand", predicate: NSPredicate(value: true))
                do {
                    let (allRecords, _) = try await sharedDB.records(matching: debugQuery, inZoneWith: zone.zoneID, resultsLimit: 100)
                    if !allRecords.isEmpty {
                        print("[CloudKitSyncService] [DIAG] Zone \(zone.zoneID.zoneName): \(allRecords.count) total ConfigurationCommand record(s)")
                        for (_, result) in allRecords {
                            if case .success(let record) = result {
                                let cmdID = record["commandID"] as? String ?? "?"
                                let targetID = record["targetDeviceID"] as? String ?? "?"
                                let status = record["status"] as? String ?? "?"
                                print("[CloudKitSyncService] [DIAG]   - \(cmdID): target=\(targetID), status=\(status)")
                            }
                        }
                    }
                } catch {
                    print("[CloudKitSyncService] [DIAG] Error fetching all commands: \(error.localizedDescription)")
                }
                #endif

                // Now try the filtered query
                let predicate = NSPredicate(
                    format: "targetDeviceID == %@ AND status == %@",
                    myDeviceID,
                    "pending"
                )
                let query = CKQuery(recordType: "ConfigurationCommand", predicate: predicate)
                query.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]

                let (matches, _) = try await sharedDB.records(matching: query, inZoneWith: zone.zoneID)

                #if DEBUG
                print("[CloudKitSyncService] Zone \(zone.zoneID.zoneName) (shared): \(matches.count) result(s)")
                #endif

                for (_, result) in matches {
                    if case .success(let record) = result {
                        commands.append(record)
                        #if DEBUG
                        let cmdID = record["commandID"] as? String ?? "?"
                        print("[CloudKitSyncService] Found pending command: \(cmdID)")
                        #endif
                    }
                }
            } catch {
                #if DEBUG
                print("[CloudKitSyncService] ⚠️ Error querying shared zone \(zone.zoneID.zoneName): \(error.localizedDescription)")
                #endif
            }
        }

        // Also check privateCloudDatabase (zones we own - parent may have saved there)
        let privateDB = container.privateCloudDatabase
        let privateZones = try await privateDB.allRecordZones()

        #if DEBUG
        print("[CloudKitSyncService] Private DB zones: \(privateZones.map { $0.zoneID.zoneName })")
        #endif

        for zone in privateZones where zone.zoneID.zoneName.hasPrefix("ChildMonitoring-") {
            do {
                let predicate = NSPredicate(
                    format: "targetDeviceID == %@ AND status == %@",
                    myDeviceID,
                    "pending"
                )
                let query = CKQuery(recordType: "ConfigurationCommand", predicate: predicate)
                query.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]

                let (matches, _) = try await privateDB.records(matching: query, inZoneWith: zone.zoneID)

                #if DEBUG
                print("[CloudKitSyncService] Zone \(zone.zoneID.zoneName) (private): \(matches.count) result(s)")
                #endif

                for (_, result) in matches {
                    if case .success(let record) = result {
                        // Avoid duplicates if somehow in both DBs
                        let cmdID = record["commandID"] as? String ?? ""
                        if !commands.contains(where: { ($0["commandID"] as? String) == cmdID }) {
                            commands.append(record)
                            #if DEBUG
                            print("[CloudKitSyncService] Found pending command (private): \(cmdID)")
                            #endif
                        }
                    }
                }
            } catch {
                #if DEBUG
                print("[CloudKitSyncService] ⚠️ Error querying private zone \(zone.zoneID.zoneName): \(error.localizedDescription)")
                #endif
            }
        }

        #if DEBUG
        print("[CloudKitSyncService] ✅ Found \(commands.count) pending command(s)")
        #endif

        return commands
    }

    /// Mark a configuration command as executed in CloudKit shared zone
    func markCommandExecutedInSharedZone(_ record: CKRecord) async throws {
        let sharedDB = container.sharedCloudDatabase

        record["status"] = "executed" as CKRecordValue
        record["executedAt"] = Date() as CKRecordValue

        try await sharedDB.save(record)

        #if DEBUG
        let cmdID = record["commandID"] as? String ?? "?"
        print("[CloudKitSyncService] ✅ Command marked executed in shared zone: \(cmdID)")
        #endif
    }

    // MARK: - Legacy Core Data Command Methods (Deprecated)

    /// Mark a configuration command as executed
    func markConfigurationCommandExecuted(_ commandID: String) async throws {
        let context = persistenceController.container.viewContext
        let fetchRequest: NSFetchRequest<ConfigurationCommand> = ConfigurationCommand.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "commandID == %@", commandID)

        let commands = try context.fetch(fetchRequest)
        guard let command = commands.first else {
            #if DEBUG
            print("[CloudKit] Command not found for marking executed: \(commandID)")
            #endif
            return
        }

        command.status = "executed"
        command.executedAt = Date()

        try context.save()

        #if DEBUG
        print("[CloudKit] Command marked as executed: \(commandID)")
        #endif
    }

    /// Fetch pending configuration commands for this device (child side)
    func fetchPendingCommands() async throws -> [ConfigurationCommand] {
        let context = persistenceController.container.viewContext
        let fetchRequest: NSFetchRequest<ConfigurationCommand> = ConfigurationCommand.fetchRequest()
        fetchRequest.predicate = NSPredicate(
            format: "targetDeviceID == %@ AND status == %@",
            DeviceModeManager.shared.deviceID,
            "pending"
        )
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]

        return try context.fetch(fetchRequest)
    }

    // MARK: - Child Device Methods
    func downloadParentConfiguration() async throws -> [AppConfiguration] {
        let context = persistenceController.container.viewContext
        let fetchRequest: NSFetchRequest<AppConfiguration> = AppConfiguration.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "deviceID == %@", DeviceModeManager.shared.deviceID)
        
        let configurations = try context.fetch(fetchRequest)
        
        // Apply each configuration to the local ScreenTimeService
        let screenTimeService = ScreenTimeService.shared
        for config in configurations {
            screenTimeService.applyCloudKitConfiguration(config)
        }
        
        return configurations
    }

    func uploadUsageRecords(_ records: [UsageRecord]) async throws {
        // In a real implementation, we would ensure these are saved to Core Data
        // Since we're using NSPersistentCloudKitContainer, they will automatically sync
        print("[CloudKit] Usage records uploaded: \(records.count)")
    }

    func uploadDailySummary(_ summary: DailySummary) async throws {
        // In a real implementation, we would ensure this is saved to Core Data
        // Since we're using NSPersistentCloudKitContainer, it will automatically sync
        print("[CloudKit] Daily summary uploaded for date: \(summary.date ?? Date())")
    }

    // === TASK 7 IMPLEMENTATION ===
    /// Upload usage records to parent's shared zone
    /// This function is called by the child device to upload usage data to the parent's shared zone
    func uploadUsageRecordsToParent(_ records: [UsageRecord]) async throws {
        #if DEBUG
        print("[CloudKitSyncService] ===== Uploading Usage Records To Parent's Zone =====")
        print("[CloudKitSyncService] Records to upload: \(records.count)")
        #endif

        let container = CKContainer(identifier: "iCloud.com.screentimerewards")
        let sharedDB = container.sharedCloudDatabase

        // Get share context from multi-parent storage (or legacy keys)
        guard let zoneInfo = getParentZoneInfo() else {
            let error = NSError(domain: "UsageUpload", code: -1,
                              userInfo: [NSLocalizedDescriptionKey: "Missing share context - device may not be paired"])
            #if DEBUG
            print("[CloudKitSyncService] ❌ Missing share context - device may not be paired")
            #endif
            throw error
        }
        let zoneName = zoneInfo.zoneName
        let zoneOwner = zoneInfo.zoneOwner
        let rootName = zoneInfo.rootRecordName

        #if DEBUG
        print("[CloudKitSyncService] Share context found:")
        print("  - Zone Name: \(zoneName)")
        print("  - Zone Owner: \(zoneOwner)")
        print("  - Root Record Name: \(rootName)")
        #endif

        let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: zoneOwner)  // 🔧 FIX: Use parent's owner!
        let rootID = CKRecord.ID(recordName: rootName, zoneID: zoneID)

        // === UPSERT LOGIC: Query existing records to avoid duplicates ===
        // Get deviceID for the query (all records should have same deviceID)
        guard let deviceID = records.first?.deviceID else {
            #if DEBUG
            print("[CloudKitSyncService] ❌ No deviceID found in records")
            #endif
            return
        }

        // Query existing CloudKit records for today for this device
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!

        var existingRecordsByLogicalID: [String: CKRecord] = [:]

        do {
            let predicate = NSPredicate(
                format: "CD_deviceID == %@ AND CD_sessionStart >= %@ AND CD_sessionStart < %@",
                deviceID, today as NSDate, tomorrow as NSDate
            )
            let query = CKQuery(recordType: "CD_UsageRecord", predicate: predicate)
            let (matches, _) = try await sharedDB.records(matching: query, inZoneWith: zoneID)

            for (_, result) in matches {
                if case .success(let record) = result,
                   let logicalID = record["CD_logicalID"] as? String {
                    existingRecordsByLogicalID[logicalID] = record
                }
            }

            #if DEBUG
            print("[CloudKitSyncService] Found \(existingRecordsByLogicalID.count) existing records in CloudKit for today")
            #endif
        } catch {
            // If query fails (e.g., schema not ready), log and continue with creating new records
            #if DEBUG
            print("[CloudKitSyncService] ⚠️ Could not query existing records: \(error.localizedDescription)")
            print("[CloudKitSyncService] Will create new records instead of upserting")
            #endif
        }

        var toSave: [CKRecord] = []
        var updatedCount = 0
        var createdCount = 0

        for item in records {
            let rec: CKRecord

            // Check if record already exists in CloudKit for this app
            if let existingRecord = existingRecordsByLogicalID[item.logicalID ?? ""] {
                // UPDATE existing record
                rec = existingRecord
                updatedCount += 1
                #if DEBUG
                print("[CloudKitSyncService] 🔄 Updating existing record: \(existingRecord.recordID.recordName) for \(item.logicalID ?? "unknown")")
                #endif
            } else {
                // CREATE new record
                let recID = CKRecord.ID(recordName: "UR-\(UUID().uuidString)", zoneID: zoneID)
                rec = CKRecord(recordType: "CD_UsageRecord", recordID: recID)
                // Link new record to the shared root so it belongs to the share
                rec.parent = CKRecord.Reference(recordID: rootID, action: .none)
                createdCount += 1
                #if DEBUG
                print("[CloudKitSyncService] ➕ Creating new record for \(item.logicalID ?? "unknown")")
                #endif
            }

            // Map UsageRecord fields to CloudKit record fields (using CD_ prefix to match Core Data schema)
            rec["CD_deviceID"] = item.deviceID as? CKRecordValue
            rec["CD_logicalID"] = item.logicalID as? CKRecordValue
            rec["CD_displayName"] = item.displayName as? CKRecordValue
            rec["CD_sessionStart"] = item.sessionStart as? CKRecordValue
            rec["CD_sessionEnd"] = item.sessionEnd as? CKRecordValue
            rec["CD_totalSeconds"] = Int(item.totalSeconds) as CKRecordValue
            rec["CD_earnedPoints"] = Int(item.earnedPoints) as CKRecordValue
            rec["CD_category"] = item.category as? CKRecordValue
            rec["CD_syncTimestamp"] = Date() as CKRecordValue

            toSave.append(rec)
        }

        #if DEBUG
        print("[CloudKitSyncService] Prepared \(toSave.count) records: \(createdCount) new, \(updatedCount) updates")
        #endif

        if toSave.isEmpty {
            #if DEBUG
            print("[CloudKitSyncService] No records to upload")
            #endif
            return
        }

        // Save all records to shared database
        let (savedRecords, _) = try await sharedDB.modifyRecords(saving: toSave, deleting: [])
        
        #if DEBUG
        print("[CloudKitSyncService] ✅ Successfully uploaded \(savedRecords.count) usage records to parent's zone")
        #endif
        
        // Update local records as synced
        let context = persistenceController.container.viewContext
        for item in records {
            item.isSynced = true
            item.syncTimestamp = Date()
        }
        try context.save()
    }
    // === END TASK 7 IMPLEMENTATION ===

    // === APP CONFIGURATION SYNC ===
    /// Upload app configurations to parent's shared zone with full schedule data
    /// This allows parent to see all configured apps with schedules, goals, and streaks
    func uploadAppConfigurationsToParent() async throws {
        #if DEBUG
        print("[CloudKitSyncService] ===== Uploading Full App Configurations To Parent's Zone =====")
        #endif

        let context = persistenceController.container.viewContext
        let deviceID = DeviceModeManager.shared.deviceID  // Use consistent ID from registration

        // Get the set of active logicalIDs from UsagePersistence
        // Only these apps should be synced; others are orphans that should be deleted
        let activeLogicalIDs = Set(ScreenTimeService.shared.usagePersistence.loadAllApps().keys)

        #if DEBUG
        print("[CloudKitSyncService] Active apps from UsagePersistence: \(activeLogicalIDs.count)")
        #endif

        // Fetch all AppConfigurations for this device
        let fetchRequest: NSFetchRequest<AppConfiguration> = AppConfiguration.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "deviceID == %@", deviceID)
        let allConfigs = try context.fetch(fetchRequest)

        // Separate active configs from orphans
        var activeConfigs: [AppConfiguration] = []
        var orphanConfigs: [AppConfiguration] = []

        for config in allConfigs {
            if let logicalID = config.logicalID, activeLogicalIDs.contains(logicalID) {
                activeConfigs.append(config)
            } else {
                orphanConfigs.append(config)
            }
        }

        // Delete orphan configs from CoreData
        if !orphanConfigs.isEmpty {
            #if DEBUG
            print("[CloudKitSyncService] 🗑️ Found \(orphanConfigs.count) orphan AppConfigurations to delete:")
            for config in orphanConfigs {
                print("[CloudKitSyncService]   - '\(config.displayName ?? "Unknown")' (logicalID: \(config.logicalID ?? "nil"))")
            }
            #endif

            for config in orphanConfigs {
                context.delete(config)
            }
            try context.save()

            #if DEBUG
            print("[CloudKitSyncService] ✅ Deleted \(orphanConfigs.count) orphan AppConfigurations from CoreData")
            #endif
        }

        // Use only active configs for sync
        let configs = activeConfigs
        guard !configs.isEmpty else {
            #if DEBUG
            print("[CloudKitSyncService] No AppConfigurations to upload")
            #endif
            return
        }

        #if DEBUG
        print("[CloudKitSyncService] Found \(configs.count) active AppConfigurations to sync")
        #endif

        // Get share context from multi-parent storage (or legacy keys)
        guard let zoneInfo = getParentZoneInfo() else {
            #if DEBUG
            print("[CloudKitSyncService] ❌ Missing share context - device may not be paired")
            #endif
            return
        }

        let zoneID = CKRecordZone.ID(zoneName: zoneInfo.zoneName, ownerName: zoneInfo.zoneOwner)
        let rootID = CKRecord.ID(recordName: zoneInfo.rootRecordName, zoneID: zoneID)
        let sharedDB = container.sharedCloudDatabase

        // Query ALL existing records for upsert (not filtered by deviceID to find old duplicates)
        var existingByLogicalID: [String: CKRecord] = [:]
        var duplicatesToDelete: [CKRecord.ID] = []

        // Use CKFetchRecordZoneChangesOperation instead of CKQuery
        // This doesn't rely on queryable field indexes and works even when CloudKit schema isn't synced
        var allRecords: [CKRecord] = []

        let fetchConfig = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
        fetchConfig.previousServerChangeToken = nil // Fetch all records from the beginning

        let fetchOperation = CKFetchRecordZoneChangesOperation(recordZoneIDs: [zoneID], configurationsByRecordZoneID: [zoneID: fetchConfig])
        // Default QoS is .background — iOS throttles it heavily, especially when
        // attached to Xcode debugger. The result block can fail to fire entirely.
        // .userInitiated keeps the operation prioritized.
        fetchOperation.qualityOfService = .userInitiated

        // Wrap the fetch in a 15s timeout. Use an actor-isolated flag so the
        // timeout race never resumes the continuation twice. If the operation
        // hangs (e.g. iOS throttled the result block under load), we proceed
        // with whatever records were collected; missed records may produce
        // duplicate writes but nothing is lost.
        actor ResumeGuard { var done = false; func tryResume() -> Bool { if done { return false }; done = true; return true } }
        let guardActor = ResumeGuard()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            fetchOperation.recordWasChangedBlock = { recordID, result in
                if case .success(let record) = result,
                   record.recordType == "CD_AppConfiguration" {
                    allRecords.append(record)
                }
            }
            fetchOperation.fetchRecordZoneChangesResultBlock = { _ in
                Task {
                    if await guardActor.tryResume() { continuation.resume() }
                }
            }
            sharedDB.add(fetchOperation)

            Task {
                try? await Task.sleep(nanoseconds: 15_000_000_000)  // 15s
                if await guardActor.tryResume() {
                    fetchOperation.cancel()
                    #if DEBUG
                    print("[CloudKitSyncService] ⏱ AppConfiguration dedup fetch hit 15s timeout — proceeding with \(allRecords.count) records collected so far")
                    #endif
                    continuation.resume()
                }
            }
        }

        #if DEBUG
        print("[CloudKitSyncService] Fetched \(allRecords.count) AppConfiguration records from zone using zone changes")
        #endif

        // PHASE 1: Group records by displayName for deduplication
        var recordsByDisplayName: [String: [CKRecord]] = [:]

        for record in allRecords {
            if let displayName = record["CD_displayName"] as? String, !displayName.isEmpty {
                recordsByDisplayName[displayName, default: []].append(record)
            }
        }

        // PHASE 2: For each displayName group, keep only the BEST record
        // Best = has iconURL, or most recent lastModified
        for (displayName, records) in recordsByDisplayName {
            if records.count > 1 {
                // Sort: prefer records with iconURL, then by lastModified date
                let sorted = records.sorted { r1, r2 in
                    let r1HasIcon = (r1["CD_iconURL"] as? String)?.isEmpty == false
                    let r2HasIcon = (r2["CD_iconURL"] as? String)?.isEmpty == false
                    if r1HasIcon != r2HasIcon {
                        return r1HasIcon // Records with iconURL come first
                    }
                    let r1Date = r1["CD_lastModified"] as? Date ?? Date.distantPast
                    let r2Date = r2["CD_lastModified"] as? Date ?? Date.distantPast
                    return r1Date > r2Date // Newer records come first
                }

                // Keep the first (best), mark others for deletion
                let bestRecord = sorted[0]
                for record in sorted.dropFirst() {
                    duplicatesToDelete.append(record.recordID)
                }

                // Use the best record's logicalID for mapping
                if let logicalID = bestRecord["CD_logicalID"] as? String {
                    existingByLogicalID[logicalID] = bestRecord
                }

                #if DEBUG
                print("[CloudKitSyncService] 🔄 Deduping '\(displayName)': keeping 1, deleting \(sorted.count - 1) duplicates")
                #endif
            } else if let record = records.first,
                      let logicalID = record["CD_logicalID"] as? String {
                existingByLogicalID[logicalID] = record
            }
        }

        // Also add records without displayName (shouldn't happen, but be safe)
        for record in allRecords {
            if let logicalID = record["CD_logicalID"] as? String,
               existingByLogicalID[logicalID] == nil {
                let displayName = record["CD_displayName"] as? String ?? ""
                if displayName.isEmpty {
                    existingByLogicalID[logicalID] = record
                }
            }
        }

        // FIX: Detect orphan CloudKit records (deleted locally but still in CloudKit)
        // Build set of current local logicalIDs
        let localLogicalIDs = Set(configs.compactMap { $0.logicalID })

        // Find CloudKit records with no matching local CoreData record
        for (cloudLogicalID, record) in existingByLogicalID {
            if !localLogicalIDs.contains(cloudLogicalID) {
                duplicatesToDelete.append(record.recordID)
                #if DEBUG
                let name = record["CD_displayName"] as? String ?? "Unknown"
                print("[CloudKitSyncService] 🗑️ Orphan found: '\(name)' (logicalID: \(cloudLogicalID)) - will delete from CloudKit")
                #endif
            }
        }

        #if DEBUG
        print("[CloudKitSyncService] Found \(existingByLogicalID.count) unique AppConfigurations after deduplication")
        if !duplicatesToDelete.isEmpty {
            print("[CloudKitSyncService] 🗑️ Found \(duplicatesToDelete.count) records to delete (duplicates + orphans)")
        }
        #endif

        var toSave: [CKRecord] = []
        var alreadyAddedRecordIDs: Set<CKRecord.ID> = []  // Track added records to prevent duplicates
        var updatedCount = 0
        var createdCount = 0

        for config in configs {
            let rec: CKRecord
            if let existing = existingByLogicalID[config.logicalID ?? ""] {
                // Check if we already added this CloudKit record (prevents "can't save same record twice" error)
                if alreadyAddedRecordIDs.contains(existing.recordID) {
                    #if DEBUG
                    print("[CloudKitSyncService] ⚠️ Skipping duplicate CoreData record: \(config.displayName ?? "Unknown")")
                    #endif
                    continue
                }
                rec = existing
                alreadyAddedRecordIDs.insert(existing.recordID)
                updatedCount += 1
            } else {
                // Use a deterministic recordName so the create-new path is a true
                // upsert. Without this, a hung dedup fetch (existingByLogicalID
                // empty) would generate a fresh UUID every run and accumulate
                // duplicate CK records for the same logical app.
                let logicalID = config.logicalID ?? UUID().uuidString
                let recID = CKRecord.ID(recordName: "AC-\(deviceID)-\(logicalID)", zoneID: zoneID)
                rec = CKRecord(recordType: "CD_AppConfiguration", recordID: recID)
                rec.parent = CKRecord.Reference(recordID: rootID, action: .none)
                createdCount += 1
            }

            // Basic fields
            rec["CD_logicalID"] = config.logicalID as CKRecordValue?
            rec["CD_deviceID"] = config.deviceID as CKRecordValue?
            rec["CD_displayName"] = config.displayName as CKRecordValue?
            rec["CD_iconURL"] = config.iconURL as CKRecordValue?
            rec["CD_category"] = config.category as CKRecordValue?
            rec["CD_pointsPerMinute"] = Int(config.pointsPerMinute) as CKRecordValue
            rec["CD_isEnabled"] = config.isEnabled as CKRecordValue
            rec["CD_blockingEnabled"] = config.blockingEnabled as CKRecordValue
            rec["CD_lastModified"] = (config.lastModified ?? Date()) as CKRecordValue
            rec["CD_tokenHash"] = config.tokenHash as CKRecordValue?

            // Fetch full schedule configuration for this app
            if let logicalID = config.logicalID,
               let scheduleConfig = AppScheduleService.shared.getSchedule(for: logicalID) {

                // Encode full schedule config as JSON
                if let scheduleJSON = encodeToJSON(scheduleConfig) {
                    rec["CD_scheduleConfigJSON"] = scheduleJSON as CKRecordValue
                    #if DEBUG
                    print("[CloudKitSyncService]   \(config.displayName ?? "?") - added schedule config")
                    #endif
                }

                // Encode linked learning apps with display names for parent dashboard
                if !scheduleConfig.linkedLearningApps.isEmpty {
                    // Enrich linked apps with display names and filter out invalid ones
                    var enrichedLinkedApps: [LinkedLearningApp] = []
                    for var linkedApp in scheduleConfig.linkedLearningApps {
                        if linkedApp.displayName == nil {
                            // Look up display name from ScreenTimeService
                            if let name = ScreenTimeService.shared.getDisplayName(for: linkedApp.logicalID) {
                                linkedApp.displayName = name
                            }
                        }
                        // Only include apps that have a valid display name (i.e., still exist on device)
                        if linkedApp.displayName != nil {
                            enrichedLinkedApps.append(linkedApp)
                        } else {
                            #if DEBUG
                            print("[CloudKitSyncService]   ⚠️ Filtering out orphaned linked app: \(linkedApp.logicalID)")
                            #endif
                        }
                    }

                    if !enrichedLinkedApps.isEmpty {
                        if let linkedJSON = encodeToJSON(enrichedLinkedApps) {
                            rec["CD_linkedAppsJSON"] = linkedJSON as CKRecordValue
                        }
                        rec["CD_unlockMode"] = scheduleConfig.unlockMode.rawValue as CKRecordValue
                        #if DEBUG
                        let names = enrichedLinkedApps.compactMap { $0.displayName }.joined(separator: ", ")
                        print("[CloudKitSyncService]   \(config.displayName ?? "?") - added \(enrichedLinkedApps.count) linked apps: \(names) (\(scheduleConfig.unlockMode.rawValue))")
                        #endif
                    }
                }

                // Phase 2: sync the schedule version history alongside the current
                // config. Parent device uses these to compute the kid's bank pinned to
                // each day's historical ratio. Additive field — old clients ignore it.
                if let logicalID = config.logicalID,
                   let history = AppScheduleService.shared.versions[logicalID],
                   !history.isEmpty,
                   let versionsJSON = encodeToJSON(history) {
                    rec["CD_scheduleVersionsJSON"] = versionsJSON as CKRecordValue
                    #if DEBUG
                    print("[CloudKitSyncService]   \(config.displayName ?? "?") - added \(history.count) schedule version(s)")
                    #endif
                }

                // Encode streak settings if enabled
                if let streakSettings = scheduleConfig.streakSettings {
                    if let streakJSON = encodeToJSON(streakSettings) {
                        rec["CD_streakSettingsJSON"] = streakJSON as CKRecordValue
                        #if DEBUG
                        print("[CloudKitSyncService]   \(config.displayName ?? "?") - added streak settings (enabled: \(streakSettings.isEnabled))")
                        #endif
                    }
                }

                // Add quick-access display fields for parent dashboard
                rec["CD_dailyLimitSummary"] = scheduleConfig.dailyLimits.displaySummary as CKRecordValue
                rec["CD_timeWindowSummary"] = scheduleConfig.todayTimeWindow.displayString as CKRecordValue
            }

            toSave.append(rec)
        }

        #if DEBUG
        print("[CloudKitSyncService] Prepared \(toSave.count) AppConfigurations: \(createdCount) new, \(updatedCount) updates")
        #endif

        if toSave.isEmpty && duplicatesToDelete.isEmpty { return }

        // CloudKit has a limit of 400 items per request
        // Batch deletes first, then save
        let batchSize = 350  // Leave room for saves

        // Delete in batches
        if !duplicatesToDelete.isEmpty {
            var deletedCount = 0
            for batchStart in stride(from: 0, to: duplicatesToDelete.count, by: batchSize) {
                let batchEnd = min(batchStart + batchSize, duplicatesToDelete.count)
                let batch = Array(duplicatesToDelete[batchStart..<batchEnd])

                let (_, _) = try await sharedDB.modifyRecords(saving: [], deleting: batch)
                deletedCount += batch.count

                #if DEBUG
                print("[CloudKitSyncService] 🗑️ Deleted batch \(batchStart/batchSize + 1): \(batch.count) records (\(deletedCount)/\(duplicatesToDelete.count))")
                #endif
            }
        }

        // Save in batches
        var savedCount = 0
        if !toSave.isEmpty {
            for batchStart in stride(from: 0, to: toSave.count, by: batchSize) {
                let batchEnd = min(batchStart + batchSize, toSave.count)
                let batch = Array(toSave[batchStart..<batchEnd])

                let (savedRecords, _) = try await sharedDB.modifyRecords(saving: batch, deleting: [])
                savedCount += savedRecords.count
            }
        }

        #if DEBUG
        print("[CloudKitSyncService] ✅ Successfully uploaded \(savedCount) full AppConfigurations to parent's zone")
        if !duplicatesToDelete.isEmpty {
            print("[CloudKitSyncService] 🗑️ Deleted \(duplicatesToDelete.count) duplicate/orphan records total")
        }
        #endif
    }

    /// Delete an app configuration record directly from CloudKit by logicalID
    /// Called when an app is removed from the child device to ensure it's deleted from CloudKit
    func deleteAppConfigurationFromCloudKit(logicalID: String) async throws {
        #if DEBUG
        print("[CloudKitSyncService] 🗑️ Deleting AppConfiguration from CloudKit for logicalID: \(logicalID)")
        #endif

        // Get share context from multi-parent storage (or legacy keys)
        guard let zoneInfo = getParentZoneInfo() else {
            #if DEBUG
            print("[CloudKitSyncService] ❌ Missing share context - device may not be paired")
            #endif
            return
        }

        let zoneID = CKRecordZone.ID(zoneName: zoneInfo.zoneName, ownerName: zoneInfo.zoneOwner)
        let sharedDB = container.sharedCloudDatabase

        // Query for records with this logicalID
        let predicate = NSPredicate(format: "CD_logicalID == %@", logicalID)
        let query = CKQuery(recordType: "CD_AppConfiguration", predicate: predicate)

        do {
            let (results, _) = try await sharedDB.records(matching: query, inZoneWith: zoneID)

            var recordIDsToDelete: [CKRecord.ID] = []
            for (_, result) in results {
                if case .success(let record) = result {
                    recordIDsToDelete.append(record.recordID)
                    #if DEBUG
                    let name = record["CD_displayName"] as? String ?? "Unknown"
                    print("[CloudKitSyncService] 🗑️ Found CloudKit record to delete: '\(name)' (recordID: \(record.recordID.recordName))")
                    #endif
                }
            }

            if !recordIDsToDelete.isEmpty {
                let (_, _) = try await sharedDB.modifyRecords(saving: [], deleting: recordIDsToDelete)
                #if DEBUG
                print("[CloudKitSyncService] ✅ Deleted \(recordIDsToDelete.count) CloudKit record(s) for logicalID: \(logicalID)")
                #endif
            } else {
                #if DEBUG
                print("[CloudKitSyncService] ℹ️ No CloudKit records found to delete for logicalID: \(logicalID)")
                #endif
            }
        } catch {
            #if DEBUG
            print("[CloudKitSyncService] ⚠️ Error querying/deleting CloudKit records: \(error.localizedDescription)")
            #endif
            throw error
        }
    }

    // MARK: - Shield State Sync

    /// Upload shield states to parent's shared zone
    /// This allows parent to see which reward apps are currently blocked/unlocked
    func uploadShieldStatesToParent() async throws {
        #if DEBUG
        print("[CloudKitSyncService] ===== Uploading Shield States To Parent's Zone =====")
        #endif

        let deviceID = DeviceModeManager.shared.deviceID

        // Read shield states from app group UserDefaults
        guard let defaults = UserDefaults(suiteName: "group.com.screentimerewards.shared"),
              let data = defaults.data(forKey: ExtensionShieldStates.userDefaultsKey),
              let shieldStates = try? JSONDecoder().decode(ExtensionShieldStates.self, from: data) else {
            #if DEBUG
            print("[CloudKitSyncService] No shield states found in app group")
            #endif
            return
        }

        guard !shieldStates.states.isEmpty else {
            #if DEBUG
            print("[CloudKitSyncService] Shield states dictionary is empty")
            #endif
            return
        }

        #if DEBUG
        print("[CloudKitSyncService] Found \(shieldStates.states.count) shield states to sync")
        #endif

        // Get share context from multi-parent storage (or legacy keys)
        guard let zoneInfo = getParentZoneInfo() else {
            #if DEBUG
            print("[CloudKitSyncService] ❌ Missing share context - device may not be paired")
            #endif
            return
        }

        let zoneID = CKRecordZone.ID(zoneName: zoneInfo.zoneName, ownerName: zoneInfo.zoneOwner)
        let rootID = CKRecord.ID(recordName: zoneInfo.rootRecordName, zoneID: zoneID)
        let sharedDB = container.sharedCloudDatabase

        // Query existing shield state records for upsert
        var existingByLogicalID: [String: CKRecord] = [:]
        do {
            let predicate = NSPredicate(format: "CD_deviceID == %@", deviceID)
            let query = CKQuery(recordType: "CD_ShieldState", predicate: predicate)
            let (matches, _) = try await sharedDB.records(matching: query, inZoneWith: zoneID)
            for (_, result) in matches {
                if case .success(let record) = result,
                   let logicalID = record["CD_rewardAppLogicalID"] as? String {
                    existingByLogicalID[logicalID] = record
                }
            }
            #if DEBUG
            print("[CloudKitSyncService] Found \(existingByLogicalID.count) existing shield states in CloudKit")
            #endif
        } catch {
            #if DEBUG
            print("[CloudKitSyncService] ⚠️ Could not query existing shield states: \(error.localizedDescription)")
            #endif
        }

        var toSave: [CKRecord] = []
        var updatedCount = 0
        var createdCount = 0

        for (logicalID, state) in shieldStates.states {
            let rec: CKRecord
            if let existing = existingByLogicalID[logicalID] {
                rec = existing
                updatedCount += 1
            } else {
                let recID = CKRecord.ID(recordName: "SS-\(UUID().uuidString)", zoneID: zoneID)
                rec = CKRecord(recordType: "CD_ShieldState", recordID: recID)
                rec.parent = CKRecord.Reference(recordID: rootID, action: .none)
                createdCount += 1
            }

            rec["CD_rewardAppLogicalID"] = logicalID as CKRecordValue
            rec["CD_deviceID"] = deviceID as CKRecordValue
            rec["CD_isUnlocked"] = state.isUnlocked as CKRecordValue
            rec["CD_unlockedAt"] = state.unlockedAt as CKRecordValue?
            rec["CD_reason"] = state.reason as CKRecordValue
            rec["CD_syncTimestamp"] = Date() as CKRecordValue

            // Look up display name for the reward app
            if let displayName = ScreenTimeService.shared.getDisplayName(for: logicalID) {
                rec["CD_rewardAppDisplayName"] = displayName as CKRecordValue
            }

            toSave.append(rec)
        }

        #if DEBUG
        print("[CloudKitSyncService] Prepared \(toSave.count) shield states: \(createdCount) new, \(updatedCount) updates")
        #endif

        if toSave.isEmpty { return }

        let (savedRecords, _) = try await sharedDB.modifyRecords(saving: toSave, deleting: [])

        #if DEBUG
        print("[CloudKitSyncService] ✅ Successfully uploaded \(savedRecords.count) shield states to parent's zone")
        #endif
    }

    /// Fetch child's shield states from CloudKit
    /// Returns a dictionary of logicalID -> ShieldStateDTO
    func fetchChildShieldStates(deviceID: String, zoneID: String? = nil, zoneOwner: String? = nil) async throws -> [String: ShieldStateDTO] {
        #if DEBUG
        print("[CloudKitSyncService] ===== Fetching Child Shield States =====")
        print("[CloudKitSyncService] Device ID: \(deviceID)")
        if let zoneID = zoneID {
            print("[CloudKitSyncService] Zone-specific query: \(zoneID)")
        }
        #endif

        let db = container.privateCloudDatabase
        var results: [String: ShieldStateDTO] = [:]

        // If zone info provided, query ONLY that specific zone (optimization + correctness)
        if let zoneName = zoneID, let ownerName = zoneOwner {
            // Skip the zone-specific attempt if we've already learned this
            // session that CD_ShieldState doesn't exist in this zone — avoids
            // a wasted CK round-trip on every refresh.
            if Self.shouldSkipZone(zoneName, recordType: "CD_ShieldState") {
                #if DEBUG
                print("[CloudKitSyncService] Skipping zone-specific fetch (schema-miss cached this session)")
                #endif
                return results
            }

            let specificZoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: ownerName)

            #if DEBUG
            print("[CloudKitSyncService] Using zone-specific fetch: \(zoneName)")
            #endif

            do {
                let predicate = NSPredicate(format: "CD_deviceID == %@", deviceID)
                let query = CKQuery(recordType: "CD_ShieldState", predicate: predicate)
                let (matches, _) = try await db.records(matching: query, inZoneWith: specificZoneID)

                #if DEBUG
                print("[CloudKitSyncService] Zone \(zoneName): found \(matches.count) shield state records")
                #endif

                for (_, res) in matches {
                    if case .success(let record) = res {
                        let dto = ShieldStateDTO(from: record)
                        results[dto.rewardAppLogicalID] = dto

                        #if DEBUG
                        print("[CloudKitSyncService]   - \(dto.rewardAppDisplayName ?? dto.rewardAppLogicalID): \(dto.isUnlocked ? "UNLOCKED" : "BLOCKED")")
                        #endif
                    }
                }

                #if DEBUG
                print("[CloudKitSyncService] ✅ Zone-specific fetch returned \(results.count) shield states")
                #endif
                return results

            } catch {
                let msg = error.localizedDescription
                // "Did not find record type" means CD_ShieldState doesn't exist
                // in the CloudKit schema at all — falling back to 33 other
                // zones produces 33 identical failures and burns CK rate-limit
                // budget for the rest of the session. Short-circuit instead.
                if msg.localizedCaseInsensitiveContains("Did not find record type") {
                    Self.recordSchemaMiss(zone: zoneName, recordType: "CD_ShieldState")
                    #if DEBUG
                    print("[CloudKitSyncService] ⚠️ CD_ShieldState record type doesn't exist — returning empty (will skip future zone-specific attempts this session)")
                    #endif
                    return results
                }
                #if DEBUG
                print("[CloudKitSyncService] ⚠️ Zone-specific fetch failed, falling back to all zones: \(msg)")
                #endif
                // Fall through to all-zone search for non-schema errors
            }
        }

        // Fallback: Enumerate all zones
        let zones = try await db.allRecordZones()
        #if DEBUG
        print("[CloudKitSyncService] Falling back to all-zone search. Found \(zones.count) zones")
        #endif

        for zone in zones {
            if zone.zoneID.zoneName == CKRecordZone.default().zoneID.zoneName {
                continue
            }

            // Skip zones that already returned "Did not find record type" this
            // session — prevents the 25-zone cascade from triggering CK rate-limit.
            if Self.shouldSkipZone(zone.zoneID.zoneName, recordType: "CD_ShieldState") {
                continue
            }

            do {
                let predicate = NSPredicate(format: "CD_deviceID == %@", deviceID)
                let query = CKQuery(recordType: "CD_ShieldState", predicate: predicate)
                let (matches, _) = try await db.records(matching: query, inZoneWith: zone.zoneID)

                #if DEBUG
                print("[CloudKitSyncService] Zone \(zone.zoneID.zoneName): found \(matches.count) shield state records")
                #endif

                for (_, res) in matches {
                    if case .success(let record) = res {
                        let dto = ShieldStateDTO(from: record)
                        results[dto.rewardAppLogicalID] = dto

                        #if DEBUG
                        print("[CloudKitSyncService]   - \(dto.rewardAppDisplayName ?? dto.rewardAppLogicalID): \(dto.isUnlocked ? "UNLOCKED" : "BLOCKED")")
                        #endif
                    }
                }
            } catch {
                // Cache the schema-miss so subsequent fetches in this session skip this zone.
                if error.localizedDescription.contains("Did not find record type") {
                    Self.recordSchemaMiss(zone: zone.zoneID.zoneName, recordType: "CD_ShieldState")
                }
                #if DEBUG
                print("[CloudKitSyncService] ⚠️ Error querying zone \(zone.zoneID.zoneName): \(error.localizedDescription)")
                #endif
            }
        }

        #if DEBUG
        print("[CloudKitSyncService] ✅ Fetched \(results.count) shield states")
        #endif

        return results
    }

    // MARK: - JSON Encoding Helpers

    /// Encode any Encodable type to JSON string
    private func encodeToJSON<T: Encodable>(_ value: T) -> String? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Decode JSON string to any Decodable type
    private func decodeFromJSON<T: Decodable>(_ json: String, as type: T.Type) -> T? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    /// Fetch child's app configurations from CloudKit
    /// Enumerates all zones (including shared zones) to find child's records
    func fetchChildAppConfigurations(deviceID: String, zoneID: String? = nil, zoneOwner: String? = nil) async throws -> [AppConfiguration] {
        #if DEBUG
        print("[CloudKitSyncService] ===== Fetching Child App Configurations =====")
        print("[CloudKitSyncService] Device ID: \(deviceID)")
        if let zoneID = zoneID {
            print("[CloudKitSyncService] Zone-specific query: \(zoneID)")
        }
        #endif

        let db = container.privateCloudDatabase
        var results: [AppConfiguration] = []
        let context = persistenceController.container.viewContext

        // If zone info provided, query ONLY that specific zone (optimization + correctness)
        if let zoneName = zoneID, let ownerName = zoneOwner {
            let specificZoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: ownerName)

            #if DEBUG
            print("[CloudKitSyncService] Using zone-specific fetch: \(zoneName)")
            #endif

            do {
                let predicate = NSPredicate(format: "CD_deviceID == %@", deviceID)
                let query = CKQuery(recordType: "CD_AppConfiguration", predicate: predicate)
                let (matches, _) = try await db.records(matching: query, inZoneWith: specificZoneID)

                #if DEBUG
                print("[CloudKitSyncService] Zone \(zoneName): found \(matches.count) records")
                #endif

                for (_, res) in matches {
                    if case .success(let r) = res {
                        let entity = NSEntityDescription.entity(forEntityName: "AppConfiguration", in: context)!
                        let config = AppConfiguration(entity: entity, insertInto: nil)
                        config.logicalID = r["CD_logicalID"] as? String
                        config.deviceID = r["CD_deviceID"] as? String
                        config.displayName = r["CD_displayName"] as? String
                        config.iconURL = r["CD_iconURL"] as? String  // FIX: Read iconURL from CloudKit
                        config.category = r["CD_category"] as? String
                        config.pointsPerMinute = Int16(r["CD_pointsPerMinute"] as? Int ?? 1)
                        config.isEnabled = r["CD_isEnabled"] as? Bool ?? true
                        config.tokenHash = r["CD_tokenHash"] as? String
                        config.lastModified = r["CD_lastModified"] as? Date
                        results.append(config)
                    }
                }

                // FIX: Deduplicate by displayName, keeping record with iconURL or newest
                let dedupedResults = deduplicateAppConfigs(results)

                #if DEBUG
                print("[CloudKitSyncService] ✅ Zone-specific fetch returned \(dedupedResults.count) configs (after dedup from \(results.count))")
                for config in dedupedResults {
                    print("[CloudKitSyncService]   - \(config.displayName ?? "?") (\(config.category ?? "?")) iconURL: \(config.iconURL ?? "nil")")
                }
                #endif
                return dedupedResults

            } catch {
                #if DEBUG
                print("[CloudKitSyncService] ⚠️ Zone-specific fetch failed, falling back to all zones: \(error.localizedDescription)")
                #endif
                // Fall through to all-zone search
            }
        }

        // Fallback: Enumerate all zones - shared zones appear in parent's private database
        let zones = try await db.allRecordZones()
        #if DEBUG
        print("[CloudKitSyncService] Falling back to all-zone search. Found \(zones.count) zones")
        for zone in zones {
            print("[CloudKitSyncService]   Zone: \(zone.zoneID.zoneName) (owner: \(zone.zoneID.ownerName))")
        }
        #endif

        for zone in zones {
            // Skip the default zone - shared records are in custom zones
            if zone.zoneID.zoneName == CKRecordZone.default().zoneID.zoneName {
                #if DEBUG
                print("[CloudKitSyncService] Skipping default zone")
                #endif
                continue
            }

            do {
                let predicate = NSPredicate(format: "CD_deviceID == %@", deviceID)
                let query = CKQuery(recordType: "CD_AppConfiguration", predicate: predicate)
                let (matches, _) = try await db.records(matching: query, inZoneWith: zone.zoneID)

                #if DEBUG
                print("[CloudKitSyncService] Zone \(zone.zoneID.zoneName): found \(matches.count) records")
                #endif

                for (_, res) in matches {
                    if case .success(let r) = res {
                        let entity = NSEntityDescription.entity(forEntityName: "AppConfiguration", in: context)!
                        let config = AppConfiguration(entity: entity, insertInto: nil)
                        config.logicalID = r["CD_logicalID"] as? String
                        config.deviceID = r["CD_deviceID"] as? String
                        config.displayName = r["CD_displayName"] as? String
                        config.iconURL = r["CD_iconURL"] as? String  // FIX: Read iconURL from CloudKit
                        config.category = r["CD_category"] as? String
                        config.pointsPerMinute = Int16(r["CD_pointsPerMinute"] as? Int ?? 1)
                        config.isEnabled = r["CD_isEnabled"] as? Bool ?? true
                        config.tokenHash = r["CD_tokenHash"] as? String
                        config.lastModified = r["CD_lastModified"] as? Date
                        results.append(config)
                    }
                }
            } catch {
                #if DEBUG
                print("[CloudKitSyncService] ⚠️ Error querying zone \(zone.zoneID.zoneName): \(error.localizedDescription)")
                #endif
                // Continue to next zone on error
            }
        }

        // FIX: Deduplicate by displayName, keeping record with iconURL or newest
        let dedupedResults = deduplicateAppConfigs(results)

        #if DEBUG
        print("[CloudKitSyncService] ✅ Fetched \(dedupedResults.count) AppConfigurations for device \(deviceID) (after dedup from \(results.count))")
        for config in dedupedResults {
            print("[CloudKitSyncService]   - \(config.displayName ?? "?") (\(config.category ?? "?")) iconURL: \(config.iconURL ?? "nil")")
        }
        #endif

        return dedupedResults
    }

    /// Fetch child's app configurations with full schedule/goals/streaks data
    /// Returns FullAppConfigDTO objects that include decoded JSON fields
    func fetchChildAppConfigurationsFullDTO(deviceID: String, zoneID: String? = nil, zoneOwner: String? = nil) async throws -> [FullAppConfigDTO] {
        #if DEBUG
        print("[CloudKitSyncService] ===== Fetching Full App Configurations (DTO) =====")
        print("[CloudKitSyncService] Device ID: \(deviceID)")
        if let zoneID = zoneID {
            print("[CloudKitSyncService] Zone-specific query: \(zoneID)")
        }
        #endif

        let db = container.privateCloudDatabase
        var results: [FullAppConfigDTO] = []

        // If zone info provided, query ONLY that specific zone (optimization)
        if let zoneName = zoneID, let ownerName = zoneOwner {
            let specificZoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: ownerName)

            #if DEBUG
            print("[CloudKitSyncService] Using zone-specific fetch: \(zoneName)")
            #endif

            do {
                let predicate = NSPredicate(format: "CD_deviceID == %@", deviceID)
                let query = CKQuery(recordType: "CD_AppConfiguration", predicate: predicate)
                let (matches, _) = try await db.records(matching: query, inZoneWith: specificZoneID)

                #if DEBUG
                print("[CloudKitSyncService] Zone \(zoneName): found \(matches.count) app config records")
                #endif

                for (_, res) in matches {
                    if case .success(let record) = res {
                        let dto = FullAppConfigDTO(from: record)
                        results.append(dto)

                        #if DEBUG
                        print("[CloudKitSyncService]   - \(dto.displayName) (\(dto.category))")
                        #endif
                    }
                }

                // FIX BUG 7: Deduplicate by displayName (same app may have multiple logicalIDs)
                let dedupedResults = deduplicateFullAppConfigs(results)

                #if DEBUG
                print("[CloudKitSyncService] ✅ Zone-specific FullDTO fetch returned \(dedupedResults.count) configs (after dedup from \(results.count))")
                for dto in dedupedResults {
                    print("[CloudKitSyncService]   - \(dto.displayName) (\(dto.category)) iconURL: \(dto.iconURL ?? "nil")")
                }
                #endif
                return dedupedResults

            } catch {
                #if DEBUG
                print("[CloudKitSyncService] ⚠️ Zone-specific fetch failed, falling back to all zones: \(error.localizedDescription)")
                #endif
                // Fall through to all-zone search
            }
        }

        // Fallback: Enumerate all zones - shared zones appear in parent's private database
        let zones = try await db.allRecordZones()
        #if DEBUG
        print("[CloudKitSyncService] Falling back to all-zone search. Found \(zones.count) zones")
        #endif

        for zone in zones {
            // Skip the default zone - shared records are in custom zones
            if zone.zoneID.zoneName == CKRecordZone.default().zoneID.zoneName {
                continue
            }

            do {
                let predicate = NSPredicate(format: "CD_deviceID == %@", deviceID)
                let query = CKQuery(recordType: "CD_AppConfiguration", predicate: predicate)
                let (matches, _) = try await db.records(matching: query, inZoneWith: zone.zoneID)

                #if DEBUG
                print("[CloudKitSyncService] Zone \(zone.zoneID.zoneName): found \(matches.count) app config records")
                #endif

                for (_, res) in matches {
                    if case .success(let record) = res {
                        let dto = FullAppConfigDTO(from: record)
                        results.append(dto)

                        #if DEBUG
                        print("[CloudKitSyncService]   - \(dto.displayName) (\(dto.category))")
                        if let schedule = dto.scheduleConfig {
                            print("[CloudKitSyncService]       Limits: \(schedule.dailyLimits.displaySummary)")
                            print("[CloudKitSyncService]       Window: \(schedule.todayTimeWindow.displayString)")
                        }
                        if !dto.linkedLearningApps.isEmpty {
                            print("[CloudKitSyncService]       Linked apps: \(dto.linkedLearningApps.count) (\(dto.unlockMode.displayName))")
                        }
                        if let streak = dto.streakSettings, streak.isEnabled {
                            print("[CloudKitSyncService]       Streak: \(streak.bonusValue)% bonus")
                        }
                        #endif
                    }
                }
            } catch {
                #if DEBUG
                print("[CloudKitSyncService] ⚠️ Error querying zone \(zone.zoneID.zoneName): \(error.localizedDescription)")
                #endif
                // Continue to next zone on error
            }
        }

        // FIX BUG 7: Deduplicate by displayName (same app may have multiple logicalIDs)
        // This also handles duplicates from old pairings in multiple zones
        let dedupedResults = deduplicateFullAppConfigs(results)

        #if DEBUG
        print("[CloudKitSyncService] ✅ Fallback FullDTO fetch returned \(dedupedResults.count) configs (after dedup from \(results.count))")
        for dto in dedupedResults {
            print("[CloudKitSyncService]   - \(dto.displayName) (\(dto.category)) iconURL: \(dto.iconURL ?? "nil")")
        }
        #endif

        return dedupedResults
    }
    // === END APP CONFIGURATION SYNC ===

    // === TASK 8 IMPLEMENTATION ===
    /// Fetch child usage data from parent's shared zones using CloudKit
    /// Enumerates all zones (including shared zones) to find child's records
    func fetchChildUsageDataFromCloudKit(deviceID: String, dateRange: DateInterval, zoneID: String? = nil, zoneOwner: String? = nil) async throws -> [UsageRecord] {
        #if DEBUG
        print("[CloudKitSyncService] ===== Fetching Child Usage Data From CloudKit =====")
        print("[CloudKitSyncService] Device ID: \(deviceID)")
        print("[CloudKitSyncService] Date Range: \(dateRange.start) to \(dateRange.end)")
        if let zoneID = zoneID {
            print("[CloudKitSyncService] Zone-specific query: \(zoneID)")
        }
        #endif

        let db = container.privateCloudDatabase
        var results: [UsageRecord] = []

        // If zone info provided, query ONLY that specific zone (optimization + correctness)
        if let zoneName = zoneID, let ownerName = zoneOwner {
            let specificZoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: ownerName)

            #if DEBUG
            print("[CloudKitSyncService] Using zone-specific fetch: \(zoneName)")
            #endif

            do {
                let predicate = NSPredicate(
                    format: "CD_deviceID == %@ AND CD_sessionStart >= %@ AND CD_sessionStart <= %@",
                    deviceID, dateRange.start as NSDate, dateRange.end as NSDate
                )
                let query = CKQuery(recordType: "CD_UsageRecord", predicate: predicate)
                let (matches, _) = try await db.records(matching: query, inZoneWith: specificZoneID)

                #if DEBUG
                print("[CloudKitSyncService] Zone \(zoneName): found \(matches.count) usage records")
                #endif

                results = mapUsageMatchResults(matches)

                #if DEBUG
                print("[CloudKitSyncService] ✅ Zone-specific fetch returned \(results.count) records")
                for record in results {
                    print("[CloudKitSyncService]   Record: \(record.logicalID ?? "nil") | Category: \(record.category ?? "nil") | Time: \(record.totalSeconds)s | Points: \(record.earnedPoints)")
                }
                #endif
                return results

            } catch let ckErr as CKError {
                // Handle schema not ready - try fallback
                let msg = ckErr.localizedDescription
                if ckErr.code == .invalidArguments ||
                   msg.localizedCaseInsensitiveContains("Unknown field") ||
                   msg.localizedCaseInsensitiveContains("not marked queryable") {
                    #if DEBUG
                    print("[CloudKitSyncService] ⚠️ Schema not ready for zone \(zoneName). Trying fallback...")
                    #endif

                    // Fallback: fetch records in zone and filter client-side (capped to prevent memory spikes)
                    let fallbackPredicate = NSPredicate(value: true)
                    let fallbackQuery = CKQuery(recordType: "CD_UsageRecord", predicate: fallbackPredicate)
                    let (matches, _) = try await db.records(matching: fallbackQuery, inZoneWith: specificZoneID, resultsLimit: 200)
                    let all = mapUsageMatchResults(matches)
                    results = all.filter { rec in
                        guard let did = rec.deviceID,
                              let start = rec.sessionStart
                        else { return false }
                        return did == deviceID && start >= dateRange.start && start <= dateRange.end
                    }

                    #if DEBUG
                    print("[CloudKitSyncService] ✅ Fallback zone-specific fetch returned \(results.count) records")
                    #endif
                    return results
                } else {
                    #if DEBUG
                    print("[CloudKitSyncService] ⚠️ Zone-specific fetch failed, falling back to all zones: \(ckErr.localizedDescription)")
                    #endif
                    // Fall through to all-zone search
                }
            } catch {
                #if DEBUG
                print("[CloudKitSyncService] ⚠️ Zone-specific fetch failed, falling back to all zones: \(error.localizedDescription)")
                #endif
                // Fall through to all-zone search
            }
        }

        // Fallback: Enumerate all zones - shared zones appear in parent's private database
        let zones = try await db.allRecordZones()
        #if DEBUG
        print("[CloudKitSyncService] Falling back to all-zone search. Found \(zones.count) zones")
        #endif

        for zone in zones {
            // Skip the default zone - shared records are in custom zones
            if zone.zoneID.zoneName == CKRecordZone.default().zoneID.zoneName {
                continue
            }

            do {
                let predicate = NSPredicate(
                    format: "CD_deviceID == %@ AND CD_sessionStart >= %@ AND CD_sessionStart <= %@",
                    deviceID, dateRange.start as NSDate, dateRange.end as NSDate
                )
                let query = CKQuery(recordType: "CD_UsageRecord", predicate: predicate)
                let (matches, _) = try await db.records(matching: query, inZoneWith: zone.zoneID)

                #if DEBUG
                print("[CloudKitSyncService] Zone \(zone.zoneID.zoneName): found \(matches.count) usage records")
                #endif

                let zoneRecords = mapUsageMatchResults(matches)
                results.append(contentsOf: zoneRecords)
            } catch let ckErr as CKError {
                // Fallback for schema not ready or non-queryable fields
                let msg = ckErr.localizedDescription
                if ckErr.code == .invalidArguments ||
                   msg.localizedCaseInsensitiveContains("Unknown field") ||
                   msg.localizedCaseInsensitiveContains("not marked queryable") {
                    #if DEBUG
                    print("[CloudKitSyncService] ⚠️ Schema not ready for zone \(zone.zoneID.zoneName). Trying fallback...")
                    #endif

                    // Fallback: fetch records in zone and filter client-side (capped to prevent memory spikes)
                    let fallbackPredicate = NSPredicate(value: true)
                    let fallbackQuery = CKQuery(recordType: "CD_UsageRecord", predicate: fallbackPredicate)
                    let (matches, _) = try await db.records(matching: fallbackQuery, inZoneWith: zone.zoneID, resultsLimit: 200)
                    let all = mapUsageMatchResults(matches)
                    let filtered = all.filter { rec in
                        guard let did = rec.deviceID,
                              let start = rec.sessionStart
                        else { return false }
                        return did == deviceID && start >= dateRange.start && start <= dateRange.end
                    }
                    results.append(contentsOf: filtered)
                } else {
                    #if DEBUG
                    print("[CloudKitSyncService] ⚠️ Error querying zone \(zone.zoneID.zoneName): \(ckErr.localizedDescription)")
                    #endif
                    // Continue to next zone on non-schema errors
                }
            } catch {
                #if DEBUG
                print("[CloudKitSyncService] ⚠️ Error querying zone \(zone.zoneID.zoneName): \(error.localizedDescription)")
                #endif
                // Continue to next zone on error
            }
        }

        #if DEBUG
        print("[CloudKitSyncService] ✅ Found \(results.count) total usage records")
        for record in results {
            print("[CloudKitSyncService]   Record: \(record.logicalID ?? "nil") | Category: \(record.category ?? "nil") | Time: \(record.totalSeconds)s | Points: \(record.earnedPoints)")
        }
        #endif

        return results
    }
    
    private func mapUsageMatchResults<S>(_ matches: S) -> [UsageRecord]
    where S: Sequence, S.Element == (CKRecord.ID, Result<CKRecord, any Error>) {
        var results: [UsageRecord] = []
        for (_, res) in matches {
            if case .success(let r) = res {
                let entity = NSEntityDescription.entity(forEntityName: "UsageRecord", in: persistenceController.container.viewContext)!
                let u = UsageRecord(entity: entity, insertInto: nil)
                u.recordID = r.recordID.recordName
                u.deviceID = r["CD_deviceID"] as? String
                u.logicalID = r["CD_logicalID"] as? String
                u.displayName = r["CD_displayName"] as? String
                u.sessionStart = r["CD_sessionStart"] as? Date
                u.sessionEnd = r["CD_sessionEnd"] as? Date
                if let secs = r["CD_totalSeconds"] as? Int { u.totalSeconds = Int32(secs) }
                if let pts = r["CD_earnedPoints"] as? Int { u.earnedPoints = Int32(pts) }
                u.category = r["CD_category"] as? String
                u.syncTimestamp = r["CD_syncTimestamp"] as? Date
                results.append(u)
            }
        }
        return results
    }
    // === END TASK 8 IMPLEMENTATION ===

    // MARK: - Helper Methods

    /// Deduplicate AppConfiguration array by displayName
    /// Keeps the record with iconURL (preferred) or the newest record if multiple exist
    private func deduplicateAppConfigs(_ configs: [AppConfiguration]) -> [AppConfiguration] {
        var byDisplayName: [String: [AppConfiguration]] = [:]

        for config in configs {
            guard let displayName = config.displayName, !displayName.isEmpty else { continue }
            byDisplayName[displayName, default: []].append(config)
        }

        var result: [AppConfiguration] = []

        for (displayName, group) in byDisplayName {
            if group.count == 1 {
                result.append(group[0])
            } else {
                // Multiple records for same displayName - pick the best one
                let sorted = group.sorted { c1, c2 in
                    // Prefer record WITH iconURL
                    let c1HasIcon = c1.iconURL?.isEmpty == false
                    let c2HasIcon = c2.iconURL?.isEmpty == false
                    if c1HasIcon != c2HasIcon {
                        return c1HasIcon
                    }
                    // If both have/don't have icon, prefer newer
                    let c1Date = c1.lastModified ?? Date.distantPast
                    let c2Date = c2.lastModified ?? Date.distantPast
                    return c1Date > c2Date
                }
                if let best = sorted.first {
                    result.append(best)
                    #if DEBUG
                    print("[CloudKitSyncService] Dedup: Kept 1 of \(group.count) records for '\(displayName)' (has icon: \(best.iconURL != nil))")
                    #endif
                }
            }
        }

        return result
    }

    /// Deduplicate FullAppConfigDTO array by displayName
    /// Keeps the record with iconURL (preferred) or the newest record if multiple exist
    private func deduplicateFullAppConfigs(_ configs: [FullAppConfigDTO]) -> [FullAppConfigDTO] {
        var byDisplayName: [String: [FullAppConfigDTO]] = [:]

        for config in configs {
            let displayName = config.displayName
            guard !displayName.isEmpty else { continue }
            byDisplayName[displayName, default: []].append(config)
        }

        var result: [FullAppConfigDTO] = []

        for (displayName, group) in byDisplayName {
            if group.count == 1 {
                result.append(group[0])
            } else {
                // Multiple records for same displayName - pick the best one
                let sorted = group.sorted { c1, c2 in
                    // Prefer record WITH iconURL
                    let c1HasIcon = c1.iconURL?.isEmpty == false
                    let c2HasIcon = c2.iconURL?.isEmpty == false
                    if c1HasIcon != c2HasIcon {
                        return c1HasIcon
                    }
                    // If both have/don't have icon, prefer newer
                    let c1Date = c1.lastModified ?? Date.distantPast
                    let c2Date = c2.lastModified ?? Date.distantPast
                    return c1Date > c2Date
                }
                if let best = sorted.first {
                    result.append(best)
                    #if DEBUG
                    print("[CloudKitSyncService] FullDTO Dedup: Kept 1 of \(group.count) records for '\(displayName)' (has icon: \(best.iconURL != nil))")
                    #endif
                }
            }
        }

        return result
    }

    // MARK: - Common Methods
    func handlePushNotification(userInfo: [AnyHashable: Any]) async {
        print("[CloudKit] Received push notification: \(userInfo)")

        // First, try to handle as a CloudKit database subscription notification
        let handled = await handleCloudKitNotification(userInfo)

        if handled {
            #if DEBUG
            print("[CloudKit] ✅ Handled as CloudKit subscription notification")
            #endif
        } else {
            // Process the notification and trigger any necessary sync operations
            #if DEBUG
            print("[CloudKit] Processing as generic push notification")
            #endif
            await processOfflineQueue()
        }
    }

    func forceSyncNow() async throws {
        // Force a sync operation
        print("[CloudKit] Forcing sync now")
        // In a real implementation, we might trigger a CloudKit sync
        // For now, we'll just process the offline queue
        await processOfflineQueue()
    }

    func processOfflineQueue() async {
        print("[CloudKit] Processing offline queue")
        await offlineQueue.processQueue()
    }

    // MARK: - Conflict Resolution
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
        if let remoteModified = remote.lastModified,
           let localModified = local.lastModified,
           remoteModified > localModified {
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
            if let logicalID = config.logicalID {
                merged[logicalID] = config
            }
        }

        // Merge remote (resolving conflicts)
        for remoteConfig in remote {
            if let logicalID = remoteConfig.logicalID,
               let localConfig = merged[logicalID] {
                merged[logicalID] = resolveConflict(
                    local: localConfig,
                    remote: remoteConfig
                )
            } else if let logicalID = remoteConfig.logicalID {
                merged[logicalID] = remoteConfig
            }
        }

        return Array(merged.values)
    }

    // MARK: - Daily Usage History Sync

    /// Upload daily usage history to parent's shared zone
    /// Syncs last N days of per-app dailyHistory from UsagePersistence
    func uploadDailyUsageHistoryToParent(daysToSync: Int = 30) async throws {
        #if DEBUG
        print("[CloudKitSyncService] ===== Uploading Daily Usage History To Parent's Zone =====")
        #endif

        let deviceID = DeviceModeManager.shared.deviceID

        // Load all apps from UsagePersistence
        let persistence = UsagePersistence()
        let allApps = persistence.loadAllApps()

        guard !allApps.isEmpty else {
            #if DEBUG
            print("[CloudKitSyncService] No apps found in UsagePersistence")
            #endif
            return
        }

        #if DEBUG
        print("[CloudKitSyncService] Found \(allApps.count) apps with usage data")
        #endif

        // Get share context from multi-parent storage (or legacy keys)
        guard let zoneInfo = getParentZoneInfo() else {
            #if DEBUG
            print("[CloudKitSyncService] ❌ Missing share context - device may not be paired")
            #endif
            return
        }

        let zoneID = CKRecordZone.ID(zoneName: zoneInfo.zoneName, ownerName: zoneInfo.zoneOwner)
        let rootID = CKRecord.ID(recordName: zoneInfo.rootRecordName, zoneID: zoneID)
        let sharedDB = container.sharedCloudDatabase

        // Calculate date range
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let cutoffDate = calendar.date(byAdding: .day, value: -daysToSync, to: today)!

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        // Use CKFetchRecordZoneChangesOperation to fetch ALL existing history records
        // This doesn't rely on queryable field indexes
        var allExistingRecords: [CKRecord] = []

        let fetchConfig = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
        fetchConfig.previousServerChangeToken = nil // Fetch all records

        let fetchOperation = CKFetchRecordZoneChangesOperation(recordZoneIDs: [zoneID], configurationsByRecordZoneID: [zoneID: fetchConfig])
        // Default QoS is .background — iOS throttles it heavily under load and
        // the result block can fail to fire entirely, hanging the upload chain.
        fetchOperation.qualityOfService = .userInitiated

        // 60s timeout guard so a stuck fetch doesn't block subsequent uploads.
        // Was 15s but that was too aggressive on busy zones — when the fetch
        // timed out with incomplete results, records that already existed on
        // CloudKit weren't in our dedup set, so the upload took the
        // create-new path and CloudKit rejected with "record to insert
        // already exists." With savePolicy=.allKeys on the save call this
        // is no longer a correctness issue (overwrite wins), but a complete
        // dedup set keeps the upload path clean and lets us correctly
        // distinguish updatedCount from createdCount in logs.
        actor HistoryResumeGuard { var done = false; func tryResume() -> Bool { if done { return false }; done = true; return true } }
        let historyGuard = HistoryResumeGuard()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            fetchOperation.recordWasChangedBlock = { recordID, result in
                if case .success(let record) = result,
                   record.recordType == "CD_DailyUsageHistory" {
                    allExistingRecords.append(record)
                }
            }
            fetchOperation.fetchRecordZoneChangesResultBlock = { _ in
                Task {
                    if await historyGuard.tryResume() { continuation.resume() }
                }
            }
            sharedDB.add(fetchOperation)

            Task {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                if await historyGuard.tryResume() {
                    fetchOperation.cancel()
                    #if DEBUG
                    print("[CloudKitSyncService] ⏱ DailyUsageHistory dedup fetch hit 60s timeout — proceeding with \(allExistingRecords.count) records collected so far")
                    #endif
                    continuation.resume()
                }
            }
        }

        #if DEBUG
        print("[CloudKitSyncService] Fetched \(allExistingRecords.count) DailyUsageHistory records from zone")
        #endif

        // Build lookup by key and detect duplicates
        var existingByKey: [String: CKRecord] = [:]
        var duplicatesToDelete: [CKRecord.ID] = []
        var recordsByKey: [String: [CKRecord]] = [:]

        // Get valid logicalIDs from current apps
        let validLogicalIDs = Set(allApps.keys)

        for record in allExistingRecords {
            guard let logicalID = record["CD_logicalID"] as? String,
                  let date = record["CD_date"] as? Date else { continue }

            let key = "\(logicalID)-\(dateFormatter.string(from: date))"
            recordsByKey[key, default: []].append(record)
        }

        // Deduplicate and detect orphans
        for (key, records) in recordsByKey {
            // Extract logicalID from the record's CD_logicalID field (NOT from the composite key,
            // which contains UUID-date and splitting by "-" breaks UUIDs like EFF1E31D-2C7D-...)
            let logicalID = records.first?["CD_logicalID"] as? String ?? ""

            // Check if this logicalID is still valid (app still tracked)
            if !validLogicalIDs.contains(logicalID) {
                // Orphan - app no longer tracked, delete all records for this logicalID
                for record in records {
                    duplicatesToDelete.append(record.recordID)
                }
                #if DEBUG
                let displayName = records.first?["CD_displayName"] as? String ?? "Unknown"
                print("[CloudKitSyncService] 🗑️ Orphan history found: '\(displayName)' (logicalID: \(logicalID)) - \(records.count) records")
                #endif
                continue
            }

            if records.count > 1 {
                // Multiple records for same key - keep the one with highest seconds
                let sorted = records.sorted { r1, r2 in
                    let s1 = r1["CD_seconds"] as? Int ?? 0
                    let s2 = r2["CD_seconds"] as? Int ?? 0
                    return s1 > s2
                }
                existingByKey[key] = sorted[0]
                for record in sorted.dropFirst() {
                    duplicatesToDelete.append(record.recordID)
                }
                #if DEBUG
                let displayName = sorted[0]["CD_displayName"] as? String ?? "Unknown"
                print("[CloudKitSyncService] 🔄 Deduping history '\(displayName)': keeping 1, deleting \(sorted.count - 1)")
                #endif
            } else if let record = records.first {
                existingByKey[key] = record
            }
        }

        #if DEBUG
        print("[CloudKitSyncService] Found \(existingByKey.count) existing history records after dedup")
        if !duplicatesToDelete.isEmpty {
            print("[CloudKitSyncService] 🗑️ Found \(duplicatesToDelete.count) stale history records to delete")
        }
        #endif

        // Delete orphans and duplicates in batches
        if !duplicatesToDelete.isEmpty {
            let deleteBatchSize = 350
            var deletedTotal = 0

            for batchStart in stride(from: 0, to: duplicatesToDelete.count, by: deleteBatchSize) {
                let batchEnd = min(batchStart + deleteBatchSize, duplicatesToDelete.count)
                let batch = Array(duplicatesToDelete[batchStart..<batchEnd])

                do {
                    let (_, deletedIDs) = try await sharedDB.modifyRecords(saving: [], deleting: batch)
                    deletedTotal += deletedIDs.count
                    #if DEBUG
                    print("[CloudKitSyncService] Deleted batch \(batchStart/deleteBatchSize + 1): \(deletedIDs.count) history records")
                    #endif
                } catch {
                    #if DEBUG
                    print("[CloudKitSyncService] ⚠️ Error deleting history batch: \(error)")
                    #endif
                }
            }

            #if DEBUG
            print("[CloudKitSyncService] ✅ Deleted \(deletedTotal) stale history records total")
            #endif
        }

        var toSave: [CKRecord] = []
        var alreadyAddedKeys: Set<String> = [] // Track to prevent duplicates
        var updatedCount = 0
        var createdCount = 0

        for (logicalID, app) in allApps {
            // Skip uncategorized apps. Use case-insensitive parse so legacy
            // lowercase records ("learning"/"reward") are still uploaded.
            guard let parsedCategory = AppUsage.AppCategory.parse(app.category) else { continue }
            // Always upload canonical capitalized form so the parent never sees
            // a lowercase category in CK records.
            let canonicalCategory = parsedCategory.rawValue

            // Upload historical days from dailyHistory
            for summary in app.dailyHistory where summary.date >= cutoffDate {
                let dateStr = dateFormatter.string(from: summary.date)
                let key = "\(logicalID)-\(dateStr)"

                // Skip if already added (prevents duplicate record error)
                guard !alreadyAddedKeys.contains(key) else { continue }
                alreadyAddedKeys.insert(key)

                let rec: CKRecord
                if let existing = existingByKey[key] {
                    rec = existing
                    updatedCount += 1
                } else {
                    // Use deterministic record ID for upsert
                    let recID = CKRecord.ID(recordName: "DUH-\(deviceID)-\(logicalID)-\(dateStr)", zoneID: zoneID)
                    rec = CKRecord(recordType: "CD_DailyUsageHistory", recordID: recID)
                    rec.parent = CKRecord.Reference(recordID: rootID, action: .none)
                    createdCount += 1
                }

                rec["CD_deviceID"] = deviceID as CKRecordValue
                rec["CD_logicalID"] = logicalID as CKRecordValue
                rec["CD_displayName"] = app.displayName as CKRecordValue
                rec["CD_date"] = summary.date as CKRecordValue
                rec["CD_seconds"] = summary.seconds as CKRecordValue
                rec["CD_category"] = canonicalCategory as CKRecordValue
                if let hourlyData = summary.hourlySeconds {
                    rec["CD_hourlySeconds"] = hourlyData as CKRecordValue
                }
                rec["CD_syncTimestamp"] = Date() as CKRecordValue

                toSave.append(rec)
            }

            // Also upload today's data.
            //
            // 2026-05-23: Upload zero-value records when an existing CloudKit
            // record exists — this lets heal overwrite stale phantom values
            // on parent's CloudKit zone. Without this, an app like Mobile
            // Legends that was phantom-credited then healed to 0 would keep
            // its old phantom value visible to the parent forever, because
            // `todaySeconds > 0` blocked the overwrite.
            //
            // Still skip creating brand-new zero records (apps with no
            // usage history and no usage today) — those would just add noise
            // to CloudKit. Mirrors syncUsageRecordFromExtensionData's
            // relocated SAFEGUARD 2 on the Core Data side.
            let todayDateStr = dateFormatter.string(from: today)
            let todayKey = "\(logicalID)-\(todayDateStr)"
            let hasExistingTodayRecord = existingByKey[todayKey] != nil
            let willUploadToday = app.todaySeconds > 0 || hasExistingTodayRecord
            #if DEBUG
            print("[CloudKitSyncService] 📋 \(app.displayName) (\(logicalID.prefix(8))) today=\(app.todaySeconds)s existingCK=\(hasExistingTodayRecord) inDailyHistory=\(alreadyAddedKeys.contains(todayKey)) → upload=\(willUploadToday && !alreadyAddedKeys.contains(todayKey))")
            #endif
            if willUploadToday {
                let dateStr = todayDateStr
                let key = todayKey

                // Skip if already added from dailyHistory
                guard !alreadyAddedKeys.contains(key) else { continue }
                alreadyAddedKeys.insert(key)

                let rec: CKRecord
                if let existing = existingByKey[key] {
                    rec = existing
                    updatedCount += 1
                } else {
                    let recID = CKRecord.ID(recordName: "DUH-\(deviceID)-\(logicalID)-\(dateStr)", zoneID: zoneID)
                    rec = CKRecord(recordType: "CD_DailyUsageHistory", recordID: recID)
                    rec.parent = CKRecord.Reference(recordID: rootID, action: .none)
                    createdCount += 1
                }

                rec["CD_deviceID"] = deviceID as CKRecordValue
                rec["CD_logicalID"] = logicalID as CKRecordValue
                rec["CD_displayName"] = app.displayName as CKRecordValue
                rec["CD_date"] = today as CKRecordValue
                rec["CD_seconds"] = app.todaySeconds as CKRecordValue
                rec["CD_category"] = canonicalCategory as CKRecordValue
                // Read hourly breakdown directly from extension's UserDefaults (source of truth)
                // This bypasses potentially stale persistence data
                if let extDefaults = UserDefaults(suiteName: "group.com.screentimerewards.shared") {
                    var hourlySecondsFromExtension = Array(repeating: 0, count: 24)
                    for hour in 0..<24 {
                        hourlySecondsFromExtension[hour] = extDefaults.integer(forKey: "ext_usage_\(logicalID)_hourly_\(hour)")
                    }
                    // Only upload if there's actual hourly data
                    if hourlySecondsFromExtension.contains(where: { $0 > 0 }) {
                        rec["CD_hourlySeconds"] = hourlySecondsFromExtension as CKRecordValue
                    }
                }
                rec["CD_syncTimestamp"] = Date() as CKRecordValue

                toSave.append(rec)
            }
        }

        #if DEBUG
        print("[CloudKitSyncService] Prepared \(toSave.count) history records: \(createdCount) new, \(updatedCount) updates")
        #endif

        if toSave.isEmpty { return }

        // CloudKit has a limit of 400 records per batch
        let batchSize = 400
        var savedTotal = 0

        for batch in stride(from: 0, to: toSave.count, by: batchSize) {
            let end = min(batch + batchSize, toSave.count)
            let batchRecords = Array(toSave[batch..<end])

            // 2026-05-23: use .allKeys save policy so records OVERWRITE on
            // collision instead of failing with "record to insert already
            // exists". This is the proper upsert pattern — necessary because
            // the dedup-fetch above can time out (15s) and miss some existing
            // records, causing the code to take the create-new path for records
            // that actually exist on CloudKit. Without .allKeys, those records
            // get silently dropped and the parent never sees the latest value
            // (the May 23 Facebook + TikTok parent-sync bug).
            //
            // .allKeys = save every field in our record, regardless of server
            // state. We are the authoritative source for these daily totals, so
            // overwrite-wins is correct.
            let (savedRecords, _) = try await sharedDB.modifyRecords(
                saving: batchRecords,
                deleting: [],
                savePolicy: .allKeys,
                atomically: false
            )

            #if DEBUG
            // Per-record outcome: savedRecords is a dictionary keyed by record ID,
            // each entry is a Result<CKRecord, Error>. modifyRecords does NOT throw
            // for individual record failures — only transactional errors. So the
            // count includes failures. We need to break it down to see what's
            // actually getting saved vs silently dropped.
            var successCount = 0
            var failureCount = 0
            for (recordID, result) in savedRecords {
                switch result {
                case .success:
                    successCount += 1
                case .failure(let error):
                    failureCount += 1
                    print("[CloudKitSyncService] ❌ Save FAILED for \(recordID.recordName): \(error.localizedDescription)")
                }
            }
            savedTotal += successCount
            print("[CloudKitSyncService] Saved batch \(batch/batchSize + 1): \(successCount) succeeded, \(failureCount) failed (of \(batchRecords.count) attempted)")
            #endif
        }

        #if DEBUG
        print("[CloudKitSyncService] ✅ Successfully uploaded \(savedTotal) daily usage history records to parent's zone")
        #endif

        // Upload daily snapshot with pre-calculated totals
        await uploadDailySnapshotToParent(
            deviceID: deviceID,
            date: today,
            allApps: allApps,
            zoneID: zoneID,
            rootID: rootID,
            sharedDB: sharedDB
        )
    }

    /// Upload daily snapshot with totals to parent's shared zone
    private func uploadDailySnapshotToParent(
        deviceID: String,
        date: Date,
        allApps: [String: UsagePersistence.PersistedApp],
        zoneID: CKRecordZone.ID,
        rootID: CKRecord.ID,
        sharedDB: CKDatabase
    ) async {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateStr = dateFormatter.string(from: date)

        #if DEBUG
        print("[EarnedMinutesDebug] UPLOAD: Using zone=\(zoneID.zoneName), owner=\(zoneID.ownerName)")
        #endif

        // Calculate totals from app data
        var totalLearningSeconds = 0
        var totalRewardSeconds = 0
        var rewardLogicalIDs: [String] = []

        for (logicalID, app) in allApps {
            // Case-insensitive parse so legacy lowercase records still aggregate.
            switch AppUsage.AppCategory.parse(app.category) {
            case .learning:
                totalLearningSeconds += app.todaySeconds
            case .reward:
                totalRewardSeconds += app.todaySeconds
                rewardLogicalIDs.append(logicalID)
            case .none:
                break
            }
        }

        // SOURCE-OF-TRUTH INVARIANT: this block must mirror
        // `AppUsageViewModel.totalEarnedMinutes` (line 156) and
        // `AppUsageViewModel.cumulativeAvailableMinutes` (line 210), which are also
        // mirrored byte-for-byte by `computeEffectivePoolBalance` in
        // DeviceActivityMonitorExtension.swift (the extension's shield gate). When
        // the bank formula changes, ALL FOUR sites update in the same commit.
        // See docs/SMART_THRESHOLD_FILTERING.md "Apr 26–27, 2026 — Pooled Time Bank
        // Shield Gate (Devices A + B)".
        //
        // Build threshold map: learningAppID → lowest minutesRequired across all
        // reward apps that link to it.
        var lowestThresholdPerLearningApp: [String: Int] = [:]
        for (logicalID, _) in allApps {
            if let schedule = AppScheduleService.shared.getSchedule(for: logicalID) {
                for linkedApp in schedule.linkedLearningApps {
                    let learningID = linkedApp.logicalID
                    let threshold = linkedApp.minutesRequired
                    if let existing = lowestThresholdPerLearningApp[learningID] {
                        lowestThresholdPerLearningApp[learningID] = min(existing, threshold)
                    } else {
                        lowestThresholdPerLearningApp[learningID] = threshold
                    }
                }
            }
        }

        // Build learning ratios map identical to `AppUsageViewModel.buildLearningRatioMap()`.
        // Today-pinned via `AppScheduleService.ratio(on:)` so a same-day ratio edit
        // (recorded with effectiveFromDay=tomorrow) doesn't re-price today's
        // uploaded snapshot.
        var learningRatios: [String: Double] = [:]
        for (logicalID, app) in allApps where AppUsage.AppCategory.parse(app.category) == .learning {
            learningRatios[logicalID] = AppScheduleService.shared.ratio(logicalID: logicalID)
        }

        // Apply threshold gate + ratio: only count if usage >= lowestThreshold,
        // then multiply by ratio. Mirrors AppUsageViewModel.totalEarnedMinutes.
        var totalEarnedMinutes = 0
        for (logicalID, app) in allApps where AppUsage.AppCategory.parse(app.category) == .learning {
            guard let lowestThreshold = lowestThresholdPerLearningApp[logicalID] else {
                continue // Not linked to any reward app
            }
            let usageMinutes = app.todaySeconds / 60
            if usageMinutes >= lowestThreshold {
                let ratio = learningRatios[logicalID] ?? 1.0
                totalEarnedMinutes += Int(Double(usageMinutes) * ratio)
            }
            // else: earned 0 for this app (threshold not met)
        }

        #if DEBUG
        print("[EarnedMinutesDebug] UPLOAD: Calculated totalEarnedMinutes = \(totalEarnedMinutes) from \(lowestThresholdPerLearningApp.count) linked learning apps (threshold gate + ratios applied)")
        #endif

        // Calculate cumulative available minutes (rollover + today's remaining).
        // Phase 2: per-day version lookup pins past learning to the ratio active on
        // each historical day. Matches AppUsageViewModel.cumulativeAvailableMinutes
        // and ScreenTimeService.syncBankHistoricalBaselineToExtension.
        let learningLogicalIDs = allApps.filter { AppUsage.AppCategory.parse($0.value.category) == .learning }.map { $0.key }
        let scheduleService = AppScheduleService.shared
        let historicalRemaining = ScreenTimeService.shared.usagePersistence.getHistoricalRemainingMinutes(
            learningIDs: learningLogicalIDs,
            rewardIDs: rewardLogicalIDs,
            ratioForDay: { logicalID, dayKey in
                if let v = scheduleService.versionActive(logicalID: logicalID, on: dayKey) {
                    return v.ratio
                }
                return learningRatios[logicalID] ?? 1.0
            }
        )
        let todayRemaining = totalEarnedMinutes - (totalRewardSeconds / 60)
        let cumulativeAvailableMinutes = max(0, historicalRemaining + todayRemaining)

        #if DEBUG
        print("[EarnedMinutesDebug] UPLOAD: Summary - earned=\(totalEarnedMinutes)m, used=\(totalRewardSeconds/60)m, historical=\(historicalRemaining)m, available=\(cumulativeAvailableMinutes)m")
        print("[CloudKitSyncService] 📊 Daily Snapshot: learning=\(totalLearningSeconds)s, reward=\(totalRewardSeconds)s, earned=\(totalEarnedMinutes)m, available=\(cumulativeAvailableMinutes)m")
        #endif

        // Create or update snapshot record
        let snapshotID = CKRecord.ID(recordName: "DS-\(deviceID)-\(dateStr)", zoneID: zoneID)
        let snapshot = CKRecord(recordType: "CD_DailySnapshot", recordID: snapshotID)
        snapshot.parent = CKRecord.Reference(recordID: rootID, action: .none)
        snapshot["CD_deviceID"] = deviceID as CKRecordValue
        snapshot["CD_date"] = date as CKRecordValue
        snapshot["CD_totalEarnedMinutes"] = totalEarnedMinutes as CKRecordValue
        snapshot["CD_totalLearningSeconds"] = totalLearningSeconds as CKRecordValue
        snapshot["CD_totalRewardSeconds"] = totalRewardSeconds as CKRecordValue
        snapshot["CD_cumulativeAvailableMinutes"] = cumulativeAvailableMinutes as CKRecordValue
        snapshot["CD_syncTimestamp"] = Date() as CKRecordValue

        #if DEBUG
        print("[EarnedMinutesDebug] UPLOAD: Writing to CloudKit - CD_totalEarnedMinutes=\(totalEarnedMinutes), CD_cumulativeAvailableMinutes=\(cumulativeAvailableMinutes)")
        #endif

        do {
            // First, delete any existing stale snapshot to force a clean overwrite
            // This ensures the new calculated value replaces the old buggy one
            #if DEBUG
            print("[EarnedMinutesDebug] UPLOAD: Deleting stale snapshot (if exists) before saving new one...")
            #endif
            do {
                let (_, deleted) = try await sharedDB.modifyRecords(saving: [], deleting: [snapshotID])
                #if DEBUG
                print("[EarnedMinutesDebug] UPLOAD: Deleted \(deleted.count) stale record(s)")
                #endif
            } catch {
                // Ignore error if record doesn't exist - that's fine
                #if DEBUG
                print("[EarnedMinutesDebug] UPLOAD: No existing record to delete (or error): \(error.localizedDescription)")
                #endif
            }

            // Now save the new snapshot with correct values
            let (saved, _) = try await sharedDB.modifyRecords(saving: [snapshot], deleting: [])
            #if DEBUG
            print("[EarnedMinutesDebug] UPLOAD: ✅ CloudKit save SUCCESS - \(saved.count) record")
            print("[CloudKitSyncService] ✅ Daily snapshot uploaded: \(saved.count) record")
            #endif
        } catch {
            #if DEBUG
            print("[EarnedMinutesDebug] UPLOAD: ❌ CloudKit save FAILED - \(error.localizedDescription)")
            print("[CloudKitSyncService] ⚠️ Failed to upload daily snapshot: \(error.localizedDescription)")
            #endif
        }
    }

    // MARK: - Extension Retry Queue Processing

    /// Process pending CloudKit syncs that failed in the extension
    /// The extension queues failed syncs in App Group for the main app to retry
    /// This is a fallback mechanism - the extension's blocking sync should usually succeed
    func processExtensionRetryQueue() async {
        guard let defaults = UserDefaults(suiteName: "group.com.screentimerewards.shared") else {
            return
        }

        let pendingKey = "ext_pending_cloudkit_sync"
        guard let pending = defaults.array(forKey: pendingKey) as? [[String: Any]],
              !pending.isEmpty else {
            return
        }

        #if DEBUG
        print("[CloudKitSyncService] Processing \(pending.count) pending extension syncs")
        #endif

        // Get share context
        guard let zoneInfo = getParentZoneInfo() else {
            #if DEBUG
            print("[CloudKitSyncService] ❌ No parent zone info - cannot process retry queue")
            #endif
            return
        }

        let deviceID = DeviceModeManager.shared.deviceID
        let zoneID = CKRecordZone.ID(zoneName: zoneInfo.zoneName, ownerName: zoneInfo.zoneOwner)
        let rootID = CKRecord.ID(recordName: zoneInfo.rootRecordName, zoneID: zoneID)
        let sharedDB = container.sharedCloudDatabase

        var recordsToSave: [CKRecord] = []

        for entry in pending {
            guard let appID = entry["appID"] as? String,
                  let seconds = entry["seconds"] as? Int,
                  let dateStr = entry["date"] as? String,
                  let hourly = entry["hourly"] as? [Int],
                  let category = entry["category"] as? String,
                  !category.isEmpty,
                  (category == "Learning" || category == "Reward") else {
                continue
            }

            let displayName = entry["displayName"] as? String

            let recordName = "DUH-\(deviceID)-\(appID)-\(dateStr)"
            let recordID = CKRecord.ID(recordName: recordName, zoneID: zoneID)
            let record = CKRecord(recordType: "CD_DailyUsageHistory", recordID: recordID)
            record.parent = CKRecord.Reference(recordID: rootID, action: .none)

            record["CD_deviceID"] = deviceID as CKRecordValue
            record["CD_logicalID"] = appID as CKRecordValue
            record["CD_category"] = category as CKRecordValue
            record["CD_seconds"] = seconds as CKRecordValue
            record["CD_syncTimestamp"] = Date() as CKRecordValue
            record["CD_syncSource"] = "main_app_retry" as CKRecordValue

            // Parse date from string
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            if let date = dateFormatter.date(from: dateStr) {
                record["CD_date"] = date as CKRecordValue
            }

            if let name = displayName, !name.isEmpty {
                record["CD_displayName"] = name as CKRecordValue
            }

            if hourly.contains(where: { $0 > 0 }) {
                record["CD_hourlySeconds"] = hourly as CKRecordValue
            }

            recordsToSave.append(record)
        }

        guard !recordsToSave.isEmpty else {
            defaults.removeObject(forKey: pendingKey)
            return
        }

        do {
            let operation = CKModifyRecordsOperation(recordsToSave: recordsToSave, recordIDsToDelete: nil)
            operation.savePolicy = .changedKeys
            operation.qualityOfService = .userInitiated

            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                operation.modifyRecordsResultBlock = { result in
                    switch result {
                    case .success:
                        continuation.resume()
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
                sharedDB.add(operation)
            }

            // Clear the queue on success
            defaults.removeObject(forKey: pendingKey)

            #if DEBUG
            print("[CloudKitSyncService] ✅ Processed \(recordsToSave.count) pending extension syncs")
            #endif
        } catch {
            #if DEBUG
            print("[CloudKitSyncService] ❌ Failed to process retry queue: \(error.localizedDescription)")
            #endif
        }
    }

    /// Fetch child's daily usage history from CloudKit shared zones
    /// Returns array of DailyUsageHistoryDTO with per-app daily summaries
    func fetchChildDailyUsageHistory(deviceID: String, daysToFetch: Int = 30, zoneID: String? = nil, zoneOwner: String? = nil) async throws -> [DailyUsageHistoryDTO] {
        #if DEBUG
        print("[CloudKitSyncService] ===== Fetching Child Daily Usage History =====")
        print("[CloudKitSyncService] Device ID: \(deviceID)")
        if let zoneID = zoneID {
            print("[CloudKitSyncService] Zone-specific query: \(zoneID)")
        }
        #endif

        let db = container.privateCloudDatabase
        var results: [DailyUsageHistoryDTO] = []

        // Calculate date range
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let startDate = calendar.date(byAdding: .day, value: -daysToFetch, to: today)!

        // If zone info provided, query ONLY that specific zone (optimization + correctness)
        if let zoneName = zoneID, let ownerName = zoneOwner {
            let specificZoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: ownerName)

            #if DEBUG
            print("[CloudKitSyncService] Using zone-specific fetch: \(zoneName)")
            #endif

            do {
                let predicate = NSPredicate(
                    format: "CD_deviceID == %@ AND CD_date >= %@",
                    deviceID, startDate as NSDate
                )
                let query = CKQuery(recordType: "CD_DailyUsageHistory", predicate: predicate)

                // 2026-05-23: paginate via cursor. CloudKit's default page size
                // (~100 records) was silently truncating the fetch — records
                // beyond page 1 (Facebook 2026-05-23, TikTok 2026-05-23 in the
                // logged case) never reached the parent dashboard. Loop until
                // CloudKit returns nil cursor.
                var totalPages = 0
                var matches: [(CKRecord.ID, Result<CKRecord, Error>)] = []
                var cursor: CKQueryOperation.Cursor?
                let pageLimit = CKQueryOperation.maximumResults
                let firstPage = try await db.records(matching: query, inZoneWith: specificZoneID, desiredKeys: nil, resultsLimit: pageLimit)
                matches.append(contentsOf: firstPage.matchResults)
                cursor = firstPage.queryCursor
                totalPages = 1
                while let c = cursor {
                    let nextPage = try await db.records(continuingMatchFrom: c, desiredKeys: nil, resultsLimit: pageLimit)
                    matches.append(contentsOf: nextPage.matchResults)
                    cursor = nextPage.queryCursor
                    totalPages += 1
                }

                #if DEBUG
                print("[CloudKitSyncService] Zone \(zoneName): found \(matches.count) history records across \(totalPages) page(s)")
                #endif

                for (_, res) in matches {
                    if case .success(let record) = res {
                        let dto = DailyUsageHistoryDTO(from: record)
                        results.append(dto)

                        #if DEBUG
                        print("[CloudKitSyncService]   - \(dto.displayName) on \(dto.date): \(dto.seconds)s (\(dto.category))")
                        #endif
                    }
                }

                #if DEBUG
                print("[CloudKitSyncService] ✅ Zone-specific fetch returned \(results.count) history records")
                #endif
                return results

            } catch {
                #if DEBUG
                print("[CloudKitSyncService] ⚠️ Zone-specific fetch failed, falling back to all zones: \(error.localizedDescription)")
                #endif
                // Fall through to all-zone search
            }
        }

        // Fallback: Enumerate all zones (shared zones appear in parent's private database)
        let zones = try await db.allRecordZones()
        #if DEBUG
        print("[CloudKitSyncService] Falling back to all-zone search. Found \(zones.count) zones")
        #endif

        for zone in zones {
            if zone.zoneID.zoneName == CKRecordZone.default().zoneID.zoneName {
                continue
            }

            do {
                let predicate = NSPredicate(
                    format: "CD_deviceID == %@ AND CD_date >= %@",
                    deviceID, startDate as NSDate
                )
                let query = CKQuery(recordType: "CD_DailyUsageHistory", predicate: predicate)
                let (matches, _) = try await db.records(matching: query, inZoneWith: zone.zoneID)

                #if DEBUG
                print("[CloudKitSyncService] Zone \(zone.zoneID.zoneName): found \(matches.count) history records")
                #endif

                for (_, res) in matches {
                    if case .success(let record) = res {
                        let dto = DailyUsageHistoryDTO(from: record)
                        results.append(dto)

                        #if DEBUG
                        print("[CloudKitSyncService]   - \(dto.displayName) on \(dto.date): \(dto.seconds)s (\(dto.category))")
                        #endif
                    }
                }
            } catch {
                #if DEBUG
                print("[CloudKitSyncService] ⚠️ Error querying zone \(zone.zoneID.zoneName): \(error.localizedDescription)")
                #endif
            }
        }

        #if DEBUG
        print("[CloudKitSyncService] ✅ Fetched \(results.count) daily usage history records")
        #endif

        return results
    }

    /// Fetch child's daily snapshot (today's totals) from CloudKit shared zones
    /// Returns the most recent DailySnapshotDTO with pre-calculated earnedMinutes
    func fetchChildDailySnapshot(deviceID: String, zoneID: String? = nil, zoneOwner: String? = nil) async throws -> DailySnapshotDTO? {
        #if DEBUG
        print("[CloudKitSyncService] ===== Fetching Child Daily Snapshot =====")
        print("[CloudKitSyncService] Device ID: \(deviceID)")
        #endif

        let db = container.privateCloudDatabase
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // If zone info provided, query only that specific zone
        if let zoneName = zoneID, let ownerName = zoneOwner {
            let specificZoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: ownerName)

            do {
                let predicate = NSPredicate(
                    format: "CD_deviceID == %@ AND CD_date >= %@",
                    deviceID, today as NSDate
                )
                let query = CKQuery(recordType: "CD_DailySnapshot", predicate: predicate)
                query.sortDescriptors = [NSSortDescriptor(key: "CD_date", ascending: false)]

                let (matches, _) = try await db.records(
                    matching: query,
                    inZoneWith: specificZoneID,
                    desiredKeys: nil,
                    resultsLimit: 1
                )

                for (_, res) in matches {
                    if case .success(let record) = res {
                        let dto = DailySnapshotDTO(from: record)
                        #if DEBUG
                        print("[EarnedMinutesDebug] FETCH: Raw CloudKit record CD_totalEarnedMinutes=\(record["CD_totalEarnedMinutes"] ?? "nil")")
                        print("[EarnedMinutesDebug] FETCH: DTO totalEarnedMinutes=\(dto.totalEarnedMinutes), cumulativeAvailableMinutes=\(dto.cumulativeAvailableMinutes)")
                        print("[CloudKitSyncService] ✅ Fetched daily snapshot: earned=\(dto.totalEarnedMinutes)m, learning=\(dto.totalLearningSeconds)s")
                        #endif
                        return dto
                    }
                }
            } catch {
                #if DEBUG
                print("[CloudKitSyncService] ⚠️ Error fetching snapshot from zone \(zoneName): \(error.localizedDescription)")
                #endif
            }
        } else {
            // Query all shared zones
            let zones = try await db.allRecordZones()
            for zone in zones {
                do {
                    let predicate = NSPredicate(
                        format: "CD_deviceID == %@ AND CD_date >= %@",
                        deviceID, today as NSDate
                    )
                    let query = CKQuery(recordType: "CD_DailySnapshot", predicate: predicate)
                    query.sortDescriptors = [NSSortDescriptor(key: "CD_date", ascending: false)]

                    let (matches, _) = try await db.records(
                        matching: query,
                        inZoneWith: zone.zoneID,
                        desiredKeys: nil,
                        resultsLimit: 1
                    )

                    for (_, res) in matches {
                        if case .success(let record) = res {
                            let dto = DailySnapshotDTO(from: record)
                            #if DEBUG
                            print("[EarnedMinutesDebug] FETCH: Raw CloudKit record CD_totalEarnedMinutes=\(record["CD_totalEarnedMinutes"] ?? "nil")")
                            print("[EarnedMinutesDebug] FETCH: DTO totalEarnedMinutes=\(dto.totalEarnedMinutes), cumulativeAvailableMinutes=\(dto.cumulativeAvailableMinutes)")
                            print("[CloudKitSyncService] ✅ Fetched daily snapshot: earned=\(dto.totalEarnedMinutes)m, learning=\(dto.totalLearningSeconds)s")
                            #endif
                            return dto
                        }
                    }
                } catch {
                    #if DEBUG
                    print("[CloudKitSyncService] ⚠️ Error querying snapshot in zone \(zone.zoneID.zoneName): \(error.localizedDescription)")
                    #endif
                }
            }
        }

        #if DEBUG
        print("[CloudKitSyncService] No daily snapshot found for today")
        #endif
        return nil
    }

    // MARK: - Child Streak Records

    /// Fetch streak records for a child device from CloudKit
    /// Used by parent device to display child's streak progress
    func fetchChildStreakRecords(deviceID: String, zoneID: String? = nil, zoneOwner: String? = nil) async throws -> [StreakRecordDTO] {
        #if DEBUG
        print("[CloudKitSyncService] ===== Fetching Child Streak Records =====")
        print("[CloudKitSyncService] Device ID: \(deviceID)")
        if let zoneID = zoneID {
            print("[CloudKitSyncService] Zone-specific query: \(zoneID)")
        }
        #endif

        let db = container.privateCloudDatabase
        var results: [StreakRecordDTO] = []

        // If zone info provided, query ONLY that specific zone
        if let zoneName = zoneID, let ownerName = zoneOwner {
            let specificZoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: ownerName)

            #if DEBUG
            print("[CloudKitSyncService] Using zone-specific fetch for streaks: \(zoneName)")
            #endif

            do {
                let predicate = NSPredicate(format: "CD_childDeviceID == %@", deviceID)
                let query = CKQuery(recordType: "CD_StreakRecord", predicate: predicate)
                let (matches, _) = try await db.records(matching: query, inZoneWith: specificZoneID)

                #if DEBUG
                print("[CloudKitSyncService] Zone \(zoneName): found \(matches.count) streak records")
                #endif

                for (_, res) in matches {
                    if case .success(let record) = res {
                        let dto = StreakRecordDTO(from: record)
                        results.append(dto)

                        #if DEBUG
                        print("[CloudKitSyncService]   - App \(dto.appLogicalID): current=\(dto.currentStreak), longest=\(dto.longestStreak)")
                        #endif
                    }
                }

                #if DEBUG
                print("[CloudKitSyncService] ✅ Zone-specific fetch returned \(results.count) streak records")
                #endif

                return results
            } catch {
                #if DEBUG
                print("[CloudKitSyncService] ⚠️ Error fetching streaks from zone \(zoneName): \(error.localizedDescription)")
                #endif
                throw error
            }
        }

        // Fallback: search all shared zones
        #if DEBUG
        print("[CloudKitSyncService] Searching all shared zones for streak records...")
        #endif

        let zones = try await db.allRecordZones()
        for zone in zones {
            guard zone.zoneID.zoneName.hasPrefix("share-") else { continue }

            do {
                let predicate = NSPredicate(format: "CD_childDeviceID == %@", deviceID)
                let query = CKQuery(recordType: "CD_StreakRecord", predicate: predicate)
                let (matches, _) = try await db.records(matching: query, inZoneWith: zone.zoneID)

                for (_, res) in matches {
                    if case .success(let record) = res {
                        let dto = StreakRecordDTO(from: record)
                        results.append(dto)

                        #if DEBUG
                        print("[CloudKitSyncService]   - App \(dto.appLogicalID): current=\(dto.currentStreak), longest=\(dto.longestStreak)")
                        #endif
                    }
                }
            } catch {
                #if DEBUG
                print("[CloudKitSyncService] ⚠️ Error querying zone \(zone.zoneID.zoneName): \(error.localizedDescription)")
                #endif
            }
        }

        #if DEBUG
        print("[CloudKitSyncService] ✅ Fetched \(results.count) streak records")
        #endif

        return results
    }

    // MARK: - Parent Notifications

    /// Send a notification to parent device via CloudKit
    /// Creates a ParentNotification record in the parent's shared zone
    func sendParentNotification(_ payload: ParentNotificationPayload) async throws {
        #if DEBUG
        print("[CloudKitSyncService] ===== Sending Parent Notification =====")
        print("[CloudKitSyncService] Type: \(payload.notificationType.rawValue)")
        print("[CloudKitSyncService] Title: \(payload.title)")
        #endif

        let sharedDB = container.sharedCloudDatabase

        // Get share context from multi-parent storage (or legacy keys)
        guard let zoneInfo = getParentZoneInfo() else {
            let error = NSError(domain: "ParentNotification", code: -1,
                              userInfo: [NSLocalizedDescriptionKey: "Missing share context - device may not be paired"])
            #if DEBUG
            print("[CloudKitSyncService] ❌ Cannot send parent notification - no zone info")
            #endif
            throw error
        }

        let zoneID = CKRecordZone.ID(zoneName: zoneInfo.zoneName, ownerName: zoneInfo.zoneOwner)
        let rootID = CKRecord.ID(recordName: zoneInfo.rootRecordName, zoneID: zoneID)

        // Create the notification record
        let record = payload.toCKRecord(zoneID: zoneID, rootID: rootID)

        #if DEBUG
        print("[CloudKitSyncService] Zone: \(zoneInfo.zoneName)")
        print("[CloudKitSyncService] Owner: \(zoneInfo.zoneOwner)")
        print("[CloudKitSyncService] Root: \(zoneInfo.rootRecordName)")
        #endif

        do {
            let (savedRecords, _) = try await sharedDB.modifyRecords(saving: [record], deleting: [])

            #if DEBUG
            print("[CloudKitSyncService] ✅ Parent notification sent: \(savedRecords.count) record(s)")
            #endif
        } catch {
            #if DEBUG
            print("[CloudKitSyncService] ❌ Failed to send parent notification: \(error.localizedDescription)")
            #endif

            // Queue for offline retry
            do {
                try offlineQueue.enqueueOperation(
                    operation: "sendParentNotification",
                    payload: [
                        "notificationID": payload.notificationID,
                        "type": payload.notificationType.rawValue,
                        "title": payload.title,
                        "body": payload.body
                    ]
                )
            } catch {
                #if DEBUG
                print("[CloudKitSyncService] ⚠️ Failed to queue for offline retry: \(error.localizedDescription)")
                #endif
            }

            throw error
        }
    }

    /// Fetch unread parent notifications (for parent device)
    func fetchUnreadParentNotifications(for childDeviceID: String? = nil) async throws -> [ParentNotificationPayload] {
        #if DEBUG
        print("[CloudKitSyncService] ===== Fetching Unread Parent Notifications =====")
        #endif

        let privateDB = container.privateCloudDatabase
        var results: [ParentNotificationPayload] = []

        // Get all child monitoring zones
        let zones = try await getAllChildMonitoringZones()

        for zone in zones {
            do {
                var predicate: NSPredicate
                if let childID = childDeviceID {
                    predicate = NSPredicate(format: "CD_childDeviceID == %@ AND CD_isRead == %@", childID, NSNumber(value: false))
                } else {
                    predicate = NSPredicate(format: "CD_isRead == %@", NSNumber(value: false))
                }

                let query = CKQuery(recordType: "ParentNotification", predicate: predicate)
                query.sortDescriptors = [NSSortDescriptor(key: "CD_timestamp", ascending: false)]

                let (matches, _) = try await privateDB.records(matching: query, inZoneWith: zone.zoneID)

                for (_, result) in matches {
                    if case .success(let record) = result,
                       let payload = ParentNotificationPayload.fromCKRecord(record) {
                        results.append(payload)
                    }
                }
            } catch {
                #if DEBUG
                print("[CloudKitSyncService] ⚠️ Error fetching notifications from zone \(zone.zoneID.zoneName): \(error.localizedDescription)")
                #endif
            }
        }

        #if DEBUG
        print("[CloudKitSyncService] ✅ Found \(results.count) unread notifications")
        #endif

        return results
    }

    /// Mark a parent notification as read
    func markParentNotificationAsRead(notificationID: String) async throws {
        #if DEBUG
        print("[CloudKitSyncService] Marking notification as read: \(notificationID)")
        #endif

        let privateDB = container.privateCloudDatabase
        let zones = try await getAllChildMonitoringZones()

        for zone in zones {
            do {
                let predicate = NSPredicate(format: "CD_notificationID == %@", notificationID)
                let query = CKQuery(recordType: "ParentNotification", predicate: predicate)
                let (matches, _) = try await privateDB.records(matching: query, inZoneWith: zone.zoneID)

                for (recordID, result) in matches {
                    if case .success(var record) = result {
                        record["CD_isRead"] = true as CKRecordValue
                        try await privateDB.modifyRecords(saving: [record], deleting: [])

                        #if DEBUG
                        print("[CloudKitSyncService] ✅ Marked notification as read")
                        #endif
                        return
                    }
                }
            } catch {
                #if DEBUG
                print("[CloudKitSyncService] ⚠️ Error in zone \(zone.zoneID.zoneName): \(error.localizedDescription)")
                #endif
            }
        }
    }

    // MARK: - Subscription Status Sync (for Child Verification)

    /// Update parent device's subscription status in CloudKit
    /// Called when subscription changes on parent device
    /// Child devices can query this to verify parent's subscription
    func updateParentSubscriptionStatus(tier: SubscriptionTier, status: SubscriptionStatus, expiryDate: Date?) async throws {
        let context = persistenceController.container.viewContext
        let deviceID = DeviceModeManager.shared.deviceID

        #if DEBUG
        print("[CloudKitSyncService] Updating parent subscription status: \(tier.rawValue), \(status.rawValue)")
        #endif

        // Find or create RegisteredDevice for this parent
        let fetchRequest: NSFetchRequest<RegisteredDevice> = RegisteredDevice.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "deviceID == %@", deviceID)

        let devices = try context.fetch(fetchRequest)

        let device: RegisteredDevice
        if let existing = devices.first {
            device = existing
        } else {
            // Create new device record
            device = RegisteredDevice(context: context)
            device.deviceID = deviceID
            device.deviceName = DeviceModeManager.shared.deviceName
            device.deviceType = "parent"
            device.registrationDate = Date()
            device.isActive = true
        }

        // Update subscription fields
        device.subscriptionTier = tier.rawValue
        device.subscriptionStatus = status.rawValue
        device.subscriptionExpiryDate = expiryDate
        device.lastSyncDate = Date()

        try context.save()

        #if DEBUG
        print("[CloudKitSyncService] ✅ Parent subscription status saved to CoreData (will sync to CloudKit)")
        #endif
    }

    /// Fetch parent's subscription status from CloudKit
    /// Called by child device to verify parent's subscription
    /// Returns (tier, status, isValid) tuple
    func fetchParentSubscriptionStatus(parentDeviceID: String) async throws -> (tier: SubscriptionTier, status: SubscriptionStatus, isValid: Bool) {
        #if DEBUG
        print("[CloudKitSyncService] Fetching parent subscription for: \(parentDeviceID)")
        #endif

        // Query shared database for parent's device record
        let sharedDB = container.sharedCloudDatabase

        do {
            let zones = try await sharedDB.allRecordZones()

            // Look in all shared zones for parent info
            for zone in zones where zone.zoneID.zoneName.hasPrefix("ChildMonitoring-") {
                do {
                    // CloudKit does not support OR across two different fields in one predicate.
                    // Run two single-field queries sequentially: parent's own registration (CD_deviceID),
                    // then fall back to child's record pointing at parent (CD_parentDeviceID).
                    var predicate = NSPredicate(format: "CD_deviceID == %@", parentDeviceID)
                    var query = CKQuery(recordType: "CD_RegisteredDevice", predicate: predicate)
                    var (matches, _) = try await sharedDB.records(matching: query, inZoneWith: zone.zoneID)

                    if matches.isEmpty {
                        predicate = NSPredicate(format: "CD_parentDeviceID == %@", parentDeviceID)
                        query = CKQuery(recordType: "CD_RegisteredDevice", predicate: predicate)
                        (matches, _) = try await sharedDB.records(matching: query, inZoneWith: zone.zoneID)
                    }

                    for (_, result) in matches {
                        if case .success(let record) = result {
                            let tierString = record["CD_subscriptionTier"] as? String ?? "trial"
                            let statusString = record["CD_subscriptionStatus"] as? String ?? "trial"
                            let expiryDate = record["CD_subscriptionExpiryDate"] as? Date

                            let tier = SubscriptionTier(rawValue: tierString) ?? .trial
                            let status = SubscriptionStatus(rawValue: statusString) ?? .trial

                            // Check if subscription is still valid
                            let isValid: Bool
                            if let expiry = expiryDate {
                                isValid = Date() < expiry || status == .active || status == .grace
                            } else {
                                isValid = status.isAccessGranted
                            }

                            #if DEBUG
                            print("[CloudKitSyncService] ✅ Found parent subscription: \(tier.rawValue), \(status.rawValue), valid: \(isValid)")
                            #endif

                            return (tier, status, isValid)
                        }
                    }
                } catch {
                    #if DEBUG
                    print("[CloudKitSyncService] ⚠️ Error checking zone \(zone.zoneID.zoneName): \(error.localizedDescription)")
                    #endif
                    continue
                }
            }
        } catch {
            #if DEBUG
            print("[CloudKitSyncService] ⚠️ Error fetching zones: \(error.localizedDescription)")
            #endif
        }

        // Fallback: Check if we have cached parent info from pairing
        // If CloudKit query fails, assume valid to avoid blocking user
        #if DEBUG
        print("[CloudKitSyncService] ⚠️ Could not verify parent subscription, assuming valid")
        #endif
        return (.trial, .trial, true)
    }

    /// Return the set of `ChildMonitoring-*` shared zone names the current iCloud account can access.
    /// Used by the child to detect when its locally-cached parent zone is no longer reachable
    /// (e.g., parent switched iCloud accounts after pairing — zone remains orphaned in old account).
    func reachableSharedParentZoneNames() async -> Set<String> {
        do {
            let zones = try await container.sharedCloudDatabase.allRecordZones()
            return Set(zones.map { $0.zoneID.zoneName }.filter { $0.hasPrefix("ChildMonitoring-") })
        } catch {
            #if DEBUG
            print("[CloudKitSyncService] ⚠️ Failed to fetch shared zones for reachability check: \(error.localizedDescription)")
            #endif
            return []
        }
    }

    /// Count parent devices that have paired with a specific child
    /// Used to enforce the 2-parent-per-child limit
    func countParentDevicesForChild(childDeviceID: String) async throws -> Int {
        #if DEBUG
        print("[CloudKitSyncService] Counting parent devices for child: \(childDeviceID)")
        #endif

        // Get paired parents from local storage
        let pairedParents = DevicePairingService.shared.getPairedParents()
        let count = pairedParents.count

        #if DEBUG
        print("[CloudKitSyncService] Found \(count) parent device(s)")
        #endif

        return count
    }

    // MARK: - CloudKit Push Subscriptions

    /// Subscription ID for parent config changes
    private static let parentConfigSubscriptionID = "parent-config-changes"

    /// Subscription ID for child usage updates
    private static let childUsageSubscriptionID = "child-usage-updates"

    /// Set up CloudKit database subscriptions for real-time push notifications
    /// Call this during app initialization after user is signed into iCloud
    func setupDatabaseSubscriptions() async {
        #if DEBUG
        print("[CloudKitSyncService] ===== Setting Up Database Subscriptions =====")
        #endif

        let deviceMode = DeviceModeManager.shared.currentMode

        do {
            if deviceMode == .childDevice {
                // Child device subscribes to parent's shared database for config changes
                try await setupChildSubscriptions()
            } else {
                // Parent device subscribes to private database for child usage updates
                try await setupParentSubscriptions()
            }
        } catch {
            #if DEBUG
            print("[CloudKitSyncService] ⚠️ Failed to setup subscriptions: \(error)")
            #endif
        }
    }

    /// Set up subscriptions for child device to receive parent config changes
    private func setupChildSubscriptions() async throws {
        let sharedDB = container.sharedCloudDatabase

        // Check if subscription already exists
        let existingSubscriptions = try await sharedDB.allSubscriptions()
        if existingSubscriptions.contains(where: { $0.subscriptionID == Self.parentConfigSubscriptionID }) {
            #if DEBUG
            print("[CloudKitSyncService] ✅ Parent config subscription already exists")
            #endif
            return
        }

        // Create a database subscription for all record types in shared database
        // This will notify us when parent pushes config commands
        let subscription = CKDatabaseSubscription(subscriptionID: Self.parentConfigSubscriptionID)

        // Configure notification info for silent push
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true  // Silent push for background processing
        notificationInfo.shouldBadge = false
        notificationInfo.soundName = nil
        subscription.notificationInfo = notificationInfo

        do {
            _ = try await sharedDB.save(subscription)
            #if DEBUG
            print("[CloudKitSyncService] ✅ Created parent config subscription")
            #endif
        } catch let error as CKError where error.code == .serverRejectedRequest {
            // Subscription may already exist or quota exceeded
            #if DEBUG
            print("[CloudKitSyncService] ⚠️ Server rejected subscription (may already exist): \(error.localizedDescription)")
            #endif
        }
    }

    /// Set up subscriptions for parent device to receive child usage updates
    private func setupParentSubscriptions() async throws {
        let privateDB = container.privateCloudDatabase

        // Check if subscription already exists
        let existingSubscriptions = try await privateDB.allSubscriptions()
        if existingSubscriptions.contains(where: { $0.subscriptionID == Self.childUsageSubscriptionID }) {
            #if DEBUG
            print("[CloudKitSyncService] ✅ Child usage subscription already exists")
            #endif
            return
        }

        // Create a database subscription for all record types in private database
        // This will notify us when child syncs usage data or shield states
        let subscription = CKDatabaseSubscription(subscriptionID: Self.childUsageSubscriptionID)

        // Configure notification info for silent push
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true  // Silent push for background processing
        notificationInfo.shouldBadge = false
        notificationInfo.soundName = nil
        subscription.notificationInfo = notificationInfo

        do {
            _ = try await privateDB.save(subscription)
            #if DEBUG
            print("[CloudKitSyncService] ✅ Created child usage subscription")
            #endif
        } catch let error as CKError where error.code == .serverRejectedRequest {
            // Subscription may already exist or quota exceeded
            #if DEBUG
            print("[CloudKitSyncService] ⚠️ Server rejected subscription (may already exist): \(error.localizedDescription)")
            #endif
        }
    }

    /// Handle a CloudKit push notification (called from AppDelegate/SceneDelegate)
    /// Returns true if the notification was handled
    func handleCloudKitNotification(_ userInfo: [AnyHashable: Any]) async -> Bool {
        guard let notification = CKNotification(fromRemoteNotificationDictionary: userInfo) else {
            return false
        }

        #if DEBUG
        print("[CloudKitSyncService] 🔔 Received CloudKit push notification")
        print("[CloudKitSyncService] Subscription ID: \(notification.subscriptionID ?? "nil")")
        print("[CloudKitSyncService] Notification Type: \(notification.notificationType.rawValue)")
        #endif

        let deviceMode = DeviceModeManager.shared.currentMode

        if deviceMode == .childDevice {
            // Child received notification - check for config updates
            if notification.subscriptionID == Self.parentConfigSubscriptionID {
                #if DEBUG
                print("[CloudKitSyncService] 📥 Processing parent config push notification")
                #endif

                do {
                    try await ChildBackgroundSyncService.shared.checkForConfigurationUpdates()
                    #if DEBUG
                    print("[CloudKitSyncService] ✅ Processed config updates from push notification")
                    #endif
                } catch {
                    #if DEBUG
                    print("[CloudKitSyncService] ⚠️ Error processing config updates: \(error)")
                    #endif
                }
                return true
            }
        } else {
            // Parent received notification - refresh child data
            if notification.subscriptionID == Self.childUsageSubscriptionID {
                #if DEBUG
                print("[CloudKitSyncService] 📥 Processing child usage push notification")
                #endif

                // Post notification for UI to refresh
                await MainActor.run {
                    NotificationCenter.default.post(name: .childDataUpdated, object: nil)
                }
                return true
            }
        }

        return false
    }

    /// Remove all CloudKit subscriptions (call during logout/unpair)
    func removeAllSubscriptions() async {
        #if DEBUG
        print("[CloudKitSyncService] ===== Removing All Database Subscriptions =====")
        #endif

        do {
            // Remove from private database
            let privateDB = container.privateCloudDatabase
            let privateSubscriptions = try await privateDB.allSubscriptions()
            for subscription in privateSubscriptions {
                try? await privateDB.deleteSubscription(withID: subscription.subscriptionID)
                #if DEBUG
                print("[CloudKitSyncService] Removed private subscription: \(subscription.subscriptionID)")
                #endif
            }

            // Remove from shared database
            let sharedDB = container.sharedCloudDatabase
            let sharedSubscriptions = try await sharedDB.allSubscriptions()
            for subscription in sharedSubscriptions {
                try? await sharedDB.deleteSubscription(withID: subscription.subscriptionID)
                #if DEBUG
                print("[CloudKitSyncService] Removed shared subscription: \(subscription.subscriptionID)")
                #endif
            }

            #if DEBUG
            print("[CloudKitSyncService] ✅ All subscriptions removed")
            #endif
        } catch {
            #if DEBUG
            print("[CloudKitSyncService] ⚠️ Error removing subscriptions: \(error)")
            #endif
        }
    }
}

// MARK: - Notification Names for CloudKit Updates

extension Notification.Name {
    /// Posted when parent receives child data update from CloudKit push
    static let childDataUpdated = Notification.Name("childDataUpdated")
}
