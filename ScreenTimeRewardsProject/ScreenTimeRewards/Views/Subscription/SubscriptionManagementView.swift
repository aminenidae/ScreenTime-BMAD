import SwiftUI
import StoreKit
import RevenueCatUI
struct SubscriptionManagementView: View {
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @EnvironmentObject var deviceModeManager: DeviceModeManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var showCustomerCenter = false
    @State private var showPaywall = false
    @State private var paywallInitialTier: SubscriptionTier = .individual
    @State private var showChildPaywall = false
    @State private var showPairingView = false
    @State private var isRestoring = false
    @State private var restoreError: String?
    @State private var showRestoreAlert = false

    // Excess children warning state
    @State private var hasExcessChildren = false
    @State private var pairedChildCount = 0
    @State private var childLimit = 0
    @State private var excessCount = 0

    var body: some View {
        ZStack(alignment: .top) {
            // Background
            AppTheme.background(for: colorScheme)
                .ignoresSafeArea()

            if deviceModeManager.currentMode == .childDevice {
                childDeviceContent
            } else {
                parentDeviceContent
            }
        }
        .sheet(isPresented: $showPaywall) {
            SubscriptionPaywallView(initialTier: paywallInitialTier)
        }
        .sheet(isPresented: $showChildPaywall) {
            ChildSubscriptionView()
                .environmentObject(subscriptionManager)
        }
        .sheet(isPresented: $showPairingView) {
            ChildPairingView()
        }
        .alert("Restore Failed", isPresented: $showRestoreAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(restoreError ?? "Unable to restore purchases. Please try again later.")
        }
    }

    // MARK: - Child Device Content

    @ViewBuilder
    private var childDeviceContent: some View {
        if subscriptionManager.isParentPairedSubscription {
            // Child is paired with parent - show "Managed by Parent" status only
            VStack(spacing: 0) {
                headerView
                ScrollView {
                    VStack(spacing: 20) {
                        managedByParentCard
                    }
                    .padding(20)
                }
            }
        } else if subscriptionManager.currentTier == .solo {
            // Child has Solo subscription - show management with parent pairing option
            VStack(spacing: 0) {
                headerView
                ScrollView {
                    VStack(spacing: 20) {
                        currentStatusCard

                        if subscriptionManager.isInGracePeriod {
                            graceCard
                        }

                        if subscriptionManager.hasAccess {
                            benefitsCard
                        }

                        managementCard

                        // Upgrade path: connect with parent for remote monitoring
                        connectWithParentUpgradeCard
                    }
                    .padding(20)
                }
            }
        } else {
            // Child is in trial - show ChildSubscriptionView
            ChildSubscriptionView()
        }
    }

    // MARK: - Parent Device Content (unchanged from original)

    private var parentDeviceContent: some View {
        VStack(spacing: 0) {
            headerView

            ScrollView {
                VStack(spacing: 20) {
                    // Show warning if too many paired children for current tier
                    if hasExcessChildren {
                        excessChildrenWarningCard
                    }

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
        .task {
            // Check for excess paired children on appear
            let result = await subscriptionManager.checkExcessPairedChildren()
            hasExcessChildren = result.hasExcess
            pairedChildCount = result.currentCount
            childLimit = result.limit
            excessCount = result.excessCount
        }
    }

    // MARK: - Connect with Parent Upgrade Card (for Solo users)

    private var connectWithParentUpgradeCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "person.2.fill")
                    .foregroundColor(AppTheme.vibrantTeal)
                Text("WANT REMOTE MONITORING?")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(AppTheme.vibrantTeal)
                    .tracking(1)
            }

            Text("Connect with a parent's Individual or Family subscription to unlock remote monitoring features.")
                .font(.system(size: 14))
                .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.7))

            Button {
                showPairingView = true
            } label: {
                HStack {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 16))
                    Text("Connect with Parent")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(AppTheme.vibrantTeal)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(AppTheme.vibrantTeal, lineWidth: 2)
                )
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(AppTheme.vibrantTeal.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(AppTheme.vibrantTeal.opacity(0.2), lineWidth: 1)
                )
        )
    }

    // MARK: - Excess Children Warning Card

    private var excessChildrenWarningCard: some View {
        VStack(spacing: 16) {
            // Warning icon
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundColor(.orange)

            // Title
            Text("Too Many Paired Devices")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(AppTheme.brandedText(for: colorScheme))

            // Description
            Text("Your \(subscriptionManager.currentTier.displayName) plan supports up to \(childLimit) child device\(childLimit == 1 ? "" : "s"), but you have \(pairedChildCount) paired. Please unpair \(excessCount) device\(excessCount == 1 ? "" : "s") or upgrade your plan.")
                .font(.system(size: 14))
                .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.7))
                .multilineTextAlignment(.center)

            // Action buttons
            VStack(spacing: 12) {
                // Manage Devices button
                NavigationLink {
                    LinkedDevicesView()
                } label: {
                    HStack {
                        Image(systemName: "person.2")
                            .font(.system(size: 16))
                        Text("Manage Devices")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.orange)
                    .cornerRadius(12)
                }

                // Upgrade button (if not already on Family)
                if subscriptionManager.currentTier != .family {
                    Button {
                        paywallInitialTier = .family
                        showPaywall = true
                    } label: {
                        HStack {
                            Image(systemName: "arrow.up.circle")
                                .font(.system(size: 16))
                            Text("Upgrade Plan")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundColor(.orange)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.orange, lineWidth: 2)
                        )
                    }
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.orange.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                )
        )
    }

    // MARK: - Managed by Parent Card

    private var managedByParentCard: some View {
        VStack(spacing: 20) {
            // Icon
            ZStack {
                Circle()
                    .fill(AppTheme.vibrantTeal.opacity(0.15))
                    .frame(width: 80, height: 80)

                Image(systemName: "person.2.fill")
                    .font(.system(size: 36))
                    .foregroundColor(AppTheme.vibrantTeal)
            }

            // Title and description
            VStack(spacing: 8) {
                Text("Managed by Parent")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(AppTheme.brandedText(for: colorScheme))

                Text("Your subscription is managed by your parent's device. Contact them for any changes.")
                    .font(.system(size: 15))
                    .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.7))
                    .multilineTextAlignment(.center)
            }

            // Current plan badge
            HStack(spacing: 8) {
                Image(systemName: "crown.fill")
                    .foregroundColor(AppTheme.sunnyYellow)
                    .font(.system(size: 14))

                Text(subscriptionManager.currentTierName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(AppTheme.sunnyYellow)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(AppTheme.sunnyYellow.opacity(0.15))
            )

            // Status
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(AppTheme.vibrantTeal)
                    .font(.system(size: 14))

                Text(subscriptionManager.currentStatus.displayText)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.8))
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(AppTheme.card(for: colorScheme))
                .shadow(color: AppTheme.cardShadow(for: colorScheme), radius: 10, x: 0, y: 4)
        )
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
                paywallInitialTier = .family
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
                paywallInitialTier = .individual
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
            Button {
                showCustomerCenter = true
            } label: {
                HStack {
                    Text("Manage Subscription")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(AppTheme.brandedText(for: colorScheme))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.brandedText(for: colorScheme).opacity(0.4))
                }
                .padding(16)
            }
            .sheet(isPresented: $showCustomerCenter) {
                CustomerCenterView()
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
            return String(localized: "Unknown")
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: trialEnd)
    }
}
