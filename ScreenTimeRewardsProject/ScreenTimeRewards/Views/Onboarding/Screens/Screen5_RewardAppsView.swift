import SwiftUI
import FamilyControls
import ManagedSettings

/// Screen 5: Reward Apps + Ratio
/// Captures reward app configuration and learning-to-reward ratio
struct Screen5_RewardAppsView: View {
    @EnvironmentObject var onboarding: OnboardingStateManager
    @Environment(\.colorScheme) private var colorScheme

    @State private var isPickerPresented = false
    @State private var selectedRatio: Double = 1.0

    private var hasSelectedApps: Bool {
        !onboarding.rewardFamilySelection.applicationTokens.isEmpty
    }

    private var learningGoal: Int {
        onboarding.dailyLearningGoalMinutes
    }

    private var rewardMinutes: Int {
        Int(Double(learningGoal) * selectedRatio)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            Text("Step 2 - Choose reward apps\nand time they earn")
                .font(.system(size: 22, weight: .bold))
                .lineLimit(3)
                .multilineTextAlignment(.center)
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                .padding(.vertical, 24)
                .padding(.horizontal, 24)

            ScrollView {
                VStack(spacing: 20) {
                    // Reward apps section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Reward apps")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                            .padding(.horizontal, 24)

                        // Select apps button
                        Button(action: { isPickerPresented = true }) {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(AppTheme.vibrantTeal)
                                Text(hasSelectedApps ? "Add more apps" : "Select reward apps")
                                    .foregroundColor(AppTheme.vibrantTeal)
                                Spacer()
                            }
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                        }

                        // Selected apps display
                        if hasSelectedApps {
                            SelectedRewardAppsGrid(
                                tokens: Array(onboarding.rewardFamilySelection.applicationTokens),
                                colorScheme: colorScheme
                            )
                            .padding(.horizontal, 24)
                        }
                    }

                    Divider()
                        .padding(.horizontal, 24)

                    // Ratio section
                    RatioSelector(
                        selectedRatio: $selectedRatio,
                        learningGoal: learningGoal,
                        colorScheme: colorScheme
                    )

                    // Preview card
                    AgreementPreviewCard(
                        learningGoal: learningGoal,
                        rewardMinutes: rewardMinutes,
                        learningAppsCount: onboarding.learningFamilySelection.applicationTokens.count,
                        rewardAppsCount: onboarding.rewardFamilySelection.applicationTokens.count,
                        colorScheme: colorScheme
                    )
                    .padding(.horizontal, 24)
                }
                .padding(.vertical, 16)
            }

            Spacer()

            // Primary CTA
            Button(action: saveAndContinue) {
                Text(hasSelectedApps ? "Finish setup" : "Select at least one app")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(hasSelectedApps ? AppTheme.vibrantTeal : Color.gray.opacity(0.3))
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .disabled(!hasSelectedApps)
            .padding(.horizontal, 24)

            // Back button
            Button(action: { onboarding.goBack() }) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
            }
            .padding(.vertical, 12)

            Spacer(minLength: 16)
        }
        .background(AppTheme.background(for: colorScheme).ignoresSafeArea())
        .familyActivityPicker(
            isPresented: $isPickerPresented,
            selection: $onboarding.rewardFamilySelection
        )
        .onAppear {
            onboarding.logScreenView(screenNumber: 5)
            selectedRatio = onboarding.learningToRewardRatio
        }
    }

    private func saveAndContinue() {
        guard hasSelectedApps else { return }

        onboarding.learningToRewardRatio = selectedRatio
        onboarding.saveRewardAppsToViewModel()
        onboarding.startMonitoring()
        onboarding.advanceScreen()
    }
}

// MARK: - Selected Reward Apps Grid

private struct SelectedRewardAppsGrid: View {
    let tokens: [ApplicationToken]
    let colorScheme: ColorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.playfulCoral)
                Text("\(tokens.count) app\(tokens.count == 1 ? "" : "s") selected")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(tokens, id: \.self) { token in
                        RewardAppTokenBadge(token: token, colorScheme: colorScheme)
                    }
                }
            }
        }
        .padding(12)
        .background(AppTheme.card(for: colorScheme))
        .cornerRadius(12)
    }
}

private struct RewardAppTokenBadge: View {
    let token: ApplicationToken
    let colorScheme: ColorScheme

    var body: some View {
        HStack(spacing: 6) {
            if #available(iOS 15.2, *) {
                Label(token)
                    .labelStyle(.iconOnly)
                    .scaleEffect(1.2)
                    .frame(width: 24, height: 24)
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: 16))
                    .foregroundColor(AppTheme.playfulCoral)
            }

            if #available(iOS 15.2, *) {
                Label(token)
                    .labelStyle(.titleOnly)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(AppTheme.playfulCoral.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Ratio Selector

private struct RatioSelector: View {
    @Binding var selectedRatio: Double
    let learningGoal: Int
    let colorScheme: ColorScheme

    private let ratioOptions: [(ratio: Double, label: String)] = [
        (0.5, "More learning"),
        (1.0, "Balanced"),
        (1.5, "More rewards")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How much reward time should learning unlock?")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                .padding(.horizontal, 24)

            VStack(spacing: 8) {
                ForEach(ratioOptions, id: \.ratio) { option in
                    RatioOptionRow(
                        option: option,
                        learningGoal: learningGoal,
                        isSelected: selectedRatio == option.ratio,
                        colorScheme: colorScheme
                    ) {
                        selectedRatio = option.ratio
                    }
                }
            }
            .padding(.horizontal, 24)
        }
    }
}

private struct RatioOptionRow: View {
    let option: (ratio: Double, label: String)
    let learningGoal: Int
    let isSelected: Bool
    let colorScheme: ColorScheme
    let onTap: () -> Void

    private var rewardMinutes: Int {
        Int(Double(learningGoal) * option.ratio)
    }

    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(rewardMinutes) minutes of rewards")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                    Text(option.label)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? AppTheme.vibrantTeal : .gray)
                    .font(.system(size: 22))
            }
            .padding(14)
            .background(isSelected ? AppTheme.vibrantTeal.opacity(0.1) : AppTheme.card(for: colorScheme))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? AppTheme.vibrantTeal : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Agreement Preview Card

private struct AgreementPreviewCard: View {
    let learningGoal: Int
    let rewardMinutes: Int
    let learningAppsCount: Int
    let rewardAppsCount: Int
    let colorScheme: ColorScheme

    var body: some View {
        VStack(spacing: 12) {
            Text("Today's Agreement")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))

            VStack(alignment: .leading, spacing: 10) {
                // Learning section
                HStack(spacing: 8) {
                    Image(systemName: "book.fill")
                        .foregroundColor(AppTheme.vibrantTeal)
                    Text("\(learningGoal) min learning")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                    Spacer()
                    Text("\(learningAppsCount) app\(learningAppsCount == 1 ? "" : "s")")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                }

                Image(systemName: "arrow.down")
                    .foregroundColor(AppTheme.vibrantTeal)
                    .frame(maxWidth: .infinity)

                // Reward section
                HStack(spacing: 8) {
                    Image(systemName: "play.tv.fill")
                        .foregroundColor(AppTheme.playfulCoral)
                    Text("\(rewardMinutes) min rewards")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                    Spacer()
                    Text("\(rewardAppsCount) app\(rewardAppsCount == 1 ? "" : "s")")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                }

                Divider()
                    .padding(.vertical, 4)

                Text("Repeats every day. Unlock and lock are automatic.")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
            }
            .padding(14)
            .background(AppTheme.card(for: colorScheme).opacity(0.5))
            .cornerRadius(12)
        }
        .padding(16)
        .background(AppTheme.vibrantTeal.opacity(0.05))
        .cornerRadius(16)
    }
}

#Preview {
    Screen5_RewardAppsView()
        .environmentObject(OnboardingStateManager())
}
