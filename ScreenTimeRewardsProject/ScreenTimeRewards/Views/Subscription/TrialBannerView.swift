import SwiftUI

struct TrialBannerView: View {
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @State private var showPaywall = false

    var body: some View {
        if subscriptionManager.isInTrial {
            trialBanner
        } else if subscriptionManager.isInGracePeriod {
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
                    if let days = subscriptionManager.trialDaysRemaining {
                        Text("\(days) days remaining")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Text("Subscribe")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppTheme.vibrantTeal)
            }
            .padding(12)
            .background(AppTheme.sunnyYellow.opacity(0.1))
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
                    if let days = subscriptionManager.graceDaysRemaining {
                        Text("\(days) days to renew")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
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
            .background(AppTheme.playfulCoral.opacity(0.1))
            .cornerRadius(12)
            .padding(.horizontal)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showPaywall) {
            SubscriptionPaywallView()
        }
    }
}
