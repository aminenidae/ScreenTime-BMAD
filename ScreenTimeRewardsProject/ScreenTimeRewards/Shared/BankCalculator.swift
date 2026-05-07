import Foundation

/// Single source of truth for the Time Bank balance calculation.
///
/// `BankCalculator.computeBank(_:)` is a pure function — no UserDefaults, no
/// snapshots, no globals. Caller gathers raw inputs and gets one Int back. Used
/// by:
///   - `AppUsageViewModel.cumulativeAvailableMinutes` (dashboard "Time Bank: N")
///   - `BlockingCoordinator.checkAvailableMinutes` (main-app shield decision)
///   - `DeviceActivityMonitorExtension.computeEffectivePoolBalance` (extension shield decision)
///
/// All three pass identical inputs ⇒ all three see identical outputs. No drift
/// possible. Was historically three separate copies of "byte-equivalent"
/// algorithms that quietly diverged — see `docs/UNIFIED_USAGE_COUNTER_PLAN.md`.
public enum BankCalculator {

    /// Pure description of one reward app's goal config, in terms BankCalculator
    /// understands. Build from extension's `ExtensionGoalConfigMinimal`,
    /// main-app's `AppScheduleConfiguration`, or wherever — keep this struct
    /// minimal so it never carries presentation logic.
    public struct GoalConfigInput {
        public let rewardAppLogicalID: String
        /// `linkedLearningApps` filtered by category — entries whose logicalID
        /// is also a reward app must be excluded BEFORE construction. See the
        /// May 6, 2026 stale-reference bug in `docs/SMART_THRESHOLD_FILTERING.md`.
        public let linkedLearning: [LinkedLearning]

        public init(rewardAppLogicalID: String, linkedLearning: [LinkedLearning]) {
            self.rewardAppLogicalID = rewardAppLogicalID
            self.linkedLearning = linkedLearning
        }

        public struct LinkedLearning {
            public let learningAppLogicalID: String
            public let minutesRequired: Int

            public init(learningAppLogicalID: String, minutesRequired: Int) {
                self.learningAppLogicalID = learningAppLogicalID
                self.minutesRequired = minutesRequired
            }
        }
    }

    public struct Inputs {
        /// Today's credited usage in seconds, keyed by logicalID. Both learning
        /// and reward apps go in the same dictionary — BankCalculator looks them
        /// up by ID. Missing keys are treated as 0 seconds.
        public let todaySecondsByLogicalID: [String: Int]

        /// All goal configs for the current reward apps. The set of reward apps
        /// is derived from `goalConfigs.map { $0.rewardAppLogicalID }`.
        public let goalConfigs: [GoalConfigInput]

        /// Per-learning-app reward ratio (rewardMinutes per learningMinute).
        /// Falls back to 1.0 for unknown IDs.
        public let ratioByLearningLogicalID: [String: Double]

        /// Pre-computed historical bank balance in minutes (>= 0). Caller is
        /// responsible for the historical math — BankCalculator doesn't touch
        /// it. Typically this is the WIP baseline+delta value or a simple
        /// sum-of-history value.
        public let historicalRemainingMinutes: Int

        public init(
            todaySecondsByLogicalID: [String: Int],
            goalConfigs: [GoalConfigInput],
            ratioByLearningLogicalID: [String: Double],
            historicalRemainingMinutes: Int
        ) {
            self.todaySecondsByLogicalID = todaySecondsByLogicalID
            self.goalConfigs = goalConfigs
            self.ratioByLearningLogicalID = ratioByLearningLogicalID
            self.historicalRemainingMinutes = historicalRemainingMinutes
        }
    }

    /// Compute the Time Bank balance.
    ///
    /// Algorithm (matches the May 6, 2026 unified design):
    ///   1. For each unique learning app across all goal configs, find the
    ///      LOWEST `minutesRequired` threshold. (A learning app linked to
    ///      multiple reward apps with different thresholds clears at the
    ///      easiest one.)
    ///   2. For each unique learning app whose `todaySeconds / 60 >= lowest
    ///      threshold`, add `usageMinutes * ratio` to `todayEarned`.
    ///   3. Sum every reward app's `todaySeconds / 60` into `todayUsed`.
    ///   4. Return `max(0, historical + todayEarned − todayUsed)`.
    ///
    /// Stale-reference filter: callers MUST drop linkedLearning entries whose
    /// logicalID is also a reward app (e.g. left over from a learning→reward
    /// category flip). BankCalculator does NOT re-filter — it trusts inputs.
    /// This matches the runtime defense in
    /// `DeviceActivityMonitorExtension.checkGoalMet` and
    /// `BlockingCoordinator.checkLearningGoal`, applied at the input boundary
    /// rather than inside the math.
    public static func computeBank(_ inputs: Inputs) -> Int {
        // Step 1 — lowest threshold per unique learning app
        var lowestThresholdByLearningID: [String: Int] = [:]
        for goal in inputs.goalConfigs {
            for link in goal.linkedLearning {
                let prior = lowestThresholdByLearningID[link.learningAppLogicalID] ?? Int.max
                lowestThresholdByLearningID[link.learningAppLogicalID] = min(prior, link.minutesRequired)
            }
        }

        // Step 2 — sum today's earned (unique per learning app)
        var todayEarnedMinutes = 0
        for (learningID, threshold) in lowestThresholdByLearningID {
            let seconds = inputs.todaySecondsByLogicalID[learningID] ?? 0
            let usageMinutes = seconds / 60
            guard usageMinutes >= threshold else { continue }
            let ratio = inputs.ratioByLearningLogicalID[learningID] ?? 1.0
            todayEarnedMinutes += Int(Double(usageMinutes) * ratio)
        }

        // Step 3 — sum today's reward usage
        var todayUsedMinutes = 0
        for goal in inputs.goalConfigs {
            let seconds = inputs.todaySecondsByLogicalID[goal.rewardAppLogicalID] ?? 0
            todayUsedMinutes += seconds / 60
        }

        // Step 4 — clamp at 0
        return max(0, inputs.historicalRemainingMinutes + todayEarnedMinutes - todayUsedMinutes)
    }
}
