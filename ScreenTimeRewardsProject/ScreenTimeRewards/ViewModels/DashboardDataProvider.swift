import Foundation
import SwiftUI

// MARK: - Dashboard Data Provider Protocol

/// Protocol abstracting dashboard data for both local (child device) and remote (parent device) contexts.
/// This enables a unified dashboard view that works with different data sources.
@MainActor
protocol DashboardDataProvider: ObservableObject {
    // MARK: - Usage Overview (Section 1)

    /// Total learning app usage today in seconds
    var learningTimeSeconds: Int { get }

    /// Total reward app usage today in seconds
    var rewardTimeSeconds: Int { get }

    /// Detailed list of learning apps with usage data
    var learningAppDetails: [AppUsageDetail] { get }

    /// Detailed list of reward apps with usage data
    var rewardAppDetails: [AppUsageDetail] { get }

    // MARK: - Time Bank (Section 2)

    /// Total minutes earned from completing learning goals
    var earnedMinutes: Int { get }

    /// Total minutes used on reward apps
    var usedMinutes: Int { get }

    /// Bonus minutes earned from streaks
    var streakBonusMinutes: Int { get }

    /// Available balance (earned + bonus - used)
    var availableMinutes: Int { get }

    // MARK: - Streaks Summary (Section 3)

    /// Current consecutive days with goal completion
    var currentStreak: Int { get }

    /// All-time longest streak
    var longestStreak: Int { get }

    /// Whether the current streak is at risk (no activity today yet)
    var isStreakAtRisk: Bool { get }

    /// Progress toward next milestone (0.0 to 1.0)
    var streakProgress: Double { get }

    /// Days in the streak cycle (e.g., 7 for weekly milestones)
    var milestoneCycleDays: Int { get }

    /// Potential bonus minutes for reaching next milestone
    var potentialBonusMinutes: Int { get }

    // MARK: - Daily/Weekly Trends (Section 4)

    /// Daily totals for charting (most recent first)
    var dailyTotals: [DailyUsageTotals] { get }

    // MARK: - Context Info

    /// Whether this is a remote context (parent device viewing child)
    var isRemoteContext: Bool { get }

    /// Device name (for remote context)
    var deviceName: String? { get }

    /// Loading state
    var isLoading: Bool { get }

    /// Error message if any
    var errorMessage: String? { get }

    // MARK: - Actions

    /// Refresh all data
    func refresh() async
}

// MARK: - Supporting Data Structures

/// Unified app usage detail for drill-down views
struct AppUsageDetail: Identifiable {
    let id: String  // logicalID or tokenHash
    let displayName: String
    let category: AppCategory
    let todaySeconds: Int
    let iconURL: String?
    let pointsPerMinute: Int
    let earnedPoints: Int

    enum AppCategory: String, Identifiable {
        case learning = "Learning"
        case reward = "Reward"

        var id: String { rawValue }
    }
}

/// Daily usage totals for charting
struct DailyUsageTotals: Identifiable {
    let date: Date
    let learningSeconds: Int
    let rewardSeconds: Int

    var id: Date { date }

    var learningMinutes: Int { learningSeconds / 60 }
    var rewardMinutes: Int { rewardSeconds / 60 }
}

// MARK: - Default Implementations

extension DashboardDataProvider {
    /// Default implementation: earned + bonus - used
    var availableMinutes: Int {
        max(earnedMinutes + streakBonusMinutes - usedMinutes, 0)
    }

    /// Default: no device name for local context
    var deviceName: String? { nil }

    /// Default: no error
    var errorMessage: String? { nil }
}
