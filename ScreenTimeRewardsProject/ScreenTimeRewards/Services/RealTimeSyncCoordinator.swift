//
//  RealTimeSyncCoordinator.swift
//  ScreenTimeRewards
//
//  Coordinates real-time CloudKit sync triggers with throttling.
//  Syncs are triggered by shield state changes and extension usage notifications.
//  Throttled to at most once per 30 seconds per sync type.
//

import Foundation

/// Coordinates real-time CloudKit sync with 30-second throttling.
/// Listens for shield state changes and gets called when extension reports usage.
@MainActor
class RealTimeSyncCoordinator {
    static let shared = RealTimeSyncCoordinator()

    // MARK: - Throttle State

    private var lastShieldSyncDate: Date?
    private var lastUsageSyncDate: Date?
    private let throttleInterval: TimeInterval = 30.0

    // MARK: - Notification Observers

    private var shieldBlockedObserver: NSObjectProtocol?
    private var shieldUnlockedObserver: NSObjectProtocol?

    // MARK: - Initialization

    private init() {
        setupNotificationObservers()
        #if DEBUG
        print("[RealTimeSyncCoordinator] Initialized")
        #endif
    }

    deinit {
        if let observer = shieldBlockedObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = shieldUnlockedObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Setup

    private func setupNotificationObservers() {
        // Listen for shield blocked notifications
        shieldBlockedObserver = NotificationCenter.default.addObserver(
            forName: .rewardAppsBlocked,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.triggerShieldStateSync()
            }
        }

        // Listen for shield unlocked notifications
        shieldUnlockedObserver = NotificationCenter.default.addObserver(
            forName: .rewardAppsUnlocked,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.triggerShieldStateSync()
            }
        }

        #if DEBUG
        print("[RealTimeSyncCoordinator] Notification observers set up")
        #endif
    }

    // MARK: - Public Trigger Methods

    /// Trigger shield state sync (called automatically on block/unblock notifications)
    /// Throttled to once per 30 seconds
    func triggerShieldStateSync() {
        guard isPaired() else {
            #if DEBUG
            print("[RealTimeSyncCoordinator] Not paired, skipping shield sync")
            #endif
            return
        }

        guard canSync(lastSync: lastShieldSyncDate) else {
            #if DEBUG
            let remaining = throttleInterval - Date().timeIntervalSince(lastShieldSyncDate ?? Date.distantPast)
            print("[RealTimeSyncCoordinator] Shield sync throttled, \(Int(remaining))s remaining")
            #endif
            return
        }

        #if DEBUG
        print("[RealTimeSyncCoordinator] Triggering real-time shield state sync")
        #endif

        lastShieldSyncDate = Date()

        Task {
            do {
                try await CloudKitSyncService.shared.uploadShieldStatesToParent()
                #if DEBUG
                print("[RealTimeSyncCoordinator] Shield state sync completed")
                #endif
            } catch {
                #if DEBUG
                print("[RealTimeSyncCoordinator] Shield sync error: \(error.localizedDescription)")
                #endif
            }
        }
    }

    /// Trigger usage data sync (called when extension reports usage via Darwin notification)
    /// Throttled to once per 30 seconds
    func triggerUsageDataSync() {
        guard isPaired() else {
            #if DEBUG
            print("[RealTimeSyncCoordinator] Not paired, skipping usage sync")
            #endif
            return
        }

        guard canSync(lastSync: lastUsageSyncDate) else {
            #if DEBUG
            let remaining = throttleInterval - Date().timeIntervalSince(lastUsageSyncDate ?? Date.distantPast)
            print("[RealTimeSyncCoordinator] Usage sync throttled, \(Int(remaining))s remaining")
            #endif
            return
        }

        #if DEBUG
        print("[RealTimeSyncCoordinator] Triggering real-time usage history sync")
        #endif

        lastUsageSyncDate = Date()

        Task {
            do {
                try await CloudKitSyncService.shared.uploadDailyUsageHistoryToParent()
                #if DEBUG
                print("[RealTimeSyncCoordinator] Usage history sync completed")
                #endif
            } catch {
                #if DEBUG
                print("[RealTimeSyncCoordinator] Usage sync error: \(error.localizedDescription)")
                #endif
            }
        }
    }

    // MARK: - Helpers

    /// Check if device is a paired child device
    private func isPaired() -> Bool {
        guard DeviceModeManager.shared.isChildDevice else {
            return false
        }

        // Check for pairing using DevicePairingService (supports multi-parent storage format)
        return !DevicePairingService.shared.getPairedParents().isEmpty
    }

    /// Check if enough time has passed since last sync
    private func canSync(lastSync: Date?) -> Bool {
        guard let lastSync = lastSync else {
            return true  // Never synced before
        }

        let elapsed = Date().timeIntervalSince(lastSync)
        return elapsed >= throttleInterval
    }
}
