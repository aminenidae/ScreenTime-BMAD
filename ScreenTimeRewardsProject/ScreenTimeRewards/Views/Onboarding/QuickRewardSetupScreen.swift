import SwiftUI
import FamilyControls
import ManagedSettings

struct QuickRewardSetupScreen: View {
    @EnvironmentObject private var appUsageViewModel: AppUsageViewModel

    let deviceName: String
    let onBack: () -> Void
    let onContinue: () -> Void

    @State private var isPickerPresented = false
    @State private var pendingSelection = FamilyActivitySelection()

    private var canContinue: Bool {
        // Reward apps are optional, can continue without selecting any
        true
    }

    var body: some View {
        VStack(spacing: 24) {
            ChildOnboardingStepHeader(
                title: "Select Reward Apps",
                subtitle: "Choose fun apps that your child can unlock by earning points. You can skip this step.",
                step: 3,
                totalSteps: 5,
                onBack: onBack
            )

            selectionCard

            if pendingSelection.applicationTokens.isEmpty {
                emptyState
            } else {
                SelectedAppGrid(tokens: Array(pendingSelection.applicationTokens))
            }

            tipCard

            Spacer()

            VStack(spacing: 12) {
                Button(action: saveAndContinue) {
                    Text("Continue")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.accentColor)
                        .cornerRadius(14)
                }

                Button(action: onContinue) {
                    Text("Skip for now")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.bottom, 16)
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .familyActivityPicker(isPresented: $isPickerPresented, selection: $pendingSelection)
    }

    private var selectionCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Pick 2-3 fun apps your child can unlock with earned points.")
                .font(.subheadline)

            Button(action: { isPickerPresented = true }) {
                Label("Select Apps", systemImage: "plus.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .foregroundColor(.white)
                    .background(AppTheme.playfulCoral)
                    .cornerRadius(12)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.05), radius: 12, x: 0, y: 6)
        )
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "star.circle")
                .font(.system(size: 42))
                .foregroundColor(.secondary)
            Text("No reward apps selected")
                .font(.headline)
            Text("That's okay! You can add them later from the Rewards tab.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var tipCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Pro tip", systemImage: "sparkles")
                .font(.headline)
            Text("Choose apps your child loves but should limit. These become rewards that motivate learning!")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func saveAndContinue() {
        let tokens = pendingSelection.applicationTokens
        guard !tokens.isEmpty else {
            onContinue()
            return
        }

        // IMPORTANT: Merge with existing familySelection to preserve learning apps
        var combinedSelection = appUsageViewModel.familySelection
        combinedSelection.applicationTokens.formUnion(pendingSelection.applicationTokens)

        // Save to AppUsageViewModel - set both familySelection and pendingSelection
        appUsageViewModel.familySelection = combinedSelection
        appUsageViewModel.pendingSelection = combinedSelection

        // Assign categories and points for the reward apps
        for token in tokens {
            appUsageViewModel.categoryAssignments[token] = .reward
            appUsageViewModel.rewardPoints[token] = 10
        }

        // Save and start monitoring - this will merge into masterSelection
        appUsageViewModel.onCategoryAssignmentSave()
        appUsageViewModel.startMonitoring()

        onContinue()
    }
}

// MARK: - Subviews (reuse from QuickLearningSetupScreen)

private struct SelectedAppGrid: View {
    let tokens: [ApplicationToken]

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(tokens, id: \.self) { token in
                    AppCard(token: token)
                }
            }
            .padding(.vertical, 8)
        }
    }

    private struct AppCard: View {
        let token: ApplicationToken

        var body: some View {
            VStack(spacing: 12) {
                // Use Label from FamilyControls to display app icon and name
                if #available(iOS 15.2, *) {
                    Label(token)
                        .labelStyle(.iconOnly)
                        .frame(width: 60, height: 60)
                        .background(
                            Circle()
                                .fill(AppTheme.playfulCoral.opacity(0.2))
                        )

                    Label(token)
                        .labelStyle(.titleOnly)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                } else {
                    // Fallback for older iOS versions
                    Circle()
                        .fill(AppTheme.playfulCoral.opacity(0.2))
                        .frame(width: 60, height: 60)
                        .overlay(
                            Image(systemName: "app.fill")
                                .foregroundColor(AppTheme.playfulCoral)
                        )

                    Text("App")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }

                Text("10 pts/min")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, minHeight: 180)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(.secondarySystemBackground))
            )
        }
    }
}
