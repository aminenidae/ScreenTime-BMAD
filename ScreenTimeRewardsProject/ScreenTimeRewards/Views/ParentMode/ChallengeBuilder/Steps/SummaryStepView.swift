import SwiftUI
import FamilyControls
import ManagedSettings

struct SummaryStepView: View {
    @EnvironmentObject private var appUsageViewModel: AppUsageViewModel
    @Binding var data: ChallengeBuilderData
    var onEdit: (ChallengeBuilderStep) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            summarySection(title: "Challenge Overview", step: .details, icon: "star.circle.fill", color: AppTheme.sunnyYellow) {
                summaryRow(title: "Name", value: data.trimmedTitle.isEmpty ? "Untitled Challenge" : data.trimmedTitle)
                summaryRow(title: "Daily Goal", value: "\(data.dailyMinutesGoal) minutes")
                if !data.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    summaryRow(title: "Description", value: data.description)
                }
            }

            summarySection(title: "Learning Apps", step: .learningApps, icon: "book.circle.fill", color: AppTheme.vibrantTeal) {
                if learningAppTokens.isEmpty {
                    summaryRow(title: "Apps", value: "All learning apps")
                } else {
                    iconGrid(for: learningAppTokens)
                }

                // Show tracking mode if multiple apps selected
                if !data.selectedLearningAppIDs.isEmpty && data.selectedLearningAppIDs.count >= 2 {
                    summaryRow(title: "Tracking", value: data.progressTrackingMode.displayName)
                }
            }

            summarySection(title: "Reward Apps", step: .rewardApps, icon: "gift.circle.fill", color: AppTheme.playfulCoral) {
                if data.selectedRewardAppIDs.isEmpty {
                    summaryRow(title: "Rewards", value: "No apps will be unlocked")
                } else {
                    iconGrid(for: rewardAppTokens)
                }
            }

            summarySection(title: "Rewards & Bonus", step: .rewardConfig, icon: "sparkles.circle.fill", color: AppTheme.sunnyYellow) {
                summaryRow(title: "Ratio", value: data.learningToRewardRatio.formattedDescription)
                if data.streakBonus.enabled {
                    summaryRow(title: "Streak Bonus", value: "\(data.streakBonus.targetDays) days → +\(data.streakBonus.bonusPercentage)%")
                } else {
                    summaryRow(title: "Streak Bonus", value: "Not enabled")
                }
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(ChallengeBuilderTheme.cardBackground)
        )
    }

    // MARK: - Helpers
    private func summarySection<Content: View>(
        title: String,
        step: ChallengeBuilderStep,
        icon: String,
        color: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(color)

                    Text(title)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(ChallengeBuilderTheme.text)
                }

                Spacer()

                Button("Edit") {
                    onEdit(step)
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(color)
            }

            VStack(spacing: 10, content: content)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(color.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(color.opacity(0.25), lineWidth: 1)
                        )
                )
        }
    }

    private func summaryRow(title: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(ChallengeBuilderTheme.mutedText)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .font(.system(size: 15))
                .foregroundColor(ChallengeBuilderTheme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var learningAppTokens: [ManagedSettings.ApplicationToken] {
        let map = Dictionary(uniqueKeysWithValues: appUsageViewModel.learningSnapshots.map { ($0.logicalID, $0.token) })
        return data.selectedLearningAppIDs.compactMap { map[$0] }
    }

    private var rewardAppTokens: [ManagedSettings.ApplicationToken] {
        let map = Dictionary(uniqueKeysWithValues: appUsageViewModel.rewardSnapshots.map { ($0.logicalID, $0.token) })
        return data.selectedRewardAppIDs.compactMap { map[$0] }
    }

    private func iconGrid(for tokens: [ManagedSettings.ApplicationToken]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 60), spacing: 12)], spacing: 12) {
            ForEach(Array(tokens.indices), id: \.self) { index in
                let token = tokens[index]
                if #available(iOS 15.2, *) {
                    Label(token)
                        .labelStyle(.iconOnly)
                        .scaleEffect(2.4)
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(ChallengeBuilderTheme.inputBackground)
                        .frame(width: 60, height: 60)
                        .overlay(
                            Image(systemName: "app.fill")
                                .font(.system(size: 30))
                                .foregroundColor(ChallengeBuilderTheme.mutedText)
                        )
                }
            }
        }
        .padding(.vertical, 4)
    }
}
