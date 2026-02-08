import Foundation
import CoreData

@MainActor
class StreakMigrationService {
    static let shared = StreakMigrationService()
    private let migrationKey = "streak_migration_v1_completed"
    private let userDefaults = UserDefaults(suiteName: "group.com.screentimerewards.shared")

    func performMigrationIfNeeded() async {
        guard !(userDefaults?.bool(forKey: migrationKey) ?? false) else {
            print("[StreakMigration] Migration already completed")
            return
        }

        print("[StreakMigration] Starting migration from global to per-app streaks")

        // 1. Load global streak settings (if any)
        let globalSettings = loadGlobalSettings()

        // 2. Get all reward apps
        let scheduleService = AppScheduleService.shared
        let rewardApps = scheduleService.schedules.values.filter { config in
            !config.linkedLearningApps.isEmpty
        }

        print("[StreakMigration] Found \(rewardApps.count) reward apps to migrate")

        // 3. Migrate global settings to each reward app
        for config in rewardApps {
            var updatedConfig = config

            if globalSettings.isEnabled {
                // Map legacy settings to new format
                // Defaulting to 7-day cycle if migrating from old milestones
                updatedConfig.streakSettings = AppStreakSettings(
                    isEnabled: globalSettings.isEnabled,
                    bonusValue: globalSettings.bonusPercentage,
                    bonusType: .percentage,
                    streakCycleDays: 7, 
                    earnedMilestones: globalSettings.earnedMilestones
                )
            } else {
                updatedConfig.streakSettings = .defaultSettings
            }

            try? scheduleService.saveSchedule(updatedConfig)
            print("[StreakMigration] Migrated settings for app: \(config.id)")
        }

        // 4. Migrate existing StreakRecord to first reward app
        if let firstRewardApp = rewardApps.first {
            migrateExistingStreakRecord(to: firstRewardApp.id)
        }

        // 5. Mark migration complete
        userDefaults?.set(true, forKey: migrationKey)
        print("[StreakMigration] Migration completed successfully")
    }

    private func loadGlobalSettings() -> LegacyStreakSettings {
        guard let data = userDefaults?.data(forKey: "streak_settings"),
              let settings = try? JSONDecoder().decode(LegacyStreakSettings.self, from: data) else {
            return LegacyStreakSettings()
        }
        return settings
    }

    // Legacy struct for reading old data
    private struct LegacyStreakSettings: Codable {
        var isEnabled: Bool = false
        var bonusPercentage: Int = 10
        var milestones: [Int] = [7, 14, 30]
        var earnedMilestones: Set<Int> = []
    }

    private func migrateExistingStreakRecord(to appLogicalID: String) {
        let context = PersistenceController.shared.container.viewContext
        let deviceID = DeviceModeManager.shared.deviceID

        let request: NSFetchRequest<StreakRecord> = StreakRecord.fetchRequest()
        request.predicate = NSPredicate(
            format: "childDeviceID == %@ AND appLogicalID == nil",
            deviceID
        )
        request.fetchLimit = 1

        do {
            if let existingRecord = try context.fetch(request).first {
                existingRecord.appLogicalID = appLogicalID
                try context.save()
                print("[StreakMigration] Migrated existing streak record to app: \(appLogicalID)")
            }
        } catch {
            print("[StreakMigration] Error migrating streak record: \(error)")
        }
    }
}
