import SwiftUI
import FamilyControls
import ManagedSettings

struct QuickLearningSetupScreen: View {
    @EnvironmentObject private var appUsageViewModel: AppUsageViewModel

    let deviceName: String
    let onBack: () -> Void
    let onContinue: () -> Void

    @State private var isPickerPresented = false
    @State private var pendingSelection = FamilyActivitySelection()

    private var minimumMet: Bool {
        !pendingSelection.applicationTokens.isEmpty
    }

    var body: some View {
        VStack(spacing: 24) {
            ChildOnboardingStepHeader(
                title: "Select Learning Apps",
                subtitle: "Choose the educational apps installed on \(deviceName.isEmpty ? "this device" : deviceName). You can add more later.",
                step: 2,
                totalSteps: 4,
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
                    Text(minimumMet ? "Continue" : "Select at least one app")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(minimumMet ? Color.accentColor : Color.accentColor.opacity(0.4))
                        .cornerRadius(14)
                }
                .disabled(!minimumMet)

            }
            .padding(.bottom, 16)
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .familyActivityPicker(isPresented: $isPickerPresented, selection: $pendingSelection)
    }

    private var selectionCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Pick 3-5 learning apps to get started. We'll automatically give each app 10 points per minute.")
                .font(.subheadline)

            Button(action: { isPickerPresented = true }) {
                Label("Select Apps", systemImage: "plus.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .foregroundColor(.white)
                    .background(Color.accentColor)
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
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.system(size: 42))
                .foregroundColor(.secondary)
            Text("No apps selected")
                .font(.headline)
            Text("Choose at least one educational app to continue.")
                .font(.subheadline)
                .foregroundColor(.secondary)
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
            Text("You can switch apps to Reward mode later. For now, keep the focus on learning apps that motivate your child.")
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
        guard minimumMet else { return }

        let tokens = pendingSelection.applicationTokens
        guard !tokens.isEmpty else { return }

        // Save to AppUsageViewModel - set both familySelection and pendingSelection
        appUsageViewModel.familySelection = pendingSelection
        appUsageViewModel.pendingSelection = pendingSelection

        // Assign categories and points
        for token in tokens {
            appUsageViewModel.categoryAssignments[token] = .learning
            appUsageViewModel.rewardPoints[token] = 10
        }

        // Save and start monitoring - this will merge into masterSelection
        appUsageViewModel.onCategoryAssignmentSave()
        appUsageViewModel.startMonitoring()

        onContinue()
    }
}

// MARK: - Subviews

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
                                .fill(Color.accentColor.opacity(0.2))
                        )

                    Label(token)
                        .labelStyle(.titleOnly)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                } else {
                    // Fallback for older iOS versions
                    Circle()
                        .fill(Color.accentColor.opacity(0.2))
                        .frame(width: 60, height: 60)
                        .overlay(
                            Image(systemName: "app.fill")
                                .foregroundColor(.accentColor)
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
