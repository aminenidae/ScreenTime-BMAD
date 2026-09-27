import SwiftUI
import FamilyControls

/// Screen 4b: shown when Screen Time access has been refused.
///
/// Verified on device 2026-09-27: re-requesting authorization in the same process
/// brings Apple's prompt back. So recovery is simply the ask again — no Settings
/// detour, no force-close instructions. The flow loops between this screen and the
/// prompt until access is granted.
///
/// This is a hard gate on purpose. Without access the app picker will not open and
/// the tutorial can neither be completed nor exited, so letting someone past here
/// would strand them somewhere worse. The screen earns the second ask by naming what
/// specifically stays broken, rather than repeating the first screen's pitch.
struct Screen4bPermissionRecoveryView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase

    /// Called once access is approved — the only way off this screen.
    let onGranted: () -> Void

    @State private var isRetrying = false
    /// Set only when a retry failed to produce a grant. Without it, a request iOS
    /// silently refuses looks identical to one the parent declined again.
    @State private var retryOutcome: String?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                header
                consequences
                callToAction
                safetyReminder
            }
            .padding(.bottom, 32)
        }
        .background(AppTheme.background(for: colorScheme).ignoresSafeArea())
        .onAppear {
            AppAnalytics.shared.track(.errorFamilyControlsDenied, parameters: [
                "source": "onboarding_permission_recovery"
            ])
        }
        // Covers a grant that happened outside the app — a relaunch, or Settings.
        .onChange(of: scenePhase) { phase in
            if phase == .active, AuthorizationCenter.shared.authorizationStatus == .approved {
                AppAnalytics.shared.track(.authorizationGranted, parameters: [
                    "source": "onboarding_permission_recovery_external"
                ])
                onGranted()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.slash.fill")
                .font(.system(size: 40))
                .foregroundColor(AppTheme.accentText(for: colorScheme))
                .padding(.bottom, 4)

            Text("WITHOUT THIS, NOTHING WORKS")
                .font(.system(size: 21, weight: .bold))
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                .multilineTextAlignment(.center)
                .textCase(.uppercase)
                .tracking(1)

            Text("Screen Time access is the switch the whole app runs on. It wasn't turned on, so right now:")
                .font(.system(size: 15))
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 24)
        .padding(.top, 32)
    }

    // MARK: - What stays broken

    /// Concrete consequences rather than a repeat of the first screen's pitch — the
    /// parent already declined the general argument once.
    private var consequences: some View {
        VStack(alignment: .leading, spacing: 14) {
            ConsequenceRow(
                icon: "lock.open.fill",
                text: String(localized: "Nothing can be locked. Games and videos stay open all day.")
            )
            ConsequenceRow(
                icon: "hourglass",
                text: String(localized: "Nothing can be earned. Time spent learning won't count towards anything.")
            )
            ConsequenceRow(
                icon: "square.grid.2x2",
                text: String(localized: "Setup can't continue. iOS won't show us your apps to choose from.")
            )
        }
        .padding(.horizontal, 32)
    }

    // MARK: - CTA

    private var callToAction: some View {
        VStack(spacing: 12) {
            Text("Tap below and Apple will ask again.")
                .font(.system(size: 15))
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)

            Button(action: retryAuthorization) {
                HStack {
                    if isRetrying {
                        ProgressView()
                            .tint(.white)
                    }
                    Text("Turn On Controls")
                }
                .font(.system(size: 18, weight: .bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(AppTheme.vibrantTeal)
                .foregroundColor(.white)
                .cornerRadius(AppTheme.CornerRadius.medium)
                .textCase(.uppercase)
            }
            .disabled(isRetrying)
            .padding(.horizontal, 24)

            if let retryOutcome {
                Text(retryOutcome)
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 32)
            }
        }
    }

    // MARK: - Safety reminder

    /// The same three lines as the priming screen, repeated below the button. A
    /// parent who declined may never have read them — and on the second ask the
    /// safety question is the one most likely to be holding them back.
    private var safetyReminder: some View {
        VStack(spacing: 16) {
            Divider()
                .padding(.horizontal, 30)

            PermissionSafetyLines()
                .padding(.horizontal, 30)
        }
        .padding(.top, 4)
    }

    // MARK: - Actions

    /// Ask again. Timing is recorded because a prompt iOS declines to draw returns
    /// almost instantly, and that case needs different advice from a second refusal.
    private func retryAuthorization() {
        isRetrying = true
        retryOutcome = nil
        let startedAt = Date()

        AppAnalytics.shared.track(.authorizationRequested, parameters: [
            "source": "onboarding_permission_recovery"
        ])

        Task {
            var threwError: String?
            do {
                try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            } catch {
                threwError = String(describing: error)
            }

            let elapsed = Date().timeIntervalSince(startedAt)
            let approved = AuthorizationCenter.shared.authorizationStatus == .approved

            #if DEBUG
            print("[PermissionRecovery] retry approved=\(approved) elapsed=\(String(format: "%.2f", elapsed))s error=\(threwError ?? "none")")
            #endif

            await MainActor.run {
                isRetrying = false

                guard !approved else {
                    AppAnalytics.shared.track(.authorizationGranted, parameters: [
                        "source": "onboarding_permission_recovery"
                    ])
                    onGranted()
                    return
                }

                AppAnalytics.shared.track(.authorizationDenied, parameters: [
                    "source": "onboarding_permission_recovery",
                    "elapsed_seconds": elapsed,
                    "error_code": threwError ?? "none"
                ])

                // Under half a second means iOS never drew the sheet. That shouldn't
                // happen — re-prompting works on device — but if it ever does, a
                // relaunch is the known way to get the prompt back.
                retryOutcome = elapsed < 0.5
                    ? String(localized: "Apple didn't show the request. Close the app completely, then open it again.")
                    : String(localized: "Still off — the app can't do anything until this is on.")
            }
        }
    }
}

// MARK: - Consequence Row

private struct ConsequenceRow: View {
    let icon: String
    let text: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(AppTheme.accentText(for: colorScheme))
                .frame(width: 22)
            Text(text)
                .font(.system(size: 15))
                .foregroundColor(AppTheme.textPrimary(for: colorScheme).opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Preview

#Preview {
    Screen4bPermissionRecoveryView(onGranted: {})
}
