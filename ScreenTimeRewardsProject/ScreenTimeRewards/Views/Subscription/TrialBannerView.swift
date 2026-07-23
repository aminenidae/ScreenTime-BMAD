import SwiftUI

/// Ongoing free-trial (or grace) status banner with a tap-through to the paywall.
///
/// Reads the correct source per device mode: on a **child** device the trial lives in
/// `ChildBackgroundSyncService` (set by `startFamilyTrial()` for a solo device, or
/// synced from the paired parent) — `SubscriptionManager` is NOT the authority there,
/// which is why an earlier SubscriptionManager-only version showed nothing on the child
/// path. On a **parent** device it's `SubscriptionManager`.
struct TrialBannerView: View {
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @StateObject private var childSync = ChildBackgroundSyncService.shared
    @StateObject private var modeManager = DeviceModeManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var showPaywall = false

    private var isChild: Bool { modeManager.isChildDevice }

    private var inTrial: Bool {
        isChild ? childSync.parentSubscriptionStatus == .trial : subscriptionManager.isInTrial
    }
    private var inGrace: Bool {
        isChild ? childSync.parentSubscriptionStatus == .grace : subscriptionManager.isInGracePeriod
    }
    private var trialDays: Int? {
        isChild ? childSync.trialDaysRemaining : subscriptionManager.trialDaysRemaining
    }
    private var graceDays: Int? {
        isChild ? childSync.trialDaysRemaining : subscriptionManager.graceDaysRemaining
    }

    var body: some View {
        if inTrial {
            trialBanner
        } else if inGrace {
            graceBanner
        }
    }
}

private extension TrialBannerView {
    var trialBanner: some View {
        Button {
            showPaywall = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "clock.fill")
                    .foregroundColor(AppTheme.sunnyYellow)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Free Trial Active")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                    if let days = trialDays {
                        Text(days == 1 ? "1 day remaining" : "\(days) days remaining")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    }
                }

                Spacer()

                Text("Subscribe")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppTheme.accentText(for: colorScheme))
            }
            .padding(12)
            .background(AppTheme.sunnyYellow.opacity(0.15))
            .cornerRadius(12)
            .padding(.horizontal)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showPaywall) {
            SubscriptionPaywallView()
        }
    }

    var graceBanner: some View {
        Button {
            showPaywall = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(AppTheme.playfulCoral)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Subscription Expired")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                    if let days = graceDays {
                        Text(days == 1 ? "1 day to renew" : "\(days) days to renew")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    }
                }

                Spacer()

                Text("Renew Now")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(AppTheme.playfulCoral)
                    .cornerRadius(8)
            }
            .padding(12)
            .background(AppTheme.playfulCoral.opacity(0.12))
            .cornerRadius(12)
            .padding(.horizontal)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showPaywall) {
            SubscriptionPaywallView()
        }
    }
}
