import Foundation
import CoreData
import Combine

@MainActor
class StreakService: ObservableObject {
    static let shared = StreakService()
    
    // Per-app streak records cache (key: appLogicalID)
    @Published private(set) var streakRecords: [String: StreakRecord] = [:]
    
    private let userDefaults = UserDefaults(suiteName: "group.com.screentimerewards.shared")
    private let context = PersistenceController.shared.container.viewContext
    
    private var midnightTimer: Timer?
    
    init() {
        setupMidnightTimer()
    }

    deinit {
        midnightTimer?.invalidate()
    }
    
    // MARK: - Bonus Management
    
    func grantBonusMinutes(_ minutes: Int, for appLogicalID: String) {
        let key = "streak_bonus_\(appLogicalID)"
        let current = userDefaults?.integer(forKey: key) ?? 0
        userDefaults?.set(current + minutes, forKey: key)
        
        NotificationCenter.default.post(
            name: Notification.Name("StreakBonusGranted"),
            object: nil,
            userInfo: ["appLogicalID": appLogicalID, "minutes": minutes]
        )
    }
    
    func getTotalBonusMinutes(for appLogicalID: String) -> Int {
        let key = "streak_bonus_\(appLogicalID)"
        return userDefaults?.integer(forKey: key) ?? 0
    }
    
    // MARK: - Streak Logic
    
    func checkAndUpdateStreak(
        goalsCompleted: Bool,
        for childDeviceID: String,
        appLogicalID: String,
        settings: AppStreakSettings
    ) {
        guard settings.isEnabled else { return }
        
        let record = getOrCreateStreakRecord(for: childDeviceID, appLogicalID: appLogicalID)
        let calendar = Calendar.current
        let today = Date()
        
        // Check if already updated today
        if let lastDate = record.lastActivityDate, calendar.isDateInToday(lastDate) {
            // Already handled today, just ensure it's in our cache
            streakRecords[appLogicalID] = record
            return
        }
        
        if goalsCompleted {
            // Check if yesterday was completed to increment, otherwise reset (unless it's the first day)
            let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
            
            var newStreak: Int16 = 1
            if let lastDate = record.lastActivityDate, calendar.isDate(lastDate, inSameDayAs: yesterday) {
                newStreak = record.currentStreak + 1
            } else if let lastDate = record.lastActivityDate, calendar.isDateInToday(lastDate) {
                 // Should be caught by the first check, but just in case
                 newStreak = record.currentStreak
            }
            
            record.currentStreak = newStreak
            record.lastActivityDate = today
            
            if newStreak > record.longestStreak {
                record.longestStreak = newStreak
            }
            
            saveContext()
            streakRecords[appLogicalID] = record
        }
    }
    
    // MARK: - Milestones & Bonuses
    
    // MARK: - Milestones & Bonuses
    
    func checkMilestoneAchievement(
        for appLogicalID: String,
        settings: AppStreakSettings
    ) -> Int? {
        guard let record = streakRecords[appLogicalID] else { return nil }
        let current = Int(record.currentStreak)
        
        // Recurring milestone check:
        // Returns true if current streak is a multiple of cycle days
        if current > 0 && current % settings.streakCycleDays == 0 {
            return current
        }
        return nil
    }
    
    func shouldApplyBonus(
        for milestone: Int,
        appLogicalID: String,
        settings: AppStreakSettings
    ) -> Bool {
        // With recurring milestones, we can allow claiming every time the cycle completes.
        // However, to prevent double-claiming on the same day due to multiple checks,
        // we persist claimed milestones.
        return !settings.earnedMilestones.contains(milestone)
    }
    
    func calculateBonusMinutes(
        earnedMinutes: Int,
        settings: AppStreakSettings,
        multiplier: Int = 1
    ) -> Int {
        var bonus: Double = 0
        
        switch settings.bonusType {
        case .percentage:
            // (Daily Reward * Percentage) * Streak Length
            let dailyBonus = Double(earnedMinutes) * (Double(settings.bonusValue) / 100.0)
            bonus = dailyBonus * Double(multiplier)
            
        case .fixedMinutes:
            // Fixed Amount per day * Streak Length
            // e.g. 5 mins per day * 7 days = 35 mins
            bonus = Double(settings.bonusValue) * Double(multiplier)
        }
        
        return Int(bonus)
    }
    
    func markMilestoneEarned(
        _ milestone: Int,
        for appLogicalID: String,
        settings: AppStreakSettings
    ) {
        // Since settings are a struct, we need to update the source.
        // However, settings are passed in. In a real app, we'd update AppScheduleConfig.
        // For now, we update via AppScheduleService.
        
        var updatedSettings = settings
        updatedSettings.earnedMilestones.insert(milestone)
        
        if var config = AppScheduleService.shared.getSchedule(for: appLogicalID) {
            config.streakSettings = updatedSettings
            try? AppScheduleService.shared.saveSchedule(config)
        }
    }
    
    // MARK: - Core Data Helper
    
    func getOrCreateStreakRecord(
        for childDeviceID: String,
        appLogicalID: String
    ) -> StreakRecord {
        let request: NSFetchRequest<StreakRecord> = StreakRecord.fetchRequest()
        request.predicate = NSPredicate(
            format: "childDeviceID == %@ AND appLogicalID == %@",
            childDeviceID,
            appLogicalID
        )
        request.fetchLimit = 1
        
        do {
            let results = try context.fetch(request)
            if let record = results.first {
                return record
            }
        } catch {
            print("Error fetching streak record: \(error)")
        }
        
        let newRecord = StreakRecord(context: context)
        newRecord.childDeviceID = childDeviceID
        newRecord.appLogicalID = appLogicalID
        newRecord.currentStreak = 0
        newRecord.longestStreak = 0
        newRecord.streakID = UUID().uuidString
        
        return newRecord
    }
    
    private func saveContext() {
        do {
            try context.save()
        } catch {
            print("Error saving streak context: \(error)")
        }
    }
    
    // MARK: - Load & Aggregate
    
    // Load all streak records for a child
    func loadStreaksForChild(childDeviceID: String) {
        let request: NSFetchRequest<StreakRecord> = StreakRecord.fetchRequest()
        request.predicate = NSPredicate(format: "childDeviceID == %@", childDeviceID)
        
        do {
            let records = try context.fetch(request)
            var newRecords: [String: StreakRecord] = [:]
            
            for record in records {
                if let appID = record.appLogicalID {
                    newRecords[appID] = record
                }
            }
            
            self.streakRecords = newRecords
        } catch {
            print("Error loading streaks for child: \(error)")
        }
    }

    // Get aggregate stats across all apps (for child dashboard)
    func getAggregateStreak(for childDeviceID: String) -> (current: Int, longest: Int, isAtRisk: Bool) {
        guard !streakRecords.isEmpty else { return (0, 0, false) }
        
        var maxCurrent = 0
        var maxLongest = 0
        var anyAtRisk = false
        
        for record in streakRecords.values {
            if record.currentStreak > maxCurrent {
                maxCurrent = Int(record.currentStreak)
            }
            if record.longestStreak > maxLongest {
                maxLongest = Int(record.longestStreak)
            }
            if record.isAtRisk {
                anyAtRisk = true
            }
        }
        
        return (maxCurrent, maxLongest, anyAtRisk)
    }
    
    // MARK: - Midnight Timer
    
    private func setupMidnightTimer() {
        let calendar = Calendar.current
        let now = Date()
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
              let nextMidnight = calendar.date(bySettingHour: 0, minute: 0, second: 1, of: tomorrow) else { return }
        
        let interval = nextMidnight.timeIntervalSince(now)
        
        midnightTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.handleMidnightReset()
                self?.setupMidnightTimer() // Schedule next one
            }
        }
    }
    
    private func handleMidnightReset() {
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: Date())!
        
        for record in streakRecords.values {
            if let lastDate = record.lastActivityDate {
                if !calendar.isDate(lastDate, inSameDayAs: yesterday) && !calendar.isDateInToday(lastDate) {
                     // Missed a day
                     record.currentStreak = 0
                }
            }
        }
        saveContext()
    }
}

extension StreakService {
    /// Get the next uncompleted milestone for a specific current streak value
    func getNextMilestone(for currentStreak: Int, settings: AppStreakSettings) -> Int? {
        // Next multiple of cycle days
        let cycle = settings.streakCycleDays
        let next = ((currentStreak / cycle) + 1) * cycle
        return next
    }
    
    /// Backward compatible overload using default settings
    func getNextMilestone(for currentStreak: Int) -> Int? {
        return getNextMilestone(for: currentStreak, settings: .defaultSettings)
    }

    /// Calculate progress toward next milestone (0.0 to 1.0)
    func progressToNextMilestone(current: Int, settings: AppStreakSettings) -> Double {
        let cycle = settings.streakCycleDays
        
        // Previous milestone is the start of current cycle
        // e.g. if cycle=7, current=13, prev=7, next=14
        // e.g. if cycle=7, current=4, prev=0, next=7
        let previous = (current / cycle) * cycle
        let next = previous + cycle
        
        // If we just hit a milestone today (current == previous), we are at 100% (or 0% of next?)
        // Usually progress is for the UPCOMING milestone.
        // If current=7, prev=7, next=14. Progress=0/7 = 0%.
        // But if we want to show "full circle" on the day of milestone, UI handles that.
        
        let range = Double(next - previous)
        let progress = Double(current - previous)

        return range > 0 ? min(progress / range, 1.0) : 0.0
    }
    
    /// Backward compatible overload using default settings
    func progressToNextMilestone(current: Int) -> Double {
        return progressToNextMilestone(current: current, settings: .defaultSettings)
    }

    /// Post notification when milestone achieved (includes app context)
    func notifyMilestoneAchieved(milestone: Int, bonusMinutes: Int, appLogicalID: String) {
        NotificationCenter.default.post(
            name: .streakMilestoneAchieved,
            object: nil,
            userInfo: [
                "milestone": milestone,
                "bonusMinutes": bonusMinutes,
                "appLogicalID": appLogicalID
            ]
        )
    }
}



// Add notification name
extension Notification.Name {
    static let streakMilestoneAchieved = Notification.Name("streakMilestoneAchieved")
}