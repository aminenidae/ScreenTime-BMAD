import SwiftUI
import FamilyControls
import ManagedSettings

struct SummaryStepView: View {
    @EnvironmentObject private var appUsageViewModel: AppUsageViewModel
    @Binding var data: ChallengeBuilderData
    var onEdit: (ChallengeBuilderStep) -> Void

    private let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()

    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            summarySection(title: "Challenge Overview", step: .details) {
                summaryRow(title: "Name", value: data.trimmedTitle.isEmpty ? "Untitled Challenge" : data.trimmedTitle)
                summaryRow(title: "Goal Type", value: data.goalType.displayName)
                summaryRow(title: "Target", value: "\(data.activeGoalValue) \(data.activeGoalConfiguration.unit)")
                if !data.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    summaryRow(title: "Description", value: data.description)
                }
            }

            summarySection(title: "Learning Apps", step: .learningApps) {
                if learningAppTokens.isEmpty {
                    summaryRow(title: "Apps", value: "All learning apps")
                } else {
                    iconGrid(for: learningAppTokens)
                }
            }

            summarySection(title: "Reward Apps", step: .rewardApps) {
                if data.selectedRewardAppIDs.isEmpty {
                    summaryRow(title: "Rewards", value: "No apps will be unlocked")
                } else {
                    iconGrid(for: rewardAppTokens)
                }
            }

            summarySection(title: "Rewards & Bonus", step: .rewardConfig) {
                summaryRow(title: "Ratio", value: data.learningToRewardRatio.formattedDescription)
                summaryRow(title: "Bonus", value: "+\(data.bonusPercentage)%")
            }

            summarySection(title: "Schedule", step: .schedule) {
                summaryRow(title: "Starts", value: dayFormatter.string(from: data.schedule.startDate))
                if data.schedule.hasEndDate, let endDate = data.schedule.endDate {
                    summaryRow(title: "Ends", value: dayFormatter.string(from: endDate))
                } else {
                    summaryRow(title: "Ends", value: "No end date")
                }

                summaryRow(title: "Days", value: formattedDays)

                if data.schedule.isFullDay {
                    summaryRow(title: "Time", value: "All day")
                } else {
                    let start = timeFormatter.string(from: data.schedule.startTime)
                    let end = timeFormatter.string(from: data.schedule.endTime)
                    summaryRow(title: "Time", value: "\(start) – \(end)")
                }

                summaryRow(title: "Repeats", value: data.schedule.repeatWeekly ? "Weekly" : "One-time")
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
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(ChallengeBuilderTheme.text)
                Spacer()
                Button("Edit") {
                    onEdit(step)
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(ChallengeBuilderTheme.primary)
            }
            VStack(spacing: 10, content: content)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(ChallengeBuilderTheme.inputBackground.opacity(0.6))
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

    private var formattedDays: String {
        guard !data.schedule.activeDays.isEmpty else {
            return "No days selected"
        }

        if data.schedule.activeDays.count == 7 {
            return "Every day"
        }

        let orderedDays = [1, 2, 3, 4, 5, 6, 7]
        let dayNames: [Int: String] = [
            1: "Mon",
            2: "Tue",
            3: "Wed",
            4: "Thu",
            5: "Fri",
            6: "Sat",
            7: "Sun"
        ]

        return orderedDays.compactMap { day -> String? in
            guard data.schedule.activeDays.contains(day) else { return nil }
            return dayNames[day]
        }
        .joined(separator: ", ")
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
