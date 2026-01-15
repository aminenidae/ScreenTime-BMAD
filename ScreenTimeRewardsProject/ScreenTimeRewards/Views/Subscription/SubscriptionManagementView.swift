import SwiftUI

struct SubscriptionManagementView: View {
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var showPaywall = false
    @State private var isRestoring = false
    @State private var restoreError: String?
    @State private var showRestoreAlert = false

    var body: some View {
        ZStack(alignment: .top) {
            // Background
            AppTheme.background(for: colorScheme)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                headerView

                ScrollView {
                    VStack(spacing: 20) {
                        currentStatusCard

                        if subscriptionManager.isInTrial {
                            trialCard
                        }

                        if subscriptionManager.isInGracePeriod {
                            graceCard
                        }

                        if subscriptionManager.hasAccess {
                            benefitsCard
                        }

                        upgradeCard
                        managementCard
                    }
                    .padding(20)
                }
            }
        }
        .sheet(isPresented: $showPaywall) {
            SubscriptionPaywallView()
        }
        .alert("Restore Failed", isPresented: $showRestoreAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(restoreError ?? "Unable to restore purchases. Please try again later.")
        }
    }
}

// MARK: - Components

private extension SubscriptionManagementView {
    var headerView: some View {
        ZStack {
            HStack {
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 30))
                        .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.3))
                }
            }

            Text("SUBSCRIPTION")
                .font(.system(size: 18, weight: .bold))
                .tracking(2)
                .foregroundColor(AppTheme.brandedText(for: colorScheme))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(AppTheme.background(for: colorScheme))
    }

    var currentStatusCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("CURRENT PLAN")
                        .font(.system(size: 12, weight: .bold))
                        .tracking(1)
                        .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.6))
                    
                    Text(subscriptionManager.currentTierName)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(AppTheme.brandedText(for: colorScheme))
                }
                
                Spacer()
                
                ZStack {
                    Circle()
                        .fill(tierColor.opacity(0.15))
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: tierIcon)
                        .font(.system(size: 24))
                        .foregroundColor(tierColor)
                }
            }
            
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(AppTheme.vibrantTeal)
                    .font(.system(size: 14))
                
                Text(subscriptionManager.currentStatus.displayText)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.8))
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(AppTheme.card(for: colorScheme))
                .shadow(color: AppTheme.cardShadow(for: colorScheme), radius: 10, x: 0, y: 4)
        )
    }

    var trialCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "clock.fill")
                    .foregroundColor(AppTheme.sunnyYellow)
                Text("FREE TRIAL")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(AppTheme.sunnyYellow)
                    .tracking(1)
            }
            
            if let daysRemaining = subscriptionManager.trialDaysRemaining {
                Text("\(daysRemaining) days remaining")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(AppTheme.brandedText(for: colorScheme))
                
                Text("Ends on \(formattedTrialEndDate)")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.6))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(AppTheme.sunnyYellow.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(AppTheme.sunnyYellow.opacity(0.3), lineWidth: 1)
                )
        )
    }

    var graceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(AppTheme.playfulCoral)
                Text("ACTION REQUIRED")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(AppTheme.playfulCoral)
                    .tracking(1)
            }
            
            if let daysRemaining = subscriptionManager.graceDaysRemaining {
                Text("\(daysRemaining) days to renew")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(AppTheme.brandedText(for: colorScheme))
                
                Text("Subscribe now to keep using the app")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.6))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(AppTheme.playfulCoral.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(AppTheme.playfulCoral.opacity(0.3), lineWidth: 1)
                )
        )
    }

    var benefitsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("YOUR BENEFITS")
                .font(.system(size: 12, weight: .bold))
                .tracking(1)
                .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.6))
            
            VStack(spacing: 12) {
                ForEach(subscriptionManager.currentTier.features, id: \.self) { feature in
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(AppTheme.vibrantTeal)
                            .font(.system(size: 16))
                        
                        Text(feature)
                            .font(.system(size: 15))
                            .foregroundColor(AppTheme.brandedText(for: colorScheme))
                        
                        Spacer()
                    }
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(AppTheme.card(for: colorScheme))
        )
    }

    @ViewBuilder
    var upgradeCard: some View {
        if subscriptionManager.currentTier == .individual {
            Button {
                showPaywall = true
            } label: {
                HStack {
                    Label("Upgrade to Family", systemImage: "person.3.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(AppTheme.lightCream)
                    Spacer()
                    Image(systemName: "arrow.up.circle.fill")
                        .foregroundColor(AppTheme.lightCream)
                }
                .padding()
                .background(AppTheme.vibrantTeal)
                .cornerRadius(16)
            }
        } else if subscriptionManager.currentTier == .trial {
            Button {
                showPaywall = true
            } label: {
                HStack {
                    Label("Unlock Premium", systemImage: "crown.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(AppTheme.lightCream)
                    Spacer()
                    Image(systemName: "arrow.right")
                        .foregroundColor(AppTheme.lightCream)
                }
                .padding()
                .background(AppTheme.vibrantTeal)
                .cornerRadius(16)
                .shadow(color: AppTheme.vibrantTeal.opacity(0.3), radius: 8, x: 0, y: 4)
            }
        }
    }

    var managementCard: some View {
        VStack(spacing: 0) {
            Link(destination: URL(string: "https://apps.apple.com/account/subscriptions")!) {
                HStack {
                    Text("Manage in App Store")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(AppTheme.brandedText(for: colorScheme))
                    Spacer()
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.4))
                }
                .padding(16)
            }
            
            Divider()
                .background(AppTheme.brandedText(for: colorScheme).opacity(0.1))
            
            Button {
                Task {
                    isRestoring = true
                    do {
                        try await subscriptionManager.restorePurchases()
                        restoreError = nil
                    } catch {
                        restoreError = error.localizedDescription
                        showRestoreAlert = true
                        #if DEBUG
                        print("[SubscriptionManagementView] Restore failed: \(error)")
                        #endif
                    }
                    isRestoring = false
                }
            } label: {
                HStack {
                    Text(isRestoring ? "Restoring..." : "Restore Purchases")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(AppTheme.brandedText(for: colorScheme))
                    Spacer()
                    if isRestoring {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.4))
                    }
                }
                .padding(16)
            }
            .disabled(isRestoring)
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(AppTheme.card(for: colorScheme))
        )
    }
}

// MARK: - Helpers

private extension SubscriptionManagementView {
    var tierIcon: String {
        switch subscriptionManager.currentTier {
        case .trial: return "hourglass"
        case .solo: return "iphone"
        case .individual: return "person.fill"
        case .family: return "person.3.fill"
        }
    }

    var tierColor: Color {
        switch subscriptionManager.currentTier {
        case .trial: return AppTheme.brandedText(for: colorScheme).opacity(0.6)
        case .solo: return AppTheme.vibrantTeal.opacity(0.8)
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
