import SwiftUI

struct SubscriptionManagementView: View {
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var showPaywall = false

    var body: some View {
        List {
            currentStatusSection

            if subscriptionManager.isInTrial {
                trialSection
            }

            if subscriptionManager.isInGracePeriod {
                graceSection
            }

            if subscriptionManager.hasAccess {
                benefitsSection
            }

            upgradeSection
            managementSection
        }
        .navigationTitle("Subscription")
        .sheet(isPresented: $showPaywall) {
            SubscriptionPaywallView()
        }
    }
}

// MARK: - Sections

private extension SubscriptionManagementView {
    var currentStatusSection: some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(subscriptionManager.currentTierName)
                        .font(.system(size: 18, weight: .bold))
                    Text(subscriptionManager.currentStatus.displayText)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: tierIcon)
                    .font(.system(size: 40))
                    .foregroundColor(tierColor)
            }
            .padding(.vertical, 8)
        }
    }

    var trialSection: some View {
        Section {
            if let daysRemaining = subscriptionManager.trialDaysRemaining {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(daysRemaining) days remaining")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Free trial ends on \(formattedTrialEndDate)")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                } icon: {
                    Image(systemName: "clock.fill")
                        .foregroundColor(AppTheme.sunnyYellow)
                }
            }
        } header: {
            Text("Free Trial")
        }
    }

    var graceSection: some View {
        Section {
            if let daysRemaining = subscriptionManager.graceDaysRemaining {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(daysRemaining) days to renew")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(AppTheme.playfulCoral)
                        Text("Subscribe now to continue using the app")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(AppTheme.playfulCoral)
                }
            }
        } header: {
            Text("Grace Period")
        }
    }

    var benefitsSection: some View {
        Section {
            ForEach(subscriptionManager.currentTier.features, id: \.self) { feature in
                Label(feature, systemImage: "checkmark.circle.fill")
                    .foregroundColor(AppTheme.vibrantTeal)
            }
        } header: {
            Text("Your Benefits")
        }
    }

    var upgradeSection: some View {
        Section {
            if subscriptionManager.currentTier == .individual {
                Button {
                    showPaywall = true
                } label: {
                    Label("Upgrade to Family", systemImage: "arrow.up.circle.fill")
                        .foregroundColor(AppTheme.vibrantTeal)
                }
            } else if subscriptionManager.currentTier == .free {
                Button {
                    showPaywall = true
                } label: {
                    Label("Subscribe Now", systemImage: "crown.fill")
                        .foregroundColor(AppTheme.vibrantTeal)
                }
            }
        }
    }

    var managementSection: some View {
        Section {
            Link(destination: URL(string: "https://apps.apple.com/account/subscriptions")!) {
                Label("Manage in App Store", systemImage: "arrow.up.forward.app")
            }

            Button {
                Task {
                    try? await subscriptionManager.restorePurchases()
                }
            } label: {
                Label("Restore Purchases", systemImage: "arrow.clockwise")
            }
        } header: {
            Text("Management")
        }
    }
}

// MARK: - Helpers

private extension SubscriptionManagementView {
    var tierIcon: String {
        switch subscriptionManager.currentTier {
        case .free: return "hourglass"
        case .individual: return "person.fill"
        case .family: return "person.3.fill"
        }
    }

    var tierColor: Color {
        switch subscriptionManager.currentTier {
        case .free: return .secondary
        case .individual: return AppTheme.vibrantTeal
        case .family: return AppTheme.sunnyYellow
        }
    }

    var formattedTrialEndDate: String {
        guard let trialEnd = subscriptionManager.subscription?.trialEndDate else {
            return "Unknown"
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: trialEnd)
    }
}
