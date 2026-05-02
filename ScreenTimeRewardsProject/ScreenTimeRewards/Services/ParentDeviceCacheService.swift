import Foundation

/// Disk cache for the parent device dashboard.
///
/// Purpose: the parent main app launch blocks on a full CloudKit fan-out (15 zones,
/// 5 paired children, 7 app configs each) before any child card can render. During
/// that ~60s cold window the dashboard renders "No Child Devices Linked" — a lie —
/// and each child card shows 0 minutes because the snapshot is still in flight.
///
/// This cache persists the last-known state (children list + per-child usage, configs,
/// daily snapshot) to a single JSON file under `Application Support/ParentCache/`.
/// The view model reads it synchronously on init, renders from cache at t=0, then
/// refreshes from CloudKit in the background and overwrites cache on each successful
/// fetch. User sees instant, stale-but-labeled state, which is strictly better than
/// instant zeros.
///
/// The cache is a projection, not a source of truth. CloudKit always wins on conflict
/// (e.g., child removed from pairing, config edited from another parent).
///
/// Intentionally isolated from the live `FullAppConfigDTO` / `DailySnapshotDTO` (those
/// have `CKRecord` inits and aren't Codable). The cache DTOs here are a deliberate
/// Codable mirror — copying fields on write, rebuilding the live DTOs on read.
final class ParentDeviceCacheService {
    static let shared = ParentDeviceCacheService()

    private let schemaVersion = 1
    private let fileManager = FileManager.default
    private let directoryURL: URL

    // Debounce concurrent saveCachedState calls so rapid objectWillChange emissions
    // don't thrash disk. One pending write per parentID.
    private var pendingSaves: [String: DispatchWorkItem] = [:]
    private let saveDebounce: TimeInterval = 0.5
    private let saveQueue = DispatchQueue(label: "com.screentimerewards.parentcache.save", qos: .utility)
    private let stateQueue = DispatchQueue(label: "com.screentimerewards.parentcache.state")

    private init() {
        // Application Support/ParentCache/
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        directoryURL = appSupport.appendingPathComponent("ParentCache", isDirectory: true)
        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    // MARK: - Public API

    /// Synchronous read. Returns nil if no cache exists for this parent, or if the
    /// persisted schemaVersion doesn't match the current one (treat as cold start).
    func loadCachedState(parentID: String) -> ParentDeviceCacheSnapshot? {
        guard !parentID.isEmpty else { return nil }
        let url = fileURL(for: parentID)
        guard fileManager.fileExists(atPath: url.path) else { return nil }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let snapshot = try decoder.decode(ParentDeviceCacheSnapshot.self, from: data)
            guard snapshot.schemaVersion == schemaVersion else {
                #if DEBUG
                print("[ParentDeviceCacheService] Schema mismatch (\(snapshot.schemaVersion) vs \(schemaVersion)) — ignoring cache")
                #endif
                return nil
            }
            #if DEBUG
            print("[ParentDeviceCacheService] ✅ Loaded cache: \(snapshot.children.count) children, savedAt=\(snapshot.savedAt)")
            #endif
            return snapshot
        } catch {
            #if DEBUG
            print("[ParentDeviceCacheService] ⚠️ Cache decode failed: \(error.localizedDescription)")
            #endif
            return nil
        }
    }

    /// Debounced write. Repeated calls within `saveDebounce` coalesce to a single
    /// disk write. Use when you want to batch rapid successive updates.
    func saveCachedState(_ snapshot: ParentDeviceCacheSnapshot, parentID: String) {
        guard !parentID.isEmpty else { return }

        stateQueue.async { [weak self] in
            guard let self = self else { return }

            // Cancel any pending save for this parent — we'll schedule a fresh one
            // that captures the newest snapshot.
            self.pendingSaves[parentID]?.cancel()

            let work = DispatchWorkItem { [weak self] in
                self?.performSave(snapshot: snapshot, parentID: parentID)
            }
            self.pendingSaves[parentID] = work
            self.saveQueue.asyncAfter(deadline: .now() + self.saveDebounce, execute: work)
        }
    }

    /// Immediate, synchronous-style write. Use for critical updates where the caller
    /// wants the write to land before returning control (e.g., final commit on
    /// user-initiated edit).
    func saveCachedStateImmediately(_ snapshot: ParentDeviceCacheSnapshot, parentID: String) {
        guard !parentID.isEmpty else { return }
        stateQueue.sync {
            pendingSaves[parentID]?.cancel()
            pendingSaves[parentID] = nil
        }
        performSave(snapshot: snapshot, parentID: parentID)
    }

    /// Mutate one child inside the cache atomically. Reads current snapshot (or
    /// creates a new one), applies the mutation, writes back. No-op if the
    /// child isn't in the cache yet and the mutation closure doesn't add it.
    func updateChild(
        deviceID: String,
        parentID: String,
        mutating: (inout CachedChild) -> Void
    ) {
        var snapshot = loadCachedState(parentID: parentID)
            ?? ParentDeviceCacheSnapshot(schemaVersion: schemaVersion, savedAt: Date(), children: [])

        if let idx = snapshot.children.firstIndex(where: { $0.deviceID == deviceID }) {
            var child = snapshot.children[idx]
            mutating(&child)
            snapshot.children[idx] = child
        } else {
            var child = CachedChild(
                deviceID: deviceID,
                displayName: "",
                sharedZoneID: nil,
                sharedZoneOwner: nil,
                lastSyncAt: Date(),
                usage: nil,
                configs: nil,
                dailySnapshot: nil
            )
            mutating(&child)
            if !child.deviceID.isEmpty {
                snapshot.children.append(child)
            }
        }
        snapshot.savedAt = Date()
        saveCachedState(snapshot, parentID: parentID)
    }

    /// Clear the cache for a parent. Call on unpair-all or sign-out.
    func clearCache(parentID: String) {
        guard !parentID.isEmpty else { return }
        let url = fileURL(for: parentID)
        try? fileManager.removeItem(at: url)
        stateQueue.sync {
            pendingSaves[parentID]?.cancel()
            pendingSaves[parentID] = nil
        }
    }

    // MARK: - Internals

    private func fileURL(for parentID: String) -> URL {
        directoryURL.appendingPathComponent("parent_\(parentID).json")
    }

    private func performSave(snapshot: ParentDeviceCacheSnapshot, parentID: String) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            let data = try encoder.encode(snapshot)
            try data.write(to: fileURL(for: parentID), options: .atomic)
            #if DEBUG
            print("[ParentDeviceCacheService] 💾 Cached \(snapshot.children.count) children for parent \(parentID.prefix(8))…")
            #endif
        } catch {
            #if DEBUG
            print("[ParentDeviceCacheService] ❌ Cache write failed: \(error.localizedDescription)")
            #endif
        }

        stateQueue.async { [weak self] in
            self?.pendingSaves[parentID] = nil
        }
    }
}

// MARK: - Codable Cache DTOs
//
// These intentionally mirror (rather than extend) the live `FullAppConfigDTO` /
// `DailySnapshotDTO` / etc. which have `CKRecord`-based inits. Keeping this layer
// separate avoids touching the CloudKit DTOs and isolates schema evolution to this
// file.

struct ParentDeviceCacheSnapshot: Codable {
    let schemaVersion: Int
    var savedAt: Date
    var children: [CachedChild]
}

struct CachedChild: Codable {
    let deviceID: String
    var displayName: String
    var sharedZoneID: String?
    var sharedZoneOwner: String?
    var lastSyncAt: Date
    var usage: CachedUsageSnapshot?
    var configs: CachedConfigSnapshot?
    var dailySnapshot: CachedDailySnapshot?
    var dailyUsageHistory: [CachedDailyUsageHistory]?
    var shieldStates: [CachedShieldState]?
}

struct CachedShieldState: Codable {
    let rewardAppLogicalID: String
    let deviceID: String
    let isUnlocked: Bool
    let unlockedAt: Date?
    let reason: String
    let syncTimestamp: Date?
    let rewardAppDisplayName: String?
}

struct CachedUsageSnapshot: Codable {
    var learningSecondsToday: Int
    var rewardSecondsToday: Int
    var recordedAt: Date
}

struct CachedConfigSnapshot: Codable {
    var learningConfigs: [CachedAppConfig]
    var rewardConfigs: [CachedAppConfig]
    var recordedAt: Date
}

/// Minimal config fields needed to render a dashboard card. Keeps the cache small
/// and decoupled from the rich `FullAppConfigDTO` which has many non-Codable deps.
struct CachedAppConfig: Codable {
    let logicalID: String
    let deviceID: String
    let displayName: String
    let category: String
    let pointsPerMinute: Int
    let isEnabled: Bool
    let blockingEnabled: Bool
    let tokenHash: String?
    let lastModified: Date?
    let iconURL: String?
    let dailyLimitSummary: String?
    let timeWindowSummary: String?
    let unlockModeRawValue: String?
    let scheduleConfigJSON: String?
    let linkedAppsJSON: String?
    let streakSettingsJSON: String?

    /// Phase 2: append-only schedule version history, JSON-encoded
    /// `[AppScheduleVersion]`. Optional with `decodeIfPresent` so old caches load.
    let scheduleVersionsJSON: String?

    init(
        logicalID: String,
        deviceID: String,
        displayName: String,
        category: String,
        pointsPerMinute: Int,
        isEnabled: Bool,
        blockingEnabled: Bool,
        tokenHash: String?,
        lastModified: Date?,
        iconURL: String?,
        dailyLimitSummary: String?,
        timeWindowSummary: String?,
        unlockModeRawValue: String?,
        scheduleConfigJSON: String?,
        linkedAppsJSON: String?,
        streakSettingsJSON: String?,
        scheduleVersionsJSON: String? = nil
    ) {
        self.logicalID = logicalID
        self.deviceID = deviceID
        self.displayName = displayName
        self.category = category
        self.pointsPerMinute = pointsPerMinute
        self.isEnabled = isEnabled
        self.blockingEnabled = blockingEnabled
        self.tokenHash = tokenHash
        self.lastModified = lastModified
        self.iconURL = iconURL
        self.dailyLimitSummary = dailyLimitSummary
        self.timeWindowSummary = timeWindowSummary
        self.unlockModeRawValue = unlockModeRawValue
        self.scheduleConfigJSON = scheduleConfigJSON
        self.linkedAppsJSON = linkedAppsJSON
        self.streakSettingsJSON = streakSettingsJSON
        self.scheduleVersionsJSON = scheduleVersionsJSON
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        logicalID = try container.decode(String.self, forKey: .logicalID)
        deviceID = try container.decode(String.self, forKey: .deviceID)
        displayName = try container.decode(String.self, forKey: .displayName)
        category = try container.decode(String.self, forKey: .category)
        pointsPerMinute = try container.decode(Int.self, forKey: .pointsPerMinute)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        blockingEnabled = try container.decode(Bool.self, forKey: .blockingEnabled)
        tokenHash = try container.decodeIfPresent(String.self, forKey: .tokenHash)
        lastModified = try container.decodeIfPresent(Date.self, forKey: .lastModified)
        iconURL = try container.decodeIfPresent(String.self, forKey: .iconURL)
        dailyLimitSummary = try container.decodeIfPresent(String.self, forKey: .dailyLimitSummary)
        timeWindowSummary = try container.decodeIfPresent(String.self, forKey: .timeWindowSummary)
        unlockModeRawValue = try container.decodeIfPresent(String.self, forKey: .unlockModeRawValue)
        scheduleConfigJSON = try container.decodeIfPresent(String.self, forKey: .scheduleConfigJSON)
        linkedAppsJSON = try container.decodeIfPresent(String.self, forKey: .linkedAppsJSON)
        streakSettingsJSON = try container.decodeIfPresent(String.self, forKey: .streakSettingsJSON)
        scheduleVersionsJSON = try container.decodeIfPresent(String.self, forKey: .scheduleVersionsJSON)
    }

    enum CodingKeys: String, CodingKey {
        case logicalID, deviceID, displayName, category, pointsPerMinute
        case isEnabled, blockingEnabled, tokenHash, lastModified, iconURL
        case dailyLimitSummary, timeWindowSummary, unlockModeRawValue
        case scheduleConfigJSON, linkedAppsJSON, streakSettingsJSON
        case scheduleVersionsJSON
    }
}

struct CachedDailySnapshot: Codable {
    let deviceID: String
    let date: Date
    let totalEarnedMinutes: Int
    let totalLearningSeconds: Int
    let totalRewardSeconds: Int
    let cumulativeAvailableMinutes: Int
    let recordedAt: Date
}

struct CachedDailyUsageHistory: Codable {
    let deviceID: String
    let logicalID: String
    let displayName: String
    let date: Date
    let seconds: Int
    let category: String
    let hourlySeconds: [Int]
}
