import SwiftUI
import FamilyControls
import ManagedSettings

/// Screen 4: Learning Apps (with Child Agreement)
/// Captures learning app configuration + child agreement
struct Screen4_LearningAppsView: View {
    @EnvironmentObject var onboarding: OnboardingStateManager
    @Environment(\.colorScheme) private var colorScheme

    @State private var isPickerPresented = false
    @State private var dailyGoal: Int = 60
    @State private var childAgreementConfirmed: Bool = false

    private var hasSelectedApps: Bool {
        !onboarding.learningFamilySelection.applicationTokens.isEmpty
    }

    private var canContinue: Bool {
        hasSelectedApps && childAgreementConfirmed
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            Text("Step 1 - Select learning apps\nwith your child")
                .font(.system(size: 22, weight: .bold))
                .lineLimit(3)
                .multilineTextAlignment(.center)
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                .padding(.vertical, 24)
                .padding(.horizontal, 24)

            ScrollView {
                VStack(spacing: 16) {
                    // Agreement info panel
                    AgreementInfoPanel(colorScheme: colorScheme)

                    // Checkbox
                    AgreementCheckbox(
                        isChecked: $childAgreementConfirmed,
                        colorScheme: colorScheme
                    )

                    Divider()
                        .padding(.horizontal, 24)

                    // Learning apps section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Learning apps")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                            .padding(.horizontal, 24)

                        // Select apps button
                        Button(action: { isPickerPresented = true }) {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(AppTheme.vibrantTeal)
                                Text(hasSelectedApps ? "Add more apps" : "Select learning apps")
                                    .foregroundColor(AppTheme.vibrantTeal)
                                Spacer()
                            }
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                        }

                        // Selected apps display
                        if hasSelectedApps {
                            SelectedAppsGrid(
                                tokens: Array(onboarding.learningFamilySelection.applicationTokens),
                                colorScheme: colorScheme
                            )
                            .padding(.horizontal, 24)
                        }
                    }

                    Divider()
                        .padding(.horizontal, 24)

                    // Daily goal section
                    DailyGoalSelector(
                        dailyGoal: $dailyGoal,
                        colorScheme: colorScheme
                    )
                }
                .padding(.vertical, 16)
            }

            Spacer()

            // Primary CTA
            Button(action: saveAndContinue) {
                Text(canContinue ? "Continue" : (hasSelectedApps ? "Confirm agreement above" : "Select at least one app"))
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(canContinue ? AppTheme.vibrantTeal : Color.gray.opacity(0.3))
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .disabled(!canContinue)
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
            selection: $onboarding.learningFamilySelection
        )
        .onAppear {
            onboarding.logScreenView(screenNumber: 4)
            dailyGoal = onboarding.dailyLearningGoalMinutes
            childAgreementConfirmed = onboarding.childAgreementConfirmed
        }
    }

    private func saveAndContinue() {
        guard canContinue else { return }

        onboarding.dailyLearningGoalMinutes = dailyGoal
        onboarding.childAgreementConfirmed = childAgreementConfirmed
        onboarding.saveLearningAppsToViewModel()
        onboarding.advanceScreen()
    }
}

// MARK: - Agreement Info Panel

private struct AgreementInfoPanel: View {
    let colorScheme: ColorScheme

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundColor(AppTheme.vibrantTeal)
                    .font(.system(size: 20))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Before you continue...")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                    Text("Sit down with your child and explain: \"If you use these learning apps for X minutes, you'll automatically unlock X minutes of your favourite apps. Fair?\"")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        .lineLimit(5)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }
        }
        .padding(12)
        .background(AppTheme.vibrantTeal.opacity(0.1))
        .cornerRadius(12)
        .padding(.horizontal, 24)
    }
}

// MARK: - Agreement Checkbox

private struct AgreementCheckbox: View {
    @Binding var isChecked: Bool
    let colorScheme: ColorScheme

    var body: some View {
        HStack(spacing: 12) {
            Button(action: { isChecked.toggle() }) {
                Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                    .foregroundColor(isChecked ? AppTheme.vibrantTeal : .gray)
                    .font(.system(size: 22))
            }

            Text("I've explained this and agreed it with my child")
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))

            Spacer()
        }
        .padding(.horizontal, 24)
    }
}

// MARK: - Selected Apps Grid

private struct SelectedAppsGrid: View {
    let tokens: [ApplicationToken]
    let colorScheme: ColorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.vibrantTeal)
                Text("\(tokens.count) app\(tokens.count == 1 ? "" : "s") selected")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(tokens, id: \.self) { token in
                        AppTokenBadge(token: token, colorScheme: colorScheme)
                    }
                }
            }
        }
        .padding(12)
        .background(AppTheme.card(for: colorScheme))
        .cornerRadius(12)
    }
}

private struct AppTokenBadge: View {
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
                    .foregroundColor(AppTheme.vibrantTeal)
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
        .background(AppTheme.vibrantTeal.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Daily Goal Selector

private struct DailyGoalSelector: View {
    @Binding var dailyGoal: Int
    let colorScheme: ColorScheme

    private let options = [30, 60, 90]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Daily learning goal")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                .padding(.horizontal, 24)

            HStack(spacing: 12) {
                ForEach(options, id: \.self) { minutes in
                    VStack(spacing: 4) {
                        Button(action: { dailyGoal = minutes }) {
                            VStack {
                                Text("\(minutes)")
                                    .font(.system(size: 20, weight: .bold))

                                Text("min")
                                    .font(.system(size: 12, weight: .regular))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(dailyGoal == minutes ? AppTheme.vibrantTeal : AppTheme.card(for: colorScheme))
                            .foregroundColor(dailyGoal == minutes ? .white : AppTheme.textPrimary(for: colorScheme))
                            .cornerRadius(12)
                        }

                        if minutes == 60 {
                            Text("Recommended")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(AppTheme.vibrantTeal)
                        } else {
                            Text(" ")
                                .font(.system(size: 10))
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
        }
    }
}

#Preview {
    Screen4_LearningAppsView()
        .environmentObject(OnboardingStateManager())
}
