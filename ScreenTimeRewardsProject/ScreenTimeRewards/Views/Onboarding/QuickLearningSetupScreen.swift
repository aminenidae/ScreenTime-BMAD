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
                SelectedAppGrid(tokens: Array(pendingSelection.applicationTokens))
            }

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
