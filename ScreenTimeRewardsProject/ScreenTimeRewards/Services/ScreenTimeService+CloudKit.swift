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
        guard DeviceModeManager.shared.isChildDevice else {
            #if DEBUG
            print("[ScreenTimeService] Not a child device, skipping CloudKit config application")
            #endif
            return
        }
        
        guard let logicalID = config.logicalID else {
            #if DEBUG
            print("[ScreenTimeService] Invalid configuration - missing logicalID")
            #endif
            return
        }
        
        // Find local token that matches this configuration
        guard let token = findLocalToken(for: logicalID) else {
            #if DEBUG
            print("[ScreenTimeService] No local token found for logicalID: \(logicalID)")
            #endif
            return
        }
        
        #if DEBUG
        print("[ScreenTimeService] Applying CloudKit config for \(config.displayName ?? "Unknown")")
        #endif
        
        // Apply category assignment
        if let categoryString = config.category,
           let category = AppUsage.AppCategory(rawValue: categoryString) {
            // Update the service's category assignments
            self.assignCategory(category, to: token)
        }
        
        // Apply reward points
        if config.category == "reward" {
            let points = Int(config.pointsPerMinute)
            // Update the service's reward points assignments
            self.assignRewardPoints(points, to: token)
        }
        
        // Apply blocking state
        if config.blockingEnabled {
            self.blockRewardApps(tokens: [token])
        } else {
            self.unblockRewardApps(tokens: [token])
        }
        
        #if DEBUG
        print("[ScreenTimeService] Applied config for \(config.displayName ?? "Unknown")")
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
    
    /// Find local token that matches the given logical ID
    private func findLocalToken(for logicalID: String) -> ApplicationToken? {
        // Search through the current family selection for a matching token
        for application in familySelection.applications {
            guard let token = application.token else { continue }
            
            let mapping = usagePersistence.resolveLogicalID(
                for: token,
                bundleIdentifier: application.bundleIdentifier,
                displayName: application.localizedDisplayName ?? "Unknown"
            )
            
            if mapping.logicalID == logicalID {
                return token
            }
        }
        
        return nil
    }
}