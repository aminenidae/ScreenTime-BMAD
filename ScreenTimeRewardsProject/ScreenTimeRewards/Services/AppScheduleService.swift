import Foundation
import SwiftUI
import Combine

/// Service for managing per-app schedule configurations
@MainActor
class AppScheduleService: ObservableObject {
    static let shared = AppScheduleService()

    // MARK: - Published Properties

    @Published private(set) var schedules: [String: AppScheduleConfiguration] = [:]

    // MARK: - Private Properties

    private let userDefaultsKey = "AppScheduleConfigurations"
    private let sharedDefaults: UserDefaults?

    // MARK: - Initialization

    private init() {
        // Use app group for sharing with extensions
        sharedDefaults = UserDefaults(suiteName: "group.com.screentime.rewards")
        loadSchedules()
    }

    // MARK: - Public Methods

    /// Load all saved schedules from UserDefaults
    func loadSchedules() {
        guard let data = sharedDefaults?.data(forKey: userDefaultsKey) else {
            return
        }

        do {
            let configs = try JSONDecoder().decode([AppScheduleConfiguration].self, from: data)
            var schedulesDict: [String: AppScheduleConfiguration] = [:]
            for config in configs {
                schedulesDict[config.id] = config
            }
            schedules = schedulesDict
        } catch {
            print("[AppScheduleService] Failed to decode schedules: \(error)")
        }
    }

    /// Save a schedule configuration for an app
    func saveSchedule(_ config: AppScheduleConfiguration) throws {
        schedules[config.id] = config
        try persistSchedules()

        // Also save individual keys for extension access
        saveScheduleForExtension(config)
    }

    /// Delete a schedule configuration
    func deleteSchedule(for logicalID: String) throws {
        schedules.removeValue(forKey: logicalID)
        try persistSchedules()

        // Remove extension keys
        removeScheduleForExtension(logicalID)
    }

    /// Get schedule for a specific app
    func getSchedule(for logicalID: String) -> AppScheduleConfiguration? {
        schedules[logicalID]
    }

    /// Check if an app is currently allowed based on its schedule
    func isAppCurrentlyAllowed(_ logicalID: String) -> Bool {
        guard let config = schedules[logicalID] else {
            return true // No config = allowed
        }

        guard config.isEnabled else {
            return false // Disabled apps are not allowed
        }

        return config.isCurrentlyInAllowedWindow
    }

    /// Calculate remaining daily limit for an app
    func remainingDailyLimit(for logicalID: String, usedMinutes: Int) -> Int {
        guard let config = schedules[logicalID] else {
            return Int.max // No config = unlimited
        }

        let todayLimit = config.dailyLimits.todayLimit
        return max(0, todayLimit - usedMinutes)
    }

    /// Get all schedules for a set of app IDs
    func getSchedules(for logicalIDs: Set<String>) -> [String: AppScheduleConfiguration] {
        var result: [String: AppScheduleConfiguration] = [:]
        for id in logicalIDs {
            if let config = schedules[id] {
                result[id] = config
            }
        }
        return result
    }

    /// Batch save multiple configurations (for challenge creation)
    func saveSchedules(_ configs: [AppScheduleConfiguration]) throws {
        for config in configs {
            schedules[config.id] = config
            saveScheduleForExtension(config)
        }
        try persistSchedules()
    }

    /// Create default configurations for a set of app IDs
    func createDefaultConfigs(for logicalIDs: Set<String>, type: AppType) -> [String: AppScheduleConfiguration] {
        var configs: [String: AppScheduleConfiguration] = [:]
        for id in logicalIDs {
            switch type {
            case .learning:
                configs[id] = .defaultLearning(logicalID: id)
            case .reward:
                configs[id] = .defaultReward(logicalID: id)
            }
        }
        return configs
    }

    // MARK: - Private Methods

    private func persistSchedules() throws {
        let configs = Array(schedules.values)
        let data = try JSONEncoder().encode(configs)
        sharedDefaults?.set(data, forKey: userDefaultsKey)
    }

    /// Save individual schedule keys for extension access
    private func saveScheduleForExtension(_ config: AppScheduleConfiguration) {
        let prefix = "schedule_\(config.id)"

        // Daily limit for today
        sharedDefaults?.set(config.dailyLimits.todayLimit, forKey: "\(prefix)_dailyLimit")

        // Time window
        let windowStart = config.allowedTimeWindow.startHour * 60 + config.allowedTimeWindow.startMinute
        let windowEnd = config.allowedTimeWindow.endHour * 60 + config.allowedTimeWindow.endMinute
        sharedDefaults?.set(windowStart, forKey: "\(prefix)_windowStart")
        sharedDefaults?.set(windowEnd, forKey: "\(prefix)_windowEnd")

        // Enabled state
        sharedDefaults?.set(config.isEnabled, forKey: "\(prefix)_enabled")

        // Individual day limits for more granular control
        sharedDefaults?.set(config.dailyLimits.sunday, forKey: "\(prefix)_limitSun")
        sharedDefaults?.set(config.dailyLimits.monday, forKey: "\(prefix)_limitMon")
        sharedDefaults?.set(config.dailyLimits.tuesday, forKey: "\(prefix)_limitTue")
        sharedDefaults?.set(config.dailyLimits.wednesday, forKey: "\(prefix)_limitWed")
        sharedDefaults?.set(config.dailyLimits.thursday, forKey: "\(prefix)_limitThu")
        sharedDefaults?.set(config.dailyLimits.friday, forKey: "\(prefix)_limitFri")
        sharedDefaults?.set(config.dailyLimits.saturday, forKey: "\(prefix)_limitSat")
    }

    private func removeScheduleForExtension(_ logicalID: String) {
        let prefix = "schedule_\(logicalID)"
        let keys = [
            "\(prefix)_dailyLimit",
            "\(prefix)_windowStart",
            "\(prefix)_windowEnd",
            "\(prefix)_enabled",
            "\(prefix)_limitSun",
            "\(prefix)_limitMon",
            "\(prefix)_limitTue",
            "\(prefix)_limitWed",
            "\(prefix)_limitThu",
            "\(prefix)_limitFri",
            "\(prefix)_limitSat"
        ]
        for key in keys {
            sharedDefaults?.removeObject(forKey: key)
        }
    }
}

// MARK: - Supporting Types

enum AppType {
    case learning
    case reward
}
