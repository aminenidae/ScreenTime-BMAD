import SwiftUI
import UIKit

struct SettingsTabView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @State private var showingPairingView = false
    @State private var showingSubscriptionManagement = false
    @State private var showResetConfirmation = false
    @State private var isManualSyncing = false
    @StateObject private var pairingService = DevicePairingService.shared
    @StateObject private var modeManager = DeviceModeManager.shared
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack(alignment: .bottom) {
            // Background
            AppTheme.background(for: colorScheme)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                TabTopBar(title: "Settings", style: topBarStyle) {
                    sessionManager.exitToSelection()
                }

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

                        // Diagnostics Section
                        settingsSection(title: "DIAGNOSTICS") {
                            usageAccuracyRow
                            manualSyncRow
                            extensionDiagnosticsRow
                            diagnosticsRow
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
                    .padding(.top, 4)
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
        Button(action: {
            showingSubscriptionManagement = true
        }) {
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

    @ViewBuilder
    var manualSyncRow: some View {
        #if DEBUG
        let _ = NSLog("[SettingsTabView] 🏗️ Building manualSyncRow, isManualSyncing=\(isManualSyncing)")
        #endif

        Button(action: triggerManualSync) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: [AppTheme.vibrantTeal.opacity(0.15), AppTheme.playfulCoral.opacity(0.15)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 40, height: 40)

                    if isManualSyncing {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(AppTheme.vibrantTeal)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(AppTheme.vibrantTeal)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Manual Usage Sync")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                    Text("Update progress beyond 4-minute limit")
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
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
        .contentShape(Rectangle())
        .buttonStyle(.plain)
        .disabled(isManualSyncing)
    }

    var extensionDiagnosticsRow: some View {
        NavigationLink {
            ExtensionDiagnosticsView()
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: [Color.red.opacity(0.15), Color.orange.opacity(0.15)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 40, height: 40)

                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.orange)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Extension Diagnostics")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                    Text("Debug extension execution and errors")
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
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

    var diagnosticsRow: some View {
        NavigationLink {
            TrackingHealthView()
        } label: {
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

                    Image(systemName: "heart.text.square.fill")
                        .font(.system(size: 20))
                        .foregroundColor(AppTheme.vibrantTeal)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Tracking Health")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                    Text("View diagnostics and troubleshoot issues")
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
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

    var usageAccuracyRow: some View {
        NavigationLink {
            UsageAccuracyDiagnosticsView()
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: [Color.green.opacity(0.15), AppTheme.vibrantTeal.opacity(0.15)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 40, height: 40)

                    Image(systemName: "checkmark.circle.badge.questionmark.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.green)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Usage Accuracy")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                    Text("Validate tracking and detect iOS bugs")
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
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

// MARK: - Actions
private extension SettingsTabView {
    func triggerManualSync() {
        NSLog("[SettingsTabView] 🔘 Manual Sync button CLICKED")
        print("[SettingsTabView] 🔘 Manual Sync button CLICKED")

        isManualSyncing = true

        // Haptic feedback for reliability confirmation
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        ScreenTimeService.shared.requestUsageReportRefresh()

        // Give the extension time to respond before reading the snapshot
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            ScreenTimeService.shared.syncFromReportSnapshot()
            isManualSyncing = false
            NSLog("[SettingsTabView] ✅ Manual sync flow completed")
        }
    }
}

// MARK: - Design Tokens
private extension SettingsTabView {
    var topBarStyle: TabTopBarStyle {
        TabTopBarStyle(
            background: AppTheme.background(for: colorScheme),
            titleColor: AppTheme.textPrimary(for: colorScheme),
            iconColor: AppTheme.vibrantTeal,
            iconBackground: AppTheme.card(for: colorScheme),
            dividerColor: Color.black.opacity(colorScheme == .dark ? 0.15 : 0.06)
        )
    }
}

struct SettingsTabView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsTabView()
            .environmentObject(SessionManager.shared)
            .environmentObject(SubscriptionManager.shared)
    }
}
