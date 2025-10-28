import Foundation
import FamilyControls
import ManagedSettings
import CoreData

// MARK: - CloudKit Sync Integration
extension ScreenTimeService {
    /// Sync current app configurations to CloudKit (child device only)
    func syncConfigurationToCloudKit() async {
        guard DeviceModeManager.shared.isChildDevice else { 
            #if DEBUG
            print("[ScreenTimeService] Not a child device, skipping CloudKit sync")
            #endif
            return 
        }

        let context = PersistenceController.shared.container.viewContext

        // Access category assignments through public method
        for (token, _) in self.getCategoryAssignments() {
            let (logicalID, tokenHash) = usagePersistence.resolveLogicalID(
                for: token,
                bundleIdentifier: nil,
                displayName: getDisplayNameFromFamilySelection(for: token) ?? "Unknown"
            )

            // Find or create AppConfiguration
            let fetchRequest = AppConfiguration.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "logicalID == %@", logicalID)

            let config: AppConfiguration
            do {
                if let existingConfig = try context.fetch(fetchRequest).first {
                    config = existingConfig
                } else {
                    config = AppConfiguration(context: context)
                }
            } catch {
                #if DEBUG
                print("[ScreenTimeService] Error fetching AppConfiguration: \(error)")
                #endif
                continue
            }

            config.logicalID = logicalID
            config.tokenHash = tokenHash
            config.displayName = getDisplayNameFromFamilySelection(for: token) ?? "Unknown"
            
            // Get category through public method
            if let category = self.getCategory(for: token) {
                config.category = category.rawValue
            }
            
            // Get points through public method
            config.pointsPerMinute = Int16(self.getRewardPoints(for: token))
            config.isEnabled = true
            config.blockingEnabled = self.isAppBlocked(token)
            config.lastModified = Date()
            config.deviceID = DeviceModeManager.shared.deviceID
            config.syncStatus = "synced"

            do {
                try context.save()
                #if DEBUG
                print("[ScreenTimeService] Synced config for \(config.displayName ?? "Unknown") to CloudKit")
                #endif
            } catch {
                #if DEBUG
                print("[ScreenTimeService] Error saving AppConfiguration: \(error)")
                #endif
            }
        }

        #if DEBUG
        print("[ScreenTimeService] Synced configurations to CloudKit")
        #endif
    }

    /// Apply CloudKit configuration to local settings (child device only)
    func applyCloudKitConfiguration(_ config: AppConfiguration) {
        // Note: We can't directly modify private properties from extension
        // This functionality would need to be implemented in the main class
        #if DEBUG
        print("[ScreenTimeService] Would apply config for \(config.displayName ?? "Unknown")")
        #endif
    }

    /// Get display name for a token from family selection
    private func getDisplayNameFromFamilySelection(for token: ApplicationToken) -> String? {
        // Find the application in the family selection
        for application in familySelection.applications {
            if application.token == token {
                return application.localizedDisplayName
            }
        }
        return nil
    }
}