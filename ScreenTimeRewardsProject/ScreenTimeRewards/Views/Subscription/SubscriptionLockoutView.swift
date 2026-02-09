import SwiftUI

struct SubscriptionLockoutView: View {
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var modeManager = DeviceModeManager.shared
    @State private var showPaywall = false

    var body: some View {
        ZStack {
            AppTheme.background(for: colorScheme)
                .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                Image(systemName: "lock.fill")
                    .font(.system(size: 100))
                    .foregroundColor(.secondary)

                VStack(spacing: 16) {
                    Text("Subscription Required")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                    Text("Your free trial has ended. Subscribe to continue using ScreenTime Rewards.")
                        .font(.system(size: 16))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Button {
                    showPaywall = true
                } label: {
                    Text("View Plans")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(AppTheme.vibrantTeal)
                        .cornerRadius(12)
                        .padding(.horizontal, 32)
                }

                Spacer()

                Text("You can still review your data from Settings.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                #if DEBUG
                // Debug bypass button for testing
                Button {
                    Task {
                        await activateDevSubscription()
                    }
                } label: {
                    Text("🔓 DEV: Bypass Subscription")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.orange)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(8)
                }
                .padding(.bottom, 16)
                #endif
            }
        }
        .sheet(isPresented: $showPaywall) {
            if modeManager.currentMode == .childDevice {
                // Child device: Solo plan only
                ChildSubscriptionView()
                    .environmentObject(subscriptionManager)
            } else {
                // Parent device: Individual + Family plans
                SubscriptionPaywallView()
                    .environmentObject(subscriptionManager)
            }
        }
    }

    #if DEBUG
    /// Activate dev subscription and restart monitoring (DEBUG only)
    private func activateDevSubscription() async {
        // Choose tier based on device mode
        let tier: SubscriptionTier = modeManager.currentMode == .childDevice ? .solo : .individual

        // Activate the dev subscription
        subscriptionManager.activateDevSubscription(tier: tier)

        // Restart monitoring services for child device
        if modeManager.currentMode == .childDevice {
            // Restart DeviceActivity monitoring with fresh thresholds
            await ScreenTimeService.shared.restartMonitoring(reason: "dev subscription bypass", force: true)

            BlockingCoordinator.shared.startPeriodicRefresh()
            let currentTokens = BlockingCoordinator.shared.currentRewardTokens
            if !currentTokens.isEmpty {
                ScreenTimeService.shared.syncRewardAppShields(currentRewardTokens: currentTokens)
            }
            ChildBackgroundSyncService.shared.scheduleNextUsageUpload()
            ChildBackgroundSyncService.shared.scheduleNextConfigCheck()
        }

        print("[SubscriptionLockoutView] 🔓 DEV subscription activated: \(tier.displayName)")
    }
    #endif
}
