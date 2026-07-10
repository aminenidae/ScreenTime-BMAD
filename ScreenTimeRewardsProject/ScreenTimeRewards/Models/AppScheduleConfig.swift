import Foundation

// MARK: - Allowed Time Window

/// Represents the time window during which an app is allowed to be used
struct AllowedTimeWindow: Codable, Equatable, Hashable {
    var startHour: Int        // 0-23
    var startMinute: Int      // 0-59
    var endHour: Int          // 0-23
    var endMinute: Int        // 0-59

    /// Full day access (midnight to 11:59 PM)
    static let fullDay = AllowedTimeWindow(startHour: 0, startMinute: 0, endHour: 23, endMinute: 59)

    /// Check if this represents full day access
    var isFullDay: Bool {
        startHour == 0 && startMinute == 0 && endHour == 23 && endMinute == 59
    }

    /// Returns a formatted string for display (e.g., "8:00 AM - 6:00 PM")
    var displayString: String {
        if isFullDay { return String(localized: "All day") }
        return "\(formatTime(hour: startHour, minute: startMinute)) - \(formatTime(hour: endHour, minute: endMinute))"
    }

    private func formatTime(hour: Int, minute: Int) -> String {
        let period = hour >= 12 ? "PM" : "AM"
        let displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
        if minute == 0 {
            return "\(displayHour) \(period)"
        }
        return String(format: "%d:%02d %@", displayHour, minute, period)
    }

    /// Create a Date object for the start time on a given day
    func startDate(on date: Date = Date()) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        components.hour = startHour
        components.minute = startMinute
        return Calendar.current.date(from: components) ?? date
    }

    /// Create a Date object for the end time on a given day
    func endDate(on date: Date = Date()) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        components.hour = endHour
        components.minute = endMinute
        return Calendar.current.date(from: components) ?? date
    }

    /// Check if a given time falls within this window
    func contains(date: Date) -> Bool {
        if isFullDay { return true }
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let totalMinutes = hour * 60 + minute
        let startMinutes = startHour * 60 + startMinute
        let endMinutes = endHour * 60 + endMinute
        return totalMinutes >= startMinutes && totalMinutes <= endMinutes
    }

    /// Duration of the time window in minutes
    var durationInMinutes: Int {
        if isFullDay { return 1440 }  // 24 hours
        let startMinutes = startHour * 60 + startMinute
        let endMinutes = endHour * 60 + endMinute
        return max(0, endMinutes - startMinutes)
    }
}

// MARK: - Daily Time Windows

/// Per-day time windows (mirrors DailyLimits pattern)
struct DailyTimeWindows: Codable, Equatable, Hashable {
    var monday: AllowedTimeWindow
    var tuesday: AllowedTimeWindow
    var wednesday: AllowedTimeWindow
    var thursday: AllowedTimeWindow
    var friday: AllowedTimeWindow
    var saturday: AllowedTimeWindow
    var sunday: AllowedTimeWindow

    /// Create windows with simple weekday/weekend pattern
    init(weekday: AllowedTimeWindow, weekend: AllowedTimeWindow) {
        monday = weekday
        tuesday = weekday
        wednesday = weekday
        thursday = weekday
        friday = weekday
        saturday = weekend
        sunday = weekend
    }

    /// Create windows with individual day values
    init(mon: AllowedTimeWindow, tue: AllowedTimeWindow, wed: AllowedTimeWindow,
         thu: AllowedTimeWindow, fri: AllowedTimeWindow, sat: AllowedTimeWindow, sun: AllowedTimeWindow) {
        monday = mon
        tuesday = tue
        wednesday = wed
        thursday = thu
        friday = fri
        saturday = sat
        sunday = sun
    }

    /// All days full day access
    static let allFullDay = DailyTimeWindows(weekday: .fullDay, weekend: .fullDay)

    /// Get window for a specific weekday (1=Sunday, 7=Saturday, matching Calendar)
    func window(for weekday: Int) -> AllowedTimeWindow {
        switch weekday {
        case 1: return sunday
        case 2: return monday
        case 3: return tuesday
        case 4: return wednesday
        case 5: return thursday
        case 6: return friday
        case 7: return saturday
        default: return monday
        }
    }

    /// Set window for a specific weekday
    mutating func setWindow(_ window: AllowedTimeWindow, for weekday: Int) {
        switch weekday {
        case 1: sunday = window
        case 2: monday = window
        case 3: tuesday = window
        case 4: wednesday = window
        case 5: thursday = window
        case 6: friday = window
        case 7: saturday = window
        default: break
        }
    }

    /// Get window for today
    var todayWindow: AllowedTimeWindow {
        let weekday = Calendar.current.component(.weekday, from: Date())
        return window(for: weekday)
    }

    /// Check if all weekdays have the same window
    var weekdayWindow: AllowedTimeWindow {
        monday
    }

    /// Check if both weekend days have the same window
    var weekendWindow: AllowedTimeWindow {
        saturday
    }

    /// True if this follows a simple weekday/weekend pattern
    var isWeekdayWeekendPattern: Bool {
        let allWeekdaysSame = monday == tuesday && tuesday == wednesday &&
                             wednesday == thursday && thursday == friday
        let bothWeekendSame = saturday == sunday
        return allWeekdaysSame && bothWeekendSame
    }

    /// True if all days have full day access
    var isAllFullDay: Bool {
        monday.isFullDay && tuesday.isFullDay && wednesday.isFullDay &&
        thursday.isFullDay && friday.isFullDay && saturday.isFullDay && sunday.isFullDay
    }

    /// Formatted summary for display
    var displaySummary: String {
        if isAllFullDay {
            return String(localized: "All day")
        }
        if isWeekdayWeekendPattern {
            if weekdayWindow == weekendWindow {
                return weekdayWindow.displayString
            }
            return String(localized: "Weekdays: \(weekdayWindow.displayString), Weekends: \(weekendWindow.displayString)")
        }
        return String(localized: "Custom schedule")
    }
}

// MARK: - Daily Limits

/// Per-day time limits in minutes
struct DailyLimits: Codable, Equatable, Hashable {
    var monday: Int
    var tuesday: Int
    var wednesday: Int
    var thursday: Int
    var friday: Int
    var saturday: Int
    var sunday: Int

    /// Create limits with simple weekday/weekend pattern
    init(weekdayMinutes: Int, weekendMinutes: Int) {
        monday = weekdayMinutes
        tuesday = weekdayMinutes
        wednesday = weekdayMinutes
        thursday = weekdayMinutes
        friday = weekdayMinutes
        saturday = weekendMinutes
        sunday = weekendMinutes
    }

    /// Create limits with individual day values
    init(mon: Int, tue: Int, wed: Int, thu: Int, fri: Int, sat: Int, sun: Int) {
        monday = mon
        tuesday = tue
        wednesday = wed
        thursday = thu
        friday = fri
        saturday = sat
        sunday = sun
    }

    /// Unlimited access (24 hours each day)
    static let unlimited = DailyLimits(weekdayMinutes: 1440, weekendMinutes: 1440)

    /// Common defaults for reward apps (more restricted)
    static let defaultReward = DailyLimits(weekdayMinutes: 60, weekendMinutes: 120)

    /// Get limit for a specific weekday (1=Sunday, 7=Saturday, matching Calendar)
    func limit(for weekday: Int) -> Int {
        switch weekday {
        case 1: return sunday
        case 2: return monday
        case 3: return tuesday
        case 4: return wednesday
        case 5: return thursday
        case 6: return friday
        case 7: return saturday
        default: return monday
        }
    }

    /// Set limit for a specific weekday
    mutating func setLimit(_ minutes: Int, for weekday: Int) {
        switch weekday {
        case 1: sunday = minutes
        case 2: monday = minutes
        case 3: tuesday = minutes
        case 4: wednesday = minutes
        case 5: thursday = minutes
        case 6: friday = minutes
        case 7: saturday = minutes
        default: break
        }
    }

    /// Get limit for today
    var todayLimit: Int {
        let weekday = Calendar.current.component(.weekday, from: Date())
        return limit(for: weekday)
    }

    /// Description of the next day when this app is allowed (limit > 0).
    /// Returns "tomorrow" if tomorrow's limit is non-zero, otherwise the weekday name
    /// (e.g. "Monday") of the next non-zero day within the next 6 days.
    /// Returns nil if every day in the week has a 0 limit (app is permanently off).
    /// Used by the shield to render "Try again on Monday!" instead of "0 minutes today".
    func nextAllowedDayDescription(from referenceDate: Date = Date()) -> String? {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateFormat = "EEEE"

        for offset in 1...7 {
            guard let candidate = calendar.date(byAdding: .day, value: offset, to: referenceDate) else { continue }
            let weekday = calendar.component(.weekday, from: candidate)
            if limit(for: weekday) > 0 {
                return offset == 1 ? "tomorrow" : formatter.string(from: candidate)
            }
        }
        return nil
    }

    /// Check if all weekdays have the same limit
    var weekdayLimit: Int {
        monday
    }

    /// Check if both weekend days have the same limit
    var weekendLimit: Int {
        saturday
    }

    /// True if this follows a simple weekday/weekend pattern
    var isWeekdayWeekendPattern: Bool {
        let allWeekdaysSame = monday == tuesday && tuesday == wednesday &&
                             wednesday == thursday && thursday == friday
        let bothWeekendSame = saturday == sunday
        return allWeekdaysSame && bothWeekendSame
    }

    /// Formatted summary for display
    var displaySummary: String {
        if isWeekdayWeekendPattern {
            if weekdayLimit == weekendLimit {
                return formatMinutes(weekdayLimit) + "/day"
            }
            return "\(formatMinutes(weekdayLimit)) weekdays, \(formatMinutes(weekendLimit)) weekends"
        }
        // Advanced mode - show a brief summary
        let uniqueLimits = Set([monday, tuesday, wednesday, thursday, friday, saturday, sunday])
        if uniqueLimits.count == 1 {
            return formatMinutes(monday) + "/day"
        }
        return String(localized: "Custom schedule")
    }

    private func formatMinutes(_ minutes: Int) -> String {
        if minutes >= 1440 {
            return String(localized: "Unlimited")
        }
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 && mins > 0 {
            return "\(hours)h \(mins)m"
        } else if hours > 0 {
            return "\(hours)h"
        } else {
            return "\(mins)m"
        }
    }
}

// MARK: - Goal Period

/// Time period for unlock requirements (daily or weekly)
enum GoalPeriod: String, Codable, CaseIterable {
    case daily = "daily"
    case weekly = "weekly"

    var displayName: String {
        switch self {
        case .daily: return String(localized: "per day")
        case .weekly: return String(localized: "per week")
        }
    }

    /// Short display name for inline pickers (e.g., "day" or "week")
    var shortDisplayName: String {
        switch self {
        case .daily: return String(localized: "day")
        case .weekly: return String(localized: "week")
        }
    }
}

// MARK: - Linked Learning App

/// Represents a linked learning app with its time requirement and reward earned
struct LinkedLearningApp: Codable, Equatable, Hashable {
    let logicalID: String           // ID of the learning app
    var displayName: String?        // App name for display (synced to parent)
    var minutesRequired: Int        // Goal: minutes needed per period (e.g., 15, 30)
    var goalPeriod: GoalPeriod      // daily or weekly
    var ratioLearningMinutes: Int   // Ratio input: every X minutes of learning...
    var rewardMinutesEarned: Int    // Ratio output: ...grants Y minutes of reward

    static func defaultRequirement(logicalID: String) -> LinkedLearningApp {
        LinkedLearningApp(
            logicalID: logicalID,
            displayName: nil,
            minutesRequired: 15,
            goalPeriod: .daily,
            ratioLearningMinutes: 1,  // Default: every 1 minute...
            rewardMinutesEarned: 1    // ...grants 1 minute (1:1 ratio)
        )
    }

    // Custom Codable to handle backward compatibility
    enum CodingKeys: String, CodingKey {
        case logicalID, displayName, minutesRequired, goalPeriod, ratioLearningMinutes, rewardMinutesEarned
    }

    init(logicalID: String, displayName: String? = nil, minutesRequired: Int, goalPeriod: GoalPeriod, ratioLearningMinutes: Int, rewardMinutesEarned: Int) {
        self.logicalID = logicalID
        self.displayName = displayName
        self.minutesRequired = minutesRequired
        self.goalPeriod = goalPeriod
        self.ratioLearningMinutes = ratioLearningMinutes
        self.rewardMinutesEarned = rewardMinutesEarned
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        logicalID = try container.decode(String.self, forKey: .logicalID)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        minutesRequired = try container.decode(Int.self, forKey: .minutesRequired)
        goalPeriod = try container.decode(GoalPeriod.self, forKey: .goalPeriod)
        // Backward compatibility: default to 1 if not present
        ratioLearningMinutes = try container.decodeIfPresent(Int.self, forKey: .ratioLearningMinutes) ?? 1
        rewardMinutesEarned = try container.decodeIfPresent(Int.self, forKey: .rewardMinutesEarned) ?? 1
    }

    /// Display string for the requirement (e.g., "15m daily → 30m reward")
    var displayString: String {
        let learnStr = formatMinutes(minutesRequired)
        let rewardStr = formatMinutes(rewardMinutesEarned)
        return "\(learnStr) \(goalPeriod.displayName) → \(rewardStr) reward"
    }

    /// Short display for learning requirement only (e.g., "15m daily")
    var learningDisplayString: String {
        let mins = minutesRequired
        if mins >= 60 {
            let hours = mins / 60
            let remainingMins = mins % 60
            if remainingMins > 0 {
                return "\(hours)h \(remainingMins)m \(goalPeriod.displayName)"
            }
            return "\(hours)h \(goalPeriod.displayName)"
        }
        return "\(mins)m \(goalPeriod.displayName)"
    }

    private func formatMinutes(_ mins: Int) -> String {
        if mins >= 60 {
            let hours = mins / 60
            let remainingMins = mins % 60
            if remainingMins > 0 {
                return "\(hours)h \(remainingMins)m"
            }
            return "\(hours)h"
        }
        return "\(mins)m"
    }
}

// MARK: - Unlock Mode

/// Unlock mode for reward apps (AND vs OR logic)
enum UnlockMode: String, Codable, CaseIterable {
    case all = "all"   // Must use ALL linked learning apps
    case any = "any"   // Can use ANY ONE of the linked apps

    var displayName: String {
        switch self {
        case .all: return String(localized: "Use all apps")
        case .any: return String(localized: "Use any one app")
        }
    }

    var description: String {
        switch self {
        case .all: return String(localized: "Child must complete all linked apps")
        case .any: return String(localized: "Child can complete any one linked app")
        }
    }
}

// MARK: - App Schedule Configuration

/// Complete schedule configuration for a single app
struct AppScheduleConfiguration: Codable, Equatable, Identifiable, Hashable {
    let id: String  // logicalID of the app
    var allowedTimeWindow: AllowedTimeWindow       // Simple mode: same window all days
    var dailyTimeWindows: DailyTimeWindows         // Advanced mode: per-day windows
    var useAdvancedTimeWindowConfig: Bool          // false = simple, true = per-day
    var dailyLimits: DailyLimits
    var isEnabled: Bool
    var useAdvancedDayConfig: Bool  // false = weekday/weekend mode for limits

    // Linked learning apps (for reward apps only)
    var linkedLearningApps: [LinkedLearningApp]  // Each with its own time requirement
    var unlockMode: UnlockMode                    // AND (all) or OR (any)

    // Streak configuration (for reward apps only)
    var streakSettings: AppStreakSettings?

    // Learning-to-reward ratio (meaningful for learning apps only)
    // Defines how much reward time each minute of learning earns
    var ratioLearningMinutes: Int   // every X minutes of learning...
    var rewardMinutesEarned: Int    // ...grants Y minutes of reward

    /// Create a new configuration for an app
    init(
        logicalID: String,
        allowedTimeWindow: AllowedTimeWindow = .fullDay,
        dailyTimeWindows: DailyTimeWindows = .allFullDay,
        useAdvancedTimeWindowConfig: Bool = false,
        dailyLimits: DailyLimits = .unlimited,
        isEnabled: Bool = true,
        useAdvancedDayConfig: Bool = false,
        linkedLearningApps: [LinkedLearningApp] = [],
        unlockMode: UnlockMode = .all,
        streakSettings: AppStreakSettings? = nil,
        ratioLearningMinutes: Int = 1,
        rewardMinutesEarned: Int = 1
    ) {
        self.id = logicalID
        self.allowedTimeWindow = allowedTimeWindow
        self.dailyTimeWindows = dailyTimeWindows
        self.useAdvancedTimeWindowConfig = useAdvancedTimeWindowConfig
        self.dailyLimits = dailyLimits
        self.isEnabled = isEnabled
        self.useAdvancedDayConfig = useAdvancedDayConfig
        self.linkedLearningApps = linkedLearningApps
        self.unlockMode = unlockMode
        self.streakSettings = streakSettings
        self.ratioLearningMinutes = ratioLearningMinutes
        self.rewardMinutesEarned = rewardMinutesEarned
    }

    // Custom Codable for backward compatibility (ratio fields may be missing in old data)
    enum CodingKeys: String, CodingKey {
        case id, allowedTimeWindow, dailyTimeWindows, useAdvancedTimeWindowConfig
        case dailyLimits, isEnabled, useAdvancedDayConfig
        case linkedLearningApps, unlockMode, streakSettings
        case ratioLearningMinutes, rewardMinutesEarned
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        allowedTimeWindow = try container.decode(AllowedTimeWindow.self, forKey: .allowedTimeWindow)
        dailyTimeWindows = try container.decode(DailyTimeWindows.self, forKey: .dailyTimeWindows)
        useAdvancedTimeWindowConfig = try container.decode(Bool.self, forKey: .useAdvancedTimeWindowConfig)
        dailyLimits = try container.decode(DailyLimits.self, forKey: .dailyLimits)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        useAdvancedDayConfig = try container.decode(Bool.self, forKey: .useAdvancedDayConfig)
        linkedLearningApps = try container.decodeIfPresent([LinkedLearningApp].self, forKey: .linkedLearningApps) ?? []
        unlockMode = try container.decodeIfPresent(UnlockMode.self, forKey: .unlockMode) ?? .all
        streakSettings = try container.decodeIfPresent(AppStreakSettings.self, forKey: .streakSettings)
        ratioLearningMinutes = try container.decodeIfPresent(Int.self, forKey: .ratioLearningMinutes) ?? 1
        rewardMinutesEarned = try container.decodeIfPresent(Int.self, forKey: .rewardMinutesEarned) ?? 1
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(allowedTimeWindow, forKey: .allowedTimeWindow)
        try container.encode(dailyTimeWindows, forKey: .dailyTimeWindows)
        try container.encode(useAdvancedTimeWindowConfig, forKey: .useAdvancedTimeWindowConfig)
        try container.encode(dailyLimits, forKey: .dailyLimits)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(useAdvancedDayConfig, forKey: .useAdvancedDayConfig)
        try container.encode(linkedLearningApps, forKey: .linkedLearningApps)
        try container.encode(unlockMode, forKey: .unlockMode)
        try container.encodeIfPresent(streakSettings, forKey: .streakSettings)
        try container.encode(ratioLearningMinutes, forKey: .ratioLearningMinutes)
        try container.encode(rewardMinutesEarned, forKey: .rewardMinutesEarned)
    }

    /// Get the effective time window for a specific weekday
    func effectiveTimeWindow(for weekday: Int) -> AllowedTimeWindow {
        if useAdvancedTimeWindowConfig {
            return dailyTimeWindows.window(for: weekday)
        }
        return allowedTimeWindow
    }

    /// Get today's effective time window
    var todayTimeWindow: AllowedTimeWindow {
        let weekday = Calendar.current.component(.weekday, from: Date())
        return effectiveTimeWindow(for: weekday)
    }

    /// Default configuration for learning apps (requires setup)
    static func defaultLearning(logicalID: String) -> AppScheduleConfiguration {
        AppScheduleConfiguration(
            logicalID: logicalID,
            allowedTimeWindow: .fullDay,
            dailyLimits: .unlimited,
            isEnabled: true,
            useAdvancedDayConfig: false
        )
    }

    /// Default configuration for reward apps (more restricted)
    static func defaultReward(logicalID: String) -> AppScheduleConfiguration {
        AppScheduleConfiguration(
            logicalID: logicalID,
            allowedTimeWindow: .fullDay,
            dailyLimits: .defaultReward,
            isEnabled: true,
            useAdvancedDayConfig: false,
            streakSettings: .defaultSettings  // Enable by default for new reward apps
        )
    }

    /// Brief summary for display in app row
    var displaySummary: String {
        var parts: [String] = []

        // Time window summary
        if useAdvancedTimeWindowConfig {
            if !dailyTimeWindows.isAllFullDay {
                parts.append(dailyTimeWindows.displaySummary)
            }
        } else if !allowedTimeWindow.isFullDay {
            parts.append(allowedTimeWindow.displayString)
        }

        parts.append(dailyLimits.displaySummary)

        // Add linked apps info for reward apps
        if !linkedLearningApps.isEmpty {
            let count = linkedLearningApps.count
            parts.append("\(count) app\(count == 1 ? "" : "s") to unlock")
        }

        return parts.joined(separator: " | ")
    }

    /// Check if app is currently allowed based on time window
    var isCurrentlyInAllowedWindow: Bool {
        todayTimeWindow.contains(date: Date())
    }

    /// Whether this reward app is blocked (no linked learning apps)
    var isRewardBlocked: Bool {
        linkedLearningApps.isEmpty
    }

    /// Summary of unlock requirements for display
    var unlockSummary: String? {
        guard !linkedLearningApps.isEmpty else { return nil }

        let count = linkedLearningApps.count
        let modeText = unlockMode == .all ? "all" : "any"
        return String(localized: "Complete \(modeText) \(count) app\(count == 1 ? "" : "s")")
    }
}

// MARK: - App Schedule Version (history)

/// Frozen snapshot of an app's schedule at a point in time.
///
/// Phase 2 of the bank-fix plan: each `saveSchedule(...)` appends one of these to a
/// per-app history array. Historical bank computations look up the version active
/// on each day (`effectiveFromDay <= row.date`) instead of re-pricing past learning
/// at the current ratio.
///
/// Stored as JSON in App Group UserDefaults under key `AppScheduleVersions`.
/// Synced to CloudKit via the `CD_scheduleVersionsJSON` field on `CD_AppConfiguration`.
struct AppScheduleVersion: Codable, Equatable, Hashable {
    /// Logical ID of the app this version describes. Matches `AppScheduleConfiguration.id`.
    let logicalID: String

    /// Day this version takes effect, in `yyyy-MM-dd` (device local time).
    /// `versionActive(on: day)` returns the most recent version whose
    /// `effectiveFromDay <= day`. Seed migration uses `"1970-01-01"`.
    let effectiveFromDay: String

    /// The schedule values at that effective date.
    let ratioLearningMinutes: Int
    let rewardMinutesEarned: Int
    let linkedLearningApps: [LinkedLearningApp]
    let dailyLimits: DailyLimits
    let dailyTimeWindows: DailyTimeWindows
    let allowedTimeWindow: AllowedTimeWindow
    let unlockMode: UnlockMode

    /// When this version was written. Audit only; bank math uses `effectiveFromDay`.
    let createdAt: Date

    /// Effective ratio (1.0 = 1 reward minute per 1 learning minute).
    var ratio: Double {
        Double(rewardMinutesEarned) / Double(max(1, ratioLearningMinutes))
    }

    /// Build a version from a current schedule, with a chosen effectivity day.
    init(
        from schedule: AppScheduleConfiguration,
        effectiveFromDay: String,
        createdAt: Date = Date()
    ) {
        self.logicalID = schedule.id
        self.effectiveFromDay = effectiveFromDay
        self.ratioLearningMinutes = schedule.ratioLearningMinutes
        self.rewardMinutesEarned = schedule.rewardMinutesEarned
        self.linkedLearningApps = schedule.linkedLearningApps
        self.dailyLimits = schedule.dailyLimits
        self.dailyTimeWindows = schedule.dailyTimeWindows
        self.allowedTimeWindow = schedule.allowedTimeWindow
        self.unlockMode = schedule.unlockMode
        self.createdAt = createdAt
    }

    /// Memberwise initializer for decoding/manual construction.
    init(
        logicalID: String,
        effectiveFromDay: String,
        ratioLearningMinutes: Int,
        rewardMinutesEarned: Int,
        linkedLearningApps: [LinkedLearningApp],
        dailyLimits: DailyLimits,
        dailyTimeWindows: DailyTimeWindows,
        allowedTimeWindow: AllowedTimeWindow,
        unlockMode: UnlockMode,
        createdAt: Date
    ) {
        self.logicalID = logicalID
        self.effectiveFromDay = effectiveFromDay
        self.ratioLearningMinutes = ratioLearningMinutes
        self.rewardMinutesEarned = rewardMinutesEarned
        self.linkedLearningApps = linkedLearningApps
        self.dailyLimits = dailyLimits
        self.dailyTimeWindows = dailyTimeWindows
        self.allowedTimeWindow = allowedTimeWindow
        self.unlockMode = unlockMode
        self.createdAt = createdAt
    }
}

extension AppScheduleVersion {
    /// `yyyy-MM-dd` formatter shared across version writes/reads. UTC-stable so
    /// device-local midnight transitions don't shift the bucket.
    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        return f
    }()

    /// Convert a `Date` to the day key used in `effectiveFromDay`.
    static func dayKey(for date: Date) -> String {
        dayFormatter.string(from: date)
    }

    /// Today's day key.
    static var todayKey: String {
        dayKey(for: Date())
    }

    /// Tomorrow's day key.
    static var tomorrowKey: String {
        dayKey(for: Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date())
    }

    /// Sentinel "always-effective" day for the seed migration row.
    static let earliestDay = "1970-01-01"
}
