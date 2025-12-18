import SwiftUI
import FamilyControls

/// Screen 4: FamilyControls Authorization
/// Requests Screen Time permission before proceeding to the guided tutorial
struct Screen4_AuthorizationView: View {
    @EnvironmentObject var onboarding: OnboardingStateManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var isRequesting = false
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 16) {
                Image(systemName: "hourglass.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(AppTheme.vibrantTeal)

                Text("Enable Screen Time Access")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                    .multilineTextAlignment(.center)

                Text("To manage your child's apps, we need permission to use Screen Time controls.")
                    .font(.system(size: 16))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.top, 48)

            Spacer()

            // Features list
            VStack(alignment: .leading, spacing: 16) {
                AuthFeatureRow(text: "Set learning apps")
                AuthFeatureRow(text: "Unlock reward apps automatically")
                AuthFeatureRow(text: "Track daily progress")
            }
            .padding(.horizontal, 32)

            Spacer()

            // Privacy note
            HStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .foregroundColor(AppTheme.vibrantTeal)
                Text("Your data is private and stays on device.")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
            }
            .padding(.horizontal, 24)

            Spacer()

            // CTA Button
            Button(action: requestAuthorization) {
                HStack {
                    if isRequesting {
                        ProgressView()
                            .tint(.white)
                    }
                    Text("Grant Permission")
                }
                .font(.system(size: 16, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(AppTheme.vibrantTeal)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(isRequesting)
            .padding(.horizontal, 24)

            // Back button
            Button(action: { onboarding.goBack() }) {
                Text("Back")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
            }
            .padding(.vertical, 16)

            Spacer(minLength: 24)
        }
        .background(AppTheme.background(for: colorScheme).ignoresSafeArea())
        .alert("Authorization Error", isPresented: $showError) {
            Button("Try Again") { requestAuthorization() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            checkExistingAuthorization()
            onboarding.logScreenView(screenNumber: 4)
        }
    }

    private func checkExistingAuthorization() {
        if AuthorizationCenter.shared.authorizationStatus == .approved {
            onboarding.advanceScreen()
        }
    }

    private func requestAuthorization() {
        isRequesting = true
        Task {
            do {
                try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
                await MainActor.run {
                    isRequesting = false
                    onboarding.advanceScreen()
                }
            } catch {
                await MainActor.run {
                    isRequesting = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
}

// MARK: - Feature Row

private struct AuthFeatureRow: View {
    let text: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(AppTheme.vibrantTeal)
            Text(text)
                .font(.system(size: 16))
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
        }
    }
}

// MARK: - Preview

#Preview {
    Screen4_AuthorizationView()
        .environmentObject(OnboardingStateManager())
}
