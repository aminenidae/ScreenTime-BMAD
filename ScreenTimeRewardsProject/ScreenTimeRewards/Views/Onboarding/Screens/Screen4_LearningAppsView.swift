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

    // Authorization state
    @State private var isAuthorized = false
    @State private var isRequestingAuth = false
    @State private var showAuthError = false
    @State private var authErrorMessage = ""

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

                    // Authorization section (show if not authorized)
                    if !isAuthorized {
                        AuthorizationSection(
                            isRequesting: $isRequestingAuth,
                            colorScheme: colorScheme,
                            onRequestAuth: requestAuthorization
                        )
                    }

                    // Learning apps section (only show if authorized)
                    if isAuthorized {
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
                }
                .padding(.vertical, 16)
            }

            Spacer()

            // Primary CTA
            Button(action: saveAndContinue) {
                Text(buttonTitle)
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
        .alert("Authorization Error", isPresented: $showAuthError) {
            Button("Try Again", role: .cancel) {
                requestAuthorization()
            }
            Button("Continue Anyway", role: .destructive) {
                // Allow continuing without auth for testing
            }
        } message: {
            Text(authErrorMessage)
        }
        .onAppear {
            onboarding.logScreenView(screenNumber: 4)
            dailyGoal = onboarding.dailyLearningGoalMinutes
            childAgreementConfirmed = onboarding.childAgreementConfirmed
            checkAuthorizationStatus()
        }
    }

    private var buttonTitle: String {
        if !isAuthorized {
            return "Enable Screen Time access first"
        } else if !hasSelectedApps {
            return "Select at least one app"
        } else if !childAgreementConfirmed {
            return "Confirm agreement above"
        } else {
            return "Continue"
        }
    }

    private func checkAuthorizationStatus() {
        // Check if already authorized
        let status = AuthorizationCenter.shared.authorizationStatus
        isAuthorized = (status == .approved)

        #if DEBUG
        print("[Screen4] Authorization status: \(status)")
        #endif
    }

    private func requestAuthorization() {
        isRequestingAuth = true

        #if DEBUG
        print("[Screen4] Requesting FamilyControls authorization...")
        #endif

        Task {
            do {
                try await AuthorizationCenter.shared.requestAuthorization(for: .individual)

                await MainActor.run {
                    isRequestingAuth = false
                    isAuthorized = true
                    UserDefaults.standard.set(true, forKey: "authorizationGranted")
                    onboarding.logEvent("screen_time_authorized")

                    #if DEBUG
                    print("[Screen4] Authorization granted!")
                    #endif
                }
            } catch {
                await MainActor.run {
                    isRequestingAuth = false
                    authErrorMessage = "Failed to get Screen Time access.\n\nError: \(error.localizedDescription)"
                    showAuthError = true

                    #if DEBUG
                    print("[Screen4] Authorization failed: \(error)")
                    #endif
                }
            }
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

// MARK: - Authorization Section

private struct AuthorizationSection: View {
    @Binding var isRequesting: Bool
    let colorScheme: ColorScheme
    let onRequestAuth: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(AppTheme.vibrantTeal.opacity(0.1))
                    .frame(width: 64, height: 64)

                Image(systemName: "figure.2.and.child.holdinghands")
                    .font(.system(size: 32))
                    .foregroundColor(AppTheme.vibrantTeal)
            }

            // Title
            Text("Enable Screen Time Access")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                .multilineTextAlignment(.center)

            // Description
            Text("To manage your child's apps, we need permission to use Screen Time controls.")
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                .multilineTextAlignment(.center)

            // Features
            VStack(alignment: .leading, spacing: 10) {
                AuthFeatureRow(icon: "checkmark.circle.fill", text: "Set learning apps", colorScheme: colorScheme)
                AuthFeatureRow(icon: "checkmark.circle.fill", text: "Unlock reward apps automatically", colorScheme: colorScheme)
                AuthFeatureRow(icon: "checkmark.circle.fill", text: "Track daily progress", colorScheme: colorScheme)
            }

            // Grant Permission Button
            Button(action: onRequestAuth) {
                HStack {
                    if isRequesting {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Image(systemName: "lock.open.fill")
                        Text("Grant Permission")
                    }
                }
                .font(.system(size: 16, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(isRequesting ? AppTheme.vibrantTeal.opacity(0.6) : AppTheme.vibrantTeal)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(isRequesting)

            // Privacy note
            Text("Your data is private and stays on device.")
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(AppTheme.textSecondary(for: colorScheme).opacity(0.7))
        }
        .padding(20)
        .background(AppTheme.card(for: colorScheme))
        .cornerRadius(16)
        .shadow(color: AppTheme.cardShadow(for: colorScheme), radius: 4, x: 0, y: 2)
        .padding(.horizontal, 24)
    }
}

private struct AuthFeatureRow: View {
    let icon: String
    let text: String
    let colorScheme: ColorScheme

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.green)

            Text(text)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
        }
    }
}

#Preview {
    Screen4_LearningAppsView()
        .environmentObject(OnboardingStateManager())
}
