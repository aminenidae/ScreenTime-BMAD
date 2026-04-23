import Foundation
import BackgroundTasks

/// Pure CloudKit resync background task for child→parent visibility.
///
/// Distinct from `ChildBackgroundSyncService.usage-upload` which also performs
/// monitoring maintenance (`performMonitoringMaintenanceIfNeeded` →
/// `restartMonitoring`). This task ONLY uploads what's already persisted to
/// CloudKit — it never touches usage tracking, threshold scheduling, or
/// DeviceActivity monitoring.
///
/// Identifier: `com.screentimerewards.ck-resync`
/// Cadence:    ~30 minutes, self-rescheduling.
///
/// What it uploads (all `CloudKitSyncService` calls — read-only against persisted state):
///   • `uploadDailyUsageHistoryToParent()` — the per-app daily totals the parent dashboard reads
///   • `uploadShieldStatesToParent()`      — current shield state snapshot
///
/// What it deliberately does NOT do:
///   • Read or rebuild extension App Group `ext_usage_*` keys
///   • Restart monitoring or refresh DeviceActivity windows
///   • Touch Core Data `UsageRecord` rows or the offline queue
///   • Anything that could affect threshold-event firing or sliding-window behavior
final class ChildCKResyncService {
    static let shared = ChildCKResyncService()

    static let taskIdentifier = "com.screentimerewards.ck-resync"
    private static let intervalSeconds: TimeInterval = 30 * 60

    private init() {}

    /// Register the BGTask handler. Must be called before app finishes launching.
    func register() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.taskIdentifier,
            using: nil
        ) { [weak self] task in
            self?.handle(task)
        }
        #if DEBUG
        print("[ChildCKResyncService] Registered \(Self.taskIdentifier)")
        #endif
    }

    /// Submit the first task to seed the chain. Idempotent — iOS replaces any
    /// pending request with the same identifier.
    func bootstrap() {
        scheduleNext(earliestDelay: 60) // first run ~1 min after launch
    }

    /// Submit the next task in the chain.
    private func scheduleNext(earliestDelay: TimeInterval = intervalSeconds) {
        let request = BGProcessingTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: earliestDelay)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false

        do {
            try BGTaskScheduler.shared.submit(request)
            #if DEBUG
            print("[ChildCKResyncService] Scheduled next CK resync in \(Int(earliestDelay))s")
            #endif
        } catch {
            #if DEBUG
            print("[ChildCKResyncService] Failed to schedule CK resync: \(error)")
            #endif
        }
    }

    /// Handle the BGTask. Pure CloudKit upload — no monitoring side effects.
    private func handle(_ task: BGTask) {
        #if DEBUG
        print("[ChildCKResyncService] ===== CK Resync task started =====")
        #endif

        task.expirationHandler = {
            #if DEBUG
            print("[ChildCKResyncService] CK resync EXPIRED (iOS killed before completion)")
            #endif
            task.setTaskCompleted(success: false)
        }

        Task {
            // Always reschedule first so a thrown error or cancellation can't
            // break the chain.
            self.scheduleNext()

            // Skip if not paired — parent zone info won't exist.
            guard DevicePairingService.shared.hasValidPairing() else {
                #if DEBUG
                print("[ChildCKResyncService] ⏭️ Skipped (no valid pairing)")
                #endif
                task.setTaskCompleted(success: true)
                return
            }

            var ok = true

            do {
                try await CloudKitSyncService.shared.uploadDailyUsageHistoryToParent()
                #if DEBUG
                print("[ChildCKResyncService] ✅ Uploaded daily usage history")
                #endif
            } catch {
                ok = false
                #if DEBUG
                print("[ChildCKResyncService] ⚠️ uploadDailyUsageHistoryToParent failed: \(error)")
                #endif
            }

            do {
                try await CloudKitSyncService.shared.uploadShieldStatesToParent()
                #if DEBUG
                print("[ChildCKResyncService] ✅ Uploaded shield states")
                #endif
            } catch {
                ok = false
                #if DEBUG
                print("[ChildCKResyncService] ⚠️ uploadShieldStatesToParent failed: \(error)")
                #endif
            }

            task.setTaskCompleted(success: ok)
        }
    }
}
