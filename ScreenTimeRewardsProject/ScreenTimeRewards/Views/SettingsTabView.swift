import SwiftUI
import UIKit

struct SettingsTabView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @State private var showingPairingView = false
    @State private var showingSubscriptionManagement = false
    @State private var showResetConfirmation = false
    @StateObject private var pairingService = DevicePairingService.shared
    @StateObject private var modeManager = DeviceModeManager.shared
    @Environment(\.colorScheme) var colorScheme

    // Design colors matching ModeSelectionView
    private let creamBackground = Color(red: 0.96, green: 0.95, blue: 0.88)
    private let tealColor = Color(red: 0.0, green: 0.45, blue: 0.45)
    private let lightCoral = Color(red: 0.98, green: 0.50, blue: 0.45)
    private let accentYellow = Color(red: 0.98, green: 0.80, blue: 0.30)
    private let errorRed = Color(red: 0.9, green: 0.3, blue: 0.25)

    var body: some View {
        ZStack(alignment: .bottom) {
            // Background
            creamBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Custom header
                VStack(spacing: 0) {
                    HStack {
                        Button(action: {
                            sessionManager.exitToSelection()
                        }) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(tealColor)
                                .frame(width: 44, height: 44)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(tealColor.opacity(0.1))
                                )
                        }

                        Spacer()

                        Text("SETTINGS")
                            .font(.system(size: 18, weight: .bold))
                            .tracking(2)
                            .foregroundColor(tealColor)

                        Spacer()

                        // Invisible spacer for balance
                        Color.clear
                            .frame(width: 44, height: 44)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 12)

                    Rectangle()
                        .fill(tealColor.opacity(0.15))
                        .frame(height: 1)
                }
                .background(creamBackground)

                ScrollView {
                    VStack(spacing: 24) {
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
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(tealColor.opacity(0.5))
                                .padding(.horizontal, 4)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            // Hidden report view to ensure extension is triggered from this screen
            HiddenUsageReportView()
                .allowsHitTesting(false)
        }
        .sheet(isPresented: $showingPairingView) {
            ChildPairingView()
        }
        .sheet(isPresented: $showingSubscriptionManagement) {
            SubscriptionManagementView()
        }
    }
}

// MARK: - Helper Functions

private extension SettingsTabView {
    func settingsSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .tracking(1.5)
                .foregroundColor(tealColor.opacity(0.6))
                .padding(.horizontal, 4)

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
                // Icon container
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(lightCoral.opacity(0.15))
                        .frame(width: 44, height: 44)

                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 20))
                        .foregroundColor(lightCoral)
                }

                // Label
                Text("Exit Parent Mode")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(tealColor)

                Spacer()

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(tealColor.opacity(0.4))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(tealColor.opacity(0.1), lineWidth: 1)
                    )
            )
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
                // Icon container
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(tealColor.opacity(0.15))
                        .frame(width: 44, height: 44)

                    Image(systemName: "ipad.and.iphone")
                        .font(.system(size: 20))
                        .foregroundColor(tealColor)
                }

                // Status content
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pairing Status")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(tealColor)

                    if pairingService.isPaired() {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(tealColor)

                            Text("Paired with Child's iPad")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(tealColor.opacity(0.7))
                        }
                    } else {
                        Text("Not paired")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(tealColor.opacity(0.5))
                    }
                }

                Spacer()

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(tealColor.opacity(0.4))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(tealColor.opacity(0.1), lineWidth: 1)
                    )
            )
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
                    RoundedRectangle(cornerRadius: 12)
                        .fill(errorRed.opacity(0.15))
                        .frame(width: 44, height: 44)

                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 20))
                        .foregroundColor(errorRed)
                }

                // Label
                Text("Reset This Device")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(errorRed)

                Spacer()

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(tealColor.opacity(0.4))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(errorRed.opacity(0.2), lineWidth: 1)
                    )
            )
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
        Button(action: {
            showingSubscriptionManagement = true
        }) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(accentYellow.opacity(0.2))
                        .frame(width: 44, height: 44)

                    Image(systemName: "crown.fill")
                        .font(.system(size: 20))
                        .foregroundColor(accentYellow)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Manage Subscription")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(tealColor)

                    Text(subscriptionManager.currentTierName)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(accentYellow)

                    if subscriptionManager.isInTrial, let days = subscriptionManager.trialDaysRemaining {
                        Text("\(days) days left in trial")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(tealColor.opacity(0.5))
                    } else if subscriptionManager.isInGracePeriod {
                        Text("Grace Period")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(lightCoral)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(tealColor.opacity(0.4))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(accentYellow.opacity(0.2), lineWidth: 1)
                    )
            )
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
