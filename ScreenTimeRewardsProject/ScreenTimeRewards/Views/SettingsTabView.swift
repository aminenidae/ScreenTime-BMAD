import SwiftUI

struct SettingsTabView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @State private var showingPairingView = false
    @State private var showResetConfirmation = false
    @StateObject private var pairingService = DevicePairingService.shared
    @StateObject private var modeManager = DeviceModeManager.shared
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        NavigationView {
            ZStack {
                // Background
                AppTheme.background(for: colorScheme)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 32) {
                        // Account Section
                        settingsSection(title: "ACCOUNT") {
                            exitParentModeRow
                        }

                        // Subscription Section
                        settingsSection(title: "SUBSCRIPTION") {
                            subscriptionRow
                        }

                        // Devices Section
                        settingsSection(title: "DEVICES") {
                            pairingStatusRow
                        }

                        // Danger Zone Section
                        VStack(alignment: .leading, spacing: 8) {
                            settingsSection(title: "DANGER ZONE") {
                                resetDeviceRow
                            }

                            Text("This will erase all app settings and data on this device.")
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                                .padding(.horizontal, 20)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 24)
                    .padding(.bottom, 24)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Settings")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                }

                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        sessionManager.exitToSelection()
                    }) {
                        Image(systemName: "chevron.backward")
                            .font(.system(size: 24))
                            .foregroundColor(AppTheme.vibrantTeal)
                    }
                }
            }
        }
        .sheet(isPresented: $showingPairingView) {
            ChildPairingView()
        }
    }
}

// MARK: - Helper Functions

private extension SettingsTabView {
    func settingsSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                .tracking(0.6)
                .padding(.horizontal, 20)

            content()
        }
    }
}

// MARK: - Row Views

private extension SettingsTabView {
    var exitParentModeRow: some View {
        Button(action: {
            sessionManager.exitToSelection()
        }) {
            HStack(spacing: 16) {
                // Icon container with gradient
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: [AppTheme.playfulCoral.opacity(0.15), AppTheme.sunnyYellow.opacity(0.15)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 40, height: 40)

                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 20))
                        .foregroundColor(AppTheme.playfulCoral)
                }

                // Label
                Text("Exit Parent Mode")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                Spacer()

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
            }
            .padding(16)
            .background(AppTheme.card(for: colorScheme))
            .cornerRadius(16)
            .shadow(color: AppTheme.cardShadow(for: colorScheme), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
    }

    var pairingStatusRow: some View {
        Button(action: {
            if !pairingService.isPaired() {
                showingPairingView = true
            }
        }) {
            HStack(spacing: 16) {
                // Icon container with gradient
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: [AppTheme.vibrantTeal.opacity(0.15), AppTheme.sunnyYellow.opacity(0.15)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 40, height: 40)

                    Image(systemName: "ipad.and.iphone")
                        .font(.system(size: 20))
                        .foregroundColor(AppTheme.vibrantTeal)
                }

                // Status content
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pairing Status")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                    if pairingService.isPaired() {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.vibrantTeal)

                            Text("Paired with Child's iPad")
                                .font(.system(size: 14))
                                .foregroundColor(AppTheme.vibrantTeal)
                        }
                    } else {
                        Text("Not paired")
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    }
                }

                Spacer()

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
            }
            .padding(16)
            .background(AppTheme.card(for: colorScheme))
            .cornerRadius(16)
            .shadow(color: AppTheme.cardShadow(for: colorScheme), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
    }

    var resetDeviceRow: some View {
        Button(action: {
            showResetConfirmation = true
        }) {
            HStack(spacing: 16) {
                // Icon container
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(AppTheme.error.opacity(0.1))
                        .frame(width: 40, height: 40)

                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 20))
                        .foregroundColor(AppTheme.error)
                }

                // Label
                Text("Reset This Device")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(AppTheme.error)

                Spacer()

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
            }
            .padding(16)
            .background(AppTheme.card(for: colorScheme))
            .cornerRadius(16)
            .shadow(color: AppTheme.cardShadow(for: colorScheme), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
        .confirmationDialog("Reset Device Mode?",
                          isPresented: $showResetConfirmation) {
            Button("Reset", role: .destructive) {
                modeManager.resetDeviceMode()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will reset your device mode selection. App configurations will be preserved.")
        }
    }

    var subscriptionRow: some View {
        NavigationLink(destination: SubscriptionManagementView()) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: [AppTheme.vibrantTeal.opacity(0.15), AppTheme.sunnyYellow.opacity(0.15)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 40, height: 40)

                    Image(systemName: "crown.fill")
                        .font(.system(size: 20))
                        .foregroundColor(AppTheme.vibrantTeal)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Manage Subscription")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                    Text(subscriptionManager.currentTierName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.vibrantTeal)

                    if subscriptionManager.isInTrial, let days = subscriptionManager.trialDaysRemaining {
                        Text("\(days) days left in trial")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    } else if subscriptionManager.isInGracePeriod {
                        Text("Grace Period")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AppTheme.playfulCoral)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
            }
            .padding(16)
            .background(AppTheme.card(for: colorScheme))
            .cornerRadius(16)
            .shadow(color: AppTheme.cardShadow(for: colorScheme), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
    }
}


struct SettingsTabView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsTabView()
            .environmentObject(SessionManager.shared)
            .environmentObject(SubscriptionManager.shared)
    }
}
