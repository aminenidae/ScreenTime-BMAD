import SwiftUI
import FamilyControls
import ManagedSettings

struct QuickLearningSetupScreen: View {
    @Environment(\.colorScheme) private var colorScheme
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
            VStack(spacing: 16) {
                OnboardingProgressIndicator(currentStep: 4)

                VStack(spacing: 12) {
                    // Icon
                    ZStack {
                        Circle()
                            .fill(AppTheme.vibrantTeal.opacity(0.15))
                            .frame(width: 80, height: 80)

                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 40))
                            .foregroundColor(AppTheme.vibrantTeal)
                    }

                    // Headline - parent-facing
                    Text("Define Your System")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                        .multilineTextAlignment(.center)

                    Text("Learning Apps")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(AppTheme.vibrantTeal)
                        .multilineTextAlignment(.center)

                    // Subtitle - purpose explanation
                    Text("Select apps that encourage learning, reading, or skill development")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 20)
            }

            Button(action: { isPickerPresented = true }) {
                Label("Select Apps", systemImage: "plus.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .foregroundColor(.white)
                    .background(AppTheme.vibrantTeal)
                    .cornerRadius(12)
            }
            .padding(.horizontal)

            if pendingSelection.applicationTokens.isEmpty {
                emptyState
            } else {
                VStack(spacing: 12) {
                    // Feedback message - parent-facing
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("\(pendingSelection.applicationTokens.count) learning apps selected")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.green.opacity(0.1))
                    )
                    .padding(.horizontal)

                    SelectedAppGrid(tokens: Array(pendingSelection.applicationTokens))
                }
            }

            Spacer()

            VStack(spacing: 12) {
                Button(action: saveAndContinue) {
                    Text(minimumMet ? "Continue" : "Select at least one app")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(minimumMet ? AppTheme.vibrantTeal : Color.secondary.opacity(0.4))
                        .cornerRadius(16)
                }
                .disabled(!minimumMet)

                Button(action: onBack) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 40)
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .familyActivityPicker(isPresented: $isPickerPresented, selection: $pendingSelection)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "book.fill")
                .font(.system(size: 42))
                .foregroundColor(AppTheme.vibrantTeal)
            Text("No apps selected")
                .font(.headline)
            Text("Choose at least one educational app to continue.")
                .font(.subheadline)
                .foregroundColor(AppTheme.vibrantTeal.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(AppTheme.vibrantTeal.opacity(0.1))
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
        // CRITICAL: Use force: true to bypass isMonitoring check
        // This ensures monitoring starts even if state is inconsistent from auto-restart failure
        appUsageViewModel.startMonitoring(force: true)

        onContinue()
    }
}

// MARK: - Subviews

private struct SelectedAppGrid: View {
    let tokens: [ApplicationToken]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(AppTheme.vibrantTeal)
                Text("Selected Apps")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
            }
            .padding(.horizontal)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(tokens, id: \.self) { token in
                        AppRow(token: token)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private struct AppRow: View {
        let token: ApplicationToken

        // Match Learning tab icon sizes
        let iconSize: CGFloat = 34
        let iconScale: CGFloat = 1.35
        let fallbackIconSize: CGFloat = 24

        var body: some View {
            HStack(spacing: 16) {
                // App Icon
                if #available(iOS 15.2, *) {
                    Label(token)
                        .labelStyle(.iconOnly)
                        .scaleEffect(iconScale)
                        .frame(width: iconSize, height: iconSize)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(AppTheme.vibrantTeal.opacity(0.2))
                        .frame(width: iconSize, height: iconSize)
                        .overlay(
                            Image(systemName: "app.fill")
                                .font(.system(size: fallbackIconSize))
                                .foregroundColor(AppTheme.vibrantTeal)
                        )
                }

                // App Info
                VStack(alignment: .leading, spacing: 2) {
                    if #available(iOS 15.2, *) {
                        Label(token)
                            .labelStyle(.titleOnly)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.primary)
                    } else {
                        Text("Learning App")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                            .foregroundColor(AppTheme.sunnyYellow)
                        Text("+10 pts/min")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppTheme.sunnyYellow)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemBackground))
                    .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
            )
        }
    }
}
