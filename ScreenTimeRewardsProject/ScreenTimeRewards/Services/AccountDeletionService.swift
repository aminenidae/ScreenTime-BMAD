import Foundation
import CoreData
import Security
import RevenueCat

/// Orchestrates complete account and data deletion for Apple Guideline 5.1.1(v) compliance.
/// Cleans up: ScreenTime monitoring, CloudKit, CoreData, Keychain, UserDefaults, RevenueCat.
@MainActor
final class AccountDeletionService {

    static let shared = AccountDeletionService()

    private init() {}

    // MARK: - All CoreData entity names

    private let coreDataEntityNames = [
        "AppConfiguration",
        "AppProgress",
        "AvatarState",
        "Badge",
        "Challenge",
        "ChallengeProgress",
        "CollectedCard",
        "ConfigurationCommand",
        "DailySummary",
        "Item",
        "PairingCode",
        "RegisteredDevice",
        "StreakRecord",
        "SyncQueueItem",
        "UsageRecord",
        "UserSubscription"
    ]

    // MARK: - Main Deletion Method

    /// Deletes all account data and returns the app to its initial state.
    /// - Parameter isChildDevice: Whether this device is in child mode (affects CloudKit cleanup path).
    func deleteAllData(isChildDevice: Bool) async throws {

        // 1. Stop Screen Time monitoring and clear shields
        let screenTimeService = ScreenTimeService.shared
        screenTimeService.stopMonitoring()
        screenTimeService.clearAllShields()
        screenTimeService.clearAllWebRestrictions()
        screenTimeService.clearBundleIDMappings()
        screenTimeService.resetData()

        // 2. CloudKit cleanup (differs by device mode)
        if isChildDevice {
            DevicePairingService.shared.unpairDevice()
        } else {
            // Parent: delete all child monitoring zones
            let _ = try? await CloudKitSyncService.shared.deleteAllChildMonitoringZones()
            // Also unpair locally
            DevicePairingService.shared.unpairDevice()
        }

        // 3. Delete all CoreData records
        deleteAllCoreDataRecords()

        // 4. Clear PIN from Keychain
        ParentPINService.shared.clearPIN()

        // 5. Delete deviceID and trialStartDate from Keychain
        deleteKeychainItem(service: "com.screentimerewards", account: "deviceID")
        deleteKeychainItem(service: "com.screentimerewards", account: "trialStartDate")

        // 6. Clear all UserDefaults (standard + app group)
        clearAllUserDefaults()

        // 7. Clear cached usage data
        UsagePersistence().clearAllAppData(reason: "Account deletion")

        // 8. Log out of RevenueCat
        try? await Purchases.shared.logOut()

        // 9. Reset device mode (returns to onboarding)
        DeviceModeManager.shared.resetDeviceMode()
    }

    // MARK: - CoreData Cleanup

    private func deleteAllCoreDataRecords() {
        let context = PersistenceController.shared.container.viewContext

        for entityName in coreDataEntityNames {
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
            let batchDelete = NSBatchDeleteRequest(fetchRequest: fetchRequest)
            batchDelete.resultType = .resultTypeStatusOnly

            do {
                try context.execute(batchDelete)
            } catch {
                #if DEBUG
                print("[AccountDeletion] Failed to delete \(entityName): \(error)")
                #endif
            }
        }

        // Reset the context to pick up batch delete changes
        context.reset()
    }

    // MARK: - Keychain Cleanup

    private func deleteKeychainItem(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - UserDefaults Cleanup

    private func clearAllUserDefaults() {
        // Clear standard UserDefaults
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }

        // Clear app group UserDefaults
        let appGroupID = "group.com.screentimerewards.shared"
        if let groupDefaults = UserDefaults(suiteName: appGroupID) {
            groupDefaults.removePersistentDomain(forName: appGroupID)
        }
    }
}
