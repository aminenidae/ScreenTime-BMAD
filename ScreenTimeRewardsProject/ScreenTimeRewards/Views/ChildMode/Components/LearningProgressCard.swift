import SwiftUI
import FamilyControls
import ManagedSettings

struct LearningProgressCard: View {
    let linkedLearningApps: [LinkedLearningApp]
    let learningProgress: [String: (used: Int, required: Int, goalMet: Bool)] // Key: logicalID
    let learningAppTokens: [String: ApplicationToken]
    let unlockMode: UnlockMode
    let isUnlocked: Bool
    /// Real reason this app is blocked — when known and not goal-related, the
    /// header reflects that instead of falsely showing "Finish your goal" while
    /// the goal is already met (e.g. blocked by daily limit / downtime).
    var blockingReason: BlockingReasonType? = nil
    /// Used to disambiguate `.dailyLimitReached` when limit is 0 (parent-disabled,
    /// not "used up the limit").
    var dailyLimit: Int = -1
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            headerSection

            // Progress bars for each linked app
            ForEach(linkedLearningApps, id: \.logicalID) { linkedApp in
                learningAppProgressRow(for: linkedApp)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(AppTheme.card(for: colorScheme))
        )
    }

    /// True when the linked-learning goal(s) are met for the current unlock mode.
    /// Used to detect "goal met but app still blocked" — the lock must come from
    /// a non-goal source (daily limit, downtime, …).
    private var goalsMet: Bool {
        guard !linkedLearningApps.isEmpty else { return true }
        let metCount = linkedLearningApps.filter { learningProgress[$0.logicalID]?.goalMet ?? false }.count
        switch unlockMode {
        case .all: return metCount == linkedLearningApps.count
        case .any: return metCount >= 1
        }
    }

    /// Header copy adapts to: shield state × number of linked apps × unlock mode ×
    /// real blocking reason. When the goal is already met, surface the actual
    /// reason (daily limit / downtime / etc.) instead of falsely saying
    /// "Finish your goal".
    private var headerText: String {
        let multi = linkedLearningApps.count >= 2
        if isUnlocked {
            switch (multi, unlockMode) {
            case (false, _):       return "UNLOCKED — GOAL REACHED"
            case (true, .all):     return "UNLOCKED — ALL GOALS REACHED"
            case (true, .any):     return "UNLOCKED — GOAL REACHED"
            }
        }

        // Locked. If the real blocking reason is known and isn't goal-related,
        // show that instead — the goal might already be met.
        if let reason = blockingReason {
            switch reason {
            case .downtime:         return "APP IN DOWNTIME"
            case .dailyLimitReached:
                return dailyLimit == 0 ? "BLOCKED FOR TODAY" : "DAILY LIMIT REACHED"
            case .rewardTimeExpired: return "REWARD TIME EXPIRED"
            case .learningGoal:
                break // fall through to goal-not-met copy
            }
        }

        // No reason given, or reason is goal-not-met. If goals look met, the lock
        // is somewhere else we can't name — show neutral copy.
        if goalsMet {
            return "GOAL REACHED — STILL LOCKED"
        }

        switch (multi, unlockMode) {
        case (false, _):       return "FINISH YOUR GOAL TO UNLOCK"
        case (true, .all):     return "FINISH ALL GOALS TO UNLOCK"
        case (true, .any):     return "FINISH ANY GOAL TO UNLOCK"
        }
    }

    private var headerSection: some View {
        HStack(spacing: 8) {
            Image(systemName: isUnlocked ? "checkmark.circle.fill" : "book.fill")
                .font(.system(size: 16))
                .foregroundColor(isUnlocked ? AppTheme.vibrantTeal : AppTheme.brandedText(for: colorScheme))

            Text(headerText)
                .font(.system(size: 13, weight: .bold))
                .tracking(1.5)
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))

            Spacer()
        }
    }

    private func learningAppProgressRow(for linkedApp: LinkedLearningApp) -> some View {
        let progress = learningProgress[linkedApp.logicalID] ?? (0, linkedApp.minutesRequired, false)
        let percentage = progress.required > 0 ? Double(progress.used) / Double(progress.required) : 0
        let appName = AppNameMappingService.shared.getDisplayName(for: linkedApp.logicalID, defaultName: "Learning App")

        return VStack(alignment: .leading, spacing: 8) {
            // App name and status
            HStack {
                // Icon placeholder
                if let token = learningAppTokens[linkedApp.logicalID], #available(iOS 15.2, *) {
                    Label(token)
                        .labelStyle(.iconOnly)
                        .scaleEffect(2.0)
                        .frame(width: 64, height: 64)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(AppTheme.vibrantTeal.opacity(0.2), lineWidth: 1))
                } else {
                    Circle()
                        .fill(AppTheme.vibrantTeal.opacity(0.2))
                        .frame(width: 64, height: 64)
                        .overlay(
                            Image(systemName: "book.fill")
                                .font(.system(size: 28))
                                .foregroundColor(AppTheme.brandedText(for: colorScheme))
                        )
                }

                VStack(alignment: .leading, spacing: 2) {
                    if let token = learningAppTokens[linkedApp.logicalID], #available(iOS 15.2, *) {
                        Label(token)
                            .labelStyle(.titleOnly)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                            .lineLimit(1)
                    } else {
                        Text(appName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                            .lineLimit(1)
                    }

                    Text("\(linkedApp.goalPeriod.displayName)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                }

                Spacer()

                if progress.goalMet {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(AppTheme.brandedText(for: colorScheme))
                }
            }

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 8)
                        .fill(AppTheme.vibrantTeal.opacity(0.1))
                        .frame(height: 24)

                    // Filled progress
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: progress.goalMet
                                    ? [AppTheme.vibrantTeal, AppTheme.vibrantTeal.opacity(0.8)]
                                    : [AppTheme.sunnyYellow, AppTheme.vibrantTeal],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * min(percentage, 1.0), height: 24)

                    // Progress text overlay
                    HStack {
                        Spacer()
                        Text("\(progress.used) / \(progress.required) MIN")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(percentage < 0.5
                                ? (colorScheme == .dark ? AppTheme.lightCream : AppTheme.vibrantTeal)
                                : .white)
                            .padding(.trailing, 8)
                    }
                }
            }
            .frame(height: 24)
        }
        .padding(.vertical, 4)
    }

}
